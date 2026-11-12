-- Skins Bagnon's bag, bank and guild bank windows, for players who use it
-- instead of Daylight UI's bags.
-- Registers a "Daylight UI" skin through Bagnon's own API (BagBrother
-- core/api/skinning.lua, Bagnon 12.1.9, `Bagnon.Skins:Register`), so players
-- can pick another in Bagnon's options at any time. It's only the default for
-- windows whose look was never picked: the default lives in Bagnon's defaults
-- table (`Bagnon.Settings.ProfileDefaults.<frame>.skin`, read through the
-- profile metatables and never saved), not in its settings.
-- A skin is a frame Bagnon creates behind each window (`template`), passed to
-- `load` and to `layout` after each layout. It gets our window shell and accent
-- line. While our skin is in use, the window's own parts are dressed too: the X,
-- title font objects, search box, top buttons, bag buttons, side tabs, and every
-- item slot after Bagnon colors it (a post-hook on its item class's
-- UpdateBorder, with quality, quest, unusable and set colors carried over to
-- our outline). After switching to another skin those parts stay ours until a
-- /reload.

local _, ns = ...
local DUI = DaylightUI
local Engine = ns.Engine
local Style = DUI.Style
local L = DUI.L

local ADDON = "Bagnon"

Engine.AddonSwitch({ key = "bagnon", addon = ADDON, label = "Bagnon",
    desc = "Its bag, bank and guild bank windows, slots and buttons. Another look can still be picked in Bagnon's own options." })

local function isTable(x) return type(x) == "table" end

local BG = {}
ns.BagnonSkin = BG
BG.ID = "DaylightUI"
BG.TEMPLATE = "BackdropTemplate" -- any template works; the frame only carries our shell
BG.ICON_PAD = 2 -- px between a top button's icon and its outline
BG.dressed = setmetatable({}, { __mode = "k" }) -- window -> true (X and title dressed)

-- Whether a Bagnon window (or part of one) is currently using our skin.
function BG.Ours(frame)
    local bg = isTable(frame) and rawget(frame, "skin")
    return isTable(bg) and isTable(bg.skin) and bg.skin.id == BG.ID
end

-- The title's font objects (a Button, so SetNormalFontObject runs on every
-- refresh), kept in sync with the font settings. Colors are set at paint time.
local fonts
local function titleFonts()
    if not fonts then
        fonts = { normal = CreateFont("DaylightUIBagnonTitle"), over = CreateFont("DaylightUIBagnonTitleOver") }
        for _, obj in pairs(fonts) do
            Style.DressText(obj, Style.SIZE.head)
            obj:SetJustifyH("LEFT")
        end
    end
    local v = Style.INK.VALUE
    fonts.normal:SetTextColor(v[1], v[2], v[3])
    local a = { Style.Accent() }
    fonts.over:SetTextColor(a[1], a[2], a[3])
    return fonts
end

-- The window's own parts, each dressed once as they appear. Bagnon creates its
-- buttons, bags and tabs when first shown.
function BG.Parts(Kit, f)
    if not BG.dressed[f] then
        BG.dressed[f] = true
        Kit.Close(f.CloseButton)
        Kit.EditBox(rawget(f, "SearchBar"))
        -- Fade in on open and leave a ghost on close, like our windows, but
        -- only while it uses our skin.
        if f.HookScript and DUI.Motion then
            f:HookScript("OnShow", function(self) if BG.Ours(self) then DUI.Motion.FadeIn(self) end end)
            f:HookScript("OnHide", function(self) if BG.Ours(self) then DUI.Motion.Ghost(self, Kit.GhostDress) end end)
        end
    end
    for _, b in ipairs(rawget(f, "MenuButtons") or {}) do Kit.IconButton(b, BG.ICON_PAD) end
    Kit.IconButton(rawget(f, "OptionsToggle"), BG.ICON_PAD)
    local bags = rawget(f, "BagGroup")
    if isTable(bags) and bags.GetChildren then
        for _, b in ipairs({ bags:GetChildren() }) do Kit.Item(b) end
    end
    local tabs = rawget(f, "TabGroup")
    if isTable(tabs) and isTable(tabs.buttons) then
        for _, t in ipairs(tabs.buttons) do
            Kit.SideTab(t, function(tab) return tab.GetChecked and tab:GetChecked() == true end)
        end
    end
end

-- An item slot after Bagnon colored it: dressed once, outlined in the color
-- Bagnon gave its border (none = the dim empty outline).
function BG.Item(Kit, btn)
    if not BG.Ours(btn.frame) then return end
    if InCombatLockdown() and btn.IsProtected and btn:IsProtected() then
        DUI.AfterCombat(function() BG.Item(Kit, btn) end, "bagnon:item")
        return
    end
    Kit.Item(btn)            -- once
    Kit.Hide(btn.IconGlow) -- our outline carries the color, so drop the glow
    Kit.SlotQuality(btn)
end

function BG.Skin(Kit)
    return {
        id = BG.ID, title = "Daylight UI", tooltip = L["The Daylight UI look."],
        template = BG.TEMPLATE,
        x = 0, y = 0, x1 = 0, y1 = 0, margin = 2, inset = 2,
        closeX = -4, closeY = -2,
        load = function(bg)
            if not BG.shells then BG.shells = setmetatable({}, { __mode = "k" }) end
            if not BG.shells[bg] then
                BG.shells[bg] = Kit.Shell(bg, "window")
                local line = bg:CreateTexture(nil, "ARTWORK")
                line:SetTexture("Interface\\Buttons\\WHITE8X8")
                line:SetHeight(DUI.Win and DUI.Win.LINE or 2)
                line:SetPoint("TOPLEFT", bg, "TOPLEFT", 6, -2)
                line:SetPoint("TOPRIGHT", bg, "TOPRIGHT", -6, -2)
                bg.dlLine = line
            end
            Style.PaintAccent(bg.dlLine, 0.7)
            titleFonts() -- re-read the accent
            local f = bg:GetParent()
            if isTable(f) then BG.Parts(Kit, f) end
        end,
        layout = function(bg)
            local f = bg:GetParent()
            if isTable(f) then BG.Parts(Kit, f) end
        end,
    }
end

-- Makes our skin the default for every Bagnon window whose look was never
-- picked. Switching it off (and reloading) leaves Bagnon's own default.
function BG.Default(B)
    local defaults = isTable(B.Settings) and B.Settings.ProfileDefaults
    if not isTable(defaults) then return end
    for _, d in pairs(defaults) do
        if isTable(d) then rawset(d, "skin", BG.ID) end
    end
end

Engine.Register({ key = "bagnon", pack = "addons", addon = ADDON, switch = "bagnon", label = "Bagnon",
    thirdParty = true, apply = function(Kit, def)
        local B = _G.Bagnon
        if not (isTable(B) and isTable(B.Skins) and type(B.Skins.Register) == "function") then return false end
        local skin = BG.Skin(Kit)
        skin.load = Engine.Safe(def, skin.load)
        skin.layout = Engine.Safe(def, skin.layout)
        -- Bagnon reads the title fonts from the skin table.
        local t = titleFonts()
        skin.font, skin.fontH = t.normal, t.over
        BG.Default(B)
        B.Skins:Register(skin)
        if isTable(B.Item) and type(B.Item.UpdateBorder) == "function" then
            hooksecurefunc(B.Item, "UpdateBorder", Engine.Safe(def, function(btn) BG.Item(Kit, btn) end))
        end
    end })
