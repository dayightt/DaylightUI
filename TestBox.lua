-- While /dui test is on, a small box at the top of the screen has a checkbox
-- per sample part (target, party, buffs...) so a part in the way can be
-- hidden. Modules register their own parts and check DUI.TestPartShown(key)
-- before showing a sample. Choices are account-wide (DaylightUIDB.testHidden)
-- and survive reloads.

local _, DUI = ...

local TestBox = {}
DUI.TestBox = TestBox

TestBox.parts = {}   -- { key, label, order, available }
TestBox.rows = {}
TestBox.COLUMNS = 5
TestBox.COL_W = 124
TestBox.ROW_H = 22
TestBox.PAD = 12

-- available() is optional. Returning false leaves the part out (its frame is off).
function DUI.RegisterTestPart(key, label, order, available)
    for i, p in ipairs(TestBox.parts) do
        if p.key == key then table.remove(TestBox.parts, i) break end
    end
    TestBox.parts[#TestBox.parts + 1] = { key = key, label = label, order = order or 100, available = available }
    table.sort(TestBox.parts, function(a, b) return a.order < b.order end)
    if TestBox.frame and TestBox.frame:IsShown() then TestBox.Layout() end
end

local function hidden()
    local root = DUI.DB.Root()
    if type(root.testHidden) ~= "table" then root.testHidden = {} end
    return root.testHidden
end

function DUI.TestPartShown(key)
    if DUI.testSolo then return DUI.testSolo[key] == true end
    return hidden()[key] ~= true
end

-- An options page's "Test frame" preview: test mode with only that page's
-- parts, ignoring the box (its choices are kept for the full preview). keys is
-- the list of parts, or nil to end it. Switching to another page's parts
-- restarts test mode so every sample is redone. Ends with test mode (combat or
-- /dui test). Returns false when it can't start, i.e. in combat.
local function sameParts(set, keys)
    if not set then return false end
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    if n ~= #keys then return false end
    for _, k in ipairs(keys) do if not set[k] then return false end end
    return true
end

function DUI.SetTestSolo(keys)
    if not keys then
        if DUI.testSolo then DUI.SetTestMode(false) end
        return true
    end
    if sameParts(DUI.testSolo, keys) then return true end
    if InCombatLockdown() then return DUI.SetTestMode(true) end -- prints why not
    if DUI.testMode then DUI.SetTestMode(false) end
    local set = {}
    for _, k in ipairs(keys) do set[k] = true end
    DUI.testSolo = set
    DUI.testRaid = false
    return DUI.SetTestMode(true)
end

-- Modules redo the sample on TestPartChanged. Samples are protected, so not
-- in combat (combat ends test mode anyway).
function DUI.SetTestPartShown(key, on)
    on = on and true or false
    if DUI.TestPartShown(key) == on or InCombatLockdown() then return end
    hidden()[key] = (not on) or nil
    DUI.Fire("TestPartChanged", key, on)
    TestBox.Refresh()
end

-- The box

local function newRow(f)
    local W = DUI.Widgets
    local C = W.COLORS
    local row = CreateFrame("Button", nil, f)
    row:SetSize(TestBox.COL_W, TestBox.ROW_H)
    row.box = W.Round(row, "ARTWORK")
    row.box:SetSize(14, 14)
    row.box:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.check = row:CreateTexture(nil, "OVERLAY")
    row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    row.check:SetSize(18, 18)
    row.check:SetPoint("CENTER", row.box, "CENTER", 0, 0)
    row.label = W.Font(row, W.BODY, DUI.Style.SIZE.body, C.text)
    row.label:SetPoint("LEFT", row.box, "RIGHT", 6, 0)
    row:SetScript("OnClick", function(self)
        DUI.SetTestPartShown(self.key, not DUI.TestPartShown(self.key))
    end)
    row:SetScript("OnEnter", function(self) if not self.on then W.Tint(self.box, C.controlHover) end end)
    row:SetScript("OnLeave", function() TestBox.Refresh() end)
    return row
end

local function build()
    if TestBox.frame then return TestBox.frame end
    local Style = DUI.Style
    local f = CreateFrame("Frame", "DaylightUITestBox", UIParent)
    DUI.Movers.FollowScale(f)
    f:SetPoint("TOP", UIParent, "TOP", 0, -12)
    f:SetFrameStrata("DIALOG")
    Style.Shell(f)
    f.title = Style.Text(f, Style.SIZE.head, "CENTER")
    f.title:SetPoint("TOP", f, "TOP", 0, -8)
    f.title:SetText(DUI.L["Show in test mode"])
    f:Hide()
    DUI.Motion.Window(f, 6)
    TestBox.frame = f
    return f
end

-- Ticks and colors from the saved choices.
function TestBox.Refresh()
    local W = DUI.Widgets
    for _, row in ipairs(TestBox.rows) do
        if row.key then
            row.on = DUI.TestPartShown(row.key)
            -- Ticked while visible: the tick pops in. Otherwise set at once.
            local fresh = row.on and not row.check:IsShown() and row.check:GetParent():IsVisible()
            row.check:SetShown(row.on)
            if fresh then DUI.Motion.Pop(row.check, 0.6, DUI.Motion.FAST) end
            -- The game's gold tick, desaturated so it reads on the accent.
            row.check:SetDesaturated(true)
            W.Tint(row.check, W.OnAccent())
            if row.on then W.TintAccent(row.box) else W.Tint(row.box, W.COLORS.control) end
            W.TextColor(row.label, row.on and W.COLORS.text or W.COLORS.dim)
        end
    end
end

-- One checkbox per available part, in rows of COLUMNS.
function TestBox.Layout()
    local f = build()
    local shown = {}
    for _, p in ipairs(TestBox.parts) do
        if not p.available or p.available() ~= false then shown[#shown + 1] = p end
    end
    for i, p in ipairs(shown) do
        local row = TestBox.rows[i] or newRow(f)
        TestBox.rows[i] = row
        row.key = p.key
        row.label:SetText(DUI.L[p.label])
        local col, line = (i - 1) % TestBox.COLUMNS, math.floor((i - 1) / TestBox.COLUMNS)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f, "TOPLEFT", TestBox.PAD + col * TestBox.COL_W, -28 - line * TestBox.ROW_H)
        row:Show()
    end
    for i = #shown + 1, #TestBox.rows do
        TestBox.rows[i].key = nil
        TestBox.rows[i]:Hide()
    end
    local cols = math.max(1, math.min(TestBox.COLUMNS, #shown))
    local lines = math.max(1, math.ceil(#shown / TestBox.COLUMNS))
    f:SetSize(2 * TestBox.PAD + cols * TestBox.COL_W, 36 + lines * TestBox.ROW_H)
    TestBox.Refresh()
end

-- A page preview has no box, only its own parts.
DUI.On("TestModeChanged", function(on)
    if not on then DUI.testSolo = nil end
    if on and not DUI.testSolo then
        TestBox.Layout()
        TestBox.frame:Show()
    elseif TestBox.frame then
        DUI.Motion.Vanish(TestBox.frame)
    end
end)

-- A frame turned on or off mid-preview gains or loses its checkbox.
DUI.On("SettingChanged", function()
    if TestBox.frame and TestBox.frame:IsShown() then TestBox.Layout() end
end)
-- Accent color for the ticks.
DUI.On("StyleChanged", function()
    if TestBox.frame and TestBox.frame:IsShown() then TestBox.Refresh() end
end)
