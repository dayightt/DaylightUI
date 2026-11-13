local stub = require("stub")
local BW = require("bookworld")

-- The spellbook's Training page (Book/Training.lua): What's Training's list (its
-- WT_API, Api.lua) drawn as a Daylight UI page, with the tab only shown while that
-- addon is on.

-- A fake WT_API shaped like What's Training's own: GetSpells (fresh copies, {}
-- before Ready), GetSource, IsReady, and CallbackHandler's dot-syntax
-- RegisterCallback(owner, event, fn).
local function fakeApi(spells, opts)
    opts = opts or {}
    local a = { version = 1, handlers = {}, ready = opts.ready ~= false, spells = spells }
    a.IsReady = function() return a.ready end
    a.GetSpells = function()
        if opts.broken then error("WT_API went wrong") end
        if not a.ready then return {} end
        local out = {}
        for i, s in ipairs(a.spells) do
            local c = {}
            for k, v in pairs(s) do c[k] = v end
            out[i] = c
        end
        return out
    end
    a.GetSource = function(id)
        if id == 202 then return { kind = "weaponMaster", cost = 1000, trainers = { { name = "Woo Ping" } } } end
        return { kind = "trainer", cost = 0 }
    end
    a.RegisterCallback = function(owner, event, fn) a.handlers[event] = fn end
    a.Fire = function(event, ...) if a.handlers[event] then a.handlers[event](event, ...) end end
    return a
end

local function sp(id, name, rank, level, cost, status, extra)
    local s = { id = id, name = name, subText = rank, level = level, cost = cost, baseCost = cost, status = status,
        icon = 135808, quest = false, isItem = false }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
end

local function warriorList()
    return {
        sp(101, "Rend", "Rank 2", 10, 600, "available"),
        sp(102, "Thunder Clap", "Rank 1", 6, 100, "available"),
        sp(103, "Heroic Strike", "Rank 3", 16, 1800, "nextLevel"),
        sp(104, "Cleave", "Rank 1", 20, 2000, "notLevel"),
        sp(105, "Intimidating Shout", nil, 22, 4000, "notLevel"),
        sp(106, "Taunt", nil, 10, 0, "available", { quest = true }),
        sp(107, "Battle Shout", "Rank 1", 1, 10, "known"),
        sp(108, "Charge", "Rank 1", 4, 100, "known"),
        sp(202, "Swords", nil, 1, 1000, "weaponAvailable"),
    }
end

local function load(api, money)
    stub.Load({ before = function()
        BW.world({})()
        _G.WT_API = api
        _G.GetMoney = function() return money or 100000 end
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { Book = { enabled = true } } } } }
    end })
    return stub.book
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

local function tabIds(f)
    local out = {}
    for _, b in ipairs(f.tabs) do out[#out + 1] = b.id end
    return out
end

local function tabOf(f, id)
    for _, b in ipairs(f.tabs) do if b.id == id then return b end end
end

-- Opens the book, then its Training tab (a click, as a player would).
local function openTraining(ns)
    BW.Open(BW.SPELLBOOK)
    frame(30)
    tabOf(ns.Window.frame, "training"):Click()
    frame(30)
    return ns.Window.frame.pages.training
end

local function lines(page)
    local out = {}
    for _, p in ipairs(page.stack.used) do if p.lineSpec and p:IsShown() then out[#out + 1] = p end end
    return out
end

local function lineNames(page)
    local out = {}
    for _, p in ipairs(lines(page)) do out[#out + 1] = p.lineSpec.text end
    return out
end

local function line(page, name)
    for _, p in ipairs(lines(page)) do if p.lineSpec.text == name then return p end end
end

local function sections(page)
    local out = {}
    for _, p in ipairs(page.stack.used) do
        if p.isSection and p:IsShown() then out[#out + 1] = p.text:GetText() end
    end
    return out
end

local function foldRow(page, word)
    for _, p in ipairs(page.stack.used) do
        if p:IsShown() and p.text and not p.isSection and not p.lineSpec
            and string.find(p.text:GetText() or "", word or "already known", 1, true) then return p end
    end
end

local function open(page)
    foldRow(page, "weapon skills"):Click()
    frame(15)
end

T.test("book training: no What's Training, no tab (the window as before)", function()
    local ns = load(nil)
    T.deq(tabIds(ns.Window.frame), { "spells", "talents" })
    T.isnil(ns.Window.frame.pages.training)
end)

T.test("book training: with What's Training on, a third tab after Talents", function()
    local ns = load(fakeApi(warriorList()))
    T.deq(tabIds(ns.Window.frame), { "spells", "talents", "training" })
end)

T.test("book training: learn now first, then next level, then later by level, known folded", function()
    local ns = load(fakeApi(warriorList()))
    local page = openTraining(ns)
    T.truthy(page:IsVisible())
    T.eq(ns.Window.frame.current, "training")
    T.deq(sections(page), { "LEARN NOW · 3", "NEXT LEVEL", "LEVEL 20", "LEVEL 22" })
    T.deq(lineNames(page), { "Thunder Clap", "Rend", "Taunt", "Heroic Strike", "Cleave", "Intimidating Shout" })
    T.truthy(foldRow(page), "the known ones fold under one row")
    T.isnil(line(page, "Charge"), "known spells stay folded")
end)

T.test("book training: weapon skills fold under one row, out of Learn now and its total", function()
    local list = warriorList()
    list[#list + 1] = sp(203, "Polearms", nil, 20, 1000, "weaponNotLevel")
    list[#list + 1] = sp(204, "Staves", nil, 12, 1000, "weaponNextLevel")
    list[#list + 1] = sp(205, "Maces", nil, 1, 1000, "weaponKnown")
    local ns = load(fakeApi(list))
    local page = openTraining(ns)
    T.isnil(line(page, "Swords"), "folded")
    T.eq(page.total:GetText(), DaylightUI.MoneyString(700), "the total is what your class trainer asks")
    T.truthy(string.find(foldRow(page, "weapon skills").text:GetText(), "+ 3", 1, true), "a known weapon isn't one to plan")
    foldRow(page, "weapon skills"):Click()
    frame(15)
    T.falsy(line(page, "Swords").lineSpec.dim, "one you can learn now reads as one")
    T.deq(line(page, "Swords").lineSpec.valueColor, DaylightUI.Style.INK.MONEY)
    T.truthy(line(page, "Staves").lineSpec.dim)
    T.truthy(line(page, "Polearms").lineSpec.dim)
    T.eq(line(page, "Polearms").lineSpec.value ~= "", true, "its cost still shows")
    foldRow(page, "weapon skills"):Click()
    frame(15)
    T.isnil(line(page, "Swords"))
    ns.Training.Search("sword")
    T.deq(lineNames(page), { "Swords" }, "a search finds it folded or not")
end)

T.test("book training: a line you can learn shows its cost in gold; later ones are dimmed", function()
    local ns = load(fakeApi(warriorList()), 1000)
    local page = openTraining(ns)
    local rend = line(page, "Rend")
    T.falsy(rend.lineSpec.dim)
    T.deq(rend.lineSpec.valueColor, DaylightUI.Style.INK.MONEY)
    T.eq(rend.lineSpec.sub, "Rank 2")
    open(page)
    local swords = line(page, "Swords")
    T.deq(swords.lineSpec.valueColor, DaylightUI.Style.INK.MONEY)
    T.eq(swords.lineSpec.sub, "From a weapon master")
    T.eq(line(page, "Taunt").lineSpec.sub, "From a quest")
    T.eq(line(page, "Taunt").lineSpec.value, "", "a quest costs nothing")
    T.truthy(line(page, "Cleave").lineSpec.dim)
end)

T.test("book training: more than you have is red, and so is the total", function()
    local ns = load(fakeApi(warriorList()), 500)
    local page = openTraining(ns)
    T.deq(line(page, "Rend").lineSpec.valueColor, DaylightUI.Style.INK.BAD)
    T.deq(line(page, "Thunder Clap").lineSpec.valueColor, DaylightUI.Style.INK.MONEY)
    T.eq(page.total:GetText(), DaylightUI.MoneyString(700))
    T.rgb({ page.total:GetTextColor() }, DaylightUI.Style.INK.BAD)
end)

T.test("book training: the known row opens and shuts the known spells", function()
    local ns = load(fakeApi(warriorList()))
    local page = openTraining(ns)
    foldRow(page):Click()
    frame(15)
    T.truthy(line(page, "Charge"))
    T.truthy(line(page, "Battle Shout"))
    T.truthy(line(page, "Charge").lineSpec.dim)
    foldRow(page):Click()
    frame(15)
    T.isnil(line(page, "Charge"))
end)

T.test("book training: search by name or rank, folded ones included", function()
    local ns = load(fakeApi(warriorList()))
    local page = openTraining(ns)
    page.search:SetText("char")
    ns.Training.Search("char")
    T.deq(lineNames(page), { "Charge" })
    ns.Training.Search("rank 3")
    T.deq(lineNames(page), { "Heroic Strike" })
    ns.Training.Search("nothing like it")
    T.deq(lineNames(page), {})
    T.truthy(page.note:IsShown())
    T.eq(page.note:GetText(), "No spells match.")
end)

T.test("book training: a chip per group shown; the Known chip opens it", function()
    local ns = load(fakeApi(warriorList()))
    local page = openTraining(ns)
    local groups = {}
    for _, c in ipairs(page.chips) do if c:IsShown() then groups[#groups + 1] = c.group end end
    T.deq(groups, { "now", "next", "later", "weapons", "known" })
    for _, c in ipairs(page.chips) do if c.group == "known" then c:Click() end end
    frame(15)
    T.truthy(line(page, "Charge"))
end)

T.test("book training: What's Training changes (a level up) and the open page follows", function()
    local api = fakeApi(warriorList())
    local ns = load(api)
    local page = openTraining(ns)
    api.spells[3].status = "available"   -- Heroic Strike
    api.Fire("LevelChanged", 16)
    frame(5)
    T.deq(sections(page), { "LEARN NOW · 4", "LEVEL 20", "LEVEL 22" })
    T.falsy(line(page, "Heroic Strike").lineSpec.dim)
end)

T.test("book training: still reading, then Ready fills it", function()
    local api = fakeApi(warriorList(), { ready = false })
    local ns = load(api)
    local page = openTraining(ns)
    T.truthy(page.note:IsShown())
    T.eq(#lines(page), 0)
    api.ready = true
    api.Fire("Ready")
    frame(5)
    T.falsy(page.note:IsShown())
    T.eq(#lines(page), 6)
end)

T.test("book training: What's Training's API erroring never breaks the window", function()
    local ns = load(fakeApi(warriorList(), { broken = true }))
    local page
    T.noerror(function() page = openTraining(ns) end)
    T.truthy(page.note:IsShown())
end)

T.test("book training: hovering a weapon skill names its weapon master", function()
    local ns = load(fakeApi(warriorList()))
    local page = openTraining(ns)
    local tip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
    _G.GameTooltip = tip
    function tip:SetOwner(o) self.__owner = o end
    function tip:GetOwner() return self.__owner end
    function tip:IsOwned(o) return self.__owner == o end
    local asked
    tip.SetSpellByID = function(_, id) asked = id end
    open(page)
    local added = {}
    local flush = DaylightUI.Tips.Flush
    DaylightUI.Tips.Flush = function(t, opts) added = true; return flush(t, opts) end
    local swords = line(page, "Swords")
    T.noerror(function() swords:GetScript("OnEnter")(swords) end)
    DaylightUI.Tips.Flush = flush
    T.eq(asked, 202, "the spell's own tooltip")
    T.truthy(added, "our lines under it")
    swords:GetScript("OnLeave")(swords)
    _G.GameTooltip = nil
end)

T.test("book training: a weapon master's line says the city and district", function()
    local ns = load(fakeApi(warriorList()))
    local maps = { [1453] = "Stormwind City", [1457] = "Darnassus" }
    _G.C_Map = _G.C_Map or {}
    local was, wasArea = C_Map.GetMapInfo, C_Map.GetAreaInfo
    C_Map.GetMapInfo = function(id) return maps[id] and { name = maps[id] } or nil end
    C_Map.GetAreaInfo = function(id) return id == 1660 and "Warrior's Terrace" or nil end
    local T2 = ns.Training
    T.eq(T2.MasterText({ npc = 11866, name = "Ilyenia Moonfire", uiMapId = 1457 }), "Ilyenia Moonfire", "off as shipped: the name alone")
    DaylightUI:Set("Book", "masterSpot", true)
    T.eq(T2.MasterText({ npc = 11866, name = "Ilyenia Moonfire", uiMapId = 1457 }),
        "Ilyenia Moonfire, Darnassus, Warrior's Terrace", "the game's own city and district names")
    T.eq(T2.MasterText({ npc = 11867, name = "Woo Ping" }), "Woo Ping, Stormwind City, Trade District",
        "no map on the record: the list's map")
    T.eq(T2.MasterText({ npc = 11869, name = "Ansekhwa", uiMapId = 1456 }), "Ansekhwa, Thunder Bluff",
        "no district known: the city only")
    T.eq(T2.MasterText({ name = "Someone" }), "Someone", "unknown: the name alone")
    C_Map.GetMapInfo, C_Map.GetAreaInfo = was, wasArea
end)

T.test("book training: closing on Training and opening the book again starts on the spellbook", function()
    local ns = load(fakeApi(warriorList()))
    openTraining(ns)
    ns.Window.Close()
    frame(30)
    BW.Open(BW.SPELLBOOK)
    frame(30)
    T.eq(ns.Window.frame.current, "spells")
    T.eq(ns.Window.frame.tab, "spells")
end)

local function chipRows(page)
    local rows = {}
    for _, c in ipairs(page.chips) do
        if c:IsShown() then
            local y = select(5, c:GetPoint(1))
            rows[y] = (rows[y] and rows[y] .. "," or "") .. c.group
        end
    end
    return rows
end

local function resize(page, w)
    page.GetWidth = function() return w end   -- the window's new width, held through refreshes
    page:GetScript("OnSizeChanged")(page, w, page:GetHeight())
    frame(30)   -- chips and list glide into place
end

T.test("book training: chips that don't fit beside the search box wrap below it, none hidden", function()
    local ns = load(fakeApi(warriorList()))
    local page = openTraining(ns)
    resize(page, 380)
    local shown, rows = 0, 0
    for _, c in ipairs(page.chips) do if c:IsShown() then shown = shown + 1 end end
    T.eq(shown, 5, "every group's chip shown")
    for _ in pairs(chipRows(page)) do rows = rows + 1 end
    T.truthy(rows >= 2, "on more than one row")
    local search = page.search
    for _, c in ipairs(page.chips) do
        if c:IsShown() and select(5, c:GetPoint(1)) == -11 then
            T.truthy(select(4, c:GetPoint(1)) + c:GetWidth() <= 380 - ns.Training.EDGE - 160, c.group .. " clear of the search box")
        end
    end
    T.truthy(page.chipsTop > ns.Training.TOP, "the list moved down for the extra row")
end)

T.test("book training: resizing rewraps the chips at once, and widening puts them back on one row", function()
    local ns = load(fakeApi(warriorList()))
    local page = openTraining(ns)
    resize(page, 380)
    T.truthy(page.chipsTop > ns.Training.TOP)
    resize(page, 900)
    local rows = 0
    for _ in pairs(chipRows(page)) do rows = rows + 1 end
    T.eq(rows, 1)
    T.eq(page.chipsTop, ns.Training.TOP, "the list back up")
end)

T.test("book training: the list glides to its new top when the chips wrap", function()
    local ns = load(fakeApi(warriorList()))
    local page = openTraining(ns)
    resize(page, 380)
    frame(30)
    T.eq(page.listTop, page.chipsTop, "settled under the last row of chips")
    T.eq(select(5, page.stack.scroll:GetPoint(1)), -page.chipsTop)
end)
