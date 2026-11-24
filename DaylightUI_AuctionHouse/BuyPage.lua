-- The Buy tab: the game's categories, recent searches and favorites on the
-- left; the search box (with suggestions from items already seen), the
-- filter row, one row per item cheapest first, and the footer that buys.
--
-- Searches run on Enter, a category, a chip, the filter menu or a level box
-- (Enter or leaving it), never per keystroke: typing only drives the
-- suggestions. Each search is one ns.Browse.Query; only the newest one's rows
-- ever show (ns.AH.Drop drops the one before it).
--
-- Picking a row searches that item (ns.Search.Item) and glides its price
-- steps and a why in under it (Parts.Table:Open, NORMAL); picking another
-- first glides the old one shut. Buying follows the game's own UI (Buy.lua):
-- a commodity takes two clicks ("Buy 60" asks the game for a quote, "Confirm
-- <total>" buys what the player saw), gear one. A price over Buy.SAFETY % of
-- usual asks once more ("311% of usual: click again"). Every purchase call
-- runs inside the button's click.
--
-- Usual here is the usual price from the days before today (Store.Prior): a
-- browse records today's cheapest before its rows are made, so a usual with
-- today in it would judge a deal against itself. An item first seen today
-- falls back to the usual with today in it.
--
-- Saved account-wide in DaylightUIAuctionDB: `recent` (the last searches and
-- categories, newest first) and `favorites` (itemIDs).

local _, ns = ...
local DUI = DaylightUI
local L = ns.L
local Win = DUI.Win
local Style = DUI.Style
local W = DUI.Widgets
local Parts = Win.Parts
local Motion = DUI.Motion

local BP = {}
ns.BuyPage = BP

BP.LEFT_W = 250
BP.CHIP_Y = 12
BP.LEFT_TOP = 44
BP.BOX_TOP = 11       -- 26 tall beside the 24 tall chips: a pixel higher, centers level
BP.FILTER_TOP = 45
BP.TABLE_TOP = 80
BP.FOOT = 52
BP.STEP_H = 26
BP.ICON = 28          -- the item icon; its outline makes it 30
BP.ICON_X = 44        -- the item name starts after its icon
BP.STEP_X = 48
BP.LEVEL_W = 40
BP.QTY_W = 52
BP.BID_W = 100       -- the bid amount box
BP.PRICE_W = 96      -- the max price box
BP.DEAL = 70          -- a % at or under this is a deal (INK.GOOD), until the settings are read
BP.RECENT_MAX = 10
-- One double-click guard for every button (W.CONFIRM_GAP, 0.25 s)
BP.CONFIRM_WAIT = W.CONFIRM_GAP   -- s a Confirm click is refused after a held total changes
BP.DOUBLE = W.CONFIRM_GAP         -- s after the Buy click a Confirm click is taken for the double-click's second half
BP.PRICE_JUMP = 5     -- % a quote may be over what the list showed before it's refused, as the game's own dialog does
BP.SPREAD = 50        -- % the dearest price bought may be over the cheapest before Confirm says so
BP.QUOTE_SHOW = 10    -- s left on a held quote from which the Confirm button counts down
BP.SUGGEST_MAX = 8
BP.ROOM_GAP = 12      -- under the first-visit card

local SEP = "  \194\183  "
local DASH = "\226\128\147"

BP.COLS = {
    { id = "name", text = L["Item"], fill = true, sort = true },
    { id = "level", text = L["Lvl"], width = 40, justify = "RIGHT", sort = true },
    { id = "qty", text = L["Qty"], width = 54, justify = "RIGHT", sort = true },
    { id = "unit", text = L["Price each"], width = 92, justify = "RIGHT", sort = true },
    { id = "usual", text = L["Usual"], width = 92, justify = "RIGHT", sort = true },
    { id = "pct", text = "%", width = 52, justify = "RIGHT", sort = true },
}
local NUMBERS = { "level", "qty", "unit", "usual", "pct" }
local STEP_CELLS = { "qty", "unit", "pct" }

-- What the page shows (tests read it): the search on screen, its rows, the
-- open row, the picked gear step, the row to open once the old one glided
-- shut, the held quote, a purchase on its way, the footer's sentence.
BP.state = {
    query = nil, rows = {}, all = {}, seen = {}, running = false, problem = nil, capped = nil, gen = 0,
    open = nil, step = nil, pending = nil, closeDone = nil, opening = nil,
    quote = nil, buying = false, tell = nil, amount = 1, amountOf = nil, amountSet = false,
    want = nil, sort = { id = "unit", desc = false },
    filters = { minLevel = nil, maxLevel = nil, usable = false, picked = {}, maxPrice = nil },
}
local S = BP.state

local page   -- the page frame, set by Build
local hint   -- why the main buy is off, for the stat line
local Left   -- the left pane, below

local function hex(c) return Parts.Hex(c) end
local function value(text) return hex(Style.INK.VALUE) .. text .. "|r" end
local function pop(text) return hex({ Style.Pop() }) .. text .. "|r" end
local function money(c) return W.Money(c, { pad = true }) end
local function plainMoney(c) return ns.SellPage.PlainMoney(c) end
local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function animated(region) return region ~= nil and region:IsVisible() and Motion.On() end

-- Shows or hides with a quick fade while it's on screen; leaving = fading out.
local function ease(region, on)
    region.buyLeaving = (not on) or nil
    W.EaseShown(region, on, not animated(region))
end
local function showing(region) return region:IsShown() and not region.buyLeaving end

local function nameOf(d) return d.name or string.format(L["Item %d"], d.itemID or 0) end

-- ---------------------------------------------------------------------
-- Saved: the recent searches and the favorites
-- ---------------------------------------------------------------------

local function saved(field)
    local root = ns.DB.Prices()
    if type(root[field]) ~= "table" then root[field] = {} end
    return root[field]
end

function BP.Recent()
    local list, out = saved("recent"), {}
    for _, e in ipairs(list) do
        if type(e) == "table" and (type(e.text) == "string" or type(e.path) == "string") then out[#out + 1] = e end
    end
    return out
end

local function sameSearch(a, b)
    if not (a and b) then return false end
    return a.path == b.path and string.lower(a.text or "") == string.lower(b.text or "")
end

local function remember(q)
    if q.favorites or (not q.path and trim(q.text) == "") then return end
    local list = saved("recent")
    for i = #list, 1, -1 do
        if type(list[i]) ~= "table" or sameSearch(list[i], q) then table.remove(list, i) end
    end
    local text = trim(q.text)
    table.insert(list, 1, { text = text ~= "" and text or nil, path = q.path, label = q.label })
    for i = #list, BP.RECENT_MAX + 1, -1 do list[i] = nil end
end

-- Empties the recent searches or the favorites (from the options), and the
-- left pane if it shows that list.
function BP.Forget(field)
    if field ~= "recent" and field ~= "favorites" then return end
    ns.DB.Prices()[field] = {}
    if Left and Left.mode == field then Left.Fill(true) end
end

function BP.Favorites()
    local out = {}
    for _, id in ipairs(saved("favorites")) do
        if type(id) == "number" then out[#out + 1] = id end
    end
    return out
end

function BP.IsFavorite(itemID)
    for _, id in ipairs(saved("favorites")) do if id == itemID then return true end end
    return false
end

-- Kept here and in the game's own favorites (account-wide on its server), so
-- a star set in either window shows in both. itemKey: the result's own.
function BP.SetFavorite(itemID, on, itemKey)
    if type(itemID) ~= "number" then return end
    local list = saved("favorites")
    for i = #list, 1, -1 do if list[i] == itemID then table.remove(list, i) end end
    if on then table.insert(list, 1, itemID) end
    local api = C_AuctionHouse
    if not (ns.AH.IsOpen() and api and api.SetFavoriteItem) then return end
    if api.FavoritesAreAvailable and api.FavoritesAreAvailable() ~= true then return end
    if on and api.HasMaxFavorites and api.HasMaxFavorites() == true then return end
    local key = type(itemKey) == "table" and itemKey or (api.MakeItemKey and api.MakeItemKey(itemID))
    if key then api.SetFavoriteItem(key, on == true) end
end

-- The game's favorites a favorites search found, added to the list here
-- (stars set in the game's own window, or on another computer).
local function learnFavorites(rows)
    local list = saved("favorites")
    local have = {}
    for _, id in ipairs(list) do have[id] = true end
    for _, r in ipairs(rows) do
        if type(r.itemID) == "number" and not have[r.itemID] then
            have[r.itemID] = true
            list[#list + 1] = r.itemID
        end
    end
end

-- ---------------------------------------------------------------------
-- The game's categories (its global AuctionCategories, filled when the game
-- loads its Auction House UI: the first time the AH opens)
-- ---------------------------------------------------------------------

local Cat = {}
BP.Categories = Cat
local tree, byWord, builtFrom

local function wordOf(name)
    return (string.gsub(string.gsub(string.lower(name), "[%s/;]+", "-"), "^%-+", ""))
end

local function copyFilters(list)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, f in ipairs(list) do
        if type(f) == "table" and type(f.classID) == "number" then
            out[#out + 1] = { classID = f.classID, subClassID = f.subClassID, inventoryType = f.inventoryType }
        end
    end
    return out
end

-- The WoW Token has nothing to browse.
local function isToken(c)
    local label = _G.TOKEN_FILTER_LABEL
    return c.isToken == true or (type(label) == "string" and c.name == label)
end

local function buildTree(list, parentPath, top)
    local nodes, index = {}, {}
    if type(list) ~= "table" then return nodes, index end
    for _, c in ipairs(list) do
        if type(c) == "table" and type(c.name) == "string" and c.name ~= "" and not (top and isToken(c)) then
            local word = wordOf(c.name)
            if word ~= "" and not index[word] then
                local path = {}
                for i, w in ipairs(parentPath) do path[i] = w end
                path[#path + 1] = word
                local node = { name = c.name, word = word, path = path, filters = copyFilters(c.filters),
                    implicitFilter = type(c.implicitFilter) == "number" and c.implicitFilter or nil }
                node.children, node.byWord = buildTree(c.subCategories, path, false)
                nodes[#nodes + 1] = node
                index[word] = node
            end
        end
    end
    return nodes, index
end

-- The tree, nil until the game's AuctionCategories exists.
function Cat.Tree()
    local src = _G.AuctionCategories
    if src == builtFrom and tree then return tree end
    if type(src) ~= "table" or #src == 0 then return nil end
    tree, byWord = buildTree(src, {}, true)
    builtFrom = src
    return tree
end

-- The node a path ("trade-goods/cloth") names, nil when it's gone.
function Cat.Find(path)
    if type(path) ~= "string" or not Cat.Tree() then return nil end
    local node, nodes = nil, byWord
    for word in string.gmatch(path, "[^/]+") do
        node = nodes and nodes[word]
        if not node then return nil end
        nodes = node.byWord
    end
    return node
end

function Cat.Path(node) return table.concat(node.path, "/") end

-- "Trade Goods / Cloth", in the game's own words.
function Cat.Label(node)
    local names, nodes = {}, byWord
    for k, word in ipairs(node.path) do
        local at = nodes and nodes[word]
        names[k] = at and at.name or word
        nodes = at and at.byWord
    end
    return table.concat(names, " / ")
end

-- ---------------------------------------------------------------------
-- Suggestions while typing: names of the items the ruleset has seen
-- ---------------------------------------------------------------------

-- A sorted index { lower, name, itemID }, built a slice a frame (a ruleset
-- can know 30,000 items: never in one frame), each slice sorted on its own,
-- then merged pairwise a budget a frame. Until a build is done the last
-- complete index serves. It's rebuilt when the ruleset knows a different
-- number of items. Only names the game already holds go in; one it hadn't
-- loaded is added when it arrives (its item event), never by asking for it or
-- building again: asking for thousands of names made the game itself stall
-- while typing.
local index = { rkey = nil, n = -1, entries = {}, missing = {}, builtAt = 0 }
BP.nameIndex = index
local build
BP.MERGE_BUDGET = 8000
BP.CONTAINS_LOOKED = 2000
BP.INDEX_SLICE = 100      -- names looked up a frame while building: each unknown one is a load for the game

local function byLower(a, b) return a[1] < b[1] end

local function merge(a, b)
    local out, i, j, na, nb = {}, 1, 1, #a, #b
    while i <= na and j <= nb do
        if a[i][1] <= b[j][1] then out[#out + 1] = a[i]; i = i + 1
        else out[#out + 1] = b[j]; j = j + 1 end
    end
    for k = i, na do out[#out + 1] = a[k] end
    for k = j, nb do out[#out + 1] = b[k] end
    return out
end

local function buildStep(job)
    if build ~= job then return end
    local keys = job.keys
    if job.pos <= #keys then
        local chunk = {}
        local last = math.min(job.pos + BP.INDEX_SLICE - 1, #keys)
        local cached = C_Item and C_Item.IsItemDataCachedByID
        for k = job.pos, last do
            local id = ns.Items.ID(keys[k])
            -- only names the game already holds: asking for one it doesn't makes it load
            -- the item, and thousands of those stall the game while the player types
            local name = id and (not cached or cached(id)) and ns.Items.Name(id) or nil
            if name then chunk[#chunk + 1] = { string.lower(name), name, id }
            elseif id then job.missing[id] = true end
        end
        job.pos = last + 1
        table.sort(chunk, byLower)
        job.runs[#job.runs + 1] = chunk
    elseif #job.runs > 1 then
        local done, nextRuns, r, k = 0, {}, job.runs, 1
        while k <= #r do
            if done >= BP.MERGE_BUDGET or k == #r then
                for m = k, #r do nextRuns[#nextRuns + 1] = r[m] end
                break
            end
            nextRuns[#nextRuns + 1] = merge(r[k], r[k + 1])
            done = done + #r[k] + #r[k + 1]
            k = k + 2
        end
        job.runs = nextRuns
    else
        local list, out = job.runs[1] or {}, {}
        for k = 1, #list do
            if k == 1 or list[k][1] ~= list[k - 1][1] then out[#out + 1] = list[k] end
        end
        index.rkey, index.entries, index.n, index.missing = job.rkey, out, job.n, job.missing
        index.builtAt = GetTime()
        build = nil
        if page and page.complete and page.box:HasFocus() then page.complete:Refresh() end
        return
    end
    C_Timer.After(0, function() buildStep(job) end)
end

-- Starts a build when the index is out of date; never builds in the call.
local function ensureIndex(rkey)
    if build and build.rkey ~= rkey then build = nil end
    if build then return end
    local n = ns.Store.Count(rkey)
    if rkey == index.rkey and n == index.n then return end
    local keys = {}
    local items = ns.Store.Items(rkey)
    for key in pairs(items or {}) do
        if not string.find(key, ":", 1, true) then keys[#keys + 1] = key end
    end
    local job = { rkey = rkey, keys = keys, pos = 1, runs = {}, missing = {}, n = n }
    build = job
    C_Timer.After(0, function() buildStep(job) end)
end

-- A name the index was missing, now loaded: put in its sorted place.
function BP.IndexLearn(itemID)
    if not index.missing[itemID] then return end
    local name = ns.Items.Name(itemID)
    if not name then return end
    index.missing[itemID] = nil
    local lower, e = string.lower(name), index.entries
    local lo, hi = 1, #e + 1
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if e[mid][1] < lower then lo = mid + 1 else hi = mid end
    end
    if e[lo] and e[lo][1] == lower then return end
    table.insert(e, lo, { lower, name, itemID })
end

-- W.Complete's suggest: names that start with what's typed, then names that
-- contain it (that part in the accent), the item's class on the right. A name
-- typed in full suggests nothing, so Enter searches.
function BP.Suggest(text)
    local typed = string.lower(trim(text))
    if #typed < 2 then return nil end
    local rkey = ns.Ruleset.Key()
    if not rkey then return nil end
    ensureIndex(rkey)
    if index.rkey ~= rkey then return nil end
    local e = index.entries
    local lo, hi = 1, #e + 1
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if e[mid][1] < typed then lo = mid + 1 else hi = mid end
    end
    if e[lo] and e[lo][1] == typed then return nil end
    local list, seen = {}, {}
    local function add(ent, label)
        seen[ent[1]] = true
        local info = ns.Items.Info(ent[3], true)
        list[#list + 1] = { insert = ent[2], from = 1, to = #text, label = label or ent[2],
            note = info and ns.Items.ClassName(info.classID) or nil }
    end
    local k = lo
    while k <= #e and #list < BP.SUGGEST_MAX and string.sub(e[k][1], 1, #typed) == typed do
        add(e[k])
        k = k + 1
    end
    local accent = hex({ Style.Accent() })
    for j = 1, math.min(#e, BP.CONTAINS_LOOKED) do
        if #list >= BP.SUGGEST_MAX then break end
        local ent = e[j]
        local at = not seen[ent[1]] and string.find(ent[1], typed, 1, true)
        if at then
            local name = ent[2]
            add(ent, string.sub(name, 1, at - 1) .. accent .. string.sub(name, at, at + #typed - 1) .. "|r"
                .. string.sub(name, at + #typed))
        end
    end
    return list
end

-- ---------------------------------------------------------------------
-- Searching: the game's browse query, one row per item
-- ---------------------------------------------------------------------

-- name, the API docs' number, the item quality
local QUALITY = { { "PoorQuality", 6, 0 }, { "CommonQuality", 7, 1 }, { "UncommonQuality", 8, 2 },
    { "RareQuality", 9, 3 }, { "EpicQuality", 10, 4 }, { "LegendaryQuality", 11, 5 }, { "ArtifactQuality", 12, 6 } }

-- The client's enum value, the API docs' number when the enum is missing.
local function filterValue(name, fallback)
    local e = Enum and Enum.AuctionHouseFilter
    if type(e) == "table" and type(e[name]) == "number" then return e[name] end
    return fallback
end

-- filter value -> the item quality it stands for
local function qualityOf(v)
    for _, q in ipairs(QUALITY) do
        if filterValue(q[1], q[2]) == v then return q[3] end
    end
end

-- Like the game's window: every quality on, every "only" filter off.
function BP.FilterOn(v)
    local picked = S.filters.picked[v]
    if picked ~= nil then return picked end
    return qualityOf(v) ~= nil
end

-- How many filters differ from the game's defaults (Usable has its own chip).
function BP.FiltersChanged()
    local n = 0
    for v, on in pairs(S.filters.picked) do
        if on ~= (qualityOf(v) ~= nil) then n = n + 1 end
    end
    return n
end

-- The columns the server can sort by, as the game's own headers do. A long
-- list is cut at Browse.MAX_PAGES, so the server's order picks which rows come.
local SERVER_SORT = { name = "Name", level = "Level", unit = "Price" }

function BP.Sorts()
    local order = Enum and Enum.AuctionHouseSortOrder
    if type(order) ~= "table" or type(order.Price) ~= "number" then return {} end
    local key = SERVER_SORT[S.sort.id]
    local out = {}
    if key and key ~= "Price" and type(order[key]) == "number" then
        out[1] = { sortOrder = order[key], reverseSort = S.sort.desc }
    end
    out[#out + 1] = { sortOrder = order.Price, reverseSort = key == "Price" and S.sort.desc or false }
    return out
end

-- The AuctionHouseBrowseQuery for a search on screen. The quality filters go
-- always, each one switched on: the game's own UI always sends them.
function BP.QueryOf(q)
    if q.favorites then return { searchString = "", sorts = BP.Sorts(), favorites = true } end
    local f = S.filters
    local query = { searchString = trim(q.text), sorts = BP.Sorts(),
        minLevel = f.minLevel, maxLevel = f.maxLevel }
    local filters = {}
    local usable = filterValue("UsableOnly", 2)
    if f.usable then filters[#filters + 1] = usable end
    for _, q in ipairs(QUALITY) do
        local v = filterValue(q[1], q[2])
        if BP.FilterOn(v) then filters[#filters + 1] = v end
    end
    for v, on in pairs(f.picked) do
        if on and v ~= usable and not qualityOf(v) then filters[#filters + 1] = v end
    end
    local node = q.path and Cat.Find(q.path)
    if node then
        if node.implicitFilter then filters[#filters + 1] = node.implicitFilter end
        if #node.filters > 0 then query.itemClassFilters = copyFilters(node.filters) end
    end
    query.filters = filters
    return query
end

local function pctOf(unit, usual)
    if type(unit) ~= "number" or unit < 1 or type(usual) ~= "number" or usual <= 0 then return nil end
    return math.floor(unit * 100 / usual + 0.5)
end

-- The usual price a row is judged against: the days before today, else
-- (first seen today) with today in it. today: true when it is the second.
function BP.Usual(key)
    local rkey = ns.Ruleset.Key()
    if not rkey then return nil end
    local now = ns.Game.Now()
    local prior = ns.Store.Prior(rkey, key, now)
    if prior then return prior, false end
    local market = ns.Store.Market(rkey, key, now)
    if market then return market, true end
    return nil
end

local waiting = {}   -- itemID -> rows waiting for the game to load its name
local skillWait = {} -- itemID -> recipe rows waiting for the server's skill

local function recipeClass()
    return Enum and Enum.ItemClass and Enum.ItemClass.Recipe or 9
end

-- The skill a recipe needs, as the game's own Skill column reads it. The
-- server sends it a while after the results, so a row may wait for it.
local function skillOf(row)
    local api = C_AuctionHouse
    if not (api and api.GetExtraBrowseInfo and type(row.itemKey) == "table") then return nil end
    local v = api.GetExtraBrowseInfo(row.itemKey)
    if type(v) == "number" and v > 0 then return v end
    local list = skillWait[row.itemID] or {}
    skillWait[row.itemID] = list
    list[#list + 1] = row
    return nil
end

local function fillInfo(row)
    -- The Lvl column is the level needed to use it, like the level filter,
    -- not the item level (blank when anyone can use it). A recipe shows the
    -- skill it needs instead, like the game's window.
    local name, quality, _, icon, _, req = ns.Items.Row(row.itemID)
    if not name then return false end
    if row.key ~= row.base and row.itemKey then ns.Items.LearnKey(row.itemKey) end
    row.name, row.quality, row.level, row.icon = ns.Items.KeyName(row.key, name), quality, req, icon
    local _, _, classID = ns.Items.Gear(row.itemID)
    if classID == recipeClass() then row.level = skillOf(row) end
    row.cantUse = ns.Items.CanUse(row.itemID) == false or nil
    return true
end

-- True when a search sits inside the Recipes category.
function BP.InRecipes(q)
    local node = q and q.path and Cat.Find(q.path)
    local root = node and Cat.Find(node.path[1])
    for _, f in ipairs(root and root.filters or {}) do
        if f.classID == recipeClass() then return true end
    end
    return false
end

-- The level column's heading follows the category, as in the game's window.
function BP.PaintLevelHead()
    local cell = page and page.table and page.table.head.cells.level
    if not cell then return end
    local skill = _G.AUCTION_HOUSE_BROWSE_HEADER_RECIPE_SKILL or L["Skill"]
    cell.text:SetText(BP.InRecipes(S.query) and skill or L["Lvl"])
end

local function rowOf(r)
    local usual = BP.Usual(r.key)
    local row = { kind = "line", key = r.key, base = r.base, itemID = r.itemID, itemKey = r.itemKey,
        qty = r.qty, unit = r.minPrice, usual = usual, pct = pctOf(r.minPrice, usual), owned = r.owned }
    if not fillInfo(row) then
        local list = waiting[r.itemID] or {}
        waiting[r.itemID] = list
        list[#list + 1] = row
        ns.Items.Request(r.itemID)
    end
    return row
end

-- Sorted by the head's column; a row with nothing to compare goes last
-- either way, then by name.
function BP.SortRows()
    local id, desc = S.sort.id, S.sort.desc
    table.sort(S.rows, function(a, b)
        if id ~= "name" then
            local x, y = a[id], b[id]
            if x ~= y then
                if x == nil then return false end
                if y == nil then return true end
                if desc then return x > y end
                return x < y
            end
        end
        local x, y = a.name or "", b.name or ""
        if x ~= y then
            if id == "name" and desc then return x > y end
            return x < y
        end
        return tostring(a.key) < tostring(b.key)
    end)
end

local SEARCH_SAY = {
    closed = L["The Auction House closed."],
    timeout = L["The Auction House didn't answer. Try again in a moment."],
    dropped = L["Search stopped."],
}
local function searchSentence(reason)
    return SEARCH_SAY[reason] or L["Something went wrong with that search."]
end

-- Over the Max price box: kept back, shown again when the box changes.
local function tooDear(r)
    local most = S.filters.maxPrice
    return most ~= nil and type(r.minPrice) == "number" and r.minPrice > most
end

-- New browse rows into the list, once per item.
local function addRows(rows)
    for _, r in ipairs(rows) do
        if type(r.key) == "string" and not S.seen[r.key] then
            S.seen[r.key] = true
            S.all[#S.all + 1] = r
            if not tooDear(r) then S.rows[#S.rows + 1] = rowOf(r) end
        end
    end
end

-- The item asked for (a favorite) opens as soon as its row is in.
local function pickWanted()
    local want = S.want
    if not want then return end
    for _, d in ipairs(S.rows) do
        if d.itemID == want then
            S.want = nil
            return BP.PickItem(d)
        end
    end
end

-- A page of rows while the rest still comes: the list shows it at once.
local function paged(g, rows)
    if g ~= S.gen then return end
    local first = #S.rows == 0
    addRows(rows)
    BP.SortRows()
    if first then BP.Changed(true) else BP.Rebuild(true); BP.PaintNote() end
    pickWanted()
end

local function answered(g, rows, reason, capped)
    if g ~= S.gen then return end
    S.running = false
    if rows then
        if S.query and S.query.favorites then learnFavorites(rows) end
        addRows(rows)
        if capped then
            local cheapest = S.sort.id == "unit" and not S.sort.desc
            S.capped = string.format(cheapest and L["Showing the cheapest %s: add words to narrow it."]
                or L["Showing the first %s in this order: add words to narrow it."], ns.Thousands(capped))
        end
    else
        S.problem = searchSentence(reason)
    end
    BP.SortRows()
    BP.Changed(true)
    pickWanted()
    S.want = nil
end

-- The Max price box changed: the rows already in are filtered again, no new search.
function BP.Refilter()
    BP.PaintTools()
    if not S.query then return end
    local had = {}
    for _, d in ipairs(S.rows) do had[d.key] = d end
    S.rows = {}
    for _, r in ipairs(S.all) do
        if not tooDear(r) then S.rows[#S.rows + 1] = had[r.key] or rowOf(r) end
    end
    local open = S.open
    if open and tooDear({ minPrice = open.unit }) then BP.CloseOpen(nil) end
    BP.SortRows()
    BP.Changed(true)
end

-- The open row's search stops when the player moves on.
local function stopOpening()
    local o = S.openSearch
    S.openSearch = nil
    if o then ns.Search.Cancel(o.itemID, o.fn) end
end

-- Runs a search: { text } or { path, label } (a category). Drops what was
-- on screen, its pick and its quote. pickItem: the itemID to open once the
-- rows are in (a favorite).
function BP.Run(q, pickItem)
    if not page then return false end
    BP.DropQuote()
    S.gen = S.gen + 1
    local g = S.gen
    stopOpening()
    S.query, S.rows, S.all, S.seen, S.problem, S.capped, S.tell = q, {}, {}, {}, nil, nil, nil
    S.open, S.step, S.pending, S.closeDone, S.opening, S.want = nil, nil, nil, nil, nil, pickItem
    for id in pairs(waiting) do waiting[id] = nil end   -- the old rows' names aren't wanted now
    for id in pairs(skillWait) do skillWait[id] = nil end
    remember(q)
    BP.PaintLevelHead()
    BP.PaintTools()
    Left.Fill(true)
    if not ns.AH.IsOpen() then
        S.problem = L["Open the Auction House to search."]
        BP.Changed(true)
        return false
    end
    ns.AH.Drop(ns.Browse.TAG)
    S.running = true
    BP.Changed(true)
    ns.Browse.Query(BP.QueryOf(q), function(rows, reason, capped) answered(g, rows, reason, capped) end, nil,
        function(rows) paged(g, rows) end)
    return true
end

-- Nothing searched: the rows go and the empty words come back (the last
-- category unpicked with nothing typed).
function BP.Clear()
    if not page then return end
    BP.DropQuote()
    S.gen = S.gen + 1
    stopOpening()
    S.query, S.rows, S.all, S.seen, S.problem, S.capped, S.tell, S.running = nil, {}, {}, {}, nil, nil, nil, nil
    S.open, S.step, S.pending, S.closeDone, S.opening, S.want = nil, nil, nil, nil, nil, nil
    for id in pairs(waiting) do waiting[id] = nil end
    for id in pairs(skillWait) do skillWait[id] = nil end
    ns.AH.Drop(ns.Browse.TAG)
    BP.PaintLevelHead()
    BP.PaintTools()
    Left.Fill(true)
    BP.Changed(true)
end

-- The words in the box searched, inside the picked category like the game's
-- own AH. anywhere: every category (an item's name from a link).
function BP.Submit(text, anywhere)
    text = trim(text)
    local q = S.query
    local path = not anywhere and q and q.path or nil
    if text == "" and not path then return false end
    if page.box:GetText() ~= text then page.box:SetText(text) end
    return BP.Run({ text = text, path = path, label = path and q.label or nil })
end

-- Every favorite and its price in one list, like the game's star button.
function BP.SearchFavorites()
    if page.box:GetText() ~= "" then page.box:SetText("") end
    return BP.Run({ text = "", favorites = true, label = L["Favorites"] })
end

function BP.Again()
    if S.query then BP.Run(S.query) end
end

-- ---------------------------------------------------------------------
-- A picked row: its price steps and its why
-- ---------------------------------------------------------------------

local function buyable(s) return s.qty - (s.own or 0) end

function BP.IsCommodity(d) return d ~= nil and d.commodity == true end

-- The steps the table shows under the open row: every price of a commodity,
-- gear's auctions only when there's more than one to pick from.
local function shownSteps(d)
    if not d.steps then return {} end
    if d.commodity or #d.steps > 1 then return d.steps end
    return {}
end

-- Steps from ns.Search.Item's auctions, cheapest first. A commodity's are one
-- per price; gear's one per auction of the row's key, those with a buyout
-- first, then the ones that only take bids. The player's own are marked,
-- never bought.
local function stepsOf(row, auctions)
    local usual = row.usual
    local steps = {}
    local want = row.key
    local found = false
    for _, a in ipairs(auctions or {}) do
        if a.key == nil or a.key == want then found = true; break end
    end
    if not found then
        -- a suffix may be the other sign of the same number; a plain key takes every suffix
        local id, sign, suffix = string.match(row.key, "^(%d+):(%-?)(%d+)$")
        want = id and (id .. ":" .. (sign == "-" and "" or "-") .. suffix) or nil
    end
    for _, a in ipairs(auctions or {}) do
        if type(a.qty) == "number" and a.qty > 0 and type(a.unit) == "number" then
            if a.auctionID then
                local buyout = type(a.buyout) == "number" and a.buyout > 0 and a.buyout or nil
                local minBid = type(a.minBid) == "number" and a.minBid > 0 and a.minBid or nil
                if (want == nil or a.key == nil or a.key == want) and (buyout or minBid) then
                    local unit = buyout and a.unit or nil
                    steps[#steps + 1] = { kind = "step", auctionID = a.auctionID, unit = unit, buyout = buyout,
                        minBid = minBid, bid = (a.bid or 0) > 0 and a.bid or nil,
                        qty = a.qty, owner = a.owner, timeLeft = a.timeLeft, pct = pctOf(unit, usual),
                        mine = (type(a.own) == "number" and a.own > 0) or nil }
                end
            else
                local own = type(a.own) == "number" and a.own > 0 and math.min(a.own, a.qty) or nil
                steps[#steps + 1] = { kind = "step", unit = a.unit, qty = a.qty, own = own, pct = pctOf(a.unit, usual) }
            end
        end
    end
    if auctions and not auctions.commodity then
        table.sort(steps, function(x, y)
            if (x.unit ~= nil) ~= (y.unit ~= nil) then return x.unit ~= nil end
            local a, b = x.unit or x.minBid or 0, y.unit or y.minBid or 0
            if a ~= b then return a < b end
            return (x.auctionID or 0) < (y.auctionID or 0)
        end)
    end
    return steps
end

-- The row's own numbers from its fresh steps: how many are up, the
-- cheapest that isn't the player's, the usual the search just priced.
local function freshLine(row)
    local qty, low = 0, nil
    for _, s in ipairs(row.steps) do
        qty = qty + s.qty
        if not s.mine and buyable(s) > 0 and s.unit and (low == nil or s.unit < low) then low = s.unit end
    end
    row.qty = qty
    if low then row.unit = low end
    row.gone = low == nil or nil
    row.usual = BP.Usual(row.key)
    row.pct = (not row.gone) and pctOf(row.unit, row.usual) or nil
end

-- The cheapest `qty` units of the open commodity: their total, and the
-- dearest unit among them (the safety net judges that step, not the average).
local function costOf(d, qty)
    local left, total, dearest, cheapest = qty, 0, nil, nil
    for _, s in ipairs(d.steps or {}) do
        local take = math.min(left, math.max(0, buyable(s)))
        total = total + take * s.unit
        if take > 0 and (dearest == nil or s.unit > dearest) then dearest = s.unit end
        if take > 0 and (cheapest == nil or s.unit < cheapest) then cheapest = s.unit end
        left = left - take
        if left <= 0 then break end
    end
    return total, dearest, cheapest
end

-- How the usual price was made, one sentence.
function BP.UsualWhy(key)
    local usual, today = BP.Usual(key)
    if not usual then return L["No usual price yet: search it again on another day, or run a full scan."] end
    local rkey = ns.Ruleset.Key()
    local lows = ns.Store.Lows(rkey, key)
    local n = lows and math.floor(#lows / 2) or 0
    if not today and n > 0 and lows[#lows - 1] >= ns.Market.Day(ns.Game.Now()) then n = n - 1 end
    local seenAt = ns.Store.SeenAt(rkey, key)
    local age = ns.Ago(math.max(0, ns.Game.Now() - (seenAt or ns.Game.Now())))
    local m = money(usual)
    if n <= 1 then
        return string.format(L["Usual %s is the cheapest price seen so far (seen %s ago)."], m, age)
    end
    if n >= ns.Market.DAYS then
        return string.format(L["Usual %s is the middle of the cheapest price each day for the last %d days (seen %s ago)."],
            m, n, age)
    end
    return string.format(L["Usual %s is the middle of the cheapest price on each of the %d days it was seen (seen %s ago)."],
        m, n, age)
end

local function commodityWhy(d)
    local out = {}
    local first, firstAt
    for i, s in ipairs(d.steps) do
        if buyable(s) > 0 then first, firstAt = s, i; break end
    end
    if not first then return L["Every one up is yours."] end
    local n = buyable(first)
    if first.pct then
        out[1] = string.format(L["The cheapest %s are %s each, %s of usual."], value(ns.Thousands(n)), money(first.unit),
            first.pct .. "%")
    else
        out[1] = string.format(L["The cheapest %s are %s each."], value(ns.Thousands(n)), money(first.unit))
    end
    out[#out + 1] = BP.UsualWhy(d.key)
    local nextStep
    for i = firstAt + 1, #d.steps do
        if buyable(d.steps[i]) > 0 then nextStep = d.steps[i]; break end
    end
    if nextStep then
        local k = n + buyable(nextStep)
        out[#out + 1] = string.format(L["The game sells the cheapest first, so %s would cost about %s."],
            value(ns.Thousands(k)), money((costOf(d, k))))
    end
    local yours = 0
    for _, s in ipairs(d.steps) do yours = yours + (s.own or 0) end
    if yours == 1 then out[#out + 1] = L["1 of them is yours and isn't counted."]
    elseif yours > 1 then out[#out + 1] = string.format(L["%d of them are yours and aren't counted."], yours) end
    return table.concat(out, " ")
end

local function gearWhy(d)
    local out = {}
    local cheapest
    local bidOnly
    for _, s in ipairs(d.steps) do
        if not s.mine and s.unit and (cheapest == nil or s.unit < cheapest.unit) then cheapest = s end
        if not s.mine and not s.unit and s.minBid and (bidOnly == nil or s.minBid < bidOnly.minBid) then bidOnly = s end
    end
    if not cheapest and bidOnly then
        return string.format(L["Only bids on this one: the next bid is at least %s. The highest bid when time runs out wins it."],
            money(bidOnly.minBid))
    end
    if not cheapest then return L["That auction is yours."] end
    local up = 0
    for _, s in ipairs(d.steps) do if not s.mine then up = up + 1 end end
    if up == 1 then out[1] = string.format(L["One up, buyout %s."], money(cheapest.buyout))
    else out[1] = string.format(L["%s up, the cheapest buyout %s."], value(tostring(up)), money(cheapest.buyout)) end
    local usual = d.usual
    if cheapest.pct and usual then
        local rkey = ns.Ruleset.Key()
        local lows = ns.Store.Lows(rkey, d.key)
        local n = lows and math.floor(#lows / 2) or 0
        out[#out + 1] = n > 1
            and string.format(L["That's %s of usual (%s, the middle of %d days it was seen)."], value(cheapest.pct .. "%"),
                money(usual), n)
            or string.format(L["That's %s of usual (%s, seen once so far)."], value(cheapest.pct .. "%"), money(usual))
    else
        out[#out + 1] = L["No usual price yet: search it again on another day, or run a full scan."]
    end
    out[#out + 1] = L["It may be a different roll; check the tooltip before you buy."]
    return table.concat(out, " ")
end

function BP.Why(d)
    if not d.steps then return "" end
    if d.commodity then return commodityWhy(d) end
    return gearWhy(d)
end

-- ---------------------------------------------------------------------
-- The table
-- ---------------------------------------------------------------------

local whys = setmetatable({}, { __mode = "k" })   -- item row -> its why row (kept: the table finds it again)

local function rowsNow()
    local list = {}
    for _, r in ipairs(S.rows) do
        list[#list + 1] = r
        if r == S.open and r.steps then
            for _, s in ipairs(shownSteps(r)) do list[#list + 1] = s end
            if r.why then
                local w = whys[r] or { kind = "why" }
                whys[r] = w
                w.text = r.why
                list[#list + 1] = w
            end
        end
    end
    return list
end

local function indexOf(d)
    local t = page and page.table
    if not (t and d) then return nil end
    for i, r in ipairs(t.rows) do if r == d then return i end end
end
BP.IndexOf = indexOf

-- The commodity steps the amount reaches: washed like a pick.
local function covered()
    local out, d = {}, S.open
    if not (d and d.commodity and d.steps) then return out end
    local left = S.amount or 0
    for _, s in ipairs(d.steps) do
        if left <= 0 then break end
        local n = buyable(s)
        if n > 0 then
            out[s] = true
            left = left - n
        end
    end
    return out
end

function BP.PaintPick()
    local t = page.table
    local stepAt = S.step and indexOf(S.step)
    t:Pick(stepAt or indexOf(S.open))
    local reach = covered()
    for i, b in pairs(t.shown) do
        local d = t.rows[i]
        if b.pick and d then
            if d == S.open then Parts.PickLine(b, true)
            elseif d.kind == "step" and not d.auctionID then Parts.PickLine(b, reach[d] == true) end
        end
    end
end

-- The table from the state. keep: in place; else a new search's rows, from
-- the top, fading in.
function BP.Rebuild(keep)
    if not page then return end
    -- a glide shut under way finishes first: its done refills
    if S.closeDone and keep then return end
    S.closeDone = nil
    local t = page.table
    t:SetRows(rowsNow(), keep)
    if not keep and animated(t.view) then Motion.Fade(t.view, 0, 1, Motion.FAST) end
    BP.PaintPick()
end

function BP.Changed(fresh)
    BP.Rebuild(not fresh)
    BP.PaintFooter()
    BP.PaintNote()
end

function BP.Deal()
    local v = ns.Setting("dealBelow")
    return type(v) == "number" and v * 100 or BP.DEAL
end

local function pctRole(pct)
    if type(pct) ~= "number" then return "LABEL" end
    if pct <= BP.Deal() then return "GOOD" end
    if pct > ns.Buy.Safety() then return "WARN" end
    return "VALUE"
end

local function place(b, fs, cols, id)
    local c = cols and cols[id]
    if not c then return fs:Hide() end
    fs:ClearAllPoints()
    fs:SetPoint("RIGHT", b, "LEFT", c.x + c.w, 0)
    fs:SetWidth(math.max(1, c.w))
    fs:Show()
end

local function makeCells(b, ids, size)
    b.cells = {}
    for _, id in ipairs(ids) do
        local fs = Style.Text(b, size, "RIGHT")
        fs:SetWordWrap(false)
        b.cells[id] = fs
    end
end

local function makeLine(b)
    Parts.ItemIcon(b, BP.ICON)
    b.name = Style.Text(b, Style.SIZE.body, "LEFT")
    b.name:SetWordWrap(false)
    makeCells(b, NUMBERS, Style.SIZE.body)
end

local function fillLine(b, d, cols)
    local c = cols.name
    b.edge:ClearAllPoints()
    b.edge:SetPoint("LEFT", b, "LEFT", c.x + 4, 0)
    Parts.FitItemIcon(b)
    local r, g, bl = Parts.SetItemIcon(b, d.icon, d.quality)
    b.name:ClearAllPoints()
    b.name:SetPoint("LEFT", b, "LEFT", c.x + BP.ICON_X, 0)
    b.name:SetWidth(math.max(1, c.w - BP.ICON_X))
    if d.name then
        b.name:SetText(d.name)
        b.name:SetTextColor(r, g, bl)
    else
        b.name:SetText(nameOf(d))
        Style.InkText(b.name, "OFF")
    end
    for _, id in ipairs(NUMBERS) do place(b, b.cells[id], cols, id) end
    local x = b.cells
    x.level:SetText(d.level and tostring(d.level) or "")
    Style.InkText(x.level, d.cantUse and "BAD" or "LABEL")   -- this character can't use it
    x.qty:SetText(d.qty and ns.Thousands(d.qty) or "")
    Style.InkText(x.qty, "pop")
    x.unit:SetText(d.gone and DASH or money(d.unit))
    Style.InkText(x.unit, d.gone and "LABEL" or "VALUE")
    x.usual:SetText(type(d.usual) == "number" and money(d.usual) or "")
    Style.InkText(x.usual, "VALUE")
    x.pct:SetText(d.pct and (d.pct .. "%") or "")
    Style.InkText(x.pct, pctRole(d.pct))
    if d == S.open then Parts.PickLine(b, true) end
end

local function makeStep(b)
    b.name = Style.Text(b, Style.SIZE.small, "LEFT")
    b.name:SetWordWrap(false)
    makeCells(b, STEP_CELLS, Style.SIZE.small)
end

local LEFT_BAND = { [0] = L["under 30 min left"], [1] = L["under 2 h left"], [2] = L["under 12 h left"],
    [3] = L["under 48 h left"] }

function BP.StepText(s)
    if s.auctionID then
        local out = s.mine and L["Yours"] or s.owner or L["An auction"]
        local band = LEFT_BAND[s.timeLeft]
        if band then out = out .. SEP .. band end
        if s.bid then out = out .. SEP .. string.format(L["bid %s"], money(s.bid))
        elseif s.minBid and not s.unit then out = out .. SEP .. string.format(L["bids from %s"], money(s.minBid)) end
        return out
    end
    local n = ns.Thousands(s.qty)
    if s.own and s.own >= s.qty then return string.format(L["%s at this price, all yours"], n) end
    if s.own then return string.format(L["%s at this price, %d of them yours"], n, s.own) end
    return string.format(L["%s at this price"], n)
end

local function fillStep(b, d, cols)
    local c = cols.name
    b.name:ClearAllPoints()
    b.name:SetPoint("LEFT", b, "LEFT", c.x + BP.STEP_X, 0)
    b.name:SetWidth(math.max(1, c.w - BP.STEP_X))
    b.name:SetText(BP.StepText(d))
    Style.InkText(b.name, "LABEL")
    for _, id in ipairs(STEP_CELLS) do place(b, b.cells[id], cols, id) end
    local x = b.cells
    local mine = d.mine or (d.own ~= nil and d.own >= d.qty)
    x.qty:SetText(ns.Thousands(d.qty))
    Style.InkText(x.qty, mine and "LABEL" or "pop")
    x.unit:SetText(d.unit and money(d.unit) or L["bids only"])
    Style.InkText(x.unit, d.unit and "VALUE" or "LABEL")
    x.pct:SetText(d.pct and (d.pct .. "%") or "")
    Style.InkText(x.pct, pctRole(d.pct))
    if not d.auctionID then Parts.PickLine(b, covered()[d] == true) end
end

-- The item's own tooltip (the Tooltip module adds its auction line).
local function onEnter(b, d)
    local row = d.kind == "step" and S.open or d
    if not (row and row.kind == "line" and type(row.itemID) == "number" and GameTooltip) then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    ns.Items.SetTip(GameTooltip, row.key, row.itemID)
    GameTooltip:Show()
end
local function onLeave(b)
    if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(b) then GameTooltip:Hide() end
end

-- ---------------------------------------------------------------------
-- Picking
-- ---------------------------------------------------------------------

-- The open row's auctions came (or the sentence of what went wrong).
function BP.Opened(d)
    if S.open ~= d then d.steps, d.why = nil, nil; return end
    local first = not d.shown
    d.shown = true
    -- Only an auction the player clicked stays picked through later pages and a
    -- search again. The auction house sends pages in its own order, often
    -- dearest first, so a pick made from the first page alone could be the
    -- most expensive one up.
    if S.step and S.stepClicked then
        local still
        for _, s in ipairs(d.steps or {}) do if s.auctionID and s.auctionID == S.step.auctionID then still = s end end
        S.step = still
    else
        S.step = nil
    end
    if not S.step then S.stepClicked = nil end
    if not S.step and d.steps and not d.commodity then
        for _, s in ipairs(d.steps) do if not s.mine then S.step = s; break end end
        S.step = S.step or d.steps[1]
    end
    BP.FillBid()
    -- Start at one, as the game's own window does. A click on a price step
    -- still takes everything through it in one go.
    if d.commodity and (S.amountOf ~= d or not S.amountSet) then
        S.amountOf, S.amountSet = d, false
        S.amount = 1
    end
    BP.Rebuild(true)
    local i = indexOf(d)
    local n = #shownSteps(d) + (d.why and 1 or 0)
    if first and i and n > 0 then page.table:Open(i, n); BP.PaintPick() end
    if d.shine then BP.Shine(d) end
    BP.PaintFooter()
end

-- Asks for the row's auctions (again after a buy: refresh asks the results the
-- client holds, as the game's own window does). The first page shows at once;
-- deeper prices join the steps as they come.
function BP.OpenRow(d, refresh)
    stopOpening()
    local token = {}
    S.opening = token
    d.opening = true
    local function show(auctions)
        d.commodity = auctions.commodity == true
        d.steps = stepsOf(d, auctions)
        freshLine(d)
        d.why = BP.Why(d)
        BP.Opened(d)
    end
    local function done(rows, reason, auctions)
        if S.opening ~= token then return end
        S.opening, S.openSearch = nil, nil
        d.opening = nil
        if rows and auctions then return show(auctions) end
        d.steps = nil
        d.why = reason == "uncached" and L["The game hasn't loaded this item yet. Try again in a moment."]
            or searchSentence(reason)
        BP.Opened(d)
    end
    S.openSearch = { itemID = d.itemID, fn = done }
    local ok, why = ns.Search.Item(d.itemID, done, {
        priority = true, refresh = refresh,
        onPage = function(_, auctions)
            if S.opening ~= token then return end
            d.opening = nil   -- the first prices are in: they can be bought while the rest comes
            show(auctions)
        end,
    })
    if not ok and S.opening == token then
        S.opening, S.openSearch = nil, nil
        d.opening = nil
        BP.Tell(searchSentence(why), "WARN")
    end
end

local function begin(d)
    S.open, S.step, S.stepClicked = d, nil, nil
    BP.Rebuild(true)
    BP.OpenRow(d)
    BP.PaintFooter()
end

-- The open row shuts: its steps and why glide out (NORMAL), then the next
-- row to open (if any) opens.
function BP.CloseOpen(nextRow)
    local d = S.open
    S.pending = nextRow
    if not d then
        S.pending = nil
        if nextRow then begin(nextRow) end
        return
    end
    local n = #shownSteps(d) + (d.why and 1 or 0)
    stopOpening()
    S.open, S.step, S.opening = nil, nil, nil
    d.steps, d.why, d.shown, d.opening = nil, nil, nil, nil
    local i = indexOf(d)
    local function done()
        if S.closeDone ~= done then return end
        S.closeDone = nil
        local nxt = S.pending
        S.pending = nil
        BP.Rebuild(true)
        if nxt then begin(nxt) else BP.PaintFooter() end
    end
    S.closeDone = done
    if i and n > 0 then page.table:Close(i, n, done) else done() end
end

function BP.PickItem(d)
    BP.DropQuote()
    BP.Tell(nil)
    if S.closeDone then S.pending = d; return end   -- the old one is still gliding shut
    if S.open == d then return BP.CloseOpen(nil) end
    BP.CloseOpen(d)
end

function BP.PickStep(s)
    if not s.auctionID then return BP.AmountThrough(s) end
    if S.step == s or s.mine then return end
    S.step, S.stepClicked = s, true
    BP.FillBid()
    BP.PaintPick()
    BP.PaintFooter()
end

-- A result's right-click: on or off the favorites.
function BP.RowMenu(d, owner)
    if type(d.itemID) ~= "number" then return end
    local on = BP.IsFavorite(d.itemID)
    W.OpenMenu(owner, { "fav" }, { fav = on and L["Remove from favorites"] or L["Add to favorites"] }, nil, function()
        BP.SetFavorite(d.itemID, not on, d.itemKey)
        BP.Tell(string.format(on and L["%s is off your favorites."] or L["%s is on your favorites now."], nameOf(d)), "LABEL")
        if Left.mode == "favorites" then Left.Fill(true) end
    end, nil, { atCursor = true })
end

local function onClick(row, d, _, button)
    if button == "RightButton" then
        if d.kind == "line" then BP.RowMenu(d, row) end
        return
    end
    if d.kind == "line" then BP.PickItem(d)
    elseif d.kind == "step" then BP.PickStep(d) end
end

-- ---------------------------------------------------------------------
-- Buying (every purchase call below runs inside a footer button's click)
-- ---------------------------------------------------------------------

BP.SAY = {
    busy = L["Wait for the search to finish, then click again."],
    late = L["Still waiting for the game's answer to your last click. Try again in a moment."],
    trouble = L["The Auction House is having trouble right now. Try again later."],
    throttled = L["The Auction House is busy: click again in a moment."],
    closed = L["The Auction House closed."],
    unavailable = L["The price changed and the game won't hold it: search again."],
    failed = L["Someone else bought it first."],
    timeout = L["The game didn't answer. Try again in a moment."],
    lost = L["The game didn't answer. Check your mailbox and bags before you buy again."],
    expired = L["The price quote ran out: click Buy again."],
    moved = L["The price changed: check the new total and click again."],
    noquote = L["The price quote is gone: click Buy again."],
    gold = L["You don't have enough gold for that."],
}

-- detail: the game's own words for what went wrong, when it gave any.
function BP.Sentence(reason, detail)
    if detail and (reason == "failed" or reason == "trouble") then
        return string.format(L["The game said no: %s."], detail)
    end
    if reason == "gold" and _G.ERR_NOT_ENOUGH_MONEY then return _G.ERR_NOT_ENOUGH_MONEY end
    return BP.SAY[reason] or L["Something went wrong with that purchase."]
end
local sentence = BP.Sentence

-- A sentence in the footer, in place of the count (nil: back to it).
function BP.Tell(text, role)
    S.tell = text and { text = text, role = role } or nil
    BP.PaintStat()
end

local function overWords(pct)
    return pct and string.format(L["%d%% of usual"], pct) or L["No usual price"]
end

-- The safety net's armed words, one whole sentence each.
local function askWords(pct)
    return pct and string.format(L["%d%% of usual: click again"], pct) or L["No usual price: click again"]
end

-- The most of the open commodity that can be bought: every step not the player's.
function BP.Most(d)
    local m = 0
    for _, s in ipairs(d and d.steps or {}) do m = m + math.max(0, buyable(s)) end
    return m
end

function BP.SetAmount(v)
    local most = BP.Most(S.open)
    if most < 1 then return end
    S.amount = math.max(1, math.min(most, math.floor(tonumber(v) or 1)))
    S.amountOf, S.amountSet = S.open, true
    BP.PaintPick()
    BP.PaintFooter()
end

-- A commodity's price step clicked: everything up to and through it.
function BP.AmountThrough(step)
    local n = 0
    for _, s in ipairs(S.open and S.open.steps or {}) do
        n = n + math.max(0, buyable(s))
        if s == step then return BP.SetAmount(n) end
    end
end

function BP.DropQuote()
    if S.quote and ns.Buy.Pending() == "quote" then ns.Buy.Cancel() end
    S.quote = nil
end

-- A soft light across a bought row.
function BP.Shine(d)
    d.shine = nil
    local i = indexOf(d)
    local b = i and page.table:Row(i)
    if b then Parts.Shine(b) end
end

-- After a buy (or a failure) the item's steps are searched again, and a
-- bought row shines once they're back. sent: the purchase went out, so no
-- answer (a timeout, the AH closing) must not claim nothing was bought.
local function after(d, ok, reason, qty, sent, detail)
    S.quote, S.buying = nil, false
    if reason == "canceled" then return BP.PaintFooter() end
    if ok then
        S.amountSet = false
        BP.Tell(string.format(L["Bought %s %s."], ns.Thousands(qty), nameOf(d)), "GOOD")
    else
        local gone = sent and (reason == "timeout" or reason == "closed" or reason == "error")
        BP.Tell(sentence(gone and "lost" or reason, detail), "WARN")
    end
    if S.open == d and ns.AH.IsOpen() then
        d.shine = ok or nil   -- once its steps are back
        BP.OpenRow(d, true)
    elseif ok then
        BP.Shine(d)
    end
    BP.PaintFooter()
end

function BP.BuyCommodity(qty)
    local d = S.open
    if not (d and d.commodity) or S.quote or S.buying then return end
    local total, dearest, cheapest = costOf(d, qty)
    local q = { row = d, qty = qty, expected = total, dearest = dearest, askedAt = GetTime() }
    if dearest and cheapest and cheapest > 0 and dearest * 100 >= cheapest * (100 + BP.SPREAD) then
        q.spread = math.floor((dearest - cheapest) * 100 / cheapest + 0.5)
    end
    S.quote = q
    BP.Tell(nil)
    -- the unit price rounded up, as the game's own buy frame sends it (SanitizeAuctionHousePrice)
    local ok, why = ns.Buy.Commodity(d.itemID, qty, math.ceil(total / qty),
        function(unit, sum) BP.Quoted(q, unit, sum) end,
        function(done, reason, detail)
            if S.quote == q or S.buying == q then after(d, done, reason, qty, q.sent, detail) end
        end)
    if not ok then
        if S.quote == q then S.quote = nil end
        BP.Tell(sentence(why), "WARN")
    end
    BP.PaintFooter()
end

-- The quote shown is the one Confirm sends. A double-click on Buy never buys:
-- Confirm takes no click until DOUBLE after the Buy click, and the game's answer
-- usually takes longer than that, so Confirm lights as its total shows. A total
-- that changes while held waits CONFIRM_WAIT before it takes a click.
local function settled(q)
    if q.total == nil then return false end
    local now = GetTime()
    if q.askedAt and now - q.askedAt < BP.DOUBLE then return false end
    return not q.changedAt or now - q.changedAt >= BP.CONFIRM_WAIT
end

-- Counts a held quote down on its Confirm button while it's nearly out, and
-- drops it when it runs out, as the game's own dialog closes then.
local function quoteLeft()
    local api = C_AuctionHouse
    local left = api and api.GetQuoteDurationRemaining and api.GetQuoteDurationRemaining()
    return type(left) == "number" and left or nil
end

local function watchQuote(q)
    if q.ticker then return end
    q.ticker = C_Timer.NewTicker(1, function()
        if S.quote ~= q then
            q.ticker:Cancel()
            q.ticker = nil
            return
        end
        local left = quoteLeft()
        if left and left <= 0 then
            q.ticker:Cancel()
            q.ticker = nil
            BP.DropQuote()
            BP.Tell(sentence("expired"), "WARN")
            BP.PaintFooter()
        elseif left and left <= BP.QUOTE_SHOW then
            BP.PaintFooter()
        end
    end)
end

function BP.Quoted(q, unit, total)
    if S.quote ~= q then return end
    -- More than PRICE_JUMP % over what the list showed: refused, as the game's own dialog
    -- does (PriceUnavailable), and the prices shown again.
    if q.expected and q.expected > 0 and total * 100 > q.expected * (100 + BP.PRICE_JUMP) then
        local d = q.row
        BP.DropQuote()
        BP.Tell(L["The price went up since you looked: here are the prices now."], "WARN")
        if S.open == d and ns.AH.IsOpen() then BP.OpenRow(d, true) end
        return BP.PaintFooter()
    end
    watchQuote(q)
    local first = q.total == nil
    local changed = q.total ~= total
    q.unit, q.total = unit, total
    -- over the net when the average is, or any step bought is: the words name
    -- the dearest step's % then
    local warn, pct = ns.Buy.Check(q.row.key, unit)
    if q.dearest then
        local dWarn, dPct = ns.Buy.Check(q.row.key, q.dearest)
        if dWarn then warn, pct = true, dPct end
    end
    q.pct, q.over = pct, warn
    q.up = total > q.expected
    if changed then
        local now = GetTime()
        local wait = 0
        if first then
            wait = q.askedAt and math.max(0, q.askedAt + BP.DOUBLE - now) or 0
        else
            q.changedAt = now
            wait = BP.CONFIRM_WAIT
        end
        local token = {}
        q.wait = token
        local function ready()
            if S.quote == q and q.wait == token then
                DUI.Sound.Play("toggle")   -- the first click worked: Confirm takes the second now
                BP.PaintFooter()
            end
        end
        if wait > 0 then C_Timer.After(wait, ready) else ready() end
    end
    BP.PaintFooter()
end

function BP.ConfirmBuy()
    local q = S.quote
    if not (q and settled(q)) then return end
    q.sent = true   -- before the call: it can end inside it
    local ok, why = ns.Buy.Confirm(q.total)
    if ok then
        if S.quote == q then S.quote, S.buying = nil, q end   -- not ended already
    elseif why == "moved" then
        q.sent = nil
        local unit, total = ns.Buy.Quote()
        if total then BP.Quoted(q, unit, total) end
        BP.Tell(sentence(why), "WARN")
    elseif why == "expired" or why == "noquote" then
        q.sent = nil
        S.quote = nil
        BP.Tell(sentence(why), "WARN")
    else
        q.sent = nil
        BP.Tell(sentence(why), "WARN")
    end
    BP.PaintFooter()
end

function BP.CancelBuy()
    BP.DropQuote()
    BP.PaintFooter()
end

-- One click on a gear auction: its buyout.
function BP.BuyItem(s)
    local d = S.open
    if not d or S.buying then return end
    BP.Tell(nil)
    local token = {}
    S.buying = token
    local ok, why = ns.Buy.Item(s.auctionID, s.buyout, function(done, reason, detail)
        if S.buying ~= token then return end
        after(d, done, reason, 1, true, detail)
    end)
    if not ok then
        S.buying = false
        BP.Tell(sentence(why), "WARN")
    end
    BP.PaintFooter()
end

-- The bid box starts at the least the picked auction's next bid can be.
function BP.FillBid()
    if not (page and page.bid) then return end
    local s = S.step
    page.bid:SetText(s and s.minBid and plainMoney(s.minBid) or "")
end

function BP.BidItem(s)
    local d = S.open
    if not d or S.buying or not s.minBid then return end
    local text = trim(page.bid:GetText())
    local amount = text == "" and s.minBid or ns.SellPage.ReadMoney(text, ns.SellPage.TopCoin(s.minBid))
    if type(amount) ~= "number" or amount < s.minBid then
        return BP.Tell(string.format(L["Bid at least %s."], money(s.minBid)), "WARN")
    end
    if s.buyout and amount >= s.buyout then
        return BP.Tell(L["That's the buyout or more: buy it out instead."], "WARN")
    end
    BP.Tell(nil)
    local token = {}
    S.buying = token
    local ok, why = ns.Buy.Bid(s.auctionID, amount, s.buyout or 0, function(done, reason, detail)
        if S.buying ~= token then return end
        S.buying = false
        if done then
            BP.Tell(string.format(L["Bid %s on %s. It's yours by mail if no one bids more."], money(amount), nameOf(d)), "GOOD")
        else
            BP.Tell(sentence(reason, detail), "WARN")
        end
        if S.open == d and ns.AH.IsOpen() then BP.OpenRow(d, true) end
        BP.PaintFooter()
    end)
    if not ok then
        S.buying = false
        BP.Tell(sentence(why), "WARN")
    end
    BP.PaintFooter()
end

-- The key binding: the footer's main button, as a click would (its second-click asks too).
function BP.Key()
    if not (page and page:IsVisible() and ns.AH.IsOpen()) then return end
    local b = page.foot and page.foot.buttons and page.foot.buttons[1]
    if b and b:IsShown() and b.spec and not b.spec.off then b:Click() end
end

-- ---------------------------------------------------------------------
-- The footer: [main] [amount] ... the count or a sentence ... [Search again]
-- ---------------------------------------------------------------------

-- Wires a footer button once: the two-click ask (W.Confirm) for a spec with
-- `ask` (its words while armed, in INK.WARN), else one click; the main
-- button's tone and a warning's color kept through every repaint.
local function wire(b)
    if b.buyWired then return end
    b.buyWired = true
    b.fit = 110
    W.Confirm(b, function() return b.spec and b.spec.text or "" end, function()
        local s = b.spec
        if s and s.onClick and not s.off then s.onClick(b) end
    end)
    local confirmClick = b:GetScript("OnClick")
    b:SetScript("OnClick", function(self)
        local s = self.spec
        if not s or s.off or not s.onClick then return end
        if s.ask then return confirmClick(self) end
        s.onClick(self)
    end)
    local paint = b.Paint
    function b.Paint()
        paint()
        local s = b.spec
        if not s then return end
        if b.armed and s.ask then
            b.text:SetText(s.ask)
            Style.InkText(b.text, "WARN")
            b.FitWidth(b.fit)
        elseif not b.armed then
            Parts.Tone(b, (s.primary and not s.plain) and "main" or nil)
            if s.warn then Style.InkText(b.text, "WARN") end
        end
    end
end

-- Three slots: 1 the main buy, 2 beside it (Cancel), 3 Search again in the
-- right corner. A slot coming or going fades (FAST), changed words fade in.
function BP.SetSlots(specs)
    local foot = page.foot
    local list, before, words = {}, {}, {}
    for i = 1, 3 do
        local b = foot.buttons[i]
        before[i] = b ~= nil and showing(b)
        words[i] = b and b.text:GetText()
        list[i] = specs[i] or { text = words[i] or "", off = true, hidden = true }
        list[i].primary = i == 1
        list[i].beside = i == 2
    end
    for i = 1, 3 do
        local b = foot.buttons[i]
        if b and b.armed and (not b.spec or b.spec.id ~= list[i].id) then b.Disarm() end
    end
    foot:Set(list)
    local animate = animated(foot.frame)
    for i = 1, 3 do
        local b = foot.buttons[i]
        wire(b)
        b.Paint()
        if list[i].hidden then
            if before[i] then ease(b, false) elseif not b.buyLeaving then b:Hide() end
        elseif not before[i] then
            b:Hide()
            ease(b, true)
        elseif animate and words[i] ~= b.text:GetText() then
            Motion.Fade(b.text, 0, 1, Motion.FAST)
        end
    end
end

local function quoteSpecs(q)
    if not q.total then
        return { id = "asking", text = L["Asking the game for the price..."], off = true }
    end
    local text = string.format(L["Confirm %s"], money(q.total))
    local ask
    if q.over then
        text = text .. SEP .. overWords(q.pct)
        ask = askWords(q.pct)
    elseif q.up then
        -- said in the warning color; still the one Confirm click, as in the game's window
        text = text .. SEP .. L["the price went up"]
    elseif q.spread then
        text = text .. SEP .. string.format(L["some cost %d%% more"], q.spread)
    end
    local left = quoteLeft()
    if left and left > 0 and left <= BP.QUOTE_SHOW then
        text = text .. SEP .. string.format(L["%d s"], math.ceil(left))
    end
    return { id = "confirm:" .. q.total, text = text, warn = q.over or q.up or q.spread ~= nil, ask = ask,
        off = not settled(q), onClick = function() BP.ConfirmBuy() end }
end

function BP.PaintFooter()
    if not page then return end
    local d = S.open
    local one, two
    local box, bidBox = false, false
    hint = nil
    local q = S.quote
    if q then
        one = quoteSpecs(q)
        two = { id = "cancel", text = CANCEL or L["Cancel"], onClick = function() BP.CancelBuy() end }
    elseif S.buying then
        one = { id = "buying", text = L["Buying..."], off = true }
    elseif d and d.steps and #d.steps > 0 then
        if d.commodity then
            local most = BP.Most(d)
            if most < 1 then
                one = { id = "nobuy", text = L["Buy"], off = true, plain = true }
                hint = L["Those are all yours."]
            else
                box = true
                local k = math.max(1, math.min(most, S.amount or 1))
                S.amount = k
                one = { id = "buy:" .. k, text = string.format(L["Buy %s"], ns.Thousands(k)),
                    onClick = function() BP.BuyCommodity(k) end }
            end
        elseif S.step and S.step.mine then
            one = { id = "mine", text = string.format(L["Buy for %s"], money(S.step.buyout or 0)), off = true, plain = true }
            hint = L["That auction is yours."]
        elseif S.step then
            local s = S.step
            local bid = s.minBid and { id = "bid:" .. s.auctionID, text = L["Bid"], onClick = function() BP.BidItem(s) end }
            if s.buyout then
                local warn, pct = ns.Buy.Check(d.key, s.unit)
                -- a row of many: one click buys one, at its price
                one = { id = "buy:" .. s.auctionID,
                    text = string.format((s.qty or 1) > 1 and L["Buy 1 for %s"] or L["Buy for %s"], money(s.buyout)),
                    ask = warn and askWords(pct) or nil,
                    onClick = function() BP.BuyItem(s) end }
                two = bid
            else
                one = bid
            end
            bidBox = bid ~= nil
        end
        -- searched again (after a buy): nothing to click until the steps are back
        if d.opening then
            if one then one.off = true end
            if two then two.off = true end
            box, bidBox = false, false
        end
        -- a search or another answer holds the Auction House: a click now would be
        -- refused, so the buttons look it until the line is free (LineChanged)
        if not ns.AH.CanAct() then
            if one then one.off = true end
            if two then two.off = true end
        end
    end
    one = one or { id = "idle", text = L["Buy"], off = true }
    local again = { id = "again", text = L["Search again"],
        off = S.query == nil or S.running or not ns.AH.IsOpen(), onClick = function() BP.Again() end }
    BP.SetSlots({ one, two, again })
    BP.PaintAmount(box)
    BP.PaintBidBox(bidBox and (two and 2 or 1) or nil)
    BP.PaintStat()
end

-- The bid box sits after the Bid button (slot 1 for bid-only gear, else 2).
function BP.PaintBidBox(slot)
    local box = page.bid
    if slot then
        box:ClearAllPoints()
        box:SetPoint("LEFT", page.foot.buttons[slot], "RIGHT", 8, 0)
    end
    ease(box, slot and true or false)
end

function BP.PaintAmount(on)
    local box = page.amount
    ease(box, on)
    if not on then return end
    if not box:HasFocus() then box:SetText(tostring(S.amount or 1)) end
end

-- The count of rows, the commodity's total, or a sentence in its place; a
-- change of words fades in (FAST).
function BP.PaintStat()
    if not page then return end
    local stat = page.stat
    local was = stat:GetText()
    local tell = S.tell or (hint and { text = hint, role = "LABEL" }) or nil
    local d = S.open
    if tell then
        stat:SetText(tell.text)
        Style.InkText(stat, tell.role)
    else
        local text = ""
        local n = #S.rows
        local count = string.format(n == 1 and L["%s item"] or L["%s items"], pop(ns.Thousands(n)))
        if S.running or (d and d.opening and not d.steps) then
            text = L["Searching..."]
        elseif d and d.commodity and d.steps and BP.Most(d) > 0 and not S.quote then
            local k = S.amount or 1
            text = string.format(L["%s for %s"], pop(ns.Thousands(k)), money((costOf(d, k))))
        elseif d then
            text = count
        elseif n > 0 then
            text = (S.capped or L["Pick an item to see its prices"]) .. SEP .. count
        end
        stat:SetText(text)
        Style.InkText(stat, "LABEL")
    end
    -- between whatever shows on the left (Buy, the amount, Cancel) and Search again
    local buttons = page.foot.buttons
    local leftOf = (showing(page.bid) and page.bid) or (buttons[2] and showing(buttons[2]) and buttons[2])
        or (showing(page.amount) and page.amount) or buttons[1]
    stat:ClearAllPoints()
    stat:SetPoint("RIGHT", buttons[3], "LEFT", -12, 0)
    stat:SetPoint("LEFT", leftOf, "RIGHT", 12, 0)
    if animated(stat) and was ~= stat:GetText() then Motion.Fade(stat, 0, 1, Motion.FAST) end
end

-- The empty table's words; a change of words fades in (FAST).
function BP.PaintNote()
    if not page then return end
    local note = page.note
    local text
    if not ns.AH.IsOpen() then
        text = L["Open the Auction House to search."]
    elseif #S.rows == 0 then
        if not S.query then text = L["Pick a category on the left, or type a name."]
        elseif S.running then text = L["Searching..."]
        else text = S.problem or L["No items match."] end
    end
    local shown = showing(note)
    if text then
        local was = note:GetText()
        note:SetText(text)
        if shown and was ~= text and animated(note) then Motion.Fade(note, 0, 1, Motion.FAST) end
    end
    ease(note, text ~= nil)
end

local function buildFooter(right)
    page.foot = Parts.Footer(right)
    local stat = Style.Text(page.foot.frame, Style.SIZE.small, "RIGHT")
    stat:SetWordWrap(false)
    page.stat = stat
    BP.SetSlots({})
    local box = W.Input(page.foot.frame, { justify = "CENTER", numeric = true, maxLetters = 6,
        onChange = function(text, user) if user and text ~= "" then BP.SetAmount(text) end end })
    box:SetWidth(BP.QTY_W)
    box:SetPoint("LEFT", page.foot.buttons[1], "RIGHT", 8, 0)
    box:SetFrameLevel(page.foot.frame:GetFrameLevel() + 3)
    box:EnableMouseWheel(true)
    box:SetScript("OnMouseWheel", function(_, delta) BP.SetAmount((S.amount or 1) + (delta > 0 and 1 or -1)) end)
    W.PadNumber(box, function(dir) BP.SetAmount((S.amount or 1) + dir) end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:HookScript("OnEditFocusLost", function(self) self:SetText(tostring(S.amount or 1)) end)
    box:Hide()
    page.amount = box
    local bid = W.Input(page.foot.frame, { justify = "RIGHT", hint = plainMoney(12000) })
    bid:SetWidth(BP.BID_W)
    W.PadNumber(bid, function(dir)
        local s = S.step
        if not (s and s.minBid) then return end
        local c = ns.SellPage.ReadMoney(trim(bid:GetText()), ns.SellPage.TopCoin(s.minBid)) or s.minBid
        bid:SetText(plainMoney(ns.SellPage.StepMoney(c, dir, s.minBid)))
    end)
    bid:SetFrameLevel(page.foot.frame:GetFrameLevel() + 3)
    bid:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if S.step then BP.BidItem(S.step) end
    end)
    bid:Hide()
    page.bid = bid
end

-- ---------------------------------------------------------------------
-- The left pane: Browse, Recent, Favorites over one list (Parts.Stack)
-- ---------------------------------------------------------------------

Left = {}
BP.Left = Left
Left.MODES = {
    { id = "browse", text = L["Browse"] },
    { id = "recent", text = L["Recent"] },
    { id = "favorites", text = L["Favorites"] },
}
Left.mode = "browse"
Left.expanded = {}   -- category path -> true while open

local function row(stack, spec, picked)
    local b = stack:Row(spec)
    b.picked = picked == true
    b.Lit(false)
    return b
end

local function empty(stack, text)
    stack:Text(text, { size = Style.SIZE.body, color = Style.INK.LABEL })
end

local function pickedPath()
    return S.query and S.query.path or nil
end

local function fillBrowse(stack)
    local t = Cat.Tree()
    stack:Section(L["Categories"])
    if not t then return empty(stack, L["Open the Auction House to browse."]) end
    local at = pickedPath()
    local function walk(nodes, depth)
        for _, node in ipairs(nodes) do
            local path = Cat.Path(node)
            local kids = #node.children > 0
            local open = kids and Left.expanded[path] == true
            row(stack, { id = "cat:" .. path, text = node.name, color = open and { Style.Pop() } or Style.INK.TEXT,
                depth = depth, chevron = kids and (open and "open" or "closed") or nil,
                onClick = function() Left.PickCategory(node) end }, at == path)
            if open then walk(node.children, depth + 1) end
        end
    end
    walk(t, 0)
end

local function fillRecent(stack)
    local list = BP.Recent()
    stack:Section(L["Recent"], { value = #list > 0 and tostring(#list) or nil })
    if #list == 0 then return empty(stack, L["No searches yet."]) end
    for i, e in ipairs(list) do
        local node = e.path and Cat.Find(e.path)
        local where = e.path and (node and Cat.Label(node) or e.label or e.path)
        local words = e.text or ""
        local text = where and words ~= "" and string.format(L["%s in %s"], words, where) or where or words
        row(stack, { id = "recent:" .. i, text = text, onClick = function()
            if page.box:GetText() ~= words then page.box:SetText(words) end
            BP.Run({ text = words, path = e.path, label = where })
        end }, sameSearch(S.query, e))
    end
end

local function hideTip(b)
    if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(b) then GameTooltip:Hide() end
end

function Left.FavoriteMenu(id, owner)
    W.OpenMenu(owner, { "off" }, { off = L["Remove from favorites"] }, nil, function()
        BP.SetFavorite(id, false)
        Left.Fill(true)
    end, nil, { atCursor = true })
end

local function fillFavorites(stack)
    local list = BP.Favorites()
    stack:Section(L["Favorites"], { value = #list > 0 and tostring(#list) or nil })
    local api = C_AuctionHouse
    local game = api and api.HasFavorites and api.HasFavorites() == true
    if #list == 0 and not game then
        return empty(stack, L["No favorites yet. Right-click an item in the results to add it."])
    end
    local q = S.query
    row(stack, { id = "fav:all", text = L["Search all favorites"], onClick = BP.SearchFavorites },
        q ~= nil and q.favorites == true)
    for _, id in ipairs(list) do
        local info = ns.Items.Info(id)
        local name = info and info.name
        local quality = info and info.quality
        local line = stack:Line({ id = "fav:" .. id, text = name or string.format(L["Item %d"], id),
            color = name and { Parts.QualityColor(quality) } or Style.INK.OFF,
            link = function() return ns.Items.Hyperlink(id) end,
            tooltip = function(b)
                if not GameTooltip then return end
                GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
                ns.Items.SetTip(GameTooltip, tostring(id), id)
                GameTooltip:Show()
            end,
            leave = hideTip,
            onRightClick = function(b) Left.FavoriteMenu(id, b) end,
            onClick = function()
                local now = ns.Items.Name(id)
                if not now then return end
                if page.box:GetText() ~= now then page.box:SetText(now) end
                BP.Run({ text = now }, id)
            end })
        Parts.SetItemIcon(line, info and info.icon or nil, quality)
    end
end

local FILL = { browse = fillBrowse, recent = fillRecent, favorites = fillFavorites }

-- The list again. keep: a change in place (a node opened or shut, a pick),
-- rows gliding to their new spots and new ones fading in (Stack:Ease,
-- NORMAL); else (another chip) from the top, fading in FAST.
function Left.Fill(keep)
    local pane = Left.pane
    if not pane then return end
    local stack = pane.stack
    local at = stack:Scrolled()
    local spots = keep and pane:IsVisible() and stack:Spots() or nil
    stack:Begin()
    FILL[Left.mode](stack)
    stack:End()
    if keep then
        stack:ScrollTo(at)
        stack:Ease(spots)
    elseif animated(pane) then
        Motion.Fade(stack.scroll, 0, 1, Motion.FAST)
    end
    for id, chip in pairs(pane.chips) do chip.SetOn(id == Left.mode) end
end

function Left.Show(mode)
    if not FILL[mode] then return end
    Left.mode = mode
    Left.Fill()
end

-- The rows under a node being shut fade out (FAST) before the refill lets the
-- rows below glide up into their place.
local function fadeChildren(path, done)
    local stack = Left.pane.stack
    local prefix, faded = "cat:" .. path .. "/", false
    if animated(Left.pane) then
        for _, b in ipairs(stack.pieces) do
            local id = b.stackKey
            if type(id) == "string" and string.sub(id, 1, #prefix) == prefix then
                Motion.Fade(b, 1, 0, Motion.FAST)
                faded = true
            end
        end
    end
    if not faded then return done() end
    local token = {}
    Left.closing = token
    C_Timer.After(Motion.FAST, function() if Left.closing == token then Left.closing = nil; done() end end)
end

-- A category: opened and browsed with the words in the box, like the game's
-- own AH. A click on the picked one unpicks it (shutting it): its parent is
-- picked, or none, and the words then search everywhere.
function Left.PickCategory(node)
    local path = Cat.Path(node)
    local text = trim(page.box:GetText())
    local unpick = pickedPath() == path
    local shut = unpick and Left.expanded[path] == true
    if shut then Left.expanded[path] = nil
    elseif not unpick and #node.children > 0 then Left.expanded[path] = true end
    local function go()
        if not unpick then return BP.Run({ text = text, path = path, label = Cat.Label(node) }) end
        local up = #node.path > 1 and Cat.Find(table.concat(node.path, "/", 1, #node.path - 1))
        if up then return BP.Run({ text = text, path = Cat.Path(up), label = Cat.Label(up) }) end
        if text ~= "" then return BP.Run({ text = text }) end
        BP.Clear()
    end
    if shut then fadeChildren(path, go) else go() end
end

-- The chips fill the pane edge to edge whatever the font: each as wide as
-- its words, the room left over shared evenly.
function Left.FitChips()
    local pane = Left.pane
    if not pane or not pane.chips then return end
    local n = #Left.MODES
    local room = BP.LEFT_W - 2 * Parts.EDGE - W.CHIP_GAP * (n - 1)
    local words = {}
    for i, m in ipairs(Left.MODES) do
        local chip = pane.chips[m.id]
        chip.FitWidth()
        words[i] = chip:GetWidth() - 2 * W.CHIP_PAD
        room = room - words[i]
    end
    local x, each = Parts.EDGE, room / n
    for i, m in ipairs(Left.MODES) do
        local chip = pane.chips[m.id]
        local right = math.floor(x + words[i] + each + 0.5)
        chip:SetWidth(right - math.floor(x + 0.5))
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", pane, "TOPLEFT", math.floor(x + 0.5), -BP.CHIP_Y)
        x = x + words[i] + each + W.CHIP_GAP
    end
end

local function buildLeft(pane)
    Left.pane = pane
    pane.chips = {}
    for _, m in ipairs(Left.MODES) do
        local chip = W.Chip(pane, m.text)
        chip:SetScript("OnClick", function() Left.Show(m.id) end)
        pane.chips[m.id] = chip
    end
    Left.FitChips()
    pane.stack = Parts.Stack(pane, { top = BP.LEFT_TOP, bottom = 12 })
    Left.Fill()
end

-- ---------------------------------------------------------------------
-- The tools: the search box, the filter row
-- ---------------------------------------------------------------------

local QUALITY_NAMES = { [0] = L["Poor"], L["Common"], L["Uncommon"], L["Rare"], L["Epic"], L["Legendary"], L["Artifact"] }
local ONLY_NAMES = {
    UncollectedOnly = { "AUCTION_HOUSE_FILTER_UNCOLLECTED_ONLY", L["Uncollected only"] },
    CurrentExpansionOnly = { "AUCTION_HOUSE_FILTER_CURRENTEXPANSION_ONLY", L["Current expansion only"] },
    UpgradesOnly = { "AUCTION_HOUSE_FILTER_UPGRADES_ONLY", L["Upgrades only"] },
    ExactMatch = { "AUCTION_HOUSE_FILTER_EXACT_MATCH", L["Exact name only"] },
}

local function gameWord(name, fallback)
    local v = _G[name]
    return (type(v) == "string" and v ~= "") and v or fallback
end

-- A filter's words: a quality in its own color, the rest the game's own.
local function filterName(v)
    local q = qualityOf(v)
    if q then return hex({ Parts.QualityColor(q) }) .. gameWord("ITEM_QUALITY" .. q .. "_DESC", QUALITY_NAMES[q]) .. "|r" end
    local e = Enum and Enum.AuctionHouseFilter
    for key, words in pairs(ONLY_NAMES) do
        if filterValue(key, -1) == v then return gameWord(words[1], words[2]) end
    end
    if type(e) == "table" then
        for key, n in pairs(e) do if n == v then return tostring(key) end end
    end
    return tostring(v)
end

-- The game's filter groups (its filter menu's sections); the qualities alone
-- when the game has none to give.
function BP.FilterGroups()
    local api = C_AuctionHouse
    local groups = api and api.GetFilterGroups and api.GetFilterGroups()
    if type(groups) == "table" and #groups > 0 then return groups end
    local list = {}
    for _, q in ipairs(QUALITY) do list[#list + 1] = filterValue(q[1], q[2]) end
    return { { filters = list } }
end

-- The filter menu: the game's sections and their switches (Usable has its
-- own chip), then Reset to the defaults.
function BP.FilterMenu()
    local keys, values, titles = {}, {}, {}
    local usable = filterValue("UsableOnly", 2)
    for i, g in ipairs(BP.FilterGroups()) do
        local rows = {}
        local qualities = false
        for _, v in ipairs(type(g.filters) == "table" and g.filters or {}) do
            if type(v) == "number" and v ~= usable then
                rows[#rows + 1] = v
                if qualityOf(v) then qualities = true end
            end
        end
        if #rows > 0 then
            local t = "t" .. i
            keys[#keys + 1], titles[t] = t, true
            local name = _G.GetAHFilterCategoryName and g.category and GetAHFilterCategoryName(g.category)
            values[t] = (type(name) == "string" and name ~= "") and name
                or (qualities and gameWord("AUCTION_HOUSE_FILTER_CATEGORY_RARITY", L["Rarity"])) or L["Other"]
            for _, v in ipairs(rows) do
                local k = "f" .. v
                keys[#keys + 1], values[k] = k, filterName(v)
            end
        end
    end
    local exact = filterValue("ExactMatch", 5)
    keys[#keys + 1], titles.tsearch, values.tsearch = "tsearch", true, gameWord("SEARCH", L["Search"])
    keys[#keys + 1], values["f" .. exact] = "f" .. exact, filterName(exact)
    keys[#keys + 1], values.reset = "reset", L["Reset filters"]
    return keys, values, titles
end

function BP.PickFilter(k)
    if k == "reset" then
        S.filters.picked = {}
    else
        local v = tonumber(string.match(tostring(k), "^f(%d+)$"))
        if not v then return end
        S.filters.picked[v] = not BP.FilterOn(v)
    end
    BP.ApplyFilters()
end

-- The filter row as the state has it; the category on the right.
function BP.PaintTools()
    if not page then return end
    local changed = BP.FiltersChanged()
    page.rarity.SetLabel(changed > 0 and string.format(L["Filters %s"], pop(tostring(changed))) or L["Filters"])
    page.usable.SetOn(S.filters.usable)
    local q = S.query
    local label = q and (q.path or q.favorites) and q.label or ""
    local was = page.where:GetText()
    page.where:SetText(label)
    if animated(page.where) and was ~= label and label ~= "" then Motion.Fade(page.where, 0, 1, Motion.FAST) end
end

-- A filter changed: the search on screen again with it.
function BP.ApplyFilters()
    BP.PaintTools()
    if S.query then BP.Run(S.query) end
end

local function levelOf(box)
    local v = tonumber(trim(box:GetText()))
    if v and v >= 1 then return math.floor(v) end
    return nil
end

local function levelBox(parent, hintText)
    local e = W.Input(parent, { numeric = true, justify = "CENTER", maxLetters = 3, hint = hintText })
    e:SetWidth(BP.LEVEL_W)
    e.was = ""
    local function apply(self)
        local now = self:GetText() or ""
        if now == self.was then return end
        self.was = now
        S.filters.minLevel, S.filters.maxLevel = levelOf(page.from), levelOf(page.to)
        if S.filters.maxLevel and not S.filters.minLevel then S.filters.minLevel = 1 end
        BP.ApplyFilters()
    end
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus(); apply(self) end)
    e:HookScript("OnEditFocusLost", apply)
    W.PadNumber(e, function(dir)
        local v = (levelOf(e) or 0) + dir
        e:SetText(v >= 1 and tostring(math.min(999, v)) or "")
        apply(e)
    end)
    return e
end

local function smallText(parent, text)
    local t = Style.Text(parent, Style.SIZE.small, "LEFT")
    Style.InkText(t, "LABEL")
    t:SetText(text)
    return t
end

local function buildTools(right)
    local box = W.Input(right, { search = true, hint = L["Search the Auction House"] })
    box:SetPoint("TOPLEFT", right, "TOPLEFT", Parts.EDGE, -BP.BOX_TOP)
    box:SetPoint("TOPRIGHT", right, "TOPRIGHT", -Parts.EDGE, -BP.BOX_TOP)
    page.box = box
    page.complete = W.Complete(box, BP.Suggest)
    -- Enter searches what's typed; a suggestion picked with the arrows is
    -- filled in first (W.Complete's own Enter fills whenever its list shows,
    -- so "cloth" could never be searched while names with it were listed)
    local arrowed = false
    box:HookScript("OnArrowPressed", function() arrowed = page.complete:IsOpen() end)
    box:HookScript("OnTextChanged", function(_, user) if user then arrowed = false end end)
    local fill = box:GetScript("OnEnterPressed")
    box:SetScript("OnEnterPressed", function(self, ...)
        if arrowed and page.complete:IsOpen() then fill(self, ...) end
        arrowed = false
        page.complete:Close()
        self:ClearFocus()
        BP.Submit(self:GetText() or "")
    end)

    local filterRow = CreateFrame("Frame", nil, right)
    filterRow:SetPoint("TOPLEFT", right, "TOPLEFT", Parts.EDGE, -BP.FILTER_TOP)
    filterRow:SetPoint("TOPRIGHT", right, "TOPRIGHT", -Parts.EDGE, -BP.FILTER_TOP)
    filterRow:SetHeight(W.CHIP_HEIGHT)
    local level = smallText(filterRow, L["Level"])
    level:SetPoint("LEFT", filterRow, "LEFT", 0, 0)
    page.from = levelBox(filterRow, "1")
    page.from:SetPoint("LEFT", level, "RIGHT", 8, 0)
    local dash = smallText(filterRow, DASH)
    dash:SetPoint("LEFT", page.from, "RIGHT", 6, 0)
    page.to = levelBox(filterRow, "60")
    page.to:SetPoint("LEFT", dash, "RIGHT", 6, 0)
    page.rarity = W.MenuButton(filterRow, L["Filters"])
    page.rarity:SetScript("OnClick", function(owner)
        local keys, values, titles = BP.FilterMenu()
        W.OpenMenu(owner, keys, values, nil, BP.PickFilter, nil, {
            titles = titles, keepOpen = true, rows = #keys,
            checked = function(k)
                local v = tonumber(string.match(tostring(k), "^f(%d+)$"))
                return v ~= nil and BP.FilterOn(v)
            end,
        })
    end)
    page.rarity:SetPoint("LEFT", page.to, "RIGHT", 12, 0)
    page.usable = W.Chip(filterRow, L["Usable"])
    page.usable.FitWidth()
    page.usable:SetScript("OnClick", function()
        S.filters.usable = not S.filters.usable
        BP.ApplyFilters()
    end)
    page.usable:SetPoint("LEFT", page.rarity, "RIGHT", 8, 0)
    page.maxPrice = W.Input(filterRow, { justify = "RIGHT", hint = L["Max price"] })
    page.maxPrice:SetWidth(BP.PRICE_W)
    page.maxPrice:SetPoint("LEFT", page.usable, "RIGHT", 8, 0)
    page.maxPrice.was = ""
    local function applyPrice(self)
        local now = trim(self:GetText())
        if now == self.was then return end
        local c = now ~= "" and ns.SellPage.ReadMoney(now) or nil
        if now ~= "" and not c then
            self:SetText(self.was)
            return BP.Tell(string.format(L["Type a price like %s."], plainMoney(50000)), "WARN")
        end
        self.was = now
        S.filters.maxPrice = c
        BP.Refilter()
    end
    page.maxPrice:SetScript("OnEnterPressed", function(self) self:ClearFocus(); applyPrice(self) end)
    page.maxPrice:HookScript("OnEditFocusLost", applyPrice)
    W.PadNumber(page.maxPrice, function(dir)
        local c = ns.SellPage.StepMoney(ns.SellPage.ReadMoney(trim(page.maxPrice:GetText())), dir)
        page.maxPrice:SetText(c > 0 and plainMoney(c) or "")
        applyPrice(page.maxPrice)
    end)
    page.where = smallText(filterRow, "")
    page.where:SetJustifyH("RIGHT")
    page.where:SetWordWrap(false)
    page.where:SetPoint("RIGHT", filterRow, "RIGHT", 0, 0)
    page.where:SetPoint("LEFT", page.maxPrice, "RIGHT", 12, 0)
end

-- ---------------------------------------------------------------------
-- Room for the first-visit card (Window.lua builds it on this page)
-- ---------------------------------------------------------------------

local roomKey = {}
BP.shift = 0

-- The right pane moves down under the card while it shows, eased (NORMAL);
-- the categories stay where they are beside it.
function BP.Room(want, instant)
    if not page then return end
    local to = want and (ns.Window.OFFER_H + BP.ROOM_GAP) or 0
    if to == BP.shift then return end
    local from = BP.shift
    BP.shift = to
    local body, right = page.body, page.right
    local function put(v)
        right:ClearAllPoints()
        right:SetPoint("TOPLEFT", body, "TOPLEFT", BP.LEFT_W + 1, -v)
        right:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
    end
    if instant or not animated(page) then Motion.Tween(roomKey, to, to, 0, put)
    else Motion.Tween(roomKey, from, to, Motion.NORMAL, put) end
end

-- ---------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------

function BP.Build(p)
    page = p
    BP.page = p
    local body = CreateFrame("Frame", nil, p)
    body:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
    p.body = body
    local left = CreateFrame("Frame", nil, body)
    left:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
    left:SetWidth(BP.LEFT_W)
    p.left = left
    local rule = Parts.Rule(left, true)
    rule:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, -12)
    rule:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 0, 12)
    local right = CreateFrame("Frame", nil, body)
    right:SetPoint("TOPLEFT", body, "TOPLEFT", BP.LEFT_W + 1, 0)
    right:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
    p.right = right

    buildLeft(left)
    buildTools(right)
    local t = Parts.Table(right, {
        head = BP.COLS, top = BP.TABLE_TOP, bottom = BP.FOOT,
        rowHeight = { line = Parts.LINE, step = BP.STEP_H },
        make = { line = makeLine, step = makeStep },
        fill = { line = fillLine, step = fillStep },
        onClick = onClick, onEnter = onEnter, onLeave = onLeave,
        padMore = function(d)
            if d.kind == "line" and type(d.itemID) == "number" then return function(b) BP.RowMenu(d, b) end end
        end,
        link = function(d) return ns.Items.RowLink(d.kind == "step" and S.open or d) end,
        onSort = function(id, desc)
            S.sort.id, S.sort.desc = id, desc
            -- a cut-off list asks the server again in the new order
            if S.capped and SERVER_SORT[id] and S.query then return BP.Run(S.query) end
            BP.SortRows()
            BP.Rebuild(true)
        end,
    })
    t.head:SetSort(S.sort.id, S.sort.desc)
    p.table = t
    buildFooter(right)
    p.note = Style.Text(right, Style.SIZE.body, "CENTER")
    Style.InkText(p.note, "LABEL")
    p.note:SetPoint("CENTER", t.view, "CENTER", 0, 0)
    p.note:Hide()
    BP.PaintTools()
    BP.Changed(true)
end

-- Each time the tab shows.
function BP.Fill()
    if not page then return end
    Left.FitChips()
    Left.Fill(true)
    BP.Room(ns.Window.OfferWanted(), true)
    BP.PaintTools()
    BP.Rebuild(true)
    BP.PaintFooter()
    BP.PaintNote()
end

-- ---------------------------------------------------------------------
-- Staying true
-- ---------------------------------------------------------------------

-- Names and prices come in bursts: one repaint a frame for them.
local soon = false
local function repaintSoon()
    if soon or not (page and page:IsVisible()) then return end
    soon = true
    C_Timer.After(0, function()
        soon = false
        if not (page and page:IsVisible()) then return end
        BP.Rebuild(true)
        if Left.mode == "favorites" then Left.Fill(true) end
    end)
end

local function itemLoaded(_, itemID)
    if type(itemID) == "number" then BP.IndexLearn(itemID) end
    local list = type(itemID) == "number" and waiting[itemID]
    if list then
        waiting[itemID] = nil
        for _, r in ipairs(list) do fillInfo(r) end
        BP.SortRows()
    end
    if list or (Left.mode == "favorites" and BP.IsFavorite(itemID)) then repaintSoon() end
end
local function skillLoaded(_, itemID)
    local list = type(itemID) == "number" and skillWait[itemID]
    if not list then return end
    skillWait[itemID] = nil
    for _, r in ipairs(list) do r.level = skillOf(r) end
    BP.SortRows()
    repaintSoon()
end

-- Item and skill answers only matter while the Auction House is open: out in the
-- world GET_ITEM_INFO_RECEIVED fires all the time.
local itemEvents = CreateFrame("Frame")
local ITEM_EVENTS = { GET_ITEM_INFO_RECEIVED = itemLoaded, ITEM_DATA_LOAD_RESULT = itemLoaded,
    EXTRA_BROWSE_INFO_RECEIVED = skillLoaded }
itemEvents:SetScript("OnEvent", function(_, event, ...)
    local fn = ITEM_EVENTS[event]
    if fn then ns.SafeCall(fn, event, ...) end
end)
local function listen(on)
    for event in pairs(ITEM_EVENTS) do
        if on then itemEvents:RegisterEvent(event) else itemEvents:UnregisterEvent(event) end
    end
end

-- A click that would have been refused can go now (or no longer can).
ns.On("LineChanged", function()
    if page and page:IsVisible() then BP.PaintFooter() end
end)

-- New prices (a scan, a search): the usual column again, not under a pick.
ns.On("PricesChanged", function()
    if not page or S.running or S.open then return end
    for _, r in ipairs(S.rows) do
        r.usual = BP.Usual(r.key)
        r.pct = (not r.gone) and pctOf(r.unit, r.usual) or nil
    end
    repaintSoon()
end)

ns.On("OfferChanged", function(shown) BP.Room(shown) end)

-- The categories exist once the game's AH UI loaded.
ns.On("AHOpened", function()
    listen(true)
    if not page then return end
    if Left.mode == "browse" then Left.Fill(true) end
    BP.PaintFooter()
    BP.PaintNote()
end)

-- The AH closed: a purchase on its way may have gone through; that sentence
-- stays for the next visit.
ns.On("AHClosed", function()
    listen(false)
    if S.buying then BP.Tell(sentence("lost"), "WARN") end
    S.quote, S.buying = nil, false
    S.running = false
    if page then BP.PaintFooter(); BP.PaintNote() end
end)

DUI.On("StyleChanged", function()
    if not (page and page:IsVisible()) then return end
    Left.FitChips()
    BP.Rebuild(true)
    BP.PaintFooter()
end)
