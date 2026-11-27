local stub = require("stub")

-- The missing buffs row's look (DaylightUI_Buffs/ReminderRow.lua): every CORE and
-- DISPLAY option of EllesmereUI's buff reminders, drawn with Daylight UI's pieces.

local RW = require("reminderworld")
local login, settle = RW.Login, RW.Settle

local PARTY = {
    player = { name = "Me", class = "WARRIOR" },
    party1 = { name = "Pri", class = "PRIEST" },
}

local function set(key, v) DaylightUI:Set("Buffs", "settings.reminder." .. key, v); stub.RunTimers() end

local function list()
    return {
        { key = "a", kind = "give", section = "raid", have = 3, total = 5, spell = 1459, unit = "party1", short = "Intellect" },
        { key = "b", kind = "get", section = "raid", short = "Fortitude" },
        { key = "c", kind = "item", section = "items", item = 20750, count = 4, macro = "/use [nocombat] item:20750", short = "Oil" },
    }
end

-- The row shows these entries, and a setting's refresh keeps showing them.
local function row(BL, entries)
    local R = BL.ReminderRow
    local set = R.Set
    local shown = entries or list()
    BL.Reminder.Collect = function() return shown end
    R.Set = function(l, sample) if l ~= shown and not sample then shown = l end return set(l, sample) end
    stub.onReset = stub.onReset or {}
    stub.onReset[#stub.onReset + 1] = function() R.Set = set end
    R.Set(shown)
    settle()
    return R
end

T.test("buffs reminder look: core: each of his CORE rows exists with his default and acts", function()
    local BL = login(PARTY)
    local d = BL.DEFAULTS.settings.reminder
    T.eq(d.enabled, true); T.eq(d.cursor, false); T.eq(d.cursorCombat, false)
    T.eq(d.tooltips, true); T.eq(d.picker, false)
    T.eq(d.size, 40); T.eq(d.shape, "none"); T.eq(d.zoom, 7); T.eq(d.crop, 10)
    T.eq(d.grow, "CENTER"); T.eq(d.strata, "MEDIUM"); T.eq(d.gap, 14)
    T.eq(d.border, "daylight"); T.eq(d.borderPx, 3); T.eq(d.borderBehind, false)
    T.eq(d.names, true); T.eq(d.nameSize, 12); T.eq(d.nameAnchor, "BOTTOM"); T.eq(d.nameX, 0); T.eq(d.nameY, -5)
    T.eq(d.count, true); T.eq(d.countSize, 16)
    T.eq(d.glow, "none"); T.eq(d.glowColor, "accent"); T.eq(d.opacity, 1)
end)

T.test("buffs reminder look: display: size 120 makes 120 px icons; 20 the smallest", function()
    local BL = login(PARTY)
    set("size", 120)
    local R = row(BL)
    T.eq(R.active[1]:GetWidth(), 120)
    T.eq(R.active[1]:GetHeight(), 120)
    set("size", 20)
    T.eq(R.active[1]:GetWidth(), 20)
end)

T.test("buffs reminder look: display: zoom sets the icon's inset; cropped trims top and bottom", function()
    local BL = login(PARTY)
    set("zoom", 10)
    local R = row(BL)
    local l, r, t, b = R.active[1].icon:GetTexCoord()
    T.near(l, 0.1, 0.001); T.near(r, 0.9, 0.001); T.near(t, 0.1, 0.001); T.near(b, 0.9, 0.001)
    set("shape", "cropped")
    set("crop", 20)
    T.eq(R.active[1]:GetWidth(), 40)
    T.eq(R.active[1]:GetHeight(), 24, "20% off the top and the bottom")
    l, r, t, b = R.active[1].icon:GetTexCoord()
    T.near(l, 0.1, 0.001)
    T.truthy(t > 0.1 and b < 0.9, "the art cut to fit")
end)

T.test("buffs reminder look: display: grow LEFT keeps the right edge; RIGHT the left edge", function()
    local BL = login(PARTY)
    set("grow", "LEFT")
    local R = row(BL)
    local _, _, _, x3 = R.active[3]:GetPoint(1)
    R.Set({ list()[1] }); settle()
    local _, _, _, x1 = R.active[1]:GetPoint(1)
    T.eq(x1, x3, "the last icon stays where it was")
    set("grow", "RIGHT")
    R.Set(list()); settle()
    local _, _, _, a = R.active[1]:GetPoint(1)
    R.Set({ list()[2] }); settle()
    local _, _, _, b = R.active[1]:GetPoint(1)
    T.eq(a, b, "the first icon stays where it was")
end)

T.test("buffs reminder look: display: strata goes to the row, its icons and their buttons", function()
    local BL = login(PARTY)
    set("strata", "HIGH")
    local R = row(BL)
    T.eq(R.holder:GetFrameStrata(), "HIGH")
    T.eq(R.active[1]:GetFrameStrata(), "HIGH")
    local b = R.buttons[1]
    T.truthy(b and b:IsShown())
    T.eq(b:GetFrameStrata(), "HIGH")
end)

T.test("buffs reminder look: display: spacing", function()
    local BL = login(PARTY)
    set("gap", 0)
    local R = row(BL)
    local _, _, _, a = R.active[1]:GetPoint(1)
    local _, _, _, b = R.active[2]:GetPoint(1)
    T.eq(b - a, 40)
end)

T.test("buffs reminder look: display: shape circle masks the icon once", function()
    local BL = login(PARTY)
    set("shape", "circle")
    local R = row(BL)
    local t = R.active[1]
    local masks = t.icon.__masks or {}
    local n = 0
    for _ in pairs(masks) do n = n + 1 end
    T.eq(n, 1, "one mask")
    T.truthy(t.shapeOuter and t.shapeOuter:IsShown(), "its outline")
    set("shape", "diamond")
    n = 0
    for _ in pairs(t.icon.__masks or {}) do n = n + 1 end
    T.eq(n, 1, "still one after a change")
    set("shape", "none")
    n = 0
    for _ in pairs(t.icon.__masks or {}) do n = n + 1 end
    T.eq(n, 0, "square again")
end)

T.test("buffs reminder look: display: border none has no edge; size, color, shift and behind", function()
    local BL = login(PARTY)
    local R = row(BL)
    local t = R.active[1]
    T.truthy(t.icon:GetWidth() < 40, "the daylight border around the icon")
    set("border", "none")
    T.eq(t.icon:GetWidth(), 40, "no edge: the icon fills it")
    T.truthy(t.shell.opts.noBorder)
    set("border", "flat")
    T.truthy(t.shell.opts.flat)
    set("borderPx", 6)
    T.eq(t.shell.opts.borderPx, 6)
    set("borderColor", { 1, 0, 0 })
    T.rgb(t.shell.opts.borderColor, { 1, 0, 0 })
    set("borderShiftX", 4); set("borderShiftY", -2)
    local _, _, _, x, y = t.edge:GetPoint(1)
    T.eq(x, 4); T.eq(y, -2)
    set("borderBehind", true)
    T.truthy(t.edge:GetFrameLevel() < t.art:GetFrameLevel(), "behind the icon")
    set("borderBehind", false)
    T.truthy(t.edge:GetFrameLevel() > t.art:GetFrameLevel(), "in front of it")
end)

T.test("buffs reminder look: display: name anchor TOP puts it above; font, size, offsets, color", function()
    local BL = login(PARTY)
    local R = row(BL)
    local t = R.active[1]
    local p, rel, rp, x, y = t.name:GetPoint(1)
    T.eq(p, "TOP"); T.eq(rel, t); T.eq(rp, "BOTTOM"); T.eq(x, 0); T.eq(y, -5)
    set("nameAnchor", "TOP")
    p, rel, rp = t.name:GetPoint(1)
    T.eq(p, "BOTTOM"); T.eq(rp, "TOP")
    set("nameX", 3); set("nameY", 7)
    local _, _, _, nx, ny = t.name:GetPoint(1)
    T.eq(nx, 3); T.eq(ny, 7)
    set("nameColor", { 0, 1, 0 })
    T.rgb({ t.name:GetTextColor() }, { 0, 1, 0 })
    set("nameSize", 20)
    local _, size = t.name:GetFont()
    T.eq(size, 20 * (DaylightUI.DB.General().fontScale or 1))
    set("nameFont", "lato")
    local file = t.name:GetFont()
    T.eq(file, DaylightUI.Style.FontFileOf("lato"))
    set("names", false)
    T.falsy(t.name:IsShown())
end)

T.test("buffs reminder look: display: item count shows the bag count, 0 red when out", function()
    local BL = login(PARTY)
    local R = row(BL)
    local oil = R.active[3]
    T.truthy(oil.count:IsShown()); T.eq(oil.count:GetText(), "4")
    T.rgb({ oil.count:GetTextColor() }, DaylightUI.Style.INK.VALUE, "white")
    local e = list()[3]
    e.count = 0; e.macro = nil
    R.Set({ list()[1], list()[2], e }); settle()
    T.eq(oil.count:GetText(), "0")
    T.rgb({ oil.count:GetTextColor() }, DaylightUI.Style.INK.BAD, "red when out")
    T.truthy(oil.icon:IsDesaturated(), "the icon grayed")
    e = list()[3]; e.substitute = true
    R.Set({ list()[1], list()[2], e }); settle()
    T.rgb({ oil.count:GetTextColor() }, DaylightUI.Style.INK.MONEY, "gold for a stand-in")
    set("count", false)
    T.falsy(oil.count:IsShown())
    T.truthy(R.active[1].count:IsShown(), "the raid coverage stays whatever the setting")
    set("countSize", 20); set("countX", -3); set("countY", 2)
    local _, _, _, cx, cy = R.active[1].count:GetPoint(1)
    T.eq(cx, -3); T.eq(cy, 2)
end)

T.test("buffs reminder look: display: glow comet loops while shown and stops when gone", function()
    local BL = login(PARTY)
    local R = row(BL)
    local t = R.active[1]
    T.falsy(t.glowDriver and t.glowDriver:IsShown() and t.glowStyle ~= "breathe" and t.glowLoop, "none: no looping glow")
    set("glow", "comet")
    T.truthy(t.glowDriver and t.glowDriver:IsShown(), "a glow")
    T.eq(t.glowStyle, "comet")
    stub.RunTimers(); settle()
    T.truthy(t.glowDriver:IsShown(), "still looping after the appear breaths")
    T.truthy(R.active[2].glowDriver and R.active[2].glowDriver:IsShown(), "display-only icons glow too")
    set("glowColor", "custom")
    set("glowCustom", { 0, 0, 1 })
    T.rgb(t.glowColors[1], { 0, 0, 1 })
    R.Set({}); settle()
    T.falsy(t.glowDriver:IsShown(), "gone: stopped")
end)

T.test("buffs reminder look: display: opacity 0.5", function()
    local BL = login(PARTY)
    set("opacity", 0.5)
    local R = row(BL)
    T.near(R.holder:GetAlpha(), 0.5, 0.001)
end)

T.test("buffs reminder look: core: tooltips off shows none", function()
    local BL = login(PARTY)
    local R = row(BL)
    local shown = 0
    local show = GameTooltip.Show
    GameTooltip.Show = function(...) shown = shown + 1; return show(...) end
    R.active[2]:GetScript("OnEnter")(R.active[2])
    T.eq(shown, 1, "on: a tooltip")
    set("tooltips", false)
    R.active[2]:GetScript("OnEnter")(R.active[2])
    T.eq(shown, 1, "off: none")
    GameTooltip.Show = show
end)

T.test("buffs reminder look: core: a tooltip is the game's spell or item one, with Daylight UI's lines under it", function()
    local BL = login(PARTY)
    local R = row(BL)
    local spell, item
    GameTooltip.SetSpellByID = function(_, id) spell = id end
    GameTooltip.SetItemByID = function(_, id) item = id end
    local text = {}
    GameTooltip.AddLine = function(_, t) text[#text + 1] = t end
    R.active[1]:GetScript("OnEnter")(R.active[1])
    T.eq(spell, 1459)
    T.truthy(table.concat(text, "\n"):find("Missing on 2 of 5", 1, true))
    local e = list()[3]; e.count = 0; e.macro = nil; e.tipItem = 20750
    R.Set({ e }); settle()
    text = {}
    R.active[1]:GetScript("OnEnter")(R.active[1])
    T.eq(item, 20750)
    T.truthy(table.concat(text, "\n"):find("You don't have this item in your bags", 1, true))
    GameTooltip.SetSpellByID, GameTooltip.SetItemByID = nil, nil
end)

T.test("buffs reminder look: core: cursor attach puts the raid buff at the cursor + 60, plain and unclickable; only in a fight moves it back out of combat", function()
    local BL = login(PARTY)
    set("cursor", true)
    local R = row(BL)
    T.eq(#R.active, 2, "the row keeps the others")
    T.eq(#R.cursorActive, 1, "Intellect rides the cursor")
    local c = R.cursorActive[1]
    T.eq(c:GetFrameStrata(), "TOOLTIP")
    T.falsy(c:IsMouseEnabled(), "can't be clicked")
    for _, b in ipairs(R.buttons) do
        if b:IsShown() then T.truthy(b.entry.key ~= "a", "no button for the one on the cursor") end
    end
    _G.GetCursorPosition = function() return 500, 300 end
    stub.RunOnUpdate(R.cursor, 1)
    local _, _, _, x, y = R.cursor:GetPoint(1)
    local s = R.cursor:GetEffectiveScale()
    T.near(x, 500 / s, 0.01); T.near(y, 300 / s + 60, 0.01)
    R.Set({}); settle()
    T.falsy(R.cursor:IsShown(), "nothing to show: it stops following")
    set("cursorCombat", true)
    R.Set(list()); settle()
    T.eq(#R.cursorActive, 0, "out of combat: back in the row")
    T.eq(#R.active, 3)
    stub.EnterCombat()
    R.Set(list()); settle()
    T.eq(#R.cursorActive, 1, "in a fight: at the cursor")
    stub.LeaveCombat()
end)
