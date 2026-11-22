local _, DUI = ...
local L = DUI.L

-- Other characters on this account: their gold (gold data text), their bags
-- and bank (the bag viewer) and their names for the mail window. A deleted,
-- renamed or moved character would linger in those lists forever, so the gold
-- text and the bag chest both open Alts.Menu to remove one. Its gold, bags and
-- mail name go, and it's marked `forgotten` so the lists that only know it by
-- its profile choice (the profiles page, the setup guide) leave it out too. A
-- character who still exists keeps their profile and setup, and is added back
-- on their next login.
local Alts = {}
DUI.Alts = Alts

-- The ruleset part of a realm name: "CAMWOW US1 Realm 8 PvP" gives "PvP", nil
-- when the name has no ruleset word. C_GameRules only answers for the player,
-- so for anyone else the realm name is all there is.
function Alts.RulesetOf(realm)
    if type(realm) ~= "string" or DUI.IsSecret(realm) then return nil end
    local s = string.lower(realm)
    if s:find("%f[%a]hardcore%f[%A]") then return L["Hardcore"] end
    if s:find("%f[%a]rp[%s%-]*p?vp%f[%A]") then return L["RP PvP"] end
    if s:find("%f[%a]pvp%f[%A]") then return L["PvP"] end
    if s:find("%f[%a]pve%f[%A]") then return L["PvE"] end
    if s:find("%f[%a]rp%f[%A]") then return L["RP"] end
end

-- Is this realm on the player's ruleset? Many numbered realms share one ruleset,
-- so only the ruleset word can say. A name with no word (on either side) counts
-- as the same, since there's no way to tell.
function Alts.SameRuleset(realm)
    local mine = Alts.RulesetOf(GetRealmName and GetRealmName())
    local theirs = Alts.RulesetOf(realm)
    return mine == nil or theirs == nil or mine == theirs
end

-- A saved character ("First Last-Realm") the player could reach from here.
-- Bags and gold on another ruleset can never be traded or mailed over, so the
-- bag viewer, item counts and the gold list leave those characters out.
function Alts.Reachable(key)
    if type(key) ~= "string" then return false end
    return Alts.SameRuleset(key:match("%-(.*)$"))
end

-- Every other character on this ruleset that can be removed, as { key, name,
-- realm, class, money }. This realm first, then by name.
function Alts.List()
    local own = DUI.DB.CharKey()
    local here = own and own:match("%-(.*)$")
    local out = {}
    local chars = DUI.DB.Root().characters
    for key, c in pairs(type(chars) == "table" and chars or {}) do
        local inv = type(c) == "table" and type(c.inventory) == "table" and c.inventory or nil
        if key ~= own and type(c) == "table" and Alts.Reachable(key)
            and (type(c.money) == "number" or inv or type(c.mailName) == "string") then
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

-- Never yourself, since you'd be re-added right away. Its name also leaves
-- every character's recent mail names. Fires CharacterForgotten.
function Alts.Forget(key)
    local chars = DUI.DB.Root().characters
    local c = type(chars) == "table" and chars[key]
    if key == DUI.DB.CharKey() or type(c) ~= "table" then return false end
    local mailName = c.mailName
    c.money, c.inventory, c.mailName = nil, nil, nil
    c.forgotten = true
    if type(mailName) == "string" then
        for _, other in pairs(chars) do
            local recent = type(other) == "table" and other.mailRecent
            if type(recent) == "table" then
                for i = #recent, 1, -1 do
                    if recent[i] == mailName then table.remove(recent, i) end
                end
            end
        end
    end
    DUI.Fire("CharacterForgotten", key)
    return true
end

-- Removed but still there: is a saved character one the player took out of
-- the lists? Logging in on it brings it back (DB.OnLogin).
function Alts.Forgotten(c)
    return type(c) == "table" and c.forgotten == true
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
