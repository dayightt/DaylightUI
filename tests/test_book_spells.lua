local stub = require("stub")
local BW = require("bookworld")

-- The spellbook page (Book/SpellData.lua, Spells.lua, Cast.lua): the game's
-- spellbook (bookworld's C_SpellBook) as one list, with a section per skill line.

local function load(spec, settings)
    spec = spec or {}
    stub.Load({ before = function()
        BW.world(spec)()
        local book = { enabled = true }
        for k, v in pairs(settings or {}) do book[k] = v end
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { Book = book } } } }
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

local function openBook(ns)
    BW.Open(BW.SPELLBOOK)
    frame(30)
    return ns.Window.frame.pages.spells
end

local function cells(page)
    local out = {}
    for _, p in ipairs(page.stack.used) do
        if p.cells then for _, b in ipairs(p.cells) do if b:IsShown() and b.cell then out[#out + 1] = b end end end
    end
    return out
end

local function names(page)
    local out = {}
    for _, b in ipairs(cells(page)) do out[#out + 1] = b.cell.name .. (b.cell.rank and (" " .. b.cell.rank) or "") end
    return out
end

local function cellOf(page, name, rank)
    for _, b in ipairs(cells(page)) do
        if b.cell.name == name and (rank == nil or b.cell.rank == rank) then return b end
    end
end

-- The fake game keeps no screen rects, so a row says where it is (as in game).
local function placed(b)
    b.GetLeft = function() return 100 end
    b.GetBottom = function() return 200 end
    return b
end

local function sectionNames(d)
    local out = {}
    for _, s in ipairs(d.sections) do out[#out + 1] = s.name end
    return out
end

T.test("book spells: a section per skill line the game lists, shouldHide left out", function()
    local ns = load({ book = BW.MageBook() })
    local d = ns.SpellData.Read(false)
    T.deq(sectionNames(d), { "General", "Fire" })
    T.truthy(d.anyLow)
end)

T.test("book spells: the warrior's Stances flyout opens into its spells, loose copies skipped", function()
    local ns = load()
    local d = ns.SpellData.Read(false)
    T.deq(sectionNames(d), { "General", "Arms", "Fury", "Protection" })
    local general = {}
    for _, s in ipairs(d.sections[1].spells) do general[#general + 1] = s.name end
    T.deq(general, { "Attack", "Battle Stance", "Defensive Stance", "Blood Fury", "Hardiness" })
    T.falsy(d.anyLow, "a warrior has no lower rank")
end)

T.test("book spells: the page lists every spell, two to a line, chips per section", function()
    local ns = load()
    local page = openBook(ns)
    T.truthy(page:IsVisible())
    T.eq(#cells(page), 9)
    T.truthy(cellOf(page, "Rend", "Rank 1"))
    local shown = 0
    for _, c in ipairs(page.chips) do if c:IsShown() then shown = shown + 1 end end
    T.eq(shown, 4)
    T.falsy(page.switch:IsShown(), "no lower ranks: the switch hides (the game's rule for Warriors and Rogues)")
end)

T.test("book spells: chips that don't fit fold into More, which reaches every section", function()
    local ns = load()
    local page = openBook(ns)
    T.falsy(page.more and page.more:IsShown(), "every chip fits: no More")
    page:SetWidth(330)
    ns.Spells.Fill(page)
    local shown, hidden = 0, {}
    for i, c in ipairs(page.chips) do
        if c:IsShown() then shown = shown + 1 elseif c.section and i <= #ns.Spells.data.sections then hidden[#hidden + 1] = c.section end
    end
    T.truthy(shown < #ns.Spells.data.sections, "some chips no longer fit")
    T.truthy(page.more:IsShown(), "More takes the rest")
    T.eq(#ns.Spells.folded, #hidden, "More holds exactly the chips that went")
    T.eq(shown + #ns.Spells.folded, #ns.Spells.data.sections, "every section reachable")
    local W = DaylightUI.Widgets
    local was, asked = W.OpenMenu, nil
    W.OpenMenu = function(owner, keys, values, current, onPick) asked = { keys = keys, values = values, pick = onPick } end
    page.more:Click()
    W.OpenMenu = was
    T.truthy(asked, "a menu opens")
    T.eq(asked.values[asked.keys[1]], hidden[1].name)
    local jumped
    local jump = ns.Spells.Jump
    ns.Spells.Jump = function(section) jumped = section end
    asked.pick(asked.keys[1])
    ns.Spells.Jump = jump
    T.eq(jumped, hidden[1], "picking one jumps to its section")
    local mx = select(4, page.more:GetPoint(1))
    local last
    for _, c in ipairs(page.chips) do if c:IsShown() then last = c end end
    T.truthy(mx >= select(4, last:GetPoint(1)) + last:GetWidth(), "More sits after the last chip")
end)

local function resize(page, w)
    page.GetWidth = function() return w end   -- held through refills
    page:GetScript("OnSizeChanged")(page, w, page:GetHeight())
end

T.test("book spells: resizing refits the chips at once, and widening brings them back", function()
    local ns = load()
    local page = openBook(ns)
    resize(page, 330)
    frame(30)
    T.truthy(page.more:IsShown(), "folded mid-drag, before any refill")
    resize(page, 900)
    frame(30)
    T.falsy(page.more:IsShown(), "all fit again")
    for i = 1, #ns.Spells.data.sections do T.truthy(page.chips[i]:IsShown(), page.chips[i].section.name) end
end)

T.test("book spells: More glides from where it is to its new spot", function()
    local ns = load()
    local page = openBook(ns)
    resize(page, 330)
    frame(30)
    local start = select(4, page.more:GetPoint(1))
    resize(page, 290)
    frame(1)
    local mid = select(4, page.more:GetPoint(1))
    frame(30)
    local stop = select(4, page.more:GetPoint(1))
    T.truthy(stop ~= start, "it moved")
    T.truthy(mid ~= stop, "not in one jump")
end)

T.test("book spells: More shown again lands on its new spot, not where an old glide was heading", function()
    local ns = load()
    local page = openBook(ns)
    resize(page, 330)
    frame(30)
    resize(page, 290)   -- a glide starts
    frame(1)
    resize(page, 900)   -- More hides mid-glide
    resize(page, 330)   -- and comes back
    frame(30)
    local last
    for _, c in ipairs(page.chips) do if c:IsShown() then last = c end end
    T.eq(select(4, page.more:GetPoint(1)), select(4, last:GetPoint(1)) + last:GetWidth() + DaylightUI.Widgets.CHIP_GAP,
        "right after the last chip")
end)

T.test("book spells: Hide lower ranks on lists the top rank only; off, the lower ranks follow it", function()
    local ns = load({ book = BW.MageBook() })
    local page = openBook(ns)
    T.truthy(page.switch:IsShown())
    T.deq(names(page), { "Attack", "Fireball Rank 3", "Fire Blast Rank 1" })
    page.switch:Click()
    T.deq(names(page), { "Attack", "Fireball Rank 3", "Fireball Rank 2", "Fireball Rank 1", "Fire Blast Rank 1" })
    T.near(cellOf(page, "Fireball", "Rank 1").icon:GetAlpha(), 1, 0.001, "a lower rank looks like any spell")
    T.falsy(cellOf(page, "Fireball", "Rank 1").glow:IsShown(), "a lower rank shown for the first time doesn't glow as new")
    page.switch:Click()
    T.deq(names(page), { "Attack", "Fireball Rank 3", "Fire Blast Rank 1" })
end)

T.test("book spells: the Hide lower ranks switch keeps the list where it was scrolled", function()
    local ns = load({ book = BW.MageBook() })
    local page = openBook(ns)
    page.stack.scroll:SetHeight(10)
    page.stack:ScrollTo(30)
    local at = page.stack:Scrolled()
    T.truthy(at > 0, "the fake list scrolls at all")
    page.switch:Click()
    T.eq(page.stack:Scrolled(), at, "showing lower ranks doesn't jump back to the top")
    page.switch:Click()
    T.eq(page.stack:Scrolled(), at, "nor does hiding them")
end)

T.test("book spells: two ranks of a spell the game doesn't call low: only the highest is listed", function()
    local book = BW.MageBook()
    table.insert(book.lines[2].items, { name = "Blessing of Might", sub = "Rank 2", spellID = 19834, icon = 23 })
    table.insert(book.lines[2].items, { name = "Blessing of Might", sub = "Rank 1", spellID = 19740, icon = 23 })
    local ns = load({ book = book })
    local page = openBook(ns)
    T.deq(names(page), { "Attack", "Fireball Rank 3", "Fire Blast Rank 1", "Blessing of Might Rank 2" })
    page.switch:Click()
    T.deq(names(page), { "Attack", "Fireball Rank 3", "Fireball Rank 2", "Fireball Rank 1", "Fire Blast Rank 1",
        "Blessing of Might Rank 2", "Blessing of Might Rank 1" })
end)

-- A player's Paladin: the Blessings are a flyout in Retribution, listed highest rank
-- first, and its spells have no book slot.
T.test("book spells: a flyout's lower ranks (the Paladin's Blessings) hide too, the highest kept", function()
    local book = BW.MageBook()
    local blessings = { 20217, 19838, 19835, 19740, 19850, 19742 }
    table.insert(book.lines[2].items, { name = "Blessings", flyout = blessings, flyoutID = 2 })
    local loose = {
        { "Blessing of Kings", nil, 20217 }, { "Blessing of Might", "Rank 3", 19838 },
        { "Blessing of Might", "Rank 2", 19835 }, { "Blessing of Might", "Rank 1", 19740 },
        { "Blessing of Wisdom", "Rank 2", 19850 }, { "Blessing of Wisdom", "Rank 1", 19742 },
    }
    for _, l in ipairs(loose) do
        table.insert(book.lines[2].items, { name = l[1], sub = l[2], spellID = l[3], icon = 23, loose = true })
    end
    local ns = load({ book = book })
    local page = openBook(ns)
    T.deq(names(page), { "Attack", "Fireball Rank 3", "Fire Blast Rank 1",
        "Blessing of Kings", "Blessing of Might Rank 3", "Blessing of Wisdom Rank 2" })
    page.switch:Click()
    T.deq(names(page), { "Attack", "Fireball Rank 3", "Fireball Rank 2", "Fireball Rank 1", "Fire Blast Rank 1",
        "Blessing of Kings", "Blessing of Might Rank 3", "Blessing of Might Rank 2", "Blessing of Might Rank 1",
        "Blessing of Wisdom Rank 2", "Blessing of Wisdom Rank 1" })
end)

T.test("book spells: a click on a section's header folds it, remembered per character; a search shows it anyway", function()
    local ns = load({ book = BW.MageBook() })
    local page = openBook(ns)
    local function headOf(name)
        for _, p in ipairs(page.stack.used) do
            if p.section and p.section.name == name and p:IsShown() then return p end
        end
    end
    headOf("Fire"):Click()
    T.deq(names(page), { "Attack" })
    T.eq(headOf("Fire").state:GetText(), "+")
    T.eq(DaylightUI.DB.Character().spellFolds.Fire, true)
    ns.Spells.Fill(page)
    T.deq(names(page), { "Attack" }, "still folded on the next fill")
    page.search:SetText("fire")
    T.deq(names(page), { "Fireball Rank 3", "Fire Blast Rank 1" })
    page.search:SetText("")
    headOf("Fire"):Click()
    T.deq(names(page), { "Attack", "Fireball Rank 3", "Fire Blast Rank 1" })
    T.isnil(DaylightUI.DB.Character().spellFolds.Fire)
end)

T.test("book spells: search matches names and ranks", function()
    local ns = load({ book = BW.MageBook() }, { hideLowRanks = false })
    local page = openBook(ns)
    page.search:SetText("fire")
    T.deq(names(page), { "Fireball Rank 3", "Fireball Rank 2", "Fireball Rank 1", "Fire Blast Rank 1" })
    page.search:SetText("rank 2")
    T.deq(names(page), { "Fireball Rank 3", "Fireball Rank 2" }, "the top rank stays as the lower rank's heading")
    page.search:SetText("nothing like it")
    T.eq(#cells(page), 0)
    T.truthy(page.note:IsShown())
end)

T.test("book spells: a pet section with a pet", function()
    local book = BW.MageBook()
    book.pet = { { name = "Firebolt", sub = "Rank 1", spellID = 3110, icon = 5, autocast = true } }
    local ns = load({ book = book })
    local d = ns.SpellData.Read(false)
    T.eq(d.sections[#d.sections].name, PET or "Pet")
    T.truthy(d.sections[#d.sections].spells[1].pet)
    local a = ns.Cast.Attributes(d.sections[#d.sections].spells[1])
    T.eq(a.type1, "macro")
    T.eq(a.macrotext1, "/cast Firebolt")
    T.eq(a.macrotext2, "/petautocasttoggle Firebolt")
end)

T.test("book spells: the cast button: out of combat only, on UIParent, never the window's child", function()
    local ns = load()
    local page = openBook(ns)
    local b = placed(cellOf(page, "Rend"))
    b:GetScript("OnEnter")(b)
    local cast = ns.Cast.button
    T.truthy(cast and cast:IsShown())
    T.eq(cast:GetParent(), UIParent)
    T.eq(cast:GetAttribute("type1"), "spell")
    T.eq(cast:GetAttribute("spell"), 772)
    -- A passive casts nothing: the button goes.
    local p = placed(cellOf(page, "Hardiness"))
    p:GetScript("OnEnter")(p)
    T.falsy(cast:IsShown())
    -- A fight starts: the button hides as it begins and isn't laid in a fight.
    b:GetScript("OnEnter")(b)
    T.truthy(cast:IsShown())
    stub.EnterCombat()
    T.falsy(cast:IsShown())
    T.noerror(function() b:GetScript("OnEnter")(b) end)
    T.falsy(cast:IsShown())
    stub.LeaveCombat()
end)

-- Closing the book with the mouse on a spell left its tooltip up for good, since
-- the row hid under it and no OnLeave ever came.
T.test("book spells: closing the window under the mouse takes the spell's tooltip with it", function()
    for _, close in ipairs({
        function(ns) ns.Window.Close() end,
        function() BW.Toggle(BW.SPELLBOOK) end,   -- the game's key
        function() BW.Escape() end,
    }) do
        local ns = load()
        local tip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
        _G.GameTooltip = tip
        function tip:SetOwner(o) self.__owner = o end
        function tip:GetOwner() return self.__owner end
        function tip:IsOwned(o) return self.__owner == o end
        local page = openBook(ns)
        local b = placed(cellOf(page, "Rend"))
        b:GetScript("OnEnter")(b)
        T.truthy(GameTooltip:IsShown())
        T.truthy(ns.Cast.button:IsShown())
        close(ns)
        frame(30)
        T.falsy(GameTooltip:IsShown(), "the tooltip goes with the window")
        T.falsy(ns.Cast.button:IsShown(), "and the cast button")
    end
end)

T.test("book spells: drag picks the spell up out of combat; in a fight nothing is called", function()
    local ns = load()
    local page = openBook(ns)
    local b = cellOf(page, "Rend")
    b:GetScript("OnDragStart")(b)
    T.eq(#BW.Calls("PickupSpellBookItem"), 1)
    T.eq(BW.Calls("PickupSpellBookItem")[1][1], b.cell.slot)
    stub.EnterCombat()
    T.noerror(function() b:GetScript("OnDragStart")(b) end)
    T.eq(#BW.Calls("PickupSpellBookItem"), 1)
    stub.LeaveCombat()
    -- A stance (from the flyout, no book slot) picks up by spell id.
    local s = cellOf(page, "Battle Stance")
    s:GetScript("OnDragStart")(s)
    T.eq(BW.Calls("PickupSpell")[1][1], 2457)
end)

T.test("book spells: Shift-click links in chat, or writes the name into the macro being edited", function()
    local ns = load()
    local page = openBook(ns)
    local old = _G.IsModifiedClick
    _G.IsModifiedClick = function(k) return k == "CHATLINK" end
    local b = cellOf(page, "Rend")
    b:GetScript("OnClick")(b, "LeftButton")
    T.eq(BW.Calls("InsertLink")[1][1], "|Hspell:772|h[Rend]|h")
    _G.MacroFrameText = { HasFocus = function() return true end }
    b:GetScript("OnClick")(b, "LeftButton")
    T.eq(BW.Calls("InsertLink")[2][1], "Rend(Rank 1)")
    _G.MacroFrameText = nil
    _G.IsModifiedClick = old
end)

T.test("book spells: a new spell glows until hovered; the first look ever glows nothing", function()
    local ns = load()
    local page = openBook(ns)
    for _, b in ipairs(cells(page)) do T.falsy(b.glow:IsShown(), b.cell.name) end
    table.insert(BW.book.lines[2].items, { name = "Overpower", sub = "Rank 1", spellID = 7384, icon = 23 })
    stub.FireEvent("SPELLS_CHANGED")
    frame(2)
    local b = cellOf(page, "Overpower")
    T.truthy(b and b.glow:IsShown())
    b:GetScript("OnEnter")(b)
    T.falsy(b.glow:IsShown())
    T.truthy(DaylightUI.DB.Character().spellsSeen[7384])
end)

T.test("book spells: the cooldown sweep comes from the game's duration object", function()
    local ns = load()
    local page = openBook(ns)
    local b = cellOf(page, "Rend")
    local got
    b.cd.SetCooldownFromDurationObject = function(_, d) got = d end
    ns.Spells.PaintCooldown(b)
    T.eq(got and got.slot, b.cell.slot)
end)

T.test("book spells: the page opens in a fight with no error", function()
    local ns = load()
    BW.LoadBook()
    stub.EnterCombat()
    T.noerror(function() BW.Open(BW.SPELLBOOK); frame(30) end)
    stub.LeaveCombat()
end)

-- The click-cast switch on the spellbook page (the unit frames' binder).
local function loadUF()
    stub.Load({ module = true, before = function()
        BW.world({})()
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { Book = { enabled = true } } } } }
    end })
    return stub.book
end

T.test("book spells: no unit frames, no Click-cast switch", function()
    local ns = load()
    local page = openBook(ns)
    T.falsy(page.bind:IsShown())
end)

T.test("book spells: Click-cast on, a click on a spell binds that click; again removes it; nothing casts", function()
    local ns = loadUF()
    local page = openBook(ns)
    T.truthy(page.bind:IsShown(), "the switch sits on our page")
    page.bind:Click()
    T.truthy(ns.Spells.binding)
    local b = placed(cellOf(page, "Rend"))
    b:GetScript("OnEnter")(b)
    T.falsy(ns.Cast.button and ns.Cast.button:IsShown(), "no cast button while binding")
    _G.IsShiftKeyDown = function() return true end
    b:GetScript("OnClick")(b, "RightButton")
    _G.IsShiftKeyDown = nil
    local list = DaylightUI.DB.Character().clickCast[DaylightUI.DB.SpecGroup()]
    T.eq(#list, 1)
    T.eq(list[1].spell, 772)
    T.eq(list[1].mods, "shift")
    T.eq(list[1].button, "RightButton")
    local bb = cellOf(page, "Rend")
    T.truthy(bb.rank:GetText() ~= nil and bb.rank:GetText():find("Right") ~= nil, "the click shows on the row")
    _G.IsShiftKeyDown = function() return true end
    bb:GetScript("OnClick")(bb, "RightButton")
    _G.IsShiftKeyDown = nil
    T.eq(#list, 0)
    -- A passive binds nothing.
    local p = cellOf(page, "Hardiness")
    p:GetScript("OnClick")(p, "LeftButton")
    T.eq(#list, 0)
end)

T.test("book spells: closing the window ends click-cast mode; the switch goes off", function()
    local ns = loadUF()
    local page = openBook(ns)
    page.bind:Click()
    ns.Window.Close()
    frame(30)
    T.falsy(ns.Spells.binding)
    T.falsy(DaylightUI.ClickBind.On())
end)

-- Clique's own tab sits on the game's book, which ours covers: the page links to it.
local function loadClique(name, opened)
    stub.Load({ before = function()
        BW.world({})()
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { Book = { enabled = true } } } } }
        stub.loadedAddOns[name] = true
        _G[name] = { ShowBindingConfig = function(self) opened[#opened + 1] = self end }
    end })
    return stub.book
end

T.test("book spells: no Clique, no Clique link", function()
    local ns = load()
    local page = openBook(ns)
    T.falsy(page.clique:IsShown())
end)

T.test("book spells: with Clique loaded, the link opens its bindings window and closes the book", function()
    for _, name in ipairs({ "Clique", "CliqueForever" }) do
        local opened = {}
        local ns = loadClique(name, opened)
        local page = openBook(ns)
        T.truthy(page.clique:IsShown(), name .. ": the link shows")
        T.eq(page.clique.text:GetText(), "Open Clique")
        page.clique:Click()
        T.eq(#opened, 1, name .. ": Clique's own opener ran once")
        T.eq(opened[1], _G[name], name .. ": called on Clique's addon table")
        frame(30)
        T.falsy(DaylightUI.Win.IsOpen(ns.Window.frame), name .. ": the book makes way")
        _G[name] = nil
    end
end)

T.test("book spells: Clique loaded but broken, the link stays hidden and nothing errors", function()
    local ns
    stub.Load({ before = function()
        BW.world({})()
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { Book = { enabled = true } } } } }
        stub.loadedAddOns.Clique = true
        _G.Clique = nil
    end })
    ns = stub.book
    local page = openBook(ns)
    T.falsy(page.clique:IsShown())
    T.noerror(function() ns.Spells.OpenClique() end)
end)
