--[[
    TRIPLE GAMBIT - core/gambit.lua

    Joker-gambit system: each shop joker carries a hidden gambit that
    locks a board to a hand type and applies a level boost when that
    hand is played on that board.

    32 templates: 8 hand types × 4 boards (A, B, C, D).
    Level boost inversely proportional to hand rarity:
      High Card +5, Pair +4, Two Pair +3, Three of a Kind +3,
      Straight +2, Flush +2, Full House +2, Four of a Kind +1
]]

local Gambit = {}

-- ============================================================
-- TEMPLATES
-- ============================================================

Gambit.templates = {
    -- Board A
    { id = "a_high",      board = "A", hand_type = "High Card",        level_boost = 5 },
    { id = "a_pair",      board = "A", hand_type = "Pair",             level_boost = 4 },
    { id = "a_twopair",   board = "A", hand_type = "Two Pair",         level_boost = 3 },
    { id = "a_three",     board = "A", hand_type = "Three of a Kind",  level_boost = 3 },
    { id = "a_straight",  board = "A", hand_type = "Straight",         level_boost = 2 },
    { id = "a_flush",     board = "A", hand_type = "Flush",            level_boost = 2 },
    { id = "a_fullhouse", board = "A", hand_type = "Full House",       level_boost = 2 },
    { id = "a_four",      board = "A", hand_type = "Four of a Kind",   level_boost = 1 },

    -- Board B
    { id = "b_high",      board = "B", hand_type = "High Card",        level_boost = 5 },
    { id = "b_pair",      board = "B", hand_type = "Pair",             level_boost = 4 },
    { id = "b_twopair",   board = "B", hand_type = "Two Pair",         level_boost = 3 },
    { id = "b_three",     board = "B", hand_type = "Three of a Kind",  level_boost = 3 },
    { id = "b_straight",  board = "B", hand_type = "Straight",         level_boost = 2 },
    { id = "b_flush",     board = "B", hand_type = "Flush",            level_boost = 2 },
    { id = "b_fullhouse", board = "B", hand_type = "Full House",       level_boost = 2 },
    { id = "b_four",      board = "B", hand_type = "Four of a Kind",   level_boost = 1 },

    -- Board C
    { id = "c_high",      board = "C", hand_type = "High Card",        level_boost = 5 },
    { id = "c_pair",      board = "C", hand_type = "Pair",             level_boost = 4 },
    { id = "c_twopair",   board = "C", hand_type = "Two Pair",         level_boost = 3 },
    { id = "c_three",     board = "C", hand_type = "Three of a Kind",  level_boost = 3 },
    { id = "c_straight",  board = "C", hand_type = "Straight",         level_boost = 2 },
    { id = "c_flush",     board = "C", hand_type = "Flush",            level_boost = 2 },
    { id = "c_fullhouse", board = "C", hand_type = "Full House",       level_boost = 2 },
    { id = "c_four",      board = "C", hand_type = "Four of a Kind",   level_boost = 1 },

    -- Board D
    { id = "d_high",      board = "D", hand_type = "High Card",        level_boost = 5 },
    { id = "d_pair",      board = "D", hand_type = "Pair",             level_boost = 3 },
    { id = "d_twopair",   board = "D", hand_type = "Two Pair",         level_boost = 3 },
    { id = "d_three",     board = "D", hand_type = "Three of a Kind",  level_boost = 3 },
    { id = "d_straight",  board = "D", hand_type = "Straight",         level_boost = 2 },
    { id = "d_flush",     board = "D", hand_type = "Flush",            level_boost = 2 },
    { id = "d_fullhouse", board = "D", hand_type = "Full House",       level_boost = 2 },
    { id = "d_four",      board = "D", hand_type = "Four of a Kind",   level_boost = 1 },
}

-- Active gambits: list of { id, board, hand_type, level_boost, joker_ref }
Gambit.active = {}

-- ============================================================
-- ACTIVATE / DEACTIVATE
-- ============================================================

function Gambit.activate(card, gambit_id)
    -- Look up template
    local template = nil
    for _, t in ipairs(Gambit.templates) do
        if t.id == gambit_id then template = t; break end
    end
    if not template then
        print("[TG] Gambit.activate: unknown id " .. tostring(gambit_id))
        return false
    end

    -- Avoid double-activation for the same card
    for _, g in ipairs(Gambit.active) do
        if g.joker_ref == card then return false end
    end

    table.insert(Gambit.active, {
        id         = template.id,
        board      = template.board,
        hand_type  = template.hand_type,
        level_boost = template.level_boost,
        joker_ref  = card,
    })

    print(string.format("[TG] Gambit activated: %s → Board %s locks to %s (+%d)",
        gambit_id, template.board, template.hand_type, template.level_boost))
    return true
end

function Gambit.deactivate(card)
    for i, g in ipairs(Gambit.active) do
        if g.joker_ref == card then
            print(string.format("[TG] Gambit deactivated: Board %s %s", g.board, g.hand_type))
            table.remove(Gambit.active, i)
            return true
        end
    end
    return false
end

-- ============================================================
-- QUERY
-- ============================================================

-- Returns true if the hand type is allowed on the given board.
-- If there is no active gambit for the board, all hands are allowed.
function Gambit.is_hand_allowed(board_id, hand_type)
    local locked_to = nil
    for _, g in ipairs(Gambit.active) do
        if g.board == board_id then
            locked_to = g.hand_type
            break
        end
    end
    if locked_to == nil then return true end  -- no lock on this board
    return locked_to == hand_type
end

-- Returns the level boost for playing hand_type on board_id (0 if none).
function Gambit.get_level_boost(board_id, hand_type)
    for _, g in ipairs(Gambit.active) do
        if g.board == board_id and g.hand_type == hand_type then
            return g.level_boost
        end
    end
    return 0
end

-- ============================================================
-- ASSIGN RANDOM
-- Pick a gambit template for the shop. Weighted toward boards
-- with fewer active gambits. Dynamically iterates TG.BOARD_IDS.
-- ============================================================

function Gambit.assign_random()
    -- Count active gambits per board
    local counts = {}
    for _, id in ipairs(TG.BOARD_IDS) do counts[id] = 0 end
    for _, g in ipairs(Gambit.active) do
        if counts[g.board] ~= nil then
            counts[g.board] = counts[g.board] + 1
        end
    end

    -- Find board(s) with the fewest gambits
    local min_count = math.huge
    for _, id in ipairs(TG.BOARD_IDS) do
        if counts[id] < min_count then min_count = counts[id] end
    end
    local candidates = {}
    for _, id in ipairs(TG.BOARD_IDS) do
        if counts[id] == min_count then table.insert(candidates, id) end
    end

    -- Pick a board
    local board_id = candidates[math.random(#candidates)]

    -- Find available (not-already-active) templates for that board
    local available = {}
    for _, t in ipairs(Gambit.templates) do
        if t.board == board_id then
            local already = false
            for _, g in ipairs(Gambit.active) do
                if g.board == board_id and g.hand_type == t.hand_type then
                    already = true; break
                end
            end
            if not already then table.insert(available, t) end
        end
    end

    if #available == 0 then return nil end
    return available[math.random(#available)]
end

return Gambit
