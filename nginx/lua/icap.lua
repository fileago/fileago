--[[
Copyright (c) 2018-2025 FileAgo Software Pvt Ltd. All Rights Reserved.

This software is proprietary and confidential.
Unauthorized copying of this file, via any medium, is strictly prohibited.

For license information, see the LICENSE.txt file in the root directory of
this project.
--]]

-- icap.lua: An enhanced non-blocking ICAP handler with large file support
-- Supports both memory mode (< 100MB) and hybrid mode (up to 1GB) for optimal performance

-- Import required modules
local upload = require "resty.upload"
local config = require "config"

-- Import enhanced non-blocking modules
local mime_detector = require "mime_detector"
local buffer_manager = require "buffer_manager"
local icap_streamer = require "icap_streamer"
local backend_streamer = require "backend_streamer"
local error_handler = require "error_handler"
local resource_manager = require "resource_manager"

-- Helper function to standardize logging
local function write_to_log(log_type, log_msg)
    if config.log_icap_traffic == true then
        ngx.log(log_type, "[ICAP] " .. log_msg)
    elseif log_type == ngx.ERR then
        ngx.log(log_type, "[ICAP] " .. log_msg)
    end
end

-- Helper function to check if file extension is allowed
local function is_allowed_extension(filename)
    if not config.allowed_extensions or config.allowed_extensions == "" then
        return true
    end
    
    local file_extension = filename:match("^.+(%..+)$")
    if not file_extension then
        write_to_log(ngx.WARN, "No file extension found in filename: " .. filename)
        return false
    end
    
    file_extension = file_extension:lower()
    
    -- Parse allowed extensions and trim whitespace
    local allowed_list = {}
    for ext in config.allowed_extensions:gmatch("[^,]+") do
        local trimmed_ext = ext:match("^%s*(.-)%s*$"):lower()  -- Trim whitespace
        table.insert(allowed_list, trimmed_ext)
        if trimmed_ext == file_extension then
            write_to_log(ngx.INFO, string.format("Extension validation passed: %s matches allowed extension %s",
                                                file_extension, trimmed_ext))
            return true
        end
    end
    
    write_to_log(ngx.WARN, string.format("Extension validation failed: %s not in allowed list [%s]",
                                        file_extension, table.concat(allowed_list, ", ")))
    return false
end

-- Enhanced upload processing with hybrid buffer support
local function process_upload_enhanced()
    -- Initialize error handling and resource tracking
    local error_context = error_handler.create_error_context()
    local timeout_context = error_handler.create_timeout_context(60)  -- 60 second timeout for large files
    local resource_tracker = resource_manager.create_resource_tracker()
    
    write_to_log(ngx.INFO, "Starting enhanced upload processing: " .. ngx.var.request_uri)
    
    -- Register cleanup tasks
    error_handler.add_cleanup_task(error_context, "resources", function()
        resource_manager.cleanup_all_resources(resource_tracker, write_to_log)
    end, 100)
    
    -- Phase 1: Initialize upload processing
    error_handler.set_phase(error_context, "upload_initialization")
    
    local form, err = upload:new(config.chunk_size)
    if not form then
        error_handler.handle_error(error_context, "UPLOAD_ERROR",
                                 "Failed to initialize upload: " .. (err or "unknown"), write_to_log)
        return false, "Failed to initialize upload"
    end
    
    form:set_timeout(config.upload_timeout)
    
    -- Create enhanced buffer (automatically handles memory/hybrid modes)
    local file_buffer = buffer_manager.create_enhanced_buffer()
    local buffer_id = "enhanced_upload_" .. ngx.now() .. "_" .. math.random(1000, 9999)
    resource_manager.track_memory_buffer(resource_tracker, buffer_id, file_buffer)
    
    -- Register buffer cleanup
    error_handler.add_cleanup_task(error_context, "file_buffer", function()
        buffer_manager.clear_buffer(file_buffer)
    end, 95)
    
    write_to_log(ngx.INFO, "Enhanced buffer created: " .. buffer_id)
    
    -- Phase 2: Process upload stream with automatic mode switching
    error_handler.set_phase(error_context, "upload_streaming")
    
    local multipart_headers = {}
    local bytes_processed = 0
    local last_mode = file_buffer.mode
    
    while true do
        -- Check timeout periodically
        local timeout_ok, timeout_err = error_handler.check_timeout(timeout_context)
        if not timeout_ok then
            error_handler.handle_error(error_context, "TIMEOUT_ERROR", timeout_err, write_to_log)
            return
        end
        
        local typ, res, err = form:read()
        if not typ then
            error_handler.handle_error(error_context, "UPLOAD_ERROR",
                                     "Failed to read upload data: " .. (err or "unknown"), write_to_log)
            return false, "Failed to read upload data"
        end
        
        if typ == "body" then
            -- Add chunk to enhanced buffer (handles mode switching automatically)
            local ok, buffer_err = buffer_manager.add_chunk(file_buffer, res)
            if not ok then
                if buffer_err == "file_too_large" then
                    error_handler.handle_error(error_context, "VALIDATION_ERROR",
                                             "File exceeds maximum size limit (1GB)", write_to_log)
                    return false, "File too large"
                else
                    error_handler.handle_error(error_context, "MEMORY_ERROR",
                                             "Buffer error: " .. (buffer_err or "unknown"), write_to_log)
                    return false, "Buffer error"
                end
            end
            
            bytes_processed = bytes_processed + #res
            error_handler.update_metrics(error_context, #res, 
                                       buffer_manager.estimate_memory_usage(file_buffer))
            
            -- Log mode switch if it occurred
            if file_buffer.mode ~= last_mode then
                write_to_log(ngx.INFO, string.format("Buffer switched from %s to %s mode at %d bytes", 
                                                    last_mode, file_buffer.mode, file_buffer.total_size))
                last_mode = file_buffer.mode
            end
            
            -- Detect MIME type on first significant chunk (use file command for accuracy)
            if not file_buffer.mime_detected and file_buffer.total_size >= 512 then
                local preview_data = buffer_manager.get_preview_data(file_buffer, 2048)  -- More data for better detection
                local detected_mime, detection_method, details = mime_detector.detect_mime_comprehensive(
                    preview_data, file_buffer.filename, config.check_mime_type  -- This enables file command
                )
                
                if detected_mime then
                    file_buffer.mime_type = detected_mime
                    file_buffer.mime_method = detection_method
                    file_buffer.mime_detected = true
                    write_to_log(ngx.INFO, string.format("MIME type detected: %s via %s (%s)",
                                                        detected_mime, detection_method, details or ""))
                end
            end
            
        elseif typ == "header" then
            write_to_log(ngx.DEBUG, "Multipart header: " .. res[1] .. " = " .. res[2])
            table.insert(multipart_headers, res[1] .. ": " .. res[2])
            
            if res[1]:lower() == "content-type" then
                file_buffer.header_mime_type = res[2]
            elseif res[1]:lower() == "content-disposition" then
                local filename_match = res[2]:match('filename="([^"]+)"')
                if filename_match then
                    file_buffer.filename = filename_match
                end
            end
            
        elseif typ == "eof" then
            break
        end
        
        -- Yield control periodically (more frequently for large files)
        if bytes_processed % (256 * 1024) == 0 then  -- Every 256KB
            ngx.sleep(0)
        end
    end
    
    local buffer_stats = buffer_manager.get_buffer_stats(file_buffer)
    write_to_log(ngx.INFO, string.format("Upload completed: %d bytes in %s mode (memory: %d, disk: %d)", 
                                        buffer_stats.total_size, buffer_stats.mode, 
                                        buffer_stats.memory_size, buffer_stats.disk_size))
    
    -- Phase 3: Validate upload
    error_handler.set_phase(error_context, "upload_validation")
    
    if file_buffer.total_size == 0 then
        error_handler.handle_error(error_context, "VALIDATION_ERROR", "No file data received", write_to_log)
        return false, "No file data received"
    end
    
    -- Check file extension
    if file_buffer.filename and file_buffer.filename ~= "" then
        write_to_log(ngx.INFO, "Validating file extension for: " .. file_buffer.filename)
        if not is_allowed_extension(file_buffer.filename) then
            error_handler.handle_error(error_context, "EXTENSION_ERROR",
                                     "File extension not allowed: " .. file_buffer.filename, write_to_log)
            return false, "File extension not allowed"
        end
    else
        write_to_log(ngx.WARN, "No filename found in upload headers")
    end
    
    -- Phase 4: MIME type validation
    error_handler.set_phase(error_context, "mime_validation")
    
    if config.check_mime_type == true then
        if not file_buffer.mime_detected then
            -- Try detection with more data and force file command usage
            local preview_data = buffer_manager.get_preview_data(file_buffer, 8192)  -- 8KB should be enough
            local detected_mime, detection_method, details = mime_detector.detect_mime_comprehensive(
                preview_data, file_buffer.filename, true  -- Force external detection for accuracy
            )
            
            if detected_mime then
                file_buffer.mime_type = detected_mime
                file_buffer.mime_method = detection_method
                file_buffer.mime_detected = true
                write_to_log(ngx.INFO, string.format("MIME type detected (retry): %s via %s (%s)",
                                                    detected_mime, detection_method, details or ""))
            else
                error_handler.handle_error(error_context, "MIME_ERROR",
                                         "Failed to detect MIME type for file: " .. (file_buffer.filename or "unknown"),
                                         write_to_log)
                return false, "Failed to detect MIME type"
            end
        end
        
        -- Validate MIME type against header (with relaxed validation for generic headers)
        if file_buffer.header_mime_type and file_buffer.mime_type then
            -- Check if header is generic/unreliable
            local generic_mime_types = {
                "application/octet-stream",
                "application/binary",
                "binary/octet-stream"
            }
            
            local is_generic_header = false
            for _, generic_type in ipairs(generic_mime_types) do
                if file_buffer.header_mime_type:lower():find(generic_type, 1, true) then
                    is_generic_header = true
                    break
                end
            end
            
            if is_generic_header then
                -- Trust file command detection over generic headers
                write_to_log(ngx.INFO, string.format("Generic MIME header detected (%s), trusting file command detection: %s",
                                                    file_buffer.header_mime_type, file_buffer.mime_type))
                write_to_log(ngx.INFO, "MIME validation: PASSED (generic header override)")
            else
                -- Perform strict validation for specific headers
                local is_valid, validation_result = mime_detector.validate_mime_type(
                    file_buffer.mime_type, file_buffer.header_mime_type
                )
                
                if not is_valid then
                    write_to_log(ngx.ERR, string.format("MIME type mismatch: detected=%s, header=%s (%s)",
                                                       file_buffer.mime_type, file_buffer.header_mime_type, validation_result))
                    error_handler.handle_error(error_context, "MIME_ERROR",
                                             "MIME type mismatch detected", write_to_log)
                    return false, "MIME type mismatch"
                else
                    write_to_log(ngx.INFO, string.format("MIME type validation passed: %s", validation_result))
                end
            end
        end
    end
    
    -- Phase 5: ICAP scanning (COMPLETE SCAN BEFORE BACKEND)
    error_handler.set_phase(error_context, "icap_scanning")
    
    write_to_log(ngx.INFO, string.format("Starting ICAP security scan for %s file (%d bytes)", 
                                        file_buffer.mode, file_buffer.total_size))
    
    -- Set longer timeout for large files
    if file_buffer.total_size > 100 * 1024 * 1024 then  -- > 100MB
        error_handler.set_phase_timeout(timeout_context, "icap_scanning", 300)  -- 5 minutes
    else
        error_handler.set_phase_timeout(timeout_context, "icap_scanning", 60)   -- 1 minute
    end
    
    -- Create ICAP connection
    local icap_sock, icap_err = icap_streamer.create_icap_connection(config, write_to_log)
    if not icap_sock then
        error_handler.handle_error(error_context, "ICAP_CONNECTION_ERROR",
                                 "ICAP connection failed: " .. (icap_err or "unknown"), write_to_log)
        return false, "ICAP connection failed"
    end
    
    -- Track ICAP socket
    local icap_socket_id = "icap_enhanced_" .. ngx.now()
    resource_manager.track_socket(resource_tracker, icap_socket_id, icap_sock, {
        host = config.icap_server_host,
        port = config.icap_server_port
    })
    
    -- Register ICAP socket cleanup
    error_handler.add_cleanup_task(error_context, "icap_socket", function()
        icap_streamer.close_icap_connection(icap_sock, write_to_log)
    end, 90)
    
    -- Perform ICAP scan with enhanced buffer
    local scan_result, scan_err = icap_streamer.scan_file_with_icap(icap_sock, file_buffer, config, write_to_log)
    if not scan_result then
        error_handler.handle_error(error_context, "ICAP_CONNECTION_ERROR",
                                 "ICAP scan failed: " .. (scan_err or "unknown"), write_to_log)
        return false, "ICAP scan failed"
    end
    
    -- Process scan results
    if scan_result.result == "blocked" then
        if scan_result.is_size_limit and config.limits_exceeded_behaviour == "allow" then
            write_to_log(ngx.WARN, "File size limit exceeded for '" .. file_buffer.filename .. "' but configured to allow")
        else
            write_to_log(ngx.ERR, string.format("File '" .. file_buffer.filename .. "' has been blocked by ICAP scan: %s", scan_result.message))
            error_handler.handle_error(error_context, "ICAP_SCAN_ERROR", scan_result.message, write_to_log)
            return false, "File blocked by ICAP scan"
        end
    elseif scan_result.result == "clean" then
        write_to_log(ngx.INFO, "File '" .. file_buffer.filename .. "' passed ICAP security scan - APPROVED for backend forwarding")
    else
        write_to_log(ngx.WARN, "Unexpected ICAP scan result: " .. (scan_result.result or "unknown"))
    end
    
    -- Close ICAP connection
    icap_streamer.close_icap_connection(icap_sock, write_to_log)
    resource_manager.cleanup_socket(resource_tracker, icap_socket_id, write_to_log)
    
    -- Phase 6: Forward to backend (ONLY AFTER ICAP APPROVAL)
    error_handler.set_phase(error_context, "backend_forwarding")
    
    local req_uri = ngx.var.request_uri or "/"
    local backend_url = config.get_backend_url(req_uri)
    write_to_log(ngx.INFO, string.format("Forwarding ICAP-approved file to backend: %s (%s mode, %d bytes)", 
                                        backend_url, file_buffer.mode, file_buffer.total_size))
    
    -- Set longer timeout for large files
    if file_buffer.total_size > 100 * 1024 * 1024 then  -- > 100MB
        error_handler.set_phase_timeout(timeout_context, "backend_forwarding", 300)  -- 5 minutes
    else
        error_handler.set_phase_timeout(timeout_context, "backend_forwarding", 60)   -- 1 minute
    end
    
    -- Get original request headers
    local incoming_headers = ngx.req.get_headers()
    
    -- Stream to backend using enhanced buffer
    local backend_response, backend_err = backend_streamer.stream_to_backend_with_retry_enhanced(
        backend_url, file_buffer, incoming_headers, multipart_headers, config, write_to_log, 0 
        -- 0 = no retries since upload token expires after first use, so no point in retrying
    )
    
    if not backend_response then
        error_handler.handle_error(error_context, "BACKEND_ERROR",
                                 "Backend forwarding failed: " .. (backend_err or "unknown"), write_to_log)
        return false, "Backend forwarding failed"
    end
    
    -- Validate backend response
    local is_valid, validation_msg = backend_streamer.validate_backend_response(backend_response, write_to_log)
    if not is_valid then
        write_to_log(ngx.WARN, "Backend response validation failed: " .. validation_msg)
    end
    
    -- Phase 7: Send response to client
    error_handler.set_phase(error_context, "response_generation")
    
    backend_streamer.proxy_backend_response_enhanced(backend_response, write_to_log)
    
    -- Success cleanup and metrics
    local final_stats = buffer_manager.get_buffer_stats(file_buffer)
    error_handler.handle_success(error_context, 
                                string.format("File processed successfully: %s (%d bytes, %s mode)", 
                                            file_buffer.filename or "unknown", 
                                            final_stats.total_size,
                                            final_stats.mode),
                                write_to_log)
    
    -- Explicitly return success
    return true, "Upload processed successfully"
end

-- Circuit breakers for external services
local icap_circuit_breaker = error_handler.create_circuit_breaker(5, 60)
local backend_circuit_breaker = error_handler.create_circuit_breaker(3, 30)

-- Main execution with enhanced error handling
local function main()
    -- Log configuration info
    local config_info = buffer_manager.get_config_info()
    write_to_log(ngx.INFO, string.format("Enhanced ICAP handler initialized - Memory threshold: %d MB, Max file size: %d MB", 
                                        config_info.memory_mode_threshold / (1024*1024),
                                        config_info.max_file_size / (1024*1024)))
    
    -- Execute with circuit breaker protection
    local result, err = error_handler.with_circuit_breaker(icap_circuit_breaker, function()
        process_upload_enhanced()
        return true  -- Explicitly return success
    end, write_to_log)
    
    if not result then
        write_to_log(ngx.ERR, "Enhanced upload processing failed: " .. (err or "unknown"))
        
        -- Only set status if headers haven't been sent yet
        if not ngx.headers_sent then
            if err == "circuit_breaker_open" then
                ngx.status = ngx.HTTP_SERVICE_UNAVAILABLE
                ngx.say("Service temporarily unavailable")
                ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
            else
                ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
                ngx.say("Internal server error")
                ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
            end
        else
            write_to_log(ngx.WARN, "Cannot set error status - headers already sent")
        end
    end
end

-- Execute main function
main()