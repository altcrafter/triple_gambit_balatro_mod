--[[
    TRIPLE GAMBIT - ui/gambit_display.lua
    MODIFY: Add phosphor treatment to badge rendering.
    Shows per-card gambit badges floating above card bottoms.
    Keeps: card-scanning logic, coordinate conversion via card.VT, badge positioning.
    Replaces: love.graphics.print calls → TG.Phosphor.draw
]]

local GD = {}

local BOARD_UI_COLORS = {
    A = { 1.0,   0.176, 0.42  },
    B = { 0.0,   0.898, 1.0   },
    C = { 1.0,   0.667, 0.133 },
    D = { 0.706, 0.302, 1.0   },
}

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

-- Sizes computed in draw_badge() from sh
local BASE_SH = 540
local BADGE_CREAM   = { 1.0, 0.961, 0.902 }  -- rgba(255,245,230) warm white/cream

-- ============================================================
-- COORDINATE HELPERS
-- ============================================================

-- Convert Balatro game coordinates to screen pixels
local function game_to_screen(gx, gy)
    if not (G and G.TILESCALE and G.TILESIZE) then
        return gx, gy
    end
    local scale = G.TILESCALE * G.TILESIZE
    local sx = gx * scale
    local sy = gy * scale
    -- Offset by camera/hand position if available
    if G.hand and G.hand.T then
        sx = sx + (G.hand.T.x or 0)
        sy = sy + (G.hand.T.y or 0)
    end
    return sx, sy
end

-- Get card's screen position from its VT table (visual transform)
local function card_screen_pos(card)
    if not card then return nil, nil end
    -- Balatro cards store position in card.T (actual) or card.VT (visual)
    local vt = card.VT or card.T
    if not vt then return nil, nil end
    -- VT coordinates are already in game space; convert to screen
    local sx, sy
    if vt.x and vt.y then
        sx = vt.x
        sy = vt.y
        if G and G.TILESCALE and G.TILESIZE then
            -- Already in screen coords if VT is populated by Balatro's layout engine
            -- Try using them directly first
        end
        return sx, sy, vt.w, vt.h
    end
    return nil, nil, nil, nil
end

-- ============================================================
-- GAMBIT LOOKUP
-- ============================================================

-- Find the gambit lock for a given board id
local function get_gambit_for_board(board_id)
    if not (TG and TG.active_gambits) then return nil end
    for _, g in ipairs(TG.active_gambits) do
        if g.board == board_id then return g end
    end
    return nil
end

-- ============================================================
-- BADGE DRAW
-- ============================================================

local function draw_badge(sx, sy, card_w, card_h, gambit)
    if not gambit or not TG or not TG.Phosphor then return end

    local _, sh = love.graphics.getDimensions()
    local scale    = sh / BASE_SH
    local badge_h  = math.floor(24 * scale)   -- ~40px at 889
    local point    = math.floor(8  * scale)   -- ~13px
    local font_sz  = math.floor(11 * scale)   -- ~18px
    local text_pad = math.floor(4  * scale)   -- ~7px

    local id    = gambit.board
    local bc    = BOARD_UI_COLORS[id] or { 1, 1, 1 }
    local label = (HAND_SHORTCODES[gambit.hand_type] or "??")
               .. "+" .. tostring(gambit.level_boost or 0)

    local badge_y = sy + (card_h or 80) - badge_h
    local badge_x = sx

    local h     = badge_h - math.floor(4 * scale)
    local pen_w = TG.Phosphor.width(label, "mono", font_sz) + text_pad * 2
    local mid_y = badge_y + h * 0.5
    local x0    = badge_x
    local x1    = badge_x + pen_w
    local xp    = x1 + point

    local verts = {
        x0, badge_y,
        x1, badge_y,
        xp, mid_y,
        x1, badge_y + h,
        x0, badge_y + h,
    }

    local pivot_x = badge_x + (pen_w + point) * 0.5
    local pivot_y = mid_y

    love.graphics.push()
    love.graphics.translate(pivot_x, pivot_y)
    love.graphics.rotate(math.rad(3))
    love.graphics.translate(-pivot_x, -pivot_y)

    love.graphics.setColor(bc[1], bc[2], bc[3], 0.10)
    love.graphics.polygon("fill", verts)
    love.graphics.setColor(bc[1], bc[2], bc[3], 0.25)
    love.graphics.setLineWidth(1)
    love.graphics.polygon("line", verts)

    local text_x = badge_x + text_pad
    local text_y = badge_y + math.floor((h - TG.Phosphor.height("mono", font_sz)) * 0.5)
    TG.Phosphor.draw(label, text_x, text_y, bc, 0.2, "mono", font_sz, 0.80)

    love.graphics.pop()
end

-- ============================================================
-- DRAW ALL BADGES
-- Called from TG.Hooks.draw()
-- ============================================================

function GD.draw_all()
    if not TG or not TG.initialized then return end
    if not TG.Phosphor then return end
    if not (G and G.STATE and G.STATES) then return end

    -- ── In shop: badge each owned joker with its board's gambit ──
    if G.STATE == G.STATES.SHOP then
        if G.jokers and G.jokers.cards then
            for _, card in ipairs(G.jokers.cards) do
                local bid = card.tg_board_id
                if bid then
                    local gambit = get_gambit_for_board(bid)
                    if gambit then
                        local sx, sy, cw, ch = card_screen_pos(card)
                        if sx and sy then
                            draw_badge(sx - (cw or 60) / 2, sy - (ch or 80) / 2,
                                       cw or 60, ch or 80, gambit)
                        end
                    end
                end
            end
        end
        love.graphics.setColor(1, 1, 1, 1)
        return
    end

    -- ── During hand play: badge all hand cards with active board's gambit ──
    local in_play = (G.STATE == G.STATES.SELECTING_HAND)
               or  (G.STATE == G.STATES.DRAW_TO_HAND)
    if not in_play then return end
    if not (G.hand and G.hand.cards) then return end

    local active_board_id = TG.active_board_id
    if not active_board_id then return end

    local gambit = get_gambit_for_board(active_board_id)
    if not gambit then return end

    for _, card in ipairs(G.hand.cards) do
        local sx, sy, cw, ch = card_screen_pos(card)
        if sx and sy then
            draw_badge(sx - (cw or 60) / 2, sy - (ch or 80) / 2, cw or 60, ch or 80, gambit)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- Legacy single-card draw (if called from card draw hooks)
function GD.draw_badge_for_card(card, gambit)
    if not card or not gambit then return end
    local sx, sy, cw, ch = card_screen_pos(card)
    if sx and sy then
        draw_badge(sx - (cw or 60) / 2, sy - (ch or 80) / 2, cw or 60, ch or 80, gambit)
    end
end

return GD
