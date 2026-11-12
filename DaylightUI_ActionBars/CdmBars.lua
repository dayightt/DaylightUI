-- Bars for spells the game only draws as icons (Essential and Utility cooldowns,
-- Tracked Buffs, spells it doesn't display), placed in one of the player's bar
-- blocks (CdmRows). Both kinds copy the shape of the game's buff bar (an Icon
-- frame holding Icon, a Bar with its Name), so the skin (CD.SkinItem, CD.StyleText)
-- and the bar layout (BuffBars.lua) dress them exactly like the game's bars.
--  * Cooldown bar: the client fills it from the spell's cooldown duration object
--    (StatusBar:SetTimerDuration, filling as the spell comes back, full = ready)
--    and counts down on a Cooldown frame's numbers, as M:SS.
--  * Aura bar: the client's aura container (CdmAuras.Setup) with one button that
--    carries a bar the client fills itself (SetDurationBar, emptying as the aura
--    runs out), plus the aura's time and stacks, laid over an empty bar of ours
--    with the spell's name.
-- No cooldown or aura value is read or compared; the client does the math. The
-- aura button and everything on it lock whenever auras are secret, so it is only
-- re-laid out through DUI.AfterRestrictions.

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel
local Skin = ns.Skin
local CD = ns.Cooldowns

local B = {}
ns.CdmBars = B

B.TIME_W = 40        -- width of the cooldown bar's time box at its right end
B.UNDER_ALPHA = 0.5  -- alpha of the aura bar's own icon under the client's while the aura is down
B.NEXT_ALPHA = 0.55  -- alpha of a charge bar's recharging piece
B.LINE = { 0, 0, 0, 0.7 }

local cooldowns = {}  -- [cooldownID] = cooldown bar
local auras = {}      -- [cooldownID] = aura bar holder
local gen = 0         -- bumped on a style change so every aura bar lays out again
DUI.On("StyleChanged", function() gen = gen + 1 end)

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function plainBool(v) if type(v) == "boolean" and not secret(v) then return v end end
local function plainNum(v) if type(v) == "number" and not secret(v) then return v end end

local function spellAPI(name)
    local f = type(C_Spell) == "table" and C_Spell[name]
    return type(f) == "function" and f or nil
end

-- The game's bar shape: Icon (a frame holding the texture) on the left, Bar for the
-- rest with its Name on the left. nameParent is where the name lives (over the
-- client's bar for an aura bar). body is where the icon and bar live (an aura bar's
-- h.under, so they move together).
local function shape(f, id, nameParent, body)
    f:SetSize(220, 18)
    body = body or f
    f.Icon = CreateFrame("Frame", nil, body)
    f.Icon:SetSize(18, 18)
    f.Icon:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.Icon.Icon = f.Icon:CreateTexture(nil, "ARTWORK")
    f.Icon.Icon:SetAllPoints()
    f.Icon.Icon:SetTexture(134400)
    f.Bar = CreateFrame("StatusBar", nil, body)
    f.Bar:SetPoint("TOPLEFT", f.Icon, "TOPRIGHT", 1, 0)
    f.Bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    Style.TrackBar(f.Bar, nil, ns.MEDIA.bars.cdm)
    f.Bar:SetMinMaxValues(0, 1)
    f.Bar:SetValue(1)
    local name = (nameParent or f.Bar):CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", f.Bar, "LEFT", 4, 0)
    name:SetPoint("RIGHT", f.Bar, "RIGHT", -B.TIME_W, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    f.Bar.Name = name
    f.cooldownID = id
    f.cooldownInfo = {}
end

-- The spell's icon and name, once the game knows them (retried until then).
local function fill(f, id)
    if f.cooldownInfo.spellID then return end
    local sid = ns.CdmOwn and ns.CdmOwn.SpellOf(id)
    if not sid then return end
    f.cooldownInfo.spellID = sid
    local tex = spellAPI("GetSpellTexture")
    tex = tex and tex(sid)
    if type(tex) ~= "nil" then f.Icon.Icon:SetTexture(tex) end
    local nameOf = spellAPI("GetSpellName")
    local ok, name = false, nil
    if nameOf then ok, name = pcall(nameOf, sid) end
    local C = ns.CdmCustom
    if C and C.Is(id) then   -- custom entries may have their own name and icon (the Seal)
        local own, look = C.Look(id)
        name, ok = own, true
        if type(look) ~= "nil" then f.Icon.Icon:SetTexture(look) end
    end
    if ok and type(name) == "string" and not secret(name) then f.Bar.Name:SetText(name) end
end

-- Cooldown bars ----------------------------------------------------------

local function enums()
    local E = _G.Enum
    local I = type(E) == "table" and E.StatusBarInterpolation
    local D = type(E) == "table" and E.StatusBarTimerDirection
    return type(I) == "table" and I.Immediate or nil, type(D) == "table" and D.ElapsedTime or nil
end

-- Charge lines cut the bar into one piece per charge. The bar's own fill is the
-- charges held (max = most charges, value = current count; a secret value is fine
-- since the client draws it). The recharging piece (f.next, one charge wide) hangs
-- off the fill's moving edge and the client fills it from the recharge.
local function lines(f, most)
    f.lines = f.lines or {}
    local w = f.Bar:GetWidth()
    for i = 1, math.max(most - 1, #f.lines) do
        local t = f.lines[i]
        if i < most then
            if not t then
                f.lineFrame = f.lineFrame or CreateFrame("Frame", nil, f.Bar)
                f.lineFrame:SetAllPoints(f.Bar)
                f.lineFrame:SetFrameLevel(f.Bar:GetFrameLevel() + 3)
                t = f.lineFrame:CreateTexture(nil, "OVERLAY")
                t:SetColorTexture(B.LINE[1], B.LINE[2], B.LINE[3], B.LINE[4])
                f.lines[i] = t
            end
            t:ClearAllPoints()
            t:SetPoint("TOP", f.Bar, "TOPLEFT", w * i / most, 0)
            t:SetPoint("BOTTOM", f.Bar, "BOTTOMLEFT", w * i / most, 0)
            t:SetWidth(Pixel.Px(f.Bar, 1))
            t:Show()
        elseif t then
            t:Hide()
        end
    end
end

local function segmented(f, most, count, d)
    if not f.next then
        f.next = CreateFrame("StatusBar", nil, f.Bar)
        f.next:SetFrameLevel(f.Bar:GetFrameLevel() + 1)
        Style.TrackBar(f.next, nil, ns.MEDIA.bars.cdm)
        f.next:SetMinMaxValues(0, 1)
    end
    f.Bar:SetMinMaxValues(0, most)
    f.Bar:SetValue(count)
    local edge = f.Bar:GetStatusBarTexture()
    f.next:ClearAllPoints()
    f.next:SetPoint("TOPLEFT", edge, "TOPRIGHT", 0, 0)
    f.next:SetPoint("BOTTOMLEFT", edge, "BOTTOMRIGHT", 0, 0)
    f.next:SetWidth(math.max(1, f.Bar:GetWidth() / most))
    local r, g, b = f.Bar:GetStatusBarColor()
    f.next:SetStatusBarColor(r or 1, g or 1, b or 1, B.NEXT_ALPHA)
    lines(f, most)
    local I, D = enums()
    if type(d) ~= "nil" and pcall(f.next.SetTimerDuration, f.next, d, I, D) then
        f.next:Show()
    else
        f.next:Hide()
    end
end

local function whole(f)
    if f.next then f.next:Hide() end
    if f.lines then for _, t in ipairs(f.lines) do t:Hide() end end
end

-- Drives the bar from the spell's cooldown, or with charges the next charge's
-- recharge. The client fills it; it stays full while ready. The global cooldown is
-- ignored (isOnGCD and isActive are never secret). With charge lines on (the
-- default), one piece per charge.
function B.UpdateCooldown(f)
    local sid = f.cooldownInfo and f.cooldownInfo.spellID
    if not sid then return end
    local d, active, count = nil, false, ""
    local C = ns.CdmCustom
    local item = C and C.ItemOf(f.cooldownID)
    local charges = not item and spellAPI("GetSpellCharges")
    local okC, ch = false, nil
    if charges then okC, ch = pcall(charges, sid) end
    local most = okC and type(ch) == "table" and plainNum(ch.maxCharges)
    if most and most > 1 then
        active = plainBool(ch.isActive) == true
        -- currentCharges may be secret, so it only goes to SetText.
        if type(ch.currentCharges) ~= "nil" then count = ch.currentCharges end
        local get = active and spellAPI("GetSpellChargeDuration")
        if get then
            local ok, x = pcall(get, sid)
            if ok then d = x end
        end
    elseif item then   -- an item added by ID: use the item's cooldown and count
        active, d = C.ItemCooldown(f.cooldownID)
        local n = C.ItemCount(f.cooldownID)
        if n then count = tostring(n) end
    else
        local cd = spellAPI("GetSpellCooldown")
        local ok, info = false, nil
        if cd then ok, info = pcall(cd, sid) end
        if ok and type(info) == "table" then
            active = plainBool(info.isActive) == true and plainBool(info.isOnGCD) ~= true
        end
        local get = active and spellAPI("GetSpellCooldownDuration")
        if get then
            local ok2, x = pcall(get, sid, true)
            if ok2 then d = x end
        end
    end
    f.ChargeCount.Current:SetText(count)
    if most and most > 1 and f.ownBar == "cooldown" and ns.CdmEffects.Get(f.button, "chargeLines") ~= false
        and type(ch.currentCharges) ~= "nil" then
        f.Timer:Clear()
        if active and type(d) ~= "nil" then pcall(f.Timer.SetCooldownFromDurationObject, f.Timer, d, true) end
        segmented(f, most, ch.currentCharges, active and d or nil)
        return
    end
    whole(f)
    if active and type(d) ~= "nil" then
        local I, D = enums()
        local ok = pcall(f.Bar.SetTimerDuration, f.Bar, d, I, D)
        pcall(f.Timer.SetCooldownFromDurationObject, f.Timer, d, true)
        if ok then return end
    end
    f.Bar:SetMinMaxValues(0, 1)
    f.Bar:SetValue(1)
    f.Timer:Clear()
end

-- Applies the time size, color and the block's time toggle to the countdown numbers.
local function dressTimer(f, block)
    local Look = ns.CdmData.Look
    local t, time = CD.BarText(block), not block or Look(block, "time") ~= false
    local c = t.timeColor
    local key = table.concat({ t.timeSize, tostring(time), c[1], c[2], c[3], gen }, "|")
    if f.timerAs == key then return end
    f.timerAs = key
    pcall(f.Timer.SetHideCountdownNumbers, f.Timer, not time)
    local fs = f.Timer.GetCountdownFontString and f.Timer:GetCountdownFontString()
    if type(fs) == "table" then
        Style.DressText(fs, t.timeSize, { slot = ns.MEDIA.font })
        CD.Ink(fs, c)
    end
end

local function fitCooldown(f, w, h, block, button)
    dressTimer(f, block)
    -- Per-button options (charge lines) and the bar's new width.
    if button then f.button = button end
    B.UpdateCooldown(f)
end

-- The cooldown time (the client's own countdown numbers, no swipe) and the charge
-- count, on a cooldown bar or under an aura bar.
local function addTimer(f)
    local t = CreateFrame("Cooldown", nil, f.Bar, "CooldownFrameTemplate")
    t:SetPoint("TOPRIGHT", f.Bar, "TOPRIGHT", 0, 0)
    t:SetPoint("BOTTOMRIGHT", f.Bar, "BOTTOMRIGHT", 0, 0)
    t:SetWidth(B.TIME_W)
    pcall(t.SetDrawSwipe, t, false)
    pcall(t.SetDrawEdge, t, false)
    pcall(t.SetDrawBling, t, false)
    local clock = Style.ClockFormatter()
    if clock and t.SetCountdownFormatter then pcall(t.SetCountdownFormatter, t, clock) end
    t:HookScript("OnCooldownDone", function() DUI.SafeCall(B.UpdateCooldown, f) end)
    f.Timer = t
    local count = f.Icon:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", f.Icon, "BOTTOMRIGHT", -1, 1)
    f.ChargeCount = { Current = count }
end

function B.Cooldown(id, parent)
    local f = cooldowns[id]
    if not f then
        f = CreateFrame("Frame", nil, parent)
        shape(f, id)
        f.ownBar = "cooldown"
        addTimer(f)
        f.fitBar = fitCooldown
        cooldowns[id] = f
        DUI.SafeCall(CD.SkinItem, f)
    elseif f:GetParent() ~= parent then
        f:SetParent(parent)
    end
    fill(f, id)
    -- Coming back from "Hide out of combat". The effects set their own alpha after this.
    f:SetAlpha(1)
    f:Show()
    B.UpdateCooldown(f)
    return f
end

function B.UpdateAll()
    for _, f in pairs(cooldowns) do
        if f:IsShown() then DUI.SafeCall(B.UpdateCooldown, f) end
    end
    for _, h in pairs(auras) do
        if h.cooldownUnder and h:IsShown() then DUI.SafeCall(B.UpdateCooldown, h) end
    end
end

-- Aura bars --------------------------------------------------------------

-- Shields ----------------------------------------------------------------

-- Spells that absorb damage (rank 1 ids; every rank counts). As an aura bar these
-- fill by the shield left instead of the time, unless the spell's fillBy is set to
-- "time". Power Word: Shield, Mana Shield, Ice Barrier, Fire/Frost/Shadow Ward,
-- Sacrifice.
B.SHIELDS = { 17, 1463, 11426, 543, 6143, 6229, 7812 }
-- The shield is your friendly target's, else yours (CdmAuras.ShieldUnit). The
-- amount is the game's total absorb on them (UnitGetTotalAbsorbs), which is always
-- secret, so it only goes to SetMinMaxValues, SetValue and SetText. The bar is just
-- that amount: empty with no shield, never waiting on the client's button (in game
-- the client's time bar showed while that button didn't). A shield's starting size
-- can't be read, so the amounts seen in the first B.FRESH seconds after you cast
-- one (your own casts stay plain), after its button appears, or after the unit
-- changes are taken as the full value.
B.FRESH = 0.5

local shieldIDs   -- [any rank's spell id] = true
local function shieldTable()
    if not shieldIDs then
        shieldIDs = {}
        local first = {}
        for _, s in ipairs(B.SHIELDS) do first[s] = true end
        for _, list in pairs(ns.CdmSpells or {}) do
            if type(list) == "table" then
                for _, f in ipairs(list) do
                    if type(f) == "table" and first[f[1]] then
                        for _, s in ipairs(f) do shieldIDs[s] = true end
                    end
                end
            end
        end
    end
    return shieldIDs
end
function B.IsShield(id)
    local sid = ns.CdmOwn and ns.CdmOwn.SpellOf(id)
    return sid ~= nil and shieldTable()[sid] == true
end

local function isShieldSpell(sid) return shieldTable()[sid] == true end

local function byShield(h)
    return h.isShield == true and ns.CdmEffects.Get(h.button, "fillBy") ~= "time"
end

-- Puts the remaining shield on the bar. The first amounts after it lands set the full value.
function B.UpdateShield(h)
    local s = h.shield
    if not (s and byShield(h)) then return end
    local v = UnitGetTotalAbsorbs(h.shieldUnit or "player")
    if type(v) == "nil" then return end
    if GetTime() < (h.freshUntil or 0) then
        s:SetMinMaxValues(0, v)
        s:SetValue(v)
    else
        Style.SetBarValue(s, v)
    end
    s.text:SetText(AbbreviateNumbers(v))
    -- Any amount fills the 0-1 gate so its clip shows the text; with none it's hidden.
    s.gate:SetValue(v)
    h.shieldGate:SetValue(v)
end

-- The client's button appeared (the shield landed) or went away: take a new full.
-- Gone and back within B.BLINK seconds is the client rebuilding it on a refresh,
-- not a new shield, so the full value stays.
B.BLINK = 0.25
local function shieldShown(h, btn, up)
    h.upButtons = h.upButtons or {}
    h.upButtons[btn] = up or nil
    local on = next(h.upButtons) ~= nil
    if on and not h.shieldUp and not (h.goneAt and GetTime() - h.goneAt <= B.BLINK) then
        h.freshUntil = GetTime() + B.FRESH
        B.UpdateShield(h)
    elseif not on and h.shieldUp then
        h.goneAt = GetTime()
    end
    h.shieldUp = on
end

-- Places our shield bar where the client's bar is (same numbers as LayoutButton), in
-- the bar's color, with the amount on the right where the time was ("Show shield
-- amount") and the name while the button wears the bar's look itself (h.bare). It's
-- our own frame so it never locks, but it's laid out together with the button.
local function layoutShield(h)
    local s = h.shield
    if not s then return end
    local on = byShield(h)
    s:SetShown(on)
    if not on then return end
    -- Hide when buff missing: the whole bar sits in the gate's clip, so no shield
    -- shows nothing. The amount is secret and never tested, only drawn.
    local hide = ns.CdmEffects.Get(h.button, "hideMissing") == true
    s:SetParent(hide and h.shieldClip or h)
    h.shieldGate:SetFrameLevel(h.over:GetFrameLevel() - 2)
    local hh = h.h
    local p = CD.Parts(h)
    local block = ns.CdmRows and ns.CdmRows.BlockOf(h)
    local Look = ns.CdmData.Look
    local icon = not block or Look(block, "icon") ~= false
    local T = (p and p.slot) and Pixel.Px(h.Bar, Style.BorderPx(p.slot)) or 0
    s:ClearAllPoints()
    s:SetPoint("TOPLEFT", h, "TOPLEFT", icon and (hh + Pixel.Px(h.Bar, 1) + T) or T, -T)
    s:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -T, T)
    s:SetFrameLevel(h.over:GetFrameLevel() - 1)
    s:SetStatusBarTexture(Style.BarFile("fill", ns.MEDIA.bars.cdm))
    Style.SetBarGradient(s, false)
    s.spellColour = nil
    CD.ColourBase(h, s, s, block and Look(block, "color") or ns.CdmData.BAR_LOOK.color, h.button)
    local t = CD.BarText(block)
    s.text:SetFont(Style.FontFile(ns.MEDIA.font), t.timeSize, Style.Outline())
    CD.Ink(s.text, t.timeColor)
    s.text:SetAlpha(ns.CdmEffects.Get(h.button, "shieldAmount") ~= false and 1 or 0)
    local Fx = ns.CdmEffects
    local name = s.name
    Style.DressText(name, t.nameSize, { untracked = true, slot = ns.MEDIA.font })
    CD.Ink(name, t.nameColor)
    name:SetText(h.Bar.Name:GetText() or "")
    name:ClearAllPoints()
    if Fx.Get(h.button, "nameAlign") == "center" then
        name:SetPoint("CENTER", s, "CENTER", 0, 0)
        name:SetJustifyH("CENTER")
    else
        name:SetPoint("LEFT", s, "LEFT", 4, 0)
        name:SetPoint("RIGHT", s, "RIGHT", -B.TIME_W, 0)
        name:SetJustifyH("LEFT")
    end
    name:SetAlpha(h.bare and Fx.Get(h.button, "showName") ~= false and 1 or 0)
    B.UpdateShield(h)
end

local function makeShield(h)
    -- The same kind of gate for the whole bar, used while "Hide when missing" is on.
    local g = CreateFrame("StatusBar", nil, h)
    g:SetAllPoints(h)
    g:SetStatusBarTexture(Style.BarFile("fill"))
    g:GetStatusBarTexture():SetAlpha(0)
    g:SetMinMaxValues(0, 1)
    g:SetValue(0)
    h.shieldGate = g
    h.shieldClip = CreateFrame("Frame", nil, g)
    h.shieldClip:SetClipsChildren(true)
    h.shieldClip:SetAllPoints(g:GetStatusBarTexture())
    local s = CreateFrame("StatusBar", nil, h)
    s:SetMinMaxValues(0, 1)
    s:SetValue(0)
    -- The amount shows only while there is one. A 0-1 bar of its own (no fill drawn)
    -- takes the secret amount and the text sits in a clip on its fill.
    s.gate = CreateFrame("StatusBar", nil, s)
    s.gate:SetAllPoints(s)
    s.gate:SetStatusBarTexture(Style.BarFile("fill"))
    s.gate:GetStatusBarTexture():SetAlpha(0)
    s.gate:SetMinMaxValues(0, 1)
    s.gate:SetValue(0)
    local clip = CreateFrame("Frame", nil, s.gate)
    clip:SetClipsChildren(true)
    clip:SetAllPoints(s.gate:GetStatusBarTexture())
    s.text = clip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.text:SetPoint("RIGHT", s, "RIGHT", -4, 0)
    s.name = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.name:SetWordWrap(false)
    h.shield = s
end

-- Another unit's shield: take its full value fresh from what it has now.
function B.Retarget(h, unit)
    if h.shieldUnit == unit then return end
    h.shieldUnit = unit
    h.freshUntil = GetTime() + B.FRESH
    B.UpdateShield(h)
end

local function eachShield(fn)
    for _, h in pairs(auras) do
        if h.shield and h.shield:IsShown() and h:IsShown() then fn(h) end
    end
end

DUI.RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED", function()
    eachShield(B.UpdateShield)
end)

-- You cast a shield on yourself or your target, so the next amounts are its full.
-- Only your own casts, filtered by the client: other units' casts come through
-- secret under restrictions, and in a raid they never stop.
local castWatch = CreateFrame("Frame")
castWatch:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
castWatch:SetScript("OnEvent", function(_, _, _, _, sid)
    if type(sid) ~= "number" or secret(sid) or not isShieldSpell(sid) then return end
    eachShield(function(h)
        h.freshUntil = GetTime() + B.FRESH
        B.UpdateShield(h)
    end)
end)

local function layoutFor(h)
    return { layoutIndex = 1, elementWidth = h.w, elementHeight = h.h, elementSpacing = 0 }
end

-- Places the button's pieces to match the holder's (the BuffBars layout): icon inside
-- its border, bar after it inside its border, time at the bar's right, fill in the
-- block's color. Only inside initializeFrame or after restrictions, since the client
-- locks the button otherwise.
function B.LayoutButton(h, btn, parts)
    ns.CdmEffects.TuneSlide(btn)
    local w, hh = h.w, h.h
    btn:SetSize(w, hh)
    local p = CD.Parts(h)
    local block = ns.CdmRows and ns.CdmRows.BlockOf(h)
    local Look = ns.CdmData.Look
    local icon = not block or Look(block, "icon") ~= false
    local inset = Pixel.Px(h, Skin.BORDER_PX)
    local T = (p and p.slot) and Pixel.Px(h.Bar, Style.BorderPx(p.slot)) or 0
    local side = math.max(1, hh - 2 * inset)
    parts.icon:ClearAllPoints()
    parts.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", inset, -inset)
    parts.icon:SetSize(side, side)
    parts.icon:SetTexCoord(Skin.CROP[1], Skin.CROP[2], Skin.CROP[3], Skin.CROP[4])
    parts.icon:SetAlpha(icon and 1 or 0)
    Skin.PaintCdmShell(parts.iconShell)
    parts.shade:SetAlpha(icon and Skin.SHADE or 0)
    parts.count:SetAlpha(icon and 1 or 0)
    parts.bar:ClearAllPoints()
    parts.bar:SetPoint("TOPLEFT", btn, "TOPLEFT", icon and (hh + Pixel.Px(h.Bar, 1) + T) or T, -T)
    parts.bar:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -T, T)
    -- Over a cooldown, use a solid back so the cooldown underneath doesn't show
    -- through the aura bar's empty part while the aura is up.
    local cover = h.cooldownUnder and 1 or 0
    parts.back:SetAllPoints(parts.bar)
    parts.back:SetAlpha(cover)
    parts.backTex:SetAllPoints(parts.bar)
    parts.backTex:SetAlpha(cover)
    -- Use the bar's background color when one is set (CD.BackOf), otherwise dark.
    -- Never the texture's own white: a white fill on it looked like the fill.
    local back, v = CD.BackOf(h.button, block)
    if back then CD.PaintBack(parts.backTex, back, v) end
    local text = CD.BarText(block)
    parts.time:SetFont(Style.FontFile(ns.MEDIA.font), text.timeSize, Style.Outline())
    CD.Ink(parts.time, text.timeColor)
    parts.time:SetAlpha((not block or Look(block, "time") ~= false) and 1 or 0)
    parts.count:SetFont(Style.FontFile(ns.MEDIA.font), Skin.COUNT, Style.Outline())
    local cc = Skin.COUNT_COLOR
    parts.count:SetTextColor(cc[1], cc[2], cc[3])
    -- The fill: bar texture, then the block's or spell's color.
    local tex = parts.bar:GetStatusBarTexture()
    if tex then tex:SetTexture(Style.BarFile("fill", ns.MEDIA.bars.cdm)) end
    -- Filled by the shield left (our h.shield on top), so the client's fill, time
    -- and name step aside.
    local shield = byShield(h)
    if tex then tex:SetAlpha(shield and 0 or 1) end
    parts.bar:SetAlpha(shield and 0 or 1)
    if shield then parts.time:SetAlpha(0) end
    Style.SetBarGradient(parts.bar, false)
    parts.spellColour = nil
    CD.ColourBase(h, parts.bar, parts, block and Look(block, "color") or ns.CdmData.BAR_LOOK.color, h.button)
    -- No background color set: paint the empty part dark (ColourBase painted the cover).
    if not back then parts.backTex:SetVertexColor(parts.back:GetVertexColor()) end
    -- With "Show missing buffs" off (h.bare) our empty bar is gone, so the button
    -- wears the whole bar look itself (background, borders, name) and nothing shows
    -- while the aura is down.
    local bare = h.bare == true
    local box = parts.iconBox
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    box:SetSize(hh, hh)
    Style.Shell(box)
    box:SetAlpha(bare and icon and 1 or 0)
    parts.slot:ClearAllPoints()
    parts.slot:SetPoint("TOPLEFT", parts.bar, "TOPLEFT", -T, T)
    parts.slot:SetPoint("BOTTOMRIGHT", parts.bar, "BOTTOMRIGHT", T, -T)
    -- An explicit background color becomes the whole background (CD.OwnBack).
    parts.slotShell.opts.noBackground = back ~= nil or nil
    Style.Shell(parts.slot)
    parts.slot:SetAlpha(bare and 1 or 0)
    if bare then
        -- The empty part: dark, or the background color set above.
        parts.back:SetAlpha(0)
        parts.backTex:SetAlpha(1)
    end
    local Fx = ns.CdmEffects
    local name = parts.name
    Style.DressText(name, text.nameSize, { untracked = true, slot = ns.MEDIA.font })
    CD.Ink(name, text.nameColor)
    name:SetText(h.Bar.Name:GetText() or "")
    name:ClearAllPoints()
    if Fx and Fx.Get(h.button, "nameAlign") == "center" then
        name:SetPoint("CENTER", parts.bar, "CENTER", 0, 0)
        name:SetJustifyH("CENTER")
    else
        name:SetPoint("LEFT", parts.bar, "LEFT", 4, 0)
        name:SetPoint("RIGHT", parts.bar, "RIGHT", -B.TIME_W, 0)
        name:SetJustifyH("LEFT")
    end
    name:SetAlpha(bare and not shield and (not Fx or Fx.Get(h.button, "showName") ~= false) and 1 or 0)
end

local function relayout(h)
    -- Ours and the button's switch together so there's never a frame with neither.
    h.bare = h.wantBare
    h.under:SetAlpha(h.bare and 0 or 1)
    h.over:SetAlpha(h.bare and 0 or 1)
    for btn, parts in pairs(h.parts or {}) do DUI.SafeCall(B.LayoutButton, h, btn, parts) end
    DUI.SafeCall(layoutShield, h)
    if h.face then DUI.SafeCall(B.LayoutFace, h) end
end

-- The pieces of an aura bar: icon, bar, time, stacks and the bar's look for when
-- our empty bar is off. Made inside the client's button, or on a frame of ours
-- for a debuff on you (the self-debuff face).
local function makeParts(btn)
    local function try(fn, ...) return pcall(fn, ...) end
    local parts = {}
    parts.icon = btn:CreateTexture(nil, "ARTWORK")
    try(parts.icon.SetTexCoord, parts.icon, Skin.CROP[1], Skin.CROP[2], Skin.CROP[3], Skin.CROP[4])
    parts.shade = btn:CreateTexture(nil, "ARTWORK", nil, 3)
    try(parts.shade.SetAllPoints, parts.shade, parts.icon)
    try(parts.shade.SetTexture, parts.shade, Skin.SHADE_FILE)
    try(parts.shade.SetVertexColor, parts.shade, 0, 0, 0, 1)
    -- The cover over a cooldown under the bar (LayoutButton shows it): background
    -- color first, then the bars' own empty-part texture.
    parts.back = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
    try(parts.back.SetColorTexture, parts.back, Style.BACKGROUND[1], Style.BACKGROUND[2], Style.BACKGROUND[3], 1)
    parts.backTex = btn:CreateTexture(nil, "BACKGROUND", nil, -7)
    try(parts.backTex.SetTexture, parts.backTex, Style.BackFile(ns.MEDIA.bars.cdm .. ".back"))
    parts.bar = CreateFrame("StatusBar", nil, btn)
    try(parts.bar.SetStatusBarTexture, parts.bar, Style.BarFile("fill", ns.MEDIA.bars.cdm))
    try(parts.bar.SetMinMaxValues, parts.bar, 0, 1)
    parts.time = parts.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    try(parts.time.SetPoint, parts.time, "RIGHT", parts.bar, "RIGHT", -4, 0)
    parts.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    try(parts.count.SetPoint, parts.count, "BOTTOMRIGHT", parts.icon, "BOTTOMRIGHT", -1, 1)
    -- The bar's look while our empty bar is off ("Show missing buffs" off): the
    -- icon and bar borders and the name. Kept out of the style repaint because the
    -- client locks them, so LayoutButton (after restrictions) repaints them.
    parts.iconBox = CreateFrame("Frame", nil, btn)
    parts.iconBox:SetAlpha(0)
    local s = Style.Shell(parts.iconBox, Skin.ShellOpts())
    if s then Style.Untrack(s) end
    parts.iconShell = s
    parts.slot = CreateFrame("Frame", nil, btn)
    parts.slot:SetAlpha(0)
    parts.slot:SetFrameLevel(math.max(0, parts.bar:GetFrameLevel() - 1))
    parts.slotShell = Style.Shell(parts.slot, { borderPx = CD.BarBorder, heavyMinPx = CD.BAR_HEAVY_MIN })
    if parts.slotShell then Style.Untrack(parts.slotShell) else parts.slotShell = { opts = {} } end
    parts.name = parts.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    parts.name:SetWordWrap(false)
    parts.name:SetAlpha(0)
    if btn.SetMouseMotionEnabled then try(btn.SetMouseMotionEnabled, btn, false) end
    return parts
end

-- Built once inside the client's initializeFrame (the button locks once that
-- returns): our pieces, with the bar, time and stacks handed to the client.
local function initButton(h, btn)
    local function try(fn, ...) return pcall(fn, ...) end
    local parts = makeParts(btn)
    h.parts = h.parts or {}
    h.parts[btn] = parts
    try(btn.SetIcon, btn, parts.icon)
    -- Empties as the aura runs out, like the game's buff bars.
    local opts = {}
    local D = type(Enum) == "table" and Enum.StatusBarTimerDirection
    if type(D) == "table" and D.RemainingTime then opts.direction = D.RemainingTime end
    local U = _G.C_AuraContainerUtil
    if type(U) == "table" and type(U.ProcessCustomAuraButtonDurationBarOptions) == "function" then
        local ok, o = pcall(U.ProcessCustomAuraButtonDurationBarOptions, opts)
        if ok and type(o) == "table" then opts = o end
    end
    local ok, err = try(btn.SetDurationBar, btn, parts.bar, opts)
    if not ok then h.err = tostring(err) end
    -- The client's time as M:SS, like every other bar.
    try(Style.SetAuraTime, btn, parts.time, nil, Style.ClockFormatter())
    try(btn.SetApplicationCount, btn, parts.count)
    ns.CdmEffects.MakeSlide(btn, h)
    -- Shown and hidden, for the shield bar (ours, outside the button).
    try(btn.HookScript, btn, "OnShow", function() shieldShown(h, btn, true) end)
    try(btn.HookScript, btn, "OnHide", function() shieldShown(h, btn, false) end)
    DUI.SafeCall(B.LayoutButton, h, btn, parts)
end

-- A debuff on you (Arcane Blast's stack) gets no client button, so CdmAuras draws
-- it itself. As a bar that's the same pieces on a frame of the addon's own, which
-- never locks: the bar runs down the counted time and the time counts down on a
-- Cooldown's numbers, like a cooldown bar.
function B.MakeFace(h)
    local f = CreateFrame("Frame", nil, h)
    f:SetAllPoints(h)
    f:SetFrameLevel(h.Bar:GetFrameLevel() + 2)
    f:SetAlpha(0)
    f.parts = makeParts(f)
    f.count = f.parts.count
    local bar = f.parts.bar
    bar:SetValue(0)
    local t = CreateFrame("Cooldown", nil, bar, "CooldownFrameTemplate")
    t:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    t:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    t:SetWidth(B.TIME_W)
    pcall(t.SetDrawSwipe, t, false)
    pcall(t.SetDrawEdge, t, false)
    pcall(t.SetDrawBling, t, false)
    local clock = Style.ClockFormatter()
    if clock and t.SetCountdownFormatter then pcall(t.SetCountdownFormatter, t, clock) end
    f.Timer = t
    function f.SetTime(start, dur)
        local U = _G.C_DurationUtil
        if start and type(U) == "table" and type(U.CreateDuration) == "function" then
            f.span = f.span or U.CreateDuration()
            f.span:SetTimeFromStart(start, dur)
            local E = type(Enum) == "table" and Enum or {}
            local I = E.StatusBarInterpolation and E.StatusBarInterpolation.Immediate
            local D = E.StatusBarTimerDirection and E.StatusBarTimerDirection.RemainingTime
            pcall(bar.SetTimerDuration, bar, f.span, I, D)
            t:SetCooldown(start, dur)
        else
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(0)
            t:Clear()
        end
    end
    return f
end

-- The face's look, by the same numbers as the client's button.
function B.LayoutFace(h)
    local f = h.face
    if not (f and f.parts) then return end
    local tex = h.Icon.Icon:GetTexture()
    if type(tex) ~= "nil" then f.parts.icon:SetTexture(tex) end
    B.LayoutButton(h, f, f.parts)
    f.parts.time:SetText("")
    dressTimer(f, ns.CdmRows and ns.CdmRows.BlockOf(h))
end

-- What the buttons were last laid out for, so a change triggers a new layout.
local function shapeKey(h, block, button)
    local Look, Fx = ns.CdmData.Look, ns.CdmEffects
    local function rgb(c) return type(c) == "table" and table.concat({ c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1 }, ",") or "" end
    local function pair(g) return type(g) == "table" and (rgb(g.lo) .. ";" .. rgb(g.hi)) or "" end
    local back, v = CD.BackOf(button, block)
    local text = CD.BarText(block)
    return table.concat({ h.w, h.h, tostring(Look(block, "icon")), tostring(Look(block, "text")),
        text.nameSize, text.timeSize, rgb(text.nameColor), rgb(text.timeColor),
        tostring(Look(block, "time")), tostring(Look(block, "color")), tostring(Fx.Get(button, "barMode")),
        rgb(Fx.Get(button, "barColor")), pair(Fx.Get(button, "barGradient")),
        tostring(back), back == "solid" and rgb(v) or pair(v),
        tostring(h.cooldownUnder), tostring(h.wantBare), tostring(h.Bar.Name:GetText()),
        tostring(Fx.Get(button, "showName")), tostring(Fx.Get(button, "nameAlign")),
        tostring(h.isShield and Fx.Get(button, "fillBy")), tostring(h.isShield and Fx.Get(button, "shieldAmount")),
        tostring(h.isShield and Fx.Get(button, "hideMissing")),
        gen }, "|")
end

-- Holder size and look, from CdmRows' placement. The container slot updates at
-- once, the client's button after restrictions.
local function fitAura(h, w, hh, block, button)
    h.w, h.h, h.button = w, hh, button
    if h.Timer then dressTimer(h, block) end
    local key = shapeKey(h, block, button)
    if key == h.fitAs then return end
    h.fitAs = key
    for _, k in ipairs(h.containers or {}) do
        pcall(k.c.SetAuraGroupLayout, k.c, "a", layoutFor(h))
        pcall(k.c.SetFlowLayoutMaximumLineSize, k.c, w)
    end
    DUI.AfterRestrictions(function() relayout(h) end, "cdm:aurabar:" .. tostring(h.id))
end

-- An aura bar with the spell's cooldown running underneath (Thunder Clap). Our bar
-- shows the cooldown (full when ready) and the client's aura bar covers it while
-- the aura is up. Without it our bar stays empty with a dim icon.
local function setUnder(h, under)
    if h.cooldownUnder == under then return end
    h.cooldownUnder = under
    h.Icon.Icon:SetDesaturated(not under)
    h.Icon.Icon:SetAlpha(under and 1 or B.UNDER_ALPHA)
    if under then
        if not h.Timer then addTimer(h) end
        -- The client's bar over our cooldown and its time, the names over both.
        local level = h.Timer:GetFrameLevel() + 1
        for _, k in ipairs(h.containers or {}) do pcall(k.c.SetFrameLevel, k.c, level) end
    else
        if h.Timer then
            h.Timer:Clear()
            h.ChargeCount.Current:SetText("")
        end
        h.Bar:SetMinMaxValues(0, 1)
        h.Bar:SetValue(0)
    end
end

-- always = "Show missing buffs": our empty bar shows while the aura is down. When
-- off, only the client's button shows, wearing the bar's look.
function B.Aura(id, parent, under, always)
    under = under == true
    local h = auras[id]
    if not h then
        h = CreateFrame("Frame", nil, parent)
        -- Our empty bar (icon, bar and their borders) under the client's.
        h.under = CreateFrame("Frame", nil, h)
        h.under:SetAllPoints(h)
        -- The name sits over the client's bar.
        h.over = CreateFrame("Frame", nil, h)
        h.over:SetAllPoints(h)
        shape(h, id, h.over, h.under)
        h.ownBar = "aura"
        h.Bar:SetValue(0)     -- stays empty; the client's bar fills over it
        h.Icon.Icon:SetDesaturated(true)
        h.Icon.Icon:SetAlpha(B.UNDER_ALPHA)
        h.cooldownUnder = false
        h.w, h.h = 220, 18
        h.layoutFor, h.init = layoutFor, initButton
        h.fitBar = fitAura
        makeShield(h)
        auras[id] = h
        DUI.SafeCall(CD.SkinItem, h)
        -- The bar's border frame belongs with the rest of our empty bar.
        local p = CD.Parts(h)
        if p and p.slot then
            p.slot:SetParent(h.under)
            p.slot:SetFrameLevel(math.max(0, h.Bar:GetFrameLevel() - 1))
        end
        if ns.CdmAuras then
            DUI.SafeCall(ns.CdmAuras.Setup, h, id)
            ns.CdmAuras.Track(h)
        end
    elseif h:GetParent() ~= parent then
        h:SetParent(parent)
    end
    h.over:SetFrameLevel(h:GetFrameLevel() + 8)
    fill(h, id)
    h.isShield = B.IsShield(id)
    setUnder(h, under)
    -- Applied together with the button's layout (fitAura) so both change at once.
    h.wantBare = not (always == true or under)
    -- The client's bar above our empty one (its frames sit a level under h.under's).
    local level = h.Bar:GetFrameLevel() + 2
    for _, k in ipairs(h.containers or {}) do
        if k.c:GetFrameLevel() < level then pcall(k.c.SetFrameLevel, k.c, level) end
        pcall(k.c.SetEnabled, k.c, true)
    end
    h:SetAlpha(1)
    h:Show()
    if under then B.UpdateCooldown(h) end
    return h
end

-- Hides every bar not in used ({ [frame] = true }).
function B.ReleaseExcept(used)
    local Fx = ns.CdmEffects
    for _, list in ipairs({ cooldowns, auras }) do
        for _, f in pairs(list) do
            if not used[f] and f:IsShown() then
                if Fx then Fx.Clear(f); Fx.Flash(f, f.Bar, false) end
                f:Hide()
                for _, k in ipairs(f.containers or {}) do pcall(k.c.SetEnabled, k.c, false) end
            end
        end
    end
end

function B.CooldownFrame(id) return cooldowns[id] end
function B.AuraFrame(id) return auras[id] end
