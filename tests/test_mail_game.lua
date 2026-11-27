local stub = require("stub")
local MW = require("mailworld")

-- What the game's own mailbox does (Blizzard_MailFrame), kept by Daylight UI's:
-- letter hovers, item links, COD per item, the gold and the letter's copy as tiles,
-- right-click Report spam, Reply, the Send form's keys, completion, drag and drop,
-- cursor money, the subject from the items, COD rules and trial accounts.

local function load(spec)
    spec = spec or {}
    spec.letters = spec.letters or {}
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
local function sendPage(ns)
    ns.Window.ShowTab("send")
    frame(10)
    return ns.Send.page
end
local function tilesOf(page)
    local out = {}
    for _, b in ipairs(page.stack.used) do if b:IsShown() and b.spec and b.spec.name and not b.spec.empty then out[#out + 1] = b end end
    return out
end
local function emptySlot(page)
    for _, b in ipairs(page.stack.used) do if b:IsShown() and b.spec and b.spec.empty then return b end end
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
local function typeTo(page, text)
    page.to:SetText(text)
    page.to:GetScript("OnTextChanged")(page.to, true)
    frame(2)
end

-- A tooltip that writes down what it was told.
local function recordTip()
    local rec = { lines = {} }
    function rec.text()
        local out = {}
        for _, l in ipairs(rec.lines) do out[#out + 1] = l[1] end
        return table.concat(out, "\n")
    end
    rec.tip = { SetOwner = function() end, Show = function() end, Hide = function() end, ClearLines = function() end,
        IsOwned = function() return true end, IsShown = function() return true end, NumLines = function() return #rec.lines end,
        AddLine = function(_, t, r, g, b) rec.lines[#rec.lines + 1] = { tostring(t), { r, g, b } } end,
        AddDoubleLine = function(_, a, v, _, _, _, r, g, b) rec.lines[#rec.lines + 1] = { tostring(a) .. " = " .. tostring(v), { r, g, b } } end,
        SetText = function(_, t) rec.lines[#rec.lines + 1] = { tostring(t) } end,
        SetInboxItem = function(_, i, a) rec.inbox = { i, a } end,
        SetSendMailItem = function(_, s) rec.send = s end }
    return rec
end
local function hover(b)
    local rec = recordTip()
    local was = _G.GameTooltip
    _G.GameTooltip = rec.tip
    b:GetScript("OnEnter")(b)
    _G.GameTooltip = was
    return rec
end
local function same(a, b)
    return type(a) == "table" and type(b) == "table" and a[1] and math.abs(a[1] - b[1]) < 0.01
        and math.abs(a[2] - b[2]) < 0.01 and math.abs(a[3] - b[3]) < 0.01
end
local function letterTiles(ns)
    local out = {}
    for _, b in ipairs(ns.Inbox.letter.stack.used) do if b:IsShown() and b.spec and b.spec.name then out[#out + 1] = b end end
    return out
end
local function tileNamed(ns, name)
    for _, b in ipairs(letterTiles(ns)) do if stub.Text(b.name):find(name, 1, true) then return b end end
end
local function click(b, which) b:GetScript("OnClick")(b, which or "LeftButton") end
local function pick(ns, n)
    local b = lines(ns)[n]
    b:GetScript("OnClick")(b, "LeftButton")
    frame(5)
end

T.test("inbox: hovering a letter shows what's in it, the gold, a COD in red you can't pay, and when it goes", function()
    local ns = load({ money = 5000, letters = {
        { sender = "Brannoc Ironhide", subject = "Ore", money = 15000, days = 10, items = { { name = "Copper Ore", itemID = 2770, count = 5 }, { name = "Tin Ore", itemID = 2771 } } },
        { sender = "Ysella Brightwind", subject = "Runecloth", cod = 60000, days = 0.25, items = { { name = "Runecloth", itemID = 14047, count = 20 } } },
    } })
    MW.Open()
    frame(20)
    local ls = lines(ns)
    local tip = hover(ls[1])
    T.truthy(tip.text():find("(2)", 1, true), "two items: " .. tip.text())
    T.truthy(tip.text():find(DaylightUI.MoneyString(15000), 1, true), "the gold enclosed: " .. tip.text())
    tip = hover(ls[2])
    local cod
    for _, l in ipairs(tip.lines) do if l[1]:find(DaylightUI.MoneyString(60000), 1, true) then cod = l end end
    T.truthy(cod, "the COD price: " .. tip.text())
    T.truthy(cod and same(cod[2], DaylightUI.Style.INK.BAD), "red: more than you have")
    T.truthy(tip.text():find("6 hr", 1, true), "under a day: the hours left, " .. tip.text())
    T.eq(stub.Text(ls[2].subValue), "6 hr", "the hours left on the line too")
end)

T.test("inbox: an item in a letter Shift-links and its COD price shows on it", function()
    local ns = load({ money = 5000, letters = {
        { sender = "Ysella Brightwind", subject = "Runecloth", cod = 60000, items = { { name = "Runecloth", itemID = 14047, count = 20 } } },
    } })
    MW.Open()
    frame(20)
    pick(ns, 1)
    local b = tileNamed(ns, "Runecloth")
    T.truthy(b, "the item tile")
    local tip = hover(b)
    T.eq(tip.inbox and tip.inbox[2], 1, "the game's item tooltip")
    T.truthy(tip.text():find(DaylightUI.MoneyString(60000), 1, true), "and the COD price: " .. tip.text())
    local linked
    _G.HandleModifiedItemClick = function(link) linked = link; return true end
    click(b)
    _G.HandleModifiedItemClick = nil
    T.truthy(linked and linked:find("14047", 1, true), "Shift-click links it")
end)

T.test("inbox: a COD item taken by itself asks to pay, and one you can't pay says so and takes nothing", function()
    local ns = load({ money = 100000, letters = {
        { sender = "Ysella Brightwind", subject = "Cloth", cod = 60000, items = { { name = "Runecloth", itemID = 14047, count = 20 }, { name = "Mageweave", itemID = 4338 } } },
    } })
    MW.Open()
    frame(20)
    pick(ns, 1)
    click(tileNamed(ns, "Mageweave"))
    T.eq(#MW.Calls("TakeInboxItem"), 0, "the first click asks")
    T.truthy(stub.Text(tileNamed(ns, "Mageweave").sub):find("again", 1, true), stub.Text(tileNamed(ns, "Mageweave").sub))
    click(tileNamed(ns, "Mageweave"))
    T.eq(#MW.Calls("TakeInboxItem"), 1)
    T.eq(MW.Calls("TakeInboxItem")[1] and MW.Calls("TakeInboxItem")[1][2], 2, "that item only")
    settle()
    T.eq(GetMoney(), 40000, "paid")

    ns = load({ money = 100, letters = { { sender = "Ysella Brightwind", subject = "Cloth", cod = 60000, items = { { name = "Runecloth", itemID = 14047 } } } } })
    MW.Open()
    frame(20)
    pick(ns, 1)
    T.truthy(button(ns, "Pay").spec.off, "Take can't pay")
    click(tileNamed(ns, "Runecloth")); click(tileNamed(ns, "Runecloth"))
    T.eq(#MW.Calls("TakeInboxItem") + #MW.Calls("AutoLootMailItem"), 0, "nothing asked of the client")
    T.truthy(stub.Text(tileNamed(ns, "Runecloth").sub):find("enough", 1, true), stub.Text(tileNamed(ns, "Runecloth").sub))
end)

T.test("inbox: the gold alone and a copy of the letter are taken from their own tiles, as the game's", function()
    local ns = load({ letters = {
        { sender = "Brannoc Ironhide", subject = "Ore", body = "Here is the ore, thanks!", money = 15000, items = { { name = "Copper Ore", itemID = 2770 } } },
    } })
    MW.Open()
    frame(20)
    pick(ns, 1)
    local gold = tileNamed(ns, DaylightUI.MoneyString(15000))
    T.truthy(gold, "a gold tile")
    click(gold)
    settle()
    T.eq(#MW.Calls("TakeInboxMoney"), 1)
    T.eq(#MW.Inbox()[1].items, 1, "the item stays")
    local copy = tileNamed(ns, "Letter")
    T.truthy(copy, "the letter as a tile")
    T.truthy(copy and hover(copy).text() ~= "", "it says what it does")
    click(copy)
    settle()
    T.eq(#MW.Calls("TakeInboxTextItem"), 1)
    T.isnil(tileNamed(ns, "Letter"), "taken once only")
end)

T.test("inbox: leaving a letter whose text was taken and nothing is left deletes it, as closing it does", function()
    local ns = load({ letters = {
        { sender = "Brannoc Ironhide", subject = "Hi", body = "Just a note." },
        { sender = "Thaxton Ashby", subject = "Hello", body = "Another." },
    } })
    MW.Open()
    frame(20)
    pick(ns, 1)
    click(tileNamed(ns, "Letter"))
    settle()
    pick(ns, 2)
    settle()
    T.eq(#MW.Calls("DeleteInboxItem"), 1)
    T.eq(#MW.Inbox(), 1)
    T.eq(MW.Inbox()[1].sender, "Thaxton Ashby")
    T.eq(ns.Inbox.Picked() and ns.Inbox.Picked().sender, "Thaxton Ashby", "the other letter stays picked")
end)

T.test("inbox: right-click a letter: Delete or Return and Report spam", function()
    local ns = load({ letters = { { sender = "Shady Goldseller", subject = "CHEAP GOLD", body = "visit..." },
        { sender = "Alliance Auction House", subject = "Auction expired: Linen Cloth", canReply = false, items = { { name = "Linen Cloth", itemID = 2589 } } } } })
    MW.Open()
    frame(20)
    local opened
    local was = DaylightUI.Widgets.OpenMenu
    DaylightUI.Widgets.OpenMenu = function(_, keys, values, _, onPick) opened = { keys = keys, values = values, pick = onPick } end
    local b = lines(ns)[1]
    b:GetScript("OnClick")(b, "RightButton")
    DaylightUI.Widgets.OpenMenu = was
    T.truthy(opened, "a menu")
    T.truthy(opened and table.concat(opened.keys, ","):find("report", 1, true), opened and table.concat(opened.keys, ","))
    if opened then opened.pick("report") end
    T.eq(#MW.Calls("Report"), 1)
    T.eq(MW.Calls("Report")[1] and MW.Calls("Report")[1][2], "Shady Goldseller")
    opened = nil
    DaylightUI.Widgets.OpenMenu = function(_, keys) opened = keys end
    b = lines(ns)[2]
    b:GetScript("OnClick")(b, "RightButton")
    DaylightUI.Widgets.OpenMenu = was
    T.falsy(table.concat(opened or {}, ","):find("report", 1, true), "an auction house letter can't be reported")
end)

T.test("reply: RE: once in front, the cursor in the letter, your own letter can't be answered, a sent reply goes back to the inbox", function()
    local ns = load({ letters = { { sender = "Brannoc Ironhide", subject = "RE: Ore" }, { sender = UnitName("player"), subject = "Note to self" } } })
    MW.Open()
    frame(20)
    pick(ns, 2)
    T.truthy(button(ns, "Reply").spec.off, "your own letter")
    pick(ns, 1)
    press(ns, "Reply")
    frame(10)
    local page = ns.Send.page
    T.eq(page.subject:GetText(), "RE: Ore", "never RE: RE:")
    T.truthy(page.body:HasFocus(), "the cursor in the letter")
    page.body:SetText("Thanks")
    sendPress(ns, "Send")
    settle()
    T.eq(ns.Window.frame.current, "inbox", "back to the inbox after a reply")
end)

T.test("send: Tab and Shift-Tab go round To, Subject, Letter and the coins; Enter moves on", function()
    local ns = load()
    MW.Open()
    frame(20)
    local page = sendPage(ns)
    local order = { page.to, page.subject, page.body, page.gold, page.silver, page.copper }
    for i, box in ipairs(order) do
        box:SetFocus()
        box:GetScript("OnTabPressed")(box)
        T.truthy(order[i % #order + 1]:HasFocus(), "Tab from box " .. i)
    end
    local was = _G.IsShiftKeyDown
    _G.IsShiftKeyDown = function() return true end
    page.subject:SetFocus()
    page.subject:GetScript("OnTabPressed")(page.subject)
    T.truthy(page.to:HasFocus(), "Shift-Tab goes back")
    page.to:GetScript("OnTabPressed")(page.to)
    T.truthy(page.copper:HasFocus(), "and round")
    _G.IsShiftKeyDown = was
    page.to:SetFocus()
    page.to:GetScript("OnEnterPressed")(page.to)
    T.truthy(page.subject:HasFocus(), "Enter in To: the subject")
    page.subject:GetScript("OnEnterPressed")(page.subject)
    T.truthy(page.body:HasFocus(), "Enter in the subject: the letter")
    T.eq(page.to.maxLetters, 77, "the game's name length")
end)

T.test("send: names complete in a list under To, Down and Enter pick one", function()
    local ns = load()
    ns.Send.Remember("Brannoc Ironhide")
    ns.Send.Remember("Bartholomew Stoneforge")
    MW.Open()
    frame(20)
    local page = sendPage(ns)
    T.truthy(page.complete, "a completion list on To")
    page.to:SetFocus()
    typeTo(page, "b")
    T.truthy(page.complete and page.complete:IsOpen(), "open while typing")
    page.to:GetScript("OnArrowPressed")(page.to, "DOWN")
    page.to:GetScript("OnEnterPressed")(page.to)
    T.eq(page.to:GetText(), "Brannoc Ironhide", "the second one")
end)

T.test("send: an attached item: left-click or drag picks it up, right-click puts it back; drop anywhere attaches", function()
    local ns = load({ money = 10000 })
    MW.Open()
    frame(20)
    local page = sendPage(ns)
    MW.Cursor({ name = "Linen Cloth", itemID = 2589, count = 20 })
    local win = ns.Window.frame
    local drop = win:GetScript("OnReceiveDrag")
    T.truthy(drop, "the window takes a drop")
    if drop then drop(win) end
    frame(2)
    T.eq(#ns.Send.Items(), 1, "dropped on the page")
    MW.Cursor({ name = "Wool Cloth", itemID = 2592 })
    local up = page.body:GetScript("OnMouseUp")
    if up then up(page.body, "LeftButton") end
    frame(2)
    T.eq(#ns.Send.Items(), 2, "clicked on the letter with one held")
    local t = tilesOf(page)[1]
    T.truthy(stub.Text(t.sub):find("Right", 1, true), stub.Text(t.sub))
    click(t, "LeftButton")
    frame(2)
    T.eq(MW.CursorItem() and MW.CursorItem().name, "Linen Cloth", "picked up onto the cursor")
    T.eq(#ns.Send.Items(), 1)
    if drop then drop(win) end
    frame(2)
    t = tilesOf(page)[1]
    t:GetScript("OnDragStart")(t)
    T.truthy(MW.CursorItem(), "dragged out")
    if drop then drop(win) end
    frame(2)
    click(tilesOf(page)[1], "RightButton")
    frame(2)
    T.eq(#ns.Send.Items(), 1, "right-click: back to the bags")
    T.isnil(MW.CursorItem())
end)

T.test("send: gold picked up from the bags drops into the coin boxes", function()
    local ns = load({ money = 100000 })
    MW.Open()
    frame(20)
    local page = sendPage(ns)
    page.silver:SetText("5")
    MW.CursorMoney(30000)
    local up = page.gold:GetScript("OnMouseUp")
    T.truthy(up, "the box takes a click")
    if up then up(page.gold, "LeftButton") end
    T.eq(page.gold:GetText(), "3")
    T.eq(page.silver:GetText(), "5", "added to what was there")
    T.eq(GetCursorMoney(), 0, "the cursor let go")
end)

T.test("send: the subject fills with the first item and its count, and clears when it's taken off", function()
    local ns = load({ money = 10000 })
    MW.Open()
    frame(20)
    local page = sendPage(ns)
    MW.Cursor({ name = "Linen Cloth", itemID = 2589, count = 20 })
    emptySlot(page):GetScript("OnReceiveDrag")(emptySlot(page))
    frame(2)
    T.eq(page.subject:GetText(), "Linen Cloth (20)")
    click(tilesOf(page)[1], "RightButton")
    frame(2)
    T.eq(page.subject:GetText(), "", "cleared with it")
    page.subject:SetText("For you")
    MW.Cursor({ name = "Wool Cloth", itemID = 2592 })
    emptySlot(page):GetScript("OnReceiveDrag")(emptySlot(page))
    frame(2)
    T.eq(page.subject:GetText(), "For you", "a typed subject stays")
end)

T.test("send: COD only with an item, off when the realm turns it off, at most 10000 gold; postage red when short", function()
    local ns = load({ money = 10 })
    MW.Open()
    frame(20)
    local page = sendPage(ns)
    T.truthy(page.cod.off, "no item: no COD")
    T.truthy(page.postage:GetText():find(DaylightUI.Win.Parts.Hex(DaylightUI.Style.INK.BAD), 1, true), "postage more than you have: " .. page.postage:GetText())
    MW.Cursor({ name = "Linen Cloth", itemID = 2589 })
    emptySlot(page):GetScript("OnReceiveDrag")(emptySlot(page))
    frame(2)
    T.falsy(page.cod.off, "an item: COD")
    click(page.cod)
    T.truthy(ns.Send.state.cod)
    page.to:SetText("Shooty McGoovy")
    page.gold:SetText("10001")
    sendPress(ns, "Send")
    T.eq(#MW.Calls("SendMail"), 0, "over the cap")
    T.truthy(stub.Text(page.said):find("10000", 1, true), stub.Text(page.said))
    click(tilesOf(page)[1], "RightButton")
    frame(2)
    T.falsy(ns.Send.state.cod, "the item gone: COD off again")

    ns = load({ codOff = true })
    MW.Open()
    frame(20)
    page = sendPage(ns)
    MW.Cursor({ name = "Linen Cloth", itemID = 2589 })
    emptySlot(page):GetScript("OnReceiveDrag")(emptySlot(page))
    frame(2)
    T.truthy(page.cod.off, "COD turned off by the realm")
    local said
    local was = DaylightUI.Widgets.Tooltip
    DaylightUI.Widgets.Tooltip = function(_, text) said = text end
    page.cod:GetScript("OnEnter")(page.cod)
    DaylightUI.Widgets.Tooltip = was
    T.truthy(said, "and says why")
end)

T.test("send: a sent letter clears To too and puts the cursor there, as the game's", function()
    local ns = load({ money = 10000 })
    MW.Open()
    frame(20)
    local page = sendPage(ns)
    page.to:SetText("Shooty McGoovy")
    page.subject:SetText("Hi")
    sendPress(ns, "Send")
    settle()
    T.eq(#MW.Sent(), 1)
    T.eq(page.to:GetText(), "")
    T.truthy(page.to:HasFocus())
end)

T.test("mailbox on a trial account: no sending", function()
    local ns = load({ trial = true })
    MW.Open()
    frame(20)
    local send
    for _, b in ipairs(ns.Window.frame.tabs) do if b.id == "send" then send = b end end
    T.truthy(send.off, "the Send tab is off")
end)
