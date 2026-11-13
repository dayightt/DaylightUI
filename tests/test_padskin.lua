local stub = require("stub")
local Fake = require("fake_padbars")

local ABW = require("abworld")

local function controller(on)
    _G.GamepadMode = { FrameControlsManager = { FrameShown = function() end, FrameHidden = function() end } }
    _G.InputUtil = { IsGamepadUIEnabled = function() return on end }
end

local function setup(on)
    local main
    local DUI = stub.Load({ actionbars = true, before = function()
        ABW.world()
        main = Fake.Install()
        controller(on)
    end })
    stub.RunTimers()
    return DUI, main
end

local function done()
    _G.GamepadMode, _G.InputUtil, _G.GamepadActionBarStyleUtil, _G.GamepadMainActionBarFrame = nil, nil, nil, nil
end

local function Skin() return stub.actionbars.Skin end

T.test("padskin: a mouse player's game bars aren't touched", function()
    local DUI, main = setup(false)
    local b = main.PageUnit.actionBars.topBar.actionButtons[1]
    T.falsy(Skin().IsSkinned(b))
    T.eq(b:GetNormalTexture().__atlas, "gamepad-actionbar-squareslot-border-normal", "the game's art stays")
    done()
end)

T.test("padskin: every button of the game's bars wears the look, none moved or rebuilt", function()
    local DUI, main = setup(true)
    for _, bar in pairs(main.PageUnit.actionBars) do
        for i, b in ipairs(bar.actionButtons) do
            T.truthy(Skin().IsSkinned(b))
            T.eq(b:GetParent(), bar, "still the game's bar's")
            T.eq(b:GetNormalTexture():GetAlpha(), 0, "its border art is gone")
        end
        T.eq(bar.BackgroundFocus.__atlas, nil, "no gold haze behind the bar in focus")
    end
    T.eq(main.PageUnit.actionBars.stanceBar.BackgroundWatermark.__atlas, nil, "no wings behind the stance bar")
    T.truthy(Skin().IsSkinned(main.PageUnit.LeftClassAction), "a class's flyout button too")
    done()
end)

T.test("padskin: the D-pad side is square, the face buttons round, as the game has them", function()
    local DUI, main = setup(true)
    local bar = main.PageUnit.actionBars.topBar
    T.falsy(Skin().GetParts(bar.actionButtons[1]).shape, "a D-pad button")
    T.eq(Skin().GetParts(bar.actionButtons[5]).shape, "circle", "a face button")
    done()
end)

T.test("padskin: a press keeps the look though the game writes its art again", function()
    local DUI, main = setup(true)
    local b = main.PageUnit.actionBars.topBar.actionButtons[5]
    local swipe = b.cooldown.__swipeTexture
    local pushed = b:GetPushedTexture().__color
    T.truthy(pushed, "our pressed color")
    b:ApplyPressedStyle(true)
    T.eq(b:GetNormalTexture():GetAlpha(), 0)
    T.eq(b:GetPushedTexture().__atlas, nil, "the game's pressed border isn't left on")
    T.truthy(b:GetPushedTexture().__color)
    T.eq(b:GetCheckedTexture().__atlas, nil)
    T.eq(b:GetHighlightTexture().__atlas, nil)
    T.eq(b.cooldown.__swipeTexture, swipe, "the look's sweep, not the game's")
    T.eq(Skin().GetParts(b).press:GetAlpha(), 1, "our pressed look shows")
    b:ApplyPressedStyle(false)
    T.eq(Skin().GetParts(b).press:GetAlpha(), 0)
    done()
end)

T.test("padskin: a bar in focus grows the game's way and keeps the look", function()
    local DUI, main = setup(true)
    local bar = main.PageUnit.actionBars.leftBar
    GamepadActionBarStyleUtil.ApplyExpandedActionBarStyle(bar)
    local b = bar.actionButtons[1]
    T.eq(b:GetWidth(), 40, "the game's size")
    T.eq(b:GetNormalTexture():GetAlpha(), 0)
    local icon = b.icon
    local p = b:GetCheckedTexture().__points
    T.eq(#p, 1); T.eq(p[1][1], "ALL"); T.eq(p[1][2], icon, "the checked wash stays on the icon")
    GamepadActionBarStyleUtil.ApplyCollapsedActionBarStyle(bar)
    T.eq(b:GetWidth(), 32)
    done()
end)

T.test("padskin: an empty slot still shows where it is, a special one is full", function()
    local DUI, main = setup(true)
    local top = main.PageUnit.actionBars.topBar
    T.truthy(Skin().GetParts(top.actionButtons[2]).back:GetAlpha() > 0, "the cross keeps its shape")
    local jump = top.actionButtons[8]
    jump.SpecialActionIcon:Show()
    Skin().UpdateEmpty(jump, true)
    T.eq(Skin().GetParts(jump).back:GetAlpha(), 1, "Jump isn't an empty slot")
    done()
end)

T.test("padskin: buttons keep no keybind text of ours: the game's button picture says it", function()
    local DUI, main = setup(true)
    local b = main.PageUnit.actionBars.topBar.actionButtons[1]
    b.HotKey:SetText("LT")
    Skin().UpdateKey(b)
    T.eq(Skin().GetParts(b).key:GetText() or "", "")
    done()
end)

T.test("padskin: switched on in a fight it waits for the fight's end", function()
    local DUI = stub.Load({ actionbars = true, before = ABW.world })
    local main = Fake.Install()
    controller(true)
    stub.EnterCombat()
    DUI.Fire("PadChanged")
    stub.RunTimers()
    local b = main.PageUnit.actionBars.topBar.actionButtons[1]
    T.falsy(Skin().IsSkinned(b))
    stub.LeaveCombat()
    stub.RunTimers()
    T.truthy(Skin().IsSkinned(b))
    done()
end)
