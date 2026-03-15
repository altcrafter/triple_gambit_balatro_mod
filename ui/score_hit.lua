--[[
    TRIPLE GAMBIT - ui/score_hit.lua
    Score hit: letter scale animation in status bar + particle burst.
    Triggered from main.lua on_score_calculated when total_scored > 0.
]]

local ScoreHit = {}

-- Per-board scale timers: { timer=0+, duration=0.20 }
local _scales = {}

-- ============================================================
-- TRIGGER
-- ============================================================

function ScoreHit.trigger(board_id)
    if not board_id then return end
    _scales[board_id] = { timer = 0.0, duration = 0.20 }
end

-- ============================================================
-- UPDATE
-- ============================================================

function ScoreHit.update(dt)
    for id, s in pairs(_scales) do
        s.timer = s.timer + dt
        if s.timer >= s.duration then
            _scales[id] = nil
        end
    end
end

-- ============================================================
-- GET SCALE (for status_bar.lua to query)
-- Returns 1.0 when inactive, 1.0→1.20→1.0 envelope when active.
-- ============================================================

function ScoreHit.get_scale(board_id)
    local s = _scales[board_id]
    if not s then return 1.0 end
    local t = s.timer / s.duration  -- 0 → 1
    -- Scale envelope: up then snap back
    -- 0→0.4: rise to 1.20, 0.4→1.0: snap back
    local scale
    if t < 0.40 then
        scale = 1.0 + 0.20 * (t / 0.40)
    else
        -- Snap back with slight overshoot
        local decay = (t - 0.40) / 0.60
        scale = 1.20 - 0.22 * decay
        scale = math.max(1.0, scale)
    end
    return scale
end

-- ============================================================
-- DRAW (particle burst at play button area)
-- ============================================================

local _burst = nil   -- { board_id, timer, duration, particles }

local BOARD_UI_COLORS = {
    A = { 1.0,   0.176, 0.42  },
    B = { 0.0,   0.898, 1.0   },
    C = { 1.0,   0.667, 0.133 },
    D = { 0.706, 0.302, 1.0   },
}

function ScoreHit.trigger_burst(board_id)
    if not board_id then return end
    local sw, sh = love.graphics.getDimensions()
    local cx = sw * 0.50
    local cy = sh * 0.72  -- approximate play-button region

    -- Spawn particles
    local particles = {}
    local bc = BOARD_UI_COLORS[board_id] or { 1, 1, 1 }
    for i = 1, 18 do
        local angle = (i / 18) * math.pi * 2 + (math.random() - 0.5) * 0.4
        local speed = 60 + math.random() * 120
        table.insert(particles, {
            x   = cx, y = cy,
            vx  = math.cos(angle) * speed,
            vy  = math.sin(angle) * speed - 40,
            life = 1.0,
            r   = 2 + math.random() * 3,
            bc  = bc,
        })
    end

    _burst = {
        board_id  = board_id,
        timer     = 0.0,
        duration  = 0.55,
        particles = particles,
    }
end

function ScoreHit.update_burst(dt)
    if not _burst then return end
    _burst.timer = _burst.timer + dt
    for _, p in ipairs(_burst.particles) do
        p.x   = p.x + p.vx * dt
        p.y   = p.y + p.vy * dt
        p.vy  = p.vy + 200 * dt  -- gravity
        p.life = p.life - dt / _burst.duration
    end
    if _burst.timer >= _burst.duration then
        _burst = nil
    end
end

function ScoreHit.draw()
    if not _burst then return end
    for _, p in ipairs(_burst.particles) do
        if p.life > 0 then
            local a = math.max(0, p.life)
            love.graphics.setBlendMode("add")
            love.graphics.setColor(p.bc[1], p.bc[2], p.bc[3], a * 0.85)
            love.graphics.circle("fill", p.x, p.y, p.r * a)
            love.graphics.setBlendMode("alpha")
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return ScoreHit
