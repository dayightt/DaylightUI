-- Your interrupt, for any cast bar that shows when it's ready: which spell it is
-- (by class, rank and stance), whether it's ready, and a thin mark on a cast bar
-- where it comes off cooldown.
--
-- In combat a cooldown's start and length are secret, so the mark is never
-- computed in Lua. A hidden StatusBar spans the cast bar, its range the cast's
-- start and end times and its value the time the interrupt is ready (all whole
-- values the client accepts secret); the mark sits on that fill's edge. It's
-- clipped to the part of the cast still to come, so it hides by itself once the
-- cast passes it (the interrupt is ready then), and when the cooldown outlasts
-- the cast (the fill is full and the mark falls just past the bar's end).
-- isActive and isOnGCD stay plain, so "ready now" is a plain answer.

local _, DUI = ...

local Interrupt = {}
DUI.Interrupt = Interrupt

-- Each class's interrupts in this client: groups of ranks, low to high (the last
-- one you know counts; ranks share a cooldown). stances = the warrior stance
-- indexes it works in, forms = the druid form ids. Felhunter's Spell Lock is a pet
-- spell (its ranks come from demon tomes). Every rank is in this client's trainer
-- and tome lists; Silence and Feral Charge are talents, so they're in neither and
-- their ids and Feral Charge's forms come from other addons written for this
-- client (not yet checked in game).
Interrupt.SPELLS = {
    WARRIOR = {
        { 72, 1671, 1672, stances = { 1, 2 } }, -- Shield Bash: battle, defensive
        { 6552, 6554, stances = { 3 } }, -- Pummel: berserker
    },
    ROGUE = { { 1766, 1767, 1768, 1769 } }, -- Kick
    MAGE = { { 2139 } }, -- Counterspell
    SHAMAN = { { 8042, 8044, 8045, 8046, 10412, 10413, 10414 } }, -- Earth Shock
    PRIEST = { { 15487 } }, -- Silence
    WARLOCK = { { 19244, 19647, pet = true } }, -- Spell Lock
    DRUID = { { 16979, forms = { 5, 8 } } }, -- Feral Charge: bear, dire bear
}
Interrupt.MARK_PX = 3 -- the mark's width

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

local function known(id, pet)
    local book = C_SpellBook
    if type(book) ~= "table" or type(book.IsSpellKnown) ~= "function" then return false end
    local bank = pet and Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet or nil
    local ok, yes = pcall(book.IsSpellKnown, id, bank)
    return ok and yes == true
end

local function has(list, v)
    for _, x in ipairs(list) do
        if x == v then return true end
    end
    return false
end

-- Whether the group works in your stance or form right now (a missing answer counts
-- as yes).
local function usableNow(group)
    if group.stances and type(GetShapeshiftForm) == "function" then
        local ok, form = pcall(GetShapeshiftForm)
        if ok and type(form) == "number" and not isSecret(form) then return has(group.stances, form) end
    end
    if group.forms and type(GetShapeshiftFormID) == "function" then
        local ok, form = pcall(GetShapeshiftFormID)
        if ok and not isSecret(form) then return type(form) == "number" and has(group.forms, form) end
    end
    return true
end

local spell, looked = nil, false

local function find()
    local _, class = UnitClass("player")
    local groups = type(class) == "string" and not isSecret(class) and Interrupt.SPELLS[class]
    if not groups then return nil end
    -- Usable in this stance first, then any you know (shown as on cooldown would be
    -- wrong, so a stance-locked one only counts while it can be cast).
    for _, group in ipairs(groups) do
        if usableNow(group) then
            for i = #group, 1, -1 do
                if known(group[i], group.pet) then return group[i] end
            end
        end
    end
    return nil
end

-- Your interrupt's spell id right now (known, and castable in your stance or
-- form), or nil.
function Interrupt.Spell()
    if not looked then
        looked = true
        spell = find()
    end
    return spell
end

-- true: ready now (or only the global cooldown runs). false: on its cooldown.
-- nil: no interrupt, or no plain answer.
function Interrupt.Ready()
    local id = Interrupt.Spell()
    if not id or type(C_Spell) ~= "table" or type(C_Spell.GetSpellCooldown) ~= "function" then return nil end
    local ok, info = pcall(C_Spell.GetSpellCooldown, id)
    if not ok or type(info) ~= "table" then return nil end
    local active, gcd = info.isActive, info.isOnGCD
    if isSecret(active) or isSecret(gcd) then return nil end
    if active ~= true or gcd == true then return true end
    if info.isEnabled == false then return nil end -- on hold: no end time yet
    return false
end

-- The cooldown as the client's duration object while it runs (its times secret in
-- combat), else nil.
function Interrupt.Cooldown()
    if Interrupt.Ready() ~= false then return nil end
    local get = type(C_Spell) == "table" and C_Spell.GetSpellCooldownDuration
    if type(get) ~= "function" then return nil end
    local ok, d = pcall(get, Interrupt.Spell(), true)
    if ok and type(d) ~= "nil" then return d end
    return nil
end

-- What can change the answer: learning a rank, a stance or form, a pet, a
-- cooldown. Listeners redraw on DUI.On("InterruptChanged").
local function forget()
    looked = false
    DUI.Fire("InterruptChanged")
end
for _, e in ipairs({ "SPELLS_CHANGED", "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD" }) do
    pcall(DUI.RegisterEvent, e, forget)
end
pcall(DUI.RegisterEvent, "UNIT_PET", function(_, unit)
    if unit == "player" then forget() end
end)
pcall(DUI.RegisterEvent, "SPELL_UPDATE_COOLDOWN", function() DUI.Fire("InterruptChanged") end)

-- ---------------------------------------------------------------------
-- The mark on a cast bar
-- ---------------------------------------------------------------------

-- A mark for bar (a cast bar's StatusBar). Hidden until Interrupt.ShowMark.
function Interrupt.NewMark(bar)
    local m = {}
    m.bar = bar
    m.clip = CreateFrame("Frame", nil, bar)
    m.clip:SetClipsChildren(true)
    m.clip:SetFrameLevel(bar:GetFrameLevel() + 2)
    m.probe = CreateFrame("StatusBar", nil, bar)
    m.probe:SetAllPoints(bar)
    m.probe:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    local fill = m.probe:GetStatusBarTexture()
    if fill then fill:SetAlpha(0) end
    m.tick = m.clip:CreateTexture(nil, "OVERLAY")
    m.tick:SetTexture("Interface\\Buttons\\WHITE8x8")
    m.clip:Hide()
    return m
end

-- The mark at ready, on a bar spanning start to finish (any of the three may be
-- secret: they only go to the client's setters). channel: the bar drains (shows
-- time left) instead of filling. The part of the cast still to come is the side
-- past the cast fill's moving edge.
function Interrupt.PlaceMark(m, start, finish, ready, channel)
    local bar = m.bar
    local rev = false
    if bar.GetReverseFill then
        local ok, r = pcall(bar.GetReverseFill, bar)
        rev = ok and r == true
    end
    local probeRev = rev ~= (channel == true)
    m.probe:SetReverseFill(probeRev)
    m.probe:SetMinMaxValues(start, finish)
    m.probe:SetValue(ready)
    local edge = m.probe:GetStatusBarTexture()
    local fill = bar:GetStatusBarTexture()
    local fillEdge = rev and "LEFT" or "RIGHT"
    local clip, tick = m.clip, m.tick
    clip:ClearAllPoints()
    clip:SetPoint("TOP", bar, "TOP", 0, 0)
    clip:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    if probeRev then
        clip:SetPoint("LEFT", bar, "LEFT", 0, 0)
        clip:SetPoint("RIGHT", fill, fillEdge, 0, 0)
    else
        clip:SetPoint("LEFT", fill, fillEdge, 0, 0)
        clip:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    end
    tick:ClearAllPoints()
    tick:SetPoint("TOP", bar, "TOP", 0, 0)
    tick:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    if probeRev then
        tick:SetPoint("RIGHT", edge, "LEFT", 0, 0)
    else
        tick:SetPoint("LEFT", edge, "RIGHT", 0, 0)
    end
    tick:SetWidth(DUI.Pixel.Px(bar, Interrupt.MARK_PX))
    -- Your interrupt: the accent, read now (it can change any time).
    local r, g, b = DUI.Style.Accent()
    tick:SetVertexColor(r, g, b, 1)
end

-- Shows the mark for a cast (castDuration: the duration object the cast bar runs
-- on) while your interrupt is on cooldown, else hides it. fade: ease in FAST (a
-- cooldown that started mid-cast); a new cast shows it at once.
function Interrupt.ShowMark(m, castDuration, channel, fade)
    local cd = type(castDuration) ~= "nil" and Interrupt.Cooldown() or nil
    if not cd then return Interrupt.HideMark(m) end
    local ok = pcall(function()
        Interrupt.PlaceMark(m, castDuration:GetStartTime(), castDuration:GetEndTime(), cd:GetEndTime(), channel)
    end)
    if not ok then return Interrupt.HideMark(m) end
    local M = DUI.Motion
    if fade and not m.clip:IsShown() then
        M.AlphaTo(m.clip, 1, M.FAST)
    else
        M.AlphaTo(m.clip, 1, 0)
    end
end

function Interrupt.HideMark(m)
    if m and m.clip:IsShown() then DUI.Motion.AlphaTo(m.clip, 0, 0, true) end
end
