-- Player marker and stix drawing engine for Qix
local Audio = require("audio")
local Particles = require("particles")

local Player = {}
Player.__index = Player

local STATE_BORDER = 0
local STATE_DRAWING = 1
local STATE_DEAD = 2

Player.STATE_BORDER = STATE_BORDER
Player.STATE_DRAWING = STATE_DRAWING
Player.STATE_DEAD = STATE_DEAD

function Player.new(grid)
    local self = setmetatable({}, Player)
    self.grid = grid
    self:reset()
    return self
end

function Player:reset(cfg)
    self.x = math.floor(self.grid.width / 2)
    self.y = self.grid.height - 1
    self.state = STATE_BORDER

    self.isSlow = false
    self.stixPath = {}
    self.drawOrigin = nil

    self.idleTimer = 0
    self.fuseWarning = false
    self.fuseActive = false
    self.fuseIndex = 1
    self.fuseWarningDelay = 0.4
    self.fuseDelay = 0.75
    self.fuseBurnSpeed = 42

    self.shieldDuration = 2.5
    self.shieldTimer = self.shieldDuration -- Grace period on level start

    self.moveAccumulator = 0
    self.animTime = 0

    self.usedFastThisLevel = false

    -- Corner Snapping & Pre-Turn Assist state
    self.lastMoveDirX = 0
    self.lastMoveDirY = 0
    self.turnBufferDx = 0
    self.turnBufferDy = 0
    self.turnBufferTimer = 0
    self.turnBufferDuration = 0.120 -- 120ms input buffer

    if cfg then
        self:applyDifficulty(cfg)
    end
end

function Player:applyDifficulty(cfg)
    if not cfg then return end
    self.shieldDuration = cfg.shieldDuration or 2.5
    self.shieldTimer = self.shieldDuration
    self.fuseDelay = cfg.fuseDelay or 0.75
    self.fuseBurnSpeed = cfg.fuseBurnSpeed or 42
end

function Player:clearTurnBuffer()
    self.turnBufferTimer = 0
    self.turnBufferDx = 0
    self.turnBufferDy = 0
end

function Player:respawn()
    if #self.stixPath > 0 then
        self.grid:clearStix(self.stixPath)
        self.stixPath = {}
    end
    Audio.stopAll()

    self.x = math.floor(self.grid.width / 2)
    self.y = self.grid.height - 1
    if not self.grid:isBorder(self.x, self.y) then
        local found = false
        for y = self.grid.height - 1, 0, -1 do
            for x = 0, self.grid.width - 1 do
                if self.grid:isActiveBorder(x, y) then
                    self.x = x
                    self.y = y
                    found = true
                    break
                end
            end
            if found then break end
        end
    end

    self.state = STATE_BORDER
    self.isSlow = false
    self.idleTimer = 0
    self.fuseWarning = false
    self.fuseActive = false
    self.fuseIndex = 1
    self.shieldTimer = self.shieldDuration
    self.lastMoveDirX = 0
    self.lastMoveDirY = 0
    self:clearTurnBuffer()
end

function Player:isShielded()
    return self.shieldTimer > 0
end

function Player:isDrawing()
    return self.state == STATE_DRAWING
end

-- Dynamic turn-assist threshold: playerSpeed * 1.5 in effective frame movement window,
-- clamped to a safe, reliable window (4 to 8 grid units = ~7 to 14px on R36S 640x480 screen)
function Player:getSnapTolerance(speed, dt)
    local effDt = dt or (1 / 60)
    local dynamicUnits = (speed * effDt) * 1.5
    return math.max(4, math.min(8, math.floor(dynamicUnits + 0.5)))
end

-- Checks if a corner in the target direction exists ahead along current travel axis
function Player:hasCornerAhead(alongDx, alongDy, targetDx, targetDy, maxDist)
    if alongDx == 0 and alongDy == 0 then return false end
    for dist = 1, maxDist do
        local cx = self.x + dist * alongDx
        local cy = self.y + dist * alongDy
        if not (self.grid:inBounds(cx, cy) and self.grid:isBorder(cx, cy)) then
            break
        end
        local tNx = cx + targetDx
        local tNy = cy + targetDy
        if self.grid:inBounds(tNx, tNy) and self.grid:isBorder(tNx, tNy) then
            return true
        end
    end
    return false
end

-- Searches for an intersecting valid perimeter path within SNAP_TOLERANCE ahead or behind
function Player:findPerimeterTurn(targetDx, targetDy, snapTolerance)
    if not self.grid then return false end

    -- 1. Check if turn is directly valid right at current position (already at corner)
    local curNx = self.x + targetDx
    local curNy = self.y + targetDy
    if self.grid:inBounds(curNx, curNy) and self.grid:isBorder(curNx, curNy) then
        return true, self.x, self.y
    end

    -- 2. Search ahead and behind along the current perimeter axis
    if targetDy ~= 0 then
        -- Perpendicular input is vertical -> along-axis must be horizontal
        local primaryDir = (self.lastMoveDirX ~= 0) and self.lastMoveDirX or 1
        -- Ahead search
        for dist = 1, snapTolerance do
            local cx = self.x + dist * primaryDir
            local cy = self.y
            if not (self.grid:inBounds(cx, cy) and self.grid:isBorder(cx, cy)) then
                break
            end
            local tNx = cx + targetDx
            local tNy = cy + targetDy
            if self.grid:inBounds(tNx, tNy) and self.grid:isBorder(tNx, tNy) then
                return true, cx, cy
            end
        end
        -- Behind search
        for dist = 1, snapTolerance do
            local cx = self.x - dist * primaryDir
            local cy = self.y
            if not (self.grid:inBounds(cx, cy) and self.grid:isBorder(cx, cy)) then
                break
            end
            local tNx = cx + targetDx
            local tNy = cy + targetDy
            if self.grid:inBounds(tNx, tNy) and self.grid:isBorder(tNx, tNy) then
                return true, cx, cy
            end
        end
    elseif targetDx ~= 0 then
        -- Perpendicular input is horizontal -> along-axis must be vertical
        local primaryDir = (self.lastMoveDirY ~= 0) and self.lastMoveDirY or 1
        -- Ahead search
        for dist = 1, snapTolerance do
            local cx = self.x
            local cy = self.y + dist * primaryDir
            if not (self.grid:inBounds(cx, cy) and self.grid:isBorder(cx, cy)) then
                break
            end
            local tNx = cx + targetDx
            local tNy = cy + targetDy
            if self.grid:inBounds(tNx, tNy) and self.grid:isBorder(tNx, tNy) then
                return true, cx, cy
            end
        end
        -- Behind search
        for dist = 1, snapTolerance do
            local cx = self.x
            local cy = self.y - dist * primaryDir
            if not (self.grid:inBounds(cx, cy) and self.grid:isBorder(cx, cy)) then
                break
            end
            local tNx = cx + targetDx
            local tNy = cy + targetDy
            if self.grid:inBounds(tNx, tNy) and self.grid:isBorder(tNx, tNy) then
                return true, cx, cy
            end
        end
    end

    return false
end

-- Executes corner snap and commits movement onto the intersecting path
function Player:trySnapTurn(targetDx, targetDy, snapTolerance)
    local found, snapX, snapY = self:findPerimeterTurn(targetDx, targetDy, snapTolerance)
    if found then
        -- Smoothly snap primary coordinate to intersection axis
        self.x = snapX
        self.y = snapY

        -- Commit movement onto intersecting path
        local nx = self.x + targetDx
        local ny = self.y + targetDy
        if self.grid:inBounds(nx, ny) and self.grid:isBorder(nx, ny) then
            self.x = nx
            self.y = ny
        end

        self.lastMoveDirX = targetDx
        self.lastMoveDirY = targetDy
        self:clearTurnBuffer()
        self.moveAccumulator = 0
        Audio.play("tick")
        return true
    end
    return false
end

function Player:update(dt, input, qixList, onAreaCaptured, onDeath, offsetX, offsetY, scaleX, scaleY)
    if self.state == STATE_DEAD then return end

    self.animTime = self.animTime + dt
    if self.shieldTimer > 0 then
        self.shieldTimer = math.max(0, self.shieldTimer - dt)
    end

    local wantsDraw = input.fastDraw or input.slowDraw

    -- When drawing stix inside playfield, or explicitly initiating a Draw into open territory
    if self.state == STATE_DRAWING or wantsDraw then
        self:clearTurnBuffer()
        local hasMove = (input.dx ~= 0) or (input.dy ~= 0)
        local speed = (self.state == STATE_BORDER) and 160 or (self.isSlow and 48 or 95)

        if hasMove then
            self.idleTimer = 0
            self.fuseWarning = false
            if self.fuseActive then
                self.fuseActive = false
                Audio.stopFuse()
            end

            self.moveAccumulator = self.moveAccumulator + speed * dt
            while self.moveAccumulator >= 1.0 do
                self.moveAccumulator = self.moveAccumulator - 1.0
                local result = self:step(input.dx, input.dy, wantsDraw, input.slowDraw, qixList)

                -- Plasma cutting spark emitter
                if self.state == STATE_DRAWING and offsetX and scaleX then
                    Particles.spawnCutSpark(offsetX + self.x * scaleX, offsetY + self.y * scaleY, input.dx, input.dy, self.isSlow)
                end

                if result and result.captured then
                    onAreaCaptured(result.captureResult)
                    return
                end
                if result and result.died then
                    onDeath(result.reason)
                    return
                end
            end
        else
            self.moveAccumulator = 0
            -- Fuse ignition on idle while drawing
            if self.state == STATE_DRAWING then
                self.idleTimer = self.idleTimer + dt
                if self.idleTimer >= self.fuseWarningDelay and self.idleTimer < self.fuseDelay then
                    self.fuseWarning = true
                elseif self.idleTimer >= self.fuseDelay then
                    self.fuseWarning = false
                    if not self.fuseActive then
                        self.fuseActive = true
                        self.fuseIndex = 1
                        Audio.startFuse()
                    end

                    self.fuseIndex = self.fuseIndex + self.fuseBurnSpeed * dt
                    if self.fuseIndex >= #self.stixPath then
                        Audio.stopAll()
                        onDeath("fuse")
                        return
                    end
                end
            end
        end
        return
    end

    -- =========================================================================
    -- Perimeter Navigation (STATE_BORDER, wantsDraw == false)
    -- Implements Corner Snapping & Pre-Turn Assist with 120ms Input Buffering
    -- =========================================================================
    local speed = 160 -- Border traversal pacing
    local snapTolerance = self:getSnapTolerance(speed, dt)

    -- 1. Update 120ms input buffer timer
    if self.turnBufferTimer > 0 then
        self.turnBufferTimer = self.turnBufferTimer - dt
        if self.turnBufferTimer <= 0 then
            self:clearTurnBuffer()
        end
    end

    local inDx = input.dx
    local inDy = input.dy

    -- 2. Check for 180-degree instant reversal along the active line
    local isReversal = false
    if self.lastMoveDirX ~= 0 and inDx == -self.lastMoveDirX and inDy == 0 then
        isReversal = true
    elseif self.lastMoveDirY ~= 0 and inDy == -self.lastMoveDirY and inDx == 0 then
        isReversal = true
    end

    if isReversal then
        self:clearTurnBuffer()
        self.idleTimer = 0
        self.moveAccumulator = self.moveAccumulator + speed * dt
        while self.moveAccumulator >= 1.0 do
            self.moveAccumulator = self.moveAccumulator - 1.0
            self:step(inDx, inDy, false, false, qixList)
        end
        return
    end

    -- 3. Detect perpendicular turn input and update buffer
    if self.lastMoveDirX ~= 0 then
        -- Currently traveling horizontally
        if inDy ~= 0 then
            self.turnBufferDx = 0
            self.turnBufferDy = inDy
            self.turnBufferTimer = self.turnBufferDuration
        end
    elseif self.lastMoveDirY ~= 0 then
        -- Currently traveling vertically
        if inDx ~= 0 then
            self.turnBufferDx = inDx
            self.turnBufferDy = 0
            self.turnBufferTimer = self.turnBufferDuration
        end
    else
        -- Stationary on perimeter
        if inDx ~= 0 and inDy == 0 then
            if not (self.grid:inBounds(self.x + inDx, self.y) and self.grid:isBorder(self.x + inDx, self.y)) then
                self.turnBufferDx = inDx
                self.turnBufferDy = 0
                self.turnBufferTimer = self.turnBufferDuration
            end
        elseif inDy ~= 0 and inDx == 0 then
            if not (self.grid:inBounds(self.x, self.y + inDy) and self.grid:isBorder(self.x, self.y + inDy)) then
                self.turnBufferDx = 0
                self.turnBufferDy = inDy
                self.turnBufferTimer = self.turnBufferDuration
            end
        elseif inDx ~= 0 and inDy ~= 0 then
            if self.grid:inBounds(self.x + inDx, self.y) and self.grid:isBorder(self.x + inDx, self.y) then
                self.lastMoveDirX = inDx
                self.turnBufferDx = 0
                self.turnBufferDy = inDy
                self.turnBufferTimer = self.turnBufferDuration
            elseif self.grid:inBounds(self.x, self.y + inDy) and self.grid:isBorder(self.x, self.y + inDy) then
                self.lastMoveDirY = inDy
                self.turnBufferDx = inDx
                self.turnBufferDy = 0
                self.turnBufferTimer = self.turnBufferDuration
            end
        end
    end

    -- 4. Attempt immediate corner snap turn if buffer is active
    if self.turnBufferTimer > 0 then
        if self:trySnapTurn(self.turnBufferDx, self.turnBufferDy, snapTolerance) then
            self.idleTimer = 0
            return
        end
    end

    -- 5. Determine along-axis movement towards corner
    local stepDx, stepDy = 0, 0
    local maxAnticipateDist = math.floor(speed * self.turnBufferDuration + 0.5) -- ~19 units

    if self.lastMoveDirX ~= 0 then
        if inDx ~= 0 then
            stepDx = inDx
        elseif (inDy ~= 0 or (self.turnBufferTimer > 0 and self.turnBufferDy ~= 0)) then
            local checkDy = (inDy ~= 0) and inDy or self.turnBufferDy
            if self:hasCornerAhead(self.lastMoveDirX, 0, 0, checkDy, maxAnticipateDist) then
                -- Pre-turning: continue moving along current axis towards the verified upcoming corner
                stepDx = self.lastMoveDirX
            end
        end
        stepDy = 0
    elseif self.lastMoveDirY ~= 0 then
        stepDx = 0
        if inDy ~= 0 then
            stepDy = inDy
        elseif (inDx ~= 0 or (self.turnBufferTimer > 0 and self.turnBufferDx ~= 0)) then
            local checkDx = (inDx ~= 0) and inDx or self.turnBufferDx
            if self:hasCornerAhead(0, self.lastMoveDirY, checkDx, 0, maxAnticipateDist) then
                stepDy = self.lastMoveDirY
            end
        end
    else
        stepDx = inDx
        stepDy = (inDx == 0) and inDy or 0
    end

    -- Advance along valid border line
    if stepDx ~= 0 or stepDy ~= 0 then
        self.idleTimer = 0
        self.moveAccumulator = self.moveAccumulator + speed * dt
        while self.moveAccumulator >= 1.0 do
            self.moveAccumulator = self.moveAccumulator - 1.0
            local oldX, oldY = self.x, self.y
            self:step(stepDx, stepDy, false, false, qixList)

            if self.x == oldX and self.y == oldY then
                self.moveAccumulator = 0
                break
            end

            -- Re-check if buffered turn can execute after this sub-step
            if self.turnBufferTimer > 0 then
                if self:trySnapTurn(self.turnBufferDx, self.turnBufferDy, snapTolerance) then
                    break
                end
            end
        end
    else
        self.moveAccumulator = 0
    end
end

function Player:step(dx, dy, wantsDraw, isSlowKey, qixList)
    if dx ~= 0 and dy ~= 0 then
        dy = 0 -- Snap to cardinal axis
    end

    local nx = self.x + dx
    local ny = self.y + dy

    if not self.grid:inBounds(nx, ny) then return nil end

    local nextCell = self.grid:get(nx, ny)

    -- Case 1: Currently on BORDER
    if self.state == STATE_BORDER then
        if nextCell == self.grid.CELL_BORDER then
            self.x = nx
            self.y = ny
            self.lastMoveDirX = dx
            self.lastMoveDirY = dy
            Audio.play("tick")
            return nil
        end

        if nextCell == self.grid.CELL_EMPTY and wantsDraw then
            self.state = STATE_DRAWING
            self.isSlow = isSlowKey
            if not isSlowKey then
                self.usedFastThisLevel = true
            end
            self.shieldTimer = 0
            self.drawOrigin = { x = self.x, y = self.y }
            self.stixPath = { { x = self.x, y = self.y } }

            self.x = nx
            self.y = ny
            self.grid:set(nx, ny, self.grid.CELL_STIX)
            table.insert(self.stixPath, { x = nx, y = ny })

            Audio.startDraw(self.isSlow)
            return nil
        end
        return nil
    end

    -- Case 2: Currently DRAWING Stix
    if self.state == STATE_DRAWING then
        -- Cannot 180 backtrack into immediate previous position
        if #self.stixPath >= 2 then
            local prev = self.stixPath[#self.stixPath - 1]
            if nx == prev.x and ny == prev.y then
                return nil
            end
        end

        -- Cannot cross own active stix
        if nextCell == self.grid.CELL_STIX then
            return nil
        end

        -- Completed stix by reaching border!
        if nextCell == self.grid.CELL_BORDER then
            self.x = nx
            self.y = ny
            table.insert(self.stixPath, { x = nx, y = ny })
            Audio.stopDraw()
            Audio.stopFuse()

            local captureResult = self.grid:completeStix(self.stixPath, self.isSlow, qixList)
            self.state = STATE_BORDER
            self.stixPath = {}
            self.drawOrigin = nil
            self.fuseActive = false

            return { captured = true, captureResult = captureResult }
        end

        -- Moving further into empty space
        if nextCell == self.grid.CELL_EMPTY then
            self.x = nx
            self.y = ny
            self.grid:set(nx, ny, self.grid.CELL_STIX)
            table.insert(self.stixPath, { x = nx, y = ny })
            return nil
        end
    end

    return nil
end

local stixLineCoords = {}
local DIAMOND_POLYGON = { 0, 0, 0, 0, 0, 0, 0, 0 }

function Player:draw(offsetX, offsetY, scaleX, scaleY)
    if self.state == STATE_DEAD then return end

    -- Draw active Stix line (single batched draw call)
    local pathCount = #self.stixPath
    if self.state == STATE_DRAWING and pathCount > 1 then
        local fIdx = (self.fuseActive and pathCount > 0) and math.min(pathCount, math.floor(self.fuseIndex)) or 0

        -- 1. If fuse is burning, draw the burnt/charred trail from origin up to fuse head
        if fIdx > 1 then
            love.graphics.setColor(0.5, 0.15, 0.08, 0.8)
            love.graphics.setLineWidth(1.6 * scaleX)
            local burntIdx = 0
            for i = 1, fIdx do
                local pt = self.stixPath[i]
                burntIdx = burntIdx + 1
                stixLineCoords[burntIdx] = offsetX + pt.x * scaleX
                burntIdx = burntIdx + 1
                stixLineCoords[burntIdx] = offsetY + pt.y * scaleY
            end
            for i = burntIdx + 1, #stixLineCoords do stixLineCoords[i] = nil end
            if burntIdx >= 4 then
                love.graphics.line(stixLineCoords)
            end
        end

        -- 2. Draw remaining intact Stix line from fuse head (or origin) to Marker
        local startPtIdx = math.max(1, fIdx)
        if startPtIdx < pathCount then
            local r, g, b = 0, 0.9, 1
            if self.isSlow then r, g, b = 1, 0.25, 0.1 end
            love.graphics.setColor(r, g, b, 1)
            love.graphics.setLineWidth(1.8 * scaleX)

            local intactIdx = 0
            for i = startPtIdx, pathCount do
                local pt = self.stixPath[i]
                intactIdx = intactIdx + 1
                stixLineCoords[intactIdx] = offsetX + pt.x * scaleX
                intactIdx = intactIdx + 1
                stixLineCoords[intactIdx] = offsetY + pt.y * scaleY
            end
            for i = intactIdx + 1, #stixLineCoords do stixLineCoords[i] = nil end
            if intactIdx >= 4 then
                love.graphics.line(stixLineCoords)
            end
        end

        -- 3. Fuse Warning Ember (hesitation warning at Stix origin)
        if self.fuseWarning and pathCount > 0 and not self.fuseActive then
            local oPt = self.stixPath[1]
            local ox = offsetX + oPt.x * scaleX
            local oy = offsetY + oPt.y * scaleY
            local pulse = 0.5 + 0.5 * math.sin(self.animTime * 25)
            love.graphics.setColor(1.0, 0.35, 0.0, 0.7 * pulse)
            love.graphics.circle("fill", ox, oy, 4.0 * scaleX)
            love.graphics.setColor(1.0, 0.9, 0.2, 0.95 * pulse)
            love.graphics.circle("fill", ox, oy, 2.0 * scaleX)
        end

        -- 4. Active Sizzling Fuse Flame traveling down the Stix
        if self.fuseActive and fIdx > 0 then
            local fPt = self.stixPath[fIdx]
            if fPt then
                local fx = offsetX + fPt.x * scaleX
                local fy = offsetY + fPt.y * scaleY
                local flicker = math.sin(self.animTime * 35)

                -- Outer heat aura
                love.graphics.setColor(1.0, 0.15, 0.0, 0.45 + 0.25 * flicker)
                love.graphics.circle("fill", fx, fy, (5.2 + flicker) * scaleX)

                -- Sizzling flame body
                love.graphics.setColor(1.0, 0.65, 0.1, 0.95)
                love.graphics.circle("fill", fx, fy, (3.4 + 0.5 * flicker) * scaleX)

                -- Intense white-hot core
                love.graphics.setColor(1.0, 1.0, 0.85, 1.0)
                love.graphics.circle("fill", fx, fy, 1.8 * scaleX)

                -- Radiating flying spark embers
                local spkOff1 = math.cos(self.animTime * 28) * 4.5 * scaleX
                local spkOff2 = math.sin(self.animTime * 32) * 4.5 * scaleX
                love.graphics.setColor(1.0, 0.9, 0.2, 0.85)
                love.graphics.circle("fill", fx + spkOff1, fy + spkOff2, 1.2 * scaleX)
                love.graphics.circle("fill", fx - spkOff2, fy + spkOff1, 1.0 * scaleX)
            end
        end
    end

    -- Draw player marker (diamond)
    local px = offsetX + self.x * scaleX
    local py = offsetY + self.y * scaleY
    local size = 3.3 * scaleX

    -- Respawn shield flashing & pulsing aura
    if self:isShielded() then
        local pulse = 1.0 + 0.25 * math.sin(self.animTime * 12)
        local alpha = 0.45 + 0.35 * math.sin(self.animTime * 14)
        love.graphics.setColor(0.0, 0.95, 1.0, alpha)
        love.graphics.setLineWidth(1.5 * scaleX)
        love.graphics.circle("line", px, py, size * 2.2 * pulse)
        love.graphics.setColor(1.0, 0.85, 0.2, alpha * 0.7)
        love.graphics.circle("line", px, py, size * 1.5 * pulse)
    end

    -- Marker diamond (reusable scratch table)
    local mr, mg, mb = 1, 1, 1
    if self.state == STATE_DRAWING then
        if self.isSlow then mr, mg, mb = 1, 0.4, 0.2 else mr, mg, mb = 0.2, 1, 1 end
    end
    love.graphics.setColor(mr, mg, mb, 1)

    DIAMOND_POLYGON[1] = px;        DIAMOND_POLYGON[2] = py - size
    DIAMOND_POLYGON[3] = px + size; DIAMOND_POLYGON[4] = py
    DIAMOND_POLYGON[5] = px;        DIAMOND_POLYGON[6] = py + size
    DIAMOND_POLYGON[7] = px - size; DIAMOND_POLYGON[8] = py

    love.graphics.polygon("fill", DIAMOND_POLYGON)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.polygon("line", DIAMOND_POLYGON)
end

return Player
