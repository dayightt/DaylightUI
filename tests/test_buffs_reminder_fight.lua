local stub = require("stub")

-- Missing buffs in a fight (DaylightUI_Buffs/Reminder.lua, ReminderRow.lua): at
-- the pull nothing moves (a secure button can't), raid buffs dim, the rest fade,
-- your own raid buff stays clickable, and nothing is read until it ends.

local RW = require("reminderworld")
local login, settle = RW.Login, RW.Settle

-- A priest giving Fortitude, a mage and a paladin here (Intellect, Wisdom from
-- others), Inner Fire missing, Wizard Oil carried.
local function world()
    local BL = login({
        player = { name = "Me", class = "PRIEST" },
        party1 = { name = "Mag", class = "MAGE" },
        party2 = { name = "Pal", class = "PALADIN" },
    }, { known = { 1243, 588 }, bags = true })
    stub.equipped[16] = { id = 1000, class = 2, subClass = 10 }
    stub.bagItems[20750] = 3
    BL.Reminder.Refresh()
    settle()
    return BL
end

local function tileOf(BL, key)
    for _, t in ipairs(BL.ReminderRow.active) do if t.key == key then return t end end
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

T.test("buffs reminder fight: the pull: raid tiles go to 0.5, the rest fade out, the spots don't move", function()
    local BL = world()
    local keys = {}
    for _, t in ipairs(BL.ReminderRow.active) do keys[#keys + 1] = t.key end
    T.deq(keys, { "fortitude", "intellect", "wisdom", "innerfire", "weapon:main" })
    local spots = {}
    for _, t in ipairs(BL.ReminderRow.active) do spots[t.key] = point(t) end
    stub.EnterCombat()
    settle()
    for _, key in ipairs({ "fortitude", "intellect", "wisdom" }) do
        local t = tileOf(BL, key)
        T.near(t:GetAlpha(), 0.5, 0.01, key .. " dims")
        T.eq(point(t), spots[key], key .. " holds its spot")
    end
    T.falsy(tileOf(BL, "innerfire"):IsShown(), "your own buff fades away")
    T.falsy(tileOf(BL, "weapon:main"):IsShown(), "the oil fades away")
    stub.LeaveCombat()
end)

T.test("buffs reminder fight: the pull: your Fortitude button keeps its spell and spot; the oil's macro does nothing in a fight", function()
    local BL = world()
    local fort, oil = buttonOf(BL, "fortitude"), buttonOf(BL, "weapon:main")
    local spot = point(fort)
    stub.secure = true
    stub.EnterCombat()
    settle()
    T.eq(fort:GetAttribute("type1"), "spell")
    T.eq(fort:GetAttribute("spell1"), 1243)
    T.truthy(fort:IsShown()); T.eq(fort:GetAlpha(), 1, "still there to click")
    T.eq(point(fort), spot)
    T.truthy(oil:GetAttribute("macrotext1"):find("[nocombat]", 1, true))
    T.eq(oil:GetAlpha(), 0, "see-through, since it can't hide in a fight")
    stub.LeaveCombat()
    stub.secure = false
end)

T.test("buffs reminder fight: nothing is read; UNIT_AURA and GROUP_ROSTER_UPDATE wait", function()
    local BL = world()
    local reads = 0
    local U = C_UnitAuras
    local get = U.GetAuraDataBySpellName
    U.GetAuraDataBySpellName = function(...) reads = reads + 1; return get(...) end
    local sets = 0
    local set = BL.ReminderRow.Set
    BL.ReminderRow.Set = function(...) sets = sets + 1; return set(...) end
    stub.secure = true
    stub.EnterCombat()
    -- The roster changes in the fight: a druid joins.
    stub.units.party3 = { name = "Dru", class = "DRUID", isPlayer = true }
    T.noerror(function()
        stub.FireEvent("GROUP_ROSTER_UPDATE")
        stub.FireEvent("UNIT_AURA", "player")
        stub.FireEvent("UNIT_AURA", "party1")
        stub.RunTimers()
    end, "no protected call")
    T.eq(reads, 0, "nothing read")
    T.eq(sets, 0, "the row holds")
    stub.LeaveCombat()
    stub.secure = false
    stub.RunTimers()
    T.eq(sets, 1, "one refresh after the fight")
    T.truthy(reads > 0)
    T.truthy(tileOf(BL, "wild"), "the druid's Mark shows now")
    U.GetAuraDataBySpellName = get
    BL.ReminderRow.Set = set
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
    T.deq(keys, { "fortitude", "intellect", "wisdom", "weapon:main" })
    T.deq(xs, { -90, -30, 30, 90 }, "re-centered without Inner Fire")
    T.truthy(tileOf(BL, "weapon:main"):IsShown(), "the oil is back")
    local again = {}
    for _, h in ipairs(glows) do again[h] = true end
    T.truthy(again[tileOf(BL, "fortitude")], "Fortitude breathes again")
    W.GlowAround = glow
end)

T.test("buffs reminder fight: ENCOUNTER_START before the lockdown already holds the row", function()
    local BL = world()
    local sets = 0
    local set = BL.ReminderRow.Set
    BL.ReminderRow.Set = function(...) sets = sets + 1; return set(...) end
    stub.FireEvent("ENCOUNTER_START", 1, "Boss", 1, 5)
    settle()
    T.near(tileOf(BL, "fortitude"):GetAlpha(), 0.5, 0.01, "dimmed at the encounter")
    T.isnil(BL.Reminder.Collect(), "nothing read")
    stub.FireEvent("UNIT_AURA", "player"); stub.RunTimers()
    T.eq(sets, 0)
    stub.FireEvent("ENCOUNTER_END", 1, "Boss", 1, 5, 1)
    stub.RunTimers()
    T.eq(sets, 1, "the encounter over, out of combat: looked again")
    BL.ReminderRow.Set = set
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
