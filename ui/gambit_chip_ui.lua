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

-- Sizes computed in draw() from sh. BASE_SH = 540 (same scale as other UI files)
local BASE_SH = 540

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

local function draw_tier_bar(x, y, w, value, max_val, tier_name, bar_h, label_sz, label_gap)
    if not TG or not TG.Phosphor then return end
    local tc   = TIER_COLORS[tier_name] or TIER_COLORS.silver
    local fill = max_val > 0 and math.min(1.0, value / max_val) or 0

    love.graphics.setColor(1, 1, 1, 0.06)
    love.graphics.rectangle("fill", x, y, w, bar_h, 2, 2)

    local fill_w = math.max(0, w * fill)
    love.graphics.setBlendMode("add")
    love.graphics.setColor(tc[1], tc[2], tc[3], 0.3)
    love.graphics.rectangle("fill", x, y - 1, fill_w, bar_h + 2, 2, 2)
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(tc[1], tc[2], tc[3], 0.9)
    love.graphics.rectangle("fill", x, y, fill_w, bar_h, 2, 2)

    local tier_str = tier_name:upper()
    local val_str  = tostring(value)
    local label_y  = y - label_gap
    TG.Phosphor.draw(tier_str, x, label_y, tc, 0.0, "mono", label_sz, 0.6)
    TG.Phosphor.draw(val_str,
        x + w - TG.Phosphor.width(val_str, "mono", label_sz) - 2,
        label_y, tc, 0.0, "mono", label_sz, 0.9)
end

function ChipUI.draw()
    local sw, sh  = love.graphics.getDimensions()
    local scale   = sh / BASE_SH
    local drawer_w = math.floor(220 * scale)  -- ~363px at 889
    local drawer_h = math.floor(160 * scale)  -- ~264px
    local tab_w    = math.floor(90  * scale)  -- ~149px
    local tab_h    = math.floor(24  * scale)  -- ~40px
    local margin   = math.floor(10  * scale)  -- ~16px
    local bar_h    = math.floor(5   * scale)  -- ~8px
    local inner_p  = math.floor(14  * scale)  -- ~23px
    local row_gap  = math.floor(30  * scale)  -- ~50px
    local head_sz  = math.floor(10  * scale)  -- ~16px
    local lbl_sz   = math.floor(7   * scale)  -- ~12px
    local lbl_gap  = math.floor(12  * scale)  -- ~20px

    local tab_x = sw - tab_w - margin
    local tab_y = sh - tab_h - margin

    -- ── TAB ──────────────────────────────────────────────────
    if TG and TG.Phosphor then
        local label = _open and "v CHIPS" or "^ CHIPS"

        love.graphics.setColor(BG_COLOR[1], BG_COLOR[2], BG_COLOR[3], 0.85)
        love.graphics.rectangle("fill", tab_x, tab_y, tab_w, tab_h, 3, 3)
        love.graphics.setColor(1, 1, 1, 0.06)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", tab_x + 0.5, tab_y + 0.5, tab_w - 1, tab_h - 1, 3, 3)

        local gold = TIER_COLORS.gold
        local lw   = TG.Phosphor.width(label, "mono", head_sz)
        local ty   = tab_y + math.floor((tab_h - TG.Phosphor.height("mono", head_sz)) * 0.5)
        TG.Phosphor.draw(label, tab_x + math.floor((tab_w - lw) / 2), ty,
                         gold, 0.4, "mono", head_sz)
    end

    -- ── DRAWER ────────────────────────────────────────────────
    if _anim_t < 0.01 then return end

    local ease     = easing(_anim_t)
    local drawer_x = sw - drawer_w - margin
    local drawer_y = tab_y - drawer_h * ease

    love.graphics.setColor(BG_COLOR[1], BG_COLOR[2], BG_COLOR[3], 0.92 * ease)
    love.graphics.rectangle("fill", drawer_x, drawer_y, drawer_w, drawer_h, 4, 4)
    love.graphics.setColor(1, 1, 1, 0.07 * ease)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", drawer_x + 0.5, drawer_y + 0.5,
                             drawer_w - 1, drawer_h - 1, 4, 4)

    if not (TG and TG.Phosphor) then return end

    local cx    = drawer_x + inner_p
    local cy    = drawer_y + inner_p
    local bar_w = drawer_w - inner_p * 2
    local gold  = TIER_COLORS.gold

    TG.Phosphor.draw("CHIP STACK", cx, cy, gold, 0.4, "mono", head_sz, ease)
    cy = cy + TG.Phosphor.height("mono", head_sz) + math.floor(4 * scale)

    love.graphics.setColor(1, 1, 1, 0.08 * ease)
    love.graphics.line(cx, cy, drawer_x + drawer_w - inner_p, cy)
    cy = cy + math.floor(8 * scale)

    local cs = get_chip_stack()
    if cs then
        draw_tier_bar(cx, cy + lbl_gap + bar_h, bar_w,
                      cs.gold   or 0, cs.gold_max   or 10, "gold",   bar_h, lbl_sz, lbl_gap)
        cy = cy + row_gap

        draw_tier_bar(cx, cy + lbl_gap + bar_h, bar_w,
                      cs.silver or 0, cs.silver_max or 20, "silver", bar_h, lbl_sz, lbl_gap)
        cy = cy + row_gap

        draw_tier_bar(cx, cy + lbl_gap + bar_h, bar_w,
                      cs.copper or 0, cs.copper_max or 40, "copper", bar_h, lbl_sz, lbl_gap)
        cy = cy + row_gap

        local net = cs.net_gain or 0
        local nc  = net >= 0 and POSITIVE_COLOR or NEGATIVE_COLOR
        local ns  = (net >= 0 and "+" or "") .. tostring(net)
        TG.Phosphor.draw("NET", cx, cy, { 1, 1, 1 }, 0.0, "mono", lbl_sz, 0.4 * ease)
        TG.Phosphor.draw(ns, cx + TG.Phosphor.width("NET ", "mono", lbl_sz), cy,
                         nc, 0.0, "mono", lbl_sz, ease)
    else
        TG.Phosphor.draw("No data", cx, cy + math.floor(10 * scale),
                         { 1, 1, 1 }, 0.0, "mono", head_sz, 0.4 * ease)
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
    local sw, sh  = love.graphics.getDimensions()
    local scale   = sh / BASE_SH
    local tab_w   = math.floor(90 * scale)
    local tab_h   = math.floor(24 * scale)
    local margin  = math.floor(10 * scale)
    local tab_x   = sw - tab_w - margin
    local tab_y   = sh - tab_h - margin

    if mx >= tab_x and mx <= tab_x + tab_w
    and my >= tab_y and my <= tab_y + tab_h then
        ChipUI.toggle()
        return true
    end
    return false
end

function ChipUI.is_open()
    return _open
end

return ChipUI
