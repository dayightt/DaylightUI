-- Mailbox window with three tabs: Inbox, Send and Ledger.
-- The game still runs the mailbox: right-clicking one shows MailFrame (MailFrame_Show,
-- from the player interaction), which is parked under the kit's veil (Win.Follow;
-- OpenMailFrame under its hidden frame). This window shows in its place and closes with it.
--
-- CloseMail: MailFrame tells the client the mailbox closed from its OnHide, which still
-- runs under the veil. This window never says it on the game's behalf, so an addon that
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
Mail.SEND_W = 460            -- the Send page is a narrow form; the window glides to this width
Mail.MIN_H = 420
Mail.ICON = "Interface\\Icons\\INV_Letter_15"
Mail.PAGES = { "inbox", "send", "ledger" }

Mail.page = "inbox"   -- every mailbox visit opens on the inbox, like the game
Mail.replyTo = nil    -- { name, subject, id = Inbox.Id }: the inbox's Reply, for the Send page

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

local function spot()
    local s = ns.module and ns.module.db and ns.module.db.spot
    if type(s) == "table" and type(s[1]) == "number" and type(s[2]) == "number" then return s end
    return nil
end

local function place(f)
    local s = spot()
    if s then return Win.PlaceTop(f, s[1], s[2]) end
    f:ClearAllPoints()
    local g = Mail.Game()
    if g then f:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
    else f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116) end
end

function Mail.Open()
    local f = Mail.frame
    if not f then return end
    Mail.Header()
    if Win.IsOpen(f) then return end
    place(f)
    Mail.ShowTab("inbox")
    Win.Open(f)
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

-- Follower callback: the game's frame shown or hidden. Its letter frame stays parked,
-- since letters show on the inbox page here.
function Mail.Changed(kind, shown)
    if kind ~= "mail" then return end
    local f = Mail.frame
    if shown then return Mail.Open() end
    if Win.IsOpen(f) then shut(f) end
end

function Mail.SaveSpot(x, y)
    local db = ns.module and ns.module.db
    if db then db.spot = { DUI.Pixel.Snap(UIParent, x), DUI.Pixel.Snap(UIParent, y) } end
end

-- Right-click on the header (or /dui reset): back to the game's spot and size.
function Mail.ResetSpot()
    local db = ns.module and ns.module.db
    if not db then return end
    if Mail.sizer then Mail.sizer.Reset() end
    if not db.spot then return end
    db.spot = nil
    if Mail.frame and Win.IsOpen(Mail.frame) then place(Mail.frame) end
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

function Mail.Build(mod)
    ns.module = mod
    if Mail.frame then return Mail.frame end
    local f = Win.New({ name = Mail.NAME, back = "Mailbox", w = Mail.W, h = Mail.H, portrait = true })
    Mail.frame = f
    f.onClose = Mail.Close
    Win.SetIcon(f, Mail.ICON)
    Win.AddPage(f, "inbox", page("inbox", Mail.W))
    Win.AddPage(f, "send", page("send", Mail.SEND_W))
    Win.AddPage(f, "ledger", page("ledger", Mail.W))
    for _, id in ipairs(Mail.PAGES) do Win.Build(f, id) end
    Win.Tabs(f, { { id = "inbox", text = INBOX or L["Inbox"] }, { id = "send", text = L["Send"] },
        { id = "ledger", text = L["Ledger"] } }, function(id) Mail.ShowTab(id) end)
    -- Controller, matching the game's mail buttons (MailFrame.lua footers): X opens all,
    -- replies to the open letter, or sends; Y opens the letter's options.
    local function picked() return f.current == "inbox" and ns.Inbox.Picked() or nil end
    f.padKeys = {
        { key = "X", label = REPLY_MESSAGE or L["Reply"], run = function() ns.Inbox.Reply() end,
          when = function() local l = picked(); return l ~= nil and l.canReply end },
        { key = "X", label = OPEN_ALL_MAIL_BUTTON or L["Collect all"], run = function() ns.Inbox.Collect() end,
          when = function() return f.current == "inbox" and picked() == nil end },
        { key = "X", label = SEND_LABEL or L["Send"], run = function() ns.Send.Send() end,
          when = function() return f.current == "send" end },
        { key = "Y", label = CONTEXT_ACTION_LABEL_OPTIONS or L["Options"], run = function(b) ns.Inbox.Options(b or f) end,
          when = function() return picked() ~= nil end },
    }
    Win.Drag(f, { save = Mail.SaveSpot, reset = Mail.ResetSpot })
    Win.WheelScale(f, function() return ns.Setting("scale") end, function(v) DUI:Set("Mailbox", "scale", v) end)
    Mail.sizer = Win.Resizable(f, { db = function() return ns.module and ns.module.db end,
        base = function(id) return id == "send" and Mail.SEND_W or Mail.W, Mail.H end, minH = Mail.MIN_H,
        save = Mail.SaveSpot, follow = function() return Mail.follow end })
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
    Mail.follow = Win.Follow({ key = "mail", frames = { mail = Mail.Game, letter = Mail.Letter }, veil = { mail = true }, changed = Mail.Changed,
        width = function() return (Mail.sizer and Mail.sizer.Size(Mail.page) or Mail.W) * Win.Scale(ns.Setting("scale")) end })
    Mail.Apply()
    return f
end
