-- Enemy flag carriers (DaylightUI_UnitFrames/Arena.lua): Daylight UI frames for the
-- battleground's arena units, with the game's arena frame hidden.
local stub = require("stub")

local function login(before)
    return stub.Load({ module = true, before = before })
end

T.test("a frame per carrier, watched, under one mover, right-click sets focus", function()
    local _, ns = login()
    T.eq(#ns.Arena.buttons, ns.Arena.MAX)
    for i, b in ipairs(ns.Arena.buttons) do
        T.eq(b:GetAttribute("unit"), "arena" .. i)
        T.eq(b:GetAttribute("*type2"), "focus")
        T.truthy(b.__unitWatch, "shows while its carrier exists")
        T.eq(b:GetParent(), ns.Arena.holder)
    end
    T.truthy(DaylightUI.Movers.Get("unitframes.arena"))
end)

T.test("a carrier seen draws their name; the game's arena frame is parked", function()
    local _, ns = login()
    _G.CompactArenaFrame = CreateFrame("Frame", "CompactArenaFrame", UIParent)
    stub.units.arena1 = { name = "Dalinar", class = "WARRIOR", isPlayer = true, enemy = true, reaction = 2,
                          health = 40, maxHealth = 100 }
    stub.FireEvent("ARENA_OPPONENT_UPDATE", "arena1", "seen")
    local b = ns.Arena.buttons[1]
    T.eq(b.nameText.__text, "Dalinar")
    T.falsy(CompactArenaFrame:IsShown(), "the game's own is hidden")
    T.eq(CompactArenaFrame:GetParent(), ns.Blizzard.hiddenParent)
end)

T.test("test mode shows two sample carriers, then hands them back", function()
    local DUI, ns = login()
    T.truthy(DUI.SetTestMode(true))
    local a, b = ns.Arena.buttons[1], ns.Arena.buttons[2]
    T.truthy(a:IsShown())
    T.eq(a.nameText.__text, "Dalinar")
    T.eq(b.nameText.__text, "Vivenna")
    T.falsy(a.__unitWatch, "watch off while previewing")
    DUI.SetTestMode(false)
    T.isnil(a.test)
    T.truthy(a.__unitWatch)
end)

T.test("switched off: no frames, the game's arena frame left alone", function()
    local _, ns = login(function() end)
    ns.module.db.arena.enabled = false
    ns.Refresh(ns.module, "arena.enabled")
    _G.CompactArenaFrame = CreateFrame("Frame", "CompactArenaFrame2", UIParent)
    stub.FireEvent("ARENA_OPPONENT_UPDATE", "arena1", "seen")
    T.falsy(ns.Arena.buttons[1]:IsShown())
    T.falsy(ns.Arena.buttons[1].__unitWatch)
    T.eq(CompactArenaFrame:GetParent(), UIParent)
end)
