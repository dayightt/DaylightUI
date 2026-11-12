-- Scrolling combat text drawing. A stage holds the three streams, each an
-- anchor frame. The live stage sits on screen; the options preview is a second
-- stage drawing the same lines.
--
-- Each line is a small frame moved by one shared OnUpdate (only while lines are
-- alive). It holds the text, the slanted tick, and on crits a glow and an
-- underline. Nothing is measured since the text may be secret: the pieces anchor
-- to the text and the client sizes them.

local _, DUI = ...
local CT = DUI.CombatText
local Motion, Style = DUI.Motion, DUI.Style

local GLOW = DUI.MEDIA .. "glow.png"
local WHITE = "Interface\\Buttons\\WHITE8x8"

CT.GAP = 4              -- px between lines
CT.RULE_ROOM = 10       -- extra room a crit's underline needs
CT.SHOVE_SPEED = 28     -- how fast a line eases out of the way of a new one
CT.TICK_LEAN = -0.35    -- radians, matches the UI's slant
CT.SLANT = 0.34         -- px sideways per px of rise, same slant
CT.CRIT_RISE = 0.3      -- crits travel less of the stream so they can be read
CT.FLARE_W, CT.FLARE_H = 5.5, 3   -- glow size in text heights

-- Position at p (0-1 of the line's life). Eased so it bursts out, then
-- drifts slowly while being read.
local function offset(motion, p, dist, dir)
    local e = 1 - (1 - p) ^ 3
    if motion == "rise" then return 0, dist * e end
    if motion == "fall" then return 0, -dist * e end
    if motion == "slant" then return dir * dist * CT.SLANT * e, dist * e end
    if motion == "arc" then return dir * dist * 0.7 * p * p, dist * e end
    if motion == "fountain" then return dir * dist * 0.55 * p, dist * math.sin(p * math.pi / 2) end
    return 0, 0   -- stack mode only moves when newer lines arrive below
end

local Stage = {}
Stage.__index = Stage

local function setFace(line, size, outline)
    local face = DUI.GameFonts.CombatTextWanted() or Style.FONT
    if line.face ~= face or line.size ~= size or line.outline ~= outline then
        line.fs:SetFont(face, size, outline)
        line.face, line.size, line.outline = face, size, outline
    end
end

local function newLine(stage)
    local line = {}
    local f = CreateFrame("Frame", nil, stage.root)
    f:SetSize(1, 1)
    line.frame = f

    line.flare = f:CreateTexture(nil, "BACKGROUND")
    line.flare:SetTexture(GLOW)
    line.flare:SetBlendMode("ADD")

    line.fs = f:CreateFontString(nil, "OVERLAY")
    line.fs:SetWordWrap(false)

    line.tick = f:CreateTexture(nil, "ARTWORK")
    line.tick:SetTexture(WHITE)
    line.tick:SetRotation(CT.TICK_LEAN)

    line.rule = f:CreateTexture(nil, "ARTWORK")
    line.rule:SetTexture(WHITE)
    return line
end

-- Which side the text grows from. Same for every line in a stream.
local function dress(line, s, r, g, b, crit)
    local fs, tick, rule, flare = line.fs, line.tick, line.rule, line.flare
    local align = s.align
    fs:ClearAllPoints()
    fs:SetPoint(align, line.frame, align, 0, 0)
    fs:SetJustifyH(align)
    fs:SetTextColor(r, g, b)
    if CT.Get("shadow") ~= false then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 0.75)
    else
        fs:SetShadowOffset(0, 0)
    end

    tick:ClearAllPoints()
    if align == "RIGHT" then tick:SetPoint("LEFT", fs, "RIGHT", 7, 0)
    elseif align == "LEFT" then tick:SetPoint("RIGHT", fs, "LEFT", -7, 0)
    else tick:SetPoint("RIGHT", fs, "LEFT", -6, 0) end
    tick:SetSize(2, math.floor(line.size * 0.72))
    tick:SetVertexColor(r, g, b, 0.85)
    tick:SetShown(CT.Get("tick") == true)

    local look = crit and CT.Get("crit") or "plain"
    line.pop = crit and CT.CRIT_POP[look] or nil
    local light = look == "plain" and 0 or CT.Get("glow")
    line.light = crit and type(light) == "number" and light or 0
    flare:ClearAllPoints()
    flare:SetPoint("CENTER", fs, "CENTER", 0, 0)
    flare:SetSize(line.size * CT.FLARE_W, line.size * CT.FLARE_H)
    flare:SetVertexColor(r, g, b)
    flare:SetAlpha(0)
    flare:SetShown(line.light > 0)

    rule:ClearAllPoints()
    rule:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -1)
    rule:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT", 0, -1)
    rule:SetHeight(2)
    if rule.SetGradient and CreateColor then
        local near, far = CreateColor(r, g, b, 0.9), CreateColor(r, g, b, 0)
        if align == "RIGHT" then rule:SetGradient("HORIZONTAL", far, near) else rule:SetGradient("HORIZONTAL", near, far) end
    end
    line.ruled = crit and look ~= "plain" and CT.Get("underline") == true
    rule:SetShown(line.ruled == true)
end

-- Distance along the stream, including how far newer lines pushed it.
local function way(line)
    local x, y = offset(line.motion, math.min(line.t / line.life, 1), line.dist, line.dir)
    return x, y + line.nudge * line.push
end

-- Each frame, newest first, push each older line just clear of the next one
-- (a new arrival, or a fast line catching a slow crit). Only the target moves
-- and the line eases toward it, so nothing jumps.
local function makeRoom(live)
    local reach, size
    for i = #live, 1, -1 do
        local l = live[i]
        local _, y = offset(l.motion, math.min(l.t / l.life, 1), l.dist, l.dir)
        local at = y * l.nudge + l.shove
        if reach then
            local want = reach + (size + l.room) / 2 + CT.GAP
            if at < want then
                l.shove = l.shove + want - at
                at = want
            end
        end
        reach, size = at, l.room
    end
end

local function step(stage, dt)
    local any = false
    local on = Motion.On()
    for _, stream in pairs(stage.streams) do
        local live = stream.live
        makeRoom(live)
        for i = #live, 1, -1 do
            local l = live[i]
            l.t = l.t + dt
            if l.t >= l.life then
                l.frame:Hide()
                table.remove(live, i)
                stage.spare[#stage.spare + 1] = l
            else
                any = true
                local t = l.t
                if on then
                    l.push = l.push + (l.shove - l.push) * math.min(1, dt * CT.SHOVE_SPEED)
                else
                    l.push = l.shove
                end
                local x, y = way(l)
                l.frame:SetPoint("CENTER", stream.anchor, "CENTER", x * stage.scale, y * stage.scale)
                local left = l.life - t
                local fade = 1
                if on then
                    fade = math.min(t / Motion.FAST, 1)
                    if left < Motion.SLOW then fade = left / Motion.SLOW end
                end
                l.frame:SetAlpha(fade)
                if l.pop and on then
                    if t < Motion.NORMAL then
                        local p = 1 - t / Motion.NORMAL
                        l.fs:SetTextScale(1 + (l.pop - 1) * p * p)
                    else
                        l.fs:SetTextScale(1)
                        l.pop = nil
                    end
                end
                if l.light > 0 then
                    local p = t / Motion.SLOW
                    l.flare:SetAlpha(p < 1 and l.light * (1 - p * p) or 0)
                end
                if l.ruled then l.rule:SetAlpha(math.min(t / Motion.NORMAL, 1)) end
            end
        end
    end
    if not any then stage.root:SetScript("OnUpdate", nil) end
end

-- Adds a line. fmt and its values go straight to SetFormattedText, they may be secret.
function Stage:Add(id, r, g, b, crit, fmt, a, b2, c, d)
    local stream, s = self.streams[id], CT.Get("streams." .. id)
    if not stream or type(s) ~= "table" or s.on == false then return end
    local live = stream.live
    local line = table.remove(self.spare) or newLine(self)

    -- Over the limit: the oldest line leaves right away.
    local most = s.lines or 8
    if #live >= most then
        local oldest = live[1]
        oldest.life = math.min(oldest.life, oldest.t + Motion.FAST)
        if #live >= most * 2 then
            oldest.frame:Hide()
            table.remove(live, 1)
            self.spare[#self.spare + 1] = oldest
        end
    end

    local size = crit and s.critSize or s.size
    setFace(line, size * (self.fontScale or 1), CT.Get("outline") or "")
    dress(line, s, r, g, b, crit)
    line.fs:SetTextScale(line.pop and Motion.On() and line.pop or 1)
    if fmt then line.fs:SetFormattedText(fmt, a, b2, c, d) else line.fs:SetText(a) end

    line.t, line.push, line.shove = 0, 0, 0
    line.size, line.crit = size, crit
    line.room = size + (line.ruled and CT.RULE_ROOM or 0)
    line.life = (s.life or 1.5) * (crit and 1.15 or 1)
    line.motion = s.motion
    line.nudge = s.motion == "fall" and -1 or 1
    line.dist = (s.dist or 0) * (crit and CT.CRIT_RISE or 1)
    if not Motion.On() then line.motion = "stack" end
    local side = CT.STREAMS[id].side
    if s.motion == "fountain" or side == 0 then
        stream.flip = -(stream.flip or 1)
        line.dir = stream.flip
    else
        line.dir = side
    end
    line.frame:SetAlpha(Motion.On() and 0 or 1)
    line.frame:SetPoint("CENTER", stream.anchor, "CENTER", 0, 0)
    line.frame:Show()
    live[#live + 1] = line

    local stage = self
    stage.root:SetScript("OnUpdate", function(_, dt) step(stage, dt) end)
    return line
end

-- Applies the stream's current size to lines already showing (preview, slider drag).
function Stage:Restyle()
    for id, stream in pairs(self.streams) do
        local s = CT.Get("streams." .. id)
        if type(s) == "table" then
            for _, l in ipairs(stream.live) do
                local size = l.crit and s.critSize or s.size
                setFace(l, size * (self.fontScale or 1), CT.Get("outline") or "")
                l.size = size
                l.room = size + (l.ruled and CT.RULE_ROOM or 0)
            end
        end
    end
end

-- Clears the stage immediately (page closed, text switched off).
function Stage:Clear()
    self.root:SetScript("OnUpdate", nil)
    for _, stream in pairs(self.streams) do
        for i = #stream.live, 1, -1 do
            local l = table.remove(stream.live, i)
            l.frame:Hide()
            self.spare[#self.spare + 1] = l
        end
    end
end

-- opts.scale = fraction of the stream's travel distance; opts.fontScale.
function CT.NewStage(root, opts)
    opts = opts or {}
    local stage = setmetatable({ root = root, spare = {}, streams = {},
        scale = opts.scale or 1, fontScale = opts.fontScale }, Stage)
    for _, id in ipairs(CT.STREAM_ORDER) do
        local anchor = CreateFrame("Frame", nil, root)
        anchor:SetSize(1, 1)
        stage.streams[id] = { anchor = anchor, live = {} }
    end
    return stage
end
