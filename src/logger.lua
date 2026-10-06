-- ==============================================================================
-- QIX - High Reliability Logging & Diagnostics Subsystem
-- Dual-target logging (stdout + file), periodic health telemetry & crash catcher.
-- ==============================================================================

local Logger = {}

Logger.logFile = nil
Logger.logPath = "log.txt"
Logger.saveLogPath = "qix_debug.log"
Logger.lastHeartbeat = 0
Logger.heartbeatInterval = 15 -- seconds
Logger.startTime = 0
Logger.history = {}
Logger.MAX_HISTORY = 40

Logger.breadcrumbs = {}
Logger.MAX_BREADCRUMBS = 60

local function getTimestamp()
    local t = os.time()
    return os.date("%Y-%m-%d %H:%M:%S", t)
end

function Logger.breadcrumb(tag, action, ...)
    local desc = (select("#", ...) > 0) and string.format(action, ...) or tostring(action)
    local uptime = love.timer and (love.timer.getTime() - Logger.startTime) or 0
    local bc = string.format("[%07.2fs] [%s] %s", uptime, tag, desc)
    table.insert(Logger.breadcrumbs, bc)
    if #Logger.breadcrumbs > Logger.MAX_BREADCRUMBS then
        table.remove(Logger.breadcrumbs, 1)
    end
end

function Logger.dumpBreadcrumbs()
    return table.concat(Logger.breadcrumbs, "\n")
end

function Logger.getOSMemory()
    local rssMb = nil
    local availMb = nil

    -- 1. Read process Resident Set Size (RSS) from Linux /proc/self/statm
    local fStatm = io.open("/proc/self/statm", "r")
    if fStatm then
        local content = fStatm:read("*all")
        fStatm:close()
        local _, rssPages = content:match("(%d+)%s+(%d+)")
        if rssPages then
            rssMb = (tonumber(rssPages) * 4096) / (1024 * 1024)
        end
    end

    -- 2. Read available system RAM from Linux /proc/meminfo
    local fMem = io.open("/proc/meminfo", "r")
    if fMem then
        local content = fMem:read("*all")
        fMem:close()
        local availKb = content:match("MemAvailable:%s+(%d+)%s+kB") or content:match("MemFree:%s+(%d+)%s+kB")
        if availKb then
            availMb = tonumber(availKb) / 1024
        end
    end

    return rssMb, availMb
end

function Logger.init()
    Logger.startTime = love.timer and love.timer.getTime() or 0

    print(string.format("\n==================================================\n[SESSION START] %s | QIX Arcade R36S\n==================================================", getTimestamp()))
    io.stdout:flush()

    Logger.info("SYSTEM", "Logger initialized. OS: %s | Love: %s", love.system.getOS(), love._version)
    local osRss, osAvail = Logger.getOSMemory()
    if osRss or osAvail then
        Logger.info("SYSTEM", "Linux Memory: Process RSS: %s | Device Available RAM: %s",
            osRss and string.format("%.1f MB", osRss) or "N/A",
            osAvail and string.format("%.1f MB", osAvail) or "N/A")
    end

    if love.graphics then
        local renderer, version, vendor, device = love.graphics.getRendererInfo()
        Logger.info("GRAPHICS", "Renderer: %s | Version: %s | Vendor: %s | Device: %s", renderer, version, vendor, device)
        local limits = love.graphics.getSystemLimits()
        Logger.info("GRAPHICS", "Max Texture Size: %d | MultiCanvas: %s", limits.texturesize or 0, tostring(limits.multicanvas))
    end
end

function Logger.formatLog(level, tag, msg, ...)
    local formatted = (select("#", ...) > 0) and string.format(msg, ...) or tostring(msg)
    local uptime = love.timer and (love.timer.getTime() - Logger.startTime) or 0
    local memKb = collectgarbage("count")
    return string.format("[%s] [%07.2fs] [%5.1f MB] [%s/%s] %s",
        getTimestamp(), uptime, memKb / 1024, level, tag, formatted)
end

function Logger.write(line)
    -- Record in in-memory rolling flight recorder
    table.insert(Logger.history, line)
    if #Logger.history > Logger.MAX_HISTORY then
        table.remove(Logger.history, 1)
    end

    -- Output to stdout (captured by PortMaster pipe to log.txt)
    print(line)
    io.stdout:flush()
end

function Logger.dumpHistory()
    return table.concat(Logger.history, "\n")
end

function Logger.info(tag, msg, ...)
    local line = Logger.formatLog("INFO", tag, msg, ...)
    Logger.write(line)
end

function Logger.warn(tag, msg, ...)
    local line = Logger.formatLog("WARN", tag, msg, ...)
    Logger.write(line)
end

function Logger.error(tag, msg, ...)
    local line = Logger.formatLog("ERROR", tag, msg, ...)
    Logger.write(line)
end

function Logger.logImageOp(status, kind, name, w, h, sizeBytes, durationSec, extra)
    local szStr = sizeBytes and string.format("%.2f MB", sizeBytes / (1024 * 1024)) or "? MB"
    local durStr = durationSec and string.format("%.0fms", durationSec * 1000) or "?ms"
    local dimStr = (w and h and w > 0 and h > 0) and string.format("%dx%d", w, h) or "unknown"
    if status == "LOAD" then
        Logger.info(kind, "Image loaded: %s (Res: %s | Size: %s | Time: %s)%s", name, dimStr, szStr, durStr, extra and (" | " .. extra) or "")
    elseif status == "SKIP" or status == "REJECT" then
        Logger.warn(kind, "Image %s: %s (Res: %s | Size: %s)%s", status, name, dimStr, szStr, extra and (" | " .. extra) or "")
    elseif status == "ERROR" then
        Logger.error(kind, "Image error: %s (Res: %s | Size: %s)%s", name, dimStr, szStr, extra and (" | " .. extra) or "")
    end
end

function Logger.heartbeat(state, level, score, lives, extra)
    local now = love.timer and love.timer.getTime() or 0
    if now - Logger.lastHeartbeat < Logger.heartbeatInterval then
        return
    end
    Logger.lastHeartbeat = now

    local luaMemMb = collectgarbage("count") / 1024
    local fps = love.timer and love.timer.getFPS() or 0
    local texMemMb = 0
    local drawCalls = 0
    local imagesCount = 0
    local canvasesCount = 0

    if love.graphics and love.graphics.getStats then
        local stats = love.graphics.getStats()
        texMemMb = (stats.texturememory or 0) / (1024 * 1024)
        drawCalls = stats.drawcalls or 0
        imagesCount = stats.images or 0
        canvasesCount = stats.canvases or 0
    end

    local osRss, osAvail = Logger.getOSMemory()
    local osMemStr = ""
    if osRss then
        osMemStr = string.format(" | RSS: %5.1fMB", osRss)
        if osAvail then
            osMemStr = osMemStr .. string.format(" | Avail: %5.1fMB", osAvail)
        end
        if osRss > 280 then
            Logger.warn("MEMORY", "High process RSS memory (%.1f MB)! Risk of memory pressure on RK3326.", osRss)
        end
        if osAvail and osAvail < 70 then
            Logger.warn("MEMORY", "Low device available RAM (%.1f MB)! Approaching system limits.", osAvail)
        end
    end

    local detail = string.format("State: %-10s | Lvl: %2d | Score: %6d | Lives: %d | FPS: %2d | LuaMem: %5.1fMB | VRAM: %5.1fMB%s | Img: %2d | Canv: %d | DC: %2d%s",
        state or "UNKNOWN", level or 0, score or 0, lives or 0, fps, luaMemMb, texMemMb, osMemStr, imagesCount, canvasesCount, drawCalls,
        extra and (" | " .. extra) or "")
    Logger.info("HEARTBEAT", detail)
end

-- ==============================================================================
-- Crash Handler (Custom love.errorhandler)
-- Formats stack traces, saves dumps to log files, and draws a clean error screen.
-- ==============================================================================
function Logger.installErrorHandler()
    function love.errorhandler(msg)
        msg = tostring(msg)
        local trace = debug.traceback("Error: " .. msg, 2)

        local banner = string.rep("=", 60)
        local crashReport = string.format("\n%s\n[CRITICAL ERROR CRASH REPORT]\nTimestamp: %s\n%s\nTraceback:\n%s\n%s\n",
            banner, getTimestamp(), banner, trace, banner)

        -- Write immediately to all outputs
        Logger.write(crashReport)

        local osRss, osAvail = Logger.getOSMemory()
        if osRss or osAvail then
            Logger.error("CRASH_DUMP", "OS Memory: Process RSS: %s | Device Available: %s",
                osRss and string.format("%.1f MB", osRss) or "N/A",
                osAvail and string.format("%.1f MB", osAvail) or "N/A")
        end

        if love.graphics and love.graphics.getStats then
            local stats = love.graphics.getStats()
            Logger.error("CRASH_DUMP", "VRAM: %.2f MB | Images: %d | Canvases: %d",
                (stats.texturememory or 0) / (1024 * 1024), stats.images or 0, stats.canvases or 0)
        end
        Logger.error("CRASH_DUMP", "Lua GC Memory: %.2f MB", collectgarbage("count") / 1024)

        local historyDump = Logger.dumpHistory()
        if historyDump and #historyDump > 0 then
            Logger.write(string.format("--- Recent Engine Activity (Last %d Events) ---\n%s\n%s\n", #Logger.history, historyDump, banner))
        end

        local breadcrumbDump = Logger.dumpBreadcrumbs()
        if breadcrumbDump and #breadcrumbDump > 0 then
            Logger.write(string.format("--- Recent Engine Breadcrumbs (Last %d Actions) ---\n%s\n%s\n", #Logger.breadcrumbs, breadcrumbDump, banner))
        end

        if not love.window or not love.graphics or not love.event then
            return
        end

        if not love.graphics.isCreated() or not love.window.isOpen() then
            local success, _ = pcall(love.window.setMode, 640, 480)
            if not success then return end
        end

        -- Reset graphics states
        love.audio.stop()
        love.graphics.reset()
        local font = love.graphics.newFont(12)
        love.graphics.setFont(font)
        love.graphics.setColor(1, 1, 1, 1)

        local function drawCrash()
            love.graphics.clear(0.08, 0.03, 0.05, 1)
            love.graphics.setColor(1, 0.2, 0.3, 1)
            love.graphics.rectangle("line", 16, 16, 608, 448, 6, 6)
            love.graphics.printf("★ QIX ARCADE: UNEXPECTED EXCEPTION ★", 24, 28, 592, "center")

            love.graphics.setColor(0.9, 0.9, 0.95, 1)
            love.graphics.printf("A diagnostic crash log was written to:\nports/qix/log.txt & saves/qix_arcade/qix_debug.log", 24, 52, 592, "center")

            love.graphics.setColor(1, 0.85, 0.2, 1)
            love.graphics.line(32, 88, 608, 88)

            love.graphics.setColor(1, 0.4, 0.4, 1)
            love.graphics.printf(msg, 32, 98, 576, "left")

            love.graphics.setColor(0.7, 0.75, 0.85, 1)
            local sanitizedTrace = trace:gsub("\t", "  ")
            love.graphics.printf(sanitizedTrace, 32, 140, 576, "left")

            love.graphics.setColor(0.2, 1.0, 0.5, 1)
            love.graphics.printf("PRESS (A), (B), START OR ESC TO SAFELY EXIT", 24, 436, 592, "center")
            love.graphics.present()
        end

        while true do
            love.event.pump()
            for e, a, b, c in love.event.poll() do
                if e == "quit" then
                    return 1
                elseif e == "keypressed" and (a == "escape" or a == "return" or a == "space" or a == "a" or a == "b") then
                    return 1
                elseif e == "gamepadpressed" and (b == "a" or b == "b" or b == "start") then
                    return 1
                end
            end
            drawCrash()
            love.timer.sleep(0.05)
        end
    end
end

return Logger
