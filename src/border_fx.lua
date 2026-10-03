-- ==============================================================================
-- QIX - Animated Viewport & Gameboard Border Loader System
-- Recreates the high-energy neon shimmer border loader with dual corner beams,
-- multi-color cycling gradient, specular glint sweep, and ambient neon aura.
-- ==============================================================================

local BorderFX = {}

BorderFX.progress = 0
BorderFX.isPaused = false
BorderFX.pauseTimer = 0
BorderFX.shimmerPhase = 0
BorderFX.glintPhase = 0

-- Multi-color neon palette from reference:
-- #00f5d4 (Cyan), #00bbf9 (Sky Blue), #6366f1 (Indigo), #f72585 (Hot Pink), #ffbe0b (Amber)
local COLOR_STOPS = {
    { 0.00 / 1.0, 0.000, 0.961, 0.831 }, -- #00f5d4
    { 0.20 / 1.0, 0.000, 0.733, 0.976 }, -- #00bbf9
    { 0.40 / 1.0, 0.388, 0.400, 0.945 }, -- #6366f1
    { 0.65 / 1.0, 0.969, 0.145, 0.522 }, -- #f72585
    { 0.85 / 1.0, 1.000, 0.745, 0.043 }, -- #ffbe0b
    { 1.00 / 1.0, 0.000, 0.961, 0.831 }  -- #00f5d4 (loop wrap)
}

local function sampleGradient(t)
    t = (t % 1.0 + 1.0) % 1.0
    for i = 1, #COLOR_STOPS - 1 do
        local s1 = COLOR_STOPS[i]
        local s2 = COLOR_STOPS[i + 1]
        if t >= s1[1] and t <= s2[1] then
            local span = s2[1] - s1[1]
            local f = (span > 0.0001) and ((t - s1[1]) / span) or 0
            local r = s1[2] + (s2[2] - s1[2]) * f
            local g = s1[3] + (s2[3] - s1[3]) * f
            local b = s1[4] + (s2[4] - s1[4]) * f
            return r, g, b
        end
    end
    return COLOR_STOPS[1][2], COLOR_STOPS[1][3], COLOR_STOPS[1][4]
end

function BorderFX.init()
    BorderFX.progress = 0
    BorderFX.isPaused = false
    BorderFX.pauseTimer = 0
    BorderFX.shimmerPhase = 0
    BorderFX.glintPhase = 0
end

function BorderFX.update(dt)
    -- 1. Shimmer movement phase (2.2s period linear infinite)
    BorderFX.shimmerPhase = (BorderFX.shimmerPhase + dt * (1.0 / 2.2)) % 1.0

    -- 2. Glint sweep phase (1.4s period infinite)
    BorderFX.glintPhase = (BorderFX.glintPhase + dt * (1.0 / 1.4)) % 1.0

    -- 3. Corner beam loading progression (matches reference progression curves)
    if not BorderFX.isPaused then
        local rate = 0
        if BorderFX.progress < 0.4 then
            rate = 0.42 -- 0.007 * 60
        elseif BorderFX.progress < 0.8 then
            rate = 0.30 -- 0.005 * 60
        elseif BorderFX.progress < 1.0 then
            rate = 0.24 -- 0.004 * 60
        end

        BorderFX.progress = BorderFX.progress + rate * dt

        if BorderFX.progress >= 1.0 then
            BorderFX.progress = 1.0
            BorderFX.isPaused = true
            BorderFX.pauseTimer = 0.90 -- 900ms pause at 100% completion before looping
        end
    else
        BorderFX.pauseTimer = BorderFX.pauseTimer - dt
        if BorderFX.pauseTimer <= 0 then
            BorderFX.progress = 0
            BorderFX.isPaused = false
        end
    end
end

-- Draw a single gradient line beam with multiple sub-segments for smooth gradient flow & glint sweep
local function drawSegmentedBeam(x1, y1, x2, y2, thickness, shimmerPhase, glintPhase, isReverse, segments)
    local segs = segments or 16
    local dx = (x2 - x1)
    local dy = (y2 - y1)
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.5 then return end

    -- Aura Glow Pass (Thicker, semi-transparent neon glow)
    love.graphics.setBlendMode("add")
    love.graphics.setLineWidth(thickness + 5)
    love.graphics.setColor(0.00, 0.96, 0.83, 0.22) -- Cyan aura
    love.graphics.line(x1, y1, x2, y2)
    love.graphics.setLineWidth(thickness + 10)
    love.graphics.setColor(0.97, 0.15, 0.52, 0.15) -- Hot pink accent aura
    love.graphics.line(x1, y1, x2, y2)

    -- Core Gradient Shimmer Pass
    love.graphics.setLineWidth(thickness)
    local prevX, prevY = x1, y1
    for i = 1, segs do
        local t0 = (i - 1) / segs
        local t1 = i / segs
        local curX = x1 + dx * t1
        local curY = y1 + dy * t1

        local gradT = isReverse and (1.0 - t0 - shimmerPhase) or (t0 + shimmerPhase)
        local r, g, b = sampleGradient(gradT)
        love.graphics.setColor(r, g, b, 0.95)
        love.graphics.line(prevX, prevY, curX, curY)
        prevX, prevY = curX, curY
    end

    -- High-Velocity Glint Specular Sweep (White highlight sweeping across the beam)
    -- glint sweeps from -0.5 to 1.5 of the beam length
    local glintPos = isReverse and (1.2 - BorderFX.glintPhase * 1.4) or (-0.2 + BorderFX.glintPhase * 1.4)
    local glintSpan = 0.22

    for i = 1, segs do
        local t = (i - 0.5) / segs
        local dist = math.abs(t - glintPos)
        if dist < glintSpan then
            local glintAlpha = (1.0 - (dist / glintSpan)) * 0.92
            local sx1 = x1 + dx * ((i - 1) / segs)
            local sy1 = y1 + dy * ((i - 1) / segs)
            local sx2 = x1 + dx * (i / segs)
            local sy2 = y1 + dy * (i / segs)
            love.graphics.setColor(1.0, 1.0, 1.0, glintAlpha)
            love.graphics.line(sx1, sy1, sx2, sy2)
        end
    end

    -- Tip Particle Spark (Bright energy bead at moving head of beam)
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.circle("fill", x2, y2, thickness * 0.9)
    local tr, tg, tb = sampleGradient(shimmerPhase)
    love.graphics.setColor(tr, tg, tb, 0.6)
    love.graphics.circle("fill", x2, y2, thickness * 1.8)

    love.graphics.setBlendMode("alpha")
end

function BorderFX.draw(bx, by, bw, bh)
    local pct = BorderFX.progress
    local thickness = 3.0

    -- Perimeter Coordinates
    local left = bx
    local right = bx + bw
    local top = by
    local bottom = by + bh

    -- Base Track: Subtle dark neon guide track along perimeter
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.02, 0.16, 0.22, 0.45)
    love.graphics.rectangle("line", left, top, bw, bh)

    -- Active Corner Beams:
    -- 1. Bottom-Left Vertical (bl-vertical): Shoots UP from (left, bottom) toward (left, top)
    local blV_h = bh * pct
    if blV_h > 0 then
        drawSegmentedBeam(left, bottom, left, bottom - blV_h, thickness, BorderFX.shimmerPhase, BorderFX.glintPhase, false, 18)
    end

    -- 2. Bottom-Left Horizontal (bl-horizontal): Shoots RIGHT from (left, bottom) toward (right, bottom)
    local blH_w = bw * pct
    if blH_w > 0 then
        drawSegmentedBeam(left, bottom, left + blH_w, bottom, thickness, BorderFX.shimmerPhase, BorderFX.glintPhase, false, 24)
    end

    -- 3. Top-Right Vertical (tr-vertical): Shoots DOWN from (right, top) toward (right, bottom)
    local trV_h = bh * pct
    if trV_h > 0 then
        drawSegmentedBeam(right, top, right, top + trV_h, thickness, BorderFX.shimmerPhase, BorderFX.glintPhase, true, 18)
    end

    -- 4. Top-Right Horizontal (tr-horizontal): Shoots LEFT from (right, top) toward (left, top)
    local trH_w = bw * pct
    if trH_w > 0 then
        drawSegmentedBeam(right, top, right - trH_w, top, thickness, BorderFX.shimmerPhase, BorderFX.glintPhase, true, 24)
    end
end

return BorderFX
