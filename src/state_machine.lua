-- ==============================================================================
-- QIX - Finite State Machine (Lifecycle Router)
-- Decouples game scenes, eliminates monolithic coupling, and isolates regressions.
-- ==============================================================================

local unpack = table.unpack or unpack

local StateMachine = {}
StateMachine.__index = StateMachine

function StateMachine.new(states)
    local self = setmetatable({}, StateMachine)
    self.states = states or {}
    self.current = nil
    self.currentStateName = nil
    self.isUpdating = false
    self.pendingChange = nil
    return self
end

function StateMachine:change(stateName, ...)
    if self.isUpdating then
        self.pendingChange = { stateName = stateName, args = { ... } }
        return
    end
    self:_applyChange(stateName, ...)
end

function StateMachine:_applyChange(stateName, ...)
    if self.current and self.current.leave then
        pcall(self.current.leave, self.current)
    end
    self.currentStateName = stateName
    self.current = self.states[stateName]
    if self.current and self.current.enter then
        pcall(self.current.enter, self.current, ...)
    end
end

function StateMachine:update(dt)
    self.isUpdating = true
    if self.current and self.current.update then
        pcall(self.current.update, self.current, dt)
    end
    self.isUpdating = false

    if self.pendingChange then
        local p = self.pendingChange
        self.pendingChange = nil
        self:_applyChange(p.stateName, unpack(p.args))
    end
end

function StateMachine:draw()
    if self.current and self.current.draw then
        pcall(self.current.draw, self.current)
    end
end

function StateMachine:keypressed(key)
    if self.current and self.current.keypressed then
        local ok, res = pcall(self.current.keypressed, self.current, key)
        return ok and res or false
    end
    return false
end

function StateMachine:gamepadpressed(joy, btn)
    if self.current and self.current.gamepadpressed then
        local ok, res = pcall(self.current.gamepadpressed, self.current, joy, btn)
        return ok and res or false
    end
    return false
end

return StateMachine
