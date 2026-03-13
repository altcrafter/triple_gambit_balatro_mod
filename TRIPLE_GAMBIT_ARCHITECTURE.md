# Triple Gambit — Architecture Spec & Cleanup Plan

**Status:** Phase 1 — all design decisions locked, ready for implementation  
**Source:** Phase 0c codebase (main_phase0c.lua, init_phase0c.lua, board.lua, resource_pool.lua, joker_bridge.lua, switching.lua, gambit.lua, gambit_base.lua, gambits.lua)  
**Target:** A single clean codebase that two Claude Code agents (claude-bacon, claude-kara) can build from without stepping on each other  

---

## 1. Core Design Decisions (Locked In)

### 1.1 Board Count & Win Condition: 4 boards, clear 3

Four boards (A, B, C, D). Player must clear exactly 3 of 4 per blind to advance. The fourth board is the sacrifice — the one you starve of resources. Run lasts 8 antes, 3 blinds per ante (small/big/boss). This replaces ALL prior win conditions (2/3 overcommit, 3/3 all-must-clear).

Win/loss logic becomes:

- `cleared_count >= 3` → blind victory, allow `Blind:defeat()` to fire naturally
- `cleared_count == 4` → this is fine, not a loss (overcommit rule is gone)
- `hands exhausted on all uncleared boards AND cleared_count < 3` → run lost (i.e., every uncleared board has `hands_remaining == 0`; it's not enough for just the active board to be out)
- Survive 8 antes → run won

### 1.2 Per-Board Resources (delete shared ResourcePool)

Each board gets its own hands and discards budget. The shared `ResourcePool` class is retired. Playing a hand on Board A costs Board A's hands, not a global counter.

Default per-board budget: 4 hands, 3 discards per blind. These can be modified by clear bonuses, gambits, etc.

Balatro's native `G.GAME.current_round.hands_left` / `discards_left` must mirror the ACTIVE board's remaining resources at all times. On board switch, sync the new board's values into Balatro's counters.

### 1.3 Keys-Only Deck System (delete standalone deck)

Board.lua currently has two deck systems running in parallel:

- **Standalone deck** (`board.deck.draw_pile`, `board.deck.hand`, `board:draw_hand()`, `board:play_cards()`, `board:discard_cards()`, etc.) — manages its own card tables independently of Balatro
- **Key-based virtual deck** (`board.deck_keys`, `board.draw_keys`, `board.hand_keys`, `board:draw_hand_keys()`, `board:keys_to_cards()`, etc.) — tracks ownership of Balatro's actual Card objects via string keys

**Only the key system survives.** The standalone deck must be deleted entirely. Rationale: Blueprint, HandyMod, Multiplayer, and Ankh all interact with Card objects in `G.hand.cards`, `G.deck.cards`, `G.jokers.cards`. A parallel card system they can't see breaks all interop.

### 1.4 CardArea Methods (no direct .cards assignment)

Current code does `G.hand.cards = hand_cards` and `G.jokers.cards = board.jokers` directly. This bypasses Balatro's CardArea layout engine and is invisible to mods that hook `CardArea:add_card()` / `CardArea:remove_card()`.

All card movement must go through Balatro's CardArea methods:

- Switch-out: `G.hand:remove_card(card)` for each card leaving
- Switch-in: `G.hand:emplace(card)` (or appropriate insertion method) for each card arriving
- Same for `G.jokers` during board switches and JokerBridge operations

This fires Balatro's internal layout updates and any mod hooks attached to card movement.

### 1.5 Free Switching (remove commit/preview system)

Board switching has no resource cost. The commit/preview system in switching.lua (`get_switch_type`) is deleted. Strategic depth comes from per-board resource allocation, not switching penalties.

Switches are allowed during `SELECTING_HAND` and `DRAW_TO_HAND` states. Key bindings: 1/2/3/4 for boards A/B/C/D.

---

## 2. What Gets Deleted

| File/Code | What | Why |
|---|---|---|
| `resource_pool.lua` | Entire file | Replaced by per-board resources in board.lua |
| `board.lua` standalone deck | `board.deck.draw_pile`, `board.deck.hand`, `board.deck.discard_pile`, `board.deck.exile`, `board.deck.full_deck`, `init_standard_deck()`, `shuffle_draw_pile()`, `draw_hand()`, `redraw_fresh_hand()`, `reshuffle_discard()`, `play_cards()`, `discard_cards()`, `exile_cards()`, `restore_exiled_cards()` | Replaced by key-based deck system |
| `switching.lua` `get_switch_type()` | Commit/preview logic | Free switching only |
| `switching.lua` `execute_switch()` standalone deck ops | Lines touching `from_board.deck.hand`, `from_board.deck.draw_pile`, `to_board:redraw_fresh_hand()` | Key system is authoritative |
| `main_phase0c.lua` chip capping | Lines 659–665 in love.update | Condition changes to `not tg_check_blind_won()` (3-of-4); approach kept for now (see section 4) |
| `main_phase0c.lua` `TG.pool` references | All calls to `TG.pool:can_play_hand()`, `TG.pool:use_hand()`, `TG.pool:can_discard()`, `TG.pool:reset()` | Replaced by `TG:get_active_board():can_play_hand()` etc. |
| `gambits.lua` | Entire file (it's a duplicate of gambit.lua) | Duplicate; see section 3.7 |
| `gambit_base.lua` | Move to `dormant/` folder | Ante-spanning gambits deferred to future phase; see section 3.7 |
| `init_phase0c.lua` line `tg_require("core/gambits")` | The load call | gambits.lua is a duplicate |

---

## 3. File-by-File Cleanup Specs

### 3.1 board.lua

**Delete:** Everything in the "DECK MANAGEMENT" section (lines 75–222 in current file) EXCEPT `on_blind_start()`, which needs rewriting.

**Keep & modify:**

- Constructor (`new`): Remove `board.deck` table entirely. Keep `board.deck_keys`, `board.draw_keys`, `board.hand_keys`, `board.discard_keys` (initialized to `{}`).
- `on_blind_start()`: Call `self:reset_deck_keys()` and `self:draw_hand_keys()` instead of the standalone deck methods. Reset per-board resources with bonus calculations.
- All key-based methods (init_deck_keys, add_card_key, draw_hand_keys, discard_key, reset_deck_keys, keys_to_cards, card_key): Keep as-is, these are the authoritative deck system.
- Per-board resource methods (can_play_hand, use_hand, can_discard, use_discard): Keep as-is.
- Money, joker, scoring, hand size, serialization methods: Keep as-is.

**Add:**

- Board D support: No code changes needed — board IDs come from `TG.BOARD_IDS` and colors/labels from config.

### 3.2 switching.lua

**Rewrite `execute_switch()`:** Remove all standalone deck operations. The function should:

1. Save current board's hand keys: move `G.hand` cards back to the from-board's draw_keys via `from_board:discard_key()` or a bulk return method, using `CardArea:remove_card()` for each card.
2. Save current board's Balatro resource counters into `from_board.hands_remaining` / `from_board.discards_remaining`.
3. Shuffle target board's draw_keys, call `to_board:draw_hand_keys()`.
4. Map target board's hand_keys to Card objects via `to_board:keys_to_cards()`.
5. Add those Card objects to `G.hand` via `CardArea:emplace()` or equivalent.
6. Swap jokers via `G.jokers:remove_card()` / `G.jokers:emplace()`.
7. Sync target board's money into `G.GAME.dollars`.
8. Sync target board's resources into `G.GAME.current_round.hands_left` / `discards_left`.

**Rewrite `perform_switch()`:** Remove commit/preview logic. Remove switch resource cost. Add Board D to key map (`["4"] = "D"`).

**Delete:** `get_switch_type()`.

### 3.3 joker_bridge.lua

**Modify `pre_score()` and `post_score()`:** Replace direct `G.jokers.cards = board.jokers` with CardArea methods. Pre-score removes current jokers and emplaces the scoring board's jokers. Post-score reverses this.

**Fix `count_for_board()`:** Always read from `TG:get_board(board_id).jokers` directly, never from `G.jokers.cards`. The bridge is for Balatro's scoring engine; TG's internal queries bypass it.

### 3.4 main_phase0c.lua (main.lua)

**Play hook:** Replace `TG.pool:can_play_hand()` / `TG.pool:use_hand()` with `TG:get_active_board():can_play_hand()` / `TG:get_active_board():use_hand()`. Same for Balatro counter sync.

**Discard hook:** Same pattern — route through active board's per-board resources.

**Win condition check (`tg_check_all_cleared`):** Rename to `tg_check_blind_won`. Count cleared boards across all four. Return true when count >= 3.

**Chip capping (love.update lines 659–665):** The approach stays the same (clamp `G.GAME.chips` below `G.blind.chips` until TG says the blind is won) but the condition changes from `not tg_check_all_cleared()` to `not tg_check_blind_won()`. See section 4 for the longer-term improvement.

**Blind start detection:** Add `TG:sync_board_resources_to_balatro()` call that writes the active board's hands/discards into `G.GAME.current_round`.

**Amplifier (`on_score_calculated`):** When a board clears, apply buff to ALL remaining uncleared boards (section 8.5). The `on_board_cleared` call should iterate all boards and apply the buff globally, not just to the active board.

**Remove:** All references to `TG.pool`. Remove `ResourcePool` require from init.

### 3.5 init_phase0c.lua

**Config changes:**

```lua
TG.BOARD_IDS = { "A", "B", "C", "D" }

TG.CONFIG.TOTAL_BOARDS    = 4
TG.CONFIG.BOARDS_TO_CLEAR = 3

TG.CONFIG.LABELS.D = "BOARD D"
TG.CONFIG.COLORS.D = { r = 0.55, g = 0.78, b = 0.42 }  -- muted green
```

**Remove:** `TG.ResourcePool = tg_require("core/resource_pool")` and `self.pool = TG.ResourcePool:new()`.

**Remove:** `tg_require("core/gambits")` (duplicate of gambit.lua).

**Add:** Board D initialization loop already handled by iterating `TG.BOARD_IDS`.

### 3.6 gambit.lua

**Add Board D templates:**

```lua
-- Board D locks
{ id = "d_pair",      board = "D", hand_type = "Pair",             level_boost = 3 },
{ id = "d_twopair",   board = "D", hand_type = "Two Pair",         level_boost = 3 },
{ id = "d_three",     board = "D", hand_type = "Three of a Kind",  level_boost = 3 },
{ id = "d_straight",  board = "D", hand_type = "Straight",         level_boost = 2 },
{ id = "d_flush",     board = "D", hand_type = "Flush",            level_boost = 2 },
{ id = "d_fullhouse", board = "D", hand_type = "Full House",       level_boost = 2 },
{ id = "d_four",      board = "D", hand_type = "Four of a Kind",   level_boost = 1 },
{ id = "d_high",      board = "D", hand_type = "High Card",        level_boost = 5 },
```

**Fix `assign_random()`:** The board count table is hardcoded to `{ A = 0, B = 0, C = 0 }`. Change to dynamically iterate `TG.BOARD_IDS`:

```lua
local counts = {}
for _, id in ipairs(TG.BOARD_IDS) do counts[id] = 0 end
```

### 3.7 gambit_base.lua / GambitBase System

**DECIDED:** Ship with joker-gambits only. Move `gambit_base.lua` to `dormant/`. Delete `gambits.lua` (duplicate of gambit.lua). The ante-spanning constraint system (GambitBase, registry, present/accept/decline/resolve, chip stack integration) is preserved in dormant/ for a future phase but is not loaded or referenced by any active code.

Context: gambit.lua and gambit_base.lua are two completely separate gambit systems that were sharing the `TG.Gambit` / `TG.Gambits` namespace. gambit.lua (joker-level locks + boosts) works. gambit_base.lua (ante-spanning constraints) is fully scaffolded but has zero registered gambits.

---

## 4. The Chip Capping Problem (Longer-Term)

The frame-level chip clamp (`G.GAME.chips = G.blind.chips - 1` every update) works but is fragile. The root cause: Balatro checks `G.GAME.chips >= G.blind.chips` during its state transition from HAND_PLAYED to the next state, and if true, triggers blind completion.

**Short-term (keep for now):** The clamp with the updated 4/3 condition is functional. The race window is small and in practice rarely fires incorrectly.

**Medium-term improvement:** Instead of clamping every frame, intercept the specific transition. Balatro's `Blind:defeat()` is already overridden — the clamp exists because Balatro has OTHER code paths that check chip totals (UI updates, animation triggers). Identifying and wrapping those specific checks would be more surgical, but requires reverse-engineering Balatro's state machine more deeply.

**Long-term ideal:** Use SMODS event hooks if/when Steamodded exposes a `pre_blind_defeat` or `should_defeat_blind` hook. This would eliminate the monkeypatch entirely.

For this cleanup phase, keep the clamp. It's ugly but it works, and replacing it requires Balatro internals knowledge that's better tested empirically by the Code agents.

---

## 5. Mod Interop Considerations

### 5.1 Blueprint

Blueprint copies joker effects. With JokerBridge doing move-not-copy into `G.jokers.cards`, Blueprint will see the active board's jokers during scoring. This is correct behavior — Blueprint should copy effects of jokers on the board being scored. No special handling needed IF the CardArea method migration is done (section 1.4), because Blueprint hooks `CardArea:add_card()`.

### 5.2 HandyMod

HandyMod modifies hand evaluation and card selection. TG's `get_highlighted_hand_type()` reads from `G.GAME.current_round.current_hand`, which HandyMod also writes to. These should be compatible as long as TG reads AFTER HandyMod writes. Load order matters — TG's hook installation should happen after HandyMod's. SMODS load order is determined by dependency declarations in mod.json.

If HandyMod is a desired hard dependency, add to mod.json:
```json
"optional_dependencies": ["HandyMod"]
```

### 5.3 Balatro Multiplayer

Multiplayer syncs game state between players. TG's `TG.SaveLoad.serialize()` / `deserialize()` already captures board state into `G.GAME.tg_save`. If Multiplayer syncs `G.GAME`, TG state rides along. The risk is that Multiplayer may not sync custom keys in `G.GAME` — this needs testing. If it doesn't, TG may need to register with Multiplayer's sync API.

### 5.4 Ankh

Ankh needs investigation — its interaction surface depends on what it modifies. If it adds new card types or joker effects, the key-based deck system handles it automatically (new cards get new keys). If it modifies the scoring pipeline, the JokerBridge pre/post score pattern should be transparent to it.

### 5.5 General Interop Principle

The single most important thing for interop: **don't bypass Balatro's APIs.** Every time TG directly assigns to `.cards` arrays, manipulates state without going through event managers, or reads from globals that other mods also write to, it creates a collision surface. The CardArea migration (section 1.4) is the highest-impact interop improvement.

---

## 6. Agent Work Split Suggestion

The cleanup naturally splits into two parallel tracks:

### Track A (data layer — suits claude-bacon or claude-kara)
- board.lua: Delete standalone deck, ensure key system is complete
- resource_pool.lua: Delete file
- init_phase0c.lua: Config updates (4 boards, remove pool, remove gambits.lua load)
- gambit.lua: Add Board D templates, fix assign_random() to iterate TG.BOARD_IDS
- gambit_base.lua: Move to dormant/
- gambits.lua: Delete (duplicate)

### Track B (hook layer — suits the other agent)
- main_phase0c.lua: Rewrite play/discard hooks for per-board resources, update win condition to cleared_count >= 3, update chip capping condition
- switching.lua: Rewrite execute_switch() and perform_switch() for keys-only + CardArea methods
- joker_bridge.lua: Migrate to CardArea methods, fix count_for_board()

Track A has no Balatro runtime dependencies — it's pure data structure refactoring. Track B requires testing against the running game. They don't share any functions or call sites, so they can be developed in parallel and merged cleanly.

### Merge point
After both tracks complete, the integration point is `on_blind_start()` in main.lua, which calls into both the board setup (Track A) and the hook/sync logic (Track B). One agent writes the blind lifecycle, the other reviews.

---

## 7. Testing Priorities

In order of "breaks everything if wrong":

1. **Board switch during SELECTING_HAND** — does the hand visually update? Do card positions animate? Can you select and play cards after switching?
2. **Play a hand on Board A, switch to Board B, play a hand** — do scores accumulate independently? Does Board A's score persist?
3. **Clear 3 boards** — does `Blind:defeat()` fire? Does the game advance to shop?
4. **Clear fewer than 3 boards, exhaust all hands** — does the run end?
5. **Shop: buy a joker for Board B while viewing Board A** — does the joker appear in Board B's lineup? Does money deduct from the correct board?
6. **Save mid-blind, reload** — do all 4 boards restore correctly? Do gambit locks persist?
7. **Load with Blueprint/HandyMod active** — does scoring work? Do copied joker effects fire?

---

## 8. Design Decisions (Locked In)

All decisions below are final. Do not revisit during implementation.

### 8.1 Board D Targets: Equal across all 4 boards

All boards use the same target table. No board is a "natural" sacrifice — which board to abandon is a pure player choice each blind. The existing target table (Ante 1: 300/450/600 through Ante 8: 50000/75000/100000) applies identically to A, B, C, and D.

### 8.2 Shop UI: All 4 boards get tabs

Every board can receive purchases in the shop. The sacrifice isn't committed until the player is actually in the blind and allocating hands. A player might buy a joker for Board D in the shop, then sacrifice Board A in the blind — full flexibility.

### 8.3 Board D Gambits: Gambits can target any board including D

Yes, a gambit that locks an abandoned board is free value — but that's the reward for planning ahead. It also means a player who locks all 4 boards is making a real bet on which one they'll sacrifice (locking D to High Card +5 is only free if you actually abandon D). This creates interesting decisions around gambit acquisition in the shop.

### 8.4 Boss Blind Effects: Apply to all 4 boards equally

"Play only Hearts," "first hand debuffed," etc. fire globally across all boards. No dumping restrictions onto the sacrifice lane. The sacrifice board eats the same boss effects as every other board — you just choose not to spend resources clearing it.

### 8.5 Amplifier: Buff applies to ALL remaining uncleared boards

When a board clears, the amplifier buff (`0.15 + (hands_remaining * 0.05)`) applies to every remaining uncleared board. This makes early clears feel powerful and rewards efficient play. It also creates a nice tension: spend an extra hand to secure the clear safely, or rush it with hands left over to buff everything else.

With per-board resources, `hands_remaining` is the clearing board's remaining hands at the moment it clears. A board cleared with 3 hands left = `0.15 + (3 * 0.05)` = 30% buff to all other uncleared boards. Buffs stack additively (two boards clearing early can stack significant buffs on the remaining boards).

### 8.6 Gambit System Scope: Joker-gambits only (Phase 1)

Ship with the joker-level gambit system (board locks + hand type boosts). The ante-spanning constraint system (gambit_base.lua) moves to `dormant/` for a future phase. See section 3.7.
