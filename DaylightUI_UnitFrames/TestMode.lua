-- Test mode for the solo frames: target, focus, pet and target of target get
-- sample units, both cast bars run mid-cast, and the target shows combo points,
-- buffs and debuffs, so every frame can be styled and moved without a real
-- target. Party and raid have their own samples (Party.lua, Raid.lua). The core
-- owns the switch (DaylightUI.SetTestMode) and this file listens for it.
--
-- Showing a unit frame without its unit is protected, so the preview only
-- starts out of combat. Combat ends it right away: the samples go invisible
-- through alpha (allowed in combat) and the frames return to their units once
-- combat is over.

local _, ns = ...
local DUI = DaylightUI
local UF, CB = ns.UF, ns.CastBar

local Test = {}
ns.Test = Test

Test.UNITS = { "target", "focus", "pet", "targettarget", "focustarget" }

Test.SAMPLES = {
    target = { name = "Sadeas", reaction = 2, health = 62, healthValue = 3120, power = 45, powerValue = 1800, powerToken = "MANA",
               classification = "elite", marker = 8, portraitClass = "WARRIOR", threat = "aggro", threatPct = 100, level = 27,
               dots = 24, dotSkull = true },
    focus = { name = "Navani", class = "PRIEST", health = 70, healthValue = 1840, power = 70, powerValue = 1680, powerToken = "MANA",
              marker = 4, portraitClass = "PRIEST", heals = 12, absorbs = 8, level = 25, leader = true },
    pet = { name = "Syl", reaction = 5, health = 91, healthValue = 880, portraitClass = "HUNTER" },
    targettarget = { class = "self", health = 100, healthValue = 4100 },
    focustarget = { name = "Sadeas", reaction = 2, health = 62, healthValue = 3120 },
}

Test.CASTS = {
    player = { text = DUI.L["Holy Light"], value = 0.6, icon = "Interface\\Icons\\Spell_Holy_HolyBolt" },
    target = { text = DUI.L["Shadow Bolt"], value = 0.35, kick = 0.8 },
}

Test.COMBO = 3

-- The target's sample auras: your debuffs first, then others', edged by
-- dispel type, plus a few buffs above the name.
local I = "Interface\\Icons\\"
Test.AURAS = {
    debuffs = {
        { icon = I .. "Spell_Shadow_ShadowWordPain", time = "14s", dispel = "Magic" },
        { icon = I .. "Spell_Shadow_CurseOfSargeras", time = "22s", dispel = "Curse", cure = true },
        { icon = I .. "Ability_Gouge", time = "9s", count = 3, dispel = "Bleed" },
        { icon = I .. "Spell_Nature_CorrosiveBreath", time = "1m", dispel = "Poison" },
        { icon = I .. "Spell_Shadow_AbominationExplosion", time = "3m", dispel = "Disease" },
    },
    buffs = {
        { icon = I .. "Spell_Holy_WordFortitude", time = "29m" },
        { icon = I .. "Spell_Nature_Regeneration", time = "13m" },
        { icon = I .. "Spell_Holy_MagicalSentry", time = "44m" },
        { icon = I .. "Ability_Warrior_BattleShout", time = "2m" },
        { icon = I .. "Spell_Holy_PowerWordShield", time = "19s", purge = "Magic" },
    },
}

-- A unit's sample, also used by the options pages' live samples. The target
-- of target is always you.
function Test.SampleFor(unit)
    local s = Test.SAMPLES[unit]
    if s.class == "self" then return UF.You(unit, s, "WARRIOR") end
    return s
end

local function db() return ns.module and ns.module.db end

function Test.Start()
    if Test.active then return true end
    if InCombatLockdown() then return false end
    Test.active = true
    local cfg = db()
    for _, spec in ipairs(ns.SPECS) do
        local unit = spec.unit
        local f = ns.frames[unit]
        local on = false
        for _, u in ipairs(Test.UNITS) do if u == unit then on = true end end
        if on and f and cfg and ns.ConfigFor(cfg, spec).enabled and DUI.TestPartShown(unit) then
            f.test = Test.SampleFor(unit)
            ns.Release(f)
            f:Show()
            f:SetAlpha(1)
            UF.ShowSample(f)
        end
    end
    local casts = DUI.TestPartShown("castbars")
    if casts and cfg and cfg.playerCastbar.enabled then CB.ShowSample(ns.playerCastbar, Test.CASTS.player) end
    if cfg and cfg.swing.enabled and DUI.TestPartShown("swing") then ns.Swing.ShowSample(ns.swing) end
    if DUI.TestPartShown("personal") then ns.Personal.ShowSample() end
    ns.Arena.ShowSamples()
    if casts and cfg and cfg.targetCastbar.enabled and ns.frames.target.test then
        CB.ShowSample(CB.At("target", cfg.targetCastbar) ~= "power" and ns.targetCastbarFree or ns.targetCastbar, Test.CASTS.target)
    end
    if casts and cfg and cfg.focusCastbar.enabled and ns.frames.focus.test then
        CB.ShowSample(CB.At("focus", cfg.focusCastbar) ~= "power" and ns.focusCastbarFree or ns.focusCastbar, Test.CASTS.target)
    end
    if ns.combo and DUI.TestPartShown("combo") then ns.Combo.ShowSample(ns.combo, Test.COMBO) end
    if DUI.TestPartShown("pet") then ns.Happiness.ShowSample(ns.happiness) end
    if ns.auras and cfg and ns.frames.target.test then
        ns.Auras.ShowSample(ns.auras, ns.frames.target, cfg.targetAuras, Test.AURAS)
    end
    -- The player frame's own rows, only once switched on.
    if ns.playerAuras and cfg then
        ns.Auras.ShowSample(ns.playerAuras, ns.frames.player, cfg.playerAuras, Test.AURAS)
    end
    return true
end

-- A settings change hands every frame back to its unit, so put the samples
-- back (frames turned off stay off). Protected, out of combat only.
function Test.Reapply()
    if not Test.active then return end
    for _, unit in ipairs(Test.UNITS) do
        local f = ns.frames[unit]
        if f then f.test = nil end
    end
    for _, b in ipairs(ns.Arena.buttons) do b.test = nil end
    Test.active = false
    Test.Start()
end

-- Back to the real units. In combat the unit watch can't be restored yet, so
-- the samples stay hidden through alpha until it can.
function Test.Stop()
    if not Test.active then return end
    Test.active = false
    for _, unit in ipairs(Test.UNITS) do
        local f = ns.frames[unit]
        if f and f.test then
            f.test = nil
            if not UnitExists(unit) then f:SetAlpha(0) end
            UF.UpdateAll(f, true)
        end
    end
    ns.Arena.HideSamples()
    CB.HideSample(ns.playerCastbar)
    ns.Swing.HideSample(ns.swing)
    ns.Personal.HideSample()
    CB.HideSample(ns.targetCastbar)
    CB.HideSample(ns.targetCastbarFree)
    CB.HideSample(ns.focusCastbar)
    CB.HideSample(ns.focusCastbarFree)
    if ns.combo then ns.Combo.HideSample(ns.combo) end
    ns.Happiness.HideSample(ns.happiness)
    if ns.auras then ns.Auras.HideSample(ns.auras) end
    if ns.playerAuras then ns.Auras.HideSample(ns.playerAuras) end
    DUI.AfterCombat(function()
        local cfg = db()
        for _, spec in ipairs(ns.SPECS) do
            local f = ns.frames[spec.unit]
            if f and f.spec.unit ~= "player" and cfg then
                f:SetAlpha(1)
                ns.SetEnabled(f, ns.ConfigFor(cfg, spec).enabled)
                UF.UpdateAll(f, true)
            end
        end
        ns.Arena.Rewatch()
    end, "unitframes:test")
end

DUI.On("TestModeChanged", function(on)
    if on then
        if not Test.Start() then DUI.SetTestMode(false) end
    else
        Test.Stop()
    end
end)

-- The parts the test box can hide (the player frame is real, not a sample).
local function frameOn(unit)
    return function()
        local cfg = db()
        if not cfg then return false end
        for _, spec in ipairs(ns.SPECS) do
            if spec.unit == unit then return ns.ConfigFor(cfg, spec).enabled == true end
        end
        return false
    end
end
DUI.RegisterTestPart("target", "Target", 10, frameOn("target"))
DUI.RegisterTestPart("focus", "Focus", 20, frameOn("focus"))
DUI.RegisterTestPart("pet", "Pet", 30, frameOn("pet"))
DUI.RegisterTestPart("targettarget", "Target of target", 40, frameOn("targettarget"))
DUI.RegisterTestPart("focustarget", "Focus target", 45, frameOn("focustarget"))
DUI.RegisterTestPart("castbars", "Cast bars", 50, function()
    local cfg = db()
    return cfg ~= nil and (cfg.playerCastbar.enabled or cfg.targetCastbar.enabled or cfg.focusCastbar.enabled
        or cfg.partyCastbar.enabled) == true
end)

-- A box was ticked or unticked, so redo the samples.
local PARTS = { target = true, focus = true, pet = true, targettarget = true, focustarget = true, castbars = true, personal = true, arena = true }
DUI.On("TestPartChanged", function(key)
    if not (PARTS[key] and Test.active) or InCombatLockdown() then return end
    Test.Stop()
    Test.Start()
end)
