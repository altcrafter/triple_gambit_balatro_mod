--[[
    TRIPLE GAMBIT - core/save_load.lua
    Persists all mod state: boards, gambits, amplifier buffs.
    No shared ResourcePool — per-board hands/discards are inside each board's serialize().
]]

TG = TG or {}

TG.SaveLoad = {}

local SAVE_KEY = "triple_gambit_state"

-- ============================================================
-- SERIALIZE
-- ============================================================

function TG.SaveLoad.serialize()
    if not TG.initialized then return nil end

    local data = {
        version             = "2.0.0",
        boards              = {},
        active_board_id     = TG.active_board_id,
        entering_shop_board = TG.entering_shop_board,
        cleared_boards      = TG.cleared_boards,
        boards_played_on    = TG.boards_played_on,
        run_active          = TG.run_active,
        current_ante        = TG.current_ante,
        current_blind_type  = TG.current_blind_type,
        gambits             = TG.Gambit   and TG.Gambit.serialize()    or {},
        amplifier           = TG.Amplifier and TG.Amplifier.serialize() or {},
    }

    for _, id in ipairs(TG.BOARD_IDS) do
        local board = TG:get_board(id)
        if board then
            data.boards[id] = board:serialize()
        end
    end

    return data
end

-- ============================================================
-- DESERIALIZE
-- ============================================================

function TG.SaveLoad.deserialize(data)
    if not data then
        print("[TG] Save data missing")
        return false
    end

    if data.version ~= "2.0.0" then
        print("[TG] Save data version unrecognized: " .. tostring(data.version))
        return false
    end

    -- Restore boards
    for _, id in ipairs(TG.BOARD_IDS) do
        if data.boards and data.boards[id] then
            if not TG.boards[id] then
                TG.boards[id] = TG.Board:new(id)
            end
            TG:get_board(id):deserialize(data.boards[id])
        end
    end

    -- Restore run state
    TG.active_board_id     = data.active_board_id     or "A"
    TG.entering_shop_board = data.entering_shop_board
    TG.cleared_boards      = data.cleared_boards      or {}
    TG.boards_played_on    = data.boards_played_on    or {}
    TG.run_active          = data.run_active
    TG.current_ante        = data.current_ante        or 1
    TG.current_blind_type  = data.current_blind_type  or "small"

    -- Restore gambit state (joker_refs will be nil until jokers reload;
    -- that is acceptable — boards remain locked correctly on deserialization)
    if TG.Gambit and data.gambits then
        TG.Gambit.deserialize(data.gambits)
    end

    -- Restore amplifier buffs
    if TG.Amplifier and data.amplifier then
        TG.Amplifier.deserialize(data.amplifier)
    end

    TG.initialized = true
    print("[TG] State loaded (version " .. tostring(data.version) .. ")")
    return true
end

-- ============================================================
-- BALATRO SAVE / LOAD HOOKS
-- ============================================================

function TG.SaveLoad.on_save(save_data)
    save_data[SAVE_KEY] = TG.SaveLoad.serialize()
end

-- Alias used in main.lua
TG.SaveLoad.on_save_progress = TG.SaveLoad.on_save

function TG.SaveLoad.on_load(save_data)
    local tg_data = save_data[SAVE_KEY]
    if tg_data then
        return TG.SaveLoad.deserialize(tg_data)
    else
        print("[TG] No Triple Gambit data in save file")
        return false
    end
end

-- ============================================================
-- VALIDATION
-- ============================================================

function TG.SaveLoad.validate()
    local living = 0
    for _, id in ipairs(TG.BOARD_IDS) do
        local b = TG:get_board(id)
        if b and not b.is_dead then living = living + 1 end
    end
    if living < TG.CONFIG.BOARDS_TO_CLEAR then
        print("[TG] WARNING: Fewer living boards than BOARDS_TO_CLEAR")
    end
    return true
end

return TG.SaveLoad
