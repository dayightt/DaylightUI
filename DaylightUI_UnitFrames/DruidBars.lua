-- Druid resource bars (druidBars, off by default). Small bars under the player
-- frame for the druid powers not shown on the main bar: rage and energy in
-- caster form, mana and energy in bear, mana and rage in cat. Each appears once
-- you know the matching form. Gradient bars in each power's colors, using the
-- player frame's power texture, with an optional number. They have their own
-- unlock handle (unitframes.druidBars) and fade with the player frame.
-- Power values go straight to secret-safe setters and are never compared.

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel, Motion = DUI.Style, DUI.Pixel, DUI.Motion

local DruidBars = {}
ns.DruidBars = DruidBars

DruidBars.KEY = "unitframes.druidBars"
-- Over the right half of the player frame. The name tab is on the left, the pet
-- and hung cast bar sit underneath, and the frame's default spot is too close
-- to the bottom of the screen for more.
DruidBars.HOME = { "BOTTOMRIGHT", "DaylightUIFrame_player", "TOPRIGHT", -8, 6 }
-- Powers in stacking order: Enum.PowerType id, token, and the forms that need
-- it (nil means always, i.e. your mana).
DruidBars.POWERS = {
    { id = 0, token = "MANA" },
    { id = 1, token = "RAGE", forms = { 5487, 9634 } },   -- Bear Form, Dire Bear Form
    { id = 3, token = "ENERGY", forms = { 768 } },        -- Cat Form
}

local holder, rows, cfg, current

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

local function known(power)
    if not power.forms then return true end
    if not (C_SpellBook and C_SpellBook.IsSpellKnown) then return false end
    for _, id in ipairs(power.forms) do
        if C_SpellBook.IsSpellKnown(id) then return true end
    end
    return false
end

local function isDruid()
    local _, class = UnitClass("player")
    return class == "DRUID"
end

function DruidBars.Create(f)
    holder = CreateFrame("Frame", "DaylightUIDruidBars", UIParent)
    holder:SetSize(160, 14)
    holder.player = f
    holder:Hide()
    rows = {}
    local media = ns.UF.MediaOf(f.spec)
    for i, p in ipairs(DruidBars.POWERS) do
        local r = CreateFrame("Frame", nil, holder)
        Style.Shell(r)
        r.bar = Style.Bar(r, nil, media.bars.power)
        r.text = Style.Text(r.bar, Style.SIZE.tiny, "CENTER")
        r.text:SetPoint("CENTER", r.bar, "CENTER", 0, 0)
        r.power = p
        r:Hide()
        rows[i] = r
    end
    holder:SetScript("OnEvent", function(_, event, unit, kind)
        if event == "UNIT_POWER_FREQUENT" then DruidBars.Values() else DruidBars.Update() end
    end)
    return holder
end

-- The powers to show now: every known one except the one the main bar shows.
function DruidBars.Wanted()
    local out = {}
    if not (cfg and cfg.enabled == true and isDruid()) then return out end
    local _, token = UnitPowerType("player")
    if isSecret(token) then token = current end
    current = token
    for i, p in ipairs(DruidBars.POWERS) do
        if p.token ~= token and known(p) then out[#out + 1] = i end
    end
    return out
end

function DruidBars.Values(instant)
    if not rows then return end
    for _, r in ipairs(rows) do
        if r:IsShown() then
            local id = r.power.id
            r.bar:SetMinMaxValues(0, UnitPowerMax("player", id))
            Style.SetBarValue(r.bar, UnitPower("player", id), instant)
            if r.text:IsShown() then r.text:SetFormattedText("%d", UnitPower("player", id)) end
        end
    end
end

-- Lays the rows out for what's wanted now. Each one eases in or out (FAST).
function DruidBars.Update(instant)
    if not holder then return end
    local want = DruidBars.Wanted()
    local w = math.max(40, tonumber(cfg and cfg.width) or 94)
    local h = math.max(3, tonumber(cfg and cfg.height) or 6)
    local gap = tonumber(cfg and cfg.spacing) or 2
    -- A thin bar gets half the border, like the buff bars. Full border looked heavy.
    local px = math.max(1, math.floor((DUI.DB.General().borderPx or 2) / 2))
    local T = Pixel.Px(holder, px)
    local show = {}
    for n, i in ipairs(want) do show[i] = n end
    for i, r in ipairs(rows) do
        local n = show[i]
        if n then
            local back = r.leaving
            r.leaving = nil
            r:ClearAllPoints()
            r:SetPoint("TOP", holder, "TOP", 0, -(n - 1) * (h + 2 * T + gap))
            r:SetSize(w, h + 2 * T)
            r.shellOpts = r.shellOpts or {}
            r.shellOpts.borderPx = px
            Style.Shell(r, r.shellOpts)
            r.bar:ClearAllPoints()
            r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", T, -T)
            r.bar:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -T, T)
            ns.UF.PaintPower(r.bar, r.power.token, "player", holder.player)
            r.text:SetShown(cfg.showText == true)
            Style.SetTextSize(r.text, math.max(8, math.min(Style.SIZE.small, h + 4)))
            if not r:IsShown() or back then
                r:Show()
                if instant then r:SetAlpha(1) else Motion.Fade(r, 0, 1, Motion.FAST) end
            end
        elseif r:IsShown() and not r.leaving then
            -- Fade out over FAST, then hide. A form change swaps them instantly.
            if instant then r:Hide() else
                r.leaving = true
                Motion.Fade(r, 1, 0, Motion.FAST)
                C_Timer.After(Motion.FAST, function() if r.leaving then r:Hide(); r.leaving = nil end end)
            end
        end
    end
    local count = #want
    holder:SetSize(w, math.max(1, count * (h + 2 * T) + math.max(0, count - 1) * gap))
    holder:SetShown(count > 0)
    DruidBars.Values(true)
end

-- Settings (player.druidBars) and events. Only a druid with them on listens.
function DruidBars.Layout(c)
    cfg = c
    if not holder then return end
    local on = cfg and cfg.enabled == true and isDruid()
    if on then
        holder:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        holder:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        holder:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
        holder:RegisterEvent("SPELLS_CHANGED")
    else
        holder:UnregisterAllEvents()
    end
    DruidBars.Update(true)
end
