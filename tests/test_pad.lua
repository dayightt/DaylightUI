local stub = require("stub")

-- A stand-in for the game's FrameControlsManager (FrameShown / FrameHidden).
local function controller(on)
    local m = { calls = {} }
    function m:FrameShown(frame) self.calls[#self.calls + 1] = { "shown", frame } end
    function m:FrameHidden(frame) self.calls[#self.calls + 1] = { "hidden", frame } end
    _G.GamepadMode = { FrameControlsManager = m }
    _G.InputUtil = { IsGamepadUIEnabled = function() return on end }
    return m
end

-- Only this frame's calls, since other windows (the setup guide) open at login.
local function of(m, f)
    local out = {}
    for _, c in ipairs(m.calls) do
        if c[2] == f then out[#out + 1] = c[1] end
    end
    return out
end

local function clear()
    _G.GamepadMode, _G.InputUtil = nil, nil
end

T.test("pad: a window tells the game when it opens and closes", function()
    local DUI = stub.Load()
    local m = controller(true)
    local f = DUI.Win.New({ name = "PadTestWindow", title = "Test" })
    f:Show()
    stub.RunTimers()
    T.eq(#of(m, f), 1); T.eq(of(m, f)[1], "shown")
    f:Hide()
    T.eq(#of(m, f), 2); T.eq(of(m, f)[2], "hidden")
    clear()
end)

T.test("pad: told a frame later, after a game window opening with it", function()
    local DUI = stub.Load()
    local m = controller(true)
    local f = CreateFrame("Frame", nil, UIParent)
    f:Hide()
    DUI.Pad.Follow(f)
    f:Show()
    T.eq(#of(m, f), 0)
    stub.RunTimers()
    T.eq(#of(m, f), 1)
    clear()
end)

T.test("pad: nothing is asked of the game in a fight, it's told after", function()
    local DUI = stub.Load()
    local m = controller(true)
    local f = CreateFrame("Frame", nil, UIParent)
    f:Hide()
    DUI.Pad.Follow(f)
    stub.EnterCombat()
    f:Show()
    stub.RunTimers()
    T.eq(#of(m, f), 0)
    stub.LeaveCombat()
    T.eq(#of(m, f), 1); T.eq(of(m, f)[1], "shown")
    clear()
end)

T.test("pad: open and shut in a fight, the game never hears of it", function()
    local DUI = stub.Load()
    local m = controller(true)
    local f = CreateFrame("Frame", nil, UIParent)
    f:Hide()
    DUI.Pad.Follow(f)
    stub.EnterCombat()
    f:Show()
    stub.RunTimers()
    f:Hide()
    stub.LeaveCombat()
    T.eq(#of(m, f), 0)
    clear()
end)

T.test("pad: B closes through the window's own close", function()
    local DUI = stub.Load()
    controller(true)
    local closed = false
    local f = DUI.Win.New({ name = "PadTestClose", title = "Test", onClose = function() closed = true end })
    T.eq(f.SmartNavigationCloseHandler(f), true)
    T.eq(closed, true)
    clear()
end)

T.test("pad: Motion windows follow too, and B vanishes them", function()
    local DUI = stub.Load()
    local m = controller(true)
    local f = CreateFrame("Frame", nil, UIParent)
    f:Hide()
    DUI.Motion.Window(f)
    f:Show()
    stub.RunTimers()
    T.eq(#of(m, f), 1)
    T.eq(type(f.SmartNavigationCloseHandler), "function")
    clear()
end)

T.test("pad: with the controller UI off, or the game's code missing, nothing happens", function()
    local DUI = stub.Load()
    local m = controller(false)
    local f = DUI.Win.New({ name = "PadTestOff", title = "Test" })
    f:Show()
    stub.RunTimers()
    T.eq(#of(m, f), 0); T.eq(DUI.Pad.On(), false)
    clear()
    f:Hide(); f:Show()
    stub.RunTimers()
    T.eq(DUI.Pad.On(), false)
end)

-- ---------------------------------------------------------------------
-- Game rules these tests rely on, copied from its source:
-- - FrameShown/FrameHidden are refused to addons while the Combat restriction
--   is active (SecureHelper.lua IsSecureOrOutOfCombatRestriction).
-- - A frame left in shownFrames keeps the catcher that blocks the D-pad and
--   face buttons (FrameControlsManager.lua SetFallThroughCatcherActive).
-- - Inside ADDON_RESTRICTION_STATE_CHANGED the client still answers "not active".
-- - FocusGamepad/UnfocusGamepad are called on the frame gaining or losing focus.
-- ---------------------------------------------------------------------
local function strict(on)
    local m = { calls = {}, shown = {}, refused = 0 }
    m.shownFrames = m.shown   -- the game's own name for its list
    local function barred()
        if C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Combat) then
            m.refused = m.refused + 1
            return true
        end
    end
    function m:GetActiveFrame() return self.focused end
    function m:Focus(frame)
        if self.focused == frame then return end
        local old = self.focused
        self.focused = frame
        if old and old.UnfocusGamepad then old:UnfocusGamepad() end
        if frame and frame.FocusGamepad then frame:FocusGamepad() end
    end
    function m:FrameShown(frame, isPopup, focus)
        if barred() then return end
        if focus == nil then focus = true end
        self.calls[#self.calls + 1] = { "shown", frame, focus }
        table.insert(self.shown, frame)
        if focus or not self.focused then self:Focus(frame) end
    end
    -- The game's FrameHidden: with no shown window left to focus, its controller
    -- bindings go back to the core set, and the action bar's listener then calls
    -- SetPreferredGamepadInteractTarget, which is refused when an addon started it.
    m.toCore = 0
    function m:FrameHidden(frame)
        if barred() then return end
        self.calls[#self.calls + 1] = { "hidden", frame }
        local was = #self.shown
        for i, f in ipairs(self.shown) do
            if f == frame then table.remove(self.shown, i); break end
        end
        if self.focused == frame then self:Focus(self.shown[1]) end
        local left = false
        for _, f in ipairs(self.shown) do if f:IsShown() then left = true end end
        if #self.shown < was and not left then self.toCore = self.toCore + 1 end
    end
    _G.GamepadMode = { FrameControlsManager = m }
    _G.InputUtil = { IsGamepadUIEnabled = function() return on end }
    return m
end

local function clearAll()
    clear()
    _G.SmartNavigation = nil
end

local function has(m, frame)
    for _, f in ipairs(m.shown) do if f == frame then return true end end
    return false
end

-- The setup guide opens at login and registers too, so get it out of the way first.
local function fresh(m)
    stub.RunTimers()
    m:Focus(nil)
    m.shown = {}
    m.shownFrames = m.shown
end

T.test("pad: a fight starting hands the controller back, so a closed window can't block the buttons", function()
    local DUI = stub.Load()
    local m = strict(true)
    local f = DUI.Win.New({ name = "PadTestFight", title = "Test" })
    f:Show()
    stub.RunTimers()
    T.eq(has(m, f), true)
    stub.SetRestriction("Combat", true)
    T.eq(has(m, f), false)      -- told in time, while the game still accepts it
    T.eq(m.refused, 0)
    stub.SetRestriction("Combat", false)
    clearAll()
end)

T.test("pad: a window still open when the fight ends is handed to the D-pad again", function()
    local DUI = stub.Load()
    local m = strict(true)
    local f = DUI.Win.New({ name = "PadTestAfter", title = "Test" })
    f:Show()
    stub.RunTimers()
    stub.SetRestriction("Combat", true)
    stub.EnterCombat()
    stub.SetRestriction("Combat", false)
    stub.LeaveCombat()
    stub.RunTimers()
    T.eq(has(m, f), true)
    clearAll()
end)

T.test("pad: a window closed in the fight isn't told again after it", function()
    local DUI = stub.Load()
    local m = strict(true)
    local f = DUI.Win.New({ name = "PadTestGone", title = "Test" })
    f:Show()
    stub.RunTimers()
    stub.SetRestriction("Combat", true)
    stub.EnterCombat()
    f:Hide()
    stub.SetRestriction("Combat", false)
    stub.LeaveCombat()
    stub.RunTimers()
    T.eq(has(m, f), false)
    T.eq(m.refused, 0)
    clearAll()
end)

T.test("pad: a game window parked behind ours leaves the game's list, given back it returns", function()
    local DUI = stub.Load()
    local m = strict(true)
    local game = CreateFrame("Frame", "PadParkedGame", UIParent)
    local ours = CreateFrame("Frame", nil, UIParent)
    DUI.Pad.Follow(ours)
    m:FrameShown(game)
    DUI.Pad.Forget(game)
    T.eq(has(m, game), false)
    DUI.Pad.Remember(game)
    T.eq(has(m, game), true)
    clearAll()
end)

-- Opening the character window drops the game's parked one in the same frame,
-- while this one is told a frame later. Dropping it then left the game's list
-- empty, so its bindings went back to the core set from addon code and the
-- game refused SetPreferredGamepadInteractTarget.
T.test("pad: a parked game window waits to leave the list until a window of ours is on it", function()
    local DUI = stub.Load()
    local m = strict(true)
    fresh(m)
    local game = CreateFrame("Frame", "PadParkedAlone", UIParent)
    local ours = CreateFrame("Frame", nil, UIParent)
    ours:Hide()
    DUI.Pad.Follow(ours)
    m:FrameShown(game)
    ours:Show()
    DUI.Pad.Forget(game)
    T.eq(m.toCore, 0, "never empties the game's list")
    T.eq(has(m, game), true, "kept until ours is listed")
    stub.RunTimers()
    T.eq(has(m, game), false, "dropped once ours is listed")
    T.eq(m.focused, ours)
    T.eq(m.toCore, 0)
    clearAll()
end)

T.test("pad: Win.Follow keeps a parked game window listed while it's alone on the list", function()
    local DUI = stub.Load()
    local m = strict(true)
    local game = CreateFrame("Frame", "PadFollowedAlone", UIParent)
    game:Hide()
    local def = DUI.Win.Follow({ key = "padalone", frames = { w = function() return game end } })
    fresh(m)
    game:Show()
    m:FrameShown(game)
    DUI.Win.Followers.Tick()
    T.eq(m.toCore, 0)
    T.eq(has(m, game), true)
    T.truthy(def)
    clearAll()
end)

T.test("pad: a parked game window seen open by Win.Follow is forgotten", function()
    local DUI = stub.Load()
    local m = strict(true)
    local game = CreateFrame("Frame", "PadFollowedGame", UIParent)
    game:Hide()
    local def = DUI.Win.Follow({ key = "padtest", frames = { w = function() return game end } })
    stub.RunTimers()
    T.eq(DUI.Win.Followers.Parked(def, "w"), true)
    game:Show()
    m:FrameShown(game)
    DUI.Win.Followers.Tick()
    T.eq(has(m, game), false)
    clearAll()
end)

T.test("pad: a second window opening with another keeps the focus on the first", function()
    local DUI = stub.Load()
    local m = strict(true)
    fresh(m)
    local first = CreateFrame("Frame", nil, UIParent); first:Hide()
    local bag = CreateFrame("Frame", nil, UIParent); bag:Hide()
    bag.padSecond = true
    DUI.Pad.Follow(first)
    DUI.Pad.Follow(bag)
    first:Show()
    stub.RunTimers()
    bag:Show()
    stub.RunTimers()
    T.eq(m.focused, first)
    T.eq(has(m, bag), true)
    clearAll()
end)

T.test("pad: a second window alone takes the focus", function()
    local DUI = stub.Load()
    local m = strict(true)
    fresh(m)
    local bag = CreateFrame("Frame", nil, UIParent); bag:Hide()
    bag.padSecond = true
    DUI.Pad.Follow(bag)
    bag:Show()
    stub.RunTimers()
    T.eq(m.focused, bag)
    clearAll()
end)

T.test("pad: a window's own buttons are bound only while it has the focus, and act on the stop", function()
    local DUI = stub.Load()
    fresh(strict(true))
    local f = DUI.Win.New({ name = "PadTestX", title = "Test" })
    local b = CreateFrame("Button", nil, f)
    _G.SmartNavigation = { GetCurrentButton = function() return b end }
    local got
    f.padKeys = { { key = "X", label = "Buy a stack", run = function(at) got = at end } }
    T.eq(stub.overrides.PAD3, nil)
    f:Show()
    stub.RunTimers()
    T.truthy(stub.overrides.PAD3)
    _G[stub.overrides.PAD3.click]:Click()
    T.eq(got, b)
    f:Hide()
    T.eq(stub.overrides.PAD3, nil)
    clearAll()
end)

T.test("pad: a window with no buttons of its own leaves X and Y to the game", function()
    local DUI = stub.Load()
    strict(true)
    local f = DUI.Win.New({ name = "PadTestNoX", title = "Test" })
    f:Show()
    stub.RunTimers()
    T.eq(stub.overrides.PAD3, nil)
    T.eq(stub.overrides.PAD4, nil)
    clearAll()
end)

T.test("pad: a button that can't act on this stop hides and does nothing", function()
    local DUI = stub.Load()
    fresh(strict(true))
    local f = DUI.Win.New({ name = "PadTestWhen", title = "Test" })
    local b = CreateFrame("Button", nil, f)
    _G.SmartNavigation = { GetCurrentButton = function() return b end }
    local ran = false
    f.padKeys = { { key = "Y", label = "Options", when = function() return false end, run = function() ran = true end } }
    f:Show()
    stub.RunTimers()
    _G[stub.overrides.PAD4.click]:Click()
    T.falsy(ran)
    for _, row in ipairs(DUI.Pad.HintList(f)) do T.truthy(row[2] ~= "Options") end
    clearAll()
end)

T.test("pad: the fight clears the window's buttons, so they're the action buttons again", function()
    local DUI = stub.Load()
    fresh(strict(true))
    local f = DUI.Win.New({ name = "PadTestXFight", title = "Test" })
    f.padKeys = { { key = "X", label = "Open all", run = function() end } }
    f:Show()
    stub.RunTimers()
    T.truthy(stub.overrides.PAD3)
    stub.SetRestriction("Combat", true)
    T.eq(stub.overrides.PAD3, nil)
    stub.SetRestriction("Combat", false)
    clearAll()
end)

T.test("pad: LB and RB step through a window's tabs, around the ends", function()
    local DUI = stub.Load()
    strict(true)
    local picked = {}
    local f = DUI.Win.New({ name = "PadTestTabs", title = "Test" })
    DUI.Win.Tabs(f, { { id = "a", text = "A" }, { id = "b", text = "B" }, { id = "c", text = "C" } },
        function(id) picked[#picked + 1] = id end)
    DUI.Win.PickTab(f, "a")
    stub.RunTimers()   -- the setup guide, opening at login, has its turn first
    f:Show()
    stub.RunTimers()
    T.truthy(stub.overrides.PADRSHOULDER)
    local nextTab = _G[stub.overrides.PADRSHOULDER.click]
    local prevTab = _G[stub.overrides.PADLSHOULDER.click]
    nextTab:Click()
    T.eq(picked[1], "b")
    prevTab:Click(); prevTab:Click()
    T.eq(picked[3], "c")
    clearAll()
end)

T.test("pad: a window without tabs leaves LB and RB to the game", function()
    local DUI = stub.Load()
    strict(true)
    local f = DUI.Win.New({ name = "PadTestNoTabs", title = "Test" })
    f:Show()
    stub.RunTimers()
    T.eq(stub.overrides.PADRSHOULDER, nil)
    clearAll()
end)

T.test("pad: moving the focus to a game window frees X for it", function()
    local DUI = stub.Load()
    local m = strict(true)
    fresh(m)
    local f = DUI.Win.New({ name = "PadTestLeave", title = "Test" })
    f.padKeys = { { key = "X", label = "Open all", run = function() end } }
    local game = CreateFrame("Frame", nil, UIParent)
    f:Show()
    stub.RunTimers()
    T.truthy(stub.overrides.PAD3)
    m:FrameShown(game)
    T.eq(stub.overrides.PAD3, nil)
    clearAll()
end)

T.test("pad: a dropdown takes the D-pad and gives it back; B closes it", function()
    local DUI = stub.Load()
    local m = strict(true)
    local popups = {}
    function m:HandlePopupShown(f) popups[#popups + 1] = "shown"; self:FrameShown(f) end
    function m:HandlePopupHide(f) popups[#popups + 1] = "hidden"; self:FrameHidden(f) end
    local closed = false
    local menu = CreateFrame("Frame", nil, UIParent); menu:Hide()
    DUI.Pad.Popup(menu, function() closed = true end)
    menu:Show()
    T.eq(has(m, menu), true)
    T.eq(menu.SmartNavigationCloseHandler(menu), true)
    T.eq(closed, true)
    menu:Hide()
    T.deq(popups, { "shown", "hidden" })
    clearAll()
end)

T.test("pad: a dropdown opened in a fight never reaches the game", function()
    local DUI = stub.Load()
    local m = strict(true)
    local asked = 0
    function m:HandlePopupShown() asked = asked + 1 end
    function m:HandlePopupHide() asked = asked + 1 end
    local menu = CreateFrame("Frame", nil, UIParent); menu:Hide()
    DUI.Pad.Popup(menu)
    stub.EnterCombat()
    menu:Show()
    menu:Hide()
    stub.LeaveCombat()
    T.eq(asked, 0)
    clearAll()
end)

T.test("pad: a new options page is built outside the window: the game scans a window for every frame made in it", function()
    local DUI = stub.Load()
    strict(true)
    local scans = 0
    _G.SmartNavigation = { RefreshButtonGroups = function() scans = scans + 1 end,
        SetTargetButtonForFrame = function() end }
    local Panel = DUI.OptionsPanel
    Panel.Show("home")
    stub.RunTimers()
    local win = _G.DaylightUIOptions
    -- The game's rule: hooksecurefunc("CreateFrame"), UpdateParent (SmartNavigation.lua).
    local made = 0
    local real = CreateFrame
    _G.CreateFrame = function(kind, name, parent, ...)
        local p = parent
        while p do
            if p == win then made = made + 1; break end
            p = p:GetParent()
        end
        return real(kind, name, parent, ...)
    end
    scans = 0
    Panel.Show("appearance")
    _G.CreateFrame = real
    T.truthy(made < 20, "made in the window: " .. made)
    T.eq(scans, 1, "one scan once it's in")
    T.truthy(Panel.PageFrame("appearance"):GetParent() ~= Panel.offstage, "it moved in")
    clearAll()
end)

T.test("pad: the buttons are named under the window that has the focus", function()
    local DUI = stub.Load()
    fresh(strict(true))
    local f = DUI.Win.New({ name = "PadTestHints", title = "Test" })
    f.padKeys = { { key = "X", label = "Buy a stack", run = function() end } }
    f.padSelect = function() return "Buy" end
    f:Show()
    stub.RunTimers()
    local hints = DUI.Pad.hints
    T.truthy(hints and hints:IsShown(), "a bar under the window")
    T.eq(select(2, hints:GetPoint()), DUI.Pad.focused)
    local labels = {}
    for _, row in ipairs(DUI.Pad.HintList(f)) do labels[#labels + 1] = row[2] end
    T.eq(labels[1], "Buy", "A says what it does here")
    T.eq(labels[2], "Buy a stack")
    f:Hide()   -- the window losing the focus takes its bar away
    stub.RunTimers()
    T.falsy(hints:IsShown(), "gone with it")
    clearAll()
end)

T.test("pad: a window given back as a fight starts waits for its end (no lockdown yet, no overflow)", function()
    local DUI = stub.Load()
    local m = strict(true)
    local game = CreateFrame("Frame", "PadFightGame", UIParent)
    game:Show()
    stub.FireEvent("PLAYER_REGEN_DISABLED")   -- comes before the lockdown starts
    DUI.Pad.Remember(game)
    DUI.Pad.Forget(game)
    DUI.Pad.Remember(game)
    T.eq(has(m, game), false, "not told in the fight")
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    T.eq(has(m, game), true, "told after it")
    clearAll()
end)

T.test("pad: a parked window the game lists again while it stays shown gives the focus back (a quest's reward page)", function()
    local DUI = stub.Load()
    local m = strict(true)
    local game = CreateFrame("Frame", "PadRelisted", UIParent)
    game:Hide()
    local def = DUI.Win.Follow({ key = "padrelist", frames = { w = function() return game end } })
    stub.RunTimers()
    T.eq(DUI.Win.Followers.Parked(def, "w"), true)
    game:Show()
    m:FrameShown(game)
    DUI.Win.Followers.Tick()
    m:FrameShown(game)               -- the game opens its next page in the same window
    DUI.Win.Followers.Tick()
    T.eq(has(m, game), false)
    clearAll()
end)

T.test("pad: a changed list is found again and the D-pad goes where it's aimed, or off a row that's gone", function()
    local DUI = stub.Load()
    strict(true)
    local nav = { scans = 0 }
    function nav:RefreshButtonGroups() self.scans = self.scans + 1 end
    function nav:SetTargetButtonForFrame(_, b) self.target = b end
    function nav:GetCurrentButton() return self.current end
    function nav:SelectTopLeftButton() self.top = true end
    _G.SmartNavigation = nav
    local f = DUI.Win.New({ name = "PadTestSettle", title = "Test" })
    f:Show()
    stub.RunTimers()
    local b = CreateFrame("Button", nil, f)
    b:Show()
    nav.scans = 0
    DUI.Pad.Settle(b)
    DUI.Pad.Settle()
    stub.RunTimers()
    T.eq(nav.scans, 1, "once a frame however many ask")
    T.eq(nav.target, b)
    nav.current = b
    b:Hide()
    DUI.Pad.Settle()
    stub.RunTimers()
    T.truthy(nav.top, "a hidden row gives the stop up")
    clearAll()
end)

T.test("pad: a wide stop counts from a spot at its left end, inside the list", function()
    local DUI = stub.Load()
    strict(true)
    local got, anchor
    _G.SmartNavigation_SetCustomCursorAnchorPointForFrame = function(f, a) got, anchor = f, a end
    _G.CreateAnchor = function(point, to, rel) return { point = point, to = to, rel = rel } end
    local b = CreateFrame("Button", nil, UIParent)
    DUI.Widgets.PadSpot(b)
    T.eq(got, b)
    T.eq(anchor.rel, "CENTER")
    T.eq(select(4, anchor.to:GetPoint(1)), 2, "off the edge")
    _G.SmartNavigation_SetCustomCursorAnchorPointForFrame, _G.CreateAnchor = nil, nil
    clearAll()
end)

-- ---------------------------------------------------------------------
-- The options window behaves like the game's Settings window on a controller
-- (Blizzard_SettingControls.lua). The row is the stop and its control is skipped.
-- Left/right change a slider or dropdown row, and A does what its control does.
-- The game's navigation marks (SmartNavigation/Utility.lua) are plain fields.
-- ---------------------------------------------------------------------
local function navMarks()
    local marks = { focus = {}, ignored = {}, anchor = {} }
    _G.SmartNavigation_MarkFrameFocusable = function(f) marks.focus[f] = true end
    _G.SmartNavigation_MarkFrameIgnored = function(f) if f then marks.ignored[f] = true end end
    _G.SmartNavigation_SetCustomCursorAnchorPointForFrame = function(f, a) marks.anchor[f] = a end
    _G.CreateAnchor = _G.CreateAnchor or function(...) return { ... } end
    return marks
end

local function clearMarks()
    _G.SmartNavigation_MarkFrameFocusable, _G.SmartNavigation_MarkFrameIgnored = nil, nil
    _G.SmartNavigation_SetCustomCursorAnchorPointForFrame = nil
end

local function rowWhere(pf, test)
    for _, card in ipairs(pf.cards) do
        for _, row in ipairs(card.rows) do
            if test(row) then return row end
        end
    end
end

local function optionsOnPad()
    local marks = navMarks()
    local DUI = stub.Load({ module = true })
    local m = strict(true)
    function m:HandlePopupShown() end
    function m:HandlePopupHide() end
    fresh(m)
    DUI.OptionsPanel.Show("appearance")
    stub.RunTimers()
    return DUI, DUI.OptionsPanel.PageFrame(), marks, m
end

T.test("pad options: each row is one stop, its control and reset arrow skipped", function()
    local DUI, pf, marks = optionsOnPad()
    local row = rowWhere(pf, function(r) return r.item.key == "softness" end)
    T.truthy(marks.focus[row], "the row is a stop")
    T.truthy(marks.ignored[row.control], "its slider isn't")
    T.truthy(marks.ignored[row.reset], "nor its reset arrow")
    T.truthy(marks.anchor[row], "the cursor at its left end")
    clearAll(); clearMarks()
end)

T.test("pad options: a slider row takes left and right while it has the D-pad, and gives them back", function()
    local DUI, pf = optionsOnPad()
    local row = rowWhere(pf, function(r) return r.item.key == "softness" end)
    local before = DUI:Get("general", "softness")
    row.OnSmartNavSelect()
    T.truthy(row.hl:IsShown(), "lit as under the mouse")
    T.truthy(stub.overrides.PADDRIGHT and stub.overrides.PADDLEFT, "left and right taken")
    local right = _G[stub.overrides.PADDRIGHT.click]
    right:GetScript("OnClick")(right, "LeftButton", true)
    right:GetScript("OnClick")(right, "LeftButton", false)
    local step = row.item.step or 1
    T.eq(DUI:Get("general", "softness"), math.min(row.item.max, before + step), "one step right")
    -- Repeats while held, stops on release.
    local v = DUI:Get("general", "softness")
    local left = _G[stub.overrides.PADDLEFT.click]
    left:GetScript("OnClick")(left, "LeftButton", true)
    stub.RunTimers()
    T.truthy(DUI:Get("general", "softness") < v - step / 2, "held: more than one step")
    left:GetScript("OnClick")(left, "LeftButton", false)
    row.OnSmartNavDeselect()
    T.eq(stub.overrides.PADDRIGHT, nil, "given back to the D-pad")
    T.falsy(row.hl:IsShown())
    clearAll(); clearMarks()
end)

T.test("pad options: left and right step a dropdown through its choices; A opens it, flips a switch", function()
    local DUI, pf = optionsOnPad()
    local dd = rowWhere(pf, function(r)
        return r.item.type == "dropdown" and type(r.item.values) == "table" and not r.disabled
    end)
    T.truthy(dd, "a dropdown on the page")
    local keys = dd.item.order or DUI.Widgets.SortedKeys(dd.item.values)
    local cur = DUI.Options.Get(dd.page, dd.item)
    local at
    for i, k in ipairs(keys) do if k == cur then at = i end end
    local want = keys[at + 1] or keys[at]
    dd.OnSmartNavSelect()
    dd.padStep(1)
    T.eq(DUI.Options.Get(dd.page, dd.item), want, "the next choice")
    dd.OnSmartNavClick()
    T.eq(DUI.Widgets.menuOwner, dd.control, "A opens the list")
    DUI.Widgets.CloseMenu()
    dd.OnSmartNavDeselect()
    local sw = rowWhere(pf, function(r) return r.item.type == "toggle" and not r.disabled end)
    local was = DUI.Options.Get(sw.page, sw.item) == true
    sw.OnSmartNavClick()
    T.eq(DUI.Options.Get(sw.page, sw.item) == true, not was, "A flips it")
    clearAll(); clearMarks()
end)

T.test("pad options: Y puts a changed row back; LB and RB step the page's tabs or pages", function()
    local DUI, pf = optionsOnPad()
    local f = DUI.OptionsPanel.Frame()
    local row = rowWhere(pf, function(r) return r.item.key == "softness" end)
    local start = DUI.Options.Get(row.page, row.item)
    DUI.Options.Set(row.page, row.item, start == row.item.max and row.item.min or row.item.max)
    stub.RunTimers()   -- a General change repaints the frame on the next timer
    local y
    for _, e in ipairs(f.padKeys) do if e.key == "Y" then y = e end end
    T.truthy(y.when(row), "offered once changed")
    y.run(row)
    T.truthy(DUI.Options.IsDefault(row.page, row.item), "back to its default")
    local list, at = f.padTabs()
    T.truthy(#list >= 2, "something to step")
    T.truthy(at ~= nil, "the one on show is known")
    T.eq(f.padScroll ~= nil, true, "the right stick scrolls the page")
    clearAll(); clearMarks()
end)

T.test("pad: a tap does an entry's run, holding it Pad.HOLD s its hold instead, as the game's tap-or-hold", function()
    local DUI = stub.Load()
    fresh(strict(true))
    local f = DUI.Win.New({ name = "PadTestHold", title = "Test" })
    local got = {}
    f.padKeys = { { key = "X", label = "Create", run = function() got[#got + 1] = "tap" end,
                    hold = { label = "Create all", run = function() got[#got + 1] = "hold" end } } }
    f:Show()
    stub.RunTimers()
    local b = _G[stub.overrides.PAD3.click]
    b:GetScript("OnClick")(b, "LeftButton", true)
    b:GetScript("OnClick")(b, "LeftButton", false)
    T.eq(table.concat(got, ","), "tap", "a tap")
    b:GetScript("OnClick")(b, "LeftButton", true)
    stub.RunTimers()
    b:GetScript("OnClick")(b, "LeftButton", false)
    T.eq(table.concat(got, ","), "tap,hold", "held: the hold alone")
    local said = {}
    for _, row in ipairs(DUI.Pad.HintList(f)) do said[#said + 1] = row[2] end
    T.truthy(table.concat(said, "|"):find("Create all", 1, true), "the hint names the hold")
    f:Hide()
    clearAll()
end)

T.test("pad options: the D-pad starts on the page in the list; landing on another shows it; A goes into its first row", function()
    local DUI, pf = optionsOnPad()
    local P = DUI.OptionsPanel
    local f = P.Frame()
    T.eq(f.padFirst(), P.PageButton("appearance"), "starts on the page on show")
    -- A set page, not one picked by pairs(): some pages start with no rows.
    local ids = {}
    for id, b in pairs(P.Nav().pageButtons) do
        if id ~= "appearance" and b:IsShown() then ids[#ids + 1] = id end
    end
    table.sort(ids)
    local other
    for _, id in ipairs(ids) do
        local b = P.Nav().pageButtons[id]
        b.OnSmartNavSelect()
        if P.FirstStop() then other = b; break end
    end
    other.OnSmartNavSelect()
    T.eq(P.Current(), other.page.id, "shown as the D-pad lands on it")
    local aimed
    _G.SmartNavigation = { RefreshButtonGroups = function() end,
        SetTargetButtonForFrame = function(_, _, b) aimed = b end, GetCurrentButton = function() return other end }
    other.OnSmartNavClick()
    stub.RunTimers()
    T.truthy(aimed ~= nil, "the D-pad handed to the page")
    T.eq(aimed, P.FirstStop())
    clearAll(); clearMarks()
end)

T.test("pad options: the game's color picker on the sticks is shown as it moves and saved once it rests or closes", function()
    local DUI = stub.Load({ module = true })
    strict(true)
    local cp = CreateFrame("Frame", "ColorPickerFrame", UIParent)
    local info, rgb = nil, { 1, 0, 0 }
    function cp:SetupColorPickerAndShow(i) info = i; self:Show() end
    function cp:GetColorRGB() return rgb[1], rgb[2], rgb[3] end
    _G.IsMouseButtonDown = function() return false end
    local saved, shown = {}, {}
    DUI.Widgets.OpenColorPicker({ 1, 1, 1 }, function(c) saved[#saved + 1] = c end, false,
        function(c) shown[#shown + 1] = c end)
    for i = 1, 5 do rgb = { i / 10, 0, 0 }; info.swatchFunc() end
    T.eq(#saved, 0, "nothing saved while the stick moves")
    T.eq(#shown, 5, "every step shown")
    stub.RunTimers()
    T.eq(#saved, 1, "saved once at rest")
    T.eq(saved[1][1], 0.5)
    rgb = { 0, 1, 0 }; info.swatchFunc()
    cp:Hide()
    T.eq(#saved, 2, "closing saves the last")
    clearAll()
    _G.ColorPickerFrame = nil
end)

T.test("pad: the right stick scrolls a window's biggest list, and follows it to another page", function()
    local DUI = stub.Load()
    fresh(strict(true))
    local set = {}
    _G.SmartNavigation = { SetScrollFrameForFrame = function(_, f, sf) set[#set + 1] = { f, sf } end,
        RefreshButtonGroups = function() end, SetTargetButtonForFrame = function() end }
    local f = DUI.Win.New({ name = "PadTestScroll", title = "Test" })
    local stacks = {}
    for _, id in ipairs({ "one", "two" }) do
        DUI.Win.AddPage(f, id, { Build = function(page) stacks[id] = DUI.Win.Parts.Stack(page) end })
    end
    DUI.Win.ShowPage(f, "one")
    f:Show()
    stub.RunTimers()
    T.eq(set[#set][2], stacks.one.scroll, "the page's list")
    DUI.Win.ShowPage(f, "two")
    T.eq(set[#set][2], stacks.two.scroll, "the next page's")
    f:Hide()
    clearAll()
end)

T.test("pad: a long dropdown brings the next choice in as the D-pad reaches the last one in view, and back up", function()
    local DUI = stub.Load()
    local m = strict(true)
    function m:HandlePopupShown() end
    function m:HandlePopupHide() end
    local W = DUI.Widgets
    local owner = CreateFrame("Button", nil, UIParent)
    local keys, values = {}, {}
    for i = 1, 30 do keys[i] = i; values[i] = "Choice " .. i end
    W.OpenMenu(owner, keys, values, 1, function() end)
    local function rowFor(n)
        for i = 1, W.MENU_MAX_ROWS + 1 do
            local r = W.MenuRow(i)
            if r and r.index == n then return r end
        end
    end
    local last = rowFor(W.MENU_MAX_ROWS)
    T.truthy(last, "the last row in view")
    last.OnSmartNavSelect(last)
    for _ = 1, 30 do stub.RunTimers(); local d = DUI.Motion.Driver(); if d then stub.RunOnUpdate(d, 0.1) end end
    T.eq(W.MenuRow(1).index, 2, "one more came in at the bottom, the first went out")
    local top = rowFor(2)
    top.OnSmartNavSelect(top)
    for _ = 1, 30 do stub.RunTimers(); local d = DUI.Motion.Driver(); if d then stub.RunOnUpdate(d, 0.1) end end
    T.eq(W.MenuRow(1).index, 1, "back up: the first choice again")
    W.CloseMenu()
    clearAll()
end)

T.test("pad: a secure entry puts the stop's own action on its key, armed again as the D-pad moves", function()
    local DUI = stub.Load()
    fresh(strict(true))
    local f = DUI.Win.New({ name = "PadTestSecure", title = "Test" })
    local one, two, none = CreateFrame("Button", nil, f), CreateFrame("Button", nil, f), CreateFrame("Button", nil, f)
    one.id, two.id = 11, 22
    local at = one
    _G.SmartNavigation = { GetCurrentButton = function() return at end }
    f.padKeys = { { key = "A", label = "Cast",
                    secure = function(b) return b and b.id and { type1 = "spell", spell = b.id } or nil end } }
    f:Show()
    stub.RunTimers()
    local o = stub.overrides.PAD1
    T.truthy(o, "A is taken while a stop has an action")
    local s = _G[o.click]
    T.eq(s:GetAttribute("spell"), 11)
    T.eq(DUI.Pad.HintList(f)[1][2], "Cast")
    at = two
    stub.RunTimers()
    T.eq(s:GetAttribute("spell"), 22, "the D-pad moved: the next row's spell")
    at = none
    stub.RunTimers()
    T.eq(stub.overrides.PAD1, nil, "a stop with nothing to cast leaves A to the game")
    T.eq(s:GetAttribute("spell"), 22)
    T.eq(DUI.Pad.HintList(f)[1][2], ACTION_LABEL_SELECT or "Select")
    f:Hide()
    T.eq(stub.overrides.PAD1, nil)
    clearAll()
end)

-- The controller bars' storage: 3 pages of 28 slots, the top bar's face buttons
-- holding none (ActionBindingUtil.lua).
local function padBars(first, page)
    _G.C_GamepadUI = { GetFirstGamepadActionStorageSlotIndex = function() return first end }
    _G.GamepadMainActionBarFrame = { PageUnit = { PageTracker = { currentPage = page or 1 } } }
end

T.test("pad bind: a press on the bars puts the spell in that slot, triggers and pages picking the bar", function()
    local DUI = stub.Load()
    fresh(strict(true))
    stub.ActionSlots({})
    padBars(200)
    local Pad = DUI.Pad
    T.eq(Pad.SlotOf(1, 0, 1), 200)
    T.eq(Pad.SlotOf(1, 0, 8), nil, "the top bar's face buttons hold nothing")
    T.eq(Pad.SlotOf(1, 1, 1), 204)
    T.eq(Pad.SlotOf(1, 3, 8), 227)
    T.eq(Pad.SlotOf(2, 0, 1), 228)
    local f = DUI.Win.New({ name = "PadTestBind", title = "Test" })
    f.padKeys = { { key = "X", label = "Bind", run = function() end } }
    f:Show()
    stub.RunTimers()
    T.truthy(Pad.BindAction({ name = "Smite", icon = 1, pickup = function() C_Spell.PickupSpell(585) end }))
    T.truthy(Pad.prompt and Pad.prompt:IsShown())
    T.eq(stub.overrides.PAD3.click, Pad.BIND_BUTTON .. "5", "X is a bar button while the prompt waits")
    local said = {}
    for _, row in ipairs(Pad.HintList(Pad.prompt)) do said[#said + 1] = row[2] end
    T.truthy(table.concat(said, "|"):find(CANCEL or "Cancel", 1, true))
    stub.PressKey("PADRSHOULDER")   -- page 2
    local lt = _G[stub.overrides.PADLTRIGGER.click]
    lt:GetScript("OnClick")(lt, "LeftButton", true)
    stub.PressKey("PAD1")
    lt:GetScript("OnClick")(lt, "LeftButton", false)
    T.eq(stub.slots[200 + 28 + 11] and stub.slots[200 + 28 + 11].spellID, 585, "page 2, LT, face down")
    T.eq(stub.cursor, nil)
    T.eq(Pad.prompt, nil)
    T.eq(stub.overrides.PAD3.click, Pad.KEY_BUTTON .. "X", "the window's own X is back")
    T.eq(stub.overrides.PADLTRIGGER, nil)
    f:Hide()
    _G.C_GamepadUI, _G.GamepadMainActionBarFrame = nil, nil
    clearAll()
end)

T.test("pad bind: B on the top bar cancels, and a fight or the window closing ends the prompt", function()
    local DUI = stub.Load()
    fresh(strict(true))
    stub.ActionSlots({})
    padBars(200)
    local Pad = DUI.Pad
    local f = DUI.Win.New({ name = "PadTestBindB", title = "Test" })
    f:Show()
    stub.RunTimers()
    local spec = { name = "Smite", pickup = function() C_Spell.PickupSpell(585) end }
    T.truthy(Pad.BindAction(spec))
    stub.PressKey("PAD2")
    T.eq(Pad.prompt, nil, "B cancels")
    T.eq(next(stub.slots), nil, "nothing placed")
    T.truthy(Pad.BindAction(spec))
    f:Hide()
    T.eq(Pad.prompt, nil, "the window closing ends it")
    T.eq(stub.overrides.PAD1, nil)
    f:Show()
    stub.RunTimers()
    T.truthy(Pad.BindAction(spec))
    stub.SetRestriction("Combat", true)
    T.eq(Pad.prompt, nil, "a fight ends it")
    T.eq(stub.overrides.PAD1, nil, "the bars are the player's again")
    stub.SetRestriction("Combat", false)
    f:Hide()
    _G.C_GamepadUI, _G.GamepadMainActionBarFrame = nil, nil
    clearAll()
end)

T.test("pad: every window's Y opens a row's right-click menu, its left menu button the search", function()
    local DUI = stub.Load()
    fresh(strict(true))
    local f = DUI.Win.New({ name = "PadTestDefaults", title = "Test" })
    local box = DUI.Widgets.Input(f, { search = true })
    local row, plain = CreateFrame("Button", nil, f), CreateFrame("Button", nil, f)
    local menu
    row.lineSpec = { onRightClick = function(b) menu = b end }
    local at = plain
    _G.SmartNavigation = { GetCurrentButton = function() return at end, SetScrollFrameForFrame = function() end }
    f:Show()
    stub.RunTimers()
    T.eq(stub.overrides.PAD4, nil, "a stop without a menu leaves Y to the game")
    T.truthy(stub.overrides.PADBACK, "the search box is found")
    local focused = false
    box.SetFocus = function() focused = true end   -- the fake game's boxes never hold focus
    _G[stub.overrides.PADBACK.click]:Click()
    T.truthy(focused)
    at = row
    stub.RunTimers()
    T.truthy(stub.overrides.PAD4, "Y on a row with a menu")
    _G[stub.overrides.PAD4.click]:Click()
    T.eq(menu, row)
    f:Hide()
    clearAll()
end)

T.test("pad: X presses the page footer's main button on a window that doesn't bind X itself", function()
    local DUI = stub.Load()
    fresh(strict(true))
    local f = DUI.Win.New({ name = "PadTestFooter", title = "Test" })
    local foot = DUI.Win.Parts.Footer(f)
    local invited = 0
    local off = false
    local function paint() foot:Set({ { text = "Invite", primary = true, off = off, onClick = function() invited = invited + 1 end },
                                      { text = "Whisper", onClick = function() end } }) end
    paint()
    _G.SmartNavigation = { GetCurrentButton = function() return nil end, SetScrollFrameForFrame = function() end }
    f:Show()
    stub.RunTimers()
    T.truthy(stub.overrides.PAD3)
    local said = {}
    for _, row in ipairs(DUI.Pad.HintList(f)) do said[#said + 1] = row[2] end
    T.truthy(table.concat(said, "|"):find("Invite", 1, true))
    _G[stub.overrides.PAD3.click]:Click()
    T.eq(invited, 1)
    off = true
    paint()
    DUI.Pad.Refresh(f)
    T.eq(stub.overrides.PAD3, nil, "a main button that's off leaves X alone")
    f:Hide()
    f.padKeys = { { key = "X", label = "Own", run = function() end } }
    off = false
    paint()
    f:Show()
    stub.RunTimers()
    said = {}
    for _, row in ipairs(DUI.Pad.HintList(f)) do said[#said + 1] = row[2] end
    T.falsy(table.concat(said, "|"):find("Invite", 1, true), "a window's own X wins")
    f:Hide()
    clearAll()
end)
