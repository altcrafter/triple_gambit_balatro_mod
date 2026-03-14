--[[
    TRIPLE GAMBIT - core/gambit.lua
    Joker gambits: board locks and hand type boosts.

    Each joker can have a gambit that locks a specific board to one hand type
    and boosts that hand type's level. Buying activates. Selling removes.

    Phase 1 changes vs source:
      - Board D templates added (8 entries, per spec §3.6).
      - assign_random() fixed to iterate TG.BOARD_IDS dynamically instead of
        hardcoding { A=0, B=0, C=0 } — now works with any board count.
      - Weighted random pick logic kept from source (not simplified away).
      - All other methods kept verbatim from source.
]]

TG = TG or {}
TG.Gambit = {}

-- ============================================================
-- GAMBIT TEMPLATES
-- ============================================================

-- Keyed by gambit_id.
-- board: which board gets locked ("A", "B", "C", "D")
-- hand_type: Balatro hand type string
-- level_boost: how many levels the hand type gains
TG.Gambit.TEMPLATES = {
    -- Board A locks
    { id = "a_pair",      board = "A", hand_type = "Pair",             level_boost = 3 },
    { id = "a_twopair",   board = "A", hand_type = "Two Pair",         level_boost = 3 },
    { id = "a_three",     board = "A", hand_type = "Three of a Kind",  level_boost = 3 },
    { id = "a_straight",  board = "A", hand_type = "Straight",         level_boost = 2 },
    { id = "a_flush",     board = "A", hand_type = "Flush",            level_boost = 2 },
    { id = "a_fullhouse", board = "A", hand_type = "Full House",       level_boost = 2 },
    { id = "a_four",      board = "A", hand_type = "Four of a Kind",   level_boost = 1 },
    { id = "a_high",      board = "A", hand_type = "High Card",        level_boost = 5 },

    -- Board B locks
    { id = "b_pair",      board = "B", hand_type = "Pair",             level_boost = 3 },
    { id = "b_twopair",   board = "B", hand_type = "Two Pair",         level_boost = 3 },
    { id = "b_three",     board = "B", hand_type = "Three of a Kind",  level_boost = 3 },
    { id = "b_straight",  board = "B", hand_type = "Straight",         level_boost = 2 },
    { id = "b_flush",     board = "B", hand_type = "Flush",            level_boost = 2 },
    { id = "b_fullhouse", board = "B", hand_type = "Full House",       level_boost = 2 },
    { id = "b_four",      board = "B", hand_type = "Four of a Kind",   level_boost = 1 },
    { id = "b_high",      board = "B", hand_type = "High Card",        level_boost = 5 },

    -- Board C locks
    { id = "c_pair",      board = "C", hand_type = "Pair",             level_boost = 3 },
    { id = "c_twopair",   board = "C", hand_type = "Two Pair",         level_boost = 3 },
    { id = "c_three",     board = "C", hand_type = "Three of a Kind",  level_boost = 3 },
    { id = "c_straight",  board = "C", hand_type = "Straight",         level_boost = 2 },
    { id = "c_flush",     board = "C", hand_type = "Flush",            level_boost = 2 },
    { id = "c_fullhouse", board = "C", hand_type = "Full House",       level_boost = 2 },
    { id = "c_four",      board = "C", hand_type = "Four of a Kind",   level_boost = 1 },
    { id = "c_high",      board = "C", hand_type = "High Card",        level_boost = 5 },

    -- Board D locks (per spec §3.6)
    { id = "d_pair",      board = "D", hand_type = "Pair",             level_boost = 3 },
    { id = "d_twopair",   board = "D", hand_type = "Two Pair",         level_boost = 3 },
    { id = "d_three",     board = "D", hand_type = "Three of a Kind",  level_boost = 3 },
    { id = "d_straight",  board = "D", hand_type = "Straight",         level_boost = 2 },
    { id = "d_flush",     board = "D", hand_type = "Flush",            level_boost = 2 },
    { id = "d_fullhouse", board = "D", hand_type = "Full House",       level_boost = 2 },
    { id = "d_four",      board = "D", hand_type = "Four of a Kind",   level_boost = 1 },
    { id = "d_high",      board = "D", hand_type = "High Card",        level_boost = 5 },
}

-- ============================================================
-- ACTIVE GAMBIT STATE
-- ============================================================

-- Active gambits: list of { gambit_id, joker_ref, board, hand_type, level_boost }
TG.Gambit.active = {}

-- ============================================================
-- ACTIVATION / DEACTIVATION
-- ============================================================

--- Activate a gambit when a joker is bought.
--- @param joker     table   The joker card object
--- @param gambit_id string  ID from TEMPLATES
function TG.Gambit.activate(joker, gambit_id)
    local template = TG.Gambit.get_template(gambit_id)
    if not template then
        print("[TG] Gambit: unknown id " .. tostring(gambit_id))
        return
    end

    table.insert(TG.Gambit.active, {
        gambit_id   = gambit_id,
        joker_ref   = joker,
        board       = template.board,
        hand_type   = template.hand_type,
        level_boost = template.level_boost,
    })

    print(string.format("[TG] Gambit activated: %s → Board %s locked to %s (+%d levels)",
        gambit_id, template.board, template.hand_type, template.level_boost))
end

--- Deactivate a gambit when a joker is sold or destroyed.
--- Matches by joker_ref identity when available (normal play), or by
--- gambit_id when joker_ref is nil (restored from save — see deserialize).
--- @param joker table  The joker being removed
function TG.Gambit.deactivate(joker)
    for i = #TG.Gambit.active, 1, -1 do
        local g = TG.Gambit.active[i]
        local match = (g.joker_ref == joker)
            or (g.joker_ref == nil and joker.tg_gambit_id == g.gambit_id)
        if match then
            table.remove(TG.Gambit.active, i)
            print(string.format("[TG] Gambit deactivated: %s (Board %s unlocked from %s)",
                g.gambit_id, g.board, g.hand_type))
        end
    end
end

-- ============================================================
-- QUERIES
-- ============================================================

--- Get all active locks for a board.
--- Returns list of { hand_type, level_boost } or empty table if unlocked.
function TG.Gambit.get_locks(board_id)
    local locks = {}
    for _, g in ipairs(TG.Gambit.active) do
        if g.board == board_id then
            table.insert(locks, {
                hand_type   = g.hand_type,
                level_boost = g.level_boost,
            })
        end
    end
    return locks
end

--- Check if a board is locked to specific hand types.
function TG.Gambit.is_locked(board_id)
    for _, g in ipairs(TG.Gambit.active) do
        if g.board == board_id then return true end
    end
    return false
end

--- Check if a hand type is allowed on a board.
--- If the board has no locks, everything is allowed.
--- If the board has locks, ONLY the locked hand types are allowed.
function TG.Gambit.is_hand_allowed(board_id, hand_type)
    local locks = TG.Gambit.get_locks(board_id)
    if #locks == 0 then return true end  -- no locks = everything allowed
    for _, lock in ipairs(locks) do
        if lock.hand_type == hand_type then return true end
    end
    return false
end

--- Get total level boost for a hand type on a board.
function TG.Gambit.get_level_boost(board_id, hand_type)
    local total = 0
    for _, g in ipairs(TG.Gambit.active) do
        if g.board == board_id and g.hand_type == hand_type then
            total = total + g.level_boost
        end
    end
    return total
end

--- Get a template by ID.
function TG.Gambit.get_template(gambit_id)
    for _, t in ipairs(TG.Gambit.TEMPLATES) do
        if t.id == gambit_id then return t end
    end
    return nil
end

--- Assign a random gambit to a joker.
--- Weighted toward boards with fewer active gambits for better balance.
--- Iterates TG.BOARD_IDS dynamically — works with any board count.
--- @param joker table  The joker card object
function TG.Gambit.assign_random(joker)
    -- Count active gambits per board (dynamic — no hardcoded board list)
    local counts = {}
    for _, id in ipairs(TG.BOARD_IDS) do counts[id] = 0 end
    for _, g in ipairs(TG.Gambit.active) do
        if counts[g.board] ~= nil then
            counts[g.board] = counts[g.board] + 1
        end
    end

    -- Find max count
    local max_count = 0
    for _, c in pairs(counts) do
        if c > max_count then max_count = c end
    end

    -- Build weighted pool: boards with fewer gambits get higher weight
    local pool    = {}
    local weights = {}
    for _, t in ipairs(TG.Gambit.TEMPLATES) do
        local w = max_count - (counts[t.board] or 0) + 1  -- min weight = 1
        table.insert(pool, t)
        table.insert(weights, w)
    end

    -- Weighted random pick
    local total = 0
    for _, w in ipairs(weights) do total = total + w end
    local r   = math.random() * total
    local cum = 0
    local chosen = pool[1]
    for i, t in ipairs(pool) do
        cum = cum + weights[i]
        if r <= cum then chosen = t; break end
    end

    joker.tg_gambit_id = chosen.id
    return chosen
end

-- ============================================================
-- SERIALIZATION
-- ============================================================

function TG.Gambit.serialize()
    local data = {}
    for _, g in ipairs(TG.Gambit.active) do
        table.insert(data, {
            gambit_id   = g.gambit_id,
            board       = g.board,
            hand_type   = g.hand_type,
            level_boost = g.level_boost,
        })
    end
    return data
end

function TG.Gambit.deserialize(data)
    TG.Gambit.active = {}
    if not data then return end
    for _, entry in ipairs(data) do
        -- Attempt to re-link joker_ref from Balatro's live card objects.
        -- G.jokers may not be available yet (called before the run fully loads),
        -- so this is best-effort; deactivate() handles nil joker_ref via gambit_id.
        local ref = nil
        if G and G.jokers and G.jokers.cards then
            for _, card in ipairs(G.jokers.cards) do
                if card.tg_gambit_id == entry.gambit_id then
                    ref = card
                    break
                end
            end
        end
        table.insert(TG.Gambit.active, {
            gambit_id   = entry.gambit_id,
            joker_ref   = ref,
            board       = entry.board,
            hand_type   = entry.hand_type,
            level_boost = entry.level_boost,
        })
    end
end

return TG.Gambit
