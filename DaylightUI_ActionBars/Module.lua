-- Registers the action bars with the DaylightUI core (Daylight UI's own bars, Bars.lua).

local _, ns = ...

DaylightUI:RegisterModule("ActionBars", {
    -- What its files define, so a file missing after an update turns the
    -- module off with one line in chat (tests/test_guards.lua keeps it right).
    ns = ns,
    parts = { "Shape", "Skin", "Hide", "Menus", "Totems", "Park", "Paging", "Buttons", "Ping", "RankUp",
               "Keys", "Small", "PadSkin", "Bars", "Diag", "Cooldowns", "BuffBars", "CdmData", "CdmTether", "CdmSpells", "CdmCustom", "CdmEffects", "CdmRows",
               "CdmOwn", "CdmAuras", "CdmBars", "CdmEditor", "CdmCard", "CdmImport", "CdmSwitch", "CdmGuide" },
    label = "Action Bars",
    order = 110,
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod) ns.Bars.Enable(mod) end,
    OnSettingChanged = function(mod, path) ns.Bars.SettingChanged(mod, path) end,
    OnSettingsChanged = function(mod, paths) ns.Bars.SettingsChanged(mod, paths) end,
    OnStyleChanged = function(mod)
        ns.Bars.Refresh(mod)
        if mod.db.skinMenus then ns.Menus.PaintMicro(); ns.Menus.PaintBagCount() end
    end,
})
