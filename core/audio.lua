--[[
    TRIPLE GAMBIT - core/audio.lua
    Procedural audio system.
    5 layers, hand-type pitch arcs, stereo panning per board.
]]

TG.Audio = TG.Audio or {}

TG.Audio._sources = {}

function TG.Audio.init()
    -- Audio is optional. Gracefully skip if love.audio is unavailable.
    if not love or not love.audio then return end
    print("[TG] Audio init (stub — implement procedural layers here).")
end

function TG.Audio.play(event_name)
    -- event_name: "action_blocked", "gambit_blocked", "near_loss", "run_won", "run_lost"
    -- TODO: implement audio events
end

function TG.Audio.play_score(board_id, chips, deficit, hand_type)
    -- Pitch arc based on hand_type. Panning based on board_id.
    -- TODO: implement procedural score audio
end

function TG.Audio.update(dt)
    -- TODO: update audio layer states
end

return TG.Audio
