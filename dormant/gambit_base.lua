--[[
    TRIPLE GAMBIT - dormant/gambit_base.lua
    Ante-spanning constraint system (GambitBase).
    DORMANT — not loaded by any active code.
    Preserved for a future phase.

    This system provides per-ante constraints that persist across blinds:
    - A gambit can be "present" (shown in shop), "accepted" (bought), or "declined" (passed).
    - Accepted gambits impose constraints for the entire ante.
    - Resolving a gambit (meeting its condition) rewards the player.
    - Failing a gambit (not meeting its condition by ante end) penalizes.

    To re-enable: add tg_require("core/gambit_base") back to core/init.lua
    and register gambit definitions in a separate registrations file.
]]

TG.GambitBase = TG.GambitBase or {}

-- Registry: all defined ante-spanning gambit types
TG.GambitBase._registry = {}

-- Active: gambits accepted this ante
TG.GambitBase._active = {}

-- ============================================================
-- REGISTRATION
-- ============================================================

function TG.GambitBase.register(def)
    -- def: { id, name, description, condition_fn, reward_fn, penalty_fn }
    TG.GambitBase._registry[def.id] = def
end

-- ============================================================
-- LIFECYCLE
-- ============================================================

function TG.GambitBase.present(gambit_id)
    -- Called when a gambit appears in the shop
    local def = TG.GambitBase._registry[gambit_id]
    if not def then return end
    print("[TG:GambitBase] Presenting: " .. gambit_id)
end

function TG.GambitBase.accept(gambit_id)
    local def = TG.GambitBase._registry[gambit_id]
    if not def then return end
    table.insert(TG.GambitBase._active, { id = gambit_id, def = def, met = false })
    print("[TG:GambitBase] Accepted: " .. gambit_id)
end

function TG.GambitBase.decline(gambit_id)
    print("[TG:GambitBase] Declined: " .. gambit_id)
end

function TG.GambitBase.resolve_all()
    -- Called at ante end. Check each active gambit.
    for _, entry in ipairs(TG.GambitBase._active) do
        if entry.def.condition_fn and entry.def.condition_fn() then
            entry.met = true
            if entry.def.reward_fn then entry.def.reward_fn() end
            print("[TG:GambitBase] Resolved (success): " .. entry.id)
        else
            if entry.def.penalty_fn then entry.def.penalty_fn() end
            print("[TG:GambitBase] Resolved (failure): " .. entry.id)
        end
    end
    TG.GambitBase._active = {}
end

return TG.GambitBase
