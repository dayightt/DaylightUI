-- Per-spell effects on the Cooldown Manager items Daylight UI places (CdmRows): proc glow,
-- per-icon size, no cooldown swipe, and what happens on cooldown (gray, fade, hide,
-- ready glow). Options live in DB.Character().cdm.sets[g].buttons[id]; a missing
-- key means the default. Fx.Clear undoes everything when an item is released.
-- Textures sit on the item the same way the skin's do, and bookkeeping is in weak
-- tables.

local _, ns = ...
local DUI = DaylightUI
local secret = DUI.IsSecret

local Fx = {}
ns.CdmEffects = Fx

-- Option keys, beyond the defaults below:
-- glowColor (proc) and readyGlowColor: nil = the accent.
-- Icons only: noDurationSwipe = no swipe while the buff is up (game items: same as
-- activeGlow false; Daylight UI's aura holders: CdmAuras.SetSwipe). activeGlow false hides
-- the game's swipe while the buff is up (the timer stays). activeColor {r,g,b,a}
-- recolors it, nil = the accent (Fx.ActiveColor).
-- Bars only: barMode "block" | "solid" | "gradient" | "customGradient" (barColor
-- {r,g,b}, barGradient {lo,hi}, barStops { count, c1 to c5 }), backMode "block" | "solid" | "gradient" (backColor {r,g,b,a},
-- backGradient {lo,hi}); nil colors follow the block's look. showName, nameAlign
-- "left" | "center". fillBy "shield" | "time": a shield spell's bar fills by the
-- shield left (CdmBars.IsShield). shieldAmount shows the amount left on it.
-- inactiveFlash: the empty bar ("Show missing buffs") pulses while the buff is down.
-- missing: "Show when missing", the spell keeps its spot (grayed icon, empty bar)
-- while its buff is down. missingGlow (missingGlowColor) makes it glow then.
-- upGlow (upGlowColor): glows while its buff is up. WoW Forever fires no proc
-- alerts, so for something like Clearcasting the buff landing is the proc.
-- clipGlow (clipGlowColor): glows while it's up and the next cast of it would land
-- just as it runs out (CdmAuras.ClipDue), the moment to cast it again.
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
    shieldAmount = true, glowStyle = "ring", inactiveFlash = false, missing = false, missingGlow = false, upGlow = false, clipGlow = false, hideActive = false, hideMissing = false, chargeLines = true,
    fxStyle = "group", fxColors = "group" }

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
    WARRIOR = { { key = "Battle", name = "Battle Stance", spells = { 2457 }, lit = true },
                { key = "Defensive", name = "Defensive Stance", spells = { 71 }, lit = true },
                { key = "Berserker", name = "Berserker Stance", spells = { 2458 }, lit = true } },
    ROGUE = { { key = "Unstealthed", name = "Out of Stealth", none = true },
              { key = "Stealth", name = "Stealth", spells = { 1784, 1785, 1786, 1787 }, stealth = true } },
}
Fx.FORM_KEYS = {}
local formBySpell = {}
-- Stances put up no buff, so nothing else tells their icon apart while you're in
-- one. Druid forms and Stealth are buffs and already show as up.
local litBySpell = {}
for _, list in pairs(Fx.FORMS) do
    for _, f in ipairs(list) do
        Fx.FORM_KEYS[#Fx.FORM_KEYS + 1] = f.key
        for _, sid in ipairs(f.spells or {}) do
            formBySpell[sid] = f.key
            if f.lit then litBySpell[sid] = f.key end
        end
    end
end
-- Each is a spell option, shown by default and only saved when turned off.
for _, k in ipairs(Fx.FORM_KEYS) do
    Fx.DEFAULTS["hideIn" .. k] = false
    if ns.CdmData then ns.CdmData.SPELL_FIELDS["hideIn" .. k] = { bool = true } end
end

local function plainOf(v) return not secret(v) and v or nil end

-- The class's forms (nil when there are none to pick).
function Fx.FormsOf(class)
    if class == nil then
        local _, token = UnitClass("player")
        class = plainOf(token)
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
        local _, active, _, sid = GetShapeshiftFormInfo(i)
        if plainOf(active) == true and type(plainOf(sid)) == "number" and formBySpell[sid] then
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
local dimNow = setmetatable({}, weak)      -- Daylight UI's own icon texture -> the color it shows or eases from
local alphaNow = setmetatable({}, weak)    -- Daylight UI's own item -> the alpha it shows or eases to
local glows = setmetatable({}, weak)       -- item -> its glow frame
local lit = setmetatable({}, weak)         -- item -> true while its glow shows
local noSwipe = setmetatable({}, weak)     -- item -> "all" | "gcd": swipe kept off always, or on the GCD
local buffOnly = setmetatable({}, weak)   -- item -> true when set to Buff only, so its cooldown changes nothing
local reversed = setmetatable({}, weak)    -- item -> true while its swipe is kept reversed
local swipeHooked = setmetatable({}, weak) -- cooldown frame -> true
local cdState = setmetatable({}, weak)     -- item -> true on cooldown, false ready (last known)
local cdFresh = setmetatable({}, weak)     -- item -> true when cdState was read this time (not secret)
local greyHooked = setmetatable({}, weak)  -- icon texture -> true
local greyed = setmetatable({}, weak)      -- item -> true while the gray is Daylight UI's
local greyAs = setmetatable({}, weak)      -- icon texture -> the gray last set on it
local faded = setmetatable({}, weak)       -- item -> true while its alpha is held below 1
local doneHooked = setmetatable({}, weak)  -- cooldown frame -> true
local mouseOff = setmetatable({}, weak)    -- item -> true while its mouse is kept off
local tinted = setmetatable({}, weak)      -- item -> true while its swipe color is held
local tintHooked = setmetatable({}, weak)  -- cooldown frame -> true
local away = setmetatable({}, weak)        -- item -> true while its "Hide out of combat" block is away
local down = setmetatable({}, weak)        -- item -> true: buff down, false: up (from CdmRows; nil = can't tell)
local due = setmetatable({}, weak)         -- item -> true: time to cast it again (CdmRows, the recast glow)
local own = setmetatable({}, weak)         -- item -> true for Daylight UI's own icons and bars (CdmOwn, CdmBars)
local refreshNow                          -- refresh without reading (set below)
local guard = false                        -- set during the file's own calls so its hooks skip them

function Fx.Get(button, key)
    local v
    if type(button) == "table" then v = button[key] end
    if v == nil then v = Fx.DEFAULTS[key] end
    return v
end

-- The saved button table of a claimed item (nil when Daylight UI doesn't hold it).
function Fx.ButtonOf(item) return opts[item] end

-- Gives a game item its mouse back as the game sets it (CooldownViewerItemMixin:SetTooltipsShown).
-- Clicks go through to the world, and the hover shows a tooltip only while its viewer's
-- Edit Mode "Show tooltips" is on.
function Fx.GameMouse(item)
    local viewer = item.GetViewerFrame and item:GetViewerFrame()
    item:SetMouseClickEnabled(false)
    item:SetMouseMotionEnabled(not (viewer and viewer.tooltipsShown == false))
end

-- Glow -----------------------------------------------------------------
-- The game's own proc glow (the looping spell alert ring every player knows) on a
-- Daylight UI frame, recolored to the option's color or the accent (a gradient accent
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

Fx.GLOW_MID = 0.4         -- the share of the ring's width that is straight edge, stretched along a bar

-- The ring is square art, so stretched over a bar its corners smear into a blob.
-- A wide item gets it in three pieces: each end a square ring cut in half, and
-- between them the ring's straight middle stretched. Each piece runs its own
-- flipbook in one group, so they turn together.
local PIECES = { "left", "mid", "right" }

local function glowOf(item)
    local g = glows[item]
    if g then return g end
    g = CreateFrame("Frame", nil, item)
    g:SetFrameLevel(item:GetFrameLevel() + 6)
    g.a = 0
    local ag = g:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    g.parts = {}
    for _, key in ipairs(PIECES) do
        local clip = CreateFrame("Frame", nil, g)
        clip:SetClipsChildren(true)
        local holder = CreateFrame("Frame", nil, clip)
        local t = holder:CreateTexture(nil, "OVERLAY")
        t:SetAllPoints(holder)
        t:SetAtlas(Fx.GLOW_ATLAS)
        -- The game's art is gold; desaturate it so Daylight UI's color tints true.
        t:SetDesaturated(true)
        local fb = ag:CreateAnimation("FlipBook")
        fb:SetTarget(t)
        fb:SetDuration(Fx.GLOW_LOOP)
        fb:SetFlipBookRows(Fx.GLOW_ROWS)
        fb:SetFlipBookColumns(Fx.GLOW_COLUMNS)
        fb:SetFlipBookFrames(Fx.GLOW_FRAMES)
        fb:SetFlipBookFrameWidth(0)
        fb:SetFlipBookFrameHeight(0)
        g.parts[key] = { clip = clip, holder = holder, tex = t }
    end
    g.tex = g.parts.mid.tex
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
    local gw, gh = w + 2 * pad, h + 2 * pad
    local P = g.parts
    for _, key in ipairs(PIECES) do
        P[key].clip:ClearAllPoints()
        P[key].holder:ClearAllPoints()
    end
    g.wide = gw > gh * 1.25
    if not g.wide then
        P.mid.clip:SetAllPoints(g)
        P.mid.holder:SetAllPoints(g)
        P.left.clip:Hide()
        P.right.clip:Hide()
        return
    end
    local half = gh / 2
    P.left.clip:SetPoint("TOPLEFT", g, "TOPLEFT")
    P.left.clip:SetSize(half, gh)
    P.left.holder:SetPoint("TOPLEFT", g, "TOPLEFT")
    P.left.holder:SetSize(gh, gh)
    P.right.clip:SetPoint("TOPRIGHT", g, "TOPRIGHT")
    P.right.clip:SetSize(half, gh)
    P.right.holder:SetPoint("TOPRIGHT", g, "TOPRIGHT")
    P.right.holder:SetSize(gh, gh)
    P.mid.clip:SetPoint("TOPLEFT", g, "TOPLEFT", half, 0)
    P.mid.clip:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -half, 0)
    P.mid.holder:SetPoint("CENTER", g, "CENTER")
    P.mid.holder:SetSize((gw - gh) / Fx.GLOW_MID, gh)
    P.left.clip:Show()
    P.right.clip:Show()
end

-- c = {r,g,b}, or nil for the accent (a gradient accent runs across the ring:
-- on a bar the left end takes one color, the right end the other).
local function paintGlow(g, c)
    local P = g.parts
    if type(c) == "table" then
        for _, key in ipairs(PIECES) do P[key].tex:SetVertexColor(c[1], c[2], c[3], 1) end
        return
    end
    local lo, hi = DUI.Style.AccentPair()
    if lo and CreateColor then
        local L, H = CreateColor(lo[1], lo[2], lo[3], 1), CreateColor(hi[1], hi[2], hi[3], 1)
        for _, key in ipairs(PIECES) do P[key].tex:SetVertexColor(1, 1, 1, 1) end
        if g.wide then
            P.left.tex:SetGradient("HORIZONTAL", L, L)
            P.right.tex:SetGradient("HORIZONTAL", H, H)
        end
        P.mid.tex:SetGradient("HORIZONTAL", L, H)
    else
        for _, key in ipairs(PIECES) do P[key].tex:SetVertexColor(DUI.Style.Accent()) end
    end
end

-- What a lit glow was painted with (plain numbers, or "accent"), so a refresh that
-- changes nothing (every cooldown event) doesn't repaint.
local litAs = setmetatable({}, weak)
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
        if goal == 1 and (item:GetWidth() ~= g.w or item:GetHeight() ~= g.h) then
            local wasWide = g.wide
            sizeGlow(g, item)
            local as = litAs[item]
            -- The lights keep the ring's pieces away (sizeGlow shows them for a ring).
            if as and as.style ~= "ring" then
                for _, key in ipairs(PIECES) do g.parts[key].clip:Hide() end
            end
            if g.wide ~= wasWide and as then paintGlow(g, as.accent == nil and as or nil) end
        end
    end
    if not any then driver:SetScript("OnUpdate", nil) end
end

local accentGen = 0          -- bumped on a style change, since the accent may differ
DUI.On("StyleChanged", function() accentGen = accentGen + 1 end)

-- A spell's glow style: "ring" (the game's proc ring) or one of the animated
-- lights (Motion.GLOW_STYLES), which run round the item's edge. Motion off, a
-- glow with no spell behind it (an action button's) or a plugin's style that
-- isn't loaded keep the ring.
function Fx.GlowStyle(button)
    local s = Fx.Get(button, "glowStyle")
    if not (DUI.Motion.GLOW_STYLES[s] and DUI.Motion.On()) then return "ring" end
    return s
end
-- A light's size and a strip's width, as shares of the item's short side, so a
-- big icon or a tall bar gets a glow to match.
Fx.GLOW_SCALE = { size = 0.7, thick = 0.08 }

-- Lays the picked style on a lit glow: the ring's pieces, or the lights.
local function styleGlow(g, item, c, style)
    local ring = style == "ring"
    for _, key in ipairs(PIECES) do g.parts[key].clip:SetShown(ring and (key == "mid" or g.wide)) end
    if ring then
        DUI.Widgets.GlowAround(g, false)
        if not g.anim:IsPlaying() then g.anim:Play() end
        return
    end
    g.anim:Stop()
    DUI.Widgets.GlowAround(g, true, {
        style = style, frame = item, inset = 0, thick = DUI.Pixel.Px(item, 2), scale = Fx.GLOW_SCALE,
        lo = type(c) == "table" and c or nil, parent = g, layer = "OVERLAY", sub = 7,
    })
end

local function lightGlow(item, c)
    local was = litAs[item]
    local style = Fx.GlowStyle(opts[item])
    if lit[item] and was and was.style == style then
        if type(c) == "table" then
            if was[1] == c[1] and was[2] == c[2] and was[3] == c[3] then return end
        elseif was.accent == accentGen then
            return
        end
    end
    local g = glowOf(item)
    sizeGlow(g, item)
    paintGlow(g, type(c) == "table" and c or nil)
    if not g:IsShown() then g:Show() end
    styleGlow(g, item, c, style)
    if type(c) == "table" then
        litAs[item] = { c[1], c[2], c[3], style = style }
    else
        litAs[item] = { accent = accentGen, style = style }
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

-- A glow style shown for a moment on a frame of the layout editor (the card's
-- Style row: a hover or a pick), in the color of a glow the spell has on.
Fx.PREVIEW_HOLD = 2.5      -- seconds a preview runs
local previewHosts = setmetatable({}, weak)
local GLOW_KEYS = { "readyGlow", "usableGlow", "upGlow", "clipGlow", "missingGlow" }
function Fx.PreviewGlow(frame, style, button)
    if type(frame) ~= "table" then return end
    local c
    for _, key in ipairs(GLOW_KEYS) do
        if c == nil and Fx.Get(button, key) == true then c = Fx.Get(button, key .. "Color") end
    end
    c = type(c) == "table" and c or nil
    local host = previewHosts[frame]
    if not host then host = {}; previewHosts[frame] = host end
    local lights = DUI.Motion.GLOW_STYLES[style] and DUI.Motion.On()
    if lights then
        Fx.SetGlow(frame, false)
        DUI.Widgets.GlowAround(host, true, {
            style = style, frame = frame, parent = frame, layer = "OVERLAY", sub = 7,
            inset = 0, thick = DUI.Pixel.Px(frame, 2), scale = Fx.GLOW_SCALE, lo = c,
        })
    else
        DUI.Widgets.GlowAround(host, false)
        Fx.SetGlow(frame, true, c)
    end
    local token = {}
    host.previewToken = token
    C_Timer.After(Fx.PREVIEW_HOLD, function()
        if host.previewToken ~= token then return end
        host.previewToken = nil
        DUI.Widgets.GlowAround(host, false)
        Fx.SetGlow(frame, false)
    end)
end

function Fx.PreviewHost(frame) return previewHosts[frame] end

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
local function clipGlows(b)
    return Fx.Get(b, "clipGlow") == true and Fx.Get(b, "hideActive") ~= true
end
-- The glow asked for by the buff being down (true) or up (false). due = time to
-- cast it again, which wins over the plain up glow. It runs on your own cast's
-- clock, so it lights with no word on the buff too, only never on a known "down".
local function buffGlow(b, isDown, due)
    if isDown == true and missingGlows(b) then return "missingGlowColor" end
    if isDown ~= true and due == true and clipGlows(b) then return "clipGlowColor" end
    if isDown == false and upGlows(b) then return "upGlowColor" end
    return false
end
Fx.UpGlows = upGlows
Fx.ClipGlows = clipGlows

-- Reads only Daylight UI's own bookkeeping, never the game's values. Returns the color key of
-- the glow that should show (proc first, then usable, then ready), or false.
local function wantsGlow(item)
    local b = opts[item]
    if Fx.Get(b, "glow") ~= false and alerts[item] == true then return "glowColor" end
    local buff = buffGlow(b, down[item], due[item])
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
-- combat (nothing of the game's animates in a fight); Daylight UI's own icons always do.
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

-- A buff landing on Daylight UI's aura icons and bars (CdmAuras, CdmBars) slides in like the
-- buff bar's (Buffs Feel.lua). It's an animation group handed to the client in
-- initializeFrame and played as the button comes up for a new aura, in fights too.
-- Translation and alpha only. The button locks once initializeFrame returns, so
-- retuning it (motion toggled) waits for the holders' after-restrictions layout.
-- Over Daylight UI's own cooldown icon ("Cooldown and buff", CdmAuras.Over) it only fades in
-- place: the same spell's icon is already there, so a drop looked like the icon
-- jumping (Shield Block).
Fx.SLIDE = 6   -- px it drops in from
Fx.SLIDE_HOLD = 0.3   -- seconds the slide stays still while the client rebuilds its buttons
local slides = setmetatable({}, weak)   -- every client button given a slide

function Fx.MakeSlide(btn, h)
    -- No OnShow/OnHide on a Daylight UI frame inside the button: the client refuses them
    -- there ("blocked by secret aspects").
    if type(btn.AddAuraShownAnimation) ~= "function" then return end
    local ag = btn:CreateAnimationGroup()
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
    slides[btn] = true
    Fx.TuneSlide(btn)
    DUI.SafeCall(btn.AddAuraShownAnimation, btn, ag)
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

-- A locked button (in a fight, under restrictions) refuses on purpose; retried next
-- layout. Returns whether it took.
local function tryTune(s, on, drop) return pcall(tune, s, on, drop) end

function Fx.TuneSlide(btn)
    local s = btn.cdmSlide
    if not s or btn.cdmSlideHeld then return end
    local on = Motion.On()
    local h = btn.cdmSlideHolder
    local drop = not (type(h) == "table" and h.overIcon == true)
    local key = on and (drop and "slide" or "fade") or false
    if btn.cdmSlideKey == key then return end
    if tryTune(s, on, drop) then btn.cdmSlideOn, btn.cdmSlideKey = on, key end
end

-- The client's aura containers rebuild every button on a fight's end, entering the
-- world, a spec change and the unit's flags or faction changing (FullAuraRefreshEvents
-- in Blizzard_CustomAuraContainer.lua): each button is let go and handed its aura
-- again, which plays its shown animation, so a buff that had been up all along slid
-- in as if it had just landed. The rebuild waits for the container's next update, so
-- the slide is stilled before it and tuned back after. Only out of a fight: the
-- buttons are locked in one, and stilled there they would stay still for the whole
-- fight, when a proc landing is what the slide is for. A fight's start is the one
-- rebuild left: its buttons lock as it begins.
function Fx.HoldSlides()
    if InCombatLockdown() then return end
    local any = false
    for btn in pairs(slides) do
        if not btn.cdmSlideHeld and tryTune(btn.cdmSlide, false) then
            btn.cdmSlideHeld, btn.cdmSlideKey = true, nil
            any = true
        end
    end
    if not any then return end
    C_Timer.After(Fx.SLIDE_HOLD, function()
        for btn in pairs(slides) do
            if btn.cdmSlideHeld then
                btn.cdmSlideHeld = nil
                Fx.TuneSlide(btn)
            end
        end
    end)
end
for _, e in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "PLAYER_SPECIALIZATION_CHANGED" }) do
    DUI.RegisterEvent(e, function() DUI.SafeCall(Fx.HoldSlides) end)
end
-- A unit event takes two units at most: the holders watch you and your target.
local flags = CreateFrame("Frame")
flags:RegisterUnitEvent("UNIT_FLAGS", "player", "target")
flags:RegisterUnitEvent("UNIT_FACTION", "player", "target")
flags:SetScript("OnEvent", function() DUI.SafeCall(Fx.HoldSlides) end)

-- Sounds ---------------------------------------------------------------
-- Like a proc addon: a per-spell sound the moment it matters. Each fires on the
-- change, never while the state holds, and a piece sounds at most once per
-- SOUND_GAP however many moments land together (ready and usable are one moment on
-- most spells). A chain that's hidden (its show rules, the editor) stays quiet along
-- with its icons.
Fx.SOUND_GAP = 0.5
Fx.ARM_MIN = 2           -- seconds; a cast's OnCooldownDone sooner than this was only the GCD
Fx.SETTLE = 2            -- seconds after entering the world; buffs already up aren't news
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

-- Plugins hear the moments too (DaylightUI.API: CooldownReady, CooldownStarted,
-- CooldownUsable, CooldownProc, CooldownBuffUp, CooldownBuffDown), by spell and
-- the piece's key. id = the piece's key when the caller knows it better than the item.
local function tell(event, item, id, on)
    local R = DUI.APIReport
    if not R.Wants(event) then return end
    local key = id
    if key == nil and item then key = item.cooldownID end
    if secret(key) then key = nil end
    local sid = id ~= nil and ns.CdmOwn and ns.CdmOwn.SpellOf(id) or nil
    if sid == nil and item then sid = Fx.SpellOf(item) end
    R.Event(event, sid, key ~= nil and tostring(key) or nil, on)
end

-- Called by CdmRows each pass for every piece whose buff state it can tell.
function Fx.BuffMoment(piece, item, isDown, id)
    if type(isDown) ~= "boolean" then return end
    local was = wasDown[piece]
    wasDown[piece] = isDown
    if was ~= nil and was ~= isDown then tell(isDown and "CooldownBuffDown" or "CooldownBuffUp", item, id) end
    if was == true and not isDown then playSound(item, piece, "buffSound")
    elseif was == false and isDown then
        -- Really ended, not a new target's debuffs leaving view or a zone change
        -- or death clearing them all.
        local now = GetTime()
        if now - targetAt < Fx.END_QUIET or now - enteredAt < Fx.SETTLE then return end
        local dead = UnitIsDeadOrGhost("player")
        if plainOf(dead) == true then return end
        playSound(item, piece, "buffEndSound")
    end
end

DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function() enteredAt = GetTime() end)
DUI.RegisterEvent("PLAYER_TARGET_CHANGED", function() targetAt = GetTime() end)

-- cdState changed from was to now (both plain): ready or on cooldown. quiet = the
-- light still runs but the sound waits (an aura's time ended over a cooldown that's
-- still going).
local function moment(item, was, now, quiet)
    if was == true and now == false then
        Fx.Sweep(item)
        tell("CooldownReady", item)
        if realCool[item] and not quiet then
            realCool[item], armed[item] = nil, nil
            playSound(item, opts[item], "readySound")
        end
    elseif was == false and now == true then
        Fx.Dip(item)
        tell("CooldownStarted", item)
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
    if secret(gcd) then return false end
    return gcd == true
end

-- Applies Daylight UI's swipe rule to the item's cooldown: always off, or off while only the
-- global cooldown runs.
local function applySwipe(item, cd)
    local rule = noSwipe[item]
    if not rule then return end
    setSwipe(cd, not (rule == "all" or onGcd(item)))
end

-- The game sets the swipe and cooldown again as it updates (Daylight UI's own icons set the
-- cooldown), so this one is reapplied after.
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
-- down. Only that swipe is recolored (alpha 0 = timer only). Unset, it takes the
-- accent like the glows, at the game's own opacity.

local ACTIVE_ALPHA = 0.7

-- A piece's buff swipe color: its own, else the accent (read at paint time).
-- into: a table to fill instead of a new one, for the swipe hooks that run on
-- every cooldown update.
function Fx.ActiveColor(b, into)
    local c = b and Fx.Get(b, "activeColor")
    if type(c) == "table" then return c end
    local r, g, bl = DUI.Style.Accent()
    if not into then return { r, g, bl, ACTIVE_ALPHA } end
    into[1], into[2], into[3], into[4] = r, g, bl, ACTIVE_ALPHA
    return into
end

local function setTint(cd, c)
    guard = true
    pcall(cd.SetSwipeColor, cd, c[1], c[2], c[3], c[4] or 1)
    guard = false
end

local function fromAura(item)
    local v = item.wasSetFromAura
    return type(v) == "boolean" and not secret(v) and v
end

-- Read by setTint at once and never kept, so one of each serves every item.
local NO_SWIPE = { 0, 0, 0, 0 }
local accentSwipe = {}

local function applyTint(item)
    local cd = item.Cooldown
    if type(cd) ~= "table" or type(cd.SetSwipeColor) ~= "function" then return end
    local b = opts[item]
    local want
    -- An element piece's standing totem counts as a buff's time (CdmOwn.FollowSlot).
    if b and kinds[item] == "icon" and (fromAura(item) or item.slotPhase == "totem") then
        if Fx.Get(b, "activeGlow") == false or Fx.Get(b, "noDurationSwipe") == true then
            want = NO_SWIPE
        else
            want = Fx.ActiveColor(b, accentSwipe)
        end
    end
    if want then
        tinted[item] = true
        setTint(cd, want)
    elseif tinted[item] then
        -- The buff is gone (or the item left Daylight UI's blocks): back to the cooldown shade.
        tinted[item] = nil
        setTint(cd, ns.Skin.SWIPE)
    end
end

-- The game sets the swipe color and cooldown as it updates, so this one goes on after.
local function hookTint(item, cd)
    if tintHooked[cd] then return end
    tintHooked[cd] = true
    local function after() if not guard and opts[item] then applyTint(item) end end
    for _, m in ipairs({ "SetSwipeColor", "SetCooldown", "SetCooldownFromDurationObject" }) do
        if type(cd[m]) == "function" then hooksecurefunc(cd, m, after) end
    end
end

-- Cooldown -------------------------------------------------------------


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

-- A totem standing: true, false, or nil when the game won't say. Only for the
-- totems with no buff (CdmCustom.TOTEMS); other totems keep their own cooldown.
-- Daylight UI's own totem icons and bars (item.totem) ask CdmCustom.TotemUp. The
-- game's item keeps an emptied slot as its totem (the client reports an empty slot
-- as having one), so its slot is asked whether it still returns a duration, which
-- is never secret. In a fight the item's totem data is a secret table: no telling.
local totemCheck = false
local function watchTotems()
    -- No event marks a totem running out, so look again while one stands.
    if totemCheck then return end
    totemCheck = true
    C_Timer.After(Fx.TOTEM_CHECK, function()
        totemCheck = false
        Fx.Soon(false)
    end)
end

local function totemUp(item)
    if type(GetTotemDuration) ~= "function" then return false end
    local C = ns.CdmCustom
    if item.totem then
        local d = C and C.TotemUp(Fx.SpellOf(item))
        if type(d) == "nil" or d == false then return false end
    else
        if not (C and C.TotemNoBuff(Fx.SpellOf(item))) then return false end
        if type(item.GetTotemData) ~= "function" then return false end
        local ok, totem = pcall(item.GetTotemData, item)
        if not ok or type(totem) == "nil" then return false end
        if secret(totem) then return nil end
        local slot = type(totem) == "table" and totem.slot
        if type(slot) ~= "number" or secret(slot) then return false end
        local okD, d = pcall(GetTotemDuration, slot)
        if not okD or type(d) == "nil" then return false end
    end
    watchTotems()
    return true
end

-- An element piece (CdmCustom.SlotNow): "totem", "cooldown" or nil. A slot that
-- changed since it was drawn is drawn again first, so its spell is current.
local function slotPhase(item)
    local C = ns.CdmCustom
    if not (item.totem and C and C.Element(item.cooldownID)) then return false end
    local sid, phase = C.SlotNow(item.cooldownID)
    if sid ~= item.slotSpell or phase ~= item.slotPhase then
        if kinds[item] == "bar" then
            if ns.CdmBars then ns.CdmBars.UpdateCooldown(item) end
        elseif ns.CdmOwn then
            ns.CdmOwn.Update(item)
        end
    end
    return phase
end
Fx.TOTEM_CHECK = 0.5   -- seconds between looks while a totem stands

-- On cooldown, not just the global cooldown? nil when the game won't say.
-- ending = asked as the item's cooldown frame ran out.
function Fx.OnCooldown(item, ending)
    local C = ns.CdmCustom
    if C and C.ItemOf(item.cooldownID) then return (C.ItemCooldown(item.cooldownID)) end
    -- A standing totem counts as its cooldown, as the game's own icon times it.
    -- So When ready Hide shows a totem only while it stands. An element piece's
    -- cooldown totem, once gone, is timed by its spell's cooldown below.
    local phase = slotPhase(item)
    if phase == "totem" then watchTotems(); return true end
    if phase == nil then return false end
    if phase == false then
        local up = totemUp(item)
        if up ~= false or item.totem then return up end
    end
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
    local was = alerts[item] == true
    alerts[item] = (ok and up == true) or nil
    if was ~= (alerts[item] == true) then tell("CooldownProc", item, nil, not was) end
end

-- Overpower on Forever: a dodge by your target opens a 5 s window, kept as a
-- hidden buff on you that can't be read in a fight. The game only answers
-- "usable" in Battle Stance, so outside it Overpower never lit up for a warrior
-- who'd swap stances to use it. Outside Battle Stance, the target's dodge
-- (UNIT_COMBAT's action stays plain) opens the window here. It can't tell whose
-- attack was dodged, so in Battle Stance the game's own answer stands.
Fx.OVERPOWER = { [7384] = true, [7887] = true, [11584] = true, [11585] = true }
Fx.OVERPOWER_WINDOW = 5
local dodgedAt = nil

local function overpowerOpen(sid)
    return Fx.OVERPOWER[sid] == true and dodgedAt ~= nil and formNow ~= "Battle"
        and GetTime() - dodgedAt < Fx.OVERPOWER_WINDOW
end

local dodges = CreateFrame("Frame")
dodges:RegisterUnitEvent("UNIT_COMBAT", "target")
dodges:RegisterEvent("PLAYER_TARGET_CHANGED")
dodges:SetScript("OnEvent", function(_, event, _, action)
    if event == "PLAYER_TARGET_CHANGED" then
        if dodgedAt then dodgedAt = nil; Fx.Soon(false) end
        return
    end
    if secret(action) or action ~= "DODGE" then return end
    dodgedAt = GetTime()
    Fx.Soon(false)
    -- Nothing else says when the window ends.
    C_Timer.After(Fx.OVERPOWER_WINDOW + 0.05, function() Fx.Soon(false) end)
end)

-- Castable now, per the game (plain in combat too). A secret or missing answer
-- keeps the last one, so "When not usable" never hides or darkens a spell when
-- it's needed.
local function readUsable(item)
    local b = opts[item]
    local glow = Fx.Get(b, "usableGlow") == true
    if not glow then usable[item] = nil end
    castable[item], short[item] = nil, nil
    if not (glow or kinds[item] == "icon" or Fx.Get(b, "onUnusable") ~= "show"
        or Fx.Get(b, "onShort") ~= "show" or Fx.Get(b, "usableSound") ~= "none"
        or DUI.APIReport.Wants("CooldownUsable")) then return end
    local ok, can, noPower
    local C = ns.CdmCustom
    if C and C.ItemOf(item.cooldownID) then   -- an item with none left in your bags reads not usable
        ok = true
        can, noPower = C.ItemUsable(item.cooldownID)
    else
        local sid = Fx.SpellOf(item)
        if not sid or type(C_Spell) ~= "table" or type(C_Spell.IsSpellUsable) ~= "function" then return end
        if overpowerOpen(sid) then
            ok, can, noPower = true, true, false
        else
            ok, can, noPower = pcall(C_Spell.IsSpellUsable, sid)
        end
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
    if was == false and now then
        playSound(item, opts[item], "usableSound")
        tell("CooldownUsable", item)
    end
end

-- Gray: true, false, or nil for the game's own. An element piece's cooldown totem,
-- once gone, is gray unless Gray out keeps it in color.
local function wantGrey(item)
    local d = Fx.Get(opts[item], "desat")
    if kinds[item] ~= "icon" then return nil end
    if item.slotPhase == "cooldown" and d ~= "color" then return true end
    if d == "game" then return nil end
    if d == "color" then return false end
    return cdState[item] == true
end

local function setGrey(icon, on)
    guard = true
    icon:SetDesaturated(on)
    guard = false
end

-- force = the game just wrote its own gray (the hook), so this one goes back on even if
-- it's the last one written.
local function applyGrey(item, icon, force)
    local want = wantGrey(item)
    if want == nil then
        -- Back to game default: undo this one and the game sets its own next update.
        if greyed[item] then greyed[item] = nil; greyAs[icon] = nil; setGrey(icon, false) end
        return
    end
    greyed[item] = true
    -- Every cooldown event refreshes, so only write on a change.
    if not force and greyAs[icon] == want then return end
    greyAs[icon] = want
    setGrey(icon, want)
end

-- The game grays icons as it updates, so this gray goes on after.
local function hookGrey(item, icon)
    if greyHooked[icon] then return end
    greyHooked[icon] = true
    local function after() if not guard and opts[item] then applyGrey(item, icon, true) end end
    hooksecurefunc(icon, "SetDesaturated", after)
    if type(icon.SetDesaturation) == "function" then hooksecurefunc(icon, "SetDesaturation", after) end
end

-- Not castable: use the game's own Cooldown Manager colors so a spell waiting on a
-- dodge doesn't look ready. Daylight UI's icons ease there FAST; the game's items snap, and
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

-- Daylight UI's own icons and bars ease (FAST, fight info never waits). The game's items snap,
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
-- Gone because it's left out of the form you're in. Keep its spot is about missing
-- buffs, so this one gives its spot up too.
function Fx.GoneForm(item) return gone[item] == "form" end

-- Fade / Hide on cooldown or while ready. Alpha is set here; Hide's spot is handled
-- by CdmRows (Fx.Gone).
local function applyAlpha(item)
    local b, state = opts[item], cdState[item]
    local mode = state == true and Fx.Get(b, "onCd") or state == false and Fx.Get(b, "onReady") or "show"
    local outOfForm = offForm(b)
    -- While its buff is up, Buff up decides (Show, or Hide below): a buff that
    -- starts the cooldown would otherwise sit faded the whole time it's up.
    if down[item] == false then
        mode = "show"
    elseif state == false and castable[item] == false and Fx.Get(b, "onUnusable") ~= "show" then
        mode = Fx.Get(b, "onUnusable")
    elseif state == false and short[item] and Fx.Get(b, "onShort") ~= "show" then
        mode = Fx.Get(b, "onShort")
    end
    -- An element piece with nothing in its slot and no cooldown running hides like
    -- When ready Hide, except in test mode.
    if state == false and item.totem and not DUI.testMode and ns.CdmCustom
        and ns.CdmCustom.Element(item.cooldownID) then
        mode = "hide"
    end
    -- Every Hide gives up its spot (Not usable and Short too; a group growing from
    -- its middle stayed off-center otherwise), as does Buff up Hide on the game's
    -- buff item or Daylight UI's cooldown icon under a buff ("up": Keep its spot only applies
    -- while missing).
    local hideUp = down[item] == false and Fx.Get(b, "hideActive") == true
    local isGone = nil
    if not away[item] then
        if hideUp then isGone = "up"
        elseif outOfForm then isGone = "form"
        elseif mode == "hide" and not buffOnly[item] then isGone = true end
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
    -- Hidden means no tooltip over the empty gap either. Daylight UI's own frames don't take
    -- the mouse, so they're left alone.
    if own[item] then return end
    if a == 0 then
        mouseOff[item] = true
        item:EnableMouse(false)
    elseif mouseOff[item] then
        mouseOff[item] = nil
        Fx.GameMouse(item)
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

-- The stance you're in: a wash over its icon in the buff-up color, as a druid's form
-- shows while its buff is up. The same switches turn it off (activeGlow,
-- noDurationSwipe). It changes the moment the stance does.
local stanceWash = setmetatable({}, weak)   -- item -> its wash texture
local STANCE_ALPHA = 0.5

local function wantsStance(item)
    local b = opts[item]
    if not b or kinds[item] ~= "icon" or formNow == nil then return false end
    if Fx.Get(b, "activeGlow") == false or Fx.Get(b, "noDurationSwipe") == true then return false end
    local sid = Fx.SpellOf(item)
    return sid ~= nil and litBySpell[sid] == formNow
end

local function applyStance(item)
    local on = wantsStance(item)
    local t = stanceWash[item]
    if not t then
        if not on then return end
        t = item:CreateTexture(nil, "OVERLAY", nil, 1)
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        t:SetBlendMode("ADD")
        t:SetAlpha(0)
        stanceWash[item] = t
    end
    local icon = ns.Cooldowns.IconOf(item) or item.Icon
    t:ClearAllPoints()
    t:SetAllPoints(type(icon) == "table" and icon or item)
    if on then
        local c = Fx.ActiveColor(opts[item])
        t:SetVertexColor(c[1], c[2], c[3])
    end
    local to = on and STANCE_ALPHA or 0
    if t.__on == on then return end
    t.__on = on
    t:Show()
    Motion.Tween(t, t:GetAlpha(), to, Motion.FAST, function(a) t:SetAlpha(a) end)
end
Fx.StanceShown = function(item)
    local t = stanceWash[item]
    return t ~= nil and t.__on == true
end

local function refresh(item, read)
    if not opts[item] then return end
    applyStance(item)
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

-- What a held item reads now, every answer plain (nil = the game won't say). For
-- plugins (DaylightUI.API.CooldownState): the same answers Daylight UI's own effects go by.
function Fx.State(item, into)
    local t = into or {}
    local cd = cdState[item]
    if buffOnly[item] then cd = nil end
    t.onCooldown = cd
    if cd ~= nil then t.ready = not cd else t.ready = nil end
    local c = castable[item]
    if type(c) == "boolean" then t.usable = c and not short[item]; t.noPower = short[item] == true
    else t.usable, t.noPower = nil, nil end
    t.proc = alerts[item] == true
    if type(down[item]) == "boolean" then t.buffUp = not down[item] else t.buffUp = nil end
    t.glowing = lit[item] == true
    return t
end
refreshNow = function(item) refresh(item, false) end

-- Whether a piece's buff is down (true), up (false) or unknown (nil), reported by
-- CdmRows each pass after Fx.Apply. An item not otherwise held (a stand-in, an
-- aura holder) only gets the missing glow, from button.
local looseLit = setmetatable({}, weak)
function Fx.SetDown(item, button, isDown, isDue)
    down[item], due[item] = isDown, isDue
    if opts[item] then refreshNow(item); return end
    local want = buffGlow(button, isDown, isDue)
    looseLit[item] = want and true or nil
    showGlow(item, want, button)
end

-- After a pass, loose items it didn't report on lose their glow, and a held item it
-- didn't report on (the game hid it as its buff dropped) forgets up or down so a
-- buff glow isn't left on it.
function Fx.EndPass(told)
    for item in pairs(looseLit) do
        if not told[item] then looseLit[item] = nil; down[item] = nil; due[item] = nil; showGlow(item, false) end
    end
    for item in pairs(opts) do
        if not told[item] and down[item] ~= nil then down[item] = nil; due[item] = nil; refreshNow(item) end
    end
end

-- Runs after each placement pass for every held item (CdmRows). isOwn = Daylight UI's own
-- icon or bar (CdmOwn, CdmBars), not the game's item.
function Fx.Apply(item, button, kind, isOwn, onlyBuff)
    opts[item], kinds[item] = button, kind
    own[item] = isOwn or nil
    -- Buff only has no cooldown rows on its card, so any old values there are ignored.
    buffOnly[item] = onlyBuff or nil
    local cd = type(item.Cooldown) == "table" and item.Cooldown or nil
    -- No event fires when a cooldown ends, but its own frame does (Daylight UI's bars' time
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

-- The item is released: undo everything changed on it.
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
    local wash = stanceWash[item]
    if wash then
        Motion.Tween(wash, 0, 0, 0)
        wash.__on = nil
        wash:SetAlpha(0)
    end
    if mouseOff[item] then mouseOff[item] = nil; Fx.GameMouse(item) end
    cdState[item], away[item], usable[item], castable[item], down[item] = nil, nil, nil, nil, nil
    short[item] = nil
    buffOnly[item] = nil
    wasUsable[item], realCool[item], armed[item], castAt[item] = nil, nil, nil, nil
    showGlow(item, false)
    opts[item], kinds[item], own[item] = nil, nil, nil
end

-- Cooldowns moved: update only the held items.
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
    if Fx.OVERPOWER[sid] and dodgedAt then dodgedAt = nil; Fx.Soon(false) end
    DUI.SafeCall(Fx.Armed, sid)
end)

-- Runs once on the next frame however many events came in. A cast sends two to four
-- cooldown and charge events, so the held items (and Daylight UI's own icons) are
-- redone once, not per event. For a proc, the game shows its alert in its own handler for the same
-- event, so this reads it a frame later anyway.
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
DUI.RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", procSoon)
DUI.RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", procSoon)
-- A spell turning castable or not (a block for Revenge, rage, the target's health).
DUI.RegisterEvent("SPELL_UPDATE_USABLE", procSoon)
DUI.RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", procSoon)

DUI.RegisterEvent("SPELL_UPDATE_COOLDOWN", cooldownSoon)
DUI.RegisterEvent("SPELL_UPDATE_CHARGES", cooldownSoon)
-- A totem going down or up: the game's icon times it (Fx.OnCooldown).
DUI.RegisterEvent("PLAYER_TOTEM_UPDATE", cooldownSoon)
-- Items added by ID (CdmCustom): their cooldown and their bag count, which shows on
-- Daylight UI's icons and bars (none left grays them).
DUI.RegisterEvent("BAG_UPDATE_COOLDOWN", cooldownSoon)
DUI.RegisterEvent("BAG_UPDATE_DELAYED", cooldownSoon)
DUI.RegisterEvent("PLAYER_REGEN_ENABLED", function() Fx.UpdateAll() end)
-- Test mode shows the empty element pieces.
DUI.On("TestModeChanged", function() Fx.UpdateAll() end)

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
    DUI.RegisterEvent(e, function() DUI.SafeCall(formChanged) end)
end
