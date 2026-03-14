--[[
    Triple Gambit - Chip Stack
    Tracks the physical stack of gambit chips earned this run.
    Successful gambits add whole chips; failed ones add fragments.
    Both are rendered by gambit_chip_ui.lua.
]]

TG = TG or {}

-- ============================================================
-- TIER COLORS (used by both chip stack and gambit chip UI)
-- ============================================================

TG.ChipStack = {}

TG.ChipStack.TIER_COLORS = {
    copper = { r = 0.80, g = 0.50, b = 0.25 },
    silver = { r = 0.78, g = 0.78, b = 0.82 },
    gold   = { r = 0.95, g = 0.80, b = 0.20 },
}

-- ============================================================
-- CLASS
-- ============================================================

TG.ChipStack.__index = TG.ChipStack

function TG.ChipStack:new()
    local cs = setmetatable({}, TG.ChipStack)
    cs.chips     = {}   -- Whole chips (gambit successes)
    cs.fragments = {}   -- Broken fragments (gambit failures)
    return cs
end

-- ============================================================
-- ADD CHIPS / FRAGMENTS
-- ============================================================

--- Add a whole chip (gambit success).
--- chip_data = { gambit_id, gambit_name, tier, cost, reward, ante, success=true }
function TG.ChipStack:add_chip(chip_data)
    table.insert(self.chips, {
        gambit_id   = chip_data.gambit_id,
        gambit_name = chip_data.gambit_name,
        tier        = chip_data.tier or "copper",
        cost        = chip_data.cost or 0,
        reward      = chip_data.reward or 0,
        ante        = chip_data.ante or 0,
        success     = true,
        -- Visual extras added at runtime, not serialized
        y_offset    = 0,
        scale       = 1.0,
    })
    print(string.format("[TG] ChipStack: +1 %s chip (%s)", chip_data.tier, chip_data.gambit_name))
end

--- Add a fragment (gambit failure).
--- frag_data = { gambit_id, gambit_name, tier, cost, ante, success=false }
function TG.ChipStack:add_fragment(frag_data)
    -- Each fragment gets a randomized visual offset so they scatter naturally
    table.insert(self.fragments, {
        gambit_id   = frag_data.gambit_id,
        gambit_name = frag_data.gambit_name,
        tier        = frag_data.tier or "copper",
        cost        = frag_data.cost or 0,
        ante        = frag_data.ante or 0,
        success     = false,
        -- Randomized scatter for rendering
        x_offset    = (math.random() - 0.5) * 30,
        y_offset    = math.random() * 12,
        rotation    = (math.random() - 0.5) * 1.2,
        scale       = 0.5 + math.random() * 0.5,
        alpha       = 0.5 + math.random() * 0.4,
    })
    print(string.format("[TG] ChipStack: +1 fragment (%s, failed)", frag_data.gambit_name))
end

-- ============================================================
-- QUERIES
-- ============================================================

function TG.ChipStack:get_chip_count()
    return #self.chips
end

function TG.ChipStack:get_fragment_count()
    return #self.fragments
end

--- Total $ profit across all resolved gambits in the stack.
function TG.ChipStack:get_total_profit()
    local profit = 0
    for _, chip in ipairs(self.chips) do
        profit = profit + (chip.reward - chip.cost)
    end
    for _, frag in ipairs(self.fragments) do
        profit = profit - frag.cost  -- Lost the buy-in
    end
    return profit
end

-- ============================================================
-- SERIALIZATION
-- ============================================================

function TG.ChipStack:serialize()
    local chips_data = {}
    for _, c in ipairs(self.chips) do
        table.insert(chips_data, {
            gambit_id   = c.gambit_id,
            gambit_name = c.gambit_name,
            tier        = c.tier,
            cost        = c.cost,
            reward      = c.reward,
            ante        = c.ante,
        })
    end

    local frags_data = {}
    for _, f in ipairs(self.fragments) do
        table.insert(frags_data, {
            gambit_id   = f.gambit_id,
            gambit_name = f.gambit_name,
            tier        = f.tier,
            cost        = f.cost,
            ante        = f.ante,
        })
    end

    return { chips = chips_data, fragments = frags_data }
end

function TG.ChipStack:deserialize(data)
    self.chips     = {}
    self.fragments = {}

    if data.chips then
        for _, c in ipairs(data.chips) do
            self:add_chip(c)
        end
    end

    if data.fragments then
        for _, f in ipairs(data.fragments) do
            self:add_fragment(f)
        end
    end
end

return TG.ChipStack