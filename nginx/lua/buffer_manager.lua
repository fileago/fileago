--[[
Copyright (c) 2018-2025 FileAgo Software Pvt Ltd. All Rights Reserved.

This software is proprietary and confidential.
Unauthorized copying of this file, via any medium, is strictly prohibited.

For license information, see the LICENSE.txt file in the root directory of
this project.
--]]

-- buffer_manager.lua: Hybrid buffer management for small and large files
-- Supports memory-based processing for small files and buffered approach for large files

local _M = {}

-- Configuration constants
local MEMORY_MODE_THRESHOLD = 100 * 1024 * 1024  -- 100MB - switch to hybrid mode above this
local MAX_MEMORY_BUFFER = 100 * 1024 * 1024      -- 100MB max in pure memory mode
local HYBRID_CHUNK_SIZE = 2 * 1024 * 1024        -- 2MB chunks for hybrid mode
local MAX_FILE_SIZE = 1024 * 1024 * 1024         -- 1GB absolute maximum
local YIELD_INTERVAL = 1024 * 1024               -- Yield every 1MB processed

-- Buffer modes
local BUFFER_MODE_MEMORY = "memory"
local BUFFER_MODE_HYBRID = "hybrid"

-- Create enhanced buffer with automatic mode selection
function _M.create_enhanced_buffer()
    return {
        mode = BUFFER_MODE_MEMORY,    -- Start in memory mode
        chunks = {},                  -- Memory chunks (memory mode)
        temp_file = nil,             -- Temporary file path (hybrid mode)
        temp_file_handle = nil,      -- File handle (hybrid mode)
        total_size = 0,              -- Total bytes stored
        memory_size = 0,             -- Bytes in memory
        disk_size = 0,               -- Bytes on disk
        mime_detected = false,       -- Whether MIME type has been detected
        mime_type = nil,             -- Detected MIME type
        mime_method = nil,           -- Detection method used
        filename = nil,              -- Original filename
        headers = {},                -- Multipart headers
        created_at = ngx.now(),      -- Creation timestamp
        last_access = ngx.now(),     -- Last access timestamp
        write_position = 0,          -- Current write position (hybrid mode)
        read_position = 0            -- Current read position (hybrid mode)
    }
end

-- Add chunk with automatic mode switching
function _M.add_chunk(buffer, data)
    if not buffer or not data then
        return nil, "invalid_parameters"
    end
    
    local chunk_size = #data
    local new_total_size = buffer.total_size + chunk_size
    
    -- Check absolute maximum file size
    if new_total_size > MAX_FILE_SIZE then
        return nil, "file_too_large"
    end
    
    -- Determine if we need to switch to hybrid mode
    if buffer.mode == BUFFER_MODE_MEMORY and new_total_size > MEMORY_MODE_THRESHOLD then
        local switch_ok, switch_err = _M.switch_to_hybrid_mode(buffer)
        if not switch_ok then
            return nil, "mode_switch_failed: " .. (switch_err or "unknown")
        end
    end
    
    -- Add chunk based on current mode
    if buffer.mode == BUFFER_MODE_MEMORY then
        return _M.add_chunk_memory(buffer, data)
    else
        return _M.add_chunk_hybrid(buffer, data)
    end
end

-- Add chunk in memory mode
function _M.add_chunk_memory(buffer, data)
    table.insert(buffer.chunks, data)
    buffer.total_size = buffer.total_size + #data
    buffer.memory_size = buffer.total_size
    buffer.last_access = ngx.now()
    return true
end

-- Add chunk in hybrid mode (write to temp file)
function _M.add_chunk_hybrid(buffer, data)
    if not buffer.temp_file_handle then
        return nil, "temp_file_not_initialized"
    end
    
    -- Write data to temp file (non-blocking write)
    local bytes_written, err = buffer.temp_file_handle:write(data)
    if not bytes_written then
        return nil, "temp_file_write_failed: " .. (err or "unknown")
    end
    
    -- Flush periodically to ensure data is written
    if buffer.total_size % (10 * 1024 * 1024) == 0 then  -- Every 10MB
        buffer.temp_file_handle:flush()
    end
    
    buffer.total_size = buffer.total_size + #data
    buffer.disk_size = buffer.total_size
    buffer.write_position = buffer.write_position + #data
    buffer.last_access = ngx.now()
    
    -- Yield control periodically
    if buffer.total_size % YIELD_INTERVAL == 0 then
        ngx.sleep(0)
    end
    
    return true
end

-- Switch from memory mode to hybrid mode
function _M.switch_to_hybrid_mode(buffer)
    if buffer.mode ~= BUFFER_MODE_MEMORY then
        return true  -- Already in hybrid mode
    end
    
    -- Create temporary file
    local temp_file = "/tmp/upload_hybrid_" .. ngx.worker.pid() .. "_" .. ngx.now() .. "_" .. math.random(1000, 9999)
    local file_handle, err = io.open(temp_file, "wb")
    if not file_handle then
        return nil, "temp_file_creation_failed: " .. (err or "unknown")
    end
    
    -- Write existing memory chunks to temp file
    for _, chunk in ipairs(buffer.chunks) do
        local bytes_written, write_err = file_handle:write(chunk)
        if not bytes_written then
            file_handle:close()
            os.remove(temp_file)
            return nil, "temp_file_write_failed: " .. (write_err or "unknown")
        end
    end
    
    file_handle:flush()
    
    -- Update buffer state
    buffer.mode = BUFFER_MODE_HYBRID
    buffer.temp_file = temp_file
    buffer.temp_file_handle = file_handle
    buffer.disk_size = buffer.total_size
    buffer.memory_size = 0
    buffer.write_position = buffer.total_size
    
    -- Clear memory chunks to free memory
    buffer.chunks = {}
    
    return true
end

-- Get preview data (works in both modes)
function _M.get_preview_data(buffer, preview_size)
    if not buffer then
        return ""
    end
    
    local size = preview_size or 1024
    
    if buffer.mode == BUFFER_MODE_MEMORY then
        return _M.get_preview_data_memory(buffer, size)
    else
        return _M.get_preview_data_hybrid(buffer, size)
    end
end

-- Get preview data from memory mode
function _M.get_preview_data_memory(buffer, preview_size)
    local preview = ""
    local remaining = preview_size
    
    for _, chunk in ipairs(buffer.chunks) do
        if remaining <= 0 then
            break
        end
        
        local take = math.min(#chunk, remaining)
        preview = preview .. chunk:sub(1, take)
        remaining = remaining - take
    end
    
    buffer.last_access = ngx.now()
    return preview
end

-- Get preview data from hybrid mode
function _M.get_preview_data_hybrid(buffer, preview_size)
    if not buffer.temp_file then
        return ""
    end
    
    -- Open temp file for reading
    local read_handle = io.open(buffer.temp_file, "rb")
    if not read_handle then
        return ""
    end
    
    local preview = read_handle:read(preview_size) or ""
    read_handle:close()
    
    buffer.last_access = ngx.now()
    return preview
end

-- Create reader iterator (works in both modes)
function _M.create_reader_iterator(buffer, start_offset)
    if not buffer then
        return function() return nil end
    end
    
    if buffer.mode == BUFFER_MODE_MEMORY then
        return _M.create_reader_iterator_memory(buffer, start_offset)
    else
        return _M.create_reader_iterator_hybrid(buffer, start_offset)
    end
end

-- Create reader iterator for memory mode
function _M.create_reader_iterator_memory(buffer, start_offset)
    local chunk_index = 1
    local chunk_offset = 1
    local bytes_skipped = 0
    local start_pos = start_offset or 0
    
    -- Skip to start position if specified
    while chunk_index <= #buffer.chunks and bytes_skipped < start_pos do
        local current_chunk = buffer.chunks[chunk_index]
        local chunk_size = #current_chunk
        
        if bytes_skipped + chunk_size <= start_pos then
            bytes_skipped = bytes_skipped + chunk_size
            chunk_index = chunk_index + 1
            chunk_offset = 1
        else
            chunk_offset = start_pos - bytes_skipped + 1
            bytes_skipped = start_pos
            break
        end
    end
    
    return function(read_size)
        if chunk_index > #buffer.chunks then
            return nil  -- EOF
        end
        
        local result = ""
        local remaining = read_size or HYBRID_CHUNK_SIZE
        
        while remaining > 0 and chunk_index <= #buffer.chunks do
            local current_chunk = buffer.chunks[chunk_index]
            local available = #current_chunk - chunk_offset + 1
            local take = math.min(remaining, available)
            
            result = result .. current_chunk:sub(chunk_offset, chunk_offset + take - 1)
            remaining = remaining - take
            chunk_offset = chunk_offset + take
            
            if chunk_offset > #current_chunk then
                chunk_index = chunk_index + 1
                chunk_offset = 1
            end
        end
        
        buffer.last_access = ngx.now()
        return #result > 0 and result or nil
    end
end

-- Create reader iterator for hybrid mode
function _M.create_reader_iterator_hybrid(buffer, start_offset)
    if not buffer.temp_file then
        return function() return nil end
    end
    
    -- Open temp file for reading
    local read_handle = io.open(buffer.temp_file, "rb")
    if not read_handle then
        return function() return nil end
    end
    
    -- Seek to start position
    if start_offset and start_offset > 0 then
        read_handle:seek("set", start_offset)
    end
    
    local bytes_read = start_offset or 0
    
    return function(read_size)
        if bytes_read >= buffer.total_size then
            read_handle:close()
            return nil  -- EOF
        end
        
        local size = read_size or HYBRID_CHUNK_SIZE
        local remaining_bytes = buffer.total_size - bytes_read
        local actual_size = math.min(size, remaining_bytes)
        
        local data = read_handle:read(actual_size)
        if not data then
            read_handle:close()
            return nil
        end
        
        bytes_read = bytes_read + #data
        buffer.last_access = ngx.now()
        
        -- Yield control periodically for large reads
        if bytes_read % YIELD_INTERVAL == 0 then
            ngx.sleep(0)
        end
        
        return data
    end
end

-- Get buffer statistics
function _M.get_buffer_stats(buffer)
    if not buffer then
        return nil
    end
    
    return {
        mode = buffer.mode,
        total_size = buffer.total_size,
        memory_size = buffer.memory_size,
        disk_size = buffer.disk_size,
        chunk_count = #buffer.chunks,
        temp_file = buffer.temp_file,
        mime_type = buffer.mime_type,
        mime_detected = buffer.mime_detected,
        filename = buffer.filename,
        age_seconds = ngx.now() - buffer.created_at,
        last_access_seconds = ngx.now() - buffer.last_access
    }
end

-- Validate buffer integrity
function _M.validate_buffer(buffer)
    if not buffer then
        return false, "buffer_is_nil"
    end
    
    if buffer.mode == BUFFER_MODE_MEMORY then
        return _M.validate_buffer_memory(buffer)
    else
        return _M.validate_buffer_hybrid(buffer)
    end
end

-- Validate memory mode buffer
function _M.validate_buffer_memory(buffer)
    if not buffer.chunks then
        return false, "chunks_array_missing"
    end
    
    local calculated_size = 0
    for i, chunk in ipairs(buffer.chunks) do
        if type(chunk) ~= "string" then
            return false, "invalid_chunk_type_at_index_" .. i
        end
        calculated_size = calculated_size + #chunk
    end
    
    if calculated_size ~= buffer.total_size then
        return false, "size_mismatch_calculated_" .. calculated_size .. "_stored_" .. buffer.total_size
    end
    
    return true
end

-- Validate hybrid mode buffer
function _M.validate_buffer_hybrid(buffer)
    if not buffer.temp_file then
        return false, "temp_file_missing"
    end
    
    -- Check if temp file exists and has correct size
    local file_handle = io.open(buffer.temp_file, "rb")
    if not file_handle then
        return false, "temp_file_not_accessible"
    end
    
    file_handle:seek("end")
    local file_size = file_handle:seek()
    file_handle:close()
    
    if file_size ~= buffer.total_size then
        return false, "file_size_mismatch_file_" .. file_size .. "_buffer_" .. buffer.total_size
    end
    
    return true
end

-- Clear buffer data and cleanup
function _M.clear_buffer(buffer)
    if not buffer then
        return
    end
    
    -- Clear memory chunks
    if buffer.chunks then
        for i = 1, #buffer.chunks do
            buffer.chunks[i] = nil
        end
        buffer.chunks = {}
    end
    
    -- Close and remove temp file
    if buffer.temp_file_handle then
        buffer.temp_file_handle:close()
        buffer.temp_file_handle = nil
    end
    
    if buffer.temp_file then
        os.remove(buffer.temp_file)
        buffer.temp_file = nil
    end
    
    -- Reset buffer state
    buffer.total_size = 0
    buffer.memory_size = 0
    buffer.disk_size = 0
    buffer.mime_detected = false
    buffer.mime_type = nil
    buffer.filename = nil
    buffer.headers = {}
end

-- Estimate memory usage
function _M.estimate_memory_usage(buffer)
    if not buffer then
        return 0
    end
    
    local base_overhead = 500  -- Base object overhead
    
    if buffer.mode == BUFFER_MODE_MEMORY then
        -- Memory mode: count actual data + overhead
        local data_size = buffer.memory_size
        local chunk_overhead = #buffer.chunks * 24
        return base_overhead + data_size + chunk_overhead
    else
        -- Hybrid mode: minimal memory usage
        return base_overhead + 1024  -- Just metadata
    end
end

-- Get configuration info
function _M.get_config_info()
    return {
        memory_mode_threshold = MEMORY_MODE_THRESHOLD,
        max_memory_buffer = MAX_MEMORY_BUFFER,
        hybrid_chunk_size = HYBRID_CHUNK_SIZE,
        max_file_size = MAX_FILE_SIZE,
        yield_interval = YIELD_INTERVAL
    }
end

return _M