-- Tracker block animation. Each block's position (y), sideways slide (dx) and
-- alpha ease toward their targets on one driver that only runs while something
-- moves. A target changed mid-way turns around from the current value. Only
-- touches the addon's own frames; the tracker supplies placement (Animate.place).

local _, ns = ...
local DUI = DaylightUI
local Motion = DUI.Motion

local Animate = {}
ns.Animate = Animate

Animate.ENTER_DX = 16    -- a new quest slides in from this far right
Animate.LEAVE_DX = 12    -- a finished one slides this far right as it leaves
Animate.LEAVE_FAR_DX = 40 -- a turned-in one goes further and slower (Motion.SLOW)
Animate.GLIDE = DUI.Motion.NORMAL   -- rows moving to a new spot
Animate.place = function() end
Animate.onTick = nil
local follower            -- one value easing along with the rows (Animate.Follow)

local recs = setmetatable({}, { __mode = "k" })
local moving = {}
local driver = CreateFrame("Frame")
driver:Hide()
Animate.driver = driver

local function smooth(t) return t * t * (3 - 2 * t) end
local function out(t) return 1 - (1 - t) ^ 3 end

function Animate.State(f)
    local r = recs[f]
    if not r then
        r = { y = 0, dx = 0, a = 1, ch = {} }
        recs[f] = r
    end
    return r
end

local function apply(f, r) Animate.place(f, r.y, r.dx, r.a) end

function Animate.Jump(f, y, dx, a)
    local r = Animate.State(f)
    r.ch = {}
    moving[f] = nil
    r.y, r.dx, r.a = y or r.y, dx or 0, a or 1
    apply(f, r)
end

local function go(f, name, to, dur, ease, done)
    local r = Animate.State(f)
    if not Motion.On() or dur <= 0 then
        r.ch[name] = nil
        r[name] = to
        apply(f, r)
        if done then done(f) end
        return
    end
    r.ch[name] = { from = r[name], to = to, t = 0, dur = dur, ease = ease, done = done }
    moving[f] = true
    driver:Show()
end

function Animate.Glide(f, y) go(f, "y", y, Animate.GLIDE, smooth) end

-- A value that moves with the rows, using Glide's time and curve on this driver
-- so what it drives (the list's scroll) stays in step. No args stops it in place.
function Animate.Follow(from, to, step)
    if not step then follower = nil; return end
    if not Motion.On() or from == to then
        follower = nil
        step(to)
        return
    end
    follower = { from = from, to = to, t = 0, step = step }
    driver:Show()
end

function Animate.Enter(f, y)
    Animate.Jump(f, y, Animate.ENTER_DX, 0)
    go(f, "dx", 0, Motion.NORMAL, out)
    go(f, "a", 1, Motion.NORMAL, out)
end

function Animate.Leave(f, done, far)
    local dur = far and Motion.SLOW or Motion.NORMAL
    go(f, "dx", far and Animate.LEAVE_FAR_DX or Animate.LEAVE_DX, dur, out)
    go(f, "a", 0, dur, out, done)
end

function Animate.FadeIn(f, y)
    Animate.Jump(f, y, 0, 0)
    go(f, "a", 1, Motion.NORMAL, out)
end

function Animate.FadeOut(f, done) go(f, "a", 0, Motion.NORMAL, out, done) end

function Animate.Forget(f)
    recs[f] = nil
    moving[f] = nil
end

function Animate.Moving() return next(moving) ~= nil or follower ~= nil end

-- Blocks that finished this tick, called back after the tick (frame/callback
-- pairs, reused rather than reallocated every frame).
local doneF, doneFn, doneN = {}, {}, 0

function Animate.Tick(dt)
    if follower then
        local c = follower
        c.t = math.min(1, c.t + dt / Animate.GLIDE)
        if c.t >= 1 then follower = nil end
        c.step(c.from + (c.to - c.from) * smooth(c.t))
    end
    for f in pairs(moving) do
        local r = recs[f]
        local still = false
        if r then
            for name, c in pairs(r.ch) do
                c.t = math.min(1, c.t + dt / c.dur)
                r[name] = c.from + (c.to - c.from) * c.ease(c.t)
                if c.t >= 1 then
                    r.ch[name] = nil
                    if c.done then
                        doneN = doneN + 1
                        doneF[doneN], doneFn[doneN] = f, c.done
                    end
                else
                    still = true
                end
            end
            apply(f, r)
        end
        if not still then moving[f] = nil end
    end
    local n = doneN
    doneN = 0
    for i = 1, n do
        local f, fn = doneF[i], doneFn[i]
        doneF[i], doneFn[i] = nil, nil
        fn(f)
    end
    if Animate.onTick then Animate.onTick() end
    if not next(moving) and not follower then driver:Hide() end
end

driver:SetScript("OnUpdate", function(_, dt) Animate.Tick(dt or 0) end)
