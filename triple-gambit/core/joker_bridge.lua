--[[
    TRIPLE GAMBIT - core/joker_bridge.lua

    Swaps board jokers into G.jokers for Balatro's scoring engine.
    Uses CardArea:remove_card() / CardArea:emplace() so that mod hooks fire.

    pre_score()  — called before orig_play; installs scoring board's jokers
    post_score() — called after on_score_calculated; restores active board's jokers
    count_for_board(id) — reads from TG boards directly (never from G.jokers.cards)
    register_joker(card, board_id) — assigns a joker card to a board
]]

local JokerBridge = {}

-- Track which board's jokers are currently in G.jokers
local _scoring_board_id = nil

-- ============================================================
-- PRE-SCORE
-- Move scoring board's jokers into G.jokers via CardArea methods.
-- ============================================================

function JokerBridge.pre_score()
    if not TG.initialized then return end

    local board_id    = TG._board_id_at_play or TG.active_board_id
    local score_board = TG:get_board(board_id)
    if not score_board then return end
    if not (G and G.jokers) then return end

    -- Remove whatever is currently in G.jokers
    local current = {}
    for _, card in ipairs(G.jokers.cards or {}) do
        table.insert(current, card)
    end
    for _, card in ipairs(current) do
        G.jokers:remove_card(card)
    end

    -- Emplace the scoring board's jokers
    for _, card in ipairs(score_board.jokers) do
        G.jokers:emplace(card)
    end

    _scoring_board_id = board_id
end

-- ============================================================
-- POST-SCORE
-- Restore the active board's jokers into G.jokers.
-- ============================================================

function JokerBridge.post_score()
    if not TG.initialized then return end

    local active_board = TG:get_active_board()
    if not active_board then return end
    if not (G and G.jokers) then return end

    -- If scoring board == active board, nothing to do
    if _scoring_board_id == TG.active_board_id then
        _scoring_board_id = nil
        return
    end

    -- Remove scoring board's jokers
    local current = {}
    for _, card in ipairs(G.jokers.cards or {}) do
        table.insert(current, card)
    end
    for _, card in ipairs(current) do
        G.jokers:remove_card(card)
    end

    -- Re-emplace active board's jokers
    for _, card in ipairs(active_board.jokers) do
        G.jokers:emplace(card)
    end

    _scoring_board_id = nil
end

-- ============================================================
-- COUNT FOR BOARD
-- Always reads from TG board state, never from G.jokers.cards
-- (G.jokers may be mid-swap during scoring).
-- ============================================================

function JokerBridge.count_for_board(board_id)
    local board = TG:get_board(board_id)
    if not board then return 0 end
    return #board.jokers
end

-- ============================================================
-- REGISTER JOKER
-- Assign a joker card object to a specific board.
-- Called when a joker is bought or enters via a pack.
-- ============================================================

function JokerBridge.register_joker(card, board_id)
    if not (card and board_id) then return end
    local board = TG:get_board(board_id)
    if not board then return end

    -- Remove from any board it's already on
    for _, id in ipairs(TG.BOARD_IDS) do
        local b = TG:get_board(id)
        if b then b:remove_joker(card) end
    end

    board:add_joker(card)
    print(string.format("[TG] Joker registered to Board %s", board_id))
end

return JokerBridge
