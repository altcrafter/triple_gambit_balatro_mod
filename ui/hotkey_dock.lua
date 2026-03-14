--[[
    TRIPLE GAMBIT - ui/hotkey_dock.lua
    NEW. Four 36x36 board-switch squares at the bottom.
    Shows board number, active state, cleared state, hot-line indicator.
]]

local Dock = {}

local SQUARE_SIZE = 36
local SQUARE_GAP  = 6
local ANIM_SPEED  = 1 / 0.15  -- 150ms transition

local BOARD_UI_COLORS = {
    A = { 1.0,   0.176, 0.42  },
    B = { 0.0,   0.898, 1.0   },
    C = { 1.0,   0.667, 0.133 },
    D = { 0.706, 0.302, 1.0   },
}

local CLEARED_COLOR = { 0.412, 0.941, 0.682 }

-- Per-square animation timers (0=inactive, 1=active)
local _anim = { A = 0, B = 0, C = 0, D = 0 }

-- ============================================================
-- HELPERS
-- ============================================================

local function board_ids()
    return (TG and TG.BOARD_IDS) or { "A", "B", "C", "D" }
end

local function active_id()
    return (TG and TG.active_board_id) or "A"
end

local function board_number(id)
    local ids = board_ids()
    for i, bid in ipairs(ids) do
        if bid == id then return i end
    end
    return 1
end

local function is_cleared(id)
    if not (TG and TG.boards and TG.boards[id]) then return false end
    return TG.boards[id].is_cleared or false
end

-- ============================================================
-- UPDATE
-- ============================================================

function Dock.update(dt)
    local aid = active_id()
    for _, id in ipairs(board_ids()) do
        local target = (id == aid) and 1.0 or 0.0
        if _anim[id] == nil then _anim[id] = 0 end
        local delta = target - _anim[id]
        if delta > 0 then
            _anim[id] = math.min(1.0, _anim[id] + dt * ANIM_SPEED)
        elseif delta < 0 then
            _anim[id] = math.max(0.0, _anim[id] - dt * ANIM_SPEED)
        end
    end
end

-- ============================================================
-- DRAW
-- ============================================================

function Dock.draw()
    if not TG or not TG.initialized then return end
    if not TG.Phosphor then return end

    local ids  = board_ids()
    local sw, sh = love.graphics.getDimensions()
    local n    = #ids
    local total_w = n * SQUARE_SIZE + (n - 1) * SQUARE_GAP
    local start_x = math.floor(sw / 2 - total_w / 2)
    local sq_y    = sh - SQUARE_SIZE - 10

    for i, id in ipairs(ids) do
        local sq_x   = start_x + (i - 1) * (SQUARE_SIZE + SQUARE_GAP)
        local anim_t = _anim[id] or 0
        local bc     = BOARD_UI_COLORS[id] or { 1, 1, 1 }
        local cleared = is_cleared(id)
        local num_str = tostring(board_number(id))

        -- Background
        if anim_t > 0.01 then
            love.graphics.setColor(bc[1], bc[2], bc[3], 0.06 * anim_t)
            love.graphics.rectangle("fill", sq_x, sq_y, SQUARE_SIZE, SQUARE_SIZE, 3, 3)
        else
            love.graphics.setColor(0.039, 0.020, 0.078, 0.40)
            love.graphics.rectangle("fill", sq_x, sq_y, SQUARE_SIZE, SQUARE_SIZE, 3, 3)
        end

        -- Border
        if anim_t > 0.01 then
            love.graphics.setColor(bc[1], bc[2], bc[3], 0.15 * anim_t)
        else
            love.graphics.setColor(1, 1, 1, 0.03)
        end
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", sq_x + 0.5, sq_y + 0.5, SQUARE_SIZE - 1, SQUARE_SIZE - 1, 3, 3)

        -- Hot-line (top 2px bar, active board only)
        if anim_t > 0.01 then
            love.graphics.setBlendMode("add")
            love.graphics.setColor(bc[1], bc[2], bc[3], 0.6 * anim_t)
            love.graphics.rectangle("fill", sq_x + 3, sq_y, SQUARE_SIZE - 6, 2, 1, 1)
            love.graphics.setBlendMode("alpha")
        end

        -- Number label
        local num_x = sq_x + math.floor(SQUARE_SIZE / 2 - TG.Phosphor.width(num_str, 16) / 2)
        local num_y = sq_y + 6
        if anim_t > 0.5 then
            TG.Phosphor.draw(num_str, num_x, num_y, bc, 0.8 * anim_t, 16)
        else
            TG.Phosphor.draw(num_str, num_x, num_y, { 1, 1, 1 }, 0.0, 16, 0.12)
        end

        -- Status dot (bottom center)
        local dot_x = sq_x + math.floor(SQUARE_SIZE / 2)
        local dot_y = sq_y + SQUARE_SIZE - 5
        local dot_c
        if cleared then
            dot_c = CLEARED_COLOR
        elseif anim_t > 0.5 then
            dot_c = bc
        else
            dot_c = nil
        end

        if dot_c then
            love.graphics.setColor(dot_c[1], dot_c[2], dot_c[3], anim_t > 0.5 and 1.0 or 0.7)
            love.graphics.circle("fill", dot_x, dot_y, 2)
        else
            love.graphics.setColor(1, 1, 1, 0.08)
            love.graphics.circle("fill", dot_x, dot_y, 2)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

-- ============================================================
-- CLICK HANDLING
-- ============================================================

function Dock.handle_click(mx, my)
    local ids  = board_ids()
    local sw, sh = love.graphics.getDimensions()
    local n    = #ids
    local total_w = n * SQUARE_SIZE + (n - 1) * SQUARE_GAP
    local start_x = math.floor(sw / 2 - total_w / 2)
    local sq_y    = sh - SQUARE_SIZE - 10

    if my < sq_y or my > sq_y + SQUARE_SIZE then return nil end

    for i, id in ipairs(ids) do
        local sq_x = start_x + (i - 1) * (SQUARE_SIZE + SQUARE_GAP)
        if mx >= sq_x and mx < sq_x + SQUARE_SIZE then
            return id
        end
    end
    return nil
end

return Dock
