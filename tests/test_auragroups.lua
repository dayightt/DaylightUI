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

T.test("heals and shields: your class's heals by spell id, every rank; a class without any shows only mine", function()
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
    T.eq(set2.buffs.__groups.mine.max, 4, "a warrior gets only mine")
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
