local stub = require("stub")

-- Add piece (Design mode): extra text lines on a frame (Texts.lua) and
-- extra aura groups on party and raid (AuraGroups.lua), each in a fixed
-- slot that's off until added.

local function login() return stub.Load({ module = true }) end

local function tile(ns, unit)
    local b = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton1", ns.Raid.header)
    b:SetAttribute("unit", unit or "raid3")
    ns.Raid.header.initialConfigFunction(ns.Raid.header, b:GetName())
    stub.RunTimers()
    return b
end

local function shownTexts(f)
    local n = 0
    for _, fs in ipairs(f.extraTexts or {}) do if fs:IsShown() then n = n + 1 end end
    return n
end

T.test("texts: no extra texts by default, so no frame gets any", function()
    local DUI, ns = login()
    for _, unit in ipairs({ "player", "target", "focus" }) do
        T.eq(shownTexts(ns.frames[unit]), 0, unit)
        T.eq(DUI:Get("UnitFrames", unit .. ".texts.t1.show"), false)
    end
    T.isnil(ns.frames.targettarget.extraTexts, "frames without slots make nothing")
end)

T.test("texts: Add puts a level text in the first free slot; Remove puts the slot back", function()
    local DUI, ns = login()
    stub.units.target = { name = "Defias Bandit", reaction = 2, level = 12, health = 50, maxHealth = 100 }
    T.eq(ns.Texts.Add("target", "level"), "t1")
    T.eq(ns.Texts.Add("target", "name"), "t2", "the next one takes the next slot")
    stub.RunTimers()
    T.eq(DUI:Get("UnitFrames", "target.texts.t1.kind"), "level")
    T.eq(DUI:Get("UnitFrames", "target.texts.t1.spot"), "left", "a fresh slot starts from the defaults")
    local f = ns.frames.target
    ns.UF.UpdateAll(f, true)
    T.eq(shownTexts(f), 2)
    T.eq(tostring(stub.Text(f.extraTexts[1])), "12")
    T.eq(stub.Text(f.extraTexts[2]), "Defias Bandit")
    DUI:Set("UnitFrames", "target.texts.t1.x", 9)
    T.truthy(ns.Texts.Remove("target", "texts", "t1"))
    stub.RunTimers()
    T.eq(DUI:Get("UnitFrames", "target.texts.t1.show"), false)
    T.eq(DUI:Get("UnitFrames", "target.texts.t1.x"), 0, "its nudge back to the default")
    T.falsy(f.extraTexts[1]:IsShown())
    T.truthy(f.extraTexts[2]:IsShown(), "the other one stays")
    T.eq(ns.Texts.Add("target", "power"), "t1", "a removed slot is free again")
end)

T.test("texts: all four slots in use, Add says so and adds nothing", function()
    local _, ns = login()
    for _ = 1, 4 do T.truthy(ns.Texts.Add("focus", "health")) end
    T.isnil(ns.Texts.Add("focus", "health"))
    T.isnil(ns.Texts.Add("focus", "bogus"), "only the known kinds")
end)

T.test("texts: health goes whole to the client's formatting, secret or not", function()
    local DUI, ns = login()
    ns.Texts.Add("target", "health")
    stub.RunTimers()
    stub.units.target = { name = "Mob", reaction = 2, health = stub.Secret(4120), maxHealth = stub.Secret(6600), pct = stub.Secret(62) }
    local f = ns.frames.target
    ns.UF.UpdateHealth(f, true)
    T.eq(type(f.extraTexts[1].__text) == "table" and f.extraTexts[1].__text.secretFormat, "%s", "still secret: whole to the client's formatting")
    T.eq(stub.Text(f.extraTexts[1]), "4.1K", "the value format by default")
    DUI:Set("UnitFrames", "target.texts.t1.healthFormat", "percent")
    stub.RunTimers()
    ns.UF.UpdateHealth(f, true)
    T.eq(stub.Text(f.extraTexts[1]), "62%")
end)

T.test("texts: a name text follows the last-name switch; class shows for players only", function()
    local DUI, ns = login()
    ns.Texts.Add("target", "name")
    ns.Texts.Add("target", "class")
    stub.RunTimers()
    DUI:Set("general", "lastNames.target", true)
    stub.units.target = { name = "Bone", lastName = "Money", isPlayer = true, class = "MAGE", health = 5, maxHealth = 10 }
    local f = ns.frames.target
    ns.UF.UpdateAll(f, true)
    T.eq(stub.Text(f.extraTexts[1]), "Bone Money")
    T.truthy(stub.Text(f.extraTexts[2]) ~= "", "a player's class")
    stub.units.target = { name = "Wolf", reaction = 2, class = "WARRIOR", health = 5, maxHealth = 10 }
    ns.UF.UpdateAll(f, true)
    T.eq(stub.Text(f.extraTexts[2]), "", "a mob's class says nothing")
end)

T.test("texts: placed by Spots inside the frame, nudged", function()
    local DUI, ns = login()
    ns.Texts.Add("player", "level")
    DUI:Set("UnitFrames", "player.texts.t1.spot", "topright")
    DUI:Set("UnitFrames", "player.texts.t1.x", -4)
    stub.RunTimers()
    local fs = ns.frames.player.extraTexts[1]
    local p, rel, rp = fs:GetPoint(1)
    T.eq(p, "TOPRIGHT"); T.eq(rel, ns.frames.player); T.eq(rp, "TOPRIGHT")
    T.eq(fs:GetJustifyH(), "RIGHT", "reads away from the side it's pinned to")
end)

T.test("aura groups: no extras by default, so no extra containers", function()
    local _, ns = login()
    local b = tile(ns)
    T.isnil(b.auraSet.extra)
end)

T.test("aura groups: an added group gets its own container, filter and spot; removing it empties it", function()
    local DUI, ns = login()
    local b = tile(ns)
    T.eq(ns.Texts.AddAuras("raid", "debuffs"), "x1")
    stub.RunTimers()
    local c = b.auraSet.extra and b.auraSet.extra.x1 and b.auraSet.extra.x1.debuffs
    T.truthy(c, "made")
    T.eq(c.__unit, "raid3", "pointed at the tile's unit")
    T.eq(c.__groups.dispel.max, 3, "only ones I can dispel, by default")
    T.isnil(c.__groups.all, "only the choice in use is added")
    local p, rel, rp = c:GetPoint(1)
    T.eq(rel, b); T.eq(rp, "TOPLEFT")
    -- Switched to buffs: a buff container of its own, the debuff one emptied.
    DUI:Set("UnitFrames", "raid.auras.x1.buffWhich", "mine")
    DUI:Set("UnitFrames", "raid.auras.x1.what", "buffs")
    stub.RunTimers()
    T.truthy(b.auraSet.extra.x1.buffs)
    T.eq(c.__groups.dispel.max, 0)
    ns.Texts.Remove("raid", "auras", "x1")
    stub.RunTimers()
    T.eq(c.__groups.dispel.max, 0, "kept for reuse, with nothing in it")
    T.eq(DUI:Get("UnitFrames", "raid.auras.x1.what"), "debuffs", "back to the defaults")
end)

T.test("aura groups: in combat no container is made; it comes once the fight is over", function()
    local DUI, ns = login()
    local b = tile(ns)
    stub.EnterCombat()
    ns.Texts.AddAuras("raid", "debuffs")
    ns.Raid.group:LayoutAuras(b, DUI:Get("UnitFrames", "raid"))
    T.isnil(b.auraSet.extra and b.auraSet.extra.x1 and b.auraSet.extra.x1.debuffs, "not in a fight")
    stub.LeaveCombat()
    stub.RunTimers()
    T.truthy(b.auraSet.extra.x1.debuffs, "after it")
end)

T.test("Add piece: Design mode on the Raid page; the new piece comes out picked with its card", function()
    local DUI, ns = login()
    local P = DUI.OptionsPanel
    P.Show("UnitFrames.raid")
    P.SetDesign(true)
    local strip = P.Strip()
    T.truthy(strip.add:IsShown(), "the chip shows in Design mode")
    local keys, values = strip.Sample().Adds()
    T.eq(#keys, #ns.Texts.KINDS + 2, "every text kind and two aura groups")
    T.truthy(values["auras:debuffs"])
    local label = strip.Sample().Add("auras:debuffs")
    T.eq(label, "Extra aura group 1")
    strip.Pick(label)
    strip.onAdded(label)
    stub.RunTimers()
    T.eq(strip.Selected(), "Extra aura group 1")
    local part = strip.SelectedPart()
    T.truthy(part, "its piece is on the preview")
    local found
    for _, k in ipairs(part.keys) do if k == "raid.auras.x1.spot" then found = true end end
    T.truthy(found, "its click opens its own settings")
    local pf = P.PageFrame()
    local card = pf.Find("raid.auras.x1.spot")
    T.truthy(card and card:IsShown(), "its card shows")
    P.SetDesign(false)
    T.falsy(strip.add:IsShown(), "no chip out of Design mode")
end)

T.test("Add piece: pages with no slots get no chip", function()
    local DUI = login()
    local P = DUI.OptionsPanel
    P.Show("UnitFrames.pet")
    P.SetDesign(true)
    T.falsy(P.Strip().add:IsShown())
    T.isnil(P.Strip().Sample().Adds)
end)

T.test("Add piece: a text added on the Target page shows on its preview", function()
    local DUI = login()
    local P = DUI.OptionsPanel
    P.Show("UnitFrames.target")
    P.SetDesign(true)
    local strip = P.Strip()
    T.eq(strip.Sample().Add("text:level"), "Extra text 1")
    stub.RunTimers()
    P.Refresh()
    local seen
    for _, b in ipairs(strip.Hotspots()) do if b.part.label == "Extra text 1" then seen = b end end
    T.truthy(seen, "a hotspot over it")
    T.truthy(seen.part.move and seen.part.size, "it moves and resizes like any piece")
end)

-- A built text without its color codes.
local function plainText(fs)
    return (string.gsub(string.gsub(tostring(stub.Text(fs)), "|c%x%x%x%x%x%x%x%x", ""), "|r", ""))
end

T.test("texts: up to three parts on one line, each its own color, joined by the separator", function()
    local DUI, ns = login()
    ns.Texts.Add("target", "name")
    DUI:Set("UnitFrames", "target.texts.t1.kind2", "level")
    DUI:Set("UnitFrames", "target.texts.t1.kind3", "health")
    DUI:Set("UnitFrames", "target.texts.t1.healthFormat", "percent")
    DUI:Set("UnitFrames", "target.texts.t1.sep", "slash")
    stub.RunTimers()
    stub.units.target = { name = "Bandit", reaction = 2, level = 12, health = 50, maxHealth = 100, pct = 50 }
    local f = ns.frames.target
    ns.UF.UpdateAll(f, true)
    local fs = f.extraTexts[1]
    T.eq(plainText(fs), "Bandit / 12 / 50%")
    T.truthy(string.find(tostring(stub.Text(fs)), "|c", 1, true), "each part in its color")
    DUI:Set("UnitFrames", "target.texts.t1.kind2", "none")
    DUI:Set("UnitFrames", "target.texts.t1.kind3", "none")
    stub.RunTimers()
    ns.UF.UpdateAll(f, true)
    T.eq(stub.Text(fs), "Bandit", "one part: no color codes, as before")
end)

T.test("texts: a built text hands a secret health on whole", function()
    local DUI, ns = login()
    ns.Texts.Add("target", "name")
    DUI:Set("UnitFrames", "target.texts.t1.kind2", "health")
    stub.RunTimers()
    stub.units.target = { name = "Boss", reaction = 2, health = stub.Secret(4120), maxHealth = stub.Secret(6600), pct = stub.Secret(62) }
    local f = ns.frames.target
    ns.UF.UpdateAll(f, true)
    T.truthy(f.extraTexts[1].__secretAnchoring, "the secret went in whole")
    T.eq(plainText(f.extraTexts[1]), "Boss 4.1K")
end)

T.test("texts: status says AFK, DND or dead; a secret AFK shows nothing", function()
    local _, ns = login()
    ns.Texts.Add("target", "status")
    stub.RunTimers()
    local f = ns.frames.target
    stub.units.target = { name = "Pal", isPlayer = true, class = "MAGE", health = 5, maxHealth = 10, afk = true }
    ns.UF.UpdateAll(f, true)
    T.eq(stub.Text(f.extraTexts[1]), "AFK")
    stub.units.target.afk = stub.Secret(true)
    stub.FireEvent("PLAYER_FLAGS_CHANGED", "target")
    T.eq(stub.Text(f.extraTexts[1]), "", "chat lockdown: nothing, never a guess")
    stub.units.target.afk, stub.units.target.dnd = false, true
    stub.FireEvent("PLAYER_FLAGS_CHANGED", "target")
    T.eq(stub.Text(f.extraTexts[1]), "DND")
end)

T.test("texts: a raid tile's group follows the roster", function()
    local _, ns = login()
    stub.units.raid3 = { name = "Tank", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10, subgroup = 2 }
    local b = tile(ns, "raid3")
    ns.Texts.Add("raid", "group")
    stub.RunTimers()
    ns.UF.UpdateAll(b, true)
    T.eq(stub.Text(b.extraTexts[1]), "G2")
    stub.units.raid3.subgroup = 5
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    stub.RunTimers()
    T.eq(stub.Text(b.extraTexts[1]), "G5", "moved to another group")
end)

T.test("texts: guild and elite or rare; nothing for none", function()
    local _, ns = login()
    ns.Texts.Add("target", "guild")
    ns.Texts.Add("target", "classification")
    stub.RunTimers()
    local f = ns.frames.target
    stub.units.target = { name = "Ragnar", reaction = 2, classification = "worldboss", health = 5, maxHealth = 10 }
    ns.UF.UpdateAll(f, true)
    T.eq(stub.Text(f.extraTexts[1]), "", "no guild")
    T.eq(stub.Text(f.extraTexts[2]), "Boss")
    stub.units.target = { name = "Pal", isPlayer = true, class = "MAGE", guild = "Dawn", health = 5, maxHealth = 10 }
    ns.UF.UpdateAll(f, true)
    T.eq(stub.Text(f.extraTexts[1]), "<Dawn>")
    T.eq(stub.Text(f.extraTexts[2]), "", "a normal unit")
end)

T.test("texts: every kind draws on the page preview, so Design mode can grab it", function()
    local DUI, ns = login()
    local P = DUI.OptionsPanel
    P.Show("UnitFrames.player")
    P.SetDesign(true)
    for i, kind in ipairs({ "status", "group", "guild", "classification" }) do
        ns.Texts.Add("player", kind)
        stub.RunTimers()
        P.Refresh()
        local seen
        for _, h in ipairs(P.Strip().Hotspots()) do if h.part.label == "Extra text " .. i then seen = h end end
        T.truthy(seen, kind .. " shows a sample")
    end
end)
