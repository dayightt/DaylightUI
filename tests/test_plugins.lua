local stub = require("stub")

-- Plugins (Plugins.lua): other people's addons built on DaylightUI, each with one
-- or more modules under its own name. As in game, a plugin loads after the core
-- and before login, so here the core loads, the plugin registers, then login fires.

local function withPlugin(register)
    local DUI = stub.Load({ login = false })
    register(DUI)
    stub.FireEvent("PLAYER_LOGIN")
    DUI.Fade.SkipIntro()
    return DUI
end

-- A small plugin module: one page, one setting.
local function barsModule(name, plugin, extra)
    local def = { plugin = plugin, label = "Bars", defaults = { size = 4 },
        options = { pages = { { id = "main", label = "Bars", desc = "The plugin's bars.",
            groups = { { label = "Size", items = { { type = "slider", key = "size", label = "Bar size",
                min = 1, max = 10, step = 1, desc = "How big the bars are." } } } } } } } }
    for k, v in pairs(extra or {}) do def[k] = v end
    return def
end

local function sectionOf(DUI, id)
    for _, s in ipairs(DUI.Options.Sections()) do
        if s.id == id then return s end
    end
end

T.test("plugins: what a plugin is comes from its .toc when it doesn't say, color codes taken out", function()
    local DUI = withPlugin(function(DUI)
        stub.addonMeta.MyPlugin = { Title = "|cff33ff99My|r Plugin", Author = "Ann", Version = "2.1",
            ["X-Website"] = "example.com/my", Notes = "Bars and more." }
        DUI.RegisterPlugin("MyPlugin")
    end)
    local p = DUI.Plugins.list.MyPlugin
    T.eq(p.title, "My Plugin")
    T.eq(p.author, "Ann")
    T.eq(p.version, "2.1")
    T.eq(p.website, "example.com/my")
    T.eq(p.desc, "Bars and more.")
    T.falsy(p.off, "made for this DaylightUI")
end)

T.test("plugins: a plugin's modules get its own section under the Plugins heading, their settings in the profile", function()
    local DUI = withPlugin(function(DUI)
        DaylightUI:RegisterPlugin("MyPlugin", { title = "My Plugin", author = "Ann", needs = { 1, 0 },
            icon = "Interface\\AddOns\\MyPlugin\\icon.png", color = "66cc99", short = "Mine" })
        DaylightUI:RegisterModule("MyBars", barsModule("MyBars", "MyPlugin"))
    end)
    local s = sectionOf(DUI, "plugin:MyPlugin")
    T.truthy(s, "its own section")
    T.eq(s.plugin, "MyPlugin")
    T.eq(s.pages[1].id, "MyBars.main", "the module's page in it")
    T.isnil(sectionOf(DUI, "MyBars"), "not a section of the module's own")
    local last = DUI.Options.Sections()
    T.eq(last[#last].id, "plugin:MyPlugin", "after all of ours")
    T.eq(DUI:Get("MyBars", "size"), 4)
    DUI:Set("MyBars", "size", 7)
    T.eq(DUI.DB.Active().modules.MyBars.size, 7, "kept in the profile, as ours are")
    T.eq(DUI.OptionsTheme.Section("plugin:MyPlugin").short, "Mine")
    T.eq(DUI.OptionsTheme.IconFile("Interface\\AddOns\\MyPlugin\\icon.png"), "Interface\\AddOns\\MyPlugin\\icon.png",
        "its own icon file")
    T.truthy(string.find(DUI.OptionsTheme.IconFile("home"), "ui-section-home", 1, true), "ours by name")
    -- The rail: the heading over the plugin's button.
    local Panel = DUI.OptionsPanel
    Panel.Show("home")
    local head, b = Panel.Nav().pluginsHead, Panel.NavButton("plugin:MyPlugin")
    T.truthy(head and head:IsShown(), "the Plugins heading")
    T.eq(stub.Text(head.text), "Plugins")
    T.truthy(b:IsShown())
    T.truthy(select(5, head:GetPoint()) > select(5, b:GetPoint()), "above the plugin's button")
    T.falsy(stub.ChatContains("Options ("), "its pages are valid")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("plugins: without one, no heading and no Plugins page", function()
    local DUI = stub.Load()
    local Panel = DUI.OptionsPanel
    Panel.Show("home")
    local head = Panel.Nav().pluginsHead
    T.truthy(head == nil or not head:IsShown(), "no heading")
    T.isnil(DUI.Options.GetPage("plugins"), "no page")
end)

T.test("plugins: one that needs a newer DaylightUI, or was made for an older one, stays off and says so", function()
    local api = { major = 1, minor = 0 }
    for _, case in ipairs({ { needs = { 1, 5 }, says = "newer" }, { needs = "2.0", says = "newer" },
                            { needs = 0, says = "older" } }) do
        local DUI = withPlugin(function(DUI)
            DUI.API.major, DUI.API.minor = api.major, api.minor
            DUI.RegisterPlugin("Later", { title = "Later Plugin", needs = case.needs })
            DUI:RegisterModule("LaterBars", barsModule("LaterBars", "Later"))
        end)
        local p = DUI.Plugins.list.Later
        T.truthy(p.off, "off")
        T.truthy(stub.ChatContains("Later Plugin"), "one line, naming it")
        T.truthy(string.find(p.why, case.says, 1, true), case.says)
        T.falsy(DUI:GetModule("LaterBars").enabled, "its module stays off")
        T.isnil(sectionOf(DUI, "plugin:Later"), "no section")
        T.eq(#stub.errors, 0, "never an error")
    end
end)

T.test("plugins: a mistake in the call is an error; a module naming a plugin that never registered is shown on its own", function()
    local DUI = withPlugin(function(DUI)
        T.errors(function() DUI.RegisterPlugin() end, "no name")
        DUI.RegisterPlugin("Once")
        T.errors(function() DUI.RegisterPlugin("Once") end, "the same name twice")
        T.errors(function() DUI.RegisterPlugin("Bad", "nope") end, "a string for its table")
        DUI:RegisterModule("Lost", barsModule("Lost", "NoSuchPlugin"))
    end)
    T.truthy(stub.ChatContains("NoSuchPlugin"), "said")
    T.truthy(DUI:GetModule("Lost").enabled, "still on")
    T.truthy(sectionOf(DUI, "Lost"), "in a section of its own")
end)

T.test("plugins: an error in a plugin's own code says the plugin's name", function()
    local DUI = withPlugin(function(DUI)
        DUI.RegisterPlugin("Oops", { title = "Oops UI" })
        DUI:RegisterModule("OopsBars", barsModule("OopsBars", "Oops", {
            OnEnable = function() error("broke") end,
            OnStyleChanged = function() error("broke again") end }))
        DUI:RegisterModule("Fine", barsModule("Fine", nil, { OnEnable = function() error("ours") end }))
    end)
    local plugin, ours
    for _, e in ipairs(stub.errors) do
        if string.find(e, "broke", 1, true) then plugin = e end
        if string.find(e, "ours", 1, true) then ours = e end
    end
    T.truthy(plugin and string.find(plugin, "^Oops UI: "), "starts with the plugin's name: " .. tostring(plugin))
    T.truthy(ours and not string.find(ours, "^Oops UI"), "a module of no plugin as before")
end)

T.test("plugins: General > Plugins lists every plugin and pack with who made it; Open goes to the plugin's pages", function()
    local DUI = withPlugin(function(DUI)
        DUI.RegisterPlugin("MyPlugin", { title = "My Plugin", author = "Ann", version = "2.1", website = "example.com/my" })
        DUI:RegisterModule("MyBars", barsModule("MyBars", "MyPlugin"))
        DUI.RegisterPlugin("Later", { title = "Later Plugin", needs = { 9, 0 } })
        DUI.RegisterPack("Pack", { label = "Pack UI", author = "Bo", profiles = { { name = "Pack UI", data = {} } } })
    end)
    local page = DUI.Options.GetPage("plugins")
    T.truthy(page, "the page")
    local labels = {}
    for i, g in ipairs(page.groups) do labels[i] = g.label end
    T.deq(labels, { "My Plugin", "Later Plugin", "Pack UI" })
    T.truthy(string.find(page.groups[1].desc, "By Ann. Version 2.1.", 1, true), "credited")
    T.truthy(string.find(page.groups[3].desc, "By Bo.", 1, true))
    local open = page.groups[1].items[1]
    T.eq(open.text, "Open")
    T.falsy(DUI.Options.IsHidden(page, open))
    T.truthy(string.find(page.groups[2].items[1].label(), "newer", 1, true), "why it's off")
    open.func()
    T.eq(DUI.OptionsPanel.Current(), "MyBars.main", "on the plugin's page")
    T.falsy(stub.ChatContains("Options ("), "the page is valid")
end)

-- DaylightUI.API 1.3: each plugin's card has a switch to turn it off for this
-- character (needs a reload) and a line on what it changes.
local function rowOf(group, kind)
    for _, it in ipairs(group.items) do if it.type == kind then return it end end
end

T.test("plugins page: a switch turns a plugin off for this character", function()
    local DUI = withPlugin(function(DUI)
        stub.installedAddOns.Neon = true
        stub.loadedAddOns.Neon = true
        DUI.RegisterPlugin("Neon", { title = "Neon" })
    end)
    local page = DUI.Options.GetPage("plugins")
    local sw = rowOf(page.groups[1], "toggle")
    T.truthy(sw, "a switch")
    T.eq(sw.reload, true, "takes a reload")
    T.eq(sw.get(), true, "on")
    sw.set(false)
    T.eq(stub.addonState.Neon[UnitGUID("player")], false, "off for this character")
    T.eq(sw.get(), false)
    T.falsy(stub.ChatContains("Options ("), "the page is valid")
end)

T.test("plugins page: a line says what a plugin changes", function()
    local DUI = withPlugin(function(DUI)
        DUI.RegisterPlugin("Neon", { title = "Neon" })
        local me = DUI.API.For("Neon")
        me.AddText("a", { label = "A", text = function() return "" end })
        me.Hook(DUI.Style, "Accent", function() end)
        me.Hook(DUI.Style, "Pop", function() end)
    end)
    DUI.APIReport.Parts("castbar", function() return {} end)   -- no unit frames loaded here
    local me = DUI.API.For("Neon")
    me.Paint("castbar", function() end)
    local page = DUI.Options.GetPage("plugins")
    local line
    for _, it in ipairs(page.groups[1].items) do
        if it.type == "text" and type(it.label) == "function" and string.find(it.label() or "", "Hooks", 1, true) then line = it.label() end
    end
    T.truthy(line, "the line")
    T.truthy(string.find(line, "Paints cast bars.", 1, true), line)
    T.truthy(string.find(line, "Adds 1 text.", 1, true), line)
    T.truthy(string.find(line, "Hooks 2 functions.", 1, true), line)
end)

T.test("plugins page: an addon that changes things without registering gets a card", function()
    local DUI = withPlugin(function(DUI)
        DUI.RegisterPlugin("Neon", { title = "Neon" })
    end)
    stub.installedAddOns.Loose = true
    DUI.APIReport.Parts("castbar", function() return {} end)   -- no unit frames loaded here
    DUI.API.For("Loose").Paint("castbar", function() end)
    DUI.API.For("NotAnAddon").Paint("castbar", function() end)
    local page = DUI.Options.GetPage("plugins")
    local byLabel = {}
    for _, g in ipairs(page.groups) do byLabel[g.label] = g end
    T.truthy(byLabel.Loose, "its card")
    T.falsy(DUI.Options.IsHidden(page, rowOf(byLabel.Loose, "toggle")), "an installed addon: a switch")
    T.truthy(byLabel.NotAnAddon, "a card")
    T.truthy(DUI.Options.IsHidden(page, rowOf(byLabel.NotAnAddon, "toggle")), "not an addon: no switch")
end)
