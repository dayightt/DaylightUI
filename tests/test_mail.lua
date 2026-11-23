local stub = require("stub")
local MW = require("mailworld")
local function DUI_money(c) return DaylightUI.MoneyString(math.abs(c)) end

-- The mailbox window follows the game's MailFrame. Closing it calls CloseMail
-- so the client knows the mailbox is shut and the next one still opens.

local LETTERS = {
    { sender = "Alliance Auction House", subject = "Auction successful: Heavy Leather (20)", money = 48500,
      invoice = { type = "seller", item = "Heavy Leather", player = "Ysella Brightwind", bid = 51000, deposit = 50, cut = 2550, count = 20 } },
    { sender = "Brannoc Ironhide", subject = "Ore money", money = 15000 },
    { sender = "Thaxton Ashby", subject = "Hello" },
}

local function load(spec)
    spec = spec or {}
    spec.letters = spec.letters or LETTERS
    if spec.enabled == false then
        spec.db = { profileData = { ["DPS/Tank"] = { modules = { Mailbox = { enabled = false } } } } }
    end
    stub.Load({ before = MW.world(spec) })
    return stub.mail
end

local function frame(n)
    for _ = 1, n or 1 do
        stub.RunTimers()
        DaylightUI.Win.Followers.Tick()
        local d = DaylightUI.Win.Feel.Driver()
        if d then stub.RunOnUpdate(d, 1 / 30) end
        local m = DaylightUI.Motion.Driver()
        if m then stub.RunOnUpdate(m, 1 / 30) end
    end
end

-- Other addons meet the mailbox at the game's own window. TradeSkillMaster
-- (Core/UI/MailingUI/Core.lua) puts its own OnHide on MailFrame, hides it and
-- opens its window; the mailbox stays open because the game's OnHide is gone.

T.test("mail: the game's mailbox really opens, so an addon hooking its OnShow hears it", function()
    load()
    local heard = 0
    MailFrame:HookScript("OnShow", function() heard = heard + 1 end)
    T.eq(MailFrame:GetParent(), DaylightUI.Win.Followers.aside)
    MW.Open()
    frame(2)
    T.eq(heard, 1)
end)

T.test("mail: an addon hiding the game's mailbox with its own OnHide keeps the mailbox open", function()
    local ns = load()
    MW.Open()
    frame(2)
    MailFrame:SetScript("OnHide", function() end)
    HideUIPanel(MailFrame)
    frame(40)
    T.eq(ns.Window.frame:IsShown(), false, "ours stepped aside")
    T.eq(#MW.Calls("CloseMail"), 0, "the other addon's window still has the mailbox")
    T.eq(MW.IsOpen(), true)
end)

T.test("mail: the game's own OnHide still tells the client once ours closes", function()
    local ns = load()
    MW.Open()
    frame(2)
    ns.Window.Close()
    frame(40)
    T.falsy(MW.IsOpen())
    T.eq(MailFrame:IsShown(), false)
end)

T.test("mail: an addon sending the game's mailbox off screen gets it to itself, the mailbox stays open", function()
    local ns = load()
    MW.Open()
    frame(2)
    T.eq(ns.Window.frame:IsShown(), true)
    MailFrame:ClearAllPoints()
    MailFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100000, 100000)
    frame(40)
    T.eq(ns.Window.frame:IsShown(), false, "ours stepped aside")
    T.eq(#MW.Calls("CloseMail"), 0)
    T.eq(MailFrame:IsShown(), true)
end)

T.test("mail: a mailbox opens ours in place of the game's, on the inbox, with the letters and gold waiting", function()
    local ns = load()
    T.truthy(DaylightUI.mailOwnWindow)
    MW.Open()
    frame(20)
    local f = ns.Window.frame
    T.truthy(DaylightUI.Win.IsOpen(f), "ours is open")
    T.eq(MailFrame:GetParent(), DaylightUI.Win.Followers.aside, "the game's is held aside, out of sight")
    T.isnil(stub.ClipAncestor(MailFrame), "never under a clipping frame")
    T.eq(MailFrame:IsVisible(), true)
    frame(40)
    local p, rel, _, x, y = f:GetPoint(1)
    T.eq(p, "TOPLEFT"); T.eq(rel, UIParent); T.eq(x, 16 / f:GetScale()); T.eq(y, -116 / f:GetScale())
    T.eq(f.current, "inbox")
    local sub = stub.Text(f.sub)
    T.truthy(sub:find("3", 1, true) and sub:find("letters", 1, true), sub)
    T.truthy(sub:find("6", 1, true), "the gold to collect: " .. sub)
end)

T.test("mail: closing ours tells the client, so the next mailbox clicks", function()
    local ns = load()
    MW.Open()
    frame(20)
    ns.Window.Close()
    frame(20)
    T.falsy(DaylightUI.Win.IsOpen(ns.Window.frame))
    T.falsy(MW.IsOpen(), "CloseMail was said")
    T.truthy(MW.Open(), "a mailbox clicks again")
    frame(20)
    T.truthy(DaylightUI.Win.IsOpen(ns.Window.frame), "and ours opens again")
end)

T.test("mail: walking away closes ours", function()
    local ns = load()
    MW.Open()
    frame(20)
    MW.Leave()
    frame(20)
    T.falsy(DaylightUI.Win.IsOpen(ns.Window.frame))
    T.truthy(MW.Open())
end)

T.test("mail: the tabs show their pages; Send is narrower", function()
    local ns = load()
    MW.Open()
    frame(20)
    local f = ns.Window.frame
    ns.Window.ShowTab("send")
    frame(20)
    T.eq(f.current, "send")
    T.near(f:GetWidth(), ns.Window.SEND_W, 1)
    ns.Window.ShowTab("ledger")
    frame(20)
    T.near(f:GetWidth(), ns.Window.LEDGER_W, 1)
end)

T.test("mail: switched off, the game's mailbox is the game's and the ledger still counts", function()
    local ns = load({ enabled = false, money = 0 })
    T.falsy(DaylightUI.mailOwnWindow)
    T.isnil(ns.Window.frame)
    MW.Open()
    T.truthy(MailFrame:IsVisible(), "the game's own window")
    TakeInboxMoney(2)
    MW.Settle()
    T.eq(ns.Ledger.Range("session").kinds.players, 15000)
end)

T.test("mail: the header's swap button hands over to the game's mailbox and it stays picked", function()
    local ns = load()
    MW.Open()
    frame(20)
    local f = ns.Window.frame
    T.truthy(DaylightUI.Win.IsOpen(f))
    T.truthy(f.swap and f.swap:IsShown(), "the swap button sits in the header")
    f.swap:Click()
    frame(10)
    T.eq(DaylightUI:Get("Mailbox", "enabled"), false, "the pick is saved")
    T.eq(DaylightUI.mailOwnWindow, false)
    T.falsy(DaylightUI.Win.IsOpen(f), "ours steps aside")
    T.eq(MailFrame:GetParent(), UIParent, "the game's mailbox is back")
    T.truthy(MailFrame:IsVisible(), "and shows")
    T.truthy(MW.IsOpen(), "the same mailbox visit goes on")
    T.truthy(ns.Window.swap.link:IsShown(), "with its way back")
    T.falsy(ns.Window.Covers(), "the skins may dress it")
    MW.Leave()
    frame(10)
    T.eq(MailFrame:GetParent(), UIParent, "never parked while it's the pick")
    T.eq(OpenMailFrame:GetParent(), UIParent, "nor the letter")
    T.truthy(MW.Open())
    frame(20)
    T.falsy(DaylightUI.Win.IsOpen(f), "the next mailbox opens in the game's window")
    T.truthy(MailFrame:IsVisible())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("mail: the game's mailbox's button switches back to Daylight UI's, no reload", function()
    local ns = load({ enabled = false })
    MW.Open()
    frame(5)
    T.isnil(ns.Window.frame, "nothing built while the game's is picked")
    OpenMailFrame:Show()
    local b = ns.Window.swap.link
    T.truthy(b and b:IsShown(), "the game's mailbox has the switch")
    T.eq(b:GetParent(), MailFrame, "it rides on the game's window")
    b:Click()
    frame(20)
    T.eq(DaylightUI:Get("Mailbox", "enabled"), true, "the pick is saved")
    local f = ns.Window.frame
    T.truthy(f and DaylightUI.Win.IsOpen(f), "ours takes over the open mailbox")
    T.eq(f.current, "inbox")
    T.eq(MailFrame:GetParent(), DaylightUI.Win.Followers.aside, "the game's frame is held aside")
    T.falsy(OpenMailFrame:IsShown(), "the open letter closes: letters show on the inbox page")
    T.eq(OpenMailFrame:GetParent(), DaylightUI.Win.Followers.hidden)
    T.truthy(MW.IsOpen(), "the same mailbox visit goes on")
    T.falsy(b:IsShown(), "the button is gone with the game's look")
    T.truthy(ns.Window.Covers())
    T.truthy(ns.Window.Covers("letter"))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("mail: a new letter while open updates the header", function()
    local ns = load()
    MW.Open()
    frame(20)
    MW.Arrive({ sender = "Mira Dawnsong", subject = "Thanks", money = 700 })
    MW.Deliver()
    frame(2)
    T.truthy(stub.Text(ns.Window.frame.sub):find("4", 1, true))
end)

-- ---------------------------------------------------------------------
-- The Inbox page
-- ---------------------------------------------------------------------

local function lines(ns)
    local out = {}
    for _, b in ipairs(ns.Inbox.list.stack.used) do
        if b:IsShown() and b.lineSpec then out[#out + 1] = b end
    end
    return out
end

local function button(ns, label)
    for _, foot in ipairs({ ns.Inbox.list.foot, ns.Inbox.letter.foot }) do
        for _, b in ipairs(foot.buttons) do
            if b:IsShown() and stub.Text(b.text):find(label, 1, true) then return b end
        end
    end
end
local function press(ns, label)
    local b = button(ns, label)
    assert(b, "no footer button " .. label)
    if not b.spec.off then b.spec.onClick(b) end
end
local function settle()
    for _ = 1, 30 do
        MW.Settle()
        frame(2)
        if MW.Waiting() == 0 then frame(2); if MW.Waiting() == 0 then return end end
    end
end

T.test("inbox: every letter a line: subject, who, the gold, a COD, the items, and the days under it", function()
    local ns = load({ letters = {
        LETTERS[1], LETTERS[2],
        { sender = "Ysella Brightwind", subject = "Runecloth", cod = 60000, days = 2, items = { { name = "Runecloth", itemID = 14047, count = 20 } } },
    } })
    MW.Open()
    frame(20)
    local ls = lines(ns)
    T.eq(#ls, 3)
    T.eq(stub.Text(ls[1].name), "Heavy Leather (20)", "the item, without the subject every house letter shares")
    T.eq(stub.Text(ls[1].sub), "Sold", "what happened to it instead of the house's name")
    T.eq(stub.Text(ls[2].sub), "Brannoc Ironhide")
    T.eq(stub.Text(ls[3].value), "COD")
    T.eq(stub.Text(ls[3].subValue), "2 days", "days left under the value, never cut off by the sender")
    T.truthy(ls[3].subValue:IsShown())
end)

T.test("inbox: the house's letters show the item and what happened to it", function()
    local ns = load({ letters = {
        { sender = "Horde Auction House", canReply = false, subject = "Auction expired: Dervish Belt of the Eagle", items = { { name = "Dervish Belt of the Eagle", itemID = 10032 } } },
        { sender = "Horde Auction House", canReply = false, subject = "Auction won: Pincer Bite", items = { { name = "Pincer Bite", itemID = 15409 } } },
        { sender = "Horde Auction House", canReply = false, subject = "Auction canceled: Linen Cloth (5)", items = { { name = "Linen Cloth", itemID = 2589, count = 5 } } },
        { sender = "Ysella Brightwind", subject = "Auction successful: my old boots" },
    } })
    MW.Open()
    frame(20)
    local ls = lines(ns)
    T.eq(stub.Text(ls[1].name), "Dervish Belt of the Eagle"); T.eq(stub.Text(ls[1].sub), "Expired")
    T.eq(stub.Text(ls[2].name), "Pincer Bite"); T.eq(stub.Text(ls[2].sub), "Won")
    T.eq(stub.Text(ls[3].name), "Linen Cloth (5)"); T.eq(stub.Text(ls[3].sub), "Canceled")
    T.eq(stub.Text(ls[4].name), "Auction successful: my old boots", "a player's letter keeps its subject")
    T.eq(stub.Text(ls[4].sub), "Ysella Brightwind")
    T.eq(ns.Inbox.AuctionSubject("Auction successful: Strange Dust"), "Strange Dust")
    T.eq(ns.Inbox.AuctionSubject("Hello"), nil)
end)

-- koKR gives sold and won the same subject: the invoice tells them apart.
T.test("inbox: a language with one subject for sold and won goes by the invoice", function()
    local sold, won = _G.AUCTION_SOLD_MAIL_SUBJECT, _G.AUCTION_WON_MAIL_SUBJECT
    _G.AUCTION_SOLD_MAIL_SUBJECT, _G.AUCTION_WON_MAIL_SUBJECT = "Auction closed: %s", "Auction closed: %s"
    local ok, err = pcall(function()
        local ns = load({ letters = {
            { sender = "Horde Auction House", subject = "Auction closed: Pincer Bite", items = { { name = "Pincer Bite", itemID = 15409 } },
              invoice = { type = "buyer", item = "Pincer Bite", player = "Ysella Brightwind", bid = 3000, count = 1 } },
            { sender = "Horde Auction House", subject = "Auction closed: Strange Dust", money = 2500,
              invoice = { type = "seller", item = "Strange Dust", player = "Brannoc Ironhide", bid = 2600, deposit = 10, cut = 110, count = 1 } },
        } })
        MW.Open()
        frame(20)
        local ls = lines(ns)
        T.eq(stub.Text(ls[1].name), "Pincer Bite"); T.eq(stub.Text(ls[1].sub), "Won")
        T.eq(stub.Text(ls[2].name), "Strange Dust"); T.eq(stub.Text(ls[2].sub), "Sold")
    end)
    _G.AUCTION_SOLD_MAIL_SUBJECT, _G.AUCTION_WON_MAIL_SUBJECT = sold, won
    if not ok then error(err, 0) end
end)

T.test("inbox: search and the chips narrow the list; an empty one says so", function()
    local ns = load()
    MW.Open()
    frame(20)
    ns.Inbox.Search("brannoc")
    T.eq(#lines(ns), 1)
    ns.Inbox.Search("")
    ns.Inbox.Filter("gold")
    T.eq(#lines(ns), 2, "the two letters with gold")
    ns.Inbox.Filter("players")
    T.eq(#lines(ns), 2, "the two you can answer")
    ns.Inbox.Search("nobody")
    T.eq(#lines(ns), 0)
    T.truthy(ns.Inbox.list.note:IsShown())
    T.eq(stub.Text(ns.Inbox.list.note), "No letters match.")
end)

T.test("inbox: a sale letter picked reads as a receipt; Take takes its gold", function()
    local ns = load({ money = 0 })
    MW.Open()
    frame(20)
    lines(ns)[1].lineSpec.onClick()
    frame(5)
    local text = {}
    for _, b in ipairs(ns.Inbox.letter.stack.used) do if b:IsShown() and b.text and not b.lineSpec then text[#text + 1] = stub.Text(b.text) end end
    local all = table.concat(text, "\n")
    T.truthy(all:find("Sold for", 1, true) and all:find("You keep", 1, true), all)
    T.truthy(all:find("Bought by", 1, true) and all:find("Ysella Brightwind", 1, true), "who bought it: " .. all)
    press(ns, "Take")
    settle()
    T.eq(GetMoney(), 48500)
    T.eq(ns.Ledger.Range("session").kinds.sales, 51000, "the ledger counts it")
end)

T.test("inbox: Collect all takes every letter's gold and items, skips cash on delivery", function()
    local ns = load({ money = 0, letters = {
        LETTERS[1], LETTERS[2],
        { sender = "Ysella Brightwind", subject = "Runecloth", cod = 60000, items = { { name = "Runecloth", itemID = 14047, count = 20 } } },
        { sender = "Alliance Auction House", subject = "Auction won: Linen Cloth (20)", items = { { name = "Linen Cloth", itemID = 2589, count = 20 } },
          invoice = { type = "buyer", item = "Linen Cloth", bid = 200, count = 20 } },
    } })
    MW.Open()
    frame(20)
    press(ns, "Collect all")
    settle()
    T.eq(GetMoney(), 48500 + 15000)
    T.eq(#MW.Bags(), 1, "the won cloth, not the COD runecloth")
    T.eq(MW.Bags()[1].name, "Linen Cloth")
    T.falsy(ns.Inbox.state.collecting, "done")
    T.eq(#MW.Calls("Refused"), 0, "never two commands at once")
end)

-- Collect all used to stop midway. Emptied auction letters are deleted and the
-- rest move up, so a letter with the same subject landed on a spot already tried.
T.test("inbox: Collect all empties a run of same-named auction letters in one press", function()
    local sale = function()
        return { sender = "Alliance Auction House", subject = "Auction successful: Light Leather (5)", money = 1000,
            invoice = { type = "seller", item = "Light Leather", bid = 1100, deposit = 5, cut = 105, count = 5 } }
    end
    local ns = load({ money = 0, letters = {
        sale(), sale(), sale(), sale(),
        { sender = "Brannoc Ironhide", subject = "Ore", body = "Here you go", money = 500,
          items = { { name = "Mithril Ore", itemID = 3858, count = 20 }, { name = "Iron Ore", itemID = 2772, count = 20 } } },
    } })
    MW.Open()
    frame(20)
    press(ns, "Collect all")
    settle()
    T.eq(GetMoney(), 4500, "every letter's gold")
    T.eq(#MW.Bags(), 2, "and both ores")
    T.eq(#MW.Inbox(), 1, "the sales gone, the letter with text kept")
    T.falsy(ns.Inbox.state.collecting, "done")
    T.eq(#MW.Calls("Refused"), 0, "never two commands at once")
end)

T.test("inbox: with full bags Collect all still takes the gold, then says the bags are full", function()
    local ns = load({ money = 0, bagFree = 0, letters = {
        { sender = "Brannoc Ironhide", subject = "Ore", money = 300, items = { { name = "Mithril Ore", itemID = 3858, count = 20 } } },
        { sender = "Alliance Auction House", subject = "Auction successful: Light Leather (5)", money = 1000,
          invoice = { type = "seller", item = "Light Leather", bid = 1100, deposit = 5, cut = 105, count = 5 } },
    } })
    MW.Open()
    frame(20)
    press(ns, "Collect all")
    settle()
    T.eq(GetMoney(), 1300, "every letter's gold")
    T.eq(#MW.Calls("TakeInboxItem"), 0, "no item tried: no room")
    T.falsy(ns.Inbox.state.collecting, "done")
    T.truthy(ns.Inbox.letter.full:IsShown(), "Your bags are full.")
end)

T.test("inbox: full bags stop Collect all and say so", function()
    local ns = load({ bagFree = 1, letters = {
        { sender = "Alliance Auction House", subject = "Auction canceled: Linen Cloth (20)", items = { { name = "Linen Cloth", itemID = 2589, count = 20 } } },
        { sender = "Brannoc Ironhide", subject = "Ore", items = { { name = "Mithril Ore", itemID = 3858, count = 20 } } },
    } })
    MW.Open()
    frame(20)
    press(ns, "Collect all")
    settle()
    T.falsy(ns.Inbox.state.collecting)
    T.truthy(ns.Inbox.letter.full:IsShown(), "Your bags are full.")
    T.eq(#MW.Calls("TakeInboxItem"), 1, "the one that fit, then stopped")
    T.eq(#MW.Bags(), 1)
end)

T.test("inbox: a COD letter's Take says the price and pays only on a second click", function()
    local ns = load({ money = 100000, letters = {
        { sender = "Ysella Brightwind", subject = "Runecloth", cod = 60000, items = { { name = "Runecloth", itemID = 14047, count = 20 } } } } })
    MW.Open()
    frame(20)
    lines(ns)[1].lineSpec.onClick()
    frame(2)
    T.truthy(button(ns, "Pay"), "Take says the price")
    press(ns, "Pay")
    settle()
    T.eq(GetMoney(), 100000, "not yet")
    press(ns, "Click again")
    settle()
    T.eq(GetMoney(), 40000)
end)

T.test("inbox: deleting a letter that still holds something asks twice; Reply opens Send to its writer", function()
    local ns = load()
    MW.Open()
    frame(20)
    lines(ns)[2].lineSpec.onClick()
    frame(2)
    press(ns, "Reply")
    frame(10)
    T.eq(ns.Window.frame.current, "send")
    T.eq(ns.Send.page.to:GetText(), "Brannoc Ironhide")
    T.eq(ns.Send.page.subject:GetText(), "Re: Ore money")
    ns.Window.ShowTab("inbox")
    frame(10)
    local heard = {}
    _G.PlaySoundFile = function(file) heard[file] = (heard[file] or 0) + 1 end
    lines(ns)[1].lineSpec.onClick()   -- the sale letter: the client lets it go (InboxItemCanDelete)
    T.eq(heard[DaylightUI.Sound.FILES.open], 1, "a letter opens")
    frame(2)
    press(ns, "Delete")
    settle()
    T.eq(#MW.Calls("DeleteInboxItem"), 0, "the first click only asks")
    press(ns, "Click again")
    settle()
    T.eq(#MW.Calls("DeleteInboxItem"), 1)
    _G.PlaySoundFile = nil
    T.eq(heard[DaylightUI.Sound.FILES.close], 1, "and closes when it goes")
end)

-- The game's OpenMail_Delete: a letter the client won't delete (a player's,
-- still holding gold or items) is sent back instead, the button says Return.
T.test("inbox: a player's letter with gold can't be deleted: the button returns it", function()
    local ns = load()
    MW.Open()
    frame(20)
    lines(ns)[2].lineSpec.onClick()   -- Brannoc's ore money
    frame(2)
    local foot = ns.Inbox.letter.foot.buttons
    T.eq(stub.Text(foot[#foot].text), MAIL_RETURN or "Return")
    foot[#foot].spec.onClick(foot[#foot])
    settle()
    T.eq(#MW.Calls("DeleteInboxItem"), 0)
    T.eq(MW.Calls("ReturnInboxItem")[1][1], 2)
end)

-- The client's answer missing (or erroring): Delete stays Delete, with its
-- second click, never a quiet Return of every letter.
T.test("inbox: with no answer from InboxItemCanDelete, Delete stays Delete", function()
    local ns = load()
    MW.Open()
    frame(20)
    local had = _G.InboxItemCanDelete
    _G.InboxItemCanDelete = function() error("gone") end
    lines(ns)[3].lineSpec.onClick()   -- Thaxton's hello
    frame(2)
    local foot = ns.Inbox.letter.foot.buttons
    T.eq(stub.Text(foot[#foot].text), "Delete")
    _G.InboxItemCanDelete = nil
    ns.Inbox.Render()
    T.eq(stub.Text(foot[#foot].text), "Delete")
    _G.InboxItemCanDelete = had
end)

-- Letters move: a new one comes in on top, an emptied one goes. The picked
-- letter and a Delete's second click stay with the same letter.
T.test("inbox: the picked letter and Delete's second click follow the letter when the others move", function()
    local ns = load()
    MW.Open()
    frame(20)
    lines(ns)[1].lineSpec.onClick()   -- the sale letter
    frame(2)
    press(ns, "Delete")
    MW.Arrive({ sender = "Mira Dawnsong", subject = "Thanks", money = 700 })
    MW.Deliver()
    frame(2)
    local head = ns.Inbox.letter.stack.used[1]
    T.eq(stub.Text(head.name), "Auction successful: Heavy Leather (20)", "the same letter still shows")
    T.truthy(lines(ns)[2].lineSpec.picked, "and is the picked line, now second")
    press(ns, "Click again")
    settle()
    T.eq(MW.Calls("DeleteInboxItem")[1][1], 2, "the sale letter, where it is now")
end)

-- Each letter's line keeps its id across refills (Stack:Ease), so a click,
-- a new letter or a take lets the others glide instead of all fading in anew.
T.test("inbox: a letter's line keeps its id across refills, even when it moves", function()
    local ns = load()
    MW.Open()
    frame(20)
    local function ids()
        local out = {}
        for _, b in ipairs(lines(ns)) do out[stub.Text(b.name)] = b.stackKey end
        return out
    end
    local before = ids()
    lines(ns)[2].lineSpec.onClick()
    frame(2)
    local after = ids()
    for name, key in pairs(before) do T.eq(after[name], key, name .. " after a click") end
    MW.Arrive({ sender = "Mira Dawnsong", subject = "Thanks", money = 700 })
    MW.Deliver()
    frame(2)
    local moved = ids()
    for name, key in pairs(before) do T.eq(moved[name], key, name .. " after a new letter") end
    T.truthy(moved.Thanks and moved.Thanks ~= before.Hello, "the new letter has its own id")
end)

-- A take the client keeps refusing (MAIL_FAILED with no item) doesn't keep
-- Collect all trying forever: that letter is left, the rest are taken.
T.test("inbox: Collect all leaves a letter whose gold the client keeps refusing", function()
    local ns = load({ money = 0 })
    MW.Open()
    frame(20)
    local was = _G.TakeInboxMoney
    _G.TakeInboxMoney = function(i)
        if i == 1 then stub.FireEvent("MAIL_FAILED"); return end
        was(i)
    end
    press(ns, "Collect all")
    settle()
    _G.TakeInboxMoney = was
    T.falsy(ns.Inbox.state.collecting, "done")
    T.eq(GetMoney(), 15000, "the other letter's gold")
end)

-- ---------------------------------------------------------------------
-- The Send page
-- ---------------------------------------------------------------------

local function sendPage(ns)
    ns.Window.ShowTab("send")
    frame(10)
    return ns.Send.page
end
local function tilesOf(page)
    local out = {}
    for _, b in ipairs(page.stack.used) do if b:IsShown() and b.spec and b.spec.name then out[#out + 1] = b end end
    return out
end
local function emptySlot(page)
    for _, b in ipairs(tilesOf(page)) do if b.spec.empty then return b end end
end

local function sendPress(ns, label)
    for _, b in ipairs(ns.Send.page.foot.buttons) do
        if b:IsShown() and stub.Text(b.text):find(label, 1, true) then
            if not b.spec.off then b.spec.onClick(b) end
            return
        end
    end
    error("no button " .. label)
end

T.test("send: a full name, gold and an item: postage and gold leave, the name is remembered", function()
    local ns = load({ money = 10000, letters = {} })
    MW.Open()
    frame(20)
    local page = sendPage(ns)
    T.truthy(MW.state.sendShowing, "the client hears the send page shows")
    MW.Cursor({ name = "Linen Cloth", itemID = 2589, count = 20 })
    local slot = emptySlot(page)
    slot:GetScript("OnReceiveDrag")(slot)
    frame(2)
    T.eq(#tilesOf(page), 2, "the item, then a new empty slot")
    T.truthy(stub.Text(emptySlot(page).sub):find("11", 1, true), stub.Text(emptySlot(page).sub))
    page.to:SetText("Shooty McGoovy")
    page.silver:SetText("5")
    local heard = {}
    _G.PlaySoundFile = function(file) heard[#heard + 1] = file end
    sendPress(ns, "Send")
    settle()
    local n = 0
    for _, f in ipairs(heard) do if f == DaylightUI.Sound.FILES.done then n = n + 1 end end
    _G.PlaySoundFile = nil
    T.eq(n, 1, "the chime, once it went")
    local sent = MW.Sent()[1]
    T.eq(sent.to, "Shooty McGoovy"); T.eq(sent.money, 500); T.eq(sent.subject, "Linen Cloth", "the first item's name when no subject")
    T.eq(GetMoney(), 10000 - 30 - 500)
    T.eq(ns.Send.Recent()[1], "Shooty McGoovy")
    T.eq(stub.Text(page.said), "Sent to Shooty McGoovy.")
    T.eq(page.silver:GetText(), "", "the form is empty again")
    T.eq(ns.Ledger.Range("session").kinds.sent, -500)
end)

-- The letter takes several lines. Enter or Shift+Enter starts a new one, and the
-- line breaks are sent with it (they used to be lost).
T.test("send: the letter is a box of several lines, its line breaks go out", function()
    local ns = load({ money = 10000, letters = {} })
    MW.Open()
    frame(20)
    local page = sendPage(ns)
    T.truthy(page.body:IsMultiLine(), "Enter starts a new line in the letter")
    T.truthy(page.letter.hint:IsShown(), "an empty letter shows its hint")
    page.to:SetText("Shooty McGoovy")
    page.subject:SetText("Ore")
    page.body:SetText("Hello,\nthe ore is in.\nThanks")
    T.falsy(page.letter.hint:IsShown(), "the hint goes with the text")
    sendPress(ns, "Send")
    settle()
    T.eq(MW.Sent()[1].body, "Hello,\nthe ore is in.\nThanks")
    T.eq(page.body:GetText(), "", "the letter is empty again")
    T.truthy(page.letter.hint:IsShown())
end)

-- A red line about something else while the letter goes (out of range, not
-- enough rage) isn't the mail refusing it: the success still empties the
-- form, so a second click can't send the gold again.
T.test("send: another error while sending doesn't stop the success emptying the form", function()
    local ns = load({ money = 10000, letters = {} })
    MW.Open()
    frame(20)
    local page = sendPage(ns)
    page.to:SetText("Shooty McGoovy")
    page.subject:SetText("Gold")
    page.silver:SetText("5")
    sendPress(ns, "Send")
    stub.FireEvent("UI_ERROR_MESSAGE", 51, "Out of range.")
    settle()
    T.eq(#MW.Sent(), 1)
    T.eq(stub.Text(page.said), "Sent to Shooty McGoovy.")
    T.eq(page.silver:GetText(), "", "the form is empty again")
end)

-- The client refusing the letter (the game's own Send button waits for
-- MAIL_FAILED): the button wakes again and the form stays as typed.
T.test("send: MAIL_FAILED gives the Send button back and keeps the form", function()
    local ns = load({ money = 10000, letters = {} })
    MW.Open()
    frame(20)
    local page = sendPage(ns)
    page.to:SetText("Shooty McGoovy")
    page.subject:SetText("Gold")
    page.silver:SetText("5")
    local was = _G.SendMail
    _G.SendMail = function() stub.FireEvent("MAIL_FAILED") end
    sendPress(ns, "Send")
    _G.SendMail = was
    settle()
    T.eq(page.silver:GetText(), "5")
    T.falsy(ns.Send.state.sending, "Send works again")
end)

-- A send the client never answers (no MAIL_FAILED, no success, no red
-- line): leaving the mailbox ends it, so Send works on the next visit.
T.test("send: a send never answered is over when the mailbox closes", function()
    local ns = load({ money = 10000, letters = {} })
    MW.Open()
    frame(20)
    local page = sendPage(ns)
    page.to:SetText("Shooty McGoovy")
    page.subject:SetText("Gold")
    page.silver:SetText("5")
    local was = _G.SendMail
    _G.SendMail = function() end
    sendPress(ns, "Send")
    _G.SendMail = was
    T.truthy(ns.Send.state.sending)
    MW.Leave()
    frame(20)
    T.falsy(ns.Send.state.sending, "over at MAIL_CLOSED")
    MW.Open()
    frame(20)
    page = sendPage(ns)
    page.to:SetText("Shooty McGoovy")
    page.subject:SetText("Gold")
    page.silver:SetText("5")
    sendPress(ns, "Send")
    settle()
    T.eq(#MW.Sent(), 1, "the next visit sends")
end)

-- A letter to a stranger first asks in the client's secure transfer box.
-- Cancel there sends nothing and fires no MAIL_FAILED: the game only wakes its
-- own Send button. Daylight UI's must wake too, or it stays off until /reload.
T.test("send: cancelling the stranger box gives the Send button back", function()
    local ns = load({ money = 100000, letters = {}, strangers = true })
    MW.Open()
    frame(20)
    local page = sendPage(ns)
    page.to:SetText("Ima Skint")
    page.gold:SetText("2")
    sendPress(ns, "Send")
    T.truthy(ns.Send.state.sending, "waits for the box")
    MW.Transfer(false)
    frame(5)
    T.falsy(ns.Send.state.sending, "Send works again after Cancel")
    T.eq(page.gold:GetText(), "2", "the form stays as typed")
    sendPress(ns, "Send")
    MW.Transfer(true)
    settle()
    T.eq(#MW.Sent(), 1, "Okay sends it")
    T.eq(MW.Sent()[1].money, 20000)
    T.falsy(ns.Send.state.sending)
end)

T.test("send: gold with no item and no subject still goes, the amount as its subject", function()
    local ns = load({ money = 100000, letters = {} })
    MW.Open()
    frame(20)
    local page = sendPage(ns)
    page.to:SetText("Ysella Brightwind")
    page.gold:SetText("2")
    page.silver:SetText("5")
    sendPress(ns, "Send")
    settle()
    T.eq(#MW.Sent(), 1, "the client took it")
    T.eq(MW.Sent()[1].money, 20500)
    T.eq(MW.Sent()[1].subject, "2 Gold, 5 Silver")
end)

T.test("send: a subject you wrote stays on a gold letter; nothing at all still asks for one", function()
    local ns = load({ money = 100000, letters = {} })
    MW.Open()
    frame(20)
    local page = sendPage(ns)
    page.to:SetText("Ysella Brightwind")
    sendPress(ns, "Send")
    T.eq(#MW.Calls("SendMail"), 0, "nothing to send")
    T.truthy(stub.Text(page.said):find("subject", 1, true))
    page.subject:SetText("For the road")
    page.gold:SetText("2")
    sendPress(ns, "Send")
    settle()
    T.eq(MW.Sent()[1].subject, "For the road")
end)

T.test("send: one word in To says to write the full name, nothing is sent", function()
    local ns = load({ letters = {} })
    MW.Open()
    frame(20)
    local page = sendPage(ns)
    page.to:SetText("beorn")
    page.subject:SetText("Hi")
    sendPress(ns, "Send")
    settle()
    T.eq(#MW.Calls("SendMail"), 0)
    T.truthy(stub.Text(page.said):find("first and last", 1, true))
end)

T.test("send: cash on delivery needs an item and a price, then sends as COD", function()
    local ns = load({ money = 10000, letters = {} })
    MW.Open()
    frame(20)
    local page = sendPage(ns)
    page.to:SetText("Ysella Brightwind")
    page.gold:SetText("6")
    page.cod:GetScript("OnClick")(page.cod)
    sendPress(ns, "Send")
    T.eq(#MW.Calls("SendMail"), 0, "no item yet")
    MW.Cursor({ name = "Runecloth", itemID = 14047, count = 20 })
    ns.Send.Attach()
    sendPress(ns, "Send")
    settle()
    T.eq(MW.Sent()[1].cod, 60000)
    T.eq(MW.Sent()[1].money, 0)
end)

T.test("send: a click on an attached item takes it back; your other characters are chips", function()
    local ns = load({ letters = {} })
    local chars = DaylightUI.DB.Root().characters
    local key = DaylightUI.DB.CharKey()
    local realm = key and key:match("%-(.*)$") or ""
    chars["Mybank-" .. realm] = { mailName = "Mybank Vaultkeeper" }
    MW.Open()
    frame(20)
    local page = sendPage(ns)
    local shown = {}
    for _, b in ipairs(page.chips) do if b:IsShown() then shown[#shown + 1] = b.name end end
    T.truthy(table.concat(shown, ","):find("Mybank Vaultkeeper", 1, true), table.concat(shown, ","))
    MW.Cursor({ name = "Linen Cloth", itemID = 2589, count = 20 })
    ns.Send.Attach()
    frame(2)
    T.truthy(emptySlot(page), "an empty slot to start with")
    local tile
    for _, b in ipairs(tilesOf(page)) do if not b.spec.empty then tile = b end end
    T.truthy(tile, "the item shows")
    tile.spec.onClick(tile)
    frame(2)
    T.eq(#ns.Send.Items(), 0)
end)

T.test("inbox: the letter's footer buttons never overlap; Collect all sits under the list", function()
    local ns = load()
    MW.Open()
    frame(20)
    lines(ns)[2].lineSpec.onClick()
    frame(5)
    T.truthy(button(ns, "Collect all"):GetParent() == ns.Inbox.list.foot.frame, "Collect all is the list's")
    local bs = {}
    for _, b in ipairs(ns.Inbox.letter.foot.buttons) do if b:IsShown() then bs[#bs + 1] = b end end
    T.eq(#bs, 4)
    local room = ns.Inbox.letter.foot.frame:GetWidth()
    local used = 0
    for _, b in ipairs(bs) do used = used + b:GetWidth() end
    T.truthy(used <= room, string.format("%d px of buttons in %d px", used, room))
end)

-- ---------------------------------------------------------------------
-- The Ledger page
-- ---------------------------------------------------------------------

local function ledgerPage(ns)
    ns.Window.ShowTab("ledger")
    frame(20)
    return ns.LedgerPage.page
end

local function rightLines(page)
    local out = {}
    for _, b in ipairs(page.right.stack.used) do
        if b:IsShown() and b.lineSpec then out[#out + 1] = b end
    end
    return out
end

T.test("ledger page: a flip shows its profit: the net, came in and went out, by item, latest", function()
    local ns = load({ money = 100000, letters = {} })
    MW.OpenAH()
    MW.BuyCommodity({ name = "Heavy Leather", itemID = 4234, count = 20, unit = 1000 })
    MW.Settle()
    local id = MW.Post({ name = "Heavy Leather", itemID = 4234, count = 20, deposit = 100, price = 51000 })
    MW.Settle()
    MW.CloseAH()
    MW.Sold(id, { cut = 2550 })
    MW.Open()
    frame(20)
    MW.Deliver()
    frame(2)
    TakeInboxMoney(1)
    settle()
    local page = ledgerPage(ns)
    local net = 51000 - 2550 - 20000
    T.eq(stub.Text(page.net), DUI_money(net))
    T.eq(stub.Text(page.inRows[1].value), DUI_money(51000), "auction sales")
    T.eq(stub.Text(page.outRows[1].value), "-" .. DUI_money(20000), "auction buys")
    local ls = rightLines(page)
    T.eq(stub.Text(ls[1].name), "Heavy Leather", "by item")
    T.eq(stub.Text(ls[1].value), "+" .. DUI_money(net), "what the flip made")
    T.truthy(stub.Text(ls[2].name):find("Sold: Heavy Leather", 1, true), "the latest: " .. stub.Text(ls[2].name))
end)

T.test("ledger page: the range chips change the days and the net; a loss reads in the damage color", function()
    local ns = load({ money = 100000, letters = {} })
    MW.OpenAH()
    MW.BuyCommodity({ name = "Wool Cloth", itemID = 2592, count = 10, unit = 300 })
    MW.Settle()
    MW.CloseAH()
    MW.Open()
    frame(20)
    local page = ledgerPage(ns)
    local shown = 0
    for _, c in ipairs(page.days.cols) do if c:IsShown() then shown = shown + 1 end end
    T.eq(shown, 7, "7 days")
    local r, g, b = page.net:GetTextColor()
    local d = DaylightUI.Style.INK.DAMAGE
    T.near(r, d[1], 0.01); T.near(g, d[2], 0.01); T.near(b, d[3], 0.01)
    ns.LedgerPage.Pick("month")
    frame(20)
    shown = 0
    for _, c in ipairs(page.days.cols) do if c:IsShown() then shown = shown + 1 end end
    T.eq(shown, 30)
    T.truthy(page.chips.month:IsShown())
end)

T.test("ledger page: something booked while it shows paints it again", function()
    local ns = load({ money = 0, letters = { { sender = "Brannoc Ironhide", subject = "Ore money", money = 15000 } } })
    MW.Open()
    frame(20)
    local page = ledgerPage(ns)
    T.eq(stub.Text(page.net), DUI_money(0))
    TakeInboxMoney(1)
    settle()
    frame(20)   -- the number counts to its value
    T.eq(stub.Text(page.net), DUI_money(15000))
    T.eq(stub.Text(page.inRows[2].value), DUI_money(15000), "from players")
end)

T.test("mail: our mailbox is on by default", function()
    local ns = load({ letters = {} })
    T.truthy(ns.module.db.enabled)
    T.truthy(DaylightUI.mailOwnWindow)
end)

T.test("send: all 12 slots used, no empty one is left", function()
    local ns = load({ letters = {} })
    MW.Open()
    frame(20)
    local page = sendPage(ns)
    for i = 1, 12 do
        MW.Cursor({ name = "Linen Cloth", itemID = 2589, count = i })
        emptySlot(page).spec.onClick()
        frame(2)
    end
    T.eq(#ns.Send.Items(), 12)
    T.isnil(emptySlot(page))
end)

local function chipNames(page)
    local shown = {}
    for _, b in ipairs(page.chips) do if b:IsShown() then shown[#shown + 1] = b.name end end
    return shown
end
local function typeTo(page, text)
    page.to:SetText(text)
    page.to:GetScript("OnTextChanged")(page.to, true)
    frame(2)
end

T.test("send: the name chips fit the Send page even opened from the wider inbox", function()
    local ns = load({ letters = {} })
    for _, n in ipairs({ "Aldwyn Brightmantle", "Corvina Ashenhollow", "Thessaly Moonwhisper", "Bartholomew Stoneforge",
                         "Ysolde Ravenmoor", "Gideon Hearthstone" }) do ns.Send.Remember(n) end
    MW.Open()
    frame(20)
    T.eq(ns.Window.frame.current, "inbox")
    local page = sendPage(ns)
    local room = ns.Window.SEND_W - ns.Send.EDGE
    T.truthy(#chipNames(page) > 0)
    for _, b in ipairs(page.chips) do
        if b:IsShown() then T.truthy(b.x + b:GetWidth() <= room, b.name .. " runs past the page") end
    end
end)

T.test("send: typing filters the chips by first or last name, with the client's suggestions; Tab takes the first", function()
    local ns = load({ letters = {} })
    local chars = DaylightUI.DB.Root().characters
    local realm = (DaylightUI.DB.CharKey() or ""):match("%-(.*)$") or ""
    chars["Mybank-" .. realm] = { mailName = "Mybank Vaultkeeper" }
    ns.Send.Remember("Brannoc Ironhide")
    local asked
    _G.C_AutoComplete = { GetAutoCompleteResults = function(text, n, cursor, full, include, exclude)
        asked = { text = text, exclude = exclude }
        if ("vaelith"):sub(1, #text) == text:lower() then return { { name = "Vaelith Dawnsong", priority = 4 } } end
        return {}
    end }
    MW.Open()
    frame(20)
    local page = sendPage(ns)
    T.eq(table.concat(chipNames(page), ","), "Brannoc Ironhide,Mybank Vaultkeeper", "nothing typed: recent, then alts")
    typeTo(page, "vault")
    T.eq(table.concat(chipNames(page), ","), "Mybank Vaultkeeper", "a last name fits too")
    typeTo(page, "Va")
    T.eq(table.concat(chipNames(page), ","), "Mybank Vaultkeeper,Vaelith Dawnsong", "the client's suggestion joins")
    T.eq(asked.text, "Va"); T.eq(asked.exclude, 8, "no Battle.net friends, as the game's mail box")
    typeTo(page, "vae")
    page.to:GetScript("OnTabPressed")(page.to)
    T.eq(page.to:GetText(), "Vaelith Dawnsong")
    _G.C_AutoComplete = nil
end)

T.test("ledger page: items show their icon and the game's tooltip, from the ID the ledger kept", function()
    local ns = load({ money = 100000, letters = {} })
    MW.OpenAH()
    MW.BuyCommodity({ name = "Heavy Leather", itemID = 4234, count = 20, unit = 1000 })
    MW.Settle()
    MW.CloseAH()
    MW.Open()
    frame(20)
    MW.Deliver()   -- the won letter carries the item: its ID
    frame(2)
    local page = ledgerPage(ns)
    local line = rightLines(page)[1]
    T.eq(stub.Text(line.name), "Heavy Leather")
    T.eq(line.icon:GetTexture(), "icon:4234")
    local asked
    local was = _G.GameTooltip
    _G.GameTooltip = { SetOwner = function() end, Show = function() end, Hide = function() end,
        IsOwned = function() return false end, SetItemByID = function(_, id) asked = id end }
    line:GetScript("OnEnter")(line)
    _G.GameTooltip = was
    T.eq(asked, 4234, "the game's item tooltip")
end)

T.test("mailbox on a controller: X opens all, replies to the letter read, or sends; Y its options", function()
    local ns = load({ money = 0 })
    MW.Open()
    frame(20)
    local f = ns.Window.frame
    local function x()
        for _, e in ipairs(f.padKeys) do if e.key == "X" and e.when() then return e.label end end
    end
    T.eq(x(), OPEN_ALL_MAIL_BUTTON or "Collect all")
    local function y()
        for _, e in ipairs(f.padKeys) do if e.key == "Y" and e.when() then return e end end
    end
    T.falsy(y(), "nothing read: no options")
    lines(ns)[1].lineSpec.onClick()
    frame(5)
    T.truthy(y(), "a letter read has its options")
    ns.Window.ShowTab("send")
    frame(5)
    T.eq(x(), SEND_LABEL or "Send")
end)

-- ---------------------------------------------------------------------
-- Shift-click and ticked letters
-- ---------------------------------------------------------------------

local function shiftClick(b)
    local was = _G.IsModifiedClick
    _G.IsModifiedClick = function(what) return what == "MAILAUTOLOOTTOGGLE" end
    b.lineSpec.onClick(b)
    _G.IsModifiedClick = was
end
local function tick(b) b.tick:GetScript("OnClick")(b.tick) end

local function expired(n)
    return { sender = "Alliance Auction House", subject = "Auction expired: Linen Cloth (20)",
        items = { { name = "Linen Cloth", itemID = 2589, count = 20 + n } } }
end

T.test("inbox: Shift-click a letter takes everything in it and leaves the others", function()
    local ns = load({ money = 0, letters = {
        expired(1),
        { sender = "Brannoc Ironhide", subject = "Ore", money = 500, items = { { name = "Mithril Ore", itemID = 3858, count = 20 } } },
        expired(2),
    } })
    MW.Open()
    frame(20)
    shiftClick(lines(ns)[2])
    settle()
    T.eq(GetMoney(), 500, "its gold")
    T.eq(#MW.Bags(), 1, "and its ore")
    T.eq(MW.Bags()[1].name, "Mithril Ore")
    T.eq(#MW.Inbox(), 2, "the expired auctions stay")
    T.eq(#MW.Calls("Refused"), 0)
end)

T.test("inbox: Shift-click on a cash on delivery letter only opens it", function()
    local ns = load({ money = 100000, letters = {
        { sender = "Ysella Brightwind", subject = "Runecloth", cod = 60000, items = { { name = "Runecloth", itemID = 14047, count = 20 } } } } })
    MW.Open()
    frame(20)
    shiftClick(lines(ns)[1])
    settle()
    T.eq(GetMoney(), 100000, "nothing paid")
    T.eq(#MW.Calls("AutoLootMailItem"), 0)
    T.truthy(ns.Inbox.Picked(), "opened")
end)

T.test("inbox: ticked letters are all the collect button takes; the ticks go with them", function()
    local ns = load({ money = 0, letters = {
        LETTERS[1],
        expired(1),
        { sender = "Brannoc Ironhide", subject = "Ore money", money = 15000 },
        { sender = "Ysella Brightwind", subject = "Runecloth", cod = 60000, items = { { name = "Runecloth", itemID = 14047, count = 20 } } },
    } })
    MW.Open()
    frame(20)
    T.eq(ns.DEFAULTS.ticks, false, "off as shipped")
    T.falsy(lines(ns)[1].tick and lines(ns)[1].tick:IsShown(), "off: no ticks")
    T.truthy(button(ns, "Collect all"))
    DaylightUI:Set("Mailbox", "ticks", true)
    frame(2)
    local ls = lines(ns)
    T.truthy(ls[4].tick.off, "a COD letter can't be ticked")
    tick(ls[1])
    tick(ls[3])
    tick(ls[4])
    frame(2)
    T.truthy(button(ns, "Collect ticked (2)"), "the button counts the ticks")
    press(ns, "Collect ticked")
    settle()
    T.eq(GetMoney(), 48500 + 15000, "both ticked letters' gold")
    T.eq(#MW.Bags(), 0, "the expired auction stays in the box")
    T.eq(#ns.Inbox.state.ticked, 0, "no ticks left")
    T.truthy(button(ns, "Collect all"), "back to Collect all")
    T.eq(#MW.Calls("Refused"), 0)
end)

T.test("inbox: of identical letters only the ticked one is taken", function()
    local same = function()
        return { sender = "Alliance Auction House", subject = "Auction expired: Linen Cloth (20)",
            items = { { name = "Linen Cloth", itemID = 2589, count = 20 } } }
    end
    local ns = load({ letters = { same(), same(), same() } })
    DaylightUI:Set("Mailbox", "ticks", true)
    MW.Open()
    frame(20)
    tick(lines(ns)[2])
    frame(2)
    press(ns, "Collect ticked (1)")
    settle()
    T.eq(#MW.Bags(), 1, "one letter's cloth")
    T.eq(#MW.Inbox(), 2)
    T.eq(#ns.Inbox.state.ticked, 0)
    tick(lines(ns)[1])
    tick(lines(ns)[1])
    T.eq(#ns.Inbox.state.ticked, 0, "a second click unticks")
end)

-- Longer words (Spanish, German): each letter 14 px instead of the stub's 7 (per = 5 for short ones).
local function wide(spec, per)
    local keep = stub.measure
    stub.measure = function(fs) return #(fs.__text or "") * (per or 14) end
    local ns = load(spec)
    stub.measure = keep
    return ns
end

local function chipsOf(map)
    local out = {}
    for _, b in pairs(map) do out[#out + 1] = b end
    return out
end

local function rowsOf(chips)
    local ys = {}
    for _, b in ipairs(chips) do ys[select(5, b:GetPoint(1))] = true end
    local n = 0
    for _ in pairs(ys) do n = n + 1 end
    return n
end

T.test("inbox: filter chips that do not fit the list take a second row, and the list starts below them", function()
    local ns = wide()
    MW.Open()
    frame(20)
    local list = ns.Inbox.list
    local chips = chipsOf(list.chips)
    T.eq(#chips, 4)
    T.eq(rowsOf(chips), 2, "two rows")
    for _, b in ipairs(chips) do
        local _, _, _, x = b:GetPoint(1)
        T.truthy(x + b:GetWidth() <= ns.Inbox.LIST_W - ns.Inbox.EDGE, "a chip runs past the list")
    end
    local _, _, _, _, y = list.stack.scroll:GetPoint(1)
    T.truthy(-y >= ns.Inbox.CHIPS_Y + 2 * DaylightUI.Widgets.CHIP_HEIGHT, "the list starts under the chips")
end)

T.test("inbox: chips that fit stay on one row", function()
    local ns = wide(nil, 5)
    MW.Open()
    frame(20)
    T.eq(rowsOf(chipsOf(ns.Inbox.list.chips)), 1)
end)

T.test("ledger page: range chips wrap inside the left column and the rows move down with them", function()
    local ns = wide({ letters = {} })
    MW.Open()
    local page = ledgerPage(ns)
    local chips = chipsOf(page.chips)
    T.eq(rowsOf(chips), 2)
    for _, b in ipairs(chips) do
        local _, _, _, x = b:GetPoint(1)
        T.truthy(x + b:GetWidth() <= ns.LedgerPage.LEFT_W - ns.LedgerPage.EDGE, "a chip runs past the column")
    end
    local _, _, _, _, labelY = page.rangeLabel:GetPoint(1)
    T.truthy(-labelY >= ns.LedgerPage.CHIPS_Y + 2 * DaylightUI.Widgets.CHIP_HEIGHT, "the label is under the second row")
end)

T.test("ledger page: a row's name ends where its amount starts", function()
    local ns = load({ letters = {} })
    MW.Open()
    local page = ledgerPage(ns)
    for _, row in ipairs(page.outRows) do
        local _, rel = row.label:GetPoint(2)
        T.eq(rel, row.value, "the name is bounded by the amount")
    end
end)

T.test("mail: the ledger is wide enough for its left column and the grip's resize reaches the lists", function()
    local ns = load({ letters = {} })
    MW.Open()
    frame(20)
    ns.Window.ShowTab("ledger")
    frame(20)
    T.near(ns.Window.frame:GetWidth(), ns.Window.LEDGER_W, 1)
    local page = ns.LedgerPage.page
    local called = 0
    local stretch = page.right.stack.Stretch
    page.right.stack.Stretch = function(...) called = called + 1; return stretch(...) end
    ns.Window.Resized(900, 560, true)
    T.eq(called, 1, "live: the right list stretches")
    local renders = 0
    local render = ns.LedgerPage.Render
    ns.LedgerPage.Render = function(...) renders = renders + 1; return render(...) end
    ns.Window.Resized(900, 560, false)
    ns.LedgerPage.Render = render
    T.eq(renders, 1, "end: the page fills again")
end)

T.test("send: the letter's text area has the outline an input has, lit by hover and focus", function()
    local ns = load({ letters = {} })
    MW.Open()
    local page = sendPage(ns)
    local area = page.letter
    T.truthy(area.edge and area.lit, "the same outline as W.Input")
    T.eq(area.glow, 0)
    area.box.IsMouseOver = function() return true end
    area:GetScript("OnEnter")(area)
    frame(20)
    T.truthy(area.glow > 0.3, "hover lights it")
    area.box.IsMouseOver = function() return false end
    area:GetScript("OnLeave")(area)
    frame(20)
    T.eq(area.glow, 0)
    page.body.HasFocus = function() return true end
    area.Ease()
    frame(20)
    T.near(area.glow, 1, 0.01)
end)

T.test("ledger page: when the right side gets wider the lists fill again at that width", function()
    local ns = load({ letters = {} })
    MW.Open()
    frame(20)
    local page = ledgerPage(ns)
    page.right:GetScript("OnSizeChanged")(page.right, 900, 500)
    frame(5)
    T.eq(page.right.stack.wide, 900 - 2 * DaylightUI.Win.Parts.EDGE)
    T.near(page.right.stack.child:GetWidth(), 900 - 2 * DaylightUI.Win.Parts.EDGE, 1, "the list is as wide as the side")
end)

T.test("inbox: the letter's side keeps the width it is given too", function()
    local ns = load()
    MW.Open()
    frame(20)
    local letter = ns.Inbox.letter
    letter:GetScript("OnSizeChanged")(letter, 800, 500)
    T.eq(letter.stack.wide, 800 - 2 * DaylightUI.Win.Parts.EDGE)
end)

-- The game's own words: the mailbox's globals win over ours, in the client's language.
local function game(words, fn)
    local keep = {}
    for k, v in pairs(words) do keep[k] = _G[k]; _G[k] = v end
    local ok, err = pcall(fn)
    for k in pairs(words) do _G[k] = keep[k] end
    if not ok then error(err, 0) end
end

T.test("mail: ns.Game takes the game's word, drops its colon, and falls back to ours", function()
    local ns = load()
    game({ MAIL_TO_LABEL = "Para:", MAIL_SUBJECT_LABEL = "Asunto :", SALE_PRICE_COLON = "Precio de venta:" }, function()
        T.eq(ns.Game("MAIL_TO_LABEL", "To"), "Para")
        T.eq(ns.Game("MAIL_SUBJECT_LABEL", "Subject"), "Asunto", "French puts a space before the colon")
        T.eq(ns.Game("SALE_PRICE_COLON", "Sold for"), "Precio de venta", "a row label has no colon either")
    end)
    T.eq(ns.Game("NOT_A_GAME_STRING", "Subject"), "Subject")
end)

T.test("mail: the Send tab says what the game's tab says", function()
    game({ SENDMAIL = "Enviar correo" }, function()
        local ns = load()
        MW.Open()
        frame(20)
        local text
        for _, b in ipairs(ns.Window.frame.tabs) do if b.id == "send" then text = stub.Text(b.text) end end
        T.eq(text, "Enviar correo")
    end)
end)

T.test("inbox: a receipt uses the game's invoice words, and a COD letter says COD the game's way", function()
    game({ PURCHASED_BY_COLON = "Comprador:", SALE_PRICE_COLON = "Precio de venta:", AMOUNT_RECEIVED_COLON = "Cantidad recibida:",
           COD = "Contra reembolso" }, function()
        local ns = load({ money = 0, letters = { LETTERS[1],
            { sender = "Ysella Brightwind", subject = "Runecloth", cod = 60000, days = 2, items = { { name = "Runecloth", itemID = 14047, count = 20 } } } } })
        MW.Open()
        frame(20)
        T.eq(stub.Text(lines(ns)[2].value), "Contra reembolso")
        lines(ns)[1].lineSpec.onClick()
        frame(5)
        local text = {}
        for _, b in ipairs(ns.Inbox.letter.stack.used) do if b:IsShown() and b.text and not b.lineSpec then text[#text + 1] = stub.Text(b.text) end end
        local all = table.concat(text, "\n")
        T.truthy(all:find("Comprador", 1, true) and all:find("Precio de venta", 1, true) and all:find("Cantidad recibida", 1, true) and not all:find("Comprador:", 1, true) and not all:find("Precio de venta:", 1, true), all)
        T.falsy(all:find("Sold for", 1, true), "ours is only the fallback")
    end)
end)

-- The NPC window's dialogue keys reach the mailbox: Space collects, as the button's
-- hint says. It never steals Space from the game when the keys are off, on the Send
-- page, or in a fight.
T.test("inbox: Space collects all with dialogue keys on, and only then", function()
    local ns = load({ money = 0, letters = { LETTERS[1], LETTERS[2] } })
    MW.Open()
    frame(20)
    local f = ns.Window.frame
    local k = f.keys
    T.truthy(k and k:IsKeyboardEnabled(), "the mailbox listens for keys while open")
    T.truthy(stub.Text(button(ns, "Collect all").text):find("Space", 1, true), "the button shows its key")
    k:GetScript("OnKeyDown")(k, "SPACE")
    T.eq(k:GetPropagateKeyboardInput(), false, "Space is taken, so the character doesn't jump")
    settle()
    T.eq(GetMoney(), 48500 + 15000, "Space collected everything")
    k:GetScript("OnKeyUp")(k, "SPACE")
    k:GetScript("OnKeyDown")(k, "W")
    T.eq(k:GetPropagateKeyboardInput(), true, "other keys stay the game's")

    ns.Window.ShowTab("send")
    k:GetScript("OnKeyDown")(k, "SPACE")
    T.eq(k:GetPropagateKeyboardInput(), true, "on the Send page Space is the game's")
    ns.Window.ShowTab("inbox")

    DaylightUI:Set("NPC", "keys", false)
    MW.Leave(); frame(20); MW.Open(); frame(20)
    k:GetScript("OnKeyDown")(k, "SPACE")
    T.eq(k:GetPropagateKeyboardInput(), true, "keys off: Space is the game's")
    T.falsy(stub.Text(button(ns, "Collect all").text):find("Space", 1, true), "and no hint")
    DaylightUI:Set("NPC", "keys", true)
end)

T.test("inbox: Space after a fight starts goes to the game, and closing gives keys back", function()
    local ns = load({ money = 0, letters = { LETTERS[1] } })
    MW.Open()
    frame(20)
    local k = ns.Window.frame.keys
    stub.EnterCombat()
    k:GetScript("OnKeyDown")(k, "SPACE")
    frame(5)
    T.falsy(ns.Inbox.state.collecting, "nothing collected by a key in combat")
    stub.LeaveCombat()
    MW.Leave()
    frame(20)
    T.falsy(k:IsKeyboardEnabled(), "closed: no keys held")
end)
