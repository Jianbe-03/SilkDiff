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

local HttpService = game:GetService("HttpService")

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

    --- SilkDiffIds we've seen, used to detect duplicates immediately
    self._seenIds = {} :: { [string]: boolean }

    --- Deleted instances captured before they're destroyed
    --- { [path]: { path: string, silkId: string, className: string } }
    self._deletedInstances = {} :: { [string]: any }

    return self
end

---------------------------------------------------------------------------
-- Internal: assign a fresh SilkDiffId to an instance (used to break
-- duplicates when Roblox copies the original's attributes on duplicate)
---------------------------------------------------------------------------
function InstanceWatcher:_regenerateSilkId(instance: Instance)
    local newId = HttpService:GenerateGUID(false)
    instance:SetAttribute("SilkDiffId", newId)
    self._seenIds[newId] = true
end

---------------------------------------------------------------------------
-- Internal: register an instance's SilkDiffId, regenerating it if it's
-- already been seen (i.e. this instance is a duplicate of another).
---------------------------------------------------------------------------
function InstanceWatcher:_registerSilkId(instance: Instance)
    local id = instance:GetAttribute("SilkDiffId")
    if typeof(id) ~= "string" or id == "" then
        return
    end
    if self._seenIds[id] then
        -- Duplicate! Give it a fresh id right away
        self:_regenerateSilkId(instance)
    else
        self._seenIds[id] = true
    end
end

---------------------------------------------------------------------------
-- Internal: is this instance a Roblox service (i.e. a legit direct child
-- of game)? Only services can live directly under game.
---------------------------------------------------------------------------
function InstanceWatcher._isServiceInstance(instance: Instance): boolean
    if instance == game then return true end
    -- Services are children of game and can be looked up via GetService
    local ok, svc = pcall(function()
        return game:GetService(instance.Name)
    end)
    return ok and svc == instance
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
-- Internal: Mark a newly-added instance (and all its descendants) as
-- changed so they appear in the diff as "added" entries.
---------------------------------------------------------------------------
function InstanceWatcher:_recordNewInstance(instance: Instance)
    self:_recordChange(instance, "Added", nil)
    for _, descendant in ipairs(instance:GetDescendants()) do
        self:_recordChange(descendant, "Added", nil)
    end
end

---------------------------------------------------------------------------
-- Internal: drop changed-instance entries for a deleted subtree.
-- *instances* were captured while the subtree was still alive. Used after
-- a deletion to remove stale property-change entries (e.g. Roblox setting
-- Parent to game while destroying the instance) so they aren't reported
-- as moves alongside the deletion.
---------------------------------------------------------------------------
function InstanceWatcher:_dropDeletedSubtree(
    root: Instance,
    instances: { [Instance]: boolean }
)
    if self._changedInstances[root] then
        self._changedInstances[root] = nil
    end
    for descendant, _ in pairs(self._changedInstances) do
        if instances[descendant] then
            self._changedInstances[descendant] = nil
        end
    end
end

---------------------------------------------------------------------------
-- Internal: Hook up change listeners on a single instance
---------------------------------------------------------------------------
function InstanceWatcher:_watchInstance(instance: Instance)
    -- Register this instance's SilkDiffId so duplicates are caught as
    -- soon as they appear (Roblox copies attributes on duplicate).
    self:_registerSilkId(instance)

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
        -- If the new child is a duplicate (shares a SilkDiffId with an
        -- existing instance), give it a fresh id immediately
        self:_registerSilkId(child)
        -- A regenerated id shows up as an attribute change; record it
        self:_recordChange(instance, "ChildAdded", child.Name)
        -- Record the new child (and its descendants) so they appear in the diff
        self:_recordNewInstance(child)
        -- Also start watching the new child + its descendants
        self:_watchInstance(child)
        self:_watchDescendants(child)
    end)
    table.insert(self._connections, addConn)

    -- Removed children
    local removeConn = instance.ChildRemoved:Connect(function(child: Instance)
        -- Capture path + identity NOW before the parent reference is cleared
        local childPath = self.getInstancePath(self, child)
        local childSilk = child:GetAttribute("SilkDiffId")
        local childClass = child.ClassName
        -- Capture every instance in the subtree while they're alive
        local subtreeInstances: { [Instance]: boolean } = { [child] = true }
        for _, desc in ipairs(child:GetDescendants()) do
            subtreeInstances[desc] = true
        end
        -- Defer one frame: if Parent is nil the child was truly deleted,
        -- otherwise it was just reparented (moved) elsewhere.
        task.defer(function()
            local parent = child.Parent
            if parent == nil then
                -- Genuinely deleted – record on the parent so it shows in diffs
                self:_recordChange(instance, "ChildDeleted", childPath)
                -- Remember it so a push can report the removal to the server
                self._deletedInstances[childPath] = {
                    path = childPath,
                    silkId = if typeof(childSilk) == "string" then childSilk else "",
                    className = childClass,
                }
                -- Drop any earlier property-change entries for this child
                -- (e.g. Roblox setting Parent to game while destroying it),
                -- otherwise the push would report a move instead of a deletion.
                self:_dropDeletedSubtree(child, subtreeInstances)
            elseif parent == game then
                -- Roblox moves deleted instances to game briefly before
                -- destroying them; a non-service child parented to game is
                -- effectively deleted (only services live directly under game).
                if InstanceWatcher._isServiceInstance(child) then
                    self:_recordChange(parent, "ChildMoved", childPath)
                else
                    self:_recordChange(instance, "ChildDeleted", childPath)
                    self._deletedInstances[childPath] = {
                        path = childPath,
                        silkId = if typeof(childSilk) == "string" then childSilk else "",
                        className = childClass,
                    }
                    self:_dropDeletedSubtree(child, subtreeInstances)
                end
            else
                -- Reparented/moved – record as moved on the child's new parent
                self:_recordChange(parent, "ChildMoved", childPath)
            end
        end)
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

    print("[SilkDiff] InstanceWatcher started - watching " .. #WATCHED_SERVICES .. " services")
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

    -- Include deleted instances (they can't be serialized from the live
    -- tree anymore, so we send the captured path + silk id instead)
    for _, deleted in pairs(self._deletedInstances) do
        table.insert(result, {
            instance  = nil,
            deleted   = true,
            path      = deleted.path,
            silkId    = deleted.silkId,
            className = deleted.className,
            changes   = { { changeType = "ChildDeleted", timestamp = os.clock() } },
            firstSeen = os.clock(),
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
    return next(self._changedInstances) ~= nil or next(self._deletedInstances) ~= nil
end

---------------------------------------------------------------------------
-- Count how many distinct instances have been changed
---------------------------------------------------------------------------
function InstanceWatcher:getChangeCount(): number
    local count = 0
    for _ in pairs(self._changedInstances) do
        count += 1
    end
    for _ in pairs(self._deletedInstances) do
        count += 1
    end
    return count
end

---------------------------------------------------------------------------
-- Clear all recorded changes (call after a successful push)
---------------------------------------------------------------------------
function InstanceWatcher:clearChanges()
    self._changedInstances = {}
    self._deletedInstances = {}
end

---------------------------------------------------------------------------
-- Get the list of service names currently being watched
---------------------------------------------------------------------------
function InstanceWatcher:getWatchedServices(): { string }
    return table.clone(WATCHED_SERVICES)
end

return InstanceWatcher
