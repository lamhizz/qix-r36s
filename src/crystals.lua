-- ==============================================================================
-- QIX - In-Field Power Crystals (Level 4+ Progression Mechanic)
-- Floating energy gems spawned inside unclaimed territory that award tactical boosts
-- when trapped and enclosed inside player captured polygons.
-- ==============================================================================

local Crystals = {}
Crystals.__index = Crystals

local TYPES = {
    { id = "FREEZE", label = "CHRONO FREEZE", color = { 0.1, 0.9, 1.0 }, icon = "❄" },
    { id = "BONUS",  label = "+5000 BONUS",    color = { 1.0, 0.85, 0.1 }, icon = "★" },
    { id = "SHIELD", label = "SHIELD MATRIX",  color = { 0.2, 1.0, 0.4 }, icon = "🛡" }
}

function Crystals.spawnForLevel(grid, levelNum)
    local list = {}
    if levelNum < 4 then
        return list -- Progression: introduced at Level 4+
    end

    local count = (levelNum >= 5) and 2 or 1
    local w, h = grid.width, grid.height

    for i = 1, count do
        local typeInfo = TYPES[((i + levelNum) % #TYPES) + 1]
        local placed = false

        -- Find safe empty position away from edges
        for attempt = 1, 30 do
            local rx = math.random(math.floor(w * 0.2), math.floor(w * 0.8))
            local ry = math.random(math.floor(h * 0.2), math.floor(h * 0.8))
            if grid.cells[ry * w + rx] == grid.CELL_EMPTY then
                table.insert(list, {
                    x = rx,
                    y = ry,
                    type = typeInfo.id,
                    label = typeInfo.label,
                    color = typeInfo.color,
                    icon = typeInfo.icon,
                    animTimer = math.random() * 6.28,
                    collected = false
                })
                placed = true
                break
            end
        end
    end

    return list
end

function Crystals.updateList(crystals, dt)
    for _, c in ipairs(crystals) do
        c.animTimer = c.animTimer + dt * 3
    end
end

function Crystals.checkCollection(crystals, grid)
    local collected = {}
    for i = #crystals, 1, -1 do
        local c = crystals[i]
        local idx = c.y * grid.width + c.x
        if grid.cells[idx] ~= grid.CELL_EMPTY then
            table.insert(collected, c)
            table.remove(crystals, i)
        end
    end
    return collected
end

local freezeImg = nil
local batteryImg = nil

local function getImages()
    if freezeImg == nil then
        if love.filesystem.getInfo("assets/freeze.png") then
            local ok, img = pcall(love.graphics.newImage, "assets/freeze.png")
            freezeImg = ok and img or false
        else
            freezeImg = false
        end
    end
    if batteryImg == nil then
        if love.filesystem.getInfo("assets/battery.png") then
            local ok, img = pcall(love.graphics.newImage, "assets/battery.png")
            batteryImg = ok and img or false
        else
            batteryImg = false
        end
    end
    return (freezeImg or nil), (batteryImg or nil)
end

function Crystals.drawList(crystals, offsetX, offsetY, scaleX, scaleY)
    local fImg, bImg = getImages()

    for _, c in ipairs(crystals) do
        local cx = offsetX + c.x * scaleX
        local cy = offsetY + c.y * scaleY
        local pulse = 0.85 + 0.15 * math.sin(c.animTimer)
        local bob = math.sin(c.animTimer * 1.6) * 2.2 -- subtle floating bob
        local drawY = cy + bob

        if c.type == "FREEZE" and fImg then
            -- Soft cyan aura glow
            love.graphics.setColor(0.1, 0.85, 1.0, 0.32 * pulse)
            love.graphics.circle("fill", cx, drawY, 20 * pulse)

            -- Freeze crystal PNG icon (scaled to ~28px for clear visibility)
            local s = (28 / 140) * pulse
            love.graphics.setColor(1, 1, 1, 0.98)
            love.graphics.draw(fImg, cx, drawY, 0, s, s, 70, 70)
        elseif c.type == "BONUS" and bImg then
            -- Soft golden battery aura glow
            love.graphics.setColor(1.0, 0.85, 0.1, 0.32 * pulse)
            love.graphics.circle("fill", cx, drawY, 20 * pulse)

            -- Battery PNG icon (scaled to ~28px for clear visibility)
            local s = (28 / 140) * pulse
            love.graphics.setColor(1, 1, 1, 0.98)
            love.graphics.draw(bImg, cx, drawY, 0, s, s, 70, 70)
        else
            -- Shield Matrix / fallback polygon
            local size = 11 * pulse

            -- Outer neon glow ring
            love.graphics.setColor(c.color[1], c.color[2], c.color[3], 0.35)
            love.graphics.circle("fill", cx, drawY, size * 1.8)

            -- Diamond crystal polygon
            love.graphics.setColor(c.color[1], c.color[2], c.color[3], 0.95)
            love.graphics.polygon("fill",
                cx, drawY - size,
                cx + size, drawY,
                cx, drawY + size,
                cx - size, drawY
            )

            -- White specular core
            love.graphics.setColor(1, 1, 1, 0.9)
            love.graphics.circle("fill", cx, drawY, size * 0.35)
        end
    end
end

return Crystals

