-- Spending talent points through the same C_Traits calls the game's talent
-- frame uses (Blizzard_SharedTalentFrame.lua, Blizzard_ClassTalentsFrame.lua).
-- Click stages a rank with PurchaseRank. Right-click refunds a staged rank,
-- and Shift also clears dependents, like ClassTalentUtil.ShouldRefundClearEdges.
-- Undo calls RollbackConfig. Apply calls C_ClassTalents.CommitConfig(nil).
--
-- All permission checks come from the game, never our own tier math:
-- canPurchaseRank / canRefundRank, GetNodeCost against the tree's currency,
-- whether the shown set is the active one, whether a commit is pending, and
-- CanChangeTalents for Apply (its error explains a disabled Apply button).

local _, DUI = ...
DUI.Book = DUI.Book or {}   -- the book window's own namespace
local ns = DUI.Book

local Spend = {}
ns.Spend = Spend

Spend.COMMIT_WAIT = 10   -- like the game's maximumCommitTime: no answer by then counts as failed
Spend.SWITCH_WAIT = 8    -- after this, an unfinished set switch re-enables Activate

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

local function traits() return type(C_Traits) == "table" and C_Traits or nil end

-- The talent set on screen and its config.
function Spend.Group() return (ns.Talents and ns.Talents.group) or ns.TalentData.ActiveGroup() end
function Spend.Config() return ns.TalentData.ConfigID(Spend.Group()) end

-- True when the shown set isn't the active one, or an Apply is pending.
function Spend.Locked()
    if Spend.committing then return true end
    return Spend.Group() ~= ns.TalentData.ActiveGroup()
end

-- Same check as the game's CanAfford.
function Spend.Afford(node, data)
    local C = traits()
    local configID = data and data.configID or Spend.Config()
    local costs = C and configID and call(C.GetNodeCost, configID, node.id)
    if type(costs) ~= "table" then return true end
    local have = data and data.currency or {}
    for _, cost in ipairs(costs) do
        if type(cost) == "table" and type(cost.amount) == "number" and (have[cost.ID] or 0) < cost.amount then return false end
    end
    return true
end

function Spend.CanBuy(node, data)
    return node ~= nil and not Spend.Locked() and node.canBuy and Spend.Afford(node, data) or false
end

function Spend.CanRefund(node)
    return node ~= nil and not Spend.Locked() and node.canRefund or false
end

-- Buy and Refund return true when the game accepted the change.
function Spend.Buy(node, data)
    if not Spend.CanBuy(node, data) then return false end
    local C, configID = traits(), Spend.Config()
    return call(C.PurchaseRank, configID, node.id) == true
end

function Spend.Refund(node)
    if not Spend.CanRefund(node) then return false end
    local C, configID = traits(), Spend.Config()
    local clear = type(IsShiftKeyDown) == "function" and IsShiftKeyDown() and true or false
    return call(C.RefundRank, configID, node.id, clear) == true
end

-- Whether the shown set has staged points, like the game's HasAnyConfigChanges.
function Spend.HasChanges()
    if Spend.committing then return false end
    local C, configID = traits(), Spend.Config()
    return C and configID and call(C.ConfigHasStagedChanges, configID) == true or false
end

function Spend.Undo()
    if Spend.Locked() or not Spend.HasChanges() then return false end
    return call(traits().RollbackConfig, Spend.Config()) == true
end

-- Returns ok and, when not ok, the game's own error text if it gave one.
function Spend.CanApply()
    if Spend.Locked() or not Spend.HasChanges() then return false end
    local CT = C_ClassTalents
    if type(CT) ~= "table" or type(CT.CanChangeTalents) ~= "function" then return true end
    local canChange, canAdd, err = call(CT.CanChangeTalents)
    if canChange or canAdd then return true end
    return false, type(err) == "string" and err ~= "" and err or nil
end

-- staged is kept so the page can highlight those talents once the server confirms.
function Spend.Apply(staged)
    if not Spend.CanApply() then return false end
    -- Set this before the call, as TalentFrameBaseMixin:CommitConfig does:
    -- the answer can arrive while CommitConfig is still running.
    Spend.committing = Spend.Config()
    Spend.sent = staged or {}
    local token = {}
    Spend.token = token
    if call(C_ClassTalents.CommitConfig, nil) ~= true then
        if Spend.token == token then Spend.committing, Spend.sent, Spend.token = nil, nil, nil end
        return false
    end
    if Spend.token ~= token then return true end   -- already answered
    C_Timer.After(Spend.COMMIT_WAIT, function()
        if Spend.token == token then Spend.Finished(false) end
    end)
    if ns.Talents then ns.Talents.Soon() end
    return true
end

-- Called from TRAIT_CONFIG_UPDATED, CONFIG_COMMIT_FAILED or the timeout.
function Spend.Finished(ok)
    if not Spend.committing then return end
    local sent = Spend.sent
    Spend.committing, Spend.sent, Spend.token = nil, nil, nil
    if ok and DUI.Sound then DUI.Sound.Play("apply") end
    if ns.Talents then ns.Talents.Applied(ok and sent or nil) end
end

-- Switch talent sets, like the game's Activate button. This starts a cast.
function Spend.Activate(group)
    local S = C_SpecializationInfo
    if type(S) ~= "table" or group == ns.TalentData.ActiveGroup() then return false end
    if InCombatLockdown() then return false end
    call(S.SetActiveSpecGroup, group)
    Spend.activating = group
    -- Moving interrupts the cast without any event, hence the timeout.
    C_Timer.After(Spend.SWITCH_WAIT, function()
        if Spend.activating == group then
            Spend.activating = nil
            if ns.Talents then ns.Talents.Soon() end
        end
    end)
    return true
end

function Spend.Init()
    if Spend.ready then return end
    Spend.ready = true
    DUI.RegisterEvent("TRAIT_CONFIG_UPDATED", function(_, configID)
        -- The event may carry our config or the active config ID (the game's
        -- frame watches the latter). Any other ID counts once nothing is staged.
        local mine = Spend.committing
        if not mine then return end
        if configID == mine or configID == call(C_ClassTalents.GetActiveConfigID)
            or (traits() and call(traits().ConfigHasStagedChanges, mine) == false) then
            Spend.Finished(true)
        end
    end)
    DUI.RegisterEvent("CONFIG_COMMIT_FAILED", function() Spend.Finished(false) end)
    DUI.RegisterEvent("ACTIVE_COMBAT_CONFIG_CHANGED", function()
        if Spend.activating and DUI.Sound then DUI.Sound.Play("apply") end
        Spend.activating = nil
    end)
end

