local stub = require("stub")
local BW = require("bookworld")

-- The spellbook in a fight (Book/Fight.lua, setting fightBook on). Daylight UI's
-- book stays, with a secure layer laid over it as the fight starts that casts,
-- scrolls, switches tabs and closes, and P, N and Escape go to it. The window
-- itself never turns protected, since it must open and close in a fight.

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
local function settle() frame(30) end

local function open(ns) return DaylightUI.Win.IsOpen(ns.Window.frame) end
local function layer(ns) return ns.Fight.h end
local function veil() return DaylightUI.Win.Followers.veil end

-- A long book: one line of 40 spells, more than the list shows.
local function longBook()
    local items = {}
    for i = 1, 40 do items[i] = { name = "Spell " .. i, sub = "Rank 1", spellID = 1000 + i, icon = i } end
    items[#items + 1] = { name = "Toughness", sub = "Passive", spellID = 2000, icon = 99, passive = true }
    return { lines = { { name = "General", icon = 1, items = items } } }
end

local function casts(ns)
    local out = {}
    local n = layer(ns).list:GetAttribute("n") or 0
    for i = 1, n do out[i] = ns.Fight.casts[i] end
    return out
end

T.test("book fight: P in a fight opens ours on the spellbook, no error, the game's stays parked", function()
    local ns = load({ loaded = true })
    stub.EnterCombat()
    T.eq(PlayerSpellsFrame:GetParent(), veil(), "not handed back")
    T.noerror(function() BW.Key("P"); settle() end)
    T.eq(open(ns), true)
    T.eq(ns.Window.frame.current, "spells")
    T.eq(PlayerSpellsFrame:IsShown(), false, "the game's book stays shut")
    local h = layer(ns)
    T.eq(h:GetAttribute("open"), true)
    T.eq(h.close:IsShown(), true, "our X is covered")
    T.eq(h.list:IsShown(), true, "the list casts")
    T.eq(stub.overrides.ESCAPE and stub.overrides.ESCAPE.click, "DaylightUIBookFightClose", "Escape closes it")
    T.eq(stub.ProtectedTree(ns.Window.frame), false, "our window never turns protected")
    T.noerror(function() BW.Key("P"); settle() end)
    T.eq(open(ns), false, "P again closes it")
    T.eq(h.list:IsShown(), false)
    T.eq(h.close:IsShown(), false)
    T.isnil(stub.overrides.ESCAPE, "Escape is the game's again")
    stub.LeaveCombat()
end)

T.test("book fight: a spell's cast button casts it; a passive gets none", function()
    local ns = load({ loaded = true, book = longBook() })
    stub.EnterCombat()
    BW.Key("P")
    settle()
    local list = casts(ns)
    T.eq(#list, 40, "every spell, not the passive")
    local b = list[1]
    T.eq(b:GetAttribute("type1"), "spell")
    T.eq(b:GetAttribute("spell"), b.row.cell.spellID)
    T.eq(b:GetObjectType(), "Button")
    T.truthy(b:IsProtected())
    stub.LeaveCombat()
end)

T.test("book fight: the wheel scrolls the cast buttons and the list together", function()
    local ns = load({ loaded = true, book = longBook() })
    stub.EnterCombat()
    BW.Key("P")
    settle()
    local h = layer(ns)
    local stack = ns.Window.frame.pages.spells.stack
    T.truthy((h.list:GetAttribute("max") or 0) > 0, "more than fits")
    local first = casts(ns)[1]
    T.eq(first:IsShown(), true, "the top spell shows")
    local wheel = h.list:GetScript("OnMouseWheel")
    T.noerror(function() for _ = 1, 3 do wheel(h.list, -1) end end)
    local at = h.list:GetAttribute("at")
    T.truthy(at > 0)
    T.near(stack:Scrolled(), at, 1e-6, "the rows went to the same spot")
    T.eq(first:IsShown(), false, "scrolled out of view: no button")
    -- A button keeps lying over its row: its top is the row's minus the scroll.
    local view = h.list:GetAttribute("view")
    for _, b in ipairs(casts(ns)) do
        local top = b:GetAttribute("y") - at
        if top >= 0 and top + b:GetAttribute("h") <= view then
            local _, _, _, x, y = b:GetPoint(1)
            T.near(-y, top, 1e-6)
            T.eq(x, b:GetAttribute("x"))
        end
    end
    for _ = 1, 50 do wheel(h.list, -1) end
    T.near(h.list:GetAttribute("at"), h.list:GetAttribute("max"), 1e-6, "stops at the end")
    T.eq(stack.bar.locked, true, "the pill doesn't drag it away")
    stub.LeaveCombat()
    T.isnil(stack.bar.locked)
end)

T.test("book fight: N opens talents, our tab back to the spellbook casts again", function()
    local ns = load({ loaded = true })
    stub.EnterCombat()
    BW.Key("N")
    settle()
    local f, h = ns.Window.frame, layer(ns)
    T.eq(f.current, "talents")
    T.eq(h.list:IsShown(), false, "nothing casts over talents")
    T.noerror(function() h.tabs[1]:Click() end)
    settle()
    T.eq(f.current, "spells")
    T.eq(h:GetAttribute("page"), "spells")
    T.eq(h.list:IsShown(), true)
    -- The X's cover moved with the page's width (720 to 600, keeping the top middle).
    local _, _, _, xs = h.close:GetPoint(1)
    T.near(xs, h.close:GetAttribute("x-spells"), 1e-6)
    T.truthy(h.close:GetAttribute("x-talents") > h.close:GetAttribute("x-spells"))
    stub.LeaveCombat()
end)

T.test("book fight: Escape and our X close it through the layer", function()
    local ns = load({ loaded = true })
    stub.EnterCombat()
    BW.Key("P")
    settle()
    T.noerror(function() BW.Escape(); settle() end)
    T.eq(open(ns), false)
    T.eq(layer(ns).list:IsShown(), false)
    BW.Key("P")
    settle()
    T.noerror(function() layer(ns).close:Click(); settle() end)
    T.eq(open(ns), false, "the X's cover runs our X")
    T.eq(layer(ns):GetAttribute("open"), false)
    stub.LeaveCombat()
end)

T.test("book fight: open as the fight starts, it's covered at once and the game's hiding changes nothing", function()
    local ns = load()
    BW.Open(BW.SPELLBOOK)
    settle()
    stub.EnterCombat()
    local h = layer(ns)
    T.eq(h:GetAttribute("open"), true)
    T.eq(h.list:IsShown(), true)
    BW.Toggle(BW.SPELLBOOK)   -- the game's own toggle (the micro menu) hides its frame
    settle()
    T.eq(PlayerSpellsFrame:IsShown(), false)
    T.eq(open(ns), true, "ours stays: only the layer closes it")
    BW.Key("P")
    settle()
    T.eq(open(ns), false)
    stub.LeaveCombat()
end)

T.test("book fight: closed by something else anyway, ours comes straight back", function()
    local ns = load({ loaded = true })
    stub.EnterCombat()
    BW.Key("P")
    settle()
    DaylightUI.Win.Shut(ns.Window.frame)
    settle()
    T.eq(open(ns), true, "never a layer over an empty spot")
    stub.LeaveCombat()
end)

T.test("book fight: search, folds and chips rest in the fight, the list refills after it", function()
    local ns = load({ loaded = true, book = longBook() })
    stub.EnterCombat()
    BW.Key("P")
    settle()
    local S, page = ns.Spells, ns.Window.frame.pages.spells
    local n = #S.Rows(page)
    S.Search("spell 1")
    S.Fold(S.data.sections[1], true)
    T.eq(#S.Rows(page), n, "the rows under the cast buttons stay")
    T.near(page.search:GetAlpha(), S.REST, 1e-6, "dimmed")
    page.search:SetText("spell 1")
    stub.LeaveCombat()
    settle()
    T.near(page.search:GetAlpha(), 1, 1e-6)
    T.truthy(#S.Rows(page) < n, "the search applies after the fight")
end)

T.test("book fight: the window holds still: no drag, grip, scale or making room", function()
    local ns = load({ loaded = true })
    stub.EnterCombat()
    BW.Key("P")
    settle()
    T.eq(DaylightUI.Win.Held(ns.Window.frame), true)
    stub.LeaveCombat()
    T.eq(DaylightUI.Win.Held(ns.Window.frame), false)
end)

T.test("book fight: after the fight, ours opened in it gets the game's book back under it", function()
    local ns = load({ loaded = true })
    stub.EnterCombat()
    BW.Key("N")
    settle()
    T.eq(PlayerSpellsFrame:IsShown(), false)
    stub.LeaveCombat()
    frame(2)
    T.isnil(stub.overrides.P, "P is the game's again")
    T.isnil(stub.overrides.N)
    T.eq(layer(ns).close:IsShown(), false)
    T.eq(PlayerSpellsFrame:IsShown(), true, "the game's book opened again, parked")
    T.eq(PlayerSpellsFrame:GetTab(), BW.TALENTS)
    T.eq(PlayerSpellsFrame:GetParent(), veil())
    BW.Escape()
    settle()
    T.eq(open(ns), false, "Escape closes both again")
end)

T.test("book fight: switched off, a fight hands the game's book back as before", function()
    local ns = load({ loaded = true }, { fightBook = false })
    stub.EnterCombat()
    T.eq(PlayerSpellsFrame:GetParent(), UIParent)
    T.isnil(stub.overrides.P)
    BW.Key("P")
    settle()
    T.eq(open(ns), false)
    T.eq(PlayerSpellsFrame:IsShown(), true)
    stub.LeaveCombat()
end)

T.test("book fight: after a fight P is the game's key again", function()
    local ns = load({ loaded = true })
    stub.EnterCombat()
    stub.LeaveCombat()
    BW.Key("P")
    settle()
    T.eq(open(ns), true, "P is the game's key again: ours on its frame")
    T.eq(PlayerSpellsFrame:IsShown(), true)
end)

T.test("book fight: a fight starting with the list already right reads nothing again", function()
    local ns = load({ loaded = true })
    stub.EnterCombat()
    stub.LeaveCombat()
    local reads = 0
    local read = ns.SpellData.Read
    ns.SpellData.Read = function(...) reads = reads + 1; return read(...) end
    stub.EnterCombat()
    T.eq(reads, 0)
    stub.LeaveCombat()
    DaylightUI:Set("Book", "hideLowRanks", false)
    stub.RunTimers()
    stub.EnterCombat()
    T.eq(reads, 1, "a setting changed while it was shut: read again")
    stub.LeaveCombat()
    ns.SpellData.Read = read
end)

T.test("book fight: a /reload in a fight builds the layer after it; that fight keeps the game's book", function()
    local ns
    stub.Load({ before = function()
        BW.world({ loaded = true })()
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { Book = { enabled = true } } } } }
        stub.combat = true
    end })
    ns = stub.book
    T.isnil(ns.Fight.h, "nothing secure made in the fight")
    stub.LeaveCombat()
    T.truthy(ns.Fight.h, "made once it's over")
    stub.EnterCombat()
    BW.Key("P")
    settle()
    T.eq(open(ns), true, "the next fight has ours")
    stub.LeaveCombat()
end)
