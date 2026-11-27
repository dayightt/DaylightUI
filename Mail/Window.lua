-- Mailbox window with three tabs: Inbox, Send and Ledger.
-- The game still runs the mailbox: right-clicking one shows MailFrame (MailFrame_Show,
-- from the player interaction), which the kit holds aside (Win.Follow;
-- OpenMailFrame under its hidden frame). This window shows in its place and closes with it.
--
-- CloseMail: MailFrame tells the client the mailbox closed from its OnHide, which still
-- runs while held aside. This window never says it on the game's behalf, so an addon that
-- hooks MailFrame's OnHide and hides it (TradeSkillMaster's mailing window) keeps the
-- mailbox open.

local _, DUI = ...
DUI.Mail = DUI.Mail or {}
local ns = DUI.Mail
local L = DUI.L
local Win = DUI.Win
local Style = DUI.Style

local Mail = {}
ns.Window = Mail

Mail.NAME = "DaylightUIMail"
Mail.W, Mail.H = 640, 560
Mail.LEDGER_W = 680          -- the ledger's left column is 340 wide, which leaves the lists the room they had
Mail.SEND_W = 460            -- the Send page is a narrow form; the window glides to this width
Mail.MIN_H = 420
Mail.ICON = "Interface\\Icons\\INV_Letter_15"
Mail.PAGES = { "inbox", "send", "ledger" }

Mail.page = "inbox"   -- every mailbox visit opens on the inbox, like the game
Mail.replyTo = nil    -- { name, subject, id = Inbox.Id }: the inbox's Reply, for the Send page

-- The game's own word for something, by its global name (the mailbox says "Send Mail",
-- "Subject:", "Cash on Delivery"), so the window speaks like the game in every language.
-- The game's labels end in a colon, which no label here wants (every row list in Daylight UI
-- has none), so it is cut. fallback is ours, for a client that lacks the global.
function ns.Game(key, fallback)
    local s = _G[key]
    if type(s) ~= "string" or s == "" then return fallback end
    s = s:gsub("%s*[:：]%s*$", "")
    return s
end

function ns.Setting(key) return ns.module and ns.module.db and ns.module.db[key] end

function Mail.Game()
    local g = _G.MailFrame
    return type(g) == "table" and g or nil
end
function Mail.Letter()
    local g = _G.OpenMailFrame
    return type(g) == "table" and g or nil
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h end
end

-- Header: title, letter count and gold waiting

-- Letters in the inbox and the gold in them.
function Mail.Waiting()
    local n = call(GetInboxNumItems)
    n = type(n) == "number" and n or 0
    local gold = 0
    for i = 1, n do
        local m = select(5, call(GetInboxHeaderInfo, i))
        if type(m) == "number" then gold = gold + m end
    end
    return n, gold
end

function Mail.Header()
    local f = Mail.frame
    if not f then return end
    local n, gold = Mail.Waiting()
    local pop = Win.Parts.Hex({ Style.Pop() }) .. n .. "|r"
    local sub
    if n == 0 then
        sub = L["No letters"]
    elseif gold > 0 then
        sub = string.format(n == 1 and L["%s letter, %s to collect"] or L["%s letters, %s to collect"], pop, DUI.MoneyString(gold))
    else
        sub = string.format(n == 1 and L["%s letter"] or L["%s letters"], pop)
    end
    Win.SetTitle(f, MAIL_LABEL or L["Mailbox"], nil, sub)
end

function Mail.ShowTab(id)
    local f = Mail.frame
    if not f then return end
    Mail.page = id
    Win.PickTab(f, id)
    Win.ShowPage(f, id)
end

-- Open, close, follow the game's frame

local function spot() return Mail.spot and Mail.spot.Get() end

local function place(f)
    local s = spot()
    if s then return Win.PlaceTop(f, s[1], s[2]) end
    f:ClearAllPoints()
    local g = Mail.Game()
    if not (g and Win.Followers.PlaceOn(f, g)) then f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116) end
end

function Mail.Open()
    local f = Mail.frame
    if not f then return end
    Mail.Header()
    if Win.IsOpen(f) then return end
    place(f)
    Mail.ShowTab("inbox")
    Win.Open(f)
    Win.KeysOn(f, true)
    if Mail.follow then Win.Followers.WriteWidth(Mail.follow) end
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
    Win.KeysOn(f, false)
    if Win.IsOpen(f) then Win.Close(f) end
end

-- Close this one now; the game's closes its own way (HideUIPanel; MailFrame_Hide
-- belongs to the interaction and runs when the client closes it).
function Mail.Close()
    local f = Mail.frame
    if not f then return end
    shut(f)
    local g = Mail.Game()
    if g and g:IsShown() then HideUIPanel(g) end
end

-- Which mailbox opens, Daylight UI's or the game's own (Win.Swap): the header's
-- swap icon, a link on the game's window, the options switch.

-- Picked the game's: an open mailbox is handed over as it is (this one closes as
-- the follower sees it go), a closed one simply let go so it opens as itself.
function Mail.GiveAway()
    local def = Mail.follow
    if not def then return end
    if InCombatLockdown() then return DUI.AfterCombat(Mail.GiveAway, "mail:giveaway") end
    Win.Followers.Release(def, "mail")
    Win.Followers.Release(def, "letter")
end

-- Picked this one: an open game mailbox is held aside again and the
-- follower's next look opens this window in its place. An open letter closes,
-- since letters show on the inbox page here.
function Mail.TakeBack()
    local def = Mail.follow
    if not (def and DUI.mailOwnWindow) then return end
    if InCombatLockdown() then return DUI.AfterCombat(Mail.TakeBack, "mail:takeback") end
    local l = Mail.Letter()
    if l and l:IsShown() and not Win.Followers.Parked(def, "letter") then HideUIPanel(l) end
    local g = Mail.Game()
    if g and g:IsShown() and not Win.Followers.Parked(def, "mail") then Win.Followers.Reclaim(def, "mail") end
end

-- The game's frame (MailFrame, or "letter" for OpenMailFrame) sits under this
-- window, or will when it opens, so the Skins leave it alone.
function Mail.Covers(kind)
    if not (Mail.follow and DUI.mailOwnWindow) then return false end
    kind = kind == "letter" and "letter" or "mail"
    local g = kind == "letter" and Mail.Letter() or Mail.Game()
    return not (g and g:IsShown() and not Win.Followers.Parked(Mail.follow, kind))
end

function Mail.Pick(ours)
    DUI.mailOwnWindow = ours
    if ours and not Mail.frame then Mail.Build(ns.module) end
    if not Mail.follow then return end
    if ours then Mail.TakeBack() else Mail.GiveAway() end
end

-- Made before the window, which is only built while it's the pick.
function Mail.InitSwap()
    if Mail.swap then return end
    Mail.swap = Win.Swap({
        scope = "Mailbox",
        game = Mail.Game,
        blocked = function() return DUI.mailMogul == true end,
        apply = Mail.Pick,
    })
end

-- Follower callback: the game's frame shown or hidden. Its letter frame stays parked,
-- since letters show on the inbox page here.
function Mail.Changed(kind, shown)
    if kind ~= "mail" then return end
    local f = Mail.frame
    if shown and not DUI.mailOwnWindow then return Mail.GiveAway() end
    if shown then return Mail.Open() end
    if Win.IsOpen(f) then shut(f) end
end

function Mail.SaveSpot(x, y)
    if Mail.spot then Mail.spot.Save(x, y) end
end

-- Right-click on the header (or /dui reset): back to the game's spot and size.
function Mail.ResetSpot()
    if not (ns.module and ns.module.db) then return end
    if Mail.sizer then Mail.sizer.Reset() end
    if Mail.spot then Mail.spot.Reset() end
end

function Mail.Apply()
    local f = Mail.frame
    if not f then return end
    f:SetScale(Win.Scale(ns.Setting("scale")))
    if spot() and Win.IsOpen(f) then place(f) end
    Win.Repaint(f)
    if Win.IsOpen(f) then
        Mail.Header()
        if ns.Inbox and ns.Inbox.list then ns.Inbox.Render() end
    end
    if Mail.follow then Win.Followers.WriteWidth(Mail.follow) end
end

-- Each page's own file fills it; a missing one stays empty.
local function page(id, w)
    local P = ns[id == "inbox" and "Inbox" or id == "send" and "Send" or "LedgerPage"]
    return { Build = P and P.Build or function() end, Fill = P and P.Fill, pieces = P and P.Pieces, w = w, h = Mail.H }
end

-- Resizing: while the grip drags (live) the rows only stretch to the new width; when it
-- lets go the page fills again, so text wraps to what it now has.
function Mail.Resized(_, _, live)
    local f = Mail.frame
    if not (f and Win.IsOpen(f)) then return end
    if f.current == "inbox" then
        local I = ns.Inbox
        if live then
            if I.list and I.list.stack then I.list.stack:Stretch() end
            if I.letter and I.letter.stack then I.letter.stack:Stretch() end
        else
            I.Render()
        end
    elseif f.current == "ledger" then
        local P = ns.LedgerPage
        if live then
            if P.page and P.page.right then P.page.right.stack:Stretch() end
        else
            P.Render()
        end
    end
end

function Mail.Build(mod)
    ns.module = mod
    if Mail.frame then return Mail.frame end
    local f = Win.New({ name = Mail.NAME, escape = false, back = "Mailbox", w = Mail.W, h = Mail.H, portrait = true })
    Mail.frame = f
    f.onClose = Mail.Close
    Mail.spot = Win.Spot(f, function() return ns.module and ns.module.db end, place)
    Win.SetIcon(f, Mail.ICON)
    Win.AddPage(f, "inbox", page("inbox", Mail.W))
    Win.AddPage(f, "send", page("send", Mail.SEND_W))
    Win.AddPage(f, "ledger", page("ledger", Mail.LEDGER_W))
    for _, id in ipairs(Mail.PAGES) do Win.Build(f, id) end
    -- Left of the X, before the tabs line up from it: the game's own mailbox instead,
    -- for addons that build on it.
    if Mail.swap then Mail.swap.Icon(f) end
    Win.Tabs(f, { { id = "inbox", text = INBOX or L["Inbox"] }, { id = "send", text = ns.Game("SENDMAIL", L["Send"]) },
        { id = "ledger", text = L["Ledger"] } }, function(id) Mail.ShowTab(id) end)
    -- Controller, matching the game's mail buttons (MailFrame.lua footers): X opens all,
    -- replies to the open letter, or sends; Y opens the letter's options.
    local function picked() return f.current == "inbox" and ns.Inbox.Picked() or nil end
    f.padKeys = {
        { key = "X", label = REPLY_MESSAGE or L["Reply"], run = function() ns.Inbox.Reply() end,
          when = function() local l = picked(); return l ~= nil and l.canReply end },
        { key = "X", label = ns.Game("OPEN_ALL_MAIL_BUTTON", L["Collect all"]), run = function() ns.Inbox.Collect() end,
          when = function() return f.current == "inbox" and picked() == nil end },
        { key = "X", label = SEND_LABEL or L["Send"], run = function() ns.Send.Send() end,
          when = function() return f.current == "send" end },
        { key = "Y", label = CONTEXT_ACTION_LABEL_OPTIONS or L["Options"], run = function(b) ns.Inbox.Options(b or f) end,
          when = function() return picked() ~= nil end },
    }
    Win.Keys(f, function(key) return ns.Inbox.OnKey(key) end)
    Win.Drag(f, { save = Mail.SaveSpot, reset = Mail.ResetSpot })
    Win.WheelScale(f, function() return ns.Setting("scale") end, function(v) DUI:Set("Mailbox", "scale", v) end)
    Mail.sizer = Win.Resizable(f, { db = function() return ns.module and ns.module.db end,
        base = function(id) return id == "send" and Mail.SEND_W or id == "ledger" and Mail.LEDGER_W or Mail.W, Mail.H end,
        minH = Mail.MIN_H, resized = Mail.Resized, save = Mail.SaveSpot, follow = function() return Mail.follow end })
    DUI.Movers.onResetAll[#DUI.Movers.onResetAll + 1] = Mail.ResetSpot   -- /dui reset
    -- Inbox updates come in bursts: count for the header once, next frame.
    DUI.RegisterEvent("MAIL_INBOX_UPDATE", function()
        if Mail.headerSoon then return end
        Mail.headerSoon = true
        C_Timer.After(0, function()
            Mail.headerSoon = nil
            Mail.Header()
        end)
    end)
    Mail.follow = Win.Follow({ key = "mail", frames = { mail = Mail.Game, letter = Mail.Letter }, aside = { mail = true }, changed = Mail.Changed,
        leave = function() return not DUI.mailOwnWindow end,
        width = function() return (Mail.sizer and Mail.sizer.Size(Mail.page) or Mail.W) * Win.Scale(ns.Setting("scale")) end })
    Mail.Apply()
    return f
end
