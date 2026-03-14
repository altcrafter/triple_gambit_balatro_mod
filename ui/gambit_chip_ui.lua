--[[
    TRIPLE GAMBIT - ui/gambit_chip_ui.lua
    REWRITE. Chip stack drawer with broadcast palette.
    DELETE: earth/loam palette, WIND mote system.
    REPLACE: broadcast colors, phosphor text, tier bars with bloom glow.
    Tab at bottom-right: "▴ CHIPS" / "▾ CHIPS". Slides up on open.
]]

local ChipUI = {}

local _open        = false
local _anim_t      = 0.0    -- 0=closed, 1=fully open
local ANIM_SPEED   = 1 / 0.35

local DRAWER_W     = 220
local DRAWER_H     = 160
local TAB_W        = 90
local TAB_H        = 24

-- Broadcast palette
local TIER_COLORS = {
    gold   = { 1.0,   0.835, 0.31  },  -- #ffd54f
    silver = { 0.69,  0.745, 0.773 },  -- #b0bec5
    copper = { 0.878, 0.569, 0.353 },  -- #e0915a
}

local POSITIVE_COLOR = { 0.412, 0.941, 0.682 }  -- #69f0ae green
local NEGATIVE_COLOR = { 1.0,   0.176, 0.42  }  -- #ff2d6b red
local BG_COLOR       = { 0.020, 0.008, 0.055 }  -- near-black purple

-- ============================================================
-- HELPERS
-- ============================================================

local function get_chip_stack()
    if TG and TG.ChipStack and TG.chip_stack then
        return TG.chip_stack
    end
    return nil
end

local function easing(t)
    -- Ease-out with slight overshoot
    local k = 1 - t
    return 1 - k * k * (1 + k * 0.5)
end

-- ============================================================
-- UPDATE
-- ============================================================

function ChipUI.update(dt)
    local target = _open and 1.0 or 0.0
    local delta  = target - _anim_t
    if delta > 0 then
        _anim_t = math.min(1.0, _anim_t + dt * ANIM_SPEED)
    elseif delta < 0 then
        _anim_t = math.max(0.0, _anim_t - dt * ANIM_SPEED)
    end
end

-- ============================================================
-- DRAW
-- ============================================================

local function draw_tier_bar(x, y, w, value, max_val, tier_name)
    if not TG or not TG.Phosphor then return end
    local tc = TIER_COLORS[tier_name] or TIER_COLORS.silver
    local bar_h = 5
    local fill  = max_val > 0 and math.min(1.0, value / max_val) or 0

    -- Track
    love.graphics.setColor(1, 1, 1, 0.06)
    love.graphics.rectangle("fill", x, y, w, bar_h, 2, 2)

    -- Fill with bloom
    local fill_w = math.max(0, w * fill)
    love.graphics.setBlendMode("add")
    love.graphics.setColor(tc[1], tc[2], tc[3], 0.3)
    love.graphics.rectangle("fill", x, y - 1, fill_w, bar_h + 2, 2, 2)
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(tc[1], tc[2], tc[3], 0.9)
    love.graphics.rectangle("fill", x, y, fill_w, bar_h, 2, 2)

    -- Label
    local tier_str = tier_name:upper()
    local val_str  = tostring(value)
    TG.Phosphor.draw(tier_str, x, y - 12, tc, 0.0, 7, 0.6)
    TG.Phosphor.draw(val_str,  x + w - TG.Phosphor.width(val_str, 7) - 2,
                     y - 12, tc, 0.0, 7, 0.9)
end

function ChipUI.draw()
    if _anim_t < 0.01 and not _open then
        -- Just draw the tab
    end

    local sw, sh = love.graphics.getDimensions()
    local tab_x  = sw - TAB_W - 10
    local tab_y  = sh - TAB_H - 10

    -- ── TAB ──────────────────────────────────────────────────
    if TG and TG.Phosphor then
        local label = _open and "\xe2\x96\xbe CHIPS" or "\xe2\x96\xb4 CHIPS"  -- ▾ / ▴ UTF-8
        -- Use ASCII arrows as fallback
        label = _open and "v CHIPS" or "^ CHIPS"

        -- Tab background
        love.graphics.setColor(BG_COLOR[1], BG_COLOR[2], BG_COLOR[3], 0.85)
        love.graphics.rectangle("fill", tab_x, tab_y, TAB_W, TAB_H, 3, 3)
        love.graphics.setColor(1, 1, 1, 0.06)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", tab_x + 0.5, tab_y + 0.5, TAB_W - 1, TAB_H - 1, 3, 3)

        -- Tab text
        local gold = TIER_COLORS.gold
        local lw   = TG.Phosphor.width(label, 10)
        TG.Phosphor.draw(label, tab_x + math.floor((TAB_W - lw) / 2), tab_y + 6, gold, 0.4, 10)
    end

    -- ── DRAWER ────────────────────────────────────────────────
    if _anim_t < 0.01 then return end

    local ease  = easing(_anim_t)
    local drawer_x = sw - DRAWER_W - 10
    local drawer_y = tab_y - DRAWER_H * ease

    -- Background
    love.graphics.setColor(BG_COLOR[1], BG_COLOR[2], BG_COLOR[3], 0.92 * ease)
    love.graphics.rectangle("fill", drawer_x, drawer_y, DRAWER_W, DRAWER_H, 4, 4)
    love.graphics.setColor(1, 1, 1, 0.07 * ease)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", drawer_x + 0.5, drawer_y + 0.5, DRAWER_W - 1, DRAWER_H - 1, 4, 4)

    if not (TG and TG.Phosphor) then return end

    -- Inner content
    local cx  = drawer_x + 14
    local cy  = drawer_y + 14
    local bar_w = DRAWER_W - 28
    local gold  = TIER_COLORS.gold

    TG.Phosphor.draw("CHIP STACK", cx, cy, gold, 0.4, 10, ease)
    cy = cy + 16

    -- Divider line
    love.graphics.setColor(1, 1, 1, 0.08 * ease)
    love.graphics.line(cx, cy, drawer_x + DRAWER_W - 14, cy)
    cy = cy + 8

    -- Chip stack data
    local cs = get_chip_stack()
    if cs then
        -- Gold tier
        local gold_val = cs.gold or 0
        local gold_max = cs.gold_max or 10
        draw_tier_bar(cx, cy + 14, bar_w, gold_val, gold_max, "gold")
        love.graphics.setColor(1, 1, 1, ease * 0.5)  -- just alpha guard
        cy = cy + 30

        -- Silver tier
        local silver_val = cs.silver or 0
        local silver_max = cs.silver_max or 20
        draw_tier_bar(cx, cy + 14, bar_w, silver_val, silver_max, "silver")
        cy = cy + 30

        -- Copper tier
        local copper_val = cs.copper or 0
        local copper_max = cs.copper_max or 40
        draw_tier_bar(cx, cy + 14, bar_w, copper_val, copper_max, "copper")
        cy = cy + 30

        -- Net / delta stat
        local net = (cs.net_gain or 0)
        local nc  = net >= 0 and POSITIVE_COLOR or NEGATIVE_COLOR
        local ns  = (net >= 0 and "+" or "") .. tostring(net)
        TG.Phosphor.draw("NET", cx, cy, { 1, 1, 1 }, 0.0, 7, 0.4 * ease)
        TG.Phosphor.draw(ns, cx + 30, cy, nc, 0.0, 7, ease)
    else
        TG.Phosphor.draw("No data", cx, cy + 10, { 1, 1, 1 }, 0.0, 8, 0.4 * ease)
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

-- ============================================================
-- TOGGLE (called from love.mousepressed or love.keypressed)
-- ============================================================

function ChipUI.toggle()
    _open = not _open
end

function ChipUI.handle_click(mx, my)
    local sw, sh = love.graphics.getDimensions()
    local tab_x  = sw - TAB_W - 10
    local tab_y  = sh - TAB_H - 10

    if mx >= tab_x and mx <= tab_x + TAB_W
    and my >= tab_y and my <= tab_y + TAB_H then
        ChipUI.toggle()
        return true
    end
    return false
end

function ChipUI.is_open()
    return _open
end

return ChipUI
