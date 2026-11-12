-- Preview: /dui buffs test shows a sample of every buff the addon knows about
-- on the bar, so the layout can be judged without a raid's worth of buffs.

local _, BL = ...

local Preview = {}
BL.Preview = Preview

local fraction = nil
local limit = nil            -- at most this many, spread across the share
local cache = nil

local PLACEHOLDER = "Interface\\Icons\\INV_Misc_QuestionMark"

local function iconFor(name)
    local id = BL.Data.Lookup(name)
    local cat = id and BL.Categories.Get(id)
    return (cat and cat.icon) or PLACEHOLDER
end

local function buildEntries()
    local names = BL.Data.Names()
    table.sort(names)
    local total = #names
    local want = math.floor(total * fraction + 0.5)
    if want > total then want = total end
    if limit and want > limit then want = limit end
    local entries = {}
    if want <= 0 then return entries end
    local step = total / want
    local now = BL.Clock()
    local pos = 1
    for i = 1, want do
        local name = names[math.floor(pos)]
        pos = pos + step
        -- Staggered, deterministic fake timers; every 7th one permanent.
        local timed = (i % 7) ~= 0
        entries[i] = {
            kind = "preview",
            index = i,
            auraInstanceID = -i,
            name = name,
            icon = iconFor(name),
            applications = (i % 5 == 0) and (i % 5 + 2) or 0,
            duration = timed and 1800 or 0,
            expirationTime = timed and (now + 30 + ((i * 97) % 1700)) or 0,
            sourceUnit = "player",
            timed = timed,
        }
    end
    return entries
end

-- value: the fraction of known buffs to show (nil stops). max: optional cap on
-- how many.
function Preview.Set(value, max)
    if value == nil then
        fraction, limit = nil, nil
        cache = nil
    else
        fraction = math.max(0, math.min(1, tonumber(value) or 0))
        limit = tonumber(max)
        cache = nil
    end
    BL.Fire("AURAS_CHANGED")
end

function Preview.Active()
    return fraction ~= nil
end

function Preview.Entries()
    if fraction == nil then return nil end
    if not cache then cache = buildEntries() end
    return cache
end
