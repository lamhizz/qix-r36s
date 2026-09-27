-- ==============================================================================
-- QIX (1981 Arcade) - Native Love2D Engine for R36S (RK3326 Handheld)
-- Authentic Arcade Aesthetics, Background Art Unveil, Floating Scores & CRT Filter
-- ==============================================================================

local Grid = require("grid")
local Player = require("player")
local Qix = require("qix")
local Sparx = require("sparx")
local Audio = require("audio")

local game = {
    state = "TITLE", -- "TITLE", "PLAYING", "PAUSED", "LEVEL_CLEAR", "GAME_OVER"
    score = 0,
    highScore = 10000,
    lives = 3,
    level = 1,
    targetPercent = 75,
    sparxTimer = 35, -- Seconds before Sparx turn into Super Sparx
    timeInLevel = 0,

    grid = nil,
    player = nil,
    qixList = {},
    sparxList = {},

    -- Display & Layout
    width = 640,
    height = 480,
    hudHeight = 28,
    scaleX = 2.0,
    scaleY = 2.0,
    offsetX = 0,
    offsetY = 28,

    -- Options
    crtFilter = true,
    fontSmall = nil,
    font = nil,
    fontMid = nil,
    fontBig = nil,

    -- Visual Effects
    floatingScores = {},
    bannerText = nil,
    bannerTimer = 0,
    nearTargetAlerted = false,
    shakeDuration = 0,
    shakeIntensity = 0,

    -- Pause Menu
    pauseIndex = 1,
    pauseItems = { "RESUME", "CRT SCANLINES", "AUDIO", "RESTART", "QUIT" },

    -- Input state
    input = {
        dx = 0,
        dy = 0,
        fastDraw = false,
        slowDraw = false
    },

    titleBlink = 0,
    deathTimer = 0,
    clearTimer = 0
}

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    Audio.init()

    -- Load Authentic Retro Arcade Font
    local fontPath = "fonts/pressstart2p.ttf"
    if love.filesystem.getInfo(fontPath) then
        local success, fSmall = pcall(love.graphics.newFont, fontPath, 8)
        local success2, fNormal = pcall(love.graphics.newFont, fontPath, 10)
        local success3, fMid = pcall(love.graphics.newFont, fontPath, 14)
        local success4, fBig = pcall(love.graphics.newFont, fontPath, 26)
        if success and success2 and success3 and success4 then
            game.fontSmall = fSmall
            game.font = fNormal
            game.fontMid = fMid
            game.fontBig = fBig
        end
    end

    if not game.font then
        game.fontSmall = love.graphics.newFont(10)
        game.font = love.graphics.newFont(12)
        game.fontMid = love.graphics.newFont(16)
        game.fontBig = love.graphics.newFont(26)
    end
    love.graphics.setFont(game.font)

    game.grid = Grid.new(320, 226)
    game.player = Player.new(game.grid)

    -- Scan art directory for dynamic image deck
    game:scanArtDeck()

    -- Load high score if available
    local info = love.filesystem.getInfo("highscore.txt")
    if info then
        local data = love.filesystem.read("highscore.txt")
        if data and tonumber(data) then
            game.highScore = tonumber(data)
        end
    end
end

function game:scanArtDeck()
    self.artDeck = {}
    if love.filesystem.getInfo("art") then
        local files = love.filesystem.getDirectoryItems("art")
        table.sort(files)
        for _, file in ipairs(files) do
            local lower = file:lower()
            if lower:match("%.jpg$") or lower:match("%.jpeg$") or lower:match("%.png$") then
                table.insert(self.artDeck, "art/" .. file)
            end
        end
    end
    if #self.artDeck == 0 and love.filesystem.getInfo("cover.png") then
        table.insert(self.artDeck, "cover.png")
    end
end

function game:saveHighScore()
    if self.score > self.highScore then
        self.highScore = self.score
        love.filesystem.write("highscore.txt", tostring(self.highScore))
    end
end

function game:startNewGame()
    self.score = 0
    self.lives = 3
    self.level = 1
    self:startLevel(1)
end

function game:startLevel(levelNum)
    self.level = levelNum
    self.timeInLevel = 0
    self.sparxTimer = math.max(18, 38 - (levelNum * 3))
    self.floatingScores = {}
    self.bannerText = nil
    self.bannerTimer = 0
    self.nearTargetAlerted = false
    self.shakeDuration = 0

    self.grid:init()
    self.player:reset()

    -- Load background art for level uncover (rotates through art deck)
    if #self.artDeck > 0 then
        local artIndex = ((levelNum - 1) % #self.artDeck) + 1
        local chosenArt = self.artDeck[artIndex]
        self.grid:loadBackground(chosenArt)
    else
        self.grid:loadBackground(nil)
    end

    -- Spawn Qix: Level 1-2 has 1 Qix; Level 3+ has 2 independent Qixes!
    self.qixList = {}
    local qixSpeed = 1.0 + (levelNum - 1) * 0.15
    local q1 = Qix.new(self.grid, self.grid.width * 0.5, self.grid.height * 0.5, qixSpeed)
    table.insert(self.qixList, q1)

    if levelNum >= 3 then
        local q2 = Qix.new(self.grid, self.grid.width * 0.4, self.grid.height * 0.4, qixSpeed * 1.1)
        table.insert(self.qixList, q2)
    end

    -- Spawn 2 initial Sparx on opposite sides
    self.sparxList = {
        Sparx.new(self.grid, 0, 0, true, false),
        Sparx.new(self.grid, self.grid.width - 1, 0, false, false)
    }

    self.state = "PLAYING"
end

function game:onAreaCaptured(captureResult)
    Audio.stopDraw()
    Audio.stopFuse()
    Audio.play("capture")

    -- Scoring: Slow draw gives 100 pts per 1%, Fast draw gives 50 pts per 1%
    local rate = captureResult.isSlow and 100 or 50
    local cutPts = math.floor(captureResult.cutPercent * rate * 10)
    if cutPts < 10 then cutPts = 10 end
    self.score = self.score + cutPts
    self:saveHighScore()

    -- Spawn floating score popup at captured centroid
    local popupX = self.offsetX + captureResult.cx * self.scaleX
    local popupY = self.offsetY + captureResult.cy * self.scaleY
    local popupColor = captureResult.isSlow and {1, 0.45, 0.1} or {0, 0.95, 1}
    table.insert(self.floatingScores, {
        text = string.format("+%d", cutPts),
        x = popupX,
        y = popupY,
        life = 1.3,
        maxLife = 1.3,
        color = popupColor
    })

    -- Massive cut celebration banner
    if captureResult.cutPercent >= 10 then
        self.bannerText = string.format("⚡ MASSIVE CUT! +%d PTS ⚡", cutPts)
        self.bannerTimer = 2.0
    end

    -- Near target alert
    if captureResult.percent >= (self.targetPercent - 8) and not self.nearTargetAlerted then
        self.bannerText = "⚡ TARGET NEAR! CLOSE THE LOOP! ⚡"
        self.bannerTimer = 2.2
        self.nearTargetAlerted = true
    end

    -- Check level clear threshold (75%)
    if captureResult.percent >= self.targetPercent then
        self.state = "LEVEL_CLEAR"
        self.clearTimer = 3.5
        Audio.play("bonus")

        -- Extra bonus for exceeding target threshold
        local excess = captureResult.percent - self.targetPercent
        if excess > 0 then
            local bonus = math.floor(excess * 1000)
            self.score = self.score + bonus
            self:saveHighScore()
        end
    end
end

function game:onPlayerDeath(reason)
    Audio.stopAll()
    Audio.play("death")
    self.state = "DEAD"
    self.player.state = Player.STATE_DEAD
    self.lives = self.lives - 1
    self.deathTimer = 1.0

    -- Screen shake impact
    self.shakeDuration = 0.35
    self.shakeIntensity = 6
end

function love.update(dt)
    -- Poll gamepad / keyboard input
    game:updateInput()

    -- Screen shake decay
    if game.shakeDuration > 0 then
        game.shakeDuration = game.shakeDuration - dt
    end

    -- Banner timer decay
    if game.bannerTimer > 0 then
        game.bannerTimer = game.bannerTimer - dt
    end

    -- Update floating score popups
    for i = #game.floatingScores, 1, -1 do
        local fs = game.floatingScores[i]
        fs.life = fs.life - dt
        fs.y = fs.y - (30 * dt)
        if fs.life <= 0 then
            table.remove(game.floatingScores, i)
        end
    end

    if game.state == "TITLE" then
        game.titleBlink = game.titleBlink + dt * 3
        if love.keyboard.isDown("return", "space") or game.input.fastDraw or game.input.slowDraw then
            game:startNewGame()
        end

    elseif game.state == "PLAYING" then
        game.timeInLevel = game.timeInLevel + dt

        -- Mutate Sparx to Super Sparx when level timer runs out
        if game.timeInLevel >= game.sparxTimer then
            for _, spx in ipairs(game.sparxList) do
                if not spx.isSuper then
                    spx:mutateToSuper()
                end
            end
        end

        -- Update Player
        game.player:update(dt, game.input, game.qixList,
            function(res) game:onAreaCaptured(res) end,
            function(reason) game:onPlayerDeath(reason) end
        )

        -- Update Qix entities
        for _, qix in ipairs(game.qixList) do
            qix:update(dt)
            -- Check collision with player's active stix line
            if game.player:isDrawing() and qix:checkStixCollision(game.player.stixPath) then
                game:onPlayerDeath("qix")
                break
            end
        end

        -- Update Sparx enemies
        for _, spx in ipairs(game.sparxList) do
            spx:update(dt, game.player)
            if spx:checkPlayerCollision(game.player) then
                game:onPlayerDeath("sparx")
                break
            end
        end

    elseif game.state == "DEAD" then
        game.deathTimer = game.deathTimer - dt
        if game.deathTimer <= 0 then
            if game.lives > 0 then
                game.player:respawn()
                -- Reset Sparx to opposite top corners so player has safe breathing room
                game.sparxList = {
                    Sparx.new(game.grid, 0, 0, true, false),
                    Sparx.new(game.grid, game.grid.width - 1, 0, false, false)
                }
                game.bannerText = "⚡ SAFE SHIELD ACTIVE ⚡"
                game.bannerTimer = 1.8
                game.state = "PLAYING"
            else
                game:saveHighScore()
                game.state = "GAME_OVER"
            end
        end

    elseif game.state == "LEVEL_CLEAR" then
        game.clearTimer = game.clearTimer - dt
        if game.clearTimer <= 0 or love.keyboard.isDown("return", "space") or game.input.fastDraw then
            game:startLevel(game.level + 1)
        end

    elseif game.state == "GAME_OVER" then
        if love.keyboard.isDown("return", "space") or game.input.fastDraw or game.input.slowDraw then
            game.state = "TITLE"
        end
    end
end

function game:updateInput()
    local dx, dy = 0, 0
    local fastDraw = false
    local slowDraw = false

    -- Keyboard support (Arrow keys or WASD)
    if love.keyboard.isDown("left", "a") then dx = -1
    elseif love.keyboard.isDown("right", "d") then dx = 1 end

    if love.keyboard.isDown("up", "w") then dy = -1
    elseif love.keyboard.isDown("down", "s") then dy = 1 end

    -- Space / Z = Fast Draw, X / Shift / C = Slow Draw (Double Points)
    if love.keyboard.isDown("space", "z", "j") then fastDraw = true end
    if love.keyboard.isDown("x", "k", "lshift", "rshift", "c") then slowDraw = true end

    -- Gamepad support (first connected joystick)
    local joysticks = love.joystick.getJoysticks()
    if #joysticks > 0 then
        local joy = joysticks[1]

        -- D-Pad
        if joy:isGamepadDown("dpleft") then dx = -1
        elseif joy:isGamepadDown("dpright") then dx = 1 end

        if joy:isGamepadDown("dpup") then dy = -1
        elseif joy:isGamepadDown("dpdown") then dy = 1 end

        -- Left Analog Stick (with deadzone 0.25)
        local axisX = joy:getGamepadAxis("leftx")
        local axisY = joy:getGamepadAxis("lefty")
        if math.abs(axisX) > 0.25 then dx = (axisX > 0) and 1 or -1 end
        if math.abs(axisY) > 0.25 then dy = (axisY > 0) and 1 or -1 end

        -- Action Buttons
        if joy:isGamepadDown("a") then fastDraw = true end
        if joy:isGamepadDown("b") then slowDraw = true end
    end

    self.input.dx = dx
    self.input.dy = dy
    self.input.fastDraw = fastDraw
    self.input.slowDraw = slowDraw
end

function love.gamepadpressed(joystick, button)
    if game.state == "PLAYING" then
        if button == "start" then
            game.state = "PAUSED"
            game.pauseIndex = 1
            Audio.stopAll()
        elseif button == "back" then
            Audio.toggleMute()
        end
    elseif game.state == "PAUSED" then
        if button == "dpup" then
            game.pauseIndex = (game.pauseIndex > 1) and (game.pauseIndex - 1) or #game.pauseItems
            Audio.play("tick")
        elseif button == "dpdown" then
            game.pauseIndex = (game.pauseIndex < #game.pauseItems) and (game.pauseIndex + 1) or 1
            Audio.play("tick")
        elseif button == "a" or button == "start" then
            game:executePauseOption()
        elseif button == "b" then
            game.state = "PLAYING"
        end
    elseif game.state == "TITLE" or game.state == "GAME_OVER" then
        if button == "start" or button == "a" or button == "b" then
            if game.state == "TITLE" then game:startNewGame() else game.state = "TITLE" end
        end
    elseif game.state == "LEVEL_CLEAR" then
        if button == "start" or button == "a" or button == "b" then
            game:startLevel(game.level + 1)
        end
    end
end

function love.keypressed(key)
    if key == "escape" or key == "p" then
        if game.state == "PLAYING" then
            game.state = "PAUSED"
            game.pauseIndex = 1
            Audio.stopAll()
        elseif game.state == "PAUSED" then
            game.state = "PLAYING"
        end
    elseif game.state == "PAUSED" then
        if key == "up" then
            game.pauseIndex = (game.pauseIndex > 1) and (game.pauseIndex - 1) or #game.pauseItems
            Audio.play("tick")
        elseif key == "down" then
            game.pauseIndex = (game.pauseIndex < #game.pauseItems) and (game.pauseIndex + 1) or 1
            Audio.play("tick")
        elseif key == "return" or key == "space" then
            game:executePauseOption()
        end
    elseif key == "m" then
        Audio.toggleMute()
    end
end

function game:executePauseOption()
    local opt = self.pauseItems[self.pauseIndex]
    if opt == "RESUME" then
        self.state = "PLAYING"
    elseif opt == "CRT SCANLINES" then
        self.crtFilter = not self.crtFilter
        Audio.play("tick")
    elseif opt == "AUDIO" then
        Audio.toggleMute()
    elseif opt == "RESTART" then
        self:startNewGame()
    elseif opt == "QUIT" then
        love.event.quit()
    end
end

-- ==============================================================================
-- RENDERING
-- ==============================================================================
function love.draw()
    love.graphics.clear(0, 0, 0, 1)

    love.graphics.push()

    -- Screen Shake Transform
    if game.shakeDuration > 0 then
        local ox = (love.math.random() - 0.5) * game.shakeIntensity
        local oy = (love.math.random() - 0.5) * game.shakeIntensity
        love.graphics.translate(ox, oy)
    end

    if game.state == "TITLE" then
        game:drawTitle()
    elseif game.state == "LEVEL_CLEAR" then
        -- During Level Clear: Unveil 100% full artwork unobstructed!
        game:drawLevelClear()
    else
        -- Draw Top Arcade HUD Bar
        game:drawHUD()

        -- Draw Playfield Grid (uncovering background image)
        game.grid:draw(game.offsetX, game.offsetY, game.scaleX, game.scaleY)

        -- Draw Qix Entities
        for _, qix in ipairs(game.qixList) do
            qix:draw(game.offsetX, game.offsetY, game.scaleX, game.scaleY)
        end

        -- Draw Sparx Enemies
        for _, spx in ipairs(game.sparxList) do
            spx:draw(game.offsetX, game.offsetY, game.scaleX, game.scaleY)
        end

        -- Draw Player Marker
        game.player:draw(game.offsetX, game.offsetY, game.scaleX, game.scaleY)

        -- Draw Floating Score Popups
        for _, fs in ipairs(game.floatingScores) do
            local alpha = math.max(0, fs.life / fs.maxLife)
            love.graphics.setFont(game.fontSmall)
            love.graphics.setColor(fs.color[1], fs.color[2], fs.color[3], alpha)
            love.graphics.print(fs.text, fs.x - 16, fs.y)
        end

        -- Draw Active Banner Alert (e.g. MASSIVE CUT or TARGET NEAR)
        if game.bannerTimer > 0 and game.bannerText then
            local alpha = math.min(1, game.bannerTimer * 2)
            love.graphics.setColor(0, 0, 0, 0.85 * alpha)
            love.graphics.rectangle("fill", 80, 36, 480, 24, 4, 4)
            love.graphics.setColor(0, 0.95, 1, alpha)
            love.graphics.rectangle("line", 80, 36, 480, 24, 4, 4)
            love.graphics.setColor(1, 0.9, 0.1, alpha)
            love.graphics.setFont(game.fontSmall)
            love.graphics.printf(game.bannerText, 80, 42, 480, "center")
        end

        -- Overlay States
        if game.state == "PAUSED" then
            game:drawPauseMenu()
        elseif game.state == "GAME_OVER" then
            game:drawGameOver()
        end
    end

    love.graphics.pop()

    -- Authentic Arcade CRT Scanline Overlay
    if game.crtFilter then
        love.graphics.setColor(0, 0, 0, 0.20)
        love.graphics.setLineWidth(1)
        for y = 0, 480, 3 do
            love.graphics.line(0, y, 640, y)
        end
    end
end

function game:drawHUD()
    -- Top HUD bar (y = 0 to 28)
    love.graphics.setColor(0.04, 0.05, 0.08, 1)
    love.graphics.rectangle("fill", 0, 0, 640, game.hudHeight)

    love.graphics.setColor(0.0, 0.85, 1.0, 0.8)
    love.graphics.setLineWidth(1)
    love.graphics.line(0, game.hudHeight, 640, game.hudHeight)

    love.graphics.setFont(game.fontSmall)

    -- Left: Claimed Percentage and Progress Bar
    local pct = self.grid:getClaimedPercent()
    love.graphics.setColor(0.0, 0.95, 1.0, 1)
    love.graphics.print(string.format("CLAIM:%4.1f%%", pct), 10, 8)

    -- Mini Claim Gauge
    local gaugeX = 110
    local gaugeY = 8
    local gaugeW = 55
    local gaugeH = 10
    love.graphics.setColor(0.15, 0.18, 0.25, 1)
    love.graphics.rectangle("fill", gaugeX, gaugeY, gaugeW, gaugeH)
    local fillW = math.min(gaugeW, math.floor((pct / self.targetPercent) * gaugeW))
    if pct >= self.targetPercent then
        love.graphics.setColor(0.2, 1.0, 0.3, 1)
    else
        love.graphics.setColor(0.0, 0.8, 1.0, 1)
    end
    if fillW > 0 then
        love.graphics.rectangle("fill", gaugeX, gaugeY, fillW, gaugeH)
    end
    love.graphics.setColor(0.4, 0.5, 0.6, 1)
    love.graphics.rectangle("line", gaugeX, gaugeY, gaugeW, gaugeH)

    -- Target: 75%
    love.graphics.setColor(1, 0.85, 0.2, 1)
    love.graphics.print(string.format("GOAL:%d%%", self.targetPercent), 175, 8)

    -- Center: Score & High Score
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(string.format("1UP %06d", self.score), 255, 8)

    love.graphics.setColor(1, 0.85, 0.2, 1)
    love.graphics.print(string.format("HI %06d", self.highScore), 375, 8)

    -- Sparx Countdown Meter
    local sparxLeft = math.max(0, self.sparxTimer - self.timeInLevel)
    local sparxRatio = sparxLeft / self.sparxTimer
    love.graphics.setColor(0.9, 0.4, 1.0, 1)
    love.graphics.print("SPX", 480, 8)

    local spxBarX = 512
    local spxBarW = 38
    love.graphics.setColor(0.15, 0.18, 0.25, 1)
    love.graphics.rectangle("fill", spxBarX, gaugeY, spxBarW, gaugeH)
    local spxFill = math.floor(sparxRatio * spxBarW)
    if sparxRatio > 0.4 then
        love.graphics.setColor(0.0, 0.9, 1.0, 1)
    elseif sparxRatio > 0.15 then
        love.graphics.setColor(1.0, 0.7, 0.1, 1)
    else
        -- Flashing red when Super Sparx mutation is imminent
        love.graphics.setColor(1.0, 0.15, 0.15, 1)
    end
    if spxFill > 0 then
        love.graphics.rectangle("fill", spxBarX, gaugeY, spxFill, gaugeH)
    end
    love.graphics.setColor(0.4, 0.5, 0.6, 1)
    love.graphics.rectangle("line", spxBarX, gaugeY, spxBarW, gaugeH)

    -- Lives (Diamond markers)
    love.graphics.setColor(1, 1, 1, 1)
    for i = 1, self.lives do
        local lx = 565 + (i * 14)
        local ly = 13
        local d = { lx, ly - 5, lx + 5, ly, lx, ly + 5, lx - 5, ly }
        love.graphics.polygon("fill", d)
    end

    -- Level Indicator
    love.graphics.setColor(0.2, 1.0, 0.4, 1)
    love.graphics.print("L" .. self.level, 615, 8)
end

function game:drawTitle()
    -- Title screen cyber background grid accent
    love.graphics.setColor(0.06, 0.08, 0.18, 0.7)
    for x = 0, 640, 32 do love.graphics.line(x, 0, x, 480) end
    for y = 0, 480, 32 do love.graphics.line(0, y, 640, y) end

    -- QIX Retro Neon Glow Title
    love.graphics.setFont(game.fontBig)
    love.graphics.setColor(0.0, 0.9, 1.0, 0.4)
    love.graphics.printf("Q  I  X", 0, 68, 640, "center")
    love.graphics.setColor(1.0, 0.2, 0.8, 1.0)
    love.graphics.printf("Q  I  X", 0, 66, 640, "center")

    love.graphics.setFont(game.fontSmall)
    love.graphics.setColor(0.0, 0.95, 1.0, 1.0)
    love.graphics.printf("1981 TAITO ARCADE CLASSIC &bull; PORTMASTER R36S", 0, 115, 640, "center")

    -- Rules Card
    love.graphics.setColor(0.05, 0.07, 0.12, 0.88)
    love.graphics.rectangle("fill", 70, 145, 500, 175, 8, 8)
    love.graphics.setColor(0.0, 0.85, 1.0, 0.8)
    love.graphics.rectangle("line", 70, 145, 500, 175, 8, 8)

    love.graphics.setFont(game.font)
    love.graphics.setColor(1, 0.85, 0.2, 1)
    love.graphics.printf("MISSION DIRECTIVES", 70, 160, 500, "center")

    love.graphics.setFont(game.fontSmall)
    love.graphics.setColor(0.9, 0.9, 0.95, 1)
    love.graphics.printf("CLAIM 75% OF THE PLAYFIELD TO UNVEIL THE ARTWORK", 80, 190, 480, "center")
    love.graphics.setColor(1.0, 0.4, 0.1, 1)
    love.graphics.printf("(B) / [X]: SLOW DRAW &bull; 2X POINTS &bull; HIGHER RISK", 80, 218, 480, "center")
    love.graphics.setColor(0.0, 0.9, 1.0, 1)
    love.graphics.printf("(A) / [SPACE]: FAST DRAW &bull; 1X POINTS &bull; QUICK ESCAPE", 80, 242, 480, "center")
    love.graphics.setColor(0.8, 0.8, 0.8, 1)
    love.graphics.printf("DON'T HESITATE: IDLE FUSE IGNITES IF YOU STOP!", 80, 270, 480, "center")
    love.graphics.printf("AVOID THE SPARX PATROLLING THE PERIMETER!", 80, 292, 480, "center")

    -- High score display
    love.graphics.setColor(1, 0.85, 0.2, 1)
    love.graphics.setFont(game.font)
    love.graphics.printf(string.format("ALL TIME HIGH SCORE: %06d", self.highScore), 0, 345, 640, "center")

    -- Blinking start prompt
    if math.floor(self.titleBlink) % 2 == 0 then
        love.graphics.setColor(0.2, 1.0, 0.4, 1)
        love.graphics.setFont(game.fontMid)
        love.graphics.printf("PRESS (A) OR START TO PLAY", 0, 390, 640, "center")
    end

    love.graphics.setFont(game.fontSmall)
    love.graphics.setColor(0.4, 0.45, 0.55, 1)
    love.graphics.printf("KEYBOARD: ARROWS / WASD + SPACE/X | CONTROLLER: D-PAD + A/B", 0, 450, 640, "center")
end

function game:drawPauseMenu()
    -- Dark translucent overlay
    love.graphics.setColor(0, 0, 0, 0.85)
    love.graphics.rectangle("fill", 130, 85, 380, 310, 8, 8)

    love.graphics.setColor(0.0, 0.85, 1.0, 1)
    love.graphics.rectangle("line", 130, 85, 380, 310, 8, 8)

    love.graphics.setColor(1, 0.85, 0.2, 1)
    love.graphics.setFont(game.fontMid)
    love.graphics.printf("SYSTEM PAUSE", 130, 105, 380, "center")

    love.graphics.setFont(game.font)
    for i, item in ipairs(self.pauseItems) do
        local label = item
        if item == "CRT SCANLINES" then
            label = "CRT FILTER: " .. (self.crtFilter and "ON" or "OFF")
        elseif item == "AUDIO" then
            label = "AUDIO: " .. (Audio.muted and "MUTED" or "ON")
        end

        local y = 160 + (i - 1) * 38
        if i == self.pauseIndex then
            love.graphics.setColor(0.0, 0.8, 1.0, 0.3)
            love.graphics.rectangle("fill", 150, y - 6, 340, 28, 4, 4)
            love.graphics.setColor(1, 1, 0.2, 1)
            love.graphics.printf("> " .. label .. " <", 130, y, 380, "center")
        else
            love.graphics.setColor(0.7, 0.7, 0.8, 1)
            love.graphics.printf(label, 130, y, 380, "center")
        end
    end

    love.graphics.setFont(game.fontSmall)
    love.graphics.setColor(0.4, 0.45, 0.55, 1)
    love.graphics.printf("▲/▼ D-PAD: SELECT &bull; (A): CHOOSE &bull; START: RESUME", 130, 365, 380, "center")
end

function game:drawLevelClear()
    -- 1. Full 100% Unobstructed Artwork Reveal
    if self.grid.bgImage then
        love.graphics.setColor(1, 1, 1, 1)
        local imgW = self.grid.bgImage:getWidth()
        local imgH = self.grid.bgImage:getHeight()
        local scale = math.max(640 / imgW, 480 / imgH)
        local drawW = imgW * scale
        local drawH = imgH * scale
        local drawX = (640 - drawW) * 0.5
        local drawY = (480 - drawH) * 0.5
        love.graphics.draw(self.grid.bgImage, drawX, drawY, 0, scale, scale)
    end

    -- 2. Sleek Glass Showcase Banner at Bottom
    love.graphics.setColor(0.03, 0.04, 0.08, 0.85)
    love.graphics.rectangle("fill", 40, 370, 560, 90, 8, 8)

    love.graphics.setColor(1.0, 0.85, 0.1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", 40, 370, 560, 90, 8, 8)

    love.graphics.setFont(game.fontMid)
    love.graphics.setColor(0.2, 1.0, 0.4, 1)
    love.graphics.printf(string.format("★ LEVEL %d COMPLETE! ★", self.level), 40, 382, 560, "center")

    love.graphics.setFont(game.font)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(string.format("TERRITORY UNVEILED: %4.1f%% (GOAL: %d%%)", self.grid:getClaimedPercent(), self.targetPercent), 40, 410, 560, "center")

    love.graphics.setFont(game.fontSmall)
    love.graphics.setColor(1, 0.85, 0.2, 1)
    love.graphics.printf("PRESS (A) OR START FOR NEXT LEVEL", 40, 435, 560, "center")
end

function game:drawGameOver()
    love.graphics.setColor(0, 0, 0, 0.85)
    love.graphics.rectangle("fill", 130, 150, 380, 180, 8, 8)

    love.graphics.setColor(1, 0.2, 0.2, 1)
    love.graphics.rectangle("line", 130, 150, 380, 180, 8, 8)

    love.graphics.setFont(game.fontMid)
    love.graphics.setColor(1, 0.2, 0.2, 1)
    love.graphics.printf("GAME OVER", 130, 175, 380, "center")

    love.graphics.setFont(game.font)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(string.format("FINAL SCORE: %06d", self.score), 130, 215, 380, "center")

    love.graphics.setFont(game.fontSmall)
    love.graphics.setColor(1, 0.85, 0.2, 1)
    love.graphics.printf("PRESS (A) OR START TO RETRY", 130, 270, 380, "center")
end
