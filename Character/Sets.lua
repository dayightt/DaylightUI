-- The equipment sets panel. It opens beside the character window, lists the
-- picked set's gear and shows it on the model. The two menus on top pick a set
-- and make or change one. The game does the saving and swapping through its
-- equipment set API.

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char
local L = DUI.L
local Style = DUI.Style

local Sets = {}
ns.Sets = Sets

Sets.NAME = "DaylightUICharacterSets"
Sets.W = 300
Sets.GAP = 6            -- between the character window and the panel
Sets.ROW_TOP = 6        -- the menus under the header
Sets.ROW_H = 26
Sets.EDIT_W = 84
Sets.MENU_W = 240
Sets.SEP = "  ·  "
Sets.NO_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
Sets.ICON_SLOTS = { 5, 1, 16 }   -- a new set takes its icon from the chest, else the head or weapon
-- What the game says about a slot of a set in place of where its item is.
Sets.MISSING, Sets.EMPTY, Sets.IGNORED = -1, 0, 1

local function api() return type(C_EquipmentSet) == "table" and C_EquipmentSet or nil end

local function refuse(text)
    if text and UIErrorsFrame and UIErrorsFrame.AddExternalErrorMessage then
        UIErrorsFrame:AddExternalErrorMessage(text)
    end
end

-- ---------------------------------------------------------------------
-- Reading sets
-- ---------------------------------------------------------------------

function Sets.Status(worn, lost)
    if worn then return L["Wearing it"] end
    if (lost or 0) == 1 then return L["1 item is missing"] end
    if (lost or 0) > 1 then return string.format(L["%d items are missing"], lost) end
    return L["Ready"]
end

function Sets.Ids()
    local C = api()
    return C and type(C.GetEquipmentSetIDs) == "function" and C.GetEquipmentSetIDs() or {}
end

local slots
local function slotKeys()
    if slots then return slots end
    slots = {}
    for _, list in ipairs({ ns.Gear.LEFT, ns.Gear.RIGHT, ns.Gear.BOTTOM, { "Ammo" } }) do
        for _, key in ipairs(list) do slots[#slots + 1] = key end
    end
    return slots
end

-- Where a set's item is right now, and its link when it's on you or in a bag.
local function locate(loc)
    if loc == Sets.MISSING then return "missing" end
    if type(loc) ~= "number" or type(EquipmentManager_GetLocationData) ~= "function" then return nil end
    local ok, d = pcall(EquipmentManager_GetLocationData, loc)
    if not ok or type(d) ~= "table" then return nil end
    if d.isBags then
        local link
        if C_Container and type(C_Container.GetContainerItemLink) == "function" and d.bag and d.slot then
            link = C_Container.GetContainerItemLink(d.bag, d.slot)
        end
        return d.isBank and "bank" or "bags", link
    end
    if d.isBank then return "bank" end
    if d.isPlayer then return "worn", d.slot and GetInventoryItemLink("player", d.slot) or nil end
end

local function itemOf(key, slot, itemID, loc)
    local e = { key = key, slot = slot, itemID = itemID, label = ns.Gear.LABEL[key] or key }
    e.where, e.link = locate(loc)
    if C_Item and type(C_Item.GetItemInfo) == "function" then
        local ok, name, link, quality, _, _, _, _, _, _, icon = pcall(C_Item.GetItemInfo, e.link or itemID)
        if ok then
            e.name, e.quality, e.icon = name, quality, icon
            e.link = e.link or link
        end
    end
    if not e.icon and C_Item and type(C_Item.GetItemIconByID) == "function" then e.icon = C_Item.GetItemIconByID(itemID) end
    return e
end

-- A set as plain data: its name, whether it's on, and its items in the
-- character window's slot order. Slots the set leaves alone are left out.
function Sets.Read(id)
    local C = api()
    if not (C and id) then return nil end
    local name, icon, _, worn, _, _, _, lost = C.GetEquipmentSetInfo(id)
    if not name then return nil end
    local set = { id = id, name = name, icon = icon, worn = worn == true, lost = lost or 0, items = {} }
    local ids = type(C.GetItemIDs) == "function" and C.GetItemIDs(id) or {}
    local where = type(C.GetItemLocations) == "function" and C.GetItemLocations(id) or {}
    for _, key in ipairs(slotKeys()) do
        local slot = ns.Gear.SlotId(key)
        local itemID = slot and ids[slot]
        -- An item id of 0 is an empty slot and 1 one the set ignores.
        if type(itemID) == "number" and itemID > Sets.IGNORED and where[slot] ~= Sets.IGNORED then
            set.items[#set.items + 1] = itemOf(key, slot, itemID, where[slot])
        end
    end
    return set
end

-- A name no set has yet: "Set 1", "Set 2"...
function Sets.FreeName()
    local taken = {}
    for _, id in ipairs(Sets.Ids()) do taken[(C_EquipmentSet.GetEquipmentSetInfo(id)) or ""] = true end
    local n = 1
    while taken[string.format(L["Set %d"], n)] do n = n + 1 end
    return string.format(L["Set %d"], n)
end

-- ---------------------------------------------------------------------
-- Changing sets
-- ---------------------------------------------------------------------

-- The game won't swap most gear in combat, so a set picked in a fight is put
-- on when it ends. A later pick replaces the waiting one.
function Sets.Equip(id)
    if InCombatLockdown() then
        DUI.AfterCombat(function() Sets.Equip(id) end, "characterSet")
        return
    end
    if type(EquipmentManager_EquipSet) == "function" then EquipmentManager_EquipSet(id) end
end

-- A save takes the slots marked as ignored at that moment, so mark the ones
-- this set already ignores (none for a new set) or a save would fill them in.
local function keepIgnored(id)
    local C = api()
    if type(C.ClearIgnoredSlotsForSave) ~= "function" then return end
    C.ClearIgnoredSlotsForSave()
    local ignored = id and type(C.GetIgnoredSlots) == "function" and C.GetIgnoredSlots(id) or nil
    for slot, on in pairs(ignored or {}) do
        if on then C.IgnoreSlotForSave(slot) end
    end
end

-- Saving reads the gear you have on at that moment, so it waits for a fight
-- to end like a swap does. The set keeps its icon.
function Sets.Save(id)
    local C = api()
    local name, icon = C.GetEquipmentSetInfo(id)
    if not name then return end
    if InCombatLockdown() then
        DUI.AfterCombat(function() Sets.Save(id) end, "characterSetSave")
        return
    end
    keepIgnored(id)
    C.SaveEquipmentSet(id, icon)
end

function Sets.AskSave(id)
    local name = api().GetEquipmentSetInfo(id)
    if not name then return end
    DUI.Widgets.Ask({ key = "characterSetSave", text = string.format(L["Save what you're wearing as %s?"], name),
        yes = SAVE or L["Save"], no = CANCEL or L["Cancel"], onYes = function() Sets.Save(id) end })
end

local function newIcon()
    for _, slot in ipairs(Sets.ICON_SLOTS) do
        local icon = GetInventoryItemTexture("player", slot)
        if icon then return icon end
    end
    return Sets.NO_ICON
end

function Sets.Create(name)
    local C = api()
    if InCombatLockdown() then
        DUI.AfterCombat(function() Sets.Create(name) end, "characterSetNew")
        return
    end
    if type(C.GetEquipmentSetID) == "function" and C.GetEquipmentSetID(name) then
        return refuse(EQUIPMENT_SETS_CANT_RENAME or L["A set already has that name."])
    end
    if type(C.GetNumEquipmentSets) == "function" and C.GetNumEquipmentSets() >= (MAX_EQUIPMENT_SETS_PER_PLAYER or 10) then
        return refuse(EQUIPMENT_SETS_TOO_MANY or L["You can't have more sets."])
    end
    keepIgnored(nil)
    Sets.wanted = name   -- shown as soon as the game has made it
    C.CreateEquipmentSet(name, newIcon())
end

function Sets.New()
    DUI.Widgets.Prompt(L["Name the new set:"], Sets.FreeName(), Sets.Create)
end

function Sets.Rename(id)
    local C = api()
    local name, icon = C.GetEquipmentSetInfo(id)
    if not name then return end
    DUI.Widgets.Prompt(string.format(L["Rename %s:"], name), name, function(text)
        -- Another set's name would overwrite that set. The game refuses it too.
        local other = type(C.GetEquipmentSetID) == "function" and C.GetEquipmentSetID(text)
        if other and other ~= id then return refuse(EQUIPMENT_SETS_CANT_RENAME or L["A set already has that name."]) end
        C.ModifyEquipmentSet(id, text, icon)
    end)
end

function Sets.Delete(id)
    if api().GetEquipmentSetInfo(id) then C_EquipmentSet.DeleteEquipmentSet(id) end
end

-- The set's icon (on the game's bars and macros): one of its own items'.
function Sets.IconMenu(owner, id)
    local set = Sets.Read(id)
    if not set then return end
    local keys, values, icons = {}, {}, {}
    for _, e in ipairs(set.items) do
        if e.icon and not icons[tostring(e.icon)] then
            local k = tostring(e.icon)
            icons[k] = e.icon
            keys[#keys + 1] = k
            values[k] = string.format("|T%s:16:16:0:0:64:64:5:59:5:59|t  %s", k, e.name or e.label)
        end
    end
    if #keys == 0 then return end
    DUI.Widgets.OpenMenu(owner, keys, values, tostring(set.icon), function(k)
        C_EquipmentSet.ModifyEquipmentSet(id, set.name, icons[k])
    end, Sets.MENU_W)
end

-- ---------------------------------------------------------------------
-- The two menus
-- ---------------------------------------------------------------------

function Sets.PickMenu(owner)
    local keys, values = {}, {}
    local combat = InCombatLockdown()
    for _, id in ipairs(Sets.Ids()) do
        local name, _, _, worn, _, _, _, lost = C_EquipmentSet.GetEquipmentSetInfo(id)
        if name then
            local k = tostring(id)
            keys[#keys + 1] = k
            values[k] = name .. Sets.SEP .. (combat and not worn and L["After combat"] or Sets.Status(worn, lost))
        end
    end
    if #keys == 0 then return end
    DUI.Widgets.OpenMenu(owner, keys, values, Sets.picked and tostring(Sets.picked) or nil,
        function(k) Sets.Pick(tonumber(k)) end, Sets.MENU_W)
end

function Sets.EditMenu(owner)
    local id = Sets.picked
    local keys, values = { "new" }, { new = L["New set from what I'm wearing"] }
    if id and api().GetEquipmentSetInfo(id) then
        for _, k in ipairs({ "save", "rename", "icon", "delete" }) do keys[#keys + 1] = k end
        values.save = L["Save what I'm wearing to it"]
        values.rename = L["Rename..."]
        values.icon = L["Change its icon"]
        values.delete = DELETE or L["Delete"]
    end
    DUI.Widgets.OpenMenu(owner, keys, values, nil, function(k)
        if k == "new" then Sets.New()
        elseif k == "save" then Sets.AskSave(id)
        elseif k == "rename" then Sets.Rename(id)
        elseif k == "icon" then Sets.IconMenu(owner, id)
        elseif k == "delete" then Sets.Delete(id) end
    end, Sets.MENU_W, { confirm = { delete = true }, more = { icon = true } })
end

-- ---------------------------------------------------------------------
-- The panel
-- ---------------------------------------------------------------------

Sets.WHERE = {
    bags = { L["Bags"], Style.INK.LABEL },
    bank = { L["Bank"], Style.INK.WARN },
    missing = { L["Missing"], Style.INK.BAD },
}

local function itemTip(b)
    local e = b.lineSpec and b.lineSpec.item
    if not e or type(GameTooltip) ~= "table" then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if e.link and type(GameTooltip.SetHyperlink) == "function" then GameTooltip:SetHyperlink(e.link)
    elseif type(GameTooltip.SetItemByID) == "function" then GameTooltip:SetItemByID(e.itemID) end
    GameTooltip:Show()
end

-- The picked set, else the one you're wearing, else the first.
function Sets.Current()
    local ids = Sets.Ids()
    local C = api()
    if Sets.wanted and C and type(C.GetEquipmentSetID) == "function" then
        local made = C.GetEquipmentSetID(Sets.wanted)
        if made then Sets.picked, Sets.wanted = made, nil end
    end
    local first, worn
    for _, id in ipairs(ids) do
        if id == Sets.picked then return id end
        first = first or id
        if not worn and select(4, C.GetEquipmentSetInfo(id)) then worn = id end
    end
    Sets.picked = worn or first
    return Sets.picked
end

function Sets.Pick(id)
    if Sets.picked == id then return end
    Sets.picked = id
    Sets.Refresh(true)
end

-- The model wears the picked set while the panel is open, and your own gear
-- again once the set is on or the panel closes.
function Sets.Preview(set)
    local Model = ns.Model
    if not (Model and Model.TryOn) then return end
    local key
    if set and not set.worn then
        key = tostring(set.id)
        for _, e in ipairs(set.items) do key = key .. ":" .. e.itemID end
    end
    if key == Sets.previewed then return end
    if Sets.previewed then Model.Redress() end
    Sets.previewed = key
    if key then
        for _, e in ipairs(set.items) do Model.TryOn(e.link or ("item:" .. e.itemID)) end
    end
end

local function statusText(set)
    local Hex = DUI.Win.Parts.Hex
    if InCombatLockdown() and not set.worn then return L["After combat"] end
    local c = (set.worn and Style.INK.GOOD) or (set.lost > 0 and Style.INK.BAD) or Style.INK.LABEL
    return Hex(c) .. Sets.Status(set.worn, set.lost) .. "|r"
end

-- lift: the picked set changed, so its lines lift in.
function Sets.Refresh(lift)
    local f = Sets.panel
    if not (f and f:IsShown()) then return end
    local set = Sets.Read(Sets.Current())
    local Parts = DUI.Win.Parts
    f.pick.SetLabel(set and set.name or L["No sets yet"])
    f.pick:SetWidth(Sets.W - 2 * DUI.Win.EDGE - Sets.EDIT_W - Parts.GAP)
    f.pick.SetOff(set == nil)
    local s = f.stack
    local at = s:Scrolled()
    s:Begin()
    if not set then
        s:Text(L["No sets yet."], { color = Style.INK.LABEL })
        s:Text(L["Save the gear you're wearing as a set, then put the whole outfit on with one click."])
    else
        s:Section(L["Gear"], { value = statusText(set) })
        for _, e in ipairs(set.items) do
            local where = Sets.WHERE[e.where]
            s:Line({ id = e.key, item = e, icon = e.icon, text = e.name or e.label, sub = e.label,
                color = e.quality and { Parts.QualityColor(e.quality) } or nil,
                value = where and where[1] or nil, valueColor = where and where[2] or nil,
                tooltip = itemTip, link = function() return e.link end })
        end
        if #set.items == 0 then s:Text(L["Nothing in this set yet."], { color = Style.INK.LABEL }) end
    end
    local pieces = s:End()
    if lift then DUI.Win.Feel.Stagger(pieces, 0) else s:ScrollTo(at) end
    local combat = InCombatLockdown()
    f.foot:Set({
        { text = combat and L["Equip after combat"] or (EQUIPSET_EQUIP or L["Equip"]), primary = true,
          off = not set or set.worn, onClick = function() Sets.Equip(set.id) end },
        { text = SAVE or L["Save"], off = not set, onClick = function() Sets.AskSave(set.id) end },
    })
    Sets.Preview(set)
end

Sets.EVENTS = { "EQUIPMENT_SETS_CHANGED", "EQUIPMENT_SWAP_FINISHED", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED",
    "GET_ITEM_INFO_RECEIVED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }

function Sets.Build()
    if Sets.panel then return Sets.panel end
    local win, Win, W = ns.window, DUI.Win, DUI.Widgets
    local f = CreateFrame("Frame", Sets.NAME, win)
    Sets.panel = f
    f:SetSize(Sets.W, ns.Window.H)
    f:EnableMouse(true)
    f:Hide()
    Style.Shell(f, { window = "Character" })
    Win.Header(f, { compact = true, onClose = Sets.Close })
    f.title:SetText(L["Equipment sets"])
    local E = Win.EDGE
    local top = Win.COMPACT + Sets.ROW_TOP
    f.edit = W.MenuButton(f, EDIT or L["Edit"], Sets.ROW_H)
    f.edit:SetWidth(Sets.EDIT_W)
    f.edit:SetPoint("TOPRIGHT", f, "TOPRIGHT", -E, -top)
    f.edit:SetScript("OnClick", function(self) Sets.EditMenu(self) end)
    f.pick = W.MenuButton(f, "", Sets.ROW_H)
    f.pick:SetPoint("TOPLEFT", f, "TOPLEFT", E, -top)
    f.pick.text:SetPoint("RIGHT", f.pick.chevron, "LEFT", -6, 0)
    f.pick.text:SetWordWrap(false)
    f.pick:SetScript("OnClick", function(self) Sets.PickMenu(self) end)
    f.stack = Win.Parts.Stack(f, { top = top + Sets.ROW_H + 10, bottom = 58 })
    f.foot = Win.Parts.Footer(f, { equal = true })
    local soon = DUI.Soon(function() Sets.Refresh() end)
    f:SetScript("OnEvent", soon)
    f:SetScript("OnShow", function(self)
        for _, e in ipairs(Sets.EVENTS) do pcall(self.RegisterEvent, self, e) end
    end)
    f:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        Sets.Preview(nil)
    end)
    return f
end

-- To the right of the character window, or to its left when the screen ends there.
function Sets.Place()
    local f, win = Sets.panel, ns.window
    f:ClearAllPoints()
    local right, scale = win:GetRight(), win:GetEffectiveScale()
    local screen = (UIParent:GetRight() or 0) * (UIParent:GetEffectiveScale() or 1)
    if type(right) == "number" and type(scale) == "number" and screen > 0
        and (right + Sets.GAP + Sets.W) * scale > screen then
        f:SetPoint("TOPRIGHT", win, "TOPLEFT", -Sets.GAP, 0)
    else
        f:SetPoint("TOPLEFT", win, "TOPRIGHT", Sets.GAP, 0)
    end
end

function Sets.IsOpen()
    return Sets.panel ~= nil and DUI.Win.Feel.IsOpen(Sets.panel)
end

function Sets.Open()
    if not ns.window or Sets.IsOpen() then return end
    local f = Sets.Build()
    Sets.Place()
    DUI.Sound.Play("open")
    DUI.Win.Feel.Open(f)
    Sets.Refresh(true)
end

function Sets.Close()
    if not Sets.IsOpen() then return end
    DUI.Widgets.CloseMenu()
    DUI.Win.Shut(Sets.panel)
end

function Sets.Toggle()
    if Sets.IsOpen() then Sets.Close() else Sets.Open() end
end

-- The character window closed or left the Character page: gone at once, so
-- it never comes back by itself with the window.
function Sets.Hide()
    local f = Sets.panel
    if not (f and f:IsShown()) then return end
    DUI.Win.Feel.Settle(f)
    f:Hide()
end

DUI.On("CharacterWindowClosed", function() Sets.Hide() end)
