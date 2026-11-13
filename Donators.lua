-- General > Top donators: players who support DaylightUI on Ko-fi, ranked by
-- what they gave (amounts never shown), and how to join them. Opened from the
-- "Top donators" link in the options home page header. The list ships with
-- the addon and is updated by hand before a release.
--
-- One centered card: a title and thank-you over a small divider, the top
-- three on a podium (first in the middle, raised), each with a softly
-- breathing glow and wisps of light rising off it, the rest of the top ten
-- numbered in a card, everyone after them in a quieter card, and the Ko-fi
-- button under a last thank-you. All in the Daylight gradient regardless of
-- the accent, like the options window.

local _, DUI = ...
local L = DUI.L
local Style = DUI.Style
local SIZE = Style.SIZE

local Donators = {}
DUI.Donators = Donators

-- Most given first. The amounts are kept privately and never shipped.
Donators.LIST = {
    "E leader",
    "Fley",
    "InventorOfTrees",
    "Allkamet",
    "Torrent",
    "SPARQ",
    "Pownzerfaust",
    "Tih Tahz",
    "Thorvald87",
    "Popatuna",
    "Boof",
    "Schmuddeljunge",
    "EZ",
    "Jin Rahk",
    "Alcasan",
    "blukraken",
    "Fang",
    "Manuel",
    "Luke",
    "riot.",
    "munolos",
    "Troody",
    "ezra",
    "Bryan",
    "Derrick Bevan",
    "X Razer",
    "ramnokri",
    "Shady",
    "Diaper Daddy",
    "wcDAEMON",
    "Spoon",
    "Edy S",
    "Mizunami",
    "xrayin",
    "PrinceOfPromise",
    "Stefan Ilic",
    "FrostByghte",
    "Sukori",
    "sam",
    "Daniel",
    "Dragon Slayer",
}

-- Monthly supporters (a Ko-fi subscription or an active Patreon member), shown
-- in their own lit card under the podium. They also stay in LIST at their
-- place by total given.
Donators.MONTHLY = {
    "Troody",
    "blukraken",
    "SPARQ",
    "Bryan",
    "Derrick Bevan",
    "Stefan Ilic",
    "FrostByghte",
}

local WHITE = "Interface\\Buttons\\WHITE8X8"
local GLOW = DUI.MEDIA .. "glow.png" -- a soft round light
local HEART = DUI.MEDIA .. "ui-heart.png" -- the heart from Tip Daylight
local HEART_PX = 13

-- Page measurements (px).
local HERO = 26 -- title size, a hero page title (Style.SIZE stops at 18)
local CARD_W, CARD_H = 180, 72
local FIRST_H = 88         -- first place stands taller...
local FIRST_UP = 12        -- ...and higher
local CARD_GAP = 14
local LINE = 24 -- one name's line in the list
local LIST_PAD = 16
local LIST_GAP = 14 -- between the top ten card and the rest
local TOP_N = 10 -- the podium's three plus this card

local TOP_TITLE = 6
local TOP_THANKS = TOP_TITLE + 38
local TOP_RULE = TOP_THANKS + 30
local TOP_PODIUM = TOP_RULE + 40 -- room above first place for its wisps
local TOP_LIST = TOP_PODIUM + FIRST_H + 28

-- Places on the podium, left to right: second, first, third.
local PODIUM = { 2, 1, 3 }
-- Each place's position along the Daylight sweep (its glow and wisps color)
-- and how strong its light is.
local SPOT = { [1] = 0.5, [2] = 0.15, [3] = 0.85 }
local LIGHT = { [1] = 1, [2] = 0.6, [3] = 0.6 }
local WISPS = { [1] = 7, [2] = 4, [3] = 4 }

-- Animation pace in seconds: the glow's breath, a wisp's rise.
local BREATH = 3.2
local RISE_MIN, RISE_MAX = 2.4, 3.8
local RISE_PX = 46

local function columns(width)
    return (type(width) == "number" and width < 560) and 2 or 3
end

-- Names in the two cards: the top ten after the podium (an empty list keeps
-- this card for "No donators yet."), then everyone else.
local function topCount() return math.max(0, math.min(#Donators.LIST, TOP_N) - 3) end
local function restCount() return math.max(0, #Donators.LIST - TOP_N) end

local function cardHeight(n, width)
    local rows = n == 0 and 1 or math.ceil(n / columns(width))
    return 40 + rows * LINE + LIST_PAD
end

-- Height of the monthly card plus the gap after it, or 0 when there are none.
local function monthlyHeight(width)
    local n = #Donators.MONTHLY
    return n > 0 and (cardHeight(n, width) + LIST_GAP) or 0
end

-- Height of the cards under the podium plus gaps (no top ten card when there
-- are 1 to 3 names).
local function listHeight(width)
    local n = #Donators.LIST
    local h = monthlyHeight(width)
    if n == 0 or topCount() > 0 then h = cardHeight(topCount(), width) end
    if restCount() > 0 then h = h + LIST_GAP + cardHeight(restCount(), width) end
    return h
end

local function rowWidth(row)
    local w = row:GetWidth()
    if type(w) ~= "number" or w <= 0 then w = (DUI.OptionsPanel and DUI.OptionsPanel.CONTENT_WIDTH) or 600 end
    return w
end

-- A card in the options window's own look (W.Card: rounded fill and outline),
-- with its outline in the Daylight gradient.
local function roundCard(parent)
    local W, C = DUI.Widgets, DUI.Widgets.COLORS
    local f = CreateFrame("Frame", nil, parent)
    f.bg = W.Round(f, "BACKGROUND")
    f.bg:SetAllPoints(f)
    W.Tint(f.bg, C.card)
    f.edge = W.Round(f, "BORDER", 0, true)
    f.edge:SetAllPoints(f)
    return f
end

-- Restart a wisp somewhere along its card's top, at its own pace.
local function respawn(w, now)
    w.born = now
    w.life = RISE_MIN + math.random() * (RISE_MAX - RISE_MIN)
    w.x = (math.random() - 0.5) * (w.card:GetWidth() - 24)
    w.sway = 4 + math.random() * 6
    w.size = 10 + math.random() * 14
    w.tex:SetSize(w.size, w.size)
end

local function podiumCard(row, place)
    local W, C = DUI.Widgets, DUI.Widgets.COLORS
    local f = roundCard(row)
    f:SetSize(CARD_W, place == 1 and FIRST_H or CARD_H)
    f.rank = W.Font(f, W.BODY, SIZE.small, C.value, "CENTER")
    f.rank:SetPoint("TOP", f, "TOP", 0, place == 1 and -18 or -14)
    f.name = W.Font(f, W.TITLE, place == 1 and SIZE.title or SIZE.head, C.value, "CENTER")
    f.name:SetPoint("TOP", f.rank, "BOTTOM", 0, -8)
    f.name:SetPoint("LEFT", f, "LEFT", 10, 0)
    f.name:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    f.name:SetWordWrap(false)
    f.name.english = true -- names aren't translated
    -- A thin lit line along the card's top, like our windows have.
    f.top = f:CreateTexture(nil, "ARTWORK")
    f.top:SetTexture(WHITE)
    f.top:SetHeight(1)
    f.top:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -1)
    f.top:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -1)

    -- Its light, behind it on the row: a soft halo and the wisps.
    local r, g, b = Style.SweepAt(SPOT[place])
    f.halo = row:CreateTexture(nil, "BACKGROUND")
    f.halo:SetTexture(GLOW)
    f.halo:SetBlendMode("ADD")
    f.halo:SetVertexColor(r, g, b, 1)
    f.halo:SetPoint("CENTER", f, "CENTER", 0, 6)
    f.halo:SetSize(CARD_W * 1.7, (place == 1 and FIRST_H or CARD_H) * 2.2)
    f.wisps = {}
    for i = 1, WISPS[place] do
        local tex = row:CreateTexture(nil, "BORDER")
        tex:SetTexture(GLOW)
        tex:SetBlendMode("ADD")
        local t = SPOT[place] + (math.random() - 0.5) * 0.3
        tex:SetVertexColor(Style.SweepAt(t))
        tex:SetAlpha(0)
        f.wisps[i] = { tex = tex, card = f }
    end
    return f
end

-- Animates the halos and wisps while the page is up (a hidden frame gets no
-- OnUpdate). Stands still with motion off.
local function drawLight(row, now)
    -- Monthly supporters' hearts beat, each slightly after the last.
    for i, line in ipairs(row.monthly.lines) do
        if line.heart and line:IsShown() then
            local t = ((now / BREATH) + i * 0.15) % 1
            local beat = t < 0.12 and math.sin(t / 0.12 * math.pi) or 0
            line.heart:SetSize(HEART_PX * (1 + 0.25 * beat), HEART_PX * (1 + 0.25 * beat))
            line.heart:SetAlpha(0.75 + 0.25 * beat)
        end
    end
    for place, f in pairs(row.cards) do
        local k = LIGHT[place]
        local on = f:IsShown()
        local breath = 0.5 + 0.5 * math.sin((now / BREATH) * 2 * math.pi + place)
        f.halo:SetShown(on)
        f.halo:SetAlpha(on and k * (0.16 + 0.12 * breath) or 0)
        for _, w in ipairs(f.wisps) do
            if not on then
                w.tex:Hide()
            else
                if not w.born or now - w.born >= w.life then respawn(w, now) end
                local p = (now - w.born) / w.life
                local x = w.x + math.sin(p * math.pi * 2 + w.size) * w.sway
                w.tex:ClearAllPoints()
                w.tex:SetPoint("CENTER", f, "TOP", x, -4 + p * RISE_PX)
                w.tex:SetAlpha(k * 0.55 * math.sin(p * math.pi))
                w.tex:Show()
            end
        end
    end
end

local function stillLight(row)
    for _, line in ipairs(row.monthly.lines) do
        if line.heart then line.heart:SetSize(HEART_PX, HEART_PX); line.heart:SetAlpha(1) end
    end
    for place, f in pairs(row.cards) do
        f.halo:SetShown(f:IsShown())
        f.halo:SetAlpha(LIGHT[place] * 0.22)
        for _, w in ipairs(f.wisps) do w.tex:Hide() end
    end
end

local function build(row)
    local W, C = DUI.Widgets, DUI.Widgets.COLORS

    row.title = W.Font(row, W.TITLE, HERO, C.value, "CENTER")
    row.title:SetPoint("TOP", row, "TOP", 0, -TOP_TITLE)
    row.thanks = W.Font(row, W.BODY, SIZE.body, C.text, "CENTER")
    row.thanks:SetPoint("TOP", row, "TOP", 0, -TOP_THANKS)
    row.thanks:SetText(L["Thank you to everyone who supports DaylightUI and keeps it growing."])

    -- The divider: two rules fading out from a small diamond between them.
    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetTexture(WHITE)
    row.dot:SetSize(5, 5)
    row.dot:SetRotation(math.pi / 4)
    row.dot:SetPoint("CENTER", row, "TOP", 0, -TOP_RULE)
    row.rules = {}
    for i, side in ipairs({ -1, 1 }) do
        local r = row:CreateTexture(nil, "ARTWORK")
        r:SetTexture(WHITE)
        r:SetSize(150, 1)
        r:SetPoint(side < 0 and "RIGHT" or "LEFT", row.dot, side < 0 and "LEFT" or "RIGHT", side * 10, 0)
        r.side = side
        row.rules[i] = r
    end

    row.cards = {}
    for _, place in ipairs(PODIUM) do row.cards[place] = podiumCard(row, place) end
    row.cards[1]:SetPoint("TOP", row, "TOP", 0, -TOP_PODIUM)
    row.cards[2]:SetPoint("TOPRIGHT", row.cards[1], "TOPLEFT", -CARD_GAP, -FIRST_UP)
    row.cards[3]:SetPoint("TOPLEFT", row.cards[1], "TOPRIGHT", CARD_GAP, -FIRST_UP)

    -- The rest of the top ten, numbered, then everyone else. Most given first,
    -- read across the columns.
    local function listCard()
        local card = roundCard(row)
        W.Tint(card.edge, C.cardEdge)
        card.head = W.Font(card, W.BODY, SIZE.small, C.value)
        card.head:SetPoint("TOPLEFT", card, "TOPLEFT", LIST_PAD, -14)
        card.lines = {}
        return card
    end
    row.monthly = listCard()
    row.list = listCard()
    row.list.empty = W.Font(row.list, W.BODY, SIZE.body, C.dim)
    row.list.empty:SetPoint("TOPLEFT", row.list, "TOPLEFT", LIST_PAD, -40)
    row.list.empty:SetText(L["No donators yet."])
    row.rest = listCard()

    row.footer = W.Font(row, W.BODY, SIZE.small, C.dim, "CENTER")
    row.footer:SetText(L["Thank you for making DaylightUI possible."])
    row.kofi = W.Button(row, L["Support on Ko-fi"], 26)
    row.kofi:SetWidth(170)
    row.kofi:SetScript("OnClick", function() DUI.OptionsPanel.ShowKofi() end)

    -- The light runs on its own frame, only while the page is up.
    row.fx = CreateFrame("Frame", nil, row)
    row.fx:SetScript("OnUpdate", function() drawLight(row, GetTime()) end)

    -- Each time the page opens the podium rises in, first place first.
    row:HookScript("OnShow", function()
        local M = DUI.Motion
        row.fx:SetShown(M.On())
        if not M.On() then stillLight(row) end
        for i, place in ipairs({ 1, 2, 3 }) do
            local c = row.cards[place]
            if c:IsShown() then M.SlideIn(c, 0, -10, M.NORMAL, (i - 1) * 0.08) end
        end
        if row.monthly:IsShown() then M.Fade(row.monthly, 0, 1, M.SLOW, 0.15) end
        if row.list:IsShown() then M.Fade(row.list, 0, 1, M.SLOW, 0.2) end
        if row.rest:IsShown() then M.Fade(row.rest, 0, 1, M.SLOW, 0.3) end
    end)
end

-- A list card across the row, `top` px down, tall enough for n names.
local function placeCard(card, row, top, width, n)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -top)
    card:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -top)
    card:SetHeight(cardHeight(n, width))
end

-- Fills a card with n names starting at `first`. Top ten names carry their
-- rank and are white; the rest get a diamond along the sweep and soft white
-- names, quieter. The monthly card (ranked == "monthly") gets a beating heart
-- and names in the Daylight gradient.
local function fill(card, names, first, n, width, ranked)
    local W, C = DUI.Widgets, DUI.Widgets.COLORS
    local cols = columns(width)
    local colW = (width - 2 * LIST_PAD) / cols
    for i = 1, n do
        local line = card.lines[i]
        if not line then
            line = CreateFrame("Frame", nil, card)
            line:SetHeight(LINE)
            if ranked == "monthly" then
                line.heart = line:CreateTexture(nil, "ARTWORK")
                line.heart:SetTexture(HEART)
                line.heart:SetSize(HEART_PX, HEART_PX)
                line.heart:SetPoint("CENTER", line, "LEFT", 8, 0)
                line.mark = CreateFrame("Frame", nil, line) -- the name's anchor, so the heart grows in place
                line.mark:SetSize(16, 1)
                line.mark:SetPoint("LEFT", line, "LEFT", 0, 0)
            elseif ranked then
                line.rank = W.Font(line, W.BODY, SIZE.small, C.dim, "RIGHT")
                line.rank:SetPoint("LEFT", line, "LEFT", 0, 0)
                line.rank:SetWidth(24)
            else
                line.dot = line:CreateTexture(nil, "ARTWORK")
                line.dot:SetTexture(WHITE)
                line.dot:SetSize(5, 5)
                line.dot:SetRotation(math.pi / 4)
                line.dot:SetPoint("LEFT", line, "LEFT", 2, 0)
            end
            line.text = W.Font(line, W.BODY, SIZE.body, ranked and C.value or C.text)
            line.text:SetPoint("LEFT", line.rank or line.mark or line.dot, "RIGHT", line.mark and 6 or 10, 0)
            line.text:SetPoint("RIGHT", line, "RIGHT", -8, 0)
            line.text:SetWordWrap(false)
            line.text.english = true -- names aren't translated
            card.lines[i] = line
        end
        if ranked == "monthly" then
            W.TintDaylight(line.heart)
        elseif ranked then
            line.rank:SetText(DUI.GradientText("#" .. (first + i - 1))) -- same as the podium's
        else
            -- Each diamond at its spot along the sweep, first to last.
            line.dot:SetVertexColor(Style.SweepAt(n > 1 and (i - 1) / (n - 1) or 0))
        end
        if ranked == "monthly" then
            line.text:SetText(DUI.GradientText(names[first + i - 1]))
        else
            line.text:SetText(names[first + i - 1])
        end
        local col, at = (i - 1) % cols, math.floor((i - 1) / cols)
        line:SetWidth(colW)
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", card, "TOPLEFT", LIST_PAD + col * colW, -40 - at * LINE)
        line:Show()
    end
    for i = n + 1, #card.lines do card.lines[i]:Hide() end
end

local function update(row)
    local W = DUI.Widgets
    local names = Donators.LIST

    row.title:SetText(DUI.GradientText(L["Top Donators"]))
    W.TintDaylight(row.dot)
    for _, r in ipairs(row.rules) do
        -- The left rule in the gradient's blue end and the right in its pink, each
        -- fading out toward the outside.
        local c = Style.GRADIENT_SHAPE[r.side < 0 and 1 or 2]
        r:SetVertexColor(1, 1, 1, 1)
        if r.SetGradient and CreateColor then
            local inner, outer = CreateColor(c[1], c[2], c[3], 0.5), CreateColor(c[1], c[2], c[3], 0)
            if r.side < 0 then r:SetGradient("HORIZONTAL", outer, inner) else r:SetGradient("HORIZONTAL", inner, outer) end
        end
    end

    for place, c in pairs(row.cards) do
        local name = names[place]
        c:SetShown(name ~= nil)
        c.rank:SetText(DUI.GradientText("#" .. place))
        if place == 1 and name then c.name:SetText(DUI.GradientText(name)) else c.name:SetText(name or "") end
        W.TintDaylight(c.edge, place == 1 and 0.9 or 0.4)
        W.TintDaylight(c.top, place == 1 and 1 or 0.6)
    end
    if not DUI.Motion.On() then stillLight(row) end

    local width = rowWidth(row)
    local top = #names > 0 and TOP_LIST or TOP_PODIUM

    -- Monthly supporters first, under the podium, their card lit all around like
    -- first place's.
    local monthly = Donators.MONTHLY
    row.monthly:SetShown(#monthly > 0)
    if #monthly > 0 then
        placeCard(row.monthly, row, top, width, #monthly)
        row.monthly.head:SetText(DUI.GradientText(string.upper(L["Monthly supporters"])))
        W.TintDaylight(row.monthly.edge, 0.9)
        fill(row.monthly, monthly, 1, #monthly, width, "monthly")
        top = top + monthlyHeight(width)
    end
    local showTop = #names == 0 or topCount() > 0
    local last = #monthly > 0 and row.monthly or nil
    row.list:SetShown(showTop)
    if showTop then
        placeCard(row.list, row, top, width, topCount())
        row.list.head:SetText(DUI.GradientText(string.upper(L["Top 10"])))
        row.list.empty:SetShown(#names == 0)
        fill(row.list, names, 4, topCount(), width, true)
        last = row.list
    end
    row.rest:SetShown(restCount() > 0)
    if restCount() > 0 then
        local at = showTop and (top + cardHeight(topCount(), width) + LIST_GAP) or top
        placeCard(row.rest, row, at, width, restCount())
        row.rest.head:SetText(DUI.GradientText(string.upper(L["Also supporting"])))
        fill(row.rest, names, TOP_N + 1, restCount(), width, false)
        last = row.rest
    end

    row.footer:ClearAllPoints()
    if last then
        row.footer:SetPoint("TOP", last, "BOTTOM", 0, -22)
    else
        row.footer:SetPoint("TOP", row, "TOP", 0, -(top + 22))
    end
    row.kofi:ClearAllPoints()
    row.kofi:SetPoint("TOP", row.footer, "BOTTOM", 0, -12)
end

local page = {
    type = "custom", label = "",
    build = build,
    update = update,
    height = function(row)
        local top = #Donators.LIST > 0 and TOP_LIST or TOP_PODIUM
        return top + listHeight(rowWidth(row)) + 22 + 14 + 12 + 26 + 16
    end,
}

DUI.Options.RegisterPage({
    id = DUI.OptionsPanel.DONATORS, section = "core", label = "Top Donators", scope = "general",
    defaults = DUI.DB.GENERAL_DEFAULTS, order = 950,
    desc = "The players who keep DaylightUI going. Thank you.",
    groups = {
        { label = "", bare = true, items = { page } },
    },
})
