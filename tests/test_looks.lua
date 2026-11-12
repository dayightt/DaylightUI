local stub = require("stub")

T.test("a look sets its settings and puts every other aura and name setting back", function()
    local DUI, ns = stub.Load({ module = true })
    DUI:Set("UnitFrames", "raid.auras.debuffs.size", 30)
    T.truthy(ns.Looks.Apply("battleground", "raid"))
    T.eq(DUI:Get("UnitFrames", "raid.namePos"), "outright")
    T.eq(DUI:Get("UnitFrames", "raid.auras.debuffs.show"), false)
    T.eq(DUI:Get("UnitFrames", "raid.auras.cc.size"), 20)
    T.eq(DUI:Get("UnitFrames", "raid.perLine"), 20)
    T.eq(DUI:Get("UnitFrames", "raid.auras.debuffs.size"), 12, "back to the default")
    T.eq(ns.Looks.Current("raid"), "battleground")
    DUI:Set("UnitFrames", "raid.auras.cc.size", 22)
    T.eq(ns.Looks.Current("raid"), "custom")
    ns.Looks.Apply("daylight", "raid")
    T.eq(DUI:Get("UnitFrames", "raid.namePos"), "bar")
    T.eq(DUI:Get("UnitFrames", "raid.auras.cc.size"), 16)
    T.eq(DUI:Get("UnitFrames", "raid.perLine"), 20, "only the looks that name it set it")
    T.eq(ns.Looks.Current("raid"), "custom", "but 20 per line isn't the DaylightUI look")
    DUI:Set("UnitFrames", "raid.perLine", 5)
    T.eq(ns.Looks.Current("raid"), "daylight")
    T.falsy(ns.Looks.Apply("nope", "raid"))
end)

T.test("every look only names settings the raid frames have", function()
    local DUI, ns = stub.Load({ module = true })
    for _, look in ipairs(ns.Looks.ORDER) do
        for key in pairs(ns.Looks.VALUES[look]) do
            T.truthy(DUI:Get("UnitFrames", "raid." .. key) ~= nil, look .. ": " .. key)
        end
    end
end)

T.test("a look reaches the real tiles at once, with one relayout", function()
    local DUI, ns = stub.Load({ module = true })
    local b = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton1", ns.Raid.header)
    b:SetAttribute("unit", "raid3")
    ns.Raid.header.initialConfigFunction(ns.Raid.header, b:GetName())
    stub.RunTimers()
    T.eq(b.auraSet.debuffs.__groups.notcc.max, 2)
    local layouts, real = 0, ns.Raid.Layout
    ns.Raid.Layout = function(...) layouts = layouts + 1; return real(...) end
    ns.Looks.Apply("minimal", "raid")
    stub.RunTimers()
    ns.Raid.Layout = real
    T.eq(b.auraSet.debuffs.__groups.notcc.max, 0, "debuffs off on the tile")
    T.isnil(b.auraSet.debuffs.__groups.all, "never shown: never added")
    T.eq(layouts, 1, "one refresh, not one per setting")
    T.eq(#stub.errors, 0)
end)

T.test("the Raid page starts with the quick looks", function()
    local DUI, ns = stub.Load({ module = true })
    local page = DUI.Options.GetPage("UnitFrames.raid")
    local first = page.groups[1]
    T.eq(first.label, "Quick looks")
    T.eq(#first.items, #ns.Looks.ORDER)
    T.eq(#DUI.Options.ValidatePage(page), 0)
end)
