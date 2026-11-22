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
    set("target.parts.portrait.order", 30)
    T.eq(f.status:GetFrameLevel(), f.portraitHolder:GetFrameLevel() + 6, "icons follow")
    set("target.parts.icons.order", 10)
    T.eq(f.status:GetFrameLevel(), f:GetFrameLevel() + 10, "their own order")
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
    T.eq(ns.Layers.TopOf(rows), rows:GetFrameLevel(), "the container's own level")
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
