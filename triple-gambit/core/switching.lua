--[[
    TRIPLE GAMBIT - core/switching.lua

    Free board switching. No commit/preview system. No switch cost.
    Boards: A (key 1), B (key 2), C (key 3), D (key 4).

    execute_switch uses Balatro's CardArea methods (remove_card / emplace)
    for all card movement so that mod hooks (Blueprint, HandyMod, etc.) fire.
]]

local Switching = {}

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
-- EXECUTE SWITCH
-- Spec §3.2 — eight steps in order.
-- ============================================================

function Switching.execute_switch(from_id, to_id)
    if from_id == to_id then return false end

    local from_board = TG:get_board(from_id)
    local to_board   = TG:get_board(to_id)
    if not (from_board and to_board) then
        print("[TG] execute_switch: invalid board id")
        return false
    end

    -- ── Step 1: Return from-board's hand back to its draw pile ─────────────
    -- Remove each card from G.hand via CardArea:remove_card(), then put its
    -- key back in from_board.draw_keys.
    if G and G.hand then
        -- Snapshot the list before mutating it
        local leaving = {}
        for _, card in ipairs(G.hand.cards or {}) do
            table.insert(leaving, card)
        end
        for _, card in ipairs(leaving) do
            G.hand:remove_card(card)
            -- Return key to draw pile (not discard — preserves for next switch)
            local key = from_board:card_key(card)
            if key then
                from_board:discard_key(key)           -- removes from hand_keys
                table.insert(from_board.draw_keys, key)  -- put in draw, not discard
                -- Undo the discard_key side-effect on discard_keys
                for i = #from_board.discard_keys, 1, -1 do
                    if from_board.discard_keys[i] == key then
                        table.remove(from_board.discard_keys, i)
                        break
                    end
                end
            end
        end
    end

    -- ── Step 2: Snapshot Balatro's resource counters into from-board ────────
    if G and G.GAME and G.GAME.current_round then
        from_board.hands_remaining    = G.GAME.current_round.hands_left
                                     or from_board.hands_remaining
        from_board.discards_remaining = G.GAME.current_round.discards_left
                                     or from_board.discards_remaining
    end

    -- ── Step 3: Shuffle + draw for target board ─────────────────────────────
    -- draw_hand_keys() shuffles then draws
    to_board:draw_hand_keys()

    -- ── Step 4: Resolve keys to Card objects ────────────────────────────────
    local new_cards = to_board:keys_to_cards()

    -- ── Step 5: Emplace target board's cards into G.hand ────────────────────
    if G and G.hand then
        for _, card in ipairs(new_cards) do
            G.hand:emplace(card)
        end
    end

    -- ── Step 6: Swap jokers ─────────────────────────────────────────────────
    if G and G.jokers then
        local current_jokers = {}
        for _, card in ipairs(G.jokers.cards or {}) do
            table.insert(current_jokers, card)
        end
        for _, card in ipairs(current_jokers) do
            G.jokers:remove_card(card)
        end
        for _, card in ipairs(to_board.jokers) do
            G.jokers:emplace(card)
        end
    end

    -- ── Step 7: Sync money ───────────────────────────────────────────────────
    if G and G.GAME then
        G.GAME.dollars = to_board.money
    end

    -- ── Step 8: Sync resources ───────────────────────────────────────────────
    if G and G.GAME and G.GAME.current_round then
        G.GAME.current_round.hands_left    = to_board.hands_remaining
        G.GAME.current_round.discards_left = to_board.discards_remaining
    end

    TG:set_active_board(to_id)

    print(string.format("[TG] Switched: %s → %s", from_id, to_id))
    return true
end

-- ============================================================
-- PERFORM SWITCH  — called from key handler
-- No commit/preview logic. Free switching.
-- ============================================================

function Switching.perform_switch(target_id)
    if not TG.initialized then return end

    -- Only allow switching during play states
    if not (G and G.STATE and G.STATES) then return end
    if G.STATE ~= G.STATES.SELECTING_HAND
    and G.STATE ~= G.STATES.DRAW_TO_HAND then
        return
    end

    local from_id = TG.active_board_id
    if target_id == from_id then return end

    local target_board = TG:get_board(target_id)
    if not target_board then return end

    if TG.UI and TG.UI.BoardTransition then
        pcall(function()
            TG.UI.BoardTransition.trigger_switch(from_id, target_id)
        end)
    end

    Switching.execute_switch(from_id, target_id)
end

-- ============================================================
-- KEY HANDLER — called from love.keypressed
-- ============================================================

function Switching.handle_key(key)
    local target_id = KEY_TO_BOARD[key]
    if target_id then
        Switching.perform_switch(target_id)
    end
end

return Switching
