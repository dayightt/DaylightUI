local stub = require("stub")

local function login(before)
    local DUI, ns = stub.Load({ module = true, before = before })
    return DUI, ns
end

-- Runs the motion kit's tweens a step, or to their end.
local function step(dt)
    local d = DaylightUI.Motion.Driver()
    if d and d:GetScript("OnUpdate") then stub.RunOnUpdate(d, dt or 0.1) end
end

local function settle()
    for _ = 1, 60 do step(1 / 60) end
end

T.test("players get their class icon in a ring over the outer end", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Stabby", isPlayer = true, class = "ROGUE", health = 5, maxHealth = 10 }
    end)
    local f = ns.frames.player
    local p = f.portrait
    ns.UF.UpdateAll(f, true)
    T.truthy(p:IsShown())
    T.eq(p.icon.__texture, DUI.MEDIA .. "class\\rogue.tga")
    T.falsy(p.model:IsShown())
    local pt, rel, rp = p:GetPoint(1)
    T.eq(pt, "CENTER"); T.eq(rel, f); T.eq(rp, "LEFT")
    T.truthy(f.__hitRect[1] < 0, "the ring is clickable")
    T.truthy(f.tabInset > ns.UF.TAB_INSET, "the name tab clears the ring")
    T.falsy(p.rim:IsShown())
    T.truthy(p.icon:GetWidth() > p.mask:GetWidth(), "overfills, cropped evenly by the round mask")
end)

T.test("NPCs, and players whose class is secret, show their face", function()
    local _, ns = login()
    local f = ns.frames.target
    stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2, class = "WARRIOR" }
    ns.UF.UpdateAll(f, true)
    T.eq(f.portrait.icon.__portraitUnit, "target")
    stub.units.target = { name = "X", isPlayer = stub.Secret(true), class = "MAGE" }
    f.portrait.icon.__portraitUnit = nil
    ns.UF.UpdateAll(f, true)
    T.eq(f.portrait.icon.__portraitUnit, "target")
end)

T.test("2D, 3D and no portrait", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Stabby", isPlayer = true, class = "ROGUE" }
    end)
    local f = ns.frames.player
    DUI:Set("UnitFrames", "player.portrait", "3d")
    T.truthy(f.portrait.model:IsShown())
    T.falsy(f.portrait.icon:IsShown())
    T.eq(f.portrait.model.__modelUnit, "player")
    T.eq(f.portrait.model.__camScale, ns.UF.MODEL_CLOSER, "a little closer")
    T.truthy(f.portrait.rim:IsShown(), "the bezel hides the model's square edges")
    DUI:Set("UnitFrames", "player.portrait", "2d")
    T.falsy(f.portrait.model:IsShown())
    T.eq(f.portrait.icon.__portraitUnit, "player")
    T.falsy(f.portrait.rim:IsShown(), "faces run up to the ring")
    DUI:Set("UnitFrames", "player.portrait", "none")
    T.falsy(f.portrait:IsShown())
    T.eq(f.tabInset, ns.UF.TAB_INSET)
    T.eq(f.__hitRect[1], 0)
end)

-- A 3D model ignores its parents' alpha, UIParent's too: the face stayed on
-- screen while its frame faded (fishing, the campfire, the AFK screen). The
-- model takes the portrait's real alpha itself.
T.test("a 3D portrait fades with its frame and with the whole UI", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Stabby", isPlayer = true, class = "ROGUE" }
    end)
    local f = ns.frames.player
    DUI:Set("UnitFrames", "player.portrait", "3d")
    local m = f.portrait.model
    local F = DUI.Fade
    local function run()
        for _ = 1, 20 do
            stub.Advance(0.5)
            F.Step()
            for _ = 1, 30 do stub.RunOnUpdate(F.driver, 1 / 60) end
        end
    end
    run()
    T.near(m:GetAlpha(), 1, 0.001, "shown with its frame")
    F.Hush("test", { "UnitFrames." })
    run()
    T.near(f:GetAlpha(), 0, 0.001, "the frame faded (a campfire or fishing hush)")
    T.near(m:GetAlpha(), 0, 0.001, "the face goes with it")
    F.Unhush("test", true)
    run()
    T.near(m:GetAlpha(), 1, 0.001, "and comes back with it")
    F.SetUIAlpha(0.25)
    T.near(m:GetAlpha(), 0.25, 0.001, "the whole UI fading (the AFK screen, the NPC scene) takes it too")
    F.SetUIAlpha(1)
    T.near(m:GetAlpha(), 1, 0.001)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A secret range answer gives the frame a secret alpha, and then the client
-- hands addon code no effective alpha at all: SetAlpha(nothing) errored on every
-- range tick in a party and every step of a whole-UI fade (a sleeping bag).
T.test("a 3D portrait follows a secret range fade and the whole UI", function()
    local DUI, ns = login()
    local f = ns.frames.target
    stub.units.target = { name = "Pal", isPlayer = true, class = "MAGE", friend = true, party = true,
        inRange = stub.Secret(false) }
    DUI:Set("UnitFrames", "target.portrait", "3d")
    ns.UF.UpdateAll(f, true)
    local m = f.portrait.model
    T.truthy(m:IsShown())
    ns.UF.UpdateRange(f)
    T.truthy(f.__alphaFromBoolean, "the frame's alpha came from the secret answer")
    local how = m.__alphaFromBoolean
    T.truthy(how, "the model takes the same secret answer")
    local own = f.__alphaFromBoolean
    T.eq(how[1], own[1])
    T.near(how[2], own[2], 0.001); T.near(how[3], own[3], 0.001)
    DUI.Fade.SetUIAlpha(0.5)
    how = m.__alphaFromBoolean
    T.near(how[2], own[2] * 0.5, 0.001, "times the whole UI's alpha")
    T.near(how[3], own[3] * 0.5, 0.001)
    DUI.Fade.SetUIAlpha(1)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The full health wait hands the frame a secret alpha from a curve: the model
-- gets its own from the same curve.
T.test("a 3D portrait follows the full health wait's secret alpha", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Stabby", isPlayer = true, class = "ROGUE" }
    end)
    local f = ns.frames.player
    DUI:Set("UnitFrames", "player.portrait", "3d")
    DUI:Set("UnitFrames", "player.fade.fullHealth", true)
    local m = f.portrait.model
    stub.units.player.pct = stub.Secret(1)
    local had = _G.C_CurveUtil
    _G.C_CurveUtil = { CreateCurve = function()
        return { AddPoint = function() end, SetType = function() end }
    end }
    ns.UF.fullCurves = {}
    ns.UF.PaintFade(f, 0.3)
    T.truthy(issecretvalue(f.__alpha), "the frame's alpha is the curve's secret answer")
    T.truthy(issecretvalue(m.__alpha), "the model takes its own answer from the same curve")
    DUI.Fade.SetUIAlpha(0.5)
    T.truthy(issecretvalue(m.__alpha))
    DUI.Fade.SetUIAlpha(1)
    _G.C_CurveUtil = had
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("icon styles come from the icon pack only when it is installed", function()
    local _, ns = login()
    local UF = ns.UF
    local file, l, r, t, b = UF.ClassIcon("PRIEST", "fabledrealm")
    T.eq(file, DaylightUI.MEDIA .. "class\\priest.tga", "no pack: our own")
    T.eq(r, 1)
    stub.installedAddOns.JiberishIcons = true
    file, l, r, t, b = UF.ClassIcon("PRIEST", "fabledrealm")
    T.eq(file, "Interface\\AddOns\\JiberishIcons\\Media\\Class\\fabledrealm.tga")
    T.near(l, 0.25); T.near(r, 0.375); T.near(t, 0.125); T.near(b, 0.25)
    T.eq((UF.ClassIcon("PRIEST", "daylight")), DaylightUI.MEDIA .. "class\\priest.tga")
end)

T.test("a class's own pick beats the icon style", function()
    local _, ns = login()
    local UF = ns.UF
    stub.installedAddOns.JiberishIcons = true
    local picks = { PRIEST = "fabledregalia", MAGE = "daylight" }
    T.eq((UF.ClassIcon("PRIEST", "fabled", picks)), "Interface\\AddOns\\JiberishIcons\\Media\\Class\\fabledregalia.tga")
    T.eq((UF.ClassIcon("MAGE", "fabled", picks)), DaylightUI.MEDIA .. "class\\mage.tga")
    T.eq((UF.ClassIcon("ROGUE", "fabled", picks)), "Interface\\AddOns\\JiberishIcons\\Media\\Class\\fabled.tga", "no pick: the style")
end)

T.test("a spec pick uses that spec's square on the spec sheet", function()
    local _, ns = login()
    local UF = ns.UF
    stub.installedAddOns.JiberishIcons = true
    -- Shadow Priest is the 22nd icon, row 2 column 5 of the 8 x 8 sheet.
    local file, l, r, t, b = UF.ClassIcon("PRIEST", "daylight", { PRIEST = "spec:258" })
    T.eq(file, "Interface\\AddOns\\JiberishIcons\\Media\\Spec\\fabledspecializations.tga")
    T.near(l, 0.625); T.near(r, 0.75); T.near(t, 0.25); T.near(b, 0.375)
    -- Another class's spec is never used.
    T.eq((UF.ClassIcon("MAGE", "daylight", { MAGE = "spec:258" })), DaylightUI.MEDIA .. "class\\mage.tga")
end)

T.test("without the pack, picks fall back to our own icons", function()
    local _, ns = login()
    local UF = ns.UF
    T.eq((UF.ClassIcon("PRIEST", "fabled", { PRIEST = "spec:258" })), DaylightUI.MEDIA .. "class\\priest.tga")
    T.eq((UF.ClassIcon("PRIEST", "fabled", { PRIEST = "fabledmyth" })), DaylightUI.MEDIA .. "class\\priest.tga")
end)

T.test("a saved class pick shows on the player's portrait", function()
    local DUI, ns = login(function()
        stub.installedAddOns.JiberishIcons = true
        stub.units.player = { name = "Stabby", isPlayer = true, class = "ROGUE", health = 5, maxHealth = 10 }
    end)
    local p = ns.frames.player.portrait
    DUI:Set("UnitFrames", "portraits.classIcons.ROGUE", "spec:260")
    T.eq(p.icon.__texture, "Interface\\AddOns\\JiberishIcons\\Media\\Spec\\fabledspecializations.tga")
    DUI:Set("UnitFrames", "portraits.classIcons.ROGUE", nil)
    T.eq(p.icon.__texture, DUI.MEDIA .. "class\\rogue.tga", "back to the style")
end)

T.test("party tiles follow the icon style and the class picks too", function()
    local DUI, ns = login(function()
        stub.installedAddOns.JiberishIcons = true
    end)
    DUI:Set("UnitFrames", "portraits.icons", "fabledpixelsv2")
    stub.RunTimers()
    local h = ns.Party.group.header
    local b = CreateFrame("Button", "DaylightUIPartyHeaderUnitButton1", h)
    b:SetAttribute("unit", "party1")
    stub.units.party1 = { name = "Funs", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 }
    h.initialConfigFunction(h, b:GetName())
    ns.UF.UpdateAll(b, true)
    local pack = "Interface\\AddOns\\JiberishIcons\\Media\\"
    T.eq(b.portrait.icon.__texture, pack .. "Class\\fabledpixelsv2.tga", "the icon style")
    DUI:Set("UnitFrames", "portraits.classIcons.WARRIOR", "spec:72")
    stub.RunTimers()
    T.eq(b.portrait.icon.__texture, pack .. "Spec\\fabledspecializations.tga", "a class's pick")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("the Look page has a line of icons per class, only with the pack", function()
    local function picker(DUI)
        DUI.OptionsPanel.Show("UnitFrames.colors")
        for _, card in ipairs(DUI.OptionsPanel.PageFrame().cards) do
            for _, row in ipairs(card.rows) do
                if row.item.label == "Icon per class" then return row end
            end
        end
    end
    local DUI = login()
    local row = picker(DUI)
    T.truthy(row, "the row exists")
    T.falsy(row:IsShown(), "hidden without the pack")

    DUI = login(function() stub.installedAddOns.JiberishIcons = true end)
    row = picker(DUI)
    T.truthy(row:IsShown())
    T.eq(#row.lines, 9)
    local warrior = row.lines[1]
    T.truthy(warrior.cells[1].ring:IsShown(), "no pick: the first icon is ringed")
    local fury
    for _, b in ipairs(warrior.cells) do if b.key == "spec:72" then fury = b end end
    fury:GetScript("OnClick")(fury)
    T.eq(DUI:Get("UnitFrames", "portraits.classIcons.WARRIOR"), "spec:72")
    T.truthy(fury.ring:IsShown()); T.falsy(warrior.cells[1].ring:IsShown())
    warrior.cells[1]:GetScript("OnClick")(warrior.cells[1])
    T.eq(DUI:Get("UnitFrames", "portraits.classIcons.WARRIOR"), nil, "first icon clears the pick")
end)

T.test("every class in the game has a row of choices", function()
    local _, ns = login()
    local UF = ns.UF
    T.eq(#UF.ICON_CLASSES, 9)
    local keys = UF.ClassIconChoices("DRUID")
    T.eq(keys[1], "daylight")
    local specs = 0
    for _, k in ipairs(keys) do
        if k:sub(1, 5) == "spec:" then specs = specs + 1 end
        T.truthy(UF.ClassIconName(k), k)
    end
    T.eq(specs, 4, "four druid specs")
    T.eq(#keys, 1 + (#UF.ICON_STYLE_ORDER - 1) + 4)
end)

T.test("the icon pack's old folder name still counts as installed", function()
    local _, ns = login()
    local UF = ns.UF
    T.falsy(UF.HasIconPack())
    stub.installedAddOns.ElvUI_JiberishIcons = true
    T.truthy(UF.HasIconPack())
    T.eq((UF.ClassIcon("PRIEST", "fabled")), "Interface\\AddOns\\ElvUI_JiberishIcons\\Media\\Class\\fabled.tga")
end)

T.test("the icon pack's old folder never offers or draws what it doesn't have", function()
    local _, ns = login()
    local UF = ns.UF
    stub.installedAddOns.ElvUI_JiberishIcons = true
    local own = DaylightUI.MEDIA .. "class\\priest.tga"
    T.eq((UF.ClassIcon("PRIEST", "fabledregalia")), own, "no Regalia sheet there")
    T.eq((UF.ClassIcon("PRIEST", "fabledclass")), own, "no Fabled Class sheet there")
    T.eq((UF.ClassIcon("PRIEST", "fabled", { PRIEST = "spec:258" })), own, "no spec sheet there")

    local function has(list, key)
        for _, k in ipairs(list) do if k == key then return true end end
        return false
    end
    local _, order = UF.IconStyleChoices()
    T.truthy(has(order, "fabled"))
    T.truthy(has(order, "daylight"))
    T.falsy(has(order, "fabledregalia"))
    T.falsy(has(order, "fabledclass"))
    local keys = UF.ClassIconChoices("PRIEST")
    T.truthy(has(keys, "fabledrealm"))
    T.falsy(has(keys, "fabledregalia"))
    T.falsy(has(keys, "spec:258"))

    -- The new folder wins when both are there, and has them all.
    stub.installedAddOns.JiberishIcons = true
    _, order = UF.IconStyleChoices()
    T.eq(#order, #UF.ICON_STYLE_ORDER)
    T.truthy(has(UF.ClassIconChoices("PRIEST"), "spec:258"))
end)

T.test("Ribbon: an elite draws no edge line across the name row (it has no tab to edge)", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "target.style", "ribbon")
    local f = ns.frames.target
    stub.units.target = { name = "Grell", isPlayer = false, reaction = 2, classification = "elite" }
    ns.UF.UpdateAll(f, true)
    T.eq(f.style, "ribbon")
    T.truthy(f.crestShown)
    T.falsy(f.tabEdge:IsShown())
    DUI:Set("UnitFrames", "target.style", "daylight")
    ns.UF.UpdateAll(f, true)
    T.eq(f.style, "daylight")
    T.truthy(f.tabEdge:IsShown(), "back on the Daylight tab")
end)

T.test("elites and rares get the dragon round the normal ring; without a portrait, the badge", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "target.portraitRing", "light")
    local f = ns.frames.target
    local p = f.portrait
    stub.units.target = { name = "Grell", isPlayer = false, reaction = 2, classification = "elite" }
    ns.UF.UpdateAll(f, true)
    T.truthy(p.elite:IsShown())
    T.truthy(p.ring:IsShown(), "the very ring every portrait has stays, the dragon behind it")
    T.eq(p.elite.__texture, ns.UF.DRAGON_FILE)
    T.near(p.elite:GetWidth(), p.ring:GetWidth() / ns.UF.DRAGON_RING, DUI.Pixel.Unit(f) + 0.01,
        "drawn bigger so its ring lines up (rounded to whole pixels)")
    T.eq(p.elite.__texCoord[1], 0, "the target's ring is on the right: the dragon wraps it as drawn")
    T.rgb(p.elite.__vertex, ns.UF.ELITE_RING_COLORS.gold, "gold")
    T.falsy(f.crest:IsShown(), "no badge while the ring shows it")
    stub.units.target.classification = "rare"
    ns.UF.UpdateAll(f, true)
    T.rgb(p.elite.__vertex, ns.UF.ELITE_RING_COLORS.silver, "silver")
    stub.units.target.classification = "normal"
    ns.UF.UpdateAll(f, true)
    T.falsy(p.elite:IsShown()); T.truthy(p.ring:IsShown())
    DUI:Set("UnitFrames", "target.portrait", "none")
    stub.units.target.classification = "elite"
    ns.UF.UpdateAll(f, true)
    local _, rel = f.crest:GetPoint(1)
    T.eq(rel, f.tab)
    T.truthy(f.crest:IsShown())
end)

T.test("the bezel covers a 3D model's straight edges", function()
    local DUI, ns = login()
    -- Measures the classic ring, whose art fills the whole portrait.
    DUI:Set("UnitFrames", "player.portraitLook", "classic")
    DUI:Set("UnitFrames", "player.portrait", "3d")
    stub.RunTimers()
    local p = ns.frames.player.portrait
    local R = p:GetWidth() / 2
    local solidFrom = p.rim:GetWidth() / 2 * 0.84
    T.truthy(solidFrom < p.model:GetWidth() / 2, "solid before the model's edge")
    T.truthy(p.rim:GetWidth() / 2 > R * ns.UF.RING_INNER, "tucked under the ring")
    T.truthy(p.model:GetWidth() / 2 * math.sqrt(2) < R, "model corners stay under the ring")
end)

T.test("the target's class icon is mirrored to face the player", function()
    local _, ns = login(function()
        stub.units.player = { name = "Me", isPlayer = true, class = "PALADIN" }
    end)
    stub.units.target = { name = "You", isPlayer = true, class = "PALADIN", reaction = 5 }
    ns.UF.UpdateAll(ns.frames.target, true)
    ns.UF.UpdateAll(ns.frames.player, true)
    T.eq(ns.frames.target.portrait.icon.__texCoord[1], 1, "flipped")
    T.eq(ns.frames.target.portrait.icon.__texCoord[2], 0)
    T.eq(ns.frames.player.portrait.icon.__texCoord[1], 0, "the player's is not")
end)

T.test("threat: red only while it's on you", function()
    local _, ns = login()
    local f, p = ns.frames.target, ns.frames.target.portrait
    local red = ns.UF.THREAT_COLORS.aggro
    stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2, threat = 3 }
    ns.UF.UpdateAll(f, true)
    T.truthy(p.threatBand:IsShown(), "the bright band over the plain ring")
    T.rgb(p.threatBand.__vertex, red, "aggro")
    T.truthy(p.ring:IsShown(), "the gray ring stays underneath")
    stub.units.target.threat = 0
    ns.UF.UpdateThreat(f)
    T.falsy(p.threatBand:IsShown(), "fighting it, but it's on someone else")
    stub.units.target.threat = nil
    ns.UF.UpdateThreat(f)
    T.falsy(p.threatBand:IsShown(), "not fighting it")
end)

T.test("aggro pulses (so it reads apart from a red enemy bar); orange and motion off don't", function()
    local DUI, ns = login()
    local f, p = ns.frames.target, ns.frames.target.portrait
    stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2, threat = 3 }
    ns.UF.UpdateAll(f, true)
    T.truthy(p.pulseHold:IsShown(), "on you")
    T.truthy(p.pulseAnim:IsPlaying())
    T.truthy(p.halo:IsShown(), "a halo past the ring")
    T.truthy(p.haloAnim:IsPlaying())
    stub.units.target.threat = nil
    ns.UF.UpdateThreat(f)
    T.falsy(p.pulseHold:IsShown(), "gone with the aggro")
    T.falsy(p.pulseAnim:IsPlaying())
    T.falsy(p.halo:IsShown())
    DUI:Set("general", "motion", false)
    stub.units.target.threat = 3
    ns.UF.UpdateAll(f, true)
    T.truthy(p.threatBand:IsShown())
    T.falsy(p.pulseHold:IsShown(), "motion off: a still band")
end)

T.test("a square portrait's aggro halo glows as softly past the band as the ring's", function()
    local DUI, ns = login()
    local UF = ns.UF
    local f, p = ns.frames.target, ns.frames.target.portrait
    stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2, threat = 3 }
    UF.UpdateAll(f, true)
    T.eq(p.haloPeak, UF.HALO_ALPHA, "round: the full halo")
    DUI:Set("UnitFrames", "target.portraitShape", "square")
    stub.RunTimers()
    UF.UpdateAll(f, true)
    T.truthy(p.halo:IsShown())
    T.truthy(p.haloPeak < UF.HALO_ALPHA, "square: a lower peak for its longer edge and corners")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("a secret tanking answer gates the pulse through the client", function()
    local _, ns = login()
    local f, p = ns.frames.target, ns.frames.target.portrait
    local flag = stub.Secret(true)
    local real = _G.UnitDetailedThreatSituation
    _G.UnitDetailedThreatSituation = function() return flag, stub.Secret(3) end
    stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2 }
    ns.UF.UpdateAll(f, true)
    _G.UnitDetailedThreatSituation = real
    T.eq(p.pulseHold.__alphaFromBoolean[1], flag)
end)

T.test("aggro on an elite: the ring alone goes red and pulses; the dragon keeps gold, its eyes catch fire", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "target.portraitRing", "light")
    local f, p = ns.frames.target, ns.frames.target.portrait
    stub.units.target = { name = "Grell", isPlayer = false, reaction = 2, classification = "elite", threat = 2 }
    ns.UF.UpdateAll(f, true)
    T.truthy(p.elite:IsShown())
    T.truthy(p.ring:IsShown(), "the band, fill and pulse lie on the normal ring, which shows")
    T.truthy(p.threatBand:IsShown())
    T.rgb(p.threatBand.__vertex, ns.UF.THREAT_COLORS.aggro)
    T.eq(p.threatBand:GetWidth(), p.ring:GetWidth(), "the red band covers the ring exactly")
    T.rgb(p.elite.__vertex, ns.UF.ELITE_RING_COLORS.gold, "the dragon stays gold")
    T.truthy(p.pulseHold:IsShown(), "the ring pulses")
    T.isnil(p.pulseElite, "no copy of the dragon to pulse")
    T.truthy(p.eye:IsShown(), "fiery eyes")
    T.truthy(p.eyeCore:IsShown(), "white-hot in the middle")
    T.near(p.eyeCore:GetWidth(), p.elite:GetWidth() * ns.UF.DRAGON_EYE.core, 0.01)
    T.rgb(p.eye.__vertex, ns.UF.EYE_FIRE)
    T.eq(p.eye.__blend, "BLEND", "paints over the gold: a light (ADD) on gold stays yellow")
    T.eq(p.eyeCore.__blend, "ADD", "a light in its middle")
    for _, c in ipairs({ ns.UF.EYE_FIRE, ns.UF.EYE_CORE }) do
        T.truthy(c[1] > c[2] * 3 and c[2] <= 0.2, "red, not orange or yellow")
    end
    T.truthy(p.pulseEye:IsShown(), "the eyes flare with the ring's pulse")
    T.near(p.eye:GetWidth(), p.elite:GetWidth() * ns.UF.DRAGON_EYE.size, 0.01, "sized by the dragon")
    local _, _, _, x, y = p.eye:GetPoint(1)
    T.near(x, p.elite:GetWidth() * ns.UF.DRAGON_EYE.x, 0.01, "on the eye")
    T.near(y, p.elite:GetWidth() * ns.UF.DRAGON_EYE.y, 0.01)
    stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2, threat = 2 }
    ns.UF.UpdateAll(f, true)
    T.falsy(p.eye:IsShown(), "no dragon, no eyes")
    T.falsy(p.pulseEye:IsShown())
    stub.units.target = { name = "Grell", isPlayer = false, reaction = 2, classification = "elite", threat = 2 }
    ns.UF.UpdateAll(f, true)
    stub.units.target.threat = nil
    ns.UF.UpdateThreat(f)
    T.falsy(p.threatBand:IsShown())
    T.falsy(p.eye:IsShown(), "the fire goes out")
    T.falsy(p.eyeCore:IsShown())
    T.rgb(p.elite.__vertex, ns.UF.ELITE_RING_COLORS.gold, "gold all along")
end)

T.test("the aggro color: the health bars' red, or your own", function()
    local DUI, ns = login()
    local S = DaylightUI.Style
    T.rgb(ns.UF.THREAT_COLORS.aggro, { S.ReactionColor(2) }, "a hostile health bar's red")
    DUI:Set("UnitFrames", "colors.threat", "custom")
    DUI:Set("UnitFrames", "colors.threatColor", { 1, 0, 1 })
    stub.RunTimers()
    T.rgb(ns.UF.THREAT_COLORS.aggro, { S.Soften(1, 0, 1) }, "your own")
    local f, p = ns.frames.target, ns.frames.target.portrait
    stub.units.target = { name = "Grell", isPlayer = false, reaction = 2, threat = 2 }
    ns.UF.UpdateAll(f, true)
    T.rgb(p.threatBand.__vertex, { S.Soften(1, 0, 1) }, "on the ring")
end)

T.test("without a portrait, the name tab's border shows threat", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "target.portrait", "none")
    local f = ns.frames.target
    local s = DaylightUI.Style.GetShell(f.tab)
    stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2, threat = 3 }
    ns.UF.UpdateAll(f, true)
    T.eq(s.opts.borderColor, ns.UF.THREAT_COLORS.aggro)
    T.rgb(s.border.TOP.__vertex, ns.UF.THREAT_COLORS.aggro, "outline")
    stub.units.target.threat = nil
    ns.UF.UpdateThreat(f)
    T.isnil(s.opts.borderColor)
    T.rgb(s.border.TOP.__vertex, DaylightUI.Style.BORDER, "back to normal")
end)

T.test("a secret tanking answer goes to the client's setters", function()
    local _, ns = login()
    local f, p = ns.frames.target, ns.frames.target.portrait
    local flag = stub.Secret(true)
    local real = _G.UnitDetailedThreatSituation
    _G.UnitDetailedThreatSituation = function() return flag, stub.Secret(3) end
    stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2 }
    ns.UF.UpdateAll(f, true)
    _G.UnitDetailedThreatSituation = real
    T.eq(p.threatBand.__alphaFromBoolean[1], flag)
end)

T.test("threat colors can be turned off", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "target.showThreat", false)
    local f, p = ns.frames.target, ns.frames.target.portrait
    stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2, threat = 3 }
    ns.UF.UpdateAll(f, true)
    T.falsy(p.threatBand:IsShown())
end)

T.test("your own ring, or name tab, goes red while you're in combat", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Me", isPlayer = true, class = "PALADIN", health = 5, maxHealth = 5 }
    end)
    local f = ns.frames.player
    stub.units.player.combat = true
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    settle()
    T.truthy(f.portrait.threatBand:IsShown(), "in combat")
    T.rgb(f.portrait.threatBand.__vertex, ns.UF.THREAT_COLORS.aggro)
    stub.units.player.combat = false
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    T.falsy(f.portrait.threatBand:IsShown(), "out of combat")
    DUI:Set("UnitFrames", "player.portrait", "none")
    stub.units.player.combat = true
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    T.eq(DaylightUI.Style.GetShell(f.tab).opts.borderColor, ns.UF.THREAT_COLORS.aggro, "the name tab without a portrait")
    DUI:Set("UnitFrames", "player.showThreat", false)
    T.isnil(DaylightUI.Style.GetShell(f.tab).opts.borderColor, "turned off")
end)

T.test("status icons: leader crown, resting and level, on the ring or the tab", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Me", isPlayer = true, class = "PALADIN", level = 25, leader = true }
        stub.resting = true
    end)
    DUI:Set("UnitFrames", "player.showLevel", true)   -- off by default
    stub.RunTimers()
    local f = ns.frames.player
    local st = f.status
    ns.UF.UpdateAll(f, true)
    T.truthy(st.icons.leader:IsShown())
    T.truthy(st.icons.rest:IsShown())
    T.eq(st.levelText.__text, 25)
    T.rgb(st.levelText.__textColor, ns.UF.LEVEL_SELF_COLOR, "your own level in white")
    local _, rel = st.icons.leader:GetPoint(1)
    T.eq(rel, f.portrait, "on the ring")
    T.truthy(st.icons.leader:GetWidth() < f.portrait:GetWidth() / 2, "small")
    DUI:Set("UnitFrames", "player.portrait", "none")
    _, rel = st.icons.leader:GetPoint(1)
    T.eq(rel, f.tab, "over the name tab without a portrait")
    stub.resting = false
    stub.units.player.leader = false
    ns.UF.UpdateStatus(f)
    T.falsy(st.icons.leader:IsShown()); T.falsy(st.icons.rest:IsShown())
    stub.resting = nil
end)

T.test("the level badge moves to a spot of its own, circle and digits together", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Me", isPlayer = true, class = "PALADIN", level = 8 }
    end)
    DUI:Set("UnitFrames", "player.showLevel", true)
    -- The classic ring keeps the badge on the portrait, so leaving and coming
    -- back shows in what it hangs off.
    DUI:Set("UnitFrames", "player.portraitLook", "classic")
    stub.RunTimers()
    local f = ns.frames.player
    local st = f.status
    ns.UF.UpdateAll(f, true)
    local _, rel = st.icons.level:GetPoint(1)
    T.eq(rel, f.portrait, "at the portrait's foot to start")
    DUI:Set("UnitFrames", "player.levelPos", "outbottomleft")
    stub.RunTimers()
    ns.UF.UpdateAll(f, true)
    _, rel = st.icons.level:GetPoint(1)
    T.eq(rel, f, "on the frame's spot")
    T.truthy(st.icons.level:IsShown(), "the circle comes along")
    T.truthy(st.icons.level:GetWidth() > 0)
    _, rel = st.levelText:GetPoint(1)
    T.eq(rel, st.icons.level, "the digits stay in it")
    DUI:Set("UnitFrames", "player.levelPos", "ring")
    stub.RunTimers()
    _, rel = st.icons.level:GetPoint(1)
    T.eq(rel, f.portrait, "back on the portrait")
end)

T.test("other units' levels are colored by difficulty; skull-level units show a skull", function()
    local _, ns = login()
    local f = ns.frames.target
    stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2, level = 27, difficulty = 3 }
    ns.UF.UpdateAll(f, true)
    local c = QuestDifficultyColors.verydifficult
    T.rgb(f.status.levelText.__textColor, { DaylightUI.Style.Lighten(c.r, c.g, c.b, ns.UF.LEVEL_LIFT) }, "difficulty color, lifted")
    -- Use the server's answer, as the game's target frame does. Retail's level
    -- math (GetCreatureDifficultyColor) said grey for a level 42 looking at a 36,
    -- the server says green.
    local level = _G.UnitLevel
    _G.UnitLevel = function(u) if u == "player" then return 42 end return level(u) end
    stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2, level = 36 }
    ns.UF.UpdateStatus(f)
    _G.UnitLevel = level
    c = QuestDifficultyColors.standard
    T.rgb(f.status.levelText.__textColor, { DaylightUI.Style.Lighten(c.r, c.g, c.b, ns.UF.LEVEL_LIFT) }, "6 under a 42: green, not grey")
    stub.units.target.level = -1
    ns.UF.UpdateStatus(f)
    T.truthy(f.status.skull:IsShown(), "skull level")
    T.falsy(f.status.levelText:IsShown())
    T.truthy(f.status.icons.level:IsShown(), "in the badge")
    stub.units.target.level = stub.Secret(30)
    ns.UF.UpdateStatus(f)
    T.eq(f.status.levelText.__text.secretFormat, "%d", "a secret level still shows")
end)

T.test("the level badge matches the ring and keeps its size without a portrait", function()
    local DUI, ns = login()
    -- The round badge: a portrait set into its frame wears a tag instead.
    DUI:Set("UnitFrames", "target.portraitLook", "classic")
    stub.RunTimers()
    local f = ns.frames.target
    local badge = f.status.icons.level
    stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2, level = 10 }
    ns.UF.UpdateAll(f, true)
    T.rgb(badge.__vertex, ns.UF.LEVEL_RING, "dark metal")
    local w = badge:GetWidth()
    stub.units.target.classification = "elite"
    ns.UF.UpdateAll(f, true)
    T.rgb(badge.__vertex, ns.UF.ELITE_RING_COLORS.gold, "an elite's gold")
    DUI:Set("UnitFrames", "target.portrait", "none")
    T.near(badge:GetWidth(), w, nil, "same size without a portrait")
end)

T.test("a PvP-flagged unit shows crossed swords in its faction's color", function()
    local DUI, ns = login()
    local f = ns.frames.target
    local st = f.status
    stub.units.target = { name = "Moash", isPlayer = true, class = "WARRIOR", reaction = 2, pvp = true, faction = "Horde" }
    ns.UF.UpdateAll(f, true)
    T.truthy(st.icons.pvp:IsShown())
    T.rgb(st.icons.pvp.__vertex, ns.UF.PVP_COLORS.Horde, "horde red")
    stub.units.target.faction = "Alliance"
    ns.UF.UpdateStatus(f)
    T.rgb(st.icons.pvp.__vertex, ns.UF.PVP_COLORS.Alliance, "alliance blue")
    stub.units.target.pvp = false
    ns.UF.UpdateStatus(f)
    T.falsy(st.icons.pvp:IsShown())
    DUI:Set("UnitFrames", "target.showPvP", false)
    stub.units.target.pvp = true
    ns.UF.UpdateStatus(f)
    T.falsy(st.icons.pvp:IsShown(), "turned off")
end)

T.test("a frame with no unit yet (an empty group slot) skips its level", function()
    local DUI, ns = login()
    local f = ns.frames.target
    local real, unit = _G.UnitLevel, f.unitToken
    -- The client throws on a nil unit.
    _G.UnitLevel = function(u) assert(u ~= nil, "bad argument #1 to 'UnitLevel'"); return real(u) end
    f.unitToken = nil
    local ok, err = pcall(ns.UF.UpdateStatus, f)
    _G.UnitLevel, f.unitToken = real, unit
    T.truthy(ok, err)
    T.falsy(f.status.icons.level:IsShown())
end)

-- ---------------------------------------------------------------------
-- Threat in a group: the orange step and the threat % tag
-- ---------------------------------------------------------------------

local function onTarget(status, scaled, boss)
    stub.units.target = { name = "Grell", isPlayer = false, reaction = 2, boss = boss,
                          threatList = { player = { status = status, scaled = scaled, raw = scaled, value = scaled * 10 } } }
end

T.test("threat: in a group the ring goes orange close to pulling and the tag shows your percent", function()
    local _, ns = login()
    local f, p = ns.frames.target, ns.frames.target.portrait
    local UF = ns.UF
    T.truthy(f.threatTag, "the target frame has a threat tag")
    stub.SetGroup(true)
    onTarget(0, 86.4)
    UF.UpdateAll(f, true)
    T.rgb(p.threatBand.__vertex, UF.THREAT_COLORS.warn, "orange: close to pulling")
    T.truthy(f.threatTag:IsShown())
    T.eq(f.threatTag.text:GetText(), "86%")
    T.rgb(f.threatTag.text.__textColor, UF.THREAT_COLORS.warn, "the tag in the same orange")
    onTarget(0, 40)
    UF.UpdateThreat(f)
    T.falsy(p.threatBand:IsShown(), "well below: no ring")
    T.eq(f.threatTag.text:GetText(), "40%")
    onTarget(3, 100)
    UF.UpdateThreat(f)
    settle()
    T.rgb(p.threatBand.__vertex, UF.THREAT_COLORS.aggro, "on you: red")
    T.rgb(f.threatTag.text.__textColor, UF.THREAT_COLORS.aggro)
    stub.units.target.threatList = nil
    UF.UpdateThreat(f)
    T.falsy(f.threatTag:IsShown(), "not on its list: no tag")
    stub.SetGroup(false)
end)

T.test("threat: alone with a pet the tag and the orange step show, as in a group", function()
    local _, ns = login()
    local f, p = ns.frames.target, ns.frames.target.portrait
    local UF = ns.UF
    stub.SetGroup(false)
    stub.units.pet = { name = "Spot", class = "WARRIOR" }
    onTarget(0, 86.4)
    UF.UpdateAll(f, true)
    T.rgb(p.threatBand.__vertex, UF.THREAT_COLORS.warn, "orange: about to take it from the pet")
    T.truthy(f.threatTag:IsShown())
    T.eq(f.threatTag.text:GetText(), "86%")
    stub.units.pet = nil
    UF.UpdateThreat(f)
    T.falsy(f.threatTag:IsShown(), "no pet: solo again")
end)

T.test("threat: solo there is no tag and no orange step (it's always on you)", function()
    local _, ns = login()
    local f, p = ns.frames.target, ns.frames.target.portrait
    stub.SetGroup(false)
    onTarget(1, 95)
    ns.UF.UpdateAll(f, true)
    T.falsy(f.threatTag:IsShown())
    T.falsy(p.threatBand:IsShown())
    onTarget(3, 100)
    ns.UF.UpdateThreat(f)
    settle()
    T.rgb(p.threatBand.__vertex, ns.UF.THREAT_COLORS.aggro, "the red ring stays, solo too")
    T.falsy(f.threatTag:IsShown())
end)

T.test("threat: on a boss the percent is secret: written whole, the ring from the plain state", function()
    local _, ns = login()
    local f, p = ns.frames.target, ns.frames.target.portrait
    stub.SetGroup(true)
    onTarget(1, 92, true)
    stub.EnterCombat()
    ns.UF.UpdateAll(f, true)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(f.threatTag:IsShown())
    T.eq(type(f.threatTag.text:GetText()), "table", "a secret, formatted by the client")
    T.rgb(p.threatBand.__vertex, ns.UF.THREAT_COLORS.warn, "the state is plain: orange")
    stub.LeaveCombat()
    stub.SetGroup(false)
end)

T.test("threat: the tag and the orange are settings", function()
    local DUI, ns = login()
    local f = ns.frames.target
    DUI:Set("UnitFrames", "colors.threatWarn", { 0, 1, 0 })
    DUI:Set("UnitFrames", "target.threatTag", false)
    stub.RunTimers()
    T.rgb(ns.UF.THREAT_COLORS.warn, { DaylightUI.Style.Soften(0, 1, 0) })
    stub.SetGroup(true)
    onTarget(0, 90)
    ns.UF.UpdateAll(f, true)
    T.falsy(f.threatTag:IsShown(), "switched off")
    stub.SetGroup(false)
end)

T.test("threat: the tag goes on its own mover, and takes its size, font size, color, box and nudge", function()
    local DUI, ns = login()
    local f, UF = ns.frames.target, ns.UF
    local holder = f.threatHolder
    T.truthy(holder, "the target has a holder for the tag on its own")
    T.eq(f.threatTag:GetParent(), f, "on the frame by default")
    DUI:Set("UnitFrames", "target.threatTagX", 6)
    DUI:Set("UnitFrames", "target.threatTagWidth", 50)
    DUI:Set("UnitFrames", "target.threatTagHeight", 20)
    DUI:Set("UnitFrames", "target.threatTagSize", 15)
    DUI:Set("UnitFrames", "target.threatTagSlant", false)
    stub.RunTimers()
    local _, _, _, x = f.threatTag:GetPoint(1)
    T.eq(x, (f.cut or 0) + 6, "nudged sideways")
    T.near(f.threatTag:GetWidth(), 50, 1, "its width, straight ends")
    T.near(f.threatTag:GetHeight(), 20, 1)
    local _, size = f.threatTag.text:GetFont()
    T.eq(size, 15, "its own text size")
    DUI:Set("UnitFrames", "target.threatTagAt", "free")
    DUI:Set("UnitFrames", "target.threatTagBox", false)
    DUI:Set("UnitFrames", "target.threatTagColor", "white")
    stub.RunTimers()
    T.eq(f.threatTag:GetParent(), holder, "moved into its own holder")
    local _, rel = f.threatTag:GetPoint(1)
    T.eq(rel, holder, "never anchored to the frame")
    T.falsy(DaylightUI.Style.GetShell(f.threatTag):IsShown(), "no box: the number alone")
    stub.SetGroup(true)
    onTarget(3, 100)
    UF.UpdateAll(f, true)
    T.rgb(f.threatTag.text.__textColor, DaylightUI.Style.INK.VALUE, "white, though it's on you")
    f:Hide()
    T.falsy(holder:IsShown(), "hides with the frame")
    f:Show()
    T.truthy(holder:IsShown(), "and comes back with it")
    DUI:Set("UnitFrames", "target.threatTagAt", "frame")
    stub.RunTimers()
    T.eq(f.threatTag:GetParent(), f, "back on the frame")
    T.falsy(holder:IsShown())
    stub.SetGroup(false)
end)

-- ---------------------------------------------------------------------
-- The aggro ring fills: a red wipe runs round the ring behind a glow head
-- when aggro comes, and back when it goes.
-- ---------------------------------------------------------------------

local function wolf(threat)
    stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2, threat = threat }
end

T.test("ring fill: aggro gained fills the red round the ring, then the plain band", function()
    local _, ns = login()
    local f, p = ns.frames.target, ns.frames.target.portrait
    wolf(nil)
    ns.UF.UpdateAll(f, true)
    wolf(3)
    ns.UF.UpdateThreat(f)
    T.falsy(p.threatBand:IsShown(), "the plain band waits for the fill")
    T.truthy(p.fill:IsShown(), "the wipe")
    T.truthy(p.head:IsShown(), "the glow head")
    step(0.1)
    T.truthy(p.fillAt > 0 and p.fillAt < 1, "part of the way: " .. tostring(p.fillAt))
    T.truthy(p.fill.__cooldown, "drawn through the cooldown swipe")
    settle()
    T.eq(p.fillAt, 1)
    T.truthy(p.threatBand:IsShown(), "landed: the plain red band")
    T.rgb(p.threatBand.__vertex, ns.UF.THREAT_COLORS.aggro)
    T.falsy(p.fill:IsShown())
    T.falsy(p.head:IsShown())
    ns.UF.UpdateThreat(f)
    T.truthy(p.threatBand:IsShown(), "a repeat threat event changes nothing")
    T.falsy(p.fill:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("ring fill: aggro lost unwinds back to the gray ring", function()
    local _, ns = login()
    local f, p = ns.frames.target, ns.frames.target.portrait
    wolf(3)
    ns.UF.UpdateAll(f, true)
    T.truthy(p.threatBand:IsShown())
    wolf(0)
    ns.UF.UpdateThreat(f)
    T.falsy(p.threatBand:IsShown(), "the plain band goes, the wipe takes over")
    T.truthy(p.fill:IsShown())
    step(0.1)
    T.truthy(p.fillAt > 0 and p.fillAt < 1)
    settle()
    T.eq(p.fillAt, 0)
    T.falsy(p.fill:IsShown())
    T.falsy(p.head:IsShown())
    T.falsy(p.threatBand:IsShown(), "gray again")
end)

T.test("ring fill: lost mid-fill unwinds from where it got to", function()
    local _, ns = login()
    local f, p = ns.frames.target, ns.frames.target.portrait
    wolf(nil)
    ns.UF.UpdateAll(f, true)
    wolf(3)
    ns.UF.UpdateThreat(f)
    step(0.1)
    local at = p.fillAt
    wolf(nil)
    ns.UF.UpdateThreat(f)
    T.eq(p.fillAt, at, "starts where the fill was")
    step(0.05)
    T.truthy(p.fillAt < at, "and goes back")
    settle()
    T.eq(p.fillAt, 0)
    T.falsy(p.threatBand:IsShown())
end)

T.test("ring fill: a target swap snaps to the new target's state", function()
    local _, ns = login()
    local f, p = ns.frames.target, ns.frames.target.portrait
    wolf(nil)
    ns.UF.UpdateAll(f, true)
    wolf(3)
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.truthy(p.threatBand:IsShown(), "red at once")
    T.falsy(p.fill:IsShown())
    wolf(nil)
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.falsy(p.threatBand:IsShown(), "gray at once")
    T.falsy(p.fill:IsShown())
    T.isnil(f.threatFresh, "the mark is cleared after the swap")
end)

T.test("ring fill: the secret path and the orange step snap", function()
    local _, ns = login()
    local f, p = ns.frames.target, ns.frames.target.portrait
    wolf(nil)
    ns.UF.UpdateAll(f, true)
    wolf(3)
    ns.UF.UpdateThreat(f)
    step(0.1)
    local flag = stub.Secret(true)
    ns.UF.ApplyThreat(f, nil, flag)
    T.falsy(p.fill:IsShown(), "a running fill is cut")
    T.falsy(p.head:IsShown())
    T.truthy(p.threatBand:IsShown())
    T.eq(p.threatBand.__alphaFromBoolean[1], flag, "the client picks, as before")
    ns.UF.ApplyThreat(f, "warn")
    T.truthy(p.threatBand:IsShown(), "orange at once")
    T.rgb(p.threatBand.__vertex, ns.UF.THREAT_COLORS.warn)
    T.falsy(p.fill:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("ring fill: from orange the red fills over it, then lands", function()
    local _, ns = login()
    local f, p = ns.frames.target, ns.frames.target.portrait
    ns.UF.ApplyThreat(f, "warn")
    ns.UF.ApplyThreat(f, "aggro")
    T.truthy(p.threatBand:IsShown(), "the orange stays under the wipe")
    T.rgb(p.threatBand.__vertex, ns.UF.THREAT_COLORS.warn)
    T.truthy(p.fill:IsShown())
    settle()
    T.rgb(p.threatBand.__vertex, ns.UF.THREAT_COLORS.aggro, "red once it lands")
    ns.UF.ApplyThreat(f, "warn")
    T.rgb(p.threatBand.__vertex, ns.UF.THREAT_COLORS.warn, "red to orange: at once")
    T.falsy(p.fill:IsShown())
end)

T.test("ring fill: your own ring fills entering combat and unwinds leaving it", function()
    local _, ns = login(function()
        stub.units.player = { name = "Me", isPlayer = true, class = "PALADIN", health = 5, maxHealth = 5 }
    end)
    local p = ns.frames.player.portrait
    stub.units.player.combat = true
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    T.truthy(p.fill:IsShown(), "fills")
    T.falsy(p.threatBand:IsShown())
    settle()
    T.truthy(p.threatBand:IsShown())
    stub.units.player.combat = false
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    T.truthy(p.fill:IsShown(), "unwinds")
    T.falsy(p.threatBand:IsShown())
    settle()
    T.falsy(p.fill:IsShown())
    T.falsy(p.threatBand:IsShown())
end)

T.test("ring fill: motion off, or no portrait, snaps", function()
    local DUI, ns = login()
    local f, p = ns.frames.target, ns.frames.target.portrait
    DaylightUI.DB.General().motion = false
    wolf(nil)
    ns.UF.UpdateAll(f, true)
    wolf(3)
    ns.UF.UpdateThreat(f)
    T.truthy(p.threatBand:IsShown(), "red at once")
    T.falsy(p.fill:IsShown())
    T.falsy(p.head:IsShown())
    DaylightUI.DB.General().motion = true
    wolf(nil)
    ns.UF.UpdateThreat(f)
    DUI:Set("UnitFrames", "target.portrait", "none")
    stub.RunTimers()
    wolf(3)
    ns.UF.UpdateThreat(f)
    T.falsy(p.fill:IsShown(), "no ring: nothing to fill")
    T.eq(DaylightUI.Style.GetShell(f.tab).opts.borderColor, ns.UF.THREAT_COLORS.aggro, "the tab goes red at once")
end)

T.test("ring color: the class gradient by default, light gray, or dark like the frame's border", function()
    local DUI, ns = login()
    -- Measures the classic ring's own art and sizes.
    DUI:Set("UnitFrames", "target.portraitLook", "classic")
    stub.RunTimers()
    local f, p = ns.frames.target, ns.frames.target.portrait
    stub.units.target = { name = "Zap", isPlayer = true, class = "MAGE", reaction = 2 }
    ns.UF.UpdateAll(f, true)
    T.eq(DUI:Get("UnitFrames", "target.portraitRing"), "class")
    DUI:Set("UnitFrames", "target.portraitRing", "light")
    ns.UF.UpdateAll(f, true)
    T.rgb(p.ring.__vertex, ns.UF.RING_COLOR, "the gray band")
    T.eq(p.ring.__texture, DUI.MEDIA .. "portrait-band.png")
    DUI:Set("UnitFrames", "target.portraitRing", "dark")
    ns.UF.UpdateAll(f, true)
    local g = p.ring.__gradient
    T.truthy(g, "the dark ring is a gradient")
    T.eq(g[1], "VERTICAL")
    T.near(g[2].r, DUI.Style.BAND[1]); T.near(g[3].r, DUI.Style.BAND_LIT[1], nil, "lit at the top")
    DUI:Set("UnitFrames", "target.portraitRing", "class")
    ns.UF.UpdateAll(f, true)
    local lo, hi = DUI.Gradients.Colors("MAGE")
    g = p.ring.__gradient
    T.eq(g[1], "VERTICAL"); T.eq(g[2], lo); T.eq(g[3], hi, "the mage pair, light end on top")
    stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2 }
    ns.UF.UpdateAll(f, true)
    lo = DUI.Gradients.Colors("HOSTILE")
    T.eq(p.ring.__gradient[2], lo, "an NPC: its reaction's pair")
    DUI:Set("UnitFrames", "target.portraitRing", "light")
    ns.UF.UpdateAll(f, true)
    T.rgb(p.ring.__vertex, ns.UF.RING_COLOR, "back to gray")
    T.isnil(p.ring.__gradient, "the gradient is cleared")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("ring color: the accent on every frame, or the Daylight gradient", function()
    local DUI, ns = login()
    -- Measures the classic ring's own art and sizes.
    DUI:Set("UnitFrames", "target.portraitLook", "classic")
    stub.RunTimers()
    local f, p = ns.frames.target, ns.frames.target.portrait
    stub.units.target = { name = "Zap", isPlayer = true, class = "MAGE", reaction = 2 }
    DUI:Set("general", "accent", "gradient")
    DUI:Set("UnitFrames", "target.portraitRing", "accent")
    ns.UF.UpdateAll(f, true)
    local a, b = DUI.Style.AccentPair()
    local g = p.ring.__gradient
    T.truthy(g, "a gradient accent: its pair")
    T.eq(g[1], "VERTICAL")
    T.near(g[2].r, a[1]); T.near(g[3].r, b[1], nil, "whatever the unit's class")
    T.eq(p.ring.__texture, ns.UF.RING_FILE)
    DUI:Set("general", "accent", "custom")
    DUI:Set("general", "accentColor", { 0.2, 0.7, 0.4 })
    ns.UF.UpdateAll(f, true)
    T.rgb(p.ring.__vertex, { 0.2, 0.7, 0.4 }, "a one-color accent")
    T.isnil(p.ring.__gradient, "its gradient cleared")
    T.eq(p.ring.__texture, ns.UF.RING_LIT_FILE, "shaded by the texture")
    T.eq(p.fillFile, ns.UF.RING_LIT_FILE, "the red band shaded too")
    DUI:Set("UnitFrames", "target.portraitRing", "daylight")
    ns.UF.UpdateAll(f, true)
    local shape = DUI.Style.GRADIENT_SHAPE
    g = p.ring.__gradient
    T.truthy(g, "the Daylight gradient")
    T.near(g[2].r, shape[1][1]); T.near(g[3].r, shape[2][1], nil, "pink on top, whatever the accent")
    T.eq(p.ring.__texture, ns.UF.RING_FILE)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("ring color: with a gradient ring the red ring is lit from above too", function()
    local DUI, ns = login()
    -- Measures the classic ring's own art and sizes.
    DUI:Set("UnitFrames", "target.portraitLook", "classic")
    stub.RunTimers()
    local f, p = ns.frames.target, ns.frames.target.portrait
    DUI:Set("UnitFrames", "target.portraitRing", "light")
    ns.UF.UpdateAll(f, true)
    T.eq(p.threatBand.__texture, DUI.MEDIA .. "portrait-band.png", "light: the flat red band")
    T.eq(p.fillFile, DUI.MEDIA .. "portrait-band.png")
    DUI:Set("UnitFrames", "target.portraitRing", "class")
    wolf(nil)
    ns.UF.UpdateAll(f, true)
    T.eq(p.threatBand.__texture, ns.UF.RING_LIT_FILE, "the red band shaded top to bottom")
    T.eq(p.fillFile, ns.UF.RING_LIT_FILE, "and the red sweeping round")
    wolf(3)
    ns.UF.UpdateThreat(f)
    settle()
    T.truthy(p.threatBand:IsShown())
    T.rgb(p.threatBand.__vertex, ns.UF.THREAT_COLORS.aggro, "still the aggro red")
    DUI:Set("UnitFrames", "target.portraitRing", "dark")
    ns.UF.UpdateAll(f, true)
    T.eq(p.threatBand.__texture, ns.UF.RING_LIT_FILE, "the dark ring too")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("ring color: the ring takes the class gradient, an elite's dragon keeps its rank's color", function()
    local DUI, ns = login()
    local f, p = ns.frames.target, ns.frames.target.portrait
    DUI:Set("UnitFrames", "target.portraitRing", "class")
    stub.units.target = { name = "Grell", isPlayer = false, reaction = 2, classification = "elite" }
    ns.UF.UpdateAll(f, true)
    T.truthy(p.elite:IsShown())
    local lo = DUI.Gradients.Colors("HOSTILE")
    T.eq(p.ring.__gradient[2], lo, "the ring: the pair")
    T.isnil(p.elite.__gradient, "the dragon: no gradient")
    T.rgb(p.elite.__vertex, ns.UF.ELITE_RING_COLORS.gold, "gold says elite at a glance")
    stub.units.target.threat = 2
    ns.UF.UpdateThreat(f)
    T.rgb(p.elite.__vertex, ns.UF.ELITE_RING_COLORS.gold, "aggro leaves it gold")
    T.truthy(p.eye:IsShown(), "only its eyes catch fire")
    stub.units.target.threat = nil
    ns.UF.UpdateThreat(f)
    T.rgb(p.elite.__vertex, ns.UF.ELITE_RING_COLORS.gold, "gold again")
    -- A secret "is tanking" value. The client decides whether the eyes light.
    ns.UF.ApplyThreat(f, nil, stub.Secret(true))
    T.rgb(p.elite.__vertex, ns.UF.ELITE_RING_COLORS.gold, "gold")
    T.truthy(p.eye:IsShown(), "the eyes, their alpha the client's pick")
    T.truthy(p.eye.__alphaFromBoolean, "alpha from the secret flag")
    ns.UF.ApplyThreat(f, nil, nil)
    T.falsy(p.eye:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("your own dragon: off by default; on, mirrored to the outer side, in your pick of color", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Me", isPlayer = true, class = "PALADIN" }
    end)
    local f, p = ns.frames.player, ns.frames.player.portrait
    ns.UF.UpdateAll(f, true)
    T.falsy(p.elite:IsShown(), "off by default")
    DUI:Set("UnitFrames", "player.portraitDragon", true)
    ns.UF.UpdateAll(f, true)
    T.truthy(p.elite:IsShown())
    T.truthy(p.ring:IsShown())
    T.eq(p.elite.__texCoord[1], 1, "the player's ring is on the left: mirrored")
    T.eq(p.elite.__texCoord[2], 0)
    local _, _, _, ex = p.eye:GetPoint(1)
    T.near(ex, -p.elite:GetWidth() * ns.UF.DRAGON_EYE.x, 0.01, "the eyes mirrored with it")
    local lo, hi = DUI.Gradients.Colors("PALADIN")
    T.eq(p.elite.__gradient[2], lo, "class gradient by default: your class pair")
    T.eq(p.elite.__gradient[3], hi)
    DUI:Set("UnitFrames", "player.portraitRing", "light")
    ns.UF.UpdateAll(f, true)
    T.eq(p.elite.__gradient[2], lo, "whatever the ring's color")
    DUI:Set("UnitFrames", "player.portraitDragonColor", "gold")
    ns.UF.UpdateAll(f, true)
    T.rgb(p.elite.__vertex, ns.UF.ELITE_RING_COLORS.gold, "gold")
    T.isnil(p.elite.__gradient)
    DUI:Set("UnitFrames", "player.portraitDragonColor", "silver")
    ns.UF.UpdateAll(f, true)
    T.rgb(p.elite.__vertex, ns.UF.ELITE_RING_COLORS.silver, "silver")
    DUI:Set("UnitFrames", "player.portraitDragonColor", "accent")
    DUI:Set("general", "accent", "custom")
    DUI:Set("general", "accentColor", { 0.2, 0.6, 0.9 })
    ns.UF.UpdateAll(f, true)
    T.rgb(p.elite.__vertex, { 0.2, 0.6, 0.9 }, "a one-color accent")
    T.isnil(p.elite.__gradient)
    DUI:Set("general", "accent", "gradient")
    ns.UF.UpdateAll(f, true)
    T.truthy(p.elite.__gradient, "a gradient accent: its pair")
    DUI:Set("UnitFrames", "player.portraitDragonColor", "class")
    ns.UF.UpdateAll(f, true)
    T.truthy(p.elite.__gradient, "class again")
    ns.UF.ApplyThreat(f, "aggro")
    T.truthy(p.elite.__gradient, "in a fight it keeps your colors")
    T.truthy(p.eye:IsShown(), "its eyes catch fire")
    ns.UF.ApplyThreat(f, nil)
    T.falsy(p.eye:IsShown(), "and go out")
    DUI:Set("UnitFrames", "player.portraitDragon", false)
    ns.UF.UpdateAll(f, true)
    T.falsy(p.elite:IsShown(), "off again")
    T.falsy(p.eye:IsShown())
    DUI:Set("UnitFrames", "player.portraitDragon", true)
    DUI:Set("UnitFrames", "player.portrait", "none")
    ns.UF.UpdateAll(f, true)
    T.falsy(p:IsShown(), "no portrait, no dragon")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("ring color: an enemy whose class the game hides gets its class color", function()
    local DUI, ns = login()
    -- Measures the classic ring's own art and sizes.
    DUI:Set("UnitFrames", "target.portraitLook", "classic")
    stub.RunTimers()
    DUI:Set("UnitFrames", "target.portraitRing", "class")
    stub.units.target = { name = "Rival", isPlayer = true, class = "MAGE", classHidden = true, reaction = 2 }
    local f, p = ns.frames.target, ns.frames.target.portrait
    ns.UF.UpdateAll(f, true)
    T.truthy(issecretvalue(p.ring.__vertex[1]), "the client's secret class color, straight to the texture")
    T.eq(p.ring.__texture, ns.UF.RING_LIT_FILE, "shaded by the texture, since a secret can't make a pair")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("ring thickness and its middle line: the ring and everything drawn on it (red band, sweep, pulse, arrival light) take the same art; the picture inside follows the opening", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Stabby", isPlayer = true, class = "ROGUE", health = 5, maxHealth = 10 }
    end)
    -- Measures the classic ring's own art and sizes.
    DUI:Set("UnitFrames", "player.portraitLook", "classic")
    DUI:Set("UnitFrames", "target.portraitLook", "classic")
    stub.RunTimers()
    local UF = ns.UF
    local f = ns.frames.player
    local p = f.portrait
    UF.UpdateAll(f, true)
    T.truthy(p.ring:GetTexture():find("portrait-band.png", 1, true), "normal, with its line, by default")
    local R = p:GetWidth() / 2
    T.near(p.radius, R * (1 + UF.RING_WIDTHS.normal) / 2, 1e-6)
    local normalMask = p.mask:GetWidth()
    DUI:Set("UnitFrames", "player.portraitRingWidth", "thick")
    DUI:Set("UnitFrames", "player.portraitRingLine", false)
    stub.RunTimers()
    UF.UpdateAll(f, true)
    UF.UpdateAll(ns.frames.target, true)
    T.eq(ns.frames.target.ringFile, UF.RingFiles("normal", true), "each frame its own: the target's stays normal")
    local file, lit = UF.RingFiles("thick", false)
    T.truthy(file:find("portrait-band-thick-smooth.png", 1, true))
    local used = { [file] = true, [lit] = true }
    T.truthy(used[p.ring:GetTexture()], "the ring")
    T.truthy(used[p.threatBand:GetTexture()], "the red aggro band")
    T.truthy(used[p.pulse:GetTexture()], "the pulse")
    T.truthy(used[p.fillFile], "the aggro sweep")
    T.near(p.radius, R * (1 + UF.RING_WIDTHS.thick) / 2, 1e-6, "the sweep's light runs down the thick band's middle")
    T.truthy(p.mask:GetWidth() < normalMask, "a smaller picture inside")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("upgrade step 18: a shared ring thickness and line move onto every frame with a portrait", function()
    local _, ns = login()
    local uf = { portraits = { icons = "game", ringWidth = "thin", ringLine = false }, target = { width = 200 } }
    ns.UPGRADE_STEPS[18](uf)
    for _, key in ipairs({ "player", "target", "focus", "party", "arena" }) do
        T.eq(uf[key].portraitRingWidth, "thin", key)
        T.eq(uf[key].portraitRingLine, false, key)
    end
    T.eq(uf.target.width, 200, "the frame's other settings stay")
    T.eq(uf.portraits.ringWidth, nil); T.eq(uf.portraits.ringLine, nil)
    T.eq(uf.portraits.icons, "game", "the icon style stays shared")
    uf = { portraits = { icons = "game" } }
    ns.UPGRADE_STEPS[18](uf)
    T.eq(uf.player, nil, "nothing changed from the defaults: no frame settings written")
end)

T.test("square and angled portraits: every layer takes the shape's art, lights ride its outline, elites get the gold frame", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Stabby", isPlayer = true, class = "ROGUE", health = 5, maxHealth = 10 }
    end)
    -- Measures the classic ring's own art and sizes.
    DUI:Set("UnitFrames", "player.portraitLook", "classic")
    DUI:Set("UnitFrames", "target.portraitLook", "classic")
    stub.RunTimers()
    local UF = ns.UF
    local f, p = ns.frames.target, ns.frames.target.portrait
    wolf(nil)
    UF.UpdateAll(f, true)
    T.eq(p.mask.__texture, DUI.MEDIA .. "crest-disc.png", "round by default")
    T.falsy(p.corners)
    DUI:Set("UnitFrames", "target.portraitShape", "square")
    stub.RunTimers()
    UF.UpdateAll(f, true)
    local file, lit = UF.RingFiles("normal", true, "square")
    local used = { [file] = true, [lit] = true }
    T.truthy(file:find("portrait-square-band.png", 1, true))
    T.truthy(used[p.ring:GetTexture()], "the band")
    T.truthy(used[p.threatBand:GetTexture()], "the red aggro band")
    T.truthy(used[p.pulse:GetTexture()], "the pulse")
    T.truthy(used[p.fillFile], "the aggro sweep")
    T.eq(p.mask.__texture, DUI.MEDIA .. "portrait-square-hole.png", "the picture cropped square")
    T.eq(p.halo.__texture, DUI.MEDIA .. "portrait-square-glow.png", "a square halo")
    UF.UpdateAll(ns.frames.player, true)
    T.falsy(ns.frames.player.portrait.shapeArt, "each frame has its own shape: the player's stays round")
    -- Half way between top and right, the light sits on the square's corner.
    local x, y = UF.RingPoint(p, math.pi / 4)
    T.near(x, p.radius, 1e-6); T.near(y, p.radius, 1e-6)
    x, y = UF.RingPoint(p, 0)
    T.near(x, 0, 1e-6); T.near(y, p.radius, 1e-6, "the top edge's middle")
    -- Aggro fills round it, the head on the outline.
    wolf(3)
    UF.UpdateThreat(f)
    step(0.1)
    T.truthy(p.fill:IsShown() and p.head:IsShown())
    settle()
    T.truthy(p.threatBand:IsShown(), "landed: the red band in the square's art")
    -- An elite: the gold frame, no dragon, no eyes even with aggro.
    stub.units.target.classification = "elite"
    UF.UpdateAll(f, true)
    UF.UpdateThreat(f)
    T.truthy(p.elite:IsShown())
    T.eq(p.elite.__texture, DUI.MEDIA .. "portrait-square-elite.png")
    T.falsy(p.eye:IsShown(), "only the dragon has eyes")
    T.rgb(p.elite.__vertex, UF.ELITE_RING_COLORS.gold, "the frame stays gold with aggro")
    -- Angled: the target's portrait sits on the frame's right end, the player's on its left.
    DUI:Set("UnitFrames", "target.portraitShape", "angled")
    DUI:Set("UnitFrames", "player.portraitShape", "angled")
    stub.RunTimers()
    UF.UpdateAll(f, true)
    T.truthy(p.ring:GetTexture():find("portrait-angled-r-band", 1, true), "the target: leaning right")
    T.eq(p.elite.__texture, DUI.MEDIA .. "portrait-angled-r-elite.png")
    local pp = ns.frames.player.portrait
    UF.UpdateAll(ns.frames.player, true)
    T.truthy(pp.ring:GetTexture():find("portrait-angled-l-band", 1, true), "the player: leaning left")
    -- The lean: below the middle, the outer (right) side is tucked in.
    local lx = UF.RingPoint(p, math.pi * 0.75)
    T.truthy(lx < p.radius - 1e-6, "the tucked-in corner is closer in")
    -- Back to round: the dragon and the round crop.
    DUI:Set("UnitFrames", "target.portraitShape", "round")
    stub.RunTimers()
    UF.UpdateAll(f, true)
    T.eq(p.elite.__texture, UF.DRAGON_FILE)
    T.eq(p.mask.__texture, DUI.MEDIA .. "crest-disc.png")
    T.falsy(p.corners)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("the game's own class icons: its classicon atlas, Daylight UI's own when the client has none", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Stabby", isPlayer = true, class = "ROGUE", health = 5, maxHealth = 10 }
    end)
    local UF = ns.UF
    local _, order = UF.IconStyleChoices()
    T.eq(order[2], "game", "in the menu with no icon pack installed")
    local had = C_Texture and C_Texture.GetAtlasInfo
    _G.C_Texture = _G.C_Texture or {}
    C_Texture.GetAtlasInfo = function(name)
        if name == "classicon-rogue" then
            return { file = 12345, leftTexCoord = 0.1, rightTexCoord = 0.2, topTexCoord = 0.3, bottomTexCoord = 0.4 }
        end
    end
    local file, l, r = UF.ClassIcon("ROGUE", "game")
    T.eq(file, 12345, "the atlas's file")
    T.eq(l, 0.1); T.eq(r, 0.2)
    file = UF.ClassIcon("MAGE", "game")
    T.truthy(type(file) == "string" and file:find("mage", 1, true), "no atlas: Daylight UI's own")
    C_Texture.GetAtlasInfo = had
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("a portrait on its own leaves the frame for its own movable holder", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Stabby", isPlayer = true, class = "ROGUE", health = 5, maxHealth = 10, level = 20 }
    end)
    stub.RunTimers()
    local UF, f = ns.UF, ns.frames.player
    local p, h, key = f.portrait, f.portraitHolder, UF.PORTRAIT_FREE.player
    T.truthy(h, "player, target and focus each get a holder")
    T.truthy(DUI.Movers.Get(key).suspended, "no handle while it sits on the frame")
    DUI:Set("UnitFrames", "player.portraitAt", "free")
    stub.RunTimers()
    ns.UF.UpdateAll(f, true)
    T.eq(p:GetParent(), h)
    T.truthy(p:IsShown()); T.truthy(h:IsShown())
    T.falsy(DUI.Movers.Get(key).suspended)
    local _, rel = p:GetPoint(1)
    T.eq(rel, h, "centered in its holder, never on the frame")
    T.eq(f.status:GetParent(), h, "the icons riding on the ring go along")
    T.eq(f.__hitRect[1], 0, "the frame's hit rect is its own again")
    T.eq(f.tabInset, UF.TAB_INSET, "the name tab no longer clears a ring")
    T.eq(f.ringReach, 0)
    T.eq(p.icon.__texture, DUI.MEDIA .. "class\\rogue.tga", "still drawn")
    f:Hide()
    T.falsy(h:IsShown(), "hides with its frame")
    f:Show()
    T.truthy(h:IsShown())
    DUI:Set("UnitFrames", "player.portrait", "none")
    stub.RunTimers()
    T.falsy(h:IsShown())
    T.truthy(DUI.Movers.Get(key).suspended, "no handle for a portrait that isn't there")
    DUI:Set("UnitFrames", "player.portrait", "class")
    DUI:Set("UnitFrames", "player.portraitAt", "frame")
    stub.RunTimers()
    T.eq(p:GetParent(), f, "back on the frame")
    T.eq(f.status:GetParent(), f)
    T.truthy(f.__hitRect[1] < 0, "the ring is clickable again")
    T.falsy(h:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("the target's portrait on its own comes and goes with its target, skull and all", function()
    local DUI, ns = login()
    stub.RunTimers()
    local f = ns.frames.target
    DUI:Set("UnitFrames", "target.portraitAt", "free")
    stub.RunTimers()
    T.eq(f.dotSkull:GetParent(), f.portraitHolder, "the DoT skull rides on the ring")
    T.falsy(f.portraitHolder:IsShown(), "no target, no portrait")
    stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2 }
    f:Show()
    ns.UF.UpdateAll(f, true)
    T.truthy(f.portraitHolder:IsShown())
    f:Hide()
    T.falsy(f.portraitHolder:IsShown())
    DUI:Set("UnitFrames", "target.portraitAt", "frame")
    stub.RunTimers()
    T.eq(f.dotSkull:GetParent(), f.overlay)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("a portrait on its own can leave its icons on the frame", function()
    local DUI, ns = login()
    stub.RunTimers()
    local f = ns.frames.target
    DUI:Set("UnitFrames", "target.portraitAt", "free")
    DUI:Set("UnitFrames", "target.portraitIconsStay", true)
    stub.RunTimers()
    T.eq(f.portrait:GetParent(), f.portraitHolder, "the ring still goes")
    T.eq(f.status:GetParent(), f, "crown, Zzz, PvP and level stay")
    T.eq(f.dotSkull:GetParent(), f.overlay, "so does the DoT skull")
    local _, rel = f.status.icons.rest:GetPoint(1)
    T.eq(rel, f.tab, "the Zzz sits by the name tab, as with no portrait")
    local _, srel = f.dotSkull:GetPoint(1)
    T.eq(srel, f, "the skull past the frame's end")
    DUI:Set("UnitFrames", "target.portraitIconsStay", false)
    stub.RunTimers()
    T.eq(f.status:GetParent(), f.portraitHolder)
    _, rel = f.status.icons.rest:GetPoint(1)
    T.eq(rel, f.portrait)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("no portrait and no name tab: icons beside the frame, combat and elite on its border", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Stabby", isPlayer = true, class = "ROGUE", leader = true, pvp = true,
                              faction = "Alliance" }
        stub.resting = true
    end)
    for _, u in ipairs({ "player", "target" }) do
        DUI:Set("UnitFrames", u .. ".portrait", "none")
        DUI:Set("UnitFrames", u .. ".nameOnBar", true)
    end
    stub.RunTimers()
    local f = ns.frames.player
    T.falsy(f.tab:IsShown())
    local icons = f.status.icons
    for _, key in ipairs({ "leader", "rest", "pvp" }) do
        local pt, rel, rp = icons[key]:GetPoint(1)
        T.eq(rel, f, key .. " hangs off the frame, not the hidden tab")
        T.truthy(pt:find("RIGHT") and rp:find("LEFT"), key .. " beside the outer end")
    end
    local shell = DaylightUI.Style.GetShell(f)
    stub.units.player.combat = true
    ns.UF.UpdateCombat(f)
    T.rgb(shell.opts.borderColor, ns.UF.THREAT_COLORS.aggro, "in a fight the frame's border goes red")
    stub.units.player.combat = false
    ns.UF.UpdateCombat(f)
    T.isnil(shell.opts.borderColor, "and back")

    local t = ns.frames.target
    stub.units.target = { name = "Grell", isPlayer = false, reaction = 2, classification = "elite", level = 20 }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    ns.UF.UpdateAll(t, true)
    local ts = DaylightUI.Style.GetShell(t)
    T.falsy(t.crest:IsShown(), "no tab for the badge")
    T.rgb(ts.opts.borderColor, ns.UF.CREST_COLORS.gold, "the elite's gold on the border instead")
    DUI:Set("UnitFrames", "target.nameOnBar", false)
    stub.RunTimers()
    ns.UF.UpdateAll(t, true)
    T.truthy(t.crest:IsShown(), "with the tab back, the badge is back")
    T.isnil(ts.opts.borderColor, "and the border is plain")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("shell join: pieces in the shell's own border layers, painted with it", function()
    local DUI, ns = login()
    local Style = DUI.Style
    local f = ns.frames.player
    local s = Style.GetShell(f)
    local j = Style.ShellJoin(f)
    T.truthy(j, "a unit frame's shell takes a join")
    T.eq(Style.ShellJoin(f), j, "made once")
    T.eq(j.outline:GetParent(), s); T.eq(j.band:GetParent(), s); T.eq(j.shadow:GetParent(), s)
    local layer, sub = j.outline:GetDrawLayer(); T.eq(layer, "BORDER"); T.eq(sub, 0)
    layer, sub = j.band:GetDrawLayer(); T.eq(layer, "BORDER"); T.eq(sub, 3, "above the shell's band and lit line, so they never cross it")
    layer, sub = j.shadow:GetDrawLayer(); T.eq(layer, "BACKGROUND"); T.eq(sub, -8)
    DUI:Set("UnitFrames", "player.portraitLook", "classic")
    stub.RunTimers()
    ns.UF.UpdateAll(f, true)
    T.falsy(j.outline:IsShown() or j.band:IsShown() or j.shadow:IsShown(), "hidden until its owner lays it out")
    Style.PaintShellColors(s)
    local r, g, b, a = j.outline:GetVertexColor()
    T.near(r, Style.BORDER[1], 1e-6); T.near(a, DUI:Get("general", "borderAlpha"), 1e-6)
end)

T.test("shell join: its own band color for aggro, and back", function()
    local DUI, ns = login()
    local Style = DUI.Style
    local f = ns.frames.player
    local s, j = Style.GetShell(f), Style.ShellJoin(f)
    Style.SetJoinBand(j, s, { 1, 0, 0 })
    local r, g, b = j.band:GetVertexColor()
    T.near(r, 1, 1e-6); T.near(g, 0, 1e-6)
    T.falsy(s.opts.bandColor, "the bar's own border keeps its color")
    Style.SetJoinBand(j, s, nil)
    T.falsy(j.color)
    Style.JoinBandFromBoolean(j, s, true, { 1, 0, 0 })
    T.truthy(j.band.__vertexFromBoolean, "the client picks the color from a secret flag")
end)

T.test("shell join: a set that lives elsewhere is painted with a shell's colors", function()
    local DUI, ns = login()
    local Style = DUI.Style
    local f = ns.frames.player
    local own = { outline = f:CreateTexture(), band = f:CreateTexture(), shadow = f:CreateTexture(), side = "left" }
    Style.PaintJoin(own, Style.GetShell(f))
    local r, _, _, a = own.outline:GetVertexColor()
    T.near(r, Style.BORDER[1], 1e-6); T.near(a, DUI:Get("general", "borderAlpha"), 1e-6)
end)

T.test("shell join: follows a see-through border and a gradient border", function()
    local DUI, ns = login()
    local Style = DUI.Style
    local f = ns.frames.target
    local j = Style.ShellJoin(f)
    j.side = "right"
    DUI:Set("general", "borderAlpha", 0.5)
    stub.RunTimers()
    Style.PaintShellColors(Style.GetShell(f))
    local _, _, _, a = j.outline:GetVertexColor()
    T.near(a, 0.5, 1e-6)
    DUI:Set("general", "gradientBorder", true)
    stub.RunTimers()
    Style.PaintShellColors(Style.GetShell(f))
    local _, hi = Style.AccentPair()
    if hi then
        local r = j.band:GetVertexColor()
        T.near(r, hi[1], 1e-6, "the right end takes the sweep's right color")
    end
end)

T.test("socket: crop and join math", function()
    local _, ns = login()
    local S = ns.Socket
    -- A circle of 10 at (0, 20), a box from x 4..100, y 4..36.
    local x0, x1, y0, y1, u0, u1, v0, v1 = S.Crop(0, 20, 10, 4, 100, 4, 36)
    T.near(x0, 4, 1e-9); T.near(x1, 10, 1e-9); T.near(y0, 10, 1e-9); T.near(y1, 30, 1e-9)
    T.near(u0, 0.7, 1e-9); T.near(u1, 1, 1e-9); T.near(v0, 0, 1e-9); T.near(v1, 1, 1e-9)
    T.falsy(S.Crop(-50, 20, 10, 4, 100, 4, 36), "no overlap")
    T.near(S.JoinX(10, 6, 3, false), 5, 1e-9)       -- sqrt(100 - 36) - 3
    T.near(S.JoinX(10, 6, 3, true), 7, 1e-9)
    T.falsy(S.JoinX(5, 6, 3, false), "a ring shorter than the bar has no join")
end)

T.test("socket: by default the ring's outer band is part of the frame's border", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Stabby", isPlayer = true, class = "ROGUE", health = 5, maxHealth = 10 }
    end)
    local UF, Style, Pixel = ns.UF, DUI.Style, DUI.Pixel
    local f = ns.frames.player
    local p = f.portrait
    UF.UpdateAll(f, true)
    local one, T_ = Pixel.Px(f, 1), Pixel.Px(f, Style.BorderPx(f))
    local j = Style.GetShell(f).join
    T.truthy(f.socketOn)
    T.truthy(j.outline:IsShown() and j.band:IsShown() and j.shadow:IsShown())
    T.eq(j.outline.__texture, DUI.MEDIA .. "socket-disc.png")
    T.near(j.outline:GetWidth(), p:GetWidth(), 1e-6, "as big as the portrait")
    T.near(j.band:GetWidth(), p:GetWidth() - 2 * one, 1e-6, "one pixel of outline round the band")
    T.falsy(p.shadow:IsShown(), "one shadow, under the join")
    -- The mock-up's measurements, built out from the classic ring's radius.
    local S = ns.Socket
    local Rb = DaylightUI.Pixel.Snap(f, f:GetHeight() * UF.PORTRAIT_SIZE * S.SIZE / 2)
    local outside = (S.PICTURE + S.HAIR) * Rb / S.RING_WIDTHS.normal
    -- Classic's size, 0.755 of its radius, less what keeps the black gap
    -- inside the line whole pixels wide.
    local picture = math.min(S.PICTURE * Rb, (S.PICTURE + S.HAIR) * Rb - Pixel.Px(f, S.GAP_PX))
    T.near(p.mask:GetWidth() / 2, picture, 1e-6, "the picture")
    T.near(p.ring:GetWidth() * S.RING_OUTER / 2, outside, 1e-6, "the line's outside")
    T.near(outside - (S.PICTURE + S.HAIR) * Rb, 0.09 * Rb, 0.002 * Rb, "the line is 0.09 of the radius thick")
    T.near(p:GetWidth() / 2, outside + T_, 1e-6, "then the frame's whole border")
    T.near(p.disc:GetWidth() / 2, outside + one, 1e-6, "one pixel of black between the line and the band")
    T.truthy(p.ring:GetTexture():find("socket-ring-normal", 1, true), "the socket's own thin line")
    T.truthy(f.socket.gap:IsShown(), "the bar is cut back")
    T.truthy(f.socket.gap:GetWidth() <= f:GetWidth() - 2 * T_ + 1e-6, "only inside the border")
    T.truthy(f.socket.gap:GetHeight() <= f:GetHeight() - 2 * T_ + 1e-6)
    T.truthy(p.vignette:IsShown())
    T.truthy(f.__hitRect[1] < 0, "still clickable")
end)

T.test("socket: Classic is the ring as it was", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Stabby", isPlayer = true, class = "ROGUE", health = 5, maxHealth = 10 }
    end)
    local UF = ns.UF
    local f = ns.frames.player
    local p = f.portrait
    UF.UpdateAll(f, true)
    DUI:Set("UnitFrames", "player.portraitLook", "classic")
    stub.RunTimers()
    UF.UpdateAll(f, true)
    local j = DUI.Style.GetShell(f).join
    T.falsy(f.socketOn)
    T.falsy(j.outline:IsShown() or j.band:IsShown() or j.shadow:IsShown())
    T.falsy(f.socket.gap:IsShown()); T.falsy(p.vignette:IsShown())
    T.truthy(p.shadow:IsShown())
    local R = DaylightUI.Pixel.Snap(f, f:GetHeight() * UF.PORTRAIT_SIZE / 2)
    T.near(p:GetWidth(), 2 * R, 1e-6, "the classic ring's own size")
    T.near(p.ring:GetWidth(), 2 * R / UF.RING_OUTER, 1e-6)
    T.eq(p.ring:GetTexture(), (UF.RingFiles("normal", true)))
    T.near(f.ringReach, R + R * UF.PORTRAIT_OUT, 1e-6)
end)

T.test("socket: a taller frame grows the portrait, the band stays the border's thickness", function()
    local DUI, ns = login()
    local UF, Pixel = ns.UF, DUI.Pixel
    local f = ns.frames.player
    UF.UpdateAll(f, true)
    local before = f.portrait:GetWidth()
    DUI:Set("UnitFrames", "player.height", 70)
    stub.RunTimers()
    UF.UpdateAll(f, true)
    local j, one = DUI.Style.GetShell(f).join, Pixel.Px(f, 1)
    T.truthy(f.portrait:GetWidth() > before)
    T.near(j.outline:GetWidth(), f.portrait:GetWidth(), 1e-6)
    T.near(j.outline:GetWidth() - j.band:GetWidth(), 2 * one, 1e-6)
    T.truthy(f.socket.gap:GetHeight() <= f:GetHeight() + 1e-6)
end)

T.test("socket: square and angled use their own shape for every piece", function()
    local DUI, ns = login()
    local UF = ns.UF
    local f = ns.frames.target
    stub.units.target = { name = "Wolf", health = 5, maxHealth = 10 }
    for _, shape in ipairs({ "square", "angled" }) do
        DUI:Set("UnitFrames", "target.portraitShape", shape)
        stub.RunTimers()
        UF.UpdateAll(f, true)
        local art = UF.ShapeArt(shape, true)
        local j = DUI.Style.GetShell(f).join
        T.eq(j.outline.__texture, DUI.MEDIA .. "portrait-" .. art .. "-hole.png", shape)
        T.eq(j.band.__texture, DUI.MEDIA .. "portrait-" .. art .. "-hole.png")
        T.eq(j.shadow.__texture, DUI.MEDIA .. "portrait-" .. art .. "-shadow.png")
        T.eq(f.socket.gap.__texture, DUI.MEDIA .. "portrait-" .. art .. "-hole.png")
        T.eq(j.side, "right", "the target's portrait is at its right end")
    end
end)

T.test("socket: a thin border has no band; no portrait, no socket", function()
    local DUI, ns = login()
    local UF = ns.UF
    local f = ns.frames.player
    DUI:Set("general", "borderPx", 2)
    stub.RunTimers()
    UF.UpdateAll(f, true)
    local j = DUI.Style.GetShell(f).join
    T.truthy(j.outline:IsShown()); T.falsy(j.band:IsShown(), "a plain border is all outline")
    DUI:Set("UnitFrames", "player.portrait", "none")
    stub.RunTimers()
    UF.UpdateAll(f, true)
    T.falsy(f.socketOn); T.falsy(j.outline:IsShown()); T.falsy(f.socket.gap:IsShown())
end)

T.test("socket: a portrait on its own is a whole ring, and leaves its frame whole", function()
    local DUI, ns = login()
    local UF, Style, Pixel = ns.UF, DUI.Style, DUI.Pixel
    local f = ns.frames.player
    local p = f.portrait
    UF.UpdateAll(f, true)
    local s = Style.GetShell(f)
    DUI:Set("UnitFrames", "player.portraitAt", "free")
    stub.RunTimers()
    UF.UpdateAll(f, true)
    -- The portrait: the same band, closed, on the portrait itself.
    T.truthy(f.socketOn); T.truthy(f.portraitFree)
    local own = p.own
    T.eq(ns.Socket.Join(f), own)
    T.eq(own.outline:GetParent(), p); T.eq(own.band:GetParent(), p)
    T.truthy(own.outline:IsShown() and own.band:IsShown() and own.shadow:IsShown())
    local one = Pixel.Px(f.portraitHolder, 1)
    T.near(own.outline:GetWidth(), p:GetWidth(), 1e-6)
    T.near(own.band:GetWidth(), p:GetWidth() - 2 * one, 1e-6)
    T.truthy(p.vignette:IsShown())
    T.falsy(p.shadow:IsShown(), "one shadow, its own")
    T.truthy(p.top:GetFrameLevel() > p:GetFrameLevel(), "the inner ring stays over its own band in the holder")
    T.truthy(p.model:GetFrameLevel() > p:GetFrameLevel())
    local r = own.outline:GetVertexColor()
    T.near(r, Style.BORDER[1], 1e-6, "in its frame's border color")
    -- The frame: nothing left behind.
    T.falsy(s.join.outline:IsShown() or s.join.band:IsShown() or s.join.shadow:IsShown(), "no band left on the frame")
    T.falsy(f.socket.gap:IsShown(), "no cut-back")
    T.falsy(f.socket.cast:IsShown(), "no cast shadow")
    T.falsy(s.opts.coveredEnd, "its rounded corners are back")
    T.eq(f.ringInset, 0); T.eq(f.ringReach, 0)
    T.falsy(f.socketJoinX)
    local _, rel = f.status.icons.level:GetPoint(1)
    T.eq(rel, p, "the level badge rides at the ring's foot")
    -- And back on the frame, with no reload.
    DUI:Set("UnitFrames", "player.portraitAt", "frame")
    stub.RunTimers()
    UF.UpdateAll(f, true)
    T.falsy(own.outline:IsShown() or own.band:IsShown() or own.shadow:IsShown(), "its own ring is put away")
    T.truthy(s.join.outline:IsShown() and f.socket.gap:IsShown(), "the socket is back")
    T.eq(ns.Socket.Join(f), s.join)
end)

T.test("socket: a portrait on its own in Classic is the old ring", function()
    local DUI, ns = login()
    local UF = ns.UF
    local f = ns.frames.player
    DUI:Set("UnitFrames", "player.portraitLook", "classic")
    DUI:Set("UnitFrames", "player.portraitAt", "free")
    stub.RunTimers()
    UF.UpdateAll(f, true)
    T.falsy(f.socketOn); T.truthy(f.portrait.shadow:IsShown())
    T.falsy(f.portrait.own and f.portrait.own.outline:IsShown())
end)

T.test("socket: a 3D model stays inside the inner ring", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Stabby", isPlayer = true, class = "ROGUE", health = 5, maxHealth = 10 }
    end)
    local UF = ns.UF
    local f = ns.frames.player
    DUI:Set("UnitFrames", "player.portrait", "3d")
    stub.RunTimers()
    UF.UpdateAll(f, true)
    local p = f.portrait
    local inner = p.ring:GetWidth() * UF.RING_OUTER / 2
    T.truthy(p.model:IsShown())
    T.truthy(p.model:GetWidth() * math.sqrt(2) / 2 <= inner + 1e-6, "its corners end under the ring, not over the band")
    local _, _, opening = UF.RingFiles("slim")
    T.truthy(p.rim:GetWidth() / 2 >= inner * (opening - 0.01) - 1e-6, "the bezel reaches the thin ring's opening")
end)

-- Nothing hanging under the player frame, so the socket's level tag has its edge.
local function nothingUnder(DUI)
    DUI:Set("UnitFrames", "playerCastbar.at", "above")
    DUI:Set("UnitFrames", "swing.enabled", false)
    stub.RunTimers()
end

T.test("socket: the level badge sits where the ring meets the bar's bottom edge", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Stabby", isPlayer = true, class = "ROGUE", level = 60, health = 5, maxHealth = 10 }
    end)
    local UF = ns.UF
    local f = ns.frames.player
    nothingUnder(DUI)
    UF.UpdateAll(f, true)
    local pt, rel, rp, x, y = f.status.icons.level:GetPoint(1)
    T.eq(pt, "CENTER"); T.eq(rel, f); T.eq(rp, "BOTTOMLEFT")
    T.near(x, f.socketJoinX, 1e-6); T.near(y, 0, 1e-6)
    T.truthy(x > 0, "on the bar, past its end")
    local badge = f.status.icons.level
    local R = f.portrait:GetWidth() / 2
    T.eq(badge.__texture, ns.UF.LEVEL_TAG_FILE, "a slanted tag")
    T.near(badge:GetWidth(), 0.7 * R, 1e-6); T.near(badge:GetHeight(), 0.4 * R, 1e-6)
    local Rb = f.portrait.mask:GetWidth() / 2 / ns.Socket.PICTURE
    local off = DUI.Pixel.Snap(f, Rb * ns.UF.PORTRAIT_OUT)
    T.near(x, 0.7 * R - off, 1e-6, "0.7 of the radius past the ring's middle (on a whole pixel)")
    T.rgb(badge.__vertex, { 1, 1, 1 }, "its own colors, untinted")
    DUI:Set("UnitFrames", "player.portraitLook", "classic")
    stub.RunTimers()
    UF.UpdateAll(f, true)
    pt, rel = f.status.icons.level:GetPoint(1)
    T.eq(rel, f.portrait, "Classic keeps it at the ring's foot")
    T.eq(f.status.icons.level.__texture, DaylightUI.MEDIA .. "status-level.png", "and round")
end)

T.test("socket: the smallest portrait still meets the bar's edges, the tag on its join", function()
    local DUI, ns = login()
    local UF = ns.UF
    local f = ns.frames.player
    nothingUnder(DUI)
    DUI:Set("UnitFrames", "player.portraitScale", 0.6)
    stub.RunTimers()
    UF.UpdateAll(f, true)
    T.truthy(f.socketOn); T.truthy(f.socketJoinX)
    local _, rel = f.status.icons.level:GetPoint(1)
    T.eq(rel, f)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("socket: the level tag stays on the join under a cast bar until moved by choice", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Stabby", isPlayer = true, class = "ROGUE", level = 60, health = 5, maxHealth = 10 }
    end)
    local UF = ns.UF
    local f = ns.frames.player
    local function spot()
        stub.RunTimers()
        UF.UpdateAll(f, true)
        local _, rel = f.status.icons.level:GetPoint(1)
        return rel
    end
    DUI:Set("UnitFrames", "playerCastbar.at", "below")
    T.eq(spot(), f, "a cast bar under the frame: still the tag on the join")
    T.eq(f.status.icons.level.__texture, UF.LEVEL_TAG_FILE, "the slanted tag, not the round badge")
    DUI:Set("UnitFrames", "player.levelPos", "foot")
    T.eq(spot(), f.portrait, "picked under the portrait")
    T.truthy(f.status.icons.level.__texture ~= UF.LEVEL_TAG_FILE, "round there")
    local t = ns.frames.target
    stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2, level = 27 }
    DUI:Set("UnitFrames", "targetCastbar.at", "slide")
    stub.RunTimers()
    UF.UpdateAll(t, true)
    local _, trel = t.status.icons.level:GetPoint(1)
    T.eq(trel, t, "the target's sliding cast bar leaves the tag too")
end)

T.test("socket: aggro reddens the whole ring, outer band too, and leaves the bar's border", function()
    local DUI, ns = login()
    local UF = ns.UF
    local f = ns.frames.target
    wolf(3)
    UF.UpdateAll(f, true)
    UF.UpdateThreat(f)
    local s = DUI.Style.GetShell(f)
    local red = UF.THREAT_COLORS.aggro
    T.truthy(s.join.color, "the outer band goes red at once")
    T.near(s.join.color[1], red[1], 1e-6)
    T.truthy(f.socket.gapBand:IsShown(), "the band over the bar shows")
    T.rgb(f.socket.gapBand.__vertex, red, "and goes red with the rest of the ring")
    T.falsy(s.opts.bandColor, "the bar's border stays calm")
    wolf(nil)
    UF.UpdateThreat(f)
    T.falsy(s.join.color, "and comes back")
end)

T.test("socket: a secret tanking answer goes to the client for the band too", function()
    local DUI, ns = login()
    local UF = ns.UF
    local f = ns.frames.target
    wolf(nil)
    UF.UpdateAll(f, true)
    UF.ApplyThreat(f, nil, stub.Secret(true))
    local j = DUI.Style.GetShell(f).join
    T.truthy(j.band.__vertexFromBoolean); T.truthy(j.flag ~= nil)
    UF.ApplyThreat(f, nil, nil)
    T.isnil(j.flag)
end)

T.test("socket: a portrait on its own goes red on its own ring, never on the frame it left", function()
    local DUI, ns = login()
    local UF = ns.UF
    local f = ns.frames.target
    DUI:Set("UnitFrames", "target.portraitAt", "free")
    stub.RunTimers()
    wolf(3)
    UF.UpdateAll(f, true)
    UF.UpdateThreat(f)
    local s = DUI.Style.GetShell(f)
    T.truthy(f.portrait.own.color, "its own band is red")
    T.falsy(s.join and s.join.color, "nothing on the frame")
    T.falsy(s.opts.bandColor)
end)

T.test("socket: each frame's Portrait card has the look, for a portrait on its own too", function()
    local DUI, ns = login()
    for _, id in ipairs({ "player", "target", "focus", "party" }) do
        T.eq(DUI:Get("UnitFrames", id .. ".portraitLook"), "socket", id)
    end
    DUI.OptionsPanel.Show("UnitFrames.player")
    local item
    for _, card in ipairs(DUI.OptionsPanel.PageFrame().cards) do
        for _, row in ipairs(card.rows) do
            if row.item.label == "Portrait look" then item = row.item end
        end
    end
    T.truthy(item, "a row on the Player page")
    local get = function(key) return DUI:Get("UnitFrames", key) end
    T.falsy(item.disabled(get))
    DUI:Set("UnitFrames", "player.portraitAt", "free")
    T.falsy(item.disabled(get), "a portrait on its own picks its look too")
    DUI:Set("UnitFrames", "player.portrait", "none")
    T.truthy(item.disabled(get))
end)

T.test("upgrade step 23: a profile from before keeps the classic ring; a new one starts set into the frame", function()
    local _, ns = login()
    local p = { modules = { UnitFrames = { groupFrames = 20, target = { portraitLook = "socket" } } } }
    ns.UpgradeGroupFrames(p)
    local uf = p.modules.UnitFrames
    for _, id in ipairs({ "player", "target", "focus", "party", "arena" }) do
        T.eq(uf[id].portraitLook, "classic", id)
    end
    -- A player from several releases back runs every older step first, then this.
    p = { modules = { UnitFrames = { groupFrames = 12 } } }
    ns.UpgradeGroupFrames(p)
    T.eq(p.modules.UnitFrames.player.portraitLook, "classic")
    p = {}
    ns.UpgradeGroupFrames(p)
    T.isnil(p.modules.UnitFrames.player, "a new profile reads the default")
    local DUI = login()
    T.eq(DUI:Get("UnitFrames", "player.portraitLook"), "socket")
end)

-- A player updating from before Socket portraits: their profile has run the
-- unit frames' upgrade steps up to 20.
local function returning(player)
    local DUI, ns = stub.Load({ module = true, before = function()
        DaylightUIDB = { version = "1.9.6", notesSeen = "1.9.6", installerSeen = true,
                         profileData = { ["DPS/Tank"] = { general = {}, positions = {},
                                         modules = { UnitFrames = { groupFrames = 20, player = player } } } } }
    end })
    stub.Dismiss()
    return DUI, ns
end

T.test("new portrait mode: a returning player is asked once, sees both looks, and keeps what they pick", function()
    local DUI, ns = returning()
    local S = ns.Socket
    T.eq(DUI:Get("UnitFrames", "player.portraitLook"), "classic", "the upgrade kept the classic ring")
    T.truthy(S.ShouldAsk())
    S.Ask()
    local asking = DUI.Widgets.Asking()
    T.eq(asking.key, S.ASK_KEY)
    T.eq(asking.title, "New portrait mode")
    T.truthy(DaylightUIAsk.preview:IsShown(), "the box shows the two looks")
    local box = S.askBox
    T.truthy(box.frames.socket.socketOn, "one sample is set into its frame")
    T.falsy(box.frames.classic.socketOn, "the other is the classic ring")
    T.eq(DUI:Get("UnitFrames", "player.portraitLook"), "classic", "showing it changes nothing")
    stub.Answer(true)
    for _, id in ipairs({ "player", "target", "focus", "party" }) do
        T.eq(DUI:Get("UnitFrames", id .. ".portraitLook"), "socket", id)
    end
    T.truthy(DUI.DB.Root().portraitLookAsked)
    T.falsy(S.ShouldAsk(), "never again on this account")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("new portrait mode: Keep Classic changes nothing; a new player is never asked; not in a fight", function()
    local DUI, ns = returning()
    ns.Socket.Ask()
    stub.Answer(false)
    T.eq(DUI:Get("UnitFrames", "player.portraitLook"), "classic")
    T.falsy(ns.Socket.ShouldAsk())
    local _, fresh = login()
    T.falsy(fresh.Socket.ShouldAsk(), "a new profile starts set into the frame")
    DUI, ns = returning()
    stub.EnterCombat()
    ns.Socket.Ask()
    T.isnil(stub.Asked(), "nothing opens in a fight")
    stub.LeaveCombat()
    stub.RunTimers()
    T.eq(stub.Asked(), ns.Socket.ASK_KEY, "it comes once the fight ends")
end)

T.test("socket: aggro stays on the ring when it detaches or re-attaches, and through a repaint", function()
    local DUI, ns = login()
    local UF, Style = ns.UF, DUI.Style
    local f = ns.frames.target
    wolf(3)
    UF.UpdateAll(f, true)
    UF.UpdateThreat(f)
    DUI:Set("UnitFrames", "target.portraitAt", "free")
    stub.RunTimers()
    T.truthy(f.portrait.own.color, "the ring on its own is still red")
    DUI:Set("UnitFrames", "target.portraitAt", "frame")
    stub.RunTimers()
    local s = Style.GetShell(f)
    T.truthy(s.join.color, "and red again back on the frame")
    UF.ApplyThreat(f, nil, stub.Secret(true))
    local picks = 0
    local pick = s.join.band.SetVertexColorFromBoolean
    s.join.band.SetVertexColorFromBoolean = function(...) picks = picks + 1; return pick(...) end
    Style.PaintShellColors(s)
    T.eq(picks, 1, "a repaint hands the secret flag to the client again")
end)

T.test("a light made on the portrait after it was first placed keeps its place over it", function()
    local DUI, ns = login()
    local UF = ns.UF
    local f = ns.frames.player
    UF.UpdateAll(f, true)
    local late = CreateFrame("Frame", nil, f.portrait)
    late:SetFrameLevel(f.portrait:GetFrameLevel() + 4)
    DUI:Set("UnitFrames", "player.portraitAt", "free")
    stub.RunTimers()
    T.eq(late:GetFrameLevel(), f.portrait:GetFrameLevel() + 4)
end)

T.test("new portrait mode: the two samples show a portrait even with the player's off", function()
    local _, ns = returning({ portrait = "none" })
    ns.Socket.Ask()
    T.eq(stub.Asked(), ns.Socket.ASK_KEY, "the target's classic ring still asks")
    T.truthy(ns.Socket.askBox.frames.socket.portrait:IsShown())
    T.truthy(ns.Socket.askBox.frames.classic.portrait:IsShown())
end)

T.test("socket: the border curves on into the bar the same at the top and the bottom", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Stabby", isPlayer = true, class = "ROGUE", health = 5, maxHealth = 10 }
    end)
    local UF = ns.UF
    local f = ns.frames.player
    UF.UpdateAll(f, true)
    local j = DUI.Style.GetShell(f).join
    for i = 1, 2 do
        T.truthy(j.bands[i]:IsShown(), "a fillet at the top and the bottom edge, one piece with its own edge")
        T.falsy(j.outlines[i]:IsShown())
        T.eq(j.bands[i].__texture, DUI.MEDIA .. "socket-fillet.png")
    end
    local s = DUI.Style.GetShell(f)
    T.falsy(s.lit:IsShown(), "no lit line on top that the bottom doesn't have")
    local _, _, _, _, top = j.bands[1]:GetPoint(1)
    local _, _, _, _, bottom = j.bands[2]:GetPoint(2)
    T.near(top, f:GetHeight() - bottom, 1e-6, "the same at the top and the bottom")
    T.truthy(f.socket.gapBand:IsShown(), "inside the bar the ring keeps its band")
    T.eq(f.socket.gapBand:GetVertexColor(), (j.band:GetVertexColor()), "in the band's color")
    DUI:Set("UnitFrames", "player.portraitShape", "square")
    stub.RunTimers()
    T.falsy(j.bands[1]:IsShown() or j.bands[2]:IsShown(), "square: a clean right angle, no fillet")
    T.truthy(f.socket.gapBand:IsShown(), "and its band all the way round")
    DUI:Set("UnitFrames", "player.portraitAt", "free")
    stub.RunTimers()
    T.falsy(j.outlines[1]:IsShown() or j.bands[1]:IsShown(), "on its own, nothing left on the frame")
    T.truthy(DUI.Style.GetShell(f).lit:IsShown(), "and the frame's lit line is back")
    DUI:Set("UnitFrames", "player.portraitLook", "classic")
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("socket: a fillet's box follows the ring and the bar's edge", function()
    local _, ns = login()
    local S = ns.Socket
    local x0, x1, y0, y1 = S.FilletBox(1, 0.75)
    T.near(x0, 0.3735, 1e-3); T.near(x1, 1.0614, 1e-3); T.near(y0, 0.75, 1e-9); T.near(y1, 0.9276, 1e-3)
    T.falsy(S.FilletBox(0.7, 0.75), "no fillet without a join")
end)

T.test("socket: with a border as thin as the mock-up's the measurements are its own", function()
    local DUI, ns = login()
    DUI:Set("general", "borderPx", 5)
    stub.RunTimers()
    local f = ns.frames.player
    ns.UF.UpdateAll(f, true)
    local p, S = f.portrait, ns.Socket
    local Rb = DUI.Pixel.Snap(f, f:GetHeight() * ns.UF.PORTRAIT_SIZE * S.SIZE / 2)
    local one = DUI.Pixel.Px(f, 1)
    T.near(p.mask:GetWidth() / 2, math.min(0.755 * Rb, 0.785 * Rb - DUI.Pixel.Px(f, S.GAP_PX)), 1e-6, "the picture")
    T.near(p.ring:GetWidth() * S.RING_OUTER / 2, 0.875 * Rb, 0.002 * Rb, "the line's outside")
    local T_ = DUI.Pixel.Px(f, DUI.Style.BorderPx(f))
    T.near(p:GetWidth() / 2, 0.875 * Rb + T_, 0.002 * Rb, "the line, then the frame's whole border")
end)

T.test("new portrait mode: the two samples are the standard frame, not the player's own setup", function()
    local DUI, ns = returning({ portrait = "3d", portraitRing = "light", height = 60, nameOnBar = true })
    local box = ns.Sample.Looks(UIParent)
    box.Refresh(340)
    for _, key in ipairs({ "socket", "classic" }) do
        local f = box.frames[key]
        T.eq(f.portraitMode, ns.DEFAULTS.player.portrait, key .. ": the default picture")
        T.near(f:GetHeight(), ns.DEFAULTS.player.height, 1, key .. ": the default height, not the player's 60")
    end
    T.eq(DUI:Get("UnitFrames", "player.height"), 60, "the player's own settings untouched")
    T.falsy(box.frames.socket.status.icons.pvp:IsShown(), "no PvP badge on the looks")
    for _, key in ipairs({ "socket", "classic" }) do
        local f = box.frames[key]
        T.falsy((f.heals and f.heals:IsShown()) or (f.absorbs and f.absorbs:IsShown())
            or (f.overshield and f.overshield:IsShown()), key .. ": no heal or shield bars at the health's end")
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("socket: no bar of the frame draws over the ring, and it holds still while the portrait pops in", function()
    local DUI, ns = login()
    local f = ns.frames.target
    stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2, threat = 3 }
    ns.UF.UpdateAll(f, true)
    local p = f.portrait
    for _, bar in ipairs({ f.health, f.power }) do
        if bar then T.truthy(bar:GetFrameLevel() < f.socket:GetFrameLevel(), "the bars sit under the ring's part over the bar") end
    end
    T.truthy(f.socket:GetFrameLevel() < p:GetFrameLevel(), "and the portrait, with its glow, over it")
    local _, _, _, x = f.socket.gap:GetPoint(1)
    ns.UF.PlacePortrait(f, 0.5)
    local _, _, _, x2 = f.socket.gap:GetPoint(1)
    T.eq(f.socket.gap:GetParent(), f.socket, "not on the portrait, which pops")
    T.near(x2, x, 1e-9, "unmoved mid-pop")
    ns.UF.PlacePortrait(f, 1)
end)

T.test("socket: square, no lit line on the bar to end at the square's side", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "player.portraitShape", "square")
    stub.RunTimers()
    local f = ns.frames.player
    T.falsy(DUI.Style.GetShell(f).lit:IsShown())
    DUI:Set("UnitFrames", "player.portraitLook", "classic")
    stub.RunTimers()
    T.truthy(DUI.Style.GetShell(f).lit:IsShown(), "Classic keeps the frame's lit line")
end)

T.test("target of target, focus target and pet: a portrait when picked, off by default", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Stabby", isPlayer = true, class = "HUNTER", health = 5, maxHealth = 10 }
        stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2, health = 5, maxHealth = 10 }
        stub.units.targettarget = { name = "Stabby", isPlayer = true, class = "HUNTER", health = 5, maxHealth = 10 }
        stub.units.pet = { name = "Cat", isPlayer = false, reaction = 5, health = 5, maxHealth = 10 }
    end)
    for _, unit in ipairs({ "targettarget", "focustarget", "pet" }) do
        local f = ns.frames[unit]
        T.truthy(f.portrait, unit .. " has the pieces")
        T.eq(DUI:Get("UnitFrames", unit .. ".portrait"), "none", unit .. " off by default")
        T.falsy(DUI:Get("UnitFrames", unit .. ".showLevel"), "no level badge out of the blue")
    end
    local tot, pet = ns.frames.targettarget, ns.frames.pet
    ns.UF.UpdateAll(tot, true); ns.UF.UpdateAll(pet, true)
    T.falsy(tot.portrait:IsShown()); T.falsy(pet.portrait:IsShown())
    DUI:Set("UnitFrames", "targettarget.portrait", "class")
    DUI:Set("UnitFrames", "pet.portrait", "2d")
    stub.RunTimers()
    ns.UF.UpdateAll(tot, true); ns.UF.UpdateAll(pet, true)
    T.truthy(tot.portrait:IsShown(), "the class icon ring on the target of target")
    T.eq(tot.portrait.icon.__texture, DUI.MEDIA .. "class\\hunter.tga")
    T.truthy(pet.portrait:IsShown(), "the pet's face")
    T.truthy(tot.__hitRect[1] < 0 or tot.__hitRect[2] < 0, "the ring is clickable")
end)

-- At a UI scale like 0.71 on a 1080-line screen, the ring's middle sat half a
-- pixel off and its picture an odd number of pixels wide at some Portrait
-- sizes (100, 105, 110 %), so one side drew a pixel wider than the other.
T.test("the ring's middle and picture land on whole pixels at any portrait size and UI scale", function()
    local DUI, ns = login(function()
        stub.physW, stub.physH = 2560, 1080
        stub.units.player = { name = "Stabby", isPlayer = true, class = "ROGUE", health = 5, maxHealth = 10 }
    end)
    local UF, Pixel = ns.UF, DUI.Pixel
    Pixel.Refresh()
    UIParent:SetScale(0.71)
    local f = ns.frames.player
    local p = f.portrait
    local function whole(v, what)
        local px = v / Pixel.Unit(f)
        T.near(px, math.floor(px + 0.5), 1e-3, what .. " is " .. px .. " px")
    end
    for _, look in ipairs({ "classic", "socket" }) do
        DUI:Set("UnitFrames", "player.portraitLook", look)
        for _, scale in ipairs({ 0.95, 1, 1.05, 1.1, 1.15, 1.2 }) do
            DUI:Set("UnitFrames", "player.portraitScale", scale)
            stub.RunTimers()
            UF.UpdateAll(f, true)
            local _, _, _, x, y = p:GetPoint(1)
            local label = look .. " at " .. scale
            whole(x, label .. ": the middle across")
            whole(y, label .. ": the middle up")
            -- Centered on a whole pixel, the ring's picture draws the same on both sides.
            local rp, rrel, rrp, rx, ry = p.ring:GetPoint(1)
            T.eq(rp, "CENTER"); T.eq(rrel, p); T.eq(rrp, "CENTER"); T.eq(rx, 0); T.eq(ry, 0)
        end
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game on elites, rares and bosses: a thin sliver of the dragon showed
-- between the portrait ring and its glow on one side. The dragon's opening
-- must sit exactly on the ring's outer edge, on the same whole pixels, at any
-- Portrait size and UI scale. Rounding the dragon's own size moves its opening
-- off the ring by a fraction of a pixel.
T.test("the dragon's opening lands on the ring's own whole pixels at any size and UI scale", function()
    local DUI, ns = login(function()
        stub.physW, stub.physH = 2560, 1080
        stub.units.player = { name = "Stabby", isPlayer = true, class = "ROGUE", health = 5, maxHealth = 10 }
    end)
    local UF, Pixel = ns.UF, DUI.Pixel
    local f = ns.frames.player
    local p = f.portrait
    DUI:Set("UnitFrames", "player.portraitDragon", true)
    for _, ui in ipairs({ 0.64, 0.71, 0.8, 0.9, 1 }) do
        UIParent:SetScale(ui)
        Pixel.Refresh()
        for _, look in ipairs({ "classic", "socket" }) do
            DUI:Set("UnitFrames", "player.portraitLook", look)
            for _, scale in ipairs({ 0.8, 0.9, 0.95, 1, 1.05, 1.1, 1.15, 1.2, 1.3 }) do
                DUI:Set("UnitFrames", "player.portraitScale", scale)
                stub.RunTimers()
                UF.UpdateAll(f, true)
                local label = look .. " at " .. scale .. ", UI scale " .. ui
                T.truthy(p.elite:IsShown(), label .. ": the dragon shows")
                -- Both pictures are centered on the portrait's middle.
                local ep, erel, erp, ex, ey = p.elite:GetPoint(1)
                T.eq(ep, "CENTER"); T.eq(erel, p); T.eq(erp, "CENTER"); T.eq(ex, 0); T.eq(ey, 0)
                local u = Pixel.Unit(f)
                local ring = p.ring:GetWidth() * UF.RING_OUTER / 2 / u
                local opening = p.elite:GetWidth() * UF.DRAGON_RING * UF.RING_OUTER / 2 / u
                T.near(opening, ring, 1e-3, label .. ": the dragon's opening is " .. opening
                    .. " px from the middle, the ring's edge " .. ring .. " px")
                if look == "classic" then
                    T.near(ring, math.floor(ring + 0.5), 1e-3, label .. ": the ring's edge on a whole pixel")
                end
            end
        end
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: specks of bright color sat in the socket's black gap round
-- many class icons. The gap was a share of the ring's size, under one screen
-- pixel at normal sizes, so the picture's soft cut edge lay over it and the
-- bright parts of the art showed there. The gap must be whole pixels wide.
T.test("socket: the picture keeps two screen pixels of black from the ring's line", function()
    local DUI, ns = login(function()
        stub.physW, stub.physH = 2560, 1080
        stub.units.player = { name = "Stabby", isPlayer = true, class = "ROGUE", health = 5, maxHealth = 10 }
    end)
    local UF, Pixel, Socket = ns.UF, DUI.Pixel, ns.Socket
    Pixel.Refresh()
    local function gapPx(f, what)
        local p = f.portrait
        T.truthy(f.socketOn, what .. ": the socket look is on")
        local s = p.shapeArt and UF.SQUARE or 1
        local ratio = Socket.RING_WIDTHS[DUI:Get("UnitFrames", "player.portraitRingWidth")]
        local lineInside = p.ring:GetWidth() / 2 * UF.RING_OUTER * ratio * s
        local picture = p.mask:GetWidth() / 2
        local gap = (lineInside - picture) / Pixel.Unit(f)
        T.truthy(gap >= 2 - 1e-3, what .. ": the black gap is " .. gap .. " px")
        -- Seen in game after that: a ring of bright specks still sat on the
        -- picture's edge. The dark shading over the picture was cut by the
        -- same round mask, so the picture's soft edge pixels were shaded
        -- less than the pixels just inside them. The shading reaches past the
        -- picture's edge into the black, and never onto the line.
        local shade = p.vignetteMask:GetWidth() / 2
        T.near(p.vignette:GetWidth() / 2, shade, 1e-6, what .. ": the shading fills its mask")
        local past = (shade - picture) / Pixel.Unit(f)
        T.truthy(past >= 2 - 1e-3, what .. ": the shading reaches " .. past .. " px past the picture")
        T.truthy(shade <= lineInside + 1e-6, what .. ": the shading stays inside the line")
    end
    for _, ui in ipairs({ 0.71, 1 }) do
        UIParent:SetScale(ui)
        for _, shape in ipairs({ "round", "square" }) do
            for _, width in ipairs({ "thin", "normal", "thick" }) do
                for _, size in ipairs({ 0.6, 1, 1.5 }) do
                    DUI:Set("UnitFrames", "player.portraitShape", shape)
                    DUI:Set("UnitFrames", "player.portraitRingWidth", width)
                    DUI:Set("UnitFrames", "player.portraitScale", size)
                    stub.RunTimers()
                    local f = ns.frames.player
                    UF.UpdateAll(f, true)
                    gapPx(f, "player, " .. shape .. ", " .. width .. " at " .. size .. ", UI scale " .. ui)
                end
            end
        end
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A player's ask: with the portrait on its own, a right click on it opened
-- nothing; only the health bar opened the unit's menu.
T.test("a portrait on its own targets and opens the unit's menu, and follows its holder", function()
    local DUI, ns = login()
    stub.RunTimers()
    local f = ns.frames.target
    T.isnil(f.portraitClick, "nothing made while the portrait sits on the frame")
    DUI:Set("UnitFrames", "target.portraitAt", "free")
    stub.RunTimers()
    local b, h = f.portraitClick, f.portraitHolder
    T.truthy(b, "a click button over the portrait")
    T.eq(b:GetParent(), f, "inside the secure frame, so it shows with the unit")
    T.truthy(b:IsProtected())
    T.eq(b:GetAttribute("useparent-unit"), true)
    T.eq(b:GetAttribute("*type1"), "target")
    T.eq(b:GetAttribute("*type2"), "togglemenu")
    local _, rel = b:GetPoint(1)
    T.truthy(rel ~= h, "never anchored to the holder")
    T.near(b:GetWidth() * b:GetEffectiveScale(), h:GetWidth() * h:GetEffectiveScale())
    -- Moved in unlock mode: the click goes along.
    DUI.DB.Positions()[ns.UF.PORTRAIT_FREE.target] = { 300, -50 }
    DUI.Movers.Apply(ns.UF.PORTRAIT_FREE.target)
    stub.RunTimers()
    local hp, hrel, hrp, hx, hy = h:GetPoint(1)
    local bp, brel, brp, bx, by = b:GetPoint(1)
    T.eq(bp, hp); T.eq(brel, hrel); T.eq(brp, hrp)
    local k = h:GetEffectiveScale() / b:GetEffectiveScale()
    T.near(bx, hx * k); T.near(by, hy * k)
    -- In a fight a move waits, nothing protected is touched.
    stub.EnterCombat()
    DUI.DB.Positions()[ns.UF.PORTRAIT_FREE.target] = { 100, 0 }
    DUI.Movers.Apply(ns.UF.PORTRAIT_FREE.target)
    stub.LeaveCombat()
    stub.RunTimers()
    _, _, _, bx = b:GetPoint(1)
    T.near(bx, (select(4, h:GetPoint(1))) * k)  -- caught up after the fight
    DUI:Set("UnitFrames", "target.portraitAt", "frame")
    stub.RunTimers()
    T.falsy(b:IsShown(), "back on the frame, the frame's own click is enough")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- How far in from the frame's outer end a bar's side starts, following its
-- anchors back to the frame (the target's health hangs off the separator).
local function sideGap(f, region, side)
    for i = 1, region:GetNumPoints() do
        local pt, rel, rp, x = region:GetPoint(i)
        if pt:find(side) and rp:find(side) then
            local gap = side == "LEFT" and x or -x
            if rel == f then return gap end
            return gap + sideGap(f, rel, side)
        end
    end
    error("no " .. side .. " point")
end

-- The ring's outline, measured from the frame's outer end, on the row y up from
-- the frame's bottom. A square or angled portrait has a straight inner side.
local function ringEdge(f, y, square)
    local half = (f.ringInset + f.ringReach) / 2
    local off = (f.ringReach - f.ringInset) / 2
    local dy = math.abs(y - (f:GetHeight() / 2 + (f.portraitY or 0)))
    if dy >= half then return 0 end
    if square then return half - off end
    return math.sqrt(half * half - dy * dy) - off
end

T.test("a portrait never hides the end of the health or power bar", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Stabby", isPlayer = true, class = "ROGUE", health = 5, maxHealth = 10 }
        stub.units.target = { name = "Wolf", reaction = 2, health = 5, maxHealth = 10, power = 1, maxPower = 2 }
        stub.units.focus = { name = "Wolf", reaction = 2, health = 5, maxHealth = 10, power = 1, maxPower = 2 }
    end)
    for _, look in ipairs({ "socket", "classic" }) do
        for _, shape in ipairs({ "round", "square", "angled" }) do
            for _, id in ipairs({ "player", "target", "focus" }) do
                DUI:Set("UnitFrames", id .. ".portraitLook", look)
                DUI:Set("UnitFrames", id .. ".portraitShape", shape)
                DUI:Set("UnitFrames", id .. ".healthTextPos", "center")
                stub.RunTimers()
                local f = ns.frames[id]
                local what = look .. " " .. shape .. " " .. id
                T.truthy(f.portrait:IsShown() and f.ringInset > 0, what .. ": the ring sits on the frame")
                local side = f.spec.slant == "left" and "RIGHT" or "LEFT"
                local H, T0 = f:GetHeight(), -select(5, f.health:GetPoint(1))
                local ph = f.power:GetHeight() + f.separator:GetHeight()
                -- Each bar starts where the ring's outline crosses the bar's
                -- edge farthest from the ring's middle: its empty end is the
                -- first thing past the ring, and a full bar still meets it.
                local sq = shape ~= "round"
                local function starts(y0, y1)
                    return math.max(T0, math.min(ringEdge(f, y0, sq), ringEdge(f, y1, sq)))
                end
                T.near(sideGap(f, f.health, side), starts(T0 + ph, H - T0), 0.6,
                    what .. ": the health bar starts at the ring")
                T.near(sideGap(f, f.power, side), starts(T0, T0 + f.power:GetHeight()), 0.6,
                    what .. ": the power bar starts at the ring")
                -- Less than a few pixels of either bar is left under the ring.
                T.truthy(ringEdge(f, (T0 + ph + H - T0) / 2, sq) - sideGap(f, f.health, side) < 4.5,
                    what .. ": next to nothing of the health bar hides under the ring")
                -- Centered health text sits on the bar, so it is centered on
                -- what shows.
                local pt, rel = f.percentText:GetPoint(1)
                T.eq(pt, "CENTER"); T.eq(rel, f.health)
                -- The empty part still reaches the border under the ring, so
                -- the frame looks as it did.
                T.near(sideGap(f, DUI.Style.BarBack(f.health), side), T0, 0.01,
                    what .. ": the health bar's empty part runs on under the ring")
                T.near(sideGap(f, f.separator, side), T0, 0.01, what .. ": the line between the bars runs on under the ring")
            end
        end
    end
    -- Ribbon: the ring covers the power line under the frame too.
    DUI:Set("UnitFrames", "player.portraitLook", "socket")
    DUI:Set("UnitFrames", "player.portraitShape", "round")
    ns.SetStyle("look.style", "ribbon")
    stub.RunTimers()
    local f = ns.frames.player
    local line = f.line
    T.truthy(line:IsShown(), "Ribbon hangs the power line")
    local _, _, _, lx, ly = line.set.power:GetPoint(1)
    -- The line hangs gap below the frame: its top and bottom rows in the frame's terms.
    local gap = -select(5, line:GetPoint(1))
    local edge = math.min(ringEdge(f, -gap + ly, false), ringEdge(f, -gap - line:GetHeight() - ly, false))
    T.truthy(edge > -ly, "the ring reaches over the line's end")
    T.near(lx, edge, 0.6, "Ribbon's power line starts at the ring")
    local T0 = -select(5, f.health:GetPoint(1))
    T.near(sideGap(f, f.health, "LEFT"), math.min(ringEdge(f, f:GetHeight() - T0, false), ringEdge(f, T0, false)), 0.6,
        "Ribbon's health starts at the ring")
    T.near(sideGap(f, DUI.Style.BarBack(line.set.power), "LEFT"), -ly, 0.01, "the line's empty part runs on under the ring")
    ns.SetStyle("look.style", "daylight")
    stub.RunTimers()
    -- On its own, the portrait leaves the bars their whole length.
    DUI:Set("UnitFrames", "player.portraitAt", "free")
    stub.RunTimers()
    T.near(sideGap(f, f.health, "LEFT"), -select(5, f.health:GetPoint(1)), 0.01, "a portrait on its own")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
