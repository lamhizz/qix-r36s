-- ==============================================================================
-- QIX (1981 Arcade) - Native Love2D Engine for R36S (RK3326 Handheld)
-- Authentic Arcade Aesthetics, Background Art Unveil, Floating Scores & CRT Filter
-- ==============================================================================

local Grid = require("grid")
local Player = require("player")
local Qix = require("qix")
local Sparx = require("sparx")
local Audio = require("audio")
local Particles = require("particles")

local COLOR_SLOW = {1, 0.45, 0.1}
local COLOR_FAST = {0, 0.95, 1}
local LIFE_DIAMOND = {0, 0, 0, 0, 0, 0, 0, 0}

game = {
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

    -- Display & Layout (Zoomed-out / smaller scale playfield)
    width = 640,
    height = 480,
    hudHeight = 28,
    scaleX = 1.8,
    scaleY = 1.8,
    offsetX = 0,
    offsetY = 28,

    -- Options
    crtFilter = true,
    fontSmall = nil,
    font = nil,
    fontMid = nil,
    fontBig = nil,
    fontTitle = nil,

    -- Visual Effects
    floatingScores = {},
    bannerText = nil,
    bannerTimer = 0,
    nearTargetAlerted = false,
    shakeDuration = 0,
    shakeIntensity = 0,

    -- Title Menu
    titleIndex = 1,
    titleItems = { "START", "HOW TO", "QUIT" },
    titleAttractQix = nil,
    scoreMultiplier = 1,
    bestCutPercent = 0,
    totalCuts = 0,
    isNewRecord = false,
    sessionInitialHighScore = 0,

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
        local success5, fTitle = pcall(love.graphics.newFont, fontPath, 46)
        if success and success2 and success3 and success4 then
            game.fontSmall = fSmall
            game.font = fNormal
            game.fontMid = fMid
            game.fontBig = fBig
            game.fontTitle = success5 and fTitle or fBig
        end
    end

    if not game.font then
        game.fontSmall = love.graphics.newFont(10)
        game.font = love.graphics.newFont(12)
        game.fontMid = love.graphics.newFont(16)
        game.fontBig = love.graphics.newFont(26)
        game.fontTitle = love.graphics.newFont(40)
    end
    love.graphics.setFont(game.font)

    game.grid = Grid.new(355, 251)
    game.player = Player.new(game.grid)
    game.titleAttractQix = Qix.new(game.grid, 177, 125, 0.75)

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

    -- Pre-render CRT scanline overlay and curved bezel vignette into an off-screen canvas
    game.crtCanvas = love.graphics.newCanvas(640, 480)
    love.graphics.setCanvas(game.crtCanvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(0, 0, 0, 0.20)
    love.graphics.setLineWidth(1)
    for y = 0, 480, 3 do
        love.graphics.line(0, y, 640, y)
    end
    -- Subtle curved CRT corner bezel vignette (darkened border gradient)
    for i = 1, 12 do
        local alpha = 0.022 * (13 - i)
        love.graphics.setColor(0, 0, 0, alpha)
        love.graphics.rectangle("line", i, i, 640 - i * 2, 480 - i * 2, 8, 8)
    end
    love.graphics.setCanvas()

    -- Pre-render title screen cyber grid (replaces 37 line draw calls per frame with 1 draw call)
    game.titleGridCanvas = love.graphics.newCanvas(640, 480)
    love.graphics.setCanvas(game.titleGridCanvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(0.06, 0.08, 0.18, 0.7)
    for x = 0, 640, 32 do love.graphics.line(x, 0, x, 480) end
    for y = 0, 480, 32 do love.graphics.line(0, y, 640, y) end
    love.graphics.setCanvas()
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
    self.sessionInitialHighScore = self.highScore
    self.score = 0
    self.lives = 3
    self.level = 1
    self.scoreMultiplier = 1
    self.bestCutPercent = 0
    self.totalCuts = 0
    self.isNewRecord = false
    self:startLevel(1)
end

function game:startLevel(levelNum)
    self.level = levelNum
    self.timeInLevel = 0
    -- Super Sparx introduced in later levels (Level 2+)
    self.superSparxEnabled = (levelNum >= 2)
    self.sparxTimer = math.max(16, 40 - (levelNum * 4))
    self.superSparxAlerted = false
    self.floatingScores = {}
    self.bannerText = nil
    self.bannerTimer = 0
    self.nearTargetAlerted = false
    self.shakeDuration = 0

    self.grid:init()
    self.player:reset()
    Particles.init()

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
    local mult = self.scoreMultiplier or 1
    local cutPts = math.floor(captureResult.cutPercent * rate * 10 * mult)
    if cutPts < 10 then cutPts = 10 end
    self.score = self.score + cutPts
    self:saveHighScore()

    self.totalCuts = (self.totalCuts or 0) + 1
    if captureResult.cutPercent > (self.bestCutPercent or 0) then
        self.bestCutPercent = captureResult.cutPercent
    end

    -- Spawn floating score popup at captured centroid (reusing static color tables)
    local popupX = self.offsetX + captureResult.cx * self.scaleX
    local popupY = self.offsetY + captureResult.cy * self.scaleY
    local popupColor = captureResult.isSlow and COLOR_SLOW or COLOR_FAST
    local popupText = (mult > 1) and string.format("+%d [%dX]", cutPts, mult) or string.format("+%d", cutPts)
    table.insert(self.floatingScores, {
        text = popupText,
        x = popupX,
        y = popupY,
        life = 1.3,
        maxLife = 1.3,
        color = popupColor
    })

    -- Visual flair: Spark explosion at captured territory centroid
    local burstCount = math.min(36, 16 + math.floor(captureResult.cutPercent * 1.5))
    Particles.spawnCaptureBurst(popupX, popupY, captureResult.isSlow, burstCount)

    -- Tactile micro-shake on significant captures (>= 5%)
    if captureResult.cutPercent >= 5 then
        self.shakeDuration = math.min(0.25, 0.08 + captureResult.cutPercent * 0.01)
        self.shakeIntensity = math.min(5, 2 + captureResult.cutPercent * 0.15)
    end

    -- Check for Classic 1981 Split-Qix Victory (trapping two Qixes into separate compartments)
    if captureResult.isSplitQix then
        self.scoreMultiplier = math.min(9, mult + 1)
        local splitBonus = 25000 * self.scoreMultiplier
        self.score = self.score + splitBonus
        self:saveHighScore()

        self.bannerText = string.format("★ SPLIT-QIX! %dX MULTIPLIER UNLOCKED! ★", self.scoreMultiplier)
        self.bannerTimer = 3.5

        self.state = "LEVEL_CLEAR"
        self.clearPhase = "SCORES"
        self.clearTimer = 2.5
        self.clearPercent = captureResult.percent
        self.clearBonus = splitBonus
        Audio.play("bonus")
        return
    end

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
        self.clearPhase = "SCORES"
        self.clearTimer = 2.5 -- Show score card briefly, then transition to pure artwork showcase
        self.clearPercent = captureResult.percent
        Audio.play("bonus")

        -- Extra bonus for exceeding target threshold
        local excess = captureResult.percent - self.targetPercent
        if excess > 0 then
            local bonus = math.floor(excess * 1000 * mult)
            self.clearBonus = bonus
            self.score = self.score + bonus
            self:saveHighScore()
        else
            self.clearBonus = 0
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

    -- Vector diamond fragment burst
    local px = self.offsetX + self.player.x * self.scaleX
    local py = self.offsetY + self.player.y * self.scaleY
    Particles.spawnDeathBurst(px, py)

    -- Screen shake impact
    self.shakeDuration = 0.35
    self.shakeIntensity = 6
end

function love.update(dt)
    -- Poll gamepad / keyboard input
    game:updateInput()
    Particles.update(dt)

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
        game.titleBlink = game.titleBlink + dt * 4
        if game.titleAttractQix then
            game.titleAttractQix:update(dt)
        end

    elseif game.state == "HOW_TO" then
        game.titleBlink = game.titleBlink + dt * 4
        if game.titleAttractQix then
            game.titleAttractQix:update(dt)
        end

    elseif game.state == "PLAYING" then
        game.timeInLevel = game.timeInLevel + dt

        -- Mutate Sparx to Super Sparx when level timer runs out (Later levels: Level 2+)
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

        -- Update Player
        game.player:update(dt, game.input, game.qixList,
            function(res) game:onAreaCaptured(res) end,
            function(reason) game:onPlayerDeath(reason) end,
            game.offsetX, game.offsetY, game.scaleX, game.scaleY
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
                if game.score > (game.sessionInitialHighScore or 0) and game.score > 0 then
                    game.isNewRecord = true
                    Audio.play("fanfare")
                else
                    game.isNewRecord = false
                end
                game:saveHighScore()
                game.state = "GAME_OVER"
            end
        end

    elseif game.state == "LEVEL_CLEAR" then
        if game.clearPhase == "SCORES" then
            game.clearTimer = game.clearTimer - dt
            if game.clearTimer <= 0 then
                game.clearPhase = "SHOWCASE"
            end
        end
        -- In SHOWCASE mode: holds indefinitely so user can admire the art until pressing A

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
    elseif game.state == "TITLE" then
        if button == "dpup" then
            game.titleIndex = (game.titleIndex > 1) and (game.titleIndex - 1) or #game.titleItems
            Audio.play("tick")
        elseif button == "dpdown" then
            game.titleIndex = (game.titleIndex < #game.titleItems) and (game.titleIndex + 1) or 1
            Audio.play("tick")
        elseif button == "a" or button == "start" then
            game:executeTitleOption()
        end
    elseif game.state == "HOW_TO" then
        if button == "a" or button == "b" or button == "start" or button == "back" then
            game.state = "TITLE"
            Audio.play("tick")
        end
    elseif game.state == "GAME_OVER" then
        if button == "a" or button == "start" then
            Audio.play("start")
            game:startNewGame()
        elseif button == "b" or button == "back" then
            Audio.play("tick")
            game.state = "TITLE"
        end
    elseif game.state == "LEVEL_CLEAR" then
        if button == "a" or button == "start" then
            if game.clearPhase == "SCORES" then
                game.clearPhase = "SHOWCASE"
            elseif game.clearPhase == "SHOWCASE" then
                game:startLevel(game.level + 1)
            end
        end
    end
end

function love.mousepressed(x, y, button)
    if game.state == "GAME_OVER" then
        if y >= 340 and y <= 405 and x >= 330 and x <= 550 then
            Audio.play("tick")
            game.state = "TITLE"
        else
            Audio.play("start")
            game:startNewGame()
        end
    elseif game.state == "LEVEL_CLEAR" then
        if game.clearPhase == "SCORES" then
            game.clearPhase = "SHOWCASE"
        elseif game.clearPhase == "SHOWCASE" then
            game:startLevel(game.level + 1)
        end
    elseif game.state == "TITLE" then
        local startY = 228
        local btnW = 260
        local btnHeight = 40
        local spacing = 14
        local btnX = math.floor((640 - btnW) * 0.5)
        for i = 1, #game.titleItems do
            local by = startY + (i - 1) * (btnHeight + spacing)
            if x >= btnX and x <= btnX + btnW and y >= by and y <= by + btnHeight then
                game.titleIndex = i
                game:executeTitleOption()
                return
            end
        end
    elseif game.state == "HOW_TO" then
        game.state = "TITLE"
        Audio.play("tick")
    end
end

function love.keypressed(key)
    if game.state == "LEVEL_CLEAR" then
        if key == "a" or key == "return" or key == "space" then
            if game.clearPhase == "SCORES" then
                game.clearPhase = "SHOWCASE"
            elseif game.clearPhase == "SHOWCASE" then
                game:startLevel(game.level + 1)
            end
        end
    elseif game.state == "TITLE" then
        if key == "up" or key == "w" then
            game.titleIndex = (game.titleIndex > 1) and (game.titleIndex - 1) or #game.titleItems
            Audio.play("tick")
        elseif key == "down" or key == "s" then
            game.titleIndex = (game.titleIndex < #game.titleItems) and (game.titleIndex + 1) or 1
            Audio.play("tick")
        elseif key == "return" or key == "space" or key == "z" or key == "j" then
            game:executeTitleOption()
        elseif key == "escape" then
            love.event.quit()
        end
    elseif game.state == "HOW_TO" then
        if key == "escape" or key == "return" or key == "space" or key == "b" or key == "x" or key == "k" then
            game.state = "TITLE"
            Audio.play("tick")
        end
    elseif game.state == "GAME_OVER" then
        if key == "return" or key == "space" or key == "a" or key == "z" then
            Audio.play("start")
            game:startNewGame()
        elseif key == "escape" or key == "b" or key == "x" then
            Audio.play("tick")
            game.state = "TITLE"
        end
    elseif key == "escape" or key == "p" then
        if game.state == "PLAYING" then
            game.state = "PAUSED"
            game.pauseIndex = 1
            Audio.stopAll()
        elseif game.state == "PAUSED" then
            game.state = "PLAYING"
        end
    elseif game.state == "PAUSED" then
        if key == "up" or key == "w" then
            game.pauseIndex = (game.pauseIndex > 1) and (game.pauseIndex - 1) or #game.pauseItems
            Audio.play("tick")
        elseif key == "down" or key == "s" then
            game.pauseIndex = (game.pauseIndex < #game.pauseItems) and (game.pauseIndex + 1) or 1
            Audio.play("tick")
        elseif key == "return" or key == "space" then
            game:executePauseOption()
        end
    elseif key == "m" then
        Audio.toggleMute()
    end
end

function game:executeTitleOption()
    local opt = self.titleItems[self.titleIndex]
    if opt == "START" then
        Audio.play("start")
        self:startNewGame()
    elseif opt == "HOW TO" then
        Audio.play("tick")
        self.state = "HOW_TO"
    elseif opt == "QUIT" then
        love.event.quit()
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
    elseif game.state == "HOW_TO" then
        game:drawHowTo()
    elseif game.state == "LEVEL_CLEAR" then
        -- During Level Clear: Unveil 100% full artwork unobstructed in FIT mode!
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

        -- Draw Visual FX Particles (Plasma cutting sparks, capture bursts, death shards)
        Particles.draw()

        -- Draw Floating Score Popups (set font once)
        if #game.floatingScores > 0 then
            love.graphics.setFont(game.fontSmall)
            for _, fs in ipairs(game.floatingScores) do
                local alpha = math.max(0, fs.life / fs.maxLife)
                love.graphics.setColor(fs.color[1], fs.color[2], fs.color[3], alpha)
                love.graphics.print(fs.text, fs.x - 16, fs.y)
            end
        end

        -- Draw Active Banner Alert (e.g. MASSIVE CUT, TARGET NEAR, SPLIT-QIX)
        if game.bannerTimer > 0 and game.bannerText then
            local alpha = math.min(1, game.bannerTimer * 2)
            love.graphics.setColor(0, 0, 0, 0.88 * alpha)
            love.graphics.rectangle("fill", 50, 34, 540, 26, 4, 4)
            love.graphics.setColor(0, 0.95, 1, alpha)
            love.graphics.rectangle("line", 50, 34, 540, 26, 4, 4)
            love.graphics.setColor(1, 0.9, 0.1, alpha)
            love.graphics.setFont(game.fontSmall)
            love.graphics.printf(game.bannerText, 50, 41, 540, "center")
        end

        -- Overlay States
        if game.state == "PAUSED" then
            game:drawPauseMenu()
        elseif game.state == "GAME_OVER" then
            game:drawGameOver()
        end
    end

    love.graphics.pop()

    -- Authentic Arcade CRT Scanline Overlay (single draw call using pre-rendered canvas)
    if game.crtFilter and game.state ~= "LEVEL_CLEAR" and game.crtCanvas then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(game.crtCanvas, 0, 0)
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

    -- Center: Score & Multiplier Badge
    love.graphics.setColor(1, 1, 1, 1)
    if self.scoreMultiplier > 1 then
        love.graphics.print(string.format("1UP %06d", self.score), 242, 8)
        love.graphics.setColor(1.0, 0.85, 0.1, 1)
        love.graphics.print(string.format("[%dX]", self.scoreMultiplier), 342, 8)
    else
        love.graphics.print(string.format("1UP %06d", self.score), 255, 8)
    end

    love.graphics.setColor(1, 0.85, 0.2, 1)
    love.graphics.print(string.format("HI %06d", self.highScore), 382, 8)

    -- Sparx Countdown Meter (Active in later levels: Level 2+)
    local spxBarX = 512
    local spxBarW = 38
    love.graphics.setColor(0.9, 0.4, 1.0, 1)
    love.graphics.print("SPX", 480, 8)

    love.graphics.setColor(0.15, 0.18, 0.25, 1)
    love.graphics.rectangle("fill", spxBarX, gaugeY, spxBarW, gaugeH)

    if self.superSparxEnabled then
        local sparxLeft = math.max(0, self.sparxTimer - self.timeInLevel)
        local sparxRatio = sparxLeft / self.sparxTimer
        local spxFill = math.floor(sparxRatio * spxBarW)
        if sparxRatio > 0.4 then
            love.graphics.setColor(0.0, 0.9, 1.0, 1)
        elseif sparxRatio > 0.15 then
            love.graphics.setColor(1.0, 0.7, 0.1, 1)
        else
            -- Flashing red when Super Sparx mutation is imminent or active
            local flash = (math.floor(love.timer.getTime() * 8) % 2 == 0)
            love.graphics.setColor(1.0, flash and 0.15 or 0.8, 0.15, 1)
        end
        if spxFill > 0 then
            love.graphics.rectangle("fill", spxBarX, gaugeY, spxFill, gaugeH)
        end
    else
        -- Level 1: Normal perimeter patrol only
        love.graphics.setColor(0.0, 0.85, 1.0, 0.75)
        love.graphics.rectangle("fill", spxBarX, gaugeY, spxBarW, gaugeH)
    end
    love.graphics.setColor(0.4, 0.5, 0.6, 1)
    love.graphics.rectangle("line", spxBarX, gaugeY, spxBarW, gaugeH)

    -- Lives (Diamond markers, reusable table)
    love.graphics.setColor(1, 1, 1, 1)
    for i = 1, self.lives do
        local lx = 565 + (i * 14)
        local ly = 13
        LIFE_DIAMOND[1] = lx;     LIFE_DIAMOND[2] = ly - 5
        LIFE_DIAMOND[3] = lx + 5; LIFE_DIAMOND[4] = ly
        LIFE_DIAMOND[5] = lx;     LIFE_DIAMOND[6] = ly + 5
        LIFE_DIAMOND[7] = lx - 5; LIFE_DIAMOND[8] = ly
        love.graphics.polygon("fill", LIFE_DIAMOND)
    end

    -- Level Indicator
    love.graphics.setColor(0.2, 1.0, 0.4, 1)
    love.graphics.print("L" .. self.level, 615, 8)
end

function game:drawTitle()
    -- 1. Pre-rendered cyber grid background
    if game.titleGridCanvas then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(game.titleGridCanvas, 0, 0)
    end

    -- 2. Living attract-mode Qix helix floating in background
    if self.titleAttractQix then
        self.titleAttractQix:draw(game.offsetX, game.offsetY, game.scaleX, game.scaleY)
    end

    -- Dark translucent gradient overlay to keep foreground text ultra legible
    love.graphics.setColor(0.02, 0.03, 0.06, 0.68)
    love.graphics.rectangle("fill", 0, 0, 640, 480)

    -- Top High Score Ribbon
    love.graphics.setFont(game.fontSmall)
    love.graphics.setColor(1, 0.85, 0.2, 0.9)
    love.graphics.printf(string.format("★ ALL TIME HIGH SCORE: %06d ★", self.highScore), 0, 16, 640, "center")

    -- 3. Centerpiece: Stunning Neon Arcade "QIX" Logo
    local titleY = 48
    love.graphics.setFont(game.fontTitle)

    -- Outer magenta/purple neon glow
    love.graphics.setColor(0.9, 0.1, 0.7, 0.35)
    love.graphics.printf("Q  I  X", 0, titleY - 2, 640, "center")
    love.graphics.printf("Q  I  X", 0, titleY + 4, 640, "center")

    -- Cyan neon halo
    love.graphics.setColor(0.0, 0.9, 1.0, 0.45)
    love.graphics.printf("Q  I  X", -3, titleY + 1, 640, "center")
    love.graphics.printf("Q  I  X", 3, titleY + 1, 640, "center")

    -- Electric hot magenta stroke
    love.graphics.setColor(1.0, 0.18, 0.65, 0.95)
    love.graphics.printf("Q  I  X", 0, titleY + 2, 640, "center")

    -- Brilliant white core
    love.graphics.setColor(1.0, 1.0, 1.0, 1.0)
    love.graphics.printf("Q  I  X", 0, titleY, 640, "center")

    -- Stylized decorative vector dividers flanking subtitle
    love.graphics.setLineWidth(1.5)
    love.graphics.setColor(0.0, 0.85, 1.0, 0.6)
    love.graphics.line(100, titleY + 68, 205, titleY + 68)
    love.graphics.line(435, titleY + 68, 540, titleY + 68)

    love.graphics.setFont(game.fontSmall)
    love.graphics.setColor(0.0, 0.95, 1.0, 1.0)
    love.graphics.printf("1981 TAITO ARCADE CLASSIC", 0, titleY + 62, 640, "center")

    love.graphics.setColor(0.55, 0.65, 0.78, 0.9)
    love.graphics.printf("PORTMASTER RK3326 HANDHELD", 0, titleY + 80, 640, "center")

    -- 4. Vertically Centered Menu Buttons ("START", "HOW TO", "QUIT")
    local startY = 228
    local btnW = 260
    local btnH = 40
    local spacing = 14
    local btnX = math.floor((640 - btnW) * 0.5)

    for i, item in ipairs(self.titleItems) do
        local by = startY + (i - 1) * (btnH + spacing)
        local isSelected = (i == self.titleIndex)

        if isSelected then
            local pulse = 0.5 + 0.5 * math.sin(self.titleBlink * 2)

            -- Glowing selection backdrop
            love.graphics.setColor(0.0, 0.55, 0.95, 0.28 + 0.15 * pulse)
            love.graphics.rectangle("fill", btnX, by, btnW, btnH, 6, 6)

            -- Glowing border
            love.graphics.setLineWidth(2)
            love.graphics.setColor(1.0, 0.85, 0.15, 0.95)
            love.graphics.rectangle("line", btnX, by, btnW, btnH, 6, 6)

            -- Animated neon pointers
            love.graphics.setFont(game.fontMid)
            love.graphics.setColor(1.0, 0.85, 0.15, 1.0)
            love.graphics.print(">", btnX + 16, by + 11)
            love.graphics.print("<", btnX + btnW - 28, by + 11)

            -- Selected Button Label
            love.graphics.setColor(1.0, 1.0, 1.0, 1.0)
            love.graphics.printf(item, btnX, by + 11, btnW, "center")
        else
            -- Clean translucent card
            love.graphics.setColor(0.05, 0.07, 0.13, 0.75)
            love.graphics.rectangle("fill", btnX, by, btnW, btnH, 6, 6)

            love.graphics.setLineWidth(1)
            love.graphics.setColor(0.2, 0.28, 0.4, 0.65)
            love.graphics.rectangle("line", btnX, by, btnW, btnH, 6, 6)

            -- Unselected Button Label
            love.graphics.setFont(game.fontMid)
            love.graphics.setColor(0.65, 0.72, 0.84, 0.9)
            love.graphics.printf(item, btnX, by + 11, btnW, "center")
        end
    end

    -- 5. Footer Controls Legend
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.0, 0.85, 1.0, 0.25)
    love.graphics.line(120, 420, 520, 420)

    love.graphics.setFont(game.fontSmall)
    love.graphics.setColor(0.0, 0.95, 1.0, 0.9)
    love.graphics.printf("▲/▼ D-PAD: SELECT    •    (A) / START: CONFIRM", 0, 434, 640, "center")

    love.graphics.setColor(0.45, 0.52, 0.62, 0.85)
    love.graphics.printf("KEYBOARD: ARROWS/WASD + ENTER/SPACE  •  QUIT: ESC", 0, 454, 640, "center")
end

function game:drawHowTo()
    -- Pre-rendered cyber grid background
    if game.titleGridCanvas then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(game.titleGridCanvas, 0, 0)
    end

    -- Dark backdrop overlay
    love.graphics.setColor(0.02, 0.03, 0.05, 0.82)
    love.graphics.rectangle("fill", 0, 0, 640, 480)

    -- Instructions Modal Box
    local mx, my, mw, mh = 36, 24, 568, 432
    love.graphics.setColor(0.04, 0.06, 0.11, 0.94)
    love.graphics.rectangle("fill", mx, my, mw, mh, 8, 8)

    love.graphics.setLineWidth(2)
    love.graphics.setColor(0.0, 0.85, 1.0, 0.9)
    love.graphics.rectangle("line", mx, my, mw, mh, 8, 8)

    -- Header
    love.graphics.setFont(game.fontMid)
    love.graphics.setColor(1.0, 0.85, 0.2, 1.0)
    love.graphics.printf("★ HOW TO PLAY & RULES ★", mx, my + 16, mw, "center")

    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.0, 0.85, 1.0, 0.4)
    love.graphics.line(mx + 30, my + 44, mx + mw - 30, my + 44)

    -- Content Sections
    love.graphics.setFont(game.fontSmall)

    -- 1. Objective
    love.graphics.setColor(0.0, 0.95, 1.0, 1.0)
    love.graphics.print("MISSION OBJECTIVE:", mx + 24, my + 56)
    love.graphics.setColor(0.9, 0.92, 0.96, 1.0)
    love.graphics.printf("Draw Stix lines into the playfield to capture territory. Claim 75% or more to unveil the full artwork and advance!", mx + 24, my + 74, mw - 48, "left")

    -- 2. Dual Draw Controls
    love.graphics.setColor(0.0, 0.95, 1.0, 1.0)
    love.graphics.print("DUAL DRAW CONTROLS:", mx + 24, my + 116)

    love.graphics.setColor(0.0, 0.95, 1.0, 1.0)
    love.graphics.print("FAST DRAW (A / Space):", mx + 24, my + 134)
    love.graphics.setColor(0.85, 0.88, 0.92, 1.0)
    love.graphics.print("Standard speed, 1X points. Ideal for fast escapes.", mx + 225, my + 134)

    love.graphics.setColor(1.0, 0.45, 0.1, 1.0)
    love.graphics.print("SLOW DRAW (B / X):", mx + 24, my + 154)
    love.graphics.setColor(0.85, 0.88, 0.92, 1.0)
    love.graphics.print("Half speed, but DOUBLE 2X POINTS & high risk!", mx + 225, my + 154)

    -- 3. Hazards
    love.graphics.setColor(0.0, 0.95, 1.0, 1.0)
    love.graphics.print("HAZARDS & THREATS:", mx + 24, my + 188)

    love.graphics.setColor(1.0, 0.25, 0.8, 1.0)
    love.graphics.print("THE QIX:", mx + 24, my + 206)
    love.graphics.setColor(0.85, 0.88, 0.92, 1.0)
    love.graphics.print("Chaotic helix. Instant death if it strikes your drawing line!", mx + 115, my + 206)

    love.graphics.setColor(1.0, 0.85, 0.2, 1.0)
    love.graphics.print("SPARX:", mx + 24, my + 226)
    love.graphics.setColor(0.85, 0.88, 0.92, 1.0)
    love.graphics.print("Patrol perimeter borders. Mutate into deadly Super Sparx!", mx + 115, my + 226)

    love.graphics.setColor(1.0, 0.25, 0.25, 1.0)
    love.graphics.print("THE FUSE:", mx + 24, my + 246)
    love.graphics.setColor(0.85, 0.88, 0.92, 1.0)
    love.graphics.print("Stopping or idling while drawing ignites a fuse along your trail!", mx + 115, my + 246)

    -- 4. Classic 1981 Split-Qix Rule
    love.graphics.setColor(1.0, 0.85, 0.15, 1.0)
    love.graphics.print("★ CLASSIC 1981 SPLIT-QIX RULE (LEVEL 3+):", mx + 24, my + 280)
    love.graphics.setColor(0.92, 0.94, 0.98, 1.0)
    love.graphics.printf("In higher levels, TWO Qixes roam the screen! If you slice between them and trap them in separate compartments, you INSTANTLY WIN the round and unlock a permanent Score Multiplier (2X up to 9X)!", mx + 24, my + 298, mw - 48, "left")

    -- Footer Prompt
    local pulse = 0.5 + 0.5 * math.sin(self.titleBlink * 3)
    love.graphics.setColor(0.2, 1.0, 0.4, 0.7 + 0.3 * pulse)
    love.graphics.setFont(game.fontSmall)
    love.graphics.printf("PRESS (B) OR (A) TO RETURN TO MAIN MENU", mx, my + 396, mw, "center")
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
    love.graphics.printf("▲/▼ D-PAD: SELECT • (A): CHOOSE • START: RESUME", 130, 365, 380, "center")
end

function game:drawLevelClear()
    -- 1. Full 100% Unobstructed Artwork Reveal (FIT Mode - Never Cropped!)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, 640, 480)

    if self.grid.bgImage then
        local imgW = self.grid.bgImage:getWidth()
        local imgH = self.grid.bgImage:getHeight()
        -- FIT mode: math.min guarantees 100% complete image visible with clean letterbox framing
        local scale = math.min(640 / imgW, 480 / imgH)
        local drawW = imgW * scale
        local drawH = imgH * scale
        local drawX = math.floor((640 - drawW) * 0.5)
        local drawY = math.floor((480 - drawH) * 0.5)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(self.grid.bgImage, drawX, drawY, 0, scale, scale)
    end

    -- Phase 1: Scores summary banner (briefly shown)
    if self.clearPhase == "SCORES" then
        love.graphics.setColor(0.03, 0.04, 0.08, 0.85)
        love.graphics.rectangle("fill", 40, 365, 560, 95, 8, 8)

        love.graphics.setColor(1.0, 0.85, 0.1, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", 40, 365, 560, 95, 8, 8)

        love.graphics.setFont(game.fontMid)
        love.graphics.setColor(0.2, 1.0, 0.4, 1)
        love.graphics.printf(string.format("★ LEVEL %d COMPLETE! ★", self.level), 40, 375, 560, "center")

        love.graphics.setFont(game.font)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(string.format("TERRITORY UNVEILED: %4.1f%% (GOAL: %d%%)", self.clearPercent or 75, self.targetPercent), 40, 404, 560, "center")

        love.graphics.setFont(game.fontSmall)
        love.graphics.setColor(1, 0.85, 0.2, 1)
        if self.clearBonus and self.clearBonus > 0 then
            love.graphics.printf(string.format("OVER-QUOTA BONUS: +%d PTS", self.clearBonus), 40, 432, 560, "center")
        else
            love.graphics.printf("PREPARING ARTWORK SHOWCASE...", 40, 432, 560, "center")
        end

    -- Phase 2: Pristine Artwork Showcase (NO graphics on image, only small "A" button at bottom right)
    elseif self.clearPhase == "SHOWCASE" then
        local bx = 598
        local by = 445
        local pulse = 0.8 + 0.2 * math.sin(love.timer.getTime() * 5)

        -- Sleek dark backing badge
        love.graphics.setColor(0, 0, 0, 0.65)
        love.graphics.circle("fill", bx, by, 18)

        -- Glowing neon cyan border
        love.graphics.setColor(0.0, 0.95, 1.0, 0.95 * pulse)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", bx, by, 18)

        -- "A" button text
        love.graphics.setFont(game.font)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf("A", bx - 18, by - 6, 36, "center")

        -- Subtle hint tag to the left
        love.graphics.setFont(game.fontSmall)
        love.graphics.setColor(1, 1, 1, 0.75 * pulse)
        love.graphics.printf("NEXT", bx - 70, by - 5, 46, "right")
    end
end

local PILOT_RANKS = {
    { minScore = 150000, grade = "EX", title = "GRAND ARCHITECT",  color = {1.0, 0.85, 0.15} },
    { minScore = 100000, grade = "S",  title = "MASTER OF VOID",   color = {1.0, 0.22, 0.85} },
    { minScore =  60000, grade = "A",  title = "QUANTUM SLICER",   color = {1.0, 0.80, 0.20} },
    { minScore =  35000, grade = "B",  title = "SECTOR VECTRON",   color = {0.20, 1.0, 0.45} },
    { minScore =  15000, grade = "C",  title = "GRID PILOT",       color = {0.00, 0.90, 1.00} },
    { minScore =      0, grade = "D",  title = "RECRUIT CADET",    color = {0.70, 0.80, 0.90} },
}

local function getPilotRank(score)
    for i = 1, #PILOT_RANKS do
        if score >= PILOT_RANKS[i].minScore then
            return PILOT_RANKS[i]
        end
    end
    return PILOT_RANKS[#PILOT_RANKS]
end

function game:drawGameOver()
    -- 1. Dim Backdrop
    love.graphics.setColor(0.02, 0.03, 0.06, 0.88)
    love.graphics.rectangle("fill", 0, 0, 640, 480)

    -- 2. Mission Debriefing Card Frame
    local cardX, cardY, cardW, cardH = 50, 26, 540, 428
    love.graphics.setColor(0.04, 0.06, 0.10, 0.96)
    love.graphics.rectangle("fill", cardX, cardY, cardW, cardH, 10, 10)

    local pulse = 0.8 + 0.2 * math.sin(love.timer.getTime() * 5)
    if self.isNewRecord then
        love.graphics.setColor(1.0, 0.82, 0.15, 0.95 * pulse)
    else
        love.graphics.setColor(0.0, 0.80, 1.0, 0.75)
    end
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", cardX, cardY, cardW, cardH, 10, 10)

    -- Header Divider
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.0, 0.85, 1.0, 0.35)
    love.graphics.line(cardX + 24, cardY + 42, cardX + cardW - 24, cardY + 42)

    -- Top Header Title
    love.graphics.setFont(game.fontMid)
    if self.isNewRecord then
        love.graphics.setColor(1.0, 0.88, 0.20, 1.0)
        love.graphics.printf("★ NEW ALL-TIME RECORD ACHIEVED! ★", cardX, cardY + 12, cardW, "center")
    else
        love.graphics.setColor(0.0, 0.95, 1.0, 1.0)
        love.graphics.printf("MISSION DEBRIEFING", cardX, cardY + 12, cardW, "center")
    end

    -- 3. Upper Hero Section: Final Score & Pilot Rank Badge
    local rank = getPilotRank(self.score)

    -- Final Score Callout (Left)
    love.graphics.setFont(game.fontSmall)
    love.graphics.setColor(0.55, 0.75, 0.95, 0.9)
    love.graphics.print("FINAL SCORE", cardX + 30, cardY + 52)

    love.graphics.setFont(game.fontBig)
    -- Glow effect
    love.graphics.setColor(0.0, 0.85, 1.0, 0.35)
    love.graphics.print(string.format("%06d", self.score), cardX + 32, cardY + 70)
    -- Main text
    love.graphics.setColor(1.0, 1.0, 1.0, 1.0)
    love.graphics.print(string.format("%06d", self.score), cardX + 30, cardY + 68)

    love.graphics.setFont(game.fontSmall)
    if self.isNewRecord then
        love.graphics.setColor(0.25, 1.0, 0.55, 1.0)
        love.graphics.print("NEW HIGH SCORE RECORD SURPASSED!", cardX + 30, cardY + 114)
    else
        love.graphics.setColor(0.70, 0.78, 0.88, 0.85)
        love.graphics.print(string.format("ALL-TIME RECORD: %06d", self.highScore), cardX + 30, cardY + 114)
    end

    -- Pilot Rank Badge (Right)
    local rx, ry, rw, rh = cardX + 330, cardY + 48, 180, 94
    love.graphics.setColor(0.08, 0.11, 0.18, 0.92)
    love.graphics.rectangle("fill", rx, ry, rw, rh, 8, 8)

    love.graphics.setLineWidth(1.5)
    love.graphics.setColor(rank.color[1], rank.color[2], rank.color[3], 0.9)
    love.graphics.rectangle("line", rx, ry, rw, rh, 8, 8)

    love.graphics.setFont(game.fontSmall)
    love.graphics.setColor(0.65, 0.72, 0.85, 1.0)
    love.graphics.printf("PILOT RANK", rx, ry + 8, rw, "center")

    love.graphics.setFont(game.fontBig)
    love.graphics.setColor(rank.color[1], rank.color[2], rank.color[3], 1.0)
    love.graphics.printf(rank.grade, rx, ry + 24, rw, "center")

    love.graphics.setFont(game.fontSmall)
    love.graphics.setColor(rank.color[1], rank.color[2], rank.color[3], 0.95)
    love.graphics.printf(rank.title, rx, ry + 66, rw, "center")

    -- 4. Four Modern Bento Statistics Tiles
    local tw, th = 230, 62
    local tx1, tx2 = cardX + 30, cardX + 280
    local ty1, ty2 = cardY + 154, cardY + 226

    -- Reusable tile renderer
    local function drawStatTile(x, y, label, value, valColor)
        love.graphics.setColor(0.07, 0.09, 0.15, 0.9)
        love.graphics.rectangle("fill", x, y, tw, th, 6, 6)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(0.20, 0.28, 0.42, 0.65)
        love.graphics.rectangle("line", x, y, tw, th, 6, 6)

        love.graphics.setFont(game.fontSmall)
        love.graphics.setColor(0.60, 0.70, 0.82, 0.95)
        love.graphics.print(label, x + 14, y + 8)

        love.graphics.setFont(game.fontMid)
        love.graphics.setColor(valColor[1], valColor[2], valColor[3], 1.0)
        love.graphics.print(value, x + 14, y + 27)
    end

    drawStatTile(tx1, ty1, "SECTOR REACHED", string.format("LEVEL %d", self.level), {0.25, 1.0, 0.55})
    drawStatTile(tx2, ty1, "GRID CLAIMED", string.format("%.1f%%", self.grid:getClaimedPercent()), {0.0, 0.95, 1.0})
    drawStatTile(tx1, ty2, "BEST SINGLE CUT", string.format("%.1f%%", self.bestCutPercent or 0), {1.0, 0.85, 0.20})
    drawStatTile(tx2, ty2, "TOTAL STIX LINES", string.format("%d CUTS", self.totalCuts or 0), {1.0, 0.35, 0.85})

    -- 5. Lower Action Pill Buttons
    local sepY = cardY + 302
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.0, 0.85, 1.0, 0.35)
    love.graphics.line(cardX + 24, sepY, cardX + cardW - 24, sepY)

    local bw, bh = 220, 44
    local bx1 = cardX + 35
    local bx2 = cardX + 285
    local by = cardY + 316

    -- Button 1: Play Again
    love.graphics.setColor(0.04, 0.28, 0.16, 0.85)
    love.graphics.rectangle("fill", bx1, by, bw, bh, 8, 8)
    love.graphics.setLineWidth(2)
    love.graphics.setColor(0.20, 1.0, 0.50, 0.90 * pulse)
    love.graphics.rectangle("line", bx1, by, bw, bh, 8, 8)

    love.graphics.setFont(game.fontMid)
    love.graphics.setColor(1.0, 1.0, 1.0, 1.0)
    love.graphics.printf("(A) PLAY AGAIN", bx1, by + 10, bw, "center")

    -- Button 2: Main Menu
    love.graphics.setColor(0.08, 0.11, 0.18, 0.85)
    love.graphics.rectangle("fill", bx2, by, bw, bh, 8, 8)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.35, 0.45, 0.65, 0.75)
    love.graphics.rectangle("line", bx2, by, bw, bh, 8, 8)

    love.graphics.setFont(game.fontMid)
    love.graphics.setColor(0.80, 0.86, 0.95, 0.90)
    love.graphics.printf("(B) MAIN MENU", bx2, by + 10, bw, "center")

    -- Footer Guidance
    love.graphics.setFont(game.fontSmall)
    love.graphics.setColor(0.50, 0.60, 0.75, 0.90)
    love.graphics.printf("GAMEPAD: (A) RETRY  •  (B) MENU   |   KEYBOARD: SPACE/ENTER  •  ESC", 0, cardY + 382, 640, "center")
end

return game

