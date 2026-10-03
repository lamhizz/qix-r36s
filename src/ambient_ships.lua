-- ==============================================================================
-- Ambient Flyby Ships - Visual Atmosphere FX for Qix (R36S Handheld)
-- Periodically spawns aesthetic background spaceships cruising diagonally
-- across the game board with radiant neon light trails and engine glow.
-- Visual ambient effect only: zero impact on gameplay collision or rules.
-- ==============================================================================

local AmbientShips = {}

local MAX_SHIPS = 3
local MAX_TRAIL_PTS = 22
local ships = {}
local sprites = {}
local spritesLoaded = false

local SHIP_PALETTES = {
    { trail = { 0.0, 0.90, 1.0 }, glow = { 0.0, 0.60, 1.0 }, core = { 0.85, 0.95, 1.0 } },  -- Cyan / Plasma
    { trail = { 1.0, 0.25, 0.85 }, glow = { 0.8, 0.10, 0.9 }, core = { 1.0, 0.85, 0.95 } }, -- Neon Magenta
    { trail = { 1.0, 0.80, 0.15 }, glow = { 1.0, 0.45, 0.05 }, core = { 1.0, 1.0, 0.85 } }, -- Golden Solar
}

local spawnTimer = 0
local nextSpawnInterval = 8.0 -- First ship appears ~8s into gameplay

local function loadSprites()
    if spritesLoaded then return end
    spritesLoaded = true
    sprites = {}

    local paths = {
        "assets/coursor/qix-player-coursor-1.png",
        "assets/coursor/qix-player-coursor-2.png",
        "assets/coursor/qix-player-coursor-3.png"
    }

    for _, path in ipairs(paths) do
        if love.filesystem.getInfo(path) then
            local ok, img = pcall(love.graphics.newImage, path)
            if ok and img then
                table.insert(sprites, img)
            end
        end
    end
end

function AmbientShips.init()
    loadSprites()
    ships = {}
    for i = 1, MAX_SHIPS do
        local trail = {}
        for p = 1, MAX_TRAIL_PTS do
            trail[p] = { x = 0, y = 0, alpha = 0 }
        end
        ships[i] = {
            active = false,
            x = 0,
            y = 0,
            vx = 0,
            vy = 0,
            speed = 0,
            angle = 0,
            scale = 0.40,
            spriteIndex = 1,
            paletteIndex = 1,
            animTimer = 0,
            trailTimer = 0,
            trailCount = 0,
            trail = trail
        }
    end
    AmbientShips.reset()
end

function AmbientShips.reset()
    for i = 1, MAX_SHIPS do
        if ships[i] then
            ships[i].active = false
            ships[i].trailCount = 0
        end
    end
    spawnTimer = 0
    nextSpawnInterval = love.math.random(6, 12)
end

function AmbientShips.spawn()
    -- Find an inactive ship slot
    local ship = nil
    for i = 1, MAX_SHIPS do
        if not ships[i].active then
            ship = ships[i]
            break
        end
    end
    if not ship then return end

    local spriteCount = #sprites
    ship.spriteIndex = (spriteCount > 0) and love.math.random(1, spriteCount) or 1
    ship.paletteIndex = love.math.random(1, #SHIP_PALETTES)

    -- Diagonal Corridors
    -- 1: Top-Left to Bottom-Right
    -- 2: Bottom-Left to Top-Right
    -- 3: Top-Right to Bottom-Left
    -- 4: Bottom-Right to Top-Left
    local corridor = love.math.random(1, 4)
    local startX, startY, endX, endY

    if corridor == 1 then
        startX = -60
        startY = love.math.random(20, 160)
        endX = 700
        endY = startY + love.math.random(220, 360)
    elseif corridor == 2 then
        startX = -60
        startY = love.math.random(320, 460)
        endX = 700
        endY = startY - love.math.random(220, 360)
    elseif corridor == 3 then
        startX = 700
        startY = love.math.random(20, 160)
        endX = -60
        endY = startY + love.math.random(220, 360)
    else
        startX = 700
        startY = love.math.random(320, 460)
        endX = -60
        endY = startY - love.math.random(220, 360)
    end

    local dx = endX - startX
    local dy = endY - startY
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1 then dist = 1 end

    local speed = love.math.random(200, 310)
    ship.x = startX
    ship.y = startY
    ship.speed = speed
    ship.vx = (dx / dist) * speed
    ship.vy = (dy / dist) * speed
    ship.angle = math.atan2(ship.vy, ship.vx) + math.pi * 0.5
    ship.scale = love.math.random(24, 28) / 61 -- Clear handheld scale (~24-28px)
    ship.animTimer = love.math.random() * 6.28
    ship.trailTimer = 0
    ship.trailCount = 0
    ship.active = true

    -- Pre-fill trail head
    for p = 1, MAX_TRAIL_PTS do
        ship.trail[p].x = startX
        ship.trail[p].y = startY
        ship.trail[p].alpha = 0
    end
end

function AmbientShips.update(dt)
    -- Handle periodic spawning
    spawnTimer = spawnTimer + dt
    if spawnTimer >= nextSpawnInterval then
        spawnTimer = 0
        nextSpawnInterval = love.math.random(14, 26) -- Spawns every 14-26 seconds
        AmbientShips.spawn()
    end

    -- Update active ships
    for i = 1, MAX_SHIPS do
        local s = ships[i]
        if s.active then
            s.animTimer = s.animTimer + dt * 16
            s.x = s.x + s.vx * dt
            s.y = s.y + s.vy * dt

            -- Record trail points behind engine nozzle
            s.trailTimer = s.trailTimer + dt
            if s.trailTimer >= 0.026 then
                s.trailTimer = 0
                -- Shift trail array backwards
                for p = MAX_TRAIL_PTS, 2, -1 do
                    s.trail[p].x = s.trail[p - 1].x
                    s.trail[p].y = s.trail[p - 1].y
                    s.trail[p].alpha = s.trail[p - 1].alpha
                end
                -- Nozzle offset behind center along velocity direction
                local normVx = s.vx / s.speed
                local normVy = s.vy / s.speed
                local nX = s.x - normVx * 12
                local nY = s.y - normVy * 12

                s.trail[1].x = nX
                s.trail[1].y = nY
                s.trail[1].alpha = 1.0
                if s.trailCount < MAX_TRAIL_PTS then
                    s.trailCount = s.trailCount + 1
                end
            end

            -- Fade trail points smoothly
            for p = 1, s.trailCount do
                s.trail[p].alpha = math.max(0, s.trail[p].alpha - dt * 1.4)
            end

            -- Despawn when far out of screen bounds
            if s.x < -120 or s.x > 760 or s.y < -120 or s.y > 600 then
                s.active = false
                s.trailCount = 0
            end
        end
    end
end

function AmbientShips.draw()
    for i = 1, MAX_SHIPS do
        local s = ships[i]
        if s.active and s.trailCount > 1 then
            local pal = SHIP_PALETTES[s.paletteIndex] or SHIP_PALETTES[1]
            local tc = s.trailCount

            -- 1. Outer Neon Aura Trail Ribbon (soft glowing boundary)
            love.graphics.setLineWidth(3.8)
            for p = 1, tc - 1 do
                local pt1 = s.trail[p]
                local pt2 = s.trail[p + 1]
                local a = ((tc - p) / tc) * 0.45 * pt1.alpha
                if a > 0.01 then
                    love.graphics.setColor(pal.glow[1], pal.glow[2], pal.glow[3], a)
                    love.graphics.line(pt1.x, pt1.y, pt2.x, pt2.y)
                end
            end

            -- 2. Inner Radiant Core Light Trail (bright beam)
            love.graphics.setLineWidth(1.8)
            for p = 1, tc - 1 do
                local pt1 = s.trail[p]
                local pt2 = s.trail[p + 1]
                local a = ((tc - p) / tc) * 0.90 * pt1.alpha
                if a > 0.01 then
                    love.graphics.setColor(pal.core[1], pal.core[2], pal.core[3], a)
                    love.graphics.line(pt1.x, pt1.y, pt2.x, pt2.y)
                end
            end

            -- 3. Engine Thruster Nozzle Flare
            local normVx = s.vx / s.speed
            local normVy = s.vy / s.speed
            local nX = s.x - normVx * 12
            local nY = s.y - normVy * 12
            local pulse = 0.8 + 0.2 * math.sin(s.animTimer)

            -- Outer engine bloom
            love.graphics.setColor(pal.trail[1], pal.trail[2], pal.trail[3], 0.55 * pulse)
            love.graphics.circle("fill", nX, nY, 8.5 * pulse)

            -- White-hot engine core
            love.graphics.setColor(1.0, 1.0, 1.0, 0.95 * pulse)
            love.graphics.circle("fill", nX, nY, 3.2 * pulse)

            -- 4. Spaceship Sprite (rotated towards movement direction)
            local spr = sprites[s.spriteIndex] or sprites[1]
            if spr then
                love.graphics.setColor(1, 1, 1, 0.98)
                love.graphics.draw(spr, s.x, s.y, s.angle, s.scale, s.scale, 30.5, 29.5)
            end
        end
    end
end

return AmbientShips
