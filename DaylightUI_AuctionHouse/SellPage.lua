-- The Sell tab, laid out like Auctionator's: what can be sold from your bags
-- on the left, under the game's item classes, and on the right the picked
-- item's sale form (how many, the price each, how long), the deposit and what
-- it brings, Post and Skip, a line saying why the price is what it is, and
-- under it what's up on the Auction House right now and its cheapest price
-- each day for two weeks.
--
-- Prices: each item is searched once a visit (ns.Search.Item, its first page:
-- results come cheapest first), the picked one first and the rest in the
-- background, one at a time, since the Auction House answers one request at a
-- time and a Post click can't wait in line. Picking an item that isn't checked
-- yet stops a background check, and a check My auctions made a moment ago is
-- used as it is. Until its search is back a row shows the saved price with its
-- age; Post waits for the search, so nothing is posted on an old price, and a
-- search older than FRESH is checked again by itself.
--
-- The price: the cheapest one up from someone else, less the undercut setting
-- (gear and recipes go a whole silver under, as the game takes only silver
-- for them), never under the smallest step. When the cheapest is yours (or
-- another of your characters'), the same price. No one else selling: the
-- usual price. Neither: the player types one.
--
-- Posting is one click (ns.Post.Send inside it; the key binding too). After a
-- post the next item is picked, so Post again and again sells the lot; "Sell
-- all" on a heading does the same inside that heading.
--
--   ns.SellPage.Build(page)   once, by the window
--   ns.SellPage.Fill()        each time the tab shows
--   ns.SellPage.Key()         the key binding: Post

local _, ns = ...
local DUI = DaylightUI
local L = ns.L
local Style = DUI.Style
local W = DUI.Widgets
local Parts = DUI.Win.Parts
local Motion = DUI.Motion

local P = {}
ns.SellPage = P

P.LEFT_W = 250
P.LIST_TOP = 40          -- the list starts under "From your bags"
P.ICON = 40
P.FORM_TOP = 70          -- the first form line under the item's name
P.FORM_STEP = 32
P.LABEL_W = 96
P.BOX_W = 220
P.BOX_H = 140
P.SAID_TOP = 204
P.WHY_TOP = 224
P.LOWER_TOP = 294        -- what's up now and the daily lows
P.DAYS = 14
P.DAY_H = 120
P.QUIET = 4              -- seconds the background checks wait after the player picks, types or posts
P.GAP = 0.2              -- seconds between two background checks, so the line is often free for a click
P.FRESH = 120            -- seconds a search stays good for a post
P.FAR_UNDER = 0.5        -- a price under this share of the usual one is said in the warning color
P.DEPTH = 0.2            -- a stackable price is judged against the one this share of the way into what's up
-- The Auction House's share of a sale. A guess: the modern game's 5%, not
-- checked on Forever yet. Only "You get when it sells" reads it.
P.CUT = 0.05
-- The Auction House's own category order (the Buy tab's list), by item class.
P.CLASS_ORDER = { 2, 4, 1, 0, 7, 6, 9, 15 }   -- Weapon, Armor, Container, Consumable, Trade Goods, Projectile, Recipe, Misc
P.AH_COLS = {
    { id = "unit", text = L["Price each"], width = 110, sort = false },
    { id = "qty", text = L["How many"], width = 96, justify = "RIGHT", sort = false },
    { id = "mine", text = "", fill = true },
}

P.picked = nil      -- the price key on the form
P.selling = nil     -- the heading being sold ("Sell all"): { id, name, keys }
P.checked = {}      -- key -> { auctions, at, err } searched this visit
P.edit = nil        -- what the player typed for the picked item: { qty, unit, bad, bid, badBid }
P.message = nil     -- the line under the form: { text, role }

local page
local rows, byKey = {}, {}
local heads            -- the headings, until the rows are read again
local lines = {}       -- key -> the list line showing it (Parts.Shine after a post)
local checking = nil   -- the key being searched now
local checkingID, checkingFn, checkingBg   -- its search, to stop a background one when the player picks
local postedKeys = {}  -- key -> true: posted this visit, so an earlier search of it is old news
local asked = nil      -- the low-price question waiting for a second Post click: key .. qty .. unit
local busy = false     -- a post is out
local ownedRead = false
local quietUntil = 0
local waking = false
local waitingInfo = false   -- a row's item isn't loaded yet: its name comes with ITEM_DATA_LOAD_RESULT
local kinds, takes = {}, {}  -- ns.Post.Kind and ns.Post.Sellable, until the bags change

local format, floor = string.format, math.floor
local SEP = "  \194\183  "
local DASH = "\226\128\148"

local function hush() quietUntil = GetTime() + P.QUIET end
local function money(c) return W.Money(c) end
local function value(text) return Parts.Hex(Style.INK.VALUE) .. text .. "|r" end
local function pop(text) return Parts.Hex({ Style.Pop() }) .. text .. "|r" end
local function visible() return page ~= nil and page:IsVisible() end

-- ---------------------------------------------------------------------
-- Money in the price box: written and read with the game's coin letters
-- ---------------------------------------------------------------------

local function symbol(name, fallback)
    local v = _G[name]
    return (type(v) == "string" and v ~= "") and v or fallback
end

local function symbols()
    return symbol("GOLD_AMOUNT_SYMBOL", "g"), symbol("SILVER_AMOUNT_SYMBOL", "s"), symbol("COPPER_AMOUNT_SYMBOL", "c")
end

-- 12050 -> "1g 20s 50c", the way a player would type it.
function P.PlainMoney(c)
    c = floor(c or 0)
    local gs, ss, cs = symbols()
    local g, s, cp = floor(c / 10000), floor(c / 100) % 100, c % 100
    local out = {}
    if g > 0 then out[#out + 1] = g .. gs end
    if s > 0 then out[#out + 1] = s .. ss end
    if cp > 0 or #out == 0 then out[#out + 1] = cp .. cs end
    return table.concat(out, " ")
end

-- One controller step of a price: a tenth of its first digit, landing on
-- round amounts (12g 34s steps to 13g, 31c to 32c), so a few presses reach
-- any price whatever its size.
function P.StepMoney(c, dir, lowest)
    c = floor(c or 0)
    local unit = 10 ^ math.max(0, #tostring(c) - 2)
    local to = dir > 0 and (floor(c / unit) + 1) * unit or (math.ceil(c / unit) - 1) * unit
    return math.max(lowest or 0, to)
end

-- The largest coin in an amount: 10000, 100 or 1.
function P.TopCoin(c)
    if type(c) ~= "number" or c < 1 then return nil end
    return c >= 10000 and 10000 or c >= 100 and 100 or 1
end

-- "1g 20s 5c" -> 12005; nil when it isn't an amount. Gold, silver and copper
-- in that order, each once. Coin words are typed through an input method in
-- some languages (Chinese 金 银 铜), so a number that ends the price needs
-- none: after a coin it is the next coin down ("1g 20" = 1g 20s), and a bare
-- number is in `coin`, the largest coin of the price the box suggested. With
-- no suggestion a bare number isn't a price.
function P.ReadMoney(text, coin)
    if type(text) ~= "string" then return nil end
    local gs, ss, cs = symbols()
    local units = { g = 10000, s = 100, c = 1 }
    units[gs:lower()], units[ss:lower()], units[cs:lower()] = 10000, 100, 1
    local rest = text:lower():gsub("%s+", "")
    if rest == "" then return nil end
    local total, last = 0, math.huge
    while rest ~= "" do
        local n, unit, after = rest:match("^(%d+)(%D*)(.*)$")
        local mult
        if unit == "" then
            -- the number ends the text
            if last == math.huge then mult = coin else mult = last > 1 and last / 100 or nil end
        else
            mult = unit and units[unit]
        end
        if not mult or mult >= last then return nil end
        total, last, rest = total + tonumber(n) * mult, mult, after
    end
    return total
end

-- ---------------------------------------------------------------------
-- The items and their prices
-- ---------------------------------------------------------------------

-- Gear and recipes post one auction each; everything else is a commodity.
-- Only a guess while the game hasn't said (Post.Kind is nil until it knows
-- the item); Post.Send asks the game itself.
local SINGLE = { [2] = true, [4] = true, [9] = true }   -- Enum.ItemClass Weapon, Armor, Recipe
function P.Kind(key, classID)
    local k = kinds[key]
    if k == nil then
        k = ns.Post.Kind(key)
        if k then kinds[key] = k end
    end
    if k then return k end
    return SINGLE[classID] and "item" or "commodity"
end

-- Someone else's cheapest in a search, and how many of them; and the
-- cheapest of yours. Your other characters' count as yours: posting never
-- undercuts them.
local function cheapest(r, auctions)
    local lowest, lowestQty, mineLow
    for _, a in ipairs(auctions or {}) do
        local unit = a.unit
        if (a.key == nil or a.key == r.key) and type(unit) == "number" and unit >= 1 then
            local qty = a.qty or 1
            local yours = math.min(qty, (a.own or 0) + (a.acct or 0))
            if yours > 0 and (not mineLow or unit < mineLow) then mineLow = unit end
            if qty > yours then
                if not lowest or unit < lowest then lowest, lowestQty = unit, qty - yours
                elseif unit == lowest then lowestQty = lowestQty + qty - yours end
            end
        end
    end
    return lowest, lowestQty, mineLow
end

-- What Sell would post a row at: d = { unit, hint, far, mine, none, lowest,
-- lowestQty, usual, saved (how old, before the search), failed, fresh, age }.
-- No unit: no price yet, or still checking (d.fresh false, no d.saved).
function P.Decide(r)
    local c = P.checked[r.key]
    local rkey = ns.Ruleset.Key()
    local now = ns.Game.Now()
    local d = { usual = rkey and ns.Store.Market(rkey, r.key, now) or nil }
    if c and c.err then
        d.failed = true
        return d
    end
    local lowest, lowestQty, mineLow
    if c then
        lowest, lowestQty, mineLow = cheapest(r, c.auctions)
        d.fresh, d.age = true, GetTime() - c.at
    else
        lowest = rkey and ns.Store.Min(rkey, r.key)
        if not lowest then return d end
        local seen = ns.Store.SeenAt(rkey, r.key) or now
        d.saved = ns.Ago(math.max(0, now - seen))
        mineLow = ownedRead and ns.Post.MineLow(r.key) or nil
    end
    local kind = P.Kind(r.key, r.classID)
    local step = ns.Post.Step(kind, r.key)
    if mineLow and (not lowest or mineLow <= lowest) then
        d.unit, d.mine = mineLow, true
        d.hint = L["the cheapest is yours: same price"]
    elseif lowest then
        local pct = ns.Setting("undercutPct") or 0
        local under = pct > 0 and math.floor(lowest * pct) or (ns.Setting("undercut") or 0)
        d.unit = math.max(step, ns.Post.Round(lowest - under, kind, true, r.key))
        d.lowest, d.lowestQty = lowest, lowestQty
        local by = lowest - d.unit
        d.hint = by > 0 and format(L["%s under the cheapest"], money(by)) or L["the same as the cheapest"]
    elseif d.usual then
        d.unit, d.none = math.max(step, ns.Post.Round(d.usual, kind, false, r.key)), true
        d.hint = L["no one else selling: usual price"]
    else
        d.none = true
        d.hint = L["no price yet: you set it"]
    end
    if d.unit and d.usual and d.unit < d.usual * P.FAR_UNDER then
        d.far = true
        d.hint = L["under half the usual price"]
    end
    if c and d.lowest then d.floor = P.Floor(c.auctions) end
    return d
end

-- The least a stackable item's price should be before Post asks twice: the price
-- DEPTH of the way into what others have up, of which a share that shrinks as the
-- price grows (70% at 1g and under, down to 30%). One silly-low listing then
-- doesn't drag a post down with it unasked. Nil for gear (each piece is its own).
function P.Floor(auctions)
    if type(auctions) ~= "table" or not auctions.commodity then return nil end
    local total = 0
    for _, a in ipairs(auctions) do total = total + math.max(0, (a.qty or 0) - (a.own or 0) - (a.acct or 0)) end
    if total <= 0 then return nil end
    local want, n = math.max(1, floor(total * P.DEPTH)), 0
    for _, a in ipairs(auctions) do
        n = n + math.max(0, (a.qty or 0) - (a.own or 0) - (a.acct or 0))
        if n >= want then
            local unit = a.unit or 0
            if unit <= 0 then return nil end
            return floor(unit * (0.3 + 0.4 * math.min(1, 10000 / unit)))
        end
    end
    return nil
end

local function makeRow(key)
    local id = ns.Items.ID(key)
    local info = ns.Items.Info(id)
    if not info then waitingInfo = true end
    local r = {
        key = key, itemID = id, quality = info and info.quality, icon = info and info.icon, classID = info and info.classID,
        name = info and ns.Items.KeyName(key, info.name) or format(L["Item %d"], id or 0),
        have = ns.Post.Most(key),
    }
    r.d = P.Decide(r)
    r.worth = r.d.unit and r.d.unit * r.have or nil
    return r
end

-- Does the game take a stack of it? Asked once until the bags change.
local function sellable(key)
    if takes[key] == nil then takes[key] = ns.Post.Sellable(key) end
    return takes[key]
end

-- Every bag item the Auction House takes, with its price.
function P.Rows()
    rows, byKey, heads = {}, {}, nil
    waitingInfo = false
    for _, key in ipairs(ns.Bags.Keys()) do
        local id = ns.Items.ID(key)
        if id and ns.Items.CanAuction(id) and ns.Bags.Free(key) > 0 and sellable(key) then
            local r = makeRow(key)
            rows[#rows + 1] = r
            byKey[key] = r
        end
    end
    return rows
end

function P.Row(key) return byKey[key] end

local function classRank()
    local rank = {}
    for i, c in ipairs(P.CLASS_ORDER) do rank[c] = i end
    return rank
end

-- The headings in order, each { id, name, rows (most valuable first), total, checking }.
function P.IsPinned(key) return ns.DB.Table("sellPinned")[key] == true end
function P.IsHidden(key) return ns.DB.Table("sellHidden")[key] == true end

-- Pinned items sit in their own heading on top, hidden ones in one at the bottom.
function P.Headings()
    if heads then return heads end
    local rank = classRank()
    local list, byId = {}, {}
    for _, r in ipairs(rows) do
        local c = r.classID
        local id, name, at = "c:" .. tostring(c or "?"), (c and ns.Items.ClassName(c)) or L["Other"], c and (rank[c] or 100 + c) or 100000
        if P.IsHidden(r.key) then id, name, at = "hidden", L["Hidden"], math.huge
        elseif P.IsPinned(r.key) then id, name, at = "pinned", L["Pinned"], -1 end
        local h = byId[id]
        if not h then
            h = { id = id, name = name, rows = {}, total = 0, checking = 0, rank = at, hidden = id == "hidden" or nil }
            byId[id] = h
            list[#list + 1] = h
        end
        h.rows[#h.rows + 1] = r
        if r.worth then h.total = h.total + r.worth
        elseif not r.d.fresh and not r.d.failed then h.checking = h.checking + 1 end
    end
    table.sort(list, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.name < b.name
    end)
    for _, h in ipairs(list) do
        table.sort(h.rows, function(a, b)
            if (a.worth ~= nil) ~= (b.worth ~= nil) then return a.worth ~= nil end
            if a.worth and a.worth ~= b.worth then return a.worth > b.worth end
            if a.name ~= b.name then return a.name < b.name end
            return a.key < b.key
        end)
    end
    heads = list
    return list
end

-- The rows in the order shown (one heading's, when given).
function P.Order(id)
    local out = {}
    for _, h in ipairs(P.Headings()) do
        if (not id and not h.hidden) or h.id == id then
            for _, r in ipairs(h.rows) do out[#out + 1] = r end
        end
    end
    return out
end

-- The few words under a row's name: "14 x 31c", or what's missing.
function P.SubOf(r)
    local d = r.d
    local n = tostring(r.have)
    if d.failed then return n .. SEP .. L["couldn't check the price"] end
    if d.unit then
        local s = format(L["%d \195\151 %s"], r.have, money(d.unit))
        if d.saved then return s .. SEP .. format(L["%s ago"], d.saved) end
        if d.none and d.fresh then s = s .. SEP .. L["no one else selling"] end
        return s
    end
    if not d.fresh then return n .. SEP .. L["checking the price..."] end
    return n .. SEP .. L["no price yet: you set it"]
end

-- ---------------------------------------------------------------------
-- Checking prices: one search at a time, the picked item first
-- ---------------------------------------------------------------------

local queued = false
local function refresh()
    if queued or not page then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        P.Paint()
    end)
end

function P.CheckNext()
    if checking or not ns.AH.IsOpen() or not visible() then return end
    local want
    if P.picked and byKey[P.picked] and not P.checked[P.picked] then want = byKey[P.picked] end
    local background = want == nil
    if background then
        for _, r in ipairs(P.Order()) do
            if not P.checked[r.key] then want = r; break end
        end
        if not want then return end
        local left = quietUntil - GetTime()
        if left > 0 then   -- the player is at it: their click comes first
            if not waking then
                waking = true
                C_Timer.After(left, function() waking = false; P.CheckNext() end)
            end
            return
        end
    end
    if not want.itemID then return end
    local key = want.key
    -- My auctions (or this page) searched it a moment ago: that answer will do
    local _, auctions, age = ns.Search.Last(want.itemID)
    if auctions and age <= P.FRESH and not postedKeys[key] then
        P.checked[key] = { auctions = auctions, at = GetTime() - age }
        refresh()
        return C_Timer.After(0, P.CheckNext)
    end
    checking = key
    local function done(_, reason, found)
        if checking == key then checking, checkingID, checkingFn = nil, nil, nil end
        if reason == "closed" or reason == "dropped" then return end
        postedKeys[key] = nil
        P.checked[key] = { auctions = found or {}, at = GetTime(), err = found == nil and reason or nil }
        refresh()
        local pickWaits = P.picked and byKey[P.picked] and not P.checked[P.picked]
        C_Timer.After(background and not pickWaits and P.GAP or 0, P.CheckNext)
    end
    checkingID, checkingFn, checkingBg = want.itemID, done, background
    ns.Search.Item(want.itemID, done, { pages = 1, priority = not background })
end

-- The player picked an item that isn't checked: a background check gives way.
local function yieldBackground(key)
    if not (checking and checkingBg and checking ~= key) then return end
    local id, fn = checkingID, checkingFn
    checking, checkingID, checkingFn = nil, nil, nil
    ns.Search.Cancel(id, fn)
end

-- An old search of the picked item is forgotten, and any warning with it.
-- True when it was.
function P.Recheck()
    local c = P.picked and P.checked[P.picked]
    if not c or c.err or GetTime() - c.at <= P.FRESH then return false end
    P.checked[P.picked] = nil
    ns.Post.Forget()
    return true
end

-- The search's age shows in the why line, and at FRESH the button changes:
-- a repaint at each, once per search.
local function watchAge(key, c)
    if c.watched then return end
    c.watched = true
    local function look()
        if not (P.picked == key and P.checked[key] == c) then return end
        -- still on it after FRESH: its price is checked again without a click
        if P.Recheck() then P.CheckNext() end
        refresh()
    end
    C_Timer.After(60, look)
    C_Timer.After(P.FRESH + 1, look)
end

-- ---------------------------------------------------------------------
-- Picking and the form's numbers
-- ---------------------------------------------------------------------

local function leaveBoxes()
    local form = page and page.right.form
    if not form then return end
    for _, box in ipairs({ form.qty, form.price }) do
        if box:HasFocus() then box:ClearFocus() end
    end
end

-- byHand: the player clicked the line (it leaves a heading being sold when
-- it isn't in it, and clears the last notice).
function P.Pick(key, byHand)
    leaveBoxes()
    local changed = P.picked ~= key
    if changed then
        P.edit = nil
        ns.Post.Forget()
    end
    if byHand then
        P.message = nil
        if P.selling then
            local inIt = false
            for _, k in ipairs(P.selling.keys) do if k == key then inIt = true end end
            if not inIt then P.selling = nil end
        end
    end
    local c = P.checked[key]
    if c and c.err then P.checked[key] = nil end   -- a failed check: picking it tries once more
    hush()
    P.picked = key
    if not P.checked[key] then yieldBackground(key) end
    P.Recheck()
    if changed and visible() and page.right.sale:IsVisible() then
        Motion.Fade(page.right.sale, 0.25, 1, Motion.FAST)
    end
    P.Paint()
    P.CheckNext()
end

function P.Hours()
    local h = ns.Setting("hours")
    for _, x in ipairs(ns.Post.HOURS) do if x == h then return h end end
    return 24
end

-- What the form shows for a row: qty, unit, hours.
function P.Numbers(r)
    local qty, unit = P.Amount(r), r.d.unit
    local e = P.edit
    if e then
        if e.qty then qty = e.qty end
        if e.unit then unit = e.unit end
    end
    return math.min(qty, r.have), unit, P.Hours()
end

-- How many Sell starts at: the amount you last posted of it, else all of it.
function P.Amount(r)
    local saved = ns.DB.Table("sellAmount")[r.key]
    if type(saved) == "number" and saved >= 1 and saved < r.have then return saved end
    return r.have
end

-- The next row after `key`: inside the heading being sold, else the whole
-- list. An item whose search found no price is passed over: it needs a price
-- typed, so it waits for the player's own pick.
local function nextAfter(key)
    local keys = {}
    if P.selling then
        keys = P.selling.keys
    else
        for i, r in ipairs(P.Order()) do keys[i] = r.key end
    end
    local at
    for i, k in ipairs(keys) do if k == key then at = i end end
    for i = (at or 0) + 1, #keys do
        local r = byKey[keys[i]]
        if r and r.key ~= key and not (r.d.fresh and not r.d.unit) then return r end
    end
    return nil
end

function P.Skip()
    if not P.picked or busy then return end
    local n = nextAfter(P.picked)
    if n then return P.Pick(n.key) end
    if P.selling then
        P.Say(format(L["That was the last of %s."], P.selling.name))
        P.selling = nil
    end
    P.Paint()
end

function P.SellAll(id, name)
    local keys = {}
    for i, r in ipairs(P.Order(id)) do keys[i] = r.key end
    if #keys == 0 then return end
    P.selling = { id = id, name = name, keys = keys }
    P.message = nil
    P.Pick(keys[1])
end

-- The boxes, as the player types: kept for the picked item until another is
-- picked. A price that doesn't read waits for Post to say so.
local function typed(which, text, user)
    if not user then return end
    local r = P.picked and byKey[P.picked]
    if not r then return end
    hush()
    P.edit = P.edit or {}
    if which == "qty" then
        local n = tonumber(text)
        P.edit.qty = n and math.max(0, floor(n)) or 0
    elseif which == "bid" then
        local trimmed = (text or ""):match("^%s*(.-)%s*$")
        local c = trimmed ~= "" and P.ReadMoney(trimmed, P.TopCoin(P.edit.unit or (r.d and r.d.unit))) or nil
        P.edit.bid = c
        P.edit.badBid = trimmed ~= "" and c == nil
    else
        local trimmed = (text or ""):match("^%s*(.-)%s*$")
        local c = trimmed ~= "" and P.ReadMoney(trimmed, P.TopCoin(r.d and r.d.unit)) or nil
        P.edit.unit = c
        P.edit.bad = trimmed ~= "" and c == nil
    end
    ns.Post.Forget()   -- a warning was for the numbers before
    P.PaintBox()
end

-- ---------------------------------------------------------------------
-- Posting
-- ---------------------------------------------------------------------

-- The game's warning waiting for the click, when it's for what the form shows now.
function P.Warned(r)
    local w = ns.Post.Warned()
    if not (w and r) then return nil end
    local qty, unit, hours = P.Numbers(r)
    if w.key == r.key and w.qty == qty and w.unit == unit and w.hours == hours then return w end
    return nil
end

local POST_SAYS = {
    closed = L["Open the Auction House to post."],
    busy = L["The Auction House is still answering. Click again in a moment."],
    checking = L["Still checking its price. Click again in a moment."],
    late = L["Still waiting for the game's answer to your last click. Try again in a moment."],
    throttled = L["The Auction House is still answering. Try again in a moment."],
    nobags = L["None of it is left in your bags to sell."],
    count = L["You don't have that many in your bags."],
    price = L["Type a price of at least 1c."],
    silver = L["The Auction House takes whole silver only for this item. Type the price again."],
    moved = L["That stack moved in your bags. Click Post to post it again."],
    unknown = L["The game is still loading this item. Try again in a moment."],
    failed = L["The game said no to that post."],
    timeout = L["No answer from the game. Check your auctions before you post it again."],
    error = L["Something went wrong posting it."],
}
-- A post that went out and then lost its answer may have gone through.
local DONE_SAYS = {
    closed = L["The Auction House closed while posting. Check your auctions before you post it again."],
}

-- The sentence for a post's end. `done`: it had gone out.
local function postSays(why, detail, done)
    if why == "failed" and type(detail) == "string" and detail ~= "" then
        return format(L["The game said no to that post: %s."], detail)
    end
    return done and DONE_SAYS[why] or POST_SAYS[why] or POST_SAYS.error
end

-- The line under the form, in a role's color (GOOD, WARN); nil clears it.
function P.Say(text, role)
    P.message = text and { text = text, role = role or "GOOD" } or nil
    if not page then return end
    local said = page.right.said
    if text and said:IsVisible() then Motion.Fade(said, 0, 1, Motion.FAST) end
    P.PaintSaid()
end

local function posted(r, qty, unit)
    busy = false
    hush()
    -- the amount posted comes back next time; all of it needs no note
    ns.DB.Table("sellAmount")[r.key] = qty < r.have and qty or nil
    if ns.Setting("chatPosts") then
        local link = ns.Items.Hyperlink(r.key) or r.name
        ns.Print(format(L["Posted %d %s at %s each."], qty, link, W.Money(unit, { color = false })))
    end
    P.checked[r.key] = nil   -- yours is up now: its price is searched again
    postedKeys[r.key] = true
    P.edit = nil
    local nextRow = nextAfter(r.key)
    local text = format(L["Posted %d %s at %s each."], qty, r.name, money(unit))
    if nextRow then
        text = text .. " " .. format(L["Next up: %s."], nextRow.name)
    elseif P.selling then
        text = text .. " " .. format(L["That was the last of %s."], P.selling.name)
        P.selling = nil
    end
    P.OwnedSoon()
    local line = lines[r.key]
    if line then Parts.Shine(line) end
    P.Say(text, "GOOD")
    if nextRow then
        P.Pick(nextRow.key)
    else
        P.Paint()
        P.CheckNext()
    end
end

-- The Post button, or the key: posts the picked item inside this click.
function P.Post()
    if busy then return end
    local r = P.picked and byKey[P.picked]
    if not r then return end
    hush()
    leaveBoxes()
    if P.edit and P.edit.bad then
        return P.Say(format(L["Type a price like %s."], P.PlainMoney(12005)), "WARN")
    end
    if P.Recheck() then
        P.Say(L["Checking its price again. Click Post when it's back."], "WARN")
        P.Paint()
        return P.CheckNext()
    end
    local qty, unit, hours = P.Numbers(r)
    if P.Warned(r) then
        local ok, why, detail = ns.Post.Confirm()
        if ok then
            busy = true
            P.Say(nil)
        else
            P.Say(postSays(why, detail), "WARN")
        end
        return P.Paint()
    end
    ns.Post.Forget()
    if not P.checked[r.key] then return P.Say(POST_SAYS.checking, "WARN") end
    if not unit then return P.Say(L["Type a price first."], "WARN") end
    if qty < 1 then return P.Say(L["Type how many to post."], "WARN") end
    -- A typed price off the step the Auction House takes (gear and recipes:
    -- whole silver) goes up to the next one, shown first, never posted unseen.
    local kind = P.Kind(r.key, r.classID)
    local bid = kind == "item" and P.edit and P.edit.bid or nil
    if kind == "item" and P.edit and P.edit.badBid then
        return P.Say(format(L["Type the starting bid like %s, or leave it empty."], P.PlainMoney(12000)), "WARN")
    end
    if bid and bid >= unit then return P.Say(L["The starting bid has to be under the price."], "WARN") end
    if bid then
        local bidStep = ns.Post.Round(bid, kind, false, r.key)
        if bidStep ~= bid then
            P.edit.bid = bidStep
            page.right.form.bid:SetText(P.PlainMoney(bidStep))
            if bidStep >= unit then return P.Say(L["The starting bid has to be under the price."], "WARN") end
            P.Say(format(L["The Auction House takes whole silver only for this item: a starting bid of %s. Click Post to post it."],
                money(bidStep)), "WARN")
            return P.Paint()
        end
    end
    local onStep = ns.Post.Round(unit, kind, false, r.key)
    if onStep ~= unit then
        P.edit = P.edit or {}
        P.edit.unit = onStep
        page.right.form.price:SetText(P.PlainMoney(onStep))
        P.Say(format(L["The Auction House takes whole silver only for this item: %s each. Click Post to post it."], money(onStep)), "WARN")
        return P.Paint()
    end
    local low = P.LowWords(r, qty, unit)
    local ask = r.key .. ":" .. qty .. ":" .. unit
    if low and asked ~= ask then
        asked = ask
        P.Say(low, "WARN")
        return P.Paint()
    end
    asked = nil
    local ok, why, detail = ns.Post.Send(r.key, qty, unit, hours, function(done, reason, said)
        busy = false
        if done then return posted(r, qty, unit) end
        P.Say(postSays(reason, said, true), "WARN")
        if reason == "failed" then   -- some of a multisell may be up: price and count are both old now
            P.checked[r.key] = nil
            ns.Post.Owned(function() refresh() end)
        end
        P.Paint()
        P.CheckNext()
    end, bid)
    if ok then
        busy = true
        P.Say(nil)
    elseif why == "confirm" then
        P.Say(L["The game asks you to look again at this price. Click Post again to post it."], "WARN")
    else
        P.Say(postSays(why, detail), "WARN")
    end
    P.Paint()
end

-- Why a price is worth a second look before it goes up, or nil: far under what
-- most others ask (P.Floor), or less than a vendor pays once the Auction House
-- takes its cut. Asked once per price; a second Post click posts it.
function P.LowWords(r, qty, unit)
    local vendor = r.itemID and ns.Items.VendorSell(r.itemID)
    if vendor and vendor * qty > floor(unit * qty * (1 - P.CUT)) then
        return format(L["A vendor pays more for it (%s each). Click Post again to post it anyway."], money(vendor))
    end
    local d = r.d
    local typed = P.edit and P.edit.unit
    if d and d.floor and not typed and unit <= d.floor then
        return format(L["That's far under what most others ask (%s). Click Post again to post it anyway."], money(d.floor))
    end
    return nil
end

-- The owned list, read once the player pauses: right after a post it would hold
-- the line while the next item's price check and Post click want it.
local owning = false
function P.OwnedSoon()
    if owning then return end
    owning = true
    local function try()
        if not ns.AH.IsOpen() then owning = false; return end
        local left = quietUntil - GetTime()
        if left > 0 or checking or busy then return C_Timer.After(math.max(left, P.GAP), try) end
        owning = false
        ns.Post.Owned(function() refresh() end)
    end
    C_Timer.After(P.QUIET, try)
end

-- ---------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------

local function checkedWords(age)
    if type(age) ~= "number" or age < 60 then return L["checked just now"] end
    return format(L["checked %s ago"], ns.Ago(age))
end

local function each(unit) return value(format(L["%s each"], money(unit))) end

-- The sentence saying why the price is what it is.
function P.WhyOf(r)
    local d = r.d
    local why
    if d.failed then return L["Couldn't check its price. Pick it again to try again."] end
    if P.edit and P.edit.unit then
        why = format(L["%s: your own price."], each(P.edit.unit))
    elseif d.saved then
        why = format(L["Saved price from %s ago. Checking the Auction House now..."], d.saved)
    elseif not d.fresh then
        why = L["Checking what it sells for right now..."]
    elseif d.mine then
        why = format(L["%s: the cheapest one up is yours, so the same price."], each(d.unit))
    elseif d.lowest then
        local by = d.lowest - d.unit
        local seen = d.lowestQty == 1 and format(L["%s, 1 of them, %s"], value(money(d.lowest)), checkedWords(d.age))
            or format(L["%s, %d of them, %s"], value(money(d.lowest)), d.lowestQty, checkedWords(d.age))
        if by > 0 then
            why = format(L["%s: %s under the cheapest one up right now (%s)."], each(d.unit), money(by), seen)
        else
            why = format(L["%s: the same as the cheapest one up right now (%s)."], each(d.unit), seen)
        end
    elseif d.unit then
        why = format(L["%s: no one else is selling it, so the usual price, the middle of the cheapest each day for the last %d days."],
            each(d.unit), P.DAYS)
    else
        why = L["No one else is selling it and it has no usual price yet. Type a price each."]
    end
    if d.far and not (P.edit and P.edit.unit) then
        why = why .. " " .. format(L["That's under half the usual price (%s)."], money(d.usual))
    end
    return why
end

-- The card: deposit, what it brings, Post and Skip.
function P.PaintBox()
    if not page then return end
    local r = P.picked and byKey[P.picked]
    if not r then return end
    local box = page.right.box
    local qty, unit, hours = P.Numbers(r)
    local deposit = qty > 0 and ns.Post.Deposit(r.key, qty, hours) or nil
    box.deposit:SetText(deposit and money(deposit) or DASH)
    Style.InkText(box.deposit, deposit and "VALUE" or "LABEL")
    local get = unit and qty > 0 and floor(unit * qty * (1 - P.CUT)) or nil
    box.get:SetText(get and money(get) or DASH)
    Style.InkText(box.get, get and "VALUE" or "LABEL")
    local c = P.checked[r.key]
    local old = c ~= nil and not c.err and GetTime() - c.at > P.FRESH
    local warned = P.Warned(r)
    local lowAsk = unit and asked == r.key .. ":" .. qty .. ":" .. unit
    local label
    if busy then label = L["Posting..."]
    elseif old then label = L["Check the price again"]
    elseif warned then label = L["The game asks: click again"]
    elseif lowAsk then label = L["Post anyway"]
    else label = format(L["Post %d"], qty) end
    box.post.text:SetText(label)
    -- off while a click would be refused: no price yet, or the Auction House busy answering
    box.post.SetOff(busy or not c or (not old and (not unit or qty < 1)) or not ns.AH.CanAct())
    Parts.Tone(box.post, (warned or lowAsk) and "no" or "main")
    box.skip.SetOff(busy)
    local key = GetBindingKey and GetBindingKey("DAYLIGHTUI_AH_ACT")
    box.key:SetText(key and format(L["or press %s"], pop(key)) or "")
    local form = page.right.form
    -- the hint follows what's typed
    local d = r.d
    local hint, role
    if P.edit and P.edit.bad then hint, role = format(L["like %s"], P.PlainMoney(12005)), "WARN"
    elseif P.edit and P.edit.unit then hint, role = L["your own price"], "LABEL"
    elseif d.failed then hint, role = L["couldn't check the price"], "WARN"
    elseif not d.fresh then hint, role = L["checking the price..."], "LABEL"
    else hint, role = d.hint, d.far and "WARN" or "LABEL" end
    form.hint:SetText(hint or "")
    Style.InkText(form.hint, role)
    local bidHint, bidRole
    if P.Kind(r.key, r.classID) ~= "item" then bidHint, bidRole = L["Stackable goods sell at their price only"], "OFF"
    elseif P.edit and P.edit.badBid then bidHint, bidRole = format(L["like %s"], P.PlainMoney(12000)), "WARN"
    elseif P.edit and P.edit.bid and unit and P.edit.bid >= unit then bidHint, bidRole = L["under the price"], "WARN"
    elseif P.edit and P.edit.bid then bidHint, bidRole = L["buyers can bid, or pay the price"], "LABEL"
    else bidHint, bidRole = L["optional: buyout only"], "LABEL" end
    form.bidHint:SetText(bidHint)
    Style.InkText(form.bidHint, bidRole)
    page.right.why:Set(P.WhyOf(r))
end

-- A click on a listing takes its price, as in the game's own window.
function P.Match(unit)
    local r = P.picked and byKey[P.picked]
    if not (r and type(unit) == "number" and unit >= 1) then return end
    hush()
    local price = ns.Post.Round(unit, P.Kind(r.key, r.classID), false, r.key)
    P.edit = P.edit or {}
    P.edit.unit, P.edit.bad = price, nil
    local box = page.right.form.price
    if box:HasFocus() then box:ClearFocus() end
    box:SetText(P.PlainMoney(price))
    ns.Post.Forget()
    P.PaintBox()
end

local function paintAH(r)
    local right = page.right
    local c = P.checked[r.key]
    local list = {}
    for _, a in ipairs(c and c.auctions or {}) do
        if type(a.unit) == "number" and a.unit >= 1 and (a.key == nil or a.key == r.key) then
            local qty = a.qty or 1
            list[#list + 1] = { kind = "line", unit = a.unit, qty = qty, own = math.min(qty, (a.own or 0) + (a.acct or 0)) }
        end
    end
    right.ah:SetRows(list)
    right.ahEmpty:SetText(not c and L["Checking..."] or c.err and L["Couldn't check its price."] or L["No one else is selling it."])
    W.EaseShown(right.ahEmpty, #list == 0)
    right.ahWhen:SetText(c and not c.err and checkedWords(GetTime() - c.at) or "")
end

local function paintDays(r, usual)
    local right = page.right
    local rkey = ns.Ruleset.Key()
    local lows = rkey and ns.Store.Lows(rkey, r.key)
    local today = ns.Market.Day(ns.Game.Now())
    local byDay = {}
    for i = 1, lows and #lows or 0, 2 do byDay[lows[i]] = lows[i + 1] end
    local days = {}
    for i = P.DAYS - 1, 0, -1 do
        days[#days + 1] = { net = byDay[today - i] or 0, ago = i }
    end
    right.days.Set(days)
    right.dayCap:SetText(usual and format(L["Usual %s is the middle of these"], money(usual)) or L["No prices seen yet"])
end

local function paintForm(r)
    local right = page.right
    local instant = not visible()
    if not r then
        right.title:SetText(#rows == 0 and L["Nothing in your bags can be sold."] or L["Pick an item on the left."])
        Style.InkText(right.title, "LABEL")
        right.meta:SetText("")
        Parts.SetItemIcon(right.icon, nil, nil)
        for _, part in ipairs({ right.form, right.box, right.why, right.lower }) do W.EaseShown(part, false, instant) end
        return
    end
    for _, part in ipairs({ right.form, right.box, right.why, right.lower }) do W.EaseShown(part, true, instant) end
    Parts.SetItemIcon(right.icon, r.icon, r.quality)
    right.title:SetText(r.name)
    local qc = { Parts.QualityColor(r.quality) }
    right.title:SetTextColor(qc[1], qc[2], qc[3])
    local d = r.d
    local meta = format(L["%d in your bags"], r.have)
    if d.usual then meta = meta .. SEP .. format(L["usual %s"], money(d.usual)) end
    right.meta:SetText(meta)
    Style.InkText(right.meta, "LABEL")

    local form = right.form
    local qty, unit, hours = P.Numbers(r)
    if not form.qty:HasFocus() then form.qty:SetText(tostring(qty)) end
    form.all.SetLabel(format(L["All %d"], r.have))
    if not form.price:HasFocus() and not (P.edit and P.edit.bad) then
        form.price:SetText(unit and P.PlainMoney(unit) or "")
    end
    for h, chip in pairs(form.chips) do chip.SetOn(h == hours) end
    local single = P.Kind(r.key, r.classID) == "item"
    W.EaseShown(form.bid, single, instant)
    if not form.bid:HasFocus() and not (P.edit and P.edit.badBid) then
        local bid = P.edit and P.edit.bid
        form.bid:SetText(bid and P.PlainMoney(bid) or "")
    end
    local c = P.checked[r.key]
    if c and not c.err then watchAge(r.key, c) end
    P.PaintBox()
    paintAH(r)
    paintDays(r, d.usual)
end

local function sectionValue(h)
    if h.total > 0 then
        local s = money(h.total)
        if h.checking > 0 then s = s .. " " .. format(L["+ %d checking"], h.checking) end
        return s
    end
    if h.checking > 0 then return format(L["%d checking"], h.checking) end
    return L["no price yet"]
end

local function lineTip(b)
    local r = b.lineSpec and b.lineSpec.row
    if not (r and r.itemID and GameTooltip) then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    ns.Items.SetTip(GameTooltip, r.key, r.itemID)
    GameTooltip:Show()
end

function P.FillList()
    local stack = page.left.stack
    local at = stack:Scrolled()
    local spots = visible() and stack:Spots() or nil
    lines = {}
    stack:Begin()
    local shown = P.Headings()
    if #shown == 0 then
        stack:Text(L["Nothing in your bags can be sold."], { size = Style.SIZE.body, color = Style.INK.LABEL })
    end
    for _, h in ipairs(shown) do
        stack:Section(h.name, {
            value = not h.hidden and sectionValue(h) or nil,
            action = not h.hidden and { text = L["Sell all"], onClick = function() P.SellAll(h.id, h.name) end } or nil,
            lit = P.selling ~= nil and P.selling.id == h.id,
        })
        for _, r in ipairs(h.rows) do
            lines[r.key] = stack:Line({
                id = r.key, row = r, icon = r.icon, text = r.name,
                color = h.hidden and Style.INK.OFF or { Parts.QualityColor(r.quality) },
                sub = P.SubOf(r), value = r.worth and money(r.worth) or DASH,
                valueColor = r.worth and Style.INK.MONEY or Style.INK.LABEL,
                picked = P.picked == r.key, tooltip = lineTip,
                link = function() return ns.Items.Hyperlink(r.key) end,
                onClick = function() P.Pick(r.key, true) end,
                onRightClick = function(b) P.LineMenu(r, b) end,
            })
        end
    end
    stack:End()
    stack:ScrollTo(at)
    if spots then stack:Ease(spots) end
end

-- A line's right-click: pin it on top, or hide it at the bottom of the list.
function P.LineMenu(r, owner)
    local pinned, hidden = P.IsPinned(r.key), P.IsHidden(r.key)
    W.OpenMenu(owner, { "pin", "hide" }, {
        pin = pinned and L["Unpin"] or L["Pin to the top"],
        hide = hidden and L["Show in the list again"] or L["Hide from the list"],
    }, nil, function(k)
        hush()
        if k == "pin" then
            ns.DB.Table("sellPinned")[r.key] = (not pinned) or nil
            if not pinned then ns.DB.Table("sellHidden")[r.key] = nil end
        else
            ns.DB.Table("sellHidden")[r.key] = (not hidden) or nil
            if not hidden then ns.DB.Table("sellPinned")[r.key] = nil end
        end
        P.Paint()
    end, nil, { atCursor = true })
end

-- The line under the form: the latest notice in its role's color.
function P.PaintSaid()
    if not page then return end
    local m = P.message
    page.right.said:SetText(m and (Parts.Hex(Style.INK[m.role] or Style.INK.GOOD) .. m.text .. "|r") or "")
end

function P.Paint()
    if not page then return end
    local at = ns.AH.IsOpen()
    local instant = not visible()
    W.EaseShown(page.left, at, instant)
    W.EaseShown(page.right, at, instant)
    W.EaseShown(page.note, not at, instant)
    if not at then return end
    P.Rows()
    local gone = P.picked and not byKey[P.picked] and P.picked or nil
    if gone then P.picked = nil end
    if not P.picked then
        local first = P.Order()[1]
        if gone and P.selling then   -- the heading being sold goes on inside itself
            first = nextAfter(gone)
            if not first then
                P.message = { text = format(L["That was the last of %s."], P.selling.name), role = "GOOD" }
                P.selling = nil
                first = P.Order()[1]
            end
        end
        P.picked = first and first.key
        P.edit = nil
        ns.Post.Forget()
    end
    P.FillList()
    paintForm(P.picked and byKey[P.picked])
    P.PaintSaid()
end

-- ---------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------

local function label(parent, text, y)
    local fs = Style.Text(parent, Style.SIZE.small, "LEFT")
    Style.InkText(fs, "LABEL")
    fs:SetText(text)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y - 7)
    return fs
end

local function buildForm(right, sale)
    local form = CreateFrame("Frame", nil, sale)
    form:SetPoint("TOPLEFT", right, "TOPLEFT", Parts.EDGE, -P.FORM_TOP)
    form:SetPoint("RIGHT", right, "RIGHT", -(P.BOX_W + 2 * Parts.EDGE), 0)
    form:SetHeight(4 * P.FORM_STEP)
    label(form, L["How many"], 0)
    form.qty = W.Input(form, { numeric = true, justify = "CENTER", onChange = function(text, user) typed("qty", text, user) end })
    form.qty:SetWidth(64)
    W.PadNumber(form.qty, function(dir)
        local r = P.picked and byKey[P.picked]
        if not r then return end
        local n = (P.edit and P.edit.qty) or tonumber(form.qty:GetText()) or 0
        n = math.max(1, math.min(r.have or 1, n + dir))
        form.qty:SetText(tostring(n))
        typed("qty", tostring(n), true)
    end)
    form.qty:SetPoint("TOPLEFT", form, "TOPLEFT", P.LABEL_W, 0)
    form.all = W.Link(form)
    form.all:SetPoint("LEFT", form.qty, "RIGHT", 10, 0)
    form.all:SetScript("OnClick", function()
        local r = P.picked and byKey[P.picked]
        if not r then return end
        if form.qty:HasFocus() then form.qty:ClearFocus() end
        P.edit = P.edit or {}
        P.edit.qty = r.have
        hush()
        form.qty:SetText(tostring(r.have))
        P.PaintBox()
    end)
    label(form, L["Price each"], P.FORM_STEP)
    form.price = W.Input(form, { hint = P.PlainMoney(12005), onChange = function(text, user) typed("price", text, user) end })
    form.price:SetWidth(120)
    W.PadNumber(form.price, function(dir)
        local text = P.PlainMoney(P.StepMoney(P.ReadMoney(form.price:GetText()), dir, 1))
        form.price:SetText(text)
        typed("price", text, true)
    end)
    form.price:SetPoint("TOPLEFT", form, "TOPLEFT", P.LABEL_W, -P.FORM_STEP)
    form.hint = Style.Text(form, Style.SIZE.small, "LEFT")
    -- the right end on the price line itself: the form's own middle is a line lower
    form.hint:SetPoint("LEFT", form.price, "RIGHT", 10, 0)
    form.hint:SetPoint("RIGHT", form, "TOPRIGHT", 0, -(P.FORM_STEP + W.INPUT_H / 2))
    form.hint:SetWordWrap(false)
    label(form, L["How long"], 2 * P.FORM_STEP)
    form.chips = {}
    local x = P.LABEL_W
    for _, h in ipairs(ns.Post.HOURS) do
        local chip = W.Chip(form, format(L["%d h"], h))
        chip.FitWidth()
        chip:SetPoint("TOPLEFT", form, "TOPLEFT", x, -(2 * P.FORM_STEP + 1))
        chip:SetScript("OnClick", function()
            hush()
            for k, other in pairs(form.chips) do other.SetOn(k == h) end
            if P.Hours() ~= h then DUI:Set("AuctionHouse", "hours", h) end
            ns.Post.Forget()
            P.PaintBox()
        end)
        x = x + chip:GetWidth() + W.CHIP_GAP
        form.chips[h] = chip
    end
    label(form, L["Starting bid"], 3 * P.FORM_STEP)
    form.bid = W.Input(form, { hint = L["none"], onChange = function(text, user) typed("bid", text, user) end })
    form.bid:SetWidth(120)
    W.PadNumber(form.bid, function(dir)
        local c = P.StepMoney(P.ReadMoney(form.bid:GetText()), dir)
        local text = c > 0 and P.PlainMoney(c) or ""
        form.bid:SetText(text)
        typed("bid", text, true)
    end)
    form.bid:SetPoint("TOPLEFT", form, "TOPLEFT", P.LABEL_W, -3 * P.FORM_STEP)
    form.bidHint = Style.Text(form, Style.SIZE.small, "LEFT")
    form.bidHint:SetPoint("LEFT", form.bid, "RIGHT", 10, 0)
    form.bidHint:SetPoint("RIGHT", form, "TOPRIGHT", 0, -(3 * P.FORM_STEP + W.INPUT_H / 2))
    form.bidHint:SetWordWrap(false)
    right.form = form
end

-- A label and its amount. `under` puts the amount on its own line below the
-- label: a long label beside an amount in gold left no room for both.
local function boxLine(box, text, y, size, under)
    local l = Style.Text(box, Style.SIZE.small, "LEFT")
    Style.InkText(l, "LABEL")
    l:SetText(text)
    l:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -y)
    local v = Style.Text(box, size or Style.SIZE.body, "RIGHT")
    if under then
        v:SetPoint("TOPRIGHT", box, "TOPRIGHT", -12, -y - Style.SIZE.small - 3)
    else
        v:SetPoint("BOTTOMRIGHT", box, "TOPRIGHT", -12, -y - Style.SIZE.small - 1)
    end
    v:SetWordWrap(false)
    v.label = l
    return v
end

local function buildBox(right)
    local box = CreateFrame("Frame", nil, right)
    box:SetPoint("TOPRIGHT", right, "TOPRIGHT", -Parts.EDGE, -14)
    box:SetSize(P.BOX_W, P.BOX_H)
    Style.Shell(box, {})
    box.deposit = boxLine(box, L["Deposit"], 14)
    box.get = boxLine(box, L["You get when it sells"], 38, Style.SIZE.head, true)
    box.post = W.Button(box, L["Post"], 30)
    box.post:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -76)
    box.post:SetPoint("RIGHT", box, "RIGHT", -84, 0)
    Parts.Tone(box.post, "main")
    box.post:SetScript("OnClick", function() P.Post() end)
    box.skip = W.Button(box, L["Skip"], 30)
    box.skip:SetPoint("TOPLEFT", box.post, "TOPRIGHT", 6, 0)
    box.skip:SetPoint("RIGHT", box, "RIGHT", -12, 0)
    box.skip:SetScript("OnClick", function() P.Skip() end)
    box.key = Style.Text(box, Style.SIZE.small, "CENTER")
    Style.InkText(box.key, "LABEL")
    box.key:SetPoint("TOP", box, "TOP", 0, -114)
    right.box = box
end

local function fillAH(b, d, cols)
    local c = cols.unit
    b.unit:ClearAllPoints()
    b.unit:SetPoint("LEFT", b, "LEFT", c.x + 4, 0)
    b.unit:SetText(money(d.unit))
    local q = cols.qty
    b.qty:ClearAllPoints()
    b.qty:SetPoint("RIGHT", b, "LEFT", q.x + q.w, 0)
    b.qty:SetText(tostring(d.qty))
    Style.InkText(b.qty, "pop")
    local m = cols.mine
    b.mine:ClearAllPoints()
    b.mine:SetPoint("LEFT", b, "LEFT", m.x + 10, 0)
    if d.own > 0 then
        b.mine.Set(d.own >= d.qty and L["yours"] or format(L["%d yours"], d.own), { Style.Pop() })
        b.mine:Show()
    else
        b.mine:Hide()
    end
end

-- A small spaced heading over one half of the lower part (Stack:Section's
-- look), and a few words at its right end. Returns those words' text.
local function heading(parent, text, right)
    local hold = CreateFrame("Frame", nil, parent)
    hold:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    hold:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    hold:SetHeight(40)
    local s = Parts.Stack(hold, { top = 6, bottom = 0 })
    s:Begin(); s:Section(text); s:End()
    local fs = Style.Text(parent, Style.SIZE.tiny, "RIGHT")
    Style.InkText(fs, "LABEL")
    fs:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -Parts.EDGE, -14)
    fs:SetText(right or "")
    return fs
end

local function buildLower(right)
    local lower = CreateFrame("Frame", nil, right)
    lower:SetPoint("TOPLEFT", right, "TOPLEFT", 0, -P.LOWER_TOP)
    lower:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 0, 0)
    local rule = Parts.Rule(lower)
    rule:SetPoint("TOPLEFT", lower, "TOPLEFT", Parts.EDGE, 0)
    rule:SetPoint("TOPRIGHT", lower, "TOPRIGHT", -Parts.EDGE, 0)
    local left = CreateFrame("Frame", nil, lower)
    left:SetPoint("TOPLEFT", lower, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMRIGHT", lower, "BOTTOM", 30, 0)
    local divider = Parts.Rule(lower, true)
    divider:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, -12)
    divider:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 0, 12)
    local days = CreateFrame("Frame", nil, lower)
    days:SetPoint("TOPLEFT", left, "TOPRIGHT", 1, 0)
    days:SetPoint("BOTTOMRIGHT", lower, "BOTTOMRIGHT", 0, 0)

    right.ahWhen = heading(left, L["On the Auction House now"])
    right.ah = Parts.Table(left, {
        head = P.AH_COLS, top = 44, bottom = 8,
        rowHeight = { line = 26 },
        make = { line = function(b)
            b.unit = Style.Text(b, Style.SIZE.body, "LEFT")
            b.qty = Style.Text(b, Style.SIZE.body, "RIGHT")
            b.mine = W.Tag(b)
        end },
        fill = { line = fillAH },
        onClick = function(_, d) P.Match(d.unit) end,
    })
    right.ahEmpty = Style.Text(left, Style.SIZE.body, "CENTER")
    Style.InkText(right.ahEmpty, "LABEL")
    right.ahEmpty:SetPoint("CENTER", right.ah.view, "CENTER", 0, 0)

    heading(days, L["Cheapest each day"], format(L["last %d days"], P.DAYS))
    right.days = W.DayBars(days, P.DAY_H, { tip = function(day)
        if not (day and DUI.Tips) then return end
        local when = day.ago == 0 and L["Today"] or format(day.ago == 1 and L["%d day ago"] or L["%d days ago"], day.ago)
        DUI.Tips.Title(when)
        DUI.Tips.Line(L["Cheapest"], (day.net or 0) > 0 and money(day.net) or L["not seen"])
    end })
    right.days:SetPoint("TOPLEFT", days, "TOPLEFT", Parts.EDGE, -44)
    right.days:SetPoint("TOPRIGHT", days, "TOPRIGHT", -Parts.EDGE, -44)
    local function cap(text, point)
        local fs = Style.Text(days, Style.SIZE.small, point)
        Style.InkText(fs, "LABEL")
        fs:SetText(text)
        fs:SetPoint("TOP" .. point, right.days, "BOTTOM" .. point, 0, -6)
        return fs
    end
    cap(L["2 weeks ago"], "LEFT")
    cap(L["today"], "RIGHT")
    -- Its own line: with a price in gold it doesn't fit between the two ends.
    right.dayCap = Style.Text(days, Style.SIZE.small, "CENTER")
    Style.InkText(right.dayCap, "LABEL")
    right.dayCap:SetPoint("TOP", right.days, "BOTTOM", 0, -24)
    right.lower = lower
end

function P.Build(p)
    page = p
    P.page = p
    local left = CreateFrame("Frame", nil, p)
    left:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 0)
    left:SetWidth(P.LEFT_W)
    p.left = left
    local rule = Parts.Rule(left, true)
    rule:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, -12)
    rule:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 0, 12)
    local from = Style.Text(left, Style.SIZE.small, "LEFT")
    Style.InkText(from, "LABEL")
    from:SetText(L["From your bags"])
    from:SetPoint("TOPLEFT", left, "TOPLEFT", Parts.EDGE, -16)
    left.stack = Parts.Stack(left, { top = P.LIST_TOP, bottom = 12 })

    local right = CreateFrame("Frame", nil, p)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 1, 0)
    right:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
    p.right = right
    -- The picked item's name and form, faded together when the next one is picked.
    local sale = CreateFrame("Frame", nil, right)
    sale:SetAllPoints(right)
    right.sale = sale
    right.icon = CreateFrame("Frame", nil, sale)
    right.icon:SetSize(P.ICON, P.ICON)
    right.icon:SetPoint("TOPLEFT", right, "TOPLEFT", Parts.EDGE, -14)
    Parts.ItemIcon(right.icon, P.ICON)
    right.icon.edge:SetPoint("CENTER", right.icon, "CENTER", 0, 0)
    right.title = Style.Text(sale, Style.SIZE.head, "LEFT")
    right.title:SetPoint("TOPLEFT", right, "TOPLEFT", Parts.EDGE + P.ICON + 12, -17)
    right.title:SetPoint("RIGHT", right, "RIGHT", -(P.BOX_W + 2 * Parts.EDGE), 0)
    right.title:SetWordWrap(false)
    right.meta = Style.Text(sale, Style.SIZE.small, "LEFT")
    Style.InkText(right.meta, "LABEL")
    right.meta:SetPoint("TOPLEFT", right.title, "BOTTOMLEFT", 0, -4)
    right.meta:SetPoint("RIGHT", right, "RIGHT", -(P.BOX_W + 2 * Parts.EDGE), 0)
    right.meta:SetWordWrap(false)
    -- Hovering the picked item's icon or name shows its tooltip, like its row on the left.
    local head = CreateFrame("Frame", nil, sale)
    head:SetPoint("TOPLEFT", right.icon, "TOPLEFT", 0, 0)
    head:SetPoint("BOTTOMLEFT", right.icon, "BOTTOMLEFT", 0, 0)
    head:SetPoint("RIGHT", right.title, "RIGHT", 0, 0)
    head:EnableMouse(true)
    head:SetScript("OnEnter", Parts.ItemTip(function(self)
        local r = P.picked and byKey[P.picked]
        if not (r and r.itemID and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        ns.Items.SetTip(GameTooltip, r.key, r.itemID)
        GameTooltip:Show()
    end))
    head:SetScript("OnLeave", function(self)
        self.UpdateTooltip = nil
        if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    right.head = head
    buildForm(right, sale)
    buildBox(right)
    right.said = Style.Text(right, Style.SIZE.small, "LEFT")
    right.said:SetPoint("TOPLEFT", right, "TOPLEFT", Parts.EDGE, -P.SAID_TOP)
    right.said:SetPoint("RIGHT", right, "RIGHT", -Parts.EDGE, 0)
    right.said:SetWordWrap(false)
    right.why = Parts.Why(right)
    right.why:SetPoint("TOPLEFT", right, "TOPLEFT", Parts.EDGE, -P.WHY_TOP)
    right.why:SetPoint("RIGHT", right, "RIGHT", -Parts.EDGE, 0)
    buildLower(right)

    local note = Style.Text(p, Style.SIZE.body, "CENTER")
    Style.InkText(note, "LABEL")
    note:SetPoint("CENTER", p, "CENTER", 0, 0)
    note:SetText(L["Open the Auction House to sell."])
    p.note = note
    P.Paint()
end

-- Each time the tab shows: what changed while it was hidden, and the checks go on.
function P.Fill()
    if not page then return end
    if ns.AH.IsOpen() and not ownedRead then
        if ns.Post.ReadAt() then
            ownedRead = true   -- read as the Auction House opened
        else
            ns.Post.Owned(function(list) if list then ownedRead = true; refresh() end end)
        end
    end
    P.Paint()
    C_Timer.After(0, P.CheckNext)   -- once the page shows (Win.ShowPage fills it first)
end

-- The key binding: the Post button, in the key press.
function P.Key()
    if visible() and ns.AH.IsOpen() then P.Post() end
end

-- The Post button while it shows on this page, for the controller's X.
function P.PostButton()
    local b = page and page.right and page.right.box and page.right.box.post
    if b and visible() and b:IsVisible() then return b end
end

local function forget()
    P.checked, checking, busy, ownedRead, kinds, takes = {}, nil, false, false, {}, {}
    checkingID, checkingFn, postedKeys, asked = nil, nil, {}, nil
    P.message, P.selling, P.edit = nil, nil, nil
end

ns.On("BagsChanged", function()
    kinds, takes = {}, {}
    if visible() then refresh() end
end)
ns.On("PricesChanged", function() if visible() then refresh() end end)
ns.On("OwnedChanged", function() if visible() then refresh() end end)
-- A Post click that would have been refused can go now (or no longer can).
ns.On("LineChanged", function() if visible() then P.PaintBox() end end)
ns.On("RulesetChanged", function()
    P.checked = {}   -- every price was read against the old ruleset's
    if visible() then
        refresh()
        C_Timer.After(0, P.CheckNext)
    end
end)
ns.On("AHOpened", function()
    forget()
    if visible() then P.Fill() end
end)
ns.On("AHClosed", function()
    forget()
    if visible() then refresh() end
end)
DUI.On("StyleChanged", function() if visible() then refresh() end end)
ns.RegisterEvent("ITEM_DATA_LOAD_RESULT", function()
    if waitingInfo and visible() then refresh() end
end)
