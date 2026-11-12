-- Colors, section looks and body font for the options window.
-- Widgets.lua re-exports these as W.COLORS and W.BODY.

local _, DUI = ...
local L = DUI.L

local Theme = {}
DUI.OptionsTheme = Theme

local function hex(s)
    return { tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255 }
end

-- Other files read these keys too (Movers, TestBox, Bags, Buffs, Profiles,
-- the cooldown editor), so don't rename them.
Theme.COLORS = {
    window = hex("141417"),
    sidebar = hex("101012"),         -- the rail
    list = hex("121214"),            -- the page list column
    stage = hex("0e0e10"),           -- behind a frame's live sample
    card = hex("1b1b1f"),
    cardEdge = hex("2a2a30"),        -- card and control outlines
    cardLit = hex("37373e"),         -- a card's lighter top edge
    line = { 1, 1, 1, 0.06 },        -- between rows
    control = hex("222227"),
    controlHover = hex("2c2c32"),
    track = hex("2c2c32"),           -- a switch that's off, a slider's track
    -- Text colors come straight from Style.INK
    text = DUI.Style.INK.TEXT,
    value = DUI.Style.INK.VALUE,     -- a slider's number
    dim = DUI.Style.INK.LABEL,
    faint = DUI.Style.INK.OFF,
    warn = DUI.Style.INK.BAD,
}

-- ---------------------------------------------------------------------
-- Body font. Latin-alphabet clients use the font picked in Appearance.
-- Other locales keep Arial Narrow, which their clients map to their own
-- glyphs, since a picked font may not have them.
-- ---------------------------------------------------------------------

Theme.LATIN = { enUS = true, enGB = true, deDE = true, frFR = true, esES = true, esMX = true,
                itIT = true, ptBR = true, ptPT = true }
Theme.NARROW = "Fonts\\ARIALN.TTF"

function Theme.BodyFont(locale)
    if locale == nil and type(GetLocale) == "function" then locale = GetLocale() end
    if not Theme.LATIN[locale or "enUS"] then return Theme.NARROW end
    -- A display font (Rubik Glitch, Press Start 2P...) is hard to read as body text.
    local picked = DUI.DB.sv and DUI.Style.FONTS[DUI.DB.General().font]
    if picked and picked.display then return DUI.Style.FONTS.expressway.file end
    return DUI.Style.FONT
end

-- ---------------------------------------------------------------------
-- Sections. Each gets a color along the gradient in rail order, a white
-- icon (Media/ui-section-<icon>.png) that gets tinted, a short rail name
-- and a tooltip line.
-- ---------------------------------------------------------------------

Theme.SECTIONS = {}
local function section(id, color, icon, short, blurb)
    Theme.SECTIONS[id] = { color = hex(color), icon = icon, short = short, blurb = blurb }
end
-- Some languages need a different word for action bars than for health or
-- power bars, so they can translate this one separately. English keeps "Bars"
-- because the rail is narrow.
local barsShort = L["Action bars, short"]
if barsShort == "Action bars, short" then barsShort = L["Bars"] end
section("core", "e9dcc8", "home", L["General"], L["Look, layout, profiles and setup."])
section("UnitFrames", "3d9cff", "frames", L["Frames"], L["Player, target, party, raid and more."])
section("ActionBars", "5f8cff", "bars", barsShort, L["Your action bars and their buttons."])
section("CooldownManager", "7d7cf5", "cooldowns", L["Cooldowns"], L["The cooldown manager's layout."])
section("InfoPanel", "9a72e8", "info", L["Info"], L["The info panel, meter, map and tracker."])
section("Quests", "a76fe0", "quests", L["Quests"], L["Your quest tracker."])
section("Bags", "b56ad6", "bags", L["Bags"], L["Backpack, bank and categories."])
section("Nameplates", "cc66c0", "plates", L["Plates"], L["Names and bars over heads."])
section("Buffs", "e0679f", "buffs", L["Buffs"], L["Your buffs and debuffs."])
section("Tooltip", "f0708a", "tooltip", L["Tooltips"], L["The game's tooltips."])
section("Chat", "ff8a5a", "chat", L["Chat"], L["Chat windows, tabs and text."])
section("QoL", "ff9a1f", "extras", L["Extras"], L["Small helpers and the game's windows in DaylightUI style."])
section("patchnotes", "e9dcc8", "news", L["News"], L["What changed in each version."])
Theme.FALLBACK_ICON = "module"

-- The whole Daylight sweep, for a section the table doesn't know.
Theme.SWEEP = { hex("1e90ff"), hex("a25ec7"), hex("e65a72"), hex("ff9a1f") }

-- The sweep's color t of the way along (0 to 1).
function Theme.GradientAt(t)
    local stops = Theme.SWEEP
    t = math.max(0, math.min(1, t or 0)) * (#stops - 1)
    local i = math.min(#stops - 1, math.floor(t) + 1)
    local f = t - (i - 1)
    local a, b = stops[i], stops[i + 1]
    return { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f }
end

local fallback = {}

-- Returns { color, icon, short, blurb }. Unknown sections (a module added
-- later) get a sweep color by their order, the generic icon and their label.
function Theme.Section(id)
    if Theme.SECTIONS[id] then return Theme.SECTIONS[id] end
    if fallback[id] then return fallback[id] end
    local label, order = tostring(id), 100
    for _, s in ipairs(DUI.Options.Sections()) do
        if s.id == id then label, order = s.label, s.order end
    end
    fallback[id] = { color = Theme.GradientAt((order - 100) / 60), icon = Theme.FALLBACK_ICON,
                     short = label, blurb = label .. "." }
    return fallback[id]
end

-- Our icons by name. Plugins (Plugins.lua) pass a full path or file id.
function Theme.IconFile(icon)
    if type(icon) == "number" or string.find(icon, "[\\/]") then return icon end
    return DUI.MEDIA .. "ui-section-" .. icon .. ".png"
end
