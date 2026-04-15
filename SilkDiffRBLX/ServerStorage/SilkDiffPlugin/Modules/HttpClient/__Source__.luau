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
    return self
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

    local ok, raw = pcall(function()
        return HttpService:GetAsync(url)
    end)

    if not ok then
        warn("[SilkDiff] GET " .. endpoint .. " failed:", raw)
        self._connected = false
        return false, raw
    end

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

    local ok, raw = pcall(function()
        return HttpService:PostAsync(url, body, Enum.HttpContentType.ApplicationJson)
    end)

    if not ok then
        warn("[SilkDiff] POST " .. endpoint .. " failed:", raw)
        self._connected = false
        return false, raw
    end

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
-- Pull changes from local machine → Roblox
---------------------------------------------------------------------------
function HttpClient:pull(): (boolean, any)
    return self:_get("/api/pull")
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
