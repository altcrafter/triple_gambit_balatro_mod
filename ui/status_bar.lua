--[[
    TRIPLE GAMBIT - ui/status_bar.lua
    36px compact beacon strip across the top. All 4 boards in a row.
    REWRITE (was 3-board; now 4-board, broadcast palette, phosphor text).
]]

local StatusBar = {}

local BAR_HEIGHT = 36

-- Vivid broadcast UI colors
local BOARD_UI_COLORS = {
    A = { 1.0,   0.176, 0.42  },
    B = { 0.0,   0.898, 1.0   },
    C = { 1.0,   0.667, 0.133 },
    D = { 0.706, 0.302, 1.0   },
}

local CLEARED_COLOR  = { 0.412, 0.941, 0.682 }
local DEAD_WHITE     = { 1, 1, 1 }

-- Hand type shortcodes for gambit badges
local HAND_SHORTCODES = {
    ["Pair"]           = "PR",
    ["Two Pair"]       = "2P",
    ["Three of a Kind"]= "3K",
    ["Straight"]       = "ST",
    ["Flush"]          = "FL",
    ["Full House"]     = "FH",
    ["Four of a Kind"] = "4K",
    ["High Card"]      = "HC",
}

-- Per-cell click regions (updated each draw)
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
        if g.board == id then
            return g
        end
    end
    return nil
end

local function board_color(id)
    return BOARD_UI_COLORS[id] or { 1, 1, 1 }
end

-- Draw a small additive bloom circle behind a main circle
local function draw_bloom_circle(cx, cy, r, color, alpha)
    love.graphics.setBlendMode("add")
    love.graphics.setColor(color[1], color[2], color[3], alpha)
    love.graphics.circle("fill", cx, cy, r * 2.2)
    love.graphics.setBlendMode("alpha")
end

-- ============================================================
-- DRAW
-- ============================================================

function StatusBar.draw()
    if not TG or not TG.initialized then return end
    if not TG.Phosphor then return end

    local w = love.graphics.getWidth()
    local num_boards = #board_ids()
    local cell_w = math.floor(w / num_boards)

    -- Background
    love.graphics.setColor(0.012, 0.004, 0.039, 0.85)
    love.graphics.rectangle("fill", 0, 0, w, BAR_HEIGHT)
    -- Bottom border
    love.graphics.setColor(1, 1, 1, 0.04)
    love.graphics.setLineWidth(1)
    love.graphics.line(0, BAR_HEIGHT, w, BAR_HEIGHT)

    _cell_rects = {}

    for i, id in ipairs(board_ids()) do
        local cx0 = (i - 1) * cell_w
        local board = get_board(id)
        local is_active  = (id == active_id())
        local is_cleared = board and board.is_cleared or false
        local bc = board_color(id)

        _cell_rects[i] = { x = cx0, y = 0, w = cell_w, h = BAR_HEIGHT, id = id }

        -- Cell separator
        if i > 1 then
            love.graphics.setColor(1, 1, 1, 0.04)
            love.graphics.line(cx0, 4, cx0, BAR_HEIGHT - 4)
        end

        -- ── Beacon dot ──────────────────────────────────────────
        local dot_x = cx0 + 10
        local dot_y = BAR_HEIGHT / 2
        local dot_r = 4

        if is_active then
            draw_bloom_circle(dot_x, dot_y, dot_r, bc, 0.25)
            love.graphics.setColor(bc[1], bc[2], bc[3], 1.0)
            love.graphics.circle("fill", dot_x, dot_y, dot_r)
        elseif is_cleared then
            love.graphics.setColor(CLEARED_COLOR[1], CLEARED_COLOR[2], CLEARED_COLOR[3], 0.9)
            love.graphics.circle("fill", dot_x, dot_y, dot_r)
        else
            love.graphics.setColor(bc[1], bc[2], bc[3], 0.35)
            love.graphics.circle("fill", dot_x, dot_y, dot_r)
        end

        -- ── Board letter ─────────────────────────────────────────
        local letter_x = cx0 + 20
        local letter_y = 4
        if is_active then
            TG.Phosphor.draw(id, letter_x, letter_y, bc, 0.7, 16)
        else
            TG.Phosphor.draw(id, letter_x, letter_y, DEAD_WHITE, 0.0, 16, 0.20)
        end

        -- ── Data stack ───────────────────────────────────────────
        if board then
            local score   = board.current_score or 0
            local target  = board.target or 1
            local money   = board.money or 0
            local pct     = math.min(1.0, score / target)

            -- Top line: money + progress %
            local money_str = "$" .. tostring(money)
            local pct_str   = is_cleared and "CLR" or (math.floor(pct * 100) .. "%")
            local money_x   = cx0 + 38
            local top_y     = 4

            TG.Phosphor.draw(money_str, money_x, top_y, { 1.0, 0.835, 0.31 }, 0.2, 8)
            local pct_x = money_x + TG.Phosphor.width(money_str, 8) + 4
            TG.Phosphor.draw(pct_str, pct_x, top_y, DEAD_WHITE, 0.0, 8, 0.35)

            -- Bottom line: progress bar
            local bar_y    = BAR_HEIGHT - 8
            local bar_x    = cx0 + 38
            local bar_w    = cell_w - 42
            local bar_h    = 3

            -- Background track
            love.graphics.setColor(1, 1, 1, 0.06)
            love.graphics.rectangle("fill", bar_x, bar_y, bar_w, bar_h, 1, 1)

            -- Fill
            local fill_w = math.max(0, bar_w * pct)
            local fill_c = is_cleared and CLEARED_COLOR or bc
            love.graphics.setColor(fill_c[1], fill_c[2], fill_c[3], 0.8)
            love.graphics.rectangle("fill", bar_x, bar_y, fill_w, bar_h, 1, 1)

            -- Bloom on bar
            if is_active then
                love.graphics.setBlendMode("add")
                love.graphics.setColor(fill_c[1], fill_c[2], fill_c[3], 0.3)
                love.graphics.rectangle("fill", bar_x, bar_y - 1, fill_w, bar_h + 2, 1, 1)
                love.graphics.setBlendMode("alpha")
            end

            -- ── Gambit badge ──────────────────────────────────────
            local G_STATE = (G and G.STATE and G.STATES) and G.STATE
            local in_shop = G_STATE and G.STATES.SHOP and (G_STATE == G.STATES.SHOP)
            if not in_shop then
                local glock = get_gambit_lock(id)
                if glock then
                    local sc = HAND_SHORTCODES[glock.hand_type] or "??"
                    local badge_x = cx0 + cell_w - 22
                    local badge_y = 6
                    local badge_w = 18
                    local badge_h = 12
                    -- Pill background
                    love.graphics.setColor(bc[1], bc[2], bc[3], 0.13)
                    love.graphics.rectangle("fill", badge_x, badge_y, badge_w, badge_h, 3, 3)
                    love.graphics.setColor(bc[1], bc[2], bc[3], 0.20)
                    love.graphics.setLineWidth(1)
                    love.graphics.rectangle("line", badge_x + 0.5, badge_y + 0.5, badge_w - 1, badge_h - 1, 3, 3)
                    -- Text
                    TG.Phosphor.draw(sc, badge_x + 2, badge_y + 2, bc, 0.3, 7)
                end
            end
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

-- ============================================================
-- CLICK HANDLING
-- Called from love.mousepressed hook in main.lua
-- Returns board_id if a cell was clicked, nil otherwise
-- ============================================================

function StatusBar.handle_click(mx, my)
    if my < 0 or my > BAR_HEIGHT then return nil end
    for _, rect in ipairs(_cell_rects) do
        if mx >= rect.x and mx < rect.x + rect.w then
            return rect.id
        end
    end
    return nil
end

function StatusBar.get_height()
    return BAR_HEIGHT
end

return StatusBar
