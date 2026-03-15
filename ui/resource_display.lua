--[[
    TRIPLE GAMBIT - ui/resource_display.lua
    Icon pips: hands + discards + cleared boards.
    Revision: all circles 5px diameter, fill-drain spend animation, 8px group gaps.

    Filled circle = available.  Hollow 1px stroke = spent/used.
    Spend animation: fill opacity 1→0, stroke opacity 0→0.08, over 120ms.
    (No shrinking — the glass empties, it doesn't shrink.)
]]

local RD = {}

local HANDS_COLOR   = { 1.0, 0.569, 0.0   }   -- #ff9100 orange
local DISC_COLOR    = { 0.251, 0.769, 1.0  }   -- #40c4ff blue
local CLEARED_COLOR = { 0.412, 0.941, 0.682 }  -- #69f0ae mint

-- PIP_R, PIP_STRIDE, GROUP_GAP computed in draw() from sh — see local declarations there
local ANIM_DUR   = 0.12  -- 120ms fill-drain animation

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

local function ensure_pip_state()
    local max_h = (TG and TG.CONFIG and TG.CONFIG.HANDS_PER_BLIND) or 4
    local max_d = (TG and TG.CONFIG and TG.CONFIG.DISCARDS_PER_BLIND) or 3
    for i = 1, max_h do
        if not _pip_state.hands[i] then
            _pip_state.hands[i] = { timer = nil }
        end
    end
    for i = 1, max_d do
        if not _pip_state.discards[i] then
            _pip_state.discards[i] = { timer = nil }
        end
    end
end

-- ============================================================
-- DRAW PIP (circle, fill-drain style)
-- ============================================================

local function draw_pip_circle(cx, cy, color, lit, timer, pip_r)
    local r, g, b = color[1], color[2], color[3]

    if timer then
        local t        = math.min(1.0, timer / ANIM_DUR)
        local fill_a   = (1 - t) * 0.9
        local stroke_a = t * 0.08

        if fill_a > 0.005 then
            love.graphics.setColor(r, g, b, fill_a)
            love.graphics.circle("fill", cx, cy, pip_r)
        end
        love.graphics.setColor(1, 1, 1, stroke_a)
        love.graphics.setLineWidth(1)
        love.graphics.circle("line", cx, cy, pip_r)

    elseif lit then
        love.graphics.setBlendMode("add")
        love.graphics.setColor(r, g, b, 0.25)
        love.graphics.circle("fill", cx, cy, pip_r * 2.0)
        love.graphics.setBlendMode("alpha")
        love.graphics.setColor(r, g, b, 0.9)
        love.graphics.circle("fill", cx, cy, pip_r)

    else
        love.graphics.setColor(1, 1, 1, 0.08)
        love.graphics.setLineWidth(1)
        love.graphics.circle("line", cx, cy, pip_r)
    end
end

-- ============================================================
-- PUBLIC: SPEND EVENTS
-- ============================================================

function RD.on_hand_spent(idx)
    ensure_pip_state()
    if _pip_state.hands[idx] then
        _pip_state.hands[idx].timer = 0
    end
end

function RD.on_discard_spent(idx)
    ensure_pip_state()
    if _pip_state.discards[idx] then
        _pip_state.discards[idx].timer = 0
    end
end

-- ============================================================
-- UPDATE
-- ============================================================

function RD.update(dt)
    for _, state in ipairs(_pip_state.hands) do
        if state.timer then
            state.timer = state.timer + dt
            if state.timer >= ANIM_DUR then state.timer = nil end
        end
    end
    for _, state in ipairs(_pip_state.discards) do
        if state.timer then
            state.timer = state.timer + dt
            if state.timer >= ANIM_DUR then state.timer = nil end
        end
    end
end

-- Alias called by main.lua update hook
RD.update_shake = RD.update

-- ============================================================
-- DRAW
-- ============================================================

function RD.draw()
    if not TG or not TG.initialized then return end

    -- Only show during hand play — not in blind select, shop, or menus
    if G and G.STATE and G.STATES then
        local s = G.STATE
        if s ~= G.STATES.SELECTING_HAND and s ~= G.STATES.DRAW_TO_HAND then
            return
        end
    end

    local board = active_board()
    if not board then return end

    local sw, sh = love.graphics.getDimensions()

    -- All sizes derived from sh so they scale with any resolution
    local pip_r      = math.max(5, math.floor(sh * 0.014))  -- min 5px; ~7px@540 ~12px@889
    local pip_stride = math.max(14, math.floor(sh * 0.036)) -- min 14px; ~19px@540 ~32px@889
    local group_gap  = math.max(10, math.floor(sh * 0.028)) -- min 10px; ~15px@540 ~25px@889

    local max_h   = (TG.CONFIG and TG.CONFIG.HANDS_PER_BLIND) or 4
    local max_d   = (TG.CONFIG and TG.CONFIG.DISCARDS_PER_BLIND) or 3
    local rem_h   = board.hands_remaining or max_h
    local rem_d   = board.discards_remaining or max_d
    local nb      = total_boards()

    ensure_pip_state()

    local group_w = function(n) return (n - 1) * pip_stride + pip_r * 2 end
    local total_w = group_w(max_h) + group_gap + group_w(max_d) + group_gap + group_w(nb)

    local row_x  = math.floor(sw / 2 - total_w / 2)
    local row_y  = math.floor(sh * 0.42)  -- above the card hand arc
    local mid_y  = row_y + pip_r

    local cx = row_x + pip_r  -- start at center of first pip

    -- ── HANDS GROUP ─────────────────────────────────────────────
    for i = 1, max_h do
        local lit   = (i <= rem_h)
        local state = _pip_state.hands[i]
        draw_pip_circle(cx, mid_y, HANDS_COLOR, lit, state and state.timer, pip_r)
        cx = cx + pip_stride
    end

    -- Group gap (no separator dot)
    cx = cx - pip_stride + pip_r * 2 + group_gap + pip_r

    -- ── DISCARDS GROUP ──────────────────────────────────────────
    for i = 1, max_d do
        local lit   = (i <= rem_d)
        local state = _pip_state.discards[i]
        draw_pip_circle(cx, mid_y, DISC_COLOR, lit, state and state.timer, pip_r)
        cx = cx + pip_stride
    end

    -- Group gap
    cx = cx - pip_stride + pip_r * 2 + group_gap + pip_r

    -- ── CLEARED GROUP ────────────────────────────────────────────
    local n_cleared = cleared_count()
    for i = 1, nb do
        local is_cleared = (i <= n_cleared)
        if is_cleared then
            love.graphics.setBlendMode("add")
            love.graphics.setColor(CLEARED_COLOR[1], CLEARED_COLOR[2], CLEARED_COLOR[3], 0.20)
            love.graphics.circle("fill", cx, mid_y, pip_r * 2)
            love.graphics.setBlendMode("alpha")
            love.graphics.setColor(CLEARED_COLOR[1], CLEARED_COLOR[2], CLEARED_COLOR[3], 1.0)
            love.graphics.circle("fill", cx, mid_y, pip_r)
        else
            love.graphics.setColor(1, 1, 1, 0.10)
            love.graphics.setLineWidth(1)
            love.graphics.circle("line", cx, mid_y, pip_r)
        end
        cx = cx + pip_stride
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("alpha")
    love.graphics.setLineWidth(1)
end

return RD
