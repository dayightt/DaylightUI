-- The fake quest world for the quest tracker tests: the quest log and its zone
-- headers, the watch list, objectives, items, timers, tracked achievements, the
-- game's own tracker (to starve), and the calls the addon's clicks make.
-- QW.world(spec) returns stub.Load's "before". Tests change QW.state (quests,
-- zone...) and fire events.
local stub = require("stub")

local QW = {}

-- A quest as the tests describe it. Fields: zone, level, objs = { { text, have,
-- need, done, type } }, complete, failed, auto, turnIn, item = { link, icon,
-- charges }, itemRange, timer, pct, watched (false: not watched), text (the
-- quest's own text), xp, rewards = { { name, icon, count } }, choices,
-- difficulty (the server's verdict, Enum.RelativeContentDifficulty 0-4),
-- onParty (party units who have it too).
function QW.quest(id, title, fields)
    local q = { id = id, title = title, level = 15, zone = "Westfall", objs = {} }
    for k, v in pairs(fields or {}) do q[k] = v end
    return q
end

local function S() return QW.state end

-- The game's QuestDifficultyColors (Blizzard_Colors) by
-- Enum.RelativeContentDifficulty (DifficultyUtil.GetDifficultyColor).
QW.COLORS = {
    trivial = { r = 0.5, g = 0.5, b = 0.5 }, standard = { r = 0.25, g = 0.75, b = 0.25 },
    difficult = { r = 1, g = 0.82, b = 0 }, verydifficult = { r = 1, g = 0.5, b = 0.25 },
    impossible = { r = 1, g = 0.1, b = 0.1 },
}
QW.DIFFICULTY = { [0] = "trivial", "standard", "difficult", "verydifficult", "impossible" }

-- Each load gets its own copies, so a test changing a quest can't leak into
-- the next test that names the same quest table.
local function copy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = copy(v) end
    return c
end

local function find(id)
    for _, q in ipairs(S().quests) do if q.id == id then return q end end
end

-- The quest log: a header per zone (in order of first appearance) with its quests
-- under it.
local function log()
    local zones, byZone = {}, {}
    for _, q in ipairs(S().quests) do
        local z = q.zone or "Westfall"
        if not byZone[z] then byZone[z] = {}; zones[#zones + 1] = z end
        table.insert(byZone[z], q)
    end
    local flat = {}
    for _, z in ipairs(zones) do
        flat[#flat + 1] = { isHeader = true, title = z }
        for _, q in ipairs(byZone[z]) do
            flat[#flat + 1] = { title = q.title, level = q.level, questID = q.id, isAutoComplete = q.auto == true }
        end
    end
    return flat
end

local function watched()
    local out = {}
    for _, q in ipairs(S().quests) do if q.watched ~= false then out[#out + 1] = q.id end end
    return out
end

local function record(kind, value) table.insert(S().calls, { kind = kind, value = value }) end

-- Every value a kind of call was made with, in order.
function QW.Calls(kind)
    local out = {}
    for _, c in ipairs(S().calls) do if c.kind == kind then out[#out + 1] = c.value end end
    return out
end

local function indexOf(id)
    for i, e in ipairs(log()) do if e.questID == id then return i end end
end
local function atIndex(i) local e = log()[i]; return e and e.questID and find(e.questID) end

function QW.world(spec)
    return function()
        local s = copy(spec or {})
        QW.state = s
        s.quests = s.quests or {}
        s.zone = s.zone or "Westfall"
        s.achievements = s.achievements or {}
        s.calls = {}
        for _, name in ipairs(s.loaded or {}) do stub.loadedAddOns[name] = true end
        _G.Enum = _G.Enum or {}
        Enum.ContentTrackingType = { Achievement = 2 }
        Enum.ContentTrackingStopType = { Manual = 0 }
        _G.GetNumSubgroupMembers = function() return S().partySize or 0 end
        _G.C_QuestLog = {
            GetNumQuestLogEntries = function() return #log(), #S().quests end,
            GetMaxNumQuestsCanAccept = function() return 25 end,
            GetInfo = function(i) return log()[i] end,
            GetLogIndexForQuestID = indexOf,
            GetTitleForQuestID = function(id) local q = find(id); return q and q.title end,
            -- onParty = { "party1", ... } lists who else has it (spec.partySize: GetNumSubgroupMembers)
            IsUnitOnQuest = function(unit, id)
                for _, u in ipairs(find(id) and find(id).onParty or {}) do if u == unit then return true end end
                return false
            end,
            GetNumQuestWatches = function() return #watched() end,
            GetQuestIDForQuestWatchIndex = function(i) return watched()[i] end,
            GetQuestObjectives = function(id)
                local q, out = find(id), {}
                for _, o in ipairs(q and q.objs or {}) do
                    out[#out + 1] = { text = o.text, type = o.type or "monster", finished = o.done == true,
                                      numFulfilled = o.have or 0, numRequired = o.need or 0 }
                end
                return out
            end,
            IsComplete = function(id) local q = find(id); return q ~= nil and q.complete == true end,
            IsFailed = function(id) local q = find(id); return q ~= nil and q.failed == true end,
            -- a quest's kind: tagID (the game's QuestConsts: elite 1, dungeon 81, raid 62, PvP 41) and elite
            IsEliteQuest = function(id) local q = find(id); return q ~= nil and q.elite == true end,
            GetQuestTagInfo = function(id)
                local q = find(id)
                if q and q.tagID then return { tagID = q.tagID, tagName = "tag " .. q.tagID } end
            end,
            GetQuestTimers = function()
                local out = {}
                for _, q in ipairs(S().quests) do
                    if q.timer then out[#out + 1] = { questID = q.id, questTimer = q.timer } end
                end
                return out
            end,
            -- The game's tracker reads a timed quest this way (Blizzard_QuestObjectiveTracker.lua).
            -- MayReturnNothing. q.allowed = { total, elapsed }.
            GetTimeAllowed = function(id)
                local q = find(id)
                if q and q.allowed then return q.allowed[1], q.allowed[2] end
            end,
            RemoveQuestWatch = function(id) record("untrack", id); local q = find(id); if q then q.watched = false end end,
            AddQuestWatch = function(id) record("track", id); local q = find(id); if q then q.watched = nil end end,
            IsPushableQuest = function() return true end,
            -- Abandoning the way the game's quest log does it
            -- (QuestMapQuestOptions_AbandonQuest in QuestMapFrame.lua, plus the
            -- ABANDON_QUEST popup): select it, mark it, then AbandonQuest() with no arguments.
            GetSelectedQuest = function() return S().selected end,
            SetSelectedQuest = function(id) S().selected = id end,
            SetAbandonQuest = function() S().abandoning = S().selected end,
            AbandonQuest = function()
                local id = S().abandoning
                record("abandon", id)
                for i, q in ipairs(S().quests) do if q.id == id then table.remove(S().quests, i); break end end
                S().abandoning = nil
            end,
            CanAbandonQuest = function(id) local q = find(id); return q ~= nil and q.noAbandon ~= true end,
        }
        -- The game's two ways to a title's color. Its quest log asks the server
        -- (GetContentDifficultyQuestForPlayer, then GetDifficultyColor). The old
        -- level math still says yellow 4 levels under you, and is the only one of
        -- the two that goes orange and red above you
        -- (DifficultyUtil.GetRelativeDifficultyColor). The player's level is
        -- `playerLevel` in the world.
        _G.UnitEffectiveLevel = function() return S().playerLevel or 15 end
        _G.QuestDifficultyColors = QW.COLORS
        _G.GetQuestDifficultyColor = function(level)
            local above = level - _G.UnitEffectiveLevel("player")
            if above >= 5 then return QW.COLORS.impossible end
            if above >= 3 then return QW.COLORS.verydifficult end
            return QW.COLORS.difficult
        end
        _G.C_PlayerInfo = { GetContentDifficultyQuestForPlayer = function(id)
            local q = find(id); return q and q.difficulty or 2
        end }
        _G.GetDifficultyColor = function(d) return QW.COLORS[QW.DIFFICULTY[d]] or QW.COLORS.difficult end
        _G.GetQuestLogCompletionText = function(i) local q = atIndex(i); return q and q.turnIn end
        _G.GetQuestLogSpecialItemInfo = function(i)
            local q = atIndex(i)
            if q and q.item then return q.item.link, q.item.icon, q.item.charges end
        end
        _G.GetQuestLogSpecialItemCooldown = function() return 0, 0, 1 end
        _G.IsQuestLogSpecialItemInRange = function(i) local q = atIndex(i); return q and q.itemRange or 1 end
        _G.GetQuestProgressBarPercent = function(id) local q = find(id); return q and q.pct or 0 end
        _G.GetRealZoneText = function() return S().zone end
        _G.GetQuestUiMapID = function() return 52 end
        _G.GetQuestLogRewardMoney = function() return 150 end
        _G.GetMoneyString = function(c) return c .. "c" end
        _G.C_Map = { OpenWorldMap = function(mapID) record("map", mapID) end }
        _G.C_SuperTrack = {
            GetSuperTrackedQuestID = function() return S().focus or 0 end,
            SetSuperTrackedQuestID = function(id) record("focus", id); S().focus = id end,
        }
        -- Callbacks by event in the order registered (CallbackRegistryMixin). The
        -- map ping the addon's clicks fire is recorded.
        local cbs = {}
        _G.EventRegistry = {
            RegisterCallback = function(_, e, fn, owner)
                cbs[e] = cbs[e] or {}
                cbs[e][#cbs[e] + 1] = { fn, owner }
            end,
            UnregisterCallback = function(_, e, owner)
                for i = #(cbs[e] or {}), 1, -1 do if cbs[e][i][2] == owner then table.remove(cbs[e], i) end end
            end,
            TriggerEvent = function(_, e, ...)
                if e == "MapCanvas.PingQuestID" then record("ping", (...)) end
                for _, c in ipairs(cbs[e] or {}) do c[1](c[2], ...) end
            end,
        }
        _G.UIErrorsFrame = { AddExternalErrorMessage = function(_, text) record("error", text) end }
        -- The game's quest popup. The addon's clicks must never call it (it taints the quest map).
        _G.QuestLogPopupDetailFrame = { ShowQuest = function(_, id) record("popup", id) end }
        _G.GetQuestLogQuestText = function(i) local q = atIndex(i); return q and q.text, q and q.logText end
        _G.GetQuestLogRewardXP = function(id) local q = find(id); return q and q.xp or 0 end
        _G.GetNumQuestLogRewards = function(id) local q = find(id); return q and q.rewards and #q.rewards or 0 end
        _G.GetQuestLogRewardInfo = function(i, id)
            local r = find(id).rewards[i]
            return r.name, r.icon, r.count, r.quality, true, r.itemID
        end
        -- The game's own reward click (QuestInfoRewardItemMixin:OnClick) asks with only the
        -- kind and index, so the link is the log's selected quest's.
        _G.GetQuestLogItemLink = function(kind, i)
            local q = find(S().selected)
            local list = q and (kind == "choice" and q.choices or q.rewards)
            local r = type(list) == "table" and list[i]
            return r and r.itemID and ("|Hitem:" .. r.itemID .. "::log|h[" .. r.name .. "]|h") or nil
        end
        -- choices: a count (the tracker only counts them) or a list like rewards.
        _G.GetNumQuestLogChoices = function(id)
            local q = find(id)
            local c = q and q.choices
            return type(c) == "table" and #c or c or 0
        end
        _G.GetQuestLogChoiceInfo = function(i, id)
            local c = find(id).choices
            local r = type(c) == "table" and c[i]
            if r then return r.name, r.icon, r.count, r.quality, true, r.itemID end
        end
        -- Blocked for addons in a fight: "the game blocked QuestLogPushQuest()"
        -- (ADDON_ACTION_BLOCKED in game, with combat lockdown on).
        _G.QuestLogPushQuest = function(i) record(InCombatLockdown() and "shareBlocked" or "share", i) end
        _G.ShowQuestComplete = function(id) record("complete", id) end
        _G.QuestMapQuestOptions_AbandonQuest = function(id) record("abandon", id) end
        _G.OpenAchievementFrameToAchievement = function(id) record("achievement", id) end
        _G.PlaySound = function(id) record("sound", id) end
        _G.PlaySoundFile = function(file) record("soundFile", file) end
        _G.SOUNDKIT = { IG_QUEST_LIST_COMPLETE = 878, IG_QUEST_LOG_ABANDON_QUEST = 846 }
        _G.IsShiftKeyDown = function() return S().shift == true end
        _G.IsControlKeyDown = function() return S().ctrl == true end
        _G.IsAltKeyDown = function() return S().alt == true end
        _G.IsModifiedClick = function() return false end
        _G.C_ContentTracking = {
            GetTrackedIDs = function()
                local out = {}
                for _, a in ipairs(S().achievements) do out[#out + 1] = a.id end
                return out
            end,
            StopTracking = function(_, id) record("stopAchievement", id) end,
        }
        local function ach(id) for _, a in ipairs(S().achievements) do if a.id == id then return a end end end
        _G.GetAchievementInfo = function(id) local a = ach(id); if a then return id, a.title, 10, a.done == true end end
        _G.GetAchievementNumCriteria = function(id) local a = ach(id); return a and #a.criteria or 0 end
        _G.GetAchievementCriteriaInfo = function(id, i)
            local c = ach(id).criteria[i]
            return c.text, 0, c.done == true, c.have or 0, c.need or 0
        end
        local tip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
        tip.lines, tip.colors = {}, {}
        function tip:ClearLines() self.lines, self.colors = {}, {} end
        function tip:SetOwner(o, anchor) self.lines, self.colors, self.__owner, self.__anchor = {}, {}, o, anchor end
        -- Each line's colors too (left, right), by its place in lines.
        function tip:AddLine(t, r, g, b)
            table.insert(self.lines, t)
            self.colors[#self.lines] = { lc = { r, g, b } }
        end
        function tip:SetQuestLogItem(kind, i, id) record("questItemTip", kind .. ":" .. i .. ":" .. id) end
        function tip:AddDoubleLine(l, r, lr, lg, lb, rr, rg, rb)
            table.insert(self.lines, l .. " | " .. tostring(r))
            self.colors[#self.lines] = { lc = { lr, lg, lb }, rc = { rr, rg, rb } }
        end
        -- The game's tracker, as far as the switch-off touches it.
        _G.ObjectiveTrackerManager = {
            AddContainer = function() end, AssignModulesOrder = function() end,
            SetModuleContainer = function() end, UpdateAll = function() end,
        }
        QW.originals = {}
        for k, v in pairs(ObjectiveTrackerManager) do QW.originals[k] = v end
        local otf = CreateFrame("Frame", "ObjectiveTrackerFrame", UIParent)
        otf:EnableMouse(true)
        -- Its background (Blizzard_ObjectiveTrackerContainer.xml). Only the game's
        -- AddContainer -> OnAdded ever turns it down to the Edit Mode opacity, so a
        -- starved tracker keeps it at full alpha.
        otf.NineSlice = CreateFrame("Frame", nil, otf)
        otf.Header = CreateFrame("Frame", nil, otf)
        otf.Header:EnableMouse(true)
        otf.Header.MinimizeButton = CreateFrame("Button", nil, otf.Header)
        CreateFrame("Frame", "QuestTimerFrame", otf):EnableMouse(true)
        if s.map then QW.map() end
    end
end

-- The world map and its quest log panel, as far as the journal touches them
-- (AttachQuestLog in Blizzard_WorldMap puts QuestMapFrame onto WorldMapFrame at
-- strata HIGH; its list, details and background are its own pieces.)
-- QW.ShowLog(on) is L: the map with the panel. The panel alone hides with the side
-- toggle (the game's SetQuestLogPanelShown shows and hides it).
function QW.map()
    local map = CreateFrame("Frame", "WorldMapFrame", UIParent)
    map:Hide()
    local qm = CreateFrame("Frame", "QuestMapFrame", map)
    qm:SetFrameStrata("HIGH")
    qm:SetSize(330, 500)
    qm.Background = qm:CreateTexture(nil, "BACKGROUND")
    qm.QuestsFrame = CreateFrame("Frame", nil, qm)
    qm.QuestsFrame:SetAllPoints(qm)
    qm.QuestsFrame:EnableMouse(true)
    qm:Hide()
    -- The map's canvas (MapCanvasMixin: ScrollContainer.Child), the map it shows,
    -- its pin level table, and its own code the journal must never call (the game's
    -- quest log row lights the blob through it).
    map.ScrollContainer = CreateFrame("ScrollFrame", nil, map)
    map.ScrollContainer.Child = CreateFrame("Frame", nil, map.ScrollContainer)
    map.mapID = 37
    map.pinFrameLevelsManager = { definitions = { PIN_FRAME_LEVEL_QUEST_BLOB = { startLevel = 2007 } } }
    -- Its quest pins (QuestDataProvider's "QuestPinTemplate" pool). A plain pool's
    -- EnumerateActive is pairs(activeObjects), with the pin as the key.
    local active = {}
    map.pinPools = { QuestPinTemplate = { activeObjects = active,
        EnumerateActive = function(self) return pairs(self.activeObjects) end } }
    for _, id in ipairs({ 1, 3 }) do
        local pin = CreateFrame("Button", nil, map.ScrollContainer.Child)
        pin.questID = id
        pin:SetFrameLevel(2100)
        pin.HighlightTexture = pin:CreateTexture()
        pin.HighlightTexture:Hide()
        active[pin] = true
    end
    for _, name in ipairs({ "SetHighlightedQuestID", "ClearHighlightedQuestID", "SetFocusedQuestID", "TriggerEvent" }) do
        map[name] = function() table.insert(QW.state.calls, { kind = "mapCode", value = name }) end
    end
    Enum.UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 }
    C_Map.GetMapInfo = function(id) return { mapID = id, mapType = QW.state.mapType or 3 } end
end

function QW.ShowLog(on)
    if on then WorldMapFrame:Show(); QuestMapFrame:Show() else WorldMapFrame:Hide() end
end

-- What the info panel reads as it loads (its own tests' world has more): the
-- minimap and its cluster, experience, and an empty damage meter.
function QW.panelWorld()
    -- The damage meter: the fake game's own (stub.DamageMeter), empty.
    local cluster = CreateFrame("Frame", "MinimapCluster", UIParent)
    cluster.IndicatorFrame = CreateFrame("Frame", nil, cluster)
    cluster.Tracking = CreateFrame("Frame", nil, cluster)
    CreateFrame("Button", "GameTimeFrame", cluster)
    local mm = CreateFrame("Frame", "Minimap", cluster)
    mm.ZoomIn = CreateFrame("Button", nil, mm)
    function mm:GetZoom() return 2 end
    _G.UnitXP = function() return 300 end
    _G.UnitXPMax = function() return 1200 end
    _G.GetXPExhaustion = function() return 400 end
    _G.IsPlayerAtEffectiveMaxLevel = function() return false end
end

return QW
