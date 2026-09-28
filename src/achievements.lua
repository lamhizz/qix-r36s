-- ==============================================================================
-- QIX - Achievements & Badges System
-- Tracks 7 arcade milestones with permanent disk saves, popups, and badges gallery.
-- ==============================================================================

local Achievements = {}
local Audio = require("audio")

Achievements.DATA = {
    {
        id = "first_contact",
        title = "FIRST CONTACT",
        badge = "ROUND 1",
        desc = "Clear Round 1 and unveil your first hidden artwork.",
        unlocked = false
    },
    {
        id = "deep_cut",
        title = "DEEP CUT",
        badge = "SLOW 20%",
        desc = "Claim 20% or more of the screen in a single slow-draw slice.",
        unlocked = false
    },
    {
        id = "divide_conquer",
        title = "DIVIDE & CONQUER",
        badge = "SPLIT-QIX",
        desc = "Slice between and separate dual roaming Qixes (Level 3+).",
        unlocked = false
    },
    {
        id = "century_club",
        title = "CENTURY CLUB",
        badge = "100K PTS",
        desc = "Achieve a score of 100,000 points or more in a single run.",
        unlocked = false
    },
    {
        id = "master_artist",
        title = "MASTER ARTIST",
        badge = "90% CLAIM",
        desc = "Uncover 90% or more of the playfield in any single round.",
        unlocked = false
    },
    {
        id = "veteran_survivor",
        title = "VETERAN SURVIVOR",
        badge = "LEVEL 5",
        desc = "Survive the gauntlet and reach Level 5.",
        unlocked = false
    },
    {
        id = "art_connoisseur",
        title = "ART CONNOISSEUR",
        badge = "5 ARTWORKS",
        desc = "Uncover and view 5 distinct background artworks.",
        unlocked = false
    }
}

Achievements.unlockedMap = {}
Achievements.artViewed = {}
Achievements.toasts = {}

function Achievements.init()
    Achievements.load()
end

function Achievements.load()
    if love.filesystem.getInfo("achievements.txt") then
        local content = love.filesystem.read("achievements.txt")
        if content then
            for line in content:gmatch("[^\r\n]+") do
                local key, val = line:match("^([^=]+)=(.*)$")
                if key == "badge" and val then
                    Achievements.unlockedMap[val] = true
                elseif key == "art" and val then
                    Achievements.artViewed[val] = true
                end
            end
        end
    end

    for _, badge in ipairs(Achievements.DATA) do
        if Achievements.unlockedMap[badge.id] then
            badge.unlocked = true
        end
    end
end

function Achievements.save()
    local lines = {}
    for id, _ in pairs(Achievements.unlockedMap) do
        table.insert(lines, "badge=" .. id)
    end
    for artPath, _ in pairs(Achievements.artViewed) do
        table.insert(lines, "art=" .. artPath)
    end
    love.filesystem.write("achievements.txt", table.concat(lines, "\n"))
end

function Achievements.unlock(id)
    if Achievements.unlockedMap[id] then
        return false -- Already unlocked
    end

    Achievements.unlockedMap[id] = true
    for _, badge in ipairs(Achievements.DATA) do
        if badge.id == id then
            badge.unlocked = true
            Achievements.save()

            -- Queue celebratory on-screen toast notification
            table.insert(Achievements.toasts, {
                title = badge.title,
                badge = badge.badge,
                desc = badge.desc,
                timer = 4.0,
                maxTimer = 4.0
            })

            Audio.play("bonus")
            return true
        end
    end
    return false
end

function Achievements.recordArtViewed(artPath)
    if not artPath then return end
    if not Achievements.artViewed[artPath] then
        Achievements.artViewed[artPath] = true
        Achievements.save()

        local count = 0
        for _ in pairs(Achievements.artViewed) do
            count = count + 1
        end

        if count >= 5 then
            Achievements.unlock("art_connoisseur")
        end
    end
end

function Achievements.getUnlockedCount()
    local count = 0
    for _, badge in ipairs(Achievements.DATA) do
        if badge.unlocked then count = count + 1 end
    end
    return count
end

function Achievements.update(dt)
    for i = #Achievements.toasts, 1, -1 do
        local toast = Achievements.toasts[i]
        toast.timer = toast.timer - dt
        if toast.timer <= 0 then
            table.remove(Achievements.toasts, i)
        end
    end
end

function Achievements.drawToasts(fontMid, fontSmall)
    if #Achievements.toasts == 0 then return end
    local toast = Achievements.toasts[1]

    local alpha = 1.0
    if toast.timer < 0.5 then
        alpha = toast.timer / 0.5
    elseif toast.timer > (toast.maxTimer - 0.4) then
        alpha = (toast.maxTimer - toast.timer) / 0.4
    end

    local boxW = 460
    local boxH = 46
    local boxX = math.floor((640 - boxW) * 0.5)
    local boxY = 36

    -- Toast backdrop
    love.graphics.setColor(0.04, 0.06, 0.12, 0.92 * alpha)
    love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 8, 8)

    -- Toast border
    love.graphics.setColor(1.0, 0.85, 0.2, 0.95 * alpha)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 8, 8)

    -- Icon & Text
    love.graphics.setFont(fontSmall or love.graphics.getFont())
    love.graphics.setColor(0.2, 1.0, 0.4, 1.0 * alpha)
    love.graphics.print("★ ACHIEVEMENT UNLOCKED! ★", boxX + 16, boxY + 8)

    love.graphics.setFont(fontMid or love.graphics.getFont())
    love.graphics.setColor(1, 1, 1, 1.0 * alpha)
    local displayText = string.format("[%s] %s", toast.badge or "MEDAL", toast.title)
    love.graphics.print(displayText, boxX + 16, boxY + 22)
end

return Achievements
