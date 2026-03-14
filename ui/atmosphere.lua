--[[
    TRIPLE GAMBIT - ui/atmosphere.lua
    Fullscreen background layer. Always animating. Draws behind everything.
    Layers (back to front):
      1. Sunset gradient mesh
      2. Sun disc + venetian blind lines
      3. Perspective grid floor
      4. Board color wash
      5. VHS rolling distortion bars
      6. Vignette / scanlines (deferred to tg_shader if available)
      7. Channel badge
]]

local Atm = {}

local _time           = 0
local _wash_current   = { 1.0, 0.176, 0.42 }  -- Board A default
local _wash_target    = { 1.0, 0.176, 0.42 }
local _wash_lerp      = 1.0  -- 1 = arrived

-- Lookup board UI colors (vivid broadcast palette)
local BOARD_UI_COLORS = {
    A = { 1.0,   0.176, 0.42  },
    B = { 0.0,   0.898, 1.0   },
    C = { 1.0,   0.667, 0.133 },
    D = { 0.706, 0.302, 1.0   },
}

-- ============================================================
-- UTILITY
-- ============================================================

local function hsl_to_rgb(h, s, l)
    h = h / 360
    if s == 0 then return l, l, l end
    local function hue2rgb(p, q, t)
        if t < 0 then t = t + 1 end
        if t > 1 then t = t - 1 end
        if t < 1/6 then return p + (q - p) * 6 * t end
        if t < 1/2 then return q end
        if t < 2/3 then return p + (q - p) * (2/3 - t) * 6 end
        return p
    end
    local q = l < 0.5 and l * (1 + s) or l + s - l * s
    local p = 2 * l - q
    return hue2rgb(p, q, h + 1/3), hue2rgb(p, q, h), hue2rgb(p, q, h - 1/3)
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function lerp_color(ca, cb, t)
    return {
        lerp(ca[1], cb[1], t),
        lerp(ca[2], cb[2], t),
        lerp(ca[3], cb[3], t),
    }
end

local function active_board_color()
    if TG and TG.active_board_id then
        return BOARD_UI_COLORS[TG.active_board_id] or BOARD_UI_COLORS.A
    end
    return BOARD_UI_COLORS.A
end

-- ============================================================
-- SUNSET GRADIENT MESH
-- ============================================================

local _gradient_mesh = nil

local GRADIENT_STOPS = {
    -- { base_h, h_amp, h_freq,   s,    base_l, l_amp, l_freq }
    { 260, 15, 0.02,  0.60, 0.08, 0.03, 0.03  },
    { 300, 20, 0.025, 0.45, 0.18, 0.04, 0.04  },
    { 340, 15, 0.03,  0.55, 0.28, 0.05, 0.035 },
    {  20, 10, 0.02,  0.70, 0.38, 0.04, 0.025 },
    {  40,  8, 0.03,  0.80, 0.50, 0.05, 0.04  },
    {  50,  5, 0.035, 0.85, 0.60, 0.03, 0.03  },
}

local STOP_Y_FRAC = { 0.0, 0.2, 0.35, 0.5, 0.7, 1.0 }

local function build_gradient_mesh()
    -- 6 rows x 2 verts (left, right) = 12 vertices, 5 quads (10 triangles)
    local verts = {}
    for i = 1, 6 do
        table.insert(verts, { 0,   0,   0, 0,   1, 1, 1, 1 })
        table.insert(verts, { 100, 0,   0, 0,   1, 1, 1, 1 })
    end
    -- Create a triangle mesh from these quads
    -- Using "strip" format: pairs of vertices per row
    local indices = {}
    for row = 0, 4 do
        local base = row * 2 + 1
        -- quad: base, base+1, base+2, base+1, base+3, base+2
        table.insert(indices, base)
        table.insert(indices, base + 1)
        table.insert(indices, base + 2)
        table.insert(indices, base + 1)
        table.insert(indices, base + 3)
        table.insert(indices, base + 2)
    end

    local ok, mesh = pcall(love.graphics.newMesh, verts, "triangles", "dynamic")
    if ok and mesh then
        local ok2 = pcall(mesh.setVertexMap, mesh, indices)
        if not ok2 then
            -- Rebuild as simple fan if index map fails
        end
        return mesh
    end
    return nil
end

local function update_gradient_mesh(t)
    if not _gradient_mesh then return end
    local w, h = love.graphics.getDimensions()
    for i, stop in ipairs(GRADIENT_STOPS) do
        local H = stop[1] + math.sin(t * stop[3] * 2 * math.pi) * stop[2]
        local S = stop[4]
        local L = stop[5] + math.sin(t * stop[7] * 2 * math.pi) * stop[6]
        local r, g, b = hsl_to_rgb(H, S, L)
        local y = STOP_Y_FRAC[i] * h
        local vi_left  = (i - 1) * 2 + 1
        local vi_right = vi_left + 1
        _gradient_mesh:setVertex(vi_left,  0, y, 0, 0, r, g, b, 0.7)
        _gradient_mesh:setVertex(vi_right, w, y, 0, 0, r, g, b, 0.7)
    end
end

-- ============================================================
-- SUN DISC
-- ============================================================

local _sun_canvas = nil

local function build_sun_canvas()
    local size = 256
    local ok, canvas = pcall(love.graphics.newCanvas, size, size)
    if not ok then return nil end
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    -- Draw concentric circles for a soft radial gradient
    local cx, cy = size / 2, size / 2
    local steps = 24
    for i = steps, 1, -1 do
        local t = i / steps
        local radius = cx * t
        local a = (1 - t) * 0.5
        local r2 = lerp(0.784, 1.0, 1 - t)
        local g2 = lerp(0.392, 0.784, 1 - t)
        local b2 = lerp(0.157, 0.314, 1 - t)
        love.graphics.setColor(r2, g2, b2, a)
        love.graphics.circle("fill", cx, cy, radius)
    end
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)
    return canvas
end

local function draw_sun(t)
    local w, h = love.graphics.getDimensions()
    local sun_x = w / 2
    local sun_y = h * (0.52 + math.sin(t * 0.04 * 2 * math.pi) * 0.08)
    local radius = 70 + math.sin(t * 0.5) * 4
    local alpha  = 0.4 + math.sin(t * 0.3) * 0.08

    if _sun_canvas then
        local scale = radius * 2 / 256
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.draw(_sun_canvas, sun_x - radius, sun_y - radius, 0, scale, scale)
    else
        -- Fallback: simple circle
        love.graphics.setColor(1.0, 0.784, 0.314, alpha * 0.6)
        love.graphics.circle("fill", sun_x, sun_y, radius)
    end

    -- Venetian blind lines below the sun
    local board_c = active_board_color()
    local num_lines = 12
    local spacing   = 7
    for i = 1, num_lines do
        local line_y = sun_y + i * spacing
        local frac   = 1 - (i / num_lines)
        local line_w = w * 0.6 * frac
        local line_x = sun_x - line_w / 2
        love.graphics.setColor(board_c[1], board_c[2], board_c[3], 0.25)
        love.graphics.rectangle("fill", line_x, line_y, line_w, 3)
    end

    love.graphics.setColor(1, 1, 1, 1)
    return sun_x, sun_y
end

-- ============================================================
-- PERSPECTIVE GRID
-- ============================================================

local function draw_grid(t, board_color)
    local w, h = love.graphics.getDimensions()
    local cx = w / 2
    local vy = h * 0.48

    love.graphics.setColor(board_color[1], board_color[2], board_color[3], 0.18)
    love.graphics.setLineWidth(1)

    -- Horizontal lines with quadratic spacing
    for i = 0, 17 do
        local frac = (i / 17) ^ 2.2
        local y = vy + (h - vy) * frac
        love.graphics.line(0, y, w, y)
    end

    -- Vertical lines converging to vanishing point
    for i = 0, 20 do
        local offset = i - 10
        local x_top  = cx + offset * 18
        local x_bot  = cx + offset * 60
        love.graphics.line(x_top, vy, x_bot, h)
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

-- ============================================================
-- BOARD COLOR WASH
-- ============================================================

local function draw_wash(t)
    local w, h = love.graphics.getDimensions()
    local cx = w * 0.5
    local cy = h * 0.55
    local base_r = w * 0.4
    local c = _wash_current

    -- Concentric circles for radial falloff
    local steps = 10
    for i = steps, 1, -1 do
        local frac   = i / steps
        local radius = base_r * frac
        local alpha  = (1 - frac) * 0.16
        love.graphics.setColor(c[1], c[2], c[3], alpha)
        love.graphics.circle("fill", cx, cy, radius)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- ============================================================
-- VHS ROLLING DISTORTION BARS
-- ============================================================

local _vhs_bars = {
    { speed = 2.0,   freq = 1.1, height = 4 },
    { speed = 3.5,   freq = 0.7, height = 6 },
    { speed = 5.0,   freq = 1.7, height = 3 },
}

local function draw_vhs(t)
    local w, h = love.graphics.getDimensions()
    local glitch = (TG and TG.Kinetics) and TG.Kinetics._glitch or 0
    local base_opacity = 0.08 + glitch * 0.42

    for i, bar in ipairs(_vhs_bars) do
        local bar_y   = (t * bar.speed * 40) % h
        local wobble  = math.sin(t * 1.3 + i) * 20
        local bar_h   = bar.height

        love.graphics.setColor(1, 1, 1, base_opacity)
        love.graphics.rectangle("fill", wobble, bar_y, w, bar_h)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- ============================================================
-- CHANNEL BADGE
-- ============================================================

local function draw_channel_badge(t)
    local pad_x = 10
    local pad_y = 44  -- below status bar
    local bw, bh = 80, 22
    local x, y = pad_x, pad_y

    -- Background
    love.graphics.setColor(0.020, 0.008, 0.059, 0.70)
    love.graphics.rectangle("fill", x, y, bw, bh, 2, 2)
    love.graphics.setColor(1, 1, 1, 0.08)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, bw - 1, bh - 1, 2, 2)

    -- REC dot
    local dot_x = x + 7
    local dot_y = y + bh / 2
    local dot_pulse = 0.5 + math.sin(t * 2 * 2 * math.pi) * 0.4
    -- Shadow glow
    love.graphics.setColor(1, 0.11, 0.11, 0.25 * dot_pulse)
    love.graphics.circle("fill", dot_x, dot_y, 5)
    -- Main dot
    love.graphics.setColor(1, 0.11, 0.11, dot_pulse)
    love.graphics.circle("fill", dot_x, dot_y, 3)

    if TG and TG.Phosphor then
        -- "CH3" text
        local ch_x = x + 16
        local ch_y = y + 4
        TG.Phosphor.draw("CH3", ch_x, ch_y, { 1, 1, 1 }, 0.3, 7)

        -- Timecode
        local sec  = math.floor(t % 60)
        local frm  = math.floor((t * 17) % 60)
        local min_ = math.floor(t / 60) % 60
        local tc   = string.format("%02d:%02d:%02d", min_, sec, frm)
        TG.Phosphor.draw(tc, x + 16, y + 12, { 1.0, 0.784, 0.196 }, 0.0, 7, 0.50)
    end

    -- Signal bar
    local sb_x = x + 4
    local sb_y = y + bh - 4
    local sb_w = bw - 8
    love.graphics.setColor(0.1, 0.1, 0.1, 0.6)
    love.graphics.rectangle("fill", sb_x, sb_y, sb_w, 3)
    local scan_phase = (t * 0.4) % 1.0
    local scan_x = sb_x + scan_phase * sb_w
    local scan_w = sb_w * 0.3
    love.graphics.setColor(0.9, 0.9, 0.9, 0.5)
    love.graphics.rectangle("fill", math.min(scan_x, sb_x + sb_w - scan_w), sb_y, scan_w, 3)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

-- ============================================================
-- PUBLIC API
-- ============================================================

function Atm.init()
    _gradient_mesh = build_gradient_mesh()
    _sun_canvas    = build_sun_canvas()
end

function Atm.on_board_switch(new_id)
    local col = BOARD_UI_COLORS[new_id]
    if col then
        _wash_target  = col
        _wash_lerp    = 0.0
    end
end

function Atm.update(dt)
    _time = _time + dt

    -- Update gradient mesh colors
    update_gradient_mesh(_time)

    -- Lerp wash color toward target over ~500ms (30 frames at dt≈0.016)
    if _wash_lerp < 1.0 then
        _wash_lerp    = math.min(1.0, _wash_lerp + dt * 2.0)
        _wash_current = lerp_color(_wash_current, _wash_target, _wash_lerp)
    end

    -- Sync wash to current active board if not animating
    if _wash_lerp >= 1.0 and TG and TG.active_board_id then
        local col = BOARD_UI_COLORS[TG.active_board_id]
        if col then
            _wash_current = col
            _wash_target  = col
        end
    end
end

function Atm.draw()
    local w, h = love.graphics.getDimensions()

    -- 1. Sunset gradient
    if _gradient_mesh then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(_gradient_mesh)
    else
        -- Fallback flat color
        love.graphics.setColor(0.06, 0.03, 0.12, 0.85)
        love.graphics.rectangle("fill", 0, 0, w, h)
    end

    -- 2. Sun + venetian blinds
    draw_sun(_time)

    -- 3. Grid
    draw_grid(_time, active_board_color())

    -- 4. Color wash
    draw_wash(_time)

    -- 5. VHS bars
    draw_vhs(_time)

    -- 6. Scanlines + vignette: deferred to tg_shader.lua
    --    (Atm does NOT re-implement if shader handles it)

    -- 7. Channel badge
    draw_channel_badge(_time)
end

return Atm
