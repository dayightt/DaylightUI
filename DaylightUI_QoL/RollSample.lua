-- Sample loot rolls: three made-up loot roll popups where the game's show, with
-- counts and button tooltips drawn by the same code as on real ones
-- (RollTally.lua), so the counts can be seen without a group. Up while test
-- mode shows its "Loot rolls" part, while frames are unlocked, or while
-- /dui rolls or the options' Preview button has them on. Their buttons never
-- roll: nothing here calls the game's roll functions.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style, W = DUI.Style, DUI.Widgets
local Rolls, RollData = ns.RollTally, ns.RollData

local Sample = {
    TEST_PART = "lootrolls",
    MOVER = "game.GroupLootContainer",   -- the "Loot Rolls" handle
    NAME = "DaylightUIRollSample",       -- <NAME>1..3, their buttons <NAME>1Need...
    W = 277, H = 67,                     -- a popup's size, as the game's
    PAD = 10, ICON = 36, LINE = 2, BUTTON = 26, GAP = 4, STACK = 6,
    -- Right to left, as the loot roll skin lines them up.
    BUTTONS = {
        { kind = "pass", name = "Pass", art = "Interface\\Buttons\\UI-GroupLoot-Pass" },
        { kind = "greed", name = "Greed", art = "Interface\\Buttons\\UI-GroupLoot-Coin" },
        { kind = "need", name = "Need", art = "Interface\\Buttons\\UI-GroupLoot-Dice" },
    },
    -- A busy epic with a winner, Off-spec Need and players yet to pick; a rare
    -- of mostly Greed and Pass; and one with no roll data yet.
    ROLLS = {
        { name = L["Cloak of the Sleeping Wyrm"], quality = 4, icon = "Interface\\Icons\\INV_Misc_Cape_18", timer = 0.7, rows = {
            { name = "Brannoc", class = "WARRIOR", choice = "need", roll = 87, winner = true },
            { name = "Corvina", class = "PALADIN", choice = "offspec", roll = 64 },
            { name = "Isolde", class = "PRIEST", choice = "need", roll = 41, isSelf = true },
            { name = "Dusk", class = "ROGUE", choice = "greed", roll = 73 },
            { name = "Fenwick", class = "MAGE", choice = "pass" },
            { name = "Garrow", class = "HUNTER", choice = "undecided" },
            { name = "Aelwyn", class = "DRUID", choice = "undecided" },
        } },
        { name = L["Bracers of the Tidecaller"], quality = 3, icon = "Interface\\Icons\\INV_Bracer_07", timer = 0.45, rows = {
            { name = "Jory", class = "SHAMAN", choice = "greed", roll = 58 },
            { name = "Kessa", class = "WARLOCK", choice = "greed", roll = 33 },
            { name = "Merrow", class = "HUNTER", choice = "greed", roll = 12 },
            { name = "Dusk", class = "ROGUE", choice = "need", roll = 22 },
            { name = "Corvina", class = "PALADIN", choice = "pass" },
            { name = "Fenwick", class = "MAGE", choice = "pass" },
            { name = "Isolde", class = "PRIEST", choice = "pass", isSelf = true },
        } },
        { name = L["Signet of the Fallen"], quality = 3, icon = "Interface\\Icons\\INV_Jewelry_Ring_15", timer = 0.9 },
    },
}
ns.RollSample = Sample
ns.features[#ns.features + 1] = Sample

local samples                                         -- { frame, spec, buttons = kind -> button, bar, tally }, once made
local placeOf = setmetatable({}, { __mode = "k" })    -- sample button -> { sample, kind }
local toggled = false                                 -- /dui rolls or the Preview button
local wired

-- A button's own line (the choice's word), then the Tally, as on a real popup.
local function enter(b)
    local at, tip = placeOf[b], GameTooltip
    if not tip then return end
    local c = Style.INK.TITLE
    tip:SetOwner(b, "ANCHOR_RIGHT")
    tip:SetText(_G[Rolls.WORDS[at.kind]], c[1], c[2], c[3])
    Rolls.AddLines(tip, at.kind, at.sample.tally)
    tip:Show()
end

local function leave(b)
    local tip = GameTooltip
    if tip and tip:IsOwned(b) then tip:Hide() end
end

local function make(i, spec)
    local P = Sample.PAD
    local f = CreateFrame("Frame", Sample.NAME .. i, UIParent)
    f:SetSize(Sample.W, Sample.H)
    f:SetFrameStrata("DIALOG")
    f:Hide()
    Style.Shell(f, { window = true })
    local s = { frame = f, spec = spec, buttons = {} }
    local r, g, b = DUI.Win.Parts.QualityColor(spec.quality)

    -- The quality line on top, inside the border.
    local line = f:CreateTexture(nil, "OVERLAY")
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    line:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    line:SetHeight(Sample.LINE)
    DUI.Gradients.PaintPair(line, DUI.Gradients.PairFrom({ r, g, b }))

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(Sample.ICON, Sample.ICON)
    icon:SetPoint("TOPLEFT", f, "TOPLEFT", P, -P)
    icon:SetTexture(spec.icon)
    Style.CropIcon(icon)

    local right
    for _, def in ipairs(Sample.BUTTONS) do
        local btn = CreateFrame("Button", f:GetName() .. def.name, f)
        btn:SetSize(Sample.BUTTON, Sample.BUTTON)
        btn:SetNormalTexture(def.art .. "-Up")
        btn:SetPushedTexture(def.art .. "-Down")
        if right then
            btn:SetPoint("RIGHT", right, "LEFT", -Sample.GAP, 0)
        else
            btn:SetPoint("RIGHT", f, "RIGHT", -P, 3)
        end
        btn:SetScript("OnEnter", enter)
        btn:SetScript("OnLeave", leave)
        placeOf[btn] = { sample = s, kind = def.kind }
        s.buttons[def.kind] = btn
        right = btn
    end

    local name = Style.Text(f, Style.SIZE.body, "LEFT")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", P, -1)
    name:SetPoint("RIGHT", s.buttons.need, "LEFT", -P, 0)
    name:SetWordWrap(false)
    name:SetTextColor(r, g, b)
    name:SetText(spec.name)

    s.bar = W.Bar(f, W.BAR_H)
    s.bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", P, P)
    s.bar:SetPoint("RIGHT", f, "RIGHT", -P, 0)
    s.bar:SetValue(spec.timer)
    return s
end

-- Stacked up from the "Loot Rolls" spot at its size, the epic at the bottom.
local function place()
    local e = DUI.Movers.Get(Sample.MOVER)
    local at = e and e.frame or _G.GroupLootContainer or UIParent
    local scale = DUI.Movers.Scale(Sample.MOVER)
    for i, s in ipairs(samples) do
        s.frame:SetScale(scale)
        s.frame:ClearAllPoints()
        if i == 1 then
            s.frame:SetPoint("BOTTOM", at, "BOTTOM", 0, 0)
        else
            s.frame:SetPoint("BOTTOM", samples[i - 1].frame, "TOP", 0, Sample.STACK)
        end
    end
end

-- Counts, the timer's accent and an open tooltip, from the settings and look now.
local function paint(s)
    s.tally = s.spec.rows and RollData.Tally(s.spec.rows) or nil
    Rolls.PaintCounts(s.buttons, s.tally)
    W.BarAccent(s.bar)
    for _, b in pairs(s.buttons) do
        if GameTooltip and GameTooltip:IsOwned(b) then enter(b) end
    end
end

local function wanted()
    if not Rolls.Active() then return false end
    if toggled then return true end
    if DUI.testMode and DUI.TestPartShown(Sample.TEST_PART) then return true end
    return DUI.Movers.unlocked == true
end

function Sample.Update()
    if not wanted() then
        for _, s in ipairs(samples or {}) do
            for _, b in pairs(s.buttons) do leave(b) end
            s.frame:Hide()
        end
        return
    end
    if not samples then
        samples = {}
        for i, spec in ipairs(Sample.ROLLS) do samples[i] = make(i, spec) end
    end
    place()
    for _, s in ipairs(samples) do
        paint(s)
        s.frame:Show()
    end
end

-- /dui rolls and the Preview button: on until asked again.
function Sample.Toggle()
    toggled = not toggled
    Sample.Update()
end

function Sample.Enable()
    if wired then return end
    wired = true
    DUI.RegisterTestPart(Sample.TEST_PART, "Loot rolls", 98, Rolls.Active)
    DUI.On("TestModeChanged", Sample.Update)
    DUI.On("TestPartChanged", function(key) if key == Sample.TEST_PART then Sample.Update() end end)
    DUI.On("UnlockChanged", Sample.Update)
    DUI.On("StyleChanged", Sample.Update)
    DUI.RegisterCommand("rolls", Sample.Toggle, L["/dui rolls - show or hide sample loot rolls"])
end

Sample.Refresh = Sample.Update
