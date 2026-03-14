--[[
    TRIPLE GAMBIT - ui/tg_shader.lua
    CRT post-processing: scanlines + vignette.
    API: Shader.init(), Shader.begin_pass(), Shader.end_pass()
    atmosphere.lua defers scanlines/vignette to this module.

    If the shader fails to compile (driver issue, old GPU), falls back to
    software scanlines + vignette drawn directly with love.graphics.
]]

local Shader = {}

Shader._canvas  = nil
Shader._shader  = nil
Shader._ok      = false

-- ============================================================
-- GLSL SOURCE
-- ============================================================

local GLSL_SRC = [[
extern vec2 screen_size;
extern float time;
extern float scanline_alpha;   // 0.0 = off, 1.0 = full
extern float vignette_alpha;   // 0.0 = off, 1.0 = full

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec4 pixel = Texel(tex, texture_coords);

    // Scanlines: darken even rows slightly
    float line = mod(floor(screen_coords.y), 2.0);
    float scan = 1.0 - line * 0.04 * scanline_alpha;
    pixel.rgb *= scan;

    // Vignette: radial falloff from center
    vec2 uv = texture_coords * 2.0 - 1.0;
    float dist = length(uv);
    float vig = 1.0 - smoothstep(0.45, 1.2, dist) * 0.55 * vignette_alpha;
    pixel.rgb *= vig;

    return pixel * color;
}
]]

-- ============================================================
-- INIT
-- ============================================================

function Shader.init()
    -- Create render canvas matching screen size
    local w, h = love.graphics.getDimensions()
    local ok_canvas, canvas = pcall(love.graphics.newCanvas, w, h)
    if not ok_canvas then
        Shader._ok = false
        return
    end
    Shader._canvas = canvas

    -- Compile shader
    local ok_shader, shader = pcall(love.graphics.newShader, GLSL_SRC)
    if ok_shader and shader then
        Shader._shader = shader
        -- Set uniforms
        if shader:hasUniform("screen_size") then
            shader:send("screen_size", { w, h })
        end
        if shader:hasUniform("scanline_alpha") then
            shader:send("scanline_alpha", 1.0)
        end
        if shader:hasUniform("vignette_alpha") then
            shader:send("vignette_alpha", 1.0)
        end
        if shader:hasUniform("time") then
            shader:send("time", 0.0)
        end
        Shader._ok = true
    else
        -- Shader compile failed; use software fallback
        Shader._ok = false
    end
end

-- ============================================================
-- PASS API
-- ============================================================

-- Call at the START of TG.Hooks.draw() — redirects rendering to canvas
function Shader.begin_pass()
    if not Shader._ok or not Shader._canvas then return end
    -- Resize canvas if screen changed
    local w, h = love.graphics.getDimensions()
    local cw   = Shader._canvas:getWidth()
    local ch   = Shader._canvas:getHeight()
    if cw ~= w or ch ~= h then
        local ok, nc = pcall(love.graphics.newCanvas, w, h)
        if ok then Shader._canvas = nc end
        if Shader._shader and Shader._shader:hasUniform("screen_size") then
            Shader._shader:send("screen_size", { w, h })
        end
    end

    love.graphics.setCanvas(Shader._canvas)
    love.graphics.clear(0, 0, 0, 0)
end

-- Call at the END of TG.Hooks.draw() — applies shader and draws to screen
function Shader.end_pass()
    if not Shader._ok or not Shader._canvas then
        -- Software fallback: just draw scanlines + vignette
        Shader._draw_software()
        return
    end

    love.graphics.setCanvas()  -- back to screen

    if Shader._shader then
        -- Update time uniform if present
        if Shader._shader:hasUniform("time") then
            Shader._shader:send("time", love.timer.getTime())
        end
        love.graphics.setShader(Shader._shader)
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(Shader._canvas, 0, 0)

    love.graphics.setShader()
end

-- ============================================================
-- SOFTWARE FALLBACK
-- ============================================================

function Shader._draw_software()
    local w, h = love.graphics.getDimensions()

    -- Scanlines: 1px lines every 4px at 4% black
    love.graphics.setColor(0, 0, 0, 0.04)
    for y = 0, h, 4 do
        love.graphics.rectangle("fill", 0, y, w, 1)
    end

    -- Vignette: concentric dark rectangles from edges inward
    local steps = 12
    for i = 1, steps do
        local frac  = i / steps
        local alpha = (1 - frac) * (1 - frac) * 0.45
        love.graphics.setColor(0, 0, 0, alpha)
        local inset = (i - 1) * (math.min(w, h) * 0.04)
        love.graphics.rectangle("line",
            inset, inset,
            w - inset * 2, h - inset * 2)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- ============================================================
-- UPDATE (called every frame from TG.Hooks.update)
-- ============================================================

function Shader.update(dt)
    if Shader._shader and Shader._shader:hasUniform("time") then
        Shader._shader:send("time", love.timer.getTime())
    end
end

-- ============================================================
-- ACCESSORS
-- ============================================================

function Shader.is_active()
    return Shader._ok
end

return Shader
