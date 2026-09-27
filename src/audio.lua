-- Audio synthesizer for Qix (1981 Arcade)
-- Generates authentic 8-bit procedural sound effects using Love2D SoundData

local Audio = {}
Audio.muted = false
Audio.volume = 0.7

local sampleRate = 22050
local sounds = {}
local activeLoops = {}

-- Helper to create synthesized sound sources
local function makeTone(freq, duration, waveType, decay)
    local numSamples = math.floor(sampleRate * duration)
    local soundData = love.sound.newSoundData(numSamples, sampleRate, 16, 1)
    decay = decay or true

    for i = 0, numSamples - 1 do
        local t = i / sampleRate
        local sample = 0
        if waveType == "square" then
            sample = (math.sin(2 * math.pi * freq * t) >= 0) and 0.25 or -0.25
        elseif waveType == "saw" then
            sample = ((t * freq) % 1.0 - 0.5) * 0.35
        elseif waveType == "triangle" then
            local phase = (t * freq) % 1.0
            sample = (phase < 0.5 and (phase * 4 - 1) or (3 - phase * 4)) * 0.3
        elseif waveType == "noise" then
            sample = (love.math.random() * 2 - 1) * 0.25
        else -- sine
            sample = math.sin(2 * math.pi * freq * t) * 0.3
        end

        if decay then
            local env = 1.0 - (i / numSamples)
            sample = sample * (env * env)
        end
        soundData:setSample(i, sample)
    end
    return love.audio.newSource(soundData, "static")
end

local function makeLoopTone(freq, waveType)
    local duration = 0.2
    local numSamples = math.floor(sampleRate * duration)
    local soundData = love.sound.newSoundData(numSamples, sampleRate, 16, 1)

    for i = 0, numSamples - 1 do
        local t = i / sampleRate
        local sample = 0
        if waveType == "square" then
            sample = (math.sin(2 * math.pi * freq * t) >= 0) and 0.20 or -0.20
        elseif waveType == "noise" then
            sample = (love.math.random() * 2 - 1) * 0.20
        else
            sample = math.sin(2 * math.pi * freq * t) * 0.25
        end
        soundData:setSample(i, sample)
    end
    local src = love.audio.newSource(soundData, "static")
    src:setLooping(true)
    return src
end

function Audio.init()
    sounds.tick = makeTone(650, 0.015, "square", true)
    sounds.start = makeTone(440, 0.20, "triangle", true)
    sounds.capture = makeTone(523, 0.25, "square", true)
    sounds.bonus = makeTone(880, 0.40, "triangle", true)

    -- Rising 8-bit victory arpeggio fanfare (C5 -> E5 -> G5 -> C6)
    local fanfareSamples = math.floor(sampleRate * 0.65)
    local fanfareData = love.sound.newSoundData(fanfareSamples, sampleRate, 16, 1)
    local notes = { 523.25, 659.25, 783.99, 1046.50 }
    for i = 0, fanfareSamples - 1 do
        local t = i / sampleRate
        local noteIdx = math.min(#notes, math.floor(t / 0.15) + 1)
        local freq = notes[noteIdx]
        local subT = (t % 0.15) / 0.15
        local env = 1.0 - subT
        local sample = math.sin(2 * math.pi * freq * t) * 0.28 * (env * env)
        fanfareData:setSample(i, sample)
    end
    sounds.fanfare = love.audio.newSource(fanfareData, "static")

    -- Death explosion sound
    local deathSamples = math.floor(sampleRate * 0.6)
    local deathData = love.sound.newSoundData(deathSamples, sampleRate, 16, 1)
    for i = 0, deathSamples - 1 do
        local env = 1.0 - (i / deathSamples)
        local noise = (love.math.random() * 2 - 1) * 0.35
        local rumble = math.sin(2 * math.pi * (80 * env) * (i / sampleRate)) * 0.3
        deathData:setSample(i, (noise + rumble) * env)
    end
    sounds.death = love.audio.newSource(deathData, "static")

    -- Continuous loop sounds
    sounds.drawSlow = makeLoopTone(90, "square")
    sounds.drawFast = makeLoopTone(190, "square")
    sounds.fuse = makeLoopTone(250, "noise")
end

function Audio.play(name)
    if Audio.muted or not sounds[name] then return end
    sounds[name]:stop()
    sounds[name]:setVolume(Audio.volume)
    sounds[name]:play()
end

function Audio.startDraw(isSlow)
    if Audio.muted then return end
    Audio.stopDraw()
    local src = isSlow and sounds.drawSlow or sounds.drawFast
    if src then
        src:setVolume(Audio.volume * 0.6)
        src:play()
        activeLoops.draw = src
    end
end

function Audio.stopDraw()
    if activeLoops.draw then
        activeLoops.draw:stop()
        activeLoops.draw = nil
    end
end

function Audio.startFuse()
    if Audio.muted or activeLoops.fuse then return end
    if sounds.fuse then
        sounds.fuse:setVolume(Audio.volume * 0.8)
        sounds.fuse:play()
        activeLoops.fuse = sounds.fuse
    end
end

function Audio.stopFuse()
    if activeLoops.fuse then
        activeLoops.fuse:stop()
        activeLoops.fuse = nil
    end
end

function Audio.stopAll()
    Audio.stopDraw()
    Audio.stopFuse()
    for _, s in pairs(sounds) do
        s:stop()
    end
end

function Audio.toggleMute()
    Audio.muted = not Audio.muted
    if Audio.muted then
        Audio.stopAll()
    end
    return Audio.muted
end

return Audio
