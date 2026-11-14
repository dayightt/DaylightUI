-- While /dui test is on, a small box at the top of the screen has a checkbox
-- per sample part (target, party, buffs...) so a part in the way can be
-- hidden. Modules register their own parts and check DUI.TestPartShown(key)
-- before showing a sample. Choices are account-wide (DaylightUIDB.testHidden)
-- and survive reloads. /dui unlock has a box like it, one checkbox per area,
-- to tuck that area's handles away.

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

-- A tick box: a shell at the top of the screen with a checkbox per item, in
-- rows of COLUMNS. spec: name, title, items() returning { key, label } lists,
-- shown(key), toggle(key, on), strata, shell (Style.Shell's opts).

local function newRow(box)
    local W = DUI.Widgets
    local C = W.COLORS
    local row = CreateFrame("Button", nil, box.frame)
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
        box.spec.toggle(self.key, not box.spec.shown(self.key))
    end)
    row:SetScript("OnEnter", function(self) if not self.on then W.Tint(self.box, C.controlHover) end end)
    row:SetScript("OnLeave", function() box.Refresh() end)
    return row
end

function TestBox.Make(spec)
    local box = { spec = spec, rows = {} }
    local Style = DUI.Style
    local f = CreateFrame("Frame", spec.name, UIParent)
    DUI.Movers.FollowScale(f)
    f:SetPoint("TOP", UIParent, "TOP", 0, -12)
    f:SetFrameStrata(spec.strata or "DIALOG")
    Style.Shell(f, spec.shell)
    f.title = Style.Text(f, Style.SIZE.head, "CENTER")
    f.title:SetPoint("TOP", f, "TOP", 0, -8)
    f.title:SetText(spec.title)
    f:Hide()
    DUI.Motion.Window(f, 6)
    box.frame = f

    -- Ticks and colors from the saved choices.
    function box.Refresh()
        local W = DUI.Widgets
        for _, row in ipairs(box.rows) do
            if row.key then
                row.on = spec.shown(row.key)
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

    function box.Layout()
        local items = spec.items()
        for i, p in ipairs(items) do
            local row = box.rows[i] or newRow(box)
            box.rows[i] = row
            row.key = p.key
            row.label:SetText(DUI.L[p.label])
            local col, line = (i - 1) % TestBox.COLUMNS, math.floor((i - 1) / TestBox.COLUMNS)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f, "TOPLEFT", TestBox.PAD + col * TestBox.COL_W, -28 - line * TestBox.ROW_H)
            row:Show()
        end
        for i = #items + 1, #box.rows do
            box.rows[i].key = nil
            box.rows[i]:Hide()
        end
        local cols = math.max(1, math.min(TestBox.COLUMNS, #items))
        local lines = math.max(1, math.ceil(#items / TestBox.COLUMNS))
        f:SetSize(2 * TestBox.PAD + cols * TestBox.COL_W, 36 + lines * TestBox.ROW_H)
        box.Refresh()
    end
    return box
end

-- The test box: one checkbox per available sample part.
local function testParts()
    local shown = {}
    for _, p in ipairs(TestBox.parts) do
        if not p.available or p.available() ~= false then shown[#shown + 1] = p end
    end
    return shown
end

function TestBox.Refresh()
    if TestBox.box then TestBox.box.Refresh() end
end

function TestBox.Layout()
    if not TestBox.box then
        TestBox.box = TestBox.Make({
            name = "DaylightUITestBox",
            title = DUI.L["Show in test mode"],
            items = testParts,
            shown = DUI.TestPartShown,
            toggle = DUI.SetTestPartShown,
        })
        TestBox.frame, TestBox.rows = TestBox.box.frame, TestBox.box.rows
    end
    TestBox.box.Layout()
    TestBox.Place()
end

-- The unlock box: one checkbox per area with handles. It sits above the
-- handles (the Lock bar's layer) so a handle can't cover it.
local UnlockBox = {}
TestBox.Unlock = UnlockBox

function UnlockBox.Layout()
    if not UnlockBox.box then
        UnlockBox.box = TestBox.Make({
            name = "DaylightUIUnlockBox",
            title = DUI.L["Show in unlock mode"],
            strata = "FULLSCREEN_DIALOG",
            -- Solid, or the handles' labels under it read through.
            shell = { bgAlpha = 1 },
            items = DUI.Movers.Areas,
            shown = DUI.Movers.AreaShown,
            toggle = DUI.Movers.SetAreaShown,
        })
        UnlockBox.frame, UnlockBox.rows = UnlockBox.box.frame, UnlockBox.box.rows
        UnlockBox.frame:EnableMouse(true)
    end
    UnlockBox.box.Layout()
    TestBox.Place()
end

-- The unlock box hangs under the Lock bar (or the Finish setup button under
-- it), and the test box under that while both are up, so none covers another.
function TestBox.Place()
    local unlocked = DUI.Movers.unlocked
    local lock = DUI.Movers.LockButton()
    local ub = UnlockBox.frame
    if ub then
        ub:ClearAllPoints()
        if unlocked and lock then
            local setup = lock.setup
            local above = (setup and setup.bar:IsShown()) and setup.bar or lock.bar
            ub:SetPoint("TOP", above, "BOTTOM", 0, -6)
        else
            ub:SetPoint("TOP", UIParent, "TOP", 0, -12)
        end
    end
    local tb = TestBox.frame
    if tb then
        tb:ClearAllPoints()
        -- Over the handles while unlocked, like the unlock box.
        if unlocked and ub then
            tb:SetPoint("TOP", ub, "BOTTOM", 0, -6)
            tb:SetFrameStrata("FULLSCREEN_DIALOG")
        else
            tb:SetPoint("TOP", UIParent, "TOP", 0, -12)
            tb:SetFrameStrata("DIALOG")
        end
    end
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

DUI.On("UnlockChanged", function(on)
    if on then
        UnlockBox.Layout()
        UnlockBox.frame:Show()
    elseif UnlockBox.frame then
        DUI.Motion.Vanish(UnlockBox.frame)
    end
    if TestBox.frame then TestBox.Place() end
end)

DUI.On("UnlockAreaChanged", function()
    if UnlockBox.box then UnlockBox.box.Refresh() end
end)

-- A frame turned on or off mid-preview gains or loses its checkbox, and an
-- area with no handles left loses its own.
DUI.On("SettingChanged", function()
    if TestBox.frame and TestBox.frame:IsShown() then TestBox.Layout() end
    if DUI.Movers.unlocked and UnlockBox.frame then UnlockBox.Layout() end
end)
-- Accent color for the ticks.
DUI.On("StyleChanged", function()
    if TestBox.frame and TestBox.frame:IsShown() then TestBox.Refresh() end
    if UnlockBox.frame and UnlockBox.frame:IsShown() then UnlockBox.box.Refresh() end
end)
