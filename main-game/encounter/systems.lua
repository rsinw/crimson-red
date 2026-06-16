-- encounter/systems.lua — Physics, movement, targeting, anti-clumping, death, stagger

local stats_mod  = require("encounter/stats")
local anim_mod   = require("encounter/anim")
local combat     = require("encounter/combat")

local statGet = stats_mod.get

local M = {}

-- ============================================================================
-- TARGET FOLLOW
-- ============================================================================

function M.targetFollow(world)
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
        if combat.checkMeleeRange(world, id, et.id) then
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

-- ============================================================================
-- MOVE TARGET
-- ============================================================================

local function hasActiveAction(world, id)
    local ec = world.effects_comp[id]; if not ec then return false end
    for _, eff in ipairs(ec.active) do
        if eff.isAction then return true end
    end
    return false
end

function M.moveTarget(world, dt)
    for id in pairs(world.entities) do
        if world.deathState[id] then goto continue end
        local mt = world.moveTarget[id]; if not (mt and mt.active) then goto continue end
        if hasActiveAction(world, id) then mt.active = false; goto continue end
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

-- ============================================================================
-- ANTI-CLUMPING
-- ============================================================================

function M.antiClumping(world)
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
                pos.x = math.max(sz.w/2, math.min(VW - sz.w/2, pos.x))
                if mb < BATTLE_LINE_Y then pos.y = BATTLE_LINE_Y - sz.h/2 end
                if mb > VH then pos.y = VH - sz.h/2 end
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
        if lk then
            lk.actionLock = math.max(0, lk.actionLock - dt)
            lk.moveLock   = math.max(0, lk.moveLock - dt)
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

return M
