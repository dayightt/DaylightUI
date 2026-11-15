local stub = require("stub")

-- DaylightUI.API 1.6: the info panel. Plugins add data texts (any slot can
-- show them), data panels of their own (slots on a frame of theirs, picked
-- with Shift+right-click), and read and paint the damage meters.

local PW = require("panelworld")

local function load()
    local DUI = PW.login()
    return DUI.API, stub.infopanel
end

local function fishText(me, state)
    return me.AddDataText("fish", {
        label = "Fish", events = { "BAG_UPDATE_DELAYED" },
        text = function() return "Fish", tostring(state.n) end,
        tooltip = function(tip) tip.Line("Caught", tostring(state.n)) end,
        click = function(button) state.clicked = button end,
    })
end

local function slotText(s) return s.text:GetText() or "" end

T.test("api info: a plugin's data text shows in a slot, redraws on its events and asks", function()
    local API, ns = load()
    local me = API.For("Angler")
    local state = { n = 3 }
    T.eq(fishText(me, state), true)
    local DT = ns.DataTexts
    T.truthy(DT.TEXTS["Angler:fish"], "in the texts")
    T.eq(DT.NAMES["Angler:fish"], "Fish", "named in the slot menus")
    DaylightUI:Set("InfoPanel", "data.enabled", true)
    DaylightUI:Set("InfoPanel", "data.slot1", "Angler:fish")
    stub.RunTimers()
    PW.settle()
    local s = DT.slots[1]
    T.eq(s.key, "Angler:fish")
    T.truthy(string.find(slotText(s), "3", 1, true), "its value")
    state.n = 4
    stub.FireEvent("BAG_UPDATE_DELAYED")
    T.truthy(string.find(slotText(s), "4", 1, true), "redrawn on its event")
    state.n = 9
    me.UpdateDataText("fish")
    T.truthy(string.find(slotText(s), "9", 1, true), "redrawn when it asks")
    s:GetScript("OnClick")(s, "LeftButton")
    T.eq(state.clicked, "LeftButton")
    T.eq(me.AddDataText("bad", { label = "x" }), false, "a text function is needed")
end)

T.test("api info: an error in a plugin's text is named and the strip keeps going", function()
    local API, ns = load()
    local me = API.For("Broken")
    me.AddDataText("boom", { label = "Boom", text = function() error("nope") end })
    DaylightUI:Set("InfoPanel", "data.enabled", true)
    DaylightUI:Set("InfoPanel", "data.slot1", "Broken:boom")
    DaylightUI:Set("InfoPanel", "data.slot2", "gold")
    stub.RunTimers()
    local named = false
    for _, line in ipairs(stub.errors) do if string.find(line, "Broken", 1, true) then named = true end end
    T.truthy(named, "the error names the plugin")
    T.truthy(ns.DataTexts.slots[2]:IsShown(), "the gold text still shows")
end)

T.test("api info: a data panel lays slots on the plugin's frame, picked with Shift+right-click", function()
    local API, ns = load()
    local me = API.For("Angler")
    fishText(me, { n = 2 })
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(300, 20)
    T.eq(me.AddDataPanel("bar", f, { count = 3, slots = { "gold", "Angler:fish" } }), true)
    stub.RunTimers()
    local p = ns.Broker.panels["Angler:bar"]
    T.truthy(p, "made")
    local slots = p.strip.slots
    T.eq(slots[1].key, "gold")
    T.eq(slots[2].key, "Angler:fish")
    T.eq(slots[3].key, ns.Broker.EMPTY, "an empty slot waits for a pick")
    T.eq(slots[1]:GetParent(), f, "on the plugin's frame")
    -- Shift+right-click opens the menu; picking saves it.
    local shift = _G.IsShiftKeyDown
    _G.IsShiftKeyDown = function() return true end
    local picked
    local open = DaylightUI.Widgets.OpenMenu
    DaylightUI.Widgets.OpenMenu = function(_, keys, _, _, onPick) picked = keys; onPick("bags") end
    slots[3]:GetScript("OnClick")(slots[3], "RightButton")
    DaylightUI.Widgets.OpenMenu, _G.IsShiftKeyDown = open, shift
    T.truthy(picked and #picked > 3, "every text offered")
    T.eq(p.strip.slots[3].key, "bags")
    T.eq(stub.infopanel.module.db.data.panels["Angler:bar"].slot3, "bags", "kept in the settings")
    T.eq(me.AddDataPanel("x", "not a frame"), false)
end)

T.test("api info: meter windows, modes and what a window shows", function()
    local API, ns = load()
    local wins = API.MeterWindows()
    T.eq(wins[1].id, "main"); T.eq(wins[1].kind, "meter"); T.eq(wins[1].mode, "damage")
    T.eq(wins[2].id, "threat")
    T.truthy(API.GetMeterWindow("main"), "the panel's meter")
    local modes = API.MeterModes()
    T.eq(modes[1].key, "damage")
    stub.meter.sources = {
        { name = "Teft", classFilename = "WARRIOR", totalAmount = 5000, amountPerSecond = 50, isLocalPlayer = true },
        { name = "Rock", classFilename = "HUNTER", totalAmount = 2500, amountPerSecond = 25 },
    }
    local rows = API.MeterRows("main")
    T.eq(#rows, 2)
    T.eq(rows[1].name, "Teft"); T.eq(rows[1].rank, 1); T.eq(rows[1].amount, 5000)
    T.eq(rows[1].isMine, true); T.eq(rows[2].class, "HUNTER")
    T.eq(API.SetMeterMode("main", "healing"), true)
    T.eq(DaylightUI:Get("InfoPanel", "meter.mode"), "healing")
    T.eq(API.SetMeterMode("main", "nope"), false)
    T.eq(API.SetMeterMode("threat", "damage"), false, "only meters have modes")
    local reset = 0
    API.On("MeterReset", function() reset = reset + 1 end)
    T.eq(API.ResetMeters(), true)
    T.eq(reset, 1)
    local opened
    local open = ns.BreakdownWindow.Open
    ns.BreakdownWindow.Open = function(_, src) opened = src end
    DaylightUI:Set("InfoPanel", "meter.mode", "damage")
    T.eq(API.OpenMeterBreakdown("main", 2), true)
    ns.BreakdownWindow.Open = open
    T.eq(opened and opened.name, "Rock")
end)

T.test("api info: fight start and end", function()
    local API = load()
    local log = {}
    API.On("MeterFightStarted", function() log[#log + 1] = "start" end)
    API.On("MeterFightEnded", function(sec) log[#log + 1] = "end" end)
    stub.EnterCombat()
    stub.LeaveCombat()
    stub.RunTimers()
    T.eq(log[1], "start"); T.eq(log[2], "end")
end)

T.test("api info: meter rows are painted with who they show; claimed colors stay the plugin's", function()
    local API, ns = load()
    local M = ns.Meter
    stub.meter.sources = {
        { name = "Teft", classFilename = "WARRIOR", totalAmount = 5000 },
        { name = "Rock", classFilename = "HUNTER", totalAmount = 2500 },
    }
    M.Draw()
    local calls = {}
    local h = API.For("Skinner").Paint("meterrow", function(row, parts, info)
        calls[#calls + 1] = info
        parts.name:SetTextColor(0, 1, 0)
        parts.fill:SetVertexColor(1, 0, 1)
    end, { owns = { "name", "fill" } })
    T.truthy(#calls >= 2, "painted at once")
    local row = PW.bars(ns.Panel.meterArea)[1]
    T.eq(API.Parts(row).name, row.name)
    calls = {}
    M.Draw()
    T.eq(#calls, 0, "nothing new: no paint")
    stub.meter.sources[1], stub.meter.sources[2] = stub.meter.sources[2], stub.meter.sources[1]
    M.Draw()
    T.truthy(#calls >= 2, "someone else in each row")
    local first
    for _, i in ipairs(calls) do if i.rank == 1 then first = i end end
    T.eq(first.name, "Rock"); T.eq(first.window, "main"); T.eq(first.mode, "damage")
    local r, g = row.name:GetTextColor()
    T.eq(r, 0); T.eq(g, 1)
    API.Off(h)
    r = row.name:GetTextColor()
    T.truthy(r ~= 0, "Daylight UI's colors back")
end)
