--[[
    TRIPLE GAMBIT - ui/shop_ui.lua
    Shop overlay: board tabs, per-board money display, gambit previews.
    Shows which board will receive a purchase and its current money.
    Broadcast palette. Phosphor text.
]]

local ShopUI = {}

local BOARD_UI_COLORS = {
    A = { 1.0,   0.176, 0.42  },
    B = { 0.0,   0.898, 1.0   },
    C = { 1.0,   0.667, 0.133 },
    D = { 0.706, 0.302, 1.0   },
}

local CLEARED_COLOR = { 0.412, 0.941, 0.682 }
local GOLD_COLOR    = { 1.0, 0.835, 0.31 }
local BG_COLOR      = { 0.020, 0.008, 0.055 }

local TAB_H   = 28
local TAB_PAD = 6

-- Track which board tab is hovered/selected for purchase routing
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

-- ============================================================
-- DRAW
-- ============================================================

function ShopUI.draw()
    if not TG or not TG.initialized then return end
    if not TG.Phosphor then return end
    if not in_shop() then return end

    local sw, sh = love.graphics.getDimensions()
    local ids     = board_ids()
    local n       = #ids
    local total_w = sw * 0.85
    local tab_w   = math.floor((total_w - (n - 1) * TAB_PAD) / n)
    local start_x = math.floor((sw - total_w) / 2)
    local row_y   = 8  -- just below top edge (above status bar, or adjust)

    local sel = selected_board()

    for i, id in ipairs(ids) do
        local tab_x  = start_x + (i - 1) * (tab_w + TAB_PAD)
        local board  = get_board(id)
        local bc     = BOARD_UI_COLORS[id] or { 1, 1, 1 }
        local is_sel = (id == sel)
        local cleared = board and board.is_cleared or false
        local money   = board and board.money or 0

        -- Tab background
        if is_sel then
            love.graphics.setColor(bc[1], bc[2], bc[3], 0.12)
        else
            love.graphics.setColor(BG_COLOR[1], BG_COLOR[2], BG_COLOR[3], 0.75)
        end
        love.graphics.rectangle("fill", tab_x, row_y, tab_w, TAB_H, 3, 3)

        -- Border
        local border_c = is_sel and bc or { 1, 1, 1 }
        local border_a = is_sel and 0.5 or 0.06
        love.graphics.setColor(border_c[1], border_c[2], border_c[3], border_a)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", tab_x + 0.5, row_y + 0.5, tab_w - 1, TAB_H - 1, 3, 3)

        -- Bottom indicator bar for selected tab
        if is_sel then
            love.graphics.setBlendMode("add")
            love.graphics.setColor(bc[1], bc[2], bc[3], 0.5)
            love.graphics.rectangle("fill", tab_x + 3, row_y + TAB_H - 2, tab_w - 6, 2, 1, 1)
            love.graphics.setBlendMode("alpha")
        end

        -- Board letter
        local glow = is_sel and 0.7 or 0.0
        local alpha = is_sel and 1.0 or 0.35
        TG.Phosphor.draw(id, tab_x + 8, row_y + 6, bc, glow, 11, alpha)

        -- Money
        local money_str = "$" .. tostring(money)
        local mw = TG.Phosphor.width(money_str, 8)
        TG.Phosphor.draw(money_str,
            tab_x + tab_w - mw - 6, row_y + 9,
            GOLD_COLOR, 0.2, 8, alpha)

        -- Cleared indicator
        if cleared then
            local cc_x = tab_x + tab_w - 10
            local cc_y = row_y + 6
            love.graphics.setColor(CLEARED_COLOR[1], CLEARED_COLOR[2], CLEARED_COLOR[3], 0.9)
            love.graphics.circle("fill", cc_x, cc_y + 4, 3)
        end
    end

    -- "BUYING FOR: BOARD X" label below the tabs
    local sel_str = "BUYING FOR: BOARD " .. sel
    local lw = TG.Phosphor.width(sel_str, 8)
    local lx = math.floor(sw / 2 - lw / 2)
    local ly = row_y + TAB_H + 4
    local sel_bc = BOARD_UI_COLORS[sel] or { 1, 1, 1 }
    TG.Phosphor.draw(sel_str, lx, ly, sel_bc, 0.3, 8, 0.75)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

-- ============================================================
-- CLICK HANDLING
-- ============================================================

function ShopUI.handle_click(mx, my)
    if not in_shop() then return false end

    local sw, sh = love.graphics.getDimensions()
    local ids     = board_ids()
    local n       = #ids
    local total_w = sw * 0.85
    local tab_w   = math.floor((total_w - (n - 1) * TAB_PAD) / n)
    local start_x = math.floor((sw - total_w) / 2)
    local row_y   = 8

    if my < row_y or my > row_y + TAB_H then return false end

    for i, id in ipairs(ids) do
        local tab_x = start_x + (i - 1) * (tab_w + TAB_PAD)
        if mx >= tab_x and mx < tab_x + tab_w then
            _selected_board = id
            return true
        end
    end
    return false
end

-- ============================================================
-- PUBLIC ACCESSORS
-- ============================================================

-- Returns the board currently targeted for shop purchases
function ShopUI.get_target_board()
    return selected_board()
end

function ShopUI.set_target_board(id)
    _selected_board = id
end

-- Reset on entering shop (default to active board)
function ShopUI.on_shop_enter()
    _selected_board = active_id()
end

return ShopUI
