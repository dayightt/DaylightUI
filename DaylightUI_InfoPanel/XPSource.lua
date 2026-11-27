-- What each XP gain was (a kill, a quest, a discovery, anything else) and
-- where on screen it came from, for the XP orbs.
--
-- Several events describe one gain: the XP update itself, the chat line that
-- names the mob and the amount, the death (UNIT_DIED), a quest turned in. They
-- arrive in either order, so each gain waits a moment for the others and every
-- line pays for one gain only.
--
-- No nameplate can be measured (the client refuses), so a mob's spot is where
-- the cursor was while it hovered the mob, fading to a default spot as that
-- sample gets old.

local _, ns = ...
local DUI = DaylightUI
local secret = DUI.IsSecret

local XPSource = {}
ns.XPSource = XPSource

XPSource.DEATH_KEEP = 1.5   -- s a death waits to be paired with its XP
XPSource.LINE_WAIT = 0.5    -- s a chat line waits for the XP it explains
XPSource.DELTA_WAIT = 0.4   -- s an XP gain waits for the line that explains it
XPSource.HINT_KEEP = 1.0    -- s a quest or discovery waits for its XP
XPSource.SAMPLE_FULL = 1    -- s a cursor sample counts in full
XPSource.SAMPLE_GONE = 3    -- s when it no longer counts at all
XPSource.SAMPLE_KEEP = 5    -- s before an unused sample is dropped
XPSource.SAMPLE_MAX = 20
XPSource.POLL = 0.1         -- s between samples while a hostile mob stays under the cursor
XPSource.QUEST_KEEP = 120   -- s the NPC window's XP spot stays usable after it closes

-- Where a gain starts when nothing better is known, as shares of the screen.
XPSource.SPOTS = { kill = { 0.5, 0.58 }, quest = { 0.30, 0.60 }, explore = { 0.5, 0.75 }, other = { 0.5, 0.65 } }

local samples, deaths, lines, hints, pending = {}, {}, {}, {}, {}
XPSource.samples, XPSource.deaths, XPSource.lines, XPSource.hints, XPSource.pending = samples, deaths, lines, hints, pending

local function now() return GetTime() end

local function plain(v) return v ~= nil and not secret(v) end

-- A format string from the client turned into an anchored pattern. order[i] is
-- which argument the i-th capture holds (positional "%2$s" included).
function XPSource.Pattern(fmt)
    local out, order, arg = { "^" }, {}, 0
    local i = 1
    while i <= #fmt do
        local c = fmt:sub(i, i)
        if c == "%" then
            local pos, kind, len = fmt:match("^%%(%d+)%$([sd])()", i)
            if pos then
                order[#order + 1] = tonumber(pos)
                out[#out + 1] = kind == "d" and "(%d+)" or "(.-)"
                i = len
            else
                local k = fmt:sub(i + 1, i + 1)
                if k == "s" or k == "d" then
                    arg = arg + 1
                    order[#order + 1] = arg
                    out[#out + 1] = k == "d" and "(%d+)" or "(.-)"
                else
                    out[#out + 1] = "%%"
                end
                i = i + 2
            end
        else
            out[#out + 1] = c:find("[%^%$%(%)%.%[%]%*%+%-%?]") and "%" .. c or c
            i = i + 1
        end
    end
    out[#out + 1] = "$"
    return table.concat(out), order
end

-- The XP chat lines this client prints, longest first so a line with a group
-- bonus isn't read as the plain one.
local function buildLines()
    local list = {}
    local function add(key, kind, rested)
        for _, tail in ipairs({ "", "_GROUP", "_RAID" }) do
            local fmt = _G[key .. tail]
            if type(fmt) == "string" then
                local pat, order = XPSource.Pattern(fmt)
                list[#list + 1] = { pat = pat, order = order, kind = kind, rested = rested, len = #fmt }
            end
        end
    end
    add("COMBATLOG_XPGAIN_FIRSTPERSON", "kill")
    for i = 1, 3 do add("COMBATLOG_XPGAIN_EXHAUSTION" .. i, "kill", true) end
    for i = 4, 5 do add("COMBATLOG_XPGAIN_EXHAUSTION" .. i, "kill") end
    add("COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED", "other")
    add("COMBATLOG_XPGAIN_QUEST", "quest", true)
    table.sort(list, function(a, b) return a.len > b.len end)
    XPSource.LINES = list
    local explore = type(ERR_ZONE_EXPLORED_XP) == "string" and ERR_ZONE_EXPLORED_XP
    -- Some languages end the sentence with a period, some don't.
    if explore then XPSource.EXPLORE = { XPSource.Pattern((explore:gsub("%.$", ""))) } end
end

local function digits(s)
    if type(s) ~= "string" then return nil end
    return tonumber((s:gsub("%D", "")))
end

-- A chat line read: { kind, mob, amount, bonus } or nil when it isn't one.
-- Kill lines' arguments: mob, amount, bonus, bonus word, group bonus; the
-- others start at the amount.
function XPSource.Read(text)
    if not XPSource.LINES then buildLines() end
    for _, l in ipairs(XPSource.LINES) do
        local caps = { text:match(l.pat) }
        if #caps > 0 then
            local args = {}
            for i, v in ipairs(caps) do args[l.order[i] or i] = v end
            local first = l.kind == "kill" and 2 or 1
            local amount = tonumber(args[first])
            if amount then
                return { kind = l.kind, mob = l.kind == "kill" and args[1] or nil, amount = amount,
                         bonus = l.rested and digits(args[first + 1]) or nil }
            end
        end
    end
end

-- The cursor's spot in UIParent units.
local function cursor()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    if not (type(x) == "number" and type(y) == "number" and s and s > 0) then return nil end
    return x / s, y / s
end

local function screenSpot(kind)
    local f = XPSource.SPOTS[kind] or XPSource.SPOTS.other
    return (UIParent:GetWidth() or 0) * f[1], (UIParent:GetHeight() or 0) * f[2]
end

local function prune()
    local t, count, oldest, oldestKey = now(), 0, nil, nil
    for guid, s in pairs(samples) do
        if t - s.t > XPSource.SAMPLE_KEEP then samples[guid] = nil
        else
            count = count + 1
            if not oldest or s.t < oldest then oldest, oldestKey = s.t, guid end
        end
    end
    if count > XPSource.SAMPLE_MAX and oldestKey then samples[oldestKey] = nil end
end

-- Remembers where the cursor is over a hostile unit, by its GUID. True while
-- there was one to remember.
function XPSource.Sample(unit)
    if not UnitExists(unit) then return false end
    local hostile = UnitCanAttack("player", unit)
    if secret(hostile) or not hostile then return false end
    local dead = UnitIsDead(unit)
    if secret(dead) or dead then return false end
    local guid = UnitGUID(unit)
    if not plain(guid) then return false end
    local x, y = cursor()
    if not x then return false end
    -- An enemy's name is secret in a PvP match or a restricted map: kept out then.
    local name = UnitName(unit)
    if secret(name) then name = nil end
    samples[guid] = { x = x, y = y, t = now(), name = name }
    prune()
    return true
end

-- While a hostile mob stays under the cursor its sample keeps up with both
-- moving; the poll stops as soon as there is none.
local polling = false
local function poll()
    if not XPSource.Sample("mouseover") then polling = false; return end
    C_Timer.After(XPSource.POLL, poll)
end
local function startPoll()
    if XPSource.Sample("mouseover") and not polling then
        polling = true
        C_Timer.After(XPSource.POLL, poll)
    end
end

-- The talk window's Complete button, read as the player clicks it (the
-- window says so: QuestTurnIn) and kept a while after, since the window
-- closes before the XP arrives.
local questSpot
function XPSource.QuestSpot()
    local fn = DUI.Npc and DUI.Npc.XPSpot
    local x, y = nil, nil
    if type(fn) == "function" then x, y = fn() end
    if x then questSpot = { x = x, y = y, t = now() } return x, y end
    if questSpot and now() - questSpot.t <= XPSource.QUEST_KEEP then return questSpot.x, questSpot.y end
end

-- The zone text's middle, when the game shows it.
local function zoneSpot()
    for _, name in ipairs({ "SubZoneTextFrame", "ZoneTextFrame" }) do
        local f = _G[name]
        if type(f) == "table" and f.IsShown and f:IsShown() then
            local x, y = f:GetCenter()
            local k = (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
            if type(x) == "number" and type(y) == "number" then return x * k, y * k end
        end
    end
end

-- How much a sample counts: in full when fresh, nothing once it's old.
function XPSource.Weight(age)
    if age <= XPSource.SAMPLE_FULL then return 1 end
    if age >= XPSource.SAMPLE_GONE then return 0 end
    return (XPSource.SAMPLE_GONE - age) / (XPSource.SAMPLE_GONE - XPSource.SAMPLE_FULL)
end

-- The mob a kill line speaks of: a recent death with a sample (its own name
-- first, the oldest first), else a sample with that name.
local function killSample(l)
    local t, best, bestDeath = now(), nil, nil
    for _, d in ipairs(deaths) do
        if not d.used and t - d.t <= XPSource.DEATH_KEEP then
            local s = d.guid and samples[d.guid]
            if s and (not best or (l.mob and s.name == l.mob and best.name ~= l.mob)) then
                best, bestDeath = s, d
            end
        end
    end
    if bestDeath then
        bestDeath.used = true
        return best
    end
    -- Not paired with a death: an unmarked one is taken, oldest first.
    for _, d in ipairs(deaths) do
        if not d.used and t - d.t <= XPSource.DEATH_KEEP then d.used = true; break end
    end
    if l.mob then
        local found
        for _, s in pairs(samples) do
            if s.name == l.mob and (not found or s.t > found.t) then found = s end
        end
        return found
    end
end

local function spotFor(kind, l)
    local dx, dy = screenSpot(kind)
    if kind == "kill" then
        local s = killSample(l)
        local w = s and XPSource.Weight(now() - s.t) or 0
        if w > 0 then return dx + (s.x - dx) * w, dy + (s.y - dy) * w, true end
        return dx, dy, false
    elseif kind == "quest" then
        local x, y = l.x, l.y
        if not x then x, y = XPSource.QuestSpot() end
        if x then return x, y, true end
    elseif kind == "explore" then
        local x, y = zoneSpot()
        if x then return x, y, true end
    end
    return dx, dy, false
end

local function decide(p, kind, l)
    p.done = true
    local x, y, known = spotFor(kind, l or {})
    local bonus = l and l.bonus
    if not bonus and kind == "kill" and p.restedDrop and p.restedDrop > 0 then
        -- Rested doubles a kill's XP and the pool drains by the whole gain.
        bonus = math.floor(math.min(p.restedDrop, p.amount) / 2)
    end
    DUI.SafeCall(p.fn, { kind = kind, x = x, y = y, known = known, bonus = bonus, amount = p.amount })
end

local function fresh(list, keep)
    local t = now()
    for i = #list, 1, -1 do
        local e = list[i]
        if e.used or t - e.t > keep then table.remove(list, i) end
    end
end

-- Pairs every waiting gain with what explains it.
function XPSource.Match()
    fresh(lines, XPSource.LINE_WAIT + XPSource.DELTA_WAIT)
    fresh(hints, XPSource.HINT_KEEP)
    fresh(deaths, XPSource.DEATH_KEEP)
    local t = now()
    for _, p in ipairs(pending) do
        if not p.done then
            -- A kill line of the same amount, else a hidden line (instances hide
            -- them): those pair in order.
            local found
            for _, l in ipairs(lines) do
                if not l.used and l.kind == "kill" and l.amount == p.amount then found = l; break end
            end
            if not found then
                for _, h in ipairs(hints) do
                    if not h.used and h.amount == p.amount then found = h; break end
                end
            end
            if not found then
                for _, l in ipairs(lines) do
                    if not l.used and (l.hidden or l.amount == p.amount) then found = l; break end
                end
            end
            if found then
                found.used = true
                decide(p, found.hidden and "kill" or found.kind, found)
            elseif t - p.t >= XPSource.DELTA_WAIT then
                -- Nothing claimed it: a quest just turned in still owns it.
                local h
                for _, e in ipairs(hints) do
                    if not e.used and e.kind == "quest" then h = e; break end
                end
                if h then h.used = true end
                decide(p, h and "quest" or "other", h)
            end
        end
    end
    for i = #pending, 1, -1 do
        if pending[i].done then table.remove(pending, i) end
    end
    if #pending > 0 and not XPSource.waiting then
        XPSource.waiting = true
        C_Timer.After(XPSource.DELTA_WAIT / 4, function()
            XPSource.waiting = false
            XPSource.Match()
        end)
    end
end

-- Asks what a gain of `amount` XP was. fn(src) runs once it is known, at once
-- or within DELTA_WAIT: src = { kind, x, y, known, bonus, amount }.
-- restedDrop: how much the rested pool fell with it, if known.
function XPSource.Resolve(amount, fn, restedDrop)
    pending[#pending + 1] = { amount = amount, fn = fn, t = now(), restedDrop = restedDrop }
    XPSource.Match()
end

-- Forgets every waiting gain (the bar was hidden, the profile changed).
function XPSource.Drop()
    for i = #pending, 1, -1 do pending[i] = nil end
end

local function onLine(text)
    if secret(text) then
        lines[#lines + 1] = { hidden = true, t = now() }
    elseif type(text) == "string" then
        local l = XPSource.Read(text)
        if not l then return end
        l.t = now()
        lines[#lines + 1] = l
    end
    XPSource.Match()
end

local function onSystem(text)
    if not plain(text) or type(text) ~= "string" then return end
    if not XPSource.LINES then buildLines() end
    local e = XPSource.EXPLORE
    if not e then return end
    local caps = { text:match(e[1]) }
    if #caps == 0 then return end
    local args = {}
    for i, v in ipairs(caps) do args[e[2][i] or i] = v end
    local amount = tonumber(args[2])
    if not amount then return end
    hints[#hints + 1] = { kind = "explore", amount = amount, t = now() }
    XPSource.Match()
end

function XPSource.Build()
    if XPSource.built then return end
    XPSource.built = true
    buildLines()
    DUI.RegisterEvent("UPDATE_MOUSEOVER_UNIT", startPoll)
    DUI.RegisterEvent("UNIT_DIED", function(_, guid)
        deaths[#deaths + 1] = { guid = plain(guid) and guid or nil, t = now() }
    end)
    DUI.RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN", function(_, text) onLine(text) end)
    DUI.RegisterEvent("CHAT_MSG_SYSTEM", function(_, text) onSystem(text) end)
    DUI.On("QuestTurnIn", function() XPSource.QuestSpot() end)
    DUI.RegisterEvent("QUEST_TURNED_IN", function(_, _, xp)
        if not (plain(xp) and type(xp) == "number" and xp > 0) then return end
        local x, y = XPSource.QuestSpot()
        hints[#hints + 1] = { kind = "quest", amount = xp, x = x, y = y, t = now() }
        XPSource.Match()
    end)
end
