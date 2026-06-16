-- ============================================================================
-- Crimson Red — Title Screen Prototype
-- ============================================================================

package.path = package.path .. ";../shared/?.lua;../shared/?/init.lua"

local common   = require("common")
local moonshine = require("moonshine")

local VW = common.VW   -- 800
local VH = common.VH   -- 450

-- Post-processing values live in common.lua (CHROMA_RADIUS, BLOOM_*)

-- ============================================================================
-- LAYOUT
-- ============================================================================

local MENU_ITEMS = {"PLAY", "OPTIONS", "EXIT"}
local BOX_PAD_X  = 8
local BOX_PAD_Y  = 5

-- Declared here so getButtonRect (defined below) can close over them
local font, titleFont

-- Triangle logo geometry (Sierpinski pyramid, 3 rows)
local triangles = {}

local function buildTriangles()
    triangles = {}
    local cx     = VW / 2
    local size   = VH * 0.11
    local h      = size * math.sqrt(3) / 2
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

local function getButtonRect(i)
    local tw = font:getWidth(MENU_ITEMS[i])
    local th = font:getHeight()
    return (VW - tw) / 2, VH * 0.67 + (i - 1) * (VH * 0.09), tw, th
end

-- ============================================================================
-- STATE
-- ============================================================================

local canvas   -- scene canvas (nearest filter, VW×VH)
local postfx   -- moonshine chain: chromasep → glow

local hoveredItem = nil
local pressedItem = nil
local box = common.newBox()

-- ============================================================================
-- LOVE CALLBACKS
-- ============================================================================

function love.load()
    canvas, postfx = common.setupWindow("Crimson Red", moonshine)

    font      = common.loadFont(math.floor(VH * 0.0444))  -- ~20px
    titleFont = common.loadFont(math.floor(VH * 0.08))    -- ~36px

    buildTriangles()

    -- Initialise box at first button position
    local bx, by, bw, bh = getButtonRect(1)
    common.initBox(box, bx - BOX_PAD_X, by - BOX_PAD_Y, bw + BOX_PAD_X*2, bh + BOX_PAD_Y*2)
end

function love.update(dt)
    hoveredItem = common.hitTest(#MENU_ITEMS, getButtonRect)

    if hoveredItem then
        local bx, by, bw, bh = getButtonRect(hoveredItem)
        common.setBoxTarget(box, bx - BOX_PAD_X, by - BOX_PAD_Y, bw + BOX_PAD_X*2, bh + BOX_PAD_Y*2)
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
        local item = MENU_ITEMS[pressedItem]
        pressedItem = nil
        if item == "EXIT" then
            love.event.quit()
        elseif item == "PLAY" then
            -- placeholder: transition to save select
        elseif item == "OPTIONS" then
            -- placeholder
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

    -- Logo
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

    -- Red box (behind button text)
    common.drawBox(box, pressedItem ~= nil)

    -- Buttons
    love.graphics.setFont(font)
    for i, label in ipairs(MENU_ITEMS) do
        local bx, by = getButtonRect(i)
        common.setItemColor(pressedItem == i)
        love.graphics.print(label, bx, by)
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
