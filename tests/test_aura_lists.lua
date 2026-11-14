local stub = require("stub")
local shows = require("aura_rules")

local function setup()
    local DUI, ns = stub.Load({ module = true })
    stub.spells = stub.spells or {}
    stub.spells[57724] = { name = "Sated" }
    stub.spells[1243] = { name = "Power Word: Fortitude" }
    stub.spells[1244] = { name = "Power Word: Fortitude" }
    stub.spells[589] = { name = "Shadow Word: Pain" }
    stub.spells[774] = { name = "Rejuvenation" }
    stub.units.player = { class = "PRIEST" }
    return DUI, ns
end

local BOX = { w = 72, h = 28, padX = 1, padY = 2, bottomInset = 4 }
local MEMBER = { canAssist = true, groupMember = true }
local ENEMY = { canAssist = false, groupMember = false }

local function groupCfg(over)
    local t = {
        debuffs = { show = true, which = "all", spot = "bottom", grow = "center", size = 13, max = 3, rows = 1, spacing = 2, x = 0, y = 0 },
        cc = { show = false, spot = "center", grow = "center", size = 18, max = 1, rows = 1, spacing = 2, x = 0, y = 0 },
        buffs = { show = true, which = "all", spot = "bottomleft", grow = "right", size = 14, max = 4, rows = 1, spacing = 2, x = 0, y = 0 },
    }
    for g, o in pairs(over or {}) do for k, v in pairs(o) do t[g][k] = v end end
    return t
end

local function tile(ns)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(72, 28)
    return f, ns.AuraGroups.Create(f, "raid1")
end

T.test("two lists to start: Hidden (hide, only Boosted Rest) and Watch list (show only, empty)", function()
    local _, ns = setup()
    local AL = ns.AuraLists
    T.eq(table.concat(AL.All(), ","), "hidden,watch")
    T.eq(AL.ModeOf("hidden"), "hide")
    T.eq(AL.ModeOf("watch"), "only")
    T.eq(AL.Get("hidden").spells, "1229451")
    T.isnil(AL.Ids("watch"))
    local values, order = AL.Choices("hide")
    T.eq(table.concat(order, ","), "none,hidden")
    T.eq(values.hidden, "Hidden")
end)

T.test("adding by id takes every rank seen with that name; removing takes them all off", function()
    local _, ns = setup()
    local AL = ns.AuraLists
    stub.SetAuras("player", "HELPFUL", { { name = "Power Word: Fortitude", spellId = 1244 } })
    T.eq(AL.Add("hidden", "1243"), "Power Word: Fortitude")
    local ids = AL.Ids("hidden")
    T.truthy(ids[1243] and ids[1244], "both ranks")
    local fort
    for _, e in ipairs(AL.Entries("hidden")) do if e.name == "Power Word: Fortitude" then fort = e end end
    T.eq(#fort.ids, 2)
    AL.Remove("hidden", "Power Word: Fortitude")
    T.isnil(AL.Ids("hidden")[1243])
    T.truthy(AL.Ids("hidden")[1229451], "Boosted Rest stays")
end)

T.test("adding by name needs the aura seen, or an id; unknown words say why", function()
    local _, ns = setup()
    local AL = ns.AuraLists
    local name, why = AL.Add("hidden", "Nothing Like This")
    T.isnil(name)
    T.truthy(type(why) == "string")
    T.isnil(AL.Add("hidden", "999999"))
    stub.SetAuras("player", "HARMFUL", { { name = "Sated", spellId = 57724 } })
    T.eq(AL.Add("hidden", "sated"), "Sated", "any case")
    T.truthy(AL.Ids("hidden")[57724])
end)

T.test("a hide list leaves its buffs off party tiles, in place, no reload", function()
    local DUI, ns = setup()
    ns.AuraLists.Delete("hidden")
    local f, set = tile(ns)
    ns.AuraGroups.Place(set, f, groupCfg({ buffs = { hide = "hidden" } }), BOX)
    local g = set.buffs.__groups.all
    T.isnil(g.opts.candidateFilters, "an empty list adds nothing")
    stub.SetAuras("player", "HELPFUL", { { name = "Power Word: Fortitude", spellId = 1243 } })
    ns.AuraLists.Add("hidden", "1243")
    ns.AuraLists.Changed()   -- what OnSettingChanged does for a list path
    T.truthy(set.buffs.__candidateSets >= 1, "changed in place")
    local fort = { spellId = 1243, harmful = false, duration = 1800 }
    local rejuv = { spellId = 774, harmful = false, duration = 12 }
    T.eq(shows(g, MEMBER, fort), false)
    T.eq(shows(g, MEMBER, rejuv), true)
    T.eq(#set.buffs.__groupOrder, 1, "no new group was made")
end)

T.test("a show-only list keeps a buff row to its spells, and narrows heals and shields", function()
    local _, ns = setup()
    stub.units.player = { class = "DRUID" }
    local f, set = tile(ns)
    ns.AuraLists.Add("watch", "774")
    ns.AuraGroups.Place(set, f, groupCfg({ buffs = { which = "heals", only = "watch" } }), BOX)
    local g = set.buffs.__groups.heals
    local inc = g.opts.candidateFilters.includeSpellIDs
    T.truthy(inc[774], "Rejuvenation stays")
    T.isnil(inc[8936], "Regrowth is a heal but not on the list")
end)

T.test("debuffs on your group: a hide list only reaches never-secret spells; boss and duration filters apply", function()
    local _, ns = setup()
    stub.neverSecretAuras[57724] = true
    local f, set = tile(ns)
    ns.AuraLists.Add("hidden", "57724")
    ns.AuraLists.Add("hidden", "589")
    ns.AuraGroups.Place(set, f, groupCfg({ debuffs = { hide = "hidden", only = "watch", boss = true, maxTime = 60 } }), BOX)
    local g = set.debuffs.__groups.all
    local cand = g.opts.candidateFilters
    T.isnil(cand.includeSpellIDs, "no show-only list on friendly debuffs")
    T.eq(cand.isBossAura, true)
    T.eq(cand.maxDuration, 60)
    local sated = { spellId = 57724, harmful = true, duration = 30, neverSecret = true, boss = true }
    local pain = { spellId = 589, harmful = true, duration = 18, boss = true }
    T.eq(shows(g, MEMBER, sated), false, "never secret: hidden")
    T.eq(shows(g, MEMBER, pain), true, "the client won't match it on a friend")
    T.eq(shows(g, MEMBER, { spellId = 1, harmful = true, duration = 18 }), false, "not a boss's")
    T.eq(shows(g, MEMBER, { spellId = 2, harmful = true, duration = 600, boss = true }), false, "too long")
end)

T.test("Boosted Rest is off every debuff row by default: party tiles and your own frame", function()
    local DUI, ns = setup()
    stub.neverSecretAuras[1229451] = true
    local rest = { spellId = 1229451, harmful = true, duration = 3600, neverSecret = true }
    local f, set = tile(ns)
    T.eq(DUI:Get("UnitFrames", "party.auras.debuffs.hide"), "hidden", "party's default pick")
    ns.AuraGroups.Place(set, f, groupCfg({ debuffs = { hide = "hidden" } }), BOX)
    local g = set.debuffs.__groups.all
    T.eq(shows(g, MEMBER, rest), false, "party tile")
    T.eq(shows(g, MEMBER, { spellId = 589, harmful = true, duration = 18 }), true, "other debuffs stay")
    for _, key in ipairs({ "playerAuras", "targetAuras", "focusAuras", "petAuras", "personal.auras" }) do
        T.eq(DUI:Get("UnitFrames", key .. ".debuffHide"), "hidden", key)
    end
    local mine = ns.auras.debuffs.__groups.mine
    T.truthy(mine.opts.candidateFilters.excludeSpellIDs[1229451], "target frame's debuff row")
end)

T.test("target debuffs: a show-only list keeps your DoTs to it on an enemy", function()
    local DUI, ns = setup()
    ns.AuraLists.Add("watch", "589")
    DUI:Set("UnitFrames", "targetAuras.debuffOnly", "watch")
    local set = ns.auras
    local g = set.debuffs.__groups.mine
    T.truthy(g.opts.candidateFilters and g.opts.candidateFilters.includeSpellIDs[589])
    T.eq(shows(g, ENEMY, { spellId = 589, harmful = true, duration = 18, mine = true }), true)
    T.eq(shows(g, ENEMY, { spellId = 772, harmful = true, duration = 18, mine = true }), false)
end)

T.test("a deleted list reads as none; built-in lists are only emptied", function()
    local DUI, ns = setup()
    local AL = ns.AuraLists
    local id = AL.New("PvP", "hide")
    T.eq(AL.ModeOf(id), "hide")
    AL.Add(id, "589")
    T.truthy(AL.Ids(id)[589])
    AL.Delete(id)
    T.isnil(AL.Get(id))
    local _, order = AL.Choices("hide")
    T.eq(table.concat(order, ","), "none,hidden")
    AL.Add("hidden", "589")
    AL.Delete("hidden")
    T.truthy(AL.Get("hidden"), "still there")
    T.isnil(AL.Ids("hidden"))
end)
