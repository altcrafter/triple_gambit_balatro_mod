--[[
    TRIPLE GAMBIT - ui/debug_overlay.lua
    Coordinate/layout debug tool.  Press ` (backtick) to toggle.

    Shows:
      · Faint grid lines at every 10% of screen (both axes)
      · Yellow crosshair tracking the mouse
      · Coordinate readout:  pixel X, Y  +  sw×factor  sh×factor
        (factor values map directly to love.graphics code, e.g. sh*0.42)
      · Screen dimensions pinned to top-right corner
      · Toggle hint pinned to top-left corner
]]

local _on = false

-- ── Self-install: keypressed ──────────────────────────────────
local _prev_kp = love.keypressed
function love.keypressed(key, scancode, isrepeat)
    if key == "`" then _on = not _on end
    if _prev_kp then _prev_kp(key, scancode, isrepeat) end
end

-- ── Self-install: draw  (chains after TG.Hooks.draw — always on top) ──
local _prev_draw = love.draw
function love.draw()
    _prev_draw()
    if not _on then return end

    local sw, sh = love.graphics.getDimensions()
    local mx, my = love.mouse.getPosition()
    local font   = love.graphics.getFont()
    local lh     = font:getHeight()
    local pad    = 5

    love.graphics.push("all")
    love.graphics.setLineWidth(1)

    -- ── Grid: lines every 10% ────────────────────────────────
    for i = 1, 9 do
        local gx = math.floor(sw * i / 10)
        local gy = math.floor(sh * i / 10)

        love.graphics.setColor(1, 1, 1, 0.07)
        love.graphics.line(gx, 0, gx, sh)
        love.graphics.line(0, gy, sw, gy)

        -- percentage labels along the edges
        love.graphics.setColor(1, 1, 1, 0.28)
        love.graphics.print(tostring(i * 10) .. "%", gx + 3, 3)
        love.graphics.print(tostring(i * 10) .. "%", 3, gy + 3)
    end

    -- ── Crosshair ────────────────────────────────────────────
    love.graphics.setColor(1, 1, 0, 0.75)
    love.graphics.line(mx - 18, my, mx + 18, my)
    love.graphics.line(mx, my - 18, mx, my + 18)
    love.graphics.circle("line", mx, my, 4)

    -- ── Coordinate label ─────────────────────────────────────
    -- Format: "1024, 320   sw×0.750  sh×0.417"
    -- sw× and sh× values paste directly into BACON code as e.g. sh * 0.417
    local label = string.format("%d, %d     sw\xc3\x970.%03d   sh\xc3\x970.%03d",
        mx, my,
        math.floor(mx / sw * 1000 + 0.5),
        math.floor(my / sh * 1000 + 0.5))
    local lw = font:getWidth(label)

    -- Position: right of cursor, flip left if near edge
    local lx = mx + 22
    local ly = my - lh - pad - 2
    if lx + lw + pad * 2 > sw - 4 then lx = mx - lw - 22 - pad * 2 end
    if ly < 0                       then ly = my + 16 end

    love.graphics.setColor(0, 0, 0, 0.82)
    love.graphics.rectangle("fill", lx - pad, ly - pad,
                             lw + pad * 2, lh + pad * 2, 3, 3)
    love.graphics.setColor(1, 1, 0.3, 1)
    love.graphics.print(label, lx, ly)

    -- ── Screen dimensions (top-right) ────────────────────────
    local dim = string.format(" %d \xc3\x97 %d ", sw, sh)
    local dw  = font:getWidth(dim)
    love.graphics.setColor(0, 0, 0, 0.82)
    love.graphics.rectangle("fill", sw - dw - pad, 0,
                             dw + pad, lh + pad * 2, 3, 3)
    love.graphics.setColor(0.5, 1, 0.5, 1)
    love.graphics.print(dim, sw - dw - pad + 2, pad)

    -- ── Toggle hint (top-left) ────────────────────────────────
    local hint   = "  DEBUG [`]  "
    local hw     = font:getWidth(hint)
    love.graphics.setColor(0, 0, 0, 0.82)
    love.graphics.rectangle("fill", 0, 0, hw + pad, lh + pad * 2, 3, 3)
    love.graphics.setColor(1, 0.45, 0.45, 1)
    love.graphics.print(hint, pad, pad)

    love.graphics.pop()
end

return {}
