--!strict
--[[
    SilkDiff InstanceWatcher Module

    Watches all instances in the game tree for changes and keeps a
    running log of everything that was modified since the last sync.

    Tracked change types:
        PropertyChanged  – A property value on an instance changed
        AttributeChanged – An attribute was added, changed, or removed
        ChildAdded       – A new child instance appeared
        ChildRemoved     – A child instance was deleted

    Usage:
        local InstanceWatcher = require(...)
        local watcher = InstanceWatcher.new()

        watcher:startWatching()              -- begin tracking
        local changes = watcher:getChangedInstances()
        watcher:clearChanges()               -- reset after a push
        watcher:stopWatching()               -- disconnect everything
]]

local InstanceWatcher = {}
InstanceWatcher.__index = InstanceWatcher

---------------------------------------------------------------------------
-- Services that we watch for changes.
-- These are the main containers where game content lives.
---------------------------------------------------------------------------
local WATCHED_SERVICES = {
    "Workspace",
    "Players",
    "Lighting",
    "MaterialService",
    "ReplicatedFirst",
    "ReplicatedStorage",
    "ServerScriptService",
    "ServerStorage",
    "StarterGui",
    "StarterPack",
    "StarterPlayer",
    "Teams",
    "SoundService",
    "TextChatService",
    "LocalizationService",
    "TestService",
    "VoiceChatService",
    "VRService",
}

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------
function InstanceWatcher.new()
    local self = setmetatable({}, InstanceWatcher)

    --- Map of Instance → change data
    --- { [Instance]: { changes: { ChangeEntry }, firstSeen: number } }
    self._changedInstances = {} :: { [Instance]: any }

    --- All active RBXScriptConnections (for bulk disconnect)
    self._connections = {} :: { RBXScriptConnection }

    --- Whether the watcher is currently active
    self._watching = false

    return self
end

---------------------------------------------------------------------------
-- Get the full dot-separated path of an instance
-- Example: "Workspace.Models.Tree"
---------------------------------------------------------------------------
function InstanceWatcher.getInstancePath(_self: any, instance: Instance): string
    local parts: { string } = {}
    local current: Instance? = instance

    while current and current ~= game do
        table.insert(parts, 1, current.Name)
        current = current.Parent
    end

    return table.concat(parts, ".")
end

---------------------------------------------------------------------------
-- Internal: Record a change for a given instance
---------------------------------------------------------------------------
function InstanceWatcher:_recordChange(instance: Instance, changeType: string, details: string?)
    if not self._changedInstances[instance] then
        self._changedInstances[instance] = {
            changes = {},
            firstSeen = os.clock(),
        }
    end

    table.insert(self._changedInstances[instance].changes, {
        changeType = changeType,
        details = details,
        timestamp = os.clock(),
    })
end

---------------------------------------------------------------------------
-- Internal: Hook up change listeners on a single instance
---------------------------------------------------------------------------
function InstanceWatcher:_watchInstance(instance: Instance)
    -- Property changes (fires with the property name)
    local propConn = instance.Changed:Connect(function(propertyName: string)
        self:_recordChange(instance, "PropertyChanged", propertyName)
    end)
    table.insert(self._connections, propConn)

    -- Attribute changes (fires with the attribute name)
    local attrConn = instance.AttributeChanged:Connect(function(attributeName: string)
        self:_recordChange(instance, "AttributeChanged", attributeName)
    end)
    table.insert(self._connections, attrConn)

    -- New children
    local addConn = instance.ChildAdded:Connect(function(child: Instance)
        self:_recordChange(instance, "ChildAdded", child.Name)
        -- Also start watching the new child + its descendants
        self:_watchInstance(child)
        self:_watchDescendants(child)
    end)
    table.insert(self._connections, addConn)

    -- Removed children
    local removeConn = instance.ChildRemoved:Connect(function(child: Instance)
        self:_recordChange(instance, "ChildRemoved", child.Name)
    end)
    table.insert(self._connections, removeConn)
end

---------------------------------------------------------------------------
-- Internal: Recursively watch all descendants of an instance
---------------------------------------------------------------------------
function InstanceWatcher:_watchDescendants(root: Instance)
    for _, descendant in ipairs(root:GetDescendants()) do
        self:_watchInstance(descendant)
    end
end

---------------------------------------------------------------------------
-- Start watching all configured game services for changes
---------------------------------------------------------------------------
function InstanceWatcher:startWatching()
    if self._watching then
        warn("[SilkDiff] InstanceWatcher is already active")
        return
    end

    self._watching = true

    for _, serviceName in ipairs(WATCHED_SERVICES) do
        local ok, service = pcall(function()
            return game:GetService(serviceName)
        end)

        if ok and service then
            self:_watchInstance(service)
            self:_watchDescendants(service)
        end
    end

    print("[SilkDiff] InstanceWatcher started — watching " .. #WATCHED_SERVICES .. " services")
end

---------------------------------------------------------------------------
-- Stop watching (disconnect every connection)
---------------------------------------------------------------------------
function InstanceWatcher:stopWatching()
    for _, connection in ipairs(self._connections) do
        connection:Disconnect()
    end
    self._connections = {}
    self._watching = false

    print("[SilkDiff] InstanceWatcher stopped")
end

---------------------------------------------------------------------------
-- Get all changed instances as a sorted list.
-- Each entry: { instance, path, changes, firstSeen }
---------------------------------------------------------------------------
function InstanceWatcher:getChangedInstances(): { any }
    local result = {}

    for instance, data in pairs(self._changedInstances) do
        table.insert(result, {
            instance  = instance,
            path      = self:getInstancePath(instance),
            changes   = data.changes,
            firstSeen = data.firstSeen,
        })
    end

    -- Sort alphabetically by path for deterministic ordering
    table.sort(result, function(a: { path: string }, b: { path: string })
        return a.path < b.path
    end)

    return result
end

---------------------------------------------------------------------------
-- Quick boolean check: are there any pending changes?
---------------------------------------------------------------------------
function InstanceWatcher:hasChanges(): boolean
    return next(self._changedInstances) ~= nil
end

---------------------------------------------------------------------------
-- Count how many distinct instances have been changed
---------------------------------------------------------------------------
function InstanceWatcher:getChangeCount(): number
    local count = 0
    for _ in pairs(self._changedInstances) do
        count += 1
    end
    return count
end

---------------------------------------------------------------------------
-- Clear all recorded changes (call after a successful push)
---------------------------------------------------------------------------
function InstanceWatcher:clearChanges()
    self._changedInstances = {}
end

---------------------------------------------------------------------------
-- Get the list of service names currently being watched
---------------------------------------------------------------------------
function InstanceWatcher:getWatchedServices(): { string }
    return table.clone(WATCHED_SERVICES)
end

return InstanceWatcher
