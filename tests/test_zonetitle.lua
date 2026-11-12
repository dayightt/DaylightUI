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
