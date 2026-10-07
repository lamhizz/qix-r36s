-- ==============================================================================
-- State: LEVEL_CLEAR
-- Displays 100% uncovered background artwork showcase & level-clear bonus tally.
-- ==============================================================================

local StateLevelClear = {}
StateLevelClear.__index = StateLevelClear

function StateLevelClear.new(game)
    local self = setmetatable({}, StateLevelClear)
    self.game = game
    return self
end

function StateLevelClear:enter()
    self.game.clearPhase = "SCORES"
    self.game.clearTimer = 2.5
end

function StateLevelClear:update(dt)
    local game = self.game
    if game.clearPhase == "SCORES" then
        game.clearTimer = game.clearTimer - dt
        if game.clearTimer <= 0 then
            game.clearPhase = "SHOWCASE"
        end
    end
end

function StateLevelClear:draw()
    self.game:drawLevelClear()
end

function StateLevelClear:advance()
    local game = self.game
    if game.clearPhase == "SCORES" then
        game.clearPhase = "SHOWCASE"
    elseif game.clearPhase == "SHOWCASE" then
        game:startLevel(game.level + 1)
    end
end

function StateLevelClear:keypressed(key)
    if key == "a" or key == "return" or key == "space" then
        self:advance()
        return true
    end
    return false
end

function StateLevelClear:gamepadpressed(joy, btn)
    if btn == "a" or btn == "start" then
        self:advance()
        return true
    end
    return false
end

function StateLevelClear:leave()
end

return StateLevelClear
