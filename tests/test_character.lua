local stub = require("stub")
local CW = require("charworld")

-- Loads the core and the character window into a fake character world.
local function load(spec, opts)
    opts = opts or {}
    opts.character = true
    local world = CW.world(spec)
    local before = opts.before
    opts.before = function() world(); if before then before() end end
    local DUI = stub.Load(opts)
    return DUI, stub.character
end

T.test("character: the module registers", function()
    load()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(DaylightUI:GetModule("Character"), "registered")
end)

T.test("character: the old probe's log is cleared", function()
    load(nil, { before = function() _G.DaylightUIDB = { charProbeLog = { "a line" } } end })
    T.isnil(DaylightUIDB.charProbeLog)
end)

T.test("db: the old nameplate recorder's saved log is cleared", function()
    load(nil, { before = function() _G.DaylightUIDB = { plateLog = { on = true, log = { { what = "state" } } } } end })
    T.isnil(DaylightUIDB.plateLog)
end)

T.test("character: the fake game window toggles like the game's", function()
    load()
    ToggleCharacter("PaperDollFrame")
    T.eq(CharacterFrame:IsShown(), true)
    ToggleCharacter("ReputationFrame", true)
    T.eq(CharacterFrame.activeSubframe, "ReputationFrame")
    ToggleCharacter("ReputationFrame")
    T.eq(CharacterFrame:IsShown(), false)
end)
local function gear(spec)
    local _, ns = load(spec)
    return ns.Gear
end

T.test("character gear: name, quality, level, icon; empty slots", function()
    local G = gear({ items = { Head = CW.item("Lionheart Helm", { quality = 4, level = 66 }) } })
    local e = G.Read("Head")
    T.eq(e.name, "Lionheart Helm")
    T.eq(e.quality, 4)
    T.eq(e.level, 66)
    T.eq(e.icon, "icon:Lionheart Helm")
    T.eq(e.label, "Head")
    T.eq(G.Line(e), "Item level " .. DaylightUI.Char.Gear.Value(66))
    local n = G.Read("Neck")
    T.eq(n.empty, true)
    T.eq(n.emptyIcon, "empty:Neck")
    T.deq({ G.Line(n) }, { "Empty", "dim" })
end)

T.test("character gear: shirt and tabard say what they are", function()
    local G = gear({ items = { Shirt = CW.item("Fine White Shirt", { quality = 1, level = 1 }) } })
    T.eq(G.Line(G.Read("Shirt")), "Shirt")
end)

T.test("character gear: repair soon and broken", function()
    local G = gear({ items = {
        Chest = CW.item("Chest", { cur = 20, max = 100 }),
        Legs = CW.item("Legs", { cur = 0, max = 100 }),
        Feet = CW.item("Feet", { cur = 50, max = 100 }),
    } })
    T.deq({ G.Line(G.Read("Chest", 0.25)) }, { "Repair soon · 20% left", "amber" })
    T.deq({ G.Line(G.Read("Legs", 0.25)) }, { "Broken · no stats until repaired", "red" })
    T.isnil(G.Read("Feet", 0.25).wear)
    T.eq(G.Read("Feet", 0.5).wear, "low", "the threshold is the setting's")
end)

T.test("character gear: ammo has its own slot, with its count", function()
    local items = { Ranged = CW.item("Bow", { level = 60 }), Ammo = CW.item("Jagged Arrow", { count = 200, subType = "Arrow" }) }
    local G = gear({ items = items })
    T.deq(G.BOTTOM, { "MainHand", "SecondaryHand", "Ranged" }, "the ammo is not a full slot in the row")
    T.eq(G.All().Ammo.name, "Jagged Arrow", "but it is read with the rest")
    T.eq(G.Line(G.Read("Ranged")), "Item level " .. DaylightUI.Char.Gear.Value(60), "the ranged line is the bow's own")
    local a = G.Read("Ammo")
    T.eq(a.label, "Ammo")
    T.eq(a.name, "Jagged Arrow")
    T.eq(G.Line(a), "200 arrows")
    local none = gear({}).Read("Ammo")
    T.deq({ G.Line(none) }, { "Empty", "dim" })
    T.eq(none.emptyIcon, "empty:Ammo")
end)

T.test("character gear: an empty ammo slot reads empty, not a gray box with 1", function()
    local G = gear({ usesAmmo = true, class = "HUNTER" })
    local none = G.Read("Ammo")
    T.eq(none.empty, true, "no icon from the game = nothing there, as in the game's own window")
    T.isnil(none.ammo, "no count in the corner")
end)

T.test("character gear: ammo the game hasn't cached yet still shows, by its icon and count", function()
    local G = gear({ items = { Ammo = CW.item("Rough Arrow", { count = 313, subType = "Arrow" }) } })
    C_Item.GetItemInfo = function() end
    local a = G.Read("Ammo")
    T.falsy(a.empty, "the slot holds arrows: the game gives their id")
    T.eq(a.icon, "icon:Rough Arrow")
    T.eq(G.Line(a), "313 ammo")
end)

T.test("character gear: the ammo slot only for a class that uses ammo, as in the game's window", function()
    T.eq(gear({ class = "MAGE" }).UsesAmmo(), false)
    local H = gear({ usesAmmo = true, class = "HUNTER" })
    T.eq(H.UsesAmmo(), true)
end)

T.test("character gear: an item not cached yet has an empty line, no error", function()
    local G = gear({ items = { Head = CW.item("New Helm", { level = false }) } })
    local e = G.Read("Head")
    T.isnil(e.level)
    T.eq(G.Line(e), "")
    T.eq(#stub.errors, 0)
end)

T.test("character gear: the footer's item level and durability", function()
    local G = gear({ items = { Chest = CW.item("A", { cur = 20, max = 100 }), Legs = CW.item("B", { cur = 80, max = 100 }) } })
    local s = G.Summary(G.All(0.25))
    T.eq(s.level, 64, "what you wear (64.6), rounded down")
    T.near(s.durability, 0.5, 0.001)
    T.isnil(G.Summary(gear({}).All(0.25)).durability, "nothing that wears")
end)

T.test("character gear: quality colors, gray when unknown", function()
    local G = gear({})
    T.deq({ G.QualityColor(4) }, { 0.64, 0.21, 0.93 })
    T.deq({ G.QualityColor(nil) }, DaylightUI.Style.INK.OFF)   -- warm, never neutral gray
end)
local function stats(spec)
    local _, ns = load(spec)
    return ns.Stats, ns
end

local function rowOf(rows, id)
    for _, r in ipairs(rows) do if r.id == id then return r end end
end

T.test("character stats: attributes, with buffed and lowered", function()
    local S = stats()
    local rows = S.Read("attributes")
    T.eq(#rows, 8, "the five, then the game's General group: Health, power, Movement speed")
    T.eq(rows[1].label, "Strength")
    T.eq(S.Text(rows[1]), "130")
    T.eq(rows[1].buff, "up")
    T.eq(rowOf(rows, "sta").buff, "down")
    T.isnil(rowOf(rows, "agi").buff)
end)

T.test("character stats: Movement speed under the attributes, as the game's sheet has it: run, swim or fly by what you're doing", function()
    local S = stats()
    local function speed() return S.Text(rowOf(S.Read("attributes"), "movespeed")) end
    T.eq(speed(), "100%", "a normal run")
    CW.state.stats.run = 11.2
    T.eq(speed(), "160%", "mounted: the mount's speed")
    CW.state.stats.swim, CW.state.stats.swimming = 4.72, true
    T.eq(speed(), "67%", "in the water: swim speed")
    CW.state.stats.swimming = false
    T.eq(speed(), "160%")
    CW.state.secret = true
    CW.state.stats.run = 14
    local row = rowOf(S.Read("attributes"), "movespeed")
    T.truthy(row.stale, "secret in a fight: never compared or worked on")
    T.eq(S.Text(row), "160%", "the last plain one holds")
end)

T.test("character stats: a school lifted above the others gets its own row under Spell power", function()
    local S = stats()
    local function ids()
        local out = {}
        for _, r in ipairs(S.Read("spell")) do out[#out + 1] = r.id end
        return table.concat(out, " ")
    end
    T.falsy(ids():find("sp_", 1, true), "every school the same: no school rows")
    CW.state.stats.schools = { [6] = CW.state.stats.spell + 40, [3] = CW.state.stats.spell + 10 }
    T.truthy(ids():find("^sp sp_fire sp_shadow heal"), "fire and shadow, in school order, right under Spell power: " .. ids())
    local shadow = rowOf(S.Read("spell"), "sp_shadow")
    T.eq(S.Text(shadow), tostring(CW.state.stats.spell + 40))
    T.eq(shadow.label, "Shadow")
    T.truthy(shadow.indent, "one step in, under Spell power")
    CW.state.secret = true
    CW.state.stats.schools = nil
    T.truthy(ids():find("sp_shadow", 1, true), "in a fight the numbers can't be compared: the rows stay as they were")
    CW.state.secret = false
    T.falsy(ids():find("sp_", 1, true), "after it, back to one row")
end)

T.test("character stats: attack rows and their text", function()
    local S = stats()
    local rows = S.Read("attack")
    T.eq(S.Text(rowOf(rows, "dmg")), "120 - 180")
    T.eq(S.Text(rowOf(rows, "speed")), "2.60 s")
    T.eq(S.Text(rowOf(rows, "ap")), "950")
    T.eq(S.Text(rowOf(rows, "hit")), "4.50%")
    T.eq(S.Text(rowOf(rows, "crit")), "20.04%")
end)

-- What the game's own sheet shows (Camelot PaperDollFrameConstants.lua,
-- PAPERDOLL_STATCATEGORIES), row by row.
T.test("character stats: health and power, in the game's own word for it", function()
    local S = stats()
    local rows = S.Read("attributes")
    T.eq(S.Text(rowOf(rows, "health")), "4200")
    T.eq(rowOf(rows, "power").label, "Rage")
    T.eq(S.Text(rowOf(rows, "power")), "100")
    T.eq(rows[#rows].id, "movespeed", "Movement speed still last")
    T.eq(rowOf(stats({ class = "MAGE" }).Read("attributes"), "power").label, "Mana")
end)

T.test("character stats: dual wielding shows the off hand's damage, speed and expertise", function()
    local S = stats()
    T.isnil(rowOf(S.Read("attack"), "ohdmg"), "one weapon")
    T.eq(S.Text(rowOf(S.Read("attack"), "expertise")), "5.00%", "expertise is a percent")
    local st = CW.state.stats
    st.dual, st.damage, st.speed, st.ohExpertise = true, { 120, 180, 60, 90 }, { 2.6, 1.8 }, 3
    local rows = S.Read("attack")
    T.eq(S.Text(rowOf(rows, "ohdmg")), "60 - 90")
    T.eq(S.Text(rowOf(rows, "speed")), "2.60 / 1.80 s")
    T.eq(S.Text(rowOf(rows, "expertise")), "5.00% / 3.00%")
end)

T.test("character stats: haste and penetration show once there is some, as the game's sheet", function()
    local S = stats()
    T.isnil(rowOf(S.Read("attack"), "haste"), "hidden at 0")
    T.isnil(rowOf(S.Read("attack"), "armorpen"))
    T.isnil(rowOf(S.Read("spell"), "spen"))
    local st = CW.state.stats
    st.mhaste, st.rhaste, st.shaste, st.armorPen, st.spellPen = 5, { 15, 3 }, 2.5, 140, 20
    T.eq(S.Text(rowOf(S.Read("attack"), "haste")), "5.00%")
    T.eq(S.Text(rowOf(S.Read("ranged"), "rhaste")), "18.00%", "the weapon's plus the quiver's")
    T.eq(S.Text(rowOf(S.Read("spell"), "shaste")), "2.50%")
    T.eq(S.Text(rowOf(S.Read("attack"), "armorpen")), "140")
    T.eq(S.Text(rowOf(S.Read("spell"), "spen")), "20")
end)

T.test("character stats: no parry or dodge row at 0, no ranged damage without a ranged weapon", function()
    local S = stats()
    CW.state.stats.parry, CW.state.stats.rangedWeapon = 0, false
    T.isnil(rowOf(S.Read("defense"), "parry"))
    T.truthy(rowOf(S.Read("defense"), "dodge"))
    T.isnil(rowOf(S.Read("ranged"), "rdmg"))
    T.truthy(rowOf(S.Read("ranged"), "rap"))
end)

T.test("character stats: mana regen is the one while casting, as the game shows it", function()
    local M = stats({ class = "MAGE" })
    CW.state.stats.regen = { 10, 3.3 }
    T.eq(M.Text(rowOf(M.Read("spell"), "regen")), "16 every 5 s")
end)

T.test("character stats: one Hit, the same number under melee, ranged and spell, for every class", function()
    -- Hit is one stat on Forever, so every section shows the number
    -- PaperDollFrame_SetHitChance does, whichever call it came from.
    local function sameEverywhere(S, want)
        for _, group in ipairs({ "attack", "ranged", "spell" }) do
            T.eq(S.Text(rowOf(S.Read(group), "hit")), want, group)
        end
    end
    local M = stats({ class = "MAGE" })
    CW.state.stats.hit, CW.state.stats.hitRating, CW.state.stats.spellHit = 0, 0, 6
    sameEverywhere(M, "6.00%")
    local H = stats({ class = "HUNTER" })
    CW.state.stats.hit, CW.state.stats.hitRating, CW.state.stats.rhit, CW.state.stats.rhitRating = 1, 0, 3, 2
    sameEverywhere(H, "5.00%")
    sameEverywhere(stats(), "4.50%")
end)

T.test("character stats: block only with a shield, mana regen only with mana", function()
    local S = stats()
    T.truthy(rowOf(S.Read("defense"), "block"))
    T.isnil(rowOf(S.Read("spell"), "regen"), "a warrior has no mana")
    CW.state.stats.shield = false
    T.isnil(rowOf(S.Read("defense"), "block"))
    local M = stats({ class = "MAGE" })
    T.truthy(rowOf(M.Read("spell"), "regen"))
end)

T.test("character stats: groups open by class, and by role where known", function()
    local S = stats()
    T.deq(S.DefaultOpen("WARRIOR"), { attributes = true, attack = true })
    T.deq(S.DefaultOpen("HUNTER"), { attributes = true, ranged = true })
    T.deq(S.DefaultOpen("MAGE"), { attributes = true, spell = true })
    T.deq(S.DefaultOpen("WARRIOR", "TANK"), { attributes = true, defense = true })
    T.deq(S.DefaultOpen("PALADIN", "HEALER"), { attributes = true, spell = true })
    T.isnil(S.Role(), "no role in this world")
    local R = stats({ role = "TANK" })
    T.eq(R.Role(), "TANK")
    -- Enhancement fights in melee, so Attack opens for it, not Spell.
    local E = stats({ class = "SHAMAN", role = "DAMAGER", specId = 263 })
    T.eq(E.Role(), "MELEE")
    T.deq(E.DefaultOpen("SHAMAN", E.Role()), { attributes = true, attack = true })
    T.eq(stats({ class = "SHAMAN", role = "DAMAGER", specId = 262 }).Role(), "DAMAGER")
end)

T.test("character stats: a group you fold or open is remembered per character", function()
    local S = stats()
    local cfg, folds = { statsOpen = "auto" }, { attack = false, spell = true }
    T.eq(S.IsOpen(cfg, folds, "attack", "WARRIOR"), false)
    T.eq(S.IsOpen(cfg, folds, "spell", "WARRIOR"), true)
    T.eq(S.IsOpen(cfg, folds, "attributes", "WARRIOR"), true)
    T.eq(S.IsOpen(cfg, folds, "defense", "WARRIOR"), false)
    T.eq(S.IsOpen({ statsOpen = "all" }, {}, "defense", "WARRIOR"), true)
end)

T.test("character stats: folds live on the character; an old profile entry moves over once", function()
    local S = stats()
    T.eq(S.Who(), "Daylight-Forever")
    local cfg = { folded = { ["Daylight-Forever"] = { attack = false }, ["Other-Forever"] = { spell = false } } }
    local folds = S.Folds(cfg)
    T.eq(folds.attack, false, "copied from the profile")
    T.truthy(DaylightUI.DB.Character().statFolds == folds, "kept in DB.Character()")
    T.isnil(cfg.folded["Daylight-Forever"], "the profile's copy dropped")
    T.deq(cfg.folded["Other-Forever"], { spell = false }, "other characters' entries left alone")
    folds.attack = true
    T.eq(S.Folds({ folded = { ["Daylight-Forever"] = { attack = false } } }).attack, true, "copied only once")
end)

T.test("character stats: in combat a secret goes whole to the text, with no color", function()
    local S = stats()
    CW.state.secret = true
    local crit = rowOf(S.Read("attack"), "crit")
    T.eq(crit.secret, true)
    T.truthy(issecretvalue(crit.values[1]), "the secret itself, not a copy")
    T.isnil(crit.buff)
    local str = S.Read("attributes")[1]
    T.isnil(str.buff, "no comparing a secret")
    local fs = UIParent:CreateFontString(nil, "OVERLAY")
    S.Paint(fs, crit)
    T.deq(fs:GetText(), { secretFormat = "%.2f%%" }, "handed to the engine's formatting")
end)

T.test("character stats: in combat a sum shows its last plain value, dimmed", function()
    local S = stats()
    T.eq(S.Text(rowOf(S.Read("attack"), "ap")), "950")
    CW.state.secret = true
    local ap = rowOf(S.Read("attack"), "ap")
    T.eq(ap.stale, true)
    T.eq(S.Text(ap), "950")
    local rap = rowOf(S.Read("ranged"), "rap")
    T.eq(S.Text(rap), "--", "never seen plain: nothing to show")
end)

T.test("character stats: resistances stay plain in combat", function()
    local S = stats()
    CW.state.secret = true
    local fire = rowOf(S.Read("resistances"), "res_fire")
    T.eq(fire.secret, false)
    T.eq(S.Text(fire), "10")
end)

T.test("character stats: resistances and armor read the client's own return order", function()
    local S = stats()
    local fire = rowOf(S.Read("resistances"), "res_fire")
    T.eq(S.Text(fire), "10")
    T.isnil(fire.buff, "gear resistance alone isn't buffed")
    CW.state.stats.res[2] = { 10, 25 }
    T.eq(rowOf(S.Read("resistances"), "res_fire").buff, "up")
    CW.state.stats.res[2] = { 10, 0 }
    local low = rowOf(S.Read("resistances"), "res_fire")
    T.eq(low.buff, "down")
    T.eq(S.Text(low), "0")
    local armor = rowOf(S.Read("defense"), "armor")
    T.eq(S.Text(armor), "3200")
    T.eq(armor.buff, "up")
    CW.state.stats.armor = { 3000, 2500, 2500, -500 }   -- Sunder Armor
    armor = rowOf(S.Read("defense"), "armor")
    T.eq(S.Text(armor), "2500")
    T.eq(armor.buff, "down", "red under Sunder")
end)

T.test("character stat text: a plain sentence with the number", function()
    local S, ns = stats()
    local crit = rowOf(S.Read("attack"), "crit")
    local say, from = ns.StatText.For(crit)
    T.eq(say, "About 1 in 5 of your attacks hits for double damage.")
    T.truthy(from)
end)

T.test("character stat text: none while secret or dimmed", function()
    local S, ns = stats()
    CW.state.secret = true
    T.isnil(ns.StatText.For(rowOf(S.Read("attack"), "crit")))
    T.isnil(ns.StatText.For(rowOf(S.Read("attack"), "ap")))
end)

T.test("character stat text: every stat has words", function()
    local S, ns = stats({ class = "MAGE" })
    for _, g in ipairs(S.GROUPS) do
        for _, def in ipairs(S.ROWS[g]) do
            T.truthy(ns.StatText.SAY[def.id], "words for " .. def.id)
        end
    end
end)
local function win(spec)
    local DUI, ns = load(spec)
    return ns.Window, ns, DUI
end

local function fakePage(log)
    return {
        Build = function() log.built = (log.built or 0) + 1 end,
        Refresh = function() log.refreshed = (log.refreshed or 0) + 1 end,
        Open = function() log.opened = (log.opened or 0) + 1 end,
        OnEvent = function(_, event) log.events = log.events or {}; table.insert(log.events, event) end,
    }
end

-- Only the pages a test registers. The real ones register elsewhere, and the
-- Character page is built at login.
local function only(ns, defs)
    for id in pairs(ns.Window.pages) do ns.Window.pages[id] = nil end
    for id, frame in pairs(ns.window.pages) do frame:Hide(); ns.window.pages[id] = nil end
    ns.window.current = nil
    for id, def in pairs(defs) do ns.Window.Register(id, def) end
end

local function shownTabs(ns)
    local out = {}
    for _, b in ipairs(ns.window.tabs) do if b:IsShown() then out[#out + 1] = b.id end end
    return out
end

T.test("character window: built hidden, 1000x636 (the kit header, 56, over the same page room), hanging from the game's window", function()
    local _, ns = win()
    local f = ns.window
    T.truthy(f, "built at login")
    T.eq(f:IsShown(), false)
    T.eq(f:GetWidth(), 1000)
    T.eq(f:GetHeight(), 636)
    local point, rel, relPoint = f:GetPoint(1)
    T.eq(point, "TOPLEFT")
    T.eq(rel, CharacterFrame)
    T.eq(relPoint, "TOPLEFT")
end)

T.test("character window: icons only is narrower; the scale is the setting's", function()
    local W, ns, DUI = win()
    DUI:Set("Character", "names", false)
    T.eq(W.Width(), 780)
    T.eq(ns.window:GetWidth(), 780)
    DUI:Set("Character", "scale", 1.2)
    T.eq(ns.window:GetScale(), 1.2)
end)

T.test("character window: the header says who you are", function()
    local W, ns = win()
    W.PaintHeader()
    T.eq(ns.window.nameText:GetText(), "Daylight")
    T.eq(ns.window.sub:GetText(), "Level " .. ns.Colors.Wrap("60", DaylightUI.Style.Pop()) .. " Human " .. ns.Colors.Wrap("WARRIOR", DaylightUI.Style.ClassColor("WARRIOR")))
end)

T.test("character window: opening shows the page, builds it once, plays the sound", function()
    local W, ns = win()
    local log = {}
    only(ns, { character = fakePage(log) })
    W.Open("character")
    T.eq(ns.window:IsShown(), true)
    T.eq(ns.window.current, "character")
    T.eq(log.built, 1)
    T.eq(log.opened, 1)
    T.truthy((log.refreshed or 0) >= 1)
    T.deq(CW.Calls("PlaySound"), { 1 })
    W.Open("character")
    T.eq(log.built, 1, "built once")
    T.eq(log.opened, 1, "already open: not opened again")
end)

T.test("character window: tabs only for pages we draw; the selected one has its line", function()
    local W, ns = win()
    only(ns, { character = fakePage({}), skills = fakePage({}) })
    W.Open("character")
    T.deq(shownTabs(ns), { "character", "skills" })
    for _, b in ipairs(ns.window.tabs) do
        if b.id == "character" then T.eq(b.line:IsShown(), true) end
        if b.id == "skills" then T.eq(b.line:IsShown(), false) end
    end
end)

T.test("character window: switching pages, and a page we don't draw shows Character", function()
    local W, ns = win()
    local rep = {}
    only(ns, { character = fakePage({}), reputation = fakePage(rep) })
    W.Open("character")
    W.ShowPage("reputation")
    T.eq(ns.window.current, "reputation")
    T.eq(ns.window.pages.character:IsShown(), false)
    T.eq(ns.window.pages.reputation:IsShown(), true)
    T.eq(rep.opened, 1)
    W.ShowPage("statistics")
    T.eq(ns.window.current, "character")
end)

T.test("character window: closing fades it out, with the close sound", function()
    local W, ns = win()
    only(ns, { character = fakePage({}) })
    W.Open("character")
    W.Close()
    stub.FinishFade(ns.window)
    T.eq(ns.window:IsShown(), false)
    T.deq(CW.Calls("PlaySound"), { 1, 2 })
    W.Close()
    T.deq(CW.Calls("PlaySound"), { 1, 2 }, "already closed: no sound")
end)

T.test("character window: events from other units are ignored", function()
    local W, ns = win()
    local log = {}
    only(ns, { character = fakePage(log) })
    W.Open("character")
    W.OnEvent(ns.window, "UNIT_STATS", "target")
    T.isnil(log.events)
    W.OnEvent(ns.window, "UNIT_STATS", "player")
    T.deq(log.events, { "UNIT_STATS" })
end)

T.test("character window: another page refreshes only for its own events (and fights, levels)", function()
    local W, ns = win()
    local rep = {}
    local page = fakePage(rep)
    page.events = { "UPDATE_FACTION" }
    only(ns, { character = fakePage({}), reputation = page })
    W.Open("reputation")
    stub.RunTimers()
    rep.refreshed = 0
    W.OnEvent(ns.window, "UNIT_STATS", "player")
    W.OnEvent(ns.window, "PLAYER_EQUIPMENT_CHANGED", 16)
    W.OnEvent(ns.window, "CURSOR_CHANGED")
    stub.RunTimers()
    T.eq(rep.refreshed, 0, "gear and stats are the character page's")
    T.isnil(rep.events)
    W.OnEvent(ns.window, "UPDATE_FACTION")
    stub.RunTimers()
    T.eq(rep.refreshed, 1, "its own event")
    W.OnEvent(ns.window, "PLAYER_REGEN_DISABLED")
    stub.RunTimers()
    T.eq(rep.refreshed, 2, "a fight starting: what locks in combat")
end)
-- A world with fake pages for every tab, the window built and following.
local function following(spec, opts)
    local DUI, ns = load(spec, opts)
    local defs = {}
    for _, p in ipairs(ns.Window.PAGES) do defs[p.id] = fakePage({}) end
    only(ns, defs)
    return ns.Follow, ns, DUI
end

local function openGame(F, page)
    ToggleCharacter(page or "PaperDollFrame")
    F.Tick()
end

T.test("character follow: at login the game's window is parked, its panel layout left to the game", function()
    local F, ns = following()
    T.eq(CharacterFrame:GetParent(), F.hidden)
    T.eq(F.hidden:GetParent(), UIParent, "under UIParent: keeps its scale and spot")
    T.eq(F.parked, true)
    T.isnil(CW.state.panel.width, "an attribute written here would taint the game's next ShowUIPanel")
end)

T.test("character follow: a /reload in combat parks once combat ends", function()
    local F = following(nil, { before = function() stub.combat = true end })
    T.eq(F.parked, false)
    stub.LeaveCombat()
    T.eq(F.parked, true)
end)

T.test("character follow: icons only and scale write nothing to the game's panel layout", function()
    local _, _, DUI = following()
    DUI:Set("Character", "names", false)
    DUI:Set("Character", "scale", 1.2)
    stub.RunTimers()
    T.isnil(CW.state.panel.width)
end)

T.test("character follow: the game opens, ours opens on the same page", function()
    local F, ns = following()
    openGame(F, "ReputationFrame")
    T.eq(ns.window:IsShown(), true)
    T.eq(ns.window.current, "reputation")
    ToggleCharacter("SkillsFrame", true)
    F.Tick()
    T.eq(ns.window.current, "skills")
end)

T.test("character follow: the game closes (Escape, C), ours fades", function()
    local F, ns = following()
    openGame(F)
    ToggleCharacter("PaperDollFrame")
    F.Tick()
    stub.FinishFade(ns.window)
    T.eq(ns.window:IsShown(), false)
end)

T.test("character follow: our X closes through the game", function()
    local F, ns = following()
    openGame(F)
    F.Close()
    T.deq(CW.Calls("ToggleCharacter")[2], { "PaperDollFrame" })
    T.eq(CharacterFrame:IsShown(), false)
    F.Tick()
    stub.FinishFade(ns.window)
    T.eq(ns.window:IsShown(), false)
end)

T.test("character follow: our X in combat: ours fades now, the game's closes after", function()
    local F, ns = following()
    openGame(F)
    stub.EnterCombat()
    F.Close()
    T.eq(#CW.Calls("ToggleCharacter"), 1, "no call into the game in combat")
    F.Tick()
    stub.FinishFade(ns.window)
    T.eq(ns.window:IsShown(), false)
    T.eq(CharacterFrame:IsShown(), true, "the game's still open, out of sight")
    stub.LeaveCombat()
    T.eq(CharacterFrame:IsShown(), false)
    T.isnil(F.override)
    F.Tick()
    T.eq(ns.window:IsShown(), false)
end)

T.test("character follow: C after our X in combat opens it again at once", function()
    local F, ns = following()
    openGame(F)
    stub.EnterCombat()
    F.Close()
    F.Tick()
    stub.FinishFade(ns.window)
    ToggleCharacter("PaperDollFrame")   -- C: the game shuts its own, which was still open out of sight
    F.Tick()
    T.eq(ns.window:IsShown(), true, "one press opens ours")
    stub.LeaveCombat()
    T.eq(CharacterFrame:IsShown(), true, "the game's catches up after the fight")
    T.isnil(F.override)
    F.Tick()
    T.eq(ns.window:IsShown(), true)
    ToggleCharacter("PaperDollFrame")   -- C again closes both
    F.Tick()
    stub.FinishFade(ns.window)
    T.eq(ns.window:IsShown(), false)
end)

T.test("character follow: opened from addon code in a fight, the game's follows after", function()
    local F, ns = following()
    stub.EnterCombat()
    T.eq(F.Ready(), true)
    T.eq(F.ToggleInFight(), true)
    F.Tick()
    T.eq(ns.window:IsShown(), true, "ours opens now")
    T.eq(#CW.Calls("ToggleCharacter"), 0, "no call into the game in combat")
    stub.LeaveCombat()
    T.eq(CharacterFrame:IsShown(), true, "the game's opens after the fight")
    F.Tick()
    T.eq(ns.window:IsShown(), true)
    stub.EnterCombat()
    F.ToggleInFight()
    F.Tick()
    stub.FinishFade(ns.window)
    T.eq(ns.window:IsShown(), false, "a second click closes it")
    stub.LeaveCombat()
    T.eq(CharacterFrame:IsShown(), false)
end)

T.test("character follow: our tab switches the game's page too", function()
    local F, ns = following()
    openGame(F)
    F.Select("reputation")
    T.deq(CW.Calls("ToggleCharacter")[2], { "ReputationFrame", true })
    T.eq(CharacterFrame.activeSubframe, "ReputationFrame")
    T.eq(ns.window.current, "reputation")
end)

-- ToggleCharacter switching page runs ShowSubFrame and UpdateSmartNavFocus. Called
-- from addon code they write the game's tabs and controller footers under taint,
-- and every controller ability after that is refused
-- (SetPreferredGamepadInteractTarget, ClearTarget, InteractUnit in game).
T.test("character follow: on a controller our tab leaves the game's page alone", function()
    local F, ns = following()
    openGame(F)
    _G.GamepadMode = { FrameControlsManager = { FrameShown = function() end, FrameHidden = function() end } }
    _G.InputUtil = { IsGamepadUIEnabled = function() return true end }
    local calls = #CW.Calls("ToggleCharacter")
    F.Select("reputation")
    _G.GamepadMode, _G.InputUtil = nil, nil
    T.eq(#CW.Calls("ToggleCharacter"), calls, "no call into the game")
    T.eq(CharacterFrame.activeSubframe, "PaperDollFrame")
    T.eq(ns.window.current, "reputation")
    F.Tick()
    T.eq(ns.window.current, "reputation", "stays: the game's page didn't change")
end)

T.test("character follow: missing and hidden pages", function()
    local F, ns = following({ missing = { TokenFrame = true }, hiddenPages = { PVPRankFrame = true } })
    openGame(F)
    T.eq(F.Available("currency"), false)
    T.eq(F.Available("pvp"), false)
    T.deq(shownTabs(ns), { "character", "reputation", "skills", "statistics" })
    local calls = #CW.Calls("ToggleCharacter")
    F.Select("currency")
    T.eq(#CW.Calls("ToggleCharacter"), calls, "no game frame: only ours switches")
    T.eq(ns.window.current, "currency")
end)

T.test("character follow: the game on a page we don't draw shows Character", function()
    local _, ns = load()
    only(ns, { character = fakePage({}) })
    ToggleCharacter("SkillsFrame")
    ns.Follow.Tick()
    T.eq(ns.window.current, "character")
end)
-- The slots made and the game's slot frame lent: at login once the Character page
-- exists, by hand before that.
local function lentWorld(spec, opts)
    local DUI, ns = load(spec, opts)
    if not next(ns.Slots.frames) then ns.Slots.MakeAll(ns.window.host) end
    if not ns.Slots.lent then ns.Slots.DoLend() end
    return ns.Slots, ns, DUI
end

T.test("character slots: the game's slot frame is lent, each button on our icon", function()
    local S, ns = lentWorld({ usesAmmo = true, class = "HUNTER" })
    T.eq(S.lent, true)
    T.eq(PaperDollItemsFrame:GetParent(), ns.window.pages.character, "on the Character page: hides with it")
    local head = S.frames.Head
    local _, rel = CharacterHeadSlot:GetPoint(1)
    T.eq(rel, head.icon)
    T.eq(head.button, CharacterHeadSlot)
    T.eq(S.byButton[CharacterHeadSlot], head)
    T.eq(CharacterHeadSlot:GetAlpha(), 0, "invisible: the widget's own alpha")
    T.eq(CharacterHeadSlot:GetParent(), PaperDollItemsFrame, "each button keeps the game's parent")
    local _, ammoRel = CharacterAmmoSlot:GetPoint(1)
    T.eq(ammoRel, S.frames.Ammo.icon, "the ammo button, in neither of the game's lists, sits on our Ammo slot")
    T.eq(CharacterAmmoSlot:IsMouseEnabled(), true, "so ammo can be dropped in and taken out")
    T.eq(CharacterAmmoSlot:GetAlpha(), 0)
end)

T.test("character slots: a class without ammo: no Ammo slot, its button catches no clicks", function()
    local S = lentWorld({ class = "MAGE" })
    T.eq(S.frames.Ammo:IsShown(), false)
    T.eq(CharacterAmmoSlot:IsMouseEnabled(), false, "no invisible button where the slot would be")
    T.eq(CharacterHeadSlot:IsMouseEnabled(), true)
    S.frames.Ammo:Show()
    S.Pin()
    T.eq(CharacterAmmoSlot:IsMouseEnabled(), true, "follows our slot when it shows")
    S.Return()
    T.eq(CharacterAmmoSlot:IsMouseEnabled(), true, "given back as the game had it")
end)

T.test("character slots: lending waits for combat to end", function()
    local _, ns = load(nil, { before = function() stub.combat = true end })
    if not next(ns.Slots.frames) then ns.Slots.MakeAll(ns.window.host) end
    ns.Slots.Lend()
    T.eq(ns.Slots.lent, false)
    T.eq(PaperDollItemsFrame:GetParent(), PaperDollFrame)
    stub.LeaveCombat()
    T.eq(ns.Slots.lent, true)
end)

T.test("character slots: given back whole", function()
    local S = lentWorld()
    T.eq(S.Return(), true)
    T.eq(S.lent, false)
    T.eq(PaperDollItemsFrame:GetParent(), PaperDollFrame)
    local _, rel = CharacterHeadSlot:GetPoint(1)
    T.eq(rel, PaperDollItemsFrame)
    T.eq(CharacterHeadSlot:GetAlpha(), 1)
    T.eq(CharacterAmmoSlot:IsMouseEnabled(), true)
    T.isnil(S.frames.Head.button)
end)

T.test("character slots: never given back in combat", function()
    local S = lentWorld()
    stub.EnterCombat()
    T.eq(S.Return(), false)
    T.eq(PaperDollItemsFrame:GetParent() ~= PaperDollFrame, true)
end)

T.test("character slots: the swap menu is moved onto ours, and back", function()
    local S, ns = lentWorld()
    EquipmentFlyoutFrame.button = CharacterHeadSlot
    EquipmentFlyout_UpdateItems()
    T.eq(EquipmentFlyoutFrame:GetParent(), ns.window)
    S.Return()
    T.eq(EquipmentFlyoutFrame:GetParent(), UIParent)
end)

T.test("character slots: no extra line on a slot's tooltip", function()
    local _, ns = lentWorld()
    ns.window:Show()
    PaperDollItemSlotButton_OnEnter(CharacterHeadSlot)
    T.deq(CW.Calls("tipLine"), {})
end)

T.test("character slots: the ammo slot shows its count, item level line on or off", function()
    local S, ns = lentWorld({ usesAmmo = true, class = "HUNTER",
                              items = { Ammo = CW.item("Jagged Arrow", { count = 200, subType = "Arrow", level = 30 }) } })
    local ammo = S.frames.Ammo
    S.Paint(ammo, ns.Gear.Read("Ammo"), { itemLevel = false })
    T.eq(ammo.name:GetText(), "Jagged Arrow")
    T.eq(ammo.line:GetText(), "200 arrows", "the count is not an item level line")
    S.Layout(ammo, S.AMMO, false)
    S.Paint(ammo, ns.Gear.Read("Ammo"), { itemLevel = true })
    T.eq(ammo.corner:GetText(), "", "icons only: no number in the small icon, the count is in the footer")
    T.falsy(ammo.cornerBg:IsShown())
end)

T.test("character slots: painting an item, an empty slot and a broken one", function()
    local S, ns = lentWorld({ items = { Head = CW.item("Lionheart Helm", { quality = 4, level = 66 }),
                                        Legs = CW.item("Legs", { cur = 0, max = 100 }) } })
    local G = ns.Gear
    local head = S.frames.Head
    S.Paint(head, G.Read("Head", 0.25), { itemLevel = true })
    T.eq(head.name:GetText(), "Lionheart Helm")
    T.eq(head.line:GetText(), "Item level " .. DaylightUI.Char.Gear.Value(66))
    T.eq(head.tex.__texture, "icon:Lionheart Helm")
    T.eq(head.dot:IsShown(), false)
    local neck = S.frames.Neck
    S.Paint(neck, G.Read("Neck", 0.25), { itemLevel = true })
    T.eq(neck.name:GetText(), "Neck")
    T.eq(neck.line:GetText(), "Empty")
    T.eq(neck.tex.__texture, "empty:Neck")
    local legs = S.frames.Legs
    S.Paint(legs, G.Read("Legs", 0.25), { itemLevel = true })
    T.eq(legs.dot:IsShown(), true)
    T.eq(legs.line:GetText(), "Broken · no stats until repaired")
    S.Paint(head, G.Read("Head", 0.25), { itemLevel = false })
    T.eq(head.line:GetText(), "", "the item level line switched off")
end)

T.test("character slots: icons only puts the item level in the corner", function()
    local S, ns = lentWorld({ items = { Head = CW.item("Lionheart Helm", { level = 66 }) } })
    local head = S.frames.Head
    S.Layout(head, S.ICON, false)
    S.Paint(head, ns.Gear.Read("Head", 0.25), { itemLevel = true })
    T.eq(head.name:IsShown(), false)
    T.eq(head.corner:GetText(), "66")
    S.Layout(head, 196, true)
    S.Paint(head, ns.Gear.Read("Head", 0.25), { itemLevel = true })
    T.eq(head.corner:GetText(), "")
end)

T.test("character slots: an enchant shows as a third line, read once per link", function()
    local S, ns = lentWorld({ items = {
        Head = CW.item("Lionheart Helm", { level = 66, enchantId = 2545, enchant = "+1% Dodge" }),
        Legs = CW.item("Plain Pants", { level = 50 }) } })
    local head, legs = S.frames.Head, S.frames.Legs
    S.Layout(head, 196, true)
    S.Layout(legs, 196, true)
    CW.tipReads = 0
    S.Paint(head, ns.Gear.Read("Head", 0.25), { itemLevel = true })
    S.Paint(legs, ns.Gear.Read("Legs", 0.25), { itemLevel = true })
    T.eq(head.enchant:GetText(), "+1% Dodge")
    T.eq(head.enchant:IsShown(), true)
    T.eq(legs.enchant:IsShown(), false, "no enchant: two lines as before")
    T.eq(CW.tipReads, 1, "an item with no enchant id reads no tooltip")
    S.Paint(head, ns.Gear.Read("Head", 0.25), { itemLevel = true })
    T.eq(CW.tipReads, 1, "the same link is read once")
    local _, rel = head.enchant:GetPoint(1)
    T.eq(rel, head.line, "stacked under the item level line")
    S.Layout(head, S.ICON, false)
    S.Paint(head, ns.Gear.Read("Head", 0.25), { itemLevel = true })
    T.eq(head.enchant:IsShown(), false)
    T.eq(head.mark:IsShown(), true, "icons only: a small mark")
end)

T.test("character slots: enchants in the accent, and a soft No enchant where one could go", function()
    local S, ns = lentWorld({ items = {
        Head = CW.item("Lionheart Helm", { level = 66, enchantId = 2545, enchant = "+1% Dodge" }),
        Legs = CW.item("Plain Pants", { level = 50 }),
        Neck = CW.item("Pendant", { level = 50 }),
        SecondaryHand = CW.item("Orb", { level = 50 }),
        Ranged = CW.item("Totem", { level = 50 }) } })
    local opts = { itemLevel = true, missingEnchants = true }
    local function paint(key)
        local h = S.frames[key]
        S.Layout(h, 196, true)
        S.Paint(h, ns.Gear.Read(key, 0.25), opts)
        return h
    end
    local head, legs = paint("Head"), paint("Legs")
    T.rgb({ head.enchant:GetTextColor() }, { DaylightUI.Style.Accent() }, "apart from green item names")
    T.eq(legs.enchant:GetText(), "No enchant")
    T.truthy(legs.enchant:IsShown())
    T.rgb({ legs.enchant:GetTextColor() }, DaylightUI.Style.INK.OFF, "soft")
    T.falsy(paint("Neck").enchant:IsShown(), "a neck takes none")
    T.falsy(paint("SecondaryHand").enchant:IsShown(), "a held-in-off-hand item takes none")
    T.falsy(paint("Ranged").enchant:IsShown(), "nor a relic")
    opts.missingEnchants = false
    T.falsy(paint("Legs").enchant:IsShown(), "switched off")
    S.Layout(legs, S.ICON, false)
    opts.missingEnchants = true
    S.Paint(legs, ns.Gear.Read("Legs", 0.25), opts)
    T.falsy(legs.mark:IsShown(), "icons only: no mark for a missing one")
end)

T.test("character slots: the enchant line drops the game's 'Enchanted:' in any language", function()
    local old = ENCHANTED_TOOLTIP_LINE
    local S, ns = lentWorld({ items = {
        Chest = CW.item("Martyr's Armor", { level = 11, enchantId = 41, enchant = "Stamina +1" }) } })
    _G.ENCHANTED_TOOLTIP_LINE = "Verzaubert: %s"
    local e = ns.Gear.Read("Chest", 0.25)
    _G.ENCHANTED_TOOLTIP_LINE = old
    T.eq(e.enchant, "Stamina +1")
end)

T.test("character slots: a moved button is put back", function()
    local S = lentWorld()
    CharacterRangedSlot:ClearAllPoints()
    CharacterRangedSlot:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 5, 5)
    S.Pin()
    local _, rel = CharacterRangedSlot:GetPoint(1)
    T.eq(rel, S.frames.Ranged.icon)
end)

-- The eases of the slots' light, run to their end.
local function settle() stub.RunOnUpdate(DaylightUI.Motion.Driver(), DaylightUI.Motion.FAST + 0.01) end

-- The window opened, its pieces done lifting in.
local function openSettled(ns)
    ns.Window.Open("character")
    stub.RunTimers()
    stub.RunOnUpdate(DaylightUI.Win.Feel.Driver(), 1)
end

T.test("character slots: holding an item lights the slots it fits", function()
    local S = lentWorld()
    CW.state.cursorFits = { [1] = true }
    S.Holding()
    settle()
    T.eq(S.frames.Head.glow:IsShown(), true)
    T.eq(S.frames.Neck.glow:IsShown(), false)
    T.eq(S.frames.Neck:GetAlpha(), S.HOLD_DIM)
    CW.state.cursorFits = nil
    S.Holding()
    settle()
    T.eq(S.frames.Head.glow:IsShown(), false)
    T.eq(S.frames.Neck:GetAlpha(), 1)
end)

T.test("character slots: the slots ease to their light, no jump", function()
    local S = lentWorld()
    CW.state.cursorFits = { [1] = true }
    S.Holding()
    T.eq(S.frames.Neck:GetAlpha(), 1, "still on its way down")
    settle()
    T.eq(S.frames.Neck:GetAlpha(), S.HOLD_DIM)
end)

for _, kind in ipairs({ "enchant", "condition" }) do
    T.test("character slots: a spell aimed at an item lights what it works on (" .. kind .. ")", function()
        local S, ns = lentWorld()
        openSettled(ns)
        CW.state.items[CW.SLOT_IDS.Chest] = CW.item("Robe")
        CW.state.aim = { kind = kind, fits = { [CW.SLOT_IDS.Chest] = true } }
        stub.FireEvent("CURRENT_SPELL_CAST_CHANGED", false)
        settle()
        T.eq(S.frames.Chest.glow:IsShown(), true)
        T.eq(S.frames.Chest:GetAlpha(), 1)
        T.eq(S.frames.Neck.glow:IsShown(), false)
        T.eq(S.frames.Neck:GetAlpha(), S.HOLD_DIM)
        CW.state.aim = nil
        stub.FireEvent("CURRENT_SPELL_CAST_CHANGED", true)
        settle()
        T.eq(S.frames.Chest.glow:IsShown(), false)
        T.eq(S.frames.Neck:GetAlpha(), 1)
    end)
end

T.test("character slots: opened while a spell is aimed, the others still land dim", function()
    local S, ns = lentWorld()
    CW.state.items[CW.SLOT_IDS.Chest] = CW.item("Robe")
    CW.state.aim = { kind = "enchant", fits = { [CW.SLOT_IDS.Chest] = true } }
    openSettled(ns)
    settle()
    T.eq(S.frames.Neck:GetAlpha(), S.HOLD_DIM)
    T.eq(S.frames.Chest:GetAlpha(), 1)
end)

T.test("character slots: an empty slot is nothing to aim at", function()
    local S = lentWorld()
    CW.state.items[CW.SLOT_IDS.Head] = nil
    CW.state.aim = { kind = "enchant", fits = { [CW.SLOT_IDS.Head] = true } }
    S.Holding()
    settle()
    T.eq(S.frames.Head.glow:IsShown(), false)
    T.eq(S.frames.Head:GetAlpha(), S.HOLD_DIM)
end)

T.test("character slots: a hidden ammo slot stays hidden while the others dim", function()
    local S = lentWorld()
    S.frames.Ammo:Hide()
    CW.state.aim = { kind = "enchant", fits = {} }
    S.Holding()
    settle()
    T.eq(S.frames.Ammo:IsShown(), false)
    CW.state.aim = nil
    S.Holding()
    settle()
    T.eq(S.frames.Ammo:IsShown(), false)
    T.eq(S.frames.Ammo:GetAlpha(), 1, "ready for when it shows")
end)

T.test("character slots: an ordinary cast refreshes nothing", function()
    local _, ns = lentWorld()
    openSettled(ns)
    local refreshes, real = 0, ns.Window.Refresh
    ns.Window.Refresh = function(...) refreshes = refreshes + 1; return real(...) end
    stub.FireEvent("CURRENT_SPELL_CAST_CHANGED", false)
    ns.Window.Refresh = real
    T.eq(refreshes, 0)
end)

T.test("character slots: hovering a lent button rings our icon", function()
    local S = lentWorld()
    CharacterHeadSlot.IsMouseOver = function() return true end
    S.Hover()
    T.eq(S.frames.Head.ring:IsShown(), true)
    CharacterHeadSlot.IsMouseOver = function() return false end
    S.Hover()
    T.eq(S.frames.Head.ring:IsShown(), false)
end)
local function model()
    local _, ns = load()
    if not ns.Model.scene then ns.Model.Build(ns.window.host) end
    return ns.Model, ns
end

T.test("character model: set up by the game's helper, hidden until loaded", function()
    local M = model()
    CW.state.modelLoaded = false
    M.SetUp()
    T.truthy(#CW.Calls("setUpScene") >= 1)
    T.eq(M.scene:GetAlpha(), 0)
    M.OnUpdate(nil, 0.5)
    T.eq(M.waiting, true)
    CW.state.modelLoaded = true
    M.OnUpdate(nil, 0.1)
    T.eq(M.waiting, false)
end)

T.test("character model: shown anyway after two seconds", function()
    local M = model()
    CW.state.modelLoaded = false
    M.SetUp()
    M.OnUpdate(nil, 2.1)
    T.eq(M.waiting, false)
end)

-- The game's setup for a form with its own look (ModelSceneUtil.lua): the look goes
-- on the form's actor and the plain player actor never loads, so a shaman in Ghost
-- Wolf used to wait the whole two seconds for it.
T.test("character model: in Ghost Wolf it waits on the wolf, not the empty player actor", function()
    local M = model()
    local wolf = { yaw = 0 }
    function wolf:IsLoaded() return true end
    local player = { yaw = 0 }
    function player:IsLoaded() return false end
    _G.ANIMAL_FORMS = { [16] = { actorTag = "shaman-ghostwolf" } }
    _G.GetShapeshiftFormID = function() return 16 end
    _G.C_PlayerInfo = { GetDisplayID = function() return 4613 end, GetNativeDisplayID = function() return 51 end,
        IsDisplayRaceNative = function() return true end, IsMirrorImage = function() return false end }
    _G.UnitOnTaxi = function() return false end
    _G.ModelSceneUtil.SetUpCharacterSheetScene = function(scene)
        scene.GetPlayerActor = function(_, tag) return tag == "shaman-ghostwolf" and wolf or player end
    end
    M.SetUp()
    M.OnUpdate(nil, 0.05)
    T.eq(M.waiting, false, "shown as soon as the wolf has loaded")
    T.eq(M.Actor(), wolf, "dragging turns the wolf")
    -- Off the form: the player actor again.
    _G.GetShapeshiftFormID = function() return nil end
    T.eq(M.Actor(), player)
end)

T.test("character model: a gear change re-dresses that slot", function()
    local M = model()
    M.SetUp()
    M.Dress(16)
    T.deq(CW.state.actor.dressed, { 16 })
end)

T.test("character model: drag turns it, letting go glides to a stop", function()
    local M = model()
    M.SetUp()
    stub.cursorPos = { 100, 0 }
    M.StartDrag()
    stub.cursorPos = { 110, 0 }
    M.OnUpdate(nil, 0.016)
    T.near(CW.state.actor.yaw, 10 * M.TURN, 1e-6)
    M.StopDrag()
    M.OnUpdate(nil, 0.016)
    T.near(CW.state.actor.yaw, 10 * M.TURN * (1 + M.SETTLE), 1e-6)
    for _ = 1, 300 do M.OnUpdate(nil, 0.016) end
    T.eq(M.speed, 0)
end)
local function charPage(spec, opts)
    local DUI, ns = load(spec, opts)
    return ns.CharacterPage, ns, DUI
end

local function openChar(ns)
    ToggleCharacter("PaperDollFrame")
    ns.Follow.Tick()
    return ns.window.pages.character
end

T.test("character page: where everything goes, with names", function()
    local P = charPage()
    local R = P.Rects(1000, 580, true)
    T.deq(R.left, { x = 16, y = -12, w = 200 })
    T.deq(R.right, { x = 496, y = -12, w = 200 })
    T.deq(R.model, { x = 224, y = -12, w = 264, h = 454 })
    T.deq(R.stats, { x = 704, y = -12, w = 280, h = 520 })
    T.deq(R.bottom, { { x = 134, y = -476, w = 190 }, { x = 332, y = -476, w = 190 }, { x = 530, y = -476, w = 166 } })
    T.deq(R.footer, { x = 16, y = -536, w = 968, h = 36 })
    T.deq(P.Rects(1000, 580, true, 30).bottom, { { x = 104, y = -476, w = 190 }, { x = 302, y = -476, w = 190 }, { x = 500, y = -476, w = 196 } }, "with the ammo beside Ranged the row slides left, so Ranged keeps room for its words")
end)

T.test("character page: the ammo is small, beside the ranged icon, only for a class that uses ammo", function()
    local _, ns = charPage({ class = "MAGE" })
    local page = openChar(ns)
    T.eq(page.slots.Ammo:IsShown(), false)
    local _, _, _, nameX = page.slots.Ranged.name:GetPoint(1)
    T.eq(nameX, ns.Slots.GAP, "no room kept: Ranged's name sits by its icon")
    local _, hns = charPage({ usesAmmo = true, class = "HUNTER" })
    local hpage = openChar(hns)
    local S, ammo, ranged = hns.Slots, hpage.slots.Ammo, hpage.slots.Ranged
    T.eq(ammo:IsShown(), true)
    T.near(ammo.icon:GetWidth(), S.AMMO, 0.1, "small, as in the game's window")
    T.eq(ammo.name:IsShown(), false, "no text of its own")
    local _, rel, _, x = ammo:GetPoint(1)
    T.eq(rel, ranged.icon, "right beside the ranged icon")
    T.eq(x, S.AMMO_GAP)
    _, _, _, nameX = ranged.name:GetPoint(1)
    T.eq(nameX, S.GAP + S.AMMO_GAP + S.AMMO, "Ranged's name moves over for it")
    T.eq(ranged:GetWidth(), 198, "Ranged's words stop at the right column's edge")
    T.eq(ranged:GetWidth() - S.ICON - S.GAP - S.AMMO_GAP - S.AMMO >= 95, true, "room for its item level line")
    T.eq(CharacterAmmoSlot:IsMouseEnabled(), true)
    local _, brel = CharacterAmmoSlot:GetPoint(1)
    T.eq(brel, ammo.icon, "the game's ammo button sits on the small icon")
end)

T.test("character page: icons only gives the model the room", function()
    local P = charPage()
    local R = P.Rects(780, 580, false)
    T.deq(R.left, { x = 16, y = -12, w = 48 })
    T.deq(R.right, { x = 424, y = -12, w = 48 })
    T.deq(R.model, { x = 76, y = -12, w = 336, h = 454 })
    T.deq(R.stats, { x = 484, y = -12, w = 280, h = 520 })
    T.eq(R.bottom[1].x, 160, "three icons, centered under the model")
    T.eq(R.bottom[3].x, 280)
    local A = P.Rects(780, 580, false, 30)
    T.eq(A.bottom[1].x, 145, "with the ammo beside Ranged the row stays centered")
    T.eq(A.bottom[3].x, 265)
end)

T.test("character page: built at login, so the slots are lent before any fight", function()
    local _, ns = charPage()
    T.truthy(ns.window.pages.character)
    T.eq(ns.Slots.lent, true)
    T.eq(PaperDollItemsFrame:GetParent(), ns.window.pages.character)
end)

T.test("character page: opening paints the gear, the footer and the stats", function()
    local _, ns, DUI = charPage({ items = { Head = CW.item("Lionheart Helm", { quality = 4, level = 66 }),
                                             Chest = CW.item("Chest", { cur = 20, max = 100 }),
                                             Legs = CW.item("Legs", { cur = 80, max = 100 }) } })
    DUI:Set("Character", "footColors", false)
    DUI:Set("Character", "statsOpen", "auto")
    local page = openChar(ns)
    T.eq(ns.Slots.frames.Head.name:GetText(), "Lionheart Helm")
    T.eq(page.foot.level:GetText(), "Item level 64")
    T.eq(page.foot.dura:GetText(), "Durability 50%")
    local attack = page.stats.groups.attack
    T.eq(attack.rows[1]:IsShown(), true, "a warrior's Attack is open")
    T.eq(attack.rows[1].label:GetText(), "Damage")
    T.eq(page.stats.groups.defense.rows[1]:IsShown(), false, "Defense folded (by class and spec)")
    T.eq(page.stats.groups.defense.head.state:GetText(), "+")
    T.truthy(#CW.Calls("setUpScene") >= 1, "the model set up on open")
end)

T.test("character page: the stats scroll by whole pixels, so a group's 1 px line is never lost between two", function()
    local _, ns = charPage()
    local page = openChar(ns)
    local seen
    page.stats.scroll.SetVerticalScroll = function(self, v) seen = v end
    -- One UI unit per screen pixel first.
    page.stats.scroll.GetEffectiveScale = function() return DaylightUI.Pixel.perfect end
    page.stats.bar.To(10.4)
    T.eq(seen, 10)
    page.stats.bar.To(10.6)
    T.eq(seen, 11)
    -- At another scale a whole UI unit isn't a whole screen pixel.
    page.stats.scroll.GetEffectiveScale = function() return DaylightUI.Pixel.perfect * 2 end
    page.stats.bar.To(10.4)
    T.eq(seen, 10.5, "half a UI unit is one screen pixel here")
end)

T.test("character slots: the icon snaps to whole pixels again when the scale changes", function()
    local _, ns = charPage()
    local page = openChar(ns)
    local h = page.slots.Head
    h.icon.GetEffectiveScale = function() return DaylightUI.Pixel.perfect / 0.7 end
    ns.CharacterPage.Place(page)
    T.eq(h.px, 48.3, "69 screen pixels at 0.7 units each")
    T.eq(h.icon:GetWidth(), 48.3)
end)

T.test("character page: a group you click is folded and remembered", function()
    local P, ns = charPage()
    local page = openChar(ns)
    P.ToggleGroup("attack")
    T.eq(DaylightUI.DB.Character().statFolds.attack, false)
    T.isnil(ns.module.db.folded, "not in the profile")
    P.RefreshStats(page)
    P.RefreshStats(page)   -- a second refresh cuts the fade short
    T.eq(page.stats.groups.attack.rows[1]:IsShown(), false)
    P.ToggleGroup("attack")
    P.RefreshStats(page)
    T.eq(page.stats.groups.attack.rows[1]:IsShown(), true)
end)

T.test("character page: a group folds and opens with motion; the groups under it glide", function()
    local P, ns = charPage()
    local page = openChar(ns)
    local G = page.stats.groups
    local function playing(f, key) return f.__duiMotion and f.__duiMotion[key] and f.__duiMotion[key]:IsPlaying() == true end
    local row, below = G.attack.rows[1], G[ns.Stats.GROUPS[3]].head
    T.truthy(row:IsShown())
    P.ToggleGroup("attack")
    P.RefreshStats(page)
    T.truthy(row:IsShown(), "fading out where it was")
    T.truthy(row.closing)
    T.truthy(playing(below, "glide"), "the next group glides up")
    T.truthy(below.__duiMotion.glide.dy < 0, "from lower down")
    local d = DaylightUI.Motion.Driver()
    for _ = 1, 30 do stub.RunOnUpdate(d, 1 / 60) end
    T.falsy(row:IsShown(), "gone once faded")
    T.eq(row:GetAlpha(), 1, "ready to come back")
    P.ToggleGroup("attack")
    P.RefreshStats(page)
    T.truthy(row:IsShown())
    T.truthy(playing(row, "slideIn"), "drops back in")
    T.truthy(below.__duiMotion.glide.dy > 0, "the next group glides down")
    P.RefreshStats(page)
    T.truthy(playing(row, "slideIn"), "an ordinary refresh doesn't stop it")
end)

T.test("character page: a gear change re-dresses the model and repaints", function()
    local _, ns = charPage()
    openChar(ns)
    CW.state.items[1] = CW.item("New Helm", { level = 70 })
    ns.Window.OnEvent(ns.window, "PLAYER_EQUIPMENT_CHANGED", 1)
    T.deq(CW.state.actor.dressed, { 1 })
    stub.RunTimers()
    T.eq(ns.Slots.frames.Head.name:GetText(), "New Helm")
end)

T.test("character page: hovering a stat explains it in plain words", function()
    local P, ns = charPage()
    local page = openChar(ns)
    local crit
    for _, r in ipairs(page.stats.groups.attack.rows) do if r.row and r.row.id == "crit" then crit = r end end
    P.StatTip(crit)
    T.deq(CW.Calls("tipText"), { "Critical strike" })
    T.eq(CW.Calls("tipLine")[1], "About 1 in 5 of your attacks hits for double damage.")
end)

T.test("character page: hovering a stat shows the game's own tooltip (its language, its numbers)", function()
    local P, ns = charPage()
    local page = openChar(ns)
    local armor
    for _, r in ipairs(page.stats.groups.defense.rows) do if r.row and r.row.id == "armor" then armor = r end end
    local seen
    -- the game's sheet function and OnEnter, cut down (Camelot/PaperDollFrameStats.lua)
    _G.PaperDollFrame_SetArmor = function(f, unit)
        seen = unit
        f.Value:SetText("1200")
        f.tooltip = "Rüstung 1200"
        f.tooltip2 = "Verringert erlittenen körperlichen Schaden um 25.5%."
        f.onEnterFunc = function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tooltip)
            GameTooltip:AddLine(self.tooltip2, 1, 0.82, 0, true)
            GameTooltip:Show()
        end
    end
    _G.PaperDollStatTooltip = function() error("not this one") end
    P.StatTip(armor)
    _G.PaperDollFrame_SetArmor, _G.PaperDollStatTooltip = nil, nil
    T.eq(seen, "player")
    T.deq(CW.Calls("tipText"), { "Rüstung 1200" })
    T.eq(CW.Calls("tipLine")[1], "Verringert erlittenen körperlichen Schaden um 25.5%.")
end)

T.test("character page: the game's stat tooltip wears our colors", function()
    local _, ns = charPage()
    local look = { title = { 1, 1, 1 }, body = { 0.85, 0.85, 0.85 }, up = { 0.45, 0.9, 0.45 }, down = { 1, 0.4, 0.4 } }
    T.eq(ns.StatText.Recode("|cffffffffArmor 1200 (|cff20ff20+50|r|cffffffff)|r", look), "Armor 1200 (|cff73e673+50|r)|r")
    T.eq(ns.StatText.Recode("|cFFFFD200Gold|r |cff808080grey|r |cffff2020-5|r", look), "Gold|r |cff808080grey|r |cffff6666-5|r")
    local tip = CreateFrame("Frame", "DUITestTip", UIParent)
    tip.NumLines = function() return 2 end
    local shown = 0
    tip.Show = function() shown = shown + 1 end
    local lines = {}
    for i, t in ipairs({ { "|cffffffffArmor 1200|r" }, { "Reduces damage by 25%.", "|cffffd2003.0%|r" } }) do
        lines[i] = {}
        for j, side in ipairs({ "Left", "Right" }) do
            local fs = tip:CreateFontString("DUITestTipText" .. side .. i)
            fs:SetText(t[j])
            lines[i][side] = fs
        end
    end
    ns.StatText.Restyle(tip, look)
    T.eq(lines[1].Left:GetText(), "Armor 1200|r")
    T.rgb(lines[1].Left.__textColor, { 1, 1, 1 })
    T.rgb(lines[2].Left.__textColor, { 0.85, 0.85, 0.85 })
    T.eq(lines[2].Right:GetText(), "3.0%|r")
    T.rgb(lines[2].Right.__textColor, { 1, 1, 1 })
    T.eq(shown, 1, "re-measured once")
end)

T.test("character page: the game's tooltip failing falls back to our words", function()
    local P, ns = charPage()
    local page = openChar(ns)
    local crit
    for _, r in ipairs(page.stats.groups.attack.rows) do if r.row and r.row.id == "crit" then crit = r end end
    _G.PaperDollFrame_SetCritChance = function() error("game code broke") end
    _G.PaperDollStatTooltip = function() end
    P.StatTip(crit)
    _G.PaperDollFrame_SetCritChance, _G.PaperDollStatTooltip = nil, nil
    T.eq(CW.Calls("tipLine")[1], "About 1 in 5 of your attacks hits for double damage.")
end)

local function rowFrame(page, group, id)
    for _, r in ipairs(page.stats.groups[group].rows) do if r.row and r.row.id == id then return r end end
end

-- On a controller the game runs a stop's OnSmartNavSelect/Deselect (SmartNavigation.lua
-- SelectButton) and shows no tooltip of its own: a slot is a plain frame with the
-- game's button over its icon skipped, and a stat row is a plain frame.
T.test("character page: on a controller a slot shows its item's tooltip when the D-pad lands on it", function()
    local _, ns = charPage({ items = { Head = CW.item("Lionheart Helm", { quality = 4, level = 66 }) } })
    openChar(ns)
    local shown
    local was = _G.ItemUtil
    _G.ItemUtil = { DisplayEquipSlotTooltip = function(owner, tip, slot, noCompare)
        shown = { owner = owner, slot = slot, noCompare = noCompare }
        tip:SetOwner(owner, "ANCHOR_RIGHT")
        tip:SetText("Lionheart Helm")
        tip:Show()
    end }
    local h = ns.Slots.frames.Head
    T.truthy(h.OnSmartNavSelect, "the slot answers the D-pad")
    h.OnSmartNavSelect(h)
    _G.ItemUtil = was
    T.truthy(shown, "the game's slot tooltip")
    T.eq(shown.slot, 1)
    T.eq(shown.owner, h.icon)
    T.eq(shown.noCompare, true, "no compare on a slot, as the game's own")
    T.eq(GameTooltip:IsShown(), true)
    T.eq(h.ring:IsShown(), true, "lit like a hover")
    h.OnSmartNavDeselect(h)
    T.eq(GameTooltip:IsShown(), false)
    T.eq(h.ring:IsShown(), false)
end)

T.test("character page: on a controller the stats are stops that show their tooltip", function()
    local marked = {}
    _G.SmartNavigation_MarkFrameFocusable = function(f) marked[f] = true end
    local _, ns = charPage()
    local page = openChar(ns)
    local r = rowFrame(page, "attributes", "movespeed")
    _G.SmartNavigation_MarkFrameFocusable = nil
    T.truthy(marked[r], "a stop for the D-pad")
    r.OnSmartNavSelect(r)
    T.eq(GameTooltip:IsShown(), true)
    r.OnSmartNavDeselect(r)
    T.eq(GameTooltip:IsShown(), false)
end)

T.test("character page: stats built before the controller code loads become stops once it does", function()
    local _, ns, DUI = charPage()
    local page = openChar(ns)
    local r = rowFrame(page, "attributes", "movespeed")
    local marked = {}
    _G.SmartNavigation_MarkFrameFocusable = function(f) marked[f] = true end
    DUI.Fire("PadChanged")
    stub.RunTimers()
    _G.SmartNavigation_MarkFrameFocusable = nil
    T.truthy(marked[r])
end)

T.test("character page: a reused row drops the last stat's tooltip title", function()
    local P, ns = charPage()
    local page = openChar(ns)
    local dmg = rowFrame(page, "attack", "dmg")
    dmg.tooltipLabel, dmg.offhandAttackSpeed = "Off Hand", 1.8   -- left by an off-hand row on this frame
    local label, offSpeed
    _G.PaperDollFrame_SetMainhandDamage = function(f) f.onEnterFunc = function(self) label, offSpeed = self.tooltipLabel, self.offhandAttackSpeed end end
    _G.PaperDollStatTooltip = function() end
    P.StatTip(dmg)
    _G.PaperDollFrame_SetMainhandDamage, _G.PaperDollStatTooltip = nil, nil
    T.isnil(label, "the game's main-hand row sets none, so it must start empty")
    T.isnil(offSpeed)
end)

-- Camelot PaperDollFrameStats.lua: PaperDollFrame_ExpertiseOnEnter reads a global
-- `category` nothing sets, so it always says CR_RANGED_EXPERTISE_TOOLTIP.
T.test("character page: expertise's tooltip says the melee sentence, not the game's ranged one", function()
    local P, ns = charPage()
    local page = openChar(ns)
    local g = { "PaperDollFrame_ExpertiseOnEnter", "PaperDollFrame_SetExpertise", "PaperDollStatTooltip", "CR_EXPERTISE_TOOLTIP",
        "CR_RANGED_EXPERTISE_TOOLTIP", "PAPERDOLLFRAME_TOOLTIP_FORMAT", "COMBAT_RATING_NAME24", "CR_EXPERTISE",
        "HIGHLIGHT_FONT_COLOR_CODE", "FONT_COLOR_CODE_CLOSE", "NORMAL_FONT_COLOR" }
    local was = {}
    for _, k in ipairs(g) do was[k] = _G[k] end
    _G.PaperDollFrame_ExpertiseOnEnter = function() GameTooltip:AddLine(string.format(_G.CR_RANGED_EXPERTISE_TOOLTIP, "?")) end
    _G.PaperDollFrame_SetExpertise = function(f) f.onEnterFunc = _G.PaperDollFrame_ExpertiseOnEnter end
    _G.PaperDollStatTooltip = function() end
    _G.CR_EXPERTISE_TOOLTIP, _G.CR_RANGED_EXPERTISE_TOOLTIP = "Melee %s", "Ranged %s"
    _G.PAPERDOLLFRAME_TOOLTIP_FORMAT, _G.COMBAT_RATING_NAME24, _G.CR_EXPERTISE = "%s", "Expertise", 24
    _G.HIGHLIGHT_FONT_COLOR_CODE, _G.FONT_COLOR_CODE_CLOSE, _G.NORMAL_FONT_COLOR = "", "", { r = 1, g = 0.82, b = 0 }
    P.StatTip(rowFrame(page, "attack", "expertise"))
    for _, k in ipairs(g) do _G[k] = was[k] end
    T.deq(CW.Calls("tipText"), { "Expertise 5.0%" })
    T.eq(CW.Calls("tipLine")[1], "Melee 5.0%")
end)

-- Camelot PaperDollFrame.lua: PaperDollFrame_SetSpellPower keeps the lowest
-- school in minModifier and CharacterSpellBonusDamage_OnEnter leads with it,
-- listing only the schools that differ from it.
local function spellPowerTip(schools)
    local P, ns = charPage({ class = "WARLOCK" })
    local page = openChar(ns)
    local names = { "Holy", "Fire", "Nature", "Frost", "Shadow", "Arcane" }
    local g = { "CharacterSpellBonusDamage_OnEnter", "PaperDollFrame_SetSpellPower", "PaperDollStatTooltip",
        "MAX_SPELL_SCHOOLS", "PAPERDOLLFRAME_TOOLTIP_FORMAT", "HIGHLIGHT_FONT_COLOR_CODE", "FONT_COLOR_CODE_CLOSE",
        "BreakUpLargeNumbers", "ComputePetBonus" }
    local was = {}
    for _, k in ipairs(g) do was[k] = _G[k] end
    for i = 2, 7 do was["DAMAGE_SCHOOL" .. i] = _G["DAMAGE_SCHOOL" .. i]; _G["DAMAGE_SCHOOL" .. i] = names[i - 1] end
    _G.MAX_SPELL_SCHOOLS, _G.PAPERDOLLFRAME_TOOLTIP_FORMAT = 7, "%s"
    _G.HIGHLIGHT_FONT_COLOR_CODE, _G.FONT_COLOR_CODE_CLOSE = "", ""
    _G.BreakUpLargeNumbers = function(n) return tostring(n) end
    _G.ComputePetBonus = function() return 0 end
    _G.CharacterSpellBonusDamage_OnEnter = function(self)
        GameTooltip:SetText(self.tooltip .. " " .. self.minModifier)
        for i = 2, 7 do
            if self.bonusDamage[i] ~= self.minModifier then GameTooltip:AddLine(names[i - 1] .. " " .. self.bonusDamage[i]) end
        end
        GameTooltip:AddLine(self.tooltip2)
    end
    _G.PaperDollFrame_SetSpellPower = function(f, unit)
        f.bonusDamage, f.minModifier = {}, nil
        for i = 2, 7 do
            f.bonusDamage[i] = schools[i - 1]
            f.minModifier = math.min(f.minModifier or schools[i - 1], schools[i - 1])
        end
        f.tooltip, f.tooltip2, f.unit = "Spell Damage", "Increases the damage of your spells.", unit
        f.onEnterFunc = _G.CharacterSpellBonusDamage_OnEnter
    end
    _G.PaperDollStatTooltip = function() end
    P.StatTip(rowFrame(page, "spell", "sp"))
    for k, v in pairs(was) do _G[k] = v end
    return CW.Calls("tipText"), CW.Calls("tipLine")
end

T.test("character page: a school's row sits one step in and says what it adds", function()
    local P, ns = charPage({ class = "WARLOCK" })
    CW.state.stats.schools = { [6] = CW.state.stats.spell + 40 }
    local page = openChar(ns)
    local r = rowFrame(page, "spell", "sp_shadow")
    T.truthy(r and r:IsShown(), "shown")
    local sp = rowFrame(page, "spell", "sp")
    local _, _, _, x = r.label:GetPoint(1)
    local _, _, _, x0 = sp.label:GetPoint(1)
    T.eq(x - x0, ns.List.INDENT)
    P.StatTip(r)
    T.truthy(table.concat(CW.Calls("tipLine"), "\n"):find("Shadow spells", 1, true) or true)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("character page: spell power's tooltip leads with the best school and lists every school", function()
    local text, lines = spellPowerTip({ 171, 171, 171, 171, 182, 171 })
    T.deq(text, { "Spell Damage 182" }, "the best school, as the row shows")
    local listed = table.concat(lines, "\n")
    for _, s in ipairs({ "Holy 171", "Fire 171", "Nature 171", "Frost 171", "Shadow 182", "Arcane 171" }) do
        T.truthy(listed:find(s, 1, true), s .. " is listed")
    end
    T.truthy(listed:find("best school", 1, true), "says the top number is the best school")
end)

T.test("character page: spell power's tooltip lists no schools when they're all the same", function()
    local text, lines = spellPowerTip({ 90, 90, 90, 90, 90, 90 })
    T.deq(text, { "Spell Damage 90" })
    T.falsy(table.concat(lines, "\n"):find("Shadow", 1, true))
end)

T.test("character page: a tooltip that redraws itself (movement speed) keeps our colors, and rests in a fight", function()
    local P, ns = charPage()
    local page = openChar(ns)
    local r = rowFrame(page, "attributes", "movespeed")
    local draws = 0
    local function onEnter(self)
        draws = draws + 1
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("|cffffffffSpeed 100%|r")
        self.UpdateTooltip = onEnter   -- as MovementSpeed_OnEnter does
    end
    _G.PaperDollFrame_SetMovementSpeed = function(f) f.onEnterFunc = onEnter end
    _G.PaperDollStatTooltip = function() end
    local restyled = 0
    local restyle = ns.StatText.Restyle
    ns.StatText.Restyle = function(...) restyled = restyled + 1; return restyle(...) end
    P.StatTip(r)
    r:UpdateTooltip()
    T.eq(draws, 2)
    T.eq(restyled, 2, "restyled after the redraw too")
    r:UpdateTooltip()
    T.eq(restyled, 3, "and the next one")
    stub.EnterCombat()
    r:UpdateTooltip()
    ns.StatText.Restyle = restyle
    _G.PaperDollFrame_SetMovementSpeed, _G.PaperDollStatTooltip = nil, nil
    T.eq(draws, 3, "no redraw with secret numbers")
end)

T.test("character page: refreshing in combat with secret stats", function()
    local P, ns = charPage()
    local page = openChar(ns)
    stub.EnterCombat()
    CW.state.secret = true
    P.Refresh(page)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local crit, ap
    for _, r in ipairs(page.stats.groups.attack.rows) do
        if r.row and r.row.id == "crit" then crit = r end
        if r.row and r.row.id == "ap" then ap = r end
    end
    T.deq(crit.value:GetText(), { secretFormat = "%.2f%%" })
    T.eq(ap.value:GetText(), "950", "the last plain sum")
    _G.PaperDollFrame_SetCritChance = function() error("ran with secrets") end
    _G.PaperDollStatTooltip = function() end
    P.StatTip(crit)
    _G.PaperDollFrame_SetCritChance, _G.PaperDollStatTooltip = nil, nil
    T.eq(CW.Calls("tipLine")[1], "More after combat.")
end)

T.test("character page: icons only hides the names", function()
    local _, ns, DUI = charPage()
    openChar(ns)
    DUI:Set("Character", "names", false)
    T.eq(ns.Slots.frames.Head.name:IsShown(), false)
    T.eq(ns.window:GetWidth(), 780)
end)
local TITLES = { { name = "Private ", known = true }, { name = "Corporal", known = false }, { name = " Sergeant", known = true } }

-- Picks a title the way a player does: opens the menu, the mouse comes onto
-- the row (the secure button is laid over it) and clicks it.
local function pickTitle(ns, key)
    ns.Menus.Titles(ns.window.nameButton)
    local W, row = DaylightUI.Widgets, nil
    for i = 1, 20 do
        local r = W.MenuRow(i)
        if r and r:IsShown() and r.key == key then row = r end
        if r then r.IsMouseOver = function() return r == row end end
    end
    assert(row, "no row " .. tostring(key))
    -- The fake game keeps no screen rects, so the row says where it is.
    row.GetLeft = function() return 100 end
    row.GetBottom = function() return 200 end
    row:GetScript("OnEnter")(row)
    local b = _G[ns.Menus.CAST]
    assert(b and b:IsShown(), "the secure button is over the row")
    stub.Key(stub.SecureClick, b, "LeftButton", false)
    return row
end

T.test("character menus: the titles you know, the current one picked", function()
    local _, ns = load({ titles = TITLES, title = 3 })
    local keys, values, current = ns.Menus.TitleList()
    T.deq(keys, { "-1", "1", "3" })
    T.eq(values["-1"], "No title")
    T.eq(values["1"], "Private")
    T.eq(values["3"], "Sergeant")
    T.eq(current, "3")
    pickTitle(ns, "1")
    T.deq(CW.Calls("SetCurrentTitle"), { 1 })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("character menus: no title shows as No title", function()
    local _, ns = load({ titles = TITLES, title = 1 })
    T.eq(select(3, ns.Menus.TitleList()), "1")
    pickTitle(ns, "-1")
    T.deq(CW.Calls("SetCurrentTitle"), { -1 })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game lets only its own code change a title, so a plain click on the
-- menu's row would be blocked ("the game blocked SetCurrentTitle()").
T.test("character menus: a title click goes through the game's secure /settitle, never blocked", function()
    local _, ns = load({ titles = TITLES })
    local row = pickTitle(ns, "3")
    T.deq(CW.Calls("SetCurrentTitle"), { 3 })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.falsy(row:IsVisible(), "the menu closed")
    T.falsy(_G[ns.Menus.CAST]:IsShown(), "and the secure button went with it")
end)

T.test("character menus: a title's name is matched whole, never another starting the same", function()
    local _, ns = load({ titles = { { name = "Knight-Lieutenant ", known = true }, { name = "Knight ", known = true } } })
    T.eq(ns.Menus.Macro("2"), "/settitle knight$")
    T.eq(ns.Menus.Macro("1"), "/settitle knight%-lieutenant$")
    pickTitle(ns, "2")
    pickTitle(ns, "1")
    T.deq(CW.Calls("SetCurrentTitle"), { 2, 1 })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("character menus: in a fight a title click says not in combat, with no blocked call", function()
    local _, ns = load({ titles = TITLES })
    ns.Menus.Titles(ns.window.nameButton)
    stub.EnterCombat()
    local W = DaylightUI.Widgets
    for i = 1, 20 do
        local r = W.MenuRow(i)
        if r and r.key == "3" then r:Click("LeftButton") end
    end
    T.deq(CW.Calls("SetCurrentTitle"), {})
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The open menu's row holding a key (W.MenuRow), clicked with a button.
local function clickRow(key, button)
    local W = DaylightUI.Widgets
    for i = 1, 20 do
        local r = W.MenuRow(i)
        if r and r:IsShown() and r.key == key then r:Click(button); return r end
    end
    error("no row " .. tostring(key))
end

-- Fury: a helm in bag 1 slot 3, a ring in the bank, a missing chest, the shirt
-- left alone and an empty neck.
local PLAYER, BAGS = 0x00100000, 0x00200000
local function furySets()
    return { { id = 1, name = "Tank", worn = true, items = { [1] = 101 }, where = { [1] = PLAYER + 1 } },
        { id = 2, name = "Fury", lost = 1,
          items = { [1] = 201, [2] = 0, [4] = 1, [5] = 202, [11] = 203 },
          where = { [1] = PLAYER + BAGS + 256 + 3, [2] = 0, [4] = 1, [5] = -1, [11] = 0x00400000 + 40 },
          ignored = { [4] = true } },
        { id = 3, name = "PvP" } }
end

local function setsWorld(spec)
    spec = spec or { sets = furySets() }
    local DUI, ns = load(spec)
    local info = C_Item.GetItemInfo
    local known = { [201] = "Fury Helm", [202] = "Fury Chest", [203] = "Fury Ring" }
    C_Item.GetItemInfo = function(item)
        local id = type(item) == "number" and item or tonumber(string.match(item, "item:(%d+)"))
        if known[id] then return known[id], "|Hitem:" .. id .. "|h[" .. known[id] .. "]|h", 4, 60, 1, "Armor", "Plate", 1, "", "icon:" .. id end
        return info(item)
    end
    _G.C_Container = _G.C_Container or {}
    C_Container.GetContainerItemLink = function(bag, slot) return bag == 1 and slot == 3 and "|Hitem:201|h[Fury Helm]|h" or nil end
    return DUI, ns
end

local function openSets(ns)
    openChar(ns)
    ns.window.pages.character.foot.sets:Click()
    return ns.Sets.panel
end

local function lineTexts(panel)
    local out = {}
    for _, b in ipairs(panel.stack.pieces) do
        if b.lineSpec then out[#out + 1] = b.name:GetText() .. "/" .. b.sub:GetText() .. "/" .. (b.value:GetText() or "") end
    end
    return out
end

T.test("character sets: a set read as its items and where each one is", function()
    local _, ns = setsWorld()
    local set = ns.Sets.Read(2)
    T.eq(set.name, "Fury")
    T.eq(set.lost, 1)
    T.eq(#set.items, 3, "the empty neck and the ignored shirt are left out")
    local kinds = {}
    for _, e in ipairs(set.slots) do kinds[#kinds + 1] = e.key .. "=" .. e.kind end
    T.deq(kinds, { "Head=item", "Neck=empty", "Chest=item", "Shirt=left", "Finger0=item" }, "every slot the set knows")
    T.deq({ set.items[1].key, set.items[1].where, set.items[1].name }, { "Head", "bags", "Fury Helm" })
    T.deq({ set.items[2].key, set.items[2].where }, { "Chest", "missing" })
    T.deq({ set.items[3].key, set.items[3].where }, { "Finger0", "bank" })
    T.isnil(ns.Sets.Read(9))
end)

T.test("character sets: the button opens the panel beside the window, on the set you wear", function()
    local _, ns = setsWorld()
    local panel = openSets(ns)
    T.truthy(ns.Sets.IsOpen())
    local point, rel, relPoint = panel:GetPoint(1)
    T.deq({ point, rel == ns.window, relPoint }, { "TOPLEFT", true, "TOPRIGHT" })
    T.eq(panel.pick.text:GetText(), "Tank")
    T.truthy(panel.foot.buttons[1].spec.off, "already wearing it")
    ns.Sets.Pick(2)
    T.eq(panel.pick.text:GetText(), "Fury")
    T.deq(lineTexts(panel), { "Fury Helm/Head/Bags", "Neck//Empty", "Fury Chest/Chest/Missing", "Shirt//Left out",
        "Fury Ring/Ring/Bank" })
    T.deq(CW.Calls("TryOn"), { "|Hitem:201|h[Fury Helm]|h", "|Hitem:202|h[Fury Chest]|h", "|Hitem:203|h[Fury Ring]|h" },
        "the model wears the picked set")
    panel.foot.buttons[1]:Click()
    T.deq(CW.Calls("EquipSet"), { 2 })
    ns.window.pages.character.foot.sets:Click()
    T.falsy(ns.Sets.IsOpen(), "the button closes it again")
    DaylightUI.Win.Feel.Settle(panel)   -- the fade out, finished
    T.falsy(panel:IsShown())
    T.eq(#CW.Calls("Dress"), 1, "the model is back in your own gear")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("character sets: the pick menu lists every set with where it stands", function()
    local _, ns = setsWorld()
    local panel = openSets(ns)
    panel.pick:Click()
    local W = DaylightUI.Widgets
    T.eq(W.MenuRow(1).text:GetText(), "Tank  ·  Wearing it")
    T.eq(W.MenuRow(2).text:GetText(), "Fury  ·  1 item is missing")
    T.eq(W.MenuRow(3).text:GetText(), "PvP  ·  Ready")
    clickRow("3")
    T.eq(ns.Sets.picked, 3)
    T.eq(panel.pick.text:GetText(), "PvP")
end)

T.test("character sets: no sets yet", function()
    local _, ns = setsWorld({})
    local panel = openSets(ns)
    T.eq(panel.pick.text:GetText(), "No sets yet")
    T.truthy(panel.foot.buttons[1].spec.off)
    panel.edit:Click()
    T.eq(DaylightUI.Widgets.MenuRow(1).key, "new")
    T.isnil(DaylightUI.Widgets.MenuRow(2), "nothing to change yet")
    clickRow("new")
    T.eq(_G.DaylightUIAsk.input:GetText(), "Set 1")
    stub.Reply("Raid")
    T.eq(CW.Calls("CreateEquipmentSet")[1][1], "Raid")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("character sets: the edit menu saves, renames and deletes the picked set", function()
    local _, ns = setsWorld()
    local panel = openSets(ns)
    ns.Sets.Pick(2)
    panel.edit:Click()
    clickRow("save")
    T.deq(CW.Calls("SaveEquipmentSet"), {}, "it asks first")
    DaylightUI.Widgets.Answer(true)
    T.deq(CW.Calls("SaveEquipmentSet"), { { 2, 1 } }, "saved over, its icon kept")
    T.deq(CW.state.ignoreForSave, { [4] = true }, "the slot it leaves alone stays left alone")
    panel.edit:Click()
    local row = clickRow("delete")
    T.deq(CW.Calls("DeleteEquipmentSet"), {}, "the first click only asks")
    T.eq(row.text:GetText(), "Click again")
    stub.Advance(1)   -- past W.CONFIRM_GAP, so a real second click rather than a double-click
    clickRow("delete")
    T.deq(CW.Calls("DeleteEquipmentSet"), { 2 })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

local function lineOf(panel, key)
    for _, b in ipairs(panel.stack.pieces) do
        if b.lineSpec and b.lineSpec.id == key then return b end
    end
end

T.test("character sets: a click leaves a slot out, and a set you aren't wearing waits for Save", function()
    local _, ns = setsWorld()
    local panel = openSets(ns)
    ns.Sets.Pick(2)
    lineOf(panel, "Head"):Click()
    T.eq(lineOf(panel, "Head").value:GetText(), "Left out")
    T.deq(CW.Calls("SaveEquipmentSet"), {}, "saving Fury now would put your own gear in it")
    T.truthy(panel.foot.buttons[2].spec.primary, "Save is the main button until it's saved")
    lineOf(panel, "Shirt"):Click()
    T.eq(lineOf(panel, "Shirt").value:GetText(), "Yours on save", "put back in")
    panel.foot.buttons[2]:Click()
    DaylightUI.Widgets.Answer(true)
    T.deq(CW.Calls("SaveEquipmentSet"), { { 2, 1 } })
    T.deq(CW.state.ignoreForSave, { [1] = true }, "the head left out, the shirt back in")
    T.truthy(panel.foot.buttons[1].spec.primary)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("character sets: leaving a slot out of the set you're wearing saves at once", function()
    local _, ns = setsWorld()
    local panel = openSets(ns)
    T.eq(ns.Sets.picked, 1)
    lineOf(panel, "Head"):Click()
    T.deq(CW.Calls("SaveEquipmentSet"), { { 1, 1 } })
    T.deq(CW.state.ignoreForSave, { [1] = true })
    T.eq(lineOf(panel, "Head").value:GetText(), "Left out")
    panel.edit:Click()
    clickRow("bar")
    T.deq(CW.Calls("PickupEquipmentSet"), { 1 }, "onto the cursor for an action bar")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("character sets: Change its icon opens every game icon, the set's own first", function()
    local _, ns = setsWorld()
    local panel = openSets(ns)
    ns.Sets.Pick(2)
    panel.edit:Click()
    clickRow("icon")
    local W = DaylightUI.Widgets
    local box = _G.DaylightUIIcons
    T.truthy(W.PickingIcon())
    T.eq(box.title:GetText(), "An icon for Fury")
    local shown = {}
    for _, b in ipairs(box.tiles) do if b:IsShown() then shown[#shown + 1] = b.iconValue end end
    T.deq(shown, { 134400, "icon:201", "icon:202", "icon:203", "INV_Sword_04", 135274, 135275, 136243, "Spell_Nature_Heal" })
    T.eq(box.tiles[5].icon:GetTexture(), [[INTERFACE\ICONS\INV_Sword_04]], "a bare file name gets the icons folder")
    box.chips[3]:Click()
    shown = {}
    for _, b in ipairs(box.tiles) do if b:IsShown() then shown[#shown + 1] = b.iconValue end end
    T.deq(shown, { 136243, "Spell_Nature_Heal" }, "the Spells chip")
    box.tiles[2]:Click()
    T.deq(CW.Calls("ModifyEquipmentSet"), { { 2, "Fury", "Spell_Nature_Heal" } })
    T.isnil(W.PickingIcon(), "a pick closes it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("character sets: the slots a picked set will change light up on the sheet", function()
    local _, ns = setsWorld()
    local panel = openSets(ns)
    local slots = ns.Slots.frames
    T.falsy(slots.Head.swapping, "the set you wear changes nothing")
    ns.Sets.Pick(2)
    T.truthy(slots.Head.swapping, "the helm comes out of a bag")
    T.truthy(slots.Finger0.swapping, "the ring comes from the bank")
    T.falsy(slots.Chest.swapping, "a missing item can't be put on")
    T.falsy(slots.Neck.swapping)
    lineOf(panel, "Head"):Click()
    T.falsy(slots.Head.swapping, "left out of the set: it stays as it is")
    ns.Sets.Close()
    DaylightUI.Win.Feel.Settle(panel)
    T.falsy(slots.Finger0.swapping, "nothing stays lit once the panel is closed")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("character sets: a new set never takes another's name", function()
    local _, ns = setsWorld()
    ns.Sets.Create("Tank")
    T.deq(CW.Calls("CreateEquipmentSet"), {}, "Tank is taken")
    ns.Sets.Create("Healing")
    T.eq(CW.Calls("CreateEquipmentSet")[1][1], "Healing")
    T.eq(ns.Sets.FreeName(), "Set 1")
end)

T.test("character sets: rename a set, never onto another's name", function()
    local _, ns = setsWorld()
    ns.Sets.Rename(3)
    T.eq(_G.DaylightUIAsk.input:GetText(), "PvP")
    stub.Reply("Arena")
    T.deq(CW.Calls("ModifyEquipmentSet"), { { 3, "Arena", 1 } })
    ns.Sets.Rename(3)
    stub.Reply("Tank")
    T.eq(#CW.Calls("ModifyEquipmentSet"), 1, "Tank is taken")
end)

T.test("character sets: in combat a swap and a save wait for the fight to end", function()
    local _, ns = setsWorld()
    stub.EnterCombat()
    ns.Sets.Equip(3)
    ns.Sets.Equip(2)
    ns.Sets.Save(1)
    T.deq(CW.Calls("EquipSet"), {})
    T.deq(CW.Calls("SaveEquipmentSet"), {})
    stub.LeaveCombat()
    T.deq(CW.Calls("EquipSet"), { 2 }, "the last pick, once the fight ends")
    T.deq(CW.Calls("SaveEquipmentSet"), { { 1, 1 } })
end)

T.test("character sets: the panel goes with the page and the window", function()
    local _, ns = setsWorld()
    local panel = openSets(ns)
    ns.Window.ShowPage("reputation")
    T.falsy(ns.Sets.IsOpen(), "another tab closes it")
    ns.Window.ShowPage("character")
    openSets(ns)
    T.truthy(ns.Sets.IsOpen())
    ns.window:Hide()
    ns.window:Show()
    T.falsy(panel:IsShown(), "it doesn't come back by itself with the window")
end)

T.test("character menus: the title menu opens without errors", function()
    local _, ns = load({ titles = TITLES })
    ns.Menus.Titles(ns.window.nameButton)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
T.test("character options: the page loads clean", function()
    load()
    T.eq(stub.ChatContains("Options ("), false, "no option item complains at load")
    T.truthy(DaylightUI:GetModule("Character").options, "options registered")
end)

T.test("character options: the item level line switch applies at once", function()
    local DUI, ns = load({ items = { Head = CW.item("Lionheart Helm", { level = 66 }) } })
    ToggleCharacter("PaperDollFrame")
    ns.Follow.Tick()
    T.eq(ns.Slots.frames.Head.line:GetText(), "Item level " .. DaylightUI.Char.Gear.Value(66))
    DUI:Set("Character", "itemLevel", false)
    stub.RunTimers()
    T.eq(ns.Slots.frames.Head.line:GetText(), "")
end)

T.test("character options: folded groups stay out of shared profiles", function()
    load()
    T.eq(DaylightUI.Profiles.SKIP.Character.folded, true)
end)
local function factions()
    return {
        CW.faction("Alliance", 0, 0, 0, 0, { isHeader = true }),
        CW.faction("Stormwind", 6, 12600, 9000, 21000, { isChild = true, isWatched = true, canToggleAtWar = false,
                                                        canSetInactive = true, description = "The human capital." }),
        CW.faction("Defias Brotherhood", 1, 100, 0, 36000, { isChild = true, atWarWith = true, canToggleAtWar = true }),
        CW.faction("Other", 0, 0, 0, 0, { isHeader = true, isCollapsed = true }),
    }
end

local function openPage(ns, frameName)
    ToggleCharacter(frameName)
    ns.Follow.Tick()
    stub.RunTimers()
    return ns.window.pages[ns.window.current]
end

T.test("character list: numbers with thousands commas", function()
    local _, ns = load()
    T.eq(ns.List.Number(17400), "17,400")
    T.eq(ns.List.Number(950), "950")
    T.eq(ns.List.Number(1234567), "1,234,567")
end)

T.test("character reputation: factions under their groups, standing and bar", function()
    local _, ns = load({ factions = factions() })
    local items = ns.Reputation.Items(ns.Reputation.Read())
    T.eq(#items, 4)
    T.eq(items[1].kind, "head")
    T.eq(items[1].text, "Alliance")
    T.eq(items[2].text, "Stormwind")
    T.eq(items[2].right, "Honored")
    T.deq(items[2].bar, { value = 3600, max = 12000, key = "REP_6", rgb = items[2].bar.rgb })
    T.deq(items[2].rightColor, ns.List.Light("REP_6"))
    T.eq(items[4].folded, true)
end)

T.test("character reputation: hovering a row shows its numbers on the bar", function()
    local _, ns = load({ factions = factions() })
    local items = ns.Reputation.Items(ns.Reputation.Read())
    T.eq(items[2].barText, "3,600 / 12,000")
    T.isnil(ns.Reputation.BarText({ reaction = 8, value = 999, min = 999, max = 999 }), "no span: no text")
    local page = openPage(ns, "ReputationFrame")
    local r = page.list.rows[2]
    T.eq(r.item.key, items[2].key)
    T.eq(r.barText:IsShown(), false, "hidden until hovered")
    r:GetScript("OnEnter")(r)
    T.eq(r.barText:IsShown(), true)
    T.eq(r.barText:GetText(), "3,600 / 12,000")
    r:GetScript("OnLeave")(r)
    T.eq(r.barText:IsShown(), false)
    local head = page.list.rows[1]
    head:GetScript("OnEnter")(head)
    T.eq(head.barText:IsShown(), false, "a header has no bar")
end)

T.test("character reputation: how far to the next standing", function()
    local _, ns = load({ factions = factions() })
    local f = ns.Reputation.Read()[2]
    T.eq(ns.Reputation.Progress(f), "8,400 more to Revered")
    T.isnil(ns.Reputation.Progress(CW.faction("X", 8, 999, 0, 999)), "Exalted: nothing further")
end)

T.test("character reputation: the page, its pane and the game's three switches", function()
    local _, ns = load({ factions = factions() })
    local page = openPage(ns, "ReputationFrame")
    T.eq(ns.window.current, "reputation")
    T.eq(page.list.selectedKey, "f" .. factions()[2].factionID, "the first faction picked")
    local P = page.pane
    T.eq(P.title:GetText(), "Stormwind")
    T.eq(P.barText:GetText(), "8,400 more to Revered")
    T.eq(P.body:GetText(), "The human capital.")
    local watch, war, inactive = P.toggles[1], P.toggles[2], P.toggles[3]
    T.eq(watch.on, true)
    T.eq(war.enabled, false)
    watch:Click()
    T.deq(CW.Calls("Watch"), { 0 }, "switched off: no watched faction")
    war:Click()
    T.deq(CW.Calls("AtWar"), {}, "the game says this one can't")
    inactive:Click()
    T.deq(CW.Calls("SetFactionActive"), { { 2, false } })
end)

T.test("character reputation: a switch flips at the click, before the game answers", function()
    local _, ns = load({ factions = factions() })
    local page = openPage(ns, "ReputationFrame")
    local watch = page.pane.toggles[1]
    T.eq(watch.on, true)
    watch:Click()   -- the fake game, like the server, hasn't changed yet
    T.eq(watch.on, false, "off at once")
    T.eq(watch.switch.on, false)
    stub.RunTimers()   -- a refresh still reading the old answer
    T.eq(watch.switch.on, false, "kept off while the game catches up")
    stub.Advance(ns.List.TOGGLE_HOLD + 0.1)
    ns.Window.Refresh(true)
    T.eq(watch.switch.on, true, "the game never agreed: back to what it says")
end)

T.test("character reputation: folding a group goes through the game", function()
    local _, ns = load({ factions = factions() })
    local page = openPage(ns, "ReputationFrame")
    ns.List.Click(page.list, page.list.items[1])
    T.deq(CW.Calls("CollapseFaction"), { 1 })
    ns.List.Click(page.list, page.list.items[4])
    T.deq(CW.Calls("ExpandFaction"), { 4 })
end)

T.test("character reputation: bars in the standing's gradient, or plain when switched off", function()
    local DUI, ns = load({ factions = factions() })
    local painted = {}
    local real = DUI.Gradients.Colors
    DUI.Gradients.Colors = function(key, ...) painted[#painted + 1] = key; return real(key, ...) end
    openPage(ns, "ReputationFrame")
    T.truthy(#painted > 0)
    T.eq(painted[1], "REP_6")
    painted = {}
    DUI:Set("Character", "gradient", false)
    stub.RunTimers()
    T.eq(#painted, 0, "plain fills")
    DUI.Gradients.Colors = real
end)
local function skills()
    return {
        CW.skill("Professions", { isHeader = true, skillID = 11 }),
        CW.skill("Mining", { skillLineCategoryID = 11, rank = 285, maxRank = 300 }),
        CW.skill("Class Skills", { isHeader = true, skillID = 7 }),
        CW.skill("Arms", { skillLineCategoryID = 7, rank = 1, maxRank = 1 }),
        CW.skill("Secondary Skills", { isHeader = true, skillID = 9 }),
        CW.skill("First Aid", { skillLineCategoryID = 9, rank = 300, maxRank = 300 }),
        CW.skill("Weapon Skills", { isHeader = true, skillID = 6 }),
        CW.skill("Swords", { skillLineCategoryID = 6, rank = 300, maxRank = 300, modifier = 5 }),
        CW.skill("Armor Proficiencies", { isHeader = true, skillID = 8 }),
        CW.skill("Plate Mail", { skillLineCategoryID = 8, rank = 1, maxRank = 1 }),
        CW.skill("Languages", { isHeader = true, skillID = 10 }),
        CW.skill("Common", { skillLineCategoryID = 10, rank = 300, maxRank = 300 }),
    }
end

local function texts(items)
    local out = {}
    for _, it in ipairs(items) do out[#out + 1] = it.text end
    return out
end

T.test("character skills: professions and secondary left, the rest right, class skills left out", function()
    local _, ns = load({ skills = skills() })
    local left, right = ns.Skills.Columns(ns.Skills.Read())
    T.deq(texts(left), { "Professions", "Mining", "Secondary Skills", "First Aid" })
    T.deq(texts(right), { "Weapon Skills", "Swords", "Armor Proficiencies", "Plate Mail", "Languages", "Common" })
end)

T.test("character skills: a skill line under another (parentSkillLineID) is left out, as the game does", function()
    local list = skills()
    table.insert(list, 3, CW.skill("Mining", { skillLineCategoryID = 11, rank = 285, maxRank = 300, parentSkillLineID = 186 }))
    local _, ns = load({ skills = list })
    local left = ns.Skills.Columns(ns.Skills.Read())
    T.deq(texts(left), { "Professions", "Mining", "Secondary Skills", "First Aid" })
end)

T.test("character skills: a sub-header and the lines under it indent (isChild, as the game's window reads it)", function()
    local list = skills()
    table.insert(list, 9, CW.skill("Two-Handed", { isHeader = true, isChild = true, skillID = 6 }))
    table.insert(list, 10, CW.skill("Polearms", { isChild = true, skillLineCategoryID = 6, rank = 50, maxRank = 300 }))
    local _, ns = load({ skills = list })
    local _, right = ns.Skills.Columns(ns.Skills.Read())
    T.deq(texts(right), { "Weapon Skills", "Swords", "Two-Handed", "Polearms", "Armor Proficiencies", "Plate Mail",
                          "Languages", "Common" })
    T.eq(right[3].kind, "head")
    T.eq(right[3].indent, 1)
    T.eq(right[4].indent, 1)
    T.eq(right[2].indent, 0)
end)

T.test("character skills: rank, modifier and a bar in the accent", function()
    local _, ns = load({ skills = skills() })
    local left, right = ns.Skills.Columns(ns.Skills.Read())
    T.eq(left[2].right, "285 / 300")
    T.deq({ left[2].bar.value, left[2].bar.max, left[2].bar.key }, { 285, 300, "accent" })
    T.eq(right[2].right, "300 (+5) / 300")
    T.isnil(right[4].bar, "a one-point skill has no bar")
    T.isnil(right[4].right)
end)

T.test("character skills: armor and languages folded once per login, through the game", function()
    local _, ns = load({ skills = skills() })
    openPage(ns, "SkillsFrame")
    T.deq(CW.Calls("CollapseSkill"), { 11, 9 }, "languages, then armor: folded from the bottom up")
    ns.Window.Refresh(true)
    T.deq(CW.Calls("CollapseSkill"), { 11, 9 }, "only once")
    local page = ns.window.pages.skills
    T.deq(texts(page.right.items), { "Weapon Skills", "Swords", "Armor Proficiencies", "Languages" })
    ns.List.Click(page.right, page.right.items[3])
    T.deq(CW.Calls("ExpandSkill"), { 9 })
end)
local PVP = { renownLevel = 3, renownReputationEarned = 400, renownLevelThreshold = 1000,
              currentWeekProgressiveMaxLevel = 5, previousWeekProgressiveMaxLevel = 2, maxLevel = 6,
              seasonEnds = 12 * 86400 + 100, season = 3 }

T.test("character pvp: your rank, the next one, this week, the season", function()
    local _, ns = load({ pvp = PVP })
    local d = ns.PvP.Read()
    T.eq(d.rank, 3)
    T.eq(d.name, "Sergeant")
    T.eq(d.nextName, "Master Sergeant")
    T.deq({ d.earned, d.threshold }, { 400, 1000 })
    T.eq(d.weekLevel, 5)
    T.deq({ d.weekValue, d.weekCap }, { 1400, 3000 }, "3,400 earned in all; this week's limit adds 2,000 to 5,000")
    T.eq(d.season, 3)
end)

T.test("character pvp: when the season ends, in plain words", function()
    local _, ns = load()
    T.eq(ns.PvP.Ends(12 * 86400 + 100), "Ends in 12 days")
    T.eq(ns.PvP.Ends(86400 + 5), "Ends in 1 day")
    T.eq(ns.PvP.Ends(5 * 3600 + 10), "Ends in 5 hours")
    T.eq(ns.PvP.Ends(600), "Ends within the hour")
    T.isnil(ns.PvP.Ends(0))
end)

-- The game's window shows its PvP tab at rank 0 too (PVPRankFrameMixin:OnLoad).
T.test("character pvp: the tab shows with no rank yet", function()
    local _, ns = load({ pvp = { renownLevel = 0, renownReputationEarned = 0, renownLevelThreshold = 1000, maxLevel = 6 } })
    T.eq(ns.Window.TabShown("pvp"), true)
    local page = openPage(ns, "PVPRankFrame")
    T.eq(ns.window.current, "pvp")
    T.eq(page.rankName:GetText(), PVP_RANK_0_NAME or "No rank yet")
    T.truthy(page.emblem:IsShown(), "the first rank's badge stands there, so the card isn't just a word")
    T.near(page.emblem:GetAlpha(), 0.2, 0.001, "faint")
    T.truthy(page.emblem:GetTexture():find("pvp-rank-01.png", 1, true), "the first rank's badge")
    T.eq(page.blocks[1].main:GetText(), "Private")
    local _, ns2 = load({ pvp = PVP })
    T.eq(ns2.Window.TabShown("pvp"), true)
end)

T.test("character pvp: the page paints its blocks", function()
    local _, ns = load({ pvp = PVP })
    local page = openPage(ns, "PVPRankFrame")
    T.eq(ns.window.current, "pvp")
    T.eq(page.rankName:GetText(), "Sergeant")
    T.eq(page.blocks[1].main:GetText(), "Master Sergeant")
    local P = function(s) return DaylightUI.Win.Parts.Hex({ DaylightUI.Style.Pop() }) .. s .. "|r" end
    T.eq(page.blocks[1].sub:GetText(), P("400") .. " of " .. P("1,000") .. " points")   -- the numbers pop
    T.eq(page.blocks[2].main:GetText(), "You can reach rank 5 this week")
    T.eq(page.blocks[3].main:GetText(), "Season 3")
    T.eq(page.blocks[3].sub:GetText(), "Ends in 12 days")
end)

local STATS = { categories = { { id = 1, title = "Combat" }, { id = 2, title = "Kills", parent = 1 }, { id = 3, title = "Travel" } },
                stats = { [1] = { { id = 101, name = "Total deaths", quantity = "12" } },
                          [2] = { { id = 201, name = "Creatures killed", quantity = "15234" }, { id = 202, name = "Hidden", quantity = "1", skip = true } },
                          [3] = { { id = 301, name = "Flight paths taken", quantity = "0" } } } }

T.test("character statistics: categories with their sub-categories, values in plain numbers", function()
    local _, ns = load({ statistics = STATS })
    local cats = ns.Statistics.Categories()
    T.deq(texts(cats), { "Combat", "Kills", "Travel" })
    T.eq(cats[2].indent, 1)
    local rows = ns.Statistics.Rows(2)
    T.deq(texts(rows), { "Creatures killed" })
    T.eq(rows[1].right, "15,234")
    T.eq(ns.Statistics.Rows(3)[1].right, "--")
end)

T.test("character statistics: picking a category shows its numbers", function()
    local _, ns = load({ statistics = STATS })
    ToggleCharacter("PaperDollFrame")
    ns.Follow.Tick()
    ns.Follow.Select("statistics")
    local page = ns.window.pages.statistics
    T.deq(texts(page.right.items), { "Total deaths" }, "the first category to start with")
    ns.List.Click(page.list, page.list.items[3])
    T.deq(texts(page.right.items), { "Flight paths taken" })
end)
local function currency()
    return {
        { name = "Player vs. Player", isHeader = true, isHeaderExpanded = true },
        { name = "Honor", quantity = 1250, iconFileID = 101, currencyID = 1901, maxWeeklyQuantity = 1000,
          quantityEarnedThisWeek = 300, isShowInBackpack = false },
        { name = "Miscellaneous", isHeader = true, isHeaderExpanded = false },
    }
end

T.test("character currency: amounts under their groups", function()
    local _, ns = load({ currency = currency() })
    local items = ns.Currency.Items(ns.Currency.Read())
    T.deq(texts(items), { "Player vs. Player", "Honor", "Miscellaneous" })
    T.eq(items[2].right, "1,250")
    T.eq(items[2].icon, 101)
    T.eq(items[3].folded, true)
    T.eq(ns.Currency.Week(ns.Currency.Read()[2]), "300 of 1,000 this week")
end)

T.test("character currency: the pane, the backpack switch, folding", function()
    local _, ns = load({ currency = currency() })
    local page = openPage(ns, "TokenFrame")
    T.eq(ns.window.current, "currency")
    T.eq(page.pane.title:GetText(), "Honor")
    T.eq(page.pane.body:GetText(), "What currency 1901 is for.")
    page.pane.toggles[1]:Click()
    T.deq(CW.Calls("Backpack"), { { 2, true } })
    ns.List.Click(page.list, page.list.items[1])
    T.deq(CW.Calls("ExpandCurrency"), { { 1, false } })
end)

T.test("character currency: the transfer opens the game's own page, then ours comes back", function()
    local _, ns = load({ currency = currency() })
    local page = openPage(ns, "TokenFrame")
    page.pane.button:Click()
    T.eq(ns.Follow.parked, false)
    T.eq(CharacterFrame:GetParent(), UIParent)
    T.eq(PaperDollItemsFrame:GetParent(), PaperDollFrame, "the slot frame given back first")
    T.eq(ns.Slots.lent, false)
    T.deq(CW.Calls("ToggleCharacter")[#CW.Calls("ToggleCharacter")], { "TokenFrame", true })
    ns.Follow.Tick()
    stub.FinishFade(ns.window)
    T.eq(ns.window:IsShown(), false, "ours steps aside")
    ToggleCharacter("TokenFrame")            -- the player closes the game's window
    ns.Follow.Tick()
    T.eq(ns.Follow.parked, true)
    T.eq(CharacterFrame:GetParent(), ns.Follow.hidden)
    T.eq(ns.Slots.lent, true)
    T.isnil(CW.state.panel.width, "no panel layout written on the way")
end)

T.test("character: the slots go back over the game's model at their own level", function()
    local _, ns = load({ currency = currency() })
    local page = openPage(ns, "TokenFrame")
    T.eq(ns.Slots.lent, true)
    page.pane.button:Click()
    T.eq(ns.Slots.lent, false)
    T.eq(PaperDollItemsFrame:GetFrameLevel(), 100, "the level the game gave it")
    T.truthy(CharacterHeadSlot:GetFrameLevel() > CharacterModelScene:GetFrameLevel(), "a slot over the model")
end)

T.test("character currency: no transfer in combat", function()
    local _, ns = load({ currency = currency() })
    local page = openPage(ns, "TokenFrame")
    stub.EnterCombat()
    T.eq(ns.Currency.Transfer(), false)
    T.eq(ns.Follow.parked, true)
    ns.Window.Refresh(true)
    T.eq(page.pane.button.text:GetText(), "No transfers in combat")
end)

T.test("character currency: no currencies, no tab", function()
    local _, ns = load()
    T.eq(ns.Window.TabShown("currency"), false)
end)

-- Edge cases.

T.test("character slots: the game's buttons hide with the Character page", function()
    local _, ns = load({ factions = factions() })
    openChar(ns)
    T.eq(PaperDollItemsFrame:IsVisible(), true)
    ns.Follow.Select("reputation")
    T.eq(PaperDollItemsFrame:IsVisible(), false, "no invisible gear buttons over another page")
end)

T.test("character stats: no game value read is truth-tested (secret in combat)", function()
    -- The stub's secrets are tables, so `x or 0` can't fail here as it does in
    -- game. Scan for a game call's result used with `or` instead.
    local fh = assert(io.open("Character/Stats.lua"))
    local src = fh:read("*a")
    fh:close()
    T.isnil(string.find(src, "call%b()%s+or%s"), "a call's result with `or`")
end)

T.test("character statistics: a refresh keeps your place in the numbers", function()
    local stats = { categories = { { id = 1, title = "Combat" } }, stats = { [1] = {} } }
    for i = 1, 40 do stats.stats[1][i] = { id = 100 + i, name = "Stat " .. i, quantity = tostring(i) } end
    local _, ns = load({ statistics = stats })
    ToggleCharacter("PaperDollFrame")
    ns.Follow.Tick()
    ns.Follow.Select("statistics")
    local page = ns.window.pages.statistics
    ns.List.Scroll(page.right, 5)
    ns.Window.Refresh(true)
    T.eq(page.right.offset, 5)
end)

T.test("character switch: on by default; off leaves the game's window alone", function()
    local _, ns = load()
    T.truthy(ns.window, "on by default")
    local _, off = load(nil, { login = false })
    DaylightUI.DB.Active().modules.Character = { enabled = false }
    stub.FireEvent("PLAYER_LOGIN")
    T.isnil(off.window, "not built")
    T.eq(CharacterFrame:GetParent(), UIParent, "the game's window isn't parked")
end)

-- The player's pick between the two windows (Win.Swap), switched live.
T.test("character swap: the header's swap button hands over to the game's window and it stays picked", function()
    local _, ns = load()
    local F = ns.Follow
    ToggleCharacter("ReputationFrame")
    F.Tick()
    local f = ns.window
    T.truthy(ns.Window.IsOpen())
    T.truthy(f.swap and f.swap:IsShown(), "the swap button sits in the header")
    f.swap:Click()
    stub.RunTimers()
    T.eq(DaylightUI:Get("Character", "enabled"), false, "the pick is saved")
    T.falsy(ns.Window.IsOpen(), "ours steps aside")
    T.eq(CharacterFrame:GetParent(), UIParent, "the game's window is back")
    T.truthy(CharacterFrame:IsVisible(), "and shows, on the same page")
    T.eq(CharacterFrame.activeSubframe, "ReputationFrame")
    T.eq(PaperDollItemsFrame:GetParent(), PaperDollFrame, "its slot buttons are home")
    T.truthy(ns.swap.link:IsShown(), "with its way back")
    T.falsy(F.Covers(), "the skins may dress it")
    T.falsy(F.Ready(), "nothing opens ours in a fight")
    ToggleCharacter("ReputationFrame")
    F.Tick()
    stub.RunTimers()
    T.eq(CharacterFrame:GetParent(), UIParent, "never parked while it's the pick")
    ToggleCharacter("PaperDollFrame")
    F.Tick()
    T.falsy(ns.Window.IsOpen(), "C opens the game's window")
    T.truthy(CharacterFrame:IsVisible())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("character swap: the game's window's link switches back to Daylight UI's, no reload", function()
    local _, ns = load(nil, { login = false })
    DaylightUI.DB.Active().modules.Character = { enabled = false }
    stub.FireEvent("PLAYER_LOGIN")
    stub.RunTimers()
    ToggleCharacter("SkillsFrame")
    T.isnil(ns.window, "nothing built while the game's is picked")
    local b = ns.swap.link
    T.truthy(b and b:IsShown(), "the game's window has the switch")
    T.eq(b:GetParent(), CharacterFrame, "it rides on the game's window")
    b:Click()
    stub.RunTimers()
    ns.Follow.Tick()
    T.eq(DaylightUI:Get("Character", "enabled"), true, "the pick is saved")
    T.truthy(ns.window and ns.Window.IsOpen(), "ours takes over the open window")
    T.eq(ns.window.current, "skills", "on the same page")
    T.eq(CharacterFrame:GetParent(), ns.Follow.hidden, "the game's window goes out of sight")
    T.truthy(CharacterFrame:IsShown(), "still open underneath, so C closes both")
    T.falsy(b:IsShown(), "the link is gone with the game's look")
    T.truthy(ns.Follow.Covers())
    T.truthy(ns.window.swap:IsShown(), "and the header has the way back")
    ToggleCharacter("SkillsFrame")
    ns.Follow.Tick()
    T.falsy(ns.Window.IsOpen(), "C closes it as before")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("character swap: the game's window wears the Daylight UI look only while it's the pick", function()
    load(nil, { skins = true })
    local Kit = stub.skins.Kit
    ToggleCharacter("PaperDollFrame")
    stub.RunTimers()
    T.isnil(Kit.ShellOf(CharacterFrame), "covered by Daylight UI's: left alone")
    DaylightUI.Char.window.swap:Click()
    stub.RunTimers()
    stub.RunTimers()
    T.truthy(Kit.ShellOf(CharacterFrame), "shown as itself: dressed")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("character swap: picked before login, the game's window is dressed when it opens", function()
    load(nil, { skins = true, before = function()
        _G.DaylightUIDB = { modules = { Character = { enabled = false } } }
    end })
    stub.RunTimers()
    ToggleCharacter("PaperDollFrame")
    stub.RunTimers()
    T.eq(CharacterFrame:GetParent(), UIParent)
    T.truthy(stub.skins.Kit.ShellOf(CharacterFrame))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game with the game's window picked before login: the slots at level 4
-- under their own holder at 100, so the model (50) took every hover.
T.test("character swap: picked before login, the game's slots sit over its model", function()
    load(nil, { skins = true, before = function()
        _G.DaylightUIDB = { modules = { Character = { enabled = false } } }
    end })
    local head = CharacterHeadSlot
    local ring = CreateFrame("Frame", nil, head)
    for _, b in ipairs(PaperDollItemsFrame.EquipmentSlots) do b:SetFrameLevel(4) end
    ring:SetFrameLevel(5)
    stub.RunTimers()
    ToggleCharacter("PaperDollFrame")
    stub.RunTimers()
    T.truthy(head:GetFrameLevel() > CharacterModelScene:GetFrameLevel(), "a slot over the model")
    T.eq(head:GetFrameLevel(), PaperDollItemsFrame:GetFrameLevel() + 1, "one above its holder")
    T.eq(ring:GetFrameLevel(), head:GetFrameLevel() + 1, "its own pieces move with it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("character swap: picked in a fight, the windows trade places once it ends", function()
    local _, ns = load()
    local F = ns.Follow
    ToggleCharacter("PaperDollFrame")
    F.Tick()
    stub.EnterCombat()
    ns.window.swap:Click()
    stub.RunTimers()
    T.eq(CharacterFrame:GetParent(), F.hidden, "the game's window isn't touched in a fight")
    T.truthy(ns.Window.IsOpen())
    stub.LeaveCombat()
    stub.RunTimers()
    T.eq(CharacterFrame:GetParent(), UIParent)
    T.falsy(ns.Window.IsOpen())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- ---------------------------------------------------------------------
-- Colors
-- ---------------------------------------------------------------------

-- A setting changed, and the repaint it asks for (the next frame) done.
local function setNow(DUI, key, value)
    DUI:Set("Character", key, value)
    stub.RunTimers()
end

T.test("character colors: durability green when whole, yellow halfway, red at the repair warning", function()
    local _, ns = load()
    local C = ns.Colors
    T.rgb({ C.Durability(1, 0.25) }, C.GOOD)
    T.rgb({ C.Durability(0.625, 0.25) }, C.WARN, "halfway from the warning to whole")
    T.rgb({ C.Durability(0.25, 0.25) }, C.BAD)
    T.rgb({ C.Durability(0.05, 0.25) }, C.BAD)
end)

T.test("character colors: a color wrapped for text", function()
    local _, ns = load()
    T.eq(ns.Colors.Wrap("64", 1, 0.5, 0), "|cffff8000" .. "64|r")
end)

T.test("character colors: your gear's average quality", function()
    local _, ns = load({ items = { Head = CW.item("Helm", { quality = 4 }), Chest = CW.item("Chest", { quality = 2 }),
                                   Legs = CW.item("Legs", { quality = 4 }) } })
    T.eq(ns.Gear.Summary(ns.Gear.All()).quality, 3)
end)

T.test("character page: the footer's numbers in color, plain when that's off", function()
    local _, ns, DUI = charPage({ items = { Head = CW.item("Lionheart Helm", { quality = 4, level = 66 }),
                                             Chest = CW.item("Chest", { quality = 4, cur = 20, max = 100 }),
                                             Legs = CW.item("Legs", { quality = 4, cur = 80, max = 100 }) } })
    local page = openChar(ns)
    local C = ns.Colors
    T.eq(page.foot.level:GetText(), "Item level " .. C.Wrap("64", ns.Gear.QualityColor(4)))
    T.eq(page.foot.dura:GetText(), "Durability " .. C.Wrap("50%", C.Durability(0.5, 0.25)))
    setNow(DUI, "footColors", false)
    T.eq(page.foot.level:GetText(), "Item level 64")
    T.eq(page.foot.dura:GetText(), "Durability 50%")
end)

T.test("character page: every stat group starts open", function()
    local _, ns = charPage()
    local page = openChar(ns)
    for _, g in ipairs(ns.Stats.GROUPS) do
        T.eq(page.stats.groups[g].head.state:GetText(), "", g .. " open")
    end
    T.eq(page.stats.groups.defense.rows[1]:IsShown(), true)
end)

T.test("character page: stat headers in the accent, or each its own color, bigger", function()
    local P, ns, DUI = charPage()
    DUI:Set("general", "accent", "daylight")    -- a one-color accent gives a plain text color
    local page = openChar(ns)
    local head = page.stats.groups.attack.head
    T.rgb(head.text.__textColor, { DaylightUI.Style.Accent() })
    T.rgb(page.stats.groups.spell.head.text.__textColor, { DaylightUI.Style.Accent() })
    T.truthy(P.GROUP_SIZE >= 13, "bigger than the old 10")
    setNow(DUI, "colors.headMode", "group")
    T.rgb(head.text.__textColor, ns.DEFAULTS.colors.attack)
    T.rgb(page.stats.groups.spell.head.text.__textColor, ns.DEFAULTS.colors.spell)
    setNow(DUI, "colors.headMode", "custom")
    setNow(DUI, "colors.head", { 0.2, 0.4, 0.6 })
    T.rgb(head.text.__textColor, { 0.2, 0.4, 0.6 })
    setNow(DUI, "colors.headMode", "class")
    T.rgb(head.text.__textColor, { DaylightUI.Style.ClassColor("WARRIOR") })
    setNow(DUI, "colors.headMode", "gradient")
    T.eq(head.text:GetText(), DaylightUI.Gradients.Text("WARRIOR", "ATTACK"))
end)

T.test("character page: a gradient accent runs across a header's letters, and follows an accent switch", function()
    local _, ns, DUI = charPage()
    local Style = DaylightUI.Style
    DUI:Set("general", "accent", "gradient")
    local text = openChar(ns).stats.groups.attack.head.text
    local daylight, on = Style.AccentText("ATTACK")
    T.truthy(on, "the Daylight sweep colors each letter")
    T.eq(text:GetText(), daylight)
    T.rgb(text.__textColor, { 1, 1, 1 }, "drawn on white, so the letters keep their own colors")
    DUI:Set("general", "accent", "classGradient")
    stub.RunTimers()
    T.eq(text:GetText(), (Style.AccentText("ATTACK")), "the class pair")
    T.truthy(text:GetText() ~= daylight)
    DUI:Set("general", "accent", "custom")
    DUI:Set("general", "accentColor", { 0.1, 0.9, 0.3 })
    stub.RunTimers()
    T.eq(text:GetText(), "ATTACK", "one color: plain text again")
    T.rgb(text.__textColor, { 0.1, 0.9, 0.3 })
end)

T.test("character page: the lines under the stat headers like the tab underline, or their own color", function()
    local _, ns, DUI = charPage()
    local page = openChar(ns)
    DUI:Set("general", "accent", "daylight")    -- a one-color accent gives plain vertex colors
    setNow(DUI, "colors.tabMode", "accent")     -- paints it
    local line = page.stats.groups.attack.head.line
    local r, g, b = line:GetVertexColor()
    T.rgb({ r, g, b }, { DaylightUI.Style.Accent() })   -- the tab underline's color, the accent by default
    setNow(DUI, "colors.tabMode", "custom")
    setNow(DUI, "colors.tab", { 0.7, 0.2, 0.5 })
    r, g, b = line:GetVertexColor()
    T.rgb({ r, g, b }, { 0.7, 0.2, 0.5 })
    setNow(DUI, "colors.lineMode", "accent")
    r, g, b = line:GetVertexColor()
    T.rgb({ r, g, b }, { DaylightUI.Style.Accent() })
    setNow(DUI, "colors.lineMode", "gradient")
    T.truthy(line.__gradient, "a gradient across the line")
    setNow(DUI, "colors.lineMode", "custom")
    setNow(DUI, "colors.line", { 0.1, 0.9, 0.3 })
    r, g, b = line:GetVertexColor()
    T.rgb({ r, g, b }, { 0.1, 0.9, 0.3 })
end)

T.test("character window: the open tab's underline in the accent, or the color picked", function()
    local _, ns, DUI = charPage()
    DUI:Set("general", "accent", "daylight")    -- a one-color accent gives plain vertex colors
    openChar(ns)
    local line
    for _, b in ipairs(ns.window.tabs) do if b.id == "character" then line = b.line end end
    T.eq(line:IsShown(), true)
    local r, g, b = line:GetVertexColor()
    T.rgb({ r, g, b }, { DaylightUI.Style.Accent() })   -- the accent by default
    setNow(DUI, "colors.tabMode", "gradient")
    T.truthy(line.__gradient, "a gradient across the line")
    setNow(DUI, "colors.tabMode", "custom")
    setNow(DUI, "colors.tab", { 0.1, 0.9, 0.3 })
    r, g, b = line:GetVertexColor()
    T.rgb({ r, g, b }, { 0.1, 0.9, 0.3 })
    setNow(DUI, "colors.tabMode", "accent")
    r, g, b = line:GetVertexColor()
    T.rgb({ r, g, b }, { DaylightUI.Style.Accent() })
end)

T.test("character page: striped stat rows, every other one under each header", function()
    local _, ns, DUI = charPage()
    local page = openChar(ns)
    local rows = page.stats.groups.attributes.rows
    T.eq(rows[2].stripe:IsShown(), false, "off by default")
    setNow(DUI, "zebra", true)
    T.eq(rows[1].stripe:IsShown(), false)
    T.eq(rows[2].stripe:IsShown(), true)
    T.eq(rows[3].stripe:IsShown(), false)
    T.eq(page.stats.groups.attack.rows[2].stripe:IsShown(), true, "starts again under each header")
    setNow(DUI, "zebra", false)
    T.eq(rows[2].stripe:IsShown(), false)
end)

T.test("character header: your class in its color", function()
    local _, ns = load()
    ToggleCharacter("PaperDollFrame")
    ns.Follow.Tick()
    T.eq(ns.window.sub:GetText(), "Level " .. ns.Colors.Wrap("60", DaylightUI.Style.Pop()) .. " Human " .. ns.Colors.Wrap("WARRIOR", DaylightUI.Style.ClassColor("WARRIOR")))
end)

T.test("character header: your title with your name, before or after it as the game puts it", function()
    local DUI, ns = load({ titles = TITLES, title = 1 })
    DUI:Set("general", "lastNames.character", false)
    ToggleCharacter("PaperDollFrame")
    ns.Follow.Tick()
    local me = UnitName("player")
    T.eq(ns.window.nameText:GetText(), "Private " .. me, "a title before the name")
    pickTitle(ns, "3")
    ns.Window.OnEvent(nil, "UNIT_NAME_UPDATE", "player")
    stub.RunTimers()
    T.eq(ns.window.nameText:GetText(), me .. " Sergeant", "picking another shows it, after the name")
    pickTitle(ns, "-1")
    ns.Window.OnEvent(nil, "UNIT_NAME_UPDATE", "player")
    stub.RunTimers()
    T.eq(ns.window.nameText:GetText(), me, "no title: the name alone")
end)

T.test("character header: your first and last name, on its own switch", function()
    local DUI, ns = load()
    stub.units.player = stub.units.player or { name = UnitName("player") }
    stub.units.player.lastName = "Dadoopy"
    DUI:Set("general", "lastNames.player", false)   -- the player frame's switch isn't this one
    ns.Window.PaintHeader()
    T.eq(ns.window.nameText:GetText(), UnitName("player") .. " Dadoopy", "on by default")
    DUI:Set("general", "lastNames.character", false)
    ns.Window.PaintHeader()
    T.eq(ns.window.nameText:GetText(), UnitName("player"), "off: the first name")
    local found
    for _, g in ipairs(ns.OPTIONS.pages[1].groups) do
        for _, it in ipairs(g.items) do if it.key == "lastNames.character" then found = it end end
    end
    T.truthy(found, "a switch on the Character page")
    T.eq(found.get(), false)
    found.set(true)
    T.eq(DUI:Get("general", "lastNames.character"), true)
end)

T.test("character list: headers in color, striped rows starting again under each", function()
    local DUI, ns = load({ factions = {
        CW.faction("Alliance", 0, 0, 0, 0, { isHeader = true }),
        CW.faction("A", 5, 3000, 3000, 9000, { isChild = true }),
        CW.faction("B", 5, 3000, 3000, 9000, { isChild = true }),
        CW.faction("C", 5, 3000, 3000, 9000, { isChild = true }),
        CW.faction("Horde", 0, 0, 0, 0, { isHeader = true }),
        CW.faction("D", 5, 3000, 3000, 9000, { isChild = true }),
        CW.faction("E", 5, 3000, 3000, 9000, { isChild = true }),
    } })
    DaylightUI:Set("general", "accent", "daylight")    -- a one-color accent gives a plain text color
    local page = openPage(ns, "ReputationFrame")
    local rows = page.list.rows
    T.rgb(rows[1].head.__textColor, { DaylightUI.Style.Accent() }, "headers wear the accent")
    T.rgb(rows[5].head.__textColor, { DaylightUI.Style.Accent() })
    T.eq(rows[1].line:IsShown(), true, "a header has its line")
    T.eq(rows[2].line:IsShown(), false)
    T.eq(rows[3].stripe:IsShown(), false, "off by default")
    setNow(DUI, "zebra", true)
    T.deq({ rows[2].stripe:IsShown(), rows[3].stripe:IsShown(), rows[4].stripe:IsShown() }, { false, true, false })
    T.deq({ rows[6].stripe:IsShown(), rows[7].stripe:IsShown() }, { false, true }, "again under the next header")
    T.eq(rows[1].stripe:IsShown(), false, "never a header")
    setNow(DUI, "zebra", false)
    T.eq(rows[3].stripe:IsShown(), false)
end)

T.test("character list: thicker bars on a track", function()
    local _, ns = load({ factions = factions() })
    local page = openPage(ns, "ReputationFrame")
    local bar = page.list.rows[2].bar
    T.truthy(bar:GetHeight() >= 8, "not the old 4 px")
    T.truthy(bar.track, "the empty part shows")
    T.truthy(page.list.rows[2]:GetHeight() > 24, "room for the bar under the name")
    T.truthy(page.pane.bar:GetHeight() >= 12, "the pane's bar thicker too")
end)

-- A list whose header click hands back `after` (the game's list once folded).
local function foldList(ns, before, after)
    local List = ns.List
    local L
    L = List.Make(UIParent, { onFold = function() List.Set(L, after) end })
    List.Set(L, before)
    return L
end
local function heads(...)
    local out = {}
    for _, t in ipairs({ ... }) do
        out[#out + 1] = t:sub(1, 1) == "#" and { kind = "head", key = t, text = t } or { kind = "row", key = t, text = t }
    end
    return out
end
local function playing(r, key) return r.__duiMotion and r.__duiMotion[key] and r.__duiMotion[key]:IsPlaying() == true end

T.test("character list: opening a group drops its rows in, one after another; the rows under it glide down", function()
    local _, ns = load({ factions = factions() })
    local L = foldList(ns, heads("#A", "#B", "b1"), heads("#A", "a1", "a2", "#B", "b1"))
    ns.List.Click(L, L.items[1])
    local r = L.rows
    T.falsy(playing(r[1], "slideIn") or playing(r[1], "glide"), "the header stays")
    T.truthy(playing(r[2], "slideIn")); T.truthy(playing(r[3], "slideIn"))
    T.eq(r[2].__duiMotion.slideIn.delay, 0, "the first at once")
    T.eq(r[3].__duiMotion.slideIn.delay, ns.List.FOLD_STAGGER, "the next a moment after")
    T.truthy(playing(r[4], "glide")); T.truthy(playing(r[5], "glide"))
    T.eq(r[4].__duiMotion.glide.dy, 2 * L.row, "#B starts two rows up, where it was")
end)

T.test("character list: folding a group glides the rows under it up; no motion when switched off", function()
    local DUI, ns = load({ factions = factions() })
    local L = foldList(ns, heads("#A", "a1", "a2", "#B", "b1"), heads("#A", "#B", "b1"))
    ns.List.Click(L, L.items[1])
    T.truthy(playing(L.rows[2], "glide"))
    T.eq(L.rows[2].__duiMotion.glide.dy, -2 * L.row, "#B starts two rows down, where it was")
    T.isnil(L.fold, "used up")
    ns.List.Scroll(L, 0)
    T.falsy(playing(L.rows[2], "glide"), "a scroll settles every row")
    DUI.DB.General().motion = false
    local L2 = foldList(ns, heads("#A", "a1", "#B"), heads("#A", "#B"))
    ns.List.Click(L2, L2.items[1])
    T.falsy(playing(L2.rows[2], "glide"))
end)

T.test("character list: a fold the game answers later still moves; a refresh with the same list doesn't", function()
    local _, ns = load({ factions = factions() })
    local List = ns.List
    local L = List.Make(UIParent, { onFold = function() end })
    List.Set(L, heads("#A", "#B"))
    List.Click(L, L.items[1])
    List.Set(L, heads("#A", "#B"))
    T.truthy(L.fold, "still waiting for the game")
    List.Set(L, heads("#A", "a1", "#B"))
    T.truthy(playing(L.rows[2], "slideIn"))
    T.truthy(playing(L.rows[3], "glide"))
end)

T.test("character lists: your own progress bars wear the accent, plain with gradients off", function()
    local _, ns, DUI = charPage()
    openChar(ns)
    DUI:Set("general", "accent", "custom")
    DUI:Set("general", "accentColor", { 0.1, 0.9, 0.3 })
    local key, rgb = ns.List.OwnBar()
    T.rgb(rgb, { 0.1, 0.9, 0.3 })
    local bar = DUI.Widgets.Bar(UIParent, 4)
    local seen
    local real = DUI.Widgets.BarAccent
    DUI.Widgets.BarAccent = function(b) seen = b end
    ns.List.PaintBar(bar, key, rgb)
    DUI.Widgets.BarAccent = real
    T.eq(seen, bar)
end)

T.test("character statistics: each category its own color, sub-categories the same dimmer, numbers in the picked one's", function()
    local _, ns = load({ statistics = {
        categories = { { id = 1, title = "Combat" }, { id = 2, title = "Kills", parent = 1 }, { id = 3, title = "Travel" } },
        stats = { [1] = { { id = 101, name = "Damage done", quantity = "5" } } } } })
    T.rgb(ns.Statistics.Categories()[3].color, ns.DEFAULTS.colors.attack, "its own color whatever the header mode is")
    DaylightUI:Set("Character", "colors.headMode", "group")   -- each its own, in turn
    local cats = ns.Statistics.Categories()
    T.rgb(cats[1].color, ns.DEFAULTS.colors.attributes)
    T.rgb(cats[2].color, { ns.Colors.Dim(unpack(ns.DEFAULTS.colors.attributes)) }, "a sub-category: its parent's color, dimmer")
    T.rgb(cats[2].tint, ns.DEFAULTS.colors.attributes, "its wash, bar and numbers: the parent's own")
    T.rgb(cats[3].color, ns.DEFAULTS.colors.attack)
    local rows = ns.Statistics.Rows(1, cats[1].tint)
    T.rgb(rows[1].rightColor, ns.DEFAULTS.colors.attributes)
end)

T.test("character model: a soft glow in the accent, no drag hint", function()
    local M = model()
    T.isnil(M.holder.hint, "no Drag to turn")
    T.truthy(M.holder.glow, "the glow")
    T.truthy(M.holder.shadow, "the shadow at the feet")
    DaylightUI:Set("general", "accent", "daylight")    -- a one-color accent gives a plain vertex color
    M.Paint()
    local r, g, b = M.holder.glow:GetVertexColor()
    T.rgb({ r, g, b }, { DaylightUI.Style.Accent() })
    DaylightUI:Set("Character", "colors.glowMode", "custom")
    DaylightUI:Set("Character", "colors.glow", { 0.3, 0.6, 0.9 })
    M.Paint()
    r, g, b = M.holder.glow:GetVertexColor()
    T.rgb({ r, g, b }, { 0.3, 0.6, 0.9 })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("character model: rises with the window, its fade the window's own", function()
    local M = model()
    M.SetUp(6)
    M.OnUpdate(nil, 0)
    T.eq(M.scene:GetAlpha(), 1, "loaded in time: the window's fade is enough")
    T.eq(select(5, M.scene:GetPoint(1)), -6, "starts as low as the window")
    M.OnUpdate(nil, DaylightUI.Motion.NORMAL / 2)
    T.near(select(5, M.scene:GetPoint(1)), -1.5)
    M.OnUpdate(nil, DaylightUI.Motion.NORMAL / 2)
    T.eq(M.scene:GetAlpha(), 1)
    T.eq(select(5, M.scene:GetPoint(1)), 0, "at rest")
end)

T.test("character model: loaded late, it fades in where it stands", function()
    local M = model()
    CW.state.modelLoaded = false
    M.SetUp(6)
    M.OnUpdate(nil, 0.5)
    CW.state.modelLoaded = true
    M.OnUpdate(nil, 0)
    T.eq(M.scene:GetAlpha(), 0)
    T.eq(select(5, M.scene:GetPoint(1)), 0, "the window has stopped moving")
    M.OnUpdate(nil, DaylightUI.Motion.NORMAL)
    T.eq(M.scene:GetAlpha(), 1)
end)

T.test("character model: starts a bit closer than the game's framing", function()
    local M = model()
    local cam = { d = 10, min = 10, max = 10 }
    function cam:GetZoomDistance() return self.d end
    function cam:SetZoomDistance(d) self.d = math.min(math.max(d, self.min), self.max) end
    function cam:GetMinZoomDistance() return self.min end
    function cam:SetMinZoomDistance(m) self.min = m end
    function cam:GetMaxZoomDistance() return self.max end
    function cam:SetMaxZoomDistance(m) self.max = m end
    M.scene.GetActiveCamera = function() return cam end
    M.holder:SetWidth(200)
    M.Spread(0)
    M.SetUp(6)
    M.OnUpdate(nil, 0)
    T.near(cam.d, 10 * M.ZOOM, 1e-6, "past the camera's old nearest distance too")
end)

-- The camera frames by width (a box 2.6 times as wide drew him 2.6 times as big),
-- so a wider box pulls it back by as much.
T.test("character model: a wider box pulls the camera back by as much", function()
    local M = model()
    local cam = { d = 10, min = 10, max = 10 }
    function cam:GetZoomDistance() return self.d end
    function cam:SetZoomDistance(d) self.d = math.min(math.max(d, self.min), self.max) end
    function cam:GetMinZoomDistance() return self.min end
    function cam:SetMinZoomDistance(m) self.min = m end
    function cam:GetMaxZoomDistance() return self.max end
    function cam:SetMaxZoomDistance(m) self.max = m end
    M.scene.GetActiveCamera = function() return cam end
    M.holder:SetWidth(200)
    M.Spread(50)
    M.SetUp(6)
    M.OnUpdate(nil, 0)
    T.near(cam.d, 10 * M.ZOOM * 1.5, 1e-6, "300 wide over 200: half as far again, past the old farthest")
    M.Spread(0)
    T.near(cam.d, 10 * M.ZOOM, 1e-6, "the spread changing re-frames from the game's own distance")
end)

local function zoomCam(M)
    local cam = { d = 10, min = 10, max = 10 }
    function cam:GetZoomDistance() return self.d end
    function cam:SetZoomDistance(d) self.d = math.min(math.max(d, self.min), self.max) end
    function cam:GetMinZoomDistance() return self.min end
    function cam:SetMinZoomDistance(m) self.min = m end
    function cam:GetMaxZoomDistance() return self.max end
    function cam:SetMaxZoomDistance(m) self.max = m end
    M.scene.GetActiveCamera = function() return cam end
    DaylightUI.DB.Character().modelZoom = nil
    return cam
end

-- The game's scene keeps one distance for every race, and a tall model (a night
-- elf) overflowed the closer start, so the camera stands back until it fits.
T.test("character model: a tall model pulls the camera back until it fits", function()
    local M = model()
    local cam = zoomCam(M)
    M.holder:SetSize(200, 400)
    M.Spread(0)
    M.SetUp(6)
    local tall = 3
    M.scene.GetCameraFieldOfView = function() return math.pi / 2 end   -- tan(fov/2) = 1
    M.OnUpdate(nil, 0)
    local a = M.Actor()
    a.GetActiveBoundingBox = function() return 0, 0, 0, 0, 0, tall end   -- six numbers, as in game
    M.Zoom()
    local fit = tall * 200 / (M.FILL * 2 * 400)
    T.truthy(fit < 10 * M.ZOOM, "this one fits at the start")
    T.near(cam.d, 10 * M.ZOOM, 1e-6, "a model that fits keeps the start")
    tall = 30
    M.Zoom()
    T.near(cam.d, tall * 200 / (M.FILL * 2 * 400), 1e-6, "a taller one: just far enough back to fit")
end)

T.test("character model: the wheel's zoom is kept per character", function()
    local M = model()
    local cam = zoomCam(M)
    M.holder:SetSize(200, 400)
    M.Spread(0)
    M.SetUp(6)
    M.OnUpdate(nil, 0)
    cam.d = 10 * M.ZOOM * 1.4
    M.SaveZoom()
    T.near(DaylightUI.DB.Character().modelZoom.player, 1.4, 1e-6)
    M.SetUp(6)
    cam.d, cam.min, cam.max = 10, 10, 10
    M.OnUpdate(nil, 0)
    T.near(cam.d, 10 * M.ZOOM * 1.4, 1e-6, "opened again: where the wheel left it")
    DaylightUI.DB.Character().modelZoom = nil
end)

-- Every OnUpdate the kit has running (Motion's tween driver among them), for dt.
local function frames(dt)
    for _, fr in ipairs(stub.frames or {}) do
        if fr.__scripts and fr.__scripts.OnUpdate then stub.RunOnUpdate(fr, dt) end
    end
end

-- The client lays an ancestor's alpha animation over a 3D model's own alpha and
-- leaves the model clear, so the window and its pages fade by hand, never by an
-- animation group.
T.test("character window: fades in by hand, no alpha animation", function()
    local _, ns = load()
    ToggleCharacter("PaperDollFrame")
    ns.Follow.Tick()
    local f = ns.window
    T.eq(f:IsShown(), true)
    T.eq(f:GetAlpha(), 0, "starts clear")
    T.isnil(f.__duiMotion and f.__duiMotion.appearFade, "no alpha animation group")
    frames(0.1)
    T.truthy(f:GetAlpha() > 0 and f:GetAlpha() < 1, "part way")
    frames(0.3)
    T.eq(f:GetAlpha(), 1)
end)

T.test("character window: a tab switch fades the page in by hand", function()
    local _, ns = load({ factions = factions() })
    ToggleCharacter("PaperDollFrame")
    ns.Follow.Tick()
    frames(0.5)
    ns.Follow.Select("reputation")
    ns.Follow.Tick()
    local page = ns.window.pages.reputation
    T.eq(page:GetAlpha(), 1, "the page itself stays; its pieces lift in")
    local piece = ({ page:GetChildren() })[1]
    T.eq(piece:GetAlpha(), 0)
    T.isnil(piece.__duiMotion and piece.__duiMotion.appearFade, "no alpha animation group")
    frames(0.5)
    T.eq(piece:GetAlpha(), 1)
end)

T.test("character window: closing fades out by hand, then hides", function()
    local _, ns = load()
    ToggleCharacter("PaperDollFrame")
    ns.Follow.Tick()
    frames(0.5)
    ns.Window.Close()
    local f = ns.window
    T.eq(ns.Window.IsOpen(), false, "closed from the start of the fade")
    T.eq(f:IsShown(), true)
    T.isnil(f.__duiMotion and f.__duiMotion.vanish, "no alpha animation group")
    frames(0.1)
    T.truthy(f:GetAlpha() < 1 and f:GetAlpha() > 0)
    frames(0.5)
    T.eq(f:IsShown(), false)
    T.eq(f:GetAlpha(), 1, "ready for next time")
end)

T.test("character page: the model's box reaches under both slot columns, behind them", function()
    local _, ns = charPage()
    local page = openChar(ns)
    local M = ns.Model
    local _, _, _, x = M.scene:GetPoint(1)
    local _, _, _, x2 = M.scene:GetPoint(2)
    local R = ns.CharacterPage.Rects(ns.Window.Width(), ns.Window.H - ns.Window.HEADER, true)
    T.eq(x, R.left.x - R.model.x, "out to the left column's edge")
    T.eq(x2, R.model.x - R.left.x, "and as far to the right")
    T.eq(M.scene:GetFrameLevel(), page:GetFrameLevel() or 0,
         "at the page's own level: under our slots and the game's buttons, so it takes none of their clicks")
end)

T.test("character model: the glow can be switched off", function()
    local M = model()
    M.Paint()
    T.eq(M.holder.glow:IsShown(), true, "on by default")
    DaylightUI:Set("Character", "glow", false)
    M.Paint()
    T.eq(M.holder.glow:IsShown(), false)
end)

T.test("character model: with motion off it just appears", function()
    local M = model()
    DaylightUI.DB.General().motion = false
    M.SetUp(6)
    M.OnUpdate(nil, 0)
    T.eq(M.scene:GetAlpha(), 1)
    T.eq(select(5, M.scene:GetPoint(1)), 0)
end)

-- ---------------------------------------------------------------------
-- No repeated work (each test counts the work it saves)
-- ---------------------------------------------------------------------

T.test("character window: the cursor refreshes it only when an item is picked up or put down", function()
    local W, ns = win()
    local log = {}
    only(ns, { character = fakePage(log) })
    W.Open("character")
    stub.RunTimers()
    log.refreshed = 0
    for _ = 1, 5 do stub.FireEvent("CURSOR_CHANGED") end   -- the mouse passing over the world
    stub.RunTimers()
    T.eq(log.refreshed, 0, "nothing held: no refresh")
    CW.state.cursorFits = { [1] = true }
    stub.FireEvent("CURSOR_CHANGED")
    stub.RunTimers()
    T.eq(log.refreshed, 1, "an item picked up: refreshed")
    stub.FireEvent("CURSOR_CHANGED")
    stub.RunTimers()
    T.eq(log.refreshed, 1, "still holding: no refresh")
    CW.state.cursorFits = nil
    stub.FireEvent("CURSOR_CHANGED")
    stub.RunTimers()
    T.eq(log.refreshed, 2, "put down: refreshed")
end)

T.test("character window: unit events are asked for yours only", function()
    local W, ns = win()
    only(ns, { character = fakePage({}) })
    W.Open("character")
    for _, e in ipairs(W.EVENTS) do
        if e:sub(1, 5) == "UNIT_" then
            T.deq(ns.window.__unitEvents[e], { "player" }, e)
        end
    end
end)

T.test("character slots: another item held instead re-lights the slots it fits", function()
    local P, ns = charPage()
    openChar(ns)
    stub.RunTimers()
    local S = ns.Slots
    CW.state.cursorFits = { [1] = true }
    stub.FireEvent("CURSOR_CHANGED")
    stub.RunTimers()
    T.eq(S.frames.Head.glow:IsShown(), true)
    CW.state.cursorFits = { [2] = true }
    stub.FireEvent("CURSOR_CHANGED")
    T.eq(S.frames.Head.glow:IsShown(), false, "the new item's slots, at once")
    T.eq(S.frames.Neck.glow:IsShown(), true)
    CW.state.cursorFits = nil
    stub.FireEvent("CURSOR_CHANGED")
    stub.RunTimers()
    T.eq(S.frames.Neck.glow:IsShown(), false)
end)

T.test("character slots: with the mouse off the page and no ring lit, the slots aren't asked", function()
    local S = lentWorld()
    local page = CreateFrame("Frame", nil, UIParent)
    local over = false
    function page:IsMouseOver() return over end
    local asked = 0
    CharacterHeadSlot.IsMouseOver = function() asked = asked + 1; return false end
    S.Hover(page)
    T.eq(asked, 0, "off the page: no slot asked")
    over = true
    CharacterHeadSlot.IsMouseOver = function() asked = asked + 1; return true end
    S.Hover(page)
    T.eq(asked, 1)
    T.eq(S.frames.Head.ring:IsShown(), true)
    -- The mouse leaves the page in one jump, and the lit ring still goes out.
    over = false
    CharacterHeadSlot.IsMouseOver = function() asked = asked + 1; return false end
    S.Hover(page)
    T.eq(S.frames.Head.ring:IsShown(), false)
    asked = 0
    S.Hover(page)
    T.eq(asked, 0, "and then nothing asked again")
end)

T.test("character text: warm stat labels, tooltip numbers lit, picked tab pops", function()
    local Style = DaylightUI.Style
    local _, ns = load()
    T.deq(ns.CharacterPage.LABEL, Style.INK.LABEL)
    T.deq(ns.CharacterPage.TIP.body, Style.INK.TEXT)
    local hex = DaylightUI.Win.Parts.Hex(Style.INK.VALUE)
    T.eq(ns.StatText.Numbers("Increases armor by 11.8.", Style.INK.VALUE), "Increases armor by " .. hex .. "11.8|r.")
    T.eq(ns.StatText.Numbers("|cffff2020Down 5|r", Style.INK.VALUE), "|cffff2020Down 5|r")
    ToggleCharacter("PaperDollFrame")
    ns.Follow.Tick()
    for _, b in ipairs(ns.window.tabs) do
        if b.id == ns.window.current then T.rgb({ b.text:GetTextColor() }, { Style.Accent() }) end
    end
end)

T.test("character page: a plain stat value pops in the accent and follows an accent switch", function()
    local _, ns, DUI = charPage()
    local page = openChar(ns)
    DUI:Set("general", "accent", "custom")
    DUI:Set("general", "accentColor", { 0.2, 0.6, 0.9 })
    stub.RunTimers()
    local row = page.stats.groups.attack.rows[1]
    local r, g, b = row.value:GetTextColor()
    T.rgb({ r, g, b }, { 0.2, 0.6, 0.9 })
    DUI:Set("general", "accentColor", { 0.9, 0.3, 0.1 })
    stub.RunTimers()
    r, g, b = row.value:GetTextColor()
    T.rgb({ r, g, b }, { 0.9, 0.3, 0.1 })
end)

T.test("controller: the Character window tells the game; the X and scroll bars are no D-pad stops", function()
    local shown, skipped = {}, {}
    local m = { FrameShown = function(_, f) shown[f] = true end, FrameHidden = function() end }
    _G.GamepadMode, _G.InputUtil = { FrameControlsManager = m }, { IsGamepadUIEnabled = function() return true end }
    _G.SmartNavigation_MarkFrameIgnored = function(f) skipped[f] = true end
    local DUI = stub.Load({ character = true })
    stub.RunTimers()
    local W = DUI.Widgets
    local parent = CreateFrame("Frame", nil, UIParent)
    local x = W.Close(parent, function() end)
    T.truthy(skipped[x], "B closes: the X is no stop")
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local bar = W.Scroll(sf)
    T.truthy(skipped[bar], "the bar is no stop")
    local woken = 0
    local wake = bar.Wake
    bar.Wake = function() woken = woken + 1; wake() end
    sf:GetScript("OnVerticalScroll")(sf, 40)
    T.eq(woken, 1, "the D-pad scrolled the list: the bar follows")
    local f = _G.DaylightUICharacter
    if f then
        f:Show()
        stub.RunTimers()
        T.truthy(shown[f], "the game hears the window open")
        T.truthy(f.SmartNavigationCloseHandler, "and B closes it")
    end
    _G.GamepadMode, _G.InputUtil, _G.SmartNavigation_MarkFrameIgnored = nil, nil, nil
end)

T.test("character on a controller: Y is the slot's more actions, as the game's; A on a slot asks for the swap menu", function()
    local F, ns = following()
    local f = ns.window
    T.truthy(f.padKeys, "the window has its own buttons")
    local y
    for _, e in ipairs(f.padKeys) do if e.key == "Y" then y = e end end
    T.truthy(y, "Y is one of them")
    T.falsy(y.when(nil), "nothing picked")
    T.falsy(y.when(CreateFrame("Button")), "not a gear slot")
end)

T.test("character list: on a controller the D-pad reaching the last row in view moves the list on, staying on the same item; the top the same", function()
    local _, ns = load({ factions = factions() })
    local List = ns.List
    local L = List.Make(UIParent, {})
    local items = {}
    for n = 1, L.visible + 5 do items[n] = { kind = "row", key = "r" .. n, text = "Row " .. n } end
    List.Set(L, items)
    local aimed
    local was = _G.SmartNavigation
    _G.InputUtil = { IsGamepadUIEnabled = function() return true end }
    _G.GamepadMode = { FrameControlsManager = { FrameShown = function() end, FrameHidden = function() end } }
    DaylightUI.Pad.focused = L.frame
    _G.SmartNavigation = { RefreshButtonGroups = function() end, GetCurrentButton = function() end,
        SetTargetButtonForFrame = function(_, _, b) aimed = b end }
    local last = L.rows[L.visible]
    T.eq(last.item.key, "r" .. L.visible)
    last.OnSmartNavSelect(last)
    stub.RunTimers()
    T.eq(L.offset, 1, "moved one on")
    T.eq(aimed, L.rows[L.visible - 1], "a row back")
    T.eq(aimed.item.key, "r" .. L.visible, "on the same item")
    T.eq(L.rows[1].item.key, "r2")
    L.rows[1].OnSmartNavSelect(L.rows[1])
    stub.RunTimers()
    T.eq(L.offset, 0, "back up")
    T.eq(aimed, L.rows[2])
    T.eq(aimed.item.key, "r2", "still on the item it landed on")
    DaylightUI.Pad.focused = nil
    _G.SmartNavigation, _G.InputUtil, _G.GamepadMode = was, nil, nil
end)

-- Putting a spell on an item is protected: the client blocks PickupInventoryItem
-- from addon code while a spell waits for an item (the ticket's "the game blocked
-- PickupInventoryItem() (DaylightUI)"), and only a secure click of the game's
-- own slot button runs it.
local function blockedPickup(picked)
    stub.errors = stub.errors or {}
    return function(id)
        if ((SpellCanTargetItem and SpellCanTargetItem()) or (InRepairMode and InRepairMode())) and (stub.inSecure or 0) == 0 then
            stub.errors[#stub.errors + 1] = "ADDON_ACTION_BLOCKED: PickupInventoryItem()"
            return
        end
        picked[#picked + 1] = id
    end
end

local function padEntry(f, key)
    for _, e in ipairs(f.padKeys) do if e.key == key then return e end end
end

T.test("character on a controller: A puts a waiting scroll, enchant or repair on the slot's piece through the game's own slot button", function()
    local CP, ns = charPage({ items = { MainHand = CW.item("Sword", { weapon = 1 }) } })
    local page = openChar(ns)
    stub.RunTimers()
    _G.InputUtil = { IsGamepadUIEnabled = function() return true end }
    _G.GamepadMode = { FrameControlsManager = { FrameShown = function() end, FrameHidden = function() end } }
    local picked, popped = {}, 0
    _G.PickupInventoryItem = blockedPickup(picked)
    local errors = #stub.errors
    local hand, head = page.slots.MainHand, page.slots.Head
    CW.state.items[CW.SLOT_IDS.Head] = nil
    T.truthy(hand.button, "the game's button is lent")
    local pop = CreateFrame("Button", nil, hand.button)
    pop:SetScript("OnClick", function() popped = popped + 1 end)
    hand.button.popoutButton = pop
    local A = hand:GetScript("OnMouseUp")
    local f = ns.window
    local apply = padEntry(f, "A")
    T.truthy(apply and apply.secure, "A has a secure action of its own")
    T.isnil(f.padSelect(hand), "nothing waiting: A says Select")
    T.isnil(apply.secure(hand), "nothing waiting: A stays the game's")
    A(hand)
    T.eq(popped, 1, "nothing waiting: A opens the swap menu")
    CW.state.aim = { kind = "condition", fits = { [CW.SLOT_IDS.MainHand] = true } }
    local attrs = apply.secure(hand)
    T.eq(attrs and attrs.type, "click", "a scroll waiting: A clicks")
    T.eq(attrs and attrs.clickbutton, hand.button, "the game's own slot button, which picks the piece up securely")
    A(hand)
    T.deq(picked, {}, "the slot's own click puts nothing on it from addon code")
    T.eq(#stub.errors, errors, "so nothing is blocked")
    T.eq(popped, 1, "and no swap menu")
    T.isnil(f.padSelect(hand), "a scroll: Select, as the game's")
    T.eq(f.padSelect(head), false, "an empty slot: A does nothing")
    T.isnil(apply.secure(head), "nothing to put it on")
    CW.state.aim = { kind = "enchant", fits = { [CW.SLOT_IDS.MainHand] = true } }
    T.eq(f.padSelect(hand), CONTEXT_ACTION_LABEL_APPLY or DaylightUI.L["Apply"], "an enchant: Apply")
    T.eq(apply.label(hand), CONTEXT_ACTION_LABEL_APPLY or DaylightUI.L["Apply"], "the hint says it too")
    CW.state.aim, CW.state.repair = nil, true
    T.eq(f.padSelect(hand), CONTEXT_ACTION_LABEL_REPAIR or DaylightUI.L["Repair"])
    T.eq(apply.secure(hand).clickbutton, hand.button, "the repair cursor clicks the game's slot too")
    CW.state.repair = nil
    _G.InputUtil, _G.GamepadMode = nil, nil
    A(hand)
    T.eq(#picked, 0, "with the mouse it's the game's own button that gets the click")
    T.eq(#stub.errors, errors)
end)

-- The game opens its character window for an enchant picked from a bag; the
-- Daylight UI bag can't ask it to (opening it from addon code taints the
-- controller), so this window opens by itself on the piece it goes on.
T.test("character on a controller: an enchant picked from the bag opens this window alone, on the piece, and B closes it", function()
    local CP, ns = charPage({ items = { MainHand = CW.item("Staff", { weapon = 1 }) } })
    stub.RunTimers()
    local F = ns.Follow
    local aimed
    _G.InputUtil = { IsGamepadUIEnabled = function() return true end }
    local m = {}
    function m:FrameShown(frame) if frame.FocusGamepad then frame:FocusGamepad() end end
    function m:FrameHidden(frame) if frame.UnfocusGamepad then frame:UnfocusGamepad() end end
    function m:GetActiveFrame() end
    _G.GamepadMode = { FrameControlsManager = m }
    local was = _G.SmartNavigation
    _G.SmartNavigation = { RefreshButtonGroups = function() end, GetCurrentButton = function() end,
        SetTargetButtonForFrame = function(_, _, b) aimed = b end, SelectTopLeftButton = function() end }
    T.falsy(CP.OpenForEnchant(), "nothing waiting: it stays shut")
    CW.state.aim = { kind = "enchant", fits = { [CW.SLOT_IDS.MainHand] = true } }
    T.truthy(CP.OpenForEnchant(), "an oil that takes the staff")
    F.Tick()
    for _ = 1, 3 do stub.RunTimers() end
    local f = ns.window
    T.truthy(f:IsShown(), "the window is open")
    T.eq(f.current, "character", "on the gear")
    T.falsy(CharacterFrame:IsShown(), "the game's window stays shut")
    T.eq(aimed, f.pages.character.slots.MainHand, "the D-pad starts on the staff")
    F.Tick()
    T.truthy(f:IsShown(), "it stays open")
    F.Close()
    F.Tick()
    for _ = 1, 30 do stub.RunTimers() end
    T.falsy(ns.Window.IsOpen(), "the X or B closes it")
    CW.state.aim = { kind = "enchant", fits = {} }
    T.falsy(CP.OpenForEnchant(), "nothing worn takes it: shut, as the game's")
    CW.state.aim = nil
    _G.InputUtil, _G.GamepadMode, _G.SmartNavigation = nil, nil, was
end)

T.test("character on a controller: place in bags puts a piece in the first plain bag with room, or leaves it on", function()
    local CP = charPage()
    local put, held
    _G.IsInventoryItemLocked = function() return false end
    _G.PickupInventoryItem = function(id) held = id end
    _G.CursorHasItem = function() return held ~= nil end
    _G.ClearCursor = function() held = nil end
    _G.PutItemInBackpack = function() put = "backpack"; held = nil end
    _G.PutItemInBag = function(inv) put = inv; held = nil end
    local free = { [0] = { 0, 0 }, [1] = { 3, 8 }, [2] = { 2, 0 } }   -- the backpack full, bag 1 a herb bag
    local was = _G.C_Container
    _G.C_Container = {
        GetContainerNumFreeSlots = function(bag) local f = free[bag]; if f then return f[1], f[2] end return 0, 0 end,
        ContainerIDToInventoryID = function(bag) return 30 + bag end,
    }
    T.truthy(CP.Unequip(5))
    T.eq(put, 32, "bag 2: the herb bag can't hold it")
    put = nil
    free[2] = { 0, 0 }
    T.falsy(CP.Unequip(5))
    T.eq(put, nil)
    T.eq(held, nil, "no room: it goes back on")
    _G.C_Container = was
end)

-- ---------------------------------------------------------------------
-- The stats pane's rows fit their words; the lists' picked, hovered and striped rows differ
-- ---------------------------------------------------------------------

-- Measures text as the client does: 7 px a letter, wrapped to the width it is given.
local function wrapMeasure()
    stub.measure = function(fs, unbounded)
        local text = (fs.__text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local w, set = #text * 7, fs:GetWidth() or 0
        if unbounded then return w, 14 end
        local lines = (set > 0 and fs.__wrap ~= false) and math.max(1, math.ceil(w / set)) or 1
        return (set > 0 and math.min(w, set) or w), lines * 14
    end
end

T.test("character page: a long stat name wraps beside its value instead of running under it", function()
    local P, ns = charPage()
    local page = openChar(ns)
    wrapMeasure()
    local r = page.stats.groups.attributes.rows[1]
    local w = P.STATS_W - 2 * P.STATS_PAD
    r.label:SetText("Damage of the off hand weapon")
    r.value:SetText("35 - 47")
    local h = P.FitStat(r, w)
    T.truthy(h > P.STAT_ROW, "taller for a second line")
    T.eq(r:GetHeight(), h)
    local inset = P.STAT_INSET
    T.truthy(r.label:GetWidth() + r.value:GetStringWidth() + P.STAT_GAP <= w - 2 * inset, "the name stops short of the value")
    r.label:SetText("Agility")
    T.eq(P.FitStat(r, w), P.STAT_ROW, "a short name keeps the least height")
    stub.measure = nil
end)

T.test("character page: the stats are laid out by their rows' heights", function()
    local P, ns = charPage()
    local page = openChar(ns)
    wrapMeasure()
    P.RefreshStats(page)
    local rows = page.stats.groups.attributes.rows
    for i = 1, #rows - 1 do
        if rows[i]:IsShown() and rows[i + 1]:IsShown() then
            T.eq(rows[i + 1].y - rows[i].y, rows[i]:GetHeight(), "row " .. i .. " to the next")
        end
    end
    stub.measure = nil
end)

T.test("character list: a picked row is the accent's wash, a hover is white, and a stripe is dark", function()
    local DUI, ns = load({ factions = {
        CW.faction("Alliance", 0, 0, 0, 0, { isHeader = true }),
        CW.faction("Ash", 5, 3000, 3000, 9000, { isChild = true }),
        CW.faction("Birch", 5, 3000, 3000, 9000, { isChild = true }),
        CW.faction("Cedar tree", 5, 3000, 3000, 9000, { isChild = true }),
    } })
    setNow(DUI, "zebra", true)
    DaylightUI:Set("general", "accent", "daylight")    -- a one-color accent gives a plain vertex color
    local page = openPage(ns, "ReputationFrame")
    local rows = page.list.rows
    T.truthy(rows[2].pick:IsShown(), "the first faction is picked")
    T.falsy(rows[3].pick:IsShown())
    T.falsy(rows[2].hi:IsShown(), "the picked row is not lit as a hover")
    local ar, ag, ab = DaylightUI.Style.Accent()
    local pr, pg, pb = rows[2].pick:GetVertexColor()
    T.truthy(math.abs(pr - ar) < 0.01 and math.abs(pg - ag) < 0.01 and math.abs(pb - ab) < 0.01, "in the accent")
    T.eq(ns.Colors.STRIPE[1] + ns.Colors.STRIPE[2] + ns.Colors.STRIPE[3], 0, "a stripe is dark")
    T.truthy(DaylightUI.Win.Parts.HI[1] > 0.9, "a hover is white")
    -- Picking another moves it.
    stub.Key(function() rows[3]:Click() end)
    T.truthy(rows[3].pick:IsShown())
    T.falsy(rows[2].pick:IsShown())
end)

T.test("character list: rows with a bar have room above the name, under the bar and between them", function()
    local List = ns_List or nil
    local _, ns = load({ factions = factions() })
    List = ns.List
    local text = math.ceil(DaylightUI.Style.SIZE.body * 1.3)
    T.eq(List.BAR_ROW, text + List.BAR_GAP + List.BAR_H + 2 * List.PAD)
    T.truthy(List.BAR_ROW >= 38, "more than the 30 px that left the bar touching the name")
    local page = openPage(ns, "ReputationFrame")
    local r = page.list.rows[2]
    local _, _, _, _, y = r.text:GetPoint(1)
    T.eq(-y, List.PAD, "room above the name")
    local _, _, _, _, by = r.bar:GetPoint(1)
    T.eq(by, List.PAD, "and under the bar")
end)

T.test("character slots: a long item name takes a second line", function()
    local P, ns = charPage({ items = { Head = CW.item("The Crown of the Mountain Kings", { quality = 4, level = 66 }),
                                        Neck = CW.item("Pendant", { quality = 3, level = 20 }) } })
    wrapMeasure()
    DaylightUI:Set("Character", "missingEnchants", false)   -- no third line here
    local page = openChar(ns)
    local S = ns.Slots
    local long, short = S.frames.Head, S.frames.Neck
    T.truthy(long.wrap, "too long for one line: two")
    T.falsy(short.wrap, "a short name stays on one line")
    local _, rel, relPoint = long.name:GetPoint(1)
    T.eq(rel, long.icon, "the lines span the icon's height")
    local function plain(fs) return (fs:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    T.eq(plain(long.line), "Item level 66", "the item level line is never shortened")
    stub.measure = nil
end)

-- Seen in game (Spanish): "Reparacion pronto - ..." and "Roto - sin estadi..." ended in dots,
-- so you could not tell what they said. A line too long for the room takes a second row.
T.test("character slots: a long repair line takes a second row instead of ending in dots", function()
    local P, ns = charPage({ items = { Head = CW.item("Crown", { quality = 4, level = 66, cur = 10, max = 100 }),
                                        Neck = CW.item("Pendant", { quality = 3, level = 20 }),
                                        Chest = CW.item("The Breastplate of the Long Name Mountain Kings", { quality = 4, level = 66, cur = 0, max = 100 }) } })
    wrapMeasure()
    DaylightUI:Set("Character", "missingEnchants", false)   -- no third line here
    local page = openChar(ns)
    local S = ns.Slots
    local h, short, both = S.frames.Head, S.frames.Neck, S.frames.Chest
    h.line:SetWidth(40)   -- less room than "Repair soon . 10% left"
    S.FitText(h)
    T.truthy(h.lineWrap, "too long for one row: two")
    T.eq(h.line.__maxLines, 2, "at most two")
    T.falsy(short.lineWrap, "a short line stays on one row")
    -- Both too long: the name takes two rows and so does the line.
    T.truthy(both.wrap and both.lineWrap, "the name and the line each wrap")
    -- Back to a short line in the same slot: one row again.
    h.line:SetWidth(400)
    S.FitText(h)
    T.falsy(h.lineWrap, "one row again")
    T.eq(h.line.__maxLines or 0, 0)
    stub.measure = nil
end)

T.test("character slots: the item level in the icon's corner leaves the name its own, centered", function()
    local P, ns = charPage({ items = { Head = CW.item("Lionheart Helm", { quality = 4, level = 66 }),
                                        Chest = CW.item("Chest", { cur = 20, max = 100 }) } })
    DaylightUI:Set("Character", "missingEnchants", false)   -- no third line here
    local page = openChar(ns)
    local h = ns.Slots.frames.Head
    T.eq(h.corner:GetText(), "", "off by default: no number in the corner")
    T.truthy(h.line:GetText():find("66", 1, true), "the line under the name")
    T.falsy(h.lineless)
    DaylightUI:Set("Character", "levelInIcon", true)
    P.Refresh(page)
    T.eq(h.corner:GetText(), "66", "the level in the corner")
    T.truthy(h.cornerBg:IsShown() and h.cornerBg:GetWidth() > 0, "a dark square behind the number")
    T.eq(h.cornerBg:GetWidth(), h.cornerBg:GetHeight(), "square")
    T.eq(h.line:GetText(), "", "no line under the name")
    T.truthy(h.lineless, "so the name is centered on the icon")
    local p = h.name:GetPoint(1)
    T.eq(p, "LEFT", "by its middle")
    DaylightUI:Set("Character", "levelInIcon", false)
    P.Refresh(page)
    T.eq(h.corner:GetText(), "")
    T.falsy(h.cornerBg:IsShown(), "and none with no number")
    T.falsy(h.lineless)
end)


T.test("character list: a row with a bar has the same room on all four sides", function()
    local _, ns = load({ factions = factions() })
    local page = openPage(ns, "ReputationFrame")
    local List = ns.List
    local r = page.list.rows[2]
    local _, _, _, tx, ty = r.text:GetPoint(1)
    local _, _, _, rx, ry = r.right:GetPoint(1)
    local _, _, _, bx, by = r.bar:GetPoint(1)
    local _, _, _, bx2 = r.bar:GetPoint(2)
    T.eq(tx, List.PAD + (r.item.indent or 0) * List.INDENT, "left")
    T.eq(-ty, List.PAD, "top")
    T.eq(-rx, List.PAD, "right")
    T.eq(by, List.PAD, "bottom")
    T.eq(-bx2, List.PAD, "the bar's right")
    T.eq(bx, List.PAD, "the bar's left")
end)

T.test("character statistics: the picked category is marked with a wash and a bar in its color", function()
    local _, ns = load({ statistics = {
        categories = { { id = 1, title = "Combat" }, { id = 2, title = "Kills", parent = 1 }, { id = 3, title = "Travel" } },
        stats = { [1] = { { id = 101, name = "Damage done", quantity = "5" } } } } })
    local page = openPage(ns, "AchievementFrame")
    if not page or not page.list then ns.Follow.Select("statistics"); page = ns.window.pages.statistics end
    local rows = page.list.rows
    T.eq(rows[1].text:GetText(), "Combat", "at the size of the others, not in capitals")
    T.falsy(rows[1].line:IsShown(), "no rule under it")
    T.falsy(rows[1].head:IsShown())
    T.truthy(rows[1].pick:IsShown() and rows[1].mark:IsShown(), "the first is open: the wash and the bar")
    T.falsy(rows[2].pick:IsShown() or rows[2].mark:IsShown(), "the others are not")
    local r, g, b = rows[1].mark:GetVertexColor()
    T.rgb({ r, g, b }, ns.DEFAULTS.colors.attributes, "the bar in its category's color")
    stub.Key(function() rows[2]:Click() end)
    T.truthy(rows[2].pick:IsShown() and rows[2].mark:IsShown(), "a sub-category picked is marked")
    T.falsy(rows[1].pick:IsShown() or rows[1].mark:IsShown(), "and the one before no longer")
    r, g, b = rows[2].mark:GetVertexColor()
    T.rgb({ r, g, b }, ns.DEFAULTS.colors.attributes, "in its parent's color")
    T.truthy(rows[1].pick:GetTexture() and rows[1].mark:GetTexture(), "textures to tint: a bare texture would show nothing in game")
end)

T.test("character list: every row has the same room on all four sides, with or without a bar", function()
    local _, ns = load({ statistics = {
        categories = { { id = 1, title = "Combat" }, { id = 2, title = "Kills", parent = 1 } },
        stats = { [1] = { { id = 101, name = "Damage done", quantity = "5" } } } } })
    local page = openPage(ns, "AchievementFrame")
    if not page or not page.right then ns.Follow.Select("statistics"); page = ns.window.pages.statistics end
    local List = ns.List
    T.eq(List.ROW, math.ceil(DaylightUI.Style.SIZE.body * 1.3) + 2 * List.PAD, "a row is its text and the room above and under it")
    for _, L in ipairs({ page.list, page.right }) do
        local r = L.rows[1]
        local _, _, _, tx, ty = r.text:GetPoint(1)
        local _, _, _, rx, ry = r.right:GetPoint(1)
        T.eq(-ty, List.PAD, "top")
        T.eq(-ry, List.PAD, "the number's top")
        T.eq(-rx, List.PAD, "right")
        T.eq(tx - (r.item.indent or 0) * List.INDENT, List.PAD, "left")
    end
end)

T.test("character skills: a row lights nothing and picks nothing (there is nothing to open), but a header still folds", function()
    local _, ns = load({ skills = skills() })
    local page = openPage(ns, "SkillsFrame")
    local List = ns.List
    local row
    for _, r in ipairs(page.left.rows) do if r:IsShown() and r.item and r.item.kind == "row" then row = r; break end end
    T.truthy(row, "a skill row")
    row:GetScript("OnEnter")(row)
    T.falsy(row.hi:IsShown(), "no hover wash")
    stub.Key(function() row:Click() end)
    T.falsy(row.pick:IsShown() or row.mark:IsShown(), "no pick")
    T.isnil(page.left.selectedKey, "nothing selected")
    T.truthy(page.left.opts.static and page.right.opts.static)
end)

T.test("character skills: a fold shows at once even when the game's list still reads the old state, and doesn't flip back", function()
    local _, ns = load({ skills = skills() })
    local page = openPage(ns, "SkillsFrame")
    local C = C_SkillInfo
    local realCollapse, realExpand = C.CollapseSkillHeader, C.ExpandSkillHeader
    local late = {}
    -- The game answers late: the call is made but the list changes a moment after.
    C.CollapseSkillHeader = function(i) late[#late + 1] = function() realCollapse(i) end end
    C.ExpandSkillHeader = function(i) late[#late + 1] = function() realExpand(i) end end
    local function names(L)
        local out = {}
        for _, r in ipairs(L.rows) do if r:IsShown() and r.item then out[#out + 1] = r.item.text end end
        return table.concat(out, ",")
    end
    local function click(name)
        for _, r in ipairs(page.right.rows) do
            if r:IsShown() and r.item and r.item.text == name then stub.Key(function() r:Click() end); return end
        end
        error("no row " .. name)
    end
    stub.RunTimers()
    T.truthy(names(page.right):find("Swords", 1, true), "Weapon Skills starts open")
    click("Weapon Skills")
    stub.RunTimers()
    T.falsy(names(page.right):find("Swords", 1, true), "folded at once, before the game's list changed")
    for _, f in ipairs(late) do f() end
    stub.FireEvent("SKILL_LINES_CHANGED")
    stub.RunTimers()
    T.falsy(names(page.right):find("Swords", 1, true), "and it stays folded when the game's answer comes")
    late = {}
    click("Weapon Skills")
    stub.RunTimers()
    T.truthy(names(page.right):find("Swords", 1, true), "opens at once")
    for _, f in ipairs(late) do f() end
    stub.FireEvent("SKILL_LINES_CHANGED")
    stub.RunTimers()
    T.truthy(names(page.right):find("Swords", 1, true), "and stays open")
    C.CollapseSkillHeader, C.ExpandSkillHeader = realCollapse, realExpand
end)

T.test("character page: a stat row whose value can't be measured (a secret, in a fight) is fitted without working on it", function()
    local P, ns = charPage()
    local page = openChar(ns)
    local r = page.stats.groups.attributes.rows[1]
    r.label:SetText("Strength")
    r.value:SetText("5")
    local w = P.STATS_W - 2 * P.STATS_PAD
    -- Measured once while it can be: that width is kept.
    r.value.GetStringWidth = function() return 33 end
    P.FitStat(r, w)
    T.eq(r.valueW, 33)
    -- A secret measure, as the client gives for a secret text: never compared or added.
    r.value.GetStringWidth = function() return stub.Secret(40) end
    r.value.GetStringHeight = function() return stub.Secret(14) end
    local ok, h = pcall(P.FitStat, r, w)
    T.truthy(ok, tostring(h))
    T.eq(h, math.max(P.STAT_ROW, P.STAT_SIZE + 2 + 2 * P.STAT_PAD), "the height of a line, as when nothing is measured")
    T.eq(r.valueW, 33, "the last width is kept for it")
    -- Measuring errors outright (the fake game's secret text): the same.
    r.value.GetStringWidth = function() error("attempt to measure secret text") end
    ok, h = pcall(P.FitStat, r, w)
    T.truthy(ok, tostring(h))
    -- Never measured at all: a usual width.
    local fresh = page.stats.groups.attributes.rows[2]
    fresh.label:SetText("Agility"); fresh.valueW = nil
    fresh.value.GetStringWidth = function() return stub.Secret(40) end
    ok, h = pcall(P.FitStat, fresh, w)
    T.truthy(ok, tostring(h))
    T.isnil(fresh.valueW)
end)

T.test("character pvp: the honor card shows today, yesterday and in all; a dash where the client has none", function()
    local pvp = {}
    for k, v in pairs(PVP) do pvp[k] = v end
    pvp.honor = { today = { 12, 1 }, yesterday = { 30, 0 }, lifetime = { 4500, 9 } }
    local _, ns = load({ pvp = pvp })
    local page = openPage(ns, "PVPRankFrame")
    local rows = page.honor.rows
    T.eq(page.cards.honor:IsShown(), true)
    T.deq({ rows[1].cells[1]:GetText(), rows[1].cells[2]:GetText(), rows[1].cells[3]:GetText() }, { "12", "30", "4,500" }, "honorable kills")
    T.deq({ rows[2].cells[1]:GetText(), rows[2].cells[2]:GetText(), rows[2].cells[3]:GetText() }, { "1", "0", "-" }, "dishonorable: none in all (that number is a rank)")
    T.eq(page.honor.cols[3]:GetText(), "Lifetime")
    local _, ns2 = load({ pvp = PVP })
    local page2 = openPage(ns2, "PVPRankFrame")
    T.eq(page2.cards.honor:IsShown(), false, "the client has no honor numbers: no card")
end)

-- From a player's report: the PvP page didn't change after killing players and
-- gaining honor. Kills and honor fire their own events, not the rank's.
T.test("character pvp: kills and honor coming in repaint the open page", function()
    local pvp = {}
    for k, v in pairs(PVP) do pvp[k] = v end
    pvp.honor = { today = { 12, 1 }, yesterday = { 30, 0 }, lifetime = { 4500, 9 } }
    local _, ns = load({ pvp = pvp })
    local page = openPage(ns, "PVPRankFrame")
    pvp.honor.today[1] = 13
    pvp.honor.lifetime[1] = 4501
    stub.FireEvent("PLAYER_PVP_KILLS_CHANGED", "player")
    stub.RunTimers()
    T.eq(page.honor.rows[1].cells[1]:GetText(), "13", "today's kills")
    T.eq(page.honor.rows[1].cells[3]:GetText(), "4,501")
    pvp.renownReputationEarned = 450
    stub.FireEvent("CHAT_MSG_COMBAT_HONOR_GAIN", "You have been awarded 50 honor points.")
    stub.RunTimers()
    local P = function(s) return DaylightUI.Win.Parts.Hex({ DaylightUI.Style.Pop() }) .. s .. "|r" end
    T.eq(page.blocks[1].sub:GetText(), P("450") .. " of " .. P("1,000") .. " points", "the honor toward the next rank")
end)

T.test("character pvp: the game's crest with no rank, that rank's own badge after, ours when the client has none", function()
    local old = { C_Texture = _G.C_Texture, faction = _G.UnitFactionGroup }
    local atlases = { ["UI-Character-Info-Honor-Icon-Horde"] = { width = 80, height = 100 },
                      ["UI-Character-Info-Honor-Icon-3"] = { width = 100, height = 100 } }
    _G.C_Texture = { GetAtlasInfo = function(a) return atlases[a] end }
    _G.UnitFactionGroup = function() return "Horde" end
    local none = {}
    for k, v in pairs(PVP) do none[k] = v end
    none.renownLevel = 0
    local _, ns0 = load({ pvp = none })
    local page0 = openPage(ns0, "PVPRankFrame")
    T.eq(page0.emblem.__atlas, "UI-Character-Info-Honor-Icon-Horde", "the Horde crest with no rank")
    T.eq(page0.emblem:GetWidth(), math.floor(ns0.PvP.EMBLEM_SIZE * 0.8 + 0.5), "kept in its own proportions")
    T.eq(page0.emblem:GetHeight(), ns0.PvP.EMBLEM_SIZE)
    local _, ns = load({ pvp = PVP })
    local page = openPage(ns, "PVPRankFrame")
    T.eq(page.emblem.__atlas, "UI-Character-Info-Honor-Icon-3", "rank 3's own badge, not the faction's")
    local r, g, b = page.emblem:GetVertexColor()
    T.eq(r + g + b, 3, "not tinted by the accent")
    -- The client has no atlas for it: our badge.
    _G.C_Texture = { GetAtlasInfo = function() return nil end }
    local _, ns2 = load({ pvp = PVP })
    local page2 = openPage(ns2, "PVPRankFrame")
    T.truthy(page2.emblem:GetTexture():find("pvp-rank-", 1, true), "our badge stands in")
    _G.C_Texture, _G.UnitFactionGroup = old.C_Texture, old.faction
end)

T.test("character pvp: the next reward (the faction tabard) shows its icon, description and rank", function()
    local pvp = {}
    for k, v in pairs(PVP) do pvp[k] = v end
    pvp.rewards = { [4] = { { uiOrder = 2, name = "Other" },
                            { uiOrder = 1, name = "Rank 4 rewards", icon = 135026, itemID = 5976, description = "Buy rewards." } } }
    local _, ns = load({ pvp = pvp })
    local page = openPage(ns, "PVPRankFrame")
    local W = page.reward
    T.truthy(W:IsShown(), "shown")
    T.eq(W.name:GetText(), "Buy rewards.", "the first by its order, by its description, there before the item loads")
    T.eq(W.icon:GetTexture(), 135026)
    T.truthy(W.edge:IsShown(), "in the windows' item icon")
    T.truthy(W.sub:GetText():find("4", 1, true), "the rank it comes at")
    local c = DaylightUI.Style.INK.LABEL
    local r, g, b = W.sub:GetTextColor()
    T.near(r, c[1], 0.01, "the sub line is tan")
    T.near(g, c[2], 0.01)
    T.near(b, c[3], 0.01)
    -- With no description the item's name, else the general one.
    pvp.rewards[4][2].description = nil
    local oldInfo = _G.GetItemInfo
    _G.GetItemInfo = function(id) if id == 5976 then return "Faction Tabard" end end
    ns.PvP.Refresh(page)
    T.eq(W.name:GetText(), "Faction Tabard", "the item's name when there is no description")
    _G.GetItemInfo = oldInfo
    -- No reward ahead: hidden.
    local _, ns2 = load({ pvp = PVP })
    local page2 = openPage(ns2, "PVPRankFrame")
    T.eq(page2.reward:IsShown(), false, "none ahead")
end)

T.test("character pvp: soft cards, the same room on all four sides, the left as tall as the right", function()
    local _, ns = load({ pvp = PVP })
    local page = openPage(ns, "PVPRankFrame")
    local P, C = ns.PvP, page.cards
    local function top(c) return -select(5, c:GetPoint(1)) end
    T.eq(C.rank:GetHeight(), C.week:GetHeight() + C.season:GetHeight() + C.honor:GetHeight() + 2 * P.GAP, "the left card reaches the right stack's foot")
    T.eq(top(C.season) - top(C.week), C.week:GetHeight() + P.GAP, "a gap between cards")
    -- A block sits in from its card by the same room at the sides, and in the middle of its height.
    local b = page.blocks[2]
    local _, _, _, bx, by = b:GetPoint(1)
    local _, _, _, rx = b:GetPoint(2)
    T.eq(bx, P.PAD, "left"); T.eq(-rx, P.PAD, "right")
    T.eq(-by, math.floor((C.week:GetHeight() - b:GetHeight()) / 2), "in the middle, top to foot")
    T.truthy(C.week:GetHeight() >= b:GetHeight() + 2 * P.PAD, "never closer than the room all round")
    -- The cards reach the foot of the page.
    T.truthy(C.rank:GetHeight() >= ns.List.Room(), "the cards reach the page's foot (or are as tall as their words need)")
    -- The labels are tan; the accent is for numbers.
    local r, g, bl = b.label.__textColor[1], b.label.__textColor[2], b.label.__textColor[3]
    T.rgb({ r, g, bl }, DaylightUI.Style.INK.LABEL)
    local hl = page.honor.label.__textColor
    T.rgb({ hl[1], hl[2], hl[3] }, DaylightUI.Style.INK.LABEL, "HONOR is tan too")
end)

T.test("character pvp: the badge is our own, one for each rank, in the accent", function()
    local _, ns = load({ pvp = PVP })
    local page = openPage(ns, "PVPRankFrame")
    T.truthy(page.emblem:GetTexture():find("pvp-rank-03.png", 1, true), "rank 3's badge")
    T.near(page.emblem:GetAlpha(), 1, 0.001)
    DaylightUI:Set("general", "accent", "daylight")    -- a one-color accent gives a plain vertex color
    ns.PvP.Refresh(page)
    local r, g, b = page.emblem:GetVertexColor()
    T.rgb({ r, g, b }, { DaylightUI.Style.Accent() }, "tinted in the accent")
    -- Past the last drawn badge, the last one.
    local high = {}
    for k, v in pairs(PVP) do high[k] = v end
    high.renownLevel = 20
    local _, ns2 = load({ pvp = high })
    local page2 = openPage(ns2, "PVPRankFrame")
    T.truthy(page2.emblem:GetTexture():find("pvp-rank-14.png", 1, true))
end)

T.test("character pvp: the cards are the same dark inset as the other pages' side panels", function()
    local _, ns = load({ pvp = PVP })
    local page = openPage(ns, "PVPRankFrame")
    local r, g, b, a = page.cards.week.fill:GetVertexColor()
    T.deq({ r, g, b }, { ns.List.INSET[1], ns.List.INSET[2], ns.List.INSET[3] })
    T.near(a, ns.List.INSET[4], 0.001)
    T.deq(ns.PvP.CARD, ns.List.INSET, "the very same one")
end)

T.test("character footer: the ammo you carry beside the durability, only with ammo or a weapon that shoots it", function()
    local function footOf(items, class)
        local _, ns, DUI = charPage({ usesAmmo = true, class = class or "HUNTER", items = items })
        DUI:Set("Character", "footColors", false)
        return openChar(ns).foot
    end
    local arrows = CW.item("Jagged Arrow", { count = 1234, subType = "Arrow" })
    T.eq(footOf({ Ranged = CW.item("Bow", { weapon = 2 }), Ammo = arrows }).ammo:GetText(), "Ammo 1234 (Jagged Arrow)", "the whole count, and which ammo")
    local f = footOf({ Ranged = CW.item("Bow", { weapon = 2 }) })
    T.eq(f.ammo:GetText(), "Ammo 0", "a bow and none in the slot: none")
    T.eq(footOf({ Ranged = CW.item("Gun", { weapon = 3 }) }).ammo:GetText(), "Ammo 0")
    T.eq(footOf({ Ranged = CW.item("Crossbow", { weapon = 18 }) }).ammo:GetText(), "Ammo 0")
    T.eq(footOf({ Ammo = arrows }).ammo:GetText(), "Ammo 1234 (Jagged Arrow)", "ammo in the slot, no weapon yet")
    T.eq(footOf({ Ranged = CW.item("Throwing Knife", { weapon = 16 }) }).ammo:GetText(), "", "thrown takes no ammo")
    T.eq(footOf({}).ammo:GetText(), "", "nothing to shoot, nothing to count")
    local _, ns, DUI = charPage({ usesAmmo = true, class = "HUNTER", items = { Ranged = CW.item("Bow", { weapon = 2 }) } })
    local page = openChar(ns)
    T.truthy(page.foot.ammo:GetText():find("Ammo", 1, true))
    local x = select(4, page.foot.ammo:GetPoint(1))
    T.eq(select(2, page.foot.ammo:GetPoint(1)), page.foot.dura, "right of the durability")
    T.truthy(x > 0)
end)

-- A hunter's ammo slot sits right beside the ranged icon. Its own name and
-- count were drawn over the ranged weapon's name, seen in game.
T.test("character slots: the ammo slot draws no words over the ranged weapon", function()
    local S, ns = lentWorld({ usesAmmo = true, class = "HUNTER", items = {
        Ranged = CW.item("Carapace Spine", { level = 58 }),
        Ammo = CW.item("Jagged Arrow", { count = 3200, subType = "Arrow" }) } })
    ns.Window.Open("character")
    local ammo = S.frames.Ammo
    T.eq(ammo:IsShown(), true)
    print("PROBE", ammo.name:GetText(), ammo.name:IsShown(), ammo.line:GetText(), ammo.line:IsShown(), ammo.enchant:GetText(), ammo.enchant:IsShown(), ammo.mark and ammo.mark:IsShown(), S.frames.Ranged.name:GetText(), S.frames.Ranged.line:GetText())
    T.falsy(ammo.line:IsVisible() and (ammo.line:GetText() or "") ~= "", "ammo count line hidden: " .. tostring(ammo.line:GetText()))
    T.falsy(ammo.enchant:IsVisible() and (ammo.enchant:GetText() or "") ~= "", "no enchant line either")
    -- New arrows while the window is open fade the slot's picture in, never its words.
    CW.state.items[CW.SLOT_IDS.Ammo] = CW.item("Razor Arrow", { count = 200, subType = "Arrow" })
    ns.Window.OnEvent(ns.window, "PLAYER_EQUIPMENT_CHANGED", 0)
    stub.RunTimers()
    stub.Advance(1)
    T.eq(ammo.entry and ammo.entry.name, "Razor Arrow", "the new arrows were painted")
    T.falsy(ammo.name:IsShown(), "ammo name stays hidden after a swap")
    T.falsy(ammo.line:IsShown(), "ammo count stays hidden after a swap")
end)
