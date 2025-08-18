--[[
Copyright (c) 2018-2025 FileAgo Software Pvt Ltd. All Rights Reserved.

This software is proprietary and confidential.
Unauthorized copying of this file, via any medium, is strictly prohibited.

For license information, see the LICENSE.txt file in the root directory of
this project.
--]]

-- backend_streamer.lua: Backend streaming with support for enhanced buffer manager
-- Handles both memory mode and hybrid mode buffers for optimal performance

local _M = {}
local http = require "resty.http"
local url = require "socket.url"

-- Constants
local CHUNK_SIZE = 128 * 1024  -- 128KB chunks for streaming
local BOUNDARY_LENGTH = 16     -- Length of random boundary suffix

-- Generate random alphanumeric string for multipart boundary
local function generate_random_alphanumeric(length)
    local charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    local result = ""
    math.randomseed(ngx.time() + ngx.worker.pid())
    
    for i = 1, length do
        local rand_index = math.random(1, #charset)
        result = result .. charset:sub(rand_index, rand_index)
    end
    
    return result
end

-- Build proxy headers for backend request
function _M.build_proxy_headers(original_headers, config, boundary)
    if not original_headers or not config or not boundary then
        return nil, "invalid_parameters"
    end
    
    local new_headers = {}
    
    -- Copy original headers except those we need to override
    for k, v in pairs(original_headers) do
        local key_lower = k:lower()
        if key_lower ~= "host" and 
           key_lower ~= "content-length" and 
           key_lower ~= "content-type" and 
           key_lower ~= "transfer-encoding" then
            new_headers[k] = v
        end
    end
    
    -- Set host header based on backend configuration
    local host_header = config.backend_host
    if not ((config.backend_protocol == "http" and config.backend_port == 80) or
            (config.backend_protocol == "https" and config.backend_port == 443)) then
        host_header = host_header .. ":" .. config.backend_port
    end
    new_headers["Host"] = host_header
    
    -- Set proxy headers
    new_headers["X-Forwarded-For"] = ngx.var.remote_addr
    new_headers["X-Real-IP"] = ngx.var.remote_addr
    new_headers["X-Forwarded-Proto"] = ngx.var.scheme
    new_headers["X-Forwarded-Host"] = ngx.var.host
    new_headers["X-Forwarded-Port"] = ngx.var.server_port
    
    -- Set transfer encoding and content type
    new_headers["Transfer-Encoding"] = "chunked"
    new_headers["Content-Type"] = "multipart/form-data; boundary=" .. boundary
    
    return new_headers
end

-- Create enhanced multipart stream reader that works with both buffer modes
function _M.create_enhanced_multipart_stream_reader(buffer, boundary, multipart_headers)
    if not buffer or not boundary or not multipart_headers then
        return nil, "invalid_parameters"
    end
    
    local buffer_manager = require "buffer_manager"
    
    -- Prepare multipart components
    local preamble = "--" .. boundary .. "\r\n" .. 
                    table.concat(multipart_headers, "\r\n") .. "\r\n\r\n"
    local postamble = "\r\n--" .. boundary .. "--\r\n"
    
    local state = "preamble"
    local file_reader = buffer_manager.create_reader_iterator(buffer, 0)
    local bytes_sent = 0
    local total_bytes = buffer.total_size
    
    return function()
        if state == "preamble" then
            state = "file"
            return string.format("%X\r\n%s\r\n", #preamble, preamble)
            
        elseif state == "file" then
            local chunk = file_reader(CHUNK_SIZE)
            if chunk then
                bytes_sent = bytes_sent + #chunk
                
                -- Yield control periodically for large files
                if bytes_sent % (1024 * 1024) == 0 then  -- Every 1MB
                    ngx.sleep(0)
                end
                
                return string.format("%X\r\n%s\r\n", #chunk, chunk)
            else
                state = "postamble"
                return string.format("%X\r\n%s\r\n", #postamble, postamble)
            end
            
        elseif state == "postamble" then
            state = "done"
            return "0\r\n\r\n"  -- End of chunks
            
        else
            return nil  -- EOF
        end
    end
end

-- Parse backend URL and extract components
function _M.parse_backend_url(backend_url, config)
    if not backend_url or not config then
        return nil, "invalid_parameters"
    end
    
    local parsed_url = url.parse(backend_url)
    if not parsed_url then
        return nil, "url_parse_failed"
    end
    
    local scheme = parsed_url.scheme or config.backend_protocol or "http"
    local host = parsed_url.host or config.backend_host
    local port = tonumber(parsed_url.port)
    
    -- Set default ports if not specified
    if not port then
        port = (scheme == "https") and 443 or 80
    end
    
    local path = parsed_url.path or "/"
    local query = parsed_url.query
    
    -- Append query string if present
    if query then
        path = path .. "?" .. query
    end
    
    return {
        scheme = scheme,
        host = host,
        port = port,
        path = path
    }
end

-- Create backend HTTP connection with enhanced timeout handling
function _M.create_backend_connection(backend_url, config, write_to_log, file_size)
    if not backend_url or not config then
        return nil, "invalid_parameters"
    end
    
    -- Parse URL components
    local url_parts, parse_err = _M.parse_backend_url(backend_url, config)
    if not url_parts then
        return nil, "url_parse_error: " .. (parse_err or "unknown")
    end
    
    write_to_log(ngx.INFO, string.format("Connecting to backend: %s://%s:%d%s (file size: %d bytes)", 
                                        url_parts.scheme, url_parts.host, url_parts.port, url_parts.path,
                                        file_size or 0))
    
    -- Create HTTP client
    local backend = http.new()
    if not backend then
        return nil, "http_client_creation_failed"
    end
    
    -- Set timeouts based on file size
    local timeout = config.socket_timeout or 5000
    if file_size and file_size > 100 * 1024 * 1024 then  -- > 100MB
        timeout = timeout * 5  -- 5x timeout for large files
        write_to_log(ngx.INFO, string.format("Using extended timeout for large file: %d ms", timeout))
    end
    
    backend:set_timeout(timeout)
    
    -- Connect to backend
    local ok, err = backend:connect{
        scheme = url_parts.scheme,
        host = url_parts.host,
        port = url_parts.port,
        ssl_verify = false  -- Disable SSL verification for internal services
    }
    
    if not ok then
        return nil, "backend_connection_failed: " .. (err or "unknown")
    end
    
    write_to_log(ngx.INFO, "Backend connection established successfully")
    
    return {
        client = backend,
        url_parts = url_parts
    }
end

-- Enhanced stream to backend with support for both buffer modes
function _M.stream_to_backend_enhanced(backend_url, buffer, original_headers, multipart_headers, config, write_to_log)
    if not backend_url or not buffer or not config then
        return nil, "invalid_parameters"
    end
    
    local buffer_manager = require "buffer_manager"
    
    -- Get buffer stats for logging and timeout calculation
    local buffer_stats = buffer_manager.get_buffer_stats(buffer)
    write_to_log(ngx.INFO, string.format("Starting backend stream: %s mode, %d bytes (memory: %d, disk: %d)", 
                                        buffer_stats.mode, buffer_stats.total_size, 
                                        buffer_stats.memory_size, buffer_stats.disk_size))
    
    -- Create backend connection with file size awareness
    local connection, conn_err = _M.create_backend_connection(backend_url, config, write_to_log, buffer_stats.total_size)
    if not connection then
        return nil, "connection_error: " .. (conn_err or "unknown")
    end
    
    local backend = connection.client
    local url_parts = connection.url_parts
    
    -- Generate multipart boundary
    local boundary = "----WebKitFormBoundary" .. generate_random_alphanumeric(BOUNDARY_LENGTH)
    
    -- Build proxy headers
    local headers, header_err = _M.build_proxy_headers(original_headers, config, boundary)
    if not headers then
        backend:close()
        return nil, "header_build_error: " .. (header_err or "unknown")
    end
    
    -- Create enhanced streaming body reader
    local body_reader, reader_err = _M.create_enhanced_multipart_stream_reader(buffer, boundary, multipart_headers)
    if not body_reader then
        backend:close()
        return nil, "reader_creation_error: " .. (reader_err or "unknown")
    end
    
    write_to_log(ngx.INFO, string.format("Starting backend upload stream: %s mode, %d bytes", 
                                        buffer_stats.mode, buffer_stats.total_size))
    
    local start_time = ngx.now()
    
    -- Make streaming request
    local res, err = backend:request{
        method = "POST",
        path = url_parts.path,
        body = body_reader,
        headers = headers
    }
    
    local duration = ngx.now() - start_time
    
    if not res then
        backend:close()
        return nil, "request_failed: " .. (err or "unknown")
    end
    
    -- Calculate throughput
    local throughput_mbps = (buffer_stats.total_size / duration) / (1024 * 1024)
    
    write_to_log(ngx.INFO, string.format("Backend upload completed: status %d, duration %.2fs, throughput %.2f MB/s", 
                                        res.status, duration, throughput_mbps))
    
    -- Read response body if present
    local response_body = ""
    if res.body then
        response_body = res.body
    end
    
    -- Close connection
    backend:close()
    
    return {
        status = res.status,
        headers = res.headers,
        body = response_body,
        reason = res.reason,
        duration = duration,
        throughput_mbps = throughput_mbps
    }
end

-- Enhanced stream with retry logic and buffer mode awareness
function _M.stream_to_backend_with_retry_enhanced(backend_url, buffer, original_headers, multipart_headers, config, write_to_log, max_retries)
    local retries = max_retries or 2
    local last_error = nil
    
    local buffer_manager = require "buffer_manager"
    local buffer_stats = buffer_manager.get_buffer_stats(buffer)
    
    -- Reduce retries for very large files to avoid excessive delays
    if buffer_stats.total_size > 500 * 1024 * 1024 then  -- > 500MB
        retries = 1
        write_to_log(ngx.INFO, "Reduced retry count for large file to prevent excessive delays")
    end
    
    for attempt = 1, retries + 1 do
        if attempt > 1 then
            local backoff_time = 0.1 * attempt * attempt  -- Quadratic backoff
            write_to_log(ngx.WARN, string.format("Backend upload retry attempt %d/%d (backoff: %.1fs)", 
                                                attempt - 1, retries, backoff_time))
            ngx.sleep(backoff_time)
        end
        
        local result, err = _M.stream_to_backend_enhanced(backend_url, buffer, original_headers, 
                                                        multipart_headers, config, write_to_log)
        
        if result then
            if attempt > 1 then
                write_to_log(ngx.INFO, string.format("Backend upload succeeded on retry attempt %d", attempt - 1))
            end
            return result
        end
        
        last_error = err
        write_to_log(ngx.WARN, string.format("Backend upload attempt %d failed: %s", attempt, err or "unknown"))
        
        -- Don't retry on certain errors
        if err and (err:find("invalid_parameters") or err:find("reader_creation_error")) then
            break
        end
        
        -- Don't retry connection errors for large files (likely network capacity issue)
        if err and err:find("connection_failed") and buffer_stats.total_size > 100 * 1024 * 1024 then
            write_to_log(ngx.WARN, "Skipping retry for large file connection error")
            break
        end
    end
    
    return nil, "max_retries_exceeded: " .. (last_error or "unknown")
end

-- Validate backend response with enhanced logging
function _M.validate_backend_response(response, write_to_log)
    if not response then
        return false, "no_response"
    end
    
    local status = response.status
    
    if status >= 200 and status < 300 then
        local perf_info = ""
        if response.duration and response.throughput_mbps then
            perf_info = string.format(" (%.2fs, %.2f MB/s)", response.duration, response.throughput_mbps)
        end
        write_to_log(ngx.INFO, "Backend response successful: " .. status .. perf_info)
        return true, "success"
    elseif status >= 400 and status < 500 then
        write_to_log(ngx.WARN, "Backend client error: " .. status)
        return false, "client_error"
    elseif status >= 500 then
        write_to_log(ngx.ERR, "Backend server error: " .. status)
        return false, "server_error"
    else
        write_to_log(ngx.WARN, "Backend unexpected status: " .. status)
        return false, "unexpected_status"
    end
end

-- Create enhanced backend response proxy
function _M.proxy_backend_response_enhanced(response, write_to_log)
    if not response then
        ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
        ngx.say("Backend response error")
        return
    end
    
    -- Set response status
    ngx.status = response.status
    
    -- Set response headers (excluding hop-by-hop headers)
    if response.headers then
        for name, value in pairs(response.headers) do
            local name_lower = name:lower()
            if name_lower ~= "connection" and 
               name_lower ~= "transfer-encoding" and
               name_lower ~= "content-length" then
                ngx.header[name] = value
            end
        end
    end
    
    -- Add performance headers for debugging
    if response.duration then
        ngx.header["X-Upload-Duration"] = string.format("%.3f", response.duration)
    end
    if response.throughput_mbps then
        ngx.header["X-Upload-Throughput"] = string.format("%.2f", response.throughput_mbps)
    end
    
    -- Send response body
    if response.body then
        ngx.say(response.body)
    end
    
    write_to_log(ngx.INFO, "Enhanced backend response proxied successfully")
end

-- Get enhanced connection statistics
function _M.get_enhanced_connection_stats(connection_start_time, buffer_stats)
    local duration = ngx.now() - connection_start_time
    local throughput = buffer_stats.total_size / duration  -- bytes per second
    
    return {
        duration_seconds = duration,
        throughput_bps = throughput,
        throughput_mbps = throughput / (1024 * 1024),
        buffer_mode = buffer_stats.mode,
        total_size_bytes = buffer_stats.total_size,
        memory_size_bytes = buffer_stats.memory_size,
        disk_size_bytes = buffer_stats.disk_size
    }
end

-- Test backend connectivity with file size consideration
function _M.test_backend_connectivity_enhanced(backend_url, config, write_to_log, expected_file_size)
    local connection, err = _M.create_backend_connection(backend_url, config, write_to_log, expected_file_size)
    if not connection then
        return false, err
    end
    
    -- Close connection immediately after successful connect
    connection.client:close()
    write_to_log(ngx.INFO, "Enhanced backend connectivity test successful")
    return true
end

-- Backward compatibility functions (delegate to enhanced versions)
function _M.stream_to_backend(backend_url, buffer, original_headers, multipart_headers, config, write_to_log)
    return _M.stream_to_backend_enhanced(backend_url, buffer, original_headers, multipart_headers, config, write_to_log)
end

function _M.stream_to_backend_with_retry(backend_url, buffer, original_headers, multipart_headers, config, write_to_log, max_retries)
    return _M.stream_to_backend_with_retry_enhanced(backend_url, buffer, original_headers, multipart_headers, config, write_to_log, max_retries)
end

function _M.proxy_backend_response(response, write_to_log)
    return _M.proxy_backend_response_enhanced(response, write_to_log)
end

return _M