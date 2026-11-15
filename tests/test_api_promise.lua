local stub = require("stub")

-- The promise: one big plugin uses every call DaylightUI.API makes, through a
-- party fight in a restricted match, and nothing escapes.

local PROMISED = {
    "On", "Off", "GetUnitFrame", "GetNameplate", "GetActionButton", "Frames", "GetSetting", "IsModuleEnabled",
    "Attach", "Skin", "Text", "Bar", "Button", "Close", "Switch", "Input", "Menu", "Accent", "Colors", "Font",
    "ClassColor", "Fade", "For",
    -- 1.2
    "GetShopTile", "ShopItem", "GetCraftRow", "GetPart", "SelectCraftRecipe", "GetCraftProfession", "FontRow", "FontFile",
    -- 1.3
    "Parts", "GetQuestRow",
    -- 1.5
    "GetActionBar", "ButtonInfo", "BindKeys", "Glow",
    -- 1.6
    "MeterWindows", "GetMeterWindow", "MeterRows", "MeterModes", "SetMeterMode", "ResetMeters", "OpenMeterBreakdown",
    -- 1.7
    "GetFrame", "GetMoverFrame", "IsUnlocked", "MotionOn", "Media", "IsAfkScreen", "RefreshShop", "RefreshBags",
    "GetCooldownPiece", "CooldownPieceInfo",
}
local VIEW = { "On", "RegisterMover", "RegisterFade", "RegisterTestPart", "RegisterCommand", "RegisterSkin", "AddOptionsGroup", "AttachCraftPane",
    "Paint", "Hook", "Wrap", "Unhook", "AddText", "AddDefaults", "AddDataText", "UpdateDataText", "AddDataPanel",
    "IsPreviewing", "SuspendMover", "Override", "FilterShop", "AddTooltipLines", "AddSetupStep", "AddBagGroup",
    "RemoveBagGroup", "AddBuffCategory", "FormatChat", "ChatLink", "OnChatLink" }
-- Internal only (DUI.APIReport), never on the public table.
local INTERNAL = { "Made", "Unit", "Back", "Gone", "Occupant", "Styled", "Wants", "Event", "Row", "ListDone", "ListClear",
    "Painted", "Owned", "Repainter", "Painting", "KindOf", "PaintedFrame", "OwnedOn", "SetInfo", "Info", "DataTexts", "DataPanels", "TooltipLines", "BagGroups", "BuffCategories",
    "FormatChat", "ChatFormatting", "ChatLinkClicked", "DropOverride", "DropShopFilter", "DropTooltipLines",
    "DropFormatter", "StartPainter", "Count",
    "Changes", "Changers", "Texts", "ApplyDefaults" }
local EVENTS = { "FrameMade", "FrameUnitChanged", "FrameRemoved", "FrameStyled",
                 "StyleChanged", "SettingChanged", "TestModeChanged", "UnlockChanged", "Login" }

T.test("api promise: a big plugin uses every promised call", function()
    local DUI = stub.Load({ module = true, actionbars = true, skins = true, login = false })
    local API = DUI.API
    for _, name in ipairs(PROMISED) do T.eq(type(API[name]), "function", "API." .. name) end
    T.eq(type(API.Speed), "table")
    for _, name in ipairs(INTERNAL) do T.isnil(DaylightUI.API[name], "API." .. name .. " is ours only") end
    T.eq(type(DUI.APIReport), "table")
    DUI.RegisterPlugin("BigPlugin", { title = "Big Plugin", needs = { 1, 1 } })
    DUI:RegisterModule("BigPlugin", { label = "Big Plugin", defaults = { big = false } })
    local me = API.For("BigPlugin")
    T.truthy(me)
    for _, name in ipairs(VIEW) do T.eq(type(me[name]), "function", "view." .. name) end

    local log, order = {}, {}
    for _, ev in ipairs(EVENTS) do
        log[ev] = 0
        me.On(ev, function() log[ev] = log[ev] + 1; order[#order + 1] = ev end)
    end
    -- A handler that errors never reaches the game or the others.
    API.On("FrameUnitChanged", function() error("plugin bug") end, "BigPlugin")
    local after = 0
    API.On("FrameUnitChanged", function() after = after + 1 end, "BigPlugin")

    -- Named things.
    local mine = CreateFrame("Frame", nil, UIParent)
    mine:SetSize(50, 20)
    me.RegisterMover(mine, "box", "Box", { point = "CENTER", x = 0, y = 0 })
    me.RegisterFade({ key = "box", frames = { mine } })
    me.RegisterTestPart("box", "Box", function() return true end)
    local ran
    T.eq(me.RegisterCommand("bigplug", function(rest) ran = rest end, "does a thing"), true)
    me.AddOptionsGroup("appearance", { label = "Big", items = {
        { type = "toggle", key = "big", label = "Go big", default = false },
    } })
    local skinned = me.RegisterSkin("BigPluginAddon", function() end)
    -- 1.3: a look on the frames, a text, a setting, a hook.
    local painted = 0
    T.truthy(me.Paint("unit", function() painted = painted + 1 end, { owns = { "healthFill" } }), "Paint")
    T.eq(me.AddText("big", { label = "Big", on = { "identity" }, text = function() return "B" end }), true, "AddText")
    T.eq(me.AddDefaults("UnitFrames", { bigGlow = true }), true, "AddDefaults")
    local hook = me.Hook(DUI.Style, "Accent", function() end)
    T.truthy(hook, "Hook")
    me.Unhook(hook)
    T.truthy(me.Wrap(DUI.Style, "Pop", function(orig, ...) return orig(...) end), "Wrap")
    T.eq(type(skinned), "boolean", "RegisterSkin answers true or false")

    stub.FireEvent("PLAYER_LOGIN")
    stub.RunTimers()
    local page, card = DUI.Options.GetPage("appearance")
    for _, g in ipairs(page.groups) do if string.find(g.label, "Big", 1, true) then card = g end end
    T.truthy(card, "the options group landed")
    T.eq(#card.items, 1)
    DUI.Options.Set(page, card.items[1], true)
    T.eq(DUI:Get("BigPlugin", "big"), true, "its row saves in its own scope")
    DUI.NotifyStyleChanged()
    stub.RunTimers()

    -- Lookups and the look kit.
    API.GetUnitFrame("player"); API.GetNameplate("nameplate1"); API.GetActionButton(1, 1)
    for _ in API.Frames("unit") do end
    API.GetSetting("general", "accent"); API.IsModuleEnabled("UnitFrames")
    local tile = CreateFrame("Frame", nil, UIParent)
    DaylightUI.APIReport.Made("raid", tile, "raid1", false)
    local holder = API.Attach(tile)
    T.truthy(holder, "a holder on Daylight UI's frame")
    T.eq(API.Attach(tile), holder, "one holder, kept")
    T.isnil(API.Attach(mine), "none on the plugin's own frame")
    API.Skin(mine, { window = true })
    API.Text(mine, "small"); API.Bar(mine); API.Accent(); API.Colors(); API.Font(); API.ClassColor("PRIEST")
    API.Fade(mine, 0.5, "FAST")
    API.Button(mine, "Go", 22); API.Close(mine, function() end); API.Switch(mine); API.Input(mine, {})

    -- A party fight in a restricted match.
    stub.SetGroup(true, false)
    stub.EnterCombat()
    stub.SetRestriction("PvPMatch", true)
    local plate = CreateFrame("Frame", nil, UIParent)
    local plateLog = {}
    for _, ev in ipairs({ "FrameMade", "FrameUnitChanged", "FrameRemoved" }) do
        me.On(ev, function(_, f) if f == plate then plateLog[#plateLog + 1] = ev end end)
    end
    DaylightUI.APIReport.Made("nameplate", plate, nil, false)
    DaylightUI.APIReport.Unit("nameplate", plate, "nameplate1", false)
    DaylightUI.APIReport.Styled("nameplate", plate, false)
    API.Attach(plate)
    DaylightUI.APIReport.Unit("nameplate", plate, "nameplate2", false)
    DaylightUI.APIReport.Gone("nameplate", plate, false)
    DUI.Fire("TestModeChanged"); DUI.Fire("UnlockChanged")
    stub.SetRestriction("PvPMatch", false)
    stub.LeaveCombat()
    stub.RunTimers()

    T.eq(log.FrameMade > 0 and log.FrameUnitChanged > 0 and log.FrameRemoved > 0 and log.FrameStyled > 0, true,
        "every frame event arrived")
    T.eq(log.Login >= 1, true, "Login")
    T.eq(log.TestModeChanged >= 1 and log.UnlockChanged >= 1, true)
    T.eq(log.SettingChanged >= 1, true, "SettingChanged")
    T.eq(log.StyleChanged >= 1, true, "StyleChanged")
    T.eq(after > 0, true, "a handler after the broken one still ran")
    -- A plate's events in order: made, a unit, goodbye to it before the next, then gone.
    T.eq(table.concat(plateLog, ","),
        "FrameMade,FrameUnitChanged,FrameRemoved,FrameUnitChanged,FrameRemoved")
    T.truthy(#stub.errors >= 1, "the broken handler was reported")
    for i, e in ipairs(stub.errors) do T.truthy(string.find(tostring(e), "plugin bug", 1, true) or string.find(tostring(e), "BigPlugin", 1, true), "only its own error: " .. tostring(e)) end
end)

T.test("api promise: RegisterSkin runs the skin when that addon loads, and says false without the Skins", function()
    local DUI = stub.Load({ skins = true, before = function()
        _G.DaylightUIDB = { modules = { NPC = { enabled = false }, Professions = { enabled = false }, Social = { enabled = false } } }
    end })
    stub.RunTimers()
    local me = DUI.API.For("SkinPlugin")
    local got
    T.eq(me.RegisterSkin("SkinTarget", function(Kit) got = Kit end), true)
    stub.RunTimers()
    T.isnil(got, "not before the addon loads")
    stub.installedAddOns.SkinTarget = true
    stub.loadedAddOns.SkinTarget = true
    stub.FireEvent("ADDON_LOADED", "SkinTarget")
    stub.RunTimers()
    T.eq(type(got), "table", "called with the Kit")
    T.eq(me.RegisterSkin(nil, function() end), false)
    T.eq(me.RegisterSkin("X", nil), false)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))

    local DUI2 = stub.Load({ login = false })
    DUI2.Skins = nil
    T.eq(DUI2.API.For("Lonely").RegisterSkin("Anything", function() end), false, "Skins not there: false, no error")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A plugin's name sorts before DaylightUI_Skins, so the game loads it first.
T.test("api promise: RegisterSkin from a plugin that loads before the Skins waits for them", function()
    local DUI = stub.Load({ login = false, before = function()
        _G.DaylightUIDB = { modules = { NPC = { enabled = false }, Professions = { enabled = false }, Social = { enabled = false } } }
    end })
    stub.installedAddOns.DaylightUI_Skins = true
    stub.addonState.DaylightUI_Skins = { ["*"] = true }
    local me = DUI.API.For("EarlyPlugin")
    local got
    T.eq(me.RegisterSkin("EarlyTarget", function(Kit) got = Kit end), true, "Skins on and coming: kept")
    T.eq(me.RegisterSkin("EarlyTarget", function() end), true, "asked twice: still once")
    stub.loadedAddOns.DaylightUI_Skins = true
    local SK = {}
    stub.LoadFiles("DaylightUI_Skins/", stub.SKINS_FILES, "DaylightUI_Skins", SK)
    stub.FireEvent("ADDON_LOADED", "DaylightUI_Skins")
    local n = 0
    for _, def in ipairs(SK.Engine.skins) do if def.key == "plugin.EarlyPlugin.EarlyTarget" then n = n + 1 end end
    T.eq(n, 1, "handed to the Skins as they load, once")
    stub.FireEvent("PLAYER_LOGIN")
    stub.RunTimers()
    stub.installedAddOns.EarlyTarget = true
    stub.loadedAddOns.EarlyTarget = true
    stub.FireEvent("ADDON_LOADED", "EarlyTarget")
    stub.RunTimers()
    T.eq(type(got), "table", "called with the Kit once the Skins came")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))

    -- Installed but switched off for this character: false.
    local DUI3 = stub.Load({ login = false })
    DUI3.Skins = nil
    stub.installedAddOns.DaylightUI_Skins = true
    stub.addonState.DaylightUI_Skins = { ["*"] = false }
    T.eq(DUI3.API.For("Off").RegisterSkin("Anything", function() end), false, "Skins switched off: false")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
