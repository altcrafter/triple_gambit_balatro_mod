--[[
    TRIPLE GAMBIT - core/board.lua
    Per-board state: key-based deck, per-board resources, jokers, money, scoring.

    Phase 1 cleanup vs source:
      - Standalone deck section (init_standard_deck, shuffle_draw_pile, draw_hand,
        redraw_fresh_hand, reshuffle_discard, play_cards, discard_cards,
        exile_cards, restore_exiled_cards) DELETED.
      - board.deck table removed from constructor.
      - on_blind_start() calls reset_deck_keys() + draw_hand_keys() instead of
        standalone deck methods.
      - Per-board resources reset here (was reset in resource_pool reset).
      - Everything else kept verbatim from source.
]]

TG = TG or {}

-- ============================================================
-- BOARD CLASS
-- ============================================================

TG.Board = {}
TG.Board.__index = TG.Board

function TG.Board:new(id)
    local board = setmetatable({}, TG.Board)

    board.id = id  -- "A", "B", "C", or "D"

    -- Joker lineup (up to MAX_JOKERS_PER_BOARD)
    board.jokers = {}

    -- Consumables (Tarot, Planet, Spectral)
    board.consumables = {}

    -- Core stats
    board.hand_size = TG.CONFIG.STARTING_HAND_SIZE
    board.money     = TG.CONFIG.STARTING_MONEY

    -- Scoring (per blind)
    board.current_score = 0
    board.target        = 0

    -- Status
    board.is_cleared = false    -- Did this board clear the current blind?
    board.is_beaten  = false    -- Permanently beaten (cleared and done for this run segment)
    board.is_dead    = false    -- Hand size reached 0?

    -- Per-board resources (reset each blind, boosted on clears)
    board.hands_remaining    = TG.CONFIG.HANDS_PER_BLIND
    board.discards_remaining = TG.CONFIG.DISCARDS_PER_BLIND

    -- Per-blind tracking (reset each blind)
    board.hands_played_this_blind    = 0
    board.discards_used_this_blind   = 0

    -- Color/label from config
    board.color = TG.CONFIG.COLORS[id]
    board.label = TG.CONFIG.LABELS[id]

    -- Key-based deck tracking (populated by init_deck_keys when G.deck is ready).
    -- Initialized to empty tables here so draw_hand_keys() never crashes if
    -- called before G.deck exists (e.g. during blind selection screen).
    board.deck_keys    = {}
    board.draw_keys    = {}
    board.hand_keys    = {}
    board.discard_keys = {}

    return board
end

-- ============================================================
-- BLIND LIFECYCLE
-- ============================================================

--- Start of blind: reset per-blind tracking, reset key deck, draw initial hand.
function TG.Board:on_blind_start()
    if self.is_dead then return end

    self.current_score = 0
    self.is_cleared    = false
    self.hands_played_this_blind    = 0
    self.discards_used_this_blind   = 0

    -- Reset per-board resources (with cumulative bonus from clears)
    local hand_bonus    = (TG and TG.clear_bonus_hands)    or 0
    local discard_bonus = (TG and TG.clear_bonus_discards) or 0
    self.hands_remaining    = (TG.CONFIG.HANDS_PER_BLIND    or 4) + hand_bonus
    self.discards_remaining = (TG.CONFIG.DISCARDS_PER_BLIND or 3) + discard_bonus

    -- Key-based deck reset and draw
    self:reset_deck_keys()
    self:draw_hand_keys()
end

-- ============================================================
-- SCORING
-- ============================================================

--- Add score from a played hand.
--- Returns true if board has now cleared its target.
function TG.Board:add_score(amount)
    self.current_score = self.current_score + amount
    if self.current_score >= self.target then
        self.is_cleared = true
        return true
    end
    return false
end

--- Get progress as fraction (0.0 to 1.0+).
function TG.Board:get_progress()
    if self.target <= 0 then return 0 end
    return self.current_score / self.target
end

-- ============================================================
-- HAND SIZE
-- ============================================================

--- Reduce hand size by amount (minimum 0). Sets is_dead if reaches 0.
function TG.Board:reduce_hand_size(amount)
    amount = amount or 1
    self.hand_size = math.max(0, self.hand_size - amount)
    if self.hand_size == 0 then
        self.is_dead = true
        print(string.format("[TG] Board %s is DEAD (hand size 0)", self.id))
    end
end

--- Restore hand size (boss clear reward). No cap.
function TG.Board:restore_hand_size(amount)
    amount = amount or 1
    if self.is_dead then return end  -- Dead boards cannot be restored
    self.hand_size = self.hand_size + amount
end

-- ============================================================
-- MONEY
-- ============================================================

function TG.Board:add_money(amount)
    self.money = self.money + amount
end

function TG.Board:spend_money(amount)
    if self.money < amount then return false end
    self.money = self.money - amount
    return true
end

function TG.Board:can_afford(amount)
    return self.money >= amount
end

-- ============================================================
-- JOKERS
-- ============================================================

--- Add a joker to this board's lineup. Returns false if full.
function TG.Board:add_joker(joker)
    if #self.jokers >= TG.CONFIG.MAX_JOKERS_PER_BOARD then
        return false
    end
    joker.board_id = self.id
    table.insert(self.jokers, joker)
    return true
end

--- Remove a joker by index. Returns the removed joker or nil.
function TG.Board:remove_joker(index)
    if index < 1 or index > #self.jokers then return nil end
    return table.remove(self.jokers, index)
end

--- Remove a specific joker object. Returns true if found and removed.
function TG.Board:remove_joker_by_ref(joker)
    for i, j in ipairs(self.jokers) do
        if j == joker then
            table.remove(self.jokers, i)
            return true
        end
    end
    return false
end

--- Sell a random joker from this board. Returns sell value or 0.
function TG.Board:sell_random_joker()
    if #self.jokers == 0 then return 0 end
    local idx    = math.random(#self.jokers)
    local joker  = self:remove_joker(idx)
    local sell_value = joker.sell_value or joker.cost or 3
    self:add_money(sell_value)
    if TG.JokerBridge then
        TG.JokerBridge.unregister_joker(joker)
    end
    print(string.format("[TG] Board %s auto-sold joker '%s' for $%d",
        self.id, joker.name or "Unknown", sell_value))
    return sell_value
end

-- ============================================================
-- PER-BOARD RESOURCES
-- ============================================================

function TG.Board:can_play_hand()
    return (tonumber(self.hands_remaining) or 0) > 0
end

function TG.Board:use_hand()
    self.hands_remaining    = math.max(0, (tonumber(self.hands_remaining) or 0) - 1)
    self.hands_played_this_blind = (self.hands_played_this_blind or 0) + 1
end

function TG.Board:can_discard()
    return (tonumber(self.discards_remaining) or 0) > 0
end

function TG.Board:use_discard()
    self.discards_remaining      = math.max(0, (tonumber(self.discards_remaining) or 0) - 1)
    self.discards_used_this_blind = (self.discards_used_this_blind or 0) + 1
end

-- ============================================================
-- STATUS CHECK
-- ============================================================

--- Returns true if this board has had any hands or discards used this blind.
function TG.Board:has_been_played()
    return (self.hands_played_this_blind or 0) > 0
        or (self.discards_used_this_blind or 0) > 0
end

-- ============================================================
-- SERIALIZATION (for save/load)
-- ============================================================

function TG.Board:serialize()
    return {
        id                       = self.id,
        hand_size                = self.hand_size,
        money                    = self.money,
        current_score            = self.current_score,
        target                   = self.target,
        is_cleared               = self.is_cleared,
        is_beaten                = self.is_beaten,
        is_dead                  = self.is_dead,
        hands_played_this_blind  = self.hands_played_this_blind,
        discards_used_this_blind = self.discards_used_this_blind,
        hands_remaining          = self.hands_remaining,
        discards_remaining       = self.discards_remaining,
    }
end

function TG.Board:deserialize(data)
    self.hand_size                = data.hand_size
    self.money                    = data.money
    self.current_score            = data.current_score
    self.target                   = data.target
    self.is_cleared               = data.is_cleared
    self.is_beaten                = data.is_beaten or false
    self.is_dead                  = data.is_dead
    self.hands_played_this_blind  = data.hands_played_this_blind  or 0
    self.discards_used_this_blind = data.discards_used_this_blind or 0
    self.hands_remaining          = data.hands_remaining    or TG.CONFIG.HANDS_PER_BLIND
    self.discards_remaining       = data.discards_remaining or TG.CONFIG.DISCARDS_PER_BLIND
end

-- ============================================================
-- VIRTUAL DECK KEY TRACKING
-- ============================================================

--- Initialize each board's key-based deck from G.deck.cards at run start.
function TG.Board:init_deck_keys()
    if not G or not G.deck or not G.deck.cards then return end
    self.deck_keys    = {}
    self.draw_keys    = {}
    self.hand_keys    = {}
    self.discard_keys = {}
    for _, card in ipairs(G.deck.cards) do
        local key = TG.Board.card_key(card)
        table.insert(self.deck_keys, key)
        table.insert(self.draw_keys, key)
    end
    -- Shuffle draw pile
    local pile = self.draw_keys
    for i = #pile, 2, -1 do
        local j = math.random(i)
        pile[i], pile[j] = pile[j], pile[i]
    end
end

--- Add a card key to this board's deck (from pack opening).
function TG.Board:add_card_key(key)
    self.deck_keys = self.deck_keys or {}
    self.draw_keys = self.draw_keys or {}
    table.insert(self.deck_keys, key)
    table.insert(self.draw_keys, key)
end

--- Draw N keys from draw_keys into hand_keys.
--- Auto-reshuffles discard into draw if insufficient.
function TG.Board:draw_hand_keys(n)
    n = n or self.hand_size
    if #self.draw_keys < n then
        for _, k in ipairs(self.discard_keys) do
            table.insert(self.draw_keys, k)
        end
        self.discard_keys = {}
        local pile = self.draw_keys
        for i = #pile, 2, -1 do
            local j = math.random(i)
            pile[i], pile[j] = pile[j], pile[i]
        end
    end
    self.hand_keys = {}
    local drawn = math.min(n, #self.draw_keys)
    for i = 1, drawn do
        table.insert(self.hand_keys, table.remove(self.draw_keys, 1))
    end
end

--- Discard a key (move from hand to discard pile).
function TG.Board:discard_key(key)
    for i, k in ipairs(self.hand_keys) do
        if k == key then
            table.remove(self.hand_keys, i)
            table.insert(self.discard_keys, key)
            return
        end
    end
end

--- Move all hand_keys back to draw_keys (used on board switch).
function TG.Board:return_hand_to_draw()
    for _, k in ipairs(self.hand_keys) do
        table.insert(self.draw_keys, k)
    end
    self.hand_keys = {}
end

--- Reset draw/discard piles at blind start (full reshuffle from deck_keys).
function TG.Board:reset_deck_keys()
    self.draw_keys    = {}
    self.hand_keys    = {}
    self.discard_keys = {}
    for _, k in ipairs(self.deck_keys or {}) do
        table.insert(self.draw_keys, k)
    end
    local pile = self.draw_keys
    for i = #pile, 2, -1 do
        local j = math.random(i)
        pile[i], pile[j] = pile[j], pile[i]
    end
end

--- Map a list of keys to Balatro Card objects from G.deck.
function TG.Board:keys_to_cards(keys)
    if not G or not G.deck or not G.deck.cards then return {} end
    local key_map = {}
    for _, card in ipairs(G.deck.cards) do
        key_map[TG.Board.card_key(card)] = card
    end
    local result = {}
    for _, k in ipairs(keys or self.hand_keys) do
        if key_map[k] then table.insert(result, key_map[k]) end
    end
    return result
end

--- Static: stable string key for a Balatro Card (suit_value).
--- Uses card.base for direct Balatro Card objects.
function TG.Board.card_key(card)
    if not card then return "nil" end
    if card.base then
        return tostring(card.base.suit or "?") .. "_" .. tostring(card.base.value or "?")
    end
    if card.config and card.config.card then
        return tostring(card.config.card.suit or "?") .. "_" .. tostring(card.config.card.value or "?")
    end
    return tostring(card)
end

return TG.Board
