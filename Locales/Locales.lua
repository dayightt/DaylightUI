-- Our own text in the player's language. English text is the key and the
-- fallback: L["Width"] gives "Width" when the language has no line, so a
-- missing line never breaks anything and a half-done language still helps.
-- Nothing is ever stored on a miss (the tests read the table).
--
-- Each language gets a file next to this one (deDE.lua, ...) that returns
-- at once unless the client is that language:
--   local _, DUI = ...
--   if DUI.LOCALE ~= "deDE" then return end
--   local L = DUI.L
--   L["Width"] = "Breite"
-- Whole sentences with string.format holes, never sentences glued from
-- pieces (word order differs). Saved things stay English: setting keys,
-- dropdown keys, profile names, slash commands and their words.
-- Module files read it as `local L = DaylightUI.L`.

local _, DUI = ...

DUI.LOCALE = GetLocale and GetLocale() or "enUS"
DUI.L = setmetatable({}, { __index = function(_, key) return key end })
