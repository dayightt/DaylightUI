-- A ring around the mouse cursor so it's easy to find in a busy fight. Off by
-- default. One clean line, with an optional glow, motion and trail.
--
-- Each timer has its own ring, so none of them muddies the cursor's: the global
-- cooldown is a thin ring just outside that drains away, and your casts fill a
-- ring further out with a spark at their tip. Both are the client's Cooldown
-- swipe fed with the game's duration objects (spell 61304, UnitCastingDuration,
-- UnitChannelDuration), so nothing secret is timed or compared in Lua. The spark
-- reads your own cast times, which stay plain in every fight.
--
-- The OnUpdate only runs while the ring is shown. The frame takes no mouse input.

local _, ns = ...
local DUI = DaylightUI
local Style, Motion = DUI.Style, DUI.Motion

local Ring = {}
ns.CursorRing = Ring
ns.features[#ns.features + 1] = Ring

Ring.ART = DUI.MEDIA .. "cursor-ring.png"          -- one flat line at RADIUS of the frame (tools/make_cursor_ring.py)
Ring.THIN_ART = DUI.MEDIA .. "cursor-ring-thin.png" -- the same circle, a thinner line
Ring.BLOOM_ART = DUI.MEDIA .. "cursor-ring-glow.png" -- soft light peaking at half its half
Ring.DOT_ART = DUI.MEDIA .. "glow.png"
Ring.GCD_SPELL = 61304       -- the game's global cooldown
Ring.RADIUS = 0.41           -- where the line sits, in frame widths (the art's own)
Ring.BLOOM = 1.64            -- the glow's size, in frame widths: its peak on the line
Ring.A_BLOOM = 0.4
Ring.GCD = 1.35              -- the global cooldown's ring, in frame widths: just outside the line
Ring.CAST = 1.75             -- the cast ring's, clear of both
Ring.A_CAST = 0.9
Ring.SPARK = 0.2             -- the light at the cast's tip, in frame widths
Ring.DOTS = 10               -- the comet: head first
Ring.DOT = 0.24              -- its head, in frame widths
Ring.TAIL = 0.32             -- its tail, as a share of the way round
Ring.RUN_EVERY = 2.4         -- s to go round once
Ring.A_DOT = 0.85
Ring.BREATH = 0.12           -- the light breathes this much under the comet
Ring.DEEP = 0.4              -- and this much when breathing is all it does
Ring.BREATH_EVERY = 3        -- s
Ring.FLASH = 0.9             -- how much brighter the ring is as the global cooldown ends
Ring.TRAIL = 18              -- trail dots kept
Ring.TRAIL_GAP = 4           -- px the cursor moves before the next one
Ring.TRAIL_DOT = 0.32        -- a trail dot, in frame widths
Ring.A_TRAIL = 0.55
Ring.LIFT = 0.45             -- a one-color ring's light end

local mod, f, wantFight

local function cfg() return mod and mod.db or {} end

local function on()
    local d = cfg()
    if d.cursorRing ~= true then return false end
    if d.cursorRingWhen == "combat" then return wantFight == true end
    return true
end

local function lift(c, k)
    return { c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k }
end

local function blend(a, b, t)
    return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end

-- The ring's two end colors, { r, g, b } each, read at paint time.
function Ring.Colors()
    local d = cfg()
    if d.cursorRingColor == "class" then
        local _, token = UnitClass("player")
        local G = DUI.Gradients
        if type(token) == "string" and G and not G.Flat() and G.RGB then
            local lo, hi = G.RGB(token)
            if lo and hi then return lift(lo, 0.25), hi end
        end
        local c = { Style.ClassColor(token) }
        return c, lift(c, Ring.LIFT)
    elseif d.cursorRingColor == "custom" and type(d.cursorRingCustom) == "table" then
        local c = d.cursorRingCustom
        c = { c[1] or 1, c[2] or 1, c[3] or 1 }
        return c, lift(c, Ring.LIFT)
    end
    local lo, hi = Style.AccentPair()
    if lo then return lo, hi end
    local c = { Style.Accent() }
    return c, lift(c, Ring.LIFT)
end

local function layer(parent, file, draw, sub, blendMode)
    local t = parent:CreateTexture(nil, draw, nil, sub)
    t:SetTexture(file)
    t:SetBlendMode(blendMode or "ADD")
    -- Sizes animate below a pixel: no snapping to the grid.
    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
    if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
    return t
end

local function gradient(tex, lo, hi, a)
    if tex.SetGradient and CreateColor then
        tex:SetVertexColor(1, 1, 1, 1)
        tex:SetGradient("HORIZONTAL", CreateColor(lo[1], lo[2], lo[3], a), CreateColor(hi[1], hi[2], hi[3], a))
    else
        tex:SetVertexColor(lo[1], lo[2], lo[3], a)
    end
end

local function sweep(parent, art)
    local cd = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
    cd:SetDrawEdge(false)
    if cd.SetDrawBling then cd:SetDrawBling(false) end
    cd:SetHideCountdownNumbers(true)
    cd:SetSwipeTexture(art)
    cd:SetReverse(true)
    cd:EnableMouse(false)
    return cd
end

local function moving()
    return Motion.On() and cfg().cursorRingMotion ~= "still"
end

-- ---------------------------------------------------------------------
-- The picture, every frame while it shows
-- ---------------------------------------------------------------------

local function place(tex, x, y)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", f, "CENTER", x, y)
end

-- A trail dot left where the cursor was, in UIParent units.
local function drop(x, y)
    local t = f.trail
    t.next = t.next % Ring.TRAIL + 1
    local dot = t[t.next]
    dot.life, dot.x, dot.y = Motion.SLOW, x, y
    dot.tex:ClearAllPoints()
    dot.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    dot.tex:Show()
end

local function stepTrail(dt, x, y)
    local t = f.trail
    if not t then return end
    local want = cfg().cursorRingTrail == true and Motion.On()
    if want and x and (not t.x or math.abs(x - t.x) + math.abs(y - t.y) >= Ring.TRAIL_GAP) then
        if t.x then drop(x, y) end
        t.x, t.y = x, y
    end
    local size = f.size * Ring.TRAIL_DOT
    local live = false
    for i = 1, Ring.TRAIL do
        local dot = t[i]
        if dot.life > 0 then
            dot.life = dot.life - dt
            if dot.life <= 0 then
                dot.tex:Hide()
            else
                live = true
                local p = dot.life / Motion.SLOW
                dot.tex:SetSize(size * (0.35 + 0.65 * p), size * (0.35 + 0.65 * p))
                dot.tex:SetAlpha(f.alpha * Ring.A_TRAIL * p * p)
            end
        end
    end
    t.live = live
end

-- The spark at the cast's tip, where the client's swipe has reached: it fills
-- clockwise from the top.
local function paintSpark()
    local from, to = f.castFrom, f.castTo
    if not (from and to and to > from) or cfg().cursorRingCast == false then f.spark:Hide(); return end
    local p = (GetTime() - from) / (to - from)
    if p < 0 or p >= 1 then f.spark:Hide(); return end
    local r = f.size * Ring.CAST * Ring.RADIUS
    local angle = p * 2 * math.pi
    f.spark:ClearAllPoints()
    f.spark:SetPoint("CENTER", f, "CENTER", math.sin(angle) * r, math.cos(angle) * r)
    f.spark:SetAlpha(f.alpha)
    f.spark:Show()
end

local function paint(dt)
    local d = cfg()
    local a, size = f.alpha, f.size
    f.t = f.t + dt
    local run = moving()
    local wave = run and math.sin(f.t * 2 * math.pi / Ring.BREATH_EVERY) or 0
    local deep = d.cursorRingMotion == "breathe"
    local breath = 1 + (deep and Ring.DEEP or Ring.BREATH) * wave
    if f.flash > 0 then f.flash = math.max(0, f.flash - dt / Motion.NORMAL) end
    local flash = 1 + Ring.FLASH * f.flash * f.flash
    f.ping:SetAlpha(a * f.flash * f.flash)
    paintSpark()
    -- The line itself stays at the opacity setting: the glow breathes and flashes.
    if d.cursorRingGlow ~= false then
        f.bloom:SetAlpha(math.min(1, Ring.A_BLOOM * (1 + 1.5 * (breath - 1)) * flash))
        local grow = 1 + 0.12 * f.flash + (deep and 0.08 * wave or 0)
        f.bloom:SetSize(size * Ring.BLOOM * grow, size * Ring.BLOOM * grow)
    end
    local comet = d.cursorRingMotion ~= "breathe" and d.cursorRingMotion ~= "still"
    if comet then
        local head = run and f.t / Ring.RUN_EVERY or 0.25
        local r = size * Ring.RADIUS
        local lo, hi = f.lo, f.hi
        for i, dot in ipairs(f.dots) do
            local p = (i - 1) / Ring.DOTS
            local u = (head - p * Ring.TAIL) % 1
            local angle = u * 2 * math.pi
            local cx = math.cos(angle)
            -- The ring's own color where the dot is, its head lifted toward white.
            local cr, cg, cb = blend(lo, hi, (cx + 1) / 2)
            if i == 1 then cr, cg, cb = cr + (1 - cr) * 0.5, cg + (1 - cg) * 0.5, cb + (1 - cb) * 0.5 end
            dot:SetVertexColor(cr, cg, cb, 1)
            local s = size * Ring.DOT * (i == 1 and 1 or 0.75 * (1 - 0.6 * p))
            dot:SetSize(s, s)
            place(dot, cx * r, math.sin(angle) * r)
            dot:SetAlpha(math.min(1, a * Ring.A_DOT * flash * (1 - p) * (1 - p)))
        end
    end
end

local function step(self, dt)
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    if x ~= self.lastX or y ~= self.lastY then
        self.lastX, self.lastY = x, y
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
    end
    paint(dt or 0)
    stepTrail(dt or 0, x / s, y / s)
end

local function build()
    f = CreateFrame("Frame", "DaylightUICursorRing", UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:EnableMouse(false)
    f:SetAlpha(0)
    f.t, f.flash, f.alpha, f.size = 0, 0, 0.8, 48
    f.bloom = layer(f, Ring.BLOOM_ART, "BACKGROUND", 0)
    f.bloom:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.ring = layer(f, Ring.ART, "ARTWORK", 0, "BLEND")
    f.ring:SetAllPoints(f)
    f.dots = {}
    for i = 1, Ring.DOTS do f.dots[i] = layer(f, Ring.DOT_ART, "OVERLAY", 1) end
    f.gcd = sweep(f, Ring.THIN_ART)
    f.gcd:SetPoint("CENTER", f, "CENTER", 0, 0)
    -- What's left of it: drains away rather than fills.
    f.gcd:SetReverse(false)
    -- Lights up as the global cooldown ends.
    f.ping = layer(f, Ring.THIN_ART, "OVERLAY", 2)
    f.ping:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.ping:SetAlpha(0)
    -- The global cooldown ending: the ring flashes (the client says when).
    f.gcd:SetScript("OnCooldownDone", function()
        if cfg().cursorRingFlash ~= false and f:IsShown() then f.flash = 1 end
    end)
    f.cast = sweep(f, Ring.ART)
    f.cast:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.spark = layer(f, Ring.DOT_ART, "OVERLAY", 3)
    f.spark:Hide()
    -- The trail lies on the screen, not on the ring: it stays where it was left.
    f.trail = { next = 0 }
    for i = 1, Ring.TRAIL do
        local tex = layer(f, Ring.DOT_ART, "BORDER", 0)
        tex:Hide()
        f.trail[i] = { tex = tex, life = 0 }
    end
    f:Hide()
    f:SetScript("OnUpdate", step)
end

function Ring.Paint()
    if not f then return end
    local d = cfg()
    local lo, hi = Ring.Colors()
    f.lo, f.hi = lo, hi
    local a = tonumber(d.cursorRingAlpha) or 0.8
    local size = tonumber(d.cursorRingSize) or 48
    f.alpha, f.size = a, size
    f:SetSize(size, size)
    gradient(f.ring, lo, hi, a)
    -- The global cooldown: a thin, near-white ring of its own.
    local swipe = lift(hi, 0.75)
    f.gcd:SetSize(size * Ring.GCD, size * Ring.GCD)
    f.gcd:SetSwipeColor(swipe[1], swipe[2], swipe[3], a)
    f.ping:SetSize(size * Ring.GCD, size * Ring.GCD)
    f.ping:SetVertexColor(swipe[1], swipe[2], swipe[3], 1)
    f.cast:SetSize(size * Ring.CAST, size * Ring.CAST)
    f.cast:SetSwipeColor(lo[1], lo[2], lo[3], a * Ring.A_CAST)
    local sc = lift(hi, 0.6)
    f.spark:SetVertexColor(sc[1], sc[2], sc[3], 1)
    f.spark:SetSize(size * Ring.SPARK, size * Ring.SPARK)
    f.bloom:SetShown(d.cursorRingGlow ~= false)
    f.bloom:SetSize(size * Ring.BLOOM, size * Ring.BLOOM)
    gradient(f.bloom, lo, hi, a)
    local comet = d.cursorRingMotion ~= "breathe" and d.cursorRingMotion ~= "still"
    for _, dot in ipairs(f.dots) do dot:SetShown(comet) end
    local tc = lift(hi, 0.2)
    for i = 1, Ring.TRAIL do f.trail[i].tex:SetVertexColor(tc[1], tc[2], tc[3], 1) end
    paint(0)
end

local function secret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end

-- The global cooldown sweep. Uses start and duration when they're plain, and the
-- duration object when they're secret (isActive stays plain). It's only ever
-- started, never stopped: the swipe ends on its own, and a hard cast ending
-- mustn't cut a running GCD.
function Ring.Gcd()
    if not (f and f:IsShown()) then return end
    if cfg().cursorRingGcd == false then f.gcd:Clear(); return end
    local read = C_Spell and C_Spell.GetSpellCooldown
    local ok, info = false, nil
    if type(read) == "function" then ok, info = pcall(read, Ring.GCD_SPELL) end
    if not ok or type(info) ~= "table" then return end
    local start, length = info.startTime, info.duration
    if secret(start) or secret(length) then
        if secret(info.isActive) or info.isActive ~= true then return end
        local get = C_Spell.GetSpellCooldownDuration
        local okD, d = false, nil
        if type(get) == "function" then okD, d = pcall(get, Ring.GCD_SPELL) end
        if okD and type(d) ~= "nil" then pcall(f.gcd.SetCooldownFromDurationObject, f.gcd, d) end
    elseif type(start) == "number" and type(length) == "number" and start > 0 and length > 0 then
        f.gcd:SetCooldown(start, length)
    end
end

-- Your cast or channel on the outer ring. Your own cast events stay plain;
-- the duration object is secret and goes straight to the client's swipe.
function Ring.Cast(event)
    if not (f and f:IsShown()) then return end
    if cfg().cursorRingCast == false then f.cast:Clear(); return end
    local d
    if event and event:find("CHANNEL") then
        d = UnitChannelDuration and UnitChannelDuration("player")
    else
        d = UnitCastingDuration and UnitCastingDuration("player")
        if type(d) == "nil" then d = UnitChannelDuration and UnitChannelDuration("player") end
    end
    if type(d) == "nil" then f.cast:Clear(); f.castFrom, f.castTo = nil, nil; return end
    pcall(f.cast.SetCooldownFromDurationObject, f.cast, d, true)
    -- Your own cast times stay plain; anything secret just leaves the spark out.
    local _, _, _, from, to = UnitCastingInfo("player")
    if type(from) == "nil" then _, _, _, from, to = UnitChannelInfo("player") end
    if type(from) == "number" and type(to) == "number" and not secret(from) and not secret(to) then
        f.castFrom, f.castTo = from / 1000, to / 1000
    else
        f.castFrom, f.castTo = nil, nil
    end
end

local function castOver()
    if not f then return end
    f.cast:Clear()
    f.castFrom, f.castTo = nil, nil
end

-- Shown or not, as the settings and the fight say: in at FAST (a fight
-- needs it at once), out at NORMAL.
function Ring.Update(instant)
    local want = on()
    if want then
        if not f then build() end
        Ring.Paint()
        f.leaving = nil
        if not f:IsShown() then
            f.lastX = nil
            f.trail.x = nil
            f:Show()
            step(f, 0)
            if instant then f:SetAlpha(1) else Motion.Fade(f, 0, 1, Motion.FAST) end
        end
        Ring.Gcd()
        Ring.Cast()
    elseif f and f:IsShown() and not f.leaving then
        -- Hidden once faded, so its OnUpdate stops.
        if instant then f:Hide(); return end
        f.leaving = true
        Motion.Fade(f, 1, 0, Motion.NORMAL)
        C_Timer.After(Motion.NORMAL, function()
            if f.leaving and not on() then f:Hide() end
            f.leaving = nil
        end)
    end
end

function Ring.Enable(m)
    mod = m
    wantFight = InCombatLockdown() and true or false
    DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function() wantFight = true; Ring.Update() end)
    DUI.RegisterEvent("PLAYER_REGEN_ENABLED", function() wantFight = false; Ring.Update() end)
    DUI.RegisterEvent("SPELL_UPDATE_COOLDOWN", Ring.Gcd)
    local function mine(fn) return function(event, unit) if unit == "player" then fn(event) end end end
    for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START",
        "UNIT_SPELLCAST_CHANNEL_UPDATE" }) do
        DUI.RegisterEvent(e, mine(Ring.Cast))
    end
    for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED" }) do
        DUI.RegisterEvent(e, mine(Ring.Gcd))
    end
    for _, e in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
        "UNIT_SPELLCAST_CHANNEL_STOP" }) do
        DUI.RegisterEvent(e, mine(castOver))
    end
    DUI.On("StyleChanged", Ring.Paint)
    Ring.Update(true)
end

function Ring.Refresh(m)
    mod = m or mod
    Ring.Update()
end
