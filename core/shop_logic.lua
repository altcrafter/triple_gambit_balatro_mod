--[[
    TRIPLE GAMBIT - core/shop_logic.lua
    Shop tab system. Per-board money and joker routing.
    Each board gets its own shop tab. Purchases are attributed to the active shop board.
]]

TG.Shop = TG.Shop or {}

TG.Shop.state = {
    is_open       = false,
    active_board_id = nil,
    joker_pool    = {},
}

-- ============================================================
-- LIFECYCLE
-- ============================================================

function TG.Shop.generate()
    TG.Shop.state.is_open = true
    TG.Shop.state.active_board_id = TG.entering_shop_board or TG.active_board_id

    -- Tag shop jokers with random gambit assignments
    if G and G.shop_jokers and G.shop_jokers.cards then
        for _, card in ipairs(G.shop_jokers.cards) do
            if card and not card.tg_gambit_id then
                if TG.Gambit then
                    TG.Gambit.assign_random(card)
                end
            end
        end
    end

    print(string.format("[TG] Shop opened. Active board: %s", TG.Shop.state.active_board_id))
end

function TG.Shop.close()
    TG.Shop.state.is_open       = false
    TG.Shop.state.active_board_id = nil
end

function TG.Shop.set_active_board(board_id)
    TG.Shop.state.active_board_id = board_id
end

-- ============================================================
-- BUY HOOK
-- Routes joker purchases to the correct board.
-- ============================================================

function TG.Shop.install_buy_hook()
    if not G or not G.FUNCS then return end
    if G.FUNCS._tg_buy_hooked then return end

    local orig_buy = G.FUNCS.buy_from_shop
    if not orig_buy then return end

    G.FUNCS.buy_from_shop = function(e, ...)
        local args = { ... }
        local result = orig_buy(e, unpack(args))

        -- After purchase: attribute to the active shop board
        if TG.initialized and TG.Shop.state.is_open then
            local board_id = TG.Shop.state.active_board_id or TG.active_board_id
            local board    = TG:get_board(board_id)
            if board and G.GAME then
                board.money = G.GAME.dollars
            end

            -- If a joker was purchased, register it with JokerBridge and assign board
            if e and e.card and e.card.config and e.card.config.center
            and e.card.config.center.set == "Joker" then
                local card = e.card
                card.tg_board_id = board_id
                if TG.JokerBridge then
                    TG.JokerBridge.register_joker(card, board_id)
                end
                -- Add to board's joker list
                if board then
                    table.insert(board.jokers, card)
                end
                -- Activate gambit if tagged
                if card.tg_gambit_id and TG.Gambit then
                    TG.Gambit.activate(card, card.tg_gambit_id)
                end
            end
        end

        return result
    end

    G.FUNCS._tg_buy_hooked = true
    print("[TG] Buy hook installed.")
end

-- ============================================================
-- SELL HOOK
-- Routes sell money to the correct board and removes joker from board list.
-- ============================================================

function TG.Shop.install_sell_hook()
    if not G or not G.FUNCS then return end
    if G.FUNCS._tg_sell_hooked then return end

    local orig_sell = G.FUNCS.sell_card
    if not orig_sell then return end

    G.FUNCS.sell_card = function(e, ...)
        local args = { ... }

        -- Before sell: identify which board owns this joker
        local card     = e and e.card
        local board_id = card and TG.JokerBridge and TG.JokerBridge.get_joker_board(card)
        local board    = board_id and TG:get_board(board_id)

        local dollars_before = (G.GAME and G.GAME.dollars) or 0
        local result = orig_sell(e, unpack(args))
        local dollars_after  = (G.GAME and G.GAME.dollars) or 0

        -- Route sell money to the owning board
        if board and dollars_after > dollars_before then
            board:add_money(dollars_after - dollars_before)
            G.GAME.dollars = board.money
        end

        -- Remove joker from board's list
        if board and card then
            for i = #board.jokers, 1, -1 do
                if board.jokers[i] == card then
                    table.remove(board.jokers, i)
                    break
                end
            end
            if TG.JokerBridge then TG.JokerBridge.unregister_joker(card) end
            if TG.Gambit then TG.Gambit.deactivate(card) end
        end

        return result
    end

    G.FUNCS._tg_sell_hooked = true
    print("[TG] Sell hook installed.")
end

return TG.Shop
