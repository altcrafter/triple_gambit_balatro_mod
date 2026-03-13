--[[
    TRIPLE GAMBIT - ui/shop_ui.lua
    Industrial Brutalism shop overlay.

    Board tags on items, per-board buy buttons, reroll override.
    Money pools are displayed in the status bar (always visible),
    so this module focuses on item-level UI.

    Style: dark panels, accent bars, sharp corners, ALL CAPS.
]]

TG    = TG or {}
TG.UI = TG.UI or {}
TG.UI.ShopUI = {}

local SUI = TG.UI.ShopUI

SUI.LAYOUT = {
    tag_size     = 12,
    tag_margin   = 3,
    btn_w        = 65,
    btn_h        = 22,
    btn_gap      = 3,
}

-- ============================================================
-- BOARD TAG (small colored pip on shop items)
-- ============================================================

function SUI.draw_board_tag(x, y, board_id)
    if not (G and G.STATE and G.STATES and G.STATE == G.STATES.SHOP) then return end
    local L   = SUI.LAYOUT
    local col = TG.CONFIG.COLORS[board_id]
    if not col then return end

    local tx = x + L.tag_margin
    local ty = y + L.tag_margin
    local ts = L.tag_size

    -- Dark square bg
    love.graphics.setColor(0.03, 0.03, 0.04, 0.90)
    love.graphics.rectangle("fill", tx, ty, ts, ts)

    -- Color fill
    love.graphics.setColor(col.r, col.g, col.b, 0.85)
    love.graphics.rectangle("fill", tx + 1, ty + 1, ts - 2, ts - 2)

    -- Letter
    love.graphics.setColor(0, 0, 0, 0.9)
    local font = love.graphics.getFont()
    local lw   = font:getWidth(board_id) * 0.55
    love.graphics.print(board_id,
        tx + (ts - lw) * 0.5,
        ty + 1,
        0, 0.55, 0.55)

    love.graphics.setColor(1, 1, 1, 1)
end

-- ============================================================
-- BUY BUTTONS (shown for joker items, one per board)
-- ============================================================

local _hover_card = nil

function SUI.set_hover_card(card)
    _hover_card = card
end

function SUI.draw_buy_buttons(item_x, item_y, item_w, item_h, cost)
    if not (G and G.STATE and G.STATES and G.STATE == G.STATES.SHOP) then return end
    local L       = SUI.LAYOUT
    local n       = #TG.BOARD_IDS
    local total_w = n * L.btn_w + (n - 1) * L.btn_gap
    local sx      = item_x + (item_w - total_w) * 0.5
    local by      = item_y + item_h + 3
    local buttons = {}

    for i, id in ipairs(TG.BOARD_IDS) do
        local bx    = sx + (i - 1) * (L.btn_w + L.btn_gap)
        local board = TG:get_board(id)
        local ok    = board:can_afford(cost)
        local col   = TG.CONFIG.COLORS[id]

        -- Button panel
        if ok then
            love.graphics.setColor(col.r * 0.3, col.g * 0.3, col.b * 0.3, 0.90)
        else
            love.graphics.setColor(0.08, 0.08, 0.08, 0.60)
        end
        love.graphics.rectangle("fill", bx, by, L.btn_w, L.btn_h)

        -- Left accent
        if ok then
            love.graphics.setColor(col.r, col.g, col.b, 0.85)
        else
            love.graphics.setColor(0.25, 0.25, 0.25, 0.40)
        end
        love.graphics.rectangle("fill", bx, by, 2, L.btn_h)

        -- Border
        love.graphics.setColor(ok and col.r or 0.2, ok and col.g or 0.2, ok and col.b or 0.2, ok and 0.5 or 0.2)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", bx, by, L.btn_w, L.btn_h)

        -- Label
        love.graphics.setColor(ok and 1 or 0.4, ok and 1 or 0.4, ok and 1 or 0.4, ok and 0.92 or 0.45)
        local text = id .. " $" .. cost
        local font = love.graphics.getFont()
        local tw   = font:getWidth(text) * 0.7
        love.graphics.print(text,
            bx + (L.btn_w - tw) * 0.5,
            by + 3, 0, 0.7, 0.7)

        table.insert(buttons, {
            x = bx, y = by, w = L.btn_w, h = L.btn_h,
            board_id = id, enabled = ok, card = _hover_card,
        })
    end

    love.graphics.setColor(1, 1, 1, 1)
    return buttons
end

-- ============================================================
-- CLICK HANDLING
-- ============================================================

function SUI.handle_buy_button_click(mx, my, buttons)
    if not buttons then return false end
    for _, btn in ipairs(buttons) do
        if btn.enabled
        and mx >= btn.x and mx <= btn.x + btn.w
        and my >= btn.y and my <= btn.y + btn.h then
            TG.Shop.set_pending_buy_board(btn.board_id)
            if btn.card and G and G.FUNCS and G.FUNCS.buy_from_shop then
                G.FUNCS.buy_from_shop(btn.card)
            end
            return true
        end
    end
    return false
end

-- ============================================================
-- REROLL BUTTON
-- ============================================================

function SUI.draw_reroll_button(x, y, w, h)
    local aid   = TG.Shop.state.active_board_id
    local board = TG:get_board(aid)
    local ok    = board:can_afford(TG.CONFIG.REROLL_COST)
                  and not TG.Shop.is_reroll_blocked()

    -- Panel
    love.graphics.setColor(ok and 0.12 or 0.06, ok and 0.28 or 0.06, ok and 0.12 or 0.06, 0.90)
    love.graphics.rectangle("fill", x, y, w, h)

    -- Left accent
    love.graphics.setColor(ok and 0.2 or 0.15, ok and 0.65 or 0.15, ok and 0.2 or 0.15, ok and 0.9 or 0.4)
    love.graphics.rectangle("fill", x, y, 3, h)

    -- Border
    love.graphics.setColor(ok and 0.3 or 0.15, ok and 0.7 or 0.15, ok and 0.3 or 0.15, ok and 0.6 or 0.2)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x, y, w, h)

    -- Label
    love.graphics.setColor(ok and 1 or 0.4, ok and 1 or 0.4, ok and 1 or 0.4, ok and 0.95 or 0.4)
    love.graphics.print("REROLL $" .. TG.CONFIG.REROLL_COST, x + 6, y + 4, 0, 0.75, 0.75)

    love.graphics.setColor(1, 1, 1, 1)
    return ok
end

-- ============================================================
-- MONEY POOL CLICK (delegates to status bar now)
-- ============================================================

function SUI.handle_money_pool_click(mx, my)
    if TG.UI and TG.UI.StatusBar then
        return TG.UI.StatusBar.handle_click(mx, my)
    end
    return false
end

-- Backwards compat
function SUI.draw_money_pools()
    -- Now handled by status_bar.lua
end

return SUI
