--[[
    TRIPLE GAMBIT - ui/gambit_chip_ui.lua

    ╔══════════════════════════════════════════════════════════╗
    ║  CHIP MANIFEST                                          ║
    ║                                                          ║
    ║  A visual designer buried two plants and three           ║
    ║  lightbulbs sprung from the loam.                        ║
    ║                                                          ║
    ║  The earth is solid and musty.                            ║
    ║  The wind moves like little lights.                      ║
    ║  Information reveals itself through warm glow.           ║
    ║                                                          ║
    ║  ZONES (same structure, new material):                   ║
    ║    Header     → title pressed into dark soil             ║
    ║    Tier       → three coins half-buried                  ║
    ║    Stack      → chips stacked in an earthen cradle       ║
    ║    Stats      → numbers glowing from beneath             ║
    ║    History    → entries like pressed leaves               ║
    ║    Footer     → drifting motes of light                  ║
    ╚══════════════════════════════════════════════════════════╝
]]

TG    = TG or {}
TG.UI = TG.UI or {}
TG.UI.ChipStackUI = {}

local CSU = TG.UI.ChipStackUI

-- ============================================================
-- WIND ENGINE (ambient, not rhythmic)
-- ============================================================
--
-- No beat. Just time passing. Wind speed.
-- Everything moves at the pace of breath.

local WIND = {
    _time = 0,
    _motes = {},     -- drifting light particles
    _max_motes = 6,  -- sparse, not distracting
}

function WIND.update(dt)
    WIND._time = WIND._time + dt

    -- Spawn motes occasionally
    if #WIND._motes < WIND._max_motes and math.random() < dt * 0.4 then
        table.insert(WIND._motes, {
            x     = math.random() * 0.8 + 0.1,  -- normalized 0-1
            y     = 0.95 + math.random() * 0.1,  -- start near bottom
            vx    = (math.random() - 0.5) * 0.015,
            vy    = -(0.02 + math.random() * 0.03), -- drift upward
            size  = 0.8 + math.random() * 1.2,
            alpha = 0,
            alpha_target = 0.15 + math.random() * 0.25,
            life  = 0,
            max_life = 4.0 + math.random() * 6.0,  -- 4-10 seconds
            -- Warm white to soft amber
            r = 0.95 + math.random() * 0.05,
            g = 0.85 + math.random() * 0.10,
            b = 0.65 + math.random() * 0.15,
        })
    end

    -- Update motes
    for i = #WIND._motes, 1, -1 do
        local m = WIND._motes[i]
        m.life = m.life + dt
        m.x = m.x + m.vx * dt
        m.y = m.y + m.vy * dt

        -- Gentle sine drift (wind)
        m.x = m.x + math.sin(WIND._time * 0.7 + m.life * 1.3) * 0.002 * dt

        -- Fade in, hold, fade out
        local life_pct = m.life / m.max_life
        if life_pct < 0.15 then
            m.alpha = m.alpha_target * (life_pct / 0.15)
        elseif life_pct > 0.7 then
            m.alpha = m.alpha_target * (1.0 - (life_pct - 0.7) / 0.3)
        else
            m.alpha = m.alpha_target
        end

        -- Remove if dead or out of bounds
        if m.life >= m.max_life or m.y < -0.1 or m.x < -0.1 or m.x > 1.1 then
            table.remove(WIND._motes, i)
        end
    end
end

--- A slow sine that breathes, not pulses
function WIND.breath(offset)
    return math.sin((WIND._time + (offset or 0)) * 0.4) * 0.5 + 0.5
end

-- ============================================================
-- EARTH PALETTE
-- ============================================================
--
-- Dark loam, warm light, muted metals.
-- Text glows from beneath like bioluminescence.

local EARTH = {
    -- Ground layers
    loam_deep  = { 0.065, 0.055, 0.048 },  -- deepest soil
    loam       = { 0.085, 0.072, 0.062 },  -- main panel
    loam_light = { 0.105, 0.090, 0.075 },  -- raised areas
    root       = { 0.055, 0.048, 0.042 },  -- divider lines (like roots)
    root_light = { 0.14,  0.12,  0.10  },  -- root highlight

    -- Light (emerging from earth)
    glow_warm  = { 0.95, 0.82, 0.55 },  -- warm amber light
    glow_soft  = { 0.90, 0.85, 0.72 },  -- softer, reading light
    glow_dim   = { 0.60, 0.55, 0.45 },  -- labels, quiet
    glow_faint = { 0.40, 0.36, 0.30 },  -- barely there

    -- Semantic
    growth     = { 0.45, 0.72, 0.42 },  -- profit, success (moss green)
    wilt       = { 0.72, 0.38, 0.32 },  -- loss, failure (dried clay)
    neutral    = { 0.78, 0.70, 0.45 },  -- amber/honey

    -- Chromatic fringe (the rainbow bleed from the screenshot)
    fringe_r   = { 0.85, 0.25, 0.20 },
    fringe_g   = { 0.25, 0.80, 0.35 },
    fringe_b   = { 0.20, 0.30, 0.85 },

    -- Chip metals (weathered, found-in-earth)
    copper     = { 0.72, 0.48, 0.28 },
    copper_hi  = { 0.82, 0.58, 0.38 },
    copper_lo  = { 0.48, 0.30, 0.16 },
    silver     = { 0.68, 0.68, 0.72 },
    silver_hi  = { 0.80, 0.80, 0.85 },
    silver_lo  = { 0.45, 0.45, 0.50 },
    gold       = { 0.88, 0.72, 0.22 },
    gold_hi    = { 0.95, 0.82, 0.40 },
    gold_lo    = { 0.58, 0.45, 0.12 },
}

local TIER_MAT = {
    copper = { base = EARTH.copper, hi = EARTH.copper_hi, lo = EARTH.copper_lo },
    silver = { base = EARTH.silver, hi = EARTH.silver_hi, lo = EARTH.silver_lo },
    gold   = { base = EARTH.gold,   hi = EARTH.gold_hi,   lo = EARTH.gold_lo   },
}

-- ============================================================
-- LAYOUT (same zones, organic proportions)
-- ============================================================

CSU.LAYOUT = {
    width     = 140,
    margin_r  = 5,
    top_y     = 155,

    header_h  = 28,
    tier_h    = 26,
    stack_h   = 110,
    stats_h   = 56,
    history_h = 52,
    footer_h  = 18,
    root_h    = 1,     -- organic divider (thin root line)

    chip_w    = 52,
    chip_h    = 7,
    chip_gap  = 2,
    chip_r    = 2,
    max_vis   = 10,

    frag_size = 5,

    -- Chromatic fringe
    fringe_w  = 2,  -- width of color bleed at panel edges
}

-- ============================================================
-- COMPUTED PANEL
-- ============================================================

local function panel_rect(sw)
    local L  = CSU.LAYOUT
    local px = sw - L.width - L.margin_r
    local py = L.top_y
    local ph = L.header_h + L.root_h
             + L.tier_h   + L.root_h
             + L.stack_h  + L.root_h
             + L.stats_h  + L.root_h
             + L.history_h + L.root_h
             + L.footer_h
    return px, py, L.width, ph
end

-- ============================================================
-- DRAW HELPERS
-- ============================================================

--- Organic root-line divider (thin, slightly irregular)
local function draw_root(x, y, w)
    -- Main root line
    love.graphics.setColor(EARTH.root[1], EARTH.root[2], EARTH.root[3], 0.7)
    love.graphics.rectangle("fill", x, y, w, 1)
    -- Faint highlight below (light catching the edge)
    love.graphics.setColor(EARTH.root_light[1], EARTH.root_light[2], EARTH.root_light[3], 0.08)
    love.graphics.rectangle("fill", x + 4, y + 1, w - 8, 1)
end

--- Chromatic fringe at panel edges (the rainbow bleed)
local function draw_fringe(px, py, pw, ph)
    local fw = CSU.LAYOUT.fringe_w
    local breath = WIND.breath(0)
    local alpha  = 0.04 + breath * 0.03  -- very subtle

    -- Left edge: R channel bleeds outward
    love.graphics.setColor(EARTH.fringe_r[1], EARTH.fringe_r[2], EARTH.fringe_r[3], alpha)
    love.graphics.rectangle("fill", px - fw, py + 8, fw, ph - 16)

    -- Right edge: B channel bleeds outward
    love.graphics.setColor(EARTH.fringe_b[1], EARTH.fringe_b[2], EARTH.fringe_b[3], alpha * 0.8)
    love.graphics.rectangle("fill", px + pw, py + 8, fw, ph - 16)

    -- Bottom edge: G channel bleeds downward
    love.graphics.setColor(EARTH.fringe_g[1], EARTH.fringe_g[2], EARTH.fringe_g[3], alpha * 0.6)
    love.graphics.rectangle("fill", px + 12, py + ph, pw - 24, fw)
end

--- Draw drifting motes within a rectangle
local function draw_motes(px, py, pw, ph)
    for _, m in ipairs(WIND._motes) do
        local mx = px + m.x * pw
        local my = py + m.y * ph
        if mx >= px and mx <= px + pw and my >= py and my <= py + ph then
            -- Soft glow halo
            love.graphics.setColor(m.r, m.g, m.b, m.alpha * 0.3)
            love.graphics.circle("fill", mx, my, m.size * 2.5)
            -- Core
            love.graphics.setColor(m.r, m.g, m.b, m.alpha)
            love.graphics.circle("fill", mx, my, m.size)
        end
    end
end

-- ============================================================
-- MAIN DRAW
-- ============================================================

function CSU.draw()
    if not TG.initialized then return end
    if not TG.chip_stack then return end

    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()
    local L  = CSU.LAYOUT
    local px, py, pw, ph = panel_rect(sw)
    local ix = px + 8   -- inner content x
    local iw = pw - 16  -- inner content width

    -- ── CHROMATIC FRINGE (behind panel) ──
    draw_fringe(px, py, pw, ph)

    -- ── PANEL BODY (dark loam) ──
    -- Shadow for depth
    love.graphics.setColor(0, 0, 0, 0.30)
    love.graphics.rectangle("fill", px + 1, py + 1, pw, ph, 3)

    -- Main fill
    love.graphics.setColor(EARTH.loam[1], EARTH.loam[2], EARTH.loam[3], 0.94)
    love.graphics.rectangle("fill", px, py, pw, ph, 3)

    -- Subtle grain texture (vertical, like wood grain / soil layers)
    love.graphics.setColor(0, 0, 0, 0.025)
    for gx = px, px + pw, 3 do
        local h_var = math.sin(gx * 0.7) * 0.5 + 0.5
        if h_var > 0.4 then
            love.graphics.rectangle("fill", gx, py, 1, ph)
        end
    end

    -- Warm edge glow at top (light coming from above)
    love.graphics.setColor(EARTH.glow_warm[1], EARTH.glow_warm[2], EARTH.glow_warm[3], 0.03)
    love.graphics.rectangle("fill", px, py, pw, 12, 3)

    -- ── ZONE RENDERING ──
    local zy = py

    -- ▌ HEADER ▌
    CSU.draw_header(px, zy, pw, L.header_h, ix, iw)
    zy = zy + L.header_h
    draw_root(px + 6, zy, pw - 12)
    zy = zy + L.root_h

    -- ▌ TIER SUMMARY ▌
    CSU.draw_tier_summary(ix, zy, iw, L.tier_h)
    zy = zy + L.tier_h
    draw_root(px + 6, zy, pw - 12)
    zy = zy + L.root_h

    -- ▌ CHIP STACK ▌
    CSU.draw_stack(ix, zy, iw, L.stack_h)
    zy = zy + L.stack_h
    draw_root(px + 6, zy, pw - 12)
    zy = zy + L.root_h

    -- ▌ STATS ▌
    CSU.draw_stats(ix, zy, iw, L.stats_h)
    zy = zy + L.stats_h
    draw_root(px + 6, zy, pw - 12)
    zy = zy + L.root_h

    -- ▌ HISTORY ▌
    CSU.draw_history(ix, zy, iw, L.history_h)
    zy = zy + L.history_h
    draw_root(px + 6, zy, pw - 12)
    zy = zy + L.root_h

    -- ▌ FOOTER (motes drift here) ▌
    draw_motes(px, py, pw, ph)

    -- ── Panel border (very subtle, warm) ──
    love.graphics.setColor(EARTH.glow_warm[1], EARTH.glow_warm[2], EARTH.glow_warm[3], 0.06)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", px, py, pw, ph, 3)

    love.graphics.setColor(1, 1, 1, 1)
end

-- ============================================================
-- ZONE: HEADER
-- ============================================================

function CSU.draw_header(px, y, pw, h, ix, iw)
    -- Slightly darker earth for header
    love.graphics.setColor(EARTH.loam_deep[1], EARTH.loam_deep[2], EARTH.loam_deep[3], 0.5)
    love.graphics.rectangle("fill", px, y, pw, h, 3)

    -- Small quiet label
    love.graphics.setColor(EARTH.glow_faint[1], EARTH.glow_faint[2], EARTH.glow_faint[3], 0.45)
    love.graphics.print("log:011", ix, y + 2, 0, 0.38, 0.38)

    -- Title: warm light emerging from dark ground
    local breath = WIND.breath(0)
    local glow   = 0.80 + breath * 0.12
    love.graphics.setColor(
        EARTH.glow_warm[1] * glow,
        EARTH.glow_warm[2] * glow,
        EARTH.glow_warm[3] * glow, 0.90)
    love.graphics.print("chip manifest", ix, y + 12, 0, 0.58, 0.58)

    -- Count (right, quiet)
    local total = TG.chip_stack:get_chip_count() + TG.chip_stack:get_fragment_count()
    if total > 0 then
        love.graphics.setColor(EARTH.glow_dim[1], EARTH.glow_dim[2], EARTH.glow_dim[3], 0.50)
        local font = love.graphics.getFont()
        local tw   = font:getWidth(tostring(total)) * 0.50
        love.graphics.print(tostring(total), ix + iw - tw, y + 12, 0, 0.50, 0.50)
    end
end

-- ============================================================
-- ZONE: TIER SUMMARY
-- ============================================================

function CSU.draw_tier_summary(x, y, w, h)
    local cs = TG.chip_stack
    if not cs then return end

    local counts = { copper = 0, silver = 0, gold = 0 }
    for _, chip in ipairs(cs.chips) do
        counts[chip.tier or "copper"] = (counts[chip.tier or "copper"] or 0) + 1
    end

    local tiers  = { "gold", "silver", "copper" }
    local slot_w = math.floor(w / 3)

    for i, tier in ipairs(tiers) do
        local sx  = x + (i - 1) * slot_w
        local mat = TIER_MAT[tier]
        local c   = counts[tier]
        local cy  = y + 6

        -- Coin (half-buried effect: darker bottom half)
        love.graphics.setColor(0, 0, 0, 0.25)
        love.graphics.rectangle("fill", sx + 1, cy + 1, 14, 6, 2)

        love.graphics.setColor(mat.base[1], mat.base[2], mat.base[3], c > 0 and 0.85 or 0.20)
        love.graphics.rectangle("fill", sx, cy, 14, 6, 2)

        -- Soil covering bottom edge (half-buried)
        love.graphics.setColor(EARTH.loam[1], EARTH.loam[2], EARTH.loam[3], c > 0 and 0.4 or 0.6)
        love.graphics.rectangle("fill", sx, cy + 4, 14, 3, 1)

        if c > 0 then
            -- Warm highlight on top
            love.graphics.setColor(mat.hi[1], mat.hi[2], mat.hi[3], 0.25)
            love.graphics.rectangle("fill", sx + 2, cy, 10, 2, 1)
        end

        -- Count
        love.graphics.setColor(EARTH.glow_soft[1], EARTH.glow_soft[2], EARTH.glow_soft[3],
                               c > 0 and 0.85 or 0.22)
        love.graphics.print(tostring(c), sx + 17, cy, 0, 0.48, 0.48)

        -- Tier initial (very quiet)
        love.graphics.setColor(EARTH.glow_faint[1], EARTH.glow_faint[2], EARTH.glow_faint[3], 0.28)
        local initials = { gold = "g", silver = "s", copper = "c" }
        love.graphics.print(initials[tier], sx + 4, cy + 10, 0, 0.32, 0.32)
    end
end

-- ============================================================
-- ZONE: CHIP STACK
-- ============================================================

function CSU.draw_stack(x, y, w, h)
    local cs = TG.chip_stack
    if not cs then return end
    local L = CSU.LAYOUT

    -- Cradle: slightly lighter earth (recessed area)
    love.graphics.setColor(EARTH.loam_light[1], EARTH.loam_light[2], EARTH.loam_light[3], 0.30)
    love.graphics.rectangle("fill", x, y + 2, w, h - 4, 2)

    -- Inner shadow (recessed feel)
    love.graphics.setColor(0, 0, 0, 0.12)
    love.graphics.rectangle("fill", x, y + 2, w, 3, 2)

    local chips = cs.chips or {}
    local frags = cs.fragments or {}
    local center_x = x + w * 0.5

    -- ── FRAGMENTS (bottom, scattered in soil) ──
    local frag_base = y + h - 10
    for _, frag in ipairs(frags) do
        local mat = TIER_MAT[frag.tier] or TIER_MAT.copper
        local fx  = center_x + (frag.x_offset or 0) * 0.4
        local fy  = frag_base - (frag.y_offset or 0) * 0.3
        local fs  = (frag.scale or 0.6) * L.frag_size
        local fa  = (frag.alpha or 0.5) * 0.45

        love.graphics.push()
        love.graphics.translate(fx, fy)
        love.graphics.rotate(frag.rotation or 0)

        -- Fragment (broken pottery in earth)
        love.graphics.setColor(
            mat.base[1] * 0.55,
            mat.base[2] * 0.55,
            mat.base[3] * 0.55, fa)
        love.graphics.rectangle("fill", -fs * 0.5, -fs * 0.5, fs, fs, 1)

        -- Soil partially covering
        love.graphics.setColor(EARTH.loam[1], EARTH.loam[2], EARTH.loam[3], fa * 0.5)
        love.graphics.rectangle("fill", -fs * 0.5, 0, fs, fs * 0.4, 1)

        love.graphics.pop()
    end

    -- ── CHIPS (stacked upward) ──
    local stack_base = frag_base - (#frags > 0 and 12 or 4)
    local start_idx  = math.max(1, #chips - L.max_vis + 1)
    local cx         = center_x - L.chip_w * 0.5

    -- Very gentle breathing (wind speed, not beat)
    local breath = math.sin(WIND._time * 0.35) * 0.4

    for i = start_idx, #chips do
        local chip = chips[i]
        local idx  = i - start_idx
        local cy   = stack_base - idx * (L.chip_h + L.chip_gap) - L.chip_h
        local mat  = TIER_MAT[chip.tier] or TIER_MAT.copper

        -- Depth-based breathing (top chips sway slightly more)
        local depth = (idx + 1) / math.max(1, #chips - start_idx + 1)
        local by    = cy + breath * depth * 0.25

        -- Shadow
        love.graphics.setColor(0, 0, 0, 0.30)
        love.graphics.rectangle("fill", cx + 0.5, by + 0.5, L.chip_w, L.chip_h, L.chip_r)

        -- Body (weathered metal)
        love.graphics.setColor(mat.base[1], mat.base[2], mat.base[3], 0.88)
        love.graphics.rectangle("fill", cx, by, L.chip_w, L.chip_h, L.chip_r)

        -- Top highlight
        love.graphics.setColor(mat.hi[1], mat.hi[2], mat.hi[3], 0.22)
        love.graphics.rectangle("fill", cx + 2, by, L.chip_w - 4, 2, 1)

        -- Bottom shadow
        love.graphics.setColor(mat.lo[1], mat.lo[2], mat.lo[3], 0.28)
        love.graphics.rectangle("fill", cx + 1, by + L.chip_h - 2, L.chip_w - 2, 2, 1)

        -- Center notch
        love.graphics.setColor(0, 0, 0, 0.08)
        local nw = L.chip_w * 0.30
        love.graphics.rectangle("fill", cx + (L.chip_w - nw) * 0.5, by + 2, nw, L.chip_h - 4, 1)
    end

    -- Truncation
    if start_idx > 1 then
        love.graphics.setColor(EARTH.glow_faint[1], EARTH.glow_faint[2], EARTH.glow_faint[3], 0.35)
        love.graphics.print("+" .. (start_idx - 1), x + 2, y + 4, 0, 0.35, 0.35)
    end

    -- Empty state
    if #chips == 0 and #frags == 0 then
        love.graphics.setColor(EARTH.glow_faint[1], EARTH.glow_faint[2], EARTH.glow_faint[3], 0.20)
        love.graphics.print("no gambits", center_x - 22, y + h * 0.35, 0, 0.40, 0.40)
        love.graphics.print("resolved", center_x - 18, y + h * 0.35 + 11, 0, 0.38, 0.38)
    end
end

-- ============================================================
-- ZONE: STATS
-- ============================================================

function CSU.draw_stats(x, y, w, h)
    local cs = TG.chip_stack
    if not cs then return end

    local wins     = cs:get_chip_count()
    local losses   = cs:get_fragment_count()
    local total    = wins + losses
    local pct      = total > 0 and math.floor(wins / total * 100) or 0
    local profit   = cs:get_total_profit()
    local invested = 0
    for _, c in ipairs(cs.chips) do invested = invested + (c.cost or 0) end
    for _, f in ipairs(cs.fragments) do invested = invested + (f.cost or 0) end

    local row_h = 12
    local ly    = y + 3

    CSU.draw_stat_row(x, ly, w, "net",
        (profit >= 0 and "+" or "") .. "$" .. math.abs(profit),
        profit > 0 and EARTH.growth or (profit < 0 and EARTH.wilt or EARTH.neutral))
    ly = ly + row_h

    CSU.draw_stat_row(x, ly, w, "w/l", wins .. " / " .. losses, EARTH.glow_soft)
    ly = ly + row_h

    CSU.draw_stat_row(x, ly, w, "rate",
        pct .. "%",
        pct >= 50 and EARTH.growth or EARTH.wilt)
    ly = ly + row_h

    CSU.draw_stat_row(x, ly, w, "cost", "$" .. invested, EARTH.neutral)
end

function CSU.draw_stat_row(x, y, w, label, value, value_color)
    -- Label
    love.graphics.setColor(EARTH.glow_dim[1], EARTH.glow_dim[2], EARTH.glow_dim[3], 0.50)
    love.graphics.print(label, x, y, 0, 0.42, 0.42)

    -- Value (right-aligned, glowing from beneath)
    love.graphics.setColor(value_color[1], value_color[2], value_color[3], 0.88)
    local font = love.graphics.getFont()
    local tw   = font:getWidth(value) * 0.48
    love.graphics.print(value, x + w - tw, y, 0, 0.48, 0.48)

    -- Connecting thread (fine dotted line, like a root between label and value)
    love.graphics.setColor(EARTH.root_light[1], EARTH.root_light[2], EARTH.root_light[3], 0.08)
    local label_end   = x + font:getWidth(label) * 0.42 + 4
    local value_start = x + w - tw - 4
    for dx = label_end, value_start, 5 do
        love.graphics.rectangle("fill", dx, y + 5, 1, 1)
    end
end

-- ============================================================
-- ZONE: HISTORY
-- ============================================================

function CSU.draw_history(x, y, w, h)
    local cs = TG.chip_stack
    if not cs then return end

    local timeline = {}
    for _, c in ipairs(cs.chips) do
        table.insert(timeline, { name = c.gambit_name, tier = c.tier,
            ante = c.ante, win = true })
    end
    for _, f in ipairs(cs.fragments) do
        table.insert(timeline, { name = f.gambit_name, tier = f.tier,
            ante = f.ante, win = false })
    end
    table.sort(timeline, function(a, b) return (a.ante or 0) > (b.ante or 0) end)

    local row_h    = 12
    local max_show = math.min(4, #timeline)

    if max_show == 0 then
        love.graphics.setColor(EARTH.glow_faint[1], EARTH.glow_faint[2], EARTH.glow_faint[3], 0.18)
        love.graphics.print("awaiting", x, y + h * 0.3, 0, 0.38, 0.38)
        return
    end

    for i = 1, max_show do
        local entry = timeline[i]
        local ey    = y + (i - 1) * row_h + 2
        local mat   = TIER_MAT[entry.tier] or TIER_MAT.copper

        -- Ante
        love.graphics.setColor(EARTH.glow_faint[1], EARTH.glow_faint[2], EARTH.glow_faint[3], 0.40)
        love.graphics.print(tostring(entry.ante or "?"), x, ey, 0, 0.35, 0.35)

        -- Name (pressed leaf: fainter if loss)
        local name = entry.name or "?"
        if #name > 12 then name = name:sub(1, 11) .. "." end
        love.graphics.setColor(EARTH.glow_soft[1], EARTH.glow_soft[2], EARTH.glow_soft[3],
                               entry.win and 0.70 or 0.32)
        love.graphics.print(name, x + 10, ey, 0, 0.35, 0.35)

        -- Result (right side, tiny colored dot + word)
        local font    = love.graphics.getFont()
        local badge   = entry.win and "won" or "lost"
        local badge_w = font:getWidth(badge) * 0.32 + 8
        local bx      = x + w - badge_w

        -- Dot (like a small seed: tier-colored for wins, wilt for losses)
        if entry.win then
            love.graphics.setColor(mat.base[1], mat.base[2], mat.base[3], 0.65)
        else
            love.graphics.setColor(EARTH.wilt[1], EARTH.wilt[2], EARTH.wilt[3], 0.45)
        end
        love.graphics.circle("fill", bx + 2, ey + 4, 2)

        -- Word
        love.graphics.setColor(
            entry.win and EARTH.glow_soft[1] or EARTH.wilt[1],
            entry.win and EARTH.glow_soft[2] or EARTH.wilt[2],
            entry.win and EARTH.glow_soft[3] or EARTH.wilt[3],
            entry.win and 0.60 or 0.40)
        love.graphics.print(badge, bx + 6, ey, 0, 0.32, 0.32)
    end
end

-- ============================================================
-- UPDATE
-- ============================================================

function CSU.update(dt)
    WIND.update(dt)
end

return CSU