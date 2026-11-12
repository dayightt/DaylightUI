-- Mouse handling on the list. On a quest: clicking its icon makes it the priority
-- (the minimap arrow points to it, clicking again clears it), click opens the map
-- to it (out of combat), shift-click stops tracking or links it into an open chat
-- box (each click's action is configurable, Clicks.Binding), right-click opens the
-- menu (Quest details opens the card in Details.lua), and hovering shows a tooltip
-- beside the list. Section headers and zone names fold. Achievements open their
-- window. Only safe game functions are called (C_Map.OpenWorldMap, never the
-- quest map's own Lua, which taints the map).

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Clicks = {}
ns.Clicks = Clicks

Clicks.MAP_IN_COMBAT = L["Can't open the map in combat."]
Clicks.IN_COMBAT = L["Can't do that in combat."]
Clicks.LINK_NO_CHAT = L["Open a chat box first to link it."]
-- Tooltip hints, one click per line.
Clicks.HINTS = { L["Click the icon: make it your priority"], L["Click: show on map"], L["Shift-click: stop tracking"],
                 L["Right-click: more"] }
-- The quest journal's rows (Journal.lua) have their own clicks.
Clicks.JOURNAL_HINTS = { L["Click: open it"], L["Shift-click: track or stop tracking"], L["Right-click: more"] }
-- What a click can do (clicks.click/shift/ctrl/alt on the Tracker page) and its
-- wording in a hint.
Clicks.ACTIONS = { "map", "details", "priority", "fold", "untrack", "link", "none" }
Clicks.ACTION_WORDS = { map = L["show on map"], details = L["quest details"], priority = L["make it your priority"],
                        fold = L["fold it"], untrack = L["stop tracking"],
                        link = L["link in chat"] }
Clicks.BUTTONS = { "click", "shift", "ctrl", "alt" }
Clicks.BUTTON_HINT = { click = L["Click: %s"], shift = L["Shift-click: %s"], ctrl = L["Ctrl-click: %s"], alt = L["Alt-click: %s"] }
Clicks.DEFAULT = { click = "map", shift = "untrack", ctrl = "priority", alt = "none" }
Clicks.ACH_HINTS = { L["Click: open achievements"], L["Shift-click: stop tracking"] }
Clicks.TIP_GAP = 44        -- keeps the tooltip clear of the item column (34 + 10)
Clicks.ICON_HIT = 18       -- the icon area of a quest row, up to where the title starts
Clicks.MENU_TEXT = { map = L["Show on map"], details = L["Quest details"], share = L["Share"],
                     untrack = L["Stop tracking"], abandon = L["Abandon"],
                     priority = L["Make it your priority"], fold = L["Fold this quest"],
                     turnin = L["Show hand-in on map"], link = L["Link in chat"], wowhead = L["Wowhead link"] }
-- Same link Questie's own Forever menu uses.
Clicks.WOWHEAD = "https://www.wowhead.com/forever/quest="

local function refuse(text)
    DUI.ShowError(text)
end

function Clicks.Attach(f)
    if f.clicksAttached then return end
    f.clicksAttached = true
    f:SetScript("OnClick", function(self, button) DUI.SafeCall(Clicks.OnClick, self, button) end)
    f:SetScript("OnEnter", function(self) DUI.SafeCall(Clicks.OnEnter, self) end)
    f:SetScript("OnLeave", function(self) DUI.SafeCall(Clicks.OnLeave, self) end)
end

-- mapID: a specific map (the turn-in's), otherwise the quest's.
function Clicks.OpenMap(questID, mapID)
    if InCombatLockdown() then refuse(Clicks.MAP_IN_COMBAT); return end
    if not (C_Map and C_Map.OpenWorldMap) then return end
    mapID = mapID or (type(GetQuestUiMapID) == "function" and GetQuestUiMapID(questID, true))
    pcall(C_Map.OpenWorldMap, (type(mapID) == "number" and mapID > 0) and mapID or nil)
    if EventRegistry and EventRegistry.TriggerEvent then
        EventRegistry:TriggerEvent("MapCanvas.PingQuestID", questID)
    end
end

-- Whether the mouse is in the icon area of the row (the row is a single button).
function Clicks.OnIcon(f)
    if type(f.IsMouseOver) ~= "function" then return false end
    local w, h = f:GetWidth() or 0, f:GetHeight() or 0
    return f:IsMouseOver(2, math.max(0, h - Clicks.ICON_HIT), -4, -math.max(0, w - Clicks.ICON_HIT)) == true
end

-- The game's priority quest: its icon in the gradient, the minimap arrow on it.
function Clicks.Focus(q)
    local ST = C_SuperTrack
    if not (ST and ST.SetSuperTrackedQuestID) then return end
    local on = ST.GetSuperTrackedQuestID and ST.GetSuperTrackedQuestID() == q.id
    if DUI.Sound then DUI.Sound.Play("click") end   -- same click as the journal's Focus
    ST.SetSuperTrackedQuestID(on and 0 or q.id)
end

-- Inserts the quest's link into an open chat box using the game's own insert,
-- like Book, Craft and Legacy do. Returns true if it went in. Never opens a box:
-- ChatFrame_OpenChat from addon code writes the box's fields tainted. Both the
-- tracker and the journal link through here; callers check
-- IsModifiedClick("CHATLINK") themselves.
function Clicks.LinkQuest(questID)
    local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
    local l = type(GetQuestLink) == "function" and GetQuestLink(questID)
    if type(insert) ~= "function" or type(l) ~= "string" or l == "" then return false end
    return insert(l) == true
end
local link = Clicks.LinkQuest

-- What the player set a click to do ("click", "shift", "ctrl", "alt").
function Clicks.Binding(button)
    local v = DUI:Get("Quests", "clicks." .. button)
    if v == "none" or Clicks.ACTION_WORDS[v] then return v end
    return Clicks.DEFAULT[button] or "none"
end

local function held()
    if IsShiftKeyDown and IsShiftKeyDown() then return "shift" end
    if IsControlKeyDown and IsControlKeyDown() then return "ctrl" end
    if IsAltKeyDown and IsAltKeyDown() then return "alt" end
    return "click"
end

-- Tooltip hints built from the bindings: the icon, each click that does
-- something, and the menu.
function Clicks.Hints()
    local out = { L["Click the icon: make it your priority"] }
    for _, b in ipairs(Clicks.BUTTONS) do
        local a = Clicks.Binding(b)
        if a ~= "none" then out[#out + 1] = Clicks.BUTTON_HINT[b]:format(Clicks.ACTION_WORDS[a]) end
    end
    out[#out + 1] = L["Right-click: more"]
    return out
end

function Clicks.Quest(q, button, f)
    if button == "RightButton" then return Clicks.Menu(q, f) end
    -- Chat box open: a click links first.
    if IsModifiedClick and IsModifiedClick("CHATLINK") and link(q.id) then return end
    local which = held()
    if which == "click" and Clicks.OnIcon(f) then return Clicks.Focus(q) end
    local action = Clicks.Binding(which)
    if which == "click" and action == "map" and q.auto then
        if type(ShowQuestComplete) == "function" then ShowQuestComplete(q.id) end
        return
    end
    if action ~= "none" then Clicks.Do(action, q) end
end

function Clicks.Achievement(a)
    if IsShiftKeyDown and IsShiftKeyDown() then
        local kinds, stop = Enum and Enum.ContentTrackingType, Enum and Enum.ContentTrackingStopType
        if C_ContentTracking and C_ContentTracking.StopTracking and kinds then
            C_ContentTracking.StopTracking(kinds.Achievement, a.id, stop and stop.Manual or 0)
        end
        return
    end
    if InCombatLockdown() then refuse(Clicks.IN_COMBAT); return end
    if type(OpenAchievementFrameToAchievement) == "function" then OpenAchievementFrameToAchievement(a.id) end
end

function Clicks.OnClick(f, button)
    local b = f.block
    if not b then return end
    if b.kind == "zone" and IsShiftKeyDown and IsShiftKeyDown() then ns.Tracker.FoldZoneQuests(b.label)
    elseif b.kind == "header" or b.kind == "zone" then ns.Tracker.ToggleFold(b.id)
    elseif b.kind == "ach" then Clicks.Achievement(b.ach, button)
    elseif b.kind == "quest" then Clicks.Quest(b.quest, button, f) end
end

-- The menu, Questie's entries in its own wording and order. Flat (the menu has
-- no submenus), each row only when it applies.
function Clicks.MenuKeys(q)
    local keys = { "priority", "fold", "map" }
    if q.state == "ready" and #ns.Spots.TurnIn(q.id) > 0 then keys[#keys + 1] = "turnin" end
    keys[#keys + 1] = "details"
    if ns.Journal.CanShare(q) then keys[#keys + 1] = "share" end
    keys[#keys + 1] = "wowhead"
    keys[#keys + 1] = "untrack"
    if ns.Journal.CanAbandon(q) then keys[#keys + 1] = "abandon" end
    return keys
end

local function priority(q)
    local ST = C_SuperTrack
    return ST and ST.GetSuperTrackedQuestID and ST.GetSuperTrackedQuestID() == q.id
end

-- Row labels for this quest. The toggles say what a click does right now.
function Clicks.MenuText(q)
    local t = {}
    for k, v in pairs(Clicks.MENU_TEXT) do t[k] = v end
    if priority(q) then t.priority = L["Stop being your priority"] end
    if ns.Tracker.Folds()["q" .. q.id] then t.fold = L["Unfold"] end
    return t
end

function Clicks.Do(k, q)
    if k == "map" then ns.Journal.OpenTo(q.id)
    elseif k == "details" then ns.Details.Toggle(q)
    elseif k == "priority" then Clicks.Focus(q)
    elseif k == "fold" then ns.Tracker.ToggleFold("q" .. q.id)
    elseif k == "turnin" then
        -- The turn-in's map; the ping lands on the quest there.
        local spot = ns.Spots.TurnIn(q.id)[1]
        ns.Journal.OpenTo(q.id, spot and spot.map)
    elseif k == "link" then
        if not link(q.id) then refuse(Clicks.LINK_NO_CHAT) end
    elseif k == "wowhead" then
        DUI.Widgets.Prompt(L["Wowhead link (Ctrl+C copies it):"], Clicks.WOWHEAD .. q.id)
    elseif k == "share" then
        ns.Journal.Share(q)
    elseif k == "untrack" then
        if C_QuestLog and C_QuestLog.RemoveQuestWatch then C_QuestLog.RemoveQuestWatch(q.id) end
    elseif k == "abandon" then
        -- A custom yes/no box. The game's QuestMapQuestOptions_AbandonQuest is quest
        -- map Lua, and called tainted its popup broke, the controller UI too.
        ns.Journal.AbandonPopup(q)
    end
end

function Clicks.Menu(q, f)
    local W = DUI.Widgets
    if not (W and W.OpenMenu) then return end
    W.OpenMenu(f, Clicks.MenuKeys(q), Clicks.MenuText(q), nil, function(k) DUI.SafeCall(Clicks.Do, k, q) end)
end

-- An objective's count as a color: red, amber, green once done.
local function objColor(o)
    local Tips = DUI.Tips
    if o.kind == "count" then return Tips.Progress(o.have, o.need) end
    if o.kind == "bar" then return Tips.Progress(o.pct, 100) end
    if o.done then return Tips.GOOD end
end

-- Same look as every DUI.Tips tooltip, with the clicks in the accent.
-- hints: the clicks for the row it belongs to (the tracker's by default).
function Clicks.QuestTip(q, hints)
    local GT, Tips = GameTooltip, DUI.Tips
    local look = ns.Tracker.Look()
    Tips.Clear()
    if not (IsInGroup and IsInGroup() and GT.SetQuestPartyProgress
            and pcall(GT.SetQuestPartyProgress, GT, q.id, false, false)) then
        Tips.Title(q.title, ns.Look.TitleColor(look, q))
        Tips.Sub(L["Level %s · %s"]:format(tostring(q.level or "?"), q.zone or ""))
        for _, o in ipairs(q.objs) do
            local right = o.kind == "count" and (o.have .. "/" .. o.need) or (o.kind == "bar" and (o.pct .. "%")) or ""
            Tips.Line(o.text, right, objColor(o))
        end
        local ok, money = pcall(GetQuestLogRewardMoney, q.id)
        if ok and type(money) == "number" and money > 0 then
            Tips.Gap()
            Tips.Line(L["Rewards"], DUI.MoneyString(money), Tips.MONEY)
        end
    end
    Tips.Gap()
    for _, h in ipairs(hints or Clicks.Hints()) do Tips.Hint(h) end
    Tips.Flush(GT)
end

function Clicks.AchievementTip(a)
    local Tips = DUI.Tips
    Tips.Clear()
    Tips.Title(a.title)
    for _, o in ipairs(a.objs) do
        if o.kind == "count" then Tips.Line(o.text, o.have .. "/" .. o.need, objColor(o)) else Tips.Sub(o.text) end
    end
    Tips.Gap()
    for _, h in ipairs(Clicks.ACH_HINTS) do Tips.Hint(h) end
    Tips.Flush(GameTooltip)
end

-- Under the mouse the icon lights up or the title lifts, depending on which part
-- the mouse is over. Follows the mouse while it's on the row.
function Clicks.Part(f)
    local b = f.block
    return (b and b.kind == "quest" and Clicks.OnIcon(f)) and "icon" or "row"
end

local function follow(self)
    local part = Clicks.Part(self)
    if part ~= self.hoverPart then
        self.hoverPart = part
        ns.Rows.Hover(self, part)
    end
end

function Clicks.OnEnter(f)
    if f.kind == "header" or f.kind == "zone" then
        ns.Rows.Hover(f, true)
    else
        f.hoverPart = nil
        follow(f)
        f:SetScript("OnUpdate", follow)
    end
    local b = f.block
    if b and (b.kind == "quest" or b.kind == "ach") then ns.Tracker.HoverDim(f) end
    if not (b and GameTooltip) or b.kind == "header" or b.kind == "zone" then return end
    if not DUI:Get("Quests", "rowTips") then return end
    GameTooltip:SetOwner(f, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPRIGHT", f, "TOPLEFT", -Clicks.TIP_GAP, 0)
    if b.kind == "quest" then
        Clicks.QuestTip(b.quest)
    else
        Clicks.AchievementTip(b.ach)
    end
    GameTooltip:Show()
end

function Clicks.OnLeave(f)
    if f.kind == "quest" or f.kind == "ach" then f:SetScript("OnUpdate", nil) end
    f.hoverPart = nil
    ns.Rows.Hover(f, false)
    if f.kind == "quest" or f.kind == "ach" then ns.Tracker.HoverDim(nil) end
    if GameTooltip then GameTooltip:Hide() end
end
