-- ==============================================================================
-- State: PLAYING
-- Core active gameplay loop: Marker navigation, territory slicing, and enemy AI.
-- ==============================================================================

local Crystals = require("crystals")
local Audio = require("audio")
local Logger = require("logger")

local StatePlaying = {}
StatePlaying.__index = StatePlaying

function StatePlaying.new(game)
    local self = setmetatable({}, StatePlaying)
    self.game = game
    return self
end

function StatePlaying:enter()
end

function StatePlaying:update(dt)
    local game = self.game
    game.timeInLevel = game.timeInLevel + dt

    if game.freezeTimer > 0 then
        game.freezeTimer = game.freezeTimer - dt
    end
    Crystals.updateList(game.crystals, dt)

    -- Mutate Sparx to Super Sparx when level timer runs out (Level 2+)
    if game.superSparxEnabled and game.timeInLevel >= game.sparxTimer then
        local justMutated = false
        for _, spx in ipairs(game.sparxList) do
            if not spx.isSuper then
                spx:mutateToSuper()
                justMutated = true
            end
        end
        if justMutated and not game.superSparxAlerted then
            game.superSparxAlerted = true
            Audio.play("death")
            game.bannerText = "⚡ WARNING: SUPER SPARX UNLEASHED! ⚡"
            game.bannerTimer = 2.5
        end
    end

    -- Update Player Marker
    game.player:update(dt, game.input, game.qixList,
        function(res) game:onAreaCaptured(res) end,
        function(reason) game:onPlayerDeath(reason) end,
        game.offsetX, game.offsetY, game.scaleX, game.scaleY
    )

    -- Update Qix and Sparx (frozen while Chrono Freeze is active)
    if game.freezeTimer <= 0 and game.state == "PLAYING" then
        for _, qix in ipairs(game.qixList) do
            qix:update(dt)
            local hit, hx, hy = qix:checkStixCollision(game.player.stixPath)
            if game.player:isDrawing() and hit then
                game:onPlayerDeath("qix", hx, hy)
                break
            end
        end

        if game.state == "PLAYING" then
            for _, spx in ipairs(game.sparxList) do
                spx:update(dt, game.player)
                if spx:checkPlayerCollision(game.player) then
                    game:onPlayerDeath("sparx", spx.x, spx.y)
                    break
                end
            end
        end
    end
end

function StatePlaying:draw()
    local game = self.game

    -- Top Arcade HUD Bar
    game:drawHUD()

    -- Playfield Grid (reveals background photo)
    if game.grid then
        pcall(game.grid.draw, game.grid, game.offsetX, game.offsetY, game.scaleX, game.scaleY)
    end

    -- Neon Viewport Shimmer Border
    local boardW = game.grid.width * game.scaleX
    local boardH = game.grid.height * game.scaleY
    game.BorderFX.draw(game.offsetX, game.offsetY, boardW, boardH)

    -- Power Crystals (Level 4+)
    if #game.crystals > 0 then
        Crystals.drawList(game.crystals, game.offsetX, game.offsetY, game.scaleX, game.scaleY)
    end

    -- Chrono Freeze Visual Overlay
    if game.freezeTimer > 0 then
        local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 8)
        love.graphics.setColor(0.1, 0.85, 1.0, 0.10 + 0.08 * pulse)
        love.graphics.rectangle("fill", game.offsetX, game.offsetY, game.grid.width * game.scaleX, game.grid.height * game.scaleY)
        love.graphics.setColor(0.2, 0.95, 1.0, 0.9)
        love.graphics.setFont(game.fontSmall)
        love.graphics.print(string.format("❄ FREEZE TIME: %0.1fs", game.freezeTimer), game.offsetX + 8, game.offsetY + 8)
    end

    -- Qix Entities
    for _, qix in ipairs(game.qixList) do
        qix:draw(game.offsetX, game.offsetY, game.scaleX, game.scaleY)
    end

    -- Sparx Enemies
    for _, spx in ipairs(game.sparxList) do
        spx:draw(game.offsetX, game.offsetY, game.scaleX, game.scaleY)
    end

    -- Player Marker
    game.player:draw(game.offsetX, game.offsetY, game.scaleX, game.scaleY)

    -- Visual FX Particles
    pcall(game.Particles.draw)

    -- Ambient Flyby Spaceships
    pcall(game.AmbientShips.draw)

    -- Floating Score Popups
    if #game.floatingScores > 0 then
        love.graphics.setFont(game.fontSmall)
        for _, fs in ipairs(game.floatingScores) do
            local alpha = math.max(0, fs.life / fs.maxLife)
            love.graphics.setColor(fs.color[1], fs.color[2], fs.color[3], alpha)
            love.graphics.print(fs.text, fs.x - 16, fs.y)
        end
    end

    -- Active Banner Alert
    if game.bannerTimer > 0 and game.bannerText then
        local alpha = math.min(1, game.bannerTimer * 2.5)
        local pulse = 0.85 + 0.15 * math.sin(love.timer.getTime() * 10)
        local bx, by, bw, bh = 24, 34, 592, 42
        love.graphics.setColor(0.03, 0.05, 0.09, 0.94 * alpha)
        love.graphics.rectangle("fill", bx, by, bw, bh, 6, 6)
        love.graphics.setLineWidth(2)
        love.graphics.setColor(0.0, 0.95, 1.0, alpha * pulse)
        love.graphics.rectangle("line", bx, by, bw, bh, 6, 6)
        love.graphics.setFont(game.fontMid)
        love.graphics.setColor(0, 0, 0, 0.85 * alpha)
        love.graphics.printf(game.bannerText, bx + 2, by + 12, bw, "center")
        love.graphics.setColor(1.0, 0.88, 0.15, alpha)
        love.graphics.printf(game.bannerText, bx, by + 10, bw, "center")
    end
end

function StatePlaying:keypressed(key)
    if key == "escape" or key == "p" then
        self.game:setState("PAUSED", "keyboard_pause")
        return true
    elseif key == "m" then
        Audio.toggleMute()
        return true
    end
    return false
end

function StatePlaying:gamepadpressed(joy, btn)
    if btn == "start" then
        self.game:setState("PAUSED", "gamepad_start_pause")
        return true
    elseif btn == "back" then
        Audio.toggleMute()
        return true
    end
    return false
end

function StatePlaying:leave()
end

return StatePlaying
