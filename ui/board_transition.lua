--[[
    TRIPLE GAMBIT - ui/board_transition.lua
    REWRITE. Two transition types:
      - switch: 550ms channel-change effect
      - clear:  800ms board-clear celebration
    Kara calls trigger_switch() and trigger_cleared() from hooks.
]]

local BT = {}

BT._active = nil  -- current transition, or nil

local BOARD_UI_COLORS = {
    A = { 1.0,   0.176, 0.42  },
    B = { 0.0,   0.898, 1.0   },
    C = { 1.0,   0.667, 0.133 },
    D = { 0.706, 0.302, 1.0   },
}

local BOARD_NAMES = {
    A = "APEX",
    B = "BLAZE",
    C = "CHROME",
    D = "DRIFT",
}

-- ============================================================
-- TRIGGER POINTS (Kara calls these)
-- ============================================================

function BT.trigger_switch(from_id, to_id)
    -- Generate random VHS bands
    local bands = {}
    local n = 3 + math.floor(math.random() * 6)  -- 3–8
    for i = 1, n do
        table.insert(bands, {
            y       = math.random() * 100,  -- % of screen
            height  = 1 + math.random() * 9,
            offset  = (math.random() * 120) - 60,
        })
    end

    BT._active = {
        type     = "switch",
        from_id  = from_id,
        to_id    = to_id,
        progress = 0.0,
        duration = 0.65,
        bands    = bands,
    }
end

function BT.trigger_cleared(board_id)
    BT._active = {
        type     = "clear",
        board_id = board_id,
        progress = 0.0,
        duration = 0.80,
    }
end

-- ============================================================
-- UPDATE
-- ============================================================

function BT.update(dt)
    if not BT._active then return end
    BT._active.progress = BT._active.progress + dt / BT._active.duration
    if BT._active.progress >= 1.0 then
        BT._active = nil
    end
end

-- ============================================================
-- DRAW HELPERS
-- ============================================================

local function power_decay(x, power)
    -- (1 - x) ^ power, x in 0–1 → 1 at x=0, 0 at x=1
    return (1 - math.min(1, x)) ^ power
end

local function smoothstep(t)
    t = math.max(0, math.min(1, t))
    return t * t * (3 - 2 * t)
end

local function draw_switch(tr)
    if not TG or not TG.Phosphor then return end

    local p      = tr.progress
    local sw, h  = love.graphics.getDimensions()
    local bc     = BOARD_UI_COLORS[tr.to_id] or { 1, 1, 1 }
    local scale  = h / 540

    -- ── Phase 0: Full-screen launch flash + white center burst (0.0–0.07) ──
    if p < 0.07 then
        local t      = p / 0.07
        local board_a = (1 - t) * 0.55
        love.graphics.setColor(bc[1], bc[2], bc[3], board_a)
        love.graphics.rectangle("fill", 0, 0, sw, h)

        local burst_a = (1 - t) * 0.70
        love.graphics.setBlendMode("add")
        love.graphics.setColor(1, 1, 1, burst_a)
        love.graphics.rectangle("fill", sw * 0.3, h * 0.3, sw * 0.4, h * 0.4)
        love.graphics.setBlendMode("alpha")
    end

    -- ── Phase 1: Speed streaks (0.03–0.55) ──────────────────────────────
    if p >= 0.03 and p < 0.55 then
        local t          = (p - 0.03) / 0.52
        local intensity  = t < 0.5 and (t / 0.5) or power_decay((t - 0.5) / 0.5, 1.5)
        local vanish_x   = math.floor(sw * 0.08)   -- left vanishing point

        if intensity > 0.01 then
            for _, band in ipairs(tr.bands) do
                local by  = (band.y / 100) * h
                local bth = math.max(1, band.height * scale)
                -- Each streak starts at vanishing point, fans out right
                local spread = intensity * (sw - vanish_x)
                love.graphics.setColor(bc[1], bc[2], bc[3], 0.45 * intensity)
                love.graphics.rectangle("fill", vanish_x, by, spread, bth)
                -- Bright core
                local core_h = math.max(1, math.floor(bth * 0.4))
                love.graphics.setBlendMode("add")
                love.graphics.setColor(bc[1], bc[2], bc[3], 0.30 * intensity)
                love.graphics.rectangle("fill", vanish_x, by + math.floor((bth - core_h) * 0.5),
                                        spread, core_h)
                love.graphics.setBlendMode("alpha")
            end
        end
    end

    -- ── Phase 2: Brand plate sweep (0.05–0.78) ──────────────────────────
    if p >= 0.05 and p < 0.78 then
        local plate_h   = math.floor(80 * scale)
        local font_sz   = math.floor(38 * scale)
        local accent_w  = math.floor(8  * scale)
        local pad       = math.floor(6  * scale)

        local brand     = BOARD_NAMES[tr.to_id] or ("BOARD " .. (tr.to_id or "?"))
        local text_w    = TG.Phosphor.width(brand, "mono", font_sz)
        local plate_w   = accent_w + pad * 3 + text_w + pad * 3
        local plate_y   = math.floor(h * 0.40)
        local rest_x    = math.floor(sw * 0.05)

        -- Plate x position: enter from right, hold, exit left
        local plate_x
        if p < 0.20 then
            local t = smoothstep((p - 0.05) / 0.15)
            plate_x = math.floor(sw + (rest_x - sw) * t)
        elseif p < 0.55 then
            plate_x = rest_x
        else
            local t = smoothstep((p - 0.55) / 0.23)
            plate_x = math.floor(rest_x + (-(plate_w + math.floor(sw * 0.05)) - rest_x) * t)
        end

        -- Plate alpha (fade in fast, hold full, fade out near exit)
        local plate_a
        if p < 0.10 then
            plate_a = (p - 0.05) / 0.05
        elseif p < 0.65 then
            plate_a = 1.0
        else
            plate_a = 1.0 - (p - 0.65) / 0.13
        end
        plate_a = math.max(0, math.min(1, plate_a))

        -- Tilt transform
        local pivot_cx = plate_x + plate_w * 0.5
        local pivot_cy = plate_y + plate_h * 0.5
        love.graphics.push()
        love.graphics.translate(pivot_cx, pivot_cy)
        love.graphics.rotate(math.rad(-1.5))
        love.graphics.translate(-pivot_cx, -pivot_cy)

        -- Dark panel background
        love.graphics.setColor(0.014, 0.006, 0.040, 0.93 * plate_a)
        love.graphics.rectangle("fill", plate_x, plate_y, plate_w, plate_h)

        -- Left accent bar + bloom
        love.graphics.setBlendMode("add")
        love.graphics.setColor(bc[1], bc[2], bc[3], 0.45 * plate_a)
        love.graphics.rectangle("fill", plate_x, plate_y, accent_w * 5, plate_h)
        love.graphics.setBlendMode("alpha")
        love.graphics.setColor(bc[1], bc[2], bc[3], plate_a)
        love.graphics.rectangle("fill", plate_x, plate_y, accent_w, plate_h)

        -- Brand name text
        local text_x  = plate_x + accent_w + pad * 2
        local text_y  = plate_y + math.floor((plate_h - TG.Phosphor.height("mono", font_sz)) * 0.5)
        local lbl_glow = 2.4 * plate_a
        TG.Phosphor.draw(brand, text_x, text_y, bc, lbl_glow, "mono", font_sz, plate_a)

        love.graphics.pop()
    end

    -- ── Phase 3: Edge frame glow (0.0–0.40) ─────────────────────────────
    if p < 0.40 then
        local edge_a = power_decay(p / 0.40, 1.5) * 0.85
        if edge_a > 0.01 then
            local edge_th = math.max(2, math.floor(5 * scale * edge_a))
            love.graphics.setBlendMode("add")
            love.graphics.setColor(bc[1], bc[2], bc[3], edge_a)
            -- Top
            love.graphics.rectangle("fill", 0, 0, sw, edge_th)
            -- Bottom
            love.graphics.rectangle("fill", 0, h - edge_th, sw, edge_th)
            -- Left
            love.graphics.rectangle("fill", 0, 0, edge_th, h)
            -- Right
            love.graphics.rectangle("fill", sw - edge_th, 0, edge_th, h)
            love.graphics.setBlendMode("alpha")
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

local function draw_clear(tr)
    if not TG or not TG.Phosphor then return end

    local p    = tr.progress
    local w, h = love.graphics.getDimensions()
    local bc   = BOARD_UI_COLORS[tr.board_id] or BOARD_UI_COLORS.A

    -- ── Phase 1: White snap (0.0–0.05) ──
    if p < 0.125 then
        local snap_alpha
        if p < 0.05 then
            snap_alpha = (1 - p / 0.05) * 0.9
        else
            snap_alpha = math.max(0, 1 - (p - 0.05) / 0.075) * 0.5
        end
        if snap_alpha > 0 then
            love.graphics.setColor(1, 1, 1, snap_alpha)
            love.graphics.rectangle("fill", 0, 0, w, h)
        end
    end

    -- ── Phase 3: Color bloom (0.05–0.375) ──
    if p >= 0.05 and p < 0.375 then
        local t2    = (p - 0.05) / 0.325
        local bloom = math.min(0.35, t2 * 0.35 * 2 - math.max(0, t2 * 0.35 * 2 - 0.35))
        love.graphics.setColor(bc[1], bc[2], bc[3], bloom)
        love.graphics.rectangle("fill", 0, 0, w, h)

        -- Edge frame during color bloom
        local border_a = bloom * 1.5
        love.graphics.setBlendMode("add")
        love.graphics.setColor(bc[1], bc[2], bc[3], border_a)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", 1, 1, w - 2, h - 2)
        love.graphics.setBlendMode("alpha")
        love.graphics.setLineWidth(1)
    end

    -- ── Phase 4: Stamp (0.1–0.25) ──
    if p >= 0.1 and p < 1.0 then
        local stamp_i
        if p < 0.2 then
            stamp_i = (p - 0.1) / 0.1
        elseif p < 0.25 then
            stamp_i = 1.0
        else
            stamp_i = power_decay((p - 0.25) / 0.75, 1.5)
        end

        if stamp_i > 0.02 then
            local scale    = h / 540
            local font_sz  = math.floor(34 * scale)   -- ~56px — legible stamp

            local label   = "BOARD " .. (tr.board_id or "?") .. "  CLEARED"
            local stamp_y = math.floor(h * 0.46)
            local lw      = TG.Phosphor.width(label, "serif", font_sz)
            local stamp_x = math.floor(w / 2 - lw / 2)

            local stamp_glow = 2.0 * stamp_i
            TG.Phosphor.draw(label, stamp_x, stamp_y,
                             { 1, 1, 1 }, stamp_glow, "serif", font_sz, stamp_i, math.rad(-1.5))
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- ============================================================
-- PUBLIC DRAW
-- ============================================================

function BT.draw()
    if not BT._active then return end
    if BT._active.type == "switch" then
        draw_switch(BT._active)
    elseif BT._active.type == "clear" then
        draw_clear(BT._active)
    end
end

function BT.is_active()
    return BT._active ~= nil
end

return BT
