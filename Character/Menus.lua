-- The title menu (click your name). The game does the real work through
-- SetCurrentTitle.

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char
local L = DUI.L

local Menus = {}
ns.Menus = Menus

Menus.NONE = "-1"
Menus.TITLE_W = 200

local function trim(s) return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", "")) end

-- The titles you know, "No title" first; keys are the title ids as text.
function Menus.TitleList()
    local keys, values = { Menus.NONE }, { [Menus.NONE] = L["No title"] }
    local n = type(GetNumTitles) == "function" and GetNumTitles() or 0
    for i = 1, n do
        if IsTitleKnown(i) then
            local name = GetTitleName(i)
            if type(name) == "string" and trim(name) ~= "" then
                local k = tostring(i)
                keys[#keys + 1] = k
                values[k] = trim(name)
            end
        end
    end
    local cur = type(GetCurrentTitle) == "function" and GetCurrentTitle() or 0
    return keys, values, (type(cur) == "number" and cur > 0) and tostring(cur) or Menus.NONE
end

-- Your name with the title you wear, the way the game shows it. The game's
-- title text has a space on the side your name goes ("Private " or " the
-- Explorer").
function Menus.WithTitle(name)
    local cur = type(GetCurrentTitle) == "function" and GetCurrentTitle() or 0
    if type(name) ~= "string" or type(cur) ~= "number" or cur <= 0 then return name end
    local title = GetTitleName(cur)
    if type(title) ~= "string" or trim(title) == "" then return name end
    if string.sub(title, 1, 1) == " " then return name .. " " .. trim(title) end
    return trim(title) .. " " .. name
end

function Menus.PickTitle(k)
    if type(SetCurrentTitle) == "function" then SetCurrentTitle(tonumber(k)) end
end

function Menus.Titles(owner)
    local keys, values, current = Menus.TitleList()
    DUI.Widgets.OpenMenu(owner, keys, values, current, Menus.PickTitle, Menus.TITLE_W)
end
