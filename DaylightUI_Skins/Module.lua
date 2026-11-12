-- Registers the window skins with the DaylightUI core.

local _, ns = ...

DaylightUI:RegisterModule("Skins", {
    -- The module's parts, so a file missing after an update disables the
    -- module with one line in chat instead of erroring.
    ns = ns,
    parts = { "Kit", "Engine", "Breath", "CcAlert", "MapMove", "MapReveal", "MapPins", "WindowScale", "WindowMove", "LootRoll", "Ace3", "RXPv2", "FDJ", "NeedRoll", "DBMSkin", "BigWigsSkin", "PrettySkin", "Attune", "OPieSkin", "BagnonSkin", "BaganatorSkin" },
    label = "Game window skins",
    order = 150,
    section = "QoL", pageOrder = 140, -- options page sits under Extras, after the custom windows
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod)
        DaylightUI.WarnIfLoaded("EllesmereUIBlizzardSkin", "EllesmereUI Blizzard Skin", DaylightUI.L["game windows"])
        ns.MapMove.Start(mod.db)
        ns.MapReveal.Start(mod.db)
        ns.MapPins.Start(mod.db)
        ns.WindowScale.Start(mod.db)
        ns.WindowMove.Start(mod.db)
        ns.Engine.Start(mod.db)
        -- Questie icons in our art follow this switch (DUI.QuestieAside).
        DaylightUI.Fire("QuestMapsChanged")
    end,
    OnSettingChanged = function(mod)
        ns.MapMove.Start(mod.db)
        ns.MapReveal.Start(mod.db)
        ns.MapPins.Start(mod.db)
        ns.WindowScale.Start(mod.db)
        ns.WindowMove.Start(mod.db)
        ns.Engine.Refresh(mod.db)
        DaylightUI.Fire("QuestMapsChanged")
    end,
})
