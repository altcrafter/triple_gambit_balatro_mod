--[[
    TRIPLE GAMBIT - ui/resource_display.lua
    Icon pips: hands + discards + cleared boards.
    REWRITE: was gauge bars, now dots/squares with spend animation.
    Layout: [●][■][■][■][■] · [●][■][■][■] · [○][○][○]
]]

local RD = {}

local HANDS_COLOR   = { 1.0, 0.569, 0.0   }  -- #ff9100 orange
local DISC_COLOR    = { 0.251, 0.769, 1.0  }  -- #40c4ff blue
local CLEARED_COLOR = { 0.412, 0.941, 0.682 } -- #69f0ae mint
local DEAD_ALPHA    = 0.15
local PIP_SIZE      = 6   -- px, square pips
local DOT_R         = 2.5 -- beacon dot radius
local SEP_R         = 1   -- separator dot radius
local SPACING       = 9   -- px between pips
local SECTION_GAP   = 14  -- px between sections

-- Per-pip spend animations
local _pip_state = {
    hands    = {},
    discards = {},
}

-- ============================================================
-- HELPERS
-- ============================================================

local function active_board()
    if TG and TG.active_board_id and TG.boards then
        return TG.boards[TG.active_board_id]
    end
    return nil
end

local function cleared_count()
    if not (TG and TG.boards and TG.BOARD_IDS) then return 0 end
    local n = 0
    for _, id in ipairs(TG.BOARD_IDS) do
        local b = TG.boards[id]
        if b and b.is_cleared then n = n + 1 end
    end
    return n
end

local function total_boards()
    return (TG and TG.BOARD_IDS) and #TG.BOARD_IDS or 4
end

-- Initialize pip state tables for max capacity
local function ensure_pip_state()
    local max_h = (TG and TG.CONFIG and TG.CONFIG.HANDS_PER_BLIND) or 4
    local max_d = (TG and TG.CONFIG and TG.CONFIG.DISCARDS_PER_BLIND) or 3
    for i = 1, max_h do
        if not _pip_state.hands[i] then
            _pip_state.hands[i] = { timer = nil, was_lit = true }
        end
    end
    for i = 1, max_d do
        if not _pip_state.discards[i] then
            _pip_state.discards[i] = { timer = nil, was_lit = true }
        end
    end
end

-- ============================================================
-- DRAW PIP (square)
-- ============================================================

local function draw_pip_sq(x, y, color, lit, pip_s)
    local sz    = pip_s or PIP_SIZE
    local r, g, b = color[1], color[2], color[3]

    if lit then
        -- Box shadow / glow
        love.graphics.setBlendMode("add")
        love.graphics.setColor(r, g, b, 0.3)
        love.graphics.rectangle("fill", x - 2, y - 2, sz + 4, sz + 4, 2, 2)
        love.graphics.setBlendMode("alpha")
        -- Main pip
        love.graphics.setColor(r, g, b, 0.9)
        love.graphics.rectangle("fill", x, y, sz, sz, 1, 1)
    else
        love.graphics.setColor(1, 1, 1, DEAD_ALPHA)
        love.graphics.rectangle("fill", x, y, sz * 0.6, sz * 0.6, 1, 1)
    end
end

-- ============================================================
-- DRAW DOT (beacon)
-- ============================================================

local function draw_dot(cx, cy, color, radius)
    local r, g, b = color[1], color[2], color[3]
    -- Glow
    love.graphics.setBlendMode("add")
    love.graphics.setColor(r, g, b, 0.3)
    love.graphics.circle("fill", cx, cy, radius * 2)
    love.graphics.setBlendMode("alpha")
    -- Main
    love.graphics.setColor(r, g, b, 1.0)
    love.graphics.circle("fill", cx, cy, radius)
end

-- ============================================================
-- DRAW SEPARATOR
-- ============================================================

local function draw_separator(cx, cy)
    love.graphics.setColor(1, 1, 1, 0.10)
    love.graphics.circle("fill", cx, cy, SEP_R)
end

-- ============================================================
-- UPDATE
-- ============================================================

-- Called by main.lua when a hand is spent (pip_index = 1-based)
function RD.on_hand_spent(idx)
    ensure_pip_state()
    if _pip_state.hands[idx] then
        _pip_state.hands[idx].timer    = 0
        _pip_state.hands[idx].was_lit  = true
    end
end

function RD.on_discard_spent(idx)
    ensure_pip_state()
    if _pip_state.discards[idx] then
        _pip_state.discards[idx].timer   = 0
        _pip_state.discards[idx].was_lit = true
    end
end

function RD.update(dt)
    local anim_dur = 0.15
    for _, state in ipairs(_pip_state.hands) do
        if state.timer then
            state.timer = state.timer + dt
            if state.timer >= anim_dur then state.timer = nil end
        end
    end
    for _, state in ipairs(_pip_state.discards) do
        if state.timer then
            state.timer = state.timer + dt
            if state.timer >= anim_dur then state.timer = nil end
        end
    end
end

-- Alias called by the existing main_phase0c.lua update hook
RD.update_shake = RD.update

-- ============================================================
-- DRAW
-- ============================================================

function RD.draw()
    if not TG or not TG.initialized then return end

    local board = active_board()
    if not board then return end

    local max_h = (TG.CONFIG and TG.CONFIG.HANDS_PER_BLIND) or 4
    local max_d = (TG.CONFIG and TG.CONFIG.DISCARDS_PER_BLIND) or 3
    local rem_h = board.hands_remaining or max_h
    local rem_d = board.discards_remaining or max_d

    ensure_pip_state()

    local sw, sh = love.graphics.getDimensions()

    -- Total row width calculation
    -- hands section: DOT + max_h PIPS
    -- discards section: DOT + max_d PIPS
    -- cleared section: total_boards CIRCLES
    local nb = total_boards()
    local total_w = (DOT_R * 2 + 2)
                  + (max_h * SPACING)
                  + SECTION_GAP
                  + (DOT_R * 2 + 2)
                  + (max_d * SPACING)
                  + SECTION_GAP
                  + (nb * SPACING)

    local row_x = math.floor(sw / 2 - total_w / 2)
    local row_y = sh - 72  -- above card hand area
    local mid_y = row_y + PIP_SIZE / 2

    local cx = row_x

    -- ── HANDS SECTION ──────────────────────────────────────────
    draw_dot(cx + DOT_R, mid_y, HANDS_COLOR, DOT_R)
    cx = cx + DOT_R * 2 + 4

    for i = 1, max_h do
        local lit   = (i <= rem_h)
        local state = _pip_state.hands[i]
        local scale = 1.0
        if state and state.timer then
            -- Quadratic ease-out with slight overshoot feel
            local t = state.timer / 0.15
            scale = 0.6 + 0.4 * math.max(0, 1 - t * (2 - t))
        elseif not lit then
            scale = 0.6
        end
        local sz = math.floor(PIP_SIZE * scale)
        local ox = math.floor((PIP_SIZE - sz) / 2)
        -- White flash on first frame of spend
        local flash = state and state.timer and state.timer < 0.033
        if flash then
            draw_pip_sq(cx + ox, row_y + ox, { 1, 1, 1 }, true, sz)
        else
            draw_pip_sq(cx + ox, row_y + ox, HANDS_COLOR, lit, sz)
        end
        cx = cx + SPACING
    end

    -- Separator
    draw_separator(cx + SEP_R, mid_y)
    cx = cx + SECTION_GAP

    -- ── DISCARDS SECTION ───────────────────────────────────────
    draw_dot(cx + DOT_R, mid_y, DISC_COLOR, DOT_R)
    cx = cx + DOT_R * 2 + 4

    for i = 1, max_d do
        local lit   = (i <= rem_d)
        local state = _pip_state.discards[i]
        local scale = 1.0
        if state and state.timer then
            local t = state.timer / 0.15
            scale = 0.6 + 0.4 * math.max(0, 1 - t * (2 - t))
        elseif not lit then
            scale = 0.6
        end
        local sz = math.floor(PIP_SIZE * scale)
        local ox = math.floor((PIP_SIZE - sz) / 2)
        local flash = state and state.timer and state.timer < 0.033
        if flash then
            draw_pip_sq(cx + ox, row_y + ox, { 1, 1, 1 }, true, sz)
        else
            draw_pip_sq(cx + ox, row_y + ox, DISC_COLOR, lit, sz)
        end
        cx = cx + SPACING
    end

    -- Separator
    draw_separator(cx + SEP_R, mid_y)
    cx = cx + SECTION_GAP

    -- ── CLEARED SECTION ────────────────────────────────────────
    local n_cleared = cleared_count()
    for i = 1, nb do
        local is_cleared = (i <= n_cleared)
        local ccx = cx + (PIP_SIZE / 2)
        local ccy = mid_y
        if is_cleared then
            love.graphics.setBlendMode("add")
            love.graphics.setColor(CLEARED_COLOR[1], CLEARED_COLOR[2], CLEARED_COLOR[3], 0.25)
            love.graphics.circle("fill", ccx, ccy, PIP_SIZE)
            love.graphics.setBlendMode("alpha")
            love.graphics.setColor(CLEARED_COLOR[1], CLEARED_COLOR[2], CLEARED_COLOR[3], 1.0)
            love.graphics.circle("fill", ccx, ccy, PIP_SIZE / 2)
        else
            love.graphics.setColor(1, 1, 1, 0.10)
            love.graphics.circle("fill", ccx, ccy, PIP_SIZE / 2)
        end
        cx = cx + SPACING
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("alpha")
end

return RD
