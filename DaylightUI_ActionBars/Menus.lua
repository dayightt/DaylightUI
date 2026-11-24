-- The game's micro menu and bag bar in the action buttons' look (a setting, on by
-- default; a reload switches it). The buttons stay the game's (keybinds, tooltips,
-- alerts); only their art changes.
--   * Micro buttons: a shell frames one of Daylight UI's line icons
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
Menus.MICRO_GROW = 0.15        -- how much bigger an icon gets under the mouse
Menus.OPEN_LINE_H = 2          -- the line under an open window's button
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

-- The action buttons' look without its button shape. A shape turns the shell's own
-- drawing off and only the action buttons lay the shape's pieces in its place, so
-- these buttons keep the square shell or they'd have no background at all.
local function squareLook()
    local L = ns.Skin.LookFor(nil)
    if not ns.Skin.ShapeOf(L) then return L end
    return setmetatable({ shape = "square" }, { __index = L })
end

local function shellOpts()
    local o = ns.Skin.SharedShellOpts()
    ns.Skin.StyleShellOpts(o, squareLook())
    return o
end

-- Follows a change of the action buttons' look (border style, corners, shadow).
local function restyle()
    local L = squareLook()
    for _, parts in pairs(skinned) do
        local s = parts.shell
        if type(s) == "table" and type(s.opts) == "table" and ns.Skin.StyleShellOpts(s.opts, L) then
            Style.LayoutShell(s)
        end
    end
end
DUI.On("ActionButtonLookChanged", restyle)

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
-- its window open), or dimmed while the game has it locked. Icons that rest dimmer
-- come up to full opacity along the same p.
local function paintIcon(parts, p)
    parts.lift = p
    local icon, hi = parts.icon, Style.INK.VALUE
    local rest = parts.restAlpha or 1
    icon:SetAlpha(rest + (1 - rest) * p)
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

-- The icon's size, swollen by g (0 to 1) while hovered.
local function sizeIcon(parts, g)
    parts.grow = g
    local s = (parts.size or Menus.MICRO_ICON) * (1 + Menus.MICRO_GROW * g)
    parts.icon:SetSize(s, s)
end

-- The tile sits gap px in from the button's edge.
local function placeBox(parts, btn, gap)
    parts.gap = gap
    local box = parts.box
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", btn, "TOPLEFT", gap, -gap)
    box:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -gap, gap)
end

-- The line under an open window's button, in the icon's own colors. Made the
-- first time it's wanted.
local function openLine(btn, parts)
    local line = parts.line
    if not line then
        line = btn:CreateTexture(nil, "OVERLAY")
        line:SetTexture("Interface\\Buttons\\WHITE8X8")
        line:SetHeight(Menus.OPEN_LINE_H)
        line:SetPoint("BOTTOMLEFT", parts.box, "BOTTOMLEFT", 4, 1)
        line:SetPoint("BOTTOMRIGHT", parts.box, "BOTTOMRIGHT", -4, 1)
        line:SetAlpha(0)
        parts.line, parts.lineOn = line, 0
    end
    local a, b = parts.from, parts.to
    line:SetVertexColor(1, 1, 1, 1)
    line:SetGradient("HORIZONTAL", CreateColor(a[1], a[2], a[3], 1), CreateColor(b[1], b[2], b[3], 1))
    return line
end

-- Eases a button to what it should show now.
local function settle(btn)
    local parts = skinned[btn]
    if not parts or not parts.from then return end
    local db = ns.db or {}
    local open = btn:GetButtonState() == "PUSHED"
    local hover = btn:IsMouseOver()
    parts.locked = not btn:IsEnabled()
    -- An open window shows as a lit border, a line under the icon, or both.
    local mark = db.microOpenMark or "border"
    local lit = open and mark ~= "line"
    if lit ~= parts.lit then
        parts.lit = lit
        if lit then
            Style.LightShell(parts.shell)
        else
            Style.SetShellColors(parts.shell, parts.rest[1], parts.rest[2], parts.rest[3])
        end
    end
    local M = DUI.Motion
    local lineTo = open and mark ~= "border" and 1 or 0
    if lineTo > 0 or parts.line then
        local line = openLine(btn, parts)
        if parts.lineOn ~= lineTo then
            parts.lineOn = lineTo
            M.AlphaTo(line, lineTo, M.FAST)
        end
    end
    local to = (open or hover) and not parts.locked and 1 or 0
    -- Motion paints at once when there's nothing to ease, so a new slice shows too.
    M.Tween(parts.icon, parts.lift, to, M.FAST, function(p) paintIcon(parts, p) end)
    local grow = hover and not parts.locked and db.microHoverGrow ~= false and M.On() and 1 or 0
    M.Tween(parts.growKey, parts.grow, grow, M.FAST, function(g) sizeIcon(parts, g) end)
end

-- Paints the sweep over the row as it stands, each button's state, and the two
-- accent pieces. Also runs after a style change.
function Menus.PaintMicro()
    local list, bar = shownMicro(), _G.MicroMenu
    local standing = type(bar) == "table" and bar.isHorizontal == false
    local per = #list
    if type(bar) == "table" and bar.isStacked then per = math.ceil(per / 2) end
    -- The icon color setting, read now so an accent change shows at once.
    local db = ns.db or {}
    local mode = db.microIconColor
    local one
    if mode == "class" then
        one = ns.Skin.ModeColor("class")
    elseif mode == "custom" and type(db.microIconCustom) == "table" then
        local c = db.microIconCustom
        one = { c[1] or 1, c[2] or 1, c[3] or 1 }
    end
    local function at(t) return one or { Style.AccentAt(t) } end
    local tiles = db.microBackgrounds ~= false and 1 or 0
    local size = tonumber(db.microIconSize) or Menus.MICRO_ICON
    local gap = tonumber(db.microGap) or Menus.MICRO_INSET[1]
    for i, btn in ipairs(list) do
        local spot = (i - 1) % per
        local parts = skinned[btn]
        parts.from, parts.to = at(spot / per), at((spot + 1) / per)
    end
    local M = DUI.Motion
    for _, name in ipairs(Menus.MICRO) do
        local btn = _G[name]
        local parts = type(btn) == "table" and skinned[btn]
        if parts then
            if not parts.from then parts.from, parts.to = at(0), at(1) end
            if mode == "each" then
                local c = Menus.ColorOf(parts.iconName)
                parts.from, parts.to = c, c
            end
            parts.standing = standing
            parts.restAlpha = tonumber(db.microRestAlpha) or 1
            parts.lit = nil         -- a style change rebuilt the shell's colors
            if parts.size ~= size then
                parts.size = size
                sizeIcon(parts, parts.grow)
            end
            if parts.gap ~= gap then
                M.Tween(parts.gapKey, parts.gap, gap, M.FAST, function(v) placeBox(parts, btn, v) end)
            end
            settle(btn)
            if parts.tiles ~= tiles then
                local box = parts.box
                DUI.Motion.Tween(box, parts.tiles or 1, tiles, DUI.Motion.FAST, function(a) box:SetAlpha(a) end)
                parts.tiles = tiles
            end
            if parts.flash then Style.PaintAccent(parts.flash) end
            if parts.dot then Style.PaintAccent(parts.dot) end
        end
    end
end

-- One icon's own color under "each", by its icon name.
function Menus.ColorOf(iconName)
    local db = ns.db or {}
    local saved = type(db.microColors) == "table" and db.microColors[iconName]
    local c = type(saved) == "table" and saved or ns.DEFAULTS.microColors[iconName] or { 1, 1, 1 }
    return { c[1] or 1, c[2] or 1, c[3] or 1 }
end

-- Every icon back to its own default color.
function Menus.ResetColors()
    DUI.Batch(function()
        for k, c in pairs(ns.DEFAULTS.microColors) do
            DUI:Set("ActionBars", "microColors." .. k, { c[1], c[2], c[3] })
        end
    end)
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
    DUI.RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function() C_Timer.After(0, Menus.PaintMicro) end)
end

-- A micro button: the shell on a box inside it, Daylight UI's icon on that, and the game's art
-- masked away (the mask sits off the button, so all of the art is outside it).
function Menus.SkinMicro(btn, name)
    if type(btn) ~= "table" or skinned[btn] or (btn.IsForbidden and btn:IsForbidden()) then return end
    local parts = { lift = 0, grow = 0, growKey = {}, gapKey = {}, iconName = Menus.ICONS[name] or "menu" }
    skinned[btn] = parts
    for _, k in ipairs(Menus.MICRO_ART) do fade(btn[k]) end
    local box = CreateFrame("Frame", nil, btn)
    parts.box = box
    placeBox(parts, btn, tonumber((ns.db or {}).microGap) or Menus.MICRO_INSET[1])
    box:SetFrameLevel(math.max(0, btn:GetFrameLevel() - 1))
    parts.shell = Style.Shell(box, shellOpts())
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
    icon:SetTexture(DUI.MEDIA .. "ui-micro-" .. parts.iconName .. ".png")
    parts.icon = icon
    parts.size = tonumber((ns.db or {}).microIconSize) or Menus.MICRO_ICON
    sizeIcon(parts, 0)
    icon:SetPoint("CENTER", box, "CENTER", 0, 0)

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
    parts.shell = Style.Shell(btn, shellOpts())
    fade(btn.IconBorder)
    local icon = btn.icon or btn.Icon
    if type(icon) == "table" and icon.ClearAllPoints then
        if btn.SquareMask and icon.RemoveMaskTexture then DUI.SafeCall(icon.RemoveMaskTexture, icon, btn.SquareMask) end
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
    Menus.PaintBagCount(btn)
    -- The game restores its art in the button's UpdateTextures, which runs from the
    -- global SetItemButtonTexture/SetItemButtonQuality (a bag slot update) and from
    -- the button's own events (the key ring's BAG_UPDATE). Follow those, never with
    -- a hook on the button's methods.
    followBags()
    if btn.HookScript then btn:HookScript("OnEvent", bagArt) end
    bagArt(btn)
end

-- The backpack's free slot count is a number a glance needs, so it takes the
-- accent. The game only ever sets its text, so the color stays.
function Menus.PaintBagCount(btn)
    if btn == nil then
        for b in pairs(skinned) do Menus.PaintBagCount(b) end
        return
    end
    local fs = btn.FreeSlots
    if type(fs) == "table" and fs.SetTextColor then Style.InkText(fs, "pop") end
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
