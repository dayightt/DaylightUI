-- Registers chat with the DaylightUI core.

local _, ns = ...

DaylightUI:RegisterModule("Chat", {
    -- Globals each file defines. If one is missing after an update, the module
    -- turns itself off with one line in chat instead of erroring.
    ns = ns,
    parts = { "Tags", "Levels", "Chat", "Feel", "History", "Copy", "Bubbles", "Links", "LinkTips", "Whisper", "Recall", "Kinds", "Box", "ChatMenu", "Extras", "Tabs", "Filter", "Talk", "Thread", "Convo", "Tiles", "Hub", "Tell" },
    label = "Chat",
    order = 145,
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod)
        ns.Talk.Load()
        ns.Talk.Listen()
        ns.Chat.Build(mod)
        ns.History.Restore(mod.db)
        ns.Bubbles.Build(mod)
    end,
    OnSettingChanged = function(mod, path)
        -- The bubbles live apart from the chat. Re-fonting every chat window reflows
        -- its whole history, and on each step of the bubble size slider that made the drag hitch.
        if not (type(path) == "string" and path:find("^bubble")) then ns.Chat.Refresh(mod) end
        ns.Bubbles.Refresh()
    end,
    OnStyleChanged = function() ns.Bubbles.Refresh() end,
})

-- The newest chat lines, saved for the next reload (History.lua).
DaylightUI.RegisterEvent("PLAYER_LOGOUT", function()
    local mod = DaylightUI:GetModule("Chat")
    if mod and mod.db and ns.History then DaylightUI.SafeCall(ns.History.Save, mod.db) end
end)
