-- Sparx Enemy Patrol Engine
local Sparx = {}
Sparx.__index = Sparx

local DIRS = {
    [0] = { dx = 1, dy = 0 },  -- 0: Right
    [1] = { dx = 0, dy = 1 },  -- 1: Down
    [2] = { dx = -1, dy = 0 }, -- 2: Left
    [3] = { dx = 0, dy = -1 }  -- 3: Up
}

local TURN_CW = { -1, 0, 1, 2 }
local TURN_CCW = { 1, 0, -1, 2 }

local STAR_POLYGON = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
local STAR_POLYGON_OUTER = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
local STAR_POLYGON_CROSS = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }

function Sparx.new(grid, x, y, isClockwise, isSuper)
    local self = setmetatable({}, Sparx)
    self.grid = grid
    self.x = x or 0
    self.y = y or 0
    self.isClockwise = (isClockwise == nil) and true or isClockwise
    self.isSuper = isSuper or false

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

    local stepsPerSec = self.isSuper and 75 or 54
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

    -- Significantly increased element size for high visibility on handheld screen
    local baseSize = self.isSuper and 5.4 or 4.4
    local size = baseSize * scaleX

    love.graphics.push()
    love.graphics.translate(sx, sy)

    -- 1. Outer High-Contrast Dark Silhouette (Ensures visibility against cyan borders & bright photos)
    love.graphics.setColor(0, 0, 0, 0.88)
    love.graphics.circle("fill", 0, 0, size * 1.35)

    -- 2. Ambient Corona / Glowing Halo
    local pulse = 0.75 + 0.25 * math.sin(self.sparkAngle * 2)
    if self.isSuper then
        -- Super Sparx: Menacing pulsing magenta/red halo
        love.graphics.setColor(1.0, 0.15, 0.45, 0.55 * pulse)
        love.graphics.circle("fill", 0, 0, size * 1.7)
    else
        -- Normal Sparx: Electric golden yellow halo
        love.graphics.setColor(1.0, 0.75, 0.0, 0.42 * pulse)
        love.graphics.circle("fill", 0, 0, size * 1.55)
    end

    -- 3. Secondary 45-degree Cross Star (creates authentic 8-point dazzling arcade sparkler)
    local sCross = size * 0.95
    local tipCross = sCross * 1.4
    local waistCross = sCross * 0.35

    love.graphics.rotate(self.sparkAngle + 0.785398) -- +45 degrees

    STAR_POLYGON_CROSS[1]  = 0;            STAR_POLYGON_CROSS[2]  = -tipCross
    STAR_POLYGON_CROSS[3]  = waistCross;   STAR_POLYGON_CROSS[4]  = -waistCross
    STAR_POLYGON_CROSS[5]  = tipCross;     STAR_POLYGON_CROSS[6]  = 0
    STAR_POLYGON_CROSS[7]  = waistCross;   STAR_POLYGON_CROSS[8]  = waistCross
    STAR_POLYGON_CROSS[9]  = 0;            STAR_POLYGON_CROSS[10] = tipCross
    STAR_POLYGON_CROSS[11] = -waistCross;  STAR_POLYGON_CROSS[12] = waistCross
    STAR_POLYGON_CROSS[13] = -tipCross;    STAR_POLYGON_CROSS[14] = 0
    STAR_POLYGON_CROSS[15] = -waistCross;  STAR_POLYGON_CROSS[16] = -waistCross

    if self.isSuper then
        love.graphics.setColor(1.0, 0.2, 0.8, 0.9)
    else
        love.graphics.setColor(1.0, 0.45, 0.05, 0.95)
    end
    love.graphics.polygon("fill", STAR_POLYGON_CROSS)

    -- 4. Primary Rotating 4-Point Star
    love.graphics.rotate(-0.785398) -- Return to sparkAngle
    local tipMain = size * 1.65
    local waistMain = size * 0.42

    -- Black outline on primary star for punchy contrast
    local shadowTip = tipMain + 1.8
    local shadowWaist = waistMain + 1.2
    STAR_POLYGON_OUTER[1]  = 0;             STAR_POLYGON_OUTER[2]  = -shadowTip
    STAR_POLYGON_OUTER[3]  = shadowWaist;   STAR_POLYGON_OUTER[4]  = -shadowWaist
    STAR_POLYGON_OUTER[5]  = shadowTip;     STAR_POLYGON_OUTER[6]  = 0
    STAR_POLYGON_OUTER[7]  = shadowWaist;   STAR_POLYGON_OUTER[8]  = shadowWaist
    STAR_POLYGON_OUTER[9]  = 0;             STAR_POLYGON_OUTER[10] = shadowTip
    STAR_POLYGON_OUTER[11] = -shadowWaist;  STAR_POLYGON_OUTER[12] = shadowWaist
    STAR_POLYGON_OUTER[13] = -shadowTip;    STAR_POLYGON_OUTER[14] = 0
    STAR_POLYGON_OUTER[15] = -shadowWaist;  STAR_POLYGON_OUTER[16] = -shadowWaist

    love.graphics.setColor(0, 0, 0, 0.95)
    love.graphics.polygon("fill", STAR_POLYGON_OUTER)

    -- Vibrant core star
    STAR_POLYGON[1]  = 0;           STAR_POLYGON[2]  = -tipMain
    STAR_POLYGON[3]  = waistMain;   STAR_POLYGON[4]  = -waistMain
    STAR_POLYGON[5]  = tipMain;     STAR_POLYGON[6]  = 0
    STAR_POLYGON[7]  = waistMain;   STAR_POLYGON[8]  = waistMain
    STAR_POLYGON[9]  = 0;           STAR_POLYGON[10] = tipMain
    STAR_POLYGON[11] = -waistMain;  STAR_POLYGON[12] = waistMain
    STAR_POLYGON[13] = -tipMain;    STAR_POLYGON[14] = 0
    STAR_POLYGON[15] = -waistMain;  STAR_POLYGON[16] = -waistMain

    if self.isSuper then
        -- Flashing electric cyan / bright magenta beacon
        local flash = math.floor(self.sparkAngle * 3) % 2
        if flash == 0 then
            love.graphics.setColor(0.1, 0.95, 1.0, 1.0)
        else
            love.graphics.setColor(1.0, 0.15, 0.7, 1.0)
        end
    else
        -- Intense electric golden yellow
        love.graphics.setColor(1.0, 0.95, 0.15, 1.0)
    end
    love.graphics.polygon("fill", STAR_POLYGON)

    -- 5. Brilliant Hot White Center Spark
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("fill", 0, 0, size * 0.42)

    love.graphics.pop()
end

return Sparx
