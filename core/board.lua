--[[
    TRIPLE GAMBIT - core/board.lua
    Board object. Key-based deck system only. Per-board resources.
    No standalone deck (draw_pile/hand/discard tables deleted per Phase 1 spec).
]]

local Board = {}
Board.__index = Board

-- ============================================================
-- CONSTRUCTOR
-- ============================================================

function Board:new(id)
    local o = setmetatable({}, self)

    o.id             = id
    o.is_cleared     = false
    o.is_dead        = false
    o.current_score  = 0
    o.target         = 300

    -- Key-based deck system (authoritative)
    o.deck_keys    = {}   -- all card keys this board owns
    o.draw_keys    = {}   -- keys not yet drawn
    o.hand_keys    = {}   -- keys currently in hand
    o.discard_keys = {}   -- keys that have been discarded

    -- Per-board resources
    o.hands_remaining    = TG.CONFIG.HANDS_PER_BLIND    or 4
    o.discards_remaining = TG.CONFIG.DISCARDS_PER_BLIND or 3

    -- Jokers and money
    o.jokers      = {}
    o.money       = TG.CONFIG.STARTING_MONEY or 4
    o.hand_size   = TG.CONFIG.STARTING_HAND_SIZE or 8

    return o
end

-- ============================================================
-- KEY UTILITIES
-- ============================================================

-- Returns the string key for a Card object.
-- Balatro cards have a unique_val field set by the deck.
function Board:card_key(card)
    if not card then return nil end
    return card.unique_val or card.sort_id or tostring(card)
end

-- ============================================================
-- KEY-BASED DECK SYSTEM
-- ============================================================

-- Populate deck_keys from G.deck.cards on the first blind start.
function Board:init_deck_keys()
    if not (G and G.deck and G.deck.cards) then return end
    self.deck_keys    = {}
    self.draw_keys    = {}
    self.hand_keys    = {}
    self.discard_keys = {}
    for _, card in ipairs(G.deck.cards) do
        local k = self:card_key(card)
        if k then
            table.insert(self.deck_keys, k)
            table.insert(self.draw_keys, k)
        end
    end
end

-- Add a specific card key to this board (e.g., from shop purchase).
function Board:add_card_key(card)
    local k = self:card_key(card)
    if not k then return end
    -- avoid duplicates
    for _, existing in ipairs(self.deck_keys) do
        if existing == k then return end
    end
    table.insert(self.deck_keys, k)
    table.insert(self.draw_keys, k)
end

-- Fisher-Yates shuffle on draw_keys.
function Board:shuffle_draw_keys()
    local t = self.draw_keys
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

-- Draw up to hand_size keys from draw_keys into hand_keys.
-- If draw pile runs out, reshuffle discard into draw first.
function Board:draw_hand_keys()
    local needed = self.hand_size - #self.hand_keys
    if needed <= 0 then return end

    -- Reshuffle discards into draw if needed
    if #self.draw_keys < needed then
        for _, k in ipairs(self.discard_keys) do
            table.insert(self.draw_keys, k)
        end
        self.discard_keys = {}
        self:shuffle_draw_keys()
    end

    -- Draw up to needed keys
    local drawn = math.min(needed, #self.draw_keys)
    for _ = 1, drawn do
        local k = table.remove(self.draw_keys, 1)
        table.insert(self.hand_keys, k)
    end
end

-- Move a key from hand_keys to discard_keys.
function Board:discard_key(k)
    for i, existing in ipairs(self.hand_keys) do
        if existing == k then
            table.remove(self.hand_keys, i)
            table.insert(self.discard_keys, k)
            return true
        end
    end
    return false
end

-- Move a key back from hand_keys to draw_keys (used on board switch).
function Board:return_to_draw(k)
    for i, existing in ipairs(self.hand_keys) do
        if existing == k then
            table.remove(self.hand_keys, i)
            table.insert(self.draw_keys, k)
            return true
        end
    end
    return false
end

-- Reset: move all hand and discard keys back to draw, reshuffle.
function Board:reset_deck_keys()
    for _, k in ipairs(self.hand_keys) do
        table.insert(self.draw_keys, k)
    end
    self.hand_keys = {}
    for _, k in ipairs(self.discard_keys) do
        table.insert(self.draw_keys, k)
    end
    self.discard_keys = {}
    self:shuffle_draw_keys()
end

-- Resolve hand_keys to Card objects via G.deck.cards.
-- Returns a list of cards in the same order as hand_keys.
function Board:keys_to_cards()
    if not (G and G.deck and G.deck.cards) then return {} end
    -- Build lookup table
    local by_key = {}
    for _, card in ipairs(G.deck.cards) do
        local k = self:card_key(card)
        if k then by_key[k] = card end
    end
    -- Also check G.hand in case cards are already there
    if G.hand and G.hand.cards then
        for _, card in ipairs(G.hand.cards) do
            local k = self:card_key(card)
            if k then by_key[k] = card end
        end
    end
    local result = {}
    for _, k in ipairs(self.hand_keys) do
        if by_key[k] then
            table.insert(result, by_key[k])
        end
    end
    return result
end

-- ============================================================
-- PER-BOARD RESOURCES
-- ============================================================

function Board:can_play_hand()
    return self.hands_remaining > 0
end

function Board:use_hand()
    if self.hands_remaining > 0 then
        self.hands_remaining = self.hands_remaining - 1
    end
end

function Board:can_discard()
    return self.discards_remaining > 0
end

function Board:use_discard()
    if self.discards_remaining > 0 then
        self.discards_remaining = self.discards_remaining - 1
    end
end

-- ============================================================
-- MONEY
-- ============================================================

function Board:add_money(amount)
    self.money = (self.money or 0) + amount
    if self.money < 0 then self.money = 0 end
end

-- ============================================================
-- SCORING
-- ============================================================

-- Add chips to this board's score. Returns true if the board just cleared.
function Board:add_score(chips)
    self.current_score = self.current_score + chips
    if not self.is_cleared and self.current_score >= self.target then
        self.is_cleared = true
        print(string.format("[TG] Board %s CLEARED! (%d / %d)",
            self.id, self.current_score, self.target))
        return true  -- just cleared
    end
    return false
end

-- ============================================================
-- BLIND LIFECYCLE
-- ============================================================

function Board:on_blind_start()
    -- Reset per-board resources
    -- Apply clear bonuses (hands_bonus/discards_bonus set externally by amplifier etc.)
    local hands_bonus    = self._hands_bonus    or 0
    local discards_bonus = self._discards_bonus or 0
    self.hands_remaining    = (TG.CONFIG.HANDS_PER_BLIND    or 4) + hands_bonus
    self.discards_remaining = (TG.CONFIG.DISCARDS_PER_BLIND or 3) + discards_bonus
    self._hands_bonus    = nil
    self._discards_bonus = nil

    -- Reset deck: return all cards to draw, shuffle, then draw opening hand
    self:reset_deck_keys()
    self:shuffle_draw_keys()
    self:draw_hand_keys()
end

-- ============================================================
-- SERIALIZATION
-- ============================================================

function Board:serialize()
    return {
        id                = self.id,
        is_cleared        = self.is_cleared,
        is_dead           = self.is_dead,
        current_score     = self.current_score,
        target            = self.target,
        deck_keys         = { table.unpack(self.deck_keys) },
        draw_keys         = { table.unpack(self.draw_keys) },
        hand_keys         = { table.unpack(self.hand_keys) },
        discard_keys      = { table.unpack(self.discard_keys) },
        hands_remaining   = self.hands_remaining,
        discards_remaining= self.discards_remaining,
        money             = self.money,
        hand_size         = self.hand_size,
    }
end

function Board:deserialize(data)
    if not data then return end
    self.is_cleared        = data.is_cleared        or false
    self.is_dead           = data.is_dead           or false
    self.current_score     = data.current_score     or 0
    self.target            = data.target            or 300
    self.deck_keys         = data.deck_keys         or {}
    self.draw_keys         = data.draw_keys         or {}
    self.hand_keys         = data.hand_keys         or {}
    self.discard_keys      = data.discard_keys      or {}
    self.hands_remaining   = data.hands_remaining   or (TG.CONFIG.HANDS_PER_BLIND    or 4)
    self.discards_remaining= data.discards_remaining or (TG.CONFIG.DISCARDS_PER_BLIND or 3)
    self.money             = data.money             or 0
    self.hand_size         = data.hand_size         or (TG.CONFIG.STARTING_HAND_SIZE or 8)
end

return Board
