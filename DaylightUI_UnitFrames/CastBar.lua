-- Cast bars. The client drives the fill from a duration object and picks
-- the interruptible color from a (possibly secret) flag, so no cast timing
-- is ever read or computed here. Every cast event just re-asks the client
-- what the unit is casting now. The player's bar stands alone; the target's
-- sits inside the target frame over its power bar while a cast runs.
-- Colors (casting, channeling, can't be interrupted, interrupted), the
-- spell name and the timer's format are settings (db.casts, CB.Configure).
-- An interrupted cast can stay up a moment, full and red, saying so.

local _, ns = ...
local DUI = DaylightUI
local isSecret = DUI.IsSecret
local Style, Pixel = DUI.Style, DUI.Pixel

local CB = {}
ns.CastBar = CB

-- Text inside a power bar is as tall as the bar, never under the smallest
-- text size: a smaller one was hard to read mid-fight, and the outline keeps
-- a letter that pokes past a thin bar readable.
function CB.FitText(barHeight)
    return math.max(DUI.Style.SIZE.tiny, math.floor(barHeight + 0.5))
end
CB.TEXT_SIZE = 12    -- a text's size when it has none saved
CB.PAD = 3            -- the text's distance from the bar's ends

local EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

CB.HOLD = 0.6         -- seconds an interrupted cast stays up
CB.SLIDE = 0.2        -- seconds the bar under the player frame takes to slide out or back
CB.CLIP_MARGIN = 30   -- the slide's clip reaches this far past the frame's sides, for shadows
CB.AT_GAP = 6         -- gap between a frame and a cast bar above or below it

-- Where each bar may sit (setting "at"), default first. The player's hangs
-- under its frame ("below", sliding out), the target's and focus's cover the
-- power bar ("power"). Any of them can sit above or below its frame at its own
-- size ("above", "below") or stand on its own mover ("free"). The target's can
-- also hang under its frame ("slide"), mirroring the player's, and so can the focus's. The player's
-- can sit between its frame and the target's ("middle"): both ends angled,
-- wider at the bottom, each end parallel to the frame beside it, with the
-- swing timers fanning out underneath (Swing.lua).
CB.AT = {
    player = { "below", "above", "middle", "free" },
    target = { "power", "above", "below", "slide", "free" },
    focus = { "power", "above", "below", "slide", "free" },
    -- Each party member's (PartyCasts.lua): "free" sits beside its frame.
    party = { "power", "slide", "free" },
}
CB.AT_LABELS = { power = "Inside the frame", above = "Above the frame", below = "Below the frame",
                 slide = "Under the frame (slides out)", middle = "Between your frame and the target's",
                 free = "On its own (unlock to move)" }

-- The spot a bar's settings ask for, or the unit's default. In a style whose
-- power is a thin line under the frame (ns.STYLES line), a bar meant to sit inside the frame sits below it at its
-- own size instead. The same goes for a frame without a power bar to sit on
-- (UF.ShowsPower) or whose power bar stands on its own (powerAt "free").
function CB.At(unit, cfg)
    -- Standing under the personal display (its page's switch, placed by Personal.Dock).
    if unit == "player" and ns.Personal.Docks("castbar") then return "personal" end
    local list = CB.AT[unit] or CB.AT.target
    local at = type(cfg) == "table" and cfg.at
    local found = list[1]
    for _, v in ipairs(list) do
        if v == at then found = at end
    end
    if found == "power" then
        local db = ns.module and ns.module.db
        local u = type(db) == "table" and db[unit]
        if type(u) == "table" and (ns.UF.StyleDef(u).line or ns.UF.StyleDef(u).backdrop or not ns.UF.ShowsPower(u) or u.powerAt == "free") then
            -- A party bar has no "below" and hangs under its frame instead.
            return unit == "party" and "slide" or "below"
        end
    end
    return found
end

-- How far up past the bottom of frame f a bar hung under it tucks: the frame's
-- border, so the borders overlap. In Ribbon it goes under the power line,
-- overlapping the line's border (negative means below the frame's bottom).
function CB.Lift(f, fT)
    local line = f.line
    if (f.foot or 0) > 0 and line then return Pixel.Px(line, Style.BorderPx(line)) - f.foot end
    return fT
end

-- A bar at its own size above or below frame f, centered and nudged by x/y.
-- Above clears the name tab when there is one. Protected parent, so out of
-- combat only (layout runs through AfterCombat).
function CB.PlaceAt(h, f, at, x, y)
    x, y = tonumber(x) or 0, tonumber(y) or 0
    h:ClearAllPoints()
    if at == "above" then
        local rel = (f.tab and f.tab:IsShown()) and f.tab or f
        h:SetPoint("BOTTOM", rel, "TOP", x, CB.AT_GAP + y)
    else
        -- Under Ribbon's power line too (f.foot).
        h:SetPoint("TOP", f, "BOTTOM", x, -CB.AT_GAP - (f.foot or 0) + y)
    end
end

local clipIn, textOpt
local function color(c) return CreateColor(c[1], c[2], c[3], 1) end
local WHITE = CreateColor(1, 1, 1, 1)
-- The colors and text settings, from db.casts (CB.Configure).
CB.cfg = { cast = Style.CAST.normal, channel = Style.CAST.normal, locked = Style.CAST.locked,
           interrupted = { 0.52, 0.17, 0.15 }, flash = true,
           kickStyle = "blade", kickedBy = true, kickedByPos = "right", kickMark = false }
-- Each bar's colors (class color, cast, channel, can't interrupt, interrupted):
-- yours from db.casts, the target's from db.targetCasts.
local palettes = {}          -- "player" / "target" -> { cfg, normal, channel, locked }
local marked = {}            -- bars with an interrupt mark (target and focus)

local function palette(c)
    return { cfg = c, normal = color(c.cast), channel = color(c.channel), locked = color(c.locked) }
end
palettes.player = palette(CB.cfg)

-- cfg: the shared settings and your bar's colors. target: the target bar's
-- colors (defaults to yours).
function CB.Configure(cfg, target)
    if type(cfg) ~= "table" then return end
    CB.cfg = cfg
    palettes.player = palette(cfg)
    palettes.target = type(target) == "table" and palette(target) or nil
end

-- A bar's colors: the target's own for a target bar, else yours.
local function colorsOf(h)
    return (h.unit ~= "player" and palettes.target) or palettes.player
end

-- A piece claimed by a plugin (DaylightUI.API's Paint, kind "castbar") is left
-- to it and never colored or textured here.
local function owned(part)
    local R = DUI.APIReport
    return type(R) == "table" and R.Owned("castbar", part) == true
end
-- The empty part, unless a plugin claimed it.
local function backOf(h)
    if owned("back") then return nil end
    return Style.BarBack(h.bar)
end

-- A bar's spell name or time setting, with what it means when unset.
local TEXT_DEFAULTS = {
    spell = { show = true, pos = "left", color = { 1, 1, 1 } },
    time = { show = true, pos = "right", format = "left", color = { 1, 1, 1 } },
}
function textOpt(t, key, kind)
    local v
    if type(t) == "table" then v = t[key] end
    if type(v) == "nil" then return TEXT_DEFAULTS[kind][key] end
    return v
end
local function showsName(h) return textOpt(h.spellCfg, "show", "spell") ~= false end
local function timeMode(h)
    if textOpt(h.timeCfg, "show", "time") == false then return "none" end
    return textOpt(h.timeCfg, "format", "time")
end

-- The timer's text: time left, left / total, or none.
function CB.WriteTime(h, d)
    local mode = timeMode(h)
    if mode == "none" then
        h.time:SetText("")
    elseif mode == "total" and d.GetTotalDuration then
        h.time:SetFormattedText("%.1f / %.1f", d:GetRemainingDuration(), d:GetTotalDuration())
    else
        h.time:SetFormattedText("%.1f", d:GetRemainingDuration())
    end
end

-- into: a bar inside attachTo to cover while casting (the target's power bar).
-- Without it the cast bar is a standalone shelled frame.
-- opts (party members, PartyCasts.lua): kind is the settings unit ("party"),
-- parent is the frame a standalone bar lives in (no name and no mover, so it
-- inherits that frame's scale and fade). unit may be nil until the frame has
-- one (CB.SetUnit).
function CB.Create(unit, attachTo, into, opts)
    opts = opts or {}
    local home = opts.parent or UIParent
    local name = not attachTo and not opts.parent and ("DaylightUICastBar_" .. unit) or nil
    local h = CreateFrame("Frame", name, attachTo or home)
    h.unit, h.attached, h.into = unit, attachTo, into
    h.kind, h.home, h.inFrame = opts.kind or unit, home, type(opts.parent) ~= "nil"
    if into then
        -- Opaque, so the power bar underneath doesn't show through.
        h:SetFrameLevel(into:GetFrameLevel() + 2)
        h.bg = h:CreateTexture(nil, "BACKGROUND")
        h.bg:SetAllPoints(h)
        local b = Style.BACKGROUND
        h.bg:SetColorTexture(b[1], b[2], b[3], 1)
    else
        Style.Shell(h)
        Style.Slant(h, nil, 0)
    end
    local media = ns.UF.MEDIA.cast[h.kind] or ns.UF.MEDIA.cast.target
    h.bar = Style.Bar(h, nil, media.bar)
    -- Its bar animation is the cast bar's own (<kind>Castbar.barFx).
    DUI.BarFx.Track(h.bar, "cast", nil, nil, nil, DUI.BarFx.Reader(function()
        local d = ns.module and ns.module.db
        local c = d and d[h.kind .. "Castbar"]
        return c and c.barFx
    end))
    if not into then
        Style.Clip(h, h.bar:GetStatusBarTexture(), "inner")
        Style.Clip(h, Style.BarBack(h.bar), "inner")
    else
        -- Inside the frame: cut to its angled end, like the bar it covers.
        local cut = into:GetStatusBarTexture()
        Style.ClipLike(h.bg, cut)
        Style.ClipLike(h.bar:GetStatusBarTexture(), cut)
        Style.ClipLike(Style.BarBack(h.bar), cut)
    end
    Style.SetBarColor(h.bar, Style.CAST.normal[1], Style.CAST.normal[2], Style.CAST.normal[3])
    local overlay = CreateFrame("Frame", nil, h)
    overlay:SetAllPoints(h)
    overlay:SetFrameLevel(h.bar:GetFrameLevel() + 3)
    -- The spell icon sits over the bar's level; the fill starts past it (CB.Layout).
    if not attachTo then
        h.icon = overlay:CreateTexture(nil, "ARTWORK")
        Style.CropIcon(h.icon)
    end
    h.text = Style.Text(overlay, 12, "LEFT", media.font)
    h.time = Style.Text(overlay, 12, "RIGHT", media.font)
    -- Hung under its frame, it slides down from underneath. When it goes back
    -- under, it hides at the end.
    h.slide = DUI.Motion.Slider(function() CB.Hang(h) end, { parent = h, dur = CB.SLIDE,
        done = function(s) if s.p == 0 then h:Hide() end end })
    h:HookScript("OnShow", function(self)
        if self.column and self.column.f:IsVisible() then
            self.slide:Jump(0)
            self.slide:To(1)
        else
            self.slide:Jump(1)
        end
    end)
    -- Inside a frame the bar covers the power bar, so the power text would run
    -- into the spell name: it fades out while the bar shows. Only the show and
    -- hide matter here, so a secret cast never gets read. underCast tells the
    -- power text's writers to leave its alpha alone until the bar goes.
    if into then
        h:HookScript("OnShow", function(self)
            local t = attachTo.powerText
            if type(t) ~= "table" then return end
            if self.coveredText and self.coveredText ~= t then self.coveredText.underCast = nil end
            self.coveredText = t
            if t.underCast then return end
            t.underCast = true
            DUI.Motion.Fade(t, 1, 0, DUI.Motion.FAST)
        end)
        h:HookScript("OnHide", function(self)
            local t = self.coveredText
            self.coveredText = nil
            if not t then return end
            t.underCast = nil
            -- Hidden at full power: its alpha is the game's answer (secret in a
            -- fight), so it is written straight back rather than faded to.
            local u = attachTo.unitToken
            if attachTo.hideFullPower and type(u) == "string" then
                ns.UF.PowerTextAlpha(t, u, true)
            else
                DUI.Motion.Fade(t, 0, 1, DUI.Motion.FAST)
            end
        end)
    end
    h:Hide()
    -- An enemy's bar: the kick (an interrupt) and who did it, on the frame the
    -- bar sits in (the screen for a free bar), so they outlast the bar's hold.
    if h.kind ~= "player" then
        h.blade = DUI.Motion.NewBlade(attachTo or home)
        h.kickTag = DUI.Motion.NewKickTag(attachTo or home, media.font)
    end
    -- Where your interrupt comes off cooldown (casts.kickMark), under the texts.
    if (h.kind == "target" or h.kind == "focus") and DUI.Interrupt then
        h.kickMark = DUI.Interrupt.NewMark(h.bar)
        marked[h] = true
    end
    -- A preview (the options' sample) only draws the test cast: it listens to nothing, and
    -- CB.Layout keeps it off the real frames.
    h.preview = opts.preview or nil
    if type(unit) == "string" and not opts.preview then
        for _, e in ipairs(EVENTS) do DUI.SafeCall(h.RegisterUnitEvent, h, e, unit) end
    end
    -- Yours counts a batch of crafts (CB.Batch).
    if h.kind == "player" and not opts.preview then
        DUI.SafeCall(h.RegisterUnitEvent, h, "UNIT_SPELLCAST_SUCCEEDED", unit)
        DUI.SafeCall(h.RegisterEvent, h, "UPDATE_TRADESKILL_CAST_STOPPED")
    end
    -- Something else is showing your cast (QoL's fishing water).
    if h.kind == "player" and not opts.preview then
        DUI.On("CastElsewhere", function(on)
            CB.elsewhere = on == true
            CB.Refresh(h)
        end)
    end
    h:SetScript("OnEvent", function(self, event, ...) CB.OnEvent(self, event, ...) end)
    -- A frame plugins can find and paint (DaylightUI.API, kind "castbar").
    if DUI.APIReport then DUI.APIReport.Made("castbar", h, type(unit) == "string" and unit or nil, opts.preview == true) end
    h:SetScript("OnUpdate", function(self, dt)
        self.elapsed = (self.elapsed or 0) + dt
        if self.elapsed < 0.05 then return end
        self.elapsed = 0
        local d = self.duration
        if d then CB.WriteTime(self, d) end
    end)
    return h
end

-- A party bar's member changed (the header re-sorted, someone joined). Its
-- events follow the new unit (nil for none). Allowed in combat.
function CB.SetUnit(h, unit)
    if h.unit == unit then return end
    h.unit, h.batch = unit, nil
    if DUI.APIReport then DUI.APIReport.Unit("castbar", h, type(unit) == "string" and unit or nil, false) end
    h:UnregisterAllEvents()
    if type(unit) == "string" then
        for _, e in ipairs(EVENTS) do DUI.SafeCall(h.RegisterUnitEvent, h, e, unit) end
    end
    CB.Refresh(h)
end

-- The clip that the bar hung under the player frame lives in (shared with the
-- swing bars under it). It runs from the frame's bottom, under its border, all
-- the way down, a little past its sides for the shadows. Anything above its top
-- edge is hidden behind the frame. lift comes from CB.Lift (under Ribbon's line
-- the clip starts below it).
function CB.Clip(h, f, lift)
    local clip = h.clip
    if not clip then
        -- A party bar's clip lives in its frame, so it fades with it.
        clip = CreateFrame("Frame", nil, h.inFrame and h.home or UIParent)
        clip:SetClipsChildren(true)
        h.clip = clip
    end
    clip:SetFrameStrata(f:GetFrameStrata())
    clip:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
    -- The frame's border, in the clip's own scale (the frame uses the UI's).
    local top = lift * f:GetEffectiveScale() / clip:GetEffectiveScale()
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", f, "BOTTOMLEFT", -CB.CLIP_MARGIN, top)
    clip:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", CB.CLIP_MARGIN, top)
    clip:SetHeight(1000)
    return clip
end

-- How far below the frame the bar sits: tucked up by its height times what's
-- left of the slide. Its angled end continues the frame's edge wherever it is.
function CB.Hang(h)
    local c = h.column
    if not c then return end
    local f, lift, H, T = c.f, c.lift, c.height, c.T
    local drop = H * (1 - h.slide.p)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, lift + drop)
    local total = c.fH + H - lift - drop
    local cut = c.slant and (f.cut or 0) * total / c.fH or 0
    -- One reused shape table, since this runs every frame of a slide.
    local ref = c.ref or {}
    c.ref, ref.frame, ref.height = ref, f, total
    local side = cut > 0 and c.side or nil
    -- Under a bar angled at both ends (the free power bar) it continues both.
    Style.Slant(h, side and (c.ends or side), cut, ref)
    -- The fill's moving edge carries the same angle.
    Style.AngleFill(h.bar, side, cut * (H - 2 * T) / total)
    if h.moved then h.moved() end
end

-- What sits under the frame right now (the target's combo pips, a druid's only
-- in cat form). The room cfg.drop keeps only counts while it's shown. h.pips
-- is the fraction in use, gliding while the bar is up.
local function pipRoom(h)
    return (h.room or 0) * (h.pips and h.pips.p or 0)
end

-- Puts the bar (and its clip) where the pips' fraction says, right now.
function CB.PlacePips(h)
    local c = h.column
    if c then
        c.lift = c.base - pipRoom(h)
        CB.Clip(h, c.f, c.lift)
        CB.Hang(h)
    elseif h.belowAt then
        CB.PlaceAt(h, h.near, "below", h.belowAt.x, h.belowAt.y - pipRoom(h))
    end
end

-- The pips appeared or went away (a form change, in combat too).
function CB.PipsUp(h, up)
    local want = up and 1 or 0
    if h:IsVisible() then
        h.pips:To(want)
    elseif h.pips.p ~= want then
        h.pips:Jump(want)
    end
end

-- How far down from the frame's top the bar's bottom is right now (it may be
-- partway out), for the swing bars hanging under it.
function CB.Depth(h)
    local c = h.column
    if not c then return nil end
    return c.fH - c.lift + c.height * h.slide.p
end

-- Between the player frame and the target's ("middle"): from the player frame's
-- right end to the target frame's left end, tops level with them. Both ends are
-- angled at the frames' own angle but lean under (wider at the bottom), so each
-- end runs parallel to the frame beside it, CB.AT_GAP apart. Without a target
-- frame it uses its own Width from the player frame. Anchored to the frames so
-- it follows them as they move. Returns the cut.
-- h.fanRate: the angle (cut per height) the swing timers fan out at.
function CB.Middle(h, cfg, T, tall)
    local pf = ns.frames.player
    local tf = ns.frames.target
    local db = ns.module and ns.module.db
    local height = tall
    local cut = cfg.slant ~= false and Pixel.Snap(h, tall * ns.UF.SLANT) or 0
    -- Measured where the edges are parallel: the frame's end is its top corner
    -- and this bar's is its bottom one, so the box comes in by this bar's cut.
    local dx = CB.AT_GAP - cut
    local y = tonumber(cfg.y) or 0
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", pf, "TOPRIGHT", dx, y)
    if type(tf) == "table" and not (type(db) == "table" and db.target.enabled == false) then
        h:SetPoint("TOPRIGHT", tf, "TOPLEFT", -dx, y)
    else
        h:SetWidth(2 * Pixel.Snap(h, cfg.width / 2))
    end
    h:SetHeight(height)
    Style.Slant(h, cut > 0 and "both" or nil, cut, nil, "both")
    Style.AngleFill(h.bar, cut > 0 and "right" or nil, cut * (height - 2 * T) / height, true)
    h.fanRate = height > 0 and cut / height or 0
    return cut
end

-- Protected, so only call through DUI.AfterCombat.
function CB.Layout(h, cfg, parentCfg)
    local g = DUI.DB.General()
    h.enabled = cfg.enabled
    -- A preview (the options' sample) never reaches for the real frames: its player bar would hang
    -- under the real player frame, and "middle" would stretch between the real ones.
    local frames = not h.preview and ns.frames or nil
    -- under: the frame it can hang below, sliding out, at h.hangAt (the
    -- player's "below", which the swing timers hang from, or the target's
    -- "slide"). near: the frame it sits above or below ("above", "below").
    -- Otherwise it's on its own mover.
    -- The player's bar hangs under its frame, or under its power bar when that
    -- stands on its own (playerCastbar.from "power"), with the swing timers
    -- hanging from it too.
    if h.kind == "player" and frames and frames.player then
        local pf = frames.player
        local pb = pf.freePower
        local db = ns.module and ns.module.db
        -- Not from a power bar with flipped angles: its line can't be continued.
        local onPower = cfg.from == "power" and type(pb) == "table" and pb:IsShown() and not pb.flip
            and type(db) == "table" and db.player.powerAt == "free"
        h.under = onPower and pb or pf
    end
    local at = CB.At(h.kind, cfg)
    local hang = type(h.under) == "table" and at == (h.hangAt or "below")
    h.cfgAttach = hang
    -- A frame fading as one picture draws over a cast bar that overlaps it,
    -- even one on a higher layer, so while this bar hangs under a frame that
    -- frame fades piece by piece. Your own bar standing on its own may sit
    -- anywhere by the player frame and its pieces, so they all do.
    local holds
    if cfg.enabled ~= false and not h.preview then
        if hang then holds = { h.under }
        elseif h.kind == "player" and frames and frames.player then holds = frames.player.pieces end
    end
    local key = "castbar:" .. tostring(h.kind)
    local now = {}
    for _, f in ipairs(holds or {}) do now[f] = true end
    for f in pairs(h.notWholeOf or {}) do
        if not now[f] then DUI.Fade.NotWhole(f, key, false) end
    end
    for f in pairs(now) do DUI.Fade.NotWhole(f, key, true) end
    h.notWholeOf = next(now) and now or nil
    -- Hung under the player frame it takes that frame's size, otherwise its own.
    if h.inFrame then
        h:SetScale(1)
    elseif not h.attached then
        local key = (hang and h.under.moverKey) or (at == "personal" and ns.Personal.KEY)
            or (at == "middle" and frames and frames.player and frames.player.moverKey) or h.moverKey
        h:SetScale(key and DUI.Movers.Scale(key) or DUI.Movers.Scale())
    end
    -- Its own border, corners and shadow (playerCastbar.shell), else General's.
    local own = not h.into and ns.UF.OwnShell(cfg) or nil
    h.ownBorder = own and tonumber(own.borderPx) or nil
    local px = h.into and 0 or ns.UF.WriteShell(Style.GetShell(h), own)
    local T = h.into and 0 or Pixel.Px(h, px)
    -- A party bar's height is the bar itself, with the border around it: a
    -- short bar that counted its border had almost no room left for the fill
    -- and its text.
    local tall = 2 * Pixel.Snap(h, (tonumber(cfg.height) or 0) / 2) + (cfg.borderOutside and 2 * T or 0)
    local cut = 0
    h.lead = 0
    h.room, h.belowAt = cfg.drop, nil
    -- Between the frames: a trapezoid with both ends leaning under (CB.Middle).
    local middle = at == "middle" and not h.into and not hang and type(frames) == "table" and type(frames.player) == "table"
    h.middle = middle or nil
    local free = not h.into and not hang and not middle
    -- Hung under a frame or standing between the frames it draws with that
    -- frame, so it can tuck under it. A party bar lives in its frame and a bar
    -- inside a frame is part of it. Otherwise it takes its own strata.
    if not h.into and not h.inFrame then
        local pf = frames and frames.player
        local s
        if hang then s = h.under:GetFrameStrata()
        elseif middle then s = pf:GetFrameStrata()
        elseif at == "personal" and ns.Personal.frame then s = ns.Personal.frame:GetFrameStrata()
        elseif cfg.strata == "FRAME" and ns.frames and ns.frames[h.unit] then s = ns.frames[h.unit]:GetFrameStrata()
        elseif type(cfg.strata) == "string" then s = ns.StrataOf(cfg) end
        if s then h:SetFrameStrata(s) end
    end
    -- When hung it runs the same way as its frame's bars, from the ring to the angle.
    local side = hang and h.under.spec.slant == "left" and "left" or "right"
    h.bar:SetReverseFill(side == "left" or (free and cfg.reverseFill == true))
    if h.into then
        h:ClearAllPoints()
        h:SetAllPoints(h.into)
    elseif hang then
        -- Hang under the frame (past whatever sits there, cfg.drop) with the
        -- borders overlapping, as wide as the frame. Its angle continues the
        -- frame's edge using one mask measured from the frame's top corner
        -- down through this bar, so the two can't drift apart and a full bar
        -- completes the line.
        local f = h.under
        local base = CB.Lift(f, Pixel.Px(f, g.borderPx))
        local lift = base - pipRoom(h)
        local fH = f:GetHeight()
        local height = tall
        -- The frame's full width, its left end tucked under the portrait ring
        -- like the frame's own bars. Its text starts at the bar's own edge (the
        -- ring is allowed to overlap it), and there's no spell icon since that
        -- corner is under the ring.
        h.lead = 0
        -- Inside a clip that starts at the frame's bottom, so it can slide out
        -- from under the frame (and the swing bars from under it).
        local clip = CB.Clip(h, f, lift)
        if h:GetParent() ~= clip then h:SetParent(clip) end
        h.fanRate = nil
        h:SetSize(f:GetWidth(), height)
        -- Drawn just above the frame (and below its portrait), so its straight
        -- border covers the rounded tip of the frame's angle where they meet.
        h:SetFrameLevel(f:GetFrameLevel() + 4)
        h.column = { f = f, base = base, lift = lift, fH = fH, height = height, T = T, side = side, slant = cfg.slant ~= false,
                     ends = f.ends }
        local total = fH + height - lift
        cut = cfg.slant == false and 0 or (f.cut or 0) * total / fH
        CB.Hang(h)
    elseif middle then
        h.column = nil
        if h.slide then h.slide:Jump(1) end
        if h.clip and h:GetParent() == h.clip then h:SetParent(h.home) end
        cut = CB.Middle(h, cfg, T, tall)
        side = cut > 0 and "both" or nil
    else
        h.column, h.fanRate = nil, nil
        if h.slide then h.slide:Jump(1) end
        if h.clip and h:GetParent() == h.clip then h:SetParent(h.home) end
        -- Free-standing: its own size and optionally the player's angle. Above
        -- or below its frame it takes the frame's width (in its own scale) when
        -- fitFrame is on (target, focus; off means their own width).
        local height = tall
        local width = cfg.width
        local f = h.near
        -- Under the personal display: as wide as it and cut the same way.
        -- Otherwise each end has its own switch; the left one leans like
        -- the target frame's end, so a bar under it can match.
        local right, left = cfg.slant == true, cfg.slantLeft == true
        -- A flipped end leans under: its bottom corner sticks out. Each end flips on its own.
        local flipRight, flipLeft = cfg.slantUnder, cfg.slantUnderLeft
        if at == "personal" then
            width = ns.Personal.frame:GetWidth()
            right, left = ns.Personal.Ends()
            flipRight, flipLeft = false, false
        elseif f and (at == "above" or at == "below") and cfg.fitFrame == true then
            width = f:GetWidth() * f:GetEffectiveScale() / h:GetEffectiveScale()
        end
        h:SetSize(2 * Pixel.Snap(h, width / 2), height)
        cut = (right or left) and Pixel.Snap(h, tall * (at == "personal" and ns.Personal.Angle() or ns.UF.AngleOf(cfg.ownAngle, cfg.lean))) or 0
        side = right and left and "both" or right and "right" or left and "left" or nil
        local under = ns.UF.UnderOf(right, left, flipRight, flipLeft)
        Style.Slant(h, side, cut, nil, under)
        -- The fill's moving edge takes the angle of the end it runs toward.
        local edge
        if cfg.reverseFill == true then edge = left and "left" or nil else edge = right and "right" or nil end
        Style.AngleFill(h.bar, edge, cut * (height - 2 * T) / height, ns.UF.EdgeUnder(under, edge))
        if h.near and at == "above" then
            CB.PlaceAt(h, h.near, at, cfg.x, cfg.y)
        elseif h.near and at == "below" then
            h.belowAt = { x = cfg.x, y = tonumber(cfg.y) or 0 }
            CB.PlacePips(h)
        end
    end
    if h.under and not h.inFrame then DUI.Movers.Suspend(h.moverKey, at ~= "free") end
    -- The fill runs the whole bar (under a portrait ring, if any), or starts
    -- past the spell icon. The icon and text start past the ring.
    h.bar:ClearAllPoints()
    h.bar:SetPoint("TOPLEFT", h, "TOPLEFT", T, -T)
    h.bar:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -T, T)
    local contentLead = h.lead
    if h.icon and cfg.showIcon and not hang and not middle then
        local s = tall - 2 * T
        -- An angled left end would cut the icon, so it starts past the angle.
        local lead = h.lead + ((side == "left" or side == "both") and cut or 0)
        h.icon:ClearAllPoints()
        h.icon:SetPoint("TOPLEFT", h, "TOPLEFT", T + lead, -T)
        h.icon:SetSize(s, s)
        h.icon:Show()
        contentLead = lead + s
        -- The fill starts past the icon: run under it, a cast's first stretch
        -- filled out of sight and the bar looked like nothing had started.
        h.bar:SetPoint("TOPLEFT", h, "TOPLEFT", T + contentLead, -T)
    elseif h.icon then
        h.icon:Hide()
    end
    -- Each text has its own size, color, spot and nudge (cfg.spell, cfg.time).
    -- Inside a power bar a text left at its default size shrinks to fit the
    -- bar; a size the player picked is kept, and the inside size wins over
    -- both. They're lifted a pixel because the font sits a little low in such
    -- a thin bar. The inside nudge moves both.
    local spell, time = type(cfg.spell) == "table" and cfg.spell or {}, type(cfg.time) == "table" and cfg.time or {}
    h.spellCfg, h.timeCfg = spell, time
    local lift, dx = 0, 0
    local defaults = ns.DEFAULTS[(h.kind or "") .. "Castbar"]
    local function sizeOf(t, kind)
        local size = tonumber(textOpt(t, "size", kind)) or CB.TEXT_SIZE
        if h.into then
            if (cfg.insideTextSize or 0) > 0 then return cfg.insideTextSize end
            local base = defaults and defaults[kind] and defaults[kind].size or CB.TEXT_SIZE
            if size ~= base then return size end
            return math.min(size, CB.FitText(parentCfg.powerHeight))
        end
        return size
    end
    if h.into then
        lift = Pixel.Px(h, 1)
        dx, lift = cfg.insideTextX or 0, lift + (cfg.insideTextY or 0)
    end
    Style.SetTextSize(h.text, sizeOf(spell, "spell"))
    Style.SetTextSize(h.time, sizeOf(time, "time"))
    local sc, tc = textOpt(spell, "color", "spell"), textOpt(time, "color", "time")
    h.text:SetTextColor(sc[1], sc[2], sc[3])
    h.time:SetTextColor(tc[1], tc[2], tc[3])
    -- The text stays clear of angled ends: the frame's when inside it, the
    -- bar's own otherwise.
    local endCut, slant = cut, cut > 0 and side or nil
    if slant and hang and h.under.ends then slant = h.under.ends end
    if h.into then
        endCut = h.attached.cut or 0
        slant = h.attached.spec and h.attached.spec.slant
    end
    local clearLeft = (slant == "left" or slant == "both") and not (h.icon and h.icon:IsShown())
    local leftPad = CB.PAD + contentLead + (clearLeft and endCut or 0)
    local rightPad = CB.PAD + ((slant == "right" or slant == "both") and endCut or 0)
    if h.into then
        -- The frame's portrait ring sits over the outer end.
        local ring = h.attached.ringInset or 0
        if slant == "left" then rightPad = rightPad + ring elseif slant == "right" then leftPad = leftPad + ring end
    elseif hang and side == "left" then
        -- The target's ring hangs over the bar's right end, so the time stays clear.
        rightPad = rightPad + (h.under.ringInset or 0)
    end
    -- The time is short, so it sits at one point. The spell name spans the
    -- bar, or stops at the time when they sit at opposite ends, and is cut
    -- short there rather than running under it.
    local sPos, tPos = textOpt(spell, "pos", "spell"), textOpt(time, "pos", "time")
    local sx, sy = (tonumber(spell.x) or 0) + dx, (tonumber(spell.y) or 0) + lift
    local tx, ty = (tonumber(time.x) or 0) + dx, (tonumber(time.y) or 0) + lift
    h.time:ClearAllPoints()
    h.time:SetJustifyH(tPos == "left" and "LEFT" or tPos == "center" and "CENTER" or "RIGHT")
    if tPos == "left" then
        h.time:SetPoint("LEFT", h.bar, "LEFT", leftPad + tx, ty)
    elseif tPos == "center" then
        h.time:SetPoint("CENTER", h.bar, "CENTER", (leftPad - rightPad) / 2 + tx, ty)
    else
        h.time:SetPoint("RIGHT", h.bar, "RIGHT", -rightPad + tx, ty)
    end
    h.text:ClearAllPoints()
    h.text:SetJustifyH(sPos == "right" and "RIGHT" or sPos == "center" and "CENTER" or "LEFT")
    local timeUp = textOpt(time, "show", "time") ~= false
    if timeUp and sPos == "left" and tPos == "right" then
        h.text:SetPoint("LEFT", h.bar, "LEFT", leftPad + sx, sy)
        h.text:SetPoint("RIGHT", h.time, "LEFT", -4, sy - ty)
    elseif timeUp and sPos == "right" and tPos == "left" then
        h.text:SetPoint("LEFT", h.time, "RIGHT", 4, sy - ty)
        h.text:SetPoint("RIGHT", h.bar, "RIGHT", -rightPad + sx, sy)
    else
        h.text:SetPoint("LEFT", h.bar, "LEFT", leftPad + sx, sy)
        h.text:SetPoint("RIGHT", h.bar, "RIGHT", -rightPad + sx, sy)
    end
    h.text:SetWordWrap(false)
    if not h.into then Style.LayoutShell(Style.GetShell(h)) end
    CB.Refresh(h)
end

-- A texture over the fill, cut like it: to the bar's own shell, or inside the
-- frame to the frame's angle (like the bar it covers).
function clipIn(h, tex)
    if h.into then Style.ClipLike(tex, h.into:GetStatusBarTexture())
    else Style.Clip(h, tex, "inner") end
end

-- A secret "can't interrupt" flag (boss fights, keystones, battlegrounds). The
-- locked color is laid over the fill in the fill's texture and the client shows
-- it from the flag, so the fill's look stays underneath. The empty part follows
-- the flag too (its own color dimmed, or the locked one), so a locked cast
-- isn't gray over the dimmed cast color.
local function paintLockedBack(h, pal, ni)
    local back = backOf(h)
    if not back then return end
    if not isSecret(ni) then return end
    local r, g, b, a = back:GetVertexColor()
    if isSecret(r) or type(r) ~= "number" then return end
    local k = Style.BAR_BACK_DIM
    local lr, lg, lb = pal.locked.r, pal.locked.g, pal.locked.b
    if CB.cfg.fill == "pair" and DUI.Gradients then lr, lg, lb = DUI.Gradients.Mid("CAST_LOCKED") end
    h.backOff = CreateColor(r, g, b, a or 1)
    back:SetVertexColorFromBoolean(ni, CreateColor(lr * k, lg * k, lb * k, Style.BAR_BACK_ALPHA), h.backOff)
end

local function paintLocked(h, pal)
    local ni = h.notInterruptible
    paintLockedBack(h, pal, ni)
    local secretFlag = isSecret(ni)
    -- A plugin's fill takes no locked color itself. A plain "can't be
    -- interrupted" is laid over it like a secret one, as a combat warning.
    local plainOverFill = not secretFlag and ni == true and owned("fill")
    if not secretFlag and not plainOverFill then
        if h.lockTex then h.lockTex:Hide() end
        return
    end
    local o = h.lockTex
    if not o then
        o = h.bar:CreateTexture(nil, "ARTWORK", nil, 2)
        Style.FollowFill(h.bar, o)
        clipIn(h, o)
        h.lockTex = o
    end
    o:SetTexture(h.bar:GetStatusBarTexture():GetTexture())
    o:SetVertexColor(pal.locked.r, pal.locked.g, pal.locked.b, 1)
    -- With a two-color fill, the "Can't interrupt" pair.
    if CB.cfg.fill == "pair" and DUI.Gradients then
        local G = DUI.Gradients
        o:SetVertexColor(1, 1, 1, 1)
        o:SetGradient(G.Orientation(), G.Colors("CAST_LOCKED"))
    end
    if plainOverFill then o:SetAlpha(1) else o:SetAlphaFromBoolean(ni, 1, 0) end
    o:Show()
end

local paintColor

function CB.ApplyColor(h)
    paintColor(h)
    paintLocked(h, colorsOf(h))
    CB.Painted(h)
end

-- Every bar paint ends here, so plugins that paint cast bars can apply their
-- look (DaylightUI.API's Paint). Reads an empty table when there are none.
function CB.Painted(h)
    local R = DUI.APIReport
    if not (R and R.Painting("castbar")) then return end
    R.Painted("castbar", h, { unit = h.unit, spellID = h.spellID, channel = h.channel == true,
        notInterruptible = h.notInterruptible, interrupted = h.holding == true })
end

-- The color picked for the spell on your own bar (casts.spellColors, a list of
-- { name, color, icon }), or nil. It goes by name so every rank matches, and
-- the latest pick wins. Only your own bar asks: another unit's spell id can
-- be secret, yours never is.
function CB.SpellColor(h)
    if h.kind ~= "player" then return nil end
    local list = CB.cfg.spellColors
    if type(list) ~= "table" or #list == 0 then return nil end
    local name = h.sampleSpell
    if not h.test then
        local id = h.spellID
        if isSecret(id) or type(id) ~= "number" then return nil end
        name = C_Spell.GetSpellName(id)
    end
    if isSecret(name) or type(name) ~= "string" then return nil end
    name = name:lower()
    for i = #list, 1, -1 do
        local e = list[i]
        if type(e) == "table" and type(e.name) == "string" and type(e.color) == "table"
            and e.name:lower() == name then
            return e.color
        end
    end
    return nil
end

-- Editing the list (the Cast Bars page). A new spell starts in the next of
-- these colors, so adding one shows a change at once; a click on its swatch
-- picks another.
CB.SPELL_COLOR_START = {
    { 0.36, 0.78, 0.38 }, { 0.62, 0.38, 0.86 }, { 0.32, 0.62, 0.92 },
    { 0.94, 0.58, 0.24 }, { 0.86, 0.30, 0.30 }, { 0.30, 0.78, 0.74 },
}

local function spellColorList()
    local list = {}
    for i, e in ipairs(type(CB.cfg.spellColors) == "table" and CB.cfg.spellColors or {}) do
        if type(e) == "table" then
            list[i] = { name = e.name, icon = e.icon,
                        color = type(e.color) == "table" and { e.color[1], e.color[2], e.color[3] } or nil }
        end
    end
    return list
end

local function saveSpellColors(list)
    DUI:Set("UnitFrames", "casts.spellColors", list)
end

-- The spell's game name and icon, from a name or an id typed in.
local function spellOf(text)
    local id = tonumber(text)
    if id then
        local name = C_Spell.GetSpellName(id)
        if type(name) ~= "string" or name == "" then return nil end
        return name, C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
    end
    local info = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(text)
    if type(info) == "table" and type(info.name) == "string" then return info.name, info.iconID end
    -- Your spellbook, any case.
    local low = text:lower()
    for _, e in ipairs(CB.BookSpells()) do
        if e.name:lower() == low then return e.name, e.icon end
    end
    return nil
end

-- Your spellbook's spells, highest rank, by name: { name, icon }.
function CB.BookSpells()
    local SD = DUI.Book and DUI.Book.SpellData
    local data = SD and SD.Read(false)
    local out, seen = {}, {}
    for _, section in ipairs(data and data.sections or {}) do
        for _, e in ipairs(section.spells or {}) do
            if type(e.name) == "string" and not e.passive and not e.future and not seen[e.name] then
                seen[e.name] = true
                out[#out + 1] = { name = e.name, icon = e.icon }
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Adds a spell by name or id. Returns its name, or nil and why not.
function CB.AddSpellColor(text)
    text = strtrim(text or "")
    if text == "" then return nil end
    local name, icon = spellOf(text)
    if not name then
        return nil, tonumber(text) and DUI.L["No spell has that ID."]
            or DUI.L["No spell by that name in your spellbook. Type its spell ID instead."]
    end
    local list = spellColorList()
    for i, e in ipairs(list) do
        if type(e.name) == "string" and e.name:lower() == name:lower() then
            -- Already there: it moves to the end, so the preview shows it.
            table.remove(list, i)
            list[#list + 1] = e
            saveSpellColors(list)
            return name
        end
    end
    local start = CB.SPELL_COLOR_START[(#list % #CB.SPELL_COLOR_START) + 1]
    list[#list + 1] = { name = name, icon = icon, color = { start[1], start[2], start[3] } }
    saveSpellColors(list)
    return name
end

function CB.RemoveSpellColor(i)
    local list = spellColorList()
    if not list[i] then return end
    table.remove(list, i)
    saveSpellColors(list)
end

function CB.SetSpellColor(i, rgb)
    local list = spellColorList()
    if not (list[i] and type(rgb) == "table") then return end
    list[i].color = { rgb[1], rgb[2], rgb[3] }
    saveSpellColors(list)
end

-- Names from your spellbook that start with what was typed (W.Complete).
function CB.SuggestSpells(text)
    text = strtrim(text or "")
    if #text < 2 or text:match("^%d+$") then return nil end
    local low, out = text:lower(), {}
    for _, e in ipairs(CB.BookSpells()) do
        if e.name:lower():find(low, 1, true) == 1 then
            out[#out + 1] = { insert = e.name, from = 1, to = #text, label = e.name }
            if #out >= 8 then break end
        end
    end
    return #out > 0 and out or nil
end

function paintColor(h)
    -- Reset the empty part to the plain color the last secret flag picked from.
    local off, back = h.backOff, backOf(h)
    if off and back then back:SetVertexColor(off.r, off.g, off.b, off.a) end
    h.backOff = nil
    local tex = h.bar:GetStatusBarTexture()
    -- A plugin's fill: white under its texture, no gradient, no class layers.
    if owned("fill") then
        Style.SetBarGradient(h.bar, false)
        Style.ClearBarStops(h.bar)
        tex:SetVertexColor(1, 1, 1, 1)
        CB.PaintHiddenClass(h)
        return
    end
    local pal = colorsOf(h)
    local base = h.channel and pal.channel or pal.normal
    -- A cast you can't interrupt is a warning, so its color beats class color
    -- and gradients (a secret flag goes through paintLocked).
    local ni = h.notInterruptible
    if not isSecret(ni) and ni == true then
        Style.SetBarGradient(h.bar, false)
        if CB.cfg.fill == "pair" and DUI.Gradients then
            DUI.Gradients.Paint(h.bar, "CAST_LOCKED")
            CB.PaintHiddenClass(h)
            return
        end
        tex:SetVertexColor(pal.locked.r, pal.locked.g, pal.locked.b, 1)
        Style.NoteFillRGB(tex, pal.locked.r, pal.locked.g, pal.locked.b)
        local back = backOf(h)
        if back then
            local k = Style.BAR_BACK_DIM
            back:SetVertexColor(pal.locked.r * k, pal.locked.g * k, pal.locked.b * k, Style.BAR_BACK_ALPHA)
        end
        CB.PaintHiddenClass(h)
        return
    end
    -- A spell given its own color: a gradient from that color, whatever the fill.
    local own = CB.SpellColor(h)
    if own then
        Style.SetBarGradient(h.bar, false)
        Style.ClearBarStops(h.bar)
        CB.PaintHiddenClass(h)
        DUI.Gradients.PaintFrom(h.bar, own)
        return
    end
    -- A caster whose class the game hides (battlegrounds): the class layers
    -- over the fill carry its color.
    local hidden
    if pal.cfg.classColor then hidden = DUI.Gradients.HiddenClassID(h.unit) end
    -- In the caster's class color, when enabled (players only).
    if pal.cfg.classColor then
        local isPlayer = UnitIsPlayer(h.unit)
        if not isSecret(isPlayer) and isPlayer then
            local _, token = UnitClass(h.unit)
            if not isSecret(token) and token then
                base = CreateColor(Style.ClassColor(token))
            end
        end
    end
    -- Your own gradient: the same colors for casts and channels.
    if CB.cfg.fill == "customGradient" and DUI.Gradients then
        Style.SetBarGradient(h.bar, false)
        DUI.Gradients.PaintStops(h.bar, pal.cfg.customGradient or CB.cfg.customGradient)
        CB.PaintHiddenClass(h)
        return
    end
    -- The fill (Fill style): the Daylight gradient, or the Gradients page's pair
    -- (cast / channel, or the caster's class), else the plain color.
    local grad = CB.cfg.fill == "daylight"
    local pair = CB.cfg.fill == "pair" and DUI.Gradients
    local sweep = Style.SetBarGradient(h.bar, grad and not pair)
    if pair then
        local key = h.channel and "CHANNEL" or "CAST"
        if pal.cfg.classColor and UnitIsPlayer(h.unit) == true then key = pair.KeyFor(h.unit) end
        pair.Paint(h.bar, key)
        CB.PaintHiddenClass(h, hidden, "classGradient")
        return
    end
    CB.PaintHiddenClass(h, hidden, "class")
    if sweep then base = WHITE elseif grad then base = CreateColor(Style.FlatSweep()) end
    tex = h.bar:GetStatusBarTexture()
    tex:SetVertexColor(base.r, base.g, base.b, 1)
    Style.NoteFillRGB(tex, base.r, base.g, base.b)
    -- The empty part in the same color, dimmed like every bar.
    local back = backOf(h)
    if back and not grad then
        local k = Style.BAR_BACK_DIM
        back:SetVertexColor(base.r * k, base.g * k, base.b * k, Style.BAR_BACK_ALPHA)
    end
end

-- The class layers for a hidden class id (DUI.Gradients, hidden classes),
-- created the first time a bar needs them. id nil hides them.
function CB.PaintHiddenClass(h, id, mode)
    if type(id) == "nil" then
        if h.classLayers then DUI.Gradients.PaintClassLayers(h.classLayers, nil, nil) end
        return
    end
    if not h.classLayers then
        h.classLayers = DUI.Gradients.ClassLayers(h.bar, function(tex) clipIn(h, tex) end)
    end
    DUI.Gradients.PaintClassLayers(h.classLayers, id, mode)
end

-- glide: a cast just ended (not a setting or test mode), so a bar hung under
-- the player frame slides back under it and any other fades out FAST, instead
-- of vanishing.
function CB.Stop(h, glide)
    h.duration = nil
    CB.UpdateKickMark(h)
    CB.SetUp(h, false)
    if glide and h.column and h:IsVisible() then
        h.slide:To(0)
    elseif glide and h:IsVisible() then
        h.slide:Jump(1)
        DUI.Motion.AlphaTo(h, 0, DUI.Motion.FAST, true)
    else
        h.slide:Jump(1)
        DUI.Motion.AlphaTo(h, 0, 0, true)
    end
end

-- The fade engine's paint for your cast bar, which has a fade setting of its
-- own. A bar fading out at the end of a cast is left to finish.
function CB.PaintFade(h, a)
    h.fadeNow = a
    local key = h.__duiAlphaKey
    if key and key.goal == 0 then return end
    h:SetAlpha(a)
end

-- Puts a bar that was just shown back at its fade: its own (yours), or its
-- frame's (the target's and focus's), so a cast never snaps a faded bar to full.
function CB.Refade(h)
    local o = h.fadeOf
    if o then
        ns.UF.PaintFade(o, o.fadeNow)
    elseif type(h.fadeNow) == "number" then
        h:SetAlpha(h.fadeNow)
    end
end

-- Show the bar at once, cancelling a fade out in progress.
local function showBar(h)
    DUI.Motion.AlphaTo(h, 1, 0)
    CB.Refade(h)
    CB.SetUp(h, true)
end

-- Whether a cast is up (h.up), told to h.onUp when it changes: the swing bars
-- under the bar between the frames move up into its spot while none is.
function CB.SetUp(h, up)
    if h.up == up then return end
    h.up = up
    if h.onUp then h.onUp(up) end
end

-- An event. An interrupt holds the bar for a moment (if enabled), and while
-- it's held only a new cast takes it over. ... is the event's payload (an
-- interrupt's 4th value is who kicked it, possibly secret).
function CB.OnEvent(h, event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then return CB.BatchMade(h, (select(3, ...))) end
    if event == "UPDATE_TRADESKILL_CAST_STOPPED" then
        if not h.batch then return end
        h.batch = nil
        return CB.Refresh(h, true)
    end
    if event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        local b, id = h.batch, select(3, ...)
        if b and not isSecret(id) and id == b.spell then h.batch = nil end
    end
    local start = event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START"
    if start then CB.Unkick(h) end
    if event == "UNIT_SPELLCAST_INTERRUPTED" and h:IsShown() and not h.test then
        -- The stop event can arrive first and start a fade out. Bring it back
        -- at once, before the kick hides the bar under its pieces.
        showBar(h)
        CB.Kicked(h, (select(4, ...)))
        if CB.cfg.flash then
            CB.Interrupted(h)
            return
        end
    end
    if h.holding and not start then return end
    CB.Refresh(h, true)
end

-- The bar's right end, x from its left at y down (inset px in from its edge).
-- A free bar uses its own angle, a bar inside a frame uses the frame's angle
-- where the bar sits. Square otherwise.
local function rightAt(h, W, y, inset)
    local frame, sl = h, Style.GetSlant(h)
    local dy, dx, FW, FH = 0, 0, W, h:GetHeight()
    if h.into then
        frame = h.attached
        sl = Style.GetSlant(frame)
        local ft, fl, ht, hl = frame:GetTop(), frame:GetLeft(), h:GetTop(), h:GetLeft()
        if type(ft) ~= "number" or type(ht) ~= "number" or type(fl) ~= "number" or type(hl) ~= "number" then
            return W - inset
        end
        dy, dx, FW, FH = ft - ht, hl - fl, frame:GetWidth(), frame:GetHeight()
        inset = Pixel.Px(frame, DUI.DB.General().borderPx)
    end
    local cut = sl and (sl.side == "right" or sl.side == "both") and not sl.ref and not sl.under and sl.cut or 0
    if type(cut) ~= "number" or type(FH) ~= "number" or FH <= 0 then cut = 0 end
    return math.min(W, FW - dx - inset - cut * (dy + y) / (FH or 1))
end

-- The bar's shape for the kick's pieces (Motion.LayPiece): its right end
-- (rightAt), its border (none inside a frame) and the interrupted color.
local function shape(h, W)
    return {
        right = function(y, inset) return rightAt(h, W, y, inset) end,
        T = h.into and 0 or Pixel.Px(h, h.ownBorder or DUI.DB.General().borderPx),
        edge = Style.BORDER, fill = colorsOf(h).cfg.interrupted or CB.cfg.interrupted,
    }
end

-- An interrupted enemy cast plays the chosen kick animation (Motion.Kick,
-- `casts.kickStyle`) and shows who kicked it (`casts.kickedBy`). by is the
-- interrupter's GUID from the event. Your own kick (plain and yours) lights in
-- the accent, anyone else's or a secret one in warm white.
function CB.Kicked(h, by)
    local k = h.blade
    if not k then return end
    local me = UnitGUID("player")
    local mine = type(by) ~= "nil" and not isSecret(by) and not isSecret(me) and by == me
    local r, g, b
    if mine then r, g, b = Style.Accent() else r, g, b = unpack(DUI.Motion.BLADE_EDGE) end
    -- At the bar's scale (a free bar has its mover's, the screen doesn't).
    local scale = h:GetEffectiveScale() / k:GetParent():GetEffectiveScale()
    k:SetScale(scale)
    local W = h:GetWidth()
    DUI.Motion.Kick(k, h, CB.cfg.kickStyle, r, g, b, type(W) == "number" and shape(h, W) or nil)
    local t = h.kickTag
    if t and CB.cfg.kickedBy then
        t:SetScale(scale)
        t:ClearAllPoints()
        if CB.cfg.kickedByPos == "below" then
            t:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 2, -3)
        else
            t:SetPoint("LEFT", h, "RIGHT", 5, 0)
        end
        t:SetFrameStrata(h:GetFrameStrata())
        t:SetFrameLevel(h:GetFrameLevel() + 8)
        DUI.Motion.KickTag(t, by, h.unit, Style.SIZE.small)
    end
end

-- Only an enemy's cast: a friend's is never yours to interrupt.
local function hostile(u)
    if type(u) ~= "string" or type(UnitCanAttack) ~= "function" then return false end
    local v = UnitCanAttack("player", u)
    return not isSecret(v) and v == true
end

-- Your interrupt's ready mark on a running cast (casts.kickMark). fade: the
-- cooldown changed mid-cast.
function CB.UpdateKickMark(h, fade)
    local m = h.kickMark
    if not m then return end
    if CB.cfg.kickMark ~= true or h.test or not h.duration or not hostile(h.unit) then
        DUI.Interrupt.HideMark(m)
        return
    end
    DUI.Interrupt.ShowMark(m, h.duration, h.channel, fade)
end

-- Your interrupt went on or came off cooldown (or changed): the bars casting now.
DUI.On("InterruptChanged", function()
    for h in pairs(marked) do
        if h.duration then DUI.SafeCall(CB.UpdateKickMark, h, true) end
    end
end)

-- A new cast or unit ends the blade at once.
function CB.Unkick(h)
    DUI.Motion.Unblade(h.blade)
end

function CB.Interrupted(h)
    h.duration = nil
    CB.UpdateKickMark(h)
    h.holding = true
    -- Each hold gets its own number so an earlier kick's timer leaves a newer one alone.
    h.holdN = (h.holdN or 0) + 1
    local n = h.holdN
    -- The stop can arrive first and start it sliding back under, so bring it
    -- out again for the hold to show.
    if h.column and h.slide.goal == 0 then h.slide:To(1) end
    h.bar:SetMinMaxValues(0, 1)
    h.bar:SetValue(1)
    if not owned("fill") then
        Style.SetBarGradient(h.bar, false)      -- no Daylight gradient on an interrupt
        if CB.cfg.fill == "pair" and DUI.Gradients then
            DUI.Gradients.Paint(h.bar, "CAST_INTERRUPTED")
        else
            local c = colorsOf(h).cfg.interrupted or CB.cfg.interrupted
            local tex = h.bar:GetStatusBarTexture()
            tex:SetVertexColor(c[1], c[2], c[3], 1)
            Style.NoteFillRGB(tex, c[1], c[2], c[3])
        end
    end
    h.text:SetText(INTERRUPTED or DUI.L["Interrupted"])
    h.time:SetText("")
    CB.Painted(h)
    C_Timer.After(CB.HOLD, function()
        if h.holding and h.holdN == n then CB.Refresh(h, true) end
    end)
end

-- Test mode: a frozen bar partway through a sample cast { text, value, icon }.
function CB.ShowSample(h, cast)
    if not h then return end
    -- With channel ticks on, your bar's sample is a channel, to show them.
    if h.kind == "player" and CB.cfg.channelTicks == true and cast.channel then cast = cast.channel end
    -- With spell colors set, your bar's sample is the last spell picked, in its color.
    local list = h.kind == "player" and CB.cfg.spellColors
    local last = type(list) == "table" and list[#list]
    if type(last) == "table" and type(last.name) == "string" then
        cast = { text = last.name, value = cast.value, icon = last.icon or cast.icon }
    end
    h.sampleSpell = cast.text
    h.test = true
    h.duration = nil
    CB.PlaceTicks(h, cast.ticks or 0)
    h.bar:SetMinMaxValues(0, 1)
    h.bar:SetValue(cast.value)
    h.text:SetText(showsName(h) and cast.text or "")
    local mode = timeMode(h)
    h.time:SetText(mode == "none" and "" or mode == "total" and "1.2 / 2.5" or "1.2")
    if h.icon then h.icon:SetTexture(cast.icon) end
    h.notInterruptible = nil
    -- Your interrupt back a little before the sample cast ends.
    if h.kickMark then
        if CB.cfg.kickMark == true and cast.kick then
            DUI.Interrupt.PlaceMark(h.kickMark, 0, 1, cast.kick, false)
            DUI.Motion.AlphaTo(h.kickMark.clip, 1, 0)
        else
            DUI.Interrupt.HideMark(h.kickMark)
        end
    end
    CB.ApplyColor(h)
    -- Sliding back under after a cast: bring it out again, or it would hide.
    if h.column and h:IsShown() and h.slide.goal == 0 then h.slide:To(1) end
    showBar(h)
end

function CB.HideSample(h)
    if not (h and h.test) then return end
    h.test = nil
    CB.Refresh(h)
end

-- A batch of crafts (Create all, 50 bandages). Your bar runs once over the
-- whole batch, showing which one it's on ("Linen Bandage 3/50"), and stays up
-- between crafts instead of sliding away and back each time. The client
-- counts what's left (GetRemainingRecasts gives the crafts after this one; the
-- game's ProfessionsCrafting adds 1), and the Daylight profession window's
-- Make.state is checked too. Your own casts stay plain under every restriction
-- (SecretWhenUnitSpellCastRestricted). If anything is secret or missing, each
-- craft is its own cast as before.
CB.BATCH_GAP = 1      -- seconds the bar waits between two crafts for the next one

local function plain(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) ~= "number" or isSecret(v) then return false end
    end
    return true
end

-- The crafts left after the one under way.
local function recastsLeft(spell)
    local ts = rawget(_G, "C_TradeSkillUI")
    local fn = type(ts) == "table" and ts.GetRemainingRecasts
    local n = 0
    if type(fn) == "function" then
        local v = fn()
        if plain(v) then n = v end
    end
    local craft = DUI.Craft and DUI.Craft.Make
    local s = craft and craft.state
    if n < 1 and type(s) == "table" and s.id == spell then n = s.total - s.done - 1 end
    return math.max(0, n)
end

-- The batch's duration for the current craft (start and end in ms), or nil
-- when not part of a batch. Asked again during one cast (a setting change, a
-- delay), it keeps the previous answer.
function CB.Batch(h, spell, from, to)
    if h.kind ~= "player" or not plain(spell, from, to) or to <= from then
        h.batch = nil
        return nil
    end
    local b = h.batch
    if b and b.spell ~= spell then b, h.batch = nil, nil end
    if b and b.castFrom == from then return b.d end
    local left = recastsLeft(spell)
    if not b then
        if left < 1 then return nil end
        local C = rawget(_G, "C_DurationUtil")
        if type(C) ~= "table" or type(C.CreateDuration) ~= "function" then return nil end
        b = { spell = spell, done = 0, start = from / 1000, d = C.CreateDuration() }
        h.batch = b
    end
    b.castFrom, b.waiting = from, nil
    b.total = b.done + left + 1
    -- This one, then the rest at the pace so far (gaps between crafts
    -- included), or at this one's length.
    local per = (to - from) / 1000
    local pace = b.done > 0 and (from / 1000 - b.start) / b.done or per
    b.d:SetTimeSpan(b.start, from / 1000 + per + left * pace)
    return b.d
end

-- Nothing casting. In a batch with crafts still to come, the bar stays up (the
-- client keeps filling it) until the next one starts or BATCH_GAP passes.
function CB.BatchWait(h)
    local b = h.batch
    if not b then return false end
    if b.done >= b.total then h.batch = nil; return false end
    b.waiting = (b.waiting or 0) + 1
    local mine = b.waiting
    C_Timer.After(CB.BATCH_GAP, function()
        if h.batch == b and b.waiting == mine then
            h.batch = nil
            CB.Refresh(h, true)
        end
    end)
    return true
end

-- One craft of the batch finished (UNIT_SPELLCAST_SUCCEEDED). If it's the last
-- one and its cast already stopped, the bar goes now.
function CB.BatchMade(h, spell)
    local b = h.batch
    if not b or not plain(spell) or spell ~= b.spell then return end
    b.done = b.done + 1
    if b.done >= b.total and b.waiting then
        h.batch = nil
        CB.Refresh(h, true)
    end
end

-- How many times each channel hits, every rank, so the bar can mark where the
-- next tick lands and the player stops a channel without losing one. Penance's
-- count is not yet seen in game.
CB.CHANNEL_TICKS = {}
for n, ids in pairs({
    [3] = { 15407, 17311, 17312, 17313, 17314, 18807,       -- Mind Flay
            5143,                                            -- Arcane Missiles, rank 1
            402174, 1240720, 1240721, 1316995 },             -- Penance
    [4] = { 5144,                                            -- Arcane Missiles, rank 2
            12051,                                           -- Evocation
            5740, 6219, 11677, 11678 },                      -- Rain of Fire
    [5] = { 5145, 8416, 8417, 10211, 10212, 25345,           -- Arcane Missiles
            689, 699, 709, 7651, 11699, 11700,               -- Drain Life
            5138, 6226, 11703, 11704,                        -- Drain Mana
            1120, 8288, 8289, 11675,                         -- Drain Soul
            740, 8918, 9862, 9863 },                         -- Tranquility
    [6] = { 1510, 14294, 14295 },                            -- Volley
    [8] = { 10, 6141, 8427, 10185, 10186, 10187 },           -- Blizzard
    [10] = { 755, 3698, 3699, 3700, 11693, 11694, 11695,     -- Health Funnel
             16914, 17401, 17402 },                          -- Hurricane
    [15] = { 1949, 11683, 11684 },                           -- Hellfire
}) do
    for _, id in ipairs(ids) do CB.CHANNEL_TICKS[id] = n end
end

-- Only your own bar: your casts stay plain under every restriction, while
-- other units' spell ids can be secret.
local function ticksOf(h, spell, channel)
    if not channel or h.kind ~= "player" or CB.cfg.channelTicks ~= true then return 0 end
    if isSecret(spell) or type(spell) ~= "number" then return 0 end
    return CB.CHANNEL_TICKS[spell] or 0
end

-- n ticks = n - 1 lines between them; the last tick is the bar's end.
function CB.PlaceTicks(h, n)
    local lines = h.tickLines
    if n <= 1 and not lines then return end
    if not lines then
        h.tickFrame = CreateFrame("Frame", nil, h)
        h.tickFrame:SetAllPoints(h.bar)
        h.tickFrame:SetFrameLevel(h.bar:GetFrameLevel() + 1)
        -- A new width (a layout mid-channel) moves the lines with it.
        h.tickFrame:SetScript("OnSizeChanged", function() CB.PlaceTicks(h, h.tickCount or 0) end)
        lines = {}
        h.tickLines = lines
    end
    h.tickCount = n
    local w = h.bar:GetWidth() or 0
    local px = DUI.Pixel.Px(h.bar, 2)
    local ink = Style.INK.VALUE
    for i = 1, math.max(n - 1, #lines) do
        local t = lines[i]
        if i < n and w > 0 then
            if not t then
                t = h.tickFrame:CreateTexture(nil, "OVERLAY")
                lines[i] = t
            end
            t:SetColorTexture(ink[1], ink[2], ink[3], 0.7)
            t:ClearAllPoints()
            t:SetPoint("TOP", h.bar, "TOPLEFT", w * i / n, 0)
            t:SetPoint("BOTTOM", h.bar, "BOTTOMLEFT", w * i / n, 0)
            t:SetWidth(px)
            t:Show()
        elseif t then
            t:Hide()
        end
    end
end

function CB.Refresh(h, glide)
    if not glide then                    -- not a cast event: a new unit or a setting
        CB.Unkick(h)
        DUI.Motion.KickTagOff(h.kickTag)
    end
    if h.test then return end
    h.holding = nil
    if not h.enabled or (CB.elsewhere and h.unit == "player") then CB.Stop(h); return end
    local u = h.unit
    if type(u) ~= "string" then CB.Stop(h); return end
    local channel = false
    -- displayName, like the game's own bar. The first value can be a raw untranslated name.
    -- Whether there is a cast is the first value, as the game's bar asks: a mob's channel
    -- can come without a display name, and then the spell's own name stands in.
    local real, name, texture, from, to, craft, _, notInterruptible, spell = UnitCastingInfo(u)
    -- A craft reports it can't be interrupted, but the locked gray is meant as
    -- a warning about casts you can't kick, so draw a craft like any other cast.
    local batch
    if not isSecret(craft) and craft == true then
        notInterruptible = false
        batch = CB.Batch(h, spell, from, to)
    elseif type(real) ~= "nil" then
        h.batch = nil
    end
    if type(real) == "nil" then
        real, name, texture, _, _, _, notInterruptible, spell = UnitChannelInfo(u)
        channel = true
        if type(real) ~= "nil" then h.batch = nil end
    end
    if type(real) == "nil" then
        if not CB.BatchWait(h) then CB.Stop(h, glide) end
        return
    end
    if type(name) == "nil" then name = real end
    local duration, count = batch, nil
    if batch then
        local b = h.batch
        count = string.format("%d/%d", math.min(b.done + 1, b.total), b.total)
        name = string.format(DUI.L["%s %s"], name, count)
    elseif channel then duration = UnitChannelDuration(u) else duration = UnitCastingDuration(u) end
    if type(duration) == "nil" then CB.Stop(h, glide); return end
    local dir = Enum.StatusBarTimerDirection
    h.bar:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate,
        channel and dir.RemainingTime or dir.ElapsedTime)
    h.duration = duration
    h.notInterruptible = notInterruptible
    h.channel = channel
    h.spellID = spell
    CB.PlaceTicks(h, ticksOf(h, spell, channel))
    CB.UpdateKickMark(h)
    -- With the name off, a batch still shows its progress.
    if showsName(h) then h.text:SetText(name) else h.text:SetText(count or "") end
    if h.icon then h.icon:SetTexture(texture) end
    CB.ApplyColor(h)
    -- Sliding back under after the last cast: bring it back out.
    if h.column and h:IsShown() and h.slide.goal == 0 then h.slide:To(1) end
    showBar(h)
end

-- What plugins get from a bar (DaylightUI.API's Paint, kind "castbar"), and how
-- a bar gets its own look back when a plugin releases a piece.
if DUI.APIReport then
    DUI.APIReport.Parts("castbar", function(h)
        return { fill = h.bar:GetStatusBarTexture(), bar = h.bar, back = Style.BarBack(h.bar),
                 name = h.text, time = h.time, icon = h.icon }
    end)
    DUI.APIReport.Repainter("castbar", function(h)
        if not owned("fill") then Style.ResetBarFill(h.bar) end   -- drop the plugin's texture
        paintColor(h)
        paintLocked(h, colorsOf(h))
    end)
end
