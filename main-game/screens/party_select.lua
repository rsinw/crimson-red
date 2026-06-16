-- screens/party_select.lua — Party select screen module

local common = require("common")
local save   = require("save")

local VW = common.VW
local VH = common.VH

-- ============================================================================
-- LAYOUT
-- ============================================================================

local ICON_SIZE     = 55
local PARTY_SLOTS   = 4
local PARTY_GAP     = 16
local PARTY_TOTAL_W = PARTY_SLOTS * ICON_SIZE + (PARTY_SLOTS - 1) * PARTY_GAP
local PARTY_X       = math.floor((VW - PARTY_TOTAL_W) / 2)
local PARTY_Y       = 50

-- Roster cells are ICON_SIZE wide × (ICON_SIZE + NAME_H) tall, flush against each
-- other (no gap) so grid lines fall on exact cell boundaries.
local ROSTER_COLS   = 6
local ROSTER_ROWS   = 2
local ROSTER_CELL_W = ICON_SIZE            -- 55
local ROSTER_NAME_H = 14
local ROSTER_CELL_H = ICON_SIZE + ROSTER_NAME_H  -- 69
local ROSTER_INNER_W = ROSTER_COLS * ROSTER_CELL_W   -- 330
local ROSTER_INNER_H = ROSTER_ROWS * ROSTER_CELL_H   -- 138
local ROSTER_PAD    = 8
local ROSTER_OUTER_W = ROSTER_INNER_W + ROSTER_PAD * 2  -- 346
local ROSTER_OUTER_H = ROSTER_INNER_H + ROSTER_PAD * 2  -- 154
local ROSTER_X      = math.floor((VW - ROSTER_OUTER_W) / 2)   -- 227
local ROSTER_Y      = 175
local ROSTER_INNER_X = ROSTER_X + ROSTER_PAD   -- 235
local ROSTER_INNER_Y = ROSTER_Y + ROSTER_PAD   -- 183

local AX        = 18
local AY        = 14
local A_H       = 20
local A_HEAD_W  = 12
local A_SHAFT_H = 8
local A_SHAFT_W = 16
local A_W       = A_HEAD_W + A_SHAFT_W
local BOX_PAD   = 5

-- ============================================================================
-- MODULE STATE
-- ============================================================================

local canvas_ref, postfx_ref, switchFn
local saveData_ref, slot_ref

local party    = {}   -- [1..4] charName or nil
local roster   = {}   -- ordered list of charNames not in active party
local icons    = {}   -- { [charName] = Image }
local drag     = { active = false }
local swapAnim = nil  -- animates a displaced icon to its new home

local assetsLoaded = false
local font          -- size 14, slot number labels
local nameFont      -- size 10, character name labels
local hoveredBack  = false
local pressedItem  = nil   -- "back" or nil
local box          = common.newBox()

-- ============================================================================
-- HELPERS
-- ============================================================================

local function getPartySlotRect(i)
    return PARTY_X + (i - 1) * (ICON_SIZE + PARTY_GAP), PARTY_Y, ICON_SIZE, ICON_SIZE
end

-- Returns top-left + full cell dimensions (including name zone for hit testing)
local function getRosterCellRect(idx)
    local col = (idx - 1) % ROSTER_COLS
    local row = math.floor((idx - 1) / ROSTER_COLS)
    return ROSTER_INNER_X + col * ROSTER_CELL_W,
           ROSTER_INNER_Y + row * ROSTER_CELL_H,
           ROSTER_CELL_W, ROSTER_CELL_H
end

local function drawIcon(name, x, y)
    local img = icons[name]
    if not img then return end
    local iw, ih = img:getDimensions()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x, y, 0, ICON_SIZE / iw, ICON_SIZE / ih)
end

local function drawArrow()
    love.graphics.setColor(pressedItem == "back" and 0 or 1, 0, 0, 1)
    love.graphics.polygon("fill",
        AX,            AY + A_H / 2,
        AX + A_HEAD_W, AY,
        AX + A_HEAD_W, AY + A_H)
    love.graphics.rectangle("fill",
        AX + A_HEAD_W - 2, AY + (A_H - A_SHAFT_H) / 2, A_SHAFT_W + 2, A_SHAFT_H)
end

-- ============================================================================
-- EXIT — saves partyOrder and returns to map
-- ============================================================================

local function exit()
    if drag.active then
        if drag.srcType == "party" then
            party[drag.srcIdx] = drag.charName
        end
        drag.active = false
    end
    if swapAnim then
        if swapAnim.dstType == "party" then
            party[swapAnim.dstIdx] = swapAnim.charName
        else
            table.insert(roster, math.min(swapAnim.dstIdx, #roster + 1), swapAnim.charName)
        end
        swapAnim = nil
    end

    local order = {}
    for i = 1, PARTY_SLOTS do
        if party[i] then order[#order + 1] = party[i] end
    end
    saveData_ref.partyOrder = order
    save.write(slot_ref, saveData_ref)
    switchFn("map", saveData_ref, slot_ref)
end

-- ============================================================================
-- DROP LOGIC
-- ============================================================================

local function completeDrop(vmx, vmy)
    if not drag.active then return end

    -- Roster drag: item was kept in table for visual continuity; remove it now
    if drag.srcType == "roster" then
        table.remove(roster, drag.srcIdx)
    end

    drag.active = false

    -- Drop onto a party slot
    for i = 1, PARTY_SLOTS do
        local sx, sy, sw, sh = getPartySlotRect(i)
        if vmx >= sx and vmx < sx + sw and vmy >= sy and vmy < sy + sh then
            local displaced = party[i]
            party[i] = drag.charName
            if displaced then
                swapAnim = {
                    charName = displaced,
                    x  = sx,  y  = sy,
                    tx = drag.srcCX - ICON_SIZE / 2,
                    ty = drag.srcCY - ICON_SIZE / 2,
                    t = 0, dur = 0.18,
                    dstType = drag.srcType,
                    dstIdx  = drag.srcIdx,
                }
            end
            return
        end
    end

    -- Drop onto the roster area
    if vmx >= ROSTER_X and vmx < ROSTER_X + ROSTER_OUTER_W
    and vmy >= ROSTER_Y and vmy < ROSTER_Y + ROSTER_OUTER_H then
        if drag.srcType == "party" then
            roster[#roster + 1] = drag.charName
        else
            table.insert(roster, drag.srcIdx, drag.charName)
        end
        return
    end

    -- No valid target: snap back silently
    if drag.srcType == "party" then
        party[drag.srcIdx] = drag.charName
    else
        table.insert(roster, drag.srcIdx, drag.charName)
    end
end

-- ============================================================================
-- MODULE INTERFACE
-- ============================================================================

local M = {}

function M.onEnter(canvas, postfx, sw, saveData, slot)
    canvas_ref   = canvas
    postfx_ref   = postfx
    switchFn     = sw
    saveData_ref = saveData
    slot_ref     = slot

    postfx_ref.chromasep.radius = common.CHROMA_RADIUS

    party = {}
    local inParty = {}
    for i, name in ipairs(saveData.partyOrder or {}) do
        if i <= PARTY_SLOTS then
            party[i] = name
            inParty[name] = true
        end
    end

    roster = {}
    local uc = saveData.unlockedCharacters or {}
    for name in pairs(uc) do
        if not inParty[name] then
            roster[#roster + 1] = name
        end
    end
    table.sort(roster)

    if not assetsLoaded then
        assetsLoaded = true
        font     = common.loadFont(14)
        nameFont = common.loadFont(10)
    end
    -- Load any icons not yet cached (handles new characters across save slots)
    for name in pairs(uc) do
        if not icons[name] then
            local ok, img = pcall(love.graphics.newImage, "assets/charicons/icon-" .. name .. ".png")
            if ok then icons[name] = img end
        end
    end

    drag        = { active = false }
    swapAnim    = nil
    hoveredBack = false
    pressedItem = nil

    common.initBox(box, AX - BOX_PAD, AY - BOX_PAD, A_W + BOX_PAD * 2, A_H + BOX_PAD * 2)
end

function M.update(dt)
    local vmx, vmy = common.virtualMouse()

    if drag.active then
        drag.x = vmx
        drag.y = vmy
    end

    if swapAnim then
        swapAnim.t = swapAnim.t + dt / swapAnim.dur
        if swapAnim.t >= 1 then
            if swapAnim.dstType == "party" then
                party[swapAnim.dstIdx] = swapAnim.charName
            else
                table.insert(roster, math.min(swapAnim.dstIdx, #roster + 1), swapAnim.charName)
            end
            swapAnim = nil
        end
    end

    -- Hover detection drives the animated box target
    hoveredBack = false
    if vmx >= AX and vmx < AX + A_W and vmy >= AY and vmy < AY + A_H then
        hoveredBack = true
        common.setBoxTarget(box, AX - BOX_PAD, AY - BOX_PAD, A_W + BOX_PAD * 2, A_H + BOX_PAD * 2)
    else
        -- Check party slots (all 4, even empty)
        local partyHit = false
        for i = 1, PARTY_SLOTS do
            local sx, sy, sw, sh = getPartySlotRect(i)
            if vmx >= sx and vmx < sx + sw and vmy >= sy and vmy < sy + sh then
                common.setBoxTarget(box, sx - BOX_PAD, sy - BOX_PAD, sw + BOX_PAD * 2, sh + BOX_PAD * 2)
                partyHit = true
                break
            end
        end
        -- Check roster cells (only occupied ones)
        if not partyHit then
            for idx = 1, #roster do
                if not (drag.active and drag.srcType == "roster" and drag.srcIdx == idx) then
                    local rx, ry, rw, rh = getRosterCellRect(idx)
                    if vmx >= rx and vmx < rx + rw and vmy >= ry and vmy < ry + ICON_SIZE then
                        common.setBoxTarget(box, rx, ry, ROSTER_CELL_W, ICON_SIZE)
                        break
                    end
                end
            end
        end
    end

    common.updateBox(box, dt)
end

function M.mousepressed(x, y, button)
    if button ~= 1 then return end
    local vmx, vmy = common.virtualMouse()

    if vmx >= AX and vmx < AX + A_W and vmy >= AY and vmy < AY + A_H then
        pressedItem = "back"
        return
    end

    for i = 1, PARTY_SLOTS do
        local sx, sy, sw, sh = getPartySlotRect(i)
        if party[i] and vmx >= sx and vmx < sx + sw and vmy >= sy and vmy < sy + sh then
            drag = {
                active   = true,
                charName = party[i],
                srcType  = "party",
                srcIdx   = i,
                srcCX    = sx + ICON_SIZE / 2,
                srcCY    = sy + ICON_SIZE / 2,
                x = vmx, y = vmy,
            }
            party[i] = nil
            return
        end
    end

    for idx, name in ipairs(roster) do
        local rx, ry, rw, rh = getRosterCellRect(idx)
        if vmx >= rx and vmx < rx + rw and vmy >= ry and vmy < ry + ICON_SIZE then
            drag = {
                active   = true,
                charName = name,
                srcType  = "roster",
                srcIdx   = idx,
                srcCX    = rx + ROSTER_CELL_W / 2,
                srcCY    = ry + ICON_SIZE / 2,
                x = vmx, y = vmy,
            }
            return
        end
    end
end

function M.mousereleased(x, y, button)
    if button ~= 1 then return end
    local vmx, vmy = common.virtualMouse()

    if pressedItem == "back" and hoveredBack then
        pressedItem = nil
        exit()
        return
    end
    pressedItem = nil

    completeDrop(vmx, vmy)
end

function M.keypressed(key)
    if key == "escape" or key == "return" or key == "kpenter" then
        exit()
    end
end

-- ============================================================================
-- DRAW
-- ============================================================================

local function drawScene()
    -- 1. Background
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, VW, VH)

    -- 2. Icons first (lines drawn on top afterwards)

    -- Roster icons + name labels
    love.graphics.setFont(nameFont)
    for idx, name in ipairs(roster) do
        local rx, ry = getRosterCellRect(idx)
        if not (drag.active and drag.srcType == "roster" and drag.srcIdx == idx) then
            drawIcon(name, rx, ry)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.printf(string.upper(name), rx, ry + ICON_SIZE + 2, ROSTER_CELL_W, "center")
        end
    end

    -- Party icons + number + name labels
    love.graphics.setFont(nameFont)
    for i = 1, PARTY_SLOTS do
        local sx, sy = getPartySlotRect(i)
        if party[i] then
            drawIcon(party[i], sx, sy)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.printf(string.upper(party[i]), sx, sy + ICON_SIZE + 16, ICON_SIZE, "center")
        end
    end

    -- Swap animation icon (in flight, above other icons)
    if swapAnim then
        local ax = swapAnim.x + (swapAnim.tx - swapAnim.x) * swapAnim.t
        local ay = swapAnim.y + (swapAnim.ty - swapAnim.y) * swapAnim.t
        drawIcon(swapAnim.charName, ax, ay)
    end

    -- 3. Lines and outlines (drawn on top of icons)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(2)

    -- Roster outer border
    love.graphics.rectangle("line", ROSTER_X, ROSTER_Y, ROSTER_OUTER_W, ROSTER_OUTER_H)

    -- Roster internal vertical grid lines (between columns)
    for c = 1, ROSTER_COLS - 1 do
        local lx = ROSTER_INNER_X + c * ROSTER_CELL_W
        love.graphics.line(lx, ROSTER_Y, lx, ROSTER_Y + ROSTER_OUTER_H)
    end

    -- Roster internal horizontal grid line (between rows)
    local ly = ROSTER_INNER_Y + ROSTER_CELL_H
    love.graphics.line(ROSTER_X, ly, ROSTER_X + ROSTER_OUTER_W, ly)

    -- Party slot outlines (white)
    for i = 1, PARTY_SLOTS do
        local sx, sy = getPartySlotRect(i)
        love.graphics.rectangle("line", sx, sy, ICON_SIZE, ICON_SIZE)
    end

    -- 4. Party slot number labels (white)
    love.graphics.setFont(font)
    for i = 1, PARTY_SLOTS do
        local sx, sy = getPartySlotRect(i)
        local lbl = tostring(i)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(lbl, sx + (ICON_SIZE - font:getWidth(lbl)) / 2, sy + ICON_SIZE + 4)
    end

    -- 5. Animated following red box
    common.drawBox(box, pressedItem == "back")

    -- 6. Back arrow (above box so it stays visible when pressed/filled white)
    drawArrow()

    -- 7. Dragged icon at cursor (absolute top)
    if drag.active then
        drawIcon(drag.charName, drag.x - ICON_SIZE / 2, drag.y - ICON_SIZE / 2)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function M.draw()
    love.graphics.setCanvas(canvas_ref)
    love.graphics.clear()
    drawScene()
    love.graphics.setCanvas()

    local ox, oy, scale = common.letterbox()
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
    love.graphics.setColor(1, 1, 1, 1)
    postfx_ref(function()
        love.graphics.draw(canvas_ref, ox, oy, 0, scale, scale)
    end)
end

return M
