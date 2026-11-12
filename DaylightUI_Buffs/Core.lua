-- Core: the module's namespace, output, secret-value guards, event bus,
-- settings access and the small formatting helpers every other file uses.
-- The saved data lives in DaylightUI's database (the module's own table), in
-- the shape the rest of these files expect: settings (with a debuff
-- sub-table), categories, categoryOrder, overrides, learned, spells, history.

local _, BL = ...
local DUI = DaylightUI

BL.MODULE = "Buffs"

function BL.Print(msg) DUI.Print(tostring(msg)) end

-- ---------------------------------------------------------------------
-- Secret values. Any value that came from aura data, a unit API or an
-- event payload goes through here before it is compared, formatted, or
-- used as a table key. A secret becomes nil, so the worst case is
-- missing data rather than an error.
-- ---------------------------------------------------------------------

function BL.Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

function BL.PlainTable(t)
    if type(t) ~= "table" then return nil end
    if issecrettable and issecrettable(t) then return nil end
    return t
end

-- ---------------------------------------------------------------------
-- Clock indirection (tests replace these)
-- ---------------------------------------------------------------------

function BL.Now() return time() end
function BL.Clock() return GetTime() end

-- ---------------------------------------------------------------------
-- Internal event bus
-- ---------------------------------------------------------------------

local listeners = {}

function BL.On(event, fn)
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
end

function BL.Fire(event, ...)
    local list = listeners[event]
    if not list then return end
    for i = 1, #list do DUI.SafeCall(list[i], ...) end
end

-- ---------------------------------------------------------------------
-- Client events go through the core's DUI.RegisterEvent. Unit events about the
-- player go through our own frame that the client filters to the player (the
-- core has no unit form): fn(event, unit, ...). The unit may be secret under
-- restrictions, but it's always the player.
-- ---------------------------------------------------------------------

local playerFrame = CreateFrame("Frame")
local playerHandlers = {}

playerFrame:SetScript("OnEvent", function(_, event, ...)
    local list = playerHandlers[event]
    for i = 1, #list do DUI.SafeCall(list[i], event, ...) end
end)

function BL.OnPlayer(event, fn)
    local list = playerHandlers[event]
    if not list then
        list = {}
        playerHandlers[event] = list
        playerFrame:RegisterUnitEvent(event, "player")
    end
    list[#list + 1] = fn
end

-- ---------------------------------------------------------------------
-- Settings. The icons use the target auras' look at a size readable at the
-- screen edge.
-- ---------------------------------------------------------------------

BL.DEFAULTS = {
    settings = {
        iconSize = 30,
        borderPx = 2, -- icon border thickness, separate from other bars
        spacing = 3,
        categoryGap = 5,
        columns = 34,
        growLeft = true,
        showBackground = false,
        backgroundAlphaOwn = false, -- off: follows the general window opacity
        backgroundAlpha = 0.85,
        consolidateOnlyGroup = false,
        consolidateOnlyRaid = false,
        hideBlizzardFrames = true,
        attach = true, -- follows the info panel
        fade = DaylightUI.Fade.Defaults(),
        -- Text on both bars: time size (0 = follows the icon), stack count
        -- size, whether times show, and where on the icon (top | middle |
        -- bottom; Widgets.TIME_SPOTS).
        timeSize = 0, countSize = 10, showTimers = true, timePos = "top",
        -- Text outline ("general" = the Appearance setting). Separate so a
        -- player can have outlines only on the timers.
        textOutline = "general",
        expiring = true, -- the buff timer warms and pulses in its last 5 s (Feel.lua)
        newGlow = true, -- buffs and debuffs slide in and lift away (Feel.lua; old name kept for saved settings)
        -- On a ready check, or entering a dungeon or raid in a group, show
        -- the group buffs you're missing for this many seconds (Reminder.lua).
        reminder = { enabled = true, seconds = 10 },
        debuff = {
            iconSize = 36,
            borderPx = 2,
            spacing = 3,
            columns = 8,
            attach = true,
            growLeft = true,
            fade = DaylightUI.Fade.Defaults(),
            showBackground = false,
            backgroundAlphaOwn = false,
            backgroundAlpha = 0.85,
            -- Boss debuffs addons can't read, shown under the first row (Private.lua).
            privateAuras = true,
        },
    },
    -- categories is intentionally absent: nil means "never seeded" and
    -- Categories.Seed fills it exactly once.
    categoryOrder = {},
    -- Buffs the game doesn't report a class for, put where they belong.
    overrides = {
        ["Mark of the Wild"] = "druid",
        ["Redoubt"] = "paladin",
        ["Seal of Fury"] = "paladin",
        ["Light's Fury"] = "paladin",
        ["Minor Arcane Elixir"] = "consumable",
        ["Minor Troll's Blood Elixir"] = "consumable",
        ["Campfire Nearby"] = "world",
        ["Welcoming Campfire"] = "world",
        ["Camp Benefits"] = "world",
    },
    learned = {},
    spells = {},      -- [spellId] = name, learned whenever aura data is readable
    history = {},
    nextCustomId = 1,
}

-- BL.DB is the module's table. DaylightUI owns it and may swap in a fresh one
-- (if the client replaces the saved variables, or when the active profile is
-- rebuilt by Profiles.Replace or the setup guide's Finish), so it's looked up
-- through the module every time instead of cached. A table not seen before gets
-- its categories seeded before anyone reads it: categories aren't defaults, so
-- a swapped-in table has none.
local seeded
setmetatable(BL, { __index = function(_, key)
    if key ~= "DB" or not BL.module then return nil end
    local db = BL.module.db
    if db ~= nil and db ~= seeded then
        seeded = db
        if BL.Categories and BL.Categories.Seed then BL.Categories.Seed() end
    end
    return db
end })

-- Called when the module is enabled: seeds the categories the first time.
function BL.UseModule(mod)
    BL.module = mod
    if BL.Categories and BL.Categories.Seed then BL.Categories.Seed() end
    BL.Fire("DB_READY")
end

local function settingsTable(scope)
    if scope == "debuff" then return BL.DB.settings.debuff end
    return BL.DB.settings
end

function BL.GetSetting(key, scope)
    return settingsTable(scope)[key]
end

-- ---------------------------------------------------------------------
-- Formatting
-- ---------------------------------------------------------------------

-- Aura-style duration abbreviation (lives in core; totem timers use it too).
BL.FormatTime = DUI.FormatTime

-- Lowercase class file token for a unit ("priest"), nil when unknown or secret.
function BL.ClassToken(unit)
    unit = BL.Plain(unit)
    if type(unit) ~= "string" then return nil end
    local _, token = UnitClass(unit)
    token = BL.Plain(token)
    if type(token) ~= "string" then return nil end
    return string.lower(token)
end
