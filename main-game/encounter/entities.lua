-- encounter/entities.lua — Entity creation functions with shared template

local stats_mod  = require("encounter/stats")
local anim_mod   = require("encounter/anim")
local skills_mod = require("encounter/skills")
local effects_mod = require("encounter/effects")

local M = {}

-- ============================================================================
-- SHARED ENTITY TEMPLATE
-- ============================================================================

local function applyBaseComponents(world, id, x, y, w, h, side, st, opts)
    opts = opts or {}
    world.position[id]     = {x=x, y=y}
    world.size[id]         = {w=w, h=h}
    world.facing[id]       = {right = opts.faceRight ~= false}
    world.physics[id]      = {vx=0, vy=0, fx=0, fy=0}
    world.moveTarget[id]   = {x=x, y=y, active=false}
    world.side[id]         = {s=side}
    world.targetSide[id]   = opts.targetSide or (side == 0 and 1 or 0)
    world.stats[id]        = st
    world.locks[id]        = {actionLock=0, moveLock=0}
    world.stagger[id]      = {points=0, staggered=false, timer=0}
    world.stun[id]         = {stunned=false, timer=0}
    world.tintColor[id]    = {R=0, G=0, B=0}
    world.bar[id]          = {hpColor = opts.hpColor or {0, 1, 0}, hpPrevRatio=1, timer=0}
    world.effects_comp[id] = {pending={}, active={}}
    if opts.isRanged then world.isRanged[id] = true end
end

-- ============================================================================
-- KNIGHT
-- ============================================================================

function M.createKnight(world, battle, x, y, saveStats, SCALE, GRAVITY)
    local id = world:new()
    local st = saveStats and stats_mod.fromSave(saveStats) or stats_mod.newStats(100, 10, 5, 0.10)
    applyBaseComponents(world, id, x, y, 30*SCALE, 40*SCALE, 0, st)
    world.anim[id] = {list={
        [1] = anim_mod.newInst("KnightIdle",    10/60, true,  true),
        [2] = anim_mod.newInst("KnightMove",     6/60, true,  false),
        [3] = anim_mod.newInst("KnightAttack1",  6/60, false, false),
        [4] = anim_mod.newInst("KnightAttack2", 12/60, false, false),
        [5] = anim_mod.newInst("KnightTakeHit",  6/60, false, false),
        [6] = anim_mod.newInst("KnightDeath",    6/60, false, false),
    }}
    world.skills[id] = {
        list  = {
            [0] = skills_mod.newKnightAutoAttackSkill(SCALE, GRAVITY),
            [1] = skills_mod.newKnightSunderArmorSkill(SCALE, GRAVITY),
            [2] = skills_mod.newKnightDefendSkill(),
            [3] = skills_mod.newKnightChallengingShoutSkill(),
        },
        queue = {}, gcd = 0, pendingActive = nil,
    }
    -- Passives
    world.hasThreateningPresence[id] = true
    local ec = world.effects_comp[id]
    table.insert(ec.pending, effects_mod.newKnightRage(id))

    battle.selCircleScales[id] = 0
    return id
end

-- ============================================================================
-- SKELETON
-- ============================================================================

function M.createSkeleton(world, battle, x, y, SCALE, GRAVITY, ENEMY_DANGER)
    local id = world:new()
    local st = stats_mod.newStats(80, 8, 3, 0.05)
    applyBaseComponents(world, id, x, y, 40*SCALE, 40*SCALE, 1, st, {
        hpColor = {1, 1, 0},
        faceRight = false,
        targetSide = 1,
    })
    world.threatMap[id]   = {map={}, decayTimer=0}
    world.hasEntered[id]  = {h=false, v=false}
    world.dangerLevel[id] = ENEMY_DANGER.skeleton
    world.anim[id] = {list={
        [1] = anim_mod.newInst("SkeletonIdle",    4/60, true,  true),
        [2] = anim_mod.newInst("SkeletonMove",    4/60, true,  false),
        [3] = anim_mod.newInst("SkeletonAttack",  3/60, false, false),
        [4] = anim_mod.newInst("SkeletonDeath",   6/60, false, false),
    }}
    world.skills[id] = {list={[0]=skills_mod.newSkeletonAutoAttackSkill(SCALE, GRAVITY)}, queue={}, gcd=0}
    if #battle.partyIds > 0 then
        local tgtId = battle.partyIds[math.random(#battle.partyIds)]
        world.entityTarget[id] = {id=tgtId}
        world.threatMap[id].map[tgtId] = 1
        local sp, tp = world.position[id], world.position[tgtId]
        if sp and tp then world.facing[id].right = (tp.x > sp.x) end
    end
    return id
end

-- ============================================================================
-- NOMAD
-- ============================================================================

function M.createNomad(world, battle, x, y, saveStats, SCALE)
    local id = world:new()
    local st = saveStats and stats_mod.fromSave(saveStats) or stats_mod.newStats(80, 8, 2, 0.05)
    applyBaseComponents(world, id, x, y, 30*SCALE, 40*SCALE, 0, st, {isRanged=true, targetSide=0})
    world.anim[id] = {list={
        [1] = anim_mod.newInst("NomadIdle",    8/60, true,  true),
        [2] = anim_mod.newInst("NomadMove",    8/60, true,  false),
        [3] = anim_mod.newInst("NomadAttack1", 6/60, false, false),
        [4] = anim_mod.newInst("NomadAttack2", 6/60, false, false),
        [5] = anim_mod.newInst("NomadDeath",   6/60, false, false),
    }}
    world.skills[id] = {
        list  = {
            [0] = skills_mod.newNomadAutoHealSkill(SCALE),
            [1] = skills_mod.newNomadGrantPowerSkill(),
            [2] = skills_mod.newNomadMendWoundsSkill(),
            [3] = skills_mod.newNomadSparkOfInspirationSkill(),
        },
        queue = {}, gcd = 0, pendingActive = nil,
    }
    battle.selCircleScales[id] = 0
    return id
end

return M
