local stub = require("stub")

-- Each frame's strata setting: the frame and its pieces move to it, a cast bar
-- or swing timer hung under a frame draws with that frame, and detached ones
-- take their own.

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

T.test("strata: frames start where they always drew", function()
    local _, ns = login()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(ns.frames.player:GetFrameStrata(), "MEDIUM")
    T.eq(ns.frames.target:GetFrameStrata(), "MEDIUM")
    T.eq(ns.Personal.frame:GetFrameStrata(), "LOW", "the personal display stays under the frames")
    T.eq(ns.Party.holder:GetFrameStrata(), "MEDIUM")
end)

T.test("strata: a frame, its free power bar and its group take the pick", function()
    local _, ns = login()
    set("player.strata", "HIGH")
    T.eq(ns.frames.player:GetFrameStrata(), "HIGH")
    T.eq(ns.frames.player.freePower:GetFrameStrata(), "HIGH", "its own power bar comes along")
    T.eq(ns.frames.target:GetFrameStrata(), "MEDIUM", "other frames keep theirs")
    set("party.strata", "LOW")
    T.eq(ns.Party.holder:GetFrameStrata(), "LOW")
    for _, b in ipairs(ns.Party.group.buttons) do T.eq(b:GetFrameStrata(), "LOW", "a party button follows its holder") end
    set("raid.strata", "BACKGROUND")
    T.eq(ns.Raid.holder:GetFrameStrata(), "BACKGROUND")
    set("arena.strata", "DIALOG")
    T.eq(ns.Arena.holder:GetFrameStrata(), "DIALOG")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("strata: a hung cast bar and swing timer draw with the player frame", function()
    local _, ns = login()
    set("playerCastbar.strata", "BACKGROUND")
    set("swing.strata", "BACKGROUND")
    set("player.strata", "HIGH")
    T.eq(ns.playerCastbar:GetFrameStrata(), "HIGH", "hung under the frame, it ignores its own pick")
    T.eq(ns.playerCastbar.clip:GetFrameStrata(), "HIGH", "and its clip tucks it under the frame")
    T.eq(ns.swing:GetFrameStrata(), "HIGH", "the swing timer hangs there too")
end)

T.test("strata: detached, cast bars and the swing timer take their own", function()
    local _, ns = login()
    set("playerCastbar.at", "free")
    set("playerCastbar.strata", "DIALOG")
    T.eq(ns.playerCastbar:GetFrameStrata(), "DIALOG")
    set("targetCastbar.at", "free")
    set("targetCastbar.strata", "LOW")
    T.eq(ns.targetCastbarFree:GetFrameStrata(), "LOW")
    set("swing.attach", false)
    set("swing.strata", "HIGH")
    T.eq(ns.swing:GetFrameStrata(), "HIGH")
    set("swing.bars.main.detach", true)
    T.eq(ns.swing.pods.main:GetFrameStrata(), "HIGH", "a bar on its own too")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("strata: a bad saved value falls back to the default", function()
    local _, ns = login()
    set("target.strata", "NOPE")
    T.eq(ns.frames.target:GetFrameStrata(), "MEDIUM")
end)
