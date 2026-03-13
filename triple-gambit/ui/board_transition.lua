--[[
    TRIPLE GAMBIT - ui/board_transition.lua
    Industrial Brutalism transition effects.

    Switch  → horizontal glitch displacement bands + hard color wipe
    Cleared → full-screen OVEREXPOSE flash, scan-line stamp, edge pulse

    Hard cuts, mechanical, thumping. No soft fades.
    Everything snaps in and decays with grit.
]]

TG    = TG or {}
TG.UI = TG.UI or {}
TG.UI.BoardTransition = {}

local BT = TG.UI.BoardTransition

BT.switch = {
    active = false, timer = 0, duration = 0.40,
    from_id = nil, to_id = nil, bands = {},
}

BT.clear = {
    active = false, timer = 0, duration = 1.0,
    board_id = nil, queue = {},
}

function BT.trigger_switch(from_id, to_id)
    BT.switch.active  = true
    BT.switch.timer   = 0
    BT.switch.from_id = from_id
    BT.switch.to_id   = to_id
    BT.switch.bands   = {}
    local sh = love.graphics.getHeight()
    for _ = 1, math.random(5, 9) do
        table.insert(BT.switch.bands, {
            y = math.random(0, sh), h = math.random(2, 18),
            offset = (math.random() - 0.5) * 40,
            decay = 0.3 + math.random() * 0.5,
        })
    end
    if TG.UI and TG.UI.Shader then TG.UI.Shader.spike_aberration(0.012, 1.0) end
end

function BT.trigger_cleared(board_id)
    if BT.clear.active then table.insert(BT.clear.queue, board_id); return end
    BT.clear.active   = true
    BT.clear.timer    = 0
    BT.clear.board_id = board_id
    if TG.UI and TG.UI.Shader then TG.UI.Shader.spike_aberration(0.018, 2.0) end
end

function BT.update(dt)
    if BT.switch.active then
        BT.switch.timer = BT.switch.timer + dt
        if BT.switch.timer >= BT.switch.duration then BT.switch.active = false end
    end
    if BT.clear.active then
        BT.clear.timer = BT.clear.timer + dt
        if BT.clear.timer >= BT.clear.duration then
            BT.clear.active = false; BT.clear.board_id = nil
            if #BT.clear.queue > 0 then BT.trigger_cleared(table.remove(BT.clear.queue, 1)) end
        end
    end
end

function BT.draw()
    BT.draw_switch_glitch()
    BT.draw_clear_burst()
end

function BT.draw_switch_glitch()
    if not BT.switch.active then return end
    local color = TG.CONFIG.COLORS[BT.switch.to_id]
    if not color then return end
    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()
    local t  = BT.switch.timer / BT.switch.duration

    local intensity = t < 0.15 and 1.0 or math.max(0, 1.0 - ((t - 0.15) / 0.85) * 1.2)

    -- Horizontal glitch bands
    for _, band in ipairs(BT.switch.bands) do
        local ba = intensity * band.decay
        if ba > 0.02 then
            love.graphics.setColor(color.r, color.g, color.b, ba * 0.6)
            love.graphics.rectangle("fill", band.offset * intensity, band.y, sw, band.h)
            love.graphics.setColor(1 - color.r, 1 - color.g, 1 - color.b, ba * 0.2)
            love.graphics.rectangle("fill", -band.offset * intensity * 0.5,
                band.y + band.h, sw, math.max(1, band.h * 0.4))
        end
    end

    -- Hard top/bottom bars
    local bar_h = 4 * intensity
    if bar_h > 0.5 then
        love.graphics.setColor(color.r, color.g, color.b, 0.7 * intensity)
        love.graphics.rectangle("fill", 0, 0, sw, bar_h)
        love.graphics.rectangle("fill", 0, sh - bar_h, sw, bar_h)
    end

    -- Board label stamp
    if intensity > 0.3 then
        local label = TG.CONFIG.LABELS[BT.switch.to_id] or "BOARD"
        local font  = love.graphics.getFont()
        local tw    = font:getWidth(label) * 1.2
        love.graphics.setColor(0, 0, 0, 0.7 * intensity)
        love.graphics.print(label, sw * 0.5 - tw * 0.5 + 2, 60, 0, 1.2, 1.2)
        love.graphics.setColor(color.r, color.g, color.b, intensity)
        love.graphics.print(label, sw * 0.5 - tw * 0.5, 58, 0, 1.2, 1.2)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function BT.draw_clear_burst()
    if not BT.clear.active then return end
    local color = TG.CONFIG.COLORS[BT.clear.board_id]
    if not color then return end
    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()
    local t  = BT.clear.timer / BT.clear.duration

    local white_a, color_a, stamp_a
    if t < 0.08 then
        white_a = (t / 0.08) * 0.7; color_a = 0; stamp_a = 0
    elseif t < 0.25 then
        local p = (t - 0.08) / 0.17
        white_a = (1 - p) * 0.7; color_a = p * 0.5; stamp_a = p
    else
        local p = (t - 0.25) / 0.75
        white_a = 0; color_a = (1 - p) * 0.5; stamp_a = math.max(0, 1 - p * 1.5)
    end

    -- White overexpose
    if white_a > 0.01 then
        love.graphics.setColor(1, 1, 1, white_a)
        love.graphics.rectangle("fill", 0, 0, sw, sh)
    end

    -- Color tint
    if color_a > 0.01 then
        love.graphics.setColor(color.r, color.g, color.b, color_a)
        love.graphics.rectangle("fill", 0, 0, sw, sh)
    end

    -- Scan lines
    if stamp_a > 0.1 then
        love.graphics.setColor(0, 0, 0, stamp_a * 0.15)
        for ly = 0, sh, 3 do love.graphics.rectangle("fill", 0, ly, sw, 1) end
    end

    -- CLEARED stamp
    if stamp_a > 0.05 then
        local label = (TG.CONFIG.LABELS[BT.clear.board_id] or "BOARD") .. "  CLEARED"
        local font  = love.graphics.getFont()
        local scale = 2.2
        local tw    = font:getWidth(label) * scale
        local th    = font:getHeight() * scale
        local tx    = (sw - tw) * 0.5
        local ty    = (sh - th) * 0.5

        -- Black band behind text
        love.graphics.setColor(0, 0, 0, stamp_a * 0.8)
        love.graphics.rectangle("fill", 0, ty - 8, sw, th + 16)
        -- Accent lines
        love.graphics.setColor(color.r, color.g, color.b, stamp_a * 0.9)
        love.graphics.setLineWidth(2)
        love.graphics.line(0, ty - 8, sw, ty - 8)
        love.graphics.line(0, ty + th + 8, sw, ty + th + 8)
        love.graphics.setLineWidth(1)
        -- Shadow + text
        love.graphics.setColor(0, 0, 0, stamp_a)
        love.graphics.print(label, tx + 2, ty + 2, 0, scale, scale)
        love.graphics.setColor(1, 1, 1, stamp_a)
        love.graphics.print(label, tx, ty, 0, scale, scale)
    end

    -- Edge frame pulse
    if color_a > 0.02 then
        love.graphics.setColor(color.r, color.g, color.b, color_a * 1.5)
        love.graphics.setLineWidth(4)
        love.graphics.rectangle("line", 4, 4, sw - 8, sh - 8)
        love.graphics.setLineWidth(1)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return BT
