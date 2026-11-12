-- Arrows between talents (the game's visibleEdges), drawn as flat lines with a
-- chevron head. They run straight down, straight across, or across then down.
-- Positions come from grid coordinates, not from the tiles, so a tile that
-- animates never bends its arrow.
--
-- When a talent hits its last rank, light runs down each outgoing arrow
-- (Arrows.Fill) and Undo drains it back (Arrows.Drain). Full arrows breathe
-- softly and fire a spark down every few seconds, staggered by row. One
-- OnUpdate driver per tree grid, parented to it, so nothing runs while the
-- window is closed. With motion off the glow stays but there are no sparks.

local _, DUI = ...
DUI.Book = DUI.Book or {}   -- the book window's own namespace
local ns = DUI.Book

local Arrows = {}
ns.Arrows = Arrows

Arrows.WIDTH = 3
Arrows.HEAD = 10
Arrows.GAP = 3        -- room between a tile's edge and the line
Arrows.OFF = { 0.17, 0.165, 0.185 }
Arrows.LIT = { 0.95, 0.76, 0.31 }       -- source talent is maxed (gold)
Arrows.STAGED = { 0.39, 0.82, 0.48 }    -- maxed but not applied yet (green)
Arrows.CHEVRON = DUI.MEDIA .. "ui-chevron.png"   -- points down

Arrows.RUN = 0.45     -- seconds for the light to run an arrow's length

Arrows.GLOW = DUI.MEDIA .. "glow.png"
Arrows.HALO = 12      -- glow width along a full arrow, px
Arrows.MOTE = 14      -- spark size
Arrows.BLOOM = 28     -- flash size on the head
Arrows.TRAVEL = 0.8   -- seconds for a spark to run down, tail included
Arrows.REST = 1.9     -- pause between sparks
Arrows.STAGGER = 0.35 -- extra delay per row
Arrows.TAIL = {       -- px behind the spark, alpha, size (times MOTE)
    { 0, 1, 1 }, { 5, 0.55, 0.75 }, { 10, 0.3, 0.55 }, { 16, 0.14, 0.4 },
}

local WHITE = "Interface\\Buttons\\WHITE8X8"
local Motion = DUI.Motion

local function glowTex(parent, sub)
    local t = parent:CreateTexture(nil, "BORDER", nil, sub)
    t:SetTexture(Arrows.GLOW)
    t:SetBlendMode("ADD")
    t:Hide()
    return t
end

function Arrows.New(parent)
    local a = { parent = parent, segs = {} }
    for i = 1, 2 do
        local t = parent:CreateTexture(nil, "BORDER")
        t:SetTexture(WHITE)
        a.segs[i] = t
    end
    a.head = parent:CreateTexture(nil, "BORDER", nil, 1)
    a.head:SetTexture(Arrows.CHEVRON)
    a.head:SetSize(Arrows.HEAD, Arrows.HEAD)
    a.lit = {}
    for i = 1, 2 do
        local t = parent:CreateTexture(nil, "BORDER", nil, 2)
        t:SetTexture(WHITE)
        t:Hide()
        a.lit[i] = t
    end
    a.halo = { glowTex(parent, -1), glowTex(parent, -1) }
    a.motes = {}
    for i, spec in ipairs(Arrows.TAIL) do
        local t = glowTex(parent, 3)
        t:SetSize(Arrows.MOTE * spec[3], Arrows.MOTE * spec[3])
        a.motes[i] = t
    end
    a.bloom = glowTex(parent, 3)
    a.bloom:SetSize(Arrows.BLOOM, Arrows.BLOOM)
    return a
end

-- One straight segment, y measured down from the grid's top-left. Segments
-- are always horizontal or vertical.
local function seg(t, parent, x1, y1, x2, y2)
    local w = Arrows.WIDTH
    local left, top = math.min(x1, x2), math.min(y1, y2)
    local width, height = math.abs(x2 - x1), math.abs(y2 - y1)
    if width < 1 and height < 1 then t:Hide() return end
    t:ClearAllPoints()
    if width < 1 then
        t:SetPoint("TOPLEFT", parent, "TOPLEFT", left - w / 2, -top)
        t:SetSize(w, height)
    else
        t:SetPoint("TOPLEFT", parent, "TOPLEFT", left, -(top - w / 2))
        t:SetSize(width + (height >= 1 and w / 2 or 0), w)
    end
    t:Show()
end

-- Stretch the glow's middle row or column so the halo is soft across the
-- line and even along it.
local function halo(t, parent, x1, y1, x2, y2)
    local w = Arrows.HALO
    local left, top = math.min(x1, x2), math.min(y1, y2)
    local width, height = math.abs(x2 - x1), math.abs(y2 - y1)
    t:ClearAllPoints()
    if width < 1 then
        t:SetPoint("TOPLEFT", parent, "TOPLEFT", left - w / 2, -top)
        t:SetSize(w, math.max(height, 1))
        t:SetTexCoord(0, 1, 0.5, 0.5)
    else
        t:SetPoint("TOPLEFT", parent, "TOPLEFT", left, -(top - w / 2))
        t:SetSize(width, w)
        t:SetTexCoord(0.5, 0.5, 0, 1)
    end
end

-- from, to: { col, row }. pitch is the tile spacing (px overrides it
-- horizontally), size is one tile.
function Arrows.Place(a, from, to, pitch, size, px)
    local p = a.parent
    px = px or pitch
    local half, gap, head = size / 2, Arrows.GAP, Arrows.HEAD
    local fx, fy = from.col * px, from.row * pitch
    local tx, ty = to.col * px, to.row * pitch
    local hx, hy, rot
    if from.col == to.col then
        -- straight down (or up)
        local x = fx + half
        local down = to.row > from.row
        local y1 = down and (fy + size + gap) or (fy - gap)
        local y2 = down and (ty - gap - head / 2) or (ty + size + gap + head / 2)
        seg(a.segs[1], p, x, y1, x, y2)
        a.segs[2]:Hide()
        a.path = { { x, y1, x, y2 } }
        hx, hy, rot = x, down and (ty - gap - head / 2) or (ty + size + gap + head / 2), down and 0 or math.pi
    elseif from.row == to.row then
        local y = fy + half
        local right = to.col > from.col
        local x1 = right and (fx + size + gap) or (fx - gap)
        local x2 = right and (tx - gap - head / 2) or (tx + size + gap + head / 2)
        seg(a.segs[1], p, x1, y, x2, y)
        a.segs[2]:Hide()
        a.path = { { x1, y, x2, y } }
        hx, hy, rot = x2, y, right and math.pi / 2 or -math.pi / 2
    else
        -- bent: across on the source's row to the target's column, then down
        local y = fy + half
        local x = tx + half
        local right = to.col > from.col
        local x1 = right and (fx + size + gap) or (fx - gap)
        seg(a.segs[1], p, x1, y, x, y)
        local y2 = ty - gap - head / 2
        seg(a.segs[2], p, x, y, x, y2)
        a.path = { { x1, y, x, y }, { x, y, x, y2 } }
        hx, hy, rot = x, y2, 0
    end
    a.head:ClearAllPoints()
    a.head:SetPoint("CENTER", p, "TOPLEFT", hx, -hy)
    a.head:SetRotation(rot)
    a.head:Show()
    a.total = 0
    for i, s in ipairs(a.path) do
        halo(a.halo[i], p, s[1], s[2], s[3], s[4])
        a.total = a.total + math.abs(s[3] - s[1]) + math.abs(s[4] - s[2])
    end
    a.bloom:ClearAllPoints()
    a.bloom:SetPoint("CENTER", p, "TOPLEFT", hx, -hy)
    if a.glowC then Arrows.Glow(a, a.glowC) end
end

-- ---------------------------------------------------------------------
-- Glow and sparks on full arrows

local drivers = setmetatable({}, { __mode = "k" })

-- Position `d` px along the arrow. Values before the start or past the end
-- extrapolate along the first or last segment.
local function pointAt(a, d)
    local n = #a.path
    for i, s in ipairs(a.path) do
        local len = math.abs(s[3] - s[1]) + math.abs(s[4] - s[2])
        if d <= len or i == n then
            local k = d / math.max(len, 1)
            if i > 1 then k = math.max(k, 0) end
            if i < n then k = math.min(k, 1) end
            return s[1] + (s[3] - s[1]) * k, s[2] + (s[4] - s[2]) * k
        end
        d = d - len
    end
end

local function quiet(a)
    for _, t in ipairs(a.motes) do t:Hide() end
    a.bloom:Hide()
end

local function step(a, elapsed)
    a.clock = a.clock + elapsed
    local breathe = 0.19 + 0.07 * math.sin(a.clock * 2.4)
    for _, t in ipairs(a.halo) do t:SetAlpha(breathe) end
    if a.clock < 0 or not a.path then quiet(a) return end
    local t = a.clock % (Arrows.TRAVEL + Arrows.REST)
    -- From the tile's edge to the head's tip, the tail following.
    local from, to = -Arrows.GAP, a.total + Arrows.HEAD / 2
    local span = to - from + Arrows.TAIL[#Arrows.TAIL][1]
    -- Falls a little faster as it goes and lands on the head.
    local lead = from + (math.min(t / Arrows.TRAVEL, 1) ^ 1.6) * span
    local arrive = Arrows.TRAVEL * ((a.total - from) / span) ^ (1 / 1.6)
    local inK = math.min(t / 0.1, 1)
    for i, m in ipairs(a.motes) do
        local spec = Arrows.TAIL[i]
        local d = lead - spec[1]
        if t < Arrows.TRAVEL and d >= from and d <= to then
            local x, y = pointAt(a, d)
            m:ClearAllPoints()
            m:SetPoint("CENTER", a.parent, "TOPLEFT", x, -y)
            m:SetAlpha(spec[2] * inK)
            m:Show()
        else
            m:Hide()
        end
    end
    local since = t - arrive
    if since >= 0 and since < 0.5 then
        local k = 1 - since / 0.5
        a.bloom:SetAlpha(0.85 * k * k)
        a.bloom:Show()
    else
        a.bloom:Hide()
    end
end

local function tick(d, elapsed)
    -- Motion off: clear the sparks and stop. Toggling motion repaints, and
    -- the next Arrows.Glow restarts the driver.
    if not Motion.On() then
        for a in pairs(d.arrows) do quiet(a) end
        d:Hide()
        return
    end
    for a in pairs(d.arrows) do step(a, elapsed) end
end

local function driverFor(parent)
    local d = drivers[parent]
    if not d then
        d = CreateFrame("Frame", nil, parent)
        d.arrows = {}
        d:SetScript("OnUpdate", tick)
        d:Hide()
        drivers[parent] = d
    end
    return d
end

function Arrows.Driver(parent) return drivers[parent] end

-- c is the glow color, nil turns the glow off. fresh fires a spark right
-- away (a fill just landed); otherwise a newly lit arrow waits its row's turn.
function Arrows.Glow(a, c, fresh)
    local d = driverFor(a.parent)
    if not c then
        a.glowC = nil
        for _, t in ipairs(a.halo) do t:Hide() end
        quiet(a)
        d.arrows[a] = nil
        if not next(d.arrows) then d:Hide() end
        return
    end
    local was = a.glowC
    a.glowC = c
    for i, t in ipairs(a.halo) do
        t:SetVertexColor(c[1], c[2], c[3], 1)
        t:SetAlpha(0.22)
        t:SetShown(a.path ~= nil and a.path[i] ~= nil)
    end
    -- Lift the spark toward white so it reads as light.
    local r, g, b = c[1] + (1 - c[1]) * 0.5, c[2] + (1 - c[2]) * 0.5, c[3] + (1 - c[3]) * 0.5
    for _, m in ipairs(a.motes) do m:SetVertexColor(r, g, b, 1) end
    a.bloom:SetVertexColor(r, g, b, 1)
    if fresh then
        a.clock = 0
    elseif not was then
        a.clock = -((a.from and a.from.row or 0) * Arrows.STAGGER)
    end
    d.arrows[a] = true
    d:Show()
end

-- state: "off" (source not maxed), "lit" (maxed) or "staged" (maxed with
-- unapplied points). fresh: see Arrows.Glow.
function Arrows.Paint(a, state, fresh)
    local c = state == "lit" and Arrows.LIT or state == "staged" and Arrows.STAGED or Arrows.OFF
    for _, t in ipairs(a.segs) do t:SetVertexColor(c[1], c[2], c[3], 1) end
    a.head:SetVertexColor(c[1], c[2], c[3], 1)
    a.state = state
    Arrows.Glow(a, state ~= "off" and c or nil, fresh)
end

function Arrows.Hide(a)
    Arrows.Stop(a)
    Arrows.Glow(a, nil)
    for _, t in ipairs(a.segs) do t:Hide() end
    a.head:Hide()
end

local function colorOf(state)
    return state == "lit" and Arrows.LIT or state == "staged" and Arrows.STAGED or Arrows.OFF
end

-- Draw the light up to fraction p of the arrow, head included. Between
-- adjacent rows an arrow is mostly head, so the head blends in last.
local function drawLit(a, p, c)
    local total = Arrows.HEAD
    for _, s in ipairs(a.path or {}) do total = total + math.abs(s[3] - s[1]) + math.abs(s[4] - s[2]) end
    local left = total * p
    local into = left - (total - Arrows.HEAD)
    local k = math.max(0, math.min(into / Arrows.HEAD, 1))
    local o = Arrows.OFF
    a.head:SetVertexColor(o[1] + (c[1] - o[1]) * k, o[2] + (c[2] - o[2]) * k, o[3] + (c[3] - o[3]) * k, 1)
    for i, t in ipairs(a.lit) do
        local s = a.path and a.path[i]
        if s and left > 0.5 then
            local len = math.abs(s[3] - s[1]) + math.abs(s[4] - s[2])
            local k = len > 0 and math.min(left / len, 1) or 1
            seg(t, a.parent, s[1], s[2], s[1] + (s[3] - s[1]) * k, s[2] + (s[4] - s[2]) * k)
            t:SetVertexColor(c[1], c[2], c[3], 1)
            left = left - len
        else
            t:Hide()
        end
    end
end

-- Cancel a running fill or drain. The caller repaints the arrow.
function Arrows.Stop(a)
    if not a.running then return end
    local key = a.running
    a.running = nil
    Motion.Tween(key, 1, 1, 0)   -- from == to drops the tween
    for _, t in ipairs(a.lit) do t:Hide() end
end

-- Run light down to the head, then paint the new state, fire a spark and
-- call done (which wakes the unlocked talent).
function Arrows.Fill(a, state, done)
    Arrows.Stop(a)
    Arrows.Paint(a, "off")
    local c = colorOf(state)
    local key = {}
    a.running = key
    Motion.Tween(key, 0, 1, Arrows.RUN, function(p) drawLit(a, p, c) end, function()
        if a.running == key then a.running = nil end
        for _, t in ipairs(a.lit) do t:Hide() end
        Arrows.Paint(a, state, true)
        if done then done() end
    end)
end

-- Reverse of Fill, for Undo or a removed point.
function Arrows.Drain(a, from)
    Arrows.Stop(a)
    Arrows.Paint(a, "off")
    local c = colorOf(from or "staged")
    local key = {}
    a.running = key
    Motion.Tween(key, 1, 0, Arrows.RUN * 0.7, function(p) drawLit(a, p, c) end, function()
        if a.running == key then a.running = nil end
        for _, t in ipairs(a.lit) do t:Hide() end
    end)
end
