-- ==============================================================================
-- State: PAUSED
-- In-game pause menu with resume, restart, settings, and title return options.
-- ==============================================================================

local Audio = require("audio")

local StatePause = {}
StatePause.__index = StatePause

function StatePause.new(game)
    local self = setmetatable({}, StatePause)
    self.game = game
    return self
end

function StatePause:enter()
    local game = self.game
    game.pauseIndex = 1
    game.pauseOpenedAt = love.timer.getTime()
    Audio.stopAll()
end

function StatePause:update(dt)
end

function StatePause:draw()
    local game = self.game
    -- Draw playfield in background
    game:drawHUD()
    if game.grid then
        pcall(game.grid.draw, game.grid, game.offsetX, game.offsetY, game.scaleX, game.scaleY)
    end
    -- Draw pause overlay
    game:drawPauseMenu()
end

function StatePause:keypressed(key)
    local game = self.game
    local now = love.timer.getTime()
    if (now - (game.pauseOpenedAt or 0)) < 0.15 then
        return true
    end

    if key == "escape" or key == "p" or key == "b" or key == "backspace" then
        game:setState("PLAYING", "keyboard_pause_resume")
        Audio.play("tick")
        return true
    elseif key == "up" or key == "w" then
        game:navMenu("up")
        return true
    elseif key == "down" or key == "s" then
        game:navMenu("down")
        return true
    elseif key == "left" or key == "a" then
        game:navMenu("left")
        return true
    elseif key == "right" or key == "d" then
        game:navMenu("right")
        return true
    elseif key == "return" or key == "space" or key == "z" then
        game:executePauseOption()
        return true
    end
    return false
end

function StatePause:gamepadpressed(joy, btn)
    local game = self.game
    local now = love.timer.getTime()
    if (now - (game.pauseOpenedAt or 0)) < 0.15 then
        return true
    end

    if btn == "b" or btn == "back" then
        game:setState("PLAYING", "gamepad_pause_back")
        Audio.play("tick")
        return true
    elseif btn == "dpup" then
        game:navMenu("up")
        return true
    elseif btn == "dpdown" then
        game:navMenu("down")
        return true
    elseif btn == "dpleft" then
        game:navMenu("left")
        return true
    elseif btn == "dpright" then
        game:navMenu("right")
        return true
    elseif btn == "a" or btn == "start" then
        game:executePauseOption()
        return true
    end
    return false
end

function StatePause:leave()
end

return StatePause
