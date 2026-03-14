--[[
    TRIPLE GAMBIT - core/amplifier.lua
    Clear-early scoring buff system.
    When a board clears, ALL remaining uncleared boards receive a multiplier buff.
    buff = 0.15 + (hands_remaining * 0.05)
    Buffs stack additively. Reset each blind.
]]

TG.Amplifier = TG.Amplifier or {}

-- Per-board buff multipliers (additive stacks), reset each blind
TG.Amplifier._buffs = {}

function TG.Amplifier.reset()
    TG.Amplifier._buffs = {}
end

-- Called when a board clears. boards_remaining_hands = the clearing board's hands_remaining.
function TG.Amplifier.on_board_cleared(cleared_board_id, hands_remaining)
    local base = TG.CONFIG.CLEAR_BUFF_BASE   or 0.15
    local per  = TG.CONFIG.CLEAR_BUFF_PER_HAND or 0.05
    local buff = base + ((hands_remaining or 0) * per)

    -- Apply buff to ALL uncleared boards
    for _, id in ipairs(TG.BOARD_IDS) do
        local b = TG:get_board(id)
        if b and not b.is_cleared then
            TG.Amplifier._buffs[id] = (TG.Amplifier._buffs[id] or 0) + buff
            print(string.format("[TG] Amplifier: Board %s +%.0f%% (from Board %s clearing with %d hands)",
                id, buff * 100, cleared_board_id, hands_remaining or 0))
        end
    end
end

-- Returns the total score multiplier for a board (1.0 = no buff).
function TG.Amplifier.get_multiplier(board_id)
    return 1.0 + (TG.Amplifier._buffs[board_id] or 0)
end

return TG.Amplifier
