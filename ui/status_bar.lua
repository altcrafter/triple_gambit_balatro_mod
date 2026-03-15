--[[
    TRIPLE GAMBIT - ui/status_bar.lua
    Board command strip across the top. 4 equal cells.
    VELOCI MAISON edition: A · APEX format, rev counter arc, checkered CLEARED.
]]

local StatusBar = {}

local BASE_SH = 540

local BOARD_UI_COLORS = {
    A = { 1.0,   0.176, 0.42  },
    B = { 0.0,   0.898, 1.0   },
    C = { 1.0,   0.667, 0.133 },
    D = { 0.706, 0.302, 1.0   },
}

local BOARD_NAMES = {
    A = "APEX",
    B = "NOCTURNE",
    C = "SOLAR",
    D = "DRIFT",
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
local _time       = 0

-- Rev counter arc: tracks per switch-in animation
local _rev_arc = { id = nil, progress = 0.0, duration = 0.30 }

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
-- UPDATE
-- ============================================================

function StatusBar.update(dt)
    _time = _time + dt
    if _rev_arc.id then
        _rev_arc.progress = math.min(1.0, _rev_arc.progress + dt / _rev_arc.duration)
    end
end

function StatusBar.on_board_switch(to_id)
    _rev_arc.id       = to_id
    _rev_arc.progress = 0.0
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
    local bh      = math.floor(73  * scale)
    local accent  = math.floor(7   * scale)
    local name_sz = math.floor(16  * scale)
    local m_size  = math.floor(14  * scale)
    local c_size  = math.floor(12  * scale)
    local pad     = math.floor(6   * scale)
    local pen_h   = math.floor(17  * scale)
    local pen_pt  = math.floor(7   * scale)
    local sep_w   = math.max(2, math.floor(2 * scale))

    local ids    = board_ids()
    local n      = #ids
    local cell_w = math.floor(w / n)

    -- ── Background ─────────────────────────────────────────────
    love.graphics.setColor(0.010, 0.003, 0.032, 0.92)
    love.graphics.rectangle("fill", 0, 0, w, bh)

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

        -- ── Active background tint / Cleared checkered ───────
        if cleared then
            -- Checkered flag tint
            local check_sz = math.max(6, math.floor(7 * scale))
            local cols = math.ceil(cell_w / check_sz) + 1
            local rows = math.ceil(bh / check_sz) + 1
            for row = 0, rows - 1 do
                for col = 0, cols - 1 do
                    if (row + col) % 2 == 0 then
                        love.graphics.setColor(1, 1, 1, 0.04)
                        love.graphics.rectangle("fill",
                            cx0 + col * check_sz, row * check_sz,
                            check_sz, check_sz)
                    end
                end
            end
        elseif active then
            love.graphics.setColor(bc[1], bc[2], bc[3], 0.08)
            love.graphics.rectangle("fill", cx0, 0, cell_w, bh)
        end

        -- ── Left accent bar ───────────────────────────────────
        local acc_a = active and 1.0 or (cleared and 0.85 or 0.28)
        love.graphics.setColor(ac[1], ac[2], ac[3], acc_a)
        love.graphics.rectangle("fill", cx0, 0, accent, bh)

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

        -- ── Rev counter arc (active board only, on switch-in) ──
        if active and _rev_arc.id == id and _rev_arc.progress < 1.0 then
            local arc_prog = _rev_arc.progress
            -- Smoothstep the arc
            local eased = arc_prog * arc_prog * (3 - 2 * arc_prog)
            local arc_r  = math.floor(20 * scale)
            local arc_cx = cx0 + cell_w - arc_r - math.floor(6 * scale)
            local arc_cy = math.floor(bh * 0.5)
            local start_a = math.pi * 0.80
            local sweep   = math.pi * 1.55 * eased  -- 0 → ~280°
            if sweep > 0.05 then
                love.graphics.setLineWidth(math.max(2, math.floor(2.5 * scale)))
                -- Glow ring (additive)
                love.graphics.setBlendMode("add")
                love.graphics.setColor(bc[1], bc[2], bc[3], 0.35)
                love.graphics.arc("line", "open", arc_cx, arc_cy, arc_r + 1, start_a, start_a + sweep)
                love.graphics.setBlendMode("alpha")
                -- Main arc
                love.graphics.setColor(bc[1], bc[2], bc[3], 0.90)
                love.graphics.arc("line", "open", arc_cx, arc_cy, arc_r, start_a, start_a + sweep)
                love.graphics.setLineWidth(1)
            end
        elseif active and _rev_arc.id == id then
            -- Hold full arc at rest (dim)
            local arc_r  = math.floor(20 * scale)
            local arc_cx = cx0 + cell_w - arc_r - math.floor(6 * scale)
            local arc_cy = math.floor(bh * 0.5)
            love.graphics.setLineWidth(math.max(1, math.floor(1.5 * scale)))
            love.graphics.setColor(bc[1], bc[2], bc[3], 0.22)
            love.graphics.arc("line", "open", arc_cx, arc_cy, arc_r, math.pi * 0.80, math.pi * 0.80 + math.pi * 1.55)
            love.graphics.setLineWidth(1)
        end

        -- ── Brand name + money stacked ─────────────────────────
        local brand  = (id or "?") .. " · " .. (BOARD_NAMES[id] or id)
        local text_x = cx0 + accent + pad * 2

        local lc, lg, la
        if active then
            lc, lg, la = bc, 0.65, 1.0
        elseif cleared then
            -- Slow pulse glow on cleared boards
            local pulse = 0.5 + math.sin(_time * 2.0) * 0.3
            lc, lg, la  = CLEARED_COLOR, 0.15 * pulse, 0.85
        else
            lc, lg, la = { 1, 1, 1 }, 0.0, 0.22
        end

        -- Score hit scale: check TG.UI.ScoreHit for letter scale
        local letter_scale = 1.0
        if TG.UI and TG.UI.ScoreHit then
            letter_scale = TG.UI.ScoreHit.get_scale(id)
        end

        if board then
            if cleared then
                local name_h  = TG.Phosphor.height("mono", name_sz)
                local cl_h    = TG.Phosphor.height("mono", c_size)
                local stack_h = name_h + 4 + cl_h
                local top_y   = math.floor((bh - stack_h) * 0.5)

                if letter_scale ~= 1.0 then
                    local cx2 = text_x + TG.Phosphor.width(brand, "mono", name_sz) * 0.5
                    local cy2 = top_y + name_h * 0.5
                    love.graphics.push()
                    love.graphics.translate(cx2, cy2)
                    love.graphics.scale(letter_scale, letter_scale)
                    love.graphics.translate(-cx2, -cy2)
                end
                TG.Phosphor.draw(brand, text_x, top_y, lc, lg, "mono", name_sz, la)
                if letter_scale ~= 1.0 then love.graphics.pop() end

                TG.Phosphor.draw("CLEARED", text_x, top_y + name_h + 4,
                                 CLEARED_COLOR, 0.6, "mono", c_size, 0.95)
            else
                local money   = board.money or 0
                local money_s = "$" .. tostring(money)
                local name_h  = TG.Phosphor.height("mono", name_sz)
                local mon_h   = TG.Phosphor.height("mono", m_size)
                local stack_h = name_h + 4 + mon_h
                local top_y   = math.floor((bh - stack_h) * 0.5)

                if letter_scale ~= 1.0 then
                    local cx2 = text_x + TG.Phosphor.width(brand, "mono", name_sz) * 0.5
                    local cy2 = top_y + name_h * 0.5
                    love.graphics.push()
                    love.graphics.translate(cx2, cy2)
                    love.graphics.scale(letter_scale, letter_scale)
                    love.graphics.translate(-cx2, -cy2)
                end
                TG.Phosphor.draw(brand, text_x, top_y, lc, lg, "mono", name_sz, la)
                if letter_scale ~= 1.0 then love.graphics.pop() end

                local money_y = top_y + name_h + 4
                local ma      = active and 1.0 or 0.40
                local mg      = active and 0.35 or 0.0
                TG.Phosphor.draw(money_s, text_x, money_y,
                                 { 1.0, 0.835, 0.31 }, mg, "mono", m_size, ma)

                local G_STATE = (G and G.STATE and G.STATES) and G.STATE
                local in_shop = G_STATE and G.STATES.SHOP and (G_STATE == G.STATES.SHOP)
                local glock   = (not in_shop) and get_gambit_lock(id) or nil
                if glock then
                    local sc    = (HAND_SHORTCODES[glock.hand_type] or "??")
                               .. "+" .. tostring(glock.level_boost or 0)
                    local pen_y = money_y + mon_h + pad
                    if pen_y + pen_h <= bh - pad then
                        local pen_w = TG.Phosphor.width(sc, "mono", m_size) + pad * 2
                        draw_gambit_pennant(text_x, pen_y, pen_w, bc, sc,
                                            pen_h, pen_pt, m_size, pad)
                    end
                end
            end
        else
            local name_h = TG.Phosphor.height("mono", name_sz)
            local name_y = math.floor((bh - name_h) * 0.5)
            TG.Phosphor.draw(brand, text_x, name_y, lc, lg, "mono", name_sz, la)
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
