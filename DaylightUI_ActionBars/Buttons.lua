-- The action buttons. They use the game's button template, so drag and drop,
-- flyouts and Quick Keybind work as usual, with the plain secure click handler.
-- Each knows its slot from its "action" attribute (bar 1's changes with the page,
-- see Paging.lua). Keybinds don't hit these directly; they press the game's hidden
-- twins (Keys.lua).

local _, ns = ...
local DUI = DaylightUI

local Buttons = {}
ns.Buttons = Buttons

local own = setmetatable({}, { __mode = "k" })   -- button -> its bar's def
local list = {}                                   -- every button made, in order

function Buttons.Slot(page, i) return (page - 1) * 12 + i end

function Buttons.SlotOf(btn)
    local a = btn:GetAttribute("action")
    if type(a) == "number" then return a end
end

-- Buttons by slot, built on demand and dropped whenever any button's slot changes.
-- A target change sends a range event for every range-checked slot, and asking
-- every button for its slot each time was thousands of calls in one frame.
local bySlot
function Buttons.SlotsChanged() bySlot = nil end
function Buttons.On(slot)
    if not bySlot then
        bySlot = {}
        for _, btn in ipairs(list) do
            local a = Buttons.SlotOf(btn)
            if a then
                local t = bySlot[a]
                if not t then t = {}; bySlot[a] = t end
                t[#t + 1] = btn
            end
        end
    end
    return bySlot[slot]
end

function Buttons.IsOwn(btn) return type(own[btn]) == "table" end
function Buttons.DefOf(btn) return own[btn] end
function Buttons.All() return list end

-- The template adds every button to the game's event list and never removes it, so
-- the game's handlers would run on these buttons under the addon's taint. Set the entry to nil in
-- place (it's the last one right after creation); removing it would shift the
-- game's own entries.
function Buttons.Unlist(btn)
    local frames = type(ActionBarButtonEventsFrame) == "table" and ActionBarButtonEventsFrame.frames
    if type(frames) ~= "table" then return end
    local n = #frames
    if frames[n] == btn then frames[n] = nil return end
    -- Walked whole: with holes left by earlier removals, the length can stop short.
    for k, v in pairs(frames) do
        if v == btn then frames[k] = nil return end
    end
end

-- The template's first Update (in OnLoad, for slot 1) registers the game's
-- per-action events. With Attack on slot 1 mid-swing (a /reload in a fight) it also
-- starts the game's blink on its update loop. Park silences the events that would
-- stop it, so every button blinked until a reload. Undo it here; Buttons.Tick
-- handles the blink instead.
function Buttons.Unwatch(btn)
    for _, name in ipairs({ "ActionBarActionEventsFrame", "ActionBarButtonUpdateFrame" }) do
        local f = _G[name]
        if type(f) == "table" and type(f.frames) == "table" then f.frames[btn] = nil end
    end
    btn.eventsRegistered, btn.needsUpdate, btn.stateDirty, btn.flashDirty = nil, nil, nil, nil
    btn.flashing = 0
    if type(btn.Flash) == "table" then btn.Flash:Hide() end
end

-- The template's show, hover and slot-change code would put each button in the
-- game's range and usable watchers, which run the game's button code on it (that
-- failed on these buttons), and its hide would turn the slot's range check off under Daylight UI's
-- painter. These no-ops keep Daylight UI's buttons out of all that.
local function stayOut() end

-- A bar's twelve buttons. SecureActionButtonTemplate goes last on purpose so the
-- click handler is the plain secure one, not the template's, which reads its own
-- fields under the addon's taint and gets blocked in combat. Clicks act on release, like
-- the game's buttons.
function Buttons.Make(def, holder)
    local made = {}
    for i = 1, 12 do
        local btn = CreateFrame("CheckButton", "DaylightUIBar" .. def.num .. "Button" .. i, holder,
                                "ActionBarButtonTemplate, SecureActionButtonTemplate")
        Buttons.Unlist(btn)
        Buttons.Unwatch(btn)
        -- OnLoad already registered these, for the slot it guessed (1).
        local leave = btn.UnregisterActionBarButtonCheckFrames
        if type(btn.action) == "number" and type(leave) == "function" then leave(btn, btn.action) end
        -- That Update also tinted the icon for slot 1, graying every button when
        -- slot 1 wasn't usable. Daylight UI's tint only undoes colors it set itself, so
        -- reset it here.
        if type(btn.icon) == "table" then btn.icon:SetVertexColor(1, 1, 1) end
        -- Same for the autocast corners, shown on every button when slot 1 held a
        -- pet autocast spell (or a locked outfit).
        local auto = btn.AutoCastOverlay
        if type(auto) == "table" then
            if type(auto.ShowAutoCastEnabled) == "function" then auto:ShowAutoCastEnabled(false) end
            auto:Hide()
        end
        btn.RegisterActionBarButtonCheckFrames = stayOut
        btn.UnregisterActionBarButtonCheckFrames = stayOut
        -- The game's UpdateAction (page change, show, hover) ends in these two,
        -- which write attributes. Running tainted on Daylight UI's buttons, the write is
        -- blocked in combat.
        btn.UpdatePressAndHoldAction = stayOut
        btn.UpdatePingAttributes = stayOut
        -- Its Update redraws the cooldown with SetCooldown, which refuses the
        -- client's secret combat times in tainted code (seen on a hover after
        -- leaving stealth). Buttons.Paint draws it instead.
        btn.Update = function(self) Buttons.Queue(self) end
        btn:SetID(0)
        btn:SetAttribute("dui-index", i)
        btn:SetAttribute("action", Buttons.Slot(def.page, i))
        btn:RegisterForClicks("AnyUp")
        btn:SetAttribute("useOnKeyDown", false)
        btn.commandName = def.command .. i      -- read by Quick Keybind
        own[btn] = def
        list[#list + 1] = btn
        btn:HookScript("OnShow", function(self)
            if self.paintStale then
                self.paintStale = nil
                Buttons.Queue(self)
            end
        end)
        btn:HookScript("OnDragStart", Buttons.DragStart)
        Buttons.SlotsChanged()
        made[i] = btn
        DUI.Fire("ActionButtonMade", btn, def)
        DUI.APIReport.Made("actionbutton", btn, def.num .. ":" .. i, false)
    end
    return made
end

-- With the game's bars locked, picking up a spell takes the pick-up key, Shift by
-- default. A bar that pages on Shift flips the moment it's held, so the spells on
-- its normal page could never be picked up. While a spellbook is open out of a
-- fight, a plain drag picks the spell up, as it does on unlocked bars. Holding
-- Shift still flips the bar, so its Shift page can be arranged too.
Buttons.BOOKS = { "DaylightUIBook", "PlayerSpellsFrame" }

function Buttons.Arranging()
    if InCombatLockdown() then return false end
    for _, name in ipairs(Buttons.BOOKS) do
        local f = _G[name]
        if type(f) == "table" and f:IsShown() then return true end
    end
    return false
end

-- Runs after the template's own drag, which already picked the spell up when
-- the bars are unlocked or the pick-up key is held.
function Buttons.DragStart(self)
    if type((GetCursorInfo())) ~= "nil" or not Buttons.Arranging() then return end
    local slot = Buttons.SlotOf(self)
    if slot then PickupAction(slot) end
end

-- The action bar kind (bars 1-8), used by Bars.lua.
Buttons.KIND = {
    Setup = function(def, holder) return Buttons.Make(def, holder) end,
    Count = function(_, cfg) return math.max(1, math.min(tonumber(cfg.icons) or 12, 12)) end,
    Base = function() return ns.Shape.BUTTON end,
    -- The game hides bars 2-8 in a pet battle, vehicle or override bar the same
    -- way. Bar 1 shows the vehicle's actions (Paging.lua).
    Rule = function(def)
        if def.num == 1 then return "[petbattle] hide; " end
        return "[petbattle][vehicleui][overridebar] hide; "
    end,
    Caps = { icons = { 1, 12 }, rows = true, height = true, show = "action" },
}

-- ---------------------------------------------------------------------
-- Painting. Daylight UI's buttons are off the game's event list, so every part is drawn here
-- from events. Painters run in order and each event runs only the ones it needs.
-- Values the client may make secret in combat (counts, cooldown times) are passed
-- whole to the engine (SetText, the cooldown's duration object), never compared
-- or tested.
-- ---------------------------------------------------------------------

local state = setmetatable({}, { __mode = "k" })
function Buttons.State(btn)
    local st = state[btn]
    if not st then
        st = {}
        state[btn] = st
    end
    return st
end

Buttons.FLASH_EVERY = 0.4    -- blink rate for auto attack and auto shot, same as the game's

-- The icon tint and keybind color come from the skin. slot, usable and noMana are
-- what the usable painter already read, passed along so they aren't queried twice.
function Buttons.Tint(btn, slot, usable, noMana)
    ns.Skin.UpdateState(btn, slot, usable, noMana)
end

function Buttons.RangeChanged(btn, out)
    local st = Buttons.State(btn)
    local parts = ns.Skin.GetParts(btn)
    return not (st.outOfRange == out and (not parts or parts.outOfRange == out))
end

function Buttons.SetOutOfRange(btn, out)
    out = out == true
    -- Every target change asks every button, so bail when nothing changed.
    if not Buttons.RangeChanged(btn, out) then return end
    local st = Buttons.State(btn)
    local parts = ns.Skin.GetParts(btn)
    st.outOfRange = out
    if parts then
        parts.outOfRange = out
        ns.Skin.UpdateRange(btn)
    end
end

local function sweep(cd, on, duration)
    if type(cd) ~= "table" then return end
    if on then cd:SetCooldownFromDurationObject(duration) else cd:Clear() end
end

-- Is any loss of control on you? The count is a plain number, no table. A count
-- that can't be read says yes, so the buttons ask for themselves as before.
function Buttons.LossOfControl()
    local L = C_LossOfControl
    local n = type(L) == "table" and type(L.GetActiveLossOfControlDataCount) == "function"
        and L.GetActiveLossOfControlDataCount()
    if type(n) ~= "number" or DUI.IsSecret(n) then return true end
    return n > 0
end

-- Slots known to have no charges, learned where the charge count can be read.
-- Forgotten when a slot or the spells change.
local noCharges = {}
function Buttons.NoteCharges(slot, charges)
    if type(charges) ~= "table" then return end
    local most = charges.maxCharges
    if type(most) == "number" and not DUI.IsSecret(most) and most <= 1 then noCharges[slot] = true end
end
function Buttons.ForgetCharges(slot)
    if type(slot) == "number" and slot ~= 0 then noCharges[slot] = nil else wipe(noCharges) end
end

-- The spell a slot casts, directly or through a macro.
-- A macro slot already names its spell (subType "spell"), the way the game's own
-- buttons read it; its id is the spell, not the macro.
local function spellOf(slot)
    local kind, id, sub = GetActionInfo(slot)
    if kind == "spell" then return id end
    if kind == "macro" and sub == "spell" then return id end
end
Buttons.SpellOf = spellOf

-- The blink runs on the events frame's OnUpdate only while something blinks,
-- which is almost never (auto attack, auto shot).
local flashing = {}
local flashT, flashIn, flashOn = 0, 0, false
local function blinking()
    local f = Buttons.frame
    if f then f:SetScript("OnUpdate", next(flashing) and Buttons.OnUpdate or nil) end
end
function Buttons.SetFlashing(btn, on)
    local flash = type(btn.Flash) == "table" and btn.Flash or nil
    if on then
        if flashing[btn] then return end
        -- The first one starts its breath from nothing, so the wash eases in.
        if not next(flashing) then flashT, flashIn, flashOn = 0, 0, false end
        flashing[btn] = true
        if flash then
            DUI.Motion.AlphaTo(flash, 0, 0)        -- stop a fade out still running
            flash:SetAlpha(0)
            flash:Show()
        end
        blinking()
        return
    end
    if not flashing[btn] then return end
    flashing[btn] = nil
    if flash then DUI.Motion.AlphaTo(flash, 0, DUI.Motion.FAST, true) end
    blinking()
end

-- With motion on the wash breathes in and out, one breath every two FLASH_EVERY
-- like the game's on and off; with motion off it blinks the game's way.
function Buttons.OnUpdate(_, dt) Buttons.Tick(dt) end
function Buttons.Tick(dt)
    local every = Buttons.FLASH_EVERY
    if DUI.Motion.On() then
        flashT = (flashT + (dt or 0)) % (2 * every)
        local a = 0.5 - 0.5 * math.cos(math.pi * flashT / every)
        for btn in pairs(flashing) do
            if type(btn.Flash) == "table" then btn.Flash:SetAlpha(a) end
        end
        return
    end
    flashIn = flashIn - (dt or 0)
    if flashIn > 0 then return end
    flashIn = every
    flashOn = not flashOn
    for btn in pairs(flashing) do
        if type(btn.Flash) == "table" then btn.Flash:SetAlpha(flashOn and 1 or 0) end
    end
end

local function text(fs, v)
    if type(fs) ~= "table" then return end
    if type(v) == "nil" then v = "" end
    fs:SetText(v)
end

Buttons.PAINTERS = {
    { name = "icon", fn = function(btn, slot)
        local icon = btn.icon
        if type(icon) ~= "table" then return end
        local tex = GetActionTexture(slot)
        icon:SetTexture(tex)
        icon:SetShown(type(tex) ~= "nil")
        -- Bar 1 paging can change the slot without a slot event, so the empty
        -- backing, keybind and highlight follow it here.
        if ns.Skin and ns.Skin.UpdateEmpty then ns.Skin.UpdateEmpty(btn) end
    end },
    -- Only slots with an icon are asked, like the game's buttons do. An emptied
    -- slot can still report the count of what used to be there.
    { name = "count", fn = function(btn, slot)
        local AB = C_ActionBar
        local c
        if type(GetActionTexture(slot)) ~= "nil" and type(AB) == "table" and AB.GetActionDisplayCount then
            c = AB.GetActionDisplayCount(slot)
        end
        text(btn.Count, c)
    end },
    { name = "name", fn = function(btn, slot) text(btn.Name, GetActionText(slot)) end },
    { name = "cost", fn = function(btn, slot) ns.Skin.UpdateCost(btn, slot) end },
    { name = "checked", fn = function(btn, slot)
        local current, auto = IsCurrentAction(slot) == true, IsAutoRepeatAction(slot) == true
        btn:SetChecked(current or auto)
        ns.Skin.SetActive(btn, current and not auto and IsAttackAction(slot) ~= true)
    end },
    { name = "flash", fn = function(btn, slot)
        Buttons.SetFlashing(btn, (IsAttackAction(slot) == true and IsCurrentAction(slot) == true)
            or IsAutoRepeatAction(slot) == true)
    end },
    { name = "usable", fn = function(btn, slot)
        local usable, noMana = IsUsableAction(slot)
        Buttons.Tint(btn, slot, usable, noMana)
    end },
    { name = "equipped", fn = function(btn, slot)
        local border = btn.Border
        if type(border) ~= "table" then return end
        local on = IsEquippedAction(slot) == true
        if on then border:SetVertexColor(0, 1, 0, 0.35) end
        border:SetShown(on)      -- the skin keeps it at alpha 0
    end },
    -- Only isActive and shouldReplaceNormalCooldown are tested (never secret). The
    -- times go to the sweep whole, as a duration object.
    -- Each ask hands back a new table, and in a fight this runs on every button
    -- several times a second, so the asks that can't matter are skipped: an empty
    -- slot, loss of control while none is on you, charges on a slot without any.
    { name = "cooldown", fn = function(btn, slot)
        local AB = C_ActionBar
        if type(AB) ~= "table" or not AB.GetActionCooldown then return end
        if type(GetActionTexture(slot)) == "nil" then
            sweep(btn.lossOfControlCooldown, false)
            sweep(btn.cooldown, false)
            sweep(btn.chargeCooldown, false)
            if ns.Ping then ns.Ping.Note(btn, slot) end
            return
        end
        local loc = Buttons.LossOfControl() and AB.GetActionLossOfControlCooldownInfo
            and AB.GetActionLossOfControlCooldownInfo(slot)
        local locOn = type(loc) == "table" and loc.isActive == true
        sweep(btn.lossOfControlCooldown, locOn, locOn and AB.GetActionLossOfControlCooldownDuration(slot))
        local info = AB.GetActionCooldown(slot)
        local on = type(info) == "table" and info.isActive == true
            and not (locOn and loc.shouldReplaceNormalCooldown == true)
        sweep(btn.cooldown, on, on and AB.GetActionCooldownDuration(slot))
        local charges = not noCharges[slot] and AB.GetActionCharges and AB.GetActionCharges(slot)
        Buttons.NoteCharges(slot, charges)
        local chOn = type(charges) == "table" and charges.isActive == true
        sweep(btn.chargeCooldown, chOn, chOn and AB.GetActionChargeDuration(slot))
        if ns.Ping then ns.Ping.Note(btn, slot, info, charges) end
    end },
    -- A proc shows the game's own glow on Daylight UI's button. The skin's border follows it.
    { name = "proc", fn = function(btn, slot)
        local id = spellOf(slot)
        local O = C_SpellActivationOverlay
        local on = type(id) == "number" and type(O) == "table" and O.IsSpellOverlayed(id) == true
        local st = Buttons.State(btn)
        local was = st.proc == true
        st.proc = on
        if was == on then return end
        local M = ActionButtonSpellAlertManager
        if type(M) ~= "table" then return end
        if on then M:ShowAlert(btn) else M:HideAlert(btn) end
        -- Update the border now; the skin's slow pass only looks for procs ending.
        ns.Skin.UpdateProc(btn)
    end },
    -- Range is checked here and by the range watch while there's a target. Never
    -- call EnableActionRangeCheck from addon code: it unbalanced the client's internal
    -- count, which survives a /reload, and the game's next enable crashed the
    -- client (BC_ASSERT). The game's twins don't turn it on either, since they're
    -- hidden and a hidden button turns its check off (ActionButton.lua OnHide).
    { name = "range", fn = function(btn, slot)
        Buttons.SetOutOfRange(btn, IsActionInRange(slot) == false)
    end },
}

-- names is a set of painter names ({ cooldown = true }), or nil for all. One
-- protected call per button rather than per painter: a failing painter is reported
-- and the rest still run, resuming after it.
local at = 0
local function paintFrom(btn, slot, names, from)
    local P = Buttons.PAINTERS
    for i = from, #P do
        local p = P[i]
        if not names or names[p.name] then
            at = i
            p.fn(btn, slot)
        end
    end
end
-- Painters that change what the button shows: plugins (DaylightUI.API's Paint)
-- paint after any of these. The rest tell the skin, which asks when it changed.
local CONTENTS = { icon = true, count = true, name = true, cost = true, checked = true, equipped = true }
local function shows(names)
    if not names then return true end
    for n in pairs(names) do if CONTENTS[n] then return true end end
    return false
end
function Buttons.Paint(btn, names)
    local slot = Buttons.SlotOf(btn)
    if not slot then return end
    local Skin = ns.Skin
    local h, a = Skin.Hold(btn)
    local from = 1
    while true do
        at = from
        if DUI.SafeCall(paintFrom, btn, slot, names, from) then break end
        from = at + 1
    end
    Skin.Release(btn, h, a, shows(names))
end

function Buttons.PaintAll(names)
    for _, btn in ipairs(list) do Buttons.Paint(btn, names) end
end

-- The range watch. With a target, shown buttons that hold an action check range
-- every RANGE_EVERY seconds (the old game's pace) and only update when it changes.
-- Stops when there's no target.
Buttons.RANGE_EVERY = 0.2
local RANGE = { range = true }
local rangeIn = 0
local function rangeTick(_, dt)
    rangeIn = rangeIn - (dt or 0)
    if rangeIn > 0 then return end
    rangeIn = Buttons.RANGE_EVERY
    for _, btn in ipairs(list) do
        if btn:IsVisible() then
            local slot = Buttons.SlotOf(btn)
            -- Ask first and paint only a change: most ticks change nothing, and a
            -- spell with no range answers nil, which reads as in range.
            if slot and HasAction(slot) and Buttons.RangeChanged(btn, IsActionInRange(slot) == false) then
                Buttons.Paint(btn, RANGE)
            end
        end
    end
end
function Buttons.WatchRange()
    local f = Buttons.rangeFrame
    if not f then
        f = CreateFrame("Frame")
        Buttons.rangeFrame = f
    end
    local on = UnitExists("target") == true
    if on == (type(f:GetScript("OnUpdate")) == "function") then return end
    rangeIn = Buttons.RANGE_EVERY
    f:SetScript("OnUpdate", on and rangeTick or nil)
end

function Buttons.PaintSlot(slot, names)
    local on = Buttons.On(slot)
    if not on then return end
    for _, btn in ipairs(on) do Buttons.Paint(btn, names) end
end

-- Paint on the next frame, once: a button whose slot changed (bar 1 paging), or
-- everything (several page events arrive together).
local queued, queuedAll = {}, false
local function flush()
    if queuedAll then
        -- Only visible buttons, as in flushWanted. A hidden one is painted in
        -- full when it shows (its OnShow in Buttons.Make).
        queuedAll = false
        for btn in pairs(queued) do queued[btn] = nil end
        for _, btn in ipairs(list) do
            if btn:IsVisible() then Buttons.Paint(btn) else btn.paintStale = true end
        end
        return
    end
    for btn in pairs(queued) do
        queued[btn] = nil
        Buttons.Paint(btn)
    end
end
local later = DUI.Soon(function() DUI.SafeCall(flush) end)
function Buttons.Queue(btn) queued[btn] = true; later() end
function Buttons.QueueAll() queuedAll = true; later() end

-- Painters requested by events, collected and run once on the next frame. Cooldown
-- events come in pairs and bursts (SPELL_UPDATE_COOLDOWN with
-- ACTIONBAR_UPDATE_COOLDOWN, charges, loss of control), and repainting every button for
-- each would waste the frame. Only visible buttons are painted: bars 5-8 start hidden, and a bar
-- shown only in or out of combat is hidden the rest of the time. A skipped button is
-- marked and painted in full when it shows.
local wanted, wantedPending = {}, false
local function flushWanted()
    wantedPending = false
    local names = wanted
    wanted = {}
    if not next(names) then return end
    for _, btn in ipairs(list) do
        if btn:IsVisible() then Buttons.Paint(btn, names) else btn.paintStale = true end
    end
end
function Buttons.QueuePaint(names)
    for n in pairs(names) do wanted[n] = true end
    if wantedPending then return end
    wantedPending = true
    C_Timer.After(0, function() DUI.SafeCall(flushWanted) end)
end

local function only(...)
    local t = {}
    for _, n in ipairs({ ... }) do t[n] = true end
    return t
end
local USABLE = only("usable")
local COST = only("cost")
local TARGET = only("usable", "range")

-- What each event repaints: a set of painter names, "all" (everything, next frame),
-- or a function of the event's arguments.
Buttons.EVENTS = {
    ACTIONBAR_SLOT_CHANGED = function(slot)
        Buttons.ForgetCharges(slot)
        if type(slot) ~= "number" or slot == 0 then Buttons.PaintAll() else Buttons.PaintSlot(slot) end
    end,
    SPELLS_CHANGED = function() Buttons.ForgetCharges(); Buttons.QueuePaint(COST) end,
    ACTIONBAR_UPDATE_STATE = only("checked", "flash"),
    START_AUTOREPEAT_SPELL = only("checked", "flash"),
    STOP_AUTOREPEAT_SPELL = only("checked", "flash"),
    PLAYER_ENTER_COMBAT = only("checked", "flash"),
    PLAYER_LEAVE_COMBAT = only("checked", "flash"),
    TRADE_SKILL_SHOW = only("checked"),
    TRADE_SKILL_CLOSE = only("checked"),
    PLAYER_EQUIPMENT_CHANGED = only("equipped", "icon", "count", "cost"),
    SPELL_UPDATE_ICON = only("icon"),
    BAG_UPDATE_DELAYED = only("count", "usable"),
    ACTIONBAR_UPDATE_COOLDOWN = only("cooldown"),
    SPELL_UPDATE_COOLDOWN = only("cooldown"),
    LOSS_OF_CONTROL_ADDED = only("cooldown"),
    LOSS_OF_CONTROL_UPDATE = only("cooldown"),
    SPELL_UPDATE_CHARGES = only("count", "cooldown"),
    SPELL_UPDATE_USABLE = only("usable"),
    -- Mounting or dismounting changes what can be cast. The game's buttons
    -- recheck on this alone (ActionButton.lua).
    PLAYER_MOUNT_DISPLAY_CHANGED = only("usable"),
    PLAYER_TARGET_CHANGED = function()
        Buttons.WatchRange()
        Buttons.QueuePaint(TARGET)
    end,
    SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = only("proc"),
    SPELL_ACTIVATION_OVERLAY_GLOW_HIDE = only("proc"),
    -- A list of { slot, usable, noMana }. Paint from the payload like the game's
    -- buttons do: IsUsableAction asked inside the event could still return the
    -- old answer (Shield Slam stayed dimmed as if short of rage).
    ACTION_USABLE_CHANGED = function(changes)
        if type(changes) ~= "table" then return Buttons.PaintAll(USABLE) end
        for _, c in ipairs(changes) do
            if type(c) == "table" and type(c.slot) == "number" then
                if type(c.usable) == "boolean" and type(c.noMana) == "boolean" then
                    for _, btn in ipairs(Buttons.On(c.slot) or {}) do
                        DUI.SafeCall(Buttons.Tint, btn, c.slot, c.usable, c.noMana)
                    end
                else
                    Buttons.PaintSlot(c.slot, USABLE)
                end
            end
        end
    end,
    -- The usable painter covers these buttons; the skin skips them on this event.
    ACTIONBAR_UPDATE_USABLE = USABLE,
    ACTION_RANGE_CHECK_UPDATE = function(slot, inRange, checksRange)
        local on = Buttons.On(slot)
        if not on then return end
        for _, btn in ipairs(on) do Buttons.SetOutOfRange(btn, checksRange == true and inRange == false) end
    end,
    -- Something on the cursor: show the empty slots so it can be dropped.
    CURSOR_CHANGED = function() ns.Skin.SetDragging(type((GetCursorInfo())) ~= "nil") end,
    PLAYER_ENTERING_WORLD = function() Buttons.WatchRange(); Buttons.QueueAll() end,
    UPDATE_SHAPESHIFT_FORM = "all", UPDATE_BONUS_ACTIONBAR = "all",
    ACTIONBAR_PAGE_CHANGED = "all", UPDATE_VEHICLE_ACTIONBAR = "all", UPDATE_OVERRIDE_ACTIONBAR = "all",
}

function Buttons.OnEvent(event, ...)
    local what = Buttons.EVENTS[event]
    if type(what) == "function" then return what(...) end
    if what == "all" then return Buttons.QueueAll() end
    if type(what) == "table" then Buttons.QueuePaint(what) end
end

-- Runs once at build: one events frame for every button, the blink, and a repaint
-- whenever a button's slot changes.
function Buttons.Wire()
    if Buttons.frame then return end
    local f = CreateFrame("Frame")
    Buttons.frame = f
    for event in pairs(Buttons.EVENTS) do pcall(f.RegisterEvent, f, event) end
    f:SetScript("OnEvent", function(_, event, ...) DUI.SafeCall(Buttons.OnEvent, event, ...) end)
    blinking()
    Buttons.WatchRange()      -- in case of a /reload with a target already set
    for _, btn in ipairs(list) do
        btn:HookScript("OnAttributeChanged", function(self, name)
            if name == "action" then
                Buttons.SlotsChanged()
                Buttons.Queue(self)
                -- A druid's page lands here a moment after the form event, so the
                -- keys shown on Cooldown Manager icons are worked out again.
                if ns.Keys then ns.Keys.OnEvent("ActionChanged") end
            end
        end)
    end
end
