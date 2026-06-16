-- screens/save_select.lua — Save Select screen module

local common = require("common")
local save   = require("save")

local VW = common.VW
local VH = common.VH

-- ============================================================================
-- LAYOUT (same as prototype)
-- ============================================================================

local SLOT_COUNT    = 3
local SLOT_W        = 200
local SLOT_H        = 110
local SLOT_GAP      = 30
local SLOTS_TOTAL_W = SLOT_COUNT * SLOT_W + (SLOT_COUNT - 1) * SLOT_GAP
local SLOT_START_X  = math.floor((VW - SLOTS_TOTAL_W) / 2)
local TITLE_Y       = math.floor(VH * 0.39)
local BOX_Y         = TITLE_Y + math.floor(VH * 0.06)

local AX      = common.ARROW_X
local AY      = common.ARROW_Y
local A_H     = common.ARROW_H
local A_W     = common.ARROW_W
local BOX_PAD = 5

local CLR_BTN_W = 60
local CLR_BTN_H = 16
local CLR_BTN_Y = BOX_Y + SLOT_H + 8

local ITEM_COUNT = 7  -- 1=back, 2/3/4=slots, 5/6/7=clear buttons

-- ============================================================================
-- MODULE STATE
-- ============================================================================

local canvas_ref, postfx_ref, switchFn

local labelFont, slotFont
local hoveredItem = nil
local pressedItem = nil
local box         = common.newBox()

local saveSlots = {}  -- rebuilt in onEnter from disk

local function getSlotCenterX(si)
    return SLOT_START_X + (si-1)*(SLOT_W+SLOT_GAP) + SLOT_W/2
end

local function getBoxTarget(i)
    if i == 1 then
        return AX - BOX_PAD, AY - BOX_PAD, A_W + BOX_PAD*2, A_H + BOX_PAD*2
    elseif i <= 4 then
        local si = i - 1
        return SLOT_START_X + (si-1)*(SLOT_W+SLOT_GAP), BOX_Y, SLOT_W, SLOT_H
    else
        local si = i - 4
        local cx = getSlotCenterX(si)
        return cx - CLR_BTN_W/2 - BOX_PAD, CLR_BTN_Y - BOX_PAD, CLR_BTN_W + BOX_PAD*2, CLR_BTN_H + BOX_PAD*2
    end
end

local function getHitRect(i)
    if i == 1 then
        return AX, AY, A_W, A_H
    elseif i <= 4 then
        local si = i - 1
        return SLOT_START_X + (si-1)*(SLOT_W+SLOT_GAP), BOX_Y, SLOT_W, SLOT_H
    else
        local si = i - 4
        local cx = getSlotCenterX(si)
        return cx - CLR_BTN_W/2, CLR_BTN_Y, CLR_BTN_W, CLR_BTN_H
    end
end

local function loadSlotInfo()
    saveSlots = {}
    for i = 1, SLOT_COUNT do
        if save.exists(i) then
            local data = save.load(i)
            if data then
                local party = data.partyOrder or {}
                local names = {}
                for _, name in ipairs(party) do
                    local uc = data.unlockedCharacters and data.unlockedCharacters[name]
                    local lv = uc and uc.level or 1
                    names[#names+1] = string.upper(name) .. " Lv." .. lv
                end
                saveSlots[i] = {
                    label   = "SAVE " .. i,
                    empty   = false,
                    summary = table.concat(names, "  "),
                }
            else
                saveSlots[i] = {label = "SAVE " .. i, empty=true}
            end
        else
            saveSlots[i] = {label = "SAVE " .. i, empty=true}
        end
    end
end

-- ============================================================================
-- MODULE INTERFACE
-- ============================================================================

local M = {}

function M.onEnter(canvas, postfx, sw)
    canvas_ref = canvas
    postfx_ref = postfx
    switchFn   = sw

    postfx_ref.chromasep.radius = common.CHROMA_RADIUS

    if not labelFont then
        labelFont = common.loadFont(16)
        slotFont  = common.loadFont(12)
    end

    loadSlotInfo()
    hoveredItem = nil
    pressedItem = nil

    local bx, by, bw, bh = getBoxTarget(2)
    common.initBox(box, bx, by, bw, bh)
end

function M.update(dt)
    local vmx, vmy = common.virtualMouse()

    hoveredItem = nil
    for i = 1, ITEM_COUNT do
        if i >= 5 and (saveSlots[i-4] or {}).empty then goto nextItem end
        local hx, hy, hw, hh = getHitRect(i)
        if vmx >= hx and vmx <= hx+hw and vmy >= hy and vmy <= hy+hh then
            hoveredItem = i; break
        end
        ::nextItem::
    end

    if hoveredItem then
        local tx, ty, tw, th = getBoxTarget(hoveredItem)
        common.setBoxTarget(box, tx, ty, tw, th)
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
        local item = pressedItem
        pressedItem = nil
        if item == 1 then
            switchFn("title")
        elseif item <= 4 then
            local si = item - 1
            local data
            if save.exists(si) then
                data = save.load(si)
            end
            if not data then
                data = save.defaultData()
                save.write(si, data)
            end
            switchFn("map", data, si)
        else
            local si = item - 4
            save.delete(si)
            loadSlotInfo()
        end
    end
end

function M.keypressed(key)
    if key == "escape" then switchFn("title") end
end

-- ============================================================================
-- DRAW
-- ============================================================================



local function drawScene()
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, VW, VH)

    -- White slot outlines
    love.graphics.setLineWidth(2)
    love.graphics.setColor(1, 1, 1, 1)
    for si = 1, SLOT_COUNT do
        local sx = SLOT_START_X + (si-1) * (SLOT_W + SLOT_GAP)
        love.graphics.rectangle("line", sx, BOX_Y, SLOT_W, SLOT_H)
    end

    -- Red box
    common.drawBox(box, pressedItem ~= nil)

    -- Back arrow
    common.drawBackArrow(pressedItem == 1)

    -- Slot content
    for si = 1, SLOT_COUNT do
        local sx   = SLOT_START_X + (si-1) * (SLOT_W + SLOT_GAP)
        local item = si + 1
        local slot = saveSlots[si] or {label="SAVE "..si, empty=true}

        love.graphics.setFont(labelFont)
        local lw = labelFont:getWidth(slot.label)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(slot.label, sx + (SLOT_W - lw)/2, TITLE_Y)

        love.graphics.setFont(slotFont)
        if slot.empty then
            local cw = slotFont:getWidth("NEW GAME")
            local ch = slotFont:getHeight()
            common.setItemColor(pressedItem == item)
            love.graphics.print("NEW GAME", sx + (SLOT_W-cw)/2, BOX_Y + (SLOT_H-ch)/2)
        else
            local summary = slot.summary or ""
            common.setItemColor(pressedItem == item)
            love.graphics.printf(summary, sx + 8, BOX_Y + 10, SLOT_W - 16, "center")
        end
    end

    -- Clear buttons (non-empty slots only)
    love.graphics.setFont(slotFont)
    for si = 1, SLOT_COUNT do
        local slot = saveSlots[si] or {empty=true}
        if not slot.empty then
            local item = si + 4
            local cx   = getSlotCenterX(si)
            local bx   = cx - CLR_BTN_W / 2
            local isPressed = pressedItem == item
            love.graphics.setColor(isPressed and 0.9 or 0.55, 0, 0, 1)
            love.graphics.rectangle("fill", bx, CLR_BTN_Y, CLR_BTN_W, CLR_BTN_H)
            local lbl = "CLEAR"
            local tw  = slotFont:getWidth(lbl)
            local th  = slotFont:getHeight()
            common.setItemColor(isPressed)
            love.graphics.print(lbl, bx + (CLR_BTN_W-tw)/2, CLR_BTN_Y + (CLR_BTN_H-th)/2)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function M.draw()
    common.renderFrame(canvas_ref, postfx_ref, drawScene)
end

return M
