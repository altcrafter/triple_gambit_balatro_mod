--[[
    TRIPLE GAMBIT - ui/phosphor.lua
    Text rendering utility. Triple-strike + bloom + dual-typeface system.
    Revision: Cormorant Garamond Bold (serif) + JetBrains Mono Bold (mono).

    Signature: TG.Phosphor.draw(text, x, y, color, glow, face, size, alpha, lean)
      face  = "serif" or "mono"  — NO default; caller must specify
      lean  = rotation in radians (optional, default 0; positive = clockwise)
      alpha = optional, 0-1 (default 1.0)

    Backward-compat: draw(text, x, y, color, glow, size_number, alpha) still works
    (face defaults to "mono" when 6th arg is a number).
]]

local Phosphor = {}

Phosphor._serif = {}  -- keyed by size: Cormorant Garamond Bold
Phosphor._mono  = {}  -- keyed by size: JetBrains Mono Bold

-- Legacy alias
Phosphor.fonts     = Phosphor._mono
Phosphor.fonts_reg = {}

local function _font_path(face)
    if not TG_MOD_PATH then return nil end
    if face == "serif" then
        return TG_MOD_PATH .. "assets/fonts/CormorantGaramond-Bold.ttf"
    else
        return TG_MOD_PATH .. "assets/fonts/JetBrainsMono-Bold.ttf"
    end
end

local SIZES = { 7, 8, 10, 11, 13, 16, 18, 20, 22, 26 }

-- ============================================================
-- FONT CACHE
-- ============================================================

function Phosphor.get_font(face, size)
    -- Legacy: get_font(size) → mono
    if type(face) == "number" then
        size, face = face, "mono"
    end
    face = face or "mono"
    size = size or 11

    local cache = (face == "serif") and Phosphor._serif or Phosphor._mono
    if not cache[size] then
        local path = _font_path(face)
        local ok, font = false, nil
        if path then
            ok, font = pcall(love.graphics.newFont, path, size)
        end
        cache[size] = (ok and font) or love.graphics.newFont(size)
    end
    return cache[size]
end

-- Legacy single-arg (always mono)
function Phosphor.get_font_reg(size)
    return Phosphor.get_font("mono", size)
end

-- ============================================================
-- DRAW
-- ============================================================

--[[
    TG.Phosphor.draw(text, x, y, color, glow, face, size, alpha, lean)

    Four-layer rendering:
      1. Red ghost  — chromatic aberration right (+offset)
      2. Blue ghost — chromatic aberration left (-offset)
      3. Main text  — at original position, actual color
      4. Bloom halo — additive blend, scaled up by (1 + glow*0.08)
]]
function Phosphor.draw(text, x, y, color, glow, face, size, alpha, lean)
    if not text or not x or not y then return end

    -- Legacy compat: if 6th arg is a number it's the old (glow, size, alpha) signature
    if type(face) == "number" then
        lean, alpha, size, face = nil, size, face, "mono"
    end

    glow  = glow  or 0
    face  = face  or "mono"
    size  = size  or 11
    alpha = alpha or 1.0
    lean  = lean  or 0

    local font = Phosphor.get_font(face, size)
    local tw   = font:getWidth(text)
    local th   = font:getHeight()

    local r = (color and color[1]) or 1
    local g = (color and color[2]) or 1
    local b = (color and color[3]) or 1

    -- Apply lean rotation around text center pivot
    local has_lean = lean ~= 0
    if has_lean then
        local px = x + tw * 0.5
        local py = y + th * 0.5
        love.graphics.push()
        love.graphics.translate(px, py)
        love.graphics.rotate(lean)
        love.graphics.translate(-px, -py)
    end

    love.graphics.setFont(font)

    -- Layer 1: Red ghost (chromatic aberration right)
    if glow >= 0.1 then
        local off   = 0.4 + glow * 0.6
        local a     = math.min(0.4, glow * 0.25) * alpha
        love.graphics.setColor(1.0, 0.235, 0.392, a)
        love.graphics.print(text, math.floor(x + off), math.floor(y))
    end

    -- Layer 2: Blue ghost (chromatic aberration left)
    if glow >= 0.1 then
        local off   = -(0.3 + glow * 0.5)
        local a     = math.min(0.3, glow * 0.2) * alpha
        love.graphics.setColor(0.235, 0.627, 1.0, a)
        love.graphics.print(text, math.floor(x + off), math.floor(y))
    end

    -- Layer 3: Main text
    love.graphics.setColor(r, g, b, alpha)
    love.graphics.print(text, math.floor(x), math.floor(y))

    -- Layer 4: Bloom halo (additive blend, scaled up)
    if glow > 0 then
        local bloom_a = glow * 0.15 * alpha
        local scale   = 1 + glow * 0.08
        local cx      = x + tw * 0.5
        local cy      = y + th * 0.5
        love.graphics.setBlendMode("add")
        love.graphics.setColor(r, g, b, bloom_a)
        love.graphics.push()
        love.graphics.translate(cx, cy)
        love.graphics.scale(scale, scale)
        love.graphics.translate(-tw * 0.5, -th * 0.5)
        love.graphics.print(text, 0, 0)
        love.graphics.pop()
        love.graphics.setBlendMode("alpha")
    end

    if has_lean then
        love.graphics.pop()
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- ============================================================
-- MEASUREMENT
-- ============================================================

function Phosphor.width(text, face, size)
    -- Legacy: width(text, size) → mono
    if type(face) == "number" then
        size, face = face, "mono"
    end
    return Phosphor.get_font(face or "mono", size or 11):getWidth(text)
end

function Phosphor.height(face, size)
    -- Legacy: height(size) → mono
    if type(face) == "number" then
        size, face = face, "mono"
    end
    return Phosphor.get_font(face or "mono", size or 11):getHeight()
end

-- ============================================================
-- INIT
-- ============================================================

function Phosphor.init()
    for _, sz in ipairs(SIZES) do
        Phosphor.get_font("serif", sz)
        Phosphor.get_font("mono",  sz)
    end
end

return Phosphor
