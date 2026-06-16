-- screens/encounter.lua — Encounter/battle screen module
-- ECS battle system lifted from prototype/encounter/main.lua

local common = require("common")

local VW    = common.VW
local VH    = common.VH
local SCALE = VH / 300

local GRAVITY       = 9.8 * 30 * SCALE
local MASS          = 70
local FRICTION      = 0.9
local BATTLE_LINE_Y = VH * 0.2
local GCD_DURATION  = 1.0

local ENEMY_DANGER = { skeleton = 3 }

-- ============================================================================
-- MODULE STATE — reset each onEnter
-- ============================================================================

local world = {}    -- ECS component pools
local battle = {    -- persistent asset refs + per-encounter combat state
    font=nil, smallFont=nil, battlebg=nil,
    music1=nil, music2=nil, bell=nil,
}

-- Animation/icon data — loaded once, persists across onEnter
local animDB     = {}
local iconImages = {}
local assetsLoaded = false

local canvas_ref, postfx_ref, switchFn
local saveData_ref, slot_ref

-- ============================================================================
-- WORLD INIT
-- ============================================================================

local function initWorld()
    world = {
        entities     = {},  nextId = 1,
        position     = {},  size        = {},  facing      = {},
        physics      = {},  moveTarget  = {},  entityTarget = {},
        side         = {},  stats       = {},  locks        = {},
        stagger      = {},  skills      = {},  effects_comp = {},
        bar          = {},  tintColor   = {},  threatMap    = {},
        anim         = {},  hasEntered  = {},  deathState   = {},
        isRanged     = {},  targetSide  = {},  dangerLevel = {},
    }
    function world:new()
        local id = self.nextId; self.nextId = id + 1
        self.entities[id] = true; return id
    end
    function world:destroy(id)
        self.entities[id] = nil
        for _, pool in pairs(self) do
            if type(pool) == "table" then pool[id] = nil end
        end
    end
end

-- Partial reset — preserves asset refs (font, battlebg, audio) across onEnter calls
local function initBattle(c, pfx)
    battle.vfx            = {shake=0, chroma=0, zoom=1.0, zoomTarget=1.0, zoomX=VW/2, zoomY=VH/2}
    battle.bloodParticles  = {}
    battle.healParticles   = {}
    battle.selCircleScales = {}
    battle.canvas          = c
    battle.postfx          = pfx
    battle.partyIds        = {}
    battle.selectedUnit    = nil
    battle.deadSlots       = {}
    battle.iconScales      = {1.0, 1.0, 1.0, 1.0}
    battle.victoryTimer    = nil
    battle.victoryDelay    = nil
    battle.hoveredUnit     = nil
    battle.pressedUnit     = nil
    -- font/smallFont/battlebg/music1/music2/bell preserved from previous onEnter
end

-- ============================================================================
-- STAT HELPERS
-- ============================================================================

local function newStat(base)  return {base=base, add=0, mult=1} end
local function statGet(s)     return (s.base * s.mult) + s.add end

local function newStats(hp, atk, def, crit)
    return {
        HP          = newStat(hp   or 100),
        maxHP       = newStat(hp   or 100),
        RES         = newStat(1.0),
        BOOST       = newStat(1.0),
        DEF         = newStat(def  or 5),
        ATK         = newStat(atk  or 10),
        CRIT        = newStat(crit or 0.10),
        CRIT_DEF    = newStat(0.05),
        MOVE_SPEED  = newStat(2.5),
        ATK_SPEED   = newStat(1.0),
        STAGGER_RES = newStat(1.0),
        MAX_STAGGER = newStat(50),
        STAGGER_DUR = newStat(2),
    }
end

local function statsFromSave(ss)
    return {
        HP          = newStat(ss.maxHP or 100),
        maxHP       = newStat(ss.maxHP or 100),
        RES         = newStat(ss.RES   or 1.0),
        BOOST       = newStat(ss.BOOST or 1.0),
        DEF         = newStat(ss.DEF   or 5),
        ATK         = newStat(ss.ATK   or 10),
        CRIT        = newStat(ss.CRIT  or 0.10),
        CRIT_DEF    = newStat(ss.CRITDEF  or 0.05),
        MOVE_SPEED  = newStat(2.5),
        ATK_SPEED   = newStat(ss.ATKSPD  or 1.0),
        STAGGER_RES = newStat(ss.STAGGERres or 1.0),
        MAX_STAGGER = newStat(ss.maxSTAGGER or 50),
        STAGGER_DUR = newStat(ss.STAGGERdur or 2),
    }
end

-- ============================================================================
-- ANIM HELPERS
-- ============================================================================

local function loadAnim(name, path, frames, fw, fh, defaultScale)
    local ok, img = pcall(love.graphics.newImage, path)
    if not ok then
        print("[anim] missing: " .. path)
        animDB[name] = {img=nil, frames=frames, fw=fw, fh=fh,
                        defaultScale=defaultScale or 1.0, quads={}}
        return
    end
    local quads = {}
    for i = 0, frames-1 do
        quads[i] = love.graphics.newQuad(i*fw, 0, fw, fh, img:getWidth(), img:getHeight())
    end
    animDB[name] = {img=img, frames=frames, fw=fw, fh=fh,
                    defaultScale=defaultScale or 1.0, quads=quads}
end

local function newAnimInst(name, frameLen, repeating, startActive)
    return {name=name, timer=0, frameLength=frameLen,
            repeat_=repeating, active=startActive or false}
end

-- ============================================================================
-- ASSET LOADING (once per session)
-- ============================================================================

local function loadAssets(c, pfx)
    if assetsLoaded then
        battle.font      = battle.font      or common.loadFont(16)
        battle.smallFont = battle.smallFont or common.loadFont(10)
        return
    end
    assetsLoaded = true

    battle.font      = common.loadFont(16)
    battle.smallFont = common.loadFont(10)

    local ok, bg = pcall(love.graphics.newImage, "assets/images/battlebg.png")
    battle.battlebg = ok and bg or nil

    local C = "assets/characters/"
    local E = "assets/enemies/"
    loadAnim("KnightIdle",    C.."Knight/Idle.png",      10, 135, 135, 1.0)
    loadAnim("KnightMove",    C.."Knight/Run.png",         6, 135, 135, 1.0)
    loadAnim("KnightAttack1", C.."Knight/Attack1.png",     4, 135, 135, 1.0)
    loadAnim("KnightAttack2", C.."Knight/Attack2.png",     4, 135, 135, 1.0)
    loadAnim("KnightTakeHit", C.."Knight/Take Hit.png",    3, 135, 135, 1.0)
    loadAnim("KnightDeath",   C.."Knight/Death.png",       9, 135, 135, 1.0)

    loadAnim("BrigandIdle",    C.."Brigand/Idle.png",     10, 126, 126, 1.0)
    loadAnim("BrigandMove",    C.."Brigand/Run.png",       8, 126, 126, 1.0)
    loadAnim("BrigandAttack1", C.."Brigand/Attack1.png",   7, 126, 126, 1.0)
    loadAnim("BrigandDeath",   C.."Brigand/Death.png",    11, 126, 126, 1.0)

    loadAnim("SkeletonIdle",   E.."Skeleton/Idle.png",     4, 150, 150, 0.75)
    loadAnim("SkeletonMove",   E.."Skeleton/Walk.png",     4, 150, 150, 0.75)
    loadAnim("SkeletonAttack", E.."Skeleton/Attack.png",   8, 150, 150, 0.75)
    loadAnim("SkeletonDeath",  E.."Skeleton/Death.png",    4, 150, 150, 0.75)

    loadAnim("BatIdle",   E.."Bat/Flight.png",  8, 150, 150, 0.75)
    loadAnim("BatAttack", E.."Bat/Attack.png",  8, 150, 150, 0.75)
    loadAnim("BatDeath",  E.."Bat/Death.png",   4, 150, 150, 0.75)

    loadAnim("ImpIdle",   E.."Imp/Idle.png",    4, 150, 150, 0.75)
    loadAnim("ImpMove",   E.."Imp/Move.png",    8, 150, 150, 0.75)
    loadAnim("ImpAttack", E.."Imp/Attack.png",  8, 150, 150, 0.75)
    loadAnim("ImpDeath",  E.."Imp/Death.png",   4, 150, 150, 0.75)

    loadAnim("MushroomIdle",   E.."Mushroom/Idle.png",    4, 150, 150, 0.75)
    loadAnim("MushroomMove",   E.."Mushroom/Move.png",    8, 150, 150, 0.75)
    loadAnim("MushroomAttack", E.."Mushroom/Attack.png",  8, 150, 150, 0.75)
    loadAnim("MushroomDeath",  E.."Mushroom/Death.png",   4, 150, 150, 0.75)

    loadAnim("NomadIdle",    C.."Nomad/Idle.png",     8, 250, 250, 0.54)
    loadAnim("NomadMove",    C.."Nomad/Run.png",       8, 250, 250, 0.54)
    loadAnim("NomadAttack1", C.."Nomad/Attack1.png",   8, 250, 250, 0.54)
    loadAnim("NomadAttack2", C.."Nomad/Attack2.png",   8, 250, 250, 0.54)
    loadAnim("NomadDeath",   C.."Nomad/Death.png",     7, 250, 250, 0.54)

    for i = 1, 54 do
        local ok2, img = pcall(love.graphics.newImage, "assets/icons/skill_icons"..i..".png")
        iconImages[i] = ok2 and img or nil
    end

    local ok1, m1 = pcall(love.audio.newSource, "assets/sounds/VistulaShort.mp3", "stream")
    if ok1 then battle.music1 = m1; m1:setLooping(true); m1:setVolume(0.6); m1:setPitch(0.3) end
    local ok2b, m2 = pcall(love.audio.newSource, "assets/sounds/jaggedrocksv1.ogg", "stream")
    if ok2b then battle.music2 = m2; m2:setLooping(true); m2:setVolume(0.8); m2:setPitch(0.3) end
    local okb, bell = pcall(love.audio.newSource, "assets/sounds/churchbell.ogg", "static")
    if okb then battle.bell = bell; bell:setVolume(0.7) end
end

-- ============================================================================
-- VFX
-- ============================================================================

local function triggerActivationVFX(casterId)
    local vfx = battle.vfx
    vfx.shake = math.min(vfx.shake+6, 20); vfx.chroma = math.min(vfx.chroma+2, 12)
    vfx.zoomTarget = 1.12
    local p = world.position[casterId]
    if p then vfx.zoomX, vfx.zoomY = p.x, p.y end
end

local function triggerHitVFX(tgtId)
    local vfx = battle.vfx
    vfx.shake = math.min(vfx.shake+8, 20); vfx.chroma = math.min(vfx.chroma+3, 12)
    vfx.zoomTarget = 1.10
    local p = world.position[tgtId]
    if p then vfx.zoomX, vfx.zoomY = p.x, p.y end
end

-- ============================================================================
-- BLOOD PARTICLES
-- ============================================================================

local function spawnBlood(srcId, tgtId, isCrit)
    local sp, tp, ts = world.position[srcId], world.position[tgtId], world.size[tgtId]
    if not (sp and tp and ts) then return end
    local dirX = (tp.x > sp.x) and 1 or -1
    local floor = tp.y + ts.h / 2
    local count = isCrit and 40 or 20
    for _ = 1, count do
        table.insert(battle.bloodParticles, {
            x=tp.x, y=tp.y,
            vx = dirX * (30 + math.random(0, 59)) * SCALE,
            vy = -(50 + math.random(0, 49)) * SCALE,
            floor=floor, timer=10.0, floorTimer=1.0, onFloor=false,
        })
    end
end

local function updateBloodParticles(dt)
    local bp = battle.bloodParticles
    for i = #bp, 1, -1 do
        local p = bp[i]
        p.timer = p.timer - dt
        if p.timer <= 0 then
            table.remove(bp, i)
        elseif p.onFloor then
            p.floorTimer = p.floorTimer - dt
            if p.floorTimer <= 0 then table.remove(bp, i) end
        else
            p.vy = p.vy + GRAVITY * dt
            p.x  = p.x + p.vx * dt
            p.y  = p.y + p.vy * dt
            if p.y >= p.floor then
                p.y = p.floor; p.onFloor = true; p.vx = 0; p.vy = 0
            end
        end
    end
end

-- ============================================================================
-- SELECTION CIRCLES
-- ============================================================================

local function drawSelectionCircles()
    for _, id in ipairs(battle.partyIds) do
        local sc = battle.selCircleScales[id] or 0
        if sc < 0.01 then goto continue end
        local pos, sz = world.position[id], world.size[id]
        if not (pos and sz) then goto continue end
        local rx = (sz.w / 2) * sc
        local ry = (sz.w * 0.18) * sc
        love.graphics.setLineWidth(3)
        love.graphics.setColor(0, 0.85, 0.1, 0.9 * sc)
        love.graphics.ellipse("line", pos.x, pos.y + sz.h/2, rx, ry)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1, 0.65 * sc)
        love.graphics.ellipse("line", pos.x, pos.y + sz.h/2, rx, ry)
        ::continue::
    end
end

local function updateSelCircles(dt)
    for _, id in ipairs(battle.partyIds) do
        local dead   = world.deathState[id] ~= nil
        local target = (not dead and id == battle.selectedUnit) and 1.0 or 0.0
        local curr   = battle.selCircleScales[id] or 0.0
        battle.selCircleScales[id] = curr + (target - curr) * math.min(1, dt * 14)
    end
end

local function drawBloodParticles()
    love.graphics.setColor(1, 0.08, 0.08, 1)
    for _, p in ipairs(battle.bloodParticles) do
        love.graphics.rectangle("fill", p.x-1, p.y-1, 2, 2)
    end
end

-- ============================================================================
-- HEAL PARTICLES
-- ============================================================================

local function spawnHealCrosses(tgtId)
    local pos = world.position[tgtId]; if not pos then return end
    for _ = 1, 8 do
        table.insert(battle.healParticles, {
            x     = pos.x + math.random(-10, 10) * SCALE,
            y     = pos.y,
            vx    = math.random(-10, 10) * SCALE,
            vy    = -(35 + math.random(0, 30)) * SCALE,
            timer = 0.8,
        })
    end
end

local function updateHealParticles(dt)
    local hp = battle.healParticles
    for i = #hp, 1, -1 do
        local p = hp[i]
        p.timer = p.timer - dt
        if p.timer <= 0 then
            table.remove(hp, i)
        else
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
        end
    end
end

local function drawHealParticles()
    for _, p in ipairs(battle.healParticles) do
        local a = p.timer / 0.8
        love.graphics.setColor(0.2, 1, 0.3, a)
        love.graphics.rectangle("fill", p.x - 1, p.y,     3, 1)
        love.graphics.rectangle("fill", p.x,     p.y - 1, 1, 3)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- ============================================================================
-- COMBAT HELPERS
-- ============================================================================

local function calcNormalDmg(srcId, tgtId, value)
    local ss, ts = world.stats[srcId], world.stats[tgtId]
    if not (ss and ts) then return 0 end
    local boost = math.max(0.10, statGet(ss.BOOST))
    local res   = math.max(0.10, statGet(ts.RES))
    return math.max(0, (value * statGet(ss.ATK) * boost - statGet(ts.DEF)) * res)
end

local function resolveHit(srcId, tgtId)
    local ss, ts = world.stats[srcId], world.stats[tgtId]
    if not (ss and ts) then return "HIT" end
    local crit = math.max(0, statGet(ss.CRIT) - statGet(ts.CRIT_DEF))
    return math.random() < crit and "CRIT" or "HIT"
end

local function getDeathAnimIdx(id)
    local ac = world.anim[id]; if not ac then return 0 end
    local maxIdx = 0
    for idx in pairs(ac.list) do if idx > maxIdx then maxIdx = idx end end
    return maxIdx
end

local function activateDeathAnim(id, holdAtEnd)
    local ac = world.anim[id]; if not ac then return end
    local di = getDeathAnimIdx(id); if di == 0 then return end
    for _, a in pairs(ac.list) do a.active = false end
    local da = ac.list[di]
    da.active = true; da.timer = 0; da.reverse = nil; da.holdAtEnd = holdAtEnd or false
end

local function applyStagger(tgtId, dmg)
    local sg, ss = world.stagger[tgtId], world.stats[tgtId]
    if not (sg and ss) or sg.staggered then return end
    sg.points = sg.points + dmg * statGet(ss.STAGGER_RES)
    if sg.points >= statGet(ss.MAX_STAGGER) then
        sg.points = 0; sg.staggered = true
        sg.timer = statGet(ss.STAGGER_DUR); sg.reversingAnim = false
        ss.RES.add = ss.RES.add + 1
        activateDeathAnim(tgtId, true)
    end
end

local function addThreat(enemyId, allyId, amount)
    local tm = world.threatMap[enemyId]
    if tm then tm.map[allyId] = (tm.map[allyId] or 0) + amount end
end

local function faceTarget(srcId, tgtId)
    local sp, tp = world.position[srcId], world.position[tgtId]
    if sp and tp and world.facing[srcId] then
        world.facing[srcId].right = (tp.x >= sp.x)
    end
end

local function checkMeleeRange(srcId, tgtId)
    local sp, ss = world.position[srcId], world.size[srcId]
    local tp, ts = world.position[tgtId], world.size[tgtId]
    if not (sp and ss and tp and ts) then return false end
    local dx = math.max(0, math.abs(sp.x-tp.x) - (ss.w/2+ts.w/2))
    local dy = math.max(0, math.abs(sp.y-tp.y) - (ss.h/2+ts.h/2))
    return math.sqrt(dx*dx+dy*dy) <= ss.w * 0.25
end

local function readTagSystem(tag)
    for _, ec in pairs(world.effects_comp) do
        for _, eff in ipairs(ec.active) do
            if eff.conditional then eff.conditional(world, battle, eff, tag) end
        end
    end
end

-- Forward declarations
local registerHit
local registerHeal

-- ============================================================================
-- EFFECTS
-- ============================================================================

local function newHurtIndicatorEffect(tgtId)
    return {
        startFlag=true, endFlag=false,
        target=tgtId, addedR=255, remaining=255, decayRate=600,
        start  = function(w, b, eff)
            local tc = w.tintColor[eff.target]
            if tc then tc.R = math.min(255, tc.R + eff.addedR) end
            eff.startFlag = false
        end,
        active = function(w, b, eff, dt)
            local sub = math.min(eff.decayRate * dt, eff.remaining)
            local tc  = w.tintColor[eff.target]
            if tc then tc.R = math.max(0, tc.R - sub) end
            eff.remaining = eff.remaining - sub
            if eff.remaining <= 0 then eff.endFlag = true end
        end,
    }
end

local function newHealIndicatorEffect(tgtId)
    return {
        startFlag=true, endFlag=false,
        target=tgtId, addedG=255, remaining=255, decayRate=600,
        start  = function(w, b, eff)
            local tc = w.tintColor[eff.target]
            if tc then tc.G = math.min(255, tc.G + eff.addedG) end
            eff.startFlag = false
        end,
        active = function(w, b, eff, dt)
            local sub = math.min(eff.decayRate * dt, eff.remaining)
            local tc  = w.tintColor[eff.target]
            if tc then tc.G = math.max(0, tc.G - sub) end
            eff.remaining = eff.remaining - sub
            if eff.remaining <= 0 then eff.endFlag = true end
        end,
    }
end

local function newForceEffect(tgtId, fx, fy, duration)
    return {
        startFlag=true, endFlag=false,
        target=tgtId, force_x=fx, force_y=fy, timer=duration,
        start  = function(w, b, eff) eff.startFlag = false end,
        active = function(w, b, eff, dt)
            eff.timer = eff.timer - dt
            if eff.timer <= 0 then eff.endFlag = true; return end
            local ph = w.physics[eff.target]
            if ph then ph.fx = ph.fx + eff.force_x; ph.fy = ph.fy + eff.force_y end
        end,
    }
end

local function newKnightRageEffect(srcId)
    return {
        startFlag=true, endFlag=false, src=srcId, resource=0, resourceMax=10,
        start  = function(w, b, eff) eff.startFlag = false end,
        active = function(w, b, eff, dt)
            eff.resource = math.max(0, eff.resource - 0.5 * dt)
            local s = w.stats[eff.src]
            if s then s.ATK.mult = 1.0 + eff.resource * 0.1 end
        end,
        conditional = function(w, b, eff, tag)
            if tag.src ~= eff.src then return end
            for _, kw in ipairs(tag.keywords or {}) do
                if kw == "Melee" then
                    eff.resource = math.min(eff.resourceMax, eff.resource + 1); break
                end
            end
        end,
    }
end

local function newHealingEffect(srcId)
    return {
        startFlag=true, endFlag=false, src=srcId, rate=6,
        start  = function(w, b, eff) eff.startFlag = false end,
        active = function(w, b, eff, dt)
            if not w.entities[eff.src] then eff.endFlag = true; return end
            if w.deathState[eff.src] then return end
            local ss = w.stats[eff.src]; if not ss then return end
            local maxHp = statGet(ss.maxHP)
            if statGet(ss.HP) < maxHp then
                ss.HP.base = math.min(maxHp, ss.HP.base + eff.rate * dt)
            end
        end,
    }
end

local function newKnightAutoAttackEffect(srcId, tgtId)
    return {
        startFlag=true, endFlag=false, isActionEffect=true, isAction=true, skillSlot=0, src=srcId, tgt=tgtId, timer=12/60,
        start  = function(w, b, eff) eff.startFlag = false end,
        active = function(w, b, eff, dt)
            eff.timer = eff.timer - dt
            if eff.timer <= 0 then eff.endFlag = true end
        end,
        end_fn = function(w, b, eff)
            if w.entities[eff.tgt] then registerHit(eff.src, eff.tgt, {"Melee"}, false) end
        end,
    }
end

local function newSkeletonAutoAttackEffect(srcId, tgtId)
    return {
        startFlag=true, endFlag=false, isAction=true, src=srcId, tgt=tgtId, timer=21/60,
        start  = function(w, b, eff) eff.startFlag = false end,
        active = function(w, b, eff, dt)
            eff.timer = eff.timer - dt
            if eff.timer <= 0 then eff.endFlag = true end
        end,
        end_fn = function(w, b, eff)
            if w.entities[eff.tgt] then registerHit(eff.src, eff.tgt, {"Melee"}, false) end
        end,
    }
end

local function newKnightSlashEffect(srcId, tgtId)
    return {
        startFlag=true, endFlag=false, isActionEffect=true, isAction=true, skillSlot=1, src=srcId, tgt=tgtId, timer=24/60,
        start  = function(w, b, eff) eff.startFlag = false end,
        active = function(w, b, eff, dt)
            eff.timer = eff.timer - dt
            if eff.timer <= 0 then eff.endFlag = true end
        end,
        end_fn = function(w, b, eff)
            if w.entities[eff.tgt] then registerHit(eff.src, eff.tgt, {"Melee","Slash"}, true) end
        end,
    }
end

local function newKnightDefendEffect(srcId)
    return {
        startFlag=true, endFlag=false, isAction=false, isActionEffect=false, skillSlot=2,
        src=srcId, timer=10.0, drainPerSec=0,
        start = function(w, b, eff)
            eff.startFlag = false
            local ss = w.stats[eff.src]; if not ss then return end
            local sg = w.stagger[eff.src]
            ss.RES.add = ss.RES.add - 0.5
            eff.drainPerSec = sg and (sg.points / 2 / 10) or 0
        end,
        active = function(w, b, eff, dt)
            if world.deathState[eff.src] then return end
            eff.timer = eff.timer - dt
            if eff.timer <= 0 then eff.endFlag = true; return end
            if eff.drainPerSec <= 0 then return end
            local sg = w.stagger[eff.src]
            if sg and not sg.staggered and sg.points > 0 then
                sg.points = math.max(0, sg.points - eff.drainPerSec * dt)
            end
        end,
        end_fn = function(w, b, eff)
            local ss = w.stats[eff.src]; if not ss then return end
            ss.RES.add = ss.RES.add + 0.5
        end,
    }
end

local function newNomadAutoHealEffect(srcId, tgtId)
    return {
        startFlag=true, endFlag=false, isActionEffect=true, isAction=true, skillSlot=0, src=srcId, tgt=tgtId, timer=24/60,
        start  = function(w, b, eff) eff.startFlag = false end,
        active = function(w, b, eff, dt)
            eff.timer = eff.timer - dt
            if eff.timer <= 0 then eff.endFlag = true end
        end,
        end_fn = function(w, b, eff)
            if w.entities[eff.tgt] and not w.deathState[eff.tgt] then
                registerHeal(eff.src, eff.tgt, 1.0)
            end
        end,
    }
end

-- ============================================================================
-- REGISTER HIT
-- ============================================================================

registerHit = function(srcId, tgtId, keywords, useVFX)
    if not (world.entities[srcId] and world.entities[tgtId]) then return end
    local verdict = resolveHit(srcId, tgtId)
    local isCrit  = (verdict == "CRIT")
    local dmg     = calcNormalDmg(srcId, tgtId, 1.0)
    if isCrit then dmg = dmg * 2 end

    local ts = world.stats[tgtId]
    if ts then ts.HP.base = math.max(0, ts.HP.base - dmg) end

    applyStagger(tgtId, dmg)
    faceTarget(srcId, tgtId)

    local srcSide = world.side[srcId]
    if srcSide and srcSide.s == 0 then
        for id in pairs(world.entities) do
            if world.side[id] and world.side[id].s == 1 then
                addThreat(id, srcId, dmg * 0.5)
            end
        end
    end

    local ec = world.effects_comp[tgtId]
    if ec then table.insert(ec.pending, newHurtIndicatorEffect(tgtId)) end

    spawnBlood(srcId, tgtId, isCrit)
    if useVFX then triggerHitVFX(tgtId) end

    local sp, tp = world.position[srcId], world.position[tgtId]
    if sp and tp then
        local dx, dy = tp.x - sp.x, tp.y - sp.y
        local len = math.sqrt(dx*dx + dy*dy)
        if len > 0.001 then dx, dy = dx/len, dy/len end
        local kbEc = world.effects_comp[tgtId]
        if kbEc then table.insert(kbEc.pending, newForceEffect(tgtId, dx*400, dy*150, 0.12)) end
    end

    readTagSystem({src=srcId, tgt=tgtId, keywords=keywords or {}, amount=dmg})

    local tgtMt = world.moveTarget[tgtId]
    if world.targetSide[tgtId] == 1 and not world.entityTarget[tgtId]
       and not (tgtMt and tgtMt.active)
       and world.entities[srcId] and not world.deathState[srcId] then
        world.entityTarget[tgtId] = {id=srcId}
    end
end

registerHeal = function(srcId, tgtId, value)
    if not (world.entities[srcId] and world.entities[tgtId]) then return end
    local ss = world.stats[srcId]; if not ss then return end
    local ts = world.stats[tgtId]; if not ts then return end
    local amount = value * statGet(ss.ATK) * math.max(0.10, statGet(ss.BOOST))
    local maxHp  = statGet(ts.maxHP)
    ts.HP.base = math.min(maxHp, ts.HP.base + amount)
    spawnHealCrosses(tgtId)
    local ec = world.effects_comp[tgtId]
    if ec then table.insert(ec.pending, newHealIndicatorEffect(tgtId)) end
end

-- ============================================================================
-- SKILLS
-- ============================================================================

local function newKnightAutoAttackSkill()
    return {
        name="KnightAutoAttack", isAutoAttack=true, cd=0, cdMax=2.0,
        use = function(w, b, id, skill)
            local et = w.entityTarget[id]; if not et then return end
            local ac = w.anim[id]
            if ac and ac.list[3] then ac.list[3].active=true; ac.list[3].timer=0 end
            local ec = w.effects_comp[id]
            if ec then table.insert(ec.pending, newKnightAutoAttackEffect(id, et.id)) end
            skill.cd = skill.cdMax
        end,
    }
end

local function newSkeletonAutoAttackSkill()
    return {
        name="SkeletonAutoAttack", isAutoAttack=true, cd=0, cdMax=2.0,
        use = function(w, b, id, skill)
            local et = w.entityTarget[id]; if not et then return end
            local ac = w.anim[id]
            if ac and ac.list[3] then ac.list[3].active=true; ac.list[3].timer=0 end
            local ec = w.effects_comp[id]
            if ec then table.insert(ec.pending, newSkeletonAutoAttackEffect(id, et.id)) end
            skill.cd = skill.cdMax
        end,
    }
end

local function newKnightSlashSkill()
    return {
        name="KnightSlash", iconName="skill_icons17",
        cd=0, cdMax=25.0, iconScale=1.0, iconScaleTarget=1.0,
        use = function(w, b, id, skill)
            local et = w.entityTarget[id]; if not et then return end
            local ac = w.anim[id]
            if ac and ac.list[4] then ac.list[4].active=true; ac.list[4].timer=0 end
            local ec = w.effects_comp[id]
            if ec then table.insert(ec.pending, newKnightSlashEffect(id, et.id)) end
        end,
    }
end

local function newKnightDefendSkill()
    return {
        name="KnightDefend", iconName="skill_icons22", noTargetRequired=true,
        cd=0, cdMax=30.0, iconScale=1.0, iconScaleTarget=1.0,
        use = function(w, b, id, skill)
            local ec = w.effects_comp[id]; if not ec then return end
            table.insert(ec.pending, newKnightDefendEffect(id))
        end,
    }
end

local function newNomadAutoHealSkill()
    return {
        name="NomadAutoHeal", isAutoAttack=true, cd=0, cdMax=2.5,
        use = function(w, b, id, skill)
            local et = w.entityTarget[id]; if not et then return end
            local ac = w.anim[id]
            if ac and ac.list[3] then ac.list[3].active=true; ac.list[3].timer=0 end
            local ec = w.effects_comp[id]
            if ec then table.insert(ec.pending, newNomadAutoHealEffect(id, et.id)) end
            skill.cd = skill.cdMax
        end,
    }
end

local function cancelActionEffects(id)
    local ec = world.effects_comp[id]; if not ec then return end
    local sk = world.skills[id]
    for _, eff in ipairs(ec.active) do
        if eff.isActionEffect then
            eff.cancelFlag = true
            -- Reset the skill so it can fire again immediately (not punishing to move mid-action)
            if eff.skillSlot ~= nil and sk and sk.list[eff.skillSlot] then
                sk.list[eff.skillSlot].cd = 0
            end
        end
    end
    -- Don't touch anims while staggered — staggerSystem owns anim state then.
    -- Resetting [6] during reversingAnim would freeze the timer and prevent stagger exit.
    local sg = world.stagger[id]
    if sg and sg.staggered then return end
    local ac = world.anim[id]; if not ac then return end
    for _, a in pairs(ac.list) do a.active = false end
    if ac.list[1] then ac.list[1].active = true; ac.list[1].timer = 0 end
end

-- ============================================================================
-- ENTITY CREATION
-- ============================================================================

local function createKnight(x, y, saveStats)
    local id = world:new()
    local st = saveStats and statsFromSave(saveStats) or newStats(100, 10, 5, 0.10)
    world.position[id]     = {x=x, y=y}
    world.size[id]         = {w=30*SCALE, h=40*SCALE}
    world.facing[id]       = {right=true}
    world.physics[id]      = {vx=0, vy=0, fx=0, fy=0}
    world.moveTarget[id]   = {x=x, y=y, active=false}
    world.side[id]         = {s=0}
    world.targetSide[id]   = 1
    world.stats[id]        = st
    world.locks[id]        = {actionLock=0, moveLock=0}
    world.stagger[id]      = {points=0, staggered=false, timer=0}
    world.tintColor[id]    = {R=0, G=0, B=0}
    world.bar[id]          = {hpColor={0,1,0}, hpPrevRatio=1, timer=0}
    world.effects_comp[id] = {pending={}, active={}}
    world.anim[id] = {list={
        [1] = newAnimInst("KnightIdle",    10/60, true,  true),
        [2] = newAnimInst("KnightMove",     6/60, true,  false),
        [3] = newAnimInst("KnightAttack1",  6/60, false, false),
        [4] = newAnimInst("KnightAttack2", 12/60, false, false),
        [5] = newAnimInst("KnightTakeHit",  6/60, false, false),
        [6] = newAnimInst("KnightDeath",    6/60, false, false),
    }}
    world.skills[id] = {
        list  = {[0]=newKnightAutoAttackSkill(), [1]=newKnightSlashSkill(), [2]=newKnightDefendSkill()},
        queue = {}, gcd = 0, pendingActive = nil,
    }
    table.insert(world.effects_comp[id].pending, newKnightRageEffect(id))
    -- table.insert(world.effects_comp[id].pending, newHealingEffect(id)) -- dev: disabled
    battle.selCircleScales[id] = 0
    return id
end

local function createSkeleton(x, y)
    local id = world:new()
    world.position[id]     = {x=x, y=y}
    world.size[id]         = {w=40*SCALE, h=40*SCALE}
    world.facing[id]       = {right=false}
    world.physics[id]      = {vx=0, vy=0, fx=0, fy=0}
    world.moveTarget[id]   = {x=x, y=y, active=false}
    world.side[id]         = {s=1}
    world.targetSide[id]   = 1
    world.stats[id]        = newStats(80, 8, 3, 0.05)
    world.locks[id]        = {actionLock=0, moveLock=0}
    world.stagger[id]      = {points=0, staggered=false, timer=0}
    world.tintColor[id]    = {R=0, G=0, B=0}
    world.bar[id]          = {hpColor={1,1,0}, hpPrevRatio=1, timer=0}
    world.effects_comp[id] = {pending={}, active={}}
    world.threatMap[id]    = {map={}, decayTimer=0}
    world.dangerLevel[id]  = ENEMY_DANGER.skeleton
    world.hasEntered[id]   = {v=false, h=false}
    world.anim[id] = {list={
        [1] = newAnimInst("SkeletonIdle",    4/60, true,  true),
        [2] = newAnimInst("SkeletonMove",    4/60, true,  false),
        [3] = newAnimInst("SkeletonAttack",  3/60, false, false),
        [4] = newAnimInst("SkeletonDeath",   6/60, false, false),
    }}
    world.skills[id] = {list={[0]=newSkeletonAutoAttackSkill()}, queue={}, gcd=0}
    if #battle.partyIds > 0 then
        local tgtId = battle.partyIds[math.random(#battle.partyIds)]
        world.entityTarget[id] = {id=tgtId}
        world.threatMap[id].map[tgtId] = 1
        local sp, tp = world.position[id], world.position[tgtId]
        if sp and tp then world.facing[id].right = (tp.x > sp.x) end
    end
    return id
end

local function createNomad(x, y, saveStats)
    local id = world:new()
    local st = saveStats and statsFromSave(saveStats) or newStats(80, 8, 2, 0.05)
    world.position[id]     = {x=x, y=y}
    world.size[id]         = {w=30*SCALE, h=40*SCALE}
    world.facing[id]       = {right=true}
    world.physics[id]      = {vx=0, vy=0, fx=0, fy=0}
    world.moveTarget[id]   = {x=x, y=y, active=false}
    world.side[id]         = {s=0}
    world.targetSide[id]   = 0
    world.isRanged[id]     = true
    world.stats[id]        = st
    world.locks[id]        = {actionLock=0, moveLock=0}
    world.stagger[id]      = {points=0, staggered=false, timer=0}
    world.tintColor[id]    = {R=0, G=0, B=0}
    world.bar[id]          = {hpColor={0, 1, 0}, hpPrevRatio=1, timer=0}
    world.effects_comp[id] = {pending={}, active={}}
    world.anim[id] = {list={
        [1] = newAnimInst("NomadIdle",    8/60, true,  true),
        [2] = newAnimInst("NomadMove",    8/60, true,  false),
        [3] = newAnimInst("NomadAttack1", 6/60, false, false),
        [4] = newAnimInst("NomadAttack2", 6/60, false, false),
        [5] = newAnimInst("NomadDeath",   6/60, false, false),
    }}
    world.skills[id] = {
        list  = {[0]=newNomadAutoHealSkill()},
        queue = {}, gcd = 0, pendingActive = nil,
    }
    battle.selCircleScales[id] = 0
    return id
end

-- ============================================================================
-- SYSTEMS
-- ============================================================================

local function targetFollowSystem()
    for id in pairs(world.entities) do
        if world.deathState[id] then goto continue end
        local et = world.entityTarget[id]
        if not et then goto continue end
        if not world.entities[et.id] or world.deathState[et.id] then
            world.entityTarget[id] = nil; goto continue
        end
        local mt = world.moveTarget[id]; if not mt then goto continue end
        if world.isRanged[id] then
            local tp, sp = world.position[et.id], world.position[id]
            if tp and sp and world.facing[id] then
                world.facing[id].right = (tp.x >= sp.x)
            end
            goto continue
        end
        if checkMeleeRange(id, et.id) then
            mt.active = false
        else
            local tp, ts = world.position[et.id], world.size[et.id]
            local sp, ss = world.position[id], world.size[id]
            if tp and ts and sp and ss then
                local offset   = ts.w/2 + ss.w/2
                local leftX    = tp.x - offset; local rightX = tp.x + offset
                local distLeft = math.abs(sp.x - leftX); local distRight = math.abs(sp.x - rightX)
                mt.x = (distLeft <= distRight) and leftX or rightX
                mt.y = tp.y + ts.h/2; mt.active = true
            end
        end
        ::continue::
    end
end

local function pendingActiveSystem()
    for id in pairs(world.entities) do
        if world.deathState[id] then goto continue end
        local sk = world.skills[id]
        if not (sk and sk.pendingActive) then goto continue end
        if sk.gcd > 0 then goto continue end
        local lk = world.locks[id]; if lk and lk.actionLock > 0 then goto continue end
        local sg = world.stagger[id]; if sg and sg.staggered then goto continue end
        local pendSkill = sk.list[sk.pendingActive]
        if not (pendSkill and pendSkill.noTargetRequired) then
            local et = world.entityTarget[id]
            if not (et and world.entities[et.id]) then goto continue end
            if not world.isRanged[id] and not checkMeleeRange(id, et.id) then goto continue end
        end
        local slot = sk.pendingActive
        local skill = sk.list[slot]
        if skill and skill.use then skill.use(world, battle, id, skill) end
        sk.gcd = GCD_DURATION; sk.pendingActive = nil
        ::continue::
    end
end

local function autoAttackSystem()
    for id in pairs(world.entities) do
        if world.deathState[id] then goto continue end
        local et = world.entityTarget[id]
        if not et or not world.entities[et.id] then goto continue end
        if world.deathState[et.id] then goto continue end
        local lk, sk = world.locks[id], world.skills[id]
        if not (lk and sk) then goto continue end
        if sk.pendingActive then goto continue end
        if lk.actionLock > 0 then goto continue end
        local auto = sk.list[0]
        if not auto or auto.cd > 0 then goto continue end
        if not world.isRanged[id] and not checkMeleeRange(id, et.id) then goto continue end
        local sg = world.stagger[id]; if sg and sg.staggered then goto continue end
        local alreadyQueued = false
        for _, qi in ipairs(sk.queue) do if qi == 0 then alreadyQueued=true; break end end
        if not alreadyQueued then table.insert(sk.queue, 0) end
        ::continue::
    end
end

local function skillSystem(dt)
    for id in pairs(world.entities) do
        local sk = world.skills[id]; if not sk then goto continue end
        sk.gcd = math.max(0, sk.gcd - dt)
        for _, skill in pairs(sk.list) do skill.cd = math.max(0, skill.cd - dt) end
        if #sk.queue > 0 and sk.gcd <= 0 then
            local lk = world.locks[id]; if lk and lk.actionLock > 0 then goto continue end
            local slotIdx = table.remove(sk.queue, 1)
            local skill   = sk.list[slotIdx]
            if skill and skill.cd <= 0 then
                skill.use(world, battle, id, skill)
                if not skill.isAutoAttack then sk.gcd = GCD_DURATION end
            end
        end
        ::continue::
    end
end

local function effectSystem(dt)
    for id in pairs(world.entities) do
        local ec = world.effects_comp[id]; if not ec then goto continue end
        for _, eff in ipairs(ec.pending) do table.insert(ec.active, eff) end
        ec.pending = {}
        local toRemove = {}
        for i, eff in ipairs(ec.active) do
            if eff.startFlag then
                if eff.start then eff.start(world, battle, eff) end
                eff.startFlag = false
            end
            if eff.cancelFlag then
                table.insert(toRemove, i)
            else
                if not eff.endFlag and eff.active then eff.active(world, battle, eff, dt) end
                if eff.endFlag then
                    if eff.end_fn then eff.end_fn(world, battle, eff) end
                    table.insert(toRemove, i)
                end
            end
        end
        for i = #toRemove, 1, -1 do table.remove(ec.active, toRemove[i]) end
        ::continue::
    end
end

local function staggerSystem(dt)
    for id in pairs(world.entities) do
        if world.deathState[id] then goto continue end
        local sg = world.stagger[id]
        if sg and sg.staggered then
            if sg.reversingAnim then
                local di = getDeathAnimIdx(id)
                local ac = world.anim[id]
                if ac and di > 0 then
                    local da    = ac.list[di]
                    local entry = animDB[da and da.name]
                    if entry and da and da.timer >= da.frameLength * entry.frames then
                        sg.staggered = false; sg.reversingAnim = false
                        da.active = false; da.reverse = nil; da.timer = 0
                        local ss = world.stats[id]
                        if ss then ss.RES.add = ss.RES.add - 1 end
                        if ac.list[1] then ac.list[1].active = true end
                    end
                end
            else
                sg.timer = sg.timer - dt
                if sg.timer <= 0 then
                    sg.reversingAnim = true
                    local di = getDeathAnimIdx(id)
                    local ac = world.anim[id]
                    if ac and di > 0 then
                        local da = ac.list[di]
                        da.active = true; da.timer = 0; da.reverse = true; da.holdAtEnd = false
                    end
                end
            end
        end
        local lk = world.locks[id]
        if lk then
            lk.actionLock = math.max(0, lk.actionLock - dt)
            lk.moveLock   = math.max(0, lk.moveLock - dt)
        end
        ::continue::
    end
end

local function threatSystem(dt)
    for id in pairs(world.entities) do
        local sd = world.side[id]; if not (sd and sd.s == 1) then goto continue end
        local tm = world.threatMap[id]; if not tm then goto continue end
        tm.decayTimer = tm.decayTimer + dt
        if tm.decayTimer >= 1.0 then
            tm.decayTimer = 0
            for ally, val in pairs(tm.map) do tm.map[ally] = val * 0.9 end
        end
        local bestId, bestVal = nil, -1
        for ally, val in pairs(tm.map) do
            if world.entities[ally] and not world.deathState[ally] and val > bestVal then
                bestId, bestVal = ally, val
            end
        end
        if bestId then
            world.entityTarget[id] = {id=bestId}
        elseif not world.entityTarget[id] then
            for _, pid in ipairs(battle.partyIds) do
                if not world.deathState[pid] then world.entityTarget[id] = {id=pid}; break end
            end
        end
        ::continue::
    end
end

local function hasActiveAction(id)
    local ec = world.effects_comp[id]; if not ec then return false end
    for _, eff in ipairs(ec.active) do
        if eff.isAction then return true end
    end
    return false
end

local function moveTargetSystem(dt)
    for id in pairs(world.entities) do
        if world.deathState[id] then goto continue end
        local mt = world.moveTarget[id]; if not (mt and mt.active) then goto continue end
        if hasActiveAction(id) then mt.active = false; goto continue end
        local lk = world.locks[id]; if lk and lk.moveLock > 0 then goto continue end
        local sg = world.stagger[id]; if sg and sg.staggered then goto continue end
        local pos, sz, ss, ph = world.position[id], world.size[id], world.stats[id], world.physics[id]
        if not (pos and sz and ss and ph) then goto continue end
        local dx = mt.x - pos.x; local dy = mt.y - (pos.y + sz.h/2)
        local dist = math.sqrt(dx*dx + dy*dy)
        if dist < 1 then mt.active = false; goto continue end
        dx, dy = dx/dist, dy/dist
        local spd = statGet(ss.MOVE_SPEED) * 30
        local moveAmt = math.min(spd * dt, dist)
        pos.x = pos.x + dx * moveAmt; pos.y = pos.y + dy * moveAmt
        local et, fc = world.entityTarget[id], world.facing[id]
        if fc then
            if et and world.position[et.id] then
                fc.right = (world.position[et.id].x > pos.x)
            else
                fc.right = (dx > 0)
            end
        end
        ::continue::
    end
end

local function antiClumpingSystem()
    local ids, boxes = {}, {}
    for id in pairs(world.entities) do
        local pos, sz = world.position[id], world.size[id]
        if pos and sz and world.physics[id] and world.stats[id] then
            local mbX, mbY = pos.x, pos.y + sz.h/2
            local bW, bH = sz.w/2, sz.w/4
            boxes[id] = {x=mbX-bW/2, y=mbY-bH/2, w=bW, h=bH, cx=mbX, cy=mbY}
            table.insert(ids, id)
        end
    end
    -- nudge exact stacks
    local resolved, attempts = false, 0
    while not resolved and attempts < 20 do
        resolved = true; attempts = attempts + 1
        for i = 1, #ids do
            for j = i+1, #ids do
                local a, b = ids[i], ids[j]
                if boxes[a].cx == boxes[b].cx and boxes[a].cy == boxes[b].cy then
                    resolved = false
                    local pos, sz = world.position[b], world.size[b]
                    if math.random(2) == 1 then pos.x = pos.x + (math.random(2)==1 and 1 or -1)
                    else pos.y = pos.y + (math.random(2)==1 and 1 or -1) end
                    local mbX, mbY = pos.x, pos.y+sz.h/2
                    local bW, bH = sz.w/2, sz.w/4
                    boxes[b] = {x=mbX-bW/2, y=mbY-bH/2, w=bW, h=bH, cx=mbX, cy=mbY}
                end
            end
        end
    end
    for i = 1, #ids do
        for j = i+1, #ids do
            local a, b = ids[i], ids[j]
            local ba, bb = boxes[a], boxes[b]
            if ba.x < bb.x+bb.w and ba.x+ba.w > bb.x and ba.y < bb.y+bb.h and ba.y+ba.h > bb.y then
                local dist = math.sqrt((bb.cx-ba.cx)^2 + (bb.cy-ba.cy)^2)
                local maxSep = (ba.w+bb.w)/2
                local t = (maxSep > 0) and math.min(dist/maxSep, 1) or 0
                local force = 1000 - t * 800
                local dx, dy = bb.cx-ba.cx, bb.cy-ba.cy
                local len = math.max(dist, 0.001)
                dx, dy = dx/len, dy/len
                local pha, phb = world.physics[a], world.physics[b]
                pha.fx = pha.fx - dx*force; pha.fy = pha.fy - dy*force
                phb.fx = phb.fx + dx*force; phb.fy = phb.fy + dy*force
            end
        end
    end
end

local function physicsSystem(dt)
    local fric = math.pow(FRICTION, 60 * dt)
    for id in pairs(world.entities) do
        local pos, ph, sz = world.position[id], world.physics[id], world.size[id]
        if not (pos and ph) then goto continue end
        ph.vx = ph.vx + (ph.fx / MASS); ph.vy = ph.vy + (ph.fy / MASS)
        ph.fx, ph.fy = 0, 0
        pos.x = pos.x + ph.vx * dt; pos.y = pos.y + ph.vy * dt
        ph.vx = ph.vx * fric; ph.vy = ph.vy * fric
        if sz then
            local sd = world.side[id]
            local mb = pos.y + sz.h/2
            if sd and sd.s == 0 then
                pos.x = math.max(sz.w/2, math.min(VW - sz.w/2, pos.x))
                if mb < BATTLE_LINE_Y then pos.y = BATTLE_LINE_Y - sz.h/2 end
                if mb > VH then pos.y = VH - sz.h/2 end
            elseif sd and sd.s == 1 then
                local he = world.hasEntered[id]
                -- h: set once the enemy's center crosses into the canvas from the right
                if he and not he.h and pos.x <= VW - sz.w/2 then he.h = true end
                if he and he.h then
                    pos.x = math.max(sz.w/2, math.min(VW - sz.w/2, pos.x))
                end
                -- v: set once the foot crosses BATTLE_LINE_Y going down
                if he and not he.v and mb >= BATTLE_LINE_Y then he.v = true end
                if he and he.v then
                    if mb < BATTLE_LINE_Y then pos.y = BATTLE_LINE_Y - sz.h/2 end
                    if mb > VH then pos.y = VH - sz.h/2 end
                end
            end
        end
        ::continue::
    end
end

local function updateAnimTimers(dt)
    for id in pairs(world.entities) do
        local ac = world.anim[id]; if not ac then goto continue end
        local mt = world.moveTarget[id]
        if ac.list[2] then
            local ph = world.physics[id]
            local sg = world.stagger[id]
            local moving = not (sg and sg.staggered) and
                           ((mt and mt.active) or (ph and (math.abs(ph.vx)>5 or math.abs(ph.vy)>5)))
            ac.list[2].active = moving or false
        end
        for _, animInst in pairs(ac.list) do
            if animInst.active then
                animInst.timer = animInst.timer + dt
                local entry = animDB[animInst.name]
                if entry then
                    local totalTime = animInst.frameLength * entry.frames
                    if not animInst.repeat_ and animInst.timer >= totalTime then
                        if animInst.holdAtEnd or animInst.reverse then
                            animInst.timer = totalTime
                        else
                            animInst.active = false; animInst.timer = totalTime
                        end
                    end
                end
            end
        end
        ::continue::
    end
end

local function deathSystem(dt)
    local toDestroy = {}
    for id in pairs(world.entities) do
        local ds = world.deathState[id]
        if not ds then
            local ss = world.stats[id]
            if not (ss and statGet(ss.HP) <= 0) then goto continue end
            world.deathState[id] = {phase="dying", timer=2.5, blinkTimer=0, blinkVisible=true}
            activateDeathAnim(id, true)
            world.bar[id] = nil
            local mt = world.moveTarget[id]; if mt then mt.active = false end
            world.entityTarget[id] = nil
            for eid in pairs(world.entities) do
                local tm = world.threatMap[eid]
                if tm then tm.map[id] = nil end
                local et = world.entityTarget[eid]
                if et and et.id == id then world.entityTarget[eid] = nil end
            end
            local side = world.side[id]
            if side and side.s == 0 then
                for i, pid in ipairs(battle.partyIds) do
                    if pid == id then
                        battle.deadSlots[i] = true
                        if battle.selectedUnit == id then
                            battle.selectedUnit = nil
                            for j, pid2 in ipairs(battle.partyIds) do
                                if not battle.deadSlots[j] then battle.selectedUnit = pid2; break end
                            end
                        end
                        break
                    end
                end
            elseif side and side.s == 1 then
                local mgr = battle.encounterMgr
                if mgr then
                    local dl = world.dangerLevel[id] or 0
                    mgr.currentDanger  = math.max(0, mgr.currentDanger - dl)
                    mgr.dangerDefeated = mgr.dangerDefeated + dl
                end
            end
        elseif ds.phase == "dying" then
            ds.timer = ds.timer - dt
            if ds.timer <= 0 then
                ds.phase="blinking"; ds.blinkTimer=0; ds.blinkVisible=true
            end
        elseif ds.phase == "blinking" then
            ds.blinkTimer = ds.blinkTimer + dt
            local rate   = 2 + ds.blinkTimer * 8
            local period = 1 / rate
            ds.blinkVisible = (math.floor(ds.blinkTimer / period) % 2 == 0)
            if ds.blinkTimer >= 2.0 then table.insert(toDestroy, id) end
        end
        ::continue::
    end
    for _, id in ipairs(toDestroy) do world:destroy(id) end
end

local function vfxDecaySystem(dt)
    local vfx = battle.vfx
    vfx.shake  = math.max(0, vfx.shake  - 18 * dt)
    vfx.chroma = math.max(0, vfx.chroma -  5 * dt)
    vfx.zoom   = vfx.zoom + (vfx.zoomTarget - vfx.zoom) * math.min(1, dt * 8)
    vfx.zoomTarget = vfx.zoomTarget + (1.0 - vfx.zoomTarget) * math.min(1, dt * 3)
    battle.postfx.chromasep.radius = common.CHROMA_RADIUS + vfx.chroma
end

-- ============================================================================
-- ENCOUNTER MANAGER
-- ============================================================================

local function queueWave(isSurprise)
    local mgr = battle.encounterMgr
    if mgr.pendingWave then return end
    if not isSurprise and mgr.dangerDefeated >= mgr.encounterGoal then return end
    local budget = math.random(mgr.waveMinThreat, mgr.waveMaxThreat)
    mgr.pendingWave = { timer = 3.0, budget = budget }
end

local function flushPendingWave()
    local mgr = battle.encounterMgr
    local pw   = mgr.pendingWave
    local count = 0
    while pw.budget >= ENEMY_DANGER.skeleton do
        local spawnX = VW + 400 + count * 120 + math.random(0, 80)
        local spawnY = VH * 0.35 + count * 80
        createSkeleton(spawnX, spawnY)
        mgr.currentDanger = mgr.currentDanger + ENEMY_DANGER.skeleton
        pw.budget = pw.budget - ENEMY_DANGER.skeleton
        count     = count     + 1
    end
    mgr.pendingWave  = nil
    mgr.waveCooldown = 2.0
end

local function encounterManagerSystem(dt)
    local mgr = battle.encounterMgr
    if mgr.spawnTimer > 0 then
        mgr.spawnTimer = mgr.spawnTimer - dt
        return
    end

    if mgr.pendingWave then
        mgr.pendingWave.timer = mgr.pendingWave.timer - dt
        if mgr.pendingWave.timer <= 0 then flushPendingWave() end
    else
        mgr.waveCooldown = math.max(0, mgr.waveCooldown - dt)
        if mgr.waveCooldown == 0
           and mgr.currentDanger  < mgr.dangerThreshold
           and mgr.dangerDefeated < mgr.encounterGoal then
            queueWave()
        end
    end

    mgr.surpriseTimer = mgr.surpriseTimer - dt
    if mgr.surpriseTimer <= 0 then
        mgr.surpriseTimer = mgr.surpriseInterval
        if mgr.dangerDefeated < mgr.encounterGoal and math.random() < mgr.surpriseChance then
            queueWave(true)
        end
    end
end

-- Check if goal is met and all enemies are cleared
local function checkVictory()
    local mgr = battle.encounterMgr
    if not mgr or mgr.dangerDefeated < mgr.encounterGoal then return false end
    local hasEnemy = false
    for id in pairs(world.entities) do
        local sd = world.side[id]
        if sd and sd.s == 1 and not world.deathState[id] then hasEnemy=true; break end
    end
    if not hasEnemy and #battle.partyIds > 0 then
        for _, pid in ipairs(battle.partyIds) do
            if not world.deathState[pid] then return true end
        end
    end
    return false
end

-- ============================================================================
-- RENDERING
-- ============================================================================

local function getEntitiesSortedByY()
    local result = {}
    for id in pairs(world.entities) do
        if world.anim[id] and world.position[id] then
            local sz = world.size[id]
            local py = world.position[id].y + (sz and sz.h/2 or 0)
            table.insert(result, {id=id, sortY=py})
        end
    end
    table.sort(result, function(a, b) return a.sortY < b.sortY end)
    return result
end

local function animSystem()
    local sorted = getEntitiesSortedByY()
    for _, entry in ipairs(sorted) do
        local id = entry.id
        local ac, pos = world.anim[id], world.position[id]
        if not (ac and pos) then goto continue end

        local chosen, chosenIdx = nil, 0
        for idx, animInst in pairs(ac.list) do
            if animInst.active and idx > chosenIdx then chosen, chosenIdx = animInst, idx end
        end
        if not chosen then chosen = ac.list[1] end
        if not chosen then goto continue end

        local ds = world.deathState[id]
        if ds and ds.phase == "blinking" and not ds.blinkVisible then goto continue end

        local dbEntry = animDB[chosen.name]
        if not (dbEntry and dbEntry.img) then goto continue end

        local fw, fh = dbEntry.fw, dbEntry.fh
        local drawScale = dbEntry.defaultScale * SCALE
        local rawFrame = math.floor(chosen.timer / chosen.frameLength)
        local frame
        if chosen.reverse then
            frame = (dbEntry.frames-1) - math.min(rawFrame, dbEntry.frames-1)
        elseif chosen.repeat_ then
            frame = rawFrame % dbEntry.frames
        else
            frame = math.min(rawFrame, dbEntry.frames-1)
        end

        local q = dbEntry.quads[frame]; if not q then goto continue end

        local faceRight = world.facing[id] and world.facing[id].right
        local flipSign  = faceRight and 1 or -1
        local sx, sy    = flipSign * drawScale, drawScale

        local tc = world.tintColor[id]
        local rR = tc and tc.R or 0
        local rG = tc and tc.G or 0
        if rR > 1 then
            local dim = (255 - rR) / 255
            love.graphics.setColor(dim, dim, dim, 1)
            love.graphics.draw(dbEntry.img, q, pos.x, pos.y, 0, sx, sy, fw/2, fh/2)
            love.graphics.setBlendMode("add")
            love.graphics.setColor(rR/255, 0, 0, 1)
            love.graphics.draw(dbEntry.img, q, pos.x, pos.y, 0, sx, sy, fw/2, fh/2)
            love.graphics.setBlendMode("alpha")
        elseif rG > 1 then
            local dim = (255 - rG) / 255
            love.graphics.setColor(dim, dim, dim, 1)
            love.graphics.draw(dbEntry.img, q, pos.x, pos.y, 0, sx, sy, fw/2, fh/2)
            love.graphics.setBlendMode("add")
            love.graphics.setColor(0, rG/255, 0, 1)
            love.graphics.draw(dbEntry.img, q, pos.x, pos.y, 0, sx, sy, fw/2, fh/2)
            love.graphics.setBlendMode("alpha")
        else
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(dbEntry.img, q, pos.x, pos.y, 0, sx, sy, fw/2, fh/2)
        end

        -- Selection highlight: additive white overlay on selected/pressed party unit
        local selAlpha = 0
        if id == battle.pressedUnit  then selAlpha = 0.55
        elseif id == battle.selectedUnit then selAlpha = 0.12
        end
        if selAlpha > 0 then
            love.graphics.setBlendMode("add")
            love.graphics.setColor(selAlpha, selAlpha, selAlpha, 1)
            love.graphics.draw(dbEntry.img, q, pos.x, pos.y, 0, sx, sy, fw/2, fh/2)
            love.graphics.setBlendMode("alpha")
        end

        ::continue::
    end
    love.graphics.setColor(1, 1, 1, 1)
end

local function barSystem()
    local BAR_W = 40; local BAR_H = 4; local BAR_GAP = 2; local ABOVE = 20
    for id in pairs(world.entities) do
        if world.deathState[id] then goto continue end
        local pos, sz, bar, ss, sg = world.position[id], world.size[id],
                                     world.bar[id], world.stats[id], world.stagger[id]
        if not (pos and sz and bar and ss) then goto continue end

        local topY = pos.y - sz.h/2
        local barX = pos.x - BAR_W/2
        local hpY  = topY - ABOVE - BAR_H
        local stgY = hpY + BAR_H + BAR_GAP

        love.graphics.setColor(0.2, 0.2, 0.2, 1)
        love.graphics.rectangle("fill", barX-2, hpY-1, BAR_W+4, BAR_H+2)

        local hp    = statGet(ss.HP)
        local maxHp = statGet(ss.maxHP)
        local ratio = (maxHp > 0) and math.max(0, hp/maxHp) or 0
        local r, g, b = unpack(bar.hpColor)
        love.graphics.setColor(r, g, b, 1)
        love.graphics.rectangle("fill", barX, hpY, BAR_W*ratio, BAR_H)

        if bar.hpPrevRatio > ratio then
            love.graphics.setColor(0.9, 0.1, 0.1, 0.6)
            love.graphics.rectangle("fill", barX+BAR_W*ratio, hpY,
                                    BAR_W*(bar.hpPrevRatio-ratio), BAR_H)
        end
        bar.hpPrevRatio = bar.hpPrevRatio + (ratio - bar.hpPrevRatio) * 0.05

        if sg then
            local maxSt   = statGet(ss.MAX_STAGGER)
            love.graphics.setColor(0.18, 0.18, 0.18, 1)
            love.graphics.rectangle("fill", barX, stgY, BAR_W, BAR_H)
            if sg.staggered then
                local staggerDur   = statGet(ss.STAGGER_DUR)
                local staggerRatio = (staggerDur > 0) and math.max(0, sg.timer/staggerDur) or 0
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.rectangle("fill", barX, stgY, BAR_W*staggerRatio, BAR_H)
            else
                local stRatio = (maxSt > 0) and math.min(1, sg.points/maxSt) or 0
                if stRatio > 0 then
                    love.graphics.setColor(1, 0.85, 0, 1)
                    love.graphics.rectangle("fill", barX, stgY, BAR_W*stRatio, BAR_H)
                end
                love.graphics.setColor(0.75, 0.75, 0.75, 1)
                love.graphics.rectangle("fill", barX+BAR_W-2, stgY, 2, BAR_H)
            end
        end

        if id == battle.hoveredUnit then
            local isEnemy = world.side[id] and world.side[id].s == 1
            local bright  = (id == battle.pressedUnit) and 1.0 or 0.65
            local r = isEnemy and bright or 0
            local g = isEnemy and 0      or bright
            love.graphics.setColor(r, g, 0, 1)
            love.graphics.setLineWidth(1)
            local plateH = BAR_H + BAR_GAP + BAR_H + 2
            love.graphics.rectangle("line", barX-3, hpY-2, BAR_W+6, plateH)
        end
        ::continue::
    end

    love.graphics.setFont(battle.smallFont)
    for i, id in ipairs(battle.partyIds) do
        local pos, sz = world.position[id], world.size[id]
        if not (pos and sz) then goto continue2 end
        local hpY = pos.y - sz.h/2 - ABOVE - BAR_H
        love.graphics.setColor(id == battle.selectedUnit and {0,1,0,1} or {1,1,1,1})
        love.graphics.print(tostring(i), pos.x - BAR_W/2 - 10, hpY)
        ::continue2::
    end
    love.graphics.setColor(1, 1, 1, 1)
end

local ICON_SIZE = 50; local ICON_GAP = 5; local ICON_X = 5; local ICON_Y = 5
local SKILL_KEYS = {"q", "w", "e", "r"}

local function getIconImage(iconName)
    if not iconName then return nil end
    local n = tonumber(iconName:match("skill_icons(%d+)"))
    return n and iconImages[n]
end

local function skillIconSystem(dt)
    local su = battle.selectedUnit; if not su then return end
    local sk = world.skills[su]; if not sk then return end
    for slotIdx = 1, 4 do
        local skill = sk.list[slotIdx]
        local ix = ICON_X + (slotIdx-1) * (ICON_SIZE+ICON_GAP)
        local iy = ICON_Y
        love.graphics.setColor(0.1, 0.1, 0.1, 0.8)
        love.graphics.rectangle("fill", ix, iy, ICON_SIZE, ICON_SIZE)
        if skill then
            local iconImg = getIconImage(skill.iconName)
            local sc = skill.iconScale or 1.0
            local cx, cy = ix+ICON_SIZE/2, iy+ICON_SIZE/2
            if iconImg then
                local iw, ih = iconImg:getDimensions()
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(iconImg, cx, cy, 0, ICON_SIZE*sc/iw, ICON_SIZE*sc/ih, iw/2, ih/2)
            else
                love.graphics.setColor(0.5, 0.5, 0.5, 1)
                love.graphics.rectangle("fill", cx-ICON_SIZE*sc/2, cy-ICON_SIZE*sc/2, ICON_SIZE*sc, ICON_SIZE*sc)
            end
            if skill.cdMax > 0 and skill.cd > 0 then
                local cdRatio = skill.cd / skill.cdMax
                love.graphics.setColor(0, 0, 0, 0.65)
                love.graphics.rectangle("fill", ix, iy, ICON_SIZE, ICON_SIZE*cdRatio)
            end
            local scTarget = skill.iconScaleTarget or 1.0
            skill.iconScale = (skill.iconScale or 1.0) + (scTarget-(skill.iconScale or 1.0)) * math.min(1, dt*12)
        end
        love.graphics.setFont(battle.smallFont)
        love.graphics.setColor(1, 1, 1, 0.7)
        love.graphics.print(string.upper(SKILL_KEYS[slotIdx]), ix+2, iy+ICON_SIZE-12)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(0.5, 0.5, 0.5, 1)
        love.graphics.rectangle("line", ix, iy, ICON_SIZE, ICON_SIZE)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

local function drawScene(dt)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, VW, VH)

    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.setLineWidth(1)
    love.graphics.line(0, BATTLE_LINE_Y, VW, BATTLE_LINE_Y)

    drawSelectionCircles()
    animSystem()
    drawBloodParticles()
    drawHealParticles()
    barSystem()
    skillIconSystem(dt)

    -- Victory overlay
    if battle.victoryTimer then
        local alpha = math.min(1, (2.0 - battle.victoryTimer) / 0.5)
        love.graphics.setColor(0, 0, 0, alpha * 0.5)
        love.graphics.rectangle("fill", 0, 0, VW, VH)
        love.graphics.setFont(battle.font)
        local txt = "VICTORY"
        local tw  = battle.font:getWidth(txt)
        love.graphics.setColor(1, 0, 0, alpha)
        love.graphics.print(txt, (VW-tw)/2, VH/2 - battle.font:getHeight())
    end

    love.graphics.setFont(battle.smallFont)
    love.graphics.setColor(1, 1, 1, 0.55)
    love.graphics.print("1-2: select  Q: slash  W: defend  K: spawn skeleton  RClick: target/move  Esc: retreat", 5, VH-14)
    love.graphics.setColor(1, 1, 1, 1)
end

-- ============================================================================
-- MODULE INTERFACE
-- ============================================================================

local M = {}

function M.onEnter(canvas, postfx, sw, sd, slot, encounterConfig)
    canvas_ref   = canvas
    postfx_ref   = postfx
    switchFn     = sw
    saveData_ref = sd
    slot_ref     = slot

    initWorld()
    initBattle(canvas, postfx)
    loadAssets(canvas, postfx)

    -- Start audio
    if battle.music1 then battle.music1:stop(); battle.music1:play() end
    if battle.music2 then battle.music2:stop(); battle.music2:play() end
    if battle.bell   then battle.bell:stop();   battle.bell:play()   end

    -- Initialize encounter manager from config (all values tunable before launch)
    local cfg = encounterConfig or {}
    local spawnDelay = cfg.spawnDelay or 4.0
    battle.encounterMgr = {
        dangerThreshold  = cfg.dangerThreshold  or 3,
        waveMinThreat    = cfg.waveMinThreat    or 3,
        waveMaxThreat    = cfg.waveMaxThreat    or 12,
        encounterGoal    = cfg.encounterGoal    or 45,
        spawnTimer       = spawnDelay,
        waveCooldown     = 0,
        currentDanger    = 0,
        dangerDefeated   = 0,
        surpriseTimer    = 30,
        surpriseInterval = 30,
        surpriseChance   = 0.15,
        pendingWave      = nil,
    }

    -- Spawn party walking in from the left edge, stacked vertically at x = VW/4
    local partyOrder  = sd and sd.partyOrder or {"knight"}
    local targetX     = VW * 0.25
    local partyFeetYs = { VH*0.50, VH*0.62, VH*0.74, VH*0.86 }
    local SLOT_H      = 40 * SCALE
    for i, charName in ipairs(partyOrder) do
        local charData = sd and sd.unlockedCharacters and sd.unlockedCharacters[charName]
        local ss = charData and charData.stats or nil
        local footY  = partyFeetYs[i] or (VH*0.50 + (i-1) * 55)
        local spawnY = footY - SLOT_H / 2
        local id
        if charName == "knight" then
            id = createKnight(-80, spawnY, ss)
        elseif charName == "nomad" then
            id = createNomad(-80, spawnY, ss)
        end
        if id then
            world.moveTarget[id].x      = targetX
            world.moveTarget[id].y      = footY
            world.moveTarget[id].active = true
            table.insert(battle.partyIds, id)
        end
    end
    battle.selectedUnit = battle.partyIds[1]
    -- Enemies are spawned by encounterManagerSystem after spawnTimer expires
end

function M.onExit()
    if battle.music1 then battle.music1:stop() end
    if battle.music2 then battle.music2:stop() end
    if battle.postfx then
        battle.postfx.chromasep.radius = common.CHROMA_RADIUS
    end
end

local function updateIconScaleAnimations(dt)
    local su = battle.selectedUnit; if not su then return end
    local sk = world.skills[su]; if not sk then return end
    for slotIdx = 1, 4 do
        local skill = sk.list[slotIdx]
        if skill then
            local held = love.keyboard.isDown(SKILL_KEYS[slotIdx])
            if held then
                skill.iconScaleTarget = 0.8
            else
                if (skill.iconScale or 1.0) < 0.95 and (skill.iconScaleTarget or 1.0) == 0.8 then
                    skill.iconScaleTarget = 1.1
                else
                    skill.iconScaleTarget = 1.0 + ((skill.iconScaleTarget or 1.0)-1.0) * math.max(0, 1-dt*6)
                end
            end
        end
    end
end

function M.update(dt)
    -- Victory timeout → return to map
    if battle.victoryTimer then
        battle.victoryTimer = battle.victoryTimer - dt
        if battle.victoryTimer <= 0 then
            switchFn("map", saveData_ref, slot_ref)
            return
        end
        -- Still run vfx decay during victory screen
        vfxDecaySystem(dt)
        return
    end

    updateBloodParticles(dt)
    updateHealParticles(dt)
    targetFollowSystem()
    pendingActiveSystem()
    autoAttackSystem()
    skillSystem(dt)
    effectSystem(dt)
    staggerSystem(dt)
    threatSystem(dt)
    moveTargetSystem(dt)
    antiClumpingSystem()
    physicsSystem(dt)
    updateAnimTimers(dt)
    deathSystem(dt)
    vfxDecaySystem(dt)
    updateIconScaleAnimations(dt)
    updateSelCircles(dt)
    encounterManagerSystem(dt)

    -- Hover detection for plate highlighting
    do
        local vmx, vmy = common.virtualMouse()
        battle.hoveredUnit = nil
        for id in pairs(world.entities) do
            if not world.deathState[id] then
                local pos, sz = world.position[id], world.size[id]
                if pos and sz
                and vmx >= pos.x-sz.w/2 and vmx <= pos.x+sz.w/2
                and vmy >= pos.y-sz.h/2 and vmy <= pos.y+sz.h/2 then
                    battle.hoveredUnit = id; break
                end
            end
        end
    end

    if battle.victoryDelay then
        battle.victoryDelay = battle.victoryDelay - dt
        if battle.victoryDelay <= 0 then
            battle.victoryDelay = nil
            battle.victoryTimer = 2.0
        end
    elseif checkVictory() then
        battle.victoryDelay = 2.0
    end
end

function M.keypressed(key)
    if key == "escape" then
        switchFn("map", saveData_ref, slot_ref)
        return
    end

    if key == "1" and battle.partyIds[1] and not battle.deadSlots[1] then battle.selectedUnit = battle.partyIds[1] end
    if key == "2" and battle.partyIds[2] and not battle.deadSlots[2] then battle.selectedUnit = battle.partyIds[2] end
    if key == "3" and battle.partyIds[3] and not battle.deadSlots[3] then battle.selectedUnit = battle.partyIds[3] end
    if key == "4" and battle.partyIds[4] and not battle.deadSlots[4] then battle.selectedUnit = battle.partyIds[4] end

    if key == "k" then
        local vmx, vmy = common.virtualMouse()
        createSkeleton(vmx, vmy)
    end

    local su = battle.selectedUnit; if not su then return end
    local sk = world.skills[su]; if not sk then return end

    local slotMap = {q=1, w=2, e=3, r=4}
    local slot = slotMap[key]
    if slot then
        local skill = sk.list[slot]
        if skill and skill.cd <= 0 then
            skill.cd = skill.cdMax; sk.pendingActive = slot
            triggerActivationVFX(su)
        end
    end
end

function M.mousepressed(x, y, button)
    local vmx, vmy = common.virtualMouse()

    if button == 1 then
        for i, id in ipairs(battle.partyIds) do
            if not battle.deadSlots[i] then
                local pos, sz = world.position[id], world.size[id]
                if pos and sz and vmx >= pos.x-sz.w/2 and vmx <= pos.x+sz.w/2
                and vmy >= pos.y-sz.h/2 and vmy <= pos.y+sz.h/2 then
                    battle.selectedUnit = id; break
                end
            end
        end
        return
    end

    if button ~= 2 then return end
    local su = battle.selectedUnit; if not su then return end
    if battle.hoveredUnit and not world.deathState[battle.hoveredUnit] then
        battle.pressedUnit = battle.hoveredUnit
    end

    local tSide = world.targetSide[su] or 1
    local clicked = nil
    for id in pairs(world.entities) do
        if world.deathState[id]           then goto scanNext end
        if id == su and tSide ~= 0        then goto scanNext end
        local sd, pos, sz = world.side[id], world.position[id], world.size[id]
        if sd and sd.s == tSide and pos and sz then
            if vmx >= pos.x-sz.w/2 and vmx <= pos.x+sz.w/2
            and vmy >= pos.y-sz.h/2 and vmy <= pos.y+sz.h/2 then
                clicked = id; break
            end
        end
        ::scanNext::
    end

    if clicked then
        world.entityTarget[su] = {id=clicked}
        if tSide == 1 then
            for id in pairs(world.entities) do
                local sd = world.side[id]
                if sd and sd.s == 1 and world.threatMap[id] then
                    world.threatMap[id].map[su] = world.threatMap[id].map[su] or 0
                end
            end
        end
    else
        local sgSu = world.stagger[su]
        if not (sgSu and sgSu.staggered) then
            world.entityTarget[su] = nil
        end
        local mt = world.moveTarget[su]
        if mt then mt.x=vmx; mt.y=vmy; mt.active=true end
        local sk = world.skills[su]
        if sk and sk.list[0] then sk.list[0].cd = 0 end
        cancelActionEffects(su)
    end
end

function M.mousereleased(x, y, button)
    if button == 2 then battle.pressedUnit = nil end
end

function M.draw()
    local vfx = battle.vfx

    love.graphics.setCanvas(battle.canvas)
    love.graphics.clear()
    drawScene(love.timer.getDelta())
    love.graphics.setCanvas()

    local ox, oy, s = common.letterbox()
    local zx, zy = vfx.zoomX, vfx.zoomY
    local zs = s * vfx.zoom
    local wx, wy = ox + zx*s, oy + zy*s
    local sk = math.floor(vfx.shake)
    local sox = sk > 0 and love.math.random(-sk, sk) or 0
    local soy = sk > 0 and love.math.random(-sk, sk) or 0

    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
    love.graphics.setColor(1, 1, 1, 1)

    battle.postfx(function()
        love.graphics.draw(battle.canvas, wx+sox, wy+soy, 0, zs, zs, zx, zy)
    end)
end

return M
