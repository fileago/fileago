--[[
Copyright (c) 2018-2025 FileAgo Software Pvt Ltd. All Rights Reserved.

This software is proprietary and confidential.
Unauthorized copying of this file, via any medium, is strictly prohibited.

For license information, see the LICENSE.txt file in the root directory of
this project.
--]]

-- mime_detector.lua: Non-blocking MIME type detection using magic numbers
-- This module provides fast, non-blocking MIME type detection for common file types

local _M = {}

-- Magic number patterns for common file types
-- Each pattern includes the binary signature and corresponding MIME type
-- IMPORTANT: Order matters - more specific patterns should come first
local MAGIC_PATTERNS = {
    -- Documents (check these first before generic patterns)
    {pattern = "^%%PDF", mime = "application/pdf", name = "PDF"},
    {pattern = "^\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1", mime = "application/msword", name = "MS Office (legacy)"},
    
    -- Office Open XML documents (more specific PK patterns first)
    {pattern = "^PK\x03\x04.{26}%[Content_Types%]%.xml", mime = "application/vnd.openxmlformats-officedocument.wordprocessingml.document", name = "DOCX (Content_Types)"},
    {pattern = "^PK\x03\x04.*word/document%.xml", mime = "application/vnd.openxmlformats-officedocument.wordprocessingml.document", name = "DOCX"},
    {pattern = "^PK\x03\x04.*xl/workbook%.xml", mime = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", name = "XLSX"},
    {pattern = "^PK\x03\x04.*ppt/presentation%.xml", mime = "application/vnd.openxmlformats-officedocument.presentationml.presentation", name = "PPTX"},
    {pattern = "^PK\x03\x04.*META%-INF/MANIFEST%.MF", mime = "application/java-archive", name = "JAR"},
    
    -- Images
    {pattern = "^\xFF\xD8\xFF", mime = "image/jpeg", name = "JPEG"},
    {pattern = "^\x89PNG\r\n\x1A\n", mime = "image/png", name = "PNG"},
    {pattern = "^GIF8[79]a", mime = "image/gif", name = "GIF"},
    {pattern = "^RIFF....WEBP", mime = "image/webp", name = "WebP"},
    {pattern = "^BM", mime = "image/bmp", name = "BMP"},
    {pattern = "^II\x2A\x00", mime = "image/tiff", name = "TIFF (little-endian)"},
    {pattern = "^MM\x00\x2A", mime = "image/tiff", name = "TIFF (big-endian)"},
    
    -- Archives
    {pattern = "^PK\x03\x04", mime = "application/zip", name = "ZIP"},
    {pattern = "^PK\x05\x06", mime = "application/zip", name = "ZIP (empty)"},
    {pattern = "^PK\x07\x08", mime = "application/zip", name = "ZIP (spanned)"},
    {pattern = "^Rar!", mime = "application/x-rar-compressed", name = "RAR"},
    {pattern = "^\x1F\x8B", mime = "application/gzip", name = "GZIP"},
    {pattern = "^7z\xBC\xAF\x27\x1C", mime = "application/x-7z-compressed", name = "7-Zip"},
    {pattern = "^\x42\x5A\x68", mime = "application/x-bzip2", name = "BZIP2"},
    {pattern = "^\xFD7zXZ\x00", mime = "application/x-xz", name = "XZ"},
    
    -- Media - Audio
    {pattern = "^ID3", mime = "audio/mpeg", name = "MP3 (ID3)"},
    {pattern = "^\xFF\xFB", mime = "audio/mpeg", name = "MP3"},
    {pattern = "^\xFF\xF3", mime = "audio/mpeg", name = "MP3"},
    {pattern = "^\xFF\xF2", mime = "audio/mpeg", name = "MP3"},
    {pattern = "^OggS", mime = "audio/ogg", name = "OGG"},
    {pattern = "^RIFF....WAVE", mime = "audio/wav", name = "WAV"},
    {pattern = "^fLaC", mime = "audio/flac", name = "FLAC"},
    {pattern = "^\x4D\x34\x41\x20", mime = "audio/mp4", name = "M4A"},
    
    -- Media - Video
    {pattern = "^\x00\x00\x00\x20ftypmp4", mime = "video/mp4", name = "MP4"},
    {pattern = "^\x00\x00\x00\x18ftypmp4", mime = "video/mp4", name = "MP4"},
    {pattern = "^ftypmp4", mime = "video/mp4", name = "MP4"},
    {pattern = "^RIFF....AVI ", mime = "video/x-msvideo", name = "AVI"},
    {pattern = "^\x1A\x45\xDF\xA3", mime = "video/webm", name = "WebM/MKV"},
    {pattern = "^\x00\x00\x01\xBA", mime = "video/mpeg", name = "MPEG"},
    {pattern = "^\x00\x00\x01\xB3", mime = "video/mpeg", name = "MPEG"},
    
    -- Text/Code (case-insensitive patterns)
    {pattern = "^<html", mime = "text/html", name = "HTML", case_insensitive = true},
    {pattern = "^<!DOCTYPE html", mime = "text/html", name = "HTML5", case_insensitive = true},
    {pattern = "^<\\?xml", mime = "application/xml", name = "XML", case_insensitive = true},
    {pattern = "^{", mime = "application/json", name = "JSON (simple)"},
    {pattern = "^%[", mime = "application/json", name = "JSON (array)"},
    
    -- Executables
    {pattern = "^MZ", mime = "application/x-msdownload", name = "Windows PE"},
    {pattern = "^\x7FELF", mime = "application/x-executable", name = "Linux ELF"},
    {pattern = "^\xCA\xFE\xBA\xBE", mime = "application/java-vm", name = "Java Class"},
    {pattern = "^\xFE\xED\xFA\xCE", mime = "application/x-mach-binary", name = "Mach-O (32-bit)"},
    {pattern = "^\xFE\xED\xFA\xCF", mime = "application/x-mach-binary", name = "Mach-O (64-bit)"},
    
    -- Fonts
    {pattern = "^\x00\x01\x00\x00", mime = "font/ttf", name = "TrueType Font"},
    {pattern = "^OTTO", mime = "font/otf", name = "OpenType Font"},
    {pattern = "^wOFF", mime = "font/woff", name = "WOFF Font"},
    {pattern = "^wOF2", mime = "font/woff2", name = "WOFF2 Font"},
    
    -- ICO pattern (moved to end and made very specific to avoid false matches)
    -- ICO files have a very specific structure: 00 00 01 00 [count] 00 [width] [height] [colors] 00 [planes] 00 [bitcount] 00
    {pattern = "^\x00\x00\x01\x00[\x01-\x20]\x00[\x10-\xFF][\x10-\xFF]", mime = "image/x-icon", name = "ICO"},
}

-- Common text file extensions for fallback detection
local TEXT_EXTENSIONS = {
    [".txt"] = "text/plain",
    [".log"] = "text/plain",
    [".md"] = "text/markdown",
    [".json"] = "application/json",
    [".xml"] = "application/xml",
    [".html"] = "text/html",
    [".htm"] = "text/html",
    [".css"] = "text/css",
    [".js"] = "application/javascript",
    [".ts"] = "application/typescript",
    [".py"] = "text/x-python",
    [".lua"] = "text/x-lua",
    [".sh"] = "application/x-sh",
    [".sql"] = "application/sql",
    [".csv"] = "text/csv",
    [".yaml"] = "application/x-yaml",
    [".yml"] = "application/x-yaml",
}

-- Detect MIME type from binary data using magic numbers
function _M.detect_mime_type(data_chunk, filename)
    if not data_chunk or #data_chunk < 4 then
        return nil, "insufficient_data"
    end
    
    -- Ensure we have enough data for pattern matching
    local check_size = math.min(#data_chunk, 1024)  -- Increased to 1KB for better Office detection
    local data_sample = data_chunk:sub(1, check_size)
    
    -- First, check if it's clearly text content (before binary patterns)
    if _M.is_text_content(data_sample) then
        -- Try to determine text type from filename extension
        if filename then
            local ext = filename:lower():match("(%.[^%.]+)$")
            if ext and TEXT_EXTENSIONS[ext] then
                return TEXT_EXTENSIONS[ext], "text_extension", "Text file by extension"
            end
        end
        return "text/plain", "text_analysis", "Text content detected"
    end
    
    -- Convert to lowercase for case-insensitive matching
    local data_lower = data_sample:lower()
    
    -- Check magic number patterns (binary files)
    for _, pattern_info in ipairs(MAGIC_PATTERNS) do
        local test_data = pattern_info.case_insensitive and data_lower or data_sample
        if test_data:match(pattern_info.pattern) then
            return pattern_info.mime, "magic_number", pattern_info.name
        end
    end
    
    -- Final fallback for unknown files
    return "application/octet-stream", "fallback", "Unknown binary file"
end

-- Check if content appears to be text
function _M.is_text_content(data)
    if not data or #data == 0 then
        return false
    end
    
    local text_chars = 0
    local total_chars = math.min(#data, 512)  -- Check first 512 bytes
    local null_bytes = 0
    local control_chars = 0
    
    for i = 1, total_chars do
        local byte = data:byte(i)
        
        -- Count null bytes (strong indicator of binary)
        if byte == 0 then
            null_bytes = null_bytes + 1
        -- Count other control characters (except common whitespace)
        elseif byte < 32 and byte ~= 9 and byte ~= 10 and byte ~= 13 then
            control_chars = control_chars + 1
        -- Count printable ASCII, common whitespace, and UTF-8 bytes
        elseif (byte >= 32 and byte <= 126) or  -- Printable ASCII
               byte == 9 or byte == 10 or byte == 13 or  -- Tab, LF, CR
               (byte >= 128 and byte <= 191) or  -- UTF-8 continuation bytes
               (byte >= 194 and byte <= 244) then  -- UTF-8 start bytes
            text_chars = text_chars + 1
        end
    end
    
    -- If more than 1% are null bytes, it's likely binary
    if null_bytes / total_chars > 0.01 then
        return false
    end
    
    -- If more than 10% are control characters, it's likely binary
    if control_chars / total_chars > 0.10 then
        return false
    end
    
    -- If more than 90% are text characters, consider it text
    return (text_chars / total_chars) > 0.90
end

-- Non-blocking external MIME type detection using file command
function _M.detect_mime_type_external_blocking(file_data)
    if not file_data or #file_data < 32 then
        return nil, "insufficient_data"
    end
    
    -- Create temporary file for external command
    local tmp_file = "/tmp/mime_check_" .. ngx.worker.pid() .. "_" .. ngx.now() .. "_" .. math.random(1000, 9999)
    
    local f = io.open(tmp_file, "wb")
    if not f then
        return nil, "temp_file_creation_failed"
    end
    
    -- Write first 16KB for detection (enough for most formats)
    f:write(file_data:sub(1, math.min(#file_data, 16384)))
    f:close()
    
    -- Execute file command with timeout protection
    local handle = io.popen("timeout 2s file --mime-type -b " .. tmp_file .. " 2>/dev/null")
    if not handle then
        os.remove(tmp_file)
        return nil, "command_execution_failed"
    end
    
    local mime_type = handle:read("*a")
    local exit_code = handle:close()
    os.remove(tmp_file)
    
    if mime_type and mime_type ~= "" and exit_code then
        mime_type = mime_type:gsub("\n$", ""):gsub("\r$", ""):gsub("%s+$", "")
        
        -- Filter out generic results that aren't helpful
        if mime_type ~= "application/octet-stream" and
           mime_type ~= "text/plain" and
           not mime_type:find("data") then
            return mime_type, "file_command"
        elseif mime_type == "text/plain" then
            return mime_type, "file_command"
        end
    end
    
    return nil, "no_specific_mime_detected"
end

-- Legacy non-blocking function (kept for compatibility)
function _M.detect_mime_type_external(file_data, callback)
    local mime_type, method = _M.detect_mime_type_external_blocking(file_data)
    callback(mime_type, method and nil or "detection_failed", method)
end

-- Comprehensive MIME type detection with file command priority
function _M.detect_mime_comprehensive(data_chunk, filename, use_external_fallback)
    -- PRIORITY 1: Use file command for maximum accuracy (if enabled)
    if use_external_fallback and data_chunk and #data_chunk >= 32 then
        local external_mime, external_method = _M.detect_mime_type_external_blocking(data_chunk)
        if external_mime and external_mime ~= "application/octet-stream" then
            return external_mime, external_method, "File command (accurate)"
        end
    end
    
    -- PRIORITY 2: Magic number detection (fast fallback)
    local mime_type, method, details = _M.detect_mime_type(data_chunk, filename)
    if mime_type and mime_type ~= "application/octet-stream" then
        return mime_type, method, details
    end
    
    -- PRIORITY 3: Extension-based detection for text files
    if filename then
        local ext = filename:lower():match("(%.[^%.]+)$")
        if ext and TEXT_EXTENSIONS[ext] then
            return TEXT_EXTENSIONS[ext], "extension_fallback", "Extension-based detection"
        end
    end
    
    -- Final fallback: application/octet-stream for unknown binary files
    return "application/octet-stream", "fallback", "Unknown binary file"
end

-- Validate detected MIME type against Content-Type header
function _M.validate_mime_type(detected_mime, header_mime)
    if not detected_mime or not header_mime then
        return false, "missing_mime_types"
    end
    
    -- Normalize MIME types for comparison
    local detected_normalized = detected_mime:lower():gsub("%s+", "")
    local header_normalized = header_mime:lower():gsub("%s+", ""):gsub(";.*", "")  -- Remove parameters
    
    -- Generic MIME types that should accept any detected type
    local generic_types = {
        "application/octet-stream",
        "application/binary",
        "binary/octet-stream"
    }
    
    -- If header is generic, trust the detected type
    for _, generic_type in ipairs(generic_types) do
        if header_normalized == generic_type then
            return true, "generic_header_override"
        end
    end
    
    -- Direct match
    if detected_normalized == header_normalized then
        return true, "exact_match"
    end
    
    -- Check for common aliases
    local mime_aliases = {
        ["application/x-msdownload"] = {"application/octet-stream", "application/exe"},
        ["image/jpeg"] = {"image/jpg"},
        ["application/javascript"] = {"text/javascript"},
        ["application/x-sh"] = {"text/x-shellscript"},
        ["text/plain"] = {"application/octet-stream"},  -- Sometimes text files are sent as binary
        -- Enhanced aliases for Office documents
        ["application/vnd.openxmlformats-officedocument.wordprocessingml.document"] = {"application/octet-stream"},
        ["application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"] = {"application/octet-stream"},
        ["application/vnd.openxmlformats-officedocument.presentationml.presentation"] = {"application/octet-stream"},
        ["application/pdf"] = {"application/octet-stream"},
    }
    
    if mime_aliases[detected_normalized] then
        for _, alias in ipairs(mime_aliases[detected_normalized]) do
            if alias == header_normalized then
                return true, "alias_match"
            end
        end
    end
    
    -- Check reverse aliases
    for canonical, aliases in pairs(mime_aliases) do
        if canonical == header_normalized then
            for _, alias in ipairs(aliases) do
                if alias == detected_normalized then
                    return true, "reverse_alias_match"
                end
            end
        end
    end
    
    return false, "mime_mismatch"
end

-- Debug function to help troubleshoot MIME detection issues
function _M.debug_mime_detection(data_chunk, filename)
    if not data_chunk then
        return {
            error = "no_data_provided",
            data_length = 0
        }
    end
    
    local debug_info = {
        data_length = #data_chunk,
        filename = filename,
        first_32_bytes_hex = "",
        first_32_bytes_ascii = "",
        is_text = _M.is_text_content(data_chunk),
        detected_mime = nil,
        detection_method = nil,
        detection_details = nil,
        pattern_matches = {}
    }
    
    -- Generate hex and ASCII representation of first 32 bytes
    local sample_size = math.min(32, #data_chunk)
    for i = 1, sample_size do
        local byte = data_chunk:byte(i)
        debug_info.first_32_bytes_hex = debug_info.first_32_bytes_hex .. string.format("%02X ", byte)
        if byte >= 32 and byte <= 126 then
            debug_info.first_32_bytes_ascii = debug_info.first_32_bytes_ascii .. string.char(byte)
        else
            debug_info.first_32_bytes_ascii = debug_info.first_32_bytes_ascii .. "."
        end
    end
    
    -- Test all patterns and record matches
    local check_size = math.min(#data_chunk, 1024)
    local data_sample = data_chunk:sub(1, check_size)
    local data_lower = data_sample:lower()
    
    for i, pattern_info in ipairs(MAGIC_PATTERNS) do
        local test_data = pattern_info.case_insensitive and data_lower or data_sample
        if test_data:match(pattern_info.pattern) then
            table.insert(debug_info.pattern_matches, {
                index = i,
                pattern = pattern_info.pattern,
                mime = pattern_info.mime,
                name = pattern_info.name,
                case_insensitive = pattern_info.case_insensitive or false
            })
        end
    end
    
    -- Get the actual detection result
    debug_info.detected_mime, debug_info.detection_method, debug_info.detection_details =
        _M.detect_mime_type(data_chunk, filename)
    
    return debug_info
end

-- Helper function to format debug info for logging
function _M.format_debug_info(debug_info)
    local lines = {
        string.format("MIME Debug Info:"),
        string.format("  File: %s", debug_info.filename or "unknown"),
        string.format("  Data length: %d bytes", debug_info.data_length),
        string.format("  First 32 bytes (hex): %s", debug_info.first_32_bytes_hex),
        string.format("  First 32 bytes (ascii): %s", debug_info.first_32_bytes_ascii),
        string.format("  Is text content: %s", tostring(debug_info.is_text)),
        string.format("  Detected MIME: %s", debug_info.detected_mime or "none"),
        string.format("  Detection method: %s", debug_info.detection_method or "none"),
        string.format("  Detection details: %s", debug_info.detection_details or "none"),
        string.format("  Pattern matches: %d", #debug_info.pattern_matches)
    }
    
    for i, match in ipairs(debug_info.pattern_matches) do
        table.insert(lines, string.format("    %d. %s -> %s (%s)",
                                         match.index, match.name, match.mime, match.pattern))
    end
    
    return table.concat(lines, "\n")
end

return _M