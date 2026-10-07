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
local Achievements = require("achievements")
local Crystals = require("crystals")
local Logger = require("logger")
local BorderFX = require("border_fx")
local AmbientShips = require("ambient_ships")

local COLOR_SLOW = {1, 0.45, 0.1}
local COLOR_FAST = {0, 0.95, 1}
local LIFE_DIAMOND = {0, 0, 0, 0, 0, 0, 0, 0}

local DIFFICULTY_CONFIGS = {
    CASUAL = {
        name = "CASUAL",
        lives = 4,
        targetBase = 55,
        targetStep = 2,
        targetMax = 70,
        speedMult = 0.82,
        shieldDuration = 3.5,
        fuseDelay = 0.90,
        fuseBurnSpeed = 32,
        sparxTimer = 36,
        label = "CASUAL"
    },
    ARCADE = {
        name = "ARCADE",
        lives = 3,
        targetBase = 65,
        targetStep = 3,
        targetMax = 80,
        speedMult = 1.0,
        shieldDuration = 2.5,
        fuseDelay = 0.65,
        fuseBurnSpeed = 42,
        sparxTimer = 26,
        label = "ARCADE"
    },
    MASTER = {
        name = "MASTER",
        lives = 2,
        targetBase = 75,
        targetStep = 3,
        targetMax = 88,
        speedMult = 1.22,
        shieldDuration = 1.5,
        fuseDelay = 0.35,
        fuseBurnSpeed = 56,
        sparxTimer = 16,
        label = "MASTER"
    }
}
local DIFFICULTY_ORDER = { "CASUAL", "ARCADE", "MASTER" }

game = {
    state = "TITLE", -- "TITLE", "PLAYING", "PAUSED", "LEVEL_CLEAR", "GAME_OVER", "BADGES"
    score = 0,
    highScore = 10000,
    lives = 3,
    level = 1,
    targetPercent = 75,
    sparxTimer = 35, -- Seconds before Sparx turn into Super Sparx
    timeInLevel = 0,
    difficulty = "ARCADE",

    grid = nil,
    player = nil,
    qixList = {},
    sparxList = {},
    crystals = {},
    freezeTimer = 0,

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
    titleItems = { "START", "HOW TO", "BADGES", "QUIT" },
    titleAttractQix = nil,
    scoreMultiplier = 1,
    bestCutPercent = 0,
    totalCuts = 0,
    isNewRecord = false,
    sessionInitialHighScore = 0,
    badgesScrollIndex = 1,
    howToPage = 1,
    gameOverAnim = nil,

    -- Pause Menu
    pauseIndex = 1,
    pauseItems = {
        { id = "RESUME",     type = "action",  label = "RESUME GAME" },
        { id = "DIFFICULTY", type = "setting", label = "DIFFICULTY" },
        { id = "CRT_FILTER", type = "setting", label = "CRT SCANLINES" },
        { id = "AUDIO",      type = "setting", label = "AUDIO SOUND" },
        { id = "VOLUME",     type = "setting", label = "VOLUME" },
        { id = "RESTART",    type = "action",  label = "RESTART GAME" },
        { id = "QUIT",       type = "action",  label = "QUIT TO TITLE" }
    },

    -- Art Decks & Input Debouncing
    artDeck = {},
    foregroundDeck = {},
    lastArtIndex = nil,
    lastNavTime = 0,

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
    Logger.init()
    Logger.installErrorHandler()
    BorderFX.init()
    AmbientShips.init()

    -- Load Authentic Retro Arcade Font (scaled for crystal-clear readability on 640x480 screen)
    local fontPath = "fonts/pressstart2p.ttf"
    if love.filesystem.getInfo(fontPath) then
        local success, fSmall = pcall(love.graphics.newFont, fontPath, 10)
        local success2, fNormal = pcall(love.graphics.newFont, fontPath, 12)
        local success3, fMid = pcall(love.graphics.newFont, fontPath, 16)
        local success4, fBig = pcall(love.graphics.newFont, fontPath, 26)
        local success5, fTitle = pcall(love.graphics.newFont, fontPath, 42)
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
        game.fontTitle = love.graphics.newFont(42)
    end
    love.graphics.setFont(game.font)

    game.grid = Grid.new(355, 251)
    game.player = Player.new(game.grid)
    game.titleGrid = Grid.new(355, 251)
    game.titleAttractQix = Qix.new(game.titleGrid, 177, 125, 0.75)

    -- Initialize Achievements
    Achievements.init()

    -- Scan art directory for dynamic image deck
    game:scanArtDeck()
    game:scanForegroundDeck()

    -- Load settings (difficulty) if available
    if love.filesystem.getInfo("settings.txt") then
        local sdata = love.filesystem.read("settings.txt")
        if sdata then
            local diff = sdata:match("difficulty=([A-Z]+)")
            if diff and DIFFICULTY_CONFIGS[diff] then
                game.difficulty = diff
            end
        end
    end

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

    if os.getenv("QIX_TEST_QUIT") then
        Logger.info("TEST", "QIX_TEST_QUIT flag detected. Initialization succeeded cleanly! Exiting test.")
        love.event.quit(0)
    end
end

function game:scanArtDeck()
    self.artDeck = {}

    local function naturalSort(a, b)
        local aName = type(a) == "table" and a.name or a
        local bName = type(b) == "table" and b.name or b
        local function pad(num) return string.format("%08d", tonumber(num)) end
        local aKey = aName:lower():gsub("(%d+)", pad)
        local bKey = bName:lower():gsub("(%d+)", pad)
        return aKey < bKey
    end

    local function scanDirFiles(dirPath, isExternal)
        local found = {}
        if not dirPath then return found end

        if isExternal then
            local p = io.popen('ls -1 "' .. dirPath .. '" 2>/dev/null')
            if p then
                for line in p:lines() do
                    local clean = line:gsub("%s+$", ""):gsub("^%s+", "")
                    local lower = clean:lower()
                    if lower:match("%.jpg$") or lower:match("%.jpeg$") or lower:match("%.png$") then
                        table.insert(found, {
                            path = dirPath .. "/" .. clean,
                            name = clean,
                            isExternal = true
                        })
                    end
                end
                p:close()
            end

            -- Manifest file fallback if popen returned nothing
            if #found == 0 then
                local mf = io.open(dirPath .. "/manifest.txt", "r")
                if mf then
                    for line in mf:lines() do
                        local clean = line:gsub("%s+$", ""):gsub("^%s+", "")
                        local lower = clean:lower()
                        if lower:match("%.jpg$") or lower:match("%.jpeg$") or lower:match("%.png$") then
                            local testF = io.open(dirPath .. "/" .. clean, "rb")
                            if testF then
                                testF:close()
                                table.insert(found, {
                                    path = dirPath .. "/" .. clean,
                                    name = clean,
                                    isExternal = true
                                })
                            end
                        end
                    end
                    mf:close()
                end
            end
        else
            if love.filesystem.getInfo(dirPath) then
                local files = love.filesystem.getDirectoryItems(dirPath)
                for _, file in ipairs(files) do
                    local lower = file:lower()
                    if lower:match("%.jpg$") or lower:match("%.jpeg$") or lower:match("%.png$") then
                        table.insert(found, {
                            path = dirPath .. "/" .. file,
                            name = file,
                            isExternal = false
                        })
                    end
                end
            end
        end

        return found
    end

    local collected = {}
    local seen = {}
    local function addFiles(list)
        for _, item in ipairs(list) do
            if not seen[item.name] then
                seen[item.name] = true
                table.insert(collected, item)
            end
        end
    end

    local base = love.filesystem.getSourceBaseDirectory()

    -- 1. Scan external and local 'art_original' directories (master source photos)
    if base then
        addFiles(scanDirFiles(base .. "/art_original", true))
        addFiles(scanDirFiles(base .. "/../art_original", true))
    end
    addFiles(scanDirFiles("art_original", false))

    -- 2. Scan external and local 'art' directories
    if base then
        addFiles(scanDirFiles(base .. "/art", true))
        addFiles(scanDirFiles(base .. "/../art", true))
    end
    addFiles(scanDirFiles("art", false))

    if #collected > 0 then
        table.sort(collected, naturalSort)
        self.artDeck = collected
        print(string.format("Loaded %d background photos for random pool (including art_original).", #self.artDeck))
        return
    end

    -- 3. Fall back to cover.png if available
    if love.filesystem.getInfo("cover.png") then
        table.insert(self.artDeck, {
            path = "cover.png",
            name = "cover.png",
            isExternal = false
        })
    end
end

function game:scanForegroundDeck()
    self.foregroundDeck = {}

    local function naturalSort(a, b)
        local aName = type(a) == "table" and a.name or a
        local bName = type(b) == "table" and b.name or b
        local function pad(num) return string.format("%08d", tonumber(num)) end
        local aKey = aName:lower():gsub("(%d+)", pad)
        local bKey = bName:lower():gsub("(%d+)", pad)
        return aKey < bKey
    end

    -- 1. Check external foreground-art directory on SD card (e.g. /roms/ports/qix/foreground-art/)
    local base = love.filesystem.getSourceBaseDirectory()
    local extFgDir = base and (base .. "/foreground-art")
    local externalFiles = {}

    if extFgDir then
        local p = io.popen('ls -1 "' .. extFgDir .. '" 2>/dev/null')
        if p then
            for line in p:lines() do
                local clean = line:gsub("%s+$", ""):gsub("^%s+", "")
                local lower = clean:lower()
                if lower:match("%.jpg$") or lower:match("%.jpeg$") or lower:match("%.png$") then
                    table.insert(externalFiles, {
                        path = extFgDir .. "/" .. clean,
                        name = clean,
                        isExternal = true
                    })
                end
            end
            p:close()
        end
    end

    if #externalFiles > 0 then
        table.sort(externalFiles, naturalSort)
        self.foregroundDeck = externalFiles
        print(string.format("Loaded %d custom foreground skins from external SD folder: %s", #self.foregroundDeck, extFgDir))
        return
    end

    -- 2. Fall back to internal bundled foreground-art folder inside qix.love
    local internalFiles = {}
    if love.filesystem.getInfo("foreground-art") then
        local files = love.filesystem.getDirectoryItems("foreground-art")
        for _, file in ipairs(files) do
            local lower = file:lower()
            if lower:match("%.jpg$") or lower:match("%.jpeg$") or lower:match("%.png$") then
                table.insert(internalFiles, {
                    path = "foreground-art/" .. file,
                    name = file,
                    isExternal = false
                })
            end
        end
    end

    if #internalFiles > 0 then
        table.sort(internalFiles, naturalSort)
        self.foregroundDeck = internalFiles
        print(string.format("Loaded %d foreground skins from bundled internal deck.", #self.foregroundDeck))
        return
    end
end

function game:saveHighScore()
    if self.score > self.highScore then
        self.highScore = self.score
        love.filesystem.write("highscore.txt", tostring(self.highScore))
    end
end

function game:setState(newState, triggerReason)
    local oldState = self.state
    if oldState == newState then return end
    Logger.info("STATE", "Transition: %s -> %s (trigger: %s)", tostring(oldState), tostring(newState), tostring(triggerReason or "unspecified"))
    Logger.breadcrumb("STATE", "%s -> %s (%s)", tostring(oldState), tostring(newState), tostring(triggerReason or "unspecified"))
    self.state = newState

    if newState == "TITLE" then
        self.titleCooldown = 0.40 -- Prevent accidental double-tap button bleed from GAME_OVER or PAUSE
        self.titleBlink = 0
        if self.titleGrid then
            self.titleGrid:init()
        end
    end
end

function game:cycleDifficulty(dir)
    local curIdx = 2
    for i, d in ipairs(DIFFICULTY_ORDER) do
        if d == self.difficulty then curIdx = i break end
    end
    curIdx = curIdx + dir
    if curIdx < 1 then curIdx = #DIFFICULTY_ORDER end
    if curIdx > #DIFFICULTY_ORDER then curIdx = 1 end
    self.difficulty = DIFFICULTY_ORDER[curIdx]
    self:saveSettings()
    Audio.play("tick")
end

function game:saveSettings()
    local str = string.format("difficulty=%s\n", self.difficulty)
    love.filesystem.write("settings.txt", str)
end

function game:startNewGame()
    local cfg = DIFFICULTY_CONFIGS[self.difficulty] or DIFFICULTY_CONFIGS.ARCADE
    self.sessionInitialHighScore = self.highScore
    self.score = 0
    self.lives = cfg.lives
    self.level = 1
    self.scoreMultiplier = 1
    self.bestCutPercent = 0
    self.totalCuts = 0
    self.isNewRecord = false
    self.freezeTimer = 0
    self:startLevel(1)
end

function game:startLevel(levelNum)
    local cfg = DIFFICULTY_CONFIGS[self.difficulty] or DIFFICULTY_CONFIGS.ARCADE
    self.level = levelNum
    self.timeInLevel = 0
    self.freezeTimer = 0
    self.targetPercent = math.min(cfg.targetMax, cfg.targetBase + (levelNum - 1) * cfg.targetStep)
    Logger.info("GAME", "Starting Round %d (Difficulty: %s | Target: %d%% | SparxTimer: %ds)",
        levelNum, self.difficulty, self.targetPercent, math.max(12, cfg.sparxTimer - (levelNum * 2)))
    collectgarbage("collect")

    -- Super Sparx introduced in later levels (Level 2+)
    self.superSparxEnabled = (levelNum >= 2)
    self.sparxTimer = math.max(12, cfg.sparxTimer - (levelNum * 2))
    self.superSparxAlerted = false
    self.floatingScores = {}
    self.bannerText = nil
    self.bannerTimer = 0
    self.nearTargetAlerted = false
    self.shakeDuration = 0

    self.grid:init(true)
    self.player:reset(cfg)
    Particles.init()
    BorderFX.reset(false)
    AmbientShips.reset()

    -- Spawn in-field tactical crystals for Level 4+
    self.crystals = Crystals.spawnForLevel(self.grid, levelNum)

    -- Achievement check: Veteran Survivor (Level 5+)
    if levelNum >= 5 then
        Achievements.unlock("veteran_survivor")
    end

    -- Load background art for level uncover (random each time, with automatic resilient retry on rejected/corrupt images)
    local loadedBg = false
    if #self.artDeck > 0 then
        local attempts = 0
        local maxAttempts = math.min(8, #self.artDeck)
        while not loadedBg and attempts < maxAttempts do
            attempts = attempts + 1
            local artIndex = 1
            if #self.artDeck > 1 then
                repeat
                    artIndex = love.math.random(1, #self.artDeck)
                until artIndex ~= self.lastArtIndex or #self.artDeck <= 1
            end
            self.lastArtIndex = artIndex

            local chosenArt = self.artDeck[artIndex]
            loadedBg = self.grid:loadBackground(chosenArt, true)
            if loadedBg then
                local artKey = type(chosenArt) == "table" and (chosenArt.name or chosenArt.path) or tostring(chosenArt)
                Achievements.recordArtViewed(artKey)
            end
        end
    end
    if not loadedBg then
        self.grid:loadBackground(nil, true)
    end

    -- Load foreground skin for uncovered playfield (randomly varies each round with resilient fallback)
    local loadedFg = false
    if #self.foregroundDeck > 0 then
        local attempts = 0
        local maxAttempts = math.min(5, #self.foregroundDeck)
        while not loadedFg and attempts < maxAttempts do
            attempts = attempts + 1
            local fgIndex = love.math.random(1, #self.foregroundDeck)
            if #self.foregroundDeck > 1 and self.lastFgIndex and fgIndex == self.lastFgIndex then
                fgIndex = (fgIndex % #self.foregroundDeck) + 1
            end
            self.lastFgIndex = fgIndex
            local chosenFg = self.foregroundDeck[fgIndex]
            loadedFg = self.grid:loadForeground(chosenFg, true)
        end
    end
    if not loadedFg then
        self.grid:loadForeground(nil, true)
    end

    -- Single authoritative pixel refresh and GPU texture upload for the new round
    self.grid:updateAllPixels()
    collectgarbage("collect")

    -- Spawn Qix: Level 1-2 has 1 Qix; Level 3+ has 2 independent Qixes!
    self.qixList = {}
    local qixSpeed = (1.0 + (levelNum - 1) * 0.15) * cfg.speedMult
    local q1 = Qix.new(self.grid, self.grid.width * 0.5, self.grid.height * 0.5, qixSpeed)
    table.insert(self.qixList, q1)

    if levelNum >= 3 then
        local q2 = Qix.new(self.grid, self.grid.width * 0.4, self.grid.height * 0.4, qixSpeed * 1.1)
        table.insert(self.qixList, q2)
    end

    -- Spawn 2 initial Sparx on opposite sides with difficulty speed multiplier
    self.sparxList = {
        Sparx.new(self.grid, 0, 0, true, false, cfg.speedMult),
        Sparx.new(self.grid, self.grid.width - 1, 0, false, false, cfg.speedMult)
    }

    self:setState("PLAYING", "level_start")
end

function game:onAreaCaptured(captureResult)
    Audio.stopDraw()
    Audio.stopFuse()
    Audio.play("capture")

    -- Update animated border level cut progress bar immediately
    if self.targetPercent and self.targetPercent > 0 then
        BorderFX.setProgress(captureResult.percent / self.targetPercent)
    end

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

    -- Achievements checks
    if captureResult.isSlow and captureResult.cutPercent >= 20 then
        Achievements.unlock("deep_cut")
    end
    if self.score >= 100000 then
        Achievements.unlock("century_club")
    end
    if captureResult.percent >= 90 then
        Achievements.unlock("master_artist")
    end

    -- Check crystal collection
    if #self.crystals > 0 then
        local collected = Crystals.checkCollection(self.crystals, self.grid)
        for _, c in ipairs(collected) do
            if c.type == "FREEZE" then
                self.freezeTimer = 4.5
                self.bannerText = "❄ CHRONO FREEZE! 4.5s TIME STOP! ❄"
                self.bannerTimer = 2.5
                Audio.play("bonus")
            elseif c.type == "BONUS" then
                local gemPts = 5000 * mult
                self.score = self.score + gemPts
                self:saveHighScore()
                self.bannerText = string.format("★ STAR CACHE! +%d PTS! ★", gemPts)
                self.bannerTimer = 2.2
                Audio.play("bonus")
            elseif c.type == "SHIELD" then
                self.lives = math.min(6, self.lives + 1)
                self.player.shieldTimer = math.max(self.player.shieldTimer, 5.0)
                self.bannerText = "🛡 SHIELD MATRIX! +1 LIFE & BARRIER! 🛡"
                self.bannerTimer = 2.5
                Audio.play("bonus")
            end
        end
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
        Achievements.unlock("divide_conquer")

        self.bannerText = string.format("★ SPLIT-QIX! %dX MULTIPLIER UNLOCKED! ★", self.scoreMultiplier)
        self.bannerTimer = 3.5

        if self.level == 1 then
            Achievements.unlock("first_contact")
        end

        self:setState("LEVEL_CLEAR", "split_qix")
        self.clearPhase = "SCORES"
        self.clearTimer = 2.5
        self.clearPercent = captureResult.percent
        self.clearBonus = splitBonus
        Audio.play("bonus")
        return
    end

    -- Massive cut celebration banner
    if captureResult.cutPercent >= 10 and (not self.bannerTimer or self.bannerTimer <= 0) then
        self.bannerText = string.format("⚡ MASSIVE CUT! +%d PTS ⚡", cutPts)
        self.bannerTimer = 2.0
    end

    -- Near target alert
    if captureResult.percent >= (self.targetPercent - 8) and not self.nearTargetAlerted then
        self.bannerText = "⚡ TARGET NEAR! CLOSE THE LOOP! ⚡"
        self.bannerTimer = 2.2
        self.nearTargetAlerted = true
    end

    -- Check level clear threshold
    if captureResult.percent >= self.targetPercent then
        if self.level == 1 then
            Achievements.unlock("first_contact")
        end

        self:setState("LEVEL_CLEAR", "quota_reached")
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

function game:onPlayerDeath(reason, hitGridX, hitGridY)
    if self.state == "DEAD" or self.state == "GAME_OVER" or self.player.state == Player.STATE_DEAD then
        return
    end

    self:setState("DEAD", reason or "player_death")
    self.player.state = Player.STATE_DEAD
    self.lives = self.lives - 1
    self.deathTimer = 1.0
    Logger.info("GAME", "Player lost life (%s). Remaining lives: %d | Level: %d | Score: %d",
        reason or "unknown", self.lives, self.level, self.score)

    Audio.stopAll()
    Audio.play("death")

    -- Fiery arcade explosion burst (incandescent white-gold, blazing yellow, fire orange, deep crimson)
    local px = self.offsetX + self.player.x * self.scaleX
    local py = self.offsetY + self.player.y * self.scaleY
    local hx = hitGridX and (self.offsetX + hitGridX * self.scaleX) or nil
    local hy = hitGridY and (self.offsetY + hitGridY * self.scaleY) or nil

    pcall(Particles.spawnDeathBurst, px, py, hx, hy, self.player.stixPath, self.offsetX, self.offsetY, self.scaleX, self.scaleY)

    -- Screen shake impact (enhanced for heavy explosion punch)
    self.shakeDuration = 0.40
    self.shakeIntensity = 8
end

function love.update(dt)
    -- Poll gamepad / keyboard input
    game:updateInput()
    -- Update animated border line level cut progress bar
    local isAttract = (game.state == "TITLE" or game.state == "HOW_TO" or game.state == "BADGES")
    local curClaimed = (game.grid and game.grid.getClaimedPercent) and game.grid:getClaimedPercent() or 0
    local targetGoal = game.targetPercent or 75
    if game.state == "LEVEL_CLEAR" then
        curClaimed = targetGoal -- Filled to 100% on level completion!
    end
    BorderFX.update(dt, curClaimed, targetGoal, isAttract)
    Particles.update(dt)
    AmbientShips.update(dt)
    Achievements.update(dt)
    Logger.heartbeat(game.state, game.level, game.score, game.lives)

    -- Screen shake decay
    if game.shakeDuration > 0 then
        game.shakeDuration = game.shakeDuration - dt
    end

    -- Banner timer decay
    if game.bannerTimer > 0 then
        game.bannerTimer = game.bannerTimer - dt
    end

    -- Title input debounce cooldown decay
    if game.titleCooldown and game.titleCooldown > 0 then
        game.titleCooldown = math.max(0, game.titleCooldown - dt)
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

    elseif game.state == "PLAYING" then
        game.timeInLevel = game.timeInLevel + dt

        if game.freezeTimer > 0 then
            game.freezeTimer = game.freezeTimer - dt
        end
        Crystals.updateList(game.crystals, dt)

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

        -- Update Qix entities and Sparx enemies (frozen while Chrono Freeze is active)
        if game.freezeTimer <= 0 and game.state == "PLAYING" then
            for _, qix in ipairs(game.qixList) do
                qix:update(dt)
                -- Check collision with player's active stix line
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

    elseif game.state == "DEAD" then
        game.deathTimer = game.deathTimer - dt
        if game.deathTimer <= 0 then
            if game.lives > 0 then
                local cfg = DIFFICULTY_CONFIGS[game.difficulty] or DIFFICULTY_CONFIGS.ARCADE
                game.player:respawn()
                game.player:applyDifficulty(cfg)
                -- Reset Sparx to opposite top corners so player has safe breathing room
                game.sparxList = {
                    Sparx.new(game.grid, 0, 0, true, false, cfg.speedMult),
                    Sparx.new(game.grid, game.grid.width - 1, 0, false, false, cfg.speedMult)
                }
                game.bannerText = "⚡ SAFE SHIELD ACTIVE ⚡"
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
                    game.score, game.level, game.totalCuts or 0, tostring(game.isNewRecord))
                Logger.breadcrumb("GAME", "Game Over initialized. DisplayScore=0 TargetScore=%d", game.score)
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
        if game.gameOverAnim then
            local anim = game.gameOverAnim
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
                        Particles.spawnCaptureBurst(rx, ry, true, 20)
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
                    Particles.spawnCutSpark(sx, sy, love.math.random(-1, 1), love.math.random(-1, 1), love.math.random() > 0.5)
                end
            end
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

function game:navMenu(dir)
    local now = love.timer.getTime()
    if now - self.lastNavTime < 0.12 then
        return
    end
    self.lastNavTime = now

    if self.state == "TITLE" then
        if dir == "up" then
            self.titleIndex = (self.titleIndex > 1) and (self.titleIndex - 1) or #self.titleItems
            Audio.play("tick")
        elseif dir == "down" then
            self.titleIndex = (self.titleIndex < #self.titleItems) and (self.titleIndex + 1) or 1
            Audio.play("tick")
        elseif dir == "left" then
            self:cycleDifficulty(-1)
        elseif dir == "right" then
            self:cycleDifficulty(1)
        end
    elseif self.state == "BADGES" then
        if dir == "up" then
            self.badgesScrollIndex = math.max(1, self.badgesScrollIndex - 1)
            Audio.play("tick")
        elseif dir == "down" then
            self.badgesScrollIndex = math.min(#Achievements.DATA, self.badgesScrollIndex + 1)
            Audio.play("tick")
        end
    elseif self.state == "PAUSED" then
        if dir == "up" then
            self.pauseIndex = (self.pauseIndex > 1) and (self.pauseIndex - 1) or #self.pauseItems
            Audio.play("tick")
        elseif dir == "down" then
            self.pauseIndex = (self.pauseIndex < #self.pauseItems) and (self.pauseIndex + 1) or 1
            Audio.play("tick")
        elseif dir == "left" then
            self:adjustPauseSetting(-1)
        elseif dir == "right" then
            self:adjustPauseSetting(1)
        end
    end
end

function game:adjustPauseSetting(dir)
    local item = self.pauseItems[self.pauseIndex]
    if not item then return end

    if item.id == "DIFFICULTY" then
        self:cycleDifficulty(dir)
        local cfg = DIFFICULTY_CONFIGS[self.difficulty]
        if self.player then self.player:applyDifficulty(cfg) end
    elseif item.id == "CRT_FILTER" then
        self.crtFilter = not self.crtFilter
        Audio.play("tick")
    elseif item.id == "AUDIO" then
        Audio.toggleMute()
        Audio.play("tick")
    elseif item.id == "VOLUME" then
        local cur = math.floor(Audio.volume * 10 + 0.5)
        cur = math.max(0, math.min(10, cur + dir))
        Audio.volume = cur / 10
        if Audio.volume > 0 and Audio.muted then
            Audio.muted = false
        end
        Audio.play("tick")
    end
end

function game:executePauseOption()
    local item = self.pauseItems[self.pauseIndex]
    if not item then return end

    if item.id == "RESUME" then
        self:setState("PLAYING", "pause_resume")
        Audio.play("tick")
    elseif item.id == "DIFFICULTY" then
        self:cycleDifficulty(1)
        local cfg = DIFFICULTY_CONFIGS[self.difficulty]
        if self.player then self.player:applyDifficulty(cfg) end
    elseif item.id == "CRT_FILTER" then
        self.crtFilter = not self.crtFilter
        Audio.play("tick")
    elseif item.id == "AUDIO" then
        Audio.toggleMute()
        Audio.play("tick")
    elseif item.id == "VOLUME" then
        -- Cycle volume: 100% -> 75% -> 50% -> 25% -> 0% -> 100%
        if Audio.volume >= 0.95 then
            Audio.volume = 0.75
        elseif Audio.volume >= 0.70 then
            Audio.volume = 0.50
        elseif Audio.volume >= 0.45 then
            Audio.volume = 0.25
        elseif Audio.volume >= 0.20 then
            Audio.volume = 0.0
            Audio.muted = true
        else
            Audio.volume = 1.0
            Audio.muted = false
        end
        Audio.play("tick")
    elseif item.id == "RESTART" then
        Audio.play("start")
        self:startNewGame()
    elseif item.id == "QUIT" then
        Audio.play("tick")
        self:setState("TITLE", "pause_quit_to_title")
    end
end

function game:executeTitleOption()
    local opt = self.titleItems[self.titleIndex]
    if opt == "START" then
        Audio.play("start")
        self:startNewGame()
    elseif opt == "HOW TO" then
        Audio.play("tick")
        self:setState("HOW_TO", "title_menu_howto")
    elseif opt == "BADGES" then
        Audio.play("tick")
        self.badgesScrollIndex = 1
        self:setState("BADGES", "title_menu_badges")
    elseif opt == "QUIT" then
        Logger.info("SYSTEM", "User selected QUIT option from Title menu.")
        love.event.quit()
    end
end

function love.gamepadpressed(joystick, button)
    -- Global Start Button: Opens Pause menu when PLAYING (never closes menu on Start)
    if button == "start" then
        if game.state == "PLAYING" then
            game:setState("PAUSED", "gamepad_start_pause")
            game.pauseIndex = 1
            game.pauseOpenedAt = love.timer.getTime()
            Audio.stopAll()
            return
        end
    end

    if game.state == "PLAYING" then
        if button == "back" then
            Audio.toggleMute()
        end
    elseif game.state == "PAUSED" then
        local now = love.timer.getTime()
        if (now - (game.pauseOpenedAt or 0)) < 0.15 then
            return
        end
        if button == "dpup" then
            game:navMenu("up")
        elseif button == "dpdown" then
            game:navMenu("down")
        elseif button == "dpleft" then
            game:navMenu("left")
        elseif button == "dpright" then
            game:navMenu("right")
        elseif button == "a" then
            game:executePauseOption()
        elseif button == "b" or button == "back" then
            game:setState("PLAYING", "gamepad_pause_back")
            Audio.play("tick")
        end
    elseif game.state == "TITLE" then
        if (game.titleCooldown or 0) > 0 then
            return
        end
        if button == "dpup" then
            game:navMenu("up")
        elseif button == "dpdown" then
            game:navMenu("down")
        elseif button == "dpleft" then
            game:navMenu("left")
        elseif button == "dpright" then
            game:navMenu("right")
        elseif button == "a" or button == "start" then
            game:executeTitleOption()
        end
    elseif game.state == "BADGES" then
        if button == "dpup" then
            game:navMenu("up")
        elseif button == "dpdown" then
            game:navMenu("down")
        elseif button == "a" or button == "b" or button == "start" or button == "back" then
            game:setState("TITLE", "gamepad_badges_back")
            Audio.play("tick")
        end
    elseif game.state == "HOW_TO" then
        if button == "dpup" then
            game.howToScrollY = math.max(0, (game.howToScrollY or 0) - 50)
            Audio.play("tick")
        elseif button == "dpdown" then
            game.howToScrollY = math.min(game.howToMaxScroll or 120, (game.howToScrollY or 0) + 50)
            Audio.play("tick")
        elseif button == "dpleft" or button == "leftshoulder" then
            game.howToPage = math.max(1, (game.howToPage or 1) - 1)
            game.howToScrollY = 0
            Audio.play("tick")
        elseif button == "dpright" or button == "rightshoulder" then
            game.howToPage = math.min(2, (game.howToPage or 1) + 1)
            game.howToScrollY = 0
            Audio.play("tick")
        elseif button == "a" or button == "b" or button == "start" or button == "back" then
            game:setState("TITLE", "gamepad_howto_back")
            Audio.play("tick")
        end
    elseif game.state == "GAME_OVER" then
        if game.gameOverAnim and game.gameOverAnim.inputLockout and game.gameOverAnim.inputLockout > 0 then
            return
        end
        if button == "dpleft" or button == "dpup" then
            if game.gameOverAnim then game.gameOverAnim.selectedButton = 1 end
            Audio.play("tick")
        elseif button == "dpright" or button == "dpdown" then
            if game.gameOverAnim then game.gameOverAnim.selectedButton = 2 end
            Audio.play("tick")
        elseif button == "a" or button == "start" then
            if game.gameOverAnim and game.gameOverAnim.selectedButton == 2 then
                Audio.play("tick")
                game:setState("TITLE", "gamepad_gameover_quit")
            else
                Audio.play("start")
                game:startNewGame()
            end
        elseif button == "b" or button == "back" then
            Audio.play("tick")
            game:setState("TITLE", "gamepad_gameover_back")
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
        if game.gameOverAnim and game.gameOverAnim.inputLockout and game.gameOverAnim.inputLockout > 0 then
            return
        end
        if y >= 320 and y <= 390 and x >= 290 and x <= 530 then
            Audio.play("tick")
            game:setState("TITLE", "mouse_gameover_quit")
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
        if (game.titleCooldown or 0) > 0 then
            return
        end
        local startY = 195
        local btnW = 260
        local btnHeight = 36
        local spacing = 10
        local btnX = math.floor((640 - btnW) * 0.5)
        for i = 1, #game.titleItems do
            local by = startY + (i - 1) * (btnHeight + spacing)
            if x >= btnX and x <= btnX + btnW and y >= by and y <= by + btnHeight then
                game.titleIndex = i
                game:executeTitleOption()
                return
            end
        end
    elseif game.state == "HOW_TO" or game.state == "BADGES" then
        game:setState("TITLE", "mouse_screen_back")
        Audio.play("tick")
    end
end

function love.keypressed(key)
    -- Global pause: Open pause on Escape or P when PLAYING (never closes on P/Start)
    if key == "escape" or key == "p" then
        if game.state == "PLAYING" then
            game:setState("PAUSED", "keyboard_pause")
            game.pauseIndex = 1
            game.pauseOpenedAt = love.timer.getTime()
            Audio.stopAll()
            return
        end
    end

    if game.state == "LEVEL_CLEAR" then
        if key == "a" or key == "return" or key == "space" then
            if game.clearPhase == "SCORES" then
                game.clearPhase = "SHOWCASE"
            elseif game.clearPhase == "SHOWCASE" then
                game:startLevel(game.level + 1)
            end
        end
    elseif game.state == "TITLE" then
        if (game.titleCooldown or 0) > 0 then
            return
        end
        if key == "up" or key == "w" then
            game:navMenu("up")
        elseif key == "down" or key == "s" then
            game:navMenu("down")
        elseif key == "left" or key == "a" then
            game:navMenu("left")
        elseif key == "right" or key == "d" then
            game:navMenu("right")
        elseif key == "return" or key == "space" or key == "z" or key == "j" then
            game:executeTitleOption()
        elseif key == "escape" then
            if game.titleIndex == #game.titleItems then
                Logger.info("SYSTEM", "User confirmed QUIT from Title menu via Escape.")
                love.event.quit()
            else
                -- Focus QUIT button first rather than immediate hard exit
                game.titleIndex = #game.titleItems
                Audio.play("tick")
            end
        end
    elseif game.state == "BADGES" then
        if key == "up" or key == "w" then
            game:navMenu("up")
        elseif key == "down" or key == "s" then
            game:navMenu("down")
        elseif key == "escape" or key == "return" or key == "space" or key == "b" or key == "x" or key == "k" then
            game:setState("TITLE", "keyboard_badges_back")
            Audio.play("tick")
        end
    elseif game.state == "HOW_TO" then
        if key == "up" or key == "w" then
            game.howToScrollY = math.max(0, (game.howToScrollY or 0) - 50)
            Audio.play("tick")
        elseif key == "down" or key == "s" then
            game.howToScrollY = math.min(game.howToMaxScroll or 120, (game.howToScrollY or 0) + 50)
            Audio.play("tick")
        elseif key == "left" or key == "a" then
            game.howToPage = math.max(1, (game.howToPage or 1) - 1)
            game.howToScrollY = 0
            Audio.play("tick")
        elseif key == "right" or key == "d" then
            game.howToPage = math.min(2, (game.howToPage or 1) + 1)
            game.howToScrollY = 0
            Audio.play("tick")
        elseif key == "escape" or key == "return" or key == "space" or key == "b" or key == "x" or key == "k" then
            game:setState("TITLE", "keyboard_howto_back")
            Audio.play("tick")
        end
    elseif game.state == "GAME_OVER" then
        if game.gameOverAnim and game.gameOverAnim.inputLockout and game.gameOverAnim.inputLockout > 0 then
            return
        end
        if key == "left" or key == "up" or key == "w" then
            if game.gameOverAnim then game.gameOverAnim.selectedButton = 1 end
            Audio.play("tick")
        elseif key == "right" or key == "down" or key == "s" then
            if game.gameOverAnim then game.gameOverAnim.selectedButton = 2 end
            Audio.play("tick")
        elseif key == "return" or key == "space" or key == "z" or key == "j" then
            if game.gameOverAnim and game.gameOverAnim.selectedButton == 2 then
                Audio.play("tick")
                game:setState("TITLE", "keyboard_gameover_quit")
            else
                Audio.play("start")
                game:startNewGame()
            end
        elseif key == "escape" or key == "b" or key == "x" then
            Audio.play("tick")
            game:setState("TITLE", "keyboard_gameover_back")
        end
    elseif game.state == "PAUSED" then
        local now = love.timer.getTime()
        if (now - (game.pauseOpenedAt or 0)) < 0.15 then
            return
        end
        if key == "up" or key == "w" then
            game:navMenu("up")
        elseif key == "down" or key == "s" then
            game:navMenu("down")
        elseif key == "left" or key == "a" then
            game:navMenu("left")
        elseif key == "right" or key == "d" then
            game:navMenu("right")
        elseif key == "return" or key == "space" or key == "z" then
            game:executePauseOption()
        elseif key == "b" or key == "escape" or key == "backspace" then
            game:setState("PLAYING", "keyboard_pause_resume")
            Audio.play("tick")
        end
    elseif key == "m" then
        Audio.toggleMute()
    end
end

function love.wheelmoved(x, y)
    if game.state == "HOW_TO" then
        game.howToScrollY = math.max(0, math.min(game.howToMaxScroll or 120, (game.howToScrollY or 0) - y * 35))
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
    elseif game.state == "BADGES" then
        game:drawBadgesGallery()
    elseif game.state == "LEVEL_CLEAR" then
        -- During Level Clear: Unveil 100% full artwork unobstructed in FIT mode!
        game:drawLevelClear()
    elseif game.state == "GAME_OVER" then
        -- During Game Over: Draw grid underneath cleanly and debriefing card
        if game.grid then
            game.grid:draw(game.offsetX, game.offsetY, game.scaleX, game.scaleY)
        end
        game:drawGameOver()
    else
        -- Draw Top Arcade HUD Bar
        game:drawHUD()

        -- Draw Playfield Grid (uncovering background image)
        game.grid:draw(game.offsetX, game.offsetY, game.scaleX, game.scaleY)

        -- Draw High-Energy Neon Shimmer Border Loader (Dual corner beams, glint sweep & neon aura)
        local boardW = game.grid.width * game.scaleX
        local boardH = game.grid.height * game.scaleY
        BorderFX.draw(game.offsetX, game.offsetY, boardW, boardH)

        -- Draw Floating Power Crystals (Level 4+)
        if #game.crystals > 0 then
            Crystals.drawList(game.crystals, game.offsetX, game.offsetY, game.scaleX, game.scaleY)
        end

        -- Active Chrono Freeze Visual Overlay
        if game.freezeTimer > 0 then
            local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 8)
            love.graphics.setColor(0.1, 0.85, 1.0, 0.10 + 0.08 * pulse)
            love.graphics.rectangle("fill", game.offsetX, game.offsetY, game.grid.width * game.scaleX, game.grid.height * game.scaleY)
            love.graphics.setColor(0.2, 0.95, 1.0, 0.9)
            love.graphics.setFont(game.fontSmall)
            love.graphics.print(string.format("❄ FREEZE TIME: %0.1fs", game.freezeTimer), game.offsetX + 8, game.offsetY + 8)
        end

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
        pcall(Particles.draw)

        -- Draw Ambient Flyby Spaceships (diagonal visual crossing with neon trail light)
        pcall(AmbientShips.draw)

        -- Draw Floating Score Popups (set font once)
        if #game.floatingScores > 0 then
            love.graphics.setFont(game.fontSmall)
            for _, fs in ipairs(game.floatingScores) do
                local alpha = math.max(0, fs.life / fs.maxLife)
                love.graphics.setColor(fs.color[1], fs.color[2], fs.color[3], alpha)
                love.graphics.print(fs.text, fs.x - 16, fs.y)
            end
        end

        -- Draw Active Banner Alert (Large, prominent announcement font for handheld screen)
        if game.bannerTimer > 0 and game.bannerText then
            local alpha = math.min(1, game.bannerTimer * 2.5)
            local pulse = 0.85 + 0.15 * math.sin(love.timer.getTime() * 10)
            local bx, by, bw, bh = 24, 34, 592, 42
            -- Translucent dark glass backdrop
            love.graphics.setColor(0.03, 0.05, 0.09, 0.94 * alpha)
            love.graphics.rectangle("fill", bx, by, bw, bh, 6, 6)
            -- Glowing neon border
            love.graphics.setLineWidth(2)
            love.graphics.setColor(0.0, 0.95, 1.0, alpha * pulse)
            love.graphics.rectangle("line", bx, by, bw, bh, 6, 6)
            -- Text shadow
            love.graphics.setFont(game.fontMid)
            love.graphics.setColor(0, 0, 0, 0.85 * alpha)
            love.graphics.printf(game.bannerText, bx + 2, by + 12, bw, "center")
            -- Vibrant announcement text
            love.graphics.setColor(1.0, 0.88, 0.15, alpha)
            love.graphics.printf(game.bannerText, bx, by + 10, bw, "center")
        end

        -- Overlay States
        if game.state == "PAUSED" then
            game:drawPauseMenu()
        end
    end

    -- Persistent Achievement Unlock Notifications
    Achievements.drawToasts(game.fontMid, game.fontSmall)

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

    -- 4. Vertically Centered Menu Buttons ("START", "HOW TO", "BADGES", "QUIT")
    local startY = 186
    local btnW = 260
    local btnH = 34
    local spacing = 10
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
            love.graphics.print(">", btnX + 16, by + 8)
            love.graphics.print("<", btnX + btnW - 28, by + 8)

            -- Selected Button Label
            love.graphics.setColor(1.0, 1.0, 1.0, 1.0)
            love.graphics.printf(item, btnX, by + 8, btnW, "center")
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
            love.graphics.printf(item, btnX, by + 8, btnW, "center")
        end
    end

    -- 5. Interactive Difficulty Preset Bar
    local diffColors = {
        CASUAL = { 0.2, 1.0, 0.4 },
        ARCADE = { 0.0, 0.95, 1.0 },
        MASTER = { 1.0, 0.35, 0.35 }
    }
    local diffSubtitles = {
        CASUAL = "4 LIVES  •  55% GOAL  •  SLOWER SPARX",
        ARCADE = "3 LIVES  •  65% GOAL  •  STANDARD ARCADE",
        MASTER = "2 LIVES  •  75% GOAL  •  TURBO ENEMIES"
    }
    local curCol = diffColors[self.difficulty] or { 0.0, 0.95, 1.0 }

    love.graphics.setFont(game.fontSmall)
    love.graphics.setColor(0.60, 0.70, 0.85, 0.9)
    love.graphics.printf("DIFFICULTY PRESET", 0, 366, 640, "center")

    love.graphics.setFont(game.fontMid)
    love.graphics.setColor(curCol[1], curCol[2], curCol[3], 1.0)
    love.graphics.printf(string.format("◄ [  %s  ] ►", self.difficulty), 0, 382, 640, "center")

    love.graphics.setFont(game.fontSmall)
    love.graphics.setColor(0.50, 0.60, 0.72, 0.85)
    love.graphics.printf(diffSubtitles[self.difficulty] or "", 0, 402, 640, "center")

    -- 6. Footer Controls Legend
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.0, 0.85, 1.0, 0.25)
    love.graphics.line(100, 420, 540, 420)

    love.graphics.setFont(game.fontSmall)
    love.graphics.setColor(0.0, 0.95, 1.0, 0.9)
    love.graphics.printf("▲/▼: SELECT   •   ◄/►: DIFFICULTY   •   (A)/START: CONFIRM", 0, 432, 640, "center")

    love.graphics.setColor(0.45, 0.52, 0.62, 0.85)
    love.graphics.printf("KEYBOARD: ARROWS/WASD + ENTER/SPACE  •  QUIT: ESC", 0, 452, 640, "center")

end

local howToAssets = nil
local function getHowToAssets()
    if not howToAssets then
        howToAssets = {}
        if love.filesystem.getInfo("assets/coursor/qix-player-coursor-1.png") then
            local ok, img = pcall(love.graphics.newImage, "assets/coursor/qix-player-coursor-1.png")
            if ok then howToAssets.ship = img end
        end
        if love.filesystem.getInfo("assets/freeze.png") then
            local ok, img = pcall(love.graphics.newImage, "assets/freeze.png")
            if ok then howToAssets.freeze = img end
        end
        if love.filesystem.getInfo("assets/battery.png") then
            local ok, img = pcall(love.graphics.newImage, "assets/battery.png")
            if ok then howToAssets.battery = img end
        end
    end
    return howToAssets
end

function game:drawHowTo()
    local hAssets = getHowToAssets()

    -- Pre-rendered cyber grid background
    if game.titleGridCanvas then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(game.titleGridCanvas, 0, 0)
    end

    -- Dark backdrop overlay
    love.graphics.setColor(0.02, 0.03, 0.05, 0.88)
    love.graphics.rectangle("fill", 0, 0, 640, 480)

    -- Instructions Modal Box
    local mx, my, mw, mh = 26, 16, 588, 448
    love.graphics.setColor(0.04, 0.06, 0.11, 0.96)
    love.graphics.rectangle("fill", mx, my, mw, mh, 10, 10)

    love.graphics.setLineWidth(2)
    love.graphics.setColor(0.0, 0.85, 1.0, 0.9)
    love.graphics.rectangle("line", mx, my, mw, mh, 10, 10)

    -- Header Title
    love.graphics.setFont(game.fontMid)
    love.graphics.setColor(1.0, 0.85, 0.2, 1.0)
    love.graphics.printf("★ HOW TO PLAY & RULES ★", mx, my + 14, mw, "center")

    -- Page Switcher Tabs
    local curPage = game.howToPage or 1
    local tabW = 260
    local tabH = 24
    local tabY = my + 44
    local tab1X = mx + 24
    local tab2X = mx + mw - 24 - tabW

    -- Tab 1
    if curPage == 1 then
        love.graphics.setColor(0.0, 0.55, 0.85, 0.9)
        love.graphics.rectangle("fill", tab1X, tabY, tabW, tabH, 5, 5)
        love.graphics.setColor(1, 1, 1, 1)
    else
        love.graphics.setColor(0.06, 0.10, 0.16, 0.85)
        love.graphics.rectangle("fill", tab1X, tabY, tabW, tabH, 5, 5)
        love.graphics.setColor(0.55, 0.65, 0.78, 1)
    end
    love.graphics.setFont(game.fontSmall)
    love.graphics.printf("1. RULES & CONTROLS", tab1X, tabY + 7, tabW, "center")

    -- Tab 2
    if curPage == 2 then
        love.graphics.setColor(0.0, 0.55, 0.85, 0.9)
        love.graphics.rectangle("fill", tab2X, tabY, tabW, tabH, 5, 5)
        love.graphics.setColor(1, 1, 1, 1)
    else
        love.graphics.setColor(0.06, 0.10, 0.16, 0.85)
        love.graphics.rectangle("fill", tab2X, tabY, tabW, tabH, 5, 5)
        love.graphics.setColor(0.55, 0.65, 0.78, 1)
    end
    love.graphics.setFont(game.fontSmall)
    love.graphics.printf("2. THREATS & CRYSTALS", tab2X, tabY + 7, tabW, "center")

    -- Divider line
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.0, 0.85, 1.0, 0.35)
    love.graphics.line(mx + 20, my + 74, mx + mw - 20, my + 74)

    -- Scrollable content viewport
    local viewX = mx + 16
    local viewY = my + 80
    local viewW = mw - 32
    local viewH = 332

    love.graphics.setScissor(viewX, viewY, viewW, viewH)
    love.graphics.push()
    love.graphics.translate(0, - (game.howToScrollY or 0))

    local contentY = viewY + 6
    local cardW = viewW - 14

    if curPage == 1 then
        -- ---------------- PAGE 1: RULES & CONTROLS ----------------
        -- 1. Objective
        love.graphics.setFont(game.fontSmall)
        love.graphics.setColor(0.0, 0.95, 1.0, 1.0)
        love.graphics.print("► MISSION OBJECTIVE:", viewX + 4, contentY)
        contentY = contentY + 18

        love.graphics.setColor(0.90, 0.92, 0.96, 1.0)
        love.graphics.printf("Draw Stix lines into the playfield to enclose territory. Claim 75% or more of the grid to unveil the full hidden artwork and clear the round!", viewX + 6, contentY, cardW - 8, "left")
        contentY = contentY + 44

        -- 2. Dual Draw Speed Controls
        love.graphics.setColor(0.0, 0.95, 1.0, 1.0)
        love.graphics.print("► DUAL DRAW SPEED CONTROLS:", viewX + 4, contentY)
        contentY = contentY + 20

        -- Fast Draw Card
        love.graphics.setColor(0.05, 0.12, 0.22, 0.92)
        love.graphics.rectangle("fill", viewX + 4, contentY, cardW, 60, 6, 6)
        love.graphics.setColor(0.0, 0.85, 1.0, 0.5)
        love.graphics.rectangle("line", viewX + 4, contentY, cardW, 60, 6, 6)

        -- Spaceship icon with cyan glow
        if hAssets.ship then
            love.graphics.setColor(0.0, 0.95, 1.0, 0.4)
            love.graphics.circle("fill", viewX + 26, contentY + 30, 14)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(hAssets.ship, viewX + 26, contentY + 30, math.pi * 0.5, 24 / 61, 24 / 61, 30.5, 29.5)
        end

        love.graphics.setColor(0.0, 0.95, 1.0, 1.0)
        love.graphics.print("FAST DRAW  [ (A) / SPACE ]", viewX + 50, contentY + 8)
        love.graphics.setColor(0.85, 0.88, 0.94, 1.0)
        love.graphics.printf("Standard speed, 1X points. Best for quick slicing, fast escapes & aggressive grid capture.", viewX + 50, contentY + 26, cardW - 60, "left")
        contentY = contentY + 70

        -- Slow Draw Card
        love.graphics.setColor(0.20, 0.08, 0.04, 0.92)
        love.graphics.rectangle("fill", viewX + 4, contentY, cardW, 60, 6, 6)
        love.graphics.setColor(1.0, 0.45, 0.1, 0.6)
        love.graphics.rectangle("line", viewX + 4, contentY, cardW, 60, 6, 6)

        -- Spaceship icon with orange glow
        if hAssets.ship then
            love.graphics.setColor(1.0, 0.45, 0.1, 0.4)
            love.graphics.circle("fill", viewX + 26, contentY + 30, 14)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(hAssets.ship, viewX + 26, contentY + 30, math.pi * 0.5, 24 / 61, 24 / 61, 30.5, 29.5)
        end

        love.graphics.setColor(1.0, 0.55, 0.15, 1.0)
        love.graphics.print("SLOW DRAW  [ (B) / (X) / SHIFT ]", viewX + 50, contentY + 8)
        love.graphics.setColor(0.85, 0.88, 0.94, 1.0)
        love.graphics.printf("Half speed, but awards DOUBLE 2X POINTS & massive score boosts! High risk, maximum arcade rewards.", viewX + 50, contentY + 26, cardW - 60, "left")
        contentY = contentY + 70

        -- 3. Split-Qix Rule
        love.graphics.setColor(1.0, 0.85, 0.20, 1.0)
        love.graphics.print("★ CLASSIC 1981 SPLIT-QIX RULE (LEVEL 3+):", viewX + 4, contentY)
        contentY = contentY + 18

        love.graphics.setColor(0.90, 0.92, 0.96, 1.0)
        love.graphics.printf("In higher levels, TWO Qixes roam the field! Slice between them into separate compartments to INSTANTLY WIN the round and unlock a permanent Score Multiplier (2X up to 9X)!", viewX + 6, contentY, cardW - 8, "left")
        contentY = contentY + 52

        -- 4. Intersection Snapping & Turn Assist
        love.graphics.setColor(0.2, 1.0, 0.45, 1.0)
        love.graphics.print("► CORNER SNAPPING & TURN ASSIST:", viewX + 4, contentY)
        contentY = contentY + 18

        love.graphics.setColor(0.90, 0.92, 0.96, 1.0)
        love.graphics.printf("Tap perpendicular inputs near intersections for fluid 120ms buffered snapping onto perpendicular perimeter tracks without stalling.", viewX + 6, contentY, cardW - 8, "left")
        contentY = contentY + 48

    else
        -- ---------------- PAGE 2: THREATS & CRYSTALS ----------------
        -- 1. Enemy Threats & Hazards
        love.graphics.setFont(game.fontSmall)
        love.graphics.setColor(1.0, 0.35, 0.45, 1.0)
        love.graphics.print("► ENEMY THREATS & HAZARDS:", viewX + 4, contentY)
        contentY = contentY + 18

        -- Hazard 1: Qix
        love.graphics.setColor(0.12, 0.05, 0.14, 0.92)
        love.graphics.rectangle("fill", viewX + 4, contentY, cardW, 46, 5, 5)
        love.graphics.setColor(1.0, 0.25, 0.85, 0.5)
        love.graphics.rectangle("line", viewX + 4, contentY, cardW, 46, 5, 5)
        love.graphics.setColor(1.0, 0.35, 0.90, 1.0)
        love.graphics.print("THE QIX:", viewX + 14, contentY + 6)
        love.graphics.setColor(0.88, 0.90, 0.95, 1.0)
        love.graphics.printf("Chaotic wandering helix. Striking your active stix line is fatal! Seal lines quickly.", viewX + 14, contentY + 22, cardW - 24, "left")
        contentY = contentY + 54

        -- Hazard 2: Sparx
        love.graphics.setColor(0.16, 0.12, 0.04, 0.92)
        love.graphics.rectangle("fill", viewX + 4, contentY, cardW, 46, 5, 5)
        love.graphics.setColor(1.0, 0.80, 0.15, 0.5)
        love.graphics.rectangle("line", viewX + 4, contentY, cardW, 46, 5, 5)
        love.graphics.setColor(1.0, 0.85, 0.20, 1.0)
        love.graphics.print("SPARX:", viewX + 14, contentY + 6)
        love.graphics.setColor(0.88, 0.90, 0.95, 1.0)
        love.graphics.printf("Patrol perimeter borders. Mutate into lethal Super Sparx when the level timer runs out!", viewX + 14, contentY + 22, cardW - 24, "left")
        contentY = contentY + 54

        -- Hazard 3: Fuse
        love.graphics.setColor(0.18, 0.05, 0.05, 0.92)
        love.graphics.rectangle("fill", viewX + 4, contentY, cardW, 46, 5, 5)
        love.graphics.setColor(1.0, 0.30, 0.30, 0.5)
        love.graphics.rectangle("line", viewX + 4, contentY, cardW, 46, 5, 5)
        love.graphics.setColor(1.0, 0.35, 0.35, 1.0)
        love.graphics.print("THE FUSE:", viewX + 14, contentY + 6)
        love.graphics.setColor(0.88, 0.90, 0.95, 1.0)
        love.graphics.printf("Stopping while drawing ignites a fuse that races down your trail—keep moving!", viewX + 14, contentY + 22, cardW - 24, "left")
        contentY = contentY + 56

        -- 2. Tactical Power Collectibles (Level 4+)
        love.graphics.setColor(0.2, 0.95, 0.6, 1.0)
        love.graphics.print("► TACTICAL POWER COLLECTIBLES (LEVEL 4+):", viewX + 4, contentY)
        contentY = contentY + 18

        love.graphics.setColor(0.85, 0.88, 0.94, 1.0)
        love.graphics.printf("Enclose floating items inside claimed territory to activate instant combat boosts:", viewX + 6, contentY, cardW - 8, "left")
        contentY = contentY + 36

        -- Crystal 1: Freeze
        love.graphics.setColor(0.06, 0.14, 0.22, 0.92)
        love.graphics.rectangle("fill", viewX + 4, contentY, cardW, 50, 5, 5)
        love.graphics.setColor(0.1, 0.9, 1.0, 0.5)
        love.graphics.rectangle("line", viewX + 4, contentY, cardW, 50, 5, 5)

        -- Freeze PNG Asset Icon
        if hAssets.freeze then
            love.graphics.setColor(0.1, 0.85, 1.0, 0.35)
            love.graphics.circle("fill", viewX + 26, contentY + 25, 16)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(hAssets.freeze, viewX + 26, contentY + 25, 0, 26 / 140, 26 / 140, 70, 70)
        end

        love.graphics.setColor(0.1, 0.95, 1.0, 1.0)
        love.graphics.print("CHRONO FREEZE", viewX + 50, contentY + 8)
        love.graphics.setColor(0.88, 0.90, 0.95, 1.0)
        love.graphics.printf("Freezes all enemies and hazards in place for 4.5 seconds!", viewX + 50, contentY + 24, cardW - 60, "left")
        contentY = contentY + 58

        -- Crystal 2: Bonus Battery
        love.graphics.setColor(0.18, 0.15, 0.04, 0.92)
        love.graphics.rectangle("fill", viewX + 4, contentY, cardW, 50, 5, 5)
        love.graphics.setColor(1.0, 0.85, 0.1, 0.5)
        love.graphics.rectangle("line", viewX + 4, contentY, cardW, 50, 5, 5)

        -- Battery PNG Asset Icon
        if hAssets.battery then
            love.graphics.setColor(1.0, 0.85, 0.1, 0.35)
            love.graphics.circle("fill", viewX + 26, contentY + 25, 16)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(hAssets.battery, viewX + 26, contentY + 25, 0, 26 / 140, 26 / 140, 70, 70)
        end

        love.graphics.setColor(1.0, 0.88, 0.15, 1.0)
        love.graphics.print("BATTERY POWER CELL", viewX + 50, contentY + 8)
        love.graphics.setColor(0.88, 0.90, 0.95, 1.0)
        love.graphics.printf("Instant +5,000 bonus points added directly to your score!", viewX + 50, contentY + 24, cardW - 60, "left")
        contentY = contentY + 58

        -- Crystal 3: Shield
        love.graphics.setColor(0.05, 0.16, 0.09, 0.92)
        love.graphics.rectangle("fill", viewX + 4, contentY, cardW, 50, 5, 5)
        love.graphics.setColor(0.2, 1.0, 0.4, 0.5)
        love.graphics.rectangle("line", viewX + 4, contentY, cardW, 50, 5, 5)

        -- Shield Matrix diamond icon
        love.graphics.setColor(0.2, 1.0, 0.4, 0.35)
        love.graphics.circle("fill", viewX + 26, contentY + 25, 16)
        love.graphics.setColor(0.2, 1.0, 0.4, 1.0)
        love.graphics.polygon("fill", viewX + 26, contentY + 16, viewX + 35, contentY + 25, viewX + 26, contentY + 34, viewX + 17, contentY + 25)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.circle("fill", viewX + 26, contentY + 25, 3.5)

        love.graphics.setColor(0.2, 1.0, 0.4, 1.0)
        love.graphics.print("SHIELD MATRIX", viewX + 50, contentY + 8)
        love.graphics.setColor(0.88, 0.90, 0.95, 1.0)
        love.graphics.printf("Awards +1 Extra Life and temporary invulnerability shield!", viewX + 50, contentY + 24, cardW - 60, "left")
        contentY = contentY + 58
    end

    local totalContentH = contentY - (viewY + 6)
    game.howToMaxScroll = math.max(0, totalContentH - viewH + 20)

    love.graphics.pop()
    love.graphics.setScissor()

    -- Scrollbar track & thumb
    if game.howToMaxScroll and game.howToMaxScroll > 0 then
        local sbX = mx + mw - 14
        local sbY = viewY + 4
        local sbW = 4
        local sbH = viewH - 8
        love.graphics.setColor(0.1, 0.2, 0.3, 0.4)
        love.graphics.rectangle("fill", sbX, sbY, sbW, sbH, 2, 2)

        local ratio = viewH / (viewH + game.howToMaxScroll)
        local thumbH = math.max(22, math.floor(sbH * ratio))
        local scrollFraction = math.min(1.0, math.max(0.0, (game.howToScrollY or 0) / game.howToMaxScroll))
        local thumbY = sbY + math.floor((sbH - thumbH) * scrollFraction)

        love.graphics.setColor(0.0, 0.85, 1.0, 0.75)
        love.graphics.rectangle("fill", sbX, thumbY, sbW, thumbH, 2, 2)
    end

    -- Footer Navigation Guidance
    local pulse = 0.5 + 0.5 * math.sin(self.titleBlink * 3)
    love.graphics.setColor(0.2, 1.0, 0.4, 0.7 + 0.3 * pulse)
    love.graphics.setFont(game.fontSmall)
    love.graphics.printf("▲/▼: SCROLL   •   ◄/►: SWITCH PAGE   •   (A) OR (B) TO RETURN", mx, my + 420, mw, "center")
end

function game:drawBadgesGallery()
    -- 1. Pre-rendered cyber grid background
    if game.titleGridCanvas then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(game.titleGridCanvas, 0, 0)
    end

    -- Dark backdrop overlay
    love.graphics.setColor(0.02, 0.03, 0.05, 0.88)
    love.graphics.rectangle("fill", 0, 0, 640, 480)

    -- Badges Modal Box
    local mx, my, mw, mh = 28, 16, 584, 448
    love.graphics.setColor(0.04, 0.06, 0.11, 0.95)
    love.graphics.rectangle("fill", mx, my, mw, mh, 8, 8)

    love.graphics.setLineWidth(2)
    love.graphics.setColor(1.0, 0.85, 0.2, 0.9)
    love.graphics.rectangle("line", mx, my, mw, mh, 8, 8)

    -- Header
    love.graphics.setFont(game.fontMid)
    love.graphics.setColor(1.0, 0.88, 0.2, 1.0)
    love.graphics.printf("★ ACHIEVEMENTS & MEDALS ★", mx, my + 10, mw, "center")

    -- Unlocked count & mini progress bar
    local unlockedCount = Achievements.getUnlockedCount()
    local totalBadges = #Achievements.DATA
    local pct = math.floor((unlockedCount / totalBadges) * 100)

    love.graphics.setFont(game.fontSmall)
    love.graphics.setColor(0.0, 0.95, 1.0, 1.0)
    love.graphics.printf(string.format("UNLOCKED: %d / %d MEDALS (%d%%)", unlockedCount, totalBadges, pct), mx, my + 30, mw, "center")

    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.0, 0.85, 1.0, 0.35)
    love.graphics.line(mx + 20, my + 46, mx + mw - 20, my + 46)

    -- 7 Badge Cards
    local cardStartY = my + 52
    local cardH = 46
    local cardSpacing = 6
    local cardW = mw - 32
    local cardX = mx + 16

    for i, badge in ipairs(Achievements.DATA) do
        local cy = cardStartY + (i - 1) * (cardH + cardSpacing)
        local isSelected = (i == self.badgesScrollIndex)
        local isUnlocked = badge.unlocked

        -- Card Background
        if isUnlocked then
            love.graphics.setColor(0.06, 0.12, 0.18, 0.85)
        else
            love.graphics.setColor(0.04, 0.05, 0.08, 0.70)
        end
        love.graphics.rectangle("fill", cardX, cy, cardW, cardH, 4, 4)

        -- Border
        love.graphics.setLineWidth(isSelected and 2 or 1)
        if isSelected then
            local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 6)
            love.graphics.setColor(0.0, 0.95, 1.0, 0.7 + 0.3 * pulse)
        elseif isUnlocked then
            love.graphics.setColor(1.0, 0.82, 0.15, 0.65)
        else
            love.graphics.setColor(0.25, 0.30, 0.40, 0.40)
        end
        love.graphics.rectangle("line", cardX, cy, cardW, cardH, 4, 4)

        -- Badge Tag Pill (Left)
        local tagW = 104
        local tagH = 26
        local tagX = cardX + 8
        local tagY = cy + 10

        if isUnlocked then
            love.graphics.setColor(1.0, 0.80, 0.15, 0.22)
            love.graphics.rectangle("fill", tagX, tagY, tagW, tagH, 3, 3)
            love.graphics.setColor(1.0, 0.85, 0.2, 0.9)
            love.graphics.rectangle("line", tagX, tagY, tagW, tagH, 3, 3)

            love.graphics.setFont(game.fontSmall)
            love.graphics.setColor(1.0, 0.9, 0.2, 1.0)
            love.graphics.printf(badge.badge or "MEDAL", tagX, tagY + 8, tagW, "center")
        else
            love.graphics.setColor(0.12, 0.14, 0.18, 0.6)
            love.graphics.rectangle("fill", tagX, tagY, tagW, tagH, 3, 3)
            love.graphics.setColor(0.35, 0.40, 0.50, 0.5)
            love.graphics.rectangle("line", tagX, tagY, tagW, tagH, 3, 3)

            love.graphics.setFont(game.fontSmall)
            love.graphics.setColor(0.50, 0.55, 0.65, 0.8)
            love.graphics.printf("[LOCKED]", tagX, tagY + 8, tagW, "center")
        end

        -- Title & Description
        local textX = tagX + tagW + 12
        love.graphics.setFont(game.font)
        if isUnlocked then
            love.graphics.setColor(1.0, 1.0, 1.0, 1.0)
        else
            love.graphics.setColor(0.60, 0.65, 0.75, 0.7)
        end
        love.graphics.print(badge.title, textX, cy + 8)

        love.graphics.setFont(game.fontSmall)
        if isUnlocked then
            love.graphics.setColor(0.2, 1.0, 0.45, 0.95)
        else
            love.graphics.setColor(0.45, 0.50, 0.60, 0.75)
        end
        love.graphics.print(badge.desc, textX, cy + 26)
    end

    -- Footer Prompt
    local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 4)
    love.graphics.setColor(0.2, 1.0, 0.4, 0.7 + 0.3 * pulse)
    love.graphics.setFont(game.fontSmall)
    love.graphics.printf("▲/▼: SCROLL   •   PRESS (B) OR (A) TO RETURN TO MAIN MENU", mx, my + mh - 20, mw, "center")
end

function game:drawPauseMenu()
    -- Dark translucent overlay
    love.graphics.setColor(0.02, 0.03, 0.07, 0.92)
    love.graphics.rectangle("fill", 95, 34, 450, 412, 8, 8)

    love.graphics.setColor(0.0, 0.85, 1.0, 0.9)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", 95, 34, 450, 412, 8, 8)

    -- Header
    love.graphics.setColor(1, 0.85, 0.2, 1)
    love.graphics.setFont(game.fontMid)
    love.graphics.printf("★ SYSTEM PAUSE ★", 95, 48, 450, "center")

    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.0, 0.85, 1.0, 0.3)
    love.graphics.line(125, 74, 515, 74)

    love.graphics.setFont(game.font)
    for i, item in ipairs(self.pauseItems) do
        local y = 88 + (i - 1) * 42
        local isSelected = (i == self.pauseIndex)

        if isSelected then
            love.graphics.setColor(0.0, 0.7, 1.0, 0.22)
            love.graphics.rectangle("fill", 110, y - 5, 420, 32, 6, 6)
            love.graphics.setColor(0.0, 0.95, 1.0, 0.8)
            love.graphics.rectangle("line", 110, y - 5, 420, 32, 6, 6)
        end

        local titleColor = isSelected and { 1, 1, 0.2, 1 } or { 0.75, 0.8, 0.9, 1 }
        love.graphics.setColor(unpack(titleColor))
        love.graphics.printf(item.label, 125, y + 3, 200, "left")

        -- Right side value or prompt
        if item.id == "DIFFICULTY" then
            local diffColors = {
                CASUAL = { 0.2, 1.0, 0.4, 1 },
                ARCADE = { 0.0, 0.95, 1.0, 1 },
                MASTER = { 1.0, 0.35, 0.35, 1 }
            }
            local col = diffColors[self.difficulty] or { 0.0, 0.95, 1.0, 1 }
            love.graphics.setColor(unpack(col))
            local display = isSelected and string.format("◄ [ %s ] ►", self.difficulty) or string.format("[ %s ]", self.difficulty)
            love.graphics.printf(display, 310, y + 3, 200, "right")
        elseif item.id == "CRT_FILTER" then
            local valText = self.crtFilter and "ON" or "OFF"
            local col = self.crtFilter and { 0.2, 1.0, 0.4, 1 } or { 0.6, 0.6, 0.6, 1 }
            love.graphics.setColor(unpack(col))
            local display = isSelected and string.format("◄ [ %s ] ►", valText) or string.format("[ %s ]", valText)
            love.graphics.printf(display, 310, y + 3, 200, "right")
        elseif item.id == "AUDIO" then
            local valText = Audio.muted and "MUTED" or "ON"
            local col = Audio.muted and { 1.0, 0.4, 0.4, 1 } or { 0.2, 1.0, 0.4, 1 }
            love.graphics.setColor(unpack(col))
            local display = isSelected and string.format("◄ [ %s ] ►", valText) or string.format("[ %s ]", valText)
            love.graphics.printf(display, 310, y + 3, 200, "right")
        elseif item.id == "VOLUME" then
            local pct = math.floor(Audio.volume * 100 + 0.5)
            love.graphics.setColor(0.3, 0.9, 1.0, 1)
            local display = isSelected and string.format("◄ %3d%% ►", pct) or string.format("%3d%%", pct)
            love.graphics.printf(display, 310, y + 3, 200, "right")
        elseif item.id == "RESUME" then
            love.graphics.setColor(0.3, 0.85, 1.0, isSelected and 1.0 or 0.6)
            love.graphics.printf(isSelected and "[ PRESS A / B ]" or "", 300, y + 3, 210, "right")
        elseif item.id == "RESTART" or item.id == "QUIT" then
            love.graphics.setColor(1.0, 0.6, 0.2, isSelected and 1.0 or 0.6)
            love.graphics.printf(isSelected and "[ PRESS A ]" or "", 300, y + 3, 210, "right")
        end
    end

    love.graphics.setFont(game.fontSmall)
    love.graphics.setColor(0.5, 0.6, 0.7, 1)
    love.graphics.printf("▲/▼: SELECT   ◄/►: CHANGE   (A): SELECT   (B): RESUME", 95, 396, 450, "center")
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
    local ok, err = pcall(function()
        local anim = self.gameOverAnim or {
            cardY = 22,
            displayScore = self.score,
            tallyDone = true,
            rankRevealed = true,
            selectedButton = 1,
            shimmer = 0
        }

        -- 1. Dim Backdrop with animated cyber grid
        love.graphics.setColor(0.02, 0.03, 0.06, 0.92)
        love.graphics.rectangle("fill", 0, 0, 640, 480)

        -- 2. Mission Debriefing Card Frame (smoothly animated entry from bottom)
        local cardX = 46
        local cardY = math.floor(math.max(16, math.min(180, anim.cardY or 22)))
        local cardW = 548
        local cardH = 436

        -- Card shadow
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", cardX + 4, cardY + 4, cardW, cardH, 8, 8)

        -- Card background
        love.graphics.setColor(0.04, 0.06, 0.10, 0.97)
        love.graphics.rectangle("fill", cardX, cardY, cardW, cardH, 8, 8)

        -- Pulsing animated border
        local pulse = 0.8 + 0.2 * math.sin(love.timer.getTime() * 5)
        love.graphics.setLineWidth(2)
        if self.isNewRecord then
            love.graphics.setColor(1.0, 0.85, 0.15, 0.95 * pulse)
        else
            love.graphics.setColor(0.0, 0.85, 1.0, 0.85 * pulse)
        end
        love.graphics.rectangle("line", cardX, cardY, cardW, cardH, 8, 8)

        -- Header Divider
        love.graphics.setLineWidth(1)
        love.graphics.setColor(0.0, 0.85, 1.0, 0.35)
        love.graphics.line(cardX + 20, cardY + 44, cardX + cardW - 20, cardY + 44)

        -- Top Header Title
        love.graphics.setFont(game.fontMid)
        if self.isNewRecord then
            love.graphics.setColor(1.0, 0.88, 0.20, 1.0)
            love.graphics.printf("* NEW ALL-TIME RECORD ACHIEVED! *", cardX, cardY + 14, cardW, "center")
        else
            love.graphics.setColor(0.0, 0.95, 1.0, 1.0)
            love.graphics.printf("* MISSION DEBRIEFING *", cardX, cardY + 14, cardW, "center")
        end

        -- 3. Upper Hero Section: Final Score & Pilot Rank Badge
        local rank = getPilotRank(self.score)

        -- Final Score Callout (Left)
        love.graphics.setFont(game.font)
        love.graphics.setColor(0.55, 0.75, 0.95, 0.9)
        love.graphics.print("FINAL SCORE", cardX + 30, cardY + 54)

        local scoreStr = string.format("%06d", anim.displayScore or self.score)
        love.graphics.setFont(game.fontBig)
        -- Glow shadow
        love.graphics.setColor(0.0, 0.85, 1.0, 0.4)
        love.graphics.print(scoreStr, cardX + 32, cardY + 74)
        -- Main text
        love.graphics.setColor(1.0, 1.0, 1.0, 1.0)
        love.graphics.print(scoreStr, cardX + 30, cardY + 72)

        love.graphics.setFont(game.font)
        if self.isNewRecord then
            love.graphics.setColor(0.25, 1.0, 0.55, 1.0)
            love.graphics.print("* NEW HIGH SCORE SURPASSED! *", cardX + 30, cardY + 116)
        else
            love.graphics.setColor(0.70, 0.78, 0.88, 0.85)
            love.graphics.print(string.format("ALL-TIME RECORD: %06d", self.highScore or 0), cardX + 30, cardY + 116)
        end

        -- Pilot Rank Badge (Right)
        local rx, ry, rw, rh = cardX + 330, cardY + 50, 188, 92
        love.graphics.setColor(0.08, 0.11, 0.18, 0.92)
        love.graphics.rectangle("fill", rx, ry, rw, rh, 8, 8)

        love.graphics.setLineWidth(2)
        if anim.rankRevealed and rank and rank.color then
            love.graphics.setColor(rank.color[1], rank.color[2], rank.color[3], 0.95)
        else
            love.graphics.setColor(0.3, 0.4, 0.5, 0.6)
        end
        love.graphics.rectangle("line", rx, ry, rw, rh, 8, 8)

        love.graphics.setFont(game.fontSmall)
        love.graphics.setColor(0.65, 0.72, 0.85, 1.0)
        love.graphics.printf("PILOT RANK", rx, ry + 8, rw, "center")

        if anim.rankRevealed and rank then
            love.graphics.setFont(game.fontBig)
            love.graphics.setColor(rank.color[1], rank.color[2], rank.color[3], 1.0)
            love.graphics.printf(rank.grade or "A", rx, ry + 24, rw, "center")

            love.graphics.setFont(game.font)
            love.graphics.setColor(rank.color[1], rank.color[2], rank.color[3], 0.95)
            love.graphics.printf(rank.title or "PILOT", rx, ry + 64, rw, "center")
        else
            love.graphics.setFont(game.font)
            local pulseT = 0.5 + 0.5 * math.sin(love.timer.getTime() * 8)
            love.graphics.setColor(0.0, 0.95, 1.0, 0.5 + 0.5 * pulseT)
            love.graphics.printf("[ EVALUATING ]", rx, ry + 40, rw, "center")
        end

        -- 4. Four Bento Statistics Tiles
        local tw, th = 234, 60
        local tx1, tx2 = cardX + 30, cardX + 284
        local ty1, ty2 = cardY + 152, cardY + 224

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

        local curClaim = (self.grid and self.grid.getClaimedPercent) and self.grid:getClaimedPercent() or 0
        drawStatTile(tx1, ty1, "SECTOR REACHED", string.format("LEVEL %d", self.level), {0.25, 1.0, 0.55})
        drawStatTile(tx2, ty1, "GRID CLAIMED", string.format("%.1f%%", curClaim), {0.0, 0.95, 1.0})
        drawStatTile(tx1, ty2, "BEST SINGLE CUT", string.format("%.1f%%", self.bestCutPercent or 0), {1.0, 0.85, 0.20})
        drawStatTile(tx2, ty2, "TOTAL STIX LINES", string.format("%d CUTS", self.totalCuts or 0), {1.0, 0.35, 0.85})

        -- 5. Lower Action Pill Buttons (with Interactive Navigation Highlight)
        local sepY = cardY + 300
        love.graphics.setLineWidth(1)
        love.graphics.setColor(0.0, 0.85, 1.0, 0.35)
        love.graphics.line(cardX + 20, sepY, cardX + cardW - 20, sepY)

        local bw, bh = 224, 44
        local bx1 = cardX + 32
        local bx2 = cardX + 292
        local by = cardY + 314
        local selBtn = anim.selectedButton or 1

        -- Button 1: Play Again
        local btn1Pulse = (selBtn == 1) and (0.8 + 0.2 * math.sin(love.timer.getTime() * 8)) or 0.6
        if selBtn == 1 then
            love.graphics.setColor(0.04, 0.38, 0.20, 0.95)
        else
            love.graphics.setColor(0.04, 0.16, 0.10, 0.7)
        end
        love.graphics.rectangle("fill", bx1, by, bw, bh, 8, 8)
        love.graphics.setLineWidth((selBtn == 1) and 2 or 1)
        love.graphics.setColor(0.20, 1.0, 0.50, btn1Pulse)
        love.graphics.rectangle("line", bx1, by, bw, bh, 8, 8)

        love.graphics.setFont(game.fontMid)
        love.graphics.setColor(1.0, 1.0, 1.0, 1.0)
        local btn1Text = (selBtn == 1) and "> (A) PLAY AGAIN" or "(A) PLAY AGAIN"
        love.graphics.printf(btn1Text, bx1, by + 12, bw, "center")

        -- Button 2: Main Menu
        local btn2Pulse = (selBtn == 2) and (0.8 + 0.2 * math.sin(love.timer.getTime() * 8)) or 0.6
        if selBtn == 2 then
            love.graphics.setColor(0.12, 0.22, 0.40, 0.95)
        else
            love.graphics.setColor(0.06, 0.09, 0.15, 0.7)
        end
        love.graphics.rectangle("fill", bx2, by, bw, bh, 8, 8)
        love.graphics.setLineWidth((selBtn == 2) and 2 or 1)
        love.graphics.setColor(0.35, 0.75, 1.0, btn2Pulse)
        love.graphics.rectangle("line", bx2, by, bw, bh, 8, 8)

        love.graphics.setFont(game.fontMid)
        love.graphics.setColor(0.85, 0.90, 1.0, 1.0)
        local btn2Text = (selBtn == 2) and "> (B) MAIN MENU" or "(B) MAIN MENU"
        love.graphics.printf(btn2Text, bx2, by + 12, bw, "center")

        -- Footer Guidance
        love.graphics.setFont(game.font)
        love.graphics.setColor(0.55, 0.68, 0.85, 0.95)
        love.graphics.printf("</>: CHOOSE   |   (A)/START: CONFIRM   |   (B): MENU", 0, cardY + 386, 640, "center")
    end)

    if not ok then
        Logger.error("DRAW", "drawGameOver error: %s", tostring(err))
        -- Emergency fallback simple UI
        love.graphics.setColor(0, 0, 0, 0.9)
        love.graphics.rectangle("fill", 80, 120, 480, 240)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setFont(game.fontMid or love.graphics.getFont())
        love.graphics.printf("GAME OVER", 80, 160, 480, "center")
        love.graphics.printf(string.format("SCORE: %d", self.score or 0), 80, 200, 480, "center")
        love.graphics.printf("PRESS (A) TO PLAY AGAIN - (B) FOR MENU", 80, 260, 480, "center")
    end
end

function love.quit()
    Logger.info("SYSTEM", "Clean game shutdown initiated. Draining audio & GPU command buffers...")
    if Audio and Audio.stopAll then
        pcall(Audio.stopAll)
    end
    if love.audio and love.audio.stop then
        pcall(love.audio.stop)
    end
    if love.graphics and love.graphics.clear then
        pcall(function()
            love.graphics.clear(0, 0, 0, 1)
            love.graphics.present()
        end)
    end
    love.timer.sleep(0.05)
    Logger.info("SYSTEM", "Shutdown cleanup complete. Process exiting safely.")
    return false
end

return game

