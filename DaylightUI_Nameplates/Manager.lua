-- Puts our plate on each of the game's nameplates. When a plate gets a unit, the
-- game's own plate frame goes to alpha 0 where it is (its widgets, like
-- soft-target icons, stay visible) and ours shows in its place. Plates the game
-- keeps from addons (friendly ones in instances) are left alone.
--
-- Ours sits on a game plate only while that plate shows a unit and comes off the
-- moment the unit goes. The game reuses its plates, and one that carries a unit
-- addons may not touch turns everything on it forbidden permanently; a frame of
-- ours left on it would be unusable from then on.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Manager = {}
ns.Manager = Manager

local hidden = CreateFrame("Frame")
hidden:Hide()

local byUnit = {} -- unit -> our plate
local spare = {} -- plates not on any game plate
Manager.byUnit = byUnit
-- Plates are built at login, out of combat: one per plate the game can show
-- (nameplate1-40), so none is ever built mid-fight.
Manager.PREPARE = 40

-- Our plates live here while not on a game plate.
local home = CreateFrame("Frame", nil, UIParent)
home:Hide()

function Manager.Prepare(n)
    for _ = 1, n do spare[#spare + 1] = ns.Plate.Create(home) end
end

function Manager.Spares() return #spare end

local plain = function(...) return ns.Plate.Plain(...) end

local function forbidden(frame)
    if not frame.IsForbidden then return false end
    local ok, no = pcall(frame.IsForbidden, frame)
    return not ok or no == true
end

-- A spare plate (dropping any that became forbidden), or a new one built under
-- our own frame.
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

-- Turns off the game's own plate under ours, the way EllesmereUI does. The frame
-- stays where the game put it at alpha 0. Reparenting it (done in early versions)
-- left the game's plate code running under our taint, which then errored on secret
-- values (and per EllesmereUI broke picking between overlapping plates).
-- Its pieces (health bar, level, borders: every child frame) are parked on our
-- hidden frame, since alpha alone got undone in combat. The name text directly on
-- it stays, made transparent (park). Its events and its cast bar's are
-- unregistered: left running it handled ~46 events per plate and rebuilt its aura
-- icons on every aura change, all fight long, under every one of our plates. Its
-- widgets stay on it and visible; the soft-target icon belongs to the game's
-- nameplate driver (its own events).
-- When given back (Manager.Unsilence) it re-registers the events it registered at
-- creation (Manager.LOAD_EVENTS, from the game's CompactUnitFrame_OnLoad). Its
-- unit events return with the next unit the game assigns (the game clears the
-- unit as it takes the frame back), so a plate the game draws itself works as before.
local silenced = setmetatable({}, { __mode = "k" })
local parked = setmetatable({}, { __mode = "k" }) -- game frame -> its pieces we parked
local faded = setmetatable({}, { __mode = "k" }) -- region left on it, made transparent -> its previous alpha
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

local function park(uf)
    local list = parked[uf] or {}
    parked[uf] = list
    for _, child in ipairs({ uf:GetChildren() }) do
        if type(child) == "table" and child ~= uf.WidgetContainer and child ~= uf.SoftTargetFrame
            and not forbidden(child) and not (child.IsProtected and child:IsProtected()) then
            list[#list + 1] = child
            child:SetParent(hidden)
        end
    end
    -- Regions directly on the frame (its name text) stay on it, made transparent.
    -- The game hangs the plate's click area off that name, and anchoring a plate's
    -- points to a frame outside it (which EllesmereUI never does) made plates go
    -- invisible. The frame's own alpha gets reset in combat; a region's isn't touched.
    for _, region in ipairs({ uf:GetRegions() }) do
        if type(region) == "table" and region.SetAlpha and not forbidden(region) and not faded[region] then
            local ok, a = pcall(region.GetAlpha, region)
            faded[region] = (ok and type(a) == "number" and not (issecretvalue and issecretvalue(a))) and a or 1
            region:SetAlpha(0)
        end
    end
end

local function unfade(uf)
    for _, region in ipairs({ uf:GetRegions() }) do
        local a = type(region) == "table" and faded[region]
        if a and not forbidden(region) then
            faded[region] = nil
            region:SetAlpha(a)
        end
    end
end

local function unpark(uf)
    local list = parked[uf]
    if not list then return end
    parked[uf] = nil
    for i = #list, 1, -1 do
        local child = list[i]
        if not forbidden(child) and child:GetParent() == hidden then child:SetParent(uf) end
    end
end

-- p is our plate on it, which holds the frame (the game has already detached it
-- from its plate by the time it reports the unit gone). A frame already silenced
-- is left alone.
function Manager.Silence(nameplate, p)
    local uf = nameplate.UnitFrame
    if type(uf) ~= "table" or not uf.SetAlpha then return end
    if p then
        if p.gameFrame and p.gameFrame ~= uf then Manager.UnsilenceFrame(p.gameFrame) end
        p.gameFrame = uf
    end
    if silenced[uf] then
        quiet(uf) -- in case the game gave it a unit (and its events) again
        uf:SetAlpha(0) -- and showed it (Manager.Unseen)
        return
    end
    silenced[uf] = true
    park(uf)
    quiet(uf)
    uf:SetAlpha(0)
    -- Widgets and the soft-target icon (mining pick, herb hand) stay visible over the hidden frame.
    for _, keep in ipairs({ uf.WidgetContainer, uf.SoftTargetFrame }) do
        if type(keep) == "table" and keep.SetIgnoreParentAlpha then keep:SetIgnoreParentAlpha(true) end
    end
end

local refused = setmetatable({}, { __mode = "k" }) -- game plates ours can't go on; the game's stays (Added)

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
    -- One of our plates still on this game plate for another unit: its removal
    -- never arrived (Manager.Sync).
    for other, q in pairs(byUnit) do
        if q.nameplate == nameplate then Manager.Removed(other) end
    end
    refused[nameplate] = nil
    local p = Manager.Take()
    -- Some plates don't report forbidden but make anything put on them forbidden.
    -- Check ours is still usable there before hiding the game's. If not (or anything
    -- here errors), ours comes off (or is dropped) and the game keeps drawing its own
    -- plate for this unit.
    if not DUI.SafeCall(ns.Plate.Attach, p, nameplate) or not Manager.Usable(p) then
        refused[nameplate] = true
        Manager.Abandon(p)
        return
    end
    byUnit[unit] = p
    if not (DUI.SafeCall(Manager.Silence, nameplate, p) and DUI.SafeCall(ns.Plate.Install, p, unit)) then
        byUnit[unit] = nil
        DUI.SafeCall(Manager.UnsilenceFrame, p.gameFrame) -- give the game its plate back for this unit
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
    if not p.apiSeen then
        p.apiSeen = true
        DUI.APIReport.Made("nameplate", p, nil, false)
    end
    DUI.APIReport.Unit("nameplate", p, unit, false)
end

-- Whether one of our plates can still be read and changed where it is.
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

-- Makes the game's own plate visible again for whatever the game puts on it next.
function Manager.Unsilence(nameplate)
    Manager.UnsilenceFrame(type(nameplate) == "table" and nameplate.UnitFrame)
end

function Manager.UnsilenceFrame(uf)
    if type(uf) ~= "table" or not uf.SetAlpha or forbidden(uf) then return end
    silenced[uf] = nil
    unpark(uf)
    unfade(uf)
    if quieted[uf] then
        quieted[uf] = nil
        for _, e in ipairs(Manager.LOAD_EVENTS) do pcall(uf.RegisterEvent, uf, e) end
    end
    uf:SetAlpha(1)
    -- Widgets and the soft-target icon (mining pick, herb hand) stay visible over the hidden frame.
    for _, keep in ipairs({ uf.WidgetContainer, uf.SoftTargetFrame }) do
        if type(keep) == "table" and keep.SetIgnoreParentAlpha then keep:SetIgnoreParentAlpha(false) end
    end
end

-- The game only makes its plate frame visible again in one place:
-- CompactUnitFrame_UpdateCenterStatusIcon (SetAlpha(1); plates don't fade out of
-- range), called from its nameplate driver's OnEvent (Blizzard_NamePlates and
-- CompactUnitFrame.lua). That happens when a plate gets its unit (SetUnit ->
-- UpdateAll; FrameHandedOut silences it again) and on its options update, which
-- covers every plate (UpdateNamePlateOptions -> ApplyFrameOptions on these events;
-- CVAR_UPDATE only matters for its option CVars, but any is cheap). The frame's
-- own events are already stopped (quiet). So right after the driver's OnEvent,
-- ours go back to 0, with no hook on the frame's SetAlpha.
Manager.RESHOW_EVENTS = { DISPLAY_SIZE_CHANGED = true, VARIABLES_LOADED = true, CVAR_UPDATE = true }
function Manager.Unseen()
    for uf in pairs(silenced) do
        if not forbidden(uf) then uf:SetAlpha(0) end
    end
end

-- The game hands a plate its frame from a shared pool as the plate gets its unit,
-- and that can happen after our NAME_PLATE_UNIT_ADDED handler ran. The frame
-- hidden there was then an older one, and the new one stayed visible under ours
-- (seen in combat with many plates coming and going). So right after the game
-- hands one out: hide it if ours is on that plate, show it if not (it may still
-- be hidden from its previous plate).
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
        Manager.Silence(nameplate, p)
    elseif silenced[uf] then
        Manager.Unsilence(nameplate)
    end
end

function Manager.Removed(unit)
    local p = byUnit[unit]
    if not p then return end
    byUnit[unit] = nil
    local wasTarget = p.isTarget
    -- The plate releases its unit but stays known for the next one.
    if p.apiSeen then DUI.APIReport.Gone("nameplate", p, false) end
    -- The frame we silenced, not the plate's: the game has already taken its frame
    -- off the plate.
    DUI.SafeCall(Manager.UnsilenceFrame, p.gameFrame)
    p.gameFrame = nil
    ns.Cast.Forget(p)
    if Manager.Usable(p) then
        ns.Plate.Uninstall(p)
        Manager.Release(p)
    else
        pcall(ns.Plate.Detach, p) -- detach our stacking frame from the game's plate regardless
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
local function sizePlate(p)
    local groupNow = sizeOn and (p.isTarget and "target" or (not othersPlain and "others" or nil)) or nil
    if groupNow == p.sizeGroup then return end
    p.sizeGroup = groupNow
    ns.Plate.Layout(p)
end

-- Puts one plate in its size group from the last pass (a new plate that isn't
-- your target).
function Manager.SizeOne(p)
    sizePlate(p)
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

-- Reconciles our plates with what the game shows now, as a /reload would. A layer
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
    Manager.UpdateTargets()
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

-- The mouse moved onto a unit: only the plate it left and the one it's on change
-- (checking all of them was ~260 calls each time). Without an answer from the
-- game, every plate is checked as before.
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
-- zoom are pinned to 1 (target zoom is ours, done in one step in
-- Plate.ApplyScale), so nothing gets resized or restacked under ours and its click
-- area doesn't grow on the target. The game refuses these in combat.
Manager.SCALE_CVARS = { "nameplateMinScale", "nameplateMaxScale", "nameplateSelectedScale" }
function Manager.ApplyScales()
    DUI.AfterCombat(function()
        if not SetCVar then return end
        for _, k in ipairs(Manager.SCALE_CVARS) do pcall(SetCVar, k, "1") end
    end, "nameplates:scales")
end

-- Friendly plates that are just the name: the game's plate under ours is its light
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

-- Sizes the game's plates to cover ours (in UI units; our plates are the UI scale
-- times Scale). The game's plate frame takes the clicks and grows from its center,
-- where ours is centered too (offset by Height). So it's as wide as our bar and
-- tall enough to reach our name above the bar in either direction from the
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
    end, "nameplates:stacking")
end

-- Makes every plate clickable over its whole frame: the game's click insets (which
-- can shrink a plate's click area to nothing, and may have been left that way) are
-- pushed past its edges.
Manager.CLICK_INSET = -10000
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
    -- which can run after ours, so a script post-hook on its OnEvent runs right after
    -- it. Not a hook on its OnNamePlateAdded method: hooking the game's own methods
    -- has broken its calls before, and this one is hot in combat.
    local driver = NamePlateDriverFrame
    if type(driver) == "table" and type(driver.HookScript) == "function" then
        driver:HookScript("OnEvent", function(_, event, unit)
            if event == "NAME_PLATE_UNIT_ADDED" then DUI.SafeCall(Manager.FrameHandedOut, unit)
            elseif Manager.RESHOW_EVENTS[event] then DUI.SafeCall(Manager.Unseen) end
        end)
    end
    DUI.RegisterEvent("PLAYER_TARGET_CHANGED", function() Manager.UpdateTargets() end)
    for _, e in ipairs(Manager.RECHECK_EVENTS) do
        DUI.RegisterEvent(e, function()
            Manager.Recheck()
            C_Timer.After(Manager.RECHECK_LATE, Manager.Recheck)
        end)
    end
    DUI.RegisterEvent("RAID_TARGET_UPDATE", function()
        Manager.Each(function(p) ns.Plate.UpdateMarker(p, true) end)
    end)
    -- Your level determines every level's color.
    DUI.RegisterEvent("PLAYER_LEVEL_UP", function() Manager.Each(ns.Plate.UpdateLevel) end)
    DUI.RegisterEvent("UPDATE_MOUSEOVER_UNIT", function()
        hoverChanged()
        watcher:Show()
    end)
    -- Quest marks: once per burst of quest log events (they come in runs, and each
    -- plate's check reads its tooltip).
    for _, e in ipairs({ "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED" }) do
        pcall(DUI.RegisterEvent, e, Manager.QuestsChanged)
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
        pcall(DUI.RegisterEvent, e, function()
            if combat then recolorForce = true end
            if recolorQueued then return end
            recolorQueued = true
            C_Timer.After(0, recolor)
        end)
    end
    -- Someone joined or left: friendly names in the group color update
    -- (Plate.InGroupName), only on plates whose answer changed.
    local namesQueued = false
    pcall(DUI.RegisterEvent, "GROUP_ROSTER_UPDATE", function()
        if namesQueued then return end
        namesQueued = true
        C_Timer.After(0, function()
            namesQueued = false
            Manager.Each(function(p)
                if p.friendly and (ns.Plate.InGroupName(p) ~= (p.groupName == true)
                    or (ns.Plate.Cfg(p).partyMark or "none") ~= "none" and ns.Plate.InGroup(p) ~= (p.groupMarkOn == true)) then
                    ns.Plate.UpdateNameColor(p)
                end
            end)
        end)
    end)
    -- Plates already up (a reload with enemies around).
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if plain(UnitExists, unit) == true then DUI.SafeCall(Manager.Added, unit) end
    end
    C_Timer.NewTicker(Manager.SYNC_EVERY, function() DUI.SafeCall(Manager.Sync) end)
end

-- /dui platefps: hides our plates (the game's stay hidden too) or brings them back,
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

-- /dui platecheck: run while a plate is missing. Compares the game's plates with
-- ours and lists what could hide each: no plate of ours on it, ours not showing,
-- or the game's plate itself. Every read is guarded and a secret just says so, so
-- it works in combat. Output stays in English.
Manager.CHECK_DETAIL = 6 -- plates listed in full; a crowd would flood the chat

local function asked(f, method)
    local ok, v = pcall(function() return f[method](f) end)
    if not ok then return "?" end
    if issecretvalue and issecretvalue(v) then return "secret" end
    if type(v) == "number" then return string.format("%.2f", v) end
    return tostring(v)
end

local function where(f)
    local ok, l, b, w, h = pcall(function() return f:GetRect() end)
    if not ok then return "can't measure" end -- the game refuses; says nothing about the plate
    if type(l) == "nil" then return "no rect" end
    if issecretvalue and (issecretvalue(l) or issecretvalue(b) or issecretvalue(w) or issecretvalue(h)) then
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
        lines[#lines + 1] = string.format("  game frame alpha=%s silenced=%s", asked(uf, "GetAlpha"), tostring(silenced[uf] == true))
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
        "nameplateStackingTypes", "nameplateMaxDistance" }) do
        local ok, v = pcall(C_CVar.GetCVar, name)
        words[#words + 1] = name:gsub("^nameplate", "") .. "=" .. tostring(ok and v)
    end
    out[#out + 1] = "Game: " .. table.concat(words, " ")
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
-- suspect: the frame we give the game for spacing plates apart (Plate.Install,
-- p.stack) went bad and the game's stacking pushed every plate out of view. Every
-- plate gets its own frame back (Plate.Detach no longer does this; it hides ours,
-- as EllesmereUI does). A plate that comes into view afterwards gets ours again;
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
-- made directly on one, with ours hidden too); /reload fixes it, and it never
-- happens without Daylight UI. Each run undoes one thing we do to the game's
-- plates and asks whether they're back: the first step that brings them back
-- names the cause and fixes it without a reload. Out of combat only (the game
-- refuses these settings in combat). Chat output stays in English since players
-- send it in with bug reports.
Manager.FIX_STEPS = 4
Manager.FIX_GAP = 0.5 -- seconds the game's plates stay off in step 3
Manager.FIX_BACK = 1 -- seconds until ours go back on after step 3
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

Manager.FIX = {
    -- 1. Reapply the plate size and click insets we give the game.
    function()
        local set = C_NamePlate and C_NamePlate.SetNamePlateSize
        if type(set) == "function" then pcall(set, Manager.PlateSize()) end
        Manager.ApplyClickable()
        return "the plate size and click area set again"
    end,
    -- 2. Hand every game plate back as it was (ours off, its own frame, name and pieces
    -- restored), and take none again until step 3 is done.
    function()
        Manager.fixPaused = true
        local units = {}
        for unit in pairs(byUnit) do units[#units + 1] = unit end
        for _, unit in ipairs(units) do DUI.SafeCall(Manager.Removed, unit) end
        return string.format("%d plates handed back to the game", #units)
    end,
    -- 3. Toggle the game's plates off and on so it rebuilds them; ours go back on after.
    function()
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
        return "the game's plates switched off and on (Daylight UI's go back on a second later)"
    end,
    -- 4. Reset the plate settings we change to the game's defaults (Daylight UI sets its
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
    return string.sub(table.concat(out, "\n"), 1, Manager.REPORT_MAX)
end

-- Shows the report in a copy box (the profiles' one) and ends the round.
function Manager.FixDone(step)
    local text = Manager.FixReport(step)
    Manager.fixStep, Manager.fixRun = nil, nil
    DUI.Profiles.ShowText(L["Nameplate report"], L["Ctrl+C to copy, then paste it in a bug report on the Daylight UI Discord. "
        .. "After that, /reload."], text)
    return text
end

-- One step per run; after the last, the next run starts over at 1.
function Manager.Fix()
    if InCombatLockdown() then return "platefix: leave combat first, then /dui platefix again." end
    local n = (Manager.fixStep or 0) + 1
    if n > Manager.FIX_STEPS then
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
