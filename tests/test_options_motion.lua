-- The options window, setup guide and unlock mode ease what changes in view:
-- rows dimming, the reset arrow, chips filling, sliders sliding, menus
-- dropping open, unlock handles fading and a put-back frame gliding home.
local stub = require("stub")

local function settle(dt)
    local d = DaylightUI.Motion.Driver()
    if d then stub.RunOnUpdate(d, dt or 1) end
end

local function open(id)
    local DUI = stub.Load({ module = true })
    DUI.OptionsPanel.Show(id)
    return DUI, DUI.OptionsPanel.PageFrame()
end

local function rowFor(pf, key)
    for _, card in ipairs(pf.cards) do
        for _, row in ipairs(card.rows) do
            if row.item.key == key then return row, card end
        end
    end
end

T.test("options motion: a row a switch turns off dims in view, FAST", function()
    local DUI, pf = open("UnitFrames.target")
    local others, card = rowFor(pf, "targetAuras.maxOtherDebuffs")
    if card.tab then DUI.OptionsPanel.SetTab(card.tab) end
    T.truthy(others:IsVisible(), "in view")
    T.eq(others:GetAlpha(), 1)
    DUI:Set("UnitFrames", "targetAuras.debuffFilter", "mine")
    T.truthy(others.disabled)
    settle(0.03)
    T.truthy(others:GetAlpha() < 1 and others:GetAlpha() > 0.35, "on its way")
    settle(1)
    T.eq(others:GetAlpha(), 0.35)
end)

T.test("options motion: the reset arrow fades in once changed, out once back", function()
    local DUI, pf = open("UnitFrames.player")
    local row = rowFor(pf, "player.width")
    T.falsy(row.reset:IsShown(), "first fill: hidden at once")
    DUI.Options.Set(row.page, row.item, row.item.min)
    T.truthy(row.reset:IsShown())
    T.truthy(row.reset:GetAlpha() < 1, "fading in")
    settle(1)
    T.eq(row.reset:GetAlpha(), 1)
    DUI.Options.ResetItem(row.page, row.item)
    settle(1)
    T.falsy(row.reset:IsShown(), "gone once faded")
end)

T.test("options motion: a typed slider value slides the knob there, the box rolling along", function()
    local DUI, pf = open("appearance")
    local row = rowFor(pf, "softness")
    local s, box = row.control.slider, row.control.box
    local before = s:GetValue()
    box:SetText("80 %")
    box:GetScript("OnEnterPressed")(box)
    T.eq(DUI:Get("general", "softness"), 0.8)
    settle(0.03)
    local mid = s:GetValue()
    T.truthy(mid > before and mid < 0.8, "partway")
    settle(1)
    T.eq(s:GetValue(), 0.8)
    T.eq(box:GetText(), "80%")
end)

T.test("options motion: a chip's accent fill floods in as it's picked", function()
    local DUI = stub.Load({ module = true })
    DUI.OptionsPanel.Show("UnitFrames.colors")
    local chips = DUI.OptionsPanel.Chips()
    T.truthy(chips:IsVisible())
    local b = chips.buttons[3]
    b:Click()
    T.truthy(b.on)
    T.truthy(b.fill < 1, "filling")
    settle(1)
    T.eq(b.fill, 1)
    T.eq(chips.buttons[1].fill, 0, "All let go")
    -- The fill rides in its tint, never SetAlpha: in game SetAlpha replaces
    -- a texture's tint alpha, and an off chip stayed filled.
    local function a(t) return select(4, t:GetVertexColor()) end
    T.eq(a(b.bg), 0.9, "picked: filled")
    T.eq(a(chips.buttons[1].bg), 0, "let go: empty")
    T.eq(b.bg.__alpha, nil, "no SetAlpha on the fill")
end)

T.test("options motion: the picked page's wash stays a 5% wash, faded in its tint", function()
    local DUI = stub.Load({ module = true })
    DUI.OptionsPanel.Show("general.appearance")
    settle(1)
    local picked
    local function walk(f)
        if type(f) ~= "table" or picked then return end
        if f.page and f.bg and f.bar and f.on then picked = f; return end
        for _, c in ipairs({ f:GetChildren() }) do walk(c) end
    end
    walk(UIParent)
    T.truthy(picked, "a picked page row")
    T.eq(select(4, picked.bg:GetVertexColor()), DUI.OptionsNav.WASH, "a wash, not solid white")
    T.eq(picked.bg.__alpha, nil, "no SetAlpha on the wash")
end)

T.test("options motion: unlock handles fade in together and out on Lock; a fight locks them at once", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(40, 20)
    DUI.Movers.Register(f, "probe", "Probe", { "CENTER", UIParent, "CENTER", 0, 0 })
    DUI.Movers.Unlock()
    local h = DUI.Movers.Handle("probe")
    T.truthy(h:IsShown())
    T.eq(h:GetAlpha(), 0, "from clear")
    settle(1)
    T.eq(h:GetAlpha(), 1)
    DUI.Movers.Lock()
    T.truthy(h:IsShown(), "fading out")
    settle(1)
    T.falsy(h:IsShown())
    T.eq(h:GetAlpha(), 1, "ready for next time")
    DUI.Movers.Unlock()
    settle(1)
    stub.combat = true
    DUI.Movers.Lock()
    T.falsy(h:IsShown(), "in a fight: at once")
    stub.combat = false
end)

T.test("options motion: Home's banner plays a sunrise: lines, then the sun from behind the horizon, then the words", function()
    local DUI, pf = open("home")
    local row = pf.cards[1].rows[1]
    local sr = row.sunrise
    T.truthy(sr and sr.pieces, "the banner in pieces")
    local O = DUI.Options
    T.eq(sr.pieces.title:GetAlpha(), 0, "never the finished banner first")
    row:Hide(); row:Show()   -- comes into view: the sunrise starts over
    T.eq(sr.pieces.title:GetAlpha(), 0, "from its first frame at once")
    stub.RunTimers()         -- it runs from the next frame
    local function sunTop()
        local _, _, _, _, y = sr.pieces.sun:GetPoint(1)
        return y
    end
    local low = sunTop()
    T.eq(sr.pieces.title:GetAlpha(), 0, "the title waits")
    settle(O.SUNRISE.title)
    T.truthy(sunTop() > low, "the sun has risen")
    T.truthy(sr.pieces.line1:GetAlpha() > 0.9, "the lines are in")
    settle(3)
    T.eq(sr.pieces.title:GetAlpha(), 1)
    T.eq(sr.pieces.tagline:GetAlpha(), 1)
    T.truthy(math.abs(sr.pieces.glow:GetAlpha() - O.SUNRISE_GLOW[2]) < 0.01, "the glow rests")
end)
