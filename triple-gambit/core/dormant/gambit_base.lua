--[[
    Triple Gambit - Gambit Base Class & Resolution
    Gambits are ante-spanning constraints with upfront cost and delayed reward.
]]

TG = TG or {}

-- ============================================================
-- GAMBIT BASE CLASS
-- ============================================================

TG.GambitBase = {}
TG.GambitBase.__index = TG.GambitBase

function TG.GambitBase:new(def)
    local gambit = setmetatable({}, TG.GambitBase)

    gambit.id          = def.id          -- Unique string identifier
    gambit.name        = def.name        -- Display name
    gambit.condition   = def.condition   -- Description of the constraint
    gambit.cost        = def.cost        -- Upfront cost in $
    gambit.reward      = def.reward      -- Payout on success
    gambit.tier        = def.tier        -- "copper", "silver", or "gold"

    -- Flags for shop restrictions
    gambit.blocks_spending  = def.blocks_spending  or false
    gambit.blocks_reroll    = def.blocks_reroll    or false
    gambit.blocks_selling   = def.blocks_selling   or false
    gambit.blocks_discards  = def.blocks_discards  or false
    gambit.blocks_consumables = def.blocks_consumables or false

    -- Trap gambit: requires minimum hand size
    gambit.min_hand_size = def.min_hand_size or 0

    -- Runtime state
    gambit.is_active      = false
    gambit.ante_accepted  = 0
    gambit.is_failed      = false   -- Set true if auto-failed (trap)

    -- Lifecycle callbacks (override in specific gambits)
    gambit.on_accept       = def.on_accept       or nil  -- Called when accepted
    gambit.on_blind_start  = def.on_blind_start  or nil  -- Called at start of each blind
    gambit.on_blind_end    = def.on_blind_end    or nil  -- Called at end of each blind
    gambit.on_hand_drawn   = def.on_hand_drawn   or nil  -- Called when hand is drawn
    gambit.on_hand_played  = def.on_hand_played  or nil  -- Called after hand is played
    gambit.on_discard      = def.on_discard      or nil  -- Called on discard
    gambit.on_update       = def.on_update       or nil  -- Called every frame
    gambit.on_resolve      = def.on_resolve      or nil  -- Called after check_success (cleanup)
    gambit.check_success   = def.check_success   or function() return true end

    return gambit
end

--- Create a fresh instance of this gambit (for accepting).
function TG.GambitBase:clone()
    local clone = TG.GambitBase:new({
        id = self.id,
        name = self.name,
        condition = self.condition,
        cost = self.cost,
        reward = self.reward,
        tier = self.tier,
        blocks_spending = self.blocks_spending,
        blocks_reroll = self.blocks_reroll,
        blocks_selling = self.blocks_selling,
        blocks_discards = self.blocks_discards,
        blocks_consumables = self.blocks_consumables,
        min_hand_size = self.min_hand_size,
        on_accept = self.on_accept,
        on_blind_start = self.on_blind_start,
        on_blind_end = self.on_blind_end,
        on_hand_drawn = self.on_hand_drawn,
        on_hand_played = self.on_hand_played,
        on_discard = self.on_discard,
        on_update = self.on_update,
        on_resolve = self.on_resolve,
        check_success = self.check_success,
    })
    return clone
end

--- Check if this gambit is a trap for any board (hand size too low).
function TG.GambitBase:is_trap_for_board(board)
    if self.min_hand_size <= 0 then return false end
    return board.hand_size < self.min_hand_size
end

-- ============================================================
-- GAMBIT PRESENTATION & ACCEPTANCE
-- ============================================================

TG.Gambits = {}

--- Present a new gambit to the player at ante start.
function TG.Gambits.present_new_gambit()
    local gambit_def = TG.Gambits.roll_random_gambit()
    if not gambit_def then return end

    TG.pending_gambit = gambit_def:clone()
    print(string.format("[TG] Presenting gambit: '%s' (Cost: $%d, Reward: $%d, Tier: %s)",
        gambit_def.name, gambit_def.cost, gambit_def.reward, gambit_def.tier))
end

--- Accept the pending gambit.
function TG.Gambits.accept_pending()
    local gambit = TG.pending_gambit
    if not gambit then return false, "No gambit pending" end

    -- Pay cost from active board
    local active_board = TG:get_active_board()
    if not active_board:can_afford(gambit.cost) then
        return false, "Cannot afford gambit cost ($" .. gambit.cost .. ")"
    end

    active_board:spend_money(gambit.cost)

    -- Activate gambit
    gambit.is_active = true
    gambit.ante_accepted = TG.current_ante
    table.insert(TG.active_gambits, gambit)

    -- Check for trap conditions
    for _, id in ipairs(TG.BOARD_IDS) do
        local board = TG:get_board(id)
        if gambit:is_trap_for_board(board) then
            print(string.format("[TG] Gambit '%s' is a TRAP for Board %s (hand size %d < %d)",
                gambit.name, id, board.hand_size, gambit.min_hand_size))
        end
    end

    -- Call accept callback
    if gambit.on_accept then
        gambit:on_accept(TG)
    end

    TG.pending_gambit = nil
    print(string.format("[TG] Gambit '%s' ACCEPTED. Cost $%d from Board %s",
        gambit.name, gambit.cost, active_board.id))

    return true, "Gambit accepted"
end

--- Decline the pending gambit.
function TG.Gambits.decline_pending()
    if TG.pending_gambit then
        print(string.format("[TG] Gambit '%s' DECLINED", TG.pending_gambit.name))
        TG.pending_gambit = nil
    end
end

-- ============================================================
-- GAMBIT RESOLUTION (end of ante / boss clear)
-- ============================================================

--- Resolve all active gambits. Called at Boss Blind clear or Lamp activation.
function TG:resolve_gambits()
    local results = {}

    for i = #self.active_gambits, 1, -1 do
        local gambit = self.active_gambits[i]

        -- Check success
        -- FIX ISSUE #12: coerce to boolean — nil return from check_success was
        -- treated as truthy, paying out rewards on failed gambits.
        local success = false
        if gambit.check_success then
            success = gambit:check_success(self) or false
        end

        -- Record result
        local result = {
            gambit = gambit,
            success = success,
            ante = gambit.ante_accepted,
        }
        table.insert(results, result)

        if success then
            -- Pay reward to the board that cleared boss (active board)
            local reward_board = self:get_active_board()
            reward_board:add_money(gambit.reward)

            -- Add to chip stack
            self.chip_stack:add_chip({
                gambit_id = gambit.id,
                gambit_name = gambit.name,
                tier = gambit.tier,
                cost = gambit.cost,
                reward = gambit.reward,
                ante = gambit.ante_accepted,
                success = true,
            })

            if TG.Audio then TG.Audio.play("chip_stack") end

            print(string.format("[TG] Gambit '%s' SUCCEEDED! Reward $%d to Board %s",
                gambit.name, gambit.reward, reward_board.id))
        else
            -- Failed: cost already paid, no reward
            self.chip_stack:add_fragment({
                gambit_id = gambit.id,
                gambit_name = gambit.name,
                tier = gambit.tier,
                cost = gambit.cost,
                ante = gambit.ante_accepted,
                success = false,
            })

            if TG.Audio then TG.Audio.play("chip_fragment") end

            print(string.format("[TG] Gambit '%s' FAILED. $%d lost.", gambit.name, gambit.cost))
        end

        -- Clean up gambit effects
        if gambit.on_resolve then
            gambit:on_resolve(self, success)
        end

        -- Remove from active list
        table.remove(self.active_gambits, i)
    end

    return results
end

-- ============================================================
-- GAMBIT REGISTRY
-- ============================================================

TG.Gambits.registry = {}  -- Populated by gambits.lua

function TG.Gambits.register(gambit_def)
    TG.Gambits.registry[gambit_def.id] = gambit_def
end

function TG.Gambits.get_by_id(id)
    local def = TG.Gambits.registry[id]
    if def then return def:clone() end
    return nil
end

--- Roll a random gambit from the registry.
function TG.Gambits.roll_random_gambit()
    local keys = {}
    for k, _ in pairs(TG.Gambits.registry) do
        table.insert(keys, k)
    end
    if #keys == 0 then return nil end
    local key = keys[math.random(#keys)]
    return TG.Gambits.registry[key]
end

return TG.Gambits