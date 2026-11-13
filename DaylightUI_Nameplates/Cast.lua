-- A plate's cast bar, attached under the health bar as one piece that continues
-- its angled end: spell icon, name and time. Every cast looks the same, because
-- the game's interruptible flag says "can be interrupted" for many casts that
-- can't be (Melt Ore, for one), so nothing here reads it.

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel

local Cast = {}
ns.Cast = Cast

Cast.EVENTS = {
    UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_INTERRUPTED = true, UNIT_SPELLCAST_DELAYED = true,
    UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_CHANNEL_UPDATE = true, UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_EMPOWER_START = true, UNIT_SPELLCAST_EMPOWER_UPDATE = true, UNIT_SPELLCAST_EMPOWER_STOP = true,
}
-- The cast bar's own border: slim and plain so it reads at a glance.
Cast.BORDER = 2
Cast.GAP = 3 -- gap between the health bar and the cast bar
Cast.TEXT = 0.7 -- spell and time text, as a fraction of the bar's height
Cast.ICON_GAP = 2 -- gap between the spell icon and the bar
Cast.TIME_EVERY = 0.05 -- seconds between time text updates (it shows tenths)
Cast.INTERRUPTED = { 0.85, 0.22, 0.2 }
Cast.FLASH = 0.85 -- peak brightness of the interrupt's white flash on the fill
Cast.INTERRUPTED_FOR = 0.5 -- seconds the "Interrupted" bar stays

-- Cast color: this setting, else the shared one.
local function castColor()
    local c = ns.cfg or {}
    return c.castColor or Style.CAST.normal
end

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- A piece claimed by a plugin (DaylightUI.API's Paint, kind "platecast": the
-- same pieces as the unit frames' "castbar") is left to it.
local function owned(part)
    local R = DUI.APIReport
    return type(R) == "table" and R.Owned("platecast", part) == true
end

-- Every paint of a plate's cast bar ends here, so plugins can apply their look.
-- A plate not yet handed to the API (still being set up) is painted once it is.
function Cast.Painted(p)
    local R = DUI.APIReport
    if not (type(R) == "table" and R.Painting("platecast") and p.apiSeen) then return end
    local c = p.cast
    R.Painted("platecast", c, { unit = p.unit, spellID = c.spellID, channel = c.channel == true,
        notInterruptible = c.notInterruptible, interrupted = c.interrupted == true })
end

function Cast.Create(p)
    local c = CreateFrame("Frame", nil, p)
    -- Slim and plain, continuing the health bar's angle along its top (Body.lua's
    -- shell look, no masks).
    c.body = ns.Body.New(c, { borderPx = Cast.BORDER, flat = true, joined = true })
    c.bar = Style.Bar(c, nil, ns.Plate.MEDIA.bars.cast)
    -- Optional spell icon: a small bordered square left of the bar, clear of its
    -- rounded end.
    c.iconBox = CreateFrame("Frame", nil, c)
    c.iconBack = c.iconBox:CreateTexture(nil, "BACKGROUND")
    c.iconBack:SetColorTexture(0, 0, 0, 1)
    c.iconBack:SetAllPoints(c.iconBox)
    c.icon = c.iconBox:CreateTexture(nil, "ARTWORK")
    c.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    local over = CreateFrame("Frame", nil, c)
    over:SetAllPoints(c)
    over:SetFrameLevel(c.bar:GetFrameLevel() + 3)
    c.text = Style.Text(over, 9, "LEFT", ns.Plate.MEDIA.fonts.cast)
    c.time = Style.Text(over, 9, "RIGHT", ns.Plate.MEDIA.fonts.cast)
    -- Who the cast is aimed at (castTarget), left of the time.
    c.target = Style.Text(over, 9, "RIGHT", ns.Plate.MEDIA.fonts.cast)
    c.target:Hide()
    -- The interrupt hit: a flat light on the fill, clipped to the fill's shape (its
    -- angled moving edge and the bar's end).
    c.light = c.bar:CreateTexture(nil, "ARTWORK", nil, 3)
    c.light:SetTexture("Interface\\Buttons\\WHITE8x8")
    c.light:SetBlendMode("ADD")
    c.light:SetAllPoints(c.bar:GetStatusBarTexture())
    -- Toggled through alpha only. A texture's vertex color alpha and SetAlpha are the
    -- same number, so a clear color followed by SetAlpha(1) left every cast bar white.
    c.light:SetAlpha(0)
    -- Where your interrupt comes off cooldown (castKickMark), under the texts.
    c.kickMark = DUI.Interrupt.NewMark(c.bar)
    c:Hide()
    p.cast = c
    -- The kick animation (Motion.Kick) and the interrupter's name live on the plate,
    -- so they outlast the bar's hold.
    p.blade = DUI.Motion.NewBlade(p)
    p.kickTag = DUI.Motion.NewKickTag(p, ns.Plate.MEDIA.fonts.cast)
end

-- The bar's shape for the kick pieces (Motion.LayPiece): its right end leaning
-- with the angle (x at y down, inset px in from its edge), the border and the
-- interrupted red. nil until the bar is laid out.
local function shape(c)
    local g = c.body.geo
    if not g then return nil end
    local W, H = g.W, g.H
    return {
        right = function(y, inset) return W - g.cutTop - g.lean * y / H - inset * g.slope end,
        T = g.T, edge = Style.BORDER, fill = Cast.INTERRUPTED,
    }
end

-- by is the interrupter's GUID from the event. Your own kick (plain and yours)
-- lights in the accent; anyone else's, or a secret one, in warm white. Plays the
-- chosen kickStyle and shows who kicked it (kickedBy).
function Cast.Kicked(p, by, style)
    local k, c = p.blade, p.cast
    if not (k and c.body) then return end
    local me = UnitGUID("player")
    local mine = type(by) ~= "nil" and not isSecret(by) and not isSecret(me) and by == me
    local r, g, b
    if mine then r, g, b = Style.Accent() else r, g, b = unpack(DUI.Motion.BLADE_EDGE) end
    DUI.Motion.Kick(k, c, style or ns.cfg.kickStyle, r, g, b, shape(c))
    if ns.cfg.kickedBy then Cast.KickedBy(p, by) end
end

-- The "Kicked by" tag, right of the cast bar or under it (kickedByPos).
function Cast.KickedBy(p, by)
    local t, c = p.kickTag, p.cast
    if not t then return end
    t:ClearAllPoints()
    if ns.cfg.kickedByPos == "below" then
        t:SetPoint("TOPLEFT", c, "BOTTOMLEFT", 2, -3)
    else
        t:SetPoint("LEFT", c, "RIGHT", 4, 0)
    end
    t:SetFrameLevel(c:GetFrameLevel() + 8)
    DUI.Motion.KickTag(t, by, "nameplates", math.max(8, math.floor((ns.cfg.castHeight or 14) * Cast.TEXT + 0.5)))
end

-- The hit on the bar itself: its red fill flashes white-hot and cools, through
-- the light (already clipped to the fill's shape).
local function flashHit(c)
    DUI.Motion.Tween(c.light, Cast.FLASH, 0, DUI.Motion.SLOW, function(a) c.light:SetAlpha(a) end)
end

-- A new cast or the plate going away: the blade and the hit flash stop at once.
function Cast.Unkick(p)
    local c = p.cast
    if c and c.light then
        DUI.Motion.Tween(c.light, 0, 0, 0) -- ends the flash (a new cast recolors it)
        c.light:SetAlpha(0)
    end
    DUI.Motion.Unblade(p.blade)
end

-- The time text shows tenths. One shared frame updates every casting plate's time
-- every Cast.TIME_EVERY seconds, and only runs while a plate is casting (15+
-- casters in a pull each running their own OnUpdate was too much). A new cast's
-- time is written right away (Cast.Update).
local casting = {} -- cast bar -> true while it shows a timed cast
local ticker = CreateFrame("Frame")
ticker:Hide()
Cast.Ticker = ticker
local since = 0

local function writeTime(c)
    local d = c.duration
    if d and c.time:IsShown() then c.time:SetFormattedText("%.1f", d:GetRemainingDuration()) end
end

ticker:SetScript("OnUpdate", function(self, dt)
    since = since + (dt or 0)
    if since < Cast.TIME_EVERY then return end
    since = 0
    if next(casting) == nil then
        self:Hide()
        return
    end
    -- A bar the game has closed to addons (its plate is forbidden) drops out; the rest
    -- keep updating.
    for c in pairs(casting) do
        if not pcall(writeTime, c) then casting[c] = nil end
    end
end)

local function startTime(c)
    casting[c] = true
    writeTime(c)
    if not ticker:IsShown() then
        since = 0
        ticker:Show()
    end
end

local function stopTime(c)
    casting[c] = nil
end

-- A plate leaving whose cast bar can't be stopped normally (Uninstall skipped
-- because its frame is closed to addons): drop it from the ticker anyway.
function Cast.Forget(p)
    if type(p) == "table" and p.cast then casting[p.cast] = nil end
end

-- cut: the health bar's angled end, continued down through this bar.
function Cast.Layout(p, cut)
    local c, cfg, hp = p.cast, ns.cfg, p.hp
    p.castStale = nil
    -- Match the health bar's width (Width times the target/others multiplier, if
    -- any) so the cast bar always lines up under it.
    local w, h = hp:GetWidth(), cfg.castHeight
    -- Just under the health bar with a small gap. The angled end is measured from the
    -- health bar's top corner across both, so the line continues across the gap and
    -- down this bar. Sits below the power bar (Power.lua) and, on your target's
    -- plate, the combo points (Combo.lua).
    local hh = hp:GetHeight()
    local gap = Cast.GAP + (ns.Combo and ns.Combo.Drop(p) or 0) + (ns.Power and ns.Power.Drop(p) or 0)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", hp, "TOPLEFT", tonumber(cfg.castX) or 0, -(hh + gap) + (tonumber(cfg.castY) or 0))
    c:SetSize(w, h)
    c:SetFrameLevel(hp:GetFrameLevel() + 4)
    local total = hh + gap + h
    local line = (cut or 0) > 0 and cut * total / hh or 0
    -- Where the line is at this bar's top and bottom, measured in from its right edge
    -- (and for a see-through border's shell, where it starts and over what).
    local ref = c.body.opts.ref or {}
    c.body.opts.ref = ref
    ref.frame, ref.height = hp, total
    ns.Body.Layout(c.body, line > 0 and line * (hh + gap) / total or 0, line)
    local T = c.body.T
    c.iconBox:ClearAllPoints()
    if cfg.castIconPos == "outright" then
        c.iconBox:SetPoint("TOPLEFT", c, "TOPRIGHT", Cast.ICON_GAP, 0)
    else
        c.iconBox:SetPoint("TOPRIGHT", c, "TOPLEFT", -Cast.ICON_GAP, 0)
    end
    c.iconBox:SetSize(h, h)
    c.iconBox:SetShown(cfg.castIcon and true or false)
    c.icon:ClearAllPoints()
    c.icon:SetPoint("TOPLEFT", c.iconBox, "TOPLEFT", T, -T)
    c.icon:SetPoint("BOTTOMRIGHT", c.iconBox, "BOTTOMRIGHT", -T, T)
    -- The fill's moving edge carries the same angle (its one mask).
    ns.Body.FitBar(c.body, c.bar)
    local size = math.max(8, math.floor(h * Cast.TEXT + 0.5))
    Style.SetTextSize(c.text, size)
    Style.SetTextSize(c.time, size)
    Style.SetTextSize(c.target, size)
    -- The time text sits inside the angled end, inset from where the slant meets the
    -- text's bottom edge. This bar's cut runs from its top to its bottom, both
    -- carrying the health bar's line further in than its own end.
    local g = c.body.geo
    local edge = g and (g.cutTop + g.lean * (0.5 + Cast.TEXT * 0.5)) or 0
    c.time:ClearAllPoints()
    c.time:SetPoint("RIGHT", c, "RIGHT", -(T + 2 + edge), 0)
    c.target:ClearAllPoints()
    c.target:SetPoint("RIGHT", c.time, "LEFT", -4, 0)
    c.text:ClearAllPoints()
    c.text:SetPoint("LEFT", c.bar, "LEFT", 3, 0)
    -- The spell name gives way to the target's name. Its width can be secret (the
    -- name is), which is fine to anchor to; nothing reads it back.
    c.text:SetPoint("RIGHT", cfg.castTarget ~= false and c.target or c.time, "LEFT", -3, 0)
    -- The light uses the fill's angled moving edge too (same mask).
    local fm = Style.GetFillMask(c.bar)
    if fm and c.lightMask ~= fm then
        if pcall(c.light.AddMaskTexture, c.light, fm) then c.lightMask = fm end
    end
end

local WHITE = CreateColor(1, 1, 1, 1)

-- The fill is the same for every cast: one color, the Daylight gradient, or the
-- Gradients page's Cast / Channel pair.
local function paintFill(c, channel)
    -- A plugin's fill: white under its texture, no gradient; the empty part in
    -- the cast color unless the plugin holds that too.
    if owned("fill") then
        Style.SetBarGradient(c.bar, false)
        c.bar:GetStatusBarTexture():SetVertexColor(1, 1, 1, 1)
        if not owned("back") then
            local col = castColor()
            ns.Plate.SetBackColor(c.bar, col[1], col[2], col[3])
        end
        return
    end
    local mode = ns.cfg.castFill
    local G = mode == "pair" and DUI.Gradients
    local sweep = Style.SetBarGradient(c.bar, mode == "daylight" and not G)
    if G then
        G.Paint(c.bar, channel and "CHANNEL" or "CAST")
        return
    end
    if mode == "daylight" then
        -- gradients off: SetBarGradient already painted it flat
        if sweep then Style.SetBarColor(c.bar, 1, 1, 1) end
    else
        local col = castColor()
        Style.SetBarColor(c.bar, col[1], col[2], col[3])
    end
end

-- The space under the health bar changed (the combo row came or went). Lay out
-- now if the bar shows, else on its next show; otherwise every rogue target switch
-- re-laid out two hidden cast bars.
function Cast.Relayout(p)
    if p.cast:IsShown() then Cast.Layout(p, p.hpCut) else p.castStale = true end
end

-- Reads the unit's cast (or channel) and shows it, or hides the bar.
function Cast.Update(p)
    local c, u = p.cast, p.unit
    if not u or p.friendly then return Cast.Stop(p) end
    -- displayName, as the game's own bar uses: the first value can be an untranslated name.
    -- The flag and spell id are only kept for plugins (Cast.Painted), passed on whole.
    local _, name, texture, _, _, _, _, ni, spellID = UnitCastingInfo(u)
    local channel = false
    if type(name) == "nil" then
        _, name, texture, _, _, _, ni, spellID = UnitChannelInfo(u)
        channel = type(name) ~= "nil"
    end
    if type(name) == "nil" then return Cast.Stop(p) end
    local duration
    if channel then
        duration = UnitChannelDuration and UnitChannelDuration(u)
    else
        duration = UnitCastingDuration and UnitCastingDuration(u)
    end
    if not duration then return Cast.Stop(p) end
    if p.castStale then Cast.Layout(p, p.hpCut) end
    c.token = (c.token or 0) + 1
    c.duration, c.channel = duration, channel
    c.spellID, c.notInterruptible, c.interrupted = spellID, ni, nil
    local dir = Enum.StatusBarTimerDirection
    c.bar:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate,
        channel and dir.RemainingTime or dir.ElapsedTime)
    c.text:SetText(name)
    c.icon:SetTexture(texture)
    c.time:Show()
    Cast.UpdateTarget(c, u)
    Cast.Unkick(p)
    paintFill(c, channel)
    Cast.UpdateKickMark(c)
    c.leaving = nil
    DUI.Motion.AlphaTo(c, 1, 0) -- immediately, ending any fade-out in progress
    startTime(c)
    ns.Plate.Dim(p)
    Cast.Painted(p)
end

-- The cast's target in its class color (castTarget, on by default). The client
-- always hands the name and class over secret, so both go whole to the text: the
-- name to SetText, the class through the game's own class color to SetTextColor.
-- No answer (an area spell, a self cast) leaves it empty.
local function targetColor(fs, class)
    if type(class) ~= "nil" and C_ClassColor and C_ClassColor.GetClassColor then
        local ok, col = pcall(C_ClassColor.GetClassColor, class)
        if ok and type(col) == "table" and not isSecret(col) then
            fs:SetTextColor(col.r, col.g, col.b)
            return
        end
    end
    Style.InkText(fs, "VALUE")
end

function Cast.UpdateTarget(c, u)
    local fs = c.target
    if ns.cfg.castTarget == false or type(UnitSpellTargetName) ~= "function" then
        fs:SetText("")
        fs:Hide()
        return
    end
    local ok, name = pcall(UnitSpellTargetName, u)
    if not ok or type(name) == "nil" then name = "" end
    fs:SetText(name)
    local class
    if type(UnitSpellTargetClass) == "function" then
        local got, cls = pcall(UnitSpellTargetClass, u)
        if got then class = cls end
    end
    targetColor(fs, class)
    fs:Show()
end

-- Your interrupt's ready mark on a running cast (castKickMark).
-- fade: the cooldown changed mid-cast.
function Cast.UpdateKickMark(c, fade)
    if ns.cfg.castKickMark == false or not c.duration then
        DUI.Interrupt.HideMark(c.kickMark)
        return
    end
    DUI.Interrupt.ShowMark(c.kickMark, c.duration, c.channel, fade)
end

-- Your interrupt went on or came off cooldown (or changed): the bars casting now.
DUI.On("InterruptChanged", function()
    for c in pairs(casting) do DUI.SafeCall(Cast.UpdateKickMark, c, true) end
end)

-- Options preview (Sample.lua): a cast frozen partway, painted like a real one
-- (s: { text, icon, value 0-1, time }), or nil for none.
function Cast.ShowSample(p, s)
    local c = p.cast
    Cast.sample = p
    if not s then
        Cast.Stop(p, true)
        return
    end
    if p.castStale then Cast.Layout(p, p.hpCut) end
    Cast.Unkick(p)
    c.duration = nil
    c.bar:SetMinMaxValues(0, 1)
    c.bar:SetValue(s.value)
    -- Your interrupt back a little before the cast ends.
    local m = c.kickMark
    if ns.cfg.castKickMark ~= false and s.kick then
        DUI.Interrupt.PlaceMark(m, 0, 1, s.kick, false)
        DUI.Motion.AlphaTo(m.clip, 1, 0)
    else
        DUI.Interrupt.HideMark(m)
    end
    c.text:SetText(s.text)
    c.icon:SetTexture(s.icon)
    c.time:SetText(s.time)
    c.time:Show()
    if ns.cfg.castTarget ~= false and s.target then
        c.target:SetText(s.target)
        c.target:SetTextColor(Style.ClassTextColor(s.targetClass))
        c.target:Show()
    else
        c.target:Hide()
    end
    c.spellID, c.channel, c.notInterruptible, c.interrupted = nil, false, false, nil
    paintFill(c, false)
    c.leaving = nil
    DUI.Motion.AlphaTo(c, 1, 0)
    Cast.Painted(p)
end

-- Options window: play an interrupt on the preview plate (the last one shown) as
-- your own kick. style is the one hovered in the list, else the chosen one a
-- moment later (the preview refresh from the setting change would cut it short).
function Cast.PlaySample(style)
    local function play()
        local p = Cast.sample
        if not (p and p:IsVisible() and p.cast:IsShown()) then return end
        Cast.Kicked(p, UnitGUID("player"), style)
    end
    if style then play() else C_Timer.After(0.05, play) end
end

-- A finished cast fades out FAST (c.leaving meanwhile, so it counts as gone in
-- Cast.Shown). snap: hide at once (plate leaving, the preview).
function Cast.Stop(p, snap)
    local c = p.cast
    c.duration = nil
    stopTime(c)
    DUI.Interrupt.HideMark(c.kickMark)
    if snap or not c:IsShown() then
        c.leaving = nil
        DUI.Motion.AlphaTo(c, 0, 0, true)
    elseif not c.leaving then
        c.leaving = true
        DUI.Motion.AlphaTo(c, 0, DUI.Motion.FAST, true)
    end
    ns.Plate.Dim(p)
end

-- A cast on the bar now, not one fading out.
function Cast.Shown(p)
    return p.cast:IsShown() and not p.cast.leaving
end

-- Interrupted: red, "Interrupted", then gone.
function Cast.Interrupted(p)
    local c = p.cast
    if not c:IsShown() then return end
    c.leaving = nil
    c.duration = nil
    stopTime(c)
    DUI.Interrupt.HideMark(c.kickMark)
    c.token = (c.token or 0) + 1
    local mine = c.token
    c.bar:SetMinMaxValues(0, 1)
    c.bar:SetValue(1)
    -- A plugin's fill keeps its look; info.interrupted tells it to show the red.
    c.interrupted = true
    if not owned("fill") then
        local col = Cast.INTERRUPTED
        local fill = c.bar:GetStatusBarTexture()
        Style.SetBarGradient(c.bar, false)
        if fill.SetGradient then fill:SetGradient("HORIZONTAL", WHITE, WHITE) end
        fill:SetVertexColor(col[1], col[2], col[3], 1)
    end
    c.text:SetText(INTERRUPTED or "Interrupted")
    c.time:Hide()
    c.target:Hide()
    flashHit(c)
    Cast.Painted(p)
    C_Timer.After(Cast.INTERRUPTED_FOR, function()
        if c.token == mine then Cast.Stop(p) end
    end)
end

-- ... is the event payload. An interrupt's 4th value is the interrupter, maybe secret.
function Cast.OnEvent(p, event, ...)
    if event == "UNIT_SPELLCAST_INTERRUPTED" then
        -- The stop can arrive first and start the fade. Bring it back at once (before the
        -- kick hides the bar under its pieces) so the red shows.
        if p.cast.leaving then
            p.cast.leaving = nil
            DUI.Motion.AlphaTo(p.cast, 1, 0)
        end
        if p.cast:IsShown() then Cast.Kicked(p, (select(4, ...))) end
        Cast.Interrupted(p)
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        -- A stop can be followed right away by the next cast's start.
        if p.cast.duration then Cast.Update(p) end
    else
        Cast.Update(p)
    end
end

-- What plugins get from a plate's cast bar (DaylightUI.API's Paint, kind
-- "platecast", the same pieces as "castbar"), and how it gets its own look back.
if DUI.APIReport then
    DUI.APIReport.Parts("platecast", function(c)
        return { fill = c.bar:GetStatusBarTexture(), bar = c.bar, back = Style.BarBack(c.bar),
                 name = c.text, time = c.time, icon = c.icon }
    end)
    DUI.APIReport.Repainter("platecast", function(c)
        if not owned("fill") then Style.ResetBarFill(c.bar) end -- drop the plugin's texture
        local p = c:GetParent()
        if c.interrupted or not Cast.Shown(p) then return end
        paintFill(c, c.channel)
    end)
end
