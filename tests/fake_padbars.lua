-- The game's controller bars in the fake game (Blizzard_GamepadActionBars):
-- GamepadMainActionBarFrame.PageUnit.actionBars, each bar's eight buttons on the
-- real action button template plus what GamepadActionBarButtonTemplate adds, and
-- GamepadActionBarStyleUtil's restyle as the game does it. On every press and
-- every expand or collapse it runs SetShapeToSquare/Circle (ActionBarButton.lua),
-- which writes the border, pushed, highlight and checked art again, plus the swipe
-- on the round ones. Sizes and spots come from ActionBarStyles.lua; where a whole
-- bar sits is only a plausible spot, for tools/snap.lua.

local F = {}

local SQUARE = { collapsed = 32, expanded = 40, shape = "SetShapeToSquare" }
local CIRCLE = { collapsed = 30, expanded = 38, shape = "SetShapeToCircle" }
local PUSHED = -4
-- left, top, right, bottom of each cross (ActionBarStyles.lua)
local SPOTS = {
    collapsed = { size = { 208, 68 }, left = { { -92, 0 }, { -58, 17 }, { -24, 0 }, { -58, -17 } },
                  right = { { 25, 0 }, { 55, 18 }, { 85, 0 }, { 55, -18 } } },
    expanded = { size = { 266, 86 }, left = { { -119, 0 }, { -75, 23 }, { -31, 0 }, { -75, -23 } },
                 right = { { 32, 0 }, { 70, 23 }, { 108, 0 }, { 70, -23 } } },
}
local SHADOWS = { "CircleShadow", "CircleShadowFocus", "SquareShadow", "SquareShadowFocus",
                  "CircleGlowFocus", "SquareGlowFocus" }

local function shapeTo(b, kind, circle)
    b.IconMask:Hide()
    b.CircleMask:SetShown(circle)
    b.SquareMask:SetShown(not circle)
    b.CircleShadow:SetShown(circle)
    b.SquareShadow:SetShown(not circle)
    b:SetNormalAtlas("gamepad-actionbar-" .. kind .. "slot-border-normal")
    b:SetPushedAtlas("gamepad-actionbar-" .. kind .. "slot-border-pressed")
    b.HighlightTexture:SetAtlas("gamepad-actionbar-" .. kind .. "slot-border-hover")
    b:SetCheckedTexture("gamepad-actionbar-" .. kind .. "slot-border-selected")
    if circle then b.cooldown:SetSwipeTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    b.Border:SetAtlas("gamepad-actionbar-" .. kind .. "slot-iconframe-border")
end

local function makeButton(parent, name)
    local b = CreateFrame("CheckButton", name, parent, "ActionBarButtonTemplate")
    b.__game = true
    b.CircleMask, b.SquareMask = b:CreateMaskTexture(), b:CreateMaskTexture()
    b.CircleMask:Hide(); b.SquareMask:Hide()
    b.icon:AddMaskTexture(b.CircleMask); b.icon:AddMaskTexture(b.SquareMask)
    b.SpecialActionIcon = b:CreateTexture(); b.SpecialActionIcon:Hide()
    b.SpecialActionIcon:AddMaskTexture(b.CircleMask)
    b.SpecialActionIcon.__points = { { "ALL", b } }
    for _, k in ipairs(SHADOWS) do
        b[k] = b:CreateTexture()
        b[k]:SetAtlas("gamepad-actionbar-" .. k)
        b[k]:Hide()
    end
    b.ButtonIcon = CreateFrame("Frame", nil, b)
    b.ButtonIcon.__w, b.ButtonIcon.__h = 15, 15
    b.ButtonIcon.__points = { { "TOPRIGHT", b, "TOPRIGHT", -1, -1 } }
    b.ButtonIcon.art = b.ButtonIcon:CreateTexture()
    b.ButtonIcon.art.__points = { { "ALL", b.ButtonIcon } }
    function b.cooldown:SetSwipeTexture(t) self.__swipeTexture = t end
    function b:SetNormalAtlas(a) self:GetNormalTexture():SetAtlas(a) end
    function b:SetPushedAtlas(a) self:GetPushedTexture():SetAtlas(a) end
    function b:SetCheckedTexture(a) self:GetCheckedTexture():SetAtlas(a) end
    function b:SetShapeToSquare() shapeTo(self, "square", false) end
    function b:SetShapeToCircle() shapeTo(self, "circle", true) end
    function b:IsPopupOpen() return false end
    function b:Collapse() end
    function b:Expand() end
    function b:ApplyPressedStyle(down) self:ApplyExtraButtonStylesForState(down and "PUSHED" or "NORMAL") end
    return b
end

local Util = {}

-- The steps of GamepadActionBarStyleUtil.ApplyExtraButtonStyles, line for line.
function Util.ApplyExtraButtonStyles(button, actionState, focusState, styleParams, anchorInfo)
    local size, method = styleParams.collapsed, "Collapse"
    local x, y = anchorInfo.x, anchorInfo.y
    if actionState == "PUSHED" then
        y = y + PUSHED / 2
        size = size + PUSHED
    end
    if focusState == "expanded" then
        size, method = styleParams.expanded, "Expand"
    end
    button[styleParams.shape](button)
    button:SetSize(size, size)
    button:ClearAllPoints()
    button:SetPoint("CENTER", anchorInfo.relativeTo, "CENTER", x, y)
    button[method](button)
end

local function restyle(bar, focus)
    local spots = SPOTS[focus]
    bar:SetSize(spots.size[1], spots.size[2])
    for i, b in ipairs(bar.actionButtons) do
        local round = i > 4
        local spot = round and spots.right[i - 4] or spots.left[i]
        function b.ApplyExtraButtonStylesForState(button, state)
            GamepadActionBarStyleUtil.ApplyExtraButtonStyles(button, state, focus, round and CIRCLE or SQUARE,
                { relativeTo = bar, x = spot[1], y = spot[2] })
        end
        b:ApplyExtraButtonStylesForState(b:GetButtonState())
        if focus == "expanded" then         -- the checked art grows past the button
            b.CheckedTexture:SetPoint("TOPLEFT", -4, 4)
            b.CheckedTexture:SetPoint("BOTTOMRIGHT", 4, -4)
        end
    end
end
function Util.ApplyExpandedActionBarStyle(bar) restyle(bar, "expanded") end
function Util.ApplyCollapsedActionBarStyle(bar) restyle(bar, "collapsed") end

local function makeBar(parent, name, x, y)
    local bar = CreateFrame("Frame", name, parent)
    bar:SetPoint("CENTER", parent, "CENTER", x, y)
    bar.BackgroundFocus = bar:CreateTexture()
    bar.BackgroundFocus:SetAtlas("gamepad-actionbar-focus-bg-section")
    bar.BackgroundFocus:Hide()
    bar.actionButtons = {}
    for i = 1, 8 do bar.actionButtons[i] = makeButton(bar, name .. "Button" .. i) end
    Util.ApplyCollapsedActionBarStyle(bar)
    return bar
end

-- The game's frames, with its controller UI on. Returns the main frame.
function F.Install()
    _G.GamepadActionBarStyleUtil = {
        ApplyExtraButtonStyles = Util.ApplyExtraButtonStyles,
        ApplyExpandedActionBarStyle = Util.ApplyExpandedActionBarStyle,
        ApplyCollapsedActionBarStyle = Util.ApplyCollapsedActionBarStyle,
    }
    local main = CreateFrame("Frame", "GamepadMainActionBarFrame", UIParent)
    main:SetSize(760, 202)
    main:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 60)
    main.PageUnit = CreateFrame("Frame", nil, main)
    main.PageUnit:SetAllPoints(main)
    main.PageUnit.actionBars = {
        topBar = makeBar(main.PageUnit, "PadFakeTop", 0, 60),
        leftBar = makeBar(main.PageUnit, "PadFakeLeft", -240, 0),
        rightBar = makeBar(main.PageUnit, "PadFakeRight", 240, 0),
        bottomBar = makeBar(main.PageUnit, "PadFakeBottom", 0, -60),
    }
    main.PageUnit.LeftClassAction = makeButton(main.PageUnit, "PadFakeLeftClass")
    main.PageUnit.RightClassAction = makeButton(main.PageUnit, "PadFakeRightClass")
    return main
end

return F
