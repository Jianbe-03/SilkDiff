--!strict
--[[
    SilkDiff Signal Module

    A lightweight custom event/signal implementation.
    Used for inter-module communication within the plugin.

    Usage:
        local Signal = require(...)
        local mySignal = Signal.new()

        -- Connect a listener
        local connection = mySignal:Connect(function(value)
            print("Received:", value)
        end)

        -- Fire the signal to all listeners
        mySignal:Fire("Hello!")

        -- Disconnect a single listener
        connection:Disconnect()

        -- Destroy the entire signal
        mySignal:Destroy()
]]

---------------------------------------------------------------------------
-- Connection class
-- Returned by Signal:Connect(). Call :Disconnect() to stop listening.
---------------------------------------------------------------------------
local Connection = {}
Connection.__index = Connection

function Connection.new(callback: (...any) -> ())
    local self = setmetatable({}, Connection)
    self._callback = callback
    self._connected = true
    return self
end

function Connection:Disconnect()
    self._connected = false
end

---------------------------------------------------------------------------
-- Signal class
---------------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal

function Signal.new()
    local self = setmetatable({}, Signal)
    self._connections = {} :: { typeof(Connection.new(function() end)) }
    return self
end

--- Connect a callback function to this signal.
--- Returns a Connection that can be disconnected later.
function Signal:Connect(callback: (...any) -> ()): typeof(Connection.new(function() end))
    local connection = Connection.new(callback)
    table.insert(self._connections, connection)
    return connection
end

--- Fire the signal, calling all connected callbacks with the given arguments.
--- Automatically cleans up disconnected listeners.
function Signal:Fire(...: any)
    for i = #self._connections, 1, -1 do
        local conn = self._connections[i]
        if conn._connected then
            task.spawn(conn._callback, ...)
        else
            table.remove(self._connections, i)
        end
    end
end

--- Destroy the signal and disconnect all listeners.
function Signal:Destroy()
    for _, conn in ipairs(self._connections) do
        conn._connected = false
    end
    self._connections = {}
end

return Signal
