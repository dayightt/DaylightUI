-- The game's controller bars in the action bars' look. Nothing is rebuilt: the
-- buttons, their keys, positions, paging and growing stay the game's, and ns.Skin
-- dresses them the way it dresses the stance and pet buttons. The D-pad side stays
-- square and the face buttons round, as the game has them.
--
-- The game rewrites each button's art on every press and every time a bar grows or
-- shrinks, with no event for it. So ours is reapplied from a post-hook on
-- GamepadActionBarStyleUtil, a plain table of functions that all of that passes
-- through (allowed in tests/guards_allow.lua).

local _, ns = ...
local DUI = DaylightUI

local PadSkin = {}
ns.PadSkin = PadSkin

PadSkin.BARS = { "topBar", "leftBar", "rightBar", "bottomBar", "possessBar", "stanceBar",
                 "friendlyTargetingBar", "hostileTargetingBar", "shortcutsBar" }
-- Art that only the XML sets, emptied once. An alpha of ours wouldn't hold, since the
-- game's focus animations end by setting theirs.
PadSkin.BLANK = { "CircleShadow", "CircleShadowFocus", "SquareShadow", "SquareShadowFocus",
                  "CircleGlowFocus", "SquareGlowFocus" }
PadSkin.SINGLES = { "LeftClassAction", "RightClassAction" }
PadSkin.ROUND_FROM = 5     -- buttons from this index on are a bar's face buttons

local hooked = false

local function unitOf()
    local main = _G.GamepadMainActionBarFrame
    local unit = type(main) == "table" and main.PageUnit
    return type(unit) == "table" and type(unit.actionBars) == "table" and unit or nil
end

local function each(bar, fn)
    local list = type(bar) == "table" and bar.actionButtons
    if type(list) ~= "table" then return end
    for i, b in ipairs(list) do fn(b, i) end
end

local function redressBar(bar)
    each(bar, function(b) ns.Skin.Redress(b) end)
end

local function hook()
    if hooked then return end
    hooked = true
    hooksecurefunc(GamepadActionBarStyleUtil, "ApplyExtraButtonStyles", function(button, state)
        ns.Skin.Redress(button, state == "PUSHED")
    end)
    hooksecurefunc(GamepadActionBarStyleUtil, "ApplyExpandedActionBarStyle", redressBar)
    hooksecurefunc(GamepadActionBarStyleUtil, "ApplyCollapsedActionBarStyle", redressBar)
end

local function dress(b, i, bar)
    for _, key in ipairs(PadSkin.BLANK) do
        local tex = b[key]
        if type(tex) == "table" and tex.SetTexture then tex:SetTexture(nil) end
    end
    if bar.isGamepadPossessBar then ns.Skin.SetPet(b) end
    ns.Skin.SetPad(b, i >= PadSkin.ROUND_FROM)
    ns.Skin.Apply(b)
end

-- Every bar's buttons, redone on a look change. Controller UI only; for a mouse
-- player the game keeps these frames as they are.
function PadSkin.Apply()
    if not DUI.Pad.On() then return end
    if InCombatLockdown() then
        DUI.AfterCombat(PadSkin.Apply, "actionbars:padskin")
        return
    end
    local unit = unitOf()
    if not unit or type(GamepadActionBarStyleUtil) ~= "table" then return end
    hook()
    for _, key in ipairs(PadSkin.BARS) do
        local bar = unit.actionBars[key]
        each(bar, function(b, i) dress(b, i, bar) end)
        local focus = type(bar) == "table" and bar.BackgroundFocus
        if type(focus) == "table" and focus.SetTexture then focus:SetTexture(nil) end
    end
    -- The shoulder and trigger buttons that open a class's flyouts have no bar of their own.
    for _, key in ipairs(PadSkin.SINGLES) do
        if type(unit[key]) == "table" then dress(unit[key], 1, unit) end
    end
end

DUI.On("PadChanged", PadSkin.Apply)
