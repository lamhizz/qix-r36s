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
    self.width = width or 355
    self.height = height or 251
    self.size = self.width * self.height
    self.totalInner = (self.width - 2) * (self.height - 2)
    self.claimedCount = 0

    self.cells = {}
    self.imageData = love.image.newImageData(self.width, self.height)
    self.image = nil
    self.bgImage = nil
    self.fgImage = nil
    self.fgGridData = nil

    self.bfsVisited = {}
    self.bfsTag = 0
    self.bfsQueue = {}

    self:init()
    return self
end

local Logger = require("logger")

local function loadSafeImage(path, isExternal, maxW, maxH)
    maxW = maxW or 640
    maxH = maxH or 480
    local rawData = nil
    local fileData = nil

    if isExternal then
        local f = io.open(path, "rb")
        if f then
            local data = f:read("*all")
            f:close()
            local filename = path:match("([^/\\]+)$") or "art.jpg"
            local okData, fd = pcall(love.filesystem.newFileData, data, filename)
            if okData and fd then
                local okImg, id = pcall(love.image.newImageData, fd)
                if okImg and id then
                    rawData = id
                end
            end
        end
    end

    if not rawData and love.filesystem.getInfo(path) then
        local okImg, id = pcall(love.image.newImageData, path)
        if okImg and id then
            rawData = id
        end
    end

    if not rawData then
        return nil
    end

    local srcW = rawData:getWidth()
    local srcH = rawData:getHeight()

    -- If image fits within limits, create image directly
    if srcW <= maxW and srcH <= maxH then
        local ok, img = pcall(love.graphics.newImage, rawData)
        if ok and img then
            return img, srcW, srcH, srcW, srcH
        end
        return nil
    end

    -- Downscale to fit within maxW x maxH preserving aspect ratio
    local scale = math.min(maxW / srcW, maxH / srcH)
    local dstW = math.max(1, math.floor(srcW * scale))
    local dstH = math.max(1, math.floor(srcH * scale))

    local okData, compactData = pcall(love.image.newImageData, dstW, dstH)
    if not okData or not compactData then
        return nil
    end

    for dy = 0, dstH - 1 do
        local sy = math.floor(dy / scale)
        if sy >= srcH then sy = srcH - 1 end
        for dx = 0, dstW - 1 do
            local sx = math.floor(dx / scale)
            if sx >= srcW then sx = srcW - 1 end
            local r, g, b, a = rawData:getPixel(sx, sy)
            compactData:setPixel(dx, dy, r, g, b, a)
        end
    end

    local ok, img = pcall(love.graphics.newImage, compactData)
    if ok and img then
        return img, srcW, srcH, dstW, dstH
    end
    return nil
end

function Grid:loadBackground(artEntry)
    self.bgImage = nil

    if not artEntry then
        self:updateAllPixels()
        return false
    end

    local path = type(artEntry) == "table" and artEntry.path or artEntry
    local isExternal = (type(artEntry) == "table" and artEntry.isExternal) or
                       (type(path) == "string" and (path:sub(1, 1) == "/" or path:match("^[A-Za-z]:")))

    local img, srcW, srcH, dstW, dstH = loadSafeImage(path, isExternal, 640, 480)

    if img then
        self.bgImage = img
        self.bgImage:setFilter("linear", "linear")
        self:updateAllPixels()
        local name = type(artEntry) == "table" and artEntry.name or tostring(path)
        Logger.info("GRID", "Loaded background: %s (Original: %dx%d -> GPU: %dx%d)", name, srcW or 0, srcH or 0, dstW or 0, dstH or 0)
        return true
    else
        Logger.warn("GRID", "Failed to load background image: %s", tostring(path))
    end

    self:updateAllPixels()
    return false
end

function Grid:loadForeground(fgEntry)
    self.fgImage = nil
    self.fgGridData = nil

    if not fgEntry then
        self:updateAllPixels()
        return false
    end

    local path = type(fgEntry) == "table" and fgEntry.path or fgEntry
    local isExternal = (type(fgEntry) == "table" and fgEntry.isExternal) or
                       (type(path) == "string" and (path:sub(1, 1) == "/" or path:match("^[A-Za-z]:")))

    local imgData = nil

    if isExternal then
        local f = io.open(path, "rb")
        if f then
            local data = f:read("*all")
            f:close()
            local filename = path:match("([^/\\]+)$") or "fg.jpg"
            local okData, fd = pcall(love.filesystem.newFileData, data, filename)
            if okData and fd then
                local okImg, loadedData = pcall(love.image.newImageData, fd)
                if okImg and loadedData then
                    imgData = loadedData
                end
            end
        end
    end

    if not imgData and love.filesystem.getInfo(path) then
        local okImg, loadedData = pcall(love.image.newImageData, path)
        if okImg and loadedData then
            imgData = loadedData
        end
    end

    if imgData then
        local srcW = imgData:getWidth()
        local srcH = imgData:getHeight()
        local targetW = self.width
        local targetH = self.height

        local scale = math.max(targetW / srcW, targetH / srcH)
        local drawW = srcW * scale
        local drawH = srcH * scale
        local offX = (drawW - targetW) * 0.5
        local offY = (drawH - targetH) * 0.5

        self.fgGridData = love.image.newImageData(targetW, targetH)
        for gy = 0, targetH - 1 do
            local sy = math.floor((gy + offY) / scale)
            if sy < 0 then sy = 0 elseif sy >= srcH then sy = srcH - 1 end
            for gx = 0, targetW - 1 do
                local sx = math.floor((gx + offX) / scale)
                if sx < 0 then sx = 0 elseif sx >= srcW then sx = srcW - 1 end
                local r, g, b, a = imgData:getPixel(sx, sy)
                self.fgGridData:setPixel(gx, gy, r, g, b, 1.0)
            end
        end

        self:updateAllPixels()
        local name = type(fgEntry) == "table" and fgEntry.name or tostring(path)
        Logger.info("GRID", "Loaded foreground skin: %s (Source: %dx%d -> Grid: %dx%d)", name, srcW, srcH, targetW, targetH)
        return true
    end

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

local BORDER_NEIGHBORS = {
    {0, 1}, {0, -1}, {1, 0}, {-1, 0},
    {1, 1}, {-1, -1}, {1, -1}, {-1, 1}
}

function Grid:isActiveBorder(x, y)
    if not self:isBorder(x, y) then return false end
    if x == 0 or x == self.width - 1 or y == 0 or y == self.height - 1 then return true end

    local w = self.width
    local cells = self.cells
    for i = 1, 8 do
        local d = BORDER_NEIGHBORS[i]
        local nx = x + d[1]
        local ny = y + d[2]
        if nx >= 0 and nx < w and ny >= 0 and ny < self.height and cells[ny * w + nx] == CELL_EMPTY then
            return true
        end
    end
    return false
end

function Grid:findNearestEmpty(targetX, targetY)
    local tx = math.floor(targetX)
    local ty = math.floor(targetY)
    if self:isEmpty(tx, ty) then return tx, ty end

    local w = self.width
    local h = self.height
    local cells = self.cells

    for r = 1, 15 do
        for dy = -r, r do
            for dx = -r, r do
                if math.abs(dx) == r or math.abs(dy) == r then
                    local nx = tx + dx
                    local ny = ty + dy
                    if nx >= 0 and nx < w and ny >= 0 and ny < h and cells[ny * w + nx] == CELL_EMPTY then
                        return nx, ny
                    end
                end
            end
        end
    end
    return nil, nil
end

function Grid:getClaimedPercent()
    if self.totalInner == 0 then return 0 end
    return math.min(100, (self.claimedCount / self.totalInner) * 100)
end

function Grid:completeStix(stixPath, isSlow, qixList)
    local w = self.width
    local h = self.height
    local cells = self.cells
    local claimType = isSlow and CELL_CLAIMED_SLOW or CELL_CLAIMED_FAST

    -- 1. Commit stix path to BORDER and update dirty pixels
    for _, pt in ipairs(stixPath) do
        cells[pt.y * w + pt.x] = CELL_BORDER
        self:updatePixel(pt.x, pt.y, CELL_BORDER)
    end

    local visited = self.bfsVisited
    local queue = self.bfsQueue

    -- 2. Check for Classic 1981 Split-Qix Rule (Level 3+ with 2 independent Qixes)
    local isSplitQix = false
    local qix1Reachable = 0
    local tagQ1 = nil

    if #qixList >= 2 then
        local q1x, q1y = self:findNearestEmpty(qixList[1].p1.x, qixList[1].p1.y)
        local q2x, q2y = self:findNearestEmpty(qixList[2].p1.x, qixList[2].p1.y)

        if q1x and q2x then
            self.bfsTag = (self.bfsTag or 0) + 1
            tagQ1 = self.bfsTag
            local q1Head = 1
            local q1Tail = 1
            local qIdx1 = q1y * w + q1x
            visited[qIdx1] = tagQ1
            queue[1] = qIdx1

            while q1Head <= q1Tail do
                local curr = queue[q1Head]
                q1Head = q1Head + 1
                local cx = curr % w
                local cy = math.floor(curr / w)

                if cx + 1 < w then
                    local nIdx = curr + 1
                    if visited[nIdx] ~= tagQ1 and cells[nIdx] == CELL_EMPTY then
                        visited[nIdx] = tagQ1
                        q1Tail = q1Tail + 1
                        queue[q1Tail] = nIdx
                    end
                end
                if cx > 0 then
                    local nIdx = curr - 1
                    if visited[nIdx] ~= tagQ1 and cells[nIdx] == CELL_EMPTY then
                        visited[nIdx] = tagQ1
                        q1Tail = q1Tail + 1
                        queue[q1Tail] = nIdx
                    end
                end
                if cy + 1 < h then
                    local nIdx = curr + w
                    if visited[nIdx] ~= tagQ1 and cells[nIdx] == CELL_EMPTY then
                        visited[nIdx] = tagQ1
                        q1Tail = q1Tail + 1
                        queue[q1Tail] = nIdx
                    end
                end
                if cy > 0 then
                    local nIdx = curr - w
                    if visited[nIdx] ~= tagQ1 and cells[nIdx] == CELL_EMPTY then
                        visited[nIdx] = tagQ1
                        q1Tail = q1Tail + 1
                        queue[q1Tail] = nIdx
                    end
                end
            end

            local qIdx2 = q2y * w + q2x
            if visited[qIdx2] ~= tagQ1 then
                -- Qix 2 was NOT reached from Qix 1: Split-Qix occurred!
                isSplitQix = true
                qix1Reachable = q1Tail
            end
        end
    end

    local newlyCaptured = 0
    local sumX, sumY = 0, 0

    if isSplitQix then
        -- In Split-Qix: The smaller compartment is claimed, and round immediately clears!
        local remainingEmpty = self.totalInner - self.claimedCount
        local claimSide1 = (qix1Reachable <= remainingEmpty * 0.5)

        for y = 1, h - 2 do
            local rowOffset = y * w
            for x = 1, w - 2 do
                local idx = rowOffset + x
                if cells[idx] == CELL_EMPTY then
                    local inSide1 = (visited[idx] == tagQ1)
                    if (claimSide1 and inSide1) or (not claimSide1 and not inSide1) then
                        cells[idx] = claimType
                        self:updatePixel(x, y, claimType)
                        newlyCaptured = newlyCaptured + 1
                        sumX = sumX + x
                        sumY = sumY + y
                    end
                end
            end
        end
    else
        -- Standard flood fill from all Qix positions
        self.bfsTag = (self.bfsTag or 0) + 1
        local tag = self.bfsTag
        local qHead = 1
        local qTail = 0

        for _, qix in ipairs(qixList) do
            local qx1, qy1 = self:findNearestEmpty(qix.p1.x, qix.p1.y)
            if qx1 then
                local qIdx = qy1 * w + qx1
                if visited[qIdx] ~= tag then
                    visited[qIdx] = tag
                    qTail = qTail + 1
                    queue[qTail] = qIdx
                end
            end
            local qx2, qy2 = self:findNearestEmpty(qix.p2.x, qix.p2.y)
            if qx2 then
                local qIdx2 = qy2 * w + qx2
                if visited[qIdx2] ~= tag then
                    visited[qIdx2] = tag
                    qTail = qTail + 1
                    queue[qTail] = qIdx2
                end
            end
        end

        while qHead <= qTail do
            local curr = queue[qHead]
            qHead = qHead + 1

            local cx = curr % w
            local cy = math.floor(curr / w)

            if cx + 1 < w then
                local nIdx = curr + 1
                if visited[nIdx] ~= tag and cells[nIdx] == CELL_EMPTY then
                    visited[nIdx] = tag
                    qTail = qTail + 1
                    queue[qTail] = nIdx
                end
            end
            if cx > 0 then
                local nIdx = curr - 1
                if visited[nIdx] ~= tag and cells[nIdx] == CELL_EMPTY then
                    visited[nIdx] = tag
                    qTail = qTail + 1
                    queue[qTail] = nIdx
                end
            end
            if cy + 1 < h then
                local nIdx = curr + w
                if visited[nIdx] ~= tag and cells[nIdx] == CELL_EMPTY then
                    visited[nIdx] = tag
                    qTail = qTail + 1
                    queue[qTail] = nIdx
                end
            end
            if cy > 0 then
                local nIdx = curr - w
                if visited[nIdx] ~= tag and cells[nIdx] == CELL_EMPTY then
                    visited[nIdx] = tag
                    qTail = qTail + 1
                    queue[qTail] = nIdx
                end
            end
        end

        -- Capture any EMPTY cell NOT reached by Qix
        for y = 1, h - 2 do
            local rowOffset = y * w
            for x = 1, w - 2 do
                local idx = rowOffset + x
                if cells[idx] == CELL_EMPTY and visited[idx] ~= tag then
                    cells[idx] = claimType
                    self:updatePixel(x, y, claimType)
                    newlyCaptured = newlyCaptured + 1
                    sumX = sumX + x
                    sumY = sumY + y
                end
            end
        end
    end

    local centroidX = newlyCaptured > 0 and (sumX / newlyCaptured) or (w * 0.5)
    local centroidY = newlyCaptured > 0 and (sumY / newlyCaptured) or (h * 0.5)

    self.claimedCount = self.claimedCount + newlyCaptured

    if self.image then
        self.image:replacePixels(self.imageData)
    else
        self.image = love.graphics.newImage(self.imageData)
        self.image:setFilter("nearest", "nearest")
    end

    return {
        capturedCells = newlyCaptured,
        percent = self:getClaimedPercent(),
        cutPercent = (newlyCaptured / self.totalInner) * 100,
        isSlow = isSlow,
        cx = centroidX,
        cy = centroidY,
        isSplitQix = isSplitQix
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
        if self.fgGridData then
            -- Foreground cover skin from foreground-art folder
            r, g, b = self.fgGridData:getPixel(x, y)
            a = 1.0
        else
            -- Deep dark arcade playfield mask fallback
            r, g, b, a = 0.02, 0.03, 0.06, 1.0
        end

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
    -- 1. Draw uncovered background artwork if present (proportional cover scaling)
    if self.bgImage then
        love.graphics.setColor(1, 1, 1, 1)
        local targetW = self.width * scaleX
        local targetH = self.height * scaleY
        local imgW = self.bgImage:getWidth()
        local imgH = self.bgImage:getHeight()
        local scale = math.max(targetW / imgW, targetH / imgH)
        local drawW = imgW * scale
        local drawH = imgH * scale
        local drawX = offsetX + (targetW - drawW) * 0.5
        local drawY = offsetY + (targetH - drawH) * 0.5

        love.graphics.setScissor(math.floor(offsetX), math.floor(offsetY), math.floor(targetW), math.floor(targetH))
        love.graphics.draw(self.bgImage, drawX, drawY, 0, scale, scale)
        love.graphics.setScissor()
    end

    -- 2. Draw grid overlay (empty mask, borders, tinted claims)
    if self.image then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(self.image, offsetX, offsetY, 0, scaleX, scaleY)
    end
end

return Grid
