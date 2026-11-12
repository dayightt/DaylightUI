local stub = require("stub")

-- The game's bars and buttons, and just enough of Edit Mode to save layouts
-- (tests/abworld.lua, shared with the installer tests).
local ABW = require("abworld")
local saved
local function world() saved = ABW.world() end

local function login() return stub.Load({ actionbars = true, before = world }) end

-- Runs the motion kit's tweens to their end.
local function settle()
    local d = DaylightUI.Motion.Driver()
    for _ = 1, 60 do
        if not (d and d:GetScript("OnUpdate")) then return end
        stub.RunOnUpdate(d, 1 / 60)
    end
end
-- The mouse over a button (its OnEnter): a click presses that one.
local function hover(b) b:GetScript("OnEnter")(b) end
-- Only a shaman has the totem bar.
local function loginShaman()
    return stub.Load({ actionbars = true, before = function()
        world()
        stub.units.player = { name = "Tester", class = "SHAMAN" }
    end })
end

local function entry(layout, idx)
    for _, e in ipairs(layout.systems) do if e.systemIndex == idx then return e end end
end
local function settingOf(e, key)
    for _, r in ipairs(e.settings) do if r.setting == key then return r.value end end
end

T.test("action bars: Extra Abilities moves off the bars, unless it was placed in Edit Mode", function()
    login()
    local L = stub.actionbars.Bars
    Enum.EditModeSystem.ExtraAbilities = 11
    local e = { system = 11, settings = {}, anchorInfo = {}, isInDefaultPosition = true }
    local layout = { systems = { e } }
    T.eq(L.ExtraCurrent(layout), false, "at the game's default: out of date")
    L.FillExtra(layout)
    local d = stub.actionbars.Shape.Defaults()
    T.eq(e.anchorInfo.point, "BOTTOM"); T.eq(e.anchorInfo.offsetX, d.extra.x)
    T.truthy(d.extra.x > d.right.x and d.extra.y > d.right.y, "over the right grid")
    T.eq(L.ExtraCurrent(layout), true)
    e.anchorInfo.offsetX = 5
    L.FillExtra(layout)
    T.eq(e.anchorInfo.offsetX, 5, "a spot picked in Edit Mode stays")
    Enum.EditModeSystem.ExtraAbilities = nil
end)

T.test("action bars: the totem bar leaves the game's bottom-bar stack (it moved in and out of fights)", function()
    loginShaman()
    local Tot = stub.actionbars.Totems
    Enum.EditModeSystem.TotemActionBar = 21
    local e = { system = 21, settings = {}, isInDefaultPosition = true,
                anchorInfo = { point = "RIGHT", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = -28, offsetY = 128 } }
    local layout = { systems = { e } }
    T.eq(Tot.LayoutCurrent(layout), false, "at the game's default: out of date")
    Tot.FillLayout(layout)
    T.eq(e.isInDefaultPosition, false, "off its default, the game no longer stacks it")
    -- Where the game puts its bar back (a fight's restack, or its own updates
    -- pulling the buttons onto it) is the holder's own default spot in the bar's
    -- scale, never the game's default over the middle of the bars.
    local d = stub.actionbars.Shape.Defaults()
    local mc = MultiCastActionBarFrame
    local r = mc:GetEffectiveScale() / UIParent:GetEffectiveScale()
    T.eq(e.anchorInfo.point, "BOTTOMLEFT"); T.eq(e.anchorInfo.relativePoint, "BOTTOM")
    T.near(e.anchorInfo.offsetX, d.totem.x / r); T.near(e.anchorInfo.offsetY, d.totem.y / r)
    T.truthy(d.totem.y > d.bar2.y, "above the bars")
    T.eq(Tot.LayoutCurrent(layout), true)
    e.anchorInfo.offsetX = 5
    Tot.FillLayout(layout)
    T.eq(e.anchorInfo.offsetX, 5, "a spot picked in Edit Mode stays")
    Enum.EditModeSystem.TotemActionBar = nil
end)

T.test("action bars: a layout holding the game's default totem spot (written before 1.6.9) is rewritten once", function()
    loginShaman()
    local Tot = stub.actionbars.Totems
    Enum.EditModeSystem.TotemActionBar = 21
    local e = { system = 21, settings = {}, isInDefaultPosition = false,
                anchorInfo = { point = "RIGHT", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = -28, offsetY = 128 } }
    local layout = { systems = { e } }
    T.eq(Tot.LayoutCurrent(layout), false, "the old spot over the bars: out of date")
    Tot.FillLayout(layout)
    T.eq(e.anchorInfo.point, "BOTTOMLEFT")
    T.eq(Tot.LayoutCurrent(layout), true, "asked once")
    Enum.EditModeSystem.TotemActionBar = nil
end)

T.test("action bars: the totem bar sits in its holder after a reload, not at its Edit Mode spot", function()
    loginShaman()
    local mc = MultiCastActionBarFrame
    local holder = stub.actionbars.Bars.holders.totem
    -- The game applies its Edit Mode layout as the world loads.
    mc:ClearAllPoints()
    mc:SetPoint("RIGHT", UIParent, "BOTTOM", -28, 128)
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.RunTimers()
    local _, rel = mc:GetPoint(1)
    T.eq(mc:GetParent(), holder, "in its holder")
    T.eq(rel, holder, "on its holder, where the unlock handle is")
end)

T.test("action bars: the totem buttons stay put when the game stacks its bottom bars in a fight (Ghost Wolf)", function()
    loginShaman()
    local mc = MultiCastActionBarFrame
    stub.RunTimers()
    stub.EnterCombat()
    -- Ghost Wolf in a fight: the game moves the bar itself, and nothing may move
    -- it back until the fight ends.
    EventRegistry:TriggerEvent("EditModeManager.UpdateBottomActionBarPositions")
    stub.RunTimers()
    local _, rel = MultiCastSummonSpellButton:GetPoint(1)
    T.eq(rel, stub.actionbars.Totems.stand, "on the stand-in")
end)

T.test("action bars: the totem bar goes back on its holder when the game stacks its bottom bars again", function()
    loginShaman()
    local mc = MultiCastActionBarFrame
    local holder = stub.actionbars.Bars.holders.totem
    stub.RunTimers()
    -- The pet bar shows (a pet summoned), so the game stacks its bottom bars,
    -- including the totem bar while its Edit Mode layout isn't written yet.
    EventRegistry:TriggerEvent("EditModeManager.UpdateBottomActionBarPositions")
    stub.RunTimers()
    local _, rel = mc:GetPoint(1)
    T.eq(rel, holder, "back on its holder, where the unlock handle is")
end)

T.test("action bars: only a shaman is asked to rewrite the layout for the totem bar", function()
    login()
    Enum.EditModeSystem.TotemActionBar = 21
    local layout = { systems = { { system = 21, settings = {}, anchorInfo = {}, isInDefaultPosition = true } } }
    T.eq(stub.actionbars.Totems.LayoutCurrent(layout), true)
    Enum.EditModeSystem.TotemActionBar = nil
end)

T.test("action bars: buttons sit in sockets, the game's art is hidden", function()
    local DUI = login()
    local b = _G.DaylightUIBar1Button3
    T.truthy(stub.actionbars.Skin.IsSkinned(b), "our socket")
    T.eq(b:GetNormalTexture():GetAlpha(), 0); T.eq(b.SlotArt:GetAlpha(), 0)
    T.eq(b.icon:GetNumPoints(), 2, "the icon sits inside the socket's rim")
    local key = stub.actionbars.Skin.GetParts(b).key
    T.eq(key.__font[2], stub.actionbars.Skin.HOTKEY.size, "small, crisp keybinds")
    T.eq(key.__font[1], DaylightUI.Style.FONT, "in our font")
    T.eq(b.HotKey:GetAlpha(), 0, "the game's own keybind text is hidden: ours stands in")
    T.truthy(DaylightUI.Style.GetShell(b), "in the shell's border, like the aura icons")
    T.truthy(not b.icon.__masks or #b.icon.__masks == 0, "square: no rounding mask")
end)

T.test("action bars: empty slots hide until a drag, or show see-through when asked", function()
    local DUI = login()
    local Skin = stub.actionbars.Skin
    local empty, full = Skin.GetParts(_G.DaylightUIBar1Button4), Skin.GetParts(_G.DaylightUIBar1Button2)
    T.eq(empty.back:GetAlpha(), 0, "hidden by default")
    DUI:Set("ActionBars", "hideEmpty", false)
    T.eq(empty.back:GetAlpha(), Skin.EMPTY_ALPHA, "shown when asked, see-through")
    T.eq(Skin.GetParts(_G.DaylightUIBar1Button4).key:GetAlpha(), 1, "its keybind isn't faded")
    T.eq(empty.shade:GetAlpha(), 0, "no icon shading ring on an empty slot")
    T.eq(full.shade:GetAlpha(), 1)
    DUI:Set("ActionBars", "hideEmpty", true)
    T.eq(full.back:GetAlpha(), 1, "a slot with an action stays")
    local function settle()
        local d = DUI.Motion.Driver()
        for _ = 1, 30 do if d then stub.RunOnUpdate(d, 1 / 60) end end
    end
    stub.FireEvent("ACTIONBAR_SHOWGRID")
    settle()
    T.eq(empty.back:GetAlpha(), 1, "back while dragging (eased in)")
    stub.FireEvent("ACTIONBAR_HIDEGRID")
    settle()
    T.eq(empty.back:GetAlpha(), 0)
end)

T.test("action bars: short of power fades like out of range (never blue); a proc colors the backing", function()
    login()
    local Skin = stub.actionbars.Skin
    local b = _G.DaylightUIBar1Button2
    local function color() return Skin.GetParts(b).color end
    T.eq(color(), Skin.NORMAL, "normally black")
    -- The skin redoes its buttons once, the frame after a burst of events.
    local function usable() stub.FireEvent("ACTIONBAR_UPDATE_USABLE"); stub.RunTimers() end
    stub.noMana[2] = true
    usable()
    T.eq(color(), Skin.NORMAL, "short of power: the backing stays black")
    settle()
    T.eq(b.icon:GetAlpha(), Skin.OUT_OF_RANGE, "and the icon fades, as out of range")
    -- Nothing of the game's tints the addon's own buttons, since they're off its watchers.
    T.eq(b.icon.__vertex[3], 1, "never the game's blue"); T.eq(b.icon.__vertex[1], 1)
    stub.FireEvent("ACTION_RANGE_CHECK_UPDATE", 2, false, true)
    settle()
    T.eq(b.icon:GetAlpha(), Skin.OUT_OF_RANGE, "out of range too: still faded")
    ActionButtonSpellAlertManager:ShowAlert(b)
    T.eq(color(), Skin.STATE.proc, "a proc colors the backing")
    ActionButtonSpellAlertManager:HideAlert(b)
    stub.FireEvent("ACTION_RANGE_CHECK_UPDATE", 2, true, true)
    settle()
    T.eq(b.icon:GetAlpha(), Skin.OUT_OF_RANGE, "back in range but still short: faded")
    stub.noMana[2] = nil
    usable()
    T.eq(color(), Skin.NORMAL)
    settle()
    T.eq(b.icon:GetAlpha(), 1, "power back: solid again")
end)

T.test("action bars: range and power tints glide to their goal, a new goal mid-way wins", function()
    login()
    local Skin = stub.actionbars.Skin
    local b = _G.DaylightUIBar1Button2
    local d
    stub.FireEvent("ACTION_RANGE_CHECK_UPDATE", 2, false, true)
    d = DaylightUI.Motion.Driver()
    stub.RunOnUpdate(d, 0.03)
    local mid = b.icon:GetAlpha()
    T.truthy(mid < 1 and mid > Skin.OUT_OF_RANGE, "fading, not flicked")
    T.near(Skin.GetParts(b).shade:GetAlpha(), mid, 1e-9, "the shading with it")
    stub.FireEvent("ACTION_RANGE_CHECK_UPDATE", 2, true, true)   -- back in range mid-fade
    settle()
    T.eq(b.icon:GetAlpha(), 1, "ends exactly at the second goal")
    stub.FireEvent("ACTION_RANGE_CHECK_UPDATE", 2, false, true)
    settle()
    T.eq(b.icon:GetAlpha(), Skin.OUT_OF_RANGE, "and exactly at a goal left alone")
end)

T.test("action bars: tints snap with motion off, on an emptied slot, and on a fresh skin", function()
    local DUI = login()
    local Skin = stub.actionbars.Skin
    local b = _G.DaylightUIBar1Button2
    DUI.DB.General().motion = false
    stub.FireEvent("ACTION_RANGE_CHECK_UPDATE", 2, false, true)
    T.eq(b.icon:GetAlpha(), Skin.OUT_OF_RANGE, "motion off: at once")
    DUI.DB.General().motion = true
    stub.FireEvent("ACTION_RANGE_CHECK_UPDATE", 2, true, true)
    T.truthy(b.icon:GetAlpha() < 1, "gliding back")
    Skin.Apply(b)
    T.eq(b.icon:GetAlpha(), 1, "a fresh skin (bar re-laid out) snaps to the goal")
    stub.FireEvent("ACTION_RANGE_CHECK_UPDATE", 2, false, true)
    T.truthy(Skin.GetParts(b).tweening, "gliding out")
    local had = _G.HasAction
    _G.HasAction = function(slot) return slot == 3 end      -- slot 2 emptied mid-glide (abworld has 2 and 3 full)
    Skin.UpdateEmpty(b)
    T.eq(Skin.GetParts(b).shade:GetAlpha(), 0, "no shading on an empty slot, at once")
    T.falsy(Skin.GetParts(b).tweening, "the glide stopped")
    _G.HasAction = had
end)

T.test("action bars: color mode glides the tint and lifts it to white", function()
    local DUI = login()
    local Skin = stub.actionbars.Skin
    local b = _G.DaylightUIBar1Button2
    DUI:Set("ActionBars", "look.range", "color"); stub.RunTimers()
    stub.FireEvent("ACTION_RANGE_CHECK_UPDATE", 2, false, true)
    settle()
    T.near(b.icon.__vertex[1], Skin.RANGE_COLOR[1], 1e-9, "the range color, exactly")
    stub.FireEvent("ACTION_RANGE_CHECK_UPDATE", 2, true, true)
    settle()
    T.eq(b.icon.__vertex[1], 1); T.eq(b.icon.__vertex[2], 1); T.eq(b.icon.__vertex[3], 1)
    T.isnil(Skin.GetParts(b).tintR, "white, and no longer ours")
end)

T.test("action bars: the press watcher only looks while a mouse button is down", function()
    login()
    local b = _G.DaylightUIBar1Button2
    local Skin = stub.actionbars.Skin
    local before = select(4, b.icon:GetPoint(1))
    local mouse = false
    local old = _G.IsMouseButtonDown
    _G.IsMouseButtonDown = function() return mouse end
    hover(b)
    b:SetButtonState("PUSHED")
    Skin.Tick(0.01)
    T.eq(select(4, b.icon:GetPoint(1)), before, "no mouse button down: the buttons aren't looked at")
    mouse = true
    Skin.Tick(0.01)
    T.truthy(select(4, b.icon:GetPoint(1)) > before, "a click: sunk in")
    mouse = false
    b:SetButtonState("NORMAL")
    Skin.Tick(0.01)
    T.eq(select(4, b.icon:GetPoint(1)), before, "let go: seen even with the mouse already up")
    _G.IsMouseButtonDown = old
end)

T.test("action bars: a keybind is shortened again only when its text changes", function()
    login()
    local b = _G.DaylightUIBar1Button2
    local Skin = stub.actionbars.Skin
    local parts = Skin.GetParts(b)
    b.HotKey:SetText("SHIFT-1")
    Skin.UpdateKey(b)
    local shown = parts.key:GetText()
    local writes = 0
    local real = parts.key.SetText
    parts.key.SetText = function(self, ...) writes = writes + 1; return real(self, ...) end
    Skin.UpdateKey(b); Skin.UpdateKey(b)
    T.eq(writes, 0, "same text: nothing done")
    b.HotKey:SetText("CTRL-2")
    Skin.UpdateKey(b)
    T.eq(writes, 1, "new text: written")
    T.truthy(parts.key:GetText() ~= shown)
end)

T.test("action bars: a press dips the icon", function()
    login()
    local b = _G.DaylightUIBar1Button2
    local Skin = stub.actionbars.Skin
    local before = select(4, b.icon:GetPoint(1))
    hover(b)
    b:SetButtonState("PUSHED")
    Skin.Tick(0.01)
    T.truthy(select(4, b.icon:GetPoint(1)) > before, "sunk in")
    b:SetButtonState("NORMAL")
    Skin.Tick(0.01)
    T.eq(select(4, b.icon:GetPoint(1)), before)
    -- Update is replaced on purpose in Buttons.Make, not hooked.
    T.eq(rawget(b, "UpdateButtonArt"), BaseActionButtonMixin.UpdateButtonArt, "nothing hooked onto the game's button")
end)

T.test("action bars: letting go springs the icon back (dip on), not with the dip off", function()
    local DUI = login()
    local b = _G.DaylightUIBar1Button2
    local Skin = stub.actionbars.Skin
    local parts = Skin.GetParts(b)
    hover(b)
    b:SetButtonState("PUSHED"); Skin.Tick(0.01)
    T.falsy(b.icon.__duiBump and b.icon.__duiBump:IsPlaying(), "the press itself is instant")
    b:SetButtonState("NORMAL"); Skin.Tick(0.01)
    T.truthy(b.icon.__duiBump and b.icon.__duiBump:IsPlaying(), "springs back on release")
    T.truthy(parts.shade.__duiBump and parts.shade.__duiBump:IsPlaying(), "its shading too")
    Skin.SetKeyDown(b, true); b.icon.__duiBump:Stop()
    Skin.SetKeyDown(b, false)
    T.truthy(b.icon.__duiBump:IsPlaying(), "a key's release springs too")
    DUI:Set("ActionBars", "look.dip", false); stub.RunTimers()
    b.icon.__duiBump:Stop()
    Skin.SetKeyDown(b, true); Skin.SetKeyDown(b, false)
    T.falsy(b.icon.__duiBump:IsPlaying(), "dip off: no spring")
end)

T.test("action bars: press and release in combat raise no error", function()
    login()
    local b = _G.DaylightUIBar1Button2
    local Skin = stub.actionbars.Skin
    stub.EnterCombat()
    Skin.SetKeyDown(b, true); Skin.SetKeyDown(b, false)
    hover(b)
    b:SetButtonState("PUSHED"); Skin.Tick(0.01)
    b:SetButtonState("NORMAL"); Skin.Tick(0.01)
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("action bars: pet and stance bars are skinned; totems move to our player frame", function()
    stub.Load({ module = true, actionbars = true, before = world })
    local Skin = stub.actionbars.Skin
    T.truthy(Skin.IsSkinned(_G.StanceButton1)); T.truthy(Skin.IsSkinned(_G.PetActionButton1))
    DaylightUI:Set("ActionBars", "hideEmpty", true)
    T.eq(Skin.GetParts(_G.PetActionButton1).back:GetAlpha(), 1, "a pet ability shows")
    T.eq(Skin.GetParts(_G.PetActionButton5).back:GetAlpha(), 0, "an empty pet slot hides")
    T.eq(TotemFrame:GetParent(), UIParent, "out from under the hidden player frame")
    local _, rel = TotemFrame:GetPoint(1)
    T.eq(rel, _G.DaylightUIFrame_player, "above our player frame")
    local totem = select(1, TotemFrame:GetChildren())
    T.eq(totem.Border:GetAlpha(), 0, "the game's totem border hidden")
end)

T.test("action bars: totem timers stay on our player frame when a new totem goes down", function()
    login()
    stub.RunTimers()
    -- All totems gone, then a new one: the game shows the frame again.
    TotemFrame:Hide()
    TotemFrame:Show()
    stub.RunTimers()
    T.eq(TotemFrame:GetParent(), UIParent, "not taken back under the hidden game player frame")
    local _, rel = TotemFrame:GetPoint(1)
    T.eq(rel, _G.DaylightUIFrame_player, "still above our player frame")
end)

-- TotemFrameMixin:Update (Blizzard_UnitFrame/Mainline/TotemFrame.lua): a totem
-- down takes a button from its pool, then self:Layout() runs at once
-- (HorizontalLayoutMixin: TOPLEFT, each after the last's width plus `spacing`).
-- A button new to the pool is laid out at its full width before the addon
-- narrows it, so the ones after it sat at the game's wider gap.
T.test("action bars: a totem just put down sits at the tighter gap at once", function()
    login()
    stub.RunTimers()
    local tf = TotemFrame
    local first = select(1, tf:GetChildren())
    first.layoutIndex = 1
    function tf:Layout()
        local kids = {}
        for _, c in ipairs({ self:GetChildren() }) do
            if c.layoutIndex and c:IsShown() then kids[#kids + 1] = c end
        end
        table.sort(kids, function(a, b) return a.layoutIndex < b.layoutIndex end)
        local x, w = 15, 0
        for i, c in ipairs(kids) do
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", self, "TOPLEFT", x, 2)
            x = x + c:GetWidth() + self.spacing
            w = w + c:GetWidth() + (i > 1 and self.spacing or 0)
        end
        self:SetWidth(15 + w)
    end
    local second
    function tf:Update()
        if not second then
            second = CreateFrame("Button", nil, self)
            second:SetSize(37, 37)
            second.Icon = CreateFrame("Frame", nil, second)
            second.Icon.Texture = second.Icon:CreateTexture()
            second.Duration = second:CreateFontString()
            second.slot, second.layoutIndex = 2, 0     -- earth before fire, by their priorities
        end
        self:Layout()
    end
    tf:GetScript("OnEvent")(tf, "PLAYER_TOTEM_UPDATE")
    local _, _, _, x1 = first:GetPoint(1)
    local _, _, _, x2 = second:GetPoint(1)
    T.eq(second:GetWidth(), 37 - stub.actionbars.Totems.TIMER_TIGHTEN, "the new one narrowed")
    T.eq(x1 - x2, second:GetWidth() + tf.spacing, "the one after it at the tighter gap, not the game's first one")
    T.eq(tf:GetWidth(), 15 + first:GetWidth() + tf.spacing + second:GetWidth(), "the frame as wide as its next layout")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("action bars: totem timers fade, and can be switched off and on", function()
    local DUI = login()
    stub.RunTimers()
    local Fade, tf = DUI.Fade, _G.TotemFrame
    local function settle() Fade.Step(); for _ = 1, 120 do stub.RunOnUpdate(Fade.driver, 1 / 60) end end
    T.truthy(Fade.State("ActionBars.totemTimers"), "a fade of their own")
    DUI:Set("ActionBars", "totemTimersFade.mode", "always")
    DUI:Set("ActionBars", "totemTimersFade.alpha", 0.2)
    stub.now = (stub.now or 0) + 10   -- abworld's clock, past the delay and the peek
    settle()
    T.near(tf:GetAlpha(), 0.2, 0.01, "faded without the mouse")
    tf.IsMouseOver = function() return true end
    settle()
    T.eq(tf:GetAlpha(), 1, "back under the mouse")
    tf.IsMouseOver = nil
    DUI:Set("ActionBars", "totemTimers", false)
    stub.RunTimers()
    T.eq(tf:GetParent(), stub.actionbars.Hide.parent, "off: parked in the hidden frame")
    tf:Hide(); tf:Show(); stub.RunTimers()
    T.eq(tf:GetParent(), stub.actionbars.Hide.parent, "a new totem doesn't bring them back")
    T.falsy(DUI.Movers.Get("actionbars.totemtimers").active(), "no handle in unlock mode")
    DUI:Set("ActionBars", "totemTimers", true)
    stub.RunTimers()
    T.eq(tf:GetParent(), UIParent, "on again")
    local _, rel = tf:GetPoint(1)
    T.eq(rel, _G.DaylightUIFrame_player, "back above our player frame")
end)


T.test("action bars: totem timers get a mover, a saved spot, and the buff-bar look", function()
    local DUI = login()
    local tf = _G.TotemFrame
    T.truthy(DUI.Movers.Get("actionbars.totemtimers"), "it gets a mover")
    local totem = select(1, tf:GetChildren())
    stub.RunTimers()
    -- Closer together without writing on the game's frame. An addon value there
    -- taints its layout (and PlayerFrame_AdjustAttachments after it).
    T.eq(tf.spacing, -6, "the game's spacing untouched")
    T.isnil(rawget(tf, "dirty"), "its layout never run by us")
    T.eq(totem:GetWidth(), 37 - 4, "each timer a little narrower")
    local point, rel, relPoint = totem.Duration:GetPoint(1)
    T.eq(point, "CENTER"); T.eq(relPoint, "TOP"); T.eq(rel, totem.Icon.Texture, "time on the icon's top edge")
    local r, g, b = DUI.Style.Soften(0.9, 0.35, 0.15)
    local edge
    for _, reg in ipairs({ totem:GetRegions() }) do
        if rawget(reg, "__texture") == "Interface\\Buttons\\WHITE8X8" then edge = reg end
    end
    T.truthy(edge, "an edge texture")
    if edge then
        local er, eg, eb = edge:GetVertexColor()
        T.near(er, r, 0.001); T.near(eg, g, 0.001); T.near(eb, b, 0.001)
    end
    -- The time is written the buff bar's way, not the game's "55 s".
    local oldInfo, oldTime = _G.GetTotemInfo, _G.GetTime
    _G.GetTotemInfo = function() return true, "Searing Totem", 100, 60, 1 end
    _G.GetTime = function() return 105 end
    local update = tf.Update
    tf:GetScript("OnEvent")(tf, "PLAYER_TOTEM_UPDATE")  -- the game updates the timers, and the addon's follow
    T.eq(tf.Update, update, "no hook on the timers' Update")
    local found
    for _, child in ipairs({ totem:GetChildren() }) do
        for _, reg in ipairs({ child:GetRegions() }) do
            if reg.GetText and reg:GetText() == "55s" then found = true end
        end
    end
    T.truthy(found, "our time reads 55s")
    -- minutes round up like the game's own text (shown in a fight), so 2:50 left
    -- never reads 2m out of a fight and 3 m in one
    local Totems = stub.actionbars.Totems
    T.eq(Totems.Time(170), "3m")
    T.eq(Totems.Time(120), "2m")
    T.eq(Totems.Time(121), "3m")
    T.eq(Totems.Time(59.6), "59s")
    T.eq(Totems.Time(3601), "2h")
    T.eq(totem.Duration:GetAlpha(), 0, "the game's own time is hidden")
    _G.GetTotemInfo, _G.GetTime = oldInfo, oldTime
    DUI.Movers.Unlock()
    DUI.DB.Positions()["actionbars.totemtimers"] = { 120, -40 }
    DUI.Movers.Get("actionbars.totemtimers").onMoved("actionbars.totemtimers")
    DUI.Movers.Lock()
    local p, _, _, x, y = tf:GetPoint(tf:GetNumPoints())
    T.eq(p, "CENTER"); T.truthy(x ~= nil and y ~= nil)
    T.isnil(rawget(tf, "SetPoint"), "no hook on the timers' SetPoint")
    tf:ClearAllPoints(); tf:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.RunTimers()
    local _, _, _, x2, y2 = tf:GetPoint(tf:GetNumPoints())
    T.eq(x2, x, "put back where it was saved"); T.eq(y2, y)
end)

T.test("action bars: not a shaman, the game's totem bar is never touched", function()
    login()
    local mc = _G.MultiCastActionBarFrame
    local parent, n = mc:GetParent(), mc:GetNumPoints()
    T.isnil(rawget(mc, "SetPoint"), "no hook")
    T.eq(mc:GetParent(), parent); T.eq(mc:GetNumPoints(), n, "not moved")
    T.eq(mc.__scale, 1, "not scaled")
    T.falsy(stub.actionbars.Skin.IsSkinned(_G.MultiCastActionButton1), "its buttons not skinned")
end)

T.test("action bars: the small bars cap the center bars, smaller", function()
    local ns = stub.Load({ actionbars = true, before = world }) and stub.actionbars
    local d = ns.Shape.Defaults()
    T.eq(d.stance.point, "BOTTOMLEFT"); T.eq(d.pet.point, "BOTTOMRIGHT")
    T.truthy(d.stance.y > d.bar2.y + ns.Shape.BUTTON * 0.7, "above bar 2")
    T.eq(d.pet.size, ns.Shape.SMALL_SIZE)
end)

T.test("action bars: the bag bar and micro menu are parked, not destroyed", function()
    login()
    T.eq(BagsBar:GetParent(), stub.actionbars.Hide.parent)
    T.eq(MicroMenuContainer:GetParent(), stub.actionbars.Hide.parent)
end)

T.test("action bars: a side grid fades smoothly, frame by frame, not in the check's steps", function()
    login()
    local Fade = DaylightUI.Fade
    T.eq(DaylightUIBar4:GetAlpha(), 0, "starts faded on login")
    DaylightUIBar4.IsMouseOver = function() return true end
    Fade.Step()
    for _ = 1, 60 do stub.RunOnUpdate(Fade.driver, 1 / 60) end
    T.eq(DaylightUIBar4:GetAlpha(), 1, "back under the mouse")
    DaylightUIBar4.IsMouseOver = function() return false end
    stub.now = (stub.now or 0) + 4   -- abworld's clock
    for _ = 1, 40 do Fade.Step() end          -- past the delay, so it should go
    T.eq(DaylightUIBar4:GetAlpha(), 1, "the check alone doesn't move it")
    local last, steps, biggest = 1, 0, 0
    while DaylightUIBar4:GetAlpha() > 0 and steps < 200 do
        stub.RunOnUpdate(Fade.driver, 1 / 60)
        local a = DaylightUIBar4:GetAlpha()
        biggest = math.max(biggest, last - a)
        last = a
        steps = steps + 1
    end
    T.eq(DaylightUIBar4:GetAlpha(), 0, "gets there")
    T.truthy(steps >= 12, "over many frames (" .. steps .. ")")
    T.truthy(biggest < 0.2, "no big jumps (" .. biggest .. ")")
    T.falsy(Fade.driver:IsShown(), "and stops running once it's there")
end)

T.test("action bars: the cooldown sweep is dark and square; the cast animation is hidden", function()
    login()
    local b = DaylightUIBar1Button2
    local cd = CreateFrame("Cooldown", nil, b)
    function cd:SetSwipeTexture(t) self.__swipe = t end
    function cd:SetSwipeColor(r, g, bl, a) self.__swipeColor = { r, g, bl, a } end
    function cd:SetDrawBling(v) self.__bling = v end
    b.cooldown = cd
    b.SpellCastAnimFrame = CreateFrame("Frame", nil, b)
    DaylightUI:Set("ActionBars", "hideEmpty", true)
    stub.RunTimers()
    T.eq(cd.__swipe, stub.actionbars.Skin.SWIPE_FILE, "square")
    T.eq(cd.__swipeColor[1], 0, "dark, not the white of the shape texture")
    T.eq(cd.__bling, false, "no bright flash at the end")
    T.eq(b.SpellCastAnimFrame:GetAlpha(), 0, "no yellow cast fill")
end)

-- A Cooldown Manager viewer with icons, shaped as the game's.
local function viewer(name, n)
    local v = CreateFrame("Frame", name, UIParent)
    local items = {}
    for i = 1, n do
        local item = CreateFrame("Frame", nil, v)
        item:SetSize(40, 40)
        item.Icon = item:CreateTexture()
        local gameMask = item:CreateMaskTexture()
        item.Icon:AddMaskTexture(gameMask)
        function item.Icon:GetNumMaskTextures() return #(self.__masks or {}) end
        function item.Icon:GetMaskTexture(k) return self.__masks[k] end
        item.overlay = item:CreateTexture()
        item.Cooldown = CreateFrame("Cooldown", nil, item)
        function item.Cooldown:SetSwipeColor(r) self.__swipeR = r end
        item.ChargeCount = CreateFrame("Frame", nil, item)
        item.ChargeCount.Current = item.ChargeCount:CreateFontString()
        function item.ChargeCount.Current:SetFont(f, s) self.__font = { f, s } end
        items[i] = item
    end
    v.itemFramePool = { EnumerateActive = function()
        local i = 0
        return function() i = i + 1; return items[i] end
    end }
    function v:RefreshLayout() end
    return v, items
end

T.test("action bars: the Cooldown Manager's icons get the buttons' look", function()
    local _, items
    stub.Load({ actionbars = true, before = function()
        world()
        _, items = viewer("EssentialCooldownViewer", 2)
    end })
    stub.RunTimers()
    local item = items[1]
    T.eq(#item.Icon.__masks, 0, "the game's rounding mask off: square")
    T.eq(item.overlay:GetAlpha(), 0, "the game's frame art hidden")
    T.eq(select(2, item.Icon:GetPoint(1)), item, "inset in the backing")
    T.eq(item.Cooldown.__swipeR, 0, "the dark sweep")
    T.eq(item.ChargeCount.Current.__font[1], DaylightUI.Style.FONT, "our font on charges")
    T.truthy(DaylightUI.Style.GetShell(item), "in the shell's border")
end)

T.test("action bars: a viewer made later is skinned when its addon loads, and new icons on layout", function()
    login()
    local v, items = viewer("UtilityCooldownViewer", 1)
    stub.FireEvent("ADDON_LOADED", "Blizzard_CooldownViewer")
    T.eq(items[1].overlay:GetAlpha(), 0, "skinned on load")
    local late = CreateFrame("Frame", nil, v)
    late.Icon = late:CreateTexture()
    late.extra = late:CreateTexture()
    items[2] = late
    -- The game's layout pass grew its grid (the client runs the viewer's
    -- OnSizeChanged, which the fake game doesn't do on its own). There's no hook
    -- on its RefreshLayout; the re-claim pass skins the new icon the frame after.
    v:GetScript("OnSizeChanged")(v)
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(late.extra:GetAlpha(), 0, "a new icon, on the next layout")
end)

T.test("action bars: a Cooldown Manager icon that appears without a layout is caught", function()
    local v, items
    stub.Load({ actionbars = true, before = function()
        world()
        v, items = viewer("BuffIconCooldownViewer", 1)
    end })
    stub.RunTimers()
    local late = CreateFrame("Frame", nil, v)
    late:SetSize(40, 40)
    late.Icon = late:CreateTexture()
    late.DebuffBorder = late:CreateTexture()
    items[2] = late
    stub.actionbars.Cooldowns.Scan()
    T.eq(select(2, late.Icon:GetPoint(1)), late, "skinned by the look-around")
    T.eq(late.DebuffBorder:GetAlpha(), 0, "its square debuff line hidden")
    -- No hook on the game's icon. Its Lua never anchors the icon (the frame's
    -- OnSizeChanged and OnShow re-place it), and hooks on the game's own methods
    -- broke its calls before. test_guards refuses one.
end)

T.test("action bars: a Cooldown Manager icon on a sub-frame is shaded from that frame, and stays square", function()
    local v, items
    stub.Load({ actionbars = true, before = function()
        world()
        v, items = viewer("BuffIconCooldownViewer", 0)
    end })
    local item = CreateFrame("Frame", nil, v)
    item:SetSize(40, 40)
    local sub = CreateFrame("Frame", nil, item)
    item.Icon = sub:CreateTexture()
    items[1] = item
    stub.actionbars.Cooldowns.Scan()
    local shaded = false
    for _, r in ipairs({ sub:GetRegions() }) do
        if r.__texture == stub.actionbars.Skin.SHADE_FILE then shaded = true end
    end
    T.truthy(shaded, "the inner shadow on the icon's own frame, drawing over it")
    -- The game's mask comes from its XML and is taken off once. There's no hook
    -- on its AddMaskTexture since the game's Lua never adds one again.
    T.eq(#(item.Icon.__masks or {}), 0)
end)

T.test("action bars: a Cooldown Manager debuff border is hidden where it is, never re-anchored", function()
    local v, items
    stub.Load({ actionbars = true, before = function()
        world()
        v, items = viewer("BuffIconCooldownViewer", 0)
    end })
    local item = CreateFrame("Frame", nil, v)
    item:SetSize(40, 40)
    item.Icon = item:CreateTexture()
    item.DebuffBorder = CreateFrame("Frame", nil, item)
    item.DebuffBorder:SetPoint("TOPLEFT", item.Icon, "TOPLEFT", 2, -2)
    items[1] = item
    stub.actionbars.Cooldowns.Scan()
    T.eq(item.DebuffBorder:GetAlpha(), 0, "hidden")
    T.eq(select(1, item.DebuffBorder:GetPoint(1)), "TOPLEFT", "left where the game put it")
    T.eq(select(2, item.DebuffBorder:GetPoint(1)), item.Icon)
end)

T.test("action bars: the Cooldown Manager's bar view gets our border too, not just its icon", function()
    local v, items
    stub.Load({ actionbars = true, before = function()
        world()
        v, items = viewer("BuffBarCooldownViewer", 0)
    end })
    local item = CreateFrame("Frame", nil, v)
    item:SetSize(160, 20)
    item.Icon = item:CreateTexture()
    item.Bar = CreateFrame("StatusBar", nil, item)
    item.Bar.Name = item.Bar:CreateFontString()
    item.Bar.Duration = item.Bar:CreateFontString()
    local barArt = item.Bar:CreateTexture() -- the game's own backdrop on the bar
    items[1] = item
    stub.actionbars.Cooldowns.Scan()
    local p = stub.actionbars.Cooldowns.Parts(item)
    T.truthy(DaylightUI.Style.GetShell(p.slot), "the bar in our border, not just the icon")
    T.eq(select(2, p.slot:GetPoint(1)), item.Bar, "the border frame around the bar, outside its fill")
    T.truthy(p.slot:GetFrameLevel() < item.Bar:GetFrameLevel(), "under the bar")
    T.eq(barArt:GetAlpha(), 0, "the game's own bar art hidden")
    T.eq(item.Bar:GetStatusBarTexture():GetAlpha(), 1, "the fill left alone (Style.TrackBar owns it)")
    T.eq(item.Bar.Name.__font[1], DaylightUI.Style.FONT, "our font on the bar's text")
end)

T.test("action bars: the Cooldown Manager section has one page, Layout", function()
    local DUI = login()
    local found
    for _, s in ipairs(DUI.Options.Sections()) do
        if s.id == "CooldownManager" then found = s end
    end
    T.truthy(found, "section listed")
    T.eq(#found.pages, 1)
    T.eq(found.pages[1].id, "cdm.layout")
    T.eq(#DUI.Options.ValidatePage(found.pages[1]), 0, "validates")
    for _, g in ipairs(stub.actionbars.OPTIONS.pages[1].groups) do
        for _, it in ipairs(g.items) do T.truthy(it.key ~= "cooldowns", "not on the Look page") end
    end
end)

-- The bar viewer with n bars shaped as the game's (the icon is a small frame
-- holding the texture), and the addon's player frame at a known place.
local function barWorld(n)
    local v, items, pf
    local DUI = stub.Load({ actionbars = true, before = function()
        world()
        pf = CreateFrame("Frame", "DaylightUIFrame_player", UIParent)
        pf:SetSize(200, 40)
        function pf:GetLeft() return 300 end
        function pf:GetBottom() return 100 end
        function pf:GetTop() return 140 end
        v, items = viewer("BuffBarCooldownViewer", 0)
        for i = 1, n do
            local item = CreateFrame("Frame", nil, v)
            item:SetSize(270, 30)
            item.layoutIndex = i
            item.Icon = CreateFrame("Frame", nil, item)
            item.Icon.Icon = item.Icon:CreateTexture()
            item.Bar = CreateFrame("StatusBar", nil, item)
            item.Bar.Name = item.Bar:CreateFontString()
            item.Bar.Duration = item.Bar:CreateFontString()
            items[i] = item
        end
    end })
    stub.RunTimers()
    stub.actionbars.Cooldowns.Scan()
    return DUI, v, items, pf
end

-- A player's error: the game writes a buff bar's time from its CooldownViewer data
-- callback (RefreshCooldownInfo, durationFontString:SetText("")), and with an
-- addon post-hook on that text the call failed with "attempt to call a nil value"
-- in CooldownViewer.lua.
T.test("action bars: a buff bar's time text is the game's own, never hooked", function()
    local _, _, items = barWorld(1)
    local d = items[1].Bar.Duration
    T.isnil(rawget(d, "SetText"), "no hook on its SetText")
    T.isnil(rawget(d, "SetFormattedText"), "or its SetFormattedText")
    d:SetText("178")
    T.eq(d:GetText(), "178", "the game's text stays as it wrote it")
    T.eq(stub.actionbars.Cooldowns.BarBorder(4), 2, "half the general border")
    T.eq(stub.actionbars.Cooldowns.BarBorder(1), 1, "never under a pixel")
    T.eq(DaylightUI.Style.IsHeavy({ opts = { borderPx = 3, heavyMinPx = 4 } }), false, "thin bar stays plain")
    T.eq(DaylightUI.Style.IsHeavy({ opts = { borderPx = 3 } }), true, "a frame is heavy from 3px")
    -- The dev tools' /dui cdm report walks the bar viewer.
    if T.dev then
        assert(loadfile("DaylightUI_Dev/CdmProbe.lua"))("DaylightUI_Dev", {})
        DaylightUI.RunCommand("cdm")
        T.truthy(stub.ChatContains("BuffBarCooldownViewer:"), "the report ran")
        DaylightUIDevDB = nil
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The time as M:SS without touching the game's text: an addon clock over the bar's
-- right end, its text written by the client's aura button (in combat too) through
-- the addon's formatter.
T.test("action bars: a game buff bar's time is our M:SS clock over the game's text", function()
    local _, _, items = barWorld(1)
    local item, BB = items[1], stub.actionbars.BuffBars
    item.cooldownID = 101
    BB.SyncClocks()
    local h = BB.Clock(101)
    T.truthy(h and h:IsShown(), "a clock for the spell")
    T.eq(h:GetParent(), item.Bar, "on its bar")
    T.eq(select(2, h:GetPoint(1)), item.Bar)
    T.falsy(item.Bar.Duration:IsShown(), "the game's time hidden under it")
    local c = h.containers[1].c
    local btn = c.__groups.a.button
    T.truthy(btn.__time, "the client writes the time")
    T.eq(btn.__timeOpts.textFormatter, DaylightUI.Style.ClockFormatter(), "as M:SS")
    T.eq(btn.__time:GetParent(), btn, "a text inside the client's button")
    -- Placed on the clock (the middle of the bar's right end), not on the button,
    -- which the client sizes and places itself. Otherwise the time sat low on the bar.
    local p, rel, relP, x, y = btn.__time:GetPoint(1)
    T.eq(p, "RIGHT"); T.eq(rel, h); T.eq(relP, "RIGHT"); T.eq(x, -BB.CLOCK_PAD); T.eq(y, 0)
    -- A taller bar in a PvP match: the client's button waits for the match to end.
    stub.SetRestriction("PvPMatch", true)
    item.Bar:SetSize(250, 26)
    BB.SyncClocks()
    T.eq(stub.lockErrors, 0, tostring(next(stub.lockSites)))
    T.truthy(btn:GetHeight() ~= 26, "not touched in the match")
    stub.SetRestriction("PvPMatch", false)
    stub.RunTimers()
    T.eq(btn:GetHeight(), 26, "after it")
    -- The game hands the pooled bar to another spell, and the clock goes with the spell.
    item.cooldownID = 202
    BB.SyncClocks()
    T.falsy(h:IsShown(), "the old spell's clock hides")
    T.eq(BB.Clock(202):GetParent(), item.Bar, "the new spell's clock on the bar")
    -- A totem's bar has no aura to find, so it uses the game's own time.
    function item:GetTotemData() return { duration = 60 } end
    BB.SyncClocks()
    T.truthy(item.Bar.Duration:IsShown(), "a totem keeps the game's time")
    T.falsy(BB.Clock(202):IsShown())
    item.GetTotemData = nil
    -- First seen in combat: aura containers are made out of combat.
    item.cooldownID = 303
    stub.EnterCombat()
    BB.SyncClocks()
    T.isnil(BB.Clock(303), "no clock made in combat")
    T.truthy(item.Bar.Duration:IsShown(), "the game's time meanwhile")
    stub.LeaveCombat()
    BB.SyncClocks()
    T.truthy(BB.Clock(303) and BB.Clock(303):IsShown(), "made once the fight ends")
    T.falsy(item.Bar.Duration:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A player saw blocked-action popups over and over after Install, then a frozen
-- game. The game fires its layouts event after each save, and a part that never
-- agrees with what the game kept (it rounds or clamps a value) must not make every
-- event write the layout again.
T.test("edit mode: a part the saved layout never satisfies doesn't rewrite it in a loop", function()
    local DUI = login()
    DUI.EditMode.Add("never", function() end, function() return false end)
    local writes, save = 0, C_EditMode.SaveLayouts
    C_EditMode.SaveLayouts = function(info)
        writes = writes + 1
        save(info)
        if writes < 20 then stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED") end
    end
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    DUI.Installer.Install()
    T.eq(writes, 1, "the install's own write, and no more until a reload")
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    T.eq(writes, 1, "a later event doesn't write either")
end)

T.test("core: an action the game blocks is named in chat, once", function()
    login()
    stub.FireEvent("ADDON_ACTION_BLOCKED", "DaylightUI", "MultiBarBottomLeft:SetPoint()")
    T.truthy(stub.ChatContains("MultiBarBottomLeft:SetPoint()"), "named")
    stub.chat = {}
    stub.FireEvent("ADDON_ACTION_BLOCKED", "DaylightUI", "MultiBarBottomLeft:SetPoint()")
    T.falsy(stub.ChatContains("MultiBarBottomLeft"), "once")
    stub.FireEvent("ADDON_ACTION_FORBIDDEN", "SomeoneElse", "Foo()")
    T.falsy(stub.ChatContains("Foo()"), "only ours")
end)

T.test("edit mode: a new layout starts from the bundled one, goes where the game puts account layouts, and is announced", function()
    local DUI = login()
    C_EditMode.ConvertStringToLayoutInfo = function(s)
        if s ~= DaylightUI.EditMode.BASE then return nil end
        local systems = {}
        for i = 1, 4 do systems[i] = { system = 0, systemIndex = i, anchorInfo = { point = "BOTTOM", offsetY = 26 }, settings = {} } end
        return { layoutName = "bigboy", layoutType = 1, systems = systems }
    end
    T.truthy(#DUI.EditMode.BASE > 1000, "the bundled layout")
    saved.layouts = { { layoutName = "mine", layoutType = 2, systems = {} } }   -- a character layout
    saved.activeLayout = 3
    local ok = DUI.EditMode.Install()
    T.truthy(ok)
    local all = saved.info.layouts
    T.eq(all[3].layoutName, "DaylightUI - DPS/Tank", "right after the presets, before character layouts")
    T.eq(all[4].layoutName, "mine")
    T.eq(saved.added, 3, "the game told it was added")
    T.eq(saved.activeLayout, 3, "and it's active")
    T.eq(all[3].systems[1].anchorInfo.offsetY, 26, "a copy of the bundled layout")
    T.eq(all[3].systems[3].anchorInfo.offsetY, 26, "its own spots kept where no part writes")
end)

T.test("edit mode: the plain name when the game won't take ours; old layouts still count; a full list is said", function()
    local DUI = login()
    C_EditMode.IsValidLayoutName = function(n) return not string.find(n, "/", 1, true) end
    DUI.EditMode.Install()
    T.eq(saved.layouts[1].layoutName, "DaylightUI DPS Tank")
    saved.layouts = { { layoutName = "DaylightUI", layoutType = 1, systems = {} } }
    saved.activeLayout = 1
    T.truthy(DUI.EditMode.Install())
    T.eq(saved.activeLayout, 3, "the old one made active, not a second one")
    T.eq(#saved.layouts, 1)
    Constants = Constants or {}
    Constants.EditModeConsts = { EditModeMaxLayoutsPerType = 1 }
    saved.layouts = { { layoutName = "other", layoutType = 1, systems = {} } }
    local ok, why = DUI.EditMode.Install()
    T.falsy(ok); T.truthy(string.find(why, "most account layouts", 1, true), "says why")
    Constants.EditModeConsts = nil
end)

T.test("edit mode: bundled text the game misreads isn't used; the Modern preset is", function()
    local DUI = login()
    Enum.InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 }
    C_EditMode.ConvertStringToLayoutInfo = function()
        return { interfaceStyle = 59, systems = { { system = 0, systemIndex = 1, anchorInfo = {}, settings = {} } } }
    end
    T.truthy(DUI.EditMode.Install())
    T.truthy(#saved.layouts[1].systems > 1, "the preset's systems, not the misread text")
    C_EditMode.SaveLayouts = function() error("bad argument") end
    saved.layouts, saved.activeLayout = {}, 1
    local ok, why = DUI.EditMode.Install()
    T.falsy(ok); T.eq(why, "the game refused the layout", "a refusal said, not thrown")
end)

T.test("edit mode: nothing is written while controller mode is on", function()
    local DUI = login()
    Enum.InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 }
    local PLM = EditModePresetLayoutManager
    local old = PLM.GetCopyOfPresetLayouts
    PLM.GetCopyOfPresetLayouts = function() return { { interfaceStyle = 1, systems = {} } } end
    saved.layouts, saved.activeLayout = {}, 1
    local ok, why = DUI.EditMode.Install()
    PLM.GetCopyOfPresetLayouts = old
    T.falsy(ok); T.truthy(string.find(why, "controller mode", 1, true), "says why")
    T.eq(#saved.layouts, 0, "no layout written")
end)

T.test("edit mode: gamepad input on, controller UI off, still installs", function()
    local DUI = login()
    Enum.InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 }
    local old = GetCVarBool
    GetCVarBool = function(name) return name == "GamePadEnable" end
    T.falsy(DUI.EditMode.GamepadMode(), "the setting alone isn't the controller UI")
    T.truthy(DUI.EditMode.Install())
    GetCVarBool = old
end)

T.test("action bars: a proc colors only its own button's border", function()
    login()
    local Skin = stub.actionbars.Skin
    ActionButtonSpellAlertManager:ShowAlert(_G.DaylightUIBar1Button2)
    T.eq(Skin.GetParts(_G.DaylightUIBar1Button2).back.opts.borderColor, Skin.STATE.proc, "the proc's button in the accent")
    T.falsy(Skin.GetParts(_G.DaylightUIBar1Button3).back.opts.borderColor, "its neighbor untouched")
end)

-- Profiles: each has its own Edit Mode layout.
local function layoutNamed(name)
    for i, l in ipairs(C_EditMode.GetLayouts().layouts) do
        if l.layoutName == name then return l, i + 2 end   -- the two presets come first
    end
end

T.test("profiles: switching to a new profile gives it its own layout, a copy of the one in use", function()
    local DUI = login()
    _G.GetNumSpecGroups = function() return 1 end
    DUI.Installer.Install()
    T.truthy(layoutNamed("DaylightUI - DPS/Tank"), "Default's layout")
    DUI.Profiles.Create("Healer")
    DUI.Profiles.Choose("character", "Healer")
    T.eq(stub.popup, "DAYLIGHTUI_PROFILE", "asked to reload")
    StaticPopupDialogs.DAYLIGHTUI_PROFILE.OnAccept(nil, "Healer")
    local l, index = layoutNamed("DaylightUI - Healer")
    T.truthy(l, "the profile's own layout")
    T.eq(C_EditMode.GetLayouts().activeLayout, index, "made active before the reload")
    T.eq(#l.systems, #layoutNamed("DaylightUI - DPS/Tank").systems, "a copy of the one in use")
    T.truthy(DUI.EditMode.IsActive("Healer"))
    T.falsy(DUI.EditMode.IsActive("Default"))
    T.truthy(stub.reloaded, "reloaded by that same click: no second Reload to press")
end)

T.test("profiles: a switch made after combat (no click) asks for the reload click", function()
    local DUI = login()
    _G.GetNumSpecGroups = function() return 1 end
    DUI.Installer.Install()
    DUI.Profiles.Create("Healer")
    DUI.Profiles.Assign("character", "Healer")
    DUI.Profiles.SwitchNow("Healer")
    T.truthy(DUI.EditMode.IsActive("Healer"))
    stub.RunTimers()
    T.falsy(stub.reloaded, "a timer can't reload (blocked without a click)")
    T.eq(stub.popup, "DAYLIGHTUI_PROFILE_RELOAD", "asks for the reload click instead")
    StaticPopupDialogs.DAYLIGHTUI_PROFILE_RELOAD.OnAccept()
    T.truthy(stub.reloaded)
end)

T.test("profiles: the game's layout update after a switch neither undoes it nor asks again", function()
    local DUI = login()
    _G.GetNumSpecGroups = function() return 1 end
    DUI.Installer.Install()
    DUI.Profiles.Create("Healer")
    DUI.Profiles.Choose("character", "Healer")
    StaticPopupDialogs.DAYLIGHTUI_PROFILE.OnAccept(nil, "Healer")
    stub.popup = nil
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")             -- the game, after the save
    T.truthy(DUI.EditMode.IsActive("Healer"), "the new profile's layout stays active")
    T.isnil(stub.popup, "no second reload asked")
    stub.RunTimers()
    T.isnil(stub.popup, "nor after the save's moment")
end)

T.test("profiles: renaming a profile renames its layout", function()
    local DUI = login()
    _G.GetNumSpecGroups = function() return 1 end
    DUI.Installer.Install()
    DUI.Profiles.Create("Healer")
    DUI.EditMode.UseProfile("Healer")
    T.truthy(DUI.Profiles.Rename("Healer", "Mender"))
    T.isnil(layoutNamed("DaylightUI - Healer"))
    T.truthy(layoutNamed("DaylightUI - Mender"))
end)

T.test("profiles: after switching without the layout, the next load puts it in place", function()
    local DUI = login()
    _G.GetNumSpecGroups = function() return 1 end
    DUI.Installer.Install()
    DUI.Profiles.Create("Healer")
    -- On the Healer profile now, but Default's layout is still active.
    DUI.DB.activeName = "Healer"
    stub.popup = nil
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    local _, index = layoutNamed("DaylightUI - Healer")
    T.truthy(index, "made")
    T.eq(C_EditMode.GetLayouts().activeLayout, index, "and active")
    T.eq(stub.popup, "DAYLIGHTUI_RELOAD", "asked to reload")
    T.falsy(DaylightUIInstaller and DaylightUIInstaller:IsShown(), "not the installer")
end)

-- Bar shapes, look and the bag bar / micro menu.

T.test("action bars: every options page is valid", function()
    local DUI = login()
    local n = 0
    for id, page in DUI.Options.Pages() do
        if page.section == "ActionBars" then
            T.eq(#DUI.Options.ValidatePage(page), 0, id)
            n = n + 1
        end
    end
    T.eq(n, 2)
end)

T.test("action bars: default places follow the shapes", function()
    local DUI = login()
    local L = stub.actionbars.Shape
    local before = L.Defaults()
    DUI:Set("ActionBars", "bars.main.size", 100)
    local after = L.Defaults()
    T.truthy(after.right.x > before.right.x, "a wider bar 1 pushes the grids out")
    T.truthy(after.bar2.y > before.bar2.y, "and bar 2 up")
    T.truthy(after.stance.y > before.stance.y, "and the small bars")
end)

T.test("action bars: the look follows its settings, live", function()
    local DUI = login()
    local Skin = stub.actionbars.Skin
    local b = _G.DaylightUIBar1Button2
    DUI:Set("ActionBars", "look.border", 5)
    T.eq(DaylightUI.Style.BorderPx(b), 5, "the border")
    DUI:Set("ActionBars", "look.pressed", { 1, 0, 0 })
    DUI:Set("ActionBars", "look.pressedAlpha", 0.5)
    T.eq(b:GetPushedTexture().__color[1], 1, "pressed color")
    T.eq(b:GetPushedTexture().__color[4], 0.5)
    DUI:Set("ActionBars", "look.keybind", false)
    T.eq(stub.actionbars.Skin.GetParts(b).key:GetAlpha(), 0, "keybinds off")
    DUI:Set("ActionBars", "look.keybindSize", 14)
    T.eq(stub.actionbars.Skin.GetParts(b).key.__font[2], 14)
    DUI:Set("ActionBars", "look.proc", "custom")
    DUI:Set("ActionBars", "look.procColor", { 0, 1, 0 })
    ActionButtonSpellAlertManager:ShowAlert(b)
    T.eq(Skin.GetParts(b).color[2], 1, "a proc in your own color")
    ActionButtonSpellAlertManager:HideAlert(b)
    DUI:Set("ActionBars", "look.checked", "custom")
    DUI:Set("ActionBars", "look.checkedColor", { 0, 0, 1 })
    T.eq(b:GetCheckedTexture().__color[3], 1, "active spell color")
end)

T.test("action bars: each bar can have a look of its own over every bar's", function()
    local DUI = login()
    local Bars, Skin = stub.actionbars.Bars, stub.actionbars.Skin
    local main, b2 = _G.DaylightUIBar1Button2, Bars.buttons.bar2[1]
    DUI:Set("ActionBars", "barLooks.bar2.border", 6)
    T.eq(DaylightUI.Style.BorderPx(b2), 6, "bar 2's own border")
    T.eq(DaylightUI.Style.BorderPx(main), 3, "bar 1 keeps every bar's")
    DUI:Set("ActionBars", "look.border", 4)
    T.eq(DaylightUI.Style.BorderPx(main), 4, "every bar's change reaches bar 1")
    T.eq(DaylightUI.Style.BorderPx(b2), 6, "but not bar 2's own")
    DUI:Set("ActionBars", "barLooks.bar2.keybindColor", { 1, 0, 0 })
    T.eq(Skin.GetParts(b2).key.__textColor[2], 0, "bar 2's keybind color")
    T.eq(Skin.GetParts(main).key.__textColor[2], 0.82, "bar 1's stays")
end)

T.test("action bars: Settings for and Copy look from on the options page", function()
    local DUI = login()
    local Bars = stub.actionbars.Bars
    local groups = stub.actionbars.OPTIONS.pages[1].groups
    local function find(label)
        for _, g in ipairs(groups) do
            for _, it in ipairs(g.items) do if it.label == label then return it end end
        end
    end
    local pick, border, from, copy = find("Settings for"), find("Border"), find("Copy look from"), find("Copy the look")
    T.eq(pick.get(), "all", "every bar at first")
    T.truthy(from.hidden(function() end), "nothing to copy onto every bar")
    border.set(5)
    T.eq(DUI:Get("ActionBars", "look.border"), 5, "All bars writes every bar's look")
    pick.set("bar2")
    T.eq(border.get(), 5, "a bar shows every bar's value until it has its own")
    T.eq(border.default(), 5, "and resets to it")
    border.set(2)
    T.eq(DUI:Get("ActionBars", "barLooks.bar2.border"), 2, "its own")
    T.eq(DaylightUI.Style.BorderPx(Bars.buttons.bar2[1]), 2)
    border.set(5)
    T.isnil(DUI:Get("ActionBars", "barLooks.bar2.border"), "back to every bar's: none of its own")
    border.set(1)
    pick.set("left")
    from.set("bar2")
    copy.func()
    T.eq(DUI:Get("ActionBars", "barLooks.left.border"), 1, "bar 2's look copied")
    T.eq(DaylightUI.Style.BorderPx(Bars.buttons.left[1]), 1)
    from.set("all")
    copy.func()
    T.isnil(DUI:Get("ActionBars", "barLooks.left.border"), "copied from All bars: none of its own")
    T.eq(border.get(), 5)
    pick.set("cdm")
    T.truthy(find("Keybinds").hidden(function() end), "keybind rows aren't the Cooldown Manager's")
    T.falsy(border.hidden(function() end), "its border is")
    pick.set("all")
end)

T.test("action bars: zoom, border color, cooldown shade and edge, text colors", function()
    local DUI = login()
    local Skin = stub.actionbars.Skin
    local b = _G.DaylightUIBar1Button2
    DUI:Set("ActionBars", "look.zoom", 0.2)
    T.near(b.icon.__texCoord[1], 0.18, 1e-6, "zoomed in")
    DUI:Set("ActionBars", "look.borderColor", "custom")
    DUI:Set("ActionBars", "look.borderCustom", { 0, 1, 0 })
    T.eq(Skin.GetParts(b).back.opts.borderColor[2], 1, "the border in your color")
    DUI:Set("ActionBars", "look.borderColor", "shell")
    T.isnil(Skin.GetParts(b).back.opts.borderColor, "back to the shell's own")
    DUI:Set("ActionBars", "look.swipeColor", { 0.2, 0, 0 })
    DUI:Set("ActionBars", "look.edge", "custom")
    DUI:Set("ActionBars", "look.edgeColor", { 0, 0, 1 })
    local L = Skin.GetParts(b).L
    T.eq(L.swipeColor[1], 0.2, "the shade's color")
    T.eq(Skin.EdgeOf(L)[3], 1, "the edge's")
    DUI:Set("ActionBars", "look.edge", "off")
    T.isnil(Skin.EdgeOf(Skin.GetParts(b).L), "no edge")
    DUI:Set("ActionBars", "look.countColor", { 1, 0, 0 })
    DUI:Set("ActionBars", "look.macroColor", { 0, 1, 0 })
    T.eq(b.Count.__textColor[2], 0, "the count's color")
    T.eq(b.Name.__textColor[1], 0, "the macro name's")
end)

T.test("action bars: bars whose backgrounds meet share one panel round them all", function()
    local DUI = login()
    local Bars = stub.actionbars.Bars
    -- Any member joins a group: a-b touch, b-c touch, and a and c are far apart.
    local g = Bars.BackGroups({ { l = 0, r = 10, b = 0, t = 10 }, { l = 10, r = 20, b = 0, t = 10 },
        { l = 20.5, r = 30, b = 0, t = 10 }, { l = 100, r = 110, b = 0, t = 10 } })
    T.eq(#g, 2, "two groups"); T.deq(g[1], { 1, 2, 3 }); T.deq(g[2], { 4 })
    DUI:Set("ActionBars", "look.back", true)
    local main, bar2 = Bars.holders.main, Bars.holders.bar2
    local w, h = main:GetSize()
    -- Bar 2 stacked 2 px over bar 1 (the default spots), so the pads overlap.
    main.__center = { 500, 100 }
    bar2.__center = { 500, 100 + h + 2 }
    Bars.PaintBacks()
    T.truthy(Bars.backs.main:IsShown(), "bar 1's panel holds both")
    T.falsy(Bars.backs.bar2 and Bars.backs.bar2:IsShown(), "no second panel drawn across it")
    local pad = 4
    local _, _, _, l, t = Bars.backs.main:GetPoint(1)
    local _, _, _, r, b = Bars.backs.main:GetPoint(2)
    T.near(l, -pad); T.near(r, pad); T.near(b, -pad)
    T.near(t, h + 2 + pad, nil, "up over bar 2's top")
    -- Moved apart, each is its own.
    bar2.__center = { 500, 400 }
    Bars.PaintBacks()
    T.truthy(Bars.backs.bar2:IsShown(), "bar 2's own panel")
    _, _, _, l, t = Bars.backs.main:GetPoint(1)
    T.near(t, pad, nil, "bar 1's round itself again")
    -- A hidden bar takes no part.
    bar2.__center = { 500, 100 + h + 2 }
    bar2:Hide()
    Bars.PaintBacks()
    _, _, _, l, t = Bars.backs.main:GetPoint(1)
    T.near(t, pad, nil, "bar 2 hidden: bar 1 round itself")
    T.falsy(Bars.backs.bar2:IsShown())
    bar2:Show()
    -- A bar this character can't use (the totem bar on a non-shaman) is an empty
    -- 1x1 holder shown by its state driver. It gets no panel, or it would draw a
    -- dot in the middle of the screen.
    local totem = Bars.holders.totem
    totem:Show()
    totem.__center = { 900, 600 }
    Bars.PaintBacks()
    T.falsy(Bars.backs.totem and Bars.backs.totem:IsShown(), "no panel on a bar not in use")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("action bars: text nudges, a bar background, lit borders on hover and press", function()
    local DUI = login()
    local Skin, Bars = stub.actionbars.Skin, stub.actionbars.Bars
    local b = _G.DaylightUIBar1Button2
    DUI:Set("ActionBars", "look.keybindX", 3)
    local _, _, _, x = Skin.GetParts(b).key:GetPoint(1)
    T.eq(x, -2 + 3, "the keybind nudged")
    DUI:Set("ActionBars", "look.macroY", 4)
    local _, _, _, _, y = b.Name:GetPoint(1)
    T.eq(y, Skin.MACRO_Y + 4, "the macro name nudged")
    T.isnil(Bars.backs.main, "no background until asked")
    DUI:Set("ActionBars", "barLooks.main.back", true)
    T.truthy(Bars.backs.main and Bars.backs.main:IsShown(), "bar 1's background")
    T.isnil(Bars.backs.bar2, "bar 2 has none")
    DUI:Set("ActionBars", "barLooks.main.back", nil)
    T.falsy(Bars.backs.main:IsShown(), "gone again")
    DUI:Set("ActionBars", "look.hoverBorder", true)
    DUI:Set("ActionBars", "look.hoverBorderMode", "custom")
    DUI:Set("ActionBars", "look.hoverBorderColor", { 0, 1, 0 })
    local parts = Skin.GetParts(b)
    b:GetScript("OnEnter")(b)
    settle()
    T.eq(parts.back.opts.borderColor[2], 1, "lit on mouseover")
    b:GetScript("OnLeave")(b)
    settle()
    T.isnil(parts.back.opts.borderColor, "back to the shell's own")
    DUI:Set("ActionBars", "look.pressBorder", true)
    DUI:Set("ActionBars", "look.pressBorderMode", "custom")
    DUI:Set("ActionBars", "look.pressBorderColor", { 0, 0, 1 })
    Skin.SetKeyDown(b, true)
    settle()
    T.eq(parts.back.opts.borderColor[3], 1, "lit while pressed")
    Skin.SetKeyDown(b, false)
    settle()
    T.isnil(parts.back.opts.borderColor)
end)

T.test("action bars: border style, corners and shadow, on bars and the Cooldown Manager", function()
    local DUI = login()
    local Skin = stub.actionbars.Skin
    local b = _G.DaylightUIBar1Button2
    local o = Skin.GetParts(b).back.opts
    DUI:Set("ActionBars", "look.borderStyle", "flat")
    T.eq(o.flat, true, "a flat outline")
    DUI:Set("ActionBars", "look.borderStyle", "none")
    T.eq(o.noBorder, true, "no border")
    local _, _, _, x = b.icon:GetPoint(1)
    T.eq(x, 0, "the icon fills the button")
    DUI:Set("ActionBars", "look.corners", "square")
    DUI:Set("ActionBars", "look.shadow", false)
    T.eq(o.cornerPx, 0, "square corners")
    T.eq(o.shadowAlpha, 0, "no shadow")
    DUI:Set("ActionBars", "look.borderStyle", "daylight")
    T.eq(o.flat, false)
    T.eq(o.noBorder, false)
    DUI:Set("ActionBars", "barLooks.cdm.borderStyle", "none")
    T.eq(Skin.BORDER_PX, 0, "the Cooldown Manager's icons fill theirs")
    local s = { opts = Skin.ShellOpts() }
    T.truthy(Skin.StyleShellOpts(s.opts, Skin.LookFor("cdm")), "its shells take the style")
    T.eq(s.opts.noBorder, true)
end)

T.test("action bars: button shapes mask the icon and draw the border in the shape", function()
    local DUI = login()
    local Skin = stub.actionbars.Skin
    local b = _G.DaylightUIBar1Button2
    local parts = Skin.GetParts(b)
    DUI:Set("ActionBars", "look.shape", "circle")
    T.eq(parts.shape, "circle")
    T.eq(#b.icon.__masks, 1, "the icon is masked")
    T.eq(parts.shapeMask.__texture, DaylightUI.MEDIA .. "shape-circle.png")
    T.truthy(parts.shapeOuter:IsShown(), "the border in the shape")
    T.eq(parts.back.opts.noBorder, true, "the square shell draws nothing")
    DUI:Set("ActionBars", "look.shape", "hexagon")
    T.eq(#b.icon.__masks, 1, "still one mask")
    T.eq(parts.shapeMask.__texture, DaylightUI.MEDIA .. "shape-hexagon.png")
    DUI:Set("ActionBars", "look.hoverBorder", true)
    DUI:Set("ActionBars", "look.hoverBorderMode", "custom")
    DUI:Set("ActionBars", "look.hoverBorderColor", { 0, 1, 0 })
    b:GetScript("OnEnter")(b)
    settle()
    T.eq(parts.shapeOuter.__vertex[2], 1, "a lit border lights the shape")
    b:GetScript("OnLeave")(b)
    settle()
    DUI:Set("ActionBars", "look.shape", "square")
    T.isnil(parts.shape)
    T.eq(#b.icon.__masks, 0, "the mask is off again")
    T.falsy(parts.shapeOuter:IsShown())
    T.eq(parts.back.opts.noBorder, false, "the shell is back")
    DUI:Set("ActionBars", "barLooks.cdm.shape", "diamond")
    local host = CreateFrame("Frame"); host:SetSize(36, 36)
    local st, icon = {}, host:CreateTexture()
    Skin.ShapeCdm(st, host, DaylightUI.Style.Shell(host, Skin.ShellOpts()), icon, {}, {})
    T.eq(st.shape, "diamond", "the Cooldown Manager's icons take its shape")
    T.eq(#icon.__masks, 1)
end)

T.test("action bars: the Cooldown Manager has a look of its own", function()
    local DUI = login()
    local Skin = stub.actionbars.Skin
    DUI:Set("ActionBars", "barLooks.cdm.zoom", 0.2)
    DUI:Set("ActionBars", "barLooks.cdm.border", 5)
    DUI:Set("ActionBars", "barLooks.cdm.countColor", { 1, 0, 0 })
    T.near(Skin.CROP[1], 0.18, 1e-6, "the Cooldown Manager's icons zoom")
    T.eq(Skin.BORDER_PX, 5, "and take its border")
    T.eq(Skin.COUNT_COLOR[2], 0, "and its count color")
    local parts = Skin.GetParts(_G.DaylightUIBar1Button2)
    T.eq(parts.L.zoom, 0, "the bars keep theirs")
    T.eq(DaylightUI.Style.BorderPx(_G.DaylightUIBar1Button2), 3)
end)

T.test("action bars: out of range can tint instead of fade", function()
    local DUI = login()
    local b = _G.DaylightUIBar1Button2
    DUI:Set("ActionBars", "look.range", "color")
    stub.FireEvent("ACTION_RANGE_CHECK_UPDATE", 2, false, true)
    T.eq(b.icon:GetAlpha(), 1, "not faded")
    settle()
    T.eq(b.icon.__vertex[1], 0.9, "tinted")
    stub.FireEvent("ACTION_RANGE_CHECK_UPDATE", 2, true, true)
    settle()
    T.eq(b.icon.__vertex[1], 1, "back to white in range")
    T.eq(b.icon.__vertex[2], 1)
end)

T.test("action bars: the bag bar and micro menu can be shown, faded, and hidden again", function()
    local DUI = login()
    local Fade, Hide = DUI.Fade, stub.actionbars.Hide
    local function settle() Fade.Step(); for _ = 1, 120 do stub.RunOnUpdate(Fade.driver, 1 / 60) end end
    DUI:Set("ActionBars", "bagBar", "shown")
    T.eq(BagsBar:GetParent(), UIParent, "back where it was")
    T.eq(MicroMenuContainer:GetParent(), Hide.parent, "the other still hidden")
    DUI:Set("ActionBars", "microMenu", "shown")
    DUI:Set("ActionBars", "microMenuFade.mode", "always")
    T.eq(MicroMenuContainer:GetParent(), UIParent, "shown")
    stub.now = (stub.now or 0) + 4   -- abworld's clock
    settle()
    T.eq(MicroMenuContainer:GetAlpha(), 0, "faded without the mouse")
    T.eq(BagsBar:GetAlpha(), 1, "the one left at Never doesn't fade")
    MicroMenuContainer.IsMouseOver = function() return true end
    settle()
    T.eq(MicroMenuContainer:GetAlpha(), 1, "back under the mouse")
    DUI:Set("ActionBars", "microMenu", "hidden")
    T.eq(MicroMenuContainer:GetParent(), Hide.parent, "hidden again")
end)

T.test("action bars: the shown bag bar and micro menu move in unlock mode and stay put", function()
    local DUI = login()
    BagsBar:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 10)
    DUI:Set("ActionBars", "bagBar", "shown")
    DUI.Movers.Unlock()
    T.truthy(DUI.Movers.Handle("actionbars.bagBar"), "shown: a handle")
    T.falsy(DUI.Movers.Handle("actionbars.microMenu"), "hidden: none")
    local h = DUI.Movers.Handle("actionbars.bagBar")
    h.__center = { UIParent:GetWidth() / 2 + 100, UIParent:GetHeight() / 2 - 200 }
    DUI.Movers.Save("actionbars.bagBar", true)
    DUI.Movers.Lock()
    local p, rel, rp, x, y = BagsBar:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(rel, UIParent); T.eq(rp, "CENTER")
    T.eq(x, DUI.Pixel.Snap(UIParent, 100)); T.eq(y, DUI.Pixel.Snap(UIParent, -200))
    -- The game lays it out again (Edit Mode's layouts), and it goes back to its spot.
    BagsBar:ClearAllPoints()
    BagsBar:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 10)
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    stub.RunTimers()
    p, _, _, x = BagsBar:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(x, DUI.Pixel.Snap(UIParent, 100))
end)

T.test("action bars: a moved micro menu stays put when the game puts it back after a death", function()
    local DUI = login()
    MicroMenuContainer:SetSize(240, 36)
    DUI:Set("ActionBars", "microMenu", "shown")
    DUI.Movers.Unlock()
    local h = DUI.Movers.Handle("actionbars.microMenu")
    h.__center = { UIParent:GetWidth() / 2 + 100, UIParent:GetHeight() / 2 + 300 }
    DUI.Movers.Save("actionbars.microMenu", true)
    DUI.Movers.Lock()
    -- The game's ResetMicroMenuPosition: Edit Mode's spot, then its pass over the
    -- micro buttons (no layouts event).
    MicroMenuContainer:ClearAllPoints()
    MicroMenuContainer:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 10)
    UpdateMicroButtons()
    stub.RunTimers()
    local p, rel, _, x, y = MicroMenuContainer:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(rel, UIParent)
    T.eq(x, DUI.Pixel.Snap(UIParent, 100)); T.eq(y, DUI.Pixel.Snap(UIParent, 300))
end)

T.test("action bars: the micro menu can start in the bottom-right corner, on any screen", function()
    local DUI = login()
    MicroMenuContainer:SetSize(240, 36)
    local function spot()
        local p, rel, rp, x, y = MicroMenuContainer:GetPoint(1)
        T.eq(p, "CENTER"); T.eq(rel, UIParent); T.eq(rp, "CENTER")
        return x, y
    end
    local X, Y = UIParent:GetWidth() / 2 - 12 - 120, 12 + 18 - UIParent:GetHeight() / 2
    DUI:Set("ActionBars", "microMenu", "shown")
    DUI:Set("ActionBars", "microMenuCorner", true)
    local x, y = spot()
    T.eq(x, X); T.eq(y, Y)
    -- The game lays it out again, and it goes back in the corner.
    MicroMenuContainer:ClearAllPoints()
    MicroMenuContainer:SetPoint("BOTTOM", UIParent, "BOTTOM", 116, 6)
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    stub.RunTimers()
    x, y = spot()
    T.eq(x, X); T.eq(y, Y)
    -- With a data bar along the bottom, it sits above it.
    DUI.Movers.SetBottomRoom(30)
    x, y = spot()
    T.eq(y, 30 + DUI.Movers.ROOM_GAP + 18 - UIParent:GetHeight() / 2, "above the data bar")
    DUI.Movers.SetBottomRoom(0)
    -- Moved by hand it stays there, and a reset takes it back to the corner.
    DUI.Movers.Unlock()
    local h = DUI.Movers.Handle("actionbars.microMenu")
    h.__center = { UIParent:GetWidth() / 2 + 100, UIParent:GetHeight() / 2 - 200 }
    DUI.Movers.Save("actionbars.microMenu", true)
    DUI.Movers.Lock()
    x = spot()
    T.eq(x, DUI.Pixel.Snap(UIParent, 100), "moved")
    DUI.Movers.Reset("actionbars.microMenu")
    x, y = spot()
    T.eq(x, X, "reset: the corner"); T.eq(y, Y)
end)

T.test("action bars: a bar set to Hidden gets no unlock handle, live", function()
    local DUI = login()
    local function shown(key)
        local h = DUI.Movers.Handle(key)
        return h ~= nil and h:IsShown()
    end
    DUI:Set("ActionBars", "bars.bar5.visible", "hidden")
    DUI.Movers.Unlock()
    T.truthy(shown("actionbars.main"), "bar 1: a handle")
    T.falsy(shown("actionbars.bar5"), "bar 5, hidden: none")
    DUI:Set("ActionBars", "bars.bar5.visible", "always")
    T.truthy(shown("actionbars.bar5"), "shown again while unlocked: its handle")
    DUI:Set("ActionBars", "bars.bar5.visible", "hidden")
    T.falsy(shown("actionbars.bar5"), "hidden while unlocked: gone")
    DUI.Movers.Lock()
end)

T.test("action bars: a moved bag bar keeps its spot after a reload", function()
    local DUI = login()
    DUI:Set("ActionBars", "bagBar", "shown")
    DUI:Set("ActionBars", "bagBarFade.mode", "always")
    DUI.Movers.Unlock()
    local h = DUI.Movers.Handle("actionbars.bagBar")
    h.__center = { UIParent:GetWidth() / 2 + 300, UIParent:GetHeight() / 2 - 400 }
    DUI.Movers.Save("actionbars.bagBar", true)
    DUI.Movers.Lock()
    local sv = DaylightUIDB
    local p = sv.profileData[DUI.DB.ActiveName()]
    p.unsaved = nil
    stub.FireEvent("PLAYER_LOGOUT")
    T.eq(p.modules.ActionBars.bagBar, "shown", "saved shown")
    T.truthy(p.positions["actionbars.bagBar"], "saved spot")
    stub.Load({ actionbars = true, before = function() world(); DaylightUIDB = sv end })
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.RunTimers()
    local pt, _, _, x, y = BagsBar:GetPoint(1)
    T.eq(pt, "CENTER"); T.eq(x, DaylightUI.Pixel.Snap(UIParent, 300)); T.eq(y, DaylightUI.Pixel.Snap(UIParent, -400))
end)

-- A micro button and a bag button as the game makes them (the art Menus.lua changes).
local function menuButtons()
    local function states(b)
        for _, k in ipairs({ "Normal", "Pushed", "Disabled", "Highlight" }) do
            local tex = b:CreateTexture()
            b["Get" .. k .. "Texture"] = function() return tex end
        end
    end
    local mm = CreateFrame("Frame", "MicroMenu", MicroMenuContainer)
    mm.BorderArt = mm:CreateTexture()
    local q = CreateFrame("Button", "QuestLogMicroButton", mm)
    q:SetSize(32, 40)
    states(q)
    q.Background = q:CreateTexture()
    q.PushedBackground = q:CreateTexture()
    q.layoutIndex = 2
    function q:GetButtonState() return self.__state or "NORMAL" end
    local c = CreateFrame("Button", "CharacterMicroButton", mm)
    c:SetSize(32, 40)
    states(c)
    c.Portrait = c:CreateTexture()
    c.layoutIndex = 1
    function c:GetButtonState() return "NORMAL" end
    -- The game's pass over the buttons, and its pool's dividers on the bag bar.
    _G.UpdateMicroButtons = function() end
    CreateFrame("Frame", nil, BagsBar)
    local bag = CreateFrame("Button", "CharacterBag0Slot", BagsBar)
    bag:SetSize(45, 45)
    states(bag)
    bag.icon = bag:CreateTexture()
    bag.SlotHighlightTexture = bag:CreateTexture()
    -- The game puts its slot art back on every bag update, from the global
    -- SetItemButtonTexture (BaseBagSlotButtonMixin:SetItemButtonTexture) and from
    -- its own events (the key ring's BAG_UPDATE).
    function bag:UpdateTextures() self:GetHighlightTexture():SetAlpha(0.4) end
    _G.SetItemButtonTexture = function(button) if button.UpdateTextures then button:UpdateTextures() end end
    bag:SetScript("OnEvent", function(self) self:UpdateTextures() end)
end

T.test("action bars: the bag bar and micro menu are skinned, unless turned off", function()
    local DUI = stub.Load({ actionbars = true, before = function() world(); menuButtons() end })
    local Menus = stub.actionbars.Menus
    T.eq(DUI:GetModule("ActionBars").db.skinMenus, true, "on by default")
    T.eq(DUI:GetModule("ActionBars").db.bagBar, "hidden", "the bars themselves still hidden by default")
    T.truthy(Menus.IsSkinned(QuestLogMicroButton), "micro button")
    T.eq(QuestLogMicroButton.Background:GetAlpha(), 0, "its plate gone")
    T.eq(#QuestLogMicroButton:GetNormalTexture().__masks, 1, "the game's glyph masked away")
    T.eq(#QuestLogMicroButton:GetHighlightTexture().__masks, 1, "its highlight too: the game sets that one's alpha")
    T.eq(#CharacterMicroButton.Portrait.__masks, 1, "and the portrait")
    T.truthy(Menus.Parts(QuestLogMicroButton).icon, "our icon")
    T.eq(#{ BagsBar:GetChildren() } > 0, true)
    for _, f in ipairs({ BagsBar:GetChildren() }) do
        if not f:GetName() then T.eq(f:GetAlpha(), 0, "the gold dividers gone") end
    end
    local late = CreateFrame("Frame", nil, BagsBar)
    BagsBar:GetScript("OnSizeChanged")(BagsBar)
    stub.RunTimers()
    T.eq(late:GetAlpha(), 0, "and one the game makes later")
    T.eq(MicroMenu.BorderArt:GetAlpha(), 0, "the bar's frame art gone")
    T.truthy(Menus.IsSkinned(CharacterBag0Slot), "bag button")
    local update = CharacterBag0Slot.UpdateTextures
    SetItemButtonTexture(CharacterBag0Slot, "bag")
    T.eq(CharacterBag0Slot:GetHighlightTexture():GetAlpha(), 0, "the game's highlight stays off after an update")
    CharacterBag0Slot:GetHighlightTexture():SetAlpha(1)
    CharacterBag0Slot:GetScript("OnEvent")(CharacterBag0Slot, "BAG_UPDATE")
    T.eq(CharacterBag0Slot:GetHighlightTexture():GetAlpha(), 0, "and after its own event")
    T.eq(CharacterBag0Slot.UpdateTextures, update, "no hook on the button's UpdateTextures")

    stub.Load({ actionbars = true, before = function()
        world(); menuButtons()
        DaylightUIDB = { modules = { ActionBars = { skinMenus = false } } }
    end })
    T.falsy(stub.actionbars.Menus.IsSkinned(QuestLogMicroButton), "off: left alone")
    T.eq(QuestLogMicroButton.Background:GetAlpha(), 1)
end)

T.test("action bars: the micro icons run along the accent, one sweep through the row", function()
    local DUI = stub.Load({ actionbars = true, before = function() world(); menuButtons() end })
    local Menus, Style = stub.actionbars.Menus, DUI.Style
    local function ends(btn)
        local g = Menus.Parts(btn).icon.__gradient
        return g[2], g[3], g[1]
    end
    DUI:Set("General", "accent", "gradient")
    Menus.PaintMicro()
    local a1, a2 = ends(CharacterMicroButton)
    local b1, b2, way = ends(QuestLogMicroButton)
    T.eq(way, "HORIZONTAL")
    local r0 = Style.AccentAt(0)
    T.near(a1.r, r0, 0.001, "starts at the sweep's start")
    T.near(a2.r, b1.r, 0.001, "the second icon picks up where the first stopped")
    T.near(a2.g, b1.g, 0.001)
    T.near(b2.r, (Style.AccentAt(1)), 0.001, "the last ends at the sweep's end")

    -- No gradient accent, just the color.
    DUI:Set("General", "accent", "daylight")
    Menus.PaintMicro()
    local r, g = Style.Accent()
    a1, a2 = ends(CharacterMicroButton)
    b1, b2 = ends(QuestLogMicroButton)
    for _, c in ipairs({ a1, a2, b1, b2 }) do T.near(c.r, r, 0.001); T.near(c.g, g, 0.001) end

    -- Its window open: white with a lit border. Locked: dim.
    QuestLogMicroButton.__state = "PUSHED"
    Menus.PaintMicro()
    stub.RunOnUpdate(DUI.Motion.Driver(), 1)
    b1 = ends(QuestLogMicroButton)
    T.near(b1.r, Style.INK.VALUE[1], 0.001, "open: lifted to white")
    QuestLogMicroButton.__state = nil
    QuestLogMicroButton:Disable()
    Menus.PaintMicro()
    stub.RunOnUpdate(DUI.Motion.Driver(), 1)
    b1 = ends(QuestLogMicroButton)
    T.near(b1.r, Style.INK.OFF[1], 0.001, "locked: dim")

    -- The menu stood up in Edit Mode runs top to bottom.
    MicroMenu.isHorizontal = false
    QuestLogMicroButton:Enable()
    Menus.PaintMicro()
    local _, _, standing = ends(QuestLogMicroButton)
    T.eq(standing, "VERTICAL")
end)

T.test("action bars: any bar can fade", function()
    local DUI = login()
    local Fade = DUI.Fade
    DUI:Set("ActionBars", "bars.main.fade.mode", "always")
    DUI:Set("ActionBars", "bars.right.fade.mode", "never")
    stub.now = (stub.now or 0) + 4   -- abworld's clock
    Fade.Step()
    for _ = 1, 120 do stub.RunOnUpdate(Fade.driver, 1 / 60) end
    T.eq(DaylightUIBar1:GetAlpha(), 0, "bar 1 faded")
    T.eq(DaylightUIBar4:GetAlpha(), 1, "the right grid doesn't now")
end)

T.test("action bars: settings from before carry over", function()
    stub.Load({ actionbars = true, before = function()
        world()
        DaylightUIDB = { modules = { ActionBars = { hideBags = false, fade = { enabled = false } } } }
    end })
    local db = DaylightUI:GetModule("ActionBars").db
    T.eq(db.bagBar, "shown", "the bag bar was shown")
    T.eq(db.microMenu, "hidden")
    T.isnil(db.hideBags)
    T.eq(db.bars.left.fade.mode, "never", "the grids' fade was off")
    T.eq(db.bars.right.fade.mode, "never")
    T.isnil(db.fade)
    T.eq(BagsBar:GetParent(), UIParent)
end)

T.test("action bars: no hooks on the keybind text; the game's tint and text changes don't touch ours", function()
    login()
    local Skin = stub.actionbars.Skin
    local b = _G.DaylightUIBar1Button2
    local hk, key = b.HotKey, Skin.GetParts(b).key
    -- The game's button code calls these from its protected update on every range
    -- check. With a hook on them the call fails ("attempt to call a nil value"),
    -- many times a second with a pet out.
    T.isnil(rawget(hk, "SetText"), "no hook on its SetText")
    T.isnil(rawget(hk, "SetVertexColor"), "no hook on its SetVertexColor")
    stub.bindings.ACTIONBUTTON2 = { "5" }
    hk:SetVertexColor(1, 0.1, 0.1)               -- out of range, so the game reddens it
    stub.FireEvent("UPDATE_BINDINGS")
    stub.RunTimers()
    T.eq(key:GetText(), "5", "ours shows the binding")
    T.isnil(key.__vertex, "and is never tinted")
    local dot = RANGE_INDICATOR or "●"         -- the game's range dot, unbound
    stub.bindings.ACTIONBUTTON2 = nil
    stub.FireEvent("UPDATE_BINDINGS")
    stub.RunTimers()
    T.eq(key:GetText(), "", "unbound: blank (our font has no range dot)")
    T.eq(hk:GetText(), dot, "the game's own text is left alone")
end)

T.test("action bars: keybind and count positions, short keybinds, macro name size", function()
    local DUI = login()
    local Skin = stub.actionbars.Skin
    local b = _G.DaylightUIBar1Button2
    b.Count = b:CreateFontString()
    DUI:Set("ActionBars", "look.keybindPos", "topleft")
    DUI:Set("ActionBars", "look.countPos", "bottomleft")
    T.eq(select(1, Skin.GetParts(b).key:GetPoint(1)), "TOPLEFT")
    T.eq(select(1, b.Count:GetPoint(1)), "BOTTOMLEFT")
    T.eq(Skin.Shorten("s-Mouse Button 4"), "SM4")
    T.eq(Skin.Shorten("c-Num Pad 5"), "CN5")
    T.eq(Skin.Shorten("Middle Mouse"), "M3")
    -- Other languages: the rules come from the game's own key names.
    _G.KEY_NUMPAD5, _G.KEY_NUMPADPLUS = "5 du pavé num.", "+ du pavé num."
    _G.KEY_BUTTON4, _G.KEY_BUTTON10 = "Bouton 4 souris", "Bouton 10 souris"
    _G.SHIFT_KEY_TEXT = "MAJ"
    Skin.localRules = nil
    T.eq(Skin.Shorten("5 du pavé num."), "N5")
    T.eq(Skin.Shorten("+ du pavé num."), "N+")
    T.eq(Skin.Shorten("Bouton 10 souris"), "M10", "longer names first")
    T.eq(Skin.Shorten("MAJ-Bouton 4 souris"), "SM4")
    _G.KEY_NUMPAD5, _G.KEY_NUMPADPLUS, _G.KEY_BUTTON4, _G.KEY_BUTTON10, _G.SHIFT_KEY_TEXT = nil
    Skin.localRules = nil
    stub.bindings.ACTIONBUTTON2 = { "a-Mouse Wheel Up" }
    stub.FireEvent("UPDATE_BINDINGS")
    DUI:Set("ActionBars", "look.shortKeys", true)
    stub.FireEvent("UPDATE_BINDINGS")
    T.eq(Skin.GetParts(b).key:GetText(), "AWU", "shortened on the button")
    T.eq(b.HotKey:GetText(), "a-Mouse Wheel Up", "the game's own text left as the game wrote it")
    b.Name = b:CreateFontString()
    DUI:Set("ActionBars", "look.macroSize", 12)
    T.eq(b.Name.__font[2], 12)
end)

T.test("action bars: cooldown numbers can be hidden; tooltips out of combat only", function()
    local DUI = login()
    local b = _G.DaylightUIBar1Button2
    local cd = CreateFrame("Cooldown", nil, b)
    function cd:SetHideCountdownNumbers(v) self.__hideNumbers = v end
    b.cooldown = cd
    DUI:Set("ActionBars", "look.cooldownNumbers", false)
    T.eq(cd.__hideNumbers, true)
    DUI:Set("ActionBars", "look.tooltips", "nocombat")
    local alpha, hidden = 1, false
    -- A tooltip frame the game's own hover code can use too (SetOwner, GetOwner).
    local keep, tip = _G.GameTooltip, CreateFrame("GameTooltip", nil, UIParent)
    function tip:Hide() hidden = true end
    function tip:SetAlpha(a) alpha = a end
    _G.GameTooltip = tip
    stub.EnterCombat()
    b:GetScript("OnEnter")(b)
    T.eq(alpha, 0, "unseen in combat")
    T.falsy(hidden, "never hidden from our code")
    b:GetScript("OnLeave")(b)
    T.eq(alpha, 1, "back for the next tooltip")
    stub.LeaveCombat()
    _G.GameTooltip = keep
end)

T.test("action bars: old fade settings move over, the side grids' default included", function()
    local DUI = login()
    local p = { general = { oocAlpha = 0.2 }, modules = { ActionBars = {
        fade = { delay = 5, alpha = 0.1 },
        bars = { main = { mouseover = true }, right = { mouseover = false }, bar2 = {} },
        ooc = { bar2 = true, right = true }, oocAlpha = { bar2 = 0.6 },
        bagBar = "mouseover" } } }
    DUI.FadeUpgrade.Run(p)
    local ab = p.modules.ActionBars
    T.eq(ab.bars.main.fade.mode, "always"); T.eq(ab.bars.main.fade.delay, 5); T.eq(ab.bars.main.fade.alpha, 0.1)
    T.eq(ab.bars.left.fade.mode, "always", "left had the old default (mouseover on)")
    T.eq(ab.bars.right.fade.mode, "ooc", "right had mouseover off and out of combat on")
    T.eq(ab.bars.right.fade.alpha, 0.2, "General's opacity")
    T.eq(ab.bars.bar2.fade.mode, "ooc"); T.eq(ab.bars.bar2.fade.alpha, 0.6)
    T.eq(ab.bagBar, "shown"); T.eq(ab.bagBarFade.mode, "always")
    T.isnil(ab.fade); T.isnil(ab.ooc); T.isnil(ab.oocAlpha); T.isnil(ab.bars.main.mouseover)
    local q = { general = {}, modules = { ActionBars = { bars = { left = { mouseover = false } } } } }
    DUI.FadeUpgrade.Run(q)
    T.eq(q.modules.ActionBars.bars.left.fade.mode, "never", "turned off stays off, not the new default")
end)

T.test("action bars: a bar fades through the engine; dragging a spell wakes it", function()
    local DUI = login()
    local ns = stub.actionbars
    local F = DUI.Fade
    DUI:Set("ActionBars", "bars.bar2.fade.mode", "always")
    DUI:Set("ActionBars", "bars.bar2.fade.delay", 0)
    stub.now = (stub.now or 0) + 3   -- abworld's clock
    local function settle() F.Step(); for _ = 1, 120 do stub.RunOnUpdate(F.driver, 1 / 60) end end
    settle()
    local frame
    for _, bar in ipairs(ns.Bars.Frames()) do if bar.key == "bar2" then frame = bar.frame end end
    T.eq(frame:GetAlpha(), 0, "faded")
    local cursor = _G.GetCursorInfo
    _G.GetCursorInfo = function() return "spell" end
    settle()
    T.eq(frame:GetAlpha(), 1, "a spell on the cursor: somewhere to drop it")
    _G.GetCursorInfo = cursor
end)

T.test("action bars: a target change's burst of range events finds each slot's buttons without asking every button", function()
    login()
    local B = stub.actionbars.Buttons
    local all = B.All()
    T.truthy(#all > 20, "plenty of buttons")
    local asked = 0
    local real = {}
    for _, btn in ipairs(all) do
        real[btn] = btn.GetAttribute
        btn.GetAttribute = function(self, name)
            if name == "action" then asked = asked + 1 end
            return real[btn](self, name)
        end
    end
    -- Out of range on 40 slots at once, as a target change sends them.
    for slot = 1, 40 do stub.FireEvent("ACTION_RANGE_CHECK_UPDATE", slot, false, true) end
    -- Before, every button was asked on every event, about 4000 times here. Now
    -- the index is built once, plus one look per button that actually changed.
    T.truthy(asked <= #all + 40, "about one ask per button, got " .. asked .. " for " .. #all .. " buttons")
    local b = _G.DaylightUIBar1Button2
    T.truthy(B.State(b).outOfRange, "the right buttons still marked")
    -- A button moved to another slot (bar 1 paging) is found there.
    asked = 0
    b:SetAttribute("action", 77)
    stub.FireEvent("ACTION_RANGE_CHECK_UPDATE", 77, true, true)
    T.falsy(B.State(b).outOfRange, "found on its new slot")
    for btn, fn in pairs(real) do btn.GetAttribute = fn end
end)

T.test("action bars: we never switch the client's range checks (the game's twins own them)", function()
    -- The game's hidden twins hold every slot the addon shows and register its range
    -- check (RegisterFrame in ActionButton.lua). Extra calls from the addon threw off
    -- the client's count, which survives a /reload, and the game's next enable
    -- crashed the client (BC_ASSERT in EnableActionRangeCheck).
    login()
    local calls = 0
    local real = C_ActionBar.EnableActionRangeCheck
    C_ActionBar.EnableActionRangeCheck = function(...) calls = calls + 1; return real(...) end
    for _ = 1, 5 do
        stub.FireEvent("PLAYER_TARGET_CHANGED")
        stub.RunTimers()
    end
    local b = _G.DaylightUIBar1Button3
    b:SetAttribute("action", 2)
    stub.actionbars.Buttons.Paint(b)
    b:Hide(); stub.actionbars.Buttons.Paint(b); b:Show()
    C_ActionBar.EnableActionRangeCheck = real
    T.eq(calls, 0, "no call from our code")
end)

-- Redundant work: each test counts what an event or a frame asks of the buttons.
-- Before, every button was asked each time.

T.test("action bars: holding a mouse button (turning the camera) doesn't ask every button each frame", function()
    login()
    local Skin = stub.actionbars.Skin
    local old = _G.IsMouseButtonDown
    _G.IsMouseButtonDown = function() return true end
    local asked = 0
    local real = {}
    for _, btn in ipairs(stub.actionbars.Buttons.All()) do
        real[btn] = btn.GetButtonState
        btn.GetButtonState = function(self) asked = asked + 1; return real[btn](self) end
    end
    for _ = 1, 10 do Skin.Tick(0.01) end
    T.eq(asked, 0, "the mouse over no button: none asked")
    local b = _G.DaylightUIBar1Button2
    hover(b)
    Skin.Tick(0.01)
    T.eq(asked, 1, "only the one under the mouse")
    b:GetScript("OnLeave")(b)
    for btn, fn in pairs(real) do btn.GetButtonState = fn end
    _G.IsMouseButtonDown = old
end)

T.test("action bars: the slow pass looks for procs ending only on buttons showing one", function()
    login()
    local Skin = stub.actionbars.Skin
    -- Every button with an alert that has faded out, as after a past proc.
    local asked = 0
    for _, btn in ipairs(stub.actionbars.Buttons.All()) do
        local alert = CreateFrame("Frame", nil, btn)
        alert:Hide()
        local real = alert.IsShown
        alert.IsShown = function(self) asked = asked + 1; return real(self) end
        btn.SpellActivationAlert = alert
    end
    Skin.Tick(1)
    T.eq(asked, 0, "no proc up: no alert asked")
    local b = _G.DaylightUIBar1Button2
    ActionButtonSpellAlertManager:ShowAlert(b)
    T.eq(Skin.GetParts(b).color, Skin.STATE.proc)
    -- The alert fades out after its event, and the slow pass sees it end.
    b.SpellActivationAlert:Hide()
    Skin.Tick(1)
    T.eq(Skin.GetParts(b).color, Skin.NORMAL, "seen ending")
end)

T.test("action bars: a usable event reads each of our buttons once, and the skin leaves them to the painter", function()
    login()
    local B = stub.actionbars.Buttons
    local calls = 0
    local real = _G.IsUsableAction
    _G.IsUsableAction = function(...) calls = calls + 1; return real(...) end
    stub.FireEvent("SPELL_UPDATE_USABLE")
    stub.FireEvent("ACTIONBAR_UPDATE_USABLE")
    stub.RunTimers()
    _G.IsUsableAction = real
    -- Before, the painter and the skin's state each asked, and the skin's refresh
    -- asked every button again (about 3 per button).
    T.truthy(calls <= #B.All() + 40, "about one per button, got " .. calls .. " for " .. #B.All())
    stub.noMana[2] = true
    stub.FireEvent("ACTIONBAR_UPDATE_USABLE"); stub.RunTimers(); settle()
    T.eq(_G.DaylightUIBar1Button2.icon:GetAlpha(), stub.actionbars.Skin.OUT_OF_RANGE, "still followed")
end)

-- ACTION_USABLE_CHANGED carries each slot's new answer, and the game's buttons
-- paint from it (ActionBarButtonUsableWatcherFrameMixin in ActionButton.lua).
-- Shield Slam stayed dimmed as short of rage after IsUsableAction already said
-- usable: asked inside the event, the client still answered the old state. That
-- reason is a guess; reading the payload is the fix.
T.test("action bars: a usable change paints from the event's own answer, not a fresh ask", function()
    login()
    local b = _G.DaylightUIBar1Button3
    local Skin = stub.actionbars.Skin
    stub.noMana[3] = true
    stub.FireEvent("ACTIONBAR_UPDATE_USABLE"); stub.RunTimers(); settle()
    T.eq(b.icon:GetAlpha(), Skin.OUT_OF_RANGE, "short of power: faded")
    -- The client still answers the old state while it sends the change.
    stub.FireEvent("ACTION_USABLE_CHANGED", { { slot = 3, usable = true, noMana = false } })
    stub.noMana[3] = nil
    stub.RunTimers(); settle()
    T.eq(b.icon:GetAlpha(), 1, "usable again: back at once")
end)

-- The template's OnLoad runs the game's Update on every button before the addon
-- replaces it, while each one still guesses slot 1 (UpdateAction -> UpdateUsable
-- in ActionButton.lua). So a slot 1 that couldn't be used grayed all of them, and
-- the addon's tint only undoes its own colors. Players' whole bars stayed gray,
-- and a /reload could clear it or bring it back.
T.test("action bars: a slot 1 that can't be used during the build grays no other button", function()
    stub.Load({ actionbars = true, before = function()
        world()
        local hasBefore, texBefore = _G.HasAction, _G.GetActionTexture
        _G.HasAction = function(slot) return slot == 1 or hasBefore(slot) end
        C_ActionBar.HasAction = _G.HasAction
        _G.GetActionTexture = function(slot) if slot == 1 then return "tex1" end return texBefore(slot) end
        C_ActionBar.GetActionTexture = _G.GetActionTexture
        _G.IsUsableAction = function(slot) return slot ~= 1, false end
        C_ActionBar.IsUsableAction = _G.IsUsableAction
    end })
    stub.RunTimers(); settle()
    local Skin = stub.actionbars.Skin
    for _, i in ipairs({ 2, 3 }) do
        local b = _G["DaylightUIBar1Button" .. i]
        T.eq(Skin.GetParts(b).unusable, false, "usable, as far as we know")
        T.eq((b.icon:GetVertexColor()), 1, "so its icon is at full color: button " .. i)
    end
    T.eq((_G.DaylightUIBar1Button1.icon:GetVertexColor()), Skin.UNUSABLE[1], "slot 1's own button stays gray")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Getting on or off a mount changes what can be cast with nothing but
-- PLAYER_MOUNT_DISPLAY_CHANGED. The game's buttons ask again on it
-- (ActionBarActionButtonMixin OnEvent in ActionButton.lua).
T.test("action bars: buttons follow a mount going away, with no other usable event", function()
    login()
    local b = _G.DaylightUIBar1Button3
    local Skin = stub.actionbars.Skin
    local can = false
    _G.IsUsableAction = function() return can, false end
    stub.FireEvent("PLAYER_MOUNT_DISPLAY_CHANGED"); stub.RunTimers(); settle()
    T.eq(Skin.GetParts(b).unusable, true, "mounted: gray")
    can = true
    stub.FireEvent("PLAYER_MOUNT_DISPLAY_CHANGED"); stub.RunTimers(); settle()
    T.eq(Skin.GetParts(b).unusable, false, "off the mount: usable again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Bar 1's paging (a vehicle, an override bar, a form) moves a button to another
-- slot without any slot event. Its empty backing, keybind and highlight follow
-- what's on the new slot.
T.test("action bars: a button paged onto an empty slot looks empty, back onto a full one full", function()
    login()
    local Skin = stub.actionbars.Skin
    local b = _G.DaylightUIBar1Button2          -- abworld has slots 2 and 3 full
    stub.RunTimers()
    local parts = Skin.GetParts(b)
    T.eq(parts.back:GetAlpha(), 1, "full at the start")
    b:SetAttribute("action", 50); stub.RunTimers(); settle()
    T.eq(parts.back:GetAlpha(), 0, "paged onto an empty slot: no backing")
    T.eq(parts.key:GetAlpha(), 0, "nor keybind")
    b:SetAttribute("action", 3); stub.RunTimers(); settle()
    T.eq(parts.back:GetAlpha(), 1, "paged onto a full one: back")
    T.eq(parts.key:GetAlpha(), 1)
end)

T.test("action bars: a usable burst paints only shown buttons; a hidden one catches up when it shows", function()
    login()
    local B = stub.actionbars.Buttons
    local holder = _G.DaylightUIBar5
    local calls = 0
    local real = _G.IsUsableAction
    _G.IsUsableAction = function(...) calls = calls + 1; return real(...) end
    stub.FireEvent("ACTIONBAR_UPDATE_USABLE"); stub.RunTimers()
    local all = calls
    holder:Hide()
    calls = 0
    stub.FireEvent("ACTIONBAR_UPDATE_USABLE"); stub.RunTimers()
    T.truthy(calls <= all - #B.All() / 8, "the hidden bar's buttons skipped: " .. calls .. " vs " .. all)
    local before = calls
    holder:Show(); stub.RunTimers()
    T.truthy(calls > before, "the hidden bar's buttons paint as they show")
    _G.IsUsableAction = real
end)

T.test("action bars: target changes write nothing to an icon whose tint didn't change", function()
    login()
    local b = _G.DaylightUIBar1Button2
    settle()
    local writes = 0
    local real = b.icon.SetAlpha
    b.icon.SetAlpha = function(self, ...) writes = writes + 1; return real(self, ...) end
    for _ = 1, 5 do
        stub.FireEvent("PLAYER_TARGET_CHANGED")
        stub.RunTimers()
        stub.FireEvent("ACTION_RANGE_CHECK_UPDATE", 2, true, true)
    end
    settle()
    b.icon.SetAlpha = real
    T.eq(writes, 0, "the same tint: not written again")
    stub.FireEvent("ACTION_RANGE_CHECK_UPDATE", 2, false, true)
    settle()
    T.eq(b.icon:GetAlpha(), stub.actionbars.Skin.OUT_OF_RANGE, "a change still shows")
end)

T.test("action bars: cursor changes redo the empty slots only when dragging starts or stops", function()
    login()
    local Skin = stub.actionbars.Skin
    local calls = 0
    local real = Skin.UpdateEmpty
    Skin.UpdateEmpty = function(...) calls = calls + 1; return real(...) end
    for _ = 1, 5 do stub.FireEvent("CURSOR_CHANGED") end
    T.eq(calls, 0, "nothing on the cursor, still nothing: no pass")
    stub.cursor = "spell"
    stub.FireEvent("CURSOR_CHANGED")
    T.truthy(calls > 0, "a drag starts: the empty slots show")
    stub.cursor = nil
    stub.FireEvent("CURSOR_CHANGED")
    Skin.UpdateEmpty = real
end)

-- Bar 1 paging (a stance or form) swaps a button's slot with no slot event. The
-- icon painter asks UpdateEmpty, and the empty backing eases (FAST).
T.test("action bars: a slot emptied by paging fades its backing, not a one-frame pop", function()
    local DUI = login()
    DUI:Set("ActionBars", "hideEmpty", true)
    stub.RunTimers()
    settle()
    local Skin = stub.actionbars.Skin
    local b = _G.DaylightUIBar1Button2
    local parts = Skin.GetParts(b)
    T.eq(parts.back:GetAlpha(), 1, "a full slot")
    local had = _G.HasAction
    _G.HasAction = function(slot) return slot == 3 end      -- the new page has slot 2 empty
    Skin.UpdateEmpty(b)
    local mid = parts.back:GetAlpha()
    T.truthy(mid > 0, "not gone in one frame")
    Skin.UpdateEmpty(b)                                     -- asked again on the way, it carries on
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 0.05)
    T.truthy(parts.back:GetAlpha() < mid and parts.back:GetAlpha() > 0, "fading")
    settle()
    T.eq(parts.back:GetAlpha(), 0, "an empty slot hidden")
    _G.HasAction = had
    Skin.UpdateEmpty(b)
    settle()
    T.eq(parts.back:GetAlpha(), 1, "back")
    DUI.DB.General().motion = false
    _G.HasAction = function(slot) return slot == 3 end
    Skin.UpdateEmpty(b)
    T.eq(parts.back:GetAlpha(), 0, "motion off: at once")
    DUI.DB.General().motion = true
    _G.HasAction = had
end)

T.test("action bars: the blink and the key poll run only while something blinks or a key is down", function()
    login()
    local B, Keys = stub.actionbars.Buttons, stub.actionbars.Keys
    T.isnil(B.frame:GetScript("OnUpdate"), "nothing blinks: no per-frame work")
    T.isnil(Keys.frame:GetScript("OnUpdate"), "no key down: no poll")
    local b = _G.DaylightUIBar1Button2
    B.SetFlashing(b, true)
    T.truthy(B.frame:GetScript("OnUpdate"), "auto attack on: blinking")
    stub.RunOnUpdate(B.frame, B.FLASH_EVERY + 0.01)
    T.truthy(b.Flash:IsShown(), "it blinks")
    B.SetFlashing(b, false)
    T.falsy(b.Flash:IsShown())
    T.isnil(B.frame:GetScript("OnUpdate"), "and stops")
    local hides = 0
    local real = b.Flash.Hide
    b.Flash.Hide = function(self) hides = hides + 1; return real(self) end
    B.SetFlashing(b, false)
    b.Flash.Hide = real
    T.eq(hides, 0, "not blinking: nothing hidden again")
    Keys.SetDown(b, true)
    T.truthy(Keys.frame:GetScript("OnUpdate"), "a key down: polled")
    Keys.SetDown(b, false)
    T.isnil(Keys.frame:GetScript("OnUpdate"), "let go: no poll")
end)

T.test("action bars: a bar swap's burst of slot changes rebuilds the flyout keys once", function()
    login()
    stub.RunTimers()
    local calls = 0
    local real = _G.ClearOverrideBindings
    _G.ClearOverrideBindings = function(...) calls = calls + 1; return real(...) end
    for slot = 1, 120 do stub.FireEvent("ACTIONBAR_SLOT_CHANGED", slot) end
    stub.RunTimers()
    _G.ClearOverrideBindings = real
    T.eq(calls, 1, "once, the frame after")
end)

T.test("action bars: a painter that fails is reported and the rest still paint", function()
    login()
    local B = stub.actionbars.Buttons
    local P = B.PAINTERS
    local real = P[1].fn
    P[1].fn = function() error("boom") end
    local b = _G.DaylightUIBar1Button2
    B.State(b).outOfRange = nil
    local errs = #stub.errors
    B.Paint(b)
    P[1].fn = real
    T.truthy(#stub.errors > errs, "the error is reported")
    T.eq(B.State(b).outOfRange, false, "the range painter (last) still ran")
end)

T.test("action bars: a burst of totem events re-places the totem bar once, not a timer per event", function()
    loginShaman()
    stub.RunTimers()
    local n = 0
    local real = C_Timer.After
    C_Timer.After = function(d, fn) n = n + 1; return real(d, fn) end
    for _ = 1, 5 do stub.FireEvent("PLAYER_TOTEM_UPDATE", 1) end
    C_Timer.After = real
    T.eq(n, 1, "once, the frame after")
    stub.RunTimers()
end)

T.test("action bars: a reused Cooldown Manager icon hides the game's art again without searching its frames", function()
    local _, items
    stub.Load({ actionbars = true, before = function()
        world()
        _, items = viewer("EssentialCooldownViewer", 2)
    end })
    stub.RunTimers()
    local item = items[1]
    local walks = 0
    local real = item.GetRegions
    item.GetRegions = function(self) walks = walks + 1; return real(self) end
    for _ = 1, 5 do
        item.overlay:SetAlpha(1)                -- the game shows its art again on reuse
        item:Hide(); item:Show()
        T.eq(item.overlay:GetAlpha(), 0, "hidden again")
    end
    T.eq(walks, 0, "the art found once, kept")
    local extra = item:CreateTexture()          -- a region the game adds later
    item:Hide(); item:Show()
    T.eq(extra:GetAlpha(), 0, "a new region is found too")
    item.GetRegions = real
end)

-- The game applies its layout again when the player's specialization changes
-- (PLAYER_SPECIALIZATION_CHANGED in EditModeManager.lua) without firing
-- EDIT_MODE_LAYOUTS_UPDATED, so a level-up put the menus back mid-screen.
T.test("action bars: a moved bag bar goes back to its spot after the game re-lays out on a spec change", function()
    local DUI = login()
    DUI:Set("ActionBars", "bagBar", "shown")
    DUI.Movers.Unlock()
    local h = DUI.Movers.Handle("actionbars.bagBar")
    h.__center = { UIParent:GetWidth() / 2 + 100, UIParent:GetHeight() / 2 - 200 }
    DUI.Movers.Save("actionbars.bagBar", true)
    DUI.Movers.Lock()
    BagsBar:ClearAllPoints()
    BagsBar:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 10)
    stub.FireEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
    stub.RunTimers()
    local p, _, _, x = BagsBar:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(x, DUI.Pixel.Snap(UIParent, 100))
end)

-- The bag bar's and micro menu's sizes are Edit Mode settings, stored as a step
-- (Bags 75-200% in 5s, micro menu 70-200% in 5s).
local function sizeWorld()
    Enum.EditModeSystem.Bags, Enum.EditModeSystem.MicroMenu = 14, 13
    Enum.EditModeBagsSetting = { Size = 2 }
    Enum.EditModeMicroMenuSetting = { Size = 2 }
    CreateFrame("Frame", "MicroMenu", MicroMenuContainer)
    saved.layouts = { { layoutType = 1, layoutName = "DaylightUI - DPS/Tank", systems = {
        { system = 14, settings = { { setting = 2, value = 15 } }, anchorInfo = {} },
        { system = 13, settings = { { setting = 2, value = 6 } }, anchorInfo = {} } } } }
    saved.activeLayout = 3      -- the two presets come first
end
local function optionItem(label)
    for _, g in ipairs(stub.actionbars.OPTIONS.pages[1].groups) do
        for _, it in ipairs(g.items) do if it.label == label then return it end end
    end
    for _, page in ipairs(stub.actionbars.OPTIONS.pages) do
        for _, g in ipairs(page.groups) do
            for _, it in ipairs(g.items) do if it.label == label then return it end end
        end
    end
end

T.test("action bars: bag bar and micro menu size read and write the active Edit Mode layout, live", function()
    local DUI = login()
    sizeWorld()
    DUI:Set("ActionBars", "bagBar", "shown")
    local bag, micro = optionItem("Bag bar size"), optionItem("Micro menu size")
    T.truthy(bag, "a bag bar size slider"); T.truthy(micro, "a micro menu size slider")
    T.near(bag.get(), 1.5, 0.001, "the layout's 150%")
    T.near(micro.get(), 1.0, 0.001, "the layout's 100%")
    stub.popup = nil           -- the login's own prompt
    bag.set(0.8)
    T.near(BagsBar:GetScale(), 0.8, 0.001, "smaller at once")
    stub.RunTimers()
    T.eq(saved.layouts[1].systems[1].settings[1].value, 1, "80% saved as step 1")
    T.eq(saved.activeLayout, 3, "the active layout stays")
    T.isnil(stub.popup, "no reload asked")
    T.near(bag.get(), 0.8, 0.001)
    micro.set(1.2)
    T.near(MicroMenu:GetScale(), 1.2, 0.001)
    stub.RunTimers()
    T.eq(saved.layouts[1].systems[2].settings[1].value, 10, "120% saved as step 10")
end)

T.test("action bars: a size slider reads what it just set, before the half-second save (no jumping, reset works)", function()
    local DUI = login()
    sizeWorld()
    DUI:Set("ActionBars", "microMenu", "shown")
    local micro = optionItem("Micro menu size")
    micro.set(1.45)
    T.near(micro.get(), 1.45, 0.001, "the new size, while the save still waits")
    micro.set(1.5)
    T.near(micro.get(), 1.5, 0.001, "each step of a drag")
    stub.RunTimers()
    T.eq(saved.layouts[1].systems[2].settings[1].value, 16, "150% saved")
    micro.set(1)                -- the reset arrow
    T.near(micro.get(), 1, 0.001, "reset shows 100% at once")
    T.near(MicroMenu:GetScale(), 1, 0.001)
    stub.RunTimers()
    T.eq(saved.layouts[1].systems[2].settings[1].value, 6, "100% saved")
    T.near(micro.get(), 1, 0.001)
end)

T.test("action bars: a drag is one save: the game re-applies a saved layout, which would snap the frame mid-drag", function()
    local DUI = login()
    sizeWorld()
    DUI:Set("ActionBars", "microMenu", "shown")
    local micro = optionItem("Micro menu size")
    stub.RunTimers()
    local saves, real = 0, C_EditMode.SaveLayouts
    C_EditMode.SaveLayouts = function(...) saves = saves + 1; return real(...) end
    micro.set(1.2); micro.set(1.3); micro.set(1.4)
    local timers = {}
    local after = C_Timer.After
    C_Timer.After = function(s, fn) timers[#timers + 1] = fn; return after(s, fn) end
    micro.set(1.45)
    C_Timer.After = after
    T.eq(#timers, 1, "each step starts the wait again")
    stub.RunTimers()
    C_EditMode.SaveLayouts = real
    T.eq(saves, 1, "one save, of the last step")
    T.eq(saved.layouts[1].systems[2].settings[1].value, 15, "145% saved")
end)

T.test("action bars: on one of the game's own layouts the size still changes, nothing is saved", function()
    local DUI = login()
    sizeWorld()
    saved.activeLayout = 1
    DUI:Set("ActionBars", "bagBar", "shown")
    local bag = optionItem("Bag bar size")
    bag.set(1.25)
    stub.RunTimers()
    T.near(BagsBar:GetScale(), 1.25, 0.001)
    T.eq(saved.layouts[1].systems[1].settings[1].value, 15, "the saved layout untouched")
end)

T.test("action bars: a data bar along the bottom lifts the bars clear of it, as it does the chat", function()
    local DUI = login()
    local Bars = stub.actionbars.Bars
    local function y(key) local _, _, _, _, oy = Bars.holders[key]:GetPoint(1); return oy end
    local base, side, two = y("main"), y("left"), y("bar2")
    T.eq(base, stub.actionbars.Shape.BOTTOM)
    DUI.Movers.SetBottomRoom(40)
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local lift = 40 + DUI.Movers.ROOM_GAP - base
    T.eq(y("main"), base + lift, "bar 1 above the data bar")
    T.eq(y("left"), side + lift, "the side grid with it")
    T.eq(y("bar2"), two + lift, "bar 2 still sits on bar 1")
    -- A short data bar under bar 1's own gap moves nothing.
    DUI.Movers.SetBottomRoom(10)
    stub.RunTimers()
    T.eq(y("main"), base)
    DUI.Movers.SetBottomRoom(0)
end)

T.test("ManaRise is told about our buttons, loaded before us or after", function()
    local got
    local DUI = stub.Load({ actionbars = true, before = function()
        world()
        _G.ManaRise_RegisterBarAddon = function(t) got = t end
    end })
    stub.RunTimers()
    T.truthy(got, "registered at build")
    T.eq(got.name, "Daylight UI")
    local list = got.buttons()
    T.truthy(#list > 0 and list[1].GetAttribute, "our action buttons")
    _G.ManaRise_RegisterBarAddon = nil
    got = nil
    stub.Load({ actionbars = true, before = world })
    stub.RunTimers()
    _G.ManaRise_RegisterBarAddon = function(t) got = t end
    stub.FireEvent("ADDON_LOADED", "ManaRise")
    T.truthy(got, "registered when it loads later")
    _G.ManaRise_RegisterBarAddon = nil
end)

T.test("new ranks: a learned rank takes the place of the one before it, in rank order, out of combat; rank 1 kept on purpose and macros stay", function()
    login()
    local RU = stub.actionbars.RankUp
    stub.spells[331] = { name = "Healing Wave", rank = "Rank 1" }
    stub.spells[332] = { name = "Healing Wave", rank = "Rank 2" }
    stub.spells[547] = { name = "Healing Wave", rank = "Rank 3" }
    stub.slots[1] = { texture = "tex332", spellID = 332 }   -- the rank you had
    stub.slots[5] = { texture = "tex331", spellID = 331 }   -- rank 1 kept to save mana
    stub.slots[6] = { texture = "m", macro = 4 }
    stub.slots[1] = { texture = "tex331", spellID = 331 }
    stub.slots[5] = nil
    -- A trainer's Train All, rank 3 heard before rank 2: taken in rank order.
    stub.FireEvent("LEARNED_SPELL_IN_SKILL_LINE", 547, 1, false)
    stub.FireEvent("LEARNED_SPELL_IN_SKILL_LINE", 332, 1, false)
    stub.RunTimers()
    T.eq(stub.slots[1].spellID, 547, "rank 1 to 2 to 3 in one go")
    stub.slots[5] = { texture = "tex331", spellID = 331 }   -- rank 1 put back on purpose
    stub.slots[1] = { texture = "tex332", spellID = 332 }
    stub.FireEvent("LEARNED_SPELL_IN_SKILL_LINE", 547, 1, false)
    stub.RunTimers()
    T.eq(stub.slots[1].spellID, 547, "the bar now has rank 3")
    T.eq(stub.slots[5].spellID, 331, "rank 1 stays")
    T.truthy(stub.slots[6].macro, "a macro stays")
    T.isnil(GetCursorInfo(), "nothing left on the cursor")
    -- In a fight it waits for the fight's end.
    stub.spells[8005] = { name = "Healing Wave", rank = "Rank 4" }
    stub.combat = true
    stub.FireEvent("LEARNED_SPELL_IN_SKILL_LINE", 8005, 1, false)
    stub.RunTimers()
    T.eq(stub.slots[1].spellID, 547, "not in combat")
    stub.combat = false
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    stub.RunTimers()
    T.eq(stub.slots[1].spellID, 8005, "after it")
    -- Switched off: nothing changes.
    DaylightUI:Set("ActionBars", "rankUp", false)
    stub.spells[8008] = { name = "Healing Wave", rank = "Rank 5" }
    stub.FireEvent("LEARNED_SPELL_IN_SKILL_LINE", 8008, 1, false)
    stub.RunTimers()
    T.eq(stub.slots[1].spellID, 8005, "off: left alone")
    T.truthy(RU, "its part is there")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
