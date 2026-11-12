-- Auto accept and turn in quests. Only the quest dialog is touched, never the tracker.
-- Shift, combat and quests that cost money leave the NPC alone.

local _, ns = ...

local Quests = {}
ns.Quests = Quests
ns.features[#ns.features + 1] = Quests

local mod, registered

local function isFn(f) return type(f) == "function" end

local function paused()
    if isFn(IsShiftKeyDown) and IsShiftKeyDown() then return true end
    if isFn(InCombatLockdown) and InCombatLockdown() then return true end
    return false
end

local function wants(key)
    return mod and mod.db and mod.db[key] == true and not paused()
end

-- Tells our NPC window this page was answered, so it never flashes up.
local function answered(event)
    if type(DaylightUI.TalkAnswered) == "function" then DaylightUI.TalkAnswered(event) end
end

local function costsMoney()
    if not isFn(GetQuestMoneyToGet) then return false end
    local m = GetQuestMoneyToGet()
    return type(m) == "number" and m > 0
end

-- A PvP quest is left to you (the game asks first); one that accepted
-- itself is acknowledged, as the game's own window does (QuestFrame.lua:636).
function Quests.OnDetail()
    if not wants("questAccept") or not isFn(AcceptQuest) then return end
    if isFn(QuestFlagsPVP) and QuestFlagsPVP() then return end
    answered("QUEST_DETAIL")
    if isFn(QuestGetAutoAccept) and QuestGetAutoAccept() and isFn(AcknowledgeAutoAcceptQuest) then
        AcknowledgeAutoAcceptQuest()
    else
        AcceptQuest()
    end
end

function Quests.OnProgress()
    if not wants("questTurnIn") or costsMoney() then return end
    if isFn(IsQuestCompletable) and IsQuestCompletable() and isFn(CompleteQuest) then
        answered("QUEST_PROGRESS")
        CompleteQuest()
    end
end

function Quests.OnComplete()
    if not wants("questTurnIn") or costsMoney() then return end
    if not isFn(GetNumQuestChoices) or not isFn(GetQuestReward) then return end
    local n = GetNumQuestChoices()
    -- A blank offer may just not have its choices yet: GetQuestReward(0) would fail
    -- and close the talk. A quest the log can't vouch for stays for the player.
    local D = DaylightUI.Npc and DaylightUI.Npc.Data
    local id = isFn(GetQuestID) and GetQuestID()
    if n == 0 and D and D.InLog(id) and D.LogChoices(id) ~= 0 then return end
    if type(n) == "number" and n <= 1 then
        answered("QUEST_COMPLETE")
        GetQuestReward(n)
    end
end

function Quests.OnGreeting()
    if wants("questTurnIn") and isFn(GetNumActiveQuests) and isFn(GetActiveTitle) and isFn(SelectActiveQuest) then
        for i = 1, GetNumActiveQuests() do
            local _, complete = GetActiveTitle(i)
            if complete then answered("QUEST_GREETING"); SelectActiveQuest(i); return end
        end
    end
    if wants("questAccept") and isFn(GetNumAvailableQuests) and isFn(SelectAvailableQuest)
        and GetNumAvailableQuests() > 0 then
        answered("QUEST_GREETING")
        SelectAvailableQuest(1)
    end
end

-- Two lists of functions that select a finished quest / an available quest.
local function gossipChoices()
    local active, available = {}, {}
    local C = C_GossipInfo
    if type(C) == "table" and isFn(C.GetActiveQuests) and isFn(C.GetAvailableQuests) then
        for _, q in ipairs(C.GetActiveQuests() or {}) do
            if q.isComplete and isFn(C.SelectActiveQuest) then
                active[#active + 1] = function() C.SelectActiveQuest(q.questID) end
            end
        end
        for _, q in ipairs(C.GetAvailableQuests() or {}) do
            if isFn(C.SelectAvailableQuest) then
                available[#available + 1] = function() C.SelectAvailableQuest(q.questID) end
            end
        end
    else
        if isFn(GetGossipActiveQuests) and isFn(SelectGossipActiveQuest) then
            local t, step = { GetGossipActiveQuests() }, 6
            for i = 1, #t, step do
                local index = (i - 1) / step + 1
                if t[i + 3] then active[#active + 1] = function() SelectGossipActiveQuest(index) end end
            end
        end
        if isFn(GetGossipAvailableQuests) and isFn(SelectGossipAvailableQuest) then
            local t, step = { GetGossipAvailableQuests() }, 7
            for i = 1, #t, step do
                local index = (i - 1) / step + 1
                available[#available + 1] = function() SelectGossipAvailableQuest(index) end
            end
        end
    end
    return active, available
end

function Quests.OnGossip()
    local turnIn, accept = wants("questTurnIn"), wants("questAccept")
    if not (turnIn or accept) then return end
    local active, available = gossipChoices()
    if turnIn and active[1] then answered("GOSSIP_SHOW"); active[1](); return end
    if accept and available[1] then answered("GOSSIP_SHOW"); available[1]() end
end

function Quests.Enable(m)
    mod = m
    if registered then return end
    registered = true
    DaylightUI.RegisterEvent("QUEST_DETAIL", Quests.OnDetail)
    DaylightUI.RegisterEvent("QUEST_PROGRESS", Quests.OnProgress)
    DaylightUI.RegisterEvent("QUEST_COMPLETE", Quests.OnComplete)
    DaylightUI.RegisterEvent("QUEST_GREETING", Quests.OnGreeting)
    DaylightUI.RegisterEvent("GOSSIP_SHOW", Quests.OnGossip)
end

function Quests.Refresh(m) mod = m end
