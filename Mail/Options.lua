-- The mailbox window's options, as data.

local _, DUI = ...
DUI.Mail = DUI.Mail or {}
local ns = DUI.Mail

local lookRows = DUI.Options.LookRows("frameStyle", function() return DUI.mailMogul == true end)

ns.OPTIONS = { pages = {
    { id = "window", label = "Mailbox",
      desc = "Your letters, sending, and what you made through the mail and the auction house, in one window, in Daylight UI style.",
      groups = {
        { label = "Window", items = {
            { type = "text", label = "DaylightMogul's mailbox is in use.",
              hidden = function() return not DaylightUI.mailMogul end },
            { type = "toggle", key = "enabled", label = "Daylight UI style mailbox window",
              disabled = function() return DaylightUI.mailMogul == true end,
              desc = "Opening a mailbox shows Daylight UI's window: your letters, sending, and a ledger of your gold. Turn it off to use the game's own window, in Daylight UI's look, for addons that build on it. Each window also has a button to switch to the other. The ledger keeps counting either way." },
            { type = "slider", key = "scale", label = "Mailbox scale", min = 0.7, max = 1.3, step = 0.05, unit = "x",
              desc = "How big the window is.", disabled = function() return DaylightUI.mailMogul == true end },
        } },
        { label = "Borders and background", items = lookRows },
        { label = "Letters", items = {
            { type = "toggle", key = "ticks", label = "Tick letters to collect", since = "1.7.2",
              disabled = function() return DaylightUI.mailMogul == true end,
              desc = "A small switch on each letter. Tick a few and the button under the list collects only those." },
        } },
    } },
} }
