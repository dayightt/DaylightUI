-- Questie's tracker and its NPC tooltip quest lines step aside while Daylight UI's are
-- shown. Its map icons, minimap icons and coordinates stay Questie's (Skins
-- dresses its icons). Each is one of Questie's own settings
-- (Questie.db.profile.<key>), turned off before it draws (its tracker builds
-- frames after login), so nothing doubles up and no reload is needed. Each
-- setting turned off this way is remembered in DB.Root().questieOff[key], and when
-- Daylight UI's goes away again (module off, setting off, another tracker addon)
-- Questie's comes back. Settings the player turned off themselves stay off.
-- One works the other way round: "Hide icons of untracked quests" is turned on
-- while Daylight UI's tracker is in charge, so a quest left out of the tracker
-- leaves the maps too. With its own tracker off, Questie reads "tracked" from
-- the game's quest watches, which is what Daylight UI's tracker lists.
-- While Skins' Questie option is on, its objective icons use Daylight UI's white symbols
-- (QA.ICONS, written the way Questie's own icon options write them), with each
-- quest colored by Questie's "Unique Map Icon Colors". The player's own picks
-- are saved in DB.Root().questieIcons and restored when it's off.
-- Lives in core, not a module, because it must run whichever modules are on
-- and restore Questie's when Quests or Skins is turned off.

local _, DUI = ...

local QA = {}
DUI.QuestieAside = QA

local function isTable(x) return type(x) == "table" end

local function questsOn()
    local m = DUI.GetModule and DUI:GetModule("Quests")
    return isTable(m) and m.enabled == true
end
local function never() return false end

QA.LIST = {
    -- Daylight UI's is shown unless the player picked Questie's (Quests `tracker`).
    { key = "trackerEnabled", ours = function() return DUI.questsOwnTracker == true and DUI:Get("Quests", "tracker") ~= false end },
    -- Daylight UI's quest lines in NPC tooltips (Quests GiverTips.lua, on unless turned off).
    { key = "showQuestsInNpcTooltip", ours = function() return questsOn() and DUI:Get("Quests", "mapQuests.tooltip") ~= false end },
    -- Untracked quests off the maps. Not with the "whole log" filter: it lists
    -- every quest without watching any, so Questie would hide them all. Turned
    -- on once (`once`): a player who turns it off again in Questie keeps it off.
    { key = "hideUntrackedQuestsMapIcons", value = true, icons = true, once = true, ours = function()
        return questsOn() and DUI.questsOwnTracker == true and DUI:Get("Quests", "tracker") ~= false
            and DUI:Get("Quests", "filter") ~= "log"
    end },
    -- No longer used, kept so settings once turned off here get turned back on.
    { key = "enableMapIcons", ours = never },
    { key = "enableMiniMapIcons", ours = never },
    { key = "mapCoordinatesEnabled", ours = never },
}

local ART = "Interface\\AddOns\\DaylightUI\\Media\\objective-%s.png"
-- Questie setting -> Daylight UI's value (files from tools/make_objective_icons.py).
QA.ICONS = {
    ICON_SLAY = ART:format("kill"), ICON_LOOT = ART:format("loot"), ICON_OBJECT = ART:format("use"),
    ICON_INTERACT = ART:format("use"), ICON_EVENT = ART:format("explore"),
    questObjectiveColors = true, questMinimapObjectiveColors = true, alwaysGlowMap = false,
    waypointHighlight = false, -- patrol paths lighting up on hover (the icon flash is Quests' Bridge.WatchHover)
}
local NONE = "none" -- stands in for a setting the player never set (nil)

local function skinOn()
    local m = DUI.GetModule and DUI:GetModule("Skins")
    return isTable(m) and m.enabled == true and DUI:Get("Skins", "addonSkins.questie") ~= false
end

-- Questie hides and shows its drawn icons only when asked (its own option does
-- the same), and draws an untracked quest's icons only once they may show.
local function module(name)
    local L = _G.QuestieLoader
    if not isTable(L) or type(L.ImportModule) ~= "function" then return nil end
    local m = L:ImportModule(name)
    return isTable(m) and m or nil
end

function QA.RedrawIcons()
    local TL, QQ, AQ = module("ThreadLib"), module("QuestieQuest"), module("ActiveQuests")
    if not (TL and QQ and AQ) or type(TL.ThreadInstant) ~= "function" or type(AQ.Iterate) ~= "function"
        or type(QQ.ShowQuestIcons) ~= "function" or type(QQ.HideQuestIcons) ~= "function"
        or type(QQ.PopulateObjectiveNotes) ~= "function" then return end
    QA.Hurry()
    TL.ThreadInstant(function()
        for _, acceptance in AQ.Iterate() do
            if isTable(acceptance) and acceptance.quest then QQ:PopulateObjectiveNotes(acceptance.quest) end
        end
        QQ:ShowQuestIcons()
        QQ:HideQuestIcons()
    end)
end


-- Questie draws new map icons from a queue, 24 every 0.2 s, so a quest with
-- hundreds of spawns spreads over the map for seconds. That used to happen
-- once at login; with untracked quests hidden it happens on every track.
-- For a short while after a watch change, work the queue every frame instead.
QA.HURRY_FOR, QA.HURRY_PER_FRAME = 2, 4
local hurry, hurryUntil

local function hurryTick()
    local M = module("QuestieMap")
    if not M or type(M.ProcessQueue) ~= "function" or GetTime() > hurryUntil then
        hurry:SetScript("OnUpdate", nil)
        return
    end
    for _ = 1, QA.HURRY_PER_FRAME do M.ProcessQueue() end
end

function QA.Hurry()
    local q = _G.Questie
    local db = isTable(q) and isTable(q.db) and q.db.profile
    if not isTable(db) or db.hideUntrackedQuestsMapIcons ~= true or db.trackerEnabled ~= false then return end
    if not module("QuestieMap") then return end
    hurry = hurry or CreateFrame("Frame")
    QA.hurryFrame = hurry
    hurryUntil = GetTime() + QA.HURRY_FOR
    hurry:SetScript("OnUpdate", function() DUI.SafeCall(hurryTick) end)
end

DUI.RegisterEvent("QUEST_WATCH_LIST_CHANGED", function(_, _, added)
    if added then QA.Hurry() end
end)

local function icons(q, db, root)
    local kept = root.questieIcons
    local changed = false
    if skinOn() then
        kept = kept or {}
        root.questieIcons = kept
        for k, v in pairs(QA.ICONS) do
            if kept[k] == nil then
                if db[k] == nil then kept[k] = NONE else kept[k] = db[k] end
            end
            if db[k] ~= v then db[k] = v; changed = true end
        end
    elseif kept then
        for k, was in pairs(kept) do
            if was == NONE then was = nil end
            if db[k] ~= was then db[k] = was; changed = true end
        end
        root.questieIcons = nil
    end
    -- Questie reads its icon list from the settings (Questie.SetIcons).
    if changed and type(q.SetIcons) == "function" then pcall(q.SetIcons, q) end
end

-- False while Questie's settings don't exist yet (or it isn't loaded).
function QA.Run()
    local q = _G.Questie
    local db = isTable(q) and isTable(q.db) and q.db.profile
    if not isTable(db) then return false end
    local root = DUI.DB and DUI.DB.Root and DUI.DB.Root()
    if not isTable(root) then return false end
    root.questieOff = root.questieOff or {}
    local off = root.questieOff
    local redraw = false
    -- A `once` setting set before is the player's from then on. One noted in
    -- questieOff was set by an earlier version, so it counts as set too.
    root.questieSet = root.questieSet or {}
    local set = root.questieSet
    for _, a in ipairs(QA.LIST) do
        local want = a.value == true
        if a.ours() then
            local setBefore = a.once and (set[a.key] or off[a.key])
            if not setBefore and db[a.key] ~= want then
                db[a.key] = want
                off[a.key] = true
                redraw = redraw or a.icons
            end
            if a.once then set[a.key] = true end
        elseif off[a.key] then
            db[a.key] = not want
            off[a.key] = nil
            set[a.key] = nil
            redraw = redraw or a.icons
        end
    end
    if next(off) == nil then root.questieOff = nil end
    if next(set) == nil then root.questieSet = nil end
    if redraw then DUI.AfterCombat(function() DUI.SafeCall(QA.RedrawIcons) end, "questie icons") end
    icons(q, db, root)
    return true
end

local function safeRun() DUI.SafeCall(QA.Run) end

-- The tracker or Skins settings changed (from their OnEnable and
-- OnSettingChanged).
DUI.On("QuestMapsChanged", safeRun)

-- Questie's settings appear when AceDB loads, which may be after Daylight UI's login.
-- While it's loaded but they're missing, check again every QA.RETRY seconds,
-- up to QA.TRIES times. Timers only, nothing per frame.
QA.RETRY, QA.TRIES = 0.5, 20
local function questieLoaded()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
    return type(loaded) == "function" and loaded("Questie") == true
end
local function retry(left)
    if left <= 0 or not questieLoaded() then return end
    C_Timer.After(QA.RETRY, function()
        local done
        DUI.SafeCall(function() done = QA.Run() end)
        if not done then retry(left - 1) end
    end)
end
DUI.On("Login", function()
    local done
    DUI.SafeCall(function() done = QA.Run() end)
    if not done then retry(QA.TRIES) end
end)
