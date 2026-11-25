-- Default settings for Proc Alerts. Each proc's own look lives in `alerts`,
-- keyed by proc, holding only what the player changed (Alerts.lua).

local _, ns = ...

ns.DEFAULTS = {
    enabled = true,  -- the alerts at all
    scale = 1,       -- the size of every alert
    alpha = 1,       -- the opacity of every alert
    soundOn = true,  -- alert sounds
    alerts = {},     -- [procKey] = { field = value } (Alerts.FIELDS)
}
