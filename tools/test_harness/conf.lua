function love.conf(t)
    t.identity = "qix_test_harness"
    t.version = "11.5"
    t.console = true
    t.window.title = "Qix Automated Test Harness"
    t.window.width = 640
    t.window.height = 480
    t.window.resizable = false
    t.window.vsync = 0
    t.modules.audio = true
    t.modules.sound = true
    t.modules.graphics = true
    t.modules.image = true
    t.modules.math = true
    t.modules.timer = true
    t.modules.window = true
    t.modules.filesystem = true
end
