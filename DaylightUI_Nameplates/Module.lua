-- Registers the nameplates with the DaylightUI core.

local _, ns = ...

-- Other nameplate addons draw over Daylight UI's (double names, no gradients).
ns.CLASHES = DaylightUI.InstallerPages.ClashesFor("Nameplates") -- listed by the setup guide

DaylightUI:RegisterModule("Nameplates", {
    -- Globals each file defines. If one is missing after an update, the module
    -- turns itself off with one line in chat instead of erroring.
    ns = ns,
    parts = { "Body", "Plate", "Minion", "Cast", "Combo", "Power", "Range", "Auras", "Manager", "Sample" },
    label = "Nameplates",
    order = 125,
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod)
        ns.cfg = mod.db
        for _, c in ipairs(ns.CLASHES) do
            DaylightUI.WarnIfLoaded(c.addon, c.label, DaylightUI.L["nameplates"])
        end
        ns.Combo.Create()
        ns.Manager.Start()
    end,
    OnSettingChanged = function(mod, path)
        ns.cfg = mod.db
        if path == "friendly.enabled" then ns.Manager.ApplyNameOnly() end
        if path == "minions" then ns.Minion.Apply() end
        if path == "friendly.hideInInstance" then ns.Manager.ApplyInstanceFriends() return end
        if path == "range" then
            ns.Manager.ApplyRange()
        elseif path == "stacking" or path == "stackFriendly" then
            ns.Manager.ApplyStacking()
        else
            ns.Manager.Refresh()
        end
        if type(path) ~= "string" or string.find(path, "barFx", 1, true) then DaylightUI.BarFx.Refresh() end
    end,
    OnStyleChanged = function(mod) ns.cfg = mod.db; ns.Manager.Refresh() end,
})
