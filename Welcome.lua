-- Welcome to Daylight UI 2.0: shown once per account to players who had
-- Daylight UI before, in the setup guide's window. The first slide is the
-- sunrise banner with what's new; then one slide per new look (portraits,
-- tooltips, Proc Alerts) where both are drawn side by side and the player
-- picks one, and a slide showing the new bar animations moving, with where to
-- pick them. A player who saw it before gets only the slides added since.
-- Nothing is written until Finish; closing it early asks again next login.
-- A brand-new account never sees it: the setup guide asks the same things.
--
-- Saved: DB.Root().welcome = the version seen (Welcome.VERSION).
-- /dui welcome opens it any time, /dui whatsnew only the newest slides.

local _, DUI = ...
local L = DUI.L
local W = DUI.Widgets
local Style = DUI.Style
local SIZE = Style.SIZE
local C = W.COLORS

local Welcome = {}
DUI.Welcome = Welcome

Welcome.VERSION = 4
Welcome.LOGIN_DELAY = 2  -- after the plugins' guides look (1 s), before the portrait question would (3 s)
Welcome.WAIT = 5         -- while the guide's window is busy, look again this often
Welcome.TRIES = 24       -- for about two minutes
-- The window, and the news slide's layout (from the approved mock-up).
Welcome.WIDTH, Welcome.HEIGHT = DUI.InstallerUI.SHOW_W, DUI.InstallerUI.SHOW_H
Welcome.TITLE_SIZE = 28    -- a showpiece's title
Welcome.TITLE_TOP = 22     -- under the banner's plaque
Welcome.INTRO_GAP = 20
Welcome.RULE_W, Welcome.RULE_GAP = 150, 24
Welcome.PLAQUE_W, Welcome.PLAQUE_H, Welcome.PLAQUE_SLANT = 190, 26, 8
Welcome.MARGIN, Welcome.GAP = 26, 11
Welcome.FEATURE_W = 270
Welcome.ROW_H, Welcome.WIDE_H = 84, 62
Welcome.TILE, Welcome.ICON = 38, 22
Welcome.FEATURE_TILE, Welcome.FEATURE_ICON, Welcome.FEATURE_TOP = 76, 42, 26
Welcome.FEATURE_WASH = 0.16
Welcome.FEATURE_TEXT = 176  -- the words' top, down from the tall card's top
Welcome.COIN = 16
Welcome.TILE_FILL, Welcome.TILE_EDGE = 0.14, 0.45
Welcome.GO_W, Welcome.GO_H, Welcome.GO_GAP = 268, 44, 22
Welcome.DOT, Welcome.DOT_ON, Welcome.DOT_GAP, Welcome.DOTS_GAP, Welcome.DOT_HUE = 8, 18, 10, 18, 0.62
Welcome.LIFT = 10          -- how far each piece lifts in
Welcome.STAGGER = 0.1      -- between one card and the next
Welcome.AFTER_SUN = 0.3    -- the words wait this long for the sunrise to start

-- The slides after the news: one per new look (InstallerLooks.KINDS), or a
-- slide that only shows something (Welcome.SHOWS).
Welcome.CHOICES = { "portraitLook", "tooltipStyle", "plateClassIcon", "procAlerts", "barFx" }
-- A slide added after the 2.0 welcome: the version it came with. A player who
-- saw an earlier one gets only these, without the news.
Welcome.SINCE = { procAlerts = 3, barFx = 4 }

-- The bar animations new since the last welcome, in the order shown, each
-- with a line about it. One that isn't in this build is left out.
Welcome.BAR_STYLES = {
    { key = "daybreak", text = "A soft crescent of light rides the end of the bar." },
    { key = "pixelsparks", text = "Pixel-art sparks fly off the end of the bar." },
    { key = "pixelblaze", text = "Pixel-art flames burn at the end of the bar." },
    { key = "pixelarc", text = "A crackling arc of pixel light at the end of the bar." },
    { key = "slosh", text = "Water sloshes inside the bar." },
    { key = "molten", text = "Soft lava glows inside the bar." },
    { key = "cinders", text = "Soft embers drift inside the bar." },
}
Welcome.BAR_CARD_H = 92   -- a style's card: its name, its line and the bar
Welcome.BAR_H = 20        -- the sample bar, as tall as a player frame's health
Welcome.BAR_PAD = 14

function Welcome.BarStyles()
    local out, defs = {}, DUI.BarFx and DUI.BarFx.DEFS or {}
    for _, s in ipairs(Welcome.BAR_STYLES) do
        if defs[s.key] then out[#out + 1] = s.key end
    end
    return out
end

-- The player frame's options page, where Bar animation sits.
local function barFxPage()
    local page = DUI.InstallerPages.Find("UnitFrames", "player.barFx.health.style")
    return page and page.id or nil
end

-- Slides that only show something: nothing to pick, Next is there at once.
Welcome.SHOWS = {
    barFx = {
        title = "New bar animations", rail = "Bar animations",
        desc = "Here is each one, in your accent color. Pick one for any bar on a unit frame's page, Bars tab, under Bar animation.",
        available = function()
            return DUI.BarFx ~= nil and DUI:GetModule("UnitFrames") ~= nil and #Welcome.BarStyles() > 0
                and barFxPage() ~= nil
        end,
        -- On every unit frame's page, on its Bars tab; the link opens the
        -- player frame's.
        later = barFxPage, laterKey = "player.barFx.health.style",
        laterSay = "Find them in /dui > Unit Frames > any frame > Bars tab",
    },
}

local function available(kind)
    local show = Welcome.SHOWS[kind]
    if not show then return DUI.InstallerLooks.Available(kind) end
    local on = false
    DUI.SafeCall(function() on = show.available() == true end)
    return on
end

-- Whether a slide waits for a pick before Next.
local function needsPick(kind) return kind ~= "news" and not Welcome.SHOWS[kind] end

-- What's new: the first one is the tall card. go = a choice slide the card
-- opens; hue = its icon's spot along the Daylight sweep.
Welcome.NEWS = {
    { icon = "ui-section-auction.png", title = "Auction House", hue = 0.5,
      text = "A whole new Auction House: buy, sell and track your auctions, with prices on every item's tooltip." },
    { icon = "ui-section-frames.png", title = "Portraits", go = "portraitLook", hue = 0.55,
      text = "Portraits can sit in their frame, with the border running around both as one piece." },
    { icon = "ui-section-tooltip.png", title = "Rich tooltips", go = "tooltipStyle", hue = 0.12,
      text = "Daylight UI's own tooltip cards: the name and tags up top, every number in tidy rows." },
    { icon = "ui-data-bags.png", title = "Loot rolls", hue = 0.68,
      text = "See who picked Need, Greed or Pass, everyone's roll and who won." },
    { icon = "ui-section-cooldowns.png", title = "Cooldown Manager", hue = 0.2,
      text = "Rebuilt from the ground up: fewer missing spells, and glows that stay right in a fight." },
    { icon = "ui-section-plates.png", title = "Nameplates", go = "plateClassIcon", hue = 0.45,
      text = "Class icons on friendly players, power numbers on the bar, and short names that fit." },
}

local run -- the welcome showing now

function Welcome.Running() return run ~= nil end
function Welcome.Slide() return run and run.slides[run.at] end
function Welcome.Page() return run and run.pages[run.at] end

local function seen() return tonumber(DUI.DB.Root().welcome) or 0 end

-- The slides: the news, then each look that can show. After an earlier
-- welcome (seen), only the looks added since; all of them for /dui welcome.
local function slides(after)
    local out = {}
    if not after or after < 2 then
        out[1] = "news"
        after = 0
    end
    for _, kind in ipairs(Welcome.CHOICES) do
        if (Welcome.SINCE[kind] or 2) > after and available(kind) then out[#out + 1] = kind end
    end
    return out
end
Welcome.Slides = slides

-- Due on an account that had Daylight UI before, on a character that's set up.
function Welcome.Due()
    local DB = DUI.DB
    local root = DB.Root()
    local was = seen()
    if was >= Welcome.VERSION then return false end
    if DB.fresh then
        root.welcome = Welcome.VERSION
        return false
    end
    if DUI.Installer.State() ~= "installed" then return false end
    -- Nothing new that can show here (its module is off): nothing to ask.
    if #slides(was) == 0 then
        root.welcome = Welcome.VERSION
        return false
    end
    return true
end

function Welcome.MarkSeen()
    local root = DUI.DB.Root()
    root.welcome = Welcome.VERSION
    -- It asked the portrait question, so the module's own never comes.
    root.portraitLookAsked = true
end

local function nextText(i)
    return i == #run.slides and L["Finish"] or (NEXT or L["Next"])
end

-- The news slide: the banner's "Version 2.0" plaque, a big title between two
-- lines, then the Auction House as a tall card on the left beside the other
-- news, the Let's go button and a dot per slide. Everything comes in after
-- the sunrise, a piece at a time.

Welcome.Spaced = DUI.InstallerChrome.Spaced

local function hex(c) return DUI.Win.Parts.Hex(c) end

-- A spot along the Daylight sweep, as a color table.
local function sweep(t) return { Style.SweepAt(t) } end

-- A rounded tile with an icon in it, both in one color of the sweep.
local function iconTile(parent, file, size, iconSize, t)
    local c = sweep(t)
    local tile = CreateFrame("Frame", nil, parent)
    tile:SetSize(size, size)
    tile.bg = W.Round(tile, "BACKGROUND")
    tile.bg:SetAllPoints(tile)
    tile.bg:SetVertexColor(c[1], c[2], c[3], Welcome.TILE_FILL)
    tile.edge = W.Round(tile, "BORDER", 0, true)
    tile.edge:SetAllPoints(tile)
    tile.edge:SetVertexColor(c[1], c[2], c[3], Welcome.TILE_EDGE)
    tile.icon = W.Icon(tile, file, iconSize, C.text, "ARTWORK")
    tile.icon:SetPoint("CENTER", tile, "CENTER", 0, 0)
    tile.icon:SetVertexColor(c[1], c[2], c[3], 1)
    return tile
end

local function goTo(kind)
    for n, s in ipairs(run.slides) do
        if s == kind then return Welcome.Go(n) end
    end
end

-- One piece of news: its icon in a tile on the left, the name and a few words.
local function newsCard(parent, item)
    local c = DUI.InstallerCards.Card(parent)
    c.tile = iconTile(c.inner, item.icon, Welcome.TILE, Welcome.ICON, item.hue)
    c.tile:SetPoint("TOPLEFT", c.inner, "TOPLEFT", 14, -14)
    c.title = W.Font(c.inner, W.TITLE, SIZE.head, C.value)
    c.title:SetPoint("TOPLEFT", c.tile, "TOPRIGHT", 12, 0)
    c.title:SetText(L[item.title])
    c.text = DUI.InstallerCards.Text(c, L[item.text])
    c.text:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -5)
    c.text:SetPoint("BOTTOMRIGHT", c.inner, "BOTTOMRIGHT", -14, 6)
    if item.go then
        c:SetScript("OnClick", function() goTo(item.go) end)
        c.tooltip = { L[item.title], L["Click to see both looks and pick yours."] }
        c:HookScript("OnShow", function() c.SetTag(L["Pick yours"]) end)
        c.SetTag(L["Pick yours"])
    end
    return c
end

-- The Auction House: a tall card with its big lit tile and coins, the name
-- and words centered under them, its outline in the Daylight gradient and a
-- slow glow breathing round it.
local function featureCard(parent, item)
    local c = DUI.InstallerCards.Card(parent)
    c.wash = c.inner:CreateTexture(nil, "BACKGROUND", nil, 2)
    c.wash:SetTexture("Interface\\Buttons\\WHITE8X8")
    c.wash:SetPoint("TOPLEFT", c.inner, "TOPLEFT", 2, -2)
    c.wash:SetPoint("BOTTOMRIGHT", c.inner, "BOTTOMRIGHT", -2, 2)
    c.lit = W.Round(c.inner, "BORDER", 1, true)
    c.lit:SetAllPoints(c.inner)
    c.tile = iconTile(c.inner, item.icon, Welcome.FEATURE_TILE, Welcome.FEATURE_ICON, item.hue)
    c.tile:SetPoint("TOP", c.inner, "TOP", 0, -Welcome.FEATURE_TOP)
    c.coins = CreateFrame("Frame", nil, c.inner)
    c.coins:SetSize(3 * Welcome.COIN + 12, Welcome.COIN)
    c.coins:SetPoint("TOP", c.tile, "BOTTOM", 0, -10)
    for i, coin in ipairs({ "coin-gold.png", "coin-silver.png", "coin-copper.png" }) do
        local t = c.coins:CreateTexture(nil, "ARTWORK")
        t:SetTexture(DUI.MEDIA .. coin)
        t:SetSize(Welcome.COIN, Welcome.COIN)
        t:SetPoint("LEFT", c.coins, "LEFT", (i - 1) * (Welcome.COIN + 6), 0)
    end
    c.title = W.Font(c.inner, W.TITLE, SIZE.title, C.value, "CENTER")
    c.title:SetPoint("BOTTOM", c.inner, "TOP", 0, -(Welcome.FEATURE_TEXT - 10))
    c.title:SetText(L[item.title])
    c.text = W.Font(c.inner, W.BODY, SIZE.body, C.text, "CENTER")
    c.text:SetWordWrap(true)
    c.text:SetJustifyV("TOP")
    c.text:SetPoint("TOPLEFT", c.inner, "TOPLEFT", 18, -Welcome.FEATURE_TEXT)
    c.text:SetPoint("BOTTOMRIGHT", c.inner, "BOTTOMRIGHT", -18, 12)
    c.text:SetText(L[item.text])
    function c.Paint()
        local a = Style.GRADIENT_SHAPE[1]
        W.TintDaylight(c.lit, 0.9)
        W.TintDaylight(c.tile.icon)
        Style.Gradient(c.wash, "VERTICAL", a[1], a[2], a[3], Welcome.FEATURE_WASH, a[1], a[2], a[3], 0)
    end
    c:HookScript("OnShow", c.Paint)
    c.Paint()
    return c
end

local function rule(parent, width, toLeft) return DUI.InstallerChrome.Rule(parent, width, toLeft) end

-- What sits on the window itself while the news shows: the plaque on the
-- banner's lower edge with its lines.
local function buildChrome(page)
    local UI = DUI.InstallerUI
    local win = UI.Frame()
    local k = CreateFrame("Frame", nil, win)
    k:SetAllPoints(win)
    k:SetFrameLevel(win:GetFrameLevel() + 30)
    k:EnableMouse(false)
    local p = DUI.InstallerChrome.Plaque(k, Welcome.PLAQUE_H, Welcome.PLAQUE_SLANT, 24)
    p:SetWidth(Welcome.PLAQUE_W)
    p:SetPoint("CENTER", win, "TOP", 0, -(UI.BANNER_H - 8))
    k.plaque = p
    for i, toLeft in ipairs({ true, false }) do
        local line = k:CreateTexture(nil, "ARTWORK")
        line:SetTexture("Interface\\Buttons\\WHITE8X8")
        line:SetHeight(DUI.Pixel.Px(k, 1))
        if toLeft then
            line:SetPoint("RIGHT", p, "LEFT", 4, 0)
            line:SetPoint("LEFT", win, "LEFT", 12, 0)
        else
            line:SetPoint("LEFT", p, "RIGHT", -4, 0)
            line:SetPoint("RIGHT", win, "RIGHT", -12, 0)
        end
        k[i == 1 and "lineL" or "lineR"] = line
    end
    function k.Paint()
        local a, z = Style.GRADIENT_SHAPE[1], Style.GRADIENT_SHAPE[2]
        p.Paint()
        p.Set(hex(Style.INK.LABEL) .. Welcome.Spaced(L["Version"]) .. "|r   "
            .. hex(Style.INK.VALUE) .. Welcome.Spaced("2.0") .. "|r")
        if p:GetWidth() < Welcome.PLAQUE_W then p:SetWidth(Welcome.PLAQUE_W) end
        Style.Gradient(k.lineL, "HORIZONTAL", a[1], a[2], a[3], 0, a[1], a[2], a[3], 0.9)
        Style.Gradient(k.lineR, "HORIZONTAL", z[1], z[2], z[3], 0.9, z[1], z[2], z[3], 0)
    end
    k:Hide()
    -- It belongs to the news: it comes and goes with that page.
    page:HookScript("OnShow", function() k.Paint(); k:Show() end)
    page:HookScript("OnHide", function() k:Hide() end)
    return k
end

local function buildNews(parent, width)
    local M = DUI.Motion
    local page = CreateFrame("Frame", nil, parent)
    page:SetWidth(width)
    page.chrome = buildChrome(page)

    local y = Welcome.TITLE_TOP
    page.greet = W.Font(page, W.TITLE, Welcome.TITLE_SIZE, C.value, "CENTER")
    page.greet:SetPoint("TOP", page, "TOP", 0, -y)
    page.greet:SetText(string.format(L["Welcome to Daylight UI %s"], DUI.GradientText("2.0")))
    page.ruleL = rule(page, Welcome.RULE_W, true)
    page.ruleL:SetPoint("RIGHT", page.greet, "LEFT", -Welcome.RULE_GAP, 0)
    page.ruleR = rule(page, Welcome.RULE_W, false)
    page.ruleR:SetPoint("LEFT", page.greet, "RIGHT", Welcome.RULE_GAP, 0)
    y = y + Welcome.TITLE_SIZE + 10

    page.intro = W.Font(page, W.BODY, SIZE.small, C.dim, "CENTER")
    page.intro:SetPoint("TOP", page, "TOP", 0, -y)
    page.intro:SetText(Welcome.Spaced(L["The biggest update yet. Here's what's new."]))
    y = y + SIZE.small + Welcome.INTRO_GAP

    -- The Auction House on the left, as tall as the rest; two by two beside
    -- it, and the last one across the bottom.
    local m, gap = Welcome.MARGIN, Welcome.GAP
    local inner = width - 2 * m
    local fw = Welcome.FEATURE_W
    local cw = (inner - fw - 2 * gap) / 2
    local tall = 2 * Welcome.ROW_H + Welcome.WIDE_H + 2 * gap
    page.cards = {}
    for i, item in ipairs(Welcome.NEWS) do
        local c
        if i == 1 then
            c = featureCard(page, item)
            c:SetSize(fw, tall)
            c:SetPoint("TOPLEFT", page, "TOPLEFT", m, -y)
        else
            c = newsCard(page, item)
            local n = i - 2
            local x = m + fw + gap
            if n < 4 then
                local col, row = n % 2, math.floor(n / 2)
                c:SetSize(cw, Welcome.ROW_H)
                c:SetPoint("TOPLEFT", page, "TOPLEFT", x + col * (cw + gap), -(y + row * (Welcome.ROW_H + gap)))
            else
                c:SetSize(2 * cw + gap, Welcome.WIDE_H)
                c:SetPoint("TOPLEFT", page, "TOPLEFT", x, -(y + 2 * (Welcome.ROW_H + gap)))
            end
        end
        page.cards[i] = c
    end
    y = y + tall + Welcome.GO_GAP

    page.go = W.HeroButton(page, L["Let's go"], Welcome.GO_H)
    page.go:SetWidth(Welcome.GO_W)
    page.go.SetLabel(L["Let's go"])
    page.go:SetPoint("TOP", page, "TOP", 0, -y)
    page.go:SetScript("OnClick", function() Welcome.Next() end)
    y = y + Welcome.GO_H + Welcome.DOTS_GAP

    -- A dot per slide, this one long and lit.
    page.dots = CreateFrame("Frame", nil, page)
    page.dots:SetHeight(Welcome.DOT)
    page.dots:SetPoint("TOP", page, "TOP", 0, -y)
    page.dots.list = {}
    y = y + Welcome.DOT + 4
    page:SetHeight(y)

    function page.Dots()
        local list, total = page.dots.list, 0
        for i = 1, #run.slides do
            local d = list[i]
            if not d then
                d = page.dots:CreateTexture(nil, "ARTWORK")
                d:SetTexture(DUI.MEDIA .. "ui-round.png")
                list[i] = d
            end
            local on = i == 1
            local w = on and Welcome.DOT_ON or Welcome.DOT
            d:SetSize(w, Welcome.DOT)
            d:ClearAllPoints()
            d:SetPoint("LEFT", page.dots, "LEFT", total, 0)
            if on then
                local c = sweep(Welcome.DOT_HUE)
                d:SetVertexColor(c[1], c[2], c[3], 1)
            else
                W.Tint(d, C.track)
            end
            d:Show()
            total = total + w + Welcome.DOT_GAP
        end
        for i = #run.slides + 1, #list do list[i]:Hide() end
        page.dots:SetWidth(math.max(1, total - Welcome.DOT_GAP))
    end

    -- After the sunrise: the plaque and its lines, the title and its lines,
    -- the line under it, the Auction House, the other cards one by one, then
    -- the button, which a light runs across once it has landed.
    function page.Play()
        page.go.SetLabel(#run.slides > 1 and L["Let's go"] or (DONE or L["Done"]))
        page.Dots()
        -- Everything is hidden at once, then lifts in its turn at the slow
        -- speed, stepped by hand like the window kit's pages (smooth at any UI
        -- scale; animation groups moved in whole pixels and drew wrong here).
        local Feel = DUI.Win.Feel
        local t, slow, beat, k, lift = Welcome.AFTER_SUN, M.SLOW, M.FAST, page.chrome, Welcome.LIFT
        Feel.Piece(k.plaque, t, slow, lift / 2)
        Feel.Piece(k.lineL, t + beat, slow, 0)
        Feel.Piece(k.lineR, t + beat, slow, 0)
        t = t + beat
        Feel.Piece(page.greet, t, slow, lift)
        Feel.Piece(page.ruleL, t + beat, slow, 0)
        Feel.Piece(page.ruleR, t + beat, slow, 0)
        Feel.Piece(page.intro, t + 2 * beat, slow, lift / 2)
        t = t + 3 * beat
        for i, c in ipairs(page.cards) do
            Feel.Piece(c, t + (i - 1) * Welcome.STAGGER, slow, lift)
        end
        t = t + #page.cards * Welcome.STAGGER
        Feel.Piece(page.go, t, slow, lift)
        Feel.Piece(page.dots, t + beat, slow, 0)
        C_Timer.After(t + slow, function()
            if page:IsVisible() then page.go.Shine() end
        end)
    end
    -- The Auction House's glow breathes while the page is up.
    page:HookScript("OnShow", function()
        local c = page.cards[1]
        W.GlowAround(c, true, { frame = c.inner, style = "breathe",
            lo = Style.GRADIENT_SHAPE[1], hi = Style.GRADIENT_SHAPE[2] })
    end)
    page:HookScript("OnHide", function() W.GlowAround(page.cards[1], false) end)
    return page
end

-- A look's slide: both looks in their cards, and a line under them.

local function buildChoice(parent, width, kind)
    local page = CreateFrame("Frame", nil, parent)
    page:SetWidth(width)
    page.picker = DUI.InstallerLooks.Picker(page, kind, {
        width = width,
        get = function() return run and run.picks[kind] end,
        set = function(k)
            run.picks[kind] = k
            DUI.InstallerUI.SetNext(nextText(run.at))
        end,
    })
    -- In the middle of the room between the header and the footer.
    local UI = DUI.InstallerUI
    local room = Welcome.HEIGHT - (UI.TOP + UI.HEADER + 12) - UI.FOOTER
    local used = page.picker.height + 12 + 16
    page.picker:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -math.max(0, math.floor((room - used) / 2)))
    page.hint = W.Font(page, W.BODY, SIZE.small, C.dim, "CENTER")
    page.hint:SetPoint("TOPLEFT", page.picker, "BOTTOMLEFT", 0, -12)
    page.hint:SetPoint("TOPRIGHT", page.picker, "BOTTOMRIGHT", 0, -12)
    page.hint:SetText(L["Click the one you want. You can switch any time in the options."])
    page:SetHeight(math.max(used, room - 4))
    function page.Refresh() page.picker.Refresh() end
    function page.Play()
        page.picker.Play()
        DUI.Win.Feel.Piece(page.hint, DUI.Motion.SLOW, DUI.Motion.SLOW, 0)
    end
    return page
end

-- The bar animations slide: a card for each new style, two a row, its name,
-- a line about it and a sample health bar wearing it, moving, filled with the
-- player's own accent. The cards take no clicks: the picking is done on the
-- unit frames' pages.

local function buildBarFx(parent, width)
    local Cards, BarFx = DUI.InstallerCards, DUI.BarFx
    local page = CreateFrame("Frame", nil, parent)
    page:SetWidth(width)
    page.cards = {}
    local gap, pad = Cards.GAP, Welcome.BAR_PAD
    local cw = (width - gap) / 2
    local lines = {}
    for _, s in ipairs(Welcome.BAR_STYLES) do lines[s.key] = s.text end
    for i, key in ipairs(Welcome.BarStyles()) do
        local c = Cards.Card(page)
        c:EnableMouse(false)
        c:SetSize(cw, Welcome.BAR_CARD_H)
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        c:SetPoint("TOPLEFT", page, "TOPLEFT", col * (cw + gap), -row * (Welcome.BAR_CARD_H + gap))
        c.title = W.Font(c.inner, W.TITLE, SIZE.head, C.value)
        c.title:SetPoint("TOPLEFT", c.inner, "TOPLEFT", pad, -pad)
        local label = BarFx.STYLES[key]
        c.title:SetText(type(label) == "function" and label() or label)
        c.text = Cards.Text(c, L[lines[key]])
        c.text:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -4)
        c.text:SetPoint("RIGHT", c.inner, "RIGHT", -pad, 0)
        c.sample = BarFx.Sample(c.inner, { "health" }, { force = key, bare = true, height = Welcome.BAR_H })
        c.sample.frame:SetPoint("BOTTOMLEFT", c.inner, "BOTTOMLEFT", pad, pad)
        -- The accent instead of the health colors, read each time the slide
        -- shows: the player can change it any time.
        local holder = c.sample.bars[1]
        function holder.Paint()
            Style.PaintAccentBar(holder.bar)
            Style.AngleFill(holder.bar, "right", math.max(2, (holder:GetHeight() or 12) * 0.5))
        end
        holder:SetScript("OnSizeChanged", holder.Paint)
        c.sample.Refresh(cw - 2 * pad + 8)
        page.cards[i] = c
    end
    function page.Refresh()
        for _, c in ipairs(page.cards) do
            c.sample.bars[1].Paint()
            c.sample.Apply()
        end
    end
    local rows = math.ceil(#page.cards / 2)
    page:SetHeight(rows * Welcome.BAR_CARD_H + math.max(0, rows - 1) * gap)
    function page.Play()
        local M = DUI.Motion
        for i, c in ipairs(page.cards) do
            DUI.Win.Feel.Piece(c, i * Welcome.STAGGER, M.SLOW, Welcome.LIFT)
        end
    end
    return page
end

-- Moving between slides

function Welcome.Go(i)
    if not run then return end
    local UI, Looks = DUI.InstallerUI, DUI.InstallerLooks
    i = math.max(1, math.min(#run.slides, i))
    local dir = (run.at and i < run.at) and -1 or 1
    run.at = i
    run.visited[i] = true
    local kind = run.slides[i]
    local page = run.pages[i]
    if not page then
        if kind == "news" then
            page = buildNews(UI.Body(), UI.ContentWidth(false))
        elseif kind == "barFx" then
            page = buildBarFx(UI.Body(), UI.ContentWidth(true))
        else
            page = buildChoice(UI.Body(), UI.ContentWidth(true), kind)
        end
        page:Hide()
        run.pages[i] = page
    end
    if kind == "news" then
        UI.SetPage(page, { full = true, veil = true, still = true, dir = dir })
    else
        local show = Welcome.SHOWS[kind]
        local spec = show or Looks.KINDS[kind]
        -- A lone slide (only Proc Alerts are new) needs no "Step 1 of 1".
        local first = run.slides[1] == "news" and 1 or 0
        local total = #run.slides - first
        UI.SetPage(page, {
            dir = dir, rail = true, veil = true, still = true, step = total > 1 and i - first or nil, total = total,
            title = L[spec.title], desc = L[spec.desc], back = i > 1,
            later = show and show.later() or Looks.Later(kind),
            laterSay = show and L[show.laterSay] or nil, laterKey = show and show.laterKey or nil,
            next = (not needsPick(kind) or run.picks[kind] ~= nil) and nextText(i) or nil,
        })
        local steps = {}
        for n, s in ipairs(run.slides) do
            local k = Welcome.SHOWS[s] or Looks.KINDS[s]
            steps[n] = { id = n, label = s == "news" and L["What's new"] or L[k.rail or k.title] }
        end
        UI.SetRail(steps, i, run.visited, Welcome.Go)
    end
    if page.Refresh then page.Refresh() end
    if page.Play then page.Play() end
end

function Welcome.Back()
    if run and run.at and run.at > 1 then Welcome.Go(run.at - 1) end
end

function Welcome.Next()
    if not run then return end
    if run.at < #run.slides then
        local kind = run.slides[run.at]
        if needsPick(kind) and run.picks[kind] == nil then return end
        return Welcome.Go(run.at + 1)
    end
    Welcome.Finish()
end

-- Every look picked: written into the profile in use, seen for the account.
function Welcome.Finish()
    if not run then return end
    if InCombatLockdown() then
        DUI.AfterCombat(Welcome.Finish, "welcome")
        return
    end
    for n, kind in ipairs(run.slides) do
        if needsPick(kind) and run.picks[kind] == nil then return Welcome.Go(n) end
    end
    local picks = run.picks
    run = nil
    for kind, k in pairs(picks) do DUI.InstallerLooks.Apply(kind, k) end
    Welcome.MarkSeen()
    if DUI.Sound then DUI.Sound.Play("done") end
    DUI.InstallerUI.QuietHide()
end

-- X or Escape: nothing written, and it comes back at the next login.
function Welcome.OnClosed()
    run = nil
end

-- False when the guide's window is busy with something else. after = the
-- welcome this account saw, to show only what came since (at login); nil
-- shows every slide (/dui welcome).
function Welcome.Show(after)
    if run then return true end
    if InCombatLockdown() then
        DUI.AfterCombat(function() Welcome.Show(after) end, "welcome")
        return true
    end
    local UI = DUI.InstallerUI
    if UI.IsShown() then return false end
    local list = slides(after)
    if #list == 0 then return true end
    run = { slides = list, picks = {}, pages = {}, visited = {} }
    UI.Open({
        width = Welcome.WIDTH, height = Welcome.HEIGHT, lit = true,
        close = Welcome.OnClosed,
        next = Welcome.Next,
        back = Welcome.Back,
        again = function() if run and run.at then Welcome.Go(run.at) end end,
    })
    Welcome.Go(1)
    return true
end

local tries = 0
local function atLogin()
    if not Welcome.Due() then return end
    -- The welcome asks about portraits itself.
    DUI.DB.Root().portraitLookAsked = true
    if Welcome.Show(seen()) then return end
    tries = tries + 1
    if tries < Welcome.TRIES then C_Timer.After(Welcome.WAIT, atLogin) end
end

DUI.RegisterEvent("PLAYER_LOGIN", function()
    -- A first install is marked at once, so a short first session never
    -- leaves it due for the next.
    if DUI.DB.fresh then DUI.DB.Root().welcome = Welcome.VERSION end
    C_Timer.After(Welcome.LOGIN_DELAY, atLogin)
end)

DUI.RegisterCommand("welcome", function() Welcome.Show() end,
    function() return L["/dui welcome - what's new in Daylight UI 2.0, and the new looks and Proc Alerts to pick from"] end)
-- Only the slides this version's welcome added.
DUI.RegisterCommand("whatsnew", function() Welcome.Show(Welcome.VERSION - 1) end,
    function() return L["/dui whatsnew - the newest slides of the welcome, like the new bar animations"] end)
