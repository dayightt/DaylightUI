-- The My auctions tab: what you have up, sold ones included, each saying
-- whether someone sells it for less, and one click per cancel.
--
-- Reading: the owned list (ns.Post.Owned, read as the Auction House opens and
-- again when one sells or gets a bid), then each item still up searched once
-- (ns.Search.Item, its first page: the cheapest are on it), one at a time,
-- never while the player is clicking (QUIET): the AH has one line for requests
-- and a cancel needs it free. A search Sell made a moment ago is used as it is.
-- "Check again" reads both again. Nothing is asked while the tab is hidden.
--
-- Cancel acts on the picked row only, so the row shown is the row canceled.
-- The first undercut row is picked for you; a canceled row slides out and
-- the next undercut one is picked. An auction the game won't cancel (a bid) says so.
--
--   ns.AuctionsPage.Build(page), .Fill(), .Key()   the window's page hooks
--   ns.AuctionsPage.Rows() -> every row built, in the list's order
--   ns.AuctionsPage.StatusOf(row) -> status id, words, ink role

local _, ns = ...
local DUI = DaylightUI
local L = ns.L
local Style = DUI.Style
local W = DUI.Widgets
local Motion = DUI.Motion
local Parts = DUI.Win.Parts

local A = {}
ns.AuctionsPage = A

A.TITLE_TOP = 14
A.META_TOP = 36
A.CHIPS_TOP = 60
A.TABLE_TOP = 96
A.FOOT = 52
A.ICON_W = 30
A.HINT_GAP = 12
A.BID_W = 110       -- the bid amount box
A.SEARCH_W = 220    -- the search box beside the chips
A.COLS = {
    { id = "icon", text = "", width = A.ICON_W },
    { id = "name", text = L["Item"], fill = true, sort = true },
    { id = "qty", text = L["Qty"], width = 46, justify = "RIGHT", sort = true },
    { id = "unit", text = L["Yours"], width = 100, justify = "RIGHT", sort = true },
    { id = "bid", text = L["Bid"], width = 92, justify = "RIGHT", sort = true },
    { id = "lowest", text = L["Lowest other"], width = 100, justify = "RIGHT", sort = true },
    { id = "left", text = L["Left"], width = 44, justify = "RIGHT", sort = true },
    { id = "status", text = L["Status"], width = 170, sort = true },
}
A.FILTERS = {
    { id = "all", text = L["All"] },
    { id = "undercut", text = L["Undercut"] },
    { id = "sold", text = L["Sold"] },
    { id = "bids", text = L["Bids"] },
}
A.QUIET = 4         -- seconds the background checks wait after a click on the page
A.GAP = 0.2         -- seconds between two checks
A.FRESH = 120       -- seconds another page's search of an item stands in for a check
A.SHORT = 7200      -- seconds left under which the time shows as running low
A.AGE_TICK = 60     -- seconds between repaints of "checked 4 min ago"

-- Sorted by what needs doing: undercut first, sold last.
local RANK = { outbid = 1, undercut = 1, high = 6, lowest = 2, few = 2, checking = 3, failed = 3, bidonly = 4, bid = 5, alone = 6, sold = 7 }
local DASH = "\226\128\148"

A.filter = "all"
A.sort = { id = "status", desc = false }   -- status = what needs doing first
A.picked = nil       -- auctionID
A.checked = {}       -- itemID -> { at (GetTime), auctions } or { at, err }
A.readAt = nil       -- when the owned list was last read (GetTime)

local page
local rows = {}
local checking, waking = nil, false
local quietUntil = 0
local busy = false        -- a cancel is out
local moving = false      -- a row or a why is easing shut: paints wait for it
local whyFor = nil        -- the auctionID whose why is open in the table
local ticker = nil

local function hush() quietUntil = GetTime() + A.QUIET end

local function money(c, plain) return W.Money(c, { pad = true, color = not plain }) end
local function value(text) return Parts.Hex(Style.INK.VALUE) .. tostring(text) .. "|r" end
local function pop(text) return Parts.Hex({ Style.Pop() }) .. text .. "|r" end

-- The game gives a bid's time left only as a band.
local BAND = { [0] = L["<30 min"], [1] = L["<2 h"], [2] = L["<12 h"], [3] = L["<48 h"] }

local function leftText(s)
    if type(s) ~= "number" then return DASH end
    if s >= 3600 then return string.format(L["%d h"], math.floor(s / 3600 + 0.5)) end
    return string.format(L["%d min"], math.max(1, math.floor(s / 60 + 0.5)))
end

local function agoText(at)
    local s = GetTime() - (at or GetTime())
    if s < 60 then return L["just now"] end
    return string.format(L["%s ago"], ns.Ago(s))
end

-- The cheapest price another seller asks for it, and how many they put up at
-- that price. Your own and your other characters' are left out: posting never
-- undercuts them. Gear compares only the same item (its suffix too).
-- cheaper: how many of theirs are under yours, for the leeway setting.
local function lowestOther(o, auctions)
    local low, qty, cheaper = nil, nil, 0
    for _, a in ipairs(auctions or {}) do
        local n = (tonumber(a.qty) or 0) - (tonumber(a.own) or 0) - (tonumber(a.acct) or 0)
        if n > 0 and type(a.unit) == "number" and a.unit >= 1 and (a.key == nil or o.key == nil or a.key == o.key) then
            if not low or a.unit < low then low, qty = a.unit, n
            elseif a.unit == low then qty = qty + n end
            if type(o.unit) == "number" and a.unit < o.unit then cheaper = cheaper + n end
        end
    end
    return low, qty, cheaper
end

-- The cheaper items from others My auctions lets pass (the options).
local function leeway()
    local n = ns.Setting and ns.Setting("undercutAhead")
    return type(n) == "number" and n or 0
end

-- What it cost to put up, lost when it's canceled. The game says it for a
-- commodity from the item alone; an auction with more than 8 hours left was
-- posted for 24. Nil when that can't be known (gear needs the item in the bags).
local function depositOf(r)
    if r.commodity ~= true then return nil end
    return ns.Post.PaidDeposit(r.itemID, r.qty, r.left)
end

-- ---------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------

-- A bid locks the auction only when the game says so: its own window offers
-- Cancel on any auction that isn't sold, so the client is asked
-- (CanCancelAuction). Without that call a bid is taken to lock it.
local function bidLocks(r)
    if (r.bid or 0) <= 0 then return false end
    local api = C_AuctionHouse
    if api and api.CanCancelAuction and type(r.auctionID) == "number" then
        return api.CanCancelAuction(r.auctionID) ~= true
    end
    return true
end

local function statusOf(r)
    if r.isBid then
        if r.high then return "high", L["You're the highest bidder"], "GOOD" end
        return "outbid", L["Outbid"], "WARN"
    end
    if r.sold then return "sold", L["Sold: in your mailbox"], "GOOD" end
    if bidLocks(r) then return "bid", L["Has a bid: can't cancel"], "LABEL" end
    local c = A.checked[r.itemID]
    if not c then return "checking", L["Checking the price..."], "LABEL" end
    if c.err then return "failed", L["Couldn't check the price"], "WARN" end
    if not r.lowest then return "alone", L["No one else selling"], "LABEL" end
    if type(r.unit) ~= "number" then return "bidonly", L["No buyout to compare"], "LABEL" end
    if r.lowest < r.unit and (r.cheaper or 1) > leeway() then
        return "undercut", string.format(L["Undercut by %s"], money(r.unit - r.lowest, true)), "WARN"
    elseif r.lowest < r.unit then
        return "few", string.format(L["%d cheaper, left up"], r.cheaper or 0), "LABEL"
    end
    return "lowest", L["You're the lowest"], "GOOD"
end
A.StatusOf = function(r) return statusOf(r) end

local function build()
    rows = {}
    for _, o in ipairs(ns.Post.Mine()) do
        local info = ns.Items.Info(o.itemID)
        local c = A.checked[o.itemID]
        local r = {
            kind = "line", auctionID = o.auctionID, key = o.key, itemID = o.itemID, qty = o.qty, unit = o.unit,
            buyout = o.buyout, sold = o.sold, left = o.left, bid = o.bid,
            name = (info and ns.Items.KeyName(o.key, info.name)) or string.format(L["Item %d"], o.itemID or 0),
            icon = info and info.icon, quality = info and info.quality,
        }
        if c and c.auctions then
            r.lowest, r.lowQty, r.cheaper = lowestOther(o, c.auctions)
            r.commodity = c.auctions.commodity
            r.at = c.at
        end
        r.status, r.text, r.role = statusOf(r)
        rows[#rows + 1] = r
    end
    for _, o in ipairs(ns.Post.MyBids()) do
        local info = ns.Items.Info(o.itemID)
        local r = {
            kind = "line", isBid = true, auctionID = o.auctionID, key = o.key, itemID = o.itemID, qty = 1,
            unit = o.buyout, buyout = o.buyout, bid = o.bid, minBid = o.minBid, band = o.band, high = o.high,
            name = (info and ns.Items.KeyName(o.key, info.name)) or string.format(L["Item %d"], o.itemID or 0),
            icon = info and info.icon, quality = info and info.quality,
        }
        r.status, r.text, r.role = statusOf(r)
        rows[#rows + 1] = r
    end
    A.SortRows(rows)
end

-- By the picked column; an empty cell goes last either way, then what
-- needs doing first, then by name.
function A.SortRows(list)
    local id, desc = A.sort.id, A.sort.desc
    local function value(r)
        if id == "status" then return RANK[r.status] or 9 end
        if id == "bid" then return (r.bid or 0) > 0 and r.bid or nil end
        if id == "left" and r.sold then return nil end
        return r[id]
    end
    table.sort(list, function(a, b)
        local x, y = value(a), value(b)
        if x ~= y then
            if x == nil then return false end
            if y == nil then return true end
            if desc then return x > y end
            return x < y
        end
        local ra, rb = RANK[a.status] or 9, RANK[b.status] or 9
        if ra ~= rb then return ra < rb end
        if a.name ~= b.name then return a.name < b.name end
        return a.auctionID < b.auctionID
    end)
end

-- The words in the search box, lower case ("" shows everything).
A.words = ""

local function passes(r, filter)
    if A.words ~= "" and not string.find(string.lower(r.name or ""), A.words, 1, true) then return false end
    filter = filter or A.filter
    if filter == "undercut" then return r.status == "undercut" end
    if filter == "bids" then return r.isBid == true end
    if r.isBid then return false end
    if filter == "sold" then return r.sold == true end
    return true
end

function A.Rows() return rows end

local function rowOf(id)
    if not id then return nil end
    for _, r in ipairs(rows) do
        if r.auctionID == id and passes(r) then return r end
    end
end

-- Only an auction still up, and not locked by a bid, can be canceled.
local function cancellable(r)
    return r ~= nil and not r.isBid and not r.sold and not bidLocks(r)
end

-- The words under the picked row: what its status means and what to do.
local function whyOf(r)
    if r.status == "high" then
        return string.format(L["Your bid of %s is the highest. It's yours when its time runs out, unless someone bids more or buys it out."],
            money(r.bid))
    elseif r.status == "outbid" then
        local out = string.format(L["Someone bid %s, more than you. Bid at least %s to win it back."], money(r.bid), money(r.minBid))
        if r.buyout then out = out .. " " .. string.format(L["Or buy it out for %s."], money(r.buyout)) end
        return out
    end
    local when = agoText(r.at)
    if r.status == "undercut" then
        local dep = depositOf(r)
        local back = dep and string.format(L["The items come back by mail; the deposit (%s) isn't refunded."], money(dep))
            or L["The items come back by mail; the deposit isn't refunded."]
        local cost = ns.Post.CancelCost(r.auctionID)
        if cost > 0 then back = back .. " " .. string.format(L["Canceling costs %s."], money(cost)) end
        return string.format(L["Someone put up %s at %s (checked %s), %s under yours. Cancel it and post again from Sell to be the cheapest."],
            value(r.lowQty), money(r.lowest), when, money(r.unit - r.lowest)) .. " " .. back
    elseif r.status == "few" then
        return string.format(L["Only %s from others are cheaper than yours (checked %s), within what you let pass in the options. It stays up."],
            value(r.cheaper or 0), when)
    elseif r.status == "lowest" then
        return string.format(L["Yours is the cheapest. The next one is %s at %s (checked %s): nothing to do."],
            value(r.lowQty), money(r.lowest), when)
    elseif r.status == "alone" then
        return string.format(L["No one else is selling it (checked %s). It stays up as it is."], when)
    elseif r.status == "bid" then
        return string.format(L["Someone bid %s on it. An auction with a bid can't be canceled: it goes to the highest bid when its time runs out, or sooner to anyone who pays your buyout."],
            money(r.bid))
    elseif r.status == "sold" then
        return string.format(L["Sold for %s. The gold is waiting in your mailbox, less the Auction House's cut."], money(r.buyout or 0))
    elseif r.status == "failed" then
        return L["Couldn't read its price just now. Check again to try once more."]
    elseif r.status == "bidonly" then
        return L["It has a starting bid but no buyout, so there's no price to compare."]
    end
    return L["Checking who else is selling it..."]
end

-- ---------------------------------------------------------------------
-- Reading and checking
-- ---------------------------------------------------------------------

local queued = false
local function refresh()
    if queued or not page then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        if page:IsVisible() then A.Paint() end
    end)
end

local function visible() return page ~= nil and page:IsVisible() end

function A.CheckNext()
    if checking or not ns.AH.IsOpen() or not visible() then return end
    local want
    for _, o in ipairs(ns.Post.Mine()) do
        if not o.sold and type(o.itemID) == "number" and not A.checked[o.itemID] then want = o.itemID; break end
    end
    if not want then return end
    local wait = quietUntil - GetTime()
    if wait > 0 then   -- the player is at it: their click comes first
        if not waking then
            waking = true
            C_Timer.After(wait, function() waking = false; A.CheckNext() end)
        end
        return
    end
    -- Sell searched it a moment ago (and not before a "Check again"): that answer will do
    local _, last, age = ns.Search.Last(want)
    if last and age <= A.FRESH and GetTime() - age >= (A.forcedAt or 0) then
        A.checked[want] = { at = GetTime() - age, auctions = last }
        refresh()
        return C_Timer.After(0, A.CheckNext)
    end
    checking = want
    ns.Search.Item(want, function(found, reason, auctions)
        if checking == want then checking = nil end
        if reason == "closed" then return end
        if reason ~= "dropped" then
            A.checked[want] = found and { at = GetTime(), auctions = auctions or {} } or { at = GetTime(), err = reason or "error" }
            refresh()
        end
        C_Timer.After(A.GAP, A.CheckNext)
    end, { pages = 1 })
end

-- force: "Check again", everything asked afresh. Without it the owned list read
-- as the Auction House opened is used.
function A.Read(force)
    A.checked = {}
    if force then A.forcedAt = GetTime() end
    local function bids()
        ns.Post.Bids(function()
            refresh()
            C_Timer.After(0, A.CheckNext)
        end)
    end
    local at = ns.Post.ReadAt()
    if at and not force then
        A.readAt = at
        bids()
        return A.Paint()
    end
    ns.Post.Owned(function(list)
        if list then A.readAt = GetTime() end
        refresh()
        bids()
    end)
    A.Paint()
end

-- ---------------------------------------------------------------------
-- Canceling
-- ---------------------------------------------------------------------

local SAYS = {
    closed = L["Open the Auction House to cancel."],
    busy = L["The Auction House is still answering. Click again in a moment."],
    late = L["Still waiting for the game's answer to your last click. Try again in a moment."],
    throttled = L["The Auction House is still answering. Try again in a moment."],
    notmine = L["That auction isn't in your list anymore. Check again."],
    failed = L["The game said no to that cancel."],
    timeout = L["No answer from the game. Check again before you cancel it again."],
    error = L["Something went wrong canceling it."],
}

function A.Say(text, role)
    if not page then return end
    page.stat:SetText(text or "")
    Style.InkText(page.stat, role or "LABEL")
    if text and page.stat:IsVisible() then Motion.Fade(page.stat, 0, 1, Motion.FAST) end
end

-- The picked row and its why slide shut, then the list is painted without
-- it and the next undercut one is picked.
local function leave(r)
    local t = page.table
    local at
    for i, d in ipairs(t.rows) do
        if d.kind == "line" and d.auctionID == r.auctionID then at = i; break end
    end
    A.picked, whyFor = nil, nil
    if not at or not visible() then return A.Paint() end
    local n = (t.rows[at + 1] and t.rows[at + 1].kind == "why") and 2 or 1
    moving = true
    t:Close(at - 1, n, function()
        moving = false
        A.Paint()
    end)
end

function A.Cancel()
    if busy then return end
    hush()
    local r = rowOf(A.picked)
    if not cancellable(r) then return end
    -- a cancel that costs gold asks once, naming the cost
    local cost = ns.Post.CancelCost(r.auctionID)
    if cost > 0 and A.costAsked ~= r.auctionID then
        A.costAsked = r.auctionID
        A.Say(string.format(L["Canceling it costs %s. Click Cancel again to cancel it."], money(cost)), "WARN")
        return A.Paint()
    end
    A.costAsked = nil
    local over = false   -- it can end inside the click: ns.AH.Act still says true then
    local ok, why = ns.Post.Cancel(r.auctionID, function(done, reason, said)
        busy, over = false, true
        if done then
            A.Say(string.format(L["Canceled %s %s: the items come back by mail."], r.qty, r.name), "GOOD")
            leave(r)
            return
        end
        A.Say(reason == "failed" and said and string.format(L["The game said no to that cancel: %s."], said)
            or SAYS[reason] or SAYS.error, "WARN")
        A.Paint()
    end)
    if ok then
        busy = not over
    else
        A.Say(SAYS[why] or SAYS.error, "WARN")
    end
    if not over then A.Paint() end
end

-- The amount in the bid box, or the least the next bid can be.
local function bidAmount(r)
    local text = page.bidBox and page.bidBox:GetText() or ""
    if text == "" then return r.minBid end
    return ns.SellPage.ReadMoney(text, ns.SellPage.TopCoin(r.minBid))
end

local BID_SAYS = {
    gold = L["Not enough gold."],
    buyout = L["That's the buyout or more: buy it out instead."],
    busy = SAYS.late, throttled = SAYS.throttled, closed = SAYS.closed, timeout = SAYS.timeout,
    failed = L["Someone else bid more, or it sold. Check again."],
}

-- After a bid or buyout the bids are read again, so the list says where you stand.
local function bidDone(done, reason, said, words)
    busy = false
    if done then A.Say(words, "GOOD")
    else A.Say(said or BID_SAYS[reason] or SAYS.error, "WARN") end
    if ns.AH.IsOpen() then ns.Post.Bids(refresh) end
    A.Paint()
end

function A.PlaceBid()
    if busy then return end
    hush()
    local r = rowOf(A.picked)
    if not (r and r.isBid) then return end
    local amount = bidAmount(r)
    if type(amount) ~= "number" or amount < (r.minBid or 0) then
        return A.Say(string.format(L["Bid at least %s."], money(r.minBid or 0)), "WARN")
    end
    local ok, why = ns.Buy.Bid(r.auctionID, amount, r.buyout or 0, function(done, reason, said)
        bidDone(done, reason, said, string.format(L["Bid %s on %s."], money(amount), r.name))
    end)
    if ok then busy = true else A.Say(BID_SAYS[why] or SAYS.error, "WARN") end
    A.Paint()
end

function A.BuyOut()
    if busy then return end
    hush()
    local r = rowOf(A.picked)
    if not (r and r.isBid and r.buyout) then return end
    local ok, why = ns.Buy.Item(r.auctionID, r.buyout, function(done, reason, said)
        bidDone(done, reason, said, string.format(L["Bought %s for %s: it's in your mailbox."], r.name, money(r.buyout)))
    end)
    if ok then busy = true else A.Say(BID_SAYS[why] or SAYS.error, "WARN") end
    A.Paint()
end

-- A click on a row picks it; its why glides open under it.
function A.Pick(id)
    hush()
    if id == A.picked then return end
    A.picked = id
    local r = rowOf(id)
    if page.bidBox then page.bidBox:SetText(r and r.isBid and ns.SellPage.PlainMoney(r.minBid or 0) or "") end
    A.Paint()
end

-- ---------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------

local function place(b, fs, cols, id)
    local c = cols[id]
    fs:ClearAllPoints()
    if not c then return fs:Hide() end
    if id == "status" then fs:SetPoint("LEFT", b, "LEFT", c.x, 0)
    else fs:SetPoint("RIGHT", b, "LEFT", c.x + c.w, 0) end
    fs:SetWidth(math.max(1, c.w))
    fs:Show()
end

local CELLS = { "qty", "unit", "bid", "lowest", "left", "status" }

local function fillLine(b, d, cols)
    local icon, name = cols.icon, cols.name
    b.edge:ClearAllPoints()
    b.edge:SetPoint("LEFT", b, "LEFT", (icon and icon.x or 0) + 1, 0)
    Parts.SetItemIcon(b, d.icon, d.quality)
    b.name:ClearAllPoints()
    b.name:SetPoint("LEFT", b, "LEFT", name and name.x or A.ICON_W, 0)
    b.name:SetWidth(math.max(1, name and name.w or 100))
    b.name:SetText(d.name)
    b.name:SetTextColor(Parts.QualityColor(d.quality))
    for _, id in ipairs(CELLS) do place(b, b.cells[id], cols, id) end
    b.cells.qty:SetText(tostring(d.qty))
    Style.InkText(b.cells.qty, "pop")
    b.cells.unit:SetText(d.unit and money(d.unit) or DASH)
    Style.InkText(b.cells.unit, d.unit and "VALUE" or "LABEL")
    local bid = (d.bid or 0) > 0 and d.bid or nil
    b.cells.bid:SetText(bid and money(bid) or DASH)
    Style.InkText(b.cells.bid, bid and "VALUE" or "LABEL")
    b.cells.lowest:SetText(d.lowest and money(d.lowest) or DASH)
    Style.InkText(b.cells.lowest, d.lowest and "VALUE" or "LABEL")
    if d.isBid then
        b.cells.left:SetText(BAND[d.band] or DASH)
        Style.InkText(b.cells.left, (d.band == 0 or d.band == 1) and "WARN" or "LABEL")
    else
        b.cells.left:SetText(d.sold and DASH or leftText(d.left))
        Style.InkText(b.cells.left, (not d.sold and type(d.left) == "number" and d.left < A.SHORT) and "WARN" or "LABEL")
    end
    b.cells.status:SetText(d.text or "")
    Style.InkText(b.cells.status, d.role or "LABEL")
end

local function makeLine(b)
    Parts.ItemIcon(b, Parts.LINE_ICON)
    b.name = Style.Text(b, Style.SIZE.body, "LEFT")
    b.name:SetWordWrap(false)
    b.cells = {}
    for _, id in ipairs(CELLS) do
        local fs = Style.Text(b, id == "status" and Style.SIZE.small or Style.SIZE.body, id == "status" and "LEFT" or "RIGHT")
        fs:SetWordWrap(false)
        b.cells[id] = fs
    end
end

local function paintHead()
    if not A.readAt then
        page.title:SetText(L["My auctions"])
        page.meta:SetText(ns.AH.IsOpen() and L["Reading your auctions..."] or "")
        return
    end
    local up, worth, sold, soldWorth = 0, 0, 0, 0
    for _, r in ipairs(rows) do
        if r.isBid then
            -- a bid isn't yours to sell
        elseif r.sold then sold, soldWorth = sold + 1, soldWorth + (r.buyout or 0)
        else up, worth = up + 1, worth + (r.buyout or 0) end
    end
    page.title:SetText(string.format(up == 1 and L["%d auction up"] or L["%d auctions up"], up))
    local meta = { string.format(L["%s at your prices"], money(worth)) }
    if sold > 0 then
        meta[#meta + 1] = Parts.Hex(Style.INK.GOOD) .. string.format(L["%d sold"], sold) .. "|r: "
            .. string.format(L["%s waiting in your mailbox"], money(soldWorth))
    end
    local oldest = A.readAt
    for _, c in pairs(A.checked) do if c.at < oldest then oldest = c.at end end
    meta[#meta + 1] = string.format(L["checked %s"], agoText(oldest))
    page.meta:SetText(table.concat(meta, ns.Window and ns.Window.SEP or "  "))
end

local function paintChips()
    local n = { all = 0, undercut = 0, sold = 0, bids = 0 }
    for _, r in ipairs(rows) do
        for _, f in ipairs(A.FILTERS) do
            if passes(r, f.id) then n[f.id] = n[f.id] + 1 end
        end
    end
    local x = 0
    for _, f in ipairs(A.FILTERS) do
        local chip = page.chips[f.id]
        chip.text:SetText(string.format("%s %d", f.text, n[f.id]))
        chip.FitWidth()
        chip.SetOn(A.filter == f.id)
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", page.body, "TOPLEFT", Parts.EDGE + x, -A.CHIPS_TOP)
        x = x + chip:GetWidth() + W.CHIP_GAP
    end
end

-- A bid's footer: Bid (the amount in the box, the least next bid to start)
-- and Buy out when it has a buyout.
local function paintBidFooter(r)
    local open = ns.AH.IsOpen()
    local can = open and ns.AH.CanAct()
    local list = { { text = busy and L["Bidding..."] or L["Bid"], primary = true, off = busy or not can,
        onClick = function() A.PlaceBid() end } }
    if r.buyout then
        list[2] = { text = string.format(L["Buy out %s"], money(r.buyout, true)), beside = true, off = busy or not can,
            onClick = function() A.BuyOut() end }
    end
    page.foot:Set(list)
    page.bidBox:ClearAllPoints()
    page.bidBox:SetPoint("LEFT", page.foot.buttons[#list], "RIGHT", A.HINT_GAP, 0)
    W.EaseShown(page.bidBox, true)
    page.hint:SetText("")
end

local function paintFooter()
    local r = rowOf(A.picked)
    if r and r.isBid then return paintBidFooter(r) end
    W.EaseShown(page.bidBox, false)
    local label, hint = L["Cancel"], ""
    if busy then
        label = L["Canceling..."]
    elseif r then
        label = string.format(L["Cancel %s"], r.name)
        if r.sold then hint = L["Sold: nothing to cancel."]
        elseif bidLocks(r) then hint = L["It has a bid, so it can't be canceled."]
        else
            local key = GetBindingKey and GetBindingKey("DAYLIGHTUI_AH_ACT")
            if type(key) == "string" and key ~= "" then hint = string.format(L["or press %s"], pop(key)) end
        end
    elseif #rows > 0 then
        hint = L["Pick an auction to cancel it."]
    end
    if not busy and r and A.costAsked == r.auctionID then
        label = string.format(L["Cancel for %s"], money(ns.Post.CancelCost(r.auctionID), true))
    end
    -- off while a click would be refused (a check out on the line): back on when it's free
    page.foot:Set({ { text = label, primary = true, off = busy or not cancellable(r) or not ns.AH.CanAct(),
        onClick = function() A.Cancel() end } })
    page.hint:ClearAllPoints()
    page.hint:SetPoint("LEFT", page.foot.buttons[1], "RIGHT", A.HINT_GAP, 0)
    page.hint:SetText(hint)
end

-- The list as it stands: the rows the filter shows, the picked one's why
-- under it (glides open when the pick is new; an old one glides shut first).
function A.Paint()
    if not page then return end
    if moving then return end   -- the easing's end paints
    build()
    paintHead()
    paintChips()
    -- on Bids that column is the auction's buyout, not your price
    page.table.head.cells.unit.text:SetText(A.filter == "bids" and L["Buyout"] or L["Yours"])
    if not busy and not rowOf(A.picked) then
        A.picked = nil
        for _, r in ipairs(rows) do
            if r.status == "undercut" and passes(r) then A.picked = r.auctionID; break end
        end
    end
    paintFooter()
    local t = page.table
    -- the why open for another row slides shut before the new one opens
    if whyFor and whyFor ~= A.picked and visible() and Motion.On() then
        for i, d in ipairs(t.rows) do
            if d.kind == "why" then
                local next
                for j, e in ipairs(t.rows) do
                    if e.kind == "line" and e.auctionID == A.picked then next = j end
                end
                t:Pick(next)
                whyFor = nil
                moving = true
                t:Close(i - 1, 1, function()
                    moving = false
                    A.Paint()
                end)
                return
            end
        end
    end
    local shown, at, why = {}, nil, nil
    for _, r in ipairs(rows) do
        if passes(r) then
            shown[#shown + 1] = r
            if r.auctionID == A.picked then
                at = #shown
                shown[#shown + 1] = { kind = "why", text = whyOf(r) }
                why = #shown
            end
        end
    end
    t:SetRows(shown, true)
    t:Pick(at)
    if why and whyFor ~= A.picked and visible() then t:Open(why - 1, 1) end
    whyFor = why and A.picked or nil
    page.empty:SetText(not A.readAt and (ns.AH.IsOpen() and L["Reading your auctions..."] or L["Open the Auction House to see your auctions."])
        or #rows == 0 and L["No auctions up."] or L["No auctions match."])
    W.EaseShown(page.empty, #shown == 0)
end

-- ---------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------

function A.Build(p)
    page = p
    A.page = p
    local body = CreateFrame("Frame", nil, p)
    body:SetAllPoints(p)
    page.body = body
    page.title = Style.Text(body, Style.SIZE.head, "LEFT")
    Style.InkText(page.title, "VALUE")
    page.title:SetPoint("TOPLEFT", body, "TOPLEFT", Parts.EDGE, -A.TITLE_TOP)
    page.meta = Style.Text(body, Style.SIZE.small, "LEFT")
    Style.InkText(page.meta, "LABEL")
    page.meta:SetPoint("TOPLEFT", body, "TOPLEFT", Parts.EDGE, -A.META_TOP)
    page.meta:SetPoint("RIGHT", body, "RIGHT", -Parts.EDGE, 0)
    page.meta:SetWordWrap(false)
    page.chips = {}
    for _, f in ipairs(A.FILTERS) do
        local chip = W.Chip(body, f.text)
        chip.FitWidth()
        chip:SetScript("OnClick", function()
            hush()
            A.filter = f.id
            A.Paint()
        end)
        page.chips[f.id] = chip
    end
    page.search = W.Input(body, { search = true, hint = L["Find an auction"], onChange = function(text)
        hush()
        A.words = string.lower((tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")))
        A.Paint()
    end })
    page.search:SetWidth(A.SEARCH_W)
    page.search:SetPoint("TOPRIGHT", body, "TOPRIGHT", -Parts.EDGE, -A.CHIPS_TOP)
    page.table = Parts.Table(body, {
        head = A.COLS, top = A.TABLE_TOP, bottom = A.FOOT,
        rowHeight = { line = Parts.LINE },
        make = { line = makeLine },
        fill = { line = fillLine },
        link = ns.Items.RowLink,
        onSort = function(id, desc)
            hush()
            A.sort.id, A.sort.desc = id, desc
            A.Paint()
        end,
        onClick = function(_, d)
            if d.kind == "line" then A.Pick(d.auctionID) end
        end,
        onEnter = function(b, d)
            if d.kind ~= "line" or not GameTooltip then return end
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            ns.Items.SetTip(GameTooltip, d.key, d.itemID)
            GameTooltip:Show()
        end,
        onLeave = function(b)
            if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(b) then GameTooltip:Hide() end
        end,
    })
    page.table.head:SetSort(A.sort.id, A.sort.desc)
    page.empty = Style.Text(body, Style.SIZE.body, "CENTER")
    Style.InkText(page.empty, "LABEL")
    page.empty:SetPoint("CENTER", page.table.view, "CENTER", 0, 0)
    page.foot = Parts.Footer(body)
    page.bidBox = W.Input(page.foot.frame, { justify = "RIGHT", hint = ns.SellPage.PlainMoney(12000) })
    page.bidBox:SetWidth(A.BID_W)
    W.PadNumber(page.bidBox, function(dir)
        local r = rowOf(A.picked)
        if not (r and r.isBid) then return end
        local c = ns.SellPage.ReadMoney(page.bidBox:GetText(), ns.SellPage.TopCoin(r.minBid)) or r.minBid or 0
        page.bidBox:SetText(ns.SellPage.PlainMoney(ns.SellPage.StepMoney(c, dir, r.minBid or 1)))
    end)
    page.bidBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        A.PlaceBid()
    end)
    page.bidBox:Hide()
    page.hint = Style.Text(page.foot.frame, Style.SIZE.small, "LEFT")
    Style.InkText(page.hint, "LABEL")
    page.hint:SetWordWrap(false)
    page.again = W.Link(page.foot.frame, Style.SIZE.small)
    page.again.SetLabel(L["Check again"])
    page.again:SetPoint("RIGHT", page.foot.frame, "RIGHT", 0, 0)
    page.again:SetScript("OnClick", function()
        hush()
        if ns.AH.IsOpen() then A.Read(true) end
    end)
    page.stat = Style.Text(page.foot.frame, Style.SIZE.small, "RIGHT")
    Style.InkText(page.stat, "LABEL")
    page.stat:SetPoint("RIGHT", page.again, "LEFT", -16, 0)
    page.stat:SetWordWrap(false)
    A.Paint()
end

-- "checked 4 min ago" keeps up while the tab shows; the ticker stops itself
-- once it doesn't.
local function keepAge()
    if ticker then return end
    ticker = C_Timer.NewTicker(A.AGE_TICK, function()
        if not visible() then
            if ticker then ticker:Cancel() end
            ticker = nil
            return
        end
        if not moving then paintHead() end
    end)
end

-- Win.ShowPage's fill: read your auctions once a visit (Check again for more).
function A.Fill()
    if not page then return end
    keepAge()
    if ns.AH.IsOpen() and not A.readAt then return A.Read() end
    A.Paint()
    C_Timer.After(0, A.CheckNext)
end

-- The key binding: the Cancel button, in the key press.
function A.Key()
    if not (visible() and ns.AH.IsOpen()) then return end
    local r = rowOf(A.picked)
    if r and r.isBid then return A.PlaceBid() end
    A.Cancel()
end

local function reset()
    A.checked, A.readAt, A.picked, A.forcedAt, A.costAsked = {}, nil, nil, nil, nil
    checking, busy, whyFor = nil, false, nil
end

ns.On("OwnedChanged", refresh)
-- A Cancel click that would have been refused can go now (or no longer can).
ns.On("LineChanged", function() if visible() and not moving then paintFooter() end end)
ns.On("AHOpened", function()
    reset()
    if visible() then A.Fill() end
end)
ns.On("AHClosed", function()
    reset()
    if page then A.Say(nil) end
    refresh()
end)
