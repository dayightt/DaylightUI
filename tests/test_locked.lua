local stub = require("stub")

-- Locked objects. While auras are secret (in combat, and in a battleground even
-- between fights) the client refuses any addon call on an aura button it made,
-- or on anything added to it. The 0.8.1 dispel tint error ("ClearAllPoints on
-- bad self") reached players this way.

-- Calls obj:method(...) from a chunk named like an addon file, so the client
-- treats it as addon code. Tests and the game's own code may touch locked objects.
local call = assert(loadstring("local obj, m = ...; return obj[m](obj, select(3, ...))", "@DaylightUI_Fake/Probe.lua"))
local function asAddon(obj, method, ...) return call(obj, method, ...) end

-- Where the refused calls came from, one line each, for the failure message.
local function sites()
    local out = {}
    for site, n in pairs(stub.lockSites) do out[#out + 1] = string.format("%4d  %s", n, site) end
    table.sort(out)
    return "\n" .. table.concat(out, "\n")
end

local function container()
    local c = CreateFrame("AuraContainer", nil, UIParent)
    local made
    c:AddAuraGroup("g", "HARMFUL", { initializeFrame = function(btn)
        made = btn:CreateTexture()
        asAddon(made, "SetPoint", "CENTER")   -- allowed: still inside the set-up call
    end })
    return c.__groups.g.button, made
end

T.test("the fake game: an aura button and its parts lock while auras are secret", function()
    stub.Load()
    local btn, tex = container()
    T.noerror(function() asAddon(tex, "ClearAllPoints") end, "open world, out of combat")
    stub.EnterCombat()
    T.errors(function() asAddon(tex, "ClearAllPoints") end, "in combat")
    T.errors(function() asAddon(btn, "SetAlpha", 1) end, "the button too")
    T.noerror(function() tex:ClearAllPoints() end, "tests may still look")
    T.noerror(function() asAddon(tex, "IsForbidden") end, "IsForbidden is always allowed")
    stub.LeaveCombat()
    stub.SetRestriction("PvPMatch", true)
    T.errors(function() asAddon(tex, "ClearAllPoints") end, "a battleground, between fights")
end)

T.test("the fake game: a texture given to AddDispelTypeTexture locks while auras are secret", function()
    stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    local tex = f:CreateTexture()
    f:AddDispelTypeTexture(tex, {})
    T.noerror(function() asAddon(tex, "SetAlpha", 1) end)
    stub.SetRestriction("PvPMatch", true)
    T.errors(function() asAddon(tex, "SetAlpha", 1) end)
    T.noerror(function() asAddon(f, "SetAlpha", 1) end, "our own frame stays ours")
end)

-- A setting change in a battleground: the re-layout never touches a locked part.
T.test("raid tiles in a battleground: a setting change touches no locked part", function()
    local DUI, ns = stub.Load({ module = true })
    local b = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton2b", ns.Raid.header)
    b:SetAttribute("unit", "raid5")
    stub.units.raid5 = { name = "Lirin", isPlayer = true, class = "PRIEST", health = 10, maxHealth = 10 }
    ns.Raid.header.initialConfigFunction(ns.Raid.header, b:GetName())
    DUI:Set("UnitFrames", "raid.dispelHighlight", "both")
    local hl = b.dispel.__groups.dispel.button.highlight
    stub.SetRestriction("PvPMatch", true)
    DUI:Set("UnitFrames", "raid.dispelAlpha", 0.6)
    DUI:Set("general", "cornerPx", 4)
    stub.RunTimers()
    T.eq(stub.lockErrors, 0, sites())
    T.near(hl.tint:GetAlpha(), 0.3, 0.001, "waits for the match to end")
    stub.SetRestriction("PvPMatch", false)
    T.near(hl.tint:GetAlpha(), 0.6, 0.001, "then takes the new look")
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

-- Which textures the client was told to color by dispel type.
local function handed(btn)
    local out = {}
    for _, d in ipairs(btn.__dispels or {}) do out[d.tex] = true end
    return out
end

-- A tile made inside a battleground (you join the match's raid there). Its
-- dispel button is born locked, so it must be fully dressed while the client
-- builds it, not after the match.
T.test("raid tiles made in a battleground: the dispel icon and border are colored", function()
    local DUI, ns = stub.Load({ module = true })
    DUI:Set("UnitFrames", "raid.dispelHighlight", "border")
    stub.RunTimers()
    stub.SetRestriction("PvPMatch", true)
    local b = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton2c", ns.Raid.header)
    b:SetAttribute("unit", "raid6")
    stub.units.raid6 = { name = "Tavi", isPlayer = true, class = "DRUID", health = 10, maxHealth = 10 }
    ns.Raid.header.initialConfigFunction(ns.Raid.header, b:GetName())
    stub.RunTimers()
    T.eq(stub.lockErrors, 0, sites())
    local btn = b.dispel.__groups.dispel.button
    local got = handed(btn)
    T.truthy(got[btn.dispelEdge], "the corner icon's edge takes the debuff's color")
    for i, s in ipairs(btn.highlight.strips) do T.truthy(got[s], "border strip " .. i) end
    for key, t in pairs(btn.highlight.glow) do T.truthy(got[t], "glow piece " .. key .. " (on by default)") end
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("buff bars in a battleground: a setting change touches no locked part", function()
    stub.Load({ buffs = true, before = function()
        _G.GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
        CreateFrame("Frame", "BuffFrame", UIParent)
        CreateFrame("Frame", "DebuffFrame", UIParent)
        stub.units = { player = { name = "Me", class = "PRIEST" } }
    end })
    stub.RunTimers()
    stub.SetRestriction("PvPMatch", true)
    DaylightUI:Set("Buffs", "settings.iconSize", 20)
    DaylightUI:Set("general", "cornerPx", 4)
    stub.RunTimers()
    T.eq(stub.lockErrors, 0, sites())
    local btn = DaylightUIBuffs.__groups.priest.button
    T.truthy(btn:GetWidth() ~= 20, "waits for the match to end")
    stub.SetRestriction("PvPMatch", false)
    stub.RunTimers()
    T.eq(btn:GetWidth(), 20, "then takes the new size")
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("the target's aura text sizes wait for the match to end, then land", function()
    local _, ns = stub.Load({ module = true })
    local DUI = DaylightUI
    local btn = ns.auras.buffs.__groups.buffs.button
    local was = btn.__time.__font[2]
    stub.SetRestriction("PvPMatch", true)
    DUI:Set("UnitFrames", "targetAuras.buffTimeSize", 16)
    stub.RunTimers()
    T.eq(stub.lockErrors, 0, sites())
    T.eq(btn.__time.__font[2], was, "locked in the match")
    stub.SetRestriction("PvPMatch", false)
    T.eq(btn.__time.__font[2], 16, "then takes the new size")
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)
