-- Every mix of the look settings, laid out on group buttons. Checks for no
-- errors, hidden parts staying hidden, nothing anchored to a hidden part,
-- corner icons never sharing a corner, and the angled end keeping its height.

local stub = require("stub")

local function login() return stub.Load({ module = true }) end

local HEIGHTS = { 16, 20, 28, 34, 56, 80 }
local WIDTHS = { 40, 72, 170, 260 }
local BOOLS = { true, false }

-- Shown: itself and every parent up to (not including) top.
local function visible(r, top)
    while r and r ~= top do
        if not r:IsShown() then return false end
        r = r:GetParent()
    end
    return true
end

local function check(ns, f, cfg, text, where)
    local UF, Pixel = ns.UF, DaylightUI.Pixel
    if f.power then T.eq(f.power:IsShown(), cfg.showPower ~= false, where .. ": power bar") end
    if f.portrait then
        T.eq(f.portrait:IsShown(), UF.PortraitMode(f, cfg) ~= "none", where .. ": portrait")
    end
    if f.tab then
        T.eq(f.tab:IsShown(), cfg.showName ~= false and cfg.nameOnBar ~= true, where .. ": name tab")
    end
    local side = cfg.slant ~= false and f.spec.slant
    T.eq(f.cut, side and Pixel.Snap(f, cfg.height * UF.SLANT) or 0, where .. ": the angled end's width")
    local regions = { f.nameText, f.percentText, f.marker, f.leaderIcon, f.roleIcon, f.portrait }
    if f.status then for _, t in pairs(f.status.icons) do regions[#regions + 1] = t end end
    for _, r in ipairs(regions) do
        if r and visible(r, f) then
            for i = 1, r:GetNumPoints() do
                local _, rel = r:GetPoint(i)
                if type(rel) == "table" and rel ~= f and rel ~= UIParent then
                    T.truthy(visible(rel, f), where .. ": a shown part hangs off a hidden one")
                end
            end
        end
    end
    local seen = {}
    for _, r in ipairs({ f.marker, f.leaderIcon, f.roleIcon }) do
        if r and visible(r, f) and r:GetNumPoints() > 0 then
            local p, rel = r:GetPoint(1)
            if rel == f.health or rel == f then
                T.falsy(seen[p], where .. ": two icons in the " .. p .. " corner")
                seen[p] = true
            end
        end
    end
    -- The text sizes the settings ask for (times the font scale).
    local fs = DaylightUI.DB.General().fontScale
    T.near(f.nameText.__font[2], text.name * fs, 0.001, where .. ": the name size")
    T.near(f.percentText.__font[2], ((cfg.bigNumber == true) and text.big or text.percent) * fs, 0.001, where .. ": the health text size")
end

T.test("sweep: raid tiles, every look at every size", function()
    local DUI, ns = login()
    DUI.SetTestMode(true)
    local d = ns.module.db
    local cfg, text = d.raid, d.raidText
    -- A button the header made, checked alongside the samples.
    local g = ns.Raid.group
    local hb = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton1", g.header)
    hb:SetAttribute("unit", "raid2")
    stub.units.raid2 = { name = "Lift", isPlayer = true, class = "PRIEST", health = 5, maxHealth = 10 }
    g.header.initialConfigFunction(g.header, hb:GetName())
    for _, h in ipairs(HEIGHTS) do for _, w in ipairs(WIDTHS) do
        for _, slant in ipairs(BOOLS) do for _, power in ipairs(BOOLS) do
            for _, vert in ipairs(BOOLS) do for _, pct in ipairs(BOOLS) do
                cfg.height, cfg.width, cfg.slant, cfg.showPower, cfg.fillVertical, cfg.showPercent =
                    h, w, slant, power, vert, pct
                g:Layout(cfg, text, d.range)
                g:ShowPreview(true)
                local what = string.format("raid %dx%d slant=%s power=%s vert=%s pct=%s",
                    w, h, tostring(slant), tostring(power), tostring(vert), tostring(pct))
                for i = 1, 3 do
                    check(ns, ns.Raid.preview[i], cfg, text, what .. " #" .. i)
                end
                check(ns, hb, cfg, text, what .. " (header button)")
            end end
        end end
    end end
    T.eq(#stub.errors, 0, "no errors: " .. tostring(stub.errors[1]))
end)

-- The party's buttons: its test-mode samples, laid out by the engine.
local function partyButtons(ns, cfg, text)
    local d = ns.module.db
    ns.Party.group:Layout(cfg, text, d.range)
    ns.Party.group:ShowPreview(true)
    local out = {}
    for i = 1, 4 do out[i] = ns.Party.preview[i] end
    return out
end

T.test("sweep: party frames, every look at every size", function()
    local DUI, ns = login()
    DUI.SetTestMode(true)
    local d = ns.module.db
    local cfg, text = d.party, d.partyText
    for _, h in ipairs(HEIGHTS) do for _, w in ipairs(WIDTHS) do
        for _, portrait in ipairs(ns.UF.PORTRAIT_ORDER) do for _, slant in ipairs(BOOLS) do
            for _, onBar in ipairs(BOOLS) do for _, power in ipairs(BOOLS) do for _, vert in ipairs(BOOLS) do
                cfg.height, cfg.width, cfg.portrait, cfg.slant, cfg.nameOnBar, cfg.showPower, cfg.fillVertical =
                    h, w, portrait, slant, onBar, power, vert
                for i, f in ipairs(partyButtons(ns, cfg, text)) do
                    check(ns, f, cfg, text, string.format("party %dx%d %s slant=%s bar=%s power=%s vert=%s #%d",
                        w, h, portrait, tostring(slant), tostring(onBar), tostring(power), tostring(vert), i))
                end
            end end end
        end end
    end end
    T.eq(#stub.errors, 0, "no errors: " .. tostring(stub.errors[1]))
end)

T.test("sweep: party layouts, direction x per line x you x sort", function()
    local _, ns = login()
    local d = ns.module.db
    local cfg, text, h = d.party, d.partyText, ns.Party.header
    local holder = ns.Party.holder
    local W, H, SP, GS = 60, 56, 4, 6   -- the sums below use these; tiles snap to whole pixels, hence the slack
    for _, dir in ipairs({ "columns", "rows" }) do for _, per in ipairs({ 1, 2, 5 }) do
        for _, hide in ipairs(BOOLS) do for _, sort in ipairs({ "group", "role", "class", "name" }) do
            cfg.width, cfg.height, cfg.spacing, cfg.groupSpacing = W, H, SP, GS
            cfg.direction, cfg.perLine, cfg.hideSelf, cfg.sortBy = dir, per, hide, sort
            ns.Party.group:Layout(cfg, text, d.range)
            local where = string.format("%s per=%d hide=%s sort=%s", dir, per, tostring(hide), sort)
            T.eq(h:GetAttribute("point"), dir == "rows" and "LEFT" or "TOP", where)
            T.eq(h:GetAttribute("unitsPerColumn"), per, where)
            T.eq(h:GetAttribute("showPlayer"), not hide, where)
            -- Sizes worked out by hand: a line holds `per` frames, spaced by
            -- spacing; the lines are spaced by groupSpacing.
            local count = hide and 4 or 5
            local inLine = math.min(per, count)
            local lines = math.ceil(count / per)
            if dir == "rows" then
                T.near(holder:GetWidth(), inLine * W + (inLine - 1) * SP, 3, where .. ": width")
                T.near(holder:GetHeight(), lines * H + (lines - 1) * GS, 3, where .. ": height")
            else
                T.near(holder:GetWidth(), lines * W + (lines - 1) * GS, 3, where .. ": width")
                T.near(holder:GetHeight(), inLine * H + (inLine - 1) * SP, 3, where .. ": height")
            end
        end end
    end end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("/dui sweep party steps through looks without touching the saved settings", function()
    local DUI, ns = login()
    local before = DUI:Get("UnitFrames", "party.width")
    DUI.RunCommand("sweep party")
    stub.RunTimers()
    T.truthy(DUI.testMode, "test mode on")
    T.truthy(DaylightUISweep:IsShown())
    ns.Sweep.Step(1)   -- Healer
    stub.RunTimers()
    T.near(ns.Party.preview[1]:GetWidth(), 60, 1, "the Healer step's tile width")
    T.truthy(ns.Party.preview[5]:IsShown(), "you included")
    T.eq(DUI:Get("UnitFrames", "party.width"), before, "the saved width untouched")
    ns.Sweep.Step(-2)  -- wraps round to the last step
    stub.RunTimers()
    T.eq(ns.Sweep.index, #ns.Sweep.STEPS.party, "wrapped to the last step")
    T.truthy(string.find(DaylightUISweep.label:GetText() or "", ns.Sweep.STEPS.party[#ns.Sweep.STEPS.party].label, 1, true), "label")
    ns.Sweep.Stop()
    stub.RunTimers()
    T.falsy(DUI.testMode)
    T.isnil(ns.Party.group.sweep)
    T.falsy(DaylightUISweep:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("the sweep's DPS / Tank step shows the stock look, not the player's own", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "party.width", 60)
    DUI:Set("UnitFrames", "party.height", 56)
    DUI.RunCommand("sweep party")
    stub.RunTimers()
    T.near(ns.Party.preview[1]:GetWidth(), ns.DEFAULTS.party.width, 1, "stock width")
    ns.Sweep.Stop()
    stub.RunTimers()
    T.eq(DUI:Get("UnitFrames", "party.width"), 60, "the saved width untouched")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("every sweep step lays out without errors", function()
    local DUI, ns = login()
    for _, kind in ipairs({ "party", "raid" }) do
        DUI.RunCommand("sweep " .. kind)
        stub.RunTimers()
        for _ = 1, #ns.Sweep.STEPS[kind] do
            ns.Sweep.Step(1)
            stub.RunTimers()
        end
        ns.Sweep.Stop()
        stub.RunTimers()
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("/dui sweep raid works right after /dui test", function()
    local DUI, ns = login()
    DUI.RunCommand("test")
    stub.RunTimers()
    DUI.RunCommand("sweep raid")
    stub.RunTimers()
    T.truthy(DUI.testMode, "test mode on")
    T.eq(ns.Sweep.kind, "raid")
    T.truthy(DaylightUISweep:IsShown(), "panel still up")
    T.truthy(ns.Raid.group.sweep, "sweep set")
    ns.Sweep.Step(1)
    stub.RunTimers()
    T.eq(ns.Sweep.index, 2, "Next works after the switch")
    T.truthy(string.find(DaylightUISweep.label:GetText() or "", ns.Sweep.STEPS.raid[2].label, 1, true), "label")
    ns.Sweep.Stop()
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("a sweep with no saved settings yet doesn't error when a button is dressed", function()
    local _, ns = login()
    local g = ns.Party.group
    g.sweep = { cfg = ns.module.db.party, text = ns.module.db.partyText }
    local old = g.opts.config
    g.opts.config = function() return nil end
    local b = CreateFrame("Button", "DaylightUIPartyHeaderUnitButton9", g.header)
    b:SetAttribute("unit", "party1")
    stub.units.party1 = stub.units.party1 or { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 }
    local ok, err = pcall(function() g:Dress(b) end)
    g.opts.config = old
    g.sweep = nil
    T.truthy(ok, tostring(err))
end)

T.test("a sweep step waiting on combat does nothing once the sweep has stopped", function()
    local DUI, ns = login()
    DUI.RunCommand("sweep party")
    stub.RunTimers()
    stub.combat = true          -- in combat, without the event that ends test mode
    ns.Sweep.Step(1)            -- its layout waits for the fight to end
    ns.Sweep.Stop()
    stub.LeaveCombat()
    stub.RunTimers()
    T.isnil(ns.Party.group.sweep)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
