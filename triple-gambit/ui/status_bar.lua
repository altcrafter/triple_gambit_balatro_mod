--[[
    TRIPLE GAMBIT - ui/status_bar.lua
    Industrial Brutalism top bar.

    Three board sections. Thick left accent stripe, desaturated dark panels,
    ALL CAPS monospace labels. Gauge-style progress bar with notch marks.

    SHOP MODE: shows board tabs with money only. No stale blind data.
    PLAY MODE: full score/progress/gambit badges/amplifier.

    FIX: Gambit lock badges drawn ABOVE progress gauge, not behind it.
    FIX: Status bar resets display when entering shop.
]]

TG    = TG or {}
TG.UI = TG.UI or {}
TG.UI.StatusBar = {}

local SB = TG.UI.StatusBar

-- ============================================================
-- INDUSTRIAL PALETTE
-- ============================================================

local P = {
    panel      = { 0.045, 0.045, 0.058, 0.92 },
    active_bg  = 0.10,
    border     = { 1.0, 1.0, 1.0, 0.05 },
    text       = { 0.88, 0.88, 0.90, 0.92 },
    text_dim   = { 0.48, 0.48, 0.50, 0.60 },
    money      = { 0.95, 0.82, 0.18, 1.0 },
    cleared    = { 0.18, 0.92, 0.32, 1.0 },
    dead       = { 0.45, 0.45, 0.45, 0.45 },
    gauge_bg   = { 0.10, 0.10, 0.12, 0.85 },
    gauge_fill = 0.80,
    notch      = { 1.0, 1.0, 1.0, 0.07 },
    badge_bg   = { 0.06, 0.06, 0.04, 0.88 },
    badge_text = { 0.95, 0.85, 0.30, 0.92 },
}

SB.LAYOUT = {
    y            = 0,
    height       = 54,
    padding      = 4,
    gap          = 2,
    accent_w     = 5,
    gauge_h      = 5,
    gauge_bottom = 48,
    corner       = 0,  -- 0 = sharp corners = brutalist
}

-- ============================================================
-- DRAW
-- ============================================================

function SB.draw()
    if not TG.initialized then return end
    local L  = SB.LAYOUT
    local sw = love.graphics.getWidth()
    local n  = #TG.BOARD_IDS
    local sec_w = (sw - 2 * L.padding - (n - 1) * L.gap) / n

    local in_shop = SB.is_in_shop()
    local active_id = TG.active_board_id
    if in_shop and TG.Shop and TG.Shop.state then
        active_id = TG.Shop.state.active_board_id or active_id
    end

    for i, id in ipairs(TG.BOARD_IDS) do
        local board = TG:get_board(id)
        if board then
            local x = L.padding + (i - 1) * (sec_w + L.gap)
            SB.draw_section(board, x, L.y, sec_w, L.height, id == active_id, in_shop)
        end
    end
end

function SB.is_in_shop()
    if not (G and G.STATE and G.STATES) then return false end
    if G.STATE == G.STATES.SHOP then return true end
    -- Pack states count as shop
    for _, s in ipairs({"TAROT_PACK","SPECTRAL_PACK","STANDARD_PACK","BUFFOON_PACK","PLANET_PACK"}) do
        if G.STATES[s] and G.STATE == G.STATES[s] then return true end
    end
    return false
end

function SB.draw_section(board, x, y, w, h, is_active, in_shop)
    local L   = SB.LAYOUT
    local col = board.color

    -- ── Panel ──
    love.graphics.setColor(P.panel[1], P.panel[2], P.panel[3], P.panel[4])
    love.graphics.rectangle("fill", x, y, w, h, L.corner)

    -- ── Active tint ──
    if is_active then
        love.graphics.setColor(col.r, col.g, col.b, P.active_bg)
        love.graphics.rectangle("fill", x, y, w, h, L.corner)
    end

    -- ── LEFT ACCENT BAR (signature brutalist element) ──
    if board.is_dead then
        love.graphics.setColor(P.dead[1], P.dead[2], P.dead[3], P.dead[4])
    else
        love.graphics.setColor(col.r, col.g, col.b, is_active and 1.0 or 0.55)
    end
    love.graphics.rectangle("fill", x, y, L.accent_w, h)

    -- ── Active border (sharp, 1px) ──
    if is_active then
        love.graphics.setColor(col.r, col.g, col.b, 0.45)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", x, y, w, h, L.corner)
    end

    local tx = x + L.accent_w + 6
    local font = love.graphics.getFont()

    -- ── BOARD LABEL ──
    if board.is_dead then
        love.graphics.setColor(P.dead[1], P.dead[2], P.dead[3], P.dead[4])
        love.graphics.print(board.label .. " [DEAD]", tx, y + 3, 0, 0.7, 0.7)
    else
        love.graphics.setColor(col.r, col.g, col.b, 1.0)
        love.graphics.print(board.label, tx, y + 3, 0, 0.7, 0.7)
    end

    -- ── MONEY (top right, always visible) ──
    love.graphics.setColor(P.money[1], P.money[2], P.money[3], P.money[4])
    local mtxt = "$" .. board.money
    local mtw  = font:getWidth(mtxt) * 0.75
    love.graphics.print(mtxt, x + w - mtw - 5, y + 3, 0, 0.75, 0.75)

    if in_shop then
        -- ══ SHOP MODE: minimal, clean ══
        if board.is_cleared then
            love.graphics.setColor(P.cleared[1], P.cleared[2], P.cleared[3], 0.6)
            love.graphics.print("CLEARED", tx, y + 16, 0, 0.6, 0.6)
        end
        -- Joker count
        local jcount = board.jokers and #board.jokers or 0
        if jcount > 0 then
            love.graphics.setColor(P.text_dim[1], P.text_dim[2], P.text_dim[3], P.text_dim[4])
            local jtxt = jcount .. "/" .. TG.CONFIG.MAX_JOKERS_PER_BOARD .. " JOKERS"
            love.graphics.print(jtxt, tx, y + 28, 0, 0.55, 0.55)
        end
    else
        -- ══ PLAY MODE: full display ══

        -- Score / Target
        love.graphics.setColor(P.text[1], P.text[2], P.text[3], 0.85)
        local stxt = SB.fmt(board.current_score) .. " / " .. SB.fmt(board.target)
        love.graphics.print(stxt, tx, y + 16, 0, 0.6, 0.6)

        -- Hand size delta (if modified)
        if not board.is_dead and board.hand_size ~= TG.CONFIG.STARTING_HAND_SIZE then
            local d = board.hand_size - TG.CONFIG.STARTING_HAND_SIZE
            love.graphics.setColor(d < 0 and 1.0 or 0.3, d < 0 and 0.3 or 1.0, 0.3, 0.85)
            local htxt = "H:" .. board.hand_size
            local htw  = font:getWidth(htxt) * 0.55
            love.graphics.print(htxt, x + w - htw - 5, y + 16, 0, 0.55, 0.55)
        end

        -- Amplifier buff
        if TG.Amplifier then
            local mult = TG.Amplifier.get_multiplier(board.id)
            if mult > 1.0 then
                love.graphics.setColor(0.28, 0.95, 0.50, 0.85)
                local btxt = string.format("x%.2f", mult)
                local btw  = font:getWidth(btxt) * 0.55
                love.graphics.print(btxt, x + w - btw - 5, y + 28, 0, 0.55, 0.55)
            end
        end

        -- ── Gambit lock badges (ABOVE gauge, so they're never hidden) ──
        SB.draw_gambit_locks(board, tx, y + 28, w - L.accent_w - 12)

        -- ── PROGRESS GAUGE ──
        local gx = x + L.accent_w + 1
        local gy = y + L.gauge_bottom
        local gw = w - L.accent_w - 2

        -- Background
        love.graphics.setColor(P.gauge_bg[1], P.gauge_bg[2], P.gauge_bg[3], P.gauge_bg[4])
        love.graphics.rectangle("fill", gx, gy, gw, L.gauge_h)

        -- Notch marks
        love.graphics.setColor(P.notch[1], P.notch[2], P.notch[3], P.notch[4])
        for _, frac in ipairs({0.25, 0.50, 0.75}) do
            love.graphics.rectangle("fill", gx + gw * frac, gy, 1, L.gauge_h)
        end

        -- Fill
        local progress = math.min(1.0, board:get_progress())
        if progress > 0 then
            if board.is_cleared then
                love.graphics.setColor(P.cleared[1], P.cleared[2], P.cleared[3], 0.85)
            else
                love.graphics.setColor(col.r, col.g, col.b, P.gauge_fill)
            end
            love.graphics.rectangle("fill", gx, gy, gw * progress, L.gauge_h)
        end

        -- ── CLEARED OVERLAY ──
        if board.is_cleared then
            love.graphics.setColor(0, 0, 0, 0.22)
            love.graphics.rectangle("fill", x, y, w, h)
            love.graphics.setColor(P.cleared[1], P.cleared[2], P.cleared[3], 0.90)
            local clbl = "CLEARED"
            local ctw  = font:getWidth(clbl) * 0.85
            love.graphics.print(clbl, x + (w - ctw) * 0.5, y + (h - font:getHeight() * 0.85) * 0.5, 0, 0.85, 0.85)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- ============================================================
-- GAMBIT LOCK BADGES
-- ============================================================

function SB.draw_gambit_locks(board, x, y, max_w)
    if not TG.Gambit then return end
    local locks = TG.Gambit.get_locks(board.id)
    if #locks == 0 then return end

    local offset = 0
    local font   = love.graphics.getFont()
    for _, lock in ipairs(locks) do
        local label = SB.short_hand(lock.hand_type) .. "+" .. lock.level_boost
        local tw    = font:getWidth(label) * 0.5 + 6
        if offset + tw > max_w then break end

        -- Dark pill
        love.graphics.setColor(P.badge_bg[1], P.badge_bg[2], P.badge_bg[3], P.badge_bg[4])
        love.graphics.rectangle("fill", x + offset, y, tw, 11, 2)

        -- Left color tick
        local bcol = TG.CONFIG.COLORS[lock.board_id or board.id]
        if bcol then
            love.graphics.setColor(bcol.r, bcol.g, bcol.b, 0.8)
            love.graphics.rectangle("fill", x + offset, y, 2, 11, 1)
        end

        -- Label
        love.graphics.setColor(P.badge_text[1], P.badge_text[2], P.badge_text[3], P.badge_text[4])
        love.graphics.print(label, x + offset + 4, y + 1, 0, 0.5, 0.5)

        offset = offset + tw + 2
    end
end

-- ============================================================
-- CLICK (switch boards by clicking status sections)
-- ============================================================

function SB.handle_click(mx, my)
    if not TG.initialized then return false end
    local L   = SB.LAYOUT
    local sw  = love.graphics.getWidth()
    local n   = #TG.BOARD_IDS
    local sec_w = (sw - 2 * L.padding - (n - 1) * L.gap) / n

    if my < L.y or my > L.y + L.height then return false end

    for i, id in ipairs(TG.BOARD_IDS) do
        local bx = L.padding + (i - 1) * (sec_w + L.gap)
        if mx >= bx and mx <= bx + sec_w then
            if SB.is_in_shop() then
                local cur = TG.Shop and TG.Shop.state and TG.Shop.state.active_board_id
                if id ~= cur then TG.Hooks.on_shop_board_switch(id) end
            else
                if id ~= TG.active_board_id then TG.Switching.perform_switch(id) end
            end
            return true
        end
    end
    return false
end

-- ============================================================
-- UTILITY
-- ============================================================

function SB.fmt(n)
    if n >= 1000000 then return string.format("%.1fM", n / 1000000)
    elseif n >= 1000 then return string.format("%.1fK", n / 1000)
    else return tostring(math.floor(n)) end
end

function SB.short_hand(ht)
    local m = {
        ["High Card"]="HI", ["Pair"]="PR", ["Two Pair"]="2PR",
        ["Three of a Kind"]="3K", ["Straight"]="STR", ["Flush"]="FL",
        ["Full House"]="FH", ["Four of a Kind"]="4K",
        ["Straight Flush"]="SF", ["Five of a Kind"]="5K",
    }
    return m[ht] or ht
end

return SB
