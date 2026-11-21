-- Temporary weapon enchants (poisons, sharpening stones, oils, shaman imbues) for
-- every module that shows them. They aren't auras: the client reports them per
-- weapon slot, and the answers stay plain in a fight too.

local _, DUI = ...

local Weapons = {}
DUI.Weapons = Weapons

-- Enum.WeaponSlot to its inventory slot.
Weapons.INVENTORY = { [0] = 16, [1] = 17, [2] = 18 }

local function plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function plainTable(t)
    if type(t) ~= "table" or (issecrettable and issecrettable(t)) then return nil end
    return t
end

local function number(v)
    v = plain(v)
    return type(v) == "number" and v or nil
end

local function trim(list, n)
    for i = #list, n + 1, -1 do list[i] = nil end
    return list
end

-- Every enchant on a weapon slot (Enum.WeaponSlot), each as plain fields: enchantID,
-- kind (Enum.ItemEnchantType), msLeft, charges and icon (the enchant's own, else the
-- weapon's). into = a list to fill again, reusing its tables, for callers that ask
-- several times a second. The second return is true when the client refused the read.
function Weapons.Read(weaponSlot, into)
    local out = into or {}
    local get = C_Item and C_Item.GetWeaponEnchantInfo
    if type(get) ~= "function" then return trim(out, 0), false end
    local ok, list = pcall(get, weaponSlot)
    if not ok then return trim(out, 0), true end
    local n, inv = 0, Weapons.INVENTORY[weaponSlot]
    for _, e in ipairs(plainTable(list) or {}) do
        e = plainTable(e)
        if e and plain(e.hasEnchant) then
            n = n + 1
            local t = out[n]
            if type(t) ~= "table" then t = {}; out[n] = t end
            t.enchantID = number(e.enchantID)
            t.kind = number(e.enchantType) or 0
            t.msLeft = number(e.timeLeft) or 0
            t.charges = number(e.charges) or 0
            t.icon = plain(e.enchantIconID) or (inv and GetInventoryItemTexture("player", inv)) or nil
        end
    end
    return trim(out, n), false
end

-- The enchant's own name. The client only gives it in the weapon's tooltip: the
-- first green line, without its "(30 min)".
function Weapons.Name(invSlot)
    if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return nil end
    local ok, info = pcall(C_TooltipInfo.GetInventoryItem, "player", invSlot)
    info = ok and plainTable(info) or nil
    local lines = info and plainTable(info.lines)
    if not lines then return nil end
    for i = 2, #lines do
        local line = plainTable(lines[i])
        local color = line and plainTable(line.leftColor)
        local text = line and plain(line.leftText)
        if color and type(text) == "string" then
            local r, g, b = number(color.r), number(color.g), number(color.b)
            if g and g > 0.9 and (r or 0) < 0.2 and (b or 0) < 0.2 then
                text = string.gsub(text, "%s*%(.-%)%s*$", "")
                if text ~= "" then return text end
            end
        end
    end
    return nil
end
