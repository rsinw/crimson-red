-- encounter/skills.lua — Skill definitions, skill system, auto-attack system

local effects_mod = require("encounter/effects")
local combat      = require("encounter/combat")
local stats_mod   = require("encounter/stats")

local statGet = stats_mod.get

local M = {}

M.GCD_DURATION = 1.0

-- ============================================================================
-- AUTO-ATTACK SKILLS (parametric)
-- ============================================================================

local function newAutoAttackSkill(name, cdMax, effectFn)
    return {
        name=name, isAutoAttack=true, cd=0, cdMax=cdMax,
        use = function(w, b, id, skill)
            local et = w.entityTarget[id]; if not et then return end
            local ac = w.anim[id]
            if ac and ac.list[3] then ac.list[3].active=true; ac.list[3].timer=0 end
            local ec = w.effects_comp[id]
            if ec then table.insert(ec.pending, effectFn(id, et.id, b)) end
            skill.cd = skill.cdMax
        end,
    }
end

function M.newKnightAutoAttackSkill(SCALE, GRAVITY)
    return newAutoAttackSkill("KnightAutoAttack", 2.0, function(srcId, tgtId, battle)
        return effects_mod.newTimedAction(srcId, tgtId, 12/60, function(w, b, eff)
            if w.entities[eff.tgt] then combat.registerHit(w, battle, eff.src, eff.tgt, {"Melee"}, false, SCALE, GRAVITY) end
        end)
    end)
end

function M.newSkeletonAutoAttackSkill(SCALE, GRAVITY)
    return newAutoAttackSkill("SkeletonAutoAttack", 2.0, function(srcId, tgtId, battle)
        return effects_mod.newTimedAction(srcId, tgtId, 21/60, function(w, b, eff)
            if w.entities[eff.tgt] then combat.registerHit(w, battle, eff.src, eff.tgt, {"Melee"}, false, SCALE, GRAVITY) end
        end, {isActionEffect=false})
    end)
end

function M.newNomadAutoHealSkill(SCALE)
    return newAutoAttackSkill("NomadAutoHeal", 2.5, function(srcId, tgtId, battle)
        return effects_mod.newTimedAction(srcId, tgtId, 24/60, function(w, b, eff)
            if w.entities[eff.tgt] and not w.deathState[eff.tgt] then
                combat.registerHeal(w, battle, eff.src, eff.tgt, 1.0, SCALE)
            end
        end)
    end)
end

-- ============================================================================
-- ACTIVE SKILLS
-- ============================================================================

function M.newKnightSunderArmorSkill(SCALE, GRAVITY)
    return {
        name="SunderArmor", iconName="skill_icons17",
        cd=0, cdMax=5.0, iconScale=1.0, iconScaleTarget=1.0,
        use = function(w, b, id, skill)
            local et = w.entityTarget[id]; if not et then return end
            local ac = w.anim[id]
            if ac and ac.list[4] then ac.list[4].active=true; ac.list[4].timer=0 end
            local ec = w.effects_comp[id]
            if ec then
                table.insert(ec.pending, effects_mod.newTimedAction(id, et.id, 24/60, function(w2, b2, eff)
                    if w2.entities[eff.tgt] then
                        combat.registerHit(w2, b, eff.src, eff.tgt, {"Melee","Slash"}, true, SCALE, GRAVITY)
                        local tec = w2.effects_comp[eff.tgt]
                        if tec then table.insert(tec.pending, effects_mod.newSunderArmor(eff.tgt)) end
                    end
                end, {skillSlot=1}))
            end
        end,
    }
end

function M.newKnightDefendSkill()
    return {
        name="KnightDefend", iconName="skill_icons22", noTargetRequired=true,
        cd=0, cdMax=30.0, iconScale=1.0, iconScaleTarget=1.0,
        use = function(w, b, id, skill)
            local ec = w.effects_comp[id]; if not ec then return end
            table.insert(ec.pending, effects_mod.newKnightDefend(id, statGet))
        end,
    }
end

-- ============================================================================
-- NOMAD SKILLS
-- ============================================================================

function M.newNomadGrantPowerSkill()
    return {
        name="GrantPower", iconName="skill_icons15",
        cd=0, cdMax=20.0, iconScale=1.0, iconScaleTarget=1.0,
        use = function(w, b, id, skill)
            local et = w.entityTarget[id]; if not et then return end
            local ac = w.anim[id]
            if ac and ac.list[4] then ac.list[4].active=true; ac.list[4].timer=0 end
            local ec = w.effects_comp[id]
            if ec then
                table.insert(ec.pending, effects_mod.newTimedAction(id, et.id, 24/60, function(w2, b2, eff)
                    if w2.entities[eff.tgt] then
                        local tec = w2.effects_comp[eff.tgt]
                        if tec then table.insert(tec.pending, effects_mod.newGrantPower(eff.tgt)) end
                    end
                end, {skillSlot=1}))
            end
        end,
    }
end

function M.newNomadMendWoundsSkill()
    return {
        name="MendWounds", iconName="skill_icons11",
        cd=0, cdMax=25.0, iconScale=1.0, iconScaleTarget=1.0,
        use = function(w, b, id, skill)
            local et = w.entityTarget[id]; if not et then return end
            local ac = w.anim[id]
            if ac and ac.list[4] then ac.list[4].active=true; ac.list[4].timer=0 end
            local ec = w.effects_comp[id]
            if ec then
                table.insert(ec.pending, effects_mod.newTimedAction(id, et.id, 24/60, function(w2, b2, eff)
                    if w2.entities[eff.tgt] then
                        local tec = w2.effects_comp[eff.tgt]
                        if tec then table.insert(tec.pending, effects_mod.newMendWounds(eff.src, eff.tgt, statGet)) end
                    end
                end, {skillSlot=2}))
            end
        end,
    }
end

function M.newNomadSparkOfInspirationSkill()
    return {
        name="SparkOfInspiration", iconName="skill_icons46",
        cd=0, cdMax=15.0, iconScale=1.0, iconScaleTarget=1.0,
        use = function(w, b, id, skill)
            local et = w.entityTarget[id]; if not et then return end
            local ac = w.anim[id]
            if ac and ac.list[4] then ac.list[4].active=true; ac.list[4].timer=0 end
            local ec = w.effects_comp[id]
            if ec then
                table.insert(ec.pending, effects_mod.newTimedAction(id, et.id, 24/60, function(w2, b2, eff)
                    if w2.entities[eff.tgt] then
                        local ts = w2.stats[eff.tgt]
                        if ts then
                            local curHp = statGet(ts.HP)
                            local sacrifice = curHp * 0.20
                            ts.HP.base = math.max(0, ts.HP.base - sacrifice)
                        end
                        -- TODO: regenerate 20 resource instantly (resource system not yet implemented)
                    end
                end, {skillSlot=3}))
            end
        end,
    }
end

function M.newKnightChallengingShoutSkill()
    return {
        name="ChallengingShout", iconName="skill_icons13", noTargetRequired=true,
        cd=0, cdMax=30.0, iconScale=1.0, iconScaleTarget=1.0,
        use = function(w, b, id, skill)
            local ss = w.stats[id]; if not ss then return end
            local flatThreat = 10 * statGet(ss.ATK)
            for eid in pairs(w.entities) do
                local sd = w.side[eid]
                if sd and sd.s == 1 and not w.deathState[eid] then
                    combat.addThreat(w, eid, id, flatThreat)
                    local ec = w.effects_comp[eid]
                    if ec then table.insert(ec.pending, effects_mod.newHurtIndicator(eid)) end
                end
            end
        end,
    }
end

-- ============================================================================
-- SKILL SYSTEM (processes cooldowns + queue)
-- ============================================================================

function M.system(world, battle, dt)
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
                if not skill.isAutoAttack then sk.gcd = M.GCD_DURATION end
            end
        end
        ::continue::
    end
end

-- ============================================================================
-- AUTO-ATTACK SYSTEM (queues auto attacks when ready)
-- ============================================================================

function M.autoAttackSystem(world)
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
        if not world.isRanged[id] and not combat.checkMeleeRange(world, id, et.id) then goto continue end
        local sg = world.stagger[id]; if sg and sg.staggered then goto continue end
        local sn = world.stun[id]; if sn and sn.stunned then goto continue end
        local alreadyQueued = false
        for _, qi in ipairs(sk.queue) do if qi == 0 then alreadyQueued=true; break end end
        if not alreadyQueued then table.insert(sk.queue, 0) end
        ::continue::
    end
end

-- ============================================================================
-- PENDING ACTIVE SYSTEM (processes skill activation from key press)
-- ============================================================================

function M.pendingActiveSystem(world, battle)
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
            if not world.isRanged[id] and not combat.checkMeleeRange(world, id, et.id) then goto continue end
        end
        local slot = sk.pendingActive
        local skill = sk.list[slot]
        if skill and skill.use then skill.use(world, battle, id, skill) end
        sk.gcd = M.GCD_DURATION; sk.pendingActive = nil
        ::continue::
    end
end

return M
