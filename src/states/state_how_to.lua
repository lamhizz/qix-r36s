-- ==============================================================================
-- State: HOW_TO
-- Displays retro arcade gameplay instructions and controls manual.
-- ==============================================================================

local Audio = require("audio")

local StateHowTo = {}
StateHowTo.__index = StateHowTo

function StateHowTo.new(game)
    local self = setmetatable({}, StateHowTo)
    self.game = game
    return self
end

function StateHowTo:enter()
    self.game.howToScrollY = 0
end

function StateHowTo:update(dt)
    local game = self.game
    game.titleBlink = game.titleBlink + dt * 4
    if game.titleAttractQix then
        game.titleAttractQix:update(dt)
    end

    -- Smooth vertical scrolling with D-Pad or Left Stick
    local scrollSpeed = 260
    local scrollDelta = 0
    if love.keyboard.isDown("up", "w") then
        scrollDelta = scrollDelta - scrollSpeed * dt
    elseif love.keyboard.isDown("down", "s") then
        scrollDelta = scrollDelta + scrollSpeed * dt
    end

    local joysticks = love.joystick.getJoysticks()
    for _, joy in ipairs(joysticks) do
        if joy:isGamepad() then
            if joy:isGamepadDown("dpup") then
                scrollDelta = scrollDelta - scrollSpeed * dt
            elseif joy:isGamepadDown("dpdown") then
                scrollDelta = scrollDelta + scrollSpeed * dt
            end
            local ly = joy:getGamepadAxis("lefty")
            if ly and math.abs(ly) > 0.3 then
                scrollDelta = scrollDelta + ly * scrollSpeed * dt
            end
        end
    end
    if scrollDelta ~= 0 then
        game.howToScrollY = math.max(0, math.min(game.howToMaxScroll or 120, (game.howToScrollY or 0) + scrollDelta))
    end
end

function StateHowTo:draw()
    self.game:drawHowTo()
end

function StateHowTo:keypressed(key)
    local game = self.game
    if key == "up" or key == "w" then
        game.howToScrollY = math.max(0, (game.howToScrollY or 0) - 50)
        Audio.play("tick")
        return true
    elseif key == "down" or key == "s" then
        game.howToScrollY = math.min(game.howToMaxScroll or 120, (game.howToScrollY or 0) + 50)
        Audio.play("tick")
        return true
    elseif key == "left" or key == "a" then
        game.howToPage = math.max(1, (game.howToPage or 1) - 1)
        game.howToScrollY = 0
        Audio.play("tick")
        return true
    elseif key == "right" or key == "d" then
        game.howToPage = math.min(2, (game.howToPage or 1) + 1)
        game.howToScrollY = 0
        Audio.play("tick")
        return true
    elseif key == "escape" or key == "return" or key == "space" or key == "b" or key == "x" or key == "k" then
        game:setState("TITLE", "keyboard_howto_back")
        Audio.play("tick")
        return true
    end
    return false
end

function StateHowTo:gamepadpressed(joy, btn)
    local game = self.game
    if btn == "dpup" then
        game.howToScrollY = math.max(0, (game.howToScrollY or 0) - 50)
        Audio.play("tick")
        return true
    elseif btn == "dpdown" then
        game.howToScrollY = math.min(game.howToMaxScroll or 120, (game.howToScrollY or 0) + 50)
        Audio.play("tick")
        return true
    elseif btn == "dpleft" or btn == "leftshoulder" then
        game.howToPage = math.max(1, (game.howToPage or 1) - 1)
        game.howToScrollY = 0
        Audio.play("tick")
        return true
    elseif btn == "dpright" or btn == "rightshoulder" then
        game.howToPage = math.min(2, (game.howToPage or 1) + 1)
        game.howToScrollY = 0
        Audio.play("tick")
        return true
    elseif btn == "a" or btn == "b" or btn == "start" or btn == "back" then
        game:setState("TITLE", "gamepad_howto_back")
        Audio.play("tick")
        return true
    end
    return false
end

function StateHowTo:leave()
end

return StateHowTo
