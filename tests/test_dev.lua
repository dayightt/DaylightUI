local stub = require("stub")   -- T (test helpers) is a global set by tests/run.lua

-- Needs the local-only DaylightUI_Dev folder.
if not T.dev then return end

-- The dev tools (DaylightUI_Dev, never shipped): /dui report and /dui perf. They
-- load after the core like the real addon would. The fake game has no addon list,
-- profiler or mouse focus, so each test brings its own and puts the old ones back.

local FILES = { "Report.lua", "Perf.lua", "PlateCost.lua", "AuraProbe.lua", "CdmBarProbe.lua", "ClockProbe.lua", "TargetTrace.lua", "Spikes.lua", "Garbage.lua", "Mem.lua", "CdmProbe.lua", "BagProbe.lua", "RingProbe.lua", "QuestXPProbe.lua", "ClickProbe.lua", "BookProbe.lua", "InviteProbe.lua", "GroupProbe.lua", "TipProbe.lua", "InspectProbe.lua", "CraftProbe.lua", "LfgProbe.lua", "MailProbe.lua", "SocialProbe.lua", "LegacyProbe.lua", "NavProbe.lua", "PadLog.lua", "MapProbe.lua", "HookProbe.lua", "BoxProbe.lua", "Waiting.lua", "Locale.lua" }

local function loadDev()
    local ns = {}
    for _, f in ipairs(FILES) do
        local chunk = assert(loadfile("DaylightUI_Dev/" .. f))
        chunk("DaylightUI_Dev", ns)
    end
    return ns
end

-- Sets globals for one test and returns a function that puts them back.
local function with(globals)
    local old = {}
    for k, v in pairs(globals) do old[k] = { v = _G[k] }; _G[k] = v end
    return function() for k, o in pairs(old) do _G[k] = o.v end end
end

local function addonList(names)
    local A = {}
    for k, v in pairs(C_AddOns) do A[k] = v end
    A.GetNumAddOns = function() return #names end
    A.GetAddOnInfo = function(i) return names[i] end
    A.IsAddOnLoaded = function() return true end
    return A
end

T.test("dev: every file is in the .toc", function()
    local f = assert(io.open("DaylightUI_Dev/DaylightUI_Dev.toc"))
    local toc = f:read("*a"); f:close()
    for _, file in ipairs(FILES) do T.truthy(toc:find(file, 1, true), file .. " in the .toc") end
    T.truthy(toc:find("## SavedVariables: DaylightUIDevDB", 1, true), "its own saved variables")
    T.truthy(toc:find("## Dependencies: DaylightUI", 1, true), "loads after the core")
end)

T.test("dev: the folder is never in a release", function()
    local f = assert(io.open(".pkgmeta"))
    local meta = f:read("*a"); f:close()
    T.truthy(meta:find("\n%s*%- DaylightUI_Dev%s*\n"), ".pkgmeta ignores DaylightUI_Dev")
    T.falsy(meta:find("DaylightUI/DaylightUI_Dev:", 1, true), "and doesn't move it out as a module")
end)

T.test("dev: /dui report keeps the frames under the mouse and the setup", function()
    local DUI = stub.Load({ module = true })
    _G.DaylightUIDevDB = nil
    loadDev()
    local thing = CreateFrame("Frame", "DaylightUITestThing", UIParent)
    thing:SetSize(40, 20)
    thing:SetPoint("CENTER", UIParent, "CENTER", 5, -3)
    local undo = with({ GetMouseFoci = function() return { thing } end, C_AddOns = addonList({ "DaylightUI", "Details" }) })
    DUI.RunCommand("report the bar looks off")
    undo()
    local r = DaylightUIDevDB.reports[1]
    T.eq(r.note, "the bar looks off")
    T.eq(#r.frames, 1)
    T.eq(r.frames[1].name, "DaylightUITestThing")
    T.eq(r.frames[1].size, "40 x 20")
    T.truthy(r.frames[1].ours, "ours")
    T.truthy(r.frames[1].points[1]:find("CENTER", 1, true), "its anchor")
    T.deq(r.addons, { "Details" }, "other addons only")
    T.eq(r.modules.UnitFrames, true)
    T.eq(type(r.settings), "table", "the settings that differ from the defaults")
    T.truthy(stub.ChatContains("Report saved"), "said so")
end)

T.test("dev: /dui report keeps only the newest few", function()
    local DUI = stub.Load()
    _G.DaylightUIDevDB = nil
    local ns = loadDev()
    for i = 1, ns.Report.KEEP + 2 do DUI.RunCommand("report " .. i) end
    T.eq(#DaylightUIDevDB.reports, ns.Report.KEEP)
    T.eq(DaylightUIDevDB.reports[1].note, tostring(ns.Report.KEEP + 2), "newest first")
end)

T.test("dev: /dui report names secret values and never touches them", function()
    local DUI = stub.Load()
    _G.DaylightUIDevDB = nil
    local ns = loadDev()
    T.eq(ns.Report.Show(stub.Secret(5)), "secret")
    T.eq(ns.Report.Show(1.234), "1.23")
    T.eq(ns.Report.Show(12), "12")
    local text = UIParent:CreateFontString(nil, "OVERLAY")
    text.GetText = function() return stub.Secret("Bob") end
    local undo = with({ GetMouseFoci = function() return { text } end })
    DUI.RunCommand("report")
    undo()
    T.eq(DaylightUIDevDB.reports[1].frames[1].text, "secret")
end)

T.test("dev: /dui report survives a frame that refuses every call", function()
    local DUI = stub.Load()
    _G.DaylightUIDevDB = nil
    loadDev()
    local locked = setmetatable({}, { __index = function() error("calling on bad self") end })
    local undo = with({ GetMouseFoci = function() return { locked } end })
    DUI.RunCommand("report")
    undo()
    T.eq(#DaylightUIDevDB.reports[1].frames, 1, "still written down")
end)

-- "DaylightUI updated its layout" came up at login now and then, cause unknown.
-- Each reload prompt over the layout logs which parts found it out of date,
-- before the write.
T.test("dev: a reload prompt over the Edit Mode layout logs which part asked", function()
    local DUI = stub.Load()
    _G.DaylightUIDevDB = nil
    local ns = loadDev()
    local EM = DUI.EditMode
    EM.Add("fine", function() end, function() return true end)
    EM.Add("drifted", function() end, function() return false end)
    local ours = EM.Ours
    EM.Ours = function() return { layoutName = "DaylightUI - DPS/Tank", systems = {} } end
    EM.Save("DaylightUI updated its layout.")
    EM.Ours = ours
    local e = DaylightUIDevDB.editModeLog[1]
    T.eq(e.stale, "drifted", "only the part that found it out of date")
    T.eq(e.text, "DaylightUI updated its layout.")
    T.eq(e.group, "solo")
    T.eq(type(ns.Report.Build().editMode), "table", "/dui report has it too")
end)

T.test("dev: /dui report lists frames drawn under the mouse that don't take it, smallest first", function()
    local DUI = stub.Load()
    _G.DaylightUIDevDB = nil
    loadDev()
    local veil = CreateFrame("Frame", "DaylightUITestVeil", UIParent)
    veil:SetAllPoints(UIParent)
    local box = CreateFrame("Frame", "DaylightUITestBox", UIParent)
    box:SetSize(200, 600)
    box:SetPoint("TOPRIGHT")
    local away = CreateFrame("Frame", "DaylightUITestAway", UIParent)
    away:SetSize(10, 10)
    local over = { [veil] = true, [box] = true }
    for _, f in ipairs({ veil, box, away }) do f.IsMouseOver = function(self) return over[self] == true end end
    local undo = with({ GetMouseFoci = function() return { veil } end })
    DUI.RunCommand("report")
    undo()
    local drawn = DaylightUIDevDB.reports[1].drawn
    T.eq(drawn[1].name, "DaylightUITestBox", "the box under the veil, first")
    for _, d in ipairs(drawn) do
        T.truthy(d.name ~= "DaylightUITestVeil", "the focus isn't listed twice")
        T.truthy(d.name ~= "DaylightUITestAway", "nor a frame the mouse isn't over")
    end
end)

-- In game a frame answered IsVisible with a secret, and comparing it broke the
-- report. Plain Lua can't make `secret == true` error, so this checks the frame is
-- skipped without being compared.
T.test("dev: /dui report skips frames that answer with secrets", function()
    local DUI = stub.Load()
    _G.DaylightUIDevDB = nil
    loadDev()
    local odd = CreateFrame("Frame", "DaylightUITestOdd", UIParent)
    odd:SetSize(10, 10)
    odd.IsVisible = function() return stub.Secret(true) end
    odd.IsMouseOver = function() return stub.Secret(true) end
    local undo = with({ GetMouseFoci = function() return {} end })
    DUI.RunCommand("report")
    undo()
    T.falsy(stub.ChatContains("report: failed"), "no failure")
    for _, d in ipairs(DaylightUIDevDB.reports[1].drawn) do
        T.truthy(d.name ~= "DaylightUITestOdd", "a secret answer counts as no")
    end
end)

T.test("dev: /dui perf times each of our addons from the client's profiler", function()
    local DUI = stub.Load({ module = true })
    _G.DaylightUIDevDB = nil
    loadDev()
    local E = { RecentAverageTime = 1, CountTimeOver5Ms = 6 }
    local times = { DaylightUI = 0.2, DaylightUI_UnitFrames = 0.5 }
    local slow = { DaylightUI = 0, DaylightUI_UnitFrames = 0 }
    local P = {
        IsEnabled = function() return true end,
        GetAddOnMetric = function(name, m) if m == E.CountTimeOver5Ms then return slow[name] end return times[name] end,
        GetOverallMetric = function(m) if m == E.CountTimeOver5Ms then return 0 end return 0.9 end,
    }
    local undo = with({ C_AddOnProfiler = P, Enum = setmetatable({ AddOnProfilerMetric = E }, { __index = Enum }),
        C_AddOns = addonList({ "DaylightUI", "DaylightUI_UnitFrames", "Details" }),
        GetFramerate = function() return 60 end })
    DUI.RunCommand("perf 2")
    DUI.RunCommand("perf 2")
    T.truthy(stub.ChatContains("already measuring"), "one run at a time")
    stub.RunTickers()
    times.DaylightUI_UnitFrames = 1.5
    slow.DaylightUI_UnitFrames = 3
    stub.RunTickers()
    stub.RunTickers()   -- the run already ended, so nothing more
    undo()
    local run = DaylightUIDevDB.perf[1]
    T.eq(run.seconds, 2)
    T.near(run.addons.DaylightUI_UnitFrames.avgMs, 1.0)
    T.near(run.addons.DaylightUI_UnitFrames.maxMs, 1.5)
    T.eq(run.addons.DaylightUI_UnitFrames.slowFrames, 3)
    T.near(run.addons.DaylightUI.avgMs, 0.2)
    T.isnil(run.addons.Details, "only ours")
    T.near(run.fps.avg, 60)
    T.truthy(stub.ChatContains("DaylightUI_UnitFrames: avg 1.000 ms"), "printed")
end)

T.test("dev: /dui perf without the profiler still gives frame rate", function()
    local DUI = stub.Load()
    _G.DaylightUIDevDB = nil
    loadDev()
    local undo = with({ C_AddOnProfiler = false, C_AddOns = addonList({ "DaylightUI" }), GetFramerate = function() return 30 end })
    DUI.RunCommand("perf 1")
    stub.RunTickers()
    undo()
    local run = DaylightUIDevDB.perf[1]
    T.eq(run.profiler, false)
    T.near(run.fps.min, 30)
    T.truthy(stub.ChatContains("profiler is off"), "said why")
end)

T.test("dev: /dui auras writes down the target's and the tiles' aura containers and the aura access", function()
    local DUI, UF = stub.Load({ module = true })
    _G.DaylightUIDevDB = nil
    loadDev()
    local b = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton9", UF.Raid.header)
    b:SetAttribute("unit", "raid3")
    stub.units.raid3 = { name = "Tavi", isPlayer = true, class = "DRUID", health = 10, maxHealth = 10 }
    UF.Raid.header.initialConfigFunction(UF.Raid.header, b:GetName())
    b:Show()
    stub.SetRestriction("PvPMatch", true)
    DUI.RunCommand("auras")
    stub.SetRestriction("PvPMatch", false)
    T.truthy(DaylightUIDevDB and DaylightUIDevDB.auraProbe, table.concat(stub.chat, "\n"))
    local lines = table.concat(DaylightUIDevDB.auraProbe[1], "\n")
    T.truthy(lines:find("PvPMatch", 1, true), "the restrictions on")
    T.truthy(lines:find("target debuffs:", 1, true), "the target's debuffs")
    T.truthy(lines:find("(raid3) dispel:", 1, true), "a tile's dispel icon")
    T.truthy(lines:find("api raid3:", 1, true), "whether addon code may read the tile's auras")
    T.falsy(stub.ChatContains("auras: failed"), "no failure")
end)

T.test("dev: /dui cdm alertprobe, alertadd, alertundo and stackprobe run against the game's alert manager", function()
    local DUI = stub.Load({ actionbars = true })
    _G.DaylightUIDevDB = nil
    loadDev()
    local D = stub.actionbars.CdmData
    D.AddPiece(D.Current(), 11, "icon", 0, 0)
    local added, saved = {}, 0
    local lm = {
        GetNumAlerts = function(_, id) return #(added[id] or {}) end,
        GetAlerts = function(_, id) return added[id] or {} end,
        AddAlert = function(_, id, a) added[id] = added[id] or {}; table.insert(added[id], a); return 0 end,
        RemoveAlert = function(_, id, a) for i, x in ipairs(added[id]) do if x == a then table.remove(added[id], i) end end end,
        SaveLayouts = function() saved = saved + 1 end,
    }
    local old = { S = _G.CooldownViewerSettings, CV = _G.C_CooldownViewer }
    _G.CooldownViewerSettings = { GetLayoutManager = function() return lm end }
    Enum.CooldownViewerAlertEventType = { Available = 1, PandemicTime = 2 }
    Enum.CooldownViewerAlertType = { Sound = 1, Visual = 2 }
    Enum.CooldownViewerSound = { InstrumentsChimeAscending = 35 }
    _G.CooldownViewerAlert_Create = function(t, e, p) return { t, e, p } end
    _G.CooldownViewerAlert_GetEvent = function(a) return a[2] end
    _G.C_CooldownViewer = setmetatable({ GetValidAlertTypes = function() return { 1, 2 } end }, { __index = old.CV })
    DUI.RunCommand("cdm alertprobe")
    DUI.RunCommand("cdm alertadd")
    T.truthy(added[11], table.concat(stub.chat, "\n"))
    T.eq(#added[11], 1, "one alert added"); T.eq(added[11][1][3], 35); T.eq(saved, 1, "the game's layout saved")
    T.eq(DaylightUIDevDB.cdmAlertAdded, 11)
    DUI.RunCommand("cdm alertundo")
    T.eq(#added[11], 0, "removed"); T.isnil(DaylightUIDevDB.cdmAlertAdded)
    DUI.RunCommand("cdm stackprobe")
    stub.RunTickers()
    T.truthy(DaylightUIDevDB.cdmAlerts and DaylightUIDevDB.cdmStacks, "saved")
    _G.CooldownViewerSettings, _G.C_CooldownViewer = old.S, old.CV
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("dev: /dui cdmbars writes down the spell's CDM family, the aura button's timer methods and test bars", function()
    local DUI = stub.Load()
    _G.DaylightUIDevDB = nil
    local ns = loadDev()
    -- Rend (772) filed as a cooldown, Mortal Strike (12294) cooling down.
    local names = { [772] = "Rend", [12294] = "Mortal Strike" }
    local old = { CV = _G.C_CooldownViewer, cats = Enum.CooldownViewerCategory, name = C_Spell.GetSpellName,
                  cd = C_Spell.GetSpellCooldown, dur = C_Spell.GetSpellCooldownDuration }
    Enum.CooldownViewerCategory = { Essential = 0, Utility = 1, TrackedBuff = 2, TrackedBar = 3 }
    _G.C_CooldownViewer = {
        GetCooldownViewerCategorySet = function(cat) return ({ [0] = { 5, 6 } })[cat] or {} end,
        GetCooldownViewerCooldownInfo = function(id)
            return ({ [5] = { spellID = 772, hasAura = true, selfAura = false, linkedSpellIDs = {} },
                      [6] = { spellID = 12294, hasAura = false, selfAura = false, linkedSpellIDs = {} } })[id]
        end,
    }
    C_Spell.GetSpellName = function(id) return names[id] end
    C_Spell.GetSpellCooldown = function(id) return { isActive = id == 12294, isOnGCD = false } end
    C_Spell.GetSpellCooldownDuration = function() return stub.Secret({}) end
    DUI.RunCommand("cdmbars")
    stub.RunTimers()
    _G.C_CooldownViewer, Enum.CooldownViewerCategory = old.CV, old.cats
    C_Spell.GetSpellName, C_Spell.GetSpellCooldown, C_Spell.GetSpellCooldownDuration = old.name, old.cd, old.dur
    T.falsy(stub.ChatContains("cdmbars: failed"), table.concat(stub.chat, "\n"))
    T.truthy(DaylightUIDevDB and DaylightUIDevDB.cdmBarProbe, "saved")
    local lines = table.concat(DaylightUIDevDB.cdmBarProbe[1], "\n")
    T.truthy(lines:find("Rend: cooldownID 5 spellID 772 filed under Essential (cooldown family: icon only)", 1, true), lines)
    T.truthy(lines:find("Rend spell ids for the filter: 772", 1, true), "the filter's ids")
    T.truthy(lines:find("Rend on the target, spell-id filter:", 1, true), "the filtered row read")
    T.truthy(lines:find("a cooldown as a bar: Mortal Strike:", 1, true), "the cooldown row picked the spell cooling down")
    T.truthy(lines:find("SetTimerDuration ok", 1, true), "the cooldown bar took the duration object")
    T.truthy(lines:find("SetDurationBar ok", 1, true), "the aura bar was taken: it sits inside the button")
    T.falsy(lines:find("bad object", 1, true), "nothing handed over from outside the button")
    T.truthy(lines:find("aura button methods", 1, true) and lines:find("SetDurationText", 1, true), "the button's timer methods")
    T.truthy(stub.ChatContains("CDM bar check saved"), "said so")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("dev perf: every frame's time gives the 1% low and the worst frame (a short dip the 1 s fps sample misses)", function()
    stub.Load()
    local ns = loadDev()
    local times = {}
    for i = 1, 199 do times[i] = 1 / 150 end
    times[200] = 1 / 20                               -- one 50 ms hitch
    local f = ns.Perf.FrameStats(times)
    T.eq(f.count, 200)
    T.near(f.worstMs, 50, 1e-9, "the hitch")
    T.near(f.low1, 1 / ((1 / 20 + 1 / 150) / 2), 1e-6, "the slowest 1% (2 frames), as fps")
    T.isnil(ns.Perf.FrameStats({}))
end)

T.test("dev perf camera: each part alone, then your camera, zoom and UI are back", function()
    stub.Load()
    local ns = loadDev()
    local Scene = DaylightUI.Npc.Scene
    local cv = { test_cameraOverShoulder = "0.5", test_cameraTargetFocusInteractStrengthPitch = "0" }
    local undo = with({ C_CVar = { GetCVar = function(n) return cv[n] end, SetCVar = function(n, v) cv[n] = v end } })
    stub.cameraZoom = 15
    local zoomed = {}
    local undoZoom = with({ CameraZoomIn = function(d) zoomed[#zoomed + 1] = d; stub.cameraZoom = stub.cameraZoom - d end,
        CameraZoomOut = function(d) zoomed[#zoomed + 1] = -d; stub.cameraZoom = stub.cameraZoom + d end })
    local run = assert(ns.Perf.Camera())
    local clock = ns.Perf.cameraClock
    local fadedTo, moved = 1, false
    for _ = 1, 500 do
        if clock.__scripts.OnUpdate then stub.RunOnUpdate(clock, 0.01) end
        local shoulder = tonumber(cv.test_cameraOverShoulder)
        if shoulder and shoulder ~= 0.5 then moved = true end
        fadedTo = math.min(fadedTo, UIParent:GetAlpha())
    end
    T.eq(#run.steps, #ns.Perf.CAMERA_STEPS, "every part measured")
    T.truthy(moved, "the settings really moved")
    T.truthy(fadedTo < 0.1, "the UI really faded")
    T.eq(zoomed[1], 15 - Scene.ZOOM)
    T.eq(zoomed[2], -(15 - Scene.ZOOM), "the zoom given back")
    T.eq(UIParent:GetAlpha(), 1)
    T.eq(cv.test_cameraOverShoulder, "0.5", "your camera back")
    T.eq(DaylightUIDB.npcCamera, nil)
    T.eq(DaylightUIDevDB.perfCamera, run)
    T.eq(#ns.Perf.CameraLines(run), #run.steps + 1)
    undoZoom(); undo()
    stub.cameraZoom = nil
end)

T.test("dev perf fade: names the dear pieces and leaves every alpha as it was", function()
    stub.Load()
    local ns = loadDev()
    local a = CreateFrame("Frame", "PerfFadeA", UIParent)
    a:SetAlpha(0.4)
    local b = CreateFrame("Frame", "PerfFadeB", a)
    b:SetAlpha(0)
    ns.Perf.FADE_TOP = 100000   -- every piece, since in the fake game they all cost nothing
    local lines = assert(ns.Perf.FadeCost())
    T.truthy(lines[1]:find("UIParent", 1, true))
    T.truthy(table.concat(lines, "\n"):find("PerfFadeA", 1, true), "the piece is listed")
    T.near(a:GetAlpha(), 0.4, 1e-9)
    T.eq(b:GetAlpha(), 0)
    T.eq(UIParent:GetAlpha(), 1)
    T.eq(DaylightUIDevDB.perfFade, lines)
end)

T.test("dev spikes: a slow frame names the addon that took it, Questie too, and the event before it", function()
    stub.Load({ module = true })
    local ns = loadDev()
    _G.DaylightUIDevDB = nil
    local E = { LastTime = 3 }
    local times = { DaylightUI = 0.2, Questie = 0.1 }
    local P = {
        IsEnabled = function() return true end,
        GetAddOnMetric = function(name) return times[name] end,
        GetOverallMetric = function() return times.DaylightUI + times.Questie end,
    }
    local undo = with({ C_AddOnProfiler = P, Enum = setmetatable({ AddOnProfilerMetric = E }, { __index = Enum }),
        C_AddOns = addonList({ "DaylightUI", "Questie" }) })
    local S = ns.Spikes
    T.eq(S.Start(10), 10)
    for _ = 1, 100 do stub.RunOnUpdate(S.clock, 1 / 100) end
    stub.FireEvent("UNIT_QUEST_LOG_CHANGED", "player")
    times.Questie = 40
    stub.RunOnUpdate(S.clock, 0.08)
    times.Questie = 0.1
    stub.RunOnUpdate(S.clock, 1 / 100)     -- the frame after isn't counted again
    stub.RunOnUpdate(S.clock, 1 / 100)
    S.Stop()
    undo()
    local lines = DaylightUIDevDB.spikes[1].lines
    T.truthy(lines[1]:find("^1 slow of 103 frames"), lines[1])
    T.truthy(lines[1]:find("1 right after a quest, loot, group or spell event", 1, true), lines[1])
    T.truthy(lines[2]:find("Questie 40", 1, true), lines[2])
    T.truthy(lines[3]:find("80 ms", 1, true) and lines[3]:find("Questie 40.0", 1, true), lines[3])
    T.truthy(lines[3]:find("game 40", 1, true), "what's left is the game's: " .. lines[3])
    T.truthy(lines[3]:find("after UNIT_QUEST_LOG_CHANGED", 1, true), lines[3])
    T.falsy(S.recording, "done")
    T.falsy(S.clock:GetScript("OnUpdate"), "costs nothing once it ends")
end)

T.test("dev spikes: says so when the profiler is off, and a steady game has no spikes", function()
    stub.Load({ module = true })
    local ns = loadDev()
    _G.DaylightUIDevDB = nil
    local S = ns.Spikes
    local undo = with({ C_AddOnProfiler = false })
    local started, why = S.Start(5)
    undo()
    T.falsy(started)
    T.truthy(why:find("profiler", 1, true), why)
    local E = { LastTime = 3 }
    undo = with({ C_AddOnProfiler = { GetAddOnMetric = function() return 0.1 end },
        Enum = setmetatable({ AddOnProfilerMetric = E }, { __index = Enum }), C_AddOns = addonList({ "Questie" }) })
    S.Start(1)
    for _ = 1, 200 do stub.RunOnUpdate(S.clock, 1 / 100) end   -- ends itself at 1 s
    undo()
    T.falsy(S.recording, "ended by itself")
    T.truthy(DaylightUIDevDB.spikes[1].lines[1]:find("^0 slow"), DaylightUIDevDB.spikes[1].lines[1])
end)

T.test("dev spikes load: watches the next load once, every slow frame counts though none is calm", function()
    stub.Load({ module = true })
    local ns = loadDev()
    _G.DaylightUIDevDB = {}
    local E = { LastTime = 3 }
    local undo = with({ C_AddOnProfiler = { GetAddOnMetric = function() return 12 end },
        Enum = setmetatable({ AddOnProfilerMetric = E }, { __index = Enum }), C_AddOns = addonList({ "Questie" }) })
    local S = ns.Spikes
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, true)
    T.falsy(S.recording, "not armed: a load costs nothing")
    DaylightUIDevDB.spikesLoad = true
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, false)
    T.falsy(S.recording, "a zone change isn't a load")
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, true)
    T.truthy(S.recording, "armed: the load is watched")
    T.falsy(DaylightUIDevDB.spikesLoad, "armed once, off for the load after")
    stub.RunOnUpdate(S.clock, 0.5)         -- the very first frame is the slow one
    stub.RunOnUpdate(S.clock, 0.1)
    stub.RunOnUpdate(S.clock, 1 / 100)
    S.Stop()
    undo()
    local lines = DaylightUIDevDB.spikes[1].lines
    T.truthy(lines[1]:find("^after a load: 2 slow of 3 frames"), lines[1])
    T.truthy(lines[3]:find("500 ms", 1, true), lines[3])
end)

T.test("dev targettrace: sums frames into half-second lines, from before the target change to after", function()
    stub.Load()
    local ns = loadDev()
    local frames = {}
    for i = 1, 90 do
        local after = i >= 30
        local slow = after and i < 60
        frames[i] = { at = (i - 30) / 60, dt = slow and 1 / 30 or 1 / 120, all = 2, moved = slow and 8 or 0, plates = 10,
            sweeping = slow and i <= 35, addons = { DaylightUI = 1.5, DaylightUI_Nameplates = 0.4 } }
    end
    local b = ns.TargetTrace.Summarize(frames, { "DaylightUI", "DaylightUI_Nameplates" })
    T.eq(b[1].from, -0.5, "starts before the target change")
    T.near(b[1].fps, 120, 0.5, "the frame rate before")
    T.near(b[2].fps, 30, 0.5, "the dip after")
    T.eq(b[2].movedAvg, 8, "plates moving")
    T.truthy(b[2].sweeping)
    local lines = ns.TargetTrace.Lines(b)
    T.truthy(lines[1]:find("^%-0%.5 to %+0%.0s"), lines[1])
    T.truthy(lines[3]:find("core 1.50", 1, true), lines[3])
    T.truthy(lines[3]:find("Nameplates 0.40", 1, true), lines[3])
end)

T.test("dev targettrace: keeps the 2 s before your target changes and the 5 s after, then prints", function()
    stub.Load()
    local ns = loadDev()
    _G.DaylightUIDevDB = nil
    local TT = ns.TargetTrace
    TT.Arm()
    for _ = 1, 600 do stub.RunOnUpdate(TT.clock, 1 / 100) end      -- 6 s of waiting
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    for _ = 1, 520 do stub.RunOnUpdate(TT.clock, 1 / 100) end
    local lines = DaylightUIDevDB.traces[1].lines
    T.truthy(lines[1]:find("^%-2%.0 to"), "starts 2 s before: " .. lines[1])
    T.truthy(lines[#lines]:find("^%+4%.5 to %+5%.0s"), "ends 5 s after: " .. lines[#lines])
    T.eq(#lines, 15, "14 half seconds and the line where you targeted")
    T.falsy(TT.recording, "done")
end)

T.test("dev targettrace: marks the moment you target, and counts the game's plates changing size", function()
    stub.Load()
    local ns = loadDev()
    local frames = {}
    for i = 1, 60 do
        frames[i] = { at = (i - 30) / 60, dt = 1 / 60, moved = 0, resized = i > 30 and 1 or 0, plates = 4, addons = {} }
    end
    local lines = ns.TargetTrace.Lines(ns.TargetTrace.Summarize(frames, {}))
    T.eq(lines[2], "---- you targeted here ----")
    T.truthy(lines[1]:find("game plates resizing 0.0", 1, true), lines[1])
    T.truthy(lines[3]:find("game plates resizing 1.0", 1, true), lines[3])
end)

T.test("dev garbage: counts what each of a module's functions allocates, then puts every function back", function()
    stub.Load({ buffs = true })
    local ns = loadDev()
    _G.DaylightUIDevDB = nil
    local BL = stub.buffs
    local learn, collect = BL.Bar.Learn, BL.Auras.CollectWeapons
    local n = ns.Garbage.Run("Buffs", 1)
    T.truthy(n and n > 20, "plenty of functions watched")
    T.truthy(BL.Bar.Learn ~= learn, "wrapped for the run")
    for _ = 1, 5 do stub.FireEvent("UNIT_AURA", "player") end
    BL.Auras.CollectWeapons(true)
    stub.RunOnUpdate(ns.Garbage.clock, 1.1)
    T.eq(BL.Bar.Learn, learn, "put back after")
    T.eq(BL.Auras.CollectWeapons, collect)
    local lines = DaylightUIDevDB.garbage[1].lines
    T.truthy(#lines > 0 and lines[1]:find("KB/s own", 1, true), lines[1])
    local all = table.concat(lines, "\n")
    T.truthy(all:find("Buffs.Auras:CollectWeapons", 1, true), all)
end)

T.test("dev mem: walks our namespaces and saved settings once each and names the biggest", function()
    local DUI = stub.Load({ buffs = true })
    local ns = loadDev()
    _G.DaylightUIDevDB = nil
    DUI.memProbeBig = {}
    for i = 1, 2000 do DUI.memProbeBig[i] = { "x" .. i } end
    DUI.memProbeAgain = DUI.memProbeBig            -- reached twice, counted once
    local lines = ns.Mem.Run()
    T.truthy(lines[1]:find("the walk reached", 1, true), lines[1])
    local all = table.concat(lines, "\n")
    local big, again = all:find("DUI.memProbeBig", 1, true), all:find("DUI.memProbeAgain", 1, true)
    T.truthy((big or again) and not (big and again), "a table reached twice is counted under one path only: " .. all)
    T.truthy(all:find("Buffs", 1, true), "module namespaces are walked")
    T.eq(DaylightUIDevDB.mem.lines, lines)
    DUI.memProbeBig, DUI.memProbeAgain = nil, nil
end)

T.test("dev: /dui l10n saves the mode, and it lands on DUI.L at the dev addon's load", function()
    local DUI = stub.Load({ module = true })
    _G.DaylightUIDevDB = nil
    local ns = loadDev()
    DUI.RunCommand("l10n pseudo")
    T.eq(DaylightUIDevDB.l10n, "pseudo")
    T.eq(DUI.L["Width"], "Width", "nothing changes before the reload")
    stub.FireEvent("ADDON_LOADED", "DaylightUI_Dev")
    T.eq(DUI.L["Width"], "«Width»")
    DUI.RunCommand("l10n off")
    T.isnil(DaylightUIDevDB.l10n)
    -- long: 40% more letters, accented, with codes and holes untouched.
    local long = ns.Locale.Lengthen("|cffaabbccRead|r %d of %s, 50%%")
    T.truthy(long:find("|cffaabbcc", 1, true) and long:find("|r", 1, true), "color codes kept")
    T.truthy(long:find("%d", 1, true) and long:find("%s", 1, true) and long:find("%%", 1, true), "holes kept")
    T.truthy(long:find("Réád", 1, true), "vowels accented")
    T.eq(string.format(long, 3, "x"):find("3", 1, true) ~= nil, true, "still formats")
end)

T.test("dev: /dui clockprobe runs and saves its lines", function()
    stub.Load{ actionbars = true }
    local ns = loadDev()
    local out = ns.ClockProbe.Run("Battle Shout")
    T.truthy(#out > 3, "lines written")
    stub.Advance(4); stub.RunTimers()
    T.truthy(type(DaylightUIDevDB) == "table" and DaylightUIDevDB.cdmBarProbe[1] == out, "saved with the CDM bar probe's runs")
end)

T.test("dev: /dui ccprobe prints what the click-cast binder sees", function()
    local DUI = stub.Load({ module = true })
    loadDev()
    T.noerror(function() DUI.RunCommand("ccprobe") end)
    T.truthy(stub.ChatContains("ccprobe:"), "prints to chat")
end)

-- The fake talent world a probe test needs: one tree, two nodes.
local function traitWorld(calls)
    local nodes = {
        [11] = { ID = 11, posX = 0, posY = 0, type = 0, flags = 0, maxRanks = 5, ranksPurchased = 0, activeRank = 0,
                 canPurchaseRank = true, canRefundRank = false, isAvailable = true, isVisible = true, meetsEdgeRequirements = true,
                 groupIDs = { 7 }, conditionIDs = {}, entryIDs = { 101 }, visibleEdges = { { targetNode = 12, type = 1, visualStyle = 1, isActive = false } } },
        [12] = { ID = 12, posX = 0, posY = 600, type = 0, flags = 0, maxRanks = 1, ranksPurchased = 1, activeRank = 1,
                 canPurchaseRank = false, canRefundRank = true, isAvailable = true, isVisible = true, meetsEdgeRequirements = true,
                 groupIDs = { 7 }, conditionIDs = { 5 }, entryIDs = { 102 }, visibleEdges = {} },
    }
    local function log(name) return function(...) calls[#calls + 1] = { name, ... }; return true end end
    return with({
        C_SpecializationInfo = { GetActiveSpecGroup = function() return 1 end, GetCombatConfigIDForSpecGroup = function(g) return g == 1 and 900 or nil end,
                                 CanPlayerUseTalentSpecUI = function() return true end, SetActiveSpecGroup = log("SetActiveSpecGroup") },
        GetNumSpecGroups = function() return 1 end,
        C_ClassTalents = { GetActiveConfigID = function() return 900 end, CanEditTalents = function() return true, "" end,
                           CanChangeTalents = function() return false, false, nil end, CommitConfig = log("ClassCommit") },
        C_Traits = {
            GetConfigInfo = function() return { ID = 900, type = 1, name = "x", treeIDs = { 50 } } end,
            CanEditConfig = function() return true, "" end,
            ConfigHasStagedChanges = function() return false end,
            GenerateImportString = function() return "ABC" end,
            GetLoadoutSerializationVersion = function() return 2 end,
            GetTreeInfo = function() return { ID = 50, gates = {} } end,
            GetTreeCurrencyInfo = function() return { { traitCurrencyID = 3, quantity = 4, maxQuantity = 10, spent = 6, spentInTree = 6 } } end,
            GetGroupDisplayInfoByTreeID = function() return { { groupID = 7, treeID = 50, displayName = "Arms", icon = 1, orderIndex = 1 } } end,
            GetGroupCurrencyInfo = function() return { { traitNodeGroupID = 7, currencyInfos = { { spent = 6 } } } } end,
            GetTreeNodes = function() return { 11, 12 } end,
            GetNodeInfo = function(_, id) return nodes[id] end,
            GetNodeCost = function() return { { ID = 3, amount = 1 } } end,
            GetEntryInfo = function(_, e) return { definitionID = e + 1000, type = 1, maxRanks = 5 } end,
            GetDefinitionInfo = function(d) return { spellID = d } end,
            GetConditionInfo = function() return { condID = 5, isGate = true, spentAmountRequired = 5 } end,
            CanPurchaseRank = function() return true end,
            CanRefundRank = function() return true end,
            PurchaseRank = log("PurchaseRank"), RefundRank = log("RefundRank"), RollbackConfig = log("RollbackConfig"),
            GetStagedChanges = function() return {} end,
        },
    })
end

T.test("dev: /dui bookprobe tree writes every node with its place, ranks and edges", function()
    stub.Load()
    _G.DaylightUIDevDB = nil
    local ns = loadDev()
    local undo = traitWorld({})
    ns.BookProbe.Run("tree")
    undo()
    local text = table.concat(DaylightUIDevDB.bookProbe[1], "\n")
    T.truthy(text:find("config 900", 1, true), "the active config")
    T.truthy(text:find("group 7 Arms", 1, true), "the tree's group")
    T.truthy(text:find("node 11 x=0 y=0", 1, true), "a node's place")
    T.truthy(text:find("edges 12:1:1:false", 1, true), "its edge")
    T.truthy(text:find("cond 5", 1, true), "a condition")
end)

T.test("dev: /dui bookprobe stage buys one rank and rolls it back", function()
    stub.Load()
    _G.DaylightUIDevDB = nil
    local ns = loadDev()
    local calls = {}
    local undo = traitWorld(calls)
    ns.BookProbe.Run("stage")
    undo()
    T.eq(calls[1][1], "PurchaseRank")
    T.eq(calls[1][3], 11, "the node the game says can be bought")
    T.eq(calls[#calls][1], "RollbackConfig", "nothing is spent")
end)

T.test("dev: /dui bookprobe survives a client without the talent calls", function()
    stub.Load()
    _G.DaylightUIDevDB = nil
    local ns = loadDev()
    local undo = with({ C_Traits = false, C_ClassTalents = false })
    T.noerror(function() ns.BookProbe.Run("tree") end)
    undo()
    T.truthy(table.concat(DaylightUIDevDB.bookProbe[1], "\n"):find("no C_Traits", 1, true))
end)

T.test("dev: /dui bookprobe securex makes a secure close button that clicks the game's X", function()
    stub.Load()
    _G.DaylightUIDevDB = nil
    local ns = loadDev()
    local book = CreateFrame("Frame", "PlayerSpellsFrame", UIParent)
    book.CloseButton = CreateFrame("Button", nil, book)
    book:Show()
    T.noerror(function() ns.BookProbe.Run("securex") end)
    local b = _G.DaylightUIDevBookClose
    T.truthy(b, "made")
    T.eq(b:GetAttribute("type"), "click")
    T.eq(b:GetAttribute("clickbutton"), book.CloseButton)
    T.truthy(b:IsShown(), "shown with the book")
    _G.PlayerSpellsFrame, _G.DaylightUIDevBookClose = nil, nil
end)

T.test("dev: /dui bookprobe handback parks the game's book and hands it back as a fight starts", function()
    stub.Load()
    _G.DaylightUIDevDB = nil
    local ns = loadDev()
    local book = CreateFrame("Frame", "PlayerSpellsFrame", UIParent)
    book:Hide()
    ns.BookProbe.Run("handback")
    T.truthy(book:GetParent() ~= UIParent, "parked out of combat")
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    T.eq(book:GetParent(), UIParent, "handed back as the fight starts")
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    local text = table.concat(DaylightUIDevDB.bookProbe[1], "\n")
    T.truthy(text:find("PLAYER_REGEN_DISABLED: InCombatLockdown=", 1, true), "the lockdown state in that moment is written")
    T.truthy(text:find("(done: /reload)", 1, true))
    _G.PlayerSpellsFrame = nil
end)

T.test("dev: /dui waiting saves each fight's answers and walks the hook probe", function()
    stub.Load({ module = true })
    _G.DaylightUIDevDB = nil
    local ns = loadDev()
    ns.Waiting.Run("")
    local w = DaylightUIDevDB.waiting
    T.truthy(w.on, "watching")
    T.eq(DaylightUIDevDB.hookProbe.mode, "read", "the hook probe's first kind is set")
    T.eq(#w.runs, 1)
    stub.EnterCombat()   -- fires PLAYER_REGEN_DISABLED
    T.eq(#w.combo, 1, "combo points written as the fight starts")
    T.truthy(w.lockdown[#w.lockdown].value:find("InChatMessagingLockdown", 1, true))
    T.eq(#w.attach, 1, "the API attach tried in the first fight")
    stub.FireEvent("ADDON_ACTION_BLOCKED", "SomeAddon", "CastSpellByName")
    T.eq(w.blocked[1].addon, "SomeAddon", "blocked calls of any addon are kept")
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    T.eq(#w.attach, 1, "attach only once a session")
    stub.LeaveCombat()
    ns.Waiting.Run("off")
    T.falsy(w.on, "off stops it")
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    T.eq(#w.combo, 2, "nothing written once off")
end)

T.test("dev: invites are logged with the confirm boxes, and who declined", function()
    stub.Load()
    _G.DaylightUIDevDB = nil
    local undo = with({ DeclineGroup = function() end })
    local ns = loadDev()
    local box = CreateFrame("Frame", "StaticPopup1", UIParent)
    box.which = "PARTY_INVITE"
    box:Show()
    stub.FireEvent("PARTY_INVITE_REQUEST", "Bob", false, false, false)
    stub.RunTimers()
    DeclineGroup()
    undo()
    local text = table.concat(DaylightUIDevDB.invites[1], "\n")
    T.truthy(text:find("PARTY_INVITE_REQUEST Bob", 1, true), text)
    T.truthy(text:find("StaticPopup1 shown true", 1, true), "the box written down")
    T.truthy(text:find("which PARTY_INVITE", 1, true), "what it holds")
    T.truthy(text:find("StaticPopup2 missing", 1, true), "a box the game lacks")
    T.truthy(text:find("1 s later", 1, true), "looked again later")
    T.truthy(text:find("DeclineGroup called from", 1, true), "the decline")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.StaticPopup1 = nil
end)

T.test("dev: a group change in a fight writes down the game's group state and every party tile", function()
    stub.Load({ module = true })
    stub.RunTimers()
    _G.DaylightUIDevDB = nil
    loadDev()
    stub.units.party1 = { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 }
    stub.EnterCombat()
    stub.SetGroup(true, false, 2)
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    stub.RunTimers()
    local text = table.concat(DaylightUIDevDB.groups[1], "\n")
    T.truthy(text:find("combat true", 1, true), text)
    T.truthy(text:find("[@party1,exists] yes", 1, true), text)
    T.truthy(text:find("DaylightUIPartyHeader shown", 1, true), "our header written down")
    T.truthy(text:find("buttons made:", 1, true), text)
    T.truthy(text:find("2 s later", 1, true), "looked again once it settled")
    T.truthy(text:find("also GROUP_ROSTER_UPDATE", 1, true), "a burst is one entry")
    T.eq(#DaylightUIDevDB.groups, 1)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("dev: /dui inspectprobe asks for a player target", function()
    local DUI = stub.Load({ module = true })
    loadDev()
    T.noerror(function() DUI.RunCommand("inspectprobe") end)
    T.truthy(stub.ChatContains("target a player first"), "says what it needs")
end)

T.test("dev: /dui craftprobe reads the open profession, crafts and switches from our code", function()
    local PW = require("craftworld")
    stub.Load({ before = PW.world({ enabled = false }) })
    _G.DaylightUIDevDB = nil
    local ns = loadDev()
    PW.Open(197)
    ns.CraftProbe.Run("read")
    local text = table.concat(DaylightUIDevDB.craftProbe[1], "\n")
    T.truthy(text:find("professionName=Tailoring", 1, true), text)
    T.truthy(text:find("Herbalism skillLine=182", 1, true), text)
    T.truthy(text:find("craftingUI=false", 1, true), text)
    T.truthy(text:find("recipes 5", 1, true) and text:find("learned 4", 1, true), "every recipe, learned or not")
    T.truthy(text:find("slot 1: need", 1, true), "a recipe's materials")
    ns.CraftProbe.Run("make")
    T.eq(PW.Calls("CraftRecipe")[1][1], 101, "the first recipe the bags can make")
    stub.Key(ns.CraftProbe.Run, "open")   -- typed: a key
    T.eq(PW.Calls("OpenTradeSkill")[1][1], 185, "the next profession with a crafting window")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("dev: /dui craftprobe survives a client without the trade skill calls", function()
    stub.Load()
    _G.DaylightUIDevDB = nil
    local ns = loadDev()
    local undo = with({ C_TradeSkillUI = false })
    T.noerror(function() ns.CraftProbe.Run("read") end)
    undo()
    T.truthy(table.concat(DaylightUIDevDB.craftProbe[1], "\n"):find("no C_TradeSkillUI", 1, true))
end)

-- A small group finder for /dui lfgprobe: one dungeon category, two activities,
-- one search result. Every call it takes is written down.
local function lfgWorld(calls)
    local L = {}
    local function log(name, ...) calls[#calls + 1] = { name, ... } end
    L.GetPremadeGroupFinderStyle = function() return 2 end
    L.IsPremadeGroupFinderEnabled = function() return true end
    L.GetAvailableCategories = function() return { 2 } end
    L.GetLfgCategoryInfo = function() return { name = "Dungeons" } end
    L.GetAvailableActivities = function() return { 10, 11 } end
    L.GetAvailableActivityGroups = function() return { 5 } end
    L.GetActivityGroupInfo = function() return "Classic", 1 end
    L.GetActivityInfoTable = function(id)
        return id == 10 and { fullName = "The Deadmines", minLevelSuggestion = 17, maxLevelSuggestion = 26 }
            or { fullName = "Scarlet Monastery", minLevelSuggestion = 55, maxLevelSuggestion = 60 }
    end
    L.IsPlayerAuthenticatedForLFG = function() return true end
    L.HasActiveEntryInfo = function() return false end
    L.GetActiveEntryInfo = function() return nil end
    L.GetAvailableRoles = function() return true, false, true end
    L.Search = function(...) log("Search", ...) end
    L.CreateListing = function(t) log("CreateListing", t); return true end
    L.RemoveListing = function() log("RemoveListing") end
    L.GetFilteredSearchResults = function() return 1, { 7 } end
    L.GetSearchResultInfo = function() return { leaderName = "Thorgrim", numMembers = 3, comment = "need dps" } end
    L.GetSearchResultMemberCounts = function() return { TANK = 1, HEALER = 1, DAMAGER = 1 } end
    L.GetSearchResultPlayerInfo = function() return { classFilename = "WARRIOR", level = 31 } end
    L.GetSearchResultEncounterInfo = function() return nil end
    return L
end

T.test("dev: /dui lfgprobe reads the group finder, searches, lists and sends a who from our code", function()
    stub.Load()
    _G.DaylightUIDevDB = nil
    local ns = loadDev()
    local calls, who = {}, {}
    local undo = with({ C_LFGList = lfgWorld(calls), UnitLevel = function() return 20 end,
        C_FriendList = { SendWho = function(...) who[#who + 1] = { ... } end, SetWhoToUi = function() end,
            GetNumWhoResults = function() return 0, 0 end } })
    T.noerror(function() ns.LfgProbe.Run("read") end)
    local text = table.concat(DaylightUIDevDB.lfgProbe[1], "\n")
    T.truthy(text:find("category 2: name=Dungeons", 1, true), text)
    T.truthy(text:find("group 5: Classic", 1, true), text)
    T.truthy(text:find("dungeon at level 20: 10", 1, true), "the dungeon whose levels hold yours")
    T.truthy(text:find("note box not loaded", 1, true), "the game's box only exists once its window loaded")
    ns.LfgProbe.Run("search")
    T.eq(calls[1][1], "Search"); T.eq(calls[1][2], 2, "the Dungeons category")
    stub.FireEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
    T.truthy(table.concat(DaylightUIDevDB.lfgProbe[1], "\n"):find("leaderName=Thorgrim", 1, true), "the first results in full")
    ns.LfgProbe.Run("list")
    T.eq(calls[2][1], "CreateListing"); T.eq(calls[2][2].activityIDs[1], 10)
    ns.LfgProbe.Run("unlist")
    T.eq(calls[3][1], "RemoveListing")
    ns.LfgProbe.Run("who")
    T.eq(who[1][1], "20", "your level")
    undo()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A small mailbox for /dui mailprobe: a sale letter with gold, a letter with an
-- item, and an empty read one. Every call it takes is written down.
local function mailWorld(calls, gold)
    local letters = {
        { "Auction House", "Auction successful: Heavy Leather", 48500, 0, 30, nil, false },
        { "Brannoc", "Ore", 0, 0, 20, 1, false },
        { "Thaxton", "Hello", 0, 0, 10, nil, true },
    }
    local function log(name, ...) calls[#calls + 1] = { name, ... } end
    return {
        GetMoney = function() return gold[1] end,
        GetInboxNumItems = function() return #letters, #letters end,
        GetInboxHeaderInfo = function(i)
            local l = letters[i]
            return nil, nil, l[1], l[2], l[3], l[4], l[5], l[6], l[7], false, false, true, false
        end,
        GetInboxInvoiceInfo = function(i)
            if i == 1 then return "seller", "Heavy Leather", "Ysella", 51000, 51000, 50, 2550, 0, 0, 0, 20 end
        end,
        GetSendMailPrice = function() return 30 end,
        TakeInboxMoney = function(i) log("TakeInboxMoney", i) end,
        AutoLootMailItem = function(i) log("AutoLootMailItem", i) end,
        SendMail = function(...) log("SendMail", ...) end,
        DeleteInboxItem = function(i) log("DeleteInboxItem", i) end,
    }
end

T.test("dev: /dui mailprobe reads the inbox, takes, loots, sends, deletes, and watches gold against events", function()
    stub.Load()
    _G.DaylightUIDevDB = nil
    local ns = loadDev()
    local calls, gold = {}, { 100000 }
    local undo = with(mailWorld(calls, gold))
    T.noerror(function() ns.MailProbe.Run("read") end)
    local text = table.concat(DaylightUIDevDB.mailProbe[1], "\n")
    T.truthy(text:find("inbox 3 shown of 3", 1, true), text)
    T.truthy(text:find("invoice type=seller item=Heavy Leather", 1, true), "the sale letter's invoice")
    T.truthy(text:find("cut=2550", 1, true), "the auction house's cut")
    ns.MailProbe.Run("take")
    T.eq(calls[1][1], "TakeInboxMoney"); T.eq(calls[1][2], 1, "the letter with gold")
    gold[1] = 148500
    stub.FireEvent("PLAYER_MONEY")
    T.truthy(table.concat(DaylightUIDevDB.mailProbe[1], "\n"):find("PLAYER_MONEY  gold=148500 (+48500)", 1, true),
        "a gold change is written with how much it moved")
    ns.MailProbe.Run("loot")
    T.eq(calls[2][1], "AutoLootMailItem"); T.eq(calls[2][2], 2, "the letter with an item")
    DaylightUI.RunCommand("mailprobe send Brannoc Ironhide")
    T.eq(calls[3][1], "SendMail"); T.eq(calls[3][2], "Brannoc Ironhide", "first and last name")
    ns.MailProbe.Run("delete")
    T.eq(calls[4][1], "DeleteInboxItem"); T.eq(calls[4][2], 3, "only a read letter with nothing in it")
    ns.MailProbe.Run("watch")
    stub.FireEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", 777)
    gold[1] = 100000
    stub.FireEvent("PLAYER_MONEY")
    text = table.concat(DaylightUIDevDB.mailProbe[1], "\n")
    T.truthy(text:find("AUCTION_HOUSE_PURCHASE_COMPLETED 777 gold=148500", 1, true), text)
    T.truthy(text:find("(-48500)", 1, true), "the purchase's gold, after it")
    T.eq(ns.MailProbe.Run("stop")[1], "stopped")
    stub.FireEvent("PLAYER_MONEY")
    T.falsy(table.concat(DaylightUIDevDB.mailProbe[1], "\n"):find("(+0)", 1, true), "nothing written after stop")
    undo()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A small social world for /dui socialprobe: one Battle.net friend in the game, one
-- request, one recent ally. SocialUIFrame remembers the tab ToggleRaidFrame asked
-- for while it's parked (its OnShow never runs).
T.test("dev: /dui socialprobe reads friends, requests and allies, parks the game's window, sets AFK", function()
    stub.Load()
    _G.DaylightUIDevDB = nil
    local ns = loadDev()
    local afk = {}
    local sf = CreateFrame("Frame", "SocialUIFrame", UIParent)
    sf:Hide()
    sf.ConsumeDeferredOpenTab = function(self) local t = self.deferredOpenTabType; self.deferredOpenTabType = nil; return t end
    local undo = with({
        C_SocialUI = { IsSystemEnabled = function() return true end },
        BNGetNumFriends = function() return 1, 1 end,
        BNGetNumFriendInvites = function() return 1 end,
        ToggleRaidFrame = function() sf.deferredOpenTabType = 4; ShowUIPanel(sf) end,
        C_BattleNet = {
            GetFriendAccountInfo = function() return { accountName = "Mara", gameAccountInfo = { characterName = "Ysella", isOnline = true } } end,
            GetFriendInviteInfo = function() return { inviteID = 9, accountName = "Nyx" } end,
            SetAFK = function(on) afk[#afk + 1] = on end,
        },
        C_RecentAllies = { GetRecentAllies = function() return { { characterData = { name = "Halvar", level = 41 } } } end },
    })
    T.noerror(function() ns.SocialProbe.Run("read") end)
    local text = table.concat(DaylightUIDevDB.socialProbe[1], "\n")
    T.truthy(text:find("characterName=Ysella", 1, true), text)
    T.truthy(text:find("accountName=Nyx", 1, true), "the request in full")
    T.truthy(text:find("name=Halvar", 1, true), "the ally in full")
    T.truthy(text:find("Consume=function", 1, true), "whether the game's frame can say the tab it was asked for")
    ns.SocialProbe.Run("park")
    text = table.concat(DaylightUIDevDB.socialProbe[1], "\n")
    T.truthy(text:find("ConsumeDeferredOpenTab: true 4", 1, true), text)
    T.eq(sf:GetParent(), UIParent, "given back")
    ns.SocialProbe.Run("status")
    T.eq(afk[1], true)
    stub.RunTimers()
    stub.Advance(3)
    stub.RunTimers()
    undo()
    _G.SocialUIFrame = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A small Legacy world for /dui legacyprobe: the constants, one reward level, one
-- category with one challenge, and one tree with two nodes (one that takes a
-- point). LegacySystemFrame reports the page it was asked for.
T.test("dev: /dui legacyprobe reads the track, a challenge and a tree, parks the game's window, stages and rolls back", function()
    stub.Load()
    _G.DaylightUIDevDB = nil
    local ns = loadDev()
    local calls = {}
    local lf = CreateFrame("Frame", "LegacySystemFrame", UIParent)
    lf:Hide()
    local node = { posX = 1200, posY = 600, type = 0, maxRanks = 3, ranksPurchased = 0, activeRank = 0, isVisible = true, canPurchaseRank = true, entryIDs = { 501 } }
    local undo = with({
        Constants = { LegacyConsts = { LEGACY_REWARD_TRACK_FACTION_ID = 3001, LEGACY_TREE_PROFESSIONS_ID = 71, LEGACY_TREE_ADVENTURE_ID = 72,
            LEGACY_TREE_PROGRESSION_ID = 73, LEGACY_POINTS_TRAIT_CURRENCY_ID = 9 } },
        LEGACY_TRACK_FRAME_TITLE = "Progress Track",
        ToggleLegacyChallenges = function() lf.currentPage = 2; ShowUIPanel(lf) end,
        C_MajorFactions = { GetCurrentRenownLevel = function() return 16 end, GetMajorFactionData = function() return { renownLevel = 16 } end,
            GetRenownLevels = function() return { { level = 15 } } end,
            GetRenownRewardsForLevel = function() return { { itemID = 9001, name = "Holstered Rifle", rewardType = 1 } } end },
        GetCategoryList = function() return { 81 } end,
        GetCategoryInfo = function() return "Mage", -1 end,
        GetCategoryNumAchievements = function() return 1, 0, 1 end,
        GetAchievementInfo = function() return 7001, "Portal Master", 10, false, nil, nil, nil, "Learn every portal." end,
        GetAchievementNumCriteria = function() return 1 end,
        GetAchievementCriteriaInfo = function() return "Stormwind", 0, true, 1, 1 end,
        C_Traits = {
            GetConfigIDByTreeID = function(id) return id + 1000 end,
            GetTraitCurrencyForAchievement = function() return 3 end,
            GetTreeNodes = function() return { 11 } end,
            GetNodeInfo = function() return node end,
            GetTreeCurrencyInfo = function() return { { quantity = 3, traitCurrencyID = 9 } } end,
            PurchaseRank = function(c, id) calls[#calls + 1] = "buy " .. id; node.ranksPurchased = 1; return true end,
            RollbackConfig = function() calls[#calls + 1] = "rollback"; node.ranksPurchased = 0; return true end,
            ConfigHasStagedChanges = function() return node.ranksPurchased > 0 end,
        },
    })
    T.noerror(function() ns.LegacyProbe.Run("read") end)
    local text = table.concat(DaylightUIDevDB.legacyProbe[1], "\n")
    T.truthy(text:find("LEGACY_TRACK_FRAME_TITLE = Progress Track", 1, true), text)
    T.truthy(text:find("name=Holstered Rifle", 1, true), "the reward in full")
    T.truthy(text:find("name=Portal Master", 1, true), "a challenge")
    T.truthy(text:find("legacy points for it: 3", 1, true), "its points")
    T.truthy(text:find("node 11 x=1200 y=600", 1, true), "the tree's layout")
    ns.LegacyProbe.Run("park")
    text = table.concat(DaylightUIDevDB.legacyProbe[1], "\n")
    T.truthy(text:find("page=2 (Challenges is 2)", 1, true), text)
    T.eq(lf:GetParent(), UIParent, "given back")
    ns.LegacyProbe.Run("spend")
    T.deq(calls, { "buy 11", "rollback" })
    undo()
    _G.LegacySystemFrame = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("dev: /dui hookprobe hooks GameTooltip's own methods at login only when on, and counts the game's calls", function()
    local ns = loadDev()
    DaylightUIDevDB = {}
    -- a tooltip of the test's own, since the real one must keep no hooks (test_tooltip)
    local tip = CreateFrame("GameTooltip", nil, UIParent)
    tip.NineSlice = CreateFrame("Frame", nil, tip)
    local undo = with({ GameTooltip = tip })
    T.eq(ns.HookProbe.installed, nil, "nothing hooked while off")
    ns.HookProbe.Run(" ON ")
    T.eq(DaylightUIDevDB.hookProbe.mode, "read", "on = the read kind, from the next login")
    local want = type(tip.FadeOut) == "function" and 6 or 5   -- the fake game's tooltip has no FadeOut
    T.eq(ns.HookProbe.Install("read"), want, "the methods there and the art's SetAlpha")
    T.truthy(rawget(tip, "SetOwner"), "hooked on the tooltip itself")
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip:SetAlpha(1)
    ns.HookProbe.Run("")
    local last = DaylightUIDevDB.hookProbe.last
    T.eq(last.mode, "read")
    T.truthy(last.counts:find("SetOwner 1", 1, true), last.counts)
    T.truthy(last.counts:find("SetAlpha 1", 1, true), last.counts)
    T.falsy(last.counts:find("writes", 1, true), "the read kind writes nothing")
    ns.HookProbe.Run("off")
    T.eq(DaylightUIDevDB.hookProbe.mode, nil)
    undo()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("dev: /dui hookprobe write sets the tooltip's alpha and spot again to what they were", function()
    local ns = loadDev()
    DaylightUIDevDB = { hookProbe = { on = true } }   -- the first probe's saved switch
    local tip = CreateFrame("GameTooltip", nil, UIParent)
    tip.NineSlice = CreateFrame("Frame", nil, tip)
    local undo = with({ GameTooltip = tip })
    ns.HookProbe.Run("")
    T.eq(DaylightUIDevDB.hookProbe.mode, "read", "the old on carries over as read")
    ns.HookProbe.Run("write")
    T.eq(DaylightUIDevDB.hookProbe.mode, "write")
    ns.HookProbe.Install("write")
    tip:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -20)
    tip:SetAlpha(0.5)
    T.eq(tip:GetAlpha(), 0.5, "alpha unchanged")
    local p, rel, rp, x, y = tip:GetPoint(1)
    T.eq(p, "TOPLEFT"); T.eq(rel, UIParent); T.eq(rp, "TOPLEFT"); T.eq(x, 10); T.eq(y, -20)
    T.eq(tip:GetNumPoints(), 1, "the point set again, not added")
    ns.HookProbe.Run("")
    local last = DaylightUIDevDB.hookProbe.last
    T.eq(last.mode, "write")
    T.truthy(last.counts:find("SetPoint 1", 1, true), last.counts)
    T.truthy(last.counts:find("SetAlpha 1", 1, true), "its own write-back isn't counted again: " .. last.counts)
    T.truthy(last.counts:find("writes 2", 1, true), last.counts)
    undo()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("boxprobe: a frame that shows and goes is written down, once, by its top frame", function()
    local ns = loadDev()
    local Probe = ns.BoxProbe
    local function rect(f) f.GetRect = function() return 100, 200, 300, 80 end end
    local box = CreateFrame("Frame", "ProbeFlashBox", UIParent)
    local inner = CreateFrame("Frame", "ProbeFlashInner", box)
    local stays = CreateFrame("Frame", "ProbeStaysBox", UIParent)
    rect(box); rect(inner); rect(stays)
    box:Hide(); stays:Hide()
    local run = { live = {}, flashes = {}, stamp = 0, worst = 0, kind = "login", time = "now" }
    Probe.Walk(run, 0)
    box:Show(); stays:Show()
    Probe.Walk(run, 6)
    box:Hide()
    Probe.Walk(run, 6.2)
    stays:Hide()
    Probe.Walk(run, 6 + Probe.BRIEF + 1)
    local text = table.concat(Probe.Lines(run), "\n")
    T.truthy(text:find("ProbeFlashBox", 1, true), text)
    T.falsy(text:find("ProbeFlashInner", 1, true), "it went with its parent: " .. text)
    T.falsy(text:find("ProbeStaysBox", 1, true), "up too long to be a flash: " .. text)
    T.truthy(text:find("6.00 s for 0.20 s", 1, true), text)
end)

T.test("dev: padlog writes presses, stops, windows and taint only when they change", function()
    local DUI = stub.Load()
    local ns = loadDev()
    local win = CreateFrame("Frame", "PadLogWindow", UIParent)
    local button = CreateFrame("Button", "PadLogButton", win)
    button:SetSize(80, 20)
    button:SetText("Accept")
    local buttons = {}
    local manager = { shownFrames = { win }, focusedFrame = win }
    local nav = { enabled = true, bindingActive = true, currentButton = button,
        activeInfo = { buttonGroups = { mainGroup = { buttons = { button },
            scrollFrames = { { buttons = { button, button } } } } } } }
    function nav:IsShown() return true end
    local back = with({ GamepadMode = { FrameControlsManager = manager }, SmartNavigation = nav,
        GamepadSharedUtility = { InputBindingManager = { bindingSetStack = {} } },
        GetBindingAction = function() return "CLICK Ours:RightButton" end,
        C_GamePad = { GetDeviceMappedState = function() return { buttons = buttons } end,
                      ButtonIndexToConfigName = function(i) return "PAD" .. i end } })

    DUI.RunCommand("padlog")
    T.truthy(ns.PadLog.Running())
    ns.PadLog.Tick()
    local run = DaylightUIDevDB.padLog[1]
    local before = #run.lines
    ns.PadLog.Tick()
    T.eq(#run.lines, before, "nothing changed, nothing written")

    buttons[1], buttons[2] = false, true
    ns.PadLog.Tick()
    ns.PadLog.Tick()             -- held down, so one press
    buttons[2] = false
    nav.currentButton = nil
    ns.PadLog.Tick()
    buttons[2] = true
    ns.PadLog.Tick()
    stub.Mark(manager, "focusedFrame", "SomeAddon")
    stub.Mark(GamepadSharedUtility.InputBindingManager, "bindingSetStack", "OtherAddon")
    ns.PadLog.Tick()
    stub.FireEvent("ADDON_ACTION_FORBIDDEN", "SomeAddon", "CastSpell()")
    DUI.RunCommand("padlog")
    T.falsy(ns.PadLog.Running())

    local text = table.concat(run.lines, "\n")
    T.truthy(text:find("PadLogWindow", 1, true), text)
    T.truthy(text:find("1 stops, 2 in lists", 1, true), text)
    T.truthy(text:find('PadLogButton [Button] "Accept" 80x20', 1, true), text)
    T.truthy(text:find('PAD1 #2 -> CLICK Ours:RightButton on PadLogButton', 1, true), text)
    T.truthy(text:find("PAD1 #2 -> CLICK Ours:RightButton on none", 1, true), "a press with nothing selected: " .. text)
    T.truthy(text:find("manager.focusedFrame by SomeAddon", 1, true), text)
    T.truthy(text:find("bindings.bindingSetStack by OtherAddon", 1, true), text)
    T.truthy(text:find("SomeAddon CastSpell()", 1, true), text)
    local _, count = text:gsub("press", "")
    T.eq(count, 2, text)
    back()
end)
