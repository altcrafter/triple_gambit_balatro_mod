--[[
    TRIPLE GAMBIT - ui/gambit_display.lua
    Industrial Brutalism gambit badges on joker cards.

    FIXES:
    1. Only assigns gambits to cards where card.ability.set == "Joker"
    2. Works during ALL pack-opening states (TAROT_PACK, SPECTRAL_PACK, etc.)
    3. Gambit data stored on card.tg_gambit_id → survives purchase transition
    4. Badge drawn at card BOTTOM with solid panel, never overlaps progress bar

    Badge style: dark panel with thick left color accent, ALL CAPS label.
    "B FLUSH +2" format.
]]

TG    = TG or {}
TG.UI = TG.UI or {}
TG.UI.GambitDisplay = {}

local GD = TG.UI.GambitDisplay

-- ============================================================
-- TYPE CHECKS
-- ============================================================

local function is_joker_card(card)
    if not card then return false end
    if card.ability and card.ability.set == "Joker" then return true end
    if card.config and card.config.center and card.config.center.set == "Joker" then return true end
    return false
end

local function is_shop_or_pack()
    if not (G and G.STATE and G.STATES) then return false end
    if G.STATE == G.STATES.SHOP then return true end
    for _, s in ipairs({"TAROT_PACK","SPECTRAL_PACK","STANDARD_PACK","BUFFOON_PACK","PLANET_PACK"}) do
        if G.STATES[s] and G.STATE == G.STATES[s] then return true end
    end
    return false
end

-- ============================================================
-- DRAW ALL
-- ============================================================

function GD.draw_all()
    if not is_shop_or_pack() then return end
    GD.draw_shop_jokers()
end

-- ============================================================
-- SCAN + RENDER
-- ============================================================

function GD.draw_shop_jokers()
    local sources = {}
    if G.shop_jokers and G.shop_jokers.cards then
        for _, c in ipairs(G.shop_jokers.cards) do table.insert(sources, c) end
    end
    if G.pack_cards and G.pack_cards.cards then
        for _, c in ipairs(G.pack_cards.cards) do table.insert(sources, c) end
    end

    for _, card in ipairs(sources) do
        if card and is_joker_card(card) then
            -- Lazy-assign gambit
            if not card.tg_gambit_id and TG.Gambit then
                TG.Gambit.assign_random(card)
            end
            if card.tg_gambit_id then
                local template = TG.Gambit.get_template(card.tg_gambit_id)
                if template then GD.draw_badge(card, template) end
            end
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- ============================================================
-- BADGE RENDERING
-- ============================================================

function GD.draw_badge(card, template)
    local pos = card.VT or card.T
    if not pos then return end
    if not (pos.x and pos.y and pos.w and pos.h) then return end

    local col = TG.CONFIG.COLORS[template.board]
    if not col then return end

    -- Game→screen coordinate conversion
    local s = (G.TILESCALE or 1) * (G.TILESIZE or 1)
    if s == 0 then s = 1 end

    local badge_h = pos.h * 0.16
    local bx = pos.x * s
    local by = (pos.y + pos.h - badge_h) * s
    local bw = pos.w * s
    local bh = badge_h * s

    -- ── Dark panel (near-black, high opacity) ──
    love.graphics.setColor(0.03, 0.03, 0.04, 0.94)
    love.graphics.rectangle("fill", bx, by, bw, bh)

    -- ── Left accent bar (board color, thick) ──
    love.graphics.setColor(col.r, col.g, col.b, 1.0)
    love.graphics.rectangle("fill", bx, by, 3, bh)

    -- ── Top edge line ──
    love.graphics.setColor(col.r, col.g, col.b, 0.5)
    love.graphics.setLineWidth(1)
    love.graphics.line(bx, by, bx + bw, by)

    -- ── Label: "B FLUSH +2" ──
    local letter = template.board or "?"
    local hand   = GD.short_name(template.hand_type)
    local label  = letter .. " " .. hand .. " +" .. template.level_boost

    local font = love.graphics.getFont()
    local tw   = font:getWidth(label)
    local ts   = math.min(0.60, (bw - 8) / tw)
    local th   = font:getHeight() * ts

    love.graphics.setColor(0.93, 0.90, 0.82, 0.95)
    love.graphics.print(label, bx + 5, by + (bh - th) * 0.5, 0, ts, ts)

    love.graphics.setColor(1, 1, 1, 1)
end

-- ============================================================
-- SHORT NAMES
-- ============================================================

function GD.short_name(ht)
    local m = {
        ["High Card"]="HIGH", ["Pair"]="PAIR", ["Two Pair"]="2PAIR",
        ["Three of a Kind"]="3OAK", ["Straight"]="STRT", ["Flush"]="FLUSH",
        ["Full House"]="FULL", ["Four of a Kind"]="4OAK",
        ["Straight Flush"]="STFL", ["Five of a Kind"]="5OAK",
        ["Flush House"]="FLHS", ["Flush Five"]="FL5",
    }
    return m[ht] or ht
end

return GD
