-- Sparx Enemy Patrol Engine
local Sparx = {}
Sparx.__index = Sparx

Sparx.canvasNormal = nil
Sparx.canvasSuperCyan = nil
Sparx.canvasSuperMagenta = nil

local DIRS = {
    [0] = { dx = 1, dy = 0 },  -- 0: Right
    [1] = { dx = 0, dy = 1 },  -- 1: Down
    [2] = { dx = -1, dy = 0 }, -- 2: Left
    [3] = { dx = 0, dy = -1 }  -- 3: Up
}

local TURN_CW = { -1, 0, 1, 2 }
local TURN_CCW = { 1, 0, -1, 2 }

-- Draws an 8-pointed star using 8 pure convex triangles from center (0, 0)
-- Bypasses Love2D EarCut / Libtess2 polygon triangulation completely,
-- guaranteeing 100% hardware stability on RK3326 Mali-G31 GPU.
local function drawStarFan(tip, waist)
    local x1, y1 = 0, -tip
    local x2, y2 = waist, -waist
    local x3, y3 = tip, 0
    local x4, y4 = waist, waist
    local x5, y5 = 0, tip
    local x6, y6 = -waist, waist
    local x7, y7 = -tip, 0
    local x8, y8 = -waist, -waist

    love.graphics.polygon("fill", 0, 0, x1, y1, x2, y2)
    love.graphics.polygon("fill", 0, 0, x2, y2, x3, y3)
    love.graphics.polygon("fill", 0, 0, x3, y3, x4, y4)
    love.graphics.polygon("fill", 0, 0, x4, y4, x5, y5)
    love.graphics.polygon("fill", 0, 0, x5, y5, x6, y6)
    love.graphics.polygon("fill", 0, 0, x6, y6, x7, y7)
    love.graphics.polygon("fill", 0, 0, x7, y7, x8, y8)
    love.graphics.polygon("fill", 0, 0, x8, y8, x1, y1)
end

function Sparx.init()
    if Sparx.canvasNormal then return end
    if not love.graphics or not love.graphics.newCanvas then return end

    local function renderStarCanvas(isSuper, isCyan)
        local cv = love.graphics.newCanvas(64, 64)
        love.graphics.setCanvas(cv)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.push()
        love.graphics.translate(32, 32)

        -- 1. Outer Dark Silhouette
        love.graphics.setColor(0, 0, 0, 0.90)
        love.graphics.circle("fill", 0, 0, 16)

        -- 2. Ambient Corona Halo
        if isSuper then
            love.graphics.setColor(1.0, 0.15, 0.45, 0.55)
            love.graphics.circle("fill", 0, 0, 20)
        else
            love.graphics.setColor(1.0, 0.75, 0.0, 0.45)
            love.graphics.circle("fill", 0, 0, 18)
        end

        -- 3. Secondary 45-degree Cross Star
        love.graphics.push()
        love.graphics.rotate(0.785398)
        if isSuper then
            love.graphics.setColor(1.0, 0.2, 0.8, 0.9)
        else
            love.graphics.setColor(1.0, 0.45, 0.05, 0.95)
        end
        drawStarFan(14 * 1.4, 14 * 0.35)
        love.graphics.pop()

        -- 4. Primary Rotating Star (Black outline + vibrant core)
        love.graphics.setColor(0, 0, 0, 0.95)
        drawStarFan(16 * 1.65 + 1.8, 16 * 0.42 + 1.2)

        if isSuper then
            if isCyan then
                love.graphics.setColor(0.1, 0.95, 1.0, 1.0)
            else
                love.graphics.setColor(1.0, 0.15, 0.7, 1.0)
            end
        else
            love.graphics.setColor(1.0, 0.95, 0.15, 1.0)
        end
        drawStarFan(16 * 1.65, 16 * 0.42)

        -- 5. Hot White Specular Spark
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.circle("fill", 0, 0, 5)

        love.graphics.pop()
        love.graphics.setCanvas()
        return cv
    end

    local ok1, cNorm = pcall(renderStarCanvas, false, false)
    local ok2, cCyan = pcall(renderStarCanvas, true, true)
    local ok3, cMag  = pcall(renderStarCanvas, true, false)

    if ok1 and cNorm then Sparx.canvasNormal = cNorm end
    if ok2 and cCyan then Sparx.canvasSuperCyan = cCyan end
    if ok3 and cMag  then Sparx.canvasSuperMagenta = cMag end
end

function Sparx.new(grid, x, y, isClockwise, isSuper, speedMultiplier)
    local self = setmetatable({}, Sparx)
    self.grid = grid
    self.x = x or 0
    self.y = y or 0
    self.isClockwise = (isClockwise == nil) and true or isClockwise
    self.isSuper = isSuper or false
    self.speedMultiplier = speedMultiplier or 1.0

    self.dir = self.isClockwise and 0 or 2 -- 0: Right, 1: Down, 2: Left, 3: Up
    self.stepAccumulator = 0
    self.sparkAngle = 0
    self.chasingStix = false
    self.stixIndex = 1

    return self
end

function Sparx:mutateToSuper()
    self.isSuper = true
end

function Sparx:update(dt, player)
    self.sparkAngle = self.sparkAngle + dt * 10

    local stepsPerSec = (self.isSuper and 75 or 54) * (self.speedMultiplier or 1.0)
    self.stepAccumulator = self.stepAccumulator + stepsPerSec * dt

    while self.stepAccumulator >= 1.0 do
        self.stepAccumulator = self.stepAccumulator - 1.0
        self:step(player)
    end
end

function Sparx:step(player)
    -- 1. Super Sparx chasing player onto active stix
    if self.isSuper and player and player:isDrawing() and #player.stixPath > 0 then
        if not self.chasingStix then
            local origin = player.stixPath[1]
            local dx = self.x - origin.x
            local dy = self.y - origin.y
            if (dx * dx + dy * dy) <= 6.25 then
                self.chasingStix = true
                self.stixIndex = 1
            end
        end

        if self.chasingStix then
            if self.stixIndex <= #player.stixPath then
                local pt = player.stixPath[self.stixIndex]
                self.x = pt.x
                self.y = pt.y
                self.stixIndex = self.stixIndex + 1
                return
            end
        end
    else
        self.chasingStix = false
    end

    -- 2. Movement along borders:
    -- Super Sparx: Actively pursues the Marker along outer borders and newly claimed inner boundaries!
    if self.isSuper and player then
        local targetX = player.x
        local targetY = player.y
        -- If player is drawing into the field, target the Stix entrance
        if player:isDrawing() and #player.stixPath > 0 then
            targetX = player.stixPath[1].x
            targetY = player.stixPath[1].y
        end

        local bestDir = nil
        local bestDist = 1e9
        local reverseDir = (self.dir + 2) % 4
        local reverseValid = false

        for i = 0, 3 do
            local d = DIRS[i]
            local nx = self.x + d.dx
            local ny = self.y + d.dy

            if self.grid:inBounds(nx, ny) and self.grid:isActiveBorder(nx, ny) then
                if i == reverseDir then
                    reverseValid = true
                else
                    local dist = (nx - targetX) * (nx - targetX) + (ny - targetY) * (ny - targetY)
                    if dist < bestDist then
                        bestDist = dist
                        bestDir = i
                    end
                end
            end
        end

        -- If trapped at a dead end, allow reversing
        if not bestDir and reverseValid then
            bestDir = reverseDir
        end

        if bestDir then
            local d = DIRS[bestDir]
            self.x = self.x + d.dx
            self.y = self.y + d.dy
            self.dir = bestDir
            return
        end
    end

    -- Normal Sparx: Fixed perimeter patrol (wall follower along outer borders and edges of claimed areas)
    local turnOrder = self.isClockwise and TURN_CW or TURN_CCW

    for i = 1, 4 do
        local testDir = (self.dir + turnOrder[i]) % 4
        local d = DIRS[testDir]
        local nx = self.x + d.dx
        local ny = self.y + d.dy

        if self.grid:inBounds(nx, ny) and self.grid:isActiveBorder(nx, ny) then
            self.x = nx
            self.y = ny
            self.dir = testDir
            return
        end
    end
end

function Sparx:checkPlayerCollision(player)
    if not player or player:isShielded() or player.state == player.STATE_DEAD then
        return false
    end
    local dx = self.x - player.x
    local dy = self.y - player.y
    return (dx * dx + dy * dy) < 4.0
end

function Sparx:draw(offsetX, offsetY, scaleX, scaleY)
    local sx = offsetX + self.x * scaleX
    local sy = offsetY + self.y * scaleY

    -- Element size scaled for handheld screen
    local baseSize = self.isSuper and 5.4 or 4.4
    local size = baseSize * scaleX

    love.graphics.push()
    love.graphics.translate(sx, sy)

    -- Primary: Pre-rendered hardware texture canvas (1 fast GPU draw call, zero EarCut triangulation)
    if Sparx.canvasNormal then
        local flash = math.floor(self.sparkAngle * 3) % 2
        local cv = self.isSuper and (flash == 0 and Sparx.canvasSuperCyan or Sparx.canvasSuperMagenta) or Sparx.canvasNormal
        if cv then
            local cvScale = (size / 16.0)
            love.graphics.rotate(self.sparkAngle)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(cv, 0, 0, 0, cvScale, cvScale, 32, 32)
            love.graphics.pop()
            return
        end
    end

    -- Secondary Fallback: 100% convex triangle fans (Zero EarCut polygon triangulation)
    love.graphics.setColor(0, 0, 0, 0.88)
    love.graphics.circle("fill", 0, 0, size * 1.35)

    local pulse = 0.75 + 0.25 * math.sin(self.sparkAngle * 2)
    if self.isSuper then
        love.graphics.setColor(1.0, 0.15, 0.45, 0.55 * pulse)
        love.graphics.circle("fill", 0, 0, size * 1.7)
    else
        love.graphics.setColor(1.0, 0.75, 0.0, 0.42 * pulse)
        love.graphics.circle("fill", 0, 0, size * 1.55)
    end

    local sCross = size * 0.95
    love.graphics.push()
    love.graphics.rotate(self.sparkAngle + 0.785398)
    if self.isSuper then
        love.graphics.setColor(1.0, 0.2, 0.8, 0.9)
    else
        love.graphics.setColor(1.0, 0.45, 0.05, 0.95)
    end
    drawStarFan(sCross * 1.4, sCross * 0.35)
    love.graphics.pop()

    love.graphics.push()
    love.graphics.rotate(self.sparkAngle)
    local tipMain = size * 1.65
    local waistMain = size * 0.42

    love.graphics.setColor(0, 0, 0, 0.95)
    drawStarFan(tipMain + 1.8, waistMain + 1.2)

    if self.isSuper then
        local flash = math.floor(self.sparkAngle * 3) % 2
        if flash == 0 then
            love.graphics.setColor(0.1, 0.95, 1.0, 1.0)
        else
            love.graphics.setColor(1.0, 0.15, 0.7, 1.0)
        end
    else
        love.graphics.setColor(1.0, 0.95, 0.15, 1.0)
    end
    drawStarFan(tipMain, waistMain)
    love.graphics.pop()

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("fill", 0, 0, size * 0.42)

    love.graphics.pop()
end

return Sparx
