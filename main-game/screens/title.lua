-- screens/title.lua — Title screen module

local common = require("common")

local VW = common.VW
local VH = common.VH

-- ============================================================================
-- LAYOUT
-- ============================================================================

local MENU_ITEMS = {"PLAY", "OPTIONS", "EXIT"}
local BOX_PAD_X  = 8
local BOX_PAD_Y  = 5

local triangles = {}

local function buildTriangles()
    triangles = {}
    local cx   = VW / 2
    local size = VH * 0.11
    local h    = size * math.sqrt(3) / 2
    local startY = VH * 0.08

    local function upTri(cx2, y)
        return { cx2, y, cx2 - size/2, y + h, cx2 + size/2, y + h }
    end

    local r1y = startY
    table.insert(triangles, upTri(cx, r1y))
    local r2y = r1y + h
    table.insert(triangles, upTri(cx - size/2, r2y))
    table.insert(triangles, upTri(cx + size/2, r2y))
    local r3y = r2y + h
    table.insert(triangles, upTri(cx - size,   r3y))
    table.insert(triangles, upTri(cx,          r3y))
    table.insert(triangles, upTri(cx + size,   r3y))
end

-- ============================================================================
-- MODULE STATE
-- ============================================================================

local canvas_ref, postfx_ref, switchFn

local font, titleFont
local hoveredItem = nil
local pressedItem = nil
local box         = common.newBox()

local function getButtonRect(i)
    local tw = font:getWidth(MENU_ITEMS[i])
    local th = font:getHeight()
    return (VW - tw) / 2, VH * 0.67 + (i-1) * (VH * 0.09), tw, th
end

-- ============================================================================
-- MODULE INTERFACE
-- ============================================================================

local M = {}

function M.onEnter(canvas, postfx, sw)
    canvas_ref = canvas
    postfx_ref = postfx
    switchFn   = sw

    -- Reset postfx to baseline (encounter may have elevated chroma)
    postfx_ref.chromasep.radius = common.CHROMA_RADIUS

    -- Load fonts once (re-use across onEnter calls)
    if not font then
        font      = common.loadFont(math.floor(VH * 0.0444))
        titleFont = common.loadFont(math.floor(VH * 0.08))
    end

    hoveredItem = nil
    pressedItem = nil

    buildTriangles()

    local bx, by, bw, bh = getButtonRect(1)
    common.initBox(box, bx - BOX_PAD_X, by - BOX_PAD_Y, bw + BOX_PAD_X*2, bh + BOX_PAD_Y*2)
end

function M.update(dt)
    hoveredItem = common.hitTest(#MENU_ITEMS, getButtonRect)

    if hoveredItem then
        local bx, by, bw, bh = getButtonRect(hoveredItem)
        common.setBoxTarget(box, bx-BOX_PAD_X, by-BOX_PAD_Y, bw+BOX_PAD_X*2, bh+BOX_PAD_Y*2)
    end

    common.updateBox(box, dt)
end

function M.mousepressed(x, y, button)
    if button ~= 1 then return end
    if hoveredItem then pressedItem = hoveredItem end
end

function M.mousereleased(x, y, button)
    if button ~= 1 then return end
    if pressedItem then
        local item = MENU_ITEMS[pressedItem]
        pressedItem = nil
        if item == "PLAY" then
            switchFn("save_select")
        elseif item == "EXIT" then
            love.event.quit()
        end
    end
end

function M.keypressed(key)
    if key == "escape" then love.event.quit() end
end

local function drawScene()
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, VW, VH)

    -- Logo (Sierpinski triangles)
    love.graphics.setColor(1, 0, 0, 1)
    for _, tri in ipairs(triangles) do
        love.graphics.polygon("fill", tri[1], tri[2], tri[3], tri[4], tri[5], tri[6])
    end

    -- Title
    love.graphics.setFont(titleFont)
    local title = "crimson red"
    local tw    = titleFont:getWidth(title)
    love.graphics.setColor(1, 0, 0, 1)
    love.graphics.print(title, (VW - tw) / 2, VH * 0.49)

    -- Red box
    common.drawBox(box, pressedItem ~= nil)

    -- Menu items
    love.graphics.setFont(font)
    for i, label in ipairs(MENU_ITEMS) do
        local bx, by = getButtonRect(i)
        common.setItemColor(pressedItem == i)
        love.graphics.print(label, bx, by)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function M.draw()
    common.renderFrame(canvas_ref, postfx_ref, drawScene)
end

return M
