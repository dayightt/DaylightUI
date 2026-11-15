-- One frame per on-screen block, painted from its layout entry. A frame keeps its
-- block's key while on screen, and the lines inside keep theirs ("title",
-- "obj:2"...), so a repaint only touches what changed and an effect (a count bump,
-- a finished objective's sheen) only plays on its own line. Frames are pooled per
-- kind; a freed frame releases all its lines so it comes back clean for another key.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style
local Layout, Look = ns.Layout, ns.Look

local Rows = {}
ns.Rows = Rows

Rows.TICK = 10
Rows.CHEVRON = 12
Rows.ZONE_CHEVRON = 10
Rows.LIFT = 1          -- how far a hovered quest title moves toward white
Rows.GLOW = DUI.MEDIA .. "glow.png"
Rows.HI_PAD = 2        -- the hover wash past a quest's top and bottom (half the compact gap)
Rows.GLOW_SIZE = 30    -- glow behind a hovered icon
Rows.GLOW_ALPHA = 0.85
Rows.glowParent = nil  -- the tracker's holder, outside the list (which clips)
Rows.Effects = {}      -- filled in by the motion code; empty means nothing plays

local pools = {}

local function newBlock(kind, parent)
    local f = CreateFrame("Button", nil, parent)
    f.kind, f.lines, f.spare = kind, {}, {}
    f:SetSize(1, 1)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if kind == "header" then
        f.label = Style.Text(f, 12, nil, ns.MEDIA.font)
        f.count = Style.Text(f, 12, "RIGHT", ns.MEDIA.font)
        f.chevron = f:CreateTexture(nil, "ARTWORK")
        f.chevron:SetTexture(Look.CHEVRON)
        f.chevron:SetSize(Rows.CHEVRON, Rows.CHEVRON)
        f.rule = f:CreateTexture(nil, "ARTWORK")
        f.rule:SetTexture(Look.WHITE)
    elseif kind == "zone" then
        f.label = Style.Text(f, 10, nil, ns.MEDIA.font)
        f.count = Style.Text(f, 10, "RIGHT", ns.MEDIA.font)
        f.chevron = f:CreateTexture(nil, "ARTWORK")
        f.chevron:SetTexture(Look.CHEVRON)
        f.chevron:SetSize(Rows.ZONE_CHEVRON, Rows.ZONE_CHEVRON)
    else
        -- The shared list-row hover wash, as in the quest log, reaching half the
        -- gap above and below so the hovered quest reads as one block.
        local W = DUI.Win.Parts
        f.hi = f:CreateTexture(nil, "BACKGROUND")
        f.hi:SetTexture(W.WHITE)
        f.hi:SetVertexColor(W.HI[1], W.HI[2], W.HI[3], W.HI[4])
        f.hi:SetPoint("TOPLEFT", f, "TOPLEFT", 0, Rows.HI_PAD)
        f.hi:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, -Rows.HI_PAD)
        f.hi:Hide()
        for _, name in ipairs({ "ring", "ready", "failed" }) do
            local t = f:CreateTexture(nil, "ARTWORK")
            t:SetSize(Layout.ICON, Layout.ICON)
            t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -1)
            t:Hide()
            f[name] = t
        end
        f.ring:SetTexture(Look.ICONS.progress)
        f.ready:SetTexture(Look.ICONS.ready)
        f.failed:SetTexture(Look.ICONS.failed)
    end
    return f
end

function Rows.Get(kind, parent)
    local list = pools[kind]
    local f = list and table.remove(list)
    if f then f:SetParent(parent) else f = newBlock(kind, parent) end
    f.key, f.block, f.painted, f.state, f.lift, f.hovered = nil, nil, nil, nil, nil, nil
    -- A header's count may have been making room for the list's controls (Tracker.lua),
    -- so a reused one starts plain at full alpha.
    if f.countGoal ~= nil then
        f.countGoal = nil
        DUI.Motion.Tween(f.count, 1, 1, 0)
        f.count:SetAlpha(1)
    end
    f:SetAlpha(1)
    f:Show()
    return f
end

local function parts(l)
    if l.kind == "title" then return { l.label, l.tag, l.party, l.voice } end
    return { l.label, l.count, l.tick, l.bar }
end

local function putLine(f, l)
    for _, p in ipairs(parts(l)) do p:Hide() end
    if l.sheen then l.sheen:SetAlpha(0) end
    f.spare[l.kind] = f.spare[l.kind] or {}
    table.insert(f.spare[l.kind], l)
end

function Rows.Free(f)
    for key, l in pairs(f.lines) do
        f.lines[key] = nil
        putLine(f, l)
    end
    f:Hide()
    f:ClearAllPoints()
    if f.hi then DUI.Win.Parts.Light(f.hi, false, true) end
    f.key, f.block, f.painted, f.state = nil, nil, nil, nil
    pools[f.kind] = pools[f.kind] or {}
    table.insert(pools[f.kind], f)
end

local function newLine(f, kind)
    local l = { kind = kind }
    if kind == "bar" then
        l.bar = Style.Bar(f, nil, ns.MEDIA.bars.progress)
        l.bar:SetMinMaxValues(0, 100)
        l.bar:SetHeight(Layout.BAR_H)
    else
        l.label = Style.Text(f, 11, nil, ns.MEDIA.font)
        l.label:SetWordWrap(true)
        if kind == "title" then
            l.sheen = Rows.NewSheen(f)   -- gold when the quest becomes ready
            l.tag = Look.NewTag(f)
            Style.SetTextSlot(l.tag.text, ns.MEDIA.font)
            l.party = Look.NewParty(f)
            Style.SetTextSlot(l.party.count, ns.MEDIA.font)
            l.voice = ns.Voice.New(f)
        end
        if kind == "obj" then
            l.count = Style.Text(f, 11, "RIGHT", ns.MEDIA.font)
            l.tick = f:CreateTexture(nil, "ARTWORK")
            l.tick:SetTexture(Look.ICONS.tick)
            l.tick:SetDesaturated(true)
            l.tick:SetSize(Rows.TICK, Rows.TICK)
            l.sheen = Rows.NewSheen(f)
        end
    end
    return l
end

-- The line for key, and whether it's new to this frame.
local function takeLine(f, key, kind)
    local l = f.lines[key]
    if l then return l, false end
    local spare = f.spare[kind]
    l = spare and table.remove(spare) or newLine(f, kind)
    l.key, l.last, l.going = key, nil, nil
    for _, p in ipairs(parts(l)) do p:SetAlpha(1); p:Show() end
    f.lines[key] = l
    return l, true
end

local function dropLine(f, key, fx)
    local l = f.lines[key]
    f.lines[key] = nil
    if fx and Rows.Effects.LineOut then Rows.Effects.LineOut(f, l, putLine) else putLine(f, l) end
end

local function place(region, f, x, y, w)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
    if w then region:SetWidth(w) end
end

function Rows.TimerText(secs)
    return string.format(DUI.L["%s left"], DUI.FormatClock(math.max(0, secs or 0)))
end

-- l: the title line; room: the title's width. The tag sits right after the title
-- text (after its widest line if the title wraps).
local function paintTag(f, l, ln, look, room)
    local tag = l.tag
    if not Look.PaintTag(tag, look, ln.tag) then return end
    local sw = math.min(Look.Number(l.label:GetStringWidth()) or room, room)
    local lineTop = (look.s.title + Layout.LEADING - Look.TAG_H) / 2
    tag:ClearAllPoints()
    tag:SetPoint("TOPLEFT", f, "TOPLEFT", Layout.TITLE_X + sw + Look.TAG_GAP, -(ln.y + math.floor(lineTop + 0.5)))
end

-- Party mark at the right end of the title line, level with its first line.
local function paintParty(f, l, ln, look, animate)
    local lineTop = (look.s.title + Layout.LEADING - Look.TAG_H) / 2
    l.party:ClearAllPoints()
    l.party:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -(ln.y + math.floor(lineTop + 0.5)))
    Look.PaintParty(l.party, ln.party, animate)
end

-- Spoken's Play button at the right end of the title line, before the party mark
-- and level with its first line. Eases in and out like the mark.
local function paintVoice(f, l, ln, b, look, animate)
    local v = l.voice
    local on = ln.voice == true and b.quest ~= nil and ns.Voice.Bind(v, b.quest.id, b.quest.title)
    local was = v.on == true
    v.on = on or nil
    if on then
        v:ClearAllPoints()
        v:SetPoint("CENTER", f, "TOPRIGHT", -((ln.party and Layout.PARTY_W or 0) + Layout.VOICE_W / 2),
            -(ln.y + math.floor((look.s.title + Layout.LEADING) / 2 + 0.5)))
        v:Show()
        if was or not animate then v:SetAlpha(f.dim or 1)
        else DUI.Motion.Fade(v, 0, f.dim or 1, DUI.Motion.FAST) end
    elseif was and animate and v:IsShown() then
        DUI.Motion.Fade(v, v:GetAlpha(), 0, DUI.Motion.FAST)
        C_Timer.After(DUI.Motion.FAST, function() if not v.on then v:Hide() end end)
    else
        v:Hide()
    end
end

local function paintTimer(l, secs, look)
    l.label:SetText(Rows.TimerText(secs))
    l.label:SetTextColor(Look.Color(look, (secs or 0) < 60 and "timerUrgent" or "timer"))
end
Rows.PaintTimer = paintTimer      -- l: anything with a .label (the journal's page too)

function Rows.SetTimer(f, secs, look)
    local l = f.lines.timer
    if l then paintTimer(l, secs, look) end
end

-- Objective text color (objColors): plain = the tracker's colors, done = green
-- once done, count = red to green by progress (Tips.Progress).
function Rows.ObjColor(look, o)
    local mode = look.db and look.db.objColors
    if mode == "count" and (o.kind == "count" or o.kind == "bar" or o.done) then
        local c = o.done and DUI.Tips.GOOD or (o.kind == "bar" and DUI.Tips.Progress(o.pct, 100) or DUI.Tips.Progress(o.have, o.need))
        return c[1], c[2], c[3]
    end
    if (mode == "done" or mode == "count") and o.done then
        local c = Style.INK.GOOD
        return c[1], c[2], c[3]
    end
    return Look.Color(look, o.done and "done" or "objective")
end

-- Dims a block's text and icons (the hover dim). The frame's own alpha is left to
-- the list's motion.
function Rows.Dim(f, a)
    f.dim = a
    for _, l in pairs(f.lines) do
        for _, p in ipairs(parts(l)) do
            if p.SetAlpha then p:SetAlpha(a) end
        end
    end
    for _, name in ipairs({ "ring", "ready", "failed" }) do
        if f[name] then f[name]:SetAlpha(a) end
    end
end

local function paintLine(f, l, ln, b, look, fx)
    local W, s = look.width, look.s
    if ln.kind == "title" then
        Style.SetTextSize(l.label, s.title)
        l.label:SetText(ln.text)
        local room = Layout.TitleRoom(W, ln.tag, ln.party, ln.voice)
        place(l.label, f, Layout.TITLE_X, ln.y, room)
        paintTag(f, l, ln, look, room)
        paintParty(f, l, ln, look, fx and l.last ~= nil)
        paintVoice(f, l, ln, b, look, fx and l.last ~= nil)
        local r, g, bl
        if b.quest then r, g, bl = Look.TitleColor(look, b.quest) else r, g, bl = Look.Color(look, "header") end
        if fx and l.last and Rows.Effects.TitleColor then
            Rows.Effects.TitleColor(f, l, l.last, { r, g, bl })
        else
            l.label:SetTextColor(r, g, bl)
        end
        l.last = { r, g, bl }
    elseif ln.kind == "obj" then
        local o = ln.obj
        local counted = o.kind ~= "text"
        Style.SetTextSize(l.label, s.objective)
        l.label:SetText(o.text)
        place(l.label, f, Layout.OBJ_X, ln.y, W - Layout.OBJ_X - (counted and Layout.COUNT_W or 0))
        l.label:SetTextColor(Rows.ObjColor(look, o))
        Style.SetTextSize(l.count, s.objective)
        l.count:ClearAllPoints()
        l.count:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -ln.y)
        l.count:SetText(o.kind == "count" and (o.have .. "/" .. o.need) or (o.kind == "bar" and (o.pct .. "%")) or "")
        l.count:SetTextColor(Look.Color(look, "count"))
        l.count:SetShown(counted and not o.done)
        l.tick:ClearAllPoints()
        l.tick:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -(ln.y + 2))
        l.tick:SetVertexColor(Look.Color(look, "tick"))
        l.tick:SetShown(o.done)
        if fx and l.last and Rows.Effects.Objective then Rows.Effects.Objective(f, l, l.last, o, look) end
        l.last = { have = o.have, done = o.done, pct = o.pct }
    elseif ln.kind == "bar" then
        place(l.bar, f, Layout.OBJ_X, ln.y, W - Layout.OBJ_X)
        Look.PaintBar(l.bar, look)
        if fx and l.last and l.last.pct ~= ln.pct and Rows.Effects.Bar then
            Rows.Effects.Bar(f, l, l.last.pct, ln.pct)
        else
            l.bar:SetValue(ln.pct)
        end
        l.last = { pct = ln.pct }
    else
        Style.SetTextSize(l.label, s.objective)
        place(l.label, f, Layout.OBJ_X, ln.y, W - Layout.OBJ_X)
        if ln.kind == "timer" then
            paintTimer(l, b.quest and b.quest.timer, look)
        else
            l.label:SetText(ln.text)
            l.label:SetTextColor(Look.Color(look, ln.kind == "failed" and "failed" or "objective"))
        end
    end
end

local function turnChevron(f, b)
    if Rows.Effects.Chevron and f.painted then
        Rows.Effects.Chevron(f, b.folded)
    else
        f.chevronTurn = b.folded and math.pi / 2 or 0
        f.chevron:SetRotation(f.chevronTurn)
    end
end

local function paintHeader(f, b, look)
    local s = look.s
    Style.SetTextSize(f.label, s.header)
    Look.PaintText(f.label, look, "header", string.upper(b.label))
    f.label:ClearAllPoints()
    f.label:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    Style.SetTextSize(f.count, s.header)
    f.count:SetText(b.count)
    f.count:SetTextColor(Look.Color(look, "done"))
    f.count:ClearAllPoints()
    f.count:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(Rows.CHEVRON + 4), 0)
    f.chevron:ClearAllPoints()
    f.chevron:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -1)
    Rows.LightChevron(f, false, true)
    turnChevron(f, b)
    Look.PaintTexture(f.rule, look, "headerLine", 0.9)
    f.rule:ClearAllPoints()
    local y = b.textH + Layout.HEADER_PAD
    f.rule:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
    f.rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -y)
    f.rule:SetHeight(Layout.HEADER_LINE)
end

local function paintZone(f, b, look)
    Style.SetTextSize(f.label, look.s.zone)
    Look.PaintText(f.label, look, "zone", string.upper(b.label))
    place(f.label, f, Layout.TITLE_X, Layout.ZONE_TOP, look.width - Layout.TITLE_X - 30)
    -- A folded zone keeps its arrow and quest count; an open one only shows the arrow
    -- on hover. A row's first paint sets this instantly, so a new or reused row never
    -- fades out an arrow it shouldn't have.
    f.chevron:ClearAllPoints()
    f.chevron:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -Layout.ZONE_TOP)
    Rows.ShowChevron(f, b.folded or f.hovered == true, not f.painted)
    if not f.hovered then Rows.LightChevron(f, false, true) end
    turnChevron(f, b)
    Style.SetTextSize(f.count, look.s.zone)
    f.count:SetText(b.count)
    f.count:SetTextColor(Look.Color(look, "done"))
    f.count:ClearAllPoints()
    f.count:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(Rows.CHEVRON + 4), -Layout.ZONE_TOP)
    f.count:SetShown(b.folded == true)
end

local function paintBlock(f, b, look, opts, events)
    local q = b.quest
    local state = q and q.state or nil
    f.ring:SetShown(state == "active")
    f.ring:SetVertexColor(unpack(Look.RING))
    f.ready:SetShown(state == "ready")
    f.ready:SetVertexColor(Look.Color(look, "ready"))
    f.failed:SetShown(state == "failed")
    f.failed:SetVertexColor(Look.Color(look, "failed"))
    if q and q.focus and state ~= "failed" then Look.PaintFocus(state == "ready" and f.ready or f.ring, look) end
    if opts.fx and f.painted and q and f.state ~= "ready" and state == "ready" then
        events.ready = true
        if Rows.Effects.Ready then Rows.Effects.Ready(f, look) end
    end
    f.state = state
    local keep = {}
    for _, ln in ipairs(b.lines) do
        keep[ln.key] = true
        if not (opts.inPlace and not f.lines[ln.key]) then
            local l, fresh = takeLine(f, ln.key, ln.kind)
            paintLine(f, l, ln, b, look, opts.fx and f.painted and not fresh)
            if fresh and opts.fx and f.painted and Rows.Effects.LineIn then Rows.Effects.LineIn(f, l) end
        end
    end
    if not opts.inPlace then
        for key in pairs(f.lines) do
            if not keep[key] then dropLine(f, key, opts.fx) end
        end
    end
end

function Rows.Paint(f, b, look, opts)
    opts = opts or {}
    local events = {}
    f.key, f.block = b.key, b
    f:SetHeight(math.max(1, b.h))
    if b.kind == "header" then paintHeader(f, b, look)
    elseif b.kind == "zone" then paintZone(f, b, look)
    else paintBlock(f, b, look, opts, events) end
    f.painted = true
    Rows.look = look
    if f.lift then Rows.Lift(f, f.lift) end   -- currently hovered
    return events
end

-- Moves a quest title p of the way to its lifted color (0 = as painted).
function Rows.Lift(f, p)
    f.lift = p > 0 and p or nil
    for _, l in pairs(f.lines) do
        if l.kind == "title" and l.last then
            local c = l.last
            local k = Rows.LIFT * p
            l.label:SetTextColor(c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k)
        end
    end
end

-- Glow behind the hovered icon. One for the whole list, on its own frame above the
-- list's (the list clips and the icons sit on its left edge). Its strength lives in
-- its color: on this client a texture's alpha and its color's alpha are the same
-- value, so painting the color sets it too.
local glow, glowAlpha = nil, 0
function Rows.Glow()
    if not glow then
        local host = CreateFrame("Frame", nil, Rows.glowParent or UIParent)
        host:SetAllPoints()
        host:SetFrameLevel(host:GetFrameLevel() + 20)
        glow = host:CreateTexture(nil, "ARTWORK")
        glow:SetTexture(Rows.GLOW)
        glow:SetBlendMode("ADD")
        glow:SetSize(Rows.GLOW_SIZE, Rows.GLOW_SIZE)
        glow:Hide()
    end
    return glow
end

local function setGlow(a)
    glowAlpha = a
    local g = Rows.Glow()
    if a <= 0 then g:Hide(); return end
    Look.PaintFocus(g, Rows.look, a)
    g:Show()
end

local function iconOf(f)
    if f.ready:IsShown() then return f.ready end
    if f.failed:IsShown() then return f.failed end
    return f.ring
end

-- Hover. On a quest, on = "icon" lights its icon, any other true value lifts its
-- title, false does neither. On a header or zone name: its chevron.
function Rows.Hover(f, on)
    local Motion = DUI.Motion
    if f.ring then
        DUI.Win.Parts.Light(f.hi, on and true or false)
        local key = "quests:lift:" .. tostring(f)
        Motion.Tween(key, f.lift or 0, (on and on ~= "icon") and 1 or 0, Motion.FAST, function(p) Rows.Lift(f, p) end)
        local g = Rows.Glow()
        if on == "icon" then
            g.owner = f
            g:ClearAllPoints()
            g:SetPoint("CENTER", iconOf(f), "CENTER")
            Motion.Tween("quests:glow", glowAlpha, Rows.GLOW_ALPHA, Motion.FAST, setGlow)
        elseif g.owner == f then
            g.owner = nil
            Motion.Tween("quests:glow", glowAlpha, 0, Motion.FAST, setGlow)
        end
    elseif f.chevron then
        if f.kind == "zone" then
            f.hovered = on and true or nil
            Rows.ShowChevron(f, on or (f.block ~= nil and f.block.folded == true))
        end
        Rows.LightChevron(f, on)
    end
end

-- A zone's arrow eases in and out with the mouse (FAST). now: set instantly (a
-- row's first paint).
function Rows.ShowChevron(f, on, now)
    DUI.Motion.AlphaTo(f.chevron, on and 1 or 0, now and 0 or DUI.Motion.FAST, true)
end

-- A hovered arrow warms to the accent and cools back (FAST). now: instantly (a repaint).
function Rows.LightChevron(f, on, now)
    local r, g, b
    if on then r, g, b = Style.Accent() else r, g, b = unpack(Look.CHEVRON_COLOR) end
    local c = f.chevronColor
    if now or not c then
        if c then DUI.Motion.Tween(c, 0, 0, 0) else c = {}; f.chevronColor = c end
        c[1], c[2], c[3] = r, g, b
        f.chevron:SetVertexColor(r, g, b)
        return
    end
    local fr, fg, fb = c[1], c[2], c[3]
    DUI.Motion.Tween(c, 0, 1, DUI.Motion.FAST, function(k)
        c[1], c[2], c[3] = fr + (r - fr) * k, fg + (g - fg) * k, fb + (b - fb) * k
        f.chevron:SetVertexColor(c[1], c[2], c[3])
    end)
end

-- Effects: each plays only for the line or block whose own state changed.

local Motion = DUI.Motion
local E = Rows.Effects

-- A soft band of the accent (or a given color) that sweeps across a line as it fades.
function Rows.NewSheen(f)
    local s = CreateFrame("Frame", nil, f)
    s:SetSize(60, 14)
    s:SetAlpha(0)
    s.left = s:CreateTexture(nil, "OVERLAY")
    s.left:SetTexture(Look.WHITE)
    s.left:SetPoint("TOPLEFT"); s.left:SetPoint("BOTTOMLEFT"); s.left:SetWidth(30)
    s.right = s:CreateTexture(nil, "OVERLAY")
    s.right:SetTexture(Look.WHITE)
    s.right:SetPoint("TOPRIGHT"); s.right:SetPoint("BOTTOMRIGHT"); s.right:SetWidth(30)
    local g = s:CreateAnimationGroup()
    s.move = g:CreateAnimation("Translation")
    s.move:SetDuration(0.6)
    s.move:SetSmoothing("OUT")
    local fade = g:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(0.6)
    fade:SetSmoothing("IN")
    g:SetScript("OnFinished", function() s:SetAlpha(0) end)
    s.anim = g
    return s
end

function Rows.Sheen(l, f, r, g, b)
    if not Motion.On() or not l.sheen then return end
    local s = l.sheen
    if not r then r, g, b = Style.Accent() end
    if CreateColor then
        s.left:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 0.55))
        s.right:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.55), CreateColor(r, g, b, 0))
    end
    s:ClearAllPoints()
    s:SetPoint("TOPLEFT", l.label, "TOPLEFT", -4, 1)
    local w = f:GetWidth()
    s.move:SetOffset((type(w) == "number" and w or 200) * 0.6, 0)
    s:SetAlpha(1)
    s.anim:Stop()
    s.anim:Play()
end

local function lerpColor(fs, from, to, dur, key)
    Motion.Tween(key, 0, 1, dur, function(p)
        fs:SetTextColor(from[1] + (to[1] - from[1]) * p, from[2] + (to[2] - from[2]) * p, from[3] + (to[3] - from[3]) * p)
    end)
end

function E.Objective(f, l, last, o, look)
    if o.done and not last.done then
        Rows.Sheen(l, f)
        Motion.Pop(l.tick, 0.6, Motion.NORMAL)
        lerpColor(l.label, { Look.Color(look, "objective") }, { Rows.ObjColor(look, o) }, Motion.SLOW, "quests:obj:" .. tostring(f.key) .. l.key)
    elseif o.kind == "count" and type(last.have) == "number" and o.have > last.have then
        Motion.Bump(l.count, 1.15, Motion.FAST)
    end
end

function E.TitleColor(f, l, from, to)
    if from[1] == to[1] and from[2] == to[2] and from[3] == to[3] then
        l.label:SetTextColor(to[1], to[2], to[3])
        return
    end
    lerpColor(l.label, from, to, Motion.SLOW, "quests:title:" .. tostring(f.key))
end

function E.Ready(f, look)
    Motion.Pop(f.ready, 0.6, Motion.NORMAL)
    local title = f.lines.title
    if title and look then Rows.Sheen(title, f, Look.Color(look, "ready")) end
end

function E.Bar(f, l, from, to)
    Motion.Tween("quests:bar:" .. tostring(f.key) .. l.key, from or 0, to, Motion.SLOW, function(v) l.bar:SetValue(v) end)
end

function E.LineIn(f, l)
    for _, p in ipairs(parts(l)) do
        if p:IsShown() then Motion.Fade(p, 0, 1, Motion.NORMAL) end
    end
end

function E.LineOut(f, l, put)
    if not Motion.On() then put(f, l); return end
    l.going = (l.going or 0) + 1
    local token = l.going
    for _, p in ipairs(parts(l)) do
        if p:IsShown() then Motion.Fade(p, p:GetAlpha(), 0, Motion.NORMAL) end
    end
    C_Timer.After(Motion.NORMAL, function() if l.going == token then put(f, l) end end)
end

function E.Chevron(f, folded)
    local from = f.chevronTurn or 0
    local to = folded and math.pi / 2 or 0
    f.chevronTurn = to
    Motion.Tween("quests:chevron:" .. tostring(f.key), from, to, Motion.NORMAL, function(v) f.chevron:SetRotation(v) end)
end

-- What plugins get for a quest row (DaylightUI.API Paint, kind "questrow"): title,
-- objectives in order, bar and state icon. The item button is secure and not
-- included. Painted back on the list's next layout.
if DUI.APIReport then
    DUI.APIReport.Parts("questrow", function(f)
        local title = f.lines.title and f.lines.title.label
        local objectives, bar = {}, nil
        for _, ln in ipairs(f.block and f.block.lines or {}) do
            local l = f.lines[ln.key]
            if l and l.kind == "bar" then bar = bar or l.bar
            elseif l and l.kind ~= "title" and l.label then objectives[#objectives + 1] = l.label end
        end
        local icon = f.ring
        if f.ready and f.ready:IsShown() then icon = f.ready elseif f.failed and f.failed:IsShown() then icon = f.failed end
        return { title = title, objectives = objectives, bar = bar, icon = icon }
    end)
    DUI.APIReport.Repainter("questrow", function()
        if ns.Tracker and ns.Tracker.Queue then ns.Tracker.Queue(false) end
    end, true)
end
