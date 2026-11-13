-- The XP bar across the top of the panel, with banked quest XP and rested XP
-- shown ahead of the fill. At the level cap it shows the watched reputation.
-- Below the cap, a reputation gain briefly switches the bar to that faction
-- (XP.REP_HOLD), unless the separate reputation bar is on. The game's own
-- tracking bars are hidden. The separate reputation bar is at the bottom.

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel

local XP = {}
ns.XP = XP

XP.COLOR = { 0.26, 0.45, 0.95 }
XP.RESTED = { 0.58, 0.32, 0.88, 1 }     -- rested: purple, seen at a glance
XP.BANKED = Style.INK.GOOD              -- finished quests' XP: green, done and waiting
XP.GAIN = Style.INK.MONEY               -- the text counting up to a gain wears this
XP.SHIMMER = { dur = 1.0, alpha = 0.6 }  -- the light along the rested part as you start resting
XP.REP_HOLD = 4                         -- seconds the reputation shows after a gain
XP.REP_SWEEP = { dur = 0.6, alpha = 0.45 }
XP.SEGMENTS = 20                        -- the classic bar's blocks: each 5% of a level
XP.TICK_ALPHA = 0.7                     -- the lines between them, in the panel's dark
XP.TIP_GAP = 4                          -- between the bar and its hover details
-- The game's own bars. They're Edit Mode frames whose updates call into
-- their parent, so they stay where the game put them and are kept hidden
-- instead of being moved under a hidden frame of ours.
XP.GAME_BARS = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

local function atCap()
    local capped = call(IsPlayerAtEffectiveMaxLevel)
    if capped ~= nil then return capped end
    local max = call(GetMaxPlayerLevel)
    return max ~= nil and UnitLevel("player") >= max
end

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- A separate bar can stand upright (xp.orientation, rep.orientation): it then
-- fills bottom to top, its text turns to read along it, and its gradient runs
-- the same way, dark at the bottom and light at the full end.
XP.TURN = math.pi / 2
function XP.TurnBar(bar, vertical)
    bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
    bar:SetRotatesTexture(vertical == true)
end

local function upright(bar, lo, hi)
    local tex = bar:GetStatusBarTexture()
    if type(tex) == "table" and tex.SetGradient and lo and hi then tex:SetGradient("VERTICAL", lo, hi) end
end
local function uprightRaw(bar, lo, hi)
    local a, b = DUI.Gradients.PaintRGBOf(lo, hi)
    upright(bar, CreateColor(a[1], a[2], a[3], 1), CreateColor(b[1], b[2], b[3], 1))
end

-- The gradient painters, turned upright for a vertical bar.
function XP.PaintKey(bar, key, vertical)
    local G = DUI.Gradients
    G.Paint(bar, key)
    if vertical then upright(bar, G.Colors(key)) end
end
function XP.PaintFrom(bar, rgb, vertical)
    local G = DUI.Gradients
    G.PaintFrom(bar, rgb)
    if vertical then uprightRaw(bar, G.PairFrom(rgb)) end
end
function XP.PaintPair(bar, lo, hi, vertical)
    DUI.Gradients.PaintPair(bar:GetStatusBarTexture(), lo, hi)
    if vertical then uprightRaw(bar, lo, hi) end
end

-- A light along a bar (Motion.Sweep's), bottom to top on an upright one.
function XP.Sweep(tex, over, opts, vertical)
    local M = DUI.Motion
    if not vertical then
        tex:SetHeight(over:GetHeight() or 1)
        return M.Sweep(tex, over, opts)
    end
    if not M.On() then return end
    tex:ClearAllPoints()
    tex:SetSize(over:GetWidth() or 1, opts.width or 40)
    tex:SetAlpha(0)
    tex:Show()
    M.Tween(tex, 0, 1, opts.dur or 0.5, function(p)
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", over, "BOTTOM", 0, p * (over:GetHeight() or 0))
        local a = p < 0.15 and p / 0.15 or (p > 0.75 and (1 - p) / 0.25 or 1)
        tex:SetAlpha((opts.alpha or 1) * a)
    end, function() tex:Hide() end)
end

-- Banked XP: the summed reward XP of quests ready to turn in. Recounted on
-- quest log events, including entries under collapsed headers.
function XP.Banked()
    local QL = C_QuestLog
    if type(QL) ~= "table" or type(QL.GetInfo) ~= "function" or type(GetQuestLogRewardXP) ~= "function" then
        return 0, 0
    end
    local shown, quests = call(QL.GetNumQuestLogEntries)
    local n = (type(shown) == "number" and shown or 0) + (type(quests) == "number" and quests or 0)
    local xp, count = 0, 0
    for i = 1, n do
        local info = call(QL.GetInfo, i)
        local id = type(info) == "table" and not info.isHeader and info.questID
        if type(id) == "number" and not call(QL.IsFailed, id)
                and (call(QL.IsComplete, id) or call(QL.ReadyForTurnIn, id)) then
            local r = call(GetQuestLogRewardXP, id)
            if type(r) == "number" and not secret(r) and r > 0 then xp, count = xp + r, count + 1 end
        end
    end
    return xp, count
end

function XP.CountBanked()
    local xp, count = 0, 0
    if XP.showBanked then xp, count = XP.Banked() end
    if xp == XP.bankedXP and count == XP.bankedQuests then return end
    XP.bankedXP, XP.bankedQuests = xp, count
    XP.Update()
end

-- What the bar shows now: { value, max, rested, banked, color, label } or nil.
function XP.Read()
    if not atCap() then
        local cur, max = UnitXP("player"), UnitXPMax("player")
        if not max or max <= 0 then return nil end
        return { value = cur, max = max, rested = call(GetXPExhaustion) or 0, banked = XP.bankedXP or 0,
                 color = XP.COLOR, label = DUI.L["Experience"] }
    end
    return XP.ReadRep()
end

-- The watched reputation: { value, max, rested = 0, color, label, rep } or nil.
function XP.ReadRep()
    local rep = C_Reputation and call(C_Reputation.GetWatchedFactionData)
    if type(rep) ~= "table" or not rep.name then return nil end
    local lo, hi = rep.currentReactionThreshold or 0, rep.nextReactionThreshold or 1
    local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[rep.reaction]
    return { value = (rep.currentStanding or lo) - lo, max = math.max(1, hi - lo), rested = 0,
             color = c and { c.r, c.g, c.b } or XP.COLOR, label = rep.name, rep = rep.reaction or 0 }
end

function XP.Build(frame)
    XP.frame = frame
    -- Bottom to top: the bar's dark background and the rested part (on the
    -- rested bar), the finished quests' XP, then the experience itself. The
    -- background lives on the bottom bar so it's under the rest, not over it.
    XP.rested = Style.Bar(frame, nil, ns.MEDIA.bars.xp)
    Style.BarBack(XP.rested):SetAlpha(0.6)
    XP.banked = Style.Bar(frame, nil, ns.MEDIA.bars.xp)
    XP.banked:SetFrameLevel(XP.rested:GetFrameLevel() + 1)
    Style.BarBack(XP.banked):Hide()
    XP.banked:SetValue(0)
    XP.bar = Style.Bar(frame, nil, ns.MEDIA.bars.xp)
    XP.bar:SetFrameLevel(XP.banked:GetFrameLevel() + 1)
    Style.BarBack(XP.bar):Hide()
    XP.text = Style.Text(XP.bar, 9, "CENTER", ns.MEDIA.fonts.xp)
    XP.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    XP.text:Hide()
    -- The rested shimmer: a soft light that runs over a frame of ours laid
    -- across the rested part (XP.restedSpan), above both bars.
    XP.restedSpan = CreateFrame("Frame", nil, frame)
    XP.restedSpan:SetFrameLevel(XP.bar:GetFrameLevel() + 1)
    XP.shimmer = XP.restedSpan:CreateTexture(nil, "OVERLAY")
    XP.shimmer:SetTexture(DUI.MEDIA .. "glow.png")
    XP.shimmer:SetBlendMode("ADD")
    XP.shimmer:Hide()
    -- The segment lines (xp.ticks): over the fill, under the rested light.
    XP.tickFrame = CreateFrame("Frame", nil, frame)
    XP.tickFrame:SetAllPoints(XP.bar)
    XP.tickFrame:SetFrameLevel(XP.bar:GetFrameLevel() + 1)
    XP.tickList = {}
    for i = 1, XP.SEGMENTS - 1 do
        local t = XP.tickFrame:CreateTexture(nil, "OVERLAY")
        Style.Follow(t, Style.BACKGROUND, XP.TICK_ALPHA, true)
        XP.tickList[i] = t
    end
    XP.tickFrame:SetScript("OnSizeChanged", function() XP.LayoutTicks() end)
    XP.tickFrame:Hide()
    -- The reputation layer: its own bar (with its dark background, so it
    -- covers the experience) over everything, at alpha 0 until a gain.
    XP.repBar = Style.Bar(frame, nil, ns.MEDIA.bars.xp)
    XP.repBar:SetFrameLevel(XP.restedSpan:GetFrameLevel() + 1)
    XP.repBar:SetAlpha(0)
    XP.repShine = XP.repBar:CreateTexture(nil, "OVERLAY")
    XP.repShine:SetTexture(DUI.MEDIA .. "glow.png")
    XP.repShine:SetBlendMode("ADD")
    XP.repShine:Hide()
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        local d = XP.Read()
        if not d then return end
        XP.hover = true
        local rep = not d.rep and not ns.RepBar.on and XP.ReadRep() or nil
        if rep then XP.ShowRep(false) end
        XP.PlaceTip(self)
        local Tips = DUI.Tips
        Tips.Clear()
        Tips.Title(d.label)
        Tips.Line(DUI.L["This level"], string.format("%s / %s  (%d%%)", BreakUpLargeNumbers(d.value),
            BreakUpLargeNumbers(d.max), math.floor(d.value / d.max * 100)))
        if d.banked and d.banked > 0 then
            Tips.Line(string.format(DUI.L["%d quests to turn in"], XP.bankedQuests or 0),
                BreakUpLargeNumbers(d.banked), XP.BANKED)
        end
        if d.rested > 0 then Tips.Line(DUI.L["Rested"], BreakUpLargeNumbers(d.rested), XP.RESTED) end
        if rep then
            Tips.Gap()
            Tips.Title(rep.label, rep.color[1], rep.color[2], rep.color[3])
            Tips.Line(DUI.L["Standing"], string.format("%s / %s  (%d%%)", BreakUpLargeNumbers(rep.value),
                BreakUpLargeNumbers(rep.max), math.floor(rep.value / rep.max * 100)))
        end
        Tips.Flush(GameTooltip)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
        XP.hover = false
        XP.HideRep()
    end)
    pcall(DUI.RegisterEvent, "PLAYER_UPDATE_RESTING", function() XP.Rest() end)
    for _, e in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "UPDATE_FACTION",
                         "PLAYER_ENTERING_WORLD" }) do
        pcall(DUI.RegisterEvent, e, function()
            if e == "PLAYER_LEVEL_UP" and ns.XPGain then ns.XPGain.levelSeen = true end
            XP.Update()
            if e == "UPDATE_FACTION" or e == "PLAYER_ENTERING_WORLD" then XP.RepGain(e == "UPDATE_FACTION") end
        end)
    end
    for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "PLAYER_ENTERING_WORLD" }) do
        pcall(DUI.RegisterEvent, e, XP.CountBanked)
    end
end

-- The segment lines, evenly across the bar, each a pixel wide.
function XP.LayoutTicks()
    local bar, vertical = XP.bar, XP.vertical
    local w = bar and (vertical and bar:GetHeight() or bar:GetWidth()) or 0
    if not XP.tickList or w <= 0 then return end
    for i, t in ipairs(XP.tickList) do
        local x = Pixel.Snap(bar, w * i / XP.SEGMENTS)
        t:ClearAllPoints()
        if vertical then
            t:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, x)
            t:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, x)
            t:SetHeight(Pixel.Px(bar, 1))
        else
            t:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
            t:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
            t:SetWidth(Pixel.Px(bar, 1))
        end
    end
end

-- Where the hover tooltip opens. "auto" faces the screen's middle: above or
-- below for a wide detached bar, otherwise left or right.
function XP.TipSide(frame, side)
    side = side or XP.tipSide or "auto"
    if side ~= "auto" then return side end
    local cx, cy = frame:GetCenter()
    local w = frame:GetWidth()
    if type(cx) ~= "number" or type(cy) ~= "number" or type(w) ~= "number" then return "left" end
    local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    if w * s > sw / 3 then return cy * s > sh / 2 and "below" or "above" end
    return cx * s > sw / 2 and "left" or "right"
end

XP.TIP_POINTS = {
    left = { "TOPRIGHT", "TOPLEFT", -1, 0 },
    right = { "TOPLEFT", "TOPRIGHT", 1, 0 },
    above = { "BOTTOM", "TOP", 0, 1 },
    below = { "TOP", "BOTTOM", 0, -1 },
}

function XP.PlaceTip(frame, side)
    local p = XP.TIP_POINTS[XP.TipSide(frame, side)] or XP.TIP_POINTS.left
    GameTooltip:SetOwner(frame, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint(p[1], frame, p[2], p[3] * XP.TIP_GAP, p[4] * XP.TIP_GAP)
end

-- ---------------------------------------------------------------------
-- The reputation turn (below the level cap)
-- ---------------------------------------------------------------------

local function secretRep(d) return issecretvalue ~= nil and (issecretvalue(d.value) or issecretvalue(d.max)) end

-- A gain with the watched faction (same faction, more than last seen; the
-- first read after login only remembers): the bar turns to it.
function XP.RepGain(heard)
    local d = XP.ReadRep()
    local was = XP.lastRep
    if not d or secretRep(d) then XP.lastRep = nil return end
    XP.lastRep = { label = d.label, value = d.value, rep = d.rep }
    if not heard or not was then return end
    local up = was.label == d.label and (d.rep > was.rep or (d.rep == was.rep and d.value > was.value))
    if up and ns.RepBar.on then
        ns.RepBar.Gain()
        DUI.Fade.Wake("InfoPanel.panel")
    elseif up and not atCap() then
        XP.ShowRep(true)
        DUI.Fade.Wake("InfoPanel.panel")   -- Float: the gain brings the panel back
        DUI.Fade.Wake("InfoPanel.xp")
    end
end

local function fadeRep(to, dur)
    local bar = XP.repBar
    if DUI.Motion.On() then
        DUI.Motion.Tween("xpRep", bar:GetAlpha() or 0, to, dur, function(a) bar:SetAlpha(a) end)
    else
        DUI.Motion.Tween("xpRep", 0, 0)
        bar:SetAlpha(to)
    end
end

-- Fills the reputation layer and fades it in; sweep = a light across it
-- (a gain). It fades back after XP.REP_HOLD, or once the mouse leaves.
function XP.ShowRep(sweep)
    if not (XP.repBar and XP.frame and XP.frame:IsShown()) then return end
    local d = XP.ReadRep()
    if not d or atCap() then return end
    local bar = XP.repBar
    bar:SetMinMaxValues(0, d.max)
    bar:SetValue(d.value)
    local G = DUI.Gradients
    local key = "REP_" .. d.rep
    if XP.gradient and G and G.Has(key) then XP.PaintKey(bar, key, XP.vertical)
    elseif XP.gradient and G then XP.PaintFrom(bar, d.color, XP.vertical)
    else Style.SetBarColor(bar, d.color[1], d.color[2], d.color[3]) end
    fadeRep(1, DUI.Motion.NORMAL)
    if sweep and DUI.Motion.On() then
        XP.Sweep(XP.repShine, bar, { width = 40, dur = XP.REP_SWEEP.dur, alpha = XP.REP_SWEEP.alpha }, XP.vertical)
    end
    XP.repUntil = GetTime() + (sweep and XP.REP_HOLD or 0)
    if sweep then C_Timer.After(XP.REP_HOLD, XP.HideRep) end
end

function XP.HideRep()
    if not XP.repBar or XP.hover then return end
    if XP.repUntil and GetTime() < XP.repUntil - 0.05 then return end
    fadeRep(0, DUI.Motion.SLOW)
end

-- Fill color. Reputation uses its standing's gradient; XP follows xp.color
-- (accent, class, blue or custom). The rested background uses the fill's middle.
local function accentPair()
    local lo, hi = Style.AccentPair()
    if not lo then lo, hi = DUI.Gradients.PairFrom({ Style.Accent() }) end
    return { lo = lo, hi = hi }
end

function XP.Paint(d)
    local G = DUI.Gradients
    local r, g, b = d.color[1], d.color[2], d.color[3]
    local accent = not d.rep and XP.colorMode == "accent"
    local custom = not d.rep and XP.colorMode == "custom" and XP.custom
    if accent and XP.gradient and G then custom = accentPair()
    elseif accent then r, g, b = Style.Accent() end
    if custom and not XP.gradient then r, g, b = custom.hi[1], custom.hi[2], custom.hi[3] end
    if custom and XP.gradient and G then
        Style.SetBarColor(XP.bar, G.MidOf(custom.lo, custom.hi))
        XP.bar:SetStatusBarColor(1, 1, 1, 1)
        XP.PaintPair(XP.bar, custom.lo, custom.hi, XP.vertical)
        r, g, b = G.MidOf(custom.lo, custom.hi)
    elseif XP.gradient and G then
        local key = d.rep and "REP_" .. d.rep or (XP.colorMode == "class" and G.KeyFor("player"))
        if key and G.Has(key) then
            XP.PaintKey(XP.bar, key, XP.vertical)
            r, g, b = G.Mid(key)
        else
            XP.PaintFrom(XP.bar, d.color, XP.vertical)
            r, g, b = G.MidOf(G.PairFrom(d.color))
        end
    else
        Style.SetBarColor(XP.bar, r, g, b)    -- a plain color also clears a gradient
    end
    Style.SetBarColor(XP.rested, r, g, b)
end

-- The text: the numbers, the percent, or both, then the rested part (nil:
-- nothing to show). value is the one on screen while it counts.
function XP.Format(d, value)
    local parts = {}
    if XP.showText then
        parts[#parts + 1] = string.format("%s / %s", BreakUpLargeNumbers(value), BreakUpLargeNumbers(d.max))
    end
    if XP.showPercent then parts[#parts + 1] = string.format("%d%%", math.floor(value / d.max * 100)) end
    if XP.showText and d.rested > 0 then
        parts[#parts + 1] = string.format("(+%s)", BreakUpLargeNumbers(d.rested))
    end
    if #parts > 0 then return table.concat(parts, "   ") end
end

local function untint()
    if XP.tint then XP.text:SetTextColor(unpack(XP.tint)); XP.tint = nil end
end

-- Writes the text. A plain gain on the same bar and level counts up in gold;
-- anything else (loss, level up, reputation, secret, motion off) is set at once.
function XP.Count(d, str)
    local was, v = XP.shown, d.value
    local level = UnitLevel and UnitLevel("player")
    XP.counting = d   -- a count under way reads the newest rest
    local plain = not (secret(v) or secret(d.max))   -- a secret is never compared
    local same = plain and was and was.label == d.label and was.max == d.max and was.level == level
    if same and XP.tint and v == was.to then return end   -- the same goal again: the count goes on
    if str and same and v > was.value and DUI.Motion.On() then
        XP.shown = { label = d.label, max = d.max, level = level, value = was.value, to = v }
        if not XP.tint then
            XP.tint = { XP.text:GetTextColor() }
            XP.text:SetTextColor(XP.GAIN[1], XP.GAIN[2], XP.GAIN[3])
        end
        DUI.Motion.Tween("xpCount", was.value, v, DUI.Motion.SLOW, function(x)
            x = math.floor(x + 0.5)
            XP.shown.value = x
            local s = XP.Format(XP.counting, x)
            if s then XP.text:SetText(s) end
        end, untint)
        return
    end
    DUI.Motion.Tween("xpCount", 0, 0)   -- ends a count under way
    untint()
    XP.shown = plain and { label = d.label, max = d.max, level = level, value = v, to = v } or nil
    if str then XP.text:SetText(str) end
end

-- Starting to rest (never the first read) with rested XP on the XP bar:
-- one slow light along the rested part, the fill's end to the rest's.
function XP.Rest()
    local now = call(IsResting) == true
    local was = XP.resting
    XP.resting = now
    if was ~= false or not now or not (XP.frame and XP.frame:IsShown() and XP.bar:IsShown()) then return end
    local d = XP.Read()
    if not d or d.rep or d.rested <= 0 or secret(d.value) or secret(d.rested) then return end
    local vertical = XP.vertical
    local w = (vertical and XP.bar:GetHeight() or XP.bar:GetWidth()) or 0
    if w <= 0 then return end
    local start = math.min(d.max, d.value + (d.banked or 0))   -- rest runs on past the quests' XP
    if start >= d.max then return end
    local from, to = w * start / d.max, w * math.min(d.max, start + d.rested) / d.max
    local span = XP.restedSpan
    span:ClearAllPoints()
    if vertical then
        span:SetPoint("BOTTOMLEFT", XP.bar, "BOTTOMLEFT", 0, from)
        span:SetPoint("BOTTOMRIGHT", XP.bar, "BOTTOMRIGHT", 0, from)
        span:SetHeight(math.max(1, to - from))
    else
        span:SetPoint("TOPLEFT", XP.bar, "TOPLEFT", from, 0)
        span:SetPoint("BOTTOMLEFT", XP.bar, "BOTTOMLEFT", from, 0)
        span:SetWidth(math.max(1, to - from))
    end
    XP.Sweep(XP.shimmer, span, { width = math.max(8, math.min(40, to - from)),
        dur = XP.SHIMMER.dur, alpha = XP.SHIMMER.alpha }, vertical)
end

function XP.Update()
    if XP.resting == nil then XP.resting = call(IsResting) == true end   -- seeded: no shimmer at login
    if not (XP.frame and XP.frame:IsShown()) then
        if ns.XPGain then ns.XPGain.last = nil end   -- shown again: no effect for what happened meanwhile
        XP.shown = nil
        return
    end
    local d = XP.Read()
    XP.bar:SetShown(d ~= nil)
    -- The bottom bar carries the background, so it shows whenever the bar
    -- does; its fill (the rested part) only when there's rest.
    XP.rested:SetShown(d ~= nil)
    XP.tickFrame:SetShown(XP.ticks and d ~= nil and not d.rep or false)
    XP.banked:SetShown(d ~= nil and not d.rep)
    if not d then
        if ns.XPGain then ns.XPGain.last = nil end
        XP.shown = nil
        return
    end
    XP.bar:SetMinMaxValues(0, d.max)
    if not (ns.XPGain and ns.XPGain.Show(d)) then XP.bar:SetValue(d.value) end
    XP.Paint(d)
    -- The finished quests' XP right after the fill, rested after that; it
    -- glides as quests are done, snaps on a new level.
    local banked = not d.rep and d.banked or 0
    local ahead = math.min(d.max, d.value + banked)
    local fresh = XP.bankedMax ~= d.max
    XP.bankedMax = d.max
    XP.banked:SetMinMaxValues(0, d.max)
    Style.SetBarValue(XP.banked, banked > 0 and ahead or 0, fresh)
    XP.banked:SetStatusBarColor(XP.BANKED[1], XP.BANKED[2], XP.BANKED[3], 1)
    XP.rested:SetMinMaxValues(0, d.max)
    XP.rested:SetValue(d.rested > 0 and math.min(d.max, ahead + d.rested) or 0)
    XP.rested:SetStatusBarColor(XP.RESTED[1], XP.RESTED[2], XP.RESTED[3], XP.RESTED[4])
    local str = XP.Format(d, d.value)
    XP.Count(d, str)
    XP.text:SetShown(str ~= nil)
end

-- Hides a game bar now and whenever the game shows it. Uses HookScript on
-- OnShow, never a hook on Show/SetShown: these are Edit Mode system frames,
-- and method hooks there broke the game's own calls.
local hooked = setmetatable({}, { __mode = "k" })
function XP.HideGameBar(frame)
    if type(frame) ~= "table" or not frame.Hide then return end
    if not hooked[frame] and frame.HookScript then
        hooked[frame] = true
        frame:HookScript("OnShow", function(self)
            if XP.hideGame then self:Hide() end
        end)
    end
    frame:Hide()
end

function XP.Apply(cfg, T)
    for _, b in ipairs({ XP.bar, XP.banked, XP.rested, XP.repBar }) do
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", XP.frame, "TOPLEFT", T, -T)
        b:SetPoint("BOTTOMRIGHT", XP.frame, "BOTTOMRIGHT", -T, T)
    end
    XP.vertical = cfg.detached == true and cfg.orientation == "vertical"
    for _, b in ipairs({ XP.bar, XP.banked, XP.rested, XP.repBar }) do XP.TurnBar(b, XP.vertical) end
    XP.text:SetRotation(XP.vertical and XP.TURN or 0)
    XP.showText = cfg.showText == true
    XP.showPercent = cfg.showPercent == true
    Style.SetTextSize(XP.text, cfg.textSize or 9)
    XP.gradient = cfg.gradient == true
    -- The old "Class color" switch, turned off before the color pick came.
    XP.colorMode = cfg.color or "accent"
    if cfg.classColor == false and (XP.colorMode == "class" or XP.colorMode == "accent") then XP.colorMode = "blue" end
    XP.custom = (type(cfg.customLo) == "table" and type(cfg.customHi) == "table")
        and { lo = cfg.customLo, hi = cfg.customHi } or nil
    XP.ticks = cfg.ticks == true
    XP.showBanked = cfg.banked ~= false
    XP.tipSide = cfg.tipSide or "auto"
    XP.hideGame = cfg.enabled and true or false
    if cfg.enabled then
        for _, name in ipairs(XP.GAME_BARS) do XP.HideGameBar(_G[name]) end
    end
    XP.LayoutTicks()
    XP.bankedXP = nil   -- counted again: the switch may have changed
    XP.CountBanked()
end

-- ---------------------------------------------------------------------
-- Separate reputation bar (rep.*, off by default) for the watched faction,
-- movable and resizable like the detached XP bar. Hidden with no watched
-- faction, except as a sample in unlock or test mode.
-- ---------------------------------------------------------------------

local Rep = {}
ns.RepBar = Rep

Rep.KEY = "infopanel.rep"
Rep.HOME = { "TOP", nil, "TOP", 0, -12 }   -- top middle: clear of the panel, bars and chat
Rep.SAMPLE = { value = 1800, max = 3000, rested = 0, color = { 0, 0.6, 0.1 }, rep = 5 }

DUI.RegisterTestPart("rep", "Reputation bar", 92, function()
    return ns.module ~= nil and ns.module.db.rep.enabled == true
end)

function Rep.Build(mod)
    local f = CreateFrame("Frame", "DaylightUIReputationBar", UIParent)
    f:SetFrameStrata("LOW")
    Style.Shell(f, { borderPx = ns.Panel.XP_BORDER })
    f:Hide()
    Rep.frame = f
    Rep.bar = Style.Bar(f, nil, ns.MEDIA.bars.xp)
    Rep.text = Style.Text(Rep.bar, 9, "CENTER", ns.MEDIA.fonts.xp)
    Rep.text:SetPoint("CENTER", f, "CENTER", 0, 0)
    Rep.shine = Rep.bar:CreateTexture(nil, "OVERLAY")
    Rep.shine:SetTexture(DUI.MEDIA .. "glow.png")
    Rep.shine:SetBlendMode("ADD")
    Rep.shine:Hide()
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        local d = Rep.Read()
        if not d or Rep.Secret(d) then return end
        XP.PlaceTip(self, Rep.tipSide)
        local Tips = DUI.Tips
        Tips.Clear()
        Tips.Title(d.label, d.color[1], d.color[2], d.color[3])
        local standing = Rep.StandingName(d.rep)
        if standing ~= "" then Tips.Sub(standing) end
        Tips.Line(DUI.L["Standing"], string.format("%s / %s  (%d%%)", BreakUpLargeNumbers(d.value),
            BreakUpLargeNumbers(d.max), math.floor(d.value / d.max * 100)))
        Tips.Flush(GameTooltip)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Rep.grip = ns.Panel.BarGrip(f, function(w, h)
        DUI.Movers.Save(Rep.KEY)
        DUI:Set("InfoPanel", "rep.width", w)
        DUI:Set("InfoPanel", "rep.height", h)
    end, function() return Rep.vertical end)
    DUI.Movers.Register(f, Rep.KEY, "Reputation Bar", Rep.HOME)
    local function refresh() if Rep.on then Rep.Update() end end
    DUI.On("UnlockChanged", function() if ns.module then Rep.Apply(ns.module.db) end end)
    DUI.On("TestModeChanged", refresh)
    DUI.On("TestPartChanged", function(key) if key == "rep" then refresh() end end)
    pcall(DUI.RegisterEvent, "UPDATE_FACTION", refresh)
end

function Rep.StandingName(reaction)
    if type(GetText) == "function" then
        local ok, s = pcall(GetText, "FACTION_STANDING_LABEL" .. tostring(reaction), UnitSex and UnitSex("player") or 2)
        if ok and type(s) == "string" then return s end
    end
    return _G["FACTION_STANDING_LABEL" .. tostring(reaction)] or ""
end

function Rep.Secret(d) return secretRep(d) end

-- The watched faction, or a sample to place it by (unlocked, or test mode).
function Rep.Read()
    local d = XP.ReadRep()
    if d then return d end
    if DUI.Movers.unlocked or (DUI.testMode and DUI.TestPartShown("rep")) then
        local s = Rep.SAMPLE
        return { value = s.value, max = s.max, rested = 0, color = s.color, rep = s.rep,
                 label = DUI.L["Reputation"], sample = true }
    end
end

-- The text: the faction's name, the numbers, the percent (nil: none).
function Rep.Format(d)
    local parts = {}
    if Rep.cfg.showName then parts[#parts + 1] = d.label end
    if not Rep.Secret(d) then
        if Rep.cfg.showText then
            parts[#parts + 1] = string.format("%s / %s", BreakUpLargeNumbers(d.value), BreakUpLargeNumbers(d.max))
        end
        if Rep.cfg.showPercent then parts[#parts + 1] = string.format("%d%%", math.floor(d.value / d.max * 100)) end
    end
    if #parts > 0 then return table.concat(parts, "   ") end
end

function Rep.Paint(d)
    local bar, G = Rep.bar, DUI.Gradients
    local key = "REP_" .. tostring(d.rep)
    if Rep.cfg.gradient and G and G.Has(key) then XP.PaintKey(bar, key, Rep.vertical)
    elseif Rep.cfg.gradient and G then XP.PaintFrom(bar, d.color, Rep.vertical)
    else Style.SetBarColor(bar, d.color[1], d.color[2], d.color[3]) end
end

-- Shows the frame when there's something to show. The fade engine owns the
-- frame's alpha, so the bar inside does the first ease-in.
function Rep.Update()
    local f = Rep.frame
    local d = Rep.on and Rep.Read() or nil
    local was = f:IsShown()
    f:SetShown(d ~= nil)
    Rep.grip:SetShown(d ~= nil and DUI.Movers.unlocked or false)
    if not d then Rep.last = nil return end
    -- Another faction (or the first look): the fill is set, not glided.
    local same = Rep.last and Rep.last.label == d.label and Rep.last.rep == d.rep
    Rep.last = { label = d.label, rep = d.rep }
    Rep.bar:SetMinMaxValues(0, d.max)
    Style.SetBarValue(Rep.bar, d.value, not same)
    Rep.Paint(d)
    local str = Rep.Format(d)
    Rep.text:SetShown(str ~= nil)
    if str then Rep.text:SetText(str) end
    if not was then
        local bar = Rep.bar
        DUI.Motion.Tween("repBar", 0, 1, DUI.Motion.NORMAL, function(a) bar:SetAlpha(a) end)
    end
end

-- A gain with the watched faction (XP.RepGain): a light across the bar.
function Rep.Gain()
    if not (Rep.frame and Rep.frame:IsShown() and DUI.Motion.On()) then return end
    XP.Sweep(Rep.shine, Rep.bar, { width = 40, dur = XP.REP_SWEEP.dur, alpha = XP.REP_SWEEP.alpha }, Rep.vertical)
end

function Rep.Apply(db)
    local cfg, f = db.rep, Rep.frame
    Rep.cfg, Rep.on = cfg, cfg.enabled == true
    Rep.tipSide = cfg.tipSide or "auto"
    Rep.vertical = cfg.orientation == "vertical"
    XP.TurnBar(Rep.bar, Rep.vertical)
    Rep.text:SetRotation(Rep.vertical and XP.TURN or 0)
    ns.Panel.Look(f, ns.Panel.BackAlpha(db), db.panelBorder)
    local T = Pixel.Px(f, Style.BorderPx(f))
    ns.Panel.SizeBar(f, cfg.width, cfg.height, T, Rep.vertical)
    Style.LayoutShell(Style.GetShell(f))
    Rep.bar:ClearAllPoints()
    Rep.bar:SetPoint("TOPLEFT", f, "TOPLEFT", T, -T)
    Rep.bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -T, T)
    Style.SetTextSize(Rep.text, cfg.textSize or 9)
    DUI.Movers.Suspend(Rep.KEY, not Rep.on)
    Rep.Update()
end
