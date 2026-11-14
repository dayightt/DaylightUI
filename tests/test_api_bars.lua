local stub = require("stub")
local ABW = require("abworld")

-- DaylightUI.API 1.5: the action bars. Buttons hand plugins their pieces by
-- name and what they show ("actionbutton"), painted after a change of what a
-- button shows or how it reads, never on a cooldown tick; claimed pieces are
-- left to the plugin (Skin.Owned). Bars are frames of kind "actionbar".

local function load()
    stub.Load({ actionbars = true, before = function() ABW.newWorld({}) end })
    stub.RunTimers()
    return DaylightUI.API, stub.actionbars
end

-- Runs the motion kit's glides to their end.
local function settle()
    local d = DaylightUI.Motion.Driver()
    for _ = 1, 60 do
        if not (d and d:GetScript("OnUpdate")) then return end
        stub.RunOnUpdate(d, 1 / 60)
    end
end

local function btn(i) return _G["DaylightUIBar1Button" .. (i or 2)] end

local function painter(API, opts)
    local me = API.For("BarPlugin")
    local calls = {}
    local h = me.Paint("actionbutton", function(frame, parts, info)
        calls[#calls + 1] = { frame = frame, parts = parts, info = info }
    end, opts)
    return calls, h
end

local function on(calls, frame)
    local n = 0
    for _, c in ipairs(calls) do if c.frame == frame then n = n + 1 end end
    return n
end

T.test("api bars: a button's pieces by name, what it shows, and its bar", function()
    local API, ns = load()
    local b = btn(2)
    local parts = API.Parts(b)
    T.truthy(parts, "parts")
    T.eq(parts.icon, b.icon)
    T.eq(parts.count, b.Count)
    T.eq(parts.macro, b.Name)
    T.eq(parts.cooldown, b.cooldown)
    T.eq(parts.hotkey, ns.Skin.GetParts(b).key)
    T.eq(type(parts.border), "table", "the border's textures")
    local info = API.ButtonInfo(b)
    T.eq(info.bar, 1); T.eq(info.barKey, "main"); T.eq(info.index, 2); T.eq(info.slot, 2)
    T.eq(info.type, "spell"); T.eq(info.id, 2); T.eq(info.empty, false)
    T.eq(info.usable, true); T.eq(info.outOfRange, false)
    T.eq(API.ButtonInfo(btn(5)).empty, true, "an empty slot")
    T.isnil(API.ButtonInfo(CreateFrame("Frame")), "nothing for another frame")
    T.eq(API.GetActionBar(1), ns.Bars.holders.main)
    T.eq(API.GetActionBar("main"), ns.Bars.holders.main)
    T.eq(API.GetActionBar("stance"), ns.Bars.holders.stance)
    T.isnil(API.GetActionBar("nope"))
    local n = 0
    for f, key in API.Frames("actionbar") do
        n = n + 1
        T.eq(ns.Bars.holders[key], f, key)
    end
    T.eq(n, #ns.Bars.DEFS, "every bar")
end)

T.test("api bars: a bar's layout says FrameStyled", function()
    local API, ns = load()
    local styled = {}
    API.On("FrameStyled", function(kind, f, key) if kind == "actionbar" then styled[key] = f end end)
    ns.Bars.LayoutBar(ns.Bars.DEFS[1])
    T.eq(styled.main, ns.Bars.holders.main)
end)

T.test("api bars: painted on start with info, then when what it shows changes", function()
    local API = load()
    local calls = painter(API)
    T.truthy(on(calls, btn(2)) >= 1, "painted at once")
    T.eq(calls[1].info and calls[1].info.slot ~= nil, true, "with info on the first call")
    -- A new action in the slot.
    local before = on(calls, btn(3))
    stub.slots[3] = { texture = "tex9", spellID = 9 }
    stub.FireEvent("ACTIONBAR_SLOT_CHANGED", 3)
    stub.RunTimers()
    T.eq(on(calls, btn(3)), before + 1, "once for a new action")
    T.eq(calls[#calls].info.id, 9)
    -- Short of power: its tint changes.
    before = on(calls, btn(2))
    stub.slots[2].noMana = true
    stub.FireEvent("SPELL_UPDATE_USABLE")
    stub.RunTimers()
    settle()       -- the tint glides there, then paints
    T.truthy(on(calls, btn(2)) > before, "painted when it can't be afforded")
    local last
    for _, c in ipairs(calls) do if c.frame == btn(2) then last = c end end
    T.eq(last.info.noPower, true)
    -- A cooldown event that changes nothing paints nothing.
    before = #calls
    stub.FireEvent("SPELL_UPDATE_COOLDOWN")
    stub.RunTimers()
    T.eq(#calls, before, "no paint on a cooldown tick")
end)

T.test("api bars: a claimed icon is never tinted, and gets its look back", function()
    local API, ns = load()
    local b = btn(2)
    local _, h = painter(API, { owns = { "icon" } })
    b.icon:SetVertexColor(0.1, 0.2, 0.3)
    b.icon:SetAlpha(0.9)
    stub.slots[2].noMana = true
    stub.FireEvent("SPELL_UPDATE_USABLE")
    stub.RunTimers()
    local r, g = b.icon:GetVertexColor()
    T.eq(r, 0.1); T.eq(g, 0.2)
    T.eq(b.icon:GetAlpha(), 0.9, "no fade either")
    API.Off(h)
    stub.RunTimers()
    settle()
    T.truthy(b.icon:GetAlpha() < 0.9, "faded again for no power")
    r = b.icon:GetVertexColor()
    T.eq(r, 1, "white again")
    T.falsy(ns.Skin.Owned(b, "icon"))
end)

T.test("api bars: a claimed border and texts keep the plugin's colors", function()
    local API, ns = load()
    local b = btn(2)
    -- Paints its own colors each time, as a real plugin does.
    API.For("BarPlugin").Paint("actionbutton", function(_, parts)
        for _, t in pairs(parts.border) do t:SetVertexColor(0.5, 0, 0.5) end
        parts.hotkey:SetTextColor(0, 1, 0)
        parts.count:SetTextColor(0, 0, 1)
    end, { owns = { "border", "hotkey", "count", "macro" } })
    local parts = ns.Skin.GetParts(b)
    local _, tex = next(parts.back.border)
    -- A proc, a hover and a full restyle: nothing of Daylight UI's lands after the plugin.
    stub.slots[2].overlayed = true
    ns.Skin.UpdateState(b)
    parts.L.hoverBorder = true
    b:GetScript("OnEnter")(b)
    settle()
    local r, g, bb = tex:GetVertexColor()
    T.eq(r, 0.5); T.eq(g, 0); T.eq(bb, 0.5)
    ns.Bars.Refresh(DaylightUI:GetModule("ActionBars"))
    stub.RunTimers()
    settle()
    r, g, bb = tex:GetVertexColor()
    T.eq(r, 0.5); T.eq(g, 0); T.eq(bb, 0.5)
    local kr, kg = parts.key:GetTextColor()
    T.eq(kr, 0); T.eq(kg, 1)
    local _, _, cb = b.Count:GetTextColor()
    T.eq(cb, 1)
end)

T.test("api bars: the border's state is in the info", function()
    local API, ns = load()
    local calls = painter(API, { owns = { "border" } })
    local b = btn(2)
    ns.Skin.GetParts(b).L.hoverBorder = true
    b:GetScript("OnEnter")(b)
    local last
    for _, c in ipairs(calls) do if c.frame == b then last = c end end
    T.eq(last.info.border, "hover")
    b:GetScript("OnLeave")(b)
    for _, c in ipairs(calls) do if c.frame == b then last = c end end
    T.isnil(last.info.border)
end)

T.test("api bars: key binding mode and a glow", function()
    local API = load()
    _G.QuickKeybindFrame = CreateFrame("Frame", "QuickKeybindFrame")
    QuickKeybindFrame:Hide()
    T.eq(API.BindKeys(), true)
    T.truthy(QuickKeybindFrame:IsShown())
    QuickKeybindFrame:Hide()
    stub.EnterCombat()
    T.eq(API.BindKeys(), false, "not in a fight")
    stub.LeaveCombat()
    local b = btn(2)
    T.eq(API.Glow(b, true, 1, 0, 0), true)
    local Fx = DaylightUI:GetModule("ActionBars").ns.CdmEffects
    local g = Fx.GlowFrame(API.Attach(b))
    T.truthy(g and g:IsShown(), "the glow shows on the button's holder")
    T.eq(API.Glow(CreateFrame("Frame"), true), false, "only Daylight UI's frames")
    T.eq(API.Glow(b, false), true)
end)
