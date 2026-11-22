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
local Report = DUI.PlateReport
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

-- Off the game's plate, back to the spares. The game plate keeps its stacking
-- frame but it's emptied (hidden, pinned nowhere), as EllesmereUI does, so a unit
-- the game puts on that plate next is spaced by nothing left from this one.
function Manager.Release(p)
    if forbidden(p) then return end
    local s = p.stack
    if s and not forbidden(s) then
        s:ClearAllPoints()
        s:Hide()
        s.y = nil -- pinned again on the next PlaceStack
    end
    p:Hide()
    p:ClearAllPoints()
    p:SetParent(home)
    p.nameplate, p.stack = nil, nil
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
    DUI.SafeCall(uf.UnregisterAllEvents, uf)
    quieted[uf] = true
    local cast = uf.castBar
    if type(cast) ~= "table" and type(uf.CastBarsContainer) == "table" then cast = uf.CastBarsContainer.castBar end
    if type(cast) == "table" and type(cast.UnregisterAllEvents) == "function" and not forbidden(cast) then
        DUI.SafeCall(cast.UnregisterAllEvents, cast)
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
    DUI.SafeCall(uf.UpdateHitTestArea, uf, NamePlateSetupOptions)
end

-- Runs fn like DUI.SafeCall (an error reaches the error log, the caller goes on),
-- and also hands back the error's first line, so /dui platefix can say what failed.
function Manager.Try(fn, ...)
    local ok, err = pcall(fn, ...)
    if ok then return true end
    DUI.SafeCall(error, err, 0)
    return false, string.sub(string.match(tostring(err), "^[^\n]*") or "", 1, 120)
end

-- Gives a held frame back to the game: its events, its widgets and, when it's on
-- a plate (nameplate given), its spot and click area there, as the game sets
-- them when it hands a frame out. Returns false and the error when the game
-- refused the move: the frame then stays held, so a later try still gives it back.
function Manager.GiveBackFrame(uf, nameplate)
    if type(uf) ~= "table" or not uf.SetParent or forbidden(uf) or not held[uf] then return end
    if quieted[uf] then
        quieted[uf] = nil
        for _, e in ipairs(Manager.LOAD_EVENTS) do DUI.SafeCall(uf.RegisterEvent, uf, e) end
        -- CompactUnitFrame_OnLoad is only the frame's baseline. The nameplate
        -- adds two unit events and two global events in OnUnitSet, while
        -- CompactUnitFrame_SetUnit registers its per-unit events. If a held
        -- frame is returned without being recycled through SetUnit first (the
        -- failed-install and platefix paths), restore those as well. Only the
        -- event list is redone: CompactUnitFrame_RegisterEvents would also set
        -- the game frame's OnEvent script from addon code.
        if uf.unit then
            if type(CompactUnitFrame_UpdateUnitEvents) == "function" then
                DUI.SafeCall(CompactUnitFrame_UpdateUnitEvents, uf)
            end
            DUI.SafeCall(uf.RegisterUnitEvent, uf, "UNIT_FACTION", uf.unit, "player")
            DUI.SafeCall(uf.RegisterUnitEvent, uf, "NAME_PLATE_UNIT_BEHIND_CAMERA_CHANGED", uf.unit)
            DUI.SafeCall(uf.RegisterEvent, uf, "PLAYER_FOCUS_CHANGED")
            DUI.SafeCall(uf.RegisterEvent, uf, "RAID_TARGET_UPDATE")
        end
    end
    moveKeepers(uf, uf)
    if type(nameplate) == "table" and nameplate.UnitFrame == uf and not forbidden(nameplate) then
        if uf:GetParent() ~= nameplate then
            local ok, err = Manager.Try(function()
                uf:SetParent(nameplate)
                uf:ClearAllPoints()
                uf:SetAllPoints(nameplate)
            end)
            if not ok then return false, err end
        end
        gameClicks(nameplate)
    end
    held[uf] = nil
    return true
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

-- The frame the game spaces a plate by, kept the same way: one per game plate,
-- on it for good, sized by whichever Daylight UI plate is there (Plate.PlaceStack).
-- A game plate keeps pointing at the last frame it was handed, so a frame that
-- travelled on with a Daylight UI plate left the old game plate spaced by
-- something sitting on another plate. The game measures the frame by what's
-- drawn in it, not its size, so it carries an unseen fill.
local stackOf = setmetatable({}, { __mode = "k" }) -- game plate -> its stacking frame
local stackSpare = {}
Manager.stackOf = stackOf

local function newStack()
    local f = CreateFrame("Frame")
    f.fill = f:CreateTexture(nil, "BACKGROUND")
    f.fill:SetColorTexture(0, 0, 0, 0)
    f.fill:SetAllPoints(f)
    return f
end

function Manager.PrepareStacks(n)
    for _ = 1, n do stackSpare[#stackSpare + 1] = newStack() end
end

-- This game plate's stacking frame, or nil once the game has closed it to addons.
function Manager.StackFrame(nameplate)
    local f = stackOf[nameplate]
    if not f then
        f = table.remove(stackSpare) or newStack()
        stackOf[nameplate] = f
        f:SetParent(nameplate)
    end
    if forbidden(f) then return nil end
    return f
end

function Manager.Unclickable(unit)
    if plain(UnitNameplateShowsWidgetsOnly, unit) == true then return true end
    if plain(UnitIsPlayer, unit) ~= true or plain(UnitIsFriend, "player", unit) ~= true then return false end
    return GetCVar(Manager.NAME_ONLY_CVAR) == "1"
end

function Manager.OwnClicks(p)
    local np, unit = p.nameplate, p.unit
    if type(np) ~= "table" or not unit or forbidden(np) or Manager.fixWithout == "hide" then return end
    if np:CanChangeHitTestPoints() ~= true then return end
    if Manager.Unclickable(unit) then
        DUI.SafeCall(np.ClearAllHitTestPoints, np)
    else
        DUI.SafeCall(np.SetAllHitTestPoints, np, clickFrame(np))
    end
end

local refused = setmetatable({}, { __mode = "k" }) -- game plates a Daylight UI plate can't go on; the game's stays (Added)

function Manager.Added(unit)
    if Manager.fixPaused then return end -- /dui platefix has handed plates back to the game for now
    if plain(UnitIsUnit, unit, "player") == true then return end
    local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    if not get then return end
    local nameplate = get(unit, issecure and issecure() or false)
    if type(nameplate) ~= "table" then return end
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
        -- An earlier handout may already have parked the game's current frame.
        DUI.SafeCall(function()
            if not forbidden(nameplate) then Manager.GiveBackFrame(nameplate.UnitFrame, nameplate) end
        end)
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
        DUI.SafeCall(ns.Plate.Uninstall, p)
        Manager.Release(p)
    else
        pcall(p.Hide, p)
    end
end

-- Takes every frame under a Daylight UI plate off its plate again and sets each
-- click area again. The game's options update (UpdateNamePlateOptions) puts its
-- own plate size and click area back on every plate.
Manager.RECLAIM_EVENTS = { DISPLAY_SIZE_CHANGED = true, VARIABLES_LOADED = true, CVAR_UPDATE = true }
function Manager.Reclaim()
    -- The game's options update also put its own plate size on: Daylight UI's
    -- goes back, as EllesmereUI does after UpdateNamePlateOptions.
    Manager.ApplySize(true)
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
        nameplate = get(unit, issecure and issecure() or false)
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

function Manager.ToggleFlattening()
    local plate = ns.Plate
    plate.flatteningOff = not plate.flatteningOff
    Manager.Each(plate.ApplyFlattening)
    for _, p in ipairs(spare) do
        if not forbidden(p) then DUI.SafeCall(plate.ApplyFlattening, p) end
    end
    return plate.flatteningOff
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

-- An NPC that turns attackable (or stops being so) may send nothing on its plate's
-- own events, so a plate set up as friendly would stay name-only or hidden.
-- unit can be any token for it ("target" too); late checks once more a moment
-- after, as the answer can lag behind the event.
function Manager.RecheckUnit(unit, late)
    if isSecret(unit) or type(unit) ~= "string" then return end
    local p = byUnit[unit]
    if not p then
        for token, q in pairs(byUnit) do
            if plain(UnitIsUnit, token, unit) == true then p = q break end
        end
    end
    if not (p and Manager.StillUsable(p)) then return end
    local token = p.unit
    ns.Plate.UpdateFriendly(p)
    if late then
        C_Timer.After(Manager.RECHECK_LATE, function()
            if byUnit[token] == p and Manager.StillUsable(p) then DUI.SafeCall(ns.Plate.UpdateFriendly, p) end
        end)
    end
end

-- Reconciles the plates with what the game shows now, as a /reload would, after
-- a death, a resurrection or a loading screen (Manager.Recheck). A plate left on
-- a unit that's gone, or a unit with no plate, would stay wrong until it left
-- view. Correct plates are left alone; only differences do any work.
function Manager.Sync()
    if Manager.fixPaused then return end
    local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    if not get then return end
    local secure = issecure and issecure() or false
    for unit, p in pairs(byUnit) do
        if plain(UnitExists, unit) == false or get(unit, secure) ~= p.nameplate then Manager.Removed(unit) end
    end
    for i = 1, Manager.PREPARE do
        local unit = "nameplate" .. i
        if not byUnit[unit] and plain(UnitExists, unit) == true then
            local np = get(unit, secure)
            if type(np) == "table" and not refused[np] then DUI.SafeCall(Manager.Added, unit) end
        end
    end
end

-- Settings or style changed: redo every plate.
function Manager.Refresh()
    ns.Plate.gen = ns.Plate.gen + 1 -- every plate is laid out and marked again
    Manager.WantDots()
    if ns.Combo then ns.Combo.gen = ns.Combo.gen + 1 end -- and the combo pips
    Manager.ApplySize()
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

-- What the plates take from the General settings and the screen, as one string.
-- A repaint with the same answer (the screen or UI scale events fire one with
-- nothing new for plates) leaves every plate and the game's plate settings alone.
local function sigOf(v, out)
    if type(v) ~= "table" then
        out[#out + 1] = tostring(v)
        return
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        out[#out + 1] = tostring(k)
        sigOf(v[k], out)
    end
end

-- A shared font or bar can arrive after login without a setting changing. Only the
-- files the plates really draw count, so a texture registered under a picked font's
-- name doesn't rebuild every plate.
local function sharedFiles(out)
    local Style, Media = DUI.Style, DUI.Media
    out[#out + 1] = tostring(Style.SharedBar()) .. tostring(Style.SharedBack())
    for id, s in pairs(Media.SLOTS) do
        if s.scope == "Nameplates" then
            local file
            if s.kind == "font" then file = Style.FontFile(id)
            elseif s.kind == "back" then file = Style.SharedBack(id)
            else file = Style.SharedBar(id) end
            out[#out + 1] = id .. "=" .. tostring(file)
        end
    end
end

function Manager.StyleSig()
    local out = {}
    local g = DUI.DB.General()
    sigOf(g, out)
    sharedFiles(out)
    out[#out + 1] = tostring(UIParent:GetEffectiveScale())
    out[#out + 1] = tostring(DUI.Pixel.perfect)
    out[#out + 1] = tostring(DUI.Style.FONT)
    return table.concat(out, "|")
end

-- The core's repaint: every plate again only when something plates draw from changed.
function Manager.StyleChanged()
    local sig = Manager.StyleSig()
    if sig ~= Manager.styleSig then
        Manager.styleSig = sig
        return Manager.Refresh()
    end
    -- The client can change the UI scale in a fight, and Daylight UI only puts its own
    -- back afterwards. A plate that came up in between was laid out at the passing scale,
    -- while the look as a whole reads the same as before, so lay out just those again.
    local ui = UIParent:GetEffectiveScale()
    Manager.Each(function(p)
        local L = p.unit and p.laid
        if L and L.base ~= ui * (ns.Plate.Cfg(p).scale or 1) then ns.Plate.Layout(p) end
    end)
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
    if not get then
        Manager.Each(ns.Plate.UpdateHover)
        return
    end
    local np, on = get("mouseover", issecure and issecure() or false), nil
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

-- Writes one of the game's plate settings only when it differs: every write
-- runs the game's CVAR_UPDATE handlers across the whole UI.
function Manager.SetCVar(name, value)
    if type(SetCVar) ~= "function" then return end
    value = tostring(value)
    if type(GetCVar) == "function" then
        if GetCVar(name) == value then return end
    end
    DUI.SafeCall(SetCVar, name, value)
end

-- Plate distance is the game's own setting, which it refuses to change in combat.
Manager.RANGE_CVAR = "nameplateMaxDistance"
function Manager.ApplyRange()
    DUI.AfterCombat(function()
        Manager.SetCVar(Manager.RANGE_CVAR, ns.cfg.range)
    end, "nameplates:range")
end

-- The game's own plate frames never change size: its distance scaling and target
-- zoom are pinned to 1 (Daylight UI zooms the target itself, in one step in
-- Plate.ApplyScale), so nothing gets resized or restacked underneath and its click
-- area doesn't grow on the target. Set once at login, as EllesmereUI does. The
-- game refuses these in combat.
Manager.SCALE_CVARS = { "nameplateMinScale", "nameplateMaxScale", "nameplateSelectedScale" }
function Manager.ApplyScales()
    DUI.AfterCombat(function()
        for _, k in ipairs(Manager.SCALE_CVARS) do Manager.SetCVar(k, "1") end
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
        Manager.SetCVar(Manager.NAME_ONLY_CVAR, nameOnly and "1" or "0")
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
    return IsInInstance() == true
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
                    local v = GetCVar(k)
                    if type(v) == "string" then was[k] = v end
                end
                root.friendlyPlatesWas = was
            end
            for k in pairs(root.friendlyPlatesWas) do Manager.SetCVar(k, "0") end
        elseif type(root.friendlyPlatesWas) == "table" then
            for k, v in pairs(root.friendlyPlatesWas) do Manager.SetCVar(k, v) end
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

-- The aura scale and debuff padding settings (lower case, as CVAR_UPDATE is compared).
Manager.SIZE_CVARS = { nameplateaurascale = true, nameplatedebuffpadding = true }
-- Written only when the size changed, unless force says the game has just put
-- its own size on (its options update, the aura CVars). The game keeps the size
-- it was given, so the same one again would only make it lay its plates out.
local sizeW, sizeH
function Manager.ApplySize(force)
    local set = C_NamePlate and C_NamePlate.SetNamePlateSize
    if type(set) ~= "function" then return end
    if force then sizeW, sizeH = nil, nil end
    DUI.AfterCombat(function()
        local w, h = Manager.PlateSize()
        if w == sizeW and h == sizeH then return end
        if DUI.SafeCall(set, w, h) then sizeW, sizeH = w, h end
    end, "nameplates:size")
end

-- Stacking is the game's own setting (enemy and friendly plates separately), set
-- when asked ("stack" or "overlap"; "game" leaves it alone).
Manager.STACK_CVAR = "nameplateStackingTypes"
function Manager.ApplyStacking()
    local mode = ns.cfg and ns.cfg.stacking or "game"
    if mode == "game" then return end
    local E = Enum and Enum.NamePlateStackType
    local set, get = C_CVar and C_CVar.SetCVarBitfield, C_CVar and C_CVar.GetCVarBitfield
    if not (E and set) then return end
    local on = mode == "stack"
    local function bit(i, v)
        if type(get) == "function" then
            if get(Manager.STACK_CVAR, i) == v then return end
        end
        DUI.SafeCall(set, Manager.STACK_CVAR, i, v)
    end
    -- Every plate already hands the game its stacking frame, stacked kind or not,
    -- so none is handed again here.
    DUI.AfterCombat(function()
        bit(E.Enemy, on)
        bit(E.Friendly, on and ns.cfg.stackFriendly == true)
    end, "nameplates:stacking")
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
            if kind ~= nil then DUI.SafeCall(M.SetNamePlateHitTestInsets, kind, i, i, i, i) end
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
    Manager.styleSig = Manager.StyleSig() -- plates are laid out for this look as they come up
    Manager.Prepare(Manager.PREPARE)
    Manager.PrepareClicks(Manager.PREPARE)
    Manager.PrepareStacks(Manager.PREPARE)
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
            -- Only for the CVars the driver itself redoes plates on (its optionCVars).
            elseif Manager.RECLAIM_EVENTS[event] and (event ~= "CVAR_UPDATE" or (driver.optionCVars or EMPTY)[unit]) then
                DUI.SafeCall(Manager.Reclaim)
            end
        end)
    end
    for _, e in ipairs({ "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
        DUI.RegisterEvent(e, function() Manager.ApplySize() end)
    end
    DUI.RegisterEvent("PLAYER_TARGET_CHANGED", function()
        Manager.UpdateTargets()
        Manager.RecheckUnit("target")
        Manager.QueueFocus()
    end)
    DUI.RegisterEvent("UNIT_TARGETABLE_CHANGED", function(_, unit) Manager.RecheckUnit(unit, true) end)
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
        if name == Manager.NAME_ONLY_CVAR:lower() then return Manager.Each(Manager.OwnClicks) end
        -- The game sets its own plate size again when these change (its CVar callbacks).
        if Manager.SIZE_CVARS[name] then return C_Timer.After(0, function() Manager.ApplySize(true) end) end
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
    say("Stacking box " .. (p.stack and rect(p.stack) or "none"))
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

local asked, state = Report.Asked, Report.State

-- One plate's lines, and whether it looks wrong.
function Manager.CheckOne(unit, np)
    if forbidden(np) then return { unit .. ": the game keeps this plate from addons (forbidden)" }, true end
    local lines, wrong = Report.PlateHead(unit, np)
    local uf = np.UnitFrame
    if type(uf) == "table" then
        local okP, parent = pcall(uf.GetParent, uf)
        lines[#lines + 1] = string.format("  game frame onPlate=%s held=%s clicks=%s box=%s", tostring(okP and parent == np),
            tostring(held[uf] == true), clickOf[np] and "ours" or "game's", stackOf[np] and "ours" or "none")
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
    for _, line in ipairs(Report.GameLines()) do out[#out + 1] = line end
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
    DUI.Print(Report.MarkSaid(Report.Mark()))
end, L["/dui platecheck - run while a nameplate is missing, and send us what it prints"])

-- /dui plateprobe: run after platecheck while plates are missing. Tests one
-- suspect: the frame handed to the game for spacing plates apart went bad and
-- the game's stacking pushed every plate out of view. Every plate is spaced by
-- itself instead. A plate that comes into view afterwards gets its stacking
-- frame again; /reload restores everything.
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
-- made directly on one, with the Daylight UI plates hidden too); /reload fixes it.
-- Each run undoes one thing Daylight UI does to the game's plates and asks whether they're back: the first step that brings them back
-- names the cause and fixes it without a reload. Out of combat only (the game
-- refuses these settings in combat). Chat output stays in English since players
-- send it in with bug reports.
Manager.FIX_GAP = 0.5 -- seconds the game's plates stay off in step 3
Manager.FIX_BACK = 1 -- seconds until the Daylight UI plates go back on after step 3
Manager.FIX_SHOW_CVARS = Report.FIX_SHOW_CVARS

local function gameDefault(name)
    local fn = C_CVar and C_CVar.GetCVarDefault
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, name)
    return ok and type(v) == "string" and v or nil
end

-- Hands every plate back to the game and takes none again until told to.
-- Returns how many it tried, how many made it back, and the first error.
local function handBack()
    Manager.fixPaused = true
    local units = {}
    for unit in pairs(byUnit) do units[#units + 1] = unit end
    local back, first = 0, nil
    for _, unit in ipairs(units) do
        local p = byUnit[unit]
        local np, uf = p.nameplate, p.gameFrame
        local ok, err = Manager.Try(Manager.Removed, unit)
        if ok then
            local gave, why
            ok, err = Manager.Try(function() gave, why = Manager.GiveBackFrame(uf, np) end)
            if ok and gave == false then ok, err = false, why end
        end
        if ok then back = back + 1 else first = first or err end
    end
    return #units, back, first
end

-- Switches the game's plates off and on so it rebuilds them, then puts the
-- Daylight UI plates back a moment later.
local function offAndOn()
    local done = Report.FixHold()
    Report.CycleShowSwitches(Manager.FIX_GAP, function()
        C_Timer.After(Manager.FIX_BACK, function()
            Manager.fixPaused = nil
            DUI.SafeCall(Manager.Recheck)
            done()
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
    if part == "pool" then
        local done = Report.FixHold()
        return Manager.FreshPool(function() offAndOn(); done() end)
    end
    offAndOn()
end

Manager.FIX = {
    -- 1. Reapply the plate size and click insets given to the game.
    function()
        local set = C_NamePlate and C_NamePlate.SetNamePlateSize
        local ok, err = true, nil
        if type(set) == "function" then ok, err = Manager.Try(set, Manager.PlateSize()) end
        Manager.ApplyClickable()
        Manager.Each(Manager.OwnClicks)
        if not ok then return "the game refused the plate size (" .. err .. "), click area set again" end
        return "the plate size and click area set again"
    end,
    -- 2. Hand every game plate back as it was (Daylight UI's off, its own frame back on it
    -- with its events and click area), and take none again until step 3 is done.
    function()
        local tried, back, err = handBack()
        if back == tried then return string.format("%d plates handed back to the game", tried) end
        return string.format("%d of %d plates handed back to the game, %d refused (%s)", back, tried, tried - back,
            tostring(err))
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
    -- 5. Rebuilt, then back on with each game plate spaced by itself, not by a
    -- frame of Daylight UI's.
    function()
        backWithout("stack")
        return "the game's plates rebuilt, Daylight UI's back on with each game plate spaced by itself (wait two seconds)"
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
    -- 8. The game's own switch for nameplates and speech bubbles back on. New
    -- steps go after it, so the earlier ones keep the numbers older reports used.
    function() return Report.InWorldBack() end,
}
-- 9 on: the layer plates are drawn on, the same steps as with this module off.
for _, step in ipairs(Report.WORLD_STEPS) do Manager.FIX[#Manager.FIX + 1] = step end
Manager.FIX_STEPS = #Manager.FIX

-- The report once a step brought them back (or none did): which step, where and
-- how long into the session, other loaded addons, the game's plate settings, and
-- the plates as they were before step 1 while still invisible. One text, short
-- enough for one Discord message.
Manager.REPORT_PLATES = 1 -- plates listed in full (a report holds 4000 characters, and the log needs room)
-- Where the player is, how the game is shown, what of Daylight UI is on and
-- the other addons (the core's report, DUI.PlateReport).
function Manager.ReportWorld()
    return Report.World(Manager.startedAt)
end

-- step: the one that brought them back, nil if none did.
function Manager.FixReport(step)
    local run = Manager.fixRun or { did = {}, before = {} }
    local title = string.format("Daylight UI %s platefix: %s", tostring(DUI.VERSION),
        step and string.format("step %d brought them back", step) or "no step brought them back")
    return Report.BuildFixReport(title, run, run.world or Manager.ReportWorld())
end

-- Shows the report in a copy box (the profiles' one) and ends the round.
function Manager.FixDone(step)
    local text = Manager.FixReport(step)
    Manager.fixStep, Manager.fixRun = nil, nil
    DUI.Profiles.ShowText(L["Nameplate report"], L["Ctrl+C to copy, then paste it in a bug report on the Daylight UI Discord. "
        .. "After that, /reload."], text)
    -- In chat too, so a screenshot still carries it if the box can't be copied.
    for line in string.gmatch(text, "[^\n]+") do DUI.Print(line) end
    Report.FixEnd()
    return text
end

-- One step per run; after the last, the next run starts over at 1.
-- How many game plates carry a Daylight UI plate, for each step's before and after.
local function ownedCount()
    local n = 0
    for _ in pairs(byUnit) do n = n + 1 end
    return n
end

function Manager.Fix()
    if Report.FixBusy() then return Report.FIX_WAIT end
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
        Manager.fixRun = { did = {}, before = Manager.CheckLines(Manager.REPORT_PLATES), world = Manager.ReportWorld(),
            log = Report.LogLines() }
        Report.FixBegin()
    end
    Manager.fixStep = n
    local did = Report.RunStep(Manager.fixRun, n, Manager.FIX[n], ownedCount)
    return string.format("platefix %d/%d: %s. Are the nameplates back? Yes: /dui platefix yes. "
        .. "No: /dui platefix again for the next step.", n, Manager.FIX_STEPS, did)
end

DUI.RegisterCommand("platefix", function(rest)
    if string.lower(rest or "") ~= "yes" then return DUI.Print(Manager.Fix()) end
    if not Manager.fixStep then return DUI.Print(L["Run /dui platefix first, while the nameplates are invisible."]) end
    if Report.FixBusy() then return DUI.Print(Report.FIX_WAIT) end
    Report.FixYes(Manager.fixRun, ownedCount)
    Manager.FixDone(Manager.fixStep)
    DUI.Print(L["Copy the text in the box and send it to the Daylight UI team, then /reload."])
end, L["/dui platefix - run while nameplates are invisible, one step each time, and say which step brought them back"])
