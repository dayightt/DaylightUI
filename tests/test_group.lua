local stub = require("stub")

local function login(before) return stub.Load({ module = true, before = before }) end

-- A party button as the party's header would make it.
local function partyButton(ns, i, unit)
    local h = ns.Party.header
    local b = CreateFrame("Button", "DaylightUIPartyHeaderUnitButton" .. i, h)
    b:SetAttribute("unit", unit)
    stub.units[unit] = stub.units[unit] or { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 }
    h.initialConfigFunction(h, b:GetName())
    return b
end

T.test("the raid is a group: header, holder and buttons come from the engine", function()
    local _, ns = login()
    local g = ns.Raid.group
    T.eq(g.key, "raid")
    T.eq(g.header, ns.Raid.header)
    T.eq(g.holder, ns.Raid.holder)
    T.eq(ns.Group.all[1], g, "made and listed")
    local b = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton1", g.header)
    b:SetAttribute("unit", "raid2")
    stub.units.raid2 = { name = "Lift", isPlayer = true, class = "PRIEST", health = 5, maxHealth = 10 }
    g.header.initialConfigFunction(g.header, b:GetName())
    T.eq(b.group, g, "the button knows its group")
    T.truthy(b.dispel and b.tint and b.auraSet, "dispel, tint and aura group containers")
    local seen = {}
    for _, x in ns.Group.Buttons() do seen[#seen + 1] = x end
    T.eq(seen[1], b, "Group.Buttons walks every group's buttons")
    T.eq(#seen, 1)
end)

T.test("Group.Buttons skips a group with no buttons and walks on across groups", function()
    local _, ns = login()
    local pb = partyButton(ns, 1, "party1")
    local seen = {}
    for _, x in ns.Group.Buttons() do seen[#seen + 1] = x end
    T.eq(#seen, 1, "the raid has none yet")
    T.eq(seen[1], pb)
    local rb = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton1", ns.Raid.header)
    rb:SetAttribute("unit", "raid2")
    stub.units.raid2 = { name = "Lift", isPlayer = true, class = "PRIEST", health = 5, maxHealth = 10 }
    ns.Raid.header.initialConfigFunction(ns.Raid.header, rb:GetName())
    local pb2 = partyButton(ns, 2, "party2")
    seen = {}
    for _, x in ns.Group.Buttons() do seen[#seen + 1] = x end
    T.eq(#seen, 3)
    T.eq(seen[1], rb, "the raid's first"); T.eq(seen[2], pb); T.eq(seen[3], pb2)
end)

T.test("Group.PerLine, Group.Direction and Group.Footprint read the settings", function()
    local _, ns = login()
    local G = ns.Group
    T.eq(G.PerLine({}), 5)
    T.eq(G.PerLine({ perLine = 3.7 }), 3)
    T.eq(G.Direction({ direction = "rows" }), "rows")
    T.eq(G.Direction({}), "columns", "columns unless set to rows")
    stub.SetGroup(true, false)
    T.eq(G.Direction({ direction = "auto" }), "columns", "no auto any more: a stray old value reads as columns")
    stub.SetGroup(false, false)
    local cfg = { width = 60, height = 50, spacing = 4, groupSpacing = 6, perLine = 5 }
    local w, h = G.Footprint(cfg, 5, true)
    T.eq(w, 5 * 60 + 4 * 4); T.eq(h, 50)
    w, h = G.Footprint(cfg, 10, false)
    T.eq(w, 2 * 60 + 6); T.eq(h, 5 * 50 + 4 * 4)
end)

T.test("an angled tile: the dispel highlight stops at the cut", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "raid.slant", true)
    DUI:Set("UnitFrames", "raid.showDispel", true)
    DUI:Set("UnitFrames", "raid.dispelHighlight", "border")
    stub.RunTimers()
    DUI.SetTestMode(true)
    stub.RunTimers()
    local b = ns.Raid.preview[3]   -- carries a Magic debuff
    T.truthy(b.cut > 0, "the tile is angled")
    local s = b.sampleHL.strips
    T.falsy(s[4]:IsShown(), "no straight edge along the angled end")
    local _, _, _, x = s[1]:GetPoint(2)
    T.eq(x, -b.cut, "the top edge stops where the cut starts")
    local _, _, _, dx = b.sampleDispel:GetPoint(1)
    T.truthy(dx <= -b.cut, "the dispel icon sits clear of the cut")
end)

T.test("the dispel glow: a soft light round the tile, in the sample and handed to the client", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "raid.slant", true)
    stub.RunTimers()
    DUI.SetTestMode(true)
    stub.RunTimers()
    local b = ns.Raid.preview[3]   -- carries a Magic debuff
    local g = b.sampleHL.glow
    T.truthy(b.sampleHLFrame:IsShown(), "on by default")
    T.truthy(g.LEFT:IsShown() and g.TOPLEFT:IsShown(), "lights the straight end")
    T.truthy(g.RIGHT:IsShown() and g.TOPRIGHT:IsShown() and g.BOTTOMRIGHT:IsShown(), "and the angled end")
    -- The angled end's light leans with the cut: one pair of its corners is
    -- sheared out by the cut, the other is left alone.
    local sl = DUI.Style.GetSlant(b)
    local v = g.RIGHT.__vertexOffsets or {}
    local leaned = 0
    for i = 1, 4 do
        if v[i] and math.abs(v[i][1] - sl.cut) < 0.01 then leaned = leaned + 1 end
    end
    T.eq(leaned, 2, "the angled end's light follows the cut")
    -- Under the portrait, at the target outline's level, never over it.
    T.eq(b.sampleGlowFrame:GetFrameLevel(), b:GetFrameLevel() + 1, "the sample glow sits just over the tile")
    DUI:Set("UnitFrames", "raid.dispelGlow", false)
    stub.RunTimers()
    T.falsy(b.sampleHLFrame:IsShown(), "off: nothing (no other highlight is on)")
    -- A real tile. The client colors each glow piece, on the shadow art.
    DUI:Set("UnitFrames", "raid.dispelGlow", true)
    local t = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton9", ns.Raid.header)
    t:SetAttribute("unit", "raid9")
    stub.units.raid9 = { name = "Syl", isPlayer = true, class = "PRIEST", health = 5, maxHealth = 10 }
    ns.Raid.header.initialConfigFunction(ns.Raid.header, t:GetName())
    stub.RunTimers()
    T.eq(t.glowBox:GetFrameLevel(), t:GetFrameLevel() + 1, "its own container, under the portrait")
    local btn = t.glowBox.__groups.glow.button
    local found = 0
    for _, d in ipairs(btn.__dispels or {}) do
        if d.tex == btn.glow.TOP then
            found = found + 1
            local a = d.opts.customDispelAssetMap.Magic
            T.eq(a.asset, ns.GroupParts.GLOW_ART)
            T.eq(a.texCoords.top, 0); T.eq(a.texCoords.bottom, 0.5)
        end
    end
    T.truthy(found >= 1, "the top light is handed over")
end)

T.test("upgrade 1: a tile's corner crown size moves to leaderPx, once", function()
    local _, ns = login()
    local p = { modules = { UnitFrames = { raid = { leaderSize = 14 }, healer = { leaderSize = 9 },
                                           party = { leaderSize = 1.2 } } }, positions = {}, general = {} }
    ns.UpgradeGroupFrames(p)
    local uf = p.modules.UnitFrames
    T.eq(uf.raid.leaderPx, 14); T.isnil(uf.raid.leaderSize)
    T.eq(uf.party.leaderSize, 1.2, "the party's tab crown scale is left alone")
    T.eq(uf.groupFrames, #ns.UPGRADE_STEPS)
    uf.raid.leaderSize = 3
    ns.UpgradeGroupFrames(p)
    T.eq(uf.raid.leaderPx, 14, "a second run changes nothing")
end)

T.test("upgrade 2: a saved party spot moves from the first frame's center to the holder's", function()
    local _, ns = login()
    local p = { modules = { UnitFrames = { groupFrames = 1 } },
                positions = { ["unitframes.party"] = { -500, 100 } }, general = { scale = 1 } }
    ns.UpgradeGroupFrames(p)
    local d = ns.DEFAULTS.party
    local h = 4 * d.height + 3 * d.spacing
    local pos = p.positions["unitframes.party"]
    T.near(pos[1], -500, 1e-6, "same width: same x")
    T.near(pos[2], 100 - (h - d.height) / 2, 1e-6, "the top edge stays put")
    local before = DaylightUI.DB.Copy(p)
    ns.UpgradeGroupFrames(p)
    T.deq(p, before, "a second run changes nothing")
    local p2 = { modules = { UnitFrames = { groupFrames = 1 } }, positions = {}, general = {} }
    ns.UpgradeGroupFrames(p2)
    T.isnil(p2.positions["unitframes.party"], "never moved: the default spot does it")
    local before2 = DaylightUI.DB.Copy(p2)
    ns.UpgradeGroupFrames(p2)
    T.deq(p2, before2, "a second run changes nothing")
end)

T.test("upgrade step 1 carries the healer tables' crown size too", function()
    local _, ns = login()
    -- The step on its own, so a later change to the healer tables can't break this.
    local uf = { healer = { leaderSize = 9 }, healerParty = { leaderSize = 7 } }
    ns.UPGRADE_STEPS[1](uf, {}, {})
    T.eq(uf.healer.leaderPx, 9); T.isnil(uf.healer.leaderSize)
    T.eq(uf.healerParty.leaderPx, 7)
end)

T.test("a profile copied from an older one is upgraded as it's copied", function()
    local DUI, ns = login()
    local uf = DaylightUIDB.profileData[DUI.DB.DEFAULT].modules.UnitFrames
    uf.groupFrames, uf.raid.leaderSize = nil, 14
    local made = DUI.Profiles.Create("Copy", nil, DUI.DB.DEFAULT)
    local copy = DaylightUIDB.profileData[made].modules.UnitFrames
    T.eq(copy.raid.leaderPx, 14)
    T.eq(copy.groupFrames, #ns.UPGRADE_STEPS)
end)

T.test("a portrait needs a frame at least UF.MIN_PORTRAIT_HEIGHT tall", function()
    local DUI, ns = login()
    local f = ns.frames.player
    DUI:Set("UnitFrames", "player.portrait", "class")
    DUI:Set("UnitFrames", "player.height", ns.UF.MIN_PORTRAIT_HEIGHT - 1)
    stub.RunTimers()
    T.falsy(f.portrait:IsShown(), "too short: no ring")
    local O = DUI.Options
    local page = O.GetPage("UnitFrames.player")
    local item
    for _, g in ipairs(page.groups) do for _, it in ipairs(g.items) do if it.key == "player.portrait" then item = it end end end
    T.truthy(O.IsDisabled(page, item), "the option grays out")
    DUI:Set("UnitFrames", "player.height", 43)
    stub.RunTimers()
    T.truthy(f.portrait:IsShown())
end)

T.test("a default party frame with its name on the bar keeps the bar-name placement", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "party.nameOnBar", true)
    stub.RunTimers()
    local f = partyButton(ns, 1, "party1")
    T.truthy(f.portrait:IsShown(), "the default party shows a portrait")
    T.isnil(f.tileName, "not named like a tile")
    T.eq(f.nameText:GetNumPoints(), 1, "one anchor, as UF.PlaceBarName sets")
    -- With no portrait it is named like a tile, clear of the corner icons.
    DUI:Set("UnitFrames", "party.portrait", "none")
    stub.RunTimers()
    T.truthy(f.tileName, "a tile name")
    T.eq(f.nameText:GetNumPoints(), 2, "both edges, as UF.PlaceTileName sets")
end)

T.test("a party button named like a tile keeps its name off the health text", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "party.nameOnBar", true)
    DUI:Set("UnitFrames", "party.portrait", "none")
    DUI:Set("UnitFrames", "party.height", 34)
    stub.RunTimers()
    local f = partyButton(ns, 1, "party1")
    T.truthy(f.tileName, "named like a tile")
    local _, _, _, x = f.nameText:GetPoint(2)
    T.truthy(-x >= f:GetWidth() * 0.5, "the name stops at the middle, before the health text")
end)

T.test("upgrade 3: the party's buff spots under/over are renamed (and 9 moves them into the aura groups)", function()
    local _, ns = login()
    local p = { modules = { UnitFrames = { groupFrames = 2, party = { buffsAt = "below" } } }, positions = {}, general = {} }
    ns.UpgradeGroupFrames(p)
    T.eq(p.modules.UnitFrames.party.auras.buffs.spot, "below", "under the debuffs, now")
    T.truthy(p.modules.UnitFrames.party.auras.buffs.y < 0, "a row further down")
    local before = DaylightUI.DB.Copy(p)
    ns.UpgradeGroupFrames(p)
    T.deq(p, before, "a second run changes nothing")
    p = { modules = { UnitFrames = { groupFrames = 2, party = { buffsAt = "above" } } }, positions = {}, general = {} }
    ns.UpgradeGroupFrames(p)
    T.eq(p.modules.UnitFrames.party.auras.buffs.spot, "above", "over the frame")
    before = DaylightUI.DB.Copy(p)
    ns.UpgradeGroupFrames(p)
    T.deq(p, before, "a second run changes nothing")
    p = { modules = { UnitFrames = { groupFrames = 2, party = { buffsAt = "left" } } }, positions = {}, general = {} }
    ns.UpgradeGroupFrames(p)
    T.eq(p.modules.UnitFrames.party.auras.buffs.spot, "outleft", "other spots stay theirs")
end)

T.test("upgrade 4: a party that ran as raid tiles keeps that look, in that spot", function()
    local _, ns = login()
    local p = { modules = { UnitFrames = { groupFrames = 3,
                    raid = { inParty = true, direction = "auto", width = 64, height = 48, healthText = "missing",
                             oocAlpha = 0.3 },
                    party = { enabled = false, oocAlpha = 0.8 },
                    raidText = { name = 13 } } },
                positions = { ["unitframes.raid"] = { 40, -200 } }, general = {} }
    DaylightUI.FadeUpgrade.Run(p)
    ns.UpgradeGroupFrames(p)
    local uf = p.modules.UnitFrames
    T.isnil(uf.raid.inParty)
    T.eq(uf.raid.direction, "columns", "auto is gone: a raid runs in columns")
    T.eq(uf.party.width, 64); T.eq(uf.party.height, 48); T.eq(uf.party.healthText, "missing")
    T.eq(uf.party.portrait, "none"); T.eq(uf.party.nameOnBar, true); T.eq(uf.party.slant, false)
    T.eq(uf.party.direction, "rows", "auto in a party was a row")
    T.eq(uf.party.hideSelf, false, "you were in it")
    T.eq(uf.partyText.name, 13)
    T.eq(uf.party.enabled, true, "the tiles showed whatever the party frames' switch")
    T.eq(uf.party.fade.alpha, 0.3, "the tiles' out-of-combat opacity")
    T.eq(p.positions["unitframes.party"][1], 40); T.eq(p.positions["unitframes.party"][2], -200)
    local before = DaylightUI.DB.Copy(p)
    ns.UpgradeGroupFrames(p)
    T.deq(p, before, "a second run changes nothing")
end)

T.test("upgrade 4 leaves a plain party alone", function()
    local _, ns = login()
    local p = { modules = { UnitFrames = { groupFrames = 3, raid = { direction = "auto" } } }, positions = {}, general = {} }
    ns.UpgradeGroupFrames(p)
    T.isnil(p.modules.UnitFrames.party and p.modules.UnitFrames.party.portrait)
    T.eq(p.modules.UnitFrames.raid.direction, "columns")
    local before = DaylightUI.DB.Copy(p)
    ns.UpgradeGroupFrames(p)
    T.deq(p, before, "a second run changes nothing")
end)

T.test("upgrade 4: tiles that never moved take the raid's default spot", function()
    local _, ns = login()
    local p = { modules = { UnitFrames = { groupFrames = 3, raid = { inParty = true, width = 60, height = 30 } } },
                positions = {}, general = {} }
    ns.UpgradeGroupFrames(p)
    local uf = p.modules.UnitFrames
    local party = ns.WithDefaults(uf.party, ns.DEFAULTS.party)
    local w, h = ns.Group.Footprint(party, 5, party.direction == "rows")
    local want = ns.SpotCentre("TOPLEFT", 20, -220, w, h, 1)
    local at = p.positions["unitframes.party"]
    T.truthy(type(at) == "table", "a spot was set")
    T.near(at[1], want[1], 0.01); T.near(at[2], want[2], 0.01)
    local before = DaylightUI.DB.Copy(p)
    ns.UpgradeGroupFrames(p)
    T.deq(p, before, "a second run changes nothing")
end)

T.test("upgrade 4: healer frames on win over raid tiles in a party", function()
    local _, ns = login()
    -- The step on its own. Step 5 then turns the healer frames into party tiles.
    local uf = { healerFrames = true, raid = { inParty = true, width = 60 } }
    ns.UPGRADE_STEPS[4](uf, {}, {})
    T.isnil(uf.party and uf.party.portrait)
    T.isnil(uf.raid.inParty)
end)

T.test("upgrade 5: healer frames become the party's and the raid's settings, in their spots", function()
    local _, ns = login()
    local p = { modules = { UnitFrames = { groupFrames = 4, healerFrames = true,
                    healerParty = { width = 80, split = true }, healer = { width = 50, leaderPx = 9, fadeOOC = true, oocAlpha = 0.2 },
                    party = { enabled = false, oocAlpha = 0.7, nameColor = "class" },
                    raid = { oocAlpha = 0.6, nameColor = "custom", nameCustom = { 1, 0, 0 } },
                    healerPartyText = { name = 13 } } },
                positions = { ["unitframes.healer"] = { 10, -300 } },
                general = { scale = 1, lastNames = { healerParty = false } } }
    DaylightUI.FadeUpgrade.Run(p)
    ns.UpgradeGroupFrames(p)
    local uf, pos = p.modules.UnitFrames, p.positions
    T.eq(uf.party.width, 80); T.eq(uf.party.height, 56, "the old party tiles' default")
    T.eq(uf.party.portrait, "none"); T.eq(uf.party.nameOnBar, true); T.eq(uf.party.auras.debuffs.show, false)
    T.eq(uf.party.direction, "rows"); T.eq(uf.party.hideSelf, false)
    T.eq(uf.party.showDispel, true); T.eq(uf.party.auras.buffs.spot, "bottomleft")
    T.eq(uf.partyText.name, 13)
    T.eq(uf.raid.width, 50); T.eq(uf.raid.leaderPx, 9); T.eq(uf.raid.direction, "columns")
    T.eq(uf.party.enabled, true, "the tiles showed whatever the party frames' switch")
    T.isnil(uf.party.fade, "the party tiles had none: the default")
    T.isnil(uf.party.nameColor, "the tiles' global name color")
    T.eq(uf.raid.fade.mode, "ooc"); T.eq(uf.raid.fade.alpha, 0.2, "the raid tiles' own opacity")
    T.isnil(uf.raid.nameColor, "the tiles' global name color, not the old raid page's")
    T.isnil(uf.raid.nameCustom)
    T.eq(pos["unitframes.raid"][1], 10); T.eq(pos["unitframes.raid"][2], -300)
    local w, h = 5 * 80 + 4 * 4, 56
    T.near(pos["unitframes.party"][1], 0, 1e-6)
    T.near(pos["unitframes.party"][2], -UIParent:GetHeight() / 2 + 140 + h / 2, 1e-6, "the old default spot")
    T.eq(p.general.lastNames.party, false)
    for _, k in ipairs({ "healerFrames", "healer", "healerText", "healerParty", "healerPartyText" }) do
        T.isnil(uf[k], k .. " gone")
    end
    T.isnil(pos["unitframes.healer"]); T.isnil(pos["unitframes.healerParty"])
    T.isnil(p.general.lastNames.healerParty)
    local before = DaylightUI.DB.Copy(p)
    ns.UpgradeGroupFrames(p)
    T.deq(p, before, "a second run changes nothing")
end)

T.test("upgrade 5: a sparse profile (healer frames on, nothing else saved) doesn't error", function()
    local _, ns = login()
    local p = { modules = { UnitFrames = { groupFrames = 4, healerFrames = true } }, positions = {}, general = {} }
    T.noerror(function() ns.UpgradeGroupFrames(p) end)
    T.eq(p.modules.UnitFrames.party.width, 60, "the old defaults fill in")
    T.truthy(p.positions["unitframes.party"])
    local before = DaylightUI.DB.Copy(p)
    ns.UpgradeGroupFrames(p)
    T.deq(p, before, "a second run changes nothing")
    -- Other partial shapes: some healer tables saved, others missing.
    local shapes = {
        { uf = { healer = { width = 50 } }, partyWidth = 50, raidWidth = 50 },
        { uf = { healerParty = { split = true, width = 70 } }, partyWidth = 70, raidWidth = 60 },
        { uf = { healerParty = { width = 70 }, healer = { height = 40 } }, partyWidth = 70, raidWidth = 60 },   -- not split, so the raid tiles' saved values are copied over
        { uf = { healerText = { name = 9 }, healer = "junk" }, partyWidth = 60, raidWidth = 60, name = 9 },
        { uf = { healerPartyText = { name = 8 } }, partyWidth = 60, raidWidth = 60, name = 8 },
        { uf = {}, general = { lastNames = { healer = false } }, partyWidth = 60, raidWidth = 60 },
    }
    for i, s in ipairs(shapes) do
        s.uf.groupFrames, s.uf.healerFrames = 4, true
        local q = { modules = { UnitFrames = s.uf }, positions = {}, general = s.general or {} }
        T.noerror(function() ns.UpgradeGroupFrames(q) end, "shape " .. i)
        local uf = q.modules.UnitFrames
        T.eq(uf.party.width, s.partyWidth, "shape " .. i .. ": party")
        T.eq(uf.raid.width, s.raidWidth, "shape " .. i .. ": raid")
        if s.name then T.eq(uf.partyText.name, s.name, "shape " .. i .. ": names") end
        T.truthy(q.positions["unitframes.party"] and q.positions["unitframes.raid"], "shape " .. i .. ": spots")
        T.isnil(uf.healerFrames); T.isnil(uf.healer); T.isnil(uf.healerParty)
        before = DaylightUI.DB.Copy(q)
        ns.UpgradeGroupFrames(q)
        T.deq(q, before, "shape " .. i .. ": a second run changes nothing")
    end
    T.eq(shapes[6].general.lastNames.raid, false, "the raid tiles' names switch carried over")
    T.isnil(shapes[6].general.lastNames.healer)
end)

T.test("upgrade 5: healer frames on but their party off leaves the party frames as they were", function()
    local _, ns = login()
    local p = { modules = { UnitFrames = { groupFrames = 4, healerFrames = true,
                    healerParty = { split = true, enabled = false, width = 80 }, healer = { width = 50 },
                    party = { width = 150 } } },
                positions = { ["unitframes.party"] = { -400, 50 } },
                general = { lastNames = { party = false, healerParty = true } } }
    ns.UpgradeGroupFrames(p)
    local uf, pos = p.modules.UnitFrames, p.positions
    T.eq(uf.party.width, 150, "the party frames' own settings")
    T.isnil(uf.party.portrait, "not turned into tiles")
    T.eq(pos["unitframes.party"][1], -400); T.eq(pos["unitframes.party"][2], 50, "nor moved")
    T.eq(p.general.lastNames.party, false, "the party frames' own names switch")
    T.eq(uf.raid.width, 50, "the raid half still applies")
    T.truthy(pos["unitframes.raid"])
    T.isnil(uf.healerParty); T.isnil(p.general.lastNames.healerParty)
    local before = DaylightUI.DB.Copy(p)
    ns.UpgradeGroupFrames(p)
    T.deq(p, before, "a second run changes nothing")
end)

T.test("upgrade 5: the first healer layout (raid tiles under the player) ends as party and raid tiles", function()
    local DUI = stub.Load({ module = true, before = function()
        DaylightUIDB = { version = 2, profileData = { Default = {
            general = {}, positions = { ["unitframes.raid"] = { 0, -320 } },
            modules = { UnitFrames = { raid = { underPlayer = true, inParty = true, direction = "auto", width = 60,
                                                height = 56, healthText = "missing" },
                                       raidText = { name = 11 }, pet = { beside = true } } } } } }
    end })
    T.isnil(DUI:Get("UnitFrames", "healerFrames"))
    T.eq(DUI:Get("UnitFrames", "party.width"), 60)
    T.eq(DUI:Get("UnitFrames", "party.healthText"), "missing")
    T.eq(DUI:Get("UnitFrames", "party.portrait"), "none")
    T.eq(DUI:Get("UnitFrames", "raid.width"), 60)
    T.eq(DUI:Get("UnitFrames", "raid.direction"), "columns")
    T.eq(DUI.DB.Positions()["unitframes.raid"][2], -320, "the tiles' spot")
    local p = DaylightUIDB.profileData[DUI.DB.DEFAULT]
    local before = DUI.DB.Copy(p)
    DUI.DB.RunUpgrades(p)
    T.deq(p, before, "a second run changes nothing")
end)

T.test("Add Healer from an older Default: the copy is upgraded before the preset lands", function()
    local DUI, ns = login()
    -- Default as an older version left it: unstamped, with healer frames on.
    local uf = DaylightUIDB.profileData[DUI.DB.DEFAULT].modules.UnitFrames
    uf.groupFrames, uf.healerFrames, uf.healer = nil, true, { width = 44 }
    stub.SetScreen(3840, 2160, 0.64) -- the preset's own screen, so its spots apply as written
    local made = DUI.Profiles.AddPreset("Healer")
    T.eq(made, "Healer")
    local h = DaylightUIDB.profileData.Healer
    T.eq(h.modules.UnitFrames.groupFrames, #ns.UPGRADE_STEPS, "stamped: never upgraded again")
    T.isnil(h.modules.UnitFrames.healerFrames)
    T.eq(h.positions["unitframes.party"][1], 0)
    T.eq(h.positions["unitframes.party"][2], -253, "the preset's spot, not converted")
    T.eq(h.positions["unitframes.raid"][2], -253)
    T.eq(h.modules.UnitFrames.party.width, 60, "the preset's party")
    T.eq(h.modules.UnitFrames.raid.width, 60, "and raid")
    local before = DUI.DB.Copy(h)
    DUI.DB.RunUpgrades(h)
    T.deq(h, before, "upgrading it again changes nothing")
end)

T.test("upgrade 2 at scale 1.2: the top edge stays put in UIParent units", function()
    local _, ns = login()
    local p = { modules = { UnitFrames = { groupFrames = 1 } },
                positions = { ["unitframes.party"] = { -500, 100 } }, general = { scale = 1.2 } }
    ns.UpgradeGroupFrames(p)
    -- Default party: 170 x 34 with gaps of 38, player left out. The holder is
    -- four frames tall (4 * 34 + 3 * 38 = 250), 216 taller than one frame, so at
    -- scale 1.2 its center drops 216 * 1.2 / 2 = 129.6.
    local pos = p.positions["unitframes.party"]
    T.near(pos[1], -500, 1e-6, "same width: same x")
    T.near(pos[2], 100 - 129.6, 1e-6)
end)

T.test("an old profile upgrades at login: raid tiles in a party, moved, at scale 1.2", function()
    local DUI, ns = login(function()
        DaylightUIDB = { modules = { UnitFrames = { raid = { inParty = true, direction = "auto", width = 64, height = 48 } } },
                         positions = { ["unitframes.raid"] = { 100, 50 } }, general = { scale = 1.2 } }
    end)
    stub.RunTimers()
    local uf = DUI.DB.Active().modules.UnitFrames
    T.eq(uf.groupFrames, #ns.UPGRADE_STEPS)
    T.isnil(uf.raid.inParty)
    T.eq(uf.raid.direction, "columns")
    T.eq(uf.party.width, 64); T.eq(uf.party.height, 48); T.eq(uf.party.portrait, "none")
    T.eq(uf.party.direction, "rows"); T.eq(uf.party.enabled, true)
    local pos = DUI.DB.Positions()
    T.eq(pos["unitframes.party"][1], 100); T.eq(pos["unitframes.party"][2], 50)
    T.eq(pos["unitframes.raid"][1], 100, "the raid keeps its own spot")
    -- Movers places it by UIParent's center, in the holder's own units.
    local pt, rel, rp, x, y = ns.Party.holder:GetPoint(1)
    T.eq(pt, "CENTER"); T.eq(rel, UIParent); T.eq(rp, "CENTER")
    T.near(x, 100 / 1.2, 1e-6); T.near(y, 50 / 1.2, 1e-6)
end)

T.test("an old profile upgrades at login: healer frames on become party and raid settings", function()
    local DUI, ns = login(function()
        DaylightUIDB = { modules = { UnitFrames = { healerFrames = true,
                             healerParty = { width = 80, split = true }, healer = { width = 50 } } },
                         positions = { ["unitframes.healer"] = { 10, -300 }, ["unitframes.healerParty"] = { 0, -200 } },
                         general = { scale = 1 } }
    end)
    stub.RunTimers()
    local uf = DUI.DB.Active().modules.UnitFrames
    T.eq(uf.groupFrames, #ns.UPGRADE_STEPS)
    T.eq(uf.party.width, 80); T.eq(uf.party.height, 56); T.eq(uf.party.portrait, "none")
    T.eq(uf.party.direction, "rows"); T.eq(uf.party.hideSelf, false); T.eq(uf.party.spacing, 4)
    T.eq(uf.raid.width, 50)
    for _, k in ipairs({ "healerFrames", "healer", "healerParty" }) do T.isnil(uf[k], k .. " gone") end
    local pos = DUI.DB.Positions()
    -- Old tiles were a row of five, 5 * 80 + 4 * 4 = 416 by 56. The party now
    -- puts the same five in a row, so same box, same spot.
    T.eq(pos["unitframes.party"][1], 0); T.eq(pos["unitframes.party"][2], -200)
    T.eq(pos["unitframes.raid"][1], 10); T.eq(pos["unitframes.raid"][2], -300)
    T.isnil(pos["unitframes.healer"]); T.isnil(pos["unitframes.healerParty"])
    local _, _, _, x, y = ns.Party.holder:GetPoint(1)
    T.near(x, 0, 1e-6); T.near(y, -200, 1e-6)
    T.eq(#stub.errors, 0)
end)

T.test("a failing upgrade can't stop the unit frames being built", function()
    local _, ns = stub.Load({ module = true, login = false })
    ns.UpgradeGroupFrames = function() error("boom") end
    stub.FireEvent("PLAYER_LOGIN")
    stub.RunTimers()
    T.truthy(ns.frames.player, "the frames are there")
    T.truthy(ns.Party.holder, "and the party")
    T.truthy(#stub.errors >= 1, "the error is reported")
end)

T.test("sample buttons can be made, laid out and filled on another frame", function()
    local _, ns = stub.Load({ module = true })
    local g = ns.Party.group
    local box = CreateFrame("Frame", nil, UIParent)
    local list = { g:NewSampleButton(box, 1), g:NewSampleButton(box, 2) }
    T.eq(list[1]:GetParent(), box)
    T.truthy(list[1].sampleDispel, "its sample dispel icon")
    local cfg, text = ns.module.db.party, ns.module.db.partyText
    g:LayoutSamples(list, box, cfg, text, 170, 34)
    local _, rel, _, x, y = list[2]:GetPoint(1)
    T.eq(rel, box)
    T.eq(x, 0)
    T.eq(y, -(34 + cfg.spacing), "down from the first")
    g:FillSamples(list, 1, cfg)
    T.truthy(list[1]:IsShown())
    T.truthy(string.find(list[1].nameText.__text, "Kaladin", 1, true), "the first sample member")
    T.falsy(list[2]:IsShown(), "past the count: hidden")
    T.falsy(ns.Party.preview[1]:IsShown(), "the party's own samples untouched")
end)

-- ---------------------------------------------------------------------
-- The game's group header (SecureGroupHeaders.lua, copied where it matters)
-- with the client's bug: a button it makes during a fight never gets its
-- initialConfigFunction (Grid2 and Cell work around the same bug), so it
-- stays an empty frame with no size. These tests run the real flow: the
-- button is made, set up, and only then handed its unit. GetFrameHandle
-- returning nil in SetupUnitButtonConfiguration is a guess from the source.
-- ---------------------------------------------------------------------
local function headerUnits(h)
    local units, n = {}, stub.groupSize or 0
    if IsInRaid() and h:GetAttribute("showRaid") then
        for i = 1, n do units[#units + 1] = "raid" .. i end
    elseif IsInGroup() and h:GetAttribute("showParty") then
        if h:GetAttribute("showPlayer") then units[1] = "player" end
        for i = 1, n - 1 do units[#units + 1] = "party" .. i end
    elseif h:GetAttribute("showSolo") then
        units[1] = "player"   -- solo shows the player whatever showPlayer says
    end
    return units
end

local function headerUpdate(h)
    local units = headerUnits(h)
    local first = h:GetAttribute("startingIndex") or 1
    local shown = #units - (first - 1)
    local perColumn, columns = h:GetAttribute("unitsPerColumn"), 1
    if perColumn and shown > perColumn then
        columns = math.min(math.ceil(shown / perColumn), h:GetAttribute("maxColumns") or 1)
    else
        perColumn = shown
    end
    local finish = math.min((first - 1) + perColumn * columns, #units)
    shown = finish - (first - 1)
    for i = 1, math.max(1, shown) do
        if not h:GetAttribute("child" .. i) then
            local name = h:GetName() .. "UnitButton" .. i
            local b = CreateFrame("Button", name, h, h:GetAttribute("template"))
            h[i] = b
            if not InCombatLockdown() then   -- the client's bug
                stub.inSecure = stub.inSecure + 1
                b:SetSize(h:GetAttribute("unitWidth"), h:GetAttribute("unitHeight"))
                stub.inSecure = stub.inSecure - 1
                h.initialConfigFunction(h, name)
            end
            local ignore = h:GetAttribute("_ignore")
            h:SetAttribute("_ignore", true)
            h:SetAttribute("child" .. i, b)
            h:SetAttribute("_ignore", ignore)
        end
    end
    stub.inSecure = stub.inSecure + 1
    local num = 0
    for i = first, finish do
        num = num + 1
        local b = h:GetAttribute("child" .. num)
        b:SetAttribute("unit", units[i])
        b:Show()
    end
    while true do
        num = num + 1
        local b = h:GetAttribute("child" .. num)
        if not b then break end
        b:Hide()
        b:SetAttribute("unit", nil)
    end
    stub.inSecure = stub.inSecure - 1
end

local function realHeaders()
    stub.secure = true
    stub.TEMPLATES.SecureGroupHeaderTemplate = function(h)
        h:Hide()
        h:SetScript("OnShow", headerUpdate)
        h:SetScript("OnAttributeChanged", function(self, name)
            if name == "_ignore" or self:GetAttribute("_ignore") then return end
            if self:IsVisible() then headerUpdate(self) end
        end)
        h:SetScript("OnEvent", function(self) if self:IsVisible() then headerUpdate(self) end end)
        h:RegisterEvent("GROUP_ROSTER_UPDATE")
    end
end

local function madeOn(h)
    local n = 0
    while h:GetAttribute("child" .. (n + 1)) do n = n + 1 end
    return n
end

local function join(raid, count)
    stub.SetGroup(true, raid, count)
    stub.SetConditions({ group = true, ["group:raid"] = raid or nil })
    stub.FireEvent("GROUP_ROSTER_UPDATE")
end

T.test("you join a party in a fight: the new member's frame shows, dressed and sized", function()
    local DUI, ns = stub.Load({ module = true, before = realHeaders })
    stub.RunTimers()
    stub.units.party1 = { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 }
    stub.EnterCombat()
    join(false, 2)
    local b = ns.Party.header:GetAttribute("child1")
    T.truthy(b, "the header has a button")
    T.truthy(b.health, "dressed")
    T.truthy(b:IsVisible(), "on screen")
    T.near(b:GetWidth(), DUI:Get("UnitFrames", "party.width"), 1, "with its size")
    T.eq(b.nameText.__text, "Kaladin")
    T.eq(b.auraSet.debuffs.__unit, "party1", "its auras are the member's")
end)

T.test("a party turns into a raid in a fight: the raid tiles take over from the party frames", function()
    local _, ns = stub.Load({ module = true, before = realHeaders })
    stub.RunTimers()
    stub.units.party1 = { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 }
    join(false, 2)
    T.truthy(ns.Party.header:IsVisible(), "a party first")
    stub.EnterCombat()
    stub.units.raid1 = { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 }
    join(true, 2)
    T.falsy(ns.Party.header:IsShown(), "the party frames step aside")
    T.truthy(ns.Raid.header:IsVisible(), "the raid shows")
    T.truthy(ns.Raid.header:GetAttribute("child1").health, "dressed")
end)

T.test("the game's [group] stays as it was until the fight ends, unit tokens don't", function()
    stub.Load({ module = true, before = realHeaders })
    stub.EnterCombat()
    stub.SetConditions({ group = true })
    T.eq(SecureCmdOptionParse("[group] show; hide"), "hide", "still solo to the macro")
    stub.units.party1 = { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 }
    T.eq(SecureCmdOptionParse("[@party1,exists] show; hide"), "show")
    stub.LeaveCombat()
    T.eq(SecureCmdOptionParse("[group] show; hide"), "show", "right again once it's over")
end)

T.test("you join a raid in a fight: every tile is ready, all forty", function()
    local _, ns = stub.Load({ module = true, before = realHeaders })
    stub.RunTimers()
    T.eq(madeOn(ns.Raid.header), 40)
    stub.units.raid1 = { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 }
    stub.units.raid33 = { name = "Teft", isPlayer = true, class = "PRIEST", health = 5, maxHealth = 10 }
    stub.EnterCombat()
    join(true, 33)
    local b = ns.Raid.header:GetAttribute("child33")
    T.truthy(b.health and b:IsVisible(), "the 33rd tile shows")
    T.eq(b.nameText.__text, "Teft")
end)

T.test("alone, the frames made ahead stay bare: nothing is dressed until someone fills one", function()
    local _, ns = stub.Load({ module = true, before = realHeaders })
    T.eq(madeOn(ns.Party.header), 5, "the party's five")
    T.eq(madeOn(ns.Raid.header), 40, "the raid's forty, at once: they're cheap")
    T.eq(#ns.Party.buttons, 0, "none dressed")
    T.eq(#ns.Raid.buttons, 0)
    T.isnil(ns.Raid.header:GetAttribute("child1").spec)
    T.falsy(ns.Raid.header:IsShown(), "alone: the header stays hidden")
    for i = 1, 40 do T.falsy(ns.Raid.header:GetAttribute("child" .. i):IsShown(), "no empty tile on screen") end

    stub.units.party1 = { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 }
    join(false, 2)
    local b = ns.Party.header:GetAttribute("child1")
    T.eq(b.unitToken, "party1")
    T.truthy(b.health and b:IsVisible())
    T.eq(#ns.Party.buttons, 1, "only the member's")
    T.falsy(ns.Party.header:GetAttribute("child2"):IsShown(), "only the members show")
    T.isnil(ns.Party.header:GetAttribute("child2").spec)
end)

T.test("a reload in a fight: the frames come when it ends, set up and dressed", function()
    stub.units.party1 = { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 }
    local DUI, ns = stub.Load({ module = true, before = function()
        realHeaders()
        stub.SetGroup(true, false, 2)
        stub.SetConditions({ group = true })
        stub.EnterCombat()
    end })
    stub.LeaveCombat()
    local h = ns.Party.header
    local b = h:GetAttribute("child1")
    T.truthy(b and b.health, "dressed once it's over")
    T.eq(b.unitToken, "party1")
    T.near(b:GetWidth(), DUI:Get("UnitFrames", "party.width"), 1, "with its size")
    T.eq(madeOn(h), 5)
end)

T.test("a size changed while they're bare reaches them, so one dressed in a fight fits", function()
    local DUI, ns = stub.Load({ module = true, before = realHeaders })
    DUI:Set("UnitFrames", "party.width", 150)
    stub.RunTimers()
    T.near(ns.Party.header:GetAttribute("child3"):GetWidth(), 150, 1)
end)

T.test("a click-cast binding made while they're bare reaches them", function()
    local _, ns = stub.Load({ module = true, before = realHeaders })
    local b = ns.Party.header:GetAttribute("child2")
    local seen = {}
    ns.ClickCast.EachFrame(function(f) seen[f] = true end)
    T.truthy(seen[b], "bare frames are gone over with the rest")
end)

T.test("a member's button keeps its unit when the frames are made with people in the group", function()
    local _, ns = stub.Load({ module = true, before = function()
        realHeaders()
        stub.units.raid1 = { name = "Teft", isPlayer = true, class = "PRIEST", health = 5, maxHealth = 10 }
        stub.SetGroup(true, true, 1)
        stub.SetConditions({ group = true, ["group:raid"] = true })
    end })
    stub.RunTimers()
    local h = ns.Raid.header
    T.eq(madeOn(h), 40)
    local b = h:GetAttribute("child1")
    T.eq(b:GetAttribute("unit"), "raid1", "back on its member")
    T.eq(b.unitToken, "raid1")
    T.eq(#ns.Raid.buttons, 1, "the shift for a moment dressed nobody else")
end)

T.test("Group, then role: the group headers get their buttons", function()
    local DUI, ns = stub.Load({ module = true, before = realHeaders })
    DUI:Set("UnitFrames", "raid.sortBy", "grouprole")
    stub.RunTimers()
    for _, gh in ipairs(ns.Raid.group.headers) do T.eq(madeOn(gh), 5) end
end)

T.test("frames switched off make no tiles", function()
    local DUI, ns = stub.Load({ module = true, before = function()
        realHeaders()
    end })
    DUI:Set("UnitFrames", "raid.sortBy", "grouprole")
    DUI:Set("UnitFrames", "raid.enabled", false)
    stub.RunTimers()
    for _, gh in ipairs(ns.Raid.group.headers) do T.truthy(madeOn(gh) <= 5) end
    T.falsy(ns.Raid.header:IsShown())
end)

T.test("Show when alone: out of a group the party frames show you, and step aside in a raid", function()
    local DUI, ns = stub.Load({ module = true, before = realHeaders })
    stub.RunTimers()
    T.falsy(ns.Party.header:IsShown(), "off by default: nothing alone")
    DUI:Set("UnitFrames", "party.showSolo", true)
    stub.RunTimers()
    T.truthy(ns.Party.header:IsVisible(), "alone: the header shows")
    local b = ns.Party.header:GetAttribute("child1")
    T.truthy(b and b:IsShown(), "one button")
    T.eq(b:GetAttribute("unit"), "player", "it's you, with Show yourself off too")
    stub.units.raid1 = { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 }
    join(true, 2)
    T.falsy(ns.Party.header:IsShown(), "a raid: the raid frames take over")
    DUI:Set("UnitFrames", "party.showSolo", false)
    stub.SetGroup(false, false, 0)
    stub.SetConditions({})
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    stub.RunTimers()
    T.falsy(ns.Party.header:IsShown(), "switched off: hidden alone again")
end)
