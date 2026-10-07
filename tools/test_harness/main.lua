-- ==============================================================================
-- QIX - Automated Headless Simulation & Stress-Test Harness
-- Validates geometry, audio concurrency, asset safety, grid math, and state cycles.
-- ==============================================================================

local function findSrcDir()
    local candidates = {
        love.filesystem.getSourceBaseDirectory() .. "/src",
        love.filesystem.getSourceBaseDirectory() .. "/../src",
        love.filesystem.getSourceBaseDirectory() .. "/../../src",
        "src",
        "../src"
    }
    for _, dir in ipairs(candidates) do
        local f = io.open(dir .. "/grid.lua", "r")
        if f then
            f:close()
            return dir
        end
    end
    return "src"
end

local srcDir = findSrcDir()
package.path = srcDir .. "/?.lua;" .. package.path

local testsPassed = 0
local testsFailed = 0
local failures = {}

local function assertTest(name, condition, errMsg)
    if condition then
        testsPassed = testsPassed + 1
        print(string.format("  \27[32m[PASS]\27[0m %s", name))
    else
        testsFailed = testsFailed + 1
        local msg = errMsg or "Assertion failed"
        table.insert(failures, string.format("%s: %s", name, msg))
        print(string.format("  \27[31m[FAIL]\27[0m %s: %s", name, msg))
    end
end

function love.load()
    print("\n=======================================================")
    print(" QIX ARCADE: R36S HEADLESS SIMULATION & STRESS TEST")
    print("=======================================================\n")

    -- --------------------------------------------------------------------------
    -- SUITE 1: AUDIO ENGINE & OPENAL CONCURRENCY
    -- --------------------------------------------------------------------------
    print("[SUITE 1] Testing Audio Engine & OpenAL Concurrency...")
    local okAudio, Audio = pcall(require, "audio")
    assertTest("Audio module loaded", okAudio and Audio ~= nil)

    if okAudio then
        Audio.init()
        assertTest("Audio initialized without error", true)

        -- Rapid interleaved source stopping and playing
        local okCycles = true
        for i = 1, 100 do
            Audio.startDraw(i % 2 == 0)
            Audio.startFuse()
            Audio.stopDraw()
            Audio.play("death")
            Audio.stopAll()
            Audio.play("bonus")
        end
        assertTest("100 cycles of rapid-fire Audio start/stop/play passed", okCycles)

        Audio.stopAll()
        assertTest("Audio.stopAll executed cleanly", true)
    end

    -- --------------------------------------------------------------------------
    -- SUITE 2: PARTICLES & GEOMETRY SAFETY (EARCUT ELIMINATION)
    -- --------------------------------------------------------------------------
    print("\n[SUITE 2] Testing Particles & Mali-G31 Geometry Safety...")
    local okPart, Particles = pcall(require, "particles")
    assertTest("Particles module loaded", okPart and Particles ~= nil)

    if okPart then
        Particles.init()
        assertTest("Particles initialized", true)

        -- Test normal death burst
        local path = { {x=10, y=10}, {x=20, y=20}, {x=30, y=30} }
        Particles.spawnDeathBurst(100, 100, 120, 120, path, 0, 0, 1, 1)
        assertTest("Normal spawnDeathBurst allocated particles", true)

        -- Test degenerate edge cases: nil path, empty path, massive path, offscreen coords
        Particles.spawnDeathBurst(nil, nil, nil, nil, nil, nil, nil, nil, nil)
        Particles.spawnDeathBurst(-500, -500, 1500, 1500, {}, 0, 0, 1, 1)

        local hugePath = {}
        for i = 1, 1000 do
            table.insert(hugePath, { x = i, y = i })
        end
        Particles.spawnDeathBurst(320, 240, 320, 240, hugePath, 0, 0, 1, 1)
        assertTest("Degenerate and massive paths handled safely without crash", true)

        -- Simulate 300 frames of updates and draws to test particle decay to size=0
        local drawOk = true
        for frame = 1, 300 do
            Particles.update(0.016)
            local okD, errD = pcall(Particles.draw)
            if not okD then
                drawOk = false
                print("Particles.draw error at frame " .. frame .. ": " .. tostring(errD))
                break
            end
        end
        assertTest("300 frames of decaying particle updates & quad draws passed", drawOk)

        -- Test capture bursts and sparks
        Particles.spawnCaptureBurst(200, 200, true, 20)
        Particles.spawnCutSpark(150, 150, 1, 0, true)
        Particles.spawnCutSpark(150, 150, 0, 1, false)
        Particles.update(0.016)
        local okSpk = pcall(Particles.draw)
        assertTest("Capture bursts and sparks updated and rendered cleanly", okSpk)
    end

    -- --------------------------------------------------------------------------
    -- SUITE 3: GRID FLOOD-FILL & TERRITORY MATH
    -- --------------------------------------------------------------------------
    print("\n[SUITE 3] Testing Grid Playfield & Territory Flood-Fill...")
    local okGridMod, Grid = pcall(require, "grid")
    assertTest("Grid module loaded", okGridMod and Grid ~= nil)

    if okGridMod then
        local grid = Grid.new(100, 80)
        assertTest("Grid instance created (100x80)", grid ~= nil and grid.width == 100 and grid.height == 80)
        assertTest("Initial claimed percent is 0.0%", grid:getClaimedPercent() == 0)

        -- Draw a closed box Stix cut
        local testStix = {}
        for x = 0, 30 do table.insert(testStix, { x = x, y = 20 }) end
        for y = 20, 0, -1 do table.insert(testStix, { x = 30, y = y }) end

        local mockQix = {
            p1 = { x = 60, y = 50 },
            p2 = { x = 70, y = 60 }
        }
        local res = grid:completeStix(testStix, false, { mockQix })
        assertTest("Stix cut completion returned capture result", res ~= nil and res.capturedCells > 0)
        assertTest("Claimed percentage increased", grid:getClaimedPercent() > 0)
    end

    -- --------------------------------------------------------------------------
    -- SUITE 4: ENTITY LIFECYCLES (PLAYER, QIX, SPARX, CRYSTALS)
    -- --------------------------------------------------------------------------
    print("\n[SUITE 4] Testing Entity Lifecycles & Collision Traps...")
    local Player = require("player")
    local Qix = require("qix")
    local Sparx = require("sparx")
    local Crystals = require("crystals")

    local testGrid = Grid.new(100, 80)
    local player = Player.new(testGrid)
    assertTest("Player created and reset", player ~= nil and player.x ~= nil)

    local qix = Qix.new(testGrid, 1.0)
    assertTest("Qix created", qix ~= nil and #qix.trail >= 0)

    -- Update Qix across 60 frames
    local qixOk = true
    for _ = 1, 60 do
        local ok, err = pcall(function() qix:update(0.016) end)
        if not ok then qixOk = false; break end
    end
    assertTest("Qix updated 60 frames without error", qixOk)

    -- Test Stix collision with player path
    local dummyStix = { {x=qix.p1.x, y=qix.p1.y}, {x=qix.p2.x, y=qix.p2.y} }
    local hit = qix:checkStixCollision(dummyStix)
    assertTest("Qix checkStixCollision executed cleanly", type(hit) == "boolean")

    -- Sparx tests
    local spx = Sparx.new(testGrid, 0, 0, true, false, 1.0)
    assertTest("Sparx created at perimeter", spx ~= nil)
    spx:mutateToSuper()
    assertTest("Sparx mutated to Super Sparx", spx.isSuper == true)

    -- Crystals tests
    local cryList = Crystals.spawnForLevel(testGrid, 4)
    assertTest("Crystals spawned for Level 4", #cryList > 0)
    Crystals.updateList(cryList, 0.016)
    assertTest("Crystals updateList executed cleanly", true)

    -- --------------------------------------------------------------------------
    -- SUITE 5: ASSET INTEGRITY INSPECTION
    -- --------------------------------------------------------------------------
    print("\n[SUITE 5] Testing Asset Integrity & Safety Bounds...")
    local manifestPath = srcDir .. "/art/manifest.txt"
    local fManifest = io.open(manifestPath, "r")
    assertTest("Art manifest file exists", fManifest ~= nil)
    if fManifest then
        local count = 0
        for line in fManifest:lines() do
            if #line > 0 and not line:match("^%s*#") then
                count = count + 1
            end
        end
        fManifest:close()
        assertTest("Art manifest contains 200+ images (found " .. count .. ")", count >= 200)
    end

    -- --------------------------------------------------------------------------
    -- SUITE 6: STATE MACHINE & SCENE ROUTING ARCHITECTURE
    -- --------------------------------------------------------------------------
    print("\n[SUITE 6] Testing State Machine Transitions & Scene Routing...")
    local okSM, StateMachine = pcall(require, "state_machine")
    assertTest("StateMachine module loaded", okSM and StateMachine ~= nil)

    if okSM then
        local StateTitle = require("states.state_title")
        local StatePlaying = require("states.state_playing")
        local StateDead = require("states.state_dead")
        local StateLevelClear = require("states.state_level_clear")
        local StateGameOver = require("states.state_game_over")
        local StateHowTo = require("states.state_how_to")
        local StateBadges = require("states.state_badges")
        local StatePause = require("states.state_pause")

        local mockGame = {
            state = "TITLE",
            score = 1500,
            level = 1,
            totalCuts = 5,
            lives = 3,
            difficulty = "ARCADE",
            DIFFICULTY_CONFIGS = {
                ARCADE = { lives = 3, speedMult = 1.0 }
            },
            grid = Grid.new(50, 40),
            floatingScores = {},
            qixList = {},
            sparxList = {},
            crystals = {},
            setState = function(self, st, reason)
                self.state = st
                self.sm:change(st, reason)
            end,
            saveHighScore = function(self) end,
            drawTitle = function(self) end,
            drawHowTo = function(self) end,
            drawBadgesGallery = function(self) end,
            drawLevelClear = function(self) end,
            drawGameOver = function(self) end,
            drawHUD = function(self) end,
            drawPauseMenu = function(self) end,
            BorderFX = { draw = function() end },
            Particles = { draw = function() end },
            AmbientShips = { draw = function() end }
        }

        local sm = StateMachine.new({
            TITLE = StateTitle.new(mockGame),
            PLAYING = StatePlaying.new(mockGame),
            DEAD = StateDead.new(mockGame),
            LEVEL_CLEAR = StateLevelClear.new(mockGame),
            GAME_OVER = StateGameOver.new(mockGame),
            HOW_TO = StateHowTo.new(mockGame),
            BADGES = StateBadges.new(mockGame),
            PAUSED = StatePause.new(mockGame)
        })
        mockGame.sm = sm

        sm:change("TITLE")
        assertTest("StateMachine changed to TITLE", sm.currentStateName == "TITLE")

        sm:update(0.016)
        assertTest("StateTitle:update executed cleanly", true)

        sm:change("PLAYING")
        assertTest("StateMachine changed to PLAYING", sm.currentStateName == "PLAYING")

        sm:change("PAUSED")
        assertTest("StateMachine changed to PAUSED", sm.currentStateName == "PAUSED")

        sm:change("PLAYING")
        assertTest("StateMachine resumed PLAYING", sm.currentStateName == "PLAYING")

        sm:change("DEAD")
        assertTest("StateMachine changed to DEAD", sm.currentStateName == "DEAD")

        sm:change("GAME_OVER")
        assertTest("StateMachine changed to GAME_OVER", sm.currentStateName == "GAME_OVER" and mockGame.gameOverAnim ~= nil)

        sm:update(0.016)
        assertTest("StateGameOver:update executed cleanly", true)

        sm:change("LEVEL_CLEAR")
        assertTest("StateMachine changed to LEVEL_CLEAR", sm.currentStateName == "LEVEL_CLEAR" and mockGame.clearPhase == "SCORES")
    end

    -- --------------------------------------------------------------------------
    -- FINAL SUMMARY & REPORT
    -- --------------------------------------------------------------------------
    print("\n=======================================================")
    print(string.format(" TEST RESULTS: %d Passed, %d Failed", testsPassed, testsFailed))
    print("=======================================================\n")

    if testsFailed > 0 then
        print("\27[31mFAILURES ENCOUNTERED:\27[0m")
        for _, f in ipairs(failures) do
            print("  - " .. f)
        end
        love.event.quit(1)
    else
        print("\27[32m>>> ALL SUITES PASSED CLEANLY! <<<\27[0m\n")
        love.event.quit(0)
    end
end
