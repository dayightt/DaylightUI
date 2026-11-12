-- Daylight UI windows on a controller.
-- The game only gives the D-pad to windows it opened itself (ShowUIPanel), so
-- our windows have to announce themselves through
-- GamepadMode.FrameControlsManager's FrameShown / FrameHidden. Those are safe
-- for addons out of combat (the game wraps both); in combat they're refused
-- with "action blocked".
--   Pad.On()                 whether the game's controller UI is on
--   Pad.Follow(frame, close) keeps the game informed about frame; close is
--                            what B does. With frame.padSecond, opening next
--                            to another window leaves that one the focus
--                            (the bag)
--   Pad.Forget(frame)        removes a game window parked behind ours from the
--                            game's list, so the D-pad never lands on it
--   Pad.Remember(frame)      puts it back on the list
--   Pad.Popup(frame, close)  a dropdown: takes the D-pad, then gives it back
--   Pad.Rescan(frame)        makes the game find a changed window's stops again
--   Pad.KeepOff(frame)       every frame while a parked game window is shown,
--                            since the game re-lists it on every page it opens
--   Pad.Settle(aim)          a list changed: the game finds its stops on the
--                            next frame, and the D-pad goes to aim (a button)
--                            or off a row that's gone
--   frame.padFirst()         the button the D-pad starts on, once per opening
--   entry.hold               { label, run(stop), when(stop) }: held for
--                            Pad.HOLD s instead of tapped (tap-or-hold)
--   frame.padTabs()          returns (list, at) for what LB / RB step through
--                            (default f.tabs); frame.padTabsLabel names them
--   frame.padScroll          the scroll frame the right stick scrolls (else the
--                            biggest one shown, see Pad.FindScroll; call
--                            Pad.Scrolls after a page change, Win.ShowPage)
--   stop.padStep(dir)        left / right change this stop's value (Pad.HoldSides
--                            while it has the D-pad, see W.PadRow);
--                            stop.padStepLabel names it
--
-- Combat hands the controller back. Every window the game knows about is
-- taken off its list right as the fight starts, the last moment it listens.
-- A window closed later couldn't be removed, and a listed window keeps the
-- game's input catcher blocking the D-pad and face buttons, abilities
-- included. Windows still open go back on the list when the fight ends. In
-- between they work with the mouse only, like windows opened in combat always
-- did.
--
-- The game's D-pad handling only has A and B. Every other button belongs to
-- the window, as on the game's own windows (merchant X buys a stack, mail X
-- opens all...). While one of our windows has focus (the game calls
-- FocusGamepad / UnfocusGamepad on it), LB / RB step through its tabs and
-- these are bound and listed in a small bar under it:
--   frame.padKeys            { { key = "X"|"Y"|"MENU_LEFT"|"MENU_RIGHT", label,
--                              run(stop), when(stop) }, ... }
--   frame.padSelect(stop)    what A says on this stop ("Buy", "Train"); nil = Select
--   entry.click              a game button's name; the key clicks it securely
--                            (the spellbook's micro button). Bound only while
--                            when() is true with no stop. Call
--                            Pad.Refresh(frame) after the window changes
-- An entry whose when() returns false is hidden and does nothing.
local ADDON_NAME, DUI = ...

local L = DUI.L
local Pad = {}
DUI.Pad = Pad

Pad.KEY_BUTTON = "DaylightUIPadKey" -- plus the key, e.g. DaylightUIPadKeyX
Pad.PREV_TAB = "DaylightUIPadPrevTab"
Pad.NEXT_TAB = "DaylightUIPadNextTab"

local told = setmetatable({}, { __mode = "k" }) -- frames the game knows are open
Pad.aimed = setmetatable({}, { __mode = "k" }) -- padFirst already ran for this opening
local followed = setmetatable({}, { __mode = "k" }) -- every frame we keep the game informed about
local fight = false -- handed back, fight not over yet

local function manager()
    if type(InputUtil) ~= "table" or type(InputUtil.IsGamepadUIEnabled) ~= "function" then return nil end
    if not InputUtil.IsGamepadUIEnabled() then return nil end
    return type(GamepadMode) == "table" and GamepadMode.FrameControlsManager or nil
end

function Pad.On() return manager() ~= nil end

-- The window's own buttons, LB, RB

local keys -- the frame our keys are bound on (created once, out of combat)

local function key(name, fallback)
    local k = _G[name]
    return type(k) == "string" and k or fallback
end

-- The game's key name for each of a window's buttons.
Pad.KEYS = {
    X = { "GAMEPAD_FACE_LEFT", "PAD3" },
    Y = { "GAMEPAD_FACE_TOP", "PAD4" },
    MENU_LEFT = { "GAMEPAD_MENU_LEFT", "PADBACK" },
    MENU_RIGHT = { "GAMEPAD_MENU_RIGHT", "PADFORWARD" },
}
local function keyOf(name) return key(Pad.KEYS[name][1], Pad.KEYS[name][2]) end

-- The stop the D-pad is on: a button, or a frame that takes clicks (a gear slot).
local function stop()
    local nav = _G.SmartNavigation
    local b = type(nav) == "table" and nav.GetCurrentButton and nav:GetCurrentButton() or nil
    return type(b) == "table" and b or nil
end
Pad.Stop = stop

-- The visible tabs and which one is picked. frame.padTabs() can supply its
-- own (list, at): the options window's page tabs, else its pages.
local function tabsOf(f)
    if type(f.padTabs) == "function" then
        local list, at = f.padTabs()
        return type(list) == "table" and list or {}, at
    end
    local out, at = {}, nil
    if type(f.tabs) ~= "table" then return out end
    local current = f.tab or f.current
    for _, b in ipairs(f.tabs) do
        if b:IsShown() then
            out[#out + 1] = b
            if b.id == current then at = #out end
        end
    end
    return out, at
end

function Pad.StepTab(dir)
    local f = Pad.focused
    if not f then return end
    local list, at = tabsOf(f)
    if #list < 2 then return end
    list[((at or 1) - 1 + dir) % #list + 1]:Click()
end

-- The focused window's entry for a key, if it can act on the stop right now.
local function entryFor(f, name, at)
    if not (f and type(f.padKeys) == "table") then return nil end
    for _, e in ipairs(f.padKeys) do
        if e.key == name and (not e.when or e.when(at)) then return e end
    end
end

-- An entry with hold = { label, run, when } runs normally on a tap and runs
-- hold.run once the key is held Pad.HOLD s, like the game's tap-or-hold
-- buttons (CreateTapOrHoldPromptedBinding, e.g. Create / Create all).
Pad.HOLD = 0.5
local holding

local pressed = {}
function Pad.Press(name, down)
    if down == false then
        -- A key up with no key down before it is a click from code, so treat it as a full press.
        if not pressed[name] then return Pad.Press(name, true) or Pad.Press(name, false) end
        pressed[name] = nil
        local h = holding
        holding = nil
        if h and h.name == name and not h.done then h.e.run(h.at) end
        return
    end
    pressed[name] = true
    local at = stop()
    local e = entryFor(Pad.focused, name, at)
    if not e then return end
    if not e.hold then return e.run(at) end
    local h = { name = name, e = e, at = at }
    holding = h
    C_Timer.After(Pad.HOLD, function()
        if holding ~= h then return end
        h.done = true
        if not e.hold.when or e.hold.when(at) then e.hold.run(at) end
    end)
end

local function buildKeys()
    if keys then return end
    keys = CreateFrame("Frame", nil, UIParent)
    for name, dir in pairs({ [Pad.PREV_TAB] = -1, [Pad.NEXT_TAB] = 1 }) do
        local b = CreateFrame("Button", name, UIParent)
        b:RegisterForClicks("AnyDown")
        b:SetScript("OnClick", function() Pad.StepTab(dir) end)
    end
    for name in pairs(Pad.KEYS) do
        local b = CreateFrame("Button", Pad.KEY_BUTTON .. name, UIParent)
        b:RegisterForClicks("AnyDown", "AnyUp")
        b:SetScript("OnClick", function(_, _, down) Pad.Press(name, down ~= false) end)
    end
end

-- D-pad left and right, taken while a stop that changes a value has focus (a
-- slider or dropdown row in the options), like the game's own Settings window
-- (Blizzard_SettingControls.lua). Holding repeats. The game's binding footer
-- isn't wrapped and writing to it taints, so this is our own override
-- binding, like X and Y.
Pad.SIDE_LEFT, Pad.SIDE_RIGHT = "DaylightUIPadLeft", "DaylightUIPadRight"
Pad.REPEAT_WAIT, Pad.REPEAT_EVERY = 0.35, 0.07
local sides, sideFn, held

local function press(dir)
    local fn = sideFn
    if not fn then return end
    local token = {}
    held = token
    fn(dir)
    local function again()
        if held ~= token or sideFn ~= fn then return end
        fn(dir)
        C_Timer.After(Pad.REPEAT_EVERY, again)
    end
    C_Timer.After(Pad.REPEAT_WAIT, again)
end

-- fn(dir): -1 left, 1 right. Out of combat only (combat hands the controller back).
function Pad.HoldSides(fn)
    if not manager() or fight or InCombatLockdown() then return end
    sideFn, held = fn, nil
    if not sides then
        sides = CreateFrame("Frame", nil, UIParent)
        for name, dir in pairs({ [Pad.SIDE_LEFT] = -1, [Pad.SIDE_RIGHT] = 1 }) do
            local b = CreateFrame("Button", name, UIParent)
            b:RegisterForClicks("AnyDown", "AnyUp")
            b:SetScript("OnClick", function(_, _, down)
                if down then press(dir) else held = nil end
            end)
        end
    end
    ClearOverrideBindings(sides)
    SetOverrideBindingClick(sides, true, key("GAMEPAD_DPAD_LEFT", "PADDLEFT"), Pad.SIDE_LEFT)
    SetOverrideBindingClick(sides, true, key("GAMEPAD_DPAD_RIGHT", "PADDRIGHT"), Pad.SIDE_RIGHT)
end

-- Gives left/right back to D-pad movement, but only if fn is still the holder.
function Pad.FreeSides(fn)
    if fn and sideFn ~= fn then return end
    sideFn, held = nil, nil
    if sides and not InCombatLockdown() then ClearOverrideBindings(sides) end
end

function Pad.HoldingSides() return sideFn ~= nil end

local function unbind()
    if keys then ClearOverrideBindings(keys) end
    Pad.FreeSides()
end

local function bind(f)
    buildKeys()
    ClearOverrideBindings(keys)
    if #tabsOf(f) > 1 then
        SetOverrideBindingClick(keys, true, key("GAMEPAD_SHOULDER_LEFT", "PADLSHOULDER"), Pad.PREV_TAB)
        SetOverrideBindingClick(keys, true, key("GAMEPAD_SHOULDER_RIGHT", "PADRSHOULDER"), Pad.NEXT_TAB)
    end
    local done = {}
    for _, e in ipairs(type(f.padKeys) == "table" and f.padKeys or {}) do
        if not done[e.key] then
            if not e.click then
                done[e.key] = true
                SetOverrideBindingClick(keys, true, keyOf(e.key), Pad.KEY_BUTTON .. e.key)
            elseif (not e.when or e.when(nil)) and _G[e.click] then
                done[e.key] = true
                SetOverrideBindingClick(keys, true, keyOf(e.key), e.click)
            end
        end
    end
end

-- A window changed what it shows (the NPC window going from a quest to a
-- trainer), so rebind and relabel its buttons.
function Pad.Refresh(f)
    if Pad.focused ~= f or InCombatLockdown() then return end
    bind(f)
    Pad.ShowHints(f)
end

-- Button hints under the window

-- The game's own glyphs (they match the controller: Xbox, PlayStation...)
-- in Daylight UI's shell. The game's footer can't be used: it isn't wrapped,
-- so writing to it taints the controller code.
Pad.HINT_GAP, Pad.HINT_ICON, Pad.HINT_PAD = 6, 18, 12

local hints

local function hintPiece(i)
    local p = hints.pieces[i]
    if p then return p end
    p = CreateFrame("Frame", nil, hints)
    p:SetHeight(Pad.HINT_ICON)
    p.icons = {}
    p.text = DUI.Style.Text(p, DUI.Style.SIZE.small, "LEFT")
    hints.pieces[i] = p
    return p
end

local function hintIcon(p, n)
    local ic = p.icons[n]
    if ic then return ic end
    ic = CreateFrame("Frame", nil, p, "InputIconTextureFrameTemplate")
    ic:SetSize(Pad.HINT_ICON, Pad.HINT_ICON)
    ic:SetPoint("LEFT", p, "LEFT", (n - 1) * (Pad.HINT_ICON + 2), 0)
    p.icons[n] = ic
    return ic
end

-- What the buttons do in this window, in the game's order: A, the window's
-- own buttons, tabs, windows, B.
function Pad.HintList(f)
    local m = manager()
    local at = stop()
    local out = {}
    -- padSelect may return false, meaning A does nothing on this stop (a slider row).
    local a = f.padSelect and f.padSelect(at)
    if a ~= false then out[1] = { { key("GAMEPAD_FACE_BOTTOM", "PAD1") }, a or ACTION_LABEL_SELECT or L["Select"] } end
    if at and at.padStep and not at.disabled then
        out[#out + 1] = { { key("GAMEPAD_DPAD_LEFT", "PADDLEFT"), key("GAMEPAD_DPAD_RIGHT", "PADDRIGHT") },
                          at.padStepLabel or L["Change"] }
    end
    local done = {}
    for _, e in ipairs(type(f.padKeys) == "table" and f.padKeys or {}) do
        if not done[e.key] and (not e.when or e.when(e.click and nil or at)) then
            done[e.key] = true
            out[#out + 1] = { { keyOf(e.key) }, type(e.label) == "function" and e.label(at) or e.label }
            local h = e.hold
            if h and (not h.when or h.when(at)) then
                out[#out + 1] = { { keyOf(e.key) }, string.format(L["Hold: %s"],
                    type(h.label) == "function" and h.label(at) or h.label) }
            end
        end
    end
    if #tabsOf(f) > 1 then
        out[#out + 1] = { { key("GAMEPAD_SHOULDER_LEFT", "PADLSHOULDER"),
                            key("GAMEPAD_SHOULDER_RIGHT", "PADRSHOULDER") }, f.padTabsLabel or L["Tabs"] }
    end
    if m and type(m.shownFrames) == "table" and #m.shownFrames > 1 then
        out[#out + 1] = { { key("GAMEPAD_TRIGGER_LEFT", "PADLTRIGGER"),
                            key("GAMEPAD_TRIGGER_RIGHT", "PADRTRIGGER") }, L["Windows"] }
    end
    out[#out + 1] = { { key("GAMEPAD_FACE_RIGHT", "PAD2") }, FRAME_ACTION_BACK or L["Back"] }
    return out
end

-- A list's labels, used to tell when the bar needs a new layout.
local function said(list)
    local out = {}
    for _, row in ipairs(list) do out[#out + 1] = table.concat(row[1], "+") .. "=" .. tostring(row[2]) end
    return table.concat(out, ";")
end

function Pad.ShowHints(f)
    local Style = DUI.Style
    if not hints then
        hints = CreateFrame("Frame", nil, UIParent)
        hints.pieces = {}
        hints:SetFrameStrata("DIALOG")
        hints:SetHeight(Pad.HINT_ICON + 2 * Pad.HINT_GAP)
        hints:SetClampedToScreen(true)
        Style.Shell(hints, { window = true })
        Pad.hints = hints
    end
    local list = Pad.HintList(f)
    local words = said(list)
    if hints.words == words and hints.owner == f and hints:IsShown() and not hints.gone then return end
    hints.words, hints.owner = words, f
    local x = Pad.HINT_PAD
    for i, row in ipairs(list) do
        local p = hintPiece(i)
        for n, k in ipairs(row[1]) do
            local ic = hintIcon(p, n)
            if ic.SetInputKey then ic:SetInputKey(k) end
            ic:Show()
        end
        for n = #row[1] + 1, #p.icons do p.icons[n]:Hide() end
        local iconW = #row[1] * (Pad.HINT_ICON + 2)
        p.text:ClearAllPoints()
        p.text:SetPoint("LEFT", p, "LEFT", iconW + 2, 0)
        p.text:SetText(row[2])
        Style.InkText(p.text, "LABEL")
        local w = iconW + 2 + p.text:GetStringWidth()
        p:SetWidth(w)
        p:ClearAllPoints()
        p:SetPoint("LEFT", hints, "LEFT", x, 0)
        p:Show()
        x = x + w + Pad.HINT_PAD
    end
    for i = #list + 1, #hints.pieces do hints.pieces[i]:Hide() end
    hints:SetWidth(x)
    hints:ClearAllPoints()
    hints:SetPoint("TOP", f, "BOTTOM", 0, -Pad.HINT_GAP)
    if not hints:IsShown() or hints.gone then
        hints.gone = nil
        hints:Show()
        DUI.Motion.Fade(hints, 0, 1, DUI.Motion.FAST)
    end
end

function Pad.HideHints()
    if not hints or not hints:IsShown() then return end
    hints.gone = true
    DUI.Motion.Fade(hints, 1, 0, DUI.Motion.FAST)
    C_Timer.After(DUI.Motion.FAST, function()
        if hints.gone then
            hints.gone = nil
            hints:Hide()
        end
    end)
end

-- What A, X and Y say depends on the stop, so it's rechecked every
-- Pad.HINT_EVERY s while a window with its own labels has focus. There's no
-- way to know when the D-pad moves short of hooking the game.
Pad.HINT_EVERY = 0.15
local watching
local function watchHints()
    local f = Pad.focused
    if not f or not (f.padSelect or type(f.padKeys) == "table") then watching = nil; return end
    Pad.ShowHints(f)
    C_Timer.After(Pad.HINT_EVERY, watchHints)
end

-- The right stick scrolls a window's list, as the game sets one for each of
-- its windows (SetScrollFrameForFrame): frame.padScroll, else the biggest
-- visible scroll frame in it (the page's list).
function Pad.FindScroll(f)
    local best, area = nil, 0
    local function walk(frame)
        if not frame:IsVisible() then return end
        if frame:IsObjectType("ScrollFrame") then
            local w, h = frame:GetWidth(), frame:GetHeight()
            local a = (type(w) == "number" and type(h) == "number") and w * h or 0
            if not best or a > area then best, area = frame, a end
        end
        for _, child in ipairs({ frame:GetChildren() }) do walk(child) end
    end
    walk(f)
    return best
end

-- After a window shows another page, the stick follows its list.
function Pad.Scrolls(f)
    local nav = _G.SmartNavigation
    if Pad.focused ~= f or fight or InCombatLockdown() or type(nav) ~= "table" or not nav.SetScrollFrameForFrame then return end
    nav:SetScrollFrameForFrame(f, f.padScroll or Pad.FindScroll(f))
end

local function focusGained(self)
    Pad.focused = self
    Pad.Scrolls(self)
    if not watching and (self.padSelect or type(self.padKeys) == "table") then
        watching = true
        C_Timer.After(Pad.HINT_EVERY, watchHints)
    end
    if not InCombatLockdown() then bind(self) end
    Pad.ShowHints(self)
    if self.padFirst and not Pad.aimed[self] then
        Pad.aimed[self] = true
        Pad.Settle(self.padFirst())
    else
        Pad.Settle()
    end
end

local function focusLost(self)
    if Pad.focused ~= self then return end
    Pad.focused = nil
    if not InCombatLockdown() then unbind() end
    Pad.HideHints()
end

-- Telling the game

local function sync(frame)
    local m = manager()
    if not m or fight then return end
    if InCombatLockdown() then
        DUI.AfterCombat(function() sync(frame) end, frame)
        return
    end
    local open = frame:IsShown()
    if open == (told[frame] == true) then return end
    told[frame] = open or nil
    if not open then
        Pad.aimed[frame] = nil
        m:FrameHidden(frame)
    elseif frame.padSecond and m.GetActiveFrame and m:GetActiveFrame() then
        m:FrameShown(frame, nil, false)
    else
        m:FrameShown(frame)
    end
end

function Pad.Follow(frame, close)
    followed[frame] = true
    if close then
        frame.SmartNavigationCloseHandler = function() close(); return true end
    end
    frame.FocusGamepad, frame.UnfocusGamepad = focusGained, focusLost
    -- One frame later, because a game window we replace opens in the same moment
    -- and the D-pad goes to whichever was announced last.
    frame:HookScript("OnShow", function(self) C_Timer.After(0, function() sync(self) end) end)
    frame:HookScript("OnHide", sync)
    if frame:IsShown() then sync(frame) end
end

-- Waits for the fight to end (`takeBack`), each frame's latest request
-- replacing the previous one. Not DUI.AfterCombat, which runs at once when
-- there's no lockdown: the fight is handed back before lockdown starts, so
-- the request would keep calling itself forever.
local waiting = {}

local function later(fn, frame)
    if InCombatLockdown() or fight then
        waiting[frame] = fn
        return true
    end
end

-- A window changed a lot at once, so the game finds its stops again. Only for
-- a window it knows is open (asking about another makes it start following it).
function Pad.Rescan(frame)
    local nav = _G.SmartNavigation
    if not manager() or not told[frame] or fight or InCombatLockdown() then return end
    if type(nav) == "table" and nav.RefreshButtonGroups then nav:RefreshButtonGroups(frame) end
end

-- A parked game window that's still shown goes back on the list, with focus,
-- every time the game opens a page in it (a quest's reward page).
function Pad.KeepOff(frame)
    local m = manager()
    if not m or fight or InCombatLockdown() or type(m.shownFrames) ~= "table" then return end
    for _, listed in ipairs(m.shownFrames) do
        if listed == frame then
            m:FrameHidden(frame)
            return
        end
    end
end

local settling, aimAt

local function settle()
    settling = nil
    local nav, f = _G.SmartNavigation, Pad.focused
    if not f then return end -- aimAt waits for focus
    local aim = aimAt
    aimAt = nil
    if fight or InCombatLockdown() or type(nav) ~= "table" or not nav.RefreshButtonGroups then return end
    nav:RefreshButtonGroups(f)
    if aim and aim:IsVisible() then
        nav:SetTargetButtonForFrame(f, aim)
    else
        local b = nav.GetCurrentButton and nav:GetCurrentButton()
        if b and not b:IsVisible() then nav:SelectTopLeftButton() end
    end
end

function Pad.Settle(aim)
    if not manager() then return end
    aimAt = aim or aimAt
    if settling then return end
    settling = true
    C_Timer.After(0, settle)
end

function Pad.Forget(frame)
    local m = manager()
    if not m or later(function() Pad.Forget(frame) end, frame) then return end
    m:FrameHidden(frame)
end

function Pad.Remember(frame)
    local m = manager()
    if not m or later(function() Pad.Remember(frame) end, frame) then return end
    if frame:IsShown() then m:FrameShown(frame) end
end

-- A small list over a window (a dropdown) takes the D-pad, and closing it
-- gives the D-pad back to the window it opened from. Not in combat.
function Pad.Popup(frame, close)
    if close then
        frame.SmartNavigationCloseHandler = function() close(); return true end
    end
    frame:HookScript("OnShow", function(self)
        local m = manager()
        if not m or fight or InCombatLockdown() then return end
        told[self] = true
        m:HandlePopupShown(self)
    end)
    frame:HookScript("OnHide", function(self)
        local m = manager()
        if not m or not told[self] or InCombatLockdown() then return end
        told[self] = nil
        m:HandlePopupHide(self)
    end)
end

-- Combat

local function combatActive()
    local R, T = C_RestrictedActions, Enum.AddOnRestrictionType
    return type(R) == "table" and T and R.IsAddOnRestrictionActive(T.Combat) == true
end

-- Called while the game still listens. Inside the restriction's own event it
-- reports "not active", and PLAYER_REGEN_DISABLED fires before lockdown.
local function handBack()
    if fight then return end
    fight = true
    unbind()
    local m = manager()
    if not m or combatActive() then return end
    for frame in pairs(told) do
        told[frame] = nil
        m:FrameHidden(frame)
    end
end

local function takeBack()
    fight = false
    local asked = waiting
    waiting = {}
    for _, fn in pairs(asked) do fn() end
    for frame in pairs(followed) do sync(frame) end
end

DUI.RegisterEvent("PLAYER_REGEN_DISABLED", handBack)
DUI.RegisterEvent("PLAYER_REGEN_ENABLED", takeBack)
DUI.RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", function(_, t, state)
    local T, S = Enum.AddOnRestrictionType, Enum.AddOnRestrictionState
    if t ~= T.Combat then return end
    if state ~= S.Inactive then handBack()
    elseif not InCombatLockdown() then takeBack() end
end)

-- The controller UI was turned on or off with windows open.
DUI.RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION", function()
    for frame in pairs(told) do told[frame] = nil end
    Pad.focused = nil
    if not InCombatLockdown() then
        unbind()
        takeBack()
    end
    DUI.Fire("PadChanged")
end)
