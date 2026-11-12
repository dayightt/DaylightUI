local stub = require("stub")

local function setup(class)
    local _, ns = stub.Load({ module = true, login = false })
    stub.units.player = { class = class or "PRIEST" }
    local tile = CreateFrame("Frame", "FakeTile", UIParent)
    tile:SetSize(72, 28)
    tile.unitToken = "raid1"
    return ns, tile, ns.AuraGroups.Create(tile, "raid1")
end

local function cfg(over)
    local function sq(spot, show) return { show = show, spell = "auto", spot = spot, x = 0, y = 0, paint = "spell", custom = { 1, 1, 1 } } end
    local t = { show = true, size = 8, swipe = true, i1 = sq("topleft", true), i2 = sq("top", true),
                i3 = sq("topright", true), i4 = sq("bottom", false) }
    for k, v in pairs(over or {}) do
        if type(v) == "table" and type(t[k]) == "table" then for a, b in pairs(v) do t[k][a] = b end else t[k] = v end
    end
    return t
end

local BOX = { w = 72, h = 28, padX = 1, padY = 2, bottomInset = 4 }

T.test("off: no squares made (no buttons built for nothing)", function()
    local ns, tile, set = setup()
    ns.Indicators.Place(set, tile, cfg({ show = false }), BOX)
    T.isnil(set.ind[1]); T.isnil(set.ind[4])
end)

T.test("a priest's picks: Renew, Power Word: Shield, Prayer of Mending, each its own square, every rank", function()
    local ns, tile, set = setup("PRIEST")
    ns.Indicators.Place(set, tile, cfg(), BOX)
    local c1, c2, c3 = set.ind[1], set.ind[2], set.ind[3]
    T.truthy(c1 and c2 and c3)
    T.isnil(set.ind[4], "square 4 off: never made")
    local g = c1.__groups.s139
    T.eq(g.filter, "HELPFUL|PLAYER")
    T.truthy(g.opts.candidateFilters.includeSpellIDs[139] and g.opts.candidateFilters.includeSpellIDs[25315])
    T.eq(g.max, 1)
    T.truthy(c2.__groups.s17); T.truthy(c3.__groups.s401859)
    T.eq(c1.__unit, "raid1")
    local p = c1:GetPoint(1)
    T.eq(p, "TOPLEFT")
end)

-- A party member, as the game's filter rule sees one (tests/aura_rules.lua).
local MEMBER = { canAssist = true, groupMember = true }
local shows = require("aura_rules")

T.test("Weakened Soul shows on a party member: the game refuses a debuff by spell id on a friend", function()
    local ns, tile, set = setup("PRIEST")
    ns.Indicators.Place(set, tile, cfg({ i4 = { show = true } }), BOX)
    local g = set.ind[4].__groups.s6788
    local soul = { spellId = 6788, harmful = true, duration = 15, mine = true }
    T.truthy(shows(g, MEMBER, soul), "your own shield's Weakened Soul")
    T.falsy(shows(g, MEMBER, { spellId = 11196, harmful = true, duration = 60, mine = true }),
        "Recently Bandaged, from your own bandage, isn't it")
    T.falsy(shows(g, MEMBER, { spellId = 11, harmful = true, duration = 8 }), "a mob's debuff isn't it")
    ns.Indicators.Place(set, tile, cfg(), BOX)
    T.truthy(shows(set.ind[1].__groups.s139, MEMBER, { spellId = 139, duration = 15, mine = true }),
        "a heal over time still goes by spell id")
end)

T.test("another priest's Weakened Soul: its own group, never a second square beside yours", function()
    local ns, tile, set = setup("PRIEST")
    ns.Indicators.Place(set, tile, cfg({ i4 = { show = true } }), BOX)
    local c = set.ind[4]
    local mine, others = c.__groups.s6788, c.__groups.s6788o
    local soul = { spellId = 6788, harmful = true, duration = 15, canApply = true, fromPlayer = true }
    T.truthy(shows(others, MEMBER, soul), "another priest's")
    T.falsy(shows(mine, MEMBER, soul), "only one of the two groups takes it")
    soul.mine = true
    T.falsy(shows(others, MEMBER, soul), "yours: the other group's")
    T.falsy(shows(others, MEMBER, { spellId = 589, harmful = true, duration = 18, canApply = true, fromPlayer = true }),
        "an enemy priest's Shadow Word: Pain")
    T.falsy(shows(others, MEMBER, { spellId = 8122, harmful = true, duration = 8, canApply = true, fromPlayer = true, cc = true }),
        "an enemy priest's fear")
    T.falsy(shows(others, MEMBER, { spellId = 589, harmful = true, duration = 15, canApply = true }), "a mob's")
    T.eq(others.max, 1)
    ns.Indicators.SetSeen(set, false)
    T.eq(others.max, 0, "out of sight: off with the square")
    ns.Indicators.SetSeen(set, true)
    ns.Indicators.Place(set, tile, cfg({ size = 11, i4 = { show = true, spell = "6346" } }), BOX)
    T.eq(others.max, 0, "another spell picked: off")
    T.eq(others.button:GetWidth(), 11, "a size change reaches it")
end)

T.test("a priest's fourth square is Weakened Soul, on by default, never in the buff row", function()
    local ns, tile, set = setup("PRIEST")
    ns.Indicators.Place(set, tile, cfg({ i4 = { show = true } }), BOX)
    local g = set.ind[4].__groups.s6788
    T.eq(g.max, 1)
    T.isnil(ns.HealSpells.Ids()[6788], "never in the HELPFUL buff row")
    T.truthy(ns.HealSpells.Ids()[17])
    local listed
    for _, f in ipairs(ns.HealSpells.Mine()) do listed = listed or f.id == 6788 end
    T.truthy(listed, "in the spell menu")
    T.eq(ns.DEFAULTS.party.indicators.i4.show, true)
    T.eq(ns.DEFAULTS.raid.indicators.i4.show, true)
end)

T.test("another class's square 4 stays empty: no container built for nothing", function()
    local ns, tile, set = setup("DRUID")
    ns.Indicators.Place(set, tile, cfg({ i4 = { show = true } }), BOX)
    T.isnil(set.ind[4])
end)

T.test("the square is styled when the client builds it: sized, colored, mouse off, swipe on", function()
    local ns, tile, set = setup("DRUID")
    ns.Indicators.Place(set, tile, cfg({ size = 9 }), BOX)
    local btn = set.ind[1].__groups.s774.button
    T.eq(btn:GetWidth(), 9)
    T.falsy(btn:IsMouseEnabled(), "clicks reach the tile (click-casting)")
    T.truthy(btn.__cooldown and btn.__cooldown:GetDrawSwipe())
end)

T.test("the icon look: the client fills the aura's icon, edged in the spell's color", function()
    local ns, tile, set = setup("DRUID")
    ns.Indicators.Place(set, tile, cfg({ look = "icon" }), BOX)
    local btn = set.ind[1].__groups.s774.button
    T.truthy(btn.__icon, "the icon handed to the client")
    T.truthy(btn.__icon:IsShown())
    ns.Indicators.Place(set, tile, cfg({ look = "square" }), BOX)
    stub.RunTimers()
    T.falsy(btn.__icon:IsShown(), "back to the colored square")
end)

T.test("group buffs: Mark of the Wild from any druid, every rank and Gift of the Wild; never in the buff row", function()
    local ns, tile, set = setup("DRUID")
    ns.Indicators.Place(set, tile, cfg({ i4 = { show = true, spell = "1126" } }), BOX)
    local g = set.ind[4].__groups.s1126
    T.eq(g.filter, "HELPFUL", "anyone's")
    T.truthy(g.opts.candidateFilters.includeSpellIDs[9885] and g.opts.candidateFilters.includeSpellIDs[21850])
    T.truthy(ns.HealSpells.IsLong(1126), "counts down its last minute")
    T.falsy(ns.HealSpells.Ids()[1126], "the buff row keeps to heals")
    local listed = false
    for _, f in ipairs(ns.HealSpells.Mine()) do listed = listed or f.id == 1126 end
    T.truthy(listed, "in the spell menu")
end)

T.test("a mage: Arcane Intellect to pick, but no heals, so the buff row falls back to Only mine", function()
    local ns = setup("MAGE")
    T.isnil(ns.HealSpells.Ids())
    T.falsy(ns.HealSpells.Has())
    T.eq(ns.HealSpells.FilterOf(1459), "HELPFUL")
end)

T.test("another spell: its own group, the old one counts 0; size changes reach built buttons", function()
    local ns, tile, set = setup("PRIEST")
    ns.Indicators.Place(set, tile, cfg(), BOX)
    ns.Indicators.Place(set, tile, cfg({ i1 = { spell = "6346" }, size = 12 }), BOX)
    local c = set.ind[1]
    T.eq(c.__groups.s139.max, 0)
    T.eq(c.__groups.s6346.max, 1)
    T.eq(c.__groups.s139.button:GetWidth(), 12)
end)

T.test("out of sight: off; back: on. A new unit retargets every square", function()
    local ns, tile, set = setup("PRIEST")
    ns.Indicators.Place(set, tile, cfg(), BOX)
    ns.Indicators.SetSeen(set, false)
    T.eq(set.ind[1].__groups.s139.max, 0)
    ns.Indicators.SetSeen(set, true)
    T.eq(set.ind[1].__groups.s139.max, 1)
    ns.AuraGroups.SetUnit(set, "raid7")
    T.eq(set.ind[2].__unit, "raid7")
end)

T.test("a paladin's third square is Oath of Light: 5 min, so it counts down its last minute; the others don't", function()
    local ns, tile, set = setup("PALADIN")
    ns.Indicators.Place(set, tile, cfg(), BOX)
    local g = set.ind[3].__groups.s1328548
    T.truthy(g and g.opts.candidateFilters.includeSpellIDs[1328548])
    T.eq(g.filter, "HELPFUL|PLAYER")
    local btn = g.button
    T.truthy(btn.__time, "its time text, written by the client")
    T.truthy(btn.__timeOpts and btn.__timeOpts.textFormatter, "a formatter that writes nothing before the last minute")
    T.isnil(set.ind[1].__groups.s1022.button.__time, "Blessing of Protection: the swipe alone")
    local listed
    for _, f in ipairs(ns.HealSpells.Mine()) do listed = listed or f.id == 1328548 end
    T.truthy(listed, "in the square's spell menu")
    local plain = ns.AuraGroups.PlainSet(tile)
    ns.Indicators.ShowSample(plain, tile, cfg(), BOX, nil)
    T.truthy(plain.ind[3].parts.time and plain.ind[3].parts.time:IsShown(), "the preview shows the countdown")
    T.isnil(plain.ind[1].parts.time)
end)

T.test("a warrior has no picks: nothing made", function()
    local ns, tile, set = setup("WARRIOR")
    ns.Indicators.Place(set, tile, cfg(), BOX)
    T.isnil(set.ind[1])
end)

T.test("the preview shows every square that's on, even with no spell for it (a warrior)", function()
    local ns, tile, _ = setup("WARRIOR")
    local set = ns.AuraGroups.PlainSet(tile)
    ns.Indicators.ShowSample(set, tile, cfg({ i4 = { show = true } }), BOX, nil)
    for i = 1, 4 do T.truthy(set.ind[i] and set.ind[i]:IsShown(), "square " .. i) end
    T.eq(set.ind[4]:GetFrameLevel(), tile:GetFrameLevel() + 9, "over the aura rows, as the real ones")
    ns.Indicators.ShowSample(set, tile, cfg({ show = false }), BOX, nil)
    T.falsy(set.ind[1]:IsShown(), "indicators off: none")
end)

T.test("in a fight no square is made (protected parent); after it, it is", function()
    local ns, tile, set = setup("PRIEST")
    stub.combat = true
    ns.Indicators.Place(set, tile, cfg(), BOX)
    T.isnil(set.ind[1])
    stub.combat = false
    ns.Indicators.Place(set, tile, cfg(), BOX)
    T.truthy(set.ind[1])
end)

T.test("samples: stand-ins placed like real squares, sample tiles show a few, the full one all", function()
    local ns, tile, _ = setup("PRIEST")
    local set = ns.AuraGroups.PlainSet(tile)
    ns.Indicators.ShowSample(set, tile, cfg(), BOX, nil)
    T.truthy(set.ind[1]:IsShown() and set.ind[2]:IsShown() and set.ind[3]:IsShown())
    T.isnil(set.ind[4])
    ns.Indicators.ShowSample(set, tile, cfg(), BOX, 2)
    T.falsy(set.ind[1]:IsShown(), "sample tile 2 shows none")
    ns.Indicators.HideSample(set)
    T.falsy(set.ind[3]:IsShown())
end)

T.test("the Party and Raid pages have the cards, valid; the Healer setup turns them on", function()
    local DUI = stub.Load({ module = true })
    local O = DUI.Options
    for _, id in ipairs({ "party", "raid" }) do
        local page = O.GetPage("UnitFrames." .. id)
        T.eq(#O.ValidatePage(page), 0)
        local found
        for _, g in ipairs(page.groups) do
            for _, it in ipairs(g.items) do if it.key == id .. ".indicators.i2.spot" then found = true end end
        end
        T.truthy(found, id)
    end
    local healer = DUI.Profiles.PRESETS.Healer.UnitFrames
    T.eq(healer.party.indicators.show, true); T.eq(healer.raid.indicators.show, true)
    T.eq(DUI:Get("UnitFrames", "raid.indicators.show"), false, "off by default")
end)

T.test("Design mode: each square is a piece that moves and resizes", function()
    local _, ns = stub.Load({ module = true })
    local labels = {}
    for _, p in ipairs(ns.PageSample.GROUP_PARTS) do labels[p.label] = p end
    local p = labels["Heal indicator 1"]
    T.truthy(p and p.move and p.size)
    T.eq(p.move.spot, "%s.indicators.i1.spot")
end)

T.test("six squares: 5 and 6 sit off in the bottom corners, watch a group buff, show in the preview and Design mode", function()
    local ns, tile, set = setup("DRUID")
    T.eq(#ns.Indicators.SLOTS, 6)
    local d = ns.DEFAULTS.raid.indicators
    T.eq(d.i5.show, false); T.eq(d.i6.show, false, "off: nothing changes for anyone who never turns them on")
    T.eq(d.i5.spot, "bottomleft"); T.eq(d.i6.spot, "bottomright")
    ns.Indicators.Place(set, tile, cfg({ i5 = { show = true, spell = "1126", spot = "bottomleft" },
        i6 = { show = true, spell = "467", spot = "bottomright" } }), BOX)
    T.truthy(set.ind[5].__groups.s1126, "Mark of the Wild on square 5")
    T.truthy(set.ind[6].__groups.s467, "Thorns on square 6")
    local plain = ns.AuraGroups.PlainSet(tile)
    ns.Indicators.ShowSample(plain, tile, cfg({ i4 = { show = true }, i5 = { show = true }, i6 = { show = true } }), BOX, nil)
    for i = 1, 6 do T.truthy(plain.ind[i] and plain.ind[i]:IsShown(), "sample square " .. i) end
    local _, ns2 = stub.Load({ module = true })
    local labels = {}
    for _, p in ipairs(ns2.PageSample.GROUP_PARTS) do labels[p.label] = p end
    T.eq(labels["Heal indicator 6"] and labels["Heal indicator 6"].move.spot, "%s.indicators.i6.spot")
end)
