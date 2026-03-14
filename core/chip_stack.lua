--[[
    TRIPLE GAMBIT - core/chip_stack.lua
    Gambit win/loss visual economy.
    Tracks chip stack gains and losses for the ChipStackUI display.
]]

local ChipStack = {}
ChipStack.__index = ChipStack

function ChipStack:new()
    local o = setmetatable({}, self)
    o.entries  = {}   -- { amount, board_id, type ("gain"/"loss"), timestamp }
    o.total    = 0
    return o
end

function ChipStack:add(amount, board_id, entry_type)
    table.insert(self.entries, {
        amount    = amount,
        board_id  = board_id,
        type      = entry_type or "gain",
        timestamp = os.time(),
    })
    if entry_type == "gain" then
        self.total = self.total + amount
    else
        self.total = self.total - amount
    end
end

function ChipStack:serialize()
    return {
        total   = self.total,
        entries = self.entries,
    }
end

function ChipStack:deserialize(data)
    if not data then return end
    self.total   = data.total   or 0
    self.entries = data.entries or {}
end

return ChipStack
