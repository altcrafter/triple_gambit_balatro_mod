--[[
    TRIPLE GAMBIT - core/switching.lua
    Board switching logic. Free switching (no resource cost).
    Key-based deck system + CardArea methods for all card movement.
    Board D support: key "4" → board "D".
]]

TG.Switching = TG.Switching or {}

-- ============================================================
-- KEY MAP
-- ============================================================

local KEY_TO_BOARD = {
    ["1"] = "A",
    ["2"] = "B",
    ["3"] = "C",
    ["4"] = "D",
}

-- ============================================================
-- PERFORM SWITCH (entry point from keypressed)
-- ============================================================

function TG.Switching.handle_key(key)
    local target_id = KEY_TO_BOARD[key]
    if not target_id then return end
    if not TG.boards[target_id] then return end  -- Board D may not exist in 3-board configs

    local allowed_states = {
        [G.STATES.SELECTING_HAND] = true,
        [G.STATES.DRAW_TO_HAND]   = true,
    }
    if not (G and G.STATE and allowed_states[G.STATE]) then return end

    if target_id == TG.active_board_id then return end

    TG.Switching.execute_switch(target_id)
end

-- ============================================================
-- EXECUTE SWITCH
-- All card movement goes through CardArea methods.
-- ============================================================

function TG.Switching.execute_switch(to_id)
    local from_id    = TG.active_board_id
    if from_id == to_id then return end

    local from_board = TG:get_board(from_id)
    local to_board   = TG:get_board(to_id)
    if not from_board or not to_board then return end

    -- ── 1. Save from-board's hand: return G.hand cards to draw ──
    if G.hand and G.hand.cards then
        for i = #G.hand.cards, 1, -1 do
            local card = G.hand.cards[i]
            local key  = from_board:card_key(card)
            if key then
                from_board:return_to_draw(key)
            end
            G.hand:remove_card(card)
        end
    end

    -- ── 2. Save from-board's Balatro resource counters ──
    if G.GAME and G.GAME.current_round then
        from_board.hands_remaining    = G.GAME.current_round.hands_left    or from_board.hands_remaining
        from_board.discards_remaining = G.GAME.current_round.discards_left or from_board.discards_remaining
    end

    -- ── 3. Swap jokers via CardArea methods ──
    if G.jokers and G.jokers.cards then
        -- Save current G.jokers back to from_board (captures pack jokers not yet tracked)
        from_board.jokers = {}
        for _, card in ipairs(G.jokers.cards) do
            table.insert(from_board.jokers, card)
        end
        -- Remove and load to_board's jokers
        for i = #G.jokers.cards, 1, -1 do
            G.jokers:remove_card(G.jokers.cards[i])
        end
        for _, joker in ipairs(to_board.jokers) do
            TG.Switching._emplace(G.jokers, joker)
        end
    end

    -- ── 4. Draw to-board's hand ──
    to_board:shuffle_draw_keys()
    to_board:draw_hand_keys()
    local hand_cards = to_board:keys_to_cards()
    for _, card in ipairs(hand_cards) do
        TG.Switching._emplace(G.hand, card)
    end

    -- ── 5. Sync to-board's state into Balatro ──
    if G.GAME then
        G.GAME.dollars = to_board.money
    end
    if G.GAME and G.GAME.current_round then
        G.GAME.current_round.hands_left    = to_board.hands_remaining
        G.GAME.current_round.discards_left = to_board.discards_remaining
    end

    -- ── 6. Update active board ──
    TG.active_board_id = to_id

    -- ── 7. Fire visual events (Bacon's APIs, if loaded) ──
    if TG.Kinetics then
        TG.Kinetics.glitch(1.0)
        TG.Kinetics.shake(4, 2, 0.2)
    end
    if TG.UI and TG.UI.BoardTransition then
        TG.UI.BoardTransition.trigger_switch(from_id, to_id)
    end
    if TG.UI and TG.UI.CardDeal then
        TG.UI.CardDeal.trigger()
    end
    if TG.UI and TG.UI.Atmosphere then
        TG.UI.Atmosphere.on_board_switch(to_id)
    end

    print(string.format("[TG] Switched: %s → %s", from_id, to_id))
end

-- ============================================================
-- CARDAREA EMPLACE HELPER
-- Tries multiple method names for compatibility.
-- ============================================================

function TG.Switching._emplace(area, card)
    if not area or not card then return end
    -- Try emplace first (LÖVE2D CardArea standard)
    if area.emplace then
        area:emplace(card)
    elseif area.add_card then
        area:add_card(card)
    elseif area.insert_card then
        area:insert_card(card)
    else
        -- Last resort fallback (breaks mod interop but keeps the game running)
        table.insert(area.cards, card)
    end
end

return TG.Switching
