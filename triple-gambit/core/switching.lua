--[[
    TRIPLE GAMBIT - core/switching.lua
    Free board switching. Keys 1/2/3/4 → Boards A/B/C/D.

    Phase 1 changes vs source:
      - get_switch_type() DELETED (free switching only — no commit/preview system).
      - execute_switch() rewritten:
          · Standalone deck operations removed (from_board.deck.hand, redraw_fresh_hand).
          · Key system is authoritative.
          · Saves Balatro's resource counters into from_board on switch.
          · Syncs to_board's resources back into Balatro's counters.
      - perform_switch(): removed is_beaten / is_cleared guards (cleared boards are
          still reachable — player may need to inspect score or switch back).
          Dead boards still blocked.
      - handle_key(): added "4" → "D".
      - UI feedback (animate_switch, show_switch_error) kept from source.
]]

TG = TG or {}

TG.Switching = {}

-- ============================================================
-- MAIN SWITCH FUNCTION
-- ============================================================

--- Attempt to switch to a target board.
--- @param target_id  string  Board ID to switch to ("A", "B", "C", or "D")
--- @return boolean   success
--- @return string    message
function TG.Switching.perform_switch(target_id)
    local current_board = TG:get_active_board()

    -- Validate target board
    local target_board = TG:get_board(target_id)
    if not target_board then
        return false, "Invalid board ID: " .. tostring(target_id)
    end
    if target_board.is_dead then
        return false, "Board " .. target_id .. " is dead"
    end
    if target_id == current_board.id then
        return false, "Already on Board " .. target_id
    end

    -- Execute switch
    TG.Switching.execute_switch(current_board, target_board)

    -- Set active board
    TG._prev_board_id = TG.active_board_id
    TG:set_active_board(target_id)

    -- Sync per-board resources to Balatro
    TG:sync_board_resources_to_balatro()

    local msg = string.format("[TG] Free switch: Board %s → Board %s",
        current_board.id, target_id)
    print(msg)

    return true, msg
end

-- ============================================================
-- EXECUTE SWITCH
-- ============================================================

--- Perform the actual board swap using the key system.
--- Standalone deck operations removed; G.hand.cards and G.jokers.cards
--- are set directly (same pattern as source — CardArea migration deferred).
---
--- Step order per spec §3.2:
---   1. Return from-board's hand keys to its draw pile.
---   2. Save Balatro's resource counters into from_board.
---   3. Shuffle to_board's draw_keys, draw fresh hand_keys.
---   4. Map hand_keys to Card objects.
---   5. Set G.hand.cards.
---   6. Swap G.jokers.cards.
---   7. Sync money.
---   8. Sync resources (handled by caller via sync_board_resources_to_balatro).
function TG.Switching.execute_switch(from_board, to_board)
    -- Step 1: Return from-board's hand keys back to its draw pile
    for _, k in ipairs(from_board.hand_keys or {}) do
        table.insert(from_board.draw_keys, k)
    end
    from_board.hand_keys = {}

    -- Step 2: Save Balatro's live resource counters into from_board
    if G and G.GAME and G.GAME.current_round then
        from_board.hands_remaining    = G.GAME.current_round.hands_left
                                     or from_board.hands_remaining
        from_board.discards_remaining = G.GAME.current_round.discards_left
                                     or from_board.discards_remaining
    end

    -- Step 3: Shuffle to_board's draw_keys and draw fresh hand
    if to_board.deck_keys and #to_board.deck_keys > 0 then
        to_board:draw_hand_keys(to_board.hand_size)
    elseif G and G.deck and G.deck.cards and #G.deck.cards > 0 then
        -- Lazy init on first switch to this board
        to_board:init_deck_keys()
        to_board:draw_hand_keys(to_board.hand_size)
    end

    -- Step 4 + 5: Resolve keys → cards, set G.hand.cards
    if G and G.hand then
        local hand_cards = to_board:keys_to_cards(to_board.hand_keys)
        if #hand_cards > 0 then
            G.hand.cards = hand_cards
        end
    end

    -- Step 6: Swap G.jokers.cards to the target board's joker lineup
    if G and G.jokers then
        G.jokers.cards = to_board.jokers
    end

    -- Step 7: Sync money
    if G and G.GAME then
        G.GAME.dollars = to_board.money
    end
end

-- ============================================================
-- KEYBOARD INPUT HANDLER
-- ============================================================

--- Called from input system. Handles 1/2/3/4 key presses for switching.
function TG.Switching.handle_key(key)
    -- Allow switching during card selection or just after drawing
    local ok_state = G.STATE == G.STATES.SELECTING_HAND
                  or G.STATE == G.STATES.DRAW_TO_HAND
                  or (G.STATES.HAND and G.STATE == G.STATES.HAND)  -- compat
    if not ok_state then return end

    local board_map = { ["1"] = "A", ["2"] = "B", ["3"] = "C", ["4"] = "D" }
    local target_id = board_map[key]
    if not target_id then return end

    local success, msg = TG.Switching.perform_switch(target_id)

    if not success then
        TG.Switching.show_switch_error(msg)
    else
        TG.Switching.animate_switch(TG.active_board_id)
        if TG.Audio then TG.Audio.play("switch_board") end
    end
end

-- ============================================================
-- UI FEEDBACK
-- ============================================================

function TG.Switching.show_switch_error(msg)
    print("[TG] Switch error: " .. msg)
    if TG.Audio then TG.Audio.play("action_blocked") end
    if TG.UI and TG.UI.ResourceDisplay then
        TG.UI.ResourceDisplay.trigger_shake("switches")
    end
end

--- Trigger switch animation.
--- @param to_id    string  Board being switched TO (already active)
--- @param from_id  string  (optional) Board just left
function TG.Switching.animate_switch(to_id, from_id)
    from_id = from_id or TG._prev_board_id or to_id

    if TG.UI and TG.UI.BoardTransition then
        TG.UI.BoardTransition.trigger_switch(from_id, to_id)
    end

    TG.transition = {
        active   = true,
        type     = "switch",
        timer    = 0,
        duration = TG.CONFIG.ANIM_SWITCH_FADE_OUT + TG.CONFIG.ANIM_SWITCH_FADE_IN,
        callback = nil,
    }
end

return TG.Switching
