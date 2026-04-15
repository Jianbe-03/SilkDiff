--!strict
--[[
    SilkDiff DiffEngine Module

    Compares two states of instance data and produces human-readable diffs.
    Used to show the user exactly what will change before a push or pull.

    Diff entry statuses:
        "added"    – Instance exists in the new state but not the old
        "removed"  – Instance exists in the old state but not the new
        "modified" – Instance exists in both but has differences

    Usage:
        local DiffEngine = require(...)
        local engine = DiffEngine.new()

        local diffs   = engine:compareTrees(oldTree, newTree)
        local summary = engine:summarize(diffs)
]]

local DiffEngine = {}
DiffEngine.__index = DiffEngine

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------
function DiffEngine.new()
    return setmetatable({}, DiffEngine)
end

---------------------------------------------------------------------------
-- Compare two flat property / attribute dictionaries.
-- Returns: { [key] = { old, new, changeType } }
---------------------------------------------------------------------------
function DiffEngine:compareProperties(
    oldProps: { [string]: any }?,
    newProps: { [string]: any }?
): { [string]: any }
    local changes: { [string]: any } = {}
    local old = oldProps or {}
    local new = newProps or {}

    -- Modified or removed keys
    for key, oldValue in pairs(old) do
        local newValue = new[key]
        if newValue == nil then
            changes[key] = { old = oldValue, new = nil, changeType = "removed" }
        elseif tostring(oldValue) ~= tostring(newValue) then
            changes[key] = { old = oldValue, new = newValue, changeType = "modified" }
        end
    end

    -- Added keys
    for key, newValue in pairs(new) do
        if old[key] == nil then
            changes[key] = { old = nil, new = newValue, changeType = "added" }
        end
    end

    return changes
end

---------------------------------------------------------------------------
-- Compare two tag lists.
-- Returns: { added = { string }, removed = { string } }
---------------------------------------------------------------------------
function DiffEngine:compareTags(
    oldTags: { string }?,
    newTags: { string }?
): { added: { string }, removed: { string } }
    local oldSet: { [string]: boolean } = {}
    for _, tag in ipairs(oldTags or {}) do
        oldSet[tag] = true
    end

    local newSet: { [string]: boolean } = {}
    for _, tag in ipairs(newTags or {}) do
        newSet[tag] = true
    end

    local added: { string }   = {}
    local removed: { string } = {}

    for _, tag in ipairs(newTags or {}) do
        if not oldSet[tag] then
            table.insert(added, tag)
        end
    end

    for _, tag in ipairs(oldTags or {}) do
        if not newSet[tag] then
            table.insert(removed, tag)
        end
    end

    return { added = added, removed = removed }
end

---------------------------------------------------------------------------
-- Compare two serialized instances (without children).
-- Returns a diff entry table, or nil if nothing changed.
---------------------------------------------------------------------------
function DiffEngine:compareInstances(
    oldInstance: { [string]: any }?,
    newInstance: { [string]: any }?
): { [string]: any }?
    -- Added
    if oldInstance == nil and newInstance ~= nil then
        return {
            path      = newInstance.path,
            name      = newInstance.name,
            className = newInstance.className,
            status    = "added",
        }
    end

    -- Removed
    if oldInstance ~= nil and newInstance == nil then
        return {
            path      = oldInstance.path,
            name      = oldInstance.name,
            className = oldInstance.className,
            status    = "removed",
        }
    end

    if oldInstance == nil or newInstance == nil then
        return nil
    end

    -- Compare every aspect
    local propChanges = self:compareProperties(oldInstance.properties, newInstance.properties)
    local attrChanges = self:compareProperties(oldInstance.attributes, newInstance.attributes)
    local tagChanges  = self:compareTags(oldInstance.tags, newInstance.tags)
    local sourceChanged = (oldInstance.source ~= newInstance.source)

    local hasPropChanges = next(propChanges) ~= nil
    local hasAttrChanges = next(attrChanges) ~= nil
    local hasTagChanges  = #tagChanges.added > 0 or #tagChanges.removed > 0

    -- If nothing actually changed, return nil
    if not hasPropChanges and not hasAttrChanges and not hasTagChanges and not sourceChanged then
        return nil
    end

    return {
        path             = newInstance.path,
        name             = newInstance.name,
        className        = newInstance.className,
        status           = "modified",
        propertyChanges  = if hasPropChanges then propChanges else nil,
        attributeChanges = if hasAttrChanges then attrChanges else nil,
        tagChanges       = if hasTagChanges then tagChanges else nil,
        sourceChanged    = sourceChanged,
        oldSource        = if sourceChanged then oldInstance.source else nil,
        newSource        = if sourceChanged then newInstance.source else nil,
    }
end

---------------------------------------------------------------------------
-- Recursively compare two full instance trees.
-- Returns a flat list of all diff entries.
---------------------------------------------------------------------------
function DiffEngine:compareTrees(
    oldTree: { [string]: any }?,
    newTree: { [string]: any }?
): { any }
    local diffs: { any } = {}

    -- Compare root nodes
    local rootDiff = self:compareInstances(oldTree, newTree)
    if rootDiff then
        table.insert(diffs, rootDiff)
    end

    -- Build child lookup tables keyed by path
    local oldChildren: { [string]: any } = {}
    local newChildren: { [string]: any } = {}

    if oldTree and oldTree.children then
        for _, child in ipairs(oldTree.children) do
            oldChildren[child.path] = child
        end
    end

    if newTree and newTree.children then
        for _, child in ipairs(newTree.children) do
            newChildren[child.path] = child
        end
    end

    -- Merge all child paths and recurse
    local allPaths: { [string]: boolean } = {}
    for path in pairs(oldChildren) do allPaths[path] = true end
    for path in pairs(newChildren) do allPaths[path] = true end

    for path in pairs(allPaths) do
        local childDiffs = self:compareTrees(oldChildren[path], newChildren[path])
        for _, diff in ipairs(childDiffs) do
            table.insert(diffs, diff)
        end
    end

    return diffs
end

---------------------------------------------------------------------------
-- Generate a one-line human-readable summary of a diff list
---------------------------------------------------------------------------
function DiffEngine:summarize(diffs: { any }): string
    if #diffs == 0 then
        return "No changes detected."
    end

    local added    = 0
    local removed  = 0
    local modified = 0

    for _, diff in ipairs(diffs) do
        if diff.status == "added" then
            added += 1
        elseif diff.status == "removed" then
            removed += 1
        elseif diff.status == "modified" then
            modified += 1
        end
    end

    local parts: { string } = {}
    if added > 0 then    table.insert(parts, tostring(added) .. " added") end
    if modified > 0 then table.insert(parts, tostring(modified) .. " modified") end
    if removed > 0 then  table.insert(parts, tostring(removed) .. " removed") end

    return table.concat(parts, ", ") .. " (" .. #diffs .. " total)"
end

return DiffEngine
