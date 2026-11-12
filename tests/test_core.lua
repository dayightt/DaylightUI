local stub = require("stub")

T.test("Print prefixes the addon name", function()
    local DUI = stub.Load()
    DUI.Print("hello")
    T.truthy(stub.ChatContains(DUI.GradientText("DaylightUI") .. ": hello"))
end)

T.test("the global points at the namespace", function()
    local DUI = stub.Load()
    T.eq(DaylightUI, DUI)
end)

T.test("RegisterEvent dispatches client events with their payload", function()
    local DUI = stub.Load()
    local got
    DUI.RegisterEvent("PLAYER_TARGET_CHANGED", function(event, a) got = event .. ":" .. tostring(a) end)
    stub.FireEvent("PLAYER_TARGET_CHANGED", "x")
    T.eq(got, "PLAYER_TARGET_CHANGED:x")
end)

T.test("On/Fire call listeners in registration order", function()
    local DUI = stub.Load()
    local order = {}
    DUI.On("Thing", function(v) order[#order + 1] = "a" .. v end)
    DUI.On("Thing", function(v) order[#order + 1] = "b" .. v end)
    DUI.Fire("Thing", 1)
    T.eq(table.concat(order, ","), "a1,b1")
end)

T.test("AfterCombat runs immediately out of combat", function()
    local DUI = stub.Load()
    local ran = false
    T.truthy(DUI.AfterCombat(function() ran = true end))
    T.truthy(ran)
end)

T.test("AfterCombat queues in combat and runs in order when combat ends", function()
    local DUI = stub.Load()
    local order = {}
    stub.EnterCombat()
    T.falsy(DUI.AfterCombat(function() order[#order + 1] = 1 end))
    DUI.AfterCombat(function() order[#order + 1] = 2 end)
    T.eq(#order, 0, "nothing yet")
    stub.LeaveCombat()
    T.eq(table.concat(order, ","), "1,2")
end)

T.test("AfterCombat with a key keeps only the latest function for that key", function()
    local DUI = stub.Load()
    local order = {}
    stub.EnterCombat()
    DUI.AfterCombat(function() order[#order + 1] = "old" end, "k")
    DUI.AfterCombat(function() order[#order + 1] = "other" end)
    DUI.AfterCombat(function() order[#order + 1] = "new" end, "k")
    stub.LeaveCombat()
    T.eq(table.concat(order, ","), "new,other")
end)

T.test("an erroring queued function does not stop the rest", function()
    local DUI = stub.Load()
    local ran = false
    stub.EnterCombat()
    DUI.AfterCombat(function() error("boom") end)
    DUI.AfterCombat(function() ran = true end)
    stub.LeaveCombat()
    T.truthy(ran)
    T.eq(#stub.errors, 1)
end)

T.test("Fire runs listeners through SafeCall so one error doesn't stop the rest", function()
    local DUI = stub.Load()
    local ran = false
    DUI.On("Thing", function() error("boom") end)
    DUI.On("Thing", function() ran = true end)
    DUI.Fire("Thing")
    T.truthy(ran)
    T.eq(#stub.errors, 1)
end)

T.test("RegisterEvent runs handlers through SafeCall so one error doesn't stop the rest", function()
    local DUI = stub.Load()
    local ran = false
    DUI.RegisterEvent("PLAYER_TARGET_CHANGED", function() error("boom") end)
    DUI.RegisterEvent("PLAYER_TARGET_CHANGED", function() ran = true end)
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.truthy(ran)
    T.eq(#stub.errors, 1)
end)

T.test("the same error reports once, then at 10, 100 and 1000 times, not every call", function()
    local DUI = stub.Load()
    for _ = 1, 150 do DUI.SafeCall(function() error("boom") end) end
    T.eq(#stub.errors, 3)
    T.truthy(string.find(stub.errors[2], "(seen 10 times)", 1, true))
    T.truthy(string.find(stub.errors[3], "(seen 100 times)", 1, true))
    DUI.SafeCall(function() error("another") end)
    T.eq(#stub.errors, 4, "a different error reports at once")
end)

T.test("a secret error report doesn't break SafeCall: passed on unchanged, counted once", function()
    local DUI = stub.Load()
    local ok
    for _ = 1, 15 do
        T.noerror(function() ok = DUI.SafeCall(function() error(stub.Secret("boom")) end) end)
    end
    T.falsy(ok)
    T.eq(#stub.errors, 2, "the 1st and the 10th")
end)

T.test("a secret stack is dropped: different errors in a fight each report", function()
    local DUI = stub.Load()
    local old = _G.debugstack
    _G.debugstack = function() return stub.Secret("stack") end
    DUI.SafeCall(function() error("first") end)
    DUI.SafeCall(function() error("second") end)
    _G.debugstack = old
    T.eq(#stub.errors, 2, "both reported, not swallowed by one shared count")
    T.falsy(issecretvalue(stub.errors[2]), "the report stays readable")
end)

T.test("/dui runs registered commands and prints help otherwise", function()
    local DUI = stub.Load()
    local got
    DUI.RegisterCommand("ping", function(rest) got = rest end, "/dui ping - test command")
    SlashCmdList.DAYLIGHTUI("PING hello there")
    T.eq(got, "hello there")
    SlashCmdList.DAYLIGHTUI("nope")
    T.falsy(stub.ChatContains("/dui ping - test command"), "a typo lists only the player's commands")
    T.truthy(stub.ChatContains("/dui unlock - move frames"))
    T.truthy(stub.ChatContains("/dui all - every command"))
    SlashCmdList.DAYLIGHTUI("all")
    T.truthy(stub.ChatContains("/dui ping - test command"), "/dui all lists every command")
end)

T.test("/rl and /reloadui reload the UI", function()
    stub.Load()
    T.eq(SLASH_DAYLIGHTUIRELOAD1, "/rl")
    T.eq(SLASH_DAYLIGHTUIRELOAD2, "/reloadui")
    stub.reloaded = nil
    SlashCmdList.DAYLIGHTUIRELOAD("")
    T.truthy(stub.reloaded)
end)

T.test("first and last names: only with the setting on, never joining a secret", function()
    local DUI = stub.Load()
    stub.units.party1 = { name = "Bone", lastName = "Money", isPlayer = true }
    T.eq(DUI.UnitName("party1"), "Bone Money", "on by default")
    DUI:Set("general", "lastNames.party", false)
    T.eq(DUI.UnitName("party1"), "Bone", "off for party only")
    T.eq(DUI.UnitName("party1", "nameplates"), "Bone Money", "nameplates keep their own switch")
    DUI:Set("general", "lastNames.party", true)
    T.eq(DUI.UnitName("party1"), "Bone Money")
    stub.units.party1.lastName = nil
    T.eq(DUI.UnitName("party1"), "Bone", "no last name: just the first")
end)

-- A fake Total RP 3 with its real public calls (totalRP3 3.5.4, Core/Player.lua):
-- AddOn_TotalRP3.Player.CreateFromCharacterID, TRP3_NameUtil.GetQualifiedName,
-- TRP3_API.register.isUnitIDKnown, TRP3_API.profile.isDefaultProfile ("*" at the
-- end means the default profile, not a roleplay one), TRP3_API.RegisterCallback.
local function fakeTRP3(profiles, callbacks)
    local Player = {}
    Player.__index = Player
    function Player:GetProfileID() return profiles[self.id] and profiles[self.id].profileID end
    function Player:GetFirstName() return profiles[self.id] and profiles[self.id].FN end
    function Player:GetLastName() return profiles[self.id] and profiles[self.id].LN end
    function Player:GetRoleplayingName()
        local name = self:GetFirstName() or self.id
        if self:GetLastName() then name = name .. " " .. self:GetLastName() end
        return name
    end
    _G.AddOn_TotalRP3 = { Player = { CreateFromCharacterID = function(id) return setmetatable({ id = id }, Player) end } }
    _G.TRP3_NameUtil = { GetQualifiedName = function(unit)
        local first, last = UnitFullName(unit)
        if type(first) == "table" then error("secret") end
        return first .. "-" .. (last or "")
    end }
    _G.TRP3_Addon = { Events = { REGISTER_DATA_UPDATED = "REGISTER_DATA_UPDATED", REGISTER_PROFILES_LOADED = "REGISTER_PROFILES_LOADED" } }
    _G.TRP3_API = {
        register = { isUnitIDKnown = function(id) return profiles[id] ~= nil end },
        profile = { isDefaultProfile = function(pid) return type(pid) == "string" and pid:sub(-1) == "*" end },
        RegisterCallback = function(_, event, fn) callbacks[event] = fn end,
    }
end

T.test("Total RP 3 names: a roleplay profile's name, first or full by the element's switch", function()
    local profiles, callbacks = {}, {}
    local DUI = stub.Load({ before = function() fakeTRP3(profiles, callbacks) end })
    stub.units.party1 = { name = "Bone", lastName = "Money", isPlayer = true }
    T.eq(DUI.UnitName("party1"), "Bone Money", "unknown to Total RP 3: the game's name")
    profiles["Bone-Money"] = { profileID = "abc", FN = "Aldric", LN = "Thorne" }
    T.eq(DUI.UnitName("party1"), "Aldric Thorne", "a roleplay name, first and last")
    DUI:Set("general", "lastNames.party", false)
    T.eq(DUI.UnitName("party1"), "Aldric", "last names off: the roleplay first name")
    DUI:Set("general", "lastNames.party", true)
    profiles["Bone-Money"].profileID = "def*"
    T.eq(DUI.UnitName("party1"), "Bone Money", "the default profile isn't a roleplay name")
    profiles["Bone-Money"].profileID = "abc"
    DUI:Set("general", "rpNames", false)
    T.eq(DUI.UnitName("party1"), "Bone Money", "switched off: the game's name")
    DUI:Set("general", "rpNames", true)
    stub.units.npc1 = { name = "Bone", lastName = "Money", isPlayer = false }
    T.eq(DUI.UnitName("npc1", "party"), "Bone Money", "only players")
    stub.units.party1.name = stub.Secret("Bone")
    T.eq(stub.Plain(DUI.UnitName("party1")), "Bone", "a secret name never reaches Total RP 3")
    stub.units.party1.name = "Bone"
    -- New data from Total RP 3 tells the frames once, a moment later.
    local told = 0
    DUI.On("NamesChanged", function() told = told + 1 end)
    T.truthy(callbacks.REGISTER_DATA_UPDATED, "listens to Total RP 3")
    callbacks.REGISTER_DATA_UPDATED()
    callbacks.REGISTER_DATA_UPDATED()
    stub.RunTimers()
    T.eq(told, 1, "many updates, one refresh")
    _G.AddOn_TotalRP3, _G.TRP3_NameUtil, _G.TRP3_Addon, _G.TRP3_API = nil, nil, nil, nil
end)

T.test("login says the version, and a newer copy seen over addon messages asks to update once", function()
    local sent = {}
    local DUI = stub.Load({ before = function()
        _G.C_ChatInfo = {
            RegisterAddonMessagePrefix = function() end,
            SendAddonMessage = function(_, msg, channel) sent[#sent + 1] = channel .. " " .. msg end,
        }
    end })
    local function count(text)
        local n = 0
        for _, m in ipairs(stub.chat) do if string.find(m, text, 1, true) then n = n + 1 end end
        return n
    end
    T.eq(count("version " .. DUI.VERSION .. " loaded"), 1)
    T.truthy(DUI.IsNewerVersion("0.10.0", "0.9.9"))
    T.falsy(DUI.IsNewerVersion("0.5.3", "0.5.3"))
    T.falsy(DUI.IsNewerVersion("dev", "0.5.3"))
    DUI.VERSION = "0.5.3"
    stub.FireEvent("CHAT_MSG_ADDON", "DaylightUI", "V:0.6.0", "GUILD")
    stub.FireEvent("CHAT_MSG_ADDON", "DaylightUI", "V:0.7.0", "GUILD")
    T.eq(count("has an update"), 1, "only once a session")
    stub.FireEvent("CHAT_MSG_ADDON", "DaylightUI", "V:0.4.0", "PARTY")
    T.eq(sent[#sent], "PARTY V:0.5.3", "an older copy gets our version back")
    -- A whisper or channel answer needs a target the event doesn't give.
    local before = #sent
    stub.FireEvent("CHAT_MSG_ADDON", "DaylightUI", "V:0.4.0", "WHISPER")
    stub.FireEvent("CHAT_MSG_ADDON", "DaylightUI", "V:0.4.0", "CHANNEL")
    T.eq(#sent, before, "never answered on a whisper or a channel")
    _G.C_ChatInfo = nil
end)

-- An update caught halfway: the module stays off with one line instead of erroring
-- hundreds of times.
T.test("core: a module with a missing file stays off and asks for a restart, once", function()
    stub.Load()
    local ran = false
    local ns = { Here = {} }
    DaylightUI:RegisterModule("PartsProbe", { label = "Parts probe", ns = ns, parts = { "Here", "Gone" },
        OnEnable = function() ran = true end })
    T.falsy(ran, "OnEnable not run")
    T.truthy(stub.ChatContains("Parts probe is missing Gone: /reload"), "one line in chat")
end)

T.test("core: a module with every part enables as before", function()
    stub.Load()
    local ran = false
    DaylightUI:RegisterModule("PartsProbe2", { ns = { Here = {} }, parts = { "Here" },
        OnEnable = function() ran = true end })
    T.truthy(ran)
end)

T.test("taint: /dui taint lists a game value we marked, and nothing else", function()
    stub.Load()
    local game = CreateFrame("Frame", "SomeGameFrame")
    game.owned, game.ours = 1, 2
    stub.Mark(game, "ours", "DaylightUI_Chat")
    _G.LeakedGlobal = true
    stub.Mark(nil, "LeakedGlobal", "DaylightUI")
    local own = CreateFrame("Frame", "DaylightUIProbeFrame")
    own.x = 1
    stub.Mark(own, "x", "DaylightUI")                   -- the addon's own: expected, not listed
    T.deq((DaylightUI.Taint.Scan()), { "LeakedGlobal  (DaylightUI)", "SomeGameFrame.ours  (DaylightUI_Chat)" })
    _G.LeakedGlobal = nil
end)

-- In game the report had 2575 lines, ~2500 of them the addon's own pieces on buttons
-- the client made inside its frames (buff buttons, bag slots, plate aura
-- containers). Those aren't the game's. The game's frames borrowed into the addon's
-- holders (named by the game) still count.
T.test("taint: frames inside ours are skipped, the game's borrowed frames are not", function()
    stub.Load()
    local holder = CreateFrame("Frame", "DaylightUITaintHolder")
    local box = CreateFrame("Frame", nil, holder)          -- a client container in an addon holder
    local btn = CreateFrame("Button", nil, box)
    btn.Count = 1
    stub.Mark(btn, "Count", "DaylightUI_Buffs")
    local plate = CreateFrame("Frame", nil, UIParent)      -- an anonymous addon frame
    plate.unit = "nameplate1"
    stub.Mark(plate, "unit", "DaylightUI_Nameplates")
    for k in pairs(plate) do if k ~= "unit" then stub.Mark(plate, k, "DaylightUI_Nameplates") end end
    local c = CreateFrame("Frame", nil, plate)             -- the client's aura container on it
    c.kind = "debuffs"
    stub.Mark(c, "kind", "DaylightUI_Nameplates")
    local borrowed = CreateFrame("Frame", "GameTotemsTaint", holder)
    borrowed.spacing = 4
    stub.Mark(borrowed, "spacing", "DaylightUI_ActionBars")
    local inner = CreateFrame("Button", nil, borrowed)
    inner.flag = true
    stub.Mark(inner, "flag", "DaylightUI_ActionBars")
    local out = DaylightUI.Taint.Scan()
    local listed = {}
    for _, line in ipairs(out) do listed[#listed + 1] = line:match("%.([%w_]+)  %(") end
    table.sort(listed)
    T.deq(listed, { "flag", "spacing" })
end)

T.test("taint: a forbidden frame is skipped without an error", function()
    stub.Load()
    local f = CreateFrame("Frame", "ForbiddenThing")
    function f:IsForbidden() return true end
    f.x = 1
    stub.Mark(f, "x", "DaylightUI")
    local out
    T.noerror(function() out = DaylightUI.Taint.Scan() end)
    T.eq(#out, 0)
end)

-- An aura button's debug name came back secret and the scan stopped ("cannot be
-- indexed with secret keys").
T.test("taint: a frame with a secret debug name is listed by its plain name", function()
    stub.Load()
    local f = CreateFrame("Button", "SecretNamedButton")
    function f:GetDebugName() return stub.Secret("SecretNamedButton") end
    f.ours = 1
    stub.Mark(f, "ours", "DaylightUI_Buffs")
    local out
    T.noerror(function() out = DaylightUI.Taint.Scan() end)
    T.deq(out, { "SecretNamedButton.ours  (DaylightUI_Buffs)" })
end)

T.test("taint: the check after login runs only with the taint log on", function()
    stub.Load()
    local game = CreateFrame("Frame", "SomeGameFrame2")
    game.ours = 1
    stub.Mark(game, "ours", "DaylightUI")
    _G.GetCVar = function(k) if k == "taintLog" then return "0" end end
    stub.FireEvent("PLAYER_ENTERING_WORLD", true, false)
    stub.RunTimers()
    T.falsy(stub.ChatContains("marked by DaylightUI"), "taint log off: quiet")
    _G.GetCVar = function(k) if k == "taintLog" then return "1" end end
    stub.FireEvent("PLAYER_ENTERING_WORLD", true, false)
    stub.RunTimers()
    T.truthy(stub.ChatContains("marked by DaylightUI"), "taint log on: one line")
    _G.GetCVar = nil
end)

local function coin(DUI, name) return DUI.CoinIcon(name) end

T.test("money: gold, silver and copper with our coins", function()
    local DUI = stub.Load()
    T.eq(DUI.MoneyString(12345), "1" .. coin(DUI, "gold") .. " 23" .. coin(DUI, "silver") .. " 45" .. coin(DUI, "copper"))
end)

T.test("money: zero parts are left out", function()
    local DUI = stub.Load()
    T.eq(DUI.MoneyString(10005), "1" .. coin(DUI, "gold") .. " 5" .. coin(DUI, "copper"))
    T.eq(DUI.MoneyString(300), "3" .. coin(DUI, "silver"))
end)

T.test("money: a secret amount gives empty text, no error", function()
    local DUI = stub.Load()
    T.eq(DUI.MoneyString(stub.Secret(12345)), "")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("money: nothing, nil or negative shows 0 copper", function()
    local DUI = stub.Load()
    local zero = "0" .. coin(DUI, "copper")
    T.eq(DUI.MoneyString(0), zero)
    T.eq(DUI.MoneyString(nil), zero)
    T.eq(DUI.MoneyString(-50), zero)
    T.eq(DUI.MoneyString("12"), zero, "not a number")
end)

T.test("money: gold gets thousands separators", function()
    local DUI = stub.Load()
    T.eq(DUI.MoneyString(12345670000), "1,234,567" .. coin(DUI, "gold"))
end)

T.test("time left: nothing under a second, like the aura buttons' own text", function()
    local DUI = stub.Load()
    T.eq(DUI.FormatTime(0.5), "")
    T.eq(DUI.FormatTime(1), "1s"); T.eq(DUI.FormatTime(59.9), "59s"); T.eq(DUI.FormatTime(180), "3m")
    T.eq(DUI.FormatTime(nil), ""); T.eq(DUI.FormatTime(-3), "")
end)

T.test("clock and thousands: one helper each", function()
    local DUI = stub.Load()
    T.eq(DUI.FormatClock(178), "2:58")
    T.eq(DUI.FormatClock(59.9), "0:59", "floored")
    T.eq(DUI.FormatClock(nil), ""); T.eq(DUI.FormatClock(-1), ""); T.eq(DUI.FormatClock(stub.Secret(5)), "")
    T.eq(DUI.Thousands(1234567), "1,234,567")
    T.eq(DUI.Thousands(-17400), "-17,400")
end)

T.test("money: colourblind mode gets the game's text version", function()
    local DUI = stub.Load()
    _G.ENABLE_COLORBLIND_MODE = "1"
    _G.GetMoneyString = function(m, sep) return "text:" .. m .. ":" .. tostring(sep) end
    local s = DUI.MoneyString(12345)
    _G.ENABLE_COLORBLIND_MODE, _G.GetMoneyString = nil, nil
    T.eq(s, "text:12345:true")
end)

T.test("money: colourblind mode read from the game's setting", function()
    local DUI = stub.Load()
    local saved = _G.C_CVar
    _G.C_CVar = { GetCVarBool = function(name) return name == "colorblindMode" end }
    _G.GetMoneyString = function(m) return "text:" .. m end
    local s = DUI.MoneyString(250)
    _G.C_CVar, _G.GetMoneyString = saved, nil
    T.eq(s, "text:250")
end)
