local stub = require("stub")
local BW = require("bookworld")

-- The spellbook and talents window (Book/): the game's PlayerSpellsFrame parked
-- under the kit's veil with Daylight UI's window in its place, and the game's own
-- book in a fight.

-- Switched on (the default, written out so the tests don't lean on it).
-- spec.fightBook = false gives the game's book in a fight (test_book_fight.lua
-- covers the addon's).
local function load(spec)
    spec = spec or {}
    stub.Load({ before = function()
        BW.world(spec)()
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { Book = { enabled = true, fightBook = spec.fightBook } } } } }
    end })
    return stub.book.Window
end

-- One frame of the world: timers, the follower's look, the moves.
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

local function open(B) return DaylightUI.Win.IsOpen(B.frame) end
local function veil() return DaylightUI.Win.Followers.veil end
local function blockedHides()
    local n = 0
    for _, c in ipairs(BW.Calls("HideUIPanel")) do if c[2] == false and stub.combat then n = n + 1 end end
    return n
end

T.test("book: switched on, the game's book is parked under the veil as it loads", function()
    local B = load()
    T.eq(DaylightUI.bookOwnWindow, true)
    T.truthy(B.frame)
    T.isnil(_G.PlayerSpellsFrame, "load-on-demand: not loaded by us")
    BW.LoadBook()
    T.eq(PlayerSpellsFrame:GetParent(), veil())
end)

T.test("book: Ctrl + the wheel sizes the window, times the master Scale", function()
    load()
    local f = _G.DaylightUIBook
    T.truthy(f, "the window is built")
    local wheel = f:GetScript("OnMouseWheel")
    wheel(f, 1)
    T.near(DaylightUI:Get("Book", "scale") or 1, 1, 1e-6, "no Ctrl: nothing")
    _G.IsControlKeyDown = function() return true end
    wheel(f, 1)
    wheel(f, 1)
    T.near(DaylightUI:Get("Book", "scale"), 1.1)
    T.near(f:GetScale(), 1.1)
    for _ = 1, 20 do wheel(f, 1) end
    T.near(DaylightUI:Get("Book", "scale"), 1.3, 1e-6, "kept within the slider's range")
    DaylightUI:Set("general", "scale", 0.5)
    stub.RunTimers()
    T.near(f:GetScale(), 0.65, 1e-6, "the master Scale multiplies it")
    stub.EnterCombat()
    wheel(f, -1)
    T.near(DaylightUI:Get("Book", "scale"), 1.3, 1e-6, "not in a fight")
    stub.LeaveCombat()
    _G.IsControlKeyDown = nil
end)

T.test("book: P opens ours on the spellbook, N on talents", function()
    local B = load()
    BW.Open(BW.SPELLBOOK)
    frame()
    T.eq(open(B), true)
    T.eq(B.frame.current, "spells")
    T.eq(B.frame.tab, "spells")
    T.eq(PlayerSpellsFrame:GetParent(), veil(), "the game's out of sight")
    BW.Toggle(BW.SPELLBOOK)
    settle()
    T.eq(open(B), false, "P again closes both")
    BW.Open(BW.TALENTS)
    frame()
    T.eq(B.frame.current, "talents")
    T.eq(B.frame.title:GetText(), TALENTS or "Talents")
end)

T.test("book: the game's tab switching while open switches our page; our tab leaves the game's", function()
    local B = load()
    BW.Open(BW.SPELLBOOK)
    frame()
    BW.Toggle(BW.TALENTS)   -- N while the book is open, so the game switches its tab
    frame()
    T.eq(open(B), true)
    T.eq(B.frame.current, "talents")
    B.frame.tabs[1]:Click()   -- the addon's Spellbook tab
    T.eq(B.frame.current, "spells")
    T.eq(PlayerSpellsFrame:GetTab(), BW.TALENTS, "the game's tab stays")
end)

T.test("book: the page glides to its size", function()
    local B = load()
    BW.Open(BW.SPELLBOOK)
    settle()
    T.near(B.frame:GetWidth(), 600, 0.5)
    B.frame.tabs[2]:Click()
    settle()
    T.near(B.frame:GetWidth(), 720, 0.5)
    T.near(B.frame:GetHeight(), 563, 0.5)
end)

T.test("book: our X closes the game's book too", function()
    local B = load()
    BW.Open(BW.SPELLBOOK)
    settle()
    B.frame.close:Click()
    settle()
    T.eq(open(B), false)
    T.eq(PlayerSpellsFrame:IsShown(), false)
    T.eq(#BW.Calls("HideUIPanel"), 1)
end)

T.test("book: Escape and a loading screen close ours with the game's", function()
    local B = load()
    BW.Open(BW.SPELLBOOK)
    settle()
    BW.Escape()
    settle()
    T.eq(open(B), false)
    BW.Open(BW.TALENTS)
    settle()
    T.eq(open(B), true)
    BW.LeaveWorld()
    settle()
    T.eq(open(B), false)
    T.eq(PlayerSpellsFrame:IsShown(), false)
end)

T.test("book: switched off for fights, as a fight starts the game's book is handed back, and parked again after it closes", function()
    local B = load({ loaded = true, fightBook = false })
    T.eq(PlayerSpellsFrame:GetParent(), veil())
    stub.EnterCombat()
    T.eq(PlayerSpellsFrame:GetParent(), UIParent, "handed back before the lockdown")
    BW.Open(BW.SPELLBOOK)   -- P in the fight
    settle()
    T.eq(open(B), false, "the game's own book, not ours")
    T.eq(PlayerSpellsFrame:GetParent(), UIParent)
    T.eq(PlayerSpellsFrame:IsShown(), true)
    stub.LeaveCombat()
    frame()
    T.eq(PlayerSpellsFrame:GetParent(), UIParent, "still open: stays the game's")
    BW.Escape()
    frame(2)
    T.eq(PlayerSpellsFrame:GetParent(), veil(), "closed: parked again")
    BW.Open(BW.SPELLBOOK)
    frame()
    T.eq(open(B), true, "ours again out of combat")
end)

T.test("book: switched off for fights, the panel width is ours while parked and the game's in the fight", function()
    load({ loaded = true, fightBook = false })
    local w = BW.state.panel[PlayerSpellsFrame]
    T.eq(w and w.width, 620)
    stub.EnterCombat()
    T.isnil(BW.state.panel[PlayerSpellsFrame].width, "the game's own (none: the frame's width)")
end)

T.test("book: switched off for fights, ours open as the fight starts stays ours; its X waits for the fight's end to close the game's", function()
    local B = load({ fightBook = false })
    BW.Open(BW.SPELLBOOK)
    settle()
    stub.EnterCombat()
    T.eq(PlayerSpellsFrame:GetParent(), veil(), "a shown book isn't handed back")
    T.eq(open(B), true)
    T.noerror(function() B.frame.close:Click() end)
    settle()
    T.eq(open(B), false, "ours closes now")
    T.eq(PlayerSpellsFrame:IsShown(), true, "the game's can't be closed by us in combat")
    T.eq(blockedHides(), 0)
    stub.LeaveCombat()
    settle()
    T.eq(PlayerSpellsFrame:IsShown(), false, "closed after the fight")
end)

T.test("book: switched off for fights, N in a fight after our X brings ours back on talents, no error", function()
    local B = load({ fightBook = false })
    BW.Open(BW.SPELLBOOK)
    settle()
    stub.EnterCombat()
    B.frame.close:Click()
    settle()
    T.noerror(function() BW.Toggle(BW.TALENTS); frame() end)
    T.eq(open(B), true)
    T.eq(B.frame.current, "talents")
    stub.LeaveCombat()
    settle()
    T.eq(PlayerSpellsFrame:IsShown(), true, "reopened: the queued close is dropped")
end)

T.test("book: the book's first load in a fight stays the game's", function()
    local B = load()
    stub.EnterCombat()
    BW.Open(BW.SPELLBOOK)
    frame()
    T.eq(PlayerSpellsFrame:GetParent(), UIParent)
    T.eq(open(B), false)
    BW.Escape()
    stub.LeaveCombat()
    frame(2)
    T.eq(PlayerSpellsFrame:GetParent(), veil())
end)

T.test("book: inspecting someone is lent to the game: ours never shows their talents", function()
    local B = load()
    BW.Inspect("target")
    frame(2)
    T.eq(open(B), false)
    T.eq(PlayerSpellsFrame:GetParent(), UIParent)
    T.eq(PlayerSpellsFrame:IsShown(), true)
    BW.Escape()
    frame(2)
    T.eq(PlayerSpellsFrame:GetParent(), veil(), "parked again once closed")
    BW.Open(BW.SPELLBOOK)
    frame()
    T.eq(open(B), true)
end)

T.test("book: an inspect while ours is open hands the window to the game", function()
    local B = load()
    BW.Open(BW.TALENTS)
    settle()
    BW.Inspect("target")
    frame(2)
    T.eq(open(B), false)
    T.eq(PlayerSpellsFrame:GetParent(), UIParent)
end)

T.test("book: the header shows the class and level", function()
    local B = load()
    stub.SetUnits({ player = { name = "Thrall", class = "WARRIOR", level = 23, isPlayer = true } })
    BW.Open(BW.SPELLBOOK)
    frame()
    local class = UnitClass("player")
    T.eq(B.frame.sub:GetText(), string.format("%s · Level %d", class, UnitLevel("player")))
    T.eq(B.frame.title:GetText(), SPELLBOOK or "Spellbook")
    T.eq(B.frame.portrait:IsShown(), true, "the class icon")
end)

T.test("book: without the unit frames, the class icon is our own", function()
    local B = load()
    stub.installedAddOns.JiberishIcons = true
    stub.SetUnits({ player = { name = "Thrall", class = "WARRIOR", level = 23, isPlayer = true } })
    BW.Open(BW.SPELLBOOK)
    frame()
    T.eq(B.frame.portrait.__texture, DaylightUI.MEDIA .. "class\\warrior.tga")
    T.eq(B.frame.portrait.__texCoord[2], 1, "the whole picture")
    stub.installedAddOns.JiberishIcons = nil
end)

T.test("book: the class icon follows the icon style and the class's pick", function()
    stub.Load({ module = true, before = function()
        BW.world()()
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { Book = { enabled = true } } } } }
    end })
    local B = stub.book.Window
    stub.installedAddOns.JiberishIcons = true
    stub.SetUnits({ player = { name = "Thrall", class = "WARRIOR", level = 23, isPlayer = true } })
    DaylightUI:Set("UnitFrames", "portraits.icons", "fabledpixelsv2")
    BW.Open(BW.SPELLBOOK)
    frame()
    local pack = "Interface\\AddOns\\JiberishIcons\\Media\\"
    T.eq(B.frame.portrait.__texture, pack .. "Class\\fabledpixelsv2.tga", "the icon style")
    T.eq(B.frame.portrait.__texCoord[2], 0.125, "the warrior's square on the sheet")
    BW.Escape()
    frame()
    DaylightUI:Set("UnitFrames", "portraits.classIcons.WARRIOR", "spec:72")
    BW.Open(BW.SPELLBOOK)
    frame()
    T.eq(B.frame.portrait.__texture, pack .. "Spec\\fabledspecializations.tga", "the class's pick")
    stub.installedAddOns.JiberishIcons = nil
end)

-- The client moves the frame while dragged (StartMoving). The fake game only
-- places it where the test says (GetLeft/GetTop of its own).
local function at(f, left, top)
    f.GetLeft = function() return left end
    f.GetTop = function() return top end
end

T.test("book: dragged by the header, it opens there again; a right-click on the header puts it back", function()
    local B = load()
    BW.Open(BW.SPELLBOOK)
    settle()
    local f = B.frame
    local w = f:GetWidth()
    at(f, 300, 700)
    stub.cursorPos = { 500, 700 - 100 }   -- on the page, under the header
    f:GetScript("OnDragStart")(f)
    T.falsy(f.dragging, "a drag on the page isn't the window's")
    stub.cursorPos = { 500, 700 - 20 }
    f:GetScript("OnDragStart")(f)
    T.eq(f.dragging, true)
    at(f, 100, 500)
    f:GetScript("OnDragStop")(f)
    local spot = B.frame and stub.book.module.db.spot
    T.near(spot[1], 100 + w / 2, 1)
    T.near(spot[2], 500, 1)
    BW.Toggle(BW.SPELLBOOK)
    settle()
    BW.Open(BW.TALENTS)
    settle()
    local p, rel, rp, x, y = f:GetPoint(1)
    T.eq(p, "TOP"); T.eq(rel, UIParent); T.eq(rp, "BOTTOMLEFT")
    T.near(x, spot[1], 1); T.near(y, spot[2], 1)
    at(f, 100, 500)
    stub.cursorPos = { 300, 490 }
    f:GetScript("OnMouseUp")(f, "RightButton")
    T.isnil(stub.book.module.db.spot)
end)

T.test("book: on by default, also for a profile that never touched it", function()
    stub.Load({ before = function()
        BW.world()()
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { Book = { scale = 1.1 } } } } }
    end })
    T.eq(DaylightUI.bookOwnWindow, true)
end)

T.test("book: switched off: the game's book stays the game's", function()
    stub.Load({ before = function()
        BW.world()()
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { Book = { enabled = false } } } } }
    end })
    T.eq(DaylightUI.bookOwnWindow, false)
    T.isnil(stub.book.Window.frame)
    BW.LoadBook()
    T.eq(PlayerSpellsFrame:GetParent(), UIParent)
end)

T.test("book: a page dragged wider by the grip opens at that size again", function()
    local B = load()
    BW.Open(BW.TALENTS)
    settle()
    local f = B.frame
    T.eq(f.current, "talents")
    -- The fake game has no layout, so a fixed top-left for the drag's sums.
    f.GetLeft = function() return 100 end
    f.GetTop = function() return 700 end
    local e = f:GetEffectiveScale()
    stub.cursorPos = { 820 * e, 137 * e }
    f.grip:GetScript("OnMouseDown")(f.grip, "LeftButton")
    stub.cursorPos = { 1200 * e, 137 * e }
    stub.RunOnUpdate(f.grip, 1 / 30)
    f.grip:GetScript("OnMouseUp")(f.grip, "LeftButton")
    T.eq(f:GetWidth(), 1100)
    BW.Toggle(BW.TALENTS)
    settle()
    T.eq(open(B), false)
    BW.Open(BW.TALENTS)
    settle()
    T.near(f:GetWidth(), 1100, 0.5, "talents open at the dragged size")
    f.tabs[1]:Click()
    settle()
    T.near(f:GetWidth(), 600, 0.5, "the spellbook keeps its own")
end)

T.test("book: talents open as a side panel like the spellbook (the game's \"center\" closes every other window)", function()
    load()
    BW.Open(BW.TALENTS)
    frame()
    T.eq(BW.state.panel[PlayerSpellsFrame].area, "centerOrLeft", "talents move aside, nothing closes")
    BW.Open(BW.SPELLBOOK)
    frame()
    T.eq(BW.state.panel[PlayerSpellsFrame].area, "centerOrLeft")
    BW.Escape()
    settle()
    BW.Inspect("target")
    frame()
    T.eq(BW.state.panel[PlayerSpellsFrame].area, "center", "an inspect is the game's own window")
end)
