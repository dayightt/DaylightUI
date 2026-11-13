-- Window motion. Windows fade and rise in, their page contents lift in one
-- after another, and they sink slightly as they fade out. A new move always
-- starts from wherever the last one left off.
--
-- Everything is stepped by hand with SetAlpha and SetPoint rather than
-- animation groups. An alpha animation on an ancestor left 3D models fully
-- transparent, and Translation animations move in whole-pixel steps.

local _, DUI = ...

local Win = DUI.Win or {}
DUI.Win = Win

local Feel = {}
Win.Feel = Feel

Feel.OPEN = 0.22       -- window fade and rise in, seconds
Feel.RISE = 8          -- px a window rises on open
Feel.CLOSE = 0.25      -- window fade out, seconds
Feel.SINK = 4          -- px a window sinks on close
Feel.PIECE = 0.12      -- one page piece lifting in, seconds
Feel.LIFT = 4          -- px a piece lifts
Feel.STEP = 0.02       -- seconds between pieces
Feel.STEPS = 5         -- after this many, the rest come in together so long lists don't wait
Feel.HEAD = 0.04       -- delay before an opening window's pieces start

local PI2 = math.pi / 2
-- Alpha eases on a sine. A cubic did most of the fade in the first frames
-- and looked like a pop. Movement uses a cubic so it settles gently.
local EASE = {
    sine = function(p) return math.sin(p * PI2) end,
    cubic = function(p) return 1 - (1 - p) ^ 3 end,
    both = function(p) if p < 0.5 then return 2 * p * p end return 1 - (-2 * p + 2) ^ 2 / 2 end,
}

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- ---------------------------------------------------------------------
-- Driver: one OnUpdate, running only while something moves.
-- ---------------------------------------------------------------------

local jobs = {}   -- [frame] = { [kind] = job }
local driver

-- SafeCall so one bad callback can't stop the driver.
local function run(fn, ...) if fn then DUI.SafeCall(fn, ...) end end

-- Snapshot this frame's jobs first, since a finished job's callback may
-- start new ones.
local now = {}
local function tick(self, dt)
    local n = 0
    for frame, kinds in pairs(jobs) do
        for kind, j in pairs(kinds) do
            n = n + 1
            now[n] = j
            j.frame, j.kind = frame, kind
        end
    end
    for i = 1, n do
        local j = now[i]
        now[i] = nil
        local kinds = jobs[j.frame]
        if kinds and kinds[j.kind] == j then
            j.t = j.t + dt
            if j.t >= 0 then
                local p = j.dur > 0 and j.t / j.dur or 1
                if p >= 1 then
                    kinds[j.kind] = nil
                    if next(kinds) == nil then jobs[j.frame] = nil end
                    run(j.apply, j.to)
                    run(j.done)
                else
                    run(j.apply, j.from + (j.to - j.from) * EASE[j.ease](p))
                end
            end
        end
    end
    if next(jobs) == nil then self:SetScript("OnUpdate", nil) end
end

-- Start or replace one kind of move on a frame. With motion off it jumps
-- straight to the end.
local function start(frame, kind, from, to, dur, ease, apply, done, delay)
    if not (DUI.Motion and DUI.Motion.On()) or dur <= 0 then
        if jobs[frame] then jobs[frame][kind] = nil end
        run(apply, to)
        run(done)
        return
    end
    jobs[frame] = jobs[frame] or {}
    jobs[frame][kind] = { t = -(delay or 0), dur = dur, from = from, to = to, ease = ease, apply = apply, done = done }
    if (delay or 0) <= 0 then run(apply, from) end
    driver = driver or CreateFrame("Frame")
    driver:SetScript("OnUpdate", tick)
end

local function stop(frame, kind)
    local kinds = jobs[frame]
    if not kinds then return end
    kinds[kind] = nil
    if next(kinds) == nil then jobs[frame] = nil end
end

function Feel.Moving(frame) return jobs[frame] ~= nil end
-- For tests. nil until the first move.
function Feel.Driver() return driver end

-- ---------------------------------------------------------------------
-- Offsets from a frame's rest position (single-anchor frames only)
-- ---------------------------------------------------------------------

-- The rest position is wherever the frame's own code anchored it. If that
-- code re-anchors it mid-move, the new spot becomes the rest position.
local function rest(frame)
    if frame:GetNumPoints() ~= 1 then return nil end
    local p, rel, rp, x, y = frame:GetPoint(1)
    if type(x) ~= "number" or type(y) ~= "number" or secret(x) or secret(y) then return nil end
    local at = frame.__feelAt
    if not at or at.rel ~= rel or at.point ~= p or at.rp ~= rp
        or math.abs(at.setX - x) > 0.5 or math.abs(at.setY - y) > 0.5 then
        at = { point = p, rel = rel, rp = rp, x = x, y = y, dx = 0, dy = 0, setX = x, setY = y }
        frame.__feelAt = at
    end
    return at
end

-- Current vertical and horizontal offset from rest. The horizontal one comes
-- from Feel.Slide, used by Win.Room.
function Feel.Offset(frame)
    local at = frame.__feelAt
    return at and at.dy or 0
end
function Feel.OffsetX(frame)
    if not frame.__feelAt then return 0 end
    local at = rest(frame)   -- picks up a re-anchor by the frame's own code
    return at and at.dx or 0
end

-- A frame holding secure children (the character window's equipment slots)
-- is protected and can't move in combat. It only fades, and returns to rest
-- after the fight.
local function locked(frame)
    return InCombatLockdown() and frame.IsProtected ~= nil and frame:IsProtected() == true
end

local function place(frame, at)
    at.setX, at.setY = at.x + at.dx, at.y + at.dy
    frame:ClearAllPoints()
    frame:SetPoint(at.point, at.rel, at.rp, at.setX, at.setY)
    if at.dx == 0 and at.dy == 0 then frame.__feelAt = nil end
end

local function shift(frame, dy)
    local at = rest(frame)
    if not at then return end
    if locked(frame) then
        if at.dy ~= 0 then
            DUI.AfterCombat(function() if not Feel.Moving(frame) then shift(frame, 0) end end, "feel:" .. tostring(frame))
        end
        return
    end
    at.dy = dy
    place(frame, at)
end
Feel.Shift = shift

local function slide(frame, dx)
    local at = rest(frame)
    if not at or locked(frame) then return end
    at.dx = dx
    place(frame, at)
end

-- Glide to dx px sideways from rest. 0 slides back home.
function Feel.Slide(frame, dx)
    if math.abs(Feel.OffsetX(frame) - dx) < 0.5 then
        stop(frame, "slide")
        if Feel.OffsetX(frame) ~= dx then slide(frame, dx) end
        return
    end
    if not frame:IsShown() then stop(frame, "slide"); slide(frame, dx); return end
    start(frame, "slide", Feel.OffsetX(frame), dx, DUI.Motion and DUI.Motion.NORMAL or 0.2, "cubic", function(v) slide(frame, v) end)
end

-- Start dx, dy px from rest (where it was before a re-layout) and glide home
-- over dur. Uses the same curve as Feel.Size, so the two stay in step.
-- Motion.Glide's Translation animation snaps to whole pixels and made bag
-- slots jitter next to a resizing window.
function Feel.Glide(frame, dx, dy, dur)
    local at = rest(frame)
    if not at or locked(frame) then return end
    local x0, y0 = dx, dy
    start(frame, "glide", 1, 0, dur or (DUI.Motion and DUI.Motion.NORMAL or 0.2), "cubic", function(p)
        local now = rest(frame)
        if not now then return end
        now.dx, now.dy = x0 * p, y0 * p
        place(frame, now)
    end)
end

-- ---------------------------------------------------------------------
-- Windows
-- ---------------------------------------------------------------------

-- Shown and not closing.
function Feel.IsOpen(frame) return frame:IsShown() and not frame.__feelClosing end

-- Fade and rise in. A hidden window starts transparent and RISE px low; one
-- caught mid-close reverses from where it is.
-- Under the Classic look a window opening gets one soft run of gold light across it.
local function glint(frame)
    if DUI.Style.Look() ~= "classic" or InCombatLockdown() or not DUI.Motion.On() then return end
    local t = frame.__feelGlint
    if not t then
        t = frame:CreateTexture(nil, "OVERLAY")
        t:SetTexture(DUI.MEDIA .. "glow.png")
        t:SetBlendMode("ADD")
        t:Hide()
        frame.__feelGlint = t
    end
    local h, w = frame:GetHeight() or 0, frame:GetWidth() or 0
    t:SetHeight(h * 1.2)
    DUI.Motion.Sweep(t, frame, { width = w * 0.35, dur = DUI.Motion.SLOW, alpha = 0.18,
        color = DUI.Style.LOOKS.classic.GOLD[2], inset = -w * 0.2 })
end

function Feel.Open(frame)
    if frame.__feelClosing and DUI.Pad then DUI.Pad.Returning(frame) end
    frame.__feelClosing = nil
    if not frame:IsShown() then glint(frame) end
    local from = frame:IsShown() and frame:GetAlpha() or 0
    local dy = frame:IsShown() and Feel.Offset(frame) or -Feel.RISE
    if not frame:IsShown() then
        frame:SetAlpha(0)
        frame:Show()
    end
    -- Shorter duration when already mostly visible, so a quick reopen never dips.
    local left = 1 - from
    start(frame, "alpha", from, 1, Feel.OPEN * math.max(0.4, left), "sine", function(a) frame:SetAlpha(a) end)
    if dy ~= 0 then
        start(frame, "move", dy, 0, Feel.OPEN, "cubic", function(v) shift(frame, v) end)
    else
        stop(frame, "move")
    end
    if frame.room and Win.Room then Win.Room.Opened(frame) end
end

-- Fade out with a small sink, then hide and reset to rest. Feel.IsOpen
-- returns false from the first frame.
function Feel.Close(frame, done)
    if not frame:IsShown() then run(done); return end
    if frame.__feelClosing then return end
    frame.__feelClosing = true
    if DUI.Pad then DUI.Pad.Leaving(frame) end   -- before the Hide, see Pad.Leaving
    local finish = function()
        if not frame.__feelClosing then return end
        frame.__feelClosing = nil
        stop(frame, "move")
        stop(frame, "slide")
        local at = frame.__feelAt
        if at then at.dx = 0 end   -- reopen at home, not slid aside
        shift(frame, 0)
        frame:Hide()
        frame:SetAlpha(1)
        run(done)
    end
    local dy = Feel.Offset(frame)
    start(frame, "move", dy, dy - Feel.SINK, Feel.CLOSE, "cubic", function(v) shift(frame, v) end)
    start(frame, "alpha", frame:GetAlpha(), 0, Feel.CLOSE, "both", function(a) frame:SetAlpha(a) end, finish)
    if frame.room and Win.Room then Win.Room.Closed(frame) end
end

-- ---------------------------------------------------------------------
-- Pages
-- ---------------------------------------------------------------------

-- Lift pieces in one after another. Each fades in over PIECE and, if it has
-- a single anchor, rises LIFT px. base is the first piece's delay
-- (Feel.HEAD when a window opens, 0 on a page switch).
function Feel.Stagger(pieces, base)
    base = base or 0
    local i = 0
    for _, piece in ipairs(pieces) do
        if not (piece.IsProtected and piece:IsProtected()) then   -- never fade the game's secure frames
            i = i + 1
            Feel.Piece(piece, base + math.min(i - 1, Feel.STEPS - 1) * Feel.STEP)
        end
    end
end

-- A page's shown children in reading order: top to bottom, then left to
-- right, falling back to creation order when positions aren't known yet.
function Feel.Pieces(page)
    local list, n = {}, 0
    for _, c in ipairs({ page:GetChildren() }) do
        if c:IsShown() then
            n = n + 1
            list[n] = { f = c, i = n, top = c.GetTop and c:GetTop(), left = c.GetLeft and c:GetLeft() }
        end
    end
    local function num(v) return type(v) == "number" and not secret(v) end
    table.sort(list, function(x, y)
        if num(x.top) and num(y.top) and math.abs(x.top - y.top) > 2 then return x.top > y.top end
        if num(x.left) and num(y.left) and math.abs(x.left - y.left) > 2 then return x.left < y.left end
        return x.i < y.i
    end)
    for i = 1, n do list[i] = list[i].f end
    return list
end

-- Animate to a new size. dur defaults to Feel.OPEN. Bags pass NORMAL to stay
-- in step with their slots' Feel.Glide.
function Feel.Size(frame, w, h, dur)
    local w0, h0 = frame:GetWidth(), frame:GetHeight()
    if math.abs(w0 - w) < 0.5 and math.abs(h0 - h) < 0.5 then stop(frame, "size"); frame:SetSize(w, h); return end
    start(frame, "size", 0, 1, dur or Feel.OPEN, "cubic", function(p) frame:SetSize(w0 + (w - w0) * p, h0 + (h - h0) * p) end)
end

-- Lift one piece in after `delay` seconds. Fades to piece.restAlpha if set
-- (a dimmed gear slot), otherwise to 1.
function Feel.Piece(piece, delay)
    delay = delay or 0
    stop(piece, "move")
    shift(piece, 0)
    piece:SetAlpha(0)
    start(piece, "alpha", 0, piece.restAlpha or 1, Feel.PIECE, "sine", function(a) piece:SetAlpha(a) end, nil, delay)
    if rest(piece) then
        start(piece, "move", -Feel.LIFT, 0, Feel.PIECE, "cubic", function(v) shift(piece, v) end, nil, delay)
        if delay > 0 then shift(piece, -Feel.LIFT) end
    end
end

-- Finish every move on the frame immediately.
function Feel.Settle(frame)
    local kinds = jobs[frame]
    if not kinds then return end
    jobs[frame] = nil
    for _, j in pairs(kinds) do
        run(j.apply, j.to)
        run(j.done)
    end
end
