--[[
    TRIPLE GAMBIT - ui/kinetics.lua
    Physics engine: screen shake, particle bursts, score popups, glitch.
    Bacon builds this. Kara calls it from hooks.
]]

local Kinetics = {}

-- ============================================================
-- SHAKE STATE
-- ============================================================

Kinetics._shake = { x = 0, y = 0, decay = 0, time = 0, current_x = 0, current_y = 0 }

function Kinetics.shake(amp_x, amp_y, dur)
    Kinetics._shake.x     = amp_x
    Kinetics._shake.y     = amp_y
    Kinetics._shake.decay = dur
    -- Do NOT reset _shake.time — let the oscillation continue for chaotic feel
end

function Kinetics.apply_shake()
    love.graphics.translate(Kinetics._shake.current_x, Kinetics._shake.current_y)
end

-- ============================================================
-- GLITCH STATE
-- ============================================================

Kinetics._glitch = 0

function Kinetics.glitch(intensity)
    Kinetics._glitch = intensity
end

-- ============================================================
-- PARTICLE SYSTEM
-- ============================================================

Kinetics._emitters     = {}
Kinetics._particle_img = nil

local EMITTER_COLORS = {
    A       = { 1.0,   0.176, 0.42  },  -- #ff2d6b hot pink
    B       = { 0.0,   0.898, 1.0   },  -- #00e5ff cyan
    C       = { 1.0,   0.667, 0.133 },  -- #ffaa22 amber
    D       = { 0.706, 0.302, 1.0   },  -- #b44dff violet
    clear   = { 0.412, 0.941, 0.682 },  -- #69f0ae mint
    discard = { 0.251, 0.769, 1.0   },  -- #40c4ff light blue
}

-- Map hex strings to emitter keys
local HEX_TO_KEY = {
    ["#ff2d6b"] = "A",
    ["#00e5ff"] = "B",
    ["#ffaa22"] = "C",
    ["#b44dff"] = "D",
    ["#69f0ae"] = "clear",
    ["#40c4ff"] = "discard",
}

local function rgb_to_key(r, g, b)
    -- Match by closest board color
    if type(r) == "table" then
        local c = r
        -- Support both {r, g, b} array and {r=x, g=y, b=z} dict (TG.CONFIG.COLORS format)
        if c.r ~= nil then
            r, g, b = c.r, c.g, c.b
        else
            r, g, b = c[1], c[2], c[3]
        end
    end
    -- Approximate: find which emitter color is closest
    local best_key = "clear"
    local best_dist = math.huge
    for key, col in pairs(EMITTER_COLORS) do
        local dr = r - col[1]
        local dg = g - col[2]
        local db = b - col[3]
        local dist = dr*dr + dg*dg + db*db
        if dist < best_dist then
            best_dist = dist
            best_key  = key
        end
    end
    return best_key
end

local function hex_to_rgb(hex)
    hex = hex:gsub("#", "")
    local r = tonumber(hex:sub(1, 2), 16) / 255
    local g = tonumber(hex:sub(3, 4), 16) / 255
    local b = tonumber(hex:sub(5, 6), 16) / 255
    return r, g, b
end

local function make_particle_image()
    -- Create a 8x8 white circle canvas
    local canvas = love.graphics.newCanvas(8, 8)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("fill", 4, 4, 4)
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)
    return canvas
end

function Kinetics.init_particles()
    local ok, img = pcall(make_particle_image)
    if not ok then
        -- Fallback: 4x4 image
        local ok2, img2 = pcall(love.graphics.newCanvas, 4, 4)
        if ok2 then img = img2 end
    end
    if not img then return end
    Kinetics._particle_img = img

    for name, c in pairs(EMITTER_COLORS) do
        local ps = love.graphics.newParticleSystem(img, 100)
        ps:setParticleLifetime(0.4, 1.0)
        ps:setSizeVariation(0.5)
        ps:setSizes(2.5, 1.5, 0.5)
        ps:setSpeed(60, 180)
        ps:setSpread(math.pi * 2)
        ps:setLinearAcceleration(0, 300)
        ps:setColors(
            c[1], c[2], c[3], 0.9,
            c[1], c[2], c[3], 0.0
        )
        ps:setEmissionRate(0)
        Kinetics._emitters[name] = ps
    end
end

function Kinetics.burst(cx, cy, color, count)
    local key
    if type(color) == "string" then
        key = HEX_TO_KEY[color] or rgb_to_key(hex_to_rgb(color))
    elseif type(color) == "table" then
        key = rgb_to_key(color)  -- rgb_to_key handles both array and {r=,g=,b=} dict
    end

    local ps = key and Kinetics._emitters[key]
    if not ps then return end

    ps:setPosition(cx, cy)
    ps:emit(count or 12)
end

function Kinetics.draw_particles()
    if not next(Kinetics._emitters) then return end
    love.graphics.setBlendMode("add")
    for _, ps in pairs(Kinetics._emitters) do
        love.graphics.draw(ps)
    end
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)
end

-- ============================================================
-- SCORE POPUPS
-- ============================================================

Kinetics._popups = {}

function Kinetics.popup(text, color, x, y, size, dur)
    local r, g, b
    if type(color) == "string" then
        r, g, b = hex_to_rgb(color)
    elseif type(color) == "table" then
        -- Handle both {r, g, b} array and {r=x, g=y, b=z} dict (TG.CONFIG.COLORS format)
        if color.r ~= nil then
            r, g, b = color.r, color.g, color.b
        else
            r, g, b = color[1], color[2], color[3]
        end
    else
        r, g, b = 1, 1, 1
    end

    table.insert(Kinetics._popups, {
        text     = tostring(text),
        x        = x,
        y        = y,
        vy       = -80 - math.random() * 40,
        color    = { r, g, b },
        life     = 0,
        max_life = dur or 1.2,
        size     = size or 22,
    })
end

function Kinetics.draw_popups()
    if not TG or not TG.Phosphor then return end
    for _, p in ipairs(Kinetics._popups) do
        local alpha
        if p.life < 0.1 then
            alpha = p.life / 0.1
        else
            alpha = math.max(0, 1 - (p.life - 0.1) / (p.max_life - 0.1))
        end
        local glow = 1.2 * alpha
        TG.Phosphor.draw(p.text, p.x, p.y, p.color, glow, "serif", p.size, alpha, math.rad(2))
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- ============================================================
-- UPDATE (called every frame from TG.Hooks.update)
-- ============================================================

function Kinetics.update(dt)
    -- Shake
    local sh = Kinetics._shake
    sh.time = sh.time + dt
    if sh.decay > 0 then
        sh.decay = sh.decay - dt
        local intensity = math.max(0, sh.decay) / 0.25
        sh.current_x = sh.x * intensity * math.sin(sh.time * 120)
        sh.current_y = sh.y * intensity * math.cos(sh.time * 90)
    else
        sh.current_x = 0
        sh.current_y = 0
    end

    -- Glitch decay
    Kinetics._glitch = math.max(0, Kinetics._glitch - dt * 3)
    -- Random micro-glitch
    if math.random() < 0.008 then
        Kinetics._glitch = 0.3 + math.random() * 0.6
    end

    -- Particle emitters
    for _, ps in pairs(Kinetics._emitters) do
        ps:update(dt)
    end

    -- Popups
    local i = 1
    while i <= #Kinetics._popups do
        local p = Kinetics._popups[i]
        p.life = p.life + dt
        p.y    = p.y + p.vy * dt
        p.vy   = p.vy * 0.96
        if p.life >= p.max_life then
            table.remove(Kinetics._popups, i)
        else
            i = i + 1
        end
    end
end

return Kinetics
