-- Keeps windows from opening on top of each other. A newly opened window keeps
-- its spot and the others slide aside, then slide back home when it closes.
-- Similar to the game's panel layout, but it also works for dragged windows.
--
-- Windows opt in with `f.room = true` (Win.New sets it). Feel.Open/Close call
-- Room.Opened/Closed.

local _, DUI = ...

local Win = DUI.Win
local Feel = Win.Feel

local Room = {}
Win.Room = Room

Room.GAP = 8      -- UIParent units between two windows set side by side
Room.EDGE = 4     -- margin from the screen edge

local order = {}  -- open windows taking part, newest first

local function num(v) return type(v) == "number" and not (issecretvalue and issecretvalue(v)) end

local function forget(f)
    for i = #order, 1, -1 do if order[i] == f then table.remove(order, i) end end
end

-- The window's resting rect in UIParent units, ignoring any slide and using
-- the size it is animating toward. nil if the client can't tell yet.
local function home(f)
    if type(f.GetLeft) ~= "function" or type(f.GetTop) ~= "function" then return nil end
    local l, t = f:GetLeft(), f:GetTop()
    local w = num(f.goalW) and f.goalW or f:GetWidth()
    local h = num(f.goalH) and f.goalH or f:GetHeight()
    if not (num(l) and num(t) and num(w) and num(h)) then return nil end
    local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    l = (l - Feel.OffsetX(f)) * k
    t = (t - Feel.Offset(f)) * k   -- an opening window counts where it will land
    return { l = l, r = l + w * k, t = t, b = t - h * k, k = k }
end

local function covers(a, b)
    return a.l < b.r and b.l < a.r and a.b < b.t and b.b < a.t
end

local function first(rect, placed)
    for _, p in ipairs(placed) do if covers(rect, p) then return p end end
end

local function at(r, x) local w = r.r - r.l; return { l = x, r = x + w, t = r.t, b = r.b, k = r.k } end

-- Nearest x where r overlaps no placed window. Tries right, then left. If
-- neither fits on screen, clamps toward the side with more room.
local function clear(r, placed, screen)
    if not first(r, placed) then return r.l end
    local function walk(dir)
        local s = r
        for _ = 1, #placed + 1 do
            local p = first(s, placed)
            if not p then return s end
            s = at(s, dir > 0 and p.r + Room.GAP or p.l - Room.GAP - (s.r - s.l))
        end
        return s
    end
    local right, left = walk(1), walk(-1)
    if not screen then return right.l end
    local function fits(s) return s.l >= Room.EDGE and s.r <= screen - Room.EDGE and not first(s, placed) end
    local dr, dl = math.abs(right.l - r.l), math.abs(left.l - r.l)
    if fits(right) and (not fits(left) or dr <= dl) then return right.l end
    if fits(left) then return left.l end
    local lo, hi = Room.EDGE, screen - Room.EDGE - (r.r - r.l)
    local x = (screen - r.r >= r.l) and right.l or left.l
    return math.max(lo, math.min(hi, x))
end

-- Re-lays every open window. The newest stays home and each older one slides
-- to the nearest clear spot. Windows that can't move in combat (Win.Held) stay
-- put and get laid out again after the fight.
function Room.Lay()
    local placed, fight = {}, false
    local screen = UIParent.GetWidth and UIParent:GetWidth()
    if not num(screen) or screen <= 0 then screen = nil end
    -- Place held windows first so new ones make room around them. The
    -- spellbook's cast layer sits above every window, so anything opened over
    -- it would steal its clicks.
    local free = {}
    for _, f in ipairs(order) do
        local r = home(f)
        if r and f.IsProtected ~= nil and Win.Held(f) then
            placed[#placed + 1] = at(r, r.l + Feel.OffsetX(f) * r.k)
            fight = true
        elseif r then
            free[#free + 1] = { f = f, r = r }
        end
    end
    for _, e in ipairs(free) do
        local r = e.r
        local x = #placed > 0 and clear(r, placed, screen) or r.l
        Feel.Slide(e.f, (x - r.l) / r.k)
        placed[#placed + 1] = at(r, x)
    end
    if fight then DUI.AfterCombat(Room.Lay, "winRoom") end
end

function Room.Opened(f)
    forget(f)
    table.insert(order, 1, f)
    Room.Lay()
end

function Room.Closed(f)
    forget(f)
    Room.Lay()
end

-- Called when an open window resizes or is dragged. It keeps its spot and the
-- others make room again.
function Room.Changed(f)
    if not (f.room and Feel.IsOpen(f)) then return end
    forget(f)
    table.insert(order, 1, f)
    Room.Lay()
end
