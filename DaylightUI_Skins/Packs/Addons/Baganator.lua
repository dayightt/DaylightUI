-- Skins Baganator's bag, bank, guild bank and settings windows, for players who
-- use it instead of Daylight UI's bags.
-- Uses Baganator's public skin API (API/Main.lua, Skins/*.lua, version 834).
-- Every piece it creates goes through `Baganator.Skins.AddFrame(regionType,
-- region, tags)`, which hands it to the current skin and then to each listener
-- (`Baganator.API.Skins.RegisterListener`). Pieces made before we registered
-- are in `Baganator.API.Skins.GetAllFrames()`. We only dress while Baganator's
-- default look ("blizzard") is selected; any other look the player picks in its
-- options (Dark, ElvUI, EllesmereUI...) is left alone. No hooks.
-- Region types (see its Skins/EllesmereUI.lua): ButtonFrame a window
-- (ButtonFrameTemplate), ItemButton a slot (tag "containerBag" = a bag), Button
-- a text button, IconButton, SearchBox and EditBox, TabButton / TopTabButton
-- (selected = disabled), SideTabButton, CheckBox, InsetFrame, Dropdown,
-- TrimScrollBar, Dialog, CategoryLabel and CategorySectionHeader (category
-- view headings).

local _, ns = ...
local DUI = DaylightUI
local Engine = ns.Engine
local Style = DUI.Style

local ADDON = "Baganator"

Engine.AddonSwitch({ key = "baganator", addon = ADDON, label = "Baganator",
    desc = "Its bag, bank and guild bank windows, slots, buttons and settings, while its own Blizzard look is picked." })

local function isTable(x) return type(x) == "table" end

local BZ = {}
ns.BaganatorSkin = BZ
BZ.LOOK = "blizzard" -- Baganator's default look, the one we dress over
BZ.ICON_PAD = 2 -- px between an icon button's icon and its outline

-- Whether Baganator is using its default look, the one we dress over.
function BZ.Ours()
    local api = isTable(_G.Baganator) and _G.Baganator.API
    local skins = isTable(api) and api.Skins
    if not (isTable(skins) and type(skins.GetCurrentSkin) == "function") then return false end
    return skins.GetCurrentSkin() == BZ.LOOK
end

local function fontOf(b)
    if not isTable(b) then return nil end
    if b.GetObjectType and b:GetObjectType() == "FontString" then return b end
    return b.GetFontString and b:GetFontString() or nil
end

function BZ.Dressers(Kit)
    return {
        ButtonFrame = function(f) Kit.Window(f) end,
        Dialog = function(f) Kit.Window(f) end,
        ItemButton = function(b)
            Kit.Item(b)
            Kit.Erase(b.SlotBackground) -- slot art replaced by our dark square
        end,
        Button = function(b) Kit.Button(b) end,
        IconButton = function(b) Kit.IconButton(b, BZ.ICON_PAD) end,
        SearchBox = function(eb) Kit.EditBox(eb) end,
        EditBox = function(eb) Kit.EditBox(eb) end,
        TabButton = function(t) Kit.Tab(t, function(tab) return not tab:IsEnabled() end) end,
        TopTabButton = function(t) Kit.Tab(t, function(tab) return not tab:IsEnabled() end) end,
        SideTabButton = function(t) Kit.SideTab(t) end,
        CheckBox = function(cb) Kit.Check(cb) end,
        InsetFrame = function(f) Kit.Inset(f) end,
        Dropdown = function(dd) Kit.Dropdown(dd) end,
        TrimScrollBar = function(bar) Kit.ScrollBar(bar) end,
        CategoryLabel = function(b) Kit.Font(fontOf(b), Style.SIZE.small, Style.INK.LABEL) end,
        CategorySectionHeader = function(b) Kit.Font(fontOf(b), Style.SIZE.small, Style.INK.LABEL) end,
    }
end

-- Dresses one piece by its kind. A slot created in combat on a protected
-- button waits until combat ends.
function BZ.Dress(Kit, details)
    if not isTable(details) or not isTable(details.region) or not BZ.Ours() then return end
    local fn = BZ.dressers and BZ.dressers[details.regionType]
    if not fn then return end
    local r = details.region
    if InCombatLockdown() and r.IsProtected and r:IsProtected() then
        DUI.AfterCombat(function() BZ.Dress(Kit, details) end, "baganator:" .. tostring(r))
        return
    end
    fn(r)
end

Engine.Register({ key = "baganator", pack = "addons", addon = ADDON, switch = "baganator", label = "Baganator",
    thirdParty = true, apply = function(Kit, def)
        local api = isTable(_G.Baganator) and _G.Baganator.API
        local skins = isTable(api) and api.Skins
        if not (isTable(skins) and type(skins.RegisterListener) == "function") then return false end
        BZ.dressers = BZ.Dressers(Kit)
        local dress = Engine.Safe(def, function(details) BZ.Dress(Kit, details) end)
        skins.RegisterListener(dress)
        if type(skins.GetAllFrames) == "function" then
            for _, details in ipairs(skins.GetAllFrames() or {}) do dress(details) end
        end
    end })
