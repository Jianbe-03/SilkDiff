--!nonstrict
--[[
    SilkDiff UI Module

    Creates and manages all visual elements for the SilkDiff plugin:

        Toolbar   – Push, Pull, Export, Settings buttons in the Studio ribbon
        Settings  – A dockable settings panel with all 8 configurable options
        DiffView  – A floating window that shows diffs before push / pull

    Uses the Signal module for custom events so other modules can react
    to user actions without tight coupling.

    Usage:
        local UI = require(...)
        local ui = UI.new(plugin, toolbar, settings)

        ui.onPush:Connect(function() ... end)
        ui.onPull:Connect(function() ... end)
        ui.onExport:Connect(function() ... end)
]]

local Signal = require(script.Parent:WaitForChild("Signal"))

---------------------------------------------------------------------------
-- Line-by-line diff via Longest Common Subsequence
-- Returns a flat list of { line: string, status: "added"|"removed"|"unchanged" }
---------------------------------------------------------------------------
local function computeLineDiff(
    oldSrc: string,
    newSrc: string
): { { line: string, status: string } }
    local function splitLines(s: string): { string }
        local lines: { string } = {}
        if s == "" then return lines end
        for line in (s .. "\n"):gmatch("([^\n]*)\n") do
            table.insert(lines, line)
        end
        return lines
    end

    local oldLines = splitLines(oldSrc)
    local newLines = splitLines(newSrc)
    local m, n    = #oldLines, #newLines

    -- Build DP table with 1-based rows/cols and explicit 0 guard row/column.
    -- dp[i][j] = LCS length of oldLines[1..i-1] vs newLines[1..j-1]
    local dp: { { number } } = {}
    for i = 0, m do
        local row = {}
        for j = 0, n do
            row[j] = 0
        end
        dp[i] = row
    end
    for i = 1, m do
        for j = 1, n do
            if oldLines[i] == newLines[j] then
                dp[i][j] = dp[i - 1][j - 1] + 1
            else
                dp[i][j] = math.max(dp[i - 1][j], dp[i][j - 1])
            end
        end
    end

    -- Backtrack to produce the diff
    local result: { { line: string, status: string } } = {}
    local i, j = m, n
    while i > 0 or j > 0 do
        if i > 0 and j > 0 and oldLines[i] == newLines[j] then
            table.insert(result, 1, { line = oldLines[i], status = "unchanged" })
            i -= 1; j -= 1
        elseif j > 0 and (i == 0 or dp[i][j - 1] >= dp[i - 1][j]) then
            table.insert(result, 1, { line = newLines[j], status = "added" })
            j -= 1
        else
            table.insert(result, 1, { line = oldLines[i], status = "removed" })
            i -= 1
        end
    end

    return result
end

local UI = {}
UI.__index = UI

---------------------------------------------------------------------------
-- Colour palette (dark theme matching Studio)
---------------------------------------------------------------------------
local COLORS = {
    bg          = Color3.fromRGB(30, 30, 30),
    bgLight     = Color3.fromRGB(45, 45, 45),
    bgHover     = Color3.fromRGB(60, 60, 60),
    text        = Color3.fromRGB(220, 220, 220),
    textDim     = Color3.fromRGB(150, 150, 150),
    accent      = Color3.fromRGB(0, 162, 255),
    success     = Color3.fromRGB(76, 175, 80),
    warning     = Color3.fromRGB(255, 193, 7),
    danger      = Color3.fromRGB(244, 67, 54),
    border      = Color3.fromRGB(60, 60, 60),
}

local FONT       = Enum.Font.SourceSans
local FONT_BOLD  = Enum.Font.SourceSansBold
local TEXT_SIZE   = 14
local HEAD_SIZE   = 18
local PAD         = 8

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------
function UI.new(pluginInstance: Plugin, toolbar: PluginToolbar, settings)
    local self = setmetatable({}, UI)

    self._plugin   = pluginInstance
    self._toolbar  = toolbar
    self._settings = settings
    self._widgets  = {} :: { [string]: DockWidgetPluginGui }
    self._buttons  = {} :: { [string]: PluginToolbarButton }

    -- Public signals (other modules connect to these)
    self.onPush      = Signal.new()
    self.onForcePush = Signal.new()
    self.onPull      = Signal.new()
    self.onExport    = Signal.new()

    -- Build everything
    self:_createToolbarButtons()
    self:_createSettingsWidget()
    self:_createDiffWidget()

    return self
end

---------------------------------------------------------------------------
-- HELPERS: reusable UI element factories
---------------------------------------------------------------------------

--- Create a TextLabel inside `parent`.
function UI:_label(parent: GuiObject, text: string, opts: { [string]: any }?): TextLabel
    opts = opts or {}
    local lbl        = Instance.new("TextLabel")
    lbl.Text         = text
    lbl.Font         = opts.font or FONT
    lbl.TextSize     = opts.textSize or TEXT_SIZE
    lbl.TextColor3   = opts.textColor or COLORS.text
    lbl.BackgroundTransparency = 1
    lbl.TextXAlignment = opts.align or Enum.TextXAlignment.Left
    lbl.Size         = opts.size or UDim2.new(1, 0, 0, 24)
    lbl.Parent       = parent
    return lbl
end

--- Create a TextBox (input field) inside `parent`.
function UI:_input(parent: GuiObject, default: string, opts: { [string]: any }?): TextBox
    opts = opts or {}
    local box = Instance.new("TextBox")
    box.Text              = default
    box.Font              = FONT
    box.TextSize          = TEXT_SIZE
    box.TextColor3        = COLORS.text
    box.PlaceholderColor3 = COLORS.textDim
    box.BackgroundColor3  = COLORS.bgLight
    box.BorderColor3      = COLORS.border
    box.BorderSizePixel   = 1
    box.Size              = opts.size or UDim2.new(1, 0, 0, 28)
    box.ClearTextOnFocus  = false
    box.Parent            = parent

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft  = UDim.new(0, 6)
    pad.PaddingRight = UDim.new(0, 6)
    pad.Parent       = box

    return box
end

--- Create a TextButton inside `parent`.
function UI:_button(parent: GuiObject, text: string, color: Color3?, opts: { [string]: any }?): TextButton
    opts = opts or {}
    local btn = Instance.new("TextButton")
    btn.Text            = text
    btn.Font            = FONT_BOLD
    btn.TextSize        = TEXT_SIZE
    btn.TextColor3      = Color3.new(1, 1, 1)
    btn.BackgroundColor3 = color or COLORS.accent
    btn.BorderSizePixel = 0
    btn.Size            = opts.size or UDim2.new(1, 0, 0, 32)
    btn.AutoButtonColor = true
    btn.Parent          = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent       = btn

    return btn
end

--- Create a dropdown selector inside `parent`.
--- `choices` is a list of valid string values.
--- `onSelect` fires when the user picks one.
function UI:_dropdown(
    parent: GuiObject,
    choices: { string },
    current: string,
    onSelect: (string) -> ()
): Frame
    local container = Instance.new("Frame")
    container.Size                 = UDim2.new(1, 0, 0, 28)
    container.BackgroundTransparency = 1
    container.ClipsDescendants     = false
    container.Parent               = parent

    -- Main button showing current value
    local mainBtn        = Instance.new("TextButton")
    mainBtn.Text         = current .. "  ▼"
    mainBtn.Font         = FONT
    mainBtn.TextSize     = TEXT_SIZE
    mainBtn.TextColor3   = COLORS.text
    mainBtn.BackgroundColor3 = COLORS.bgLight
    mainBtn.BorderColor3 = COLORS.border
    mainBtn.BorderSizePixel = 1
    mainBtn.Size         = UDim2.new(1, 0, 1, 0)
    mainBtn.TextXAlignment = Enum.TextXAlignment.Left
    mainBtn.Parent       = container

    local btnPad = Instance.new("UIPadding")
    btnPad.PaddingLeft = UDim.new(0, 6)
    btnPad.Parent      = mainBtn

    -- Options list (initially hidden)
    local optFrame = Instance.new("Frame")
    optFrame.Size            = UDim2.new(1, 0, 0, #choices * 28)
    optFrame.Position        = UDim2.new(0, 0, 1, 2)
    optFrame.BackgroundColor3 = COLORS.bgLight
    optFrame.BorderColor3    = COLORS.border
    optFrame.BorderSizePixel = 1
    optFrame.Visible         = false
    optFrame.ZIndex          = 10
    optFrame.Parent          = container

    local optLayout = Instance.new("UIListLayout")
    optLayout.SortOrder = Enum.SortOrder.LayoutOrder
    optLayout.Parent    = optFrame

    for i, choice in ipairs(choices) do
        local optBtn = Instance.new("TextButton")
        optBtn.Text            = choice
        optBtn.Font            = FONT
        optBtn.TextSize        = TEXT_SIZE
        optBtn.TextColor3      = COLORS.text
        optBtn.BackgroundColor3 = COLORS.bgLight
        optBtn.BorderSizePixel = 0
        optBtn.Size            = UDim2.new(1, 0, 0, 28)
        optBtn.TextXAlignment  = Enum.TextXAlignment.Left
        optBtn.ZIndex          = 11
        optBtn.LayoutOrder     = i
        optBtn.Parent          = optFrame

        local optPad = Instance.new("UIPadding")
        optPad.PaddingLeft = UDim.new(0, 6)
        optPad.Parent      = optBtn

        optBtn.MouseEnter:Connect(function()
            optBtn.BackgroundColor3 = COLORS.bgHover
        end)
        optBtn.MouseLeave:Connect(function()
            optBtn.BackgroundColor3 = COLORS.bgLight
        end)

        optBtn.MouseButton1Click:Connect(function()
            mainBtn.Text       = choice .. "  ▼"
            optFrame.Visible   = false
            onSelect(choice)
        end)
    end

    mainBtn.MouseButton1Click:Connect(function()
        optFrame.Visible = not optFrame.Visible
    end)

    return container
end

---------------------------------------------------------------------------
-- Toolbar buttons (Push · Pull · Export · Settings)
---------------------------------------------------------------------------
function UI:_createToolbarButtons()
    -- Push
    self._buttons.push = self._toolbar:CreateButton(
        "SilkDiff_Push", "Push watched changes to local machine",
        "rbxassetid://6031280882", "Push"
    )
    self._buttons.push.Click:Connect(function()
        self.onPush:Fire()
    end)

    task.wait()

    -- Force Push (full state comparison, no watcher needed)
    self._buttons.forcePush = self._toolbar:CreateButton(
        "SilkDiff_ForcePush", "Offline Push: compare entire Roblox state against local files",
        "rbxassetid://6034328955", "Offline Push"
    )
    self._buttons.forcePush.Click:Connect(function()
        self.onForcePush:Fire()
    end)

    task.wait()

    -- Pull
    self._buttons.pull = self._toolbar:CreateButton(
        "SilkDiff_Pull", "Pull changes from local machine",
        "rbxassetid://6031280882", "Pull"
    )
    self._buttons.pull.Click:Connect(function()
        self.onPull:Fire()
    end)

    task.wait()

    -- Export (full game → local)
    self._buttons.export = self._toolbar:CreateButton(
        "SilkDiff_Export", "Export entire game to local machine",
        "rbxassetid://6034328955", "Export"
    )
    self._buttons.export.Click:Connect(function()
        self.onExport:Fire()
    end)

    task.wait()

    -- Settings
    self._buttons.settings = self._toolbar:CreateButton(
        "SilkDiff_Settings", "Open SilkDiff settings",
        "rbxassetid://6031280882", "Settings"
    )
    self._buttons.settings.Click:Connect(function()
        local w = self._widgets.settings
        w.Enabled = not w.Enabled
    end)
end

---------------------------------------------------------------------------
-- Settings widget (docked panel)
---------------------------------------------------------------------------
function UI:_createSettingsWidget()
    local info = DockWidgetPluginGuiInfo.new(
        Enum.InitialDockState.Float,
        false,  -- not visible at start
        false,  -- don't override saved state
        380, 520, 300, 400
    )
    local widget = self._plugin:CreateDockWidgetPluginGui("SilkDiff_Settings", info)
    widget.Title = "SilkDiff Settings"
    self._widgets.settings = widget

    -- Scrollable root
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size                = UDim2.new(1, 0, 1, 0)
    scroll.BackgroundColor3    = COLORS.bg
    scroll.BorderSizePixel     = 0
    scroll.ScrollBarThickness  = 6
    scroll.CanvasSize          = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent              = widget

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding   = UDim.new(0, 4)
    layout.Parent    = scroll

    local pad = Instance.new("UIPadding")
    pad.PaddingTop    = UDim.new(0, PAD)
    pad.PaddingBottom = UDim.new(0, PAD)
    pad.PaddingLeft   = UDim.new(0, PAD)
    pad.PaddingRight  = UDim.new(0, PAD)
    pad.Parent        = scroll

    -- Title
    local title = self:_label(scroll, "⚙  SilkDiff Settings", {
        font     = FONT_BOLD,
        textSize = HEAD_SIZE,
    })
    title.LayoutOrder = 0

    -- Build one row per setting
    local inputs: { [string]: any } = {}
    local settingOrder = self._settings:getSettingOrder()

    for i, key in ipairs(settingOrder) do
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, 0, 0, 54)
        frame.BackgroundTransparency = 1
        frame.LayoutOrder = i
        frame.Parent = scroll

        -- Label
        local lbl = self:_label(frame, self._settings:getLabel(key), { textColor = COLORS.textDim })
        lbl.Size     = UDim2.new(1, 0, 0, 20)
        lbl.Position = UDim2.new(0, 0, 0, 0)

        -- Input
        local currentValue = self._settings:get(key)
        local choices = self._settings:getChoices(key)

        if choices then
            -- Dropdown
            local dd = self:_dropdown(frame, choices, tostring(currentValue), function(v)
                inputs[key] = v
            end)
            dd.Position  = UDim2.new(0, 0, 0, 22)
            inputs[key]  = tostring(currentValue)
        else
            -- Plain text / number
            local box = self:_input(frame, tostring(currentValue))
            box.Position = UDim2.new(0, 0, 0, 22)
            inputs[key]  = box
        end
    end

    -- Spacer
    local spacer = Instance.new("Frame")
    spacer.Size = UDim2.new(1, 0, 0, 12)
    spacer.BackgroundTransparency = 1
    spacer.LayoutOrder = 90
    spacer.Parent = scroll

    -- Save button
    local saveBtn = self:_button(scroll, "💾  Save Settings", COLORS.success)
    saveBtn.LayoutOrder = 91
    saveBtn.MouseButton1Click:Connect(function()
        for key, input in pairs(inputs) do
            if typeof(input) == "Instance" and input:IsA("TextBox") then
                if key == "ServerPort" then
                    local num = tonumber(input.Text)
                    self._settings:set(key, num or self._settings:getDefaults()[key])
                else
                    self._settings:set(key, input.Text)
                end
            elseif typeof(input) == "string" then
                self._settings:set(key, input)
            end
        end
        self:showNotification("Settings saved!")
    end)

    -- Reset button
    local resetBtn = self:_button(scroll, "↺  Reset to Defaults", COLORS.danger)
    resetBtn.LayoutOrder = 92
    resetBtn.MouseButton1Click:Connect(function()
        self._settings:resetToDefaults()
        local defaults = self._settings:getDefaults()
        for key, input in pairs(inputs) do
            if typeof(input) == "Instance" and input:IsA("TextBox") then
                input.Text = tostring(defaults[key])
            end
            -- Dropdowns keep their visual state via the onSelect callback;
            -- a full refresh would require recreating the widget.
        end
        self:showNotification("Settings reset to defaults!")
    end)
end

---------------------------------------------------------------------------
-- Diff viewer widget (floating window, created once, populated on demand)
---------------------------------------------------------------------------
function UI:_createDiffWidget()
    local info = DockWidgetPluginGuiInfo.new(
        Enum.InitialDockState.Float,
        false, false,
        500, 400, 400, 300
    )
    local widget = self._plugin:CreateDockWidgetPluginGui("SilkDiff_DiffViewer", info)
    widget.Title = "SilkDiff - Review Changes"
    self._widgets.diffViewer = widget

    -- Permanent root frame (content is rebuilt per diff)
    local root = Instance.new("Frame")
    root.Name            = "Root"
    root.Size            = UDim2.new(1, 0, 1, 0)
    root.BackgroundColor3 = COLORS.bg
    root.BorderSizePixel = 0
    root.Parent          = widget
end

---------------------------------------------------------------------------
-- Format a typed property envelope {t=..., v=...} (or raw value) for display
---------------------------------------------------------------------------
local function propValStr(val: any): string
    if val == nil then return "nil" end
    if type(val) == "table" and val.t ~= nil then
        local t, v = val.t, val.v
        if t == "string" then return tostring(v)
        elseif t == "number" then return tostring(v)
        elseif t == "boolean" then return tostring(v)
        elseif t == "Enum" or t == "BrickColor" or t == "Instance" or t == "unknown" then
            return tostring(v)
        elseif t == "Color3" and type(v) == "table" then
            return string.format("rgb(%d, %d, %d)", v.R or 0, v.G or 0, v.B or 0)
        elseif t == "Vector3" and type(v) == "table" then
            return string.format("(%.3f, %.3f, %.3f)", v.X or 0, v.Y or 0, v.Z or 0)
        elseif t == "Vector2" and type(v) == "table" then
            return string.format("(%.3f, %.3f)", v.X or 0, v.Y or 0)
        elseif t == "UDim2" and type(v) == "table" then
            local x, y = v.X or {}, v.Y or {}
            return string.format("{%.3f,%d},{%.3f,%d}", x.Scale or 0, x.Offset or 0, y.Scale or 0, y.Offset or 0)
        elseif t == "UDim" and type(v) == "table" then
            return string.format("{%.3f,%d}", v.Scale or 0, v.Offset or 0)
        elseif t == "CFrame" and type(v) == "table" then
            local p = v.Position or {}
            return string.format("CFrame(%.2f, %.2f, %.2f)", p.X or 0, p.Y or 0, p.Z or 0)
        else
            return tostring(v)
        end
    end
    if type(val) == "string" or type(val) == "number" or type(val) == "boolean" then
        return tostring(val)
    end
    return "?"
end

---------------------------------------------------------------------------
-- Populate the diff viewer with a list of diff entries.
--
-- The viewer shows two stacked lists:
--     Staged Changes (top)  – starts empty; accumulates what you pick
--     Changes (bottom)      – the remaining un-staged changes
--
-- Each instance row has a +/- button to stage/unstage the whole instance.
-- Expanding a row reveals its individual changes (properties, attributes,
-- tags, source); each of those has its own +/- button so you can stage
-- just a single property.
--
-- `onDecision(stagedEntries)` fires on approve with a list of diff entries
-- containing ONLY the staged changes (nil if cancelled).
---------------------------------------------------------------------------
function UI:showDiff(diffs: { any }, summary: string, onDecision: (any?) -> (), mode: string?)
    local widget = self._widgets.diffViewer
    local root   = widget:FindFirstChild("Root") :: Frame

    -- Clear old content
    for _, child in ipairs(root:GetChildren()) do
        child:Destroy()
    end

    mode = mode or "push"

    -- ────────────────────────────────────────────────────────────
    -- Staging state
    -- stagedMap[path] = diff entry containing only the staged bits
    -- stagedOrder keeps insertion order so the staged list is stable
    -- ────────────────────────────────────────────────────────────
    local stagedMap: { [string]: any } = {}
    local stagedOrder: { string } = {}

    -- Tracks which rows are expanded, keyed by path + list so expansion
    -- survives rebuild() after staging/unstaging.
    local expandedKeys: { [string]: boolean } = {}

    local function expandKey(path: string, isStaged: boolean): string
        return path .. "::" .. (isStaged and "s" or "c")
    end

    -- Forward declaration: rebuild() is defined at the bottom but called
    -- from the staging functions above it.
    local rebuild: () -> ()

    local function findDiff(path: string): any?
        for _, d in ipairs(diffs) do
            if d.path == path then return d end
        end
        return nil
    end

    local function entryEmpty(st: any): boolean
        if st.status == "added" or st.status == "removed" then return false end
        if st.propertyChanges and next(st.propertyChanges) then return false end
        if st.attributeChanges and next(st.attributeChanges) then return false end
        if st.tagChanges then return false end
        if st.sourceChanged then return false end
        return true
    end

    local function removeFromOrder(path: string)
        for i, p in ipairs(stagedOrder) do
            if p == path then
                table.remove(stagedOrder, i)
                return
            end
        end
    end

    local function stageInstance(path: string)
        if stagedMap[path] then return end
        local diff = findDiff(path)
        if not diff then return end
        local st = {}
        for k, v in pairs(diff) do
            if k == "propertyChanges" or k == "attributeChanges" or k == "tagChanges" then
                st[k] = {}
                for kk, vv in pairs(v) do st[k][kk] = vv end
            else
                st[k] = v
            end
        end
        stagedMap[path] = st
        table.insert(stagedOrder, path)
        rebuild()
    end

    local function unstageInstance(path: string)
        stagedMap[path] = nil
        removeFromOrder(path)
        rebuild()
    end

    local function stageChange(path: string, kind: string, key: string?)
        local diff = findDiff(path)
        if not diff then return end
        local st = stagedMap[path]
        if not st then
            st = { path = path, name = diff.name, className = diff.className, status = diff.status }
            stagedMap[path] = st
            table.insert(stagedOrder, path)
        end
        if kind == "property" then
            st.propertyChanges = st.propertyChanges or {}
            st.propertyChanges[key] = diff.propertyChanges[key]
        elseif kind == "attribute" then
            st.attributeChanges = st.attributeChanges or {}
            st.attributeChanges[key] = diff.attributeChanges[key]
        elseif kind == "tags" then
            st.tagChanges = diff.tagChanges
        elseif kind == "source" then
            st.sourceChanged = true
            st.oldSource = diff.oldSource
            st.newSource = diff.newSource
        end
        rebuild()
    end

    local function unstageChange(path: string, kind: string, key: string?)
        local st = stagedMap[path]
        if not st then return end
        if kind == "property" and st.propertyChanges then
            st.propertyChanges[key] = nil
        elseif kind == "attribute" and st.attributeChanges then
            st.attributeChanges[key] = nil
        elseif kind == "tags" then
            st.tagChanges = nil
        elseif kind == "source" then
            st.sourceChanged = nil
            st.oldSource = nil
            st.newSource = nil
        end
        if entryEmpty(st) then
            unstageInstance(path)
        else
            rebuild()
        end
    end

    local function stageAll()
        for _, diff in ipairs(diffs) do
            if not stagedMap[diff.path] then stageInstance(diff.path) end
        end
        rebuild()
    end

    local function unstageAll()
        stagedMap = {}
        stagedOrder = {}
        rebuild()
    end

    -- Remaining = original diffs minus whatever is staged
    local function remainingEntries(): { any }
        local out: { any } = {}
        for _, diff in ipairs(diffs) do
            local st = stagedMap[diff.path]
            if st == nil then
                table.insert(out, diff)
            elseif diff.status ~= "added" and diff.status ~= "removed" then
                local rem = { path = diff.path, name = diff.name, className = diff.className, status = diff.status }
                if diff.propertyChanges then
                    local pc = {}
                    for k, v in pairs(diff.propertyChanges) do
                        if not (st.propertyChanges and st.propertyChanges[k]) then pc[k] = v end
                    end
                    if next(pc) then rem.propertyChanges = pc end
                end
                if diff.attributeChanges then
                    local ac = {}
                    for k, v in pairs(diff.attributeChanges) do
                        if not (st.attributeChanges and st.attributeChanges[k]) then ac[k] = v end
                    end
                    if next(ac) then rem.attributeChanges = ac end
                end
                if diff.tagChanges and not st.tagChanges then
                    rem.tagChanges = diff.tagChanges
                end
                if diff.sourceChanged and not st.sourceChanged then
                    rem.sourceChanged = true
                    rem.oldSource = diff.oldSource
                    rem.newSource = diff.newSource
                end
                if rem.propertyChanges or rem.attributeChanges or rem.tagChanges or rem.sourceChanged then
                    table.insert(out, rem)
                end
            end
        end
        return out
    end

    local function stagedEntries(): { any }
        local out: { any } = {}
        for _, path in ipairs(stagedOrder) do
            table.insert(out, stagedMap[path])
        end
        return out
    end

    -- ────────────────────────────────────────────────────────────
    -- Layout scaffolding
    -- ────────────────────────────────────────────────────────────
    local pad = 8
    local heading = self:_label(root, summary, { font = FONT_BOLD, textSize = HEAD_SIZE })
    heading.Position = UDim2.new(0, pad, 0, pad)
    heading.Size = UDim2.new(1, -2 * pad, 0, 24)

    local y = pad + 24 + 4

    local stagedSection = Instance.new("Frame")
    stagedSection.BackgroundTransparency = 1
    stagedSection.Position = UDim2.new(0, pad, 0, y)
    stagedSection.Size = UDim2.new(1, -2 * pad, 0, 150)
    stagedSection.Parent = root
    y += 150 + 4

    local changesSection = Instance.new("Frame")
    changesSection.BackgroundTransparency = 1
    changesSection.Position = UDim2.new(0, pad, 0, y)
    changesSection.Size = UDim2.new(1, -2 * pad, 1, -y - 40 - pad)
    changesSection.Parent = root

    local btnBar = Instance.new("Frame")
    btnBar.BackgroundTransparency = 1
    btnBar.Position = UDim2.new(0, pad, 1, -40 - pad)
    btnBar.Size = UDim2.new(1, -2 * pad, 0, 40)
    btnBar.Parent = root

    -- Section builder: label row (+/- stage-all button) + scroll list
    local function buildSection(frame: Frame, isStaged: boolean): (TextLabel, ScrollingFrame)
        local labelRow = Instance.new("Frame")
        labelRow.BackgroundTransparency = 1
        labelRow.Size = UDim2.new(1, 0, 0, 24)
        labelRow.Parent = frame

        local lbl = self:_label(labelRow, "", { font = FONT_BOLD, textSize = 15 })
        lbl.Size = UDim2.new(1, -32, 0, 24)

        local allBtn = self:_button(labelRow, isStaged and "−" or "+", COLORS.bgHover, {
            size = UDim2.new(0, 26, 0, 22),
        })
        allBtn.Position = UDim2.new(1, -28, 0, 1)
        allBtn.Font = FONT_BOLD
        allBtn.TextSize = 16
        allBtn.MouseButton1Click:Connect(function()
            if isStaged then unstageAll() else stageAll() end
        end)

        local scroll = Instance.new("ScrollingFrame")
        scroll.Size                = UDim2.new(1, 0, 1, -24)
        scroll.Position            = UDim2.new(0, 0, 0, 24)
        scroll.BackgroundColor3    = COLORS.bgLight
        scroll.BorderSizePixel     = 0
        scroll.ScrollBarThickness  = 6
        scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        scroll.Parent              = frame

        local scrollLayout = Instance.new("UIListLayout")
        scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
        scrollLayout.Padding   = UDim.new(0, 2)
        scrollLayout.Parent    = scroll

        local scrollPad = Instance.new("UIPadding")
        scrollPad.PaddingTop   = UDim.new(0, 4)
        scrollPad.PaddingLeft  = UDim.new(0, 4)
        scrollPad.PaddingRight = UDim.new(0, 4)
        scrollPad.Parent       = scroll

        return lbl, scroll
    end

    local stagedLabel, stagedScroll = buildSection(stagedSection, true)
    local changesLabel, changesScroll = buildSection(changesSection, false)

    -- Rows created per render pass; tracked so rebuild can destroy them
    local stagedRows: { any } = {}
    local changesRows: { any } = {}

    local function clearRows(rows: { any })
        for _, r in ipairs(rows) do
            r:Destroy()
        end
        for i = #rows, 1, -1 do
            rows[i] = nil
        end
    end

    -- ────────────────────────────────────────────────────────────
    -- Row rendering
    -- ────────────────────────────────────────────────────────────
    local function buildRow(scroll: ScrollingFrame, diff: any, isStaged: boolean, order: number, rowsOut: { any })
        local statusColor = COLORS.warning
        local icon        = "✏️"
        if diff.status == "added" then
            statusColor = COLORS.success
            icon        = "➕"
        elseif diff.status == "removed" then
            statusColor = COLORS.danger
            icon        = "➖"
        end

        local detailText = diff.status :: string
        local hasProps = diff.propertyChanges ~= nil
        local hasAttrs = diff.attributeChanges ~= nil
        local hasTags  = diff.tagChanges ~= nil
        local hasSrc   = diff.sourceChanged == true
        local canExpand = hasProps or hasAttrs or hasTags or hasSrc

        if hasProps then
            local n = 0; for _ in pairs(diff.propertyChanges) do n += 1 end
            detailText ..= " · " .. n .. " prop" .. (n == 1 and "" or "s")
        end
        if hasAttrs then
            local n = 0; for _ in pairs(diff.attributeChanges) do n += 1 end
            detailText ..= " · " .. n .. " attr" .. (n == 1 and "" or "s")
        end
        if hasTags then detailText ..= " · tags" end
        if hasSrc  then detailText ..= " · source" end
        if canExpand then detailText ..= "  ▶" end

        local row = Instance.new("Frame")
        row.Size             = UDim2.new(1, 0, 0, 40)
        row.BackgroundColor3 = COLORS.bg
        row.BorderSizePixel  = 0
        row.ClipsDescendants = true
        row.LayoutOrder      = order
        row.Parent           = scroll
        table.insert(rowsOut, row)

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 4)
        corner.Parent       = row

        local bar = Instance.new("Frame")
        bar.Size             = UDim2.new(0, 4, 0, 40)
        bar.BackgroundColor3 = statusColor
        bar.BorderSizePixel  = 0
        bar.Parent           = row

        local pathLbl = Instance.new("TextLabel")
        pathLbl.Text                   = icon .. "  " .. (diff.path or diff.name or "?")
        pathLbl.Font                   = FONT
        pathLbl.TextSize               = TEXT_SIZE
        pathLbl.TextColor3             = COLORS.text
        pathLbl.BackgroundTransparency = 1
        pathLbl.Size                   = UDim2.new(1, -56, 0, 20)
        pathLbl.Position               = UDim2.new(0, 12, 0, 2)
        pathLbl.TextXAlignment         = Enum.TextXAlignment.Left
        pathLbl.Parent                 = row

        local detailLbl = Instance.new("TextLabel")
        detailLbl.Text                   = detailText
        detailLbl.Font                   = FONT
        detailLbl.TextSize               = 12
        detailLbl.TextColor3             = COLORS.textDim
        detailLbl.BackgroundTransparency = 1
        detailLbl.Size                   = UDim2.new(1, -56, 0, 16)
        detailLbl.Position               = UDim2.new(0, 12, 0, 22)
        detailLbl.TextXAlignment         = Enum.TextXAlignment.Left
        detailLbl.Parent                 = row

        -- Stage / unstage whole instance
        local stageBtn = Instance.new("TextButton")
        stageBtn.Text            = isStaged and "−" or "+"
        stageBtn.Font            = FONT_BOLD
        stageBtn.TextSize        = 16
        stageBtn.TextColor3      = Color3.new(1, 1, 1)
        stageBtn.BackgroundColor3 = if isStaged then COLORS.danger else COLORS.success
        stageBtn.BorderSizePixel = 0
        stageBtn.Size            = UDim2.new(0, 24, 0, 24)
        stageBtn.Position        = UDim2.new(1, -30, 0, 8)
        stageBtn.ZIndex          = 6
        stageBtn.Parent          = row
        local stageCorner = Instance.new("UICorner")
        stageCorner.CornerRadius = UDim.new(0, 4)
        stageCorner.Parent       = stageBtn
        stageBtn.MouseButton1Click:Connect(function()
            if isStaged then unstageInstance(diff.path) else stageInstance(diff.path) end
        end)

        -- Expandable panels; stacked vertically when the row is expanded
        local panels: { any } = {}

        -- Generic change table (properties / attributes) with per-row +/- button
        local function buildChangePanel(kind: string, changes: { [string]: any })
            local keys: { string } = {}
            for k in pairs(changes) do table.insert(keys, k) end
            table.sort(keys)
            local height = math.min(200, #keys * 22 + 28)

            local frame = Instance.new("Frame")
            frame.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
            frame.BorderSizePixel  = 0
            frame.ClipsDescendants = true
            frame.Visible          = false
            frame.ZIndex           = 2
            frame.Parent           = row

            local headerKey = Instance.new("TextLabel")
            headerKey.Text                   = if kind == "property" then "Property" else "Attribute"
            headerKey.Font                   = Enum.Font.SourceSansBold
            headerKey.TextSize               = 11
            headerKey.TextColor3             = COLORS.textDim
            headerKey.BackgroundTransparency = 1
            headerKey.Size                   = UDim2.new(0.30, 0, 0, 20)
            headerKey.Position               = UDim2.new(0, 6, 0, 2)
            headerKey.TextXAlignment         = Enum.TextXAlignment.Left
            headerKey.ZIndex                 = 3
            headerKey.Parent                 = frame

            local headerOld = Instance.new("TextLabel")
            headerOld.Text                   = "Before"
            headerOld.Font                   = Enum.Font.SourceSansBold
            headerOld.TextSize               = 11
            headerOld.TextColor3             = COLORS.textDim
            headerOld.BackgroundTransparency = 1
            headerOld.Size                   = UDim2.new(0.30, 0, 0, 20)
            headerOld.Position               = UDim2.new(0.30, 0, 0, 2)
            headerOld.TextXAlignment         = Enum.TextXAlignment.Left
            headerOld.ZIndex                 = 3
            headerOld.Parent                 = frame

            local headerNew = Instance.new("TextLabel")
            headerNew.Text                   = "After"
            headerNew.Font                   = Enum.Font.SourceSansBold
            headerNew.TextSize               = 11
            headerNew.TextColor3             = COLORS.textDim
            headerNew.BackgroundTransparency = 1
            headerNew.Size                   = UDim2.new(0.30, 0, 0, 20)
            headerNew.Position               = UDim2.new(0.60, 0, 0, 2)
            headerNew.TextXAlignment         = Enum.TextXAlignment.Left
            headerNew.ZIndex                 = 3
            headerNew.Parent                 = frame

            for pi, key in ipairs(keys) do
                local change = changes[key]
                local yPos   = 22 + (pi - 1) * 22

                local rowBg = Instance.new("Frame")
                rowBg.BackgroundColor3 = if pi % 2 == 0
                    then Color3.fromRGB(28, 28, 35)
                    else Color3.fromRGB(22, 22, 28)
                rowBg.BorderSizePixel  = 0
                rowBg.Size             = UDim2.new(1, 0, 0, 22)
                rowBg.Position         = UDim2.new(0, 0, 0, yPos)
                rowBg.ZIndex           = 2
                rowBg.Parent           = frame

                local function cell(text: string, xPos: number, width: number, color: Color3)
                    local lbl = Instance.new("TextLabel")
                    lbl.Text                   = text
                    lbl.Font                   = Enum.Font.Code
                    lbl.TextSize               = 11
                    lbl.TextColor3             = color
                    lbl.BackgroundTransparency = 1
                    lbl.Size                   = UDim2.new(width, -18, 0, 22)
                    lbl.Position               = UDim2.new(xPos, 4, 0, 0)
                    lbl.TextXAlignment         = Enum.TextXAlignment.Left
                    lbl.TextTruncate           = Enum.TextTruncate.AtEnd
                    lbl.ZIndex                 = 3
                    lbl.Parent                 = rowBg
                end

                cell(key,                     0,    0.30, Color3.fromRGB(180, 180, 220))
                cell(propValStr(change.old),  0.30, 0.30, Color3.fromRGB(220, 100, 100))
                cell(propValStr(change.new),  0.60, 0.30, Color3.fromRGB(100, 220, 100))

                local itemBtn = Instance.new("TextButton")
                itemBtn.Text            = isStaged and "−" or "+"
                itemBtn.Font            = FONT_BOLD
                itemBtn.TextSize        = 13
                itemBtn.TextColor3      = Color3.new(1, 1, 1)
                itemBtn.BackgroundColor3 = if isStaged then COLORS.danger else COLORS.success
                itemBtn.BorderSizePixel = 0
                itemBtn.Size            = UDim2.new(0, 16, 0, 16)
                itemBtn.Position        = UDim2.new(0.90, 2, 0, 3)
                itemBtn.ZIndex          = 5
                itemBtn.Parent          = rowBg
                local itemCorner = Instance.new("UICorner")
                itemCorner.CornerRadius = UDim.new(0, 3)
                itemCorner.Parent       = itemBtn
                itemBtn.MouseButton1Click:Connect(function()
                    if isStaged then unstageChange(diff.path, kind, key)
                    else stageChange(diff.path, kind, key) end
                end)
            end

            table.insert(panels, { frame = frame, height = height })
        end

        -- Single-row panel with a +/- button, used for tags / source
        local function buildUnitPanel(kind: string, title: string, subtitle: string)
            local frame = Instance.new("Frame")
            frame.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
            frame.BorderSizePixel  = 0
            frame.ClipsDescendants = true
            frame.Visible          = false
            frame.ZIndex           = 2
            frame.Parent           = row

            local lbl = Instance.new("TextLabel")
            lbl.Text                   = title
            lbl.Font                   = Enum.Font.SourceSansBold
            lbl.TextSize               = 12
            lbl.TextColor3             = COLORS.text
            lbl.BackgroundTransparency = 1
            lbl.Size                   = UDim2.new(0.85, -20, 0, 22)
            lbl.Position               = UDim2.new(0, 6, 0, 0)
            lbl.TextXAlignment         = Enum.TextXAlignment.Left
            lbl.ZIndex                 = 3
            lbl.Parent                 = frame

            local sub = Instance.new("TextLabel")
            sub.Text                   = subtitle
            sub.Font                   = FONT
            sub.TextSize               = 11
            sub.TextColor3             = COLORS.textDim
            sub.BackgroundTransparency = 1
            sub.Size                   = UDim2.new(0.85, -20, 0, 16)
            sub.Position               = UDim2.new(0, 6, 0, 22)
            sub.TextXAlignment         = Enum.TextXAlignment.Left
            sub.TextTruncate           = Enum.TextTruncate.AtEnd
            sub.ZIndex                 = 3
            sub.Parent                 = frame

            local unitBtn = Instance.new("TextButton")
            unitBtn.Text            = isStaged and "−" or "+"
            unitBtn.Font            = FONT_BOLD
            unitBtn.TextSize        = 15
            unitBtn.TextColor3      = Color3.new(1, 1, 1)
            unitBtn.BackgroundColor3 = if isStaged then COLORS.danger else COLORS.success
            unitBtn.BorderSizePixel = 0
            unitBtn.Size            = UDim2.new(0, 20, 0, 20)
            unitBtn.Position        = UDim2.new(0.90, 4, 0, 4)
            unitBtn.ZIndex          = 5
            unitBtn.Parent          = frame
            local unitCorner = Instance.new("UICorner")
            unitCorner.CornerRadius = UDim.new(0, 3)
            unitCorner.Parent       = unitBtn
            unitBtn.MouseButton1Click:Connect(function()
                if isStaged then unstageChange(diff.path, kind, nil)
                else stageChange(diff.path, kind, nil) end
            end)

            table.insert(panels, { frame = frame, height = 42 })
            return frame
        end

        -- Source diff lines panel (shown below the source unit row)
        local srcLinesFrame
        local srcLinesHeight = 0
        if hasSrc then
            local lineDiff = computeLineDiff(diff.oldSource or "", diff.newSource or "")
            srcLinesHeight = math.min(300, math.max(60, #lineDiff * 18 + 8))
            srcLinesFrame = Instance.new("ScrollingFrame")
            srcLinesFrame.BackgroundColor3    = Color3.fromRGB(20, 20, 20)
            srcLinesFrame.BorderSizePixel     = 0
            srcLinesFrame.ScrollBarThickness  = 4
            srcLinesFrame.CanvasSize          = UDim2.new(0, 0, 0, 0)
            srcLinesFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
            srcLinesFrame.Visible             = false
            srcLinesFrame.ZIndex              = 2
            srcLinesFrame.Parent              = row

            local lineLayout = Instance.new("UIListLayout")
            lineLayout.SortOrder = Enum.SortOrder.LayoutOrder
            lineLayout.Parent    = srcLinesFrame

            for li, entry in ipairs(lineDiff) do
                local bgColor, textColor
                if entry.status == "added" then
                    bgColor   = Color3.fromRGB(20, 50, 20)
                    textColor = Color3.fromRGB(100, 220, 100)
                elseif entry.status == "removed" then
                    bgColor   = Color3.fromRGB(50, 20, 20)
                    textColor = Color3.fromRGB(220, 100, 100)
                else
                    bgColor   = Color3.fromRGB(28, 28, 28)
                    textColor = Color3.fromRGB(180, 180, 180)
                end
                local prefix = if entry.status == "added"     then "+ "
                               elseif entry.status == "removed" then "- "
                               else   "  "

                local lineLbl = Instance.new("TextLabel")
                lineLbl.Text             = prefix .. entry.line
                lineLbl.Font             = Enum.Font.Code
                lineLbl.TextSize         = 12
                lineLbl.TextColor3       = textColor
                lineLbl.BackgroundColor3 = bgColor
                lineLbl.BorderSizePixel  = 0
                lineLbl.Size             = UDim2.new(1, 0, 0, 18)
                lineLbl.TextXAlignment   = Enum.TextXAlignment.Left
                lineLbl.TextTruncate     = Enum.TextTruncate.AtEnd
                lineLbl.ZIndex           = 3
                lineLbl.LayoutOrder      = li
                lineLbl.Parent           = srcLinesFrame

                local lpad = Instance.new("UIPadding")
                lpad.PaddingLeft = UDim.new(0, 6)
                lpad.Parent      = lineLbl
            end
        end

        -- Assemble panels in a stable order
        if hasProps then buildChangePanel("property", diff.propertyChanges) end
        if hasAttrs then buildChangePanel("attribute", diff.attributeChanges) end
        if hasTags then
            local tc = diff.tagChanges
            local subParts: { string } = {}
            if tc.added and #tc.added > 0 then table.insert(subParts, "added: " .. table.concat(tc.added, ", ")) end
            if tc.removed and #tc.removed > 0 then table.insert(subParts, "removed: " .. table.concat(tc.removed, ", ")) end
            buildUnitPanel("tags", "Tags", table.concat(subParts, "  ·  "))
        end
        if hasSrc then
            buildUnitPanel("source", "Source", "Script source changed")
            if srcLinesFrame then table.insert(panels, { frame = srcLinesFrame, height = srcLinesHeight }) end
        end

        -- Layout panels vertically when the row is expanded
        local function relayout(expanded: boolean)
            local yOff = 40
            for _, p in ipairs(panels) do
                p.frame.Visible = expanded
                p.frame.Size = UDim2.new(1, -4, 0, p.height)
                p.frame.Position = UDim2.new(0, 4, 0, yOff)
                if expanded then yOff += p.height end
            end
            bar.Size = UDim2.new(0, 4, 0, yOff)
            row.Size = UDim2.new(1, 0, 0, yOff)
        end

        -- Transparent click button over the 40px header (excluding the stage btn)
        local clickBtn = Instance.new("TextButton")
        clickBtn.Size                   = UDim2.new(1, -36, 0, 40)
        clickBtn.BackgroundTransparency = 1
        clickBtn.Text                   = ""
        clickBtn.ZIndex                 = 5
        clickBtn.Parent                 = row

        local expanded = expandedKeys[expandKey(diff.path, isStaged)] or false
        if expanded then
            relayout(true)
            detailLbl.Text = detailText:gsub("▶", "▼")
        end

        clickBtn.MouseButton1Click:Connect(function()
            expanded = not expanded
            expandedKeys[expandKey(diff.path, isStaged)] = expanded
            relayout(expanded)
            detailLbl.Text = if expanded
                then detailText:gsub("▶", "▼")
                else detailText
        end)
    end

    -- ────────────────────────────────────────────────────────────
    -- Bottom button bar
    -- ────────────────────────────────────────────────────────────
    local btnLayout = Instance.new("UIListLayout")
    btnLayout.FillDirection       = Enum.FillDirection.Horizontal
    btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    btnLayout.Padding             = UDim.new(0, 8)
    btnLayout.Parent              = btnBar

    local decided = false
    local function decide(approved: boolean)
        if decided then return end
        decided = true
        widget.Enabled = false
        if approved then
            onDecision(stagedEntries())
        else
            onDecision(nil)
        end
    end

    local cancelBtn = self:_button(btnBar, "Cancel", COLORS.danger, {
        size = UDim2.new(0, 120, 0, 32),
    })
    cancelBtn.MouseButton1Click:Connect(function()
        decide(false)
    end)

    local approveBtn = self:_button(btnBar, "✓  Approve", COLORS.success, {
        size = UDim2.new(0, 180, 0, 32),
    })
    approveBtn.MouseButton1Click:Connect(function()
        decide(true)
    end)

    -- Closing the window via the X button also counts as cancel
    local closeConn
    closeConn = widget:GetPropertyChangedSignal("Enabled"):Connect(function()
        if not widget.Enabled then
            decide(false)
            closeConn:Disconnect()
        end
    end)

    -- ────────────────────────────────────────────────────────────
    -- Rebuild both lists
    -- ────────────────────────────────────────────────────────────
    rebuild = function()
        local staged = stagedEntries()
        local remain = remainingEntries()

        stagedLabel.Text = string.format("Staged Changes (%d)", #staged)
        changesLabel.Text = string.format("Changes (%d)", #remain)

        local verb = if mode == "pull" then "Pull" else "Push"
        if #staged > 0 then
            approveBtn.Text = "✓  " .. verb .. " Staged (" .. #staged .. ")"
            approveBtn.BackgroundColor3 = COLORS.success
        else
            approveBtn.Text = "✓  " .. verb .. " Staged (0)"
            approveBtn.BackgroundColor3 = COLORS.bgHover
        end

        clearRows(stagedRows)
        clearRows(changesRows)

        for i, entry in ipairs(staged) do
            buildRow(stagedScroll, entry, true, i, stagedRows)
        end
        for i, entry in ipairs(remain) do
            buildRow(changesScroll, entry, false, i, changesRows)
        end
    end

    -- Initial render
    rebuild()

    -- Show the widget
    widget.Enabled = true
end

---------------------------------------------------------------------------
-- Show a brief notification (prints to Output for now)
---------------------------------------------------------------------------
function UI:showNotification(message: string)
    print("[SilkDiff] " .. message)
end

---------------------------------------------------------------------------
-- Tear down all widgets and signals
---------------------------------------------------------------------------
function UI:destroy()
    self.onPush:Destroy()
    self.onForcePush:Destroy()
    self.onPull:Destroy()
    self.onExport:Destroy()

    for _, w in pairs(self._widgets) do
        w:Destroy()
    end
end

return UI
