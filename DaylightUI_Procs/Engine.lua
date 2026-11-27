-- Watches the player's procs and shows or hides their flares.
--
-- The game hides buffs from addons in a fight, so a proc is seen through the
-- spell it boosts: the game says it can be used now (usable), it casts
-- faster or instantly (faster, instant), it costs nothing (free), its
-- cooldown ended early (reset), or the game shows its own proc alert
-- (overlay). Every read is checked for a secret first and a secret answer
-- keeps the last one. Events ask for a check on the next frame; in a fight,
-- or while a flare is up, a light poll every 0.2 s catches what changes a
-- moment after the events. Nothing runs between fights with nothing up.

local _, ns = ...
local DUI = DaylightUI
local isSecret = DUI.IsSecret

local Engine = { state = {} }
ns.Engine = Engine
local state = Engine.state

Engine.POLL = 0.2
Engine.GRACE = 0.3        -- a "no" shorter than this is ignored
Engine.RESPENT = 2        -- after its time ran out, a window still open this long is a new one

local inCombat = false
local ticker, started, learned, fresh = nil, false, false, false
local CHECKS, SOURCES = {}, {}
Engine.CHECKS, Engine.SOURCES = CHECKS, SOURCES
local castRoles = {}      -- spell id -> list of { p, role }

-- A plain number, or nil (secret, missing).
local function num(v)
    if isSecret(v) then return nil end
    if type(v) == "number" then return v end
end
Engine.Num = num

local function knows(id)
    if type(IsPlayerSpell) == "function" then
        local v = IsPlayerSpell(id)
        if not isSecret(v) and v == true then return true end
    end
    local book = C_SpellBook
    if type(book) == "table" and type(book.IsSpellKnown) == "function" then
        local v = book.IsSpellKnown(id)
        if not isSecret(v) and v == true then return true end
    end
    return false
end

-- The highest rank of a list the player knows.
function Engine.Known(list)
    if type(list) ~= "table" then return nil end
    for i = #list, 1, -1 do
        if knows(list[i]) then return list[i] end
    end
end

-- Reads -------------------------------------------------------------------

-- Each spell is read once per check, however many procs look at it.
local readAt, ctCache, costCache = 0, {}, {}

function Engine.CastTime(id)
    if not id then return nil end
    local c = ctCache[id]
    if c and c[1] == readAt then return c[2] end
    local v
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local info = C_Spell.GetSpellInfo(id)
        if type(info) == "table" and not isSecret(info) then v = num(info.castTime) end
    end
    ctCache[id] = { readAt, v }
    return v
end

-- The cost that applies now out of the client's list: the first one not tied
-- to an aura the player lacks (the list also holds costs for forms and buffs
-- that aren't there). false for an empty list (no cost at all), nil when
-- none applies (a cat's Claw out of Cat Form) or it can't be read.
local function applies(t)
    if t[1] == nil then return false end
    for _, e in ipairs(t) do
        if type(e) ~= "table" then return nil end
        local aura, has = e.requiredAuraID, e.hasRequiredAura
        if isSecret(aura) or isSecret(has) then return nil end
        if not (type(aura) == "number" and aura ~= 0 and has ~= true) then return e end
    end
    return nil
end

-- A spell's cost in the first resource that applies (0 = free), or nil when
-- the game can't say.
function Engine.Cost(id)
    if not id then return nil end
    local c = costCache[id]
    if c and c[1] == readAt then return c[2] end
    local v
    if C_Spell and type(C_Spell.GetSpellPowerCost) == "function" then
        local t = C_Spell.GetSpellPowerCost(id)
        if t ~= nil and not isSecret(t) and type(t) == "table" then
            local e = applies(t)
            if e == false then v = 0 elseif e then v = num(e.cost) end
        end
    end
    costCache[id] = { readAt, v }
    return v
end

-- true or false, or nil when the answer is secret.
function Engine.Usable(id, short)
    if not (C_Spell and type(C_Spell.IsSpellUsable) == "function") then return nil end
    local u, lack = C_Spell.IsSpellUsable(id)
    if isSecret(u) or isSecret(lack) then return nil end
    return u == true or (short and lack == true) or false
end

local function stealthed()
    if type(IsStealthed) ~= "function" then return false end
    local v = IsStealthed()
    return not isSecret(v) and v == true
end

-- Usable ------------------------------------------------------------------

-- Shown while the game says the spell can be used. For a short window
-- (Overpower, Revenge) "usable with more rage" counts too, so the flare
-- never flickers with the rage bar; for a state (Execute) it doesn't.
CHECKS.usable = function(p, g, now)
    local short = p.noPower ~= false
    local on, read = false, false
    for _, id in ipairs({ g.id or false, g.alsoId or false }) do
        if id then
            local v = Engine.Usable(id, short)
            if v ~= nil then
                read = true
                if v then on = true end
            end
        end
    end
    if not read then return end       -- secret or unknown: keep the last answer
    if on and p.combatOnly and not inCombat then on = false end
    if on and p.notStealthed and stealthed() then on = false end
    -- When the window opened: the game says yes from the dodge on, even while
    -- the flare waits for the cooldown. A cast that opens it (Ghostly Strike) counts from itself.
    if on and not g.seenOn and not (g.seenOffAt and now - g.seenOffAt < Engine.GRACE) then
        local at = g.openCastAt
        g.openAt = (at and now - at < p.dur) and at or now
    end
    if g.seenOn and not on then g.seenOffAt = now end
    g.seenOn = on
    if g.wait and ((not on and not p.holdCd) or now - g.castAt >= (p.cd or 1)) then
        g.wait, g.raw, g.offAt = false, on, nil
        return
    end
    -- No grace for one that follows the target, nor after a fight.
    if g.raw and not on then g.offAt = (not p.onTarget and (inCombat or not p.combatOnly)) and now or nil end
    g.raw = on
end
SOURCES.usable = function(p, g, now)
    if g.wait then return false end
    if g.raw then return true end
    return g.offAt ~= nil and now - g.offAt < Engine.GRACE
end

-- Instant -----------------------------------------------------------------

-- The cast time is 0, and a real one was seen before (a spell instant from
-- the start is just instant).
CHECKS.instant = function(p, g)
    local ct = Engine.CastTime(g.id)
    g.ct = ct
    if ct == nil then return end
    if ct > 0 then
        g.base, g.on = ct, false
        if not g.maxCt or ct > g.maxCt then g.maxCt = ct end
    else
        g.on = g.base ~= nil
    end
end
SOURCES.instant = function(p, g) return g.on == true or (p.stacks ~= nil and (g.n or 0) > 0) end

-- Shadow Trance: Shadow Bolt going instant, or the game's own alert for it.
CHECKS.trance = CHECKS.instant
SOURCES.trance = function(p, g) return g.on == true or g.overlay == true end

-- Faster ------------------------------------------------------------------

-- Casts faster than usual, against a reference spell the proc doesn't touch,
-- so haste (which speeds both) never counts. The usual ratio is the highest
-- seen, learned again when talents change. selfCheck: also faster than its
-- own slowest cast seen.
CHECKS.faster = function(p, g)
    g.q, g.cut = nil, nil
    local ct = Engine.CastTime(g.id)
    if not (ct and ct > 0) then
        if ct == 0 then g.on = false end
        return
    end
    if p.selfCheck and (not g.maxCt or ct > g.maxCt) then g.maxCt = ct end
    local refId, ref
    for _, rid in ipairs(g.refIds or {}) do
        local c = Engine.CastTime(rid)
        if c and c > 0 then refId, ref = rid, c; break end
    end
    local threshold = p.threshold or 0.9
    if not ref then
        if p.selfCheck and g.maxCt then g.on = ct < g.maxCt * threshold end
        return
    end
    local r = ct / ref
    local base = g.ratio[refId]
    -- Learned only while the spell is at its own usual speed.
    local learn = not (p.selfCheck and g.maxCt and ct < g.maxCt * 0.95)
    if not base or (r > base and learn) then base = r; g.ratio[refId] = r end
    local on = r < base * threshold
    if not (p.selfCheck and g.maxCt and ct >= g.maxCt * 0.95) then
        g.q = r / base
        if g.maxCt then g.cut = (1 - r / base) * g.maxCt / 1000 end
    end
    if on and p.selfCheck then on = ct < g.maxCt * 0.95 end
    -- Charges (Eclipse): only the full cut counts, the largest seen standing for full.
    if on and p.fullCut and g.maxCt then
        local cut = (1 - r / base) * g.maxCt / 1000
        g.maxCut = math.max(g.maxCut or 0, cut)
        on = cut >= math.max(0.25, math.min(p.fullCut, g.maxCut * 0.9))
    end
    g.on = on
end
SOURCES.faster = SOURCES.instant

-- Free --------------------------------------------------------------------

-- At most `free` times its usual cost; the usual cost is the highest seen.
local function cheap(g, id, free)
    local c = Engine.Cost(id)
    if c == nil then return nil end
    local b = g.costBase[id]
    if not b or c > b then b = c; g.costBase[id] = c end
    return b > 0 and c <= b * free
end

CHECKS.free = function(p, g, now)
    local seen, on = false, false
    for _, id in ipairs(g.watch or {}) do
        local skip = p.skipInstant and Engine.CastTime(id) == 0
        if not skip then
            local v = cheap(g, id, 0)
            if v ~= nil then
                seen = true
                if v then on = true end
            end
        end
    end
    if not seen then
        -- Can't be read any more: it ends at the latest after its usual length.
        if g.on and g.seenAt and now - g.seenAt > p.dur then g.on = false end
        return
    end
    g.seenAt = now
    -- Missile Barrage: Clearcasting frees every spell, so while it's up the cost
    -- can't tell. One already seen stays until its spell is cast (a "spend"
    -- cast clears g.on) or its usual length is over; a new one isn't claimed.
    local other = p.unless and state[p.unless]
    if on and other and other.on then
        on = g.on == true and g.freeAt ~= nil and now - g.freeAt < p.dur
    end
    if on and not g.on then g.freeAt = now end
    -- Searing Light: not when another spell is free too (Inner Focus frees any spell).
    for _, id in ipairs(g.others or {}) do
        if cheap(g, id, 0) then on = false end
    end
    g.on = on
end
SOURCES.free = function(p, g) return g.on == true end

-- Overlay -----------------------------------------------------------------

-- On while the game shows its own proc alert for the spell. A missed end
-- still ends it a little after its usual length.
CHECKS.overlay = function(p, g, now)
    if g.overlay and g.overlayAt and now - g.overlayAt > p.dur + 2 then g.overlay = false end
end
SOURCES.overlay = function(p, g) return g.overlay == true end

local overlayOf = {}      -- spell id in the game's alert -> proc
for _, p in ipairs(ns.Data.PROCS) do
    for _, id in ipairs(p.overlayIds or {}) do overlayOf[id] = p end
end

local function onOverlay(event, spellID)
    if not started then return end
    local now = GetTime()
    if event == "SPELL_ACTIVATION_OVERLAY_HIDE" and spellID == nil then
        for _, g in pairs(state) do g.overlay = false end
        return Engine.Soon()
    end
    local id = num(spellID)
    local p = id and overlayOf[id]
    local g = p and state[p.key]
    if not g then return end
    if p.mode == "aura" then
        -- The client draws this one from its buff; the alert only says when it
        -- lands, so it plays the sound once per alert.
        local on = event == "SPELL_ACTIVATION_OVERLAY_SHOW"
        if on and not g.overlay and not g.silent
            and not (ns.Alerts.Get(p.key, "combatOnly") ~= false and not inCombat) then
            ns.Flares.PlaySound(p.key)
        end
        g.overlay, g.overlayAt = on, now
        return
    end
    g.overlay = event == "SPELL_ACTIVATION_OVERLAY_SHOW"
    g.overlayAt = now
    Engine.Soon()
end

-- Reset -------------------------------------------------------------------

-- Whether a spell's cooldown runs now. isActive is never secret, the rest is.
local function cooldown(id)
    if not (C_Spell and type(C_Spell.GetSpellCooldown) == "function") then return nil end
    local info = C_Spell.GetSpellCooldown(id)
    if type(info) ~= "table" or isSecret(info.isActive) or info.isActive == nil then return nil end
    return info.isActive == true, not isSecret(info.isOnGCD) and info.isOnGCD == true
end

-- After a cast, a cooldown ending well before its usual length was reset.
-- The first second is skipped (the cooldown is being set up), and so is the
-- last moment of the usual one.
Engine.RESET_FROM = 1
CHECKS.reset = function(p, g, now)
    if g.on then
        if not inCombat or now - (g.onAt or now) > p.dur then g.on = false end
        return
    end
    local at = g.resetCastAt
    if not (g.id and at) then return end
    if not inCombat then g.resetCastAt = nil; return end
    local since = now - at
    if since >= p.cd - 0.6 then g.resetCastAt = nil; return end
    if since < Engine.RESET_FROM then return end
    if cooldown(g.id) == false then g.on, g.onAt, g.resetCastAt = true, now, nil end
end
SOURCES.reset = function(p, g) return g.on == true end

-- Told right after SPELL_UPDATE_COOLDOWN (the only moment isOnGCD is
-- trusted): only the global cooldown left means its own one is over.
local function onCooldowns()
    if not started or not inCombat then return end
    local now = GetTime()
    for _, p in ipairs(ns.Data.Mine()) do
        local g = state[p.key]
        if p.mode == "reset" and g and not g.on and g.id and g.resetCastAt then
            local since = now - g.resetCastAt
            local active, gcd = cooldown(g.id)
            if since >= Engine.RESET_FROM and since < p.cd - 0.6 and active and gcd then
                g.on, g.onAt, g.resetCastAt = true, now, nil
            end
        end
    end
    Engine.Soon()
end

-- Casts -------------------------------------------------------------------

-- Stacks counted from the casts themselves (Arcane Blast): one a cast, up to
-- its most, gone its length after the first.
CHECKS.casts = function(p, g, now)
    if g.winStart and now - g.winStart >= p.dur then g.cn, g.winStart = 0, nil end
    g.on = (g.cn or 0) >= p.stacks
    g.from = g.winStart
end
SOURCES.casts = function(p, g) return (g.cn or 0) > 0 end

-- Stacks ------------------------------------------------------------------

-- How many stacks a stacking proc has now, from what the game still shows:
-- how much faster (Heating Up), the seconds cut (Eclipse), or the cost cut
-- (Maelstrom Weapon, 20% a stack; its cast time when the cost reads 0).
function Engine.Stacks(p, g)
    if g.on then return p.stacks end
    if p.mode == "casts" then return g.cn or 0 end
    if p.stackAt then
        if not g.q then return 0 end
        for i = #p.stackAt, 1, -1 do
            if g.q < p.stackAt[i] then return i end
        end
        return 0
    end
    local cut, per
    if p.perCharge then
        if not (g.cut and g.q and g.q < 0.95) then return 0 end
        cut, per = g.cut, p.perCharge
    elseif p.perStack then
        local c, b = Engine.Cost(g.id), g.id and g.costBase[g.id]
        if c and (not b or c > b) then b = c; g.costBase[g.id] = c end
        if c and b and b > 0 and c > 0 then cut = 1 - c / b end
        if not cut and g.ct and g.ct > 0 and g.maxCt and g.maxCt > 0 then cut = 1 - g.ct / g.maxCt end
        per = p.perStack
    end
    if not cut then return 0 end
    local n = math.floor(cut / per + 0.5)
    return math.max(0, math.min(p.stacks - 1, n))
end

-- Watching ----------------------------------------------------------------

local function enabled() return DUI:Get("Procs", "enabled") ~= false end

local function mapCast(id, p, role)
    local l = castRoles[id]
    if not l then l = {}; castRoles[id] = l end
    l[#l + 1] = { p = p, role = role }
end

-- Which procs this character watches and which ranks it knows. Again when
-- spells or talents change, or an alert is turned on or off.
local function knownEach(lists)
    local out = {}
    for _, list in ipairs(lists or {}) do
        local id = Engine.Known(list)
        if id then out[#out + 1] = id end
    end
    return out
end

-- fresh = talents changed: the usual speeds and costs are learned again.
function Engine.Learn(fresh)
    learned = true
    for k in pairs(castRoles) do castRoles[k] = nil end
    -- A proc another one is told apart from (Clearcasting for Missile Barrage)
    -- is still watched with its own alert off, only never shown: otherwise every
    -- Clearcasting would light Missile Barrage.
    local keep, behind = {}, {}
    for _, p in ipairs(ns.Data.Mine()) do
        if p.unless and ns.Alerts.Get(p.key, "enabled") ~= false then behind[p.unless] = true end
    end
    for _, p in ipairs(ns.Data.Mine()) do
        local on = ns.Alerts.Get(p.key, "enabled") ~= false
        if on or behind[p.key] then
            keep[p.key] = true
            local g = state[p.key]
            if not g then g = { ratio = {}, costBase = {} }; state[p.key] = g end
            g.silent = not on
            if fresh then g.ratio, g.costBase, g.maxCt, g.maxCut, g.base = {}, {}, nil, nil, nil end
            g.id = Engine.Known(p.cast)
            g.alsoId = Engine.Known(p.also)
            g.refIds = knownEach(p.refs)
            g.watch = knownEach(p.watch)
            g.others = knownEach(p.others)
            if p.mode == "usable" and p.hideOnCast ~= false then
                for _, id in ipairs(p.cast or {}) do mapCast(id, p, "used") end
                for _, id in ipairs(p.also or {}) do mapCast(id, p, "used") end
            end
            for _, id in ipairs(p.openCast or {}) do mapCast(id, p, "open") end
            -- A free proc that can hide behind another (Missile Barrage under
            -- Clearcasting) is spent by a cast of its own spell.
            if p.mode == "free" and p.unless then
                for _, list in ipairs(p.watch or {}) do
                    for _, id in ipairs(list) do mapCast(id, p, "spend") end
                end
            end
            if p.mode == "reset" then
                for _, id in ipairs(p.cast) do mapCast(id, p, "reset") end
            elseif p.mode == "casts" then
                for _, id in ipairs(p.cast) do mapCast(id, p, "stack") end
            end
        end
    end
    for key in pairs(state) do
        if not keep[key] then
            local f = ns.Flares.live[key]
            if state[key].flared and f and not f.test then ns.Flares.Hide(key) end
            state[key] = nil
        end
    end
end

function Engine.Watched(key) return state[key] ~= nil and not state[key].silent end
function Engine.Polling() return ticker ~= nil end
function Engine.InCombat() return inCombat end

-- The game's own alert ------------------------------------------------------

-- The game draws its own art for a few procs (Shadow Trance), which would
-- double the flare. While one with a signal of its own is watched, the
-- game's setting is turned off; the player's value comes back when it isn't
-- (and at logout, so a module turned off in the AddOns list leaves it right).
-- The game's alert code checks the setting in its own handler, so the event
-- still comes. A mage's setting is left alone: Fingers of Frost's sound comes
-- from the alert event.
local ALERT_CVAR = "displaySpellActivationOverlays"

local function wantGameOff()
    if not enabled() then return false end
    for _, p in ipairs(ns.Data.Mine()) do
        if p.gameAlertOff and Engine.Watched(p.key) then return true end
    end
    return false
end

function Engine.GameAlert(watching)
    if type(GetCVar) ~= "function" or type(SetCVar) ~= "function" then return end
    local root = DUI.DB.Root()
    local off = watching and wantGameOff()
    local now = GetCVar(ALERT_CVAR)
    if isSecret(now) then return end
    if off then
        if now == "0" then return end
        root.procsGameAlert = now
        DUI.AfterCombat(function() DUI.SafeCall(SetCVar, ALERT_CVAR, "0") end, "procs:gamealert")
    elseif root.procsGameAlert ~= nil then
        local was = root.procsGameAlert
        root.procsGameAlert = nil
        DUI.AfterCombat(function() DUI.SafeCall(SetCVar, ALERT_CVAR, was) end, "procs:gamealert")
    end
end

-- Checking ----------------------------------------------------------------

local function poll(need)
    if need and not ticker then
        ticker = C_Timer.NewTicker(Engine.POLL, function() Engine.Refresh() end)
    elseif not need and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

-- Whether a proc counts as up now: its check, then the rules every proc shares.
local function decide(p, g, now)
    local check = CHECKS[p.mode]
    if check then check(p, g, now) end
    if p.stacks then g.n = Engine.Stacks(p, g) end
    local src = SOURCES[p.mode]
    local active = src ~= nil and src(p, g, now) == true
    -- A usable window ends when its time runs out, even if the game says yes a
    -- moment longer; still yes a while later, a new dodge or kill opened it again.
    if p.mode == "usable" and not p.noTimer then
        if active and g.active and g.startedAt and now >= g.startedAt + p.dur then
            g.spent, g.spentAt = true, now
        end
        if g.spent then
            if not active or now - g.spentAt >= Engine.RESPENT then g.spent = nil else active = false end
        end
    end
    if active and not g.active then
        g.startedAt = now
        if p.mode == "usable" and g.openAt and g.openAt < now and now - g.openAt < p.dur then g.startedAt = g.openAt end
        if g.from then g.startedAt = g.from end
    end
    g.active = active
    return active
end

function Engine.Refresh()
    if not started then return end
    if not enabled() then
        ns.Flares.HideAll(true)
        poll(false)
        Engine.GameAlert(false)
        return
    end
    if not learned then
        Engine.Learn(fresh)
        fresh = false
        Engine.GameAlert(true)
    end
    local now = GetTime()
    readAt = readAt + 1
    local any = false
    if Engine.BeforeChecks then Engine.BeforeChecks(now) end
    for _, p in ipairs(ns.Data.Mine()) do
        local g = state[p.key]
        if g and p.mode ~= "aura" then
            local active = decide(p, g, now)
            local show = active and not g.silent and not (ns.Alerts.Get(p.key, "combatOnly") and not inCombat)
            if show then
                local info = { stacks = g.n }
                if not p.noTimer and g.startedAt then
                    local dur = g.dur or p.dur
                    info.left, info.dur, info.at = g.startedAt + dur - now, dur, g.startedAt
                end
                ns.Flares.Show(p.key, info)
                g.flared = true
            elseif g.flared then
                -- Only a flare the engine showed: test flares and samples stay.
                g.flared = nil
                local f = ns.Flares.live[p.key]
                if f and not f.test then ns.Flares.Hide(p.key) end
            end
            if (active and not g.silent) or g.wait then any = true end
        end
    end
    poll(inCombat or any)
end

local soon = DUI.Soon(function() Engine.Refresh() end)
Engine.Soon = soon

-- The player's own cast: a usable proc's spell hides it (for its cooldown
-- with holdCd); other modes add their own roles.
local function onCast(_, unit, _, spellID)
    if not started or isSecret(unit) or unit ~= "player" then return end
    local id = num(spellID)
    local roles = id and castRoles[id]
    if not roles then return end
    local now = GetTime()
    for _, r in ipairs(roles) do
        local g = state[r.p.key]
        if g then
            if r.role == "used" then
                g.wait, g.castAt = true, now
            elseif r.role == "open" then
                g.openCastAt = now
            elseif r.role == "spend" then
                g.on, g.freeAt = false, nil
            elseif r.role == "reset" then
                g.on, g.resetCastAt = false, now
            elseif r.role == "stack" then
                if not g.winStart then g.winStart, g.cn = now, 0 end
                g.cn = math.min(r.p.stacks, (g.cn or 0) + 1)
            end
        end
    end
    soon()
end

function Engine.Start(mod)
    if started then return end
    started = true
    inCombat = InCombatLockdown() == true
    DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function() inCombat = true; soon() end)
    DUI.RegisterEvent("PLAYER_REGEN_ENABLED", function() inCombat = false; soon() end)
    for _, e in ipairs({ "SPELL_UPDATE_USABLE", "PLAYER_TARGET_CHANGED",
                         "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD" }) do
        DUI.RegisterEvent(e, soon)
    end
    -- A new rank only changes which spell is read. The usual speeds and costs
    -- are learned again on a talent change alone: the spells-changed event can
    -- come with the proc itself (a buff that changes a cast time), and forgetting
    -- them then would learn the boosted speed as the usual one.
    DUI.RegisterEvent("SPELLS_CHANGED", function() learned = false; soon() end)
    for _, e in ipairs({ "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED" }) do
        DUI.RegisterEvent(e, function() learned, fresh = false, true; soon() end)
    end
    -- The proc's buff landing out of a fight, when nothing polls.
    DUI.RegisterUnitEvent("UNIT_AURA", soon, "player")
    DUI.RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", onCast, "player")
    DUI.RegisterEvent("SPELL_ACTIVATION_OVERLAY_SHOW", onOverlay)
    DUI.RegisterEvent("SPELL_ACTIVATION_OVERLAY_HIDE", onOverlay)
    DUI.RegisterEvent("SPELL_UPDATE_COOLDOWN", onCooldowns)
    DUI.RegisterEvent("PLAYER_LOGOUT", function() Engine.GameAlert(false) end)
    Engine.Learn()
    Engine.GameAlert(true)
    soon()
end

-- A Proc Alerts setting changed: act at once, in a fight too (only frames of
-- Daylight UI's own are touched).
DUI.On("SettingChanged", function(scope)
    if scope ~= "Procs" or not started then return end
    learned = false
    if not enabled() then ns.Flares.HideAll(true) end
    ns.Flares.Repaint()
    Engine.Refresh()
end)
