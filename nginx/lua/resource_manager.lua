--[[
Copyright (c) 2018-2025 FileAgo Software Pvt Ltd. All Rights Reserved.

This software is proprietary and confidential.
Unauthorized copying of this file, via any medium, is strictly prohibited.

For license information, see the LICENSE.txt file in the root directory of
this project.
--]]

-- resource_manager.lua: Non-blocking resource management and cleanup
-- This module tracks and manages system resources to prevent leaks and optimize performance

local _M = {}

-- Resource tracking constants
local MAX_TRACKED_RESOURCES = 1000
local CLEANUP_INTERVAL = 300  -- 5 minutes
local MEMORY_WARNING_THRESHOLD = 50 * 1024 * 1024  -- 50MB

-- Create resource tracker
function _M.create_resource_tracker()
    return {
        memory_buffers = {},      -- Track memory buffers
        socket_connections = {},  -- Track socket connections
        temporary_data = {},      -- Track temporary data
        file_handles = {},        -- Track any file handles (if used)
        timers = {},             -- Track ngx.timer handles
        threads = {},            -- Track ngx.thread handles
        created_at = ngx.now(),
        last_cleanup = ngx.now(),
        stats = {
            peak_memory_usage = 0,
            total_resources_created = 0,
            total_resources_cleaned = 0,
            cleanup_operations = 0
        }
    }
end

-- Track memory buffer
function _M.track_memory_buffer(tracker, buffer_id, buffer)
    if not tracker or not buffer_id or not buffer then
        return false, "invalid_parameters"
    end
    
    -- Check if we're tracking too many resources
    if #tracker.memory_buffers >= MAX_TRACKED_RESOURCES then
        return false, "max_resources_exceeded"
    end
    
    tracker.memory_buffers[buffer_id] = {
        buffer = buffer,
        created_at = ngx.now(),
        last_access = ngx.now(),
        size = buffer.total_size or 0
    }
    
    tracker.stats.total_resources_created = tracker.stats.total_resources_created + 1
    
    -- Update peak memory usage
    local current_usage = _M.calculate_total_memory_usage(tracker)
    if current_usage > tracker.stats.peak_memory_usage then
        tracker.stats.peak_memory_usage = current_usage
    end
    
    return true
end

-- Track socket connection
function _M.track_socket(tracker, socket_id, socket, connection_info)
    if not tracker or not socket_id or not socket then
        return false, "invalid_parameters"
    end
    
    tracker.socket_connections[socket_id] = {
        socket = socket,
        created_at = ngx.now(),
        last_used = ngx.now(),
        info = connection_info or {}
    }
    
    tracker.stats.total_resources_created = tracker.stats.total_resources_created + 1
    return true
end

-- Track temporary data
function _M.track_temporary_data(tracker, data_id, data, cleanup_func)
    if not tracker or not data_id then
        return false, "invalid_parameters"
    end
    
    tracker.temporary_data[data_id] = {
        data = data,
        cleanup_func = cleanup_func,
        created_at = ngx.now(),
        size = type(data) == "string" and #data or 0
    }
    
    tracker.stats.total_resources_created = tracker.stats.total_resources_created + 1
    return true
end

-- Track thread
function _M.track_thread(tracker, thread_id, thread)
    if not tracker or not thread_id or not thread then
        return false, "invalid_parameters"
    end
    
    tracker.threads[thread_id] = {
        thread = thread,
        created_at = ngx.now(),
        status = "running"
    }
    
    tracker.stats.total_resources_created = tracker.stats.total_resources_created + 1
    return true
end

-- Update buffer access time
function _M.update_buffer_access(tracker, buffer_id)
    if tracker and tracker.memory_buffers[buffer_id] then
        tracker.memory_buffers[buffer_id].last_access = ngx.now()
    end
end

-- Update socket usage time
function _M.update_socket_usage(tracker, socket_id)
    if tracker and tracker.socket_connections[socket_id] then
        tracker.socket_connections[socket_id].last_used = ngx.now()
    end
end

-- Calculate total memory usage
function _M.calculate_total_memory_usage(tracker)
    if not tracker then
        return 0
    end
    
    local total = 0
    
    -- Sum buffer sizes
    for _, buffer_info in pairs(tracker.memory_buffers) do
        total = total + (buffer_info.size or 0)
    end
    
    -- Sum temporary data sizes
    for _, temp_info in pairs(tracker.temporary_data) do
        total = total + (temp_info.size or 0)
    end
    
    return total
end

-- Clean up expired resources
function _M.cleanup_expired_resources(tracker, max_age_seconds, write_to_log)
    if not tracker then
        return 0
    end
    
    local now = ngx.now()
    local max_age = max_age_seconds or 3600  -- Default 1 hour
    local cleaned_count = 0
    
    -- Clean up old memory buffers
    for buffer_id, buffer_info in pairs(tracker.memory_buffers) do
        if (now - buffer_info.last_access) > max_age then
            _M.cleanup_memory_buffer(tracker, buffer_id, write_to_log)
            cleaned_count = cleaned_count + 1
        end
    end
    
    -- Clean up old temporary data
    for data_id, temp_info in pairs(tracker.temporary_data) do
        if (now - temp_info.created_at) > max_age then
            _M.cleanup_temporary_data(tracker, data_id, write_to_log)
            cleaned_count = cleaned_count + 1
        end
    end
    
    -- Clean up old socket connections
    for socket_id, socket_info in pairs(tracker.socket_connections) do
        if (now - socket_info.last_used) > max_age then
            _M.cleanup_socket(tracker, socket_id, write_to_log)
            cleaned_count = cleaned_count + 1
        end
    end
    
    tracker.last_cleanup = now
    tracker.stats.cleanup_operations = tracker.stats.cleanup_operations + 1
    
    if write_to_log and cleaned_count > 0 then
        write_to_log(ngx.INFO, string.format("Cleaned up %d expired resources", cleaned_count))
    end
    
    return cleaned_count
end

-- Clean up specific memory buffer
function _M.cleanup_memory_buffer(tracker, buffer_id, write_to_log)
    if not tracker or not tracker.memory_buffers[buffer_id] then
        return false
    end
    
    local buffer_info = tracker.memory_buffers[buffer_id]
    local buffer = buffer_info.buffer
    
    -- Clear buffer data if it has a clear method
    if buffer and type(buffer.chunks) == "table" then
        for i = 1, #buffer.chunks do
            buffer.chunks[i] = nil
        end
        buffer.chunks = {}
        buffer.total_size = 0
    end
    
    tracker.memory_buffers[buffer_id] = nil
    tracker.stats.total_resources_cleaned = tracker.stats.total_resources_cleaned + 1
    
    if write_to_log then
        write_to_log(ngx.DEBUG, string.format("Cleaned up memory buffer: %s", buffer_id))
    end
    
    return true
end

-- Clean up specific socket
function _M.cleanup_socket(tracker, socket_id, write_to_log)
    if not tracker or not tracker.socket_connections[socket_id] then
        return false
    end
    
    local socket_info = tracker.socket_connections[socket_id]
    local socket = socket_info.socket
    
    -- Close socket if it has a close method
    if socket and socket.close then
        local ok, err = pcall(socket.close, socket)
        if not ok and write_to_log then
            write_to_log(ngx.WARN, string.format("Socket close error for %s: %s", socket_id, err))
        end
    end
    
    tracker.socket_connections[socket_id] = nil
    tracker.stats.total_resources_cleaned = tracker.stats.total_resources_cleaned + 1
    
    if write_to_log then
        write_to_log(ngx.DEBUG, string.format("Cleaned up socket: %s", socket_id))
    end
    
    return true
end

-- Clean up specific temporary data
function _M.cleanup_temporary_data(tracker, data_id, write_to_log)
    if not tracker or not tracker.temporary_data[data_id] then
        return false
    end
    
    local temp_info = tracker.temporary_data[data_id]
    
    -- Execute custom cleanup function if provided
    if temp_info.cleanup_func then
        local ok, err = pcall(temp_info.cleanup_func, temp_info.data)
        if not ok and write_to_log then
            write_to_log(ngx.WARN, string.format("Temp data cleanup error for %s: %s", data_id, err))
        end
    end
    
    tracker.temporary_data[data_id] = nil
    tracker.stats.total_resources_cleaned = tracker.stats.total_resources_cleaned + 1
    
    if write_to_log then
        write_to_log(ngx.DEBUG, string.format("Cleaned up temporary data: %s", data_id))
    end
    
    return true
end

-- Clean up all resources
function _M.cleanup_all_resources(tracker, write_to_log)
    if not tracker then
        return 0
    end
    
    local cleaned_count = 0
    
    -- Clean up all memory buffers
    for buffer_id, _ in pairs(tracker.memory_buffers) do
        if _M.cleanup_memory_buffer(tracker, buffer_id, write_to_log) then
            cleaned_count = cleaned_count + 1
        end
    end
    
    -- Clean up all sockets
    for socket_id, _ in pairs(tracker.socket_connections) do
        if _M.cleanup_socket(tracker, socket_id, write_to_log) then
            cleaned_count = cleaned_count + 1
        end
    end
    
    -- Clean up all temporary data
    for data_id, _ in pairs(tracker.temporary_data) do
        if _M.cleanup_temporary_data(tracker, data_id, write_to_log) then
            cleaned_count = cleaned_count + 1
        end
    end
    
    -- Clean up threads
    for thread_id, thread_info in pairs(tracker.threads) do
        if thread_info.thread then
            -- Note: ngx.thread objects are automatically cleaned up by OpenResty
            tracker.threads[thread_id] = nil
            cleaned_count = cleaned_count + 1
        end
    end
    
    tracker.stats.total_resources_cleaned = tracker.stats.total_resources_cleaned + cleaned_count
    
    if write_to_log then
        write_to_log(ngx.INFO, string.format("Cleaned up all resources: %d items", cleaned_count))
    end
    
    return cleaned_count
end

-- Get resource statistics
function _M.get_resource_stats(tracker)
    if not tracker then
        return nil
    end
    
    local current_memory = _M.calculate_total_memory_usage(tracker)
    
    return {
        memory_buffers_count = _M.count_table_entries(tracker.memory_buffers),
        socket_connections_count = _M.count_table_entries(tracker.socket_connections),
        temporary_data_count = _M.count_table_entries(tracker.temporary_data),
        threads_count = _M.count_table_entries(tracker.threads),
        current_memory_usage = current_memory,
        peak_memory_usage = tracker.stats.peak_memory_usage,
        total_resources_created = tracker.stats.total_resources_created,
        total_resources_cleaned = tracker.stats.total_resources_cleaned,
        cleanup_operations = tracker.stats.cleanup_operations,
        tracker_age_seconds = ngx.now() - tracker.created_at,
        last_cleanup_seconds_ago = ngx.now() - tracker.last_cleanup
    }
end

-- Helper function to count table entries
function _M.count_table_entries(tbl)
    if not tbl then
        return 0
    end
    
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- Check if memory usage is above warning threshold
function _M.check_memory_warning(tracker)
    if not tracker then
        return false, 0
    end
    
    local current_usage = _M.calculate_total_memory_usage(tracker)
    local is_warning = current_usage > MEMORY_WARNING_THRESHOLD
    
    return is_warning, current_usage
end

-- Create memory-efficient resource pool
function _M.create_resource_pool(resource_type, max_pool_size, create_func, reset_func)
    local pool = {
        resources = {},
        resource_type = resource_type,
        max_size = max_pool_size or 10,
        current_size = 0,
        create_func = create_func,
        reset_func = reset_func,
        stats = {
            created_count = 0,
            reused_count = 0,
            destroyed_count = 0
        }
    }
    
    return {
        get_resource = function()
            if pool.current_size > 0 then
                local resource = pool.resources[pool.current_size]
                pool.resources[pool.current_size] = nil
                pool.current_size = pool.current_size - 1
                
                -- Reset resource if reset function provided
                if pool.reset_func then
                    pool.reset_func(resource)
                end
                
                pool.stats.reused_count = pool.stats.reused_count + 1
                return resource
            else
                -- Create new resource
                local resource = pool.create_func and pool.create_func() or {}
                pool.stats.created_count = pool.stats.created_count + 1
                return resource
            end
        end,
        
        return_resource = function(resource)
            if pool.current_size < pool.max_size and resource then
                pool.current_size = pool.current_size + 1
                pool.resources[pool.current_size] = resource
            else
                -- Pool is full, destroy resource
                pool.stats.destroyed_count = pool.stats.destroyed_count + 1
            end
        end,
        
        get_pool_stats = function()
            return {
                resource_type = pool.resource_type,
                current_size = pool.current_size,
                max_size = pool.max_size,
                stats = pool.stats
            }
        end,
        
        clear_pool = function()
            for i = 1, pool.current_size do
                pool.resources[i] = nil
            end
            pool.current_size = 0
            pool.stats.destroyed_count = pool.stats.destroyed_count + pool.current_size
        end
    }
end

-- Monitor resource usage and trigger cleanup if needed
function _M.monitor_and_cleanup(tracker, write_to_log)
    if not tracker then
        return false
    end
    
    local now = ngx.now()
    local should_cleanup = false
    
    -- Check if it's time for periodic cleanup
    if (now - tracker.last_cleanup) > CLEANUP_INTERVAL then
        should_cleanup = true
    end
    
    -- Check memory usage
    local is_memory_warning, current_memory = _M.check_memory_warning(tracker)
    if is_memory_warning then
        should_cleanup = true
        if write_to_log then
            write_to_log(ngx.WARN, string.format("Memory usage warning: %d bytes (threshold: %d bytes)", 
                                                current_memory, MEMORY_WARNING_THRESHOLD))
        end
    end
    
    -- Perform cleanup if needed
    if should_cleanup then
        local cleaned = _M.cleanup_expired_resources(tracker, 1800, write_to_log)  -- 30 minutes
        return cleaned > 0
    end
    
    return false
end

return _M