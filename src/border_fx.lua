-- ==============================================================================
-- QIX - Minimal Animated Viewport Border (Level Cut Progress Bar)
-- Functions as the clean, minimal Qix Level Cut Progress Bar around the gameboard.
-- Features animated multi-color shimmer gradient and subtle glint sweep without heavy glow.
-- Only displayed during active gameplay; hidden in menus and on level complete screen.
-- ==============================================================================

local BorderFX = {}

BorderFX.progress = 0
BorderFX.targetProgress = 0
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
    BorderFX.targetProgress = 0
    BorderFX.shimmerPhase = 0
    BorderFX.glintPhase = 0
end

function BorderFX.reset()
    BorderFX.progress = 0
    BorderFX.targetProgress = 0
end

function BorderFX.setProgress(ratio, immediate)
    local target = math.max(0.0, math.min(1.0, ratio or 0))
    BorderFX.targetProgress = target
    if immediate then
        BorderFX.progress = target
    end
end

function BorderFX.update(dt, currentClaimed, targetGoal)
    -- 1. Continuous Multi-Color Shimmer Flow (2.2s period linear infinite)
    BorderFX.shimmerPhase = (BorderFX.shimmerPhase + dt * (1.0 / 2.2)) % 1.0

    -- 2. Continuous High-Velocity Specular Glint Sweep (1.4s period infinite)
    BorderFX.glintPhase = (BorderFX.glintPhase + dt * (1.0 / 1.4)) % 1.0

    if currentClaimed and targetGoal and targetGoal > 0 then
        BorderFX.targetProgress = math.max(0.0, math.min(1.0, currentClaimed / targetGoal))
    end

    -- Smoothly interpolate progress toward targetProgress
    local diff = BorderFX.targetProgress - BorderFX.progress
    if math.abs(diff) > 0.0005 then
        local speed = math.max(0.65, math.abs(diff) * 5.0)
        if diff > 0 then
            BorderFX.progress = math.min(BorderFX.targetProgress, BorderFX.progress + speed * dt)
        else
            BorderFX.progress = math.max(BorderFX.targetProgress, BorderFX.progress - speed * dt)
        end
    else
        BorderFX.progress = BorderFX.targetProgress
    end
end

-- Draw clean, minimal segmented beam with shimmer gradient & subtle specular glint
local function drawSegmentedBeam(x1, y1, x2, y2, thickness, shimmerPhase, glintPhase, isReverse, segments)
    local segs = segments or 16
    local dx = (x2 - x1)
    local dy = (y2 - y1)
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.5 then return end

    -- Core Gradient Shimmer Pass (Minimal, crisp line)
    love.graphics.setLineWidth(thickness)
    local prevX, prevY = x1, y1
    for i = 1, segs do
        local t0 = (i - 1) / segs
        local t1 = i / segs
        local curX = x1 + dx * t1
        local curY = y1 + dy * t1

        local gradT = isReverse and (1.0 - t0 - shimmerPhase) or (t0 + shimmerPhase)
        local r, g, b = sampleGradient(gradT)
        love.graphics.setColor(r, g, b, 1.0)
        love.graphics.line(prevX, prevY, curX, curY)
        prevX, prevY = curX, curY
    end

    -- Subtle Specular Glint Sweep (Clean white gleam)
    local glintPos = isReverse and (1.2 - glintPhase * 1.4) or (-0.2 + glintPhase * 1.4)
    local glintSpan = 0.20

    for i = 1, segs do
        local t = (i - 0.5) / segs
        local dist = math.abs(t - glintPos)
        if dist < glintSpan then
            local glintAlpha = (1.0 - (dist / glintSpan)) * 0.85
            local sx1 = x1 + dx * ((i - 1) / segs)
            local sy1 = y1 + dy * ((i - 1) / segs)
            local sx2 = x1 + dx * (i / segs)
            local sy2 = y1 + dy * (i / segs)
            love.graphics.setColor(1.0, 1.0, 1.0, glintAlpha)
            love.graphics.line(sx1, sy1, sx2, sy2)
        end
    end

    -- Small crisp tip point at moving head
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.circle("fill", x2, y2, thickness * 0.75)
end

function BorderFX.draw(bx, by, bw, bh)
    local pct = BorderFX.progress
    local thickness = 2.0
    local inset = 2 -- Inset slightly to prevent screen bezel clipping on R36S

    -- Perimeter Coordinates
    local left = bx + inset
    local right = bx + bw - inset
    local top = by + inset
    local bottom = by + bh - inset
    local effW = right - left
    local effH = bottom - top

    -- Base Track: Minimal subtle guide track showing the unfilled boundary
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.10, 0.16, 0.24, 0.40)
    love.graphics.rectangle("line", left, top, effW, effH)

    if pct <= 0.0001 then return end

    -- Active Corner Beams (Acting as Level Cut Progress Bar):
    -- 1. Bottom-Left Vertical (bl-vertical): Shoots UP from (left, bottom) toward (left, top)
    local blV_h = effH * pct
    if blV_h > 0.5 then
        drawSegmentedBeam(left, bottom, left, bottom - blV_h, thickness, BorderFX.shimmerPhase, BorderFX.glintPhase, false, 16)
    end

    -- 2. Bottom-Left Horizontal (bl-horizontal): Shoots RIGHT from (left, bottom) toward (right, bottom)
    local blH_w = effW * pct
    if blH_w > 0.5 then
        drawSegmentedBeam(left, bottom, left + blH_w, bottom, thickness, BorderFX.shimmerPhase, BorderFX.glintPhase, false, 20)
    end

    -- 3. Top-Right Vertical (tr-vertical): Shoots DOWN from (right, top) toward (right, bottom)
    local trV_h = effH * pct
    if trV_h > 0.5 then
        drawSegmentedBeam(right, top, right, top + trV_h, thickness, BorderFX.shimmerPhase, BorderFX.glintPhase, true, 16)
    end

    -- 4. Top-Right Horizontal (tr-horizontal): Shoots LEFT from (right, top) toward (left, top)
    local trH_w = effW * pct
    if trH_w > 0.5 then
        drawSegmentedBeam(right, top, right - trH_w, top, thickness, BorderFX.shimmerPhase, BorderFX.glintPhase, true, 20)
    end
end

return BorderFX
