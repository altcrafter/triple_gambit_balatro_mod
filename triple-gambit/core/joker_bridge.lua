--[[
    TRIPLE GAMBIT - core/joker_bridge.lua
    Temporarily swaps the active board's jokers into G.jokers.cards
    so Balatro's scoring engine can see and trigger them, then swaps back.

    Decision: We MOVE jokers rather than copy them.
    Rationale: Joker effects mutate internal state (counters, retriggers).
    Copying would desync TG's board state from Balatro's object state.
    Moving preserves object identity — one source of truth.

    Phase 1 changes vs source:
      - count_for_board() now reads from TG.boards directly (spec §3.3).
        Previously read from G.jokers.cards via tg_board_id tags, which
        was unreliable mid-swap. TG's board.jokers array is authoritative.
      - Everything else kept verbatim from source.
]]

TG = TG or {}

TG.JokerBridge = {}

local JB = TG.JokerBridge

-- Storage for Balatro's joker list during scoring
JB._original_joker_cards = {}
JB._board_scored = nil   -- Board ID currently scoring (nil when not scoring)

-- ============================================================
-- PRE / POST SCORE
-- ============================================================

--- Call BEFORE original Game.play_hand().
--- Moves the active board's jokers into G.jokers.cards so Balatro scores them.
function JB.pre_score()
    if not TG.initialized then return end
    if not G or not G.jokers or not G.jokers.cards then return end

    local board = TG:get_active_board()
    if not board then return end

    JB._original_joker_cards = G.jokers.cards
    JB._board_scored = board.id

    -- Swap in this board's joker lineup
    G.jokers.cards = board.jokers

    print(string.format("[TG] JokerBridge: swapped in %d jokers for Board %s",
        #board.jokers, board.id))
end

--- Call AFTER original Game.play_hand() returns.
--- Saves any joker mutations back to the board, then restores Balatro's list.
function JB.post_score()
    if not TG.initialized then return end
    if not G or not G.jokers or not G.jokers.cards then return end

    local board_id = JB._board_scored
    if not board_id then return end

    -- Persist any mutations Balatro made to the joker objects back to our board
    local board = TG:get_board(board_id)
    if board then
        board.jokers = G.jokers.cards
    end

    -- Restore G.jokers.cards to the active board's lineup.
    -- We do NOT restore JB._original_joker_cards — that was Balatro's
    -- global list from before TG took over. TG owns joker routing now.
    local active_board = TG:get_active_board()
    if active_board then
        G.jokers.cards = active_board.jokers
    else
        G.jokers.cards = JB._original_joker_cards
    end
    JB._original_joker_cards = {}
    JB._board_scored = nil

    print(string.format("[TG] JokerBridge: restored jokers for Board %s", board_id))
end

-- ============================================================
-- REGISTRATION HELPERS
-- ============================================================

--- Tag a Balatro Card object with a board_id when it enters a board's lineup.
function JB.register_joker(joker, board_id)
    if joker then
        joker.tg_board_id = board_id
        print(string.format("[TG] JokerBridge: registered joker '%s' to Board %s",
            joker.name or "Unknown", board_id))
    end
end

--- Clear the board tag when a joker is sold or destroyed.
function JB.unregister_joker(joker)
    if joker then
        joker.tg_board_id = nil
    end
end

-- ============================================================
-- SAFETY ACCESSORS
-- ============================================================

--- Returns true if we are currently mid-score swap (between pre and post).
function JB.is_scoring()
    return JB._board_scored ~= nil
end

--- Count how many jokers belong to a given board.
--- Reads from TG.boards directly — never from G.jokers.cards, which may be
--- mid-swap during scoring (spec §3.3).
function JB.count_for_board(board_id)
    local board = TG:get_board(board_id)
    return board and #board.jokers or 0
end

return TG.JokerBridge
