-- A fake loot roll world: the game's roll API, its Loot History, the chat lines it
-- prints (enUS GlobalStrings, word for word) and the roll popups as
-- GroupLootFrame.xml/.lua make and place them (Blizzard_UIPanels_Game/Mainline,
-- forever branch). Only what the game does; a test drives it with Drop, Pick,
-- Roll, Win, AllPass and CancelAll.
local stub = require("stub")

local RW = {}

-- Enum.EncounterLootDropRollState (LootHistoryDocumentation).
local STATE = { NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5 }
local PICK_STATE = { need = 0, offspec = 1, transmog = 2, greed = 3, pass = 5, disenchant = 3 }
-- RollOnLoot's numbers (GroupLootFrame.xml button ids).
local ROLL_KIND = { [0] = "pass", [1] = "need", [2] = "greed", [3] = "disenchant", [4] = "transmog" }

local STRINGS = {
    LOOT_ROLL_ALL_PASSED = "|HlootHistory:%d|h[Loot]|h: Everyone passed on: %s",
    LOOT_ROLL_DISENCHANT = "%s has selected Disenchant for: %s",
    LOOT_ROLL_DISENCHANT_SELF = "|HlootHistory:%d|h[Loot]|h: You have selected Disenchant for: %s",
    LOOT_ROLL_GREED = "|HlootHistory:%d|h[Loot]|h: %s has selected Greed for: %s",
    LOOT_ROLL_GREED_SELF = "|HlootHistory:%d|h[Loot]|h: You have selected Greed for: %s",
    LOOT_ROLL_INELIGIBLE_REASON1 = "Your class may not roll need on this item.",
    LOOT_ROLL_INELIGIBLE_REASON2 = "You already have the maximum amount of this item.",
    LOOT_ROLL_INELIGIBLE_REASON3 = "This item may not be disenchanted.",
    LOOT_ROLL_INELIGIBLE_REASON4 = "You do not have an Enchanter of skill %d in your group.",
    LOOT_ROLL_INELIGIBLE_REASON5 = "Need rolls are disabled for this item.",
    LOOT_ROLL_INELIGIBLE_REASON6 = "You already have a powerful version of this item.",
    LOOT_ROLL_INELIGIBLE_REASON7 = "You do not have the profession required to use this item.",
    LOOT_ROLL_LOST_ROLL = "|HlootHistory:%d|h[Loot]|h: You have rolled %s - %d for: %s",
    LOOT_ROLL_NEED = "|HlootHistory:%d|h[Loot]|h: %s has selected Need for: %s",
    LOOT_ROLL_NEED_SELF = "|HlootHistory:%d|h[Loot]|h: You have selected Need for: %s",
    LOOT_ROLL_NEED_SELF_OFF_SPEC = "|HlootHistory:%d|h[Loot]|h: You have selected Need for: %s",
    LOOT_ROLL_PASSED = "|HlootHistory:%d|h[Loot]|h: %s passed on: %s",
    LOOT_ROLL_PASSED_AUTO = "%s automatically passed on: %s because he cannot loot that item.",
    LOOT_ROLL_PASSED_AUTO_FEMALE = "%s automatically passed on: %s because she cannot loot that item.",
    LOOT_ROLL_PASSED_SELF = "|HlootHistory:%d|h[Loot]|h: You passed on: %s",
    LOOT_ROLL_PASSED_SELF_AUTO = "|HlootHistory:%d|h[Loot]|h: You automatically passed on: %s because you cannot loot that item.",
    LOOT_ROLL_ROLLED_DE = "Disenchant Roll - %d for %s by %s",
    LOOT_ROLL_ROLLED_GREED = "|HlootHistory:%d|h[Loot]|h: Greed Roll - %d for %s by %s",
    LOOT_ROLL_ROLLED_NEED = "|HlootHistory:%d|h[Loot]|h: Need Roll - %d for %s by %s",
    LOOT_ROLL_ROLLED_NEED_ROLE_BONUS = "Need Roll - %d for %s by %s + Role Bonus",
    LOOT_ROLL_ROLLED_TRANSMOG = "|HlootHistory:%d|h[Loot]|h: Transmog Roll - %d for %s by %s",
    LOOT_ROLL_STARTED = "|HlootHistory:%d|h[Loot]|h: %s",
    LOOT_ROLL_WON = "|HlootHistory:%d|h[Loot]|h: %s won: %s",
    LOOT_ROLL_WON_NO_SPAM_DE = "|HlootHistory:%d|h[Loot]|h: %s (Disenchant - %d) Won: %s",
    LOOT_ROLL_WON_NO_SPAM_GREED = "|HlootHistory:%d|h[Loot]|h: %s (Greed - %d) Won: %s",
    LOOT_ROLL_WON_NO_SPAM_NEED = "|HlootHistory:%d|h[Loot]|h: %s (Need - %d, Main-Spec) Won: %s",
    LOOT_ROLL_WON_NO_SPAM_NEED_OFF_SPEC = "|HlootHistory:%d|h[Loot]|h: %s (Need - %d, Off-Spec) Won: %s",
    LOOT_ROLL_WON_NO_SPAM_TRANSMOGRIFICATION = "|HlootHistory:%d|h[Loot]|h: %s (Transmogrification - %d) Won: %s",
    LOOT_ROLL_YOU_WON = "|HlootHistory:%d|h[Loot]|h: You won: %s",
    LOOT_ROLL_YOU_WON_NO_SPAM_DE = "|HlootHistory:%d|h[Loot]|h: You (Disenchant - %d) Won: %s",
    LOOT_ROLL_YOU_WON_NO_SPAM_GREED = "|HlootHistory:%d|h[Loot]|h: You (Greed - %d) Won: %s",
    LOOT_ROLL_YOU_WON_NO_SPAM_NEED = "|HlootHistory:%d|h[Loot]|h: You (Need - %d, Main-Spec) Won: %s",
    LOOT_ROLL_YOU_WON_NO_SPAM_NEED_OFF_SPEC = "|HlootHistory:%d|h[Loot]|h: You (Need - %d, Off-Spec) Won: %s",
    LOOT_ROLL_YOU_WON_NO_SPAM_TRANSMOG = "|HlootHistory:%d|h[Loot]|h: You (Transmogrification - %d) Won: %s",
    NEED = "Need", GREED = "Greed", PASS = "Pass", ROLL_DISENCHANT = "Disenchant",
    TRANSMOGRIFICATION = "Transmogrification",
}
RW.STRINGS = STRINGS

local ENCOUNTER = 1

local function chat(text)
    stub.FireEvent("CHAT_MSG_LOOT", text, "", "", "", "", "", 0, 0, "", 0, 0, "")
end

local function now() return GetTime() end

-- The Loot History keeps its own clock in milliseconds (GetLootHistoryTime),
-- not GetTime's. Its startTime and duration are on that clock: the game's own
-- frame takes GetLootHistoryTime() - startTime and compares it with duration.
local HISTORY_BASE = 7300000
local function historyNow() return now() * 1000 + HISTORY_BASE end

-- The drop's Loot History record, the way GetSortedInfoForDrop answers it.
local function historyInfo(d)
    local infos, winner, leader = {}, nil, nil
    for _, p in ipairs(d.players) do
        local info = { playerName = p.name, playerGUID = "Player-1-" .. p.name, playerClass = p.class,
                       isSelf = p.self == true, state = p.state, isWinner = p.won == true, roll = p.roll }
        infos[#infos + 1] = info
        if p.won then winner = info end
        if p.roll and (not leader or p.roll > leader.roll) then leader = info end
    end
    local mine = STATE.NoRoll
    for _, p in ipairs(d.players) do if p.self then mine = p.state end end
    return { lootListKey = d.historyID, itemHyperlink = d.link, playerRollState = mine,
             currentLeader = leader, isTied = false, winner = winner, allPassed = d.allPassed == true,
             rollInfos = infos, startTime = d.start * 1000 + HISTORY_BASE, duration = d.time }
end

local function historyChanged(d)
    if RW.history then stub.FireEvent("LOOT_HISTORY_UPDATE_DROP", ENCOUNTER, d.historyID) end
end

local function player(d, name)
    for _, p in ipairs(d.players) do
        if p.name == name then return p end
    end
    error("rollworld: no player " .. tostring(name) .. " on roll " .. tostring(d.rollID), 3)
end

-- The roll leaves the game's list: it isn't active and its popup goes.
local function close(d)
    d.active = false
    stub.FireEvent("CANCEL_LOOT_ROLL", d.rollID)
    for i = 1, 4 do
        local f = _G["GroupLootFrame" .. i]
        if f and f.rollID == d.rollID and f:IsShown() then _G.GroupLootFrame_Remove(f) end
    end
end

function RW.Install()
    for k, v in pairs(STRINGS) do _G[k] = v end
    Enum.EncounterLootDropRollState = {}
    for k, v in pairs(STATE) do Enum.EncounterLootDropRollState[k] = v end
    RW.drops, RW.order, RW.rolled = {}, {}, {}
    RW.nextRoll, RW.nextHistory, RW.history = 100, 40, true
    -- Rolls only happen in a group.
    stub.SetGroup(true, false, 7)

    _G.GetLootRollItemInfo = function(rollID)
        local d = RW.drops[rollID]
        if not d then return nil end
        return d.icon, d.name, d.count, d.quality, d.bop, d.canNeed, d.canGreed, d.canDisenchant,
            d.reasonNeed or 0, d.reasonGreed or 0, d.reasonDisenchant or 0, d.deSkillRequired or 0, d.canTransmog
    end
    _G.GetLootRollItemLink = function(rollID)
        local d = RW.drops[rollID]
        return d and d.link or nil
    end
    -- Milliseconds left to pick.
    _G.GetLootRollTimeLeft = function(rollID)
        local d = RW.drops[rollID]
        if not d then return 0 end
        return math.max(0, d.time - (now() - d.start) * 1000)
    end
    _G.GetActiveLootRollIDs = function()
        local list = {}
        for _, id in ipairs(RW.order) do
            if RW.drops[id].active then list[#list + 1] = id end
        end
        return list
    end
    _G.C_Loot = _G.C_Loot or {}
    C_Loot.GetLootRollDuration = function(rollID)
        local d = RW.drops[rollID]
        return d and d.time or nil
    end
    -- Your own pick. On an item that binds, the game asks first (CONFIRM_LOOT_ROLL,
    -- its own confirm box) and takes the pick only once you say yes (RW.Confirm).
    -- Then it hides its popup at once (CANCEL_LOOT_ROLL) and, for a Need, shows
    -- your number (MAIN_SPEC_NEED_ROLL); the chat line and history follow.
    local function take(rollID, id)
        local d = RW.drops[rollID]
        if not d or not d.active then return end
        local me
        for _, p in ipairs(d.players) do if p.self then me = p end end
        -- A picked roll is no longer active: a reload doesn't open its popup again.
        close(d)
        if id == 1 then stub.FireEvent("MAIN_SPEC_NEED_ROLL", rollID, d.myNeed or 77, false) end
        if me then RW.Pick(rollID, me.name, ROLL_KIND[id]) end
    end
    _G.RollOnLoot = function(rollID, id)
        RW.rolled[#RW.rolled + 1] = { rollID = rollID, id = id }
        local d = RW.drops[rollID]
        if d and d.active and d.bop and id ~= 0 then
            RW.confirming, RW.confirmID = rollID, id
            stub.FireEvent("CONFIRM_LOOT_ROLL", rollID, id, "")
            return
        end
        take(rollID, id)
    end
    -- Yes in the game's bind box.
    function RW.Confirm(rollID)
        local id = RW.confirmID
        RW.confirming, RW.confirmID = nil, nil
        take(rollID, id)
    end
    _G.C_LootHistory = {
        GetLootHistoryTime = historyNow,
        GetAllEncounterInfos = function()
            if not RW.history or #RW.order == 0 then return {} end
            return { { encounterName = "Trash", encounterID = ENCOUNTER, startTime = 0, duration = 0 } }
        end,
        GetSortedDropsForEncounter = function(encounterID)
            if not RW.history or encounterID ~= ENCOUNTER then return nil end
            local list = {}
            for _, id in ipairs(RW.order) do
                if RW.drops[id].announced then list[#list + 1] = historyInfo(RW.drops[id]) end
            end
            return list
        end,
        GetSortedInfoForDrop = function(encounterID, key)
            if not RW.history or encounterID ~= ENCOUNTER then return nil end
            for _, id in ipairs(RW.order) do
                local d = RW.drops[id]
                if d.historyID == key then return historyInfo(d) end
            end
            return nil
        end,
    }
end

-- The roll popups and their container, as the game's XML makes them, with the
-- container's own functions copied from GroupLootFrame.lua.
function RW.GameFrames()
    local c = CreateFrame("Frame", "GroupLootContainer", UIParent)
    c:SetSize(280, 100)
    c.rollFrames, c.waitingRolls, c.reservedSize, c.maxIndex = {}, {}, 100, 0
    c:Hide()
    -- A managed frame (BottomManagedFrameTemplate, ManagedFrameSystem.lua): shown,
    -- the game's bottom column takes it and places it; hidden, the column lets it
    -- go and clears every point it had, so it has no place on screen.
    c:SetScript("OnShow", function(self)
        self:ClearAllPoints()
        self:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200)
    end)
    c:SetScript("OnHide", function(self) self:ClearAllPoints() end)
    for i = 1, 4 do
        local roll = CreateFrame("Frame", "GroupLootFrame" .. i, UIParent)
        roll:SetSize(277, 67)
        roll.Background = roll:CreateTexture(); roll.Background:SetTexture("gold frame")
        roll.IconFrame = CreateFrame("Button", nil, roll)
        roll.IconFrame:SetSize(34, 34)
        roll.IconFrame.Icon = roll.IconFrame:CreateTexture()
        roll.IconFrame.Border = roll.IconFrame:CreateTexture()
        roll.Name = roll:CreateFontString()
        roll.Timer = CreateFrame("StatusBar", nil, roll)
        roll.Timer:SetMinMaxValues(0, 60000)
        local box = CreateFrame("Frame", nil, roll)
        roll.LootButtonContainer = box
        for _, key in ipairs({ "NeedButton", "GreedButton", "PassButton", "TransmogButton" }) do
            local b = CreateFrame("Button", nil, box)
            b:SetSize(32, 32)
            local art, glow = b:CreateTexture(), b:CreateTexture()
            art:SetTexture("dice"); glow:SetTexture("dice glow")
            function b:GetNormalTexture() return art end
            function b:GetHighlightTexture() return glow end
            box[key] = b
        end
        roll:EnableMouse(true)
        roll:Hide()
    end

    local function gamepad() return _G.InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() end
    local function calcMax(self)
        local m = 0
        for k in pairs(self.rollFrames) do if k > m then m = k end end
        self.maxIndex = m
    end
    _G.GroupLootContainer_Update = function(self)
        if gamepad() then return end
        local last
        for i = 1, self.maxIndex do
            local f = self.rollFrames[i]
            if f then
                f:ClearAllPoints()
                f:SetPoint("CENTER", self, "BOTTOM", 0, self.reservedSize * (i - 1 + 0.5))
                last = i
            end
        end
        if last then self:SetHeight(self.reservedSize * last); self:Show() else self:Hide() end
    end
    _G.GroupLootContainer_AddFrame = function(self, frame)
        local idx = self.maxIndex + 1
        for i = 1, self.maxIndex do
            if not self.rollFrames[i] then idx = i; break end
        end
        self.rollFrames[idx] = frame
        if idx > self.maxIndex then self.maxIndex = idx end
        GroupLootContainer_Update(self)
        frame:Show()
    end
    _G.GroupLootContainer_RemoveFrame = function(self, frame, cancellingAll)
        local idx
        for k, v in pairs(self.rollFrames) do if v == frame then idx = k; break end end
        frame:Hide()
        if idx then
            self.rollFrames[idx] = nil
            if idx == self.maxIndex then calcMax(self) end
            if #self.waitingRolls > 0 and not cancellingAll then
                local w = table.remove(self.waitingRolls, 1)
                GroupLootContainer_AddRoll(w.rollID, w.rollTime)
            end
        end
        GroupLootContainer_Update(self)
    end
    _G.GroupLootContainer_OpenNewFrame = function(rollID, rollTime)
        for i = 1, 4 do
            local f = _G["GroupLootFrame" .. i]
            if not f:IsShown() then
                f.rollID, f.rollTime = rollID, rollTime
                f.Timer:SetMinMaxValues(0, rollTime)
                GroupLootContainer_AddFrame(GroupLootContainer, f)
                return true
            end
        end
        return false
    end
    _G.GroupLootContainer_AddRoll = function(rollID, rollTime)
        if not GroupLootContainer_OpenNewFrame(rollID, rollTime) then
            table.insert(GroupLootContainer.waitingRolls, { rollID = rollID, rollTime = rollTime })
        end
    end
    _G.GroupLootFrame_Remove = function(self, cancellingAll)
        if self:IsShown() then GroupLootContainer_RemoveFrame(GroupLootContainer, self, cancellingAll) end
    end
    return c
end

-- A new roll: the client opens a popup for it (unless the controller UI is on),
-- fires START_LOOT_ROLL, prints the started line and records the drop in history.
function RW.Drop(spec)
    local rollID = RW.nextRoll; RW.nextRoll = RW.nextRoll + 1
    local historyID = RW.nextHistory; RW.nextHistory = RW.nextHistory + 1
    local d = {
        rollID = rollID, historyID = historyID, name = spec.name or "Band of Accuria",
        link = spec.link or ("|cffa335ee|Hitem:17063|h[" .. (spec.name or "Band of Accuria") .. "]|h|r"),
        icon = spec.icon or 133345, quality = spec.quality or 4, bop = spec.bop == true, count = spec.count or 1,
        canNeed = spec.canNeed ~= false, canGreed = spec.canGreed ~= false,
        canDisenchant = spec.canDisenchant == true, canTransmog = spec.canTransmog == true,
        reasonNeed = spec.reasonNeed, reasonGreed = spec.reasonGreed, reasonDisenchant = spec.reasonDisenchant,
        time = spec.time or 60000, start = now(), active = true, myNeed = spec.myNeed, players = {},
    }
    for _, p in ipairs(spec.players or {}) do
        d.players[#d.players + 1] = { name = p.name, class = p.class, self = p.self == true, state = STATE.NoRoll }
    end
    RW.drops[rollID] = d
    RW.order[#RW.order + 1] = rollID
    if not (_G.InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled())
        and _G.GroupLootContainer_AddRoll then
        GroupLootContainer_AddRoll(rollID, d.time)
    end
    stub.FireEvent("START_LOOT_ROLL", rollID, d.time)
    if spec.announce ~= false then RW.Announce(rollID) end
    return rollID, historyID
end

-- The started line and the history record. Two copies dropping together get
-- both START_LOOT_ROLLs first; nothing ties a roll id to its history key, so a
-- test can announce them in the other order (spec.announce = false, then this).
function RW.Announce(rollID)
    local d = RW.drops[rollID]
    d.announced = true
    chat(STRINGS.LOOT_ROLL_STARTED:format(d.historyID, d.link))
    historyChanged(d)
end

-- A player picks: kind need|offspec|greed|pass|disenchant|transmog|auto (an
-- automatic pass). Their chat line and their history state; no number yet.
function RW.Pick(rollID, name, kind)
    local d = RW.drops[rollID]
    local p = player(d, name)
    p.pick = kind == "auto" and "pass" or kind
    p.state = PICK_STATE[p.pick] or STATE.Pass
    local id, link = d.historyID, d.link
    local text
    if p.self then
        if kind == "need" then text = STRINGS.LOOT_ROLL_NEED_SELF:format(id, link)
        elseif kind == "offspec" then text = STRINGS.LOOT_ROLL_NEED_SELF_OFF_SPEC:format(id, link)
        elseif kind == "greed" then text = STRINGS.LOOT_ROLL_GREED_SELF:format(id, link)
        elseif kind == "disenchant" then text = STRINGS.LOOT_ROLL_DISENCHANT_SELF:format(id, link)
        elseif kind == "pass" then text = STRINGS.LOOT_ROLL_PASSED_SELF:format(id, link)
        elseif kind == "auto" then text = STRINGS.LOOT_ROLL_PASSED_SELF_AUTO:format(id, link) end
    else
        if kind == "need" or kind == "offspec" then text = STRINGS.LOOT_ROLL_NEED:format(id, name, link)
        elseif kind == "greed" then text = STRINGS.LOOT_ROLL_GREED:format(id, name, link)
        elseif kind == "disenchant" then text = STRINGS.LOOT_ROLL_DISENCHANT:format(name, link)
        elseif kind == "pass" then text = STRINGS.LOOT_ROLL_PASSED:format(id, name, link)
        elseif kind == "auto" then text = STRINGS.LOOT_ROLL_PASSED_AUTO:format(name, link) end
    end
    -- Transmog has no "selected" line in the game's strings: history only.
    if text then chat(text) end
    historyChanged(d)
end

-- A player's number lands, on the roll type they picked.
function RW.Roll(rollID, name, number)
    local d = RW.drops[rollID]
    local p = player(d, name)
    p.roll = number
    local id, link = d.historyID, d.link
    local text
    if p.pick == "greed" then text = STRINGS.LOOT_ROLL_ROLLED_GREED:format(id, number, link, name)
    elseif p.pick == "transmog" then text = STRINGS.LOOT_ROLL_ROLLED_TRANSMOG:format(id, number, link, name)
    elseif p.pick == "disenchant" then text = STRINGS.LOOT_ROLL_ROLLED_DE:format(number, link, name)
    else text = STRINGS.LOOT_ROLL_ROLLED_NEED:format(id, number, link, name) end
    chat(text)
    historyChanged(d)
end

-- The game names the winner; the roll leaves the active list.
function RW.Win(rollID, name)
    local d = RW.drops[rollID]
    local p = player(d, name)
    p.won = true
    if p.self then chat(STRINGS.LOOT_ROLL_YOU_WON:format(d.historyID, d.link))
    else chat(STRINGS.LOOT_ROLL_WON:format(d.historyID, name, d.link)) end
    historyChanged(d)
    if d.active then close(d) end
end

function RW.AllPass(rollID)
    local d = RW.drops[rollID]
    d.allPassed = true
    chat(STRINGS.LOOT_ROLL_ALL_PASSED:format(d.historyID, d.link))
    historyChanged(d)
    if d.active then close(d) end
end

-- Leaving the group or zoning out of the loot's reach: every roll ends at once.
function RW.CancelAll()
    for _, id in ipairs(RW.order) do RW.drops[id].active = false end
    stub.FireEvent("CANCEL_ALL_LOOT_ROLLS")
    for i = 1, 4 do
        local f = _G["GroupLootFrame" .. i]
        if f and f:IsShown() then _G.GroupLootFrame_Remove(f, true) end
    end
end

-- You leave the group with rolls up. What the server sends then isn't in the
-- game's docs or UI code, so this is the worst case: only GROUP_LEFT, while the
-- client keeps listing the rolls until their time runs out and the Loot History
-- keeps their records, with no winner ever coming.
function RW.LeaveGroup()
    stub.SetGroup(false)
    stub.FireEvent("GROUP_LEFT", 1, "Party-1")
end

-- off = the world where C_LootHistory answers nothing (chat only).
function RW.UseHistory(on) RW.history = on ~= false end

return RW
