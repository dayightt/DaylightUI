-- Daylight UI's own text in the player's language. English text is the key
-- and the fallback: L["Width"] gives "Width" when the language has no line,
-- so a missing line never breaks anything and a half-done language still
-- helps. Nothing is ever stored on a miss (the tests read the table).
--
-- Each language gets a file next to this one (deDE.lua, ...) that hands its
-- lines over in a function:
--   local _, DUI = ...
--   DUI.AddLanguage("deDE", function(L)
--   L["Width"] = "Breite"
--   end)
-- Whole sentences with string.format holes, never sentences glued from
-- pieces (word order differs). Saved things stay English: setting keys,
-- dropdown keys, profile names, slash commands and their words.
-- Module files read it as `local L = DaylightUI.L`.
--
-- The language can be picked on the options' Home page. Saved variables
-- arrive only after every core file has run, so the client's language goes
-- on first and the pick replaces it as they load (DUI.UseLanguage, from
-- Core.lua's ADDON_LOADED), before any module file runs. Core files must
-- not keep L's text from while they load: look it up when drawing.

local _, DUI = ...

-- The game's own language. The game's text (spell tooltips, item names)
-- is always in this one, whatever is picked.
DUI.CLIENT_LOCALE = GetLocale and GetLocale() or "enUS"
-- The language of Daylight UI's own text.
DUI.LOCALE = DUI.CLIENT_LOCALE

local function english(_, key) return key end
DUI.L = setmetatable({}, { __index = english })

-- The languages there are, in the menu's order, each named in its own words.
DUI.LANGUAGES = {
    { "enUS", "English" }, { "deDE", "Deutsch" }, { "esES", "Español" }, { "frFR", "Français" },
    { "ruRU", "Русский" }, { "koKR", "한국어" }, { "zhCN", "简体中文" },
}
-- Clients whose language shares another's file.
DUI.LANGUAGE_FILE = { esMX = "esES", enGB = "enUS" }

local fills = {}
local later = {}

-- A core file that keeps text in a table at load (labels, sample names) builds
-- it in here instead: it runs once the picked language is on, and at once
-- after that (modules load later).
function DUI.WithLanguage(fn)
    if later then later[#later + 1] = fn else fn() end
end

local function fileOf(locale)
    return DUI.LANGUAGE_FILE[locale] or locale
end

function DUI.AddLanguage(locale, fill)
    fills[locale] = fill
    if locale == fileOf(DUI.LOCALE) then fill(DUI.L) end
end

-- Puts the picked language on, once, as the saved variables load. nil or
-- "auto" keeps the client's; a language with no file here does too. The
-- other languages' lines are let go after, so only one is ever kept.
function DUI.UseLanguage(pick)
    if not later then return end
    local want = DUI.CLIENT_LOCALE
    if type(pick) == "string" and pick ~= "auto" and (pick == "enUS" or fills[fileOf(pick)]) then want = pick end
    if fileOf(want) ~= fileOf(DUI.LOCALE) then
        local L = DUI.L
        for k in pairs(L) do L[k] = nil end
        setmetatable(L, { __index = english })
        local fill = fills[fileOf(want)]
        if fill then fill(L) end
    end
    DUI.LOCALE = want
    fills = {}
    local waiting = later
    later = nil
    for _, fn in ipairs(waiting or {}) do DUI.SafeCall(fn) end
end
