--[[
Copyright (c) 2018-2025 FileAgo Software Pvt Ltd. All Rights Reserved.

This software is proprietary and confidential.
Unauthorized copying of this file, via any medium, is strictly prohibited.

For license information, see the LICENSE.txt file in the root directory of
this project.
--]]

-- icap_streamer.lua: ICAP streamer that works with both buffer types
-- This version ensures compatibility with both original buffer_manager and enhanced buffer_manager

local _M = {}

-- ICAP protocol constants
local ICAP_VERSION = "ICAP/1.0"
local CHUNK_SIZE = 128 * 1024  -- 128KB chunks for streaming

-- Detect which buffer manager is being used and create appropriate reader
local function create_compatible_reader(buffer, start_offset)
    local buffer_manager = require "buffer_manager"
    return buffer_manager.create_reader_iterator(buffer, start_offset)
end

-- Get preview data with compatibility
local function get_compatible_preview_data(buffer, preview_size)
    local buffer_manager = require "buffer_manager"
    return buffer_manager.get_preview_data(buffer, preview_size)
end

-- Create ICAP preview request payload
function _M.create_icap_preview_request(buffer, http_request_line, config)
    if not buffer or not http_request_line or not config then
        return nil, "invalid_parameters"
    end
    
    local preview_data = get_compatible_preview_data(buffer, config.preview_size)
    
    -- Build HTTP request headers
    local http_req_line = http_request_line .. "\r\n" ..
                         "Host: example.com\r\n" ..
                         "Content-Length: " .. tostring(buffer.total_size) .. "\r\n\r\n"
    local req_hdr_len = #http_req_line
    
    -- Build ICAP headers
    local icap_headers = {
        "REQMOD " .. config.icap_url .. " " .. ICAP_VERSION,
        "Host: " .. config.icap_server_host,
        "Allow: 204",
        "Preview: " .. tostring(config.preview_size),
        "Encapsulated: req-hdr=0, req-body=" .. tostring(req_hdr_len),
        ""
    }
    
    -- Construct complete ICAP request
    local icap_request = table.concat(icap_headers, "\r\n") .. "\r\n" ..
                        http_req_line ..
                        string.format("%X\r\n", #preview_data) ..
                        preview_data .. "\r\n" ..
                        "0\r\n\r\n"
    
    return icap_request
end

-- Send ICAP preview request non-blocking
function _M.send_icap_preview(sock, buffer, http_request_line, config, write_to_log)
    if not sock or not buffer or not config then
        return nil, "invalid_parameters"
    end
    
    -- Create preview request
    local preview_request, err = _M.create_icap_preview_request(buffer, http_request_line, config)
    if not preview_request then
        return nil, "preview_creation_failed: " .. (err or "unknown")
    end
    
    write_to_log(ngx.INFO, "Sending ICAP preview request, preview size: " .. config.preview_size)
    
    -- Send preview request
    local bytes_sent, send_err = sock:send(preview_request)
    if not bytes_sent then
        return nil, "preview_send_failed: " .. (send_err or "unknown")
    end
    
    write_to_log(ngx.INFO, "ICAP preview sent successfully, bytes: " .. bytes_sent)
    return bytes_sent
end

-- Stream remaining file body to ICAP server (fixed version)
function _M.stream_full_body_to_icap(sock, buffer, config, write_to_log)
    if not sock or not buffer or not config then
        return nil, "invalid_parameters"
    end
    
    local remaining_size = buffer.total_size - config.preview_size
    
    if remaining_size <= 0 then
        write_to_log(ngx.INFO, "No remaining body to send (file smaller than preview)")
        -- Still need to send the termination sequence for small files
        local ok, err = sock:send("0; ieof\r\n\r\n")
        if not ok then
            return nil, "termination_send_failed: " .. (err or "unknown")
        end
        return true
    end
    
    write_to_log(ngx.INFO, "Streaming remaining body to ICAP, size: " .. remaining_size)
    
    -- Send remaining body size header (exactly like original)
    local ok, err = sock:send(string.format("%X\r\n", remaining_size))
    if not ok then
        return nil, "size_header_send_failed: " .. (err or "unknown")
    end
    
    -- Create compatible reader starting after preview
    local reader = create_compatible_reader(buffer, config.preview_size)
    
    local total_sent = 0
    local chunk_count = 0
    
    -- Stream data in chunks (exactly like original)
    while true do
        local chunk = reader(CHUNK_SIZE)
        if not chunk then
            -- Send final CRLF after data (like original line 281)
            local ok, err = sock:send("\r\n")
            if not ok then
                return nil, "final_crlf_send_failed: " .. (err or "unknown")
            end
            break
        end
        
        local ok, err = sock:send(chunk)
        if not ok then
            return nil, "chunk_send_failed: " .. (err or "unknown")
        end
        
        total_sent = total_sent + #chunk
        chunk_count = chunk_count + 1
        
        -- Log progress for large files
        if chunk_count % 50 == 0 then  -- Every ~6.4MB
            write_to_log(ngx.INFO, string.format("ICAP streaming progress: %d/%d bytes (%d chunks)", 
                                                total_sent, remaining_size, chunk_count))
        end
    end
    
    -- Send final chunk markers (exactly like original line 288)
    local ok, err = sock:send("0; ieof\r\n\r\n")
    if not ok then
        return nil, "final_marker_send_failed: " .. (err or "unknown")
    end
    
    write_to_log(ngx.INFO, string.format("ICAP body streaming completed: %d bytes in %d chunks", 
                                        total_sent, chunk_count))
    return total_sent
end

-- Parse ICAP status line
function _M.parse_icap_status(status_line)
    if not status_line then
        return nil, "missing_status_line"
    end
    
    -- Parse "ICAP/1.0 204 No Content" format
    local version, code, message = status_line:match("^(ICAP/[%d%.]+)%s+(%d+)%s*(.*)")
    
    if not version or not code then
        return nil, "invalid_status_format"
    end
    
    return {
        version = version,
        code = tonumber(code),
        message = message or "",
        is_clean = (tonumber(code) == 204),
        needs_full_body = (tonumber(code) == 100),
        is_blocked = (tonumber(code) >= 400)
    }
end

-- Check if response indicates file size limit exceeded
function _M.is_max_filesize_exceeded(headers)
    if not headers then
        return false
    end
    
    local headers_str = table.concat(headers, " | ")
    return headers_str:find("Heuristics.Limits.Exceeded.MaxFileSize", 1, true) ~= nil
end

-- Complete ICAP scanning workflow (fixed to match original exactly)
function _M.scan_file_with_icap(sock, buffer, config, write_to_log)
    if not sock or not buffer or not config then
        return nil, "invalid_parameters"
    end
    
    local http_request_line = "POST / HTTP/1.1"
    
    -- Step 1: Send preview request
    local preview_result, preview_err = _M.send_icap_preview(sock, buffer, http_request_line, config, write_to_log)
    if not preview_result then
        return nil, "preview_failed: " .. (preview_err or "unknown")
    end
    
    -- Step 2: Read initial ICAP response status line
    local status_line, err = sock:receive("*l")
    if not status_line then
        write_to_log(ngx.ERR, "Failed to receive status: " .. (err or "unknown"))
        return nil, "status_read_failed: " .. (err or "unknown")
    end
    
    write_to_log(ngx.INFO, "ICAP server response: " .. status_line)
    
    -- Step 3: Parse status
    local status, status_err = _M.parse_icap_status(status_line)
    if not status then
        return nil, "status_parse_failed: " .. (status_err or "unknown")
    end
    
    -- Step 4: Handle different response types (exactly like original)
    if status_line:find("ICAP/1.0 204") then
        write_to_log(ngx.INFO, "File is clean (204)")
        return {
            result = "clean",
            status_code = 204,
            message = "File passed security scan"
        }
        
    elseif status_line:find("ICAP/1.0 100 Continue") then
        write_to_log(ngx.INFO, "Server requested full body after preview")
        write_to_log(ngx.INFO, "Sending full body chunk, size: " .. buffer.total_size)
        
        -- Set timeout
        sock:settimeout(config.socket_timeout)
        
        -- Send full body
        local body_result, body_err = _M.stream_full_body_to_icap(sock, buffer, config, write_to_log)
        if not body_result then
            return nil, "full_body_failed: " .. (body_err or "unknown")
        end
        
        -- CRITICAL: Follow exact protocol from original (lines 291-293)
        sock:settimeout(config.socket_timeout)
        sock:receive("*l")  -- Skip empty line (line 292 - ESSENTIAL!)
        
        -- Read final status line (line 293)
        local final_status_line, final_err = sock:receive("*l")
        if not final_status_line then
            write_to_log(ngx.ERR, "No status received after full body")
            return nil, "final_status_failed: " .. (final_err or "unknown")
        end
        
        write_to_log(ngx.INFO, "Final response after full body: " .. final_status_line)
        
        -- Check final status
        if final_status_line:find("ICAP/1.0 204") then
            write_to_log(ngx.INFO, "File is clean after full scan (204)")
            return {
                result = "clean",
                status_code = 204,
                message = "File passed full security scan"
            }
        else
            -- Try reading encapsulated HTTP response (like original lines 307-334)
            local icap_headers = {}
            while true do
                local header_line, err = sock:receive("*l")
                if not header_line then break end
                if header_line == "" then break end
                table.insert(icap_headers, header_line)
            end
            
            local headers_str = table.concat(icap_headers, " | ")
            write_to_log(ngx.ERR, "ICAP extra headers: " .. headers_str)
            
            local http_line, http_err = sock:receive("*l")
            if http_line then
                write_to_log(ngx.INFO, "Embedded HTTP response: " .. http_line)
                if http_line:find("403 Forbidden") then
                    local is_size_exceeded = _M.is_max_filesize_exceeded(icap_headers)
                    
                    return {
                        result = "blocked",
                        status_code = 403,
                        message = is_size_exceeded and "File size limit exceeded" or "File blocked by security scan",
                        is_size_limit = is_size_exceeded,
                        headers = icap_headers
                    }
                end
            else
                write_to_log(ngx.ERR, "No HTTP line received")
            end
            
            return {
                result = "blocked",
                status_code = 403,
                message = "File rejected by security scan",
                headers = icap_headers
            }
        end
        
    else
        write_to_log(ngx.ERR, "File rejected by ICAP server")
        return {
            result = "blocked",
            status_code = 403,
            message = "File immediately rejected by security scan"
        }
    end
end

-- Create ICAP connection with proper timeout handling
function _M.create_icap_connection(config, write_to_log)
    if not config then
        return nil, "missing_config"
    end
    
    write_to_log(ngx.INFO, "Connecting to ICAP server: " .. config.icap_server_host .. ":" .. config.icap_server_port)
    
    local sock = ngx.socket.tcp()
    if not sock then
        return nil, "socket_creation_failed"
    end
    
    -- Set connection timeout
    sock:settimeout(config.socket_timeout)
    
    -- Connect to ICAP server
    local ok, err = sock:connect(config.icap_server_host, config.icap_server_port)
    if not ok then
        return nil, "connection_failed: " .. (err or "unknown")
    end
    
    write_to_log(ngx.INFO, "ICAP connection established successfully")
    return sock
end

-- Close ICAP connection safely
function _M.close_icap_connection(sock, write_to_log)
    if not sock then
        return
    end
    
    local ok, err = sock:close()
    if not ok and write_to_log then
        write_to_log(ngx.WARN, "ICAP connection close warning: " .. (err or "unknown"))
    elseif write_to_log then
        write_to_log(ngx.INFO, "ICAP connection closed successfully")
    end
end

return _M