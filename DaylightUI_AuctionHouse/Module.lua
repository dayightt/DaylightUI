-- Registers the Auction House with the DaylightUI core.

local _, ns = ...

DaylightUI:RegisterModule("AuctionHouse", {
    -- What each file defines. If a file goes missing after an update, the module
    -- turns itself off with one line in chat (tests/test_guards.lua checks this list).
    ns = ns,
    parts = { "DB", "Items", "Market", "Ruleset", "Store", "Rows", "AH", "Bags", "Replicate", "Search", "Browse", "Buy", "Post", "Scan" },
    label = "Auction House",
    order = 160,
    defaults = {},
    OnEnable = function() ns.Fire("Login") end,
})
