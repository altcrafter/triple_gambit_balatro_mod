-- Mods/TripleGambit/ui/resource_display.lua
-- Robust resource display for Triple Gambit
local M = {}

local L = {
    row_h   = 26,
    pad     = 6,
    margin_r= 6,
    gauge_h = 4,
    width   = 96,
    y       = 60,
    font    = nil, -- will be set in init
}

local function safe_num(v, fallback)
    return tonumber(v) or (fallback or 0)
end

local function draw_row(x, y, w, label, cur, max, color)
    -- Defensive normalization
    cur = safe_num(cur, 0)
    max = safe_num(max, 0)

    local progress = 0
    if max > 0 then
        progress = math.max(0, math.min(1, cur / max))
    else
        progress = 0
    end

    local font = L.font or love.graphics.getFont()
    love.graphics.setFont(font)

    -- Label
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(label, x, y)

    -- Numeric text
    local ntxt = tostring(cur)
    if max > 0 then ntxt = ntxt .. "/" .. tostring(max) end
    local ntw = font:getWidth(ntxt)
    love.graphics.print(ntxt, x + w - ntw, y)

    -- Gauge background
    local gy = y + L.row_h - L.gauge_h - 2
    love.graphics.setColor(0.06, 0.06, 0.06, 1)
    love.graphics.rectangle("fill", x, gy, w, L.gauge_h)

    -- Gauge fill
    local col = color or { r = 0.9, g = 0.9, b = 0.9 }
    love.graphics.setColor(col.r or 1, col.g or 1, col.b or 1, 1)
    love.graphics.rectangle("fill", x, gy, math.floor(w * progress), L.gauge_h)

    -- Reset color
    love.graphics.setColor(1, 1, 1, 1)
end

function M.init(opts)
    opts = opts or {}
    L.font = opts.font or love.graphics.getFont()
    L.row_h = opts.row_h or L.row_h
    L.pad   = opts.pad   or L.pad
    L.width = opts.width or L.width
    L.y     = opts.y     or L.y
end

function M.draw()
    -- Positioning: top-right area
    local screen_w = love.graphics.getWidth()
    local x = screen_w - L.width - L.margin_r
    local y = L.y

    -- Defensive TG/board/config access
    local board = (TG and TG.initialized) and TG:get_active_board() or nil
    local cfg   = (TG and TG.CONFIG) and TG.CONFIG or nil

    local cur_hands = board and safe_num(board.hands_remaining) or 0
    local max_hands = cfg and safe_num(cfg.HANDS_PER_BLIND) or 0
    -- Include clear bonus in max display
    local bonus_h = (TG and TG.clear_bonus_hands) or 0
    max_hands = max_hands + bonus_h

    local cur_disc  = board and safe_num(board.discards_remaining) or 0
    local max_disc  = cfg and safe_num(cfg.DISCARDS_PER_BLIND) or 0
    local bonus_d = (TG and TG.clear_bonus_discards) or 0
    max_disc = max_disc + bonus_d

    -- Colors (tweakable)
    local hands_col = { r = 0.92, g = 0.55, b = 0.18 }
    local disc_col  = { r = 0.27, g = 0.48, b = 0.62 }
    local sw_col    = { r = 0.6,  g = 0.3,  b = 0.7  }

    draw_row(x, y, L.width, "HANDS",    cur_hands,  max_hands,  hands_col); y = y + L.row_h + L.pad
    draw_row(x, y, L.width, "DISCARDS", cur_disc,   max_disc,   disc_col)
end

-- Shake state: key -> seconds remaining
local shake_state = {}

function M.trigger_shake(key)
    shake_state[key] = 0.35  -- shake duration in seconds
end

function M.update_shake(dt)
    for key, t in pairs(shake_state) do
        shake_state[key] = t - dt
        if shake_state[key] <= 0 then
            shake_state[key] = nil
        end
    end
end

return M
