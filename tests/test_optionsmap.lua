-- The options map (/dui optionsmap): every setting as the window shows it.
local stub = require("stub")

local ALL = { module = true, actionbars = true, buffs = true, bags = true, nameplates = true, tooltip = true,
              qol = true, chat = true, infopanel = true, skins = true, quests = true }

T.test("every value row on every page is in the map, with its path", function()
    local DUI = stub.Load(ALL)
    local settings, errors = DUI.OptionsMap.Build()
    T.eq(#errors, 0, table.concat(errors, "; "))
    local seen = {}
    for _, e in ipairs(settings) do
        T.truthy(type(e.path) == "string" and e.path:find(e.label, 1, true), "path ends in the label: " .. tostring(e.path))
        T.truthy(e.rail and e.page and e.type, "rail, page and type for " .. e.path)
        if e.key then seen[e.scope .. ":" .. e.key] = true end
    end
    for _, s in ipairs(DUI.Options.Sections(true)) do
        for _, page in ipairs(s.pages) do
            for _, group in ipairs(page.groups) do
                for _, item in ipairs(group.items) do
                    if item.key and DUI.Options.VALUE[item.type] then
                        local k = (group.module or page.scope) .. ":" .. DUI.Options.Key(page, item.key)
                        T.truthy(seen[k], "mapped " .. k)
                    end
                end
            end
        end
    end
end)

T.test("the rail name is the one drawn on the rail, not the section's title", function()
    local DUI = stub.Load(ALL)
    local settings = DUI.OptionsMap.Build()
    local rails = {}
    for _, e in ipairs(settings) do
        if e.module and e.module.name == "ActionBars" then rails[e.rail] = e.section end
    end
    T.eq(rails["Bars"], "Action Bars")
end)

T.test("dropdowns list their choices as shown, sliders their range, rows their module", function()
    local DUI = stub.Load(ALL)
    stub.installedAddOns["DaylightUI_UnitFrames"] = true
    local settings = DUI.OptionsMap.Build()
    local drop, slider
    for _, e in ipairs(settings) do
        if not drop and e.type == "dropdown" and not e.choicesVary and e.choices and #e.choices > 1 then drop = e end
        if not slider and e.type == "slider" then slider = e end
    end
    T.truthy(drop, "a fixed dropdown")
    for _, c in ipairs(drop.choices) do T.truthy(type(c.key) == "string" and type(c.text) == "string", drop.path) end
    T.truthy(slider.min < slider.max, slider.path)
    local frame
    for _, e in ipairs(settings) do
        if e.scope == "UnitFrames" then frame = e; break end
    end
    T.eq(frame.module.addon, "DaylightUI_UnitFrames")
end)

T.test("picker rows name their pick, window cards name their module", function()
    local DUI = stub.Load(ALL)
    local settings = DUI.OptionsMap.Build()
    local picked, carded
    for _, e in ipairs(settings) do
        if e.pick and not picked then picked = e end
        if e.page == "More windows" and e.module and not carded then carded = e end
    end
    T.truthy(picked and picked.path:find(picked.pick, 1, true), "pick in the path")
    T.truthy(carded, "a More windows row")
    T.eq(carded.module.addon, "DaylightUI")
end)

T.test("search texts follow the search box; noSearch rows say so", function()
    local DUI = stub.Load(ALL)
    local O = DUI.Options
    O.RegisterSection("mapTest", "Map test", 999)
    O.RegisterPage({ id = "mapTest.p", section = "mapTest", label = "Page", scope = "general", defaults = {},
        hidden = function() return true end,
        groups = { { label = "Card", items = {
            { type = "button", label = "Go", text = "Run", desc = "Does it.", func = function() end },
            { type = "button", label = "Quiet", noSearch = true, func = function() end },
            { type = "text", label = "Just words" },
        } } } })
    local rows = {}
    for _, e in ipairs(DUI.OptionsMap.Build()) do
        if e.section == "Map test" then rows[#rows + 1] = e end
    end
    T.eq(#rows, 2, "text rows are left out")
    T.deq(rows[1].search, { "Go", "Does it.", "Run", "Card" })
    T.eq(rows[1].button, "Run")
    T.eq(rows[1].pageConditional, true, "a hidden page is listed and marked")
    T.eq(rows[2].searchable, false)
end)

T.test("/dui optionsmap saves the map to its saved variable", function()
    local DUI = stub.Load(ALL)
    _G.DaylightUIOptionsMap = nil
    DUI.RunCommand("optionsmap")
    local map = _G.DaylightUIOptionsMap
    T.truthy(map and #map.settings > 100, "settings saved")
    T.eq(map.version, DUI.VERSION)
    _G.DaylightUIOptionsMap = nil
end)
