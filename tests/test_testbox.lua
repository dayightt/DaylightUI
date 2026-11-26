local stub = require("stub")

-- With the meter shown (it's folded away by default).
local function login(before)
    local DUI, ns = stub.Load({ module = true, buffs = true, infopanel = true, before = before })
    DUI:Set("InfoPanel", "meter.enabled", true)
    return DUI, ns
end

local function rowFor(DUI, key)
    for _, row in ipairs(DUI.TestBox.rows) do
        if row:IsShown() and row.key == key then return row end
    end
end

local function shownCount(list)
    local n = 0
    for _, b in ipairs(list) do if b:IsShown() then n = n + 1 end end
    return n
end

T.test("test box: shows only in test mode, one box per registered part", function()
    local DUI = login()
    T.falsy(DUI.TestBox.frame and DUI.TestBox.frame:IsShown())
    DUI.SetTestMode(true)
    T.truthy(DUI.TestBox.frame:IsShown())
    for _, key in ipairs({ "target", "focus", "pet", "targettarget", "castbars", "party", "raid", "buffs", "meter" }) do
        T.truthy(rowFor(DUI, key), key .. " has a box")
    end
    T.isnil(rowFor(DUI, "player"), "the player frame is real, not a sample")
    T.eq(rowFor(DUI, "target").label.__text, "Target")
    DUI.SetTestMode(false)
    stub.FinishFade(DUI.TestBox.frame)
    T.falsy(DUI.TestBox.frame:IsShown())
end)

T.test("test box: modules not loaded don't get a box", function()
    local DUI = stub.Load({ module = true })
    DUI.SetTestMode(true)
    T.truthy(rowFor(DUI, "target"))
    T.isnil(rowFor(DUI, "buffs"))
    T.isnil(rowFor(DUI, "meter"))
end)

T.test("test box: frames turned off don't get a box", function()
    local DUI = login()
    DUI:Set("InfoPanel", "meter.enabled", false)
    DUI:Set("UnitFrames", "raid.enabled", false)
    DUI.SetTestMode(true)
    T.isnil(rowFor(DUI, "meter"))
    T.isnil(rowFor(DUI, "raid"))
    T.truthy(rowFor(DUI, "party"))
end)

T.test("test box: unticking hides that sample at once, ticking brings it back", function()
    local DUI = login()
    DUI.SetTestMode(true)
    rowFor(DUI, "target"):Click()
    T.falsy(DUI.TestPartShown("target"))
    T.falsy(rowFor(DUI, "target").check:IsShown(), "the tick goes")
    rowFor(DUI, "target"):Click()
    T.truthy(DUI.TestPartShown("target"))
    T.truthy(rowFor(DUI, "target").check:IsShown())
end)

T.test("test box: unit frame samples follow their boxes", function()
    local DUI, ns = stub.Load({ module = true })
    DUI.SetTestMode(true)
    local target, focus = ns.frames.target, ns.frames.focus
    T.truthy(target.test)
    DUI.SetTestPartShown("target", false)
    T.isnil(target.test, "target sample gone")
    T.truthy(target.__unitWatch, "the target frame watches its unit again")
    T.truthy(focus.test, "focus untouched")
    T.falsy(ns.targetCastbar:IsShown(), "the target's cast goes with it")
    DUI.SetTestPartShown("castbars", false)
    T.falsy(ns.playerCastbar:IsShown(), "cast bars hidden")
    DUI.SetTestPartShown("target", true)
    DUI.SetTestPartShown("castbars", true)
    T.truthy(target.test)
    T.eq(target.nameText.__text, "Torol Sadeas")
    T.truthy(ns.playerCastbar:IsShown())
    T.truthy(ns.targetCastbar:IsShown())
end)

T.test("test box: party and raid samples follow their boxes", function()
    local DUI, ns = stub.Load({ module = true })
    DUI.SetTestMode(true)
    stub.RunTimers()
    T.eq(shownCount(ns.Raid.preview), 40)
    DUI.SetTestPartShown("raid", false)
    stub.RunTimers()
    T.eq(shownCount(ns.Raid.preview), 0, "raid samples hidden")
    T.truthy(ns.Party.preview[1]:IsShown(), "party untouched")
    DUI.SetTestPartShown("party", false)
    stub.RunTimers()
    T.falsy(ns.Party.preview[1]:IsShown(), "party samples hidden")
    T.eq(ns.Party.header:GetAlpha(), 1, "the real party shows again")
    DUI.SetTestPartShown("raid", true)
    DUI.SetTestPartShown("party", true)
    stub.RunTimers()
    T.eq(shownCount(ns.Raid.preview), 40)
    T.truthy(ns.Party.preview[1]:IsShown())
    T.eq(ns.Party.header:GetAlpha(), 0)
end)

-- Every aura piece a sample tile can carry that's showing: icons in its aura
-- groups, corner indicators, boss-debuff stand-ins, the dispel icon and glow.
local function tileAuras(ns, list)
    local n = 0
    for _, b in ipairs(list or {}) do
        if b:IsShown() then
            local set = b.sampleSet
            if set then
                for _, c in ns.AuraGroups.Containers(set) do
                    if c:IsShown() then
                        for _, btn in ipairs(c.pool or {}) do if btn:IsShown() then n = n + 1 end end
                    end
                end
                for _, c in pairs(set.ind or {}) do if c.plain and c:IsShown() then n = n + 1 end end
            end
            for _, slot in ipairs(b.privateSet and b.privateSet.slots or {}) do
                if slot.sample and slot.sample:IsShown() then n = n + 1 end
            end
            if b.sampleDispel and b.sampleDispel:IsShown() then n = n + 1 end
            if b.sampleHLFrame and b.sampleHLFrame:IsShown() then n = n + 1 end
        end
    end
    return n
end

T.test("test box: an Auras box clears every sample aura off the frames, the frames stay", function()
    local DUI, ns = stub.Load({ module = true })
    DUI:Set("UnitFrames", "playerAuras.debuffs", true)
    DUI.SetTestMode(true)
    stub.RunTimers()
    T.truthy(rowFor(DUI, "auras"), "the box has an Auras tick")
    T.truthy(tileAuras(ns, ns.Party.preview) > 0, "party samples start with auras")
    T.truthy(tileAuras(ns, ns.Raid.preview) > 0, "raid samples too")
    T.truthy(ns.auras.sample, "and the target")

    rowFor(DUI, "auras"):Click()
    stub.RunTimers()
    T.falsy(DUI.TestPartShown("auras"))
    T.eq(tileAuras(ns, ns.Party.preview), 0, "no auras on the party")
    T.eq(tileAuras(ns, ns.Raid.preview), 0, "nor the raid")
    T.isnil(ns.auras.sample, "nor the target")
    T.isnil(ns.playerAuras and ns.playerAuras.sample, "nor the player's own rows")
    T.isnil(ns.focusAuras and ns.focusAuras.sample)
    T.truthy(ns.Party.preview[1]:IsShown(), "the party samples stay")
    T.eq(shownCount(ns.Raid.preview), 40, "every raid tile stays")
    T.truthy(ns.frames.target.test, "the target sample stays")
    T.truthy(ns.targetCastbar:IsShown(), "its cast too")

    -- Kept for the next test mode, and a page's own preview still shows them.
    DUI.SetTestMode(false)
    DUI.SetTestMode(true)
    stub.RunTimers()
    T.isnil(ns.auras.sample, "still off next time")
    T.eq(tileAuras(ns, ns.Party.preview), 0)
    DUI.SetTestSolo({ "party" })
    stub.RunTimers()
    T.truthy(tileAuras(ns, ns.Party.preview) > 0, "a page's preview is styling them: it shows them")
    DUI.SetTestSolo(nil)

    DUI.SetTestMode(true)
    rowFor(DUI, "auras"):Click()
    stub.RunTimers()
    T.truthy(tileAuras(ns, ns.Party.preview) > 0, "ticked again, back")
    T.truthy(tileAuras(ns, ns.Raid.preview) > 0)
    T.truthy(ns.auras.sample)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("test box: a sweep shows its group even when unticked", function()
    local DUI, ns = stub.Load({ module = true })
    DUI.SetTestPartShown("party", false)
    DUI.RunCommand("sweep party")
    stub.RunTimers()
    T.truthy(ns.Party.preview[1]:IsShown())
end)

T.test("test box: buffs and meter samples follow their boxes", function()
    local DUI = login()
    local BL, M = stub.buffs, stub.infopanel.Meter
    DUI.SetTestMode(true)
    T.truthy(BL.Preview.Active())
    T.truthy(M.Fights() == M.SAMPLE_FIGHTS)
    DUI.SetTestPartShown("buffs", false)
    T.falsy(BL.Preview.Active(), "sample buffs gone")
    DUI.SetTestPartShown("meter", false)
    T.falsy(M.Fights() == M.SAMPLE_FIGHTS, "the meter reads the real fights")
    DUI.SetTestPartShown("buffs", true)
    DUI.SetTestPartShown("meter", true)
    T.truthy(BL.Preview.Active())
    T.truthy(M.Fights() == M.SAMPLE_FIGHTS)
end)

T.test("test box: a hidden part stays hidden the next time test mode starts", function()
    local DUI, ns = stub.Load({ module = true })
    DUI.SetTestPartShown("focus", false)
    DUI.SetTestMode(true)
    T.isnil(ns.frames.focus.test)
    T.truthy(ns.frames.target.test)
end)

T.test("test box: choices are saved across a reload", function()
    local DUI = stub.Load({ module = true })
    DUI.SetTestPartShown("raid", false)
    local saved = DaylightUIDB
    DUI = stub.Load({ module = true, before = function() DaylightUIDB = saved end })
    T.falsy(DUI.TestPartShown("raid"))
    T.truthy(DUI.TestPartShown("party"))
    DUI.SetTestMode(true)
    T.falsy(rowFor(DUI, "raid").check:IsShown())
end)

-- ---------------------------------------------------------------------
-- One page's preview: the "Test frame" switch on an options page
-- ---------------------------------------------------------------------

T.test("page preview: only that page's parts show, whatever the box says", function()
    local DUI, ns = login()
    DUI.SetTestPartShown("focus", false)
    T.truthy(DUI.SetTestSolo({ "focus" }))
    stub.RunTimers()
    T.truthy(DUI.testMode)
    T.truthy(ns.frames.focus.test, "focus shows though its box is unticked")
    T.isnil(ns.frames.target.test)
    T.isnil(ns.frames.pet.test)
    T.falsy(ns.playerCastbar:IsShown(), "no cast bars")
    T.falsy(ns.swing.test, "no swing")
    T.falsy(ns.combo and ns.combo.test, "no combo points")
    T.falsy(ns.happiness and ns.happiness.test, "no pet happiness")
    T.isnil(ns.Party.preview, "the party samples aren't even built")
    T.isnil(ns.Raid.preview, "nor the raid's")
    T.falsy(stub.buffs.Preview.Active())
    T.falsy(DUI.TestBox.frame and DUI.TestBox.frame:IsShown(), "the test box stays hidden")
    DUI.SetTestSolo(nil)
    T.falsy(DUI.testMode)
    T.isnil(DUI.testSolo)
    T.falsy(DUI.TestPartShown("focus"), "the box's own choices are kept")
    T.truthy(DUI.TestPartShown("target"))
end)

T.test("page preview: another page's parts redo the samples", function()
    local DUI, ns = login()
    DUI.SetTestSolo({ "target" })
    T.truthy(ns.frames.target.test)
    DUI.SetTestSolo({ "party" })
    stub.RunTimers()
    T.isnil(ns.frames.target.test)
    T.truthy(ns.Party.preview[1]:IsShown())
    T.eq(ns.Party.header:GetAlpha(), 0)
end)

T.test("page preview: a setting changed while it's on shows at once", function()
    local DUI, ns = login()
    DUI.SetTestSolo({ "target" })
    DUI:Set("UnitFrames", "target.width", 250)
    stub.RunTimers()
    T.truthy(ns.frames.target.test)
    T.near(ns.frames.target:GetWidth(), 250, 1)
    T.isnil(ns.frames.focus.test, "still only the target")
end)

T.test("page preview: ending test mode ends it; the next preview is the full one", function()
    local DUI, ns = login()
    DUI.SetTestSolo({ "pet" })
    DUI.SetTestMode(false)
    T.isnil(DUI.testSolo)
    DUI.SetTestMode(true)
    T.truthy(ns.frames.target.test)
    T.truthy(ns.frames.focus.test)
    T.truthy(DUI.TestBox.frame:IsShown())
end)

T.test("page preview: can't start in combat", function()
    local DUI = login()
    stub.combat = true
    T.falsy(DUI.SetTestSolo({ "target" }))
    T.falsy(DUI.testMode)
    T.isnil(DUI.testSolo)
    stub.combat = false
end)

T.test("page preview: the switch at the top of a frame's options page", function()
    local DUI, ns = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("UnitFrames.player")
    local sw = P.TestSwitch()
    T.falsy(sw:IsShown(), "your own frame is always real: no switch")
    P.Show("UnitFrames.target")
    T.truthy(sw:IsShown())
    sw.control:Click()
    T.truthy(DUI.testMode)
    T.truthy(ns.frames.target.test)
    T.isnil(ns.frames.focus.test)
    P.Show("UnitFrames.focus")
    T.truthy(ns.frames.focus.test, "follows you to the next frame's page")
    T.isnil(ns.frames.target.test)
    P.Show("UnitFrames.colors")
    T.falsy(sw:IsShown())
    T.truthy(ns.frames.focus.test, "a page without the switch keeps the last one")
    P.Toggle()
    T.falsy(P.IsShown())
    T.truthy(ns.frames.focus.test, "closing the window doesn't end it")
    P.Show("UnitFrames.focus")
    sw.control:Click()
    T.falsy(DUI.testMode, "switched off")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("page preview: the full preview doesn't flip the switch or follow pages", function()
    local DUI, ns = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    DUI.SetTestMode(true)
    P.Show("UnitFrames.target")
    T.isnil(DUI.testSolo)
    T.truthy(ns.frames.focus.test, "every sample still shows")
    P.TestSwitch().control:Click()
    T.truthy(DUI.testMode)
    T.isnil(ns.frames.focus.test, "now only the target")
end)

T.test("page preview: cast bars and swing pages show their own bars", function()
    local DUI, ns = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("UnitFrames.castbars")
    P.TestSwitch().control:Click()
    T.truthy(ns.playerCastbar:IsShown())
    T.truthy(ns.targetCastbar:IsShown(), "with the target it hangs off")
    T.isnil(ns.frames.pet.test)
    T.falsy(ns.swing.test)
    P.Show("UnitFrames.swing")
    T.truthy(ns.swing.test)
    T.falsy(ns.playerCastbar:IsShown())
    T.isnil(ns.frames.target.test)
end)

-- The unlock box: one checkbox per area with handles, tucking them away.
local function unlockRow(DUI, key)
    for _, row in ipairs(DUI.TestBox.Unlock.rows or {}) do
        if row:IsShown() and row.key == key then return row end
    end
end

T.test("unlock box: shows while unlocked, one box per area with handles", function()
    local DUI = stub.Load({ module = true, buffs = true })
    T.falsy(DUI.TestBox.Unlock.frame and DUI.TestBox.Unlock.frame:IsShown())
    DUI.Movers.Unlock()
    T.truthy(DUI.TestBox.Unlock.frame:IsShown())
    T.truthy(unlockRow(DUI, "unit"), "unit frames")
    T.truthy(unlockRow(DUI, "buffs"), "buffs")
    T.isnil(unlockRow(DUI, "chat"), "chat isn't loaded")
    T.eq(DUI.Movers.AreaOf("unitframes.playerCastbar"), "cast")
    T.eq(DUI.Movers.AreaOf("unitframes.raid20"), "group")
    T.eq(DUI.Movers.AreaOf("unitframes.target"), "unit")
    T.eq(DUI.Movers.AreaOf("plugin.x.y"), "other")
    DUI.Movers.Lock()
    stub.FinishFade(DUI.TestBox.Unlock.frame)
    T.falsy(DUI.TestBox.Unlock.frame:IsShown())
end)

T.test("unlock box: unticking an area hides its handles, kept after a lock", function()
    local DUI = stub.Load({ module = true, buffs = true })
    DUI:Set("general", "motion", false)
    DUI.Movers.Unlock()
    T.truthy(DUI.Movers.Handle("unitframes.target"):IsShown())
    unlockRow(DUI, "unit"):Click()
    T.falsy(DUI.Movers.AreaShown("unit"))
    T.falsy(DUI.Movers.Handle("unitframes.target"):IsShown(), "tucked away")
    local other = 0
    for _, a in ipairs(DUI.Movers.Areas()) do
        if a.key ~= "unit" then other = other + 1; T.truthy(DUI.Movers.AreaShown(a.key), a.key) end
    end
    T.truthy(other > 0, "other areas stay")
    T.falsy(unlockRow(DUI, "unit").check:IsShown())
    DUI.Movers.Lock()
    DUI.Movers.Unlock()
    T.falsy(DUI.Movers.Handle("unitframes.target"):IsShown(), "still tucked away")
    T.truthy(DaylightUIDB.unlockHidden.unit, "saved account-wide")
    unlockRow(DUI, "unit"):Click()
    T.truthy(DUI.Movers.Handle("unitframes.target"):IsShown(), "back")
    T.eq(DUI.Movers.Handle("unitframes.target"):GetAlpha(), 1)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("unlock box: sits under the Lock bar, the test box under it", function()
    local DUI = stub.Load({ module = true })
    DUI.SetTestMode(true)
    local _, rel = DUI.TestBox.frame:GetPoint(1)
    T.eq(rel, UIParent)
    DUI.Movers.Unlock()
    local ub = DUI.TestBox.Unlock.frame
    _, rel = ub:GetPoint(1)
    T.truthy(rel == DUI.Movers.LockButton().bar or rel == DUI.Movers.SetupButton().bar)
    _, rel = DUI.TestBox.frame:GetPoint(1)
    T.eq(rel, ub)
    DUI.Movers.Lock()
    _, rel = DUI.TestBox.frame:GetPoint(1)
    T.eq(rel, UIParent)
end)

T.test("boxes: the X closes each, the Areas button brings the unlock box back", function()
    local DUI = stub.Load({ module = true })
    DUI.SetTestMode(true)
    local tb = DUI.TestBox.frame
    tb.close:Click()
    stub.FinishFade(tb)
    T.falsy(tb:IsShown(), "test box closed")
    DUI.SetTestMode(false)
    DUI.SetTestMode(true)
    T.truthy(tb:IsShown(), "back with the next test mode")
    DUI.SetTestMode(false)

    DUI.Movers.Unlock()
    local ub = DUI.TestBox.Unlock.frame
    local areas = DUI.Movers.LockButton().areas
    T.truthy(areas.active, "lit while open")
    ub.close:Click()
    stub.FinishFade(ub)
    T.falsy(ub:IsShown(), "unlock box closed")
    T.falsy(areas.active, "unlit when closed")
    DUI.Movers.Lock()
    DUI.Movers.Unlock()
    T.falsy(ub:IsShown(), "stays closed")
    areas:Click()
    T.truthy(ub:IsShown(), "Areas opens it")
    T.truthy(areas.active)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tick boxes: a column is as wide as its longest label", function()
    local DUI = stub.Load({ module = true })
    DUI.Movers.Unlock()
    local rows = DUI.TestBox.Unlock.rows
    T.truthy(#rows > 1)
    local first = rows[1]
    T.truthy(first:GetWidth() >= DUI.TestBox.COL_W)
    first.label.GetStringWidth = function() return 300 end -- a long word in another language
    DUI.TestBox.Unlock.box.Layout()
    T.truthy(first:GetWidth() >= 300, "the row holds its label")
    local second = rows[2]
    local x1 = select(4, first:GetPoint(1))
    local x2 = select(4, second:GetPoint(1))
    T.truthy(x2 - x1 >= 300 or select(5, second:GetPoint(1)) ~= select(5, first:GetPoint(1)), "the next column starts after it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Runs the shared tween driver long enough for every ease to land.
local function settle(DUI)
    for _ = 1, 4 do
        local d = DUI.Motion.Driver()
        if d then stub.RunOnUpdate(d, 1) end
        stub.RunTimers()
    end
end

T.test("unlock bar: Hide folds it into a small tab and takes the unlock box along; Show brings both back", function()
    local DUI = stub.Load({ module = true })
    DUI.Movers.Unlock()
    settle(DUI)
    local lock = DUI.Movers.LockButton()
    local ub = DUI.TestBox.Unlock.frame
    T.truthy(lock.bar:IsShown()); T.truthy(ub:IsShown()); T.falsy(lock.tab:IsShown())
    lock.fold:Click()
    settle(DUI)
    stub.FinishFade(ub)
    T.falsy(lock.bar:IsShown(), "bar folded away")
    T.falsy(ub:IsShown(), "unlock box goes with it")
    T.truthy(lock.tab:IsShown(), "the small tab is up")
    T.truthy(DUI.Movers.unlocked, "still unlocked")
    lock.unfold:Click()
    settle(DUI)
    T.truthy(lock.bar:IsShown()); T.truthy(ub:IsShown()); T.falsy(lock.tab:IsShown())
    T.eq(lock.bar:GetAlpha(), 1, "fully back")
    DUI.Movers.SetBarHidden(true)
    settle(DUI)
    DUI.Movers.Lock()
    T.falsy(lock.tab:IsShown(), "no tab once locked")
    T.falsy(lock.bar:IsShown())
    DUI.Movers.SetBarHidden(false)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("unlock bar: the bar and tab ease (fade) rather than switching", function()
    local DUI = stub.Load({ module = true })
    DUI.Movers.Unlock()
    settle(DUI)
    local lock = DUI.Movers.LockButton()
    lock.fold:Click()
    stub.RunOnUpdate(DUI.Motion.Driver(), 0.03)
    T.truthy(lock.bar:IsShown() and lock.bar:GetAlpha() < 1, "the bar is mid-fade, not gone yet")
    T.truthy(lock.tab:IsShown() and lock.tab:GetAlpha() < 1, "the tab fades in")
    settle(DUI)
    T.falsy(lock.bar:IsShown())
    T.eq(lock.tab:GetAlpha(), 1)
end)

T.test("unlock bar: the test box fades out and back in around its move, not jumping", function()
    local DUI = stub.Load({ module = true })
    DUI.SetTestMode(true)
    DUI.Movers.Unlock()
    settle(DUI)
    local tb = DUI.TestBox.frame
    local lock = DUI.Movers.LockButton()
    local _, rel = tb:GetPoint(1)
    T.eq(rel, DUI.TestBox.Unlock.frame, "under the unlock box")
    lock.fold:Click()
    stub.RunOnUpdate(DUI.Motion.Driver(), 0.03)
    T.truthy(tb:GetAlpha() < 1, "fading out first")
    _, rel = tb:GetPoint(1)
    T.eq(rel, DUI.TestBox.Unlock.frame, "still where it was while it fades")
    settle(DUI)
    _, rel = tb:GetPoint(1)
    T.eq(rel, UIParent, "then under the tab")
    T.eq(tb:GetAlpha(), 1, "and back in")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
