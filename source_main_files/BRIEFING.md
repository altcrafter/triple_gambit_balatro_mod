# Triple Gambit — Handoff Briefing

## What this is

A Balatro SMODS mod. Three simultaneous boards (A, B, C), each with its own deck, jokers, money, and score target. Shared resource pool (hands/discards). Beat 2 of 3 boards per blind to advance. Beat all 3 = lose (overcommit). 8 antes to win.

Framework: **Steamodded (>=1.0.0~)**. No Lovely (crashes on macOS). Module loader uses `love.filesystem.load()`. Entry point: `main.lua`. All hooks monkeypatch `love.draw`/`love.update`/`love.keypressed`/`love.mousepressed` + wrap `G.FUNCS.play_cards_from_highlighted` and `G.FUNCS.discard_cards_from_highlighted`.

## Files included

- **main_phase0c.lua** — Best triple-board main (725 lines). Farthest along with working hooks.
- **init_phase0c.lua** — Matching init (259 lines). Loads 11 modules, sets up 3 boards.
- **mod.json** — SMODS manifest.

## Balatro globals the mod depends on

```
G.GAME              — run state (dollars, chips, ante, hands, deck)
G.hand / G.deck / G.jokers / G.consumeables — card areas with .cards arrays
G.blind             — current blind object
G.E_MANAGER         — event queue (add_event for async operations)
G.FUNCS             — button callbacks (play_cards_from_highlighted, discard_cards_from_highlighted)
G.STATE / G.STATES  — state machine (SELECTING_HAND, HAND_PLAYED, DRAW_TO_HAND, SHOP, ROUND_EVAL, pack states)
G.TILESCALE / G.TILESIZE — coordinate system (screen_x = game_x * G.TILESCALE * G.TILESIZE)
G.GAME.current_round.hands_left / discards_left — Balatro's native resource counters
G.GAME.chips        — accumulated score this blind
G.blind.chips       — target score to beat
```

Scoring is async: `play_cards_from_highlighted` triggers play → events run → chips accumulate in `G.GAME.chips` → when `chips >= G.blind.chips`, `Blind:defeat()` fires.

## Architecture (TG namespace)

```
TG.BOARD_IDS = {"A", "B", "C"}
TG.boards[id]       — Board objects (deck_keys, jokers, money, current_score, target, is_cleared)
TG.active_board_id   — currently active board
TG.pool              — ResourcePool (hands_remaining, discards_remaining, switches_remaining)
TG.Switching         — board switch logic (keys 1/2/3)
TG.Shop              — shop generation, buy/sell hooks, per-board money routing
TG.JokerBridge       — swaps board.jokers into G.jokers.cards for scoring (move, not copy)
TG.Gambit            — hand-type lock + level boost system
TG.Amplifier         — clear-early scoring buff
TG.ChipStack         — gambit win/loss visual economy
TG.SaveLoad          — persistence via G.GAME.tg_save
TG.Audio             — procedural audio (5 layers, hand-type pitch arcs, stereo panning)
TG.UI.*              — StatusBar, ResourceDisplay, GambitDisplay, BoardTransition, ShopUI, ChipStackUI, Shader
```

## Gambit system

Every shop joker carries a hidden gambit: board + hand type + level boost.

- 24 templates: 8 hand types × 3 boards
- Level boost inversely proportional to hand rarity: High Card +5, Pair +4, ... Four of a Kind +1
- Buying the joker **locks** that board to that hand type (other hands blocked)
- The boost is applied in the play hook before `orig_play`, removed in `on_score_calculated` after chip delta capture
- Weighted assignment: boards with fewer gambits get more shop tags
- GambitBase: ante-spanning constraint system, gambits persist across blinds within an ante

## Amplifier

When a board clears: remaining boards get `buff = 0.15 + (hands_remaining × 0.05)`. Clearing with 4 hands left = 35% scoring buff. Stacks additively. Resets each blind.

## Win/loss

- **Win blind:** 2 of 3 boards cleared → `Blind:defeat()` allowed
- **Lose (overcommit):** all 3 cleared → `TG:on_run_lost("overcommit")`
- **Lose (exhausted):** 0 hands remaining, not enough boards cleared
- **Win run:** survive 8 antes
- Cleared boards get `target × 1.6` scaling next blind

## What broke (known issues in main_phase0c.lua)

1. **Chip capping hack** (lines 659-665): clamps `G.GAME.chips` to `blind.chips - 1` every frame to prevent Balatro from auto-triggering blind victory. Fragile — races with Balatro's own state transitions.

2. **Blind.defeat override** (lines 568-598): suppresses victory until all boards clear, but double-fire possible if `on_score_calculated` and `Blind.defeat` trigger in the same event cycle.

3. **Money sync** (lines 693-712): works in shop but has edge cases around booster pack states (TAROT_PACK, SPECTRAL_PACK, etc.). Pack-opening counts as "still in shop" but the state detection is patchy.

4. **JokerBridge**: move-not-copy works for scoring, but Balatro's native tooltip/UI doesn't know about the swap — joker tooltips show stale data.

5. **Boss blind effects**: "play only Hearts", "first hand debuffed" etc. fire globally and don't know about per-board state.

6. **Lazy hook install** (lines 271-372): waits for `G.FUNCS` to be populated, but if a mod loads after TG and also wraps these functions, the chain breaks.

7. **Per-board resources** (Phase 0d init, not included): the later design gave each board its own hands/discards (4H/3D each) instead of a shared pool. The Phase 0c code here still uses a shared pool. The Phase 0d init was written but its matching main.lua wasn't completed.

## Hook surface (what main_phase0c.lua actually patches)

```
Game:start_run(...)                — calls on_run_start() after orig
Blind:set_blind(...)               — syncs ante after orig
Blind:defeat(...)                  — blocks unless all boards cleared
Game:save_progress(...)            — serializes TG state into G.GAME.tg_save
Game:load_run(...)                 — deserializes on load
love.draw(...)                     — appends TG.Hooks.draw()
love.update(dt, ...)               — state machine detection, chip capping, money sync
love.keypressed(key, ...)          — intercepts 1/2/3 for board switching
love.mousepressed(x, y, ...)       — intercepts status bar clicks
G.FUNCS.play_cards_from_highlighted — resource check, gambit validation, level boost, JokerBridge pre/post
G.FUNCS.discard_cards_from_highlighted — resource check, pool decrement
```

## Config (from init_phase0c.lua)

```
HANDS_PER_BLIND      = 4        DISCARDS_PER_BLIND = 3
SWITCHES_PER_BLIND   = 1        BOARDS_TO_CLEAR    = 3
MAX_JOKERS_PER_BOARD = 5        FINAL_ANTE         = 8
STARTING_MONEY       = 4        REROLL_COST        = 5
CLEAR_BUFF_BASE      = 0.15     CLEAR_BUFF_PER_HAND = 0.05
```

Target table (per ante × blind type):
```
Ante 1: 300 / 450 / 600
Ante 2: 800 / 1200 / 1600
Ante 3: 2000 / 3000 / 4000
Ante 4: 5000 / 7500 / 10000
Ante 5: 11000 / 16500 / 22000
Ante 6: 20000 / 30000 / 40000
Ante 7: 35000 / 52500 / 70000
Ante 8: 50000 / 75000 / 100000
```

## Modules referenced but source not included

These exist on disk (`~/Documents/gambit_mod_balatro/claude_mod/TripleGambit/`) but aren't in this handoff:

```
core/board.lua, core/resource_pool.lua, core/switching.lua, core/shop_logic.lua,
core/joker_bridge.lua, core/save_load.lua, core/amplifier.lua, core/gambit.lua,
core/gambit_base.lua, core/gambits.lua, core/chip_stack.lua, core/audio.lua
ui/status_bar.lua, ui/resource_display.lua, ui/gambit_chip_ui.lua,
ui/gambit_display.lua, ui/board_transition.lua, ui/shop_ui.lua, ui/tg_shader.lua
```

The `TripleGambit-Ren/` folder also has: `core/lamp.lua`, `core/progression.lua`, `ui/lamp_ui.lua` (Lamp era, dormant).
