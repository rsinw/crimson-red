-- encounter/combat.lua — Damage calculation, hit/heal resolution, stagger, threat

local stats_mod    = require("encounter/stats")
local effects_mod  = require("encounter/effects")
local particles    = require("encounter/particles")
local anim_mod     = require("encounter/anim")

local statGet = stats_mod.get

local M = {}

-- ============================================================================
-- COMBAT MATH
-- ============================================================================

function M.calcNormalDmg(world, srcId, tgtId, value)
    local ss, ts = world.stats[srcId], world.stats[tgtId]
    if not (ss and ts) then return 0 end
    local boost = math.max(0.10, statGet(ss.BOOST))
    local res   = math.max(0.10, statGet(ts.RES))
    return math.max(0, (value * statGet(ss.ATK) * boost - statGet(ts.DEF)) * res)
end

function M.resolveHit(world, srcId, tgtId)
    local ss, ts = world.stats[srcId], world.stats[tgtId]
    if not (ss and ts) then return "HIT" end
    local crit = math.max(0, statGet(ss.CRIT) - statGet(ts.CRIT_DEF))
    return math.random() < crit and "CRIT" or "HIT"
end

-- ============================================================================
-- STAGGER
-- ============================================================================

function M.applyStagger(world, tgtId, dmg)
    local sg, ss = world.stagger[tgtId], world.stats[tgtId]
    if not (sg and ss) or sg.staggered then return end
    sg.points = sg.points + dmg * statGet(ss.STAGGER_RES)
    if sg.points >= statGet(ss.MAX_STAGGER) then
        sg.points = 0; sg.staggered = true
        sg.timer = statGet(ss.STAGGER_DUR); sg.reversingAnim = false
        ss.RES.add = ss.RES.add + 1
        anim_mod.activateDeathAnim(world, tgtId, true)
    end
end

-- ============================================================================
-- THREAT
-- ============================================================================

function M.addThreat(world, enemyId, allyId, amount)
    local tm = world.threatMap[enemyId]
    if tm then tm.map[allyId] = (tm.map[allyId] or 0) + amount end
end

-- ============================================================================
-- FACING
-- ============================================================================

function M.faceTarget(world, srcId, tgtId)
    local sp, tp = world.position[srcId], world.position[tgtId]
    if sp and tp and world.facing[srcId] then
        world.facing[srcId].right = (tp.x >= sp.x)
    end
end

-- ============================================================================
-- MELEE RANGE CHECK
-- ============================================================================

function M.checkMeleeRange(world, srcId, tgtId)
    local sp, ss = world.position[srcId], world.size[srcId]
    local tp, ts = world.position[tgtId], world.size[tgtId]
    if not (sp and ss and tp and ts) then return false end
    local dx = math.max(0, math.abs(sp.x-tp.x) - (ss.w/2+ts.w/2))
    local dy = math.max(0, math.abs(sp.y-tp.y) - (ss.h/2+ts.h/2))
    return math.sqrt(dx*dx+dy*dy) <= ss.w * 0.25
end

-- ============================================================================
-- VFX TRIGGERS
-- ============================================================================

function M.triggerActivationVFX(battle, casterId, world)
    local vfx = battle.vfx
    vfx.shake = math.min(vfx.shake+6, 20); vfx.chroma = math.min(vfx.chroma+2, 12)
    vfx.zoomTarget = 1.12
    local p = world.position[casterId]
    if p then vfx.zoomX, vfx.zoomY = p.x, p.y end
end

local function triggerHitVFX(battle, tgtId, world)
    local vfx = battle.vfx
    vfx.shake = math.min(vfx.shake+8, 20); vfx.chroma = math.min(vfx.chroma+3, 12)
    vfx.zoomTarget = 1.10
    local p = world.position[tgtId]
    if p then vfx.zoomX, vfx.zoomY = p.x, p.y end
end

-- ============================================================================
-- REGISTER HIT / HEAL
-- ============================================================================

function M.registerHit(world, battle, srcId, tgtId, keywords, useVFX, SCALE, GRAVITY)
    if not (world.entities[srcId] and world.entities[tgtId]) then return end
    local verdict = M.resolveHit(world, srcId, tgtId)
    local isCrit  = (verdict == "CRIT")
    local dmg     = M.calcNormalDmg(world, srcId, tgtId, 1.0)
    if isCrit then dmg = dmg * 2 end

    local ts = world.stats[tgtId]
    if ts then ts.HP.base = math.max(0, ts.HP.base - dmg) end

    M.applyStagger(world, tgtId, dmg)
    M.faceTarget(world, srcId, tgtId)

    local srcSide = world.side[srcId]
    if srcSide and srcSide.s == 0 then
        for id in pairs(world.entities) do
            if world.side[id] and world.side[id].s == 1 then
                M.addThreat(world, id, srcId, dmg * 0.5)
            end
        end
    end

    local ec = world.effects_comp[tgtId]
    if ec then table.insert(ec.pending, effects_mod.newHurtIndicator(tgtId)) end

    particles.spawnBlood(world, battle, srcId, tgtId, isCrit, SCALE, GRAVITY)
    if useVFX then triggerHitVFX(battle, tgtId, world) end

    local sp, tp = world.position[srcId], world.position[tgtId]
    if sp and tp then
        local dx, dy = tp.x - sp.x, tp.y - sp.y
        local len = math.sqrt(dx*dx + dy*dy)
        if len > 0.001 then dx, dy = dx/len, dy/len end
        local kbEc = world.effects_comp[tgtId]
        if kbEc then table.insert(kbEc.pending, effects_mod.newForce(tgtId, dx*400, dy*150, 0.12)) end
    end

    effects_mod.readTagSystem(world, {src=srcId, tgt=tgtId, keywords=keywords or {}, amount=dmg})

    local tgtMt = world.moveTarget[tgtId]
    if world.targetSide[tgtId] == 1 and not world.entityTarget[tgtId]
       and not (tgtMt and tgtMt.active)
       and world.entities[srcId] and not world.deathState[srcId] then
        world.entityTarget[tgtId] = {id=srcId}
    end
end

function M.registerHeal(world, battle, srcId, tgtId, value, SCALE)
    if not (world.entities[srcId] and world.entities[tgtId]) then return end
    local ss = world.stats[srcId]; if not ss then return end
    local ts = world.stats[tgtId]; if not ts then return end
    local amount = value * statGet(ss.ATK) * math.max(0.10, statGet(ss.BOOST))
    local maxHp  = statGet(ts.maxHP)
    ts.HP.base = math.min(maxHp, ts.HP.base + amount)
    particles.spawnHeal(world, battle, tgtId, SCALE)
    local ec = world.effects_comp[tgtId]
    if ec then table.insert(ec.pending, effects_mod.newHealIndicator(tgtId)) end
end

return M
