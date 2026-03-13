--[[
    TRIPLE GAMBIT - core/init.lua
    Initializes TG. Loads modules. Sets up all three boards and resource pool.
]]

TG = TG or {}

TG.BOARD_IDS = { "A", "B", "C" }

-- ============================================================
-- CONFIG
-- ============================================================

TG.CONFIG = {
    HANDS_PER_BLIND           = 4,
    DISCARDS_PER_BLIND        = 3,
    SWITCHES_PER_BLIND        = 1,
    STARTING_HAND_SIZE        = 8,
    STARTING_MONEY            = 4,
    MAX_JOKERS_PER_BOARD      = 5,
    TOTAL_BOARDS              = 3,
    BOARDS_TO_CLEAR           = 3,
    FINAL_ANTE                = 8,
    REROLL_COST               = 5,
    REWARD_PER_UNUSED_HAND    = 1,
    REWARD_PER_UNUSED_DISCARD = 0,
    SHOP_JOKER_SLOTS          = 2,
    SHOP_PACK_SLOTS           = 2,
    ANIM_SWITCH_FADE_OUT      = 0.15,
    ANIM_SWITCH_FADE_IN       = 0.15,

    LABELS = {
        A = "BOARD A",
        B = "BOARD B",
        C = "BOARD C",
    },

    -- Industrial palette: desaturated, high contrast
    COLORS = {
        A = { r = 0.85, g = 0.22, b = 0.27 },  -- signal red
        B = { r = 0.27, g = 0.48, b = 0.62 },  -- steel blue
        C = { r = 0.92, g = 0.62, b = 0.28 },  -- amber warning
    },

    CLEAR_BUFF_BASE           = 0.15,
    CLEAR_BUFF_PER_HAND       = 0.05,
}

-- ============================================================
-- INIT
-- ============================================================

function TG:init()
    if self.initialized then return end
    print("[TG] Initializing Triple Gambit...")

    TG.Board        = tg_require("core/board")
    TG.ResourcePool = tg_require("core/resource_pool")
    TG.Switching    = tg_require("core/switching")
    TG.Shop         = tg_require("core/shop_logic")
    TG.SaveLoad     = tg_require("core/save_load")
    TG.JokerBridge  = tg_require("core/joker_bridge")
    TG.Gambit       = tg_require("core/gambit")
    TG.Amplifier    = tg_require("core/amplifier")
    TG.ChipStack    = tg_require("core/chip_stack")
    TG.GambitBase   = tg_require("core/gambit_base")
    tg_require("core/gambits")  -- registers all 11 gambits

    self.boards = {}
    for _, id in ipairs(TG.BOARD_IDS) do
        self.boards[id] = TG.Board:new(id)
        self.boards[id]:init_standard_deck()
    end
    self.active_board_id = "A"

    self.pool = TG.ResourcePool:new()
    self.active_gambits = {}
    self.chip_stack          = TG.ChipStack:new()
    self.run_active          = true
    self.current_ante        = 1
    self.current_blind_type  = "small"
    self._last_seen_ante     = nil
    self._prev_state         = nil
    self.entering_shop_board = nil
    self.cleared_boards      = {}
    self.boards_played_on    = {}

    self.initialized = true
    print("[TG] Triple Gambit ready. Three boards initialized.")
end

-- ============================================================
-- BOARD ACCESS
-- ============================================================

function TG:get_active_board()
    return self.boards[self.active_board_id]
end

function TG:get_board(id)
    return self.boards[id]
end

function TG:set_active_board(id)
    assert(self.boards[id], "[TG] Unknown board: " .. tostring(id))
    self.active_board_id = id
end

function TG:random_other_board(exclude_id, exclude_set)
    local candidates = {}
    for _, id in ipairs(TG.BOARD_IDS) do
        if id ~= exclude_id
        and self.boards[id]
        and not self.boards[id].is_dead
        and not self.boards[id].is_cleared then
            local dominated = false
            for _, ex in ipairs(exclude_set or {}) do
                if ex == id then dominated = true; break end
            end
            if not dominated then
                table.insert(candidates, id)
            end
        end
    end
    if #candidates == 0 then return nil end
    return candidates[math.random(#candidates)]
end

-- ============================================================
-- BLIND LIFECYCLE
-- ============================================================

function TG:on_blind_start()
    self.pool:reset()
    TG.Amplifier.reset()

    -- Sync from Balatro's state
    if G and G.GAME then
        if G.GAME.round_resets and G.GAME.round_resets.blind_ante then
            self.current_ante = G.GAME.round_resets.blind_ante
        elseif G.GAME.ante then
            self.current_ante = G.GAME.ante
        end
        if G.GAME.current_round and G.GAME.current_round.blind_states then
            local bs = G.GAME.current_round.blind_states
            if bs.Small == "Current" then self.current_blind_type = "small"
            elseif bs.Big == "Current" then self.current_blind_type = "big"
            else self.current_blind_type = "boss" end
        end
    end

    local target = self:calculate_target()
    for _, id in ipairs(TG.BOARD_IDS) do
        local b = self.boards[id]
        if b then
            b.current_score = 0
            b.is_cleared    = false
            b.target        = target
            b:on_blind_start()
        end
    end
end

function TG:on_blind_end()
    local reward = self.pool.hands_remaining * TG.CONFIG.REWARD_PER_UNUSED_HAND
    if reward > 0 then
        local board = self:get_active_board()
        if board then board:add_money(reward) end
    end
    self:advance_blind()
end

function TG:advance_blind()
    if self.current_blind_type == "small" then
        self.current_blind_type = "big"
    elseif self.current_blind_type == "big" then
        self.current_blind_type = "boss"
    else
        self.current_ante       = self.current_ante + 1
        self.current_blind_type = "small"
        if self.current_ante > TG.CONFIG.FINAL_ANTE then
            self:on_run_won()
        end
    end
end

-- ============================================================
-- TARGET — reads Balatro's ante as fallback
-- ============================================================

function TG:calculate_target()
    local targets = {
        [1] = { small = 300,   big = 450,   boss = 600   },
        [2] = { small = 800,   big = 1200,  boss = 1600  },
        [3] = { small = 2000,  big = 3000,  boss = 4000  },
        [4] = { small = 5000,  big = 7500,  boss = 10000 },
        [5] = { small = 11000, big = 16500, boss = 22000 },
        [6] = { small = 20000, big = 30000, boss = 40000 },
        [7] = { small = 35000, big = 52500, boss = 70000 },
        [8] = { small = 50000, big = 75000, boss = 100000 },
    }
    local a = self.current_ante
    if G and G.GAME then
        if G.GAME.round_resets and G.GAME.round_resets.blind_ante then
            a = G.GAME.round_resets.blind_ante
        elseif G.GAME.ante then
            a = G.GAME.ante
        end
    end
    a = math.min(a or 1, TG.CONFIG.FINAL_ANTE)
    return (targets[a] and targets[a][self.current_blind_type]) or 300
end

-- ============================================================
-- WIN / LOSS
-- ============================================================

function TG:on_run_won()
    self.run_active = false
    if TG.Audio then TG.Audio.play("run_won") end
    print("[TG] === RUN WON ===")
end

function TG:on_run_lost(reason)
    self.run_active = false
    if TG.Audio then TG.Audio.play("run_lost") end
    print("[TG] === RUN LOST === " .. tostring(reason))
    if G and G.E_MANAGER then
        G.E_MANAGER:add_event(Event({
            blocking = true,
            blockable = false,
            func = function()
                if G.STATE ~= G.STATES.SELECTING_HAND
                and G.STATE ~= G.STATES.DRAW_TO_HAND then
                    return false
                end
                if G.GAME and G.GAME.current_round then
                    G.GAME.current_round.hands_left = 0
                end
                if G.blind and G.blind.defeat then
                    G.blind:defeat()
                elseif G.FUNCS and G.FUNCS.game_over then
                    G.FUNCS.game_over()
                end
                return true
            end
        }))
    end
end

-- ============================================================
-- UPDATE
-- ============================================================

function TG:update(dt)
    if not self.initialized or not self.run_active then return end
end

return TG
