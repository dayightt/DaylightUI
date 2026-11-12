-- Questie's tracker and its NPC tooltip quest lines step aside while ours are
-- shown. Its map icons, minimap icons and coordinates stay Questie's (Skins
-- dresses its icons). Each is one of Questie's own settings
-- (Questie.db.profile.<key>), turned off before it draws (its tracker builds
-- frames after login), so nothing doubles up and no reload is needed. Each
-- setting we turn off is remembered in DB.Root().questieOff[key], and when
-- ours goes away again (module off, setting off, another tracker addon)
-- Questie's comes back. Settings the player turned off themselves stay off.
-- While Skins' Questie option is on, its objective icons use our white symbols
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
    -- Ours is shown unless the player picked Questie's (Quests `tracker`).
    { key = "trackerEnabled", ours = function() return DUI.questsOwnTracker == true and DUI:Get("Quests", "tracker") ~= false end },
    -- Our quest lines in NPC tooltips (Quests GiverTips.lua, on unless turned off).
    { key = "showQuestsInNpcTooltip", ours = function() return questsOn() and DUI:Get("Quests", "mapQuests.tooltip") ~= false end },
    -- No longer ours, kept so settings we once turned off get turned back on.
    { key = "enableMapIcons", ours = never },
    { key = "enableMiniMapIcons", ours = never },
    { key = "mapCoordinatesEnabled", ours = never },
}

local ART = "Interface\\AddOns\\DaylightUI\\Media\\objective-%s.png"
-- Questie setting -> our value (files from tools/make_objective_icons.py).
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
    for _, a in ipairs(QA.LIST) do
        if a.ours() then
            if db[a.key] ~= false then
                db[a.key] = false
                off[a.key] = true
            end
        elseif off[a.key] then
            db[a.key] = true
            off[a.key] = nil
        end
    end
    if next(off) == nil then root.questieOff = nil end
    icons(q, db, root)
    return true
end

local function safeRun() DUI.SafeCall(QA.Run) end

-- The tracker or Skins settings changed (from their OnEnable and
-- OnSettingChanged).
DUI.On("QuestMapsChanged", safeRun)

-- Questie's settings appear when AceDB loads, which may be after our login.
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
