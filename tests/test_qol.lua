local stub = require("stub")

-- The quality-of-life module: the skeleton registers and shows its page.

T.test("qol: the module registers and its options page exists", function()
    stub.Load({ qol = true })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(DaylightUI:GetModule("QoL"), "module registered")
    T.truthy(DaylightUI.Options.GetPage("QoL.qol"), "the options page exists")
end)

local function popupSetup(setting)
    local box = { text = "" }
    function box:SetText(t) self.text = t end
    _G.DELETE_ITEM_CONFIRM_STRING = "DELETE"
    _G.StaticPopup_Show = function() end
    local cur
    _G.StaticPopup_FindVisible = function(which) if cur and cur.which == which then return cur end end
    stub.Load({ qol = true })
    DaylightUI:GetModule("QoL").db.autoDelete = setting
    return box, function(which) cur = { which = which, editBox = box }; StaticPopup_Show(which) end
end

T.test("qol: DELETE is filled in for a good item", function()
    local box, show = popupSetup(true)
    show("DELETE_GOOD_ITEM")
    T.eq(box.text, "DELETE")
end)

T.test("qol: other popups are left alone", function()
    local box, show = popupSetup(true)
    show("SOMETHING_ELSE")
    T.eq(box.text, "")
end)

T.test("qol: turning the option off does nothing", function()
    local box, show = popupSetup(false)
    show("DELETE_GOOD_ITEM")
    T.eq(box.text, "")
end)

-- Fast loot.

local function lootSetup(setting, autoDefault, modifier)
    local looted = {}
    _G.GetCVarBool = function() return autoDefault end
    _G.IsModifiedClick = function() return modifier end
    _G.GetNumLootItems = function() return 3 end
    _G.LootSlot = function(i) looted[#looted + 1] = i end
    stub.Load({ qol = true })
    DaylightUI:GetModule("QoL").db.fastLoot = setting
    return looted
end

T.test("qol: fast loot takes every slot once when auto loot is on", function()
    local looted = lootSetup(true, true, false)
    stub.FireEvent("LOOT_READY")
    T.eq(table.concat(looted, ","), "3,2,1")
end)

T.test("qol: fast loot does nothing when auto loot is off", function()
    local looted = lootSetup(true, false, false)
    stub.FireEvent("LOOT_READY")
    T.eq(#looted, 0)
end)

T.test("qol: the modifier key flips auto loot", function()
    local looted = lootSetup(true, false, true)
    stub.FireEvent("LOOT_READY")
    T.eq(#looted, 3)
end)

T.test("qol: fast loot does nothing when the option is off", function()
    local looted = lootSetup(false, true, false)
    stub.FireEvent("LOOT_READY")
    T.eq(#looted, 0)
end)

T.test("qol: fast loot is throttled to once per 0.3 seconds", function()
    local looted = lootSetup(true, true, false)
    stub.FireEvent("LOOT_READY")
    stub.FireEvent("LOOT_READY")
    T.eq(#looted, 3, "second event inside 0.3s ignored")
    stub.Advance(0.5)
    stub.FireEvent("LOOT_READY")
    T.eq(#looted, 6)
end)

-- Train All.

local function trainerSetup(services, money, setting)
    local bought, printed = {}, {}
    _G.GetNumTrainerServices = function() return #services end
    _G.GetTrainerServiceInfo = function(i) return "Spell " .. i, services[i].status, nil, 0, "Rank 1" end
    _G.GetTrainerServiceCost = function(i) return services[i].cost, services[i].profession == true end
    _G.GetMoney = function() return money end
    _G.BuyTrainerService = function(i)
        bought[#bought + 1] = i
        services[i].status = "used"
        money = money - services[i].cost
    end
    stub.Load({ qol = true })
    local unitExists = _G.UnitExists
    _G.UnitExists = function(u) return u == "npc" or unitExists(u) end
    _G.ClassTrainerFrame = CreateFrame("Frame", "ClassTrainerFrame", UIParent)
    ClassTrainerFrame:Show()
    DaylightUI:GetModule("QoL").db.trainAll = setting ~= false
    DaylightUI.Print = function(m) printed[#printed + 1] = m end
    stub.FireEvent("TRAINER_SHOW")
    return bought, printed
end

T.test("qol: train all counts only available, affordable services", function()
    local bought = trainerSetup({
        { status = "available", cost = 10 }, { status = "unavailable", cost = 5 },
        { status = "available", cost = 100 }, { status = "available", cost = 20 },
    }, 50)
    T.eq(DaylightUITrainAllButton:GetText(), "Train all (2)")
    T.eq(#bought, 0)
end)

T.test("qol: train all buys them in order and reports", function()
    local bought, printed = trainerSetup({
        { status = "available", cost = 10 }, { status = "available", cost = 20 },
    }, 100)
    DaylightUITrainAllButton:GetScript("OnClick")()
    stub.RunTimers()
    T.eq(table.concat(bought, ","), "1,2")
    T.truthy(printed[1] and printed[1]:find("Learned 2 skills"), tostring(printed[1]))
end)

T.test("qol: train all on a slow server never buys the same skill twice", function()
    local services = { { status = "available", cost = 10 }, { status = "available", cost = 20 } }
    local bought = trainerSetup(services, 100)
    -- The server hasn't answered yet: every line still reads available.
    _G.BuyTrainerService = function(i) bought[#bought + 1] = i end
    DaylightUITrainAllButton:GetScript("OnClick")()
    stub.RunTimers()
    T.eq(table.concat(bought, ","), "1,2", "each once")
end)

T.test("qol: train all skips a service with no plain gold cost", function()
    local bought = trainerSetup({ { status = "available", cost = false } }, 100)
    DaylightUITrainAllButton:GetScript("OnClick")()
    stub.RunTimers()
    T.eq(#bought, 0)
end)

T.test("qol: train all never learns a new profession (it uses up a slot)", function()
    local bought = trainerSetup({
        { status = "available", cost = 10, profession = true }, { status = "available", cost = 20 },
    }, 100)
    T.eq(DaylightUITrainAllButton:GetText(), "Train all (1)")
    DaylightUITrainAllButton:GetScript("OnClick")()
    stub.RunTimers()
    T.eq(table.concat(bought, ","), "2")
end)

T.test("qol: train all stays off at a pet trainer (training points, not gold)", function()
    _G.C_Trainer = { GetTrainerType = function() return 3 end }
    trainerSetup({ { status = "available", cost = 10 } }, 100)
    _G.C_Trainer = nil
    T.falsy(DaylightUITrainAllButton and DaylightUITrainAllButton:IsShown())
end)

T.test("qol: train all shows after a /reload at an open trainer", function()
    stub.Load({ qol = true, before = function()
        stub.loadedAddOns.Blizzard_TrainerUI = true
        _G.GetNumTrainerServices = function() return 1 end
        _G.GetTrainerServiceInfo = function() return "x", "available" end
        _G.GetTrainerServiceCost = function() return 10 end
        _G.GetMoney = function() return 100 end
        local unitExists = _G.UnitExists
        _G.UnitExists = function(u) return u == "npc" or unitExists(u) end
        _G.ClassTrainerFrame = CreateFrame("Frame", "ClassTrainerFrame", UIParent)
        ClassTrainerFrame:Show()
    end })
    T.truthy(DaylightUITrainAllButton and DaylightUITrainAllButton:IsShown())
end)

T.test("qol: train all stops when the window closes", function()
    local bought = trainerSetup({
        { status = "available", cost = 10 }, { status = "available", cost = 10 },
    }, 100)
    DaylightUITrainAllButton:GetScript("OnClick")()
    ClassTrainerFrame:Hide()
    stub.RunTimers()
    T.eq(#bought, 1)
end)

-- Quests: auto accept and turn in.

local function questSetup(accept, turnIn)
    stub.Load({ qol = true })
    local db = DaylightUI:GetModule("QoL").db
    db.questAccept, db.questTurnIn = accept, turnIn
    local calls = {}
    local function rec(name) return function(...) calls[#calls + 1] = name .. ":" .. table.concat({ ... }, ",") end end
    _G.AcceptQuest, _G.CompleteQuest, _G.GetQuestReward = rec("accept"), rec("complete"), rec("reward")
    _G.IsQuestCompletable = function() return true end
    _G.GetNumQuestChoices = function() return 0 end
    _G.GetQuestMoneyToGet = function() return 0 end
    _G.IsShiftKeyDown = function() return false end
    stub.combat = false
    return calls
end

-- A blank offer isn't "no choices" until the log says so: GetQuestReward(0) on one
-- that has them fails and closes the talk. One that truly has none still goes.
T.test("qol: quests: a blank offer the log can't vouch for stays; one it says has none hands in", function()
    local c = questSetup(false, true)
    local loaded, logged = false, true
    _G.GetQuestID = function() return 122 end
    _G.C_QuestLog = _G.C_QuestLog or {}
    _G.C_QuestLog.GetLogIndexForQuestID = function() return logged and 1 or nil end
    _G.HaveQuestData = function() return loaded end
    _G.GetNumQuestLogChoices = function() return 0 end
    stub.FireEvent("QUEST_COMPLETE")
    T.eq(table.concat(c, " "), "", "not loaded: left for the player")
    loaded = true
    stub.FireEvent("QUEST_COMPLETE")
    T.eq(table.concat(c, " "), "reward:0", "the log says none")
    logged = false
    stub.FireEvent("QUEST_COMPLETE")
    T.eq(table.concat(c, " "), "reward:0 reward:0", "not in the log: as before")
end)

T.test("qol: quests are accepted and completed", function()
    local c = questSetup(true, true)
    stub.FireEvent("QUEST_DETAIL")
    stub.FireEvent("QUEST_PROGRESS")
    stub.FireEvent("QUEST_COMPLETE")
    T.eq(table.concat(c, " "), "accept: complete: reward:0")
end)

T.test("qol: quest options are off by default", function()
    stub.Load({ qol = true })
    local db = DaylightUI:GetModule("QoL").db
    T.eq(db.questAccept, false)
    T.eq(db.questTurnIn, false)
end)

T.test("qol: Shift pauses quests", function()
    local c = questSetup(true, true)
    _G.IsShiftKeyDown = function() return true end
    stub.FireEvent("QUEST_DETAIL")
    stub.FireEvent("QUEST_COMPLETE")
    T.eq(#c, 0)
end)

T.test("qol: a reward choice is left for the player", function()
    local c = questSetup(true, true)
    _G.GetNumQuestChoices = function() return 3 end
    stub.FireEvent("QUEST_COMPLETE")
    T.eq(#c, 0)
end)

T.test("qol: quests that cost money are skipped", function()
    local c = questSetup(true, true)
    _G.GetQuestMoneyToGet = function() return 50 end
    stub.FireEvent("QUEST_PROGRESS")
    stub.FireEvent("QUEST_COMPLETE")
    T.eq(#c, 0)
end)

T.test("qol: combat pauses quests", function()
    local c = questSetup(true, true)
    stub.combat = true
    stub.FireEvent("QUEST_DETAIL")
    T.eq(#c, 0)
    stub.combat = false
end)

T.test("qol: gossip picks a finished quest first, then an available one", function()
    questSetup(true, true)
    local picked = {}
    _G.C_GossipInfo = {
        GetActiveQuests = function() return { { questID = 1, isComplete = false }, { questID = 2, isComplete = true } } end,
        GetAvailableQuests = function() return { { questID = 3 } } end,
        SelectActiveQuest = function(id) picked[#picked + 1] = "a" .. id end,
        SelectAvailableQuest = function(id) picked[#picked + 1] = "v" .. id end,
    }
    stub.FireEvent("GOSSIP_SHOW")
    T.eq(table.concat(picked, ","), "a2")
    picked = {}
    _G.C_GossipInfo.GetActiveQuests = function() return {} end
    stub.FireEvent("GOSSIP_SHOW")
    T.eq(table.concat(picked, ","), "v3")
    _G.C_GossipInfo = nil
end)

T.test("qol: greeting picks a finished quest first", function()
    questSetup(true, true)
    local picked = {}
    _G.GetNumActiveQuests = function() return 2 end
    _G.GetActiveTitle = function(i) return "q" .. i, i == 2 end
    _G.SelectActiveQuest = function(i) picked[#picked + 1] = "a" .. i end
    _G.GetNumAvailableQuests = function() return 1 end
    _G.SelectAvailableQuest = function(i) picked[#picked + 1] = "v" .. i end
    stub.FireEvent("QUEST_GREETING")
    T.eq(table.concat(picked, ","), "a2")
end)

-- Skip cinematics.

local function cineSetup(setting, shift)
    local calls = {}
    _G.IsShiftKeyDown = function() return shift end
    _G.CinematicFrame_CancelCinematic = function() calls[#calls + 1] = "cine" end
    _G.MovieFrame = { StopMovie = function() calls[#calls + 1] = "movie" end }
    stub.Load({ qol = true })
    DaylightUI:GetModule("QoL").db.skipCinematics = setting
    return calls
end

T.test("qol: cinematics and movies are skipped when on", function()
    local calls = cineSetup(true, false)
    stub.FireEvent("CINEMATIC_START")
    stub.FireEvent("PLAY_MOVIE")
    T.eq(table.concat(calls, ","), "cine,movie")
end)

T.test("qol: cinematics play when off or when Shift is held", function()
    local calls = cineSetup(false, false)
    stub.FireEvent("CINEMATIC_START")
    T.eq(#calls, 0)
    calls = cineSetup(true, true)
    stub.FireEvent("CINEMATIC_START")
    stub.FireEvent("PLAY_MOVIE")
    T.eq(#calls, 0)
    _G.IsShiftKeyDown, _G.CinematicFrame_CancelCinematic, _G.MovieFrame = nil, nil, nil
end)

-- Hide tutorial tips.

local function tutSetup(setting)
    local cvars, hidden = {}, 0
    _G.SetCVar = function(k, v) cvars[#cvars + 1] = k .. "=" .. v end
    _G.TutorialFrame = { Hide = function() hidden = hidden + 1 end }
    stub.Load({ qol = true })
    local m = DaylightUI:GetModule("QoL")
    m.db.hideTutorials = setting
    return m, cvars, function() return hidden end
end

T.test("qol: tutorials are switched off when the setting is turned on", function()
    local m, cvars, hidden = tutSetup(false)
    m.db.hideTutorials = true
    DaylightUI:GetModule("QoL"):OnSettingChanged()
    T.eq(table.concat(cvars, ","), "showTutorials=0")
    T.eq(hidden(), 1)
    m.db.hideTutorials = false
    DaylightUI:GetModule("QoL"):OnSettingChanged()
    T.eq(table.concat(cvars, ","), "showTutorials=0,showTutorials=1")
end)

T.test("qol: turning tutorials back on gives the player's own setting back", function()
    local m, cvars = tutSetup(false)
    _G.GetCVar = function(k) if k == "showTutorials" then return "0" end end
    m.db.hideTutorials = true
    m:OnSettingChanged()
    m.db.hideTutorials = false
    m:OnSettingChanged()
    T.eq(table.concat(cvars, ","), "showTutorials=0,showTutorials=0", "they had tips off already")
    T.eq(DaylightUI.DB.Root().qolCVars.showTutorials, nil, "forgotten once handed back")
    _G.SetCVar, _G.GetCVar, _G.TutorialFrame = nil, nil, nil
end)

T.test("qol: tutorial setting is left alone when unchanged", function()
    local m, cvars = tutSetup(false)
    DaylightUI:GetModule("QoL"):OnSettingChanged()
    DaylightUI:GetModule("QoL"):OnSettingChanged()
    T.eq(#cvars, 0)
    _G.SetCVar, _G.TutorialFrame = nil, nil
end)

-- Max camera distance. The fake client clamps the CVar at `limit`, as the
-- real one does; its normal max is 2.0 and the player's own value 1.5.

local function camSetup(limit, zoom)
    local cvars = { cameraDistanceMaxZoomFactor = "1.5" }
    stub.Load({ qol = true, before = function()
        _G.GetCVar = function(k) return cvars[k] end
        _G.SetCVar = function(k, v)
            if k == "cameraDistanceMaxZoomFactor" then v = tostring(math.min(limit, tonumber(v))) end
            cvars[k] = v
        end
        _G.GetCVarDefault = function() return "2" end
        DaylightUIDB = { modules = { QoL = { cameraZoom = zoom } } }
    end })
    return DaylightUI:GetModule("QoL"), cvars
end

local function camDone() _G.GetCVar, _G.SetCVar, _G.GetCVarDefault = nil, nil, nil end

T.test("qol: camera slider's top end is the client's limit, and 100% leaves the game setting alone", function()
    local _, cvars = camSetup(3.4)
    T.eq(stub.qol.CAMERA_SLIDER.max, 1.7, "3.4 of a normal 2.0 is 170%")
    T.eq(cvars.cameraDistanceMaxZoomFactor, "1.5", "the player's own value is put back")
    camDone()
end)

T.test("qol: camera distance applies as a share of the game's normal max", function()
    local m, cvars = camSetup(2.6)
    m.db.cameraZoom = 1.25
    m:OnSettingChanged()
    T.eq(cvars.cameraDistanceMaxZoomFactor, "2.5")
    m.db.cameraZoom = 1.7
    m:OnSettingChanged()
    T.eq(cvars.cameraDistanceMaxZoomFactor, "2.6", "never past the client's limit")
    m.db.cameraZoom = 1
    m:OnSettingChanged()
    T.eq(cvars.cameraDistanceMaxZoomFactor, "2", "back to 100%: the game's normal max")
    camDone()
end)

T.test("qol: camera distance applies on login when changed", function()
    local _, cvars = camSetup(3.4, 1.5)
    T.eq(cvars.cameraDistanceMaxZoomFactor, "3")
    camDone()
end)

local function gossipSetup(setting, options, quests)
    stub.Load({ qol = true })
    local db = DaylightUI:GetModule("QoL").db
    db.skipGossip, db.questAccept, db.questTurnIn = setting, false, false
    local picked = {}
    _G.IsShiftKeyDown = function() return false end
    _G.C_GossipInfo = {
        GetActiveQuests = function() return {} end,
        GetAvailableQuests = function() return quests or {} end,
        GetOptions = function() return options end,
        SelectOptionByIndex = function(i) picked[#picked + 1] = i end,
    }
    return picked
end

local VENDOR = { name = "Let me browse your goods.", icon = 132060, status = 0, orderIndex = 0, selectOptionWhenOnlyOption = false }

T.test("qol: a lone vendor button is pressed once per talk", function()
    local picked = gossipSetup(true, { VENDOR })
    stub.FireEvent("GOSSIP_SHOW")
    T.eq(table.concat(picked, ","), "0")
    stub.FireEvent("GOSSIP_SHOW")
    T.eq(#picked, 1, "not pressed again before the dialogue closes")
    stub.FireEvent("GOSSIP_CLOSED")
    stub.FireEvent("GOSSIP_SHOW")
    T.eq(#picked, 2, "next talk")
    _G.C_GossipInfo, _G.IsShiftKeyDown = nil, nil
end)

T.test("qol: dialogue is left alone when off, with Shift, in combat or with quests", function()
    local picked = gossipSetup(false, { VENDOR })
    stub.FireEvent("GOSSIP_SHOW")
    T.eq(#picked, 0, "off")
    picked = gossipSetup(true, { VENDOR })
    _G.IsShiftKeyDown = function() return true end
    stub.FireEvent("GOSSIP_SHOW")
    T.eq(#picked, 0, "shift")
    picked = gossipSetup(true, { VENDOR })
    stub.combat = true
    stub.FireEvent("GOSSIP_SHOW")
    stub.combat = false
    T.eq(#picked, 0, "combat")
    picked = gossipSetup(true, { VENDOR }, { { questID = 5 } })
    stub.FireEvent("GOSSIP_SHOW")
    T.eq(#picked, 0, "quests")
    _G.C_GossipInfo, _G.IsShiftKeyDown = nil, nil
end)

T.test("qol: two buttons, chat buttons and locked buttons are not pressed", function()
    local taxi = { name = "Show me where I can fly.", icon = 132057, status = 0, orderIndex = 1 }
    local picked = gossipSetup(true, { VENDOR, taxi })
    stub.FireEvent("GOSSIP_SHOW")
    T.eq(#picked, 0, "two buttons")
    picked = gossipSetup(true, { { name = "Tell me more.", icon = 132053, status = 0, orderIndex = 0 } })
    stub.FireEvent("GOSSIP_SHOW")
    T.eq(#picked, 0, "chat")
    picked = gossipSetup(true, { { name = "Locked", icon = 132060, status = 2, orderIndex = 0 } })
    stub.FireEvent("GOSSIP_SHOW")
    T.eq(#picked, 0, "locked")
    picked = gossipSetup(true, { { name = "Server picks", icon = 132060, status = 0, orderIndex = 0, selectOptionWhenOnlyOption = true } })
    stub.FireEvent("GOSSIP_SHOW")
    T.eq(#picked, 0, "the game presses it itself")
    _G.C_GossipInfo, _G.IsShiftKeyDown = nil, nil
end)

-- Loot sparkles: the outline mode goes off so lootable quest objects sparkle.

local function sparkleSetup(setting)
    local cvars, log = {}, {}
    _G.GetCVar = function(k) return cvars[k] end
    _G.SetCVar = function(k, v) cvars[k] = v; log[#log + 1] = k .. "=" .. v end
    _G.GetCVarDefault = function(k) return ({ graphicsOutlineMode = "2", OutlineEngineMode = "2" })[k] or "0" end
    stub.Load({ qol = true })
    local m = DaylightUI:GetModule("QoL")
    m.db.lootSparkles = setting
    return m, cvars, log
end

local function sparklesDone()
    _G.GetCVar, _G.SetCVar, _G.GetCVarDefault = nil, nil, nil
end

T.test("qol: loot sparkles set the outline settings when turned on, and the game's back when off", function()
    local m, cvars, log = sparkleSetup(false)
    m.db.lootSparkles = true
    m:OnSettingChanged()
    T.eq(cvars.outlineModeShowLootEffectWhenDisabled, "1")
    T.eq(cvars.graphicsOutlineMode, "0")
    T.eq(cvars.OutlineEngineMode, "0")
    T.eq(cvars.raidGraphicsOutlineMode, "0")
    T.eq(cvars.RAIDOutlineEngineMode, "0")
    m.db.lootSparkles = false
    m:OnSettingChanged()
    T.eq(cvars.outlineModeShowLootEffectWhenDisabled, "0")
    T.eq(cvars.graphicsOutlineMode, "2")
    T.eq(cvars.OutlineEngineMode, "2")
    sparklesDone()
end)

T.test("qol: loot sparkles off gives back what the player had, not the defaults", function()
    local m, cvars = sparkleSetup(false)
    cvars.graphicsOutlineMode, cvars.OutlineEngineMode = "1", "3"
    m.db.lootSparkles = true
    m:OnSettingChanged()
    T.eq(cvars.graphicsOutlineMode, "0")
    cvars.graphicsOutlineMode = "2"   -- a graphics preset; ours goes on again
    stub.FireEvent("CVAR_UPDATE", "graphicsOutlineMode", "2")
    stub.RunTimers()
    m.db.lootSparkles = false
    m:OnSettingChanged()
    T.eq(cvars.graphicsOutlineMode, "1")
    T.eq(cvars.OutlineEngineMode, "3")
    T.eq(cvars.RAIDOutlineEngineMode, "0", "nothing kept: the game's default")
    sparklesDone()
end)

T.test("qol: loot sparkles leave the game's settings alone while off", function()
    local m, _, log = sparkleSetup(false)
    m:OnSettingChanged()
    stub.FireEvent("CVAR_UPDATE", "graphicsOutlineMode", "2")
    stub.RunTimers()
    T.eq(#log, 0)
    sparklesDone()
end)

T.test("qol: loot sparkles come back after a graphics preset turns the outline on", function()
    local m, cvars = sparkleSetup(false)
    m.db.lootSparkles = true
    m:OnSettingChanged()
    cvars.graphicsOutlineMode = "2"
    stub.FireEvent("CVAR_UPDATE", "graphicsOutlineMode", "2")
    stub.RunTimers()
    T.eq(cvars.graphicsOutlineMode, "0")
    sparklesDone()
end)

T.test("qol: loot sparkles wait for combat to end", function()
    local m, cvars = sparkleSetup(false)
    m.db.lootSparkles = true
    m:OnSettingChanged()
    stub.EnterCombat()
    cvars.graphicsOutlineMode = "2"
    stub.FireEvent("CVAR_UPDATE", "graphicsOutlineMode", "2")
    stub.RunTimers()
    T.eq(cvars.graphicsOutlineMode, "2", "not in combat")
    stub.LeaveCombat()
    stub.RunTimers()
    T.eq(cvars.graphicsOutlineMode, "0")
    sparklesDone()
end)

-- Quiet error messages. The fake error frame follows the game's own rule from
-- UIErrorsFrame.lua: a message type listed in BLACK_LISTED_MESSAGE_TYPES is
-- skipped. Forever's list only holds "another action in progress".

local ERR = { SPELL_FAILED_ANOTHER_IN_PROGRESS = 1, OUT_OF_RAGE = 2, SPELL_COOLDOWN = 3,
    SPELL_OUT_OF_RANGE = 4, GENERIC_NO_TARGET = 5, SPELL_FAILED_MOVING = 6,
    SPELL_FAILED_UNIT_NOT_INFRONT = 7, INV_FULL = 8, SPELL_FAILED_INTERRUPTED = 9,
    LOOT_GONE = 10, QUEST_ACCEPTED_S = 11, SPELL_FAILED_LINE_OF_SIGHT = 12, OUT_OF_MANA = 13 }

-- played collects every sound file the addon played, such as the soft tick that
-- replaces a quieted error's voice line. kits collects the game's sound kits.
-- fire() hands the event to both error frames and says whether the line showed.
local played, kits = {}, {}
local KIT = 777

local function errorsSetup(over)
    local shown, drawn = {}, { n = 0 }
    for k in pairs(played) do played[k] = nil end
    for k in pairs(kits) do kits[k] = nil end
    stub.Load({ qol = true, before = function()
        for name, id in pairs(ERR) do _G["LE_GAME_ERR_" .. name] = id end
        _G.BLACK_LISTED_MESSAGE_TYPES = { [ERR.SPELL_FAILED_ANOTHER_IN_PROGRESS] = true }
        _G.UIErrorsFrame = {
            AddMessage = function(_, text) shown[#shown + 1] = text end,
            OnEvent = function(self, event, messageType, message)
                if event == "UI_ERROR_MESSAGE" and not BLACK_LISTED_MESSAGE_TYPES[messageType] then
                    self:AddMessage(message)
                end
            end,
        }
        played.was = _G.PlaySoundFile
        _G.PlaySoundFile = function(file) played[#played + 1] = file end
        played.wasKit, played.wasInfo = _G.PlaySound, _G.GetGameMessageInfo
        _G.PlaySound = function(kit) kits[#kits + 1] = kit end
        _G.GetGameMessageInfo = function() return "x", KIT end
        if over then DaylightUIDB = { modules = { QoL = over } } end
    end })
    local ET = stub.qol.ErrorText
    local show = ET.Show
    ET.Show = function(...) drawn.n = drawn.n + 1; return show(...) end
    local function fire(name, event)
        local before, was = #shown, drawn.n
        UIErrorsFrame:OnEvent(event or "UI_ERROR_MESSAGE", ERR[name], name)
        stub.FireEvent(event or "UI_ERROR_MESSAGE", ERR[name], name)
        return #shown > before or drawn.n > was, #shown > before, drawn.n > was
    end
    return DaylightUI:GetModule("QoL"), fire, drawn
end

local function ticks()
    local n = 0
    for _, file in ipairs(played) do if file == DaylightUI.Sound.FILES.nope then n = n + 1 end end
    return n
end

local function errorsDone()
    for name in pairs(ERR) do _G["LE_GAME_ERR_" .. name] = nil end
    _G.BLACK_LISTED_MESSAGE_TYPES, _G.UIErrorsFrame = nil, nil
    if played.was then _G.PlaySoundFile, played.was = played.was, nil end
    _G.PlaySound, _G.GetGameMessageInfo, played.wasKit, played.wasInfo = played.wasKit, played.wasInfo, nil, nil
end

local SPAM = { "OUT_OF_RAGE", "OUT_OF_MANA", "SPELL_COOLDOWN", "SPELL_OUT_OF_RANGE", "GENERIC_NO_TARGET",
    "SPELL_FAILED_MOVING", "SPELL_FAILED_UNIT_NOT_INFRONT" }
local USEFUL = { "INV_FULL", "SPELL_FAILED_INTERRUPTED", "LOOT_GONE", "QUEST_ACCEPTED_S", "SPELL_FAILED_LINE_OF_SIGHT" }

T.test("qol: quiet errors is on out of the box: the spam is hidden, the useful ones show", function()
    local m, fire = errorsSetup()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(m.db.quietErrors, true)
    for _, name in ipairs(SPAM) do T.falsy(fire(name), name .. " hidden") end
    for _, name in ipairs(USEFUL) do T.truthy(fire(name), name .. " shown") end
    T.falsy(fire("SPELL_FAILED_ANOTHER_IN_PROGRESS"), "the game's own stays hidden")
    errorsDone()
end)

T.test("qol: turning quiet errors off shows everything again, and back on hides it", function()
    local m, fire = errorsSetup({ errorText = false })
    m.db.quietErrors = false
    m:OnSettingChanged()
    for _, name in ipairs(SPAM) do T.truthy(fire(name), name .. " shown") end
    T.falsy(fire("SPELL_FAILED_ANOTHER_IN_PROGRESS"), "the game's own entry is left alone")
    T.eq(BLACK_LISTED_MESSAGE_TYPES[ERR.OUT_OF_RAGE], nil, "removed, not set to false")
    m.db.quietErrors = true
    m:OnSettingChanged()
    for _, name in ipairs(SPAM) do T.falsy(fire(name), name .. " hidden again") end
    errorsDone()
end)

T.test("qol: quiet errors off from login leaves the game's list untouched", function()
    local m, fire = errorsSetup({ quietErrors = false, errorText = false })
    m:OnSettingChanged()
    local n = 0
    for _ in pairs(BLACK_LISTED_MESSAGE_TYPES) do n = n + 1 end
    T.eq(n, 1)
    T.truthy(fire("OUT_OF_RAGE"))
    errorsDone()
end)

T.test("qol: quiet errors waits for the game's error frame if it loads late", function()
    stub.Load({ qol = true, before = function()
        for name, id in pairs(ERR) do _G["LE_GAME_ERR_" .. name] = id end
        DaylightUIDB = { modules = { QoL = { errorText = false } } }
    end })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.BLACK_LISTED_MESSAGE_TYPES = {}
    stub.FireEvent("ADDON_LOADED", "Blizzard_UIErrorsFrame")
    T.eq(BLACK_LISTED_MESSAGE_TYPES[ERR.OUT_OF_RAGE], true)
    T.eq(BLACK_LISTED_MESSAGE_TYPES[ERR.INV_FULL], nil)
    errorsDone()
end)

T.test("qol: a quieted error plays the soft tick in place of its voice line, out of the box", function()
    local m, fire = errorsSetup()
    T.eq(m.db.errorSound, true)
    fire("SPELL_COOLDOWN")
    T.eq(ticks(), 1)
    T.eq(#played, 1, "nothing else of ours")
    errorsDone()
end)

T.test("qol: mashing a key ticks calmly: at most once per Errors.GAP", function()
    local m, fire = errorsSetup()
    local QoL = stub.qol
    for _ = 1, 5 do fire("SPELL_COOLDOWN") end
    fire("OUT_OF_RAGE")
    T.eq(ticks(), 1, "one tick for a burst, whatever the error")
    stub.Advance(QoL.Errors.GAP + 0.01)
    fire("OUT_OF_RAGE")
    T.eq(ticks(), 2)
    errorsDone()
end)

T.test("qol: errors that still show, and the game's own quiet one, play no tick", function()
    local m, fire = errorsSetup()
    for _, name in ipairs(USEFUL) do
        fire(name)
        stub.Advance(1)
    end
    fire("SPELL_FAILED_ANOTHER_IN_PROGRESS")
    T.eq(ticks(), 0)
    errorsDone()
end)

T.test("qol: no tick with the switch off, quiet errors off, or our UI sounds off", function()
    local m, fire = errorsSetup()
    m.db.errorSound = false
    m:OnSettingChanged()
    fire("SPELL_COOLDOWN")
    T.eq(ticks(), 0, "switch off")
    m.db.errorSound = true
    m.db.quietErrors = false
    m:OnSettingChanged()
    stub.Advance(1)
    fire("SPELL_COOLDOWN")
    T.eq(ticks(), 0, "quiet errors off: the game's voice line plays instead")
    m.db.quietErrors = true
    m:OnSettingChanged()
    DaylightUI:Set("general", "sounds", false)
    stub.Advance(1)
    fire("SPELL_COOLDOWN")
    T.eq(ticks(), 0, "General > Soft UI sounds off")
    errorsDone()
end)

T.test("qol: no tick while the game holds its messages back (it skips its voice line then too)", function()
    local m, fire = errorsSetup()
    UIErrorsFrame.GetMessagesSuppressed = function() return true end
    fire("SPELL_COOLDOWN")
    T.eq(ticks(), 0)
    UIErrorsFrame.GetMessagesSuppressed = function() return false end
    fire("SPELL_COOLDOWN")
    T.eq(ticks(), 1)
    errorsDone()
end)

T.test("qol: a secret error type is never used as a key (no tick, no error)", function()
    local m = errorsSetup()
    stub.FireEvent("UI_ERROR_MESSAGE", stub.Secret(ERR.SPELL_COOLDOWN), stub.Secret("x"))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(ticks(), 0)
    errorsDone()
end)

T.test("qol: the soft-sound switch dims while quiet errors is off", function()
    errorsSetup()
    errorsDone()
    local item
    for _, g in ipairs(stub.qol.OPTIONS.pages[1].groups) do
        for _, it in ipairs(g.items) do if it.key == "errorSound" then item = it end end
    end
    T.truthy(item, "the row")
    T.eq(item.disabled(function(k) return k == "quietErrors" and false end), true)
    T.falsy(item.disabled(function(k) return k == "quietErrors" end))
end)

T.test("qol: a PvP quest is left to the player (the game asks first)", function()
    local c = questSetup(true, true)
    _G.QuestFlagsPVP = function() return true end
    stub.FireEvent("QUEST_DETAIL")
    _G.QuestFlagsPVP = nil
    T.eq(#c, 0)
end)

T.test("qol: a quest that accepted itself is acknowledged, not accepted again", function()
    local c = questSetup(true, true)
    _G.QuestGetAutoAccept = function() return true end
    _G.AcknowledgeAutoAcceptQuest = function() c[#c + 1] = "ack:" end
    stub.FireEvent("QUEST_DETAIL")
    _G.QuestGetAutoAccept, _G.AcknowledgeAutoAcceptQuest = nil, nil
    T.eq(table.concat(c, " "), "ack:")
end)

-- Error text in Daylight UI style: the lines the game would still show are
-- drawn by us (ErrorText.lua) in its place, with the game's sound.

local function errorRow(text)
    for _, r in ipairs(stub.qol.ErrorText.rows) do
        if r:IsShown() and not r.leaving and r.text:GetText() == text then return r end
    end
end

local function rowsShown()
    local n = 0
    for _, r in ipairs(stub.qol.ErrorText.rows) do if r:IsShown() and not r.leaving then n = n + 1 end end
    return n
end

local function inkIs(fs, ink)
    local r, g, b = fs:GetTextColor()
    return math.abs(r - ink[1]) < 0.01 and math.abs(g - ink[2]) < 0.01 and math.abs(b - ink[3]) < 0.01
end

T.test("qol: error text is on out of the box: the useful errors are ours, in the soft red", function()
    local m, fire = errorsSetup()
    T.eq(m.db.errorText, true)
    for _, name in ipairs(USEFUL) do
        local _, game, ours = fire(name)
        T.falsy(game, name .. " not in the game's frame")
        T.truthy(ours, name .. " drawn by us")
    end
    local r = errorRow("SPELL_FAILED_INTERRUPTED")
    T.truthy(r, "Interrupted shows")
    T.truthy(inkIs(r.text, DaylightUI.Style.INK.BAD), "INK.BAD")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    errorsDone()
end)

T.test("qol: error text leaves quieted errors and the game's own quiet one hidden", function()
    local _, fire = errorsSetup()
    for _, name in ipairs(SPAM) do T.falsy(fire(name), name .. " hidden") end
    T.falsy(fire("SPELL_FAILED_ANOTHER_IN_PROGRESS"), "the game's own stays hidden")
    T.eq(ticks(), 1, "the soft tick still plays")
    T.eq(#kits, 0, "no game sound for them")
    errorsDone()
end)

T.test("qol: with quiet errors off, the spam shows as our error text", function()
    local m, fire = errorsSetup()
    m.db.quietErrors = false
    m:OnSettingChanged()
    local _, game, ours = fire("OUT_OF_RAGE")
    T.falsy(game)
    T.truthy(ours)
    errorsDone()
end)

T.test("qol: error text off gives every line back to the game's frame", function()
    local m, fire = errorsSetup()
    fire("INV_FULL")
    m.db.errorText = false
    m:OnSettingChanged()
    local _, game, ours = fire("SPELL_FAILED_INTERRUPTED")
    T.truthy(game)
    T.falsy(ours)
    T.eq(BLACK_LISTED_MESSAGE_TYPES[ERR.INV_FULL], nil, "removed, not set to false")
    T.eq(BLACK_LISTED_MESSAGE_TYPES[ERR.OUT_OF_RAGE], true, "quiet errors keeps its own")
    T.eq(BLACK_LISTED_MESSAGE_TYPES[ERR.SPELL_FAILED_ANOTHER_IN_PROGRESS], true, "the game's own stays")
    T.eq(rowsShown(), 0, "our lines leave")
    errorsDone()
end)

T.test("qol: an info line is ours too, in soft white", function()
    local _, fire = errorsSetup()
    local _, game, ours = fire("QUEST_ACCEPTED_S", "UI_INFO_MESSAGE")
    T.falsy(game)
    T.truthy(ours)
    T.truthy(inkIs(errorRow("QUEST_ACCEPTED_S").text, DaylightUI.Style.INK.TEXT), "INK.TEXT")
    errorsDone()
end)

T.test("qol: a line we draw plays the game's own sound for it", function()
    local _, fire = errorsSetup()
    fire("INV_FULL")
    T.eq(kits[1], KIT)
    errorsDone()
end)

T.test("qol: the same error again stays one line, and a line leaves after a moment", function()
    local _, fire = errorsSetup()
    local ET = stub.qol.ErrorText
    fire("INV_FULL")
    stub.Advance(1)
    fire("INV_FULL")
    T.eq(rowsShown(), 1, "one line")
    stub.Advance(ET.HOLD + 1)
    stub.RunTimers()
    T.falsy(errorRow("INV_FULL"), "gone")
    errorsDone()
end)

T.test("qol: the same error again eases to a glow and back, it never jumps or changes size", function()
    local _, fire = errorsSetup()
    local INK, ET = DaylightUI.Style.INK, stub.qol.ErrorText
    fire("INV_FULL")
    local r = errorRow("INV_FULL")
    stub.Advance(1)
    fire("INV_FULL")
    T.falsy(r.text.__duiBump, "no size change: scaled text jumps")
    T.truthy(inkIs(r.text, INK.BAD), "starts where it was")
    local d = DaylightUI.Motion.Driver()
    stub.RunOnUpdate(d, DaylightUI.Motion.FAST)
    local _, g = r.text:GetTextColor()
    T.truthy(g > INK.BAD[2] + 0.1, "lit up")
    fire("INV_FULL")
    local _, again = r.text:GetTextColor()
    T.truthy(again >= g - 0.01, "pressed again while lit: carries on from there, no dip")
    stub.RunOnUpdate(d, DaylightUI.Motion.FAST)
    stub.RunOnUpdate(d, DaylightUI.Motion.NORMAL)
    T.truthy(inkIs(r.text, INK.BAD), "back to the soft red")
    errorsDone()
end)

T.test("qol: more errors than rows: the oldest line makes room", function()
    local _, fire = errorsSetup()
    local ET = stub.qol.ErrorText
    for _, name in ipairs({ "INV_FULL", "LOOT_GONE", "SPELL_FAILED_LINE_OF_SIGHT", "SPELL_FAILED_INTERRUPTED" }) do
        fire(name)
        stub.Advance(0.1)
    end
    T.falsy(errorRow("INV_FULL"), "the oldest went")
    T.truthy(errorRow("SPELL_FAILED_INTERRUPTED"), "the newest shows")
    T.eq(#ET.rows, ET.ROWS)
    errorsDone()
end)

T.test("qol: a secret error type is never used as a key, a secret text still draws", function()
    errorsSetup()
    stub.FireEvent("UI_ERROR_MESSAGE", stub.Secret(ERR.INV_FULL), stub.Secret("x"))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    stub.qol.ErrorText.Show("error", stub.Secret("Interrupted"))
    stub.qol.ErrorText.Show("error", stub.Secret("Interrupted"))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(rowsShown(), 2, "secret lines are never compared")
    errorsDone()
end)

T.test("qol: nothing drawn while the game holds its messages back", function()
    local _, fire = errorsSetup()
    UIErrorsFrame.GetMessagesSuppressed = function() return true end
    T.falsy(fire("INV_FULL"))
    errorsDone()
end)

T.test("qol: our own red lines go through the error text when it's on", function()
    local m, _, drawn = errorsSetup()
    DaylightUI.ShowError("Can't track more")
    T.eq(drawn.n, 1)
    T.truthy(errorRow("Can't track more"))
    m.db.errorText = false
    m:OnSettingChanged()
    local sent
    UIErrorsFrame.AddExternalErrorMessage = function(_, text) sent = text end
    DaylightUI.ShowError("Can't track more")
    T.eq(sent, "Can't track more", "the game's frame when it's off")
    errorsDone()
end)

T.test("qol: unlock mode shows sample lines and they leave after", function()
    errorsSetup()
    DaylightUI.Movers.unlocked = true
    DaylightUI.Fire("UnlockChanged")
    T.truthy(rowsShown() > 0, "samples show")
    DaylightUI.Movers.unlocked = false
    DaylightUI.Fire("UnlockChanged")
    T.eq(rowsShown(), 0)
    errorsDone()
end)

-- Right-click to fish (Fishing.lua): a pole in hand, a quick right-click on
-- the world, and BUTTON2 is ours for that press's release.
local function fishSetup(setting)
    _G.WorldFrame = {}
    _G.GetMouseFoci = function() return { WorldFrame } end
    _G.GetInventoryItemID = function(_, slot) return slot == 16 and 6256 or nil end
    C_Item.GetItemInfoInstant = function(id) return id, "", "", "", 0, 2, id == 6256 and 20 or 7 end
    _G.GetUnitSpeed = function() return 0 end
    stub.Load({ qol = true })
    -- Forever's profession book lists Bait and Tackle first (1278067, opens the
    -- trade skill window), then the Fishing cast (7620).
    _G.GetProfessions = function() return nil, nil, nil, 3 end
    _G.GetProfessionInfo = function(i) if i == 3 then return "Fishing", 1, 46, 75, 3, 40, 356 end end
    _G.CanTradeSkillShowCraftingUI = nil   -- only in C_TradeSkillUI on this client
    _G.C_TradeSkillUI = _G.C_TradeSkillUI or {}
    C_TradeSkillUI.CanTradeSkillShowCraftingUI = function(id) return id == 1278067 end
    local book = { [41] = { spellID = 1278067 }, [42] = { spellID = 7777, isPassive = true }, [43] = { spellID = 7620 } }
    C_SpellBook.GetSpellBookItemInfo = function(slot) return book[slot] end
    local m = DaylightUI:GetModule("QoL")
    m.db.fishClick = setting
    return m
end

local function bound() return stub.overrides.BUTTON2 end
local function press() stub.FireEvent("GLOBAL_MOUSE_DOWN", "RightButton") end

T.test("qol: fishing: off by default", function()
    fishSetup(nil)
    T.eq(DaylightUI:GetModule("QoL").db.fishClick == true, false)
    press()
    T.eq(bound(), nil)
end)

T.test("qol: fishing: a right-click on the world with a pole binds the spell for its release", function()
    fishSetup(true)
    press()
    local b = _G.DaylightUIFishCast
    T.truthy(bound(), "BUTTON2 taken")
    T.eq(bound().click, "DaylightUIFishCast")
    T.eq(b:GetAttribute("type"), "spell")
    T.eq(b:GetAttribute("spell"), 7620, "the cast, not the slot that opens the fishing window")
    T.eq(b:GetAttribute("useOnKeyDown"), false, "the game's secure code must act on the release")
    b:GetScript("PostClick")(b)
    T.eq(bound(), nil, "gone after the click")
end)

T.test("qol: fishing: a held button is a camera turn: the binding goes before its release", function()
    fishSetup(true)
    press()
    stub.RunTimers()
    T.eq(bound(), nil)
end)

T.test("qol: fishing: the left button, windows, the wrong weapon and a fight leave the press alone", function()
    fishSetup(true)
    stub.FireEvent("GLOBAL_MOUSE_DOWN", "LeftButton")
    T.eq(bound(), nil, "left button")
    local foci = _G.GetMouseFoci
    _G.GetMouseFoci = function() return { CreateFrame("Frame") } end
    press()
    T.eq(bound(), nil, "over a window")
    _G.GetMouseFoci = foci
    local pole = _G.GetInventoryItemID
    _G.GetInventoryItemID = function() return 1234 end
    press()
    T.eq(bound(), nil, "a sword in hand")
    _G.GetInventoryItemID = pole
    stub.combat = true
    press()
    stub.combat = false
    T.eq(bound(), nil, "in a fight")
end)

T.test("qol: fishing: the line in the water: a click never recasts", function()
    fishSetup(true)
    local real = _G.UnitChannelInfo
    _G.UnitChannelInfo = function() return "Fishing" end
    press()
    _G.UnitChannelInfo = real
    T.eq(bound(), nil)
end)

T.test("qol: fishing: pointing at a unit or a thing with a tooltip leaves the click to the game", function()
    fishSetup(true)
    local alpha = 1
    _G.GameTooltip = { IsShown = function() return true end, GetAlpha = function() return alpha end }
    press()
    T.eq(bound(), nil, "a tooltip up")
    alpha = 0.4
    press()
    _G.GameTooltip = nil
    T.truthy(bound(), "a tooltip fading away has been left behind")
end)

T.test("qol: fishing: a fight starting takes the mouse back", function()
    fishSetup(true)
    press()
    stub.enteringCombat = true
    stub.combat = true
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    stub.enteringCombat = false
    stub.combat = false
    T.eq(bound(), nil)
end)

T.test("qol: fishing: switching it off gives the button back", function()
    local m = fishSetup(true)
    press()
    m.db.fishClick = false
    m:OnSettingChanged()
    T.eq(bound(), nil)
end)

T.test("qol: fishing: no cast in the book: the click stays the game's, never the fishing window", function()
    fishSetup(true)
    C_TradeSkillUI.CanTradeSkillShowCraftingUI = function() return true end
    press()
    T.eq(bound(), nil)
end)

-- Bait: a pole with none on, and bait in the bags: the click puts the best on;
-- bait on, or none in the bags: the click casts.
local function baitSetup(items)
    local m = fishSetup(true)
    local bag = items or { [1] = 6530, [2] = 6529, [3] = 9999, [4] = 6256, [5] = 6533, [6] = 4411 }
    local text = { [6529] = "Use: When applied to your fishing pole, increases Fishing by 25 for 10 min.",
        [6530] = "Use: When applied to your fishing pole, increases Fishing by 50 for 10 min.",
        [6533] = "Use: When applied to your fishing pole, increases Fishing by 100 for 5 min.",
        [6256] = "Equip: Increased Fishing +5.", [4411] = "Use: Teaches you Expert Fishing 300.",
        [9999] = "Use: Restores 100 health." }
    _G.C_Container = { GetContainerNumSlots = function(b) return b == 0 and 8 or 0 end,
        GetContainerItemInfo = function(b, s) if b == 0 and bag[s] then return { itemID = bag[s] } end end }
    _G.C_TooltipInfo = { GetBagItem = function(_, s) return { lines = { { leftText = bag[s] and text[bag[s]] } } } end }
    C_Item.GetItemSpell = function(id) if id ~= 6256 then return "Use", 1 end end
    C_Item.IsUsableItem = function(id) return id ~= 6533 end   -- this one's skill is too high yet
    local info = C_Item.GetItemInfoInstant
    C_Item.GetItemInfoInstant = function(id)
        if id == 4411 then return id, "", "", "", 0, 9, 9 end   -- a recipe book
        if id == 6256 then return info(id) end                 -- the pole
        return id, "", "", "", 0, 0, 8
    end
    C_Spell.GetSpellName = function() return "Fishing" end
    stub.weaponEnchants = nil
    return m
end

T.test("qol: fishing bait: no bait on: the click puts the best usable bait from the bags on the pole", function()
    baitSetup()
    press()
    local b = _G.DaylightUIFishCast
    T.eq(b:GetAttribute("type"), "item")
    T.eq(b:GetAttribute("item"), "0 1", "Nightcrawlers: 100 is too high a skill, 25 is less")
    T.eq(b:GetAttribute("target-slot"), 16)
end)

T.test("qol: fishing bait: bait on the pole: the click casts", function()
    baitSetup()
    stub.weaponEnchants = { { slot = 0 } }
    press()
    local b = _G.DaylightUIFishCast
    T.eq(b:GetAttribute("type"), "spell")
    T.eq(b:GetAttribute("spell"), 7620)
    T.eq(b:GetAttribute("target-slot"), nil)
    stub.weaponEnchants = nil
end)

T.test("qol: fishing bait: no bait in the bags: the click casts", function()
    baitSetup({ [1] = 9999, [2] = 4411 })
    press()
    T.eq(_G.DaylightUIFishCast:GetAttribute("type"), "spell")
end)

T.test("qol: fishing bait: bait the game does not show on the pole is never put on again and again", function()
    baitSetup()
    press()
    local b = _G.DaylightUIFishCast
    b:GetScript("PostClick")(b)
    press()
    T.eq(b:GetAttribute("type"), "spell", "the next click casts")
    b:GetScript("PostClick")(b)
end)

T.test("qol: fishing bait: a bait cast that failed may be tried again", function()
    baitSetup()
    press()
    local b = _G.DaylightUIFishCast
    b:GetScript("PostClick")(b)
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    press()
    T.eq(b:GetAttribute("type"), "item")
    b:GetScript("PostClick")(b)
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
end)

-- The fishing water. Timings below match the real client: the channel stops,
-- then LOOT_READY about 10 ms later on a catch, and no loot on a miss.
local SPELL = 7620

local function water(setting)
    local m = fishSetup(false)
    m.db.fishScene = setting
    stub.channel = nil
    _G.UnitChannelInfo = function()
        local c = stub.channel
        if c then return "Fishing", "", 0, c.from, c.to, true, false, SPELL end
    end
    local sounds = {}
    local play = DaylightUI.Sound.Play
    DaylightUI.Sound.Play = function(name) sounds[#sounds + 1] = name; return play(name) end
    return stub.qol.Fishing.Scene, sounds, m
end

local function frame() return _G.DaylightUIFishScene end

local function cast()
    local now = GetTime() * 1000
    stub.channel = { from = now, to = now + 30000 }
    stub.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", SPELL)
end

local function stop()
    stub.channel = nil
    stub.FireEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player", "guid", SPELL)
end

local function play(secs)
    local n = math.max(1, math.floor(secs * 30 + 0.5))
    for _ = 1, n do
        local f = frame()
        if f and f:IsShown() then stub.RunOnUpdate(f, secs / n) end
        stub.Advance(secs / n)
    end
end

local function dropsUp(f)
    local n = 0
    for _, d in ipairs(f.drops) do if d.tex:IsShown() then n = n + 1 end end
    return n
end

T.test("qol: fishing water: on by default, the line going in brings it up and hushes the bars", function()
    local Scene = water(true)
    T.eq(DaylightUI:GetModule("QoL").db.fishScene, true)
    T.isnil(frame(), "built only when first needed")
    cast()
    T.eq(frame():IsShown(), true)
    T.eq(Scene.state, "line")
    T.eq(DaylightUI.Fade.Hushed(), true)
end)

T.test("qol: fishing water: another channel, a fight or the switch off leaves it down", function()
    local Scene, _, m = water(true)
    stub.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 12345)
    T.eq(Scene.state, "idle", "not Fishing")
    stub.EnterCombat()
    cast()
    T.eq(Scene.state, "idle", "in a fight")
    stub.LeaveCombat()
    m.db.fishScene = false
    cast()
    T.eq(Scene.state, "idle", "switched off")
end)

T.test("qol: fishing water: a catch splashes, a line pulled in empty doesn't", function()
    local Scene, sounds = water(true)
    cast()
    play(1)
    stop()
    stub.FireEvent("LOOT_READY", true)
    T.eq(#sounds, 1)
    T.eq(sounds[1], "splash")
    T.eq(dropsUp(frame()) >= Scene.BURST, true, "drops fly")
    stub.FireEvent("LOOT_READY", true)   -- the client sends it twice
    T.eq(#sounds, 1, "one splash a catch")
    play(Scene.LINGER + 0.5)
    cast()
    play(1)
    stop()
    play(Scene.CATCH + 0.1)
    stub.FireEvent("LOOT_READY", true)
    T.eq(#sounds, 1, "loot long after isn't this line's")
end)

T.test("qol: fishing water: the next cast keeps the water, then it leaves by itself", function()
    local Scene = water(true)
    cast()
    play(2)
    stop()
    T.eq(Scene.state, "waiting")
    play(Scene.LINGER - 1)
    cast()
    T.eq(Scene.state, "line", "the same water")
    play(Scene.LINGER + 1)
    T.eq(Scene.state, "line", "the old line's timer is gone")
    stop()
    play(Scene.LINGER + 0.1)
    stub.RunTimers()
    T.eq(Scene.state, "idle")
    T.eq(DaylightUI.Fade.Hushed(), false, "the bars come back")
    play(Scene.GLOW_OUT + 0.2)
    T.eq(frame():IsShown(), false, "nothing runs once it's gone")
end)

T.test("qol: fishing water: moving, targeting and another spell wake it, Fishing itself doesn't, a fight snaps it", function()
    local Scene = water(true)
    cast()
    stub.FireEvent("UNIT_SPELLCAST_SENT", "player", "", "guid", SPELL)
    T.eq(Scene.state, "line", "casting again")
    stub.FireEvent("PLAYER_STARTED_MOVING")
    T.eq(Scene.state, "idle")
    cast()
    stub.FireEvent("UNIT_SPELLCAST_SENT", "player", "", "guid", 133)
    T.eq(Scene.state, "idle")
    cast()
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.eq(Scene.state, "idle")
    cast()
    stub.EnterCombat()
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    T.eq(Scene.state, "idle")
    T.eq(frame():IsShown(), false, "at once")
    stub.LeaveCombat()
end)

T.test("qol: fishing water: the tide runs out on the game's channel times, and rushes back", function()
    local Scene = water(true)
    cast()
    local full = frame().tide:GetWidth()
    play(15)
    T.near(frame().tide:GetWidth() / full, 0.5, 0.02)
    play(10)
    T.near(frame().tide:GetWidth() / full, 1 / 6, 0.02)
    stop()
    play(DaylightUI.Motion.SLOW * 1.1)
    T.near(frame().tide:GetWidth() / full, 1, 0.01)
    T.eq(Scene.state, "waiting")
end)

T.test("qol: fishing water: no motion: it still comes and goes, with the sound and no drops", function()
    local Scene, sounds = water(true)
    DaylightUI.Motion.On = function() return false end
    cast()
    play(0.1)
    stop()
    stub.FireEvent("LOOT_READY", true)
    T.eq(sounds[#sounds], "splash")
    T.eq(dropsUp(frame()), 0)
    stub.FireEvent("PLAYER_STARTED_MOVING")
    T.eq(frame():IsShown(), false)
    T.eq(Scene.state, "idle")
end)

T.test("qol: fishing water: the preview plays through and ends itself", function()
    local Scene, sounds = water(true)
    Scene.Preview()
    T.eq(Scene.state, "line")
    stub.Advance(Scene.PREVIEW_CATCH + 0.1)
    stub.RunTimers()
    T.eq(sounds[#sounds], "splash")
    T.eq(Scene.state, "idle", "and it leaves by itself")
end)

T.test("qol: fishing water: your cast bar steps aside while the line is in", function()
    local DUI, ns = stub.Load({ module = true, qol = true })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local h = ns.playerCastbar
    stub.units.player = stub.units.player or { name = "You" }
    stub.channel = { from = 0, to = 30000 }
    stub.units.player.channel = { name = "Fishing", duration = stub.Duration(30) }
    stub.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    T.eq(h:IsShown(), true, "shown before")
    DUI.Fire("CastElsewhere", true)
    T.eq(h:IsShown(), false, "the water has it")
    stub.FireEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
    T.eq(h:IsShown(), false, "and keeps it")
    DUI.Fire("CastElsewhere", false)
    T.eq(h:IsShown(), true, "back at once")
    stub.channel = nil
    stub.units.player.channel = nil
end)

-- The forge theme. Crafts report as casts with the trade skill flag. Within a
-- batch the game sends START, SUCCEEDED, STOP, and the last SUCCEEDED can come
-- after its STOP.
local HELM, BACON, POTION, BOMB, SHIRT = 2851, 2542, 2330, 3923, 2385

local function forge(setting)
    local Scene, sounds, m = water(true)
    m.db.forgeScene = setting
    m.db.brewScene = setting
    m.db.workshopScene = setting
    m.db.sewingScene = setting
    stub.casting = nil
    stub.left = 0
    _G.UnitCastingInfo = function()
        local c = stub.casting
        if c then return "Copper Helm", "", 0, c.from, c.to, c.craft ~= false, "id", false, c.spell end
    end
    C_TradeSkillUI.GetRemainingRecasts = function() return stub.left end
    C_TradeSkillUI.GetProfessionInfoByRecipeID = function(id)
        if id == POTION then return { professionID = 171 } end
        if id == BOMB then return { professionID = 202 } end
        if id == SHIRT then return { professionID = 197 } end
        return { professionID = (id == HELM or id == HELM + 1) and 164 or 185 }
    end
    return Scene, sounds, m
end

local function craft(id, secs, opts)
    local now = GetTime() * 1000
    stub.casting = { from = now, to = now + secs * 1000, spell = id, craft = opts and opts.craft }
    stub.FireEvent("UNIT_SPELLCAST_START", "player", "guid", id)
end

local function done(id)
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", id)
    stub.casting = nil
    stub.FireEvent("UNIT_SPELLCAST_STOP", "player", "guid", id)
end

T.test("qol: forge: smithing brings it up in the forge's look, other work doesn't", function()
    local Scene = forge(true)
    craft(BACON, 3)
    T.eq(Scene.state, "idle", "cooking has no scene yet")
    stub.casting = nil
    craft(HELM, 3, { craft = false })
    T.eq(Scene.state, "idle", "not a craft")
    stub.casting = nil
    craft(HELM, 3)
    T.eq(Scene.state, "line")
    T.eq(frame().bobber:GetTexture(), Scene.THEMES.forge.object, "the anvil, not the bobber")
    T.eq(frame().hammer:IsShown(), true)
    T.eq(DaylightUI.Fade.Hushed(), true)
end)

T.test("qol: forge: a fight, restrictions or the switch off leave it down", function()
    local Scene, _, m = forge(true)
    stub.EnterCombat()
    craft(HELM, 3)
    T.eq(Scene.state, "idle")
    stub.LeaveCombat()
    stub.casting = nil
    m.db.forgeScene = false
    craft(HELM, 3)
    T.eq(Scene.state, "idle")
end)

T.test("qol: forge: a batch runs on one tide and counts its items", function()
    local Scene = forge(true)
    stub.left = 3
    craft(HELM, 2)
    T.eq(frame().count:GetText(), "1 / 4")
    local full = UIParent:GetWidth() * Scene.TIDE_WIDE
    play(2)
    T.near(frame().tide:GetWidth() / full, 0.5 * 0.5, 0.03)
    done(HELM)
    stub.left = 2
    craft(HELM, 2)
    T.eq(frame().count:GetText(), "2 / 4")
    T.eq(Scene.state, "line", "the same forge")
    play(2)
    T.near(frame().tide:GetWidth() / full, 0.5, 0.03)
end)

T.test("qol: forge: each item throws sparks, the same recipe made one at a time starts over", function()
    local Scene = forge(true)
    craft(HELM, 1)
    play(1)
    local before = dropsUp(frame())
    done(HELM)
    T.eq(dropsUp(frame()) >= before + Scene.BURST, true, "sparks")
    T.eq(frame().count:IsShown(), false, "one item: no count")
    play(1)
    craft(HELM, 1)
    play(0.5)
    T.near(frame().tide:GetWidth() / (UIParent:GetWidth() * Scene.TIDE_WIDE), 0.5, 0.05)
end)

T.test("qol: forge: it leaves after the last item, and the water still comes back for fishing", function()
    local Scene = forge(true)
    craft(HELM, 1)
    play(1)
    done(HELM)
    play(Scene.CRAFT_LINGER + 0.1)
    stub.RunTimers()
    T.eq(Scene.state, "idle")
    T.eq(DaylightUI.Fade.Hushed(), false)
    cast()
    T.eq(frame().bobber:GetTexture(), Scene.THEMES.water.object)
    T.eq(frame().hammer:IsShown(), false)
    T.eq(frame().count:IsShown(), false)
end)

T.test("qol: forge: another recipe doesn't wake it, another spell and moving do", function()
    local Scene = forge(true)
    craft(HELM, 3)
    stub.FireEvent("UNIT_SPELLCAST_SENT", "player", "", "guid", HELM + 1)
    T.eq(Scene.state, "line", "the next recipe")
    C_TradeSkillUI.GetProfessionInfoByRecipeID = function() return { professionID = 185 } end
    stub.FireEvent("UNIT_SPELLCAST_SENT", "player", "", "guid", 133)
    T.eq(Scene.state, "idle")
end)

T.test("qol: forge: no motion: it still comes and goes", function()
    local Scene = forge(true)
    DaylightUI.Motion.On = function() return false end
    craft(HELM, 1)
    play(1)
    done(HELM)
    T.eq(dropsUp(frame()), 0)
    stub.FireEvent("PLAYER_STARTED_MOVING")
    T.eq(frame():IsShown(), false)
    T.eq(Scene.state, "idle")
end)

T.test("qol: forge: the preview plays a small batch", function()
    local Scene = forge(true)
    Scene.PreviewCraft("forge")
    T.eq(Scene.state, "line")
    T.eq(frame().count:GetText(), "1 / " .. Scene.CRAFT_PREVIEW)
    stub.Advance(Scene.CRAFT_SECS + 0.05)
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The brew (the scene's alchemy theme): the forge's batch, with bubbles.
local function bubbles(f)
    local up = 0
    for _, d in ipairs(f.drops) do if d.tex:IsShown() then up = up + 1 end end
    return up
end

T.test("qol: brew: alchemy brings it up in its own look", function()
    local Scene = forge(true)
    craft(POTION, 3)
    T.eq(Scene.state, "line")
    T.eq(frame().bobber:GetTexture(), Scene.THEMES.brew.object, "the flask")
    T.eq(frame().hammer:IsShown(), false, "no hammer at a flask")
    T.eq(frame().drops[1].tex:GetTexture(), DaylightUI.MEDIA .. "fish-ripple.png", "drops are bubbles")
end)

T.test("qol: brew: a batch counts its potions on one tide", function()
    local Scene = forge(true)
    stub.left = 19
    craft(POTION, 2)
    T.eq(frame().count:GetText(), "1 / 20")
    play(2)
    done(POTION)
    stub.left = 18
    craft(POTION, 2)
    T.eq(frame().count:GetText(), "2 / 20")
    T.near(frame().tide:GetWidth() / (UIParent:GetWidth() * Scene.TIDE_WIDE), 1 / 20, 0.02)
end)

T.test("qol: brew: bubbles rise through the tide, stop with the craft, and leave by themselves", function()
    local Scene = forge(true)
    craft(POTION, 6)
    play(5)
    local f = frame()
    local up = bubbles(f)
    T.eq(up > 0, true, "bubbles while brewing")
    T.eq(up <= Scene.THEMES.brew.bubbles * Scene.BUBBLE_LIFE + 2, true, "a calm stream, no pile-up")
    local y
    for _, d in ipairs(f.drops) do if d.tex:IsShown() then y = d end end
    local from = y.y
    play(0.2)
    T.eq(y.y > from, true, "up, not down")
    stub.casting = nil
    stub.FireEvent("UNIT_SPELLCAST_STOP", "player", "guid", POTION)
    play(Scene.BUBBLE_LIFE + 0.1)
    T.eq(bubbles(f), 0, "none left once the craft stops")
end)

T.test("qol: brew: each potion sends a rush of bubbles, the water after it is plain drops again", function()
    local Scene = forge(true)
    craft(POTION, 1)
    play(1)
    local before = bubbles(frame())
    done(POTION)
    T.eq(bubbles(frame()) >= before + Scene.BURST, true)
    play(Scene.CRAFT_LINGER + 0.1)
    stub.RunTimers()
    play(Scene.GLOW_OUT + 0.2)
    cast()
    T.eq(frame().drops[1].tex:GetTexture(), DaylightUI.MEDIA .. "char-glow.png")
    T.eq(frame().bobber:GetTexture(), Scene.THEMES.water.object)
end)

T.test("qol: brew: a fight, the switch off and the preview", function()
    local Scene, _, m = forge(true)
    stub.EnterCombat()
    craft(POTION, 3)
    T.eq(Scene.state, "idle")
    stub.LeaveCombat()
    stub.casting = nil
    m.db.brewScene = false
    craft(POTION, 3)
    T.eq(Scene.state, "idle", "its own switch")
    stub.casting = nil
    m.db.brewScene = true
    Scene.PreviewCraft("brew")
    T.eq(frame().bobber:GetTexture(), Scene.THEMES.brew.object)
    T.eq(frame().count:GetText(), "1 / " .. Scene.CRAFT_PREVIEW)
end)

-- Smelting copper once showed nothing because Mining had no theme. A recipe can
-- answer with a profession id that isn't known, so the open window's profession
-- wins, the same one the profession window itself trusts.
T.test("qol: forge: a recipe answering with an unknown id still counts through the open window", function()
    local Scene = forge(true)
    C_TradeSkillUI.GetProfessionInfoByRecipeID = function() return { professionID = 2872 } end
    C_TradeSkillUI.GetBaseProfessionInfo = function() return { professionID = 164 } end
    craft(HELM, 3)
    T.eq(Scene.state, "line")
    T.eq(frame().bobber:GetTexture(), Scene.THEMES.forge.object)
end)

T.test("qol: forge: the game's skill line check counts with no window open", function()
    local Scene = forge(true)
    C_TradeSkillUI.GetProfessionInfoByRecipeID = function() return {} end
    C_TradeSkillUI.GetBaseProfessionInfo = function() return nil end
    C_TradeSkillUI.IsRecipeInSkillLine = function(_, line) return line == 164 end
    craft(HELM, 3)
    T.eq(Scene.state, "line")
end)

T.test("qol: forge: smelting is forge work too", function()
    local Scene = forge(true)
    C_TradeSkillUI.GetProfessionInfoByRecipeID = function() return { professionID = 186 } end
    craft(2657, 3)
    T.eq(Scene.state, "line")
    T.eq(frame().bobber:GetTexture(), Scene.THEMES.forge.object)
end)

T.test("qol: forge: an open smithing window never keeps a plain spell from waking it", function()
    local Scene = forge(true)
    craft(HELM, 3)
    C_TradeSkillUI.GetProfessionInfoByRecipeID = function() return { professionID = 0 } end
    C_TradeSkillUI.GetBaseProfessionInfo = function() return { professionID = 164 } end
    C_TradeSkillUI.IsRecipeInSkillLine = function() return false end
    stub.FireEvent("UNIT_SPELLCAST_SENT", "player", "", "guid", 133)
    T.eq(Scene.state, "idle")
end)

-- The workshop (the scene's engineering theme): two gears in mesh.
local function turned(tex) return rawget(tex, "spunTo") or 0 end

-- Each gear notes the turn it's given.
local function watchGears()
    for _, tex in ipairs({ frame().bobber, frame().hammer }) do
        rawset(tex, "SetRotation", function(self, r) rawset(self, "spunTo", r) end)
    end
end

T.test("qol: workshop: engineering brings it up in its own look", function()
    local Scene = forge(true)
    craft(BOMB, 3)
    T.eq(Scene.state, "line")
    local t = Scene.THEMES.workshop
    T.eq(frame().bobber:GetTexture(), t.object)
    T.eq(frame().hammer:GetTexture(), t.second, "the small gear, not the hammer")
    T.eq(frame().hammer:IsShown(), true)
end)

T.test("qol: workshop: the gears turn opposite ways, the small one twice as fast", function()
    local Scene = forge(true)
    craft(BOMB, 3)
    watchGears()
    play(1)
    local big, small = turned(frame().bobber), turned(frame().hammer)
    T.eq(big > 0, true)
    T.near(small, -big * Scene.GEAR_RATIO, 0.001)
end)

T.test("qol: workshop: a finished item kicks them, then they settle", function()
    local Scene = forge(true)
    local speed = Scene.THEMES.workshop.spin
    craft(BOMB, 1)
    watchGears()
    play(1)
    local at = turned(frame().bobber)
    done(BOMB)
    play(0.1)
    local fast = (turned(frame().bobber) - at) / 0.1
    T.eq(fast > speed * 2, true, "a kick of speed")
    play(Scene.GEAR_SETTLE)
    at = turned(frame().bobber)
    play(0.1)
    T.near((turned(frame().bobber) - at) / 0.1, speed, 0.02, "back to normal")
end)

T.test("qol: workshop: the hammer comes back after gears, at its own size", function()
    local Scene = forge(true)
    craft(BOMB, 1)
    play(1)
    stub.casting = nil
    stub.FireEvent("PLAYER_STARTED_MOVING")
    play(Scene.GLOW_OUT + 0.3)
    craft(HELM, 1)
    T.eq(frame().hammer:GetTexture(), DaylightUI.MEDIA .. "forge-hammer.png")
    T.near(frame().hammer:GetWidth(), Scene.HAMMER, 0.1)
end)

T.test("qol: workshop: no motion leaves them still; its own switch and preview", function()
    local Scene, _, m = forge(true)
    m.db.workshopScene = false
    craft(BOMB, 3)
    T.eq(Scene.state, "idle", "its own switch")
    stub.casting = nil
    m.db.workshopScene = true
    Scene.PreviewCraft("workshop")
    T.eq(frame().bobber:GetTexture(), Scene.THEMES.workshop.object)
    Scene.Wake(true)
    DaylightUI.Motion.On = function() return false end
    craft(BOMB, 3)
    watchGears()
    play(0.1)
    local at = turned(frame().bobber)
    play(1)
    T.eq(turned(frame().bobber), at, "still")
end)

-- The sewing (the scene's tailoring theme): a seam that grows with the batch.
local function stitchesLit(f)
    local n = 0
    for _, t in ipairs(f.bits) do if t:GetAlpha() > 0.3 then n = n + 1 end end
    return n
end

T.test("qol: sewing: tailoring brings it up in its own look, stitches instead of a waterline", function()
    local Scene = forge(true)
    craft(SHIRT, 3)
    T.eq(Scene.state, "line")
    local t = Scene.THEMES.sewing
    T.eq(frame().bobber:GetTexture(), t.object)
    T.eq(frame().hammer:GetTexture(), t.second, "the needle")
    T.eq(frame().bits[1]:GetHeight(), 4, "short stitches")
end)

T.test("qol: sewing: the seam grows with the batch, the needle at its end", function()
    local Scene = forge(true)
    stub.left = 3
    craft(SHIRT, 2)
    play(Scene.GLOW_IN + 0.1)
    local early = stitchesLit(frame())
    play(4)
    T.eq(stitchesLit(frame()) > early, true, "more stitches")
    local _, _, _, x = frame().hammer:GetPoint()
    T.near(x, UIParent:GetWidth() / 2 + UIParent:GetWidth() * Scene.TIDE_WIDE * ((Scene.GLOW_IN + 4.1) / 8) * 0.46, 20)
end)

T.test("qol: sewing: a finished item puffs fluff that leaves by itself", function()
    local Scene = forge(true)
    craft(SHIRT, 1)
    play(1)
    done(SHIRT)
    T.eq(dropsUp(frame()) >= Scene.BURST, true, "a puff")
    play(Scene.THEMES.sewing.life + 0.1)
    T.eq(dropsUp(frame()), 0, "gone")
end)

T.test("qol: sewing: the water's line comes back after stitches; its own switch and preview", function()
    local Scene, _, m = forge(true)
    craft(SHIRT, 1)
    play(1)
    stub.casting = nil
    stub.FireEvent("PLAYER_STARTED_MOVING")
    play(Scene.GLOW_OUT + 0.3)
    cast()
    T.eq(frame().bits[1]:GetHeight(), 9)
    stub.channel = nil
    stub.FireEvent("PLAYER_STARTED_MOVING")
    play(Scene.GLOW_OUT + 0.3)
    m.db.sewingScene = false
    craft(SHIRT, 3)
    T.eq(Scene.state, "idle", "its own switch")
    stub.casting = nil
    m.db.sewingScene = true
    Scene.PreviewCraft("sewing")
    T.eq(frame().bobber:GetTexture(), Scene.THEMES.sewing.object)
end)

-- Keep tracking on.

local function trackingWorld(list)
    _G.C_Minimap = {
        GetNumTrackingTypes = function() return #list end,
        GetTrackingInfo = function(i) return list[i] end,
        SetTracking = function(i, on)
            list[i].active = on
            stub.FireEvent("MINIMAP_UPDATE_TRACKING")
        end,
    }
    _G.UnitIsDeadOrGhost = function() return false end
end

local function trackingLoad(keep)
    local list = {
        { name = "Flight Master", active = true },
        { name = "Find Herbs", spellID = 2383, active = false },
        { name = "Find Minerals", spellID = 2580, active = false },
    }
    stub.Load({ qol = true, before = function()
        trackingWorld(list)
    end })
    local Q = DaylightUI:GetModule("QoL")
    DaylightUI.DB.Character().tracking = keep
    return list, Q
end

local function settle()
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, false)
    stub.RunTimers()   -- the wait after arriving
    stub.RunTimers()   -- the wait before changes count
end

T.test("qol tracking: what was kept comes back after logging in", function()
    local list = trackingLoad({ 2580 })
    settle()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(list[3].active, true, "Find Minerals is on")
    T.eq(list[2].active, false, "Find Herbs stays off")
end)

T.test("qol tracking: it goes by spell, not by its spot in the list", function()
    local list = trackingLoad({ 2580 })
    table.remove(list, 2)
    settle()
    T.eq(list[2].name, "Find Minerals")
    T.eq(list[2].active, true)
end)

T.test("qol tracking: turning it off yourself stays off", function()
    local list = trackingLoad({ 2580 })
    settle()
    C_Minimap.SetTracking(3, false)
    T.eq(DaylightUI.DB.Character().tracking, nil)
    settle()
    T.eq(list[3].active, false)
end)

T.test("qol tracking: a new pick is what's kept", function()
    trackingLoad(nil)
    settle()
    C_Minimap.SetTracking(2, true)
    T.eq(DaylightUI.DB.Character().tracking[1], 2383)
end)

T.test("qol tracking: leaving the world dropping it isn't the player turning it off", function()
    local list = trackingLoad({ 2580 })
    settle()
    stub.FireEvent("PLAYER_LEAVING_WORLD")
    list[3].active = false
    stub.FireEvent("MINIMAP_UPDATE_TRACKING")
    T.eq(DaylightUI.DB.Character().tracking[1], 2580, "still kept")
    settle()
    T.eq(list[3].active, true, "back on")
end)

T.test("qol tracking: dying drops it, coming back brings it back", function()
    local list = trackingLoad({ 2580 })
    settle()
    _G.UnitIsDeadOrGhost = function() return true end
    list[3].active = false
    stub.FireEvent("MINIMAP_UPDATE_TRACKING")
    stub.FireEvent("PLAYER_DEAD")
    T.eq(DaylightUI.DB.Character().tracking[1], 2580, "still kept")
    _G.UnitIsDeadOrGhost = function() return false end
    stub.FireEvent("PLAYER_UNGHOST")
    stub.RunTimers()
    T.eq(list[3].active, true, "back on")
end)

T.test("qol tracking: a turn-on that didn't take isn't forgotten", function()
    local list = trackingLoad({ 2580 })
    C_Minimap.SetTracking = function() end
    settle()
    T.eq(list[3].active, false)
    T.eq(DaylightUI.DB.Character().tracking[1], 2580)
end)

T.test("qol tracking: switched off, nothing is turned on", function()
    local list, Q = trackingLoad({ 2580 })
    Q.db.keepTracking = false
    settle()
    T.eq(list[3].active, false)
end)

-- Object glow (Glow.lua): the light hangs off the soft target's plate.

local function glowSetup(setting, before, own)
    local cvars = { SoftTargetInteract = "0", SoftTargetInteractRange = "10", SoftTargetInteractArc = "1",
        SoftTargetInteractOnlyInRange = "1", SoftTargetInteractRangeIsHard = "1", SoftTargetIconGameObject = "0",
        SoftTargetNameplateInteract = "0", SoftTargetIconInteract = "1", nameplateGameObjectMaxDistance = "30" }
    for k, v in pairs(own or {}) do cvars[k] = v end
    local g = { cvars = cvars, cursor = "Interface\\Cursor\\LootAll", near = true, isObject = true, profs = { 186 } }
    local saved = {}
    for _, k in ipairs({ "GetCVar", "SetCVar", "UnitIsGameObject", "SetUnitCursorTexture", "UnitIsInInteractRange",
        "GetProfessions", "GetProfessionInfo", "IsInInstance", "C_NamePlate" }) do saved[k] = _G[k] end
    _G.GetCVar = function(k) return cvars[k] end
    _G.SetCVar = function(k, v) cvars[k] = v end
    _G.UnitIsGameObject = function(u) return u == "softinteract" and g.isObject end
    _G.SetUnitCursorTexture = function(tex, u)
        if u ~= "softinteract" or not g.cursor then return false end
        tex:SetTexture(g.cursor)
        return true
    end
    _G.UnitIsInInteractRange = function() return g.near end
    _G.GetProfessions = function() return 1, 2 end
    _G.GetProfessionInfo = function(i) return "p", 0, 1, 300, 0, 0, g.profs[i] end
    _G.C_NamePlate = setmetatable({ GetNamePlateForUnit = function(u)
        if u == "softinteract" and g.plateUp then return g.plate end
    end }, { __index = saved.C_NamePlate })
    function g.done()
        for _, k in ipairs({ "GetCVar", "SetCVar", "UnitIsGameObject", "SetUnitCursorTexture", "UnitIsInInteractRange",
            "GetProfessions", "GetProfessionInfo", "IsInInstance", "C_NamePlate" }) do _G[k] = saved[k] end
    end
    stub.Load({ qol = true, before = before })
    _G.IsInInstance = function() return g.inside == true end
    stub.units.softinteract = { name = "Battered Chest", guid = "GameObject-0-1-2-3-2843-00001" }
    g.plate = CreateFrame("Frame", nil, UIParent)
    g.m = DaylightUI:GetModule("QoL")
    g.G = stub.qol.Glow
    if setting ~= nil then g.m.db.objectGlow = setting; g.m:OnSettingChanged() end
    function g.at(guid, name)
        stub.units.softinteract.guid, stub.units.softinteract.name = guid, name
    end
    return g
end

local function soft() stub.FireEvent("PLAYER_SOFT_INTERACT_CHANGED", "old", "new") end

T.test("glow: on takes the interact settings, off gives back what the player had", function()
    local g = glowSetup(true)
    T.eq(g.cvars.SoftTargetInteract, "3")
    T.eq(g.cvars.SoftTargetInteractRange, "15")
    T.eq(g.cvars.SoftTargetIconGameObject, "1")
    T.eq(g.cvars.nameplateGameObjectMaxDistance, "60")
    g.m.db.objectGlow = false
    g.m:OnSettingChanged()
    T.eq(g.cvars.SoftTargetInteract, "0")
    T.eq(g.cvars.SoftTargetInteractRange, "10")
    T.eq(g.cvars.SoftTargetIconGameObject, "0")
    T.eq(g.cvars.SoftTargetIconInteract, "1")
    T.eq(g.cvars.nameplateGameObjectMaxDistance, "30")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    g.done()
end)

T.test("glow: logging out gives the settings back, so none outlives the addon", function()
    local g = glowSetup(true)
    stub.FireEvent("PLAYER_LOGOUT")
    T.eq(g.cvars.SoftTargetInteract, "0")
    T.eq(g.cvars.nameplateGameObjectMaxDistance, "30")
    g.done()
end)

T.test("glow: the game's plate opens only for what lights up, and the light lands on it", function()
    local g = glowSetup(true)
    local G = g.G
    soft()
    T.eq(g.cvars.SoftTargetNameplateInteract, "1")
    T.eq(G.art:IsShown(), false, "no plate yet")
    g.plateUp = true
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    T.eq(G.art:IsShown(), true)
    T.eq(G.art:GetParent(), g.plate)
    T.eq(G.art.kind, "chest")
    T.eq(G.art.state, "ready")
    g.isObject = false   -- an NPC now: no light, and the plate shut again
    soft()
    T.eq(G.art:IsShown(), false)
    T.eq(g.cvars.SoftTargetNameplateInteract, "0")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    g.done()
end)

T.test("glow: a lit bobber hides the game's interact icon, a chest keeps it, and leaving gives it back", function()
    local g = glowSetup(true)
    local G = g.G
    local function plateWithIcon()
        local p = CreateFrame("Frame", nil, UIParent)
        p.UnitFrame = CreateFrame("Frame", nil, p)
        p.UnitFrame.SoftTargetFrame = CreateFrame("Frame", nil, p.UnitFrame)
        return p, p.UnitFrame.SoftTargetFrame
    end
    local bobber, bobberIcon = plateWithIcon()
    G.Show(bobber, "bobber", "ready", "GameObject-0-0-0-0-35591-1")
    T.eq(bobberIcon:GetAlpha(), 0, "one marker on the bobber, the light")
    local chest, chestIcon = plateWithIcon()
    G.Show(chest, "chest", "ready", "GameObject-0-0-0-0-2843-1")
    T.eq(bobberIcon:GetAlpha(), 1, "the bobber's plate gets its icon back")
    T.eq(chestIcon:GetAlpha(), 1, "a chest keeps the game's icon")
    G.Leave()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    g.done()
end)

-- Ore and herbs stay dark, even for a character who gathers them: the plate
-- switched on and off for every node is suspected of stopping all plates.
T.test("glow: ore and herbs never light, and never open the game's plate", function()
    local g = glowSetup(true)
    g.plateUp = true
    for _, node in ipairs({ { "Interface\\Cursor\\Mine", "Copper Vein", 1731 },
        { "Interface\\Cursor\\GatherHerbs", "Peacebloom", 1617 } }) do
        g.cursor = node[1]
        g.at("GameObject-0-1-2-3-" .. node[3] .. "-00001", node[2])
        soft()
        T.eq(g.G.art:IsShown(), false, node[2])
        T.eq(g.cvars.SoftTargetNameplateInteract, "0", node[2])
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    g.done()
end)

T.test("glow: an object it doesn't light keeps the plate the player's own settings show", function()
    -- The player shows the interact plate themself, so every node has a plate.
    -- Closing the gate must not hide it (node plates used to flash up, then go).
    local g = glowSetup(true, nil, { SoftTargetNameplateInteract = "1", SoftTargetIconInteract = "0" })
    g.cursor = "Interface\\Cursor\\Mine"   -- ore stays dark
    g.at("GameObject-0-1-2-3-1731-00001", "Copper Vein")
    g.plateUp = true
    soft()
    T.eq(g.G.art:IsShown(), false)
    T.eq(g.cvars.SoftTargetNameplateInteract, "1")
    T.eq(g.cvars.SoftTargetIconInteract, "0")
    g.isObject = false   -- an NPC: the player's own plate stays too
    soft()
    T.eq(g.cvars.SoftTargetNameplateInteract, "1")
    g.cursor = "Interface\\Cursor\\LootAll"   -- a chest it lights: the plate shows, then the player's own again
    g.at("GameObject-0-1-2-3-2843-00001", "Battered Chest")
    g.isObject = true
    soft()
    T.eq(g.G.art:IsShown(), true)
    T.eq(g.cvars.SoftTargetIconInteract, "0", "the player's own icon setting, opened")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    g.done()
end)

T.test("glow: far, in reach and refused each show, and reaching it runs the ring", function()
    local g = glowSetup(true)
    local G = g.G
    g.plateUp = true
    g.near = false
    soft()
    T.eq(G.art.state, "far")
    T.eq(G.art.ringAge, nil)
    g.near = true
    soft()
    T.eq(G.art.state, "ready")
    T.eq(G.art.ringAge, 0)
    g.cursor = "Interface\\Cursor\\UnableLootAll"
    soft()
    T.eq(G.art.state, "locked")
    g.done()
end)

T.test("glow: the light sits lower once in reach, and follows the height setting", function()
    local g = glowSetup(true)
    local G = g.G
    g.m.db.objectGlowHeight = 100
    g.plateUp = true
    g.near = false
    soft()
    T.eq(math.floor(G.art.drop + 0.5), 55)
    g.near = true
    soft()
    G.art:GetScript("OnUpdate")(G.art, 1)
    T.eq(G.art.drop, 100)
    g.done()
end)

T.test("glow: a far object's plate that comes after the events still gets its light", function()
    local g = glowSetup(true)
    local G = g.G
    g.near = false
    soft()                  -- the target changed, its plate not there yet
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")   -- and still not, as the event comes
    T.eq(G.art:IsShown(), false)
    g.plateUp = true        -- the game can give it now, and tells nobody
    G.Watch()
    T.eq(G.art:IsShown(), true)
    T.eq(G.art.state, "far")
    g.done()
end)

T.test("glow: what an object is", function()
    local g = glowSetup(true)
    local G = g.G
    T.eq((G.ReadCursorName("Interface\\Cursor\\GatherHerbs")), "herb")
    T.eq((G.ReadCursorName("Cursor_Crosshair_UnableMine_64")), "ore")
    T.eq((G.ReadCursorName("QuestInteract")), "quest")
    T.eq(select(2, G.ReadCursorName("UnableMine")), true)
    T.eq(G.ObjectID("GameObject-0-1-2-3-35591-0000AA"), 35591)
    T.eq(G.ObjectID("Creature-0-1-2-3-35591-0000AA"), nil)
    T.eq(G.IsChest(nil, "Battered Chest"), true)
    T.eq(G.IsChest(nil, "Mountain Silversage"), false)
    g.plateUp = true
    g.cursor = "Interface\\Cursor\\Interact"
    g.at("GameObject-0-1-2-3-35591-00002", "Fishing Bobber")   -- the bobber wears any object's cursor
    soft()
    T.eq(G.art.kind, "bobber")
    g.at("GameObject-0-1-2-3-99-00003", "Battered Chest")      -- a chest wears a lever's
    soft()
    T.eq(G.art.kind, "chest")
    g.at("GameObject-0-1-2-3-98-00004", "Lever")               -- other is off by default
    soft()
    T.eq(G.art:IsShown(), false)
    g.cursor = "Interface\\Cursor\\Mail"
    g.at("GameObject-0-1-2-3-97-00005", "Mailbox")
    soft()
    T.eq(G.art:IsShown(), false)
    g.done()
end)

T.test("glow: a looted crate counts as a chest from then on, ore never does", function()
    local g = glowSetup(true)
    local G = g.G
    local count, source = _G.GetNumLootItems, _G.GetLootSourceInfo
    _G.GetNumLootItems = function() return 1 end
    _G.GetLootSourceInfo = function() return "GameObject-0-1-2-3-555-00009" end
    stub.FireEvent("LOOT_READY")
    T.eq(G.IsChest(555, "Plain Thing"), true)
    g.plateUp = true
    g.cursor = "Interface\\Cursor\\Mine"
    g.at("GameObject-0-1-2-3-1731-00001", "Copper Vein")
    soft()   -- id 1731, ore by its cursor
    _G.GetLootSourceInfo = function() return "GameObject-0-1-2-3-1731-00001" end
    stub.FireEvent("LOOT_READY")
    T.eq(G.IsChest(1731, "Copper Vein"), false)
    _G.GetNumLootItems, _G.GetLootSourceInfo = count, source
    g.done()
end)

T.test("glow: a fight or an instance puts it out by default, and each has a switch", function()
    local g = glowSetup(true)
    local G = g.G
    g.plateUp = true
    soft()
    T.eq(G.art:IsShown(), true)
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    T.eq(G.art:IsShown(), false)
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    T.eq(G.art:IsShown(), true)
    g.inside = true
    soft()
    T.eq(G.art:IsShown(), false)
    g.m.db.objectGlowInstance = true
    soft()
    T.eq(G.art:IsShown(), true)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    g.done()
end)

T.test("glow: a secret answer reads as nothing, never an error", function()
    local g = glowSetup(true)
    local objectIs = _G.UnitIsGameObject
    _G.UnitIsGameObject = function() return stub.Secret(true) end
    g.plateUp = true
    soft()
    T.eq(g.G.art:IsShown(), false)
    _G.UnitIsGameObject = objectIs
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    g.done()
end)

T.test("glow: casting Fishing looks further for the bobber until the line comes in", function()
    local g = glowSetup(true)
    local Fish = stub.qol.Fishing
    local spell = Fish.Spell
    Fish.Spell = function() return 7620 end
    stub.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "player", "cast", 7620)
    T.eq(g.cvars.SoftTargetInteractRange, "60")
    stub.FireEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast", 7620)
    T.eq(g.cvars.SoftTargetInteractRange, "15")
    Fish.Spell = spell
    g.done()
end)

T.test("glow: its driver runs only while a light shows, and the light fades out where it stood", function()
    local g = glowSetup(true)
    local G = g.G
    T.eq(G.art:IsShown(), false, "nothing shows: its OnUpdate is still")
    T.eq(G.ghost:IsShown(), false)
    g.plateUp = true
    soft()
    G.art:GetScript("OnUpdate")(G.art, 1)
    T.eq(G.art.arrive, 1)
    G.art.gx, G.art.gy = 100, 200
    g.isObject = false
    soft()
    T.eq(G.art:IsShown(), false)
    T.eq(G.ghost:IsShown(), true)
    G.ghost:GetScript("OnUpdate")(G.ghost, 1)
    T.eq(G.ghost:IsShown(), false)
    g.done()
end)

T.test("glow: every look paints, and shows only its own pieces", function()
    local g = glowSetup(true)
    local G = g.G
    g.plateUp = true
    local pieces = { daybreak = "shaft", frame = "frame", sunrise = "sun", sweep = "track" }
    for look, piece in pairs(pieces) do
        G.Leave()
        g.m.db.objectGlowLook = look
        soft()
        G.art:GetScript("OnUpdate")(G.art, 0.1)
        T.eq(G.art.look, look)
        for other, name in pairs(pieces) do
            T.eq(G.art[name]:IsShown(), name == piece, look .. " " .. other)
        end
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    g.done()
end)

T.test("glow: an unknown look falls back to the sweep, and the light follows the color setting", function()
    local g = glowSetup(true)
    local G = g.G
    g.m.db.objectGlowLook = "gone"
    T.eq(G.LookOf(), "sweep")
    g.m.db.objectGlowColor = "object"
    local lo = G.ColorOf("quest")
    T.eq(lo, G.KINDS.quest)
    g.m.db.objectGlowColor = "accent"
    local Style = DaylightUI.Style
    local pair = Style.AccentPair()
    T.eq(G.ColorOf("quest")[1], pair and pair[1] or (Style.Accent()))
    g.done()
end)

T.test("cursor ring: follows the cursor, in a fight only when asked, gone (and still) once faded", function()
    stub.Load({ qol = true })
    local m = DaylightUI:GetModule("QoL")
    local ns = m.ns
    T.isnil(_G.DaylightUICursorRing, "off by default: nothing made")
    m.db.cursorRing = true
    m:OnSettingChanged()
    local f = _G.DaylightUICursorRing
    T.truthy(f and f:IsShown())
    stub.cursorPos = { 300, 200 }
    f:GetScript("OnUpdate")(f, 0.016)
    local _, _, _, x, y = f:GetPoint(1)
    local s = UIParent:GetEffectiveScale()
    T.near(x, 300 / s, 0.01); T.near(y, 200 / s, 0.01)
    T.eq(f:GetWidth(), 40)
    m.db.cursorRingWhen = "combat"
    m:OnSettingChanged()
    stub.RunTimers()
    T.falsy(f:IsShown(), "out of a fight: faded and hidden, its OnUpdate stopped")
    stub.EnterCombat()
    T.truthy(f:IsShown(), "a fight brings it at once")
    stub.LeaveCombat()
    stub.RunTimers()
    T.falsy(f:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(ns.CursorRing)
end)

T.test("cursor ring: the accent's gradient, a comet running round, casts, the flash and a trail", function()
    stub.Load({ qol = true })
    local DUI = DaylightUI
    local m = DUI:GetModule("QoL")
    local R = m.ns.CursorRing
    DUI:Set("general", "accent", "gradient")
    m.db.cursorRing = true
    m:OnSettingChanged()
    local f = _G.DaylightUICursorRing
    T.truthy(f and f:IsShown())
    T.truthy(f.ring.__gradient, "a gradient accent runs across the ring")
    local lo = DUI.Style.AccentPair()
    T.eq(f.lo, lo)

    -- The comet moves round the ring.
    local function at(t) local _, _, _, x, y = t:GetPoint(1); return x, y end
    local x1, y1 = at(f.dots[1])
    f:GetScript("OnUpdate")(f, 0.5)
    local x2, y2 = at(f.dots[1])
    T.truthy(math.abs(x2 - x1) + math.abs(y2 - y1) > 1, "the head moved")
    T.near(math.sqrt(x2 * x2 + y2 * y2), 40 * R.RADIUS, 0.01, "on the line")
    m.db.cursorRingMotion = "still"
    m:OnSettingChanged()
    T.falsy(f.dots[1]:IsShown(), "still: no comet")

    -- Your cast fills the outer ring, and leaves with it.
    stub.units.player = stub.units.player or { name = "You" }
    local d = stub.Duration(2)
    stub.units.player.cast = { name = "Fireball", duration = d }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    T.truthy(f.cast.__duration, "the cast's duration (a secret copy) on the outer ring")
    stub.units.player.cast = nil
    stub.FireEvent("UNIT_SPELLCAST_STOP", "player")
    stub.FireEvent("UNIT_SPELLCAST_START", "target")

    -- The global cooldown: in a fight its times are secret, so the game's duration object.
    local gcd = stub.Duration(1.5)
    _G.C_Spell = _G.C_Spell or {}
    local was, read = C_Spell.GetSpellCooldownDuration, C_Spell.GetSpellCooldown
    C_Spell.GetSpellCooldownDuration = function(id) return id == R.GCD_SPELL and gcd or nil end
    C_Spell.GetSpellCooldown = function()
        return { isActive = true, isOnGCD = true, startTime = stub.Secret(50), duration = stub.Secret(1.5) }
    end
    stub.FireEvent("SPELL_UPDATE_COOLDOWN")
    T.eq(f.gcd.__duration, gcd)
    C_Spell.GetSpellCooldownDuration = was
    -- Plain times (out of a fight): its start and length.
    C_Spell.GetSpellCooldown = function() return { isActive = true, startTime = 50, duration = 1.5 } end
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    T.eq(f.gcd.__cooldown[1], 50); T.eq(f.gcd.__cooldown[2], 1.5)
    C_Spell.GetSpellCooldown = read

    -- The global cooldown ending flashes the ring, then it settles.
    f.gcd:GetScript("OnCooldownDone")(f.gcd)
    T.eq(f.flash, 1)
    f:GetScript("OnUpdate")(f, 1)
    T.eq(f.flash, 0)

    -- The trail: dots left behind as the cursor moves, gone after their time.
    m.db.cursorRingTrail = true
    m:OnSettingChanged()
    for i = 1, 6 do
        stub.cursorPos = { 100 + i * 20, 100 }
        f:GetScript("OnUpdate")(f, 0.016)
    end
    T.truthy(f.trail.live, "dots behind the cursor")
    f:GetScript("OnUpdate")(f, 1)
    T.falsy(f.trail.live, "and they fade away")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
