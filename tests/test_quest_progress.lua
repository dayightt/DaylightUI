local stub = require("stub")
local QW = require("questworld")

-- Quest progress: the game's yellow quest lines ("Mindless Zombie slain: 5/8")
-- redrawn in the addon's look. The fake error frame follows the game's
-- UIErrorsMixin:OnEvent rule: suppressed messages are dropped, types listed
-- in BLACK_LISTED_MESSAGE_TYPES are skipped, the rest get AddMessage plus the
-- sound from GetGameMessageInfo. Forever's list holds only "another action
-- in progress".

local ERR = { SPELL_FAILED_ANOTHER_IN_PROGRESS = 1, QUEST_ADD_KILL_SII = 2, QUEST_ADD_ITEM_SII = 3,
    QUEST_ADD_FOUND_SII = 4, QUEST_ADD_PLAYER_KILL_SII = 5, QUEST_OBJECTIVE_COMPLETE_S = 6,
    QUEST_UNKNOWN_COMPLETE = 7, QUEST_COMPLETE_S = 8, QUEST_ACCEPTED_S = 9, INV_FULL = 10 }
local KIT = 777   -- a sound the game plays with one of these lines

local shown, sounds

local function load(over, world)
    shown, sounds = {}, {}
    local game = QW.world(world or { quests = {} })
    stub.Load({ quests = true, before = function()
        game()
        for name, id in pairs(ERR) do _G["LE_GAME_ERR_" .. name] = id end
        _G.BLACK_LISTED_MESSAGE_TYPES = { [ERR.SPELL_FAILED_ANOTHER_IN_PROGRESS] = true }
        _G.UIErrorsFrame = {
            AddExternalErrorMessage = function() end,
            GetMessagesSuppressed = function(self) return self.suppressed == true end,
            AddMessage = function(_, text) shown[#shown + 1] = text end,
            OnEvent = function(self, event, messageType, message)
                if event ~= "UI_INFO_MESSAGE" and event ~= "UI_ERROR_MESSAGE" then return end
                if self:GetMessagesSuppressed() or BLACK_LISTED_MESSAGE_TYPES[messageType] then return end
                self:AddMessage(message)
                local _, kit = GetGameMessageInfo(messageType)
                if kit then PlaySound(kit) end
            end,
        }
        _G.GetGameMessageInfo = function(t) if t == ERR.QUEST_ADD_KILL_SII then return "x", KIT end end
        _G.PlaySound = function(kit) sounds[#sounds + 1] = kit end
        if over then DaylightUIDB = { modules = { Quests = over } } end
    end })
    return DaylightUI:GetModule("Quests"), stub.quests
end

local function done()
    for name in pairs(ERR) do _G["LE_GAME_ERR_" .. name] = nil end
    _G.BLACK_LISTED_MESSAGE_TYPES, _G.GetGameMessageInfo = nil, nil
end

-- The event to the game's frame and to ours; true when the game drew it.
local function fire(name, text)
    local before = #shown
    UIErrorsFrame:OnEvent("UI_INFO_MESSAGE", ERR[name], text)
    stub.FireEvent("UI_INFO_MESSAGE", ERR[name], text)
    return #shown > before
end

local function settle()
    local d = DaylightUI.Motion.Driver()
    for _ = 1, 60 do if d then stub.RunOnUpdate(d, 0.05) end end
end

local function rows(ns)
    local out = {}
    for _, r in ipairs(ns.Progress.rows or {}) do
        if r:IsShown() then out[#out + 1] = r end
    end
    return out
end

T.test("quest progress: on out of the box, the game's quest lines go, every other line stays", function()
    local m = load()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(m.db.progress, true)
    for _, name in ipairs({ "QUEST_ADD_KILL_SII", "QUEST_ADD_ITEM_SII", "QUEST_ADD_FOUND_SII",
            "QUEST_ADD_PLAYER_KILL_SII", "QUEST_OBJECTIVE_COMPLETE_S", "QUEST_UNKNOWN_COMPLETE", "QUEST_COMPLETE_S" }) do
        T.falsy(fire(name, "Thing: 1/2"), name .. " is ours")
    end
    T.truthy(fire("QUEST_ACCEPTED_S", "Quest accepted: The Mindless Ones"), "accepting stays the game's")
    T.truthy(fire("INV_FULL", "Inventory is full."), "errors stay the game's")
    done()
end)

T.test("quest progress: a kill shows the objective, its count and a bar that glides there", function()
    local _, ns = load()
    fire("QUEST_ADD_KILL_SII", "Mindless Zombie slain: 5/8")
    local r = rows(ns)
    T.eq(#r, 1)
    T.eq(r[1].label:GetText(), "Mindless Zombie slain")
    T.eq(r[1].count:GetText(), "5/8")
    T.eq(r[1].bar:IsShown(), true)
    settle()
    T.near(r[1].bar:GetValue(), 5 / 8, 0.001)
    T.eq(r[1].tick:IsShown(), false)
    done()
end)

T.test("quest progress: it leaves by itself after a moment", function()
    local _, ns = load()
    fire("QUEST_ADD_KILL_SII", "Mindless Zombie slain: 5/8")
    T.eq(#rows(ns), 1)
    stub.RunTimers()
    T.eq(#rows(ns), 0)
    done()
end)

T.test("quest progress: the same objective again updates its line in place", function()
    local _, ns = load()
    fire("QUEST_ADD_KILL_SII", "Mindless Zombie slain: 5/8")
    fire("QUEST_ADD_KILL_SII", "Mindless Zombie slain: 6/8")
    local r = rows(ns)
    T.eq(#r, 1)
    T.eq(r[1].count:GetText(), "6/8")
    settle()
    T.near(r[1].bar:GetValue(), 6 / 8, 0.001)
    done()
end)

T.test("quest progress: other objectives get lines of their own, at most three", function()
    local _, ns = load()
    fire("QUEST_ADD_ITEM_SII", "Zombie Brain: 1/4")
    fire("QUEST_ADD_KILL_SII", "Mindless Zombie slain: 5/8")
    T.eq(#rows(ns), 2)
    fire("QUEST_ADD_ITEM_SII", "Bone Fragments: 2/10")
    fire("QUEST_ADD_ITEM_SII", "Rotting Flesh: 3/5")
    local r = rows(ns)
    T.eq(#r, ns.Progress.ROWS)
    local labels = {}
    for _, row in ipairs(r) do labels[row.label:GetText()] = true end
    T.truthy(labels["Rotting Flesh"], "the newest shows")
    T.falsy(labels["Zombie Brain"], "the oldest made room")
    done()
end)

T.test("quest progress: an objective done fills the bar and shows the tick on its line", function()
    local _, ns = load()
    fire("QUEST_ADD_KILL_SII", "Mindless Zombie slain: 7/8")
    fire("QUEST_OBJECTIVE_COMPLETE_S", "Mindless Zombie slain: 8/8 (Complete)")
    local r = rows(ns)
    T.eq(#r, 1, "the same line")
    T.eq(r[1].label:GetText(), "Mindless Zombie slain")
    T.eq(r[1].tick:IsShown(), true)
    settle()
    T.near(r[1].bar:GetValue(), 1, 0.001)
    done()
end)

T.test("quest progress: a whole quest done is gold", function()
    local m, ns = load()
    fire("QUEST_COMPLETE_S", "The Mindless Ones completed.")
    local r = rows(ns)
    T.eq(#r, 1)
    T.eq(r[1].label:GetText(), "The Mindless Ones completed.")
    T.rgb({ r[1].label:GetTextColor() }, m.db.colors.ready)
    T.eq(r[1].count:GetText(), "")
    done()
end)

T.test("quest progress: a line without a count shows whole, with no bar", function()
    local _, ns = load()
    fire("QUEST_ADD_FOUND_SII", "Explore the Crypt")
    local r = rows(ns)
    T.eq(r[1].label:GetText(), "Explore the Crypt")
    T.eq(r[1].bar:IsShown(), false)
    done()
end)

T.test("quest progress: the game's sound for a line still plays, once", function()
    local _, ns = load()
    fire("QUEST_ADD_KILL_SII", "Mindless Zombie slain: 5/8")
    T.eq(#sounds, 1)
    T.eq(sounds[1], KIT)
    fire("QUEST_ADD_ITEM_SII", "Zombie Brain: 1/4")
    T.eq(#sounds, 1, "a line with no sound plays none")
    done()
end)

T.test("quest progress: nothing while the game holds its messages back", function()
    local _, ns = load()
    UIErrorsFrame.suppressed = true
    fire("QUEST_ADD_KILL_SII", "Mindless Zombie slain: 5/8")
    T.eq(#rows(ns), 0)
    T.eq(#sounds, 0)
    done()
end)

T.test("quest progress: switched off, the game's line comes back and ours stays away", function()
    local m, ns = load()
    m.db.progress = false
    m:OnSettingChanged("progress")
    T.truthy(fire("QUEST_ADD_KILL_SII", "Mindless Zombie slain: 5/8"), "the game's line")
    T.eq(#rows(ns), 0)
    T.eq(BLACK_LISTED_MESSAGE_TYPES[ERR.QUEST_ADD_KILL_SII], nil, "removed, not set to false")
    T.eq(BLACK_LISTED_MESSAGE_TYPES[ERR.SPELL_FAILED_ANOTHER_IN_PROGRESS], true, "the game's own entry stays")
    m.db.progress = true
    m:OnSettingChanged("progress")
    T.falsy(fire("QUEST_ADD_KILL_SII", "Mindless Zombie slain: 6/8"))
    T.eq(#rows(ns), 1)
    done()
end)

T.test("quest progress: off from login leaves the game's list untouched", function()
    load({ progress = false })
    local n = 0
    for _ in pairs(BLACK_LISTED_MESSAGE_TYPES) do n = n + 1 end
    T.eq(n, 1)
    done()
end)

T.test("quest progress: a secret line shows whole with no bar; a secret type is left alone", function()
    local _, ns = load()
    stub.FireEvent("UI_INFO_MESSAGE", ERR.QUEST_ADD_KILL_SII, stub.Secret("Mindless Zombie slain: 5/8"))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local r = rows(ns)
    T.eq(#r, 1)
    T.eq(r[1].bar:IsShown(), false)
    stub.RunTimers()
    stub.FireEvent("UI_INFO_MESSAGE", stub.Secret(ERR.QUEST_ADD_KILL_SII), stub.Secret("x"))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(#rows(ns), 0)
    done()
end)

-- Secret lines can't be read or compared, so there's one row per message
-- type and a run of kills updates one row instead of filling all three.
T.test("quest progress: secret lines of one type share a row", function()
    local _, ns = load()
    for i = 1, 3 do
        stub.FireEvent("UI_INFO_MESSAGE", ERR.QUEST_ADD_KILL_SII, stub.Secret("Mindless Zombie slain: " .. i .. "/8"))
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(#rows(ns), 1, "one row for the kills")
    stub.FireEvent("UI_INFO_MESSAGE", ERR.QUEST_ADD_ITEM_SII, stub.Secret("Brass Collar: 1/1"))
    T.eq(#rows(ns), 2, "another type, its own row")
    done()
end)

T.test("quest progress: test mode and unlock mode show a sample that stays", function()
    local _, ns = load()
    DaylightUI.SetTestMode(true)
    T.truthy(#rows(ns) >= 1, "sample in test mode")
    stub.RunTimers()
    T.truthy(#rows(ns) >= 1, "it stays")
    DaylightUI.SetTestMode(false)
    stub.RunTimers()
    T.eq(#rows(ns), 0)
    DaylightUI.Movers.Unlock()
    T.truthy(#rows(ns) >= 1, "sample while unlocked")
    DaylightUI.Movers.Lock()
    stub.RunTimers()
    T.eq(#rows(ns), 0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    done()
end)

T.test("quest progress: Parse finds the last count in any word order", function()
    local _, ns = load()
    local P = ns.Progress.Parse
    local l, h, n = P("Mindless Zombie slain: 5/8")
    T.eq(l, "Mindless Zombie slain"); T.eq(h, 5); T.eq(n, 8)
    l, h, n = P("5/8 Zombies tués")
    T.eq(l, "Zombies tués"); T.eq(h, 5); T.eq(n, 8)
    l, h = P("Objective Complete.")
    T.eq(l, "Objective Complete."); T.isnil(h)
    done()
end)

T.test("quest progress: Pop-up scale scales the whole pop-up", function()
    local m, ns = load({ progressScale = 1.5 })
    local holder = _G.DaylightUIQuestProgress
    T.eq(holder:GetScale(), 1.5)
    m.db.progressScale = 0.8
    m:OnSettingChanged("progressScale")
    T.eq(holder:GetScale(), 0.8)
    done()
end)

T.test("quest progress: Stays for sets how long a line stays", function()
    local m, ns = load({ progressHold = 4 })
    local waits, after = {}, C_Timer.After
    C_Timer.After = function(s, fn) waits[#waits + 1] = s; return after(s, fn) end
    fire("QUEST_ADD_KILL_SII", "Mindless Zombie slain: 5/8")
    T.eq(waits[#waits], 4)
    m.db.progressHold = 2.5
    fire("QUEST_ADD_KILL_SII", "Mindless Zombie slain: 6/8")
    T.eq(waits[#waits], 2.5)
    C_Timer.After = after
    done()
end)
