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
DUI.WithLanguage(function()
    Social.STATUS_WORD = { on = L["Available"], away = L["Away"], busy = L["Busy"], off = L["Offline"],
        hidden = L["Appearing offline"] }
end)
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
    local _, _, tag = ns.Data.Me()
    f.online:SetText("·  " .. string.format(L["%s online"], Win.Parts.Hex({ Style.Pop() }) .. on .. "|r"))
    Social.LayTag(f, tag)
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
    local room = 40 + (f.headerRoom or 0)
    for _, b in ipairs(f.tabs or {}) do room = room + b:GetWidth() + Win.TAB_GAP end
    f.title:SetPoint("RIGHT", f, "RIGHT", -room, 0)
end

-- Your own BattleTag right after your status, on every tab (so: status · BattleTag · friends online), as a
-- link that shows it selected in a box, ready for Ctrl+C (an addon can't call CopyToClipboard: the game
-- blocks it). It sits on the status row under the tabs, each text hung by its top from the one before, so
-- the row stays one line: a text tied by its middle to a tab took the tab's height instead. The row runs
-- under the tabs' row, so only the friends online are cut with "...", at the window's edge. Nothing here
-- measures the window, so the first paint after a /reload is right. Without a BattleTag (not connected)
-- the friends online follow the status.
function Social.LayTag(f, tag)
    f.tag:SetShown(tag ~= nil)
    f.tagDot:SetShown(tag ~= nil)
    local after = f.status.text
    if tag then
        f.tag.SetLabel(tag)
        f.tagDot:ClearAllPoints()
        f.tagDot:SetPoint("TOPLEFT", f.status.text, "TOPRIGHT", 6, 0)
        f.tag.text:ClearAllPoints()
        f.tag.text:SetPoint("TOPLEFT", f.tagDot, "TOPRIGHT", 6, 0)
        -- The link's mouse area is its words.
        f.tag:ClearAllPoints()
        f.tag:SetPoint("LEFT", f.tag.text, "LEFT", 0, 0)
        after = f.tag.text
    end
    f.online:ClearAllPoints()
    f.online:SetPoint("TOPLEFT", after, "TOPRIGHT", 6, 0)
    f.online:SetPoint("RIGHT", f, "RIGHT", -Win.EDGE, 0)
end

function Social.CopyTag()
    local _, _, tag = ns.Data.Me()
    if not tag then return end
    DUI.Widgets.Ask({ key = "battletag", text = L["Your BattleTag. Press Ctrl+C to copy it."], yes = CLOSE or L["Close"], no = false,
        input = { initial = tag, locked = true } })
end

-- Available, Away, Busy, appear offline, broadcast: only from a click (the calls require one).
function Social.StatusMenu(owner)
    local keys = { "on", "away", "busy", "hidden", "broadcast" }
    local values = { on = Social.STATUS_WORD.on, away = Social.STATUS_WORD.away, busy = Social.STATUS_WORD.busy,
        hidden = L["Appear offline"], broadcast = L["Broadcast..."] }
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
    f.status:HookScript("OnEnter", function(self)
        DUI.Widgets.Tooltip(self, L["Change status"], L["Set yourself as Available, Away or Busy for your Battle.net friends, or send them a broadcast."])
    end)
    f.status:HookScript("OnLeave", function() DUI.Widgets.HideTooltip() end)
    f.online = Style.Text(f, Style.SIZE.small, "LEFT")
    f.online:SetPoint("TOPLEFT", f.status.text, "TOPRIGHT", 6, 0)
    f.online:SetWordWrap(false)
    Style.InkText(f.online, "LABEL")
    f.tagDot = Style.Text(f, Style.SIZE.small, "LEFT")
    f.tagDot:SetText("·")
    Style.InkText(f.tagDot, "LABEL")
    f.tagDot:Hide()
    f.tag = DUI.Widgets.Link(f, Style.SIZE.small)
    f.tag.text.english = true   -- a name, not a word
    f.tag.text:SetWordWrap(false)
    f.tag:SetScript("OnClick", function() Social.CopyTag() end)
    f.tag:HookScript("OnEnter", function(self)
        DUI.Widgets.Tooltip(self, L["Copy your BattleTag"], L["Shows your BattleTag selected, to copy it with Ctrl+C and give it to a friend."])
    end)
    f.tag:HookScript("OnLeave", function() DUI.Widgets.HideTooltip() end)
    f.tag:Hide()
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

local function spot() return Social.spot and Social.spot.Get() end

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

-- Which window opens, Daylight UI's or the game's own (Win.Swap): the header's swap
-- icon, a link on the game's window and the options switch all set "enabled".
function Social.Ours() return Social.swap ~= nil and Social.swap.Ours() end

-- Switched to the game's window: an open one shows as itself (this one closes), a
-- closed one is simply let go.
function Social.GiveAway()
    local f, g = Social.frame, Social.Game()
    if f and Win.IsOpen(f) then shut(f) end
    if Social.follow and g then Win.Followers.Release(Social.follow, "social") end
end

-- Switched back: an open game window closes, is parked, and opens again out of
-- sight, so this one shows in its place on the same page. It parks under a hidden
-- frame, so it can't be parked while shown.
function Social.TakeBack()
    local g = Social.Game()
    if not (Social.follow and g and g:IsShown()) or Win.Followers.Parked(Social.follow, "social") then return end
    local ok, tab = pcall(g.GetSelectedTab, g)
    HideUIPanel(g)
    Win.Followers.Tick()
    if not Win.Followers.Parked(Social.follow, "social") then return end
    if ok and Social.GAME_TAB[tab] then Social.page = Social.GAME_TAB[tab] end
    ShowUIPanel(g)
end

-- The game's window sits under this one (or will when it opens), so the Skins
-- leave it alone. Shown on its own, picked by the player, it isn't.
function Social.Covers()
    if not (Social.follow and Social.Ours()) then return false end
    local g = Social.Game()
    return not (g and g:IsShown() and not Win.Followers.Parked(Social.follow, "social"))
end

local function apply(ours)
    if ours and not Social.frame then Social.Build(ns.module) end
    if ours then Social.TakeBack() else Social.GiveAway() end
end

-- Made before the window is built: it's only built while it's the pick.
function Social.SwapInit()
    Social.swap = Win.Swap({ scope = "Social", game = Social.Game, addon = "Blizzard_SocialUI", apply = apply })
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
    if Social.spot then Social.spot.Save(x, y) end
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
    if not (ns.module and ns.module.db) then return end
    if Social.sizer then Social.sizer.Reset() end
    if Social.spot then Social.spot.Reset() end
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

-- Friends and Recent allies grow by the detail card's room while a row is picked.
Social.side = {}
local function width(id)
    return (id == "raid" and Social.RAID_W or Social.W) + (Social.side[id] and ns.Detail.SPAN or 0)
end

-- The detail card of a page opened or closed: the window makes room on its right (or
-- gives it back), easing like a change of page. Pages lay out for the width they are
-- going to have (goalW), as when a tab changes.
function Social.SetSide(id, on)
    on = on == true
    if (Social.side[id] == true) == on then return end
    Social.side[id] = on or nil
    local f = Social.frame
    if not f then return end
    local def = f.defs and f.defs[id]
    if def then def.w = width(id) end
    -- The controller finds a window's search box and main button when the page changes or
    -- the window gets the focus, and hidden pieces aren't found: the card has just shown,
    -- so look again (X presses its Invite).
    if on and DUI.Pad and DUI.Pad.Scrolls then DUI.Pad.Scrolls(f) end
    if f.current ~= id then return end
    local w, h = Social.sizer.Size(id)
    f.goalW, f.goalH = w, h
    if Win.IsOpen(f) then Win.Feel.Size(f, w, h) else f:SetSize(w, h) end
    if Win.Room then Win.Room.Changed(f) end
    if Social.follow then Win.Followers.WriteWidth(Social.follow) end
end

function Social.Build(mod)
    ns.module = mod
    if Social.frame then return Social.frame end
    local f = Win.New({ name = Social.NAME, escape = false, back = "Social", w = Social.W, h = Social.H, portrait = true })
    Social.frame = f
    f.onClose = Social.Close
    Social.spot = Win.Spot(f, function() return ns.module and ns.module.db end, place)
    Win.SetIcon(f, Social.ICON)
    makeStatus(f)
    for _, id in ipairs(Social.PAGES) do
        local P = pageOf(id)
        Win.AddPage(f, id, { Build = P.Build, Fill = P.Fill, pieces = P.Pieces, w = width(id), h = Social.H })
        Win.Build(f, id)
    end
    if Social.swap then Social.swap.Icon(f) end   -- left of the X: the game's own window instead
    Win.Tabs(f, { { id = "friends", text = FRIENDS or L["Friends"] }, { id = "allies", text = L["Recent allies"] },
        { id = "requests", text = L["Requests"] }, { id = "raid", text = RAID or L["Raid"] } },
        function(id) Social.ShowTab(id, true) end)
    Social.LayTag(f, (select(3, ns.Data.Me())))
    -- Controller: the game's friends list has no buttons of its own, so this one
    -- follows its Communities window. Y is a row's menu and X the footer's main
    -- button (every window's); A on a raid member targets them.
    f.padKeys = { { key = "A", label = TARGET or L["Target"], secure = function(b) return ns.Raid.PadTarget(b) end } }
    Win.Drag(f, { save = Social.SaveSpot, reset = Social.ResetSpot })
    Win.WheelScale(f, function() return ns.Setting("scale") end, function(v) DUI:Set("Social", "scale", v) end)
    Social.sizer = Win.Resizable(f, { db = function() return ns.module and ns.module.db end,
        base = function(id) return width(id), Social.H end, minH = Social.MIN_H,
        extra = function(id) return Social.side[id] and ns.Detail.SPAN or 0 end,   -- the card's room isn't part of the size kept
        save = Social.SaveSpot, resized = Social.Resized, follow = function() return Social.follow end })
    DUI.Movers.onResetAll[#DUI.Movers.onResetAll + 1] = Social.ResetSpot   -- /dui reset
    for _, e in ipairs({ "BN_INFO_CHANGED", "PLAYER_FLAGS_CHANGED", "BN_CONNECTED", "BN_DISCONNECTED",
        "BN_FRIEND_INVITE_ADDED", "BN_FRIEND_INVITE_REMOVED", "BN_FRIEND_INVITE_LIST_INITIALIZED" }) do
        DUI.RegisterEvent(e, function() Social.Refresh("requests") end)
    end
    Social.follow = Win.Follow({ key = "social", frames = { social = Social.Game }, changed = Social.Changed,
        leave = function() return not Social.Ours() end,
        width = function() return (Social.sizer and Social.sizer.Size(Social.page) or Social.W) * Win.Scale(ns.Setting("scale")) end })
    Social.Apply()
    return f
end
