local stub = require("stub")
local PW = require("panelworld")

-- The clash box (Clashes.lua): another addon doing a part of Daylight UI's
-- job is asked about at login, one row per part, one reload for all.

local ME = function() return UnitGUID("player") end

-- A set-up character with these modules and these other addons loaded.
local function login(opts, others, before)
    opts = opts or {}
    local extra = opts.before
    opts.before = function()
        _G.C_Container = _G.C_Container or setmetatable({}, { __index = function() return function() end end })
        if before then before() end
        if extra then extra() end
    end
    local DUI = stub.Load(opts)
    for _, a in ipairs(others or {}) do stub.loadedAddOns[a] = true; stub.installedAddOns[a] = true end
    DUI.Installer.Mark("installed")
    DUI.Installer.MarkSeen()
    stub.Dismiss()
    return DUI
end

local function lines() return DaylightUIAsk.preview.lines end
local function chips(line)
    local out = {}
    for _, c in ipairs(line.chips) do if c:IsShown() then out[c.key] = c end end
    return out
end
local function click(chip) chip:GetScript("OnClick")(chip, "LeftButton") end
local function off(addon) return stub.addonState[addon] and stub.addonState[addon][ME()] == false end

T.test("clashes: Platynator with Daylight UI's nameplates asks once at login", function()
    local DUI = login({ nameplates = true }, { "Platynator" })
    stub.RunTimers()
    T.eq(stub.Asked(), "clashes")
    T.eq(#DUI.Clashes.rows, 1)
    T.eq(lines()[1].label:GetText(), "Nameplates")
    local c = chips(lines()[1])
    T.truthy(c.ours and c.Platynator, "Daylight UI and Platynator to pick from")
    T.truthy(c.ours.on, "Daylight UI picked to start with")
    T.falsy(c.Platynator.on)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("clashes: Daylight UI's pick turns Platynator off for this character and reloads", function()
    login({ nameplates = true }, { "Platynator" })
    stub.RunTimers()
    stub.ClickReload()
    T.truthy(off("Platynator"), "Platynator off")
    T.falsy(off("DaylightUI_Nameplates"), "Daylight UI's nameplates stay")
    T.isnil(stub.Asked())
end)

T.test("clashes: Platynator's pick turns Daylight UI's nameplates off", function()
    login({ nameplates = true }, { "Platynator" })
    stub.RunTimers()
    click(chips(lines()[1]).Platynator)
    T.truthy(chips(lines()[1]).Platynator.on)
    T.falsy(chips(lines()[1]).ours.on)
    stub.ClickReload()
    T.truthy(off("DaylightUI_Nameplates"), "Daylight UI's nameplates off")
    T.falsy(off("Platynator"), "Platynator stays")
end)

T.test("clashes: two nameplate addons make one row; picking Plater turns off the other two", function()
    login({ nameplates = true }, { "Platynator", "Plater" })
    stub.RunTimers()
    T.eq(#lines(), 1)
    local c = chips(lines()[1])
    T.truthy(c.ours and c.Platynator and c.Plater, "three chips")
    T.eq(DaylightUIAsk.foot.buttons[2].text:GetText(), "Keep all")
    click(c.Plater)
    stub.ClickReload()
    T.truthy(off("DaylightUI_Nameplates")); T.truthy(off("Platynator")); T.falsy(off("Plater"))
end)

T.test("clashes: a part's clash turns off its setting, not the module", function()
    local DUI = login({ module = true }, { "Grid2" })
    stub.RunTimers()
    T.eq(lines()[1].label:GetText(), "Party and raid frames")
    click(chips(lines()[1]).Grid2)
    stub.ClickReload()
    T.falsy(off("DaylightUI_UnitFrames"), "the unit frames stay on")
    T.eq(DUI:Get("UnitFrames", "raid.enabled"), false)
    T.eq(DUI:Get("UnitFrames", "party.enabled"), false)
    T.falsy(off("Grid2"))
    T.eq(#DUI.Clashes.Due(), 0, "no clash once those are off")
end)

T.test("clashes: EllesmereUI Cooldown Manager never turns off the action bars", function()
    local DUI = login({ actionbars = true }, { "EllesmereUICooldownManager" })
    stub.RunTimers()
    T.eq(lines()[1].label:GetText(), "Cooldown Manager icons")
    click(chips(lines()[1]).EllesmereUICooldownManager)
    stub.ClickReload()
    T.falsy(off("DaylightUI_ActionBars"))
    T.eq(DUI:Get("ActionBars", "cooldowns"), false)
end)

T.test("clashes: Keep both is remembered; a new addon still asks", function()
    local DUI = login({ nameplates = true, bags = true }, { "Platynator" })
    stub.RunTimers()
    T.eq(DaylightUIAsk.foot.buttons[2].text:GetText(), "Keep both")
    stub.Answer(false)
    T.falsy(off("Platynator")); T.falsy(off("DaylightUI_Nameplates"))
    T.truthy(DUI.DB.Root().clashKept.Platynator)
    T.isnil(stub.Asked())
    stub.loadedAddOns.Baganator = true
    T.truthy(DUI.Clashes.Show(), "Baganator is new")
    T.eq(#DUI.Clashes.rows, 1)
    T.eq(DUI.Clashes.rows[1].what, "bags")
end)

T.test("clashes: Escape asks again next login and saves nothing", function()
    local DUI = login({ nameplates = true }, { "Platynator" })
    stub.RunTimers()
    DUI.Widgets.CloseAsk()
    T.isnil(stub.Asked())
    T.isnil(DUI.DB.Root().clashKept)
    T.falsy(off("Platynator")); T.falsy(off("DaylightUI_Nameplates"))
    T.truthy(DUI.Clashes.Show(), "asked again")
end)

T.test("clashes: at login in a fight it waits for the fight to end", function()
    login({ nameplates = true }, { "Platynator" })
    stub.EnterCombat()
    stub.RunTimers()
    T.isnil(stub.Asked(), "not in a fight")
    stub.LeaveCombat()
    stub.RunTimers()
    T.eq(stub.Asked(), "clashes")
end)

T.test("clashes: no box before the character is set up; waits for the setup guide", function()
    local DUI = stub.Load({ nameplates = true })
    stub.loadedAddOns.Platynator = true
    stub.Dismiss()
    stub.RunTimers()
    T.isnil(stub.Asked(), "the setup guide asks itself")
    DUI = login({ nameplates = true }, { "Platynator" })
    DUI.InstallerUI.Open()
    T.truthy(DUI.InstallerUI.IsShown())
    for _ = 1, 3 do stub.RunTimersOnce() end
    T.isnil(stub.Asked(), "not over the guide")
    DUI.InstallerUI.Frame():Hide()
    stub.RunTimers()
    T.eq(stub.Asked(), "clashes")
end)

T.test("clashes: Leatrix Plus counts only while its chat or minimap options are on", function()
    local DUI = login({ chat = true, infopanel = true }, { "Leatrix_Plus" }, function()
        PW.world()
        _G.LeaPlusDB = { NoChatFade = "Off", MinimapModder = "Off" }
    end)
    T.eq(#DUI.Clashes.Due(), 0, "all off: no clash")
    _G.LeaPlusDB.NoChatFade = "On"
    local rows = DUI.Clashes.Due()
    T.eq(#rows, 1); T.eq(rows[1].what, "chat")
    _G.LeaPlusDB.MinimapModder = "On"
    T.eq(#DUI.Clashes.Due(), 2, "chat and minimap")
    _G.LeaPlusDB = nil
end)

-- Every entry: its part names one Daylight UI side, its settings exist, and
-- with every module and every listed addon loaded, every part gets a row.
T.test("clashes: every listed addon gets a row for its part", function()
    local DUI = login({ module = true, actionbars = true, buffs = true, skins = true, bags = true, nameplates = true,
        chat = true, infopanel = true, quests = true, tooltip = true }, nil, function()
        PW.world()
        _G.LeaPlusDB = { NoChatFade = "On", MinimapModder = "On" }
    end)
    DUI:Set("InfoPanel", "meter.enabled", true)   -- folded away by default
    local P = DUI.InstallerPages
    local side, whats = {}, {}
    for _, c in ipairs(P.CLASHES) do
        stub.loadedAddOns[c.addon] = true
        local key = c.core and "core" or c.settings and (c.settings[1][1] .. "." .. c.settings[1][2]) or c.module
        T.eq(side[c.what] or key, key, c.addon .. ": one Daylight UI side per part")
        side[c.what] = key
        whats[c.what] = true
        for _, s in ipairs(c.settings or {}) do
            T.truthy(DUI:Get(s[1], s[2]) ~= nil, c.addon .. ": setting " .. s[1] .. " " .. s[2] .. " exists")
        end
        T.truthy(c.core or c.settings or P.Module(c.module), c.addon .. ": a module the guide knows")
    end
    local got = {}
    for _, row in ipairs(DUI.Clashes.Due()) do got[row.what] = #row.addons end
    for what in pairs(whats) do T.truthy(got[what], "a row for " .. what) end
    T.truthy(DUI.Clashes.Show())
    T.eq(#lines(), #DUI.Clashes.rows)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.LeaPlusDB = nil
end)
