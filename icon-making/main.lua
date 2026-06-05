local size = 512
local canvas

local function saveImageDataToProjectFolder(imageData, filename)
    local pngData = imageData:encode("png")
    local fullPath = love.filesystem.getSource() .. "/" .. filename

    local file, err = io.open(fullPath, "wb")
    if not file then
        print("Could not save file: " .. tostring(err))
        return
    end

    file:write(pngData:getString())
    file:close()

    print("Saved: " .. fullPath)
end

local function drawQuestionMark()
    love.graphics.setCanvas(canvas)

    -- inverted colors: white background
    love.graphics.clear(1, 1, 1, 1)

    -- black symbol
    love.graphics.setColor(0, 0, 0, 1)

    -- large font for clean question mark
    local font = love.graphics.newFont(300)
    love.graphics.setFont(font)

    local text = "?"
    local textWidth = font:getWidth(text)
    local textHeight = font:getHeight()

    local x = (size - textWidth) / 2
    local y = 20

    love.graphics.print(text, x, y)

    -- black dot underneath
    love.graphics.circle("fill", size / 2, 430, 38)

    love.graphics.setCanvas()
end

function love.load()
    love.window.setMode(size, size, {resizable = false})
    love.window.setTitle("Inverted Question Mark Icon")

    canvas = love.graphics.newCanvas(size, size)
    drawQuestionMark()

    local imageData = canvas:newImageData()
    saveImageDataToProjectFolder(imageData, "question_inverted.png")
end

function love.draw()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(canvas, 0, 0)
end