-- The Home page at the options window's narrowest: the support buttons stay
-- clear of the title, and the shared profiles card grows to hold its text.
local stub = require("stub")

local function home()
    local DUI = stub.Load({ module = true })
    DUI.OptionsPanel.Show("home")
    return DUI, DUI.OptionsPanel
end

local function profilesRow(pf)
    for _, card in ipairs(pf.cards) do
        for _, row in ipairs(card.rows) do
            if row.browse then return row end
        end
    end
end

-- 7 px per letter, wrapped to the text's width, 14 px per line.
local function measure(fs)
    local text = (fs.__text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local w = #text * 7
    local box = fs:GetWidth()
    local lines = (box and box > 0) and math.max(1, math.ceil(w / box)) or 1
    return math.min(w, box and box > 0 and box or w), lines * 14
end

T.test("home header: the support buttons have a row of their own under the description, at any width", function()
    local DUI, P = home()
    local h = P.Header()
    T.eq(P.MIN[1], 860, "the window's least width stays")
    T.truthy(h.vip:IsShown() and h.tip:IsShown() and h.donators:IsShown(), "all three, none hidden")
    local _, to, rel, x, y = h.vip:GetPoint(1)
    T.eq(to, h); T.eq(rel, "TOPLEFT"); T.eq(x, 0, "from the left edge")
    T.truthy(-y >= P.SUPPORT_H + 4, "below the title row and Reset page")
    T.eq(select(2, h.tip:GetPoint(1)), h.vip); T.eq(select(2, h.donators:GetPoint(1)), h.tip)
    local home = h:GetHeight()
    T.truthy(P.HeaderExtra() > 0)
    -- Narrow or wide, it stays put.
    for _, w in ipairs({ 560, 1400 }) do
        h:SetWidth(w)
        P.Frame():GetScript("OnSizeChanged")(P.Frame())
        T.eq(select(5, h.vip:GetPoint(1)), y, w .. " px: same row")
    end
    -- Another page: no row, and the header back to its own height.
    DUI.OptionsPanel.Show("appearance")
    T.falsy(h.vip:IsShown())
    T.eq(P.HeaderExtra(), 0)
    T.eq(h:GetHeight(), P.HEADER - P.TOP, "the header's usual height")
    T.truthy(home > h:GetHeight(), "Home's was taller")
end)

T.test("shared profiles card: as tall as its text once a narrow window wraps it", function()
    local DUI, P = home()
    local row = profilesRow(P.PageFrame())
    T.truthy(row, "the card is on Home")
    stub.measure = measure
    row:SetWidth(900)
    row.Measure()
    T.eq(row:GetHeight(), DUI.Options.HOME_PROFILES_H, "wide: the usual height")
    row:SetWidth(520)
    row.Measure()
    local narrow = row:GetHeight()
    T.truthy(narrow > DUI.Options.HOME_PROFILES_H, "narrow: taller, got " .. narrow)
    T.truthy(row.text:GetWidth() < 520 - row.browse:GetWidth(), "wraps beside the button")
    stub.measure = nil
end)

T.test("section rail: its scroll bar sits past the rail's edge, clear of the current section's band", function()
    local _, P = home()
    local nav = P.Nav()
    local bar = nav.railScroll.bar
    T.eq(bar:GetParent(), P.Frame(), "drawn on the window, over the page list's margin")
    local p, to, rel, x = bar:GetPoint(1)
    T.eq(p, "TOPLEFT"); T.eq(to, nav.railScroll); T.eq(rel, "TOPRIGHT")
    T.truthy(x >= 0, "outside the rail")
    T.truthy(x + bar:GetWidth() < 8, "before the page highlights start")
    T.truthy(bar:GetFrameLevel() > nav.list:GetFrameLevel(), "above the page list")
end)
