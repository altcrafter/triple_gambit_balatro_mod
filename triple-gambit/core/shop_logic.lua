--[[
    Triple Gambit - Shop System
    Unified shop with board-tagged items, three money pools, and buy-for-board logic.
]]

TG = TG or {}

TG.Shop = {}

-- ============================================================
-- SHOP STATE
-- ============================================================

TG.Shop.state = {
    jokers = {},
    packs = {},
    voucher = nil,
    active_board_id = nil,
    is_open = false,
    reroll_count = 0,
    -- Set by "Buy for X" button before Balatro fires buy_from_shop.
    -- The buy hook reads and clears this to know which board is the target.
    pending_buy_board_id = nil,
}

local function safe_random(key)
    return math.random()
end

local function safe_random_element(t, key)
    if #t == 0 then return nil end
    return t[math.random(#t)]
end

-- ============================================================
-- SHOP GENERATION
-- ============================================================

--- Tag Balatro's already-generated shop items with board metadata.
--- We NEVER create new card objects here — Balatro has already populated
--- G.shop_jokers, G.shop_booster, and G.shop_vouchers. Creating additional
--- cards caused duplicate/ghost items on screen.
function TG.Shop.generate()
    local state = TG.Shop.state
    state.is_open = true
    state.active_board_id = TG.entering_shop_board or TG.active_board_id
    state.reroll_count = 0

    -- Sync G.GAME.dollars to the active board's money so Balatro's
    -- affordability checks and HUD reflect the correct board pool.
    TG.Shop.sync_dollars_to_board(state.active_board_id)

    -- Tag existing jokers
    state.jokers = {}
    if G and G.shop_jokers then
        for i, card in ipairs(G.shop_jokers.cards or {}) do
            table.insert(state.jokers, {
                card     = card,
                board_tag = TG.Shop.random_board_tag(),
                slot     = i,
                sold     = false,
            })
        end
    end

    -- Tag existing boosters/packs
    state.packs = {}
    if G and G.shop_booster then
        for i, card in ipairs(G.shop_booster.cards or {}) do
            table.insert(state.packs, {
                card     = card,
                board_tag = TG.Shop.random_board_tag(),
                slot     = i,
                sold     = false,
            })
        end
    end

    -- Tag existing voucher
    state.voucher = nil
    if G and G.shop_vouchers then
        local vcards = G.shop_vouchers.cards or {}
        if vcards[1] then
            state.voucher = {
                card = vcards[1],
                sold = false,
            }
        end
    end

    print("[TG] Shop tagged. Active board: " .. tostring(state.active_board_id)
        .. " | jokers=" .. #state.jokers
        .. " packs=" .. #state.packs
        .. " voucher=" .. tostring(state.voucher ~= nil))
end

--- Assign a random board tag.
function TG.Shop.random_board_tag()
    return TG.BOARD_IDS[math.random(#TG.BOARD_IDS)]
end

-- ============================================================
-- BUYING ITEMS
-- ============================================================

--- Buy a joker or pack for a specific board.
--- @param slot_type  string  "joker" or "pack"
--- @param slot_index number  1-based index in the slot list
--- @param buyer_id   string  Board ID that is paying ("A", "B", "C")
--- @param target_id  string  Board ID that receives the item
--- @return boolean   success
--- @return string    message
function TG.Shop.buy_item(slot_type, slot_index, buyer_id, target_id)
    local state = TG.Shop.state
    target_id = target_id or buyer_id  -- Default: buyer gets the item

    -- Get the slot list
    local slots
    if slot_type == "joker" then
        slots = state.jokers
    elseif slot_type == "pack" then
        slots = state.packs
    else
        return false, "Invalid slot type"
    end

    -- Validate slot
    local slot = slots[slot_index]
    if not slot or slot.sold then
        return false, "Slot empty or already sold"
    end

    -- Check gambit restriction: "Can't Spend Money This Ante"
    if TG.Shop.is_spending_blocked() then
        return false, "Cannot spend money this ante (gambit effect)"
    end

    local item = slot.card  -- card reference from Balatro's shop
    if not item then
        return false, "Slot has no card"
    end

    -- Get cost from Balatro card object
    local cost = item.cost or 0

    -- Check buyer board's money
    local buyer_board = TG:get_board(buyer_id)
    if not buyer_board:can_afford(cost) then
        return false, string.format("Board %s cannot afford $%d (has $%d)",
            buyer_id, cost, buyer_board.money)
    end

    -- Get target board
    local target_board = TG:get_board(target_id)

    -- For jokers: check if target board has room
    if slot_type == "joker" then
        if #target_board.jokers >= TG.CONFIG.MAX_JOKERS_PER_BOARD then
            return false, "Board " .. target_id .. " joker slots full"
        end
    end

    -- Deduct from TG board money pool, then mirror to G.GAME.dollars so
    -- Balatro's HUD stays accurate. We do NOT subtract from G.GAME.dollars
    -- separately — that would double-deduct, since generate() already loaded
    -- this board's money into G.GAME.dollars when the shop opened.
    buyer_board:spend_money(cost)
    TG.Shop.sync_dollars_to_board(buyer_board.id)

    if slot_type == "joker" then
        target_board:add_joker(item)
    elseif slot_type == "pack" then
        TG.Shop.open_pack_for_board(item, target_board)
    end

    slot.sold = true

    print(string.format("[TG] Board %s bought %s '%s' for Board %s ($%d)",
        buyer_id, slot_type, item.name or "Unknown", target_id, cost))

    return true, "Purchase successful"
end

--- Buy a voucher (universal, paid by active board).
--- @return boolean success
--- @return string  message
function TG.Shop.buy_voucher()
    local state = TG.Shop.state
    -- FIX ISSUE #9: also guard against state.voucher.item being nil —
    -- roll_voucher() returns nil when no vouchers are available.
    if not state.voucher or not state.voucher.card or state.voucher.sold then
        return false, "No voucher available"
    end

    if TG.Shop.is_spending_blocked() then
        return false, "Cannot spend money this ante (gambit effect)"
    end

    local vcard = state.voucher.card
    local cost = vcard.cost or 0
    local active_board = TG:get_board(state.active_board_id)

    if not active_board:can_afford(cost) then
        return false, string.format("Board %s cannot afford $%d", state.active_board_id, cost)
    end

    active_board:spend_money(cost)
    TG.Shop.sync_dollars_to_board(active_board.id)
    state.voucher.sold = true

    -- Apply voucher effect to all boards (universal)
    TG.Shop.apply_voucher(vcard)

    print(string.format("[TG] Voucher '%s' purchased by Board %s ($%d)",
        vcard.name or "Unknown", state.active_board_id, cost))

    return true, "Voucher purchased"
end

-- ============================================================
-- REROLL
-- ============================================================

--- Reroll shop contents. Paid by active board.
--- @return boolean success
--- @return string  message
function TG.Shop.reroll()
    local state = TG.Shop.state

    -- Check gambit restrictions
    if TG.Shop.is_spending_blocked() then
        return false, "Cannot spend money this ante"
    end
    if TG.Shop.is_reroll_blocked() then
        return false, "Reroll disabled this ante (gambit effect)"
    end

    local cost = TG.CONFIG.REROLL_COST
    local active_board = TG:get_board(state.active_board_id)

    if not active_board:can_afford(cost) then
        return false, string.format("Board %s cannot afford reroll ($%d)", state.active_board_id, cost)
    end

    active_board:spend_money(cost)
    state.reroll_count = state.reroll_count + 1

    -- Generate new jokers and packs (with new random tags)
    state.jokers = {}
    for i = 1, TG.CONFIG.SHOP_JOKER_SLOTS do
        table.insert(state.jokers, {
            item = TG.Shop.roll_joker(),
            board_tag = TG.Shop.random_board_tag(),
            slot = i,
            sold = false,
        })
    end

    state.packs = {}
    for i = 1, TG.CONFIG.SHOP_PACK_SLOTS do
        table.insert(state.packs, {
            item = TG.Shop.roll_pack(),
            board_tag = TG.Shop.random_board_tag(),
            slot = i,
            sold = false,
        })
    end

    -- Voucher may or may not change (standard Balatro logic)
    -- For simplicity, keep voucher the same on reroll

    print(string.format("[TG] Shop rerolled by Board %s ($%d)", state.active_board_id, cost))
    -- Re-tag the fresh items Balatro just created
    TG.Shop.generate()
    return true, "Rerolled"
end

-- ============================================================
-- ACTIVE BOARD SWITCHING (in shop)
-- ============================================================

--- Switch which board is "active" in the shop (affects voucher/reroll payment).
function TG.Shop.set_active_board(board_id)
    if TG:get_board(board_id) then
        TG.Shop.state.active_board_id = board_id
        TG.Shop.sync_dollars_to_board(board_id)
        print("[TG] Shop active board changed to: " .. board_id)
    end
end

--- Called by "Buy for X" button clicks in shop_ui.lua BEFORE Balatro fires buy_from_shop.
--- Records which board should receive the next purchase.
--- The buy hook reads and clears this to know the intended target board.
function TG.Shop.set_pending_buy_board(board_id)
    TG.Shop.state.pending_buy_board_id = board_id
    print("[TG] Pending buy board set to: " .. tostring(board_id))
end

-- ============================================================
-- SELLING JOKERS
-- ============================================================

--- Sell a joker from a specific board.
--- @param board_id  string  Board that owns the joker
--- @param joker_idx number  Index in the board's joker lineup
--- @return boolean success
function TG.Shop.sell_joker(board_id, joker_idx)
    -- Check gambit: "Can't Sell Jokers This Ante"
    if TG.Shop.is_selling_blocked() then
        return false, "Cannot sell jokers this ante (gambit effect)"
    end

    local board = TG:get_board(board_id)
    if not board then return false, "Invalid board" end

    local joker = board:remove_joker(joker_idx)
    if not joker then return false, "No joker at index" end

    local sell_value = joker.sell_value or joker.cost or 3
    board:add_money(sell_value)

    print(string.format("[TG] Board %s sold joker '%s' for $%d",
        board_id, joker.name or "Unknown", sell_value))

    return true, "Sold"
end

-- ============================================================
-- SHOP EXIT
-- ============================================================

function TG.Shop.close()
    TG.Shop.state.is_open = false

    -- Save any native Balatro spending back to active shop board first
    TG.Shop.sync_dollars_from_board(TG.Shop.state.active_board_id)

    -- Return to the board that entered the shop
    local return_board_id = TG.entering_shop_board or TG.active_board_id
    TG:set_active_board(return_board_id)

    -- Realign G.jokers.cards to the board we're returning to
    local return_board = TG:get_board(return_board_id)
    if return_board and G and G.jokers then
        G.jokers.cards = return_board.jokers
    end

    -- Clear so it doesn't go stale
    TG.entering_shop_board = nil

    print("[TG] Shop closed. Returning to Board " .. return_board_id)
end

-- ============================================================
-- DOLLAR SYNC HELPERS
-- ============================================================

--- Load a board's money into G.GAME.dollars so Balatro's HUD and
--- affordability checks reflect the correct board pool.
function TG.Shop.sync_dollars_to_board(board_id)
    if not G or not G.GAME then return end
    local board = TG:get_board(board_id)
    if not board then return end
    G.GAME.dollars = board.money
end

--- Write G.GAME.dollars back into a board's money pool.
--- Called before switching active board or on shop close.
function TG.Shop.sync_dollars_from_board(board_id)
    if not G or not G.GAME then return end
    local board = TG:get_board(board_id)
    if not board then return end
    board.money = G.GAME.dollars
end

-- ============================================================
-- BALATRO BUY HOOK — intercepts native purchases
-- ============================================================

--- Wrap Balatro's G.FUNCS.buy_from_shop so every purchase routes through
--- TG.Shop.buy_item rather than Balatro's default handler.
--- This prevents:
---   1. Jokers landing in G.jokers.cards (global) instead of a board's list.
---   2. G.GAME.dollars being deducted independently of TG's board money.
--- Call this once after Balatro's G.FUNCS is ready (e.g. from main.lua on_run_start).
function TG.Shop.install_buy_hook()
    if not G or not G.FUNCS then return end
    if G.FUNCS._tg_buy_hooked then return end  -- idempotent

    local original_buy = G.FUNCS.buy_from_shop
    G.FUNCS.buy_from_shop = function(card)
        if not TG.initialized or not TG.Shop.state.is_open then
            -- Not in a TG run or shop not open — let Balatro handle it normally.
            return original_buy(card)
        end

        -- Identify which TG slot this card belongs to.
        local state = TG.Shop.state
        local buyer_id = state.active_board_id

        -- Consume the pending buy board (set by "Buy for X" button click).
        -- Fall back to active board if the player bought without pressing a button.
        local target_id = state.pending_buy_board_id or buyer_id
        state.pending_buy_board_id = nil  -- clear after consuming

        -- Check joker slots
        for i, slot in ipairs(state.jokers) do
            if slot.card == card and not slot.sold then
                local success, msg = TG.Shop.buy_item("joker", i, buyer_id, target_id)
                if not success then
                    print("[TG] Buy blocked: " .. msg)
                    if TG.UI and TG.UI.ResourceDisplay then
                        TG.UI.ResourceDisplay.trigger_shake("hands")
                    end
                end
                -- Either way: do NOT call original_buy. We own this purchase now.
                return
            end
        end

        -- Check pack slots
        for i, slot in ipairs(state.packs) do
            if slot.card == card and not slot.sold then
                local success, msg = TG.Shop.buy_item("pack", i, buyer_id, target_id)
                if not success then
                    print("[TG] Buy blocked: " .. msg)
                end
                return
            end
        end

        -- Check voucher
        if state.voucher and state.voucher.card == card and not state.voucher.sold then
            local success, msg = TG.Shop.buy_voucher()
            if not success then
                print("[TG] Buy blocked: " .. msg)
            end
            return
        end

        -- Card not found in TG's shop state — fall back to Balatro's handler.
        -- (Handles edge cases like pack contents being picked up.)
        return original_buy(card)
    end

    G.FUNCS._tg_buy_hooked = true
    print("[TG] Buy hook installed on G.FUNCS.buy_from_shop")
end

--- Mirror for the sell hook — intercepts G.FUNCS.sell_card so joker sales
--- deduct from the correct board and respect the no_selling gambit.
function TG.Shop.install_sell_hook()
    if not G or not G.FUNCS then return end
    if G.FUNCS._tg_sell_hooked then return end

    local original_sell = G.FUNCS.sell_card
    G.FUNCS.sell_card = function(card)
        if not TG.initialized then
            return original_sell(card)
        end

        -- Find which board owns this joker
        for _, id in ipairs(TG.BOARD_IDS) do
            local board = TG:get_board(id)
            for idx, joker in ipairs(board.jokers) do
                if joker == card then
                    local success, msg = TG.Shop.sell_joker(id, idx)
                    if not success then
                        print("[TG] Sell blocked: " .. msg)
                        return  -- Block the native sell too
                    end
                    -- Sync money back to G.GAME.dollars so HUD updates
                    TG.Shop.sync_dollars_to_board(TG.Shop.state.active_board_id)
                    -- Let Balatro do its visual removal of the card object
                    return original_sell(card)
                end
            end
        end

        -- Not a TG-owned joker — fall through normally
        return original_sell(card)
    end

    G.FUNCS._tg_sell_hooked = true
    print("[TG] Sell hook installed on G.FUNCS.sell_card")
end

-- ============================================================
-- GAMBIT RESTRICTION CHECKS
-- ============================================================

function TG.Shop.is_spending_blocked()
    for _, gambit in ipairs(TG.active_gambits) do
        if gambit.blocks_spending then return true end
    end
    return false
end

function TG.Shop.is_reroll_blocked()
    for _, gambit in ipairs(TG.active_gambits) do
        if gambit.blocks_reroll then return true end
    end
    return false
end

function TG.Shop.is_selling_blocked()
    for _, gambit in ipairs(TG.active_gambits) do
        if gambit.blocks_selling then return true end
    end
    return false
end

-- ============================================================
-- BALATRO INTEGRATION STUBS
-- These hook into Balatro's actual item generation systems.
-- Replace with real Balatro calls during integration.
-- ============================================================

-- FIX ISSUE #10: pseudorandom/pseudorandom_element/pseudoseed may not be loaded yet.
-- Wrap them in safe fallbacks so shop generation never crashes at startup.
local function safe_random(seed)
    if pseudorandom then
        return pseudorandom(seed)
    end
    return math.random()
end

local function safe_random_element(t, seed)
    if pseudorandom_element and pseudoseed then
        return pseudorandom_element(t, pseudoseed(seed))
    end
    if #t == 0 then return nil end
    return t[math.random(#t)]
end

function TG.Shop.roll_joker()
    -- Create a joker card using Balatro's card creation system
    -- create_card(type, area, legendary, rarity, skip_materialize, soulable, forced_key, key_append)

    -- Guard: require Balatro globals to be ready
    if not create_card or not G or not G.jokers then
        print("[TG] roll_joker: Balatro globals not ready, returning nil")
        return nil
    end
    local rarity_roll = safe_random('tg_shop_joker')
    local rarity = 1  -- Common
    if rarity_roll > 0.96 then
        rarity = 4  -- Legendary
    elseif rarity_roll > 0.92 then
        rarity = 3  -- Rare
    elseif rarity_roll > 0.67 then
        rarity = 2  -- Uncommon
    end
    
    -- Create the joker card
    -- G.jokers is the area where jokers live
    local card = create_card('Joker', G.jokers, nil, rarity, nil, nil, nil, 'tg_shop')
    
    -- Set shop price based on rarity
    if card.config and card.config.center then
        local base_cost = card.config.center.cost or 0
        card.cost = base_cost
        card.sell_value = math.max(1, math.floor(base_cost / 2))
    else
        -- Fallback if center not set
        card.cost = 3
        card.sell_value = 1
    end
    
    return card
end

function TG.Shop.roll_pack()
    -- Create a booster pack using Balatro's pack system
    -- Balatro has: Arcana Pack (Tarot), Celestial Pack (Planet), Spectral Pack (Spectral), Standard Pack (playing cards)

    -- FIX ISSUE #11: Card() constructor may not exist during early init — guard against it.
    if not Card then
        print("[TG] roll_pack: Card constructor not available yet, returning nil")
        return nil
    end

    -- Also guard required globals
    if not G or not G.P_CENTERS or not G.P_CARDS or not G.shop_booster then
        print("[TG] roll_pack: Balatro shop globals not ready, returning nil")
        return nil
    end

    -- Weighted selection: Standard 50%, Arcana 25%, Celestial 20%, Spectral 5%
    local pack_roll = safe_random('tg_shop_pack')
    local pack_key
    
    if pack_roll > 0.95 then
        pack_key = 'p_spectral_normal_1'  -- Spectral Pack
    elseif pack_roll > 0.75 then
        pack_key = 'p_celestial_normal_1'  -- Celestial Pack
    elseif pack_roll > 0.50 then
        pack_key = 'p_arcana_normal_1'  -- Arcana Pack
    else
        pack_key = 'p_standard_normal_1'  -- Standard Pack
    end
    
    -- Create the pack card
    local card = Card(G.shop_booster.T.x, G.shop_booster.T.y, G.CARD_W, G.CARD_H, 
                     G.P_CARDS[pack_key], G.P_CENTERS[pack_key])
    
    -- Set cost based on pack type
    card.cost = card.config and card.config.cost or 4
    card.ability = card.ability or {}
    card.ability.consumeable = card.ability.consumeable or {}
    
    return card
end

function TG.Shop.roll_voucher()
    -- Create a voucher using Balatro's voucher system
    -- Vouchers appear randomly and have prerequisites (some require others first)

    -- Guard: require Balatro globals to be ready
    if not Card or not G or not G.P_CENTERS or not G.GAME or not G.GAME.used_vouchers
       or not G.shop_vouchers or not G.P_CARDS then
        print("[TG] roll_voucher: Balatro globals not ready, returning nil")
        return nil
    end
    local available_vouchers = {}
    
    for k, v in pairs(G.P_CENTERS) do
        if v.set == 'Voucher' and not v.wip and not v.demo then
            -- Check if already redeemed
            if not G.GAME.used_vouchers[k] then
                -- Check prerequisites
                local can_use = true
                if v.requires then
                    -- Voucher has prerequisites
                    for _, req in ipairs(v.requires) do
                        if not G.GAME.used_vouchers[req] then
                            can_use = false
                            break
                        end
                    end
                end
                
                if can_use then
                    table.insert(available_vouchers, k)
                end
            end
        end
    end
    
    -- If no vouchers available, return nil
    if #available_vouchers == 0 then
        return nil
    end
    
    -- Pick a random available voucher
    local voucher_key = safe_random_element(available_vouchers, 'tg_voucher')
    
    -- Create the voucher card
    local card = Card(G.shop_vouchers.T.x, G.shop_vouchers.T.y, G.CARD_W, G.CARD_H,
                     G.P_CARDS.empty, G.P_CENTERS[voucher_key])
    
    -- Set cost
    card.cost = card.config and card.config.cost or 10
    
    return card
end

function TG.Shop.open_pack_for_board(pack, board)
    -- Open a booster pack and add its contents to the specified board's deck
    -- pack is a Card object representing the booster
    
    print(string.format("[TG] Opening pack '%s' for Board %s", pack.name or "Unknown", board.id))
    
    -- Temporarily redirect Balatro's card area to this board's context
    -- Store original deck reference
    local original_deck = G.deck
    
    -- Use the pack's ability to determine contents
    if pack.ability and pack.ability.consumeable then
        local pack_config = pack.config.center
        
        -- Open the pack (this creates cards)
        -- Standard pattern: check pack type and create appropriate cards
        local cards_to_add = {}
        
        if pack_config.name:find('Arcana') then
            -- Tarot cards
            for i = 1, (pack_config.config and pack_config.config.choose or 1) do
                local card = create_card('Tarot', G.consumeables, nil, nil, nil, nil, nil, 'tg_pack')
                table.insert(cards_to_add, card)
            end
            
        elseif pack_config.name:find('Celestial') then
            -- Planet cards
            for i = 1, (pack_config.config and pack_config.config.choose or 1) do
                local card = create_card('Planet', G.consumeables, nil, nil, nil, nil, nil, 'tg_pack')
                table.insert(cards_to_add, card)
            end
            
        elseif pack_config.name:find('Spectral') then
            -- Spectral cards
            for i = 1, (pack_config.config and pack_config.config.choose or 1) do
                local card = create_card('Spectral', G.consumeables, nil, nil, nil, nil, nil, 'tg_pack')
                table.insert(cards_to_add, card)
            end
            
        else
            -- Standard pack - playing cards
            for i = 1, (pack_config.config and pack_config.config.choose or 1) do
                local card = create_card('Base', G.deck, nil, nil, nil, nil, nil, 'tg_pack')
                table.insert(cards_to_add, card)
            end
        end
        
        -- Add cards to the board's consumables or deck
        for _, card in ipairs(cards_to_add) do
            if card.ability.set == 'Tarot' or card.ability.set == 'Planet' or card.ability.set == 'Spectral' then
                -- Consumable - add to board's consumables
                table.insert(board.consumables, card)
            else
                -- Playing card - register key with board's key-based deck
                board:add_card_key(card)
                card.board_id = board.id
            end
        end
        
        print(string.format("[TG] Added %d cards to Board %s", #cards_to_add, board.id))
    end
end

function TG.Shop.apply_voucher(voucher)
    -- Apply a voucher's effect globally to all boards
    -- Vouchers in Balatro modify G.GAME state permanently
    
    print(string.format("[TG] Applying voucher '%s' to all boards", voucher.name or "Unknown"))
    
    if not voucher.config or not voucher.config.center then
        print("[TG] Warning: Voucher has no config.center")
        return
    end
    
    local voucher_key = voucher.config.center.key
    
    -- Mark voucher as used in game state
    G.GAME.used_vouchers[voucher_key] = true
    
    -- Call the voucher's redeem function if it exists
    if voucher.config.center.redeem then
        voucher.config.center:redeem()
    end
    
    -- Apply voucher effects to TG state
    -- Many vouchers modify G.GAME directly, which affects all boards automatically
    -- Some need explicit application to TG's board system
    
    -- Examples of voucher effects that need TG-specific handling:
    if voucher_key == 'v_overstock_norm' or voucher_key == 'v_overstock_plus' then
        -- Increases shop slots - TG.CONFIG.SHOP_JOKER_SLOTS already references G.GAME
        -- No action needed, shop generation reads from G.GAME directly
        
    elseif voucher_key == 'v_tarot_merchant' or voucher_key == 'v_tarot_tycoon' then
        -- Increases consumable slots - affects all boards' consumable capacity
        -- Update TG config if we're tracking max consumables per board
        
    elseif voucher_key == 'v_grabber' then
        -- Permanent +1 hand size - apply to all living boards
        for _, id in ipairs(TG.BOARD_IDS) do
            local board = TG:get_board(id)
            if not board.is_dead then
                board:restore_hand_size(1)
                print(string.format("[TG] Grabber: Board %s hand size -> %d", id, board.hand_size))
            end
        end
        
    elseif voucher_key == 'v_money_tree' or voucher_key == 'v_seed_money' then
        -- Increases interest/money cap - already affects G.GAME.interest_amount
        -- No TG-specific action needed
        
    end
    
    -- Log the voucher redemption
    print(string.format("[TG] Voucher '%s' applied successfully", voucher_key))
end

return TG.Shop