-- Skip NPC dialogue: when the only thing an NPC offers is one service button
-- (vendor, flight master, banker, trainer...), press it. Shift, combat, quests,
-- several buttons and plain chat buttons leave the dialogue alone.

local _, ns = ...

local Gossip = {}
ns.Gossip = Gossip
ns.features[#ns.features + 1] = Gossip

local mod, registered, pickedThisTalk

local function isFn(f) return type(f) == "function" end

-- Speech-bubble icons mean "talk more", not a service. Old and new art.
local CHAT_ICONS = { [132053] = true, [1019848] = true }

local function paused()
    if isFn(IsShiftKeyDown) and IsShiftKeyDown() then return true end
    if isFn(InCombatLockdown) and InCombatLockdown() then return true end
    return false
end

local function hasQuests(C)
    local a = isFn(C.GetActiveQuests) and C.GetActiveQuests() or nil
    local v = isFn(C.GetAvailableQuests) and C.GetAvailableQuests() or nil
    return (type(a) == "table" and #a > 0) or (type(v) == "table" and #v > 0)
end

local function isService(o)
    if type(o) ~= "table" or CHAT_ICONS[o.overrideIconID or o.icon] then return false end
    if o.status ~= nil and o.status ~= 0 then return false end  -- locked or used up
    return o.failureDescription == nil
end

function Gossip.OnShow()
    if not (mod and mod.db and mod.db.skipGossip == true) or paused() then return end
    local C = C_GossipInfo
    if type(C) ~= "table" or not isFn(C.GetOptions) or not isFn(C.SelectOptionByIndex) then return end
    -- One press per conversation, so an unknown chat button can't loop.
    if pickedThisTalk or hasQuests(C) then return end
    local options = C.GetOptions()
    if type(options) ~= "table" or #options ~= 1 then return end
    local o = options[1]
    -- The game already presses buttons the server flags for it.
    if not isService(o) or o.selectOptionWhenOnlyOption then return end
    pickedThisTalk = true
    if type(DaylightUI.TalkAnswered) == "function" then DaylightUI.TalkAnswered("GOSSIP_SHOW") end   -- our NPC window stays shut
    C.SelectOptionByIndex(o.orderIndex or 1)
end

function Gossip.OnClosed() pickedThisTalk = nil end

function Gossip.Enable(m)
    mod = m
    if registered then return end
    registered = true
    DaylightUI.RegisterEvent("GOSSIP_SHOW", Gossip.OnShow)
    DaylightUI.RegisterEvent("GOSSIP_CLOSED", Gossip.OnClosed)
end

function Gossip.Refresh(m) mod = m end
