-- Per-spell effects on the Cooldown Manager items we place (CdmRows): proc glow,
-- per-icon size, no cooldown swipe, and what happens on cooldown (gray, fade, hide,
-- ready glow). Options live in DB.Character().cdm.sets[g].buttons[id]; a missing
-- key means the default. Fx.Clear undoes everything when an item is released.
-- Textures sit on the item the same way the skin's do, and bookkeeping is in weak
-- tables.

local _, ns = ...
local DUI = DaylightUI

local Fx = {}
ns.CdmEffects = Fx

-- Option keys, beyond the defaults below:
-- glowColor (proc) and readyGlowColor: nil = the accent.
-- Icons only: noDurationSwipe = no swipe while the buff is up (game items: same as
-- activeGlow false; our aura holders: CdmAuras.SetSwipe). activeGlow false hides
-- the game's swipe while the buff is up (the timer stays). activeColor {r,g,b,a}
-- recolors it, nil = the accent (Fx.ActiveColor).
-- Bars only: barMode "block" | "solid" | "gradient" (barColor {r,g,b}, barGradient
-- {lo,hi}), backMode "block" | "solid" | "gradient" (backColor {r,g,b,a},
-- backGradient {lo,hi}); nil colors follow the block's look. showName, nameAlign
-- "left" | "center". fillBy "shield" | "time": a shield spell's bar fills by the
-- shield left (CdmBars.IsShield). shieldAmount shows the amount left on it.
-- inactiveFlash: the empty bar ("Show missing buffs") pulses while the buff is down.
-- missing: "Show when missing", the spell keeps its spot (grayed icon, empty bar)
-- while its buff is down. missingGlow (missingGlowColor) makes it glow then.
-- upGlow (upGlowColor): glows while its buff is up. WoW Forever fires no proc
-- alerts, so for something like Clearcasting the buff landing is the proc.
-- hideActive: hidden while its buff is up (by alpha, so the gap stays).
-- hideMissing: shown only while its buff is up (CdmOwn.Track says "buff" and
-- missing is ignored; a shield bar hides with no shield, see CdmBars).
-- onCd / onReady: "show" | "fade" (to cdAlpha) | "hide", on cooldown / when ready
-- (the global cooldown counts as ready). onUnusable: the same for ready but not
-- castable per the game (being short of power alone still counts as castable).
-- onShort: the same for ready but short of power (Kick without the energy). A secret
-- answer changes nothing.
-- readySound / usableSound / buffSound / buffEndSound: a Sound.Alert key, "none" =
-- silent. Played when the spell comes ready, turns usable, or its buff lands or
-- ends (see Sounds).
Fx.DEFAULTS = { readySound = "none", usableSound = "none", buffSound = "none", buffEndSound = "none",
    glow = true, size = 0, noSwipe = false, noGcd = false, reverse = false, desat = "game",
    onCd = "show", onReady = "show", onUnusable = "show", onShort = "show", cdAlpha = 0.4, readyGlow = false, usableGlow = false, activeGlow = true, noDurationSwipe = false,
    barMode = "block", backMode = "block", showName = true, nameAlign = "left", fillBy = "shield",
    shieldAmount = true, inactiveFlash = false, missing = false, missingGlow = false, upGlow = false, hideActive = false, hideMissing = false, chargeLines = true }

-- Show in: each form, stance or stealth of the class the spell can be left out of
-- (e.g. cat spells only in Cat Form), saved as hideIn<Key> (false = shown). In a
-- form it's left out of, it hides the way Hide does, and its spot closes up with the
-- group's Slide over. spells = the form's spell ids (every rank; Bear and Dire Bear
-- count as one). none = no form (caster, out of stealth).
Fx.FORMS = {
    DRUID = { { key = "Caster", name = "No form", none = true },
              { key = "Bear", name = "Bear Form", spells = { 5487, 9634 } },
              { key = "Cat", name = "Cat Form", spells = { 768 } },
              { key = "Aquatic", name = "Aquatic Form", spells = { 1066 } },
              { key = "Travel", name = "Travel Form", spells = { 783 } },
              { key = "Moonkin", name = "Moonkin Form", spells = { 24858 } } },
    WARRIOR = { { key = "Battle", name = "Battle Stance", spells = { 2457 } },
                { key = "Defensive", name = "Defensive Stance", spells = { 71 } },
                { key = "Berserker", name = "Berserker Stance", spells = { 2458 } } },
    ROGUE = { { key = "Unstealthed", name = "Out of Stealth", none = true },
              { key = "Stealth", name = "Stealth", spells = { 1784, 1785, 1786, 1787 }, stealth = true } },
}
Fx.FORM_KEYS = {}
local formBySpell = {}
for _, list in pairs(Fx.FORMS) do
    for _, f in ipairs(list) do
        Fx.FORM_KEYS[#Fx.FORM_KEYS + 1] = f.key
        for _, sid in ipairs(f.spells or {}) do formBySpell[sid] = f.key end
    end
end
-- Each is a spell option, shown by default and only saved when turned off.
for _, k in ipairs(Fx.FORM_KEYS) do
    Fx.DEFAULTS["hideIn" .. k] = false
    if ns.CdmData then ns.CdmData.SPELL_FIELDS["hideIn" .. k] = { bool = true } end
end

local function plainOf(v) return not (issecretvalue and issecretvalue(v)) and v or nil end

-- The class's forms (nil when there are none to pick).
function Fx.FormsOf(class)
    if class == nil then
        local ok, _, token = pcall(UnitClass, "player")
        class = ok and plainOf(token) or nil
    end
    return class and Fx.FORMS[class] or nil
end

-- The form you're in now, by key. nil when it can't be told, in which case nothing
-- hides by form.
function Fx.ReadForm()
    local list = Fx.FormsOf()
    if not list then return nil end
    local n = type(GetNumShapeshiftForms) == "function" and plainOf(GetNumShapeshiftForms()) or 0
    for i = 1, type(n) == "number" and n or 0 do
        local ok, _, active, _, sid = pcall(GetShapeshiftFormInfo, i)
        if ok and plainOf(active) == true and type(plainOf(sid)) == "number" and formBySpell[sid] then
            return formBySpell[sid]
        end
    end
    local stealthed = type(IsStealthed) == "function" and plainOf(IsStealthed()) or nil
    for _, f in ipairs(list) do
        if f.stealth and stealthed == true then return f.key end
    end
    for _, f in ipairs(list) do
        if f.none then return f.key end
    end
    return nil
end

local formNow = nil
function Fx.FormNow() return formNow end

-- Left out of the current form (its hideIn<Key> option).
local function offForm(b)
    return formNow ~= nil and Fx.Get(b, "hideIn" .. formNow) == true
end

local weak = { __mode = "k" }
local opts = setmetatable({}, weak)        -- item -> its button table (claimed items only)
local kinds = setmetatable({}, weak)       -- item -> "icon" | "bar"
local alerts = setmetatable({}, weak)      -- item -> true while the game's spell alert is up
local usable = setmetatable({}, weak)      -- item -> the game's last plain "castable now" answer
local castable = setmetatable({}, weak)    -- item -> castable or only short of power; nil = the game won't say
local short = setmetatable({}, weak)       -- item -> true while only short of power
local dimAs = setmetatable({}, weak)       -- icon texture -> "no" | "power" while dimmed
local dimNow = setmetatable({}, weak)      -- our own icon texture -> the color it shows or eases from
local alphaNow = setmetatable({}, weak)    -- our own item -> the alpha it shows or eases to
local glows = setmetatable({}, weak)       -- item -> its glow frame
local lit = setmetatable({}, weak)         -- item -> true while its glow shows
local noSwipe = setmetatable({}, weak)     -- item -> "all" | "gcd": swipe kept off always, or on the GCD
local buffOnly = setmetatable({}, weak)   -- item -> true when set to Buff only, so its cooldown changes nothing
local reversed = setmetatable({}, weak)    -- item -> true while its swipe is kept reversed
local swipeHooked = setmetatable({}, weak) -- cooldown frame -> true
local cdState = setmetatable({}, weak)     -- item -> true on cooldown, false ready (last known)
local cdFresh = setmetatable({}, weak)     -- item -> true when cdState was read this time (not secret)
local greyHooked = setmetatable({}, weak)  -- icon texture -> true
local greyed = setmetatable({}, weak)      -- item -> true while its gray is ours
local greyAs = setmetatable({}, weak)      -- icon texture -> the gray last set on it
local faded = setmetatable({}, weak)       -- item -> true while its alpha is held below 1
local doneHooked = setmetatable({}, weak)  -- cooldown frame -> true
local mouseOff = setmetatable({}, weak)    -- item -> true while its mouse is kept off
local tinted = setmetatable({}, weak)      -- item -> true while its swipe color is held
local tintHooked = setmetatable({}, weak)  -- cooldown frame -> true
local away = setmetatable({}, weak)        -- item -> true while its "Hide out of combat" block is away
local down = setmetatable({}, weak)        -- item -> true: buff down, false: up (from CdmRows; nil = can't tell)
local own = setmetatable({}, weak)         -- item -> true for our own icons and bars (CdmOwn, CdmBars)
local refreshNow                          -- refresh without reading (set below)
local guard = false                        -- set during our own calls so our hooks skip them

function Fx.Get(button, key)
    local v
    if type(button) == "table" then v = button[key] end
    if v == nil then v = Fx.DEFAULTS[key] end
    return v
end

-- The saved button table of a claimed item (nil when not ours).
function Fx.ButtonOf(item) return opts[item] end

-- Glow -----------------------------------------------------------------
-- The game's own proc glow (the looping spell alert ring every player knows) on a
-- frame of ours, recolored to the option's color or the accent (a gradient accent
-- runs across it). Three hand-made glows were tried first and read as a border, a
-- blob and a slab; it has to glow and move. The game's alert manager is never
-- touched. It fades in fast (fight info never waits) and out gently. With motion
-- off the fades snap, but the ring itself always turns: a stopped flipbook shows
-- its whole sheet.

local Motion = DUI.Motion

-- From ActionButtonSpellAlerts.xml: the loop's atlas and flipbook, 1.4 times the
-- button size (ActionButtonSpellAlerts.lua).
Fx.GLOW_ATLAS = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
Fx.GLOW_ROWS, Fx.GLOW_COLUMNS, Fx.GLOW_FRAMES = 6, 5, 30
Fx.GLOW_LOOP = 1          -- seconds per turn
Fx.GLOW_PAD = 0.2         -- how far it reaches past each edge, as a share of the item's short side

local function glowOf(item)
    local g = glows[item]
    if g then return g end
    g = CreateFrame("Frame", nil, item)
    g:SetFrameLevel(item:GetFrameLevel() + 6)
    g.a = 0
    local t = g:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints(g)
    t:SetAtlas(Fx.GLOW_ATLAS)
    -- The game's art is gold; desaturate it so our color tints true.
    t:SetDesaturated(true)
    g.tex = t
    local ag = g:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local fb = ag:CreateAnimation("FlipBook")
    fb:SetTarget(t)
    fb:SetDuration(Fx.GLOW_LOOP)
    fb:SetFlipBookRows(Fx.GLOW_ROWS)
    fb:SetFlipBookColumns(Fx.GLOW_COLUMNS)
    fb:SetFlipBookFrames(Fx.GLOW_FRAMES)
    fb:SetFlipBookFrameWidth(0)
    fb:SetFlipBookFrameHeight(0)
    g.anim = ag
    g:SetAlpha(0)
    g:Hide()
    glows[item] = g
    return g
end

-- Around the item, reaching past each edge by the same amount (bars too).
local function sizeGlow(g, item)
    local w, h = item:GetWidth(), item:GetHeight()
    if type(w) ~= "number" or w <= 0 then w = 36 end
    if type(h) ~= "number" or h <= 0 then h = w end
    g.w, g.h = w, h
    local pad = math.min(w, h) * Fx.GLOW_PAD
    g:ClearAllPoints()
    g:SetPoint("TOPLEFT", item, "TOPLEFT", -pad, pad)
    g:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", pad, -pad)
end

-- c = {r,g,b}, or nil for the accent (a gradient accent runs across the ring).
local function paintGlow(g, c)
    local t = g.tex
    if type(c) == "table" then
        t:SetVertexColor(c[1], c[2], c[3], 1)
        return
    end
    local lo, hi = DUI.Style.AccentPair()
    if lo and CreateColor then
        t:SetVertexColor(1, 1, 1, 1)
        t:SetGradient("HORIZONTAL", CreateColor(lo[1], lo[2], lo[3], 1), CreateColor(hi[1], hi[2], hi[3], 1))
    else
        t:SetVertexColor(DUI.Style.Accent())
    end
end

local glowing = setmetatable({}, weak)   -- item -> true while its glow fades in or out
local driver = CreateFrame("Frame")
Fx.glowDriver = driver
local function smooth(v) return v * v * (3 - 2 * v) end
local function fade(_, dt)
    local moving = Motion.On()
    local any = false
    for item in pairs(glowing) do
        local g = glows[item]
        local goal = lit[item] and 1 or 0
        if not moving then
            g.a = goal
        elseif g.a < goal then
            g.a = math.min(goal, g.a + dt / Motion.FAST)
        elseif g.a > goal then
            g.a = math.max(goal, g.a - dt / Motion.NORMAL)
        end
        g:SetAlpha(smooth(g.a))
        if g.a == goal then
            glowing[item] = nil
            if goal == 0 then
                g.anim:Stop()
                g:Hide()
            end
        else
            any = true
        end
        -- Resized while lit (an icon's own size, the editor), so follow it.
        if goal == 1 and (item:GetWidth() ~= g.w or item:GetHeight() ~= g.h) then sizeGlow(g, item) end
    end
    if not any then driver:SetScript("OnUpdate", nil) end
end

-- What a lit glow was painted with (plain numbers, or "accent"), so a refresh that
-- changes nothing (every cooldown event) doesn't repaint.
local litAs = setmetatable({}, weak)
local accentGen = 0          -- bumped on a style change, since the accent may differ
DUI.On("StyleChanged", function() accentGen = accentGen + 1 end)

local function lightGlow(item, c)
    local was = litAs[item]
    if lit[item] and was then
        if type(c) == "table" then
            if was[1] == c[1] and was[2] == c[2] and was[3] == c[3] then return end
        elseif was.accent == accentGen then
            return
        end
    end
    local g = glowOf(item)
    sizeGlow(g, item)
    paintGlow(g, type(c) == "table" and c or nil)
    if not g:IsShown() then
        g:Show()
        g.anim:Play()
    end
    if type(c) == "table" then
        litAs[item] = { c[1], c[2], c[3] }
    else
        litAs[item] = { accent = accentGen }
    end
    lit[item] = true
    glowing[item] = true
    driver:SetScript("OnUpdate", fade)
end

local function showGlow(item, on, button)
    if not on then
        if not lit[item] then return end
        lit[item], litAs[item] = nil, nil
        glowing[item] = true
        driver:SetScript("OnUpdate", fade)
        return
    end
    lightGlow(item, Fx.Get(button or opts[item], on))
end

-- The same glow on anything else (an action button's queued spell, Skin.lua).
-- c = {r,g,b}, or nil for the accent.
function Fx.SetGlow(item, on, c)
    if on then lightGlow(item, c) else showGlow(item, false) end
end

-- The glow's frame (for tests).
function Fx.GlowFrame(item) return glows[item] end

-- Flash: an empty placeholder bar (CdmOwn) pulses inside while the buff is down.
-- The holder's own alpha stays free for "Hide out of combat".
local flashing = setmetatable({}, weak)   -- holder -> the part that pulses
local flashDriver = CreateFrame("Frame")
Fx.flashDriver = flashDriver
local flashClock = 0
local function flashPulse(_, dt)
    flashClock = flashClock + dt
    local a = 0.6 + 0.4 * math.sin(flashClock * 6)
    local any = false
    for holder, part in pairs(flashing) do
        if holder:IsShown() then
            any = true
            part:SetAlpha(a)
        else
            flashing[holder] = nil
            part:SetAlpha(1)
        end
    end
    if not any then flashDriver:SetScript("OnUpdate", nil) end
end

function Fx.Flash(holder, part, on)
    if on then
        flashing[holder] = part
        flashDriver:SetScript("OnUpdate", flashPulse)
    elseif flashing[holder] then
        flashing[holder] = nil
        part:SetAlpha(1)
    end
end

function Fx.Flashing(holder) return flashing[holder] ~= nil end

-- Hide (Buff missing) shows nothing while the buff is down, so nothing glows.
local function missingGlows(b)
    return Fx.Get(b, "missingGlow") == true and Fx.Get(b, "hideMissing") ~= true
end
-- Hide (Buff up) shows nothing while the buff is up, so nothing glows.
local function upGlows(b)
    return Fx.Get(b, "upGlow") == true and Fx.Get(b, "hideActive") ~= true
end
-- The glow asked for by the buff being down (true) or up (false).
local function buffGlow(b, isDown)
    if isDown == true and missingGlows(b) then return "missingGlowColor" end
    if isDown == false and upGlows(b) then return "upGlowColor" end
    return false
end
Fx.UpGlows = upGlows

-- Reads only our own bookkeeping, never the game's values. Returns the color key of
-- the glow that should show (proc first, then usable, then ready), or false.
local function wantsGlow(item)
    local b = opts[item]
    if Fx.Get(b, "glow") ~= false and alerts[item] == true then return "glowColor" end
    local buff = buffGlow(b, down[item])
    if buff then return buff end
    -- Usable: Revenge after a block, Overpower after a dodge, Execute under 20%.
    -- WoW Forever fires no spell alerts, so this stands in for the proc.
    if Fx.Get(b, "usableGlow") == true and usable[item] == true and cdState[item] ~= true then
        return "usableGlowColor"
    end
    if Fx.Get(b, "readyGlow") == true and cdState[item] == false and cdFresh[item] == true then
        return "readyGlowColor"
    end
    return false
end

function Fx.GlowShown(item) return lit[item] == true end

-- Moments --------------------------------------------------------------
-- Coming ready: a light sweeps once across the item (a band in a clipping frame,
-- like the bags' loot glint). Going on cooldown: the icon dips and springs back like
-- a pressed button. The dip resizes the item, so the game's items only dip out of
-- combat (nothing of the game's animates in a fight); our own icons always do.
-- With motion off, neither happens.

Fx.SWEEP_DUR = 0.45
Fx.SWEEP_ALPHA = 0.5
Fx.SWEEP_WIDTH = 0.6          -- band width, as a share of the item's short side
Fx.SWEEP_TILT = -math.pi / 6  -- leans like /
Fx.DIP = 0.9                  -- icon scale at the bottom of the dip

local shines = setmetatable({}, weak)   -- item -> { clip, band, [1], [2] }
local function shineOf(item)
    local p = shines[item]
    if p then return p end
    p = {}
    p.clip = CreateFrame("Frame", nil, item)
    p.clip:SetAllPoints(item)
    p.clip:SetClipsChildren(true)
    p.clip:SetFrameLevel(item:GetFrameLevel() + 5)
    p.band = CreateFrame("Frame", nil, p.clip)
    p.band:Hide()
    for i = 1, 2 do
        local t = p.band:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        t:SetBlendMode("ADD")
        t:SetRotation(Fx.SWEEP_TILT)
        p[i] = t
    end
    shines[item] = p
    return p
end

function Fx.Sweep(item)
    if not Motion.On() then return end
    local p = shineOf(item)
    local w, h = item:GetWidth() or 0, item:GetHeight() or 0
    local s = math.min(w, h)
    if s <= 0 then return end
    local bw = s * Fx.SWEEP_WIDTH
    local q = bw / 4
    local cx, cy = q * math.cos(Fx.SWEEP_TILT), q * math.sin(Fx.SWEEP_TILT)
    -- Each half fades out from the middle, in the accent.
    local r, g, b = DUI.Style.Accent()
    for i = 1, 2 do
        local t = p[i]
        t:SetSize(bw / 2, h * 2)
        t:ClearAllPoints()
        t:SetPoint("CENTER", p.band, "CENTER", (i == 1 and -cx or cx), (i == 1 and -cy or cy))
        if CreateColor then
            local clear, full = CreateColor(r, g, b, 0), CreateColor(r, g, b, 1)
            t:SetGradient("HORIZONTAL", i == 1 and clear or full, i == 1 and full or clear)
        end
    end
    p.band:SetHeight(h * 2)
    Motion.Sweep(p.band, p.clip, { width = bw, dur = Fx.SWEEP_DUR, alpha = Fx.SWEEP_ALPHA, inset = -bw })
end

local dips = setmetatable({}, weak)   -- item -> its resting size while it dips
function Fx.Dip(item)
    if kinds[item] ~= "icon" or not Motion.On() then return end
    if not own[item] and InCombatLockdown() then return end
    local rest = dips[item]
    if not rest then
        local w, h = item:GetWidth(), item:GetHeight()
        if type(w) ~= "number" or w <= 0 then return end
        rest = { w, h }
        dips[item] = rest
    end
    Motion.Tween(rest, 0, 1, Motion.NORMAL, function(p)
        local k = 1 - (1 - Fx.DIP) * math.sin(math.pi * p)
        item:SetSize(rest[1] * k, rest[2] * k)
    end, function()
        dips[item] = nil
        item:SetSize(rest[1], rest[2])
    end)
end

-- A buff landing on our aura icons and bars (CdmAuras, CdmBars) slides in like the
-- buff bar's (Buffs Feel.lua). It's an animation group handed to the client in
-- initializeFrame and played as the button comes up for a new aura, in fights too.
-- Translation and alpha only. The button locks once initializeFrame returns, so
-- retuning it (motion toggled) waits for the holders' after-restrictions layout.
-- Over our own cooldown icon ("Cooldown and buff", CdmAuras.Over) it only fades in
-- place: the same spell's icon is already there, so a drop looked like the icon
-- jumping (Shield Block).
Fx.SLIDE = 6   -- px it drops in from

function Fx.MakeSlide(btn, h)
    -- No OnShow/OnHide on a frame of ours inside the button: the client refuses them
    -- there ("blocked by secret aspects").
    if type(btn.AddAuraShownAnimation) ~= "function" then return end
    local ag = btn:CreateAnimationGroup()
    -- Set here while the button can still be written to; it runs in fights.
    if h then ag:SetScript("OnPlay", function() DUI.SafeCall(Fx.AuraShown, h) end) end
    local s = {}
    s.up = ag:CreateAnimation("Translation")
    s.up:SetOrder(1); s.up:SetDuration(0)
    s.hide = ag:CreateAnimation("Alpha")
    s.hide:SetOrder(1); s.hide:SetDuration(0)
    s.down = ag:CreateAnimation("Translation")
    s.down:SetOrder(2); s.down:SetSmoothing("OUT")
    s.show = ag:CreateAnimation("Alpha")
    s.show:SetOrder(2); s.show:SetSmoothing("OUT"); s.show:SetToAlpha(1)
    btn.cdmSlide, btn.cdmSlideHolder = s, h
    Fx.TuneSlide(btn)
    pcall(btn.AddAuraShownAnimation, btn, ag)
    if h then
        -- The buff going away. The client stops a button's shown animations
        -- whenever its aura clears (ApplyVisibility, Blizzard_CustomAuraButton.lua),
        -- in fights and dungeons too, where auras can't be read. A loop with no
        -- movement plays as long as the aura is up, so its OnStop is the signal
        -- (CdmAuras.Hidden). Not yet confirmed in game.
        local sig = btn:CreateAnimationGroup()
        sig:SetLooping("REPEAT")
        local hold = sig:CreateAnimation("Translation")
        hold:SetOffset(0, 0); hold:SetDuration(1)
        sig:SetScript("OnStop", function() DUI.SafeCall(Fx.AuraHeard, h, "stop") end)
        -- Only logged in the report: whether the client ends the loop this way
        -- instead when it hides the button.
        sig:SetScript("OnFinished", function() DUI.SafeCall(Fx.AuraHeard, h, "finish") end)
        sig:SetScript("OnPause", function() DUI.SafeCall(Fx.AuraHeard, h, "pause") end)
        pcall(btn.AddAuraShownAnimation, btn, sig)
    end
end

-- What the buff's button reported: "play" = up; "stop" (shown animations stopped),
-- "time out" (countdown ended) and "blocked" (your blocks used up its charges,
-- CdmAuras) = down. "finish" and "pause" only go in the report. The last few are
-- kept for /dui cdm report, to see which ones the client really sends in a fight
-- or a dungeon.
local DOWN = { stop = true, ["time out"] = true, blocked = true }
function Fx.AuraHeard(h, what)
    h.heard = h.heard or {}
    table.insert(h.heard, string.format("%s %.1f%s", what, GetTime(), InCombatLockdown() and " fight" or ""))
    if #h.heard > 8 then table.remove(h.heard, 1) end
    local A = ns.CdmAuras
    if not A then return end
    if what == "play" then A.Shown(h) elseif DOWN[what] then A.Hidden(h) end
end

local function tune(s, on, drop)
    local d = on and drop and Fx.SLIDE or 0
    s.up:SetOffset(0, d)
    s.down:SetOffset(0, -d)
    s.down:SetDuration(on and Motion.NORMAL or 0)
    s.show:SetDuration(on and Motion.NORMAL or 0)
    s.hide:SetFromAlpha(on and 0 or 1); s.hide:SetToAlpha(on and 0 or 1)
    s.show:SetFromAlpha(on and 0 or 1)
end

-- A locked button (in a fight, under restrictions) refuses; retried next layout.
function Fx.TuneSlide(btn)
    local s = btn.cdmSlide
    if not s then return end
    local on = Motion.On()
    local h = btn.cdmSlideHolder
    local drop = not (type(h) == "table" and h.overIcon == true)
    local key = on and (drop and "slide" or "fade") or false
    if btn.cdmSlideKey == key then return end
    if pcall(tune, s, on, drop) then btn.cdmSlideOn, btn.cdmSlideKey = on, key end
end

-- Sounds ---------------------------------------------------------------
-- Like a proc addon: a per-spell sound the moment it matters. Each fires on the
-- change, never while the state holds, and a piece sounds at most once per
-- SOUND_GAP however many moments land together (ready and usable are one moment on
-- most spells, and a buff can be reported by two paths). A chain that's hidden (its
-- show rules, the editor) stays quiet along with its icons.
Fx.SOUND_GAP = 0.5
Fx.ARM_MIN = 2           -- seconds; a cast's OnCooldownDone sooner than this was only the GCD
Fx.SETTLE = 2            -- seconds after entering the world; buffs already up aren't news
Fx.AURA_QUIET = 0.3      -- seconds after a new target or container; its buttons coming up aren't news
Fx.END_QUIET = 0.5       -- seconds after a new target; its debuffs leaving view didn't end

local heard = setmetatable({}, weak)      -- piece -> when it last sounded
local wasUsable = setmetatable({}, weak)  -- item -> last plain usable answer
local wasDown = setmetatable({}, weak)    -- piece -> its buff's last plain down answer
local realCool = setmetatable({}, weak)   -- item -> true when this cooldown is real (not a wand shot's)
local armed = setmetatable({}, weak)      -- item -> when you cast it while its cooldown was unreadable
local castAt = setmetatable({}, weak)     -- item -> when you last cast its spell (one with a cooldown)
local enteredAt, targetAt = GetTime(), 0

local function playSound(item, button, key)
    local s = Fx.Get(button, key)
    if s == "none" or type(button) ~= "table" or away[item] then return end
    local now = GetTime()
    if heard[button] and now - heard[button] < Fx.SOUND_GAP then return end
    heard[button] = now
    DUI.Sound.Alert(s)
end

-- Called by CdmRows each pass for every piece whose buff state it can tell.
function Fx.BuffMoment(piece, item, isDown)
    if type(isDown) ~= "boolean" then return end
    local was = wasDown[piece]
    wasDown[piece] = isDown
    if was == true and not isDown then playSound(item, piece, "buffSound")
    elseif was == false and isDown then
        -- Really ended, not a new target's debuffs leaving view or a zone change
        -- or death clearing them all.
        local now = GetTime()
        if now - targetAt < Fx.END_QUIET or now - enteredAt < Fx.SETTLE then return end
        local ok, dead = pcall(UnitIsDeadOrGhost, "player")
        if ok and dead == true then return end
        playSound(item, piece, "buffEndSound")
    end
end

-- The client's aura button came up for a new aura (the slide's OnPlay). In a fight
-- that's the only signal of a proc when no game item shows that buff.
function Fx.AuraShown(h)
    -- A buff that slid out of its group comes back (CdmRows).
    Fx.AuraHeard(h, "play")
    local p = h.soundPiece
    if not p or not h:IsShown() then return end
    local now = GetTime()
    if now - enteredAt < Fx.SETTLE or now - targetAt < Fx.AURA_QUIET
        or now - (h.builtAt or 0) < Fx.AURA_QUIET then return end
    playSound(h.soundItem or h, p, "buffSound")
end

DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function() enteredAt = GetTime() end)
DUI.RegisterEvent("PLAYER_TARGET_CHANGED", function() targetAt = GetTime() end)

-- cdState changed from was to now (both plain): ready or on cooldown. quiet = the
-- light still runs but the sound waits (an aura's time ended over a cooldown that's
-- still going).
local function moment(item, was, now, quiet)
    if was == true and now == false then
        Fx.Sweep(item)
        if realCool[item] and not quiet then
            realCool[item], armed[item] = nil, nil
            playSound(item, opts[item], "readySound")
        end
    elseif was == false and now == true then
        Fx.Dip(item)
    end
end

-- Swipe ----------------------------------------------------------------

local function setSwipe(cd, on)
    guard = true
    pcall(cd.SetDrawSwipe, cd, on)
    guard = false
end

-- Only the global cooldown is running for the item's spell (plain answer). A secret
-- or unknown answer counts as no, so the swipe shows.
local function onGcd(item)
    -- An item added by ID: its cooldown read already excludes the global one.
    if ns.CdmCustom and ns.CdmCustom.ItemOf(item.cooldownID) then return false end
    local sid = Fx.SpellOf(item)
    if not sid or type(C_Spell) ~= "table" or type(C_Spell.GetSpellCooldown) ~= "function" then return false end
    local ok, info = pcall(C_Spell.GetSpellCooldown, sid)
    local gcd = ok and type(info) == "table" and info.isOnGCD
    if issecretvalue and issecretvalue(gcd) then return false end
    return gcd == true
end

-- Applies our swipe rule to the item's cooldown: always off, or off while only the
-- global cooldown runs.
local function applySwipe(item, cd)
    local rule = noSwipe[item]
    if not rule then return end
    setSwipe(cd, not (rule == "all" or onGcd(item)))
end

-- The game sets the swipe and cooldown again as it updates (our own icons set the
-- cooldown), so ours is reapplied after.
local function hookSwipe(item, cd)
    if swipeHooked[cd] then return end
    swipeHooked[cd] = true
    local function after(self) if not guard and noSwipe[item] then applySwipe(item, self) end end
    for _, m in ipairs({ "SetDrawSwipe", "SetCooldown", "SetCooldownFromDurationObject" }) do
        if type(cd[m]) == "function" then hooksecurefunc(cd, m, after) end
    end
end

-- Active swipe ---------------------------------------------------------
-- While the spell's buff is up the game paints the swipe yellow and counts the buff
-- down. We only recolor that swipe (alpha 0 = timer only). Unset, it takes the
-- accent like the glows, at the game's own opacity.

local ACTIVE_ALPHA = 0.7

-- A piece's buff swipe color: its own, else the accent (read at paint time).
function Fx.ActiveColor(b)
    local c = b and Fx.Get(b, "activeColor")
    if type(c) == "table" then return c end
    local r, g, bl = DUI.Style.Accent()
    return { r, g, bl, ACTIVE_ALPHA }
end

local function setTint(cd, c)
    guard = true
    pcall(cd.SetSwipeColor, cd, c[1], c[2], c[3], c[4] or 1)
    guard = false
end

local function fromAura(item)
    local v = item.wasSetFromAura
    return type(v) == "boolean" and not (issecretvalue and issecretvalue(v)) and v
end

local function applyTint(item)
    local cd = item.Cooldown
    if type(cd) ~= "table" or type(cd.SetSwipeColor) ~= "function" then return end
    local b = opts[item]
    local want
    if b and kinds[item] == "icon" and fromAura(item) then
        if Fx.Get(b, "activeGlow") == false or Fx.Get(b, "noDurationSwipe") == true then
            want = { 0, 0, 0, 0 }
        else
            want = Fx.ActiveColor(b)
        end
    end
    if want then
        tinted[item] = true
        setTint(cd, want)
    elseif tinted[item] then
        -- The buff is gone (or the item left our blocks): back to the cooldown shade.
        tinted[item] = nil
        setTint(cd, ns.Skin.SWIPE)
    end
end

-- The game sets the swipe color and cooldown as it updates, so ours goes on after.
local function hookTint(item, cd)
    if tintHooked[cd] then return end
    tintHooked[cd] = true
    local function after() if not guard and opts[item] then applyTint(item) end end
    for _, m in ipairs({ "SetSwipeColor", "SetCooldown", "SetCooldownFromDurationObject" }) do
        if type(cd[m]) == "function" then hooksecurefunc(cd, m, after) end
    end
end

-- Cooldown -------------------------------------------------------------

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

local function clean(v)
    if type(v) == "nil" or secret(v) then return nil end
    return v
end

-- The spell behind an item, override first. nil when unknown or secret.
function Fx.SpellOf(item)
    local info = item.cooldownInfo
    if type(info) == "table" then
        local id = clean(info.overrideSpellID) or clean(info.spellID)
        if type(id) == "number" then return id end
    end
    if type(item.GetSpellID) == "function" then
        local ok, id = pcall(item.GetSpellID, item)
        if ok then id = clean(id) else id = nil end
        if type(id) == "number" then return id end
    end
end

-- A game icon whose cooldown frame also counts its buff's time.
local function auraItem(item)
    local info = item.cooldownInfo
    return not own[item] and type(info) == "table" and clean(info.hasAura) == true
end

-- You cast the item's spell since the last wand shot, so its cooldown is real.
local function castSinceShot(item)
    local at, shot = castAt[item], ns.Ping and ns.Ping.shotAt
    return at ~= nil and shot ~= nil and at >= shot
end

-- The item's cooldown can't be told apart from a wand shot's lockout right now.
local function blindShot(item)
    local sid = Fx.SpellOf(item)
    if not sid or not ns.Ping or type(C_Spell) ~= "table" or type(C_Spell.GetSpellCooldown) ~= "function" then return false end
    local ok, info = pcall(C_Spell.GetSpellCooldown, sid)
    return ok and ns.Ping.ShotBlind(info)
end

-- On cooldown, not just the global cooldown? nil when the game won't say.
-- ending = asked as the item's cooldown frame ran out.
function Fx.OnCooldown(item, ending)
    local C = ns.CdmCustom
    if C and C.ItemOf(item.cooldownID) then return (C.ItemCooldown(item.cooldownID)) end
    local sid = Fx.SpellOf(item)
    if not sid or type(C_Spell) ~= "table" then return nil end
    if type(C_Spell.GetSpellCharges) == "function" then
        local ok, ch = pcall(C_Spell.GetSpellCharges, sid)
        if ok and type(ch) == "table" then
            local cur, mx = ch.currentCharges, ch.maxCharges
            if secret(cur) or secret(mx) then return nil end
            if type(cur) == "number" and type(mx) == "number" and mx > 1 then return cur == 0 end
        end
    end
    if type(C_Spell.GetSpellCooldown) ~= "function" then return nil end
    local ok, info = pcall(C_Spell.GetSpellCooldown, sid)
    if not ok or type(info) ~= "table" then return nil end
    local d, gcd, active = info.duration, info.isOnGCD, info.isActive
    if secret(gcd) then gcd = nil end
    if gcd == true then return false end
    -- A wand shot's lockout isn't flagged as the GCD but acts like one (Ping.Shot).
    if ns.Ping and ns.Ping.IsShotCooldown(info) then return false end
    -- In a fight the start and duration are secret, so the lockout can't be seen.
    -- It's on cooldown only if it was before the shot or you cast it since, and its
    -- frame running out marks that cooldown's end. A game icon with an aura counts
    -- the aura there too, so there's no telling.
    if active == true and not secret(active) and ns.Ping and ns.Ping.ShotBlind(info) then
        if ending and not auraItem(item) then return false end
        return cdState[item] == true or castSinceShot(item)
    end
    if type(active) == "boolean" and not secret(active) then return active end
    if secret(d) or type(d) ~= "number" then return nil end
    return d > 0
end

-- When the game won't say (secret in combat), fade and gray keep the last state,
-- and the ready glow turns off rather than stay on a spell that's on cooldown.
-- readAlert: the game's spell alert (its proc) on this item, asked of its alert
-- manager. Never hooked: the game calls HideAlert from its action buttons'
-- protected code, and with a hook on it every call failed ("attempt to call a nil
-- value").
local function readAlert(item)
    local m = _G.ActionButtonSpellAlertManager
    if type(m) ~= "table" or type(m.HasAlert) ~= "function" then return end
    local ok, up = pcall(m.HasAlert, m, item)
    alerts[item] = (ok and up == true) or nil
end

-- Castable now, per the game (plain in combat too). A secret or missing answer
-- keeps the last one, so "When not usable" never hides or darkens a spell when
-- it's needed.
local function readUsable(item)
    local b = opts[item]
    local glow = Fx.Get(b, "usableGlow") == true
    if not glow then usable[item] = nil end
    castable[item], short[item] = nil, nil
    if not (glow or kinds[item] == "icon" or Fx.Get(b, "onUnusable") ~= "show"
        or Fx.Get(b, "onShort") ~= "show" or Fx.Get(b, "usableSound") ~= "none") then return end
    local ok, can, noPower
    local C = ns.CdmCustom
    if C and C.ItemOf(item.cooldownID) then   -- an item with none left in your bags reads not usable
        ok = true
        can, noPower = C.ItemUsable(item.cooldownID)
    else
        local sid = Fx.SpellOf(item)
        if not sid or type(C_Spell) ~= "table" or type(C_Spell.IsSpellUsable) ~= "function" then return end
        ok, can, noPower = pcall(C_Spell.IsSpellUsable, sid)
    end
    if not ok or type(can) ~= "boolean" or secret(can) then return end
    if glow then usable[item] = can end
    if secret(noPower) then return end
    castable[item] = can or noPower == true
    short[item] = (not can and noPower == true) or nil
end

local function updateState(item)
    readAlert(item)
    readUsable(item)
    local on
    if buffOnly[item] then cdState[item] = nil else on = Fx.OnCooldown(item) end
    cdFresh[item] = on ~= nil
    if on ~= nil then cdState[item] = on end
    -- A wand shot puts every spell on a fake cooldown (Ping.Shot).
    if on == true and (GetTime() >= ns.Ping.lockUntil or castSinceShot(item)) then realCool[item] = true end
end

-- Usable or proc. Castable already counts a spell that's only short of power, so
-- this is the condition coming true (a dodge, a block, a low target), not rage
-- trickling back. Also requires being off cooldown, like the usable glow.
local function usableMoment(item)
    local now
    if alerts[item] == true then now = true
    elseif cdState[item] == true then now = false
    elseif type(castable[item]) == "boolean" then now = castable[item]
    else return end
    local was = wasUsable[item]
    wasUsable[item] = now
    if was == false and now then playSound(item, opts[item], "usableSound") end
end

-- Gray: true, false, or nil for the game's own.
local function wantGrey(item)
    local d = Fx.Get(opts[item], "desat")
    if kinds[item] ~= "icon" or d == "game" then return nil end
    if d == "color" then return false end
    return cdState[item] == true
end

local function setGrey(icon, on)
    guard = true
    icon:SetDesaturated(on)
    guard = false
end

-- force = the game just wrote its own gray (our hook), so ours goes back on even if
-- it's what we last set.
local function applyGrey(item, icon, force)
    local want = wantGrey(item)
    if want == nil then
        -- Back to game default: undo ours and the game sets its own next update.
        if greyed[item] then greyed[item] = nil; greyAs[icon] = nil; setGrey(icon, false) end
        return
    end
    greyed[item] = true
    -- Every cooldown event refreshes, so only write on a change.
    if not force and greyAs[icon] == want then return end
    greyAs[icon] = want
    setGrey(icon, want)
end

-- The game grays icons as it updates, so ours goes on after.
local function hookGrey(item, icon)
    if greyHooked[icon] then return end
    greyHooked[icon] = true
    local function after() if not guard and opts[item] then applyGrey(item, icon, true) end end
    hooksecurefunc(icon, "SetDesaturated", after)
    if type(icon.SetDesaturation) == "function" then hooksecurefunc(icon, "SetDesaturation", after) end
end

-- Not castable: use the game's own Cooldown Manager colors so a spell waiting on a
-- dodge doesn't look ready. Our icons ease there FAST; the game's items snap, and
-- the game's own refresh puts its color back (range red too).
local DIM = { no = { 0.4, 0.4, 0.4 }, power = { 0.5, 0.5, 1 }, yes = { 1, 1, 1 } }

local function applyDim(item, icon)
    local want = not buffOnly[item] and (short[item] and "power" or castable[item] == false and "no") or nil
    if dimAs[icon] == want then return end
    dimAs[icon] = want
    local to = DIM[want or "yes"]
    if own[item] then
        local from = dimNow[icon] or DIM.yes
        local now = { from[1], from[2], from[3] }
        dimNow[icon] = now
        Motion.Tween(icon, 0, 1, Motion.FAST, function(t)
            for i = 1, 3 do now[i] = from[i] + (to[i] - from[i]) * t end
            icon:SetVertexColor(now[1], now[2], now[3])
        end)
    elseif not want and type(item.RefreshIconColor) == "function" then
        pcall(item.RefreshIconColor, item)
    else
        icon:SetVertexColor(to[1], to[2], to[3])
    end
end

-- Our own icons and bars ease (FAST, fight info never waits). The game's items snap,
-- since nothing of the game's fades in combat.
local function setAlpha(item, a)
    local from = alphaNow[item]
    if not own[item] then item:SetAlpha(a); return end
    alphaNow[item] = a
    if from == nil then from = a end
    Motion.Tween(item, from, a, Motion.FAST, function(v) item:SetAlpha(v) end)
end

-- Hidden by On cooldown or When ready Hide. With the group's Slide over, the spot
-- closes up (CdmRows asks Fx.Gone; a change requests a pass).
local gone = setmetatable({}, weak)
function Fx.Gone(item) return gone[item] ~= nil end
-- Gone because its buff is up (Buff up Hide). It gives up its spot even with Keep
-- its spot on, and keeps tracking up or down while closed (CdmRows).
function Fx.GoneUp(item) return gone[item] == "up" end

-- Fade / Hide on cooldown or while ready. Alpha is set here; Hide's spot is handled
-- by CdmRows (Fx.Gone).
local function applyAlpha(item)
    local b, state = opts[item], cdState[item]
    local mode = state == true and Fx.Get(b, "onCd") or state == false and Fx.Get(b, "onReady") or "show"
    local outOfForm = offForm(b)
    if state == false and castable[item] == false and Fx.Get(b, "onUnusable") ~= "show" then
        mode = Fx.Get(b, "onUnusable")
    elseif state == false and short[item] and Fx.Get(b, "onShort") ~= "show" then
        mode = Fx.Get(b, "onShort")
    end
    -- Every Hide gives up its spot (Not usable and Short too; a group growing from
    -- its middle stayed off-center otherwise), as does Buff up Hide on the game's
    -- buff item or our cooldown icon under a buff ("up": Keep its spot only applies
    -- while missing).
    local hideUp = down[item] == false and Fx.Get(b, "hideActive") == true
    local isGone = nil
    if not away[item] then
        if hideUp then isGone = "up"
        elseif (mode == "hide" and not buffOnly[item]) or outOfForm then isGone = true end
    end
    if gone[item] ~= isGone then
        gone[item] = isGone
        if ns.CdmRows then ns.CdmRows.Refresh() end
    end
    local a = 1
    if away[item] or outOfForm or (down[item] == false and Fx.Get(b, "hideActive") == true) then
        a = 0
    elseif mode ~= "show" then
        a = (mode == "hide") and 0 or Fx.Get(b, "cdAlpha")
    end
    if a == 1 and not faded[item] and not mouseOff[item] then return end
    faded[item] = (a ~= 1) or nil
    setAlpha(item, a)
    -- Hidden means no tooltip over the empty gap either. Our own frames don't take
    -- the mouse, so they're left alone.
    if own[item] then return end
    if a == 0 then
        mouseOff[item] = true
        item:EnableMouse(false)
    elseif mouseOff[item] then
        mouseOff[item] = nil
        item:EnableMouse(true)
    end
end

-- "Hide out of combat" (CdmRows): out of combat the block is away, and no cooldown
-- change brings an item back.
function Fx.SetAway(item, on)
    on = on or nil
    if away[item] == on then return end
    away[item] = on
    if opts[item] then applyAlpha(item) end
end

-- Apply / clear --------------------------------------------------------

local function refresh(item, read)
    if not opts[item] then return end
    if read then
        local was = cdState[item]
        updateState(item)
        if cdFresh[item] then moment(item, was, cdState[item]) end
        usableMoment(item)
    end
    if kinds[item] == "icon" then
        local icon = ns.Cooldowns.IconOf(item)
        if type(icon) == "table" then
            if wantGrey(item) ~= nil then hookGrey(item, icon) end
            applyGrey(item, icon)
            applyDim(item, icon)
        end
    end
    applyAlpha(item)
    showGlow(item, wantsGlow(item))
end

function Fx.Refresh(item) refresh(item, true) end
refreshNow = function(item) refresh(item, false) end

-- Whether a piece's buff is down (true), up (false) or unknown (nil), reported by
-- CdmRows each pass after Fx.Apply. An item we don't otherwise hold (a stand-in, an
-- aura holder) only gets the missing glow, from button.
local looseLit = setmetatable({}, weak)
function Fx.SetDown(item, button, isDown)
    down[item] = isDown
    if opts[item] then refreshNow(item); return end
    local want = buffGlow(button, isDown)
    looseLit[item] = want and true or nil
    showGlow(item, want, button)
end

-- After a pass, loose items it didn't report on lose their glow, and a held item it
-- didn't report on (the game hid it as its buff dropped) forgets up or down so a
-- buff glow isn't left on it.
function Fx.EndPass(told)
    for item in pairs(looseLit) do
        if not told[item] then looseLit[item] = nil; down[item] = nil; showGlow(item, false) end
    end
    for item in pairs(opts) do
        if not told[item] and down[item] ~= nil then down[item] = nil; refreshNow(item) end
    end
end

-- Runs after each placement pass for every item we hold (CdmRows). isOwn = our own
-- icon or bar (CdmOwn, CdmBars), not the game's item.
function Fx.Apply(item, button, kind, isOwn, onlyBuff)
    opts[item], kinds[item] = button, kind
    own[item] = isOwn or nil
    -- Buff only has no cooldown rows on its card, so any old values there are ignored.
    buffOnly[item] = onlyBuff or nil
    local cd = type(item.Cooldown) == "table" and item.Cooldown or nil
    -- No event fires when a cooldown ends, but its own frame does (our bars' time
    -- in CdmBars is one too). No game value is read; the spell is simply ready.
    local done = cd or (type(item.Timer) == "table" and item.Timer) or nil
    if done and type(done.HookScript) == "function" and not doneHooked[done] then
        doneHooked[done] = true
        done:HookScript("OnCooldownDone", function()
            if not opts[item] or buffOnly[item] then return end
            local was = cdState[item]
            -- On the game's icons the frame also counts a buff's time.
            local still = Fx.OnCooldown(item, true) == true
            -- Blind under a wand shot, there's no later read to restore it.
            cdState[item] = still and was == true and blindShot(item)
            moment(item, was, false, still)
            -- Cast while the cooldown was unreadable (Fx.Armed): this is its end.
            local cast = armed[item]
            if cast and was ~= true and not still and GetTime() - cast >= Fx.ARM_MIN then
                armed[item] = nil
                playSound(item, opts[item], "readySound")
            end
            refresh(item, false)
        end)
    end
    if cd then
        local rule = kind == "icon" and (Fx.Get(button, "noSwipe") == true and "all"
            or Fx.Get(button, "noGcd") == true and "gcd") or nil
        if rule then
            hookSwipe(item, cd)
            noSwipe[item] = rule
            applySwipe(item, cd)
        elseif noSwipe[item] then
            noSwipe[item] = nil
            setSwipe(cd, true)
        end
        local rev = kind == "icon" and Fx.Get(button, "reverse") == true
        if rev or reversed[item] then
            reversed[item] = rev or nil
            pcall(cd.SetReverse, cd, rev)
        end
        if kind == "icon" then hookTint(item, cd) end
        applyTint(item)
    end
    Fx.Refresh(item)
end

-- The item is released: undo everything we changed.
function Fx.Clear(item)
    if noSwipe[item] then
        noSwipe[item] = nil
        if type(item.Cooldown) == "table" then setSwipe(item.Cooldown, true) end
    end
    if reversed[item] then
        reversed[item] = nil
        if type(item.Cooldown) == "table" then pcall(item.Cooldown.SetReverse, item.Cooldown, false) end
    end
    if greyed[item] then
        greyed[item] = nil
        local icon = ns.Cooldowns.IconOf(item)
        if type(icon) == "table" then greyAs[icon] = nil; setGrey(icon, false) end
    end
    local dimmed = ns.Cooldowns.IconOf(item)
    if type(dimmed) == "table" and dimAs[dimmed] then
        Motion.Tween(dimmed, 1, 1, 0)
        dimAs[dimmed], dimNow[dimmed] = nil, nil
        dimmed:SetVertexColor(1, 1, 1)
    end
    if tinted[item] then
        opts[item] = nil
        applyTint(item)
    end
    if faded[item] then
        faded[item] = nil
        if alphaNow[item] ~= nil then Motion.Tween(item, 1, 1, 0) end
        item:SetAlpha(1)
    end
    alphaNow[item] = nil
    if mouseOff[item] then mouseOff[item] = nil; item:EnableMouse(true) end
    cdState[item], away[item], usable[item], castable[item], down[item] = nil, nil, nil, nil, nil
    short[item] = nil
    buffOnly[item] = nil
    wasUsable[item], realCool[item], armed[item], castAt[item] = nil, nil, nil, nil
    showGlow(item, false)
    opts[item], kinds[item], own[item] = nil, nil, nil
end

-- Cooldowns moved: update only the items we hold.
function Fx.UpdateAll()
    for item in pairs(opts) do Fx.Refresh(item) end
end

-- Your own cast (plain in every fight) when the client hides the cooldown, so its
-- start can't be seen; the cooldown frame's end then means ready. A game icon with
-- an aura counts that aura on the same frame, so it stays quiet rather than sound
-- early.
function Fx.Armed(sid)
    local real = ns.CdmOwn.HasCooldown(sid)
    for item, b in pairs(opts) do
        if real and not buffOnly[item] and Fx.SpellOf(item) == sid then
            castAt[item] = GetTime()   -- so a wand shot's lockout can't hide this one (Fx.OnCooldown)
            if Fx.Get(b, "readySound") ~= "none" and not auraItem(item) and Fx.OnCooldown(item) == nil then
                armed[item] = GetTime()
            end
        end
    end
end

local casts = CreateFrame("Frame")
casts:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
casts:SetScript("OnEvent", function(_, _, _, _, sid)
    if type(sid) ~= "number" or secret(sid) then return end
    DUI.SafeCall(Fx.Armed, sid)
end)

-- Runs once on the next frame however many events came in. A cast sends two to four
-- cooldown and charge events, and each one used to redo every held item (and our
-- own icons). For a proc, the game shows its alert in its own handler for the same
-- event, so ours reads it a frame later anyway.
local wantFx, wantOwn, queued = false, false, false
local function flush()
    queued = false
    local fx, own = wantFx, wantOwn
    wantFx, wantOwn = false, false
    if fx then DUI.SafeCall(Fx.UpdateAll) end
    if own and ns.CdmOwn then DUI.SafeCall(ns.CdmOwn.UpdateAll) end
end
function Fx.Soon(own)
    wantFx = true
    if own then wantOwn = true end
    if queued then return end
    queued = true
    C_Timer.After(0, flush)
end
local function procSoon() Fx.Soon(false) end
local function cooldownSoon() Fx.Soon(true) end
pcall(DUI.RegisterEvent, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", procSoon)
pcall(DUI.RegisterEvent, "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", procSoon)
-- A spell turning castable or not (a block for Revenge, rage, the target's health).
pcall(DUI.RegisterEvent, "SPELL_UPDATE_USABLE", procSoon)
pcall(DUI.RegisterEvent, "PLAYER_MOUNT_DISPLAY_CHANGED", procSoon)

DUI.RegisterEvent("SPELL_UPDATE_COOLDOWN", cooldownSoon)
DUI.RegisterEvent("SPELL_UPDATE_CHARGES", cooldownSoon)
-- Items added by ID (CdmCustom): their cooldown and their bag count, which shows on
-- our icons and bars (none left grays them).
pcall(DUI.RegisterEvent, "BAG_UPDATE_COOLDOWN", cooldownSoon)
pcall(DUI.RegisterEvent, "BAG_UPDATE_DELAYED", cooldownSoon)
DUI.RegisterEvent("PLAYER_REGEN_ENABLED", function() Fx.UpdateAll() end)

-- A new form, stance or stealth updates what's shown at once (fight info never
-- waits).
local function formChanged()
    local now = Fx.ReadForm()
    if now == formNow then return end
    formNow = now
    Fx.UpdateAll()
end
Fx.FormChanged = formChanged
for _, e in ipairs({ "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS", "UPDATE_STEALTH", "PLAYER_ENTERING_WORLD" }) do
    pcall(DUI.RegisterEvent, e, function() DUI.SafeCall(formChanged) end)
end
