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

T.test("the Extras page has a line of icons per class, only with the pack", function()
    local function picker(DUI)
        DUI.OptionsPanel.Show("UnitFrames.extras")
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
    T.truthy(f.ribbon)
    T.truthy(f.crestShown)
    T.falsy(f.tabEdge:IsShown())
    DUI:Set("UnitFrames", "target.style", "daylight")
    ns.UF.UpdateAll(f, true)
    T.falsy(f.ribbon)
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
    T.near(p.elite:GetWidth(), p.ring:GetWidth() / ns.UF.DRAGON_RING, 0.01, "drawn bigger so its ring lines up")
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
    DUI:Set("UnitFrames", "player.portrait", "3d")
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
    local UF = ns.UF
    local f = ns.frames.player
    local p = f.portrait
    UF.UpdateAll(f, true)
    T.truthy(p.ring:GetTexture():find("portrait-band.png", 1, true), "normal, with its line, by default")
    local R = p:GetWidth() / 2
    T.near(p.radius, R * (1 + UF.RING_WIDTHS.normal) / 2, 1e-6)
    local normalMask = p.mask:GetWidth()
    DUI:Set("UnitFrames", "portraits.ringWidth", "thick")
    DUI:Set("UnitFrames", "portraits.ringLine", false)
    stub.RunTimers()
    UF.UpdateAll(f, true)
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
