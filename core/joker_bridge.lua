--[[
    TRIPLE GAMBIT - core/joker_bridge.lua
    Swaps per-board jokers into G.jokers for scoring.
    Uses CardArea methods (no direct .cards assignment).
]]

TG.JokerBridge = TG.JokerBridge or {}

TG.JokerBridge._saved_jokers = nil

-- Joker registry: tracks which board owns which card
TG.JokerBridge._registry = {}   -- card unique_val → board_id

-- ============================================================
-- REGISTRY
-- ============================================================

function TG.JokerBridge.register_joker(card, board_id)
    local k = card and (card.unique_val or tostring(card))
    if not k then return end
    TG.JokerBridge._registry[k] = board_id
    card.tg_board_id = board_id
end

function TG.JokerBridge.unregister_joker(card)
    local k = card and (card.unique_val or tostring(card))
    if not k then return end
    TG.JokerBridge._registry[k] = nil
    card.tg_board_id = nil
end

function TG.JokerBridge.get_joker_board(card)
    local k = card and (card.unique_val or tostring(card))
    if not k then return nil end
    return TG.JokerBridge._registry[k] or card.tg_board_id
end

-- ============================================================
-- PRE SCORE
-- Swap in the scoring board's jokers before Balatro evaluates.
-- ============================================================

function TG.JokerBridge.pre_score()
    local board_id = TG._board_id_at_play or TG.active_board_id
    local board    = TG:get_board(board_id)
    if not board or not G.jokers then return end

    -- Capture any jokers in G.jokers not yet in board.jokers (e.g., pack acquisitions)
    if G.jokers.cards then
        for _, card in ipairs(G.jokers.cards) do
            local found = false
            for _, j in ipairs(board.jokers) do
                if j == card then found = true; break end
            end
            if not found then table.insert(board.jokers, card) end
        end
    end

    -- Save current jokers and remove from G.jokers
    TG.JokerBridge._saved_jokers = {}
    if G.jokers.cards then
        for i = #G.jokers.cards, 1, -1 do
            table.insert(TG.JokerBridge._saved_jokers, G.jokers.cards[i])
            G.jokers:remove_card(G.jokers.cards[i])
        end
    end

    -- Emplace scoring board's jokers
    for _, joker in ipairs(board.jokers) do
        TG.Switching._emplace(G.jokers, joker)
    end
end

-- ============================================================
-- POST SCORE
-- Restore original jokers after Balatro evaluates.
-- ============================================================

function TG.JokerBridge.post_score()
    if not G.jokers or not TG.JokerBridge._saved_jokers then return end

    -- Remove scoring board's jokers
    if G.jokers.cards then
        for i = #G.jokers.cards, 1, -1 do
            G.jokers:remove_card(G.jokers.cards[i])
        end
    end

    -- Restore saved jokers
    for _, joker in ipairs(TG.JokerBridge._saved_jokers) do
        TG.Switching._emplace(G.jokers, joker)
    end

    TG.JokerBridge._saved_jokers = nil
end

-- ============================================================
-- COUNT FOR BOARD
-- Always reads from the board's .jokers table directly.
-- Never reads from G.jokers.cards (which is mid-swap during scoring).
-- ============================================================

function TG.JokerBridge.count_for_board(board_id)
    local board = TG:get_board(board_id)
    if not board then return 0 end
    return #board.jokers
end

return TG.JokerBridge
