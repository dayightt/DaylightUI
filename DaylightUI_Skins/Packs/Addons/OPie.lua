-- Gives OPie's ring buttons the player's action bar look, read live from
-- DUI.ActionButtonLook: border size, style, color, corners, shadow and shape,
-- icon zoom, out of range / no power (fade or color), cooldown sweep color, edge
-- and numbers, keybind and count text, the hover wash and lit border on the
-- slice you'd pick, the checked tint on an active one (a form, your current
-- mount), and the proc border. Changes there show on the ring immediately
-- (ActionButtonLookChanged). With the action bars module off, their default look
-- is used (Fallback below). The ring itself (spin, zoom, center pointer,
-- options) stays OPie's.
-- How (OPie 8.10.2, UI/RingView.lua): OPie accepts button looks from other
-- addons through OPie.UI:RegisterIndicatorConstructor(key, { name, apiLevel,
-- CreateIndicator, ... }), the same way other UI suites plug in. The last one
-- registered is used unless the player picks another under Appearance in its
-- options. apiLevel 5 means implementing every method RingView calls
-- (RequiredIndicatorMethods there), and SetActive / SetHighlighted /
-- SetOuterGlow receive secret booleans (OPie checks this with a secret false
-- at registration). SetCooldownDuration gets the client's duration object in
-- combat. Nothing here hooks OPie.

local _, ns = ...
local DUI = DaylightUI
local Engine = ns.Engine
local Style, Pixel, Motion = DUI.Style, DUI.Pixel, DUI.Motion

local ADDON = "OPie"

Engine.AddonSwitch({ key = "opie", addon = ADDON, label = "OPie",
    desc = "Its ring buttons in your action bar look. The ring, its spin and its options stay OPie's." })

local OPieSkin = {
    KEY = "daylight",
    GCD = 1.5, -- longer than this is a real cooldown (gets the look's gray and opacity)
}
ns.OPieSkin = OPieSkin
OPieSkin.made = setmetatable({}, { __mode = "k" }) -- every button created, repainted on a look change

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- The action bars' default look (their Defaults.lua) and the plain pieces it
-- needs, for when that module is off.
local Fallback = {
    NORMAL = {}, LIT = {},
    KEYBIND_POS = { topright = { "TOPRIGHT", -2, -3 } },
    COUNT_POS = { bottomright = { "BOTTOMRIGHT", -2, 3 } },
    SHADE_FILE = DUI.MEDIA .. "inner-shadow.png", SHADE = 0.55,
    OUT_OF_RANGE = 0.4,
}
Fallback.LOOK = { border = 3, keybind = true, keybindSize = 12, countSize = 11, macroSize = 9,
    highlight = { 1, 1, 1 }, highlightAlpha = 0.12, checked = "accent", checkedAlpha = 0.3, proc = "accent",
    range = "fade", cooldownAlpha = 0.7, swipeColor = { 0, 0, 0 }, cooldownNumbers = true, cooldownSize = 14,
    keybindPos = "topright", countPos = "bottomright", borderColor = "shell", hoverBorder = false,
    keybindX = 0, keybindY = 0, countX = 0, countY = 0, macroX = 0, macroY = 0, cdGray = false, cdAlpha = 1 }
function Fallback.Look() return Fallback.LOOK end
function Fallback.BorderPx(L) return L.border end
function Fallback.StyleShellOpts() return false end
function Fallback.BorderOf() return nil end
function Fallback.ModeColor() return { Style.Accent() } end
function Fallback.CropOf() return Style.ICON_CROP end
function Fallback.Shape() return false end
function Fallback.Shorten(text) return text end
function Fallback.Text(fs, size) Style.DressText(fs, size) end
function Fallback.StyleCooldown(cd, L)
    cd:SetSwipeTexture(WHITE)
    local c = L.swipeColor
    cd:SetSwipeColor(c[1], c[2], c[3], L.cooldownAlpha)
    cd:SetDrawBling(false)
    cd:SetDrawEdge(false)
    cd:SetHideCountdownNumbers(L.cooldownNumbers == false)
    local fs = cd.GetCountdownFontString and cd:GetCountdownFontString()
    if type(fs) == "table" then Style.DressText(fs, L.cooldownSize) end
end
function Fallback.Tint(st)
    local off = st.outOfRange or st.noPower
    return off and Fallback.OUT_OF_RANGE or 1, nil
end
function Fallback.PaintBorder(st, color)
    if color == Fallback.NORMAL then
        Style.SetShellColors(st.back, nil, nil)
    elseif color == Fallback.LIT then
        Style.LightShell(st.back)
    else
        Style.SetShellColors(st.back, color, { color[1] * 0.45, color[2] * 0.45, color[3] * 0.45 })
    end
end
OPieSkin.Fallback = Fallback

-- The action bars' look kit, or the fallback when they're off.
local function kit()
    local A = DUI.ActionButtonLook
    return type(A) == "table" and A or Fallback
end

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end
-- OPie may pass a secret flag in combat, so let the client pick the alpha.
local function alphaFrom(region, flag, on)
    if secret(flag) then
        region:SetAlphaFromBoolean(flag, on, 0)
    else
        region:SetAlpha(flag and on or 0)
    end
end
local function lerp(x, y, p) return x + (y - x) * p end

-- Icon color and opacity: the look's out of range / no power / on cooldown rules
-- (Tint) multiplied by OPie's own tint. Eases at FAST like the action bars, and
-- snaps on a fresh look or with motion off.
local function setTint(d, a, r, g, b)
    d.icon:SetVertexColor(d.ir * r, d.ig * g, d.ib * b)
    d.icon:SetAlpha(a)
    d.shade:SetAlpha(a)
    d.tA, d.tR, d.tG, d.tB = a, r, g, b
end
local function paintTint(d, snap)
    local a, col = d.A.Tint(d)
    local r, g, b = 1, 1, 1
    if col then r, g, b = col[1], col[2], col[3] end
    if d.gA == a and d.gR == r and d.gG == g and d.gB == b and not snap then return end
    d.gA, d.gR, d.gG, d.gB = a, r, g, b
    if snap or d.tA == nil or not Motion.On() then
        Motion.Tween(d.tintKey, 0, 0, 0)
        setTint(d, a, r, g, b)
        return
    end
    local a0, r0, g0, b0 = d.tA, d.tR, d.tG, d.tB
    Motion.Tween(d.tintKey, 0, 1, Motion.FAST, function(p)
        setTint(d, lerp(a0, a, p), lerp(r0, r, p), lerp(g0, g, p), lerp(b0, b, p))
    end, function() setTint(d, a, r, g, b) end)
end

-- Border priority: a proc, then the slice you'd pick (the look's lit border on
-- hover, if enabled), else the resting color.
local function paintBorder(d)
    local A, L = d.A, d.L
    local color
    if d.procOn then
        color = L.proc == "custom" and L.procColor or { Style.Accent() }
    elseif d.picked and L.hoverBorder then
        color = A.ModeColor(L.hoverBorderMode, L.hoverBorderColor)
    end
    color = color or (L.borderColor == "accent" and A.LIT) or d.rest or A.NORMAL
    A.PaintBorder(d, color)
end

-- The look's "gray on cooldown", for real cooldowns.
local function paintGray(d)
    local goal = (d.cooling and d.L.cdGray) and 1 or 0
    if d.gray == goal then return end
    local from = d.gray or 0
    d.gray = goal
    Motion.Tween(d.grayKey, from, goal, Motion.FAST, function(v) d.icon:SetDesaturation(v) end)
end

local function placeText(fs, f, pos, x, y)
    fs:ClearAllPoints()
    fs:SetPoint(pos[1], f, pos[1], pos[2] + (x or 0), pos[3] + (y or 0))
    fs:SetJustifyH(pos[1] == "TOPLEFT" and "LEFT" or pos[1] == "BOTTOM" and "CENTER" or "RIGHT")
end

-- Reapplies the whole look: on creation, on an action bar look change, on a style change.
function OPieSkin.Restyle(f)
    local d = f.dui
    local A = kit()
    local L = A.Look()
    d.A, d.L = A, L
    A.StyleShellOpts(d.opts, L)
    Style.Shell(f)
    local T = Pixel.Px(f, A.BorderPx(L))
    d.icon:ClearAllPoints()
    d.icon:SetPoint("TOPLEFT", f, "TOPLEFT", T, -T)
    d.icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -T, T)
    local c = A.CropOf(L)
    d.crop = c
    if not d.atlas then d.icon:SetTexCoord(c[1], c[2], c[3], c[4]) end
    A.StyleCooldown(d.cd, L)
    d.numbers = L.cooldownNumbers ~= false
    d.recharge = nil -- the next cooldown sets the sweep kind again

    -- Hover wash on the slice you'd pick (the checked tint on an active one is
    -- in OPieSkin.Accent).
    local h = L.highlight
    d.wash:SetColorTexture(h[1], h[2], h[3], 1)

    A.Text(d.key, L.keybindSize)
    local kc = L.keybindColor or Style.INK.LABEL
    d.key:SetTextColor(kc[1], kc[2], kc[3])
    placeText(d.key, d.icon, A.KEYBIND_POS[L.keybindPos] or A.KEYBIND_POS.topright, L.keybindX, L.keybindY)
    d.key:SetAlpha(L.keybind == false and 0 or 1)
    A.Text(d.count, L.countSize)
    local cc = L.countColor or Style.INK.VALUE
    d.count:SetTextColor(cc[1], cc[2], cc[3])
    placeText(d.count, d.icon, A.COUNT_POS[L.countPos] or A.COUNT_POS.bottomright, L.countX, L.countY)
    -- OPie's short label uses the macro name's style.
    A.Text(d.label, L.macroSize)
    local mc = L.macroColor or Style.INK.TEXT
    d.label:SetTextColor(mc[1], mc[2], mc[3])
    d.label:ClearAllPoints()
    d.label:SetPoint("BOTTOMLEFT", d.icon, "BOTTOMLEFT", 1 + (L.macroX or 0), 2 + (L.macroY or 0))
    d.label:SetPoint("BOTTOMRIGHT", d.icon, "BOTTOMRIGHT", -1 + (L.macroX or 0), 2 + (L.macroY or 0))

    A.Shape(d, f, d.back, d.icon, { d.shade, d.wash, d.check }, { d.cd }, L)
    d.rest = A.BorderOf(L)
    d.shownKey = nil
    if d.binding ~= nil then f:SetBinding(d.binding) end
    OPieSkin.Accent(f)
    paintTint(d, true)
    paintGray(d)
end

-- Only the accent colors, each time the ring opens.
function OPieSkin.Accent(f)
    local d = f.dui
    local ck = d.L.checked == "custom" and d.L.checkedColor or { Style.Accent() }
    d.check:SetColorTexture(ck[1], ck[2], ck[3], 1)
    paintBorder(d)
end

local Button = {} -- the methods OPie calls
OPieSkin.Button = Button

function Button:SetIcon(texture, aspect)
    local d = self.dui
    d.icon:SetTexture(texture)
    d.atlas = false
    local c = d.crop
    d.icon:SetTexCoord(c[1], c[2], c[3], c[4])
    d.aspect = aspect or 1
end
function Button:SetIconAtlas(atlas, aspect)
    local d = self.dui
    d.icon:SetAtlas(atlas)
    d.atlas = true
    d.aspect = aspect or 1
end
function Button:SetIconTexCoord(a, b, c, e, ...)
    if a and b and c and e then self.dui.icon:SetTexCoord(a, b, c, e, ...) end
end
function Button:SetIconVertexColor(r, g, b)
    local d = self.dui
    r, g, b = r or 1, g or 1, b or 1
    if d.ir == r and d.ig == g and d.ib == b then return end
    d.ir, d.ig, d.ib = r, g, b
    setTint(d, d.tA or 1, d.tR or 1, d.tG or 1, d.tB or 1)
end
-- These flags are plain (OPie tests them itself before calling). Its usable is
-- also false on any cooldown, global included (ActionBook Handlers.lua: usable
-- and inRange and cdUsable). Out of combat onCooldown says so. In combat every
-- cooldown arrives as a duration object (SetCooldownDuration, right after this)
-- and onCooldown stays false, so "unusable" and "on cooldown" can't be told
-- apart. The unusable gray therefore waits until combat ends, otherwise it would
-- flash on every global cooldown.
local function paintUsable(d)
    local usable = d.uUsable
    local out, power = (not usable and d.uRange) and true or false, (not usable and d.uMana) and true or false
    local unusable = (not usable and not out and not power and not d.uCd and not d.fightCd) and true or false
    if d.outOfRange == out and d.noPower == power and d.unusable == unusable then return end
    d.outOfRange, d.noPower, d.unusable = out, power, unusable
    paintTint(d)
end
function Button:SetUsable(usable, _, onCooldown, noMana, noRange)
    local d = self.dui
    d.uUsable, d.uCd, d.uMana, d.uRange = usable, onCooldown, noMana, noRange
    paintUsable(d)
end
-- OPie's color for the slice (taken from the icon) is for its center pointer and
-- glow. The buttons keep the action bar look.
function Button:SetDominantColor() end
function Button:SetOverlayIcon(tex, w, h, ...)
    local o = self.dui.overIcon
    if not tex then return o:Hide() end
    o:SetTexture(tex)
    o:SetSize(w, h)
    if ... then o:SetTexCoord(...) else o:SetTexCoord(0, 1, 0, 1) end
    o:Show()
end
function Button:SetOverlayIconVertexColor(r, g, b, a)
    self.dui.overIcon:SetVertexColor(r, g, b, a or 1)
end
-- The count may be secret (an item's, in combat), so only its type is checked.
function Button:SetCount(count)
    local fs = self.dui.count
    if type(count) == "nil" or type(count) == "boolean" then fs:SetText("") else fs:SetText(count) end
end
-- The keybind as the action bars show it (shortened if the look says so). OPie
-- sends it many times a second, so it's only reformatted when it changes.
function Button:SetBinding(binding)
    local d = self.dui
    d.binding = binding or false
    local short = d.L.shortKeys == true
    if d.shownKey == binding and d.shownShort == short then return end
    d.shownKey, d.shownShort = binding, short
    local text = binding and GetBindingText(binding, 1) or ""
    if short and text ~= "" then text = d.A.Shorten(text) end
    d.key:SetText(text)
end
function Button:SetShortLabel(text)
    self.dui.label:SetText(text or "")
end
function Button:SetQualityOverlay(_, atlas)
    local q = self.dui.quality
    if atlas then q:SetAtlas(atlas) end
    q:SetShown(atlas ~= nil)
end
-- In your bags (yellow) or equipped (green): a small corner mark.
function Button:SetEquipState(inBags, worn)
    local m = self.dui.mark
    local on = inBags or worn
    m:SetShown(on and true or false)
    if on then
        local c = worn and Style.INK.GOOD or Style.INK.WARN
        m:SetVertexColor(c[1], c[2], c[3], 1)
    end
end

-- Cooldowns use the client's own sweep in the look's color, with numbers as the
-- look says. A recharge (charges left) draws only the edge with no numbers, like
-- the action bars' charge cooldown, so the icon stays bright while usable.
local function sweepKind(d, recharge)
    if d.recharge == recharge then return end
    d.recharge = recharge
    d.cd:SetDrawSwipe(not recharge)
    d.cd:SetDrawEdge(recharge or d.A.EdgeOf ~= nil and d.A.EdgeOf(d.L) ~= nil)
    d.cd:SetHideCountdownNumbers(recharge or not d.numbers)
end
local function setCooling(d, on)
    if d.cooling == on then return end
    d.cooling = on
    paintTint(d)
    paintGray(d)
end
-- Plain numbers (out of combat, or a spell OPie reads itself): seconds left and
-- total length. OPie calls this many times a second while the ring is open, so
-- the sweep is only reset when its end time moves.
function Button:SetCooldown(remain, duration, usableCharge)
    local d = self.dui
    if d.fightCd then
        d.fightCd = false
        paintUsable(d)
    end
    if (duration or 0) <= 0 or (remain or 0) <= 0 then
        if d.ends or d.fromDuration then d.cd:Clear() end
        d.ends, d.length, d.fromDuration = nil, nil, nil
        setCooling(d, false)
        return
    end
    local ends = GetTime() + remain
    local recharge = usableCharge and true or false
    sweepKind(d, recharge)
    setCooling(d, not recharge and duration > OPieSkin.GCD)
    if d.length ~= duration or not d.ends or math.abs(d.ends - ends) > 0.05 then
        d.ends, d.length, d.fromDuration = ends, duration, nil
        d.cd:SetCooldown(ends - duration, duration)
    end
end
-- In combat: the client's duration object, drawn by the client. Its length
-- can't be read, so a real cooldown can't be told from the global one. The
-- look's gray and opacity on cooldown therefore stay off in combat, even for
-- one started before the pull, until plain numbers bring them back.
function Button:SetCooldownDuration(duration, isRecharge)
    local d = self.dui
    if not d.fightCd then
        d.fightCd = true
        paintUsable(d)
    end
    setCooling(d, false)
    sweepKind(d, isRecharge and true or false)
    d.ends, d.length, d.fromDuration = nil, nil, true
    d.cd:SetCooldownFromDurationObject(duration, true)
end

function Button:SetActive(on)
    local d = self.dui
    alphaFrom(d.check, on, d.L.checkedAlpha or 0.3)
end
function Button:SetHighlighted(on)
    local d = self.dui
    alphaFrom(d.wash, on, d.L.highlightAlpha or 0.12)
    local picked = not secret(on) and on and true or false
    if d.picked ~= picked then
        d.picked = picked
        if d.L.hoverBorder then paintBorder(d) end
    end
end
-- A proc (OPie's overlay glow) colors the border. A secret flag can't choose a
-- color, so the border is left as is then.
function Button:SetOuterGlow(on)
    local d = self.dui
    local proc = not secret(on) and on and true or false
    if d.procOn == proc then return end
    d.procOn = proc
    paintBorder(d)
end

-- One button. OPie positions, scales, shows and parents it itself; everything
-- else goes through the methods above.
function OPieSkin.Create(name, parent, size)
    local f = CreateFrame("Frame", name, parent)
    f:SetSize(size, size)
    local d = { ir = 1, ig = 1, ib = 1, tintKey = {}, grayKey = {}, crop = Style.ICON_CROP }
    f.dui = d
    for k, fn in pairs(Button) do f[k] = fn end
    local A = kit()
    d.A, d.L = A, A.Look()
    -- The shell backs the button. It gets its own options table (a proc color
    -- is written into it) and the look's thickness.
    d.opts = { noBevel = true, borderPx = function() return d.A.BorderPx(d.L) end }
    d.back = Style.Shell(f, d.opts)

    d.icon = f:CreateTexture(nil, "ARTWORK", nil, 1)
    d.check = f:CreateTexture(nil, "ARTWORK", nil, 2)
    d.check:SetAllPoints(d.icon)
    d.check:SetAlpha(0)
    d.shade = f:CreateTexture(nil, "ARTWORK", nil, 3)
    d.shade:SetTexture(A.SHADE_FILE)
    d.shade:SetVertexColor(0, 0, 0, A.SHADE)
    d.shade:SetAllPoints(d.icon)
    d.wash = f:CreateTexture(nil, "ARTWORK", nil, 4)
    d.wash:SetAllPoints(d.icon)
    d.wash:SetAlpha(0)

    d.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    d.cd:SetAllPoints(d.icon)
    d.cd:SetFrameLevel(f:GetFrameLevel() + 1)
    d.recharge = false

    -- Text and marks sit above the sweep.
    d.top = CreateFrame("Frame", nil, f)
    d.top:SetAllPoints()
    d.top:SetFrameLevel(d.cd:GetFrameLevel() + 1)
    d.key = d.top:CreateFontString(nil, "OVERLAY")
    d.count = d.top:CreateFontString(nil, "OVERLAY")
    d.label = d.top:CreateFontString(nil, "OVERLAY")
    d.label:SetJustifyH("CENTER")
    d.label:SetMaxLines(1)
    d.overIcon = d.top:CreateTexture(nil, "OVERLAY", nil, 1)
    d.overIcon:SetPoint("BOTTOMLEFT", d.icon, "BOTTOMLEFT", 1, 1)
    d.overIcon:Hide()
    d.quality = d.top:CreateTexture(nil, "OVERLAY", nil, 2)
    d.quality:SetSize(14, 14)
    d.quality:SetPoint("TOPLEFT", d.icon, "TOPLEFT", 1, -1)
    d.quality:Hide()
    d.mark = d.top:CreateTexture(nil, "OVERLAY", nil, 2)
    d.mark:SetTexture(WHITE)
    d.mark:SetSize(6, 6)
    d.mark:SetPoint("TOPLEFT", d.icon, "TOPLEFT", 2, -2)
    d.mark:Hide()

    OPieSkin.Restyle(f)
    -- Each time the ring opens: re-read the accent (proc, checked, lit border;
    -- cheap, colors only), and the whole look if it changed while hidden.
    f:SetScript("OnShow", function()
        if d.stale then
            d.stale = nil
            OPieSkin.Restyle(f)
        else
            OPieSkin.Accent(f)
        end
    end)
    OPieSkin.made[f] = true
    return f
end

-- Restyles every button: shown ones now, the rest as they show.
function OPieSkin.RestyleAll()
    for f in pairs(OPieSkin.made) do
        if f:IsVisible() then OPieSkin.Restyle(f) else f.dui.stale = true end
    end
end

Engine.Register({ key = "opie", pack = "addons", addon = ADDON, switch = "opie", label = "OPie",
    thirdParty = true, apply = function(_, def)
    local ui = type(_G.OPie) == "table" and _G.OPie.UI
    if type(ui) ~= "table" or type(ui.RegisterIndicatorConstructor) ~= "function" then return false end
    local ok, err = ui:RegisterIndicatorConstructor(OPieSkin.KEY, {
        name = "Daylight UI",
        apiLevel = 5,
        CreateIndicator = OPieSkin.Create,
        supportsShortLabels = true,
    })
    -- OPie refused our buttons (a newer OPie wants more): report it in chat,
    -- and OPie keeps its own.
    if not ok then error(tostring(err)) end
    DUI.On("ActionButtonLookChanged", Engine.Safe(def, OPieSkin.RestyleAll))
    DUI.On("StyleChanged", Engine.Safe(def, OPieSkin.RestyleAll))
end })
