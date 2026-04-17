--!strict
--[[
    SilkDiff HttpClient Module

    Handles all HTTP communication between the Roblox Studio plugin
    and the local SilkDiff server running on the user's machine.

    The base URL is built from Settings.ServerHost and Settings.ServerPort.

    Endpoints used:
        GET  /api/status   → Check if the server is reachable
        POST /api/push     → Push serialized changes to local files
        GET  /api/pull     → Pull local file state into Roblox
        POST /api/diff     → Request a diff (Roblox state vs local files)
        POST /api/export   → Full game export to local files
        POST /api/confirm  → Confirm / apply a pending diff

    Usage:
        local HttpClient = require(...)
        local client = HttpClient.new(settings)

        if client:ping() then
            local ok, response = client:push(data)
        end
]]

local HttpService = game:GetService("HttpService")

local HttpClient = {}
HttpClient.__index = HttpClient

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------
function HttpClient.new(settings)
    local self = setmetatable({}, HttpClient)
    self._settings  = settings
    self._connected = false
    self._console   = nil  -- set later via :setConsole() to avoid circular deps
    return self
end

---------------------------------------------------------------------------
-- Inject a Console instance for debug logging (called after both are init'd)
---------------------------------------------------------------------------
function HttpClient:setConsole(console)
    self._console = console
end

---------------------------------------------------------------------------
-- Internal: emit a debug log if DebugMode is on
---------------------------------------------------------------------------
function HttpClient:_debug(msg: string)
    if self._settings:get("DebugMode") ~= "true" then return end
    if self._console then
        self._console:log(msg, "info")
    else
        print("[SilkDiff DEBUG] " .. msg)
    end
end

---------------------------------------------------------------------------
-- Internal: build the base URL from current settings
---------------------------------------------------------------------------
function HttpClient:_getBaseUrl(): string
    return self._settings:getServerUrl()
end

---------------------------------------------------------------------------
-- Internal: perform a GET request and return (success, data)
---------------------------------------------------------------------------
function HttpClient:_get(endpoint: string): (boolean, any)
    local base: string = tostring(self:_getBaseUrl())
    local url = base .. endpoint

    self:_debug("GET " .. url)

    local ok, raw = pcall(function()
        return HttpService:GetAsync(url)
    end)

    if not ok then
        warn("[SilkDiff] GET " .. endpoint .. " failed:", raw)
        self._connected = false
        return false, raw
    end

    self:_debug("GET " .. endpoint .. " → " .. tostring(raw):sub(1, 200))

    -- Try to decode JSON; fall back to raw string
    local decodeOk, parsed = pcall(function()
        return HttpService:JSONDecode(raw)
    end)

    return true, if decodeOk then parsed else raw
end

---------------------------------------------------------------------------
-- Internal: perform a POST request with a JSON body
---------------------------------------------------------------------------
function HttpClient:_post(endpoint: string, data: any): (boolean, any)
    local base: string = tostring(self:_getBaseUrl())
    local url  = base .. endpoint
    local body = HttpService:JSONEncode(data)

    self:_debug("POST " .. endpoint .. " body=" .. body:sub(1, 300))

    local ok, raw = pcall(function()
        return HttpService:PostAsync(url, body, Enum.HttpContentType.ApplicationJson)
    end)

    if not ok then
        warn("[SilkDiff] POST " .. endpoint .. " failed:", raw)
        self._connected = false
        return false, raw
    end

    self:_debug("POST " .. endpoint .. " → " .. tostring(raw):sub(1, 200))

    local decodeOk, parsed = pcall(function()
        return HttpService:JSONDecode(raw)
    end)

    return true, if decodeOk then parsed else raw
end

---------------------------------------------------------------------------
-- Ping the server to check if it's reachable
---------------------------------------------------------------------------
function HttpClient:ping(): boolean
    local ok, _ = self:_get("/api/status")
    self._connected = ok
    return ok
end

---------------------------------------------------------------------------
-- Push changes from Roblox → local machine
---------------------------------------------------------------------------
function HttpClient:push(data: any): (boolean, any)
    return self:_post("/api/push", {
        action    = "push",
        timestamp = os.time(),
        data      = data,
    })
end

---------------------------------------------------------------------------
-- Pull changes from local machine → Roblox.
-- Pass the serialized current Roblox state so the server can compute
-- a proper diff (local files vs Roblox) and return diff entries.
---------------------------------------------------------------------------
function HttpClient:pull(robloxState: { any }): (boolean, any)
    return self:_post("/api/pull", {
        action    = "pull",
        timestamp = os.time(),
        data      = robloxState,
    })
end

---------------------------------------------------------------------------
-- Request a diff between the current Roblox state and local files
---------------------------------------------------------------------------
function HttpClient:requestDiff(localData: any): (boolean, any)
    return self:_post("/api/diff", {
        action    = "diff",
        timestamp = os.time(),
        data      = localData,
    })
end

---------------------------------------------------------------------------
-- Send a full export of the entire game to the server
---------------------------------------------------------------------------
function HttpClient:fullExport(treeData: any): (boolean, any)
    return self:_post("/api/export", {
        action    = "export",
        timestamp = os.time(),
        data      = treeData,
    })
end

---------------------------------------------------------------------------
-- Confirm / apply a pending diff the user approved
---------------------------------------------------------------------------
function HttpClient:confirmDiff(diff: any): (boolean, any)
    return self:_post("/api/confirm", {
        action    = "confirm",
        timestamp = os.time(),
        diff      = diff,
    })
end

---------------------------------------------------------------------------
-- Check whether the last connection attempt succeeded
---------------------------------------------------------------------------
function HttpClient:isConnected(): boolean
    return self._connected
end

return HttpClient
