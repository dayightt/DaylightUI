-- The title menu (click your name). Only the game's own code may call
-- SetCurrentTitle, so a click on a title goes through a secure button laid
-- over the row (Win.Caster) running the game's /settitle, as its own title
-- list does it from a click.

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char
local L = DUI.L

local Menus = {}
ns.Menus = Menus

Menus.NONE = "-1"
Menus.TITLE_W = 200
Menus.CAST = "DaylightUICharacterTitle"

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

-- The /settitle line for a choice, or nil when the game has no such command.
-- The game finds the title with a pattern from the start of its name, so the
-- name is escaped and pinned at its end: "Knight" never picks "Knight-Captain".
function Menus.Macro(k)
    local cmd = type(SLASH_SET_TITLE1) == "string" and SLASH_SET_TITLE1 or nil
    if not cmd then return nil end
    if k == Menus.NONE then return cmd end
    local name = GetTitleName(tonumber(k))
    if type(name) ~= "string" or trim(name) == "" then return nil end
    local plain = string.gsub(string.lower(trim(name)), "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    return cmd .. " " .. plain .. "$"
end

-- The menu row under the mouse, found when the title is clicked, since the
-- list may have scrolled under the secure button since it was laid there.
local function rowUnderMouse()
    local W = DUI.Widgets
    for i = 1, 40 do
        local r = W.MenuRow(i)
        if not r then return nil end
        if r:IsShown() and r:IsMouseOver() then return r end
    end
end

local caster
local function casterOf()
    if caster then return caster end
    caster = DUI.Win.Caster({ name = Menus.CAST,
        above = function() return Menus.row end,
        enter = function(row) local fn = row:GetScript("OnEnter"); if fn then fn(row) end end,
        leave = function(row) local fn = row:GetScript("OnLeave"); if fn then fn(row) end end,
        post = function(_, button)
            if button ~= "LeftButton" then return end
            DUI.Sound.Play("click")
            DUI.Widgets.CloseMenu()
        end })
    return caster
end

-- A row of the title menu got the mouse: lay the secure button over it.
local hooked = setmetatable({}, { __mode = "k" })
function Menus.Hover(k)
    local W = DUI.Widgets
    local row
    for i = 1, 40 do
        local r = W.MenuRow(i)
        if not r then break end
        if r:IsShown() and r.key == k then row = r; break end
    end
    local macro = row and Menus.Macro(k)
    if not macro then return end
    Menus.row = row
    local c = casterOf()
    if not hooked[row] then
        hooked[row] = true
        -- The menu closed under the button: take it away with the rows.
        row:HookScript("OnHide", function(self) if caster and Menus.row == self then caster.Hide() end end)
    end
    local b = c.Over(row, { type1 = "macro", macrotext1 = macro })
    if b and not b.titlePre then
        b.titlePre = true
        b:SetScript("PreClick", function(self)
            if InCombatLockdown() then return end
            local under = rowUnderMouse()
            self:SetAttribute("macrotext1", under and Menus.Macro(under.key) or nil)
            self:SetAttribute("type1", under and "macro" or nil)
        end)
    end
end

-- Reached only when the secure button wasn't there to take the click: in a
-- fight, where the game refuses a title change to addon code.
function Menus.PickTitle()
    if InCombatLockdown() and UIErrorsFrame and UIErrorsFrame.AddExternalErrorMessage then
        UIErrorsFrame:AddExternalErrorMessage(ERR_NOT_IN_COMBAT or L["Not in combat."])
    end
end

function Menus.Titles(owner)
    local keys, values, current = Menus.TitleList()
    DUI.Widgets.OpenMenu(owner, keys, values, current, Menus.PickTitle, Menus.TITLE_W, { onHover = Menus.Hover })
end
