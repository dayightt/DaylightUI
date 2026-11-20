-- The Auction House window's options, as data. With DaylightMogul loaded the
-- page is hidden: Mogul owns the Auction House then.

local _, ns = ...

local backRows = DaylightUI.Options.BackAlphaRows("windowAlpha", "Auction house")

ns.DEFAULTS = {
    -- Daylight UI's Auction House window instead of the game's; switched from either window.
    enabled = true,
    scale = 1,
    undercut = 1,             -- copper under the cheapest when Sell fills a price (gear: whole silver)
    windowAlphaOwn = false,   -- off: follows the general window opacity
    windowAlpha = 0.85,
}

ns.OPTIONS = { pages = {
    { id = "window", label = "Auction House",
      desc = "Buy, sell and your auctions in one window, with prices remembered from your searches and shown on every item tooltip.",
      hidden = function() return DaylightUI.ahMogul == true end,
      groups = {
        { label = "Window", items = {
            { type = "toggle", key = "enabled", label = "Daylight UI style Auction House window",
              desc = "Talking to an auctioneer shows Daylight UI's window. Turn it off to use the game's own window, for addons that build on it. Each window also has a button to switch to the other." },
            { type = "slider", key = "scale", label = "Auction House scale", min = 0.7, max = 1.3, step = 0.05, unit = "x",
              desc = "How big the window is." },
            backRows[1], backRows[2],
        } },
        { label = "Selling", items = {
            { type = "slider", key = "undercut", label = "Undercut by", min = 0, max = 100, step = 1, unit = "c",
              desc = "How far under the cheapest one up Sell puts your price, in copper. Gear and recipes go a whole silver under, as the game only takes them in silver." },
        } },
    } },
} }
