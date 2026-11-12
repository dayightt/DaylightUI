local stub = require("stub")

local function login(before)
    return stub.Load({ module = true, before = before })
end

T.test("preview shows every frame with sample units and both casts", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Daylight", isPlayer = true, class = "PALADIN", health = 50, maxHealth = 50 }
    end)
    T.truthy(DUI.SetTestMode(true))
    local target, focus, tot = ns.frames.target, ns.frames.focus, ns.frames.targettarget
    for _, unit in ipairs(ns.Test.UNITS) do
        local f = ns.frames[unit]
        T.truthy(f:IsShown(), unit)
        T.falsy(f.__unitWatch, unit .. " watch off while previewing")
    end
    T.eq(target.nameText.__text, "Sadeas")
    T.eq(target.percentText.__text, "62")
    T.truthy(target.portrait.elite:IsShown(), "elite sample shows the dragon")
    T.eq(target.marker.__cell, 8, "skull")
    T.eq(focus.nameText.__text, "Navani")
    T.eq(tot.nameText.__text, "Daylight", "the target's target is you")
    T.truthy(ns.playerCastbar:IsShown())
    T.eq(ns.playerCastbar.text.__text, "Holy Light")
    T.truthy(ns.targetCastbar:IsShown())
end)

T.test("sample frames ignore real unit events and don't fade", function()
    local DUI, ns = login()
    DUI.SetTestMode(true)
    local pet = ns.frames.pet
    stub.units.pet = { name = "Real Pet", health = 1, maxHealth = 100, friend = true, inRange = false }
    stub.FireEvent("UNIT_HEALTH", "pet")
    T.eq(pet.nameText.__text, "Syl")
    T.eq(pet:GetAlpha(), 1)
end)

T.test("turning it off hands the frames back to their units", function()
    local DUI, ns = login()
    DUI.SetTestMode(true)
    DUI.SetTestMode(false)
    T.truthy(ns.frames.target.__unitWatch)
    T.isnil(ns.frames.target.test)
    T.falsy(ns.playerCastbar:IsShown())
end)

T.test("changing a setting mid-preview keeps the sample frames", function()
    local DUI, ns = login()
    DUI.SetTestMode(true)
    ns.Refresh(ns.module)
    for _, unit in ipairs(ns.Test.UNITS) do
        local f = ns.frames[unit]
        T.truthy(f:IsShown(), unit)
        T.falsy(f.__unitWatch, unit .. " watch stays off")
    end
    T.eq(ns.frames.target.nameText.__text, "Sadeas")
    ns.module.db.target.enabled = false
    ns.Refresh(ns.module)
    T.falsy(ns.frames.target:IsShown(), "a frame turned off leaves the preview")
    T.isnil(ns.frames.target.test)
    DUI.SetTestMode(false)
    T.falsy(ns.frames.target.__unitWatch)
end)

T.test("combat ends the preview; the frames wait until it's over", function()
    local DUI, ns = login()
    DUI.SetTestMode(true)
    stub.combat = true
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    T.falsy(DUI.testMode)
    T.eq(ns.frames.target:GetAlpha(), 0, "no target: hidden by alpha until the watch comes back")
    T.falsy(ns.frames.target.__unitWatch)
    stub.combat = false
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    T.truthy(ns.frames.target.__unitWatch)
    T.eq(ns.frames.target:GetAlpha(), 1)
end)

T.test("it can't start in combat", function()
    local DUI = login()
    stub.combat = true
    T.falsy(DUI.SetTestMode(true))
    T.falsy(DUI.testMode)
    T.truthy(stub.ChatContains("Can't preview"))
end)

T.test("disabled frames stay out of the preview", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "focus.enabled", false)
    DUI.SetTestMode(true)
    T.falsy(ns.frames.focus.test)
end)

T.test("the preview gives the target sample debuffs and buffs, in their look", function()
    local DUI, ns = login()
    DUI.SetTestMode(true)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local set = ns.auras
    local dh, bh = ns.Auras.HolderFor(set.debuffs), ns.Auras.HolderFor(set.buffs)
    local shown = function(h)
        local n = 0
        for _, b in ipairs(h.pool) do if b:IsShown() then n = n + 1 end end
        return h:IsShown() and n or 0
    end
    local cfg = DUI:Get("UnitFrames", "targetAuras")
    T.eq(shown(dh), math.min(#ns.Test.AURAS.debuffs, cfg.maxDebuffs + cfg.maxOtherDebuffs), "debuffs")
    T.eq(shown(bh), math.min(#ns.Test.AURAS.buffs, cfg.maxBuffs), "buffs")
    local d = dh.pool[1]
    T.eq(d:GetWidth(), cfg.debuffSize, "the debuff size")
    T.eq(d.time.__text, "14s", "the compact time")
    local c = ns.Auras.DISPEL_COLORS.Magic
    T.near(d.edge.__vertex[1], DUI.Style.Soften(c[1], c[2], c[3]), 1e-6, "edged by dispel type")
    -- Put where the real debuffs go, by the same points, not on the container.
    local p, q = { dh:GetPoint(1) }, { set.debuffs:GetPoint(1) }
    T.eq(p[2], q[2]); T.eq(p[1], q[1]); T.eq(p[4], q[4])
    T.eq(set.debuffs:GetAlpha(), 0, "the real ones out of the way")
    -- The party's aura groups too, on its samples' stand-ins.
    local p1 = ns.Party.preview[1]
    local row = p1.sampleSet.debuffs
    T.truthy(shown(row) > 0, "party debuffs")
    T.eq(row.pool[1]:GetWidth(), DUI:Get("UnitFrames", "party.auras.debuffs.size"))
    local br = p1.sampleSet.buffs
    T.truthy(shown(br) > 0, "party buffs")
    DUI:Set("UnitFrames", "party.auras.buffs.show", false)
    stub.RunTimers()
    T.eq(shown(br), 0, "none when off")
    DUI:Set("UnitFrames", "party.auras.buffs.show", true)
    stub.RunTimers()
    DUI.SetTestMode(false)
    T.eq(shown(dh), 0, "gone after")
    T.falsy(row:IsShown())
    T.eq(set.debuffs:GetAlpha(), 1)
end)
