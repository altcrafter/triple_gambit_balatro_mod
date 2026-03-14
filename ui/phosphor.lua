--[[
    TRIPLE GAMBIT - ui/phosphor.lua
    Text rendering utility. Triple-strike + bloom rendering.
    Every other UI module calls this. Build this first.
]]

local Phosphor = {}

-- Font cache keyed by size
Phosphor.fonts      = {}
Phosphor.fonts_reg  = {}

local FONT_PATH_BOLD = TG_MOD_PATH and (TG_MOD_PATH .. "assets/fonts/JetBrainsMono-Bold.ttf") or ""
local FONT_PATH_REG  = TG_MOD_PATH and (TG_MOD_PATH .. "assets/fonts/JetBrainsMono-Regular.ttf") or ""

local SIZES = { 7, 8, 10, 11, 13, 16, 18, 20, 22, 26 }

function Phosphor.get_font(size)
    if not Phosphor.fonts[size] then
        local ok, font = pcall(love.graphics.newFont, FONT_PATH_BOLD, size)
        if ok and font then
            Phosphor.fonts[size] = font
        else
            Phosphor.fonts[size] = love.graphics.newFont(size)
        end
    end
    return Phosphor.fonts[size]
end

function Phosphor.get_font_reg(size)
    if not Phosphor.fonts_reg[size] then
        local ok, font = pcall(love.graphics.newFont, FONT_PATH_REG, size)
        if ok and font then
            Phosphor.fonts_reg[size] = font
        else
            Phosphor.fonts_reg[size] = love.graphics.newFont(size)
        end
    end
    return Phosphor.fonts_reg[size]
end

--[[
    TG.Phosphor.draw(text, x, y, color, glow, size, alpha)
    color: {r, g, b} table, 0-1 range
    glow:  0.0 to 3.0
    size:  font size in pixels
    alpha: optional, 0-1 (applied to all layers)
]]
function Phosphor.draw(text, x, y, color, glow, size, alpha)
    if not text or not x or not y then return end
    glow  = glow  or 0
    size  = size  or 11
    alpha = alpha or 1.0

    local font = Phosphor.get_font(size)
    love.graphics.setFont(font)

    local r = color and color[1] or 1
    local g = color and color[2] or 1
    local b = color and color[3] or 1

    -- Layer 1: Red ghost (chromatic aberration right)
    if glow >= 0.1 then
        local red_off   = 0.4 + glow * 0.6
        local red_alpha = math.min(0.4, glow * 0.25) * alpha
        love.graphics.setColor(1.0, 0.235, 0.392, red_alpha)
        love.graphics.print(text, math.floor(x + red_off), math.floor(y))
    end

    -- Layer 2: Blue ghost (chromatic aberration left)
    if glow >= 0.1 then
        local blue_off   = -(0.3 + glow * 0.5)
        local blue_alpha = math.min(0.3, glow * 0.2) * alpha
        love.graphics.setColor(0.235, 0.627, 1.0, blue_alpha)
        love.graphics.print(text, math.floor(x + blue_off), math.floor(y))
    end

    -- Layer 3: Main text at full color
    love.graphics.setColor(r, g, b, alpha)
    love.graphics.print(text, math.floor(x), math.floor(y))

    -- Layer 4: Bloom halo (additive blend, scaled up)
    if glow > 0 then
        local bloom_alpha = glow * 0.15 * alpha
        local scale       = 1 + glow * 0.08
        local tw = font:getWidth(text)
        local th = font:getHeight()
        local cx = x + tw / 2
        local cy = y + th / 2
        love.graphics.setBlendMode("add")
        love.graphics.setColor(r, g, b, bloom_alpha)
        love.graphics.push()
        love.graphics.translate(cx, cy)
        love.graphics.scale(scale, scale)
        love.graphics.translate(-tw / 2, -th / 2)
        love.graphics.print(text, 0, 0)
        love.graphics.pop()
        love.graphics.setBlendMode("alpha")
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- Measure text width using the bold font at given size
function Phosphor.width(text, size)
    size = size or 11
    local font = Phosphor.get_font(size)
    return font:getWidth(text)
end

function Phosphor.height(size)
    size = size or 11
    local font = Phosphor.get_font(size)
    return font:getHeight()
end

-- Preload common sizes
function Phosphor.init()
    for _, sz in ipairs(SIZES) do
        Phosphor.get_font(sz)
    end
end

return Phosphor
