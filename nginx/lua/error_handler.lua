--[[
Copyright (c) 2018-2025 FileAgo Software Pvt Ltd. All Rights Reserved.

This software is proprietary and confidential.
Unauthorized copying of this file, via any medium, is strictly prohibited.

For license information, see the LICENSE.txt file in the root directory of
this project.
--]]

-- error_handler.lua: Comprehensive error handling and cleanup for non-blocking operations
-- This module provides structured error handling with automatic resource cleanup

local _M = {}

-- Error types and their HTTP response mappings
local ERROR_TYPES = {
    UPLOAD_ERROR = {code = 400, message = "Upload processing failed"},
    MIME_ERROR = {code = 400, message = "MIME type validation failed"},
    EXTENSION_ERROR = {code = 400, message = "File extension not allowed"},
    MEMORY_ERROR = {code = 413, message = "File too large for processing"},
    ICAP_CONNECTION_ERROR = {code = 502, message = "Antivirus service unavailable"},
    ICAP_SCAN_ERROR = {code = 403, message = "File blocked by security scan"},
    BACKEND_ERROR = {code = 502, message = "Backend service unavailable"},
    TIMEOUT_ERROR = {code = 408, message = "Request timeout"},
    VALIDATION_ERROR = {code = 400, message = "Request validation failed"},
    INTERNAL_ERROR = {code = 500, message = "Internal server error"}
}

-- Create error handling context
function _M.create_error_context()
    return {
        cleanup_tasks = {},           -- Cleanup functions to execute
        error_occurred = false,       -- Whether an error has occurred
        start_time = ngx.now(),      -- Request start time
        request_id = ngx.var.request_id or "unknown",  -- Request identifier
        phase = "initialization",    -- Current processing phase
        metrics = {                  -- Performance metrics
            bytes_processed = 0,
            operations_count = 0,
            peak_memory_usage = 0
        }
    }
end

-- Add cleanup task to be executed on error or success
function _M.add_cleanup_task(context, task_name, cleanup_func, priority)
    if not context or not task_name or not cleanup_func then
        return false, "invalid_parameters"
    end
    
    context.cleanup_tasks[task_name] = {
        func = cleanup_func,
        priority = priority or 100,  -- Default priority
        added_at = ngx.now()
    }
    
    return true
end

-- Remove cleanup task
function _M.remove_cleanup_task(context, task_name)
    if context and context.cleanup_tasks then
        context.cleanup_tasks[task_name] = nil
    end
end

-- Set current processing phase
function _M.set_phase(context, phase_name)
    if context then
        context.phase = phase_name
    end
end

-- Update metrics
function _M.update_metrics(context, bytes_processed, memory_usage)
    if not context or not context.metrics then
        return
    end
    
    if bytes_processed then
        context.metrics.bytes_processed = context.metrics.bytes_processed + bytes_processed
    end
    
    if memory_usage and memory_usage > context.metrics.peak_memory_usage then
        context.metrics.peak_memory_usage = memory_usage
    end
    
    context.metrics.operations_count = context.metrics.operations_count + 1
end

-- Execute cleanup tasks in priority order
function _M.execute_cleanup_tasks(context, write_to_log)
    if not context or not context.cleanup_tasks then
        return
    end
    
    -- Sort cleanup tasks by priority (higher priority first)
    local cleanup_order = {}
    for task_name, task_info in pairs(context.cleanup_tasks) do
        table.insert(cleanup_order, {
            name = task_name,
            info = task_info
        })
    end
    
    table.sort(cleanup_order, function(a, b)
        return a.info.priority > b.info.priority
    end)
    
    -- Execute cleanup tasks
    local cleanup_count = 0
    local cleanup_errors = 0
    
    for _, task in ipairs(cleanup_order) do
        local task_name = task.name
        local cleanup_func = task.info.func
        
        local ok, err = pcall(cleanup_func)
        if ok then
            cleanup_count = cleanup_count + 1
            if write_to_log then
                write_to_log(ngx.DEBUG, string.format("Cleanup task '%s' completed successfully", task_name))
            end
        else
            cleanup_errors = cleanup_errors + 1
            if write_to_log then
                write_to_log(ngx.WARN, string.format("Cleanup task '%s' failed: %s", task_name, err or "unknown"))
            end
        end
    end
    
    if write_to_log then
        write_to_log(ngx.INFO, string.format("Cleanup completed: %d successful, %d failed", 
                                            cleanup_count, cleanup_errors))
    end
end

-- Handle error with cleanup and appropriate HTTP response
function _M.handle_error(context, error_type, details, write_to_log)
    if not context then
        -- Fallback error handling without context
        ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
        ngx.say("Internal server error")
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
        return
    end
    
    context.error_occurred = true
    
    -- Log error details
    local error_msg = string.format("[ERROR] %s in phase '%s': %s (Request ID: %s)", 
                                   error_type, context.phase, details or "no details", context.request_id)
    
    if write_to_log then
        write_to_log(ngx.ERR, error_msg)
    end
    
    -- Execute cleanup tasks
    _M.execute_cleanup_tasks(context, write_to_log)
    
    -- Get error information
    local error_info = ERROR_TYPES[error_type] or ERROR_TYPES.INTERNAL_ERROR
    
    -- Calculate request duration
    local duration = ngx.now() - context.start_time
    
    -- Log performance metrics
    if write_to_log then
        write_to_log(ngx.INFO, string.format(
            "Request failed after %.3fs - Bytes processed: %d, Operations: %d, Peak memory: %d bytes",
            duration, context.metrics.bytes_processed, context.metrics.operations_count, 
            context.metrics.peak_memory_usage
        ))
    end
    
    -- Set HTTP response
    ngx.status = error_info.code
    ngx.header["Content-Type"] = "text/plain"
    ngx.header["X-Request-ID"] = context.request_id
    ngx.header["X-Error-Type"] = error_type
    ngx.say(error_info.message)
    
    -- Exit with appropriate status
    ngx.exit(error_info.code)
end

-- Handle successful completion
function _M.handle_success(context, message, write_to_log)
    if not context then
        return
    end
    
    -- Execute cleanup tasks
    _M.execute_cleanup_tasks(context, write_to_log)
    
    -- Calculate request duration and performance metrics
    local duration = ngx.now() - context.start_time
    local throughput = context.metrics.bytes_processed / duration  -- bytes per second
    
    -- Log success with metrics
    if write_to_log then
        write_to_log(ngx.INFO, string.format(
            "Request completed successfully in %.3fs - %s - Bytes: %d, Throughput: %.2f MB/s, Operations: %d",
            duration, message or "Success", context.metrics.bytes_processed, 
            throughput / (1024 * 1024), context.metrics.operations_count
        ))
    end
end

-- Wrap function execution with error handling
function _M.with_error_handling(context, phase_name, operation_func, write_to_log)
    if not context or not operation_func then
        return nil, "invalid_parameters"
    end
    
    -- Set current phase
    _M.set_phase(context, phase_name)
    
    -- Execute operation with error handling
    local ok, result = pcall(operation_func)
    
    if ok then
        return result
    else
        _M.handle_error(context, "INTERNAL_ERROR", 
                       string.format("Operation failed in phase '%s': %s", phase_name, result), 
                       write_to_log)
        return nil  -- This line won't be reached due to ngx.exit in handle_error
    end
end

-- Create timeout context for operation timeouts
function _M.create_timeout_context(total_timeout_seconds)
    return {
        start_time = ngx.now(),
        total_timeout = total_timeout_seconds or 30,
        phase_timeouts = {},
        current_phase = nil
    }
end

-- Set timeout for current phase
function _M.set_phase_timeout(timeout_context, phase_name, timeout_seconds)
    if not timeout_context then
        return false
    end
    
    timeout_context.phase_timeouts[phase_name] = {
        timeout = timeout_seconds,
        start_time = ngx.now()
    }
    timeout_context.current_phase = phase_name
    return true
end

-- Check if any timeout has been exceeded
function _M.check_timeout(timeout_context)
    if not timeout_context then
        return true  -- No timeout context means no timeout
    end
    
    local now = ngx.now()
    
    -- Check total timeout
    if (now - timeout_context.start_time) > timeout_context.total_timeout then
        return false, "total_timeout_exceeded"
    end
    
    -- Check current phase timeout
    if timeout_context.current_phase then
        local phase_info = timeout_context.phase_timeouts[timeout_context.current_phase]
        if phase_info and (now - phase_info.start_time) > phase_info.timeout then
            return false, string.format("phase_timeout_exceeded: %s", timeout_context.current_phase)
        end
    end
    
    return true
end

-- Execute operation with timeout checking
function _M.with_timeout(timeout_context, phase_name, timeout_seconds, operation_func)
    if not timeout_context or not operation_func then
        return nil, "invalid_parameters"
    end
    
    -- Set phase timeout
    _M.set_phase_timeout(timeout_context, phase_name, timeout_seconds)
    
    -- Check timeout before operation
    local timeout_ok, timeout_err = _M.check_timeout(timeout_context)
    if not timeout_ok then
        return nil, timeout_err
    end
    
    -- Execute operation
    local ok, result = pcall(operation_func)
    
    -- Check timeout after operation
    timeout_ok, timeout_err = _M.check_timeout(timeout_context)
    if not timeout_ok then
        return nil, timeout_err
    end
    
    if not ok then
        return nil, string.format("operation_failed: %s", result)
    end
    
    return result
end

-- Create circuit breaker for external service calls
function _M.create_circuit_breaker(failure_threshold, recovery_timeout)
    return {
        failure_count = 0,
        failure_threshold = failure_threshold or 5,
        recovery_timeout = recovery_timeout or 60,
        last_failure_time = 0,
        state = "closed"  -- closed, open, half-open
    }
end

-- Execute operation with circuit breaker protection
function _M.with_circuit_breaker(circuit_breaker, operation_func, write_to_log)
    if not circuit_breaker or not operation_func then
        return nil, "invalid_parameters"
    end
    
    local now = ngx.now()
    
    -- Check circuit breaker state
    if circuit_breaker.state == "open" then
        if (now - circuit_breaker.last_failure_time) > circuit_breaker.recovery_timeout then
            circuit_breaker.state = "half-open"
            if write_to_log then
                write_to_log(ngx.INFO, "Circuit breaker transitioning to half-open state")
            end
        else
            return nil, "circuit_breaker_open"
        end
    end
    
    -- Execute operation
    local ok, result = pcall(operation_func)
    
    if ok then
        -- Success - reset failure count
        if circuit_breaker.failure_count > 0 then
            circuit_breaker.failure_count = 0
            circuit_breaker.state = "closed"
            if write_to_log then
                write_to_log(ngx.INFO, "Circuit breaker reset to closed state")
            end
        end
        return result
    else
        -- Failure - increment failure count
        circuit_breaker.failure_count = circuit_breaker.failure_count + 1
        circuit_breaker.last_failure_time = now
        
        if circuit_breaker.failure_count >= circuit_breaker.failure_threshold then
            circuit_breaker.state = "open"
            if write_to_log then
                write_to_log(ngx.WARN, string.format("Circuit breaker opened after %d failures", 
                                                    circuit_breaker.failure_count))
            end
        end
        
        return nil, string.format("operation_failed: %s", result)
    end
end

-- Get error context statistics
function _M.get_context_stats(context)
    if not context then
        return nil
    end
    
    return {
        request_id = context.request_id,
        current_phase = context.phase,
        duration_seconds = ngx.now() - context.start_time,
        error_occurred = context.error_occurred,
        cleanup_tasks_count = context.cleanup_tasks and #context.cleanup_tasks or 0,
        metrics = context.metrics
    }
end

return _M