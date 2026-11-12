-- Legacy window, Progress page. The player's Legacy Points large inside a ring that
-- fills toward the next reward, a line saying what's next and how many points to go,
-- then the track: a gradient bar with a marker at each reward level and one card per
-- reward below. Earned cards are full color with an accent line on top and "Earned" in
-- green; the rest are dimmed with "9 more" in the accent. Hover shows the reward's
-- tooltip (the item's own first). New points count up, the ring and bar glide, and a
-- reached reward shines.
--
-- Four cards show at once, like the game; extra rewards glide sideways on the mouse
-- wheel. The bar fill lines up with the cards the same way as the game's
-- SetupProgressDetails: bar start to the first card, then card to card, by points.

local _, DUI = ...
DUI.Legacy = DUI.Legacy or {}
local ns = DUI.Legacy
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win
local Motion = DUI.Motion

local Progress = {}
ns.Progress = Progress

Progress.EDGE = 22
Progress.SHOW = 4           -- cards visible at once
Progress.CARD_GAP = 14
Progress.CARD_H = 218
Progress.ICON = 56
Progress.MEDAL = 84
Progress.RING = DUI.MEDIA .. "portrait-band.png"   -- the unit frames' ring art
Progress.RING_D = 1e7       -- the ring's cooldown duration, long enough that it never moves on its own
Progress.HERO_Y = -20
Progress.TRACK_Y = -136
Progress.BAR_H = 6
Progress.CARDS_Y = -170
Progress.NUMBER = 32        -- size of the big points number (display art)

local WHITE = "Interface\\Buttons\\WHITE8X8"
local function W() return DUI.Widgets end
local function hex(c) return Win.Parts.Hex(c) end
local function pop(n) return hex({ Style.Pop() }) .. tostring(n) .. "|r" end

local function tex(parent, layer, c, sub)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(WHITE)
    if c then t:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
    return t
end

-- Ring: a long cooldown that looks paused, over the band art (like the unit frames'
-- aggro fill), showing fraction v of the way round from the top

local function makeMedal(page)
    local m = CreateFrame("Frame", nil, page)
    m:SetSize(Progress.MEDAL, Progress.MEDAL)
    m.back = m:CreateTexture(nil, "BACKGROUND")
    m.back:SetTexture(DUI.MEDIA .. "shape-circle.png")
    m.back:SetAllPoints(m)
    m.back:SetVertexColor(0.04, 0.04, 0.045, 1)
    m.track = m:CreateTexture(nil, "BORDER")
    m.track:SetTexture(Progress.RING)
    m.track:SetAllPoints(m)
    local I = Style.INK.OFF
    m.track:SetVertexColor(I[1], I[2], I[3], 0.35)
    local cd = CreateFrame("Cooldown", nil, m)
    cd:SetAllPoints(m)
    cd:SetSwipeTexture(Progress.RING)
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    cd:SetReverse(true)
    m.fill = cd
    local top = CreateFrame("Frame", nil, m)
    top:SetAllPoints(m)
    top:SetFrameLevel(cd:GetFrameLevel() + 1)
    m.num = Style.Text(top, Progress.NUMBER, "CENTER")
    m.num:SetPoint("CENTER", m, "CENTER", 0, 0)
    m.at = 0
    return m
end

local function drawRing(m, v)
    m.at = v
    if v <= 0 then m.fill:Hide() return end
    local r, g, b = Style.Accent()
    m.fill:SetSwipeColor(r, g, b, 1)
    m.fill:SetCooldown(GetTime() - math.min(v, 0.999) * Progress.RING_D, Progress.RING_D)
    m.fill:Show()
end

-- Reward card

local function makeCard(parent)
    local b = CreateFrame("Button", nil, parent)
    b.bg = tex(b, "BACKGROUND", { 1, 1, 1, 0.03 })
    b.bg:SetAllPoints(b)
    b.hi = tex(b, "BORDER", Win.Parts.HI)
    b.hi:SetAllPoints(b)
    b.hi:Hide()
    b.lit = tex(b, "ARTWORK")   -- accent line along the top of an earned card
    b.lit:SetHeight(2)
    b.lit:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.lit:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
    b.edge = tex(b, "ARTWORK")
    b.edge:SetSize(Progress.ICON + 2, Progress.ICON + 2)
    b.edge:SetPoint("TOP", b, "TOP", 0, -26)
    b.well = tex(b, "ARTWORK", { 0, 0, 0, 1 }, 1)
    b.well:SetPoint("TOPLEFT", b.edge, "TOPLEFT", 1, -1)
    b.well:SetPoint("BOTTOMRIGHT", b.edge, "BOTTOMRIGHT", -1, 1)
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetAllPoints(b.well)
    Style.CropIcon(b.icon)
    b.name = Style.Text(b, Style.SIZE.body, "CENTER")
    b.name:SetPoint("TOP", b.edge, "BOTTOM", 0, -12)
    b.name:SetPoint("LEFT", b, "LEFT", 10, 0)
    b.name:SetPoint("RIGHT", b, "RIGHT", -10, 0)
    b.name:SetWordWrap(true)
    b.kind = Style.Text(b, Style.SIZE.small, "CENTER")
    b.kind:SetPoint("TOP", b.name, "BOTTOM", 0, -6)
    Style.InkText(b.kind, "LABEL")
    b.state = Style.Text(b, Style.SIZE.small, "CENTER")
    b.state:SetPoint("BOTTOM", b, "BOTTOM", 0, 14)
    b.shine = tex(b, "OVERLAY", nil, 7)
    b.shine:SetBlendMode("ADD")
    b.shine:SetHeight(Progress.CARD_H)
    b.shine:Hide()
    b:SetScript("OnEnter", function(self)
        Win.Parts.Light(self.hi, true)
        Progress.Tip(self)
    end)
    b:SetScript("OnLeave", function(self)
        Win.Parts.Light(self.hi, false)
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    b:SetScript("OnClick", function(self)
        local r = self.reward
        if r and r.itemID and IsModifiedClick and IsModifiedClick() and type(HandleModifiedItemClick) == "function" then
            local link = select(2, pcall(function() return select(2, C_Item.GetItemInfo(r.itemID)) end))
            if type(link) == "string" then HandleModifiedItemClick(link) end
        end
    end)
    return b
end

-- Reward tooltip: the item's own (the game's, with mount and pet lines), then where it
-- sits on the track and how far away it is.
function Progress.Tip(b)
    local r, level = b.reward, b.level
    if not (r and GameTooltip) then return end
    local T = DUI.Tips
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    T.Clear()
    if r.itemID and GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(r.itemID)
        T.Gap()
    else
        T.Title(r.name, Win.Parts.QualityColor(r.quality))
        if r.kind ~= "" then T.Sub(r.kind) end
        if r.desc and r.desc ~= "" then T.Text(r.desc) end
        T.Gap()
    end
    local earned = ns.Data.Earned()
    T.Sub(string.format(L["Legacy reward at %d"], level))
    if earned >= level then T.Text(L["Earned"], Style.INK.GOOD)
    else T.Text(string.format(L["%s more Legacy Points"], pop(level - earned))) end
    T.Flush(GameTooltip)
    GameTooltip:Show()
end

local function paintCard(b, row, earned, shine)
    local r = row.rewards[1] or { name = "", kind = "" }
    b.reward, b.level = r, row.level
    local got = earned >= row.level
    b.icon:SetTexture(r.icon or 134400)
    b.icon:SetDesaturated(not got)
    b.icon:SetVertexColor(got and 1 or 0.55, got and 1 or 0.55, got and 1 or 0.55, 1)
    local qr, qg, qb = Win.Parts.QualityColor(r.quality)
    if not r.quality then qr, qg, qb = Style.INK.LABEL[1], Style.INK.LABEL[2], Style.INK.LABEL[3] end
    b.edge:SetVertexColor(qr, qg, qb, got and 1 or 0.35)
    b.name:SetText(r.name or "")
    Style.InkText(b.name, got and "VALUE" or "OFF")
    b.kind:SetText(r.kind or "")
    b.lit:SetShown(got)
    if got then Style.PaintAccent(b.lit, 1) end
    if got then
        b.state:SetText(L["Earned"])
        Style.InkText(b.state, "GOOD")
    else
        b.state:SetText(string.format(L["%s more"], pop(row.level - earned)))
        Style.InkText(b.state, "LABEL")
    end
    if shine and DUI.Motion then
        Motion.Sweep(b.shine, b, { width = 120, dur = 0.6, alpha = 0.4, color = Win.Parts.SHINE, key = b.shine })
        Motion.Bump(b.edge, 1.12, Motion.NORMAL)
    end
end

-- Track geometry

-- Current inner width of the page (the grip's size, or the window's).
local function width(page)
    local w = page:GetWidth()
    if type(w) ~= "number" or w <= 0 then w = ns.Window.PageSize() end
    return w + Win.GoalGrowth(page)
end

local function cardW(w)
    return math.floor((w - 2 * Progress.EDGE - (Progress.SHOW - 1) * Progress.CARD_GAP) / Progress.SHOW)
end

-- Center of card i along the bar (x from the bar's left), counting from first visible
-- card `off` (fractional while gliding).
local function spot(i, off, cw)
    return (i - 1 - off) * (cw + Progress.CARD_GAP) + cw / 2
end

-- How far the bar fills (px from its left) for these points: bar start to the first
-- card, then card to card, like the game.
function Progress.FillX(levels, earned, off, cw, bw)
    local lastLevel, lastX = 0, (off > 0) and (spot(1, off, cw) - (cw + Progress.CARD_GAP)) or 0
    for i, row in ipairs(levels) do
        local x = spot(i, off, cw)
        if earned < row.level then
            local x0 = lastX
            local v = x0 + (x - x0) * (earned - lastLevel) / (row.level - lastLevel)
            return math.max(0, math.min(bw, v))
        end
        lastLevel, lastX = row.level, x
    end
    return bw
end

-- The page

local function lay(page, off)
    local w = width(page)
    local cw = cardW(w)
    local bw = w - 2 * Progress.EDGE
    page.clip:SetSize(bw, Progress.CARD_H + 30)
    page.bar:SetWidth(bw)
    for i, b in ipairs(page.cards) do
        if b:IsShown() then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", page.clip, "TOPLEFT", (i - 1 - off) * (cw + Progress.CARD_GAP), -30)
            b:SetSize(cw, Progress.CARD_H)
            local m = page.marks[i]
            m:ClearAllPoints()
            m:SetPoint("CENTER", page.bar, "LEFT", spot(i, off, cw), 0)
            local x = spot(i, off, cw)
            m:SetShown(x > -8 and x < bw + 8)
        end
    end
    return cw, bw
end

local function mark(page, i)
    local m = page.marks[i]
    if m then return m end
    m = CreateFrame("Frame", nil, page)
    m:SetSize(26, 26)
    m:SetFrameLevel(page.bar:GetFrameLevel() + 2)
    m.edge = tex(m, "BORDER")
    m.edge:SetSize(17, 17)
    m.edge:SetPoint("CENTER", m, "CENTER", 0, 0)
    m.edge:SetRotation(math.pi / 4)
    m.well = tex(m, "ARTWORK", { 0.07, 0.07, 0.08, 1 })
    m.well:SetSize(14, 14)
    m.well:SetPoint("CENTER", m, "CENTER", 0, 0)
    m.well:SetRotation(math.pi / 4)
    m.text = Style.Text(m, Style.SIZE.tiny, "CENTER")
    m.text:SetPoint("CENTER", m, "CENTER", 0, 0)
    page.marks[i] = m
    return m
end

local function paintMark(m, level, got)
    m.text:SetText(tostring(level))
    Style.InkText(m.text, got and "VALUE" or "OFF")
    if got then local r, g, b = Style.Accent(); m.edge:SetVertexColor(r, g, b, 1)
    else local c = Style.INK.OFF; m.edge:SetVertexColor(c[1], c[2], c[3], 0.5) end
end

-- Ring fraction: from the last reward reached to the next.
local function ringShare(levels, earned)
    local from, to = 0, nil
    for _, row in ipairs(levels) do
        if earned >= row.level then from = row.level else to = row.level break end
    end
    if not to then return 1 end
    return (earned - from) / math.max(to - from, 1)
end

local function nextLine(levels, earned)
    for _, row in ipairs(levels) do
        if earned < row.level then
            local r = row.rewards[1]
            local name = r and r.name or ""
            if r and r.quality then name = hex({ Win.Parts.QualityColor(r.quality) }) .. name .. "|r"
            else name = hex(Style.INK.VALUE) .. name .. "|r" end
            return string.format(L["Next: %s at %d, %s to go"], name, row.level, pop(row.level - earned))
        end
    end
    return L["Every reward earned."]
end

-- keep: a refill (a point earned) animates what changed; a first fill just sets it.
function Progress.Render(keep)
    local page = Progress.page
    if not (page and page:IsShown()) then return end
    local data = ns.Data.Track(function() ns.Window.Refresh("progress") end)
    Progress.data = data
    if not data or #data.levels == 0 then
        page.hero:Hide()
        page.track:Hide()
        page.note:SetText(L["Legacy rewards aren't available yet."])
        page.note:Show()
        return
    end
    page.note:Hide()
    page.hero:Show()
    page.track:Show()
    local earned = data.earned
    local was = keep and Progress.shown
    local levels = data.levels
    -- First visible card: the one holding the next reward, kept until the wheel moves it.
    local most = math.max(#levels - Progress.SHOW, 0)
    if not Progress.off or not keep then
        local nextI = #levels
        for i, row in ipairs(levels) do if earned < row.level then nextI = i break end end
        Progress.off = math.max(0, math.min(most, nextI - 2))
    end
    Progress.off = math.min(Progress.off, most)
    for i, row in ipairs(levels) do
        local b = page.cards[i]
        if not b then b = makeCard(page.clip); page.cards[i] = b end
        b:Show()
        local reached = was and was < row.level and earned >= row.level
        paintCard(b, row, earned, reached)
        paintMark(mark(page, i), row.level, earned >= row.level)
    end
    for i = #levels + 1, #page.cards do page.cards[i]:Hide(); if page.marks[i] then page.marks[i]:Hide() end end
    local cw, bw = lay(page, Progress.off)
    -- Points: the number counts, ring and bar glide (snap with motion off).
    local m = page.medal
    local from = was or earned
    local fillTo = Progress.FillX(levels, earned, Progress.off, cw, bw) / math.max(bw, 1)
    local ringTo = ringShare(levels, earned)
    page.next:SetText(nextLine(levels, earned))
    if was and was ~= earned and Motion.On() then
        local fillFrom, ringFrom = page.bar:GetValue() or 0, m.at or 0
        Motion.Tween(page, 0, 1, Motion.SLOW, function(p)
            m.num:SetText(tostring(math.floor(from + (earned - from) * p + 0.5)))
            page.bar:SetValue(fillFrom + (fillTo - fillFrom) * p)
            drawRing(m, ringFrom + (ringTo - ringFrom) * p)
        end, function()
            m.num:SetText(tostring(earned))
            page.bar:SetValue(fillTo)
            drawRing(m, ringTo)
        end)
    else
        Motion.Tween(page, 0, 0, 0)
        m.num:SetText(tostring(earned))
        page.bar:SetValue(fillTo)
        drawRing(m, ringTo)
    end
    Style.InkText(m.num, "pop")
    W().BarAccent(page.bar)
    Progress.shown = earned
end

-- Mouse wheel over the cards moves one card, gliding (only with more than four).
function Progress.Wheel(delta)
    local data = Progress.data
    local page = Progress.page
    if not (data and page) then return end
    local most = math.max(#data.levels - Progress.SHOW, 0)
    local to = math.max(0, math.min(most, (Progress.goal or Progress.off or 0) - delta))
    if to == (Progress.goal or Progress.off) then return end
    Progress.goal = to
    local from = Progress.off or 0
    local earned = data.earned
    local function at(off)
        Progress.off = off
        local cw, bw = lay(page, off)
        page.bar:SetValue(Progress.FillX(data.levels, earned, off, cw, bw) / math.max(bw, 1))
    end
    if Motion.On() then
        Motion.Tween(page.clip, from, to, Motion.NORMAL, at, function() at(to); Progress.goal = nil end)
    else
        at(to)
        Progress.goal = nil
    end
end

-- While the grip drags, cards and bar follow the edge.
function Progress.Stretch()
    local page = Progress.page
    if page and page:IsShown() and Progress.data then
        local cw, bw = lay(page, Progress.off or 0)
        page.bar:SetValue(Progress.FillX(Progress.data.levels, Progress.data.earned, Progress.off or 0, cw, bw) / math.max(bw, 1))
    end
end

function Progress.Build(page)
    Progress.page = page
    page.cards, page.marks = {}, {}
    local hero = CreateFrame("Frame", nil, page)
    hero:SetPoint("TOPLEFT", page, "TOPLEFT", Progress.EDGE + 6, Progress.HERO_Y)
    hero:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Progress.EDGE, Progress.HERO_Y)
    hero:SetHeight(Progress.MEDAL)
    page.hero = hero
    page.medal = makeMedal(hero)
    page.medal:SetPoint("LEFT", hero, "LEFT", 0, 0)
    page.label = Style.Text(hero, Style.SIZE.head, "LEFT")
    page.label:SetPoint("BOTTOMLEFT", page.medal, "RIGHT", 18, 3)
    page.label:SetText(L["Legacy Points"])
    Style.InkText(page.label, "LABEL")
    page.next = Style.Text(hero, Style.SIZE.body, "LEFT")
    page.next:SetPoint("TOPLEFT", page.medal, "RIGHT", 18, -4)
    page.next:SetPoint("RIGHT", hero, "RIGHT", 0, 0)
    page.next:SetWordWrap(false)
    Style.InkText(page.next, "TEXT")
    -- The track: bar with markers and cards below, clipped (cards past the fourth glide in
    -- from the side).
    local track = CreateFrame("Frame", nil, page)
    track:SetPoint("TOPLEFT", page, "TOPLEFT", Progress.EDGE, Progress.TRACK_Y)
    track:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -Progress.EDGE, 12)
    page.track = track
    page.bar = W().Bar(track, Progress.BAR_H)
    page.bar:SetPoint("TOPLEFT", track, "TOPLEFT", 0, -10)
    page.clip = CreateFrame("Frame", nil, track)
    page.clip:SetPoint("TOPLEFT", track, "TOPLEFT", 0, -4)
    page.clip:SetClipsChildren(true)
    track:EnableMouseWheel(true)
    track:SetScript("OnMouseWheel", function(_, delta) Progress.Wheel(delta) end)
    page.note = Style.Text(page, Style.SIZE.body, "CENTER")
    page.note:SetPoint("CENTER", page, "CENTER", 0, 0)
    Style.InkText(page.note, "LABEL")
    page.note:Hide()
    page:HookScript("OnHide", function() Progress.shown = nil end)
end

function Progress.Fill(page)
    Progress.Render()
end

function Progress.Pieces(page)
    local out = { page.hero, page.bar }
    for _, b in ipairs(page.cards) do if b:IsShown() then out[#out + 1] = b end end
    return out
end
