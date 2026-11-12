-- Registers chat with the DaylightUI core.

local _, ns = ...

DaylightUI:RegisterModule("Chat", {
    -- Globals each file defines. If one is missing after an update, the module
    -- turns itself off with one line in chat instead of erroring.
    ns = ns,
    parts = { "Tags", "Chat", "Feel", "History", "Copy", "Bubbles", "Links", "LinkTips", "Whisper", "Recall", "Kinds", "Box", "ChatMenu", "Extras", "Tabs", "Filter", "Talk", "Thread", "Convo", "Tiles", "Hub", "Tell" },
    label = "Chat",
    order = 145,
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod)
        DaylightUI.WarnIfLoaded("EllesmereUIChat", "EllesmereUI Chat", DaylightUI.L["chat"])
        ns.Talk.Load()
        ns.Talk.Listen()
        ns.Chat.Build(mod)
        ns.History.Restore(mod.db)
        ns.Bubbles.Build(mod)
    end,
    OnSettingChanged = function(mod) ns.Chat.Refresh(mod) end,
})

-- The newest chat lines, saved for the next reload (History.lua).
DaylightUI.RegisterEvent("PLAYER_LOGOUT", function()
    local mod = DaylightUI:GetModule("Chat")
    if mod and mod.db and ns.History then DaylightUI.SafeCall(ns.History.Save, mod.db) end
end)
