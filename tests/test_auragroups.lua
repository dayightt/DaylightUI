local stub = require("stub")

local function setup(opts)
    local _, ns = stub.Load({ module = true, login = false, before = opts and opts.before })
    local tile = CreateFrame("Frame", "FakeTile", UIParent)
    tile:SetSize(72, 28)
    return ns, tile, ns.AuraGroups.Create(tile, "raid1")
end

local function cfg(over)
    local t = {
        debuffs = { show = true, which = "all", spot = "bottom", grow = "center", size = 13, max = 3, rows = 1, spacing = 2, x = 0, y = 0 },
        cc = { show = true, spot = "center", grow = "center", size = 18, max = 1, rows = 1, spacing = 2, x = 0, y = 0 },
        buffs = { show = false, which = "mine", spot = "bottomleft", grow = "right", size = 14, max = 4, rows = 1, spacing = 2, x = 0, y = 0 },
    }
    for g, o in pairs(over or {}) do for k, v in pairs(o) do t[g][k] = v end end
    return t
end

local BOX = { w = 72, h = 28, padX = 1, padY = 2, bottomInset = 4 }

T.test("one container per group; a choice's group is added the first time it shows, and kept", function()
    local ns, tile, set = setup()
    T.eq(set.debuffs.__unit, "raid1")
    T.eq(#set.debuffs.__groupOrder, 0, "nothing until placed")
    ns.AuraGroups.Place(set, tile, cfg(), BOX)
    T.eq(table.concat(set.debuffs.__groupOrder, ","), "notcc")
    T.eq(set.debuffs.__groups.notcc.filter, "HARMFUL|!CROWD_CONTROL")
    T.eq(set.cc.__groups.cc.filter, "HARMFUL|CROWD_CONTROL")
    T.eq(#set.buffs.__groupOrder, 0, "buffs off: none")
    ns.AuraGroups.Place(set, tile, cfg({ cc = { show = false }, buffs = { show = true, which = "all" } }), BOX)
    ns.AuraGroups.Place(set, tile, cfg({ debuffs = { which = "dispel" } }), BOX)
    T.eq(table.concat(set.debuffs.__groupOrder, ","), "notcc,all,dispel")
    T.eq(set.debuffs.__groups.dispel.filter, "HARMFUL|RAID_PLAYER_DISPELLABLE")
    T.eq(table.concat(set.buffs.__groupOrder, ","), "all")
end)

T.test("only the chosen group counts; debuffs skip crowd control while that group shows it", function()
    local ns, tile, set = setup()
    ns.AuraGroups.Place(set, tile, cfg(), BOX)
    T.eq(set.debuffs.__groups.notcc.max, 3, "crowd control has its own group")
    T.isnil(set.debuffs.__groups.all, "never shown: never added")
    T.eq(set.cc.__groups.cc.max, 1)
    T.isnil(set.buffs.__groups.mine, "buffs off")
    ns.AuraGroups.Place(set, tile, cfg({ cc = { show = false } }), BOX)
    T.eq(set.debuffs.__groups.all.max, 3)
    T.eq(set.debuffs.__groups.notcc.max, 0)
    T.eq(set.cc.__groups.cc.max, 0)
    ns.AuraGroups.Place(set, tile, cfg({ debuffs = { which = "dispel" }, buffs = { show = true, which = "all" } }), BOX)
    T.eq(set.debuffs.__groups.dispel.max, 3)
    T.eq(set.debuffs.__groups.notcc.max, 0)
    T.eq(set.buffs.__groups.all.max, 4); T.isnil(set.buffs.__groups.mine)
end)

T.test("heals and shields: your class's heals by spell id, every rank; a class without any shows none", function()
    local ns, tile, set = setup()
    stub.units.player = { class = "PRIEST" }
    ns.AuraGroups.Place(set, tile, cfg({ buffs = { show = true, which = "heals" } }), BOX)
    local g = set.buffs.__groups.heals
    T.eq(g.filter, "HELPFUL|PLAYER")
    local ids = g.opts.candidateFilters.includeSpellIDs
    T.truthy(ids[139] and ids[25315], "Renew, rank 1 and the top rank")
    T.truthy(ids[17], "Power Word: Shield")
    T.isnil(ids[1243], "not Fortitude")
    T.eq(g.max, 4); T.isnil(set.buffs.__groups.mine, "only mine never shown: never added")
    ns.Auras.SetBuffsSeen(set.buffs, false)
    T.eq(g.max, 0, "too far to see: off, like only mine")
    ns.Auras.SetBuffsSeen(set.buffs, true)
    T.eq(g.max, 4)
    ns.AuraGroups.Place(set, tile, cfg({ buffs = { show = true, which = "mine" } }), BOX)
    T.eq(g.max, 0); T.eq(set.buffs.__groups.mine.max, 4)

    local ns2, tile2, set2 = setup()
    stub.units.player = { class = "WARRIOR" }
    T.falsy(ns2.AuraGroups.Refused(ns2.AuraGroups.BY_KEY.buffs, "heals"), "the options still list it (one profile, every character)")
    T.falsy(ns2.AuraGroups.Usable(ns2.AuraGroups.BY_KEY.buffs, "heals"))
    ns2.AuraGroups.Place(set2, tile2, cfg({ buffs = { show = true, which = "heals" } }), BOX)
    T.isnil(set2.buffs.__groups.heals)
    T.isnil(set2.buffs.__groups.mine, "never everything a warrior casts (tracking, long buffs)")
    T.isnil(ns2.AuraGroups.ActiveKey(ns2.AuraGroups.BY_KEY.buffs, cfg({ buffs = { show = true, which = "heals" } })))
    ns2.AuraGroups.Place(set2, tile2, cfg({ buffs = { show = true, which = "mine" } }), BOX)
    T.eq(set2.buffs.__groups.mine.max, 4, "Only mine still works when picked")
    T.eq(ns2.AuraGroups.ActiveKey(ns2.AuraGroups.BY_KEY.buffs, cfg({ buffs = { show = true, which = "heals" } }), true),
         "heals", "a preview still shows the row, so it can be seen and placed")
end)

-- What the client would show in the buff row, by the game's rule (tests/aura_rules.lua).
local shows = require("aura_rules")
local MEMBER = { canAssist = true, groupMember = true }
local function shown(c, aura)
    for key, g in pairs(c.__groups) do
        if (g.max or 0) > 0 and shows(g, MEMBER, aura) then return key end
    end
end

T.test("heals and shields never shows tracking or long buffs, whatever the class (a player's report)", function()
    local TRACK = { spellId = 2580, mine = true, duration = 0 }       -- Find Minerals
    local LONG = { spellId = 6673, mine = true, duration = 120 }      -- a shout or blessing of yours
    local RENEW = { spellId = 139, mine = true, duration = 15 }
    for _, class in ipairs({ "PRIEST", "DRUID", "PALADIN", "SHAMAN", "MAGE", "WARRIOR", "ROGUE", "HUNTER", "WARLOCK" }) do
        local ns, tile, set = setup()
        stub.units.player = { class = class }
        ns.AuraGroups.Place(set, tile, cfg({ buffs = { show = true, which = "heals" } }), BOX)
        T.isnil(shown(set.buffs, TRACK), class .. ": no tracking")
        T.isnil(shown(set.buffs, LONG), class .. ": no long buffs")
        local x1 = cfg({ buffs = { show = false } })
        x1.x1 = { show = true, what = "buffs", buffWhich = "heals", spot = "top", grow = "right", size = 14, max = 4,
                  rows = 1, spacing = 2, x = 0, y = 0 }
        ns.AuraGroups.Place(set, tile, x1, BOX)
        local extra = set.extra and set.extra.x1 and set.extra.x1.buffs
        T.isnil(extra and shown(extra, TRACK), class .. ": an added buff group, no tracking either")
    end
    local ns, tile, set = setup()
    stub.units.player = { class = "PRIEST" }
    ns.AuraGroups.Place(set, tile, cfg({ buffs = { show = true, which = "heals" } }), BOX)
    T.eq(shown(set.buffs, RENEW), "heals", "a priest's Renew still shows")
end)

T.test("each group is placed by its spot, grows its way, at its own size", function()
    local ns, tile, set = setup()
    ns.AuraGroups.Place(set, tile, cfg({ debuffs = { spacing = 3 } }), BOX)
    local p, rel, rp, x, y = set.debuffs:GetPoint(1)
    T.eq(p, "BOTTOM"); T.eq(rel, tile); T.eq(rp, "BOTTOM"); T.eq(x, 0); T.eq(y, 2 + 4)
    T.eq(set.debuffs.__anchorPoint, "BOTTOMLEFT")
    T.eq(set.debuffs.__groups.notcc.layout.elementWidth, 13)
    T.eq(set.debuffs.__groups.notcc.layout.elementSpacing, 3)
    p, rel, rp = set.cc:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(rp, "CENTER")
end)

T.test("no settings at all: every group off, nothing errors", function()
    local ns, tile, set = setup()
    ns.AuraGroups.Place(set, tile, nil, BOX)
    T.eq(#set.debuffs.__groupOrder, 0); T.eq(#set.cc.__groupOrder, 0)
    T.eq(#stub.errors, 0)
end)

T.test("a filter the client refuses: its choice falls back, nothing errors", function()
    local ns, tile, set = setup({ before = function()
        stub.refuseAuraFilters = { ["HARMFUL|!CROWD_CONTROL"] = true, ["HARMFUL|CROWD_CONTROL"] = true }
    end })
    T.truthy(ns.Auras.REFUSED["HARMFUL|CROWD_CONTROL"])
    T.truthy(ns.AuraGroups.Refused(ns.AuraGroups.BY_KEY.cc, "cc"))
    ns.AuraGroups.Place(set, tile, cfg(), BOX)
    T.eq(set.debuffs.__groups.all.max, 3, "plain debuffs instead of 'all but crowd control'")
    T.isnil(set.cc.__groups.cc, "never added")
    T.eq(#stub.errors, 0)
end)

T.test("timer numbers on a row under the frame: it drops by their height (they sit on each icon's top)", function()
    local ns, tile, set = setup()
    local box = { w = 72, h = 28, padX = 1, padY = 2 }
    ns.AuraGroups.Place(set, tile, cfg({ debuffs = { spot = "below", timers = false } }), box)
    local y0 = select(5, set.debuffs:GetPoint(1))
    ns.AuraGroups.Place(set, tile, cfg({ debuffs = { spot = "below", timers = true } }), box)
    T.near(select(5, set.debuffs:GetPoint(1)), y0 - ns.Auras.TIME_SIZE.gdebuff * 0.6, 0.01)
    ns.AuraGroups.Place(set, tile, cfg({ debuffs = { spot = "above", timers = true } }), box)
    T.eq(select(5, set.debuffs:GetPoint(1)), ns.Spots.GAP, "above: the numbers face away, nothing moves")
end)

-- A real client method the fake game only no-ops, recorded here so a test can see
-- what a tile's icon does with the mouse.
local function watchMouse()
    stub.Widget.SetMouseClickEnabled = function(self, on) self.__clicks = on end
    stub.Widget.SetMouseMotionEnabled = function(self, on) self.__motion = on end
end

T.test("a tile's icons let clicks and the hover through to the tile (mouseover casting)", function()
    watchMouse()
    local ns, tile, set = setup()
    ns.AuraGroups.Place(set, tile, cfg(), BOX)
    local btn = set.debuffs.__groups.notcc.button
    T.eq(btn.__clicks, false, "a click reaches the tile")
    T.eq(btn.__motion, false, "the hover stays on the tile")
end)

T.test("Tooltip on hover gives an icon the hover back, never the clicks, and is on the container before its buttons", function()
    watchMouse()
    local ns, tile, set = setup()
    ns.AuraGroups.Place(set, tile, cfg({ debuffs = { tooltips = true } }), BOX)
    local btn = set.debuffs.__groups.notcc.button
    T.eq(btn.__motion, true, "built with it on")
    T.eq(btn.__clicks, false)
    ns.AuraGroups.Place(set, tile, cfg(), BOX)
    T.eq(btn.__motion, false, "switched off later")
    T.eq(btn.__clicks, false)
end)

T.test("a group's time and stack sizes and its stack count switch are on its buttons from the start, and follow later", function()
    local ns, tile, set = setup()
    ns.AuraGroups.Place(set, tile, cfg({ debuffs = { timers = true, timeSize = 11, countSize = 13, counts = false } }), BOX)
    local btn = set.debuffs.__groups.notcc.button
    local _, time = btn.__time:GetFont()
    local _, count = btn.__count:GetFont()
    T.eq(time, 11); T.eq(count, 13)
    T.eq(btn.__count:GetAlpha(), 0, "built with stacks off")
    ns.AuraGroups.Place(set, tile, cfg({ debuffs = { timers = true, timeSize = 9, countSize = 12 } }), BOX)
    T.eq(btn.__count:GetAlpha(), 1, "on again")
    _, count = btn.__count:GetFont()
    T.eq(count, 12)
end)

T.test("the party and raid pages list the new text rows on every group", function()
    local DUI = stub.Load({ module = true })
    local O = DUI.Options
    for _, page in ipairs({ "UnitFrames.party", "UnitFrames.raid" }) do
        local keys = {}
        for _, g in ipairs(O.GetPage(page).groups) do
            for _, it in ipairs(g.items or {}) do if it.key then keys[it.key] = true end end
        end
        local p = page == "UnitFrames.party" and "party" or "raid"
        for _, k in ipairs({ "debuffs.timeSize", "debuffs.countSize", "debuffs.counts", "buffs.counts", "cc.timeSize" }) do
            T.truthy(keys[p .. ".auras." .. k], page .. " " .. k)
        end
        T.eq(#O.ValidatePage(O.GetPage(page)), 0)
    end
end)

T.test("a plugin's spell list is one more Filter choice, matched by spell id; debuffs only by ids the game allows", function()
    local ns, tile, set = setup()
    stub.neverSecretAuras = { [57724] = true }
    local me = DaylightUI.API.For("Raidy")
    T.eq(me.AddAuraFilter("walls", { label = "Big defensives", spells = { 871, 498 } }), true)
    T.eq(me.AddAuraFilter("sated", { label = "Sated", what = "debuffs", spells = { 57724, 12345 } }), true)
    T.eq(me.AddAuraFilter("boss", { label = "Boss", what = "debuffs", spells = { 12345 } }), false,
         "no spell the game lets it pick out on a group member")
    T.eq(me.AddAuraFilter("bad", { label = "X" }), false, "no spells")
    stub.neverSecretAuras = {}
    local AG = ns.AuraGroups
    T.truthy(table.concat(AG.BY_KEY.buffs.choices, ","):find("Raidy:walls", 1, true))
    T.isnil(table.concat(AG.BY_KEY.debuffs.choices, ","):find("Raidy:boss", 1, true))
    T.eq(AG.CHOICE_LABELS.buffs["Raidy:walls"], "Big defensives")

    AG.Place(set, tile, cfg({ buffs = { show = true, which = "Raidy:walls" } }), BOX)
    local g = set.buffs.__groups["Raidy:walls"]
    T.eq(g.filter, "HELPFUL"); T.eq(g.max, 4)
    T.eq(shown(set.buffs, { spellId = 871 }), "Raidy:walls")
    T.isnil(shown(set.buffs, { spellId = 1243 }), "not on the list")
    ns.Auras.SetBuffsSeen(set.buffs, false)
    T.eq(g.max, 4, "anyone's buffs: being out of sight changes nothing")
    ns.Auras.SetBuffsSeen(set.buffs, true)

    AG.Place(set, tile, cfg({ debuffs = { which = "Raidy:sated" }, cc = { show = false } }), BOX)
    local d = set.debuffs.__groups["Raidy:sated"]
    T.eq(d.filter, "HARMFUL"); T.eq(d.max, 3)
    T.isnil(d.opts.candidateFilters.includeSpellIDs[12345], "a secret one is left out")
    T.eq(shown(set.debuffs, { spellId = 57724, harmful = true, neverSecret = true }), "Raidy:sated")
    T.eq((AG.ExtraActive({ show = true, what = "buffs", buffWhich = "Raidy:walls" })), AG.BY_KEY.buffs, "extra rows too")

    T.eq(me.AddAuraFilter("hots", { label = "My HoTs", spells = { 774 }, mine = true }), true)
    AG.Place(set, tile, cfg({ buffs = { show = true, which = "Raidy:hots" } }), BOX)
    local h = set.buffs.__groups["Raidy:hots"]
    T.eq(h.filter, "HELPFUL|PLAYER"); T.eq(h.max, 4); T.eq(g.max, 0, "one choice shows at a time")
    ns.Auras.SetBuffsSeen(set.buffs, false)
    T.eq(h.max, 0, "yours only: off out of sight, like Only mine")
end)
