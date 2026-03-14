--[[
    TRIPLE GAMBIT - core/save_load.lua
    Serialization and deserialization of TG state into G.GAME.tg_save.
]]

TG.SaveLoad = TG.SaveLoad or {}

function TG.SaveLoad.serialize()
    if not TG.initialized then return nil end

    local boards_data = {}
    for _, id in ipairs(TG.BOARD_IDS) do
        local b = TG:get_board(id)
        if b then boards_data[id] = b:serialize() end
    end

    local gambits_data = {}
    if TG.Gambit then
        for _, g in ipairs(TG.Gambit.active) do
            table.insert(gambits_data, {
                id       = g.id,
                board    = g.board,
                joker_id = g.joker_ref and (g.joker_ref.unique_val or tostring(g.joker_ref)),
            })
        end
    end

    return {
        version          = 1,
        active_board_id  = TG.active_board_id,
        current_ante     = TG.current_ante,
        current_blind_type = TG.current_blind_type,
        boards           = boards_data,
        gambits          = gambits_data,
        amplifier_buffs  = TG.Amplifier and TG.Amplifier._buffs or {},
    }
end

function TG.SaveLoad.on_load(save_data)
    if not save_data or not save_data.triple_gambit_state then return end
    local s = save_data.triple_gambit_state
    if not s then return end

    TG.active_board_id  = s.active_board_id  or "A"
    TG.current_ante     = s.current_ante     or 1
    TG.current_blind_type = s.current_blind_type or "small"

    if s.boards then
        for id, bdata in pairs(s.boards) do
            local b = TG:get_board(id)
            if b then b:deserialize(bdata) end
        end
    end

    if TG.Amplifier and s.amplifier_buffs then
        TG.Amplifier._buffs = s.amplifier_buffs
    end

    print("[TG] SaveLoad: state restored.")
end

return TG.SaveLoad
