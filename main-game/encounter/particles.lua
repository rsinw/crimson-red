-- encounter/particles.lua — Blood and heal particle systems

local M = {}

-- ============================================================================
-- BLOOD PARTICLES
-- ============================================================================

function M.spawnBlood(world, battle, srcId, tgtId, isCrit, SCALE, GRAVITY)
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

function M.updateBlood(battle, dt, GRAVITY)
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

function M.drawBlood(battle)
    love.graphics.setColor(1, 0.08, 0.08, 1)
    for _, p in ipairs(battle.bloodParticles) do
        love.graphics.rectangle("fill", p.x-1, p.y-1, 2, 2)
    end
end

-- ============================================================================
-- HEAL PARTICLES
-- ============================================================================

function M.spawnHeal(world, battle, tgtId, SCALE)
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

function M.updateHeal(battle, dt)
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

function M.drawHeal(battle)
    for _, p in ipairs(battle.healParticles) do
        local a = p.timer / 0.8
        love.graphics.setColor(0.2, 1, 0.3, a)
        love.graphics.rectangle("fill", p.x - 1, p.y,     3, 1)
        love.graphics.rectangle("fill", p.x,     p.y - 1, 1, 3)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return M
