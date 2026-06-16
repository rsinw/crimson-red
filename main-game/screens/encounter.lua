-- screens/encounter.lua — Encounter/battle screen module (orchestrator)
-- Sub-modules live in encounter/ and handle stats, anim, particles,
-- effects, combat, skills, entities, systems, encounter manager, and UI.

local common       = require("common")
local anim_mod     = require("encounter/anim")
local particles    = require("encounter/particles")
local effects_mod  = require("encounter/effects")
local combat       = require("encounter/combat")
local skills_mod   = require("encounter/skills")
local entities_mod = require("encounter/entities")
local systems      = require("encounter/systems")
local enc_mgr      = require("encounter/encounter_mgr")
local ui           = require("encounter/ui")

local VW    = common.VW
local VH    = common.VH
local SCALE = VH / 300

local GRAVITY       = 9.8 * 30 * SCALE
local MASS          = 70
local FRICTION      = 0.9
local BATTLE_LINE_Y = VH * 0.2

local ENEMY_DANGER = { skeleton = 3 }

-- ============================================================================
-- MODULE STATE — reset each onEnter
-- ============================================================================

local world = {}
local battle = {
    font=nil, smallFont=nil, battlebg=nil,
    music1=nil, music2=nil, bell=nil,
}

local iconImages = {}
local assetsLoaded = false

local switchFn
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
end

-- ============================================================================
-- ASSET LOADING (once per session)
-- ============================================================================

local function getIconImage(iconName)
    if not iconName then return nil end
    local n = tonumber(iconName:match("skill_icons(%d+)"))
    return n and iconImages[n]
end

local function loadAssets()
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
    anim_mod.load("KnightIdle",    C.."Knight/Idle.png",      10, 135, 135, 1.0)
    anim_mod.load("KnightMove",    C.."Knight/Run.png",         6, 135, 135, 1.0)
    anim_mod.load("KnightAttack1", C.."Knight/Attack1.png",     4, 135, 135, 1.0)
    anim_mod.load("KnightAttack2", C.."Knight/Attack2.png",     4, 135, 135, 1.0)
    anim_mod.load("KnightTakeHit", C.."Knight/Take Hit.png",    3, 135, 135, 1.0)
    anim_mod.load("KnightDeath",   C.."Knight/Death.png",       9, 135, 135, 1.0)

    anim_mod.load("BrigandIdle",    C.."Brigand/Idle.png",     10, 126, 126, 1.0)
    anim_mod.load("BrigandMove",    C.."Brigand/Run.png",       8, 126, 126, 1.0)
    anim_mod.load("BrigandAttack1", C.."Brigand/Attack1.png",   7, 126, 126, 1.0)
    anim_mod.load("BrigandDeath",   C.."Brigand/Death.png",    11, 126, 126, 1.0)

    anim_mod.load("SkeletonIdle",   E.."Skeleton/Idle.png",     4, 150, 150, 0.75)
    anim_mod.load("SkeletonMove",   E.."Skeleton/Walk.png",     4, 150, 150, 0.75)
    anim_mod.load("SkeletonAttack", E.."Skeleton/Attack.png",   8, 150, 150, 0.75)
    anim_mod.load("SkeletonDeath",  E.."Skeleton/Death.png",    4, 150, 150, 0.75)

    anim_mod.load("BatIdle",   E.."Bat/Flight.png",  8, 150, 150, 0.75)
    anim_mod.load("BatAttack", E.."Bat/Attack.png",  8, 150, 150, 0.75)
    anim_mod.load("BatDeath",  E.."Bat/Death.png",   4, 150, 150, 0.75)

    anim_mod.load("ImpIdle",   E.."Imp/Idle.png",    4, 150, 150, 0.75)
    anim_mod.load("ImpMove",   E.."Imp/Move.png",    8, 150, 150, 0.75)
    anim_mod.load("ImpAttack", E.."Imp/Attack.png",  8, 150, 150, 0.75)
    anim_mod.load("ImpDeath",  E.."Imp/Death.png",   4, 150, 150, 0.75)

    anim_mod.load("MushroomIdle",   E.."Mushroom/Idle.png",    4, 150, 150, 0.75)
    anim_mod.load("MushroomMove",   E.."Mushroom/Move.png",    8, 150, 150, 0.75)
    anim_mod.load("MushroomAttack", E.."Mushroom/Attack.png",  8, 150, 150, 0.75)
    anim_mod.load("MushroomDeath",  E.."Mushroom/Death.png",   4, 150, 150, 0.75)

    anim_mod.load("NomadIdle",    C.."Nomad/Idle.png",     8, 250, 250, 0.54)
    anim_mod.load("NomadMove",    C.."Nomad/Run.png",       8, 250, 250, 0.54)
    anim_mod.load("NomadAttack1", C.."Nomad/Attack1.png",   8, 250, 250, 0.54)
    anim_mod.load("NomadAttack2", C.."Nomad/Attack2.png",   8, 250, 250, 0.54)
    anim_mod.load("NomadDeath",   C.."Nomad/Death.png",     7, 250, 250, 0.54)

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
-- DRAW SCENE (composites all render sub-systems)
-- ============================================================================

local function drawScene(dt)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, VW, VH)

    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.setLineWidth(1)
    love.graphics.line(0, BATTLE_LINE_Y, VW, BATTLE_LINE_Y)

    ui.drawSelectionCircles(world, battle)
    anim_mod.drawEntities(world, battle, SCALE)
    particles.drawBlood(battle)
    particles.drawHeal(battle)
    ui.barSystem(world, battle)
    ui.skillIconSystem(world, battle, dt)

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
    switchFn     = sw
    saveData_ref = sd
    slot_ref     = slot

    initWorld()
    initBattle(canvas, postfx)
    loadAssets()

    -- Expose icon lookup for UI sub-module
    battle.getIconImage = getIconImage

    -- Start audio
    if battle.music1 then battle.music1:stop(); battle.music1:play() end
    if battle.music2 then battle.music2:stop(); battle.music2:play() end
    if battle.bell   then battle.bell:stop();   battle.bell:play()   end

    -- Initialize encounter manager from config
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

    -- Spawn party walking in from the left edge
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
            id = entities_mod.createKnight(world, battle, -80, spawnY, ss, SCALE, GRAVITY)
        elseif charName == "nomad" then
            id = entities_mod.createNomad(world, battle, -80, spawnY, ss, SCALE)
        end
        if id then
            world.moveTarget[id].x      = targetX
            world.moveTarget[id].y      = footY
            world.moveTarget[id].active = true
            table.insert(battle.partyIds, id)
        end
    end
    battle.selectedUnit = battle.partyIds[1]
end

function M.onExit()
    if battle.music1 then battle.music1:stop() end
    if battle.music2 then battle.music2:stop() end
    if battle.postfx then
        battle.postfx.chromasep.radius = common.CHROMA_RADIUS
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
        systems.vfxDecay(battle, dt, common)
        return
    end

    particles.updateBlood(battle, dt, GRAVITY)
    particles.updateHeal(battle, dt)
    systems.targetFollow(world)
    skills_mod.pendingActiveSystem(world, battle)
    skills_mod.autoAttackSystem(world)
    skills_mod.system(world, battle, dt)
    effects_mod.system(world, battle, dt)
    systems.stagger(world, dt)
    systems.threat(world, battle, dt)
    systems.moveTarget(world, dt)
    systems.antiClumping(world)
    systems.physics(world, dt, VW, VH, BATTLE_LINE_Y, FRICTION, MASS)
    anim_mod.updateTimers(world, dt)
    systems.death(world, battle, dt)
    systems.vfxDecay(battle, dt, common)
    ui.updateIconScaleAnimations(world, battle, dt)
    ui.updateSelCircles(world, battle, dt)
    enc_mgr.system(world, battle, dt, VW, VH, SCALE, GRAVITY, ENEMY_DANGER)

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
    elseif enc_mgr.checkVictory(world, battle) then
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
        entities_mod.createSkeleton(world, battle, vmx, vmy, SCALE, GRAVITY, ENEMY_DANGER)
    end

    local su = battle.selectedUnit; if not su then return end
    local sk = world.skills[su]; if not sk then return end

    local slotMap = {q=1, w=2, e=3, r=4}
    local slot = slotMap[key]
    if slot then
        local skill = sk.list[slot]
        if skill and skill.cd <= 0 then
            skill.cd = skill.cdMax; sk.pendingActive = slot
            combat.triggerActivationVFX(battle, su, world)
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
        effects_mod.cancelActions(world, su)
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
