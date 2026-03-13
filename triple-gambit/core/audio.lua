--[[
    TRIPLE GAMBIT - core/audio.lua
    Procedural chip audio system.

    ARCHITECTURE OVERVIEW
    ─────────────────────
    The system has five independent layers that compose together at play time:

    1. TIMED CASCADE QUEUE
       Scoring a hand pushes N chip beats into a queue, staggered ~60ms apart.
       Audio.update(dt) drains the queue frame-by-frame. This means a hand's
       scoring sounds play out over 300–700ms as a cascade, not as one instant
       click. Beat count scales with how large the score is relative to the
       board's target. The queue is flushed on every new play_score call so
       fast consecutive hands don't accumulate a backlog.

    2. HAND-TYPE PITCH ARC
       Within a single cascade, each beat's pitch follows a curve determined
       by the hand type. Flush is flat (all beats at the same pitch — smooth,
       uniform). Straight steps upward evenly. Four of a Kind accelerates
       exponentially toward a heavy landing. Full House follows an S-curve.
       High Card introduces small random jitter. This gives each hand type
       a sonic character and lets gambit-locked boards develop an identity
       the player recognises by ear.

    3. PER-BOARD PITCH IDENTITY
       Board A sounds at its root pitch (1.00). Board B is a major second up
       (×1.122). Board C is a major third up (×1.260). These intervals are
       musically consonant, so boards scoring near-simultaneously don't clash.

    4. PROGRESS-BASED PITCH MODULATION
       The final pitch of each beat also rises as the board nears its target.
       Below 50% completion the modulation is barely perceptible. At 90%+ the
       pitch peaks noticeably. The last-moment clear sounds distinct and urgent
       compared to clearing with hands to spare.

    5. VOLUME DUCKING
       Loud one-shot events (board clear, board death, run over) briefly reduce
       the volume of ongoing scoring sounds via a duck_factor that recovers at
       2.5 units/second. Scoring ticks don't muddy the clear cue.

    ADDITIONAL FEATURES
    ───────────────────
    · Chip ID cycling: five chip files (chip1–chip5) rotate per-board so no
      two consecutive beats use the same sample.
    · Cooldowns: non-cascade events have a minimum gap between plays.
    · Same-frame deduplication: identical sound IDs within one update are
      collapsed to one call, preventing clipping artifacts.
    · Stereo panning: Board A panned left-center, Board B center, Board C
      right-center. Uses love.audio.Source:setPosition() for 3D panning.
      Auto-detected on init; falls back gracefully to PLAY_SOUND (mono) if
      Balatro's sound file paths can't be resolved.
    · One-off warning log: missing/broken sound IDs are printed once, then
      silently ignored for the rest of the session.

    PUBLIC API
    ──────────
    Audio.play(event [, board_id])
        Play a named event. board_id defaults to TG.active_board_id.

    Audio.play_for_board(event, board_id)
        Explicit board context. Use when the event concerns a board other
        than the currently active one (e.g. amplifier buff on a receiving board).

    Audio.play_score(board_id, scored, deficit, hand_type)
        Build and enqueue a hand-scoring cascade. Picks cascade length from
        scored/target ratio, arc from hand_type.
        deficit < 0 means overkill (scored more than the board needed).
        hand_type is a Balatro hand string: "Flush", "Straight", etc.

    Audio.play_raw(sound_id, vol, pitch)
        Bypass the event system. One-off raw Balatro sound ID.

    Audio.update(dt)
        Drain cascade queue, recover duck_factor, clear frame dedup.
        Call from TG.Hooks.update every frame.

    Audio.init()
        Reset all state. Call once from load_ui() after Balatro is ready.
        Probes for stereo panning capability.
]]

TG       = TG or {}
TG.Audio = TG.Audio or {}

local Audio = TG.Audio

-- ============================================================
-- SUPPORT STATE
-- ============================================================

-- Cooldown timestamps for non-cascade events
local last_played = {}

-- Same-frame dedupe table
local _frame_played = {}

-- Ducking system state
local duck_factor = 1.0
local duck_target = 1.0
local duck_rate   = 2.5   -- recovers 2.5 units/sec toward 1.0

-- Warned sound IDs (missing / failing)
local _warned_ids = {}

-- ============================================================
-- VOLUME CATEGORY MIX
-- ============================================================

Audio.MIX = {
    scoring      = 0.48,   -- cascade chip ticks — frequent, sit under the action layer
    actions      = 0.68,   -- switch, block, gambit confirm
    board_events = 0.92,   -- clear, blind start, board death — notable but not jingles
    run_events   = 1.00,   -- win / lose jingles — always full
    shop         = 0.58,   -- buy, sell feedback
}

-- ============================================================
-- PER-BOARD PITCH PROFILES
-- ============================================================

Audio.BOARD_PITCH = {
    A = 1.000,
    B = 1.122,
    C = 1.260,
    D = 1.498,   -- perfect fifth above A (×1.498 ≈ 3:2)
}

-- ============================================================
-- PER-BOARD STEREO PAN POSITIONS
-- ============================================================

Audio.BOARD_PAN = {
    A = -0.45,
    B =  0.00,
    C =  0.45,
    D =  0.70,
}

-- ============================================================
-- CHIP SOUND POOL
-- ============================================================

local CHIP_ALL   = { "chip1", "chip2", "chip3", "chip4", "chip5" }
local CHIP_HEAVY = { "chip3", "chip4", "chip5" }

local chip_cursor = {}   -- { A=1, B=1, C=1, D=1 } — reset in Audio.init()

local function next_chip(board_id)
    local key = board_id or "A"
    local cur = chip_cursor[key] or 1
    local id  = CHIP_ALL[cur]
    chip_cursor[key] = (cur % #CHIP_ALL) + 1
    return id
end

local function random_heavy_chip()
    return CHIP_HEAVY[math.random(#CHIP_HEAVY)]
end

-- ============================================================
-- HAND-TYPE BASE PITCH MODIFIERS
-- ============================================================

local HAND_PITCH = {
    ["High Card"]        = 0.94,
    ["Pair"]             = 0.98,
    ["Two Pair"]         = 1.00,
    ["Three of a Kind"]  = 1.04,
    ["Straight"]         = 1.08,
    ["Flush"]            = 0.95,
    ["Full House"]       = 1.10,
    ["Four of a Kind"]   = 0.90,
    ["Straight Flush"]   = 1.14,
    ["Royal Flush"]      = 1.20,
}

-- ============================================================
-- HAND-TYPE CASCADE PITCH ARCS
-- ============================================================

local HAND_ARC = {
    ["High Card"] = function(i, n)
        return 1.0 + (math.random() * 0.06 - 0.03)
    end,
    ["Pair"] = function(i, n)
        return 1.0 + (i - 1) / math.max(n - 1, 1) * 0.04
    end,
    ["Two Pair"] = function(i, n)
        return 1.0 + (i - 1) / math.max(n - 1, 1) * 0.07
    end,
    ["Three of a Kind"] = function(i, n)
        return 1.0 + (i - 1) / math.max(n - 1, 1) * 0.09
    end,
    ["Straight"] = function(i, n)
        return 1.0 + (i - 1) / math.max(n - 1, 1) * 0.14
    end,
    ["Flush"] = function(i, n)
        return 1.0
    end,
    ["Full House"] = function(i, n)
        local t = (i - 1) / math.max(n - 1, 1)
        return 1.0 + 0.14 * (3 * t * t - 2 * t * t * t)
    end,
    ["Four of a Kind"] = function(i, n)
        local t = (i - 1) / math.max(n - 1, 1)
        return 1.0 + (t * t) * 0.20
    end,
    ["Straight Flush"] = function(i, n)
        return 1.06 + (i - 1) / math.max(n - 1, 1) * 0.24
    end,
    ["Royal Flush"] = function(i, n)
        return 1.12 + (i - 1) / math.max(n - 1, 1) * 0.28
    end,
}

local function default_arc(i, n)
    return 1.0 + (i - 1) / math.max(n - 1, 1) * 0.06
end

local function get_arc(hand_type, i, n)
    local arc = hand_type and HAND_ARC[hand_type]
    if arc then return arc(i, n) end
    return default_arc(i, n)
end

-- ============================================================
-- COOLDOWN HELPERS
-- ============================================================

local function check_cooldown(event, def)
    if not def.cooldown or def.cooldown <= 0 then
        return true
    end
    if not love or not love.timer or not love.timer.getTime then
        return true
    end
    local now  = love.timer.getTime()
    local last = last_played[event] or 0
    return (now - last) >= def.cooldown
end

local function record_play(event)
    if not love or not love.timer or not love.timer.getTime then
        return
    end
    last_played[event] = love.timer.getTime()
end

-- ============================================================
-- DUCKING HELPERS
-- ============================================================

local function apply_duck(value)
    duck_factor = math.min(duck_factor, value)
    duck_target = 1.0
end

-- ============================================================
-- PROGRESS-BASED PITCH MODULATION
-- ============================================================

local function progress_pitch_factor(board_id)
    local board = TG.get_board and TG:get_board(board_id) or nil
    if not board or not board.target or board.target <= 0 then
        return 1.0
    end

    local pct = board.current_score / board.target
    pct = math.max(0, math.min(1, pct))

    if pct < 0.70 then
        return 1.0 + pct * 0.05
    elseif pct < 0.90 then
        return 1.035 + (pct - 0.70) * 0.20
    else
        return 1.075 + (pct - 0.90) * 0.35
    end
end

-- ============================================================
-- CASCADE BEAT COUNT
-- ============================================================

local function cascade_beat_count(scored, board_target)
    if not board_target or board_target <= 0 then return 3 end
    local pct = scored / board_target
    if     pct < 0.03 then return 2
    elseif pct < 0.08 then return 3
    elseif pct < 0.15 then return 4
    elseif pct < 0.25 then return 5
    elseif pct < 0.40 then return 7
    elseif pct < 0.60 then return 9
    else                    return 12
    end
end

-- ============================================================
-- CASCADE BEAT INTERVALS
-- ============================================================

local function beat_delay(beat_index)
    if beat_index == 1 then return 0 end
    return math.max(0.035, 0.070 - (beat_index - 2) * 0.005)
end

-- ============================================================
-- EVENT DEFINITIONS
-- ============================================================

local EVENTS = {
    amplifier_stacked = {
        sound_id       = "amplifier_stacked",
        volume         = 0.75,
        pitch          = 1.00,
        category       = "actions",
        cooldown       = 0.05,
        board_pitch    = true,
        progress_pitch = true,
        ducks          = nil,
    },
    board_dead = {
        sound_id       = "board_dead",
        volume         = 1.00,
        pitch          = 1.00,
        category       = "board_events",
        cooldown       = 0.2,
        board_pitch    = false,
        progress_pitch = false,
        ducks          = 0.50,
    },
    near_loss = {
        sound_id       = "near_loss",
        volume         = 0.70,
        pitch          = 1.00,
        category       = "actions",
        cooldown       = 1.0,
        board_pitch    = false,
        progress_pitch = false,
        ducks          = nil,
    },
    switch_board = {
        sound_id       = "switch_board",
        volume         = 0.80,
        pitch          = 1.00,
        category       = "actions",
        cooldown       = 0.03,
        board_pitch    = true,
        progress_pitch = false,
        ducks          = nil,
    },
    commit_switch = {
        sound_id       = "commit_switch",
        volume         = 0.90,
        pitch          = 1.00,
        category       = "actions",
        cooldown       = 0.03,
        board_pitch    = false,
        progress_pitch = false,
        ducks          = nil,
    },
    action_blocked = {
        sound_id       = "action_blocked",
        volume         = 0.90,
        pitch          = 1.00,
        category       = "actions",
        cooldown       = 0.05,
        board_pitch    = false,
        progress_pitch = false,
        ducks          = nil,
    },
    gambit_blocked = {
        sound_id       = "gambit_blocked",
        volume         = 0.95,
        pitch          = 1.00,
        category       = "actions",
        cooldown       = 0.05,
        board_pitch    = false,
        progress_pitch = false,
        ducks          = nil,
    },
    gambit_activated = {
        sound_id       = "gambit_activated",
        volume         = 0.85,
        pitch          = 1.00,
        category       = "actions",
        cooldown       = 0.05,
        board_pitch    = false,
        progress_pitch = false,
        ducks          = nil,
    },
    gambit_deactivated = {
        sound_id       = "gambit_deactivated",
        volume         = 0.70,
        pitch          = 1.00,
        category       = "actions",
        cooldown       = 0.05,
        board_pitch    = false,
        progress_pitch = false,
        ducks          = nil,
    },
    run_won = {
        sound_id       = "run_won",
        volume         = 1.00,
        pitch          = 1.00,
        category       = "run_events",
        cooldown       = 1.0,
        board_pitch    = false,
        progress_pitch = false,
        ducks          = 0.40,
    },
    run_lost = {
        sound_id       = "run_lost",
        volume         = 1.00,
        pitch          = 1.00,
        category       = "run_events",
        cooldown       = 1.0,
        board_pitch    = false,
        progress_pitch = false,
        ducks          = 0.40,
    },
}

-- ============================================================
-- STEREO PANNING SYSTEM
-- ============================================================

Audio._panning_available = false
Audio._sound_prefix      = nil    -- e.g. "resources/"

local PROBE_PATHS = {
    "resources/",
    "assets/sounds/",
    "sounds/",
    "resources/sounds/",
}

local function probe_panning()
    if not (love and love.audio and love.audio.newSource) then return false end
    for _, prefix in ipairs(PROBE_PATHS) do
        local ok, src = pcall(love.audio.newSource, prefix .. "chip1.ogg", "static")
        if ok and src then
            Audio._panning_available = true
            Audio._sound_prefix      = prefix
            pcall(function() src:release() end)
            print(string.format("[TG] Audio: stereo panning via love.audio ('%s')", prefix))
            return true
        end
    end
    print("[TG] Audio: stereo panning unavailable — falling back to mono PLAY_SOUND()")
    return false
end

-- Check if an .ogg file exists for a given sound_id
local function ogg_exists(sound_id)
    if Audio._panning_available and Audio._sound_prefix then
        if love and love.filesystem and love.filesystem.getInfo then
            return love.filesystem.getInfo(
                Audio._sound_prefix .. sound_id .. ".ogg") ~= nil
        end
    end
    return true
end

-- ============================================================
-- CHIP CASCADE QUEUE
-- ============================================================

local cascade_queue   = {}
local cascade_elapsed = 0

local function flush_cascade()
    cascade_queue   = {}
    cascade_elapsed = 0
end

local function push_cascade(board_id, scored, deficit, hand_type)
    flush_cascade()

    local ok, board = pcall(function() return TG:get_board(board_id) end)
    local target    = (ok and board and board.target > 0) and board.target or 300

    local n_beats   = cascade_beat_count(scored, target)
    local overkill  = deficit ~= nil and deficit < 0

    local board_p   = Audio.BOARD_PITCH[board_id] or 1.0
    local prog_p    = progress_pitch_factor(board_id)
    local hand_base = hand_type and HAND_PITCH[hand_type] or 1.0
    local pan       = Audio.BOARD_PAN[board_id] or 0.0

    local base_vol = 0.85 * (Audio.MIX["scoring"] or 0.48) * duck_factor

    local t_cursor = 0.0

    for i = 1, n_beats do
        t_cursor = t_cursor + beat_delay(i)

        local sid
        if overkill and i == n_beats then
            sid = random_heavy_chip()
        else
            sid = next_chip(board_id)
        end

        local arc_factor = get_arc(hand_type, i, n_beats)
        local beat_pitch = board_p * hand_base * prog_p * arc_factor

        local vol_scale
        if i == 1 then
            vol_scale = 0.75
        elseif i == n_beats then
            vol_scale = 1.20
        else
            vol_scale = 1.00
        end
        local beat_vol = base_vol * vol_scale

        table.insert(cascade_queue, {
            sound_id = sid,
            vol      = beat_vol,
            pitch    = beat_pitch,
            pan      = pan,
            fire_at  = t_cursor,
        })
    end
end

-- ============================================================
-- STEREO PLAY + FALLBACK
-- ============================================================

local function play_panned(sound_id, vol, pitch, pan)
    -- Option A: skip missing sounds entirely (with one-time warning)
    if not ogg_exists(sound_id) then
        if not _warned_ids[sound_id] then
            _warned_ids[sound_id] = true
            print(string.format("[TG] Audio: missing .ogg for '%s', skipping", sound_id))
        end
        return
    end

    if Audio._panning_available and Audio._sound_prefix then
        local path = Audio._sound_prefix .. sound_id .. ".ogg"
        local ok, src = pcall(love.audio.newSource, path, "static")
        if ok and src then
            local ok2 = pcall(function()
                src:setVolume(math.max(0, math.min(1.5, vol)))
                src:setPitch(math.max(0.3, math.min(3.0, pitch)))
                src:setPosition(pan * 6.0, 0, -1)
                src:setRelative(false)
                love.audio.setListenerPosition(0, 0, 0)
                love.audio.setListenerDirection(0, 0, -1, 0, 1, 0)
                src:play()
            end)
            if ok2 then return end
        end
    end

    -- Fallback to Balatro's PLAY_SOUND, still safe because ogg_exists() passed
    pcall(PLAY_SOUND, {
        sound_code = sound_id,
        vol        = vol,
        per        = pitch,
    })
end

-- ============================================================
-- FIRE QUEUED BEAT
-- ============================================================

local function fire_queued_beat(entry)
    if _frame_played[entry.sound_id] then return end

    local vol   = math.max(0, math.min(1.5, entry.vol * duck_factor))
    local pitch = math.max(0.3, math.min(3.0, entry.pitch))

    if Audio._panning_available and entry.pan ~= 0 then
        play_panned(entry.sound_id, vol, pitch, entry.pan)
    else
        -- Option A: skip missing sounds entirely
        if not ogg_exists(entry.sound_id) then
            if not _warned_ids[entry.sound_id] then
                _warned_ids[entry.sound_id] = true
                print(string.format("[TG] Audio: missing .ogg for '%s', skipping", entry.sound_id))
            end
            return
        end
        local ok, err = pcall(PLAY_SOUND, {
            sound_code = entry.sound_id,
            vol        = vol,
            per        = pitch,
        })
        if not ok and not _warned_ids[entry.sound_id] then
            _warned_ids[entry.sound_id] = true
            print(string.format("[TG] Audio: '%s' failed: %s", entry.sound_id, tostring(err)))
        end
    end

    _frame_played[entry.sound_id] = true
end

-- ============================================================
-- CORE _do_play (for non-cascade events)
-- ============================================================

local function _do_play(def, event_name, board_id)
    if not PLAY_SOUND then return end

    local sound_id
    if type(def.sound_id) == "function" then
        sound_id = def.sound_id(board_id or (TG and TG.active_board_id) or "A")
    else
        sound_id = def.sound_id
    end
    if not sound_id then return end

    if _frame_played[sound_id] then return end
    if not check_cooldown(event_name, def) then return end

    -- Option A: skip missing sounds entirely
    if not ogg_exists(sound_id) then
        if not _warned_ids[sound_id] then
            _warned_ids[sound_id] = true
            print(string.format("[TG] Audio: missing .ogg for '%s', skipping", sound_id))
        end
        return
    end

    local vol = (def.volume or 0.75)
              * (Audio.MIX[def.category] or 1.0)
              * duck_factor

    local pitch = def.pitch or 1.0
    if def.board_pitch and board_id then
        pitch = pitch * (Audio.BOARD_PITCH[board_id] or 1.0)
    end
    if def.progress_pitch and board_id then
        pitch = pitch * progress_pitch_factor(board_id)
    end

    vol   = math.max(0.0, math.min(1.5, vol))
    pitch = math.max(0.3, math.min(3.0, pitch))

    local pan = board_id and (Audio.BOARD_PAN[board_id] or 0.0) or 0.0
    if Audio._panning_available and def.board_pitch and pan ~= 0 then
        play_panned(sound_id, vol, pitch, pan)
    else
        local ok, err = pcall(PLAY_SOUND, {
            sound_code = sound_id,
            vol        = vol,
            per        = pitch,
        })
        if not ok and not _warned_ids[sound_id] then
            _warned_ids[sound_id] = true
            print(string.format("[TG] Audio: '%s' failed: %s", sound_id, tostring(err)))
        end
    end

    _frame_played[sound_id] = true
    record_play(event_name)

    if def.ducks then
        apply_duck(def.ducks)
    end
end

-- ============================================================
-- PUBLIC API
-- ============================================================

function Audio.play(event, board_id)
    local def = EVENTS[event]
    if not def then return end
    board_id = board_id or (TG and TG.active_board_id)
    _do_play(def, event, board_id)
end

function Audio.play_for_board(event, board_id)
    Audio.play(event, board_id)
end

function Audio.play_score(board_id, scored, deficit, hand_type)
    if not (scored and scored > 0) then return end
    push_cascade(board_id, scored, deficit, hand_type)
end

function Audio.play_raw(sound_id, vol, pitch)
    if not PLAY_SOUND then return end
    if _frame_played[sound_id] then return end

    -- Option A: skip missing sounds entirely
    if not ogg_exists(sound_id) then
        if not _warned_ids[sound_id] then
            _warned_ids[sound_id] = true
            print(string.format("[TG] Audio: missing .ogg for '%s' (raw), skipping", sound_id))
        end
        return
    end

    local ok, err = pcall(PLAY_SOUND, {
        sound_code = sound_id,
        vol        = vol or 0.75,
        per        = pitch or 1.0,
    })
    if ok then
        _frame_played[sound_id] = true
    elseif not _warned_ids[sound_id] then
        _warned_ids[sound_id] = true
        print(string.format("[TG] Audio: raw '%s' failed: %s", sound_id, tostring(err)))
    end
end

function Audio.update(dt)
    if #cascade_queue > 0 then
        cascade_elapsed = cascade_elapsed + dt
        for i = #cascade_queue, 1, -1 do
            local entry = cascade_queue[i]
            if cascade_elapsed >= entry.fire_at then
                fire_queued_beat(entry)
                table.remove(cascade_queue, i)
            end
        end
    end

    if duck_factor < duck_target then
        duck_factor = math.min(duck_target, duck_factor + duck_rate * dt)
    end

    _frame_played = {}
end

function Audio.init()
    last_played     = {}
    _frame_played   = {}
    _warned_ids     = {}
    cascade_queue   = {}
    cascade_elapsed = 0
    duck_factor     = 1.0
    duck_target     = 1.0
    chip_cursor     = { A = 1, B = 1, C = 1, D = 1 }

    probe_panning()

    local n = 0
    for _ in pairs(EVENTS) do n = n + 1 end
    print(string.format(
        "[TG] Audio initialized. Events: %d. Panning: %s. Hand arcs: %d.",
        n,
        Audio._panning_available and "love.audio" or "mono fallback",
        (function() local k=0; for _ in pairs(HAND_ARC) do k=k+1 end; return k end)()
    ))
end

return Audio