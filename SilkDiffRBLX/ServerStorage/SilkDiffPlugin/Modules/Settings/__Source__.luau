--!strict
--[[
    SilkDiff Settings Module

    Manages all plugin settings with persistent storage.
    Settings are saved using Roblox's plugin:GetSetting / SetSetting API
    so they survive across Studio sessions.

    ┌─────────────────────────┬──────────────────────────────────────────┐
    │ Setting                 │ Description                              │
    ├─────────────────────────┼──────────────────────────────────────────┤
    │ ServerHost              │ Host address for the SilkDiff server     │
    │ ServerPort              │ Port for the SilkDiff server             │
    │ PropertiesExtension     │ File extension for property files        │
    │ SourceExtension         │ File extension for source code files     │
    │ PropertiesFileName      │ Base name of properties files            │
    │ AttributesFileName      │ Base name of attributes files            │
    │ TagsFileName            │ Base name of tags files                  │
    │ SourceFileName          │ Base name of source code files           │
    └─────────────────────────┴──────────────────────────────────────────┘

    Usage:
        local Settings = require(...)
        local settings = Settings.new(plugin)

        settings:get("ServerHost")          --> "127.0.0.1"
        settings:set("ServerPort", 8080)
        settings:getAll()                   --> { ServerHost = ..., ... }
        settings:getServerUrl()             --> "http://127.0.0.1:8080"
]]

local Settings = {}
Settings.__index = Settings

---------------------------------------------------------------------------
-- Default values for all settings
---------------------------------------------------------------------------
local DEFAULTS = {
    ServerHost         = "127.0.0.1",
    ServerPort         = 6969,
    PropertiesExtension = ".yaml",
    SourceExtension    = ".luau",
    PropertiesFileName = "__Properties__",
    AttributesFileName = "__Attributes__",
    TagsFileName       = "__Tags__",
    SourceFileName     = "__Source__",
    UseInstanceIds     = "true",   -- track instances by SilkDiffId attribute instead of path
    UseConsole         = "true",   -- route all logs to the SilkDiff console instead of Studio Output
    DebugMode          = "false",  -- log raw HTTP request/response bodies to the console
}

---------------------------------------------------------------------------
-- Valid choices for dropdown-style settings
---------------------------------------------------------------------------
local VALID_CHOICES = {
    PropertiesExtension = { ".yaml", ".json" },
    SourceExtension     = { ".luau", ".lua", ".txt" },
    UseInstanceIds      = { "false", "true" },
    UseConsole          = { "false", "true" },
    DebugMode           = { "false", "true" },
}

---------------------------------------------------------------------------
-- Setting metadata for the UI (label text shown to the user)
---------------------------------------------------------------------------
local SETTING_LABELS = {
    ServerHost         = "Server Host",
    ServerPort         = "Server Port",
    PropertiesExtension = "Properties Extension",
    SourceExtension    = "Source Extension",
    PropertiesFileName = "Properties File Name",
    AttributesFileName = "Attributes File Name",
    TagsFileName       = "Tags File Name",
    SourceFileName     = "Source File Name",
    UseInstanceIds     = "Track Instances by ID",
    UseConsole         = "Use SilkDiff Console (suppress Studio Output)",
    DebugMode          = "Debug Mode (log HTTP traffic)",
}

---------------------------------------------------------------------------
-- Longer explanations shown in the help window
---------------------------------------------------------------------------
local SETTING_DESCRIPTIONS = {
    ServerHost = "The IP address the SilkDiff server listens on. " ..
        "127.0.0.1 means only this computer can connect, which is the safe default.",
    ServerPort = "The TCP port the SilkDiff server listens on. " ..
        "Make sure it matches the port you used when starting the server (default 6969).",
    PropertiesExtension = "File format used for property, attribute, and tag files. " ..
        ".yaml is human-readable; .json is also supported.",
    SourceExtension = "The file extension for script source code on disk. " ..
        "Choose .luau, .lua, or .txt depending on your editor setup.",
    PropertiesFileName = "Base name of the file containing instance properties " ..
        "(defaults to __Properties__).",
    AttributesFileName = "Base name of the file containing instance attributes " ..
        "(defaults to __Attributes__).",
    TagsFileName = "Base name of the file containing CollectionService tags " ..
        "(defaults to __Tags__).",
    SourceFileName = "Base name of the file containing script source " ..
        "(defaults to __Source__).",
    UseInstanceIds = "When enabled, instances are matched by a SilkDiffId attribute " ..
        "instead of their folder path. This keeps renames and moves in sync correctly.",
    UseConsole = "Route all SilkDiff log output to the in-Studio console panel " ..
        "instead of the Studio Output window.",
    DebugMode = "Log raw HTTP request and response bodies to the console. " ..
        "Enable this when troubleshooting sync issues.",
}

--- The display order of settings in the UI
local SETTING_ORDER = {
    "ServerHost",
    "ServerPort",
    "PropertiesExtension",
    "SourceExtension",
    "PropertiesFileName",
    "AttributesFileName",
    "TagsFileName",
    "SourceFileName",
    "UseInstanceIds",
    "UseConsole",
    "DebugMode",
}

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------
function Settings.new(pluginInstance: Plugin)
    local self = setmetatable({}, Settings)
    self._plugin = pluginInstance
    self._values = {}
    self._changeCallbacks = {}

    -- Load saved settings (or fall back to defaults)
    self:_loadAll()

    return self
end

---------------------------------------------------------------------------
-- Internal: Load all settings from plugin storage
---------------------------------------------------------------------------
function Settings:_loadAll()
    for key, default in pairs(DEFAULTS) do
        local saved = self._plugin:GetSetting("SilkDiff_" .. key)
        if saved ~= nil then
            self._values[key] = saved
        else
            self._values[key] = default
        end
    end
end

---------------------------------------------------------------------------
-- Get a single setting value by key
---------------------------------------------------------------------------
function Settings:get(key: string): any
    return self._values[key] or DEFAULTS[key]
end

---------------------------------------------------------------------------
-- Set a single setting value and persist it
---------------------------------------------------------------------------
function Settings:set(key: string, value: any)
    -- Make sure the setting key actually exists
    if DEFAULTS[key] == nil then
        warn("[SilkDiff] Unknown setting key: " .. key)
        return
    end

    -- Validate dropdown-type settings
    if VALID_CHOICES[key] then
        local isValid = false
        for _, choice in ipairs(VALID_CHOICES[key]) do
            if choice == value then
                isValid = true
                break
            end
        end
        if not isValid then
            warn("[SilkDiff] Invalid value for " .. key .. ": " .. tostring(value))
            return
        end
    end

    -- Save the value
    local oldValue = self._values[key]
    self._values[key] = value
    self._plugin:SetSetting("SilkDiff_" .. key, value)

    -- Notify change listeners
    if oldValue ~= value then
        for _, callback in ipairs(self._changeCallbacks) do
            task.spawn(callback, key, value, oldValue)
        end
    end
end

---------------------------------------------------------------------------
-- Get all settings as a table
---------------------------------------------------------------------------
function Settings:getAll(): { [string]: any }
    local result = {}
    for key, _ in pairs(DEFAULTS) do
        result[key] = self:get(key)
    end
    return result
end

---------------------------------------------------------------------------
-- Get the default value table (copy)
---------------------------------------------------------------------------
function Settings:getDefaults(): { [string]: any }
    return table.clone(DEFAULTS)
end

---------------------------------------------------------------------------
-- Get valid choices for a dropdown setting (or nil if not a dropdown)
---------------------------------------------------------------------------
function Settings:getChoices(key: string): { string }?
    return VALID_CHOICES[key]
end

---------------------------------------------------------------------------
-- Get the human-readable label for a setting key
---------------------------------------------------------------------------
function Settings:getLabel(key: string): string
    return SETTING_LABELS[key] or key
end

---------------------------------------------------------------------------
-- Get the longer explanation for a setting key (shown in the help window)
---------------------------------------------------------------------------
function Settings:getDescription(key: string): string
    return SETTING_DESCRIPTIONS[key] or ""
end

---------------------------------------------------------------------------
-- Get the ordered list of setting keys (for UI rendering)
---------------------------------------------------------------------------
function Settings:getSettingOrder(): { string }
    return table.clone(SETTING_ORDER)
end

---------------------------------------------------------------------------
-- Reset all settings back to their defaults
---------------------------------------------------------------------------
function Settings:resetToDefaults()
    for key, default in pairs(DEFAULTS) do
        self:set(key, default)
    end
end

---------------------------------------------------------------------------
-- Register a callback that fires whenever a setting changes
-- Callback signature: (key: string, newValue: any, oldValue: any) -> ()
---------------------------------------------------------------------------
function Settings:onChange(callback: (key: string, newValue: any, oldValue: any) -> ())
    table.insert(self._changeCallbacks, callback)
end

---------------------------------------------------------------------------
-- Build the full server URL from host + port settings
---------------------------------------------------------------------------
function Settings:getServerUrl(): string
    local host = tostring(self:get("ServerHost"))
    local port = tostring(self:get("ServerPort"))
    return "http://" .. host .. ":" .. port
end

return Settings
