local stub = require("stub")

-- Aura icon borders, set on each frame (iconBorder in its aura settings).

local CFG = { debuffSize = 30, debuffs = true, debuffFilter = "all", maxDebuffs = 8, maxOtherDebuffs = 4,
              buffSize = 18, buffs = true, maxBuffs = 6 }

local function with(look)
    local out = {}
    for k, v in pairs(CFG) do out[k] = v end
    out.iconBorder = look
    return out
end

-- A target row set built with look already on, like a frame whose settings
-- were saved before the login.
local function setup(look, unit)
    local _, ns = stub.Load({ module = true, login = false })
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(220, 48)
    f.spec = { slant = "left" }
    local set = ns.Auras.Create(f, unit == "player" and "right" or "left", unit, with(look))
    return set, ns
end

local BOX = { w = 72, h = 28, padX = 1, padY = 2, bottomInset = 4 }
local WHITE = "Interface\\Buttons\\WHITE8x8"
local function edgeOf(btn)
    for _, r in ipairs(stub.Children(btn)) do
        if rawget(r, "__texture") == WHITE and rawget(r, "__objectType") ~= "Frame" then return r end
    end
end
local function shellOf(btn) return DaylightUI.Style.GetShell(btn) end
local function inset(btn) return rawget(btn, "__icon").__points[1][4] end

local function soft(c) return { DaylightUI.Style.Soften(c[1], c[2], c[3]) } end

T.test("a debuff border by dispel type, wine or plain", function()
    local set, ns = setup({ debuff = "wine" })
    local btn = set.debuffs.__groups.mine.button
    T.isnil(rawget(btn, "__dispels"), "wine: the client doesn't color it")
    T.rgb(edgeOf(btn).__vertex, soft(ns.Auras.DEBUFF_BORDER), "every debuff wine")
    set, ns = setup({ debuff = "plain" })
    btn = set.debuffs.__groups.mine.button
    T.isnil(rawget(btn, "__dispels"))
    T.rgb(edgeOf(btn).__vertex, DaylightUI.Style.BORDER, "plain: the frame's border color")
    set, ns = setup({ debuff = "dispel", noType = "plain" })
    btn = set.debuffs.__groups.mine.button
    local map = btn.__dispel.opts.customDispelColorMap
    T.near(map.None.r, soft(DaylightUI.Style.BORDER)[1], 0.001, "no type: plain")
    T.near(map.Magic.r, soft(ns.Auras.DISPEL_COLORS.Magic)[1], 0.001, "Magic keeps its color")
    set = setup({})
    map = set.debuffs.__groups.mine.button.__dispel.opts.customDispelColorMap
    T.near(map.None.r, soft(ns.Auras.DEBUFF_BORDER)[1], 0.001, "the default: wine without a type")
end)

T.test("a buff border plain, accent, class or custom", function()
    local set = setup({ buff = "custom", color = { 0.1, 0.8, 0.3 } })
    T.rgb(shellOf(set.buffs.__groups.buffs.button).border.TOP.__vertex, { 0.1, 0.8, 0.3 }, "custom")
    set = setup({ buff = "accent" })
    T.rgb(shellOf(set.buffs.__groups.buffs.button).border.TOP.__vertex, { DaylightUI.Style.Accent() }, "accent")
    set = setup({ buff = "class" })
    local _, token = UnitClass("player")
    T.rgb(shellOf(set.buffs.__groups.buffs.button).border.TOP.__vertex, { DaylightUI.Style.ClassColor(token) }, "your class")
    set = setup({ buff = "plain" })
    T.rgb(shellOf(set.buffs.__groups.buffs.button).border.TOP.__vertex, DaylightUI.Style.BORDER, "plain")
end)

T.test("border size 0 to 4", function()
    local set = setup({ px = 0 })
    local d, b = set.debuffs.__groups.mine.button, set.buffs.__groups.buffs.button
    T.eq(inset(d), 0, "the icon fills the button")
    T.falsy(edgeOf(d):IsShown(), "no debuff edge")
    T.eq(shellOf(b).border.TOP.__vertex[4], 0, "no buff border")
    set = setup({ px = 4 })
    d, b = set.debuffs.__groups.mine.button, set.buffs.__groups.buffs.button
    T.eq(inset(d), DaylightUI.Pixel.Px(d, 4), "a thick edge")
    T.eq(inset(b), DaylightUI.Pixel.Px(b, 4))
    set = setup({ px = 9 })
    T.eq(inset(set.debuffs.__groups.mine.button), DaylightUI.Pixel.Px(set.debuffs.__groups.mine.button, 4), "4 at most")
end)

T.test("the glow can go", function()
    local set = setup({ glow = false })
    local cure = set.debuffs.__groups.cure.button
    T.eq(#cure.__dispels, 1, "the dispellable debuff: its edge, no glow")
    T.isnil(rawget(set.buffs.__groups.buffs.button, "__dispels"), "the target's buffs: no purge glow")
    set = setup({})
    T.eq(#set.debuffs.__groups.cure.button.__dispels, 2, "on by default")
end)

T.test("a change in a boss fight waits, then restyles the icons already made", function()
    local set, ns = setup({})
    local btn = set.debuffs.__groups.cure.button
    local buff = set.buffs.__groups.buffs.button
    stub.SetRestriction("Encounter", true)
    T.noerror(function() ns.Auras.Apply(set, with({ debuff = "plain", buff = "custom", color = { 0, 1, 0 }, glow = false, px = 3 })) end)
    T.eq(#btn.__dispels, 2, "locked: untouched")
    stub.SetRestriction("Encounter", false)
    stub.RunTimers()
    T.isnil(rawget(btn, "__dispels"), "plain: handed back to nobody")
    T.rgb(edgeOf(btn).__vertex, DaylightUI.Style.BORDER)
    T.rgb(shellOf(buff).border.TOP.__vertex, { 0, 1, 0 })
    T.eq(inset(btn), DaylightUI.Pixel.Px(btn, 3))
    ns.Auras.Apply(set, with({}))
    stub.RunTimers()
    T.eq(#btn.__dispels, 2, "back to dispel colors and the glow, once each")
    T.truthy(edgeOf(btn):IsShown())
end)

T.test("the target's look never reaches the player's rows", function()
    local _, ns = stub.Load({ module = true, login = false })
    local t, p = CreateFrame("Frame", nil, UIParent), CreateFrame("Frame", nil, UIParent)
    local target = ns.Auras.Create(t, "left", nil, with({}))
    local player = ns.Auras.Create(p, "right", "player", with({}))
    ns.Auras.Apply(target, with({ debuff = "plain" }))
    stub.RunTimers()
    T.isnil(rawget(target.debuffs.__groups.mine.button, "__dispels"), "the target's changed")
    T.truthy(player.debuffs.__groups.all.button.__dispel, "the player's keep their dispel colors")
end)

T.test("party and raid each keep their own", function()
    local DUI, ns = stub.Load({ module = true })
    DUI:Set("UnitFrames", "raid.iconBorder.debuff", "wine")
    stub.RunTimers()
    local a, b = CreateFrame("Frame", nil, UIParent), CreateFrame("Frame", nil, UIParent)
    local party, raid = ns.AuraGroups.Create(a, "party1"), ns.AuraGroups.Create(b, "raid1")
    local cfg = { debuffs = { show = true, which = "all", max = 3, size = 14 } }
    ns.AuraGroups.Place(party, a, cfg, BOX, DUI:Get("UnitFrames", "party.iconBorder"))
    ns.AuraGroups.Place(raid, b, cfg, BOX, DUI:Get("UnitFrames", "raid.iconBorder"))
    T.truthy(party.debuffs.__groups.all.button.__dispel, "party: by dispel type")
    T.isnil(rawget(raid.debuffs.__groups.all.button, "__dispels"), "raid: wine")
end)

T.test("the samples wear the frame's border", function()
    local _, ns = stub.Load({ module = true })
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(220, 48)
    local set = ns.Auras.PlainSet(f, "left")
    local cfg = with({ debuff = "plain", buff = "custom", color = { 0, 0, 1 }, px = 0 })
    ns.Auras.Apply(set, cfg)
    ns.Auras.Place(set, f)
    ns.Auras.ShowSample(set, f, cfg, ns.Test.AURAS)
    local d, b = ns.Auras.HolderFor(set.debuffs).pool[1], ns.Auras.HolderFor(set.buffs).pool[1]
    T.falsy(d.edge:IsShown(), "no edge at 0")
    T.eq(shellOf(b).border.TOP.__vertex[4], 0, "no buff border at 0")
    cfg = with({ debuff = "plain", buff = "custom", color = { 0, 0, 1 }, px = 2 })
    ns.Auras.Apply(set, cfg)
    ns.Auras.ShowSample(set, f, cfg, ns.Test.AURAS)
    T.rgb(d.edge.__vertex, DaylightUI.Style.BORDER, "plain")
    T.rgb(shellOf(b).border.TOP.__vertex, { 0, 0, 1 }, "custom")
end)

T.test("every frame with icons has its own border settings, today's look by default", function()
    stub.Load({ module = true })
    for _, key in ipairs({ "targetAuras", "focusAuras", "playerAuras", "petAuras", "personal.auras", "party", "raid", "raid20", "raid40" }) do
        T.eq(DaylightUI:Get("UnitFrames", key .. ".iconBorder.px"), 2, key)
        T.eq(DaylightUI:Get("UnitFrames", key .. ".iconBorder.debuff"), "dispel", key)
        T.eq(DaylightUI:Get("UnitFrames", key .. ".iconBorder.buff"), "plain", key)
    end
end)

T.test("icons built with no border get it back when a width is picked", function()
    local set, ns = setup({ px = 0 })
    local b = set.buffs.__groups.buffs.button
    T.eq(shellOf(b).border.TOP.__vertex[4], 0, "none at first")
    ns.Auras.Apply(set, with({ px = 2 }))
    stub.RunTimers()
    T.truthy(shellOf(b).border.TOP.__vertex[4] > 0, "the buff's outline shows again")
    T.truthy(edgeOf(set.debuffs.__groups.mine.button):IsShown(), "and the debuff's edge")
end)

T.test("each frame page has its own Icon borders card; the glow only where icons have one", function()
    local DUI = stub.Load({ module = true })
    local want = { ["UnitFrames.player"] = "playerAuras", ["UnitFrames.target"] = "targetAuras", ["UnitFrames.focus"] = "focusAuras",
                   ["UnitFrames.pet"] = "petAuras", ["UnitFrames.personal"] = "personal.auras", ["UnitFrames.party"] = "party",
                   ["UnitFrames.raid"] = "raid", ["UnitFrames.raid20"] = "raid", ["UnitFrames.raid40"] = "raid" }
    local seen = {}
    for id, page in DUI.Options.Pages() do
        for _, g in ipairs(page.groups) do
            if g.label == "Icon borders" then
                local keys = {}
                for _, it in ipairs(g.items) do keys[it.key] = true end
                local base = want[id]
                T.truthy(base, id .. " has the card")
                if base then
                    T.truthy(keys[base .. ".iconBorder.px"] and keys[base .. ".iconBorder.debuff"] and keys[base .. ".iconBorder.buff"]
                             and keys[base .. ".iconBorder.noType"] and keys[base .. ".iconBorder.color"], id .. ": its own keys")
                    local glow = id == "UnitFrames.target" or id == "UnitFrames.focus"
                    T.eq(keys[base .. ".iconBorder.glow"] == true, glow, id .. ": glow row")
                end
                seen[id] = true
            end
        end
    end
    for id in pairs(want) do T.truthy(seen[id], id .. " shows the card") end
end)
