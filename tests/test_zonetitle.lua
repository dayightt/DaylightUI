local stub = require("stub")

-- The zone title (QoL/ZoneTitle.lua). A big title on a zone change, a small line
-- on a subzone change, and the game's four zone texts hidden at alpha 0 while on.

local where = { zone = "Elwynn Forest", sub = "Goldshire", pvp = "contested" }

local function login(zoneTitle, toasts)
    where.zone, where.sub, where.pvp = "Elwynn Forest", "Goldshire", "contested"
    stub.Load({ qol = true, before = function()
        local zf = CreateFrame("Frame", "ZoneTextFrame", UIParent)
        local sf = CreateFrame("Frame", "SubZoneTextFrame", UIParent)
        _G.ZoneTextString = zf:CreateFontString("ZoneTextString")
        _G.PVPInfoTextString = zf:CreateFontString("PVPInfoTextString")
        _G.SubZoneTextString = sf:CreateFontString("SubZoneTextString")
        _G.PVPArenaTextString = sf:CreateFontString("PVPArenaTextString")
        _G.GetZoneText = function() return where.zone end
        _G.GetSubZoneText = function() return where.sub end
        _G.C_PvP = _G.C_PvP or {}
        _G.C_PvP.GetZonePVPInfo = function() return where.pvp, where.pvpSub, where.faction end
        _G.CONTESTED_TERRITORY = "(Contested Territory)"
        _G.SANCTUARY_TERRITORY = "(Sanctuary)"
        _G.FACTION_CONTROLLED_TERRITORY = "(%s Territory)"
        _G.FREE_FOR_ALL_TERRITORY = "(Free-for-All PvP Zone)"
        _G.COMBAT_ZONE = "(Combat Zone)"
        if toasts then
            -- The game's toast manager. IsCurrentlyToasting returns the shown toast, or nil.
            local m = CreateFrame("Frame", "EventToastManagerFrame", UIParent)
            m.IsCurrentlyToasting = function(self) return self.currentDisplayingToast end
            m:Hide()
        end
    end })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    if zoneTitle ~= nil then DaylightUI:Set("QoL", "zoneTitle", zoneTitle) end
    return stub.qol.ZoneTitle
end

local function settle()
    local d = DaylightUI.Motion.Driver()
    for _ = 1, 120 do
        if not (d and d:GetScript("OnUpdate")) then return end
        stub.RunOnUpdate(d, 1 / 30)
    end
end

local function plain(s) return (s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end

local function finish() stub.RunTimers(); settle() end

T.test("zone title: a new zone plays the name, line, subzone and PvP line, then goes away", function()
    login()
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    local f = _G.DaylightUIZoneTitle
    T.truthy(f and f:IsShown(), "shown on a zone change")
    T.eq(plain(f.name:GetText()), "Elwynn Forest")
    T.eq(f.sub:GetText(), "Goldshire")
    T.eq(f.pvp:GetText(), "(Contested Territory)")
    T.falsy(f:IsMouseEnabled(), "takes no clicks")
    stub.FireEvent("ZONE_CHANGED")   -- the game often sends it with the new area
    T.eq(f.sub:GetAlpha(), 0, "the subzone waits")
    settle()
    T.eq(f.name:GetAlpha(), 1, "the name is in")
    T.truthy(f.left:GetWidth() > 10, "the line has drawn out")
    stub.RunTimers()
    T.eq(f.sub:GetAlpha(), 1, "the subzone is in")
    T.eq(f.pvp:GetAlpha(), 1, "the PvP line is in")
    settle()
    T.falsy(f:IsShown(), "gone after the hold")
end)

T.test("zone title: follows the accent (the sweep, or one color)", function()
    login()
    local DUI = DaylightUI
    stub.SetUnits{ player = { name = "Me", class = "MAGE", isPlayer = true } }
    local f
    local function play(accent, color)
        DUI:Set("general", "accent", accent)
        if color then DUI:Set("general", "accentColor", color) end
        stub.FireEvent("ZONE_CHANGED_NEW_AREA")
        f = _G.DaylightUIZoneTitle
        return f.name:GetText()
    end
    T.eq(play("gradient"), DUI.GradientText("Elwynn Forest"), "gradient: the Daylight sweep")
    T.rgb({ f.name:GetTextColor() }, { 1, 1, 1 })
    local g = f.right.__gradient[3]
    T.rgb({ g.r, g.g, g.b }, { DUI.Style.SweepAt(1) }, "the line runs out to the sweep's end")
    T.eq(play("custom", { 0.2, 0.6, 0.4 }), "Elwynn Forest", "one color: plain text")
    T.rgb({ f.name:GetTextColor() }, { 0.2, 0.6, 0.4 })
    g = f.left.__gradient[3]
    T.rgb({ g.r, g.g, g.b }, { 0.2, 0.6, 0.4 }, "the line in the accent")
    play("class")
    T.rgb({ f.name:GetTextColor() }, { DUI.Style.Accent() }, "class: the class color")
    play("daylight")
    T.rgb({ f.name:GetTextColor() }, DUI.Style.ACCENT, "daylight: the warm gray")
    finish()
end)

T.test("zone title: friendly and sanctuary zones read the game's own strings", function()
    local ZT = login()
    where.pvp, where.faction = "friendly", "Alliance"
    T.eq((ZT.PvP()), "(Alliance Territory)")
    where.pvp = "sanctuary"
    T.eq((ZT.PvP()), "(Sanctuary)")
    where.pvp = nil
    T.eq((ZT.PvP()), "")
end)

T.test("zone title: a subzone change shows only the small subzone line", function()
    login()
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    finish()
    local f = _G.DaylightUIZoneTitle
    where.sub = "Lion's Pride Inn"
    stub.FireEvent("ZONE_CHANGED_INDOORS")
    T.truthy(f:IsShown(), "shown for the subzone")
    T.eq(f.sub:GetText(), "Lion's Pride Inn")
    T.eq(f.sub:GetAlpha(), 1)
    T.eq(f.name:GetAlpha(), 0, "no zone name")
    T.eq(f.pvp:GetAlpha(), 0, "no PvP line")
    T.falsy(f.left:IsShown() or f.right:IsShown(), "no line, not even a 1 px dot above the word")
    finish()
    T.falsy(f:IsShown(), "gone after the short hold")
    -- Back out into the zone itself (no subzone): nothing.
    where.sub = ""
    stub.FireEvent("ZONE_CHANGED")
    T.falsy(f:IsShown(), "an empty subzone shows nothing")
end)

T.test("zone title: a subzone change during the whole title changes its line in place", function()
    login()
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    settle()
    local f = _G.DaylightUIZoneTitle
    where.sub = "Lion's Pride Inn"
    stub.FireEvent("ZONE_CHANGED_INDOORS")
    T.eq(f.name:GetAlpha(), 1, "the zone name stays")
    T.eq(f.sub:GetText(), "Lion's Pride Inn")
    finish()
    T.falsy(f:IsShown())
end)

T.test("zone title: the zone name changing on ZONE_CHANGED plays the whole title", function()
    login()
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    finish()
    local f = _G.DaylightUIZoneTitle
    where.zone, where.sub = "Westfall", ""
    stub.FireEvent("ZONE_CHANGED")
    T.truthy(f:IsShown())
    T.eq(plain(f.name:GetText()), "Westfall")
    settle()
    T.eq(f.name:GetAlpha(), 1, "the name is in")
end)

T.test("zone title: the game's zone texts are hidden while on, back when off", function()
    login()
    for _, n in ipairs({ "ZoneTextString", "SubZoneTextString", "PVPInfoTextString", "PVPArenaTextString" }) do
        T.eq(_G[n]:GetAlpha(), 0, n .. " hidden")
    end
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    DaylightUI:Set("QoL", "zoneTitle", false)
    for _, n in ipairs({ "ZoneTextString", "SubZoneTextString", "PVPInfoTextString", "PVPArenaTextString" }) do
        T.eq(_G[n]:GetAlpha(), 1, n .. " back")
    end
    T.falsy(_G.DaylightUIZoneTitle:IsShown(), "a show in progress stops")
    finish()
    where.zone = "Westfall"
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    T.falsy(_G.DaylightUIZoneTitle:IsShown(), "switched off, nothing plays")
end)

T.test("zone title: skipped while the level-up shows; a level-up takes its place", function()
    login()
    stub.FireEvent("PLAYER_LEVEL_UP", 11, 18, 15, 1, 0, 2, 0, 1, 0)
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    local f = _G.DaylightUIZoneTitle
    T.falsy(f and f:IsShown(), "not over the level-up")
    finish()
    -- The other way round: the title steps aside for the level-up.
    where.zone = "Westfall"
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    f = _G.DaylightUIZoneTitle
    T.truthy(f:IsShown())
    stub.FireEvent("PLAYER_LEVEL_UP", 12, 18, 15, 1, 0, 2, 0, 1, 0)
    settle()
    T.falsy(f:IsShown(), "gone for the level-up")
end)

T.test("zone title: a zone change during the level-up plays once it has gone", function()
    login()
    stub.FireEvent("PLAYER_LEVEL_UP", 11, 18, 15, 1, 0, 2, 0, 1, 0)
    where.zone, where.sub = "Westfall", "Sentinel Hill"
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    T.falsy(_G.DaylightUIZoneTitle and _G.DaylightUIZoneTitle:IsShown(), "waits for the level-up")
    _G.DaylightUILevelUp:Hide()
    local f = _G.DaylightUIZoneTitle
    T.truthy(f and f:IsShown(), "the zone title plays when the level-up ends")
    T.eq(plain(f.name:GetText()), "Westfall")
    T.eq(f.sub:GetText(), "Sentinel Hill")
end)

T.test("zone title: a zone change during one of the game's toasts plays once it ends", function()
    login(nil, true)
    local m = _G.EventToastManagerFrame
    m.currentDisplayingToast = { toastInfo = { eventType = 1 } }
    m:Show()
    where.zone = "Westfall"
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    T.falsy(_G.DaylightUIZoneTitle and _G.DaylightUIZoneTitle:IsShown(), "not over the toast")
    m.currentDisplayingToast = nil
    m:Hide()
    local f = _G.DaylightUIZoneTitle
    T.truthy(f and f:IsShown(), "plays when the toast ends")
    T.eq(plain(f.name:GetText()), "Westfall")
    m:Show(); m:Hide()
    T.eq(plain(f.name:GetText()), "Westfall", "played once")
end)

T.test("zone title: motion off shows at once and hides after the hold, no tweens", function()
    login()
    DaylightUI:Set("general", "motion", false)
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    local f = _G.DaylightUIZoneTitle
    T.truthy(f:IsShown())
    T.eq(f.name:GetAlpha(), 1, "the name is in at once")
    T.truthy(f.left:GetWidth() > 10, "the line is drawn at once")
    stub.RunTimers()
    T.falsy(f:IsShown(), "gone after the hold with nothing to settle")
end)

T.test("zone title: plays in combat too", function()
    login()
    stub.EnterCombat()
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    T.truthy(_G.DaylightUIZoneTitle:IsShown(), "shown in a fight")
    finish()
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("zone title: the preview and /dui zone play it", function()
    local ZT = login()
    ZT.Preview()
    local f = _G.DaylightUIZoneTitle
    T.truthy(f:IsShown())
    T.eq(plain(f.name:GetText()), "Elwynn Forest")
    T.eq(f.sub:GetText(), "Goldshire")
    T.eq(f.pvp:GetText(), "(Contested Territory)")
    finish()
    DaylightUI.RunCommand("zone")
    T.truthy(f:IsShown(), "the command plays it")
end)

-- The options page's settings.

T.test("zone title: subzone, PvP line and subzone changes can each be turned off", function()
    login()
    DaylightUI:Set("QoL", "zoneTitleSub", false)
    DaylightUI:Set("QoL", "zoneTitlePvP", false)
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    local f = _G.DaylightUIZoneTitle
    T.eq(f.sub:GetText(), "", "no subzone")
    T.eq(f.pvp:GetText(), "", "no PvP line")
    finish()
    where.sub = "Lion's Pride Inn"
    stub.FireEvent("ZONE_CHANGED_INDOORS")
    T.falsy(f:IsShown(), "no subzone line on its own either")
    DaylightUI:Set("QoL", "zoneTitleSub", true)
    DaylightUI:Set("QoL", "zoneTitleSubAlone", false)
    where.sub = "Goldshire"
    stub.FireEvent("ZONE_CHANGED")
    T.falsy(f:IsShown(), "subzone changes off: nothing for a subzone")
    where.zone = "Westfall"
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    T.truthy(f:IsShown(), "a new zone still plays")
    T.eq(f.sub:GetText(), "Goldshire", "with its subzone")
end)

T.test("zone title: capitals and a longer hold", function()
    login()
    DaylightUI:Set("QoL", "zoneTitleCaps", true)
    DaylightUI:Set("QoL", "zoneTitleHold", 6)
    -- The fake timers run without waiting, so note how long each was asked to wait.
    local after, waits = C_Timer.After, {}
    C_Timer.After = function(t, fn) waits[#waits + 1] = t; return after(t, fn) end
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    C_Timer.After = after
    local f = _G.DaylightUIZoneTitle
    T.eq(plain(f.name:GetText()), "ELWYNN FOREST")
    local longest = 0
    for _, t in ipairs(waits) do longest = math.max(longest, t) end
    T.near(longest, DaylightUI.Motion.SLOW + 6, 0.001, "it leaves after the 6 s hold")
    finish()
end)

T.test("zone title: the name's color can be the zone's PvP color, white or one color", function()
    login()
    local f
    local function play(mode, custom)
        DaylightUI:Set("QoL", "zoneTitleColor", mode)
        if custom then DaylightUI:Set("QoL", "zoneTitleColorCustom", custom) end
        stub.FireEvent("ZONE_CHANGED_NEW_AREA")
        f = _G.DaylightUIZoneTitle
        finish()
    end
    play("zone")
    T.eq(f.name:GetText(), "Elwynn Forest", "plain text")
    T.rgb({ f.name:GetTextColor() }, stub.qol.ZoneTitle.COLORS.contested, "contested amber")
    local g = f.left.__gradient[3]
    T.rgb({ g.r, g.g, g.b }, stub.qol.ZoneTitle.COLORS.contested, "the line too")
    where.pvp = nil
    play("zone")
    T.rgb({ f.name:GetTextColor() }, { DaylightUI.Style.Accent() }, "no PvP color: the accent")
    play("white")
    T.rgb({ f.name:GetTextColor() }, DaylightUI.Style.INK.TITLE)
    play("custom", { 0.3, 0.5, 0.9 })
    T.rgb({ f.name:GetTextColor() }, { 0.3, 0.5, 0.9 })
end)

T.test("zone title: its own font and text sizes", function()
    login()
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    local f = _G.DaylightUIZoneTitle
    local before = f.name:GetFont()
    local pick
    for _, name in ipairs(DaylightUI.Style.FONT_ORDER) do
        if DaylightUI.Style.FONTS[name].file ~= before then pick = name break end
    end
    DaylightUI:Set("QoL", "zoneTitleFont", pick)
    stub.RunTimers()   -- the font comes with the next repaint
    T.eq((f.name:GetFont()), DaylightUI.Style.FONTS[pick].file, "the name in the picked font")
    T.eq((f.sub:GetFont()), DaylightUI.Style.FONTS[pick].file, "the subzone too")
    DaylightUI:Set("QoL", "zoneTitleNameSize", 40)
    DaylightUI:Set("QoL", "zoneTitleSubSize", 20)
    finish()
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    T.eq(select(2, f.name:GetFont()), 40)
    T.eq(select(2, f.sub:GetFont()), 20)
    T.eq(select(2, f.pvp:GetFont()), 18, "the PvP line a little smaller")
end)

T.test("zone title: it has a mover, and its scale is the piece scale", function()
    login()
    local M = DaylightUI.Movers
    local holder = _G.DaylightUIZoneTitleHolder
    T.truthy(holder, "a holder for the handle")
    M.SetPieceScale("qol.zone", 1.5)
    T.near(holder:GetScale(), 1.5 * M.Scale(), 0.001, "the holder takes the piece scale")
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    T.eq(_G.DaylightUIZoneTitle:GetParent(), holder, "the title inside it")
end)

T.test("zone title: unlock mode shows it standing still, without holding anything up", function()
    local ZT = login()
    DaylightUI.Movers.unlocked = true
    DaylightUI.Fire("UnlockChanged", true)
    local f = _G.DaylightUIZoneTitle
    T.truthy(f:IsShown(), "the sample")
    T.eq(f.name:GetAlpha(), 1)
    T.falsy(ZT.Showing(), "a sample doesn't hold the reputation banner")
    stub.RunTimers()
    settle()
    T.truthy(f:IsShown(), "it stays")
    DaylightUI:Set("QoL", "zoneTitleCaps", true)
    T.eq(plain(f.name:GetText()), "ELWYNN FOREST", "a change shows on the sample at once")
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    T.truthy(ZT.Showing(), "a real zone change plays over it")
    DaylightUI.Movers.unlocked = false
    DaylightUI.Fire("UnlockChanged", false)
    finish()
    T.falsy(f:IsShown())
end)

T.test("zone title: the flourishes, a light across the name, a haze and a diamond", function()
    login()
    DaylightUI:Set("QoL", "zoneTitleHaze", true)
    DaylightUI:Set("QoL", "zoneTitleGem", true)
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    local f = _G.DaylightUIZoneTitle
    T.falsy(f.gem:IsShown(), "the diamond waits for the line")
    settle()
    T.truthy(f.gem:IsShown(), "the diamond is in")
    T.near(f.gem:GetWidth(), stub.qol.ZoneTitle.GEM_SIZE, 0.01)
    T.truthy(f.haze:GetAlpha() > 0, "the haze glows")
    stub.RunTimersOnce()
    T.truthy(f.shine:IsShown(), "the light runs across the name")
    finish()
    DaylightUI:Set("QoL", "zoneTitleShine", false)
    DaylightUI:Set("QoL", "zoneTitleHaze", false)
    DaylightUI:Set("QoL", "zoneTitleGem", false)
    where.zone = "Westfall"
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    settle()
    stub.RunTimersOnce()
    T.falsy(f.gem:IsShown(), "no diamond")
    T.eq(f.haze:GetAlpha(), 0, "no haze")
    T.falsy(f.shine:IsShown(), "no light")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("zone title: the subzone, PvP line and line under the name each take their own color", function()
    login()
    local S = DaylightUI.Style
    local f
    local function play()
        stub.FireEvent("ZONE_CHANGED_NEW_AREA")
        f = _G.DaylightUIZoneTitle
    end
    local function line() local g = f.left.__gradient[3]; return { g.r, g.g, g.b } end
    play()
    T.rgb({ f.sub:GetTextColor() }, S.INK.LABEL, "subzone: tan by default")
    T.rgb({ f.pvp:GetTextColor() }, stub.qol.ZoneTitle.COLORS.contested, "PvP: the zone's color by default")
    finish()

    DaylightUI:Set("QoL", "zoneTitleColor", "custom")
    DaylightUI:Set("QoL", "zoneTitleColorCustom", { 0.3, 0.5, 0.9 })
    DaylightUI:Set("QoL", "zoneTitleSubColor", "name")
    DaylightUI:Set("QoL", "zoneTitlePvPColor", "white")
    DaylightUI:Set("QoL", "zoneTitleLineColor", "custom")
    DaylightUI:Set("QoL", "zoneTitleLineColorCustom", { 0.9, 0.2, 0.2 })
    play()
    T.rgb({ f.sub:GetTextColor() }, { 0.3, 0.5, 0.9 }, "subzone: same as the name")
    T.rgb({ f.pvp:GetTextColor() }, S.INK.VALUE, "PvP: white")
    T.rgb(line(), { 0.9, 0.2, 0.2 }, "the line: its own color")
    T.rgb({ f.gem:GetVertexColor() }, { 0.9, 0.2, 0.2 }, "the diamond follows the line")
    finish()

    DaylightUI:Set("QoL", "zoneTitleSubColor", "custom")
    DaylightUI:Set("QoL", "zoneTitleSubColorCustom", { 0.1, 0.8, 0.3 })
    DaylightUI:Set("QoL", "zoneTitlePvPColor", "custom")
    DaylightUI:Set("QoL", "zoneTitlePvPColorCustom", { 0.8, 0.8, 0.1 })
    DaylightUI:Set("QoL", "zoneTitleLineColor", "zone")
    play()
    T.rgb({ f.sub:GetTextColor() }, { 0.1, 0.8, 0.3 }, "subzone: one color")
    T.rgb({ f.pvp:GetTextColor() }, { 0.8, 0.8, 0.1 }, "PvP: one color")
    T.rgb(line(), stub.qol.ZoneTitle.COLORS.contested, "the line: the zone's PvP color")
    finish()

    -- A subzone on its own takes its color too.
    where.sub = "Lion's Pride Inn"
    stub.FireEvent("ZONE_CHANGED_INDOORS")
    T.rgb({ f.sub:GetTextColor() }, { 0.1, 0.8, 0.3 }, "a lone subzone in its color")
    finish()
    DaylightUI:Set("QoL", "zoneTitleSubColor", "name")
    where.sub = "Goldshire"
    stub.FireEvent("ZONE_CHANGED")
    T.rgb({ f.sub:GetTextColor() }, { 0.3, 0.5, 0.9 }, "a lone subzone follows the name's color")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
