-- Opening and closing. The game still decides: its bag windows are parented to
-- a hidden frame, so they keep opening and closing as usual, out of sight. After
-- each of its open/close/toggle functions and its close-all-bags event, this bag
-- is shown if the game has any bag open. Closing this one closes the game's too,
-- so they never disagree.
--
-- Nothing of the game's is replaced (that would taint it), only followed. A frame
-- under a hidden parent never gets OnShow, so the functions are followed rather
-- than the frames.

local _, ns = ...
local DUI = DaylightUI

local OC = {}
ns.OpenClose = OC

OC.FUNCTIONS = { "OpenAllBags", "CloseAllBags", "ToggleAllBags", "OpenBackpack", "CloseBackpack",
                 "ToggleBackpack", "OpenBag", "CloseBag", "ToggleBag" }

OC.hidden = CreateFrame("Frame")
OC.hidden:Hide()

-- The game's bag windows: the combined one and one per bag, keyring included.
-- Forever's bank uses tabs, not bag windows, so none of these is the bank.
function OC.GameWindows()
    local out = {}
    if _G.ContainerFrameCombinedBags then out[#out + 1] = _G.ContainerFrameCombinedBags end
    for i = 1, NUM_CONTAINER_FRAMES or 13 do
        local f = _G["ContainerFrame" .. i]
        if f then out[#out + 1] = f end
    end
    return out
end

function OC.AnyOpen()
    if type(IsAnyBagOpen) == "function" then
        local ok, open = pcall(IsAnyBagOpen)
        if ok then return open and true or false end
    end
    for _, f in ipairs(OC.GameWindows()) do
        if f:IsShown() then return true end
    end
    return false
end

-- The game announces a bag opening or closing from each window's OnShow/OnHide,
-- which never run under the hidden parent. Don't announce it on their behalf:
-- calling EventRegistry:TriggerEvent from addon code runs the game's listeners
-- tainted (taint.log blames DaylightUI_Bags in its controller code, then action
-- buttons error in the next fight). The cost: the bag tutorial's "Open your bag"
-- step doesn't advance, and the bag buttons don't light up for an open bag.

local function parked(region)
    while type(region) == "table" and region.GetParent do
        if region == OC.hidden then return true end
        region = region:GetParent()
    end
    return false
end

-- Where a help tip aimed at one of the game's item buttons should go: the same
-- slot here, or the bag itself when that slot is merged into a stack.
local function ourSpot(region)
    local bag = region.GetBagID and region:GetBagID()
    local set = ns.Bags and ns.Bags.buttons[bag]
    local btn = set and set[region:GetID()]
    if btn and btn:IsVisible() then return btn end
    return ns.window
end

-- The game's help tips point at its hidden item buttons. Re-show them on these
-- slots through the game's own HelpTip.
function OC.MoveTips()
    local pool = HelpTip and HelpTip.framePool
    if not pool then return end
    local moving
    for tip in pool:EnumerateActive() do
        if tip.info and parked(tip.relativeRegion) then
            moving = moving or {}
            moving[#moving + 1] = { tip:GetParent(), tip.info, ourSpot(tip.relativeRegion) }
        end
    end
    for _, m in ipairs(moving or {}) do
        HelpTip:Hide(m[1], m[2].text)
        HelpTip:Show(m[1], m[2], m[3])
    end
end

-- Match the game's open state at most once per frame (toggling all bags calls
-- several of these functions in a row).
local pending = false
function OC.Follow()
    -- The game closed its bags (walking away from a merchant): tell it now, inside
    -- its own close, while the NPC window is still listed. A frame later the bag
    -- would be the last window listed and emptying the list gets refused.
    local w = ns.window
    if w and w:IsShown() and not OC.held and DUI.Pad and not OC.AnyOpen() then DUI.Pad.Leaving(w) end
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        local f = ns.window
        if not f then return end
        if OC.AnyOpen() or OC.held then
            f:Show()
            if DUI.Pad then DUI.Pad.Returning(f) end   -- closed and reopened in one frame
        elseif DUI.Motion then DUI.Motion.Vanish(f)
        else f:Hide() end
        if f:IsShown() then OC.MoveTips() end
    end)
end

-- Closes the game's bags by hiding their windows, like their X button does.
-- Never call CloseAllBags from here: it writes the game's who-opened-the-bags
-- local while tainted, and the game reads it on every CloseAllBags(frame)
-- (a window closing, Escape, an NPC). Everything after that read is blocked,
-- including the controller's D-pad and action buttons. The only other thing the
-- game's CloseBag does is RemoveNewItem, done here per window.
function OC.CloseGame()
    for _, f in ipairs(OC.GameWindows()) do
        if f:IsShown() then
            if f ~= _G.ContainerFrameCombinedBags and type(UpdateNewItemList) == "function" then
                pcall(UpdateNewItemList, f)
            end
            f:Hide()
        end
    end
end

function OC.CloseAll()
    OC.held = nil
    OC.CloseGame()
    OC.Follow()
end

-- Shows this bag at the bank or a trade without opening the game's bags. The game
-- opens them there from its own frame's OnShow, which never runs here, and its
-- OpenAllBags called from addon code runs all of its bag code tainted (its bag
-- windows, their settings manager, their anchors). The game read that state at
-- the auction house or bank later and refused SetPreferredGamepadInteractTarget.
-- Returns true when the bag was opened for this (it was closed).
function OC.Hold()
    if OC.held or OC.AnyOpen() or (ns.window and ns.window:IsShown()) then return false end
    OC.held = true
    OC.Follow()
    return true
end

-- What a game open/close/toggle call means for a bag held open by OC.Hold: an
-- open hands it to the game, a close or a toggle closes it (the player sees it
-- open, so a toggle means close). CloseAllBags(frame) only closes what that frame
-- opened, so with a frame it leaves the held bag alone.
local RELEASE = {
    OpenAllBags = "open", OpenBackpack = "open", OpenBag = "open",
    CloseAllBags = "close", CloseBackpack = "close",
    ToggleAllBags = "toggle", ToggleBackpack = "toggle", ToggleBag = "toggle",
}
local function after(name)
    local how = RELEASE[name]
    return function(frame)
        if OC.held and how then
            if how == "open" then
                if OC.AnyOpen() then OC.held = nil end
            elseif how == "toggle" then
                OC.held = nil
                if OC.AnyOpen() then OC.CloseGame() end
            elseif not (name == "CloseAllBags" and frame) then
                OC.held = nil
            end
        end
        OC.Follow()
    end
end

local taken = false
function OC.Take()
    if taken then return end
    taken = true
    for _, f in ipairs(OC.GameWindows()) do f:SetParent(OC.hidden) end
    for _, name in ipairs(OC.FUNCTIONS) do
        if type(_G[name]) == "function" then hooksecurefunc(name, after(name)) end
    end
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("ContainerFrame.CloseAllBags", OC.Follow, OC)
    end
    -- A tutorial that starts with the bag already open points right away with no
    -- signal. It listens to this same event, so check on the next frame.
    DUI.RegisterEvent("BAG_UPDATE_DELAYED", function()
        if ns.window and ns.window:IsShown() then C_Timer.After(0, OC.MoveTips) end
    end)
    -- The controller's Character action opens the bags with it, and the game closes
    -- them in CharacterFrame's OnHide, which never runs while that frame is parked.
    DUI.On("CharacterWindowClosed", function()
        if DUI.Pad.On() and OC.AnyOpen() then OC.CloseAll() end
    end)
    -- The game opens the bags at the mailbox and auction house, but at a trade only
    -- on a controller. Show this bag there too, the way the bank does (OC.Hold),
    -- and close it with the trade if it was opened for it.
    DUI.RegisterEvent("TRADE_SHOW", function()
        OC.tradeOpened = OC.Hold() or OC.tradeOpened
    end)
    DUI.RegisterEvent("TRADE_CLOSED", function()
        if OC.tradeOpened and (OC.held or OC.AnyOpen()) then OC.CloseAll() end
        OC.tradeOpened = nil
    end)
    -- This bag closed some other way (Escape): close the game's bags too.
    local f = ns.window
    if f then
        f:HookScript("OnHide", function()
            OC.held = nil
            if OC.AnyOpen() then OC.CloseGame() end
        end)
    end
end
