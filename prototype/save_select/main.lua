-- ============================================================================
-- Crimson Red — Save Select Screen Prototype
-- ============================================================================

package.path = package.path .. ";../shared/?.lua;../shared/?/init.lua"

local common    = require("common")
local moonshine = require("moonshine")

local VW = common.VW   -- 800
local VH = common.VH   -- 450

-- Post-processing values live in common.lua (CHROMA_RADIUS, BLOOM_*)

-- ============================================================================
-- LAYOUT
-- ============================================================================

local SLOT_COUNT    = 3
local SLOT_W        = 200
local SLOT_H        = 110
local SLOT_GAP      = 30
local SLOTS_TOTAL_W = SLOT_COUNT * SLOT_W + (SLOT_COUNT - 1) * SLOT_GAP
local SLOT_START_X  = math.floor((VW - SLOTS_TOTAL_W) / 2)
local TITLE_Y       = math.floor(VH * 0.39)
local BOX_Y         = TITLE_Y + math.floor(VH * 0.06)

-- Back arrow geometry (from common)
local AX      = common.ARROW_X
local AY      = common.ARROW_Y
local A_H     = common.ARROW_H
local A_W     = common.ARROW_W
local BOX_PAD = 5   -- padding around arrow when box targets it

-- Focusable items: 1 = back arrow, 2/3/4 = save slots 1/2/3
local ITEM_COUNT = 4

-- ============================================================================
-- STATE
-- ============================================================================

local canvas   -- scene canvas (nearest filter, VW×VH)
local postfx   -- moonshine chain: chromasep → glow

local labelFont, slotFont
local hoveredItem = nil
local pressedItem = nil
local box = common.newBox()

-- Placeholder data — replace with JSON later
local saveSlots = {
    {label = "SAVE 1", empty = true},
    {label = "SAVE 2", empty = true},
    {label = "SAVE 3", empty = true},
}

-- ============================================================================
-- HELPERS
-- ============================================================================

-- Red box target rect for each item
local function getBoxTarget(i)
    if i == 1 then
        return AX - BOX_PAD, AY - BOX_PAD, A_W + BOX_PAD*2, A_H + BOX_PAD*2
    else
        local si = i - 1
        return SLOT_START_X + (si-1)*(SLOT_W+SLOT_GAP), BOX_Y, SLOT_W, SLOT_H
    end
end

-- Mouse hit rect for each item
local function getHitRect(i)
    if i == 1 then
        return AX, AY, A_W, A_H
    else
        local si = i - 1
        return SLOT_START_X + (si-1)*(SLOT_W+SLOT_GAP), BOX_Y, SLOT_W, SLOT_H
    end
end

-- ============================================================================
-- LOVE CALLBACKS
-- ============================================================================

function love.load()
    canvas, postfx = common.setupWindow("Crimson Red — Save Select", moonshine)

    labelFont = common.loadFont(16)
    slotFont  = common.loadFont(12)

    -- Initialise box at save slot 1 (item 2)
    local bx, by, bw, bh = getBoxTarget(2)
    common.initBox(box, bx, by, bw, bh)
end

function love.update(dt)
    hoveredItem = common.hitTest(ITEM_COUNT, getHitRect)

    if hoveredItem then
        local tx, ty, tw, th = getBoxTarget(hoveredItem)
        common.setBoxTarget(box, tx, ty, tw, th)
    end

    common.updateBox(box, dt)
end

function love.mousepressed(x, y, button)
    if button ~= 1 then return end
    if hoveredItem then pressedItem = hoveredItem end
end

function love.mousereleased(x, y, button)
    if button ~= 1 then return end
    if pressedItem then
        local item = pressedItem
        pressedItem = nil
        if item == 1 then
            -- placeholder: return to title screen
        else
            -- placeholder: load/start save (item - 1)
        end
    end
end

function love.resize(w, h) postfx.resize(w, h) end
function love.keypressed(key) if key == "escape" then love.event.quit() end end

-- ============================================================================
-- DRAW
-- ============================================================================

local function drawScene()
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, VW, VH)

    -- White slot outlines (always present; red box overlays on top)
    love.graphics.setLineWidth(2)
    love.graphics.setColor(1, 1, 1, 1)
    for si = 1, SLOT_COUNT do
        local sx = SLOT_START_X + (si-1) * (SLOT_W + SLOT_GAP)
        love.graphics.rectangle("line", sx, BOX_Y, SLOT_W, SLOT_H)
    end

    -- Red box (drawn over outlines, under text)
    common.drawBox(box, pressedItem ~= nil)

    -- Back arrow (on top of box so it's always readable)
    common.drawBackArrow(pressedItem == 1)

    -- Slot labels and content text (always on top)
    for si = 1, SLOT_COUNT do
        local sx   = SLOT_START_X + (si-1) * (SLOT_W + SLOT_GAP)
        local item = si + 1

        -- "SAVE X" label above the box
        love.graphics.setFont(labelFont)
        local lw = labelFont:getWidth(saveSlots[si].label)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(saveSlots[si].label, sx + (SLOT_W - lw)/2, TITLE_Y)

        -- Content inside the box
        love.graphics.setFont(slotFont)
        local content = saveSlots[si].empty and "NEW GAME" or "SAVE DATA"
        local cw = slotFont:getWidth(content)
        local ch = slotFont:getHeight()
        common.setItemColor(pressedItem == item)
        love.graphics.print(content, sx + (SLOT_W - cw)/2, BOX_Y + (SLOT_H - ch)/2)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function love.draw()
    love.graphics.setCanvas(canvas)
    love.graphics.clear()
    drawScene()
    love.graphics.setCanvas()

    local ox, oy, scale = common.letterbox()
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
    love.graphics.setColor(1, 1, 1, 1)
    postfx(function()
        love.graphics.draw(canvas, ox, oy, 0, scale, scale)
    end)
end
