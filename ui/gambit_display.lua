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

local BADGE_H       = 16
local BADGE_ACCENT  = 3
local BADGE_FONT_SZ = 7
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

    local id  = gambit.board
    local bc  = BOARD_UI_COLORS[id] or { 1, 1, 1 }
    local sc  = HAND_SHORTCODES[gambit.hand_type] or "??"
    local lvl = "+" .. tostring(gambit.level_boost or 0)
    local label = id .. " " .. sc .. lvl

    local badge_x = sx
    local badge_y = sy + (card_h or 80) - BADGE_H
    local badge_w = (card_w or 60)

    -- Dark backing slab
    love.graphics.setColor(0.012, 0.004, 0.039, 0.88)
    love.graphics.rectangle("fill", badge_x, badge_y, badge_w, BADGE_H)

    -- Left accent bar + bloom
    love.graphics.setBlendMode("add")
    love.graphics.setColor(bc[1], bc[2], bc[3], 0.5)
    love.graphics.rectangle("fill", badge_x, badge_y, 6, BADGE_H)
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(bc[1], bc[2], bc[3], 1.0)
    love.graphics.rectangle("fill", badge_x, badge_y, BADGE_ACCENT, BADGE_H)

    -- Text with phosphor glow
    local text_x = badge_x + BADGE_ACCENT + 3
    local text_y = badge_y + math.floor((BADGE_H - TG.Phosphor.height(BADGE_FONT_SZ)) / 2)
    TG.Phosphor.draw(label, text_x, text_y, BADGE_CREAM, 0.3, BADGE_FONT_SZ, 0.85)
end

-- ============================================================
-- DRAW ALL BADGES
-- Called from TG.Hooks.draw()
-- ============================================================

function GD.draw_all()
    if not TG or not TG.initialized then return end
    if not TG.Phosphor then return end
    if not (G and G.hand and G.hand.cards) then return end

    -- Only show badges during selecting hand state
    local in_play = (G.STATE == G.STATES.SELECTING_HAND)
               or  (G.STATE == G.STATES.DRAW_TO_HAND)
    if not in_play then return end

    -- For each card in hand, check if any board has a gambit
    -- and the card belongs to that board's deck
    -- Simplified: show gambit badge for active board on all cards
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
