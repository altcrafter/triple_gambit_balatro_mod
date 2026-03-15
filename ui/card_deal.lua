--[[
    TRIPLE GAMBIT - ui/card_deal.lua
    Staggered card entrance animation on board switch.
    Right-edge reveal: right side of hand clears first, left side last.
    Simulates cards dealing in from the right.
]]

local CardDeal = {}

CardDeal._timer    = nil
CardDeal._duration = 0.38

function CardDeal.trigger()
    CardDeal._timer = 0
end

function CardDeal.update(dt)
    if CardDeal._timer == nil then return end
    CardDeal._timer = CardDeal._timer + dt
    if CardDeal._timer >= CardDeal._duration then
        CardDeal._timer = nil
    end
end

-- Right-to-left sweep reveal over the hand area
-- Segments: rightmost clears first, leftmost clears last
function CardDeal.draw()
    if CardDeal._timer == nil then return end

    local t  = math.min(1.0, CardDeal._timer / CardDeal._duration)
    local sw, sh = love.graphics.getDimensions()

    -- Hand area (approximate lower portion of screen)
    local hand_top = sh * 0.48
    local hand_h   = sh * 0.46

    -- Use 10 vertical strips; rightmost strip has stagger_offset = 0, leftmost = 0.45
    local strips = 10
    for i = 1, strips do
        -- i=1 is leftmost, i=strips is rightmost
        local stagger = (strips - i) * (0.45 / strips)  -- left strips lag behind
        local strip_t = math.max(0, math.min(1, (t - stagger) / (1 - stagger + 0.001)))
        -- Ease-out: (1 - (1-x)^2)
        local eased   = 1 - (1 - strip_t) ^ 2
        local alpha   = math.max(0, 1 - eased * 1.4) * 0.88

        if alpha > 0.005 then
            local strip_x = sw * (i - 1) / strips
            local strip_w = sw / strips + 1
            love.graphics.setColor(0.012, 0.004, 0.039, alpha)
            love.graphics.rectangle("fill", strip_x, hand_top, strip_w, hand_h)
        end
    end

    -- Leading edge shimmer (board color flash sweeping left)
    if t < 0.75 and TG and TG.active_board_id then
        local bc = ({
            A = { 1.0,   0.176, 0.42  },
            B = { 0.0,   0.898, 1.0   },
            C = { 1.0,   0.667, 0.133 },
            D = { 0.706, 0.302, 1.0   },
        })[TG.active_board_id] or { 1, 1, 1 }
        -- Leading edge x: sweeps from right (sw) to left (0)
        local edge_x = sw * (1 - t / 0.75)
        local edge_a = (1 - t / 0.75) * 0.55
        love.graphics.setBlendMode("add")
        love.graphics.setColor(bc[1], bc[2], bc[3], edge_a)
        love.graphics.rectangle("fill", edge_x - 4, hand_top, 8, hand_h)
        love.graphics.setBlendMode("alpha")
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function CardDeal.is_active()
    return CardDeal._timer ~= nil
end

return CardDeal
