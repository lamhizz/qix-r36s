-- Qix Chaotic Vector Helix Entity
local Qix = {}
Qix.__index = Qix

local function ccw(Ax, Ay, Bx, By, Cx, Cy)
    return (Cy - Ay) * (Bx - Ax) > (By - Ay) * (Cx - Ax)
end

local function lineIntersect(p1, p2, p3, p4)
    local p1x, p1y = p1.x, p1.y
    local p2x, p2y = p2.x, p2.y
    local p3x, p3y = p3.x, p3.y
    local p4x, p4y = p4.x, p4.y
    return (ccw(p1x, p1y, p3x, p3y, p4x, p4y) ~= ccw(p2x, p2y, p3x, p3y, p4x, p4y))
       and (ccw(p1x, p1y, p2x, p2y, p3x, p3y) ~= ccw(p1x, p1y, p2x, p2y, p4x, p4y))
end

-- Convert HSV to RGB
local function hsvToRgb(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    elseif i == 5 then return v, p, q
    end
    return 1, 1, 1
end

function Qix.new(grid, startX, startY, speedMultiplier)
    local self = setmetatable({}, Qix)
    self.grid = grid
    self.speedMultiplier = speedMultiplier or 1.0

    local len = 18
    self.p1 = { x = startX or (grid.width / 2), y = startY or (grid.height / 2) }
    self.p2 = { x = self.p1.x + len, y = self.p1.y }

    local speed = 1.42 * self.speedMultiplier
    local a1 = love.math.random() * math.pi * 2
    local a2 = love.math.random() * math.pi * 2
    self.v1 = { x = math.cos(a1) * speed, y = math.sin(a1) * speed }
    self.v2 = { x = math.cos(a2) * speed, y = math.sin(a2) * speed }

    self.minLen = 14
    self.maxLen = 38
    self.trailLength = 20
    self.trail = {}
    self.tumbleTimer = 0
    self.baseHue = love.math.random()

    return self
end

function Qix:isBlocked(x, y)
    local gx = math.floor(x + 0.5)
    local gy = math.floor(y + 0.5)
    if not self.grid:inBounds(gx, gy) then return true end
    local cell = self.grid:get(gx, gy)
    return cell == self.grid.CELL_BORDER or cell == self.grid.CELL_CLAIMED_SLOW or cell == self.grid.CELL_CLAIMED_FAST
end

function Qix:update(dt)
    -- Normalize movement step to 60 FPS standard
    -- Ensures identical speed on 60Hz (R36S) and 120Hz/ProMotion (Mac)
    local step = math.min(2.0, dt * 60)
    self.baseHue = (self.baseHue + dt * 0.15) % 1.0
    self.tumbleTimer = self.tumbleTimer + step

    -- Periodic slight steering perturbation
    if self.tumbleTimer > 12 then
        self.tumbleTimer = 0
        local dAngle1 = (love.math.random() - 0.5) * 0.6
        local dAngle2 = (love.math.random() - 0.5) * 0.6

        local spd1 = math.sqrt(self.v1.x^2 + self.v1.y^2)
        local spd2 = math.sqrt(self.v2.x^2 + self.v2.y^2)

        local a1 = math.atan2(self.v1.y, self.v1.x) + dAngle1
        local a2 = math.atan2(self.v2.y, self.v2.x) + dAngle2

        self.v1.x = math.cos(a1) * spd1
        self.v1.y = math.sin(a1) * spd1
        self.v2.x = math.cos(a2) * spd2
        self.v2.y = math.sin(a2) * spd2
    end

    -- Prediction & collision with borders (zero allocations)
    local next1X = self.p1.x + self.v1.x * step
    local next1Y = self.p1.y + self.v1.y * step
    local next2X = self.p2.x + self.v2.x * step
    local next2Y = self.p2.y + self.v2.y * step

    if self:isBlocked(next1X, next1Y) or self:isBlocked(next1X, self.p1.y) then
        self.v1.x = -self.v1.x + (love.math.random() - 0.5) * 0.4
    end
    if self:isBlocked(next1X, next1Y) or self:isBlocked(self.p1.x, next1Y) then
        self.v1.y = -self.v1.y + (love.math.random() - 0.5) * 0.4
    end

    if self:isBlocked(next2X, next2Y) or self:isBlocked(next2X, self.p2.y) then
        self.v2.x = -self.v2.x + (love.math.random() - 0.5) * 0.4
    end
    if self:isBlocked(next2X, next2Y) or self:isBlocked(self.p2.x, next2Y) then
        self.v2.y = -self.v2.y + (love.math.random() - 0.5) * 0.4
    end

    -- Clamp speeds (tactical zoomed-out pacing)
    local maxSpd = 1.85 * self.speedMultiplier
    local minSpd = 0.65 * self.speedMultiplier
    local cur1 = math.sqrt(self.v1.x^2 + self.v1.y^2)
    local cur2 = math.sqrt(self.v2.x^2 + self.v2.y^2)

    if cur1 > maxSpd then self.v1.x = (self.v1.x/cur1)*maxSpd; self.v1.y = (self.v1.y/cur1)*maxSpd end
    if cur1 < minSpd then self.v1.x = (self.v1.x/cur1)*minSpd; self.v1.y = (self.v1.y/cur1)*minSpd end
    if cur2 > maxSpd then self.v2.x = (self.v2.x/cur2)*maxSpd; self.v2.y = (self.v2.y/cur2)*maxSpd end
    if cur2 < minSpd then self.v2.x = (self.v2.x/cur2)*minSpd; self.v2.y = (self.v2.y/cur2)*minSpd end

    if not self:isBlocked(self.p1.x + self.v1.x * step, self.p1.y + self.v1.y * step) then
        self.p1.x = self.p1.x + self.v1.x * step
        self.p1.y = self.p1.y + self.v1.y * step
    end
    if not self:isBlocked(self.p2.x + self.v2.x * step, self.p2.y + self.v2.y * step) then
        self.p2.x = self.p2.x + self.v2.x * step
        self.p2.y = self.p2.y + self.v2.y * step
    end

    -- Distance tether
    local dx = self.p2.x - self.p1.x
    local dy = self.p2.y - self.p1.y
    local dist = math.sqrt(dx^2 + dy^2)

    if dist > self.maxLen then
        local diff = (dist - self.maxLen) * 0.5
        local nx, ny = dx / dist, dy / dist
        self.p1.x = self.p1.x + nx * diff
        self.p1.y = self.p1.y + ny * diff
        self.p2.x = self.p2.x - nx * diff
        self.p2.y = self.p2.y - ny * diff
    elseif dist < self.minLen and dist > 0.001 then
        local diff = (self.minLen - dist) * 0.5
        local nx, ny = dx / dist, dy / dist
        self.p1.x = self.p1.x - nx * diff
        self.p1.y = self.p1.y - ny * diff
        self.p2.x = self.p2.x + nx * diff
        self.p2.y = self.p2.y + ny * diff
    end

    -- Update ribbon trail (recycle segments once full, zero allocations)
    self.trailTimer = (self.trailTimer or 0) + step
    if self.trailTimer >= 1.0 then
        self.trailTimer = self.trailTimer - 1.0
        local seg
        if #self.trail >= self.trailLength then
            seg = table.remove(self.trail)
            seg.p1.x = self.p1.x
            seg.p1.y = self.p1.y
            seg.p2.x = self.p2.x
            seg.p2.y = self.p2.y
        else
            seg = {
                p1 = { x = self.p1.x, y = self.p1.y },
                p2 = { x = self.p2.x, y = self.p2.y }
            }
        end
        table.insert(self.trail, 1, seg)
    end
end

-- Check if Qix collides with active player stix line
function Qix:checkStixCollision(stixPath)
    if not stixPath or #stixPath < 2 then return false end

    for _, seg in ipairs(self.trail) do
        for i = 1, #stixPath - 1 do
            if lineIntersect(seg.p1, seg.p2, stixPath[i], stixPath[i + 1]) then
                return true
            end
        end
    end
    return false
end

function Qix:draw(offsetX, offsetY, scaleX, scaleY)
    local n = #self.trail
    if n < 1 then return end

    love.graphics.setBlendMode("add")

    -- Pass 1: Wide radiant outer glow / bloom
    love.graphics.setLineWidth(3.4 * scaleX)
    for i = n, 1, -1 do
        local seg = self.trail[i]
        local alpha = (0.15 + (0.45 * (n - i + 1) / n)) * 0.4
        local hue = (self.baseHue + (i / n) * 0.8) % 1.0
        local r, g, b = hsvToRgb(hue, 0.95, 1.0)

        love.graphics.setColor(r, g, b, alpha)
        love.graphics.line(
            offsetX + seg.p1.x * scaleX, offsetY + seg.p1.y * scaleY,
            offsetX + seg.p2.x * scaleX, offsetY + seg.p2.y * scaleY
        )
    end

    -- Pass 2: Vibrant primary vector beam
    love.graphics.setLineWidth(1.6 * scaleX)
    for i = n, 1, -1 do
        local seg = self.trail[i]
        local alpha = 0.25 + (0.75 * (n - i + 1) / n)
        local hue = (self.baseHue + (i / n) * 0.8) % 1.0
        local r, g, b = hsvToRgb(hue, 0.85, 1.0)

        love.graphics.setColor(r, g, b, alpha)
        love.graphics.line(
            offsetX + seg.p1.x * scaleX, offsetY + seg.p1.y * scaleY,
            offsetX + seg.p2.x * scaleX, offsetY + seg.p2.y * scaleY
        )
    end

    -- Pass 3: White-hot phosphor core on leading segments
    local leadCount = math.min(n, 7)
    love.graphics.setLineWidth(0.9 * scaleX)
    for i = 1, leadCount do
        local seg = self.trail[i]
        local alpha = 0.9 * (1.0 - (i - 1) / leadCount)
        love.graphics.setColor(1.0, 1.0, 1.0, alpha)
        love.graphics.line(
            offsetX + seg.p1.x * scaleX, offsetY + seg.p1.y * scaleY,
            offsetX + seg.p2.x * scaleX, offsetY + seg.p2.y * scaleY
        )
    end

    -- Glowing energy nodes at leading tips (p1, p2)
    local seg1 = self.trail[1]
    if seg1 then
        local x1 = offsetX + seg1.p1.x * scaleX
        local y1 = offsetY + seg1.p1.y * scaleY
        local x2 = offsetX + seg1.p2.x * scaleX
        local y2 = offsetY + seg1.p2.y * scaleY
        local pulse = 0.75 + 0.25 * math.sin(self.baseHue * 10)

        love.graphics.setColor(1.0, 0.9, 0.2, 0.55 * pulse)
        love.graphics.circle("fill", x1, y1, 3.2 * scaleX)
        love.graphics.circle("fill", x2, y2, 3.2 * scaleX)
        love.graphics.setColor(1, 1, 1, 0.95)
        love.graphics.circle("fill", x1, y1, 1.5 * scaleX)
        love.graphics.circle("fill", x2, y2, 1.5 * scaleX)
    end

    love.graphics.setBlendMode("alpha")
end

return Qix
