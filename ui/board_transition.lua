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
        duration = 0.55,
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

local function draw_switch(tr)
    if not TG or not TG.Phosphor then return end

    local p  = tr.progress
    local w, h = love.graphics.getDimensions()
    local bc = BOARD_UI_COLORS[tr.to_id] or { 1, 1, 1 }

    -- ── Phase 1: Snap (0.0–0.09) ──
    if p < 0.09 then
        local flash_alpha = (1 - p / 0.09) * 0.25
        love.graphics.setColor(bc[1], bc[2], bc[3], flash_alpha)
        love.graphics.rectangle("fill", 0, 0, w, h)
    end

    -- ── VHS tracking bands ──────────────────────────────────
    local band_intensity
    if p < 0.09 then
        band_intensity = 1.0
    elseif p < 0.35 then
        band_intensity = 1.0
    else
        band_intensity = power_decay((p - 0.35) / 0.65, 1.5)
    end

    if band_intensity > 0.01 then
        for _, band in ipairs(tr.bands) do
            local by = (band.y / 100) * h
            local bh = band.height
            local bx = band.offset * band_intensity

            -- Main white
            love.graphics.setColor(1, 1, 1, 0.35 * band_intensity)
            love.graphics.rectangle("fill", bx, by, w, bh)
            -- Red ghost
            love.graphics.setColor(1, 0.392, 0.588, 0.12 * band_intensity)
            love.graphics.rectangle("fill", bx + 4, by, w, bh)
            -- Blue ghost
            love.graphics.setColor(0.235, 0.627, 1.0, 0.10 * band_intensity)
            love.graphics.rectangle("fill", bx - 4, by, w, bh)
        end
    end

    -- ── Edge glow lines ──────────────────────────────────────
    local edge_intensity
    if p < 0.09 then
        edge_intensity = 1.0
    elseif p < 0.35 then
        edge_intensity = 1.0
    else
        edge_intensity = power_decay((p - 0.35) / 0.65, 2.0)
    end

    if edge_intensity > 0.01 then
        local edge_h = math.max(1, 4 * edge_intensity)
        love.graphics.setBlendMode("add")
        love.graphics.setColor(bc[1], bc[2], bc[3], edge_intensity * 0.8)
        love.graphics.rectangle("fill", 0, 0,          w, edge_h)
        love.graphics.rectangle("fill", 0, h - edge_h, w, edge_h)
        love.graphics.setBlendMode("alpha")
    end

    -- ── Label chyron (Phase 2: 0.09–0.35) ───────────────────
    local chyron_visible
    if p < 0.09 then
        chyron_visible = 0
    elseif p < 0.35 then
        chyron_visible = (p - 0.09) / 0.26
    else
        chyron_visible = power_decay((p - 0.35) / 0.65, 1.8)
    end

    if chyron_visible > 0.02 then
        local scale  = h / 540   -- same baseline as all other UI files

        local chyron_h = math.floor(73 * scale)   -- ~120px — matches status bar height
        local font_sz  = math.floor(38 * scale)   -- ~63px — big readable label
        local accent_w = math.floor(7  * scale)   -- ~12px
        local pad      = math.floor(6  * scale)   -- ~10px

        -- Entrance: slide in from left
        local entrance_progress = math.min(1.0, chyron_visible * 1.5)
        local margin_frac       = (1 - entrance_progress) * -0.5
        local chyron_x          = math.floor(margin_frac * w)
        local chyron_y          = math.floor(h * 0.38)
        local chyron_w          = math.floor(w * 0.55)

        -- Background gradient (solid left 60%, fades right)
        local solid_w = math.floor(chyron_w * 0.60)
        local fade_w  = chyron_w - solid_w
        local steps   = 10
        love.graphics.setColor(0.020, 0.008, 0.055, 0.92 * chyron_visible)
        love.graphics.rectangle("fill", chyron_x, chyron_y, solid_w, chyron_h)
        for i = 1, steps do
            local frac = 1 - (i / steps)
            love.graphics.setColor(0.020, 0.008, 0.055, 0.92 * frac * chyron_visible)
            love.graphics.rectangle("fill",
                chyron_x + solid_w + (i - 1) * (fade_w / steps), chyron_y,
                fade_w / steps + 1, chyron_h)
        end

        -- Left accent bar + bloom
        love.graphics.setBlendMode("add")
        love.graphics.setColor(bc[1], bc[2], bc[3], 0.5 * chyron_visible)
        love.graphics.rectangle("fill", chyron_x, chyron_y, accent_w * 5, chyron_h)
        love.graphics.setBlendMode("alpha")
        love.graphics.setColor(bc[1], bc[2], bc[3], chyron_visible)
        love.graphics.rectangle("fill", chyron_x, chyron_y, accent_w, chyron_h)

        local label  = "BOARD " .. (tr.to_id or "?")
        local text_x = chyron_x + accent_w + pad * 2
        local text_y = chyron_y + math.floor((chyron_h - TG.Phosphor.height("serif", font_sz)) * 0.5)

        local label_glow = 2.4 * chyron_visible
        TG.Phosphor.draw(label, text_x, text_y, bc, label_glow, "serif", font_sz, chyron_visible)
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
