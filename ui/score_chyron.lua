--[[
    TRIPLE GAMBIT - ui/score_chyron.lua
    Broadcast lower-third score readout. 3 elements only:
      1. Left accent bar (3px, board color, urgency bloom 8→16px at 4Hz)
      2. Score number (serif 18px, board color, +2° lean, glow 0.6 + urgency×0.4)
      3. Target (mono 11px, rgba(255,255,255,0.20), "/ N" directly below score)
    Right 40% fades to transparent. No deficit, no progress wire, no gambit indicator.
    Cleared state: serif "CLEARED" white -1.5° lean glow 1.8.
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

local SLAB_H   = 52
local ACCENT_W = 3

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

local function format_number(n)
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

local function urgency_factor(pct)
    -- 0 when pct < 0.7, rises linearly to 1.0 at pct = 1.0
    if pct < 0.7 then return 0 end
    return (pct - 0.7) / 0.3
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

    -- Self-update time if main.lua isn't calling Chyron.update(dt)
    _time = love.timer and love.timer.getTime() or _time

    local board = active_board()
    if not board then return end

    local id      = active_id()
    local bc      = BOARD_UI_COLORS[id] or { 1, 1, 1 }
    local cleared = board.is_cleared or false
    local score   = board.current_score or 0
    local target  = board.target or 1
    local pct     = math.min(1.0, score / target)
    local urgency = urgency_factor(pct)
    -- 4Hz pulse: 0→1 at urgency=0 it stays 0; at urgency=1 it pulses 0–1
    local pulse   = urgency * (0.5 + math.sin(_time * 4 * 2 * math.pi) * 0.5)

    local sw, sh = love.graphics.getDimensions()
    local slab_x = 0
    local slab_y = sh - 160
    local slab_w = math.floor(sw * 0.6)

    -- ── Background slab: solid left 60%, fades right 40% ──────
    local solid_w = math.floor(slab_w * 0.60)
    local fade_w  = slab_w - solid_w
    local steps   = 10

    love.graphics.setColor(0.020, 0.008, 0.055, 0.85)
    love.graphics.rectangle("fill", slab_x, slab_y, solid_w, SLAB_H)

    for i = 1, steps do
        local frac = 1 - (i / steps)
        love.graphics.setColor(0.020, 0.008, 0.055, 0.85 * frac)
        love.graphics.rectangle("fill",
            slab_x + solid_w + (i - 1) * (fade_w / steps), slab_y,
            fade_w / steps + 1, SLAB_H)
    end

    -- ── Left accent bar ───────────────────────────────────────
    local accent_c = cleared and CLEARED_COLOR or bc
    local bloom_w  = 8 + pulse * 8   -- 8→16px with urgency

    love.graphics.setBlendMode("add")
    love.graphics.setColor(accent_c[1], accent_c[2], accent_c[3], 0.30 + pulse * 0.20)
    love.graphics.rectangle("fill", slab_x, slab_y, bloom_w, SLAB_H)
    love.graphics.setBlendMode("alpha")

    -- Solid 3px bar
    love.graphics.setColor(accent_c[1], accent_c[2], accent_c[3], 1.0)
    love.graphics.rectangle("fill", slab_x, slab_y, ACCENT_W, SLAB_H)

    local content_x = ACCENT_W + 7

    if cleared then
        -- ── CLEARED STATE ─────────────────────────────────────
        local label_y = slab_y + math.floor((SLAB_H - TG.Phosphor.height("serif", 20)) * 0.5)
        TG.Phosphor.draw("CLEARED", content_x, label_y,
                         { 1, 1, 1 }, 1.8, "serif", 20, 1.0, math.rad(-1.5))
    else
        -- ── NORMAL STATE ─────────────────────────────────────
        local score_str  = format_number(score)
        local target_str = "/ " .. format_number(target)

        -- Score: serif 18px, board color, +2° lean
        local score_glow = 0.6 + urgency * 0.4
        local score_y    = slab_y + 6
        TG.Phosphor.draw(score_str, content_x, score_y,
                         bc, score_glow, "serif", 18, 1.0, math.rad(2))

        -- Target: mono 11px, dim white, directly below score
        local target_y = score_y + TG.Phosphor.height("serif", 18) + 2
        TG.Phosphor.draw(target_str, content_x, target_y,
                         { 1, 1, 1 }, 0.0, "mono", 11, 0.20)
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("alpha")
end

return Chyron
