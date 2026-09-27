-- Sparx Enemy Patrol Engine
local Sparx = {}
Sparx.__index = Sparx

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

    local stepsPerSec = self.isSuper and 95 or 65
    self.stepAccumulator = self.stepAccumulator + stepsPerSec * dt

    while self.stepAccumulator >= 1.0 do
        self.stepAccumulator = self.stepAccumulator - 1.0
        self:step(player)
    end
end

function Sparx:step(player)
    -- Super Sparx chasing player onto active stix
    if self.isSuper and player and player:isDrawing() and #player.stixPath > 0 then
        if not self.chasingStix then
            local origin = player.stixPath[1]
            local dist = math.sqrt((self.x - origin.x)^2 + (self.y - origin.y)^2)
            if dist <= 2.0 then
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

    -- Normal border following
    local dirs = {
        { dx = 1, dy = 0 },  -- 0: Right
        { dx = 0, dy = 1 },  -- 1: Down
        { dx = -1, dy = 0 }, -- 2: Left
        { dx = 0, dy = -1 }  -- 3: Up
    }

    -- Wall follower algorithm
    local turnOrder = self.isClockwise and { -1, 0, 1, 2 } or { 1, 0, -1, 2 }

    for _, t in ipairs(turnOrder) do
        local testDir = (self.dir + t) % 4
        local nx = self.x + dirs[testDir + 1].dx
        local ny = self.y + dirs[testDir + 1].dy

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
    local dist = math.sqrt((self.x - player.x)^2 + (self.y - player.y)^2)
    return dist < 1.5
end

function Sparx:draw(offsetX, offsetY, scaleX, scaleY)
    local sx = offsetX + self.x * scaleX
    local sy = offsetY + self.y * scaleY
    local size = (self.isSuper and 5 or 4) * scaleX

    local r, g, b = 1, 0.2, 0.1
    if self.isSuper then
        r, g, b = 0.2, 0.5, 1.0
    end
    love.graphics.setColor(r, g, b, 1)

    -- Draw rotating 4-pointed spark star
    love.graphics.push()
    love.graphics.translate(sx, sy)
    love.graphics.rotate(self.sparkAngle)

    local star = {
        0, -size * 1.5,
        size * 0.4, -size * 0.4,
        size * 1.5, 0,
        size * 0.4, size * 0.4,
        0, size * 1.5,
        -size * 0.4, size * 0.4,
        -size * 1.5, 0,
        -size * 0.4, -size * 0.4
    }
    love.graphics.polygon("fill", star)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.circle("fill", 0, 0, size * 0.4)
    love.graphics.pop()
end

return Sparx
