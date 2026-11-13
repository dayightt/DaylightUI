-- The viewer: your bank away from a banker, and your other characters' bags and
-- banks, from saved data (Saved.lua). It's the bag window again (Window.Create,
-- same grid, groups and search) but display only. Its slots are plain item
-- buttons (tooltip, Shift-click to link), never the game's bag buttons, since
-- none of those items can actually be reached.
--
-- Tabs in the title bar (Bags for another character, Bank, Account), character
-- picker beside the search. Opened from the bag portrait's right-click menu or /dui bank.
-- Turning viewer.enabled off takes Alts off that menu and stops saving; what's
-- saved stays for when it's back on.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Viewer = {}
ns.Viewer = Viewer

Viewer.NAME = "DaylightUIBagViewer"
Viewer.DEFAULT_POINT = { "TOP", "TOP", 0, -120 }
Viewer.CHARS_ICON = "ui-data-social.png"
Viewer.EMPTY_H = 20          -- room for the "nothing saved yet" line

Viewer.who = nil             -- shown character, "Name-Realm"
Viewer.part = "bank"         -- "bags", "bank" or "account"

local Saved = ns.Saved

-- On unless switched off (Bags > Bank and alts).
function Viewer.On()
    local db = ns.module and ns.module.db
    local v = db and db.viewer
    return not (type(v) == "table" and v.enabled == false)
end

-- Display-only slot: item tooltip, Shift/Ctrl-click to link or try on (the
-- game's HandleModifiedItemClick). Scripts are set before Items.Dress hooks them.
local function infoOf(btn)
    local holder = btn:GetParent()
    return ns.Items.InfoAt(holder and holder:GetID(), btn:GetID())
end

local function makeSlot(holder)
    local btn = CreateFrame("ItemButton", nil, holder)
    btn:SetScript("OnEnter", function(self)
        local info = infoOf(self)
        if not (info and info.hyperlink) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, info.hyperlink)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnClick", function(self)
        local info = infoOf(self)
        if info and info.hyperlink and type(HandleModifiedItemClick) == "function" then
            pcall(HandleModifiedItemClick, info.hyperlink)
        end
    end)
    return btn
end

Viewer.set = ns.Bags.NewSet(Saved.List, makeSlot)

-- What's shown

local function own() return DUI.DB.CharKey() end

-- Which parts a character has. The current character has no Bags tab, the bag window is that.
local function parts(key)
    local inv = Saved.Of(key)
    return {
        bags = key ~= own() and inv ~= nil and inv.bags ~= nil,
        bank = true,
        account = Saved.Account() ~= nil,
    }
end

local function containers(key, part)
    if part == "account" then
        local a = Saved.Account()
        return a and a.tabs
    end
    local inv = Saved.Of(key)
    return inv and inv[part]
end

local function nameOf(key) return (key or ""):match("^(.-)%-") or key or "" end

local function paintTabs(f)
    local has = parts(Viewer.who)
    for _, t in ipairs(f.viewTabs or {}) do
        t:SetShown(has[t.part] == true)
        t.Pick(t.part == Viewer.part, true)
    end
end

local function paintTitle(f)
    local inv = Saved.Of(Viewer.who)
    f.title:SetText(nameOf(Viewer.who))
    f.title:SetTextColor(DUI.Style.ClassTextColor(inv and inv.class))
    -- Their class icon in the portrait, the bag's own icon when it is unknown.
    local file, l, r, t, b
    if DUI.ClassIcon and inv and type(inv.class) == "string" then file, l, r, t, b = DUI.ClassIcon(inv.class) end
    if file then ns.Window.SetPortrait(f, file, l, r, t, b) else ns.Window.SetPortrait(f, ns.Window.BAGS_ICON) end
end

-- Repaint the picked tab right away when the accent changes.
DUI.On("StyleChanged", function()
    if Viewer.window then paintTabs(Viewer.window) end
end)

-- Shows a character's part (key nil = current character; part nil = the one
-- already shown, or the bank if that character doesn't have it).
function Viewer.Show(key, part)
    local f = Viewer.window
    if not f then return end
    Viewer.who = key or Viewer.who or own()
    part = part or Viewer.part
    if not parts(Viewer.who)[part] then part = "bank" end
    Viewer.part = part
    Saved.Show(containers(Viewer.who, part))
    paintTabs(f)
    f.empty:SetText(part == "bags" and string.format(L["Nothing saved yet: log in on %s once."], nameOf(Viewer.who))
        or (Viewer.who == own() or part == "account") and L["Nothing saved yet: visit a banker once."]
        or string.format(L["Nothing saved yet: visit a banker on %s once."], nameOf(Viewer.who)))
    -- On open, glide from the old size to the new one (Feel.Size) instead of
    -- jumping. The grid hangs from the top left, so nothing inside moves.
    local open = DUI.Motion.Shown(f)
    local w0, h0 = f:GetWidth(), f:GetHeight()
    ns.Window.Relayout(f)
    ns.Window.FillAll(f)
    if open then
        local w, h = f:GetWidth(), f:GetHeight()
        f:SetSize(w0, h0)
        DUI.Win.Feel.Size(f, w, h)
    end
end

function Viewer.Open(key, part)
    local f = Viewer.window
    if not f then return end
    Viewer.Show(key, part)
    f:Show()
end

function Viewer.Toggle()
    local f = Viewer.window
    if not f then return end
    if DUI.Motion.Shown(f) then Viewer.Close()
    elseif Viewer.On() then Viewer.Open()
    else DUI.Print(L["Bank and alts is off. Turn it on in Bags > Bank and alts."]) end
end

-- Toggles the current character's bank in one click (right-click the bag's
-- title bar or its chest button, like Bagnon).
function Viewer.ToggleBank()
    local f = Viewer.window
    if not f then return end
    if DUI.Motion.Shown(f) and Viewer.who == own() and Viewer.part == "bank" then Viewer.Close()
    elseif Viewer.On() then Viewer.Open(own(), "bank")
    else DUI.Print(L["Bank and alts is off. Turn it on in Bags > Bank and alts."]) end
end

-- The portrait menu's Bank: the live bank at a banker, else the saved one here.
function Viewer.OpenBank()
    local bank = ns.Bank
    if bank and bank.open and bank.window then bank.Open()
    elseif Viewer.On() then Viewer.Open(own(), "bank")
    else DUI.Print(L["Bank and alts is off. Turn it on in Bags > Bank and alts."]) end
end

-- The portrait menu's Alts: the character already shown, else the first other one
-- with bags saved; your own bank when there is nobody else.
function Viewer.OpenAlts()
    if not Viewer.On() then return end
    local key = Viewer.who
    if not (key and key ~= own() and parts(key).bags) then
        key = nil
        for _, c in ipairs(Saved.Characters()) do
            if not c.own and type(c.inv) == "table" and c.inv.bags then key = c.key break end
        end
    end
    if key then Viewer.Open(key, "bags") else Viewer.Open(own(), "bank") end
end

-- Closes the window when the viewer is switched off. The bag's portrait menu
-- asks Viewer.On each time it opens, so Alts leaves it by itself.
function Viewer.Sync()
    local on = Viewer.On()
    if not on and Viewer.window and DUI.Motion.Shown(Viewer.window) then Viewer.Close() end
end

function Viewer.Close()
    local f = Viewer.window
    if not f then return end
    if DUI.Motion then DUI.Motion.Vanish(f) else f:Hide() end
end

-- The shown character was removed (DUI.Alts): go back to the current character's bank.
DUI.On("CharacterForgotten", function(key)
    if Viewer.who == key then Viewer.Show(own(), "bank") end
end)

-- A bank was just saved while on screen: refresh it.
DUI.On("BagsSaved", function()
    local f = Viewer.window
    if f and f:IsShown() and Viewer.part ~= "bags" and (Viewer.part == "account" or Viewer.who == own()) then
        Viewer.Show()
    end
end)

-- The window

-- Title bar tabs, right of the title and left of the X (same as the bank).
local function makeTabs(f)
    f.viewTabs = {}
    local right = f.close
    local defs = { { L["Bags"], "bags" }, { L["Bank"], "bank" }, { L["Account"], "account" } }
    for i = #defs, 1, -1 do
        local t = DUI.Widgets.Tab(f, defs[i][1], { size = ns.Window.TEXT_SIZE })
        t.part = defs[i][2]
        t:SetHeight(DUI.Widgets.TAB_H)
        t.FitWidth()
        t:SetPoint("RIGHT", right, "LEFT", -DUI.Win.TAB_GAP, 0)
        t:SetScript("OnClick", function(self) Viewer.Show(nil, self.part) end)
        table.insert(f.viewTabs, 1, t)
        right = t
    end
    f.title:SetPoint("RIGHT", right, "LEFT", -8, 0)
    f.sub:SetPoint("RIGHT", right, "LEFT", -8, 0)
    f.handle:ClearAllPoints()
    f.handle:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.handle:SetPoint("RIGHT", right, "LEFT", -4, 0)
    f.handle:SetHeight(ns.Window.TITLE)
end

-- Character picker: every character with something saved, in class color,
-- with the realm shown for other realms.
function Viewer.PickMenu(owner)
    local keys, values = {}, {}
    local here = (own() or ""):match("%-(.*)$")
    for _, c in ipairs(Saved.Characters()) do
        local r, g, b = DUI.Style.ClassTextColor(c.class)
        local name = c.realm ~= here and (c.name .. " - " .. c.realm) or c.name
        keys[#keys + 1] = c.key
        values[c.key] = DUI.Win.Parts.Hex({ r, g, b }) .. name .. "|r"
    end
    local more
    if #DUI.Alts.List() > 0 then
        keys[#keys + 1] = "remove"
        values.remove = L["Remove a character"]
        more = { remove = true }
    end
    DUI.Widgets.OpenMenu(owner, keys, values, Viewer.who, function(key)
        if key == "remove" then DUI.Alts.Menu(owner) else Viewer.Show(key) end
    end, nil, { more = more })
end

-- When the shown part was last seen, as a time ago.
local function seenOf(inv)
    if Viewer.part == "account" then
        local a = Saved.Account()
        return a and a.time
    end
    return inv and (Viewer.part == "bank" and inv.bankTime or inv.time)
end

-- Sub line under the character's name: when this was saved.
local function updateSub(f)
    local seen = seenOf(Saved.Of(Viewer.who))
    local ago = DUI.Social and DUI.Social.Data and DUI.Social.Data.Ago
    if #Saved.view > 0 and type(seen) == "number" and ago and time then
        f.sub:SetText(string.format(L["Saved %s"], ago(math.max(0, time() - seen))))
    else
        f.sub:SetText("")
    end
end

-- Footer: the matching gold (the character's or the account bank's). When it
-- was saved sits in the sub line.
local function updateFooter(f)
    local inv = Saved.Of(Viewer.who)
    local money
    if Viewer.part == "account" then
        local a = Saved.Account()
        money = a and a.money
    else
        money = Viewer.who == own() and GetMoney and GetMoney() or inv and inv.money
    end
    if #Saved.view == 0 then f.free:SetText("") end
    f.money:SetText(type(money) == "number" and DUI.Widgets.Money(money) or "")
end

function Viewer.Build()
    local W = ns.Window
    local f = W.Create({
        kind = "viewer", name = Viewer.NAME, title = "Bank and alts", set = Viewer.set, prefix = "viewer.",
        defaultPoint = Viewer.DEFAULT_POINT, still = true,
        onClose = function() Viewer.Close() end,
        updateFooter = updateFooter, updateSub = updateSub,
        portrait = ns.Window.BAGS_ICON,
        afterLayout = function(w)
            -- After a repaint too, which resets the title to white.
            paintTitle(w)
            -- Nothing saved: one line where the slots would be.
            local none = #Saved.view == 0
            DUI.Motion.AlphaTo(w.empty, none and 1 or 0, DUI.Motion.FAST, true)
            if none then
                w.items:SetHeight(Viewer.EMPTY_H)
                w:SetHeight(w:GetHeight() + Viewer.EMPTY_H)
            end
        end,
        tools = {
            { key = "charsButton", icon = Viewer.CHARS_ICON, title = L["Characters"],
              desc = L["See another character's bags and bank."],
              onClick = function(w) Viewer.PickMenu(w.charsButton) end },
            { key = "viewButton", icon = W.VIEW_ICON, title = L["Shelf or grid"],
              desc = L["Switch between Shelf, grouped by kind, and Grid, bag by bag."],
              onClick = function(w) w.Set("view", w.Setting("view") == "categories" and "grid" or "categories") end },
        },
    })
    Viewer.window = f
    f.empty = DUI.Style.Text(f.items, DUI.Style.SIZE.body, "LEFT")
    f.empty:SetPoint("TOPLEFT", f.items, "TOPLEFT", 0, -2)
    DUI.Style.InkText(f.empty, "LABEL")
    f.empty:Hide()
    makeTabs(f)
    Viewer.Show(own(), "bank")
    Viewer.Sync()
    if not DUI.HasCommand("bank") then
        DUI.RegisterCommand("bank", function() Viewer.Toggle() end, L["/dui bank - your bank and your other characters' bags, anywhere"])
    end
end
