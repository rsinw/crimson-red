-- ============================================================================
-- Crimson Red — Shared prototype module
-- Require from any prototype by adding to package.path first:
--   package.path = package.path .. ";../shared/?.lua;../shared/?/init.lua"
-- ============================================================================

local M = {}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

M.VW = 800
M.VH = 450

M.COLOR_RED   = {1, 0, 0, 1}
M.COLOR_WHITE = {1, 1, 1, 1}
M.COLOR_BLACK = {0, 0, 0, 1}

-- ============================================================================
-- MOONSHINE SETUP
-- ============================================================================
-- Both chromatic aberration and bloom are handled by Moonshine.
-- Call M.newPostFX() after requiring moonshine in your prototype.
--
-- Pipeline:
--   1. Draw scene into canvas  (nearest, VW×VH)
--   2. postfx(function() love.graphics.draw(canvas) end)  ← 1:1, no scale
--      postfx runs at fixed VW×VH so bloom is always the same strength.
--      The result lands in canvas2 because you set canvas2 active before calling postfx.
--   3. Scale canvas2 to screen with letterbox.
--
-- See newOutputCanvas() below for step 2 setup.

M.CHROMA_RADIUS  = 1.0   -- chromatic aberration pixel offset
M.BLOOM_MIN_LUMA = 0.15  -- pixels brighter than this glow (pure red luma ≈ 0.21)
M.BLOOM_STRENGTH = 3     -- glow spread (sigma); glow.lua only has strength + min_luma

function M.newPostFX(moonshine)
    -- Use .chain() not :chain() — colon passes self as the effect arg.
    -- Moonshine's internal buffers match the window size (resize via postfx.resize).
    -- vw/vh on each effect lock the UV pixel step to the virtual resolution so
    -- bloom and chromasep look identical regardless of how large the window is.
    local fx = moonshine(moonshine.effects.chromasep).chain(moonshine.effects.glow)
    fx.chromasep.angle  = 0
    fx.chromasep.radius = M.CHROMA_RADIUS
    fx.chromasep.vw     = M.VW
    fx.chromasep.vh     = M.VH
    fx.glow.min_luma    = M.BLOOM_MIN_LUMA
    fx.glow.strength    = M.BLOOM_STRENGTH
    fx.glow.vw          = M.VW
    fx.glow.vh          = M.VH
    return fx
end

-- ============================================================================
-- CANVAS HELPER
-- ============================================================================

-- Scene canvas: nearest filter keeps pixels crisp at native res.
-- Scale up happens inside the moonshine draw call.
function M.newSceneCanvas()
    local c = love.graphics.newCanvas(M.VW, M.VH)
    c:setFilter("nearest", "nearest")
    return c
end

-- ============================================================================
-- WINDOW / MOUSE HELPERS
-- ============================================================================

-- Maps real window mouse position to virtual 800x450 canvas coordinates
function M.virtualMouse()
    local mx, my = love.mouse.getPosition()
    local sw, sh = love.graphics.getDimensions()
    local s  = math.min(sw / M.VW, sh / M.VH)
    local ox = (sw - M.VW * s) / 2
    local oy = (sh - M.VH * s) / 2
    return (mx - ox) / s, (my - oy) / s
end

-- Returns ox, oy, scale for letterboxing the virtual canvas to the window
function M.letterbox()
    local sw, sh = love.graphics.getDimensions()
    local s  = math.min(sw / M.VW, sh / M.VH)
    return (sw - M.VW * s) / 2, (sh - M.VH * s) / 2, s
end

-- ============================================================================
-- BOX ANIMATION SYSTEM
-- ============================================================================
-- A persistent animated red outline box that glides between interactive items.
-- Once shown it never hides; when the mouse leaves it freezes at last position.

M.BOX_SPEED = 14  -- exponential lerp speed (higher = snappier)

local function lerp(a, b, t) return a + (b - a) * t end

-- Create a new box state table
function M.newBox()
    return {
        x = 0, y = 0, w = 0, h = 0,   -- current animated position
        tx = 0, ty = 0, tw = 0, th = 0, -- target position
        shown = false,
    }
end

-- Snap box to a position immediately and mark as shown
-- Call this on startup to set the initial position without animation
function M.initBox(box, x, y, w, h)
    box.x,  box.y,  box.w,  box.h  = x, y, w, h
    box.tx, box.ty, box.tw, box.th = x, y, w, h
    box.shown = true
end

-- Update the box target (called when a new item is hovered)
-- The box will animate toward the new target on the next updateBox call
function M.setBoxTarget(box, x, y, w, h)
    box.tx, box.ty, box.tw, box.th = x, y, w, h
    if not box.shown then
        -- Snap on first ever hover so it doesn't fly in from (0,0)
        box.x, box.y, box.w, box.h = x, y, w, h
        box.shown = true
    end
end

-- Advance the box animation. Call every frame regardless of hover state
-- so the box keeps gliding even after the mouse leaves an item.
function M.updateBox(box, dt)
    if not box.shown then return end
    local t = 1 - math.exp(-M.BOX_SPEED * dt)
    box.x = lerp(box.x, box.tx, t)
    box.y = lerp(box.y, box.ty, t)
    box.w = lerp(box.w, box.tw, t)
    box.h = lerp(box.h, box.th, t)
end

-- Draw the box: red outline normally, white fill when an item is pressed
function M.drawBox(box, pressed)
    if not box.shown then return end
    if pressed then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", box.x, box.y, box.w, box.h)
    else
        love.graphics.setColor(1, 0, 0, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", box.x, box.y, box.w, box.h)
    end
end

-- ============================================================================
-- FONT HELPER
-- ============================================================================

-- Load Dedicool at the given size (path relative to the calling prototype's dir)
function M.loadFont(size)
    local ok, f = pcall(love.graphics.newFont, "assets/dedicool/Dedicool.ttf", size)
    if not ok then print("[common] Font load error:", f) end
    return ok and f or love.graphics.newFont(size)
end

return M
