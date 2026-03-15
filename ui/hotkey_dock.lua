--[[
    TRIPLE GAMBIT - ui/hotkey_dock.lua
    Four board-switch squares. One element per square: the board number.
    No background, no border, no hot-line, no status dot.
    Phosphor bloom IS the background.

    Active:   serif 13px, board color, glow 0.6, +2° lean.
    Inactive: rgba(255,255,255,0.10), glow 0.0.
    Cleared:  #69f0ae, glow 0.2.
    16px gaps between squares.
]]

local Dock = {}

local SQUARE_SIZE = 36
local SQUARE_GAP  = 16

local BOARD_UI_COLORS = {
    A = { 1.0,   0.176, 0.42  },
    B = { 0.0,   0.898, 1.0   },
    C = { 1.0,   0.667, 0.133 },
    D = { 0.706, 0.302, 1.0   },
}

local CLEARED_COLOR = { 0.412, 0.941, 0.682 }

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
-- UPDATE (state read directly from TG each frame)
-- ============================================================

function Dock.update(dt)
end

-- ============================================================
-- DRAW
-- ============================================================

function Dock.draw()
    if not TG or not TG.initialized then return end
    if not TG.Phosphor then return end

    local ids     = board_ids()
    local sw, sh  = love.graphics.getDimensions()
    local n       = #ids
    local total_w = n * SQUARE_SIZE + (n - 1) * SQUARE_GAP
    local start_x = math.floor(sw / 2 - total_w / 2)
    local sq_y    = sh - SQUARE_SIZE - 10

    for i, id in ipairs(ids) do
        local sq_x   = start_x + (i - 1) * (SQUARE_SIZE + SQUARE_GAP)
        local active  = (id == active_id())
        local cleared = is_cleared(id)
        local num_str = tostring(board_number(id))

        -- Determine rendering state
        local color, glow, lean, alpha
        if active then
            color = BOARD_UI_COLORS[id] or { 1, 1, 1 }
            glow  = 0.6
            lean  = math.rad(2)
            alpha = 1.0
        elseif cleared then
            color = CLEARED_COLOR
            glow  = 0.2
            lean  = 0
            alpha = 0.85
        else
            color = { 1, 1, 1 }
            glow  = 0.0
            lean  = 0
            alpha = 0.10
        end

        -- Center the number within the hit square
        local num_w = TG.Phosphor.width(num_str, "serif", 13)
        local num_h = TG.Phosphor.height("serif", 13)
        local num_x = sq_x + math.floor((SQUARE_SIZE - num_w) * 0.5)
        local num_y = sq_y + math.floor((SQUARE_SIZE - num_h) * 0.5)

        TG.Phosphor.draw(num_str, num_x, num_y, color, glow, "serif", 13, alpha, lean)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- ============================================================
-- CLICK HANDLING
-- ============================================================

function Dock.handle_click(mx, my)
    local ids     = board_ids()
    local sw, sh  = love.graphics.getDimensions()
    local n       = #ids
    local total_w = n * SQUARE_SIZE + (n - 1) * SQUARE_GAP
    local start_x = math.floor(sw / 2 - total_w / 2)
    local sq_y    = sh - SQUARE_SIZE - 10

    if my < sq_y or my > sq_y + SQUARE_SIZE then return nil end

    for i, id in ipairs(ids) do
        local sq_x = start_x + (i - 1) * (SQUARE_SIZE + SQUARE_GAP)
        if mx >= sq_x and mx < sq_x + SQUARE_SIZE then
            if TG and TG.Switching then
                TG.Switching.execute_switch(id)
            end
            return true
        end
    end
    return nil
end

return Dock
