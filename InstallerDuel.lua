-- The setup guide's "this or that" page: one question at a time, its choices
-- drawn side by side across the window with the one in use lit, and one big
-- Next. Two to four choices split the area into leaning columns with a
-- gradient line and an "or" between them; five or more become a fan of thin
-- leaning strips, the one under the mouse (or the picked one) opened wide.
-- One page is built and reused for every question (page.Show).
--
-- The lean: each column's slanted sides are cut by two masks made from one
-- right-triangle art (Media/ui-duel-edge.png and its mirror, made by
-- tools/make_duel_edge.py), so a strip of any width keeps the same 68-over-384
-- lean. The dividers are the matching line art. Click areas stay plain
-- rectangles: the game can't hit-test a slant.

local _, DUI = ...
local W = DUI.Widgets
local Style = DUI.Style
local SIZE = Style.SIZE
local C = W.COLORS
local L = DUI.L

local Duel = {}
DUI.InstallerDuel = Duel

Duel.AREA = { x = 12, y = 128, w = 876, h = 384 }
Duel.LEAN = 34                    -- half the lean: a line runs from 34 right of its spot at the top to 34 left at the bottom
Duel.WASH = { idle = 0.07, hover = 0.2, picked = 0.3 }
Duel.COVER = 0.3                  -- the others darken while the mouse is over one
Duel.FAN_FROM = 5                 -- this many choices or more make a fan
Duel.FAN_OPEN = 5.5               -- the open strip's share against 1 for the others
Duel.FAN_OVER = 36                -- the fan runs this far past the area's sides, so its outer leans hide
Duel.FAN_EDGE = 2                 -- the colored line on a strip's left edge
Duel.FAN_INSET = 18               -- the first and last strips' content sits this far toward the middle
Duel.FULL_W = 270                 -- an open strip's content
Duel.PICTURE = { [2] = 300, [3] = 210, [4] = 170 }
Duel.NAME_GAP, Duel.LINE_GAP, Duel.TAG_GAP, Duel.LINE_W = 18, 4, 10, 200
Duel.FAN_NAME_GAP = 16
Duel.LINE_BOX = 1.25              -- a line of words' box, as a share of its size
Duel.TICK, Duel.TICK_TOP = 20, 40
Duel.ORB = 30
Duel.SHOW_SIZE = 28               -- the question
Duel.TOP = { part = 22, finish = 19, ask = 44, what = 86, hint = 524 }
Duel.PART_X, Duel.LOGO, Duel.FINISH_RIGHT = 30, 26, 54
Duel.FOOT = { bottom = 22, height = 44, side = 28, backW = 78, backH = 32, nextW = 190, nextH = 40, barW = 260, barH = 4,
    barGap = 8 }
Duel.BASE = { 0.094, 0.094, 0.110 }   -- a column's own dark (#18181c)
Duel.STAGGER, Duel.WHAT_AFTER, Duel.LIFT = 0.1, 0.07, 10

local WHITE = "Interface\\Buttons\\WHITE8X8"
local EDGE, EDGE_R, LINE = DUI.MEDIA .. "ui-duel-edge.png", DUI.MEDIA .. "ui-duel-edge-r.png", DUI.MEDIA .. "ui-duel-line.png"

local function hex(c) return DUI.Win.Parts.Hex(c) end

-- Spot j of n along the Daylight sweep, blue to pink.
local function sweep(j, n)
    local a, z = Style.GRADIENT_SHAPE[1], Style.GRADIENT_SHAPE[2]
    local t = n > 1 and (j - 1) / (n - 1) or 0
    return { a[1] + (z[1] - a[1]) * t, a[2] + (z[2] - a[2]) * t, a[3] + (z[3] - a[3]) * t }
end

-- A choice: a button over its strip's straight middle, and the strip's
-- leaning shape (base, wash and cover) cut by its two masks.
local function newChoice(area)
    local c = CreateFrame("Button", nil, area)
    c:RegisterForClicks("LeftButtonUp")
    local function shape(layer, sub)
        local t = c:CreateTexture(nil, layer, nil, sub)
        t:SetTexture(WHITE)
        return t
    end
    c.base = shape("BACKGROUND")
    c.base:SetVertexColor(Duel.BASE[1], Duel.BASE[2], Duel.BASE[3], 1)
    c.wash = shape("BORDER")
    c.cover = shape("BORDER", 2)
    c.cover:SetVertexColor(0, 0, 0, 1)
    c.cover:SetAlpha(0)
    c.maskL = c:CreateMaskTexture()
    c.maskL:SetTexture(EDGE, "CLAMPTOWHITE", "CLAMPTOWHITE")
    c.maskR = c:CreateMaskTexture()
    c.maskR:SetTexture(EDGE_R, "CLAMPTOWHITE", "CLAMPTOWHITE")
    for _, t in ipairs({ c.base, c.wash, c.cover }) do
        t:AddMaskTexture(c.maskL)
        t:AddMaskTexture(c.maskR)
    end
    -- Its left edge's line, in the strip's own color (the fan's).
    c.edge = c:CreateTexture(nil, "ARTWORK")
    c.edge:SetTexture(LINE)
    c.edge:Hide()
    c.tick = W.Icon(c, "ui-check.png", Duel.TICK, C.value, "OVERLAY")
    c.tick:Hide()
    -- The content: a frame centered on the strip (split), or the closed and
    -- open samples of a fan's strip.
    c.content = CreateFrame("Frame", nil, c)
    c.content:SetSize(1, 1)
    c.name = W.Font(c.content, W.TITLE, SIZE.title, C.value, "CENTER")
    c.line = W.Font(c.content, W.BODY, SIZE.small, Style.INK.LABEL, "CENTER")
    c.line:SetWordWrap(true)
    c.line:SetJustifyV("TOP")
    c.tag = DUI.InstallerCards.ShowTag(c.content)
    c.tag:Hide()
    c.tag.Lit(true)
    c.mini = CreateFrame("Frame", nil, c)
    c.mini:SetSize(1, 1)
    return c
end

-- Lays a strip over the area between its two boundaries (b0, b1: where each
-- crosses the area's middle height, from the area's left). slant0/slant1:
-- whether that side leans; a straight side is the area's own edge.
local function place(c, area, b0, b1, slant0, slant1)
    local H, S = Duel.AREA.h, Duel.LEAN
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", area, "TOPLEFT", b0, 0)
    c:SetSize(math.max(1, b1 - b0), H)
    local left = slant0 and -S or 0
    local right = (b1 - b0) + (slant1 and S or 0)
    for _, t in ipairs({ c.base, c.wash, c.cover }) do
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", c, "TOPLEFT", left, 0)
        t:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", left, 0)
        t:SetWidth(math.max(1, right - left))
    end
    -- A straight side's mask sits outside the shape, where it clamps to white.
    c.maskL:ClearAllPoints()
    if slant0 then
        c.maskL:SetPoint("TOPLEFT", c, "TOPLEFT", -S, 0)
    else
        c.maskL:SetPoint("TOPLEFT", c, "TOPLEFT", -2 * S - 2, 0)
    end
    c.maskL:SetSize(2 * S, H)
    c.maskR:ClearAllPoints()
    if slant1 then
        c.maskR:SetPoint("TOPLEFT", c, "TOPLEFT", (b1 - b0) - S, 0)
    else
        c.maskR:SetPoint("TOPLEFT", c, "TOPLEFT", (b1 - b0) + 2, 0)
    end
    c.maskR:SetSize(2 * S, H)
    c.edge:ClearAllPoints()
    c.edge:SetPoint("TOPLEFT", c, "TOPLEFT", -S - 2, 0)
    c.edge:SetSize(2 * S + 4, H)
end

-- The divider between two columns: the gradient line and the "or" on its middle.
local function newDivider(area)
    local d = CreateFrame("Frame", nil, area)
    d:SetSize(2 * Duel.LEAN + 4, Duel.AREA.h)
    d:SetFrameLevel(area:GetFrameLevel() + 20)
    d.line = d:CreateTexture(nil, "ARTWORK")
    d.line:SetTexture(LINE)
    d.line:SetAllPoints(d)
    d.orb = CreateFrame("Frame", nil, d)
    d.orb:SetSize(Duel.ORB, Duel.ORB)
    d.orb:SetPoint("CENTER", d, "CENTER", 0, 0)
    d.orb.edge = d.orb:CreateTexture(nil, "BORDER")
    d.orb.edge:SetTexture(WHITE)
    d.orb.edge:SetSize(Duel.ORB + 2, Duel.ORB + 2)
    d.orb.edge:SetPoint("CENTER", d.orb, "CENTER", 0, 0)
    d.orb.edge:SetRotation(math.pi / 4)
    d.orb.fill = d.orb:CreateTexture(nil, "ARTWORK")
    d.orb.fill:SetTexture(WHITE)
    d.orb.fill:SetSize(Duel.ORB, Duel.ORB)
    d.orb.fill:SetPoint("CENTER", d.orb, "CENTER", 0, 0)
    d.orb.fill:SetRotation(math.pi / 4)
    d.orb.text = W.Font(d.orb, W.BODY, 11, Style.INK.LABEL, "CENTER")
    d.orb.text:SetPoint("CENTER", d.orb, "CENTER", 0, 0)
    d.orb.text:SetText(L["or"])
    function d.Paint()
        local a, z = Style.GRADIENT_SHAPE[1], Style.GRADIENT_SHAPE[2]
        d.line:SetVertexColor(1, 1, 1, 1)
        if d.line.SetGradient and CreateColor then
            d.line:SetGradient("VERTICAL", CreateColor(z[1], z[2], z[3], 1), CreateColor(a[1], a[2], a[3], 1))
        end
        W.Tint(d.orb.edge, C.cardLit)
        W.Tint(d.orb.fill, C.window)
    end
    d.Paint()
    return d
end

-- The text's height once drawn, or a fair guess before the game has drawn it.
local function heightOf(fs, guess)
    local h = fs:GetStringHeight()
    if type(h) == "number" and not DUI.IsSecret(h) and h > 0 then return h end
    return guess
end

function Duel.New(parent)
    local M, Feel = DUI.Motion, DUI.Win.Feel
    local UI = DUI.InstallerUI
    local A, F = Duel.AREA, Duel.FOOT
    local page = CreateFrame("Frame", nil, parent)
    page:SetSize(UI.SHOW_W, UI.SHOW_H)

    -- The part's name, top left, after the small sunrise logo.
    page.part = CreateFrame("Frame", nil, page)
    page.part:SetSize(200, Duel.LOGO)
    page.part:SetPoint("TOPLEFT", page, "TOPLEFT", Duel.PART_X, -Duel.TOP.part)
    page.part.logo = page.part:CreateTexture(nil, "ARTWORK")
    page.part.logo:SetTexture(DUI.MEDIA .. "logo-64.png")
    page.part.logo:SetSize(Duel.LOGO, Duel.LOGO)
    page.part.logo:SetPoint("LEFT", page.part, "LEFT", 0, 0)
    page.part.text = W.Font(page.part, W.BODY, SIZE.small, C.value)
    page.part.text:SetPoint("LEFT", page.part.logo, "RIGHT", 10, 0)

    page.finish = W.Link(page, SIZE.small)
    page.finish:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Duel.FINISH_RIGHT, -Duel.TOP.finish)
    page.finish.SetLabel(L["Finish now"])
    page.finish:SetScript("OnClick", function() if page.q and page.q.finish then DUI.SafeCall(page.q.finish) end end)

    page.ask = W.Font(page, W.TITLE, Duel.SHOW_SIZE, C.value, "CENTER")
    page.ask:SetPoint("TOP", page, "TOP", 0, -Duel.TOP.ask)
    page.what = W.Font(page, W.BODY, SIZE.body, Style.INK.LABEL, "CENTER")
    page.what:SetPoint("TOP", page, "TOP", 0, -Duel.TOP.what)

    page.area = CreateFrame("Frame", nil, page)
    page.area:SetPoint("TOPLEFT", page, "TOPLEFT", A.x, -A.y)
    page.area:SetSize(A.w, A.h)
    page.area:SetClipsChildren(true)

    page.hint = W.Font(page, W.BODY, SIZE.small, Style.INK.LABEL, "CENTER")
    page.hint:SetPoint("TOP", page, "TOP", 0, -Duel.TOP.hint)

    -- The row along the bottom: Back, the progress, Next.
    local row = UI.SHOW_H - F.bottom - F.height / 2   -- the row's middle, down from the top
    page.back = W.Button(page, BACK or L["Back"], F.backH)
    page.back:SetWidth(F.backW)
    page.back:SetPoint("LEFT", page, "TOPLEFT", F.side, -row)
    page.back:SetScript("OnClick", function() if page.q and page.q.back then DUI.SafeCall(page.q.back) end end)
    page.next = W.HeroButton(page, NEXT or L["Next"], F.nextH)
    page.next:SetWidth(F.nextW)
    page.next.SetLabel(NEXT or L["Next"])
    page.next:SetPoint("RIGHT", page, "TOPRIGHT", -F.side, -row)
    page.next:SetScript("OnClick", function() if page.q and page.q.next then DUI.SafeCall(page.q.next) end end)
    page.progress = CreateFrame("Frame", nil, page)
    page.progress:SetSize(F.barW, F.barH + F.barGap + SIZE.small + 2)
    page.progress:SetPoint("CENTER", page, "TOP", 0, -row)
    -- The bar, slanted like a health bar: its ends cut, the fill growing inside.
    page.barFrame = CreateFrame("Frame", nil, page.progress)
    page.barFrame:SetPoint("TOPLEFT", page.progress, "TOPLEFT", 0, 0)
    page.barFrame:SetSize(F.barW, F.barH)
    page.track = page.barFrame:CreateTexture(nil, "BACKGROUND")
    page.track:SetTexture(WHITE)
    page.track:SetAllPoints(page.barFrame)
    W.Tint(page.track, C.track)
    page.bar = page.barFrame:CreateTexture(nil, "ARTWORK")
    page.bar:SetTexture(WHITE)
    page.bar:SetPoint("TOPLEFT", page.barFrame, "TOPLEFT", 0, 0)
    page.bar:SetSize(1, F.barH)
    Style.Clip(page.barFrame, page.track, "outer")
    Style.Clip(page.barFrame, page.bar, "outer")
    Style.Slant(page.barFrame, "both", math.max(1, F.barH * math.tan(math.rad(22))), nil, "left")
    page.stepText = W.Font(page.progress, W.BODY, SIZE.small, Style.INK.LABEL, "CENTER")
    page.stepText:SetPoint("TOP", page.track, "BOTTOM", 0, -F.barGap)

    page.choices, page.lines = {}, {}
    local pool, dividers = {}, {}
    local barAt = 0

    local function washTo(c, to, instant)
        if instant then
            local key = c.wash.__duiAlphaKey
            if key then M.Tween(key, to, to, 0); key.goal = nil end
            c.wash:SetAlpha(to)
        else
            M.AlphaTo(c.wash, to, M.NORMAL)
        end
    end

    -- Washes, ticks and covers for who is picked and who is under the mouse.
    local function light(instant)
        local hovered
        for _, c in ipairs(page.choices) do if c.hover then hovered = c end end
        for _, c in ipairs(page.choices) do
            local picked = c.key == page.picked
            washTo(c, picked and Duel.WASH.picked or (c.hover and Duel.WASH.hover or Duel.WASH.idle), instant)
            local cover = (hovered and not c.hover and not picked) and Duel.COVER or 0
            if instant then c.cover:SetAlpha(cover) else M.AlphaTo(c.cover, cover, M.FAST) end
            c.tick:SetShown(picked)
            c.tag.Lit(true)
        end
    end

    -- The fan: weights glide from where they are to where they're going.
    local fan = { from = {}, to = {}, now = {} }
    local function layoutFan()
        local n = #page.choices
        -- Every strip after the first has its 2-wide colored edge besides its share.
        local total, sum = A.w + 2 * Duel.FAN_OVER - Duel.FAN_EDGE * (n - 1), 0
        for i = 1, n do sum = sum + fan.now[i] end
        local x = -Duel.FAN_OVER
        for i, c in ipairs(page.choices) do
            local w = total * fan.now[i] / sum + (i > 1 and Duel.FAN_EDGE or 0)
            place(c, page.area, x, x + w, true, true)
            local mid = w / 2 + (i == 1 and Duel.FAN_INSET or 0) - (i == n and Duel.FAN_INSET or 0)
            c.content:ClearAllPoints()
            c.content:SetPoint("CENTER", c, "LEFT", mid, 0)
            c.mini:ClearAllPoints()
            c.mini:SetPoint("CENTER", c, "LEFT", mid, 0)
            c.tick:ClearAllPoints()
            c.tick:SetPoint("TOP", c, "TOPLEFT", mid, -Duel.TICK_TOP)
            x = x + w
        end
    end
    local function openFan(instant)
        local open
        for _, c in ipairs(page.choices) do if c.hover then open = c.key end end
        open = open or page.picked
        for i, c in ipairs(page.choices) do
            fan.from[i] = fan.now[i] or 1
            fan.to[i] = c.key == open and Duel.FAN_OPEN or 1
            local on = c.key == open
            if instant then
                c.content:SetAlpha(on and 1 or 0); c.mini:SetAlpha(on and 0 or 1)
            else
                M.AlphaTo(c.content, on and 1 or 0, M.NORMAL)
                M.AlphaTo(c.mini, on and 0 or 1, M.NORMAL)
            end
        end
        local function step(p)
            for i = 1, #page.choices do fan.now[i] = fan.from[i] + (fan.to[i] - fan.from[i]) * p end
            layoutFan()
        end
        if instant then M.Tween(fan, 1, 1, 0, step) else M.Tween(fan, 0, 1, M.NORMAL, step) end
    end

    local function pick(c)
        local q = page.q
        if not q then return end
        page.picked = c.key
        if q.pick then DUI.SafeCall(q.pick, c.key) end
        light(false)
        if c.tick:IsShown() then
            M.Tween(c.tick, 0.5, 1, M.NORMAL, function(k) c.tick:SetSize(Duel.TICK * k, Duel.TICK * k) end)
        end
        if page.fan then openFan(false) end
        if DUI.Sound then DUI.Sound.Play("toggle") end
        page.next.Shine()
    end

    local function choiceAt(i)
        local c = pool[i]
        if not c then
            c = newChoice(page.area)
            c:SetScript("OnClick", function(self) pick(self) end)
            c:SetScript("OnEnter", function(self)
                self.hover = true
                light(false)
                if page.fan then openFan(false) end
                if page.q and page.q.hover then DUI.SafeCall(page.q.hover, self.spec, true) end
            end)
            c:SetScript("OnLeave", function(self)
                self.hover = false
                light(false)
                if page.fan then openFan(false) end
                if page.q and page.q.hover then DUI.SafeCall(page.q.hover, self.spec, false) end
            end)
            pool[i] = c
        end
        c.hover = false
        return c
    end

    -- The picture and words of a choice, stacked and centered as one block.
    -- Pictures are kept per question and width, so a page shown again reuses them.
    local cache = {}
    local function pictureFor(q, spec, width, holder)
        local key = tostring(q.id or q.ask) .. "|" .. tostring(spec.key) .. "|" .. width
        local pic = cache[key]
        if not pic and spec.picture then
            pic = spec.picture(holder, width)
            cache[key] = pic
        end
        return pic
    end
    local shownPics = {}
    local function fill(c, spec, q, width, nameGap)
        local pic = pictureFor(q, spec, width, c.content)
        if pic then
            pic:SetParent(c.content)
            pic:ClearAllPoints()
            pic:Show()
            shownPics[#shownPics + 1] = pic
        end
        if spec.nameFont then c.name:SetFont(spec.nameFont, SIZE.title, "") else Style.SetTextSize(c.name, SIZE.title) end
        c.name:SetText(spec.name or "")
        c.line:SetWidth(Duel.LINE_W)
        c.line:SetText(spec.line or "")
        c.line:SetShown(spec.line ~= nil and spec.line ~= "")
        c.tag:SetShown(c.tag.Say(spec.tag))
        -- The words sit in line boxes a little taller than the letters (1.25),
        -- so the gaps between them read the same at any font.
        local picH = pic and pic:GetHeight() or 0
        local nameH = math.ceil(SIZE.title * Duel.LINE_BOX)
        c.name:SetHeight(nameH)
        local one = math.ceil(SIZE.small * Duel.LINE_BOX)
        local lineH = 0
        if c.line:IsShown() then
            lineH = heightOf(c.line, one) > SIZE.small * 1.5 and 2 * one or one
            c.line:SetHeight(lineH)
        end
        local tagH = c.tag:IsShown() and (Duel.TAG_GAP + W.TAG_H) or 0
        local total = picH + (pic and nameGap or 0) + nameH + (lineH > 0 and Duel.LINE_GAP + lineH or 0) + tagH
        c.content:SetSize(math.max(width, Duel.LINE_W), total)
        local y = 0
        if pic then
            pic:SetPoint("TOP", c.content, "TOP", 0, 0)
            y = picH + nameGap
        end
        c.name:ClearAllPoints()
        c.name:SetPoint("TOP", c.content, "TOP", 0, -y)
        y = y + nameH
        c.line:ClearAllPoints()
        c.line:SetPoint("TOP", c.content, "TOP", 0, -(y + Duel.LINE_GAP))
        if lineH > 0 then y = y + Duel.LINE_GAP + lineH end
        c.tag:ClearAllPoints()
        c.tag:SetPoint("TOP", c.content, "TOP", 0, -(y + Duel.TAG_GAP))
    end

    local function hideAll()
        for _, c in ipairs(pool) do c:Hide() end
        for _, d in ipairs(dividers) do d:Hide() end
        for _, pic in ipairs(shownPics) do pic:Hide() end
        shownPics = {}
        if page.span then page.span:Hide(); page.span = nil end
    end

    local function buildSplit(q)
        local n = #q.choices
        local width = q.pictureWidth or Duel.PICTURE[n] or Duel.PICTURE[4]
        local cw = A.w / n
        -- A look drawn once across both columns (the portraits, the tooltips).
        local spanned
        if q.span then
            -- Built once per question and kept, like the pictures.
            local key = tostring(q.id or q.ask) .. "|span"
            local made = cache[key]
            if not made then
                local f, spots = q.span(page.area, A.w)
                made = { f = f, spots = spots }
                cache[key] = made
            end
            local f, spots = made.f, made.spots
            if f then
                f:SetParent(page.area)
                f:ClearAllPoints()
                f:SetPoint("CENTER", page.area, "CENTER", 0, 0)
                f:SetFrameLevel(page.area:GetFrameLevel() + 10)
                f:Show()
                page.span, spanned = f, spots or {}
            end
        end
        for i, spec in ipairs(q.choices) do
            local c = choiceAt(i)
            c.key, c.spec = spec.key, spec
            local b0, b1 = (i - 1) * cw, i * cw
            place(c, page.area, b0, b1, i > 1, i < n)
            local col = sweep(i, n)
            c.wash:SetVertexColor(col[1], col[2], col[3], 1)
            c.edge:Hide()
            c.mini:Hide()
            c.content:SetAlpha(1)
            c.content:Show()
            fill(c, spec, q, width, Duel.NAME_GAP)
            if spanned and spanned[spec.key] then
                -- The look sits in the shared drawing: it and the words under it
                -- are centered on the column together, as a picture would be.
                local pic = spanned[spec.key]
                local k = pic:GetScale() or 1
                local picH = (pic:GetHeight() or 0) * k
                local top = math.max(0, (A.h - (picH + Duel.NAME_GAP + c.content:GetHeight())) / 2)
                pic:ClearAllPoints()
                pic:SetPoint("TOP", c, "TOP", 0, -top / k)
                c.content:ClearAllPoints()
                c.content:SetPoint("TOP", c, "TOP", 0, -(top + picH + Duel.NAME_GAP))
            else
                c.content:ClearAllPoints()
                c.content:SetPoint("CENTER", c, "CENTER", 0, 0)
            end
            c.tick:ClearAllPoints()
            c.tick:SetPoint("TOP", c, "TOP", 0, -Duel.TICK_TOP)
            c:Show()
            page.choices[i] = c
        end
        for i = 2, n do
            local d = dividers[i - 1]
            if not d then d = newDivider(page.area); dividers[i - 1] = d end
            d:ClearAllPoints()
            d:SetPoint("CENTER", page.area, "TOPLEFT", (i - 1) * cw, -A.h / 2)
            d.Paint()
            d:Show()
            page.lines[i - 1] = d
        end
    end

    local function buildFan(q)
        local n = #q.choices
        fan.now, fan.from, fan.to = {}, {}, {}
        for i, spec in ipairs(q.choices) do
            local c = choiceAt(i)
            c.key, c.spec = spec.key, spec
            local col = sweep(i, n)
            c.wash:SetVertexColor(col[1], col[2], col[3], 1)
            c.edge:SetVertexColor(col[1], col[2], col[3], 1)
            c.edge:SetShown(i > 1)
            -- Closed: the small sample. Open: the full picture and words.
            if c.closed then c.closed:Hide(); c.closed = nil end
            local key = tostring(q.id or q.ask) .. "|" .. tostring(spec.key) .. "|closed"
            local mini = cache[key]
            if not mini and spec.closed then mini = spec.closed(c.mini); cache[key] = mini end
            if mini then
                mini:SetParent(c.mini)
                mini:ClearAllPoints()
                mini:SetPoint("CENTER", c.mini, "CENTER", 0, 0)
                mini:Show()
                c.closed = mini
                shownPics[#shownPics + 1] = mini
            end
            c.mini:Show()
            c.content:Show()
            fill(c, spec, q, q.pictureWidth or Duel.FULL_W, Duel.FAN_NAME_GAP)
            fan.now[i] = 1
            c:Show()
            page.choices[i] = c
        end
        openFan(true)
    end

    -- Sets a question on the page (page.Show is the frame's own Show). q: see Duel.New.
    function page.Set(q)
        page.q = q
        hideAll()
        page.choices, page.lines = {}, {}
        page.part.text:SetText(DUI.InstallerChrome.Spaced(q.part or ""))
        page.ask:SetText(q.ask or "")
        page.what:SetText(q.what or "")
        page.picked = nil
        for _, spec in ipairs(q.choices or {}) do
            if spec.key == q.current then page.picked = q.current end
        end
        page.fan = #q.choices >= Duel.FAN_FROM or q.fan == true
        if page.fan then buildFan(q) else buildSplit(q) end
        light(true)
        -- The hint: a warning, the first question's longer one, or the usual.
        if q.warn then
            page.hint:SetText(q.warn)
            W.TextColor(page.hint, Style.INK.WARN)
        else
            local hint = page.picked and L["Not sure? Just press Next: it keeps the one that's lit."]
                or L["Not sure? Just press Next: your setup keeps what it has."]
            if q.first then hint = L["Click the one you like, then press Next."] .. " " .. hint end
            page.hint:SetText(hint)
            W.TextColor(page.hint, Style.INK.LABEL)
        end
        local step, total = q.step or 1, math.max(1, q.total or 1)
        local r, g, b = Style.Accent()
        page.stepText:SetText(string.format(L["Step %s of %d"], hex({ r, g, b }) .. step .. "|r", total))
        local goal = F.barW * math.min(1, step / total)
        M.Tween(page.bar, barAt, goal, M.SLOW, function(w)
            barAt = w
            page.bar:SetWidth(math.max(1, w))
        end)
        local a, z = Style.GRADIENT_SHAPE[1], Style.GRADIENT_SHAPE[2]
        page.bar:SetVertexColor(1, 1, 1, 1)
        if page.bar.SetGradient and CreateColor then
            page.bar:SetGradient("HORIZONTAL", CreateColor(a[1], a[2], a[3], 1), CreateColor(z[1], z[2], z[3], 1))
        end
        page.next.SetLabel(q.nextText or NEXT or L["Next"])
        page.next:SetWidth(F.nextW)
        page.finish:SetShown(q.finish ~= nil)
    end

    -- The question, the line under it, then each choice a beat after the last.
    function page.Play()
        local slow = M.SLOW
        Feel.Piece(page.ask, 0, slow, Duel.LIFT)
        Feel.Piece(page.what, Duel.WHAT_AFTER, slow, Duel.LIFT / 2)
        local t = Duel.WHAT_AFTER
        for i, c in ipairs(page.choices) do
            t = Duel.WHAT_AFTER + i * Duel.STAGGER
            Feel.Piece(c, t, slow, Duel.LIFT)
        end
        for _, d in ipairs(page.lines) do Feel.Piece(d, t, slow, 0) end
        if page.span then Feel.Piece(page.span, Duel.WHAT_AFTER + Duel.STAGGER, slow, Duel.LIFT) end
    end

    page:HookScript("OnShow", function()
        for _, d in ipairs(page.lines) do d.Paint() end
    end)
    return page
end
