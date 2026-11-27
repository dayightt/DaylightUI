-- Turns a snapshot into the on-screen list: blocks top to bottom (section header,
-- zone name, quest, achievement), each with a key, a position (y down from the
-- top) and a height, plus a quest's lines inside it. Keys name what a block shows
-- ("quest:123"), never where it is, so a block keeps its frame while it moves.
-- Pure: text heights come from measure().

local _, ns = ...
local secret = DaylightUI.IsSecret
local L = DaylightUI.L

local Layout = {}
ns.Layout = Layout

Layout.ICON = 13
Layout.TITLE_X = 18          -- where a quest title starts (after its icon)
Layout.OBJ_X = 24            -- where objectives start
Layout.COUNT_W = 34          -- room on the right for "11/15"
-- room after a tagged quest's title for its tag (Look.NewTag), by kind
Layout.TAG_W = { elite = 22, dungeon = 22, raid = 22, pvp = 42 }
Layout.PARTY_W = 24          -- room on the title's right for the party mark (Look.NewParty)
Layout.VOICE_W = 18          -- room on the title's right for Spoken's Play button (Voice.lua)
Layout.LINE_GAP = 1
Layout.QUEST_GAP = { normal = 7, compact = 4 }
Layout.HEADER_PAD = 3        -- below the header text, above its line
Layout.HEADER_LINE = 2
Layout.HEADER_GAP = 6        -- below the line
Layout.SECTION_GAP = 6       -- above every section but the first
Layout.ZONE_TOP, Layout.ZONE_GAP = 2, 3
Layout.FILTER_EXTRA = 10      -- the filter words' row under the header's line: the zone name's text size plus this (their line, air above and below)
Layout.BAR_H, Layout.BAR_TOP, Layout.BAR_BOTTOM = 7, 3, 2
Layout.LEADING = 3           -- line height minus font size
Layout.FAILED = L["Failed"]

local function lineH(size, text, width, measure)
    local h = measure and measure(text, size, width)
    h = type(h) == "number" and math.ceil(h) or 0
    return math.max(size + Layout.LEADING, h)
end

local function textLine(lines, key, kind, text, o, measure, y)
    y = y + Layout.LINE_GAP
    local h = lineH(o.sizes.objective, text, o.width - Layout.OBJ_X, measure)
    lines[#lines + 1] = { key = key, kind = kind, y = y, h = h, text = text }
    return y + h
end

local function objLines(lines, objs, o, measure, y)
    for _, ob in ipairs(objs) do
        if not (o.hideDone and ob.done) then
            y = y + Layout.LINE_GAP
            local room = o.width - Layout.OBJ_X - (ob.kind ~= "text" and Layout.COUNT_W or 0)
            local h = lineH(o.sizes.objective, ob.text, room, measure)
            lines[#lines + 1] = { key = "obj:" .. ob.index, kind = "obj", y = y, h = h, obj = ob }
            y = y + h
            if ob.kind == "bar" then
                y = y + Layout.BAR_TOP
                lines[#lines + 1] = { key = "bar:" .. ob.index, kind = "bar", y = y, h = Layout.BAR_H, pct = ob.pct }
                y = y + Layout.BAR_H + Layout.BAR_BOTTOM
            end
        end
    end
    return y
end

-- level: the quest's level, shown in front ("[15] Title") when o.levels is on.
-- tag: the quest's type (Data.Tag), shown after the title when o.tags is on,
-- with room reserved. party: how many party members are on it, a mark at the
-- line's right end when o.party is on, room reserved. voice: Spoken has a voice
-- line for it, a Play button at the right end (before the party mark), room
-- reserved. The title gets whatever width is left after the icon, tag, Play
-- button and party mark.
-- A tag's room on the title's line: its width and the gap before it.
function Layout.TagRoom(tag)
    local look = ns.Look
    local w = look and look.TagWidth and look.TagWidth(tag) or Layout.TAG_W[tag] or 0
    return w + (look and look.TAG_GAP or 5)
end

function Layout.TitleRoom(width, tag, party, voice)
    return width - Layout.TITLE_X - (tag and Layout.TagRoom(tag) or 0) - (party and Layout.PARTY_W or 0)
        - (voice and Layout.VOICE_W or 0)
end

local function titleLine(lines, title, o, measure, level, tag, party, voice)
    if o.caps then title = DaylightUI.Style.Upper(title) end
    if o.levels and type(level) == "number" and level > 0 then title = "[" .. level .. "] " .. title end
    tag = o.tags and Layout.TAG_W[tag] and tag or nil
    party = o.party and type(party) == "number" and party > 0 and party or nil
    voice = voice == true or nil
    local room = Layout.TitleRoom(o.width, tag, party, voice)
    local h = lineH(o.sizes.title, title, room, measure)
    lines[1] = { key = "title", kind = "title", y = 0, h = h, text = title, tag = tag, party = party, voice = voice }
    return h
end

local function questBlock(q, o, measure, gap)
    local lines = {}
    local y = titleLine(lines, q.title, o, measure, q.level, q.tag, q.party, q.voice)
    local folded = o.folds and o.folds["q" .. q.id]
    if o.foldReady and q.state == "ready" and not q.timer then folded = true end
    if folded then
        -- Folded from its menu: just the title, plus a timer if one is still running.
        if q.timer then y = textLine(lines, "timer", "timer", "", o, measure, y) end
    elseif q.state == "failed" then
        y = textLine(lines, "failed", "failed", Layout.FAILED, o, measure, y)
    else
        if q.state == "ready" then
            y = textLine(lines, "turnin", "turnin", q.turnIn or "", o, measure, y)
        else
            y = objLines(lines, q.objs, o, measure, y)
        end
        -- Ready quests keep their timer: a timed quest fails if it isn't turned in.
        if q.timer then y = textLine(lines, "timer", "timer", "", o, measure, y) end
    end
    return { key = "quest:" .. q.id, kind = "quest", quest = q, lines = lines, h = y + gap, item = q.item ~= nil }
end

local function achBlock(a, o, measure, gap)
    local lines = {}
    local y = titleLine(lines, a.title, o, measure)
    y = objLines(lines, a.objs, o, measure, y)
    return { key = "ach:" .. a.id, kind = "ach", ach = a, lines = lines, h = y + gap }
end

-- Most recent progress first. Quests with an entry in recent (questID -> number,
-- higher = newer) go first, newest on top, and the rest keep the game's order
-- below them. Sorts the snapshot's list in place.
function Layout.RecentFirst(quests, recent)
    local any = false
    for _, q in ipairs(quests) do if recent[q.id] then any = true; break end end
    if not any then return end
    local at = {}
    for i, q in ipairs(quests) do at[q] = i end
    table.sort(quests, function(a, b)
        local ra, rb = recent[a.id] or 0, recent[b.id] or 0
        if ra ~= rb then return ra > rb end
        return at[a] < at[b]
    end)
end

local function levelOf(q) return type(q.level) == "number" and q.level or 0 end

-- Order within each zone group (o.sort; the groups themselves keep their order).
-- o.frozen (questID -> position, in combat) keeps the on-screen order and puts new
-- quests after the rest, so nothing re-sorts under the mouse mid-fight.
-- here (header name -> true) is given only for one list of every zone (level
-- across zones with zone names off): the zone you're in goes first.
function Layout.Sort(quests, o, here)
    local at = {}
    for i, q in ipairs(quests) do at[q] = i end
    local function stable(key)
        table.sort(quests, function(a, b)
            local ka, kb = key(a), key(b)
            if ka ~= kb then return ka < kb end
            return at[a] < at[b]
        end)
    end
    if o.frozen then
        stable(function(q) return o.frozen[q.id] or math.huge end)
    elseif o.sort == "recent" and o.recent then
        Layout.RecentFirst(quests, o.recent)
    elseif o.sort == "levelAll" and here then
        -- Levels in the game stay well under this, so being here always wins.
        stable(function(q) return (here[q.zone] and 0 or 100000) + levelOf(q) end)
    elseif o.sort == "level" or o.sort == "levelAll" then
        stable(levelOf)
    elseif o.sort == "ready" then
        stable(function(q) return q.state == "ready" and 0 or 1 end)
    elseif o.sort == "watched" then
        stable(function(q) return q.watched and 0 or 1 end)
    elseif o.sort == "near" and o.near then
        stable(function(q) return o.near[q.id] or math.huge end)
    end
end

-- Zone order: most recent progress first, so a quest that progresses reaches the
-- very top, not just the top of its zone. Zones without an entry keep their place
-- below (the current zone, then log order). Level across zones puts the zone with
-- the lowest quest first. o.hereFirst keeps the zones you're in (here, header
-- name -> true) above all of that. o.frozenZones (name -> position, in combat)
-- keeps the on-screen order. o.zoneOrder (a list of names, dragged or picked from
-- the Quests menu) is the player's own order and wins over the sort's.
function Layout.SortZones(groups, o, here)
    local key
    if o.frozenZones then
        key = function(g) return o.frozenZones[g.name] or math.huge end
        here = nil
    elseif type(o.zoneOrder) == "table" and #o.zoneOrder > 0 then
        key = Layout.OwnZoneKey(groups, o.zoneOrder)
    elseif o.sort == "recent" and o.recent then
        key = function(g)
            local newest = 0
            for _, q in ipairs(g.quests) do
                local n = o.recent[q.id]
                if n and n > newest then newest = n end
            end
            return -newest
        end
    elseif o.sort == "levelAll" then
        key = function(g)
            local low = math.huge
            for _, q in ipairs(g.quests) do low = math.min(low, levelOf(q)) end
            return low
        end
    end
    if not o.hereFirst then here = nil end
    if not key and not here then return end
    local rank, at, away = {}, {}, {}
    for i, g in ipairs(groups) do
        rank[g], at[g] = key and key(g) or 0, i
        away[g] = here and not here[g.name] and 1 or 0
    end
    table.sort(groups, function(a, b)
        if away[a] ~= away[b] then return away[a] < away[b] end
        if rank[a] ~= rank[b] then return rank[a] < rank[b] end
        return at[a] < at[b]
    end)
end

-- Ranks for the player's own zone order. A zone that isn't in it yet (a new
-- quest's) slots in right after the zone the log lists before it.
function Layout.OwnZoneKey(groups, own)
    local pos, rank = {}, {}
    for i, name in ipairs(own) do pos[name] = i end
    local last, step = 0, 0
    for _, g in ipairs(groups) do
        if pos[g.name] then
            last, step = pos[g.name], 0
            rank[g] = last
        else
            step = step + 1
            rank[g] = last + step / 1000
        end
    end
    return function(g) return rank[g] end
end

-- A new own order: shown (the zones on screen, in their new order), with the
-- zones of the old order that aren't on screen kept after the zone they followed.
function Layout.MergeZoneOrder(old, shown)
    local out, has = {}, {}
    for i, name in ipairs(shown) do out[i], has[name] = name, true end
    local prev
    for _, name in ipairs(old or {}) do
        if not has[name] then
            local at = 1
            if prev then
                for i, n in ipairs(out) do if n == prev then at = i + 1; break end end
            end
            table.insert(out, at, name)
            has[name] = true
        end
        prev = name
    end
    return out
end

-- A fight with `fightFocus` on: only the priority quest, and quests with an item
-- button (those buttons can't move in a fight). A copy, the snapshot stays whole.
function Layout.FightOnly(snap)
    local out = {}
    for k, v in pairs(snap) do out[k] = v end
    out.groups, out.achievements = {}, {}
    for _, g in ipairs(snap.groups) do
        local keep = {}
        for _, q in ipairs(g.quests) do
            if q.focus or q.item then keep[#keep + 1] = q end
        end
        out.groups[#out.groups + 1] = { name = g.name, quests = keep }
    end
    return out
end

-- The height of the filter words' row: it follows the tracker's text size.
function Layout.FilterH(o)
    return (o.sizes and o.sizes.zone or 10) + Layout.FILTER_EXTRA
end

function Layout.Build(snap, o, measure)
    if o.fightOnly then snap = Layout.FightOnly(snap) end
    local blocks, y = {}, 0
    local gap = o.compact and Layout.QUEST_GAP.compact or Layout.QUEST_GAP.normal
    local folds = o.folds or {}
    local function push(b)
        b.y = y
        y = y + b.h
        blocks[#blocks + 1] = b
    end
    local function header(id, label, count, filter)
        if #blocks > 0 then y = y + Layout.SECTION_GAP end
        local textH = lineH(o.sizes.header, DaylightUI.Style.Upper(label), o.width - 30, measure)
        push({ key = "section:" .. id, kind = "header", id = id, label = label, count = count,
               folded = folds[id] == true, textH = textH, filter = filter,
               h = textH + Layout.HEADER_PAD + Layout.HEADER_LINE + Layout.HEADER_GAP + (filter and Layout.FilterH(o) or 0) })
    end
    local total = 0
    for _, g in ipairs(snap.groups) do total = total + #g.quests end
    local function shownZone(g)
        return o.filter ~= "zone" or g.name == snap.zone or (snap.here and snap.here[g.name])
    end
    -- Quests ready to hand in can gather in their own section after the rest.
    -- In a fight the section keeps the quests it had before it (o.frozenReady), so
    -- nothing moves under the mouse: one turning ready waits in its zone until the end.
    local ready, rest, readyIDs = {}, {}, {}
    if o.readyLast then
        local inReady = o.frozen and o.frozenReady
            and function(q) return o.frozenReady[q.id] == true end
            or function(q) return q.state == "ready" end
        for _, g in ipairs(snap.groups) do
            local keep = {}
            for _, q in ipairs(g.quests) do
                if inReady(q) then
                    if shownZone(g) then ready[#ready + 1] = q; readyIDs[q.id] = true end
                else
                    keep[#keep + 1] = q
                end
            end
            rest[g] = keep
        end
    end
    local function questsOf(g) return rest[g] or g.quests end
    if total > 0 or o.emptyHeader then
        -- With the option on, the filter (All / This zone) sits right under this header's line,
        -- on the right, while the quests show: it never sits over a title.
        header("quests", L["Quests"], snap.logCount .. "/" .. snap.logMax,
               o.filterRow and not folds.quests and (o.filter == "zone" and "zone" or "all") or nil)
        local flat = o.sort == "levelAll" and not o.zoneNames
        if not folds.quests and not flat then Layout.SortZones(snap.groups, o, snap.here) end
        if not folds.quests and flat then
            -- Level across zones with no zone names: one list of every shown zone,
            -- equal levels in the game's zone order (the zone you're in first).
            local list = {}
            for _, g in ipairs(snap.groups) do
                if shownZone(g) then
                    for _, q in ipairs(questsOf(g)) do list[#list + 1] = q end
                end
            end
            Layout.Sort(list, o, o.hereFirst and snap.here or nil)
            for _, q in ipairs(list) do push(questBlock(q, o, measure, gap)) end
        elseif not folds.quests then
            for _, g in ipairs(snap.groups) do
                if #questsOf(g) > 0 and shownZone(g) then
                    -- A zone can only be folded while its name shows, otherwise nothing could unfold it.
                    local folded = false
                    if o.zoneNames then
                        local key = "zone:" .. g.name
                        folded = folds[key] == true
                        local h = Layout.ZONE_TOP + lineH(o.sizes.zone, DaylightUI.Style.Upper(g.name), o.width - Layout.TITLE_X - 30, measure) + Layout.ZONE_GAP
                        push({ key = key, kind = "zone", id = key, label = g.name, folded = folded, count = #questsOf(g), h = h })
                    end
                    if not folded then
                        local list = questsOf(g)
                        Layout.Sort(list, o)
                        for _, q in ipairs(list) do push(questBlock(q, o, measure, gap)) end
                    end
                end
            end
        end
    end
    if #ready > 0 then
        header("ready", L["Ready to turn in"], tostring(#ready))
        if not folds.ready then
            Layout.Sort(ready, o)
            for _, q in ipairs(ready) do push(questBlock(q, o, measure, gap)) end
        end
    end
    if #snap.achievements > 0 then
        header("achievements", L["Achievements"], tostring(#snap.achievements))
        if not folds.achievements then
            for _, a in ipairs(snap.achievements) do push(achBlock(a, o, measure, gap)) end
        end
    end
    return blocks, y, readyIDs
end

-- What changed between two layouts, by key.
function Layout.Diff(old, new)
    local was, now = {}, {}
    for _, b in ipairs(old or {}) do was[b.key] = b end
    for _, b in ipairs(new) do now[b.key] = b end
    local d = { enter = {}, leave = {}, moved = {} }
    for k, b in pairs(now) do
        local o = was[k]
        if not o then d.enter[k] = true elseif o.y ~= b.y then d.moved[k] = true end
    end
    for k in pairs(was) do if not now[k] then d.leave[k] = true end end
    return d
end

-- Deep equality on plain data (no frames, no cycles). A secret value can't be
-- compared, so it counts as changed.
local function same(a, b)
    if secret(a) or secret(b) then return false end
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not same(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- True when two layouts show exactly the same thing: same blocks, positions and
-- contents (a quest event that changed nothing visible).
function Layout.Same(old, new)
    if #old ~= #new then return false end
    for i = 1, #new do
        if not same(old[i], new[i]) then return false end
    end
    return true
end

-- Item buttons can't follow in combat. Returns true when the new layout would
-- move, add or remove a quest that has one. view (optional) describes how the
-- list's view moves too: { from, to = old and new list heights, max = height
-- limit, offset = scroll, growUp }. Growing upward, the view stands on its bottom,
-- so a new shown height moves every row; a list too short for the scroll pulls it
-- back (Scroll.Set), which moves them too.
function Layout.WouldMoveItems(old, new, view)
    local was, any = {}, false
    for _, b in ipairs(old or {}) do if b.item then was[b.key] = b.y; any = true end end
    for _, b in ipairs(new) do
        if b.item then
            if was[b.key] ~= b.y then return true end
            was[b.key] = nil
        end
    end
    if next(was) ~= nil then return true end
    if any and view and type(view.to) == "number" then
        local max = view.max or math.huge
        local shown = math.min(view.to, max)
        if view.growUp and type(view.from) == "number" and math.min(view.from, max) ~= shown then return true end
        if (view.offset or 0) > math.max(0, view.to - shown) then return true end
    end
    return false
end
