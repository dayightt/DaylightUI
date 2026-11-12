-- Where a piece sits on a unit frame or nameplate bar: one of nine spots on
-- the frame or just outside one side, which way a row of icons grows from
-- there, and a nudge. Pure math with no frames, so tests can run it on plain
-- tables. The angled end stays clear: a spot on that side moves in by the cut
-- and a row inside gets shorter by it. Lives in core so unit frames and
-- nameplates can share it whichever is enabled.
--
-- box fields, all in px, missing = 0: w, h, padX, padY, cutL, cutR,
-- topInset, bottomInset, topReserve, above, below, outL, outR, aboveInL,
-- aboveInR, belowInL, belowInR, corners.
--   topInset/bottomInset push top and bottom spots in (for the power bar).
--   topReserve shortens a top row (for a corner icon).
--   above/below push outside spots out (for a name tab).
--   outL/outR push spots beside that side out (a portrait ring past the end).
--   aboveIn*/belowIn* move a row above or below the frame inward from that
--   end (to clear the ring, or start after the name tab).
--   corners = { [spot] = px } marks an icon at that inside spot, so a row
--   there starts past it and never covers the role icon or raid marker.

local _, DUI = ...

local Spots = {}
DUI.Spots = Spots

Spots.ORDER = { "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright",
                "above", "below", "outleft", "outright",
                "outtopleft", "outtopright", "outbottomleft", "outbottomright" }
Spots.LABELS = { topleft = "Top left", top = "Top", topright = "Top right", left = "Left", center = "Middle",
                 right = "Right", bottomleft = "Bottom left", bottom = "Bottom", bottomright = "Bottom right",
                 above = "Outside: above", below = "Outside: below", outleft = "Outside: left",
                 outright = "Outside: right", outtopleft = "Outside: top left", outtopright = "Outside: top right",
                 outbottomleft = "Outside: bottom left", outbottomright = "Outside: bottom right" }
Spots.GROW_ORDER = { "right", "left", "center" }
Spots.GROW_LABELS = { right = "To the right", left = "To the left", center = "From the middle" }
Spots.GAP = 2 -- gap between the frame and a piece outside it
Spots.DOT_OUT = 8 -- how far outside the frame an outside spot's dot sits
Spots.MAGNET = 3 -- a drop this close to a dot snaps to it (a light snap, pieces can go anywhere)

-- Inside spots: column (L, C, R) and row (T, M, B).
local INSIDE = { topleft = { "L", "T" }, top = { "C", "T" }, topright = { "R", "T" },
                 left = { "L", "M" }, center = { "C", "M" }, right = { "R", "M" },
                 bottomleft = { "L", "B" }, bottom = { "C", "B" }, bottomright = { "R", "B" } }
local V, H = { T = "TOP", M = "", B = "BOTTOM" }, { L = "LEFT", C = "", R = "RIGHT" }
-- Spots beside the frame or off its corners: the row and column they hang off.
local BESIDE = { outleft = { "M", "L" }, outright = { "M", "R" }, outtopleft = { "T", "L" },
                 outtopright = { "T", "R" }, outbottomleft = { "B", "L" }, outbottomright = { "B", "R" } }

local function point(v, h)
    local p = V[v] .. H[h]
    return p == "" and "CENTER" or p
end

local function n(v) return tonumber(v) or 0 end

-- The fixed end of a row: left end when growing right, right end when growing
-- left, middle when growing both ways.
local function pinned(grow)
    if grow == "left" then return "R" elseif grow == "center" then return "C" end
    return "L"
end

function Spots.Valid(spot) return Spots.LABELS[spot] ~= nil end

-- Returns { point, relPoint, x, y, flowAnchor, hDir, vDir, line }. The row is
-- placed with SetPoint(point, frame, relPoint, x, y), flows from flowAnchor
-- along hDir then vDir, and may be at most `line` px wide.
-- opts: { x, y (the nudge), line (the wanted row width) }.
function Spots.Layout(spot, grow, box, opts)
    opts = opts or {}
    local w, padX, padY = n(box.w), n(box.padX), n(box.padY)
    local cutL, cutR = n(box.cutL), n(box.cutR)
    if not Spots.Valid(spot) then spot = "center" end
    if grow ~= "left" and grow ~= "center" then grow = "right" end
    local pin = pinned(grow)
    local L = {}
    if INSIDE[spot] then
        local col, row = INSIDE[spot][1], INSIDE[spot][2]
        L.point, L.relPoint = point(row, pin), point(row, col)
        local icon = type(box.corners) == "table" and n(box.corners[spot]) or 0
        if col == "C" then icon = 0 end
        L.x = (col == "L" and padX + cutL + icon) or (col == "R" and -(padX + cutR + icon)) or 0
        L.y = (row == "T" and -(padY + n(box.topInset))) or (row == "B" and padY + n(box.bottomInset)) or 0
        L.vDir = row == "B" and "Up" or "Down"
        L.hDir = grow == "left" and "Left" or "Right"
        local room = w - 2 * padX - cutL - cutR - icon
        if row == "T" then room = room - n(box.topReserve) end
        room = math.max(1, room)
        L.line = math.min(opts.line or room, room)
    elseif spot == "above" or spot == "below" then
        local up = spot == "above"
        L.point = point(up and "B" or "T", pin)
        L.relPoint = point(up and "T" or "B", pin)
        local key = up and "aboveIn" or "belowIn"
        L.x = (pin == "L" and n(box[key .. "L"])) or (pin == "R" and -n(box[key .. "R"])) or 0
        L.y = up and (Spots.GAP + n(box.above)) or -(Spots.GAP + n(box.below))
        L.vDir = up and "Up" or "Down"
        L.hDir = grow == "left" and "Left" or "Right"
        L.line = opts.line or w
    else
        -- Beside the frame or off a corner: the piece's facing side meets the
        -- frame's and it grows away from the frame.
        local o = BESIDE[spot]
        local left = o[2] == "L"
        L.point = point(o[1] == "T" and "B" or (o[1] == "B" and "T" or "M"), left and "R" or "L")
        L.relPoint = point(o[1], o[2])
        L.x = left and -(Spots.GAP + n(box.outL)) or Spots.GAP + n(box.outR)
        L.y = (o[1] == "T" and Spots.GAP + n(box.above)) or (o[1] == "B" and -(Spots.GAP + n(box.below))) or 0
        L.vDir, L.hDir = o[1] == "T" and "Up" or "Down", left and "Left" or "Right"
        L.line = opts.line or w
    end
    L.flowAnchor = (L.vDir == "Down" and "TOP" or "BOTTOM") .. (L.hDir == "Left" and "RIGHT" or "LEFT")
    L.x, L.y = L.x + n(opts.x), L.y + n(opts.y)
    return L
end

-- Dots offered in Design mode: { spot, x, y } in px from the frame's top-left,
-- y pointing down.
function Spots.Dots(box)
    local w, h, padX, padY = n(box.w), n(box.h), n(box.padX), n(box.padY)
    local X = { L = padX + n(box.cutL), C = w / 2, R = w - padX - n(box.cutR) }
    local Y = { T = padY, M = h / 2, B = h - padY }
    local out = {}
    for _, s in ipairs(Spots.ORDER) do
        local p, x, y = INSIDE[s]
        if p then x, y = X[p[1]], Y[p[2]]
        elseif s == "above" then x, y = w / 2, -Spots.DOT_OUT
        elseif s == "below" then x, y = w / 2, h + Spots.DOT_OUT
        else
            local o = BESIDE[s]
            x = o[2] == "L" and -Spots.DOT_OUT - n(box.outL) or w + Spots.DOT_OUT + n(box.outR)
            y = (o[1] == "T" and -Spots.DOT_OUT) or (o[1] == "B" and h + Spots.DOT_OUT) or h / 2
        end
        out[#out + 1] = { spot = s, x = x, y = y }
    end
    return out
end

local function nearest(dots, x, y)
    local best, bestD
    for _, d in ipairs(dots) do
        local dx, dy = d.x - x, d.y - y
        local dd = dx * dx + dy * dy
        if not bestD or dd < bestD then best, bestD = d, dd end
    end
    return best, bestD
end

function Spots.Nearest(dots, x, y)
    local d = nearest(dots, x, y)
    return d and d.spot
end

-- A grip dragged by delta px from start, clamped to min..max and rounded to step.
function Spots.Resize(start, delta, min, max, step)
    step = step or 1
    local v = math.floor((start + delta) / step + 0.5) * step
    return math.max(min, math.min(max, v))
end

-- A drop at x, y (dot coordinates): returns the nearest spot and the nudge
-- that keeps the piece where it was dropped (0, 0 within MAGNET of the dot).
-- The nudge's y points up, as SetPoint expects.
function Spots.Drop(dots, x, y)
    local d, dd = nearest(dots, x, y)
    if not d then return nil, 0, 0 end
    if dd <= Spots.MAGNET * Spots.MAGNET then return d.spot, 0, 0 end
    return d.spot, math.floor(x - d.x + 0.5), math.floor(d.y - y + 0.5)
end
