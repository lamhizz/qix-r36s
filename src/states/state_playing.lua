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

function StatePlaying:enter(trigger)
    Logger.setLastAction("STATE", "StatePlaying: enter (trigger=%s)", tostring(trigger))
end

function StatePlaying:update(dt)
    local game = self.game
    Logger.setLastAction("UPDATE", "StatePlaying: start (t=%.2f)", game.timeInLevel)
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
            game.bannerText = ">> WARNING: SUPER SPARX UNLEASHED! <<"
            game.bannerTimer = 2.5
        end
    end

    -- Update Player Marker
    Logger.setLastAction("UPDATE", "StatePlaying: player:update (x=%d, y=%d, state=%s)", game.player.x, game.player.y, tostring(game.player.state))
    game.player:update(dt, game.input, game.qixList,
        function(res) game:onAreaCaptured(res) end,
        function(reason) game:onPlayerDeath(reason) end,
        game.offsetX, game.offsetY, game.scaleX, game.scaleY
    )

    -- Update Qix and Sparx (frozen while Chrono Freeze is active)
    if game.freezeTimer <= 0 and game.state == "PLAYING" then
        Logger.setLastAction("UPDATE", "StatePlaying: qixList update (%d)", #game.qixList)
        for _, qix in ipairs(game.qixList) do
            qix:update(dt)
            local hit, hx, hy = qix:checkStixCollision(game.player.stixPath)
            if game.player:isDrawing() and hit then
                game:onPlayerDeath("qix", hx, hy)
                break
            end
        end

        if game.state == "PLAYING" then
            Logger.setLastAction("UPDATE", "StatePlaying: sparxList update (%d)", #game.sparxList)
            for _, spx in ipairs(game.sparxList) do
                spx:update(dt, game.player)
                if spx:checkPlayerCollision(game.player) then
                    game:onPlayerDeath("sparx", spx.x, spx.y)
                    break
                end
            end
        end
    end
    Logger.setLastAction("UPDATE", "StatePlaying: update done")
end

function StatePlaying:draw()
    local game = self.game

    -- Top Arcade HUD Bar
    Logger.setLastAction("DRAW", "StatePlaying: drawHUD")
    pcall(game.drawHUD, game)

    -- Playfield Grid (reveals background photo)
    if game.grid then
        Logger.setLastAction("DRAW", "StatePlaying: grid.draw")
        pcall(game.grid.draw, game.grid, game.offsetX, game.offsetY, game.scaleX, game.scaleY)
    end

    -- Neon Viewport Shimmer Border
    local boardW = game.grid.width * game.scaleX
    local boardH = game.grid.height * game.scaleY
    Logger.setLastAction("DRAW", "StatePlaying: BorderFX.draw")
    pcall(game.BorderFX.draw, game.offsetX, game.offsetY, boardW, boardH)

    -- Power Crystals (Level 4+)
    if #game.crystals > 0 then
        Logger.setLastAction("DRAW", "StatePlaying: Crystals.drawList (%d)", #game.crystals)
        pcall(Crystals.drawList, game.crystals, game.offsetX, game.offsetY, game.scaleX, game.scaleY)
    end

    -- Chrono Freeze Visual Overlay
    if game.freezeTimer > 0 then
        local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 8)
        love.graphics.setColor(0.1, 0.85, 1.0, 0.10 + 0.08 * pulse)
        love.graphics.rectangle("fill", game.offsetX, game.offsetY, game.grid.width * game.scaleX, game.grid.height * game.scaleY)
        love.graphics.setColor(0.2, 0.95, 1.0, 0.9)
        love.graphics.setFont(game.fontSmall)
        love.graphics.print(string.format("[FREEZE] TIME STOP: %0.1fs", game.freezeTimer), game.offsetX + 8, game.offsetY + 8)
    end

    -- Qix Entities
    Logger.setLastAction("DRAW", "StatePlaying: qixList draw (%d)", #game.qixList)
    for _, qix in ipairs(game.qixList) do
        pcall(qix.draw, qix, game.offsetX, game.offsetY, game.scaleX, game.scaleY)
    end

    -- Sparx Enemies
    Logger.setLastAction("DRAW", "StatePlaying: sparxList draw (%d)", #game.sparxList)
    for _, spx in ipairs(game.sparxList) do
        pcall(spx.draw, spx, game.offsetX, game.offsetY, game.scaleX, game.scaleY)
    end

    -- Player Marker
    Logger.setLastAction("DRAW", "StatePlaying: player.draw (x=%d, y=%d, shielded=%s)", game.player.x, game.player.y, tostring(game.player:isShielded()))
    pcall(game.player.draw, game.player, game.offsetX, game.offsetY, game.scaleX, game.scaleY)

    -- Visual FX Particles
    Logger.setLastAction("DRAW", "StatePlaying: Particles.draw")
    pcall(game.Particles.draw)

    -- Ambient Flyby Spaceships
    Logger.setLastAction("DRAW", "StatePlaying: AmbientShips.draw")
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

    -- Active Banner Alert (pcall-guarded, sharp 1px hardware lines, zero polyline tessellation)
    if game.bannerTimer > 0 and game.bannerText then
        pcall(function()
            local alpha = math.min(1, game.bannerTimer * 2.5)
            local pulse = 0.85 + 0.15 * math.sin(love.timer.getTime() * 10)
            local bx, by, bw, bh = 24, 34, 592, 42
            love.graphics.setColor(0.03, 0.05, 0.09, 0.94 * alpha)
            love.graphics.rectangle("fill", bx, by, bw, bh)
            love.graphics.setLineWidth(1)
            love.graphics.setColor(0.0, 0.95, 1.0, alpha * pulse)
            love.graphics.line(bx, by, bx + bw, by)
            love.graphics.line(bx, by + bh, bx + bw, by + bh)
            love.graphics.line(bx, by, bx, by + bh)
            love.graphics.line(bx + bw, by, bx + bw, by + bh)
            love.graphics.setFont(game.fontMid)
            love.graphics.setColor(0, 0, 0, 0.85 * alpha)
            love.graphics.printf(game.bannerText, bx + 2, by + 12, bw, "center")
            love.graphics.setColor(1.0, 0.88, 0.15, alpha)
            love.graphics.printf(game.bannerText, bx, by + 10, bw, "center")
        end)
    end

    love.graphics.setLineWidth(1)
    Logger.setLastAction("DRAW", "StatePlaying: draw done")
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
