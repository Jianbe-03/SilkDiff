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
    self.onPush   = Signal.new()
    self.onPull   = Signal.new()
    self.onExport = Signal.new()

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
        "SilkDiff_Push", "Push changes to local machine",
        "rbxassetid://6031280882", "Push"
    )
    self._buttons.push.Click:Connect(function()
        self.onPush:Fire()
    end)

    -- Pull
    self._buttons.pull = self._toolbar:CreateButton(
        "SilkDiff_Pull", "Pull changes from local machine",
        "rbxassetid://6031280882", "Pull"
    )
    self._buttons.pull.Click:Connect(function()
        self.onPull:Fire()
    end)

    -- Export (full game → local)
    self._buttons.export = self._toolbar:CreateButton(
        "SilkDiff_Export", "Export entire game to local machine",
        "rbxassetid://6034328955", "Export"
    )
    self._buttons.export.Click:Connect(function()
        self.onExport:Fire()
    end)

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
        Enum.InitialDockState.Right,
        false,  -- not visible at start
        false,  -- don't override saved state
        350, 500, 300, 400
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
    widget.Title = "SilkDiff — Review Changes"
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
-- Populate the diff viewer with a list of diff entries.
-- `onDecision(true)` = approved, `onDecision(false)` = cancelled
---------------------------------------------------------------------------
function UI:showDiff(diffs: { any }, summary: string, onDecision: (boolean) -> ())
    local widget = self._widgets.diffViewer
    local root   = widget:FindFirstChild("Root") :: Frame

    -- Clear old content
    for _, child in ipairs(root:GetChildren()) do
        child:Destroy()
    end

    -- Layout
    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding   = UDim.new(0, 2)
    layout.Parent    = root

    local pad = Instance.new("UIPadding")
    pad.PaddingTop    = UDim.new(0, PAD)
    pad.PaddingBottom = UDim.new(0, PAD)
    pad.PaddingLeft   = UDim.new(0, PAD)
    pad.PaddingRight  = UDim.new(0, PAD)
    pad.Parent        = root

    -- Summary heading
    local heading = self:_label(root, summary, { font = FONT_BOLD, textSize = HEAD_SIZE })
    heading.LayoutOrder = 0

    -- Scrollable change list
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size                = UDim2.new(1, 0, 1, -80)
    scroll.BackgroundColor3    = COLORS.bgLight
    scroll.BorderSizePixel     = 0
    scroll.ScrollBarThickness  = 6
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.LayoutOrder         = 1
    scroll.Parent              = root

    local scrollLayout = Instance.new("UIListLayout")
    scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
    scrollLayout.Padding   = UDim.new(0, 2)
    scrollLayout.Parent    = scroll

    local scrollPad = Instance.new("UIPadding")
    scrollPad.PaddingTop  = UDim.new(0, 4)
    scrollPad.PaddingLeft = UDim.new(0, 4)
    scrollPad.PaddingRight = UDim.new(0, 4)
    scrollPad.Parent      = scroll

    -- One row per diff entry
    for i, diff in ipairs(diffs) do
        local statusColor = COLORS.warning
        local icon        = "✏️"

        if diff.status == "added" then
            statusColor = COLORS.success
            icon        = "➕"
        elseif diff.status == "removed" then
            statusColor = COLORS.danger
            icon        = "➖"
        end

        -- Row container
        local row = Instance.new("Frame")
        row.Size            = UDim2.new(1, 0, 0, 40)
        row.BackgroundColor3 = COLORS.bg
        row.BorderSizePixel = 0
        row.LayoutOrder     = i
        row.Parent          = scroll

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 4)
        corner.Parent       = row

        -- Colour bar on the left edge
        local bar = Instance.new("Frame")
        bar.Size            = UDim2.new(0, 4, 1, 0)
        bar.BackgroundColor3 = statusColor
        bar.BorderSizePixel = 0
        bar.Parent          = row

        -- Path
        local pathLbl = Instance.new("TextLabel")
        pathLbl.Text            = icon .. "  " .. (diff.path or diff.name or "?")
        pathLbl.Font            = FONT
        pathLbl.TextSize        = TEXT_SIZE
        pathLbl.TextColor3      = COLORS.text
        pathLbl.BackgroundTransparency = 1
        pathLbl.Size            = UDim2.new(1, -12, 0, 20)
        pathLbl.Position        = UDim2.new(0, 12, 0, 2)
        pathLbl.TextXAlignment  = Enum.TextXAlignment.Left
        pathLbl.Parent          = row

        -- Detail line
        local detail = diff.status :: string
        if diff.propertyChanges then
            local n = 0; for _ in pairs(diff.propertyChanges) do n += 1 end
            detail ..= " · " .. n .. " props"
        end
        if diff.sourceChanged then
            detail ..= " · source"
        end

        local detailLbl = Instance.new("TextLabel")
        detailLbl.Text            = detail
        detailLbl.Font            = FONT
        detailLbl.TextSize        = 12
        detailLbl.TextColor3      = COLORS.textDim
        detailLbl.BackgroundTransparency = 1
        detailLbl.Size            = UDim2.new(1, -12, 0, 16)
        detailLbl.Position        = UDim2.new(0, 12, 0, 22)
        detailLbl.TextXAlignment  = Enum.TextXAlignment.Left
        detailLbl.Parent          = row
    end

    -- Bottom button bar
    local btnBar = Instance.new("Frame")
    btnBar.Size = UDim2.new(1, 0, 0, 40)
    btnBar.BackgroundTransparency = 1
    btnBar.LayoutOrder = 99
    btnBar.Parent = root

    local btnLayout = Instance.new("UIListLayout")
    btnLayout.FillDirection       = Enum.FillDirection.Horizontal
    btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    btnLayout.Padding             = UDim.new(0, 8)
    btnLayout.Parent              = btnBar

    -- Cancel
    local cancelBtn = self:_button(btnBar, "Cancel", COLORS.danger, {
        size = UDim2.new(0, 120, 0, 32),
    })
    cancelBtn.MouseButton1Click:Connect(function()
        widget.Enabled = false
        onDecision(false)
    end)

    -- Approve
    local approveBtn = self:_button(btnBar, "✓  Approve", COLORS.success, {
        size = UDim2.new(0, 120, 0, 32),
    })
    approveBtn.MouseButton1Click:Connect(function()
        widget.Enabled = false
        onDecision(true)
    end)

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
    self.onPull:Destroy()
    self.onExport:Destroy()

    for _, w in pairs(self._widgets) do
        w:Destroy()
    end
end

return UI
