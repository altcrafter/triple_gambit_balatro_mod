--[[
    TRIPLE GAMBIT - core/gambit.lua
    Hand-type lock + level boost system.
    Joker-gambits only (Phase 1). Ante-spanning system is in dormant/.
    Board D supported: 32 templates total (8 hand types × 4 boards).
]]

TG.Gambit = TG.Gambit or {}

-- ============================================================
-- TEMPLATES
-- 8 hand types × 4 boards = 32 templates.
-- Level boost is inversely proportional to hand rarity.
-- ============================================================

TG.Gambit.TEMPLATES = {
    -- Board A
    { id = "a_pair",      board = "A", hand_type = "Pair",            level_boost = 3 },
    { id = "a_twopair",   board = "A", hand_type = "Two Pair",        level_boost = 3 },
    { id = "a_three",     board = "A", hand_type = "Three of a Kind", level_boost = 3 },
    { id = "a_straight",  board = "A", hand_type = "Straight",        level_boost = 2 },
    { id = "a_flush",     board = "A", hand_type = "Flush",           level_boost = 2 },
    { id = "a_fullhouse", board = "A", hand_type = "Full House",      level_boost = 2 },
    { id = "a_four",      board = "A", hand_type = "Four of a Kind",  level_boost = 1 },
    { id = "a_high",      board = "A", hand_type = "High Card",       level_boost = 5 },
    -- Board B
    { id = "b_pair",      board = "B", hand_type = "Pair",            level_boost = 3 },
    { id = "b_twopair",   board = "B", hand_type = "Two Pair",        level_boost = 3 },
    { id = "b_three",     board = "B", hand_type = "Three of a Kind", level_boost = 3 },
    { id = "b_straight",  board = "B", hand_type = "Straight",        level_boost = 2 },
    { id = "b_flush",     board = "B", hand_type = "Flush",           level_boost = 2 },
    { id = "b_fullhouse", board = "B", hand_type = "Full House",      level_boost = 2 },
    { id = "b_four",      board = "B", hand_type = "Four of a Kind",  level_boost = 1 },
    { id = "b_high",      board = "B", hand_type = "High Card",       level_boost = 5 },
    -- Board C
    { id = "c_pair",      board = "C", hand_type = "Pair",            level_boost = 3 },
    { id = "c_twopair",   board = "C", hand_type = "Two Pair",        level_boost = 3 },
    { id = "c_three",     board = "C", hand_type = "Three of a Kind", level_boost = 3 },
    { id = "c_straight",  board = "C", hand_type = "Straight",        level_boost = 2 },
    { id = "c_flush",     board = "C", hand_type = "Flush",           level_boost = 2 },
    { id = "c_fullhouse", board = "C", hand_type = "Full House",      level_boost = 2 },
    { id = "c_four",      board = "C", hand_type = "Four of a Kind",  level_boost = 1 },
    { id = "c_high",      board = "C", hand_type = "High Card",       level_boost = 5 },
    -- Board D
    { id = "d_pair",      board = "D", hand_type = "Pair",            level_boost = 3 },
    { id = "d_twopair",   board = "D", hand_type = "Two Pair",        level_boost = 3 },
    { id = "d_three",     board = "D", hand_type = "Three of a Kind", level_boost = 3 },
    { id = "d_straight",  board = "D", hand_type = "Straight",        level_boost = 2 },
    { id = "d_flush",     board = "D", hand_type = "Flush",           level_boost = 2 },
    { id = "d_fullhouse", board = "D", hand_type = "Full House",      level_boost = 2 },
    { id = "d_four",      board = "D", hand_type = "Four of a Kind",  level_boost = 1 },
    { id = "d_high",      board = "D", hand_type = "High Card",       level_boost = 5 },
}

-- Active gambits for this run: list of { id, board, hand_type, level_boost, joker_ref }
TG.Gambit.active = {}

-- ============================================================
-- TEMPLATE LOOKUP
-- ============================================================

function TG.Gambit.get_template(id)
    for _, t in ipairs(TG.Gambit.TEMPLATES) do
        if t.id == id then return t end
    end
    return nil
end

function TG.Gambit.templates_for_board(board_id)
    local result = {}
    for _, t in ipairs(TG.Gambit.TEMPLATES) do
        if t.board == board_id then
            table.insert(result, t)
        end
    end
    return result
end

-- ============================================================
-- ACTIVATE / DEACTIVATE
-- ============================================================

-- Activate a gambit from a joker card.
-- gambit_id: the template id string stored on the card.
function TG.Gambit.activate(joker_card, gambit_id)
    local template = TG.Gambit.get_template(gambit_id)
    if not template then return end

    -- Avoid double-activation
    for _, g in ipairs(TG.Gambit.active) do
        if g.joker_ref == joker_card then return end
    end

    table.insert(TG.Gambit.active, {
        id         = template.id,
        board      = template.board,
        hand_type  = template.hand_type,
        level_boost= template.level_boost,
        joker_ref  = joker_card,
    })

    print(string.format("[TG] Gambit activated: Board %s locked to %s (+%d)",
        template.board, template.hand_type, template.level_boost))
end

function TG.Gambit.deactivate(joker_card)
    for i = #TG.Gambit.active, 1, -1 do
        if TG.Gambit.active[i].joker_ref == joker_card then
            table.remove(TG.Gambit.active, i)
            return
        end
    end
end

-- ============================================================
-- QUERY
-- ============================================================

-- Returns true if the given hand type is allowed on this board.
-- A board with no gambit lock allows all hand types.
function TG.Gambit.is_hand_allowed(board_id, hand_type)
    for _, g in ipairs(TG.Gambit.active) do
        if g.board == board_id then
            -- Board is locked — only the locked hand type is allowed
            if g.hand_type ~= hand_type then
                return false
            end
        end
    end
    return true
end

-- Returns the level boost for playing hand_type on board_id.
function TG.Gambit.get_level_boost(board_id, hand_type)
    for _, g in ipairs(TG.Gambit.active) do
        if g.board == board_id and g.hand_type == hand_type then
            return g.level_boost
        end
    end
    return 0
end

-- Returns the active gambit entry for a board (or nil).
function TG.Gambit.get_for_board(board_id)
    for _, g in ipairs(TG.Gambit.active) do
        if g.board == board_id then return g end
    end
    return nil
end

-- ============================================================
-- SHOP ASSIGNMENT
-- Assign a random gambit template to a shop joker.
-- Weighted: boards with fewer active gambits get more shop tags.
-- ============================================================

function TG.Gambit.assign_random(joker_card, board_id)
    -- If board_id is provided, pick from that board's templates.
    -- Otherwise, weight by board gambit count.
    local target_board = board_id

    if not target_board then
        -- Count current gambits per board
        local counts = {}
        for _, id in ipairs(TG.BOARD_IDS) do counts[id] = 0 end
        for _, g in ipairs(TG.Gambit.active) do
            if counts[g.board] then
                counts[g.board] = counts[g.board] + 1
            end
        end

        -- Build weighted pool (boards with fewer gambits appear more often)
        local max_count = 0
        for _, c in pairs(counts) do
            if c > max_count then max_count = c end
        end

        local pool = {}
        for _, id in ipairs(TG.BOARD_IDS) do
            local weight = (max_count - counts[id]) + 1
            for _ = 1, weight do
                table.insert(pool, id)
            end
        end

        target_board = pool[math.random(#pool)]
    end

    -- Pick a random template for the selected board
    local templates = TG.Gambit.templates_for_board(target_board)
    if #templates == 0 then return end
    local t = templates[math.random(#templates)]

    -- Tag the card
    joker_card.tg_gambit_id = t.id
    print(string.format("[TG] Shop joker tagged: %s (Board %s, %s +%d)",
        t.id, t.board, t.hand_type, t.level_boost))
end

-- ============================================================
-- SERIALIZATION
-- ============================================================

function TG.Gambit.serialize()
    local data = {}
    for _, g in ipairs(TG.Gambit.active) do
        -- Store gambit_id on the joker card for deserialization
        if g.joker_ref then
            table.insert(data, {
                id    = g.id,
                board = g.board,
            })
        end
    end
    return data
end

return TG.Gambit
