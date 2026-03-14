--[[
    TRIPLE GAMBIT - ui/tg_shader.lua
    Post-processing pipeline for TG's UI overlay.

    Renders all TG UI to an offscreen canvas, then applies:
    1. Chromatic aberration (Apple waterdrop style — R/G/B channel displacement
       that radiates from center, stronger at edges)
    2. CRT scanlines — industrial horizontal banding
    3. Barrel lens distortion — subtle curve like looking through glass/water
    4. Vignette — edge darkening for depth

    This gives TG its own visual identity independent of Balatro's render
    pipeline, so our overlays get the CRT/industrial treatment.
]]

TG    = TG or {}
TG.UI = TG.UI or {}
TG.UI.Shader = {}

local S = TG.UI.Shader

S._canvas            = nil
S._shader            = nil
S._time              = 0
S._aberration        = 0.0015  -- base chromatic aberration (subtle)
S._aberration_target = 0.0015
S._aberration_rate   = 3.0
S._scanline_alpha    = 0.045
S._active            = false
S._initialized       = false

-- ============================================================
-- SHADER SOURCE (GLSL)
-- ============================================================

local SHADER_SRC = [[
extern float aberration;
extern float time;
extern float scanline_alpha;
extern vec2 resolution;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords) {
    // ── Barrel distortion (waterdrop lens) ──
    vec2 center = uv - 0.5;
    float r2 = dot(center, center);
    float distort = 1.0 + r2 * 0.08;  // subtle barrel
    vec2 duv = center * distort + 0.5;

    // Clamp to valid range
    duv = clamp(duv, 0.0, 1.0);

    // ── Chromatic aberration (radial, Apple-style) ──
    // Displacement scales with distance from center (waterdrop effect)
    float ab = aberration * (1.0 + r2 * 8.0);
    // Add subtle time-based drift (industrial hum)
    ab *= (1.0 + 0.15 * sin(time * 2.3));

    vec2 dir = normalize(center + 0.001);
    float r = Texel(tex, duv + dir * ab).r;
    float g = Texel(tex, duv).g;
    float b = Texel(tex, duv - dir * ab).b;
    float a = Texel(tex, duv).a;

    // Take max alpha from all channels so nothing disappears
    a = max(a, max(Texel(tex, duv + dir * ab).a,
                   Texel(tex, duv - dir * ab).a));

    vec4 col = vec4(r, g, b, a);

    // ── Scanlines (industrial CRT) ──
    float line_pos = screen_coords.y;
    float scanline = 1.0 - scanline_alpha * (0.5 + 0.5 * sin(line_pos * 3.14159));
    col.rgb *= scanline;

    // ── Sub-pixel horizontal banding (every 3rd pixel row, very subtle) ──
    float subpx = 1.0 - 0.02 * step(0.66, fract(screen_coords.y / 3.0));
    col.rgb *= subpx;

    // ── Vignette (industrial edge darkening) ──
    float vig = 1.0 - dot(center, center) * 0.4;
    col.rgb *= clamp(vig, 0.55, 1.0);

    return col * color;
}
]]

-- ============================================================
-- INIT
-- ============================================================

function S.init()
    local ok, shader = pcall(love.graphics.newShader, SHADER_SRC)
    if ok and shader then
        S._shader      = shader
        S._initialized = true
        print("[TG] Shader: chromatic aberration + CRT + barrel distortion initialized")
    else
        print("[TG] Shader: compile failed (" .. tostring(shader) .. "), falling back to direct draw")
        S._initialized = false
    end
end

-- ============================================================
-- CANVAS
-- ============================================================

local function ensure_canvas()
    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()
    if not S._canvas or S._canvas:getWidth() ~= sw or S._canvas:getHeight() ~= sh then
        S._canvas = love.graphics.newCanvas(sw, sh)
    end
end

-- ============================================================
-- RENDER PASS
-- ============================================================

function S.begin_pass()
    if not S._initialized then return end
    ensure_canvas()
    S._active = true
    love.graphics.setCanvas(S._canvas)
    love.graphics.clear(0, 0, 0, 0)
end

function S.end_pass()
    if not S._active then return end
    S._active = false
    love.graphics.setCanvas()

    if S._shader then
        local sw = love.graphics.getWidth()
        local sh = love.graphics.getHeight()
        love.graphics.setShader(S._shader)
        S._shader:send("aberration", S._aberration)
        S._shader:send("time", S._time)
        S._shader:send("scanline_alpha", S._scanline_alpha)
        pcall(function() S._shader:send("resolution", {sw, sh}) end)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(S._canvas, 0, 0)
        love.graphics.setShader()
    else
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(S._canvas, 0, 0)
    end
end

-- ============================================================
-- UPDATE
-- ============================================================

function S.update(dt)
    S._time = S._time + dt
    if S._aberration > S._aberration_target then
        S._aberration = S._aberration - S._aberration_rate * dt
        if S._aberration < S._aberration_target then
            S._aberration = S._aberration_target
        end
    end
end

-- ============================================================
-- ABERRATION SPIKE
-- ============================================================

function S.spike_aberration(amount, duration_factor)
    S._aberration = math.min(0.025, (amount or 0.008))
    S._aberration_rate = duration_factor and (3.0 / duration_factor) or 3.0
end

return S
