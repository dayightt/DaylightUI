-- Core: the module's namespace, output, secret-value guards, event bus,
-- settings access and the small formatting helpers every other file uses.
-- The saved data lives in DaylightUI's database (the module's own table), in
-- the shape the rest of these files expect: settings (with a debuff
-- sub-table), categories, categoryOrder, overrides, learned, spells, history.

local _, BL = ...
local DUI = DaylightUI
local isSecret = DUI.IsSecret

BL.MODULE = "Buffs"

function BL.Print(msg) DUI.Print(tostring(msg)) end

-- ---------------------------------------------------------------------
-- Secret values. Any value that came from aura data, a unit API or an
-- event payload goes through here before it is compared, formatted, or
-- used as a table key. A secret becomes nil, so the worst case is
-- missing data rather than an error.
-- ---------------------------------------------------------------------

function BL.Plain(v)
    if isSecret(v) then return nil end
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
-- player go through a frame of the module's own that the client filters to the player (the
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
        categoryRows = false, -- class buffs share a row, every other kind starts its own
        columns = 34,
        growLeft = true,
        -- Within each category: soonest to run out first, or longest first
        -- with buffs that never run out leading (soonest | longest). The
        -- client's container sorts them, so the order holds in a fight.
        sortOrder = "soonest",
        showBackground = false,
        -- The bar background's border, shadow and opacity, or General's. Its
        -- border is thin by design.
        frameStyle = DaylightUI.Style.LookDefaults({ borderPx = 2 }),
        consolidateOnlyGroup = false,
        consolidateOnlyRaid = false,
        hideBlizzardFrames = true,
        attach = true, -- follows the info panel
        attachY = 0, -- while attached, nudged up (+) or down (-) from that spot, in px
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
        -- Missing buffs, a row of tiles above you (Reminder.lua, ReminderRow.lua):
        -- which kinds show, solo too, when a buff counts as running low, how
        -- see-through raid buffs are in a fight, and the tiles' look. The
        -- consumables are off: not everyone carries them.
        reminder = {
            enabled = true, solo = false,
            give = true, get = true, self = true, weapons = true,
            food = false, scrolls = false, camp = false, sleepingBag = false,
            lowMinutes = 5, fightAlpha = 0.5, size = 36, gap = 24, names = true,
        },
        -- Aura lists from Unit Frames > Aura Lists ("none" = no list): one to
        -- hide, one to show only.
        hideList = "none", onlyList = "none",
        debuff = {
            -- Every debuff or only the ones you can dispel (all | dispel), a
            -- list to hide, only a boss's, and the longest shown in seconds
            -- (0 = any).
            filter = "all", hideList = "none", bossOnly = false, maxTime = 0,
            iconSize = 36,
            borderPx = 2,
            spacing = 3,
            columns = 8,
            attach = true,
            attachY = 0,
            growLeft = true,
            sortOrder = "soonest",
            fade = DaylightUI.Fade.Defaults(),
            showBackground = false,
            frameStyle = DaylightUI.Style.LookDefaults({ borderPx = 2 }),
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
