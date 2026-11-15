-- The title menu (click your name) and the equipment sets menu (footer button).
-- The game does the real work through SetCurrentTitle and its equip-set API.

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char
local L = DUI.L

local Menus = {}
ns.Menus = Menus

Menus.NONE = "-1"
Menus.NEW = "new"
Menus.HINT = "hint"
Menus.TITLE_W, Menus.SETS_W = 200, 280
Menus.SEP = "  ·  "
Menus.NO_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

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

function Menus.SetStatus(worn, lost)
    if worn then return L["Wearing it"] end
    if (lost or 0) == 1 then return L["1 item is missing"] end
    if (lost or 0) > 1 then return string.format(L["%d items are missing"], lost) end
    return L["Ready"]
end

function Menus.SetList()
    local keys, values = {}, {}
    local C = C_EquipmentSet
    if type(C) ~= "table" or type(C.GetEquipmentSetIDs) ~= "function" then return keys, values end
    local combat = InCombatLockdown()
    for _, id in ipairs(C.GetEquipmentSetIDs() or {}) do
        local name, _, _, worn, _, _, _, lost = C.GetEquipmentSetInfo(id)
        if name then
            local k = tostring(id)
            keys[#keys + 1] = k
            values[k] = name .. Menus.SEP .. (combat and L["After combat"] or Menus.SetStatus(worn, lost))
        end
    end
    local any = #keys > 0
    if type(C.CreateEquipmentSet) == "function" then
        keys[#keys + 1] = Menus.NEW
        values[Menus.NEW] = combat and L["Save what I'm wearing (after combat)"] or L["Save what I'm wearing as a new set"]
    end
    if any then
        keys[#keys + 1] = Menus.HINT
        values[Menus.HINT] = L["Right-click a set to change it"]
    end
    return keys, values
end

-- A name no set has yet: "Set 1", "Set 2"...
function Menus.FreeName()
    local taken = {}
    for _, id in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
        taken[(C_EquipmentSet.GetEquipmentSetInfo(id))] = true
    end
    local n = 1
    while taken["Set " .. n] do n = n + 1 end
    return "Set " .. n
end

-- The game won't swap most gear in combat, so a pick made in a fight waits
-- for it to end. A later pick replaces the queued one.
function Menus.PickSet(k)
    if InCombatLockdown() then
        DUI.AfterCombat(function() Menus.PickSet(k) end, "characterSet")
        return
    end
    if k == Menus.NEW then
        C_EquipmentSet.CreateEquipmentSet(Menus.FreeName(), GetInventoryItemTexture("player", 1) or Menus.NO_ICON)
    elseif type(EquipmentManager_EquipSet) == "function" then
        EquipmentManager_EquipSet(tonumber(k))
    end
end

-- Right-click a set to save your current gear into it, rename it or delete it.
function Menus.SetActions(k)
    local id = tonumber(k)
    if not id or not C_EquipmentSet.GetEquipmentSetInfo(id) then return end
    local keys = { "save", "rename", "delete" }
    local values = {
        save = InCombatLockdown() and L["Save what I'm wearing to it (after combat)"] or L["Save what I'm wearing to it"],
        rename = L["Rename..."],
        delete = DELETE or L["Delete"],
    }
    DUI.Widgets.OpenMenu(nil, keys, values, nil, function(a) Menus.ChangeSet(id, a) end, Menus.SETS_W,
        { atCursor = true, confirm = { delete = true } })
end

-- A set keeps its icon. Saving waits for combat to end like a swap does,
-- since it reads the gear you're wearing at that point.
function Menus.ChangeSet(id, action)
    local C = C_EquipmentSet
    local name, icon = C.GetEquipmentSetInfo(id)
    if not name then return end
    if action == "save" then
        if InCombatLockdown() then
            DUI.AfterCombat(function() Menus.ChangeSet(id, action) end, "characterSetSave")
            return
        end
        C.SaveEquipmentSet(id, icon)
    elseif action == "rename" then
        DUI.Widgets.Prompt(string.format(L["Rename %s:"], name), name, function(text)
            -- Reusing another set's name would overwrite that set. The game refuses it too.
            local other = type(C.GetEquipmentSetID) == "function" and C.GetEquipmentSetID(text)
            if other and other ~= id then
                if UIErrorsFrame and UIErrorsFrame.AddExternalErrorMessage then
                    UIErrorsFrame:AddExternalErrorMessage(EQUIPMENT_SETS_CANT_RENAME or L["A set already has that name."])
                end
                return
            end
            C.ModifyEquipmentSet(id, text, icon)
        end)
    elseif action == "delete" then
        C.DeleteEquipmentSet(id)
    end
end

function Menus.Sets(owner)
    local keys, values = Menus.SetList()
    if #keys == 0 then return end
    DUI.Widgets.OpenMenu(owner, keys, values, nil, Menus.PickSet, Menus.SETS_W,
        { hints = { [Menus.HINT] = true }, onRightClick = Menus.SetActions })
end
