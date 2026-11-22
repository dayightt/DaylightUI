local stub = require("stub")

-- Layers: each part's draw order (its level over its frame) and, standing on
-- its own, its layer. Untouched parts keep the level their own code gives them.

local function login()
    local DUI, ns = stub.Load({ module = true, before = function()
        stub.units.player = { name = "Daylight", isPlayer = true, class = "WARRIOR", health = 50, maxHealth = 50 }
    end })
    stub.RunTimers()
    return DUI, ns
end

local function set(key, v)
    DaylightUI:Set("UnitFrames", key, v)
    stub.RunTimers()
end

local function freeTarget()
    local DUI, ns = login()
    set("target.powerAt", "free")
    set("target.portraitAt", "free")
    return DUI, ns, ns.frames.target
end

T.test("layers: untouched parts keep their levels, and the order shows them", function()
    local _, ns, f = freeTarget()
    local L, base = ns.Layers, f:GetFrameLevel()
    T.eq(f.freePower:GetFrameLevel(), base + ns.UF.PIECE_LIFT, "power where it always was")
    T.eq(f.portraitHolder:GetFrameLevel(), base + ns.UF.PIECE_LIFT + ns.UF.PORTRAIT_LIFT)
    T.eq(L.OrderOf("target", "power"), ns.UF.PIECE_LIFT)
    T.eq(L.OrderOf("target", "portrait"), ns.UF.PIECE_LIFT + ns.UF.PORTRAIT_LIFT)
    T.isnil(L.Saved("target", "power"))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("layers: a higher order draws a part over another, and clearing it puts it back", function()
    local _, ns, f = freeTarget()
    local base, was = f:GetFrameLevel(), f.freePower:GetFrameLevel()
    set("target.parts.power.order", 25)
    T.eq(f.freePower:GetFrameLevel(), base + 25)
    T.truthy(f.freePower:GetFrameLevel() > f.portraitHolder:GetFrameLevel(), "power over the portrait")
    set("target.parts.power.order", nil)
    T.eq(f.freePower:GetFrameLevel(), was, "back where its own code had it")
end)

T.test("layers: the portrait icons ride over a moved portrait unless given their own order", function()
    local _, ns, f = freeTarget()
    local gap = f.status:GetFrameLevel() - f.portraitHolder:GetFrameLevel()
    set("target.parts.portrait.order", 30)
    T.eq(f.status:GetFrameLevel() - f.portraitHolder:GetFrameLevel(), gap, "icons follow")
    set("target.parts.level.order", 10)
    local badge = f.status.icons.level
    T.truthy(badge:GetParent() ~= f.status, "the level badge has a frame of its own")
    T.eq(badge:GetParent():GetFrameLevel(), f:GetFrameLevel() + 10, "its own order")
    T.eq(f.status.levelText:GetParent(), badge:GetParent(), "its number goes with it")
end)

T.test("layers: a raid marker gets a frame of its own, and reset puts it back", function()
    local _, ns, f = freeTarget()
    local home = f.marker:GetParent()
    set("target.parts.marker.order", 33)
    local c = f.marker:GetParent()
    T.truthy(c ~= home)
    T.eq(c:GetFrameLevel(), f:GetFrameLevel() + 33)
    ns.Layers.Reset("target", "marker")
    stub.RunTimers()
    T.eq(f.marker:GetParent(), home, "back in its own frame")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("layers: buffs and debuffs are layered on their own", function()
    local _, ns, f = freeTarget()
    set("target.parts.debuffs.order", 30)
    set("target.parts.buffs.order", 8)
    T.eq(ns.auras.debuffs:GetFrameLevel(), f:GetFrameLevel() + 30)
    T.eq(ns.auras.buffs:GetFrameLevel(), f:GetFrameLevel() + 8)
end)

T.test("layers: the options preview draws the same order", function()
    local DUI, ns = freeTarget()
    set("target.parts.portrait.order", 2)
    set("target.parts.health.order", 9)
    local s = ns.PageSample.New("target", UIParent)
    s.Refresh(400, 200)
    local f = s.f
    T.truthy(f.health:GetFrameLevel() > ns.Layers.TopOf(f.portrait), "the preview stacks the bar over the portrait")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("layers: a part on its own takes a layer, Same as frame follows the frame", function()
    local _, ns, f = freeTarget()
    set("target.parts.power.layer", "HIGH")
    T.eq(f.freePower:GetFrameStrata(), "HIGH")
    set("target.parts.power.layer", nil)
    T.eq(f.freePower:GetFrameStrata(), f:GetFrameStrata(), "with the frame again")
end)

T.test("layers: Bring forward and Send back step past what a part overlaps", function()
    local _, ns, f = freeTarget()
    local L = ns.Layers
    local order = L.Step("target", "power", { f.portraitHolder }, true)
    T.truthy(order, "forward")
    set("target.parts.power.order", order)
    T.truthy(f.freePower:GetFrameLevel() > L.TopOf(f.portraitHolder), "over the portrait and its ring")
    local back = L.Step("target", "power", { f.portraitHolder }, false)
    T.truthy(back, "back")
    set("target.parts.power.order", back)
    T.truthy(L.TopOf(f.freePower) < f.portraitHolder:GetFrameLevel(), "under it again")
    local none, why = L.Step("target", "power", {}, true)
    T.isnil(none)
    T.eq(why, "top")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("layers: stepping past aura rows doesn't look inside the game's containers", function()
    local _, ns, f = freeTarget()
    local rows = ns.auras.debuffs
    local btn = CreateFrame("Button", nil, rows)
    btn:SetFrameLevel(rows:GetFrameLevel() + 40)
    btn.__shown = stub.Secret(true)
    T.eq(ns.Layers.TopOf(rows), rows:GetFrameLevel() + 2, "its buttons counted, not looked into")
    ns.Layers.Step("target", "power", { rows, f.portraitHolder }, true)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("layers: each covered frame's page has a Layers card that validates", function()
    local DUI = login()
    for _, id in ipairs({ "player", "target", "focus", "pet" }) do
        local page = DUI.Options.GetPage("UnitFrames." .. id)
        local found
        for _, g in ipairs(page.groups) do
            if g.label == "Layers" then found = g end
            for _, sub in ipairs(g.groups or {}) do if sub.label == "Layers" then found = sub end end
        end
        T.truthy(found, id .. " has Layers")
        T.eq(#DUI.Options.ValidatePage(page), 0, id)
    end
end)

T.test("layers: Reset layers puts every part back", function()
    local _, ns, f = freeTarget()
    local was = f.freePower:GetFrameLevel()
    T.truthy(ns.Layers.Untouched("target"))
    set("target.parts.power.order", 25)
    set("target.parts.power.layer", "HIGH")
    T.falsy(ns.Layers.Untouched("target"))
    ns.Layers.Reset("target")
    stub.RunTimers()
    T.eq(f.freePower:GetFrameLevel(), was)
    T.eq(f.freePower:GetFrameStrata(), f:GetFrameStrata())
    T.truthy(ns.Layers.Untouched("target"))
end)

T.test("layers: the target page has a Layers tab", function()
    local DUI = login()
    local P = DUI.OptionsPanel
    P.Show("UnitFrames.target")
    local tabs = P.PageFrame().tabs
    T.eq(tabs[#tabs], "Layers")
    P.Show("UnitFrames.party")
    tabs = P.PageFrame().tabs
    T.truthy(tabs[#tabs] ~= "Layers", "not on party")
end)

T.test("layers: a level change leaves the game's aura buttons alone", function()
    local _, ns, f = freeTarget()
    local rows = ns.auras.buffs
    local btn = CreateFrame("Button", nil, rows)
    local edge = CreateFrame("Frame", nil, btn)
    btn:SetFrameLevel(rows:GetFrameLevel() + 1)
    edge:SetFrameLevel(btn:GetFrameLevel() + 3)
    set("target.parts.buffs.order", 60)
    T.eq(rows:GetFrameLevel(), f:GetFrameLevel() + 60)
    T.isnil(btn.levelOffset, "nothing noted inside the container")
    T.isnil(edge.levelOffset)
end)

T.test("layers: an extra text's rows show only while it's added", function()
    local DUI = login()
    local page = DUI.Options.GetPage("UnitFrames.target")
    local row
    for _, g in ipairs(page.groups) do
        for _, it in ipairs(g.items or {}) do if it.key == "target.parts.text1.order" then row = it end end
    end
    T.truthy(row and row.hidden, "has a hidden check")
    local get = function(k) return DUI:Get("UnitFrames", k) end
    T.truthy(row.hidden(get), "hidden while unused")
    set("target.texts.t1.show", true)
    T.falsy(row.hidden(get), "shown once added")
end)

T.test("layers: the frame's border moves with its health bar", function()
    local DUI, ns, f = freeTarget()
    local shell = DUI.Style.GetShell(f)
    local gap = shell:GetFrameLevel() - f.health:GetFrameLevel()
    set("target.parts.health.order", 40)
    T.eq(shell:GetFrameLevel(), f.health:GetFrameLevel() + gap, "same gap under the bar")
    set("target.parts.health.order", nil)
    T.eq(shell:GetFrameLevel() - f.health:GetFrameLevel(), gap, "back")
end)

T.test("layers: the preview's stand-in aura rows take their order", function()
    local DUI, ns = freeTarget()
    set("target.parts.buffs.order", 50)
    local s = ns.PageSample.New("target", UIParent)
    s.Refresh(400, 200)
    local h = ns.Auras.HolderFor(s.f.sampleAuras.buffs)
    T.truthy(h, "a holder")
    T.eq(h:GetFrameLevel(), s.f:GetFrameLevel() + 50)
end)

T.test("layers: a portrait under the bar takes its ring and icons under too", function()
    local DUI, ns = login()
    local f = ns.frames.target
    set("target.parts.portrait.order", 13)
    set("target.parts.health.order", 17)
    local top = ns.Layers.TopOf(f.portrait)
    for _, g in ipairs({ f.socket, f.status, f.dotSkull }) do
        if g then top = math.max(top, ns.Layers.TopOf(g)) end
    end
    T.truthy(ns.Layers.LowOf(f.health) > top, "the whole portrait under the whole bar")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("layers: two parts on the same order never interleave", function()
    local _, ns, f = freeTarget()
    set("target.parts.marker.order", 20)
    set("target.parts.buffs.order", 20)
    local marker = f.marker:GetParent()
    T.truthy(ns.auras.buffs:GetFrameLevel() > ns.Layers.TopOf(marker), "the buffs, borders and all, over the marker")
end)
