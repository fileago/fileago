--[[
Copyright (c) 2018-2025 FileAgo Software Pvt Ltd. All Rights Reserved.

This software is proprietary and confidential.
Unauthorized copying of this file, via any medium, is strictly prohibited.

For license information, see the LICENSE.txt file in the root directory of
this project.
--]]

-- Configuration module for ICAP and backend settings

local _M = {}

-- Helper function to get environment variable with a default value
local function env_or_default(env_var, default)
    local value = os.getenv(env_var)
    return value ~= nil and value or default
end

-- ICAP Server Configuration
_M.icap_server_host = env_or_default("ICAP_SERVER_HOST", "clamcap")
_M.icap_server_port = tonumber(env_or_default("ICAP_SERVER_PORT", "1344"))
_M.icap_service_name = env_or_default("ICAP_SERVICE_NAME", "avscan")

-- Construct ICAP URL
_M.icap_url = string.format("icap://%s:%d/%s", 
    _M.icap_server_host, 
    _M.icap_server_port, 
    _M.icap_service_name
)

-- Upload and Timeout Configuration
_M.chunk_size = tonumber(env_or_default("UPLOAD_CHUNK_SIZE", "4096"))
_M.upload_timeout = tonumber(env_or_default("UPLOAD_TIMEOUT", "5000"))
_M.socket_timeout = tonumber(env_or_default("SOCKET_TIMEOUT", "5000"))

-- Preview Configuration
_M.preview_size = tonumber(env_or_default("ICAP_PREVIEW_SIZE", "1024"))

-- Backend Configuration
_M.backend_protocol = env_or_default("BACKEND_PROTOCOL", "http")
_M.backend_host = env_or_default("BACKEND_HOST", "dms")
_M.backend_port = tonumber(env_or_default("BACKEND_PORT", "8080"))

-- Logging Configuration (setting to false will still log ERR)
_M.log_icap_traffic = env_or_default("LOG_ICAP_TRAFFIC", false)

-- Mime Type Verification (recommended: true)
_M.check_mime_type = env_or_default("CHECK_MIME_TYPE", true)

-- Allowed File Extensions (comma-separated, empty allows all) e.g.: ".txt,.pdf,.docx"
_M.allowed_extensions = env_or_default("ALLOWED_EXTENSIONS", "")

-- Limits exeeded behaviour (allow/block). Used to decide behaviour when Clamav returns 
-- 403 with header "Heuristics.Limits.Exceeded.MaxFileSize" for very large files. Setting
-- it to "allow" will bypass scan on very large files, and setting it to "block" will
-- prevent files larger than MaxScanSize & MaxFileSize limits in clamd.conf
-- from being uploaded successfully (recommended: block).
_M.limits_exceeded_behaviour = env_or_default("LIMITS_EXCEEDED_BEHAVIOUR", "block")

-- Generate backend URL function
function _M.get_backend_url(req_uri)
    req_uri = req_uri or "/"
    
    -- Determine if port should be included
    local port_str = ""
    if not (((_M.backend_protocol == "http" and _M.backend_port == 80) or
             (_M.backend_protocol == "https" and _M.backend_port == 443))) then
        port_str = string.format(":%d", _M.backend_port)
    end
    
    return string.format("%s://%s%s%s",
        _M.backend_protocol,
        _M.backend_host,
        port_str,
        req_uri
    )
end

return _M
