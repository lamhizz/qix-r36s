-- ==============================================================================
-- QIX - Arcade Particle & Visual FX System
-- Zero-allocation static particle pool for high-performance 60 FPS visual flair.
-- ==============================================================================

local Particles = {}

local MAX_PARTICLES = 96
local pool = {}

for i = 1, MAX_PARTICLES do
    pool[i] = {
        active = false,
        x = 0, y = 0,
        vx = 0, vy = 0,
        life = 0, maxLife = 1,
        size = 2,
        r = 1, g = 1, b = 1,
        rot = 0, vRot = 0,
        shape = 1 -- 1: spark, 2: shard
    }
end

function Particles.init()
    for i = 1, MAX_PARTICLES do
        pool[i].active = false
    end
end

local function allocParticle()
    for i = 1, MAX_PARTICLES do
        if not pool[i].active then
            return pool[i]
        end
    end
    -- If pool full, recycle the oldest particle
    local oldest = pool[1]
    local minLife = oldest.life
    for i = 2, MAX_PARTICLES do
        if pool[i].life < minLife then
            minLife = pool[i].life
            oldest = pool[i]
        end
    end
    return oldest
end

function Particles.spawnCutSpark(sx, sy, dx, dy, isSlow)
    local p = allocParticle()
    p.active = true
    p.x = sx
    p.y = sy
    -- Spray backwards opposite to move direction with random angular scatter
    local angle = math.atan2(-dy, -dx) + (love.math.random() - 0.5) * 1.4
    local speed = love.math.random(35, 95)
    p.vx = math.cos(angle) * speed
    p.vy = math.sin(angle) * speed
    p.life = love.math.random(0.18, 0.35)
    p.maxLife = p.life
    p.size = love.math.random(1.5, 2.8)
    p.shape = 1

    if isSlow then
        -- Fiery orange / amber plasma sparks
        p.r = 1.0
        p.g = love.math.random(0.35, 0.75)
        p.b = 0.05
    else
        -- Electric cyan / neon blue sparks
        p.r = love.math.random(0.05, 0.3)
        p.g = love.math.random(0.85, 1.0)
        p.b = 1.0
    end
end

function Particles.spawnCaptureBurst(cx, cy, isSlow, count)
    local num = count or 24
    for _ = 1, num do
        local p = allocParticle()
        p.active = true
        p.x = cx
        p.y = cy
        local angle = love.math.random() * math.pi * 2
        local speed = love.math.random(50, 165)
        p.vx = math.cos(angle) * speed
        p.vy = math.sin(angle) * speed
        p.life = love.math.random(0.45, 0.85)
        p.maxLife = p.life
        p.size = love.math.random(2.0, 4.0)
        p.shape = 1

        if isSlow then
            -- Fiery gold / orange burst
            p.r = 1.0
            p.g = love.math.random(0.4, 0.95)
            p.b = 0.1
        else
            -- Electric cyan / neon diamond burst
            p.r = 0.1
            p.g = love.math.random(0.75, 1.0)
            p.b = 1.0
        end
    end
end

function Particles.spawnDeathBurst(px, py)
    -- Vector shard explosion when player loses a life
    for _ = 1, 20 do
        local p = allocParticle()
        p.active = true
        p.x = px
        p.y = py
        local angle = love.math.random() * math.pi * 2
        local speed = love.math.random(60, 190)
        p.vx = math.cos(angle) * speed
        p.vy = math.sin(angle) * speed
        p.life = love.math.random(0.6, 1.1)
        p.maxLife = p.life
        p.size = love.math.random(3.0, 5.5)
        p.rot = love.math.random() * math.pi * 2
        p.vRot = (love.math.random() - 0.5) * 12
        p.shape = 2

        -- Vibrant cyan / magenta / white vector fragments
        local roll = love.math.random(1, 3)
        if roll == 1 then
            p.r, p.g, p.b = 0.0, 0.95, 1.0
        elseif roll == 2 then
            p.r, p.g, p.b = 1.0, 0.2, 0.7
        else
            p.r, p.g, p.b = 1.0, 1.0, 1.0
        end
    end
end

function Particles.update(dt)
    for i = 1, MAX_PARTICLES do
        local p = pool[i]
        if p.active then
            p.life = p.life - dt
            if p.life <= 0 then
                p.active = false
            else
                p.x = p.x + p.vx * dt
                p.y = p.y + p.vy * dt
                -- Drag/friction
                p.vx = p.vx * (1 - 2.5 * dt)
                p.vy = p.vy * (1 - 2.5 * dt)

                if p.shape == 2 then
                    p.rot = p.rot + p.vRot * dt
                end
            end
        end
    end
end

local SHARD_DIAMOND = {0, 0, 0, 0, 0, 0, 0, 0}

function Particles.draw()
    love.graphics.setBlendMode("add")

    for i = 1, MAX_PARTICLES do
        local p = pool[i]
        if p.active then
            local alpha = math.max(0, p.life / p.maxLife)
            love.graphics.setColor(p.r, p.g, p.b, alpha)

            if p.shape == 1 then
                -- Glowing spark point / circle
                love.graphics.circle("fill", p.x, p.y, p.size * (0.6 + 0.4 * alpha))
            elseif p.shape == 2 then
                -- Tumbling vector diamond shard
                local s = p.size * alpha
                love.graphics.push()
                love.graphics.translate(p.x, p.y)
                love.graphics.rotate(p.rot)
                SHARD_DIAMOND[1] = 0;   SHARD_DIAMOND[2] = -s
                SHARD_DIAMOND[3] = s;   SHARD_DIAMOND[4] = 0
                SHARD_DIAMOND[5] = 0;   SHARD_DIAMOND[6] = s
                SHARD_DIAMOND[7] = -s;  SHARD_DIAMOND[8] = 0
                love.graphics.polygon("fill", SHARD_DIAMOND)
                love.graphics.pop()
            end
        end
    end

    love.graphics.setBlendMode("alpha")
end

return Particles
