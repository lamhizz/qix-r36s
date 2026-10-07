-- ==============================================================================
-- State: TITLE
-- Handles arcade attract mode, difficulty selector, and main menu navigation.
-- ==============================================================================

local Logger = require("logger")
local Audio = require("audio")

local StateTitle = {}
StateTitle.__index = StateTitle

function StateTitle.new(game)
    local self = setmetatable({}, StateTitle)
    self.game = game
    return self
end

function StateTitle:enter()
    local game = self.game
    game.titleCooldown = 0.40
    game.titleBlink = 0
    if game.titleGrid then
        game.titleGrid:init()
    end
end

function StateTitle:update(dt)
    local game = self.game
    game.titleBlink = game.titleBlink + dt * 4
    if game.titleAttractQix then
        game.titleAttractQix:update(dt)
    end
end

function StateTitle:draw()
    self.game:drawTitle()
end

function StateTitle:keypressed(key)
    local game = self.game
    if (game.titleCooldown or 0) > 0 then return false end

    if key == "up" or key == "w" then
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
    elseif key == "return" or key == "space" or key == "z" or key == "j" then
        game:executeTitleOption()
        return true
    elseif key == "escape" then
        if game.titleIndex == #game.titleItems then
            love.event.quit()
        else
            game.titleIndex = #game.titleItems
            Audio.play("tick")
        end
        return true
    end
    return false
end

function StateTitle:gamepadpressed(joy, btn)
    local game = self.game
    if (game.titleCooldown or 0) > 0 then return false end

    if btn == "dpup" then
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
        game:executeTitleOption()
        return true
    end
    return false
end

function StateTitle:leave()
end

return StateTitle
