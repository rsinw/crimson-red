-- encounter/effects.lua — Generic effect system + all effect constructors

local M = {}

-- ============================================================================
-- EFFECT SYSTEM (processes pending → active → end lifecycle)
-- ============================================================================

function M.system(world, dt)
    for id in pairs(world.entities) do
        local ec = world.effects_comp[id]; if not ec then goto continue end
        for _, eff in ipairs(ec.pending) do table.insert(ec.active, eff) end
        ec.pending = {}
        local toRemove = {}
        for i, eff in ipairs(ec.active) do
            if eff.startFlag then
                if eff.start then eff.start(world, nil, eff) end
                eff.startFlag = false
            end
            if eff.cancelFlag then
                table.insert(toRemove, i)
            else
                if not eff.endFlag and eff.active then eff.active(world, nil, eff, dt) end
                if eff.endFlag then
                    if eff.end_fn then eff.end_fn(world, nil, eff) end
                    table.insert(toRemove, i)
                end
            end
        end
        for i = #toRemove, 1, -1 do table.remove(ec.active, toRemove[i]) end
        ::continue::
    end
end

-- ============================================================================
-- INDICATOR EFFECTS (tint flash on hit/heal)
-- ============================================================================

function M.newHurtIndicator(tgtId)
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

function M.newHealIndicator(tgtId)
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

-- ============================================================================
-- FORCE EFFECT (knockback)
-- ============================================================================

function M.newForce(tgtId, fx, fy, duration)
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

-- ============================================================================
-- TIMED ACTION EFFECT (generic: countdown then fire end_fn)
-- ============================================================================

function M.newTimedAction(srcId, tgtId, timer, endFn, opts)
    opts = opts or {}
    return {
        startFlag=true, endFlag=false,
        isActionEffect = opts.isActionEffect ~= false,
        isAction       = opts.isAction ~= false,
        skillSlot      = opts.skillSlot or 0,
        src=srcId, tgt=tgtId, timer=timer,
        start  = function(w, b, eff) eff.startFlag = false end,
        active = function(w, b, eff, dt)
            eff.timer = eff.timer - dt
            if eff.timer <= 0 then eff.endFlag = true end
        end,
        end_fn = endFn,
    }
end

-- ============================================================================
-- CHARACTER-SPECIFIC PASSIVE EFFECTS
-- ============================================================================

function M.newKnightRage(srcId)
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

function M.newHealing(srcId, statGet)
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

function M.newKnightDefend(srcId, statGet)
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
            if w.deathState[eff.src] then return end
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

-- ============================================================================
-- TAG SYSTEM (broadcasts events to conditional effects)
-- ============================================================================

function M.readTagSystem(world, tag)
    for _, ec in pairs(world.effects_comp) do
        for _, eff in ipairs(ec.active) do
            if eff.conditional then eff.conditional(world, nil, eff, tag) end
        end
    end
end

-- ============================================================================
-- CANCEL ACTION EFFECTS
-- ============================================================================

function M.cancelActions(world, id)
    local ec = world.effects_comp[id]; if not ec then return end
    local sk = world.skills[id]
    for _, eff in ipairs(ec.active) do
        if eff.isActionEffect then
            eff.cancelFlag = true
            if eff.skillSlot ~= nil and sk and sk.list[eff.skillSlot] then
                sk.list[eff.skillSlot].cd = 0
            end
        end
    end
    local sg = world.stagger[id]
    if sg and sg.staggered then return end
    local ac = world.anim[id]; if not ac then return end
    for _, a in pairs(ac.list) do a.active = false end
    if ac.list[1] then ac.list[1].active = true; ac.list[1].timer = 0 end
end

return M
