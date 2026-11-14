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
-- the game's handlers would run on ours under our taint. Set the entry to nil in
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
-- failed on ours), and its hide would turn the slot's range check off under our
-- painter. These no-ops keep our buttons out of all that.
local function stayOut() end

-- A bar's twelve buttons. SecureActionButtonTemplate goes last on purpose so the
-- click handler is the plain secure one, not the template's, which reads its own
-- fields under our taint and gets blocked in combat. Clicks act on release, like
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
        -- slot 1 wasn't usable. Our tint only undoes colors it set itself, so
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
        -- which write attributes. Running tainted on our buttons, the write is
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
        Buttons.SlotsChanged()
        made[i] = btn
        DUI.Fire("ActionButtonMade", btn, def)
        DUI.APIReport.Made("actionbutton", btn, def.num .. ":" .. i, false)
    end
    return made
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
-- Painting. Our buttons are off the game's event list, so every part is drawn here
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

function Buttons.SetOutOfRange(btn, out)
    out = out == true
    local st = Buttons.State(btn)
    local parts = ns.Skin.GetParts(btn)
    -- Every target change asks every button, so bail when nothing changed.
    if st.outOfRange == out and (not parts or parts.outOfRange == out) then return end
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

-- The spell a slot casts, directly or through a macro.
local function spellOf(slot)
    local kind, id = GetActionInfo(slot)
    if kind == "spell" then return id end
    if kind == "macro" and type(GetMacroSpell) == "function" then return GetMacroSpell(id) end
end
Buttons.SpellOf = spellOf

-- The blink runs on the events frame's OnUpdate only while something blinks,
-- which is almost never (auto attack, auto shot).
local flashing = {}
local function blinking()
    local f = Buttons.frame
    if f then f:SetScript("OnUpdate", next(flashing) and Buttons.OnUpdate or nil) end
end
function Buttons.SetFlashing(btn, on)
    if on then
        if flashing[btn] then return end
        flashing[btn] = true
        blinking()
        return
    end
    if not flashing[btn] then return end
    flashing[btn] = nil
    if type(btn.Flash) == "table" then btn.Flash:Hide() end
    blinking()
end

local flashIn, flashOn = 0, false
function Buttons.OnUpdate(_, dt) Buttons.Tick(dt) end
function Buttons.Tick(dt)
    flashIn = flashIn - (dt or 0)
    if flashIn > 0 then return end
    flashIn = Buttons.FLASH_EVERY
    flashOn = not flashOn
    for btn in pairs(flashing) do
        if type(btn.Flash) == "table" then btn.Flash:SetShown(flashOn) end
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
    { name = "cooldown", fn = function(btn, slot)
        local AB = C_ActionBar
        if type(AB) ~= "table" or not AB.GetActionCooldown then return end
        local loc = AB.GetActionLossOfControlCooldownInfo and AB.GetActionLossOfControlCooldownInfo(slot)
        local locOn = type(loc) == "table" and loc.isActive == true
        sweep(btn.lossOfControlCooldown, locOn, locOn and AB.GetActionLossOfControlCooldownDuration(slot))
        local info = AB.GetActionCooldown(slot)
        local on = type(info) == "table" and info.isActive == true
            and not (locOn and loc.shouldReplaceNormalCooldown == true)
        sweep(btn.cooldown, on, on and AB.GetActionCooldownDuration(slot))
        local charges = AB.GetActionCharges and AB.GetActionCharges(slot)
        local chOn = type(charges) == "table" and charges.isActive == true
        sweep(btn.chargeCooldown, chOn, chOn and AB.GetActionChargeDuration(slot))
        if ns.Ping then ns.Ping.Note(btn, slot, info, charges) end
    end },
    -- A proc shows the game's own glow on our button. The skin's border follows it.
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
    -- call EnableActionRangeCheck ourselves: it unbalanced the client's internal
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
local CONTENTS = { icon = true, count = true, name = true, checked = true, equipped = true }
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
            if slot and HasAction(slot) then Buttons.Paint(btn, RANGE) end
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
local queued, queuedAll, pending = {}, false, false
local function flush()
    pending = false
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
local function later()
    if pending then return end
    pending = true
    C_Timer.After(0, function() DUI.SafeCall(flush) end)
end
function Buttons.Queue(btn) queued[btn] = true; later() end
function Buttons.QueueAll() queuedAll = true; later() end

-- Painters requested by events, collected and run once on the next frame. Cooldown
-- events come in pairs and bursts (SPELL_UPDATE_COOLDOWN with
-- ACTIONBAR_UPDATE_COOLDOWN, charges, loss of control), and each one used to repaint
-- every button. Only visible buttons are painted: bars 5-8 start hidden, and a bar
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
local TARGET = only("usable", "range")

-- What each event repaints: a set of painter names, "all" (everything, next frame),
-- or a function of the event's arguments.
Buttons.EVENTS = {
    ACTIONBAR_SLOT_CHANGED = function(slot)
        if type(slot) ~= "number" or slot == 0 then Buttons.PaintAll() else Buttons.PaintSlot(slot) end
    end,
    ACTIONBAR_UPDATE_STATE = only("checked", "flash"),
    START_AUTOREPEAT_SPELL = only("checked", "flash"),
    STOP_AUTOREPEAT_SPELL = only("checked", "flash"),
    PLAYER_ENTER_COMBAT = only("checked", "flash"),
    PLAYER_LEAVE_COMBAT = only("checked", "flash"),
    TRADE_SKILL_SHOW = only("checked"),
    TRADE_SKILL_CLOSE = only("checked"),
    PLAYER_EQUIPMENT_CHANGED = only("equipped", "icon", "count"),
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
    -- The skin used to repaint our buttons on this too; now the usable painter
    -- handles them.
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
            end
        end)
    end
end
