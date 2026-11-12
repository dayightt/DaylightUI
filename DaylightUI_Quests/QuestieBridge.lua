-- The one place that reads Questie's internals (when the player has Questie on).
-- Most of it isn't public API, so every read goes through a pcall with a type
-- check at each step, and any failure (a renamed module, a changed field) returns
-- nil so the caller falls back to its own way. Read-only, except for one hook on
-- Questie's functions (Bridge.WatchHover) and the highlight on its map icons
-- (Bridge.FocusIcons).
--
-- What it reads from Questie's source:
-- - QuestieLoader:ImportModule(name) returns the module, or an empty table for an
--   unknown name (Modules/Libs/QuestieLoader.lua:165).
-- - QuestieTooltips.lookupByKey["m_<npcId>"] = { [k] = { questId, starterId,
--   ... } }: quests that NPC starts and the player can take, filled by Questie's
--   available-quest pass (RegisterQuestStartTooltip, Tooltips/Tooltip.lua:78).
--   An entry with `objective` is a quest target, not a start.
-- - Questie.API.GetQuestObjectiveIconForUnit(guid) = an icon file path for the
--   first unfinished objective (Public/GetQuestObjectiveIconForUnit.lua,
--   Modules/QuestieNameplate.lua:315; Questie.icons in Questie.lua:230).

local _, ns = ...

local Bridge = {
    -- Icon file name (Questie.icons) -> objective kind. Questie's nameplates show its
    -- object kind as loot (QuestieNameplate.lua:329).
    KIND = { slay = "kill", loot = "loot", object = "use", interact = "use", event = "explore" },
}
ns.Bridge = Bridge

-- Reports the error only with the dev addon on, same as Skins' Engine.Broke.
local function broke(err)
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
    if type(loaded) == "function" and loaded("DaylightUI_Dev") then geterrorhandler()(err) end
end

local function safe(fn, ...)
    local ok, a = pcall(fn, ...)
    if not ok then broke(a); return nil end
    return a
end

local function api()
    local Q = _G.Questie
    return type(Q) == "table" and type(Q.API) == "table" and Q.API or nil
end

local function module(name)
    local L = _G.QuestieLoader
    if type(L) ~= "table" or type(L.ImportModule) ~= "function" then return nil end
    local m = L:ImportModule(name)
    return type(m) == "table" and m or nil
end

function Bridge.Loaded()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
    if type(loaded) ~= "function" or loaded("Questie") ~= true then return false end
    return type(_G.Questie) == "table"
end

-- One quest's icons grow and the other quests' fade, eased, on the world map and
-- minimap (while a quest name or one of its icons is hovered). id nil restores
-- them all. Only the frame's alpha and size are touched: Questie's own fades are
-- on the texture, and its frame alpha is only used for a party member's
-- objective at 0.5 (QuestieFrame.lua's draw), which is `base` here. A world map
-- icon sits CENTER on the map pin, so scale grows it in place and Questie's own
-- zoom rescale stays out of the way. A minimap icon is placed by an offset from
-- the minimap's center (HereBeDragons-Pins: `pin:SetPoint("CENTER", Minimap,
-- "CENTER", x, y)`), and a frame's scale scales its offset, which would push it
-- outward, so that one grows by SetSize (its textures fill the frame).
-- Each one is tracked in `lit` with its state so it's restored when left.
local lit = {}
local LIT_KEY = {}

-- Questie reused this frame for something else; its draw already reset alpha and
-- size, so only the scale is left to undo.
local function recycled(icon, e)
    if icon.data == e.data then return false end
    icon:SetScale(1)
    lit[icon] = nil
    return true
end

local function litStep(t)
    for icon, e in pairs(lit) do
        if not recycled(icon, e) then
            if t >= 1 then
                e.a, e.s = e.toA, e.toS
            else
                e.a, e.s = e.fromA + (e.toA - e.fromA) * t, e.fromS + (e.toS - e.fromS) * t
            end
            icon:SetAlpha(e.a)
            if e.fromS ~= e.toS then     -- fading icons keep their size
                if e.w then icon:SetSize(e.w * e.s, e.h * e.s) else icon:SetScale(e.s) end
            end
        end
    end
end

local function litDone()
    for icon, e in pairs(lit) do
        if e.toA == e.base and e.toS == 1 then lit[icon] = nil end
    end
end

function Bridge.FocusIcons(id, dim, grow)
    if not id and next(lit) == nil then return end
    safe(function()
        for icon, e in pairs(lit) do
            if not recycled(icon, e) then e.fromA, e.fromS, e.toA, e.toS = e.a, e.s, e.base, 1 end
        end
        local map = id and Bridge.Loaded() and module("QuestieMap")
        local byQuest = map and map.questIdFrames
        for quest, names in pairs(type(byQuest) == "table" and byQuest or {}) do
            for _, name in pairs(type(names) == "table" and names or {}) do
                local icon = _G[name]
                if type(icon) == "table" and icon:IsVisible() then
                    local e = lit[icon]
                    if not e then
                        local data = icon.data
                        local o = type(data) == "table" and data.ObjectiveData
                        local base = type(o) == "table" and o.IsPartyObjective and 0.5 or 1
                        e = { base = base, a = base, s = 1, fromA = base, fromS = 1, data = data }
                        if icon.miniMapIcon then e.w, e.h = icon:GetSize() end
                        lit[icon] = e
                    end
                    e.toA = quest == id and e.base or e.base * dim
                    e.toS = quest == id and grow or 1
                end
            end
        end
        local M = DaylightUI.Motion
        M.Tween(LIT_KEY, 0, 1, M.FAST, litStep, litDone)
    end)
end

-- Calls fn(questID) while one of Questie's icons is hovered on either map, and
-- fn(nil) when it's left; fn nil stops. Questie's own white flash over the
-- quest's other icons stays off meanwhile. Both come from one hook:
-- QuestieWaypoints.SetHighlighted(data, on) runs on every icon's enter and leave
-- and is looked up at call time (Tooltips/MapIconTooltip.lua:117), since each
-- icon's OnEnter is stored per frame from before this addon loads. The flash
-- right after it only runs while `data.touchedPins` is empty, and its reset on
-- leave clears what's set here.
function Bridge.WatchHover(fn)
    Bridge.onHover = fn
    if Bridge.hooked or not (fn and Bridge.Loaded()) then return end
    local m = module("QuestieWaypoints")
    if not (m and type(m.SetHighlighted) == "function") then return end
    Bridge.hooked = true
    hooksecurefunc(m, "SetHighlighted", function(data, on)
        if not Bridge.onHover or type(data) ~= "table" then return end
        if on then data.touchedPins = data.touchedPins or {} end
        safe(Bridge.onHover, on and type(data.Id) == "number" and data.Id or nil)
    end)
end

-- Quests this NPC starts that Questie says the player can take: { questID, ... }
-- (a sorted copy), or nil without Questie.
function Bridge.NpcQuests(npcID)
    if type(npcID) ~= "number" or not Bridge.Loaded() then return nil end
    return safe(function()
        local m = module("QuestieTooltips")
        local byKey = m and m.lookupByKey
        if type(byKey) ~= "table" then return nil end
        local out, seen = {}, {}
        local entries = byKey["m_" .. npcID]
        for _, e in pairs(type(entries) == "table" and entries or {}) do
            local id = type(e) == "table" and e.starterId ~= nil and e.questId
            if type(id) == "number" and not seen[id] then
                seen[id] = true
                out[#out + 1] = id
            end
        end
        table.sort(out)
        return out
    end)
end

-- What Questie would show on this unit's nameplate, as an objective kind.
function Bridge.PlateKind(guid)
    if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return nil end
    local a = Bridge.Loaded() and api()
    if not a or a.isReady ~= true or type(a.GetQuestObjectiveIconForUnit) ~= "function" then return nil end
    return safe(function()
        local path = a.GetQuestObjectiveIconForUnit(guid)
        if type(path) ~= "string" then return nil end
        local file = string.match(string.lower(path), "([%w_]+)%.%w+$")
        return file and Bridge.KIND[file] or nil
    end)
end
