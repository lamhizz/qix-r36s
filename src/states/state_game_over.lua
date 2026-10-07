-- ==============================================================================
-- State: GAME_OVER
-- Displays debriefing card, score tally roll, pilot ranking, and retry prompt.
-- ==============================================================================

local Audio = require("audio")
local Particles = require("particles")
local Logger = require("logger")

local StateGameOver = {}
StateGameOver.__index = StateGameOver

function StateGameOver.new(game)
    local self = setmetatable({}, StateGameOver)
    self.game = game
    return self
end

function StateGameOver:enter()
    local game = self.game
    game.gameOverAnim = {
        timer = 0,
        cardY = 160,
        targetCardY = 22,
        displayScore = 0,
        tallySpeed = math.max(120, math.floor(game.score / 1.0)),
        tallyDone = (game.score == 0),
        rankRevealed = (game.score == 0),
        inputLockout = 0.5,
        selectedButton = 1,
        sparkTimer = 0,
        shimmer = 0
    }
    Logger.info("GAME", "Game Over! Score: %d | Level: %d | Cuts: %d | New Record: %s",
        game.score or 0, game.level or 1, game.totalCuts or 0, tostring(game.isNewRecord))
end

function StateGameOver:update(dt)
    local game = self.game
    local anim = game.gameOverAnim
    if not anim then return end

    anim.timer = anim.timer + dt
    anim.shimmer = (anim.shimmer + dt * 2.5) % 6.28
    if anim.inputLockout > 0 then
        anim.inputLockout = anim.inputLockout - dt
    end

    -- Smooth spring slide-up
    anim.cardY = anim.cardY + (anim.targetCardY - anim.cardY) * math.min(1, dt * 8)

    -- Rolling score count-up
    if not anim.tallyDone then
        anim.displayScore = math.min(game.score, anim.displayScore + math.ceil(anim.tallySpeed * dt))
        if anim.displayScore >= game.score then
            anim.displayScore = game.score
            anim.tallyDone = true
            if not anim.rankRevealed then
                anim.rankRevealed = true
                Audio.play("bonus")
                local rx = 50 + 330 + 90
                local ry = anim.cardY + 48 + 47
                pcall(Particles.spawnCaptureBurst, rx, ry, true, 20)
            end
        end
    end

    -- Periodic celebratory confetti sparks if new all-time record
    if game.isNewRecord then
        anim.sparkTimer = anim.sparkTimer + dt
        if anim.sparkTimer >= 0.15 then
            anim.sparkTimer = 0
            local sx = love.math.random(60, 580)
            local sy = love.math.random(30, 440)
            pcall(Particles.spawnCutSpark, sx, sy, love.math.random(-1, 1), love.math.random(-1, 1), love.math.random() > 0.5)
        end
    end
end

function StateGameOver:draw()
    local game = self.game
    if game.grid then
        pcall(game.grid.draw, game.grid, game.offsetX, game.offsetY, game.scaleX, game.scaleY)
    end
    game:drawGameOver()
end

function StateGameOver:keypressed(key)
    local game = self.game
    local anim = game.gameOverAnim
    if not anim or (anim.inputLockout and anim.inputLockout > 0) then return false end

    -- Fast-forward rolling count
    if not anim.tallyDone then
        anim.displayScore = game.score
        anim.tallyDone = true
        anim.rankRevealed = true
        return true
    end

    if key == "left" or key == "up" or key == "w" then
        anim.selectedButton = 1
        Audio.play("tick")
        return true
    elseif key == "right" or key == "down" or key == "s" then
        anim.selectedButton = 2
        Audio.play("tick")
        return true
    elseif key == "return" or key == "space" or key == "z" or key == "j" then
        if anim.selectedButton == 2 then
            Audio.play("tick")
            game:setState("TITLE", "keyboard_gameover_quit")
        else
            Audio.play("start")
            game:startNewGame()
        end
        return true
    elseif key == "escape" or key == "b" or key == "x" then
        Audio.play("tick")
        game:setState("TITLE", "keyboard_gameover_back")
        return true
    end
    return false
end

function StateGameOver:gamepadpressed(joy, btn)
    local game = self.game
    local anim = game.gameOverAnim
    if not anim or (anim.inputLockout and anim.inputLockout > 0) then return false end

    if not anim.tallyDone then
        anim.displayScore = game.score
        anim.tallyDone = true
        anim.rankRevealed = true
        return true
    end

    if btn == "dpleft" or btn == "dpup" then
        anim.selectedButton = 1
        Audio.play("tick")
        return true
    elseif btn == "dpright" or btn == "dpdown" then
        anim.selectedButton = 2
        Audio.play("tick")
        return true
    elseif btn == "a" or btn == "start" then
        if anim.selectedButton == 2 then
            Audio.play("tick")
            game:setState("TITLE", "gamepad_gameover_quit")
        else
            Audio.play("start")
            game:startNewGame()
        end
        return true
    elseif btn == "b" or btn == "back" then
        Audio.play("tick")
        game:setState("TITLE", "gamepad_gameover_back")
        return true
    end
    return false
end

function StateGameOver:leave()
end

return StateGameOver
