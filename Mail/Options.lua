-- The mailbox window's options, as data.

local _, DUI = ...
DUI.Mail = DUI.Mail or {}
local ns = DUI.Mail

local backRows = DUI.Options.BackAlphaRows("windowAlpha", "Mailbox", function() return DUI.mailMogul == true end, "1.6.2")

ns.OPTIONS = { pages = {
    { id = "window", label = "Mailbox",
      desc = "Your letters, sending, and what you made through the mail and the auction house, in one window, in DaylightUI style.",
      groups = {
        { label = "Window", items = {
            { type = "text", label = "DaylightMogul's mailbox is in use.",
              hidden = function() return not DaylightUI.mailMogul end },
            { type = "toggle", key = "enabled", label = "DaylightUI style mailbox", reload = true,
              disabled = function() return DaylightUI.mailMogul == true end,
              desc = "Opening a mailbox shows DaylightUI's window: your letters, sending, and a ledger of your gold. Turn it off to use the game's window. The ledger keeps counting either way." },
            { type = "slider", key = "scale", label = "Window scale", min = 0.7, max = 1.3, step = 0.05, unit = "x",
              desc = "How big the window is.", disabled = function() return DaylightUI.mailMogul == true end },
            backRows[1], backRows[2],
        } },
    } },
} }
