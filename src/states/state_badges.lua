-- ==============================================================================
-- State: BADGES
-- Displays retro arcade achievements, badge unlock criteria, and status.
-- ==============================================================================

local Audio = require("audio")

local StateBadges = {}
StateBadges.__index = StateBadges

function StateBadges.new(game)
    local self = setmetatable({}, StateBadges)
    self.game = game
    return self
end

function StateBadges:enter()
end

function StateBadges:update(dt)
end

function StateBadges:draw()
    self.game:drawBadgesGallery()
end

function StateBadges:keypressed(key)
    local game = self.game
    if key == "up" or key == "w" then
        game:navMenu("up")
        return true
    elseif key == "down" or key == "s" then
        game:navMenu("down")
        return true
    elseif key == "escape" or key == "return" or key == "space" or key == "b" or key == "x" or key == "k" then
        game:setState("TITLE", "keyboard_badges_back")
        Audio.play("tick")
        return true
    end
    return false
end

function StateBadges:gamepadpressed(joy, btn)
    local game = self.game
    if btn == "dpup" then
        game:navMenu("up")
        return true
    elseif btn == "dpdown" then
        game:navMenu("down")
        return true
    elseif btn == "a" or btn == "b" or btn == "start" or btn == "back" then
        game:setState("TITLE", "gamepad_badges_back")
        Audio.play("tick")
        return true
    end
    return false
end

function StateBadges:leave()
end

return StateBadges
