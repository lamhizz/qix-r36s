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

local function getTimestamp()
    local t = os.time()
    return os.date("%Y-%m-%d %H:%M:%S", t)
end

function Logger.init()
    Logger.startTime = love.timer and love.timer.getTime() or 0

    -- Try opening log.txt in root game directory (append mode)
    pcall(function()
        local f = io.open(Logger.logPath, "a")
        if f then
            f:write(string.format("\n==================================================\n[SESSION START] %s | QIX Arcade R36S\n==================================================\n", getTimestamp()))
            f:flush()
            Logger.logFile = f
        end
    end)

    -- Also append to Love2D saves directory
    pcall(function()
        love.filesystem.append(Logger.saveLogPath, string.format("\n[SESSION START] %s\n", getTimestamp()))
    end)

    Logger.info("SYSTEM", "Logger initialized. OS: %s | Love: %s", love.system.getOS(), love._version)
    if love.graphics then
        local renderer, version, vendor, device = love.graphics.getRendererInfo()
        Logger.info("GRAPHICS", "Renderer: %s | Version: %s | Vendor: %s | Device: %s", renderer, version, vendor, device)
        local limits = love.graphics.getSystemLimits()
        Logger.info("GRAPHICS", "Max Texture Size: %d | MultiCanvas: %s", limits.texturesize or 0, tostring(limits.multicanvas))
    end

    Logger.installNativeSignalHandler()
end

function Logger.installNativeSignalHandler()
    pcall(function()
        local ok, ffi = pcall(require, "ffi")
        if not ok or not ffi then return end

        ffi.cdef[[
            typedef void (*sighandler_t)(int);
            sighandler_t signal(int signum, sighandler_t handler);
            int backtrace(void **buffer, int size);
            void backtrace_symbols_fd(void *const *buffer, int size, int fd);
            int write(int fd, const void *buf, size_t count);
            void _exit(int status);
        ]]

        local onSignal = ffi.cast("sighandler_t", function(sig)
            local msg = string.format("\n==================================================\n[FATAL NATIVE SIGNAL %d (SIGSEGV/CRASH)]\nEngine crashed at native C/C++ driver level!\n--- C Stack Backtrace ---\n", tonumber(sig))
            ffi.C.write(1, msg, #msg)
            local buf = ffi.new("void*[64]")
            local frames = ffi.C.backtrace(buf, 64)
            ffi.C.backtrace_symbols_fd(buf, frames, 1)
            local endMsg = "==================================================\n"
            ffi.C.write(1, endMsg, #endMsg)
            ffi.C._exit(128 + tonumber(sig))
        end)

        ffi.C.signal(11, onSignal) -- SIGSEGV
        ffi.C.signal(4, onSignal)  -- SIGILL
        ffi.C.signal(7, onSignal)  -- SIGBUS
        ffi.C.signal(8, onSignal)  -- SIGFPE
        Logger.info("SYSTEM", "Native crash signal handler installed (SIGSEGV, SIGBUS, SIGFPE, SIGILL).")
    end)
end

function Logger.formatLog(level, tag, msg, ...)
    local formatted = (select("#", ...) > 0) and string.format(msg, ...) or tostring(msg)
    local uptime = love.timer and (love.timer.getTime() - Logger.startTime) or 0
    local memKb = collectgarbage("count")
    return string.format("[%s] [%07.2fs] [%5.1f MB] [%s/%s] %s",
        getTimestamp(), uptime, memKb / 1024, level, tag, formatted)
end

function Logger.write(line)
    -- 1. Output to stdout (captured by PortMaster tee to log.txt)
    print(line)
    io.stdout:flush()

    -- 2. Output to direct file handle if open
    if Logger.logFile then
        pcall(function()
            Logger.logFile:write(line .. "\n")
            Logger.logFile:flush()
        end)
    end

    -- 3. Output to Love save folder
    pcall(function()
        love.filesystem.append(Logger.saveLogPath, line .. "\n")
    end)
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

    local detail = string.format("State: %-10s | Lvl: %2d | Score: %6d | Lives: %d | FPS: %2d | LuaMem: %5.1fMB | VRAM: %5.1fMB | Img: %2d | Canv: %d | DC: %2d%s",
        state or "UNKNOWN", level or 0, score or 0, lives or 0, fps, luaMemMb, texMemMb, imagesCount, canvasesCount, drawCalls,
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

        if love.graphics and love.graphics.getStats then
            local stats = love.graphics.getStats()
            Logger.error("CRASH_DUMP", "VRAM: %.2f MB | Images: %d | Canvases: %d",
                (stats.texturememory or 0) / (1024 * 1024), stats.images or 0, stats.canvases or 0)
        end
        Logger.error("CRASH_DUMP", "Lua GC Memory: %.2f MB", collectgarbage("count") / 1024)

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
