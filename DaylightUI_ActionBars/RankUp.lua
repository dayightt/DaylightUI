-- New ranks on your bars: when you learn rank N of a spell, every action slot holding
-- rank N-1 gets rank N. A lower rank kept on a bar on purpose (rank 1 to save mana)
-- is left alone, as are macros. Ranks come from the game's rank text ("Rank 3" in any
-- language, its last number), the same way the spellbook reads them. Out of combat
-- only (placing an action is protected), and never while something is on the
-- cursor. Controlled by the `rankUp` setting (on by default).

local _, ns = ...
local DUI = DaylightUI

local RU = {}
ns.RankUp = RU

RU.SLOTS = 180     -- every action slot the game has
RU.WAIT = 0.5      -- seconds; a trainer burst (Train All) is handled in rank order
RU.RETRY = 1       -- seconds; retry later while something is on the cursor

local queue = {}   -- learned spell ids waiting to be applied

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if ok then return a end
end

local function nameOf(id) return call(C_Spell and C_Spell.GetSpellName, id) end

-- The rank number from the game's rank text, or nil for a spell with no ranks.
function RU.RankOf(id)
    local t = call(C_Spell and C_Spell.GetSpellSubtext, id)
    if type(t) ~= "string" then return nil end
    return tonumber(string.match(t, "(%d+)%D*$"))
end

-- The slots holding the rank just below this one.
function RU.Slots(newID)
    local out = {}
    local name, r = nameOf(newID), RU.RankOf(newID)
    if type(name) ~= "string" or not r or r < 2 then return out end
    for slot = 1, RU.SLOTS do
        local kind, id = GetActionInfo(slot)
        if kind == "spell" and type(id) == "number" and id ~= newID and nameOf(id) == name
            and RU.RankOf(id) == r - 1 then
            out[#out + 1] = slot
        end
    end
    return out
end

function RU.On() return DUI:Get("ActionBars", "rankUp") ~= false end

-- Puts newID in each slot holding the rank below it. Returns how many changed.
function RU.Apply(newID)
    local n = 0
    for _, slot in ipairs(RU.Slots(newID)) do
        C_Spell.PickupSpell(newID)
        PlaceAction(slot)     -- the old rank comes onto the cursor...
        ClearCursor()         -- ...and goes
        n = n + 1
    end
    return n
end

function RU.Flush()
    if not RU.On() then wipe(queue); return end
    if InCombatLockdown() then return DUI.AfterCombat(RU.Flush, "ActionBars.rankUp") end
    if GetCursorInfo() then return C_Timer.After(RU.RETRY, RU.Flush) end
    local list = queue
    queue = {}
    table.sort(list, function(a, b) return (RU.RankOf(a) or 0) < (RU.RankOf(b) or 0) end)
    for _, id in ipairs(list) do RU.Apply(id) end
end

function RU.Learned(id)
    if type(id) ~= "number" or not RU.On() then return end
    queue[#queue + 1] = id
    if #queue == 1 then C_Timer.After(RU.WAIT, RU.Flush) end
end

DUI.RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE", function(_, id) RU.Learned(id) end)
