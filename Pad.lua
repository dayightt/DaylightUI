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
--                            (default f.tabs); frame.padTabsLabel (text or a
--                            function) names them
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
--   entry.secure(stop)       returns a secure action's attributes ({ type =
--                            "spell", spell = id } or { type = "click",
--                            clickbutton = stop }); the key then clicks a secure
--                            button carrying them, with entry.button as the mouse
--                            button. For what addon code can't do itself: casting
--                            a spell, using a bag item. Rebound as the D-pad
--                            moves. The only kind of entry A can have
--   frame.padHints()         a list of { keys, label } shown instead (the bind
--                            prompt, the chat's typing box: Pad.Take)
-- An entry whose when() returns false is hidden and does nothing. An entry
-- with a hold and no label of its own does nothing on a tap.
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
local forgetting = setmetatable({}, { __mode = "k" }) -- parked game windows waiting for one of ours to be listed

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
    A = { "GAMEPAD_FACE_BOTTOM", "PAD1" },
    X = { "GAMEPAD_FACE_LEFT", "PAD3" },
    Y = { "GAMEPAD_FACE_TOP", "PAD4" },
    MENU_LEFT = { "GAMEPAD_MENU_LEFT", "PADBACK" },
    MENU_RIGHT = { "GAMEPAD_MENU_RIGHT", "PADFORWARD" },
}
local function keyOf(name) return key(Pad.KEYS[name][1], Pad.KEYS[name][2]) end
Pad.KeyOf = keyOf   -- "X" -> the game's key name for it ("PAD3")
Pad.GameKey = key   -- a game key global ("GAMEPAD_SHOULDER_LEFT"), else the fallback

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
-- What every window of ours gets after its own entries: Y opens a list row's
-- right-click menu (More actions, as on the game's Communities window), and
-- the left menu button goes into the page's search box (the game's bags,
-- spellbook). entry.follow: bound only while it acts on the stop, again as
-- the D-pad moves, so a window without them leaves the keys to the game.
-- stop.padMore(stop) returns the menu's opener for a stop the kit doesn't know
-- (a raid tile), or nil when it has none right now.
local function moreOf(b)
    if type(b) ~= "table" then return nil end
    if type(b.padMore) == "function" then return b.padMore(b) end
    local spec = b.spec or b.lineSpec
    if type(spec) ~= "table" or spec.dim then return nil end
    if type(spec.onRightClick) == "function" then return spec.onRightClick end
    if type(spec.onMenu) == "function" then return spec.onMenu end   -- the finder's and Social's rows
    return nil
end

local function searchOf(f)
    local box = f and f.padSearch
    if type(box) == "table" and box:IsVisible() and (not box.IsEnabled or box:IsEnabled()) then return box end
    return nil
end

-- The footer's main button (Parts.Footer, the primary one), while it can be pressed.
local function mainOf(f)
    local foot = f and f.padFoot
    if type(foot) ~= "table" or not (foot.frame and foot.frame:IsVisible()) then return nil end
    for _, b in ipairs(foot.buttons or {}) do
        if b:IsShown() and type(b.spec) == "table" and b.spec.primary then
            if b.spec.off then return nil end
            return b
        end
    end
end

-- X presses the footer's main button, as the game's windows put their main
-- action on X; only on windows that don't bind X themselves.
Pad.FOOTER_KEY = { key = "X", follow = true,
    label = function() local b = mainOf(Pad.focused); return b and b.spec.text end,
    when = function() return mainOf(Pad.focused) ~= nil end,
    run = function() local b = mainOf(Pad.focused); if b then b:Click() end end }

Pad.DEFAULT_KEYS = {
    { key = "Y", follow = true, label = function() return CONTEXT_ACTION_LABEL_MORE_ACTIONS or L["More"] end,
      when = function(b) return moreOf(b) ~= nil end, run = function(b) local fn = moreOf(b); if fn then fn(b) end end },
    { key = "MENU_LEFT", follow = true, label = function() return SEARCH or L["Search"] end,
      when = function() return searchOf(Pad.focused) ~= nil end,
      run = function() local box = searchOf(Pad.focused); if box then box:SetFocus() end end },
}

-- A window's own entries, then the defaults (f.padNoDefaults leaves them out).
local function entriesOf(f)
    local own = type(f.padKeys) == "table" and f.padKeys or {}
    if f.padNoDefaults then return own end
    local out, ownX = {}, false
    for _, e in ipairs(own) do
        out[#out + 1] = e
        if e.key == "X" then ownX = true end
    end
    if not ownX then out[#out + 1] = Pad.FOOTER_KEY end
    for _, e in ipairs(Pad.DEFAULT_KEYS) do out[#out + 1] = e end
    return out
end
Pad.Entries = entriesOf

local function entryFor(f, name, at)
    if not f then return nil end
    for _, e in ipairs(entriesOf(f)) do
        if e.key == name and (not e.when or e.when(at)) then return e end
    end
end

-- An entry with hold = { label, run, when } runs normally on a tap and runs
-- hold.run when a key held Pad.HOLD s is let go, like the game's tap-or-hold
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
        if not (h and h.name == name) then return end
        if not h.done then
            if h.e.run then h.e.run(h.at) end
        elseif not h.e.hold.when or h.e.hold.when(h.at) then
            h.e.hold.run(h.at)
        end
        return
    end
    pressed[name] = true
    local at = stop()
    local e = entryFor(Pad.focused, name, at)
    if not e then return end
    if not e.hold then return e.run and e.run(at) end
    local h = { name = name, e = e, at = at }
    holding = h
    -- The timer only marks the hold. The hold itself runs on the key's release,
    -- because some of them (crafting all) are refused outside a real key press.
    C_Timer.After(Pad.HOLD, function()
        if holding == h then h.done = true end
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
        -- A secure twin per key: a binding's click is a hardware press, so the
        -- secure action it carries runs untainted.
        local s = CreateFrame("Button", Pad.SECURE_BUTTON .. name, UIParent, "SecureActionButtonTemplate")
        s:RegisterForClicks("AnyUp")
        s:SetAttribute("useOnKeyDown", false)
        s:HookScript("OnClick", function()
            C_Timer.After(0, function() if Pad.focused then Pad.ShowHints(Pad.focused) end end)
        end)
    end
end

Pad.SECURE_BUTTON = "DaylightUIPadSecure" -- plus the key
-- Sets a key's secure twin to these attributes only, clearing the last ones.
local function arm(name, attrs)
    local s = _G[Pad.SECURE_BUTTON .. name]
    for k in pairs(s.padAttrs or {}) do s:SetAttribute(k, nil) end
    s.padAttrs = attrs
    for k, v in pairs(attrs) do s:SetAttribute(k, v) end
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

local boundAt -- the stop the secure entries were bound for

local function bind(f)
    buildKeys()
    ClearOverrideBindings(keys)
    if #tabsOf(f) > 1 then
        SetOverrideBindingClick(keys, true, key("GAMEPAD_SHOULDER_LEFT", "PADLSHOULDER"), Pad.PREV_TAB)
        SetOverrideBindingClick(keys, true, key("GAMEPAD_SHOULDER_RIGHT", "PADRSHOULDER"), Pad.NEXT_TAB)
    end
    local done = {}
    local at = stop()
    boundAt = at
    for _, e in ipairs(entriesOf(f)) do
        if not done[e.key] then
            if e.follow then
                if not e.when or e.when(at) then
                    done[e.key] = true
                    SetOverrideBindingClick(keys, true, keyOf(e.key), Pad.KEY_BUTTON .. e.key)
                end
            elseif e.secure then
                local attrs = (not e.when or e.when(at)) and e.secure(at) or nil
                if attrs then
                    done[e.key] = true
                    arm(e.key, attrs)
                    SetOverrideBindingClick(keys, true, keyOf(e.key), Pad.SECURE_BUTTON .. e.key, e.button or "LeftButton")
                end
            elseif e.key == "A" then
                -- A stays the game's unless a secure entry takes it.
            elseif not e.click then
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
    if Pad.focused ~= f or Pad.prompt or InCombatLockdown() then return end
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
local function labelOf(e, at)
    if type(e.label) == "function" then return e.label(at) end
    return e.label
end

-- Whether an entry acts on this stop: its when(), and for a secure one an action.
local function acts(e, at)
    if e.when and not e.when(e.click and nil or at) then return false end
    return not e.secure or e.secure(at) ~= nil
end

function Pad.HintList(f)
    if type(f.padHints) == "function" then return f.padHints() end
    local m = manager()
    local at = stop()
    local out = {}
    local list = entriesOf(f)
    local a
    for _, e in ipairs(list) do
        if e.key == "A" and e.secure and acts(e, at) then a = labelOf(e, at); break end
    end
    -- padSelect may return false, meaning A does nothing on this stop (a slider row).
    if a == nil then a = f.padSelect and f.padSelect(at) end
    if a ~= false then out[1] = { { key("GAMEPAD_FACE_BOTTOM", "PAD1") }, a or ACTION_LABEL_SELECT or L["Select"] } end
    if at and at.padStep and not at.disabled then
        out[#out + 1] = { { key("GAMEPAD_DPAD_LEFT", "PADDLEFT"), key("GAMEPAD_DPAD_RIGHT", "PADDRIGHT") },
                          at.padStepLabel or L["Change"] }
    end
    local done = { A = true }
    for _, e in ipairs(list) do
        if not done[e.key] and acts(e, at) then
            done[e.key] = true
            local label = labelOf(e, at)
            if label then out[#out + 1] = { { keyOf(e.key) }, label } end
            local h = e.hold
            if h and (not h.when or h.when(at)) then
                out[#out + 1] = { { keyOf(e.key) }, string.format(L["Hold: %s"],
                    type(h.label) == "function" and h.label(at) or h.label) }
            end
        end
    end
    if #tabsOf(f) > 1 then
        out[#out + 1] = { { key("GAMEPAD_SHOULDER_LEFT", "PADLSHOULDER"),
                            key("GAMEPAD_SHOULDER_RIGHT", "PADRSHOULDER") },
                          (type(f.padTabsLabel) == "function" and f.padTabsLabel() or f.padTabsLabel) or L["Tabs"] }
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
    if f.padHintsAbove then
        hints:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, Pad.HINT_GAP)
    else
        hints:SetPoint("TOP", f, "BOTTOM", 0, -Pad.HINT_GAP)
    end
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
    if not f then watching = nil; return end
    -- A secure entry carries the stop's own action (this spell, this item), so
    -- it's armed again once the D-pad moves.
    if Pad.prompt then C_Timer.After(Pad.HINT_EVERY, watchHints); return end   -- the bind prompt has the bar
    if stop() ~= boundAt and not fight and not InCombatLockdown() then
        for _, e in ipairs(entriesOf(f)) do
            if e.secure or e.follow then bind(f); break end
        end
    end
    Pad.ShowHints(f)
    C_Timer.After(Pad.HINT_EVERY, watchHints)
end

-- Putting a spell or item on the game's controller bars

-- The game's own bind screen (GamepadActionBarEditFrame:BindSpell and the
-- rest) isn't wrapped: started from addon code it suspends the window and
-- writes the game's binding stack, which taints the controller for the rest
-- of the session. All it ends in is a pickup and PlaceAction on the slot that
-- was pressed, so this does just that: a small prompt waits for a press on
-- the bars and puts the action there.
--   Pad.BindAction({ icon, name, pickup = fn })   out of combat; true if shown
--   Pad.EndBind()                                  cancels it

-- The controller bars: 3 pages of 4 bars of 8 buttons, the triggers held pick
-- the bar (none, LT, RT, both), and the top bar's 4 face buttons (jump,
-- interact...) hold no action, so a page is 28 slots (ActionBindingUtil.lua).
-- Buttons in Bindings.xml order: D-pad left, up, right, down, then face left,
-- up, right, down.
Pad.BAR_PAGES, Pad.BAR_PAGE_SLOTS, Pad.BAR_SIZE, Pad.BAR_RESERVED = 3, 28, 8, 4
Pad.BAR_BUTTONS = { "PADDLEFT", "PADDUP", "PADDRIGHT", "PADDDOWN", "PAD3", "PAD4", "PAD2", "PAD1" }
Pad.BIND_BUTTON = "DaylightUIPadBind" -- plus 1-8, LT, RT, PREV, NEXT
Pad.PROMPT_W, Pad.PROMPT_ICON = 420, 40

-- The storage slot a press lands on, or nil for a button that holds none.
function Pad.SlotOf(page, bar, index)
    local U = C_GamepadUI
    local first = type(U) == "table" and U.GetFirstGamepadActionStorageSlotIndex and U.GetFirstGamepadActionStorageSlotIndex()
    if type(first) ~= "number" then return nil end
    local at = bar * Pad.BAR_SIZE + index - 1
    if at >= Pad.BAR_SIZE then
        at = at - Pad.BAR_RESERVED
    elseif at >= Pad.BAR_RESERVED then
        return nil
    end
    return first + (page - 1) * Pad.BAR_PAGE_SLOTS + at
end

local function barKey(i) return GetBindingKey("GAMEPADACTIONBUTTON" .. i) or Pad.BAR_BUTTONS[i] end

-- The page the game's bars show now (its special page counts as the first).
local function barPage()
    local bars = _G.GamepadMainActionBarFrame
    local unit = type(bars) == "table" and bars.PageUnit
    local page = type(unit) == "table" and type(unit.PageTracker) == "table" and unit.PageTracker.currentPage
    if type(page) ~= "number" or page < 1 or page > Pad.BAR_PAGES then return 1 end
    return page
end

local bindOwner, wanted
local triggers, page = {}, 1

local function bindHints()
    return {
        { { key("GAMEPAD_TRIGGER_LEFT", "PADLTRIGGER"), key("GAMEPAD_TRIGGER_RIGHT", "PADRTRIGGER") }, L["Other bars"] },
        { { key("GAMEPAD_SHOULDER_LEFT", "PADLSHOULDER"), key("GAMEPAD_SHOULDER_RIGHT", "PADRSHOULDER") },
          string.format(L["Page %d"], page) },
        { { key("GAMEPAD_FACE_RIGHT", "PAD2") }, CANCEL or L["Cancel"] },
    }
end

-- Where each button sits on its cross, in cells from the cross's middle:
-- the D-pad's four on the left cross, the face buttons on the right.
Pad.CROSS = { { -1, 0 }, { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 }, { 0, 1 }, { 1, 0 }, { 0, -1 } }
Pad.CELL, Pad.CELL_GAP, Pad.CROSS_GAP = 30, 4, 48
Pad.PROMPT_HOLD = 0.6 -- s the placed spell stays in view before the prompt goes

local function makeCell(parent)
    local Style = DUI.Style
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(Pad.CELL, Pad.CELL)
    Style.Shell(c, { borderPx = 1, noBevel = true })
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("TOPLEFT", c, "TOPLEFT", 1, -1)
    c.icon:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -1, 1)
    Style.CropIcon(c.icon)
    c.glyph = CreateFrame("Frame", nil, c, "InputIconTextureFrameTemplate")
    c.glyph:SetSize(Pad.HINT_ICON - 2, Pad.HINT_ICON - 2)
    c.glyph:SetPoint("CENTER", c, "BOTTOMRIGHT", -3, 3)
    return c
end

local function makeGlyph(parent)
    local g = CreateFrame("Frame", nil, parent, "InputIconTextureFrameTemplate")
    g:SetSize(Pad.HINT_ICON, Pad.HINT_ICON)
    return g
end

local function prompt()
    if Pad.promptFrame then return Pad.promptFrame end
    local Style = DUI.Style
    local pad, step = Pad.HINT_PAD, Pad.CELL + Pad.CELL_GAP
    local cross = 3 * Pad.CELL + 2 * Pad.CELL_GAP
    local barW, barH = 2 * cross + Pad.CROSS_GAP, Pad.HINT_ICON + 4 + cross
    local p = CreateFrame("Frame", nil, UIParent)
    p:SetFrameStrata("DIALOG")
    p:SetSize(Pad.PROMPT_W, pad + Pad.PROMPT_ICON + pad + barH + pad)
    p:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    Style.Shell(p, { bgAlpha = 1 })   -- solid: it sits over the window it came from
    p.well = CreateFrame("Frame", nil, p)
    p.well:SetSize(Pad.PROMPT_ICON, Pad.PROMPT_ICON)
    p.well:SetPoint("TOPLEFT", p, "TOPLEFT", pad, -pad)
    Style.Shell(p.well, { borderPx = 1, noBevel = true })
    p.icon = p.well:CreateTexture(nil, "ARTWORK")
    p.icon:SetAllPoints(p.well)
    Style.CropIcon(p.icon)
    p.name = Style.Text(p, Style.SIZE.head, "LEFT")
    p.name:SetPoint("TOPLEFT", p.well, "TOPRIGHT", 10, -1)
    p.name:SetPoint("RIGHT", p, "RIGHT", -pad, 0)
    p.name:SetWordWrap(false)
    p.text = Style.Text(p, Style.SIZE.small, "LEFT")
    p.text:SetPoint("BOTTOMLEFT", p.well, "BOTTOMRIGHT", 10, 1)
    p.text:SetPoint("RIGHT", p, "RIGHT", -pad, 0)
    -- The bar the next press lands on, as two crosses, with the triggers held lit.
    p.bar = CreateFrame("Frame", nil, p)
    p.bar:SetSize(barW, barH)
    p.bar:SetPoint("TOP", p, "TOP", 0, -(pad + Pad.PROMPT_ICON + pad))
    p.cells = {}
    for i = 1, Pad.BAR_SIZE do
        local c = makeCell(p.bar)
        local spot = Pad.CROSS[i]
        local mid = (i <= 4) and (cross / 2) or (cross + Pad.CROSS_GAP + cross / 2)
        c:SetPoint("CENTER", p.bar, "TOPLEFT", mid + spot[1] * step, -(Pad.HINT_ICON + 4 + cross / 2) + spot[2] * step)
        p.cells[i] = c
    end
    p.lt, p.rt = makeGlyph(p.bar), makeGlyph(p.bar)
    p.lt:SetPoint("TOPLEFT", p.bar, "TOPLEFT", 0, 0)
    p.rt:SetPoint("TOPRIGHT", p.bar, "TOPRIGHT", 0, 0)
    p.page = Style.Text(p.bar, Style.SIZE.small, "CENTER")
    p.page:SetPoint("TOP", p.bar, "TOP", 0, -2)
    p.padHints = bindHints
    p:Hide()
    Pad.promptFrame = p
    return p
end

local function barOf() return (triggers.LT and 1 or 0) + (triggers.RT and 2 or 0) end

-- Paints the preview: what's on each button of the bar the triggers pick.
-- moved fades the crosses in, as the bar changes under them.
local function paintBar(moved)
    local p = Pad.prompt
    if not p then return end
    local bar = barOf()
    for i, c in ipairs(p.cells) do
        local slot = Pad.SlotOf(page, bar, i)
        local tex = slot and GetActionTexture(slot) or nil
        c.icon:SetTexture(tex)
        c.icon:SetShown(tex ~= nil)
        c:SetAlpha(slot and 1 or 0.3)   -- the top bar's face buttons hold nothing
        if c.glyph.SetInputKey then c.glyph:SetInputKey(barKey(i)) end
    end
    if p.lt.SetInputKey then p.lt:SetInputKey(key("GAMEPAD_TRIGGER_LEFT", "PADLTRIGGER")) end
    if p.rt.SetInputKey then p.rt:SetInputKey(key("GAMEPAD_TRIGGER_RIGHT", "PADRTRIGGER")) end
    local M = DUI.Motion
    M.Fade(p.lt, p.lt:GetAlpha(), triggers.LT and 1 or 0.3, M.FAST)
    M.Fade(p.rt, p.rt:GetAlpha(), triggers.RT and 1 or 0.3, M.FAST)
    p.page:SetText(string.format(L["Page %d"], page))
    DUI.Style.InkText(p.page, "LABEL")
    if moved then M.Fade(p.bar, 0.4, 1, M.FAST) end
end

local function placeOn(slot)
    if InCombatLockdown() then return false end
    ClearCursor()
    wanted.pickup()
    if not GetCursorInfo() then return false end
    PlaceAction(slot)
    ClearCursor()   -- what was in the slot comes onto the cursor; it's dropped, as on the game's bind
    return true
end

local function pressBar(i)
    local p = Pad.prompt
    if not p then return end
    local slot = Pad.SlotOf(page, barOf(), i)
    if not slot then
        if barKey(i) == key("GAMEPAD_FACE_RIGHT", "PAD2") then Pad.EndBind() end   -- B on the top bar holds nothing: cancel
        return
    end
    local placed = placeOn(slot)
    if placed then
        -- Show it land: the new icon pops into the pressed button before the prompt goes.
        paintBar()
        DUI.Motion.Pop(p.cells[i].icon, 0.5)
    end
    Pad.EndBind(placed)
end

local function buildBind()
    if bindOwner then return end
    bindOwner = CreateFrame("Frame", nil, UIParent)
    for i = 1, Pad.BAR_SIZE do
        local b = CreateFrame("Button", Pad.BIND_BUTTON .. i, UIParent)
        b:RegisterForClicks("AnyDown")
        b:SetScript("OnClick", function() pressBar(i) end)
    end
    for _, side in ipairs({ "LT", "RT" }) do
        local b = CreateFrame("Button", Pad.BIND_BUTTON .. side, UIParent)
        b:RegisterForClicks("AnyDown", "AnyUp")
        b:SetScript("OnClick", function(_, _, down)
            triggers[side] = down ~= false or nil
            paintBar(true)
        end)
    end
    for name, dir in pairs({ PREV = -1, NEXT = 1 }) do
        local b = CreateFrame("Button", Pad.BIND_BUTTON .. name, UIParent)
        b:RegisterForClicks("AnyDown")
        b:SetScript("OnClick", function()
            page = (page - 1 + dir) % Pad.BAR_PAGES + 1
            paintBar(true)
            if Pad.prompt then Pad.ShowHints(Pad.prompt) end
        end)
    end
end

function Pad.BindAction(spec)
    if not manager() or fight or InCombatLockdown() or type(spec) ~= "table" or type(spec.pickup) ~= "function" then return false end
    if not Pad.SlotOf(1, 1, 1) then return false end
    buildBind()
    wanted, triggers, page = spec, {}, barPage()
    -- The window's own buttons wait under the prompt.
    if keys then ClearOverrideBindings(keys) end
    Pad.FreeSides()
    ClearOverrideBindings(bindOwner)
    for i = 1, Pad.BAR_SIZE do SetOverrideBindingClick(bindOwner, true, barKey(i), Pad.BIND_BUTTON .. i) end
    SetOverrideBindingClick(bindOwner, true, key("GAMEPAD_TRIGGER_LEFT", "PADLTRIGGER"), Pad.BIND_BUTTON .. "LT")
    SetOverrideBindingClick(bindOwner, true, key("GAMEPAD_TRIGGER_RIGHT", "PADRTRIGGER"), Pad.BIND_BUTTON .. "RT")
    SetOverrideBindingClick(bindOwner, true, key("GAMEPAD_SHOULDER_LEFT", "PADLSHOULDER"), Pad.BIND_BUTTON .. "PREV")
    SetOverrideBindingClick(bindOwner, true, key("GAMEPAD_SHOULDER_RIGHT", "PADRSHOULDER"), Pad.BIND_BUTTON .. "NEXT")
    local p = prompt()
    -- The row's tooltip would sit over the prompt (tooltips draw above everything).
    if GameTooltip then GameTooltip:Hide() end
    if spec.icon then p.icon:SetTexture(spec.icon) end
    p.name:SetText(spec.name or "")
    DUI.Style.InkText(p.name, "VALUE")
    p.text:SetText(L["Press the button to put it on. Hold a trigger for its bar."])
    DUI.Style.InkText(p.text, "TEXT")
    Pad.prompt = p
    p.gone = nil
    local M = DUI.Motion
    M.Fade(p, p:IsShown() and p:GetAlpha() or 0, 1, M.FAST)
    p:Show()
    paintBar()
    Pad.ShowHints(p)
    return true
end

-- Closes the prompt; placed says it put the action on a slot, which stays in
-- view a moment so the player sees where it went.
function Pad.EndBind(placed)
    local p = Pad.prompt
    if not p then return end
    Pad.prompt, wanted, triggers = nil, nil, {}
    if bindOwner and not InCombatLockdown() then ClearOverrideBindings(bindOwner) end
    if DUI.Sound then DUI.Sound.Play(placed and "snap" or "close") end
    p.gone = true
    local wait = placed and Pad.PROMPT_HOLD or 0
    DUI.Motion.Fade(p, 1, 0, DUI.Motion.FAST, wait)
    C_Timer.After(wait + DUI.Motion.FAST, function() if p.gone then p.gone = nil; p:Hide() end end)
    local f = Pad.focused
    if f and not fight and not InCombatLockdown() then
        bind(f)
        Pad.ShowHints(f)
    else
        Pad.HideHints()
    end
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
    if Pad.focused == f then f.padSearch, f.padFoot = Pad.FindParts(f) end
    local nav = _G.SmartNavigation
    if Pad.focused ~= f or fight or InCombatLockdown() or type(nav) ~= "table" or not nav.SetScrollFrameForFrame then return end
    nav:SetScrollFrameForFrame(f, f.padScroll or Pad.FindScroll(f))
end

-- The search box (W.Input with search) and footer (Parts.Footer) on the
-- window's page in view, found once per page so the hints don't walk the
-- window every time.
function Pad.FindParts(f)
    local search, foot
    local function walk(frame)
        if (search and foot) or not frame:IsVisible() then return end
        if frame.isSearch then search = search or frame end
        if frame.padFooter then foot = foot or frame.padFooter end
        for _, child in ipairs({ frame:GetChildren() }) do walk(child) end
    end
    walk(f)
    return search, foot
end

local function focusGained(self)
    if Pad.prompt then Pad.EndBind() end
    Pad.focused = self
    Pad.Scrolls(self)
    if not watching then
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

-- A box of ours the game gives the controller to by itself (the chat's typing
-- box, which the game focuses through its own chat frame): its hints show and
-- its keys bind while it's taken, then whichever window has the focus gets them
-- back. f is a frame of ours with padHints and, if it binds any, padKeys /
-- padTabs; f.padHintsAbove puts the bar over it.
function Pad.Take(f)
    if not manager() or fight or InCombatLockdown() or Pad.prompt then return end
    Pad.taken = f
    bind(f)
    Pad.ShowHints(f)
end

function Pad.Release(f)
    if Pad.taken ~= f then return end
    Pad.taken = nil
    if InCombatLockdown() then return end
    unbind()
    local w = Pad.focused
    if w and not fight then
        bind(w)
        Pad.ShowHints(w)
    else
        Pad.HideHints()
    end
end

local function focusLost(self)
    if Pad.focused ~= self then return end
    Pad.focused = nil
    if Pad.prompt then Pad.EndBind() end
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
    if open and next(forgetting) then
        local waiting = {}
        for f in pairs(forgetting) do waiting[#waiting + 1] = f end
        for _, f in ipairs(waiting) do Pad.Forget(f) end
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

-- Takes a parked game window off the game's list, but only while another shown
-- window is on it. Emptying the list sends the game's controller bindings back
-- to its core set, and the game's own listener for that makes a protected call
-- that is refused when addon code started it. Returns false when it has to wait.
local function drop(m, frame)
    local list = m.shownFrames
    if type(list) ~= "table" then
        m:FrameHidden(frame)
        return true
    end
    local listed, other = false, false
    for _, f in ipairs(list) do
        if f == frame then
            listed = true
        elseif type(f) == "table" and f.IsShown and f:IsShown() then
            other = true
        end
    end
    if not listed then return true end
    if not other then return false end
    m:FrameHidden(frame)
    return true
end

-- A parked game window that's still shown goes back on the list, with focus,
-- every time the game opens a page in it (a quest's reward page).
function Pad.KeepOff(frame)
    local m = manager()
    if not m or fight or InCombatLockdown() or type(m.shownFrames) ~= "table" then return end
    drop(m, frame)
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
    forgetting[frame] = (not drop(m, frame)) or nil
end

function Pad.Remember(frame)
    forgetting[frame] = nil
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
    if Pad.prompt then Pad.EndBind() end
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
