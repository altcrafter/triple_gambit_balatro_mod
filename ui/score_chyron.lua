--[[
    TRIPLE GAMBIT - ui/score_chyron.lua
    NEW. Broadcast lower-third score readout for the active board.
    Dark slab with colored left accent bar, score/target, gambit indicator.
]]

local Chyron = {}

local _time = 0

local BOARD_UI_COLORS = {
    A = { 1.0,   0.176, 0.42  },
    B = { 0.0,   0.898, 1.0   },
    C = { 1.0,   0.667, 0.133 },
    D = { 0.706, 0.302, 1.0   },
}

local CLEARED_COLOR = { 0.412, 0.941, 0.682 }

local HAND_SHORTCODES = {
    ["Pair"]            = "PR",
    ["Two Pair"]        = "2P",
    ["Three of a Kind"] = "3K",
    ["Straight"]        = "ST",
    ["Flush"]           = "FL",
    ["Full House"]      = "FH",
    ["Four of a Kind"]  = "4K",
    ["High Card"]       = "HC",
}

local SLAB_W    = 300
local SLAB_H    = 44
local ACCENT_W  = 3
local WIRE_H    = 2

-- ============================================================
-- HELPERS
-- ============================================================

local function active_id()
    return (TG and TG.active_board_id) or "A"
end

local function active_board()
    if TG and TG.active_board_id and TG.boards then
        return TG.boards[TG.active_board_id]
    end
    return nil
end

local function get_gambit_lock(id)
    if not (TG and TG.active_gambits) then return nil end
    for _, g in ipairs(TG.active_gambits) do
        if g.board == id then return g end
    end
    return nil
end

local function format_number(n)
    -- Add commas for readability
    local s = tostring(math.floor(n))
    local result = ""
    local len = #s
    for i = 1, len do
        if i > 1 and (len - i + 1) % 3 == 0 then
            result = result .. ","
        end
        result = result .. s:sub(i, i)
    end
    return result
end

local function urgency_pulse(t, pct)
    if pct < 0.7 then return 0 end
    return math.max(0.1, 0.5 + math.sin(t * 4) * 0.4)
end

-- ============================================================
-- UPDATE
-- ============================================================

function Chyron.update(dt)
    _time = _time + dt
end

-- ============================================================
-- DRAW
-- ============================================================

function Chyron.draw()
    if not TG or not TG.initialized then return end
    if not TG.Phosphor then return end

    local board = active_board()
    if not board then return end

    local id        = active_id()
    local bc        = BOARD_UI_COLORS[id] or { 1, 1, 1 }
    local cleared   = board.is_cleared or false
    local score     = board.current_score or 0
    local target    = board.target or 1
    local pct       = math.min(1.0, score / target)
    local pulse     = urgency_pulse(_time, pct)

    local sw, sh = love.graphics.getDimensions()

    -- Position: bottom of play area, roughly
    local slab_x = 12
    local slab_y = sh - 160

    -- ── Background slab (gradient left→transparent) ──────────
    -- Draw as stacked rectangles fading right
    local steps = 12
    for i = 1, steps do
        local frac = 1 - (i / steps)
        love.graphics.setColor(0.020, 0.008, 0.055, 0.85 * frac)
        love.graphics.rectangle("fill",
            slab_x + (i - 1) * (SLAB_W / steps), slab_y,
            SLAB_W / steps + 1, SLAB_H)
    end

    -- ── Left accent bar ──────────────────────────────────────
    local accent_c = cleared and CLEARED_COLOR or bc
    -- Bloom
    love.graphics.setBlendMode("add")
    love.graphics.setColor(accent_c[1], accent_c[2], accent_c[3], 0.33 + pulse * 0.2)
    love.graphics.rectangle("fill", slab_x, slab_y, 8, SLAB_H)
    love.graphics.setBlendMode("alpha")
    -- Solid bar
    love.graphics.setColor(accent_c[1], accent_c[2], accent_c[3], 1.0)
    love.graphics.rectangle("fill", slab_x, slab_y, ACCENT_W, SLAB_H)

    local content_x = slab_x + ACCENT_W + 6

    if cleared then
        -- ── CLEARED STATE ────────────────────────────────────
        TG.Phosphor.draw("CLEARED", content_x, slab_y + 12, CLEARED_COLOR, 2.0, 20)
    else
        -- ── NORMAL STATE ─────────────────────────────────────
        local score_str  = format_number(score)
        local div_str    = "/"
        local target_str = format_number(target)
        local deficit    = math.max(0, target - score)
        local def_str    = format_number(deficit) .. " rem"

        -- Score number (big, glow scales with urgency)
        local score_glow = 0.7 + pulse * 0.6
        TG.Phosphor.draw(score_str, content_x, slab_y + 4, bc, score_glow, 18)

        -- Divider
        local div_x = content_x + TG.Phosphor.width(score_str, 18) + 4
        TG.Phosphor.draw(div_str, div_x, slab_y + 8, { 1, 1, 1 }, 0.0, 8, 0.12)

        -- Target
        local tgt_x = div_x + TG.Phosphor.width(div_str, 8) + 4
        TG.Phosphor.draw(target_str, tgt_x, slab_y + 8, { 1, 1, 1 }, 0.0, 11, 0.25)

        -- Deficit (right-aligned)
        local def_w = TG.Phosphor.width(def_str, 7)
        local def_x = slab_x + SLAB_W - def_w - 10
        TG.Phosphor.draw(def_str, def_x, slab_y + 10, { 1, 1, 1 }, 0.0, 7, 0.12)

        -- Gambit indicator
        local glock = get_gambit_lock(id)
        if glock then
            local sc  = HAND_SHORTCODES[glock.hand_type] or "?"
            local lvl = "+" .. tostring(glock.level_boost)
            local badge_str = sc .. lvl .. " LOCK"
            love.graphics.setColor(bc[1], bc[2], bc[3], 0.35)
            love.graphics.circle("fill", content_x + 3, slab_y + SLAB_H - 10, 2)
            TG.Phosphor.draw(badge_str, content_x + 8, slab_y + SLAB_H - 15,
                             bc, 0.0, 7, 0.70)
        end
    end

    -- ── Progress wire ────────────────────────────────────────
    local wire_y  = slab_y + SLAB_H - WIRE_H
    local wire_c  = cleared and CLEARED_COLOR or bc
    local wire_w  = math.max(0, (SLAB_W - ACCENT_W) * pct)

    love.graphics.setColor(wire_c[1], wire_c[2], wire_c[3], 0.15)
    love.graphics.rectangle("fill", slab_x + ACCENT_W, wire_y, SLAB_W - ACCENT_W, WIRE_H)

    love.graphics.setBlendMode("add")
    love.graphics.setColor(wire_c[1], wire_c[2], wire_c[3], 0.8 + pulse * 0.2)
    love.graphics.rectangle("fill", slab_x + ACCENT_W, wire_y, wire_w, WIRE_H)
    love.graphics.setBlendMode("alpha")

    love.graphics.setColor(1, 1, 1, 1)
end

return Chyron
