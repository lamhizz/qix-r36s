-- ==============================================================================
-- QIX - Finite State Machine (Lifecycle Router)
-- Decouples game scenes, eliminates monolithic coupling, and isolates regressions.
-- ==============================================================================

local StateMachine = {}
StateMachine.__index = StateMachine

function StateMachine.new(states)
    local self = setmetatable({}, StateMachine)
    self.states = states or {}
    self.current = nil
    self.currentStateName = nil
    return self
end

function StateMachine:change(stateName, ...)
    if self.current and self.current.leave then
        self.current:leave()
    end
    self.currentStateName = stateName
    self.current = self.states[stateName]
    if self.current and self.current.enter then
        self.current:enter(...)
    end
end

function StateMachine:update(dt)
    if self.current and self.current.update then
        self.current:update(dt)
    end
end

function StateMachine:draw()
    if self.current and self.current.draw then
        self.current:draw()
    end
end

function StateMachine:keypressed(key)
    if self.current and self.current.keypressed then
        return self.current:keypressed(key)
    end
    return false
end

function StateMachine:gamepadpressed(joy, btn)
    if self.current and self.current.gamepadpressed then
        return self.current:gamepadpressed(joy, btn)
    end
    return false
end

return StateMachine
