local stub = require("stub")

-- The soft AFK screen (DaylightUI_QoL/Afk.lua): up when you go away, gone when you
-- come back, never in combat or under the client's restrictions, and touching
-- nothing of the game's but UIParent's alpha.

local function settle()
    local d = DaylightUI.Motion.Driver()
    for _ = 1, 60 do
        if not (d and d:GetScript("OnUpdate")) then return end
        stub.RunOnUpdate(d, 1 / 60)
    end
end

local function world(db, extra)
    stub.Load({ qol = true, before = function()
        _G.UnitRace = function() return "Night Elf" end
        _G.GetGuildInfo = function() return "Dawnwatch" end
        _G.GetRealZoneText = function() return "Darnassus" end
        _G.GetSubZoneText = function() return "Craftsmen's Terrace" end
        _G.GetAverageItemLevel = function() return 61.4, 58.6 end
        _G.UnitXP = function() return 300 end
        _G.UnitXPMax = function() return 1000 end
        _G.GetMaxPlayerLevel = function() return 60 end
        _G.RequestTimePlayed = function() error("RequestTimePlayed prints in chat: never ask") end
        if extra then extra() end
    end })
    stub.SetUnits({ player = { name = "Ayla", lastName = "Moonwhisper", class = "DRUID", level = 42,
        isPlayer = true, health = 100, maxHealth = 100 } })
    stub.secure = true
    local mod = DaylightUI:GetModule("QoL")
    for k, v in pairs(db or {}) do mod.db[k] = v end
    return stub.qol.Afk
end

local function away(on)
    stub.units.player.afk = on
    stub.FireEvent("PLAYER_FLAGS_CHANGED", "player")
    settle()
end

local function screen() return _G.DaylightUIAfkScreen end
local function up() local s = screen(); return s ~= nil and s:IsShown() == true end

local function texts(frame, out)
    out = out or {}
    for _, r in ipairs({ frame:GetRegions() }) do
        if r.GetText and r:IsShown() and type(r:GetText()) == "string" then out[#out + 1] = r:GetText() end
    end
    for _, c in ipairs({ frame:GetChildren() }) do texts(c, out) end
    return table.concat(out, "\n")
end

T.test("afk: going away brings the screen up and fades the UI", function()
    world()
    away(true)
    T.truthy(up(), "the screen is up")
    T.eq(UIParent.__alpha, 0, "the UI faded away")
    T.eq(screen().__alpha, 1)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("afk: the card shows who, where and how long", function()
    world()
    away(true)
    local all = texts(screen().panel)
    T.truthy(all:find("Ayla Moonwhisper", 1, true), "first and last name: " .. all)
    local sub = screen().panel.sub:GetText()
    T.truthy(sub:find("Level 42 Night Elf ", 1, true), "level, race: " .. sub)
    local hex = DaylightUI.Win.Parts.Hex({ DaylightUI.Style.ClassTextColor("DRUID") })
    T.truthy(sub:find(hex .. "DRUID|r", 1, true), "the class in its color: " .. sub)
    local lr, lg = screen().panel.sub:GetTextColor()
    T.near(lr, DaylightUI.Style.INK.LABEL[1], 0.001, "the rest warm tan")
    T.truthy(all:find("<Dawnwatch>", 1, true), "guild")
    T.truthy(all:find("Craftsmen's Terrace, Darnassus", 1, true), "zone")
    T.falsy(all:find("Item level", 1, true), "no item level: it means little in classic")
    T.truthy(all:find("30%", 1, true), "experience")
    T.falsy(all:find("Played", 1, true), "no played time until the game has said it")
    T.truthy(all:find("0:00", 1, true), "away time starts at zero")
    stub.Advance(65)
    stub.RunOnUpdate(screen(), 1)
    T.truthy(texts(screen().panel):find("1:05", 1, true), "away time counts up")
end)

T.test("afk: played time shows once the game has said it, and counts on", function()
    world()
    stub.FireEvent("TIME_PLAYED_MSG", 2 * 86400 + 3 * 3600, 600)
    stub.Advance(3600)
    away(true)
    T.truthy(texts(screen().panel):find("2d 4h", 1, true), texts(screen().panel))
end)

T.test("afk: coming back glides the UI back", function()
    world()
    away(true)
    away(false)
    T.falsy(up(), "the screen is gone")
    T.eq(UIParent.__alpha, 1, "the UI is back")
end)

T.test("afk: a fight starting snaps everything back, nothing protected touched", function()
    world()
    away(true)
    stub.EnterCombat()
    T.falsy(up(), "the screen stepped aside")
    T.eq(UIParent.__alpha, 1, "the UI is back at once, no fade in combat")
    stub.RunOnUpdate(DaylightUI.Motion.Driver() or screen(), 1 / 60)
    T.eq(UIParent.__alpha, 1)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    -- Still flagged away after the fight, it doesn't come back by itself.
    stub.LeaveCombat()
    stub.FireEvent("PLAYER_FLAGS_CHANGED", "player")
    T.falsy(up(), "no surprise return after the fight")
end)

T.test("afk: combat starting mid-fade-in snaps too", function()
    world()
    stub.units.player.afk = true
    stub.FireEvent("PLAYER_FLAGS_CHANGED", "player")
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 0.1)
    stub.EnterCombat()
    settle()
    T.falsy(up())
    T.eq(UIParent.__alpha, 1)
end)

T.test("afk: never comes up in combat", function()
    world()
    stub.EnterCombat()
    away(true)
    T.falsy(up())
    T.eq(UIParent.__alpha or 1, 1)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("afk: never comes up in a PvP match or a boss fight", function()
    world()
    stub.SetRestriction("PvPMatch", true)
    away(true)
    T.falsy(up(), "PvP match")
    away(false)
    stub.SetRestriction("PvPMatch", false)
    stub.SetRestriction("Encounter", true)
    away(true)
    T.falsy(up(), "boss fight")
end)

T.test("afk: chat lockdown (the AFK flag is secret) is left alone", function()
    world()
    stub.SetRestriction("Chat", true)
    away(true)
    T.falsy(up())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("afk: a restriction starting while up puts the UI back", function()
    world()
    away(true)
    stub.SetRestriction("Encounter", true)
    T.falsy(up())
    T.eq(UIParent.__alpha, 1)
end)

T.test("afk: switched off, nothing happens", function()
    world({ afkScreen = false })
    away(true)
    T.falsy(up())
    T.eq(UIParent.__alpha or 1, 1)
end)

T.test("afk: on by default", function()
    world()
    T.eq(DaylightUI:GetModule("QoL").db.afkScreen, true)
end)

T.test("afk: any key closes it; the key goes on to the game, Escape doesn't", function()
    world()
    away(true)
    local s = screen()
    function s:SetPropagateKeyboardInput(v) self.__propagate = v end
    s.__scripts.OnKeyDown(s, "PRINTSCREEN")
    settle()
    T.truthy(up(), "a screenshot keeps it up")
    T.eq(s.__propagate, true, "and the game takes the screenshot")
    s.__scripts.OnKeyDown(s, "W")
    settle()
    T.falsy(up())
    T.eq(s.__propagate, true, "W walks on")
    T.eq(UIParent.__alpha, 1)
    -- Still flagged away: a flags event for something else doesn't bring it back.
    stub.FireEvent("PLAYER_FLAGS_CHANGED", "player")
    T.falsy(up())
    away(false)
    away(true)
    T.truthy(up(), "back the next time you go away")
    s.__scripts.OnKeyDown(s, "ESCAPE")
    settle()
    T.falsy(up())
    T.eq(s.__propagate, false, "Escape doesn't open the game menu as well")
end)

T.test("afk: a click closes it", function()
    world()
    away(true)
    screen().__scripts.OnMouseDown(screen(), "LeftButton")
    settle()
    T.falsy(up())
end)

T.test("afk: a ready check or a queue pop steps it aside", function()
    world()
    away(true)
    stub.FireEvent("READY_CHECK", "Someone", 30)
    settle()
    T.falsy(up(), "ready check")
    away(false)
    away(true)
    _G.GetBattlefieldStatus = function() return "queued" end
    stub.FireEvent("UPDATE_BATTLEFIELD_STATUS", 1)
    settle()
    T.truthy(up(), "only queued: stays")
    _G.GetBattlefieldStatus = function() return "confirm" end
    stub.FireEvent("UPDATE_BATTLEFIELD_STATUS", 1)
    settle()
    T.falsy(up(), "battleground ready: steps aside")
end)

T.test("afk: /dui afk previews it and closes it again", function()
    world()
    DaylightUI.RunCommand("afk")
    settle()
    T.truthy(up(), "preview up without the flag")
    -- A flags event that isn't going away doesn't close the preview.
    stub.FireEvent("PLAYER_FLAGS_CHANGED", "player")
    T.truthy(up())
    DaylightUI.RunCommand("afk")
    settle()
    T.falsy(up())
    T.eq(UIParent.__alpha, 1)
end)

T.test("afk: the preview refuses in combat", function()
    world()
    stub.EnterCombat()
    DaylightUI.RunCommand("afk")
    T.falsy(up())
    T.truthy(stub.ChatContains("can't show"), "says why")
end)

T.test("afk: the options page has the switch and the preview", function()
    world()
    local page = DaylightUI.Options.GetPage("QoL.qol")
    local found = {}
    for _, g in ipairs(page.groups) do
        for _, item in ipairs(g.items) do found[item.key or item.label] = item end
    end
    T.truthy(found.afkScreen, "the switch")
    local preview = found["Preview the AFK screen"]
    T.truthy(preview, "the preview button")
    preview.func()
    settle()
    T.truthy(up())
end)

T.test("afk: the model is set up and sways once loaded", function()
    local Afk = world()
    local actor = { yaw = 0 }
    function actor:IsLoaded() return true end
    function actor:SetYaw(y) self.yaw = y end
    function actor:GetYaw() return self.yaw end
    _G.ModelSceneUtil = { SetUpCharacterSheetScene = function(scene)
        scene.GetPlayerActor = function() return actor end
    end }
    away(true)
    local s = screen()
    T.truthy(s.scene, "a model scene")
    T.eq(s.scene.__alpha, 0, "hidden until loaded")
    stub.RunOnUpdate(s, 0.1)    -- loaded
    stub.RunOnUpdate(s, 1)
    T.eq(s.scene.__alpha, 1, "faded in")
    T.truthy(actor.yaw ~= 0, "turning")
    _G.ModelSceneUtil = nil
    T.truthy(Afk.Shown())
end)

-- ---------------------------------------------------------------------
-- Rested XP and the fun facts (AfkFacts.lua)
-- ---------------------------------------------------------------------

-- A character with something to say about everything.
local function lively()
    _G.GetXPExhaustion = function() return 750 end
    _G.C_QuestLog = _G.C_QuestLog or {}
    _G.C_QuestLog.GetAllCompletedQuestIDs = function() local t = {} for i = 1, 1412 do t[i] = i end return t end
    _G.GetPVPLifetimeStats = function() return 37, 0 end
    _G.C_SkillInfo = {
        GetNumSkillLines = function() return 3 end,
        GetSkillLineInfo = function(i)
            return ({ { skillID = 0, name = "Professions", isHeader = true, rank = 0, maxRank = 0 },
                { skillID = 186, name = "Mining", isHeader = false, rank = 150, maxRank = 150 },
                { skillID = 95, name = "Defense", isHeader = false, rank = 200, maxRank = 210 } })[i]
        end,
    }
    _G.GetMoney = function() return 4567890 end
end

local function fact() local f = screen().panel.fact; return f:IsShown() and (f.head:GetText() .. " " .. f.line:GetText()) or nil end

-- Shows every fact that fits, in deck order, by turning the card over.
local function allFacts(n)
    local seen = {}
    for _ = 1, n or 20 do
        local f = fact()
        if f then seen[#seen + 1] = f end
        for _ = 1, stub.qol.AfkFacts.EVERY do stub.RunOnUpdate(screen(), 1) end
        settle()
    end
    return table.concat(seen, " | ")
end

T.test("afk: rested XP shows under experience, as a share of a level", function()
    world(nil, lively)
    away(true)
    T.truthy(texts(screen().panel):find("75% of a level", 1, true), texts(screen().panel))
end)

T.test("afk: no rested row at max level or with none", function()
    world(nil, function() lively(); _G.GetXPExhaustion = function() return nil end end)
    away(true)
    T.falsy(texts(screen().panel):find("Rested", 1, true))
end)

T.test("afk: a fun fact shows, and turns over to a different one", function()
    world(nil, lively)
    away(true)
    local first = fact()
    T.truthy(first, "a fact on the card")
    for _ = 1, stub.qol.AfkFacts.EVERY - 1 do stub.RunOnUpdate(screen(), 1) end
    settle()
    T.eq(fact(), first, "stays a while")
    stub.RunOnUpdate(screen(), 1)
    settle()
    T.truthy(fact() ~= first, "then a new one: " .. tostring(fact()))
    T.eq(screen().panel.fact.__alpha or 1, 1, "faded back in")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("afk: the facts say what fits this character", function()
    world(nil, function()
        lively()
        _G.IsInGuild = function() return true end
        _G.GetNumGuildMembers = function() return 40, 6 end
    end)
    stub.units.pet = { name = "Snowpaw", health = 10, maxHealth = 10 }
    away(true)
    local all = allFacts(30)
    T.truthy(all:find("1,412 quests", 1, true), "quests done: " .. all)
    T.truthy(all:find("37 honorable kills", 1, true), "honorable kills")
    T.truthy(all:find("Mining 150 / 150. Time to visit a trainer.", 1, true), "a profession at its cap")
    T.falsy(all:find("Defense", 1, true), "weapon skills aren't professions")
    T.truthy(all:find("XP to level 43", 1, true) or all:find("XP until level 43", 1, true), "XP to the next level")
    T.truthy(all:find("Snowpaw", 1, true), "your pet by name")
    T.truthy(all:find("5 guildmates online", 1, true), "guildmates, not counting you")
    T.truthy(all:find("456", 1, true), "your gold")
end)

T.test("afk: long away gets its own lines", function()
    world(nil, lively)
    away(true)
    local Facts = stub.qol.AfkFacts
    T.isnil(Facts.Read("away"), "not after a minute")
    stub.Advance(1900)
    local _, line = Facts.Read("away")
    T.truthy(line and line:find("innkeeper", 1, true), tostring(line))
    stub.Advance(2000)
    _, line = Facts.Read("away")
    T.truthy(line and line:find("Over an hour", 1, true), tostring(line))
end)

T.test("afk: played time facts once the game has said it", function()
    world(nil, lively)
    stub.FireEvent("TIME_PLAYED_MSG", 3 * 86400, 5400)
    local Facts = stub.qol.AfkFacts
    Facts.Random = function() return 1 end
    local _, line = Facts.Read("played")
    T.truthy(line:find("at level 42", 1, true), line)
    Facts.Random = function(n) return n end
    _, line = Facts.Read("played")
    T.truthy(line:find("3 whole days", 1, true), line)
end)

T.test("afk: the card keeps its height as facts turn over", function()
    world(nil, lively)
    away(true)
    local h = screen().panel:GetHeight()
    for _ = 1, 4 do
        for _ = 1, stub.qol.AfkFacts.EVERY do stub.RunOnUpdate(screen(), 1) end
        settle()
        T.eq(screen().panel:GetHeight(), h)
    end
end)

T.test("afk: with nothing to say, no fact and no gap", function()
    world(nil, function()
        _G.GetMoney = function() return 0 end
        _G.UnitXPMax = function() return 0 end
        _G.IsInGuild = function() return false end
        _G.GetPVPLifetimeStats = function() return 0, 0 end
        _G.C_SkillInfo = nil
        if _G.C_QuestLog then _G.C_QuestLog.GetAllCompletedQuestIDs = function() return {} end end
    end)
    local date = _G.date
    _G.date = function(f, ...) if f == "%H" then return "14" end return date(f, ...) end
    away(true)
    _G.date = date
    T.falsy(screen().panel.fact:IsShown(), tostring(screen().panel.fact.key))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("afk: secret answers just leave a fact out", function()
    world(nil, function()
        lively()
        _G.GetPVPLifetimeStats = function() return stub.Secret(37), 0 end
        _G.GetMoney = function() return stub.Secret(100) end
    end)
    away(true)
    local Facts = stub.qol.AfkFacts
    T.isnil(Facts.Read("honor"))
    T.isnil(Facts.Read("gold"))
    T.truthy(Facts.Read("quests"))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: the arrow and the quest and tracking dots floated over the AFK
-- screen with the map only see-through. They draw whatever the map's alpha,
-- its own too, so it hides while the UI is away.
T.test("afk: the minimap hides while the UI is away (its arrow and dots ignore any alpha) and comes back after", function()
    world(nil, function() CreateFrame("Frame", "Minimap", UIParent) end)
    local backs = 0
    DaylightUI.On("MinimapBack", function() backs = backs + 1 end)
    away(true)
    T.falsy(Minimap:IsVisible(), "the player arrow and quest dots would show on the AFK screen")
    T.eq(Minimap:GetAlpha(), 1, "its alpha isn't what hides it")
    away(false)
    T.truthy(Minimap:IsShown(), "back with the UI")
    T.eq(backs, 1, "told it's back, so the info panel redraws it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("afk: a minimap hidden before stays hidden after", function()
    world(nil, function() CreateFrame("Frame", "Minimap", UIParent) end)
    Minimap:Hide()
    away(true)
    away(false)
    T.falsy(Minimap:IsShown())
end)

T.test("afk: a map someone else made see-through stays so after", function()
    world(nil, function() CreateFrame("Frame", "Minimap", UIParent) end)
    Minimap:SetAlpha(0.4)
    away(true)
    away(false)
    T.near(Minimap:GetAlpha(), 0.4, 0.001)
end)
