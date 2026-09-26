-- ==============================================================================
-- QIX - Playfield Grid & Capture Engine
-- Discrete playfield grid, BFS flood-fill, background art reveal & area calculation.
-- ==============================================================================

local Grid = {}
Grid.__index = Grid

local CELL_EMPTY = 0
local CELL_BORDER = 1
local CELL_CLAIMED_SLOW = 2
local CELL_CLAIMED_FAST = 3
local CELL_STIX = 4

Grid.CELL_EMPTY = CELL_EMPTY
Grid.CELL_BORDER = CELL_BORDER
Grid.CELL_CLAIMED_SLOW = CELL_CLAIMED_SLOW
Grid.CELL_CLAIMED_FAST = CELL_CLAIMED_FAST
Grid.CELL_STIX = CELL_STIX

function Grid.new(width, height)
    local self = setmetatable({}, Grid)
    self.width = width or 320
    self.height = height or 226
    self.size = self.width * self.height
    self.totalInner = (self.width - 2) * (self.height - 2)
    self.claimedCount = 0

    self.cells = {}
    self.imageData = love.image.newImageData(self.width, self.height)
    self.image = nil
    self.bgImage = nil

    self:init()
    return self
end

function Grid:loadBackground(imagePath)
    if love.filesystem.getInfo(imagePath) then
        local success, img = pcall(love.graphics.newImage, imagePath)
        if success then
            self.bgImage = img
            self.bgImage:setFilter("linear", "linear")
            self:updateAllPixels()
            return true
        end
    end
    self.bgImage = nil
    self:updateAllPixels()
    return false
end

function Grid:init()
    for i = 0, self.size - 1 do
        self.cells[i] = CELL_EMPTY
    end
    self.claimedCount = 0

    -- Perimeter borders
    for x = 0, self.width - 1 do
        self.cells[x] = CELL_BORDER -- Top edge
        self.cells[(self.height - 1) * self.width + x] = CELL_BORDER -- Bottom edge
    end
    for y = 0, self.height - 1 do
        self.cells[y * self.width] = CELL_BORDER -- Left edge
        self.cells[y * self.width + (self.width - 1)] = CELL_BORDER -- Right edge
    end

    self:updateAllPixels()
end

function Grid:index(x, y)
    return y * self.width + x
end

function Grid:inBounds(x, y)
    return x >= 0 and x < self.width and y >= 0 and y < self.height
end

function Grid:get(x, y)
    if not self:inBounds(x, y) then return CELL_BORDER end
    return self.cells[y * self.width + x]
end

function Grid:set(x, y, val)
    if self:inBounds(x, y) then
        self.cells[y * self.width + x] = val
        self:updatePixel(x, y, val)
    end
end

function Grid:isBorder(x, y)
    if not self:inBounds(x, y) then return false end
    return self.cells[y * self.width + x] == CELL_BORDER
end

function Grid:isClaimed(x, y)
    if not self:inBounds(x, y) then return false end
    local c = self.cells[y * self.width + x]
    return c == CELL_CLAIMED_SLOW or c == CELL_CLAIMED_FAST
end

function Grid:isEmpty(x, y)
    if not self:inBounds(x, y) then return false end
    return self.cells[y * self.width + x] == CELL_EMPTY
end

function Grid:isActiveBorder(x, y)
    if not self:isBorder(x, y) then return false end
    if x == 0 or x == self.width - 1 or y == 0 or y == self.height - 1 then return true end

    local dirs = { {0,1}, {0,-1}, {1,0}, {-1,0}, {1,1}, {-1,-1}, {1,-1}, {-1,1} }
    for _, d in ipairs(dirs) do
        local nx = x + d[1]
        local ny = y + d[2]
        if self:inBounds(nx, ny) and self.cells[ny * self.width + nx] == CELL_EMPTY then
            return true
        end
    end
    return false
end

function Grid:findNearestEmpty(targetX, targetY)
    local tx = math.floor(targetX)
    local ty = math.floor(targetY)
    if self:isEmpty(tx, ty) then return { x = tx, y = ty } end

    for r = 1, 15 do
        for dy = -r, r do
            for dx = -r, r do
                if math.abs(dx) == r or math.abs(dy) == r then
                    local nx = tx + dx
                    local ny = ty + dy
                    if self:isEmpty(nx, ny) then
                        return { x = nx, y = ny }
                    end
                end
            end
        end
    end
    return nil
end

function Grid:getClaimedPercent()
    if self.totalInner == 0 then return 0 end
    return math.min(100, (self.claimedCount / self.totalInner) * 100)
end

function Grid:completeStix(stixPath, isSlow, qixList)
    -- 1. Commit stix path to BORDER
    for _, pt in ipairs(stixPath) do
        self.cells[pt.y * self.width + pt.x] = CELL_BORDER
    end

    local claimType = isSlow and CELL_CLAIMED_SLOW or CELL_CLAIMED_FAST
    local w = self.width
    local h = self.height

    -- 2. Flood fill from all Qix positions to find empty cells Qix can reach
    local visited = {}
    local queue = {}
    local qHead = 1

    for _, qix in ipairs(qixList) do
        local pos = self:findNearestEmpty(qix.p1.x, qix.p1.y)
        if pos then
            local qIdx = pos.y * w + pos.x
            if not visited[qIdx] then
                visited[qIdx] = true
                table.insert(queue, qIdx)
            end
        end
        local pos2 = self:findNearestEmpty(qix.p2.x, qix.p2.y)
        if pos2 then
            local qIdx2 = pos2.y * w + pos2.x
            if not visited[qIdx2] then
                visited[qIdx2] = true
                table.insert(queue, qIdx2)
            end
        end
    end

    while qHead <= #queue do
        local curr = queue[qHead]
        qHead = qHead + 1

        local cx = curr % w
        local cy = math.floor(curr / w)

        local n1 = (cx + 1 < w) and (curr + 1) or nil
        local n2 = (cx - 1 >= 0) and (curr - 1) or nil
        local n3 = (cy + 1 < h) and (curr + w) or nil
        local n4 = (cy - 1 >= 0) and (curr - w) or nil

        local neighbors = { n1, n2, n3, n4 }
        for _, nIdx in ipairs(neighbors) do
            if nIdx and not visited[nIdx] and self.cells[nIdx] == CELL_EMPTY then
                visited[nIdx] = true
                table.insert(queue, nIdx)
            end
        end
    end

    -- 3. Any EMPTY cell NOT reached by Qix is captured!
    local newlyCaptured = 0
    local sumX, sumY = 0, 0

    for y = 1, h - 2 do
        local rowOffset = y * w
        for x = 1, w - 2 do
            local idx = rowOffset + x
            if self.cells[idx] == CELL_EMPTY and not visited[idx] then
                self.cells[idx] = claimType
                newlyCaptured = newlyCaptured + 1
                sumX = sumX + x
                sumY = sumY + y
            end
        end
    end

    local centroidX = newlyCaptured > 0 and (sumX / newlyCaptured) or (w * 0.5)
    local centroidY = newlyCaptured > 0 and (sumY / newlyCaptured) or (h * 0.5)

    self.claimedCount = self.claimedCount + newlyCaptured
    self:updateAllPixels()

    return {
        capturedCells = newlyCaptured,
        percent = self:getClaimedPercent(),
        cutPercent = (newlyCaptured / self.totalInner) * 100,
        isSlow = isSlow,
        cx = centroidX,
        cy = centroidY
    }
end

function Grid:clearStix(stixPath)
    for _, pt in ipairs(stixPath) do
        local idx = pt.y * self.width + pt.x
        if self.cells[idx] == CELL_STIX then
            self.cells[idx] = CELL_EMPTY
            self:updatePixel(pt.x, pt.y, CELL_EMPTY)
        end
    end
    if self.image then
        self.image:replacePixels(self.imageData)
    end
end

-- Pixel color mapping
function Grid:updatePixel(x, y, val)
    local r, g, b, a = 0, 0, 0, 1

    if val == CELL_EMPTY then
        -- Deep dark arcade playfield mask
        r, g, b, a = 0.02, 0.03, 0.06, 1.0

    elseif val == CELL_BORDER then
        -- Vibrant electric neon cyan
        r, g, b, a = 0.0, 0.95, 1.0, 1.0

    elseif val == CELL_CLAIMED_SLOW then
        if self.bgImage then
            -- Fiery orange/red translucent tint revealing background artwork underneath
            local hatch = ((x + y) % 4 == 0)
            r, g, b = 1.0, 0.30, 0.05
            a = hatch and 0.28 or 0.14
        else
            -- Retro arcade dense crosshatch
            local pat = (x % 4 < 2 and y % 4 < 2) or (x % 4 >= 2 and y % 4 >= 2)
            if pat then
                r, g, b = 1.0, 0.25, 0.12
            else
                r, g, b = 0.25, 0.05, 0.05
            end
            a = 1.0
        end

    elseif val == CELL_CLAIMED_FAST then
        if self.bgImage then
            -- Electric cyan/blue translucent tint revealing background artwork underneath
            local scan = (y % 4 < 2)
            r, g, b = 0.0, 0.65, 1.0
            a = scan and 0.30 or 0.15
        else
            -- Retro arcade horizontal scan stripes
            local scan = (y % 4 < 2)
            if scan then
                r, g, b = 0.0, 0.60, 1.0
            else
                r, g, b = 0.04, 0.15, 0.35
            end
            a = 1.0
        end

    elseif val == CELL_STIX then
        -- Bright neon yellow stix
        r, g, b, a = 1.0, 0.95, 0.2, 1.0
    end

    self.imageData:setPixel(x, y, r, g, b, a)
end

function Grid:updateAllPixels()
    local w = self.width
    local h = self.height
    for y = 0, h - 1 do
        local row = y * w
        for x = 0, w - 1 do
            self:updatePixel(x, y, self.cells[row + x])
        end
    end
    if not self.image then
        self.image = love.graphics.newImage(self.imageData)
        self.image:setFilter("nearest", "nearest")
    else
        self.image:replacePixels(self.imageData)
    end
end

function Grid:draw(offsetX, offsetY, scaleX, scaleY)
    -- 1. Draw uncovered background artwork if present
    if self.bgImage then
        love.graphics.setColor(1, 1, 1, 1)
        local sx = (self.width * scaleX) / self.bgImage:getWidth()
        local sy = (self.height * scaleY) / self.bgImage:getHeight()
        love.graphics.draw(self.bgImage, offsetX, offsetY, 0, sx, sy)
    end

    -- 2. Draw grid overlay (empty mask, borders, tinted claims)
    if self.image then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(self.image, offsetX, offsetY, 0, scaleX, scaleY)
    end
end

return Grid
