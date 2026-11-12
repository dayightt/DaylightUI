local _, DUI = ...
local L = DUI.L

-- Other characters on this account: their gold (gold data text), their bags
-- and bank (the bag viewer) and their names for the mail window. A deleted,
-- renamed or moved character would linger in those lists forever, so the gold
-- text and the bag chest both open Alts.Menu to remove one. Only the list
-- entries go. A character who still exists keeps their profile and is added
-- back on their next login.
local Alts = {}
DUI.Alts = Alts

-- Every other character that can be removed, as { key, name, realm, class,
-- money }. This realm first, then by name.
function Alts.List()
    local own = DUI.DB.CharKey()
    local here = own and own:match("%-(.*)$")
    local out = {}
    local chars = DUI.DB.Root().characters
    for key, c in pairs(type(chars) == "table" and chars or {}) do
        local inv = type(c) == "table" and type(c.inventory) == "table" and c.inventory or nil
        if key ~= own and type(c) == "table" and (type(c.money) == "number" or inv or type(c.mailName) == "string") then
            local name, realm = key:match("^(.-)%-(.*)$")
            local money = type(c.money) == "number" and c.money or (inv and type(inv.money) == "number" and inv.money) or nil
            out[#out + 1] = { key = key, name = name or key, realm = realm or "", class = c.class or (inv and inv.class), money = money }
        end
    end
    table.sort(out, function(a, b)
        local ah, bh = a.realm == here, b.realm == here
        if ah ~= bh then return ah end
        if a.realm ~= b.realm then return a.realm < b.realm end
        return a.name < b.name
    end)
    return out
end

-- Never yourself, since you'd be re-added right away. Fires CharacterForgotten.
function Alts.Forget(key)
    local chars = DUI.DB.Root().characters
    local c = type(chars) == "table" and chars[key]
    if key == DUI.DB.CharKey() or type(c) ~= "table" then return false end
    c.money, c.inventory, c.mailName = nil, nil, nil
    DUI.Fire("CharacterForgotten", key)
    return true
end

-- Each character in class color with their gold. A click asks to confirm, and
-- the menu stays open for the next one.
function Alts.Menu(owner)
    local list = Alts.List()
    local W = DUI.Widgets
    if #list == 0 then return W.CloseMenu() end
    local here = (DUI.DB.CharKey() or ""):match("%-(.*)$")
    local keys = { "title", "hint" }
    local values = { title = L["Remove a character"], hint = L["They come back if you log in on them."] }
    local confirm = {}
    for _, c in ipairs(list) do
        local r, g, b = DUI.Style.ClassTextColor(c.class)
        local name = c.realm ~= here and (c.name .. " - " .. c.realm) or c.name
        keys[#keys + 1] = c.key
        values[c.key] = DUI.Win.Parts.Hex({ r, g, b }) .. name .. "|r"
            .. (c.money and ("  " .. DUI.MoneyString(c.money)) or "")
        confirm[c.key] = true
    end
    W.OpenMenu(owner, keys, values, nil, function(key)
        Alts.Forget(key)
        Alts.Menu(owner)
    end, nil, { titles = { title = true }, hints = { hint = true }, confirm = confirm, keepOpen = true })
end
