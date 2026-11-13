local stub = require("stub")

local SINGLE = { "player", "target", "focus", "targettarget", "pet" }

local function load() return stub.Load({ module = true }) end

-- A page's sample on a shown box, drawn once.
local function sample(ns, id, width, maxH)
    local box = CreateFrame("Frame", nil, UIParent)
    local s = ns.PageSample.New(id, box)
    local h = s.Refresh(width or 600, maxH or 120)
    return s, h
end

-- Each part label, with how many spots it has.
local function labels(parts)
    local out = {}
    for _, p in ipairs(parts) do out[p.label] = (out[p.label] or 0) + 1 end
    return out
end

-- Every setting key on a unit frames page.
local function pageKeys(DUI, id)
    local keys = {}
    for _, g in ipairs(DUI.Options.GetPage("UnitFrames." .. id).groups) do
        for _, item in ipairs(g.items) do
            if item.key then keys[item.key] = true end
        end
    end
    return keys
end

T.test("each frame page's sample is its own frame, fitted to the room given", function()
    local _, ns = load()
    for _, id in ipairs(SINGLE) do
        local s, h = sample(ns, id)
        T.truthy(h > 0 and h <= 120, id .. ": height " .. tostring(h))
        T.eq(s.frame:GetWidth(), 600, id)
        T.eq(s.f.spec.unit, id)
        T.truthy(s.f.test, id .. ": filled with a sample unit")
        T.falsy(s.f:IsMouseEnabled(), id .. ": only to look at")
    end
    T.eq(#stub.errors, 0)
end)

T.test("the pet sample shows happiness while it's on, and design mode can move it", function()
    local DUI, ns = load()
    local s = sample(ns, "pet")
    local found
    for _, p in ipairs(s.Parts()) do
        if p.label == "Pet happiness" then found = p end
    end
    T.truthy(found and found.region:IsVisible(), "shown in the preview")
    T.eq(found.move.spotKey, "pet.happinessSpot")
    T.eq(found.move.xKey, "pet.happinessX")
    T.eq(found.move.yKey, "pet.happinessY")
    T.eq(found.size.keys.s, "pet.happinessSize")
    DUI:Set("UnitFrames", "pet.happiness", false)
    s.Refresh(600, 120)
    for _, p in ipairs(s.Parts()) do
        T.falsy(p.label == "Pet happiness", "hidden while the switch is off")
    end
end)

T.test("every part showing leads to settings its page has", function()
    local DUI, ns = load()
    for _, id in ipairs(SINGLE) do
        local s = sample(ns, id)
        local parts, keys = s.Parts(), pageKeys(DUI, id)
        T.eq(#s.missing, 0, id .. ": " .. table.concat(s.missing, ", "))
        local seen = labels(parts)
        T.truthy(seen["Health bar"] and seen["Name"], id .. ": the health bar and the name")
        for _, p in ipairs(parts) do
            T.truthy(#p.keys > 0, id .. " " .. p.label)
            T.truthy(p.region:IsVisible(), id .. " " .. p.label .. " shows")
            for _, k in ipairs(p.keys) do T.truthy(keys[k], id .. " " .. p.label .. ": " .. k) end
        end
    end
end)

T.test("with everything switched on, no part showing is left without settings", function()
    local DUI, ns = load()
    local ON = { "showPercent", "showPowerText", "showMarker", "showClassification", "showLevel",
                 "showLeader", "showPvP", "showResting", "showRole" }
    for _, id in ipairs(SINGLE) do
        for _, k in ipairs(ON) do
            if DUI:Get("UnitFrames", id .. "." .. k) ~= nil then DUI:Set("UnitFrames", id .. "." .. k, true) end
        end
        local s = sample(ns, id)
        T.truthy(#s.Parts() > 0, id)
        T.eq(#s.missing, 0, id .. ": " .. table.concat(s.missing, ", "))
    end
    -- The other looks: the health text instead of the large number, the
    -- crest on the tab without a portrait, the name on the bar.
    DUI:Set("UnitFrames", "player.bigNumber", false)
    DUI:Set("UnitFrames", "target.portrait", "none")
    DUI:Set("UnitFrames", "focus.nameOnBar", true)
    for _, id in ipairs({ "player", "target", "focus" }) do
        local s = sample(ns, id)
        local seen = labels(s.Parts())
        T.eq(#s.missing, 0, id .. ": " .. table.concat(s.missing, ", "))
        if id == "player" then T.truthy(seen["Health text"], "player: the health text") end
        if id == "target" then T.truthy(seen["Elite crest"], "target: the crest on its tab") end
    end
end)

T.test("the sample follows the settings: size, name on the bar, portrait off", function()
    local DUI, ns = load()
    local s = sample(ns, "target")
    DUI:Set("UnitFrames", "target.width", 250)
    s.Refresh(600, 120)
    T.near(s.f:GetWidth(), 250, 2, "the new width")
    DUI:Set("UnitFrames", "target.nameOnBar", true)
    s.Refresh(600, 120)
    local name
    for _, p in ipairs(s.Parts()) do if p.label == "Name" then name = p end end
    T.eq(name.region, s.f.nameText, "the name's spot follows it onto the bar")
    DUI:Set("UnitFrames", "target.portrait", "none")
    s.Refresh(600, 120)
    T.isnil(labels(s.Parts())["Portrait"], "no portrait, nothing to click there")
end)

T.test("a frame switched off is drawn faded", function()
    local DUI, ns = load()
    DUI:Set("UnitFrames", "focus.enabled", false)
    local s = sample(ns, "focus")
    T.eq(s.f:GetAlpha(), ns.PageSample.OFF_ALPHA)
    DUI:Set("UnitFrames", "focus.enabled", true)
    s.Refresh(600, 120)
    T.eq(s.f:GetAlpha(), 1)
end)

T.test("the target's sample carries its auras, and makes room for them", function()
    local DUI, ns = load()
    local s = sample(ns, "target")
    local seen = labels(s.Parts())
    T.truthy(seen["Debuffs"] and seen["Buffs"], "the sample debuffs and buffs can be clicked")
    local tall = s.Refresh(2000, 2000)
    DUI:Set("UnitFrames", "targetAuras.debuffs", false)
    DUI:Set("UnitFrames", "targetAuras.buffs", false)
    local short = s.Refresh(2000, 2000)
    T.truthy(short < tall, "less room without them: " .. short .. " vs " .. tall)
    T.isnil(labels(s.Parts())["Debuffs"])
end)

T.test("big settings never make the sample taller or wider than its room", function()
    local DUI, ns = load()
    for k, v in pairs({ width = 400, height = 80, portraitScale = 1.5 }) do DUI:Set("UnitFrames", "target." .. k, v) end
    for k, v in pairs({ debuffRows = 6, maxDebuffs = 16, maxOtherDebuffs = 16, buffRows = 6, maxBuffs = 12, debuffSize = 48 }) do
        DUI:Set("UnitFrames", "targetAuras." .. k, v)
    end
    local s, h = sample(ns, "target", 300, 120)
    T.truthy(h <= 120, "height " .. h)
    local scale = s.f:GetScale()
    T.truthy(scale < 1, "shrunk to fit")
    T.truthy(s.f:GetWidth() * scale <= 300, "within the width")
end)

T.test("changing a setting in combat redraws the sample, never the real auras", function()
    local DUI, ns = load()
    local s = sample(ns, "target")
    local real = ns.auras.debuffs.__groups.mine.button
    local w = real:GetWidth()
    stub.EnterCombat()
    DUI:Set("UnitFrames", "targetAuras.debuffSize", w + 14)
    s.Refresh(600, 120)
    T.eq(real:GetWidth(), w, "the real buttons wait for the fight to end")
    T.eq(ns.Auras.HolderFor(s.auras.debuffs).pool[1]:GetWidth(), w + 14, "the sample's icons change now")
    T.eq(#stub.errors, 0)
    stub.LeaveCombat()
end)

T.test("the party preview is one member carrying every piece, calm, to drag each one", function()
    local DUI, ns = load()
    local s, h = sample(ns, "party")
    T.truthy(h > 0 and h <= 120, "height " .. tostring(h))
    T.eq(#s.members, 1, "one member: two made Design mode drags confusing")
    local b = s.members[1]
    T.truthy(b:IsShown())
    T.isnil(b.test.threat, "no red aggro ring on the preview")
    T.truthy(b.test.dispel and b.test.marker and b.test.leader and b.test.role, "every corner icon")
    local seen = labels(s.Parts())
    T.eq(seen["Health bar"], 1)
    T.eq(seen["Debuffs"], 1); T.eq(seen["Buffs"], 1)
    DUI:Set("UnitFrames", "party.hideSelf", false)
    s.Refresh(600, 120)
    T.eq(#s.members, 1)
    T.eq(#stub.errors, 0)
end)

T.test("the party's parts: each member's frame, debuffs and buffs", function()
    local DUI, ns = load()
    local s = sample(ns, "party")
    local parts, keys = s.Parts(), pageKeys(DUI, "party")
    T.eq(#s.missing, 0, table.concat(s.missing, ", "))
    local seen = labels(parts)
    T.eq(seen["Health bar"], 1, "the one member")
    T.truthy(seen["Debuffs"], "the debuff rows")
    T.truthy(seen["Buffs"], "the buff rows")
    for _, p in ipairs(parts) do
        for _, k in ipairs(p.keys) do T.truthy(keys[k], p.label .. ": " .. k) end
    end
end)

T.test("the party's sample makes room for the debuffs wherever they sit", function()
    local DUI, ns = load()
    local SPOT = { under = "below", over = "above", right = "outright", left = "outleft", inTop = "topright",
                   inBottom = "bottomright" }
    local function offset(at)
        DUI:Set("UnitFrames", "party.auras.debuffs.spot", SPOT[at])
        local s = sample(ns, "party", 600, 200)
        s.Parts()
        T.eq(#s.missing, 0, at .. ": " .. table.concat(s.missing, ", "))
        local _, _, _, x, y = s.holder:GetPoint(1)
        return x, y
    end
    local ux, uy = offset("under")
    T.truthy(offset("right") < ux, "outside the right: shifted left to fit them")
    T.truthy(offset("left") > ux, "outside the left: shifted right")
    local _, oy = offset("over")
    T.truthy(oy < uy, "over the frame: room above, none below")
    offset("inTop")
end)

T.test("the party's tile look: its parts still lead to its settings", function()
    local DUI, ns = load()
    for k, v in pairs({ portrait = "none", nameOnBar = true, showDispel = true, ["auras.buffs.spot"] = "bottomleft", fillVertical = true }) do
        DUI:Set("UnitFrames", "party." .. k, v)
    end
    local s = sample(ns, "party")
    s.Parts()
    T.eq(#s.missing, 0, table.concat(s.missing, ", "))
end)

T.test("the party's sample stays in its room however it's laid out", function()
    local DUI, ns = load()
    for k, v in pairs({ width = 300, height = 120, spacing = 80, direction = "columns", perLine = 1, groupSpacing = 80 }) do
        DUI:Set("UnitFrames", "party." .. k, v)
    end
    local s, h = sample(ns, "party", 500, 120)
    T.truthy(h <= 120, "height " .. h)
    local scale = s.holder:GetScale()
    T.truthy(s.holder:GetWidth() * scale <= 500, "within the width")
end)

T.test("the raid page has a preview, and every part on it leads to its settings", function()
    local DUI, ns = load()
    DUI:Set("UnitFrames", "raid.auras.buffs.show", true)
    local s, h = sample(ns, "raid")
    T.truthy(h > 0 and h <= 120, "height " .. tostring(h))
    T.eq(#s.missing, 0, table.concat(s.missing, ", "))
    local seen, keys = labels(s.Parts()), pageKeys(DUI, "raid")
    for _, want in ipairs({ "Health bar", "Name", "Debuffs", "Crowd control", "Buffs" }) do
        T.truthy(seen[want], "raid: " .. want)
    end
    for _, p in ipairs(s.Parts()) do
        T.truthy(#p.keys > 0, "raid " .. p.label)
        for _, k in ipairs(p.keys) do T.truthy(keys[k], "raid " .. p.label .. ": " .. k) end
    end
    T.truthy(DUI.Options.GetPage("UnitFrames.raid").sample, "the page shows it")
    T.eq(#stub.errors, 0)
end)

T.test("the raid preview is one tile carrying every piece, to drag each one", function()
    local _, ns = load()
    local s = sample(ns, "raid")
    T.eq(#s.members, 1)
    local seen = labels(s.Parts())
    T.eq(seen["Debuffs"], 1); T.eq(seen["Crowd control"], 1, "crowd control shows on the one tile")
    T.eq(seen["Health bar"], 1)
end)

T.test("a piece outside the tile on the preview makes room for itself", function()
    local DUI, ns = load()
    local inside = sample(ns, "raid", 900, 130).holder:GetScale()
    DUI:Set("UnitFrames", "raid.auras.debuffs.spot", "outtopright")
    local s = sample(ns, "raid", 900, 130)
    T.truthy(s.holder:GetScale() < inside, "drawn a little smaller to fit the piece above: " .. s.holder:GetScale())
    T.truthy(s.frame:GetHeight() <= 130)
end)

T.test("a group moved in the settings moves on the raid preview too", function()
    local DUI, ns = load()
    DUI:Set("UnitFrames", "raid.auras.debuffs.spot", "topleft")
    DUI:Set("UnitFrames", "raid.auras.debuffs.grow", "right")
    local s = sample(ns, "raid")
    local region
    for _, p in ipairs(s.Parts()) do if p.label == "Debuffs" then region = p.region end end
    T.truthy(region, "debuffs part")
    T.eq((region:GetPoint(1)), "TOPLEFT")
end)

T.test("the existing links still work: health bar and name on every frame page", function()
    local _, ns = load()
    for _, id in ipairs({ "player", "target", "focus", "targettarget", "pet", "party", "raid" }) do
        local s = sample(ns, id)
        local seen = labels(s.Parts())
        T.truthy(seen["Health bar"], id .. ": health bar")
        T.truthy(seen["Name"], id .. ": name")
    end
end)

T.test("the raid preview zooms: 3x to start, as the zoom says, never past its room", function()
    local _, ns = load()
    local s = sample(ns, "raid", 900, 220)
    T.eq(s.Zoom(), 3, "starts at 3x")
    T.eq(s.holder:GetScale(), 3)
    s.SetZoom(1.5)
    s.Refresh(900, 220)
    T.eq(s.holder:GetScale(), 1.5)
    s.SetZoom(9)
    T.eq(s.Zoom(), ns.PageSample.ZOOM_MAX, "kept within the slider's range")
    s.SetZoom(3)
    s.Refresh(150, 220)
    local scale = s.holder:GetScale()
    T.truthy(scale > 1 and scale < 3, "narrower: as big as fits, " .. scale)
    T.truthy(s.frame:GetWidth() <= 150)
    T.isnil(s.zoomText, "no more 'Shown at' note")
    -- The single frames and the party start as they are in game.
    local p = sample(ns, "party", 900, 220)
    T.truthy(p.holder:GetScale() <= 1)
end)

T.test("every frame page's preview zooms: 1x to start, each page its own, never past its room", function()
    local _, ns = load()
    for _, id in ipairs({ "player", "target", "focus", "targettarget", "pet", "party" }) do
        local s = sample(ns, id, 2000, 600)
        T.eq(s.Zoom(), 1, id .. " starts as in game")
        T.truthy(s.SetZoom and s.zoomRange, id .. " zooms")
        local box = s.holder or s.f
        local before = box:GetScale()
        s.SetZoom(2)
        s.Refresh(2000, 600)
        T.near(box:GetScale(), 2 * before, 0.01, id .. ": twice as big with room")
        s.SetZoom(4)
        s.Refresh(300, 100)
        T.truthy(box:GetScale() < 4, id .. ": no bigger than its room")
        s.SetZoom(1)
    end
    local t = sample(ns, "target")
    t.SetZoom(2.5)
    T.eq(sample(ns, "player").Zoom(), 1, "one page's zoom leaves the others alone")
    T.eq(sample(ns, "target").Zoom(), 2.5, "kept for the session")
    T.eq(sample(ns, "raid").Zoom(), ns.PageSample.RAID_ZOOM)
    t.SetZoom(1)
end)

local function byLabel(parts)
    local out = {}
    for _, p in ipairs(parts) do out[p.label] = out[p.label] or p end
    return out
end

T.test("raid preview pieces say how they move and resize", function()
    local DUI, ns = load()
    local s = sample(ns, "raid")
    local by = byLabel(s.Parts())
    local d = by["Debuffs"]
    T.eq(d.move.spotKey, "raid.auras.debuffs.spot")
    T.eq(d.move.xKey, "raid.auras.debuffs.x"); T.eq(d.move.yKey, "raid.auras.debuffs.y")
    T.eq(#d.move.dots, 17)
    T.eq(d.move.owner, d.region:GetParent(), "dots are the tile's")
    T.eq(d.size.keys.s, "raid.auras.debuffs.size")
    T.eq(d.size.min, 10); T.eq(d.size.max, 32); T.eq(d.size.step, 1, "from the page's own slider")
    T.eq(d.size.now.s, DUI:Get("UnitFrames", "raid.auras.debuffs.size"))
    local spot, x, y = d.move.drop(1, 1)
    T.eq(spot, "topleft"); T.eq(x, 0); T.eq(y, 0)
    T.eq(d.size.resize(12, 3, 10, 32, 1), 15)
    local m = by["Raid marker"]
    T.eq(m.move.spotKey, "raid.markerPos"); T.eq(#m.move.dots, 17, "icons go outside too")
    T.eq(m.move.xKey, "raid.markerX"); T.eq(m.move.yKey, "raid.markerY")
    T.eq(m.size.keys.s, "raid.markerSize")
    T.eq(by["Name"].move.spotKey, "raid.namePos"); T.eq(by["Name"].move.xKey, "raid.nameX")
    local h = by["Health bar"]
    T.isnil(h.move, "the frame itself doesn't move")
    T.eq(h.size.keys.w, "raid.width"); T.eq(h.size.keys.h, "raid.height")
    T.eq(h.size.min.w, 40); T.eq(h.size.max.h, 80)
end)

T.test("every frame's health and power text moves in Design mode, nudged from its one home", function()
    local DUI, ns = load()
    DUI:Set("UnitFrames", "focus.showPowerText", true)
    DUI:Set("UnitFrames", "pet.showPercent", true)
    DUI:Set("UnitFrames", "pet.showPowerText", true)
    DUI:Set("UnitFrames", "targettarget.showPercent", true)
    DUI:Set("UnitFrames", "player.bigNumber", false)
    for id, text in pairs({ player = { "Health text" }, target = { "Large health number" }, focus = { "Health text", "Power text" },
                            pet = { "Health text", "Power text" }, targettarget = { "Health text" } }) do
        local by = byLabel(sample(ns, id).Parts())
        for _, label in ipairs(text) do
            local key = label == "Power text" and "powerText" or "healthText"
            local m = by[label] and by[label].move
            T.truthy(m, id .. " " .. label .. " moves")
            T.isnil(m.spotKey, "no spot")
            T.eq(m.xKey, id .. "." .. key .. "X"); T.eq(m.yKey, id .. "." .. key .. "Y")
            T.eq(#m.dots, 1)
            T.eq(DUI:Get("UnitFrames", id .. "." .. key .. "X"), 0, id .. " has a default")
        end
    end
end)

T.test("a health text's home stays put whatever its nudge", function()
    local DUI, ns = load()
    DUI:Set("UnitFrames", "player.bigNumber", false)
    local s = sample(ns, "player")
    local part = byLabel(s.Parts())["Health text"]
    local owner, region = part.move.owner, part.region
    owner.GetLeft = function() return 100 end
    owner.GetTop = function() return 300 end
    region.GetCenter = function() return 150, 280 end
    local home = byLabel(s.Parts())["Health text"].move.dots[1]
    T.eq(home.x, 50); T.eq(home.y, 20)
    DUI:Set("UnitFrames", "player.healthTextX", 12)
    DUI:Set("UnitFrames", "player.healthTextY", -7)
    region.GetCenter = function() return 150 + 12, 280 - 7 end
    local d = byLabel(s.Parts())["Health text"].move.dots[1]
    T.near(d.x, home.x, 0.01); T.near(d.y, home.y, 0.01)
end)

T.test("the corner icons nudge from their spot, inside the frame and round it", function()
    local DUI, ns = load()
    local UF, f = ns.UF, CreateFrame("Frame", nil, UIParent)
    local rel, icon = CreateFrame("Frame", nil, f), f:CreateTexture()
    f:SetSize(100, 30)
    UF.PlaceSpot(icon, f, rel, "topright", 2, 1, 5, -3)
    local _, _, _, x, y = icon:GetPoint(1)
    T.eq(x, -2 + 5); T.eq(y, -1 - 3)
    UF.PlaceSpot(icon, f, rel, "above", 2, 1, 5, -3)
    local _, _, _, ax, ay = icon:GetPoint(1)
    UF.PlaceSpot(icon, f, rel, "above", 2, 1)
    local _, _, _, bx, by = icon:GetPoint(1)
    T.eq(ax, bx + 5); T.eq(ay, by - 3)
end)

T.test("the party page's pet is a piece: it drags between its four spots and resizes", function()
    local DUI, ns = load()
    DUI:Set("UnitFrames", "partyPet.enabled", true)
    local by = byLabel(sample(ns, "party").Parts())
    local p = by["Party pet"]
    T.truthy(p, "the pet is a part")
    T.eq(p.move.spotKey, "partyPet.spot"); T.eq(p.move.xKey, "partyPet.x")
    T.eq(#p.move.dots, 4)
    T.eq(p.size.keys.w, "partyPet.width")
    local at = {}
    for _, d in ipairs(p.move.dots) do at[d.spot] = d end
    local b = p.move.owner
    T.truthy(at.right.x > b:GetWidth(), "right of it"); T.truthy(at.left.x < 0, "left of it")
    T.truthy(at.below.y > b:GetHeight(), "under it"); T.truthy(at.above.y < 0, "over it")
    T.isnil(byLabel(sample(ns, "raid").Parts())["Party pet"], "the raid's tiles have none")
end)

T.test("on an angled tile, the dots on the slanted side sit in from the cut", function()
    local DUI, ns = load()
    DUI:Set("UnitFrames", "raid.slant", true)
    local s = sample(ns, "raid")
    local d = byLabel(s.Parts())["Debuffs"]
    local tile = d.move.owner
    T.truthy((tile.cut or 0) > 0, "the tile is angled")
    local tr
    for _, dot in ipairs(d.move.dots) do if dot.spot == "topright" then tr = dot end end
    T.truthy(tr.x <= tile:GetWidth() - tile.cut, "clear of the cut: " .. tr.x)
end)

T.test("single frames: the health bar resizes the frame; the name tab moves along the top", function()
    local _, ns = load()
    local by = byLabel(sample(ns, "player").Parts())
    T.eq(by["Health bar"].size.keys.w, "player.width")
    T.eq(by["Name"].move.spotKey, "player.tab.at")
end)

T.test("the raid preview tile is calm: no aggro border, but it carries a dispel icon", function()
    local _, ns = load()
    local s = sample(ns, "raid")
    local b = s.members[1]
    T.isnil(b.test.threat, "no red aggro border on the preview")
    T.truthy(b.test.dispel, "a dispellable debuff, so its icon can be placed")
    T.truthy(b.sampleDispel:IsShown(), "the dispel icon shows")
    T.truthy(byLabel(s.Parts())["Dispellable debuff"], "and can be clicked")
end)

T.test("a switched-off aura group isn't on the raid preview", function()
    local DUI, ns = load()
    DUI:Set("UnitFrames", "raid.auras.debuffs.show", false)
    local s = sample(ns, "raid")
    T.isnil(byLabel(s.Parts())["Debuffs"], "off = not shown")
    T.truthy(byLabel(s.Parts())["Crowd control"], "the ones that are on still are")
end)

T.test("a tile's corner icons can sit outside it", function()
    local DUI, ns = load()
    DUI:Set("UnitFrames", "raid.markerPos", "outleft")
    DUI:Set("UnitFrames", "raid.rolePos", "above")
    local s = sample(ns, "raid")
    local b = s.members[1]
    local p, rel, rp = b.marker:GetPoint(1)
    T.eq(p, "RIGHT"); T.eq(rel, b); T.eq(rp, "LEFT", "the marker hangs off the tile's left side")
    p, rel, rp = b.roleIcon:GetPoint(1)
    T.eq(p, "BOTTOM"); T.eq(rel, b); T.eq(rp, "TOP", "the role icon sits above the tile")
    local items = {}
    for _, g in ipairs(DUI.Options.GetPage("UnitFrames.raid").groups) do
        for _, item in ipairs(g.items) do if item.key then items[item.key] = item end end
    end
    T.truthy(items["raid.markerPos"].values.outleft, "the spot list offers outside spots")
    local found
    for _, k in ipairs(items["raid.markerPos"].order) do if k == "outbottomright" then found = true end end
    T.truthy(found, "in its order too")
end)

T.test("the power bar's grips: its thickness, with the frame growing by as much", function()
    local _, ns = load()
    local s = sample(ns, "target")
    local pw = byLabel(s.Parts())["Power bar"]
    T.truthy(pw, "the target shows its power bar")
    T.eq(pw.size.keys.w, "target.width")
    T.eq(pw.size.keys.h, "target.powerHeight")
    T.eq(pw.size.link.h.key, "target.height", "the frame grows with it, so the health bar keeps its size")
end)

T.test("raid tiles: the power bar goes to 20 px, the tile to 80 tall", function()
    local _, ns = load()
    local pw = byLabel(sample(ns, "raid").Parts())["Power bar"]
    T.eq(pw.size.max.h, 20)
    T.eq(pw.size.link.h.max, 80)
end)

T.test("party and target preview aura pieces move and resize in Design mode, by their own keys", function()
    local DUI, ns = load()
    local s = sample(ns, "party")
    local d = byLabel(s.Parts())["Debuffs"]
    T.truthy(d, "a party debuff piece")
    T.eq(d.move.spotKey, "party.auras.debuffs.spot")
    T.eq(d.move.xKey, "party.auras.debuffs.x")
    T.eq(d.size.keys.s, "party.auras.debuffs.size")
    s = sample(ns, "target")
    local by = byLabel(s.Parts())
    T.eq(#s.missing, 0, table.concat(s.missing, ", "))
    d = by["Debuffs"]
    T.eq(d.move.spotKey, "targetAuras.debuffSpot")
    T.eq(d.move.xKey, "targetAuras.debuffX"); T.eq(d.move.yKey, "targetAuras.debuffY")
    T.eq(d.move.owner.spec.unit, "target", "dots are the target frame's")
    T.eq(d.size.keys.s, "targetAuras.debuffSize")
    T.eq(by["Buffs"].move.spotKey, "targetAuras.buffSpot")
    T.eq(by["Buffs"].size.keys.s, "targetAuras.buffSize")
end)

T.test("the player's level badge shows on its preview and drags in Design mode", function()
    local DUI, ns = load()
    DUI:Set("UnitFrames", "player.showLevel", true)
    local s = sample(ns, "player")
    local part
    for _, p in ipairs(s.Parts()) do if p.label == "Level" then part = p end end
    T.truthy(part, "the badge is on the preview")
    T.truthy(part.move and part.move.spotKey == "player.levelPos", "it moves by levelPos")
    T.eq(part.move.xKey, "player.levelX")
end)
