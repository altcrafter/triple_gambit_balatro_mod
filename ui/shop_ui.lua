--[[
    TRIPLE GAMBIT - ui/shop_ui.lua
    Shop board selector. Rendered only during G.STATES.SHOP.

    Sits immediately below the status bar. Same visual language:
      · Dark background, board-color left accent bar
      · Large board letter, gold money readout
      · Selected board: full board-color left bar + background tint + bright text
      · Unselected: dim accent (25%), dim text
      · Cleared boards: mint accent, "CLEARED" in place of money

    A single "PURCHASING FOR  BOARD X" callout bar sits below the tabs,
    using the selected board's color.
]]

local ShopUI = {}

local BASE_SH = 540   -- same scale baseline as status_bar

local BOARD_UI_COLORS = {
    A = { 1.0,   0.176, 0.42  },
    B = { 0.0,   0.898, 1.0   },
    C = { 1.0,   0.667, 0.133 },
    D = { 0.706, 0.302, 1.0   },
}

local CLEARED_COLOR = { 0.412, 0.941, 0.682 }
local GOLD_COLOR    = { 1.0, 0.835, 0.31 }
local BG_COLOR      = { 0.010, 0.003, 0.032 }

local _selected_board = nil

-- ============================================================
-- HELPERS
-- ============================================================

local function board_ids()
    return (TG and TG.BOARD_IDS) or { "A", "B", "C", "D" }
end

local function active_id()
    return (TG and TG.active_board_id) or "A"
end

local function get_board(id)
    return (TG and TG.boards and TG.boards[id]) or nil
end

local function in_shop()
    return G and G.STATE and G.STATES and G.STATES.SHOP and (G.STATE == G.STATES.SHOP)
end

local function selected_board()
    return _selected_board or active_id()
end

-- Derive sizes from sh (same formula as status_bar for visual consistency)
local function sizes(sh)
    local scale = sh / BASE_SH
    return {
        status_bh = math.floor(73 * scale),   -- must match status_bar's bh
        tab_h     = math.floor(46 * scale),   -- ~76px — slightly shorter than status bar
        accent    = math.floor(7  * scale),   -- ~12px accent bar
        l_size    = math.floor(22 * scale),   -- ~36px letter
        m_size    = math.floor(12 * scale),   -- ~20px money
        c_size    = math.floor(10 * scale),   -- ~16px CLEARED
        pad       = math.floor(6  * scale),   -- ~10px general padding
        callout_h = math.floor(20 * scale),   -- ~33px callout strip below tabs
        callout_sz= math.floor(11 * scale),   -- ~18px callout text
        sep_w     = math.max(2, math.floor(2 * scale)),
    }
end

-- ============================================================
-- DRAW
-- ============================================================

function ShopUI.draw()
    if not TG or not TG.initialized then return end
    if not TG.Phosphor then return end
    if not in_shop() then return end

    local sw, sh = love.graphics.getDimensions()
    local S      = sizes(sh)

    local row_y  = S.status_bh   -- flush under the status bar
    local ids    = board_ids()
    local n      = #ids
    local cell_w = math.floor(sw / n)
    local sel    = selected_board()

    -- ── Tab row background ──────────────────────────────────────
    love.graphics.setColor(BG_COLOR[1], BG_COLOR[2], BG_COLOR[3], 0.88)
    love.graphics.rectangle("fill", 0, row_y, sw, S.tab_h)

    -- Bottom border of tab row
    love.graphics.setColor(1, 1, 1, 0.06)
    love.graphics.setLineWidth(1)
    love.graphics.line(0, row_y + S.tab_h, sw, row_y + S.tab_h)

    for i, id in ipairs(ids) do
        local cx0    = (i - 1) * cell_w
        local board  = get_board(id)
        local is_sel = (id == sel)
        local cleared = board and board.is_cleared or false
        local bc     = BOARD_UI_COLORS[id] or { 1, 1, 1 }
        local ac     = cleared and CLEARED_COLOR or bc

        -- ── Selected background tint ────────────────────────────
        if is_sel then
            love.graphics.setColor(bc[1], bc[2], bc[3], 0.09)
            love.graphics.rectangle("fill", cx0, row_y, cell_w, S.tab_h)
        end

        -- ── Left accent bar ─────────────────────────────────────
        local acc_a = is_sel and 1.0 or (cleared and 0.75 or 0.22)
        love.graphics.setColor(ac[1], ac[2], ac[3], acc_a)
        love.graphics.rectangle("fill", cx0, row_y, S.accent, S.tab_h)

        if is_sel then
            love.graphics.setBlendMode("add")
            love.graphics.setColor(bc[1], bc[2], bc[3], 0.12)
            love.graphics.rectangle("fill", cx0, row_y, S.accent * 6, S.tab_h)
            love.graphics.setBlendMode("alpha")
        end

        -- ── Cell separator ──────────────────────────────────────
        if i < n then
            love.graphics.setColor(1, 1, 1, 0.10)
            love.graphics.setLineWidth(S.sep_w)
            local sx = cx0 + cell_w - S.sep_w * 0.5
            love.graphics.line(sx, row_y, sx, row_y + S.tab_h)
            love.graphics.setLineWidth(1)
        end

        -- ── Board letter ────────────────────────────────────────
        local letter_x = cx0 + S.accent + S.pad * 2
        local lh       = TG.Phosphor.height("serif", S.l_size)
        local letter_y = row_y + math.floor((S.tab_h - lh) * 0.5)

        local lc, lg, la
        if is_sel then
            lc, lg, la = bc, 0.55, 1.0
        elseif cleared then
            lc, lg, la = CLEARED_COLOR, 0.1, 0.80
        else
            lc, lg, la = { 1, 1, 1 }, 0.0, 0.22
        end
        TG.Phosphor.draw(id, letter_x, letter_y, lc, lg, "serif", S.l_size, la,
                         is_sel and math.rad(2) or 0)

        -- ── Money or CLEARED ────────────────────────────────────
        if board then
            local right_x = letter_x + TG.Phosphor.width(id, "serif", S.l_size) + S.pad * 2

            if cleared then
                local cy = row_y + math.floor((S.tab_h - TG.Phosphor.height("mono", S.c_size)) * 0.5)
                TG.Phosphor.draw("CLEARED", right_x, cy, CLEARED_COLOR, 0.4, "mono", S.c_size, 0.9)
            else
                local money   = board.money or 0
                local money_s = "$" .. tostring(money)
                local my = row_y + math.floor((S.tab_h - TG.Phosphor.height("mono", S.m_size)) * 0.5)
                TG.Phosphor.draw(money_s, right_x, my,
                                 GOLD_COLOR, is_sel and 0.3 or 0.0, "mono", S.m_size,
                                 is_sel and 1.0 or 0.38)
            end
        end
    end

    -- ── "PURCHASING FOR  BOARD X" callout ───────────────────────
    local callout_y  = row_y + S.tab_h
    local sel_bc     = BOARD_UI_COLORS[sel] or { 1, 1, 1 }
    local callout_s  = "PURCHASING FOR  BOARD " .. sel

    -- Callout background
    love.graphics.setColor(sel_bc[1], sel_bc[2], sel_bc[3], 0.06)
    love.graphics.rectangle("fill", 0, callout_y, sw, S.callout_h)
    love.graphics.setColor(sel_bc[1], sel_bc[2], sel_bc[3], 0.18)
    love.graphics.setLineWidth(1)
    love.graphics.line(0, callout_y + S.callout_h, sw, callout_y + S.callout_h)

    -- Callout text (centred)
    local cw  = TG.Phosphor.width(callout_s, "mono", S.callout_sz)
    local cx  = math.floor(sw / 2 - cw / 2)
    local cy  = callout_y + math.floor((S.callout_h - TG.Phosphor.height("mono", S.callout_sz)) * 0.5)
    TG.Phosphor.draw(callout_s, cx, cy, sel_bc, 0.35, "mono", S.callout_sz, 0.90)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

-- ============================================================
-- CLICK HANDLING
-- ============================================================

function ShopUI.handle_click(mx, my)
    if not in_shop() then return false end

    local sw, sh = love.graphics.getDimensions()
    local S      = sizes(sh)
    local row_y  = S.status_bh

    if my < row_y or my > row_y + S.tab_h then return false end

    local ids    = board_ids()
    local n      = #ids
    local cell_w = math.floor(sw / n)

    for i, id in ipairs(ids) do
        local tab_x = (i - 1) * cell_w
        if mx >= tab_x and mx < tab_x + cell_w then
            _selected_board = id
            return true
        end
    end
    return false
end

-- ============================================================
-- PUBLIC ACCESSORS
-- ============================================================

function ShopUI.get_target_board()
    return selected_board()
end

function ShopUI.set_target_board(id)
    _selected_board = id
end

function ShopUI.on_shop_enter()
    _selected_board = active_id()
end

return ShopUI
