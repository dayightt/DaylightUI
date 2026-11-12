-- Private auras (boss debuffs addon code can't read): the client draws them
-- on slots we lend it (PrivateAuras.lua). Raid and party buttons carry two
-- in the middle (GroupPrivate.lua), the debuff bar three under its first
-- row (DaylightUI_Buffs/Private.lua). Anchors change out of combat only.
local stub = require("stub")

local function login(opts) return stub.Load(opts or { module = true }) end

local function raidButton(ns, i, unit)
    local h = ns.Raid.header
    local b = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton" .. i, h)
    b:SetAttribute("unit", unit)
    stub.units[unit] = stub.units[unit] or { name = "Lift", isPlayer = true, class = "PRIEST", health = 5, maxHealth = 10 }
    b:Show()
    h.initialConfigFunction(h, b:GetName())
    return b
end

local function byIndex(list)
    local out = {}
    for _, a in ipairs(list) do out[a.auraIndex] = a end
    return out
end

T.test("a raid tile lends the client two single-icon anchors in its middle", function()
    local DUI, ns = login()
    local b = raidButton(ns, 1, "raid2")
    local list = stub.PrivateAnchors("raid2")
    T.eq(#list, 2, "two icons per tile")
    local a = byIndex(list)
    T.truthy(a[1] and a[2], "aura indexes 1 and 2")
    local size = ns.GroupPrivate.Size(DUI:Get("UnitFrames", "raid"))
    for i = 1, 2 do
        T.eq(a[i].isContainer, false, "single-icon mode")
        T.eq(a[i].showCooldownFrame, true, "with the swipe")
        T.eq(a[i].showCountdownNumbers, false, "no numbers on a tile")
        T.eq(a[i].parent, b.privateSet.slots[i], "on a slot of ours")
        T.eq(a[i].iconInfo.iconAnchor.relativeTo, b.privateSet.slots[i])
        T.eq(a[i].iconInfo.iconWidth, size); T.eq(a[i].iconInfo.iconHeight, size)
    end
    -- Bigger than the tile's own debuffs, and both fit across it.
    T.truthy(size > DUI:Get("UnitFrames", "raid.auras.debuffs.size"), "bigger than the tile's debuffs")
    T.truthy(2 * size + ns.GroupPrivate.GAP < DUI:Get("UnitFrames", "raid.width"), "both fit")
    local p1 = { b.privateSet.slots[1]:GetPoint(1) }
    T.eq(p1[1], "CENTER", "the first sits in the middle")
end)

T.test("party buttons carry them too, bigger than their debuffs", function()
    local DUI, ns = login()
    local h = ns.Party.header
    local b = CreateFrame("Button", "DaylightUIPartyHeaderUnitButton1", h)
    b:SetAttribute("unit", "party1")
    stub.units.party1 = { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 }
    b:Show()
    h.initialConfigFunction(h, b:GetName())
    T.eq(#stub.PrivateAnchors("party1"), 2)
    T.truthy(ns.GroupPrivate.Size(DUI:Get("UnitFrames", "party")) > DUI:Get("UnitFrames", "party.auras.debuffs.size"))
end)

T.test("a new unit on the tile moves its anchors; hidden, it holds none", function()
    local _, ns = login()
    local b = raidButton(ns, 1, "raid2")
    stub.units.raid5 = { name = "Jasnah", isPlayer = true, class = "MAGE", health = 5, maxHealth = 10 }
    b:SetAttribute("unit", "raid5")
    T.eq(#stub.PrivateAnchors("raid2"), 0, "the old unit's taken back")
    T.eq(#stub.PrivateAnchors("raid5"), 2)
    T.eq(#stub.PrivateAnchors(), 2, "never more than the tile's two")
    b:Hide()
    T.eq(#stub.PrivateAnchors(), 0, "the header hid it: none")
    b:Show()
    T.eq(#stub.PrivateAnchors("raid5"), 2, "back as it shows")
end)

T.test("in combat nothing changes: a tile made or re-pointed mid-fight gets its anchors after it", function()
    local _, ns = login()
    local b = raidButton(ns, 1, "raid2")
    stub.EnterCombat()
    stub.units.raid6 = { name = "Lopen", isPlayer = true, class = "ROGUE", health = 5, maxHealth = 10 }
    T.noerror(function() b:SetAttribute("unit", "raid6") end)
    local late = raidButton(ns, 2, "raid7")
    T.eq(#stub.PrivateAnchors("raid2"), 2, "kept until the fight ends")
    T.eq(#stub.PrivateAnchors("raid7"), 0, "a member who joined mid-fight waits")
    stub.LeaveCombat()
    T.eq(#stub.PrivateAnchors("raid2"), 0)
    T.eq(#stub.PrivateAnchors("raid6"), 2)
    T.eq(#stub.PrivateAnchors("raid7"), 2)
    T.truthy(late.privateSet)
end)

T.test("the switch takes them away and brings them back; a taller tile, bigger icons", function()
    local DUI, ns = login()
    raidButton(ns, 1, "raid2")
    DUI:Set("UnitFrames", "raid.privateAuras", false)
    stub.RunTimers()
    T.eq(#stub.PrivateAnchors(), 0)
    DUI:Set("UnitFrames", "raid.privateAuras", true)
    stub.RunTimers()
    T.eq(#stub.PrivateAnchors("raid2"), 2)
    local before = stub.PrivateAnchors("raid2")[1].iconInfo.iconWidth
    DUI:Set("UnitFrames", "raid.height", 50)
    stub.RunTimers()
    local list = stub.PrivateAnchors("raid2")
    T.eq(#list, 2, "re-made, not added twice")
    T.truthy(list[1].iconInfo.iconWidth > before, "sizes follow the tile")
end)

T.test("an anchor the client turns down under a restriction is tried again once it lifts", function()
    local _, ns = login()
    local add = C_UnitAuras.AddPrivateAuraAnchor
    C_UnitAuras.AddPrivateAuraAnchor = function() error("refused") end
    stub.SetRestriction("Encounter", true)
    local b = raidButton(ns, 1, "raid2")
    T.eq(#stub.PrivateAnchors(), 0)
    C_UnitAuras.AddPrivateAuraAnchor = add
    stub.SetRestriction("Encounter", false)
    T.eq(#stub.PrivateAnchors("raid2"), 2)
    T.truthy(b.privateSet)
end)

T.test("an old anchor the client won't give back: nothing new goes on top until it does", function()
    local _, ns = login()
    local b = raidButton(ns, 1, "raid2")
    local remove = C_UnitAuras.RemovePrivateAuraAnchor
    C_UnitAuras.RemovePrivateAuraAnchor = function() error("refused") end
    stub.SetRestriction("Encounter", true)
    stub.units.raid5 = { name = "Jasnah", isPlayer = true, class = "MAGE", health = 5, maxHealth = 10 }
    b:SetAttribute("unit", "raid5")
    T.eq(#stub.PrivateAnchors("raid2"), 2, "still there")
    T.eq(#stub.PrivateAnchors("raid5"), 0, "no second pair over them")
    C_UnitAuras.RemovePrivateAuraAnchor = remove
    stub.SetRestriction("Encounter", false)
    T.eq(#stub.PrivateAnchors("raid2"), 0)
    T.eq(#stub.PrivateAnchors("raid5"), 2)
end)

T.test("test mode: a plain stand-in on a few sample tiles, never an anchor", function()
    local DUI, ns = login()
    DUI.SetTestMode(true)
    stub.RunTimers()
    local P = ns.Raid.preview
    local function shown(b, i)
        local s = b.privateSet and b.privateSet.slots[i].sample
        return s ~= nil and s:IsShown() == true
    end
    T.truthy(shown(P[5], 1), "tile 5 carries one")
    T.falsy(shown(P[5], 2))
    T.truthy(shown(P[22], 1) and shown(P[22], 2), "tile 22 carries two")
    T.falsy(P[1].privateSet ~= nil and shown(P[1], 1), "most carry none")
    T.eq(#stub.PrivateAnchors(), 0, "samples lend the client nothing")
    DUI:Set("UnitFrames", "raid.privateAuras", false)
    stub.RunTimers()
    T.falsy(shown(P[5], 1), "the switch hides the stand-in too")
    DUI.SetTestMode(false)
    stub.RunTimers()
end)

T.test("your own: three under the debuff bar's first row, with a countdown", function()
    local DUI = login({ buffs = true })
    local BL = stub.buffs
    T.truthy(BL.Private.set, "made with the debuff bar")
    local list = stub.PrivateAnchors("player")
    T.eq(#list, 3)
    local a = byIndex(list)
    local size = DUI:Get("Buffs", "settings.debuff.iconSize")
    for i = 1, 3 do
        T.eq(a[i].showCountdownNumbers, true)
        T.eq(a[i].isContainer, false)
        T.eq(a[i].iconInfo.iconWidth, size, "the debuffs' size")
    end
    local p = { BL.Private.frame:GetPoint(1) }
    T.eq(p[2], BL.DebuffBar.holder, "hung off the debuff bar")
    T.truthy(p[5] < -size, "under its first row")
    DUI:Set("Buffs", "settings.debuff.privateAuras", false)
    stub.RunTimers()
    T.eq(#stub.PrivateAnchors("player"), 0)
    DUI:Set("Buffs", "settings.debuff.privateAuras", true)
    stub.RunTimers()
    T.eq(#stub.PrivateAnchors("player"), 3)
    DUI:Set("Buffs", "settings.hideBlizzardFrames", false)
    stub.RunTimers()
    T.eq(#stub.PrivateAnchors("player"), 0, "the game's own frame shows them then")
end)

T.test("the buffs preview shows where yours land", function()
    login({ buffs = true })
    local BL = stub.buffs
    BL.Preview.Set(BL.PREVIEW_SHARE, BL.PREVIEW_MAX)
    local s = BL.Private.set.slots[1].sample
    T.truthy(s and s:IsShown(), "one stand-in")
    BL.Preview.Set(nil)
    T.falsy(s:IsShown())
    T.eq(#stub.PrivateAnchors("player"), 3, "the real anchors stay")
end)
