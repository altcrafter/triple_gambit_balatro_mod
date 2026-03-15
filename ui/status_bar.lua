--[[
    TRIPLE GAMBIT - ui/status_bar.lua
    36px compact beacon strip across the top. All 4 boards in a row.
    Revision: beacon rings, serif letters, pennant gambit badges, no progress bar.

    Per cell (left-clustered, right is void):
      [ring 8px from left] [board letter 4px gap] [money or pennant 4px gap]
]]

local StatusBar = {}

local BAR_HEIGHT = 36

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
-- BEACON RING
-- Three states via one shape:
--   Active:   8px outer, 2px stroke, board color, phosphor bloom
--   Cleared:  8px outer, filled #69f0ae
--   Inactive: 8px outer, 1px stroke, board color 30% opacity
-- ============================================================

local function draw_beacon_ring(cx, cy, bc, is_active, is_cleared)
    local r = 4  -- outer radius

    if is_cleared then
        -- Filled solid mint
        love.graphics.setColor(CLEARED_COLOR[1], CLEARED_COLOR[2], CLEARED_COLOR[3], 1.0)
        love.graphics.circle("fill", cx, cy, r)
    elseif is_active then
        -- Bloom (additive, bleeds inward and outward)
        love.graphics.setBlendMode("add")
        love.graphics.setColor(bc[1], bc[2], bc[3], 0.30)
        love.graphics.circle("fill", cx, cy, r * 2.5)
        love.graphics.setBlendMode("alpha")
        -- Ring: 2px stroke, no fill
        love.graphics.setColor(bc[1], bc[2], bc[3], 1.0)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", cx, cy, r - 1)
        love.graphics.setLineWidth(1)
    else
        -- Dim ring: 1px stroke, board color 30%
        love.graphics.setColor(bc[1], bc[2], bc[3], 0.30)
        love.graphics.setLineWidth(1)
        love.graphics.circle("line", cx, cy, r - 0.5)
        love.graphics.setLineWidth(1)
    end
end

-- ============================================================
-- GAMBIT PENNANT
-- Rectangle with triangular point on the right edge.
-- Height: 14px.  Point extends 6px beyond right boundary.
-- 3° clockwise rotation applied to whole shape.
-- Fill: board color 10%.  Stroke: board color 25%, 1px.
-- Text: mono 7px, board color 80%.
-- ============================================================

local function draw_gambit_pennant(left_x, top_y, rect_w, bc, shortcode)
    local h     = 14
    local point = 6        -- px beyond rect right boundary
    local mid_y = top_y + h * 0.5

    local x0 = left_x
    local x1 = left_x + rect_w
    local xp  = x1 + point  -- point tip

    -- 5 vertices: top-left, top-right, point, bottom-right, bottom-left
    local verts = {
        x0, top_y,
        x1, top_y,
        xp, mid_y,
        x1, top_y + h,
        x0, top_y + h,
    }

    -- Pivot for 3° CW rotation: center of bounding box
    local pivot_x = left_x + (rect_w + point) * 0.5
    local pivot_y = mid_y

    love.graphics.push()
    love.graphics.translate(pivot_x, pivot_y)
    love.graphics.rotate(math.rad(3))
    love.graphics.translate(-pivot_x, -pivot_y)

    -- Fill
    love.graphics.setColor(bc[1], bc[2], bc[3], 0.10)
    love.graphics.polygon("fill", verts)
    -- Stroke
    love.graphics.setColor(bc[1], bc[2], bc[3], 0.25)
    love.graphics.setLineWidth(1)
    love.graphics.polygon("line", verts)

    -- Text (mono 7px, board color 80%)
    if TG and TG.Phosphor and shortcode then
        local text_x = left_x + 4
        local text_y = top_y + math.floor((h - TG.Phosphor.height("mono", 7)) * 0.5)
        TG.Phosphor.draw(shortcode, text_x, text_y, bc, 0.2, "mono", 7, 0.8)
    end

    love.graphics.pop()
end

-- ============================================================
-- DRAW
-- ============================================================

function StatusBar.draw()
    if not TG or not TG.initialized then return end
    if not TG.Phosphor then return end

    local w       = love.graphics.getWidth()
    local ids     = board_ids()
    local n       = #ids
    local cell_w  = math.floor(w / n)

    -- Background
    love.graphics.setColor(0.012, 0.004, 0.039, 0.85)
    love.graphics.rectangle("fill", 0, 0, w, BAR_HEIGHT)
    -- Bottom border
    love.graphics.setColor(1, 1, 1, 0.04)
    love.graphics.setLineWidth(1)
    love.graphics.line(0, BAR_HEIGHT, w, BAR_HEIGHT)

    _cell_rects = {}

    for i, id in ipairs(ids) do
        local cx0     = (i - 1) * cell_w
        local board   = get_board(id)
        local active  = (id == active_id())
        local cleared = board and board.is_cleared or false
        local bc      = board_color(id)

        _cell_rects[i] = { x = cx0, y = 0, w = cell_w, h = BAR_HEIGHT, id = id }

        -- Cell separator
        if i > 1 then
            love.graphics.setColor(1, 1, 1, 0.04)
            love.graphics.line(cx0, 4, cx0, BAR_HEIGHT - 4)
        end

        -- ── Beacon ring ──────────────────────────────────────────
        -- Beacon ring: 8px from cell left edge
        -- Ring outer diameter = 8px → radius = 4, center at cx0 + 8 + 4 = cx0 + 12
        local ring_cx = cx0 + 12
        local ring_cy = BAR_HEIGHT * 0.5
        draw_beacon_ring(ring_cx, ring_cy, bc, active, cleared)

        -- ── Board letter ─────────────────────────────────────────
        -- 4px from ring's right edge (ring right = cx0 + 12 + 4 = cx0 + 16)
        local letter_x = cx0 + 20
        local letter_y = math.floor(BAR_HEIGHT * 0.5 - TG.Phosphor.height("serif", 13) * 0.5)

        if active then
            -- Serif, 13px, glow 0.5, +2° lean
            TG.Phosphor.draw(id, letter_x, letter_y, bc, 0.5, "serif", 13, 1.0, math.rad(2))
        else
            -- Serif, 13px, glow 0.0, flat
            TG.Phosphor.draw(id, letter_x, letter_y, { 1, 1, 1 }, 0.0, "serif", 13, 0.20, 0)
        end

        -- ── Money or gambit pennant ───────────────────────────────
        if board then
            local letter_right = letter_x + TG.Phosphor.width(id, "serif", 13) + 4

            -- Check for gambit lock
            local G_STATE = (G and G.STATE and G.STATES) and G.STATE
            local in_shop = G_STATE and G.STATES.SHOP and (G_STATE == G.STATES.SHOP)
            local glock   = (not in_shop) and get_gambit_lock(id) or nil

            if glock then
                -- Pennant replaces money
                local sc      = HAND_SHORTCODES[glock.hand_type] or "??"
                local pen_y   = math.floor(BAR_HEIGHT * 0.5 - 7)  -- center 14px pennant
                local pen_w   = TG.Phosphor.width(sc, "mono", 7) + 10
                draw_gambit_pennant(letter_right, pen_y, pen_w, bc, sc)
            else
                -- Money: mono 7px, warm gold, glow 0.15
                local money   = board.money or 0
                local money_s = "$" .. tostring(money)
                local money_y = math.floor(BAR_HEIGHT * 0.5 - TG.Phosphor.height("mono", 7) * 0.5)
                TG.Phosphor.draw(money_s, letter_right, money_y,
                                 { 1.0, 0.835, 0.31 }, 0.15, "mono", 7)
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
