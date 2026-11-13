local stub = require("stub")

-- The new action bars (Daylight UI's own buttons, Bars.lua) and the fake game's
-- secure mode they need. The old engine is tests/test_actionbars.lua.

-- Runs the motion kit's tweens to their end.
local function settle()
    local d = DaylightUI.Motion.Driver()
    for _ = 1, 60 do
        if not (d and d:GetScript("OnUpdate")) then return end
        stub.RunOnUpdate(d, 1 / 60)
    end
end

local function blocked(fn)
    local ok, err = pcall(fn)
    return not ok and string.find(tostring(err), "ADDON_ACTION_BLOCKED", 1, true) ~= nil
end

T.test("stub: macro conditions pick the first clause that holds", function()
    stub.Reset()
    stub.conditions = {}
    T.eq(SecureCmdOptionParse("[combat] show; hide"), "hide")
    stub.conditions = { combat = true }
    T.eq(SecureCmdOptionParse("[combat] show; hide"), "show")
    T.eq(SecureCmdOptionParse("[nocombat] a; b"), "b", "no- turns a condition round")
    stub.conditions = { ["bar:2"] = true, ["bonusbar:1"] = true }
    T.eq(SecureCmdOptionParse("[bar:2] 2; [bonusbar:1] 7; 1"), "2", "the first that holds wins")
    stub.conditions = { petbattle = true }
    T.eq(SecureCmdOptionParse("[vehicleui][petbattle] hide; show"), "hide", "brackets side by side: either")
    stub.conditions = { combat = true }
    T.eq(SecureCmdOptionParse("[combat,nopet] x; y"), "x", "a comma: both")
    stub.conditions = { combat = true, pet = true }
    T.eq(SecureCmdOptionParse("[combat,nopet] x; y"), "y")
    stub.conditions = {}
    T.isnil(SecureCmdOptionParse("[pet] x"), "nothing holds, no default")
end)

T.test("stub: in secure mode a state driver runs now and on new conditions", function()
    stub.Reset()
    stub.secure = true
    local f = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
    RegisterStateDriver(f, "visibility", "[combat] show; hide")
    T.falsy(f:IsShown(), "hidden at once")
    stub.SetConditions({ combat = true })
    T.truthy(f:IsShown(), "shown when the condition holds")
    f:SetAttribute("_onstate-page", "self:SetAttribute('seen', newstate)")
    RegisterStateDriver(f, "page", "[combat] 2; 1")
    T.eq(f:GetAttribute("state-page"), "2")
    T.eq(f:GetAttribute("seen"), "2", "the _onstate snippet ran")
end)

T.test("stub: out of secure mode a state driver only records", function()
    stub.Reset()
    local f = CreateFrame("Frame", nil, UIParent)
    RegisterStateDriver(f, "visibility", "hide")
    T.truthy(f:IsShown())
    T.eq(f.__stateDriver.visibility, "hide")
end)

T.test("stub: snippets run restricted: only allowed globals, no CallMethod", function()
    stub.Reset()
    stub.secure = true
    local f = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
    local child = CreateFrame("Button", nil, f, "SecureActionButtonTemplate")
    child:SetAttribute("_childupdate-page", "self:SetAttribute('got', message)")
    f:SetFrameRef("other", child)
    stub.RunSnippet(f, "self:ChildUpdate('page', tonumber('3')); self:GetFrameRef('other'):SetAttribute('ref', 1)")
    T.eq(child:GetAttribute("got"), 3, "ChildUpdate reached the child")
    T.eq(child:GetAttribute("ref"), 1, "a frame ref is a handle")
    T.errors(function() stub.RunSnippet(f, "print('x')") end, "print isn't allowed")
    T.errors(function() stub.RunSnippet(f, "self:CallMethod('Foo')") end, "CallMethod isn't allowed")
end)

T.test("stub: a protected frame refuses changes in combat, unless secure code makes them", function()
    stub.Reset()
    stub.secure = true
    local f = CreateFrame("Frame", "ProtectedThing", UIParent, "SecureHandlerStateTemplate")
    local plain = CreateFrame("Frame", nil, UIParent)
    stub.combat = true
    T.truthy(blocked(function() f:SetPoint("CENTER") end), "SetPoint")
    T.truthy(blocked(function() f:SetSize(1, 1) end), "SetSize")
    T.truthy(blocked(function() f:Hide() end), "Hide")
    T.truthy(blocked(function() f:SetAttribute("x", 1) end), "SetAttribute")
    T.truthy(blocked(function() f:SetParent(UIParent) end), "SetParent")
    T.truthy(blocked(function() RegisterStateDriver(f, "visibility", "hide") end), "RegisterStateDriver")
    T.truthy(blocked(function() SetOverrideBindingClick(f, false, "1", "ProtectedThing") end), "override bindings")
    T.noerror(function() plain:SetPoint("CENTER") end, "a plain frame is fine")
    T.noerror(function() f:SetAlpha(0.5) end, "alpha is fine")
    f.__stateDriver = { visibility = "show" }
    T.noerror(function() stub.RunDriver(f, "visibility") end, "a driver may show it in combat")
end)

T.test("stub: the combat-start event's handlers may still change protected frames, as in the client", function()
    stub.Reset()
    stub.secure = true
    local f = CreateFrame("Frame", "ProtectedThing2", UIParent, "SecureHandlerStateTemplate")
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:SetScript("OnEvent", function() f:Hide() end)
    T.noerror(function() stub.EnterCombat() end, "hidden as combat starts")
    T.falsy(f:IsShown())
    T.truthy(blocked(function() f:Show() end), "after that, blocked")
end)

T.test("stub: CreateFrame runs each template's builder, in order", function()
    stub.Reset()
    local seen = {}
    stub.TEMPLATES.FooTemplate = function(f) seen[#seen + 1] = "foo"; f.foo = true end
    stub.TEMPLATES.BarTemplate = function(f) seen[#seen + 1] = "bar" end
    local f = CreateFrame("Button", nil, UIParent, "FooTemplate, BarTemplate")
    T.truthy(f.foo)
    T.deq(seen, { "foo", "bar" })
end)

T.test("stub: bindings and override bindings", function()
    stub.Reset()
    stub.bindings = { ACTIONBUTTON1 = { "1", "Q" } }
    local a, b = GetBindingKey("ACTIONBUTTON1")
    T.eq(a, "1"); T.eq(b, "Q")
    T.isnil(GetBindingKey("ACTIONBUTTON2"))
    T.eq(GetBindingText("SHIFT-1", true), "SHIFT-1")
    local owner = CreateFrame("Frame")
    SetOverrideBindingClick(owner, false, "1", "SomeButton", "LeftButton")
    T.eq(stub.overrides["1"].click, "SomeButton")
    ClearOverrideBindings(owner)
    T.isnil(stub.overrides["1"])
    stub.keysDown = { ["1"] = true }
    T.truthy(IsKeyDown("1")); T.falsy(IsKeyDown("2"))
end)

T.test("bars: the toc and the test loader list the same files", function()
    local toc = {}
    for line in io.lines("DaylightUI_ActionBars/DaylightUI_ActionBars.toc") do
        local f = line:match("^([%w_/]+%.lua)%s*$")
        if f then toc[#toc + 1] = f end
    end
    T.deq(toc, stub.ACTIONBARS_FILES)
end)

local ABW = require("abworld")

-- The new bars. opts are newWorld's, plus login = false to stop before
-- PLAYER_LOGIN (files loaded, nothing enabled yet).
local function login(opts)
    opts = opts or {}
    return stub.Load({ actionbars = true, login = opts.login, before = function()
        ABW.newWorld(opts)
        if opts.class then stub.units = stub.units or {}; stub.units.player = { class = opts.class } end
    end })
end
local function AB() return stub.actionbars end
local function holder(key) return AB().Bars.holders[key] end
local function btn(key, i) return AB().Bars.buttons[key][i] end
local function noBlocked()
    for _, e in ipairs(stub.errors) do T.falsy(string.find(e, "BLOCKED", 1, true), e) end
end

T.test("shape: a bar's size from its settings, count and button width", function()
    login()
    local Shape = stub.actionbars.Shape
    local w, h = Shape.Extent({ size = 70, pad = 2, rows = 1 }, 12)
    T.near(w, 12 * 31.5 + 11 * 2); T.near(h, 31.5)
    w, h = Shape.Extent({ size = 70, pad = 2, rows = 2, icons = 12 })
    T.near(w, 6 * 31.5 + 5 * 2, nil, "two rows of six"); T.near(h, 2 * 31.5 + 2)
    w, h = Shape.Extent({ size = 70, pad = 2, rows = 2, icons = 12, vertical = true })
    T.near(w, 2 * 31.5 + 2, nil, "vertical swaps"); T.near(h, 6 * 31.5 + 5 * 2)
    w, h = Shape.Extent({ size = 60, pad = 2, rows = 1 }, 10, 30)
    T.near(w, 10 * 18 + 9 * 2, nil, "a small bar's 30-wide buttons"); T.near(h, 18)
    w, h = Shape.Extent({ size = 60, pad = 2, rows = 1, icons = 10 }, 0, 30)
    T.eq(w, 0, "no buttons, no size"); T.eq(h, 0)
    T.eq(Shape.Extent({ size = 70, pad = 2, rows = 1, icons = 6 }, 3), 3 * 31.5 + 2 * 2, "the count wins over the setting")
end)

T.test("switch: the new defaults are there", function()
    login()
    local d = stub.actionbars.DEFAULTS
    T.eq(d.bars.main.visible, "always")
    T.eq(d.bars.stance.icons, 10); T.eq(d.bars.pet.icons, 10)
    T.eq(d.bars.possess.visible, "always")
    T.eq(d.bars.bar5.visible, "hidden"); T.eq(d.bars.bar8.visible, "hidden")
    T.deq(d.bars.totem, { size = 60, pad = 2, rows = 1, vertical = false, visible = "always",
                          fade = { mode = "never", alpha = 0, mouseover = true, target = true, targetEnemy = false, delay = 4.5, opacity = 1 } })
    T.eq(d.bars.possess.fade.mode, "never")
    T.eq(d.bars.left.fade.mode, "always"); T.eq(d.bars.left.fade.delay, 3)
end)

T.test("movers: a default can be a function, asked each time the frame is placed", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    local y = 10
    DUI.Movers.Register(f, "test.live", "Live", function() return { "BOTTOM", "UIParent", "BOTTOM", 0, y } end)
    T.eq(select(5, f:GetPoint(1)), 10)
    y = 40
    DUI.Movers.Apply("test.live")
    T.eq(select(5, f:GetPoint(1)), 40, "the new default")
    T.eq(select(2, f:GetPoint(1)), UIParent)
    DUI.DB.Positions()["test.live"] = { 5, 6 }
    DUI.Movers.Apply("test.live")
    T.eq(f:GetPoint(1), "CENTER", "a saved spot still wins")
end)

T.test("world: the new bars' world has the button template and the game's frames", function()
    stub.Load({ actionbars = true, before = function() ABW.newWorld({ switch = false }) end })
    T.truthy(stub.secure)
    local b = CreateFrame("CheckButton", "WorldTestButton", UIParent, "ActionBarButtonTemplate, SecureActionButtonTemplate")
    T.truthy(b.icon and b.HotKey and b.Count and b.Name and b.Flash and b.Border)
    T.truthy(b.cooldown and b.chargeCooldown and b.lossOfControlCooldown)
    T.eq(b:GetAttribute("type"), "action")
    T.truthy(b:IsProtected())
    local joined = false
    for _, v in pairs(ActionBarButtonEventsFrame.frames) do joined = joined or v == b end
    T.truthy(joined, "joined the game's list")
    T.truthy(PossessButton1 and PossessButton2 and QuickKeybindFrame)
    T.truthy(MainMenuBarVehicleLeaveButton, "the leave-vehicle button (our build moves it off bar 1)")
    T.truthy(ActionButton1:IsProtected() and MainActionBar:IsProtected())
    T.eq(DaylightUIDB.newActionBars, false)
end)

T.test("park: the game's bars go under a hidden frame, never hidden themselves", function()
    login()
    local parked = DaylightUIParkedBars
    T.falsy(parked:IsShown(), "the parking frame is hidden")
    T.eq(MultiBarBottomLeft:GetParent(), parked); T.eq(MultiBar6:GetParent(), parked)
    T.truthy(MultiBarBottomLeft:IsShown(), "never Hide()n")
    T.isnil(next(MultiBarBottomLeft.__events), "bars 2-8 silenced")
    T.eq(MainActionBar:GetParent(), parked)
    T.truthy(MainActionBar:IsShown(), "bar 1 never Hide()n either")
    T.truthy(MainActionBar.__events.ACTIONBAR_PAGE_CHANGED, "bar 1 keeps its events (the game writes its page)")
    T.falsy(MainActionBar:IsMouseEnabled())
    T.eq(ActionButton1:GetParent(), MainActionBar, "twins stay where they are")
    -- Nothing written on them: an attribute written by an addon keeps its taint,
    -- and the game reads "statehidden" in its own fight-time pass.
    T.isnil(ActionButton1:GetAttribute("statehidden"), "no attribute written on a twin")
    T.isnil(MultiBarBottomLeftButton12:GetAttribute("statehidden"))
    T.falsy(ActionButton1:IsVisible(), "the parked bar keeps it out of sight")
    T.isnil(next(ActionBarActionEventsFrame.__events), "the per-action events frame is silenced")
    T.truthy(ActionBarButtonEventsFrame.__events.ACTIONBAR_SLOT_CHANGED, "the button events frame isn't touched")
end)

T.test("park: a client without bar 8 is fine; a bar the game takes back is parked again after combat", function()
    login()
    local Park = stub.actionbars.Park
    T.isnil(_G.MultiBar7)
    MultiBarBottomLeft:SetParent(UIParent)
    stub.EnterCombat()
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    T.eq(MultiBarBottomLeft:GetParent(), UIParent, "not in combat")
    stub.LeaveCombat()
    T.eq(MultiBarBottomLeft:GetParent(), DaylightUIParkedBars, "after combat")
end)

T.test("buttons: twelve per bar from the game's template, the plain secure click last", function()
    login()
    local Buttons = stub.actionbars.Buttons
    local b = btn("bar2", 3)
    T.eq(#AB().Bars.buttons.bar2, 12)
    T.eq(b:GetName(), "DaylightUIBar2Button3")
    T.eq(b:GetParent(), holder("bar2"))
    T.eq(b:GetObjectType(), "CheckButton")
    T.eq(b.__template, "ActionBarButtonTemplate, SecureActionButtonTemplate")
    T.eq(b:GetID(), 0)
    T.eq(b:GetAttribute("action"), 63, "page 6, button 3")
    T.eq(b:GetAttribute("dui-index"), 3)
    T.eq(b:GetAttribute("useOnKeyDown"), false)
    T.deq(b.__clicks, { "AnyUp" }, "a mouse click acts on release")
    T.eq(b.commandName, "MULTIACTIONBAR1BUTTON3")
    for _, field in ipairs({ "bar", "isExtra", "buttonType", "index" }) do
        T.isnil(rawget(b, field), "no ." .. field .. " (the game's secure code reads it)")
    end
    T.truthy(Buttons.IsOwn(b)); T.eq(Buttons.DefOf(b).key, "bar2")
    T.falsy(Buttons.IsOwn(ActionButton1))
    T.eq(Buttons.SlotOf(b), 63)
    T.eq(Buttons.Slot(13, 1), 145)
    T.eq(Buttons.All()[12 + 3], b)
end)

T.test("buttons: ours come off the game's events list in place; the game's entries stay", function()
    login()
    local list = ActionBarButtonEventsFrame.frames
    local made = AB().Bars.buttons.bar2
    T.eq(#list, 3, "the list didn't grow")
    T.eq(list[1], "game1"); T.eq(list[2], "game2"); T.eq(list[3], "game3")
    for _, v in pairs(list) do
        for _, b in ipairs(made) do T.falsy(v == b, "none of ours left") end
    end
end)

-- A /reload mid-swing: the template's first Update runs for slot 1 (its guess),
-- finds Attack on and starts the game's blink on every button. Park silences the
-- events that would stop it, so it ran until the next reload.
T.test("buttons: a reload mid-swing leaves none of ours blinking or in the game's watchers", function()
    login({ slots = { [1] = { texture = "attack", attack = true, current = true },
                      [2] = { texture = "tex2", spellID = 2 } } })
    for _, b in ipairs(AB().Buttons.All()) do
        T.falsy(b.flashing == 1, b:GetName() .. " not blinking")
        T.isnil(ActionBarButtonUpdateFrame.frames[b], b:GetName() .. " off the game's update loop")
        T.isnil(ActionBarActionEventsFrame.frames[b], b:GetName() .. " off the game's per-action events")
        T.falsy(b.Flash:IsShown(), b:GetName() .. " flash hidden")
    end
end)

T.test("buttons: one in the middle of the list goes by nil in place, never by shifting", function()
    login()
    local list = ActionBarButtonEventsFrame.frames
    local b = CreateFrame("CheckButton", "DUITestListButton", UIParent, "ActionBarButtonTemplate")   -- the game's code needs a name
    list[#list + 1] = "game4"
    local at = #list - 1
    T.eq(list[at], b)
    stub.actionbars.Buttons.Unlist(b)
    T.isnil(list[at]); T.eq(list[at + 1], "game4", "the game's entry didn't move")
end)

T.test("buttons: the action kind counts, sizes and hides like the game's bars", function()
    login()
    local K = stub.actionbars.Buttons.KIND
    T.eq(K.Count({}, { icons = 6 }), 6); T.eq(K.Count({}, { icons = 20 }), 12); T.eq(K.Count({}, {}), 12)
    T.eq(K.Base({}), 45)
    T.eq(K.Rule({ num = 1 }), "[petbattle] hide; ")
    T.eq(K.Rule({ num = 2 }), "[petbattle][vehicleui][overridebar] hide; ")
    T.deq(K.Caps, { icons = { 1, 12 }, rows = true, height = true, show = "action" })
end)

-- The template's own show, hover and slot-change code put the addon's buttons in
-- the game's range watcher, whose code then failed on them ("attempt to call a nil
-- value" in ActionButton.lua), and its hide turned the slot's range check off under
-- the addon's own painter.
T.test("buttons: ours never join the game's range or usable watchers", function()
    login()
    local b = btn("main", 1)
    local function held()
        for _, w in ipairs({ ActionBarButtonRangeCheckFrame, ActionBarButtonUsableWatcherFrame }) do
            for _, frames in pairs(w.actions) do
                if frames[b] then return true end
            end
        end
        return false
    end
    T.falsy(held(), "not after login")
    b:Hide(); b:Show()
    b:GetScript("OnEnter")(b)
    b:SetAttribute("action", 5)
    T.falsy(held(), "not after a show, a hover or a slot change")
    local slot = AB().Buttons.SlotOf(b)
    AB().Buttons.Paint(b)
    b:Hide()
    T.isnil(stub.rangeChecks[slot], "and our code never touches the client's range check")
    noBlocked()
end)

T.test("buttons: a hover in combat writes no attributes on ours", function()
    login()
    local b = btn("main", 9)
    stub.combat = true
    b:GetScript("OnEnter")(b)
    stub.combat = false
    noBlocked()
end)

-- Leaving stealth, a hover in combat ran the game's Update on the addon's buttons,
-- and its SetCooldown refused the secret times (ActionButton.lua). The addon's
-- painter draws the cooldown, and the game's Update stays off its buttons. A page
-- change in combat runs it too (the next test).
T.test("buttons: a hover in combat skips the game's cooldown code", function()
    login()
    local b = btn("main", 3)
    stub.secretCooldownErrors = 0
    stub.combat = true
    T.noerror(function() b:GetScript("OnEnter")(b) end)
    stub.combat = false
    T.eq(stub.secretCooldownErrors, 0)
end)

-- Eyes of the Beast in combat: the driver pages bar 1, each button's action
-- changes, and the game's script on it must not write attributes.
T.test("buttons: a page change in combat writes no attributes on ours", function()
    login()
    stub.combat = true
    stub.SetConditions({ ["bonusbar:3"] = true })
    T.eq(btn("main", 1):GetAttribute("action"), 97, "the page followed")
    stub.SetConditions({})
    stub.combat = false
    noBlocked()
end)

T.test("bars: built when the files load, before login", function()
    login({ login = false })
    T.truthy(AB().Bars.built)
    local h = holder("main")
    T.eq(h:GetName(), "DaylightUIBar1"); T.truthy(h:IsProtected())
    T.eq(btn("main", 1):GetName(), "DaylightUIBar1Button1")
    T.eq(btn("bar8", 12):GetName(), "DaylightUIBar8Button12", "bar 8, even without the game's")
    T.near(h:GetWidth(), 12 * 31.5 + 11 * 2); T.near(h:GetHeight(), 31.5)
    T.eq(h:GetPoint(1), "BOTTOM", "placed already")
    T.eq(MainActionBar:GetParent(), DaylightUIParkedBars, "the game's bars are parked")
    T.eq(DaylightUI.ActionBarButtons("main")[1], btn("main", 1))
end)

T.test("bars: buttons laid out from the settings", function()
    login()
    local step = (31.5 + 2) / 0.7      -- one button and a gap, in the buttons' own (scaled) units
    local b2 = btn("main", 2)
    T.near(b2:GetScale(), 0.7)
    local p, rel, _, x, y = b2:GetPoint(1)
    T.eq(p, "BOTTOMLEFT"); T.eq(rel, holder("main")); T.near(x, step); T.near(y, 0)
    local l = holder("left")
    T.near(l:GetWidth(), 6 * 31.5 + 5 * 2); T.near(l:GetHeight(), 2 * 31.5 + 2)
    _, _, _, x, y = btn("left", 7):GetPoint(1)
    T.near(x, 0); T.near(y, step, nil, "button 7 starts the second row, above the first")
    T.eq(btn("bar2", 3):GetAttribute("action"), 63)
    T.eq(btn("bar6", 1):GetAttribute("action"), 145)
end)

T.test("bars: a vertical bar runs down, then into the next column", function()
    login({ ab = { bars = { bar5 = { vertical = true, rows = 2, icons = 12 } } } })
    local step = (31.5 + 2) / 0.7
    local p, _, _, x, y = btn("bar5", 2):GetPoint(1)
    T.eq(p, "TOPLEFT"); T.near(x, 0); T.near(y, -step)
    _, _, _, x, y = btn("bar5", 7):GetPoint(1)
    T.near(x, step, nil, "the second column"); T.near(y, 0)
    T.near(holder("bar5"):GetWidth(), 2 * 31.5 + 2)
end)

T.test("bars: a start corner puts button 1 there and fills away from it, rows or columns", function()
    login({ ab = { bars = { bar5 = { rows = 4, icons = 12, corner = "bottomleft" } } } })
    local step = (31.5 + 2) / 0.7
    local p, _, _, x, y = btn("bar5", 2):GetPoint(1)
    T.eq(p, "BOTTOMLEFT"); T.near(x, step); T.near(y, 0, nil, "1, 2, 3 along the bottom")
    _, _, _, x, y = btn("bar5", 4):GetPoint(1)
    T.near(x, 0); T.near(y, step, nil, "4 starts the row above")
    DaylightUI:Set("ActionBars", "bars.bar5.corner", "topright")
    p, _, _, x, y = btn("bar5", 2):GetPoint(1)
    T.eq(p, "TOPRIGHT"); T.near(x, -step); T.near(y, 0)
    _, _, _, x, y = btn("bar5", 4):GetPoint(1)
    T.near(x, 0); T.near(y, -step, nil, "the next row under it")
    DaylightUI:Set("ActionBars", "bars.bar5.vertical", true)
    DaylightUI:Set("ActionBars", "bars.bar5.corner", "bottomright")
    p, _, _, x, y = btn("bar5", 2):GetPoint(1)
    T.eq(p, "BOTTOMRIGHT"); T.near(x, 0); T.near(y, step, nil, "a vertical bar runs up from the bottom")
    _, _, _, x, y = btn("bar5", 4):GetPoint(1)
    T.near(x, -step, nil, "then the next column to the left"); T.near(y, 0)
    T.eq(AB().Bars.Corner(AB().Bars.DEFS[1], AB().DEFAULTS.bars.main), "bottomleft", "bar 1 unset: as before")
    T.eq(AB().Bars.Corner(AB().Bars.DEFS[5], AB().DEFAULTS.bars.bar5), "topleft")
end)

T.test("bars: a button height under 100 makes wide buttons, the icon cropped to fit, not stretched", function()
    login({ ab = { bars = { bar5 = { rows = 2, icons = 12, height = 50, visible = "always" } } } })
    local b = btn("bar5", 2)
    T.near(b:GetWidth(), 45); T.near(b:GetHeight(), 22.5, nil, "half as tall, in its own scale")
    T.near(holder("bar5"):GetWidth(), 6 * 31.5 + 5 * 2)
    T.near(holder("bar5"):GetHeight(), 2 * 15.75 + 2, nil, "the bar shrinks with it")
    local _, _, _, x, y = btn("bar5", 7):GetPoint(1)
    T.near(x, 0); T.near(y, -(15.75 + 2) / 0.7, nil, "the next row a short button down")
    local l, r, t, bt = b.icon:GetTexCoord()
    T.near((bt - t) / (r - l), 0.5, 0.001, "the art cut to the button's shape")
    T.near((t + bt) / 2, 0.5, 0.001, "around its middle")
    DaylightUI:Set("ActionBars", "bars.bar5.height", 100)
    T.near(b:GetHeight(), 45, nil, "square again")
    l, r, t, bt = b.icon:GetTexCoord()
    T.near(bt - t, r - l, 0.001)
    DaylightUI:Set("ActionBars", "bars.bar5.height", 150)
    l, r, t, bt = b.icon:GetTexCoord()
    T.near((r - l) / (bt - t), 1 / 1.5, 0.001, "a tall button crops the sides")
    DaylightUI:Set("ActionBars", "bars.bar5.vertical", true)
    T.near(holder("bar5"):GetWidth(), 2 * 31.5 + 2, nil, "vertical: two columns as wide as a button")
    T.near(holder("bar5"):GetHeight(), 6 * 47.25 + 5 * 2)
    noBlocked()
end)

T.test("bars: a setting applies at once, no reload; fewer buttons hide the rest", function()
    login()
    if DaylightUIInstaller then DaylightUIInstaller:Hide() end   -- made the first time it shows
    stub.popup = nil
    DaylightUI:Set("ActionBars", "bars.main.icons", 6)
    T.near(holder("main"):GetWidth(), 6 * 31.5 + 5 * 2)
    T.falsy(btn("main", 7):IsShown()); T.eq(btn("main", 7):GetAttribute("statehidden"), true)
    T.truthy(btn("main", 6):IsShown())
    DaylightUI:Set("ActionBars", "bars.main.icons", 12)
    T.truthy(btn("main", 7):IsShown()); T.isnil(btn("main", 7):GetAttribute("statehidden"))
    T.isnil(stub.popup, "no reload asked")
end)

T.test("bars: a change in combat waits for combat to end", function()
    login()
    stub.EnterCombat()
    T.noerror(function() DaylightUI:Set("ActionBars", "bars.main.rows", 2) end)
    T.near(holder("main"):GetHeight(), 31.5, nil, "not in combat")
    stub.LeaveCombat()
    T.near(holder("main"):GetHeight(), 2 * 31.5 + 2)
    noBlocked()
end)

T.test("bars: a slider dragged in combat lands once, after combat", function()
    login()
    stub.EnterCombat()
    for _, v in ipairs({ 80, 90, 100 }) do DaylightUI:Set("ActionBars", "bars.main.size", v) end
    T.near(holder("main"):GetWidth(), 400)
    stub.LeaveCombat()
    T.near(holder("main"):GetWidth(), 12 * 45 + 11 * 2, nil, "the last value")
    T.near(btn("main", 1):GetScale(), 1)
    noBlocked()
end)

T.test("bars: login re-lays out from the profile in use", function()
    login({ login = false })
    T.near(holder("main"):GetWidth(), 400)
    DaylightUIDB.profileData[DaylightUI.DB.DEFAULT].modules.ActionBars.bars.main.size = 100
    stub.FireEvent("PLAYER_LOGIN")
    T.near(holder("main"):GetWidth(), 12 * 45 + 11 * 2)
end)

T.test("bars: holders sit at the old default places; a saved spot and a reset apply at once", function()
    login()
    local p, rel, rp, x, y = holder("main"):GetPoint(1)
    T.eq(p, "BOTTOM"); T.eq(rel, UIParent); T.eq(rp, "BOTTOM"); T.eq(x, 0); T.eq(y, 26)
    T.near(select(5, holder("bar2"):GetPoint(1)), 26 + 31.5 + 2, nil, "bar 2 on bar 1")
    DaylightUI:Set("ActionBars", "bars.main.size", 100)
    T.near(select(5, holder("bar2"):GetPoint(1)), 26 + 45 + 2, nil, "a bigger bar 1 pushes bar 2 up, live")
    local e = DaylightUI.Movers.Get("actionbars.main")
    T.falsy(e.proxy, "a plain mover: it moves the real bar"); T.eq(e.frame, holder("main"))
    DaylightUI.DB.Positions()["actionbars.main"] = { 100, -400 }
    DaylightUI.Movers.Apply("actionbars.main")
    p, _, _, x, y = holder("main"):GetPoint(1)
    T.eq(p, "CENTER"); T.eq(x, 100); T.eq(y, -400)
    AB().Bars.ResetPositions()
    T.eq(holder("main"):GetPoint(1), "BOTTOM", "reset: back at once")
    T.isnil(DaylightUI.DB.Positions()["actionbars.main"])
end)

T.test("bars: when a bar shows: its kind's clauses, then its Show setting", function()
    login()
    T.eq(holder("main").__stateDriver.visibility, "[petbattle] hide; show")
    T.eq(holder("bar2").__stateDriver.visibility, "[petbattle][vehicleui][overridebar] hide; show")
    DaylightUI:Set("ActionBars", "bars.bar2.visible", "combat")
    T.eq(holder("bar2").__stateDriver.visibility, "[petbattle][vehicleui][overridebar] hide; [combat] show; hide")
    T.falsy(holder("bar2"):IsShown())
    stub.SetConditions({ combat = true })
    T.truthy(holder("bar2"):IsShown())
    stub.SetConditions({ combat = true, vehicleui = true })
    T.falsy(holder("bar2"):IsShown(), "the game hides bars 2-8 in a vehicle too")
    T.truthy(holder("main"):IsShown(), "bar 1 stays")
    stub.SetConditions({ petbattle = true })
    T.falsy(holder("main"):IsShown())
    DaylightUI:Set("ActionBars", "bars.main.visible", "hidden")
    stub.SetConditions({})
    T.falsy(holder("main"):IsShown(), "bar 1 can be hidden too")
end)

-- Bars 5-8 start hidden. A profile from before keeps the ones it uses.
local BARS_5_TO_8 = { "bar5", "bar6", "bar7", "bar8" }
local function relog(saved, slots)
    stub.Load({ actionbars = true, before = function()
        ABW.newWorld({ slots = slots })
        DaylightUIDB = saved
    end })
    stub.FireEvent("PLAYER_ENTERING_WORLD")
end
local function shows(key) return DaylightUI:Get("ActionBars", "bars." .. key .. ".visible") end

T.test("bars 5-8: hidden on a new install, on both profiles", function()
    relog(nil)
    for _, key in ipairs(BARS_5_TO_8) do
        T.eq(shows(key), "hidden", key)
        T.falsy(holder(key):IsShown(), key)
    end
    T.truthy(holder("bar2"):IsShown(), "bar 2 still shows")
    local made = DaylightUI.Profiles.AddPreset("Healer")
    local healer = DaylightUIDB.profileData[made]
    T.eq(healer.hiddenBars1, true, "made past the one-time keep")
    for _, key in ipairs(BARS_5_TO_8) do T.eq(healer.modules.ActionBars.bars[key].visible, "hidden", "Healer " .. key) end
end)

T.test("bars 5-8: a profile from before keeps the ones with something on them, once", function()
    -- Bar 6 (slots 145-156) has a spell; bar 7 was hidden by hand.
    local slots = { [1] = { texture = "t1" }, [145] = { texture = "t145" } }
    login({ ab = { bars = { bar7 = { visible = "hidden" } } }, slots = slots })
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    T.eq(shows("bar5"), "hidden", "nothing on it: hidden")
    T.falsy(holder("bar5"):IsShown())
    T.eq(shows("bar6"), "always", "in use: kept")
    T.truthy(holder("bar6"):IsShown())
    T.eq(shows("bar7"), "hidden", "hidden by hand stays hidden")
    T.eq(shows("bar8"), "hidden")
    -- Shown again by hand, so not hidden again at later logins.
    DaylightUI:Set("ActionBars", "bars.bar5.visible", "always")
    stub.FireEvent("PLAYER_LOGOUT")
    relog(DaylightUIDB, slots)
    T.eq(shows("bar5"), "always", "stays shown")
    T.truthy(holder("bar5"):IsShown())
    T.eq(shows("bar6"), "always")
    stub.FireEvent("PLAYER_LOGOUT")
    relog(DaylightUIDB, slots)
    T.eq(shows("bar5"), "always", "and again")
end)

T.test("bars 5-8: the check waits until the game has sent the actions", function()
    login({ slots = {} })
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    T.eq(shows("bar5"), "always", "nothing known yet: left as it was")
    stub.slots[150] = { texture = "t150" }
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    T.eq(shows("bar5"), "hidden")
    T.eq(shows("bar6"), "always", "slot 150 is on bar 6")
end)

T.test("bars: our buttons wear the skin; empty slots hide by alpha", function()
    login()
    local Skin = AB().Skin
    T.truthy(Skin.IsSkinned(btn("main", 3)))
    T.eq(Skin.GetParts(btn("main", 3)).back:GetAlpha(), 1, "slot 3 has an action")
    T.eq(Skin.GetParts(btn("main", 5)).back:GetAlpha(), 0, "slot 5 is empty")
    T.eq(Skin.GetParts(btn("bar2", 2)).back:GetAlpha(), 0, "bar 2's slot 62 is empty")
    T.falsy(Skin.IsSkinned(ActionButton1), "the game's hidden buttons are left alone")
    T.eq(MainActionBar.EndCaps:GetAlpha(), 1, "the parked bar's art isn't touched")
end)

T.test("bars: fade until mouseover works on our holders", function()
    login()
    local Fade = DaylightUI.Fade
    local h = holder("left")
    function h:IsMouseOver() return self.__mouse == true end
    local function run()
        Fade.Step()
        for _ = 1, 120 do stub.RunOnUpdate(Fade.driver, 1 / 60) end
    end
    stub.now = (stub.now or 0) + 4   -- abworld's clock
    run()
    T.eq(h:GetAlpha(), 0, "the side grid faded")
    T.eq(holder("main"):GetAlpha(), 1, "bar 1 doesn't")
    h.__mouse = true
    run()
    T.eq(h:GetAlpha(), 1, "back under the mouse")
end)

T.test("bars: the core still looks after its Edit Mode layout (the setup guide asks)", function()
    login()
    if DaylightUIInstaller then DaylightUIInstaller:Hide() end   -- made the first time it shows
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    T.truthy(DaylightUIInstaller:IsShown(), "a new character is still asked to set up")
end)

T.test("bars: a fade ends at exactly its goal even when the game keeps alpha in 1/255 steps", function()
    login({ ab = { bars = { main = { mouseover = true } } } })
    local Fade = DaylightUI.Fade
    local h = holder("main")
    local a = 1
    function h:SetAlpha(v) a = math.ceil(v * 255 - 1e-9) / 255 end   -- the client rounds up
    function h:GetAlpha() return a end
    h.IsMouseOver = function() return true end
    local function run()
        Fade.Step()
        for _ = 1, 120 do stub.RunOnUpdate(Fade.driver, 1 / 60) end
    end
    run()
    T.eq(a, 1, "the old mouseover setting came over: shown under the mouse")
    h.IsMouseOver = function() return false end
    stub.now = (stub.now or 0) + 4   -- abworld's clock
    run()
    T.eq(a, 0, "all the way down")
    h.IsMouseOver = function() return true end
    run()
    T.eq(a, 1, "all the way back")
end)

T.test("paging: the rule asks the game for the special pages, in the game's order", function()
    login()
    T.eq(AB().Paging.Rule(), "[overridebar] 33; [vehicleui] 31; [possessbar] 31; [shapeshift] 32; "
        .. "[bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6; "
        .. "[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10; [bonusbar:5] 11; 1")
    GetOverrideBarIndex = function() return 40 end
    GetVehicleBarIndex = nil
    GetTempShapeshiftBarIndex = function() error("not yet") end
    local rule = AB().Paging.Rule()
    T.truthy(rule:find("[overridebar] 40", 1, true), "the game's number")
    T.truthy(rule:find("[vehicleui] 31", 1, true), "missing: the proven number")
    T.truthy(rule:find("[shapeshift] 32", 1, true), "erroring: the proven number")
end)

T.test("paging: bar 1's form and page changes switched off keep it on its own buttons", function()
    login()
    DaylightUI:Set("ActionBars", "bars.main.autoPage", false)
    for _, case in ipairs({ { { ["bonusbar:1"] = true }, 1 }, { { ["bar:3"] = true }, 1 },
                            { { vehicleui = true }, 31 }, { {}, 1 } }) do
        stub.SetConditions(case[1] or {})
        local page = case[2] or 1
        T.eq(holder("main"):GetAttribute("actionpage"), page, "page " .. page)
        T.eq(MainActionBar:GetAttribute("actionpage"), page, "the game's bar 1 too")
    end
    DaylightUI:Set("ActionBars", "bars.main.autoPage", true)
    stub.SetConditions({ ["bonusbar:1"] = true })
    T.eq(holder("main"):GetAttribute("actionpage"), 7, "back on: forms page it again")
    stub.SetConditions({})
end)

-- Conditions, and the page bar 1 must show.
local PAGES = {
    { {}, 1 }, { { ["bar:2"] = true }, 2 }, { { ["bar:6"] = true }, 6 },
    { { ["bonusbar:1"] = true }, 7 }, { { ["bonusbar:3"] = true }, 9 }, { { ["bonusbar:5"] = true }, 11 },
    { { ["bar:2"] = true, ["bonusbar:1"] = true }, 2 },   -- a page picked by hand beats a form, as in the game
    { { vehicleui = true }, 31 }, { { overridebar = true }, 33 }, { { possessbar = true }, 31 },
    { { shapeshift = true }, 32 }, { { overridebar = true, vehicleui = true }, 33 },
    { { vehicleui = true, ["bonusbar:1"] = true }, 31 },
}

T.test("paging: bar 1 follows every clause, and the game's hidden bar 1 follows it", function()
    login()
    for _, case in ipairs(PAGES) do
        stub.SetConditions(case[1])
        local page = case[2]
        local where = "page " .. page
        T.eq(holder("main"):GetAttribute("actionpage"), page, where)
        T.eq(btn("main", 1):GetAttribute("action"), (page - 1) * 12 + 1, where)
        T.eq(btn("main", 12):GetAttribute("action"), (page - 1) * 12 + 12, where)
        T.eq(MainActionBar:GetAttribute("actionpage"), page, where .. ": the game's bar 1 too")
    end
end)

T.test("paging: hidden buttons still follow the page", function()
    login()
    DaylightUI:Set("ActionBars", "bars.main.icons", 4)
    stub.SetConditions({ ["bonusbar:3"] = true })
    T.falsy(btn("main", 10):IsShown())
    T.eq(btn("main", 10):GetAttribute("action"), 106)
    DaylightUI:Set("ActionBars", "bars.main.icons", 12)
    T.truthy(btn("main", 10):IsShown())
    T.eq(btn("main", 10):GetAttribute("action"), 106, "the right spell at once")
end)

T.test("paging: bars 2-8 keep their fixed slots, with no driver", function()
    login()
    stub.SetConditions({ ["bonusbar:1"] = true })
    T.isnil(holder("bar2").__stateDriver.page)
    T.eq(btn("bar2", 1):GetAttribute("action"), 61)
end)

-- The player's class (the fake world starts with no player unit).
local function asClass(c)
    stub.units = stub.units or {}
    stub.units.player = stub.units.player or {}
    stub.units.player.class = c
end

T.test("paging: every paging state has a default of no change on bars 2-8, only the held keys on bar 1", function()
    login()
    for _, def in ipairs(AB().Bars.DEFS) do
        local d = AB().DEFAULTS.bars[def.key]
        if def.kind == "action" and def.page then
            for _, state in ipairs(AB().Paging.STATES) do
                if def.paged and not state.held then T.isnil(d.paging[state.id], def.key .. " " .. state.id)
                else T.eq(d.paging[state.id], 0, def.key .. " " .. state.id) end
            end
        else
            T.isnil(d.paging, def.key)
        end
    end
end)

T.test("paging: a bar 5 page for Cat Form shows it in cat, and the game's bar 5 follows so the key casts it", function()
    login()
    asClass("DRUID")
    DaylightUI:Set("ActionBars", "bars.bar5.paging.cat", 2)
    DaylightUI:Set("ActionBars", "bars.bar5.paging.prowl", 11)
    T.eq(holder("bar5").__stateDriver.page, "[bonusbar:1,stealth] 11; [bonusbar:1] 2; 4")
    local cases = { { {}, 4 }, { { ["bonusbar:1"] = true }, 2 }, { { ["bonusbar:1"] = true, stealth = true }, 11 },
                    { { ["bonusbar:3"] = true }, 4 } }
    for _, case in ipairs(cases) do
        stub.SetConditions(case[1])
        local page, where = case[2], "page " .. case[2]
        T.eq(btn("bar5", 1):GetAttribute("action"), (page - 1) * 12 + 1, where)
        T.eq(btn("bar5", 12):GetAttribute("action"), (page - 1) * 12 + 12, where)
        T.eq(MultiBarLeft:GetAttribute("actionpage"), page, where .. ": the game's twin too")
    end
    T.eq(MultiBarBottomLeft:GetAttribute("actionpage"), 6, "other bars keep theirs")
    T.isnil(holder("bar2").__stateDriver.page)
    noBlocked()
end)

T.test("paging: a held key beats a form; another class's states and a bar's own page add nothing", function()
    login()
    asClass("ROGUE")
    DaylightUI:Set("ActionBars", "bars.right.paging.stealth", 7)
    DaylightUI:Set("ActionBars", "bars.right.paging.shift", 12)
    DaylightUI:Set("ActionBars", "bars.right.paging.cat", 9)        -- a druid's
    DaylightUI:Set("ActionBars", "bars.right.paging.alt", 3)        -- its own page
    T.eq(holder("right").__stateDriver.page, "[mod:shift] 12; [bonusbar:1] 7; 3")
    stub.SetConditions({ ["bonusbar:1"] = true, ["mod:shift"] = true })
    T.eq(btn("right", 1):GetAttribute("action"), 133)
    T.eq(MultiBarRight:GetAttribute("actionpage"), 12)
end)

T.test("paging: bar 1's Shift page shows while Shift is held, over a form, and the game's bar 1 is written back after its own form write", function()
    login()
    asClass("DRUID")
    DaylightUI:Set("ActionBars", "bars.main.paging.shift", 13)
    local cases = { { {}, 1 }, { { ["mod:shift"] = true }, 13 }, { { ["bonusbar:1"] = true }, 7 },
                    { { ["bonusbar:1"] = true, ["mod:shift"] = true }, 13 },
                    { { vehicleui = true, ["mod:shift"] = true }, 31 } }
    for _, case in ipairs(cases) do
        stub.SetConditions(case[1])
        local page, where = case[2], "page " .. case[2]
        T.eq(btn("main", 1):GetAttribute("action"), (page - 1) * 12 + 1, where)
        T.eq(MainActionBar:GetAttribute("actionpage"), page, where .. ": the game's bar 1 too")
    end
    -- Shift held, then a form: the game writes its form page and the addon writes 13 back.
    stub.SetConditions({ ["mod:shift"] = true })
    MainActionBar:SetAttribute("actionpage", 9)
    stub.SetConditions({ ["mod:shift"] = true, ["bonusbar:3"] = true })
    T.eq(MainActionBar:GetAttribute("actionpage"), 13, "written back after the form change")
    DaylightUI:Set("ActionBars", "bars.main.paging.shift", 0)
    T.falsy(holder("main").__stateDriver.page:find("mod:", 1, true), "no change: no held clause")
    noBlocked()
end)

T.test("paging: a friendly or enemy target pages bars 2-8 and bar 1; a held key comes first, then the target, then a form", function()
    login()
    asClass("WARRIOR")
    DaylightUI:Set("ActionBars", "bars.bar2.paging.harm", 13)
    DaylightUI:Set("ActionBars", "bars.bar2.paging.help", 14)
    DaylightUI:Set("ActionBars", "bars.bar2.paging.shift", 15)
    DaylightUI:Set("ActionBars", "bars.bar2.paging.battle", 2)
    T.eq(holder("bar2").__stateDriver.page, "[mod:shift] 15; [help] 14; [harm] 13; [bonusbar:1] 2; 6")
    local cases = { { {}, 6 }, { { harm = true }, 13 }, { { help = true }, 14 },
                    { { harm = true, ["bonusbar:1"] = true }, 13 }, { { ["bonusbar:1"] = true }, 2 },
                    { { harm = true, ["mod:shift"] = true }, 15 } }
    for _, case in ipairs(cases) do
        stub.SetConditions(case[1])
        T.eq(btn("bar2", 1):GetAttribute("action"), (case[2] - 1) * 12 + 1, "page " .. case[2])
        T.eq(MultiBarBottomLeft:GetAttribute("actionpage"), case[2], "the game's twin too")
    end
    stub.SetConditions({})
    DaylightUI:Set("ActionBars", "bars.main.paging.harm", 13)
    stub.SetConditions({ harm = true, ["bonusbar:1"] = true })
    T.eq(btn("main", 1):GetAttribute("action"), 145, "bar 1 over its stance page")
    T.eq(MainActionBar:GetAttribute("actionpage"), 13)
    MainActionBar:SetAttribute("actionpage", 7)
    stub.SetConditions({ harm = true, ["bonusbar:2"] = true })
    T.eq(MainActionBar:GetAttribute("actionpage"), 13, "written back after the game's own stance write")
    stub.SetConditions({ ["bonusbar:2"] = true })
    T.eq(btn("main", 1):GetAttribute("action"), 85, "no target: the stance page again")
    noBlocked()
end)

T.test("paging: back to no change drops the driver and gives the bar and its twin their own page", function()
    login()
    asClass("WARRIOR")
    DaylightUI:Set("ActionBars", "bars.bar2.paging.defensive", 2)
    stub.SetConditions({ ["bonusbar:2"] = true })
    T.eq(btn("bar2", 1):GetAttribute("action"), 13)
    DaylightUI:Set("ActionBars", "bars.bar2.paging.defensive", 0)
    T.isnil(holder("bar2").__stateDriver.page)
    T.eq(btn("bar2", 1):GetAttribute("action"), 61)
    T.eq(MultiBarBottomLeft:GetAttribute("actionpage"), 6)
end)

T.test("paging: a pick made in combat lands after combat; a /reload keeps it", function()
    login()
    asClass("DRUID")
    stub.EnterCombat()
    DaylightUI:Set("ActionBars", "bars.bar5.paging.bear", 2)
    T.isnil(holder("bar5").__stateDriver.page, "not in combat")
    stub.LeaveCombat()
    T.eq(holder("bar5").__stateDriver.page, "[bonusbar:3] 2; 4")
    noBlocked()
    login({ class = "DRUID", ab = { bars = { bar5 = { paging = { bear = 2 } } } } })
    T.eq(holder("bar5").__stateDriver.page, "[bonusbar:3] 2; 4", "built at file load")
end)

T.test("paging: the page list names each bar's page and your forms' pages on bar 1", function()
    login()
    asClass("DRUID")
    local row
    for _, page in ipairs(AB().OPTIONS.pages) do
        for _, g in ipairs(page.groups) do
            for _, item in ipairs(g.items) do
                if item.key == "bars.bar5.paging.cat" then row = item end
            end
        end
    end
    T.truthy(row, "the row is on Bar Layout")
    local values, order = row.choices()
    T.eq(order[1], 0)
    T.eq(values[0], "No change")
    T.eq(values[4], "Action Bar 5")
    T.eq(values[7], "Action Bar 1 in Cat Form")
    T.eq(values[9], "Action Bar 1 in Bear Form")
    T.eq(values[2], "Spare page 2")
    T.eq(#order, 16)
    -- Read top to bottom: the bars by their own number, then the forms' pages,
    -- then the spare pages, whatever page number the game gives each.
    local names = {}
    for i = 2, #order do names[#names + 1] = values[order[i]] end
    for n = 1, 8 do T.eq(names[n], "Action Bar " .. n, "bar " .. n .. " in its place") end
    T.eq(names[9], "Action Bar 1 in Cat Form")
    T.eq(names[10], "Action Bar 1 in Bear Form")
    local spare = {}
    for i = 11, #names do
        spare[#spare + 1] = tonumber(names[i]:match("^Spare page (%d+)$"))
        T.truthy(spare[#spare], names[i] .. " is a spare page")
        if #spare > 1 then T.truthy(spare[#spare] > spare[#spare - 1], "spare pages in number order") end
    end
end)

T.test("paging: the rule is built again at each loading screen, after combat", function()
    login()
    GetOverrideBarIndex = function() return 40 end
    stub.EnterCombat()
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    T.falsy(holder("main").__stateDriver.page:find("40", 1, true), "not in combat")
    stub.LeaveCombat()
    T.truthy(holder("main").__stateDriver.page:find("[overridebar] 40", 1, true))
    noBlocked()
end)

-- A druid powershifting with "/cast !Cat Form": the client's bonus bar went stale,
-- so the caster bar stayed up in Cat Form, and a key pressed the game's hidden bar
-- 1, whose page the game writes from that same stale value. A druid's bars page by
-- the form itself, and bar 1's page goes onto each of the game's hidden buttons,
-- which read their own page before their bar's (SecureButton_GetModifiedAttribute).
local DRUID_FORMS = { 5487, 1066, 768, 783, 24858 }   -- Bear, Aquatic, Cat, Travel, Moonkin

-- The page a key on the game's hidden bar 1 casts from, as the game works it out.
local function keyPage(i)
    local b = _G["ActionButton" .. i]
    return b:GetAttribute("actionpage") or MainActionBar:GetAttribute("actionpage")
end

T.test("paging: a druid's bar 1 pages by the form, so a stale bonus bar never leaves the caster bar up", function()
    login({ class = "DRUID", formSpells = DRUID_FORMS })
    local rule = AB().Paging.Rule()
    T.truthy(rule:find("[form:3] 7; [form:1] 9; [form:5] 10", 1, true), rule)
    T.falsy(rule:find("bonusbar:1", 1, true), "never the bonus bar for a form the druid has")
    T.truthy(rule:find("[bonusbar:5] 11", 1, true), "possess stays")
    -- Powershifted into Cat: in Cat Form, while the bonus bar still says caster.
    stub.SetConditions({ ["form:3"] = true })
    T.eq(holder("main"):GetAttribute("actionpage"), 7, "the cat bar")
    -- The game writes its bar 1 from the stale bonus bar, yet the keys still cast cat.
    MainActionBar:SetAttribute("actionpage", 1)
    T.eq(keyPage(1), 7, "a key casts what the button shows")
    T.eq(keyPage(12), 7)
    -- Out of Cat with the bonus bar stuck on cat: the caster bar.
    stub.SetConditions({ ["bonusbar:1"] = true })
    T.eq(holder("main"):GetAttribute("actionpage"), 1, "caster")
    T.eq(keyPage(1), 1)
    stub.SetConditions({ ["form:1"] = true })
    T.eq(holder("main"):GetAttribute("actionpage"), 9, "bear")
    stub.SetConditions({ ["form:4"] = true })
    T.eq(holder("main"):GetAttribute("actionpage"), 1, "travel form: the caster bar, as the game shows it")
    stub.SetConditions({})
    noBlocked()
end)

T.test("paging: a powershift macro's /click DaylightUICat keeps the cat bar up while the game confirms the form", function()
    login({ class = "DRUID", formSpells = DRUID_FORMS })
    local h = holder("main")
    T.truthy(DaylightUICat and DaylightUIBear and DaylightUIMoonkin, "the macro buttons")
    T.eq(DaylightUICat:GetAttribute("attribute-value"), 7); T.eq(DaylightUIBear:GetAttribute("attribute-value"), 9)
    T.eq(DaylightUIMoonkin:GetAttribute("attribute-value"), 10)
    stub.SetConditions({ ["form:1"] = true })
    T.eq(h:GetAttribute("actionpage"), 9, "bear")
    stub.EnterCombat()
    -- "/click DaylightUICat" then "/cast !Cat Form": the game drops to caster first.
    stub.SecureClick(DaylightUICat)
    stub.SetConditions({})
    T.eq(h:GetAttribute("actionpage"), 7, "the cat bar at once, not the caster bar")
    T.eq(keyPage(1), 7, "and the keys cast it")
    stub.SetConditions({ ["form:3"] = true })
    T.eq(h:GetAttribute("actionpage"), 7, "cat confirmed")
    T.isnil(h:GetAttribute("dui-hold"), "the hold is over")
    stub.SetConditions({})
    T.eq(h:GetAttribute("actionpage"), 1, "a real drop to caster afterwards shows the caster bar")
    -- Cat to Cat (the energy powershift): the cat bar never leaves.
    stub.SetConditions({ ["form:3"] = true })
    stub.SecureClick(DaylightUICat)
    stub.SetConditions({})
    T.eq(h:GetAttribute("actionpage"), 7)
    stub.SetConditions({ ["form:3"] = true })
    stub.LeaveCombat()
    -- A click whose shift never came (on cooldown) lets go a moment later.
    stub.SecureClick(DaylightUIBear)
    stub.SetConditions({})
    T.eq(h:GetAttribute("actionpage"), 9, "held while waiting")
    stub.RunTimers()
    T.eq(h:GetAttribute("actionpage"), 1, "no bear came: back to the caster bar")
    T.isnil(h:GetAttribute("dui-hold"))
    -- With "Change with forms and stances" off the bar stays on page 1.
    DaylightUI:Set("ActionBars", "bars.main.autoPage", false)
    T.isnil(DaylightUICat:GetAttribute("attribute-value"))
    stub.SetConditions({ ["form:1"] = true })
    stub.SecureClick(DaylightUICat)
    stub.SetConditions({})
    T.eq(h:GetAttribute("actionpage"), 1)
    noBlocked()
end)

T.test("paging: only a druid gets the powershift macro buttons", function()
    login({ class = "WARRIOR" })
    T.isnil(_G.DaylightUICat)
end)

T.test("paging: a druid's bars 2-8 page by the form too; forms learned build it again after combat", function()
    login({ class = "DRUID", formSpells = { 5487, 1066 } })
    DaylightUI:Set("ActionBars", "bars.bar5.paging.cat", 2)
    DaylightUI:Set("ActionBars", "bars.bar5.paging.bear", 3)
    T.eq(holder("bar5").__stateDriver.page, "[form:1] 3; 4", "no Cat Form yet: no cat clause")
    -- Cat Form learned: the stance bar has it third.
    stub.formSpells = { 5487, 1066, 768 }
    stub.forms = 3
    stub.EnterCombat()
    stub.FireEvent("UPDATE_SHAPESHIFT_FORMS")
    T.eq(holder("bar5").__stateDriver.page, "[form:1] 3; 4", "not in combat")
    stub.LeaveCombat()
    T.eq(holder("bar5").__stateDriver.page, "[form:3] 2; [form:1] 3; 4")
    T.truthy(holder("main").__stateDriver.page:find("[form:3] 7", 1, true), "bar 1 too")
    DaylightUI:Set("ActionBars", "bars.bar5.paging.prowl", 11)
    T.eq(holder("bar5").__stateDriver.page, "[form:3,stealth] 11; [form:3] 2; [form:1] 3; 4")
    stub.SetConditions({ ["form:3"] = true, stealth = true })
    T.eq(MultiBarLeft:GetAttribute("actionpage"), 11)
    stub.SetConditions({})
    noBlocked()
end)

T.test("paging: Bear and Dire Bear are one form: either page bar 1 to the bear bar", function()
    login({ class = "DRUID", formSpells = { 9634, 768 } })
    T.truthy(AB().Paging.Rule():find("[form:2] 7; [form:1] 9", 1, true))
    T.eq(AB().Paging.FormConds()[3], "form:1")
end)

-- WoW: Forever as Classic: Shadowform is a shapeshift (form 28) with no bonus bar
-- (BonusActionBar 0 in SpellShapeshiftForm) and no stance bar, so
-- GetNumShapeshiftForms() is 0 for a priest, yet the macro conditions call it
-- form 1 ("/cast [noform:1] Shadowform" works in game).
T.test("paging: a priest's Shadowform pages bar 1 with no stance bar and no bonus bar", function()
    login({ class = "PRIEST", formSpells = {} })
    local h = holder("main")
    T.eq(h:GetAttribute("actionpage"), 1)
    stub.SetConditions({ ["form:1"] = true })
    T.eq(h:GetAttribute("actionpage"), 7, "Shadowform's page, as a druid's form 1")
    T.eq(keyPage(1), 7, "and the keys cast it")
    T.falsy(AB().Paging.Rule():find("bonusbar:1", 1, true), "never the bonus bar it doesn't get")
    stub.SetConditions({})
    T.eq(h:GetAttribute("actionpage"), 1, "out of Shadowform")
    DaylightUI:Set("ActionBars", "bars.bar5.paging.shadowform", 3)
    T.truthy(holder("bar5").__stateDriver.page:find("[form:1] 3", 1, true), "bars 2-8 can page in it too")
    DaylightUI:Set("ActionBars", "bars.main.paging.shift", 13)
    stub.SetConditions({ ["form:1"] = true, ["mod:shift"] = true })
    T.eq(h:GetAttribute("actionpage"), 13, "a held page over it")
    stub.SetConditions({})
    noBlocked()
end)

T.test("leave button: out from under the parked bar 1, beside ours, put back when the game moves it", function()
    login()
    local b = MainMenuBarVehicleLeaveButton
    T.eq(b:GetParent(), UIParent)
    local p, rel, rp, x, y = b:GetPoint(1)
    T.eq(p, "BOTTOMRIGHT"); T.eq(rel, holder("main")); T.eq(rp, "BOTTOMLEFT")
    T.eq(x, -AB().Park.LEAVE_GAP); T.eq(y, 0)
    T.isnil(rawget(b, "SetPoint"), "no hook on its SetPoint (Edit Mode's protected code calls it)")
    b:ClearAllPoints(); b:SetPoint("CENTER", UIParent, "CENTER", 0, 0)   -- the game's Edit Mode re-anchoring it
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    stub.RunTimers()
    T.eq(b:GetNumPoints(), 1); T.eq(select(2, b:GetPoint(1)), holder("main"), "put back")
    stub.EnterCombat()
    b:ClearAllPoints(); b:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    stub.FireEvent("UNIT_ENTERED_VEHICLE", "player")
    stub.RunTimers()
    T.eq(select(2, b:GetPoint(b:GetNumPoints())), UIParent, "left alone in combat")
    stub.LeaveCombat()
    T.eq(b:GetNumPoints(), 1); T.eq(select(2, b:GetPoint(1)), holder("main"), "put back after")
    T.isnil(b.__shows, "never shown by us"); T.isnil(b.__hides, "never hidden by us")
    b:SetParent(MainActionBar)
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    T.eq(b:GetParent(), UIParent, "the game took it back: out again")
end)

T.test("leave button: its own unlock-mode handle; a moved one stays where it was put", function()
    login()
    local DUI, b = DaylightUI, MainMenuBarVehicleLeaveButton
    local key = AB().Park.LEAVE_KEY
    local e = DUI.Movers.Get(key)
    T.truthy(e and e.proxy, "a proxy mover: the handle stands in, the button is placed by us")
    T.truthy(e.home, "never moved: the handle sits beside bar 1")
    DUI.DB.Positions()[key] = { 120, -80 }
    e.onMoved(key)
    local p, rel, _, x, y = b:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(rel, UIParent); T.eq(x, 120); T.eq(y, -80)
    b:ClearAllPoints(); b:SetPoint("BOTTOMRIGHT", holder("main"), "BOTTOMLEFT", -4, 0)  -- Edit Mode re-anchoring it
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    stub.RunTimers()
    T.eq(b:GetNumPoints(), 1); T.eq(select(2, b:GetPoint(1)), UIParent, "kept where it was put, not snapped to bar 1")
    DUI.Movers.Reset(key)
    T.eq(select(2, b:GetPoint(1)), holder("main"), "a reset puts it beside bar 1 again")
    T.isnil(b.__shows, "never shown by us"); T.isnil(b.__hides, "never hidden by us")
end)

T.test("leave button: the game showing it (a vehicle, a flight) doesn't leave it at its Edit Mode spot", function()
    login()
    local b = MainMenuBarVehicleLeaveButton
    b.__shown = false
    b:__gameShow()
    T.eq(b:GetNumPoints(), 1); T.eq(select(2, b:GetPoint(1)), holder("main"), "beside bar 1 at once, no frame at the game's spot")
    b.__shown = false
    DaylightUI.DB.Positions()[AB().Park.LEAVE_KEY] = { 120, -80 }
    b:__gameShow()
    local _, rel, _, x, y = b:GetPoint(1)
    T.eq(rel, UIParent); T.eq(x, 120); T.eq(y, -80)
    T.isnil(b.__shows, "never shown by us")
end)

T.test("leave button: leaves the game's bottom-bar stack (any bar showing or hiding took it off our spot, no event said so)", function()
    login({ login = false })
    local EM = DaylightUI.EditMode
    local parts, add = {}, EM.Add
    EM.Add = function(key, fill, current) parts[key] = { fill = fill, current = current }; return add(key, fill, current) end
    stub.FireEvent("PLAYER_LOGIN")
    EM.Add = add
    local b, part = MainMenuBarVehicleLeaveButton, parts.leave
    T.truthy(part, "a part of our Edit Mode layout")
    local e = { system = 9, settings = {}, isInDefaultPosition = true,
                anchorInfo = { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = 0, offsetY = 40 } }
    local layout = { systems = { e } }
    T.eq(part.current(layout), false, "at the game's default: out of date")
    b.__shown = false
    b:__gameShow()
    b:__gameStack()
    T.eq(select(2, b:GetPoint(1)), UIParent, "at its default the game takes it, with nothing telling us")
    part.fill(layout)
    T.eq(e.isInDefaultPosition, false, "off its default, the game no longer stacks it")
    T.eq(e.anchorInfo.point, "BOTTOM"); T.eq(e.anchorInfo.offsetY, 40)
    T.eq(part.current(layout), true)
    e.anchorInfo.offsetX = 5
    part.fill(layout)
    T.eq(e.anchorInfo.offsetX, 5, "a spot picked in Edit Mode stays")
    b.systemInfo = e                    -- the reload puts the layout in place
    AB().Park.PlaceLeave()
    b:__gameStack()
    T.eq(b:GetNumPoints(), 1); T.eq(select(2, b:GetPoint(1)), holder("main"), "ours stays")
end)

T.test("leave button: dressed like bar 1's buttons, the game's wooden art gone", function()
    login()
    local b = MainMenuBarVehicleLeaveButton
    T.truthy(AB().Skin.IsSkinned(b), "our shell and border")
    T.eq(b:GetNormalTexture():GetAlpha(), 0, "the wood is gone")
    T.truthy(AB().Skin.IconOf(b):GetTexture():find("ui-leave.png", 1, true), "our own arrow")
    T.isnil(rawget(b, "icon"), "nothing written on the game's button (/dui taint)")
    T.truthy(b:GetHighlightTexture().__color, "the look's hover wash")
    T.truthy(b:GetPushedTexture().__color, "the look's press")
    b:GetNormalTexture():SetAlpha(1)    -- the game redrawing its art
    AB().Skin.Tick(1)
    T.eq(b:GetNormalTexture():GetAlpha(), 0, "the wood goes again")
    T.isnil(b.__shows, "never shown by us"); T.isnil(b.__hides, "never hidden by us")
end)

T.test("leave button: a click on a flight keeps the look's highlight (the game swaps it for its own)", function()
    login()
    local b = MainMenuBarVehicleLeaveButton
    b:GetScript("OnClick")(b)
    T.truthy(b:GetHighlightTexture().__color, "ours again after the game's")
    b:GetHighlightTexture().__color = nil
    b.__shown = false
    b:__gameShow()
    T.truthy(b:GetHighlightTexture().__color, "and as it shows")
end)

T.test("leave button: dragged in unlock mode, it lands there and stays", function()
    login()
    local DUI, b = DaylightUI, MainMenuBarVehicleLeaveButton
    local key = AB().Park.LEAVE_KEY
    DUI.Movers.Unlock()
    local h = DUI.Movers.Handle(key)
    T.truthy(h and h:IsShown(), "a handle, with the button hidden")
    h:ClearAllPoints(); h:SetPoint("CENTER", UIParent, "CENTER", 200, 100)
    h.__center = { UIParent:GetWidth() / 2 + 200, UIParent:GetHeight() / 2 + 100 }
    h:GetScript("OnDragStop")(h)
    DUI.Movers.Lock()
    local saved = DUI.DB.Positions()[key]
    T.truthy(saved, "saved")
    T.eq(select(2, b:GetPoint(1)), UIParent, "the button went with it")
    b.__shown = false
    b:__gameShow()
    T.eq(select(2, b:GetPoint(1)), UIParent, "a vehicle later, still there")
    DUI.Movers.Reset(key)
end)

T.test("leave button: a burst of vehicle events (every unit in a raid) re-places it once", function()
    login()
    stub.RunTimers()
    local n = 0
    local real = C_Timer.After
    C_Timer.After = function(d, fn) n = n + 1; return real(d, fn) end
    for i = 1, 20 do stub.FireEvent("UNIT_ENTERED_VEHICLE", "raid" .. i) end
    C_Timer.After = real
    T.eq(n, 1, "one timer, not one per event")
    stub.RunTimers()
end)

T.test("bars: a /reload in combat builds the same way: placed, paged, no blocked action", function()
    login({ login = false })
    stub.combat = true          -- the game puts combat lockdown back after the files load
    stub.SetConditions({ ["bonusbar:1"] = true })
    stub.FireEvent("PLAYER_LOGIN")
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    T.eq(holder("main"):GetPoint(1), "BOTTOM", "placed")
    T.eq(btn("main", 1):GetAttribute("action"), 73, "paged: the driver runs in combat")
    noBlocked()
    stub.LeaveCombat()
    noBlocked()
end)

T.test("/dui bars: the engine, bar 1's page against the game's pick, and every bar", function()
    login()
    _G.GetActionBarPage = function() return 1 end
    _G.GetBonusBarOffset = function() return stub.bonus or 0 end
    stub.bonus = 0
    stub.chat = {}
    DaylightUI.RunCommand("bars")
    T.truthy(stub.ChatContains("MATCH"))
    T.falsy(stub.ChatContains("MISMATCH"))
    T.truthy(stub.ChatContains("Action Bar 2: shown, 12 buttons, button 1 slot 61"))
    T.truthy(stub.ChatContains("possessbar=no"))
    stub.bonus = 3
    stub.SetConditions({ ["bonusbar:3"] = true })
    stub.chat = {}
    DaylightUI.RunCommand("bars")
    T.truthy(stub.ChatContains("page 9")); T.falsy(stub.ChatContains("MISMATCH"), "a form: still a match")
    stub.bonus = 0
    stub.SetConditions({ ["bar:2"] = true })
    stub.chat = {}
    DaylightUI.RunCommand("bars")
    T.truthy(stub.ChatContains("MISMATCH"), "ours says 2, the game's page says 1")
end)

T.test("paint: icon, count and macro name come from the slot", function()
    login({ slots = { [1] = { texture = "fireball", count = 5, text = "Boom" } } })
    local b1 = btn("main", 1)
    T.eq(b1.icon.__texture, "fireball"); T.truthy(b1.icon:IsShown())
    T.eq(b1.Count:GetText(), "5"); T.eq(b1.Name:GetText(), "Boom")
    local b2 = btn("main", 2)
    T.isnil(b2.icon.__texture); T.falsy(b2.icon:IsShown(), "empty: no icon")
    T.eq(b2.Count:GetText(), ""); T.eq(b2.Name:GetText(), "")
end)

T.test("paint: an emptied slot drops its count, though the game still answers with the old one", function()
    login({ slots = { [11] = { texture = "potion", count = 7, item = 1 } } })
    T.eq(btn("main", 11).Count:GetText(), "7")
    stub.slots[11] = nil
    local get = C_ActionBar.GetActionDisplayCount
    C_ActionBar.GetActionDisplayCount = function(slot) if slot == 11 then return "7" end return get(slot) end
    stub.FireEvent("ACTIONBAR_SLOT_CHANGED", 11)
    stub.FireEvent("BAG_UPDATE_DELAYED")
    T.eq(btn("main", 11).Count:GetText(), "", "an empty slot shows no count")
end)

T.test("paint: a slot change repaints that slot; slot 0 repaints all", function()
    login()
    stub.slots[5] = { texture = "new" }
    stub.FireEvent("ACTIONBAR_SLOT_CHANGED", 5)
    T.eq(btn("main", 5).icon.__texture, "new")
    stub.slots[6] = { texture = "six" }; stub.slots[62] = { texture = "bar2" }
    stub.FireEvent("ACTIONBAR_SLOT_CHANGED", 0)
    T.eq(btn("main", 6).icon.__texture, "six"); T.eq(btn("bar2", 2).icon.__texture, "bar2")
end)

T.test("paint: an active spell is checked; auto attack blinks", function()
    login({ slots = { [1] = { texture = "a", current = true, attack = true }, [2] = { texture = "b" } } })
    T.truthy(btn("main", 1):GetChecked()); T.falsy(btn("main", 2):GetChecked())
    local frame = AB().Buttons.frame
    stub.RunOnUpdate(frame, 0.5)
    local first = btn("main", 1).Flash:IsShown()
    stub.RunOnUpdate(frame, 0.5)
    T.truthy(btn("main", 1).Flash:IsShown() ~= first, "it blinks")
    T.falsy(btn("main", 2).Flash:IsShown())
    stub.slots[1].current = false
    stub.FireEvent("ACTIONBAR_UPDATE_STATE"); stub.RunTimers()
    T.falsy(btn("main", 1):GetChecked()); T.falsy(btn("main", 1).Flash:IsShown(), "stopped")
end)

T.test("paint: a queued spell lights its border and glow when asked, attacks don't", function()
    local DUI = login({ slots = { [1] = { texture = "hs", current = true }, [2] = { texture = "atk", current = true, attack = true },
        [3] = { texture = "c" } } })
    local Skin, Fx = stub.actionbars.Skin, stub.actionbars.CdmEffects
    local hs, atk = btn("main", 1), btn("main", 2)
    local parts = Skin.GetParts(hs)
    T.truthy(parts.color ~= Skin.STATE.lit, "off by default")
    T.falsy(Fx.GlowShown(hs))
    DUI:Set("ActionBars", "look.checkedBorder", true)
    DUI:Set("ActionBars", "look.checkedGlow", true)
    stub.RunTimers()
    parts = Skin.GetParts(hs)
    T.eq(parts.color, Skin.STATE.lit, "lit in the accent, like a stance")
    T.truthy(Fx.GlowShown(hs), "glow")
    T.truthy(Skin.GetParts(atk).color ~= Skin.STATE.lit, "auto attack keeps its blink only")
    T.falsy(Fx.GlowShown(atk))
    DUI:Set("ActionBars", "look.checkedBorderMode", "custom")
    DUI:Set("ActionBars", "look.checkedBorderColor", { 0, 1, 0 })
    stub.RunTimers()
    parts = Skin.GetParts(hs)
    T.eq(parts.color[2], 1, "your own color")
    stub.slots[1].current = false       -- the swing landed
    stub.FireEvent("ACTIONBAR_UPDATE_STATE"); stub.RunTimers()
    parts = Skin.GetParts(hs)
    T.truthy(parts.color ~= parts.activeLit, "back to rest")
    T.falsy(Fx.GlowShown(hs))
    T.falsy(hs:GetChecked())
end)

T.test("paint: an equipped item's border", function()
    login({ slots = { [4] = { texture = "trinket", equipped = true }, [3] = { texture = "c" } } })
    T.truthy(btn("main", 4).Border:IsShown()); T.falsy(btn("main", 3).Border:IsShown())
end)

T.test("paint: paging repaints the buttons the frame after", function()
    login({ slots = { [1] = { texture = "caster" }, [73] = { texture = "bear" } } })
    stub.SetConditions({ ["bonusbar:1"] = true })
    stub.RunTimers()
    T.eq(btn("main", 1).icon.__texture, "bear")
    stub.SetConditions({})
    stub.RunTimers()
    T.eq(btn("main", 1).icon.__texture, "caster")
end)

T.test("paint: something on the cursor shows the empty slots", function()
    login()
    local Skin = AB().Skin
    T.eq(Skin.GetParts(btn("main", 5)).back:GetAlpha(), 0)
    local function run(frames)
        local d = DaylightUI.Motion.Driver()
        for _ = 1, frames do if d then stub.RunOnUpdate(d, 1 / 60) end end
    end
    stub.cursor = "spell"
    stub.FireEvent("CURSOR_CHANGED")
    run(3)
    local mid = Skin.GetParts(btn("main", 5)).back:GetAlpha()
    T.truthy(mid > 0 and mid < 1, "fading in (FAST)")
    run(30)
    T.eq(Skin.GetParts(btn("main", 5)).back:GetAlpha(), 1, "somewhere to drop it")
    stub.cursor = nil
    stub.FireEvent("CURSOR_CHANGED")
    run(30)
    T.eq(Skin.GetParts(btn("main", 5)).back:GetAlpha(), 0)
end)

T.test("paint: cooldowns go through duration objects; loss of control replaces the normal one", function()
    login({ slots = { [1] = { texture = "a", cooldown = true }, [2] = { texture = "b", charges = true },
                      [3] = { texture = "c", cooldown = true, loc = true, locReplaces = true } } })
    local b1, b2, b3 = btn("main", 1), btn("main", 2), btn("main", 3)
    T.deq(b1.cooldown.__duration, { slot = 1, kind = "cooldown" })
    T.isnil(b2.cooldown.__duration); T.deq(b2.chargeCooldown.__duration, { slot = 2, kind = "charges" })
    T.isnil(b3.cooldown.__duration, "loss of control replaces it")
    T.deq(b3.lossOfControlCooldown.__duration, { slot = 3, kind = "loc" })
    stub.slots[1].cooldown = false
    stub.FireEvent("SPELL_UPDATE_COOLDOWN"); stub.RunTimers()
    T.isnil(b1.cooldown.__duration, "cleared when it ends")
end)

T.test("paint: painting in combat never touches a secret", function()
    login({ slots = { [1] = { texture = "a", count = 3 }, [2] = { texture = "b" } } })
    local before = #stub.errors
    stub.EnterCombat()
    stub.slots[2].cooldown = true; stub.slots[2].charges = true; stub.slots[2].loc = true
    T.noerror(function()
        stub.FireEvent("ACTIONBAR_UPDATE_COOLDOWN")
        stub.FireEvent("SPELL_UPDATE_CHARGES")
        stub.FireEvent("LOSS_OF_CONTROL_UPDATE")
        stub.FireEvent("ACTIONBAR_SLOT_CHANGED", 0)
    end)
    T.truthy(issecretvalue(btn("main", 1).Count:GetText()), "the count went to the engine whole")
    T.truthy(btn("main", 2).cooldown.__duration or btn("main", 2).lossOfControlCooldown.__duration)
    T.eq(#stub.errors, before, table.concat(stub.errors, "\n"))
    noBlocked()
end)

-- The ready ping. bumps[icon] counts icon pops.
local function watchPings(DUI)
    local bumps, real = {}, DUI.Motion.Bump
    DUI.Motion.Bump = function(region, ...)
        bumps[region] = (bumps[region] or 0) + 1
        return real(region, ...)
    end
    return bumps
end
local function done(cd) cd:GetScript("OnCooldownDone")(cd) end
-- Painter events paint once, the frame after (Buttons.QueuePaint).
local function cooldowns() stub.FireEvent("SPELL_UPDATE_COOLDOWN"); stub.RunTimers() end

T.test("paint: cooldown events in one frame repaint the buttons once, the frame after", function()
    login({ slots = { [1] = { texture = "a", cooldown = true } } })
    stub.RunTimers()   -- whatever login left for the frame after
    local asked, real = 0, C_ActionBar.GetActionCooldown
    C_ActionBar.GetActionCooldown = function(...) asked = asked + 1; return real(...) end
    stub.FireEvent("SPELL_UPDATE_COOLDOWN")
    stub.FireEvent("ACTIONBAR_UPDATE_COOLDOWN")
    stub.FireEvent("SPELL_UPDATE_CHARGES")
    T.eq(asked, 0, "not yet: gathered")
    stub.RunTimers()
    local once = asked
    T.truthy(once > 0, "painted")
    stub.FireEvent("SPELL_UPDATE_COOLDOWN"); stub.RunTimers()
    T.eq(asked - once, once, "one event, one paint: the three above were one paint too")
    C_ActionBar.GetActionCooldown = real
end)

-- Bars 5-8 start hidden, half of the 96 buttons. Cooldown and usable events
-- (several a second in a fight) only paint what's on screen, and a hidden bar
-- catches up when it shows.
T.test("paint: a hidden bar's buttons skip the event paints and catch up when it shows", function()
    login({ slots = { [1] = { texture = "a", cooldown = true }, [37] = { texture = "b", cooldown = true } } })
    stub.RunTimers()
    holder("bar5"):Hide()
    T.falsy(btn("bar5", 1):IsVisible(), "a hidden bar")
    local asked, real = {}, C_ActionBar.GetActionCooldown
    C_ActionBar.GetActionCooldown = function(slot, ...) asked[slot] = (asked[slot] or 0) + 1; return real(slot, ...) end
    cooldowns()
    T.truthy((asked[1] or 0) > 0, "a shown bar paints")
    T.isnil(asked[37], "a hidden one doesn't")
    holder("bar5"):Show(); stub.RunTimers()
    T.truthy((asked[37] or 0) > 0, "shown: painted the frame after")
    C_ActionBar.GetActionCooldown = real
end)

-- A page, form or vehicle change repaints everything, but still only what's on
-- screen. Hidden bars catch up when they show.
T.test("paint: a page change paints only shown buttons; a hidden bar catches up when it shows", function()
    login({ slots = { [1] = { texture = "a", cooldown = true }, [37] = { texture = "b", cooldown = true } } })
    stub.RunTimers()
    holder("bar5"):Hide()
    local asked, real = {}, C_ActionBar.GetActionCooldown
    C_ActionBar.GetActionCooldown = function(slot, ...) asked[slot] = (asked[slot] or 0) + 1; return real(slot, ...) end
    stub.FireEvent("UPDATE_SHAPESHIFT_FORM"); stub.FireEvent("ACTIONBAR_PAGE_CHANGED"); stub.RunTimers()
    T.truthy((asked[1] or 0) > 0, "a shown bar paints")
    T.isnil(asked[37], "a hidden one doesn't")
    holder("bar5"):Show(); stub.RunTimers()
    T.truthy((asked[37] or 0) > 0, "shown: painted the frame after")
    C_ActionBar.GetActionCooldown = real
end)

T.test("ready ping: a real cooldown pings once when done, even after a GCD paint; a GCD never", function()
    local DUI = login({ slots = { [1] = { texture = "a", spellID = 11 }, [2] = { texture = "b", spellID = 12 } } })
    local bumps = watchPings(DUI)
    local b1, b2 = btn("main", 1), btn("main", 2)
    local before = #stub.errors
    stub.EnterCombat()
    stub.slots[1].cooldown, stub.slots[2].cooldown = true, true
    stub.spellCooldowns[11], stub.spellCooldowns[12] = "gcd", "gcd"
    cooldowns()
    stub.spellCooldowns[11] = "real"     -- the real one shows after the GCD
    cooldowns()
    stub.spellCooldowns[11] = "gcd"      -- a GCD from another cast on top
    cooldowns()
    done(b1.cooldown); done(b2.cooldown)
    T.eq(bumps[b1.icon], 1, "the real one pinged")
    T.isnil(bumps[b2.icon], "GCD only: no ping")
    local flash = AB().Buttons.State(b1).pingFlash
    T.truthy(flash:IsShown(), "the flash shows")
    T.eq(flash:GetParent(), b1)
    T.eq(flash.__texture, "a", "the icon's own picture")
    T.eq(flash:GetBlendMode(), "ADD", "added on top, not a flat cover")
    T.eq(bumps[flash], 1, "pops with the icon")
    stub.slots[1].cooldown = false; stub.spellCooldowns[11] = nil
    cooldowns(); done(b1.cooldown)
    T.eq(bumps[b1.icon], 1, "once")
    T.eq(#stub.errors, before, table.concat(stub.errors, "\n"))
end)

T.test("login wave: the shown bars' buttons light up in turn at the login reveal; empty slots, hidden bars and a fight don't", function()
    local DUI = login({ slots = { [1] = { texture = "a", spellID = 11 }, [37] = { texture = "b", spellID = 12 } } })
    stub.RunTimers()
    holder("bar5"):Hide()
    local bumps = watchPings(DUI)
    DUI.Fire("LoginReveal")
    T.isnil(bumps[btn("main", 1).icon], "not at once: when the ripple gets there")
    stub.RunTimers()
    T.eq(bumps[btn("main", 1).icon], 1, "a filled slot lights up once")
    T.eq(bumps[AB().Buttons.State(btn("main", 1)).pingFlash], 1, "with its flash")
    T.isnil(bumps[btn("main", 2).icon], "an empty slot stays dark")
    T.isnil(bumps[btn("bar5", 1).icon], "a hidden bar: nothing")

    DUI = login({ slots = { [1] = { texture = "a", spellID = 11 } } })
    stub.RunTimers()
    bumps = watchPings(DUI)
    DUI.Fire("LoginReveal")
    stub.EnterCombat()
    stub.RunTimers()
    T.isnil(bumps[btn("main", 1).icon], "a fight started: fight info first")
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("look: gray out and fade on a real cooldown, in combat, never on the GCD", function()
    local DUI = login({ slots = { [1] = { texture = "a", spellID = 11 }, [2] = { texture = "b", spellID = 12 } } })
    DUI:Set("ActionBars", "look.cdGray", true)
    DUI:Set("ActionBars", "look.cdAlpha", 0.5)
    stub.RunTimers()
    local b1, b2 = btn("main", 1), btn("main", 2)
    local before = #stub.errors
    stub.EnterCombat()
    stub.slots[1].cooldown, stub.slots[2].cooldown = true, true
    stub.spellCooldowns[11], stub.spellCooldowns[12] = "real", "gcd"
    cooldowns()
    local d = DUI.Motion.Driver()
    for _ = 1, 30 do if d and d:GetScript("OnUpdate") then stub.RunOnUpdate(d, 1 / 30) end end
    T.eq(b1.icon:GetDesaturation(), 1, "gray on a real cooldown")
    T.near(b1.icon:GetAlpha(), 0.5, 1e-6, "and faded")
    T.eq(b2.icon:GetDesaturation(), 0, "the GCD: not gray")
    T.eq(b2.icon:GetAlpha(), 1, "nor faded")
    done(b1.cooldown)
    for _ = 1, 30 do if d and d:GetScript("OnUpdate") then stub.RunOnUpdate(d, 1 / 30) end end
    T.eq(b1.icon:GetDesaturation(), 0, "ready: colored again")
    T.eq(b1.icon:GetAlpha(), 1)
    T.eq(#stub.errors, before, table.concat(stub.errors, "\n"))
    noBlocked()
end)

T.test("ready ping: a paint that finds it ready pings (a reset); Done after adds none", function()
    local DUI = login({ slots = { [1] = { texture = "a", spellID = 11, cooldown = true } } })
    local bumps = watchPings(DUI)
    stub.spellCooldowns[11] = "real"
    cooldowns()
    stub.slots[1].cooldown = false; stub.spellCooldowns[11] = nil
    cooldowns()
    T.eq(bumps[btn("main", 1).icon], 1)
    done(btn("main", 1).cooldown)
    T.eq(bumps[btn("main", 1).icon], 1)
end)

T.test("ready ping: none while loss of control hides a running cooldown, nor for a new slot", function()
    local DUI = login({ slots = { [1] = { texture = "a", spellID = 11, cooldown = true },
                                  [2] = { texture = "b", spellID = 12, cooldown = true } } })
    local bumps = watchPings(DUI)
    stub.spellCooldowns[11], stub.spellCooldowns[12] = "real", "real"
    cooldowns()
    stub.slots[1].loc, stub.slots[1].locReplaces = true, true
    cooldowns()
    T.isnil(bumps[btn("main", 1).icon], "still on cooldown under the stun")
    local b2 = btn("main", 2)
    b2:SetAttribute("action", 14)        -- a page change, so an empty slot now
    AB().Buttons.Paint(b2)
    done(b2.cooldown)
    T.isnil(bumps[b2.icon], "the old slot's cooldown isn't this one's")
end)

T.test("ready ping: an idle sweep's Done and charges", function()
    local DUI = login({ slots = { [1] = { texture = "a", spellID = 11 }, [2] = { texture = "b", spellID = 12 } } })
    local bumps = watchPings(DUI)
    local b1, b2 = btn("main", 1), btn("main", 2)
    done(b1.cooldown); done(b1.chargeCooldown)
    T.isnil(bumps[b1.icon], "nothing was running")
    stub.slots[2].charges = true
    cooldowns()
    stub.slots[2].charges = false
    done(b2.chargeCooldown)
    T.eq(bumps[b2.icon], 1, "a charge came back")
    done(b2.chargeCooldown)
    T.eq(bumps[b2.icon], 1)
end)

T.test("ready ping: off with actionbars.readyPing", function()
    local DUI = login({ slots = { [1] = { texture = "a", spellID = 11, cooldown = true } } })
    local bumps = watchPings(DUI)
    T.eq(AB().db.readyPing, true, "on by default")
    DUI:Set("ActionBars", "readyPing", false)
    stub.spellCooldowns[11] = "real"
    cooldowns()
    done(btn("main", 1).cooldown)
    T.isnil(bumps[btn("main", 1).icon])
end)

-- A wand shot puts every spell on a cooldown as long as the wand's speed, which the
-- game doesn't flag as the GCD, so every icon pinged in game.
local function wand(speed)
    C_Spell.IsAutoRepeatSpell = function(id) return id == 5019 or id == 75 end
    _G.UnitRangedDamage = function() return speed end
end
local function shot(id) stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", id or 5019) end

T.test("ready ping: a wand shot's lockout on every button pings none", function()
    local DUI = login({ slots = { [1] = { texture = "a", spellID = 11 }, [2] = { texture = "b", spellID = 12 } } })
    wand(1.8)
    local bumps = watchPings(DUI)
    local b1, b2 = btn("main", 1), btn("main", 2)
    stub.EnterCombat()
    shot()
    stub.slots[1].cooldown, stub.slots[2].cooldown = true, true
    stub.spellCooldowns[11], stub.spellCooldowns[12] = "real", "real"   -- not flagged GCD
    cooldowns()
    stub.now = (stub.now or 0) + 2.2
    stub.slots[1].cooldown, stub.slots[2].cooldown = false, false
    stub.spellCooldowns[11], stub.spellCooldowns[12] = nil, nil
    cooldowns(); done(b1.cooldown); done(b2.cooldown)
    T.isnil(bumps[b1.icon]); T.isnil(bumps[b2.icon])
    _G.UnitRangedDamage = nil
end)

T.test("ready ping: a real cooldown started under a wand lockout still pings; Auto Shot locks nothing", function()
    local DUI = login({ slots = { [1] = { texture = "a", spellID = 11 }, [2] = { texture = "b", spellID = 12 } } })
    wand(nil)                            -- speed unreadable, so the long hold
    local bumps = watchPings(DUI)
    local b1, b2 = btn("main", 1), btn("main", 2)
    shot()
    stub.slots[1].cooldown = true
    stub.spellCooldowns[11] = "real"
    cooldowns()
    T.isnil(bumps[b1.icon])
    stub.now = (stub.now or 0) + AB().Ping.LOCK_UNKNOWN + 0.1
    cooldowns()                          -- the repaint as the lockout ends: still running means real
    stub.slots[1].cooldown, stub.spellCooldowns[11] = false, nil
    cooldowns(); done(b1.cooldown)
    T.eq(bumps[b1.icon], 1, "pinged once when its own cooldown ended")
    shot(75)                             -- a hunter's Auto Shot
    stub.slots[2].cooldown, stub.spellCooldowns[12] = true, "real"
    cooldowns()
    stub.slots[2].cooldown, stub.spellCooldowns[12] = false, nil
    cooldowns(); done(b2.cooldown)
    T.eq(bumps[b2.icon], 1, "Auto Shot isn't a lockout")
    _G.UnitRangedDamage = nil
end)

T.test("ready ping: items use the action's own GCD flag (out of combat)", function()
    local DUI = login({ slots = { [1] = { texture = "a", item = 5, cooldown = true, gcd = true },
                                  [2] = { texture = "b", item = 6, cooldown = true } } })
    local bumps = watchPings(DUI)
    cooldowns()
    done(btn("main", 1).cooldown); done(btn("main", 2).cooldown)
    T.isnil(bumps[btn("main", 1).icon], "GCD")
    T.eq(bumps[btn("main", 2).icon], 1, "its own cooldown")
end)

T.test("paint: an empty slot filled in combat shows at once, by alpha", function()
    login()
    local Skin = AB().Skin
    local b = btn("main", 5)
    T.eq(Skin.GetParts(b).back:GetAlpha(), 0)
    stub.EnterCombat()
    stub.slots[5] = { texture = "dropped" }
    stub.FireEvent("ACTIONBAR_SLOT_CHANGED", 5)
    T.eq(b.icon.__texture, "dropped")
    stub.RunTimers()   -- the skin's pass, the frame after (one per burst)
    -- The icon at once, and its backing starts easing in at once (FAST), by alpha.
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 1 / 60)
    T.truthy(Skin.GetParts(b).back:GetAlpha() > 0, "the backing on its way in at once")
    settle()
    T.eq(Skin.GetParts(b).back:GetAlpha(), 1)
    noBlocked()
end)

T.test("paint: can't be used grays the icon; short of power fades it (skinned)", function()
    login({ slots = { [1] = { texture = "a", usable = false }, [2] = { texture = "b", noMana = true }, [3] = { texture = "c" } } })
    local Skin = AB().Skin
    local p1, p2, p3 = Skin.GetParts(btn("main", 1)), Skin.GetParts(btn("main", 2)), Skin.GetParts(btn("main", 3))
    settle()
    T.truthy(p1.unusable); T.near(btn("main", 1).icon.__vertex[1], 0.4)
    T.truthy(p2.noPower); T.eq(btn("main", 2).icon:GetAlpha(), Skin.OUT_OF_RANGE)
    T.falsy(p3.unusable); T.falsy(p3.noPower); T.eq(btn("main", 3).icon:GetAlpha(), 1)
    stub.slots[1].usable = nil
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    settle()
    T.falsy(p1.unusable); T.near(btn("main", 1).icon.__vertex[1], 1, nil, "back to full color")
    T.falsy(Skin.GetParts(btn("main", 4)) and Skin.GetParts(btn("main", 4)).unusable, "an empty slot isn't grayed")
end)

T.test("paint: out of range fades (skinned); range checks are left to the game's twins", function()
    login({ slots = { [1] = { texture = "a" } } })
    stub.FireEvent("ACTION_RANGE_CHECK_UPDATE", 1, false, true)
    T.truthy(AB().Skin.GetParts(btn("main", 1)).outOfRange)
    settle()
    T.eq(btn("main", 1).icon:GetAlpha(), AB().Skin.OUT_OF_RANGE)
    stub.FireEvent("ACTION_RANGE_CHECK_UPDATE", 1, true, true)
    T.falsy(AB().Skin.GetParts(btn("main", 1)).outOfRange)
end)

-- The game's twin buttons are hidden, and a hidden twin switches its slot's range
-- check off (OnHide / UpdateAction's IsVisible in ActionButton.lua), so no
-- ACTION_RANGE_CHECK_UPDATE comes. Walking up to a mob left the buttons out of
-- range until a cast or a hover.
T.test("range: walking into range lights the buttons up with no event", function()
    login({ slots = { [1] = { texture = "a", inRange = false } } })
    local U = stub.units or {}
    U.target = { name = "Mob", reaction = 2 }
    stub.SetUnits(U)
    stub.FireEvent("PLAYER_TARGET_CHANGED"); stub.RunTimers()
    T.truthy(AB().Buttons.State(btn("main", 1)).outOfRange, "out of range at first")
    stub.slots[1].inRange = true            -- walked up, and the client sends nothing
    local f = AB().Buttons.rangeFrame
    T.truthy(f and f:GetScript("OnUpdate"), "range is watched while there's a target")
    stub.RunOnUpdate(f, AB().Buttons.RANGE_EVERY)
    T.falsy(AB().Buttons.State(btn("main", 1)).outOfRange, "in range, no cast or hover needed")
    U.target = nil
    stub.FireEvent("PLAYER_TARGET_CHANGED"); stub.RunTimers()
    T.isnil(f:GetScript("OnUpdate"), "no target: nothing runs")
end)

T.test("paint: a proc shows the game's glow on our button, and our border", function()
    login({ slots = { [3] = { texture = "c", spellID = 100 }, [5] = { texture = "m", macro = 7 } } })
    stub.macroSpells[7] = 200
    local b = btn("main", 3)
    stub.overlay[100] = true
    stub.FireEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 100); stub.RunTimers()
    T.truthy(rawget(b, "SpellActivationAlert") and b.SpellActivationAlert:IsShown(), "the game's glow")
    T.truthy(AB().Skin.GetParts(b).proc, "our border")
    stub.overlay[100] = nil
    stub.FireEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 100); stub.RunTimers()
    T.falsy(b.SpellActivationAlert:IsShown())
    stub.overlay[200] = true
    stub.FireEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 200); stub.RunTimers()
    T.truthy(rawget(btn("main", 5), "SpellActivationAlert"), "a macro's spell procs too")
end)

T.test("bars: no bare nil comparisons in the painting and key code", function()
    for _, path in ipairs({ "DaylightUI_ActionBars/Buttons.lua", "DaylightUI_ActionBars/Keys.lua" }) do
        local fh = io.open(path)
        if fh then
            fh:close()
            local i = 0
            for line in io.lines(path) do
                i = i + 1
                T.falsy(string.find(line, "== nil", 1, true) or string.find(line, "~= nil", 1, true),
                    path .. ":" .. i .. ": " .. line)
            end
        end
    end
end)

-- The keybind a button shows: the skin's own label (the game's text is hidden).
local function keyText(b)
    stub.RunTimers()
    return AB().Skin.GetParts(b).key:GetText()
end

local BINDINGS = { ACTIONBUTTON1 = { "1" }, MULTIACTIONBAR1BUTTON2 = { "SHIFT-2" }, ACTIONBUTTON4 = { "4", "F" } }

T.test("keys: each button shows its keybind; a change of bindings follows", function()
    login({ bindings = BINDINGS })
    T.eq(keyText(btn("main", 1)), "1")
    T.eq(keyText(btn("bar2", 2)), "S2", "short by default")
    T.eq(keyText(btn("main", 3)), "", "unbound: blank (the skin drops the game's dot)")
    stub.bindings.ACTIONBUTTON3 = { "3" }
    stub.FireEvent("UPDATE_BINDINGS")
    T.eq(keyText(btn("main", 3)), "3")
    DaylightUI:Set("ActionBars", "look.shortKeys", false)
    stub.FireEvent("UPDATE_BINDINGS")
    T.eq(keyText(btn("bar2", 2)), "SHIFT-2", "switched off: the full key")
    T.isnil(next(stub.overrides), "no override bindings for normal slots")
end)

-- A whole skin refresh (a bindings change, a slot change, a form) only redoes
-- buttons on screen. A hidden bar's catch up when it shows.
T.test("keys: a bindings change redoes only shown buttons, a hidden bar's when it shows", function()
    login({ bindings = BINDINGS })
    stub.RunTimers()
    holder("bar5"):Hide()
    local Skin = AB().Skin
    local redone, real = {}, Skin.UpdateEmpty
    Skin.UpdateEmpty = function(b, ...) redone[b] = true; return real(b, ...) end
    stub.bindings.MULTIACTIONBAR4BUTTON1 = { "CTRL-1" }
    stub.FireEvent("UPDATE_BINDINGS"); stub.RunTimers()
    T.truthy(redone[btn("main", 1)], "a shown button redone")
    T.isnil(redone[btn("bar5", 1)], "a hidden one not")
    holder("bar5"):Show(); stub.RunTimers()
    Skin.UpdateEmpty = real
    T.truthy(redone[btn("bar5", 1)], "shown: redone")
    T.eq(keyText(btn("bar5", 1)), "C1", "and its key caught up")
end)

T.test("keys: the keybind text is shown even if the game's template hid it", function()
    login({ bindings = BINDINGS })
    btn("main", 1).HotKey:Hide()
    stub.FireEvent("UPDATE_BINDINGS")
    T.truthy(btn("main", 1).HotKey:IsShown())
end)

T.test("keys: a key going down gives our button the pressed look, and up takes it off", function()
    login({ bindings = BINDINGS })
    local Skin = AB().Skin
    ActionButtonDown(3)
    T.truthy(Skin.GetParts(btn("main", 3)).keyDown)
    T.eq(Skin.GetParts(btn("main", 3)).press:GetAlpha(), 1)
    ActionButtonUp(3)
    T.falsy(Skin.GetParts(btn("main", 3)).keyDown)
    T.eq(Skin.GetParts(btn("main", 3)).press:GetAlpha(), 0)
    MultiActionButtonDown("MultiBarBottomLeft", 2)
    T.truthy(Skin.GetParts(btn("bar2", 2)).keyDown)
    MultiActionButtonUp("MultiBarBottomLeft", 2)
    T.falsy(Skin.GetParts(btn("bar2", 2)).keyDown)
end)

T.test("keys: a missed key up is cleared once the key isn't held", function()
    login({ bindings = BINDINGS })
    stub.keysDown = { ["1"] = true }
    ActionButtonDown(1)
    AB().Keys.Poll(1)
    T.truthy(AB().Skin.GetParts(btn("main", 1)).keyDown, "still held")
    stub.keysDown = {}
    AB().Keys.Poll(1)
    T.falsy(AB().Skin.GetParts(btn("main", 1)).keyDown, "let go: cleared")
end)

T.test("keys: a flyout slot's keys click our button; the rest stay the game's", function()
    login({ bindings = BINDINGS, slots = { [4] = { texture = "portals", flyout = 7 } } })
    local o = stub.overrides["4"]
    T.truthy(o, "key 4 is routed"); T.eq(o.click, "DaylightUIBar1Button4"); T.eq(o.button, "LeftButton")
    T.eq(stub.overrides["F"].click, "DaylightUIBar1Button4", "every key bound to it")
    T.isnil(stub.overrides["1"], "a plain slot keeps the game's binding")
    stub.slots[4] = { texture = "frostbolt", spellID = 4 }
    stub.FireEvent("ACTIONBAR_SLOT_CHANGED", 4)
    stub.RunTimers()                                       -- once the frame after a burst
    T.isnil(stub.overrides["4"], "not a flyout any more")
end)

T.test("keys: flyout keys change after combat, never in it", function()
    login({ bindings = BINDINGS })
    stub.EnterCombat()
    stub.slots[4] = { texture = "portals", flyout = 7 }
    stub.FireEvent("ACTIONBAR_SLOT_CHANGED", 4)
    stub.RunTimers()
    T.isnil(stub.overrides["4"])
    noBlocked()
    stub.LeaveCombat()
    T.eq(stub.overrides["4"].click, "DaylightUIBar1Button4")
end)

T.test("keys: a flyout opens away from the nearest screen edge", function()
    login({ ab = { bars = { right = { vertical = true } } } })
    holder("main").__center = { 960, 50 }
    holder("bar5").__center = { 960, 1000 }
    holder("right").__center = { 1800, 540 }
    AB().Keys.UpdateDirections()
    T.eq(btn("main", 1):GetAttribute("flyoutDirection"), "UP")
    T.eq(btn("bar5", 1):GetAttribute("flyoutDirection"), "DOWN")
    T.eq(btn("right", 1):GetAttribute("flyoutDirection"), "LEFT")
    holder("main").__center = { 960, 1000 }
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.RunTimers()
    T.eq(btn("main", 1):GetAttribute("flyoutDirection"), "DOWN", "again after the bars are laid out")
end)

T.test("keys: Quick Keybind mode: our buttons bind instead of casting, then cast again", function()
    login({ bindings = BINDINGS })
    local b = btn("main", 2)
    QuickKeybindFrame:Show()
    T.truthy(b.__quickMode); T.isnil(b:GetAttribute("type"), "a click doesn't cast")
    b:Click("Button4")
    T.eq(stub.quickClicks[#stub.quickClicks][1], b); T.eq(stub.quickClicks[#stub.quickClicks][2], "Button4")
    QuickKeybindFrame:Hide()
    T.falsy(b.__quickMode); T.eq(b:GetAttribute("type"), "action")
    local n = #stub.quickClicks
    b:Click("LeftButton")
    T.eq(#stub.quickClicks, n, "out of the mode, a click is a click")
    T.eq(b.commandName, "ACTIONBUTTON2", "the command Quick Keybind binds")
end)

T.test("keys: Quick Keybind lifts our bars above the game's frames, then puts them back", function()
    login({ bindings = BINDINGS })
    holder("main"):SetFrameStrata("MEDIUM")     -- the real client always has one
    holder("main"):SetFrameStrata("MEDIUM")     -- the real client always has one
    local before = holder("main"):GetFrameStrata()
    QuickKeybindFrame:Show()
    T.eq(holder("main"):GetFrameStrata(), "HIGH")
    QuickKeybindFrame:Hide()
    T.eq(holder("main"):GetFrameStrata(), before)
end)

T.test("keys: the Action Bars page's Bind keys button opens Quick Keybind, our window out of the way", function()
    login({ bindings = BINDINGS })
    local item
    for _, g in ipairs(AB().OPTIONS.pages[1].groups) do
        for _, it in ipairs(g.items) do if it.text == "Bind keys" then item = it end end
    end
    T.truthy(item, "the button is on the page")
    DaylightUI.OptionsPanel.Show("ActionBars.bars")
    T.truthy(DaylightUI.OptionsPanel.IsShown())
    item.func()
    T.truthy(QuickKeybindFrame:IsShown())
    T.falsy(DaylightUI.OptionsPanel.IsShown(), "our options step aside")
    T.truthy(btn("main", 2).__quickMode, "our buttons are in the mode")
    QuickKeybindFrame:Hide()
    stub.EnterCombat()
    T.eq(AB().Keys.OpenQuick(), false, "refused in a fight")
    T.falsy(QuickKeybindFrame:IsShown())
    stub.LeaveCombat()
end)

T.test("keys: /kb opens Quick Keybind, in a fight once it ends", function()
    login({ bindings = BINDINGS })
    T.eq(SLASH_DAYLIGHTUIKB1, "/kb")
    SlashCmdList.DAYLIGHTUIKB("")
    T.truthy(QuickKeybindFrame:IsShown())
    QuickKeybindFrame:Hide()
    stub.EnterCombat()
    SlashCmdList.DAYLIGHTUIKB("")
    T.falsy(QuickKeybindFrame:IsShown(), "never in a fight")
    stub.LeaveCombat()
    T.truthy(QuickKeybindFrame:IsShown(), "opens as the fight ends")
    QuickKeybindFrame:Hide()
end)

T.test("bars: one part failing as the files load doesn't stop the rest", function()
    stub.Load({ actionbars = true, before = function()
        ABW.newWorld({ bindings = BINDINGS })
        _G.GetActionInfo = nil       -- the flyout keys can't read a slot
    end })
    T.truthy(AB().Bars.built)
    T.eq(keyText(btn("main", 1)), "1", "keybind text still there")
    QuickKeybindFrame:Show()
    T.truthy(btn("main", 2).__quickMode, "Quick Keybind still wired")
    T.eq(holder("main"):GetPoint(1), "BOTTOM", "and the bars placed")
end)

T.test("small bars: the stance bar takes the game's buttons, as many as there are forms", function()
    login({ forms = 3 })
    local h = holder("stance")
    T.eq(h:GetName(), "DaylightUIStanceBar")
    T.eq(StanceButton1:GetParent(), h); T.eq(StanceButton3:GetParent(), h)
    T.eq(StanceButton4:GetParent(), DaylightUIParkedBars, "one past the forms: out of sight, never hidden from here")
    T.eq(StanceBar:GetParent(), DaylightUIParkedBars, "the game's bar is parked")
    T.truthy(StanceButton3:IsShown())
    T.isnil(StanceButton4:GetAttribute("statehidden"), "nothing written on the game's button")
    T.near(h:GetWidth(), 3 * 18 + 2 * 2, nil, "30-wide buttons at 60%")
    T.near(StanceButton1:GetScale(), 0.6)
    T.eq(h.__stateDriver.visibility, "[petbattle][vehicleui][overridebar] hide; show")
    T.truthy(AB().Skin.IsSkinned(StanceButton1))
    T.falsy(AB().Buttons.IsOwn(StanceButton1), "still the game's button")
end)

-- Every game button the addon borrows or hides. A Show, Hide or SetShown from addon
-- code (or a SetAttribute, which runs the button's own OnAttributeChanged and so
-- the game's Update under addon taint) leaves it so that the game's own SetShown
-- in a fight is blocked. Players saw "the game blocked StanceButton1:SetShown()"
-- and "MultiBarBottomLeftButton5:SetShown()".
local GAME_BUTTONS = { { "ActionButton", 12 }, { "MultiBarBottomLeftButton", 12 }, { "MultiBarBottomRightButton", 12 },
                       { "StanceButton", 10 }, { "PetActionButton", 10 }, { "PossessButton", 2 } }
local function watchGameButtons(touched)
    for _, spec in ipairs(GAME_BUTTONS) do
        for i = 1, spec[2] do
            local b = _G[spec[1] .. i]
            for _, m in ipairs({ "Show", "Hide", "SetShown", "SetAttribute" }) do
                local orig = b[m]
                b[m] = function(self, ...)
                    -- The state driver's secure snippet (bar 1's page on the
                    -- game's buttons) is the game's own way in, so it's allowed.
                    if (stub.inSecure or 0) == 0 then touched[#touched + 1] = self:GetName() .. ":" .. m .. "(" .. tostring((...)) .. ")" end
                    return orig(self, ...)
                end
            end
        end
    end
end

T.test("small bars and the game's hidden buttons: our code never shows, hides or sets an attribute with a handler on them", function()
    local touched = {}
    stub.Load({ actionbars = true, before = function()
        ABW.newWorld({ forms = 3, ab = { bars = { stance = { icons = 2 }, pet = { icons = 6 } } } })
        watchGameButtons(touched)
    end })
    DaylightUI:Set("ActionBars", "bars.stance.icons", 3)
    DaylightUI:Set("ActionBars", "bars.stance.icons", 1)
    stub.forms = 4
    stub.FireEvent("UPDATE_SHAPESHIFT_FORMS")
    stub.RunTimers()
    T.eq(#touched, 0, table.concat(touched, ", "))
    -- Still hidden where the bar has no room for them, still in place where it has.
    T.eq(StanceButton2:GetParent(), DaylightUIParkedBars, "past the Buttons setting: out of sight")
    T.isnil(StanceButton2:GetAttribute("statehidden"), "nothing written on it")
    T.eq(StanceButton1:GetParent(), holder("stance")); T.truthy(StanceButton1:IsShown())
    T.isnil(StanceButton1:GetAttribute("statehidden"))
    T.eq(PetActionButton7:GetParent(), DaylightUIParkedBars); T.eq(PetActionButton6:GetParent(), holder("pet"))
    T.isnil(MultiBarBottomLeftButton1:GetAttribute("statehidden"), "bar 2's twins: nothing written either")
    noBlocked()
end)

-- Players saw "the game blocked MultiBarBottomLeft:ShowBase()" and the other bars'
-- Show, Hide, SetScale and SetPoint after a stance swap in a fight.
T.test("small bars: a stance swap in a fight never runs the game's bar pass tainted", function()
    stub.Load({ actionbars = true, before = function()
        ABW.newWorld({ forms = 3, ab = { bars = { stance = { icons = 2 } } } })
    end })
    DaylightUI:Set("ActionBars", "bars.stance.icons", 1)
    stub.RunTimers()
    stub.EnterCombat()
    stub.FireEvent("UPDATE_BONUS_ACTIONBAR")
    stub.LeaveCombat()
    T.eq(StanceButton3:GetParent(), DaylightUIParkedBars, "past the Buttons setting: out of sight all the same")
    noBlocked()
end)

T.test("small bars: the stance you're in is lit, the others gray and dim, also in a fight", function()
    login({ forms = 3 })
    local Skin = AB().Skin
    local parts1, parts2 = Skin.GetParts(StanceButton1), Skin.GetParts(StanceButton2)
    local swap = function(i)
        stub.form = i
        stub.FireEvent("UPDATE_SHAPESHIFT_FORM")
        stub.RunTimers()
    end
    swap(nil)
    T.falsy(parts1.formOn); T.falsy(parts1.formOff, "no form: every icon keeps its color")
    T.near(StanceButton1.icon:GetAlpha(), 1)
    stub.EnterCombat()
    swap(1)
    T.truthy(parts1.formOn, "the one you're in")
    T.eq(parts1.color, Skin.STATE.lit, "lit border")
    T.truthy(parts2.formOff, "the others")
    T.near(parts2.gA, Skin.FORM_OFF, nil, "dim")
    T.eq(parts2.gray, 1)
    swap(2)
    stub.LeaveCombat()
    T.falsy(parts1.formOn); T.truthy(parts1.formOff); T.truthy(parts2.formOn); T.falsy(parts2.formOff)
    T.eq(parts2.gray, 0, "back in color")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    noBlocked()
end)

T.test("small bars: a stance that reads secret keeps the last answer", function()
    login({ forms = 2, form = 1 })
    local parts1 = AB().Skin.GetParts(StanceButton1)
    stub.FireEvent("UPDATE_SHAPESHIFT_FORM")
    stub.RunTimers()
    T.truthy(parts1.formOn)
    local wasSecret = _G.issecretvalue
    _G.issecretvalue = function() return true end
    stub.form = 2
    stub.FireEvent("UPDATE_SHAPESHIFT_FORM")
    stub.RunTimers()
    T.truthy(parts1.formOn)
    _G.issecretvalue = wasSecret
end)

T.test("small bars: no forms, no stance bar; learning one brings it, after combat", function()
    login()
    T.falsy(holder("stance"):IsShown())
    stub.forms = 2
    stub.EnterCombat()
    stub.FireEvent("UPDATE_SHAPESHIFT_FORMS")
    T.falsy(holder("stance"):IsShown(), "not in combat")
    stub.LeaveCombat()
    T.truthy(holder("stance"):IsShown()); T.eq(StanceButton2:GetParent(), holder("stance"))
    T.eq(StanceButton3:GetParent(), DaylightUIParkedBars)
    noBlocked()
end)

T.test("small bars: the pet bar shows with a pet; the game's pet bar stays, unseen", function()
    login()
    local h = holder("pet")
    T.eq(PetActionButton1:GetParent(), h)
    T.eq(PetActionBar:GetParent(), UIParent, "not parked: its OnUpdate colors range")
    T.eq(PetActionBar:GetAlpha(), 0); T.falsy(PetActionBar:IsMouseEnabled())
    T.eq(h.__stateDriver.visibility, "[petbattle][vehicleui][overridebar] hide; [nopet] hide; show")
    T.falsy(h:IsShown())
    stub.SetConditions({ pet = true })
    T.truthy(h:IsShown())
    DaylightUI:Set("ActionBars", "bars.pet.icons", 6)
    T.eq(PetActionButton7:GetParent(), DaylightUIParkedBars)
    DaylightUI:Set("ActionBars", "bars.pet.icons", 10)
    T.eq(PetActionButton7:GetParent(), h, "back on the bar")
end)

T.test("small bars: the possess bar shows only while possessing", function()
    login()
    local h = holder("possess")
    T.eq(PossessButton1:GetParent(), h); T.eq(PossessButton2:GetParent(), h)
    T.eq(PossessActionBar:GetParent(), DaylightUIParkedBars)
    T.eq(h.__stateDriver.visibility, "[nopossessbar] hide; show")
    T.falsy(h:IsShown())
    stub.SetConditions({ possessbar = true })
    T.truthy(h:IsShown())
end)

T.test("small bars: every option applies live, like the big bars", function()
    login({ forms = 4 })
    DaylightUI:Set("ActionBars", "bars.stance.rows", 2)
    T.near(holder("stance"):GetHeight(), 2 * 18 + 2)
    DaylightUI:Set("ActionBars", "bars.stance.vertical", true)
    T.near(holder("stance"):GetWidth(), 2 * 18 + 2)
    DaylightUI:Set("ActionBars", "bars.stance.size", 100)
    T.near(StanceButton1:GetScale(), 1)
    local e = DaylightUI.Movers.Get("actionbars.stance")
    T.eq(e.frame, holder("stance")); T.falsy(e.proxy)
end)

T.test("totem bar: the game's totem bar in our holder, centered, scaled, kept there", function()
    login({ class = "SHAMAN" })
    local h = holder("totem")
    local mc = MultiCastActionBarFrame
    T.eq(h:GetName(), "DaylightUITotemBar")
    T.eq(mc:GetParent(), h)
    local p, rel = mc:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(rel, h)
    T.near(mc:GetScale(), 0.6)
    T.near(h:GetWidth(), 200 * 0.6); T.near(h:GetHeight(), 40 * 0.6)
    -- No hook on its SetPoint, since Edit Mode's protected code calls it. It's put
    -- back the frame after the game's layout.
    T.isnil(rawget(mc, "SetPoint"), "no hook on the totem bar's SetPoint")
    mc:ClearAllPoints(); mc:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)   -- Edit Mode moving it
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    stub.RunTimers()
    T.eq(mc:GetNumPoints(), 1); T.eq(select(2, mc:GetPoint(1)), h)
    local e = DaylightUI.Movers.Get("actionbars.totembar")
    T.eq(e.frame, h, "the totem bar's old mover key, on our holder"); T.falsy(e.proxy)
    T.eq(h.__stateDriver.visibility, "[petbattle][vehicleui][overridebar] hide; show")
    T.truthy(AB().Skin.IsSkinned(MultiCastActionButton1))
end)

T.test("totem bar: an unlock handle once the game's bar has totems", function()
    local DUI = login({ class = "SHAMAN", totemSlots = 4 })
    local e = DUI.Movers.Get("actionbars.totembar")
    T.truthy(e.active(), "a shaman's totem bar with totems gets a handle")
    MultiCastActionBarFrame.numActiveSlots = 0
    T.falsy(e.active(), "no totems yet: the game keeps the bar hidden, no handle")
    DUI.Movers.Unlock()
    MultiCastActionBarFrame.numActiveSlots = 3
    stub.FireEvent("UPDATE_MULTI_CAST_ACTIONBAR")
    stub.RunTimers()
    T.truthy(e.active(), "totems learned")
    local h = DUI.Movers.Handle("actionbars.totembar")
    T.truthy(h and h:IsShown(), "learned while unlocked: the handle comes at once")
    DUI.Movers.Lock()
end)

T.test("totem bar: not a shaman, the game's totem bar is never touched", function()
    login()
    local mc = MultiCastActionBarFrame
    T.eq(mc:GetParent(), UIParent, "not in our holder")
    T.isnil(rawget(mc, "SetPoint"), "no hook")
    T.eq(mc.__scale, 1, "not scaled")
    T.falsy(AB().Skin.IsSkinned(MultiCastActionButton1), "its buttons not skinned")
end)

T.test("totem bar: size, spacing and direction apply live", function()
    login({ class = "SHAMAN" })
    DaylightUI:Set("ActionBars", "bars.totem.size", 100)
    T.near(MultiCastActionBarFrame:GetScale(), 1)
    DaylightUI:Set("ActionBars", "bars.totem.pad", 6)
    local _, rel, _, x = MultiCastActionButton2:GetPoint(1)
    T.eq(rel, MultiCastActionButton1); T.eq(x, 6)
    DaylightUI:Set("ActionBars", "bars.totem.vertical", true)
    local p, _, rp, _, y = MultiCastActionButton2:GetPoint(1)
    T.eq(p, "TOP"); T.eq(rp, "BOTTOM"); T.eq(y, -6)
end)

T.test("options: the Bar Layout page has one card for every bar (Settings for), from the bars' data", function()
    local DUI = login()
    local page = DUI.Options.GetPage("ActionBars.barlayout")
    local errors = DUI.Options.ValidatePage(page)
    T.eq(#errors, 0, table.concat(errors, "\n"))
    local labels = {}
    for _, g in ipairs(page.groups) do labels[#labels + 1] = g.label end
    T.deq(labels, { "Bars", "Totem Timers" })
    local pick = page.groups[1].items[1]
    T.eq(pick.label, "Settings for")
    T.deq(pick.order, { "main", "bar2", "left", "right", "bar5", "bar6", "bar7", "bar8", "stance", "pet", "possess", "totem" })
    T.eq(pick.values.main, "Action Bar 1")
    T.falsy(page.desc:find("reload", 1, true) or page.desc:find("Edit Mode", 1, true), "nothing about reloads")
    local function item(bar, label)
        for _, it in ipairs(page.groups[1].items) do
            if it.label == label and type(it.key) == "string" and it.key:find("bars." .. bar .. ".", 1, true) == 1 then return it end
        end
    end
    T.eq(item("main", "Buttons").min, 1, "1 to 12 now"); T.eq(item("main", "Buttons").max, 12)
    -- One Visible row covers the fade picks and the hiding ones (When to show and Fade used to be two rows).
    local vis = item("main", "Visible")
    T.eq(vis.key, "bars.main.visible", "keyed on the bar's own setting, so a jump finds it")
    T.deq(vis.order, { "never", "ooc", "combat", "always", "float", "hide:nocombat", "hide:combat", "hide:hidden" })
    T.eq(vis.values.never, "Always")
    T.isnil(item("main", "When to show")); T.isnil(item("main", "Fade"))
    T.eq(item("stance", "Buttons").max, 10)
    T.eq(item("stance", "Visible").values.never, "When you have forms")
    T.eq(item("pet", "Visible").values.never, "With a pet")
    T.isnil(item("possess", "Buttons")); T.isnil(item("possess", "Rows"), "possess: two buttons, one row")
    T.isnil(item("possess", "Visible").values["hide:combat"], "possess: only Hidden")
    T.truthy(item("possess", "Visible").values["hide:hidden"])
    T.isnil(item("totem", "Buttons")); T.eq(item("totem", "Button size").key, "bars.totem.size")
    T.eq(item("totem", "Visible").values.never, "When you have totems")
    -- It reads and writes both settings.
    T.eq(vis.get(), "never")
    vis.set("ooc")
    T.eq(DUI:Get("ActionBars", "bars.main.fade.mode"), "ooc"); T.eq(DUI:Get("ActionBars", "bars.main.visible"), "always")
    vis.set("hide:nocombat")
    T.eq(DUI:Get("ActionBars", "bars.main.visible"), "nocombat"); T.eq(DUI:Get("ActionBars", "bars.main.fade.mode"), "never")
    T.eq(vis.get(), "hide:nocombat")
    vis.set("float")
    T.eq(vis.get(), "float"); T.eq(DUI:Get("ActionBars", "bars.main.visible"), "always")
    T.eq(item("left", "Visible").default(), "always", "the side bars fade until moused over")
    T.eq(item("bar5", "Visible").default(), "hide:hidden")
    vis.set("never")
    -- Copy from: an action bar's shape onto another.
    DUI:Set("ActionBars", "bars.bar2.size", 80)
    pick.set("bar5")
    local from, button = page.groups[1].items[2], page.groups[1].items[3]
    from.set("bar2")
    button.func()
    T.eq(DUI:Get("ActionBars", "bars.bar5.size"), 80, "copied")
    pick.set("main")
end)

T.test("upgrade: the totem bar's size and spacing move into the bars' settings, once", function()
    login({ ab = { totemBar = { size = 80, pad = 5 } }, class = "SHAMAN" })
    local db = DaylightUI:GetModule("ActionBars").db
    T.eq(db.bars.totem.size, 80); T.eq(db.bars.totem.pad, 5)
    T.eq(db.barsUpgrade, #AB().BARS_UPGRADE)
    T.isnil(db.totemBar, "the old bars' settings are gone once carried over")
    T.near(MultiCastActionBarFrame:GetScale(), 0.8, nil, "and the bar shows it from the start")
    db.bars.totem.size = 100
    AB().UpgradeBars(DaylightUI.DB.Active())
    T.eq(db.bars.totem.size, 100, "a step never runs twice")
end)

T.test("upgrade: a profile copied from an older one is upgraded too", function()
    login()
    local p = { modules = { ActionBars = { totemBar = { size = 70 } } } }
    DaylightUI.DB.RunUpgrades(p)
    T.eq(p.modules.ActionBars.bars.totem.size, 70)
    T.isnil(p.modules.ActionBars.bars.totem.pad, "only what was saved")
end)

-- A profile's action bar settings as saved: only what differs from the defaults.
local SAVED = { look = { border = 2, keybindPos = "bottom" }, bars = { left = { rows = 1 }, pet = { size = 80 } },
                ooc = { main = true }, totemBar = { size = 80, pad = 5 } }
local function copyOf(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copyOf(v) end
    return out
end

T.test("profiles: with the new bars, a profile's saved settings keep every value, plus the upgrade's", function()
    login({ ab = copyOf(SAVED) })
    stub.FireEvent("PLAYER_LOGOUT")
    local expected = copyOf(SAVED)
    expected.bars.totem = { size = 80, pad = 5 }
    expected.totemBar = nil                       -- upgrade step 2: the old bars' settings are gone
    expected.barsUpgrade = #AB().BARS_UPGRADE
    expected.ooc = nil                            -- the fade upgrade: now the bar's own fade
    expected.bars.main = { fade = { mode = "ooc" } }
    -- From before bars 5-8 started hidden: kept shown, to be checked at the next login.
    expected.checkEmptyBars = {}
    for _, key in ipairs(BARS_5_TO_8) do
        expected.bars[key] = { visible = "always" }
        expected.checkEmptyBars[key] = true
    end
    T.deq(DaylightUIDB.profileData[DaylightUI.DB.DEFAULT].modules.ActionBars, expected)
end)

-- The next session: the saved settings and the game's layouts carried over.
-- opts are newWorld's, plus switch (set the account switch for it) and edit(db)
-- (change the saved table before it loads).
local function relogin(opts)
    opts = opts or {}
    local db = DaylightUIDB
    ABW.carry = ABW.lastSaved
    return stub.Load({ actionbars = true, before = function()
        ABW.newWorld(opts)
        _G.DaylightUIDB = db
        if opts.switch ~= nil then db.newActionBars = opts.switch end
        if opts.edit then opts.edit(db) end
    end })
end

-- On this profile's own Edit Mode layout (the setup guide's Install), then into the
-- world, which is what Bars.Convert waits for.
local function onOurLayout(DUI)
    DUI.Installer.Install()
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.RunTimers()
end

-- tests/abworld.lua: bar 3's hidden buttons run from x 200 to 480, y 26 to 118.
local function bar3Centre()
    return 340 - UIParent:GetWidth() / 2, 72 - UIParent:GetHeight() / 2
end

T.test("positions: a moved bar lands where its buttons were; the old spot is kept", function()
    local DUI = login({ positions = { ["actionbars.left"] = { -500, -300 } } })
    onOurLayout(DUI)
    local pos = DUI.DB.Positions()
    local x, y = bar3Centre()
    T.near(pos["actionbars.left"][1], x, 1); T.near(pos["actionbars.left"][2], y, 1)
    T.deq(pos["actionbars.old.left"], { -500, -300 }, "the old bars' own spot, kept")
    T.isnil(pos["actionbars.main"], "a bar never moved keeps no spot: it follows the shapes")
    local p, _, _, hx = holder("left"):GetPoint(1)
    T.eq(p, "CENTER"); T.near(hx, pos["actionbars.left"][1], 0.01)
end)

T.test("positions: off this profile's own Edit Mode layout, nothing is converted", function()
    local DUI = login({ positions = { ["actionbars.left"] = { -500, -300 } } })
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.RunTimers()
    T.deq(DUI.DB.Positions()["actionbars.left"], { -500, -300 })
    T.isnil(DUI.DB.Positions()["actionbars.old.left"])
end)

T.test("positions: converted once; a move or a reset afterwards stays", function()
    local DUI = login({ positions = { ["actionbars.left"] = { -500, -300 }, ["actionbars.right"] = { 500, -300 } } })
    onOurLayout(DUI)
    local pos = DUI.DB.Positions()
    pos["actionbars.right"] = { 1, 2 }                    -- moved again with the new bars
    DaylightUI.Movers.Reset("actionbars.left")            -- one bar reset
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.RunTimers()
    T.deq(pos["actionbars.right"], { 1, 2 }, "a move after converting isn't undone")
    T.isnil(pos["actionbars.left"], "nor a reset")
    AB().Bars.ResetPositions()
    T.isnil(pos["actionbars.old.right"], "Reset bar positions clears the old spots too")
end)

T.test("positions: each profile converts on its own, when it's used", function()
    local DUI = login({ positions = { ["actionbars.left"] = { -500, -300 } } })
    local data = DaylightUIDB.profileData
    data.Second = { positions = { ["actionbars.left"] = { 400, 100 } } }
    onOurLayout(DUI)
    T.deq(data.Second.positions["actionbars.left"], { 400, 100 }, "another profile isn't touched")
    T.isnil(data.Second.positions["actionbars.old.left"])
    local key = DUI.DB.CharKey()
    DUI = relogin({ edit = function(db)
        db.characters[key] = db.characters[key] or {}
        db.characters[key].profile = "Second"
    end })
    T.eq(DUI.DB.ActiveName(), "Second")
    DUI.EditMode.UseProfile("Second")                     -- its own layout, as a profile switch gives it
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.RunTimers()
    T.near(data.Second.positions["actionbars.left"][1], (bar3Centre()), 1, "converted when it was used")
    T.deq(data.Second.positions["actionbars.old.left"], { 400, 100 })
end)

T.test("profiles: copying bar positions keeps each bar's spot and old spot together", function()
    local DUI = login()
    local data = DaylightUIDB.profileData
    data.From = { positions = { ["actionbars.left"] = { 1, 1 } } }       -- not converted yet
    data.To = { positions = { ["actionbars.left"] = { 2, 2 }, ["actionbars.old.left"] = { 3, 3 } } }
    DUI.Profiles.CopyActionBarPositions("From", "To")
    T.deq(data.To.positions["actionbars.left"], { 1, 1 })
    T.isnil(data.To.positions["actionbars.old.left"], "no stale old spot left behind")
    data.From.positions["actionbars.old.left"] = { 9, 9 }
    DUI.Profiles.CopyActionBarPositions("From", "To")
    T.deq(data.To.positions["actionbars.old.left"], { 9, 9 }, "a converted one travels whole")
end)

T.test("info panel: the experience bar measures our bar 1 when the new bars run", function()
    stub.Load({ actionbars = true, infopanel = true, before = function() ABW.newWorld() end })
    for i, b in ipairs(DaylightUI.ActionBarButtons("main")) do
        local x = 100 + (i - 1) * 40
        function b:GetLeft() return x end
        function b:GetRight() return x + 30 end
        function b:GetBottom() return 20 end
    end
    local span = stub.infopanel.Panel.BarsSpan(CreateFrame("Frame", nil, UIParent))
    -- The buttons are at 70%, so their own units times 0.7.
    T.near(span.left, 100 * 0.7); T.near(span.right, (100 + 11 * 40 + 30) * 0.7); T.near(span.bottom, 20 * 0.7)
end)

T.test("default on: an account that never set the switch gets the new bars; moved bars convert", function()
    local DUI = login({ switch = "unset", positions = { ["actionbars.left"] = { -500, -300 } } })
    T.truthy(AB().Bars.built)
    onOurLayout(DUI)
    T.near(DUI.DB.Positions()["actionbars.left"][1], (bar3Centre()), 1)
    T.deq(DUI.DB.Positions()["actionbars.old.left"], { -500, -300 })
end)

T.test("bars: the game's controller bars up, ours step aside; off again they're back", function()
    login()
    local Bars, def = AB().Bars, AB().Bars.DEFS[1]
    local ruleOff = Bars.Rule(def)
    T.truthy(ruleOff ~= "hide")
    _G.GamepadMode = { FrameControlsManager = {} }
    _G.InputUtil = { IsGamepadUIEnabled = function() return true end }
    T.eq(Bars.Rule(def), "hide")
    _G.GamepadMode, _G.InputUtil = nil, nil
    T.eq(Bars.Rule(def), ruleOff)
end)

-- The game's controller bars, as their own buttons read in game (/dui padbars):
-- 3 pages of 28 slots, 4 bars of 8 in order no trigger, LT, RT, both, the top
-- bar's 4 face buttons taking no storage. Buttons: D-pad left, up, right, down,
-- then face left, up, right, down (Bindings.xml).
T.test("keys: on a controller a spell's key is the pad button that casts it", function()
    login()
    local Keys = AB().Keys
    local FIRST = 200
    _G.C_GamepadUI = { GetFirstGamepadActionStorageSlotIndex = function() return FIRST end }
    _G.GamepadMode = { FrameControlsManager = {} }
    _G.InputUtil = { IsGamepadUIEnabled = function() return true end }
    local names = { [1] = "Top", [2] = "Dpad", [3] = "Left", [4] = "Face", [5] = "Both", [6] = "Second" }
    C_Spell.GetSpellName = function(id) return names[id] end
    local at = {
        [FIRST + 0] = 1,        -- page 1, top bar, D-pad left
        [FIRST + 3] = 2,        -- page 1, top bar, D-pad down
        [FIRST + 4] = 3,        -- page 1, LT, D-pad left
        [FIRST + 11] = 4,       -- page 1, LT, face down
        [FIRST + 27] = 5,       -- page 1, LT+RT, face down
        [FIRST + 28] = 6,       -- page 2, top bar, D-pad left
    }
    for slot, id in pairs(at) do stub.slots[slot] = { texture = "t", spellID = id } end
    Keys.OnEvent("PadChanged")
    T.eq(Keys.CastKey("Top"), "PADDLEFT")
    T.eq(Keys.CastKey("Dpad"), "PADDDOWN")
    T.eq(Keys.CastKey("Left"), "PADLTRIGGER+PADDLEFT")
    T.eq(Keys.CastKey("Face"), "PADLTRIGGER+PAD1")
    T.eq(Keys.CastKey("Both"), "PADLTRIGGER+PADRTRIGGER+PAD1")
    T.eq(Keys.CastKey("Second"), "2: PADDLEFT")
    T.eq(Keys.CastKey("Nothing"), nil)
    _G.C_GamepadUI, _G.GamepadMode, _G.InputUtil = nil, nil, nil
    for slot in pairs(at) do stub.slots[slot] = nil end
end)

-- The game's glyph sets (InputIconTexture.lua): the active one is picked by the
-- pad's label style, Shapes for a PlayStation pad.
T.test("keys: on a PS5 pad the Cooldown Manager's keys are its own glyphs (L2, cross), and change with the pad", function()
    login()
    local Keys = AB().Keys
    _G.C_GamepadUI = { GetFirstGamepadActionStorageSlotIndex = function() return 200 end }
    _G.GamepadMode = { FrameControlsManager = {} }
    _G.InputUtil = { IsGamepadUIEnabled = function() return true end }
    local style = "Shapes"
    local ATLAS = { Shapes = { PADLTRIGGER = "gamepad-ps-l2-normal", PAD1 = "gamepad-ps-cross-normal" },
                    Letters = { PADLTRIGGER = "gamepad-xbox1-trigger-lt-normal", PAD1 = "gamepad-xbox1-a-normal" } }
    _G.InputIconTextureState = { Normal = 1 }
    _G.InputDeviceIconVariant = { Standard = 1, NoShadow = 2 }
    _G.InputIconTextureSetUtility = { GetActiveInputIconButtonTextures = function(key, variant)
        local a = ATLAS[style][key]
        return a and { [1] = variant == 2 and a:gsub("%-normal$", "-flat-normal") or a } or nil
    end }
    C_Spell.GetSpellName = function(id) return id == 4 and "Face" or nil end
    stub.slots[211] = { texture = "t", spellID = 4 }   -- page 1, LT, face down
    Keys.OnEvent("PadChanged")
    T.eq(Keys.CastKey("Face"), "|A:gamepad-ps-l2-flat-normal:0:0|a+|A:gamepad-ps-cross-flat-normal:0:0|a")
    style = "Letters"
    stub.FireEvent("GAME_PAD_ACTIVE_CHANGED", true)
    T.eq(Keys.CastKey("Face"), "|A:gamepad-xbox1-trigger-lt-flat-normal:0:0|a+|A:gamepad-xbox1-a-flat-normal:0:0|a", "another pad, its own")
    stub.slots[211] = nil
    _G.InputIconTextureSetUtility, _G.InputIconTextureState, _G.InputDeviceIconVariant = nil, nil, nil
    _G.C_GamepadUI, _G.GamepadMode, _G.InputUtil = nil, nil, nil
end)

T.test("keys: a rebound controller button shows its new key", function()
    login()
    local Keys = AB().Keys
    _G.C_GamepadUI = { GetFirstGamepadActionStorageSlotIndex = function() return 200 end }
    _G.GamepadMode = { FrameControlsManager = {} }
    _G.InputUtil = { IsGamepadUIEnabled = function() return true end }
    C_Spell.GetSpellName = function(id) return id == 1 and "Top" or nil end
    stub.slots[200] = { texture = "t", spellID = 1 }
    stub.bindings["GAMEPADACTIONBUTTON1"] = { "PADPADDLE1" }
    Keys.OnEvent("PadChanged")
    T.eq(Keys.CastKey("Top"), "PADPADDLE1")
    stub.bindings["GAMEPADACTIONBUTTON1"] = nil
    stub.slots[200] = nil
    _G.C_GamepadUI, _G.GamepadMode, _G.InputUtil = nil, nil, nil
end)
