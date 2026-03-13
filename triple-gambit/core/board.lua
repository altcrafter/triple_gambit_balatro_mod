--[[
    TRIPLE GAMBIT - core/board.lua

    Per-board state. Key-based deck system only — the standalone deck
    (draw_pile, hand tables, draw_hand(), etc.) has been deleted.

    Each board owns:
      - A virtual deck tracked by string keys (tg_key on each Card object)
      - Its own hands/discards budget
      - Its own joker lineup, money, and score
]]

local Board = {}
Board.__index = Board

-- ============================================================
-- CONSTRUCTOR
-- ============================================================

function Board:new(id)
    local b = setmetatable({}, Board)

    b.id              = id
    b.is_cleared      = false
    b.is_dead         = false
    b.current_score   = 0
    b.target          = 0
    b.money           = TG.CONFIG.STARTING_MONEY or 4
    b.jokers          = {}
    b.hand_size       = TG.CONFIG.STARTING_HAND_SIZE or 8

    -- Per-board resource budget (reset each blind)
    b.hands_remaining    = TG.CONFIG.HANDS_PER_BLIND    or 4
    b.discards_remaining = TG.CONFIG.DISCARDS_PER_BLIND or 3

    -- Key-based virtual deck — no standalone card tables
    b.deck_keys    = {}   -- all keys belonging to this board (full deck)
    b.draw_keys    = {}   -- keys in the draw pile
    b.hand_keys    = {}   -- keys currently in hand
    b.discard_keys = {}   -- keys in discard pile

    return b
end

-- ============================================================
-- BLIND LIFECYCLE
-- ============================================================

function Board:on_blind_start()
    -- Reset key system
    self:reset_deck_keys()
    self:draw_hand_keys()

    -- Reset per-board resources each blind (bonuses applied externally if needed)
    self.hands_remaining    = TG.CONFIG.HANDS_PER_BLIND    or 4
    self.discards_remaining = TG.CONFIG.DISCARDS_PER_BLIND or 3
end

-- ============================================================
-- PER-BOARD RESOURCE METHODS
-- ============================================================

function Board:can_play_hand()
    return self.hands_remaining > 0
end

function Board:use_hand()
    self.hands_remaining = math.max(0, self.hands_remaining - 1)
end

function Board:can_discard()
    return self.discards_remaining > 0
end

function Board:use_discard()
    self.discards_remaining = math.max(0, self.discards_remaining - 1)
end

-- ============================================================
-- KEY-BASED DECK SYSTEM
-- ============================================================

-- Assign a stable string key to a Card object (idempotent)
function Board:card_key(card)
    if not card then return nil end
    if not card.tg_key then
        card.tg_key = "tgc_" .. tostring(card):gsub("table: ", "")
    end
    return card.tg_key
end

-- Initialise deck_keys from G.deck.cards. Called once when G.deck is ready.
function Board:init_deck_keys()
    self.deck_keys    = {}
    self.draw_keys    = {}
    self.hand_keys    = {}
    self.discard_keys = {}

    if not (G and G.deck and G.deck.cards) then return end

    for _, card in ipairs(G.deck.cards) do
        local key = self:card_key(card)
        table.insert(self.deck_keys, key)
        table.insert(self.draw_keys, key)
    end
end

-- Add a single card's key to this board (e.g. card acquired mid-run)
function Board:add_card_key(card)
    local key = self:card_key(card)
    -- Avoid duplicates
    for _, k in ipairs(self.deck_keys) do
        if k == key then return end
    end
    table.insert(self.deck_keys, key)
    table.insert(self.draw_keys, key)
end

-- Shuffle draw_keys then move n keys into hand_keys
function Board:draw_hand_keys(n)
    n = n or self.hand_size or TG.CONFIG.STARTING_HAND_SIZE or 8

    -- Fisher-Yates shuffle on draw pile
    for i = #self.draw_keys, 2, -1 do
        local j = math.random(i)
        self.draw_keys[i], self.draw_keys[j] = self.draw_keys[j], self.draw_keys[i]
    end

    -- Draw up to n cards (or as many as available)
    local drawn = 0
    while drawn < n and #self.draw_keys > 0 do
        local key = table.remove(self.draw_keys)
        table.insert(self.hand_keys, key)
        drawn = drawn + 1
    end
end

-- Move a key from hand_keys to discard_keys
function Board:discard_key(key)
    for i, k in ipairs(self.hand_keys) do
        if k == key then
            table.remove(self.hand_keys, i)
            table.insert(self.discard_keys, key)
            return true
        end
    end
    return false
end

-- Return all hand_keys back to draw_keys (used on board switch)
function Board:return_hand_to_draw()
    for _, key in ipairs(self.hand_keys) do
        table.insert(self.draw_keys, key)
    end
    self.hand_keys = {}
end

-- Reshuffle discard pile into draw pile (mid-blind reshuffle)
function Board:reshuffle_discard_to_draw()
    for _, key in ipairs(self.discard_keys) do
        table.insert(self.draw_keys, key)
    end
    self.discard_keys = {}
end

-- Merge draw/hand/discard back into draw pile and clear hand (blind reset)
function Board:reset_deck_keys()
    -- Rebuild draw_keys from all owned keys
    local in_draw = {}
    for _, k in ipairs(self.deck_keys) do
        in_draw[k] = true
    end
    self.draw_keys    = {}
    for k in pairs(in_draw) do
        table.insert(self.draw_keys, k)
    end
    self.hand_keys    = {}
    self.discard_keys = {}
end

-- Resolve hand_keys (or provided key list) to actual Card objects.
-- Searches G.hand.cards and G.deck.cards.
function Board:keys_to_cards(keys)
    keys = keys or self.hand_keys

    -- Build a lookup of all accessible Card objects by tg_key
    local by_key = {}
    local function index_area(area)
        if area and area.cards then
            for _, card in ipairs(area.cards) do
                if card and card.tg_key then
                    by_key[card.tg_key] = card
                end
            end
        end
    end
    index_area(G and G.deck)
    index_area(G and G.hand)
    index_area(G and G.jokers)

    local result = {}
    for _, key in ipairs(keys) do
        local card = by_key[key]
        if card then table.insert(result, card) end
    end
    return result
end

-- ============================================================
-- MONEY
-- ============================================================

function Board:add_money(amount)
    self.money = (self.money or 0) + (amount or 0)
end

function Board:spend_money(amount)
    self.money = math.max(0, (self.money or 0) - (amount or 0))
end

-- ============================================================
-- JOKERS
-- ============================================================

function Board:add_joker(card)
    if #self.jokers >= (TG.CONFIG.MAX_JOKERS_PER_BOARD or 5) then
        return false
    end
    table.insert(self.jokers, card)
    card.tg_board_id = self.id
    return true
end

function Board:remove_joker(card)
    for i, j in ipairs(self.jokers) do
        if j == card then
            table.remove(self.jokers, i)
            card.tg_board_id = nil
            return true
        end
    end
    return false
end

-- ============================================================
-- SCORING
-- ============================================================

-- Add chips to this board's score. Returns true if the board just cleared.
function Board:add_score(chips)
    if self.is_cleared then return false end
    self.current_score = (self.current_score or 0) + (chips or 0)
    if self.current_score >= self.target then
        self.is_cleared = true
        print(string.format("[TG] Board %s CLEARED! (%d / %d)", self.id, self.current_score, self.target))
        return true
    end
    return false
end

-- ============================================================
-- HAND SIZE
-- ============================================================

function Board:modify_hand_size(delta)
    self.hand_size = math.max(1, (self.hand_size or 8) + delta)
end

-- ============================================================
-- SERIALIZATION
-- ============================================================

function Board:serialize()
    return {
        id                   = self.id,
        is_cleared           = self.is_cleared,
        is_dead              = self.is_dead,
        current_score        = self.current_score,
        target               = self.target,
        money                = self.money,
        hand_size            = self.hand_size,
        hands_remaining      = self.hands_remaining,
        discards_remaining   = self.discards_remaining,
        deck_keys            = self.deck_keys,
        draw_keys            = self.draw_keys,
        hand_keys            = self.hand_keys,
        discard_keys         = self.discard_keys,
        joker_keys           = (function()
            local ks = {}
            for _, card in ipairs(self.jokers) do
                if card and card.tg_key then table.insert(ks, card.tg_key) end
            end
            return ks
        end)(),
    }
end

function Board:deserialize(data)
    self.is_cleared          = data.is_cleared          or false
    self.is_dead             = data.is_dead             or false
    self.current_score       = data.current_score       or 0
    self.target              = data.target              or 0
    self.money               = data.money               or 0
    self.hand_size           = data.hand_size           or (TG.CONFIG.STARTING_HAND_SIZE or 8)
    self.hands_remaining     = data.hands_remaining     or (TG.CONFIG.HANDS_PER_BLIND or 4)
    self.discards_remaining  = data.discards_remaining  or (TG.CONFIG.DISCARDS_PER_BLIND or 3)
    self.deck_keys           = data.deck_keys           or {}
    self.draw_keys           = data.draw_keys           or {}
    self.hand_keys           = data.hand_keys           or {}
    self.discard_keys        = data.discard_keys        or {}
    -- jokers are re-linked by save_load.lua after card objects are available
end

return Board
