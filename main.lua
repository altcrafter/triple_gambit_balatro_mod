--[[
    TRIPLE GAMBIT - main.lua
    Entry point. Hooks into Balatro.
    Phase 1: 4 boards, per-board resources, keys-only deck, Bacon visual APIs wired.
]]

TG = TG or {}
TG.Hooks = TG.Hooks or {}

-- ============================================================
-- MODULE LOADER
-- ============================================================

TG_MOD_PATH = SMODS.current_mod.path
if TG_MOD_PATH:sub(-1) ~= "/" then TG_MOD_PATH = TG_MOD_PATH .. "/" end

function tg_require(path)
    local chunk, err = love.filesystem.load(TG_MOD_PATH .. path .. ".lua")
    if not chunk then
        error("[TG] Failed to load " .. path .. ": " .. tostring(err))
    end
    local ok, result = pcall(chunk)
    if not ok then
        error("[TG] Error in " .. path .. ": " .. tostring(result))
    end
    return result
end

-- ============================================================
-- LOAD UI
-- ============================================================

local ui_loaded = false

local function load_ui()
    if ui_loaded then return end
    TG.UI                    = TG.UI or {}
    -- Bacon's modules (loaded here, built by Bacon agent)
    TG.Phosphor              = tg_require("ui/phosphor")
    TG.Kinetics              = tg_require("ui/kinetics")
    TG.UI.Atmosphere         = tg_require("ui/atmosphere")
    TG.UI.StatusBar          = tg_require("ui/status_bar")
    TG.UI.ResourceDisplay    = tg_require("ui/resource_display")
    TG.UI.ScoreChyron        = tg_require("ui/score_chyron")
    TG.UI.HotkeyDock         = tg_require("ui/hotkey_dock")
    TG.UI.ShopUI             = tg_require("ui/shop_ui")
    TG.UI.GambitDisplay      = tg_require("ui/gambit_display")
    TG.UI.BoardTransition    = tg_require("ui/board_transition")
    TG.UI.Shader             = tg_require("ui/tg_shader")
    TG.UI.ChipStackUI        = tg_require("ui/gambit_chip_ui")
    TG.UI.CardDeal           = tg_require("ui/card_deal")
    TG.Audio                 = tg_require("core/audio")
    if TG.Phosphor  then TG.Phosphor.init()            end
    if TG.Audio     then TG.Audio.init()               end
    if TG.UI.Shader then TG.UI.Shader.init()           end
    if TG.Kinetics  then TG.Kinetics.init_particles()  end
    ui_loaded = true
end

-- ============================================================
-- PACK STATE HELPER
-- ============================================================

local function is_pack_state()
    if not (G and G.STATE and G.STATES) then return false end
    return (G.STATES.TAROT_PACK    and G.STATE == G.STATES.TAROT_PACK)
        or (G.STATES.SPECTRAL_PACK and G.STATE == G.STATES.SPECTRAL_PACK)
        or (G.STATES.STANDARD_PACK and G.STATE == G.STATES.STANDARD_PACK)
        or (G.STATES.BUFFOON_PACK  and G.STATE == G.STATES.BUFFOON_PACK)
        or (G.STATES.PLANET_PACK   and G.STATE == G.STATES.PLANET_PACK)
        or false
end

-- ============================================================
-- WIN / LOSS HELPERS
-- ============================================================

local _tg_blind_won        = false
local _tg_defeat_processed = false
local _hooks_installed     = false

-- Captured here (before on_score_calculated) so the event closure can see it.
local orig_blind_defeat

-- Count cleared boards. Returns true when >= BOARDS_TO_CLEAR are cleared.
local function tg_check_blind_won()
    if not TG.initialized then return false end
    local count = 0
    for _, id in ipairs(TG.BOARD_IDS) do
        local b = TG:get_board(id)
        if b and b.is_cleared then count = count + 1 end
    end
    return count >= (TG.CONFIG.BOARDS_TO_CLEAR or 3)
end

-- ============================================================
-- RUN START
-- ============================================================

local function on_run_start()
    TG.initialized       = false
    _hooks_installed     = false
    _tg_blind_won        = false
    _tg_defeat_processed = false
    TG._run_lost         = false
    if G and G.FUNCS then
        G.FUNCS._tg_buy_hooked  = nil
        G.FUNCS._tg_sell_hooked = nil
    end
    tg_require("core/init")
    TG:init()
    load_ui()
    TG.Hooks.sync_starting_money()
end

function TG.Hooks.sync_starting_money()
    if not (G and G.GAME and G.GAME.dollars and TG.initialized) then return end
    local total = G.GAME.dollars
    local n     = #TG.BOARD_IDS
    local per   = math.floor(total / n)
    local rem   = total - per * n
    for i, id in ipairs(TG.BOARD_IDS) do
        local board = TG:get_board(id)
        if board then board.money = per + (i == 1 and rem or 0) end
    end
    print(string.format("[TG] Starting money $%d split across %d boards", total, n))
end

-- ============================================================
-- HAND TYPE DETECTION
-- ============================================================

function TG.get_highlighted_hand_type()
    if not G or not G.hand or not G.hand.highlighted then return nil end
    local cards = G.hand.highlighted
    if #cards == 0 then return nil end

    local ok1, r1 = pcall(function()
        local ch = G.GAME
            and G.GAME.current_round
            and G.GAME.current_round.current_hand
        if ch then
            if type(ch.handname) == "string" and ch.handname ~= "" then
                return ch.handname
            end
            if ch[1] then
                if type(ch[1]) == "table"  then return ch[1].handname or ch[1][1] end
                if type(ch[1]) == "string" then return ch[1] end
            end
        end
        return nil
    end)
    if ok1 and r1 then return r1 end

    local ok2, r2 = pcall(function()
        if not evaluate_poker_hand then return nil end
        local result = evaluate_poker_hand(cards)
        if type(result) == "string" and result ~= "" then return result end
        if type(result) == "table" then
            if result[1] and type(result[1]) == "table" then
                return result[1].handname or result[1][1]
            end
            if result[1] and type(result[1]) == "string" then return result[1] end
        end
        return nil
    end)
    if ok2 and r2 then return r2 end

    return nil
end

-- ============================================================
-- AFTER SCORING
-- ============================================================

local function on_score_calculated()
    if not TG.initialized then return end

    local board_id = TG._board_id_at_play or TG.active_board_id
    local board    = TG:get_board(board_id)
    if not board then return end

    local chips_now    = (G.GAME and G.GAME.chips) or 0
    local chips_before = TG._chips_before or 0
    local scored       = math.max(0, chips_now - chips_before)

    -- AMPLIFIER bonus
    local mult        = TG.Amplifier and TG.Amplifier.get_multiplier(board_id) or 1.0
    local bonus_chips = 0
    if mult > 1.0 and scored > 0 then
        bonus_chips = math.floor(scored * (mult - 1.0))
        if bonus_chips > 0 then
            if G.GAME then G.GAME.chips = (G.GAME.chips or 0) + bonus_chips end
            print(string.format("[TG] Amplifier: Board %s x%.2f +%d bonus chips",
                board_id, mult, bonus_chips))
        end
    end

    local total_scored = scored + bonus_chips

    -- Update board score
    if total_scored > 0 then
        local just_cleared = board:add_score(total_scored)

        -- Score popup (Bacon API) — fires after add_score so total_scored is final
        if TG.Kinetics then
            local cx          = love.graphics.getWidth() / 2
            local cy          = love.graphics.getHeight() * 0.42
            local board_color = TG.CONFIG.COLORS[board_id]
            TG.Kinetics.popup("+" .. tostring(total_scored), board_color, cx, cy, 22, 1.2)
        end

        if just_cleared then
            if TG.Amplifier then
                TG.Amplifier.on_board_cleared(board_id, board.hands_remaining)
            end
            -- Board clear visuals (Bacon APIs)
            if TG.Kinetics then
                local cx = love.graphics.getWidth() / 2
                local cy = love.graphics.getHeight() * 0.4
                TG.Kinetics.shake(6, 6, 0.35)
                TG.Kinetics.burst(cx, cy, {0.412, 0.941, 0.682}, 24)  -- #69f0ae
                TG.Kinetics.popup("CLEARED", {0.412, 0.941, 0.682}, cx, cy, 20, 1.5)
            end
            if TG.UI and TG.UI.BoardTransition then
                pcall(function()
                    TG.UI.BoardTransition.trigger_cleared(board_id)
                end)
            end
        end
    end

    -- JokerBridge restore
    if TG.JokerBridge then TG.JokerBridge.post_score() end

    -- Gambit level boost cleanup
    local hand_type_cleanup = TG._hand_type_at_play
    local boost_cleanup     = TG._boost_at_play or 0
    if boost_cleanup > 0 and hand_type_cleanup
    and G.GAME and G.GAME.hands and G.GAME.hands[hand_type_cleanup] then
        local h = G.GAME.hands[hand_type_cleanup]
        h.level = math.max(1, (h.level or 1) - boost_cleanup)
    end

    -- Win condition: enough boards cleared → force blind victory
    if tg_check_blind_won() and not _tg_blind_won then
        _tg_blind_won = true
        if G.GAME and G.blind then
            G.GAME.chips = G.blind.chips or G.GAME.chips
        end
        if G.E_MANAGER then
            G.E_MANAGER:add_event(Event({
                func = function()
                    if _tg_defeat_processed then return true end
                    if not G.blind then return true end
                    _tg_defeat_processed = true
                    local db = (G.GAME and G.GAME.dollars) or 0
                    orig_blind_defeat(G.blind)
                    local da = (G.GAME and G.GAME.dollars) or 0
                    if da > db and TG.initialized then
                        local b = TG:get_active_board()
                        if b then b:add_money(da - db) end
                    end
                    TG.Hooks.on_blind_end()
                    return true
                end
            }))
        end
        print("[TG] 3-of-4 boards cleared! Blind victory queued.")
    end

    -- Near-loss tension
    local active_board = TG:get_active_board()
    if active_board and active_board.hands_remaining == 1
    and not tg_check_blind_won() and not _tg_blind_won then
        if TG.Audio then TG.Audio.play("near_loss") end
    end

    -- Loss condition: all uncleared boards have 0 hands left
    if not tg_check_blind_won() and not _tg_blind_won then
        local all_exhausted = true
        for _, id in ipairs(TG.BOARD_IDS) do
            local b = TG:get_board(id)
            if b and not b.is_cleared and b.hands_remaining > 0 then
                all_exhausted = false
                break
            end
        end
        if all_exhausted then
            TG:on_run_lost("hands exhausted")
        end
    end

    -- Score audio
    if TG.Audio and total_scored > 0 then
        local b2        = TG:get_board(board_id)
        local deficit   = b2 and (b2.target - b2.current_score) or nil
        local hand_type = TG._hand_type_at_play
        TG.Audio.play_score(board_id, total_scored, deficit, hand_type)
    end

    -- Cleanup per-play state
    TG._chips_before       = nil
    TG._hand_type_at_play  = nil
    TG._boost_at_play      = nil
    TG._board_id_at_play   = nil
end

-- ============================================================
-- LAZY HOOK INSTALLATION
-- ============================================================

local function install_hooks()
    if _hooks_installed then return end
    if not TG.initialized then return end
    if not (G and G.FUNCS) then return end
    if not G.FUNCS.play_cards_from_highlighted then return end
    if not G.FUNCS.discard_cards_from_highlighted then return end

    -- ── PLAY HOOK ──
    local orig_play = G.FUNCS.play_cards_from_highlighted
    G.FUNCS.play_cards_from_highlighted = function(e, ...)
        if not TG.initialized then
            local args = { ... }; return orig_play(e, unpack(args))
        end

        local active_board = TG:get_active_board()
        if not active_board then
            local args = { ... }; return orig_play(e, unpack(args))
        end

        if not active_board:can_play_hand() then
            if TG.Audio then TG.Audio.play("action_blocked") end
            -- Gambit block visual (Bacon API)
            if TG.Kinetics then
                local cx = love.graphics.getWidth() / 2
                local cy = love.graphics.getHeight() * 0.42
                TG.Kinetics.shake(3, 2, 0.15)
                TG.Kinetics.popup("BLOCKED", {1.0, 0.176, 0.42}, cx, cy, 16, 0.8)
            end
            return
        end

        local board_id  = TG.active_board_id
        local hand_type = TG.get_highlighted_hand_type()

        -- Track that this board was played on
        TG.boards_played_on = TG.boards_played_on or {}
        TG.boards_played_on[board_id] = true

        -- GAMBIT: validate hand type
        if hand_type and TG.Gambit and not TG.Gambit.is_hand_allowed(board_id, hand_type) then
            if TG.Audio then TG.Audio.play("gambit_blocked") end
            if TG.Kinetics then
                local cx = love.graphics.getWidth() / 2
                local cy = love.graphics.getHeight() * 0.42
                TG.Kinetics.shake(3, 2, 0.15)
                TG.Kinetics.popup("BLOCKED", {1.0, 0.176, 0.42}, cx, cy, 16, 0.8)
            end
            return
        end

        -- GAMBIT: apply level boost
        local boost = 0
        if hand_type and TG.Gambit then
            boost = TG.Gambit.get_level_boost(board_id, hand_type)
        end
        if boost > 0 and G.GAME and G.GAME.hands then
            local hdata = G.GAME.hands[hand_type]
            if hdata then
                hdata.level = (hdata.level or 1) + boost
                print(string.format("[TG] Gambit boost: Board %s %s +%d (→ lvl %d)",
                    board_id, hand_type, boost, hdata.level))
            end
        end

        -- Use per-board hand
        active_board:use_hand()
        if G.GAME and G.GAME.current_round then
            G.GAME.current_round.hands_left = active_board.hands_remaining
        end
        -- Pip drain animation: spent pip is the one that just emptied
        if TG.UI and TG.UI.ResourceDisplay then
            TG.UI.ResourceDisplay.on_hand_spent(active_board.hands_remaining + 1)
        end

        -- Snapshot chips before play
        TG._chips_before      = (G.GAME and G.GAME.chips) or 0
        TG._hand_type_at_play = hand_type
        TG._boost_at_play     = boost
        TG._board_id_at_play  = board_id

        if TG.JokerBridge then TG.JokerBridge.pre_score() end

        local args = { ... }
        orig_play(e, unpack(args))

        -- Play kinetics (Bacon APIs)
        if TG.Kinetics then
            local cx          = love.graphics.getWidth() / 2
            local cy          = love.graphics.getHeight() * 0.42
            local board_color = TG.CONFIG.COLORS[board_id]
            TG.Kinetics.shake(2, 3, 0.18)
            TG.Kinetics.burst(cx, cy, board_color, 12)
        end
    end

    -- ── DISCARD HOOK ──
    local orig_discard = G.FUNCS.discard_cards_from_highlighted
    G.FUNCS.discard_cards_from_highlighted = function(e, ...)
        if not TG.initialized then
            local args = { ... }; return orig_discard(e, unpack(args))
        end

        local active_board = TG:get_active_board()
        local forced = type(e) == "table" and e.triggered == true

        if not forced and active_board and not active_board:can_discard() then
            if TG.Audio then TG.Audio.play("action_blocked") end
            return
        end

        local args   = { ... }
        local result = orig_discard(e, unpack(args))

        if not forced and active_board then
            active_board:use_discard()
            if G.GAME and G.GAME.current_round then
                G.GAME.current_round.discards_left = active_board.discards_remaining
            end
            -- Pip drain animation
            if TG.UI and TG.UI.ResourceDisplay then
                TG.UI.ResourceDisplay.on_discard_spent(active_board.discards_remaining + 1)
            end
        end

        -- Discard kinetics (Bacon APIs)
        if TG.Kinetics then
            local cx = love.graphics.getWidth() / 2
            local cy = love.graphics.getHeight() * 0.42
            TG.Kinetics.shake(1, 1, 0.1)
            TG.Kinetics.burst(cx, cy, {0.251, 0.769, 1.0}, 6)  -- #40c4ff
        end

        return result
    end

    -- ── BUY / SELL HOOKS ──
    if TG.Shop then
        TG.Shop.install_buy_hook()
        TG.Shop.install_sell_hook()
    end

    -- Point G.jokers at active board's lineup
    if G.jokers and TG:get_active_board() then
        -- Use CardArea emplace for the initial setup
        local board = TG:get_active_board()
        if G.jokers.cards then
            for i = #G.jokers.cards, 1, -1 do
                G.jokers:remove_card(G.jokers.cards[i])
            end
        end
        for _, joker in ipairs(board.jokers) do
            if TG.Switching then
                TG.Switching._emplace(G.jokers, joker)
            end
        end
    end

    _hooks_installed = true
    print("[TG] Hooks installed.")
end

-- ============================================================
-- HOOKS TABLE
-- ============================================================

function TG.Hooks.on_blind_start()
    if not TG.initialized then return end
    _tg_blind_won        = false
    _tg_defeat_processed = false

    -- Sync ante/blind type from Balatro's authoritative state
    if G and G.GAME then
        if G.GAME.round_resets and G.GAME.round_resets.blind_ante then
            TG.current_ante = G.GAME.round_resets.blind_ante
        elseif G.GAME.ante then
            TG.current_ante = G.GAME.ante
        end
        if G.GAME.current_round and G.GAME.current_round.blind_states then
            local bs = G.GAME.current_round.blind_states
            if bs.Small == "Current" then TG.current_blind_type = "small"
            elseif bs.Big == "Current" then TG.current_blind_type = "big"
            else TG.current_blind_type = "boss" end
        end
    end

    TG:on_blind_start()

    -- Sync any jokers in G.jokers that aren't tracked in board.jokers yet
    -- (captures jokers obtained from packs, which bypass the shop buy hook)
    local ab = TG:get_active_board()
    if ab and G and G.jokers and G.jokers.cards then
        for _, card in ipairs(G.jokers.cards) do
            local found = false
            for _, j in ipairs(ab.jokers) do
                if j == card then found = true; break end
            end
            if not found then
                table.insert(ab.jokers, card)
            end
        end
    end

    -- Initialize deck keys on first blind (G.deck is now populated)
    if G and G.deck and G.deck.cards and #G.deck.cards > 0 then
        for _, id in ipairs(TG.BOARD_IDS) do
            local b = TG:get_board(id)
            if b and (not b.deck_keys or #b.deck_keys == 0) then
                b:init_deck_keys()
                print(string.format("[TG] Deck keys initialized for Board %s (%d keys)",
                    id, #b.deck_keys))
            end
        end
    end

    -- Sync active board's resources to Balatro
    TG:sync_board_resources_to_balatro()
end

function TG.Hooks.on_blind_end()
    if not TG.initialized then return end
    TG:on_blind_end()
end

function TG.Hooks.on_shop_open()
    if not TG.initialized then return end
    TG.entering_shop_board = TG.active_board_id

    local board = TG:get_active_board()
    if board and G then
        if G.GAME and G.GAME.dollars and G.GAME.dollars > board.money then
            board.money = G.GAME.dollars
        end
        if G.GAME   then G.GAME.dollars = board.money end
        if G.jokers and TG.Switching then
            -- Capture any untracked jokers into board.jokers first
            -- (starter jokers, or anything Balatro added before we hooked)
            if G.jokers.cards then
                for _, card in ipairs(G.jokers.cards) do
                    local found = false
                    for _, j in ipairs(board.jokers) do
                        if j == card then found = true; break end
                    end
                    if not found then table.insert(board.jokers, card) end
                end
            end
            -- Sync jokers via CardArea
            if G.jokers.cards then
                for i = #G.jokers.cards, 1, -1 do
                    G.jokers:remove_card(G.jokers.cards[i])
                end
            end
            for _, joker in ipairs(board.jokers) do
                TG.Switching._emplace(G.jokers, joker)
            end
        end
    end
    if TG.Shop then TG.Shop.generate() end
end

function TG.Hooks.on_shop_board_switch(new_board_id)
    if TG.Shop and TG.Shop.state and TG.Shop.state.active_board_id then
        local old_board = TG:get_board(TG.Shop.state.active_board_id)
        if old_board and G and G.GAME then
            old_board.money = G.GAME.dollars
        end
    end
    if TG.Shop then TG.Shop.set_active_board(new_board_id) end
    local board = TG:get_board(new_board_id)
    if board and G then
        if G.GAME then G.GAME.dollars = board.money end
        if G.jokers and TG.Switching then
            if G.jokers.cards then
                for i = #G.jokers.cards, 1, -1 do
                    G.jokers:remove_card(G.jokers.cards[i])
                end
            end
            for _, joker in ipairs(board.jokers) do
                TG.Switching._emplace(G.jokers, joker)
            end
        end
    end
end

function TG.Hooks.on_shop_close()
    if not TG.initialized then return end
    local close_board_id = TG.Shop and TG.Shop.state and TG.Shop.state.active_board_id
                           or TG.active_board_id
    local close_board = TG:get_board(close_board_id)
    if close_board then
        if G and G.GAME then close_board.money = G.GAME.dollars end
        -- Capture any pack jokers that Balatro added to G.jokers during shopping
        if G and G.jokers and G.jokers.cards then
            for _, card in ipairs(G.jokers.cards) do
                local found = false
                for _, j in ipairs(close_board.jokers) do
                    if j == card then found = true; break end
                end
                if not found then
                    table.insert(close_board.jokers, card)
                    print(string.format("[TG] on_shop_close: captured joker for board %s", close_board_id))
                end
            end
        end
    end
    if TG.Shop then TG.Shop.close() end
end

function TG.Hooks.on_key_pressed(key)
    if not TG.initialized then return false end
    if key == "1" or key == "2" or key == "3" or key == "4" then
        TG.Switching.handle_key(key)
        return true
    end
    return false
end

function TG.Hooks.on_mouse_pressed(x, y)
    if not TG.initialized then return false end
    if TG.UI and TG.UI.StatusBar and TG.UI.StatusBar.handle_click then
        local clicked_board = TG.UI.StatusBar.handle_click(x, y)
        if clicked_board then
            TG.Switching.execute_switch(clicked_board)
            return true
        end
    end
    if TG.UI and TG.UI.HotkeyDock and TG.UI.HotkeyDock.handle_click then
        if TG.UI.HotkeyDock.handle_click(x, y) then return true end
    end
    if TG.UI and TG.UI.ChipStackUI and TG.UI.ChipStackUI.handle_click then
        if TG.UI.ChipStackUI.handle_click(x, y) then return true end
    end
    return false
end

function TG.Hooks.draw()
    if not TG.initialized then return end

    local shader = TG.UI and TG.UI.Shader
    if shader then shader.begin_pass() end

    -- Screen shake (applied first, affects everything inside)
    if TG.Kinetics then TG.Kinetics.apply_shake() end

    -- Atmosphere layer (fullscreen background, behind everything)
    if TG.UI and TG.UI.Atmosphere then TG.UI.Atmosphere.draw() end

    -- UI components
    if TG.UI then
        if TG.UI.StatusBar       then TG.UI.StatusBar.draw()        end
        if TG.UI.ResourceDisplay then TG.UI.ResourceDisplay.draw()  end
        if TG.UI.ScoreChyron     then TG.UI.ScoreChyron.draw()      end
        if TG.UI.HotkeyDock      then TG.UI.HotkeyDock.draw()       end
        if TG.UI.BoardTransition then TG.UI.BoardTransition.draw()  end
        if TG.UI.GambitDisplay   then TG.UI.GambitDisplay.draw_all() end
        if TG.UI.ChipStackUI     then TG.UI.ChipStackUI.draw()      end
        if TG.UI.CardDeal        then TG.UI.CardDeal.draw()         end
    end

    -- Kinetic overlay (particles + popups) — always on top
    if TG.Kinetics then
        TG.Kinetics.draw_particles()
        TG.Kinetics.draw_popups()
    end

    if shader then shader.end_pass() end
end

function TG.Hooks.update(dt)
    if not TG.initialized then return end
    TG:update(dt)

    -- Kinetics and Bacon systems
    if TG.Kinetics            then TG.Kinetics.update(dt)                 end
    if TG.UI and TG.UI.Atmosphere then TG.UI.Atmosphere.update(dt)       end
    if TG.UI and TG.UI.CardDeal   then TG.UI.CardDeal.update(dt)         end
    if TG.UI and TG.UI.BoardTransition then TG.UI.BoardTransition.update(dt) end
    if TG.UI and TG.UI.ResourceDisplay then TG.UI.ResourceDisplay.update_shake(dt) end
    if TG.UI and TG.UI.ChipStackUI    then TG.UI.ChipStackUI.update(dt)           end
    if TG.UI and TG.UI.ScoreChyron    then TG.UI.ScoreChyron.update(dt)           end
    if TG.UI and TG.UI.Shader         then TG.UI.Shader.update(dt)                end
    if TG.Audio                then TG.Audio.update(dt)                   end

    -- Auto-activate gambits on jokers that entered boards via packs
    if TG.Gambit and G and G.jokers and G.jokers.cards then
        for _, card in ipairs(G.jokers.cards) do
            if card and card.tg_gambit_id then
                local already = false
                for _, g in ipairs(TG.Gambit.active) do
                    if g.joker_ref == card then already = true; break end
                end
                if not already then
                    TG.Gambit.activate(card, card.tg_gambit_id)
                    if TG.JokerBridge and not card.tg_board_id then
                        local bid = TG.active_board_id
                        if TG.Shop and TG.Shop.state and TG.Shop.state.is_open then
                            bid = TG.Shop.state.active_board_id or bid
                        end
                        TG.JokerBridge.register_joker(card, bid)
                    end
                end
            end
        end
    end
end

-- ============================================================
-- REGISTRATIONS
-- ============================================================

local orig_start_run = Game.start_run
function Game:start_run(...)
    local r = orig_start_run(self, ...)
    on_run_start()
    return r
end

-- ============================================================
-- BLIND SET
-- ============================================================

local orig_blind_set = Blind.set_blind
function Blind:set_blind(blind, size, silent)
    -- Do NOT call on_blind_start here. Balatro calls set_blind multiple times
    -- (previews, mid-defeat animations) so firing here resets boards at wrong times.
    -- on_blind_start is triggered by the SELECTING_HAND state transition instead.
    local r = orig_blind_set(self, blind, size, silent)
    if TG.initialized and G.GAME and G.GAME.ante
    and G.GAME.ante ~= TG._last_seen_ante then
        TG._last_seen_ante = G.GAME.ante
    end
    return r
end

-- ============================================================
-- BLIND DEFEAT OVERRIDE
-- ============================================================

orig_blind_defeat = Blind.defeat
function Blind:defeat(...)
    if TG.initialized then
        -- Loss path: on_run_lost sets TG._run_lost to bypass suppression.
        if TG._run_lost then
            TG._run_lost = false
            return orig_blind_defeat(self, ...)
        end
        -- Suppress unless enough boards are cleared (3-of-4)
        if not tg_check_blind_won() then
            return  -- Block — player must keep playing
        end
        if _tg_defeat_processed then return end
        _tg_defeat_processed = true
        local dollars_before = (G and G.GAME and G.GAME.dollars) or 0
        local result         = orig_blind_defeat(self, ...)
        local dollars_after  = (G and G.GAME and G.GAME.dollars) or 0
        local reward_delta   = dollars_after - dollars_before
        if reward_delta > 0 then
            local board = TG:get_active_board()
            if board then board:add_money(reward_delta) end
        end
        TG.Hooks.on_blind_end()
        return result
    end

    local dollars_before = (G and G.GAME and G.GAME.dollars) or 0
    local result         = orig_blind_defeat(self, ...)
    local dollars_after  = (G and G.GAME and G.GAME.dollars) or 0
    if dollars_after - dollars_before > 0 then
        local board = TG:get_active_board()
        if board then board:add_money(dollars_after - dollars_before) end
    end
    TG.Hooks.on_blind_end()
    return result
end

-- ============================================================
-- SAVE / LOAD HOOKS
-- ============================================================

local orig_save = Game.save_progress
function Game:save_progress(...)
    if TG.initialized and TG.SaveLoad and G and G.GAME then
        G.GAME.tg_save = TG.SaveLoad.serialize()
    end
    return orig_save(self, ...)
end

local orig_load_run = Game.load_run
if orig_load_run then
    function Game:load_run(...)
        local r = orig_load_run(self, ...)
        if G and G.GAME and G.GAME.tg_save and TG.SaveLoad then
            on_run_start()
            TG.SaveLoad.on_load({ triple_gambit_state = G.GAME.tg_save })
        end
        return r
    end
end

-- ============================================================
-- LOVE HOOKS
-- ============================================================

local _orig_draw = love.draw
function love.draw(...)
    _orig_draw(...)
    TG.Hooks.draw()
end

local _prev_state  = nil
local _shop_open   = false
local _orig_update = love.update
function love.update(dt, ...)
    _orig_update(dt, ...)

    if not (G and G.STATE and G.STATES) then return end

    install_hooks()

    local curr = G.STATE

    -- Score capture on leaving HAND_PLAYED
    if _prev_state == G.STATES.HAND_PLAYED
    and curr       ~= G.STATES.HAND_PLAYED then
        on_score_calculated()
    end

    -- Blind start: entering SELECTING_HAND for the first time this blind.
    -- Only fires on fresh blind entry (not mid-blind after HAND_PLAYED).
    -- This is the canonical trigger for on_blind_start — NOT Blind:set_blind,
    -- which fires too early and for previews/mid-defeat animations.
    if curr == G.STATES.SELECTING_HAND
    and _prev_state ~= G.STATES.SELECTING_HAND
    and _prev_state ~= G.STATES.HAND_PLAYED
    and TG.initialized then
        TG.Hooks.on_blind_start()
    end

    -- After each hand play, re-sync resources (Balatro may drift from TG).
    if curr == G.STATES.SELECTING_HAND
    and _prev_state == G.STATES.HAND_PLAYED
    and TG.initialized then
        TG:sync_board_resources_to_balatro()
    end

    _prev_state = curr

    -- ═══════════════════════════════════════════════════════════
    -- CHIP CAPPING: prevent Balatro auto-victory until 3-of-4 cleared
    -- ═══════════════════════════════════════════════════════════
    if TG.initialized and not _tg_blind_won then
        if G.GAME and G.blind and G.blind.chips then
            if G.GAME.chips >= G.blind.chips then
                G.GAME.chips = G.blind.chips - 1
            end
        end
    end

    -- ═══════════════════════════════════════════════════════════
    -- SHOP / PACK STATE DETECTION
    -- ═══════════════════════════════════════════════════════════
    local in_shop_or_pack = (curr == G.STATES.SHOP) or is_pack_state()

    if in_shop_or_pack then
        if not _shop_open then
            _shop_open = true
            TG.Hooks.on_shop_open()
        end
    else
        if _shop_open then
            _shop_open = false
            TG.Hooks.on_shop_close()
        end
    end

    TG.Hooks.update(dt)

    -- ═══════════════════════════════════════════════════════════
    -- MONEY SYNC
    -- ═══════════════════════════════════════════════════════════
    if TG.initialized and G and G.GAME and G.GAME.dollars ~= nil then
        local is_shop = TG.Shop and TG.Shop.state and TG.Shop.state.is_open
        if not is_shop and is_pack_state() then is_shop = true end

        local board_id = is_shop
            and (TG.Shop.state.active_board_id or TG.active_board_id)
            or  TG.active_board_id
        local board = TG:get_board(board_id)

        if board then
            local dollars = G.GAME.dollars
            if is_shop and dollars ~= board.money and dollars >= 0 then
                board.money = dollars
            elseif not is_shop and dollars > board.money then
                board.money = dollars
            else
                G.GAME.dollars = board.money
            end
        end
    end
end

local _orig_keypressed = love.keypressed
function love.keypressed(key, ...)
    if TG.Hooks.on_key_pressed(key) then return end
    if _orig_keypressed then _orig_keypressed(key, ...) end
end

local _orig_mousepressed = love.mousepressed
function love.mousepressed(x, y, button, ...)
    if TG.Hooks.on_mouse_pressed(x, y) then return end
    if _orig_mousepressed then _orig_mousepressed(x, y, button, ...) end
end
