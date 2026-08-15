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
-- Internal: emit a debug log if DebugMode is on.
-- kind = "req" | "res" | "err"  controls the colour.
-- data may be a JSON string – it's pretty-printed line-by-line.
---------------------------------------------------------------------------
function HttpClient:_debug(kind: string, label: string, body: string?)
    if self._settings:get("DebugMode") ~= "true" then return end

    -- Header line colour per kind
    local headerColor, icon
    if kind == "req" then
        headerColor = "rgb(100,180,255)"  -- blue  → outgoing request
        icon        = "→"
    elseif kind == "res" then
        headerColor = "rgb(100,220,130)"  -- green → incoming response
        icon        = "←"
    else
        headerColor = "rgb(240,100,100)"  -- red   → error
        icon        = "✗"
    end

    local header = string.format('<font color="%s">%s %s</font>', headerColor, icon, label)
    if self._console then
        self._console:logRaw(header)
    else
        print("[SilkDiff DEBUG] " .. icon .. " " .. label)
    end

    -- Pretty-print the JSON body if provided
    if body and body ~= "" then
        -- Try to decode and re-encode with indentation via our own pretty-printer
        local ok, parsed = pcall(function()
            return game:GetService("HttpService"):JSONDecode(body)
        end)
        local lines: { string }
        if ok then
            lines = HttpClient._prettyLines(parsed, 0)
        else
            -- Not valid JSON – just split on commas/braces for readability
            lines = { body }
        end
        for _, line in ipairs(lines) do
            local escaped = line
                :gsub("<", "&lt;")
                :gsub(">", "&gt;")
            local colored = string.format('<font color="rgb(190,190,130)">%s</font>', escaped)
            if self._console then
                self._console:logRaw(colored)
            else
                print("  " .. line)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Internal: recursive pretty-printer, returns a list of indented strings
---------------------------------------------------------------------------
function HttpClient._prettyLines(val: any, depth: number): { string }
    local indent  = string.rep("  ", depth)
    local indent1 = string.rep("  ", depth + 1)
    local lines: { string } = {}

    if type(val) == "table" then
        -- Detect array vs dict
        local isArray = true
        local maxN = 0
        for k in pairs(val) do
            if type(k) ~= "number" then isArray = false; break end
            if k > maxN then maxN = k end
        end
        isArray = isArray and maxN == #val

        if isArray then
            table.insert(lines, indent .. "[")
            for _, v in ipairs(val) do
                local sub = HttpClient._prettyLines(v, depth + 1)
                for _, sl in ipairs(sub) do table.insert(lines, sl) end
            end
            table.insert(lines, indent .. "]")
        else
            table.insert(lines, indent .. "{")
            local keys = {}
            for k in pairs(val) do table.insert(keys, k) end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for _, k in ipairs(keys) do
                local sub = HttpClient._prettyLines(val[k], depth + 1)
                if #sub == 1 then
                    table.insert(lines, indent1 .. tostring(k) .. ": " .. sub[1]:gsub("^%s+", ""))
                else
                    table.insert(lines, indent1 .. tostring(k) .. ":")
                    for _, sl in ipairs(sub) do table.insert(lines, sl) end
                end
            end
            table.insert(lines, indent .. "}")
        end
    elseif type(val) == "string" then
        table.insert(lines, indent .. '"' .. val .. '"')
    elseif val == nil then
        table.insert(lines, indent .. "null")
    else
        table.insert(lines, indent .. tostring(val))
    end

    return lines
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

    self:_debug("req", "GET " .. url)

    local ok, result = pcall(function()
        return HttpService:RequestAsync({
            Url = url,
            Method = "GET",
            Timeout = 30,
        })
    end)

    if not ok or not result.Success then
        local msg = if ok then (result.StatusMessage or "Unknown") else tostring(result)
        self:_debug("err", "GET " .. endpoint .. " failed", msg)
        self._connected = false
        return false, msg
    end

    local responseBody = result.Body or ""

    self:_debug("res", "GET " .. endpoint .. " " .. tostring(result.StatusCode), responseBody)

    -- Try to decode JSON; fall back to raw string
    local decodeOk, parsed = pcall(function()
        return HttpService:JSONDecode(responseBody)
    end)

    self._connected = true
    return true, if decodeOk then parsed else responseBody
end

---------------------------------------------------------------------------
-- Internal: perform a POST request with a JSON body
---------------------------------------------------------------------------
function HttpClient:_post(endpoint: string, data: any): (boolean, any)
    local base: string = tostring(self:_getBaseUrl())
    local url  = base .. endpoint
    local body = HttpService:JSONEncode(data)

    self:_debug("req", "POST " .. endpoint, body)

    local ok, result = pcall(function()
        return HttpService:RequestAsync({
            Url = url,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
            },
            Body = body,
            Timeout = 30,
        })
    end)

    if not ok or not result.Success then
        local msg = if ok then (result.StatusMessage or "Unknown") else tostring(result)
        self:_debug("err", "POST " .. endpoint .. " failed", msg)
        self._connected = false
        return false, msg
    end

    local responseBody = result.Body or ""

    self:_debug("res", "POST " .. endpoint .. " " .. tostring(result.StatusCode), responseBody)

    -- Try to decode JSON; fall back to raw string
    local decodeOk, parsed = pcall(function()
        return HttpService:JSONDecode(responseBody)
    end)

    if result.StatusCode >= 400 then
        self._connected = false
        local errMsg = if decodeOk then (parsed.error or tostring(result.StatusCode)) else tostring(result.StatusCode)
        return false, errMsg
    end

    return true, if decodeOk then parsed else responseBody
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
-- Request a diff between the current Roblox state and local files.
-- `full` – when true the server also reports local instances that are
-- missing from the Roblox state (used by Force Push to catch deletions).
---------------------------------------------------------------------------
function HttpClient:requestDiff(localData: any, full: boolean?): (boolean, any)
    return self:_post("/api/diff", {
        action    = "diff",
        timestamp = os.time(),
        data      = localData,
        full      = full == true,
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
