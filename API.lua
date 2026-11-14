-- The public API other addons build on (DaylightUI.API; Plugins.lua creates
-- the table and handles which version a plugin needs). Find our frames, hear
-- when they're created, change unit, go away or get restyled, and read
-- settings.
--
-- Frame kinds (fixed): "unit" (player, target, targettarget, pet, focus,
-- focustarget), "party", "raid", "partypet", "nameplate", "actionbutton".
-- List rows in our windows (1.2): "shoptile" (the vendor's shelf, unit =
-- "buy:<index>" or "buyback:<index>", see API.ShopItem) and "craftrow" (the
-- profession window's recipe lines, unit = the recipe id). 1.4: "platecast",
-- a nameplate's cast bar (unit = its plate's). 1.5: "actionbar", the action
-- bars' holders (unit = the bar's key: "main", "bar2"... "stance", "pet").
-- 1.6: "meterrow", a damage meter window's row (unit = "<window>:<place>").
-- Frame events, args (kind, frame, unit, isPreview): FrameMade,
-- FrameUnitChanged, FrameRemoved, FrameStyled. A frame that changes unit (a
-- pooled plate) first gets FrameRemoved for the old one. Preview frames (test
-- mode, options samples) get the events too, with isPreview, but are never
-- returned by lookups. Other events passed on from the core: StyleChanged,
-- SettingChanged (scope, path, value), TestModeChanged, UnlockChanged, Login.
-- The profession window's own (1.2, Report.Event): CraftShown, CraftHidden,
-- CraftProfessionChanged (skillLine), CraftRecipeSelected (recipeID),
-- CraftStarted (recipeID, count), CraftMade (recipeID, done, count),
-- CraftStopped (recipeID, done, count).
--
-- Our frames call the reporters below (DUI.APIReport: Made, Unit, Back, Gone,
-- Occupant, Styled), each behind Report.Wants where it costs anything, so
-- with nobody listening a report is just a table read. They're internal and
-- not part of DaylightUI.API (another addon could break the lookups through
-- them). Modules reach the core only through the global DaylightUI, so
-- DaylightUI.APIReport is reachable from outside too. It's internal by
-- promise (never documented, and a test keeps it off the API), not by being
-- hidden.
-- Handlers run through SafeCallAs under their owner's name.

local ADDON_NAME, DUI = ...
local L = DUI.L

local API = DUI.API
local Report = {}
DUI.APIReport = Report

local FRAME_EVENTS = { FrameMade = true, FrameUnitChanged = true, FrameRemoved = true, FrameStyled = true }
local PASSED_ON = { "StyleChanged", "SettingChanged", "TestModeChanged", "UnlockChanged", "Login" }
local passedOn = {}
for _, name in ipairs(PASSED_ON) do passedOn[name] = true end
-- The only events our windows may send (Report.Event).
local OWN_EVENTS = { CraftShown = true, CraftHidden = true, CraftProfessionChanged = true,
    CraftRecipeSelected = true, CraftStarted = true, CraftMade = true, CraftStopped = true,
    -- The damage meter's (1.6).
    MeterFightStarted = true, MeterFightEnded = true, MeterReset = true }

local lists = {} -- event -> array of listeners { fn, owner, event, dead }
local counts = {} -- event -> listeners still alive
local firing = {} -- event -> how many fires of it are running
local dirty = {} -- event -> a dead listener awaits compaction

local live = {}       -- live[kind][frame] = unit (real frames only)
local byUnit = {}     -- byUnit[kind][unit] = frame
local previews = {}   -- previews[kind][frame] = unit or false
local made = {} -- made[kind][frame] = isPreview, every frame ever made (kept after Gone)
local rowInfo = setmetatable({}, { __mode = "k" }) -- frame -> what it shows (Report.Row, Report.SetInfo)

local function str(v) return type(v) == "string" and v ~= "" and v or nil end

-- Listeners

local function compact(event)
    local list = lists[event]
    local j = 0
    for i = 1, #list do
        local e = list[i]
        if not e.dead then
            j = j + 1
            list[j] = e
        end
    end
    for i = #list, j + 1, -1 do list[i] = nil end
    dirty[event] = nil
end

-- Returns a handle, or nil (with one line in chat) for an unknown event or a
-- missing function. owner is the plugin's name, used in its errors.
function API.On(event, fn, owner)
    if not (FRAME_EVENTS[event] or passedOn[event] or OWN_EVENTS[event]) then
        DUI.Print(string.format(L["%s: DaylightUI has no event called %s."], str(owner) or L["an addon"], tostring(event)))
        return nil
    end
    if type(fn) ~= "function" then
        DUI.Print(string.format(L["%s: %s needs a function."], str(owner) or L["an addon"], tostring(event)))
        return nil
    end
    local list = lists[event]
    if not list then list = {}; lists[event] = list end
    local e = { fn = fn, owner = str(owner), event = event }
    list[#list + 1] = e
    counts[event] = (counts[event] or 0) + 1
    if event == "FrameMade" then
        -- Replays every frame made before this listener was added (buttons are built
        -- at file load) with its current unit, to this listener only, real frames
        -- then previews. Copied first since a handler may report more.
        local owner = e.owner or L["an addon"]
        local todo, n = {}, 0
        for pass = 1, 2 do
            local wantPreview = pass == 2
            for kind, m in pairs(made) do
                for frame, isPreview in pairs(m) do
                    if isPreview == wantPreview then
                        local unit
                        if isPreview then unit = (previews[kind] and previews[kind][frame]) or nil
                        else unit = live[kind] and live[kind][frame] end
                        n = n + 1
                        todo[n] = { kind, frame, unit, isPreview }
                    end
                end
            end
        end
        for i = 1, n do
            if e.dead then break end
            local t = todo[i]
            DUI.SafeCallAs(owner, fn, t[1], t[2], t[3], t[4])
        end
    end
    return e
end

local stopPainterRef -- the Paint section's stopper (defined below)

function API.Off(handle)
    if type(handle) == "table" and handle.painter == true then
        if stopPainterRef then stopPainterRef(handle) end
        return
    end
    if type(handle) ~= "table" or handle.dead or not handle.event or not handle.fn then return end
    handle.dead = true
    local event = handle.event
    counts[event] = (counts[event] or 1) - 1
    if (firing[event] or 0) == 0 then compact(event) else dirty[event] = true end
end

function Report.Wants(event)
    return (counts[event] or 0) > 0
end

-- Notifies everyone listening to event: the listeners present when it began
-- (one added now waits for the next fire, though FrameMade's replay hands it
-- the frame in progress at once), skipping any removed since.
local function fire(event, a, b, c, d)
    local list = lists[event]
    if not list then return end
    local n = #list
    if n == 0 then return end
    firing[event] = (firing[event] or 0) + 1
    for i = 1, n do
        local e = list[i]
        if not e.dead then DUI.SafeCallAs(e.owner or L["an addon"], e.fn, a, b, c, d) end
    end
    local depth = firing[event] - 1
    firing[event] = depth
    if depth == 0 and dirty[event] then compact(event) end
end

-- Reporters (internal): the registry behind the lookups, and the events

local function bucket(tbl, kind)
    local t = tbl[kind]
    if not t then t = {}; tbl[kind] = t end
    return t
end

local function setUnit(kind, frame, unit)
    local l, u = bucket(live, kind), bucket(byUnit, kind)
    local old = l[frame]
    if old ~= nil and u[old] == frame then u[old] = nil end
    l[frame] = unit
    if unit ~= nil then u[unit] = frame end
end

function Report.Made(kind, frame, unit, isPreview)
    bucket(made, kind)[frame] = isPreview and true or false
    if isPreview then
        bucket(previews, kind)[frame] = unit or false
    elseif unit ~= nil then
        setUnit(kind, frame, unit)
    end
    fire("FrameMade", kind, frame, unit, isPreview and true or false)
    -- A frame painted before it was reported (built, then reported): plugins
    -- painting its kind apply their look now.
    if Report.Painted then Report.Painted(kind, frame, rowInfo[frame]) end
end

-- The frame lets go of its unit (a plate released, a tile cleared, a preview
-- discarded). It stays known as made, so a later Unit is only a unit change,
-- never a second FrameMade.
function Report.Gone(kind, frame, isPreview)
    if isPreview then
        local p = bucket(previews, kind)
        local old = p[frame]
        p[frame] = nil
        if old ~= nil then fire("FrameRemoved", kind, frame, old or nil, true) end
        return
    end
    local old = bucket(live, kind)[frame]
    if old == nil then return end
    setUnit(kind, frame, nil)
    fire("FrameRemoved", kind, frame, old, false)
end

-- The frame now shows unit. If it showed another, that one is removed first.
function Report.Unit(kind, frame, unit, isPreview)
    if unit == nil then return Report.Gone(kind, frame, isPreview) end
    if isPreview then
        local p = bucket(previews, kind)
        local old = p[frame]
        if old == unit then return end
        if old then fire("FrameRemoved", kind, frame, old, true) end
        p[frame] = unit
        return fire("FrameUnitChanged", kind, frame, unit, true)
    end
    local old = bucket(live, kind)[frame]
    if old == unit then return end
    if old ~= nil then
        setUnit(kind, frame, nil)
        fire("FrameRemoved", kind, frame, old, false)
    end
    setUnit(kind, frame, unit)
    fire("FrameUnitChanged", kind, frame, unit, false)
end

-- A preview shown again with no unit (the nameplate samples, created with
-- none): FrameUnitChanged with nil.
function Report.Back(kind, frame)
    local p = bucket(previews, kind)
    if p[frame] ~= nil then return end
    p[frame] = false
    fire("FrameUnitChanged", kind, frame, nil, true)
end

-- A frame that keeps its unit token for good (target, focus, found by that
-- token even when empty) has a new occupant, or none: FrameUnitChanged.
function Report.Occupant(kind, frame, unit)
    local l = live[kind]
    if not (l and l[frame] == unit) then return Report.Unit(kind, frame, unit) end
    fire("FrameUnitChanged", kind, frame, unit, false)
end

function Report.Styled(kind, frame, isPreview)
    local unit
    if isPreview then unit = (previews[kind] and previews[kind][frame]) or nil
    else unit = live[kind] and live[kind][frame] end
    fire("FrameStyled", kind, frame, unit, isPreview and true or false)
end

-- A window's event (OWN_EVENTS only; just a table read when nobody listens).
function Report.Event(event, a, b, c, d)
    if OWN_EVENTS[event] and (counts[event] or 0) > 0 then fire(event, a, b, c, d) end
end

-- Rows of a list refilled repeatedly from a pool (shop tiles, profession list
-- lines). Call Report.Row for each visible row in order, then Report.ListDone.
-- A known row is a unit change when its key moved, or a new occupant when the
-- same key now holds something else (info.id, like another shop's item at the
-- same index). A row not in this fill lets go of its key. Then FrameStyled
-- fires for each, so a plugin repaints over our fresh paint. info (a table or
-- nil) is what API.ShopItem returns.
local fills = {} -- kind -> { now = { [frame] = isPreview }, was = {...}, order }

function Report.Row(kind, frame, key, info, isPreview)
    isPreview = isPreview and true or false
    local f = fills[kind]
    if not f then f = { now = {}, was = {}, order = {} }; fills[kind] = f end
    f.now[frame] = isPreview
    f.order[#f.order + 1] = frame
    local old = rowInfo[frame]
    rowInfo[frame] = info
    local m = bucket(made, kind)
    if m[frame] == nil then return Report.Made(kind, frame, key, isPreview) end
    if m[frame] ~= isPreview then
        -- A pooled row moving between the sample shop and a real one.
        Report.Gone(kind, frame, m[frame])
        m[frame] = isPreview
    end
    local cur
    if isPreview then cur = previews[kind] and previews[kind][frame] or nil
    else cur = live[kind] and live[kind][frame] end
    if cur == key and not isPreview and type(old) == "table" and type(info) == "table" and old.id ~= info.id then
        return Report.Occupant(kind, frame, key)
    end
    Report.Unit(kind, frame, key, isPreview)
end

function Report.ListDone(kind)
    local f = fills[kind]
    if not f then return end
    for frame, isPreview in pairs(f.was) do
        if f.now[frame] == nil then
            rowInfo[frame] = nil
            Report.Gone(kind, frame, isPreview)
        end
    end
    local order = f.order
    f.was, f.now, f.order = f.now, {}, {}
    if (counts.FrameStyled or 0) > 0 then
        for i = 1, #order do Report.Styled(kind, order[i], f.was[order[i]]) end
    end
    if Report.Painting and Report.Painting(kind) then
        for i = 1, #order do
            local frame = order[i]
            Report.Painted(kind, frame, rowInfo[frame])
        end
    end
end

-- What a frame shows, passed to Paint as its info (a table owned by the caller).
function Report.SetInfo(frame, info) rowInfo[frame] = info end

-- The list went away (its window closed), so every row lets go of its key.
function Report.ListClear(kind)
    local f = fills[kind]
    if not f then return end
    f.now, f.order = {}, {}
    Report.ListDone(kind)
end

-- Paint (1.3): a plugin's look applied to our frames right after each of our
-- own paints. A module that opens a kind provides its frames' named parts
-- (Report.Parts), reports when it painted one (Report.Painted), checks before
-- coloring a piece a plugin claimed (Report.Owned), and can repaint a frame
-- back to our look (Report.Repainter).

local partsOf = {} -- kind -> fn(frame) -> { name = region }
local infoOf = {} -- kind -> fn(frame) -> what it shows now, for a paint with none given
local repaint = {} -- kind -> fn(frame)
local painters = {} -- kind -> array of { fn, owner, owns = { part = true }, dead, painter = true }
local owners = {} -- kind -> { part -> the painter holding it }

local paintAsked -- painters requested before their kind's module loaded (below)
function Report.Parts(kind, fn)
    local had = partsOf[kind]
    partsOf[kind] = fn
    if not had and paintAsked then paintAsked(kind) end
end
-- A kind whose frames can say what they show at any time (action buttons):
-- a painter started, stopped or caught up gets that instead of nothing.
function Report.Info(kind, fn) infoOf[kind] = fn end

-- Is anyone painting kind? A module skips gathering info when nobody is.
function Report.Painting(kind) return painters[kind] ~= nil end

-- The kind a frame was made as (each frame has one kind), or nil.
function Report.KindOf(frame)
    for kind, m in pairs(made) do
        if m[frame] ~= nil then return kind end
    end
    return nil
end

-- The same calls by frame, for code that paints frames of several kinds (unit
-- frames: "unit", "party", "raid", "partypet"). Each starts with a table read
-- and stops there while no plugin paints or claims anything.
local ownedAny = 0 -- pieces claimed, across all kinds
function Report.PaintedFrame(frame, info)
    if next(painters) == nil then return end
    local kind = Report.KindOf(frame)
    if kind then Report.Painted(kind, frame, info) end
end

function Report.OwnedOn(frame, part)
    if ownedAny == 0 then return false end
    local kind = Report.KindOf(frame)
    return kind ~= nil and Report.Owned(kind, part)
end
-- whole: fn() repaints every frame of the kind at once (a list refilled),
-- otherwise fn(frame) one frame at a time.
local repaintWhole = {}
function Report.Repainter(kind, fn, whole)
    repaint[kind] = fn
    repaintWhole[kind] = whole == true or nil
end

-- The visible frames of kind, frame -> unit. Read only, never keep or change it.
function Report.Live(kind) return live[kind] end

function Report.Owned(kind, part)
    local o = owners[kind]
    return o ~= nil and o[part] ~= nil
end

local function paintOne(e, kind, frame, info)
    local get = partsOf[kind]
    if not get then return end
    local ok, parts = pcall(get, frame)
    if not ok or type(parts) ~= "table" then return end
    if info == nil and infoOf[kind] then
        local got, i = pcall(infoOf[kind], frame)
        if got then info = i end
    end
    DUI.SafeCallAs(e.owner or L["an addon"], e.fn, frame, parts, info)
end

-- Right after we painted frame, runs every painter of its kind in the order
-- they registered. With none it's just a table read. A painter stopped while
-- its kind is being painted (by itself or another) is only marked, and the
-- list is cleaned up after the loop.
local paintingNow, paintDirty = {}, {}
local function tidy(kind)
    local list = painters[kind]
    if not list then return end
    for i = #list, 1, -1 do if list[i].dead then table.remove(list, i) end end
    if #list == 0 then painters[kind] = nil end
    paintDirty[kind] = nil
end

function Report.Painted(kind, frame, info)
    local list = painters[kind]
    if not list then return end
    paintingNow[kind] = (paintingNow[kind] or 0) + 1
    for i = 1, #list do
        local e = list[i]
        if e and not e.dead then paintOne(e, kind, frame, info) end
    end
    local depth = paintingNow[kind] - 1
    paintingNow[kind] = depth
    if depth == 0 and paintDirty[kind] then tidy(kind) end
end

-- Every frame of kind ever made (real first, then previews), once each.
local function eachMade(kind, fn)
    local m = made[kind]
    if not m then return end
    local list = {}
    for pass = 1, 2 do
        for frame, isPreview in pairs(m) do
            if isPreview == (pass == 2) then list[#list + 1] = frame end
        end
    end
    for _, frame in ipairs(list) do fn(frame) end
end

-- Puts our own look back on every frame of kind (when a claim begins or ends).
local function repaintAll(kind)
    local back = repaint[kind]
    if not back then return end
    if repaintWhole[kind] then DUI.SafeCall(back) return end
    eachMade(kind, function(frame) DUI.SafeCall(back, frame) end)
end

local function claim(kind, e)
    local o = owners[kind]
    if not o then o = {}; owners[kind] = o end
    for part in pairs(e.owns) do
        local held = o[part]
        if held and held ~= e then
            DUI.Print(string.format(L["%s and %s both want to paint the %s of %s; %s keeps it."],
                held.owner or L["an addon"], e.owner or L["an addon"], part, kind, held.owner or L["an addon"]))
        else
            o[part] = e
            ownedAny = ownedAny + 1
        end
    end
end

-- A painter stops: its pieces pass to the next painter that asked for them,
-- and every frame of the kind gets our own look back at once.
local function stopPainter(e)
    if e.dead then return end
    e.dead = true
    if e.owner and Report.Count then Report.Count(e.owner, "paints", e.kind, -1) end
    local kind = e.kind
    local o = owners[kind]
    if o then
        for part, held in pairs(o) do
            if held == e then
                o[part] = nil
                ownedAny = ownedAny - 1
                for _, other in ipairs(painters[kind] or {}) do
                    if not other.dead and other.owns[part] then
                        o[part] = other
                        ownedAny = ownedAny + 1
                        break
                    end
                end
            end
        end
    end
    if (paintingNow[kind] or 0) > 0 then paintDirty[kind] = true else tidy(kind) end
    repaintAll(kind)
    -- What the others paint goes back on top of our look.
    for _, other in ipairs(painters[kind] or {}) do
        if not other.dead then
            eachMade(kind, function(frame) paintOne(other, kind, frame, rowInfo[frame]) end)
        end
    end
end

stopPainterRef = stopPainter

-- me.Paint(kind, fn, { owns = { "fill", ... } }) runs fn(frame, parts, info) on
-- every existing frame of kind, then after each of our paints. Returns a
-- handle (API.Off stops it). A kind whose module hasn't loaded yet (the
-- plugin's name sorts first) is kept and painted once its parts are known.
local function startPainter(owner, kind, fn, opts)
    if type(kind) ~= "string" or kind == "" or type(fn) ~= "function" then return nil end
    local e = { fn = fn, owner = owner, kind = kind, owns = {}, painter = true }
    if type(opts) == "table" and type(opts.owns) == "table" then
        for _, part in ipairs(opts.owns) do
            if type(part) == "string" then e.owns[part] = true end
        end
    end
    local list = painters[kind]
    if not list then list = {}; painters[kind] = list end
    list[#list + 1] = e
    claim(kind, e)
    -- A claimed piece is no longer ours, so remove our look from it before the
    -- plugin paints (a gradient overlay, a vertex color).
    if partsOf[kind] then
        if next(e.owns) then repaintAll(kind) end
        eachMade(kind, function(frame) if not e.dead then paintOne(e, kind, frame, rowInfo[frame]) end end)
    end
    if DUI.Fire then DUI.Fire("PluginsChanged") end
    return e
end

-- A kind's parts just arrived (its module loaded after the plugin asked).
-- Claims take effect and every frame made so far is painted.
paintAsked = function(kind)
    local list = painters[kind]
    if not list then return end
    local claims = false
    for _, e in ipairs(list) do if not e.dead and next(e.owns) then claims = true end end
    if claims then repaintAll(kind) end
    for _, e in ipairs(list) do
        if not e.dead then eachMade(kind, function(frame) paintOne(e, kind, frame, rowInfo[frame]) end) end
    end
end
Report.StartPainter = startPainter

-- The named parts of a frame of an opened kind, or nil.
function API.Parts(frame)
    if type(frame) ~= "table" then return nil end
    for kind, get in pairs(partsOf) do
        local m = made[kind]
        if m and m[frame] ~= nil then
            local ok, parts = pcall(get, frame)
            if ok and type(parts) == "table" then return parts end
            return nil
        end
    end
    return nil
end

-- Lookups (real frames only, never previews)

local function lookup(kind, unit)
    if type(unit) ~= "string" then return nil end
    local u = byUnit[kind]
    return u and u[unit] or nil
end

-- Visible now (our own frames, so a plain read).
local function shown(f)
    local v = f:IsVisible()
    return not issecretvalue(v) and v == true
end

-- A frame of kind showing unit: the visible one first when wantShown is set
-- (a hidden header's tile can keep a stale unit), else any. byUnit holds the
-- last one reported; another with the same unit is found by walking.
local function find(kind, unit, wantShown)
    if type(unit) ~= "string" then return nil end
    local f = lookup(kind, unit)
    if f and (not wantShown or shown(f)) then return f end
    local l = live[kind]
    if not l then return nil end
    for frame, tok in pairs(l) do
        if tok == unit and frame ~= f and (not wantShown or shown(frame)) then return frame end
    end
    if not wantShown then return f end
end

-- "player" in a raid: the tile whose unit is you. UnitIsUnit is secret in a
-- PvP match or restricted map, so then only a tile that is literally "player".
local function playerTile(wantShown)
    local l = live.raid
    if not l then return nil end
    for frame, tok in pairs(l) do
        if type(tok) == "string" and (not wantShown or shown(frame)) then
            local same = UnitIsUnit("player", tok)
            if not issecretvalue(same) and same then return frame end
        end
    end
end

-- LibGetFrame-style lookup: a visible raid tile for that unit, else a party
-- tile, else our own frame for it (player, target, focus...), else a party
-- pet. If none is visible, the same order including hidden ones.
local ORDER = { "raid", "party", "player", "unit", "partypet" }
function API.GetUnitFrame(unit)
    if type(unit) ~= "string" then return nil end
    for pass = 1, 2 do
        local wantShown = pass == 1
        for _, kind in ipairs(ORDER) do
            local f
            if kind == "player" then
                if unit == "player" then f = playerTile(wantShown) end
            else
                f = find(kind, unit, wantShown)
            end
            if f then return f end
        end
    end
end

function API.GetNameplate(unit)
    return lookup("nameplate", unit)
end

-- bar is its number (1-8) or its key in ActionBars' Bars.DEFS (same names;
-- tests/test_api_frames.lua checks they match).
local BAR_NUM = { main = 1, bar2 = 2, left = 3, right = 4, bar5 = 5, bar6 = 6, bar7 = 7, bar8 = 8 }
function API.GetActionButton(bar, i)
    if bar == nil or i == nil then return nil end
    bar = BAR_NUM[bar] or bar
    return lookup("actionbutton", tostring(bar) .. ":" .. tostring(i))
end

-- A bar's holder (1.5): its number 1-8 or any key in Bars.DEFS ("stance",
-- "pet", "possess", "totem" too).
local BAR_KEY = {}
for key, n in pairs(BAR_NUM) do BAR_KEY[n] = key end
function API.GetActionBar(bar)
    if bar == nil then return nil end
    return lookup("actionbar", BAR_KEY[bar] or tostring(bar))
end

-- What one of the bars' buttons shows and how it reads right now (1.5): the
-- same table its paint gets. Nil for anything else.
function API.ButtonInfo(button)
    local m, fn = made.actionbutton, infoOf.actionbutton
    if type(button) ~= "table" or not (m and m[button] ~= nil) or not fn then return nil end
    local ok, info = pcall(fn, button)
    return ok and info or nil
end

local function barsNs()
    local mod = DUI:GetModule("ActionBars")
    return mod and mod.enabled and mod.ns or nil
end

-- Opens the game's key binding mode on the bars (1.5), as the Action Bars
-- page's Bind keys button does. False in a fight or with the bars off.
function API.BindKeys()
    local ns = barsNs()
    if not (ns and ns.Keys and ns.Keys.OpenQuick) then return false end
    return ns.Keys.OpenQuick() == true
end

-- The Cooldown Manager's glow (1.5) on one of Daylight UI's frames: the game's
-- proc ring, easing in and out. It sits on the frame's API.Attach holder, so
-- it never fights Daylight UI's own glows. r, g, b: its color, else the accent.
function API.Glow(frame, on, r, g, b)
    local ns = barsNs()
    local Fx = ns and ns.CdmEffects
    if not (Fx and Fx.SetGlow) then return false end
    local h = API.Attach(frame)
    if not h then return false end
    local c = type(r) == "number" and type(g) == "number" and type(b) == "number" and { r, g, b } or nil
    Fx.SetGlow(h, on == true, c)
    return true
end

-- The damage meter (1.6). Window ids are the Meters page's: "main" (the
-- panel's meter), "threat", and "w<n>" for the player's own windows.
local function panelNs()
    local mod = DUI:GetModule("InfoPanel")
    return mod and mod.enabled and mod.ns or nil
end

function API.MeterWindows()
    local ns = panelNs()
    local out = {}
    if not (ns and ns.Windows) then return out end
    for _, e in ipairs(ns.Windows.List()) do
        out[#out + 1] = { id = e.id, kind = e.kind or "meter", name = ns.Windows.Name(e),
                          mode = type(e.cfg) == "table" and e.cfg.mode or nil }
    end
    return out
end

function API.GetMeterWindow(id)
    local ns = panelNs()
    if not ns or type(id) ~= "string" then return nil end
    local h = ns.MeterFrame and ns.MeterFrame.hosts[id]
    if h and not h.dead then return h.frame end
    if id == "main" and ns.Meter then return ns.Meter.Area() end
end

-- What a meter window shows now, in its order: { rank, name, class, amount,
-- perSecond, isMine, guid, mode, window, sample } each. Names and amounts can
-- be secret in a fight. Nil for a window that isn't a meter.
function API.MeterRows(id)
    local ns = panelNs()
    if not (ns and ns.Meter) then return nil end
    return ns.Meter.Read(type(id) == "string" and id or "main")
end

function API.MeterModes()
    local ns = panelNs()
    local out = {}
    if not (ns and ns.Meter) then return out end
    for _, md in ipairs(ns.Meter.MODES) do
        out[#out + 1] = { key = md.key, name = L[md.name], group = md.group }
    end
    return out
end

-- Switches a meter window to another mode ("damage", "dps", "healing"...),
-- as its header's menu does. True when it did.
function API.SetMeterMode(id, mode)
    local ns = panelNs()
    if not (ns and ns.Meter and ns.Windows) or type(id) ~= "string" then return false end
    local known = false
    for _, md in ipairs(ns.Meter.MODES) do if md.key == mode then known = true end end
    local e = known and ns.Windows.Get(nil, id)
    if not (e and (e.kind or "meter") == "meter" and e.path) then return false end
    DUI:Set("InfoPanel", e.path .. ".mode", mode)
    return true
end

-- Clears every fight, as the meter's reset button does (without asking).
function API.ResetMeters()
    local ns = panelNs()
    if not (ns and ns.Meter) then return false end
    ns.Meter.ResetAll()
    return true
end

-- Opens the breakdown window (spells, targets, deaths) for the player at
-- rank in a meter window, as a click on their row does.
function API.OpenMeterBreakdown(id, rank)
    local ns = panelNs()
    local m = ns and ns.Meter and ns.Meter.ViewOf(type(id) == "string" and id or "main")
    if not (m and ns.BreakdownWindow and type(rank) == "number") then return false end
    local sources = m.Sources()
    local src = type(sources) == "table" and sources[rank]
    if not src then return false end
    ns.BreakdownWindow.Open(m, src)
    return true
end

-- A visible shop tile: tab "buy" or "buyback", and the game's index there.
function API.GetShopTile(tab, index)
    if (tab ~= "buy" and tab ~= "buyback") or type(index) ~= "number" then return nil end
    return lookup("shoptile", tab .. ":" .. index)
end

-- What a shop tile shows: tab ("buy" | "buyback"), index (the game's, for
-- GetMerchantItemInfo / GetBuybackItemInfo), itemID (nil when the game hasn't
-- provided it yet), link. Nil for anything else.
function API.ShopItem(frame)
    local m = made.shoptile
    if type(frame) ~= "table" or not (m and m[frame] ~= nil) then return nil end
    local t = rowInfo[frame]
    if type(t) ~= "table" then return nil end
    return t.tab, t.index, t.id, t.link
end

-- The quest tracker's row for a quest, while visible.
function API.GetQuestRow(questID)
    if type(questID) ~= "number" then return nil end
    local u = byUnit.questrow
    return u and u[questID] or nil
end

-- The profession window's line for a recipe, while visible.
function API.GetCraftRow(recipeID)
    if type(recipeID) ~= "number" then return nil end
    local u = byUnit.craftrow
    return u and u[recipeID] or nil
end

-- for frame, unit in API.Frames("raid") do ... end
function API.Frames(kind)
    local l = type(kind) == "string" and live[kind]
    local frames, units, n, i = {}, {}, 0, 0
    if l then
        for frame, unit in pairs(l) do
            n = n + 1
            frames[n], units[n] = frame, unit
        end
    end
    return function()
        i = i + 1
        if i <= n then return frames[i], units[i] end
    end
end

-- Settings and modules

-- Read only, through DUI:Get (nil for a module that's off).
function API.GetSetting(scope, path)
    if type(scope) ~= "string" or type(path) ~= "string" then return nil end
    return DUI:Get(scope, path)
end

function API.IsModuleEnabled(name)
    local mod = type(name) == "string" and DUI:GetModule(name)
    return mod and mod.enabled and true or false
end

-- Fitting in: our look for other addons. All wrappers, each reading the
-- player's font, accent and sizes when called, never cached.

local HOLDER = "__duiApiHolder"

-- A plain child of our frame, above our art, to draw on. Created once and the
-- same one returned every call. It isn't protected, so it can be created on a
-- secure tile in combat too (the game allows a plain child of a protected
-- frame, and nothing here moves, shows or resizes the tile). Only for our own
-- frames (ones the reporters know, previews included). A game frame or
-- another addon's gets nothing, so no field of ours is ever written on it
-- (taint).
local function isOurs(frame)
    for _, m in pairs(made) do
        if m[frame] ~= nil then return true end
    end
    return false
end

function API.Attach(frame)
    if type(frame) ~= "table" or not isOurs(frame) then return nil end
    local h = rawget(frame, HOLDER)
    if h then return h end
    h = CreateFrame("Frame", nil, frame)
    h:SetAllPoints(frame)
    h:SetFrameLevel(frame:GetFrameLevel() + 20)
    frame[HOLDER] = h
    return h
end

-- One named piece of a frame of an opened kind (1.2; API.Parts returns all of them).
function API.GetPart(frame, part)
    if type(part) ~= "string" then return nil end
    local parts = API.Parts(frame)
    local p = parts and parts[part]
    return type(p) == "table" and p or nil
end

-- Selects a recipe in the profession window (highlighted in the list,
-- scrolled into view, shown on the right). True when it worked: the window is
-- open on your own profession and the recipe is learned.
function API.SelectCraftRecipe(recipeID)
    local Craft = DUI.Craft and DUI.Craft.Window
    if type(recipeID) ~= "number" or type(Craft) ~= "table" or type(Craft.Select) ~= "function" then return false end
    return Craft.Select(recipeID) == true
end

-- The profession window's open profession as skillLine, name; nil while closed.
function API.GetCraftProfession()
    local Craft = DUI.Craft and DUI.Craft.Window
    if type(Craft) ~= "table" or type(Craft.Current) ~= "function" then return nil end
    return Craft.Current()
end

-- Style.Shell with a copy of the caller's opts (a shell writes into its own).
function API.Skin(frame, opts)
    local copy
    if type(opts) == "table" then
        copy = {}
        for k, v in pairs(opts) do copy[k] = v end
    end
    return DUI.Style.Shell(frame, copy)
end

-- size: "tiny" "small" "body" "head" "title"; anything else is "body".
function API.Text(parent, size, justify)
    local Style = DUI.Style
    return Style.Text(parent, Style.SIZE[size] or Style.SIZE.body, justify)
end

function API.Bar(parent)
    local bar = DUI.Style.Bar(parent)
    DUI.Style.SetBarGradient(bar, true)
    return bar
end

function API.Button(...) return DUI.Widgets.Button(...) end
function API.Close(...) return DUI.Widgets.Close(...) end
function API.Switch(...) return DUI.Widgets.Switch(...) end
function API.Input(...) return DUI.Widgets.Input(...) end
function API.Menu(...) return DUI.Widgets.OpenMenu(...) end

function API.Accent() return DUI.Style.Accent() end

local INK_KEYS = { "TITLE", "VALUE", "TEXT", "LABEL", "OFF", "GOOD", "WARN", "BAD", "DAMAGE", "MONEY" }
function API.Colors()
    local ink, out = DUI.Style.INK, {}
    for _, k in ipairs(INK_KEYS) do
        local c = ink[k]
        if c then out[k] = { c[1], c[2], c[3] } end
    end
    return out
end

function API.Font() return DUI.Style.FONT end

-- An options row that picks a font, each shown in its own face (1.2), the
-- same picker Daylight UI's own pages use. Its value is a font key, with
-- "general" meaning the player's font; API.FontFile turns it into a path. For
-- AddOptionsGroup or a module's own pages (default "general").
function API.FontRow(key, label, desc)
    if type(key) ~= "string" or type(label) ~= "string" then return nil end
    return DUI.Options.MediaPick("font", key, label, type(desc) == "string" and desc or nil)
end

function API.FontFile(key)
    if type(key) ~= "string" or key == DUI.Media.GENERAL then return DUI.Style.FONT end
    return DUI.Style.FontFileOf(key)
end

function API.ClassColor(token) return DUI.Style.ClassColor(token) end

API.Speed = { FAST = DUI.Motion.FAST, NORMAL = DUI.Motion.NORMAL, SLOW = DUI.Motion.SLOW }

-- Eases a region of yours to toAlpha. speed is a number or "FAST"/"NORMAL"/"SLOW".
-- Stepped from its current alpha (Motion.AlphaTo, no animation group). A
-- hidden region only gets its alpha set; we never show it (it may be protected).
function API.Fade(region, toAlpha, speed)
    if type(region) ~= "table" or type(toAlpha) ~= "number" then return end
    local Motion = DUI.Motion
    -- Only names from API.Speed, since any other key of Motion is a function.
    local dur = type(speed) == "number" and speed or API.Speed[speed] or Motion.NORMAL
    if not region:IsShown() then
        region:SetAlpha(toAlpha)
        return
    end
    Motion.AlphaTo(region, toAlpha, dur)
end

-- Named things. API.For(name) returns a view tied to a plugin's (or addon's)
-- name. Everything it creates is namespaced by it ("plugin.<name>.<key>") and
-- its errors carry the name.

local views = {}
local pending = {} -- pageId -> groups held until the page exists { group, after, name }

local function chat(fmt, ...) DUI.Print(string.format(fmt, ...)) end

-- Runs a plugin's function under its name. An error is reported (named, with
-- the core's one-report-per-error count) and returns nil so it can't stop the
-- caller. Returns ok, then fn's first result. No closure per call, since a
-- fade's wake and cap run every tick.
local box
local function keep(fn, ...) box = fn(...) end
local function callAs(name, fn, ...)
    box = nil
    local ok = DUI.SafeCallAs(name, keep, fn, ...)
    local r = box
    box = nil
    return ok, r
end

-- A plugin's options row, reading and writing its key in scope.
local function pluginRow(src, scope)
    local item = {}
    for k, v in pairs(src) do item[k] = v end
    item.anySize = true -- the Raid 20/40 "follows Raid 10" lock doesn't apply to these
    local function getter(key) return DUI:Get(scope, key) end
    -- Only wrapped when they're functions; anything else is left for
    -- Options.Validate to reject.
    if type(src.disabled) == "function" then item.disabled = function() return src.disabled(getter) end end
    if type(src.hidden) == "function" then item.hidden = function() return src.hidden(getter) end end
    if src.type ~= "button" and src.type ~= "text" and src.type ~= "custom" and not src.get and type(src.key) == "string" then
        local key, default = src.key, src.default
        item.key = nil
        item.get = function()
            local v = DUI:Get(scope, key)
            if v == nil then
                if type(default) == "function" then return default() end
                return default
            end
            return v
        end
        item.set = function(v) return DUI:Set(scope, key, v) end
        item.default = function()
            if type(default) == "function" then return default() end
            return default
        end
    end
    return item
end

-- Puts a plugin's group on its page (once). True when it was placed.
local function placeGroup(pageId, entry)
    local page = DUI.Options.GetPage(pageId)
    if not page then return false end
    local scope = str(entry.group.scope) or entry.name
    if not DUI:GetModule(scope) then
        -- Our pages are built before a plugin's addon loads (and registers its
        -- module), so until login it waits. At login it's placed or rejected.
        if not DUI.loggedIn then return false end
        entry.done = true
        DUI.Print(string.format(L["%s: its options need a module called %s."], entry.name, scope))
        return true
    end
    entry.done = true
    local card = {}
    for k, v in pairs(entry.group) do card[k] = v end
    card.tab = nil -- never starts a tab of the page
    card.label = string.format("%s - %s", tostring(entry.group.label or ""), string.format(L["From %s"], entry.name))
    local items = {}
    for i, src in ipairs(entry.group.items or {}) do
        -- Validated like our own pages' rows (Options.Validate). A bad one is left
        -- out with one line in chat so it can't break the page.
        local item, bad
        if type(src) ~= "table" then
            bad = L["not a table"]
        else
            item = pluginRow(src, scope)
            bad = DUI.Options.Validate({ item }, {}, {}, "")[1]
            if bad then bad = string.match(bad, "^%[1%]: (.*)$") or bad end
        end
        if bad then
            DUI.Print(string.format(L["%s: options row %d left out (%s)."], entry.name, i, bad))
        else
            items[#items + 1] = item
        end
    end
    card.items = items
    local at = #page.groups + 1
    if type(entry.after) == "string" then
        for i, g in ipairs(page.groups) do
            if g.label == entry.after then at = i + 1 break end
        end
    end
    table.insert(page.groups, at, card)
    DUI.Fire("OptionsChanged")
    return true
end

-- Each page's waiting list is taken out first (placing fires OptionsChanged,
-- which re-enters here), placed in arrival order, and whatever didn't land
-- goes back in front of anything queued meanwhile.
local function placePending()
    local ids = {}
    for pageId in pairs(pending) do ids[#ids + 1] = pageId end
    for _, pageId in ipairs(ids) do
        local list = pending[pageId]
        pending[pageId] = nil
        local left = {}
        for _, entry in ipairs(list or {}) do
            -- Each runs under its plugin's name, so one that errors is reported and
            -- dropped without taking other plugins' waiting groups with it.
            if not entry.done then
                local ok, landed = callAs(entry.name, placeGroup, pageId, entry)
                if ok and not landed then left[#left + 1] = entry end
            end
        end
        if #left > 0 then
            local more = pending[pageId]
            if more then for _, e in ipairs(more) do left[#left + 1] = e end end
            pending[pageId] = left
        end
    end
end

DUI.On("OptionsChanged", function() if next(pending) then placePending() end end)
DUI.On("Login", function() if next(pending) then placePending() end end)

local View = {}

function API.For(name)
    if not str(name) then return nil end
    local v = views[name]
    if not v then
        v = { name = name }
        for fname, fn in pairs(View) do
            v[fname] = function(...) return fn(v, ...) end
        end
        views[name] = v
    end
    return v
end

local function prefixed(v, key) return "plugin." .. v.name .. "." .. tostring(key) end

-- Something the fade engine can paint and check the mouse against: a region.
local function isRegion(f)
    return type(f) == "table" and type(f.SetAlpha) == "function" and type(f.IsShown) == "function"
        and type(f.GetLeft) == "function"
end

-- RegisterMover and RegisterFade return true once registered, false when
-- rejected (bad arguments) or on error (reported under the plugin's name).
-- Movers.Register and Fade.Register return nothing else.
function View.RegisterMover(v, frame, key, label, default)
    if type(frame) ~= "table" or not str(key) then return false end
    return DUI.SafeCallAs(v.name, DUI.Movers.Register, frame, prefixed(v, key), label, default)
end

function View.RegisterFade(v, def)
    if type(def) ~= "table" or not str(def.key) then return false end
    local name = v.name
    local copy = {}
    for k, val in pairs(def) do copy[k] = val end
    copy.key = prefixed(v, def.key)
    -- The engine steps every area in one loop each tick. The plugin's functions
    -- run guarded and only regions from its list are passed on (a cached table,
    -- as the engine expects), so a plugin's bug stays its own.
    local frames, wake, cap, paint = def.frames, def.wake, def.cap, def.paint
    if type(frames) == "function" then
        local list, warned = {}, false
        copy.frames = function()
            local ok, got = callAs(name, frames)
            local n = 0
            if ok and type(got) == "table" then
                for _, f in ipairs(got) do
                    if isRegion(f) then
                        n = n + 1
                        list[n] = f
                    elseif not warned then
                        warned = true
                        chat(L["%s: fade %s left out something that isn't a frame."], name, tostring(def.key))
                    end
                end
            end
            for i = #list, n + 1, -1 do list[i] = nil end
            return list
        end
    end
    if type(wake) == "function" then
        copy.wake = function() local ok, r = callAs(name, wake); return ok and r or nil end
    end
    if type(cap) == "function" then
        copy.cap = function() local ok, r = callAs(name, cap); return ok and r or nil end
    end
    if type(paint) == "function" then
        copy.paint = function(f, a) callAs(name, paint, f, a) end
    end
    return DUI.SafeCallAs(name, DUI.Fade.Register, copy)
end

function View.RegisterTestPart(v, key, label, available)
    if not str(key) then return end
    -- Asked when /dui test lists its checkboxes. Guarded; an error leaves it out.
    local asked
    if type(available) == "function" then
        local name = v.name
        asked = function()
            local ok, r = callAs(name, available)
            if not ok then return false end
            return r
        end
    end
    DUI.RegisterTestPart(prefixed(v, key), label, 2000, asked)
    return true
end

function View.RegisterCommand(v, word, fn, help)
    if not str(word) or type(fn) ~= "function" then return end
    word = string.lower(word)
    if DUI.HasCommand(word) then
        chat(L["%s: /dui %s is already taken."], v.name, word)
        return false
    end
    local name = v.name
    DUI.RegisterCommand(word, function(rest) DUI.SafeCallAs(name, fn, rest) end, help)
    return true
end

-- Pages that rebuild their groups from scratch (a plugin's group would vanish).
local OWN_GROUPS = { plugins = true, profiles = true, gradients = true }

-- group = { label, desc?, items }. Rows with a key store it in the plugin's
-- own settings. A page that doesn't exist yet (module off, not built) gets it
-- when it appears. after is the label of a group on that page to follow.
function View.AddOptionsGroup(v, pageId, group, after)
    if not str(pageId) or type(group) ~= "table" or type(group.items) ~= "table" then return false end
    if OWN_GROUPS[pageId] then
        chat(L["%s: the %s page makes its own groups and takes none from plugins."], v.name, pageId)
        return false
    end
    local entry = { group = group, after = after, name = v.name }
    local ok, landed = callAs(v.name, placeGroup, pageId, entry)
    if not ok then return false end
    if not landed then
        local list = pending[pageId]
        if not list then list = {}; pending[pageId] = list end
        list[#list + 1] = entry
    end
    return true
end

-- Skins another addon's window in our look when that addon loads: fn(Kit)
-- runs once it's there (return false to be called again as more addons
-- load). This is the Skins engine's third-party kind: an error in fn names
-- the addon once in chat and stops it, and the player can't turn it off
-- separately. False when the Skins module isn't present. A plugin the game
-- loads before DaylightUI_Skins (name sorts first) has its skin held until
-- Skins loads.
local SKINS_ADDON = "DaylightUI_Skins"
local skinKeys = {}
local skinsWaiting = {} -- defs held until Skins loads

local function skinsReady()
    local Skins = DUI.Skins
    return type(Skins) == "table" and type(Skins.Register) == "function" and Skins or nil
end

-- Installed, enabled for this character and not loaded yet.
local function skinsComing()
    local api = C_AddOns
    if type(api) ~= "table" then return false end
    if api.IsAddOnLoaded and api.IsAddOnLoaded(SKINS_ADDON) then return false end
    if not (api.DoesAddOnExist and api.DoesAddOnExist(SKINS_ADDON)) then return false end
    return DUI.InstallerPages.EnabledFor(SKINS_ADDON) == true
end

local function registerWaiting()
    local Skins = skinsReady()
    if not Skins or #skinsWaiting == 0 then return end
    local list = skinsWaiting
    skinsWaiting = {}
    for _, def in ipairs(list) do Skins.Register(def) end
end

DUI.RegisterEvent("ADDON_LOADED", function(_, name) if name == SKINS_ADDON then registerWaiting() end end)
DUI.On("Login", registerWaiting)

function View.RegisterSkin(v, addon, fn)
    if not str(addon) or type(fn) ~= "function" then return false end
    local key = prefixed(v, addon)
    if skinKeys[key] then return true end
    local Skins = skinsReady()
    local def = { key = key, addon = addon, label = addon, apply = fn }
    if Skins then
        skinKeys[key] = true
        Skins.Register(def)
        return true
    end
    if not skinsComing() then return false end
    skinKeys[key] = true
    skinsWaiting[#skinsWaiting + 1] = def
    return true
end

-- A plugin panel docked to the profession window's right edge (1.2). It moves,
-- scales, opens and closes with the window, uses the window's shell, and the
-- game's windows beside it make room for it. One per plugin (the same frame
-- each call; a new width is applied). Never shown when Daylight UI's
-- profession window isn't in use (turned off, or DaylightMogul's instead).
function View.AttachCraftPane(v, width)
    if type(width) ~= "number" or width <= 0 then return nil end
    local Craft = DUI.Craft and DUI.Craft.Window
    if type(Craft) ~= "table" or type(Craft.Pane) ~= "function" then return nil end
    return Craft.Pane(v.name, width)
end

function View.On(v, event, fn) return API.On(event, fn, v.name) end

function View.Paint(v, kind, fn, opts)
    local h = Report.StartPainter(v.name, kind, fn, opts)
    if h then Report.Count(v.name, "paints", kind) end
    return h
end

-- What each plugin changes (shown on the Plugins page), counted as it asks.

local changes = {} -- name -> { paints = { kind = n }, hooks = n, texts = n, defaults = n }
local changeOrder = {}

function Report.Count(name, what, kind, by)
    local c = changes[name]
    if not c then
        c = { paints = {}, hooks = 0, texts = 0, defaults = 0 }
        changes[name] = c
        changeOrder[#changeOrder + 1] = name
    end
    by = by or 1
    if what == "paints" then c.paints[kind] = math.max(0, (c.paints[kind] or 0) + by)
    else c[what] = math.max(0, (c[what] or 0) + by) end
    if DUI.Fire then DUI.Fire("PluginsChanged") end
end

function Report.Changes(name) return changes[name] end
-- Every name that changed something, in the order they first did.
function Report.Changers() return changeOrder end

-- Named hooks (1.3): me.Hook(tbl, "Fn", after), me.Wrap(tbl, "Fn",
-- fn(original, ...)), me.Unhook(handle). Only on Daylight UI's own tables (the
-- core, a module's ns, or a table inside either), never a frame and never the
-- game's. Several plugins on one function all keep working, each runs under
-- its own name, and a wrap that errors falls back to Daylight UI's own.

local hooked = {} -- tbl -> name -> { orig, wraps = {}, afters = {}, fn }

local function pk(...) return { n = select("#", ...), ... } end

local function isWidget(t)
    local ok, got = pcall(function() return t.GetObjectType end)
    return not ok or type(got) == "function"
end

-- Daylight UI's own: the core table, a module's ns, or a table one or two
-- levels inside either.
local function ours(tbl)
    if type(tbl) ~= "table" or tbl == _G or isWidget(tbl) then return false end
    local roots = { DUI }
    for _, mod in DUI.Modules() do
        if type(mod.ns) == "table" then roots[#roots + 1] = mod.ns end
    end
    for _, root in ipairs(roots) do
        if root == tbl then return true end
        for _, a in pairs(root) do
            if a == tbl then return true end
            if type(a) == "table" and not isWidget(a) then
                for _, b in pairs(a) do if b == tbl then return true end end
            end
        end
    end
    return false
end

local function reportAs(owner, err)
    DUI.SafeCallAs(owner, function() error(err, 0) end)
end

-- The call chain, innermost first: Daylight UI's function, then each wrap
-- around the previous one.
local function rebuild(rec)
    local call = rec.orig
    for _, w in ipairs(rec.wraps) do
        local inner, fn, owner = call, w.fn, w.owner
        call = function(...)
            local ran, out, failed, err = false, nil, false, nil
            -- Daylight UI's own function. Its error is its own and is re-raised
            -- unchanged, never blamed on the wrap around it.
            local function once(...)
                ran = true
                local r = pk(pcall(inner, ...))
                if not r[1] then
                    failed, err = true, r[2]
                    error(r[2], 0)
                end
                out = pk(unpack(r, 2, r.n))
                return unpack(out, 1, out.n)
            end
            local r = pk(pcall(fn, once, ...))
            if r[1] then return unpack(r, 2, r.n) end
            if failed then error(err, 0) end
            reportAs(owner, r[2])
            if ran and out then return unpack(out, 1, out.n) end
            return inner(...)
        end
    end
    rec.call = call
end

-- Never hookable: the error reporting every hook runs through (it would call itself).
local NEVER = { SafeCall = true, SafeCallAs = true }

local function addHook(v, tbl, name, fn, kind)
    if type(name) ~= "string" or type(fn) ~= "function" then return false end
    if tbl == DUI and NEVER[name] then
        chat(L["%s: only Daylight UI's own functions can be hooked, not %s."], v.name, name)
        return false
    end
    if not ours(tbl) then
        chat(L["%s: only Daylight UI's own functions can be hooked, not %s."], v.name, tostring(name))
        return false
    end
    local byName = hooked[tbl]
    local rec = byName and byName[name]
    if not rec then
        local orig = rawget(tbl, name)
        if type(orig) ~= "function" then return false end
        rec = { orig = orig, wraps = {}, afters = {} }
        rec.fn = function(...)
            local out = pk(rec.call(...))
            local afters = rec.afters
            rec.firing = (rec.firing or 0) + 1
            for i = 1, #afters do
                local a = afters[i]
                if a and not a.dead then DUI.SafeCallAs(a.owner, a.fn, ...) end
            end
            rec.firing = rec.firing - 1
            if rec.firing == 0 and rec.dirty then rec.tidy() end
            return unpack(out, 1, out.n)
        end
        -- Hooks removed mid-call are only marked, and cleaned up once the call is over.
        rec.tidy = function()
            rec.dirty = nil
            for i = #rec.afters, 1, -1 do if rec.afters[i].dead then table.remove(rec.afters, i) end end
            if #rec.wraps == 0 and #rec.afters == 0 and hooked[tbl] and hooked[tbl][name] == rec then
                hooked[tbl][name] = nil
                if rawget(tbl, name) == rec.fn then tbl[name] = rec.orig end
            end
        end
        if not byName then byName = {}; hooked[tbl] = byName end
        byName[name] = rec
        rebuild(rec)
        tbl[name] = rec.fn
    end
    local e = { fn = fn, owner = v.name, kind = kind, tbl = tbl, name = name, hook = true }
    if kind == "wrap" then
        rec.wraps[#rec.wraps + 1] = e
        rebuild(rec)
    else
        rec.afters[#rec.afters + 1] = e
    end
    Report.Count(v.name, "hooks")
    return e
end

function View.Hook(v, tbl, name, after) return addHook(v, tbl, name, after, "after") end

-- Plugin settings on our modules (1.3): me.AddDefaults(module, tbl) adds new
-- top-level keys to a module's defaults (never one it already has), saved and
-- stripped like ours. DB.PluginKeys records their owner. A module not on yet
-- picks them up when it turns on (Core.lua's EnableModule).

local waitingDefaults = {} -- module -> list of { owner, tbl }

local function clashes(defaults, tbl)
    for k in pairs(tbl) do
        if defaults[k] ~= nil then return k end
    end
end

local function addDefaults(mod, owner, tbl)
    mod.defaults = mod.defaults or {}
    local bad = clashes(mod.defaults, tbl)
    if bad then
        chat(L["%s: %s already has a setting called %s."], owner, mod.name, tostring(bad))
        return false
    end
    local keys = DUI.DB.PluginKeys()
    keys[mod.name] = keys[mod.name] or {}
    local added = {}
    for k, v in pairs(tbl) do
        mod.defaults[k] = DUI.DB.Copy(v)
        added[k] = mod.defaults[k]
        keys[mod.name][k] = owner
    end
    if mod.enabled and type(mod.db) == "table" then DUI.DB.MergeDefaults(mod.db, added) end
    return true
end

function Report.ApplyDefaults(mod)
    local list = waitingDefaults[mod.name]
    if not list then return end
    waitingDefaults[mod.name] = nil
    for _, w in ipairs(list) do
        if not addDefaults(mod, w.owner, w.tbl) then Report.Count(w.owner, "defaults", nil, -1) end
    end
end

function View.AddDefaults(v, module, tbl)
    if type(module) ~= "string" or type(tbl) ~= "table" then return false end
    local mod = DUI:GetModule(module)
    local ok
    if mod and mod.enabled then
        ok = addDefaults(mod, v.name, tbl)
    else
        if mod and mod.defaults then
            local bad = clashes(mod.defaults, tbl)
            if bad then
                chat(L["%s: %s already has a setting called %s."], v.name, module, tostring(bad))
                return false
            end
        end
        local list = waitingDefaults[module] or {}
        waitingDefaults[module] = list
        list[#list + 1] = { owner = v.name, tbl = tbl }
        ok = true
    end
    if ok then Report.Count(v.name, "defaults") end
    return ok
end

-- Plugin texts on the unit frames (1.3): me.AddText(key, { label, on, events,
-- text = fn(unit, frame) -> text[, r, g, b], sample }). Saved as
-- "<name>:<key>". The unit frames pick them up as they load or right away
-- (TextsChanged); see Texts.AddKind in Texts.lua.

local texts, textOrder = {}, {}

function Report.Texts() return textOrder, texts end

function View.AddText(v, key, spec)
    if type(key) ~= "string" or key == "" or type(spec) ~= "table" or type(spec.label) ~= "string"
        or type(spec.text) ~= "function" then
        return false
    end
    local full = v.name .. ":" .. key
    if not texts[full] then textOrder[#textOrder + 1] = full end
    texts[full] = { key = full, owner = v.name, label = spec.label, on = spec.on, events = spec.events,
                    text = spec.text, sample = spec.sample }
    Report.Count(v.name, "texts")
    if DUI.Fire then DUI.Fire("TextsChanged", full) end
    return true
end
-- Data texts and data panels (1.6), the way ElvUI's DT:RegisterDatatext and
-- DT:RegisterPanel work: kept here, taken in by the Info Panel module (its
-- Broker.lua) as it enables and whenever one is added.
local dataTexts, dataOrder = {}, {}
local dataPanels, panelOrder = {}, {}
function Report.DataTexts() return dataOrder, dataTexts end
function Report.DataPanels() return panelOrder, dataPanels end

local function eventList(events)
    if type(events) == "string" then
        local out = {}
        for e in string.gmatch(events, "[%w_]+") do out[#out + 1] = e end
        return out
    end
    if type(events) ~= "table" then return nil end
    local out = {}
    for _, e in ipairs(events) do if type(e) == "string" then out[#out + 1] = e end end
    return out
end
local function fnOrNil(f) return type(f) == "function" and f or nil end

-- me.AddDataText(key, { label, text = fn() -> label, value, r, g, b, events,
-- onEvent, poll, tooltip = fn(tip), click = fn(button, slot), wheel, icon,
-- sample }). Players pick it in any data text slot. Saved as "<plugin>:<key>".
function View.AddDataText(v, key, spec)
    if type(key) ~= "string" or key == "" or type(spec) ~= "table" or type(spec.label) ~= "string"
        or type(spec.text) ~= "function" then
        chat(L["%s: a data text needs a key, a label and a text function."], v.name)
        return false
    end
    local full = v.name .. ":" .. key
    if not dataTexts[full] then dataOrder[#dataOrder + 1] = full end
    dataTexts[full] = {
        key = full, owner = v.name, label = spec.label, text = spec.text, events = eventList(spec.events),
        onEvent = fnOrNil(spec.onEvent), poll = spec.poll == true, tooltip = fnOrNil(spec.tooltip),
        click = fnOrNil(spec.click), wheel = fnOrNil(spec.wheel),
        icon = (type(spec.icon) == "string" or type(spec.icon) == "number" or type(spec.icon) == "function") and spec.icon or nil,
        sample = (type(spec.sample) == "string" or type(spec.sample) == "number") and spec.sample or nil,
    }
    Report.Count(v.name, "datatexts")
    if DUI.Fire then DUI.Fire("DataTextsChanged", full) end
    return true
end

-- Draws a data text again now (its value changed outside its events).
function View.UpdateDataText(v, key)
    if type(key) ~= "string" then return end
    if DUI.Fire then DUI.Fire("DataTextRedraw", v.name .. ":" .. key) end
end

-- me.AddDataPanel(key, frame, { count = 1-5, slots = { "gold", "MyAddon:fish" },
-- labels, icons, textSize }): data text slots on a frame of the plugin's.
function View.AddDataPanel(v, key, frame, spec)
    spec = type(spec) == "table" and spec or {}
    if type(key) ~= "string" or key == "" or not isRegion(frame) then
        chat(L["%s: a data panel needs a key and a frame."], v.name)
        return false
    end
    local full = v.name .. ":" .. key
    local slots = {}
    if type(spec.slots) == "table" then
        for i, k in ipairs(spec.slots) do if type(k) == "string" then slots[i] = k end end
    end
    local count = math.max(1, math.min(5, math.floor(tonumber(spec.count) or #slots)))
    if not dataPanels[full] then panelOrder[#panelOrder + 1] = full end
    local size = DUI.Style and DUI.Style.SIZE
    dataPanels[full] = {
        key = full, owner = v.name, frame = frame, count = count, slots = slots,
        labels = spec.labels ~= false, icons = spec.icons == true,
        textSize = type(spec.textSize) == "number" and spec.textSize or (size and size.small or 12),
    }
    Report.Count(v.name, "datapanels")
    if DUI.Fire then DUI.Fire("DataPanelsChanged", full) end
    return true
end

function View.Wrap(v, tbl, name, fn) return addHook(v, tbl, name, fn, "wrap") end

function View.Unhook(v, handle)
    if type(handle) ~= "table" or not handle.hook or handle.dead then return end
    handle.dead = true
    local byName = hooked[handle.tbl]
    local rec = byName and byName[handle.name]
    if not rec then return end
    Report.Count(handle.owner, "hooks", nil, -1)
    if handle.kind == "wrap" then
        for i = #rec.wraps, 1, -1 do if rec.wraps[i] == handle then table.remove(rec.wraps, i) end end
        rebuild(rec)
    end
    if (rec.firing or 0) > 0 then rec.dirty = true else rec.tidy() end
end

-- Passed on from the core (one DUI.On each, created at file load)

for _, name in ipairs(PASSED_ON) do
    DUI.On(name, function(a, b, c, d) fire(name, a, b, c, d) end)
end
