-- encounter/systems.lua — Physics, movement, targeting, anti-clumping, death, stagger

local stats_mod  = require("encounter/stats")
local anim_mod   = require("encounter/anim")
local combat     = require("encounter/combat")

local statGet = stats_mod.get

local M = {}

local function hasActiveAction(world, id)
    local ec = world.effects_comp[id]; if not ec then return false end
    for _, eff in ipairs(ec.active) do
        if eff.isAction then return true end
    end
    return false
end

-- ============================================================================
-- MELEE SLOT SELECTION
-- ============================================================================

local function getMeleeSlot(world, id, tgtId)
    local tp, ts = world.position[tgtId], world.size[tgtId]
    local sp, ss = world.position[id],    world.size[id]
    if not (tp and ts and sp and ss) then return nil end

    local anchorY = tp.y + ts.h / 2
    local hOffset = ts.w / 2 + ss.w / 2
    local leftX   = tp.x - hOffset
    local rightX  = tp.x + hOffset
    local SPACING = 20
    local myFootY = sp.y + ss.h / 2

    -- Anchor = whoever the target is CURRENTLY targeting (checked every frame).
    -- Only requires the anchor to be a living melee unit; no mutual-targeting check.
    local et_tgt   = world.entityTarget[tgtId]
    local anchorId = et_tgt and et_tgt.id
    if anchorId then
        if not world.entities[anchorId] or world.deathState[anchorId]
           or world.isRanged[anchorId] then
            anchorId = nil
        end
    end

    -- Anchor side is recomputed every frame using the anchor's INTENDED X
    -- (mt.x when moving, current pos otherwise) so stale values never linger.
    local ma = world.meleeAnchor
    if ma then
        if anchorId then
            local ap = world.position[anchorId]
            if ap then
                local amt    = world.moveTarget[anchorId]
                local anchorX = (amt and amt.active) and amt.x or ap.x
                local dL = math.abs(anchorX - leftX)
                local dR = math.abs(anchorX - rightX)
                ma[tgtId] = {id = anchorId, left = dL <= dR}
            end
        else
            ma[tgtId] = nil
        end
    end

    local anchorInfo = ma and ma[tgtId]

    if not anchorInfo then
        -- Enemy has no valid melee target: go to closest side at anchorY
        local dL = math.abs(sp.x - leftX)
        local dR = math.abs(sp.x - rightX)
        return (dL <= dR) and leftX or rightX, anchorY
    end

    if anchorInfo.id == id then
        -- ── SOLO (anchor) ─────────────────────────────────────────────────────
        -- Mutual targeting: recompute side from current position with a stable
        -- ID tiebreaker so both units never pick the same side simultaneously.
        local tgtEt = world.entityTarget[tgtId]
        if tgtEt and tgtEt.id == id then
            local dL = math.abs(sp.x - leftX)
            local dR = math.abs(sp.x - rightX)
            local goLeft = (dL < dR) or (dL == dR and id < tgtId)
            return goLeft and leftX or rightX, anchorY
        end
        return anchorInfo.left and leftX or rightX, anchorY

    else
        -- ── GROUP ─────────────────────────────────────────────────────────────
        -- Opposite side from anchor, evenly spaced with fixed gap.
        local groupX = anchorInfo.left and rightX or leftX

        local groupList = {}
        for oid in pairs(world.entities) do
            if oid == id or oid == anchorInfo.id then goto gskip end
            if world.deathState[oid]              then goto gskip end
            if world.isRanged[oid]               then goto gskip end
            local et2 = world.entityTarget[oid]
            if not (et2 and et2.id == tgtId) then goto gskip end
            local op, os = world.position[oid], world.size[oid]
            if not (op and os) then goto gskip end
            local mt2 = world.moveTarget[oid]
            local cy  = (mt2 and mt2.active) and mt2.y or (op.y + os.h / 2)
            table.insert(groupList, {id = oid, y = cy})
            ::gskip::
        end
        table.insert(groupList, {id = id, y = myFootY})
        table.sort(groupList, function(a, b)
            return a.y < b.y or (a.y == b.y and a.id < b.id)
        end)

        local n = #groupList
        for i, u in ipairs(groupList) do
            if u.id == id then
                local slotY = anchorY + (i - 1 - (n - 1) / 2) * SPACING
                return groupX, slotY
            end
        end
        return groupX, myFootY
    end
end

-- ============================================================================
-- TARGET FOLLOW
-- ============================================================================

function M.targetFollow(world)
    for id in pairs(world.entities) do
        if world.deathState[id] then goto continue end
        local et = world.entityTarget[id]
        if not et then goto continue end
        if not world.entities[et.id] or world.deathState[et.id] then
            world.entityTarget[id] = nil
            goto continue
        end
        local lk = world.locks[id]
        if hasActiveAction(world, id) or (lk and lk.moveLock > 0) then goto continue end
        local mt = world.moveTarget[id]; if not mt then goto continue end
        if world.isRanged[id] then goto continue end

        local tx, ty = getMeleeSlot(world, id, et.id)
        if not tx then goto continue end

        local sp = world.position[id]
        local ss = world.size[id]
        local tp = world.position[et.id]
        if not (sp and ss and tp) then goto continue end

        -- Unit must reach its exact slot before it can attack.
        -- Check X and Y proximity to the assigned slot directly — not just
        -- "in range" or "on the right side", which both pass while still
        -- in transit through the target area.
        local footY  = sp.y + ss.h / 2
        local atSlotX = math.abs(sp.x - tx) <= 4
        local atSlotY = math.abs(ty - footY) <= 4
        if atSlotX and atSlotY then
            mt.active = false
        else
            mt.x = tx; mt.y = ty; mt.active = true
        end
        ::continue::
    end
end

-- ============================================================================
-- MOVE TARGET
-- ============================================================================

function M.moveTarget(world, dt)
    for id in pairs(world.entities) do
        if world.deathState[id] then goto continue end
        local mt = world.moveTarget[id]; if not (mt and mt.active) then goto continue end
        if hasActiveAction(world, id) then mt.active = false; goto continue end
        local lk = world.locks[id]; if lk and lk.moveLock > 0 then goto continue end
        local sg = world.stagger[id]; if sg and sg.staggered then goto continue end
        local sn = world.stun[id]; if sn and sn.stunned then goto continue end
        local pos, sz, ss, ph = world.position[id], world.size[id], world.stats[id], world.physics[id]
        if not (pos and sz and ss and ph) then goto continue end
        local dx = mt.x - pos.x; local dy = mt.y - (pos.y + sz.h/2)
        local dist = math.sqrt(dx*dx + dy*dy)
        if dist < 1 then mt.active = false; goto continue end
        dx, dy = dx/dist, dy/dist
        local spd = statGet(ss.MOVE_SPEED) * 30
        local moveAmt = math.min(spd * dt, dist)
        pos.x = pos.x + dx * moveAmt; pos.y = pos.y + dy * moveAmt
        local fc = world.facing[id]
        if fc then fc.right = (dx > 0) end
        ::continue::
    end
end

-- ============================================================================
-- PHYSICS
-- ============================================================================

function M.physics(world, dt, VW, VH, BATTLE_LINE_Y, FRICTION, MASS)
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
                local he = world.hasEntered[id]
                if he then
                    if not he.h and pos.x >= sz.w/2 then he.h = true end
                    if he.h then
                        pos.x = math.max(sz.w/2, math.min(VW - sz.w/2, pos.x))
                    end
                    if not he.v and mb >= BATTLE_LINE_Y then he.v = true end
                    if he.v then
                        if mb < BATTLE_LINE_Y then pos.y = BATTLE_LINE_Y - sz.h/2 end
                        if mb > VH then pos.y = VH - sz.h/2 end
                    end
                else
                    pos.x = math.max(sz.w/2, math.min(VW - sz.w/2, pos.x))
                    if mb < BATTLE_LINE_Y then pos.y = BATTLE_LINE_Y - sz.h/2 end
                    if mb > VH then pos.y = VH - sz.h/2 end
                end
            elseif sd and sd.s == 1 then
                local he = world.hasEntered[id]
                if he and not he.h and pos.x <= VW - sz.w/2 then he.h = true end
                if he and he.h then
                    pos.x = math.max(sz.w/2, math.min(VW - sz.w/2, pos.x))
                end
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

-- ============================================================================
-- STAGGER + LOCK DECAY
-- ============================================================================

function M.stagger(world, dt)
    for id in pairs(world.entities) do
        if world.deathState[id] then goto continue end
        local sg = world.stagger[id]
        if sg and sg.staggered then
            if sg.reversingAnim then
                local di = anim_mod.getDeathAnimIdx(world, id)
                local ac = world.anim[id]
                if ac and di > 0 then
                    local da    = ac.list[di]
                    local entry = anim_mod.db[da and da.name]
                    if entry and da and da.timer >= da.frameLength * entry.frames then
                        sg.staggered = false; sg.reversingAnim = false
                        local ss = world.stats[id]
                        if ss then ss.RES.add = ss.RES.add - 1 end
                        local lk2 = world.locks[id]
                        if lk2 and not (world.stun[id] and world.stun[id].stunned) then lk2.actionLock = 0 end
                        local sn = world.stun[id]
                        if sn and sn.stunned and sn.timer > 0 then
                            da.active = true; da.timer = da.frameLength * entry.frames
                            da.reverse = nil; da.holdAtEnd = true
                        else
                            da.active = false; da.reverse = nil; da.timer = 0
                            if ac.list[1] then ac.list[1].active = true end
                        end
                    end
                end
            else
                sg.timer = sg.timer - dt
                if sg.timer <= 0 then
                    sg.reversingAnim = true
                    local di = anim_mod.getDeathAnimIdx(world, id)
                    local ac = world.anim[id]
                    if ac and di > 0 then
                        local da = ac.list[di]
                        da.active = true; da.timer = 0; da.reverse = true; da.holdAtEnd = false
                    end
                end
            end
        end
        local lk = world.locks[id]
        local sn = world.stun[id]
        if lk then
            if not (sg and sg.staggered) and not (sn and sn.stunned) then
                lk.actionLock = math.max(0, lk.actionLock - dt)
            end
            lk.moveLock = math.max(0, lk.moveLock - dt)
        end
        ::continue::
    end
end

-- ============================================================================
-- STUN
-- ============================================================================

function M.stunSystem(world, dt)
    for id in pairs(world.entities) do
        if world.deathState[id] then goto continue end
        local sn = world.stun[id]; if not (sn and sn.stunned) then goto continue end
        local sg = world.stagger[id]
        if sg and sg.staggered then goto continue end
        sn.timer = sn.timer - dt
        if sn.timer <= 0 then
            sn.stunned = false
            sn.timer = 0
            local lk = world.locks[id]
            if lk then lk.actionLock = 0 end
            local ac = world.anim[id]
            if ac then
                local di = anim_mod.getDeathAnimIdx(world, id)
                if di > 0 then
                    local da = ac.list[di]
                    da.active = true; da.timer = 0; da.reverse = true; da.holdAtEnd = false
                    sn.reversingAnim = true
                end
            end
        end
        ::continue::
    end
    for id in pairs(world.entities) do
        if world.deathState[id] then goto continue end
        local sn = world.stun[id]; if not (sn and sn.reversingAnim) then goto continue end
        local di = anim_mod.getDeathAnimIdx(world, id)
        local ac = world.anim[id]
        if ac and di > 0 then
            local da = ac.list[di]
            local entry = anim_mod.db[da and da.name]
            if entry and da and da.timer >= da.frameLength * entry.frames then
                sn.reversingAnim = false
                da.active = false; da.reverse = nil; da.timer = 0
                if ac.list[1] then ac.list[1].active = true end
            end
        end
        ::continue::
    end
end

-- ============================================================================
-- THREAT
-- ============================================================================

function M.threat(world, battle, dt)
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
            local prevEt = world.entityTarget[id]
            if not prevEt or prevEt.id ~= bestId then world.hasAttacked[id] = nil end
            world.entityTarget[id] = {id=bestId}
        elseif not world.entityTarget[id] then
            for _, pid in ipairs(battle.partyIds) do
                if not world.deathState[pid] then world.entityTarget[id] = {id=pid}; break end
            end
        end
        ::continue::
    end
end

-- ============================================================================
-- DEATH
-- ============================================================================

function M.death(world, battle, dt)
    local toDestroy = {}
    for id in pairs(world.entities) do
        local ds = world.deathState[id]
        if not ds then
            local ss = world.stats[id]
            if not (ss and statGet(ss.HP) <= 0) then goto continue end
            world.deathState[id] = {phase="dying", timer=2.5, blinkTimer=0, blinkVisible=true}
            anim_mod.activateDeathAnim(world, id, true)
            world.bar[id] = nil
            local mt = world.moveTarget[id]; if mt then mt.active = false end
            world.entityTarget[id] = nil
            for eid in pairs(world.entities) do
                local tm = world.threatMap[eid]
                if tm then tm.map[id] = nil end
                local et = world.entityTarget[eid]
                if et and et.id == id then
                    world.entityTarget[eid] = nil
                    world.hasAttacked[eid]  = nil
                end
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

-- ============================================================================
-- VFX DECAY
-- ============================================================================

function M.vfxDecay(battle, dt, common)
    local vfx = battle.vfx
    vfx.shake  = math.max(0, vfx.shake  - 18 * dt)
    vfx.chroma = math.max(0, vfx.chroma -  5 * dt)
    vfx.zoom   = vfx.zoom + (vfx.zoomTarget - vfx.zoom) * math.min(1, dt * 8)
    vfx.zoomTarget = vfx.zoomTarget + (1.0 - vfx.zoomTarget) * math.min(1, dt * 3)
    battle.postfx.chromasep.radius = common.CHROMA_RADIUS + vfx.chroma
end

function M.updateFacing(world)
    for id in pairs(world.entities) do
        if world.deathState[id] then goto continue end
        local sg = world.stagger[id]; if sg and sg.staggered then goto continue end
        local sn = world.stun[id]; if sn and sn.stunned then goto continue end
        local et = world.entityTarget[id]; if not et then goto continue end
        if not world.entities[et.id] or world.deathState[et.id] then goto continue end
        local sp = world.position[id]
        local tp = world.position[et.id]
        local fc = world.facing[id]
        if sp and tp and fc then
            fc.right = (tp.x >= sp.x)
        end
        ::continue::
    end
end

return M
