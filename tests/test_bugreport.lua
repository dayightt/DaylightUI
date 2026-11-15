local stub = require("stub")

-- /dui bug: the filled-in report a player copies into the Discord forum.

-- The game's AddOns list: the two calls the fake game leaves out.
local function addons(names)
    _G.C_AddOns.GetNumAddOns = function() return #names end
    _G.C_AddOns.GetAddOnInfo = function(i) return names[i] end
end

local function load()
    stub.Load({})
    addons({ "Questie", "DaylightUI", "DaylightUI_Chat", "DaylightMogul", "Baganator", "NotLoaded" })
    stub.loadedAddOns.Questie, stub.loadedAddOns.Baganator, stub.loadedAddOns.DaylightMogul = true, true, true
    return DaylightUI.BugReport
end

T.test("bug report: the other loaded addons, A to Z, without Daylight UI's own folders", function()
    local Bug = load()
    T.eq(table.concat(Bug.Addons(), ","), "Baganator,DaylightMogul,Questie")
end)

T.test("bug report: no addon list on a client without one", function()
    local Bug = load()
    _G.C_AddOns.GetNumAddOns = nil
    T.eq(#Bug.Addons(), 0)
    T.eq(Bug.Fields()[2].text, "None", "as the form's own hint puts it")
end)

T.test("bug report: one answer for each box of the Discord form, and no name", function()
    local Bug = load()
    stub.physW, stub.physH = 2560, 1440
    local f = Bug.Fields()
    T.eq(#f, 3)
    T.eq(f[1].text, tostring(DaylightUI.VERSION), "the version alone")
    T.eq(f[2].text, "Baganator, DaylightMogul, Questie", "the other addons")
    T.truthy(string.find(f[3].text, "screen 2560x1440 at UI scale ", 1, true), "the screen")
    T.truthy(string.find(f[3].text, "modules off: None", 1, true), "nothing switched off")
    for i = 1, #f do
        T.eq(string.find(f[i].text, UnitName("player"), 1, true), nil, "the character's name stays out")
    end
    T.eq(string.find(f[1].text .. f[2].text, "\n", 1, true), nil, "one line each, for the one-line boxes")
end)

T.test("bug report: a module switched off shows in the setup line", function()
    local Bug = load()
    local on = Bug.Modules()
    local mod = DaylightUI:GetModule(on[1])
    mod.enabled = false
    local _, off = Bug.Modules()
    T.eq(off[1], on[1])
    T.truthy(string.find(Bug.Setup(), "modules off: " .. on[1], 1, true))
    mod.enabled = true
end)

-- The game keeps a copy of a few nameplate settings, and an addon writing one
-- leaves that copy tainted until /reload: suspected of stopping every plate.
T.test("bug report: a tainted copy of the game's plate settings shows in the setup line, by whom", function()
    local Bug = load()
    local reg, secure = _G.CVarCallbackRegistry, _G.issecurevariable
    T.eq(string.find(Bug.Setup(), "plate settings", 1, true), nil, "nothing to say without the game's copy")
    _G.CVarCallbackRegistry = { cvarValueCache = { SoftTargetIconInteract = "1", nameplateStyle = "0" } }
    local tainted = {}
    _G.issecurevariable = function(_, key)
        if tainted[key] then return false, tainted[key] end
        return true
    end
    T.eq(string.find(Bug.Setup(), "plate settings", 1, true), nil, "all clean: the line stays short")
    tainted.SoftTargetIconInteract = "Lueur"
    T.truthy(string.find(Bug.Setup(), "plate settings tainted: SoftTargetIconInteract by Lueur", 1, true))
    _G.issecurevariable = function() error("no") end
    T.eq(string.find(Bug.Setup(), "plate settings", 1, true), nil, "an error asking says nothing")
    _G.CVarCallbackRegistry, _G.issecurevariable = reg, secure
end)

T.test("bug report: /dui bug opens a box per field, each read-only and selected on a click", function()
    local Bug = load()
    DaylightUI.RunCommand("bug")
    local box = _G.DaylightUIBugReport
    T.truthy(box:IsShown(), "shown")
    local f = Bug.Fields()
    T.eq(#box.rows, #f)
    for i, row in ipairs(box.rows) do
        T.eq(row.label:GetText(), f[i].label)
        T.eq(row.edit.__text, f[i].text)
    end
    -- Typing over a box puts its text back.
    local edit = box.rows[2].edit
    edit:SetText("typed over")
    edit:GetScript("OnTextChanged")(edit, true)
    T.eq(edit.__text, f[2].text, "read-only")
    DaylightUI.RunCommand("bug")
    T.eq(_G.DaylightUIBugReport, box, "the same window the second time")
end)

T.test("bug report: the options home page has a Report a bug button beside its chips", function()
    load()
    local Panel = DaylightUI.OptionsPanel
    Panel.Show("home")
    local b = Panel.BugButton()
    T.truthy(b:IsShown(), "on the home page")
    T.truthy(Panel.Chips():IsShown(), "next to the chips")
    b:GetScript("OnClick")(b)
    T.truthy(_G.DaylightUIBugReport:IsShown(), "it opens the report")
    T.falsy(Panel.IsShown(), "and the options close, out of its way")
    Panel.Show("appearance")
    T.falsy(b:IsShown(), "only on the home page")
end)

-- Errors: a report is about one bug, so the last box carries one error.

local function boom(text, times)
    for _ = 1, times or 1 do DaylightUI.SafeCall(function() error(text) end) end
end

T.test("bug report: each error is kept once with its count, the latest last, and the oldest drop off", function()
    load()
    boom("first", 3)
    boom("second")
    boom("first")
    local log = DaylightUI.Errors()
    T.eq(#log, 2)
    T.truthy(string.find(log[1].text, "second", 1, true), "second is now the older one")
    T.truthy(string.find(log[2].text, "first", 1, true), "first happened again, so it's the latest")
    T.eq(log[2].count, 4)
    for i = 1, DaylightUI.ERROR_LOG_MAX + 5 do boom("flood " .. i) end
    T.eq(#DaylightUI.Errors(), DaylightUI.ERROR_LOG_MAX, "capped")
end)

T.test("bug report: a blocked action is kept as an error", function()
    load()
    stub.FireEvent("ADDON_ACTION_BLOCKED", "DaylightUI_Chat", "GuildInvite()")
    stub.FireEvent("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "Thing()")
    local log = DaylightUI.Errors()
    T.eq(#log, 1, "only Daylight UI's")
    T.eq(log[1].text, "the game blocked GuildInvite() (DaylightUI_Chat)")
end)

T.test("bug report: the last box opens on the latest error and steps one at a time", function()
    local Bug = load()
    boom("older")
    boom("newer", 2)
    DaylightUI.RunCommand("bug")
    local box = _G.DaylightUIBugReport
    local edit = box.rows[3].edit
    T.truthy(string.find(edit.__text, "newer (x2)\n", 1, true), "the latest and its count, on its own line")
    T.truthy(string.find(edit.__text, "\n[Game ", 1, true), "then the setup")
    T.eq(string.find(edit.__text, "older", 1, true), nil, "one error a report")
    T.truthy(box.prev:IsShown() and box.next:IsShown(), "arrows with more than one")
    T.eq(box.count:GetText(), "2 of 2")
    Bug.Step(-1)
    T.truthy(string.find(edit.__text, "older\n", 1, true), "the one before")
    T.eq(box.count:GetText(), "1 of 2")
    Bug.Step(-1)
    T.eq(box.count:GetText(), "1 of 2", "stops at the first")
end)

T.test("bug report: with no error the last box is the setup alone and the arrows are away", function()
    local Bug = load()
    DaylightUI.RunCommand("bug")
    local box = _G.DaylightUIBugReport
    T.eq(box.rows[3].edit.__text, Bug.Setup())
    T.falsy(box.prev:IsShown())
    T.falsy(box.count:IsShown())
end)

T.test("bug report: with BugGrabber, its Daylight UI errors of this session, repeats folded", function()
    local Bug = load()
    for _ = 1, 12 do DaylightUI.SafeCall(function() error("Interface/AddOns/DaylightUI/Fade.lua:1: ours", 0) end) end
    local key = DaylightUI.Errors()[1].text
    _G.BugGrabber = {
        GetSessionId = function() return 7 end,
        GetDB = function() return {
            { message = "Interface/AddOns/DaylightUI_Bags/Bag.lua:5: old session", session = 6, counter = 1 },
            { message = "Interface/AddOns/Questie/Q.lua:9: not ours", session = 7, counter = 4 },
            { message = "Interface/FrameXML/Game.lua:3: bad argument", session = 7, counter = 2,
              stack = "Interface/AddOns/DaylightUI_Chat/Box.lua:961: in function" },
            { message = key .. "\nstack", session = 7, counter = 1 },
            { message = "Interface/AddOns/DaylightUI_Bags/Bag.lua:5: plain handler", session = 7, counter = 3 },
            { message = "(seen 10 times) " .. key .. "\nstack", session = 7, counter = 1 },
        } end,
    }
    local e = Bug.Errors()
    _G.BugGrabber = nil
    T.eq(#e, 3, "this session's, Daylight UI's, each once")
    T.eq(e[1].text, "Interface/FrameXML/Game.lua:3: bad argument", "ours by its stack alone")
    T.eq(e[2].text, "Interface/AddOns/DaylightUI_Bags/Bag.lua:5: plain handler")
    T.eq(e[2].count, 3, "BugGrabber's count")
    T.eq(e[3].text, key, "ours, at its latest spot")
    T.eq(e[3].count, 12, "our own count")
end)

T.test("bug report: an addon list too long for the form's box is cut at a whole name, the rest counted", function()
    local Bug = load()
    local names = {}
    for i = 1, 40 do names[i] = "SomeLongAddonName" .. i end
    local short = Bug.Short(names)
    T.truthy(#short <= Bug.ADDONS_MAX, "fits the box: " .. #short)
    local shown = select(2, string.gsub(short, "SomeLongAddonName", ""))
    T.truthy(string.find(short, " +" .. (40 - shown) .. " more", 1, true), "says how many were left out")
    T.eq(string.sub(short, 1, 18), "SomeLongAddonName1")
    T.eq(Bug.Short({ "Questie", "Baganator" }), "Questie, Baganator", "a short list is left alone")
end)

T.test("bug report: a long list spends its room on whole addons, their parts and helpers aside", function()
    local Bug = load()
    T.eq(table.concat(Bug.Main({ "!BugGrabber", "Questie", "Spoken", "Spoken_Quests", "Zygor_Data" }), ","),
        "Questie,Spoken,Zygor_Data,!BugGrabber", "a part without its addon loaded stays")
    local names = { "!Helper" }
    for i = 1, 20 do
        names[#names + 1] = "Pack" .. i
        names[#names + 1] = "Pack" .. i .. "_Data"
    end
    local short = Bug.Short(names)
    T.eq(string.find(short, "_Data", 1, true), nil, "no parts")
    T.eq(string.sub(short, 1, 5), "Pack1", "helpers aren't first")
end)

T.test("bug report: the last box is the error and the setup, never the addon list", function()
    local Bug = load()
    local names = {}
    for i = 1, 40 do
        names[i] = "SomeLongAddonName" .. i
        stub.loadedAddOns[names[i]] = true
    end
    addons(names)
    local f = Bug.Fields()
    T.truthy(#f[2].text <= Bug.ADDONS_MAX)
    T.eq(f[3].text, Bug.Setup())
end)

T.test("bug report: an error brings the calls nearest it, not the whole stack", function()
    local Bug = load()
    local stack = {}
    for i = 1, 30 do stack[i] = "Interface/AddOns/DaylightUI/File.lua:" .. i .. ": in function" end
    DaylightUI.SafeCall(function() error("deep\n" .. table.concat(stack, "\n"), 0) end)
    local e = DaylightUI.Errors()[1]
    T.eq(e.text, "deep")
    local text = Bug.Fields(e)[3].text
    T.truthy(string.find(text, "File.lua:" .. Bug.STACK_LINES .. ": in function", 1, true), "the nearest calls")
    T.eq(string.find(text, "File.lua:" .. (Bug.STACK_LINES + 1) .. ": in function", 1, true), nil, "no further")
    T.truthy(#text < 4000, "fits the form's box")
end)

T.test("bug report: the window's list is its own, so an error repeating while it's open moves nothing", function()
    local Bug = load()
    boom("first")
    boom("second")
    T.truthy(Bug.Errors() ~= DaylightUI.Errors(), "a copy")
    DaylightUI.RunCommand("bug")
    local box = _G.DaylightUIBugReport
    local edit = box.rows[3].edit
    Bug.Step(-1)
    T.truthy(string.find(edit.__text, ": first\n", 1, true), "on the first")
    boom("first", 3)   -- the live log moves it to the end
    Bug.Step(1)
    T.truthy(string.find(edit.__text, ": second\n", 1, true), "the next one is still the second")
    T.eq(box.count:GetText(), "2 of 2")
end)

T.test("bug report: with BugGrabber, an error of ours that repeats is still the latest", function()
    local Bug = load()
    boom("A")
    boom("B")
    boom("A", 5)
    local own = DaylightUI.Errors()
    -- BugGrabber keeps each where it first saw it, and only counts the repeats.
    _G.BugGrabber = {
        GetSessionId = function() return 1 end,
        GetDB = function() return {
            { message = own[2].text .. "\nstack", session = 1, counter = 6 },
            { message = "Interface/AddOns/DaylightUI_Bags/Bag.lua:5: plain handler", session = 1, counter = 1 },
            { message = own[1].text .. "\nstack", session = 1, counter = 1 },
        } end,
    }
    local e = Bug.Errors()
    _G.BugGrabber = nil
    T.eq(#e, 3)
    T.truthy(string.find(e[1].text, "plain handler", 1, true), "BugGrabber's own first, where it saw it")
    T.truthy(string.find(e[2].text, ": B", 1, true))
    T.truthy(string.find(e[3].text, ": A", 1, true), "A happened last")
    T.eq(e[3].count, 6)
end)

T.test("bug report: with BugGrabber, its later error is the latest and a blocked action shows once", function()
    local Bug = load()
    boom("mine")
    stub.FireEvent("ADDON_ACTION_BLOCKED", "DaylightUI", "Thing()")
    local later = date("%Y/%m/%d %H:%M:%S", time() + 60)
    _G.BugGrabber = {
        GetSessionId = function() return 1 end,
        GetDB = function() return {
            { message = "[ADDON_ACTION_BLOCKED] AddOn 'DaylightUI' tried to call the protected function 'Thing()'.",
              session = 1, counter = 1, time = later },
            { message = "Interface/AddOns/DaylightUI_Bags/Bag.lua:5: after", session = 1, counter = 1, time = later },
        } end,
    }
    local e = Bug.Errors()
    _G.BugGrabber = nil
    T.eq(#e, 3, "the blocked action once, in its own words")
    T.truthy(string.find(e[3].text, ": after", 1, true), "BugGrabber's error came last, so it's the latest")
end)

T.test("bug report: with BugGrabber, another addon's error inside something of ours isn't ours", function()
    local Bug = load()
    -- A callback's error: their file in the message, ours only further down the stack.
    _G.BugGrabber = {
        GetSessionId = function() return 1 end,
        GetDB = function() return {
            { message = "Interface/AddOns/Other/Core.lua:9: theirs", session = 1, counter = 1,
              stack = "Interface/AddOns/Other/Core.lua:9: in function\nInterface/AddOns/DaylightUI/Core.lua:300: in function" },
            { message = "Interface/FrameXML/Game.lua:3: bad argument", session = 1, counter = 1,
              stack = "Interface/AddOns/DaylightUI_Chat/Box.lua:961: in function\n[C]: ?" },
        } end,
    }
    local e = Bug.Errors()
    _G.BugGrabber = nil
    T.eq(#e, 1)
    T.eq(e[1].text, "Interface/FrameXML/Game.lua:3: bad argument", "ours when we're the top of its stack")
end)

T.test("bug report: BugGrabber's list is read once, however long", function()
    local Bug = load()
    local db = {}
    for i = 1, 400 do
        db[i] = { message = "Interface/AddOns/DaylightUI/Fade.lua:" .. (i % 40) .. ": many", session = 1, counter = 2 }
    end
    _G.BugGrabber = { GetSessionId = function() return 1 end, GetDB = function() return db end }
    local e = Bug.Errors()
    _G.BugGrabber = nil
    T.eq(#e, 40, "one entry a message")
    T.eq(e[1].count, 20, "its repeats added up")
end)
