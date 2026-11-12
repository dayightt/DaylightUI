-- Stat tooltips. Out of combat it's the game's own (StatText.GameTip), which is
-- localized and has every number, like armor's damage reduction. Otherwise a
-- plain sentence per stat plus where it comes from. Secret or dimmed rows get none.

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char
local L = DUI.L

local StatText = {}
ns.StatText = StatText

-- "1 in N" for a chance in percent; nil at 0.
local function oneIn(pct)
    if type(pct) ~= "number" or pct <= 0 then return nil end
    return math.max(1, math.floor(100 / pct + 0.5))
end
local function chance(text)
    return function(v)
        local n = oneIn(v)
        return n and string.format(text, n) or nil
    end
end
local GEAR = L["From your gear, buffs and race."]
local function resist(say)
    return { say = say,
             from = L["From your gear and buffs."] }
end

-- say is a string or a function of the row's values. If the function
-- returns nil, `none` is shown instead. from says where the stat comes from.
StatText.SAY = {
    str = { say = L["Your melee attacks hit harder: Strength adds attack power."], from = GEAR },
    agi = { say = L["More critical strikes, dodges and armor. Hunters and rogues hit harder with it too."], from = GEAR },
    sta = { say = function(v) return string.format(L["Your health. Each point adds about 10; you have %.0f."], v) end, from = GEAR },
    int = { say = L["More mana, and more critical strikes with spells."], from = GEAR },
    spi = { say = L["Your health and mana come back faster while you're not fighting or casting."], from = GEAR },
    dmg = { say = function(lo, hi) return string.format(L["Each main-hand swing hits for %.0f to %.0f before armor."], lo, hi) end, from = L["From your weapon and attack power."] },
    speed = { say = function(v) return string.format(L["Your main hand swings every %.2f seconds. Lower is faster."], v) end, from = L["From your weapon, and haste."] },
    ap = { say = function(v) return string.format(L["Adds about %.0f damage per second to your melee attacks."], v / 14) end, from = L["From Strength, Agility, gear and buffs."] },
    hit = { say = function(v) return string.format(L["Your attacks and spells miss %.1f%% less often."], v) end, from = L["From your gear and talents."] },
    crit = { say = chance(L["About 1 in %d of your attacks hits for double damage."]), none = L["Your attacks don't land critical hits yet."], from = L["From Agility, gear and talents."] },
    expertise = { say = L["Fewer of your attacks are dodged or parried."], from = L["From your gear and talents."] },
    rdmg = { say = function(lo, hi) return string.format(L["Each shot hits for %.0f to %.0f before armor."], lo, hi) end, from = L["From your ranged weapon, ammo and attack power."] },
    rspeed = { say = function(v) return string.format(L["You shoot every %.2f seconds. Lower is faster."], v) end, from = L["From your ranged weapon, and haste."] },
    rap = { say = function(v) return string.format(L["Adds about %.0f damage per second to your shots."], v / 14) end, from = L["From Agility, gear and buffs."] },
    rcrit = { say = chance(L["About 1 in %d of your shots hits for double damage."]), none = L["Your shots don't land critical hits yet."], from = L["From Agility, gear and talents."] },
    sp = { say = function(v) return string.format(L["Adds up to %.0f to your spells' damage."], v) end, from = L["From your gear and buffs."] },
    heal = { say = function(v) return string.format(L["Adds up to %.0f to your heals."], v) end, from = L["From your gear and buffs."] },
    scrit = { say = chance(L["About 1 in %d of your spells lands a critical hit for half again as much."]), none = L["Your spells don't land critical hits yet."], from = L["From Intellect, gear and talents."] },
    regen = { say = function(v) return string.format(L["You get back %.0f mana every 5 seconds while casting."], v) end, from = L["From Spirit, gear and buffs."] },
    health = { say = function(v) return string.format(L["You can take %.0f damage before you die."], v) end, from = L["From Stamina, gear and buffs."] },
    power = { say = L["The most you can hold for your abilities."], from = L["From your class, gear and buffs."] },
    ohdmg = { say = function(lo, hi) return string.format(L["Each off-hand swing hits for %.0f to %.0f before armor."], lo, hi) end, from = L["From your weapon and attack power."] },
    haste = { say = function(v) return string.format(L["You swing %.1f%% faster."], v) end, from = L["From your gear, buffs and talents."] },
    rhaste = { say = function(v) return string.format(L["You shoot %.1f%% faster."], v) end, from = L["From your quiver, gear and buffs."] },
    shaste = { say = function(v) return string.format(L["You cast %.1f%% faster."], v) end, from = L["From your gear, buffs and talents."] },
    armorpen = { say = function(v) return string.format(L["Your attacks ignore %.0f of the target's armor."], v) end, from = L["From your gear and talents."] },
    rarmorpen = { say = function(v) return string.format(L["Your attacks ignore %.0f of the target's armor."], v) end, from = L["From your gear and talents."] },
    spen = { say = function(v) return string.format(L["Your spells ignore %.0f of the target's resistances."], v) end, from = L["From your gear and talents."] },
    armor = { say = L["Lowers the physical damage you take."], from = L["From your gear, Agility and buffs."] },
    defense = { say = L["Fewer critical hits against you, and more misses, dodges, parries and blocks."], from = L["From your defense skill and gear."] },
    dodge = { say = chance(L["You dodge about 1 in %d attacks."]), none = L["You don't dodge attacks yet."], from = L["From Agility, defense and gear."] },
    parry = { say = chance(L["You parry about 1 in %d attacks from the front."]), none = L["You can't parry yet."], from = L["From defense, gear and talents."] },
    block = { say = chance(L["You block about 1 in %d attacks with your shield."]), none = L["You don't block yet."], from = L["From your shield, defense and gear."] },
    movespeed = { say = function(v) return string.format(L["You move at %.0f%% of a normal run: on foot, mounted, swimming or flying, by what you're doing."], v) end,
                  from = L["From your mount, talents, gear and buffs."] },
    res_fire = resist(L["Lowers the fire damage you take, and how often fire spells hit you in full."]),
    res_nature = resist(L["Lowers the nature damage you take, and how often nature spells hit you in full."]),
    res_frost = resist(L["Lowers the frost damage you take, and how often frost spells hit you in full."]),
    res_shadow = resist(L["Lowers the shadow damage you take, and how often shadow spells hit you in full."]),
    res_arcane = resist(L["Lowers the arcane damage you take, and how often arcane spells hit you in full."]),
}

function StatText.For(row)
    if row.secret or row.stale or not row.values then return nil end
    local e = StatText.SAY[row.id]
    if not e then return nil end
    local say = e.say
    if type(say) == "function" then say = say(unpack(row.values, 1, table.maxn(row.values))) or e.none end
    return say, e.from
end

-- Swaps the game's color codes for the window's. White and gold are dropped so
-- the line color shows, green and red become the up and down colors, and
-- anything else is kept.
local function hex(c) return string.format("ff%02x%02x%02x", c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5) end
function StatText.Recode(text, look)
    return (string.gsub(text, "|c(%x%x%x%x%x%x%x%x)", function(code)
        code = string.lower(code)
        if code == "ffffffff" or code == "ffffd200" then return "" end
        if code == "ff20ff20" and look.up then return "|c" .. hex(look.up) end
        if code == "ffff2020" and look.down then return "|c" .. hex(look.down) end
    end))
end

-- Colors standalone numbers in a sentence ("by 11.8") with `c`. Skips lines
-- that already have color codes, since the added |r would end theirs early.
function StatText.Numbers(text, c)
    if text:find("|c", 1, true) then return text end
    local open = DUI.Win.Parts.Hex(c)
    return (text:gsub("%f[%w](%d[%d,]*%.?%d*)", function(n)
        local tail = ""
        if n:sub(-1) == "." then n, tail = n:sub(1, -2), "." end
        return open .. n .. "|r" .. tail
    end))
end

-- Recolors the game's tooltip after it's drawn. Only runs out of combat, so
-- the text is never secret.
function StatText.Restyle(tip, look)
    if type(look) ~= "table" or type(tip.NumLines) ~= "function" or type(tip.GetName) ~= "function" then return end
    local name = tip:GetName()
    if type(name) ~= "string" then return end
    for i = 1, tip:NumLines() or 0 do
        for _, side in ipairs({ "Left", "Right" }) do
            local fs = _G[name .. "Text" .. side .. i]
            local text = type(fs) == "table" and fs.GetText and fs:GetText()
            if type(text) == "string" and text ~= "" then
                local c = (i > 1 and side == "Left") and look.body or look.title
                text = StatText.Recode(text, look)
                if c == look.body and look.value then
                    -- "pop" colors each number by meaning: heals green, damage red, else the accent
                    if look.value == "pop" then text = DUI.Tips.Numbers(text)
                    else text = StatText.Numbers(text, look.value) end
                end
                fs:SetText(text)
                fs:SetTextColor(c[1], c[2], c[3])
            end
        end
    end
    tip:Show()   -- re-measure, since the widths may have changed
end

-- The game's sheet functions write to a Value text. Give them one that does nothing.
local SINK = { SetText = function() end }

-- Shows the game's own tooltip for a row. Its sheet function fills
-- owner.tooltip (and sometimes owner.onEnterFunc), then it's shown the way the
-- game's sheet does it. Never with secret numbers, since the game's code does
-- math on them. Returns false when it can't. look holds the window's colors.
-- The game's expertise hover picks its sentence from a global `category` that
-- nothing sets, so it always shows the ranged one. This is the same tooltip
-- with the melee sentence.
function StatText.ExpertiseTip(owner)
    local main, off = GetExpertise()
    local text = string.format("%.1f%%", main)
    if IsDualWielding() then text = text .. " / " .. string.format("%.1f%%", off) end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(HIGHLIGHT_FONT_COLOR_CODE .. string.format(PAPERDOLLFRAME_TOOLTIP_FORMAT, _G["COMBAT_RATING_NAME" .. CR_EXPERTISE])
        .. " " .. text .. FONT_COLOR_CODE_CLOSE)
    GameTooltip:AddLine(string.format(CR_EXPERTISE_TOOLTIP, text), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
    GameTooltip:Show()
end

-- What the game's sheet functions leave on a stat frame. Rows are reused for
-- other stats, so a main-hand row must not keep an off-hand row's title.
local LEFTOVERS = { "tooltip", "tooltip2", "tooltip3", "tooltip4", "onEnterFunc", "UpdateTooltip", "tooltipLabel",
    "offhandDamage", "offhandAttackSpeed", "bonusDamage", "minModifier", "lineWrap" }

function StatText.GameTip(owner, row, look)
    if row.secret or row.stale or type(row.game) ~= "string" then return false end
    local fn, show = _G[row.game], _G.PaperDollStatTooltip
    if type(fn) ~= "function" or type(show) ~= "function" or type(GameTooltip) ~= "table" then return false end
    for _, k in ipairs(LEFTOVERS) do owner[k] = nil end
    owner.Value = SINK
    local ok, unit = nil, row.unit or "player"
    if row.gameArg ~= nil then ok = pcall(fn, owner, unit, row.gameArg) else ok = pcall(fn, owner, unit) end
    -- Damage rows set no text. Their hover function (CharacterDamageFrame_OnEnter)
    -- builds the tooltip instead.
    if not ok or (type(owner.tooltip) ~= "string" and type(owner.onEnterFunc) ~= "function") then return false end
    if owner.onEnterFunc ~= nil and owner.onEnterFunc == _G.PaperDollFrame_ExpertiseOnEnter
        and type(_G.CR_EXPERTISE_TOOLTIP) == "string" then
        owner.onEnterFunc = StatText.ExpertiseTip
    end
    -- The game's spell power hover leads with the lowest school and lists the
    -- others. The row shows the best school, so lead with that one instead.
    if owner.onEnterFunc ~= nil and owner.onEnterFunc == _G.CharacterSpellBonusDamage_OnEnter and type(owner.bonusDamage) == "table" then
        local best = owner.minModifier
        for _, v in pairs(owner.bonusDamage) do
            if type(v) == "number" and type(best) == "number" and v > best then best = v end
        end
        owner.minModifier = best
    end
    if not pcall(owner.onEnterFunc or show, owner) then return false end
    StatText.Restyle(GameTooltip, look)
    StatText.KeepStyled(owner, look)
    return true
end

-- Some hovers redraw themselves while shown (movement speed sets
-- UpdateTooltip, which the tooltip calls every moment). Each redraw would
-- bring back the game's colors, so restyle after it. In a fight the numbers
-- are secret, so the tooltip just stays as it was.
function StatText.KeepStyled(owner, look)
    local redraw = owner.UpdateTooltip
    if type(redraw) ~= "function" then return end
    local function update(self)
        if InCombatLockdown() or DUI.Restricted() then return end
        if pcall(redraw, self) then StatText.Restyle(GameTooltip, look) end
        self.UpdateTooltip = update   -- the game's redraw sets itself back
    end
    owner.UpdateTooltip = update
end
