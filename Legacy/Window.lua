-- Legacy window with three tabs: Progress, Challenges and Legacy trees. The game still
-- runs its own: the Legacy micro button (ToggleLegacySystemUI), the achievement key
-- (ToggleLegacyChallenges) and clicking a tracked challenge (ShowLegacyChallenge) load
-- and open LegacySystemFrame (Blizzard_LegacySystem, load on demand; never loaded from
-- here). It's parked under the kit's hidden frame as it loads (Win.Follow), and this
-- window shows in its place and closes with it.
--
-- The requested page is the frame's currentPage, set before it shows
-- (LegacySystemFrameMixin:SelectPage). While open, the game's "Legacy.SelectPage"
-- (EventRegistry) switches this window's page too. Nothing here is protected, so it
-- opens and closes in combat.

local _, DUI = ...
DUI.Legacy = DUI.Legacy or {}
local ns = DUI.Legacy
local L = DUI.L
local Win = DUI.Win
local Style = DUI.Style

local Legacy = {}
ns.Window = Legacy

Legacy.NAME = "DaylightUILegacy"
Legacy.W, Legacy.H = 780, 580
Legacy.MIN_H = 480
Legacy.ICON = "Interface\\Icons\\Achievement_GuildPerk_HonorableMention"   -- the game's Challenges tab icon
Legacy.PAGES = { "progress", "challenges", "trees" }
Legacy.GAME_PAGE = { [1] = "progress", [2] = "challenges", [3] = "trees" }   -- the game's page ids (LegacySystemFrame.Pages)

Legacy.page = "progress"   -- page to open on: the last one shown this session

function ns.Setting(key) return ns.module and ns.module.db and ns.module.db[key] end

function Legacy.Game()
    local g = _G.LegacySystemFrame
    return type(g) == "table" and g or nil
end

local function pageOf(id)
    return id == "progress" and ns.Progress or id == "challenges" and ns.Challenges or ns.Trees
end

local function pop(n) return Win.Parts.Hex({ Style.Pop() }) .. tostring(n) .. "|r" end

-- Header: points earned and left to spend; new challenges on their tab

function Legacy.Header()
    local f = Legacy.frame
    if not f then return end
    local p = ns.Data.Points()
    local sub = string.format(L["%s Legacy Points"], pop(p.earned)) .. "  ·  " .. string.format(L["%s to spend"], pop(p.left))
    Win.SetTitle(f, L["Legacy"], nil, sub)
    Style.InkText(f.sub, "LABEL")   -- labels tan, numbers in the accent
    local tab = Legacy.Tab("challenges")
    if tab then
        local n = ns.Data.UnviewedCount()
        local word = L["Challenges"]
        tab.text:SetText(n > 0 and (word .. " " .. pop(n)) or word)
        tab.FitWidth()
        Legacy.FitTitle()
    end
end

function Legacy.Tab(id)
    for _, b in ipairs(Legacy.frame and Legacy.frame.tabs or {}) do if b.id == id then return b end end
end

-- Title and sub line stop short of the tabs.
function Legacy.FitTitle()
    local f = Legacy.frame
    local room = 40
    for _, b in ipairs(f.tabs or {}) do room = room + b:GetWidth() + Win.TAB_GAP end
    f.title:SetPoint("RIGHT", f, "RIGHT", -room, 0)
    if f.sub then f.sub:SetPoint("RIGHT", f, "RIGHT", -room, 0) end
end

-- Pages

function Legacy.ShowTab(id)
    local f = Legacy.frame
    if not f then return end
    Legacy.page = id
    Win.PickTab(f, id)
    Win.ShowPage(f, id)
end

-- Repaint whatever changed once, next frame (renown and currency events come in pairs).
local dirty = {}
function Legacy.Refresh(what)
    -- Closed: nothing to paint; opening renders the page (Legacy.Open).
    if not (Legacy.frame and Win.IsOpen(Legacy.frame)) then return end
    dirty[what or "all"] = true
    if Legacy.waiting then return end
    Legacy.waiting = true
    C_Timer.After(0, function()
        Legacy.waiting = false
        local d = dirty
        dirty = {}
        local f = Legacy.frame
        if not (f and Win.IsOpen(f)) then return end
        Legacy.Header()
        local P = pageOf(f.current)
        if P and P.Render and (d.all or d[f.current]) then P.Render(true) end
    end)
end

-- Open, close, follow the game's frame

local function spot()
    local s = ns.module and ns.module.db and ns.module.db.spot
    if type(s) == "table" and type(s[1]) == "number" and type(s[2]) == "number" then return s end
    return nil
end

local function place(f)
    local s = spot()
    if s then return Win.PlaceTop(f, s[1], s[2]) end
    f:ClearAllPoints()
    local g = Legacy.Game()
    if g then f:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
    else f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116) end
end

-- The page the game's frame was opened on.
function Legacy.AskedPage()
    local g = Legacy.Game()
    return g and Legacy.GAME_PAGE[g.currentPage] or nil
end

function Legacy.Open(page)
    local f = Legacy.frame
    if not f then return end
    if page then Legacy.page = page end
    Legacy.Header()
    if Win.IsOpen(f) then return Legacy.ShowTab(Legacy.page) end
    place(f)
    Legacy.ShowTab(Legacy.page)
    Win.Open(f)
    if Legacy.follow then Win.Followers.WriteWidth(Legacy.follow) end
end

-- Closing under the mouse: the hovered piece never gets OnLeave.
local function shut(f)
    local tip = GameTooltip
    local owner = tip and tip:IsShown() and tip:GetOwner()
    while owner do
        if owner == f then tip:Hide(); break end
        owner = owner:GetParent()
    end
    if DUI.Widgets.CloseMenu then DUI.Widgets.CloseMenu() end
    Win.Close(f)
end

-- Close this one now; the game's closes its own way (HideUIPanel).
function Legacy.Close()
    local f = Legacy.frame
    if not f then return end
    shut(f)
    local g = Legacy.Game()
    if not (g and g:IsShown()) then return end
    if InCombatLockdown() and g:IsProtected() then
        DUI.AfterCombat(function()
            local now = Legacy.Game()
            if now and now:IsShown() and not Win.IsOpen(Legacy.frame) then HideUIPanel(now) end
        end, "legacy:close")
        return
    end
    HideUIPanel(g)
end

-- Follower callback: the game's frame shown or hidden.
function Legacy.Changed(_, shown)
    local f = Legacy.frame
    if not shown then
        if Win.IsOpen(f) then shut(f) end
        return
    end
    local want = Legacy.wanted
    Legacy.wanted = nil
    if want then ns.Challenges.Want(want) end
    Legacy.Open(want and "challenges" or Legacy.AskedPage())
end

-- The game switching its own page while this window is open (the achievement key on an
-- open window, clicking a tracked challenge).
function Legacy.GamePage(id)
    local f = Legacy.frame
    local page = Legacy.GAME_PAGE[id]
    if not (f and page and Win.IsOpen(f)) then return end
    if Legacy.wanted then
        ns.Challenges.Want(Legacy.wanted)
        Legacy.wanted = nil
        if f.current == "challenges" then return ns.Challenges.Render() end
    end
    if f.current ~= page then Legacy.ShowTab(page) end
end

-- ShowLegacyChallenge(achievementID): open on that challenge. Global post-hook; the game
-- opens its frame first, then switches the page.
function Legacy.Asked(achievementID)
    if type(achievementID) ~= "number" then return end
    Legacy.wanted = achievementID
    local f = Legacy.frame
    if f and Win.IsOpen(f) then Legacy.GamePage(2) end
end

function Legacy.SaveSpot(x, y)
    local db = ns.module and ns.module.db
    if db then db.spot = { DUI.Pixel.Snap(UIParent, x), DUI.Pixel.Snap(UIParent, y) } end
end

-- Lay out the visible page for the grip's size (live while dragging, rows only
-- stretched).
function Legacy.Resized(_, _, live)
    local f = Legacy.frame
    if not (f and Win.IsOpen(f)) then return end
    local P = pageOf(f.current)
    if live then
        if P and P.Stretch then P.Stretch() end
        return
    end
    if P and P.Render then P.Render(true) end
end

-- Current page size (the grip's, or the created size).
function Legacy.PageSize()
    local w, h = Legacy.W, Legacy.H
    if Legacy.sizer then w, h = Legacy.sizer.Size(Legacy.page) end
    return w, h - Win.HEADER - 1
end

-- Right-click on the header (or /dui reset): back to the game's spot and size.
function Legacy.ResetSpot()
    local db = ns.module and ns.module.db
    if not db then return end
    if Legacy.sizer then Legacy.sizer.Reset() end
    if not db.spot then return end
    db.spot = nil
    if Legacy.frame and Win.IsOpen(Legacy.frame) then place(Legacy.frame) end
end

function Legacy.Apply()
    local f = Legacy.frame
    if not f then return end
    f:SetScale(Win.Scale(ns.Setting("scale")))
    if spot() and Win.IsOpen(f) then place(f) end
    Win.Repaint(f)
    if Win.IsOpen(f) then
        Legacy.Header()
        local P = pageOf(f.current)
        if P and P.Render then P.Render(true) end
    end
    if Legacy.follow then Win.Followers.WriteWidth(Legacy.follow) end
end

local hooked
local function hookAsk()
    if hooked or type(_G.ShowLegacyChallenge) ~= "function" then return end
    hooked = true
    hooksecurefunc("ShowLegacyChallenge", function(id) Legacy.Asked(id) end)
end

-- Controller, matching the game's Legacy footers (Blizzard_LegacySystem): on a
-- challenge X links it; in a tree A adds a point, Y removes one (or undoes changes), X
-- applies; the menu button searches.
function Legacy.PadSetup(f)
    local function spend() return ns.Trees and ns.Trees.Spend end
    local function node(b) return f.current == "trees" and type(b) == "table" and b.node or nil end
    local function search()
        local P = f.current == "challenges" and ns.Challenges or f.current == "trees" and ns.Trees or nil
        return P and P.page and P.page.search
    end
    f.padSelect = function(b)
        if node(b) then return GAMEPAD_TALENT_ADD_POINT or L["Add point"] end
    end
    f.padKeys = {
        { key = "X", label = SOCIAL_SHARE_TEXT or L["Link in chat"],
          when = function(b) return f.current == "challenges" and type(b) == "table" and b.ch ~= nil end,
          run = function(b) ns.Data.Link(b.ch.id, true) end },
        { key = "X", label = GAMEPAD_TALENT_APPLY or L["Apply"],
          when = function() return f.current == "trees" and spend() and spend().HasChanges() end,
          run = function() if spend().Apply() then ns.Trees.Buttons() end end },
        { key = "Y", label = GAMEPAD_TALENT_REMOVE_POINT or L["Remove point"],
          when = function(b) local n = node(b); return n ~= nil and spend().CanRefund(n) end,
          run = function(b) if spend().Refund(node(b)) then ns.Trees.Soon() end end },
        { key = "Y", label = L["Undo"],
          when = function() return f.current == "trees" and spend() and spend().HasChanges() end,
          run = function() if spend().Undo() then ns.Trees.Soon() end end },
        { key = "MENU_LEFT", label = SEARCH or L["Search"], when = function(b) local s = search(); return s ~= nil and b ~= s end,
          run = function() search():SetFocus() end },
    }
end

function Legacy.Build(mod)
    ns.module = mod
    if Legacy.frame then return Legacy.frame end
    local f = Win.New({ name = Legacy.NAME, back = "Legacy", w = Legacy.W, h = Legacy.H, portrait = true })
    Legacy.frame = f
    f.onClose = Legacy.Close
    Win.SetIcon(f, Legacy.ICON)
    for _, id in ipairs(Legacy.PAGES) do
        local P = pageOf(id)
        Win.AddPage(f, id, { Build = P.Build, Fill = P.Fill, pieces = P.Pieces, w = Legacy.W, h = Legacy.H })
        Win.Build(f, id)
    end
    Win.Tabs(f, { { id = "progress", text = L["Progress"] }, { id = "challenges", text = L["Challenges"] },
        { id = "trees", text = L["Legacy trees"] } }, function(id) Legacy.ShowTab(id) end)
    Legacy.PadSetup(f)
    Win.Drag(f, { save = Legacy.SaveSpot, reset = Legacy.ResetSpot })
    Win.WheelScale(f, function() return ns.Setting("scale") end, function(v) DUI:Set("Legacy", "scale", v) end)
    Legacy.sizer = Win.Resizable(f, { db = function() return ns.module and ns.module.db end,
        base = function() return Legacy.W, Legacy.H end, shared = true, minH = Legacy.MIN_H,
        save = Legacy.SaveSpot, resized = Legacy.Resized, follow = function() return Legacy.follow end })
    DUI.Movers.onResetAll[#DUI.Movers.onResetAll + 1] = Legacy.ResetSpot   -- /dui reset
    for _, e in ipairs({ "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "TRAIT_TREE_CURRENCY_INFO_UPDATED" }) do
        DUI.RegisterEvent(e, function() Legacy.Refresh() end)
    end
    if type(EventRegistry) == "table" and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("Legacy.SelectPage", function(_, id) Legacy.GamePage(id) end, Legacy)
        EventRegistry:RegisterCallback("Legacy.UnviewedChallengesUpdated", function() Legacy.Refresh("challenges") end, Legacy)
    end
    hookAsk()
    DUI.RegisterEvent("ADDON_LOADED", function() hookAsk() end)
    Legacy.follow = Win.Follow({ key = "legacy", frames = { legacy = Legacy.Game }, changed = Legacy.Changed,
        width = function() return (Legacy.sizer and Legacy.sizer.Size(Legacy.page) or Legacy.W) * Win.Scale(ns.Setting("scale")) end })
    Legacy.Apply()
    return f
end
