--[[
    TRIPLE GAMBIT - core/amplifier.lua
    When a board clears its target, ALL remaining uncleared boards get a
    scoring buff. Buff scales with how many hands the clearing board had left —
    more hands left = bigger buff. This rewards clearing boards early.
]]

TG = TG or {}
TG.Amplifier = {}

-- Active buffs: { board_id = accumulated_buff_fraction }
-- e.g. { B = 0.35 } means Board B scores at 1.35x
TG.Amplifier.buffs = {}

--- Called when a board clears its target.
--- Buffs all uncleared living boards (every board except the one that just cleared).
--- @param cleared_board_id string  The board that just cleared
function TG.Amplifier.on_board_cleared(cleared_board_id)
    -- Use the clearing board's own remaining hands (not a shared pool)
    local clearing_board = TG:get_board(cleared_board_id)
    local hands_left     = clearing_board and (clearing_board.hands_remaining or 0) or 0
    local base           = TG.CONFIG.CLEAR_BUFF_BASE    or 0.15
    local per_hand       = TG.CONFIG.CLEAR_BUFF_PER_HAND or 0.05
    local buff           = base + (hands_left * per_hand)

    for _, id in ipairs(TG.BOARD_IDS) do
        local board = TG:get_board(id)
        if board and not board.is_cleared and not board.is_dead and id ~= cleared_board_id then
            local current = TG.Amplifier.buffs[id] or 0
            TG.Amplifier.buffs[id] = current + buff
            print(string.format(
                "[TG] Amplifier: Board %s gets +%.0f%% buff (Board %s cleared with %d hands left)",
                id, buff * 100, cleared_board_id, hands_left))
        end
    end
end

--- Get the current scoring multiplier for a board.
--- Returns 1.0 + accumulated buff (e.g., 1.35 for a 35% buff).
--- @param board_id string
--- @return number
function TG.Amplifier.get_multiplier(board_id)
    return 1.0 + (TG.Amplifier.buffs[board_id] or 0)
end

--- Reset all buffs. Called at the start of each blind.
function TG.Amplifier.reset()
    TG.Amplifier.buffs = {}
end

-- ============================================================
-- SERIALIZATION
-- ============================================================

function TG.Amplifier.serialize()
    return { buffs = TG.Amplifier.buffs }
end

function TG.Amplifier.deserialize(data)
    TG.Amplifier.buffs = (data and data.buffs) or {}
end

return TG.Amplifier
