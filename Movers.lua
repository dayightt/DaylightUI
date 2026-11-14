-- Every movable DaylightUI frame registers here. Positions are saved as
-- CENTER offsets from UIParent's CENTER in UIParent units, so they survive
-- scale changes. Unlock mode shows a labeled handle over each frame.

local _, DUI = ...
local L = DUI.L

local Movers = {}
DUI.Movers = Movers

Movers.GRID = 16

-- Default positions as CENTER offsets from UIParent's CENTER, stored the same
-- way saves are. A frame with no saved spot, or a reset one, goes here, else
-- to the default its module registered.
Movers.DEFAULTS = {
    ["unitframes.player"] = { -207.78, -303.89 },
    ["unitframes.target"] = { 207.78, -303.89 },
    ["unitframes.focus"] = { 687.78, -176.11 },
    ["unitframes.pet"] = { -256.11, -352.22 },
    ["buffs.buff"] = { 496.11, 543.89 },
}

local entries, order, handles = {}, {}, {}
local grid, gridDirty = nil, true

local function ratio(frame)
    return frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

-- opts.scale: nil means the frame is scaled here (Movers.Scale), false means
-- never scaled (no mouse wheel on its handle), and a function(s) means the
-- area scales its own pieces by s (times any size setting of its own).
-- opts.proxy: the frame is placed by something else (the game's Edit Mode).
-- Its handle moves on its own, the position is saved, and opts.onMoved(key)
-- is called. The frame itself is never touched, unless opts.scale is a
-- function: then the size is still ours (the handle takes the wheel), and
-- that function is the only thing done to the frame.
-- opts.corner: the point it stays pinned by until the player picks one
-- (default CENTER). opts.onCorner(key): for a proxy that places itself,
-- called when one is picked.
-- opts.bottom: starts at the screen's bottom edge with its default function
-- taking its height from Movers.Above, and glides when that room changes.
-- default: { point, rel, relPoint, x, y } for a frame never moved, or a
-- function returning one (a default that follows other settings).
function Movers.Register(frame, key, label, default, opts)
    assert(not entries[key], "mover already registered: " .. key)
    local proxy = opts and opts.proxy or false
    entries[key] = { frame = frame, key = key, label = label, default = default,
                     proxy = proxy, onMoved = opts and opts.onMoved,
                     follow = opts and opts.follow, home = opts and opts.home,
                     minW = opts and opts.minW, minH = opts and opts.minH,
                     active = opts and opts.active, scale = opts and opts.scale,
                     corner = opts and opts.corner, onCorner = opts and opts.onCorner,
                     bottom = opts and opts.bottom }
    order[#order + 1] = key
    if proxy then
        if type(opts.scale) == "function" then Movers.Apply(key) end
        return
    end
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    Movers.Apply(key)
end

function Movers.Get(key) return entries[key] end

-- Every handle's label in English (tests/locale_keys.lua lists them for
-- translation; the handles draw them through L).
function Movers.Labels()
    local out = {}
    for _, key in ipairs(order) do out[#out + 1] = entries[key].label end
    return out
end
function Movers.Handle(key) return handles[key] end

-- Room along the screen's bottom edge. A bar along it (the data bar) reports
-- how tall it is, and pieces never moved by hand start above it. A piece the
-- player placed stays exactly where it is.

Movers.ROOM_GAP = 2
local bottomRoom = 0

function Movers.BottomRoom() return bottomRoom end

-- A default spot y px above the screen's bottom, clear of that room.
function Movers.Above(y)
    if bottomRoom <= 0 then return y end
    return math.max(y, bottomRoom + Movers.ROOM_GAP)
end

function Movers.SetBottomRoom(px)
    if px == bottomRoom then return end
    local moving = {}
    for _, key in ipairs(order) do
        local e = entries[key]
        if e.bottom and not e.suspended and type(e.default) == "function"
           and not Movers.Valid(DUI.DB.Positions()[key]) then
            moving[e] = e.default()[5]
        end
    end
    bottomRoom = px
    for e, y in pairs(moving) do
        Movers.Apply(e.key)
        local d = (y - e.default()[5]) / (e.frame:GetEffectiveScale() / UIParent:GetEffectiveScale())
        -- In combat, a protected piece (an action bar) moves once combat ends.
        if d ~= 0 and e.frame:IsShown() and not (InCombatLockdown() and e.frame:IsProtected()) then
            DUI.Motion.Glide(e.frame, 0, d, DUI.Motion.SLOW)
        end
    end
    DUI.Fire("BottomRoomChanged", px)
end

-- A suspended mover keeps its saved position but stops placing its frame and
-- shows no handle. Used while a frame is attached to another one.
function Movers.Suspend(key, suspended)
    local e = entries[key]
    if not e then return end
    e.suspended = suspended and true or false
    if e.suspended and handles[key] then handles[key]:Hide() end
    if not e.suspended then
        Movers.Apply(key)
        Movers.Recheck(key)
    end
end

-- A saved position is { x, y }, two finite numbers. Anything else (a damaged
-- import, an old bug) is ignored and the frame takes its default spot.
local function finite(n) return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge end
function Movers.Valid(pos)
    return type(pos) == "table" and finite(pos[1]) and finite(pos[2])
end

local function savedAt(key)
    local saved = DUI.DB.Positions()[key]
    if Movers.Valid(saved) then return saved end
end

-- Size: the master Scale (General) times the piece's own, which the mouse
-- wheel over its handle sets in unlock mode (general.frameScales[key]).

Movers.STEP, Movers.MIN, Movers.MAX = 0.05, 0.5, 2

local function pieceScales()
    local g = DUI.DB.General()
    if type(g.frameScales) ~= "table" then g.frameScales = {} end
    return g.frameScales
end

-- The piece's own size (1 = as built).
function Movers.PieceScale(key)
    local v = pieceScales()[key]
    if type(v) ~= "number" or v ~= v then return 1 end
    return math.max(Movers.MIN, math.min(Movers.MAX, v))
end

-- The size a piece is drawn at: the master Scale times its own.
function Movers.Scale(key)
    local g = DUI.DB.General()
    local master = type(g.scale) == "number" and g.scale or 1
    return master * (key and Movers.PieceScale(key) or 1)
end

-- Whether the piece can be sized at all (and so takes the wheel).
function Movers.Scalable(key)
    local e = entries[key]
    if not e or e.scale == false then return false end
    return not e.proxy or type(e.scale) == "function"
end

local function applyScale(e)
    if e.scale == false then return end
    local s = Movers.Scale(e.key)
    if type(e.scale) == "function" then
        e.scale(s)
    elseif e.frame:GetScale() ~= s then
        e.frame:SetScale(s)
    end
end

-- Anchor: which point of a piece stays put (general.frameAnchors[key]), so a
-- growing window grows away from a screen corner. A save still keeps its
-- CENTER offset (x, y, which every reader wants) and adds that point's own
-- offset (at, ax, ay), which is what actually places the frame.

Movers.ANCHORS = { "CENTER", "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
Movers.ANCHOR_SIGN = { CENTER = { 0, 0 }, TOPLEFT = { -1, 1 }, TOP = { 0, 1 }, TOPRIGHT = { 1, 1 }, LEFT = { -1, 0 },
    RIGHT = { 1, 0 }, BOTTOMLEFT = { -1, -1 }, BOTTOM = { 0, -1 }, BOTTOMRIGHT = { 1, -1 } }

local function pieceAnchors()
    local g = DUI.DB.General()
    if type(g.frameAnchors) ~= "table" then g.frameAnchors = {} end
    return g.frameAnchors
end

function Movers.Corner(key)
    local e = entries[key]
    if not e then return nil end
    local at = pieceAnchors()[key]
    return Movers.ANCHOR_SIGN[at] and at or e.corner or "CENTER"
end

-- Whether a piece can be pinned by another point. A proxy only if it places itself.
function Movers.Cornerable(key)
    local e = entries[key]
    return e and (not e.proxy or e.onCorner ~= nil) or false
end

-- Point `at` of a w x h box centered on (x, y).
function Movers.PointOf(at, x, y, w, h)
    local s = Movers.ANCHOR_SIGN[at] or Movers.ANCHOR_SIGN.CENTER
    return x + s[1] * w / 2, y + s[2] * h / 2
end

function Movers.Apply(key)
    local e = entries[key]
    if e.proxy then
        if Movers.Scalable(key) then DUI.AfterCombat(function() applyScale(e) end, "mover:" .. key) end
        return
    end
    -- Attached to another frame (suspended): its area places it, but it still
    -- takes the master Scale.
    if e.suspended then
        DUI.AfterCombat(function() applyScale(e) end, "mover:" .. key)
        return
    end
    DUI.AfterCombat(function()
        local f = e.frame
        applyScale(e)
        local saved = savedAt(key) or Movers.DEFAULTS[key]
        local r = ratio(f)
        f:ClearAllPoints()
        if saved and saved.at and finite(saved.ax) and finite(saved.ay) then
            f:SetPoint(saved.at, UIParent, "CENTER", saved.ax / r, saved.ay / r)
        elseif saved then
            f:SetPoint("CENTER", UIParent, "CENTER", saved[1] / r, saved[2] / r)
        else
            local d = e.default
            if type(d) == "function" then d = d() end
            local rel = d[2]
            if type(rel) == "string" then rel = _G[rel] end
            -- The default's offsets are in UIParent units too, regardless of size.
            f:SetPoint(d[1], rel or UIParent, d[3], (d[4] or 0) / r, (d[5] or 0) / r)
        end
        DUI.Fire("MoverApplied", key)
    end, "mover:" .. key)
end

-- Sets one piece's own size, rounded to a step and clamped to MIN-MAX (1 is
-- stored as nil). The piece is redrawn right away.
function Movers.SetPieceScale(key, v)
    if not Movers.Scalable(key) then return end
    v = math.floor(math.max(Movers.MIN, math.min(Movers.MAX, v)) / Movers.STEP + 0.5) * Movers.STEP
    if math.abs(v - 1) < 0.001 then v = nil end
    pieceScales()[key] = v
    Movers.Apply(key)
    local h = handles[key]
    if h and h:IsShown() then Movers.PlaceHandle(entries[key], h) end
end

-- Frames of ours with no handle of their own (a pop-up, a card, a banner)
-- that should still follow the master Scale, now and on every style change,
-- out of combat. own() optionally returns an extra size on top.
local followers = {}
local function applyFollower(f, own)
    local s = Movers.Scale() * (type(own) == "function" and (tonumber(own()) or 1) or 1)
    if math.abs((f:GetScale() or 1) - s) > 0.001 then f:SetScale(s) end
end

function Movers.FollowScale(frame, own)
    followers[frame] = own or true
    DUI.AfterCombat(function() applyFollower(frame, own) end)
end

function Movers.ApplyAll()
    for _, key in ipairs(order) do Movers.Apply(key) end
    DUI.AfterCombat(function()
        for f, own in pairs(followers) do applyFollower(f, own) end
    end, "mover:followers")
end

-- The frame a mover's handle stands for: the frame itself, or for a proxy
-- (one the game places), the handle standing in for it.
local function moverFrame(e)
    return e.proxy and handles[e.key] or e.frame
end

-- Where a mover's frame is right now, as an unsnapped CENTER offset from
-- UIParent's CENTER in UIParent units, the same numbers Save() stores.
local function liveOffset(f)
    local cx, cy = f:GetCenter()
    if not cx then return nil end
    local r = ratio(f)
    return cx * r - UIParent:GetWidth() / 2, cy * r - UIParent:GetHeight() / 2
end

-- Moves a following proxy's real frame to (x, y), a CENTER offset from
-- UIParent's CENTER. Out of combat only, since the game's bars are protected.
local function place(f, x, y)
    local r = ratio(f)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", x / r, y / r)
end

local function follow(e, x, y)
    if not e.follow or InCombatLockdown() then return end
    -- The game hangs some bars off others (bar 1 off bar 2), so pin the other
    -- following frames where they are to keep them from coming along.
    for _, key in ipairs(order) do
        local o = entries[key]
        if o ~= e and o.follow then
            local ox, oy = liveOffset(o.frame)
            if ox then place(o.frame, ox, oy) end
        end
    end
    place(e.frame, x, y)
end

-- A mover's current position in the same terms as Movers.Positions()[key]:
-- a CENTER offset from UIParent's CENTER. Nil while it can't be read (the
-- frame isn't on screen yet).
function Movers.Position(key)
    local e = entries[key]
    if not e then return nil end
    return liveOffset(moverFrame(e))
end

-- Groups. Pieces in a group (general.frameGroups[key] = its number) move
-- together by any of them: a drag, a nudge or typed X/Y. A group isn't an
-- anchor. Each piece keeps its own saved spot, so it can leave a group right
-- where it is.

local function pieceGroups()
    local g = DUI.DB.General()
    if type(g.frameGroups) ~= "table" then g.frameGroups = {} end
    return g.frameGroups
end

function Movers.GroupOf(key) return pieceGroups()[key] end

-- The pieces in a group, in registration order.
function Movers.Members(group)
    local out, all = {}, pieceGroups()
    for _, key in ipairs(order) do
        if all[key] == group then out[#out + 1] = key end
    end
    return out
end

-- The groups in use, lowest first.
function Movers.Groups()
    local seen, out = {}, {}
    for _, g in pairs(pieceGroups()) do
        if not seen[g] then seen[g] = true; out[#out + 1] = g end
    end
    table.sort(out)
    return out
end

function Movers.NewGroup()
    local g, used = 1, {}
    for _, n in ipairs(Movers.Groups()) do used[n] = true end
    while used[g] do g = g + 1 end
    return g
end

-- A group left with one piece is no longer a group.
local function tidyGroups()
    local all = pieceGroups()
    for _, g in ipairs(Movers.Groups()) do
        local m = Movers.Members(g)
        if #m == 1 then all[m[1]] = nil end
    end
end

function Movers.SetGroup(key, group)
    if not entries[key] then return end
    pieceGroups()[key] = group
    if group == nil then tidyGroups() end
    Movers.PaintGroups()
end

-- key joins (or leaves) owner's group. owner starts a new one if it has none.
function Movers.ToggleInGroup(owner, key)
    if owner == key or not (entries[owner] and entries[key]) then return end
    local all = pieceGroups()
    local g = all[owner]
    if g and all[key] == g then
        return Movers.SetGroup(key, nil)
    end
    if not g then
        g = Movers.NewGroup()
        all[owner] = g
    end
    Movers.SetGroup(key, g)
end

-- Before a piece moves, record where its group stands so each member can
-- follow by the same distance (store, moveCrew). Positions are read once here.
local function mark(e)
    e.crew, e.from = nil, nil
    local g = pieceGroups()[e.key]
    local x, y
    if g then x, y = liveOffset(moverFrame(e)) end
    if not x then return end
    local crew = {}
    for _, key in ipairs(Movers.Members(g)) do
        local o = entries[key]
        local f = o ~= e and not o.suspended and moverFrame(o)
        local ox, oy
        if f then ox, oy = liveOffset(f) end
        if ox then crew[#crew + 1] = { o, ox, oy } end
    end
    if crew[1] then e.crew, e.from = crew, { x, y } end
end

-- Moves the rest of the group live while the piece moves. Nothing saved yet.
local function moveCrew(e, x, y)
    if not e.crew or InCombatLockdown() then return end
    local dx, dy = x - e.from[1], y - e.from[2]
    for _, c in ipairs(e.crew) do
        local f = moverFrame(c[1])
        if f then place(f, c[2] + dx, c[3] + dy) end
        follow(c[1], c[2] + dx, c[3] + dy)
    end
end

-- Writes a mover's spot (a CENTER offset in UIParent units) and places the
-- frame there. The rest of its group moves the same distance.
local function store(e, x, y)
    x = DUI.Pixel.Snap(UIParent, x)
    y = DUI.Pixel.Snap(UIParent, y)
    local pos = { x, y }
    local at = Movers.Corner(e.key)
    if not e.proxy and at ~= "CENTER" then
        local r = ratio(e.frame)
        local ax, ay = Movers.PointOf(at, x, y, (e.frame:GetWidth() or 0) * r, (e.frame:GetHeight() or 0) * r)
        pos.at, pos.ax, pos.ay = at, DUI.Pixel.Snap(UIParent, ax), DUI.Pixel.Snap(UIParent, ay)
    end
    DUI.DB.Positions()[e.key] = pos
    if e.proxy then
        -- Onto the saved (snapped) spot, as other frames land on theirs.
        if handles[e.key] then Movers.PlaceHandle(e, handles[e.key]) end
        follow(e, x, y)
        if e.onMoved then e.onMoved(e.key) end
    else
        Movers.Apply(e.key)
    end
    local crew, from = e.crew, e.from
    e.crew, e.from = nil, nil
    if crew then
        local dx, dy = x - from[1], y - from[2]
        for _, c in ipairs(crew) do store(c[1], c[2] + dx, c[3] + dy) end
    end
end

-- The nearest grid line to an offset from the screen's center (grid lines run
-- through the center, Movers.GRID apart).
function Movers.OnGrid(v)
    return math.floor(v / Movers.GRID + 0.5) * Movers.GRID
end

-- exact keeps the position as is, off the grid (a nudge or typed position).
function Movers.Save(key, exact)
    local e = entries[key]
    local x, y = liveOffset(moverFrame(e))
    if not x then return end
    if DUI.DB.General().gridSnap and not exact then
        x, y = Movers.OnGrid(x), Movers.OnGrid(y)
    end
    store(e, x, y)
end

-- Nudges a mover by exactly one physical screen pixel (whatever the frame's
-- own scale), then saves through Movers.Save, the same path dragging uses.
function Movers.Nudge(key, dx, dy)
    local e = entries[key]
    if not e then return end
    local f = moverFrame(e)
    local cx, cy = f:GetCenter()
    if not cx then return end
    mark(e)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx + DUI.Pixel.Px(f, dx), cy + DUI.Pixel.Px(f, dy))
    Movers.Save(key, true)
end

-- Sets a mover's exact position (a CENTER offset from UIParent's CENTER, as
-- Movers.Position returns and positions[key] stores), then saves through
-- Movers.Save.
function Movers.SetExact(key, x, y)
    local e = entries[key]
    if not e then return end
    local f = moverFrame(e)
    mark(e)
    local r = ratio(f)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", x / r, y / r)
    Movers.Save(key, true)
end

-- Picks the point that stays put. The piece doesn't move.
function Movers.SetCorner(key, at)
    local e = entries[key]
    if not (Movers.Cornerable(key) and Movers.ANCHOR_SIGN[at]) then return end
    local x, y = Movers.Position(key)
    pieceAnchors()[key] = at ~= (e.corner or "CENTER") and at or nil
    if e.onCorner then
        e.onCorner(key)
    elseif x then
        store(e, x, y)
    end
end

-- Changes the point a piece is pinned by until the player picks one
-- (opts.corner), e.g. a panel that now grows the other way. It doesn't move:
-- a spot saved by another point (an old CENTER save, the previous corner) is
-- re-saved by this one where it is now. A point the player picked is kept.
function Movers.SetPin(key, at)
    local e = entries[key]
    if not (e and not e.proxy and Movers.ANCHOR_SIGN[at]) then return end
    local picked = pieceAnchors()[key] ~= nil
    e.corner = at
    if picked then return end
    local saved = savedAt(key)
    if saved and (saved.at or "CENTER") ~= at then
        local x, y = Movers.Position(key)
        if x then store(e, x, y) end
    end
end

-- Magnet: while dragging, edges and centers line up with other frames

Movers.MAGNET = 8 -- how close, in UIParent units, before a snap

-- One axis: each of the dragged frame's three lines (low edge, center, high
-- edge) against each of every other frame's. Flush (its low edge on their
-- high one, or the reverse) beats aligned on a tie, then the nearer frame
-- wins. Returns the move and the line it lands on, or nil.
local function snapAxis(mine, others, lines, range, centreOf, myCentre)
    local bestD, bestFlush, bestNear, bestTo
    for _, o in ipairs(others) do
        local theirs = lines(o)
        local ox, oy = centreOf(o)
        local near = (ox - myCentre[1]) ^ 2 + (oy - myCentre[2]) ^ 2
        for i = 1, 3 do
            for j = 1, 3 do
                local d = theirs[j] - mine[i]
                local ad = math.abs(d)
                if ad <= range then
                    local flush = (i == 1 and j == 3) or (i == 3 and j == 1)
                    local better = bestD == nil or ad < math.abs(bestD) - 1e-6
                    if not better and math.abs(ad - math.abs(bestD)) <= 1e-6 then
                        better = (flush and not bestFlush) or (flush == bestFlush and near < bestNear)
                    end
                    if better then bestD, bestFlush, bestNear, bestTo = d, flush, near, theirs[j] end
                end
            end
        end
    end
    return bestD, bestTo
end

local function centreOf(o) return (o.l + o.r) / 2, (o.b + o.t) / 2 end

function Movers.Magnet(rect, others, range)
    range = range or Movers.MAGNET
    local me = { centreOf(rect) }
    local dx, gx = snapAxis({ rect.l, me[1], rect.r }, others,
        function(o) return { o.l, (o.l + o.r) / 2, o.r } end, range, centreOf, me)
    local dy, gy = snapAxis({ rect.b, me[2], rect.t }, others,
        function(o) return { o.b, (o.b + o.t) / 2, o.t } end, range, centreOf, me)
    return dx, dy, gx, gy
end

local function shiftDown() return type(IsShiftKeyDown) == "function" and IsShiftKeyDown() == true end

-- A frame's rectangle in UIParent units, or nil while it isn't placed.
local function rectOf(f)
    local cx, cy = f:GetCenter()
    if not cx then return nil end
    local r = ratio(f)
    local w, h = (f:GetWidth() or 0) * r / 2, (f:GetHeight() or 0) * r / 2
    cx, cy = cx * r, cy * r
    return { l = cx - w, r = cx + w, b = cy - h, t = cy + h }
end

-- Every other frame with a handle up, plus the screen's center lines and its
-- edges (so a frame can go right into a corner).
local function otherRects(key, crew)
    local out, skip = {}, {}
    for _, c in ipairs(crew or {}) do skip[c[1].key] = true end
    for _, k in ipairs(order) do
        local e, h = entries[k], handles[k]
        if k ~= key and not skip[k] and h and h:IsShown() and not e.suspended then
            local rect = rectOf(moverFrame(e))
            if rect then out[#out + 1] = rect end
        end
    end
    local cx, cy = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    out[#out + 1] = { l = cx, r = cx, b = cy, t = cy }
    out[#out + 1] = { l = 0, r = cx * 2, b = 0, t = cy * 2 }
    return out
end

-- Every registered frame on screen now (with or without handles) as rects in
-- UIParent units, plus the screen's center. The CDM editor's pieces snap to
-- these.
function Movers.FrameRects()
    local out = {}
    for _, k in ipairs(order) do
        local e = entries[k]
        if not e.suspended and e.frame:IsVisible() then
            local rect = rectOf(e.frame)
            if rect and rect.r > rect.l then out[#out + 1] = rect end
        end
    end
    local cx, cy = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    out[#out + 1] = { l = cx, r = cx, b = cy, t = cy }
    return out
end

-- The snap a dragged mover would take now, or nil (Shift held).
local function snapFor(e, others)
    if shiftDown() then return nil end
    local rect = rectOf(moverFrame(e))
    if not rect then return nil end
    return Movers.Magnet(rect, others)
end

-- Guide lines: at most one per direction, spanning the screen, in the accent.
-- They have their own frame since the grid's is hidden while Snap to grid is off.
local guides
local function guideLines()
    if not guides then
        guides = CreateFrame("Frame", nil, UIParent)
        guides:SetAllPoints(UIParent)
        guides:SetFrameStrata("FULLSCREEN_DIALOG")
        guides:EnableMouse(false)
        guides.v = guides:CreateTexture(nil, "OVERLAY")
        guides.h = guides:CreateTexture(nil, "OVERLAY")
        guides.v:Hide(); guides.h:Hide()
    end
    return guides.v, guides.h
end

function Movers.Guides() return guideLines() end

function Movers.ShowGuides(gx, gy)
    if not (gx or gy) and not guides then return end
    local v, hz = guideLines()
    local px = DUI.Pixel.Unit(guides)
    if gx then
        if not v:IsShown() then DUI.Style.PaintAccent(v, 0.9) end
        v:ClearAllPoints()
        v:SetPoint("BOTTOMLEFT", guides, "BOTTOMLEFT", gx - px / 2, 0)
        v:SetSize(px, UIParent:GetHeight())
        v:Show()
    else
        v:Hide()
    end
    if gy then
        if not hz:IsShown() then DUI.Style.PaintAccent(hz, 0.9) end
        hz:ClearAllPoints()
        hz:SetPoint("BOTTOMLEFT", guides, "BOTTOMLEFT", 0, gy - px / 2)
        hz:SetSize(UIParent:GetWidth(), px)
        hz:Show()
    else
        hz:Hide()
    end
end

-- A drop with a guide lit: glide the rest of the way quickly (moving the frame
-- each step, out of combat, which unlock mode already is), then save exactly
-- there, off the grid, with a soft tick. Grabbing it mid-glide cancels the
-- glide.
local function glide(e, h, mover, dx, dy)
    local x0, y0 = liveOffset(moverFrame(e))
    local cx, cy = mover:GetCenter()
    if not (x0 and cx) then Movers.Save(e.key); return end
    local r = ratio(mover)
    local token = {}
    h.glide = token
    DUI.Motion.Tween("mover:" .. e.key, 0, 1, DUI.Motion.FAST, function(p)
        if h.glide ~= token or InCombatLockdown() then return end
        mover:ClearAllPoints()
        mover:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx + dx * p / r, cy + dy * p / r)
        follow(e, x0 + dx * p, y0 + dy * p)
        moveCrew(e, x0 + dx * p, y0 + dy * p)
    end, function()
        if h.glide ~= token then return end
        h.glide = nil
        store(e, x0 + dx, y0 + dy)
        if DUI.Sound then DUI.Sound.Play("snap") end
    end)
end

function Movers.Reset(key)
    local e = entries[key]
    DUI.DB.Positions()[key] = nil
    pieceScales()[key] = nil
    pieceAnchors()[key] = nil
    if e.proxy then
        Movers.Apply(key)
        if e.home then
            local x, y = e.home()
            if x then follow(e, x, y) end
        end
        if e.onMoved then e.onMoved(key) end
        -- After onMoved: a frame the game has put back on its own spot tells where
        -- its handle stands.
        if handles[key] then Movers.PlaceHandle(e, handles[key]) end
    else
        local x0, y0
        if Movers.unlocked and not InCombatLockdown() and DUI.Motion.On() then
            x0, y0 = liveOffset(e.frame)
        end
        Movers.Apply(key)
        -- Reset in unlock mode: it glides home from where it was, its handle with it,
        -- then gets anchored exactly as placed.
        local x1, y1
        if x0 then x1, y1 = liveOffset(e.frame) end
        if x1 and (math.abs(x1 - x0) > 0.5 or math.abs(y1 - y0) > 0.5) then
            DUI.Motion.Tween("mover:" .. key, 0, 1, DUI.Motion.NORMAL, function(p)
                local h = handles[key]
                if InCombatLockdown() or p >= 1 or (h and h.moving) then return end
                place(e.frame, x0 + (x1 - x0) * p, y0 + (y1 - y0) * p)
            end, function()
                local h = handles[key]
                if not (h and h.moving) then Movers.Apply(key) end
            end)
        end
    end
end

-- Things placed outside the movers (the world map) get reset too.
Movers.onResetAll = {}

function Movers.ResetAll()
    for _, key in ipairs(order) do Movers.Reset(key) end
    for _, fn in ipairs(Movers.onResetAll) do fn() end
end

-- Unlock mode

-- A proxy's handle stands at its saved position (or over the frame), sized
-- like the frame. Others simply cover their frame. With live, a following
-- frame on screen gets its handle right over wherever the game actually put
-- it (it can sit off its saved spot due to the game's rounding and scale, or
-- a layout not reloaded yet). Used on unlock.
function Movers.PlaceHandle(e, h, live)
    h:ClearAllPoints()
    if not e.proxy then
        h:SetAllPoints(e.frame)
        return
    end
    local r = ratio(e.frame)
    -- The minimum sizes stand in for a frame that isn't up yet, drawn at the piece's size too.
    local s = Movers.Scalable(e.key) and Movers.Scale(e.key) or 1
    h:SetSize(math.max(e.frame:GetWidth() * r, (e.minW or 0) * s), math.max(e.frame:GetHeight() * r, (e.minH or 0) * s))
    local saved = savedAt(e.key)
    local x, y
    if live and e.follow and e.frame:IsVisible() then
        x, y = liveOffset(e.frame)
    end
    if not x then
        if saved then
            x, y = saved[1], saved[2]
        elseif e.home then
            x, y = e.home()
        end
    end
    if x then
        h:SetPoint("CENTER", UIParent, "CENTER", x, y)
    else
        local cx, cy = e.frame:GetCenter()
        cx, cy = (cx or 0) * r, (cy or 0) * r
        h:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
    end
end

local editor -- the mover editor (below)

-- Shows each visible handle's group.
function Movers.PaintGroups()
    for key, h in pairs(handles) do
        local g = pieceGroups()[key]
        h.groupTag:SetText(g and string.format(L["G%d"], g) or "")
        DUI.Style.InkText(h.groupTag, "pop")
    end
end

local function makeHandle(e)
    local h = CreateFrame("Frame", nil, UIParent)
    h:SetFrameStrata("DIALOG")
    h:SetMovable(e.proxy)
    h:SetClampedToScreen(true)
    h:EnableMouse(true)
    h:RegisterForDrag("LeftButton")
    DUI.Style.Shell(h, { bgAlpha = 0.55 })
    -- The accent tint, repainted every time handles appear (Unlock) so a newly
    -- picked accent shows.
    local tint = h:CreateTexture(nil, "ARTWORK")
    tint:SetAllPoints(h)
    tint:SetColorTexture(1, 1, 1, 1)
    h.tint = tint
    local label = DUI.Style.Text(h, DUI.Style.SIZE.small, "CENTER")
    label:SetPoint("CENTER", h, "CENTER", 0, 0)
    label:SetText(L[e.label])
    DUI.Style.InkText(label, "VALUE")
    -- Its group's number, in the corner.
    h.groupTag = DUI.Style.Text(h, DUI.Style.SIZE.tiny, "RIGHT")
    h.groupTag:SetPoint("TOPRIGHT", h, "TOPRIGHT", -3, -2)
    local mover = e.proxy and h or e.frame
    -- A plain click opens the editor and a drag moves the frame and saves. The
    -- game never starts a drag for a click that doesn't move, so a click is told
    -- apart on mouse-up by whether a drag began.
    h:SetScript("OnMouseDown", function() h.dragging = false end)
    h:SetScript("OnDragStart", function()
        h.dragging = true
        h.moving = true
        h.glide = nil
        mark(e)
        mover:StartMoving()
        -- Snapping to other frames: their positions are read once here.
        h.others = DUI.DB.General().magnet ~= false and otherRects(e.key, e.crew) or nil
        -- A following proxy's real frame tracks the handle as it moves, the rest of a
        -- group follows the piece, and the magnet's guides show the snap it would take.
        if e.follow or h.others or e.crew then
            h:SetScript("OnUpdate", function()
                if e.follow then
                    local x, y = liveOffset(h)
                    if x then follow(e, x, y) end
                end
                if e.crew then
                    local x, y = liveOffset(mover)
                    if x then moveCrew(e, x, y) end
                end
                if h.others then
                    local _, _, gx, gy = snapFor(e, h.others)
                    Movers.ShowGuides(gx, gy)
                end
            end)
        end
    end)
    h:SetScript("OnDragStop", function()
        h.moving = nil
        h:SetScript("OnUpdate", nil)
        mover:StopMovingOrSizing()
        mover:SetUserPlaced(false)
        local dx, dy
        if h.others then dx, dy = snapFor(e, h.others) end
        h.others = nil
        Movers.ShowGuides(nil, nil)
        if dx or dy then glide(e, h, mover, dx or 0, dy or 0) else Movers.Save(e.key) end
    end)
    -- The wheel sizes the piece, and the label briefly shows the size.
    if Movers.Scalable(e.key) then
        h:EnableMouseWheel(true)
        h:SetScript("OnMouseWheel", function(_, delta)
            if InCombatLockdown() or h.moving then return end
            Movers.SetPieceScale(e.key, Movers.PieceScale(e.key) + (delta > 0 and Movers.STEP or -Movers.STEP))
            label:SetText(string.format(L["%s %d%%"], L[e.label], math.floor(Movers.PieceScale(e.key) * 100 + 0.5)))
            local token = {}
            h.sizeShown = token
            C_Timer.After(1.2, function()
                if h.sizeShown == token then label:SetText(L[e.label]) end
            end)
        end)
    end
    h:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            Movers.Reset(e.key)
        elseif button == "LeftButton" and not h.dragging then
            local Ctrl = type(IsControlKeyDown) == "function" and IsControlKeyDown() == true
            if Ctrl and editor and editor.key and editor.key ~= e.key and DUI.Motion.Shown(editor) then
                Movers.ToggleInGroup(editor.key, e.key)
                Movers.RefreshEditor()
                if DUI.Sound then DUI.Sound.Play("snap") end
            else
                Movers.OpenEditor(e.key)
            end
        end
    end)
    return h
end

-- Pooled line textures. Takes the next free one from grid.lines and only
-- creates one when the pool runs out, so rebuilding never grows unbounded.
local function nextLine(n)
    local t = grid.lines[n]
    if not t then
        t = grid:CreateTexture(nil, "BACKGROUND")
        grid.lines[n] = t
    end
    t:Show()
    return t
end

local function layoutGrid()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local cx, cy, step = w / 2, h / 2, Movers.GRID
    local line = DUI.Pixel.Unit(grid)
    local n = 0
    for x = cx % step, w, step do
        n = n + 1
        local t = nextLine(n)
        t:ClearAllPoints()
        t:SetColorTexture(1, 1, 1, math.abs(x - cx) < 0.5 and 0.35 or 0.08)
        t:SetPoint("TOPLEFT", grid, "TOPLEFT", x, 0)
        t:SetSize(line, h)
    end
    for y = cy % step, h, step do
        n = n + 1
        local t = nextLine(n)
        t:ClearAllPoints()
        t:SetColorTexture(1, 1, 1, math.abs(y - cy) < 0.5 and 0.35 or 0.08)
        t:SetPoint("BOTTOMLEFT", grid, "BOTTOMLEFT", 0, y)
        t:SetSize(w, line)
    end
    for i = n + 1, #grid.lines do grid.lines[i]:Hide() end
    gridDirty = false
end

-- Others who want the grid besides unlock mode (the cooldown layout editor).
local gridHolds = {}

local function gridWanted()
    return DUI.DB.General().gridSnap and (Movers.unlocked or next(gridHolds) ~= nil) and true or false
end

local function showGrid(show)
    if not grid then
        grid = CreateFrame("Frame", nil, UIParent)
        grid:SetAllPoints(UIParent)
        grid:SetFrameStrata("BACKGROUND")
        grid.lines = {}
    end
    if not show then
        grid:Hide()
        return
    end
    if gridDirty then layoutGrid() end
    grid:Show()
end

-- The grid shows while unlock mode or a holder wants it and Snap to grid is
-- on. key identifies the holder (the CDM editor holds it while open).
function Movers.HoldGrid(key, on)
    gridHolds[key] = on and true or nil
    showGrid(gridWanted())
end

function Movers.Grid() return grid end

-- The mover editor. Clicking a handle without dragging opens this small
-- window for that one frame. One window, reused for whichever frame was
-- clicked last.

-- Where a piece's settings live (the editor's Options button): its options
-- page and a setting to jump to. Unit frames and bars go by key; the rest are
-- listed.
Movers.OPTIONS = {
    chat = { "Chat.chat" }, tooltip = { "Tooltip.tooltip" },
    infopanel = { "InfoPanel.panel" }, ["infopanel.xp"] = { "InfoPanel.panel" },
    ["infopanel.meter"] = { "InfoPanel.meter" }, ["infopanel.meter.*"] = { "InfoPanel.meter" },
    ["infopanel.threat"] = { "InfoPanel.meter" }, ["infopanel.tracker"] = { "InfoPanel.tracker" },
    ["quests.tracker"] = { "Quests.tracker" }, ["quests.arrow"] = { "Quests.navigation" },
    ["buffs.buff"] = { "Buffs.buffs" }, ["buffs.debuff"] = { "Buffs.debuffs" }, ["qol.loot"] = { "QoL.loot" },
    ["unitframes.playerCastbar"] = { "UnitFrames.castbars" }, ["unitframes.targetCastbar"] = { "UnitFrames.castbars" },
    ["unitframes.focusCastbar"] = { "UnitFrames.castbars" }, ["unitframes.swing"] = { "UnitFrames.swing" },
    ["unitframes.swingMain"] = { "UnitFrames.swing", "swing.bars.main.detach" },
    ["unitframes.swingOff"] = { "UnitFrames.swing", "swing.bars.off.detach" },
    ["unitframes.swingRanged"] = { "UnitFrames.swing", "swing.bars.ranged.detach" },
    ["actionbars.totembar"] = { "ActionBars.barlayout", "bars.totem.visible" },
    ["actionbars.totemtimers"] = { "ActionBars.barlayout", "totemTimers" },
}

-- The options page (and a setting on it to jump to) for a mover, or nil.
function Movers.OptionsOf(key)
    local o = Movers.OPTIONS[key]
    if not o and type(key) == "string" then
        local unit = string.match(key, "^unitframes%.([%a]+)$")
        local bar = string.match(key, "^actionbars%.([%w]+)$")
        -- The player's own meter windows (infopanel.meter.<id>) go to the meters page.
        if string.match(key, "^infopanel%.meter%.") then o = Movers.OPTIONS["infopanel.meter.*"] end
        if unit then o = { "UnitFrames." .. unit, unit .. ".width" }
        elseif bar then o = { "ActionBars.barlayout", "bars." .. bar .. ".visible" } end
    end
    local Options = DUI.Options
    if o and Options and Options.GetPage(o[1]) then return o[1], o[2] end
end

-- Done placing it: unlock mode ends and the options window opens at the
-- piece's settings.
function Movers.OpenOptions(key)
    local page, jump = Movers.OptionsOf(key)
    if not page then return end
    Movers.Lock()
    DUI.OptionsPanel.Show(page)
    if jump then DUI.OptionsPanel.JumpTo({ jump }) end
end

Movers.EDITOR_BUTTON = 56 -- width of each nudge button and X/Y box
Movers.EDITOR_ROW = 24 -- and their height
Movers.EDITOR_GAP = 4 -- gap between them
Movers.EDITOR_HINT = 16 -- room for the line under the title
Movers.ARROWS = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }

local function nudgeButton(parent, dx, dy, text)
    local b = DUI.Widgets.Button(parent, text, Movers.EDITOR_ROW)
    b:SetWidth(Movers.EDITOR_BUTTON)
    b:SetScript("OnClick", function()
        if editor.key then
            Movers.Nudge(editor.key, dx, dy)
            Movers.RefreshEditor()
        end
    end)
    return b
end

local function xyBox(parent, onEnter)
    local W = DUI.Widgets
    local box = W.Input(parent, { height = Movers.EDITOR_ROW, justify = "CENTER" })
    box:SetWidth(Movers.EDITOR_BUTTON)
    box:SetScript("OnEnterPressed", onEnter)
    return box
end

function Movers.AnchorLabels()
    return { CENTER = L["Center"], TOPLEFT = L["Top left"], TOP = L["Top"], TOPRIGHT = L["Top right"], LEFT = L["Left"],
        RIGHT = L["Right"], BOTTOMLEFT = L["Bottom left"], BOTTOM = L["Bottom"], BOTTOMRIGHT = L["Bottom right"] }
end

local function buildEditor()
    local W = DUI.Widgets
    local B, R, G = Movers.EDITOR_BUTTON, Movers.EDITOR_ROW, Movers.EDITOR_GAP
    editor = CreateFrame("Frame", "DaylightUIMoverEditor", UIParent)
    editor.BASE_H = 5 * R + 4 * G + 90 + Movers.EDITOR_HINT
    editor:SetSize(3 * B + 2 * G + 32, editor.BASE_H)
    editor:SetFrameStrata("DIALOG")
    editor:SetToplevel(true)
    editor:EnableMouse(true)
    DUI.Style.Shell(editor)
    editor.title = DUI.Style.Text(editor, DUI.Style.SIZE.head, "CENTER")
    editor.title:SetPoint("TOP", editor, "TOP", 0, -12)
    editor.hint = W.Font(editor, W.BODY, DUI.Style.SIZE.small, W.COLORS.dim)
    editor.hint:SetText(L["Arrow keys move it, Shift a grid step"])
    editor.hint:SetPoint("TOP", editor.title, "BOTTOM", 0, -3)

    -- The four nudges as a cross: Up over Down, Left and Right beside Down.
    editor.up = nudgeButton(editor, 0, 1, L["Up"])
    editor.up:SetPoint("TOP", editor, "TOP", 0, -34 - Movers.EDITOR_HINT)
    editor.down = nudgeButton(editor, 0, -1, L["Down"])
    editor.down:SetPoint("TOP", editor.up, "BOTTOM", 0, -G)
    editor.left = nudgeButton(editor, -1, 0, L["Left"])
    editor.left:SetPoint("RIGHT", editor.down, "LEFT", -G, 0)
    editor.right = nudgeButton(editor, 1, 0, L["Right"])
    editor.right:SetPoint("LEFT", editor.down, "RIGHT", G, 0)

    local function typed()
        local x, y = tonumber(editor.x:GetText()), tonumber(editor.y:GetText())
        if editor.key and x and y then
            Movers.SetExact(editor.key, x, y)
            Movers.RefreshEditor()
        end
        editor.x:ClearFocus()
        editor.y:ClearFocus()
    end

    -- X and Y, each a label over its box, under the left and right nudges.
    editor.x = xyBox(editor, typed)
    editor.x:SetPoint("TOP", editor.left, "BOTTOM", 0, -(G + 16))
    editor.xLabel = W.Font(editor, W.BODY, DUI.Style.SIZE.small, W.COLORS.dim)
    editor.xLabel:SetText("X")
    editor.xLabel:SetPoint("BOTTOM", editor.x, "TOP", 0, 3)
    editor.y = xyBox(editor, typed)
    editor.y:SetPoint("TOP", editor.right, "BOTTOM", 0, -(G + 16))
    editor.yLabel = W.Font(editor, W.BODY, DUI.Style.SIZE.small, W.COLORS.dim)
    editor.yLabel:SetText("Y")
    editor.yLabel:SetPoint("BOTTOM", editor.y, "TOP", 0, 3)

    editor.close = W.Button(editor, DONE or L["Done"], R)
    editor.close:SetPoint("BOTTOMLEFT", editor, "BOTTOMLEFT", 16, 12)
    editor.close:SetPoint("BOTTOMRIGHT", editor, "BOTTOMRIGHT", -16, 12)
    editor.close:SetScript("OnClick", function() DUI.Motion.Vanish(editor) end)
    -- Its settings in the options window, if it has a page.
    editor.options = W.Button(editor, OPTIONS or L["Options"], R)
    editor.options:SetPoint("BOTTOMLEFT", editor.close, "TOPLEFT", 0, G)
    editor.options:SetPoint("BOTTOMRIGHT", editor.close, "TOPRIGHT", 0, G)
    editor.options:SetScript("OnClick", function() if editor.key then Movers.OpenOptions(editor.key) end end)
    -- Which point of it stays put.
    editor.corner = W.MenuButton(editor, "", R)
    editor.corner:SetScript("OnClick", function(self)
        if not editor.key then return end
        W.OpenMenu(self, Movers.ANCHORS, Movers.AnchorLabels(), Movers.Corner(editor.key), function(at)
            Movers.SetCorner(editor.key, at)
            Movers.RefreshEditor()
        end, editor:GetWidth() - 32)
    end)
    -- Which group it moves with.
    editor.group = W.MenuButton(editor, "", R)
    editor.group:SetScript("OnClick", function(self)
        if not editor.key then return end
        local keys, values = { "none" }, { none = NONE or L["None"] }
        for _, g in ipairs(Movers.Groups()) do
            keys[#keys + 1] = g
            values[g] = string.format(L["Group %d (%d)"], g, #Movers.Members(g))
        end
        keys[#keys + 1] = "new"
        values.new = L["New group"]
        W.OpenMenu(self, keys, values, Movers.GroupOf(editor.key) or "none", function(pick)
            if pick == "none" then
                Movers.SetGroup(editor.key, nil)
            elseif pick == "new" then
                Movers.SetGroup(editor.key, Movers.NewGroup())
            else
                Movers.SetGroup(editor.key, pick)
            end
            Movers.RefreshEditor()
        end, editor:GetWidth() - 32)
    end)
    editor.group:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        DUI.Tips.Title(GameTooltip, L["Move together"])
        DUI.Tips.Hint(GameTooltip, L["Ctrl-click"], L["another frame adds it to this group, or takes it out"])
        GameTooltip:Show()
    end)
    editor.group:HookScript("OnLeave", W.HideTooltip)
    -- Arrow keys nudge it while this is open (Shift moves a grid step). Every
    -- other key passes through to the game, and a box being typed in keeps them.
    editor:EnableKeyboard(true)
    editor:SetPropagateKeyboardInput(true)
    editor:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        local arrow = editor.key and Movers.ARROWS[key]
        self:SetPropagateKeyboardInput(not arrow)
        if arrow then
            local step = shiftDown() and Movers.GRID or 1
            Movers.Nudge(editor.key, arrow[1] * step, arrow[2] * step)
            Movers.RefreshEditor()
        end
    end)
    editor:Hide()
    DUI.Motion.Window(editor, 6)
end

-- An offset as the X/Y boxes show it: one decimal, dropped when whole. Spots
-- are saved on screen pixels, which are fractions of a unit, so whole numbers
-- alone would show two spots a pixel or two apart as the same number.
function Movers.ShowOffset(v)
    local s = string.format("%.1f", v)
    s = string.gsub(s, "%.0$", "")
    if s == "-0" then s = "0" end
    return s
end

-- Re-reads the mover's position into the X/Y boxes (after a nudge, or when the
-- editor opens).
function Movers.RefreshEditor()
    if not editor or not DUI.Motion.Shown(editor) or not editor.key then return end
    editor.corner.SetLabel(string.format(L["Anchor: %s"], Movers.AnchorLabels()[Movers.Corner(editor.key)]))
    local g = Movers.GroupOf(editor.key)
    editor.group.SetLabel(g and string.format(L["Group %d (%d)"], g, #Movers.Members(g)) or L["No group"])
    local x, y = Movers.Position(editor.key)
    if not x then return end
    editor.x:SetText(Movers.ShowOffset(x))
    editor.y:SetText(Movers.ShowOffset(y))
end

function Movers.CloseEditor()
    if editor then DUI.Motion.Vanish(editor) end
end

function Movers.OpenEditor(key)
    local e = entries[key]
    if not e then return end
    if not editor then buildEditor() end
    editor.key = key
    local hasOptions, corner = Movers.OptionsOf(key) ~= nil, Movers.Cornerable(key)
    editor.options:SetShown(hasOptions)
    editor.corner:SetShown(corner)
    -- From the bottom up: Done, Options, Anchor, Group, however many there are.
    local G, under, rows = Movers.EDITOR_GAP, hasOptions and editor.options or editor.close, 0
    for _, b in ipairs({ corner and editor.corner or false, editor.group }) do
        if b then
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", under, "TOPLEFT", 0, G)
            b:SetPoint("BOTTOMRIGHT", under, "TOPRIGHT", 0, G)
            under, rows = b, rows + 1
        end
    end
    if not hasOptions then rows = rows - 1 end
    editor:SetHeight(editor.BASE_H + rows * (Movers.EDITOR_ROW + G))
    editor.title:SetText(L[e.label])
    DUI.Style.InkText(editor.title, "pop") -- the accent, read when it opens
    editor:ClearAllPoints()
    local h = handles[key]
    if h then
        -- Below the frame, unless there's no room under it, then above.
        local bottom, eh = h:GetBottom(), editor:GetHeight()
        if type(bottom) == "number" and type(eh) == "number"
            and bottom * h:GetEffectiveScale() < (eh + 8) * editor:GetEffectiveScale() then
            editor:SetPoint("BOTTOM", h, "TOP", 0, 8)
        else
            editor:SetPoint("TOP", h, "BOTTOM", 0, -8)
        end
    else
        editor:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    editor:Show()
    Movers.RefreshEditor()
end

function Movers.Editor() return editor end

-- A "Lock" button at the top middle of the screen for as long as unlock mode
-- is on, however it was started (options window, /dui unlock, the panel
-- button). It ends unlock mode, and the options window (if unlocking hid it)
-- listens for that and reopens itself.
local lockButton

-- "Snap to grid" and "Snap to frames" (the magnet, Movers.Magnet): the same
-- settings as on the Layout page, lit while on. Unlock mode's bar and the
-- cooldown layout editor's pill each make a pair, and Sync() re-reads the
-- setting since the other pair may have flipped it.
function Movers.SnapButtons(parent, height, width)
    local W = DUI.Widgets
    local snap = W.Button(parent, L["Snap to grid"], height)
    snap.FitWidth(width)
    function snap.Sync() snap.SetActive(DUI.DB.General().gridSnap and true or false) end
    snap:SetScript("OnClick", function()
        DUI:Set("general", "gridSnap", not DUI.DB.General().gridSnap)
        snap.Sync()
        showGrid(gridWanted())
    end)
    local mag = W.Button(parent, L["Snap to frames"], height)
    mag.FitWidth(width)
    function mag.Sync() mag.SetActive(DUI.DB.General().magnet ~= false) end
    mag:SetScript("OnClick", function()
        DUI:Set("general", "magnet", DUI.DB.General().magnet == false)
        mag.Sync()
    end)
    snap.Sync()
    mag.Sync()
    return snap, mag
end

-- A dark pill behind unlock mode's buttons. They have no fill of their own
-- (they're made for our windows), so over the bare world they were see-through
-- and a handle under them showed through.
local PILL_PAD = 8
local function pill()
    local p = CreateFrame("Frame", nil, UIParent)
    -- Above the movers (DIALOG) so a mover parked at the top middle of the screen
    -- can't cover it.
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetFrameLevel(100)
    p:EnableMouse(true)
    DUI.Style.Shell(p, {})
    return p
end

local function showLockButton(show)
    if show and not lockButton then
        local bar = pill()
        bar:SetPoint("TOP", UIParent, "TOP", 0, -16)
        bar:SetHeight(30 + 2 * PILL_PAD)
        lockButton = DUI.Widgets.Button(bar, L["Lock"], 30)
        lockButton:SetFrameLevel(bar:GetFrameLevel() + 2)
        lockButton:SetPoint("LEFT", bar, "LEFT", PILL_PAD, 0)
        lockButton.FitWidth(120)
        lockButton:SetScript("OnClick", Movers.Lock)
        lockButton.bar = bar

        -- "Snap to grid" and "Snap to frames" beside it.
        local snap, mag = Movers.SnapButtons(bar, 30, 120)
        snap:SetFrameLevel(bar:GetFrameLevel() + 2)
        snap:SetPoint("LEFT", lockButton, "RIGHT", 8, 0)
        mag:SetFrameLevel(bar:GetFrameLevel() + 2)
        mag:SetPoint("LEFT", snap, "RIGHT", 8, 0)
        lockButton.snap, lockButton.magnet = snap, mag
        bar:SetWidth(PILL_PAD + lockButton:GetWidth() + 8 + snap:GetWidth()
            + 8 + mag:GetWidth() + PILL_PAD)

        -- The setup guide was never finished, so moves are lost at logout. Shown lit
        -- under the bar, with the reason on hover. A click opens the guide.
        local under = pill()
        under:SetPoint("TOP", bar, "BOTTOM", 0, -6)
        under:SetHeight(26 + 2 * PILL_PAD)
        local setup = DUI.Widgets.Button(under, L["Finish setup to keep your moves"], 26)
        setup:SetFrameLevel(under:GetFrameLevel() + 2)
        setup:SetPoint("CENTER", under, "CENTER", 0, 0)
        setup.FitWidth(120)
        under:SetWidth(setup:GetWidth() + 2 * PILL_PAD)
        setup.bar = under
        setup.SetActive(true)
        setup:HookScript("OnEnter", function(self) DUI.Installer.UnsavedTip(self) end)
        setup:HookScript("OnLeave", DUI.Widgets.HideTooltip)
        setup:SetScript("OnClick", function() DUI.Installer.OpenToSave() end)
        lockButton.setup = setup
    end
    if lockButton then
        lockButton.bar:SetShown(show)
        lockButton:SetShown(show)
        lockButton.snap:SetShown(show)
        lockButton.magnet:SetShown(show)
        local setup = show and DUI.DB.Unsaved()
        lockButton.setup.bar:SetShown(setup)
        lockButton.setup:SetShown(setup)
        if show then
            lockButton.snap.Sync()
            lockButton.magnet.Sync()
        end
    end
end

function Movers.LockButton() return lockButton end
function Movers.SnapButton() return lockButton and lockButton.snap end
function Movers.MagnetButton() return lockButton and lockButton.magnet end
function Movers.SetupButton() return lockButton and lockButton.setup end

-- Areas whose handles the unlock box can tuck away, so the ones under them
-- can be reached. A handle belongs to the first area its key matches.
Movers.AREAS = {
    { id = "cast",       label = "Cast Bars",     match = "^unitframes%.%a*[Cc]astbar" },
    { id = "group",      label = "Group Frames",  match = "^unitframes%.raid" },
    { id = "group",      match = "^unitframes%.party" },
    { id = "group",      match = "^unitframes%.arena" },
    { id = "unit",       label = "Unit Frames",   match = "^unitframes%." },
    { id = "actionbars", label = "Action Bars",   match = "^actionbars%." },
    { id = "buffs",      label = "Buffs",         match = "^buffs%." },
    { id = "infopanel",  label = "Info Panel",    match = "^infopanel" },
    { id = "quests",     label = "Quests",        match = "^quests%." },
    { id = "chat",       label = "Chat",          match = "^chat" },
    { id = "bags",       label = "Bags",          match = "^bags%." },
    { id = "tooltip",    label = "Tooltip",       match = "^tooltip" },
    { id = "combattext", label = "Combat Text",   match = "^combattext%." },
    { id = "game",       label = "Game Frames",   match = "^game%." },
    { id = "other",      label = "Other",         match = "" },
}

function Movers.AreaOf(key)
    for _, a in ipairs(Movers.AREAS) do
        if string.find(key, a.match) then return a.id end
    end
    return "other"
end

-- Account-wide, like the test box's choices.
local function hiddenAreas()
    local root = DUI.DB.Root()
    if type(root.unlockHidden) ~= "table" then root.unlockHidden = {} end
    return root.unlockHidden
end

function Movers.AreaShown(id) return hiddenAreas()[id] ~= true end

-- A frame in use whose handle would show while unlocked, whatever the box says.
function Movers.InUse(key)
    local e = entries[key]
    return e ~= nil and not e.suspended and not (e.active and not e.active())
end

-- The areas with at least one handle in use, in AREAS order.
function Movers.Areas()
    local used, out, seen = {}, {}, {}
    for _, key in ipairs(order) do
        if Movers.InUse(key) then used[Movers.AreaOf(key)] = true end
    end
    for _, a in ipairs(Movers.AREAS) do
        if a.label and used[a.id] and not seen[a.id] then
            seen[a.id] = true
            out[#out + 1] = { key = a.id, label = a.label }
        end
    end
    return out
end

-- While unlocked, a frame's handle shows if it's in use and its area isn't
-- tucked away, else it's hidden. active is an optional check that the frame is
-- in use at all (a bar set to Hidden, a bag bar turned off), rechecked when its
-- setting changes.
function Movers.Recheck(key)
    local e = entries[key]
    if not (e and Movers.unlocked) then return end
    if not Movers.InUse(key) or not Movers.AreaShown(Movers.AreaOf(key)) then
        if handles[key] then handles[key]:Hide() end
        return
    end
    handles[key] = handles[key] or makeHandle(e)
    Movers.PlaceHandle(e, handles[key], true)
    DUI.Style.PaintAccent(handles[key].tint, 0.25)
    handles[key]:Show()
    Movers.PaintGroups()
end

-- The unlock box's tick: the area's handles fade out (then hide) or back in.
function Movers.SetAreaShown(id, on)
    on = on and true or false
    if Movers.AreaShown(id) == on then return end
    hiddenAreas()[id] = (not on) or nil
    if Movers.unlocked then
        local list = {}
        for _, key in ipairs(order) do
            if Movers.AreaOf(key) == id then
                local h = handles[key]
                if on then
                    Movers.Recheck(key)
                    h = handles[key]
                    if h and h:IsShown() then h:SetAlpha(0); list[#list + 1] = h end
                elseif h and h:IsShown() then
                    list[#list + 1] = h
                end
            end
        end
        if not on and editor and editor.key and Movers.AreaOf(editor.key) == id then Movers.CloseEditor() end
        DUI.Motion.Tween("movers:area:" .. id, on and 0 or 1, on and 1 or 0, DUI.Motion.FAST, function(p)
            for _, h in ipairs(list) do h:SetAlpha(p) end
        end, function()
            if Movers.AreaShown(id) then return end
            for _, h in ipairs(list) do h:Hide(); h:SetAlpha(1) end
        end)
    end
    DUI.Fire("UnlockAreaChanged", id, on)
end

-- Unlock mode's handles and grid fade in together (one tween for all) and out
-- the same way on Lock. A fight locks them at once.
local unlockP = 1
local function paintUnlock(p)
    unlockP = p
    for _, h in pairs(handles) do if h:IsShown() then h:SetAlpha(p) end end
    if grid and grid:IsShown() then grid:SetAlpha(p) end
end

local function unlockDone()
    if Movers.unlocked then return end
    paintUnlock(1) -- back to full for next time, then hidden
    for _, h in pairs(handles) do h:Hide() end
    showGrid(gridWanted())
end

function Movers.Unlock()
    if InCombatLockdown() then
        DUI.Print(L["Can't unlock frames during combat."])
        return false
    end
    Movers.unlocked = true
    for _, key in ipairs(order) do Movers.Recheck(key) end
    showGrid(gridWanted())
    local from = unlockP < 1 and unlockP or 0
    DUI.Motion.Tween("movers:unlock", from, 1, DUI.Motion.FAST, paintUnlock)
    showLockButton(true)
    DUI.Fire("UnlockChanged", true)
    DUI.Print(L["Unlocked. Drag to move, scroll to resize, right-click to put back, /dui lock when done."])
    if DUI.DB.Unsaved() then
        DUI.Print(L["This character hasn't finished the setup guide, so moved frames go back when you log out. Type /dui install to finish it."])
    end
    return true
end

function Movers.Lock()
    if not Movers.unlocked then return end
    Movers.unlocked = false
    if InCombatLockdown() then
        DUI.Motion.Tween("movers:unlock", 0, 0, 0)
        unlockDone()
    else
        DUI.Motion.Tween("movers:unlock", unlockP, 0, DUI.Motion.FAST, paintUnlock, unlockDone)
    end
    showLockButton(false)
    Movers.CloseEditor()
    DUI.Fire("UnlockChanged", false)
end

DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if not Movers.unlocked then return end
    for _, key in ipairs(order) do entries[key].frame:StopMovingOrSizing() end
    -- A drag cut short by combat ends as if dropped where it is (no snap glide):
    -- saved, with its follow OnUpdate turned off.
    for _, h in pairs(handles) do
        if h.moving then
            h.others = nil
            h:GetScript("OnDragStop")(h)
        end
    end
    Movers.Lock()
    DUI.Print(L["Frames locked for combat."])
end)

DUI.On("StyleChanged", function()
    Movers.ApplyAll()
    if grid then
        gridDirty = true
        showGrid(gridWanted())
        if Movers.unlocked and lockButton then lockButton.snap.Sync() end
    end
end)

DUI.RegisterCommand("unlock", Movers.Unlock, L["/dui unlock - move frames"])
DUI.RegisterCommand("lock", Movers.Lock, L["/dui lock - finish moving"])
DUI.RegisterCommand("reset", function()
    Movers.ResetAll()
    DUI.Print(L["All frames are back in their default places."])
end, L["/dui reset - put every frame back"])
