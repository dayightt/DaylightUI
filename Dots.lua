-- Your DoTs for every module that shows them (target frame, nameplates): how
-- much damage the ones you've put on a mob will still deal.
--
-- The client gives addons neither the combat log (closed) nor a mob's auras
-- (secret), so this learns your DoTs the way the Does It Die addon does:
--   * your own casts stay readable (UNIT_SPELLCAST_SENT/SUCCEEDED for the
--     player are never secret), and a spell's description gives its damage,
--     school and duration;
--   * UNIT_COMBAT reports every hit on a unit token (target, focus, plates).
--     On Forever the amount is secret even though the docs don't say so,
--     while action, flag and school stay plain. A hit is matched to one of
--     your DoTs by school and rhythm alone (onBeat), and the damage left is
--     the description's share, or a size learned where amounts are plain.
--     Those hits (onWound) also match on size and learn the real ticks.
-- Everything here is a plain number. Health is never read: DotsDraw.lua hands
-- these numbers to the client's bars next to the unit's secret health, and
-- the bars do the comparing.

local _, DUI = ...

local Dots = {}
DUI.Dots = Dots

local VERSION = 1 -- bumping this drops learned tick sizes that older code got wrong
local DEFAULT_INTERVAL = 3
-- Seconds either side of an expected tick. On Forever the first tick lands
-- within about 0.1 s of one interval after the cast, later ones within about
-- 0.1 s of the first tick's rhythm. Tight windows keep melee swings out
-- (same Physical school as a bleed, similar size, about 1 s apart).
local TICK_WINDOW, TICK_WINDOW_ANCHORED = 0.45, 0.25
local MISSES_BEFORE_DROP = 3 -- a DoT that never ticks was resisted or immune
-- A projectile DoT starts when it lands. Serpent Sting's first tick came
-- 3.6-3.9 s after the cast instead of 3.
local PROJECTILE_TRAVEL = 1.5
-- Once a DoT's tick size is known, same-school hits further off belong to
-- something else (the Imp's Firebolt beside Immolate, white hits beside Rip).
local SIZE_TOLERANCE, FIRST_SIZE_TOLERANCE = 0.25, 0.3
-- A bleed's first tick before its size is known: a white hit on its rhythm
-- (often ten times a Rend tick) is refused past this many description shares.
local BLEED_CEILING = 4
local CRIT_MIN, CRIT_MAX = 1.3, 2.3
-- A cast's own outcome arrives almost at once: the first avoid or hit on the
-- mob right after it decides. It can also arrive just before the cast event.
local OUTCOME_WINDOW, OUTCOME_LOOKBACK = 0.4, 0.25
local SENT_SECONDS = 10
local SAME_SLOT = 0.2 -- two hits in one tick slot: the one closer in size was the tick
local COMBO_CAP = 5
local TICK_EVERY = 0.1

-- Description patterns, English only for now (kept in one table so other
-- languages can be added).
Dots.PATTERNS = {
    finisher = "Finishing move",
    perPoint = "(%d+) points?%s*:%s*(%d+) damage over (%d+%.?%d*) sec",
    weapon = "[Cc]oats a weapon", -- poisons: a proc, never cast on the mob
    heal = "^Heals",
    over = "(%d+)%s*([%a ]-)%s*damage over (%d+%.?%d*) sec",
    every = "(%d+)%s*([%a ]-)%s*damage every (%d+%.?%d*) sec",
    drain = "(%d+) health.-every (%d+%.?%d*) sec",
    lasts = "[Ll]asts (%d+%.?%d*) sec",
    awards = "Awards (%d+) combo point",
}

Dots.SCHOOLS = {
    Physical = 1, Holy = 2, Fire = 4, Nature = 8, Frost = 16, Shadow = 32, Arcane = 64,
    Frostfire = 4 + 16,       -- combined schools report as the OR of their masks
}
local PHYSICAL = 1

-- Tick intervals other than 3 s that descriptions don't state.
local INTERVALS = {
    ["Insect Swarm"] = 2, ["Curse of Agony"] = 2, ["Bane of Agony"] = 2, ["Fireball"] = 2,
    ["Holy Fire"] = 2, ["Rip"] = 2, ["Rupture"] = 2,
}
-- Uneven ticks: each tick is the average times its factor (factors average
-- to 1). Agony is back-loaded on Forever: 3,3,3,3, then 6..., then 9.
local AGONY = { 0.5, 0.5, 0.5, 0.5, 1, 1, 1, 1, 1.5, 1.5, 1.5, 1.5 }
local SHAPES = { ["Curse of Agony"] = AGONY, ["Bane of Agony"] = AGONY }
local SCHOOL_BY_NAME = { ["Siphon Life"] = 32 }
-- Read like DoTs but aren't one on the mob: areas, channels, traps and
-- delayed damage (Wyvern Sting starts after the sleep).
local SKIP = {
    ["Rain of Fire"] = true, ["Hellfire"] = true, ["Blizzard"] = true, ["Flamestrike"] = true,
    ["Consecration"] = true, ["Hurricane"] = true, ["Volley"] = true,
    ["Drain Life"] = true, ["Drain Soul"] = true, ["Drain Mana"] = true, ["Health Funnel"] = true,
    ["Mind Flay"] = true, ["Arcane Missiles"] = true, ["Starshards"] = true,
    ["Immolation Trap"] = true, ["Explosive Trap"] = true, ["Wyvern Sting"] = true,
}
local PROJECTILE = { ["Serpent Sting"] = true, ["Fireball"] = true, ["Pyroblast"] = true, ["Frostfire Bolt"] = true }

local AVOIDS = {
    MISS = true, DODGE = true, PARRY = true, EVADE = true, IMMUNE = true, DEFLECT = true, RESIST = true, REFLECT = true,
}
-- Spells can't be dodged or parried, so next to a spell DoT these were melee.
local MELEE_ONLY = { DODGE = true, PARRY = true, DEFLECT = true }

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function round(v) return math.floor(v + 0.5) end

-- Reading a description

local function schoolOf(words)
    local school = PHYSICAL
    for word in string.gmatch(words or "", "%a+") do
        if Dots.SCHOOLS[word] then school = Dots.SCHOOLS[word] end
    end
    return school
end

-- Finishers list their DoT per combo point; points past the list use the top one.
local function parseFinisher(desc, points)
    local byPoints, top = {}, 0
    for p, amount, secs in string.gmatch(desc, Dots.PATTERNS.perPoint) do
        p = tonumber(p)
        byPoints[p] = { total = tonumber(amount), duration = tonumber(secs) }
        if p > top then top = p end
    end
    if top == 0 then return nil end
    local e = byPoints[math.max(1, math.min(points, top))] or byPoints[top]
    return e.total, PHYSICAL, e.duration
end

-- Returns total, school, duration, interval (only when stated), or nil if not
-- a DoT. combo is the points a finisher was cast with (unknown = 1, erring low).
function Dots.Parse(desc, combo)
    if type(desc) ~= "string" or isSecret(desc) then return nil end
    local P = Dots.PATTERNS
    if string.find(desc, P.finisher) then return parseFinisher(desc, combo or 1) end
    if string.find(desc, P.weapon) or string.find(desc, P.heal) then return nil end
    -- The last "... damage over N sec", so Immolate's periodic part, not its hit.
    local total, school, duration
    for amount, words, secs in string.gmatch(desc, P.over) do
        total, school, duration = tonumber(amount), schoolOf(words), tonumber(secs)
    end
    if total and duration and duration > 0 then return total, school, duration end
    local amount, words, every = string.match(desc, P.every)
    if not amount then
        amount, every = string.match(desc, P.drain)
        words = ""
    end
    local lasts = string.match(desc, P.lasts)
    if amount and every and lasts then
        every, lasts = tonumber(every), tonumber(lasts)
        if every > 0 and lasts > 0 then
            return tonumber(amount) * round(lasts / every), schoolOf(words), lasts, every
        end
    end
    return nil
end

-- State

local byMob = {} -- mob key -> { [spell name] = dot }
local sent = {} -- cast GUID -> { key, at }, the mob a cast was aimed at
local counted = 0             -- combo points counted from builders
local comboAtSend             -- combo points read when a finisher was sent
local pendingBuilder -- { key, points, at }: a builder whose outcome isn't known yet
local pendingCast -- { key, name, dot, previous, at }: a DoT cast whose outcome isn't known yet
local lastOutcome             -- { key, avoided, action, school, at }
local lastHit, lastAmount, lastSchool, lastAt -- the last hit, since target and plate tokens both report it
local ticker
local events = CreateFrame("Frame")
local hearing = false -- UNIT_COMBAT is registered only while a cast or DoT needs the hits

-- Whether any hit on a mob can matter now: a DoT running, a cast sent, or one
-- whose outcome is pending. Otherwise hits (hundreds a second on every token
-- in a raid) aren't listened to at all.
local function needHits()
    return next(byMob) ~= nil or next(sent) ~= nil or pendingBuilder ~= nil or pendingCast ~= nil
end

local function hear(on)
    if on == hearing then return end
    hearing = on
    if on then events:RegisterEvent("UNIT_COMBAT") else events:UnregisterEvent("UNIT_COMBAT") end
end

-- The learned tick sizes, looked up on every hit. The table reference is
-- cached once the character's name is known, and refreshed when the saved
-- table is replaced (DB.Init after the game hands DaylightUIDB over).
local ticks, ticksIn
local function saved()
    local DB = DUI.DB
    if ticks and ticksIn == DB.sv and ticksIn == _G.DaylightUIDB then return ticks end
    local c = DB.Character()
    if type(c.dots) ~= "table" or c.dots.v ~= VERSION then c.dots = { v = VERSION, ticks = {} } end
    if type(c.dots.ticks) ~= "table" then c.dots.ticks = {} end
    -- Before the name is known DB.Character() is a scratch entry, so don't cache it.
    if DB.CharKey() then ticks, ticksIn = c.dots.ticks, DB.sv else ticks = nil end
    return c.dots.ticks
end

-- key: the one mob whose DoTs changed (a plate or frame on another mob has
-- nothing to redraw); nil means any number of them.
local function changed(key) DUI.Fire("DotsChanged", key) end

-- The mob behind a unit token: its GUID, or "target" when the target's GUID
-- is secret (a battleground), else nil (that token can't be told apart).
function Dots.KeyOf(unit)
    if type(unit) ~= "string" then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok then return nil end
    if isSecret(guid) then return unit == "target" and "target" or nil end
    if type(guid) == "string" then return guid end
    return nil
end

local function stopTicker()
    if ticker then ticker:Cancel() end
    ticker = nil
    hear(false)
end

function Dots.Forget()
    byMob, sent = {}, {}
    counted, comboAtSend = 0, nil
    pendingBuilder, pendingCast, lastOutcome, lastHit = nil, nil, nil, nil
    stopTicker()
    changed()
end

-- One DoT's sums

-- Best known average tick: the ones seen (crits excluded), else the learned
-- size, else the description's share.
local function expected(dot)
    if dot.normalTicks > 0 then return dot.tickSum / dot.normalTicks end
    return (dot.tickKey and saved()[dot.tickKey]) or (dot.total / dot.totalTicks)
end

local function tickNumberAt(dot, when)
    return math.max(1, round((when - dot.appliedAt) / dot.interval))
end

-- The factor for a given tick number (1 for even DoTs), with the shape
-- stretched to the DoT's tick count.
local function shapeOf(dot, number)
    local shape = dot.shape
    if not shape then return 1 end
    local i = math.ceil(math.min(math.max(number, 1), dot.totalTicks) / dot.totalTicks * #shape)
    return shape[math.max(1, math.min(i, #shape))]
end

-- A doubtful DoT (an avoid right after its cast that may have been someone
-- else's) only counts once it has ticked.
local function waiting(dot) return dot.ticksSeen == 0 and dot.doubtful == true end

local function remaining(dot)
    if dot.nextTickAt > dot.expiresAt + dot.interval / 2 then return 0 end
    local left = round((dot.expiresAt - dot.nextTickAt) / dot.interval) + 1
    if not dot.shape then return left * expected(dot) end
    local avg, total = expected(dot), 0
    for number = math.max(1, dot.totalTicks - left + 1), dot.totalTicks do
        total = total + avg * shapeOf(dot, number)
    end
    return total
end

-- What your DoTs on unit will still deal, as a plain whole number, or nil.
function Dots.Left(unit)
    local dots = byMob[Dots.KeyOf(unit)]
    if not dots then return nil end
    local total = 0
    for _, dot in pairs(dots) do
        if not waiting(dot) then total = total + remaining(dot) end
    end
    total = round(total)
    if total <= 0 then return nil end
    return total
end

-- Upkeep

-- Whether hits on the mob reach us right now. UNIT_COMBAT only covers unit
-- tokens, so a mob you tabbed away from ticks unseen and keeps its DoTs.
local function observable(key)
    if Dots.KeyOf("target") == key or Dots.KeyOf("focus") == key then return true end
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) and Dots.KeyOf(unit) == key then return true end
    end
    return false
end

-- How late a tick may run before its slot passes. The last one gets half an
-- interval: when seen it ends the DoT right away, so waiting costs nothing,
-- while giving up too soon would drop damage it was still going to deal.
local function lastSlot(dot) return dot.nextTickAt > dot.expiresAt - dot.interval / 2 end
local function lateness(dot) return lastSlot(dot) and dot.interval / 2 or TICK_WINDOW end

local function upkeep()
    local now, dropped = GetTime(), false
    for key, dots in pairs(byMob) do
        local slipped = false -- a tick's slot passed unseen, so its share comes off now
        for name, dot in pairs(dots) do
            local late = (dot.ticksSeen == 0 and dot.travel) or 0
            while dot.nextTickAt < now - lateness(dot) - late and dot.nextTickAt <= dot.expiresAt do
                dot.nextTickAt = dot.nextTickAt + dot.interval
                slipped = true
                if dot.ticksSeen == 0 and observable(key) then dot.missed = dot.missed + 1 end
            end
            if dot.nextTickAt > dot.expiresAt + dot.interval / 2
                or (dot.ticksSeen == 0 and dot.missed >= MISSES_BEFORE_DROP) then
                dots[name] = nil
                dropped = true
            end
        end
        if next(dots) == nil then byMob[key] = nil end
        if slipped then changed(key) end
    end
    -- Sends that never landed (an interrupt) and outcomes past their window.
    for guid, s in pairs(sent) do
        if now - s.at > SENT_SECONDS then sent[guid] = nil end
    end
    if pendingBuilder and now - pendingBuilder.at > OUTCOME_WINDOW then pendingBuilder = nil end
    if pendingCast and now - pendingCast.at > OUTCOME_WINDOW then pendingCast = nil end
    if not needHits() then stopTicker() end
    if dropped then changed() end
end

local function startTicker()
    hear(true)
    if not ticker then ticker = C_Timer.NewTicker(TICK_EVERY, upkeep) end
end

-- Casts

local function describe(id)
    local okName, name = pcall(C_Spell.GetSpellName, id)
    local okDesc, desc = pcall(C_Spell.GetSpellDescription, id)
    if not okName or isSecret(name) or type(name) ~= "string" then return nil end
    if not okDesc or isSecret(desc) or type(desc) ~= "string" then desc = "" end
    return name, desc
end

-- Whether a spell's cast can matter here, per spell id: a DoT, a finisher or
-- a builder. A heal, mount or direct hit has nothing to learn from later
-- hits, so its send doesn't turn on UNIT_COMBAT or the ticker. A description
-- that isn't loaded yet (empty) isn't cached and is checked again next cast.
local matters = {}
local function mattersFor(id)
    local known = matters[id]
    if known ~= nil then return known end
    local name, desc = describe(id)
    if not name or desc == "" then return false end
    local P = Dots.PATTERNS
    known = string.find(desc, P.awards) ~= nil
        or (not SKIP[name] and (string.find(desc, P.finisher) ~= nil or Dots.Parse(desc) ~= nil))
    matters[id] = known
    return known
end

local function readCombo()
    if type(GetComboPoints) ~= "function" then return nil end
    local ok, points = pcall(GetComboPoints, "player", "target")
    if ok and not isSecret(points) and type(points) == "number" and points > 0 then return points end
    return nil
end

-- The mob a cast was sent at: the unit the game names (mouseover and focus
-- macros), else the target.
local AIMS = { "target", "mouseover", "focus", "softenemy" }
local function aimedAt(name)
    if type(name) == "string" and not isSecret(name) and name ~= "" then
        for _, unit in ipairs(AIMS) do
            local ok, n = pcall(UnitName, unit)
            if ok and not isSecret(n) and n == name then return Dots.KeyOf(unit) end
        end
    end
    return Dots.KeyOf("target")
end

local function onSent(targetName, castGUID, id)
    if not mattersFor(id) then return end
    local now = GetTime()
    for guid, s in pairs(sent) do
        if now - s.at > SENT_SECONDS then sent[guid] = nil end
    end
    if type(castGUID) == "string" then
        sent[castGUID] = { key = aimedAt(targetName), at = now }
        startTicker() -- its outcome (a dodge, a resist, a first tick) comes after this, so listen for hits
    end
    local _, desc = describe(id)
    if desc and string.find(desc, Dots.PATTERNS.finisher) then comboAtSend = readCombo() end
end

-- A cast that failed or was interrupted never lands. Drop its send now
-- rather than after SENT_SECONDS of listening to every hit.
local function onStopped(castGUID)
    if type(castGUID) == "string" then sent[castGUID] = nil end
end

local function avoidJustBefore(key)
    local o = lastOutcome
    if o and o.avoided and o.key == key and GetTime() - o.at <= OUTCOME_LOOKBACK then return o end
end

-- An avoided DoT cast isn't on the mob: drop it, or restore the one it
-- replaced. A spell DoT is only taken back by an avoid that could be its own;
-- one that might not be (another school) makes it wait for a tick. Returns
-- false when the avoid was someone else's (its own may still come).
local function takeBack(cast, action, school)
    local dot = cast.dot
    local dots = byMob[cast.key]
    if not dots or dots[cast.name] ~= dot then return true end
    local own = not isSecret(school) and school == dot.school
    if dot.school ~= PHYSICAL and not own then
        if MELEE_ONLY[action] then return false end
        if not cast.previous then
            dot.doubtful = true
            changed(cast.key)
            return true
        end
    end
    dots[cast.name] = cast.previous
    changed(cast.key)
    return true
end

local function onCast(castGUID, id)
    local s = type(castGUID) == "string" and sent[castGUID]
    local key
    if s then
        sent[castGUID], key = nil, s.key
    else
        key = Dots.KeyOf("target")
    end
    local name, desc = describe(id)
    if not name then return end
    local awards = tonumber(string.match(desc, Dots.PATTERNS.awards) or "")
    if awards then
        if not avoidJustBefore(key) then
            counted = math.min(COMBO_CAP, counted + awards)
            pendingBuilder = { key = key, points = awards, at = GetTime() }
        end
    end
    if SKIP[name] then return end
    local finisher = string.find(desc, Dots.PATTERNS.finisher) ~= nil
    local points
    if finisher then
        points = comboAtSend or (counted > 0 and counted or nil)
        comboAtSend, counted, pendingBuilder = nil, 0, nil
    end
    local total, school, duration, stated = Dots.Parse(desc, points)
    if not total or not key then return end
    -- A finisher's tick size depends on its points, so it's learned per point
    -- count, and not at all when the count is unknown.
    local tickKey = id
    if finisher then tickKey = points and (id .. "x" .. points) or nil end

    local now = GetTime()
    local interval = stated or INTERVALS[name] or DEFAULT_INTERVAL
    byMob[key] = byMob[key] or {}
    local previous = byMob[key][name]
    local dot = {
        spellID = id, tickKey = tickKey,
        school = SCHOOL_BY_NAME[name] or school,
        total = total, duration = duration, interval = interval,
        totalTicks = math.max(1, round(duration / interval)),
        shape = SHAPES[name], travel = PROJECTILE[name] and PROJECTILE_TRAVEL or nil,
        appliedAt = now, expiresAt = now + duration, nextTickAt = now + interval,
        tickSum = 0, normalTicks = 0, ticksSeen = 0, missed = 0,
    }
    byMob[key][name] = dot
    pendingCast = { key = key, name = name, dot = dot, previous = previous, at = now }
    startTicker()
    local avoided = avoidJustBefore(key)
    if avoided and takeBack(pendingCast, avoided.action, avoided.school) then
        pendingCast = nil
    end
    changed(key)
end

-- Hits and avoids

-- One reused table each for the last avoid and hit, since a raid boss takes
-- hundreds of hits and misses a second.
local avoidOutcome = { avoided = true }
local function onAvoided(key, action, school)
    local now = GetTime()
    local o = avoidOutcome
    o.key, o.action, o.school, o.at = key, action, school, now
    lastOutcome = o
    if pendingBuilder and pendingBuilder.key == key then
        if now - pendingBuilder.at <= OUTCOME_WINDOW then
            counted = math.max(0, counted - pendingBuilder.points)
        end
        pendingBuilder = nil
    end
    if pendingCast and pendingCast.key == key then
        if now - pendingCast.at > OUTCOME_WINDOW or takeBack(pendingCast, action, school) then
            pendingCast = nil
        end
    end
end

-- A hit on the mob means the casts on it landed (a later avoid is someone
-- else's). A spell DoT's cast only counts by a hit in its own school.
local hitOutcome = { avoided = false }
local function onHit(key, school)
    hitOutcome.key, hitOutcome.at = key, GetTime()
    lastOutcome = hitOutcome
    if pendingBuilder and pendingBuilder.key == key then pendingBuilder = nil end
    local c = pendingCast
    if c and c.key == key and (c.dot.school == PHYSICAL or c.dot.school == school) then pendingCast = nil end
end

-- Seconds from now to the nearest expected tick, and its number. Counted
-- from the first tick once seen (so jitter doesn't add up), else from the cast.
local function distance(dot, now)
    local anchor = dot.firstTickAt or dot.appliedAt
    if not dot.firstTickAt and dot.travel then
        local late = now - (anchor + dot.interval)
        if late > 0 then anchor = anchor + math.min(late, dot.travel) end
    end
    local k = math.max(1, round((now - anchor) / dot.interval))
    return math.abs(now - (anchor + k * dot.interval)), k
end

local function plausible(dot, amount, crit, number)
    local known, tolerance
    if dot.normalTicks > 0 then
        known, tolerance = dot.tickSum / dot.normalTicks, SIZE_TOLERANCE
    else
        known, tolerance = dot.tickKey and saved()[dot.tickKey], FIRST_SIZE_TOLERANCE
    end
    if not known then
        if dot.school ~= PHYSICAL then return true end
        return amount <= (dot.total / dot.totalTicks) * shapeOf(dot, number) * BLEED_CEILING + 1
    end
    known = known * shapeOf(dot, number)
    if crit then return amount >= known * CRIT_MIN - 1 and amount <= known * CRIT_MAX + 1 end
    return math.abs(amount - known) <= math.max(1, known * tolerance)
end

-- Saved for the next cast only once two normal ticks agree, since a single
-- one may have been someone else's hit slipping through.
local function learn(dot)
    if dot.tickKey and dot.normalTicks > 1 then
        saved()[dot.tickKey] = math.floor(dot.tickSum / dot.normalTicks * 10 + 0.5) / 10
    end
end

-- Moves a DoT's bookkeeping to the tick in slot `index` that landed now.
local function anchor(dot, index, now)
    dot.missed = 0
    if dot.firstTickAt then
        dot.lastTickIndex = index
    else
        dot.firstTickAt, dot.lastTickIndex = now, 0
        if dot.travel then dot.appliedAt = now - index * dot.interval end
    end
    dot.lastTickAt = now
    dot.nextTickAt = now + dot.interval
    -- Ticks land a little after their nominal time, so the end follows them.
    local number = tickNumberAt(dot, now)
    dot.expiresAt = now + (dot.totalTicks - number) * dot.interval
end

-- Two same-school hits in one slot (a Shadow Bolt landing with a Corruption
-- tick): if this one is closer to the expected size, it was the tick.
local function swapSameSlot(dot, amount, crit, now)
    if crit or dot.lastTickCrit or not dot.lastTickAt or now - dot.lastTickAt > SAME_SLOT then return false end
    local factor = dot.lastTickShape
    local reference
    if dot.normalTicks > 1 then
        reference = (dot.tickSum - dot.lastTickAmount / factor) / (dot.normalTicks - 1)
    else
        reference = dot.total / dot.totalTicks
    end
    reference = reference * factor
    if math.abs(amount - reference) >= math.abs(dot.lastTickAmount - reference) then return false end
    dot.tickSum = dot.tickSum + (amount - dot.lastTickAmount) / factor
    dot.lastTickAmount = amount
    learn(dot)
    return true
end

-- A wrong learned size rejects every real tick. Two consecutive hits on the
-- DoT's rhythm that agree with each other and were rejected only on size are
-- the real ticks, so learn from them.
local function relearn(dot, amount, crit, index, dist, now)
    local window = dot.firstTickAt and TICK_WINDOW_ANCHORED or TICK_WINDOW
    local fresh = not dot.firstTickAt or index > dot.lastTickIndex
    if crit or not fresh or dist > window then return false end
    local prev = dot.offBeat
    local factor = shapeOf(dot, tickNumberAt(dot, now))
    local average = amount / factor
    dot.offBeat = { index = index, amount = amount, average = average, at = now }
    if not prev or index ~= prev.index + 1
        or math.abs(average - prev.average) > math.max(1, prev.average * SIZE_TOLERANCE) then
        return false
    end
    dot.offBeat = nil
    dot.tickSum, dot.normalTicks = prev.average + average, 2
    dot.ticksSeen = dot.ticksSeen + 2
    dot.lastTickAmount, dot.lastTickShape, dot.lastTickCrit = amount, factor, false
    learn(dot)
    if not dot.firstTickAt then
        dot.firstTickAt, dot.lastTickIndex = prev.at, 0
        index = 1
    end
    anchor(dot, index, now)
    return true
end

local function onWound(key, amount, school, crit)
    local dots = byMob[key]
    if not dots then return end
    local now = GetTime()
    if key == lastHit and amount == lastAmount and school == lastSchool and now == lastAt then return end
    lastHit, lastAmount, lastSchool, lastAt = key, amount, school, now

    local best, bestDist, bestIndex
    for _, dot in pairs(dots) do
        if dot.school == school and plausible(dot, amount, crit, tickNumberAt(dot, now)) then
            local dist, index = distance(dot, now)
            local window = dot.firstTickAt and TICK_WINDOW_ANCHORED or TICK_WINDOW
            if lastSlot(dot) then window = dot.interval / 2 end
            local fresh = not dot.firstTickAt or index > dot.lastTickIndex
            if fresh and dist <= window and (not bestDist or dist < bestDist) then
                best, bestDist, bestIndex = dot, dist, index
            end
        end
    end
    if not best then
        for _, dot in pairs(dots) do
            if dot.school == school then
                local dist, index = distance(dot, now)
                if swapSameSlot(dot, amount, crit, now) or relearn(dot, amount, crit, index, dist, now) then
                    changed(key)
                    return
                end
            end
        end
        return
    end
    local factor = shapeOf(best, tickNumberAt(best, now))
    best.ticksSeen = best.ticksSeen + 1
    best.lastTickAmount, best.lastTickShape, best.lastTickCrit = amount, factor, crit
    best.offBeat = nil
    if not crit then
        best.tickSum = best.tickSum + amount / factor
        best.normalTicks = best.normalTicks + 1
        learn(best)
    end
    anchor(best, bestIndex, now)
    changed(key)
end

-- A hit whose amount is secret: only school and timing can say it's a tick.
-- The rhythm stays the cast's (each slot takes one hit), so a swing landing
-- near a tick in its place changes nothing. A flag means a swing, since
-- bleeds aren't blocked.
local function onBeat(key, school, flag)
    local dots = byMob[key]
    if not dots then return end
    if school == PHYSICAL and not isSecret(flag) and flag ~= "" then return end
    local now = GetTime()
    local best, bestDist, bestIndex
    for _, dot in pairs(dots) do
        if dot.school == school then
            local dist, index = distance(dot, now)
            local fresh = not dot.lastTickIndex or index > dot.lastTickIndex
            if fresh and dist <= TICK_WINDOW and (not bestDist or dist < bestDist) then
                best, bestDist, bestIndex = dot, dist, index
            end
        end
    end
    if not best then return end
    if best.travel then -- was in flight until now, so its ticks and end count from here
        best.appliedAt = now - bestIndex * best.interval
        best.expiresAt = best.appliedAt + best.duration
        best.travel = nil
    end
    best.ticksSeen = best.ticksSeen + 1
    best.missed = 0
    best.lastTickIndex, best.lastTickAt = bestIndex, now
    best.nextTickAt = (best.firstTickAt or best.appliedAt) + (bestIndex + 1) * best.interval
    changed(key)
end

-- Your group's tokens never point at a mob with your DoTs.
local function groupToken(unit)
    return unit == "player" or unit == "pet" or string.find(unit, "^raid") ~= nil or string.find(unit, "^party") ~= nil
end

local function onCombat(unit, action, flag, amount, school)
    if not needHits() then return end
    if isSecret(unit) or type(unit) ~= "string" or groupToken(unit) then return end
    if isSecret(action) or type(action) ~= "string" then return end
    if not AVOIDS[action] and action ~= "WOUND" then return end
    local key = Dots.KeyOf(unit)
    if not key then return end
    if isSecret(school) or type(school) ~= "number" then school = nil end
    if AVOIDS[action] then return onAvoided(key, action, school) end
    onHit(key, school)
    if not school then return end
    if isSecret(amount) or type(amount) ~= "number" then return onBeat(key, school, flag) end
    onWound(key, amount, school, not isSecret(flag) and flag == "CRITICAL")
end

-- Who wants it

events:SetScript("OnEvent", function(_, event, unit, a, b, c, d)
    if event == "UNIT_COMBAT" then
        onCombat(unit, a, b, c, d)
    elseif event == "PLAYER_TARGET_CHANGED" then
        counted, pendingBuilder = 0, nil
        -- DoTs stored under "target" (a secret GUID, an enemy player in a
        -- battleground) belong to the target you just left.
        if byMob.target then
            byMob.target = nil
            if pendingCast and pendingCast.key == "target" then pendingCast = nil end
            changed()
        end
    elseif isSecret(unit) or unit ~= "player" then
        return
    elseif event == "UNIT_SPELLCAST_SENT" then
        -- (unit, target name, cast GUID, spell id)
        if not isSecret(b) and not isSecret(c) and type(c) == "number" then onSent(a, b, c) end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- (unit, cast GUID, spell id)
        if not isSecret(a) and not isSecret(b) and type(b) == "number" then onCast(a, b) end
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        -- (unit, cast GUID, spell id)
        if not isSecret(a) then onStopped(a) end
    end
end)

local wanted = {}
local listening = false

-- who ("unitframes", "nameplates") starts or stops showing DoTs. The tracker
-- only listens while someone shows them.
function Dots.Want(who, on)
    wanted[who] = on and true or nil
    local any = next(wanted) ~= nil
    if any == listening then return end
    listening = any
    if any then
        events:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
        events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        events:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
        events:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
        events:RegisterEvent("PLAYER_TARGET_CHANGED")
    else
        events:UnregisterEvent("UNIT_SPELLCAST_SENT")
        events:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        events:UnregisterEvent("UNIT_SPELLCAST_FAILED")
        events:UnregisterEvent("UNIT_SPELLCAST_INTERRUPTED")
        events:UnregisterEvent("PLAYER_TARGET_CHANGED")
        Dots.Forget()
    end
end
