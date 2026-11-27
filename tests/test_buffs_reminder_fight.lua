local stub = require("stub")

-- Missing buffs in a fight (DaylightUI_Buffs/Reminder.lua, ReminderRow.lua), as
-- EllesmereUI does it: raid buffs are still read when the client says every
-- rank is plain, your own raid buff's button stays clickable, the rest fade
-- where they stand, and nothing moves under a secure button.

local RW = require("reminderworld")
local login, settle = RW.Login, RW.Settle

-- A priest giving Fortitude, a mage and a paladin here (Intellect, Wisdom from
-- others), Inner Fire missing, Camp Benefits switched on and missing.
local function world()
    local BL = login({
        player = { name = "Me", class = "PRIEST" },
        party1 = { name = "Mag", class = "MAGE" },
        party2 = { name = "Pal", class = "PALADIN" },
    }, { known = { 1243, 588 }, bags = true })
    DaylightUI:Set("Buffs", "settings.reminder.items.camp", true)
    BL.Reminder.Refresh()
    settle()
    return BL
end

local function tileOf(BL, key)
    for _, t in ipairs(BL.ReminderRow.active) do if t.key == key and t:IsShown() then return t end end
end

local function buttonOf(BL, key)
    for _, b in ipairs(BL.ReminderRow.buttons) do
        if b:IsShown() and b.entry and b.entry.key == key then return b end
    end
end

local function point(f)
    local p, rel, rp, x, y = f:GetPoint(1)
    return table.concat({ tostring(p), tostring(rel), tostring(rp), tostring(x), tostring(y) }, " ")
end

local function fortitude(units)
    for _, u in ipairs(units) do
        stub.SetAuras(u, "HELPFUL", { { name = "Power Word: Fortitude", spellId = 1243 } })
    end
end

-- Every Fortitude rank never secret, as the client may say for a raid buff.
local function plainFortitude(BL)
    for _, id in ipairs(BL.ReminderData.byKey.fortitude.ids) do stub.neverSecretAuras[id] = true end
end

T.test("buffs reminder fight: the pull: raid tiles go to 0.5, the rest fade out, the spots don't move", function()
    local BL = world()
    local keys = {}
    for _, t in ipairs(BL.ReminderRow.active) do keys[#keys + 1] = t.key end
    T.deq(keys, { "fortitude", "intellect", "wisdom", "innerfire", "camp" })
    local spots = {}
    for _, t in ipairs(BL.ReminderRow.active) do spots[t.key] = point(t) end
    stub.EnterCombat()
    stub.RunTimers(); settle()
    for _, key in ipairs({ "fortitude", "intellect", "wisdom" }) do
        local t = tileOf(BL, key)
        T.truthy(t, key .. " held (can't be read in the fight)")
        T.near(t:GetAlpha(), 0.5, 0.01, key .. " dims")
        T.eq(point(t), spots[key], key .. " holds its spot")
    end
    T.falsy(tileOf(BL, "innerfire"), "your own buff fades away")
    T.falsy(tileOf(BL, "camp"), "the camp fades away")
    stub.LeaveCombat()
end)

T.test("buffs reminder fight: the pull: your Fortitude button keeps its spell and spot; Inner Fire's goes see-through", function()
    local BL = world()
    local fort, inner = buttonOf(BL, "fortitude"), buttonOf(BL, "innerfire")
    local spot = point(fort)
    stub.secure = true
    stub.EnterCombat()
    settle()
    T.eq(fort:GetAttribute("type1"), "spell")
    T.eq(fort:GetAttribute("spell1"), 1243)
    T.truthy(fort:IsShown()); T.eq(fort:GetAlpha(), 1, "still there to click")
    T.eq(point(fort), spot)
    T.truthy(inner:GetAttribute("macrotext1"):find("[nocombat", 1, true))
    T.eq(inner:GetAlpha(), 0, "see-through, since it can't hide in a fight")
    stub.LeaveCombat()
    stub.secure = false
end)

T.test("buffs reminder fight: an unreadable raid buff isn't read in a fight; the row holds; one refresh after", function()
    local BL = world()
    local reads = 0
    local U = C_UnitAuras
    local get = U.GetAuraDataBySpellName
    U.GetAuraDataBySpellName = function(...) reads = reads + 1; return get(...) end
    stub.secure = true
    stub.EnterCombat()
    stub.units.party3 = { name = "Dru", class = "DRUID", isPlayer = true }
    T.noerror(function()
        stub.FireEvent("GROUP_ROSTER_UPDATE")
        stub.FireEvent("UNIT_AURA", "player")
        stub.FireEvent("UNIT_AURA", "party1")
        stub.RunTimers()
    end, "no protected call")
    T.eq(reads, 0, "secret in the fight: nothing read")
    T.truthy(tileOf(BL, "fortitude"), "held")
    stub.LeaveCombat()
    stub.secure = false
    stub.RunTimers()
    T.truthy(reads > 0)
    T.truthy(tileOf(BL, "wild"), "the druid's Mark shows now")
    U.GetAuraDataBySpellName = get
end)

-- Worst case 1: Fortitude missing on one at the pull, the button bound to it.
-- A dead priest's Fortitude comes back missing on two after a combat res.
T.test("buffs reminder fight: a combat res mid-fight: Fortitude missing on two shows in the fight, the provider button casts it", function()
    local units = {
        player = { name = "Me", class = "PRIEST" },
        party1 = { name = "War", class = "WARRIOR" },
        party2 = { name = "Rog", class = "ROGUE" },
    }
    local BL = login(units, { known = { 1243 } })
    plainFortitude(BL)
    fortitude({ "player", "party1" })
    BL.Reminder.Refresh(); settle()
    local t = tileOf(BL, "fortitude")
    T.eq(t.count:GetText(), "2/3")
    local b = buttonOf(BL, "fortitude")
    stub.secure = true
    stub.EnterCombat()
    -- party1 died and was brought back: no Fortitude.
    stub.SetAuras("party1", "HELPFUL", {})
    stub.FireEvent("UNIT_AURA", "party1")
    stub.RunTimers(); settle()
    t = tileOf(BL, "fortitude")
    T.truthy(t, "shown in the fight")
    T.eq(t.count:GetText(), "1/3", "read again in the fight")
    T.eq(b:GetAlpha(), 1)
    T.eq(b:GetAttribute("spell1"), 1243, "the button still casts it")
    local cast = {}
    stub.CastSpell = function(id) cast[#cast + 1] = id end
    stub.SecureClick(b, "LeftButton", false)
    stub.CastSpell = nil
    T.deq(cast, { 1243 })
    stub.LeaveCombat(); stub.secure = false
end)

T.test("buffs reminder fight: all buffed at the pull, missing after: a plain icon that says it can't be clicked", function()
    local units = {
        player = { name = "Me", class = "PRIEST" },
        party1 = { name = "War", class = "WARRIOR" },
    }
    local BL = login(units, { known = { 1243 } })
    plainFortitude(BL)
    fortitude({ "player", "party1" })
    BL.Reminder.Refresh(); settle()
    T.falsy(tileOf(BL, "fortitude"))
    stub.secure = true
    stub.EnterCombat()
    stub.SetAuras("party1", "HELPFUL", {})
    stub.FireEvent("UNIT_AURA", "party1")
    stub.RunTimers(); settle()
    local t = tileOf(BL, "fortitude")
    T.truthy(t, "shown in the fight")
    T.falsy(buttonOf(BL, "fortitude"), "no button made in a fight")
    local said = {}
    _G.UIErrorsFrame = CreateFrame("Frame", "UIErrorsFrame", UIParent)
    UIErrorsFrame.AddMessage = function(_, text) said[#said + 1] = text end
    t:GetScript("OnMouseUp")(t, "LeftButton")
    t:GetScript("OnMouseUp")(t, "LeftButton")
    T.deq(said, { "Click-to-use is disabled in combat" }, "said once, not every click")
    stub.LeaveCombat(); stub.secure = false
end)

T.test("buffs reminder fight: in combat unticked: no raid icon in a fight", function()
    local units = { player = { name = "Me", class = "PRIEST" }, party1 = { name = "War", class = "WARRIOR" } }
    local BL = login(units, { known = { 1243 } })
    plainFortitude(BL)
    DaylightUI:Set("Buffs", "settings.reminder.raid.where.in_combat", false)
    BL.Reminder.Refresh(); settle()
    T.truthy(tileOf(BL, "fortitude"), "out of combat: shown")
    stub.EnterCombat()
    stub.FireEvent("UNIT_AURA", "party1")
    stub.RunTimers(); settle()
    T.falsy(tileOf(BL, "fortitude"), "in a fight: gone")
    stub.LeaveCombat()
end)

T.test("buffs reminder fight: a second buff of yours (Fortitude and Spirit) gets its own icon out of combat; in a fight only the bound one", function()
    local units = { player = { name = "Me", class = "PRIEST" }, party1 = { name = "Mag", class = "MAGE" } }
    local BL = login(units, { known = { 1243, 14752 } })
    plainFortitude(BL)
    for _, id in ipairs(BL.ReminderData.byKey.spirit.ids) do stub.neverSecretAuras[id] = true end
    BL.Reminder.Refresh(); settle()
    T.truthy(buttonOf(BL, "fortitude")); T.truthy(buttonOf(BL, "spirit"), "its own icon and cast")
    T.eq(buttonOf(BL, "spirit"):GetAttribute("spell1"), 14752)
    local spirit = buttonOf(BL, "spirit")
    stub.secure = true
    stub.EnterCombat()
    stub.FireEvent("UNIT_AURA", "party1")
    stub.RunTimers(); settle()
    T.truthy(tileOf(BL, "fortitude"), "the bound one")
    T.falsy(tileOf(BL, "spirit"), "not the second")
    T.eq(spirit:GetAlpha(), 0, "its button see-through")
    stub.LeaveCombat(); stub.secure = false
end)

T.test("buffs reminder fight: after the fight the row re-centers, the faded come back and the glow breathes again", function()
    local BL = world()
    local W = DaylightUI.Widgets
    local glows = {}
    local glow = W.GlowAround
    W.GlowAround = function(host, on, shape) if on then glows[#glows + 1] = host end return glow(host, on, shape) end
    stub.EnterCombat()
    settle()
    -- Inner Fire landed in the fight.
    stub.SetAuras("player", "HELPFUL", { { name = "Inner Fire", spellId = 588 } })
    stub.LeaveCombat()
    stub.RunTimers()
    settle()
    local keys, xs = {}, {}
    for _, t in ipairs(BL.ReminderRow.active) do
        keys[#keys + 1] = t.key
        local _, _, _, x = t:GetPoint(1)
        xs[#xs + 1] = x
        T.eq(t:GetAlpha(), 1, t.key .. " back to full")
    end
    T.deq(keys, { "fortitude", "intellect", "wisdom", "camp" })
    T.deq(xs, { -81, -27, 27, 81 }, "re-centered without Inner Fire")
    T.truthy(tileOf(BL, "camp"), "the camp is back")
    local again = {}
    for _, h in ipairs(glows) do again[h] = true end
    T.truthy(again[tileOf(BL, "fortitude")], "Fortitude breathes again")
    W.GlowAround = glow
end)

T.test("buffs reminder fight: ENCOUNTER_START before the lockdown already dims the row", function()
    local BL = world()
    stub.FireEvent("ENCOUNTER_START", 1, "Boss", 1, 5)
    stub.RunTimers(); settle()
    T.near(tileOf(BL, "fortitude"):GetAlpha(), 0.5, 0.01, "dimmed at the encounter")
    stub.FireEvent("ENCOUNTER_END", 1, "Boss", 1, 5, 1)
    stub.RunTimers(); settle()
    T.eq(tileOf(BL, "fortitude"):GetAlpha(), 1, "the encounter over, out of combat: back")
end)

T.test("buffs reminder fight: the glow breathes three laps, then rests (nothing runs while idle)", function()
    local BL = world()
    BL.ReminderRow.Set({ { key = "x", kind = "self", spell = 588, macro = "/cast [nocombat,@player] Inner Fire", short = "Inner Fire" } })
    local t = tileOf(BL, "x")
    T.truthy(t.glowDriver and t.glowDriver:IsShown(), "breathing as it appears")
    stub.RunTimers()
    settle()
    T.falsy(t.glowDriver:IsShown(), "at rest after its laps")
end)
