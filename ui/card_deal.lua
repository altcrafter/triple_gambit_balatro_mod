--[[
    TRIPLE GAMBIT - ui/card_deal.lua
    NEW. Staggered card entrance animation on board switch.
    Approach B (spec default): translates the entire hand area down + fades in.
    If per-card stagger is needed, promote to Approach A (Card:draw hook).
]]

local CardDeal = {}

CardDeal._timer    = nil   -- nil = no animation, 0+ = active
CardDeal._duration = 0.5   -- total animation window in seconds

-- ============================================================
-- TRIGGER (Kara calls this after execute_switch populates G.hand)
-- ============================================================

function CardDeal.trigger()
    CardDeal._timer = 0
end

-- ============================================================
-- UPDATE
-- ============================================================

function CardDeal.update(dt)
    if CardDeal._timer == nil then return end
    CardDeal._timer = CardDeal._timer + dt
    if CardDeal._timer >= CardDeal._duration then
        CardDeal._timer = nil
    end
end

-- ============================================================
-- GET CARD OFFSET (per-card stagger for Approach A if ever needed)
-- Returns { y = offset_px, alpha = 0-1 }
-- card_index: 1-based
-- ============================================================

function CardDeal.get_card_offset(card_index)
    if CardDeal._timer == nil then
        return { y = 0, alpha = 1 }
    end

    local card_delay = (card_index - 1) * 0.08
    local card_phase = (CardDeal._timer - card_delay) / 0.12
    card_phase = math.max(0, math.min(1, card_phase))

    -- Quadratic ease-in
    local deal_y     = (1 - card_phase * card_phase) * 60
    local deal_alpha = card_phase

    return { y = deal_y, alpha = deal_alpha }
end

-- ============================================================
-- DRAW (Approach B: whole-hand overlay)
-- Draws a semi-transparent fade-in overlay that lifts off over duration.
-- This is applied as an additive mask on top of the hand area.
-- ============================================================

function CardDeal.draw()
    if CardDeal._timer == nil then return end

    local t = CardDeal._timer / CardDeal._duration
    -- Ease-in: alpha goes from 1 (fully dark) to 0 (transparent)
    local fade_alpha = math.max(0, 1 - t * t)

    if fade_alpha < 0.01 then return end

    local sw, sh = love.graphics.getDimensions()
    -- Hand area: roughly centered, lower third of screen
    -- Use a generous overlay region
    local hand_y = sh * 0.55
    local hand_h = sh * 0.35

    -- Upward translation: cards appear to rise up from below
    local lift_offset = (1 - math.min(1, t * 1.5)) * 50

    -- Darken mask from below (simulate cards entering from below screen)
    love.graphics.setColor(0.012, 0.004, 0.039, fade_alpha * 0.6)
    love.graphics.rectangle("fill", 0, hand_y + lift_offset, sw, hand_h)

    love.graphics.setColor(1, 1, 1, 1)
end

-- ============================================================
-- ACTIVE CHECK
-- ============================================================

function CardDeal.is_active()
    return CardDeal._timer ~= nil
end

return CardDeal
