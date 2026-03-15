--[[
    TRIPLE GAMBIT - ui/status_bar.lua
    Board command strip across the top. 4 equal cells.

    Each cell:
      · Left accent bar  — board color, full opacity active, 25% inactive, mint cleared
      · Bloom behind accent bar when active (additive soft spread)
      · Active cell: faint board-color background tint
      · Board letter  — large serif, glow when active
      · Money         — gold mono, vertically centred right of letter
      · Gambit pennant — below money when a hand-type lock is active
      · "CLEARED"      — replaces money+pennant when board is cleared

    Dividers: 2px vertical lines, white 12%.
    All sizes scale from BASE_SH so the bar looks right at any resolution.
]]

local StatusBar = {}

local BASE_SH = 540   -- design baseline height; scale = sh / BASE_SH

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

local _cell_rects = {}

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

local function get_gambit_lock(id)
    if not (TG and TG.active_gambits) then return nil end
    for _, g in ipairs(TG.active_gambits) do
        if g.board == id then return g end
    end
    return nil
end

local function board_color(id)
    return BOARD_UI_COLORS[id] or { 1, 1, 1 }
end

-- ============================================================
-- GAMBIT PENNANT
-- ============================================================

local function draw_gambit_pennant(left_x, top_y, rect_w, bc, shortcode, h, point, text_size, pad)
    if not (TG and TG.Phosphor and shortcode) then return end
    local mid_y   = top_y + h * 0.5
    local x0, x1  = left_x, left_x + rect_w
    local xp      = x1 + point

    local verts = { x0, top_y, x1, top_y, xp, mid_y, x1, top_y + h, x0, top_y + h }

    local pivot_x = left_x + (rect_w + point) * 0.5
    love.graphics.push()
    love.graphics.translate(pivot_x, mid_y)
    love.graphics.rotate(math.rad(3))
    love.graphics.translate(-pivot_x, -mid_y)

    love.graphics.setColor(bc[1], bc[2], bc[3], 0.12)
    love.graphics.polygon("fill", verts)
    love.graphics.setColor(bc[1], bc[2], bc[3], 0.35)
    love.graphics.setLineWidth(1)
    love.graphics.polygon("line", verts)

    local ty = top_y + math.floor((h - TG.Phosphor.height("mono", text_size)) * 0.5)
    TG.Phosphor.draw(shortcode, left_x + pad, ty, bc, 0.3, "mono", text_size, 0.9)

    love.graphics.pop()
end

-- ============================================================
-- DRAW
-- ============================================================

function StatusBar.draw()
    if not TG or not TG.initialized then return end
    if not TG.Phosphor then return end

    local w, sh  = love.graphics.getDimensions()
    local scale  = sh / BASE_SH

    -- ── Sizes ──────────────────────────────────────────────────
    local bh      = math.floor(73  * scale)   -- bar height  ~120px at 889
    local accent  = math.floor(7   * scale)   -- accent bar  ~12px
    local l_size  = math.floor(34  * scale)   -- letter font ~56px
    local m_size  = math.floor(14  * scale)   -- money font  ~23px
    local c_size  = math.floor(12  * scale)   -- "CLEARED"   ~20px
    local pad     = math.floor(6   * scale)   -- gen padding ~10px
    local pen_h   = math.floor(17  * scale)   -- pennant h   ~28px
    local pen_pt  = math.floor(7   * scale)   -- pennant pt  ~12px
    local sep_w   = math.max(2, math.floor(2 * scale))  -- separator ~3px

    local ids    = board_ids()
    local n      = #ids
    local cell_w = math.floor(w / n)

    -- ── Background ─────────────────────────────────────────────
    love.graphics.setColor(0.010, 0.003, 0.032, 0.92)
    love.graphics.rectangle("fill", 0, 0, w, bh)

    -- Bottom border
    love.graphics.setColor(1, 1, 1, 0.08)
    love.graphics.setLineWidth(1)
    love.graphics.line(0, bh, w, bh)

    _cell_rects = {}

    for i, id in ipairs(ids) do
        local cx0    = (i - 1) * cell_w
        local board  = get_board(id)
        local active = (id == active_id())
        local cleared = board and board.is_cleared or false
        local bc     = board_color(id)
        local ac     = cleared and CLEARED_COLOR or bc

        _cell_rects[i] = { x = cx0, y = 0, w = cell_w, h = bh, id = id }

        -- ── Active background tint ────────────────────────────
        if active then
            love.graphics.setColor(bc[1], bc[2], bc[3], 0.08)
            love.graphics.rectangle("fill", cx0, 0, cell_w, bh)
        end

        -- ── Left accent bar ───────────────────────────────────
        local acc_a = active and 1.0 or (cleared and 0.85 or 0.28)
        love.graphics.setColor(ac[1], ac[2], ac[3], acc_a)
        love.graphics.rectangle("fill", cx0, 0, accent, bh)

        -- Soft bloom behind accent (active only)
        if active then
            love.graphics.setBlendMode("add")
            love.graphics.setColor(bc[1], bc[2], bc[3], 0.14)
            love.graphics.rectangle("fill", cx0, 0, accent * 6, bh)
            love.graphics.setBlendMode("alpha")
        end

        -- ── Cell separator ────────────────────────────────────
        if i < n then
            love.graphics.setColor(1, 1, 1, 0.12)
            love.graphics.setLineWidth(sep_w)
            local sx = cx0 + cell_w - sep_w * 0.5
            love.graphics.line(sx, 0, sx, bh)
            love.graphics.setLineWidth(1)
        end

        -- ── Board letter ──────────────────────────────────────
        local letter_x = cx0 + accent + pad * 2
        local lh       = TG.Phosphor.height("serif", l_size)
        local letter_y = math.floor((bh - lh) * 0.5)

        local lc, lg, la, ll
        if active then
            lc, lg, la, ll = bc, 0.65, 1.0, math.rad(2)
        elseif cleared then
            lc, lg, la, ll = CLEARED_COLOR, 0.15, 0.85, 0
        else
            lc, lg, la, ll = { 1, 1, 1 }, 0.0, 0.22, 0
        end
        TG.Phosphor.draw(id, letter_x, letter_y, lc, lg, "serif", l_size, la, ll)

        -- ── Right content: money or CLEARED ──────────────────
        if board then
            local right_x = letter_x + TG.Phosphor.width(id, "serif", l_size) + pad * 2

            if cleared then
                local cl_y = math.floor((bh - TG.Phosphor.height("mono", c_size)) * 0.5)
                TG.Phosphor.draw("CLEARED", right_x, cl_y,
                                 CLEARED_COLOR, 0.6, "mono", c_size, 0.95)
            else
                local money   = board.money or 0
                local money_s = "$" .. tostring(money)
                local money_y = math.floor((bh - TG.Phosphor.height("mono", m_size)) * 0.5)
                local ma      = active and 1.0 or 0.40
                local mg      = active and 0.35 or 0.0
                TG.Phosphor.draw(money_s, right_x, money_y,
                                 { 1.0, 0.835, 0.31 }, mg, "mono", m_size, ma)

                -- Gambit pennant (below money when lock is active)
                local G_STATE = (G and G.STATE and G.STATES) and G.STATE
                local in_shop = G_STATE and G.STATES.SHOP and (G_STATE == G.STATES.SHOP)
                local glock   = (not in_shop) and get_gambit_lock(id) or nil
                if glock then
                    local sc    = (HAND_SHORTCODES[glock.hand_type] or "??")
                               .. "+" .. tostring(glock.level_boost or 0)
                    local pen_y = money_y + TG.Phosphor.height("mono", m_size) + pad
                    if pen_y + pen_h <= bh - pad then
                        local pen_w = TG.Phosphor.width(sc, "mono", m_size) + pad * 2
                        draw_gambit_pennant(right_x, pen_y, pen_w, bc, sc,
                                            pen_h, pen_pt, m_size, pad)
                    end
                end
            end
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

-- ============================================================
-- CLICK HANDLING
-- ============================================================

function StatusBar.handle_click(mx, my)
    local sh = love.graphics.getHeight()
    local bh = math.floor(73 * sh / BASE_SH)
    if my < 0 or my > bh then return nil end
    for _, rect in ipairs(_cell_rects) do
        if mx >= rect.x and mx < rect.x + rect.w then
            return rect.id
        end
    end
    return nil
end

function StatusBar.get_height()
    local sh = love.graphics.getHeight()
    return math.floor(73 * sh / BASE_SH)
end

return StatusBar
