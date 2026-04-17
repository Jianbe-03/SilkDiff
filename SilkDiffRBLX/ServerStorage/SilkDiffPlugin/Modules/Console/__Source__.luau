--!nonstrict
--[[
    SilkDiff Console Module

    A docked output panel that replaces cluttering the Studio Output window.
    Supports RichText-colored log levels so messages are easy to scan.

    Usage:
        local Console = require(...)
        local console = Console.new(pluginInstance, toolbar)

        console:log("Server connected",      "success")
        console:log("Checking for changes",  "info")
        console:log("Large file detected",   "warn")
        console:log("Connection refused",    "error")

    NOTE: Each log line is a separate TextLabel so we never hit Roblox's
    per-label text limit. The ring buffer caps at MAX_LINES labels total.
]]

local Console = {}
Console.__index = Console

local MAX_LINES = 200   -- oldest label destroyed when this is exceeded

-- RichText hex colours per level
local LEVEL_COLOR = {
    info    = "rgb(200,200,200)",
    success = "rgb(100,220,100)",
    warn    = "rgb(255,200,70)",
    error   = "rgb(240,90,90)",
    _time   = "rgb(100,100,100)",
}

local LEVEL_ICON = {
    info    = "●",
    success = "✓",
    warn    = "⚠",
    error   = "✗",
}

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------
function Console.new(pluginInstance: Plugin, toolbar: PluginToolbar, settings)
    local self      = setmetatable({}, Console)
    self._plugin    = pluginInstance
    self._toolbar   = toolbar
    self._settings  = settings
    self._labels    = {} :: { TextLabel }
    self._nextOrder = 1
    self._widget    = nil
    self._scroll    = nil

    self:_createWidget()
    self:_createButton()
    return self
end

---------------------------------------------------------------------------
-- Build the docked widget
---------------------------------------------------------------------------
function Console:_createWidget()
    local info = DockWidgetPluginGuiInfo.new(
        Enum.InitialDockState.Float,
        false, false,
        700, 220, 400, 120
    )
    local widget        = self._plugin:CreateDockWidgetPluginGui("SilkDiff_Console", info)
    widget.Title        = "SilkDiff Console"
    self._widget        = widget

    -- Header bar
    local header                = Instance.new("Frame")
    header.Size                 = UDim2.new(1, 0, 0, 28)
    header.BackgroundColor3     = Color3.fromRGB(20, 20, 20)
    header.BorderSizePixel      = 0
    header.Parent               = widget

    local titleLbl                      = Instance.new("TextLabel")
    titleLbl.Text                       = "  🧵  SilkDiff Console"
    titleLbl.Font                       = Enum.Font.SourceSansBold
    titleLbl.TextSize                   = 13
    titleLbl.TextColor3                 = Color3.fromRGB(180, 180, 180)
    titleLbl.BackgroundTransparency     = 1
    titleLbl.Size                       = UDim2.new(0.75, 0, 1, 0)
    titleLbl.TextXAlignment             = Enum.TextXAlignment.Left
    titleLbl.Parent                     = header

    local clearBtn                  = Instance.new("TextButton")
    clearBtn.Text                   = "Clear"
    clearBtn.Font                   = Enum.Font.SourceSans
    clearBtn.TextSize               = 12
    clearBtn.TextColor3             = Color3.fromRGB(180, 180, 180)
    clearBtn.BackgroundColor3       = Color3.fromRGB(50, 50, 50)
    clearBtn.BorderSizePixel        = 0
    clearBtn.Size                   = UDim2.new(0, 56, 0, 20)
    clearBtn.Position               = UDim2.new(1, -64, 0, 4)
    clearBtn.AutoButtonColor        = true
    clearBtn.Parent                 = header

    local cc = Instance.new("UICorner")
    cc.CornerRadius = UDim.new(0, 3)
    cc.Parent       = clearBtn

    clearBtn.MouseButton1Click:Connect(function() self:clear() end)

    -- Scrolling log area
    local scroll                    = Instance.new("ScrollingFrame")
    scroll.Size                     = UDim2.new(1, 0, 1, -28)
    scroll.Position                 = UDim2.new(0, 0, 0, 28)
    scroll.BackgroundColor3         = Color3.fromRGB(18, 18, 18)
    scroll.BorderSizePixel          = 0
    scroll.ScrollBarThickness       = 4
    scroll.ScrollBarImageColor3     = Color3.fromRGB(80, 80, 80)
    scroll.AutomaticCanvasSize      = Enum.AutomaticSize.XY
    scroll.CanvasSize               = UDim2.new(0, 0, 0, 0)
    scroll.Parent                   = widget
    self._scroll                    = scroll

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding   = UDim.new(0, 0)
    layout.Parent    = scroll

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft   = UDim.new(0, 6)
    pad.PaddingRight  = UDim.new(0, 6)
    pad.PaddingTop    = UDim.new(0, 2)
    pad.PaddingBottom = UDim.new(0, 2)
    pad.Parent        = scroll
end

---------------------------------------------------------------------------
-- Add a Console toolbar button
---------------------------------------------------------------------------
function Console:_createButton()
    local btn = self._toolbar:CreateButton(
        "SilkDiff_Console", "Open SilkDiff Console",
        "rbxassetid://6031280882", "Console"
    )
    btn.Click:Connect(function()
        self._widget.Enabled = not self._widget.Enabled
    end)
end

---------------------------------------------------------------------------
-- Append a single RichText label to the scroll frame
---------------------------------------------------------------------------
function Console:_appendLabel(richLine: string)
    -- Evict oldest when at capacity
    if #self._labels >= MAX_LINES then
        local oldest = table.remove(self._labels, 1)
        if oldest and oldest.Parent then
            oldest:Destroy()
        end
    end

    local lbl                       = Instance.new("TextLabel")
    lbl.RichText                    = true
    lbl.Text                        = richLine
    lbl.Font                        = Enum.Font.Code
    lbl.TextSize                    = 12
    lbl.TextColor3                  = Color3.fromRGB(200, 200, 200)
    lbl.BackgroundTransparency      = 1
    lbl.Size                        = UDim2.new(0, 0, 0, 16)
    lbl.AutomaticSize               = Enum.AutomaticSize.X
    lbl.TextXAlignment              = Enum.TextXAlignment.Left
    lbl.TextWrapped                 = false
    lbl.TextTruncate                = Enum.TextTruncate.None
    lbl.LayoutOrder                 = self._nextOrder
    lbl.Parent                      = self._scroll

    self._nextOrder += 1
    table.insert(self._labels, lbl)

    -- Auto-scroll to the newest line (keep X position)
    task.defer(function()
        if not self._scroll then return end
        local cs = self._scroll.AbsoluteCanvasSize.Y
        local ws = self._scroll.AbsoluteSize.Y
        if cs > ws then
            self._scroll.CanvasPosition = Vector2.new(
                self._scroll.CanvasPosition.X,
                cs - ws
            )
        end
    end)
end

---------------------------------------------------------------------------
-- Public: log a message at a given level
-- level = "info" | "success" | "warn" | "error"
---------------------------------------------------------------------------
function Console:log(message: string, level: string?)
    local lvl   = level or "info"
    local color = LEVEL_COLOR[lvl]  or LEVEL_COLOR.info
    local icon  = LEVEL_ICON[lvl]   or "●"

    local t  = os.date("*t") :: any
    local ts = string.format("%02d:%02d:%02d", t.hour, t.min, t.sec)

    local richLine = string.format(
        '<font color="%s">%s</font> <font color="%s">%s %s</font>',
        LEVEL_COLOR._time, ts,
        color, icon, message
    )

    -- Decide whether to mirror to the Studio Output window.
    -- When UseConsole=true only critical errors go there; everything else
    -- stays in our own panel to keep the Output window clean.
    local useConsole = self._settings and self._settings:get("UseConsole") == "true"
    if useConsole then
        if lvl == "error" then
            warn("[SilkDiff CRITICAL] " .. message)
        end
    else
        -- Legacy mode: mirror everything like before
        if lvl == "error" then
            warn("[SilkDiff] " .. message)
        else
            print("[SilkDiff] " .. message)
        end
    end

    self:_appendLabel(richLine)
end

---------------------------------------------------------------------------
-- Public: clear all log lines
---------------------------------------------------------------------------
function Console:clear()
    for _, lbl in ipairs(self._labels) do
        if lbl and lbl.Parent then lbl:Destroy() end
    end
    self._labels    = {}
    self._nextOrder = 1
end

---------------------------------------------------------------------------
-- Open the console panel (useful to call after logging an error)
---------------------------------------------------------------------------
function Console:open()
    if self._widget then
        self._widget.Enabled = true
    end
end

---------------------------------------------------------------------------
-- Destroy
---------------------------------------------------------------------------
function Console:destroy()
    if self._widget then
        self._widget:Destroy()
        self._widget = nil
    end
end

return Console
