-- Gold ledger: what each character made and spent through the mail and the auction
-- house, by day. It never calls mail or auction functions itself. It only listens to
-- what the client reports, which looks the same whichever addon did the work (the
-- game's window, this one, Auctionator, TSM, Postal...). A single global post-hook on
-- SendMail records who a letter is for.
--
-- Matching gold changes to reasons: the client reports the action first and the gold
-- about 0.2-0.3 s later, so each action leaves a pending "reason" and the next fitting
-- PLAYER_MONEY change claims it.
-- * out: a commodity bought (its quote from COMMODITY_PRICE_UPDATED; the name from the
-- won notice), gear bought (ITEM_PURCHASED / PURCHASE_COMPLETED with an id), an auction
-- posted (deposit), a letter sent (postage, then any gold attached), an item taken from
-- a COD letter.
-- * in: gold taken from a letter, found by diffing the inbox around each
-- MAIL_INBOX_UPDATE: a sale (seller invoice: price, house cut, deposit back) or a
-- player's letter.
-- A change with no pending reason (vendor, loot, quest) isn't recorded.
-- A won-auction letter (buyer invoice) is checked against buys seen live; one with no
-- live buy (a bid won while away) is recorded from the letter, once (Ledger seen keys).

local _, DUI = ...
DUI.Mail = DUI.Mail or {}
local ns = DUI.Mail

local Ledger = {}
ns.Ledger = Ledger

Ledger.WINDOW = 2       -- s a reason waits for its gold (and gold for its reason)
Ledger.KEEP = 300       -- newest entries kept per character
Ledger.MATCH = 31 * 86400   -- a live buy waits for its won letter as long as mail can sit in the mailbox
Ledger.SAME = 3600      -- s two reads of a letter's expiry may differ and still be the same letter
Ledger.ITEMS = 500      -- items tracked by name (busiest kept; the page shows the top few)
Ledger.IDS = 1000       -- item IDs kept before ones nothing refers to anymore are dropped
Ledger.KINDS = { "sales", "players", "buys", "cuts", "deposits", "postage", "sent", "cod" }
Ledger.RANGES = { session = 1, week = 7, month = 30 }

local session = {}      -- kind -> copper since login
local sessionItems = {}
local reasons = {}      -- waiting for gold: { kind, amount (nil = any), item, count, who, t }
local gains = {}        -- gold that arrived with no reason yet: { amount, t }
local snap              -- the inbox as last read, while a mailbox is open
local money             -- gold as last read
local quote             -- total of the last commodity quote
local postage           -- send page postage as last read

local itemsChanged = 0   -- bumped when item tallies change; the sorted list is only rebuilt then
local missing = {}       -- names with no ID found this session (bags aren't searched again)

local function now() return GetTime() end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j, k, l, m = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h, i, j, k, l, m end
end
local function num(v) return (type(v) == "number" and not (issecretvalue and issecretvalue(v))) and v or nil end

-- Saved data

function Ledger.Data()
    local c = DUI.DB.Character()
    local d = c.ledger
    if type(d) ~= "table" then
        d = { since = time(), days = {}, items = {}, recent = {}, seen = {} }
        c.ledger = d
    end
    d.days, d.items, d.recent, d.seen = d.days or {}, d.items or {}, d.recent or {}, d.seen or {}
    d.ids = d.ids or {}   -- item name -> itemID, whenever the game showed one (icons, tooltips)
    return d
end

-- Item ID by name: saved whenever the game shows one (a won letter's item, a gear buy,
-- a post), else the client's cache, else the bags.
function Ledger.Remember(name, id)
    if type(name) == "string" and type(id) == "number" and not (issecretvalue and issecretvalue(id)) then
        Ledger.Data().ids[name] = id
        missing[name] = nil
    end
end

local function inBags(name)
    local C = C_Container
    if type(C) ~= "table" or type(C.GetContainerNumSlots) ~= "function" then return nil end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, call(C.GetContainerNumSlots, bag) or 0 do
            local info = call(C.GetContainerItemInfo, bag, slot)
            local link = type(info) == "table" and info.hyperlink
            if type(link) == "string" and link:match("%[(.-)%]") == name then return info.itemID end
        end
    end
end

function Ledger.ItemID(name)
    if type(name) ~= "string" then return nil end
    local d = Ledger.Data()
    local id = d.ids[name]
    if id then return id end
    if missing[name] then return nil end
    id = C_Item and call(C_Item.GetItemInfoInstant, name)
    if type(id) ~= "number" then id = inBags(name) end
    Ledger.Remember(name, id)
    if not d.ids[name] then missing[name] = true end
    return d.ids[name]
end

-- The client loaded item info, so a name missed earlier may be cached now. Retried once
-- per frame (the event comes in bursts); a hit repaints the page for its icon.
local retryAsked = false
function Ledger.RetryMissing()
    if retryAsked or next(missing) == nil then return end
    retryAsked = true
    C_Timer.After(0, function()
        retryAsked = false
        local found = false
        for name in pairs(missing) do
            local id = C_Item and call(C_Item.GetItemInfoInstant, name)
            if type(id) == "number" then
                Ledger.Remember(name, id)
                found = found or Ledger.Data().ids[name] ~= nil
            end
        end
        if found and DUI.Fire then DUI.Fire("MailLedger") end
    end)
end

local function dayKey(t) return date("%Y-%m-%d", t or time()) end

local function addItem(list, name, field, amount, count)
    if not name then return end
    local it = list[name] or { bought = 0, boughtN = 0, sold = 0, soldN = 0 }
    list[name] = it
    it[field] = it[field] + amount
    it[field .. "N"] = it[field .. "N"] + (count or 1)
    itemsChanged = itemsChanged + 1
end

-- Record one entry: a kind and signed copper (negative = gold out), with what it was
-- for. Goes on the recent list unless `quiet` (part of a sale).
local function book(kind, amount, e, quiet)
    if amount == 0 then return end
    local d = Ledger.Data()
    local day = d.days[dayKey()] or {}
    d.days[dayKey()] = day
    day[kind] = (day[kind] or 0) + amount
    session[kind] = (session[kind] or 0) + amount
    if DUI.Fire then DUI.Fire("MailLedger") end   -- repaint the Ledger page
    if e and e.item and (kind == "buys" or kind == "sales") then
        local field = kind == "buys" and "bought" or "sold"
        -- An item sale counts what's kept: the price minus the house's cut.
        local worth = math.abs(amount) - (e.cut or 0)
        addItem(d.items, e.item, field, worth, e.count)
        addItem(sessionItems, e.item, field, worth, e.count)
    end
    if quiet then return end
    local entry = { kind = kind, amount = amount, t = time(), item = e and e.item, count = e and e.count, who = e and e.who,
        net = e and e.net }
    if entry.item then Ledger.ItemID(entry.item) end
    table.insert(d.recent, 1, entry)
    while #d.recent > Ledger.KEEP do table.remove(d.recent) end
    return entry
end

function Ledger.Recent() return Ledger.Data().recent end

-- Reasons and gold

local function expire(list)
    local t = now()
    for i = #list, 1, -1 do
        if t - list[i].t > Ledger.WINDOW then table.remove(list, i) end
    end
end

-- A reason with its gold: a sale is three entries, a send two.
local function settle(r, amount)
    if r.kind == "sale" then
        local v = r.invoice
        local e = { item = v.item, count = v.count, who = v.player, net = amount, cut = v.cut }
        local entry = book("sales", v.bid, e)
        book("cuts", -v.cut, nil, true)
        book("deposits", v.deposit, nil, true)
        if entry then entry.net = amount end
    elseif r.kind == "send" then
        local post = math.min(-amount, r.postage or -amount)
        book("postage", -post, { who = r.who })
        if -amount > post then book("sent", amount + post, { who = r.who }) end
    else
        local entry = book(r.kind, amount, r)
        if entry and r.kind == "buys" then entry.live = true end
    end
end

-- A gold change looks for its reason: same amount first, then one that accepts any
-- amount, then the oldest in the same direction.
local function match(list, amount, out)
    local pick
    for i, r in ipairs(list) do
        if r.out == out and r.amount == math.abs(amount) then pick = i; break end
    end
    if not pick then
        for i, r in ipairs(list) do
            if r.out == out and r.amount == nil then pick = i; break end
        end
    end
    if not pick then
        for i, r in ipairs(list) do
            if r.out == out then pick = i; break end
        end
    end
    return pick and table.remove(list, pick)
end

local function wait(r)
    r.t = now()
    expire(reasons)
    expire(gains)
    -- Gold that arrived before its reason (the order isn't guaranteed).
    for i, g in ipairs(gains) do
        if (g.amount < 0) == (r.out == true) and (r.amount == nil or r.amount == math.abs(g.amount)) then
            table.remove(gains, i)
            settle(r, g.amount)
            return
        end
    end
    reasons[#reasons + 1] = r
end

function Ledger.OnMoney()
    local m = num(call(GetMoney))
    if not m then return end
    local was = money
    money = m
    if not was or m == was then return end
    local delta = m - was
    expire(reasons)
    expire(gains)   -- loot and vendor gold never finds a reason; only kept for the window
    local r = match(reasons, delta, delta < 0)
    if r then settle(r, delta) else gains[#gains + 1] = { amount = delta, t = now() } end
end

-- Inbox, before and after

local function invoice(i)
    local kind, item, player, bid, _, deposit, cut, _, _, _, count = call(GetInboxInvoiceInfo, i)
    if kind ~= "buyer" and kind ~= "seller" then return nil end
    return { type = kind, item = item, player = player, bid = num(bid) or 0, deposit = num(deposit) or 0,
        cut = num(cut) or 0, count = num(count) or 1 }
end

-- A letter's stable key: sender, subject, invoice. Its expiry (now + days left) is
-- stored beside the key, not in it. The client counts days down on its own clock, so
-- two reads differ slightly, and a key rounded to the hour changed between reads near
-- the hour. Letters with the same key are told apart by closest expiry (`pairUp`,
-- `closest`, within Ledger.SAME).
local function letterKey(sender, subject, v)
    local key = tostring(sender) .. "|" .. tostring(subject)
    if v then key = key .. "|" .. v.type .. "|" .. tostring(v.item) .. "|" .. v.bid .. "|" .. v.count end
    return key
end
Ledger.LetterKey = letterKey   -- the inbox page tracks its selected letter by this too

-- The entry in `list` not yet `used` (by index) whose expiry is nearest `ends`, within Ledger.SAME.
local function closest(list, ends, used, endOf)
    local pick, best
    for j, x in ipairs(list) do
        local gap = math.abs(endOf(x) - ends)
        if not used[j] and gap <= Ledger.SAME and (not best or gap < best) then pick, best = j, gap end
    end
    return pick
end

-- Also reports whether every letter is visible. Past 50 the client only shows the first
-- 50, and new mail pushes the oldest out of view without removing it.
local function readInbox()
    local shown, total = call(GetInboxNumItems)
    local n = num(shown) or 0
    local out = {}
    for i = 1, n do
        local _, _, sender, subject, gold, cod, days, items = call(GetInboxHeaderInfo, i)
        if sender ~= nil or subject ~= nil then
            local v = invoice(i)
            if (num(items) or 0) > 0 then
                local name, itemID = call(GetInboxItem, i, 1)
                Ledger.Remember(name, itemID)
            end
            out[#out + 1] = { sender = sender, subject = subject, money = num(gold) or 0, cod = num(cod) or 0,
                items = num(items) or 0, invoice = v, key = letterKey(sender, subject, v),
                ends = time() + (num(days) or 0) * 86400 }
        end
    end
    return out, (num(total) or n) <= n
end

-- A won letter: match it to its live buy, or record it. Seen ones are kept by key as a
-- list of expiries (two identical won letters are two entries).
local function endOf(x) return x end
local function seenOf(key)
    local d = Ledger.Data()
    local seen = type(d.seen[key]) == "table" and d.seen[key] or {}
    d.seen[key] = seen
    return seen
end
-- A won letter that left the inbox (taken, deleted) never comes back, so drop its
-- expiry; a later identical win is a new buy. Only done while every letter is visible,
-- since one pushed out of view does come back (stale ones go at expiry, `Ledger.Trim`).
local function wonGone(o)
    local seen = seenOf(o.key)
    local j = closest(seen, o.ends, {}, endOf)
    if j then table.remove(seen, j) end
end
local function wonLetter(l, used)
    local d = Ledger.Data()
    local v = l.invoice
    local seen = seenOf(l.key)
    used[l.key] = used[l.key] or {}
    used = used[l.key]
    local j = closest(seen, l.ends, used, endOf)
    if j then used[j] = true; return end
    seen[#seen + 1] = l.ends
    used[#seen] = true
    for _, e in ipairs(d.recent) do
        if e.kind == "buys" and e.live and not e.checked and time() - e.t <= Ledger.MATCH
            and (-e.amount == v.bid) and (e.item == nil or e.item == v.item) then
            e.checked = true
            e.item = e.item or v.item
            return
        end
    end
    book("buys", -v.bid, { item = v.item, count = v.count, who = v.player })
end

local function byKey(list)
    local t = {}
    for _, l in ipairs(list) do
        t[l.key] = t[l.key] or {}
        table.insert(t[l.key], l)
    end
    return t
end

-- Pair each current letter with its old self: across all old/new pairs with the same
-- key within Ledger.SAME, closest expiries pair first (greedy in list order let a
-- removed letter take its neighbor's place). Returns old -> new.
local function pairUp(olds, nows)
    local cands = {}
    for i, o in ipairs(olds) do
        for j, n in ipairs(nows) do
            local gap = math.abs(o.ends - n.ends)
            if gap <= Ledger.SAME then cands[#cands + 1] = { i = i, j = j, gap = gap } end
        end
    end
    table.sort(cands, function(a, b)
        if a.gap ~= b.gap then return a.gap < b.gap end
        if a.i ~= b.i then return a.i < b.i end
        return a.j < b.j
    end)
    local pairOf, taken = {}, {}
    for _, c in ipairs(cands) do
        if not pairOf[c.i] and not taken[c.j] then pairOf[c.i], taken[c.j] = nows[c.j], true end
    end
    return pairOf
end

function Ledger.OnInbox()
    local new, whole = readInbox()
    local found = {}
    if snap then
        local after = byKey(new)
        for key, olds in pairs(byKey(snap)) do
            local pairOf = pairUp(olds, after[key] or {})
            found[key] = { olds = olds, pairOf = pairOf }
            for i, o in ipairs(olds) do
                if whole and not pairOf[i] and o.invoice and o.invoice.type == "buyer" then wonGone(o) end
            end
        end
    end
    local used = {}
    for _, l in ipairs(new) do
        if l.invoice and l.invoice.type == "buyer" then wonLetter(l, used) end
    end
    for _, p in pairs(found) do
        for i, o in ipairs(p.olds) do
            local n = p.pairOf[i]
            local gold = o.money - (n and n.money or 0)
            if gold > 0 then
                if o.invoice and o.invoice.type == "seller" then
                    wait({ kind = "sale", out = false, amount = gold, invoice = o.invoice })
                else
                    wait({ kind = "players", out = false, amount = gold, who = o.sender })
                end
            end
            local cod = o.cod - (n and n.cod or 0)
            if cod > 0 and (n == nil or n.items < o.items) then
                wait({ kind = "cod", out = true, amount = cod, who = o.sender })
            end
        end
    end
    snap = new
end

-- Auction house and sending

local lastWon
local EVENTS = {
    COMMODITY_PRICE_UPDATED = function(_, total) quote = num(total) end,
    AUCTION_HOUSE_SHOW_COMMODITY_WON_NOTIFICATION = function(name, count)
        lastWon = { item = name, count = num(count) }
        -- The won notice can come after its SUCCEEDED: name the pending buy.
        for i = #reasons, 1, -1 do
            local r = reasons[i]
            if r.kind == "buys" and r.commodity and not r.item then r.item, r.count = name, num(count); lastWon = nil; return end
        end
    end,
    COMMODITY_PURCHASE_SUCCEEDED = function()
        local r = { kind = "buys", out = true, amount = quote, commodity = true }
        if lastWon then r.item, r.count, lastWon = lastWon.item, lastWon.count, nil end
        quote = nil
        wait(r)
    end,
    ITEM_PURCHASED = function(itemID)
        local name = C_Item and call(C_Item.GetItemNameByID, itemID)
        Ledger.Remember(name, itemID)
        wait({ kind = "buys", out = true, item = name, count = 1 })
    end,
    -- The posted item, if the client already knows the new auction (a guess).
    AUCTION_HOUSE_AUCTION_CREATED = function(auctionID)
        local info = C_AuctionHouse and call(C_AuctionHouse.GetAuctionInfoByID, auctionID)
        local id = type(info) == "table" and type(info.itemKey) == "table" and info.itemKey.itemID or nil
        local name = id and C_Item and call(C_Item.GetItemNameByID, id)
        Ledger.Remember(name, id)
        wait({ kind = "deposits", out = true, item = name })
    end,
    MAIL_SEND_INFO_UPDATE = function() postage = num(call(GetSendMailPrice)) end,
    MAIL_SEND_SUCCESS = function()
        local price = math.max(postage or 0, num(call(GetSendMailPrice)) or 0)
        postage = nil
        wait({ kind = "send", out = true, postage = price, who = Ledger.sendTo })
    end,
    MAIL_SHOW = function() snap = nil; Ledger.OnInbox() end,
    MAIL_CLOSED = function() snap = nil end,
    MAIL_INBOX_UPDATE = function() Ledger.OnInbox() end,
    PLAYER_MONEY = function() Ledger.OnMoney() end,
    GET_ITEM_INFO_RECEIVED = function() Ledger.RetryMissing() end,
}

-- ITEM_PURCHASED covers gear. PURCHASE_COMPLETED's id is the same purchase (0 for a
-- commodity), so it isn't a second reason.

function Ledger.Start()
    if Ledger.started then return end
    Ledger.started = true
    money = num(call(GetMoney))
    Ledger.Trim(Ledger.Data())
    for event, fn in pairs(EVENTS) do
        DUI.RegisterEvent(event, function(_, ...) fn(...) end)
    end
    -- Who a letter is for, whichever addon sends it. Global post-hook: runs after the
    -- client's function and changes nothing.
    if type(SendMail) == "function" then
        hooksecurefunc("SendMail", function(to) if type(to) == "string" then Ledger.sendTo = to end end)
    end
end

-- At login: drop seen won letters past their expiry, convert the old saved format
-- (expiry hour inside the key) to the new one, trim items beyond the busiest
-- Ledger.ITEMS (the page shows the top few), and past Ledger.IDS drop IDs no item or
-- entry refers to anymore.
function Ledger.Trim(d)
    local t = time()
    local old = {}
    for k, v in pairs(d.seen) do
        if type(v) == "table" then
            for j = #v, 1, -1 do
                if type(v[j]) ~= "number" or v[j] + Ledger.SAME < t then table.remove(v, j) end
            end
            if #v == 0 then d.seen[k] = nil end
        else
            old[k] = v
        end
    end
    for k, v in pairs(old) do
        d.seen[k] = nil
        local head, hour, tail = string.match(tostring(k), "^(.*)|(%d+)|(buyer|.*)$")
        if head and type(v) == "number" and v >= t then
            local key = head .. "|" .. tail
            local list = type(d.seen[key]) == "table" and d.seen[key] or {}
            list[#list + 1] = tonumber(hour) * 3600 + 1800
            d.seen[key] = list
        end
    end
    local names = {}
    for name in pairs(d.items) do names[#names + 1] = name end
    if #names > Ledger.ITEMS then
        local function busy(n) local it = d.items[n]; return (it.sold or 0) + (it.bought or 0) end
        table.sort(names, function(a, b) return busy(a) > busy(b) end)
        for j = Ledger.ITEMS + 1, #names do d.items[names[j]] = nil end
        itemsChanged = itemsChanged + 1
    end
    local ids = 0
    for _ in pairs(d.ids) do ids = ids + 1 end
    if ids > Ledger.IDS then
        local named = {}
        for name in pairs(d.items) do named[name] = true end
        for _, e in ipairs(d.recent) do if e.item then named[e.item] = true end end
        for name in pairs(d.ids) do
            if not named[name] then d.ids[name] = nil end
        end
    end
end

-- Reading it back

-- Re-sorted only when tallies changed, not on every paint.
local sorted = setmetatable({}, { __mode = "k" })
local function itemList(src)
    local was = sorted[src]
    if was and was.at == itemsChanged then return was.list end
    local out = {}
    for name, it in pairs(src) do
        out[#out + 1] = { name = name, bought = it.bought, boughtN = it.boughtN, sold = it.sold, soldN = it.soldN,
            net = it.sold - it.bought }
    end
    table.sort(out, function(a, b)
        if a.sold + a.bought ~= b.sold + b.bought then return a.sold + a.bought > b.sold + b.bought end
        return a.name < b.name
    end)
    sorted[src] = { at = itemsChanged, list = out }
    return out
end

-- "session" | "week" | "month" | "all": { net, kinds = { kind = copper },
-- days = { { day, net } } oldest first, items = { ... } busiest first }.
function Ledger.Range(name)
    local d = Ledger.Data()
    local out = { kinds = {}, days = {}, net = 0 }
    for _, k in ipairs(Ledger.KINDS) do out.kinds[k] = 0 end
    local function add(kinds)
        local net = 0
        for k, v in pairs(kinds) do
            out.kinds[k] = (out.kinds[k] or 0) + v
            net = net + v
        end
        out.net = out.net + net
        return net
    end
    if name == "session" then
        add(session)
        out.items = itemList(sessionItems)
        out.days[1] = { day = dayKey(), net = out.net }
        return out
    end
    local n = Ledger.RANGES[name]
    if n then
        for i = n - 1, 0, -1 do
            local key = dayKey(time() - i * 86400)
            out.days[#out.days + 1] = { day = key, net = add(d.days[key] or {}) }
        end
    else
        local keys = {}
        for key in pairs(d.days) do keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do out.days[#out.days + 1] = { day = key, net = add(d.days[key]) } end
    end
    out.items = itemList(d.items)   -- by item: all time (kept small)
    return out
end
