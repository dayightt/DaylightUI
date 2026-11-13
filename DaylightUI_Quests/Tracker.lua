-- The quest tracker. A fixed-size holder moved by the unlock handle (below the
-- info panel by default), a view that clips the list at the height limit, and the
-- list itself: one block per section header, zone name, quest and achievement,
-- each keyed by what it shows. Any change re-lays the list. Blocks that stay keep
-- their frame and glide to their new spot, and only what changed inside them
-- repaints (Rows). A block only slides in or out for a game reason (accepted,
-- turned in, untracked); one that appears because data arrived (login, a loading
-- screen) just appears.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style

local Tracker = {}
ns.Tracker = Tracker

Tracker.MOVER = "quests.tracker"
Tracker.HOLDER = { 226, 160 }     -- the handle; the list hangs from its top-right
Tracker.OLD_MOVER = "infopanel.tracker"
Tracker.OLD_W = 248               -- the info panel's handle width (its position is a CENTER)
Tracker.FALLBACK = { "TOPRIGHT", "UIParent", "TOPRIGHT", -24, -300 }
Tracker.BOX_PAD = { 8, 6 }        -- box padding around the list: sides, then top and bottom
Tracker.EVENTS = { "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
    "QUEST_REMOVED", "QUEST_AUTOCOMPLETE", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
    "CONTENT_TRACKING_UPDATE", "TRACKED_ACHIEVEMENT_UPDATE", "PLAYER_REGEN_ENABLED", "SUPER_TRACKING_CHANGED",
    "PLAYER_LEVEL_UP",    -- title difficulty colors depend on the player's level
    "UNIT_QUEST_LOG_CHANGED", "GROUP_ROSTER_UPDATE" }   -- which party members are on a quest
-- These can arrive in bursts (a whole raid turning in), so they wait and get one check.
Tracker.WAITS = { QUEST_LOG_UPDATE = true, UNIT_QUEST_LOG_CHANGED = true, GROUP_ROSTER_UPDATE = true }
-- Settings whose change re-lays the list with a fade instead of a jump.
Tracker.FADE_PATHS = { filter = true, instances = true, zoneNames = true, hideDone = true, sort = true, foldReady = true, emptyHeader = true }
Tracker.NEAR_EVERY = 5            -- seconds between nearest-first checks
Tracker.DIM = 0.5                 -- other quests' alpha while one is hovered

local db, holder, view, content, box
local frames, shown = {}, {}
local queued, wantAnimate = false, nil
Tracker.frames = frames
Tracker.shown = shown
Tracker.reasons = { enter = {}, leave = {}, far = {}, fold = false }

function Tracker.Folds()
    local c = DUI.DB.Character()
    if type(c.questFolds) ~= "table" then c.questFolds = {} end
    return c.questFolds
end

-- Most recent progress first: questID -> number, higher = progressed more
-- recently. Saved per character so the order survives a reload.
Tracker.RECENT_MAX = 25           -- entries kept; the oldest drop off past this
function Tracker.Recent()
    local c = DUI.DB.Character()
    if type(c.questRecent) ~= "table" then c.questRecent = {} end
    return c.questRecent
end

local function plain(v) return type(v) == "number" and not (issecretvalue and issecretvalue(v)) end
local function amount(ob)
    if ob.kind == "count" then return ob.have elseif ob.kind == "bar" then return ob.pct end
end

-- Each watched quest's progress at the last check (this session only; the first
-- check after login only records it).
local seen = {}
local function remember(q)
    local p = seen[q.id] or {}   -- reused, this runs on every quest update
    p.ready = q.state == "ready"
    for _, ob in ipairs(q.objs) do
        local o = p[ob.index] or {}
        o.v, o.done = amount(ob), ob.done
        p[ob.index] = o
    end
    return p
end
-- Progressed since then: ready to turn in, an objective done, a count or bar up.
local function movedOn(was, q)
    if q.state == "ready" and not was.ready then return true end
    for _, ob in ipairs(q.objs) do
        local old = was[ob.index]
        if old then
            if ob.done and not old.done then return true end
            local v = amount(ob)
            if plain(v) and plain(old.v) and v > old.v then return true end
        end
    end
    return false
end

function Tracker.NoteProgress(snap)
    local recent, top = Tracker.Recent(), 0
    for _, n in pairs(recent) do if plain(n) and n > top then top = n end end
    for _, g in ipairs(snap.groups) do
        for _, q in ipairs(g.quests) do
            local was = seen[q.id]
            if was and movedOn(was, q) then
                top = top + 1; recent[q.id] = top
                DUI.Fade.Wake("Quests.tracker")   -- in Float mode, progress brings the tracker back
            end
            seen[q.id] = remember(q)
        end
    end
    local n, oldest, oldestID = 0, math.huge, nil
    for id, v in pairs(recent) do
        n = n + 1
        if not plain(v) or v < oldest then oldest, oldestID = plain(v) and v or -1, id end
    end
    if n > Tracker.RECENT_MAX and oldestID then recent[oldestID] = nil end
end

function Tracker.ForgetProgress(id)
    Tracker.Recent()[id] = nil
    seen[id] = nil
end

function Tracker.Width()
    if db.matchMap and DUI:Get("InfoPanel", "map.enabled") == true then
        local w = DUI:Get("InfoPanel", "map.size")
        if type(w) == "number" and w > 0 then return w end
    end
    return db.width
end

function Tracker.Options()
    return { width = Tracker.Width(), sizes = db.sizes, zoneNames = db.zoneNames, compact = db.compact,
             hideDone = db.hideDone, filter = Tracker.ZoneOnly() and "zone" or db.filter, folds = Tracker.Folds(), caps = db.capsTitles,
             levels = db.questLevels, tags = db.questTags, party = db.questParty, sort = db.sort,
             recent = db.sort == "recent" and Tracker.Recent() or nil, near = Tracker.near,
             frozen = InCombatLockdown() and Tracker.order or nil,
             frozenZones = InCombatLockdown() and Tracker.zoneOrder or nil,
             foldReady = db.foldReady, emptyHeader = db.emptyHeader }
end

-- Only the current zone: the player's filter, or a dungeon's own view (instances
-- "zone", lasts for the visit and leaves the filter alone).
function Tracker.ZoneOnly()
    return db.filter == "zone" or DUI.DB.Character().questInstanceZone == true
end

-- Quests in the tracker, i.e. what the map symbols and the arrow call "tracked".
-- Read live from the game (the map redraws on a watch change before the list lays
-- out again): every log quest in "every quest in your log" mode, otherwise the
-- watch list (only this zone's, per the last layout).
local inTracker = {}
local function watched(id)
    local QL = C_QuestLog
    if not (QL and QL.GetNumQuestWatches) then return false end
    for i = 1, QL.GetNumQuestWatches() or 0 do
        if QL.GetQuestIDForQuestWatchIndex(i) == id then return true end
    end
    return false
end
function Tracker.Shown(id)
    local inList
    if Tracker.built and db.filter == "log" then
        local QL = C_QuestLog
        local i = QL and QL.GetLogIndexForQuestID and QL.GetLogIndexForQuestID(id)
        inList = type(i) == "number"
    else
        inList = watched(id)
    end
    if inList and Tracker.built and Tracker.ZoneOnly() then return inTracker[id] == true end
    return inList
end

-- Same thing as a list, in tracker order.
function Tracker.ShownIDs()
    local out = {}
    for _, b in ipairs(shown) do
        if b.kind == "quest" and inTracker[b.quest.id] then out[#out + 1] = b.quest.id end
    end
    for id in pairs(inTracker) do
        local seen = false
        for _, x in ipairs(out) do if x == id then seen = true; break end end
        if not seen then out[#out + 1] = id end
    end
    return out
end

local function inInstance()
    if type(IsInInstance) ~= "function" then return false end
    local inside, kind = IsInInstance()
    return inside == true and kind ~= "none"
end

-- Quest IDs nearest first as one string ("2<3=1", "=" is a tie that keeps the
-- watch order). Walking changes every distance but rarely this.
function Tracker.NearOrder(near)
    local ids = {}
    for id in pairs(near) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        if near[a] ~= near[b] then return near[a] < near[b] end
        return a < b
    end)
    local parts = {}
    for i, id in ipairs(ids) do
        parts[#parts + 1] = tostring(id)
        local nxt = ids[i + 1]
        if nxt then parts[#parts + 1] = near[nxt] == near[id] and "=" or "<" end
    end
    return table.concat(parts)
end

-- Nearest first: each shown quest's distance, checked every NEAR_EVERY seconds
-- (and when the sort is picked), never in combat or an instance. Only a new order
-- triggers a layout.
function Tracker.NearTick()
    if not Tracker.built or db.sort ~= "near" or InCombatLockdown() or inInstance() then return end
    local QL = C_QuestLog
    if not (QL and QL.GetDistanceSqToQuest) then return end
    local near = {}
    for id in pairs(inTracker) do
        local ok, d = pcall(QL.GetDistanceSqToQuest, id)
        if ok and plain(d) then near[id] = d end
    end
    local order = Tracker.NearOrder(near)
    local changed = Tracker.near == nil or order ~= Tracker.nearOrder
    Tracker.near, Tracker.nearOrder = near, order
    if changed then
        Tracker.reasons.fold = true
        Tracker.Queue(true)
    end
end

-- Dims the other quests while one is hovered (hoverDim). f nil restores them all.
function Tracker.HoverDim(f)
    if not Tracker.built then return end
    local on = f ~= nil and db.hoverDim == true
    local M = DUI.Motion
    for key, fr in pairs(frames) do
        if fr.kind == "quest" or fr.kind == "ach" then
            local to = (on and fr ~= f) and Tracker.DIM or 1
            local from = fr.dim or 1
            if from ~= to then
                M.Tween("quests:dim:" .. key, from, to, M.FAST, function(a) ns.Rows.Dim(fr, a) end)
            end
        end
    end
end

-- Which instance this is; every loading screen inside one checks.
local function instanceHere()
    if type(GetInstanceInfo) ~= "function" then return true end
    return select(8, GetInstanceInfo()) or true
end

-- Entering a dungeon or raid (a loading screen): show only this zone, fold, or
-- hide (instances setting), and restore on leaving. A fold made here is undone
-- here; one the player made is left alone. Happens once per visit
-- (questInstanceHere), so if opened by hand (All, the header) it stays open
-- through later loading screens inside. changed: the setting changed, start over.
function Tracker.CheckInstance(changed)
    if not Tracker.built then return end
    local inside, mode = inInstance(), db.instances
    local c = DUI.DB.Character()
    local folds = Tracker.Folds()
    local visit = inside and (mode == "zone" or mode == "fold")
    if changed or not visit then
        c.questInstanceHere, c.questInstanceZone = nil, nil
        if c.questInstanceFolded then
            folds.quests = nil
            c.questInstanceFolded = nil
        end
    end
    if visit then
        local here = instanceHere()
        if c.questInstanceHere ~= here then
            c.questInstanceHere = here
            if mode == "zone" then
                c.questInstanceZone = true
            elseif not folds.quests then
                folds.quests = true; c.questInstanceFolded = true
            end
        end
    end
    if Tracker.controls then Tracker.PaintControls() end
    local away = inside and mode == "hide"
    if away ~= (Tracker.instanceAway == true) then
        Tracker.instanceAway = away or nil
        Tracker.Follow()
    end
end

-- The list hangs down from the handle, or grows up from it (growUp).
function Tracker.Anchor()
    view:ClearAllPoints()
    if db.growUp then
        view:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
    else
        view:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
    end
end

-- The journal's tooltips and cards read this too, even when this tracker was
-- never built (Questie's picked), so fall back to the module settings.
function Tracker.Look()
    local d = db or Tracker.mod.db
    local look = ns.Look.Get(d)
    look.width = db and Tracker.Width() or d.width
    return look
end

-- Wrapped height of a text at a given size and width, from an invisible ruler
-- (kept shown at alpha 0, since a hidden FontString may not measure). Each render
-- measures every line, mostly the same texts again, so results are cached
-- (size -> width -> text -> height) until the font, a setting, the UI scale or a
-- loading screen could change them (Tracker.ForgetMeasures).
local ruler
local measured, measuredN = {}, 0
Tracker.MEASURE_KEEP = 1000       -- max cached texts; past this the cache starts over

function Tracker.ForgetMeasures()
    measured, measuredN = {}, 0
end

function Tracker.Measure(text, size, width)
    local plainText = not (issecretvalue and issecretvalue(text))
    local bySize = measured[size]
    local byWidth = bySize and bySize[width]
    local known = plainText and byWidth and byWidth[text]
    if known then return known end
    if not ruler then
        ruler = Style.Text(UIParent, 12, nil, ns.MEDIA.font)   -- measures in the tracker's font
        ruler:SetAlpha(0)
        ruler:SetWordWrap(true)
    end
    Style.SetTextSize(ruler, size)
    ruler:SetWidth(width)
    ruler:SetText(text)
    local h = ruler:GetStringHeight()
    h = type(h) == "number" and h or 0
    -- Only cache a real height for plain keys (a failed measure, e.g. before the font
    -- is ready, gets asked again next time).
    if plainText and not (issecretvalue and issecretvalue(h)) and type(text) == "string" and type(size) == "number" and type(width) == "number"
        and size == size and width == width and h > 0 then
        if measuredN >= Tracker.MEASURE_KEEP then Tracker.ForgetMeasures() end
        bySize = measured[size]
        if not bySize then
            bySize = {}
            measured[size] = bySize
        end
        byWidth = bySize[width]
        if not byWidth then
            byWidth = {}
            bySize[width] = byWidth
        end
        byWidth[text] = h
        measuredN = measuredN + 1
    end
    return h
end

local function questID(key) return tonumber(string.match(key, "^quest:(%d+)$")) end

function Tracker.EnterStyle(b, r)
    if b.kind == "quest" and r.enter[b.quest.id] then return "slide" end
    if r.fold then return "fade" end
    return nil
end

function Tracker.LeaveStyle(key, r)
    local id = questID(key)
    if id and r.far[id] then return "far" end
    if id and r.leave[id] then return "slide" end
    if r.fold then return "fade" end
    return nil
end

function Tracker.Arrive(f, b, style)
    if style == "slide" then ns.Animate.Enter(f, b.y)
    elseif style == "fade" then ns.Animate.FadeIn(f, b.y)
    else ns.Animate.Jump(f, b.y, 0, 1) end
end

-- Login reveal (Fade.Reveal): the list's lines slide in one after another as the
-- ripple reaches them, like a new quest does. The whole cascade starts within
-- LOGIN_SPREAD seconds. If combat starts first, every line still waiting just
-- lands in place (nothing moves under the item buttons in combat).
Tracker.LOGIN_STEP = 0.05
Tracker.LOGIN_SPREAD = 0.6
function Tracker.LoginReveal()
    if not (holder and holder:IsVisible() and DUI.Motion.On()) then return end
    local A = ns.Animate
    local at = DUI.Fade.RippleDelay(holder) or 0
    local rows = {}
    for _, b in ipairs(shown) do
        local f = frames[b.key]
        if f then
            rows[#rows + 1] = { key = b.key, f = f }
            A.Jump(f, b.y, A.ENTER_DX, 0)
        end
    end
    local step = #rows > 1 and math.min(Tracker.LOGIN_STEP, Tracker.LOGIN_SPREAD / (#rows - 1)) or 0
    for i, r in ipairs(rows) do
        C_Timer.After(at + (i - 1) * step, function()
            if frames[r.key] ~= r.f then return end   -- gone or recreated since, it already came in its own way
            local y = A.State(r.f).y
            if InCombatLockdown() then A.Jump(r.f, y) else A.Enter(r.f, y) end
        end)
    end
end
DUI.On("LoginReveal", function() Tracker.LoginReveal() end)

function Tracker.Drop(f, style)
    local function gone(fr)
        ns.Animate.Forget(fr)
        ns.Rows.Free(fr)
    end
    if style == "slide" or style == "far" then ns.Animate.Leave(f, gone, style == "far")
    elseif style == "fade" then ns.Animate.FadeOut(f, gone)
    else gone(f) end
end

-- Soft chime (Media/sounds/shh-quest3.ogg); toggled under General > Sound.
function Tracker.OnReady()
    if db.sound and DaylightUI.Sound then DaylightUI.Sound.Play("quest") end
end

function Tracker.FitBox(h)
    if not box then return end
    box:SetShown(db.box == true and h > 1)
    Style.Shell(box, { bgAlpha = Style.BackAlpha(db.boxAlphaOwn, db.boxAlpha), noBorder = db.boxBorder == false })
    box:ClearAllPoints()
    local px, py = Tracker.BOX_PAD[1], Tracker.BOX_PAD[2]
    box:SetPoint("TOPLEFT", view, "TOPLEFT", -px, py)
    box:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", px, -py)
end

-- The list's height. The view shows up to the height limit (Scroll) and glides
-- there from wherever it is when the change is animated.
function Tracker.SetHeight(h, animate)
    Tracker.contentHeight = h
    content:SetHeight(math.max(1, h))
    local target = ns.Scroll and ns.Scroll.Set(h, db.maxHeight, animate) or h
    -- Contents at the view's edges just changed, for rows that aren't moving too.
    Tracker.RefreshEdges()
    local from = Tracker.viewNow or target
    local function step(v)
        Tracker.viewNow = v
        view:SetHeight(math.max(1, v))
        Tracker.FitBox(v)
    end
    if animate and from ~= target then
        DUI.Motion.Tween("quests:height", from, target, ns.Animate.GLIDE, step)
    else
        DUI.Motion.Tween("quests:height", target, target, 0, step)   -- also stops a glide in progress
    end
end

-- Paint options for Rows.Paint (read only, so shared rather than built per block).
local PAINT = { [true] = { fx = true }, [false] = { fx = false } }
local PAINT_IN_PLACE = { [true] = { fx = true, inPlace = true }, [false] = { fx = false, inPlace = true } }
local PAINT_NEW = {}

-- ifChanged: only when the list would show something new (the game sends
-- QUEST_LOG_UPDATE for plenty that changes nothing here).
function Tracker.Render(animate, ifChanged)
    queued, Tracker.waiting = false, false
    if not content then return end
    local snap = ns.Data.Snapshot(db.filter)
    Tracker.zone = snap.realZone   -- ZONE_CHANGED compares against the game's own zone text
    Tracker.groups, Tracker.hereKey = snap.groups, ns.Data.HereKey(snap.here)
    for k in pairs(inTracker) do inTracker[k] = nil end
    local zoneOnly = Tracker.ZoneOnly()
    for _, g in ipairs(snap.groups) do
        if not zoneOnly or snap.here[g.name] then
            for _, q in ipairs(g.quests) do inTracker[q.id] = true end
        end
    end
    Tracker.NoteProgress(snap)
    local blocks, height = ns.Layout.Build(snap, Tracker.Options(), Tracker.Measure)
    if ifChanged and not Tracker.held and ns.Layout.Same(shown, blocks) then
        Tracker.reasons = { enter = {}, leave = {}, far = {}, fold = false }
        return
    end
    local look = Tracker.Look()
    view:SetWidth(look.width)
    content:SetWidth(look.width)
    local r = Tracker.reasons
    Tracker.reasons = { enter = {}, leave = {}, far = {}, fold = false }
    if InCombatLockdown() and ns.Layout.WouldMoveItems(shown, blocks, { from = Tracker.contentHeight, to = height,
            max = db.maxHeight, offset = ns.Scroll and ns.Scroll.offset, growUp = db.growUp == true }) then
        -- Item buttons can't follow in combat: keep the on-screen layout and only update
        -- what's already there. The rest plays when combat ends.
        Tracker.held = true
        local keep = Tracker.reasons
        for k in pairs(r.enter) do keep.enter[k] = true end
        for k in pairs(r.leave) do keep.leave[k] = true end
        for k in pairs(r.far) do keep.far[k] = true end
        keep.fold = keep.fold or r.fold
        for _, b in ipairs(blocks) do
            local f = frames[b.key]
            if f then
                local ev = ns.Rows.Paint(f, b, look, PAINT_IN_PLACE[animate == true])
                if ev.ready and animate then Tracker.OnReady(b) end
            end
        end
        if ns.Items then ns.Items.Dim(snap) end
        Tracker.ReportRows(blocks)
        return
    end
    Tracker.held = false
    local diff = ns.Layout.Diff(shown, blocks)
    for key in pairs(diff.leave) do
        local f = frames[key]
        frames[key] = nil
        if f then Tracker.Drop(f, animate and Tracker.LeaveStyle(key, r) or nil) end
    end
    for _, b in ipairs(blocks) do
        local f = frames[b.key]
        if f then
            local ev = ns.Rows.Paint(f, b, look, PAINT[animate == true])
            if ev.ready and animate then Tracker.OnReady(b) end
            if diff.moved[b.key] then
                if animate then ns.Animate.Glide(f, b.y) else ns.Animate.Jump(f, b.y) end
            end
        else
            f = ns.Rows.Get(b.kind, content)
            frames[b.key] = f
            if ns.Clicks then ns.Clicks.Attach(f) end
            ns.Rows.Paint(f, b, look, PAINT_NEW)
            Tracker.Arrive(f, b, animate and Tracker.EnterStyle(b, r) or nil)
        end
    end
    for i = #shown, 1, -1 do shown[i] = nil end
    for i, b in ipairs(blocks) do shown[i] = b end
    -- The order frozen for combat (Layout.Sort's frozen).
    if not InCombatLockdown() then
        local order, n = {}, 0
        for _, b in ipairs(blocks) do
            if b.kind == "quest" then n = n + 1; order[b.quest.id] = n end
        end
        Tracker.order = order
        local zones = {}
        for i, g in ipairs(snap.groups) do zones[g.name] = i end
        Tracker.zoneOrder = zones
    end
    local ends, now = Tracker.timerEnds, GetTime()
    for k in pairs(ends) do ends[k] = nil end
    for _, b in ipairs(blocks) do
        if b.kind == "quest" and type(b.quest.timer) == "number" then ends[b.quest.id] = now + b.quest.timer end
    end
    Tracker.SetHeight(height, animate)
    if ns.Items then ns.Items.Sync(blocks, frames) end
    Tracker.ReportRows(blocks)
end

-- Reports the shown quests to plugins (DaylightUI.API's "questrow" kind, quest ID
-- as the unit) and lets them paint, after every layout.
function Tracker.ReportRows(blocks)
    local R = DUI.APIReport
    if type(R) ~= "table" then return end
    for _, b in ipairs(blocks) do
        local f = b.kind == "quest" and b.quest and frames[b.key]
        if f then
            local info = f.apiInfo or {}
            f.apiInfo = info
            info.questID = b.quest.id
            R.SetInfo(f, info)
            R.Row("questrow", f, b.quest.id, info, false)
        end
    end
    R.ListDone("questrow")
end

-- At most one render per frame. It animates only if every request asked for it (a
-- loading screen's request wins, no motion behind it), and is skipped when nothing
-- visible changed only if every request allowed that.
-- wait: a bare QUEST_LOG_UPDATE (bursts, many per second in combat) waits LOG_WAIT
-- so a burst lays out once. Any other request (accept, turn-in, watch, combat end)
-- still runs next frame and takes the waiting one with it. In combat it waits
-- LOG_WAIT_FIGHT, since each check reads the whole log and the progress popup has
-- already shown what changed.
Tracker.LOG_WAIT = 0.15
Tracker.LOG_WAIT_FIGHT = 0.5
Tracker.waiting = false
local wantIfChanged = nil
local function runQueued()
    local a, c = wantAnimate, wantIfChanged
    wantAnimate, wantIfChanged = nil, nil
    DUI.SafeCall(Tracker.Render, a == true and DUI.loggedIn == true, c == true)
end
function Tracker.Queue(animate, ifChanged, wait)
    if wantAnimate == nil then wantAnimate = animate else wantAnimate = wantAnimate and animate end
    ifChanged = ifChanged == true
    if wantIfChanged == nil then wantIfChanged = ifChanged else wantIfChanged = wantIfChanged and ifChanged end
    if queued then return end
    if wait then
        if Tracker.waiting then return end
        Tracker.waiting = true
        C_Timer.After(InCombatLockdown() and Tracker.LOG_WAIT_FIGHT or Tracker.LOG_WAIT, function()
            if Tracker.waiting then runQueued() end   -- otherwise a render already ran
        end)
        return
    end
    queued, Tracker.waiting = true, false
    C_Timer.After(0, runQueued)
end

-- Events after which the list always lays out: a loading screen (texts measure
-- again) and combat ending (whatever was held).
Tracker.ALWAYS = { PLAYER_ENTERING_WORLD = true, PLAYER_REGEN_ENABLED = true }

function Tracker.OnEvent(event, a, b)
    local r = Tracker.reasons
    if event == "QUEST_ACCEPTED" then
        if type(a) == "number" then r.enter[a] = true end
    elseif event == "QUEST_WATCH_LIST_CHANGED" then
        if type(a) == "number" then
            if b then r.enter[a] = true else r.leave[a] = true; Tracker.ForgetProgress(a) end
        end
    elseif event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED" then
        if type(a) == "number" then
            r.leave[a] = true
            -- A turn-in leaves further and slower than an untrack or abandon.
            if event == "QUEST_TURNED_IN" then r.far[a] = true end
            Tracker.ForgetProgress(a)
            if ns.Details then ns.Details.OnRemoved(a) end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        Tracker.ForgetMeasures()     -- measure again after a loading screen
        Tracker.CheckInstance()
    elseif event == "ZONE_CHANGED" then
        -- A new subzone of the same zone matters only when it changes which of
        -- the log's headers count as here (Northshire Valley inside Elwynn Forest).
        local ok, zone = pcall(GetRealZoneText)
        if ok and zone == Tracker.zone and Tracker.groups and Tracker.HereKey() == Tracker.hereKey then return end
    end
    Tracker.Queue(event ~= "PLAYER_ENTERING_WORLD", not Tracker.ALWAYS[event], Tracker.WAITS[event] == true)
end

-- Which headers count as here now, for the groups last laid out.
function Tracker.HereKey()
    local D, names = ns.Data, {}
    for _, g in ipairs(Tracker.groups) do names[g.name] = true end
    return D.HereKey(D.HereSet(Tracker.groups, D.Here(function(name) return names[name] == true end)))
end

function Tracker.ToggleFold(id)
    local folds = Tracker.Folds()
    if folds[id] then folds[id] = nil else folds[id] = true end
    -- Header toggled by hand: the fold now belongs to the player, not the dungeon.
    if id == "quests" then DUI.DB.Character().questInstanceFolded = nil end
    Tracker.reasons.fold = true
    Tracker.Queue(true)
end

-- Shift-click a zone name: fold every quest in it (or unfold them if all are folded).
function Tracker.FoldZoneQuests(zone)
    local folds, ids, open = Tracker.Folds(), {}, false
    for _, b in ipairs(Tracker.shown or {}) do
        if b.kind == "quest" and b.quest.zone == zone then
            ids[#ids + 1] = b.quest.id
            if not folds["q" .. b.quest.id] then open = true end
        end
    end
    for _, id in ipairs(ids) do folds["q" .. id] = open or nil end
    Tracker.reasons.fold = true
    Tracker.Queue(true)
end

-- Key binding (Bindings.xml): fold the whole list to its header.
function Tracker.FoldAll() Tracker.ToggleFold("quests") end
DUI.QuestsFoldAll = function() if Tracker.built then Tracker.FoldAll() end end
_G.BINDING_HEADER_DAYLIGHTUI_QUESTS = string.format(DUI.L["Daylight UI: %s"], DUI.L["Quests"])
_G.BINDING_NAME_DAYLIGHTUI_QUESTS_FOLD = DUI.L["Fold the quest tracker"]

function Tracker.Apply(path)
    if not Tracker.built then return end
    Tracker.ForgetMeasures()         -- a size, the font or its scale may have changed
    -- The All / This zone buttons may be showing when the filter changes.
    if Tracker.controls then Tracker.PaintControls() end
    if path == "growUp" then Tracker.Anchor() end
    if path == "instances" then Tracker.CheckInstance(true) end
    if path == "sort" then Tracker.near = nil; Tracker.NearTick() end
    if path and Tracker.FADE_PATHS[path] then
        Tracker.reasons.fold = true
        Tracker.Queue(true)
        return
    end
    Tracker.Render(false)
end

-- Below the info panel if it's there, otherwise below the screen corner.
function Tracker.Default()
    if _G.DaylightUITrackerAnchor then return { "TOPRIGHT", "DaylightUITrackerAnchor", "TOPRIGHT", 0, 0 } end
    return Tracker.FALLBACK
end

-- Where the player had moved the game's tracker becomes this one's (same top-right
-- corner; the old handle was wider). Marked `follows`: a spot that was the panel's
-- corner may still follow the data text strip (the info panel's
-- Tracker.FollowStrip); moving it by hand saves a plain one.
function Tracker.Migrate()
    local pos = DUI.DB.Positions()
    local old = pos[Tracker.OLD_MOVER]
    if pos[Tracker.MOVER] or type(old) ~= "table" or type(old[1]) ~= "number" then return end
    pos[Tracker.MOVER] = { old[1] + (Tracker.OLD_W - Tracker.HOLDER[1]) / 2, old[2], follows = true }
end

-- The Quests header stays pinned at the top of the view while the list scrolls
-- (with its All / This zone buttons). Once the list has scrolled past it, it's
-- placed at the scroll offset over the rows, which fade out as they slide under it
-- (Scroll.EdgeFor's top inset).
Tracker.PIN = "section:quests"
Tracker.PIN_LEVEL = 5   -- above the rows in the content

local function pinned(f) return f ~= nil and f == frames[Tracker.PIN] end

-- The pinned header's height while it heads the list (its block at the top),
-- otherwise 0. The rows' top edge moves down by this.
function Tracker.PinnedHeight()
    local h = frames[Tracker.PIN]
    if not (h and h:IsShown()) or ns.Animate.State(h).y > 0.5 then return 0 end
    return h:GetHeight() or 0
end

local function softenBlock(f, y, a)
    local edge = 1
    if ns.Scroll and not pinned(f) then edge = ns.Scroll.EdgeFor(y, f:GetHeight()) end
    f:SetAlpha(a * edge)
end

local function placeBlock(f, y, dx, a)
    local top = y
    if pinned(f) and y < 0.5 and ns.Scroll then
        top = math.max(y, ns.Scroll.offset)
        local want = (content:GetFrameLevel() or 0) + Tracker.PIN_LEVEL
        if f:GetFrameLevel() ~= want then f:SetFrameLevel(want) end
    end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", content, "TOPLEFT", dx, -top)
    f:SetPoint("TOPRIGHT", content, "TOPRIGHT", dx, -top)
    softenBlock(f, y, a)
end

-- After a scroll, and every frame of a glide: only the edge fade follows. The view
-- moved, not the rows, so nothing is re-anchored (that would lay out the whole
-- list every frame).
function Tracker.RefreshEdges()
    if ns.Scroll then ns.Scroll.topInset = Tracker.PinnedHeight() end
    for _, f in pairs(frames) do
        local st = ns.Animate.State(f)
        softenBlock(f, st.y, st.a)
    end
    -- Only the pinned header moves with the view.
    local h = frames[Tracker.PIN]
    if h then
        local st = ns.Animate.State(h)
        placeBlock(h, st.y, st.dx, st.a)
    end
    if Tracker.controls and Tracker.controls:IsShown() then Tracker.PlaceControls() end
end

-- Timed quests count down every second without a relayout.
Tracker.timerEnds = {}
function Tracker.TickTimers()
    if not next(Tracker.timerEnds) then return end
    local look = Tracker.Look()
    local now = GetTime()
    for id, ends in pairs(Tracker.timerEnds) do
        local f = frames["quest:" .. id]
        if f then ns.Rows.SetTimer(f, math.max(0, ends - now), look) end
    end
end

Tracker.CONTROL_H = 18
Tracker.CONTROL_GAP = 6              -- between the buttons and the header's arrow
Tracker.CONTROL_LINGER = 1          -- seconds they stay after the mouse leaves

-- A W.Button short enough for the header's line. The picked filter shows as
-- active (SetActive).
local function controlButton(parent, text, onClick)
    local b = DUI.Widgets.Button(parent, text, Tracker.CONTROL_H)
    b.FitWidth(0)
    b:SetScript("OnClick", function(self) DUI.SafeCall(onClick, self) end)
    return b
end

-- The All / This zone buttons. Inside a dungeon's own view, All lifts it for the
-- visit and the player's filter stays as it was.
function Tracker.PickFilter(filter)
    local c = DUI.DB.Character()
    if not c.questInstanceZone then return DUI:Set("Quests", "filter", filter) end
    if filter ~= "zone" then
        c.questInstanceZone = nil
        Tracker.Apply("filter")
    end
end

function Tracker.BuildControls()
    local c = CreateFrame("Frame", nil, holder)
    c:SetHeight(Tracker.CONTROL_H)
    c:SetPoint("TOPRIGHT", view, "TOPRIGHT", -(ns.Rows.CHEVRON + 4), 0)
    c:SetWidth(150)
    -- Above the rows (holder > view > content > row > line) so clicks reach it.
    c:SetFrameLevel((content:GetFrameLevel() or 0) + 10)
    c:Hide()
    c.zone = controlButton(c, DUI.L["This zone"], function() Tracker.PickFilter("zone") end)
    c.all = controlButton(c, ALL or DUI.L["All"], function() Tracker.PickFilter("all") end)
    c.zone:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, 0)
    c.all:SetPoint("TOPRIGHT", c.zone, "TOPLEFT", -4, 0)
    Tracker.controls = c
end

-- On the Quests header's line, just left of its arrow (or the list's corner when
-- there's no header; the controls sit outside the view's clip). The header stays
-- in view while it heads the list (pinned), so they never sit over the rows.
function Tracker.PlaceControls()
    local c, h = Tracker.controls, frames["section:quests"]
    c:ClearAllPoints()
    local inView = h and (ns.Scroll == nil or Tracker.PinnedHeight() > 0 or ns.Scroll.offset <= ns.Animate.State(h).y)
    if inView and h:IsShown() and h.chevron and h.label then
        c:SetPoint("RIGHT", h.chevron, "LEFT", -Tracker.CONTROL_GAP, 0)
        c:SetPoint("TOP", h.label, "CENTER", 0, Tracker.CONTROL_H / 2)
    else
        c:SetPoint("TOPRIGHT", view, "TOPRIGHT", -(ns.Rows.CHEVRON + Tracker.CONTROL_GAP), 0)
    end
end

function Tracker.PaintControls()
    local c = Tracker.controls
    local zoneOnly = Tracker.ZoneOnly()
    c.all.SetActive(not zoneOnly)
    c.zone.SetActive(zoneOnly)
end

-- Controls show while the mouse is over the list (and a moment after it leaves).
-- The count under them fades out.
local function alpha(a) Tracker.controls:SetAlpha(a) end
function Tracker.Hovered()
    local c = Tracker.controls
    local over = (view:IsMouseOver() == true) or (c:IsShown() and c:IsMouseOver() == true)
    local now = GetTime()
    if over then Tracker.lastOver = now end
    local want = over or (Tracker.lastOver and now - Tracker.lastOver < Tracker.CONTROL_LINGER)
    local M = DUI.Motion
    if want and (not c:IsShown() or c.leaving) then
        Tracker.PlaceControls()
        Tracker.PaintControls()
        if c.leaving then
            c.leaving = nil   -- caught while leaving, come back from there
            M.Tween(c, c:GetAlpha(), 1, M.FAST, alpha)
        else
            c:Show()
            M.Fade(c, 0, 1, M.NORMAL)
        end
    elseif not want and c:IsShown() and not c.leaving then
        -- Fades out FAST, then hides.
        c.leaving = true
        M.Tween(c, c:GetAlpha(), 0, M.FAST, alpha, function()
            if not c.leaving then return end
            c.leaving = nil
            c:Hide()
            c:SetAlpha(1)
        end)
    end
    local h = frames["section:quests"]
    -- The count makes way as the controls appear (FAST) and returns as they go
    -- (NORMAL), never a blink.
    if h then
        local goal = (c:IsShown() and not c.leaving) and 0 or 1
        if h.countGoal ~= goal then
            local fs = h.count
            local from = h.countGoal and fs:GetAlpha() or goal
            h.countGoal = goal
            M.Tween(fs, from, goal, goal == 0 and M.FAST or M.NORMAL, function(a) fs:SetAlpha(a) end)
        end
    end
end

-- Whether this tracker draws: the game's is starved (no other tracker addon) and,
-- with Questie on, the player didn't pick Questie's (`tracker`, Choice.lua).
-- Without Questie this is the only tracker, whatever the setting says.
function Tracker.Wanted()
    if not ns.Blizzard.starved then return false end
    if DUI:Get("Quests", "tracker") == false and ns.Bridge and ns.Bridge.Loaded() then return false end
    return true
end

-- `tracker` changed: fade out and go, or appear (built the first time) and fade
-- in. Out of combat only, since the item buttons are secure.
function Tracker.Follow()
    DUI.AfterCombat(function()
        local M = DUI.Motion
        if Tracker.Wanted() and not Tracker.instanceAway then
            if not Tracker.built then
                if Tracker.mod then Tracker.Build(Tracker.mod) end
                return
            end
            local h, items = Tracker.holder, ns.Items and ns.Items.holder
            if Tracker.going then
                -- Turned back on mid fade-out: come back from where it is.
                Tracker.going = nil
                local from = h:GetAlpha()
                M.Tween(h, from, 1, M.FAST, function(a)
                    h:SetAlpha(a)
                    if items then items:SetAlpha(a) end
                end, function() DUI.Fade.Hold("Quests.tracker", false) end)
                return
            end
            if h:IsShown() then return end
            Tracker.holder:Show()
            if ns.Items and ns.Items.holder then ns.Items.holder:Show() end
            DUI.Fade.Hold("Quests.tracker", false)
            DUI.Fade.Arrive("Quests.tracker", M.NORMAL)
            Tracker.Render(false)
        elseif Tracker.built and Tracker.holder:IsShown() then
            local h, items = Tracker.holder, ns.Items and ns.Items.holder
            if Tracker.going then return end
            Tracker.going = true
            DUI.Fade.Hold("Quests.tracker", true)
            M.Tween(h, h:GetAlpha(), 0, M.NORMAL, function(a)
                h:SetAlpha(a)
                if items then items:SetAlpha(a) end
            end, function()
                if not Tracker.going then return end
                Tracker.going = nil
                DUI.AfterCombat(function()
                    h:Hide()
                    if items then items:Hide() end
                end, "quest tracker away")
            end)
        end
    end, "quest tracker switch")
end

function Tracker.Build(mod)
    Tracker.mod = mod
    if Tracker.built or not Tracker.Wanted() then return end
    db = mod.db
    holder = CreateFrame("Frame", "DaylightUIQuestTracker", UIParent)
    holder:SetSize(Tracker.HOLDER[1], Tracker.HOLDER[2])
    holder:SetFrameStrata("LOW")
    ns.Rows.glowParent = holder
    box = CreateFrame("Frame", nil, holder)
    box:EnableMouse(false)
    box:Hide()
    view = CreateFrame("ScrollFrame", nil, holder)
    view:SetSize(Tracker.Width(), 1)
    content = CreateFrame("Frame", nil, view)
    content:SetSize(Tracker.Width(), 1)
    view:SetScrollChild(content)
    ns.Scroll.Build(view, content)
    Tracker.BuildControls()
    Tracker.holder, Tracker.view, Tracker.content, Tracker.box = holder, view, content, box
    -- The login reveal outlines the list even without its box (the box's own border is
    -- traced when it shows), where the box would be.
    DUI.Fade.RevealAlso(function()
        if not box:IsShown() and #shown > 0 then return view, Tracker.BOX_PAD[1] end
    end)
    Tracker.Anchor()
    ns.Animate.place = placeBlock
    ns.Animate.onTick = function() if ns.Items then ns.Items.Follow() end end
    Tracker.Migrate()
    DUI.Movers.Register(holder, Tracker.MOVER, "Quest Tracker", Tracker.Default)
    -- Only the holder is hovered and faded. The item column's holder covers the screen
    -- (its buttons are placed in screen coordinates), so it gets the same alpha by
    -- hand, and the list (which can hang below the holder) and the item buttons wake it.
    local list = { holder }   -- one shared table, the fade asks often
    DUI.Fade.Register{ key = "Quests.tracker", scope = "Quests", path = "fade", page = "Quests.tracker",
        frames = function() return list end,
        paint = function(f, a)
            f:SetAlpha(a)
            if ns.Items and ns.Items.holder then ns.Items.holder:SetAlpha(a) end
        end,
        over = function()
            return view:IsMouseOver() == true or (ns.Items ~= nil and ns.Items.Hovered())
        end }
    for _, e in ipairs(Tracker.EVENTS) do
        pcall(DUI.RegisterEvent, e, function(event, ...) Tracker.OnEvent(event, ...) end)
    end
    -- Spoken's voice packs loaded or its quest part toggled: re-check the Play buttons.
    ns.Voice.Enable(function() Tracker.Queue(true, true) end)
    -- Text is drawn to whole pixels, so measured heights can shift slightly with the
    -- UI scale.
    for _, e in ipairs({ "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
        pcall(DUI.RegisterEvent, e, function() Tracker.ForgetMeasures() end)
    end
    -- Matching the minimap: its Size slider (or turning matching off) re-lays the list
    -- right away, not on the next quest event.
    DUI.On("SettingChanged", function(scope, path)
        if scope == "InfoPanel" and (path == "map.size" or path == "map.enabled") and db.matchMap then Tracker.Apply() end
    end)
    Tracker.built = true
    Tracker.Render(false)
    Tracker.hoverTicker = C_Timer.NewTicker(0.1, function()
        DUI.SafeCall(Tracker.Hovered)
        if ns.Items then DUI.SafeCall(ns.Items.FollowIfMoved) end
    end)
    Tracker.timerTicker = C_Timer.NewTicker(1, function() DUI.SafeCall(Tracker.TickTimers) end)
    Tracker.nearTicker = C_Timer.NewTicker(Tracker.NEAR_EVERY, function() DUI.SafeCall(Tracker.NearTick) end)
    Tracker.CheckInstance()
end
