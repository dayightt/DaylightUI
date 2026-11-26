-- Registers the window skins with the DaylightUI core.

local _, ns = ...

DaylightUI:RegisterModule("Skins", {
    -- The module's parts, so a file missing after an update disables the
    -- module with one line in chat instead of erroring.
    ns = ns,
    parts = { "Kit", "Engine", "Breath", "CcAlert", "MapMove", "MapReveal", "MapPins", "MapLevels", "WindowScale", "WindowMove", "LootRoll", "LootLayout", "RollChat", "RollData", "RollCard", "RollSample", "RollStack", "Ace3", "RXPv2", "FDJ", "NeedRoll", "DBMSkin", "BigWigsSkin", "PrettySkin", "Attune", "OPieSkin", "BagnonSkin", "BaganatorSkin", "Trade" },
    label = "Game window skins",
    order = 150,
    section = "QoL", pageOrder = 140, -- options page sits under Extras, after the custom windows
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod)
        ns.MapMove.Start(mod.db)
        ns.MapReveal.Start(mod.db)
        ns.MapPins.Start(mod.db)
        ns.MapLevels.Start(mod.db)
        ns.WindowScale.Start(mod.db)
        ns.WindowMove.Start(mod.db)
        ns.Engine.Start(mod.db)
        -- Questie icons in the Daylight art follow this switch (DUI.QuestieAside).
        DaylightUI.Fire("QuestMapsChanged")
    end,
    OnSettingChanged = function(mod)
        ns.MapMove.Start(mod.db)
        ns.MapReveal.Start(mod.db)
        ns.MapPins.Start(mod.db)
        ns.MapLevels.Start(mod.db)
        ns.WindowScale.Start(mod.db)
        ns.WindowMove.Start(mod.db)
        ns.Engine.Refresh(mod.db)
        ns.RollStack.Refresh()
        DaylightUI.Fire("QuestMapsChanged")
    end,
})
