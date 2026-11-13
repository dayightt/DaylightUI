local stub = require("stub")

local function login() return stub.Load({ module = true }) end

T.test("the raid header: groups as columns, left to right, only in a raid", function()
    local DUI, ns = login()
    local h = ns.Raid.header
    T.eq(h:GetAttribute("groupBy"), "GROUP")
    T.eq(h:GetAttribute("maxColumns"), 8); T.eq(h:GetAttribute("unitsPerColumn"), 5)
    T.eq(h:GetAttribute("columnAnchorPoint"), "LEFT")
    T.eq(h.__stateDriver.visibility, "[@raid1,exists] show; hide")
    T.truthy(DUI.Movers.Get("unitframes.raid"))
    local cfg = DUI:Get("UnitFrames", "raid")
    local w = ns.Raid.holder:GetWidth()
    T.truthy(w < 700, "all eight groups fit across")
    DUI:Set("UnitFrames", "raid.enabled", false)
    T.isnil(h.__stateDriver.visibility)
end)

T.test("Use in a party: the raid tiles show in a party and the party frames step aside", function()
    local DUI, ns = login()
    local h, ph = ns.Raid.header, ns.Party.header
    T.eq(h:GetAttribute("showParty"), false, "off by default")
    DUI:Set("UnitFrames", "raid.showInParty", true)
    stub.RunTimers()
    T.eq(h.__stateDriver.visibility, "[@raid1,exists][@party1,exists][group] show; hide")
    T.eq(h:GetAttribute("showParty"), true)
    for _, gh in ipairs(ns.Raid.group.headers) do T.eq(gh:GetAttribute("showParty"), true) end
    T.eq(ph.__stateDriver.visibility, "hide")
    -- The raid frames off: the party frames come back.
    DUI:Set("UnitFrames", "raid.enabled", false)
    stub.RunTimers()
    T.eq(h:GetAttribute("showParty"), false)
    T.eq(ph.__stateDriver.visibility, "[@raid1,exists] hide; [@party1,exists][group] show; hide")
end)

T.test("a button the header makes is dressed and follows its unit", function()
    local _, ns = login()
    local b = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton1", ns.Raid.header)
    b:SetAttribute("unit", "raid3")
    stub.units.raid3 = { name = "Teft", isPlayer = true, class = "WARRIOR", health = 40, maxHealth = 80, threat = 3 }
    ns.Raid.header.initialConfigFunction(ns.Raid.header, b:GetName())
    T.truthy(b.health, "built")
    T.eq(b.nameText.__text, "Teft")
    T.eq(DaylightUI.Style.GetShell(b).opts.borderColor, ns.UF.THREAT_COLORS.aggro, "aggro on its border")
    T.truthy(b.power:IsShown(), "a thin power bar along the bottom")
    stub.units.raid7 = { name = "Rock", isPlayer = true, class = "HUNTER", health = 80, maxHealth = 80 }
    b:SetAttribute("unit", "raid7")
    b:GetScript("OnAttributeChanged")(b, "unit", "raid7")
    T.eq(b.nameText.__text, "Rock")
end)

T.test("raid tiles have their own name color", function()
    local DUI, ns = login()
    T.eq(ns.DEFAULTS.raid.nameColor, "global", "follows the Colors page by default")
    DUI:Set("UnitFrames", "raid.nameColor", "classGradient")
    stub.RunTimers()
    local b = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton1", ns.Raid.header)
    b:SetAttribute("unit", "raid3")
    stub.units.raid3 = { name = "Teft", isPlayer = true, class = "WARRIOR", health = 40, maxHealth = 80 }
    ns.Raid.header.initialConfigFunction(ns.Raid.header, b:GetName())
    T.eq(b.nameText.__text, DUI.Gradients.Text("WARRIOR", "Teft"))
end)

T.test("test mode shows a sample raid of forty; party frames hide in a raid", function()
    local DUI, ns = login()
    DUI.SetTestMode(true)
    local shown = 0
    for _, b in ipairs(ns.Raid.preview) do if b:IsShown() then shown = shown + 1 end end
    T.eq(shown, 40)
    T.eq(ns.Raid.preview[1].nameText.__text, "Kaladin")
    local _, _, _, x = ns.Raid.preview[6]:GetPoint(1)
    T.truthy(x > 0, "the second group starts a new column to the right")
    DUI.SetTestMode(false)
    T.falsy(ns.Raid.preview[1]:IsShown())
end)

T.test("each raid tile gets a one-icon dispel container on its unit", function()
    local DUI, ns = login()
    local b = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton2", ns.Raid.header)
    b:SetAttribute("unit", "raid5")
    stub.units.raid5 = { name = "Lirin", isPlayer = true, class = "PRIEST", health = 10, maxHealth = 10 }
    ns.Raid.header.initialConfigFunction(ns.Raid.header, b:GetName())
    local c = b.dispel
    T.truthy(c)
    T.eq(c.__groups.dispel.filter, "HARMFUL|RAID_PLAYER_DISPELLABLE")
    T.eq(c.__groups.dispel.max, 1)
    T.eq(c.__unit, "raid5")
    T.truthy(c.__groups.dispel.button.__dispel, "dispel-colored edge")
    b:SetAttribute("unit", "raid9")
    b:GetScript("OnAttributeChanged")(b, "unit", "raid9")
    T.eq(c.__unit, "raid9", "follows the tile's unit")
    DUI:Set("UnitFrames", "raid.showDispel", false)
    T.eq(c.__groups.dispel.max, 0, "icon off: the glow has its own container")
    T.eq(b.glowBox.__unit, "raid9", "which follows the tile's unit too")
    T.eq(b.glowBox.__groups.glow.max, 1)
    DUI:Set("UnitFrames", "raid.dispelGlow", false)
    T.eq(b.glowBox.__groups.glow.max, 0)
end)

T.test("the dispel highlight: border and tint on the tile, and the any-debuff group", function()
    local DUI, ns = login()
    local b = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton2b", ns.Raid.header)
    b:SetAttribute("unit", "raid5")
    stub.units.raid5 = { name = "Lirin", isPlayer = true, class = "PRIEST", health = 10, maxHealth = 10 }
    ns.Raid.header.initialConfigFunction(ns.Raid.header, b:GetName())
    local c = b.dispel
    local hl = c.__groups.dispel.button.highlight
    T.truthy(hl, "highlight textures on the aura button")
    T.falsy(hl.tint:IsShown(), "off by default")
    T.falsy(hl.strips[1]:IsShown())
    T.eq(c.__groups.dispel.max, 1)
    T.isnil(c.__groups.dispelAll, "the any-debuff group: added when picked")
    DUI:Set("UnitFrames", "raid.dispelHighlight", "border")
    T.truthy(hl.strips[1]:IsShown())
    T.falsy(hl.tint:IsShown())
    DUI:Set("UnitFrames", "raid.dispelHighlight", "tint")
    T.falsy(hl.strips[1]:IsShown())
    T.truthy(math.abs(hl.tint:GetAlpha() - 0.3) < 0.001, "default strength")
    DUI:Set("UnitFrames", "raid.dispelAlpha", 0.6)
    T.truthy(math.abs(hl.tint:GetAlpha() - 0.6) < 0.001)
    -- Icon off, highlight on: the group still runs.
    DUI:Set("UnitFrames", "raid.showDispel", false)
    T.eq(c.__groups.dispel.max, 1)
    DUI:Set("UnitFrames", "raid.dispelOnlyMine", false)
    T.eq(c.__groups.dispel.max, 0)
    T.eq(c.__groups.dispelAll.filter, "HARMFUL")
    T.eq(c.__groups.dispelAll.max, 1)
    DUI:Set("UnitFrames", "raid.dispelHighlight", "none")
    T.eq(c.__groups.dispelAll.max, 0, "nothing of the corner icon's left on")
    -- The glow (on by default) runs on its own container, under the portrait.
    T.eq(b.glowBox.__groups.glowAll.max, 1)
    DUI:Set("UnitFrames", "raid.dispelGlow", false)
    T.eq(b.glowBox.__groups.glowAll.max, 0)
end)

T.test("raid tiles show the raid marker in the bar's corner and a leader crown", function()
    local DUI, ns = login()
    local b = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton3", ns.Raid.header)
    b:SetAttribute("unit", "raid2")
    stub.units.raid2 = { name = "Adolin", isPlayer = true, class = "WARRIOR", raidTarget = 8, leader = true }
    ns.Raid.header.initialConfigFunction(ns.Raid.header, b:GetName())
    T.truthy(b.marker:IsShown())
    local p, rel = b.marker:GetPoint(1)
    T.eq(p, "BOTTOMRIGHT"); T.eq(rel, b.health, "small, in the health's corner")
    T.eq(stub.Plain(b.marker.__cell), 8, "the skull's cell of our marker sheet")
    T.truthy(b.leaderIcon:IsShown())
    DUI:Set("UnitFrames", "raid.showLeader", false)
    T.falsy(b.leaderIcon:IsShown())
end)

T.test("raid tiles: in rows", function()
    local DUI, ns = login()
    local h = ns.Raid.header
    DUI:Set("UnitFrames", "raid.direction", "rows")
    stub.RunTimers()
    T.eq(h:GetAttribute("point"), "LEFT", "members left to right")
    T.eq(h:GetAttribute("columnAnchorPoint"), "TOP", "groups stacked down")
    local cfg = DUI:Get("UnitFrames", "raid")
    T.near(ns.Raid.holder:GetWidth(), 5 * cfg.width + 4 * cfg.spacing, 5, "five across (pixel-snapped)")
end)

T.test("raid tiles: grow up from the bottom and from the right", function()
    local DUI, ns = login()
    local h = ns.Raid.header
    DUI:Set("UnitFrames", "raid.growUp", true)
    DUI:Set("UnitFrames", "raid.growLeft", true)
    stub.RunTimers()
    local cfg = DUI:Get("UnitFrames", "raid")
    T.eq(h:GetAttribute("point"), "BOTTOM", "members bottom to top")
    T.eq(h:GetAttribute("yOffset"), cfg.spacing, "a positive gap steps up")
    T.eq(h:GetAttribute("columnAnchorPoint"), "RIGHT", "groups right to left")
    T.eq((h:GetPoint(1)), "BOTTOMRIGHT", "the header sits in the holder's bottom right")
    DUI:Set("UnitFrames", "raid.direction", "rows")
    stub.RunTimers()
    T.eq(h:GetAttribute("point"), "RIGHT", "members right to left")
    T.eq(h:GetAttribute("xOffset"), -cfg.spacing, "a negative gap steps left")
    T.eq(h:GetAttribute("columnAnchorPoint"), "BOTTOM", "groups stacked up")
    -- Group, then role: each group's header from the same corner.
    DUI:Set("UnitFrames", "raid.sortBy", "grouprole")
    stub.RunTimers()
    local gh = ns.Raid.group.headers[2]
    local pt, _, _, x, y = gh:GetPoint(1)
    T.eq(pt, "BOTTOMRIGHT"); T.eq(x, 0); T.truthy(y > 0, "group 2 sits above group 1")
end)

T.test("raid tiles: the holder is the size of the groups shown", function()
    local DUI, ns = login()
    stub.RunTimers()
    local all = ns.Raid.holder:GetWidth()
    DUI:Set("UnitFrames", "raid.groups", 2)
    stub.RunTimers()
    local cfg = DUI:Get("UnitFrames", "raid")
    T.near(ns.Raid.holder:GetWidth(), 2 * cfg.width + cfg.groupSpacing, 5, "two groups across")
    T.truthy(ns.Raid.holder:GetWidth() < all)
end)

T.test("raid tiles keep their own mover", function()
    local DUI, ns = login()
    stub.RunTimers()
    T.falsy(DUI.Movers.Get("unitframes.raid").suspended, "placed by its own mover")
end)

T.test("/dui test raid: a raid of forty, and the party's samples step aside", function()
    local DUI, ns = login()
    DUI.RunCommand("test raid")
    stub.RunTimers()
    local shown = 0
    for _, b in ipairs(ns.Raid.preview) do if b:IsShown() then shown = shown + 1 end end
    T.eq(shown, 40)
    T.falsy(ns.Party.preview[1]:IsShown(), "no party samples")
    DUI.RunCommand("test")
    stub.RunTimers()
    T.truthy(ns.Party.preview[1]:IsShown(), "plain /dui test: the party's samples")
    DUI.RunCommand("test")
end)

T.test("raid tiles show a role icon from the role a member picked", function()
    local DUI, ns = login()
    local b = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton5", ns.Raid.header)
    b:SetAttribute("unit", "raid11")
    stub.units.raid11 = { name = "Renarin", isPlayer = true, class = "DRUID", role = "HEALER" }
    ns.Raid.header.initialConfigFunction(ns.Raid.header, b:GetName())
    T.truthy(b.roleIcon:IsShown())
    stub.units.raid11.role = "NONE"
    ns.UF.UpdateRole(b)
    T.falsy(b.roleIcon:IsShown(), "no role: nothing shows")
    stub.units.raid11.role = "TANK"
    ns.UF.UpdateRole(b)
    T.truthy(b.roleIcon:IsShown())
    DUI:Set("UnitFrames", "raid.showRole", false)
    T.falsy(b.roleIcon:IsShown(), "the option turns it off")
end)

T.test("raid tile icons: spot, size, and hide options", function()
    local DUI, ns = login()
    local b = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton6", ns.Raid.header)
    b:SetAttribute("unit", "raid12")
    stub.units.raid12 = { name = "Kaladin", isPlayer = true, class = "WARRIOR", role = "DAMAGER" }
    ns.Raid.header.initialConfigFunction(ns.Raid.header, b:GetName())
    T.eq(b.roleIcon:GetWidth(), 11, "today's size by default")
    DUI:Set("UnitFrames", "raid.roleSize", 20)
    DUI:Set("UnitFrames", "raid.rolePos", "topright")
    T.eq(b.roleIcon:GetWidth(), 20, "size slider")
    T.eq((b.roleIcon:GetPoint(1)), "TOPRIGHT", "spot dropdown")
    T.truthy(b.roleIcon:IsShown())
    DUI:Set("UnitFrames", "raid.roleHideDamage", true)
    ns.UF.UpdateRole(b)
    T.falsy(b.roleIcon:IsShown(), "damage role hidden")
    DUI:Set("UnitFrames", "raid.roleHideDamage", false)
    DUI:Set("UnitFrames", "raid.roleHideInCombat", true)
    ns.UF.fighting = true
    ns.UF.UpdateRole(b)
    T.falsy(b.roleIcon:IsShown(), "hidden in combat")
    ns.UF.fighting = false
    ns.UF.UpdateRole(b)
    T.truthy(b.roleIcon:IsShown())
end)

T.test("raid tiles: the health can fill upward instead of across", function()
    local DUI, ns = login()
    local b = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton4", ns.Raid.header)
    b:SetAttribute("unit", "raid6")
    stub.units.raid6 = { name = "Wit", isPlayer = true, class = "PRIEST", health = 50, maxHealth = 100 }
    ns.Raid.header.initialConfigFunction(ns.Raid.header, b:GetName())
    T.eq(b.health:GetOrientation(), "HORIZONTAL", "across, by default")
    DUI:Set("UnitFrames", "raid.fillVertical", true)
    stub.RunTimers()
    T.eq(b.health:GetOrientation(), "VERTICAL")
    T.eq(b.heals:GetOrientation(), "VERTICAL", "heals and shields stack upward too")
    local point, rel, relPoint = b.heals:GetPoint(1)
    T.eq(point, "BOTTOMLEFT"); T.eq(rel, b.health:GetStatusBarTexture()); T.eq(relPoint, "TOPLEFT")
end)

T.test("raid tiles: tiles per line other than five run everyone on in order", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "raid.perLine", 4)
    stub.RunTimers()
    local h = ns.Raid.header
    T.isnil(h:GetAttribute("groupBy"), "not by group")
    T.eq(h:GetAttribute("unitsPerColumn"), 4)
    T.eq(h:GetAttribute("maxColumns"), 10)
    DUI:Set("UnitFrames", "raid.perLine", 5)
    stub.RunTimers()
    T.eq(h:GetAttribute("groupBy"), "GROUP", "five: by group again")
end)

T.test("raid tiles: sort by role, class or name, and show only the first groups", function()
    local DUI, ns = login()
    local h = ns.Raid.header
    T.eq(h:GetAttribute("groupBy"), "GROUP", "by group, by default")
    T.isnil(h:GetAttribute("groupFilter"), "all groups, by default")
    DUI:Set("UnitFrames", "raid.sortBy", "role")
    stub.RunTimers()
    T.eq(h:GetAttribute("groupBy"), "ASSIGNEDROLE")
    T.eq(h:GetAttribute("groupingOrder"), "TANK,HEALER,DAMAGER,NONE")
    DUI:Set("UnitFrames", "raid.sortBy", "class")
    stub.RunTimers()
    T.eq(h:GetAttribute("groupBy"), "CLASS")
    DUI:Set("UnitFrames", "raid.sortBy", "name")
    stub.RunTimers()
    T.isnil(h:GetAttribute("groupBy"))
    T.eq(h:GetAttribute("sortMethod"), "NAME")
    DUI:Set("UnitFrames", "raid.sortBy", "group")
    DUI:Set("UnitFrames", "raid.groups", 4)
    stub.RunTimers()
    T.eq(h:GetAttribute("groupBy"), "GROUP")
    T.eq(h:GetAttribute("groupFilter"), "1,2,3,4")
end)

T.test("with Clique loaded, the raid header hands each new button to Clique's header", function()
    local refs, gameSetRef = {}, nil
    local cliqueHeader = CreateFrame("Frame", "CliqueHeaderFrame", UIParent)
    local _, ns = stub.Load({ module = true, before = function()
        ClickCastHeader = cliqueHeader
        gameSetRef = SecureHandlerSetFrameRef
        -- A group header has no SetFrameRef of its own: the game's helper sets it.
        -- Only Clique's refs are counted; the spellbook's fight cover sets its own through the game's.
        SecureHandlerSetFrameRef = function(frame, label, ref)
            if label == "clickcast_header" then refs[#refs + 1] = { frame, label, ref }
            else gameSetRef(frame, label, ref) end
        end
    end })
    -- The game's own helper back: the spellbook's fight cover (Book/Fight.lua) uses it too.
    ClickCastHeader, SecureHandlerSetFrameRef = nil, gameSetRef
    T.eq(#refs, 10, "each header (the raid's, its eight group headers, the party's) was pointed at Clique once")
    T.eq(refs[1][1], ns.Raid.header); T.eq(refs[1][2], "clickcast_header"); T.eq(refs[1][3], cliqueHeader)
    for i = 1, 8 do T.eq(refs[1 + i][1], ns.Raid.group.headers[i]); T.eq(refs[1 + i][3], cliqueHeader) end
    T.eq(refs[10][1], ns.Party.header); T.eq(refs[10][3], cliqueHeader)
    local init = ns.Raid.header:GetAttribute("initialConfigFunction")
    T.truthy(init:find('SetAttribute("clickcast_button", self)', 1, true), "the button is passed to Clique before it registers")
end)

T.test("raid tiles carry buffs when asked (only mine when picked)", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "raid.auras.buffs.which", "mine")
    local b = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton3", ns.Raid.header)
    b:SetAttribute("unit", "raid3")
    stub.units.raid3 = { name = "Lirin", isPlayer = true, class = "PRIEST", health = 10, maxHealth = 10 }
    ns.Raid.header.initialConfigFunction(ns.Raid.header, b:GetName())
    local c = b.auraSet.buffs
    T.eq(#c.__groupOrder, 0, "off by default: no groups")
    DUI:Set("UnitFrames", "raid.auras.buffs.show", true)
    stub.RunTimers()
    T.eq(c.__unit, "raid3")
    T.eq(c.__groups.mine.filter, "HELPFUL|PLAYER")
    T.isnil(c.__groups.all, "only mine")
    T.eq(c.__groups.mine.max, 4)
    DUI:Set("UnitFrames", "raid.auras.buffs.which", "all")
    T.eq(c.__groups.mine.max, 0); T.eq(c.__groups.all.max, 4)
    DUI:Set("UnitFrames", "raid.auras.buffs.show", false)
    T.eq(c.__groups.all.max, 0, "toggling updates live")
end)

T.test("a buff setting change makes the tile's and party's buffs re-read", function()
    local DUI, ns = login()
    local b = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton4", ns.Raid.header)
    b:SetAttribute("unit", "raid4")
    ns.Raid.header.initialConfigFunction(ns.Raid.header, b:GetName())
    DUI:Set("UnitFrames", "raid.auras.buffs.show", true)
    stub.RunTimers()
    local tileBefore = b.auraSet.buffs.__refreshes or 0
    local pb = CreateFrame("Button", "DaylightUIPartyHeaderUnitButton1", ns.Party.header)
    pb:SetAttribute("unit", "party1")
    ns.Party.header.initialConfigFunction(ns.Party.header, pb:GetName())
    local row = pb.auraSet.buffs
    local rowBefore = row.__refreshes or 0
    DUI:Set("UnitFrames", "raid.auras.buffs.which", "all")
    DUI:Set("UnitFrames", "party.auras.buffs.which", "all")
    stub.RunTimers()
    T.truthy((b.auraSet.buffs.__refreshes or 0) > tileBefore, "the client only redraws on a re-read")
    T.truthy((row.__refreshes or 0) > rowBefore)
end)

T.test("raid tiles: the health text follows its X/Y offset", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "raid.height", 44)
    DUI:Set("UnitFrames", "raid.showPercent", true)
    stub.RunTimers()
    DUI.SetTestMode(true)
    stub.RunTimers()
    local b = ns.Raid.preview[1]
    local _, _, _, x0, y0 = b.percentText:GetPoint(1)
    DUI:Set("UnitFrames", "raid.healthTextX", 5)
    DUI:Set("UnitFrames", "raid.healthTextY", 4)
    stub.RunTimers()
    local _, _, _, x, y = b.percentText:GetPoint(1)
    T.eq(x, x0 + 5); T.eq(y, y0 + 4)
    DUI.SetTestMode(false)
end)

T.test("the Raid page carries the tile options; no 'raid frames in a party'", function()
    local DUI = login()
    local O = DUI.Options
    local page = O.GetPage("UnitFrames.raid")
    T.eq(#O.ValidatePage(page), 0)
    local items = {}
    for _, g in ipairs(page.groups) do for _, it in ipairs(g.items) do if it.key then items[it.key] = it end end end
    for _, key in ipairs({ "raid.slant", "raid.perLine", "raid.fillVertical", "raid.hideSelf", "raid.nameAlign",
                           "raid.nameX", "raid.nameY", "raid.auras.buffs.show", "raid.auras.buffs.spot", "raid.auras.buffs.size",
                           "raid.auras.debuffs.show", "raid.auras.debuffs.which", "raid.auras.cc.show" }) do
        T.truthy(items[key], key)
    end
    T.isnil(items["raid.inParty"])
    T.isnil(DUI:Get("UnitFrames", "raid.inParty"))
end)

T.test("/dui test raid: the raid tiles' settings show in the preview at once, sample dispel and tint too", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "raid.width", 40)
    stub.RunTimers()
    DUI.RunCommand("test raid")
    stub.RunTimers()
    T.near(ns.Raid.preview[1]:GetWidth(), 40, 1, "the raid tiles' width")
    DUI:Set("UnitFrames", "raid.width", 70)
    stub.RunTimers()
    T.near(ns.Raid.preview[1]:GetWidth(), 70, 1, "a change shows in the preview")
    T.truthy(ns.Raid.preview[3].sampleDispel:IsShown(), "a sample dispel")
    DUI:Set("UnitFrames", "raid.dispelHighlight", "tint")
    DUI:Set("UnitFrames", "raid.dispelAlpha", 0.3)
    stub.RunTimers()
    local tint = ns.Raid.preview[3].sampleHL.tint
    T.truthy(tint:IsShown() and ns.Raid.preview[3].sampleHLFrame:IsShown(), "a sample tint")
    T.near(tint.__color[4], 0.3, 0.001, "see-through, at the slider's strength")
    DUI:Set("UnitFrames", "raid.showDispel", false)
    stub.RunTimers()
    T.falsy(ns.Raid.preview[3].sampleDispel:IsShown(), "gone as soon as it's turned off")
    DUI.RunCommand("test raid")
    stub.RunTimers()
end)
T.test("group, then role: a header per raid group, sorted tank, healer, damage", function()
    local DUI, ns = login()
    local g = ns.Raid.group
    T.eq(#g.headers, 8, "one header per raid group")
    for i, gh in ipairs(g.headers) do
        T.eq(gh:GetName(), "DaylightUIRaidGroup" .. i .. "Header")
        T.eq(gh:GetAttribute("groupFilter"), tostring(i))
        T.eq(gh:GetAttribute("groupBy"), "ASSIGNEDROLE")
        T.eq(gh:GetAttribute("groupingOrder"), "TANK,HEALER,DAMAGER,NONE")
        T.eq(gh:GetAttribute("unitsPerColumn"), 5); T.eq(gh:GetAttribute("maxColumns"), 1)
        T.isnil(gh.__stateDriver and gh.__stateDriver.visibility, "off unless the mode is on")
    end
    DUI:Set("UnitFrames", "raid.sortBy", "grouprole")
    stub.RunTimers()
    T.isnil(ns.Raid.header.__stateDriver.visibility, "the one big header steps aside")
    for _, gh in ipairs(g.headers) do T.eq(gh.__stateDriver.visibility, "[@raid1,exists] show; hide") end
    DUI:Set("UnitFrames", "raid.sortBy", "group")
    stub.RunTimers()
    T.eq(ns.Raid.header.__stateDriver.visibility, "[@raid1,exists] show; hide", "and comes back")
    for _, gh in ipairs(g.headers) do T.isnil(gh.__stateDriver.visibility) end
end)

T.test("group, then role: groups side by side, or stacked in rows", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "raid.sortBy", "grouprole")
    DUI:Set("UnitFrames", "raid.perLine", 3)   -- ignored: a group is a line
    stub.RunTimers()
    local cfg, holder = DUI:Get("UnitFrames", "raid"), ns.Raid.holder
    local g = ns.Raid.group
    local _, rel, _, x1, y1 = g.headers[1]:GetPoint()
    T.eq(rel, holder); T.eq(x1, 0); T.eq(y1, 0)
    local _, _, _, x3, y3 = g.headers[3]:GetPoint()
    T.near(x3, 2 * (holder.tileW + cfg.groupSpacing), 0.01, "third column"); T.eq(y3, 0)
    T.eq(g.headers[3]:GetAttribute("point"), "TOP")
    T.eq(g.headers[3]:GetAttribute("unitWidth"), holder.tileW)
    T.near(holder:GetHeight(), 5 * holder.tileH + 4 * cfg.spacing, 0.01, "five down, whatever perLine says")
    DUI:Set("UnitFrames", "raid.direction", "rows")
    stub.RunTimers()
    local _, _, _, rx, ry = g.headers[3]:GetPoint()
    T.eq(rx, 0); T.near(ry, -2 * (holder.tileH + cfg.groupSpacing), 0.01, "third row")
    T.eq(g.headers[3]:GetAttribute("point"), "LEFT")
end)

T.test("group, then role: only the groups shown, and you can hide yourself", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "raid.sortBy", "grouprole")
    DUI:Set("UnitFrames", "raid.groups", 4)
    DUI:Set("UnitFrames", "raid.hideSelf", true)
    stub.RunTimers()
    local g = ns.Raid.group
    for i, gh in ipairs(g.headers) do
        if i <= 4 then T.eq(gh.__stateDriver.visibility, "[@raid1,exists] show; hide")
        else T.isnil(gh.__stateDriver.visibility, "group " .. i .. " hidden") end
        T.eq(gh:GetAttribute("showPlayer"), false)
    end
end)

T.test("group, then role: a button a group header makes is dressed at that header's size", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "raid.sortBy", "grouprole")
    stub.RunTimers()
    local gh = ns.Raid.group.headers[2]
    local b = CreateFrame("Button", "DaylightUIRaidGroup2HeaderUnitButton1", gh)
    b:SetAttribute("unit", "raid6")
    stub.units.raid6 = { name = "Lopen", isPlayer = true, class = "ROGUE", role = "DAMAGER" }
    gh.initialConfigFunction(gh, b:GetName())
    T.eq(b.group, ns.Raid.group)
    local found = false
    for _, x in ipairs(ns.Raid.buttons) do if x == b then found = true end end
    T.truthy(found, "joins the raid's buttons")
    T.eq(b:GetWidth(), gh:GetAttribute("unitWidth"))
end)

T.test("group, then role: test mode hides every real header", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "raid.sortBy", "grouprole")
    DUI.RunCommand("test raid")
    stub.RunTimers()
    local want = ns.Raid.header:GetAlpha()
    for _, gh in ipairs(ns.Raid.group.headers) do T.eq(gh:GetAlpha(), want) end
    DUI.RunCommand("test")
end)

T.test("the raid's sort list offers Group, then role; the party's doesn't", function()
    local _, ns = login()
    local function find(pageId, key)
        for _, p in ipairs(ns.OPTIONS.pages) do
            if p.id == pageId then
                for _, grp in ipairs(p.groups) do
                    for _, it in ipairs(grp.items) do if it.key == key then return it end end
                end
            end
        end
    end
    local r = find("raid", "raid.sortBy")
    T.eq(r.values.grouprole, "Group, then role")
    T.eq(r.order[2], "grouprole", "right after Group")
    local p = find("party", "party.sortBy")
    T.isnil(p.values.grouprole)
end)

T.test("test mode, Group, then role: each sample group runs tank, healer, damage", function()
    local DUI, ns = login()
    local cfg = { sortBy = "grouprole" }
    local rank = ns.Raid.ROLE_RANK
    for first = 1, 40, 5 do
        local last = 0
        for i = first, first + 4 do
            local r = rank[ns.Raid.PreviewSample(i, cfg).role]
            T.truthy(r >= last, "slot " .. i .. " in role order"); last = r
        end
    end
    -- The plain sort keeps the samples as they come.
    T.eq(ns.Raid.PreviewSample(3, { sortBy = "group" }).name, ns.Raid.SampleFor(3).name)
end)

local function tile(ns, unit)
    local b = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton1", ns.Raid.header)
    b:SetAttribute("unit", unit or "raid3")
    ns.Raid.header.initialConfigFunction(ns.Raid.header, b:GetName())
    stub.RunTimers()
    return b
end

T.test("a raid tile carries the aura groups, pointed at its unit, laid out from the settings", function()
    local DUI, ns = login()
    local b = tile(ns)
    T.truthy(b.auraSet and b.auraSet.debuffs and b.auraSet.cc and b.auraSet.buffs)
    T.isnil(b.buffs, "the old tile buffs container is gone from raid tiles")
    T.eq(b.auraSet.debuffs.__unit, "raid3")
    T.eq(b.auraSet.debuffs.__groups.notcc.max, 2, "debuffs on by default, crowd control in its own group")
    T.eq(b.auraSet.cc.__groups.cc.max, 1)
    T.isnil(b.auraSet.buffs.__groups.mine, "buffs still off by default")
    DUI:Set("UnitFrames", "raid.auras.debuffs.spot", "topleft")
    DUI:Set("UnitFrames", "raid.auras.debuffs.grow", "right")
    stub.RunTimers()
    T.eq((b.auraSet.debuffs:GetPoint(1)), "TOPLEFT")
end)

T.test("a change in combat waits for the fight to end, and nothing protected fails", function()
    local DUI, ns = login()
    local b = tile(ns)
    stub.EnterCombat()
    DUI:Set("UnitFrames", "raid.auras.debuffs.max", 5)
    stub.RunTimers()
    T.eq(b.auraSet.debuffs.__groups.notcc.max, 2, "not yet")
    stub.LeaveCombat()
    stub.RunTimers()
    T.eq(b.auraSet.debuffs.__groups.notcc.max, 5)
    T.eq(#stub.errors, 0)
end)

T.test("upgrade 7: a profile's raid buff settings move into the buffs group, same place", function()
    local _, ns = login()
    local uf = { raid = { showBuffs = true, buffFilter = "all", buffsAt = "right", buffSize = 18,
                          maxBuffs = 6, buffSpacing = 3, buffRows = 2 } }
    ns.UPGRADE_STEPS[7](uf)
    local b = uf.raid.auras.buffs
    T.eq(b.show, true); T.eq(b.which, "all"); T.eq(b.spot, "outright"); T.eq(b.grow, "right")
    T.eq(b.size, 18); T.eq(b.max, 6); T.eq(b.spacing, 3); T.eq(b.rows, 2)
    T.isnil(uf.raid.showBuffs); T.isnil(uf.raid.buffsAt); T.isnil(uf.raid.buffRows)
    -- Every old spot has a new one.
    local AT = { below = "bottomleft", above = "topleft", left = "outleft", right = "outright", top = "above", bottom = "below" }
    for old, new in pairs(AT) do
        local u = { raid = { buffsAt = old } }
        ns.UPGRADE_STEPS[7](u)
        T.eq(u.raid.auras.buffs.spot, new, old)
    end
    -- Nothing saved: nothing written.
    local empty = { raid = {} }
    ns.UPGRADE_STEPS[7](empty)
    T.isnil(empty.raid.auras)
end)

T.test("raid buffs at the bottom sit where the old tile buffs did, now past the role icon", function()
    local DUI, ns = login()
    local b = tile(ns)
    DUI:Set("UnitFrames", "raid.auras.buffs.show", true)
    stub.RunTimers()
    local cfg = DUI:Get("UnitFrames", "raid")
    local T_ = DUI.Pixel.Px(b, DUI.Style.BorderPx(b))
    local p, rel, rp, x, y = b.auraSet.buffs:GetPoint(1)
    T.eq(p, "BOTTOMLEFT"); T.eq(rel, b); T.eq(rp, "BOTTOMLEFT")
    T.eq(x, T_ + cfg.roleSize + 1); T.eq(y, T_ + 1 + cfg.powerHeight + 1)
end)

T.test("the Healer ready-made profile only sets real raid settings, and shows raid buffs", function()
    local DUI, ns = login()
    local function check(set, defaults, path)
        for k, v in pairs(set) do
            T.truthy(defaults[k] ~= nil, path .. k .. " is a setting")
            if type(v) == "table" and type(defaults[k]) == "table" and #v == 0 then check(v, defaults[k], path .. k .. ".") end
        end
    end
    local raid = DUI.Profiles.PRESETS.Healer.UnitFrames.raid
    check(raid, ns.DEFAULTS.raid, "raid.")
    T.eq(raid.auras.buffs.show, true)
end)

T.test("/dui sweep raid: a step that changes one aura group keeps the others' defaults", function()
    local DUI, ns = login()
    local idx
    for i, s in ipairs(ns.Sweep.STEPS.raid) do if s.set.auras then idx = i end end
    T.truthy(idx, "a raid step sets aura groups")
    ns.Sweep.Start("raid")
    ns.Sweep.Step(idx - 1)
    stub.RunTimers()
    local cfg = ns.Raid.group.sweep.cfg
    T.eq(cfg.auras.buffs.show, true); T.eq(cfg.auras.buffs.spot, "outright")
    T.eq(cfg.auras.buffs.size, ns.DEFAULTS.raid.auras.buffs.size, "the rest of the group's settings kept")
    T.eq(cfg.auras.debuffs.show, true, "the other groups kept")
    T.isnil(rawget(ns.DEFAULTS.raid.auras.buffs, "spot") == "outright" and true or nil, "the defaults untouched")
    ns.Sweep.Stop()
end)

T.test("the name: across the bar by default, or at a spot, or beside the tile", function()
    local DUI, ns = login()
    local b = tile(ns)
    local fs = b.nameText
    local today = select(1, fs:GetPoint(1))   -- "LEFT" (stretched across the bar; "TOPLEFT" on a tall tile)
    T.eq(fs:GetNumPoints(), 2, "today: stretched across the bar")
    DUI:Set("UnitFrames", "raid.namePos", "topleft")
    stub.RunTimers()
    T.eq(select(1, fs:GetPoint(1)), "TOPLEFT")
    T.eq(fs:GetJustifyH(), "LEFT")
    DUI:Set("UnitFrames", "raid.namePos", "outright")
    stub.RunTimers()
    local p, rel, rp = fs:GetPoint(1)
    T.eq(p, "LEFT"); T.eq(rel, b); T.eq(rp, "RIGHT")
    DUI:Set("UnitFrames", "raid.namePos", "bar")
    stub.RunTimers()
    T.eq(select(1, fs:GetPoint(1)), today, "back to today's")
    T.eq(fs:GetNumPoints(), 2)
end)

T.test("tiles per line can go up to 40; the default layout is unchanged", function()
    local DUI, ns = login()
    T.eq(DUI:Get("UnitFrames", "raid.perLine"), 5, "default stays 5")
    T.eq(ns.Group.PerLine(DUI:Get("UnitFrames", "raid")), 5)
    DUI:Set("UnitFrames", "raid.perLine", 40)
    stub.RunTimers()
    T.eq(ns.Group.PerLine(DUI:Get("UnitFrames", "raid")), 40)
    T.eq(#stub.errors, 0)
end)

-- Test mode's sample tiles (the group's preview buttons) that show now.
local function sampleTiles(ns)
    local out = {}
    for _, b in ipairs(ns.Raid.preview or {}) do if b:IsShown() then out[#out + 1] = b end end
    return out
end

T.test("/dui test raid: sample tiles show sample auras where the settings put them", function()
    local DUI, ns = login()
    DUI.SetTestMode(true)
    stub.RunTimers()
    local b = sampleTiles(ns)[1]
    T.truthy(b and b.sampleSet, "a sample tile with its stand-in aura groups")
    local cfg = DUI:Get("UnitFrames", "raid")
    local T_ = DUI.Pixel.Px(b, DUI.Style.BorderPx(b))
    local p, rel, rp, x, y = b.sampleSet.debuffs:GetPoint(1)
    T.eq(p, "BOTTOMRIGHT"); T.eq(rel, b); T.eq(rp, "BOTTOMRIGHT")
    T.eq(x, -(T_ + cfg.markerSize + 1)); T.eq(y, T_ + 1 + cfg.powerHeight + 1, "where a real tile's debuffs sit")
    T.truthy(b.sampleSet.debuffs:IsShown(), "sample debuffs show")
    T.eq((b.sampleSet.cc:GetPoint(1)), "CENTER")
    T.eq(#stub.errors, 0)
    DUI.SetTestMode(false)
end)

T.test("test mode: raid tiles show sample buffs when asked", function()
    local DUI, ns = login()
    local function count()
        local n = 0
        for _, b in ipairs(sampleTiles(ns)) do
            for _, icon in ipairs(b.sampleSet.buffs.pool or {}) do
                if icon:IsVisible() then n = n + 1 end
            end
        end
        return n
    end
    DUI.SetTestMode(true)
    stub.RunTimers()
    T.eq(count(), 0, "off by default")
    DUI:Set("UnitFrames", "raid.auras.buffs.show", true)
    stub.RunTimers()
    T.truthy(count() > 0, "on: sample buffs")
    DUI:Set("UnitFrames", "raid.auras.buffs.show", false)
    stub.RunTimers()
    T.eq(count(), 0, "off: none")
    DUI.SetTestMode(false)
end)

T.test("a calm default tile: two small debuffs in the corner, a smaller crowd-control icon, no timer numbers", function()
    local DUI, ns = login()
    local a = DUI:Get("UnitFrames", "raid.auras")
    T.eq(a.debuffs.spot, "bottomright"); T.eq(a.debuffs.grow, "left")
    T.eq(a.debuffs.size, 12); T.eq(a.debuffs.max, 2)
    T.eq(a.cc.size, 16); T.eq(a.cc.spot, "center")
    for _, g in ipairs({ "debuffs", "cc", "buffs" }) do T.eq(a[g].timers, false, g) end
    T.eq(a.buffs.spot, "bottomleft", "buffs keep the old tile buffs' spot (upgrade step 7 relies on it)")
end)

T.test("timer numbers on a tile's icons follow the group's switch, once restrictions lift", function()
    local DUI, ns = login()
    local b = tile(ns)
    local btn = b.auraSet.debuffs.__groups.notcc.button
    T.truthy(btn.__time, "the icon has its time text")
    local off, on = DUI.Style.DurationFormatter(0), ns.Auras.TimeFormatter(false)
    T.eq(btn.__timeOpts.textFormatter, off, "off by default: writes nothing")
    DUI:Set("UnitFrames", "raid.auras.debuffs.timers", true)
    stub.RunTimers()
    T.eq(btn.__timeOpts.textFormatter, on)
    stub.SetRestriction("PvPMatch", true)
    DUI:Set("UnitFrames", "raid.auras.debuffs.timers", false)
    stub.RunTimers()
    T.eq(btn.__timeOpts.textFormatter, on, "locked in a battleground: waits")
    T.eq(#stub.errors, 0)
    stub.SetRestriction("PvPMatch", false)
    stub.RunTimers()
    T.eq(btn.__timeOpts.textFormatter, off, "done once it lifts")
end)

T.test("sample tiles look like a real raid: most show nothing, a few show debuffs, one crowd control", function()
    local DUI, ns = login()
    DUI.SetTestMode(true)
    stub.RunTimers()
    local tiles, withDebuffs, withCC = sampleTiles(ns), 0, 0
    for _, b in ipairs(tiles) do
        if b.sampleSet.debuffs:IsShown() then withDebuffs = withDebuffs + 1 end
        if b.sampleSet.cc:IsShown() then withCC = withCC + 1 end
    end
    T.truthy(#tiles >= 20, "a full raid of samples")
    T.truthy(withDebuffs > 0 and withDebuffs <= #tiles / 2, "debuffs on some: " .. withDebuffs)
    T.truthy(withCC > 0 and withCC <= #tiles / 5, "crowd control on a few: " .. withCC)
    local icon = tiles[1].sampleSet.debuffs.pool[1]
    T.falsy(icon.time:IsShown(), "no timer numbers on samples either, by default")
    DUI.SetTestMode(false)
end)

T.test("aura rows start past the corner icons (role, marker), never on them", function()
    local DUI, ns = login()
    local b = tile(ns)
    local cfg = DUI:Get("UnitFrames", "raid")
    local T_ = DUI.Pixel.Px(b, DUI.Style.BorderPx(b))
    local _, _, _, x = b.auraSet.debuffs:GetPoint(1)
    T.eq(x, -(T_ + cfg.markerSize + 1), "debuffs clear the marker's corner")
    DUI:Set("UnitFrames", "raid.showMarker", false)
    stub.RunTimers()
    _, _, _, x = b.auraSet.debuffs:GetPoint(1)
    T.eq(x, -T_, "no marker: right into the corner")
end)

-- Setups by raid size (Raid.lua): 10, 20 and 40 players, each its own.
local function widthNow(ns) return ns.Raid.header:GetAttribute("unitWidth") end
-- A width as the header gets it: snapped to whole pixels.
local function want(ns, w) return 2 * DaylightUI.Pixel.Snap(ns.Raid.holder, w / 2) end

T.test("raid sizes: untouched, every raid size runs the 10-player setup", function()
    local DUI, ns = login()
    T.eq(DUI:Get("UnitFrames", "raid40.follow"), true)
    DUI:Set("UnitFrames", "raid.width", 64)
    stub.SetGroup(true, true, 30)
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    stub.RunTimers()
    T.eq(widthNow(ns), want(ns, 64), "40 follows 10")
end)

T.test("raid sizes: a size that follows 10 runs 10's; its own setup starts as a copy and swaps with the roster", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "raid.width", 64)
    stub.SetGroup(true, true, 30)
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    stub.RunTimers()
    T.eq(widthNow(ns), want(ns, 64), "40 follows 10 by default")
    -- Follow off: a copy of 10's, so nothing jumps.
    ns.Raid.SetFollow(40, false)
    stub.RunTimers()
    T.eq(DUI:Get("UnitFrames", "raid40.width"), 64)
    T.eq(DUI:Get("UnitFrames", "raid40.own"), true)
    T.eq(widthNow(ns), want(ns, 64))
    DUI:Set("UnitFrames", "raid40.width", 50)
    stub.RunTimers()
    T.eq(widthNow(ns), want(ns, 50), "40 players: its own width")
    T.eq(DUI:Get("UnitFrames", "raid.width"), 64, "10's untouched")
    -- Down to 8 players: back to 10's.
    stub.SetGroup(true, true, 8)
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    stub.RunTimers()
    T.eq(widthNow(ns), want(ns, 64))
    -- Follow on again, then off: its own setup comes back, not a new copy.
    ns.Raid.SetFollow(40, true)
    ns.Raid.SetFollow(40, false)
    T.eq(DUI:Get("UnitFrames", "raid40.width"), 50)
end)

T.test("raid sizes: a raid that grows mid-fight swaps once the fight ends", function()
    local DUI, ns = login()
    ns.Raid.SetFollow(20, false)
    DUI:Set("UnitFrames", "raid20.width", 90)
    stub.SetGroup(true, true, 10)
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    stub.RunTimers()
    T.eq(widthNow(ns), want(ns, 72))
    stub.EnterCombat()
    stub.SetGroup(true, true, 14)
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    stub.RunTimers()
    T.eq(widthNow(ns), want(ns, 72), "the header is locked in combat")
    stub.LeaveCombat()
    stub.RunTimers()
    T.eq(widthNow(ns), want(ns, 90))
end)

T.test("raid sizes: Raid 40 can sit in a spot of its own, with its own handle; back to 10 the frames go home", function()
    local DUI, ns = login()
    local M = DUI.Movers
    local spot = ns.Raid.spots[40]
    T.truthy(M.Get("unitframes.raid40"), "a mover of its own")
    T.falsy(M.Get("unitframes.raid40").active(), "no handle while it's off")
    stub.SetGroup(true, true, 30)
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    stub.RunTimers()
    T.falsy(M.Get("unitframes.raid").suspended, "off by default: Raid 10's spot")
    DUI:Set("UnitFrames", "raid40.ownSpot", true)
    stub.RunTimers()
    T.truthy(M.Get("unitframes.raid40").active(), "its handle while it's on")
    local _, rel = ns.Raid.holder:GetPoint(1)
    T.eq(rel, spot, "a raid of 30 sits on Raid 40's spot")
    T.truthy(M.Get("unitframes.raid").suspended, "Raid 10's mover stands aside")
    T.near(spot:GetWidth(), ns.Raid.holder:GetWidth() * ns.Raid.holder:GetEffectiveScale() / spot:GetEffectiveScale(), 0.01,
        "the handle the raid's size")
    -- Following 10's look doesn't matter, nor does a copy of 10 take the spot away.
    ns.Raid.SetFollow(40, false)
    stub.RunTimers()
    T.eq(DUI:Get("UnitFrames", "raid40.ownSpot"), true, "Copy Raid 10 keeps where it sits")
    stub.SetGroup(true, true, 8)
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    stub.RunTimers()
    T.falsy(M.Get("unitframes.raid").suspended, "8 players: Raid 10's spot again")
    local _, rel2 = ns.Raid.holder:GetPoint(1)
    T.truthy(rel2 ~= spot, "off the Raid 40 spot")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("Copy from: a frame takes another's setup, its switch, fade and layout stay", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "party.width", 150)
    DUI:Set("UnitFrames", "party.nameColor", "custom")
    DUI:Set("UnitFrames", "party.auras.debuffs.size", 22)
    DUI:Set("UnitFrames", "partyText.name", 14)
    DUI:Set("UnitFrames", "party.sortBy", "name")
    T.truthy(ns.CopyFrame("party", "raid"))
    T.eq(DUI:Get("UnitFrames", "raid.width"), 150)
    T.eq(DUI:Get("UnitFrames", "raid.nameColor"), "custom")
    T.eq(DUI:Get("UnitFrames", "raid.auras.debuffs.size"), 22)
    T.eq(DUI:Get("UnitFrames", "raidText.name"), 14)
    T.eq(DUI:Get("UnitFrames", "raid.sortBy"), "group", "the raid keeps its own sorting")
    -- Raid 40 with its own frames: only its own, Raid 10 untouched.
    ns.Raid.SetFollow(40, false)
    DUI:Set("UnitFrames", "party.width", 120)
    ns.CopyFrame("party", "raid40")
    T.eq(DUI:Get("UnitFrames", "raid40.width"), 120)
    T.eq(DUI:Get("UnitFrames", "raid.width"), 150)
    -- Single frames too, through the page's card.
    DUI:Set("UnitFrames", "target.width", 260)
    local page = DUI.Options.GetPage("UnitFrames.focus")
    local pickRow, copyRow
    for _, g in ipairs(page.groups) do
        for _, it in ipairs(g.items) do
            if it.label == "Copy from" then pickRow = it elseif it.label == "Copy its setup" then copyRow = it end
        end
    end
    local _, order = pickRow.choices()
    for _, k in ipairs(order) do T.truthy(k ~= "focus", "never itself") end
    pickRow.set("target")
    copyRow.func()
    T.eq(DUI:Get("UnitFrames", "focus.width"), 260)
    T.eq(#DUI.Options.ValidatePage(page), 0)
end)

T.test("Frames grow / Groups grow: two picks set direction, growUp and growLeft", function()
    local DUI, ns = login()
    local O = DUI.Options
    local function find(p, label)
        for _, g in ipairs(p.groups) do
            for _, it in ipairs(g.items) do if it.label == label then return it end end
        end
    end
    local ten = O.GetPage("UnitFrames.raid")
    local frames, groups = find(ten, "Frames grow"), find(ten, "Groups grow")
    T.eq(frames.get(), "down"); T.eq(groups.get(), "right")
    frames.set("left")
    T.eq(DUI:Get("UnitFrames", "raid.direction"), "rows"); T.eq(DUI:Get("UnitFrames", "raid.growLeft"), true)
    local _, order = groups.choices()
    T.eq(order[1], "down", "lines across: the groups go down or up")
    groups.set("up")
    T.eq(DUI:Get("UnitFrames", "raid.growUp"), true)
    T.eq(frames.get(), "left"); T.eq(groups.get(), "up")
    -- Raid 40 with its own frames writes its own.
    ns.Raid.SetFollow(40, false)
    local forty = O.GetPage("UnitFrames.raid40")
    find(forty, "Frames grow").set("up")
    T.eq(DUI:Get("UnitFrames", "raid40.growUp"), true)
    T.eq(DUI:Get("UnitFrames", "raid40.direction"), "columns")
    local party = O.GetPage("UnitFrames.party")
    find(party, "Frames grow").set("up")
    T.eq(DUI:Get("UnitFrames", "party.growUp"), true)
end)

T.test("raid sizes: Raid 10, 20 and 40 pages; one that's the same as Raid 10 is grayed out", function()
    local DUI, ns = login()
    local O = DUI.Options
    local ten, page = O.GetPage("UnitFrames.raid"), O.GetPage("UnitFrames.raid40")
    T.eq(ten.label, "Raid 10")
    T.eq(page.label, "Raid 40")
    T.eq(O.GetPage("UnitFrames.raid20").label, "Raid 20")
    T.eq(#O.ValidatePage(ten), 0)
    T.eq(#O.ValidatePage(page), 0)
    local function find(p, f)
        for _, g in ipairs(p.groups) do
            for _, it in ipairs(g.items) do if f(it) then return it, g end end
        end
    end
    local width = find(page, function(it) return it.key == "raid.width" end)
    local follow, card = find(page, function(it) return it.label == "Same as Raid 10" end)
    T.eq(page.groups[1], card, "the size's own card comes first")
    T.falsy(find(ten, function(it) return it.label == "Same as Raid 10" end), "Raid 10 has none")
    -- The rows every size shares live on Raid 10 only.
    local show = find(page, function(it) return it.key == "raid.enabled" end)
    T.eq(O.IsHidden(page, show), true, "Show: on Raid 10's page")
    T.falsy(find(page, function(it) return it.key == "raid.fade.mode" end), "no fade card")
    T.falsy(find(page, function(it) return it.key == "leader.enabled" end), "no leader tools")
    T.truthy(find(ten, function(it) return it.key == "raid.fade.mode" end), "Raid 10 keeps the fade")
    -- Same as Raid 10: grayed out, nothing written.
    T.eq(O.IsDisabled(page, width), true, "follows 10: grayed out")
    T.falsy(O.Set(page, width, 40))
    T.eq(DUI:Get("UnitFrames", "raid.width"), 72, "nothing written while it follows")
    T.eq(O.Get(page, follow), true)
    O.Set(page, follow, false)
    T.eq(O.IsDisabled(page, width), false)
    O.Set(page, width, 44)
    T.eq(DUI:Get("UnitFrames", "raid40.width"), 44)
    T.eq(DUI:Get("UnitFrames", "raid.width"), 72)
    T.eq(O.Get(page, width), 44)
    T.eq(O.Get(ten, find(ten, function(it) return it.key == "raid.width" end)), 72, "Raid 10's page reads its own")
    -- Test mode: 40 before a page opens, then the page shown last.
    DUI.SetTestMode(true)
    stub.RunTimers()
    local function shown()
        local n = 0
        for _, b in ipairs(ns.Raid.preview) do if b:IsShown() then n = n + 1 end end
        return n
    end
    T.eq(shown(), 40)
    T.eq(widthNow(ns), want(ns, 44))
    DUI.OptionsPanel.Show("UnitFrames.raid")
    stub.RunTimers()
    T.eq(shown(), 10)
    T.eq(widthNow(ns), want(ns, 72))
    DUI.OptionsPanel.Show("UnitFrames.raid40")
    stub.RunTimers()
    T.eq(shown(), 40)
    T.eq(widthNow(ns), want(ns, 44))
    DUI.SetTestMode(false)
end)

-- A setting lays out only what it reaches (Units.lua ns.Refresh): a dragged
-- player slider must not lay out the party and the raid's 40 tiles each step.
local function countLayouts(ns)
    local seen = { raid = 0, party = 0 }
    local raidNow, partyLayout, ufLayout = ns.Raid.LayoutNow, ns.Party.group.Layout, ns.UF.Layout
    ns.Raid.LayoutNow = function(...) seen.raid = seen.raid + 1; return raidNow(...) end
    ns.Party.group.Layout = function(...) seen.party = seen.party + 1; return partyLayout(...) end
    ns.UF.Layout = function(f, ...)
        for unit, fr in pairs(ns.frames) do if fr == f then seen[unit] = (seen[unit] or 0) + 1 end end
        return ufLayout(f, ...)
    end
    return seen, function() for k in pairs(seen) do seen[k] = 0 end end
end

T.test("a frame's own setting lays out that frame alone; a party one the party, not the raid; a raid one everything", function()
    local DUI, ns = login()
    local seen, reset = countLayouts(ns)
    DUI:Set("UnitFrames", "player.width", 200)
    stub.RunTimers()
    T.eq(seen.player, 1, "the player frame")
    T.eq(seen.target or 0, 0, "not the target")
    T.eq(seen.party, 0, "not the party")
    T.eq(seen.raid, 0, "not the raid")
    reset()
    DUI:Set("UnitFrames", "targetCastbar.height", 18)
    stub.RunTimers()
    T.eq(seen.target, 1, "a cast bar key: the five frames")
    T.eq(seen.player, 1)
    T.eq(seen.raid, 0)
    reset()
    DUI:Set("UnitFrames", "party.width", 150)
    stub.RunTimers()
    T.eq(seen.party, 1, "the party")
    T.eq(seen.raid, 0, "not the raid")
    reset()
    DUI:Set("UnitFrames", "raid.width", 90)
    stub.RunTimers()
    T.eq(seen.raid, 1, "the raid")
    T.eq(seen.party, 1)
    T.eq(seen.player, 1)
end)

T.test("changed in a fight: a player setting after a raid one still lays out the raid once it ends", function()
    local DUI, ns = login()
    local seen = countLayouts(ns)
    stub.EnterCombat()
    DUI:Set("UnitFrames", "raid.width", 90)
    DUI:Set("UnitFrames", "player.width", 200)
    DUI:Set("UnitFrames", "target.width", 210)
    stub.RunTimers()
    T.eq(seen.raid, 0, "nothing in the fight")
    stub.LeaveCombat()
    stub.RunTimers()
    T.truthy(seen.raid >= 1, "the raid, after the fight")
    T.truthy(seen.player >= 1 and seen.target >= 1, "and both frames")
end)

-- A battleground or a filling raid sends GROUP_ROSTER_UPDATE all the time;
-- a tile whose player didn't change only reads online, crown and role.
T.test("raid roster: a tile with the same player isn't redrawn on a roster update, a new player is", function()
    local DUI, ns = login()
    stub.SetGroup(true, true, 10)
    stub.units.raid3 = { name = "Teft", isPlayer = true, class = "WARRIOR", health = 40, maxHealth = 80, guid = "Player-1-03" }
    local b = tile(ns, "raid3")
    stub.FireEvent("GROUP_ROSTER_UPDATE"); stub.RunTimers()
    local full, status = 0, 0
    local updateAll, updateStatus = ns.UF.UpdateAll, ns.UF.UpdateStatus
    ns.UF.UpdateAll = function(f, ...) if f == b then full = full + 1 end return updateAll(f, ...) end
    ns.UF.UpdateStatus = function(f, ...) if f == b then status = status + 1 end return updateStatus(f, ...) end
    stub.FireEvent("GROUP_ROSTER_UPDATE"); stub.RunTimers()
    T.eq(full, 0, "same player: no full redraw")
    T.truthy(status >= 1, "online still read")
    stub.units.raid3 = { name = "Rock", isPlayer = true, class = "HUNTER", health = 80, maxHealth = 80, guid = "Player-1-07" }
    stub.FireEvent("GROUP_ROSTER_UPDATE"); stub.RunTimers()
    T.eq(full, 1, "someone new on the same unit word: redrawn")
    -- A GUID gone secret (a battleground): the name still tells who it is.
    stub.units.raid3.guid = stub.Secret("Player-1-07")
    stub.FireEvent("GROUP_ROSTER_UPDATE"); stub.RunTimers()
    stub.FireEvent("GROUP_ROSTER_UPDATE"); stub.RunTimers()
    T.eq(full, 2, "secret GUID: read by name, redrawn once as the key changed, then left")
    ns.UF.UpdateAll, ns.UF.UpdateStatus = updateAll, updateStatus
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A mob's threat list updates many times a second in a raid fight; a tile
-- only shows its own member's state, which has its own event.
T.test("raid threat: a mob's list update leaves the tiles alone; a member's own update redoes only their tile", function()
    local DUI, ns = login()
    stub.SetGroup(true, true, 10)
    stub.units.raid3 = { name = "Teft", isPlayer = true, class = "WARRIOR", health = 40, maxHealth = 80 }
    stub.units.raid7 = { name = "Rock", isPlayer = true, class = "HUNTER", health = 80, maxHealth = 80 }
    local b3 = tile(ns, "raid3")
    local b7 = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton2", ns.Raid.header)
    b7:SetAttribute("unit", "raid7")
    ns.Raid.header.initialConfigFunction(ns.Raid.header, b7:GetName())
    stub.RunTimers()
    local done = {}
    local real = ns.UF.UpdateThreat
    ns.UF.UpdateThreat = function(f, ...) done[f] = (done[f] or 0) + 1; return real(f, ...) end
    local walks, buttons = 0, ns.Group.Buttons
    ns.Group.Buttons = function() walks = walks + 1; return buttons() end
    for _ = 1, 5 do stub.FireEvent("UNIT_THREAT_LIST_UPDATE", "target") end
    stub.RunTimers()
    ns.Group.Buttons = buttons
    T.eq(walks, 0, "list update: no walk over every tile, nothing is due")
    T.isnil(done[b3], "list update: tile untouched"); T.isnil(done[b7])
    stub.FireEvent("UNIT_THREAT_SITUATION_UPDATE", "raid7"); stub.RunTimers()
    T.isnil(done[b3], "someone else's change"); T.eq(done[b7], 1, "their own tile")
    stub.FireEvent("UNIT_THREAT_SITUATION_UPDATE", "player"); stub.RunTimers()
    T.eq(done[b3], 1, "your own change: every tile"); T.eq(done[b7], 2)
    ns.UF.UpdateThreat = real
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A battleground sends UNIT_FACTION many times a second for all 40 tiles.
T.test("raid status: one member's faction update redoes their tile; the leader changing redoes all", function()
    local DUI, ns = login()
    stub.SetGroup(true, true, 10)
    stub.units.raid3 = { name = "Teft", isPlayer = true, class = "WARRIOR", health = 40, maxHealth = 80 }
    stub.units.raid7 = { name = "Rock", isPlayer = true, class = "HUNTER", health = 80, maxHealth = 80 }
    local b3 = tile(ns, "raid3")
    local b7 = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton2", ns.Raid.header)
    b7:SetAttribute("unit", "raid7")
    ns.Raid.header.initialConfigFunction(ns.Raid.header, b7:GetName())
    stub.RunTimers()
    local done, real = {}, ns.UF.UpdateLeader
    ns.UF.UpdateLeader = function(f, ...) done[f] = (done[f] or 0) + 1; return real(f, ...) end
    stub.FireEvent("UNIT_FACTION", "raid7"); stub.RunTimers()
    T.isnil(done[b3], "someone else's"); T.eq(done[b7], 1, "their own tile")
    stub.FireEvent("UNIT_FACTION", "player"); stub.RunTimers()
    T.eq(done[b3], 1, "your own: every tile"); T.eq(done[b7], 2)
    stub.FireEvent("PARTY_LEADER_CHANGED"); stub.RunTimers()
    T.eq(done[b3], 2, "the leader: every tile"); T.eq(done[b7], 3)
    ns.UF.UpdateLeader = real
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A heal landing sends health and prediction in the same frame.
T.test("raid heals: a tile reads its heals once a frame, its health at once", function()
    local DUI, ns = login()
    stub.SetGroup(true, true, 10)
    stub.units.raid3 = { name = "Teft", isPlayer = true, class = "WARRIOR", health = 40, maxHealth = 80 }
    local b = tile(ns, "raid3")
    stub.RunTimers()
    local reads, real = 0, ns.UF.UpdatePrediction
    ns.UF.UpdatePrediction = function(...) reads = reads + 1; return real(...) end
    local fire = b:GetScript("OnEvent")
    fire(b, "UNIT_HEALTH", "raid3")
    fire(b, "UNIT_HEAL_PREDICTION", "raid3")
    fire(b, "UNIT_ABSORB_AMOUNT_CHANGED", "raid3")
    T.eq(reads, 0, "folded")
    stub.RunTimers()
    T.eq(reads, 1, "one read for all three")
    fire(b, "UNIT_HEAL_PREDICTION", "raid3")
    stub.RunTimers()
    T.eq(reads, 2, "and the next frame's")
    ns.UF.UpdatePrediction = real
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The header can take a member off a tile (a release, a roster shuffle) in the
-- frame between a heal event and its read.
T.test("raid heals: a tile that loses its member before the read stays quiet", function()
    local DUI, ns = login()
    stub.SetGroup(true, true, 10)
    stub.units.raid3 = { name = "Teft", isPlayer = true, class = "WARRIOR", health = 40, maxHealth = 80 }
    local b = tile(ns, "raid3")
    stub.RunTimers()
    b:GetScript("OnEvent")(b, "UNIT_HEAL_PREDICTION", "raid3")
    b:SetAttribute("unit", nil)
    T.eq(b.unitToken, nil, "the header took the member away")
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("raid flags: a tile repaints only when tapped or the reaction changed", function()
    local DUI, ns = login()
    stub.SetGroup(true, true, 10)
    stub.units.raid3 = { name = "Teft", isPlayer = true, class = "WARRIOR", health = 40, maxHealth = 80 }
    local b = tile(ns, "raid3")
    stub.RunTimers()
    local react = _G.UnitReaction
    _G.UnitReaction = function() return 5 end
    ns.UF.UpdateIdentity(b)
    local paints, real = 0, ns.UF.UpdateIdentity
    ns.UF.UpdateIdentity = function(...) paints = paints + 1; return real(...) end
    local fire = b:GetScript("OnEvent")
    fire(b, "UNIT_FLAGS", "raid3")
    fire(b, "UNIT_FACTION", "raid3")
    T.eq(paints, 0, "entering combat, sitting...: nothing to repaint")
    _G.UnitReaction = function() return 2 end   -- mind controlled
    fire(b, "UNIT_FLAGS", "raid3")
    T.eq(paints, 1, "the reaction changed")
    _G.UnitReaction, ns.UF.UpdateIdentity = react, real
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("range ticker: a tile's group check is kept until the roster changes", function()
    local _, ns = login()
    local b = tile(ns, "raid3")
    stub.units.raid3 = { name = "Pal", isPlayer = true, class = "MAGE", friend = true, raid = true, inRange = false }
    local asked, real = 0, ns.UF.InGroup
    ns.UF.InGroup = function(...) asked = asked + 1; return real(...) end
    for _ = 1, 5 do ns.UF.UpdateRange(b) end
    T.eq(asked, 1, "five ticks, one group check")
    T.eq(stub.Plain(b:GetAlpha()), b.rangeAlpha, "out of range fades")
    stub.units.raid3.inRange = true
    ns.UF.UpdateRange(b)
    T.eq(stub.Plain(b:GetAlpha()), 1, "the range itself is read every tick")
    stub.units.raid3 = { name = "Stranger", isPlayer = true, class = "MAGE", friend = true, inRange = false }
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    ns.UF.UpdateRange(b)
    T.eq(asked, 2, "a roster change asks again")
    T.eq(stub.Plain(b:GetAlpha()), 1, "no longer in the group: no fade")
    ns.UF.InGroup = real
    stub.units.raid3 = nil
end)
