local stub = require("stub")

-- The nameplates' options pages show a live sample plate above the settings,
-- drawn by the plate's own code.

local PAGES = { "plates", "target", "bars", "threat", "cast", "auras", "friendly" }

local function load(class)
    stub.Load({ nameplates = true, before = function()
        stub.units = { player = { name = "Me", class = class or "PRIEST", isPlayer = true } }
    end })
    stub.RunTimers()
    return DaylightUI, stub.nameplates
end

-- A page's sample on a shown box, drawn once.
local function sample(ns, id, width, maxH)
    local box = CreateFrame("Frame", nil, UIParent)
    local s = ns.Sample.New(id, box)
    local h = s.Refresh(width or 600, maxH or 200)
    return s, h
end

-- How many spots each part label has.
local function labels(parts)
    local out = {}
    for _, p in ipairs(parts) do out[p.label] = (out[p.label] or 0) + 1 end
    return out
end

local function partOf(parts, label)
    for _, p in ipairs(parts) do
        if p.label == label then return p end
    end
end

local function pageKeys(DUI, id)
    local keys = {}
    for _, g in ipairs(DUI.Options.GetPage("Nameplates." .. id).groups) do
        for _, item in ipairs(g.items) do
            if item.key then keys[item.key] = true end
        end
    end
    return keys
end

T.test("nameplate sample: every page has one, fitted to the room, only to look at", function()
    local DUI, ns = load()
    for _, id in ipairs(PAGES) do
        T.truthy(DUI.Options.GetPage("Nameplates." .. id).sample, id .. ": the page carries a sample")
        local s, h = sample(ns, id)
        T.truthy(h > 0 and h <= 200, id .. ": height " .. tostring(h))
        T.eq(s.frame:GetWidth(), 600, id)
        T.truthy(s.p:IsShown(), id .. ": the plate shows")
        T.truthy(s.p.isSample, id)
        T.falsy(s.p:IsMouseEnabled(), id .. ": only to look at")
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplate sample: every piece showing leads to settings on its page", function()
    local DUI, ns = load()
    for _, id in ipairs(PAGES) do
        local s = sample(ns, id)
        local parts, keys = s.Parts(), pageKeys(DUI, id)
        T.eq(#s.missing, 0, id .. ": " .. table.concat(s.missing, ", "))
        for _, p in ipairs(parts) do
            T.truthy(#p.keys > 0 or p.move or p.size, id .. " " .. p.label .. ": settings here, or it moves or resizes")
            T.truthy(p.region:IsVisible(), id .. " " .. p.label .. " shows")
            for _, k in ipairs(p.keys) do T.truthy(keys[k], id .. " " .. p.label .. ": " .. k) end
        end
    end
end)

T.test("nameplate sample: the enemy is your target, carrying every piece", function()
    local _, ns = load()
    local s = sample(ns, "plates")
    local p = s.p
    T.eq(stub.Text(p.name), "Sadeas")
    T.truthy(p.outline:IsShown(), "your target's outline")
    T.truthy(p.cast:IsShown(), "a cast part way")
    T.eq(stub.Text(p.cast.text), DaylightUI.L["Shadow Bolt"])
    T.truthy(p.marker:IsShown() and p.quest:IsShown() and p.questCount:IsShown(), "marker and quest mark")
    T.eq(stub.Text(p.percent), "62%")
    local seen = labels(ns.Sample.New("auras", CreateFrame("Frame", nil, UIParent)).Parts())
    T.eq(seen["Your debuffs"], nil, "an unrefreshed sample shows nothing")
    local a = sample(ns, "auras")
    seen = labels(a.Parts())
    T.eq(seen["Your debuffs"], 3)
    T.eq(seen["Crowd control"], 1)
    T.eq(seen["Buffs"], 1)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplate sample: it follows the settings at once", function()
    local DUI, ns = load()
    local s = sample(ns, "auras")
    DUI:Set("Nameplates", "maxDebuffs", 2)
    s.Refresh(600, 200)
    T.eq(labels(s.Parts())["Your debuffs"], 2)
    DUI:Set("Nameplates", "debuffs", false)
    s.Refresh(600, 200)
    T.isnil(labels(s.Parts())["Your debuffs"], "switched off: gone")
    DUI:Set("Nameplates", "width", 220)
    s.Refresh(600, 200)
    T.near(s.p.hp:GetWidth(), 220 * DUI:Get("Nameplates", "target.width"), 1, "the bar's width")
    DUI:Set("Nameplates", "castIcon", true)
    local c = sample(ns, "cast")
    T.truthy(labels(c.Parts())["Spell icon"], "the spell icon")
    DUI:Set("Nameplates", "castIcon", false)
    c.Refresh(600, 200)
    T.isnil(labels(c.Parts())["Spell icon"], "no spell icon")
end)

T.test("nameplate sample: the friendly page shows a friendly player", function()
    local DUI, ns = load()
    DUI:Set("Nameplates", "friendly.enabled", true)
    DUI:Set("Nameplates", "friendly.myBuffs", true)
    local s = sample(ns, "friendly")
    local p = s.p
    T.eq(stub.Text(p.name), "Navani")
    T.eq(stub.Text(p.sub), "<Bridge Four>")
    T.falsy(p.cast:IsShown(), "no cast")
    T.falsy(p.marker:IsShown(), "no marker")
    T.falsy(p.outline:IsShown(), "not your target")
    local seen = labels(s.Parts())
    T.truthy(seen["Health bar"] and seen["Name"] and seen["Guild name"])
    T.eq(seen["Your buffs"], 2)
    DUI:Set("Nameplates", "friendly.enabled", false)
    s.Refresh(600, 200)
    T.isnil(labels(s.Parts())["Health bar"], "name only")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplate sample: threat shows on its own page only", function()
    local DUI, ns = load()
    DUI:Set("Nameplates", "threat", true)
    DUI:Set("Nameplates", "threatGlow", true)
    T.truthy(sample(ns, "threat").p.threatGlow:IsShown(), "the threat page shows it")
    T.falsy(sample(ns, "plates").p.threatGlow:IsShown(), "other pages don't")
end)

T.test("nameplate sample: combo points only for rogues and druids", function()
    local _, ns = load("PRIEST")
    T.isnil(sample(ns, "plates").p.comboRow, "a priest's General page")
    local s = sample(ns, "target")
    T.isnil(s.p.comboRow, "not even on the Target page")
    T.isnil(labels(s.Parts())["Combo points"])
    T.isnil(ns.Combo.row, "the real row: a priest has none")
    for _, class in ipairs({ "ROGUE", "DRUID" }) do
        local DUI
        DUI, ns = load(class)
        T.truthy(sample(ns, "plates").p.comboRow, class .. " sees them everywhere")
        T.truthy(ns.Combo.row ~= sample(ns, "plates").p.comboRow, "on its own row, not the real one")
        s = sample(ns, "target")
        T.truthy(labels(s.Parts())["Combo points"], class)
        -- The cast bar below the health bar makes room.
        local _, _, _, _, y = s.p.cast:GetPoint(1)
        T.truthy(y < -(s.p.hp:GetHeight() + ns.Cast.GAP), "the cast bar moved down")
        DUI:Set("Nameplates", "comboPoints", false)
        s.Refresh(600, 200)
        T.isnil(s.p.comboRow, "switched off: gone")
    end
end)

T.test("nameplate sample: Design mode grips write the page's own sliders", function()
    local _, ns = load()
    local parts = sample(ns, "plates").Parts()
    local bar = partOf(parts, "Health bar")
    T.eq(bar.size.keys.w, "width")
    T.eq(bar.size.keys.h, "height")
    T.eq(bar.size.max.w, 300)
    T.eq(partOf(parts, "Cast bar").size.keys.h, "castHeight")
    T.eq(partOf(sample(ns, "bars").Parts(), "Raid marker").size.keys.s, "markerSize")
    T.eq(partOf(sample(ns, "auras").Parts(), "Your debuffs").size.keys.s, "debuffSize")
    T.eq(partOf(sample(ns, "friendly").Parts(), "Name").size.keys.s, "friendly.nameSize")
    T.eq(ns.Sample.Resize(170, 13.4, 60, 300, 1), 183)
    T.eq(ns.Sample.Resize(170, 500, 60, 300, 1), 300, "within the slider's range")
end)

T.test("nameplate sample: the threat % drags to any spot and resizes in Design mode, on every page, in its color", function()
    local DUI, ns = load()
    DUI:Set("Nameplates", "threatPct", true)
    stub.RunTimers()
    for _, id in ipairs({ "plates", "bars", "threat", "auras" }) do
        local s = sample(ns, id)
        T.truthy(s.p.threatPct:IsShown(), id .. ": the sample shows it")
        local part = partOf(s.Parts(), "Threat %")
        T.truthy(part and part.move, id .. ": it moves")
        T.eq(part.move.spotKey, "threatPctPos", id)
        T.eq(#part.move.dots, 17, id .. ": any spot, on the bar too")
        T.eq(part.size.keys.s, "threatPctSize", id .. ": and resizes")
    end
    -- The Threat page's chips show each state's number and color.
    ns.Sample.threatView = "aggro"
    local s = sample(ns, "threat")
    T.eq(s.p.threatPct:GetText(), "100%")
    DUI:Set("Nameplates", "threatPctColor", "custom")
    DUI:Set("Nameplates", "threatPctCustom", { 0.2, 0.4, 0.9 })
    stub.RunTimers()
    s = sample(ns, "threat")
    T.near(select(3, s.p.threatPct:GetTextColor()), 0.9, 1e-6, "One color: the picked color")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplate sample: Design mode moves the name, marks and rows, each to its own spots", function()
    local DUI, ns = load()
    local bars = sample(ns, "bars")
    local parts = bars.Parts()
    local name = partOf(parts, "Name")
    T.eq(name.move.spotKey, "namePos"); T.eq(name.move.xKey, "nameX"); T.eq(name.move.yKey, "nameY")
    T.eq(name.move.owner, bars.p.hp, "dots round the health bar")
    T.eq(#name.move.dots, 17, "any spot, on the bar too")
    T.eq(partOf(parts, "Raid marker").move.spotKey, "markerPos")
    T.eq(partOf(parts, "Quest mark").move.spotKey, "questPos")
    local auras = sample(ns, "auras").Parts()
    local deb = partOf(auras, "Your debuffs")
    T.eq(deb.move.spotKey, "debuffSpot")
    T.eq(#deb.move.dots, 8, "a row: round the bar only")
    local below
    for _, d in ipairs(deb.move.dots) do if d.spot == "below" then below = d end end
    local spot, x, y = deb.move.drop(below.x + 1, below.y)
    T.eq(spot, "below"); T.eq(x, 0); T.eq(y, 0)
    T.eq(partOf(auras, "Crowd control").move.spotKey, "ccSpot")
    T.eq(partOf(auras, "Buffs").move.spotKey, "buffSpot")

    local fr = sample(ns, "friendly")
    T.isnil(partOf(fr.Parts(), "Name").move, "just the name: centered, it doesn't move")
    DUI:Set("Nameplates", "friendly.enabled", true)
    DUI:Set("Nameplates", "friendly.myBuffs", true)
    stub.RunTimers()
    fr.Refresh(600, 200)
    local fparts = fr.Parts()
    T.eq(partOf(fparts, "Name").move.spotKey, "friendly.namePos", "the friendly plate's own")
    T.eq(partOf(fparts, "Your buffs").move.spotKey, "friendly.myBuffSpot")

    DUI:Set("Nameplates", "debuffSpot", "below")
    stub.RunTimers()
    local s, h = sample(ns, "auras")
    T.eq(select(3, s.p.sampleAuras.debuffs:GetPoint(1)), "BOTTOM", "the stand-in row follows, under the bar")
    T.truthy(h > 0 and h <= 200)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplate sample: every piece moves and resizes on every page, not just its own", function()
    local DUI, ns = load()
    for _, id in ipairs({ "plates", "target", "bars", "threat", "cast", "auras" }) do
        local parts = sample(ns, id).Parts()
        for label, key in pairs({ ["Your debuffs"] = "debuffSpot", ["Crowd control"] = "ccSpot", Buffs = "buffSpot",
                                  ["Quest mark"] = "questPos", ["Raid marker"] = "markerPos", Name = "namePos" }) do
            local part = partOf(parts, label)
            T.truthy(part and part.move, id .. ": " .. label .. " moves")
            T.eq(part.move.spotKey, key, id .. ": " .. label)
        end
        T.eq(partOf(parts, "Your debuffs").size.keys.s, "debuffSize", id .. ": and resizes")
    end
    local fparts = sample(ns, "friendly").Parts()
    DUI:Set("Nameplates", "friendly.enabled", true)
    stub.RunTimers()
    fparts = sample(ns, "friendly").Parts()
    T.eq(partOf(fparts, "Name").move.spotKey, "friendly.namePos", "a friendly plate writes its own")
end)

T.test("nameplate sample: the skull, bar texts, guild line, cast bar and combo points all move", function()
    local DUI, ns = load("ROGUE")
    DUI:Set("Nameplates", "castIcon", true)
    DUI:Set("Nameplates", "level", true)
    DUI:Set("Nameplates", "percent", true)
    stub.RunTimers()
    for _, id in ipairs({ "plates", "target", "bars", "threat", "cast", "auras" }) do
        local parts = sample(ns, id).Parts()
        for label, key in pairs({ ["DoT skull"] = "dotSkullPos", ["Health text"] = "percentPos", Level = "levelPos",
                                  ["Guild name"] = "namePos", ["Spell icon"] = "castIconPos" }) do
            local part = partOf(parts, label)
            if label ~= "Guild name" or part then    -- no guild on this sample, so nothing shows to grab
                T.truthy(part and part.move, id .. ": " .. label .. " moves")
                T.eq(part.move.spotKey, key, id .. ": " .. label)
            end
        end
        local cast = partOf(parts, "Cast bar")
        T.truthy(cast and cast.move, id .. ": the cast bar moves")
        T.isnil(cast.move.spotKey, id .. ": by nudges from its one home")
        T.eq(cast.move.xKey, "castX", id); T.eq(cast.move.yKey, "castY", id)
        T.eq(#cast.move.dots, 1, id)
    end
    local parts = sample(ns, "bars").Parts()
    T.eq(#partOf(parts, "DoT skull").move.dots, 17, "the skull: any spot, on the bar too")
    T.eq(#partOf(parts, "Spell icon").move.dots, 2, "the icon: either end of the cast bar")
    T.eq(#partOf(parts, "Health text").move.dots, 17)
    T.eq(#partOf(parts, "Level").move.dots, 17)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplate sample: combo points drag between over and under the bar", function()
    local DUI, ns = load("ROGUE")
    local parts = sample(ns, "bars").Parts()
    local combo = partOf(parts, "Combo points")
    T.truthy(combo and combo.move, "combo points move")
    T.eq(combo.move.spotKey, "comboPosition")
    T.isnil(combo.move.xKey, "no nudges: the row is laid across the bar")
    T.eq(#combo.move.dots, 2)
    local above
    for _, d in ipairs(combo.move.dots) do if d.spot == "above" then above = d end end
    T.eq((combo.move.drop(above.x, above.y)), "above")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: every piece sits where it always did until moved", function()
    local DUI, ns = load()
    DUI:Set("Nameplates", "level", true)
    DUI:Set("Nameplates", "percent", true)
    DUI:Set("Nameplates", "castIcon", true)
    stub.RunTimers()
    local p = sample(ns, "bars").p
    local hp, T_ = p.hp, p.body and p.body.T or 0
    local point, rel, relPoint, x, y = p.dotSkull:GetPoint(1)
    T.eq(point, "LEFT"); T.eq(rel, hp); T.eq(relPoint, "RIGHT"); T.eq(x, 3); T.eq(y, 0, "the skull")
    -- Measured as laid out. The preview's fit changes the scale afterwards,
    -- so only its size is checked here.
    point, rel, relPoint, x, y = p.percent:GetPoint(1)
    T.eq(point, "RIGHT"); T.eq(rel, hp); T.eq(relPoint, "RIGHT")
    T.eq(x, -(T_ + (p.hpCut or 0) * 0.5 + 2), "health text x")
    T.truthy(y > 0 and y <= 1, "health text a pixel up")
    local up = y
    point, rel, relPoint, x, y = p.level:GetPoint(1)
    T.eq(point, "LEFT"); T.eq(rel, hp); T.eq(relPoint, "LEFT"); T.eq(x, T_ + 3); T.eq(y, up, "the level, level with it")
    point, rel, relPoint, x = p.cast.iconBox:GetPoint(1)
    T.eq(point, "TOPRIGHT"); T.eq(rel, p.cast); T.eq(relPoint, "TOPLEFT"); T.eq(x, -ns.Cast.ICON_GAP, "the spell icon")
    point, rel, relPoint, x, y = p.cast:GetPoint(1)
    T.eq(rel, hp); T.eq(x, 0); T.eq(y, -(hp:GetHeight() + ns.Cast.GAP), "the cast bar")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: a moved piece goes where its settings say", function()
    local DUI, ns = load()
    DUI:Set("Nameplates", "level", true)
    DUI:Set("Nameplates", "percent", true)
    DUI:Set("Nameplates", "castIcon", true)
    DUI:Set("Nameplates", "dotSkullPos", "above")
    DUI:Set("Nameplates", "dotSkullX", 5)
    DUI:Set("Nameplates", "percentPos", "center")
    DUI:Set("Nameplates", "levelPos", "outright")
    DUI:Set("Nameplates", "castX", 12)
    DUI:Set("Nameplates", "castY", 7)
    DUI:Set("Nameplates", "castIconPos", "outright")
    stub.RunTimers()
    local s = sample(ns, "bars")
    local p, hp = s.p, s.p.hp
    local point, rel, relPoint, x, y = p.dotSkull:GetPoint(1)
    T.eq(point, "BOTTOM"); T.eq(rel, hp); T.eq(relPoint, "TOP"); T.eq(x, 5, "the skull's nudge")
    T.truthy(y > 0, "over the bar, past the name")
    point, rel, relPoint = p.percent:GetPoint(1)
    T.eq(point, "CENTER"); T.eq(relPoint, "CENTER", "the health text on the bar's middle")
    point, rel, relPoint = p.level:GetPoint(1)
    T.eq(point, "LEFT"); T.eq(relPoint, "RIGHT", "the level past the bar's end")
    point, rel, relPoint, x, y = p.cast:GetPoint(1)
    T.eq(x, 12); T.eq(y, -(hp:GetHeight() + ns.Cast.GAP) + 7, "the cast bar nudged")
    point, rel, relPoint, x = p.cast.iconBox:GetPoint(1)
    T.eq(point, "TOPLEFT"); T.eq(rel, p.cast); T.eq(relPoint, "TOPRIGHT"); T.eq(x, ns.Cast.ICON_GAP, "the icon's other end")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: the skull never shoves a row, and a row never shoves it", function()
    local DUI, ns = load()
    DUI:Set("Nameplates", "cc", true)
    stub.RunTimers()
    local p = sample(ns, "auras").p
    local _, rel, _, x = p.dotSkull:GetPoint(1)
    T.eq(rel, p.hp); T.eq(x, 3, "crowd control on its spot too: the skull stays by the bar")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplate sample: the fit makes room for a moved skull and cast bar", function()
    local DUI, ns = load()
    local p = sample(ns, "bars").p
    T.truthy((p.spotReach.right or 0) >= 3 + p.dotSkull:GetWidth(), "by default, past the bar's end")
    DUI:Set("Nameplates", "dotSkullPos", "outleft")
    stub.RunTimers()
    p = sample(ns, "bars").p
    T.truthy((p.spotReach.left or 0) >= 3 + p.dotSkull:GetWidth(), "moved left: on the left")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Presses on hotspot b, moves the cursor to the owner's px x, y, lets go.
local function drag(P, b, x, y)
    local owner = b.part.move.owner
    owner.GetLeft = function() return 300 end
    owner.GetTop = function() return 500 end
    local function at(px, py)
        local sc = owner:GetEffectiveScale()
        stub.cursorPos = { (300 + px) * sc, (500 - py) * sc }
    end
    at(1, 1)
    b:GetScript("OnMouseDown")(b, "LeftButton")
    at(x, y)
    stub.RunOnUpdate(P.Strip(), 0.016)
    local during = P.Strip().DotsShown()
    b:GetScript("OnMouseUp")(b, "LeftButton")
    return during
end

T.test("nameplate sample: in the options window, the DoT skull drags to a dot and the cast bar drags freely", function()
    local DUI = load()
    local P = DUI.OptionsPanel
    P.Show("Nameplates.plates")
    P.SetDesign(true)
    local function hot(label)
        for _, h in ipairs(P.Strip().Hotspots()) do
            if h:IsShown() and h.part.label == label then return h end
        end
    end
    local b = hot("DoT skull")
    T.truthy(b, "the skull has a hotspot on General")
    local above
    for _, d in ipairs(b.part.move.dots) do if d.spot == "above" then above = d end end
    drag(P, b, above.x + 1, above.y)
    T.eq(DUI:Get("Nameplates", "dotSkullPos"), "above", "the drag saved")

    b = hot("Cast bar")
    T.truthy(b, "the cast bar has a hotspot on General")
    local home = b.part.move.dots[1]
    drag(P, b, home.x + 40, home.y - 30)
    T.truthy(DUI:Get("Nameplates", "castX") ~= 0 or DUI:Get("Nameplates", "castY") ~= 0, "a nudge saved")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplate sample: in the options window, a drag on the General page moves your debuffs under the bar", function()
    local DUI = load()
    local P = DUI.OptionsPanel
    P.Show("Nameplates.plates")
    P.SetDesign(true)
    local b
    for _, h in ipairs(P.Strip().Hotspots()) do
        if h:IsShown() and h.part.label == "Your debuffs" then b = h end
    end
    T.truthy(b, "your debuffs have a hotspot on General")
    local below
    for _, d in ipairs(b.part.move.dots) do if d.spot == "below" then below = d end end
    T.eq(drag(P, b, below.x + 1, below.y), 8, "the spots round the bar showed")
    T.eq(DUI:Get("Nameplates", "debuffSpot"), "below")
    T.eq(DUI:Get("Nameplates", "debuffX"), 0)
    T.eq(DUI:Get("Nameplates", "debuffY"), 0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplate sample: an Execute range chip at the top right shows the enemy that low, off at first", function()
    local DUI = load()
    local ns = stub.nameplates
    local P = DUI.OptionsPanel
    P.Show("Nameplates.bars")
    local strip = P.Strip()
    local function chip()
        for _, c in ipairs(strip.ViewChips()) do if c:IsShown() and c.viewKey == "execute" then return c end end
    end
    T.falsy(chip(), "execute range off (the default): no chip")
    DUI:Set("Nameplates", "execute", "on")
    stub.RunTimers()
    P.Refresh()
    local c = chip()
    T.truthy(c, "the chip shows")
    T.eq(c.text:GetText(), "Execute range")
    local p = strip.Sample().p
    T.eq(p.health:GetValue(), ns.Sample.ENEMY.health, "off at first: the enemy at its health")
    c:GetScript("OnClick")(c)
    stub.RunOnUpdate(DUI.Motion.Driver and DUI.Motion.Driver() or strip, 1)
    T.truthy(p.health:GetValue() <= DUI:Get("Nameplates", "executePct") * 100, "in the execute range")
    T.truthy(chip().viewOn, "the chip filled")
    P.Show("Nameplates.cast")
    T.truthy(chip() and chip().viewOn, "one for every page")
    chip():GetScript("OnClick")(chip())
    stub.RunOnUpdate(DUI.Motion.Driver and DUI.Motion.Driver() or strip, 1)
    T.eq(strip.Sample().p.health:GetValue(), ns.Sample.ENEMY.health, "back to its health")
    P.Show("Nameplates.friendly")
    T.falsy(chip(), "not on a friendly plate")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplate sample: the Zoom is one for every page", function()
    local _, ns = load()
    local a, b = sample(ns, "plates"), sample(ns, "cast")
    a.SetZoom(2)
    T.eq(b.Zoom(), 2)
    a.SetZoom(9)
    T.eq(a.Zoom(), ns.Sample.ZOOM_MAX)
    a.SetZoom(1)
end)

T.test("nameplate sample: in the options window, with a Design switch, in combat too", function()
    local DUI = load()
    local P = DUI.OptionsPanel
    P.Show("Nameplates.plates")
    local strip = P.Strip()
    T.truthy(strip:IsShown(), "the strip shows")
    T.truthy(strip.Sample().p, "the plate's sample")
    T.truthy(strip.Movable(), "pieces resize: the Design switch shows")
    stub.EnterCombat()
    DUI:Set("Nameplates", "height", 22)
    T.near(strip.Sample().p.hp:GetHeight(), 22 * DUI:Get("Nameplates", "target.height"), 1, "redrawn in combat")
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The same display name the game's own cast bar shows.
T.test("a plate's cast shows the spell's display name, not its raw name", function()
    local _, ns = load()
    local s = sample(ns, "cast")
    local p = s.p
    p.unit, p.friendly = "nameplate1", false
    stub.units.nameplate1 = { cast = { name = "Open", duration = stub.Duration(1) } }
    local casting = _G.UnitCastingInfo
    _G.UnitCastingInfo = function() return "Open", "打开", 1, 0, 0, false, 1, false, 1 end
    ns.Cast.Update(p)
    _G.UnitCastingInfo = casting
    T.eq(p.cast.text.__text, "打开")
end)

T.test("nameplate sample: the Health & Names page's chips show the enemy with a guild or a job", function()
    local DUI, ns = load()
    local s = sample(ns, "bars")
    T.falsy(s.p.sub:IsShown(), "the plain enemy has neither")
    s.SetView("guild", true)
    s.Refresh(600, 200)
    T.eq(s.p.sub.__text, "<Sons of Honor>")
    DUI:Set("Nameplates", "guildColor", "white")
    DUI:Set("Nameplates", "guildSize", 15)
    s.Refresh(600, 200)
    local v = DUI.Style.INK.VALUE
    T.rgb(s.p.sub.__textColor, { v[1], v[2], v[3] }, "its picked color")
    T.eq(s.p.sub.__font[2], 15, "its picked size")
    s.SetView("job", true)
    s.Refresh(600, 200)
    T.eq(s.p.sub.__text, "Quartermaster")
    s.SetView("job", false)
    s.Refresh(600, 200)
    T.falsy(s.p.sub:IsShown(), "off again")
    local plain = select(1, sample(ns, "cast"))
    ns.Sample.enemyLine = "guild"
    plain.Refresh(600, 200)
    T.falsy(plain.p.sub:IsShown(), "only on its own page")
    ns.Sample.enemyLine = nil
end)

T.test("nameplate sample: a boss, rare or caster chip while its color is on", function()
    local DUI, ns = load()
    local s = sample(ns, "bars")
    local function has(key)
        for _, v in ipairs(s.Views()) do if v.key == key then return true end end
        return false
    end
    T.falsy(has("rare"), "no chip while it's off")
    DUI:Set("Nameplates", "healthColor", "class")
    DUI:Set("Nameplates", "rareBar", true)
    DUI:Set("Nameplates", "rareColor", { 0, 0, 1 })
    T.truthy(has("rare"), "a chip once on")
    T.falsy(has("boss"), "only the ones on")
    s.SetView("rare", true)
    s.Refresh(600, 200)
    T.rgb(s.p.health.__barColor, { DUI.Style.Soften(0, 0, 1) }, "the rare's color")
    T.rgb(s.p.dragon.__vertex, ns.Plate.DRAGON_COLORS.silver, "and its silver dragon")
    DUI:Set("Nameplates", "rareBar", false)
    s.Refresh(600, 200)
    T.rgb(s.p.health.__barColor, { DUI.Style.ReactionColor(2) }, "switched off: back to normal")
    s.SetView("rare", false)
end)

T.test("nameplate sample: the Friendly page's chips show a player's guild or an NPC's job", function()
    local DUI, ns = load()
    local s = sample(ns, "friendly")
    local views = s.Views()
    T.eq(#views, 2, "a chip each")
    T.eq(s.p.sub.__text, "<Bridge Four>", "a player first")
    s.SetView("npc", true)
    s.Refresh(600, 200)
    T.eq(s.p.sub.__text, "Innkeeper", "the NPC's job")
    DUI:Set("Nameplates", "friendly.roleColor", "custom")
    DUI:Set("Nameplates", "friendly.roleCustom", { 0.1, 0.2, 0.3 })
    DUI:Set("Nameplates", "friendly.roleSize", 15)
    s.Refresh(600, 200)
    T.rgb(s.p.sub.__textColor, { 0.1, 0.2, 0.3 }, "its picked color")
    T.eq(s.p.sub.__font[2], 15, "its picked size")
    s.SetView("player", true)
    s.Refresh(600, 200)
    T.eq(s.p.sub.__text, "<Bridge Four>", "back to the player")
end)
