--!strict
--[[
    SilkDiff Serializer Module

    Converts Roblox instances into a JSON-safe dictionary format that
    can be sent over HTTP to the local SilkDiff server.

    Each instance is serialized into:
        properties  – Key-value pairs of instance properties
        attributes  – Key-value pairs of instance attributes
        tags        – List of CollectionService tags
        source      – Script source code (only for Script / LocalScript / ModuleScript)
        path        – Full dot-separated path (e.g. "Workspace.Models.Tree")
        children    – Recursive list of child instances (for tree serialization)

    Usage:
        local Serializer = require(...)
        local serializer = Serializer.new(settings)

        local data     = serializer:serializeInstance(workspace.Baseplate)
        local fullTree = serializer:serializeTree(workspace)
        local json     = serializer:toJSON(data)
]]

local CollectionService = game:GetService("CollectionService")
local HttpService       = game:GetService("HttpService")

local Serializer = {}
Serializer.__index = Serializer

---------------------------------------------------------------------------
-- Class names that have a Source property
---------------------------------------------------------------------------
local SCRIPT_CLASSES = {
    Script       = true,
    LocalScript  = true,
    ModuleScript = true,
}

---------------------------------------------------------------------------
-- Properties to include for every single instance
---------------------------------------------------------------------------
local CORE_PROPERTIES = {
    "Name",
    "ClassName",
    "Archivable",
}

---------------------------------------------------------------------------
-- Additional properties per ClassName
-- Extend this table whenever you need to track more property types.
---------------------------------------------------------------------------
local CLASS_PROPERTIES: { [string]: { string } } = {
    -- BasePart / Part
    Part = {
        "Anchored", "CanCollide", "CanQuery", "CanTouch", "CastShadow",
        "Color", "Material", "Reflectance", "Size", "Transparency",
        "CFrame", "Shape", "Position", "Orientation",
    },
    MeshPart = {
        "Anchored", "CanCollide", "CanQuery", "CanTouch", "CastShadow",
        "Color", "Material", "Reflectance", "Size", "Transparency",
        "CFrame", "MeshId", "TextureID", "Position", "Orientation",
    },
    SpawnLocation = {
        "Anchored", "CanCollide", "Duration", "Enabled",
        "AllowTeamChangeOnTouch", "Neutral", "TeamColor",
        "Size", "CFrame", "Position", "Orientation",
    },

    -- Containers / organisers
    Model  = { "PrimaryPart" },
    Folder = {},

    -- Scripts
    Script       = { "Disabled", "RunContext" },
    LocalScript  = { "Disabled" },
    ModuleScript = {},

    -- Camera
    Camera = { "CameraType", "FieldOfView", "CFrame" },
    Terrain = {},

    -- Lighting
    Lighting          = {
        "Ambient", "Brightness", "ColorShift_Bottom", "ColorShift_Top",
        "EnvironmentDiffuseScale", "EnvironmentSpecularScale",
        "GlobalShadows", "OutdoorAmbient", "Technology",
        "ClockTime", "GeographicLatitude",
    },
    Atmosphere        = { "Color", "Decay", "Density", "Glare", "Haze", "Offset" },
    Sky               = {
        "CelestialBodiesShown", "MoonAngularSize", "MoonTextureId",
        "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp",
        "StarCount", "SunAngularSize", "SunTextureId",
    },
    BloomEffect       = { "Intensity", "Size", "Threshold" },
    DepthOfFieldEffect = { "FarIntensity", "FocusDistance", "InFocusRadius", "NearIntensity" },
    SunRaysEffect     = { "Intensity", "Spread" },

    -- Sound
    Sound = { "Looped", "PlaybackSpeed", "SoundId", "Volume" },

    -- Value objects
    StringValue = { "Value" },
    IntValue    = { "Value" },
    NumberValue = { "Value" },
    BoolValue   = { "Value" },
    ObjectValue = { "Value" },

    -- GUI
    ScreenGui   = { "DisplayOrder", "Enabled", "IgnoreGuiInset", "ResetOnSpawn", "ZIndexBehavior" },
    Frame       = { "AnchorPoint", "BackgroundColor3", "BackgroundTransparency", "BorderSizePixel", "Position", "Size", "Visible" },
    TextLabel   = { "AnchorPoint", "BackgroundColor3", "BackgroundTransparency", "Font", "Position", "Size", "Text", "TextColor3", "TextScaled", "TextSize", "Visible" },
    TextButton  = { "AnchorPoint", "BackgroundColor3", "BackgroundTransparency", "Font", "Position", "Size", "Text", "TextColor3", "TextScaled", "TextSize", "Visible" },
    TextBox     = { "AnchorPoint", "BackgroundColor3", "BackgroundTransparency", "Font", "Position", "Size", "Text", "TextColor3", "TextScaled", "TextSize", "Visible", "PlaceholderText" },
    ImageLabel  = { "AnchorPoint", "BackgroundColor3", "BackgroundTransparency", "Image", "Position", "Size", "Visible" },
    ImageButton = { "AnchorPoint", "BackgroundColor3", "BackgroundTransparency", "Image", "Position", "Size", "Visible" },
}

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------
function Serializer.new(settings)
    local self = setmetatable({}, Serializer)
    self._settings = settings
    return self
end

---------------------------------------------------------------------------
-- Convert a Roblox value into something JSON-safe
---------------------------------------------------------------------------
function Serializer:_serializeValue(value: any): any
    local t = typeof(value)

    if t == "string" then
        return { t = "string",  v = value }

    elseif t == "number" then
        -- Round to 5 decimal places to avoid floating-point noise
        return { t = "number",  v = math.floor(value * 1e5 + 0.5) / 1e5 }

    elseif t == "boolean" then
        return { t = "boolean", v = value }

    elseif t == "nil" then
        return nil

    elseif t == "Vector3" then
        return { t = "Vector3", v = {
            X = math.floor(value.X * 1e5 + 0.5) / 1e5,
            Y = math.floor(value.Y * 1e5 + 0.5) / 1e5,
            Z = math.floor(value.Z * 1e5 + 0.5) / 1e5,
        }}

    elseif t == "Vector2" then
        return { t = "Vector2", v = {
            X = math.floor(value.X * 1e5 + 0.5) / 1e5,
            Y = math.floor(value.Y * 1e5 + 0.5) / 1e5,
        }}

    elseif t == "CFrame" then
        local c = { value:GetComponents() }
        return { t = "CFrame", v = {
            Position   = { X = c[1],  Y = c[2],  Z = c[3]  },
            RightVector = { X = c[4],  Y = c[5],  Z = c[6]  },
            UpVector    = { X = c[7],  Y = c[8],  Z = c[9]  },
            LookVector  = { X = c[10], Y = c[11], Z = c[12] },
        }}

    elseif t == "Color3" then
        return { t = "Color3", v = {
            R = math.round(value.R * 255),
            G = math.round(value.G * 255),
            B = math.round(value.B * 255),
        }}

    elseif t == "BrickColor" then
        return { t = "BrickColor", v = value.Name }

    elseif t == "UDim2" then
        return { t = "UDim2", v = {
            X = { Scale = value.X.Scale, Offset = value.X.Offset },
            Y = { Scale = value.Y.Scale, Offset = value.Y.Offset },
        }}

    elseif t == "UDim" then
        return { t = "UDim", v = { Scale = value.Scale, Offset = value.Offset } }

    elseif t == "EnumItem" then
        return { t = "Enum", v = tostring(value) }

    elseif t == "Instance" then
        -- Represent instance references as their path
        local parts: { string } = {}
        local current: Instance? = value
        while current and current ~= game do
            table.insert(parts, 1, current.Name)
            current = current.Parent
        end
        return { t = "Instance", v = table.concat(parts, ".") }

    else
        return { t = "unknown", v = tostring(value) }
    end
end

---------------------------------------------------------------------------
-- Ensure an instance has a SilkDiffId attribute when UseInstanceIds is on.
-- Returns the existing or newly-assigned ID, or nil when the feature is off.
---------------------------------------------------------------------------
function Serializer:_ensureSilkDiffId(instance: Instance): string?
    local enabled = self._settings:get("UseInstanceIds")
    if enabled ~= "true" and enabled ~= true then return nil end

    local existing: string? = instance:GetAttribute("SilkDiffId") :: string?
    if existing and existing ~= "" then return existing end

    local newId = HttpService:GenerateGUID(false)
    instance:SetAttribute("SilkDiffId", newId)
    return newId
end

---------------------------------------------------------------------------
-- Get the dot-separated path of an instance
---------------------------------------------------------------------------
function Serializer:_getPath(instance: Instance): string
    local parts: { string } = {}
    local current: Instance? = instance

    while current and current ~= game do
        table.insert(parts, 1, current.Name)
        current = current.Parent
    end

    return table.concat(parts, ".")
end

---------------------------------------------------------------------------
-- Get the parent's Name (for the "Parent" field in the properties file)
---------------------------------------------------------------------------
function Serializer:_getParentName(instance: Instance): string
    if instance.Parent and instance.Parent ~= game then
        return instance.Parent.Name
    end
    return "game"
end

---------------------------------------------------------------------------
-- Serialize all tracked properties of an instance
---------------------------------------------------------------------------
function Serializer:serializeProperties(instance: Instance): { [string]: any }
    local properties: { [string]: any } = {}

    -- Always include core properties
    for _, propName in ipairs(CORE_PROPERTIES) do
        local ok, val = pcall(function()
            return (instance :: any)[propName]
        end)
        if ok then
            properties[propName] = self:_serializeValue(val)
        end
    end

    -- Parent reference
    properties["Parent"] = self:_getParentName(instance)

    -- Class-specific properties
    local classProps = CLASS_PROPERTIES[instance.ClassName]
    if classProps then
        for _, propName in ipairs(classProps) do
            local ok, val = pcall(function()
                return (instance :: any)[propName]
            end)
            if ok then
                properties[propName] = self:_serializeValue(val)
            end
        end
    end

    return properties
end

---------------------------------------------------------------------------
-- Serialize all attributes of an instance
---------------------------------------------------------------------------
function Serializer:serializeAttributes(instance: Instance): { [string]: any }
    local attributes: { [string]: any } = {}
    for name, value in pairs(instance:GetAttributes()) do
        attributes[name] = self:_serializeValue(value)
    end
    return attributes
end

---------------------------------------------------------------------------
-- Serialize the tags of an instance
---------------------------------------------------------------------------
function Serializer:serializeTags(instance: Instance): { string }
    return CollectionService:GetTags(instance)
end

---------------------------------------------------------------------------
-- Get the source code of a script (returns nil for non-scripts)
---------------------------------------------------------------------------
function Serializer:serializeSource(instance: Instance): string?
    if not SCRIPT_CLASSES[instance.ClassName] then
        return nil
    end

    local ok, source = pcall(function()
        return (instance :: any).Source
    end)

    return if ok then source else nil
end

---------------------------------------------------------------------------
-- Serialize a single instance (without its children)
---------------------------------------------------------------------------
function Serializer:serializeInstance(instance: Instance): { [string]: any }
    return {
        path       = self:_getPath(instance),
        className  = instance.ClassName,
        name       = instance.Name,
        silkId     = self:_ensureSilkDiffId(instance),
        properties = self:serializeProperties(instance),
        attributes = self:serializeAttributes(instance),
        tags       = self:serializeTags(instance),
        source     = self:serializeSource(instance),
    }
end

---------------------------------------------------------------------------
-- Serialize an entire instance tree (instance + all descendants)
---------------------------------------------------------------------------
function Serializer:serializeTree(root: Instance): { [string]: any }
    local data = self:serializeInstance(root)

    local children = {}
    for _, child in ipairs(root:GetChildren()) do
        table.insert(children, self:serializeTree(child))
    end

    if #children > 0 then
        data.children = children
    end

    return data
end

---------------------------------------------------------------------------
-- Serialize a list of changed instances (from InstanceWatcher output)
---------------------------------------------------------------------------
function Serializer:serializeChanges(changes: { any }): { any }
    local serialized = {}

    for _, change in ipairs(changes) do
        table.insert(serialized, {
            instance = self:serializeInstance(change.instance),
            changes  = change.changes,
            path     = change.path,
        })
    end

    return serialized
end

---------------------------------------------------------------------------
-- JSON helpers (thin wrappers around HttpService)
---------------------------------------------------------------------------
function Serializer:toJSON(data: any): string
    return HttpService:JSONEncode(data)
end

function Serializer:fromJSON(jsonString: string): any
    return HttpService:JSONDecode(jsonString)
end

return Serializer
