-- ==============================================================================
-- QIX - In-Field Power Crystals (Level 4+ Progression Mechanic)
-- Floating energy gems spawned inside unclaimed territory that award tactical boosts
-- when trapped and enclosed inside player captured polygons.
-- ==============================================================================

local Crystals = {}
Crystals.__index = Crystals

local TYPES = {
    { id = "FREEZE", label = "CHRONO FREEZE", color = { 0.1, 0.9, 1.0 }, icon = "[FREEZE]" },
    { id = "BONUS",  label = "+5000 BONUS",    color = { 1.0, 0.85, 0.1 }, icon = "[BONUS]" },
    { id = "SHIELD", label = "SHIELD MATRIX",  color = { 0.2, 1.0, 0.4 }, icon = "[SHIELD]" }
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
    if not crystals or #crystals == 0 then return end
    pcall(function()
        for _, c in ipairs(crystals) do
            local cx = offsetX + c.x * scaleX
            local cy = offsetY + c.y * scaleY
            local pulse = 0.85 + 0.15 * math.sin(c.animTimer or 0)
            local bob = math.sin((c.animTimer or 0) * 1.6) * 2.2 -- subtle floating bob
            local drawY = cy + bob

            -- Clamping within safe viewport margins
            cx = math.max(146, math.min(620, cx))
            drawY = math.max(34, math.min(468, drawY))
            local size = 11 * pulse

            -- Outer neon aura glow (safe filled circle / triangle fan)
            local col = c.color or { 0.2, 0.8, 1.0 }
            love.graphics.setColor(col[1], col[2], col[3], 0.32)
            love.graphics.circle("fill", cx, drawY, size * 1.8)

            if c.type == "FREEZE" then
                -- Chrono Freeze: Rotating dual cyan ice diamonds
                love.graphics.push()
                love.graphics.translate(cx, drawY)
                love.graphics.rotate((c.animTimer or 0) * 0.9)
                local half = size * 0.75
                love.graphics.setColor(0.1, 0.9, 1.0, 0.95)
                love.graphics.rectangle("fill", -half, -half, half * 2, half * 2)

                love.graphics.rotate(-(c.animTimer or 0) * 1.8)
                love.graphics.setColor(1.0, 1.0, 1.0, 0.95)
                local innerHalf = half * 0.42
                love.graphics.rectangle("fill", -innerHalf, -innerHalf, innerHalf * 2, innerHalf * 2)
                love.graphics.pop()
            elseif c.type == "BONUS" then
                -- Golden Battery: Rotating 8-pointed star crystal
                love.graphics.push()
                love.graphics.translate(cx, drawY)
                love.graphics.rotate((c.animTimer or 0) * 1.2)
                local wLong = size * 1.15
                local wShort = size * 0.38
                love.graphics.setColor(1.0, 0.85, 0.1, 0.95)
                love.graphics.rectangle("fill", -wLong, -wShort, wLong * 2, wShort * 2)
                love.graphics.rectangle("fill", -wShort, -wLong, wShort * 2, wLong * 2)

                love.graphics.setColor(1.0, 1.0, 0.7, 0.95)
                love.graphics.circle("fill", 0, 0, size * 0.35)
                love.graphics.pop()
            else
                -- Shield Matrix: Emerald rotating diamond with white specular core
                love.graphics.push()
                love.graphics.translate(cx, drawY)
                love.graphics.rotate(0.785398 + (c.animTimer or 0) * 0.6)
                local half = size * 0.707
                love.graphics.setColor(0.2, 1.0, 0.4, 0.95)
                love.graphics.rectangle("fill", -half, -half, half * 2, half * 2)
                love.graphics.pop()

                love.graphics.setColor(1, 1, 1, 0.9)
                love.graphics.circle("fill", cx, drawY, size * 0.35)
            end
        end
        love.graphics.setLineWidth(1)
    end)
end

return Crystals

