-- The buff reminder: on a ready check, and when you enter a dungeon or raid
-- in a group, a calm one-line banner lists the group buffs you don't have
-- yet (Fortitude, Mark of the Wild, Arcane Intellect, a blessing...), only
-- the ones someone in your group can give (their class is there). It
-- fades after a few seconds (settings.reminder.seconds), when the buffs
-- land, or when a fight starts. Buffs are matched by spell id (and by the
-- client's own name for those ids, so another rank or locale still counts).
-- Auras are secret in combat and under the client's restrictions (boss
-- fights, keystones, PvP matches): then nothing is read and nothing shows.

local _, BL = ...
local DUI = DaylightUI
local L = DUI.L
local Style, Motion = DUI.Style, DUI.Motion

local Reminder = {}
BL.Reminder = Reminder

Reminder.MOVER = "buffs.reminder"
Reminder.DEFAULT = { "TOP", nil, "TOP", 0, -200 } -- between the error text and raid warnings
Reminder.HEIGHT = 30
Reminder.ICON = 18
Reminder.PAD = 10        -- inside the banner's ends
Reminder.GAP = 12        -- between two buffs
Reminder.CLOSE = 16 -- room for the close button at the right end
Reminder.SETTLE = 3 -- seconds to wait after a loading screen before checking
Reminder.HOLDER_W = 320 -- unlock handle width
Reminder.NAME_COLOR = Style.INK.TEXT

-- Each family: who gives it (class), its short name and icon, and every rank's
-- spell id (single and group-wide versions). mana: only for mana users. seen:
-- only asked for when someone in the group already has it (Divine Spirit is a
-- talent, Shadow Protection is for some fights). blessing: one per paladin in
-- the group (Reminder.BLESSING_ORDER).
local I = "Interface\\Icons\\"
Reminder.BUFFS = {
    { key = "fortitude", class = "PRIEST", short = L["Fortitude"], icon = I .. "Spell_Holy_WordFortitude",
      ids = { 1243, 1244, 1245, 2791, 10937, 10938, 25389, 21562, 21564, 25392 } },
    { key = "wild", class = "DRUID", short = L["Mark of the Wild"], icon = I .. "Spell_Nature_Regeneration",
      ids = { 1126, 5232, 6756, 5234, 8907, 9884, 9885, 26990, 21849, 21850, 26991 } },
    { key = "intellect", class = "MAGE", short = L["Intellect"], icon = I .. "Spell_Holy_MagicalSentry", mana = true,
      ids = { 1459, 1460, 1461, 10156, 10157, 27126, 23028, 27127 } },
    { key = "spirit", class = "PRIEST", short = L["Spirit"], icon = I .. "Spell_Holy_DivineSpirit", mana = true, seen = true,
      ids = { 14752, 14818, 14819, 27841, 25312, 27681, 32999 } },
    { key = "shadow", class = "PRIEST", short = L["Shadow Protection"], icon = I .. "Spell_Shadow_AntiShadow", seen = true,
      ids = { 976, 10957, 10958, 25433, 27683, 39374 } },
    { key = "might", class = "PALADIN", short = L["Might"], icon = I .. "Spell_Holy_FistOfJustice", blessing = true,
      ids = { 19740, 19834, 19835, 19836, 19837, 19838, 25291, 27140, 25782, 25916, 27141 } },
    { key = "wisdom", class = "PALADIN", short = L["Wisdom"], icon = I .. "Spell_Holy_SealOfWisdom", blessing = true,
      ids = { 19742, 19850, 19852, 19853, 19854, 25290, 27142, 25894, 25918, 27143 } },
    { key = "kings", class = "PALADIN", short = L["Kings"], icon = I .. "Spell_Magic_MageArmor", blessing = true,
      ids = { 20217, 25898 } },
    { key = "salvation", class = "PALADIN", short = L["Salvation"], icon = I .. "Spell_Holy_SealOfSalvation", blessing = true,
      ids = { 1038, 25895 } },
    { key = "light", class = "PALADIN", short = L["Light"], icon = I .. "Spell_Holy_PrayerOfHealing02", blessing = true,
      ids = { 19977, 19978, 19979, 27144, 25890, 27145 } },
    { key = "sanctuary", class = "PALADIN", short = L["Sanctuary"], icon = I .. "Spell_Nature_LightningShield", blessing = true,
      ids = { 20911, 20912, 20913, 20914, 27168, 25899, 27169 } },
}

-- Which blessings to ask for first, by your class; a tank skips Salvation
-- (it lowers threat). Classes not listed use mana and want Wisdom first.
Reminder.BLESSING_ORDER = {
    WARRIOR = { "might", "kings", "salvation", "light" },
    ROGUE = { "might", "kings", "salvation", "light" },
    HUNTER = { "might", "kings", "wisdom", "salvation" },
    default = { "wisdom", "kings", "salvation", "might" },
}
Reminder.NO_MANA = { WARRIOR = true, ROGUE = true }

Reminder.SAMPLE = { "fortitude", "intellect", "kings" }

local byKey, byId = {}, {}
local blessingCount = 0
for _, b in ipairs(Reminder.BUFFS) do
    byKey[b.key] = b
    for _, id in ipairs(b.ids) do byId[id] = b end
    if b.blessing then blessingCount = blessingCount + 1 end
end
Reminder.byKey = byKey

local function cfg()
    local db = BL.DB
    local s = db and db.settings
    return type(s) == "table" and type(s.reminder) == "table" and s.reminder or nil
end

function Reminder.Enabled()
    local c = cfg()
    return c ~= nil and c.enabled == true
end

-- ---------------------------------------------------------------------
-- What you have, who's here
-- ---------------------------------------------------------------------

-- Auras can't be read (or would come back secret), so skip the check.
function Reminder.AurasSecret()
    if DUI.Restricted() then return true end
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
        if not ok or BL.Plain(secret) ~= false then return true end -- yes, or no plain answer
    end
    return false
end

-- The client's name for each id (any locale), asked once per id that has one.
local names = {}
local function familyOfName(name)
    if type(name) ~= "string" then return nil end
    if C_Spell and C_Spell.GetSpellName then
        for _, b in ipairs(Reminder.BUFFS) do
            for _, id in ipairs(b.ids) do
                if names[id] == nil then
                    local ok, n = pcall(C_Spell.GetSpellName, id)
                    n = ok and BL.Plain(n) or nil
                    if type(n) == "string" then names[id] = n end
                end
                if names[id] == name then return b end
            end
        end
    end
    return nil
end

-- { [familyKey] = true } for every family on you; nil when unreadable.
function Reminder.PlayerFamilies()
    local have = {}
    for index = 1, BL.Auras.MAX do
        local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, "HELPFUL")
        if not ok then return nil end
        if type(data) == "nil" then break end
        data = BL.PlainTable(data)
        if not data then return nil end
        local id = BL.Plain(data.spellId)
        local b = type(id) == "number" and byId[id] or familyOfName(BL.Plain(data.name))
        if b then have[b.key] = true end
    end
    return have
end

-- The group's unit tokens, you first.
local function groupUnits()
    local units = { "player" }
    if IsInRaid() then
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitExists(u) and not UnitIsUnit(u, "player") then units[#units + 1] = u end
        end
    else
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) then units[#units + 1] = u end
        end
    end
    return units
end

-- { [CLASS] = how many are connected }, plus the units.
local function roster()
    local classes = {}
    local units = groupUnits()
    for _, u in ipairs(units) do
        local online = UnitIsConnected(u)
        if BL.Plain(online) ~= false then
            local _, token = UnitClass(u)
            token = BL.Plain(token)
            if type(token) == "string" then classes[token] = (classes[token] or 0) + 1 end
        end
    end
    return classes, units
end

local function known(b)
    if not (C_SpellBook and C_SpellBook.IsSpellKnown) then return false end
    for _, id in ipairs(b.ids) do
        local ok, yes = pcall(C_SpellBook.IsSpellKnown, id)
        if ok and BL.Plain(yes) == true then return true end
    end
    return false
end

-- Someone else in the group has it (so a priest here can give it).
local function worn(b, units)
    local get = C_UnitAuras.GetUnitAuraBySpellID
    if type(get) ~= "function" then return false end
    for i = 2, #units do
        for _, id in ipairs(b.ids) do
            local ok, aura = pcall(get, units[i], id)
            if ok and BL.PlainTable(aura) then return true end
        end
    end
    return false
end

-- The families you're missing (tables from Reminder.BUFFS), in order. An empty
-- list outside a group, nil when it can't tell (auras secret).
function Reminder.Missing()
    if not IsInGroup() then return {} end
    if Reminder.AurasSecret() then return nil end
    local have = Reminder.PlayerFamilies()
    if not have then return nil end
    local classes, units = roster()
    local _, mine = UnitClass("player")
    mine = BL.Plain(mine)
    local mana = not Reminder.NO_MANA[mine]
    local out = {}
    for _, b in ipairs(Reminder.BUFFS) do
        if not b.blessing and not have[b.key] and (classes[b.class] or 0) > 0 and (mana or not b.mana) then
            local wanted = true
            if b.seen then wanted = (mine == b.class and known(b)) or worn(b, units) end
            if wanted then out[#out + 1] = b end
        end
    end
    -- Blessings: one per paladin, the ones that suit you first.
    local paladins = classes.PALADIN or 0
    if paladins > 0 then
        local had = 0
        for _, b in ipairs(Reminder.BUFFS) do
            if b.blessing and have[b.key] then had = had + 1 end
        end
        local need = math.min(paladins, blessingCount) - had
        local tank = UnitGroupRolesAssigned and BL.Plain(UnitGroupRolesAssigned("player")) == "TANK"
        for _, key in ipairs(Reminder.BLESSING_ORDER[mine] or Reminder.BLESSING_ORDER.default) do
            if need <= 0 then break end
            if not have[key] and not (tank and key == "salvation") then
                out[#out + 1] = byKey[key]
                need = need - 1
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------------
-- The banner
-- ---------------------------------------------------------------------

local watching = false -- UNIT_AURA is only watched while the banner shows (Check to Hide)

function Reminder.Build()
    if Reminder.frame then return Reminder.frame end
    local holder = CreateFrame("Frame", "DaylightUIBuffReminderHolder", UIParent)
    holder:SetSize(Reminder.HOLDER_W, Reminder.HEIGHT)
    holder:SetFrameStrata("MEDIUM")
    Reminder.holder = holder
    DUI.Movers.Register(holder, Reminder.MOVER, "Missing Buffs", Reminder.DEFAULT)

    local f = CreateFrame("Frame", "DaylightUIBuffReminder", holder)
    f:SetPoint("CENTER", holder, "CENTER", 0, 0)
    f:SetSize(Reminder.HOLDER_W, Reminder.HEIGHT)
    f:EnableMouse(false) -- never blocks a click
    f:Hide()
    Style.Shell(f, {})
    f.label = Style.Text(f, Style.SIZE.small, "LEFT")
    f.label:SetPoint("LEFT", f, "LEFT", Reminder.PAD, 0)
    f.label:SetText(L["Missing"])
    f.entries = {}
    -- A small close button at the right end. Only it takes clicks, so the
    -- banner stays out of the way but can still be dismissed.
    local close = DUI.Widgets.Close(f, function() Reminder.Hide() end, Reminder.CLOSE, 9)
    close:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    f.close = close
    Reminder.frame = f
    return f
end

local function entry(f, i)
    local e = f.entries[i]
    if e then return e end
    e = {}
    e.edge = f:CreateTexture(nil, "ARTWORK", nil, 1)
    e.edge:SetSize(Reminder.ICON + 2, Reminder.ICON + 2)
    local c = Style.BORDER
    e.edge:SetColorTexture(c[1], c[2], c[3], 1)
    e.icon = f:CreateTexture(nil, "ARTWORK", nil, 2)
    e.icon:SetSize(Reminder.ICON, Reminder.ICON)
    e.icon:SetPoint("CENTER", e.edge, "CENTER", 0, 0)
    Style.CropIcon(e.icon)
    e.name = Style.Text(f, Style.SIZE.body, "LEFT")
    e.name:SetPoint("LEFT", e.edge, "RIGHT", 5, 0)
    f.entries[i] = e
    return e
end

local function iconOf(b)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, b.ids[1])
        tex = ok and BL.Plain(tex) or nil
        if tex then return tex end
    end
    return b.icon
end

-- Lays the banner out for a list of families; its width follows the text.
function Reminder.Fill(list)
    local f = Reminder.Build()
    Style.PaintAccentText(f.label, L["Missing"])
    local x = Reminder.PAD + f.label:GetStringWidth() + Reminder.GAP
    local n = Reminder.NAME_COLOR
    for i, fam in ipairs(list) do
        local e = entry(f, i)
        e.icon:SetTexture(iconOf(fam))
        e.name:SetText(fam.short)
        e.name:SetTextColor(n[1], n[2], n[3])
        e.edge:ClearAllPoints()
        e.edge:SetPoint("LEFT", f, "LEFT", x, 0)
        e.edge:Show(); e.icon:Show(); e.name:Show()
        x = x + Reminder.ICON + 2 + 5 + e.name:GetStringWidth() + Reminder.GAP
    end
    for i = #list + 1, #f.entries do
        local e = f.entries[i]
        e.edge:Hide(); e.icon:Hide(); e.name:Hide()
    end
    f:SetWidth(math.floor(x - Reminder.GAP + Reminder.PAD + Reminder.CLOSE + 0.5))
    f.shown = list
end

-- token: a newer show or hide cancels the older timer.
local token = 0

function Reminder.Hide(instant)
    local f = Reminder.frame
    token = token + 1
    Reminder.sample = nil
    watching = false
    if not f or not f:IsShown() then return end
    if instant or f.leaving then
        Motion.Tween("buffs.reminder", 0, 0, 0)
        f.leaving = nil
        f:Hide()
        return
    end
    f.leaving = true
    Motion.Tween("buffs.reminder", 1, 0, Motion.SLOW, function(a) f:SetAlpha(a) end, function()
        if f.leaving then f.leaving = nil; f:Hide(); f:SetAlpha(1) end
    end)
end

-- seconds: how long before it fades (nil = until hidden, for the test mode sample).
function Reminder.Show(list, seconds)
    local f = Reminder.Build()
    local was = f:IsShown() and not f.leaving
    Motion.Tween("buffs.reminder", 1, 1, 0) -- cancels a fade out
    f.leaving = nil
    Reminder.Fill(list)
    f:SetAlpha(1)
    f:Show()
    if not was then Motion.Appear(f, 6) end
    token = token + 1
    local mine = token
    if seconds then
        C_Timer.After(seconds, function() if token == mine then Reminder.Hide() end end)
    end
end

local function seconds()
    local c = cfg()
    local s = c and tonumber(c.seconds)
    return s and s > 0 and s or 10
end

-- A ready check or a new instance: check and show what's missing.
function Reminder.Check()
    if not Reminder.Enabled() or Reminder.sample then return end
    if InCombatLockdown() then return end
    local list = Reminder.Missing()
    if not list or #list == 0 then return end
    Reminder.Show(list, seconds())
    watching = true
end

-- While shown, a buff landing removes its name, and the last one fades it out.
function Reminder.Recheck()
    local f = Reminder.frame
    if not f or not f:IsShown() or f.leaving or Reminder.sample then return end
    local list = Reminder.Missing()
    if not list then return end -- can't tell right now, leave it to its timer
    if #list == 0 then Reminder.Hide() return end
    Reminder.Fill(list)
end

-- Once next frame, however many came in. A raid's roster and a pre-pull rebuff
-- come in bursts, and each check reads every aura and member.
local recheckQueued = false
function Reminder.RecheckSoon()
    if recheckQueued then return end
    recheckQueued = true
    C_Timer.After(0, function()
        recheckQueued = false
        DUI.SafeCall(Reminder.Recheck)
    end)
end

-- The sample: test mode (until it ends) or the options button (a few seconds).
function Reminder.ShowSample(timed)
    local list = {}
    for _, key in ipairs(Reminder.SAMPLE) do list[#list + 1] = byKey[key] end
    Reminder.Show(list, timed and seconds() or nil)
    Reminder.sample = true
    watching = false
end

-- Test mode ---------------------------------------------------------------

local function syncTest()
    if not Reminder.frame then return end
    if DUI.testMode and DUI.TestPartShown("buffreminder") then
        Reminder.ShowSample(false)
    elseif Reminder.sample then
        Reminder.Hide(true)
    end
end
DUI.On("TestModeChanged", syncTest)
DUI.On("TestPartChanged", function(key) if key == "buffreminder" then syncTest() end end)
DUI.RegisterTestPart("buffreminder", "Buff reminder", 85, function()
    return Reminder.frame ~= nil and Reminder.Enabled()
end)

-- A new font or accent: re-layout the shown text.
DUI.On("StyleChanged", function()
    local f = Reminder.frame
    if f and f:IsShown() and f.shown then Reminder.Fill(f.shown) end
end)

BL.On("DB_READY", function() Reminder.Build() end)
BL.On("SETTINGS_CHANGED", function(key)
    if key == "reminder.enabled" and not Reminder.Enabled() then Reminder.Hide(true) end
end)

-- Events -----------------------------------------------------------------

-- The core's events, plus your own auras through the buffs' player frame
-- (BL.OnPlayer), only watched while the banner shows.
DUI.RegisterEvent("READY_CHECK", function()
    if Reminder.frame then Reminder.Check() end
end)
DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function(_, _, reloading)
    -- A loading screen into a dungeon or raid (not a /reload): check once the
    -- group and auras have settled.
    if not Reminder.frame or BL.Plain(reloading) == true then return end
    C_Timer.After(Reminder.SETTLE, function()
        local inside, kind = false, nil
        if IsInInstance then inside, kind = IsInInstance() end
        if BL.Plain(inside) and (kind == "party" or kind == "raid") then DUI.SafeCall(Reminder.Check) end
    end)
end)
DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if Reminder.frame and not Reminder.sample then Reminder.Hide() end
end)
DUI.RegisterEvent("GROUP_ROSTER_UPDATE", function()
    if Reminder.frame then Reminder.RecheckSoon() end
end)
BL.OnPlayer("UNIT_AURA", function()
    if watching and Reminder.frame and Reminder.frame:IsShown() then Reminder.RecheckSoon() end
end)
