-- Registers the Auction House with the DaylightUI core.

local _, ns = ...

DaylightUI:RegisterModule("AuctionHouse", {
    -- What each file defines. If a file goes missing after an update, the module
    -- turns itself off with one line in chat (tests/test_guards.lua checks this list).
    ns = ns,
    parts = { "DB", "Items", "Market", "Ruleset", "Store", "Rows", "AH", "Bags", "Replicate", "Search", "Browse", "Buy", "Post", "Scan",
              "Tooltip", "ScanBand", "BuyPage", "SellPage", "AuctionsPage", "Window" },
    label = "Auction House",
    order = 160,
    section = "QoL", pageOrder = 137,   -- its options page sits under Extras, after the smaller windows
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod)
        ns.module = mod
        ns.mogul = ns.MogulOwns()
        DaylightUI.ahMogul = ns.mogul
        if not ns.mogul then
            ns.Window.InitSwap()
            if ns.swap.Ours() then ns.Window.Build(mod) end
        end
        ns.Fire("Login")
    end,
    OnSettingChanged = function()
        if ns.swap then ns.swap.Apply() end
        ns.Window.Apply()
    end,
    OnStyleChanged = function()
        ns.Window.Apply()
        ns.ScanBand.Restyle()
    end,
})
