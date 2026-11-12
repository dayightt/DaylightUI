-- The game's micro menu and bag bar in the action buttons' look (a setting, on by
-- default; a reload switches it). The buttons stay the game's (keybinds, tooltips,
-- alerts); only their art changes.
--   * Micro buttons: a shell frames one of our line icons
--     (tools/make_micro_icons.py), painted along the accent so the whole row is one
--     sweep (a single-color accent is just that color). The game's art is cut away
--     by a mask, which also covers whatever atlas or alpha the game sets later.
--   * Bag buttons: the slot art goes, the icon fills the shell square, and an open
--     bag gets the accent over its icon. The bar's dividers are hidden.
-- Nothing is stored on the buttons and none of their methods are hooked. The game's
-- art is followed through global post-hooks and script hooks. Done out of combat.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style

local Menus = {}
ns.Menus = Menus

Menus.MICRO = {
    "CharacterMicroButton", "ProfessionMicroButton", "PlayerSpellsMicroButton", "SpellbookMicroButton",
    "TalentMicroButton", "AchievementMicroButton", "LegacyMicroButton", "QuestLogMicroButton",
    "HousingMicroButton", "GuildMicroButton", "LFDMicroButton", "CollectionsMicroButton",
    "EJMicroButton", "HelpMicroButton", "StoreMicroButton", "MainMenuMicroButton",
}
-- Each button's icon: Media/ui-micro-<name>.png.
Menus.ICONS = {
    CharacterMicroButton = "character", ProfessionMicroButton = "professions",
    PlayerSpellsMicroButton = "talents", SpellbookMicroButton = "spellbook",
    TalentMicroButton = "talents", AchievementMicroButton = "achievements",
    LegacyMicroButton = "legacy", QuestLogMicroButton = "quests", HousingMicroButton = "housing",
    GuildMicroButton = "guild", LFDMicroButton = "finder", CollectionsMicroButton = "collections",
    EJMicroButton = "journal", HelpMicroButton = "help", StoreMicroButton = "shop",
    MainMenuMicroButton = "menu",
}
-- Micro button art that's removed: the plate, pressed or not, and the character
-- portrait's shadows (the game only shows and hides these).
Menus.MICRO_ART = { "Background", "PushedBackground", "Shadow", "PushedShadow" }
-- What the mask cuts away besides the button's four state textures. The game sets
-- these again when a button is pressed or a pulse runs.
Menus.MICRO_CUT = { "Portrait", "Emblem", "HighlightEmblem", "FlashContent" }
-- How far in from a micro button's edge the shell sits (x, y).
Menus.MICRO_INSET = { 3, 3 }
Menus.MICRO_ICON = 18
Menus.MICRO_PRESS = 0.88       -- icon scale when pressed
Menus.NEWS_DOT = 7             -- size of the news dot (replaces the game's diamond)
Menus.LATENCY_W, Menus.LATENCY_H = 16, 2    -- the game menu button's latency line
Menus.BAGS = {
    "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
    "CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton",
}
-- The bars' frame art behind the buttons.
Menus.BAR_ART = { MicroMenu = { "BorderArt", "BackgroundArt" }, BagsBar = { "BorderArt" } }
Menus.OPEN_ALPHA = 0.3      -- accent alpha over an open bag's icon

local skinned = setmetatable({}, { __mode = "k" })     -- button -> its parts

local function fade(tex)
    if type(tex) == "table" and tex.SetAlpha then tex:SetAlpha(0) end
end

-- ---------------------------------------------------------------------
-- The micro row. Each shown button holds its slice of the accent so the sweep runs
-- through the icons from first to last. With two rows (Edit Mode's stacked menu)
-- each row runs the whole sweep, and a vertical menu runs top to bottom. Slices are
-- computed when something changes, never per frame.
-- ---------------------------------------------------------------------

-- The shown buttons, in the game's order (it numbers the ones it put in the menu).
local function shownMicro()
    local list = {}
    for _, name in ipairs(Menus.MICRO) do
        local btn = _G[name]
        if type(btn) == "table" and skinned[btn] and type(btn.layoutIndex) == "number"
            and btn:IsShown() then
            list[#list + 1] = btn
        end
    end
    table.sort(list, function(a, b) return a.layoutIndex < b.layoutIndex end)
    return list
end

-- A button's icon: its slice of the accent, lifted toward white by p (hovered, or
-- its window open), or dimmed while the game has it locked.
local function paintIcon(parts, p)
    parts.lift = p
    local icon, hi = parts.icon, Style.INK.VALUE
    local function mix(c)
        return CreateColor(c[1] + (hi[1] - c[1]) * p, c[2] + (hi[2] - c[2]) * p, c[3] + (hi[3] - c[3]) * p, 1)
    end
    local a, b = parts.from, parts.to
    if parts.locked then a, b = Style.INK.OFF, Style.INK.OFF end
    icon:SetVertexColor(1, 1, 1, 1)
    if parts.standing then
        icon:SetGradient("VERTICAL", mix(b), mix(a))    -- the bottom is the later end
    else
        icon:SetGradient("HORIZONTAL", mix(a), mix(b))
    end
end

-- Eases a button to what it should show now.
local function settle(btn)
    local parts = skinned[btn]
    if not parts or not parts.from then return end
    local open = btn:GetButtonState() == "PUSHED"
    parts.locked = not btn:IsEnabled()
    if open ~= parts.open then
        parts.open = open
        if open then
            Style.LightShell(parts.shell)
        else
            Style.SetShellColors(parts.shell, parts.rest[1], parts.rest[2], parts.rest[3])
        end
    end
    local to = (open or btn:IsMouseOver()) and not parts.locked and 1 or 0
    -- Motion paints at once when there's nothing to ease, so a new slice shows too.
    local M = DUI.Motion
    M.Tween(parts.icon, parts.lift, to, M.FAST, function(p) paintIcon(parts, p) end)
end

-- Paints the sweep over the row as it stands, each button's state, and the two
-- accent pieces. Also runs after a style change.
function Menus.PaintMicro()
    local list, bar = shownMicro(), _G.MicroMenu
    local standing = type(bar) == "table" and bar.isHorizontal == false
    local per = #list
    if type(bar) == "table" and bar.isStacked then per = math.ceil(per / 2) end
    local function at(t) return { Style.AccentAt(t) } end
    for i, btn in ipairs(list) do
        local spot = (i - 1) % per
        local parts = skinned[btn]
        parts.from, parts.to = at(spot / per), at((spot + 1) / per)
    end
    for _, name in ipairs(Menus.MICRO) do
        local btn = _G[name]
        local parts = type(btn) == "table" and skinned[btn]
        if parts then
            if not parts.from then parts.from, parts.to = at(0), at(1) end
            parts.standing = standing
            parts.open = nil        -- a style change rebuilt the shell's colors
            settle(btn)
            if parts.flash then Style.PaintAccent(parts.flash) end
            if parts.dot then Style.PaintAccent(parts.dot) end
        end
    end
end

local followingMicro = false
local function followMicro()
    if followingMicro then return end
    followingMicro = true
    -- The game's own pass over every button: a window opened or closed, a button
    -- shown or locked.
    if type(_G.UpdateMicroButtons) == "function" then
        hooksecurefunc("UpdateMicroButtons", function() Menus.PaintMicro() end)
    end
    -- Edit Mode rotated or stacked the menu; repaint after it has laid it out.
    pcall(DUI.RegisterEvent, "EDIT_MODE_LAYOUTS_UPDATED", function() C_Timer.After(0, Menus.PaintMicro) end)
end

-- A micro button: the shell on a box inside it, our icon on that, and the game's art
-- masked away (the mask sits off the button, so all of the art is outside it).
function Menus.SkinMicro(btn, name)
    if type(btn) ~= "table" or skinned[btn] or (btn.IsForbidden and btn:IsForbidden()) then return end
    local parts = { lift = 0 }
    skinned[btn] = parts
    for _, k in ipairs(Menus.MICRO_ART) do fade(btn[k]) end
    local x, y = Menus.MICRO_INSET[1], Menus.MICRO_INSET[2]
    local box = CreateFrame("Frame", nil, btn)
    box:SetPoint("TOPLEFT", btn, "TOPLEFT", x, -y)
    box:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -x, y)
    box:SetFrameLevel(math.max(0, btn:GetFrameLevel() - 1))
    parts.box = box
    parts.shell = Style.Shell(box, ns.Skin.SharedShellOpts())
    local o = parts.shell.opts
    parts.rest = { o.borderColor, o.bandColor, o.borderPair }

    local mask = btn:CreateMaskTexture()
    mask:SetTexture("Interface\\Buttons\\WHITE8X8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetSize(1, 1)
    mask:SetPoint("BOTTOMRIGHT", btn, "TOPLEFT", -8, 8)
    parts.mask = mask
    -- The same texture objects stay when the game sets another atlas on them (a
    -- pressed button, the guild tabard colors), so the mask stays too.
    local gone = { btn:GetNormalTexture(), btn:GetPushedTexture(), btn:GetDisabledTexture(), btn:GetHighlightTexture() }
    for _, k in ipairs(Menus.MICRO_CUT) do gone[#gone + 1] = btn[k] end
    for i = 1, #gone do
        local t = gone[i]
        if type(t) == "table" and t.AddMaskTexture then t:AddMaskTexture(mask) end
    end

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(DUI.MEDIA .. "ui-micro-" .. (Menus.ICONS[name] or "menu") .. ".png")
    icon:SetSize(Menus.MICRO_ICON, Menus.MICRO_ICON)
    icon:SetPoint("CENTER", box, "CENTER", 0, 0)
    parts.icon = icon

    -- A game alert's pulse: its own art, in the accent, around the shell.
    local flash = btn.FlashBorder
    if type(flash) == "table" and flash.SetDesaturated then
        flash:SetDesaturated(true)
        flash:ClearAllPoints()
        flash:SetAllPoints(box)
        parts.flash = flash
    end
    -- News: the game's diamond becomes a small dot on the shell's corner.
    local news = btn.NotificationOverlay
    local dot = type(news) == "table" and news.GetRegions and news:GetRegions()
    if type(dot) == "table" and dot.SetTexture then
        dot:SetTexture(DUI.MEDIA .. "ui-round.png")
        dot:SetTexCoord(0, 1, 0, 1)
        dot:SetSize(Menus.NEWS_DOT, Menus.NEWS_DOT)
        dot:ClearAllPoints()
        dot:SetPoint("CENTER", box, "TOPRIGHT", -1, -1)
        parts.dot = dot
    end
    -- The game menu's latency line, thin, inside the shell (its color stays the game's).
    local line = btn.MainMenuBarPerformanceBar
    if type(line) == "table" and line.SetColorTexture then
        line:SetColorTexture(1, 1, 1, 1)
        line:SetSize(Menus.LATENCY_W, Menus.LATENCY_H)
        line:ClearAllPoints()
        line:SetPoint("BOTTOM", box, "BOTTOM", 0, 3)
    end

    if btn.HookScript then
        local function now() settle(btn) end
        btn:HookScript("OnEnter", now)
        btn:HookScript("OnLeave", now)
        btn:HookScript("OnEnable", now)
        btn:HookScript("OnDisable", now)
        btn:HookScript("OnMouseDown", function()
            if btn:IsEnabled() then
                DUI.Motion.Bump(icon, Menus.MICRO_PRESS)
                settle(btn)
            end
        end)
        -- The client releases the pressed state after this script.
        btn:HookScript("OnMouseUp", function() C_Timer.After(0, now) end)
    end
    followMicro()
end

-- An open bag's accent, applied after the game has put its own art back.
local function bagArt(btn)
    local parts = skinned[btn]
    if not parts then return end
    fade(btn:GetNormalTexture())
    fade(btn:GetPushedTexture())
    fade(btn:GetHighlightTexture())
    local open = btn.SlotHighlightTexture
    if type(open) == "table" and open.SetColorTexture then
        open:SetColorTexture(1, 1, 1, 1)
        Style.PaintAccent(open, Menus.OPEN_ALPHA)
        open:ClearAllPoints()
        open:SetAllPoints(btn)
    end
    -- An item's icon is cropped like the action buttons'. An atlas icon (the empty
    -- key ring) can't be, since its coordinates are the atlas's.
    local icon = btn.icon or btn.Icon
    if type(icon) == "table" and icon.SetTexCoord and not (icon.GetAtlas and icon:GetAtlas()) then
        local c = ns.Skin.CropOf(ns.Skin.LookFor(nil))
        icon:SetTexCoord(c[1], c[2], c[3], c[4])
    end
end

local followingBags = false
local function followBags()
    if followingBags then return end
    followingBags = true
    for _, fn in ipairs({ "SetItemButtonTexture", "SetItemButtonQuality" }) do
        if type(_G[fn]) == "function" then hooksecurefunc(fn, bagArt) end
    end
end

-- A bag button: the shell on the button itself, the icon filling it.
function Menus.SkinBag(btn)
    if type(btn) ~= "table" or skinned[btn] or (btn.IsForbidden and btn:IsForbidden()) then return end
    local parts = {}
    skinned[btn] = parts
    parts.shell = Style.Shell(btn, ns.Skin.SharedShellOpts())
    fade(btn.IconBorder)
    local icon = btn.icon or btn.Icon
    if type(icon) == "table" and icon.ClearAllPoints then
        if btn.SquareMask and icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, btn.SquareMask) end
        icon:ClearAllPoints()
        icon:SetAllPoints(btn)
    end
    -- Mouseover: a faint white over the icon. The game's own highlight comes back at
    -- 40% on every update, so it's reset to 0 after each.
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    local c = ns.Skin.HIGHLIGHT
    hl:SetColorTexture(c[1], c[2], c[3], c[4])
    hl:SetAllPoints(btn)
    parts.highlight = hl
    for _, k in ipairs({ "Count", "FreeSlots" }) do
        local fs = btn[k]
        Style.DressText(fs, 11)
    end
    -- The game restores its art in the button's UpdateTextures, which runs from the
    -- global SetItemButtonTexture/SetItemButtonQuality (a bag slot update) and from
    -- the button's own events (the key ring's BAG_UPDATE). Follow those, never with
    -- a hook on the button's methods.
    followBags()
    if btn.HookScript then btn:HookScript("OnEvent", bagArt) end
    bagArt(btn)
end

function Menus.IsSkinned(btn) return skinned[btn] ~= nil end
function Menus.Parts(btn) return skinned[btn] end

-- The game's dividers between the bag buttons: pooled frames, the only unnamed
-- frames on the bar. A released one keeps its alpha, so each only has to be handled
-- once. New ones come with a new layout (a size change: another bag slot, or the bar
-- rotated in Edit Mode).
function Menus.HideDividers()
    local bar = _G.BagsBar
    if type(bar) ~= "table" or not bar.GetChildren then return end
    for _, child in ipairs({ bar:GetChildren() }) do
        if child:GetObjectType() == "Frame" and not child:GetName() then child:SetAlpha(0) end
    end
end

local watchingBar = false
local function watchBar()
    local bar = _G.BagsBar
    if watchingBar or type(bar) ~= "table" or not bar.HookScript then return end
    watchingBar = true
    -- The game lays out the dividers after it sets the size.
    bar:HookScript("OnSizeChanged", function() C_Timer.After(0, Menus.HideDividers) end)
end

-- Skins every button there is now (already skinned ones are skipped) and repaints
-- the row, in case the game showed or hid a button since.
function Menus.Apply()
    for bar, keys in pairs(Menus.BAR_ART) do
        local f = _G[bar]
        if type(f) == "table" then
            for _, k in ipairs(keys) do fade(f[k]) end
        end
    end
    for _, name in ipairs(Menus.MICRO) do Menus.SkinMicro(_G[name], name) end
    for _, name in ipairs(Menus.BAGS) do Menus.SkinBag(_G[name]) end
    watchBar()
    Menus.HideDividers()
    Menus.PaintMicro()
end
