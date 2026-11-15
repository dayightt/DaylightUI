-- Puts a Daylight UI plate on each of the game's nameplates. When a plate gets a
-- unit, the game's own plate frame is taken off it (its widgets, like soft-target
-- icons, stay in view) and the Daylight UI plate shows in its place. Plates the
-- game keeps from addons (friendly ones in instances) are left alone.
--
-- A Daylight UI plate sits on a game plate only while that plate shows a unit and
-- comes off the moment the unit goes. The game reuses its plates, and one that
-- carries a unit addons may not touch turns everything on it forbidden for good,
-- so an addon frame left on it would be unusable from then on.

local _, ns = ...
local DUI = DaylightUI
local isSecret = DUI.IsSecret
local L = DUI.L

local Manager = {}
ns.Manager = Manager

local hidden = CreateFrame("Frame")
hidden:Hide()

local byUnit = {} -- unit -> its Daylight UI plate
local spare = {} -- plates not on any game plate
Manager.byUnit = byUnit
-- Plates are built at login, out of combat: one per plate the game can show
-- (nameplate1-40), so none is ever built mid-fight.
Manager.PREPARE = 40

-- Plates live here while not on a game plate.
local home = CreateFrame("Frame", nil, UIParent)
home:Hide()

function Manager.Prepare(n)
    for _ = 1, n do spare[#spare + 1] = ns.Plate.Create(home) end
end

function Manager.Spares() return #spare end

-- Sets the spare plates aside for good and builds a new set, for /dui platefix.
-- The old ones stay hidden where they are and are never put on a plate again.
-- A few are built each frame: all 40 in one frame froze the game for a moment.
-- done runs once the last one is built.
Manager.FRESH_PER_FRAME = 4
function Manager.FreshPool(done)
    for i = #spare, 1, -1 do spare[i] = nil end
    local left = Manager.PREPARE
    local function step()
        local n = math.min(left, Manager.FRESH_PER_FRAME)
        Manager.Prepare(n)
        left = left - n
        if left > 0 then return C_Timer.After(0, step) end
        if done then done() end
    end
    step()
end

local plain = function(...) return ns.Plate.Plain(...) end

local function forbidden(frame)
    if not frame.IsForbidden then return false end
    local ok, no = pcall(frame.IsForbidden, frame)
    return not ok or no == true
end

-- A spare plate (dropping any that became forbidden), or a new one built under
-- the home frame.
function Manager.Take()
    while #spare > 0 do
        local p = table.remove(spare)
        if not forbidden(p) then return p end
    end
    return ns.Plate.Create(home)
end

-- Off the game's plate, back to the spares.
function Manager.Release(p)
    if forbidden(p) then return end
    pcall(ns.Plate.Detach, p)
    p:Hide()
    p:ClearAllPoints()
    p:SetParent(home)
    p.nameplate = nil
    spare[#spare + 1] = p
end

-- Takes the game's own plate frame off its plate while a Daylight UI plate is
-- on it, the way Platynator does: the frame moves onto a hidden frame and all
-- its events (and its cast bar's) stop, so none of the game's plate code runs
-- or draws under the Daylight UI plate. Its widgets (quest progress, loot
-- sparkle) and soft-target icon move onto the game's plate itself and stay in
-- view. Where the plate is clicked becomes Daylight UI's too (Manager.OwnClicks),
-- since the game hangs it from that frame's health bar and name.
-- The game puts the frame back on a plate itself each time it hands one out,
-- and its SetUnit registers the unit events again, so every hand-out is taken
-- off again (Manager.Added, Manager.FrameHandedOut). Nothing is given back when
-- a unit leaves: the game takes its frame back to its pool, and a frame handed
-- to a plate without a Daylight UI plate on it gets back the events it
-- registered when it was made (Manager.LOAD_EVENTS, from the game's
-- CompactUnitFrame_OnLoad) and its widgets (Manager.GiveBackFrame).
local held = setmetatable({}, { __mode = "k" }) -- game frames taken off their plate
Manager.LOAD_EVENTS = {
    "VARIABLES_LOADED", "CVAR_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED",
    "PLAYER_SOFT_FRIEND_CHANGED", "PLAYER_SOFT_ENEMY_CHANGED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_LEVEL_UP",
    "PLAYER_ROLES_ASSIGNED", "PLAYER_LEVEL_CHANGED", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
    "READY_CHECK", "READY_CHECK_FINISHED", "READY_CHECK_CONFIRM", "PARTY_MEMBER_DISABLE",
    "PARTY_MEMBER_ENABLE", "INCOMING_RESURRECT_CHANGED", "GROUP_JOINED", "GROUP_LEFT", "INCOMING_SUMMON_CHANGED",
}
local quieted = setmetatable({}, { __mode = "k" })

local function quiet(uf)
    if type(uf.UnregisterAllEvents) ~= "function" then return end
    pcall(uf.UnregisterAllEvents, uf)
    quieted[uf] = true
    local cast = uf.castBar
    if type(cast) ~= "table" and type(uf.CastBarsContainer) == "table" then cast = uf.CastBarsContainer.castBar end
    if type(cast) == "table" and type(cast.UnregisterAllEvents) == "function" and not forbidden(cast) then
        pcall(cast.UnregisterAllEvents, cast)
    end
end

-- The pieces of the game's frame that stay in view on the plate.
local function keepers(uf)
    return { uf.WidgetContainer, uf.SoftTargetFrame }
end

local function moveKeepers(uf, to)
    for _, keep in ipairs(keepers(uf)) do
        if type(keep) == "table" and keep.SetParent and not forbidden(keep) and keep:GetParent() ~= to then
            keep:SetParent(to)
        end
    end
end

-- p is the Daylight UI plate on it. It remembers the frame, since the game has
-- already taken its frame off the plate by the time it reports the unit gone.
function Manager.HideGameFrame(nameplate, p)
    if Manager.fixWithout == "hide" then return end -- /dui platefix is trying the plates without this
    local uf = nameplate.UnitFrame
    if type(uf) ~= "table" or not uf.SetParent or forbidden(uf) then return end
    if p then p.gameFrame = uf end
    held[uf] = true
    if uf:GetParent() ~= hidden then uf:SetParent(hidden) end
    quiet(uf)
    moveKeepers(uf, nameplate)
end

function Manager.IsHeld(uf)
    return held[uf] == true
end

-- The game's own way of setting where its plate is clicked (its UpdateHitTestArea).
local function gameClicks(nameplate)
    local uf = nameplate.UnitFrame
    if type(uf) ~= "table" or forbidden(uf) or type(uf.UpdateHitTestArea) ~= "function" then return end
    if type(NamePlateSetupOptions) ~= "table" then return end
    pcall(uf.UpdateHitTestArea, uf, NamePlateSetupOptions)
end

-- Gives a held frame back to the game: its events, its widgets and, when it's on
-- a plate (nameplate given), its spot and click area there, as the game sets
-- them when it hands a frame out.
function Manager.GiveBackFrame(uf, nameplate)
    if type(uf) ~= "table" or not uf.SetParent or forbidden(uf) or not held[uf] then return end
    held[uf] = nil
    if quieted[uf] then
        quieted[uf] = nil
        for _, e in ipairs(Manager.LOAD_EVENTS) do pcall(uf.RegisterEvent, uf, e) end
    end
    moveKeepers(uf, uf)
    if type(nameplate) == "table" and nameplate.UnitFrame == uf and not forbidden(nameplate) then
        if uf:GetParent() ~= nameplate then
            uf:SetParent(nameplate)
            uf:ClearAllPoints()
            uf:SetAllPoints(nameplate)
        end
        gameClicks(nameplate)
    end
end

-- Where a plate is clicked, Platynator's way: one frame of Daylight UI's per
-- game plate, covering it (the game sizes its plates to the Daylight UI ones,
-- Manager.ApplySize), handed to the game as the plate's click area. It stays on
-- that game plate for good, so the game's plate never points at a frame that
-- moved on to another. Built at login (Manager.PrepareClicks); one needed in a
-- fight is built bare, never on a game plate. A plate the game shows only as a
-- name (friendly players with friendly bars off) or only its widgets (a
-- lootable corpse) can't be clicked, as the game does it.
local clickOf = setmetatable({}, { __mode = "k" }) -- game plate -> its click frame
local clickSpare = {}
Manager.clickOf = clickOf

function Manager.PrepareClicks(n)
    for _ = 1, n do clickSpare[#clickSpare + 1] = CreateFrame("Frame") end
end

local function clickFrame(nameplate)
    local f = clickOf[nameplate]
    if f then return f end
    f = table.remove(clickSpare) or CreateFrame("Frame")
    clickOf[nameplate] = f
    f:SetParent(nameplate)
    f:ClearAllPoints()
    f:SetAllPoints(nameplate)
    f:Show()
    return f
end

function Manager.Unclickable(unit)
    if plain(UnitNameplateShowsWidgetsOnly, unit) == true then return true end
    if plain(UnitIsPlayer, unit) ~= true or plain(UnitIsFriend, "player", unit) ~= true then return false end
    local ok, v = pcall(GetCVar, Manager.NAME_ONLY_CVAR)
    return ok and v == "1"
end

function Manager.OwnClicks(p)
    local np, unit = p.nameplate, p.unit
    if type(np) ~= "table" or not unit or forbidden(np) or Manager.fixWithout == "hide" then return end
    local okC, can = pcall(np.CanChangeHitTestPoints, np)
    if not okC or can ~= true then return end
    if Manager.Unclickable(unit) then
        pcall(np.ClearAllHitTestPoints, np)
    else
        pcall(np.SetAllHitTestPoints, np, clickFrame(np))
    end
end

local refused = setmetatable({}, { __mode = "k" }) -- game plates a Daylight UI plate can't go on; the game's stays (Added)

function Manager.Added(unit)
    if Manager.fixPaused then return end -- /dui platefix has handed plates back to the game for now
    if plain(UnitIsUnit, unit, "player") == true then return end
    local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    if not get then return end
    local ok, nameplate = pcall(get, unit, issecure and issecure() or false)
    if not ok or type(nameplate) ~= "table" then return end
    -- Some plates (friendly players' in some places) belong to the game alone.
    -- Touching one is an error, so they're left as the game draws them.
    if forbidden(nameplate) then return end
    if byUnit[unit] then Manager.Removed(unit) end
    -- A plate still on this game plate for another unit means its removal never
    -- arrived (Manager.Sync).
    for other, q in pairs(byUnit) do
        if q.nameplate == nameplate then Manager.Removed(other) end
    end
    refused[nameplate] = nil
    local p = Manager.Take()
    -- Some plates don't report forbidden but make anything put on them forbidden.
    -- Check the new one is still usable there before hiding the game's. If not (or
    -- anything here errors), it comes off (or is dropped) and the game keeps drawing
    -- its own plate for this unit.
    if not DUI.SafeCall(ns.Plate.Attach, p, nameplate) or not Manager.Usable(p) then
        refused[nameplate] = true
        Manager.Abandon(p)
        return
    end
    byUnit[unit] = p
    if not (DUI.SafeCall(Manager.HideGameFrame, nameplate, p) and DUI.SafeCall(ns.Plate.Install, p, unit)
        and DUI.SafeCall(Manager.OwnClicks, p)) then
        byUnit[unit] = nil
        DUI.SafeCall(Manager.GiveBackFrame, p.gameFrame, nameplate) -- give the game its plate back for this unit
        p.gameFrame = nil
        refused[nameplate] = true
        Manager.Abandon(p)
        return
    end
    if Manager.testHidden then p:Hide() end
    -- Only your target appearing changes the other plates' sizes.
    if p.isTarget then Manager.UpdateTargets() else Manager.SizeOne(p) end
    -- Registered with the API once it's really up and sized (a plate that failed above
    -- never is). The first time a pooled plate shows it's created; every time, it
    -- gets a unit.
    -- Its cast bar goes along as a "platecast" frame.
    if not p.apiSeen then
        p.apiSeen = true
        DUI.APIReport.Made("nameplate", p, nil, false)
        DUI.APIReport.Made("platecast", p.cast, nil, false)
    end
    DUI.APIReport.Unit("nameplate", p, unit, false)
    DUI.APIReport.Unit("platecast", p.cast, unit, false)
    -- Set up before the API knew it, so plugins paint it now.
    ns.Plate.Painted(p)
    if ns.Cast.Shown(p) then ns.Cast.Painted(p) end
end

-- Whether a Daylight UI plate can still be read and changed where it is.
local function usable(f)
    if forbidden(f) then return false end
    return (pcall(f.GetEffectiveScale, f))
end

function Manager.Usable(p)
    return usable(p) and usable(p.hp) and usable(p.cast)
end

-- Same check for a plate already in place. It was fully checked when added, so
-- only the plate itself is asked (walks run on most events, for every plate).
function Manager.StillUsable(p)
    return usable(p)
end

-- Permanently off the game's plate: back to the spares if still usable, else left
-- where it is and never touched again.
function Manager.Abandon(p)
    ns.Cast.Forget(p)
    if Manager.Usable(p) then
        pcall(ns.Plate.Uninstall, p)
        Manager.Release(p)
    else
        pcall(ns.Plate.Detach, p)
        pcall(p.Hide, p)
    end
end

-- Takes every frame under a Daylight UI plate off its plate again and sets each
-- click area again. The game's options update (UpdateNamePlateOptions) gives
-- every frame its unit, events and click area back; Manager.Start switches off
-- the two driver events that run it in play (DISPLAY_SIZE_CHANGED, CVAR_UPDATE),
-- and VARIABLES_LOADED still does once.
Manager.RECLAIM_EVENTS = { DISPLAY_SIZE_CHANGED = true, VARIABLES_LOADED = true, CVAR_UPDATE = true }
function Manager.Reclaim()
    for _, p in pairs(byUnit) do
        if type(p.nameplate) == "table" then
            Manager.HideGameFrame(p.nameplate, p)
            Manager.OwnClicks(p)
        end
    end
end

-- The game hands a plate its frame from a shared pool as the plate gets its unit,
-- and that can happen after Manager.Added ran. So right after the game hands one
-- out, take it off the plate if a Daylight UI plate is on that plate, and give it
-- back if not (it may still be held from its previous plate).
function Manager.FrameHandedOut(unit)
    local p = byUnit[unit]
    local nameplate = p and p.nameplate
    if not nameplate then
        local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
        if not get then return end
        local ok, np = pcall(get, unit, issecure and issecure() or false)
        nameplate = ok and np
    end
    if type(nameplate) ~= "table" or forbidden(nameplate) then return end
    local uf = nameplate.UnitFrame
    if type(uf) ~= "table" or forbidden(uf) then return end
    if p then
        Manager.HideGameFrame(nameplate, p)
        Manager.OwnClicks(p)
    elseif held[uf] then
        Manager.GiveBackFrame(uf, nameplate)
    end
end

function Manager.Removed(unit)
    local p = byUnit[unit]
    if not p then return end
    byUnit[unit] = nil
    local wasTarget = p.isTarget
    -- The plate releases its unit but stays known for the next one.
    if p.apiSeen then
        DUI.APIReport.Gone("nameplate", p, false)
        DUI.APIReport.Gone("platecast", p.cast, false)
    end
    -- The game's frame stays held: the game takes it back to its pool, and the
    -- next plate it's handed to either has a Daylight UI plate or gets it back
    -- (Manager.FrameHandedOut).
    p.gameFrame = nil
    ns.Cast.Forget(p)
    if Manager.Usable(p) then
        ns.Plate.Uninstall(p)
        Manager.Release(p)
    else
        pcall(ns.Plate.Detach, p) -- take the stacking frame off the game's plate regardless
    end
    -- Any other plate going leaves the rest (and the combo row) alone.
    if wasTarget then Manager.UpdateTargets() end
end

-- Who's targeted. With the option on and your target on a plate, that plate and
-- every other one are sized per their settings (Defaults.lua "target" and
-- "others": width and height multipliers plus an extra zoom, in one step).
-- Otherwise all are normal size.
local EMPTY = {}

-- The last pass's results (plain flags), for a plate shown later.
local sizeOn, othersPlain = false, true
local anyTarget = false

local function markTarget(p)
    ns.Plate.UpdateTarget(p)
    if p.isTarget then anyTarget = true end
end

-- Only plates whose size group changed are re-laid out: a target switch touches
-- two plates, not all of them, and a new plate (laid out at setup) only if it's
-- your target. A size change that's only a zoom is a new scale, not a new layout
-- (Plate.Layout).
-- Your target's own size wins, then the plate's threat size (Plate.UpdateThreatSize),
-- then the others' size. Every group is a fixed size, so plates only ever take a few
-- scales.
local function sizePlate(p)
    local groupNow
    if sizeOn and p.isTarget then
        groupNow = "target"
    elseif p.threatSize then
        groupNow = p.threatSize
    elseif sizeOn and not othersPlain then
        groupNow = "others"
    end
    if groupNow == p.sizeGroup then return end
    p.sizeGroup = groupNow
    ns.Plate.Layout(p)
end

-- One plate's size group again (its threat state changed).
Manager.Resize = sizePlate

-- Puts one plate in its size group from the last pass (a new plate that isn't
-- your target).
function Manager.SizeOne(p)
    sizePlate(p)
    ns.Range.Read(p)
    ns.Plate.Dim(p, true)
end

function Manager.UpdateTargets()
    anyTarget = false
    Manager.Each(markTarget)
    sizeOn = ns.cfg.targetScale and anyTarget or false
    -- "Others" left at normal size (the default) isn't a group at all, so other plates
    -- aren't re-laid out on every target switch (each layout costs the game a plate
    -- redraw; dozens in a crowd).
    local o = ns.cfg.others or EMPTY
    othersPlain = (o.width or 1) == 1 and (o.height or 1) == 1 and (o.scale or 1) == 1
    Manager.Each(sizePlate)
    ns.Plate.hasTarget = anyTarget
    Manager.Each(ns.Plate.Dim)
    if ns.Combo then ns.Combo.Place() end
end

-- Group focus (groupFocus): the enemy most of your party or raid targets gets a
-- mark. Counted at most once per FOCUS_DELAY seconds after a burst of target,
-- roster or plate changes, never per frame. Matched by GUID (one table lookup per
-- member, not a UnitIsUnit per member and plate). In battlegrounds, arenas and
-- restricted maps GUIDs are secret: nothing matches, so no mark.
Manager.FOCUS_DELAY = 0.2
Manager.FOCUS_MIN = 2 -- at least this many of you on it
local focusQueued = false
local focusGuids, focusCounts = {}, {}

local function focusGuid(unit)
    local g = plain(UnitGUID, unit)
    return type(g) == "string" and g or nil
end

local function focusWanted()
    return ns.cfg and ns.cfg.groupFocus == true and plain(IsInGroup) == true
end

function Manager.CountFocus()
    focusQueued = false
    local best
    if focusWanted() then
        wipe(focusGuids)
        wipe(focusCounts)
        for unit, p in pairs(byUnit) do
            if not p.friendly then
                local g = focusGuid(unit)
                if g then focusGuids[g] = p end
            end
        end
        local function add(member)
            local g = focusGuid(member == "player" and "target" or member .. "target")
            local p = g and focusGuids[g]
            if p then focusCounts[p] = (focusCounts[p] or 0) + 1 end
        end
        if plain(IsInRaid) == true then
            for i = 1, 40 do add("raid" .. i) end
        else
            add("player")
            for i = 1, 4 do add("party" .. i) end
        end
        -- The most, at least FOCUS_MIN; a tie marks none.
        local most, tie = Manager.FOCUS_MIN - 1, false
        for p, n in pairs(focusCounts) do
            if n > most then
                best, most, tie = p, n, false
            elseif n == most then
                tie = true
            end
        end
        if tie then best = nil end
    end
    Manager.focus = best
    Manager.Each(function(p) ns.Plate.ShowFocus(p, p == best) end)
end

-- Something that can change the count: queued, unless there's nothing to count
-- and no mark to take down.
function Manager.QueueFocus()
    if focusQueued or not (focusWanted() or Manager.focus) then return end
    focusQueued = true
    C_Timer.After(Manager.FOCUS_DELAY, Manager.CountFocus)
end

local FOCUS_UNITS = { player = true }
for i = 1, 4 do FOCUS_UNITS["party" .. i] = true end
for i = 1, 40 do FOCUS_UNITS["raid" .. i] = true end
-- UNIT_TARGET comes for every plate's mob too; only group members' count.
function Manager.FocusTargetChanged(_, unit)
    if type(unit) == "string" and not isSecret(unit) and FOCUS_UNITS[unit] then
        Manager.QueueFocus()
    end
end

Manager.QUEST_DELAY = 0.2
-- Each plate's check reads its unit's tooltip, so a full pass only happens when a
-- quest was added or removed (QUEST_ACCEPTED, QUEST_REMOVED, or the log count
-- changed) or completion changed (an objective finished, or reopened because you
-- sold some of the items; Plate.QuestSig). A mob that isn't a quest unit can't
-- become one otherwise. A progress tick re-reads only plates that were quest
-- units. Accepting a quest re-reads every plate once more QUEST_LATE seconds
-- later, since the tooltip's quest lines can lag behind.
Manager.QUEST_ALL = { QUEST_ACCEPTED = true, QUEST_REMOVED = true }
Manager.QUEST_LATE = 1.5
local questsDue, questsAll, questCount, questSig = false, false, false, false
local function updateQuest(p)
    if p.questUnit then ns.Plate.UpdateQuest(p) end
end
-- Quest marks or quest mob colors on: either needs the quest log followed.
local function questsWanted()
    return ns.cfg and (ns.cfg.quest or ns.cfg.questBar)
end
local function updateQuests()
    questsDue = false
    local n, sig = ns.Plate.QuestCount(), ns.Plate.QuestSig()
    local all = questsAll or n ~= questCount or sig ~= questSig
    questsAll, questCount, questSig = false, n, sig
    Manager.Each(all and ns.Plate.UpdateQuest or updateQuest)
end
local function queueQuests()
    if questsDue then return end
    questsDue = true
    C_Timer.After(Manager.QUEST_DELAY, updateQuests)
end
local function lateQuests()
    if not questsWanted() then return end
    questsAll = true
    queueQuests()
end
function Manager.QuestsChanged(event)
    -- Marks and colors off: nothing to update (turning one on refreshes every plate).
    if not questsWanted() then return end
    if Manager.QUEST_ALL[event] then questsAll = true end
    if event == "QUEST_ACCEPTED" then C_Timer.After(Manager.QUEST_LATE, lateQuests) end
    queueQuests()
end

function Manager.Each(fn)
    for _, p in pairs(byUnit) do
        if Manager.StillUsable(p) then DUI.SafeCall(fn, p) end
    end
end

-- You died, resurrected or loaded in: what you can attack changed without an
-- event on the plate units. The answer can lag, so check again a moment later
-- (Plate.UpdateFriendly does nothing if nothing changed).
Manager.RECHECK_EVENTS = { "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_ENTERING_WORLD" }
Manager.RECHECK_LATE = 1
function Manager.Recheck()
    Manager.Sync()
    Manager.Each(ns.Plate.UpdateFriendly)
end

-- Reconciles the plates with what the game shows now, as a /reload would. A layer
-- or phase change swaps every unit around you with no loading screen, and which
-- events the engine sends then is up to it. A plate left on a unit that's gone, or
-- a unit with no plate, would stay wrong until it left view. Correct plates are
-- left alone; only differences do any work. A secret or failed answer counts as
-- no difference.
Manager.SYNC_EVERY = 2
function Manager.Sync()
    if Manager.fixPaused then return end
    local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    if not get then return end
    local secure = issecure and issecure() or false
    for unit, p in pairs(byUnit) do
        local ok, np = pcall(get, unit, secure)
        if plain(UnitExists, unit) == false or (ok and np ~= p.nameplate) then Manager.Removed(unit) end
    end
    for i = 1, Manager.PREPARE do
        local unit = "nameplate" .. i
        if not byUnit[unit] and plain(UnitExists, unit) == true then
            local ok, np = pcall(get, unit, secure)
            if ok and type(np) == "table" and not refused[np] then DUI.SafeCall(Manager.Added, unit) end
        end
    end
end

-- Settings or style changed: redo every plate.
function Manager.Refresh()
    ns.Plate.gen = ns.Plate.gen + 1 -- every plate is laid out and marked again
    Manager.WantDots()
    if ns.Combo then ns.Combo.gen = ns.Combo.gen + 1 end -- and the combo pips
    Manager.ApplySize()
    Manager.ApplyScales()
    Manager.Each(function(p)
        if p.unit then
            ns.Plate.Layout(p)
            ns.Auras.SetUnit(p, p.unit)
            ns.Plate.UpdateAll(p)
            DUI.APIReport.Styled("nameplate", p, false)
        end
    end)
    ns.Range.Apply()
    Manager.UpdateTargets()
    Manager.CountFocus()
end

-- The mouseover highlight follows the mouse; checked while it's over a plate.
local watcher = CreateFrame("Frame")
watcher:Hide()
Manager.hoverWatcher = watcher
watcher:SetScript("OnUpdate", function(self)
    if plain(UnitExists, "mouseover") ~= true then
        local lit = ns.Plate.hovered
        if lit then
            lit.hover:Hide()
            ns.Minion.Hover(lit, false)
        end
        ns.Plate.hovered = nil
        self:Hide()
    end
end)

-- The mouse moved onto a unit. Only the plate it left and the one it's on change,
-- so only those are checked. Without an answer from the game, every plate is.
local function hoverChanged()
    local lit = ns.Plate.hovered
    local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    local ok, np = false, nil
    if get then ok, np = pcall(get, "mouseover", issecure and issecure() or false) end
    if not ok then
        Manager.Each(ns.Plate.UpdateHover)
        return
    end
    local on
    if type(np) == "table" then
        for _, p in pairs(byUnit) do
            if p.nameplate == np then on = p break end
        end
    end
    if lit and lit ~= on then
        lit.hover:Hide()
        ns.Minion.Hover(lit, false)
        ns.Plate.hovered = nil
    end
    if on and Manager.Usable(on) then ns.Plate.UpdateHover(on) end
end

-- Plate distance is the game's own setting, which it refuses to change in combat.
Manager.RANGE_CVAR = "nameplateMaxDistance"
function Manager.ApplyRange()
    DUI.AfterCombat(function()
        if SetCVar then pcall(SetCVar, Manager.RANGE_CVAR, tostring(ns.cfg.range)) end
    end, "nameplates:range")
end

-- The game's own plate frames never change size: its distance scaling and target
-- zoom are pinned to 1 (Daylight UI zooms the target itself, in one step in
-- Plate.ApplyScale), so nothing gets resized or restacked underneath and its click
-- area doesn't grow on the target. The game refuses these in combat.
Manager.SCALE_CVARS = { "nameplateMinScale", "nameplateMaxScale", "nameplateSelectedScale" }
function Manager.ApplyScales()
    DUI.AfterCombat(function()
        if not SetCVar then return end
        for _, k in ipairs(Manager.SCALE_CVARS) do pcall(SetCVar, k, "1") end
    end, "nameplates:scales")
end

-- Friendly plates that are just the name: the game's plate underneath is its light
-- name-only one, not a full plate drawn and updated out of sight (a city full of
-- players cost a fifth of the frame rate). The game refuses this in combat.
Manager.NAME_ONLY_CVAR = "nameplateShowOnlyNameForFriendlyPlayerUnits"
function Manager.ApplyNameOnly()
    DUI.AfterCombat(function()
        local f = ns.cfg.friendly
        local nameOnly = not (type(f) == "table" and f.enabled)
        if SetCVar then pcall(SetCVar, Manager.NAME_ONLY_CVAR, nameOnly and "1" or "0") end
    end, "nameplates:nameonly")
end

-- Turns friendly plates off inside instances (dungeon, raid, battleground, arena;
-- friendly.hideInInstance) through the game's own CVars. The player's own values
-- are saved in DB.Root().friendlyPlatesWas before the first change (saved, so
-- logging out inside still restores them) and restored on the way out or when the
-- setting is turned off. A CVar this client doesn't have reads nil and is skipped.
-- The game refuses these in combat.
Manager.FRIENDLY_CVARS = { "nameplateShowFriendlyPlayers", "nameplateShowFriendlyNpcs" }
function Manager.InInstance()
    if type(IsInInstance) ~= "function" then return false end
    local ok, inside = pcall(IsInInstance)
    return ok and inside == true
end
function Manager.ApplyInstanceFriends()
    DUI.AfterCombat(function()
        if type(GetCVar) ~= "function" or type(SetCVar) ~= "function" then return end
        local root = DUI.DB.Root()
        local f = ns.cfg and ns.cfg.friendly
        local hide = type(f) == "table" and f.hideInInstance == true and Manager.InInstance()
        if hide then
            if type(root.friendlyPlatesWas) ~= "table" then
                local was = {}
                for _, k in ipairs(Manager.FRIENDLY_CVARS) do
                    local ok, v = pcall(GetCVar, k)
                    if ok and type(v) == "string" then was[k] = v end
                end
                root.friendlyPlatesWas = was
            end
            for k in pairs(root.friendlyPlatesWas) do pcall(SetCVar, k, "0") end
        elseif type(root.friendlyPlatesWas) == "table" then
            for k, v in pairs(root.friendlyPlatesWas) do pcall(SetCVar, k, v) end
            root.friendlyPlatesWas = nil
        end
    end, "nameplates:instancefriends")
end

-- Sizes the game's plates to cover the Daylight UI ones (in UI units; those are
-- the UI scale times Scale). The game's plate frame takes the clicks and grows from
-- its center, where the Daylight UI plate is centered too (offset by Height). So
-- it's as wide as the bar and tall enough to reach the name above the bar in either direction from the
-- center, plus the click margin. The game refuses this in combat.
function Manager.PlateSize()
    local c = ns.cfg
    local scale = c.scale or 1
    local pad = c.clickPad or 0
    local up = (c.offsetY or 0) + c.height / 2 + c.nameSize + ns.Plate.NAME_GAP + 2
    local down = (c.offsetY or 0) - c.height / 2
    local half = math.max(math.abs(up), math.abs(down)) + pad
    return (c.width + 2 * pad) * scale, 2 * half * scale
end

Manager.DRIVER_OFF = { "DISPLAY_SIZE_CHANGED", "CVAR_UPDATE" }
-- The aura scale and debuff padding settings (lower case, as CVAR_UPDATE is compared).
Manager.SIZE_CVARS = { nameplateaurascale = true, nameplatedebuffpadding = true }
function Manager.ApplySize()
    local set = C_NamePlate and C_NamePlate.SetNamePlateSize
    if type(set) ~= "function" then return end
    DUI.AfterCombat(function()
        local w, h = Manager.PlateSize()
        pcall(set, w, h)
    end, "nameplates:size")
end

-- Stacking is the game's own setting (enemy and friendly plates separately), set
-- when asked ("stack" or "overlap"; "game" leaves it alone).
Manager.STACK_CVAR = "nameplateStackingTypes"
function Manager.ApplyStacking()
    local mode = ns.cfg and ns.cfg.stacking or "game"
    if mode == "game" then return end
    local E = Enum and Enum.NamePlateStackType
    local set = C_CVar and C_CVar.SetCVarBitfield
    if not (E and set) then return end
    local on = mode == "stack"
    DUI.AfterCombat(function()
        pcall(set, Manager.STACK_CVAR, E.Enemy, on)
        pcall(set, Manager.STACK_CVAR, E.Friendly, on and ns.cfg.stackFriendly == true)
        Manager.Restack()
    end, "nameplates:stacking")
end

-- The stacking setting changed: every plate hands its frame over again.
function Manager.Restack()
    Manager.Each(ns.Plate.PlaceStack)
end

-- Makes every plate clickable over its whole click area (Manager.OwnClicks): the
-- game's click insets can shrink it to nothing, and may have been left that way.
Manager.CLICK_INSET = 0
function Manager.ApplyClickable()
    local M, T = C_NamePlateManager, Enum and Enum.NamePlateType
    if not (M and M.SetNamePlateHitTestInsets and T) then return end
    DUI.AfterCombat(function()
        for _, kind in ipairs({ T.Enemy, T.Friendly }) do
            local i = Manager.CLICK_INSET
            if kind ~= nil then pcall(M.SetNamePlateHitTestInsets, kind, i, i, i, i) end
        end
    end, "nameplates:clickable")
end

-- The DoT tracker (DUI.Dots) runs while any plate setting needs it.
function Manager.WantDots()
    local c = ns.cfg
    DUI.Dots.Want("nameplates", c.dotTint ~= false or c.dotSkull ~= false)
end

function Manager.Start()
    Manager.startedAt = type(GetTime) == "function" and GetTime() or nil -- for a report: time into the session
    Manager.Prepare(Manager.PREPARE)
    Manager.PrepareClicks(Manager.PREPARE)
    Manager.WantDots()
    -- One mob's DoTs changed (a cast, a tick): only its plate redraws.
    local changedKey
    local function one(p)
        if p.unit and DUI.Dots.KeyOf(p.unit) == changedKey then ns.Plate.UpdateDots(p) end
    end
    DUI.On("DotsChanged", function(key)
        if key == nil then return Manager.Each(ns.Plate.UpdateDots) end
        changedKey = key
        Manager.Each(one)
    end)
    -- Total RP 3 learned a roleplay name (DUI.UnitName).
    DUI.On("NamesChanged", function() Manager.Each(ns.Plate.UpdateName) end)
    -- The veil color lives on Unit Frames > Colors.
    DUI.On("SettingChanged", function(scope, path)
        if scope ~= "UnitFrames" or path ~= "colors.dotTint" then return end
        local tint = DUI.Dots.Tint()
        Manager.Each(function(p) DUI.Dots.TintVeil(p.dotVeil, tint) end)
    end)
    Manager.ApplyClickable()
    Manager.ApplyRange()
    Manager.ApplyNameOnly()
    Manager.ApplyInstanceFriends()
    DUI.RegisterEvent("PLAYER_ENTERING_WORLD", Manager.ApplyInstanceFriends)
    DUI.RegisterEvent("ZONE_CHANGED_NEW_AREA", Manager.ApplyInstanceFriends)
    ns.Minion.Apply()
    Manager.ApplySize()
    Manager.ApplyScales()
    Manager.ApplyStacking()
    DUI.RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit) Manager.Added(unit) end)
    DUI.RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, unit) Manager.Removed(unit) end)
    -- The game hands a plate its frame inside its own NAME_PLATE_UNIT_ADDED handler,
    -- which can run after Manager.Added, so a script post-hook on its OnEvent runs right after
    -- it. Not a hook on its OnNamePlateAdded method: hooking the game's own methods
    -- has broken its calls before, and this one is hot in combat.
    local driver = NamePlateDriverFrame
    if type(driver) == "table" and type(driver.HookScript) == "function" then
        driver:HookScript("OnEvent", function(_, event, unit)
            if event == "NAME_PLATE_UNIT_ADDED" then DUI.SafeCall(Manager.FrameHandedOut, unit)
            elseif Manager.RECLAIM_EVENTS[event] then DUI.SafeCall(Manager.Reclaim) end
        end)
    end
    -- The game's driver redoes every plate's frame, size and click area on these
    -- (UpdateNamePlateOptions), handing its frames their unit and events again
    -- under the Daylight UI plates. Platynator switches them off on this client;
    -- the plate size is set here instead.
    if type(driver) == "table" and type(driver.UnregisterEvent) == "function" then
        for _, e in ipairs(Manager.DRIVER_OFF) do pcall(driver.UnregisterEvent, driver, e) end
    end
    for _, e in ipairs({ "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED", "PLAYER_ENTERING_WORLD" }) do
        DUI.RegisterEvent(e, function() Manager.ApplySize() end)
    end
    local changes = Manager.screenChanges
    DUI.RegisterEvent("UI_SCALE_CHANGED", function() changes.scale = changes.scale + 1 end)
    DUI.RegisterEvent("DISPLAY_SIZE_CHANGED", function() changes.display = changes.display + 1 end)
    DUI.RegisterEvent("PLAYER_TARGET_CHANGED", function()
        Manager.UpdateTargets()
        Manager.QueueFocus()
    end)
    DUI.RegisterEvent("UNIT_TARGET", Manager.FocusTargetChanged)
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }) do
        DUI.RegisterEvent(e, function() Manager.QueueFocus() end)
    end
    for _, e in ipairs(Manager.RECHECK_EVENTS) do
        DUI.RegisterEvent(e, function()
            Manager.Recheck()
            C_Timer.After(Manager.RECHECK_LATE, Manager.Recheck)
        end)
    end
    -- A friendly plate that's only there as your soft target hides and shows with
    -- it and with the game's friendly plate switches.
    local function softAll() Manager.Each(ns.Plate.UpdateSoftOnly) end
    local function softRecheck() Manager.Each(function(p) ns.Plate.UpdateSoftOnly(p, true) end) end
    DUI.RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED", softAll)
    DUI.RegisterEvent("PLAYER_SOFT_FRIEND_CHANGED", softAll)
    DUI.RegisterEvent("CVAR_UPDATE", function(_, name)
        if type(name) ~= "string" then return end
        name = name:lower()
        if name == Manager.STACK_CVAR:lower() then return Manager.Restack() end
        if name == Manager.NAME_ONLY_CVAR:lower() then return Manager.Each(Manager.OwnClicks) end
        -- The game sets its own plate size again when these change (its CVar callbacks).
        if Manager.SIZE_CVARS[name] then return C_Timer.After(0, Manager.ApplySize) end
        for _, cv in pairs(ns.Plate.FRIENDLY_SHOW) do
            if cv:lower() == name then return softRecheck() end
        end
    end)
    DUI.RegisterEvent("RAID_TARGET_UPDATE", function()
        Manager.Each(function(p) ns.Plate.UpdateMarker(p, true) end)
    end)
    -- Your level determines every level's color.
    DUI.RegisterEvent("PLAYER_LEVEL_UP", function() Manager.Each(ns.Plate.UpdateLevel) end)
    -- A finisher learned: execute range on "Your class" can start showing.
    -- Out of range fade asks your attacks by name, read again for a new spell.
    DUI.RegisterEvent("SPELLS_CHANGED", function()
        ns.Plate.ExecuteSpellsChanged()
        ns.Range.SpellsChanged()
    end)
    DUI.RegisterEvent("UPDATE_MOUSEOVER_UNIT", function()
        hoverChanged()
        watcher:Show()
    end)
    -- Quest marks: once per burst of quest log events (they come in runs, and each
    -- plate's check reads its tooltip).
    for _, e in ipairs({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED" }) do
        DUI.RegisterEvent(e, Manager.QuestsChanged)
    end
    -- Threat colors follow combat and your role, on the bars (not the names), once
    -- on the frame after a burst (a raid filling sends dozens of roster events).
    -- Roster, role and pet events only matter when having company or being the tank
    -- changed (what Plate.ThreatColor checks); combat always does.
    local recolorQueued, recolorForce, groupKey = false, false, nil
    local function recolor()
        recolorQueued = false
        local key = (DUI.Threat.Shared() and 1 or 0) + (DUI.Threat.IsTank() and 2 or 0)
        local force = recolorForce
        recolorForce = false
        if not force and key == groupKey then return end
        groupKey = key
        Manager.Each(ns.Plate.UpdateBarColor)
    end
    for _, e in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "UNIT_PET" }) do
        local combat = e == "PLAYER_REGEN_ENABLED" or e == "PLAYER_REGEN_DISABLED"
        DUI.RegisterEvent(e, function()
            if combat then recolorForce = true end
            if recolorQueued then return end
            recolorQueued = true
            C_Timer.After(0, recolor)
        end)
    end
    -- Someone joined or left: friendly names in the group color update
    -- (Plate.InGroupName), only on plates whose answer changed.
    DUI.RegisterEvent("GROUP_ROSTER_UPDATE", DUI.Soon(function()
        Manager.Each(function(p)
            if p.friendly and (ns.Plate.InGroupName(p) ~= (p.groupName == true)
                or (ns.Plate.Cfg(p).partyMark or "none") ~= "none" and ns.Plate.InGroup(p) ~= (p.groupMarkOn == true)) then
                ns.Plate.UpdateNameColor(p)
            end
        end)
    end))
    -- Plates already up (a reload with enemies around).
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if plain(UnitExists, unit) == true then DUI.SafeCall(Manager.Added, unit) end
    end
    C_Timer.NewTicker(Manager.SYNC_EVERY, function() DUI.SafeCall(Manager.Sync) end)
    ns.Range.Apply()
end

-- /dui platefps hides the Daylight UI plates (the game's stay hidden too) or brings them back,
-- and shows each addon's Lua time, to tell drawing cost from script cost when the
-- frame rate drops.
function Manager.HideAllForTest(hide)
    Manager.testHidden = hide
    for _, p in pairs(byUnit) do
        if Manager.Usable(p) then ns.Plate.ShowNow(p) end
    end
end

DUI.RegisterCommand("platefps", function()
    local say = DUI.Print
    Manager.HideAllForTest(not Manager.testHidden)
    say(Manager.testHidden and L["Our nameplates hidden: check your FPS, then /dui platefps again."]
        or L["Our nameplates back."])
    local P, E = C_AddOnProfiler, Enum and Enum.AddOnProfilerMetric
    if not (P and E and P.GetAddOnMetric) then return end
    local M = E.RecentAverageTime
    say("Profiler on: " .. tostring(P.IsEnabled and P.IsEnabled()))
    local n = C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns() or 0
    for i = 1, n do
        local name = C_AddOns.GetAddOnInfo(i)
        if type(name) == "string" and name:find("^DaylightUI") then
            local ok, v = pcall(P.GetAddOnMetric, name, M)
            if ok and type(v) == "number" then say(string.format("%s: %.3f ms", name, v)) end
        end
    end
    if P.GetOverallMetric then
        local ok, v = pcall(P.GetOverallMetric, M)
        if ok and type(v) == "number" then say(string.format(L["All addons: %.3f ms"], v)) end
    end
end, L["/dui platefps - hide or show our nameplates and print addon time (testing)"])

-- /dui platedebug: dumps your target plate's click area, to find out why a plate
-- can't be clicked. Output stays in English since it's for debugging.
DUI.RegisterCommand("platedebug", function()
    local say = DUI.Print
    local p
    for _, q in pairs(byUnit) do
        if q.isTarget then p = q end
    end
    if not p then
        say(L["Target something with a nameplate first."])
        return
    end
    local np = p.nameplate
    local function rect(f)
        local ok, l, b, w, h = pcall(f.GetRect, f)
        if not ok or not l then return "no rect" end
        return string.format("%.0f,%.0f %.0fx%.0f", l, b, w, h)
    end
    say("Game's plate (takes the clicks) " .. rect(np) .. "; ours " .. rect(p) .. "; our bar " .. rect(p.hp))
    say("Stacking box " .. rect(p.stack))
    local okC, can = pcall(np.CanChangeHitTestPoints, np)
    say("Can set the click area: " .. tostring(okC and can))
    local M, T = C_NamePlateManager, Enum and Enum.NamePlateType
    if M and M.GetNamePlateHitTestInsets and T then
        for name, kind in pairs({ enemy = T.Enemy, friendly = T.Friendly }) do
            local ok, l, r, t, b = pcall(M.GetNamePlateHitTestInsets, kind)
            say(string.format("Click insets, %s: %s %s %s %s", name, tostring(ok and l), tostring(r), tostring(t), tostring(b)))
        end
    end
    if C_NamePlate and C_NamePlate.GetNamePlateSize then
        local ok, w, h = pcall(C_NamePlate.GetNamePlateSize)
        say("Plate size: " .. tostring(ok and w) .. " x " .. tostring(h))
    end
end, L["/dui platedebug - your target's nameplate's click area"])

-- /dui platecheck, run while a plate is missing. Compares the game's plates with
-- the Daylight UI ones and lists what could hide each: no plate on it, the plate
-- not showing, or the game's plate itself. Every read is guarded and a secret just says so, so
-- it works in combat. Output stays in English.
Manager.CHECK_DETAIL = 6 -- plates listed in full; a crowd would flood the chat

local function asked(f, method)
    local ok, v = pcall(function() return f[method](f) end)
    if not ok then return "?" end
    if isSecret(v) then return "secret" end
    if type(v) == "number" then return string.format("%.2f", v) end
    return tostring(v)
end

local function where(f)
    local ok, l, b, w, h = pcall(function() return f:GetRect() end)
    if not ok then return "can't measure" end -- the game refuses; says nothing about the plate
    if type(l) == "nil" then return "no rect" end
    if isSecret(l) or isSecret(b) or isSecret(w) or isSecret(h) then
        return "secret"
    end
    return string.format("%.0f,%.0f %.0fx%.0f", l, b, w, h)
end

local function state(f)
    return string.format("shown=%s visible=%s alpha=%s effective=%s strata=%s scale=%s rectValid=%s box=%s",
        asked(f, "IsShown"), asked(f, "IsVisible"), asked(f, "GetAlpha"), asked(f, "GetEffectiveAlpha"),
        asked(f, "GetFrameStrata"), asked(f, "GetEffectiveScale"), asked(f, "IsRectValid"), where(f))
end

-- One plate's lines, and whether it looks wrong.
function Manager.CheckOne(unit, np)
    if forbidden(np) then return { unit .. ": the game keeps this plate from addons (forbidden)" }, true end
    local attack = plain(UnitCanAttack, "player", unit)
    local kind = attack == true and "enemy" or attack == false and "friendly" or "unknown"
    local player = plain(UnitIsPlayer, unit)
    local head = string.format("%s: %s, player=%s, minion=%s, target=%s", unit, kind, tostring(player),
        tostring(plain(UnitIsMinion, unit)), tostring(plain(UnitIsUnit, unit, "target")))
    local lines = { head, "  game plate " .. state(np) }
    local wrong = asked(np, "IsVisible") ~= "true" or asked(np, "GetAlpha") == "0.00"
        or asked(np, "GetEffectiveAlpha") == "0.00"
    local okUp, up = pcall(function() return np:GetParent() end)
    if okUp and type(up) == "table" then
        lines[#lines + 1] = "  above it " .. asked(up, "GetName") .. " " .. state(up)
    end
    local uf = np.UnitFrame
    if type(uf) == "table" then
        local okP, parent = pcall(uf.GetParent, uf)
        lines[#lines + 1] = string.format("  game frame onPlate=%s held=%s clicks=%s", tostring(okP and parent == np),
            tostring(held[uf] == true), clickOf[np] and "ours" or "game's")
    end
    local p = byUnit[unit]
    if not p then
        lines[#lines + 1] = "  no plate of ours, refused=" .. tostring(refused[np] == true)
        return lines, true
    end
    lines[#lines + 1] = "  ours " .. state(p)
    lines[#lines + 1] = string.format("  on this plate=%s friendly=%s nameOnly=%s minion=%s bar=%s name=%s group=%s",
        tostring(p.nameplate == np), tostring(p.friendly), tostring(p.laid and p.laid.nameOnly), tostring(p.minion),
        asked(p.hp, "IsShown"), asked(p.name, "IsShown"), tostring(p.sizeGroup))
    if p.nameplate ~= np or asked(p, "IsVisible") ~= "true" or asked(p, "GetAlpha") == "0.00" then wrong = true end
    return lines, wrong
end

-- detail: how many plates are listed in full (CHECK_DETAIL by default).
function Manager.CheckLines(detail)
    local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    if not get then return { "No nameplate API." } end
    local secure = issecure and issecure() or false
    local wrongs, fine, count, ours = {}, {}, 0, 0
    for _ in pairs(byUnit) do ours = ours + 1 end
    for i = 1, Manager.PREPARE do
        local unit = "nameplate" .. i
        local ok, np = pcall(get, unit, secure)
        if ok and type(np) == "table" then
            count = count + 1
            local lines, wrong = Manager.CheckOne(unit, np)
            local into = wrong and wrongs or fine
            into[#into + 1] = lines
        end
    end
    local c = ns.cfg or {}
    local out = {
        string.format("Daylight UI %s. Game plates %d, ours %d, spare %d, hidden by platefps=%s", tostring(DUI.VERSION),
            count, ours, #spare, tostring(Manager.testHidden == true)),
        string.format("Settings: scale=%s offsetY=%s dimOthers=%s minions=%s friendly bars=%s", tostring(c.scale),
            tostring(c.offsetY), tostring(c.dimOthers), tostring(c.minions),
            tostring(type(c.friendly) == "table" and c.friendly.enabled)),
    }
    local words = {}
    for _, name in ipairs({ "nameplateMinAlpha", "nameplateMaxAlpha", "nameplateOccludedAlphaMult", "nameplateGlobalScale",
        "nameplateMinScale", "nameplateMaxScale", "nameplateSelectedScale", "nameplateMaxDistance" }) do
        local ok, v = pcall(C_CVar.GetCVar, name)
        words[#words + 1] = name:gsub("^nameplate", "") .. "=" .. tostring(ok and v)
    end
    -- The stacking setting is a bitfield whose raw value isn't text (the copy box
    -- showed nothing at all with it in), so it's read bit by bit.
    local E = Enum and Enum.NamePlateStackType
    local getBit = C_CVar and C_CVar.GetCVarBitfield
    if E and type(getBit) == "function" then
        local function bit(i) return tostring(plain(getBit, Manager.STACK_CVAR, i)) end
        words[#words + 1] = "Stacking enemy=" .. bit(E.Enemy) .. " friendly=" .. bit(E.Friendly)
    end
    out[#out + 1] = "Game: " .. table.concat(words, " ")
    local Bug = DUI.BugReport
    if type(Bug) == "table" and type(Bug.PlateCache) == "function" then
        local tainted = Bug.PlateCache()
        out[#out + 1] = #tainted > 0 and ("Plate settings tainted: " .. table.concat(tainted, ", "))
            or "Plate settings: clean"
    end
    local left = detail or Manager.CHECK_DETAIL
    for _, list in ipairs({ wrongs, fine }) do
        for _, lines in ipairs(list) do
            if left > 0 then
                left = left - 1
                for _, line in ipairs(lines) do out[#out + 1] = line end
            end
        end
    end
    out[#out + 1] = #wrongs > 0 and string.format("LOOKS WRONG: %d plate(s).", #wrongs) or "Nothing looks wrong."
    return out
end

DUI.RegisterCommand("platecheck", function()
    for _, line in ipairs(Manager.CheckLines()) do DUI.Print(line) end
end, L["/dui platecheck - run while a nameplate is missing, and send us what it prints"])

-- /dui plateprobe: run after platecheck while plates are missing. Tests one
-- suspect: the frame handed to the game for spacing plates apart (Plate.Install,
-- p.stack) went bad and the game's stacking pushed every plate out of view. Every
-- plate gets its own frame back (Plate.Detach doesn't do this; it hides the
-- stacking frame, as EllesmereUI does). A plate that comes into view afterwards gets
-- a Daylight UI plate again;
-- /reload restores everything.
function Manager.Probe()
    local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    if not get then return 0, 0 end
    local secure = issecure and issecure() or false
    local done, failed = 0, 0
    for i = 1, Manager.PREPARE do
        local ok, np = pcall(get, "nameplate" .. i, secure)
        if ok and type(np) == "table" and not forbidden(np) then
            if pcall(np.SetStackingBoundsFrame, np, np) then done = done + 1 else failed = failed + 1 end
        end
    end
    return done, failed
end

DUI.RegisterCommand("plateprobe", function()
    local done, failed = Manager.Probe()
    DUI.Print(string.format("plateprobe: %d changed, %d refused.", done, failed))
    DUI.Print(L["Did the nameplates come back within a second? Tell the Daylight UI team yes or no, then /reload."])
end, L["/dui plateprobe - run after /dui platecheck while nameplates are missing, and say if they come back"])

-- /dui platefix: run while every plate is invisible. In that state the game's
-- plates exist, are shown at alpha 1, yet nothing on them draws (even a texture
-- made directly on one, with the Daylight UI plates hidden too); /reload fixes it, and it never
-- happens without Daylight UI. Each run undoes one thing Daylight UI does to the game's
-- plates and asks whether they're back: the first step that brings them back
-- names the cause and fixes it without a reload. Out of combat only (the game
-- refuses these settings in combat). Chat output stays in English since players
-- send it in with bug reports.
Manager.FIX_STEPS = 7
Manager.FIX_GAP = 0.5 -- seconds the game's plates stay off in step 3
Manager.FIX_BACK = 1 -- seconds until the Daylight UI plates go back on after step 3
Manager.FIX_SHOW_CVARS = { "nameplateShowEnemies", "nameplateShowFriendlyPlayers", "nameplateShowFriendlyNpcs" }

local function cvar(name)
    if type(GetCVar) ~= "function" then return nil end
    local ok, v = pcall(GetCVar, name)
    return ok and type(v) == "string" and v or nil
end

local function gameDefault(name)
    local fn = C_CVar and C_CVar.GetCVarDefault
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, name)
    return ok and type(v) == "string" and v or nil
end

-- Hands every plate back to the game and takes none again until told to.
local function handBack()
    Manager.fixPaused = true
    local units = {}
    for unit in pairs(byUnit) do units[#units + 1] = unit end
    for _, unit in ipairs(units) do
        local p = byUnit[unit]
        local np, uf = p.nameplate, p.gameFrame
        DUI.SafeCall(Manager.Removed, unit)
        DUI.SafeCall(Manager.GiveBackFrame, uf, np)
    end
    return #units
end

-- Switches the game's plates off and on so it rebuilds them, then puts the
-- Daylight UI plates back a moment later.
local function offAndOn()
    local was = {}
    for _, name in ipairs(Manager.FIX_SHOW_CVARS) do
        local v = cvar(name)
        if v then
            was[name] = v
            pcall(SetCVar, name, "0")
        end
    end
    C_Timer.After(Manager.FIX_GAP, function()
        for name, v in pairs(was) do pcall(SetCVar, name, v) end
        C_Timer.After(Manager.FIX_BACK, function()
            Manager.fixPaused = nil
            DUI.SafeCall(Manager.Recheck)
        end)
    end)
end

-- Steps 5 to 7. Step 3 showed the game's rebuilt plates draw until the Daylight UI
-- plates go back on, so each of these rebuilds them the same way and then puts
-- the plates back with one part of that left out (Manager.fixWithout): "stack"
-- hands the game no stacking frame, "hide" leaves the game's own frame
-- showing underneath, "pool" uses plates built just now instead of the ones
-- from login. One part at a time, so the step that works names the part.
local function backWithout(part)
    handBack()
    Manager.fixWithout = part
    if part == "pool" then return Manager.FreshPool(offAndOn) end
    offAndOn()
end

Manager.FIX = {
    -- 1. Reapply the plate size and click insets given to the game.
    function()
        local set = C_NamePlate and C_NamePlate.SetNamePlateSize
        if type(set) == "function" then pcall(set, Manager.PlateSize()) end
        Manager.ApplyClickable()
        Manager.Each(Manager.OwnClicks)
        return "the plate size and click area set again"
    end,
    -- 2. Hand every game plate back as it was (Daylight UI's off, its own frame back on it
    -- with its events and click area), and take none again until step 3 is done.
    function()
        return string.format("%d plates handed back to the game", handBack())
    end,
    -- 3. Toggle the game's plates off and on so it rebuilds them, then put Daylight UI's back.
    function()
        offAndOn()
        return "the game's plates switched off and on (Daylight UI's go back on a second later)"
    end,
    -- 4. Reset the plate settings Daylight UI changes to the game's defaults (Daylight UI sets its
    -- own again on the next /reload).
    function()
        local names = { Manager.RANGE_CVAR, Manager.NAME_ONLY_CVAR, ns.Minion.CVAR }
        for _, k in ipairs(Manager.SCALE_CVARS) do names[#names + 1] = k end
        local done = 0
        for _, name in ipairs(names) do
            local v = gameDefault(name)
            if v and pcall(SetCVar, name, v) then done = done + 1 end
        end
        return string.format("%d plate settings back to the game's defaults", done)
    end,
    -- 5. Rebuilt, then back on with no stacking frame handed to the game.
    function()
        backWithout("stack")
        return "the game's plates rebuilt, Daylight UI's back on without their stacking frame (wait two seconds)"
    end,
    -- 6. Rebuilt, then back on with the game's own frame left showing underneath.
    function()
        backWithout("hide")
        return "the game's plates rebuilt, Daylight UI's back on over the game's own, which stay visible "
            .. "(wait two seconds, and say which of the two you see)"
    end,
    -- 7. Rebuilt, then back on using plates built just now.
    function()
        backWithout("pool")
        return "the game's plates rebuilt, Daylight UI's back on with newly built plates (wait two seconds)"
    end,
}

-- The report once a step brought them back (or none did): which step, where and
-- how long into the session, other loaded addons, the game's plate settings, and
-- the plates as they were before step 1 while still invisible. One text, short
-- enough for one Discord message.
Manager.REPORT_PLATES = 2 -- plates listed in full (a report holds 4000 characters)
Manager.REPORT_MAX = 3800
Manager.REPORT_ADDONS = 40
Manager.REPORT_CVARS = {
    "nameplateShowAll", "nameplateShowEnemies", "nameplateShowFriendlyPlayers", "nameplateShowFriendlyNpcs",
    "nameplateShowOnlyNameForFriendlyPlayerUnits", "nameplateMinScale", "nameplateMaxScale", "nameplateSelectedScale",
    "nameplateSize", "nameplateStyle", "nameplateSimplifiedTypes", "nameplateMotionSpeed", "nameplateShowEnemyMinions",
}

-- How the game is shown: screen, window mode, graphics card, frame caps, and the
-- UI scale three ways (the game's setting, whether it's used, and what UIParent
-- really has, which Daylight UI keeps at its own saved value), with how often
-- the scale and the screen changed this session. Lined up across reports, this
-- shows what the players who lose their plates have in common.
Manager.screenChanges = { scale = 0, display = 0 }

function Manager.ReportScreen()
    local words = {}
    local function add(label, v)
        if v ~= nil then words[#words + 1] = label .. "=" .. tostring(v) end
    end
    if type(GetPhysicalScreenSize) == "function" then
        local ok, w, h = pcall(GetPhysicalScreenSize)
        if ok and type(w) == "number" and type(h) == "number" then words[#words + 1] = string.format("%dx%d", w, h) end
    end
    if type(GetMonitorCount) == "function" then
        local ok, n = pcall(GetMonitorCount)
        if ok then add("monitors", n) end
    end
    add("maximized", cvar("gxMaximize"))
    add("windowed", cvar("gxWindow"))
    add("api", cvar("gxapi"))
    add("maxFPS", cvar("maxFPS"))
    add("background", cvar("maxFPSBk"))
    local V = C_VideoOptions
    if type(V) == "table" and type(V.GetGxAdapterInfo) == "function" then
        local ok, list = pcall(V.GetGxAdapterInfo)
        if ok and type(list) == "table" then
            local names = {}
            for _, a in ipairs(list) do
                if type(a) == "table" and type(a.name) == "string" then names[#names + 1] = a.name end
            end
            if #names > 0 then words[#words + 1] = "GPU " .. table.concat(names, " / ") end
        end
    end
    local scale = {}
    scale[#scale + 1] = "uiScale=" .. tostring(cvar("uiScale"))
    scale[#scale + 1] = "useUiScale=" .. tostring(cvar("useUiScale"))
    local ok, ui = pcall(UIParent.GetScale, UIParent)
    scale[#scale + 1] = "UIParent=" .. (ok and type(ui) == "number" and string.format("%.2f", ui) or "?")
    local c = Manager.screenChanges
    return {
        "Screen: " .. table.concat(words, " "),
        string.format("Scale: %s, scale changes %d, display changes %d", table.concat(scale, " "), c.scale, c.display),
    }
end

-- Where the player is and what else is running, at the time of asking.
function Manager.ReportWorld()
    local out = {}
    local up = Manager.startedAt and type(GetTime) == "function" and (GetTime() - Manager.startedAt) / 60
    local zone = type(GetRealZoneText) == "function" and plain(GetRealZoneText) or nil
    local kind
    if type(GetInstanceInfo) == "function" then
        local ok, _, instanceType = pcall(GetInstanceInfo)
        kind = ok and instanceType or nil
    end
    out[#out + 1] = string.format("%s min since login or /reload, zone %s (%s), restricted=%s",
        up and string.format("%.0f", up) or "?", tostring(zone), tostring(kind), tostring(DUI.Restricted() == true))
    local words = {}
    for _, name in ipairs(Manager.REPORT_CVARS) do
        local v = cvar(name)
        if v then words[#words + 1] = name:gsub("^nameplate", "") .. "=" .. v end
    end
    out[#out + 1] = "More: " .. table.concat(words, " ")
    for _, line in ipairs(Manager.ReportScreen()) do out[#out + 1] = line end
    local A = C_AddOns
    if A and A.GetNumAddOns and A.GetAddOnInfo and A.IsAddOnLoaded then
        local names, more = {}, 0
        for i = 1, A.GetNumAddOns() do
            local ok, name = pcall(A.GetAddOnInfo, i)
            if ok and type(name) == "string" and not name:find("^DaylightUI") and A.IsAddOnLoaded(name) then
                if #names < Manager.REPORT_ADDONS then names[#names + 1] = name else more = more + 1 end
            end
        end
        out[#out + 1] = "Other addons: " .. (#names > 0 and table.concat(names, ", ") or "none")
            .. (more > 0 and string.format(" +%d more", more) or "")
    end
    return out
end

-- step: the one that brought them back, nil if none did.
function Manager.FixReport(step)
    local run = Manager.fixRun or { did = {}, before = {} }
    local out = { string.format("Daylight UI %s platefix: %s", tostring(DUI.VERSION),
        step and string.format("step %d brought them back", step) or "no step brought them back") }
    for i, did in ipairs(run.did) do out[#out + 1] = string.format("  %d. %s", i, did) end
    for _, line in ipairs(run.world or Manager.ReportWorld()) do out[#out + 1] = line end
    out[#out + 1] = "Before step 1:"
    for _, line in ipairs(run.before) do out[#out + 1] = line end
    return Manager.Printable(table.concat(out, "\n"), Manager.REPORT_MAX)
end

-- Text an edit box shows as it is: control bytes become "?", a "|" is doubled
-- (else the box reads it as a color or link code), broken UTF-8 becomes "?", and
-- a cut at max bytes never splits a character. Any of these left the copy box empty.
function Manager.Printable(text, max)
    local out, len, i = {}, 0, 1
    while i <= #text do
        local b = text:byte(i)
        local n = b < 0x80 and 1 or (b >= 0xF0 and b < 0xF5) and 4 or (b >= 0xE0 and b < 0xF0) and 3
            or (b >= 0xC2 and b < 0xE0) and 2 or 0
        local piece
        if n == 1 then
            piece = (b == 124 and "||") or (((b < 32 and b ~= 10) or b == 127) and "?") or string.char(b)
        elseif n > 1 then
            piece = text:sub(i, i + n - 1)
            for k = 2, n do
                local c = piece:byte(k)
                if not c or c < 0x80 or c > 0xBF then piece = nil break end
            end
        end
        if not piece then piece, n = "?", 1 end
        if max and len + #piece > max then break end
        out[#out + 1] = piece
        len = len + #piece
        i = i + n
    end
    return table.concat(out)
end

-- Shows the report in a copy box (the profiles' one) and ends the round.
function Manager.FixDone(step)
    local text = Manager.FixReport(step)
    Manager.fixStep, Manager.fixRun = nil, nil
    DUI.Profiles.ShowText(L["Nameplate report"], L["Ctrl+C to copy, then paste it in a bug report on the Daylight UI Discord. "
        .. "After that, /reload."], text)
    -- In chat too, so a screenshot still carries it if the box can't be copied.
    for line in string.gmatch(text, "[^\n]+") do DUI.Print(line) end
    return text
end

-- One step per run; after the last, the next run starts over at 1.
function Manager.Fix()
    if InCombatLockdown() then return "platefix: leave combat first, then /dui platefix again." end
    local n = (Manager.fixStep or 0) + 1
    if n > Manager.FIX_STEPS then
        Manager.fixWithout = nil -- nothing helped, so the next plates are whole again
        Manager.FixDone(nil)
        return "platefix: that was every step and none brought them back. Copy the text in the box and send it to the "
            .. "Daylight UI team, then /reload."
    end
    -- Snapshot the plates now, still invisible, before anything is undone.
    if n == 1 then
        Manager.fixRun = { did = {}, before = Manager.CheckLines(Manager.REPORT_PLATES), world = Manager.ReportWorld() }
    end
    Manager.fixStep = n
    local ok, did = pcall(Manager.FIX[n])
    if not ok then did = "failed (" .. tostring(did) .. ")" end
    if Manager.fixRun then Manager.fixRun.did[n] = did end
    return string.format("platefix %d/%d: %s. Are the nameplates back? Yes: /dui platefix yes. "
        .. "No: /dui platefix again for the next step.", n, Manager.FIX_STEPS, did)
end

DUI.RegisterCommand("platefix", function(rest)
    if string.lower(rest or "") ~= "yes" then return DUI.Print(Manager.Fix()) end
    if not Manager.fixStep then return DUI.Print(L["Run /dui platefix first, while the nameplates are invisible."]) end
    Manager.FixDone(Manager.fixStep)
    DUI.Print(L["Copy the text in the box and send it to the Daylight UI team, then /reload."])
end, L["/dui platefix - run while nameplates are invisible, one step each time, and say which step brought them back"])
