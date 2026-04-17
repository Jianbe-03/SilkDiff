--!nonstrict
--[[
    SilkDiff Popup Module

    Provides a lightweight confirmation dialog that floats over Studio.

    Usage:
        local Popup = require(...)
        local popup = Popup.new(pluginInstance)

        popup:show(
            "⚠  Full Export",
            "This will DELETE all local files and do a full rebuild.\nPull any local changes first!",
            function() -- confirmed
                doTheExport()
            end,
            function() -- cancelled
                print("cancelled")
            end
        )
]]

local Popup = {}
Popup.__index = Popup

local COLORS = {
    bg      = Color3.fromRGB(30, 30, 30),
    bgLight = Color3.fromRGB(50, 50, 50),
    text    = Color3.fromRGB(220, 220, 220),
    warning = Color3.fromRGB(255, 193, 7),
    success = Color3.fromRGB(76, 175, 80),
    danger  = Color3.fromRGB(244, 67, 54),
}

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------
function Popup.new(pluginInstance: Plugin)
    local self = setmetatable({}, Popup)
    self._plugin = pluginInstance
    self._widget = nil
    self:_createWidget()
    return self
end

---------------------------------------------------------------------------
-- Build the persistent widget (hidden at start)
---------------------------------------------------------------------------
function Popup:_createWidget()
    local info = DockWidgetPluginGuiInfo.new(
        Enum.InitialDockState.Float,
        false, false,
        440, 210, 440, 210
    )
    local widget = self._plugin:CreateDockWidgetPluginGui("SilkDiff_Popup", info)
    widget.Title = "SilkDiff"
    self._widget = widget

    local root = Instance.new("Frame")
    root.Name             = "Root"
    root.Size             = UDim2.new(1, 0, 1, 0)
    root.BackgroundColor3 = COLORS.bg
    root.BorderSizePixel  = 0
    root.Parent           = widget

    local layout = Instance.new("UIListLayout")
    layout.SortOrder           = Enum.SortOrder.LayoutOrder
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.Padding             = UDim.new(0, 10)
    layout.Parent              = root

    local pad = Instance.new("UIPadding")
    pad.PaddingTop    = UDim.new(0, 16)
    pad.PaddingBottom = UDim.new(0, 16)
    pad.PaddingLeft   = UDim.new(0, 20)
    pad.PaddingRight  = UDim.new(0, 20)
    pad.Parent        = root
end

---------------------------------------------------------------------------
-- Show the dialog. onCancel is optional.
---------------------------------------------------------------------------
function Popup:show(
    title: string,
    message: string,
    onConfirm: () -> (),
    onCancel: (() -> ())?
)
    local widget = self._widget
    local root   = widget:FindFirstChild("Root") :: Frame

    -- Clear previous content (keep layout + padding)
    for _, c in ipairs(root:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
            c:Destroy()
        end
    end

    -- Title label
    local titleLbl                   = Instance.new("TextLabel")
    titleLbl.Text                    = title
    titleLbl.Font                    = Enum.Font.SourceSansBold
    titleLbl.TextSize                = 18
    titleLbl.TextColor3              = COLORS.warning
    titleLbl.BackgroundTransparency  = 1
    titleLbl.Size                    = UDim2.new(1, 0, 0, 26)
    titleLbl.TextXAlignment          = Enum.TextXAlignment.Center
    titleLbl.LayoutOrder             = 1
    titleLbl.Parent                  = root

    -- Divider line
    local div                = Instance.new("Frame")
    div.Size                 = UDim2.new(1, 0, 0, 1)
    div.BackgroundColor3     = Color3.fromRGB(60, 60, 60)
    div.BorderSizePixel      = 0
    div.LayoutOrder          = 2
    div.Parent               = root

    -- Message
    local msgLbl                   = Instance.new("TextLabel")
    msgLbl.Text                    = message
    msgLbl.Font                    = Enum.Font.SourceSans
    msgLbl.TextSize                = 14
    msgLbl.TextColor3              = COLORS.text
    msgLbl.BackgroundTransparency  = 1
    msgLbl.Size                    = UDim2.new(1, 0, 0, 64)
    msgLbl.TextWrapped             = true
    msgLbl.TextXAlignment          = Enum.TextXAlignment.Center
    msgLbl.LayoutOrder             = 3
    msgLbl.Parent                  = root

    -- Button row
    local btnRow                    = Instance.new("Frame")
    btnRow.Size                     = UDim2.new(1, 0, 0, 36)
    btnRow.BackgroundTransparency   = 1
    btnRow.LayoutOrder              = 4
    btnRow.Parent                   = root

    local btnLayout = Instance.new("UIListLayout")
    btnLayout.FillDirection       = Enum.FillDirection.Horizontal
    btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    btnLayout.Padding             = UDim.new(0, 12)
    btnLayout.Parent              = btnRow

    local function makeBtn(text: string, color: Color3, cb: () -> ())
        local btn                = Instance.new("TextButton")
        btn.Text                 = text
        btn.Font                 = Enum.Font.SourceSansBold
        btn.TextSize             = 14
        btn.TextColor3           = Color3.new(1, 1, 1)
        btn.BackgroundColor3     = color
        btn.BorderSizePixel      = 0
        btn.Size                 = UDim2.new(0, 160, 0, 32)
        btn.AutoButtonColor      = true
        btn.Parent               = btnRow
        local corner             = Instance.new("UICorner")
        corner.CornerRadius      = UDim.new(0, 4)
        corner.Parent            = btn
        btn.MouseButton1Click:Connect(function()
            widget.Enabled = false
            cb()
        end)
    end

    makeBtn("✓  Confirm", COLORS.danger, onConfirm)
    makeBtn("✗  Cancel",  COLORS.bgLight, onCancel or function() end)

    widget.Enabled = true
end

---------------------------------------------------------------------------
-- Destroy
---------------------------------------------------------------------------
function Popup:destroy()
    if self._widget then
        self._widget:Destroy()
        self._widget = nil
    end
end

return Popup
