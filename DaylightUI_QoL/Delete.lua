-- Fills in "DELETE" when you destroy a good item. The player still presses the button.

local _, ns = ...

local Delete = {}
ns.Delete = Delete
ns.features[#ns.features + 1] = Delete

local WHICH = { DELETE_GOOD_ITEM = true, DELETE_GOOD_QUEST_ITEM = true }
local mod, hooked

local function findDialog(which)
    if type(StaticPopup_FindVisible) == "function" then
        local ok, d = pcall(StaticPopup_FindVisible, which)
        if ok and type(d) == "table" then return d end
    end
    for i = 1, 4 do
        local d = _G["StaticPopup" .. i]
        if type(d) == "table" and d.which == which then return d end
    end
end

local function findEditBox(dialog)
    if type(dialog.editBox) == "table" then return dialog.editBox end
    if type(dialog.GetEditBox) == "function" then
        local ok, e = pcall(dialog.GetEditBox, dialog)
        if ok and type(e) == "table" then return e end
    end
    local name = type(dialog.GetName) == "function" and dialog:GetName()
    local e = name and _G[name .. "EditBox"]
    if type(e) == "table" then return e end
end

local function onShow(which)
    if not (mod and mod.db and mod.db.autoDelete == true) then return end
    if not WHICH[which] then return end
    local dialog = findDialog(which)
    local box = dialog and findEditBox(dialog)
    if box and type(box.SetText) == "function" and type(DELETE_ITEM_CONFIRM_STRING) == "string" then
        box:SetText(DELETE_ITEM_CONFIRM_STRING)
    end
end

function Delete.Enable(m)
    mod = m
    if hooked or type(StaticPopup_Show) ~= "function" then return end
    hooked = true
    hooksecurefunc("StaticPopup_Show", onShow)
end

function Delete.Refresh(m) mod = m end
