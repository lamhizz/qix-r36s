-- ==============================================================================
-- State: DEAD
-- Handles player death sequence, respawn cooldown, and life depletion.
-- ==============================================================================

local Sparx = require("sparx")
local Logger = require("logger")
local Audio = require("audio")

local StateDead = {}
StateDead.__index = StateDead

function StateDead.new(game)
    local self = setmetatable({}, StateDead)
    self.game = game
    return self
end

function StateDead:enter(reason)
    self.game.deathTimer = 1.0
    Logger.breadcrumb("DEATH", "Entered StateDead: reason=%s, remaining lives=%d", tostring(reason), self.game.lives)
end

function StateDead:update(dt)
    local game = self.game
    game.deathTimer = game.deathTimer - dt

    if game.deathTimer <= 0 then
        if game.lives > 0 then
            local cfg = game.DIFFICULTY_CONFIGS[game.difficulty] or game.DIFFICULTY_CONFIGS.ARCADE
            game.player:respawn()
            game.player:applyDifficulty(cfg)
            -- Reset Sparx to safe active perimeter positions away from player
            local s1X, s1Y = game.grid:findNearestActiveBorder(0, 0)
            local s2X, s2Y = game.grid:findNearestActiveBorder(game.grid.width - 1, 0)
            game.sparxList = {
                Sparx.new(game.grid, s1X, s1Y, true, false, cfg.speedMult),
                Sparx.new(game.grid, s2X, s2Y, false, false, cfg.speedMult)
            }
            game.bannerText = "** SAFE SHIELD ACTIVE **"
            game.bannerTimer = 1.8
            game:setState("PLAYING", "respawn")
        else
            if game.score > (game.sessionInitialHighScore or 0) and game.score > 0 then
                game.isNewRecord = true
                Audio.play("fanfare")
            else
                game.isNewRecord = false
            end
            game:saveHighScore()
            game:setState("GAME_OVER", "lives_depleted")
        end
    end
end

function StateDead:draw()
    local game = self.game
    -- Render HUD & Playfield
    pcall(game.drawHUD, game)
    if game.grid then
        pcall(game.grid.draw, game.grid, game.offsetX, game.offsetY, game.scaleX, game.scaleY)
    end
    -- Border loader
    local boardW = game.grid.width * game.scaleX
    local boardH = game.grid.height * game.scaleY
    pcall(game.BorderFX.draw, game.offsetX, game.offsetY, boardW, boardH)

    -- Entities (frozen during death)
    for _, qix in ipairs(game.qixList) do
        pcall(qix.draw, qix, game.offsetX, game.offsetY, game.scaleX, game.scaleY)
    end
    for _, spx in ipairs(game.sparxList) do
        pcall(spx.draw, spx, game.offsetX, game.offsetY, game.scaleX, game.scaleY)
    end

    -- Visual FX (Explosion shards)
    pcall(game.Particles.draw)
    pcall(game.AmbientShips.draw)
    love.graphics.setLineWidth(1)
end

function StateDead:leave()
end

return StateDead
