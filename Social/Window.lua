-- Social window with four tabs: Friends, Recent allies, Requests and Raid. The game
-- still runs its own: O (ToggleFriendsFrame), ToggleRaidFrame and the micro button
-- open SocialUIFrame (Blizzard_SocialUI), which is parked under the kit's hidden frame
-- (Win.Follow). This window shows in its place and closes with it.
--
-- The tab the game was asked to open (ToggleRaidFrame, ToggleFriendsFrame(tab)) waits
-- in its frame for OnShow (Reset) to consume it. Parked, that never runs, so this window
-- takes it with the game's own ConsumeDeferredOpenTab.
-- Nothing here is protected (SocialUIFrame isn't, and the Raid page's target buttons
-- live in their own layer, see Raid.lua), so it opens and closes in combat too, like
-- the group finder.

local _, DUI = ...
DUI.Social = DUI.Social or {}
local ns = DUI.Social
local L = DUI.L
local Win = DUI.Win
local Style = DUI.Style

local Social = {}
ns.Window = Social

Social.NAME = "DaylightUISocial"
Social.W, Social.H = 520, 600   -- four header tabs, with room beside them for status and friends online
Social.RAID_W = 700          -- eight groups side by side need a wider window
Social.MIN_H = 460
Social.ICON = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"
Social.PAGES = { "friends", "allies", "requests", "raid" }
-- The game's tab ids (SocialUITabType) mapped to page names.
Social.GAME_TAB = { [1] = "friends", [2] = "requests", [4] = "raid", [6] = "allies" }

Social.page = "friends"   -- page to open on: the last one shown this session

-- Status labels and their dot colors (header and friend rows).
Social.STATUS = { "on", "away", "busy" }
Social.STATUS_WORD = { on = L["Available"], away = L["Away"], busy = L["Busy"], off = L["Offline"] }
function Social.StatusColor(status)
    local I = Style.INK
    return status == "on" and I.GOOD or status == "away" and I.WARN or status == "busy" and I.BAD or I.OFF
end

function ns.Setting(key) return ns.module and ns.module.db and ns.module.db[key] end

function Social.Game()
    local g = _G.SocialUIFrame
    return type(g) == "table" and g or nil
end

local function pageOf(id)
    return id == "friends" and ns.Friends or id == "allies" and ns.Allies or id == "requests" and ns.Requests or ns.Raid
end

-- Header: title, the player's status (a link that opens the menu), friends online,
-- and pending requests on their tab

function Social.Header()
    local f = Social.frame
    if not f then return end
    Win.SetTitle(f, SOCIAL_LABEL or L["Social"], nil, "")
    local status = ns.Data.Me()
    local c = Social.StatusColor(status)
    f.statusDot:SetVertexColor(c[1], c[2], c[3], 1)
    f.status.SetLabel(Social.STATUS_WORD[status])
    local on = ns.Data.Online()
    f.online:SetText("·  " .. string.format(L["%s online"], Win.Parts.Hex({ Style.Pop() }) .. on .. "|r"))
    -- Requests: count on its tab, in the accent.
    local n = #ns.Data.Invites()
    local tab = Social.Tab("requests")
    if tab then
        local word = L["Requests"]
        tab.text:SetText(n > 0 and (word .. " " .. Win.Parts.Hex({ Style.Pop() }) .. n .. "|r") or word)
        tab.FitWidth()
        Social.FitTitle()
    end
end

function Social.Tab(id)
    for _, b in ipairs(Social.frame and Social.frame.tabs or {}) do if b.id == id then return b end end
end

-- Title and sub line stop short of the tabs (Win.Tabs' width, rechecked after a tab's
-- label changes).
function Social.FitTitle()
    local f = Social.frame
    local room = 40
    for _, b in ipairs(f.tabs or {}) do room = room + b:GetWidth() + Win.TAB_GAP end
    f.title:SetPoint("RIGHT", f, "RIGHT", -room, 0)
end

-- Available, Away, Busy, broadcast: only from a click (the calls require one).
function Social.StatusMenu(owner)
    local keys = { "on", "away", "busy", "broadcast" }
    local values = { on = Social.STATUS_WORD.on, away = Social.STATUS_WORD.away, busy = Social.STATUS_WORD.busy,
        broadcast = L["Broadcast..."] }
    DUI.Widgets.OpenMenu(owner, keys, values, (ns.Data.Me()), function(k)
        if k == "broadcast" then
            local _, now = ns.Data.Me()
            DUI.Widgets.Prompt(L["Broadcast to your friends:"], now or "", function(text) ns.Data.Broadcast(text) end, { now = true })
        else
            ns.Data.SetStatus(k)
        end
    end, 160)
end

local function makeStatus(f)
    f.statusDot = f:CreateTexture(nil, "ARTWORK")
    f.statusDot:SetTexture(DUI.MEDIA .. "shape-circle.png")
    f.statusDot:SetSize(7, 7)
    f.statusDot:SetPoint("TOPLEFT", f.sub, "TOPLEFT", 0, -3)
    f.status = DUI.Widgets.Link(f, Style.SIZE.small)
    f.status:SetPoint("LEFT", f.statusDot, "RIGHT", 5, 0)
    f.status:SetScript("OnClick", function(self) Social.StatusMenu(self) end)
    f.online = Style.Text(f, Style.SIZE.small, "LEFT")
    f.online:SetPoint("LEFT", f.status, "RIGHT", 6, 0)
    f.online:SetWordWrap(false)
    Style.InkText(f.online, "LABEL")
end

-- Pages

-- Tab click shows that page. Since it's a real click, a page may query the game
-- (recent allies, saved raids).
function Social.ShowTab(id, clicked)
    local f = Social.frame
    if not f then return end
    Social.page = id
    Win.PickTab(f, id)
    Win.ShowPage(f, id)
    local P = pageOf(id)
    if clicked and P and P.Clicked then P.Clicked() end
end

-- Repaint whatever changed once, next frame (the client sends BN_FRIEND_INFO_CHANGED in
-- bursts).
local dirty = {}
function Social.Refresh(what)
    -- Closed: nothing to paint; opening renders the page (Social.Open).
    if not (Social.frame and Win.IsOpen(Social.frame)) then return end
    dirty[what or "all"] = true
    if Social.waiting then return end
    Social.waiting = true
    C_Timer.After(0, function()
        Social.waiting = false
        local d = dirty
        dirty = {}
        local f = Social.frame
        if not (f and Win.IsOpen(f)) then return end
        Social.Header()
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
    local g = Social.Game()
    if g then f:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
    else f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116) end
end

-- The tab the game was asked for, if any (consumed with the game's own call).
function Social.AskedTab()
    local g = Social.Game()
    if not (g and type(g.ConsumeDeferredOpenTab) == "function") then return nil end
    local ok, tab = pcall(g.ConsumeDeferredOpenTab, g)
    return ok and Social.GAME_TAB[tab] or nil
end

function Social.Open(page)
    local f = Social.frame
    if not f then return end
    if page then Social.page = page end
    Social.Header()
    if Win.IsOpen(f) then return Social.ShowTab(Social.page) end
    place(f)
    Social.ShowTab(Social.page)
    Win.Open(f)
    if Social.page == "raid" then ns.Raid.Sync() end   -- the target layer (it follows the window's moves afterwards)
    if Social.follow then Win.Followers.WriteWidth(Social.follow) end
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
    if ns.Raid and ns.Raid.Closed then ns.Raid.Closed() end
end

-- Close this one now; the game's closes its own way (HideUIPanel), deferred until after
-- combat only if the game ever makes its frame protected.
function Social.Close()
    local f = Social.frame
    if not f then return end
    shut(f)
    local g = Social.Game()
    if not (g and g:IsShown()) then return end
    if InCombatLockdown() and g:IsProtected() then
        DUI.AfterCombat(function()
            local now = Social.Game()
            if now and now:IsShown() and not Win.IsOpen(Social.frame) then HideUIPanel(now) end
        end, "social:close")
        return
    end
    HideUIPanel(g)
end

-- Follower callback: the game's frame shown or hidden.
function Social.Changed(_, shown)
    local f = Social.frame
    if not shown then
        if Win.IsOpen(f) then shut(f) end
        return
    end
    Social.Open(Social.AskedTab())
end

function Social.SaveSpot(x, y)
    local db = ns.module and ns.module.db
    if db then db.spot = { DUI.Pixel.Snap(UIParent, x), DUI.Pixel.Snap(UIParent, y) } end
    if ns.Raid and ns.Raid.Moved then ns.Raid.Moved() end
end

-- Lay out the visible page for the grip's size (live while dragging, rows only
-- stretched).
function Social.Resized(_, _, live)
    local f = Social.frame
    if not (f and Win.IsOpen(f)) then return end
    local page = f.pages[f.current]
    if live then
        if page and page.stack then page.stack:Stretch() end
        return
    end
    local P = pageOf(f.current)
    if P and P.Render then P.Render(true) end
end

-- Right-click on the header (or /dui reset): back to the game's spot and size.
function Social.ResetSpot()
    local db = ns.module and ns.module.db
    if not db then return end
    if Social.sizer then Social.sizer.Reset() end
    if not db.spot then return end
    db.spot = nil
    if Social.frame and Win.IsOpen(Social.frame) then place(Social.frame) end
end

function Social.Apply()
    local f = Social.frame
    if not f then return end
    f:SetScale(Win.Scale(ns.Setting("scale")))
    if spot() and Win.IsOpen(f) then place(f) end
    Win.Repaint(f)
    if Win.IsOpen(f) then
        Social.Header()
        local P = pageOf(f.current)
        if P and P.Render then P.Render() end
    end
    if Social.follow then Win.Followers.WriteWidth(Social.follow) end
end

local function width(id) return id == "raid" and Social.RAID_W or Social.W end

function Social.Build(mod)
    ns.module = mod
    if Social.frame then return Social.frame end
    local f = Win.New({ name = Social.NAME, back = "Social", w = Social.W, h = Social.H, portrait = true })
    Social.frame = f
    f.onClose = Social.Close
    Win.SetIcon(f, Social.ICON)
    makeStatus(f)
    for _, id in ipairs(Social.PAGES) do
        local P = pageOf(id)
        Win.AddPage(f, id, { Build = P.Build, Fill = P.Fill, pieces = P.Pieces, w = width(id), h = Social.H })
        Win.Build(f, id)
    end
    Win.Tabs(f, { { id = "friends", text = FRIENDS or L["Friends"] }, { id = "allies", text = L["Recent allies"] },
        { id = "requests", text = L["Requests"] }, { id = "raid", text = RAID or L["Raid"] } },
        function(id) Social.ShowTab(id, true) end)
    f.online:SetPoint("RIGHT", f.tabs[1], "LEFT", -8, 0)   -- stops short of the tabs (long translations get cut instead of overlapping)
    Win.Drag(f, { save = Social.SaveSpot, reset = Social.ResetSpot })
    Win.WheelScale(f, function() return ns.Setting("scale") end, function(v) DUI:Set("Social", "scale", v) end)
    Social.sizer = Win.Resizable(f, { db = function() return ns.module and ns.module.db end,
        base = function(id) return width(id), Social.H end, minH = Social.MIN_H,
        save = Social.SaveSpot, resized = Social.Resized, follow = function() return Social.follow end })
    DUI.Movers.onResetAll[#DUI.Movers.onResetAll + 1] = Social.ResetSpot   -- /dui reset
    for _, e in ipairs({ "BN_INFO_CHANGED", "PLAYER_FLAGS_CHANGED", "BN_CONNECTED", "BN_DISCONNECTED",
        "BN_FRIEND_INVITE_ADDED", "BN_FRIEND_INVITE_REMOVED", "BN_FRIEND_INVITE_LIST_INITIALIZED" }) do
        DUI.RegisterEvent(e, function() Social.Refresh("requests") end)
    end
    Social.follow = Win.Follow({ key = "social", frames = { social = Social.Game }, changed = Social.Changed,
        width = function() return (Social.sizer and Social.sizer.Size(Social.page) or Social.W) * Win.Scale(ns.Setting("scale")) end })
    Social.Apply()
    return f
end
