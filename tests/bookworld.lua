-- The fake game's spellbook and talents window for the book tests: the game's
-- PlayerSpellsFrame as the game drives it (Blizzard_PlayerSpellsFrame.lua). It is
-- load-on-demand (made the first time it opens, ADDON_LOADED inside the load),
-- with tabs spec 1 / talents 2 / spellbook 3 (the ids on Forever). SetTab fires
-- EventRegistry "PlayerSpellsFrame.TabSet", OnShow/OnHide fire
-- "PlayerSpellsFrame.OpenFrame"/"CloseFrame", PLAYER_LEAVING_WORLD hides it, and
-- inspecting someone switches to the talents tab.
--
-- The frame is protected through its children (IsProtected() returns true,
-- false in game), so stub.secure is on. Addon code can't re-parent it in a fight,
-- and HideUIPanel on it from addon code is blocked in combat (ADDON_ACTION_BLOCKED,
-- seen in game). The game's own calls (the keys, Escape, a loading screen) run
-- untainted and always work.
--
-- BW.world(spec) is stub.Load's "before". A test then plays:
--   BW.Open(3)  -- P: the spellbook;  BW.Open(2)  -- N: talents
--   BW.Toggle(tab), BW.Escape(), BW.LeaveWorld(), BW.Inspect("target")
-- and reads what was called: BW.Calls("HideUIPanel").
local stub = require("stub")

local BW = {}

BW.SPEC, BW.TALENTS, BW.SPELLBOOK = 1, 2, 3

local function S() return BW.state end
local function record(kind, ...) table.insert(S().calls, { kind = kind, args = { ... } }) end

function BW.Calls(kind)
    local out = {}
    for _, c in ipairs(S().calls) do if c.kind == kind then out[#out + 1] = c.args end end
    return out
end

-- The game's own code runs untainted, so what it does always works (secure code
-- in the fake game, stub.inSecure).
local function asGame(fn, ...)
    S().game = (S().game or 0) + 1
    stub.inSecure = (stub.inSecure or 0) + 1
    local ok, err = pcall(fn, ...)
    stub.inSecure = stub.inSecure - 1
    S().game = S().game - 1
    if not ok then error(err, 2) end
end

-- EventRegistry: callbacks by event, in the order registered.
local function registry()
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

-- Blizzard_PlayerSpells, loaded the first time the book opens.
local function bookFrame()
    local f = _G.PlayerSpellsFrame
    if f then return f end
    f = CreateFrame("Frame", "PlayerSpellsFrame", UIParent)
    f.__protected = true
    f:Hide()
    f:SetSize(1618, 720)
    f:SetPoint("TOP", UIParent, "TOP", 0, -104)   -- the center panel spot
    f.specTabID, f.talentTabID, f.spellBookTabID = BW.SPEC, BW.TALENTS, BW.SPELLBOOK
    f.tab = BW.SPELLBOOK
    function f:GetTab() return self.tab end
    function f:SetTab(tabID)
        self.tab = tabID
        EventRegistry:TriggerEvent("PlayerSpellsFrame.TabSet", PlayerSpellsFrame, tabID)
    end
    function f:IsInspecting() return self.inspectUnit ~= nil end
    function f:SetInspectUnit(unit)
        self.inspectUnit = unit
        if unit then self:SetTab(self.talentTabID) end
    end
    f:SetScript("OnShow", function()
        S().opened = (S().opened or 0) + 1
        f:RegisterEvent("PLAYER_LEAVING_WORLD")
        EventRegistry:TriggerEvent("PlayerSpellsFrame.OpenFrame")
    end)
    f:SetScript("OnHide", function()
        f.inspectUnit = nil   -- ClearInspectUnit
        f:UnregisterEvent("PLAYER_LEAVING_WORLD")
        EventRegistry:TriggerEvent("PlayerSpellsFrame.CloseFrame")
    end)
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LEAVING_WORLD" then asGame(HideUIPanel, f) end
    end)
    record("LoadAddOn", "Blizzard_PlayerSpells")
    stub.FireEvent("ADDON_LOADED", "Blizzard_PlayerSpells")
    return f
end

function BW.LoadBook() return bookFrame() end

local function install()
    _G.ShowUIPanel = function(f)
        record("ShowUIPanel", f:GetName())
        f:Show()
    end
    _G.HideUIPanel = function(f)
        record("HideUIPanel", f:GetName(), (S().game or 0) > 0)
        if f.__protected and stub.combat and not stub.enteringCombat and (S().game or 0) == 0 then
            error("ADDON_ACTION_BLOCKED: HideUIPanel on " .. tostring(f:GetName()), 2)
        end
        f:Hide()
    end
    _G.SetUIPanelAttribute = function(f, key, value)
        S().panel[f] = S().panel[f] or {}
        S().panel[f][key] = value
    end
    _G.GetUIPanel = function() return nil end
    _G.PlayerSpellsUtil = {
        -- PlayerSpellsUtil.TogglePlayerSpellsFrame(tab): open on that tab, or
        -- close if it's already open on it.
        TogglePlayerSpellsFrame = function(tab) BW.Toggle(tab) end,
        OpenToSpellBookTab = function() BW.Open(BW.SPELLBOOK) end,
        OpenToClassTalentsTab = function() BW.Open(BW.TALENTS) end,
    }
    -- The game's keys (Bindings_Camelot.xml): P, Shift-P, N, Escape.
    stub.bindings.TOGGLESPELLBOOK = { "P" }
    stub.bindings.TOGGLEPETBOOK = { "SHIFT-P" }
    stub.bindings.TOGGLETALENTS = { "N" }
    stub.bindings.TOGGLEGAMEMENU = { "ESCAPE" }
    stub.commands = {
        TOGGLESPELLBOOK = function() BW.Toggle(BW.SPELLBOOK) end,
        TOGGLEPETBOOK = function() BW.Toggle(BW.SPELLBOOK) end,
        TOGGLETALENTS = function() BW.Toggle(BW.TALENTS) end,
        TOGGLEGAMEMENU = function()
            local f = _G.PlayerSpellsFrame
            if f and f:IsShown() then asGame(HideUIPanel, f) end
        end,
    }
end

-- A key press: an addon override binding first (the fight's book), as in the
-- client, else the game's command (BW.Toggle, BW.Escape's).
function BW.Key(key) stub.PressKey(key) end

-- The key (P = 3, N = 2): load, set the tab, show. Like the game's TrySetTab
-- (Blizzard_PlayerSpellsFrame.lua, Camelot's AreaAttributeForTab), the panel area
-- goes first, and the talents tab is a "center" panel that closes every other one.
function BW.Open(tab)
    asGame(function()
        local f = bookFrame()
        tab = tab or BW.SPELLBOOK
        SetUIPanelAttribute(f, "area", tab == BW.SPELLBOOK and "centerOrLeft" or "center")
        f:SetTab(tab)
        ShowUIPanel(f)
    end)
end

function BW.Toggle(tab)
    local f = _G.PlayerSpellsFrame
    if f and f:IsShown() and f:GetTab() == tab then
        asGame(HideUIPanel, f)
    else
        BW.Open(tab)
    end
end

function BW.Escape() stub.PressKey("ESCAPE") end

function BW.LeaveWorld() stub.FireEvent("PLAYER_LEAVING_WORLD") end

-- Inspecting someone (InspectUnit, or a talent link) opens the game's frame on the
-- talents tab with their tree.
function BW.Inspect(unit)
    asGame(function()
        local f = bookFrame()
        SetUIPanelAttribute(f, "area", "center")   -- TrySetTab(ClassTalents)
        f:SetInspectUnit(unit or "target")
        ShowUIPanel(f)
    end)
end

-- ---------------------------------------------------------------------
-- The talent tree (C_Traits), as read in game on Forever from a level 10 Warrior.
-- One config, one tree holding the class's three trees as display groups
-- (GetGroupDisplayInfoByTreeID), node positions on a 600 grid (rows
-- y = 2130 + 600 * row, columns from each tree's smallest x), each tier's rule a
-- condition ("Spend %d more points in %s", spentAmountRequired = points in that
-- tree), arrows as visibleEdges on the source node, and one currency
-- (quantity = points left). A node lists several groupIDs; its tree is the
-- display group among them.
-- ---------------------------------------------------------------------

BW.CONFIG, BW.CONFIG2, BW.TREE, BW.CURRENCY = 8237012, 8237013, 1117, 3820
BW.SWITCH_DELAY = 3
BW.ARMS, BW.FURY, BW.PROT = 11650, 11657, 11670

BW.GROUPS = {
    { groupID = BW.ARMS, displayName = "Arms", icon = 132292, orderIndex = 0, skillLineID = 26 },
    { groupID = BW.FURY, displayName = "Fury", icon = 132347, orderIndex = 1, skillLineID = 256 },
    { groupID = BW.PROT, displayName = "Protection", icon = 132341, orderIndex = 2, skillLineID = 257 },
}

-- { id, spell, name, group, x, y, max, rank (bought, applied), staged?, edges = { target ids } }
-- Real nodes read in game (Arms, Fury), with Protection's made up the same way.
function BW.WarriorNodes()
    return {
        { id = 105949, spell = 1310222, name = "Spearing Strike", group = BW.ARMS, x = 1020, y = 3930, max = 1 },
        { id = 105948, spell = 12163, name = "Two-Handed Weapon Specialization", group = BW.ARMS, x = 1620, y = 3930, max = 3 },
        { id = 105947, spell = 16493, name = "Impale", group = BW.ARMS, x = 2220, y = 3930, max = 2 },
        { id = 105951, spell = 12296, name = "Anger Management", group = BW.ARMS, x = 1620, y = 3330, max = 1 },
        { id = 105950, spell = 12834, name = "Deep Wounds", group = BW.ARMS, x = 2220, y = 3330, max = 3, edges = { 105947 } },
        { id = 105945, spell = 12292, name = "Sweeping Strikes", group = BW.ARMS, x = 1620, y = 4530, max = 1, edges = { 105941 } },
        { id = 105944, spell = 1290261, name = "Weaponmaster", group = BW.ARMS, x = 2220, y = 4530, max = 5 },
        { id = 105942, spell = 12289, name = "Improved Hamstring", group = BW.ARMS, x = 2220, y = 5130, max = 3 },
        { id = 105941, spell = 12294, name = "Mortal Strike", group = BW.ARMS, x = 1620, y = 5730, max = 1 },
        { id = 105938, spell = 12321, name = "Booming Voice", group = BW.FURY, x = 5620, y = 2130, max = 5 },
        { id = 105939, spell = 12320, name = "Cruelty", group = BW.FURY, x = 6220, y = 2130, max = 5, rank = 2 },
        { id = 105937, spell = 12322, name = "Unbridled Wrath", group = BW.FURY, x = 6220, y = 2730, max = 5 },
        { id = 105935, spell = 12323, name = "Piercing Howl", group = BW.FURY, x = 5620, y = 3330, max = 1 },
        { id = 105934, spell = 16487, name = "Blood Craze", group = BW.FURY, x = 6220, y = 3330, max = 3 },
        { id = 105933, spell = 23584, name = "Dual Wield Specialization", group = BW.FURY, x = 5020, y = 3930, max = 5 },
        { id = 105931, spell = 12317, name = "Enrage", group = BW.FURY, x = 6220, y = 3930, max = 5 },
        { id = 105932, spell = 20502, name = "Improved Execute", group = BW.FURY, x = 6820, y = 3930, max = 2 },
        { id = 105927, spell = 12328, name = "Death Wish", group = BW.FURY, x = 5620, y = 4530, max = 1, edges = { 105928 } },
        { id = 105926, spell = 20504, name = "Improved Intercept", group = BW.FURY, x = 6820, y = 4530, max = 2 },
        { id = 105928, spell = 12319, name = "Flurry", group = BW.FURY, x = 5620, y = 5130, max = 5 },
        { id = 105930, spell = 23881, name = "Bloodthirst", group = BW.FURY, x = 5620, y = 5730, max = 1 },
        { id = 105960, spell = 12298, name = "Shield Specialization", group = BW.PROT, x = 9680, y = 2130, max = 5 },
        { id = 105961, spell = 12297, name = "Anticipation", group = BW.PROT, x = 10280, y = 2130, max = 5 },
        { id = 105962, spell = 12301, name = "Improved Bloodrage", group = BW.PROT, x = 9080, y = 2730, max = 2 },
        { id = 105963, spell = 12809, name = "Concussion Blow", group = BW.PROT, x = 9680, y = 4530, max = 1, edges = { 105964 } },
        { id = 105964, spell = 23922, name = "Shield Slam", group = BW.PROT, x = 9680, y = 5730, max = 1 },
    }
end

-- The tree a config holds (BW.trees[configID]); BW.tree is the first set's.
local function treeOf(configID) return BW.trees and BW.trees[configID] end

local function spentIn(tree, group)
    local n = 0
    for _, node in ipairs(tree.nodes) do if node.group == group then n = n + (node.rank or 0) end end
    return n
end

local function spentAll(tree)
    local n = 0
    for _, node in ipairs(tree.nodes) do n = n + (node.rank or 0) end
    return n
end

local function rowOf(node) return math.floor((node.y - 2130) / 600 + 0.5) end

-- The tier rule: points in that tree (as the game's conditions read).
local function condMet(tree, node) return spentIn(tree, node.group) >= rowOf(node) * 5 end

local function edgesMet(tree, node)
    for _, src in ipairs(tree.nodes) do
        for _, to in ipairs(src.edges or {}) do
            if to == node.id and (src.rank or 0) < src.max then return false end
        end
    end
    return true
end

function BW.Node(id, configID)
    local tree = configID and treeOf(configID) or BW.tree
    for _, node in ipairs(tree.nodes) do if node.id == id then return node end end
end

-- canPurchaseRank is the server's "may": the tier and the arrow, not the points
-- (the game checks those itself in TalentFrameBaseMixin:CanAfford). Applied points
-- can't be refunded on Forever (cannotRefund).
local function nodeInfo(tree, node)
    local rank = node.rank or 0
    local avail = condMet(tree, node) and edgesMet(tree, node)
    local edges = {}
    for _, to in ipairs(node.edges or {}) do
        edges[#edges + 1] = { targetNode = to, type = 2, visualStyle = 1, isActive = rank >= node.max }
    end
    local conds = {}
    if rowOf(node) > 0 then conds[1] = node.group * 10 + rowOf(node) end
    return {
        ID = node.id, posX = node.x, posY = node.y, type = 0, flags = 0,
        ranksPurchased = rank, activeRank = BW.state.activeFollows and rank or rank - (node.staged or 0), currentRank = rank, maxRanks = node.max,
        canPurchaseRank = avail and rank < node.max, canRefundRank = (node.staged or 0) > 0,
        isAvailable = condMet(tree, node), isVisible = node.hidden ~= true, meetsEdgeRequirements = edgesMet(tree, node),
        groupIDs = { node.group + 3, 12826, node.group }, conditionIDs = conds,
        entryIDs = { node.id + 24730 }, activeEntry = { entryID = node.id + 24730, rank = rank },
        visibleEdges = edges,
    }
end

-- The game's staging happens client side, at once: a rank bought or taken back
-- fires TRAIT_NODE_CHANGED and the currency event. Apply goes to the server and
-- answers later (within 0.8 s in game), BW.COMMIT_DELAY.
BW.COMMIT_DELAY = 0.5

local function hasStaged(tree)
    for _, node in ipairs(tree.nodes) do if (node.staged or 0) > 0 then return true end end
    return false
end

local function changed(node)
    stub.FireEvent("TRAIT_NODE_CHANGED", node.id)
    stub.FireEvent("TRAIT_TREE_CURRENCY_INFO_UPDATED", BW.TREE)
end

local function purchase(configID, nodeID)
    record("PurchaseRank", configID, nodeID)
    local tree = treeOf(configID)
    local node = tree and BW.Node(nodeID, configID)
    if not node or tree.committing or not nodeInfo(tree, node).canPurchaseRank or tree.left < 1 then return false end
    node.rank = (node.rank or 0) + 1
    node.staged = (node.staged or 0) + 1
    tree.left = tree.left - 1
    changed(node)
    return true
end

local function refund(configID, nodeID, clearEdges)
    record("RefundRank", configID, nodeID, clearEdges)
    local tree = treeOf(configID)
    local node = tree and BW.Node(nodeID, configID)
    if not node or tree.committing or (node.staged or 0) < 1 then return false end
    node.rank = node.rank - 1
    node.staged = node.staged - 1
    tree.left = tree.left + 1
    changed(node)
    return true
end

local function rollback(configID)
    record("RollbackConfig", configID)
    local tree = treeOf(configID)
    if not tree or tree.committing then return false end
    for _, node in ipairs(tree.nodes) do
        local n = node.staged or 0
        if n > 0 then
            node.rank, node.staged, tree.left = node.rank - n, 0, tree.left + n
            stub.FireEvent("TRAIT_NODE_CHANGED", node.id)
        end
    end
    stub.FireEvent("TRAIT_TREE_CURRENCY_INFO_UPDATED", BW.TREE)
    return true
end

local function canChange()
    if stub.combat then return false, false, "You can't do that while in combat." end
    return true, true, nil
end

-- The set's combat config, or nil for a second set never switched to.
function BW.ConfigOf(group)
    if group == 1 then return BW.CONFIG end
    if group == 2 and BW.state.dual and treeOf(BW.CONFIG2) then return BW.CONFIG2 end
end

local function commit(savedConfigID)
    record("CommitConfig", savedConfigID)
    local configID = BW.ConfigOf(BW.state.active)
    local tree = treeOf(configID)
    if not tree or tree.committing or not hasStaged(tree) or not canChange() then return false end
    tree.committing = true
    -- The game's frame listens on C_ClassTalents.GetActiveConfigID()
    -- (Blizzard_ClassTalentsFrame.lua). The answer comes for that id, which may
    -- not be the set's combat config (BW.state.activeConfig).
    local answerID = C_ClassTalents.GetActiveConfigID()
    local function answer()
        tree.committing = nil
        if BW.state.commitFails then
            stub.FireEvent("CONFIG_COMMIT_FAILED", configID)
            return
        end
        for _, node in ipairs(tree.nodes) do
            if (node.staged or 0) > 0 then node.staged = 0; stub.FireEvent("TRAIT_NODE_CHANGED", node.id) end
        end
        stub.FireEvent("SPELLS_CHANGED")
        stub.FireEvent("TRAIT_TREE_CURRENCY_INFO_UPDATED", BW.TREE)
        stub.FireEvent("TRAIT_CONFIG_UPDATED", answerID)
        stub.FireEvent("PLAYER_TALENT_UPDATE")
    end
    -- An instant answer comes inside the call, before it returns. The game marks
    -- the commit started before calling (TalentFrameBaseMixin:CommitConfig).
    if BW.state.commitInstant then answer() else C_Timer.After(BW.COMMIT_DELAY, answer) end
    return true
end

local function install_traits()
    _G.C_ClassTalents = {
        GetActiveConfigID = function() return BW.state.activeConfig or BW.ConfigOf(BW.state.active) end,
        CanEditTalents = function() return true, "" end,
        CanChangeTalents = canChange,
        CommitConfig = commit,
    }
    _G.C_SpecializationInfo = _G.C_SpecializationInfo or {}
    C_SpecializationInfo.GetActiveSpecGroup = function() return BW.state.active end
    C_SpecializationInfo.GetCombatConfigIDForSpecGroup = function(g) return BW.ConfigOf(g) end
    -- Forever only has the global (the game's ClassTalentsFrame IsDualSpecUnlocked).
    -- C_SpecializationInfo has no GetNumSpecGroups, and asking it grayed Secondary.
    C_SpecializationInfo.GetNumSpecGroups = nil
    _G.GetNumSpecGroups = function() return BW.state.dual and 2 or 1 end
    -- Switching sets is a cast on the server (the game shows a cast bar), so it
    -- answers later, BW.SWITCH_DELAY.
    C_SpecializationInfo.SetActiveSpecGroup = function(g)
        record("SetActiveSpecGroup", g)
        if g == BW.state.active or not BW.state.dual then return end
        C_Timer.After(BW.SWITCH_DELAY, function()
            BW.state.active = g
            if not treeOf(BW.CONFIG2) then BW.trees[BW.CONFIG2] = BW.NewTree({ blank = true }) end
            stub.FireEvent("ACTIVE_COMBAT_CONFIG_CHANGED", BW.ConfigOf(g))
            stub.FireEvent("PLAYER_TALENT_UPDATE")
        end)
    end
    _G.C_Traits = {
        GetConfigInfo = function(id)
            if not treeOf(id) then return nil end
            return { ID = id, name = "Warrior", treeIDs = { BW.TREE }, type = 4, usesSharedActionBars = false }
        end,
        GetTreeNodes = function(treeID)
            if treeID ~= BW.TREE then return {} end
            local ids = {}
            for _, node in ipairs(BW.tree.nodes) do ids[#ids + 1] = node.id end
            return ids
        end,
        GetNodeInfo = function(configID, nodeID)
            local tree = treeOf(configID)
            local node = tree and BW.Node(nodeID, configID)
            if not node then return { ID = nodeID, isVisible = false, entryIDs = {}, groupIDs = {}, visibleEdges = {}, conditionIDs = {} } end
            return nodeInfo(tree, node)
        end,
        GetEntryInfo = function(_, entryID)
            local node = BW.Node(entryID - 24730)
            if not node then return nil end
            return { definitionID = node.id + 29531, type = 1, maxRanks = node.max, isAvailable = true }
        end,
        GetDefinitionInfo = function(defID)
            local node = BW.Node(defID - 29531)
            if not node then return nil end
            return { spellID = node.spell }
        end,
        GetConditionInfo = function(configID, condID)
            local tree = treeOf(configID) or BW.tree
            local group, row = math.floor(condID / 10), condID % 10
            -- spentAmountRequired is the points still missing, not the tier's
            -- total. Fury with 2 spent said 3/8/13/18/23/28 in game, and the game
            -- prints it as is (Blizzard_SharedTalentUtil.lua).
            local need = math.max(row * 5 - spentIn(tree, group), 0)
            local met = need == 0
            return { condID = condID, isAlwaysMet = false, isGate = false, isMet = met, isSufficient = met,
                spentAmountRequired = need, traitCurrencyID = BW.CURRENCY, type = 0,
                tooltipFormat = "Spend %d more |4point:points; in %s |4Talent:Talents;",
                tooltipText = "|cffff2020Spend " .. need .. " more |4point:points; in  |4Talent:Talents;|r" }
        end,
        GetGroupDisplayInfoByTreeID = function(treeID)
            if treeID ~= BW.TREE then return {} end
            return BW.tree.groups
        end,
        GetTreeInfo = function(_, treeID) return { ID = treeID, buttonSize = 40, cannotRefund = true, gates = {} } end,
        GetTreeCurrencyInfo = function(configID, treeID)
            local tree = treeOf(configID)
            if treeID ~= BW.TREE or not tree then return {} end
            return { { traitCurrencyID = BW.CURRENCY, quantity = tree.left, maxQuantity = tree.left + spentAll(tree), spent = spentAll(tree) } }
        end,
        GetNodeCost = function() return { { ID = BW.CURRENCY, amount = 1 } } end,
        -- Empty while the talent's spell isn't loaded (BW.uncached[spell]), as in
        -- the client after a login.
        GetTraitDescription = function(entryID, rank)
            local node = BW.Node(entryID - 24730)
            if node and BW.uncached[node.spell] then return "" end
            return node and string.format("%s, rank %d. Lowers threat by %d%%.", node.name, rank, rank * 5) or ""
        end,
        PurchaseRank = purchase,
        RefundRank = refund,
        RollbackConfig = rollback,
        ConfigHasStagedChanges = function(configID)
            local tree = treeOf(configID)
            return tree ~= nil and hasStaged(tree)
        end,
        -- What the game's talent window reads for the talents an Apply learns
        -- (ClassTalentsFrameMixin:SetCommitStarted).
        GetStagedChanges = function(configID)
            local buys = {}
            for _, node in ipairs(treeOf(configID) and treeOf(configID).nodes or {}) do
                if (node.staged or 0) > 0 then buys[#buys + 1] = node.id end
            end
            return buys, {}, {}
        end,
    }
    stub.spells = stub.spells or {}
    for _, node in ipairs(BW.tree.nodes) do stub.spells[node.spell] = { name = node.name, icon = 130000 + node.id % 1000, talent = true } end
    -- iconID, originalIconID: the game's talent buttons draw the second
    -- (Blizzard_SharedTalentUtil.lua). The first is left empty for a talent here
    -- so a reader of the first answer shows up in the tests.
    C_Spell.GetSpellTexture = function(id)
        local sp = stub.spells[id]
        if not sp then return nil end
        if sp.talent then return 0, sp.icon end
        return sp.icon, sp.icon
    end
    BW.uncached = {}
    C_Spell.IsSpellDataCached = function(id) return not BW.uncached[id] end
    C_Spell.RequestLoadSpellData = function(id) record("RequestLoadSpellData", id) end
    -- The game's whole tooltip for a talent's rank, as its own talent buttons
    -- append it (AddTooltipDescription in Blizzard_TalentDisplay.lua): an ability's
    -- cost, range, cast time, cooldown and requirement in white (red when not
    -- met), then the description in yellow. The description is missing while the
    -- spell isn't loaded.
    _G.C_TooltipInfo = _G.C_TooltipInfo or {}
    local WHITE, YELLOW, RED = { r = 1, g = 1, b = 1 }, { r = 1, g = 0.82, b = 0 }, { r = 1, g = 0.125, b = 0.125 }
    BW.ABILITY = {
        [12294] = {
            { leftText = "30 Rage", leftColor = WHITE, rightText = "Melee Range", rightColor = WHITE },
            { leftText = "Instant", leftColor = WHITE, rightText = "6 sec cooldown", rightColor = WHITE },
            { leftText = "Requires Melee Weapon", leftColor = RED },
        },
    }
    C_TooltipInfo.GetTraitEntry = function(entryID, rank)
        local node = BW.Node(entryID - 24730)
        if not node then return nil end
        local lines = {}
        for _, l in ipairs(BW.ABILITY[node.spell] or {}) do lines[#lines + 1] = l end
        if not BW.uncached[node.spell] then
            lines[#lines + 1] = { leftText = string.format("%s, rank %d. Lowers threat by %d%%.", node.name, rank, rank * 5), leftColor = YELLOW, wrapText = true }
        end
        return { type = 0, lines = lines }
    end
    C_Spell.GetSpellLink = function(id)
        local sp = stub.spells[id]
        return "|Hspell:" .. tostring(id) .. "|h[" .. tostring(sp and sp.name) .. "]|h"
    end
    _G.ChatFrameUtil = { InsertLink = function(link) record("InsertLink", link); return true end }
end

-- The tree for this world: spec.tree = { nodes = BW.WarriorNodes() (default),
-- left = points left (0), groups = BW.GROUPS, blank = no ranks }. A test changes
-- BW.tree (a node's rank, left) and fires the game's event, or spends through the
-- game's calls (C_Traits.PurchaseRank...), which fire them like the game.
function BW.NewTree(spec)
    spec = spec or {}
    local nodes = spec.nodes or BW.WarriorNodes()
    if spec.blank then for _, node in ipairs(nodes) do node.rank, node.staged = nil, nil end end
    return { nodes = nodes, left = spec.left or 0, groups = spec.groups or BW.GROUPS }
end

-- The spellbook (C_SpellBook, SpellBookDocumentation): skill lines of items in
-- slot order, plus a pet's own bank. An item: { name, sub, icon, spellID, passive,
-- low, flyout = { spellIDs }, loose, future }. The Warrior read in game had
-- General, Arms, Fury, Protection, no low ranks, and Stances as a flyout (type 4)
-- with no spell id. A test changes BW.book and fires SPELLS_CHANGED.
BW.PLAYER, BW.PET = 0, 1
function BW.WarriorBook()
    return { lines = {
        { name = "General", icon = 1, items = {
            { name = "Attack", spellID = 6603, icon = 11 },
            { name = "Stances", flyout = { 2457, 71 } },
            { name = "Battle Stance", spellID = 2457, icon = 12, loose = true },
            { name = "Defensive Stance", spellID = 71, icon = 13, loose = true },
            { name = "Blood Fury", sub = "Racial", spellID = 20572, icon = 14 },
            { name = "Hardiness", sub = "Racial Passive", spellID = 20573, icon = 15, passive = true },
        } },
        { name = "Arms", icon = 2, items = {
            { name = "Heroic Strike", sub = "Rank 2", spellID = 284, icon = 21 },
            { name = "Rend", sub = "Rank 1", spellID = 772, icon = 22 },
        } },
        { name = "Fury", icon = 3, items = { { name = "Battle Shout", sub = "Rank 1", spellID = 6673, icon = 31 } } },
        { name = "Protection", icon = 4, items = { { name = "Shield Bash", sub = "Rank 1", spellID = 72, icon = 41 } } },
    } }
end

-- A mage with lower ranks (Rank 1 and 2 under Rank 3) and a pet book.
function BW.MageBook()
    return { lines = {
        { name = "General", icon = 1, items = { { name = "Attack", spellID = 6603, icon = 11 } } },
        { name = "Fire", icon = 2, items = {
            { name = "Fireball", sub = "Rank 1", spellID = 133, icon = 21, low = true },
            { name = "Fireball", sub = "Rank 2", spellID = 143, icon = 21, low = true },
            { name = "Fireball", sub = "Rank 3", spellID = 145, icon = 21 },
            { name = "Fire Blast", sub = "Rank 1", spellID = 2136, icon = 22 },
        } },
        { name = "Hidden", icon = 9, shouldHide = true, items = { { name = "Secret", spellID = 1, icon = 1 } } },
    } }
end

local function bookItem(slot, bank)
    local b = BW.book
    if bank == BW.PET then return b.pet and b.pet[slot] end
    local n = 0
    for _, line in ipairs(b.lines) do
        if slot <= n + #line.items then return line.items[slot - n] end
        n = n + #line.items
    end
end

local function install_book()
    local SB = _G.C_SpellBook
    SB.GetNumSpellBookSkillLines = function() return #BW.book.lines end
    SB.GetSpellBookSkillLineInfo = function(i)
        local n = 0
        for k = 1, i - 1 do n = n + #BW.book.lines[k].items end
        local line = BW.book.lines[i]
        return { name = line.name, iconID = line.icon, itemIndexOffset = n, numSpellBookItems = #line.items,
            shouldHide = line.shouldHide or false }
    end
    SB.GetSpellBookItemInfo = function(slot, bank)
        local it = bookItem(slot, bank)
        if not it then return nil end
        return { actionID = it.flyout and (it.flyoutID or 1) or it.spellID, spellID = (not it.flyout) and it.spellID or nil,
            itemType = it.flyout and 4 or (it.future and 2 or (bank == BW.PET and 3 or 1)),
            name = it.name, subName = it.sub or "", iconID = it.icon or 0, isPassive = it.passive or false, isOffSpec = false }
    end
    SB.IsSpellBookItemLowRank = function(slot, bank) local it = bookItem(slot, bank); return it and it.low or false end
    SB.IsSpellBookItemLooseFlyoutMember = function(slot, bank) local it = bookItem(slot, bank); return it and it.loose or false end
    SB.GetSpellBookItemCooldownDuration = function(slot, bank) return { slot = slot, bank = bank } end
    SB.GetSpellBookItemAutoCast = function(slot, bank) local it = bookItem(slot, bank); return it and it.autocast or false, false end
    SB.GetSpellBookItemLink = function(slot, bank) local it = bookItem(slot, bank); return it and ("|Hspell:" .. tostring(it.spellID) .. "|h[" .. it.name .. "]|h") end
    SB.GetSpellBookItemTradeSkillLink = function() return nil end
    SB.HasPetSpells = function() if BW.book.pet then return #BW.book.pet, "PET" end return nil end
    -- Blocked from addon code in a fight (ADDON_ACTION_BLOCKED in game).
    SB.PickupSpellBookItem = function(slot, bank)
        if stub.combat and (S().game or 0) == 0 then error("ADDON_ACTION_BLOCKED: PickupSpellBookItem", 2) end
        record("PickupSpellBookItem", slot, bank)
    end
    _G.PetHasSpellbook = function() return BW.book.pet ~= nil end
    -- A flyout by its id (an item's flyoutID, 1 by default): its name, its count,
    -- and each slot's spell from the book's loose copy.
    local function flyoutOf(id)
        for _, line in ipairs(BW.book.lines) do
            for _, it in ipairs(line.items) do
                if it.flyout and (it.flyoutID or 1) == id then return it end
            end
        end
    end
    local function spellItem(id)
        for _, line in ipairs(BW.book.lines) do
            for _, x in ipairs(line.items) do if x.spellID == id and not x.flyout then return x end end
        end
    end
    _G.GetFlyoutInfo = function(id)
        local f = flyoutOf(id)
        if f then return f.name, "", #f.flyout, true end
    end
    _G.GetFlyoutSlotInfo = function(id, i)
        local f = flyoutOf(id)
        local x = f and spellItem(f.flyout[i])
        if x then return x.spellID, x.spellID, true, x.name end
    end
    _G.C_Spell = _G.C_Spell or {}
    -- The rank text ("Rank 2", or "" for none, as the book item's subName).
    C_Spell.GetSpellSubtext = function(id) local x = spellItem(id); return x and (x.sub or "") end
    C_Spell.PickupSpell = function(id)
        if stub.combat then error("ADDON_ACTION_BLOCKED: PickupSpell", 2) end
        record("PickupSpell", id)
    end
end

-- spec.dual: a second talent set. true means it was switched to before and has its
-- own tree (spec.tree2, blank by default); "new" means bought but never used, with
-- no config yet. spec.active is the set in use (1).
function BW.world(spec)
    spec = spec or {}
    return function()
        BW.state = { calls = {}, panel = {} }
        stub.secure = true
        _G.PlayerSpellsFrame = nil
        registry()
        install()
        BW.tree = BW.NewTree(spec.tree)
        BW.trees = { [BW.CONFIG] = BW.tree }
        BW.state.active = spec.active or 1
        BW.state.dual = spec.dual and true or nil
        if spec.dual == true then BW.trees[BW.CONFIG2] = BW.NewTree(spec.tree2 or { blank = true }) end
        install_traits()
        BW.book = spec.book or BW.WarriorBook()
        install_book()
        if spec.loaded then bookFrame() end
        if spec.before then spec.before() end
    end
end

return BW
