local stub = require("stub")

-- The API (API.lua): listeners, the frame registry behind the lookups, and what
-- is passed on from the core.

local function load()
    local DUI = stub.Load()
    return DUI, DUI.API
end

-- A recorder: every call as { args... }.
local function recorder()
    local calls = {}
    return calls, function(...) calls[#calls + 1] = { ... } end
end

T.test("api: version 1.1 on the same table Plugins reads", function()
    local DUI = load()
    T.eq(DaylightUI.API.major, 1)
    T.eq(DaylightUI.API.minor, 7)
    T.eq(DaylightUI.API, DUI.API)
end)

T.test("api: On/Off, handlers get the frame events with kind, frame, unit, preview", function()
    local _, API = load()
    local f = CreateFrame("Frame")
    local calls, fn = recorder()
    local h = API.On("FrameMade", fn)
    DaylightUI.APIReport.Made("raid", f, "raid3", false)
    T.eq(#calls, 1)
    T.eq(calls[1][1], "raid")
    T.eq(calls[1][2], f)
    T.eq(calls[1][3], "raid3")
    T.eq(calls[1][4], false)
    T.eq(API.GetUnitFrame("raid3"), f)
    API.Off(h)
    DaylightUI.APIReport.Made("raid", CreateFrame("Frame"), "raid4", false)
    T.eq(#calls, 1)
end)

T.test("api: previews get events, lookups never return them", function()
    local _, API = load()
    local p = CreateFrame("Frame")
    local calls, fn = recorder()
    API.On("FrameMade", fn)
    DaylightUI.APIReport.Made("party", p, "party1", true)
    T.eq(#calls, 1)
    T.eq(calls[1][4], true)
    T.isnil(API.GetUnitFrame("party1"))
    T.isnil(API.Frames("party")())
end)

T.test("api: a frame that changes unit says goodbye to the old one first", function()
    local _, API = load()
    local f = CreateFrame("Frame")
    DaylightUI.APIReport.Made("nameplate", f, "nameplate1", false)
    local seq = {}
    API.On("FrameRemoved", function(k, fr, u) seq[#seq + 1] = "removed " .. u end)
    API.On("FrameUnitChanged", function(k, fr, u) seq[#seq + 1] = "changed " .. u end)
    DaylightUI.APIReport.Unit("nameplate", f, "nameplate2")
    T.deq(seq, { "removed nameplate1", "changed nameplate2" })
    T.isnil(API.GetNameplate("nameplate1"))
    T.eq(API.GetNameplate("nameplate2"), f)
end)

T.test("api: Gone clears the unit but the frame stays known: later Unit is only a unit change", function()
    local _, API = load()
    local f = CreateFrame("Frame")
    local seq = {}
    for _, e in ipairs({ "FrameMade", "FrameRemoved", "FrameUnitChanged" }) do
        API.On(e, function(k, fr, u) seq[#seq + 1] = e .. " " .. tostring(u) end)
    end
    DaylightUI.APIReport.Made("nameplate", f, "nameplate1", false)
    DaylightUI.APIReport.Gone("nameplate", f)
    DaylightUI.APIReport.Gone("nameplate", f)
    T.isnil(API.GetNameplate("nameplate1"))
    DaylightUI.APIReport.Unit("nameplate", f, "nameplate2")
    T.deq(seq, { "FrameMade nameplate1", "FrameRemoved nameplate1", "FrameUnitChanged nameplate2" })
    local n = 0
    for fr, u in API.Frames("nameplate") do n = n + 1; T.eq(fr, f); T.eq(u, "nameplate2") end
    T.eq(n, 1)
end)

T.test("api: a handler's error doesn't stop the others and names its owner", function()
    local _, API = load()
    local called = 0
    API.On("FrameMade", function() error("boom-api-owner") end, "MyPlugin")
    API.On("FrameMade", function() called = called + 1 end)
    DaylightUI.APIReport.Made("party", CreateFrame("Frame"), "party2", false)
    T.eq(called, 1)
    T.eq(#stub.errors, 1)
    T.truthy(string.find(stub.errors[1], "MyPlugin", 1, true))
    T.truthy(string.find(stub.errors[1], "boom-api-owner", 1, true))
end)

T.test("api: Off and On inside a fire don't skip or double a handler", function()
    local _, API = load()
    local a, b, c = 0, 0, 0
    local hA
    hA = API.On("FrameMade", function()
        a = a + 1
        API.Off(hA)
        API.On("FrameMade", function() c = c + 1 end)
    end)
    API.On("FrameMade", function() b = b + 1 end)
    DaylightUI.APIReport.Made("party", CreateFrame("Frame"), "party1", false)
    -- c joined mid-fire: it hears party1 from the replay, not twice from this fire
    T.eq(a, 1); T.eq(b, 1); T.eq(c, 1)
    DaylightUI.APIReport.Made("party", CreateFrame("Frame"), "party2", false)
    T.eq(a, 1); T.eq(b, 2); T.eq(c, 2)
end)

T.test("api: bad input is refused quietly", function()
    local _, API = load()
    T.isnil(API.GetUnitFrame(nil))
    T.isnil(API.GetNameplate(nil))
    T.isnil(API.GetActionButton(nil, nil))
    stub.chat = {}
    T.isnil(API.On("NoSuchEvent", function() end))
    T.eq(#stub.chat, 1)
    T.isnil(API.On("FrameMade", nil))
    T.eq(#stub.chat, 2)
    API.Off(nil)
    API.Off({})
    T.isnil(API.Frames(nil)())
    T.isnil(API.GetSetting(nil, nil))
    T.falsy(API.IsModuleEnabled(nil))
end)

T.test("api: no listener, no work", function()
    local _, API = load()
    T.falsy(DaylightUI.APIReport.Wants("FrameMade"))
    local h = API.On("FrameMade", function() end)
    T.truthy(DaylightUI.APIReport.Wants("FrameMade"))
    API.Off(h)
    T.falsy(DaylightUI.APIReport.Wants("FrameMade"))
end)

T.test("api: re-broadcasts StyleChanged and SettingChanged", function()
    local DUI, API = load()
    local calls, fn = recorder()
    API.On("SettingChanged", fn)
    DUI:Set("general", "accent", "custom")
    T.eq(#calls, 1)
    T.eq(calls[1][1], "general")
    T.eq(calls[1][2], "accent")
    T.eq(calls[1][3], "custom")
    local styled = 0
    API.On("StyleChanged", function() styled = styled + 1 end)
    DUI.Fire("StyleChanged")
    T.eq(styled, 1)
end)

T.test("api: GetSetting reads, IsModuleEnabled knows our modules", function()
    local DUI = stub.Load({ module = true })
    local API = DUI.API
    T.eq(API.GetSetting("general", "accent"), DUI:Get("general", "accent"))
    T.eq(type(DUI:Get("UnitFrames", "focus.enabled")), "boolean")
    T.eq(API.GetSetting("UnitFrames", "focus.enabled"), DUI:Get("UnitFrames", "focus.enabled"))
    T.eq(API.IsModuleEnabled("UnitFrames"), true)
    T.eq(API.IsModuleEnabled("Nope"), false)
end)

T.test("api: FrameMade replays already-made frames to a new listener only", function()
    local _, API = load()
    local a, b = CreateFrame("Frame"), CreateFrame("Frame")
    local early, efn = recorder()
    API.On("FrameMade", efn)
    DaylightUI.APIReport.Made("raid", a, "raid1", false)
    DaylightUI.APIReport.Made("partypet", b, "partypet1", false)
    T.eq(#early, 2)
    local late, lfn = recorder()
    API.On("FrameMade", lfn, "Late")
    T.eq(#late, 2)
    T.eq(#early, 2)
    local seen = {}
    for _, c in ipairs(late) do seen[c[2]] = c; T.eq(c[4], false) end
    T.eq(seen[a][1], "raid"); T.eq(seen[a][3], "raid1")
    T.eq(seen[b][3], "partypet1")
end)

T.test("api: the replay covers frames with no unit now, and previews that went", function()
    local _, API = load()
    local a, b, c = CreateFrame("Frame"), CreateFrame("Frame"), CreateFrame("Frame")
    DaylightUI.APIReport.Made("party", a, nil, false)
    DaylightUI.APIReport.Made("nameplate", b, "nameplate1", false)
    DaylightUI.APIReport.Gone("nameplate", b, false)
    DaylightUI.APIReport.Made("raid", c, "raid1", true)
    DaylightUI.APIReport.Gone("raid", c, true)
    local calls, fn = recorder()
    API.On("FrameMade", fn)
    T.eq(#calls, 3)
    local seen = {}
    for _, x in ipairs(calls) do seen[x[2]] = x; T.isnil(x[3]) end
    T.eq(seen[a][4], false); T.eq(seen[b][4], false); T.eq(seen[c][4], true)
    T.eq(seen[c][1], "raid")
    T.isnil(API.GetNameplate("nameplate1"))
end)

T.test("api: a shown frame wins over a hidden one with a stale unit", function()
    local _, API = load()
    local R = DaylightUI.APIReport
    local shown, stale = CreateFrame("Frame", nil, UIParent), CreateFrame("Frame", nil, UIParent)
    R.Made("party", shown, "party1", false)
    R.Made("party", stale, "party1", false)   -- told last
    stale:Hide()
    T.eq(API.GetUnitFrame("party1"), shown, "the shown tile")
    shown:Hide()
    T.truthy(API.GetUnitFrame("party1") == shown or API.GetUnitFrame("party1") == stale, "none shown: still one")
    -- Across kinds: a hidden raid tile loses to a shown party tile.
    local raid, party = CreateFrame("Frame", nil, UIParent), CreateFrame("Frame", nil, UIParent)
    R.Made("raid", raid, "partypet2", false)
    R.Made("party", party, "partypet2", false)
    raid:Hide()
    T.eq(API.GetUnitFrame("partypet2"), party)
    raid:Show()
    T.eq(API.GetUnitFrame("partypet2"), raid, "shown, the raid tile comes first")
    -- When one of two tiles on the same unit lets it go, the other is still found.
    local a, b = CreateFrame("Frame", nil, UIParent), CreateFrame("Frame", nil, UIParent)
    R.Made("raid", a, "raid5", false)
    R.Made("raid", b, "raid5", false)
    R.Unit("raid", b, "raid6", false)
    T.eq(API.GetUnitFrame("raid5"), a)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api: a replayed handler may report a new frame", function()
    local _, API = load()
    DaylightUI.APIReport.Made("party", CreateFrame("Frame"), "party1", false)
    DaylightUI.APIReport.Made("party", CreateFrame("Frame"), "party2", false)
    local n = 0
    local inside = false
    API.On("FrameMade", function(kind)
        if kind ~= "party" or inside then return end
        n = n + 1
        inside = true
        DaylightUI.APIReport.Made("raid", CreateFrame("Frame"), "raid" .. n, false)
        inside = false
    end)
    T.eq(n, 2)
end)

T.test("api kit: Attach gives one holder per frame, a child above our art", function()
    local _, API = load()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameLevel(5)
    DaylightUI.APIReport.Made("raid", f, "raid1", false)
    local h = API.Attach(f)
    T.eq(type(h), "table")
    T.eq(h:GetObjectType(), "Frame")
    T.eq(API.Attach(f), h)
    T.eq(h:GetParent(), f)
    T.truthy(h:GetFrameLevel() > f:GetFrameLevel())
    T.isnil(API.Attach(nil))
    T.isnil(API.Attach("nope"))
    local g = CreateFrame("Frame", nil, UIParent)
    DaylightUI.APIReport.Made("party", g, nil, true)
    T.truthy(API.Attach(g) ~= h, "a preview is ours too")
end)

T.test("api kit: Attach writes nothing on a frame that isn't Daylight UI's", function()
    local _, API = load()
    local game = CreateFrame("Frame", "SomeGameFrame", UIParent)
    T.isnil(API.Attach(game))
    T.isnil(rawget(game, "__duiApiHolder"), "no field written on it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api kit: Attach works on a tile made in combat", function()
    -- The game lets a plain child be made on a protected frame in combat (the child
    -- isn't protected), and the fake game's secure mode agrees.
    local DUI = stub.Load()
    local API = DUI.API
    stub.secure = true
    local tile = CreateFrame("Button", nil, UIParent, "SecureUnitButtonTemplate")
    DaylightUI.APIReport.Made("raid", tile, "raid1", false)
    stub.EnterCombat()
    local ok, h = pcall(API.Attach, tile)
    stub.LeaveCombat()
    stub.secure = false
    T.truthy(ok, tostring(h))
    T.eq(type(h), "table")
    T.eq(h:GetParent(), tile)
    T.eq(API.Attach(tile), h)
end)

T.test("api kit: Colors is a copy", function()
    local DUI, API = load()
    local c = API.Colors()
    local before = DUI.Style.INK.TEXT[1]
    c.TEXT[1] = 0.1
    c.GOOD = nil
    T.eq(DUI.Style.INK.TEXT[1], before)
    T.truthy(DUI.Style.INK.GOOD)
    T.eq(API.Colors().TEXT[1], before)
    for _, k in ipairs({ "TITLE", "VALUE", "TEXT", "LABEL", "OFF", "GOOD", "WARN", "BAD", "DAMAGE", "MONEY" }) do
        T.eq(type(API.Colors()[k]), "table", k)
    end
end)

T.test("api kit: Text takes our size names only", function()
    local DUI, API = load()
    local p = CreateFrame("Frame", nil, UIParent)
    local _, size = API.Text(p, "body"):GetFont()
    T.eq(size, 13)
    _, size = API.Text(p, "tiny"):GetFont()
    T.eq(size, 10)
    _, size = API.Text(p, "huge"):GetFont()
    T.eq(size, 13)
    _, size = API.Text(p, 40):GetFont()
    T.eq(size, 13)
end)

T.test("api kit: Accent follows the player's accent at call time", function()
    local DUI, API = load()
    DUI:Set("general", "accent", "custom")
    DUI:Set("general", "accentColor", { 0.1, 0.2, 0.3 })
    local r, g, b = API.Accent()
    T.eq(r, 0.1); T.eq(g, 0.2); T.eq(b, 0.3)
    DUI:Set("general", "accentColor", { 0.9, 0.8, 0.7 })
    r, g, b = API.Accent()
    T.eq(r, 0.9); T.eq(g, 0.8); T.eq(b, 0.7)
end)

T.test("api kit: the rest is our own pieces", function()
    local DUI, API = load()
    T.eq(API.Speed.FAST, DUI.Motion.FAST)
    T.eq(API.Speed.NORMAL, DUI.Motion.NORMAL)
    T.eq(API.Speed.SLOW, DUI.Motion.SLOW)
    T.eq(API.Font(), DUI.Style.FONT)
    local f = CreateFrame("Frame", nil, UIParent)
    local o1 = { window = true }
    T.truthy(API.Skin(f, o1))
    local bar = API.Bar(f)
    T.eq(bar:GetObjectType(), "StatusBar")
    T.eq(type(API.Button(f, "Go", 24)), "table")
    T.eq(type(API.Close(f, function() end)), "table")
    T.eq(type(API.Switch(f)), "table")
    T.eq(type(API.Input(f, {})), "table")
    -- Stepped from where it is (Motion.AlphaTo), with no animation group.
    local function settle() for _ = 1, 40 do stub.RunOnUpdate(DUI.Motion.Driver(), 0.05) end end
    API.Fade(f, 0.5, "FAST")
    T.truthy(f:GetAlpha() > 0.5, "on its way")
    T.isnil(f.__duiMotion and f.__duiMotion.fade, "no animation group")
    settle()
    T.eq(f:GetAlpha(), 0.5)
    API.Fade(f, 1)
    settle()
    T.eq(f:GetAlpha(), 1)
    -- A speed name that's another of Motion's keys gives the usual speed, no error.
    API.Fade(f, 0.25, "Fade")
    settle()
    T.eq(f:GetAlpha(), 0.25)
    -- A hidden region is only set, never shown, since it may be a protected frame.
    local hidden = CreateFrame("Frame", nil, UIParent)
    hidden:Hide()
    API.Fade(hidden, 1)
    T.falsy(hidden:IsShown(), "left hidden")
    T.eq(hidden:GetAlpha(), 1)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(type(API.ClassColor("WARRIOR")), "number")
end)

-- ---------------------------------------------------------------------
-- API.For(name): named things
-- ---------------------------------------------------------------------

local function plugin(name)
    local DUI = stub.Load({ login = false, module = true })
    DUI:RegisterModule(name, { label = name, defaults = { on = false } })
    stub.FireEvent("PLAYER_LOGIN")
    DUI.Fade.SkipIntro()
    return DUI, DUI.API.For(name)
end

T.test("api for: two plugins' movers with the same key don't clash", function()
    local DUI, a = plugin("MyHeals")
    local b = DUI.API.For("MyBars")
    T.eq(DUI.API.For("MyHeals"), a, "same view per name")
    local f1, f2 = CreateFrame("Frame", nil, UIParent), CreateFrame("Frame", nil, UIParent)
    f1:SetSize(50, 20); f2:SetSize(50, 20)
    T.eq(a.RegisterMover(f1, "bar", "Bar", { "CENTER", UIParent, "CENTER", 0, 0 }), true)
    T.eq(b.RegisterMover(f2, "bar", "Bar", { "CENTER", UIParent, "CENTER", 0, 50 }), true)
    T.eq(a.RegisterMover(nil, "bar2"), false, "no frame: refused")
    T.truthy(DUI.Movers.Get("plugin.MyHeals.bar"))
    T.truthy(DUI.Movers.Get("plugin.MyBars.bar"))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api for: a plugin's command runs and its error names it", function()
    local DUI, v = plugin("MyHeals")
    local got
    v.RegisterCommand("heals", function(rest) got = rest end, "/dui heals - hi")
    DUI.RunCommand("heals now")
    T.eq(got, "now")
    v.RegisterCommand("boom", function() error("kaboom") end, "/dui boom")
    DUI.RunCommand("boom")
    T.eq(#stub.errors, 1)
    T.truthy(string.find(stub.errors[1], "MyHeals", 1, true))
    T.truthy(string.find(stub.errors[1], "kaboom", 1, true))
    -- a word the addon uses itself is refused with one line
    local n = #stub.chat
    v.RegisterCommand("test", function() got = "stolen" end)
    T.eq(#stub.chat, n + 1)
    T.truthy(DUI.HasCommand("test"))
end)

T.test("api for: RegisterFade and RegisterTestPart carry the prefix", function()
    local DUI, v = plugin("MyHeals")
    local f = CreateFrame("Frame", nil, UIParent)
    T.eq(v.RegisterFade({ key = "bars", scope = "MyHeals", path = "fade", frames = function() return { f } end }), true)
    T.eq(v.RegisterFade({ key = "" }), false, "no key: refused")
    T.truthy(DUI.Fade.State("plugin.MyHeals.bars") ~= nil, "registered under the prefix")
    T.isnil(DUI.Fade.State("bars"))
    v.RegisterTestPart("bars", "My bars", function() return true end)
    local found
    for _, p in ipairs(DUI.TestBox.parts) do
        if p.key == "plugin.MyHeals.bars" then found = p end
    end
    T.truthy(found)
    T.eq(found.label, "My bars")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api for: a broken plugin fade never stops the other areas' fading", function()
    local DUI, v = plugin("MyHeals")
    local Fade = DUI.Fade
    local f = CreateFrame("Frame", nil, UIParent)
    -- wake errors, cap errors, and frames handing back things that aren't frames.
    v.RegisterFade({ key = "broken", frames = function() return { f, "oops", 5, {} } end,
        wake = function() error("wake-bug") end, cap = function() error("cap-bug") end })
    -- A Daylight UI area registered after it must still fade.
    local mine = CreateFrame("Frame", nil, UIParent)
    Fade.Register({ key = "zz.after", scope = "general", path = "fadeTestArea",
        frames = function() return { mine } end, cap = function() return 0.3 end })
    local ok, err = pcall(Fade.Step)
    T.truthy(ok, tostring(err))
    ok, err = pcall(Fade.Step)
    T.truthy(ok, "again: " .. tostring(err))
    for _ = 1, 100 do stub.RunOnUpdate(Fade.driver, 0.1) end
    T.eq(mine:GetAlpha(), 0.3, "the area after it still fades")
    T.truthy(#stub.errors >= 1, "the plugin's error was reported")
    for _, e in ipairs(stub.errors) do T.truthy(string.find(tostring(e), "MyHeals", 1, true), "named: " .. tostring(e)) end
end)

local function groupFor()
    return { label = "Heals", items = {
        { type = "toggle", key = "on", label = "Show heals", desc = "Shows the heals.", default = false },
    } }
end

local function findGroup(page, name)
    for _, g in ipairs(page.groups) do
        if string.find(g.label, name, 1, true) then return g end
    end
end

T.test("api for: a group lands on our Raid page, its rows in the plugin's scope", function()
    local DUI, v = plugin("MyHeals")
    local Options = DUI.Options
    local fired = 0
    DUI.On("OptionsChanged", function() fired = fired + 1 end)
    local page = Options.GetPage("UnitFrames.raid")
    T.truthy(page, "raid page")
    local before = #page.groups
    v.AddOptionsGroup("UnitFrames.raid", groupFor())
    T.eq(#page.groups, before + 1)
    T.truthy(fired >= 1)
    local g = findGroup(page, "Heals")
    T.truthy(g)
    T.truthy(string.find(g.label, "From MyHeals", 1, true), g.label)
    local item = g.items[1]
    T.eq(Options.Get(page, item), false)
    T.truthy(Options.Set(page, item, true))
    T.eq(DUI:Get("MyHeals", "on"), true)
    T.isnil(DUI:Get("UnitFrames", "on"))
    T.eq(Options.Get(page, item), true)
    T.eq(Options.Default(page, item), false)
    T.falsy(stub.ChatContains("Options ("))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api for: a group for a page not there yet arrives when the page does", function()
    local DUI, v = plugin("MyHeals")
    local Options = DUI.Options
    v.AddOptionsGroup("Later.page", groupFor())
    T.isnil(Options.GetPage("Later.page"))
    local page = Options.RegisterPage({ id = "Later.page", section = "core", label = "Later", scope = "general",
        defaults = {}, groups = { { label = "Own", items = {} } } })
    T.eq(#page.groups, 2)
    T.truthy(findGroup(page, "Heals"))
    DUI.Fire("OptionsChanged")
    DUI.Fire("OptionsChanged")
    T.eq(#page.groups, 2, "once")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api for: For('') is refused quietly", function()
    local DUI = load()
    local n = #stub.chat
    T.isnil(DUI.API.For(""))
    T.isnil(DUI.API.For(nil))
    T.isnil(DUI.API.For(5))
    T.eq(#stub.chat, n)
    T.eq(#stub.errors, 0)
end)

T.test("api for: On carries the plugin's name to its errors", function()
    local DUI, v = plugin("MyHeals")
    v.On("FrameMade", function() error("oops-for") end)
    DUI.APIReport.Made("raid", CreateFrame("Frame"), "raid1", false)
    -- The replay hands it the cast bars made at load too, and every error is its own.
    T.truthy(#stub.errors >= 1)
    for _, e in ipairs(stub.errors) do T.truthy(string.find(e, "MyHeals", 1, true), e) end
end)

T.test("api for: two plugins' groups for one waiting page both land, in order", function()
    local DUI, a = plugin("MyHeals")
    DUI:RegisterModule("MyBars", { label = "MyBars", defaults = {} })
    local b = DUI.API.For("MyBars")
    local g2 = groupFor(); g2.label = "Bars"
    a.AddOptionsGroup("Later.page", groupFor())
    b.AddOptionsGroup("Later.page", g2)
    local page = DUI.Options.RegisterPage({ id = "Later.page", section = "core", label = "Later", scope = "general",
        defaults = {}, groups = { { label = "Own", items = {} } } })
    T.eq(#page.groups, 3)
    T.truthy(string.find(page.groups[2].label, "Heals", 1, true))
    T.truthy(string.find(page.groups[3].label, "Bars", 1, true))
    DUI.Fire("OptionsChanged")
    T.eq(#page.groups, 3, "once")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api for: a group with no module of its scope is refused with one line", function()
    local DUI = load()
    local v = DUI.API.For("NoModule")
    local page = DUI.Options.GetPage("core") or DUI.Options.GetPage("home")
    local before, n = #page.groups, #stub.chat
    v.AddOptionsGroup(page.id, groupFor())
    T.eq(#page.groups, before)
    T.eq(#stub.chat, n + 1)
end)

-- A plugin's addon loads after Daylight UI, so the core pages are there before its
-- module registers. Before login the group waits, and at login it lands.
T.test("api for: a group asked for before its module registers lands at login", function()
    local DUI = stub.Load({ login = false })
    local page = DUI.Options.GetPage("appearance")
    T.truthy(page, "a core page made at file load")
    local before, n = #page.groups, #stub.chat
    T.eq(DUI.API.For("EarlyHeals").AddOptionsGroup("appearance", groupFor()), true)
    T.eq(#page.groups, before, "not yet")
    T.eq(#stub.chat, n, "and not refused")
    DUI:RegisterModule("EarlyHeals", { label = "EarlyHeals", defaults = { on = false } })
    stub.FireEvent("PLAYER_LOGIN")
    T.eq(#page.groups, before + 1, "placed at login")
    T.truthy(findGroup(page, "Heals"))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    -- Still no module by login: refused then, with one line.
    local DUI2 = stub.Load({ login = false })
    local page2 = DUI2.Options.GetPage("appearance")
    local b2 = #page2.groups
    DUI2.API.For("NeverHeals").AddOptionsGroup("appearance", groupFor())
    stub.FireEvent("PLAYER_LOGIN")
    T.eq(#page2.groups, b2)
    T.truthy(stub.ChatContains("NeverHeals"), "said once")
end)

T.test("api for: a bad row is left out with one line, the rest land", function()
    local DUI, v = plugin("MyHeals")
    local Options = DUI.Options
    local page = Options.GetPage("UnitFrames.raid")
    local g = groupFor()
    g.items[2] = { type = "toggle", key = "on2", label = "Broken", default = false, disabled = true }
    g.items[3] = { type = "whatsit", key = "x", label = "Odd" }
    g.items[4] = { type = "button", label = "Go", func = function() end, hidden = function() return false end }
    local n = #stub.chat
    v.AddOptionsGroup("UnitFrames.raid", g)
    local card = findGroup(page, "Heals")
    T.truthy(card)
    T.eq(#card.items, 2, "the good rows")
    T.eq(card.items[1].label, "Show heals")
    T.eq(card.items[2].label, "Go")
    T.eq(#stub.chat, n + 2, "one line per bad row")
    T.truthy(stub.ChatContains("MyHeals"))
    for _, item in ipairs(card.items) do
        local ok, err = pcall(Options.IsDisabled, page, item)
        T.truthy(ok, tostring(err))
        ok, err = pcall(Options.IsHidden, page, item)
        T.truthy(ok, tostring(err))
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api for: group.scope saves into that module, and disabled/hidden read it", function()
    local DUI, _ = plugin("MyHeals")
    local o = DUI.API.For("Other")
    local g = groupFor()
    g.scope = "MyHeals"
    g.items[2] = { type = "toggle", key = "on2", label = "More", default = false,
        disabled = function(get) return get("on") ~= true end }
    local Options = DUI.Options
    local page = Options.GetPage("UnitFrames.raid")
    o.AddOptionsGroup("UnitFrames.raid", g)
    local card = page.groups[#page.groups]
    T.truthy(card.items[1].anySize)
    T.truthy(Options.IsDisabled(page, card.items[2]), "off until on")
    T.truthy(Options.Set(page, card.items[1], true))
    T.eq(DUI:Get("MyHeals", "on"), true)
    T.falsy(Options.IsDisabled(page, card.items[2]), "on now")
    -- a refused write is a refusal
    DUI:GetModule("MyHeals").enabled = false
    T.eq(Options.Set(page, card.items[1], false), false)
end)

T.test("api for: a row that isn't a table is left out with one line, and other plugins' waiting groups still land", function()
    local DUI, a = plugin("MyHeals")
    DUI:RegisterModule("MyBars", { label = "MyBars", defaults = {} })
    local b = DUI.API.For("MyBars")
    local bad = { label = "Oops", items = { "oops" } }
    local g2 = groupFor(); g2.label = "Bars"
    -- On a page that exists, no error reaches the plugin.
    local n = #stub.chat
    local ok, err = pcall(a.AddOptionsGroup, "UnitFrames.raid", bad)
    T.truthy(ok, tostring(err))
    T.eq(#stub.chat, n + 1, "one line for the bad row")
    -- Waiting for a page: the bad one first, the good one after it.
    a.AddOptionsGroup("Later.page", bad)
    b.AddOptionsGroup("Later.page", g2)
    local page
    ok, err = pcall(function()
        page = DUI.Options.RegisterPage({ id = "Later.page", section = "core", label = "Later", scope = "general",
            defaults = {}, groups = { { label = "Own", items = {} } } })
    end)
    T.truthy(ok, tostring(err))
    T.truthy(findGroup(page, "Bars"), "the other plugin's group landed")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api for: pages that rebuild their own groups refuse plugin groups with one line", function()
    local DUI, v = plugin("MyHeals")
    for _, id in ipairs({ "plugins", "profiles", "gradients" }) do
        local n = #stub.chat
        T.eq(v.AddOptionsGroup(id, groupFor()), false, id)
        T.eq(#stub.chat, n + 1, id .. ": one line")
    end
end)

T.test("api for: a test part whose available errors leaves the /dui test list working", function()
    local DUI, v = plugin("MyHeals")
    v.RegisterTestPart("bad", "Bad", function() error("avail-bug") end)
    v.RegisterTestPart("good", "Good", function() return true end)
    local ok, err = pcall(DUI.TestBox.Layout)
    T.truthy(ok, tostring(err))
    local keys = {}
    for _, row in ipairs(DUI.TestBox.rows) do if row.key then keys[row.key] = true end end
    T.truthy(keys["plugin.MyHeals.good"], "the good part is listed")
    T.falsy(keys["plugin.MyHeals.bad"], "the broken one is left out")
    T.truthy(#stub.errors >= 1 and string.find(stub.errors[1], "MyHeals", 1, true), tostring(stub.errors[1]))
end)
