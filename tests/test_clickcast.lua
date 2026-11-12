local stub = require("stub")

-- Spells the fake game knows: a name per id, the top rank by name.
local SPELLS = {
    [2061] = { name = "Flash Heal", top = 2061 },
    [9472] = { name = "Flash Heal", top = 2061 },   -- a lower rank
    [139] = { name = "Renew", top = 139 },
    [774] = { name = "Rejuvenation", top = 774 },
}
local function spellWorld()
    _G.C_Spell.GetSpellName = function(id) return SPELLS[id] and SPELLS[id].name end
    _G.C_Spell.GetSpellInfo = function(q)
        for id, s in pairs(SPELLS) do
            if q == s.name or q == id then return { spellID = s.top, name = s.name } end
        end
    end
    _G.C_Spell.GetSpellTexture = function() return 135907 end
    _G.IsPlayerSpell = function(id) return SPELLS[id] ~= nil end
end

local function login(opts)
    opts = opts or {}
    local DUI, ns = stub.Load({ module = true, before = function()
        spellWorld()
        -- The game's own spellbook (with Daylight UI's book window off) is the binder's home.
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { Book = { enabled = false } } } } }
        if opts.before then opts.before() end
    end })
    spellWorld()
    return DUI, ns, ns.ClickCast
end

-- What a click does on a frame, as the game's SecureUnitButton reads it
-- (SecureButton_GetModifiedAttribute: modifier prefix plus button suffix).
local SUFFIX = { LeftButton = "1", RightButton = "2", MiddleButton = "3", Button4 = "4", Button5 = "5" }
local function clickOn(f, button, mods)
    local prefix = (mods and mods ~= "") and (mods .. "-") or ""
    local t = f:GetAttribute(prefix, "type", SUFFIX[button])
    if t == "spell" then return "spell", f:GetAttribute(prefix, "spell", SUFFIX[button]) end
    return t
end

-- A button a group header makes, as the game makes it: its own setup snippet (not
-- run here), then the header's initial attributes copied onto it
-- (SetupUnitButtonConfiguration in SecureGroupHeaders.lua), then the addon's Lua
-- dressing through the snippet's CallMethod.
local function headerButton(header, name, unit)
    local b = CreateFrame("Button", name, header, "SecureUnitButtonTemplate")
    stub.inSecure = (stub.inSecure or 0) + 1
    b:SetAttribute("*type1", "target")
    b:SetAttribute("*type2", "togglemenu")
    b:SetAttribute("unit", unit)
    local names = header:GetAttribute("_initialAttributeNames")
    if type(names) == "string" then
        for n in names:gmatch("[^,]+") do b:SetAttribute(n, header:GetAttribute("_initialAttribute-" .. n)) end
    end
    stub.inSecure = stub.inSecure - 1
    header.initialConfigFunction(header, b:GetName())
    return b
end

T.test("nothing is bound out of the box: left-click targets, right-click opens the menu", function()
    local DUI, ns, CC = login()
    local f = ns.frames.player
    T.eq(clickOn(f, "LeftButton"), "target")
    T.eq(clickOn(f, "RightButton"), "togglemenu")
    T.eq(clickOn(f, "RightButton", "shift"), "togglemenu", "a modified click falls back to the button's own")
    T.eq(#CC.List(), 0)
    T.isnil(DUI.DB.Character().clickCast, "nothing written to the saved file")
    T.isnil(ns.Raid.header:GetAttribute("_initialAttributeNames"))
end)

T.test("a binding casts on every frame of ours, and only on its click", function()
    local DUI, ns, CC = login()
    local raid = headerButton(ns.Raid.header, "DaylightUIRaidHeaderUnitButton1", "raid1")
    T.truthy(CC.Bind("shift", "RightButton", 2061, "Flash Heal"))
    stub.RunTimers()
    for _, f in ipairs({ ns.frames.player, ns.frames.target, ns.frames.focus, ns.frames.pet, ns.frames.targettarget, raid }) do
        local t, spell = clickOn(f, "RightButton", "shift")
        T.eq(t, "spell", f:GetName())
        T.eq(spell, "Flash Heal", "the top rank is cast by name")
        T.eq(clickOn(f, "RightButton"), "togglemenu", "plain right-click still opens the menu")
        T.eq(clickOn(f, "LeftButton", "shift"), "target")
    end
    T.eq(CC.Describe("shift", "RightButton"), "Shift + Right click")
    T.eq(#DUI.DB.Character().clickCast[1], 1, "kept for this character's talent set")
end)

-- What a forwarded mouse button runs on a frame: its macro line, if any (the
-- game's ATTRIBUTE_NOOP "" reads as nothing).
local function macroOn(f, button, mods)
    local prefix = (mods and mods ~= "") and (mods .. "-") or ""
    local t = f:GetAttribute(prefix, "type", SUFFIX[button])
    if t ~= "macro" then return nil end
    return f:GetAttribute(prefix, "macrotext", SUFFIX[button])
end

T.test("a mouse button bound to an action bar key presses it over a frame (mouseover casting with mouse buttons)", function()
    local _, ns, CC = login({ before = function()
        stub.bindings.ACTIONBUTTON3 = { "BUTTON4" }
        stub.bindings.MULTIACTIONBAR1BUTTON12 = { "SHIFT-BUTTON5" }
        stub.bindings["CLICK DaylightUIBar1Button2:LeftButton"] = { "BUTTON3" }
        stub.bindings.MOVEFORWARD = { "ALT-BUTTON4" }
    end })
    local raid = headerButton(ns.Raid.header, "DaylightUIRaidHeaderUnitButton1", "raid1")
    for _, f in ipairs({ ns.frames.player, ns.frames.target, raid }) do
        T.eq(macroOn(f, "Button4"), "/click ActionButton3", f:GetName())
        T.eq(macroOn(f, "Button4", "shift"), "/click ActionButton3", "a held key with no binding of its own: the plain one, as in the world")
        T.isnil(macroOn(f, "Button4", "alt"), "alt has its own binding (not a button): nothing")
        T.eq(macroOn(f, "Button5", "shift"), "/click MultiBarBottomLeftButton12")
        T.isnil(macroOn(f, "Button5"), "plain Button 5 has no binding")
        T.eq(macroOn(f, "MiddleButton"), "/click DaylightUIBar1Button2 LeftButton")
        T.eq(clickOn(f, "LeftButton"), "target", "left and right click stay")
        T.eq(clickOn(f, "RightButton"), "togglemenu")
    end

    -- A click-cast binding on the same click wins; the others stay.
    T.truthy(CC.Bind("", "Button4", 2061, "Flash Heal"))
    stub.RunTimers()
    T.eq(clickOn(ns.frames.player, "Button4"), "spell")
    T.eq(macroOn(ns.frames.player, "Button4", "shift"), "/click ActionButton3")

    -- When key bindings change, the frames follow after the fight.
    stub.EnterCombat()
    stub.bindings.ACTIONBUTTON3 = nil
    stub.bindings.ACTIONBUTTON7 = { "BUTTON4" }
    stub.FireEvent("UPDATE_BINDINGS")
    T.eq(macroOn(ns.frames.player, "Button4", "shift"), "/click ActionButton3", "not in a fight")
    stub.LeaveCombat()
    T.eq(macroOn(ns.frames.player, "Button4", "shift"), "/click ActionButton7")
end)

T.test("with Clique loaded no mouse button is forwarded", function()
    local _, ns = login({ before = function()
        stub.bindings.ACTIONBUTTON3 = { "BUTTON4" }
        stub.loadedAddOns.Clique = true
        _G.ClickCastFrames = {}
    end })
    T.isnil(macroOn(ns.frames.player, "Button4"))
end)

T.test("a lower rank picked in the spellbook is cast by name and rank, never by id (aimed at the clicked unit)", function()
    local _, ns, CC = login()
    CC.Bind("", "MiddleButton", 9472, "Flash Heal", "Rank 2")
    stub.RunTimers()
    local t, spell = clickOn(ns.frames.player, "MiddleButton")
    T.eq(t, "spell"); T.eq(spell, "Flash Heal(Rank 2)")
    T.eq(CC.Describe("", "MiddleButton"), "Middle click")
end)

T.test("the same click again moves it; removing puts the click back", function()
    local _, ns, CC = login()
    local f = ns.frames.player
    CC.Bind("ctrl", "LeftButton", 139, "Renew")
    CC.Bind("ctrl", "LeftButton", 774, "Rejuvenation")
    stub.RunTimers()
    T.eq(#CC.List(), 1, "one binding per click")
    T.eq(select(2, clickOn(f, "LeftButton", "ctrl")), "Rejuvenation")
    T.eq(CC.Toggle("ctrl", "LeftButton", 774, "Rejuvenation"), "removed", "the binder's same click on the same spell")
    stub.RunTimers()
    T.eq(clickOn(f, "LeftButton", "ctrl"), "target")
    T.isnil(f:GetAttribute("ctrl-spell1"))
end)

T.test("changing a binding's click (the options page) moves it, replacing what was there", function()
    local _, ns, CC = login()
    local f = ns.frames.player
    CC.Bind("shift", "LeftButton", 139, "Renew")
    CC.Bind("alt", "LeftButton", 774, "Rejuvenation")
    T.truthy(CC.Rebind(1, "alt", "LeftButton"))
    stub.RunTimers()
    T.eq(#CC.List(), 1)
    T.eq(select(2, clickOn(f, "LeftButton", "alt")), "Renew")
    T.eq(clickOn(f, "LeftButton", "shift"), "target")
    T.falsy(CC.Rebind(1, "shift-alt", "LeftButton"), "modifiers only in the game's order")
end)

T.test("bindings wait for combat to end; a raid member who joins mid-fight gets them from the header", function()
    local _, ns, CC = login()
    stub.secure = true
    CC.Bind("shift", "LeftButton", 139, "Renew")
    stub.RunTimers()
    T.eq(ns.Raid.header:GetAttribute("_initialAttributeNames"), "shift-type1,shift-spell1")
    T.eq(ns.Raid.header:GetAttribute("_initialAttribute-shift-spell1"), "Renew")
    T.isnil(ns.Raid.header:GetAttribute("_ignore"), "the header's own updates aren't left switched off")
    stub.EnterCombat()
    T.noerror(function() CC.Bind("alt", "RightButton", 774, "Rejuvenation") end, "binding in combat writes nothing protected")
    T.eq(clickOn(ns.frames.player, "RightButton", "alt"), "togglemenu", "not yet")
    local b = headerButton(ns.Raid.header, "DaylightUIRaidHeaderUnitButton4", "raid4")
    T.eq(select(2, clickOn(b, "LeftButton", "shift")), "Renew", "the header copied the bindings in secure code")
    stub.LeaveCombat()
    stub.RunTimers()
    T.eq(select(2, clickOn(ns.frames.player, "RightButton", "alt")), "Rejuvenation")
    T.eq(select(2, clickOn(b, "RightButton", "alt")), "Rejuvenation")
    T.eq(ns.Raid.header:GetAttribute("_initialAttribute-alt-spell2"), "Rejuvenation")
    stub.secure = false
end)

T.test("a party button made out of combat is dressed with the bindings", function()
    local _, ns, CC = login()
    CC.Bind("", "Button4", 139, "Renew")
    stub.RunTimers()
    local b = CreateFrame("Button", "DaylightUIPartyHeaderUnitButton2", ns.Party.header, "SecureUnitButtonTemplate")
    b:SetAttribute("unit", "party2")
    ns.Party.header.initialConfigFunction(ns.Party.header, b:GetName())
    T.eq(select(2, clickOn(b, "Button4")), "Renew")
end)

T.test("each talent set has its own bindings", function()
    local sets = 2
    local _, ns, CC = login({ before = function()
        _G.GetNumSpecGroups = function() return sets end
        _G.C_SpecializationInfo = { GetActiveSpecGroup = function() return stub.activeSpec end }
        stub.activeSpec = 1
    end })
    CC.Bind("shift", "LeftButton", 139, "Renew")
    stub.RunTimers()
    stub.activeSpec = 2
    stub.FireEvent("ACTIVE_TALENT_GROUP_CHANGED", 2, 1)
    stub.RunTimers()
    T.eq(#CC.List(), 0)
    T.eq(clickOn(ns.frames.player, "LeftButton", "shift"), "target", "set 2 has nothing bound")
    CC.Bind("shift", "LeftButton", 774, "Rejuvenation")
    stub.activeSpec = 1
    stub.FireEvent("ACTIVE_TALENT_GROUP_CHANGED", 1, 2)
    stub.RunTimers()
    T.eq(select(2, clickOn(ns.frames.player, "LeftButton", "shift")), "Renew")
end)

T.test("with Clique loaded, ours steps aside and Clique still finds our frames", function()
    local _, ns, CC = login({ before = function()
        stub.loadedAddOns.Clique = true
        _G.ClickCastFrames = {}
    end })
    T.truthy(CC.Stepped())
    CC.Bind("shift", "LeftButton", 139, "Renew")
    stub.RunTimers()
    T.eq(clickOn(ns.frames.player, "LeftButton", "shift"), "target", "nothing of ours written")
    T.isnil(ns.Raid.header:GetAttribute("_initialAttributeNames"))
    T.truthy(ClickCastFrames[ns.frames.player], "our frames are in Clique's list")
    ns.ClickBinder.SetMode(true)
    T.falsy(ns.ClickBinder.on, "no binding mode")
    _G.ClickCastFrames = nil
end)

-- ---------------------------------------------------------------------
-- The spellbook binder
-- ---------------------------------------------------------------------

-- The game's spellbook as the binder reads it: PlayerSpellsFrame.SpellBookFrame
-- with its paged list of entries (each a frame with .Button and the
-- spellBookItemInfo the game keeps on it), plus EventRegistry's show and hide.
local function spellbook(entries)
    local callbacks = {}
    _G.EventRegistry = { RegisterCallback = function(_, event, fn, owner) callbacks[event] = { fn, owner } end }
    _G.Enum = _G.Enum or {}
    Enum.SpellBookSpellBank = { Player = 0, Pet = 1 }
    Enum.SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 }
    local psf = CreateFrame("Frame", "PlayerSpellsFrame", UIParent)
    local book = CreateFrame("Frame", nil, psf)
    psf.SpellBookFrame = book
    book.SearchBox = CreateFrame("EditBox", nil, book)
    local paged = CreateFrame("Frame", nil, book)
    book.PagedSpellsFrame = paged
    local items = {}
    for i, e in ipairs(entries) do
        local item = CreateFrame("Frame", nil, paged)
        item.Button = CreateFrame("Button", nil, item)
        item.spellBank = e.bank or 0
        item.spellBookItemInfo = { spellID = e.spell, actionID = e.spell, itemType = e.itemType or 1, name = e.name,
                                   subName = e.rank or "", isPassive = e.passive == true, isOffSpec = false }
        items[i] = item
    end
    function paged:EnumerateFrames() return ipairs(items) end
    book:Hide()
    local world = { book = book, items = items }
    function world.Show()
        book:Show()
        local cb = callbacks["PlayerSpellsFrame.SpellBookFrame.Show"]
        if cb then cb[1](cb[2]) end
    end
    local function fire(event)
        local cb = callbacks[event]
        if cb then cb[1](cb[2]) end
    end
    -- The book's page hides (a switch to the talents tab).
    function world.Tab()
        book:Hide()
        fire("PlayerSpellsFrame.SpellBookFrame.Hide")
    end
    -- The whole window closes.
    function world.Hide()
        world.Tab()
        fire("PlayerSpellsFrame.CloseFrame")
    end
    function world.Hover(i)
        for j, item in ipairs(items) do
            item.Button.IsMouseOver = function() return j == i end
        end
    end
    return world
end

T.test("the binder: with our own book window the game's book gets no switch (it's veiled; ours is drawn there)", function()
    local DUI, ns = login()
    local B = ns.ClickBinder
    local book = spellbook({ { spell = 139, name = "Renew" } })
    stub.FireEvent("ADDON_LOADED", "Blizzard_PlayerSpells")
    DUI.bookOwnWindow = true
    book.Show()
    DUI.bookOwnWindow = nil
    T.falsy(B.toggle and B.toggle:IsShown(), "no pill floating over our window's header")
    T.falsy(B.Driver():IsShown(), "no scan over a book nobody sees")
end)

T.test("the binder: a Click-cast switch on the spellbook; hover a spell and click to bind it", function()
    local DUI, ns, CC = login()
    local B = ns.ClickBinder
    local book = spellbook({ { spell = 139, name = "Renew" }, { spell = 2061, name = "Flash Heal" },
                             { spell = 15473, name = "Shadowform", passive = true } })
    stub.FireEvent("ADDON_LOADED", "Blizzard_PlayerSpells")
    T.truthy(B.toggle, "made once the spellbook exists")
    T.falsy(B.toggle:IsShown(), "only with the spellbook open")
    book.Show()
    T.truthy(B.toggle:IsShown())
    T.falsy(B.on, "off until switched on")
    B.toggle:Click()
    T.truthy(B.on)
    book.Hover(2)
    stub.RunOnUpdate(B.Driver(), 1)
    T.truthy(B.catcher:IsShown(), "the catcher lies over the hovered spell")
    T.eq(B.catcher.entry.spell, 2061)
    B.catcher.IsMouseOver = function() return true end
    _G.IsShiftKeyDown = function() return true end
    B.catcher:Click("RightButton")
    _G.IsShiftKeyDown = nil
    stub.RunTimers()
    T.eq(select(2, clickOn(ns.frames.player, "RightButton", "shift")), "Flash Heal")
    -- A passive isn't offered.
    B.catcher.IsMouseOver = nil
    B.catcher:Hide()
    book.Hover(3)
    stub.RunOnUpdate(B.Driver(), 1)
    T.falsy(B.catcher:IsShown(), "nothing to bind on a passive")
    -- The talents tab: the scan stops, the switch hides, and binding waits.
    book.Tab()
    T.falsy(B.toggle:IsShown())
    T.falsy(B.Driver():IsShown(), "no per-frame work while the book's page is away")
    T.truthy(B.on, "still on for when the page is back")
    book.Show()
    T.truthy(B.toggle:IsShown())
    -- Closing the book ends binding. The options window stays shut since it
    -- wasn't opened from there.
    book.Hide()
    T.falsy(B.on, "closing the spellbook switches binding off")
    stub.RunTimers()
    T.falsy(DUI.OptionsPanel.IsShown(), "nothing reopens")
end)

T.test("Bind in spellbook: the game's own spellbook button opens it; closing it brings the page back", function()
    local DUI, ns = login()
    local B = ns.ClickBinder
    local book = spellbook({ { spell = 139, name = "Renew" } })
    stub.FireEvent("ADDON_LOADED", "Blizzard_PlayerSpells")
    _G.SpellbookMicroButton = CreateFrame("Button", "SpellbookMicroButton", UIParent)
    local item = ns.ClickCastPage.groups[2].items[2]
    T.eq(item.text(), "Bind in spellbook")
    DUI.OptionsPanel.Show(B.PAGE)
    local row = CreateFrame("Frame", nil, UIParent)
    local b = CreateFrame("Button", nil, row)
    b.GetLeft = function() return 100 end
    b.GetBottom = function() return 200 end
    b.GetWidth = function() return 120 end
    b.GetHeight = function() return 24 end
    item.built(b, row)
    -- Hovering the button lays the secure opener over it.
    b:GetScript("OnEnter")(b)
    local o = B.opener
    T.truthy(o and o:IsShown(), "a secure button over ours")
    T.eq(o:GetAttribute("type"), "macro")
    T.eq(o:GetAttribute("macrotext"), "/click SpellbookMicroButton", "the game's code opens the book")
    T.eq(select(2, o:GetPoint(1)), UIParent, "placed on the screen, not anchored to our frames")
    -- The click: the macro opens the book (on the way down), then binding is on.
    book.Show()
    o:GetScript("PostClick")(o, "LeftButton", true)
    T.falsy(B.on, "nothing on the way down")
    o:GetScript("PostClick")(o, "LeftButton", false)
    T.truthy(B.on, "binding is on")
    T.falsy(o:IsShown())
    T.falsy(DUI.OptionsPanel.IsShown(), "the options window steps aside")
    T.eq(item.text(), "Stop binding")
    T.isnil(B.Opener(b, row), "while binding, the button just stops it")
    -- Done: closing the book ends binding and the page comes back.
    book.Hide()
    T.falsy(B.on)
    stub.RunTimers()
    T.truthy(DUI.OptionsPanel.IsShown(), "the options window is back")
    T.eq(DUI.OptionsPanel.Current(), B.PAGE)
    -- The same click with the book already open closes it, and nothing switches on.
    book.Hide()
    o:GetScript("PostClick")(o, "LeftButton", false)
    T.falsy(B.on)
    -- In combat (a secure frame can't show) the button's own click is left alone.
    stub.EnterCombat()
    T.isnil(B.Opener(b, row))
    stub.LeaveCombat()
    -- Without the game's button, the same.
    _G.SpellbookMicroButton = nil
    T.isnil(B.Opener(b, row))
end)

T.test("the options page lists the bindings and removes them", function()
    local DUI, ns, CC = login()
    CC.Bind("shift", "RightButton", 2061, "Flash Heal")
    CC.Bind("", "MiddleButton", 139, "Renew")
    local page = ns.ClickCastPage
    T.eq(page.id, "clickcast")
    local list = page.groups[3].items[1]
    local row = CreateFrame("Frame", nil, UIParent)
    list.build(row)
    list.update(row)
    T.eq(row.count, 2)
    T.eq(row.lines[1].name.__text, "Flash Heal")
    T.eq(row.lines[1].click.text.__text, "Shift + Right click")
    -- To change the click, click the pill, then click it again with the new one.
    local pill = row.lines[2].click
    pill:Click("LeftButton")
    T.eq(pill.text.__text, "Click here with the new click")
    _G.IsAltKeyDown = function() return true end
    pill:Click("Button5")
    _G.IsAltKeyDown = nil
    list.update(row)
    T.eq(row.lines[2].click.text.__text, "Alt + Button 5")
    row.lines[1].delete:Click()
    list.update(row)
    T.eq(row.count, 1)
    T.eq(row.lines[1].name.__text, "Renew")
    local clear = page.groups[2].items[3]
    T.falsy(clear.disabled())
    clear.func()
    T.truthy(clear.disabled(), "nothing left to remove")
    T.eq(#CC.List(), 0)
end)

-- Forever's spellbook (Camelot/Blizzard_PlayerSpellsFrame.xml): the book's page is
-- frameLevel 100 inside a toplevel window that the game raises on every click,
-- with its search box and spells above that. The switch and the catcher used to
-- sit at the window's level + 50, under the page's dark background, so the switch
-- looked grayed out and clicks went to the book, and binding never switched on.
T.test("the binder: the switch and the catcher draw above the whole spellbook, even after the game raises it", function()
    local DUI, ns, CC = login()
    local B = ns.ClickBinder
    local world = spellbook({ { spell = 2061, name = "Flash Heal" } })
    local psf = _G.PlayerSpellsFrame
    psf:SetFrameStrata("HIGH")
    psf:SetFrameLevel(3)
    world.book:SetFrameLevel(100)
    world.book.SearchBox:SetFrameLevel(102)
    world.items[1]:SetFrameLevel(104)
    world.items[1].Button:SetFrameLevel(105)
    stub.FireEvent("ADDON_LOADED", "Blizzard_PlayerSpells")
    world.Show()
    local ORDER = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
    T.truthy(ORDER[B.toggle:GetFrameStrata()] > ORDER.HIGH, "the switch sits a layer above the spellbook")
    B.toggle:Click()
    world.Hover(1)
    B.Driver():GetScript("OnUpdate")(B.Driver(), 1)
    T.truthy(B.catcher:IsShown())
    T.truthy(ORDER[B.catcher:GetFrameStrata()] > ORDER.HIGH, "the catcher too")
end)

T.test("the binder: with our own book window, the mode on never scans the veiled game book", function()
    local DUI, ns = login()
    local B = ns.ClickBinder
    local book = spellbook({ { spell = 139, name = "Renew" } })
    stub.FireEvent("ADDON_LOADED", "Blizzard_PlayerSpells")
    DUI.bookOwnWindow = true
    book.Show()
    DUI.ClickBind.Set(true)
    T.truthy(DUI.ClickBind.On())
    T.falsy(B.Driver():IsShown(), "our page binds by itself")
    DUI.ClickBind.Set(false)
    DUI.bookOwnWindow = nil
end)

T.test("the binder: DUI.ClickBind.Entry takes castable spells of yours only", function()
    local DUI = login()
    local E = DUI.ClickBind.Entry
    T.eq(E({ spellID = 139, name = "Renew", rank = "Rank 2" }).rank, "Rank 2")
    T.isnil(E({ spellID = 1, name = "x", passive = true }))
    T.isnil(E({ spellID = 1, name = "x", future = true }))
    T.isnil(E({ spellID = 1, name = "x", pet = true }))
end)

-- The game's mouseover setting, as its Combat settings read it: a CVar plus a
-- modified click that's saved with the key bindings.
local function mouseoverGame(state)
    state.cvar, state.key, state.saved = state.cvar or "0", state.key or "NONE", 0
    _G.GetCVar = function(n) if n == "enableMouseoverCast" then return state.cvar end end
    _G.GetCVarBool = function(n) return n == "enableMouseoverCast" and state.cvar == "1" end
    _G.SetCVar = function(n, v) if n == "enableMouseoverCast" then state.cvar = v end end
    _G.GetModifiedClick = function(n) return n == "MOUSEOVERCAST" and state.key or nil end
    _G.SetModifiedClick = function(n, v) if n == "MOUSEOVERCAST" then state.key = v end end
    _G.GetCurrentBindingSet = function() return 2 end
    _G.SaveBindings = function(set) state.saved = set end
end

T.test("mouseover casting: the switch is the game's own setting, the key saved with the bindings", function()
    local state = {}
    local _, _, CC = login({ before = function() mouseoverGame(state) end })
    T.truthy(CC.MouseoverSupported())
    T.falsy(CC.MouseoverOn())
    CC.SetMouseover(true)
    T.eq(state.cvar, "1")
    T.truthy(CC.MouseoverOn())
    T.eq(CC.MouseoverKey(), "NONE", "always, by default")
    CC.SetMouseoverKey("SHIFT")
    T.eq(state.key, "SHIFT")
    T.eq(state.saved, 2, "kept past a relog")
    CC.SetMouseover(false)
    T.eq(state.cvar, "0")
end)

T.test("mouseover casting: changed in a fight it waits for the fight's end", function()
    local state = {}
    local _, _, CC = login({ before = function() mouseoverGame(state) end })
    stub.EnterCombat()
    CC.SetMouseover(true)
    T.eq(state.cvar, "0", "not yet")
    stub.LeaveCombat()
    T.eq(state.cvar, "1")
end)

T.test("mouseover casting: a client without it hides the rows", function()
    local _, _, CC = login()
    _G.GetCVar = function() return nil end
    T.falsy(CC.MouseoverSupported())
end)
