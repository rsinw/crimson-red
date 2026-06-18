-- music_mgr.lua — Manages all music with per-track fade in/out

local M = {}

local FADE_SPEED = 1.0  -- volume units per second (~0.7s for a full fade at vol 0.7)

local TRACKS = {
    title1 = { path="assets/sounds/VistulaShort.mp3",          baseVol=0.6, pitch=0.3 },
    title2 = { path="assets/sounds/jaggedrocksv1.ogg",         baseVol=0.8, pitch=0.3 },
    forest = { path="assets/music/forest.ogg",                 baseVol=0.7 },
    battle = { path="assets/music/Battle in the winter.mp3",   baseVol=0.7 },
}

-- Per-track runtime state: { src, currentVol, targetVol, baseVol }
local state = {}

local function getOrLoad(name)
    if state[name] then return state[name] end
    local def = TRACKS[name]
    if not def then return nil end
    local ok, src = pcall(love.audio.newSource, def.path, "stream")
    if not ok then return nil end
    src:setLooping(true)
    src:setVolume(0)
    if def.pitch then src:setPitch(def.pitch) end
    state[name] = { src=src, currentVol=0, targetVol=0, baseVol=def.baseVol }
    return state[name]
end

-- Call from love.update every frame
function M.update(dt)
    for _, s in pairs(state) do
        if s.currentVol ~= s.targetVol then
            if s.currentVol < s.targetVol then
                s.currentVol = math.min(s.targetVol, s.currentVol + FADE_SPEED * dt)
            else
                s.currentVol = math.max(s.targetVol, s.currentVol - FADE_SPEED * dt)
            end
            s.src:setVolume(s.currentVol)
            if s.currentVol == 0 then s.src:stop() end
        end
    end
end

-- Fade in all tracks in the group; fade out everything else
function M.playGroup(names)
    local active = {}
    for _, name in ipairs(names) do active[name] = true end

    for _, name in ipairs(names) do
        local s = getOrLoad(name)
        if s then
            s.targetVol = s.baseVol
            if not s.src:isPlaying() then
                s.currentVol = 0
                s.src:setVolume(0)
                s.src:play()
            end
        end
    end

    for name, s in pairs(state) do
        if not active[name] then
            s.targetVol = 0
        end
    end
end

-- Convenience: single track
function M.play(name)
    M.playGroup({ name })
end

-- Fade out all tracks
function M.stop()
    for _, s in pairs(state) do
        s.targetVol = 0
    end
end

return M
