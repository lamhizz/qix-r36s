-- Qix Chaotic Vector Helix Entity
local Qix = {}
Qix.__index = Qix

local function ccw(A, B, C)
    return (C.y - A.y) * (B.x - A.x) > (B.y - A.y) * (C.x - A.x)
end

local function lineIntersect(p1, p2, p3, p4)
    return (ccw(p1, p3, p4) ~= ccw(p2, p3, p4)) and (ccw(p1, p2, p3) ~= ccw(p1, p2, p4))
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

    local len = 25
    self.p1 = { x = startX or (grid.width / 2), y = startY or (grid.height / 2) }
    self.p2 = { x = self.p1.x + len, y = self.p1.y }

    local speed = 1.8 * self.speedMultiplier
    local a1 = love.math.random() * math.pi * 2
    local a2 = love.math.random() * math.pi * 2
    self.v1 = { x = math.cos(a1) * speed, y = math.sin(a1) * speed }
    self.v2 = { x = math.cos(a2) * speed, y = math.sin(a2) * speed }

    self.minLen = 20
    self.maxLen = 60
    self.trailLength = 22
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
    self.baseHue = (self.baseHue + dt * 0.15) % 1.0
    self.tumbleTimer = self.tumbleTimer + 1

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

    -- Prediction & collision with borders
    local next1 = { x = self.p1.x + self.v1.x, y = self.p1.y + self.v1.y }
    local next2 = { x = self.p2.x + self.v2.x, y = self.p2.y + self.v2.y }

    if self:isBlocked(next1.x, next1.y) or self:isBlocked(next1.x, self.p1.y) then
        self.v1.x = -self.v1.x + (love.math.random() - 0.5) * 0.4
    end
    if self:isBlocked(next1.x, next1.y) or self:isBlocked(self.p1.x, next1.y) then
        self.v1.y = -self.v1.y + (love.math.random() - 0.5) * 0.4
    end

    if self:isBlocked(next2.x, next2.y) or self:isBlocked(next2.x, self.p2.y) then
        self.v2.x = -self.v2.x + (love.math.random() - 0.5) * 0.4
    end
    if self:isBlocked(next2.x, next2.y) or self:isBlocked(self.p2.x, next2.y) then
        self.v2.y = -self.v2.y + (love.math.random() - 0.5) * 0.4
    end

    -- Clamp speeds
    local maxSpd = 2.6 * self.speedMultiplier
    local minSpd = 1.0 * self.speedMultiplier
    local cur1 = math.sqrt(self.v1.x^2 + self.v1.y^2)
    local cur2 = math.sqrt(self.v2.x^2 + self.v2.y^2)

    if cur1 > maxSpd then self.v1.x = (self.v1.x/cur1)*maxSpd; self.v1.y = (self.v1.y/cur1)*maxSpd end
    if cur1 < minSpd then self.v1.x = (self.v1.x/cur1)*minSpd; self.v1.y = (self.v1.y/cur1)*minSpd end
    if cur2 > maxSpd then self.v2.x = (self.v2.x/cur2)*maxSpd; self.v2.y = (self.v2.y/cur2)*maxSpd end
    if cur2 < minSpd then self.v2.x = (self.v2.x/cur2)*minSpd; self.v2.y = (self.v2.y/cur2)*minSpd end

    if not self:isBlocked(self.p1.x + self.v1.x, self.p1.y + self.v1.y) then
        self.p1.x = self.p1.x + self.v1.x
        self.p1.y = self.p1.y + self.v1.y
    end
    if not self:isBlocked(self.p2.x + self.v2.x, self.p2.y + self.v2.y) then
        self.p2.x = self.p2.x + self.v2.x
        self.p2.y = self.p2.y + self.v2.y
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

    -- Update ribbon trail
    table.insert(self.trail, 1, {
        p1 = { x = self.p1.x, y = self.p1.y },
        p2 = { x = self.p2.x, y = self.p2.y }
    })
    while #self.trail > self.trailLength do
        table.remove(self.trail)
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
    love.graphics.setLineWidth(2.0 * scaleX)

    for i = n, 1, -1 do
        local seg = self.trail[i]
        local alpha = 0.2 + (0.8 * (n - i + 1) / n)
        local hue = (self.baseHue + (i / n) * 0.8) % 1.0
        local r, g, b = hsvToRgb(hue, 0.9, 1.0)

        love.graphics.setColor(r, g, b, alpha)
        love.graphics.line(
            offsetX + seg.p1.x * scaleX, offsetY + seg.p1.y * scaleY,
            offsetX + seg.p2.x * scaleX, offsetY + seg.p2.y * scaleY
        )
    end
    love.graphics.setBlendMode("alpha")
end

return Qix
