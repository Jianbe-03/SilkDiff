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

    The same works in reverse with "Pull" - local file changes are
    diffed against the current Roblox state and applied on approval.

    Modules (under Modules/):
        Signal          – Lightweight custom event system
        Settings        – 8 configurable options, persisted across sessions
        InstanceWatcher – Watches game services for property/attribute/child changes
        Serializer      – Converts instances into JSON-safe dictionaries
        HttpClient      – Talks to the local SilkDiff Python server
        DiffEngine      – Compares two states and produces diff entries
        UI              – Toolbar, Settings panel, Diff Viewer
        Popup           – Simple modal confirmation dialog
        Console         – Docked RichText output panel (replaces print spam)
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
local Popup           = require(Modules:WaitForChild("Popup"))
local Console         = require(Modules:WaitForChild("Console"))

---------------------------------------------------------------------------
-- Initialise everything
---------------------------------------------------------------------------
local settings        = Settings.new(plugin)
local httpClient      = HttpClient.new(settings)
local serializer      = Serializer.new(settings)
local diffEngine      = DiffEngine.new()
local instanceWatcher = InstanceWatcher.new()
local ui              = UI.new(plugin, toolbar, settings)
local popup           = Popup.new(plugin)
local console         = Console.new(plugin, toolbar, settings)

-- Now that console exists, give HttpClient a reference for debug logging
httpClient:setConsole(console)

-- Helper: serialize all watched services → tree list (for pull payload)
local function serializeCurrentState(): { any }
    local trees = {}
    for _, serviceName in ipairs(instanceWatcher:getWatchedServices()) do
        local ok, service = pcall(function()
            return game:GetService(serviceName)
        end)
        if ok and service then
            table.insert(trees, serializer:serializeTree(service))
        end
    end
    return trees
end

-- Helper: flatten a serialized tree into a list of individual instance nodes
-- (the server's /api/diff and /api/push both accept flat lists)
local function flattenTree(tree: { any }, out: { any }?): { any }
    out = out or {}
    -- Strip children before inserting so we send leaf-level data cleanly
    local node = {}
    for k, v in pairs(tree) do
        if k ~= "children" then node[k] = v end
    end
    table.insert(out, node)
    for _, child in ipairs(tree.children or {}) do
        flattenTree(child, out)
    end
    return out
end

-- Flatten all service trees into one list
local function flatCurrentState(): { any }
    local flat = {}
    for _, tree in ipairs(serializeCurrentState()) do
        flattenTree(tree, flat)
    end
    return flat
end

console:log("SilkDiff plugin loaded", "info")

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
        console:log("Cannot reach SilkDiff server at " .. settings:getServerUrl(), "error")
        return
    end

    -- Collect changes
    local changes = instanceWatcher:getChangedInstances()
    if #changes == 0 then
        console:log("No changes to push.", "info")
        return
    end

    -- Serialize
    local serializedChanges = serializer:serializeChanges(changes)

    -- Request a diff from the server
    local ok, diff = httpClient:requestDiff(serializedChanges)
    if not ok then
        console:log("Diff request failed: " .. tostring(diff), "error")
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
                console:log("Changes pushed successfully!", "success")
            else
                console:log("Push failed: " .. tostring(pushResult), "error")
            end
        else
            console:log("Push cancelled.", "warn")
        end
    end)
end)

---------------------------------------------------------------------------
-- FORCE PUSH  (Compare entire Roblox state against local files → push)
--
-- Unlike Push (which only sends watcher-tracked changes), Force Push
-- serializes the *whole* current Roblox game, diffs it against whatever
-- is on disk, and lets you push every difference. This is the correct
-- flow when teammates made changes while your machine was off — the
-- watcher would have missed those events, but Force Push sees them all.
---------------------------------------------------------------------------
ui.onForcePush:Connect(function()
    if not httpClient:ping() then
        console:log("Cannot reach SilkDiff server at " .. settings:getServerUrl(), "error")
        return
    end

    console:log("Force Push: serializing entire Roblox state…", "info")
    local flat = flatCurrentState()
    console:log(string.format("Force Push: %d instances — computing diff…", #flat), "info")

    local ok, diff = httpClient:requestDiff(flat)
    if not ok then
        console:log("Force Push diff failed: " .. tostring(diff), "error")
        return
    end

    local entries = diff.entries or diff
    local summary = diffEngine:summarize(entries)

    if #entries == 0 then
        console:log("Force Push: local files already match Roblox. Nothing to push.", "success")
        return
    end

    console:log("Force Push diff ready: " .. summary, "info")
    ui:showDiff(entries, "Force Push: " .. summary, function(approved)
        if approved then
            local pushOk, pushResult = httpClient:push(flat)
            if pushOk then
                instanceWatcher:clearChanges()
                console:log("Force Push complete! " .. summary, "success")
            else
                console:log("Force Push failed: " .. tostring(pushResult), "error")
            end
        else
            console:log("Force Push cancelled.", "warn")
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
        console:log("Cannot reach SilkDiff server at " .. settings:getServerUrl(), "error")
        return
    end

    console:log("Serializing current Roblox state for pull diff…", "info")
    local robloxState = serializeCurrentState()

    local ok, data = httpClient:pull(robloxState)
    if not ok then
        console:log("Pull failed: " .. tostring(data), "error")
        return
    end

    local entries = data.entries or data.diffs or {}
    local summary = diffEngine:summarize(entries)

    if #entries == 0 then
        console:log("Everything is up to date — nothing to pull.", "success")
        return
    end

    console:log("Pull diff ready: " .. summary, "info")
    ui:showDiff(entries, "Pull: " .. summary, function(approved)
        if approved then
            -- Apply the local file data to Roblox instances
            local appliedCount = 0
            local errorCount = 0
            local instances = data.instances or {}

            for _, instanceData in ipairs(instances) do
                local path = instanceData.path
                if not path then
                    -- skip
                else
                    local instance = serializer:findInstanceByPath(path)
                    if instance then
                        local ok, err = pcall(function()
                            serializer:applyInstanceData(instance, instanceData)
                        end)
                        if ok then
                            appliedCount += 1
                        else
                            warn("[SilkDiff] Failed to apply " .. path .. ": " .. tostring(err))
                            errorCount += 1
                        end
                    else
                        warn("[SilkDiff] Instance not found in Roblox: " .. path)
                        errorCount += 1
                    end
                end
            end

            console:log(string.format("Pull complete! Applied %d instance(s) (%d errors).", appliedCount, errorCount), if errorCount > 0 then "warn" else "success")
            instanceWatcher:clearChanges()
        else
            console:log("Pull cancelled.", "warn")
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
        console:log("Cannot reach SilkDiff server at " .. settings:getServerUrl(), "error")
        return
    end

    -- Ask for confirmation — export wipes the entire local tree first
    popup:show(
        "⚠  Full Export",
        "This will DELETE all existing local files and do a full rebuild from Roblox.\n\nMake sure any local-only changes are backed up first!",
        function()
            -- Confirmed — proceed
            console:log("Exporting game — this may take a moment…", "warn")

            local watchedServices = instanceWatcher:getWatchedServices()
            local exportData = {}
            for _, serviceName in ipairs(watchedServices) do
                local ok2, service = pcall(function()
                    return game:GetService(serviceName)
                end)
                if ok2 and service then
                    table.insert(exportData, serializer:serializeTree(service))
                end
            end

            local exportOk, result = httpClient:fullExport(exportData)
            if exportOk then
                instanceWatcher:clearChanges()
                console:log("Game exported successfully! (" .. #exportData .. " services)", "success")
            else
                console:log("Export failed: " .. tostring(result), "error")
            end
        end,
        function()
            console:log("Export cancelled.", "info")
        end
    )
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
    popup:destroy()
    console:destroy()
    print("[SilkDiff] Plugin unloaded.")
end)
