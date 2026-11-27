-- XP orbs: when you gain experience, a ring of orbs blooms where it came from
-- (the mob, the quest giver's reward, the zone name), settles, then streams
-- into the XP bar. The fill steps up as each orb lands; the last one sweeps a
-- light over the gained piece and shows the "+N".
--
-- What a gain was and where it started is XPSource.lua's. Everything here is
-- one frame over the screen with pooled textures and one OnUpdate, which stops
-- as soon as the last orb, spark and ring are gone.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style

local XPOrbs = {}
ns.XPOrbs = XPOrbs

local M = DUI.Motion
XPOrbs.MAX = 30             -- orbs in one burst
XPOrbs.ALIVE = 120          -- orbs on screen at once, every burst together
XPOrbs.NO_TRAILS = 80       -- past this many alive, new bursts fly without trails
XPOrbs.RING = { 16, 16 }    -- each orb's ring radius: from, plus up to
XPOrbs.SQUASH = 0.8         -- the ring is a little wider than tall
XPOrbs.WIDEN, XPOrbs.WIDE_CAP = 1.6, 64   -- an unknown spot: the ring spreads wider
XPOrbs.BORN = { 6, 5 }      -- orbs are born this far around the spot
XPOrbs.SHIVER = { 0.8, 18 } -- px and speed of the shiver while they hold
-- The bow, as shares of the way to the bar, so a stream across the whole
-- screen curves like a short one: each orb first leaves along its own
-- direction, then comes in from the screen's middle.
XPOrbs.OUT = { 0.3, 0.23 }
XPOrbs.PULL = 0.6
XPOrbs.EDGE = 12            -- the bow stays this far inside the screen
XPOrbs.SIZE = { 4.5, 2.5 }  -- core radius at size 1: from, plus up to
XPOrbs.HALO = 2.2           -- the glow's radius, in core radii
XPOrbs.CORE = 0.8           -- the white core's radius, in core radii
XPOrbs.LIFT = 0.4           -- the core's color, this far toward white
XPOrbs.TRAIL = { { 0.03, 0.45, 0.85 }, { 0.06, 0.30, 0.70 }, { 0.09, 0.15, 0.55 } }  -- seconds behind, alpha, size
XPOrbs.SPARK = { 2, 8, 0.8 }           -- landing ring radius from, to, alpha
XPOrbs.SOURCE = { 8, 6, 42, 32, 0.6 }  -- the spot's ring: from w, h to w, h (radii), alpha

local GLOW = DUI.MEDIA .. "glow.png"
local RINGTEX = DUI.MEDIA .. "cursor-ring-thin.png"

XPOrbs.bursts = {}
XPOrbs.owed = 0      -- XP the bar holds back until its orbs land
XPOrbs.landed = 0
XPOrbs.textures = {}
local free = {}

-- How many orbs a gain gets: more for a bigger share of the level, so a big
-- kill looks bigger, and even a small one reads.
function XPOrbs.Count(gain, max)
    if type(gain) ~= "number" or type(max) ~= "number" or gain <= 0 or max <= 0 then return 0 end
    local n = math.floor(3 + 5 * math.sqrt(gain / max * 100) + 0.5)
    return math.max(1, math.min(XPOrbs.MAX, n))
end

local function settings() return ns.module and ns.module.db end

-- Orbs fly with the XP gain effects and motion on, and never next to the XP
-- Orbs addon (two sets would fly).
function XPOrbs.On()
    local db = settings()
    if (db and db.xpGain == false) or not M.On() then return false end
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
    return not (loaded and loaded("XPOrbs"))
end

-- ...for a gain below the level cap (reputation at the cap has none).
function XPOrbs.Wanted(d)
    return d ~= nil and not d.rep and XPOrbs.On()
end

-- The player's settings, for other addons (API.XPOrbs).
function XPOrbs.Settings()
    local db = settings()
    local o = db and db.orbs or {}
    return { on = XPOrbs.On(), size = o.size or 1, flight = o.flight or 2 * M.SLOW, color = o.color or "bar" }
end

-- Other addons hear each gain once its source is known (XPGained: amount,
-- kind, x, y, known) and each gain's last orb landing (XPOrbsLanded: amount).
local function tell(event, ...)
    local R = DUI.APIReport
    if R and R.Event then R.Event(event, ...) end
end

-- What the bar shows now: the true value less what is still flying, or, while
-- a level-up burst fills the old level, its share of the bar.
function XPOrbs.Shown(d)
    if XPOrbs.levelling then
        local _, max = ns.XP.bar:GetMinMaxValues()
        return XPOrbs.levelling.frac * (type(max) == "number" and max or d.max)
    end
    return math.max(0, d.value - XPOrbs.owed)
end

local function layer()
    local f = XPOrbs.layer
    if f then return f end
    f = CreateFrame("Frame", nil, UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("HIGH")
    XPOrbs.layer = f
    return f
end

local function texture(file)
    local t = table.remove(free)
    if not t then
        t = layer():CreateTexture(nil, "OVERLAY")
        XPOrbs.textures[#XPOrbs.textures + 1] = t
    end
    t:SetTexture(file)
    t:SetBlendMode("ADD")
    t:SetAlpha(1)
    t:Show()
    return t
end

local function release(t)
    if not t then return end
    t:Hide()
    free[#free + 1] = t
end

local function place(t, x, y, w, h)
    t:ClearAllPoints()
    t:SetPoint("CENTER", XPOrbs.layer, "BOTTOMLEFT", x, y)
    t:SetSize(w, h or w)
end

local function alive()
    local n = 0
    for _, b in ipairs(XPOrbs.bursts) do n = n + (b.n - b.landed) end
    return n
end

local function lift(c, k)
    local w = Style.INK.VALUE
    return { c[1] + (w[1] - c[1]) * k, c[2] + (w[2] - c[2]) * k, c[3] + (w[3] - c[3]) * k }
end

-- An orb's color at t (0 = the first orb, 1 = the last), by the player's
-- pick (orbs.color): the bar's own colors, the accent, the Daylight gradient,
-- the class gradient, the class color or one color.
function XPOrbs.ColorAt(t)
    local cfg = settings()
    local mode = cfg and cfg.orbs and cfg.orbs.color or "bar"
    if mode == "accent" then return Style.AccentAt(t) end
    if mode == "daylight" then return Style.SweepAt(t) end
    if mode == "gradient" or mode == "class" then
        local G = DUI.Gradients
        local key = G.KeyFor("player")
        if mode == "class" then
            local _, token = UnitClass("player")
            if not DUI.IsSecret(token) then return Style.ClassColor(token) end
        elseif G.Has(key) then
            local lo, hi = G.PaintRGB(key)
            return lo[1] + (hi[1] - lo[1]) * t, lo[2] + (hi[2] - lo[2]) * t, lo[3] + (hi[3] - lo[3]) * t
        end
    end
    if mode == "custom" then
        local c = cfg.orbs.custom
        if type(c) == "table" and type(c[1]) == "number" then return c[1], c[2], c[3] end
    end
    return ns.XP.ColorAt(t)
end

-- The player's size and flight time: K stretches the hold, the stagger and
-- the flight together (1 at SLOW flights).
local function look()
    local cfg = settings()
    local o = cfg and cfg.orbs or {}
    local size = type(o.size) == "number" and o.size or 1
    local flight = type(o.flight) == "number" and o.flight or 2 * M.SLOW
    return size, flight, flight / M.SLOW
end

-- Where the fill ends now: the orbs aim there, and it moves as they land.
local function target()
    local XP = ns.XP
    local bar = XP.bar
    -- The client eases the fill itself; aim at the edge it draws now.
    local v = type(bar.GetInterpolatedValue) == "function" and bar:GetInterpolatedValue() or bar:GetValue()
    if DUI.IsSecret(v) or type(v) ~= "number" then return nil end
    return XP.LandAt(v)
end

local function bez(a, b, c, d, t)
    local u = 1 - t
    return u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d
end

-- An orb's spot `t` seconds into its burst; nil before it exists, and true as
-- a third value once it has landed.
local function spot(b, o, t, tx, ty)
    if t < 0 then return nil end
    if t < o.leave then
        -- Out from where it was born to its ring spot, a little past and back.
        local bloom = M.Back(math.min(1, t / M.NORMAL))
        local sh = XPOrbs.SHIVER
        return o.sx + (o.rx - o.sx) * bloom + math.sin(t * sh[2] + o.i) * sh[1], o.sy + (o.ry - o.sy) * bloom
    end
    local p = (t - o.leave) / b.flight
    if p >= 1 then return tx, ty, true end
    local s = p * p * (3 - 2 * p)
    local e = 0.35 * s + 0.65 * p * p * p
    local d = math.sqrt((tx - o.rx) ^ 2 + (ty - o.ry) ^ 2)
    local W, H, m = b.w, b.h, XPOrbs.EDGE
    local cx = math.max(m, math.min(W - m, o.rx + o.dx * XPOrbs.OUT[1] * d))
    local cy = math.max(m, math.min(H - m, o.ry + o.dy * XPOrbs.OUT[2] * d))
    local qx = math.max(m, math.min(W - m, tx + b.ux * XPOrbs.PULL * d))
    local qy = math.max(m, math.min(H - m, ty + b.uy * XPOrbs.PULL * d))
    return bez(o.rx, cx, qx, tx, e), bez(o.ry, cy, qy, ty, e)
end

-- The bar gives the orbs its value back as they land.
local function settleBar()
    local XP = ns.XP
    local d = XP.Read()
    if d and not d.rep then Style.SetBarValue(XP.bar, XPOrbs.Shown(d)) end
end

local function startDriver()
    layer():SetScript("OnUpdate", function(_, dt) XPOrbs.Step(dt) end)
end

local function finish(b)
    release(b.ring)
    b.ring = nil
    for _, o in ipairs(b.orbs) do
        release(o.halo); release(o.core)
        for _, g in ipairs(o.ghosts) do release(g) end
        o.halo, o.core, o.ghosts = nil, nil, {}
    end
end

-- One frame of every burst.
function XPOrbs.Step(dt)
    local tx, ty = target()
    if not tx then XPOrbs.Drop(); return end
    local W, H = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
    local busy = false
    for bi = #XPOrbs.bursts, 1, -1 do
        local b = XPOrbs.bursts[bi]
        b.t = b.t + dt
        local t = b.t
        -- The bow's pull: from the bar toward the middle of the screen.
        local mx, my = W / 2 - tx, H / 2 - ty
        local len = math.sqrt(mx * mx + my * my)
        if len > 0 then b.ux, b.uy = mx / len, my / len else b.ux, b.uy = 0, 1 end
        b.w, b.h = W, H
        if b.ring then
            local s, p = XPOrbs.SOURCE, t / (M.SLOW * math.max(1, b.flight / M.SLOW))
            if p >= 1 then release(b.ring); b.ring = nil
            else
                local e = 1 - (1 - p) ^ 3
                place(b.ring, b.x, b.y, 2 * (s[1] + (s[3] - s[1]) * e), 2 * (s[2] + (s[4] - s[2]) * e))
                b.ring:SetAlpha(s[5] * (1 - p))
            end
        end
        for _, o in ipairs(b.orbs) do
            if not o.done then
                local x, y, landed = spot(b, o, t, tx, ty)
                if landed then
                    o.done = true
                    release(o.halo); release(o.core)
                    for _, g in ipairs(o.ghosts) do release(g) end
                    o.ghosts = {}
                    b.landed = b.landed + 1
                    XPOrbs.landed = XPOrbs.landed + 1
                    b.sparks[#b.sparks + 1] = { tex = texture(RINGTEX), t = t, x = tx, y = ty }
                    if b.level then b.level.frac = math.min(1, b.level.frac + b.step)
                    elseif not b.cosmetic then XPOrbs.owed = math.max(0, XPOrbs.owed - b.step) end
                    settleBar()
                    if b.landed == b.n then XPOrbs.Done(b) end
                elseif x then
                    place(o.halo, x, y, 2 * XPOrbs.HALO * o.r)
                    place(o.core, x, y, 2 * XPOrbs.CORE * o.r)
                    for k, g in ipairs(o.ghosts) do
                        local spec = XPOrbs.TRAIL[k]
                        local gt = t - spec[1] * b.k
                        if gt > o.leave then
                            local gx, gy = spot(b, o, gt, tx, ty)
                            g:Show()
                            g:SetAlpha(spec[2])
                            place(g, gx, gy, 2 * XPOrbs.HALO * o.r * spec[3])
                        else
                            g:Hide()
                        end
                    end
                end
            end
        end
        for i = #b.sparks, 1, -1 do
            local k = b.sparks[i]
            local p = (t - k.t) / M.NORMAL
            if p >= 1 then release(k.tex); table.remove(b.sparks, i)
            else
                local s = XPOrbs.SPARK
                place(k.tex, k.x, k.y, 2 * (s[1] + (s[2] - s[1]) * p))
                k.tex:SetAlpha(s[3] * (1 - p))
            end
        end
        if b.landed == b.n and not b.ring and #b.sparks == 0 then
            table.remove(XPOrbs.bursts, bi)
        else
            busy = true
        end
    end
    if not busy then
        XPOrbs.layer:SetScript("OnUpdate", nil)
        XPOrbs.landed = 0
    end
end

-- The last orb of a burst is home.
function XPOrbs.Done(b)
    local G = ns.XPGain
    if b.plugin then return end
    if b.level then
        XPOrbs.levelling = nil
        G.LevelSweep()
    elseif not b.cosmetic then
        G.Landed(b.from, b.to, b.max, b.gain)
    end
    tell("XPOrbsLanded", b.gain)
end

-- A burst for a gain, from src (XPSource's answer).
local function burst(g, src)
    local n = g.count or XPOrbs.Count(g.gain, g.max)
    local room = XPOrbs.ALIVE - alive()
    if n > room then n = math.max(math.min(3, n), room) end
    if n <= 0 then return end
    local trails = alive() < XPOrbs.NO_TRAILS
    local x, y = src.x, src.y
    local size, flight, K = look()
    local b = { x = x, y = y, t = 0, n = n, landed = 0, orbs = {}, sparks = {}, step = g.gain / n, plugin = g.plugin,
                from = g.from, to = g.to, max = g.max, gain = g.gain, level = g.level, flight = flight, k = K,
                ux = 0, uy = 1, w = UIParent:GetWidth() or 0, h = UIParent:GetHeight() or 0 }
    if g.level then b.step = (1 - g.level.frac) / n end
    local XP = ns.XP
    local restedN = 0
    if type(src.bonus) == "number" and src.bonus > 0 then
        restedN = math.floor(n * math.min(1, src.bonus / g.gain) + 0.5)
    end
    local tx, ty = target()
    local wide = not src.known
    for i = 1, n do
        local a = (i - 1) / n * 2 * math.pi + math.random() * 0.4
        local r = XPOrbs.RING[1] + math.random() * XPOrbs.RING[2]
        local rxr = wide and math.min(XPOrbs.WIDE_CAP, r * XPOrbs.WIDEN) or r
        local rested = math.floor(i * restedN / n) > math.floor((i - 1) * restedN / n)
        local color = rested and { XP.RESTED[1], XP.RESTED[2], XP.RESTED[3] }
            or { XPOrbs.ColorAt(n > 1 and (i - 1) / (n - 1) or 0) }
        local o = { i = i, rested = rested, color = color, r = (XPOrbs.SIZE[1] + math.random() * XPOrbs.SIZE[2]) * size,
            sx = x + (math.random() - 0.5) * 2 * XPOrbs.BORN[1], sy = y + (math.random() - 0.5) * 2 * XPOrbs.BORN[2],
            rx = x + math.cos(a) * rxr, ry = y + math.sin(a) * r * XPOrbs.SQUASH,
            dx = math.cos(a), dy = math.sin(a), ghosts = {} }
        o.halo = texture(GLOW)
        o.halo:SetVertexColor(color[1], color[2], color[3])
        local c = lift(color, XPOrbs.LIFT)
        o.core = texture(GLOW)
        o.core:SetVertexColor(c[1], c[2], c[3])
        if trails then
            for k = 1, #XPOrbs.TRAIL do
                local gtex = texture(GLOW)
                gtex:SetVertexColor(color[1], color[2], color[3])
                gtex:Hide()
                o.ghosts[k] = gtex
            end
        end
        b.orbs[i] = o
    end
    -- They leave nearest the bar first, all gone within NORMAL after the hold.
    local order = {}
    for i, o in ipairs(b.orbs) do order[i] = o end
    if tx then
        table.sort(order, function(p, q)
            local dp = (p.rx - tx) ^ 2 + (p.ry - ty) ^ 2
            local dq = (q.rx - tx) ^ 2 + (q.ry - ty) ^ 2
            if dp ~= dq then return dp < dq end
            return p.i < q.i
        end)
    end
    -- They hold a moment once the ring has settled, then leave one by one;
    -- slower flights hold and spread out in step.
    for rank, o in ipairs(order) do o.leave = M.NORMAL + M.FAST * K + (rank - 1) * M.NORMAL * K / n end
    b.ring = texture(RINGTEX)
    local hi = { XPOrbs.ColorAt(1) }
    b.ring:SetVertexColor(hi[1], hi[2], hi[3])
    XPOrbs.bursts[#XPOrbs.bursts + 1] = b
    if #XPOrbs.bursts == 1 and alive() == n then XPOrbs.landed = 0 end
    startDriver()
end

-- A gain for the orbs to carry. g = { from, to, max, gain, levelUp, restedDrop }.
-- The bar holds back what they carry until they land.
function XPOrbs.Gain(g)
    XPOrbs.gen = XPOrbs.gen or 0
    local gen = XPOrbs.gen
    if g.levelUp then
        -- Earlier bursts still fly, but the bar they were filling is gone.
        for _, b in ipairs(XPOrbs.bursts) do b.cosmetic = true end
        XPOrbs.owed = 0
        g.level = { frac = math.max(0, math.min(1, g.from / g.max)) }
        XPOrbs.levelling = g.level
    else
        XPOrbs.owed = XPOrbs.owed + g.gain
    end
    ns.XPSource.Resolve(g.gain, function(src)
        if gen ~= XPOrbs.gen then return end
        if not target() then XPOrbs.Drop(); return end
        burst(g, src)
        tell("XPGained", g.gain, src.kind, src.x, src.y, src.known == true)
    end, g.restedDrop)
end

-- A burst of another addon's (API: me.ShowXPOrbs): count orbs from (x, y) in
-- UIParent units into the bar. It only looks: the bar keeps its value and no
-- event fires. False while the orbs are off or the bar isn't on screen.
function XPOrbs.Show(x, y, count)
    if type(x) ~= "number" or type(y) ~= "number" or not XPOrbs.On() or not target() then return false end
    local n = math.max(1, math.min(XPOrbs.MAX, math.floor(tonumber(count) or 12)))
    burst({ gain = 0, max = 1, count = n, plugin = true }, { x = x, y = y, known = true })
    return true
end

-- Ends every burst at once: the bar shows the true value, nothing is left drawn.
function XPOrbs.Drop()
    XPOrbs.gen = (XPOrbs.gen or 0) + 1
    local had = #XPOrbs.bursts > 0 or XPOrbs.owed > 0 or XPOrbs.levelling
    for _, b in ipairs(XPOrbs.bursts) do
        finish(b)
        for _, k in ipairs(b.sparks) do release(k.tex) end
    end
    for i = #XPOrbs.bursts, 1, -1 do XPOrbs.bursts[i] = nil end
    XPOrbs.owed, XPOrbs.levelling, XPOrbs.landed = 0, nil, 0
    if XPOrbs.layer then XPOrbs.layer:SetScript("OnUpdate", nil) end
    ns.XPSource.Drop()
    return had
end
