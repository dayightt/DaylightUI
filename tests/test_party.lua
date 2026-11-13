local stub = require("stub")

local function login(before) return stub.Load({ module = true, before = before }) end

-- A party button as the header would make it, on unit.
local function button(ns, i, unit, data)
    local h = ns.Party.header
    local b = CreateFrame("Button", "DaylightUIPartyHeaderUnitButton" .. i, h)
    b:SetAttribute("unit", unit)
    if data then stub.units[unit] = data end
    h.initialConfigFunction(h, b:GetName())
    return b
end

T.test("the party: a header of up to five, down from the first, hidden in a raid", function()
    local DUI, ns = login()
    local h, cfg = ns.Party.header, DUI:Get("UnitFrames", "party")
    T.eq(h:GetAttribute("showParty"), true)
    T.eq(h:GetAttribute("showRaid"), false)
    T.eq(h:GetAttribute("showPlayer"), false, "you're left out by default, like before")
    T.eq(h:GetAttribute("point"), "TOP")
    T.eq(h:GetAttribute("yOffset"), -cfg.spacing, "the old gap between frames")
    T.eq(h.__stateDriver.visibility, "[@raid1,exists] hide; [@party1,exists][group] show; hide")
    T.near(h:GetAttribute("unitWidth"), cfg.width, 1)
    T.near(ns.Party.holder:GetHeight(), 4 * cfg.height + 3 * cfg.spacing, 2, "room for four")
end)

T.test("the party moves as one, by its holder; its first frame starts where party1 did", function()
    local DUI, ns = login()
    local m = DUI.Movers.Get("unitframes.party")
    T.eq(m.frame, ns.Party.holder)
    local d = m.default
    T.eq(d[1], "TOPLEFT"); T.eq(d[3], "LEFT"); T.eq(d[4], 70)
    T.eq(d[5], 160 + DUI:Get("UnitFrames", "party.height") / 2)
    T.isnil(ns.frames.party1, "the old frames are gone")
end)

T.test("a new party height moves the mover's default with it, so the first frame stays at 160", function()
    local DUI = login()
    DUI:Set("UnitFrames", "party.height", 40)
    stub.RunTimers()
    T.eq(DUI.Movers.Get("unitframes.party").default[5], 160 + 20)
end)

T.test("a party button's heals and shields never run past its health bar", function()
    local DUI, ns = login()
    local b = button(ns, 3, "party2", { name = "Hale", isPlayer = true, class = "PRIEST", health = 90, maxHealth = 100 })
    for _, bar in ipairs({ b.heals, b.heals.wedge, b.absorbs, b.absorbs.wedge, b.overshield }) do
        local clip = bar:GetParent()
        T.truthy(clip:DoesClipChildren(), "cut off at the health bar's edge")
        local _, rel = clip:GetPoint(1)
        T.eq(rel, b.health)
    end
end)

T.test("one settings table drives every party button", function()
    local DUI, ns = login()
    local b = button(ns, 1, "party1", { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 })
    DUI:Set("UnitFrames", "party.width", 200)
    stub.RunTimers()
    T.near(b:GetWidth(), 200, 1)
    DUI:Set("UnitFrames", "party.spacing", 12)
    stub.RunTimers()
    T.eq(ns.Party.header:GetAttribute("yOffset"), -12)
    DUI:Set("UnitFrames", "party.enabled", false)
    stub.RunTimers()
    T.isnil(ns.Party.header.__stateDriver.visibility)
end)

T.test("a party button is a full frame: portrait, name tab, aggro on the ring", function()
    local _, ns = login()
    local b = button(ns, 1, "party1", { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10, threat = 3 })
    T.truthy(b.portrait and b.portrait:IsShown(), "portrait")
    T.truthy(b.tab and b.tab:IsShown(), "name tab")
    T.truthy(b.portrait.threatBand:IsShown(), "aggro")
    stub.units.party1.threat = 0
    ns.UF.UpdateThreat(b)
    T.falsy(b.portrait.threatBand:IsShown())
end)

T.test("a roleplay name learned later (Total RP 3, NamesChanged) redraws the button's name", function()
    local DUI, ns = login()
    local b = button(ns, 1, "party1", { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 })
    T.truthy(string.find(b.nameText.__text, "Kaladin", 1, true))
    local real = DUI.UnitName
    DUI.UnitName = function(u, e) if u == "party1" then return "Aldric" end return real(u, e) end
    DUI.Fire("NamesChanged")
    DUI.UnitName = real
    T.truthy(string.find(b.nameText.__text, "Aldric", 1, true), "the new name shows")
end)

T.test("a role icon shows the role a member picked; none for unknown or off", function()
    local DUI, ns = login()
    local b = button(ns, 1, "party1", { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10, role = "TANK" })
    T.truthy(b.status.icons.role:IsShown())
    stub.units.party1.role = "NONE"
    ns.UF.UpdateRole(b)
    T.falsy(b.status.icons.role:IsShown(), "no role picked: nothing shows")
    DUI:Set("UnitFrames", "party.showRole", false)
    stub.RunTimers()
    stub.units.party1.role = "HEALER"
    ns.UF.UpdateRole(b)
    T.falsy(b.status.icons.role:IsShown(), "the option turns it off")
end)

T.test("a new party leader gets the crown on their button", function()
    local _, ns = login()
    local b = button(ns, 1, "party1", { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 })
    T.falsy(b.status.icons.leader:IsShown())
    stub.units.party1.leader = true
    stub.FireEvent("PARTY_LEADER_CHANGED")
    stub.RunTimers()   -- status events are gathered into one pass the frame after
    T.truthy(b.status.icons.leader:IsShown(), "the crown follows the leader")
end)

T.test("test mode fills the party with sample members", function()
    local DUI, ns = login()
    DUI.SetTestMode(true)
    stub.RunTimers()
    T.eq(ns.Party.preview[1].nameText.__text, "Kaladin")
    T.eq(ns.Party.preview[4].nameText.__text, "Jasnah")
    T.falsy(ns.Party.preview[5]:IsShown(), "four: you're left out")
    T.truthy(ns.Party.preview[1].portrait.threatBand:IsShown(), "the sample tank has aggro")
    T.eq(ns.Party.header:GetAlpha(), 0, "the real buttons step aside")
    DUI:Set("UnitFrames", "party.hideSelf", false)
    stub.RunTimers()
    T.truthy(ns.Party.preview[5]:IsShown(), "five with you")
    DUI.SetTestMode(false)
    stub.RunTimers()
    T.falsy(ns.Party.preview[1]:IsShown())
    T.eq(ns.Party.header:GetAlpha(), 1)
end)

T.test("party text sizes are their own", function()
    local DUI, ns = login()
    local b = button(ns, 1, "party1", { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 })
    T.truthy(DUI:Get("UnitFrames", "partyText.big") < DUI:Get("UnitFrames", "playerText.big"))
    DUI:Set("UnitFrames", "partyText.name", 14)
    stub.RunTimers()
    T.eq(b.nameText.__font[2], 14)
end)

local LIFT = { name = "Lift", isPlayer = true, class = "PRIEST", health = 5, maxHealth = 10 }

T.test("each party button gets the aura groups on its unit: debuffs under it from its right end, your buffs from its left", function()
    local DUI, ns = login()
    local b = button(ns, 2, "party2", LIFT)
    local set = b.auraSet
    T.truthy(set)
    T.isnil(b.debuffRow); T.isnil(b.buffRow); T.isnil(b.buffs, "the old rows are gone")
    T.eq(set.debuffs.__unit, "party2"); T.eq(set.buffs.__unit, "party2")
    T.eq(set.debuffs.__groups.all.max, 4)
    T.eq(set.buffs.__groups.mine.max, 4, "only mine by default")
    T.isnil(set.cc.__groups.cc, "crowd control off: party frames keep their look")
    local p, rel, rp = set.debuffs:GetPoint(1)
    T.eq(p, "TOPRIGHT"); T.eq(rel, b); T.eq(rp, "BOTTOMRIGHT")
    p, rel, rp = set.buffs:GetPoint(1)
    T.eq(p, "TOPLEFT"); T.eq(rel, b); T.eq(rp, "BOTTOMLEFT")
    T.truthy(select(4, set.buffs:GetPoint(1)) >= b.ringInset, "past the portrait ring")
    DUI:Set("UnitFrames", "party.auras.debuffs.show", false)
    DUI:Set("UnitFrames", "party.auras.buffs.which", "all")
    stub.RunTimers()
    T.eq(set.debuffs.__groups.all.max, 0)
    T.eq(set.buffs.__groups.mine.max, 0); T.eq(set.buffs.__groups.all.max, 4)
end)

T.test("party auras: any spot, in both looks; outside the left clears the ring, above clears the name tab", function()
    local DUI, ns = login()
    local b = button(ns, 2, "party2", LIFT)
    local c = b.auraSet.debuffs
    DUI:Set("UnitFrames", "party.auras.debuffs.spot", "outleft")
    stub.RunTimers()
    T.truthy(select(4, c:GetPoint(1)) < -b.ringReach, "outside the left: past the portrait ring")
    DUI:Set("UnitFrames", "party.auras.debuffs.spot", "above")
    stub.RunTimers()
    T.truthy(select(5, c:GetPoint(1)) > b.tabHeight, "above the frame: over the name tab")
    DUI:Set("UnitFrames", "party.nameOnBar", true)
    stub.RunTimers()
    T.eq(select(5, c:GetPoint(1)), ns.Spots.GAP, "no tab: just over the frame")
    -- The tile look: no portrait, no tab, icons in the corners; the same settings apply.
    DUI:Set("UnitFrames", "party.portrait", "none")
    DUI:Set("UnitFrames", "party.auras.debuffs.spot", "bottomleft")
    DUI:Set("UnitFrames", "party.auras.debuffs.grow", "right")
    stub.RunTimers()
    T.truthy(b.cornerMode)
    local p, _, rp, x = c:GetPoint(1)
    T.eq(p, "BOTTOMLEFT"); T.eq(rp, "BOTTOMLEFT")
    T.truthy(x > DUI:Get("UnitFrames", "party.roleSize"), "the role icon in that corner is kept clear")
end)

T.test("party auras: rows share the count, spacing sets the gap, the nudge moves them", function()
    local DUI, ns = login()
    local c = button(ns, 2, "party2", LIFT).auraSet.debuffs
    for k, v in pairs({ max = 8, rows = 2, spacing = 4, size = 18 }) do
        DUI:Set("UnitFrames", "party.auras.debuffs." .. k, v)
    end
    stub.RunTimers()
    T.eq(c.__lineSize, 4 * (18 + 4) - 4, "four a row")
    T.eq(c.__groups.all.layout.elementSpacing, 4)
    T.eq(c.__groups.all.max, 8)
    local _, _, _, x0, y0 = c:GetPoint(1)
    DUI:Set("UnitFrames", "party.auras.debuffs.x", 5)
    DUI:Set("UnitFrames", "party.auras.debuffs.y", -3)
    stub.RunTimers()
    local _, _, _, x1, y1 = c:GetPoint(1)
    T.eq(x1, x0 + 5); T.eq(y1, y0 - 3)
end)

T.test("only mine: off on someone too far to see (the game can't tell whose buffs those are)", function()
    local DUI, ns = login()
    local b = button(ns, 1, "party1", { name = "Lift", isPlayer = true, class = "PRIEST", health = 5, maxHealth = 10 })
    stub.RunTimers()
    local c = b.auraSet.buffs
    T.eq(c.__groups.mine.max > 0, true, "seen: on")
    stub.units.party1.visible = false
    stub.RunOnUpdate(ns.RangeTicker(), 1)
    T.eq(c.__groups.mine.max, 0, "too far: off")
    T.isnil(c.__groups.all)
    DUI:Set("UnitFrames", "party.auras.buffs.size", 16)
    stub.RunTimers()
    T.eq(c.__groups.mine.max, 0, "a new setting keeps it off")
    stub.units.party1.visible = nil
    stub.RunOnUpdate(ns.RangeTicker(), 1)
    T.eq(c.__groups.mine.max > 0, true, "back in sight: on")
    -- All doesn't ask whose they are, so it stays on far away.
    DUI:Set("UnitFrames", "party.auras.buffs.which", "all")
    stub.RunTimers()
    stub.units.party1.visible = false
    stub.RunOnUpdate(ns.RangeTicker(), 1)
    T.eq(c.__groups.all.max > 0, true, "all: still on")
end)

T.test("the party's aura groups keep their own size: the raid tiles' stay theirs", function()
    local _, ns = login()
    local rb = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton1", ns.Raid.header)
    rb:SetAttribute("unit", "raid3")
    stub.units.raid3 = { name = "Teft", isPlayer = true, class = "WARRIOR", health = 40, maxHealth = 80 }
    ns.Raid.header.initialConfigFunction(ns.Raid.header, rb:GetName())
    local pb = button(ns, 1, "party1", { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 })
    local db = ns.module.db
    db.raid.auras.buffs.size, db.party.auras.buffs.size = 20, 12
    db.raid.auras.buffs.show = true
    ns.Refresh(ns.module)
    stub.RunTimers()
    T.eq(rb.auraSet.buffs.__groups.mine.button:GetWidth(), 20, "raid laid out first, the party after: still 20")
    T.eq(rb.auraSet.buffs.__groups.mine.layout.elementWidth, 20)
    T.eq(pb.auraSet.buffs.__groups.mine.button:GetWidth(), 12)
    T.eq(pb.auraSet.buffs.__groups.mine.layout.elementWidth, 12)
end)

T.test("the Party page: a card per aura group, like the Raid page's", function()
    local DUI = login()
    local O = DUI.Options
    local page = O.GetPage("UnitFrames.party")
    T.eq(#O.ValidatePage(page), 0)
    local items = {}
    for _, g in ipairs(page.groups) do for _, it in ipairs(g.items) do if it.key then items[it.key] = it end end end
    for _, g in ipairs({ "debuffs", "cc", "buffs" }) do
        for _, f in ipairs({ "show", "spot", "grow", "size", "max", "rows", "spacing", "timers", "shortTimers", "x", "y" }) do
            T.truthy(items["party.auras." .. g .. "." .. f], g .. "." .. f)
        end
    end
    T.isnil(items["party.debuffsAt"]); T.isnil(items["party.buffsAt"], "the old spots are gone")
    T.falsy(O.IsDisabled(page, items["party.auras.debuffs.spot"]))
    DUI:Set("UnitFrames", "party.auras.debuffs.show", false)
    T.truthy(O.IsDisabled(page, items["party.auras.debuffs.spot"]), "off with the debuffs")
    T.falsy(O.IsDisabled(page, items["party.auras.buffs.shortTimers"]))
    DUI:Set("UnitFrames", "party.auras.buffs.timers", false)
    T.truthy(O.IsDisabled(page, items["party.auras.buffs.shortTimers"]), "off with the timers")
end)

-- What a bound time formatter writes at seconds left (the last step at or
-- under it, as the client's rule formatter picks).
local function formatAt(opts, secs)
    local fmt
    for _, s in ipairs(opts.textFormatter.steps) do
        if s.threshold <= secs then fmt = s.format end
    end
    return fmt
end

T.test("party buff timers can hide while more than a minute is left, once restrictions lift", function()
    local DUI, ns = login()
    local b = button(ns, 1, "party1", { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 })
    stub.RunTimers()
    local btn = b.auraSet.buffs.__groups.mine.button
    T.eq(DUI:Get("UnitFrames", "party.auras.buffs.shortTimers"), false, "off by default: every time shows")
    T.eq(formatAt(btn.__timeOpts, 1800), "%dm")
    stub.SetRestriction("PvPMatch", true)
    DUI:Set("UnitFrames", "party.auras.buffs.shortTimers", true)
    stub.RunTimers()
    T.eq(formatAt(btn.__timeOpts, 1800), "%dm", "locked in a battleground: waits")
    T.eq(#stub.errors, 0)
    stub.SetRestriction("PvPMatch", false)
    stub.RunTimers()
    local o = btn.__timeOpts
    T.eq(formatAt(o, 12), "%ds", "12 s: shown")
    T.eq(formatAt(o, 59.5), "%ds", "59 s: shown")
    T.eq(formatAt(o, 60), "", "a minute or more: nothing written")
    T.eq(formatAt(o, 1800), "")
    T.falsy(o.textColor, "no see-through color curve: in game it left long times showing")
    DUI:Set("UnitFrames", "party.auras.buffs.shortTimers", false)
    stub.RunTimers()
    T.eq(formatAt(btn.__timeOpts, 1800), "%dm", "off again: long times show")
    local nb = button(ns, 2, "party2", { name = "Shallan", isPlayer = true, class = "WARLOCK", health = 5, maxHealth = 10 })
    DUI:Set("UnitFrames", "party.auras.buffs.shortTimers", true)
    stub.RunTimers()
    T.eq(formatAt(nb.auraSet.buffs.__groups.mine.button.__timeOpts, 1800), "", "a button made later too")
end)

T.test("the party preview hides a long sample time with the switch", function()
    local _, ns = login()
    local AG = ns.AuraGroups
    local set = ns.Auras.PlainSet(UIParent)
    local cfg = { buffs = { show = true, which = "mine", spot = "below", grow = "right", size = 14, max = 4,
                            rows = 1, spacing = 2, x = 0, y = 0, timers = true, shortTimers = true } }
    AG.ShowSample(set, UIParent, cfg, { w = 72, h = 28, padX = 1, padY = 2 })
    local shown, hidden = 0, 0
    for i, s in ipairs(AG.SAMPLES.buffs) do
        local t = set.buffs.pool[i].time
        if t:IsShown() then shown = shown + 1 else hidden = hidden + 1 end
        T.eq(t:IsShown(), not s.long, s.time)
    end
    T.truthy(hidden > 0 and shown > 0, "a long one hides, short ones stay")
end)

T.test("party aura swipe: off by default, switched on once restrictions lift, on later buttons and samples too", function()
    local DUI, ns = login()
    local b = button(ns, 1, "party1", { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 })
    stub.RunTimers()
    local cd = b.auraSet.buffs.__groups.mine.button.__cooldown
    T.truthy(cd, "the client drives the icon's cooldown")
    T.eq(DUI:Get("UnitFrames", "party.auras.buffs.swipe"), false, "off by default")
    T.falsy(cd:GetDrawSwipe())
    stub.SetRestriction("PvPMatch", true)
    DUI:Set("UnitFrames", "party.auras.buffs.swipe", true)
    stub.RunTimers()
    T.falsy(cd:GetDrawSwipe(), "locked in a battleground: waits")
    T.eq(#stub.errors, 0)
    stub.SetRestriction("PvPMatch", false)
    stub.RunTimers()
    T.truthy(cd:GetDrawSwipe(), "on once the lock lifts")
    T.truthy(cd:GetReverse(), "the time gone shades the icon")
    local nb = button(ns, 2, "party2", { name = "Shallan", isPlayer = true, class = "WARLOCK", health = 5, maxHealth = 10 })
    stub.RunTimers()
    T.truthy(nb.auraSet.buffs.__groups.mine.button.__cooldown:GetDrawSwipe(), "a button made later too")
    DUI:Set("UnitFrames", "party.auras.buffs.swipe", false)
    stub.RunTimers()
    T.falsy(cd:GetDrawSwipe(), "off again")
    local set = ns.Auras.PlainSet(UIParent)
    local cfg = { buffs = { show = true, which = "mine", spot = "below", grow = "right", size = 14, max = 2,
                            rows = 1, spacing = 2, x = 0, y = 0, timers = false, swipe = true } }
    ns.AuraGroups.ShowSample(set, UIParent, cfg, { w = 72, h = 28, padX = 1, padY = 2 })
    local sample = set.buffs.pool[1]
    T.truthy(sample.cd:IsShown() and sample.cd:GetDrawSwipe(), "the preview shows the sweep")
    cfg.buffs.swipe = false
    ns.AuraGroups.ShowSample(set, UIParent, cfg, { w = 72, h = 28, padX = 1, padY = 2 })
    T.falsy(sample.cd:IsShown(), "and drops it with the switch")
end)

T.test("a party button made in combat is dressed without protected calls, and follows a new unit", function()
    local _, ns = login()
    stub.EnterCombat()
    local b = button(ns, 3, "party3", { name = "Shallan", isPlayer = true, class = "WARLOCK", health = 5, maxHealth = 10 })
    T.isnil(b.__hitRect, "the portrait's hit rect waits for combat to end")
    T.truthy((b.auraSet.debuffs:GetPoint(1)), "the aura groups are placed at once (a member joining mid-fight)")
    T.truthy((b.auraSet.buffs:GetPoint(1)))
    local first = b.nameText.__text
    T.truthy(first, "named")
    stub.units.party4 = { name = "Jasnah", isPlayer = true, class = "MAGE", health = 9, maxHealth = 10 }
    b:SetAttribute("unit", "party4")
    b:GetScript("OnAttributeChanged")(b, "unit", "party4")
    T.truthy(b.nameText.__text ~= first, "the name follows")
    T.eq(b.auraSet.debuffs.__unit, "party4", "the debuffs follow")
    T.eq(b.auraSet.buffs.__unit, "party4", "the buffs follow")
    T.eq(b.dispel.__unit, "party4", "the dispel icon follows")
    stub.LeaveCombat()
    T.truthy(b.__hitRect, "set once the fight is over")
    local p, rel, rp = b.auraSet.debuffs:GetPoint(1)
    T.eq(p, "TOPRIGHT"); T.eq(rel, b); T.eq(rp, "BOTTOMRIGHT")
    T.truthy((b.auraSet.buffs:GetPoint(1)), "the buffs laid out after the fight")
end)

T.test("your own party button reads the party's name switch, not the player's", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Daylight-Rift", isPlayer = true, class = "PALADIN", health = 5, maxHealth = 5 }
    end)
    DUI:Set("UnitFrames", "party.hideSelf", false)
    local seen
    local orig = DaylightUI.UnitName
    DaylightUI.UnitName = function(u, element) seen = element; return orig(u, element) end
    local b = button(ns, 1, "player")
    DaylightUI.UnitName = orig
    T.eq(b.unitToken, "player")
    T.eq(seen, "party")
end)

T.test("the tile look: no portrait, name on the bar, icons in the corners, aggro on the border", function()
    local DUI, ns = login()
    for k, v in pairs({ portrait = "none", nameOnBar = true, slant = false, width = 60, height = 56 }) do
        DUI:Set("UnitFrames", "party." .. k, v)
    end
    stub.RunTimers()
    local b = button(ns, 1, "party1", { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5,
                                        maxHealth = 10, threat = 3, role = "TANK", leader = true })
    T.truthy(b.cornerMode)
    T.falsy(b.tab:IsShown(), "no tab")
    T.eq(select(1, b.nameText:GetPoint(1)), "TOPLEFT", "a tall tile: the name along the top")
    T.truthy(b.roleIcon:IsShown(), "the role in a corner")
    T.falsy(b.status.icons.role:IsShown(), "not on the status set")
    local p, rel = b.roleIcon:GetPoint(1)
    T.eq(p, "BOTTOMLEFT"); T.eq(rel, b.health)
    T.eq(DaylightUI.Style.GetShell(b).opts.borderColor, ns.UF.THREAT_COLORS.aggro, "aggro on its border")
end)

T.test("a secret role or leader flag in corner mode: nothing compares it, nothing errors", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "party.portrait", "none")
    DUI:Set("UnitFrames", "party.nameOnBar", true)
    stub.RunTimers()
    local b = button(ns, 1, "party1", { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5,
                                        maxHealth = 10, role = stub.Secret("TANK"), leader = stub.Secret(true) })
    T.truthy(b.cornerMode)
    T.noerror(function() ns.UF.UpdateRole(b); ns.UF.UpdateLeader(b) end)
    T.falsy(b.roleIcon:IsShown(), "a secret role shows nothing")
    T.falsy(b.leaderIcon:IsShown(), "a secret leader flag shows nothing")
    T.eq(#stub.errors, 0)
end)

T.test("layout: across, a grid, sorted by role, you included", function()
    local DUI, ns = login()
    local h = ns.Party.header
    DUI:Set("UnitFrames", "party.direction", "rows")
    DUI:Set("UnitFrames", "party.perLine", 2)
    DUI:Set("UnitFrames", "party.sortBy", "role")
    DUI:Set("UnitFrames", "party.hideSelf", false)
    stub.RunTimers()
    T.eq(h:GetAttribute("point"), "LEFT")
    T.eq(h:GetAttribute("unitsPerColumn"), 2)
    T.eq(h:GetAttribute("groupBy"), "ASSIGNEDROLE")
    T.eq(h:GetAttribute("showPlayer"), true)
    local cfg = DUI:Get("UnitFrames", "party")
    T.near(ns.Party.holder:GetHeight(), 3 * cfg.height + 2 * cfg.groupSpacing, 2, "five in lines of two: three lines")
end)

T.test("default: the party runs tank, healer, damage", function()
    local DUI, ns = login()
    T.eq(DUI:Get("UnitFrames", "party.sortBy"), "role")
    T.eq(ns.Party.header:GetAttribute("groupBy"), "ASSIGNEDROLE")
    T.eq(ns.Party.header:GetAttribute("groupingOrder"), ns.Group.ROLE_ORDER)
end)

T.test("samples: sorted by role they run tank, healer, damage, you among them", function()
    local _, ns = login()
    local roles = function(cfg, n)
        local out = {}
        for i = 1, n do out[i] = ns.Party.SampleFor(i, cfg).role end
        return table.concat(out, " ")
    end
    T.eq(roles({ sortBy = "role", hideSelf = false }, 5), "TANK HEALER HEALER DAMAGER DAMAGER")
    T.eq(ns.Party.SampleFor(2, { sortBy = "role", hideSelf = false }).you, true, "the header keeps the party's order within a role: you first")
    T.eq(roles({ sortBy = "group", hideSelf = false }, 5), "HEALER TANK HEALER DAMAGER DAMAGER")
    T.eq(ns.Party.SampleFor(5, { sortBy = "role", hideSelf = true }), nil)
end)

T.test("the Party page: layout, tile and dispel options, valid; level and PvP need a home", function()
    local DUI = login()
    local O = DUI.Options
    local page = O.GetPage("UnitFrames.party")
    T.eq(#O.ValidatePage(page), 0)
    local items = {}
    for _, g in ipairs(page.groups) do for _, it in ipairs(g.items) do if it.key then items[it.key] = it end end end
    for _, key in ipairs({ "party.direction", "party.perLine", "party.groupSpacing", "party.sortBy", "party.hideSelf",
                           "party.fillVertical", "party.showPower", "party.nameAlign", "party.nameX", "party.nameY",
                           "party.rolePos", "party.leaderPx", "party.markerPos", "party.dispelPos", "party.showDispel",
                           "party.dispelSize", "party.dispelHighlight", "party.dispelAlpha", "party.dispelOnlyMine" }) do
        T.truthy(items[key], key)
    end
    T.falsy(O.IsDisabled(page, items["party.showLevel"]))
    T.falsy(items["party.showLevel"].desc:find("corner", 1, true), "it never shows in a corner: the description says so")
    T.truthy(items["party.showLevel"].desc:find("Needs the portrait or the name tab", 1, true))
    DUI:Set("UnitFrames", "party.portrait", "none")
    DUI:Set("UnitFrames", "party.nameOnBar", true)
    T.truthy(O.IsDisabled(page, items["party.showLevel"]), "no portrait and no tab: nowhere to show it")
    T.falsy(O.IsDisabled(page, items["party.rolePos"]), "corner spots in use now")
    T.falsy(O.IsDisabled(page, items["party.dispelPos"]))
end)

T.test("the Party page: a short frame has no portrait; the icon spots and sizes work with a name tab too", function()
    local DUI = login()
    local O = DUI.Options
    local page = O.GetPage("UnitFrames.party")
    local items = {}
    for _, g in ipairs(page.groups) do for _, it in ipairs(g.items) do if it.key then items[it.key] = it end end end
    T.eq(items["party.leaderPx"].label, "Leader crown pixel size")
    for _, key in ipairs({ "party.rolePos", "party.roleSize", "party.roleX", "party.roleY", "party.markerPos",
                           "party.markerX", "party.markerY", "party.leaderPos", "party.leaderPx", "party.leaderX", "party.leaderY" }) do
        T.falsy(O.IsDisabled(page, items[key]), key .. " works with the name tab")
    end
    T.eq(items["party.rolePos"].order[1], "home", "with the name or portrait first")
    T.eq(DUI:Get("UnitFrames", "party.rolePos"), "home", "and the default")
    T.falsy(O.IsDisabled(page, items["party.dispelPos"]), "the dispel spot works in bar mode too")
    T.falsy(O.IsDisabled(page, items["party.roleHideDamage"]), "so do the hide toggles")
    T.falsy(O.IsDisabled(page, items["party.leaderHideInCombat"]))
    DUI:Set("UnitFrames", "party.nameOnBar", true)
    DUI:Set("UnitFrames", "party.height", 16)
    T.truthy(O.IsDisabled(page, items["party.showLevel"]), "too short for a portrait: nowhere to show it")
    T.falsy(O.IsDisabled(page, items["party.rolePos"]))
end)

T.test("test mode: party samples are drawn on stand-ins where the real groups go", function()
    local DUI, ns = login()
    DUI.SetTestMode(true)
    stub.RunTimers()
    local shown = 0
    for i, b in ipairs(ns.Party.group.preview) do
        if b:IsShown() then
            T.truthy(b.sampleSet, "member " .. i .. " has stand-ins")
            if b.sampleSet.debuffs:IsShown() then shown = shown + 1 end
            local p, rel, rp = b.sampleSet.debuffs:GetPoint(1)
            T.eq(p, "TOPRIGHT"); T.eq(rel, b); T.eq(rp, "BOTTOMRIGHT")
        end
    end
    T.truthy(shown > 0, "some members carry debuffs")
    DUI.SetTestMode(false)
end)

T.test("a roster change re-reads every party button, even on the same unit word", function()
    local _, ns = login()
    local b = button(ns, 2, "party2", { name = "Lift", isPlayer = true, class = "PRIEST", health = 5, maxHealth = 10 })
    T.eq(b.nameText.__text, "Lift")
    local reads = 0
    local orig = b.auraSet.debuffs.UpdateAllAuras
    b.auraSet.debuffs.UpdateAllAuras = function(...) reads = reads + 1; return orig(...) end
    stub.units.party2 = { name = "Dalinar", isPlayer = true, class = "WARRIOR", health = 9, maxHealth = 10 }
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    stub.RunTimers()   -- a roster burst is one pass the frame after
    T.eq(b.nameText.__text, "Dalinar", "the new member's name, same party2")
    T.truthy(reads > 0, "its auras re-read")
end)

T.test("a burst of roster, threat and faction events is one pass over the buttons", function()
    local _, ns = login()
    button(ns, 1, "party1", { name = "Lift", isPlayer = true, class = "PRIEST", health = 5, maxHealth = 10 })
    button(ns, 2, "party2", { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 })
    stub.RunTimers()
    local UF = ns.UF
    local calls = { UpdateAll = 0, UpdateThreat = 0, UpdateStatus = 0, UpdateRole = 0 }
    local orig = {}
    for name in pairs(calls) do
        orig[name] = UF[name]
        UF[name] = function(...) calls[name] = calls[name] + 1; return orig[name](...) end
    end
    -- Someone new on both words: each button is redone in full, once.
    stub.units.party1 = { name = "Vex", isPlayer = true, class = "WARLOCK", health = 5, maxHealth = 10 }
    stub.units.party2 = { name = "Rell", isPlayer = true, class = "HUNTER", health = 5, maxHealth = 10 }
    for _ = 1, 20 do
        stub.FireEvent("GROUP_ROSTER_UPDATE")
        stub.FireEvent("UNIT_THREAT_LIST_UPDATE", "nameplate1")
        stub.FireEvent("UNIT_FACTION", "nameplate2")
    end
    T.eq(calls.UpdateAll, 0, "nothing in the same frame")
    stub.RunTimers()
    for name, fn in pairs(orig) do UF[name] = fn end
    local buttons = 0
    for _ in ns.Group.Buttons() do buttons = buttons + 1 end
    T.eq(calls.UpdateAll, buttons, "the roster: one UpdateAll per button, not 20")
    T.truthy(calls.UpdateThreat <= 2 * (buttons + 2), "threat: one pass (UpdateAll's own included), not 20")
    T.truthy(calls.UpdateStatus <= 3 * (buttons + 6), "status: one pass each, not 20")
end)

T.test("party buttons take right-clicks; one made in combat once the fight is over", function()
    local _, ns = login()
    local b = button(ns, 1, "party1", { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 })
    T.eq(b.__clicks and b.__clicks[1], "AnyUp")
    stub.EnterCombat()
    local c = button(ns, 3, "party3", { name = "Shallan", isPlayer = true, class = "WARLOCK", health = 5, maxHealth = 10 })
    T.isnil(c.__clicks, "not mid-fight")
    stub.LeaveCombat()
    T.eq(c.__clicks and c.__clicks[1], "AnyUp")
end)

T.test("a raid look sorted Group, then role gives the party a plain role sort", function()
    local _, ns = stub.Load({ module = true })
    local out = ns.TileLook({ sortBy = "grouprole" }, {})
    T.eq(out.sortBy, "role")
end)

-- Golden test: where a party member's debuffs and buffs sat before they
-- moved onto aura groups, for every old spot.
-- A profile saved with the old keys is loaded, so the upgrade runs on it.
local GOLDEN_TILE = { below = true, above = true, left = true, right = true, top = true, bottom = true }
local function goldenRows(b, buffsAt)
    if b.auraSet then return b.auraSet.debuffs, b.auraSet.buffs end
    return b.debuffRow, GOLDEN_TILE[buffsAt or "row"] and b.buffs or b.buffRow
end

local function round(v) return math.floor(v * 10 + 0.5) / 10 end

local function goldenWhere(c, b)
    local p, rel, rp, x, y = c:GetPoint(1)
    local fd = AnchorUtil.FlowDirection
    local names = { [fd.Left] = "Left", [fd.Right] = "Right", [fd.Up] = "Up", [fd.Down] = "Down" }
    return { p, rel == b and "frame" or (rel == b.tab and "tab" or "other"), rp, round(x), round(y),
             c.__anchorPoint, names[c.__growth[1]], names[c.__growth[2]], round(c.__lineSize) }
end

local function goldenLoad(party)
    return stub.Load({ module = true, before = function()
        DaylightUIDB = { version = 2, profileData = { Default = { general = {}, positions = {},
            modules = { UnitFrames = { groupFrames = 8, party = party } } } } }
    end })
end

local GOLDEN = {
    ["debuffs under"] = { "TOPRIGHT", "frame", "BOTTOMRIGHT", 0, -7.4, "TOPRIGHT", "Left", "Down", 78 },
    ["debuffs over"] = { "BOTTOMRIGHT", "frame", "TOPRIGHT", 0, 18.3, "BOTTOMRIGHT", "Left", "Up", 78 },
    ["debuffs inBottom"] = { "BOTTOMRIGHT", "frame", "BOTTOMRIGHT", -13.8, 14.7, "BOTTOMRIGHT", "Left", "Up", 78 },
    ["debuffs inTop"] = { "TOPRIGHT", "frame", "TOPRIGHT", -13.8, -6.7, "TOPRIGHT", "Left", "Down", 78 },
    ["debuffs left"] = { "TOPRIGHT", "frame", "TOPLEFT", -32.7, 0, "TOPRIGHT", "Left", "Down", 78 },
    ["debuffs right"] = { "TOPLEFT", "frame", "TOPRIGHT", 2, 0, "TOPLEFT", "Right", "Down", 78 },
    ["debuffs over, no tab"] = { "BOTTOMRIGHT", "frame", "TOPRIGHT", 0, 3, "BOTTOMRIGHT", "Left", "Up", 78 },
    ["buffs row"] = { "TOPLEFT", "frame", "BOTTOMLEFT", 14.8, -7.4, "TOPLEFT", "Right", "Down", 73.9 },
    ["buffs under"] = { "TOPLEFT", "frame", "BOTTOMLEFT", 14.8, -33.8, "TOPLEFT", "Right", "Down", 155.9 },
    ["buffs over"] = { "BOTTOMLEFT", "tab", "TOPLEFT", 0, 3, "BOTTOMLEFT", "Right", "Up", 155.9 },
    ["buffs below"] = { "BOTTOMLEFT", "frame", "BOTTOMLEFT", 5.7, 14.7, "BOTTOMLEFT", "Right", "Up", 152.2 },
    ["buffs above"] = { "TOPLEFT", "frame", "TOPLEFT", 5.7, -6.7, "TOPLEFT", "Right", "Down", 152.2 },
    ["buffs left"] = { "TOPRIGHT", "frame", "TOPLEFT", -2, 0, "TOPRIGHT", "Left", "Down", 62 },
    ["buffs right"] = { "TOPLEFT", "frame", "TOPRIGHT", 2, 0, "TOPLEFT", "Right", "Down", 62 },
    ["buffs top"] = { "BOTTOMLEFT", "frame", "TOPLEFT", 0, 2, "BOTTOMLEFT", "Right", "Up", 170.7 },
    ["buffs bottom"] = { "TOPLEFT", "frame", "BOTTOMLEFT", 0, -2, "TOPLEFT", "Right", "Down", 170.7 },
}

-- What moved on purpose when the party went onto aura groups:
-- - outside left/right sit centered beside the frame, like the raid's
-- - buffs over the frame hang off the frame above the name tab, not off the tab
-- - a row is as long as its icons, not the room left
-- - the old tile spots now clear the portrait ring, the name tab and the numbers
local GOLDEN_CHANGED = {
    ["debuffs left"] = { "RIGHT", "frame", "LEFT", -32.7, 0, "TOPRIGHT", "Left", "Down", 78 },
    ["debuffs right"] = { "LEFT", "frame", "RIGHT", 2, 0, "TOPLEFT", "Right", "Down", 78 },
    ["buffs row"] = { "TOPLEFT", "frame", "BOTTOMLEFT", 14.8, -6.8, "TOPLEFT", "Right", "Down", 62 },
    ["buffs under"] = { "TOPLEFT", "frame", "BOTTOMLEFT", 14.8, -33.8, "TOPLEFT", "Right", "Down", 62 },
    ["buffs over"] = { "BOTTOMLEFT", "frame", "TOPLEFT", 22.8, 18, "BOTTOMLEFT", "Right", "Up", 62 },
    ["buffs below"] = { "BOTTOMLEFT", "frame", "BOTTOMLEFT", 5.7, 14.7, "BOTTOMLEFT", "Right", "Up", 62 },
    ["buffs above"] = { "TOPLEFT", "frame", "TOPLEFT", 5.7, -6.7, "TOPLEFT", "Right", "Down", 62 },
    ["buffs left"] = { "RIGHT", "frame", "LEFT", -32.7, 0, "TOPRIGHT", "Left", "Down", 62 },
    ["buffs right"] = { "LEFT", "frame", "RIGHT", 2, 0, "TOPLEFT", "Right", "Down", 62 },
    ["buffs top"] = { "BOTTOMLEFT", "frame", "TOPLEFT", 22.8, 18, "BOTTOMLEFT", "Right", "Up", 62 },
    ["buffs bottom"] = { "TOPLEFT", "frame", "BOTTOMLEFT", 14.8, -6.8, "TOPLEFT", "Right", "Down", 62 },
}

-- Points, growth and line exact. x and y within a pixel, since the icon
-- numbers went from 9 pt to 8.
local function goldenSame(got, want, label)
    for i = 1, 9 do
        if i == 4 or i == 5 then T.near(got[i], want[i], 1, label .. "." .. i)
        else T.eq(got[i], want[i], label .. "." .. i) end
    end
end

T.test("golden: party debuffs and buffs stay where they were at every old spot", function()
    local dump = os.getenv("GOLDEN_DUMP")
    local cases = {}
    for _, at in ipairs({ "under", "over", "inBottom", "inTop", "left", "right" }) do
        cases[#cases + 1] = { "debuffs " .. at, { debuffsAt = at }, 1 }
    end
    cases[#cases + 1] = { "debuffs over, no tab", { debuffsAt = "over", nameOnBar = true }, 1 }
    for _, at in ipairs({ "row", "under", "over", "below", "above", "left", "right", "top", "bottom" }) do
        cases[#cases + 1] = { "buffs " .. at, { buffsAt = at }, 2 }
    end
    for _, case in ipairs(cases) do
        local DUI, ns = goldenLoad(case[2])
        local b = button(ns, 2, "party2", LIFT)
        stub.RunTimers()
        local c = select(case[3], goldenRows(b, case[2].buffsAt))
        local got = goldenWhere(c, b)
        if dump then
            local parts = {}
            for i = 1, 9 do
                local v = got[i]
                parts[i] = type(v) == "string" and string.format("%q", v) or tostring(v)
            end
            print(string.format('    [%q] = { %s },', case[1], table.concat(parts, ", ")))
        elseif GOLDEN[case[1]] then
            goldenSame(got, GOLDEN_CHANGED[case[1]] or GOLDEN[case[1]], case[1])
        end
    end
end)

T.test("upgrade 9: the party's old aura keys move into party.auras, each old spot to its new one", function()
    local _, ns = stub.Load({ module = true, login = false })
    local step = ns.UPGRADE_STEPS[9]
    local uf = { party = { showDebuffs = false, debuffFilter = "dispel", debuffSize = 20, maxDebuffs = 6,
                           debuffSpacing = 3, debuffRows = 2, debuffX = 4, debuffY = -2, debuffsAt = "inTop",
                           showBuffs = true, buffFilter = "all", buffSize = 12, maxBuffs = 5, buffSpacing = 1,
                           buffRows = 2, buffsAt = "left" } }
    step(uf)
    local p = uf.party
    for _, k in ipairs({ "showDebuffs", "debuffFilter", "debuffSize", "maxDebuffs", "debuffSpacing", "debuffRows",
                         "debuffX", "debuffY", "debuffsAt", "showBuffs", "buffFilter", "buffSize", "maxBuffs",
                         "buffSpacing", "buffRows", "buffsAt" }) do
        T.isnil(p[k], k .. " is gone")
    end
    T.deq(p.auras.debuffs, { show = false, which = "dispel", size = 20, max = 6, spacing = 3, rows = 2, x = 4, y = -2,
                             spot = "topright", grow = "left" })
    T.deq(p.auras.buffs, { show = true, which = "all", size = 12, max = 5, spacing = 1, rows = 2,
                           spot = "outleft", grow = "left" })
    local map = { under = { "below", "left" }, over = { "above", "left" }, inBottom = { "bottomright", "left" },
                  inTop = { "topright", "left" }, left = { "outleft", "left" }, right = { "outright", "right" } }
    for old, new in pairs(map) do
        local u = { party = { debuffsAt = old } }
        step(u)
        T.eq(u.party.auras.debuffs.spot, new[1], old); T.eq(u.party.auras.debuffs.grow, new[2], old)
    end
    map = { row = { "below", "right" }, under = { "below", "right" }, over = { "above", "right" },
            below = { "bottomleft", "right" }, above = { "topleft", "right" }, left = { "outleft", "left" },
            right = { "outright", "right" }, top = { "above", "right" }, bottom = { "below", "right" } }
    for old, new in pairs(map) do
        local u = { party = { buffsAt = old } }
        step(u)
        T.eq(u.party.auras.buffs.spot, new[1], old); T.eq(u.party.auras.buffs.grow, new[2], old)
    end
    local u = { party = { buffsAt = "under" } }
    step(u)
    T.eq(u.party.auras.buffs.y, -(16 + 11), "under the debuffs: one 18 px row (16 tall) further down")
    u = { party = { buffsAt = "under", debuffsAt = "inTop" } }
    step(u)
    T.isnil(u.party.auras.buffs.y, "debuffs elsewhere: straight under the frame")
    u = {}
    step(u)
    T.isnil(u.party, "nothing saved: nothing written")
    u = { party = { width = 120 } }
    step(u)
    T.isnil(u.party.auras, "no aura keys saved: the defaults stand")
end)

T.test("the samples of you carry your last name, by each frame's own switch", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Kaladin", lastName = "Stormblessed", isPlayer = true, class = "WARRIOR" }
    end)
    T.eq(ns.Party.You().name, "Kaladin Stormblessed", "party sample")
    T.eq(ns.Sample.You().name, "Kaladin Stormblessed", "player frame sample")
    DUI:Set("general", "lastNames.party", false)
    T.eq(ns.Party.You().name, "Kaladin", "the party switch off")
    T.eq(ns.Sample.You().name, "Kaladin Stormblessed", "the player's own switch still on")
end)

T.test("a faction update for a nameplate starts no status pass; one for a member does", function()
    local _, ns = login()
    button(ns, 1, "party1", { name = "Lift", isPlayer = true, class = "PRIEST", health = 5, maxHealth = 10 })
    stub.RunTimers()
    local UF, n = ns.UF, 0
    local orig = UF.UpdateStatus
    UF.UpdateStatus = function(...) n = n + 1; return orig(...) end
    for i = 1, 20 do stub.FireEvent("UNIT_FACTION", "nameplate" .. i) end
    stub.RunTimers()
    T.eq(n, 0, "enemies' plates in a battleground: nothing of ours")
    stub.FireEvent("UNIT_FACTION", "party1")
    stub.RunTimers()
    UF.UpdateStatus = orig
    T.truthy(n > 0, "a member's PvP flag repaints")
    T.truthy(ns.OurUnit("raid12") and ns.OurUnit("target") and not ns.OurUnit("nameplate4"))
end)

local function settle()
    local d = DaylightUI.Motion.Driver()
    for _ = 1, 60 do
        if not (d and d:GetScript("OnUpdate")) then return end
        stub.RunOnUpdate(d, 1 / 60)
    end
end

T.test("your target's party button gets the outline; it moves with a new target", function()
    local DUI, ns = login()
    local b1 = button(ns, 1, "party1", { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 })
    local b2 = button(ns, 2, "party2", { name = "Lift", isPlayer = true, class = "PRIEST", health = 5, maxHealth = 10 })
    stub.units.target = stub.units.party2
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    settle()
    T.truthy(b2.targetMark:IsShown())
    T.eq(b2.targetMark:GetAlpha(), 1)
    T.eq(b1.targetMark:GetAlpha(), 0)
    stub.units.target = stub.units.party1
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    settle()
    T.eq(b1.targetMark:GetAlpha(), 1)
    T.eq(b2.targetMark:GetAlpha(), 0, "the old one fades away")
    DUI:Set("UnitFrames", "party.targetMark", false)
    stub.RunTimers()
    T.falsy(b1.targetMark:IsShown(), "switched off")
end)

T.test("the target outline: a secret answer in a battleground goes straight to the client", function()
    local _, ns = login()
    local b = button(ns, 1, "party1", { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 })
    -- The fake game hides comparisons only for enemies: answer secret here.
    local real = _G.UnitIsUnit
    _G.UnitIsUnit = function(a, c) return stub.Secret(a == "party1" and c == "target") end
    T.noerror(function() stub.FireEvent("PLAYER_TARGET_CHANGED") end)
    _G.UnitIsUnit = real
    T.truthy(b.targetMark.__alphaFromBoolean, "the alpha comes from the secret answer")
    T.eq(stub.Plain(b.targetMark:GetAlpha()), 1)
end)

T.test("the target outline: custom color, and the sample shows it", function()
    local DUI, ns = login()
    local b = button(ns, 1, "party1", { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 })
    DUI:Set("UnitFrames", "party.targetMarkColor", "custom")
    DUI:Set("UnitFrames", "party.targetMarkCustom", { 0, 1, 0 })
    stub.RunTimers()
    T.rgb({ b.targetMark.ring.border.LEFT:GetVertexColor() }, { 0, 1, 0 })
    -- The ring follows the tile's angle and sits under the portrait.
    local sl, ml = DUI.Style.GetSlant(b), DUI.Style.GetSlant(b.targetMark)
    T.truthy(sl and sl.side, "the party button is angled")
    T.eq(ml and ml.side, sl.side, "the ring takes the same angled end")
    T.truthy(b.targetMark.cutEdge[sl.side]:IsShown(), "drawn by one thin sheared strip")
    T.falsy(b.targetMark.ring.slantFill[sl.side]:IsShown(), "not the shell's wedge (nothing inside to cover it)")
    T.rgb({ b.targetMark.cutEdge[sl.side]:GetVertexColor() }, { 0, 1, 0 })
    -- Angle off: a plain rounded ring, both ends square.
    DUI:Set("UnitFrames", "party.slant", false)
    stub.RunTimers()
    local off = DUI.Style.GetSlant(b.targetMark)
    T.isnil(off and off.side, "no angle on the ring either")
    T.falsy(b.targetMark.cutEdge.right:IsShown())
    T.falsy(b.targetMark.cutEdge.left:IsShown())
    T.truthy(b.targetMark.ring.border.RIGHT:IsShown(), "the right end is the ring's own straight edge")
    T.truthy(b.targetMark.ring.border.LEFT:IsShown())
    DUI:Set("UnitFrames", "party.slant", true)
    stub.RunTimers()
    T.truthy(b.targetMark.cutEdge.right:IsShown(), "and back")
    T.truthy(b.portrait == nil or b.targetMark:GetFrameLevel() < b.portrait:GetFrameLevel())
    DUI.SetTestMode(true)
    stub.RunTimers()
    T.truthy(ns.Party.preview[3].targetMark:IsShown(), "Shallan, the sample target")
    T.falsy(ns.Party.preview[1].targetMark:IsShown())
    DUI.SetTestMode(false)
    stub.RunTimers()
end)

T.test("the target outline leaves a tile whose unit word now holds someone else", function()
    local _, ns = login()
    local b = button(ns, 2, "party2", { name = "Lift", isPlayer = true, class = "PRIEST", health = 5, maxHealth = 10 })
    stub.units.target = stub.units.party2
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    settle()
    T.eq(b.targetMark:GetAlpha(), 1)
    stub.units.party2 = { name = "Dalinar", isPlayer = true, class = "WARRIOR", health = 9, maxHealth = 10 }
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    stub.RunTimers()
    settle()
    T.eq(b.targetMark:GetAlpha(), 0, "Dalinar isn't your target")
end)

T.test("a button the header moved to a new unit isn't redone again by the roster pass", function()
    local _, ns = login()
    local b = button(ns, 1, "party1", { name = "Lift", isPlayer = true, class = "PRIEST", health = 5, maxHealth = 10 })
    stub.RunTimers()
    stub.units.party3 = { name = "Dalinar", isPlayer = true, class = "WARRIOR", health = 9, maxHealth = 10 }
    local UF, n = ns.UF, 0
    local orig = UF.UpdateAll
    UF.UpdateAll = function(f, ...) if f == b then n = n + 1 end; return orig(f, ...) end
    b:SetAttribute("unit", "party3")
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    stub.RunTimers()
    UF.UpdateAll = orig
    T.eq(n, 1, "the unit change redid it once; the roster pass only reads crown and role")
    T.eq(b.nameText.__text, "Dalinar")
end)

T.test("your own party tile fades by the party's fade, never the player frame's full-health one", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "player.fade.fullHealth", true)
    stub.RunTimers()
    -- Hurt: the player frame would stay shown.
    local b = button(ns, 1, "player", { name = "Lift", isPlayer = true, class = "PRIEST", health = 4, maxHealth = 10 })
    ns.UF.PaintFade(b, 0.3)
    T.near(b:GetAlpha(), 0.3, 1e-6, "the party's alpha as given")
end)

T.test("floating mode: someone joining wakes the party and raid tiles; leaving or a shuffle doesn't", function()
    local DUI = login(function() stub.SetGroup(true, false, 2) end)
    local woke = {}
    local wake = DUI.Fade.Wake
    DUI.Fade.Wake = function(key) woke[#woke + 1] = key end
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    T.eq(#woke, 0, "the same people: nothing changed")
    stub.SetGroup(true, false, 3)
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    T.eq(table.concat(woke, " "), "UnitFrames.party UnitFrames.raid", "one more: the tiles come back")
    woke = {}
    stub.SetGroup(true, false, 2)
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    T.eq(#woke, 0, "someone left")
    stub.SetGroup(true, false, 3)
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    T.eq(#woke, 2, "counts from the group as it is now, not its biggest")
    DUI.Fade.Wake = wake
end)

T.test("party debuffs show their tooltip on hover by default; clicks still go to the tile", function()
    stub.Widget.SetMouseClickEnabled = function(self, on) self.__clicks = on end
    stub.Widget.SetMouseMotionEnabled = function(self, on) self.__motion = on end
    local DUI, ns = login()
    local b = button(ns, 1, "party1", { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 })
    stub.RunTimers()
    T.eq(DUI:Get("UnitFrames", "party.auras.debuffs.tooltips"), true, "on by default")
    T.eq(DUI:Get("UnitFrames", "party.auras.cc.tooltips"), true, "crowd control too")
    local btn = b.auraSet.debuffs.__groups.all.button
    T.eq(btn.__motion, true, "the icon takes the hover: its tooltip shows")
    T.eq(btn.__clicks, false, "a click reaches the tile (click-casting)")
    T.eq(DUI:Get("UnitFrames", "raid.auras.debuffs.tooltips"), false, "raid tiles keep the hover for mouseover casting")
end)

T.test("icon spots with a name tab: home rides with the tab, a picked spot moves the icon there", function()
    local DUI, ns = login()
    local b = button(ns, 1, "party1", { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5,
                                        maxHealth = 10, role = "TANK", leader = true, raidTarget = 8 })
    stub.RunTimers()
    T.falsy(b.cornerMode, "the default look: a name tab")
    T.truthy(b.status.icons.role:IsShown(), "home: the role rides with the tab")
    T.falsy(b.roleIcon:IsShown())
    T.isnil(b.markerSpot, "the marker stays in the tab")
    -- Nudged at home: from where it sits there.
    local rx, ly = select(4, b.status.icons.role:GetPoint(1)), select(5, b.status.icons.leader:GetPoint(1))
    DUI:Set("UnitFrames", "party.roleX", 5)
    DUI:Set("UnitFrames", "party.leaderY", -4)
    stub.RunTimers()
    T.near(select(4, b.status.icons.role:GetPoint(1)), rx + 5, 0.01, "the role's nudge counts at home")
    T.near(select(5, b.status.icons.leader:GetPoint(1)), ly - 4, 0.01, "so does the crown's")
    -- A picked size counts there too.
    DUI:Set("UnitFrames", "party.roleSize", 20)
    stub.RunTimers()
    T.eq(b.status.icons.role:GetWidth(), 20)
    -- Moved to a spot: the corner icons, tab or not.
    DUI:Set("UnitFrames", "party.rolePos", "topright")
    DUI:Set("UnitFrames", "party.leaderPos", "outleft")
    DUI:Set("UnitFrames", "party.markerPos", "bottomright")
    stub.RunTimers()
    T.falsy(b.cornerMode)
    T.truthy(b.tab:IsShown(), "the tab stays")
    T.truthy(b.roleIcon:IsShown(), "the role at its spot")
    T.falsy(b.status.icons.role:IsShown(), "not on the tab")
    T.eq((b.roleIcon:GetPoint(1)), "TOPRIGHT")
    T.eq(b.leaderSpot, "outleft")
    T.truthy(b.leaderIcon:IsShown(), "the crown at its spot")
    T.eq(b.status.icons.leader:GetAlpha(), 0, "not over the tab")
    T.eq(b.markerSpot, "bottomright")
    T.eq(b.marker:GetParent(), b.overlay, "the marker leaves the tab")
    T.eq(#stub.errors, 0)
end)

T.test("a role picked off home keeps aura rows clear of it with a name tab; home reserves nothing", function()
    local DUI, ns = login()
    local b = button(ns, 2, "party2", { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5,
                                        maxHealth = 10, role = "TANK" })
    local box = ns.AuraGroups.Box(b, DUI:Get("UnitFrames", "party"))
    T.isnil(next(box.corners), "home: nothing in the corners")
    DUI:Set("UnitFrames", "party.rolePos", "bottomleft")
    stub.RunTimers()
    box = ns.AuraGroups.Box(b, DUI:Get("UnitFrames", "party"))
    T.eq(box.corners.bottomleft, DUI:Get("UnitFrames", "party.roleSize") + 1)
    T.isnil(box.corners.topright, "the dispel icon is left out with a tab, as before")
end)

T.test("Show leader crown in combat counts for the crown on the name tab", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "party.leaderHideInCombat", true)
    local b = button(ns, 1, "party1", { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5,
                                        maxHealth = 10, leader = true })
    stub.RunTimers()
    T.eq(b.status.icons.leader:GetAlpha(), 1)
    ns.UF.fighting = true
    ns.UF.UpdateLeader(b)
    T.eq(b.status.icons.leader:GetAlpha(), 0, "hidden in a fight")
    ns.UF.fighting = false
end)
