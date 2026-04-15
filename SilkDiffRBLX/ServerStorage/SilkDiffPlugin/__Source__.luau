--!nonstrict
--[[
    ╔══════════════════════════════════════════════════════════════╗
    ║                    SilkDiff Plugin                          ║
    ║  Syncs Roblox instances with local files using diffs.       ║
    ╚══════════════════════════════════════════════════════════════╝

    How it works:
        1. The InstanceWatcher monitors the game tree for any changes
        2. When you click "Push", changed instances are serialized and
           sent to the local SilkDiff server via HTTP
        3. The server generates a diff against your local files
        4. You review the diff in the Diff Viewer and approve or cancel
        5. On approval the server writes the changes to disk

    The same works in reverse with "Pull" — local file changes are
    diffed against the current Roblox state and applied on approval.

    Modules (under Modules/):
        Signal          – Lightweight custom event system
        Settings        – 8 configurable options, persisted across sessions
        InstanceWatcher – Watches game services for property/attribute/child changes
        Serializer      – Converts instances into JSON-safe dictionaries
        HttpClient      – Talks to the local SilkDiff Python server
        DiffEngine      – Compares two states and produces diff entries
        UI              – Toolbar, Settings panel, Diff Viewer
]]

---------------------------------------------------------------------------
-- Plugin toolbar (shows up in the Studio ribbon)
---------------------------------------------------------------------------
local toolbar = plugin:CreateToolbar("SilkDiff")

---------------------------------------------------------------------------
-- Load all modules
---------------------------------------------------------------------------
local Modules         = script:WaitForChild("Modules")
local Settings        = require(Modules:WaitForChild("Settings"))
local InstanceWatcher = require(Modules:WaitForChild("InstanceWatcher"))
local Serializer      = require(Modules:WaitForChild("Serializer"))
local HttpClient      = require(Modules:WaitForChild("HttpClient"))
local DiffEngine      = require(Modules:WaitForChild("DiffEngine"))
local UI              = require(Modules:WaitForChild("UI"))

---------------------------------------------------------------------------
-- Initialise everything
---------------------------------------------------------------------------
local settings        = Settings.new(plugin)
local httpClient      = HttpClient.new(settings)
local serializer      = Serializer.new(settings)
local diffEngine      = DiffEngine.new()
local instanceWatcher = InstanceWatcher.new()
local ui              = UI.new(plugin, toolbar, settings)

print("[SilkDiff] Plugin loaded!")

---------------------------------------------------------------------------
-- PUSH  (Roblox → Local Machine)
--
-- 1. Gather changed instances from the watcher
-- 2. Serialize them
-- 3. Ask the server for a diff
-- 4. Show the diff to the user
-- 5. On approval, push to local files
---------------------------------------------------------------------------
ui.onPush:Connect(function()
    -- Verify server connection
    if not httpClient:ping() then
        ui:showNotification("Cannot reach SilkDiff server at " .. settings:getServerUrl())
        return
    end

    -- Collect changes
    local changes = instanceWatcher:getChangedInstances()
    if #changes == 0 then
        ui:showNotification("No changes to push.")
        return
    end

    -- Serialize
    local serializedChanges = serializer:serializeChanges(changes)

    -- Request a diff from the server
    local ok, diff = httpClient:requestDiff(serializedChanges)
    if not ok then
        ui:showNotification("Diff request failed: " .. tostring(diff))
        return
    end

    -- Present the diff
    local entries = diff.entries or diff
    local summary = diffEngine:summarize(entries)

    ui:showDiff(entries, "Push: " .. summary, function(approved)
        if approved then
            local pushOk, pushResult = httpClient:push(serializedChanges)
            if pushOk then
                instanceWatcher:clearChanges()
                ui:showNotification("✓ Changes pushed successfully!")
            else
                ui:showNotification("✗ Push failed: " .. tostring(pushResult))
            end
        else
            ui:showNotification("Push cancelled.")
        end
    end)
end)

---------------------------------------------------------------------------
-- PULL  (Local Machine → Roblox)
--
-- 1. Fetch local state from the server
-- 2. Show the diff
-- 3. On approval, confirm & apply
---------------------------------------------------------------------------
ui.onPull:Connect(function()
    if not httpClient:ping() then
        ui:showNotification("Cannot reach SilkDiff server at " .. settings:getServerUrl())
        return
    end

    local ok, data = httpClient:pull()
    if not ok then
        ui:showNotification("Pull failed: " .. tostring(data))
        return
    end

    local diffs   = data.diffs or {}
    local summary = diffEngine:summarize(diffs)

    if #diffs == 0 then
        ui:showNotification("Everything is up to date — nothing to pull.")
        return
    end

    ui:showDiff(diffs, "Pull: " .. summary, function(approved)
        if approved then
            local confirmOk, confirmResult = httpClient:confirmDiff(data)
            if confirmOk then
                ui:showNotification("✓ Changes pulled successfully!")
            else
                ui:showNotification("✗ Pull apply failed: " .. tostring(confirmResult))
            end
        else
            ui:showNotification("Pull cancelled.")
        end
    end)
end)

---------------------------------------------------------------------------
-- EXPORT  (Full game → Local files)
--
-- Serializes every watched service and sends the full tree to the server.
---------------------------------------------------------------------------
ui.onExport:Connect(function()
    if not httpClient:ping() then
        ui:showNotification("Cannot reach SilkDiff server at " .. settings:getServerUrl())
        return
    end

    ui:showNotification("Exporting game — this may take a moment …")

    local watchedServices = instanceWatcher:getWatchedServices()
    local exportData = {}

    for _, serviceName in ipairs(watchedServices) do
        local ok, service = pcall(function()
            return game:GetService(serviceName)
        end)
        if ok and service then
            table.insert(exportData, serializer:serializeTree(service))
        end
    end

    local exportOk, result = httpClient:fullExport(exportData)
    if exportOk then
        instanceWatcher:clearChanges()
        ui:showNotification("✓ Game exported successfully!")
    else
        ui:showNotification("✗ Export failed: " .. tostring(result))
    end
end)

---------------------------------------------------------------------------
-- Start watching for changes as soon as the plugin loads
---------------------------------------------------------------------------
instanceWatcher:startWatching()

---------------------------------------------------------------------------
-- Clean up when the plugin is unloaded
---------------------------------------------------------------------------
plugin.Unloading:Connect(function()
    instanceWatcher:stopWatching()
    ui:destroy()
    print("[SilkDiff] Plugin unloaded.")
end)
