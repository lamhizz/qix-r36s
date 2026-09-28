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

function Crystals.drawList(crystals, offsetX, offsetY, scaleX, scaleY)
    for _, c in ipairs(crystals) do
        local cx = offsetX + c.x * scaleX
        local cy = offsetY + c.y * scaleY
        local pulse = 0.8 + 0.2 * math.sin(c.animTimer)
        local size = 7 * pulse

        -- Outer neon glow ring
        love.graphics.setColor(c.color[1], c.color[2], c.color[3], 0.35)
        love.graphics.circle("fill", cx, cy, size * 1.8)

        -- Diamond crystal polygon
        love.graphics.setColor(c.color[1], c.color[2], c.color[3], 0.95)
        love.graphics.polygon("fill",
            cx, cy - size,
            cx + size, cy,
            cx, cy + size,
            cx - size, cy
        )

        -- White specular core
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.circle("fill", cx, cy, size * 0.35)
    end
end

return Crystals
