-- The fake game's Legacy window for the Legacy window's tests, as Forever has it:
--   * Blizzard_LegacySystem loads on demand. The bootstrap's ToggleLegacySystemUI()
--     (only past renown 0) loads it the first time (LegacySystemFrame made,
--     ADDON_LOADED), then calls ToggleFrame. The page it opens on is the frame's
--     currentPage, set before it shows (SelectPage, EventRegistry
--     "Legacy.SelectPage"). ToggleLegacyChallenges() and ShowLegacyChallenge(id)
--     open it on Challenges.
--   * Points: the Legacy faction's renown (C_MajorFactions) and the trees'
--     currency (C_Traits.GetTreeCurrencyInfo, shared by the three trees).
--   * Challenges: achievement categories with done ones first in each
--     (GetAchievementInfo by category and index), criteria, the client's search
--     (SetAchievementSearchString answers a frame later with
--     ACHIEVEMENT_SEARCH_UPDATED), tracking (C_ContentTracking), and unviewed
--     ones (LegacyChallengeViewedUtil, from the tracker addon).
--   * Trees: three trait trees, each its own config, on a 400 grid (the real
--     step is unconfirmed), staged like the game (PurchaseRank, RefundRank,
--     SetSelection, RollbackConfig, ResetTree), with CommitConfig answering later
--     with TRAIT_CONFIG_UPDATED (LW.COMMIT_DELAY).
--
-- LW.world(spec) is stub.Load's "before". A test then plays LW.Toggle(),
-- LW.Challenges(), LW.Show(id), LW.Close(), LW.Earn(n), LW.Complete(id), and
-- reads LW.Calls(kind).

local stub = require("stub")

local LW = {}

local function S() return LW.state end
local function record(kind, ...) table.insert(S().calls, { kind = kind, args = { ... } }) end
function LW.Calls(kind)
    local out = {}
    for _, c in ipairs(S().calls) do if c.kind == kind then out[#out + 1] = c.args end end
    return out
end

local function asGame(fn, ...)
    stub.inSecure = (stub.inSecure or 0) + 1
    local ok, err = pcall(fn, ...)
    stub.inSecure = stub.inSecure - 1
    if not ok then error(err, 2) end
end

LW.FACTION, LW.CURRENCY, LW.POINTS_CURRENCY = 2701, 9001, 9002
LW.PROF, LW.ADV, LW.PROG = 71, 72, 73
LW.COMMIT_DELAY = 0.5
LW.CONFIG = function(treeID) return treeID + 1000 end

-- ---------------------------------------------------------------------
-- Samples
-- ---------------------------------------------------------------------

function LW.Levels()
    return {
        { level = 15, rewards = { { itemID = 501, name = "Holstered Replica Ironforge Air Rifle", icon = 1001, description = "A replica.", rewardType = 1 } } },
        { level = 25, rewards = { { itemID = 502, name = "Spectral Bear Cub", icon = 1002, description = "A ghostly cub.", rewardType = 1 } } },
        { level = 40, rewards = { { itemID = 503, name = "Spectral Bear Tabard", icon = 1003, description = "Show your Legacy.", rewardType = 1 } } },
        { level = 55, rewards = { { mountID = 77, name = "Reins of the Spectral Bear", icon = 1004, description = "A Spectral Bear.", rewardType = 2 } } },
    }
end

-- Categories: { id, name, parent }, achievements: { id, cat, name, points
-- (Legacy Points), done, mine (earned by this character), desc, steps = {
-- { text, done, have, need } } }.
function LW.Categories()
    return { { id = 10, name = "Classes", parent = -1 }, { id = 11, name = "Mage", parent = 10 }, { id = 12, name = "Warrior", parent = 10 },
        { id = 20, name = "Exploration", parent = -1 }, { id = 30, name = "Dungeons", parent = -1 } }
end

function LW.Achievements()
    return {
        { id = 1101, cat = 11, name = "Arcane Initiate", points = 2, done = true, mine = true, desc = "Cast Arcane Missiles 50 times.", steps = { { text = "Cast it 50 times", done = true, have = 50, need = 50 } } },
        { id = 1102, cat = 11, name = "Portal Master", points = 3, desc = "Learn every portal to your faction's capitals.", steps = { { text = "Stormwind", done = true }, { text = "Ironforge", done = true }, { text = "Darnassus" } } },
        { id = 1103, cat = 11, name = "Ice Is Nice", points = 2, done = true, mine = false, desc = "Freeze 10 enemies at once." },
        { id = 1201, cat = 12, name = "Shield Wall", points = 2, desc = "Block 1,000 attacks.", steps = { { text = "", have = 412, need = 1000 } } },
        { id = 2001, cat = 20, name = "Explore Elwynn Forest", points = 1, done = true, mine = true, desc = "Explore Elwynn Forest.", steps = { { text = "Northshire", done = true }, { text = "Goldshire", done = true } } },
        { id = 2002, cat = 20, name = "Explore Tanaris", points = 2, desc = "Explore Tanaris.", steps = { { text = "Gadgetzan", done = true }, { text = "Lost Rigger Cove" } } },
        { id = 3001, cat = 30, name = "The Deadmines", points = 2, desc = "Defeat Edwin VanCleef." },
    }
end

-- Trees: nodes { id, x, y, max, rank (bought), applied, edges = { to }, choices = { entryIDs } }.
function LW.Trees()
    return {
        [LW.PROF] = { nodes = {
            { id = 7101, x = 1000, y = 1000, max = 3, rank = 2, applied = 2, edges = { 7103 } },
            { id = 7102, x = 1800, y = 1000, max = 2 },
            { id = 7103, x = 1000, y = 1400, max = 1, edges = { 7105 } },
            { id = 7104, x = 1800, y = 1400, max = 3 },
            { id = 7105, x = 1400, y = 1800, max = 1, edges = { 7106 } },
            { id = 7106, x = 1400, y = 2200, max = 1, choices = { 71061, 71062 } },
        } },
        [LW.ADV] = { nodes = {
            { id = 7201, x = 1400, y = 1000, max = 3, rank = 1, applied = 1, edges = { 7202 } },
            { id = 7202, x = 1000, y = 1400, max = 2 },
            { id = 7203, x = 1800, y = 1400, max = 1 },
        } },
        [LW.PROG] = { nodes = {
            { id = 7301, x = 1400, y = 1000, max = 5 },
            { id = 7302, x = 1400, y = 1400, max = 1 },
        } },
    }
end

-- ---------------------------------------------------------------------
-- The game's frame and its toggles (Blizzard_LegacySystem)
-- ---------------------------------------------------------------------

local function frame() return _G.LegacySystemFrame end

-- The addon loads its frame at page 1 (OnLoad's SelectPage(1)).
local function load()
    if frame() then return frame() end
    record("LoadLegacy")
    local f = CreateFrame("Frame", "LegacySystemFrame", UIParent)
    f:Hide()
    f:SetSize(920, 575)
    f.currentPage = 1
    function f:SelectPage(id)
        self.currentPage = id
    end
    stub.FireEvent("ADDON_LOADED", "Blizzard_LegacySystem")
    return f
end
LW.Load = load

local function selectPage(id)
    local f = frame()
    f:SelectPage(id)
    EventRegistry:TriggerEvent("Legacy.SelectPage", id)
end

-- The micro button (ToggleLegacySystemUI) calls ToggleFrame.
function LW.Toggle()
    asGame(function()
        if C_MajorFactions.GetCurrentRenownLevel(LW.FACTION) <= 0 then return end
        local f = load()
        if f:IsShown() then f:Hide() else f:Show() end
    end)
end

-- The achievement key (ToggleLegacyChallenges) closes it when on Challenges, else goes there.
function LW.Challenges()
    asGame(function()
        local f = load()
        if f:IsShown() and f.currentPage == 2 then HideUIPanel(f) return end
        ShowUIPanel(f)
        selectPage(2)
    end)
end

-- A tracked challenge's click (ShowLegacyChallenge).
function LW.Show(id)
    asGame(function() _G.ShowLegacyChallenge(id) end)
end

function LW.Close() asGame(function() HideUIPanel(frame()) end) end

-- ---------------------------------------------------------------------
-- The world's changes, as a test plays them
-- ---------------------------------------------------------------------

-- n more Legacy Points earned (renown, and points to spend).
function LW.Earn(n)
    S().earned = S().earned + n
    S().left = S().left + n
    stub.FireEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", LW.FACTION, S().earned, S().earned - n)
    stub.FireEvent("TRAIT_TREE_CURRENCY_INFO_UPDATED", LW.PROF)
end

-- A challenge earned, unviewed until its category is opened.
function LW.Complete(id)
    for _, a in ipairs(S().achievements) do
        if a.id == id then a.done, a.mine = true, true end
    end
    LegacyChallengesUnviewed[id] = LW.Ach(id).cat
    stub.FireEvent("ACHIEVEMENT_EARNED", id)
    EventRegistry:TriggerEvent("Legacy.UnviewedChallengesUpdated")
end

function LW.Ach(id)
    for _, a in ipairs(S().achievements) do if a.id == id then return a end end
end

function LW.Node(id)
    for treeID, t in pairs(S().trees) do
        for _, n in ipairs(t.nodes) do if n.id == id then return n, treeID end end
    end
end

-- ---------------------------------------------------------------------
-- The game's functions
-- ---------------------------------------------------------------------

local function registry()
    if type(_G.EventRegistry) == "table" and _G.EventRegistry.TriggerEvent then return end
    local cbs = {}
    _G.EventRegistry = {
        RegisterCallback = function(_, e, fn, owner)
            cbs[e] = cbs[e] or {}
            cbs[e][#cbs[e] + 1] = { fn, owner }
        end,
        UnregisterCallback = function(_, e, owner)
            for i = #(cbs[e] or {}), 1, -1 do if cbs[e][i][2] == owner then table.remove(cbs[e], i) end end
        end,
        TriggerEvent = function(_, e, ...)
            for _, c in ipairs(cbs[e] or {}) do c[1](c[2], ...) end
        end,
    }
end

-- Achievements of a category in the client's order: done ones first.
local function inCategory(cat)
    local done, todo = {}, {}
    for _, a in ipairs(S().achievements) do
        if a.cat == cat then if a.done then done[#done + 1] = a else todo[#todo + 1] = a end end
    end
    local out = {}
    for _, a in ipairs(done) do out[#out + 1] = a end
    for _, a in ipairs(todo) do out[#out + 1] = a end
    return out, #done, #todo
end

local function install_achievements()
    _G.GetCategoryList = function()
        local out = {}
        for _, c in ipairs(S().categories) do out[#out + 1] = c.id end
        return out
    end
    _G.GetCategoryInfo = function(id)
        for _, c in ipairs(S().categories) do if c.id == id then return c.name, c.parent, 0 end end
    end
    _G.GetCategoryNumAchievements = function(cat)
        local all, done, todo = inCategory(cat)
        return #all, done, todo
    end
    _G.GetAchievementInfo = function(cat, i)
        local a
        if i then a = inCategory(cat)[i] else a = LW.Ach(cat) end
        if not a then return nil end
        return a.id, a.name, 10, a.done == true, a.done and 10 or nil, a.done and 12 or nil, a.done and 26 or nil,
            a.desc, 0, 3000 + a.id % 100, "", false, a.mine == true
    end
    _G.GetAchievementCategory = function(id) local a = LW.Ach(id); return a and a.cat end
    _G.GetAchievementNumCriteria = function(id) local a = LW.Ach(id); return a and #(a.steps or {}) or 0 end
    _G.GetAchievementCriteriaInfo = function(id, i)
        local st = LW.Ach(id).steps[i]
        return st.text, 0, st.done == true, st.have or 0, st.need or 0, nil, st.need and 1 or 0
    end
    _G.EVALUATION_TREE_FLAG_PROGRESS_BAR = 1
    _G.GetAchievementLink = function(id) return "|Hachievement:" .. id .. "|h[" .. LW.Ach(id).name .. "]|h" end
    -- The client's search gives the matching ids a frame later.
    _G.SetAchievementSearchString = function(text)
        record("Search", text)
        S().search = string.lower(text or "")
        S().filtered = nil
        C_Timer.After(0, function()
            S().filtered = {}
            for _, a in ipairs(S().achievements) do
                if S().search == "" or string.find(string.lower(a.name), S().search, 1, true) then S().filtered[#S().filtered + 1] = a.id end
            end
            stub.FireEvent("ACHIEVEMENT_SEARCH_UPDATED")
        end)
    end
    _G.GetNumFilteredAchievements = function() return S().filtered and #S().filtered or 0 end
    _G.GetFilteredAchievementID = function(i) return S().filtered and S().filtered[i] end
    _G.LegacyChallengesUnviewed = S().unviewed
    _G.LegacyChallengeViewedUtil = {
        CategoryHasUnviewedChallenges = function(cat)
            for _, c in pairs(LegacyChallengesUnviewed) do if c == cat then return true end end
            return false
        end,
        HasAnyUnviewedChallenges = function() return next(LegacyChallengesUnviewed) ~= nil end,
        MarkCategoryViewed = function(cat)
            local changed = false
            for id, c in pairs(LegacyChallengesUnviewed) do if c == cat then LegacyChallengesUnviewed[id] = nil; changed = true end end
            if changed then EventRegistry:TriggerEvent("Legacy.UnviewedChallengesUpdated") end
        end,
    }
    _G.Enum = _G.Enum or {}
    Enum.ContentTrackingType = Enum.ContentTrackingType or { Appearance = 0, Mount = 1, Achievement = 2 }
    Enum.ContentTrackingStopType = Enum.ContentTrackingStopType or { Invalidated = 0, Collected = 1, Manual = 2 }
    _G.C_ContentTracking = setmetatable({
        IsTracking = function(_, id) return S().tracked[id] == true end,
        -- The client's answer: some challenges can't be tracked (S().untrackable).
        IsTrackable = function(_, id) return not (S().untrackable and S().untrackable[id]) end,
        StartTracking = function(_, id) record("StartTracking", id); S().tracked[id] = true; stub.FireEvent("CONTENT_TRACKING_UPDATE", 2, id, true) end,
        StopTracking = function(_, id) record("StopTracking", id); S().tracked[id] = nil; stub.FireEvent("CONTENT_TRACKING_UPDATE", 2, id, false) end,
        GetTrackedIDs = function()
            local out = {}
            for id in pairs(S().tracked) do out[#out + 1] = id end
            return out
        end,
    }, { __index = _G.C_ContentTracking })
end

-- ---------------------------------------------------------------------
-- The trees: C_Traits for the Legacy configs. Any other config goes to the C_Traits
-- that was there before (a book world's).
-- ---------------------------------------------------------------------

local function treeOfConfig(configID)
    for treeID in pairs(S().trees) do if LW.CONFIG(treeID) == configID then return treeID end end
end

local function spentIn(treeID)
    local n = 0
    for _, node in ipairs(S().trees[treeID].nodes) do n = n + (node.rank or 0) end
    return n
end

local function edgesMet(treeID, node)
    for _, src in ipairs(S().trees[treeID].nodes) do
        for _, to in ipairs(src.edges or {}) do
            if to == node.id and (src.rank or 0) < src.max then return false end
        end
    end
    return true
end

local function staged(treeID)
    for _, node in ipairs(S().trees[treeID].nodes) do if (node.rank or 0) ~= (node.applied or 0) or node.picked ~= node.pickedApplied then return true end end
    return false
end

local function nodeInfo(treeID, node)
    local rank, applied = node.rank or 0, node.applied or 0
    local edges = {}
    for _, to in ipairs(node.edges or {}) do edges[#edges + 1] = { targetNode = to, type = 2, visualStyle = 1, isActive = rank >= node.max } end
    local entry
    if node.choices then entry = node.picked else entry = node.id * 10 end
    return {
        ID = node.id, posX = node.x, posY = node.y, type = node.choices and 2 or 0, flags = 0,
        ranksPurchased = rank, activeRank = applied, currentRank = rank, maxRanks = node.max,
        canPurchaseRank = edgesMet(treeID, node) and rank < node.max and S().left > 0,
        canRefundRank = rank > applied, isAvailable = true, isVisible = true, meetsEdgeRequirements = edgesMet(treeID, node),
        groupIDs = {}, conditionIDs = {}, entryIDs = node.choices or { node.id * 10 },
        activeEntry = entry and { entryID = entry, rank = rank } or nil, visibleEdges = edges,
    }
end

local function changed(treeID, node)
    if node then stub.FireEvent("TRAIT_NODE_CHANGED", node.id) end
    stub.FireEvent("TRAIT_TREE_CURRENCY_INFO_UPDATED", treeID)
end

local function install_traits()
    local before = _G.C_Traits or {}
    local function mine(configID) return treeOfConfig(configID) ~= nil end
    local T = {}
    T.GetConfigIDByTreeID = function(treeID) return S().trees[treeID] and LW.CONFIG(treeID) or nil end
    T.GetConfigInfo = function(id)
        local treeID = treeOfConfig(id)
        if not treeID then return before.GetConfigInfo and before.GetConfigInfo(id) end
        return { ID = id, name = "Legacy", treeIDs = { treeID }, type = 1 }
    end
    T.GetTreeNodes = function(treeID)
        if not S().trees[treeID] then return before.GetTreeNodes and before.GetTreeNodes(treeID) or {} end
        local out = {}
        for _, n in ipairs(S().trees[treeID].nodes) do out[#out + 1] = n.id end
        return out
    end
    T.GetNodeInfo = function(configID, nodeID)
        if not mine(configID) then return before.GetNodeInfo and before.GetNodeInfo(configID, nodeID) end
        local node, treeID = LW.Node(nodeID)
        return nodeInfo(treeID, node)
    end
    T.GetEntryInfo = function(configID, entryID)
        if not mine(configID) then return before.GetEntryInfo and before.GetEntryInfo(configID, entryID) end
        return { definitionID = entryID + 500000, type = 1, maxRanks = 1, isAvailable = true }
    end
    T.GetDefinitionInfo = function(defID)
        if defID < 500000 then return before.GetDefinitionInfo and before.GetDefinitionInfo(defID) end
        return { spellID = defID - 500000 + 800000 }
    end
    T.GetGroupDisplayInfoByTreeID = function(treeID)
        if S().trees[treeID] then return {} end
        return before.GetGroupDisplayInfoByTreeID and before.GetGroupDisplayInfoByTreeID(treeID) or {}
    end
    T.GetTreeCurrencyInfo = function(configID, treeID, ...)
        if not mine(configID) then return before.GetTreeCurrencyInfo and before.GetTreeCurrencyInfo(configID, treeID, ...) or {} end
        -- The currency is shared: spent is every tree's points together, and spentInTree
        -- is this tree's (the game's Blizzard_LegacyTree shows spentInTree).
        local all = 0
        for id in pairs(S().trees) do all = all + spentIn(id) end
        return { { traitCurrencyID = LW.CURRENCY, quantity = S().left, maxQuantity = 40, spent = all, spentInTree = spentIn(treeID) } }
    end
    T.GetMaxAvailableTraitCurrency = function(id) return id == LW.CURRENCY and 140 or 0 end
    T.GetTraitCurrencyForAchievement = function(_, id) local a = LW.Ach(id); return a and a.points or 0 end
    T.GetNodeCost = function(configID, ...)
        if not mine(configID) then return before.GetNodeCost and before.GetNodeCost(configID, ...) end
        return { { ID = LW.CURRENCY, amount = 1 } }
    end
    T.GetConditionInfo = before.GetConditionInfo
    T.GetTraitDescription = function(entryID, rank)
        if entryID >= 70000 then return string.format("Legacy perk %d, rank %d: %d%% faster.", entryID, rank, rank * 5) end
        return before.GetTraitDescription and before.GetTraitDescription(entryID, rank) or ""
    end
    T.PurchaseRank = function(configID, nodeID)
        if not mine(configID) then return before.PurchaseRank(configID, nodeID) end
        record("PurchaseRank", configID, nodeID)
        local node, treeID = LW.Node(nodeID)
        if S().committing or node.choices or not nodeInfo(treeID, node).canPurchaseRank then return false end
        node.rank = (node.rank or 0) + 1
        S().left = S().left - 1
        changed(treeID, node)
        return true
    end
    T.SetSelection = function(configID, nodeID, entryID)
        record("SetSelection", configID, nodeID, entryID)
        local node, treeID = LW.Node(nodeID)
        if S().committing or not node.choices then return false end
        if entryID then
            if (node.rank or 0) > 0 or S().left < 1 then return false end
            node.picked, node.rank = entryID, 1
            S().left = S().left - 1
        else
            if (node.rank or 0) <= (node.applied or 0) then return false end
            node.picked, node.rank = nil, 0
            S().left = S().left + 1
        end
        changed(treeID, node)
        return true
    end
    T.RefundRank = function(configID, nodeID, ...)
        if not mine(configID) then return before.RefundRank(configID, nodeID, ...) end
        record("RefundRank", configID, nodeID)
        local node, treeID = LW.Node(nodeID)
        if S().committing or (node.rank or 0) <= (node.applied or 0) then return false end
        node.rank = node.rank - 1
        S().left = S().left + 1
        changed(treeID, node)
        return true
    end
    T.RollbackConfig = function(configID)
        if not mine(configID) then return before.RollbackConfig(configID) end
        record("RollbackConfig", configID)
        local treeID = treeOfConfig(configID)
        for _, node in ipairs(S().trees[treeID].nodes) do
            S().left = S().left + (node.rank or 0) - (node.applied or 0)
            node.rank, node.picked = node.applied or 0, node.pickedApplied
        end
        changed(treeID)
        return true
    end
    -- The game's TraitTreeInfo (SharedTraitsDocumentation): cannotRefund is the tree's
    -- CannotRefund flag, and the game's Legacy window hides its Reset button on it
    -- (LegacyTreeTraitPanelMixin:UpdateConfigButtonsState).
    T.GetTreeInfo = function(configID, treeID)
        if not mine(configID) then return before.GetTreeInfo and before.GetTreeInfo(configID, treeID) end
        return { ID = treeID, gates = {}, hideSingleRankNumbers = false, cannotRefund = S().cannotRefund == true, uiTextureKit = "" }
    end
    T.ResetTree = function(configID, treeID)
        record("ResetTree", configID, treeID)
        for _, node in ipairs(S().trees[treeID].nodes) do
            S().left = S().left + (node.rank or 0)
            node.rank, node.picked = 0, nil
        end
        changed(treeID)
        return true
    end
    T.ConfigHasStagedChanges = function(configID)
        if not mine(configID) then return before.ConfigHasStagedChanges and before.ConfigHasStagedChanges(configID) end
        return staged(treeOfConfig(configID))
    end
    T.GetStagedChanges = function(configID)
        if not mine(configID) then return before.GetStagedChanges(configID) end
        local buys = {}
        for _, node in ipairs(S().trees[treeOfConfig(configID)].nodes) do
            if (node.rank or 0) > (node.applied or 0) then buys[#buys + 1] = node.id end
        end
        return buys, {}, {}
    end
    T.CommitConfig = function(configID)
        record("CommitConfig", configID)
        local treeID = treeOfConfig(configID)
        if not treeID or S().committing or not staged(treeID) then return false end
        S().committing = true
        C_Timer.After(LW.COMMIT_DELAY, function()
            S().committing = nil
            if S().commitFails then stub.FireEvent("CONFIG_COMMIT_FAILED", configID) return end
            for _, node in ipairs(S().trees[treeID].nodes) do
                if (node.rank or 0) ~= (node.applied or 0) then node.applied, node.pickedApplied = node.rank, node.picked; stub.FireEvent("TRAIT_NODE_CHANGED", node.id) end
            end
            stub.FireEvent("TRAIT_TREE_CURRENCY_INFO_UPDATED", treeID)
            stub.FireEvent("TRAIT_CONFIG_UPDATED", configID)
        end)
        return true
    end
    _G.C_Traits = setmetatable(T, { __index = before })
    stub.spells = stub.spells or {}
    for _, t in pairs(S().trees) do
        for _, n in ipairs(t.nodes) do
            for _, e in ipairs(n.choices or { n.id * 10 }) do
                stub.spells[e + 800000] = { name = "Perk " .. e, icon = 140000 + e % 1000 }
            end
        end
    end
end

local function install()
    registry()
    -- Another world's panel calls (the hostile sweep's) keep working: this one records, then theirs run.
    local show, hide = _G.ShowUIPanel, _G.HideUIPanel
    _G.ShowUIPanel = function(f)
        record("ShowUIPanel", f:GetName())
        if show then show(f) else f:Show() end
    end
    -- UIParentPanelManager's rule: from addon code in combat it does nothing.
    _G.HideUIPanel = function(f)
        record("HideUIPanel", f:GetName())
        if stub.combat and (stub.inSecure or 0) == 0 then return end
        if hide then hide(f) else f:Hide() end
    end
    _G.Constants = _G.Constants or {}
    Constants.LegacyConsts = { LEGACY_REWARD_TRACK_FACTION_ID = LW.FACTION, LEGACY_POINTS_TRAIT_CURRENCY_ID = LW.POINTS_CURRENCY,
        LEGACY_TREE_PROFESSIONS_ID = LW.PROF, LEGACY_TREE_ADVENTURE_ID = LW.ADV, LEGACY_TREE_PROGRESSION_ID = LW.PROG,
        LEGACY_DEFAULT_CATEGORY_MAGE = 11, LEGACY_DEFAULT_CATEGORY_WARRIOR = 12 }
    _G.C_MajorFactions = setmetatable({
        GetCurrentRenownLevel = function(id) if id == LW.FACTION then return S().earned end return 0 end,
        GetMajorFactionData = function(id)
            if id ~= LW.FACTION or S().noFaction then return nil end
            return { factionID = id, renownLevel = S().earned, maxLevel = 55, isUnlocked = true, renownLevelThreshold = 1, renownReputationEarned = 0 }
        end,
        GetRenownLevels = function(id)
            local out = {}
            for _, lv in ipairs(id == LW.FACTION and S().levels or {}) do out[#out + 1] = { level = lv.level, isMilestone = false } end
            return out
        end,
        GetRenownRewardsForLevel = function(id, level)
            for _, lv in ipairs(S().levels) do if lv.level == level then return lv.rewards end end
            return {}
        end,
    }, { __index = _G.C_MajorFactions })
    _G.RenownRewardUtil = {
        GetUnformattedRenownRewardInfo = function(r) return r.icon, r.name, "%s", r.description end,
        GetRenownRewardInfo = function(r) return r.icon, r.name, r.description end,
    }
    _G.C_ToyBox = { GetToyInfo = function(itemID) if itemID == 501 then return itemID, "Rifle", 1001 end end }
    _G.C_PetJournal = { GetPetInfoByItemID = function(itemID) if itemID == 502 then return "Spectral Bear Cub" end end }
    _G.C_Item = _G.C_Item or {}
    local itemInstant = C_Item.GetItemInfoInstant
    C_Item.GetItemInfoInstant = function(itemID)
        if itemID == 503 then return 503, "Armor", "Miscellaneous", "INVTYPE_TABARD", 1003, 4, 0 end
        if itemInstant then return itemInstant(itemID) end
    end
    C_Item.GetItemQualityByID = function(itemID) if itemID == 503 then return 4 end if itemID then return 3 end end
    _G.INVTYPE_TABARD = "Tabard"
    install_achievements()
    install_traits()
    -- The bootstrap (Blizzard_LegacySystem_Bootstrap.lua, loaded with the game).
    _G.ToggleLegacySystemUI = LW.Toggle
    _G.ToggleLegacyChallenges = LW.Challenges
    _G.ShowLegacyChallenge = function(id)
        record("ShowLegacyChallenge", id)
        local f = load()
        ShowUIPanel(f)
        selectPage(2)
    end
end

-- spec: earned (16), left (3), levels, categories, achievements, trees (the samples
-- above), unviewed ({ [achievementID] = categoryID }), enabled (the module's switch,
-- default true), noFaction (the faction's data not there yet), cannotRefund (the
-- trees' no-refund flag).
function LW.world(spec)
    spec = spec or {}
    return function()
        LW.state = { calls = {}, earned = spec.earned or 16, left = spec.left or 3, levels = spec.levels or LW.Levels(),
            categories = spec.categories or LW.Categories(), achievements = spec.achievements or LW.Achievements(),
            trees = spec.trees or LW.Trees(), unviewed = spec.unviewed or {}, tracked = {}, noFaction = spec.noFaction, cannotRefund = spec.cannotRefund }
        _G.LegacySystemFrame = nil
        install()
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { Legacy = { enabled = spec.enabled ~= false } } } } }
    end
end

return LW
