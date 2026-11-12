-- Popup keys: while one of the game's yes/no popups (StaticPopup1-4) is up, Enter
-- presses its first button. Escape is left to the game.
--
-- Out of combat, Enter is bound to a secure button that clicks the popup's first
-- button, so the game's own code runs the accept untainted. Combat clears the
-- binding right away, and Enter goes back to chat whenever no popup is shown.
-- Only popups in P.YES get this (invites, shares, summons, resurrects, battleground
-- entry). Unknown popups could bind an item, spend gold or roll Need, so they are
-- never touched, and neither are popups with an edit box or that already take Enter.
--
-- Space only answers popups in P.ASKED, the follow-up to something the player just
-- asked an NPC for, so mashing Space through a talk keeps going. Space is also jump,
-- so it must never accept an invite.

local _, DUI = ...
local ns = DUI.Npc

local P = {}
ns.Popups = P

P.NAME = "DaylightUIPopupYes"
P.MAX = 4
-- Popups Enter may answer (names from Blizzard_StaticPopup_Game/GameDialogDefs.lua).
P.YES = {
    PARTY_INVITE = true, GROUP_INVITE_CONFIRMATION = true, QUEST_ACCEPT = true,
    CONFIRM_SUMMON = true, CONFIRM_SUMMON_STARTING_AREA = true, CONFIRM_SUMMON_SCENARIO = true,
    RESURRECT = true, RESURRECT_NO_SICKNESS = true, RESURRECT_NO_TIMER = true,
    CONFIRM_BATTLEFIELD_ENTRY = true, BFMGR_INVITED_TO_QUEUE = true, BFMGR_INVITED_TO_ENTER = true,
    CHAT_CHANNEL_INVITE = true, CHANNEL_INVITE = true,
    CONFIRM_BINDER = true,
}
-- Popups Space also answers, when the accept key includes Space.
P.ASKED = { CONFIRM_BINDER = true }

-- The button Enter would press on this popup, or nil.
function P.ButtonOf(dialog)
    if type(dialog) ~= "table" or not dialog.IsShown or not dialog:IsShown() then return end
    local which = dialog.which
    if type(which) ~= "string" or not P.YES[which] then return end
    local info = type(StaticPopupDialogs) == "table" and StaticPopupDialogs[which]
    if type(info) ~= "table" or info.ignoreKeys or info.enterClicksFirstButton or info.hasEditBox then return end
    local c = dialog.ButtonContainer
    local b = type(c) == "table" and c.Button1
    if type(b) == "table" and b.IsShown and b:IsShown() then return b end
end

-- Bind Enter (and Space for P.ASKED) to the first popup that wants it, or release them.
function P.Update()
    if not P.button or InCombatLockdown() then return end
    local target, space
    if ns.Setting("popupKeys") ~= false then
        for i = 1, P.MAX do
            local d = _G["StaticPopup" .. i]
            target = P.ButtonOf(d)
            if target then
                space = P.ASKED[d.which] == true and ns.Setting("keys") ~= false
                    and ns.Setting("acceptKey") ~= "enter"
                break
            end
        end
    end
    space = space or false
    if target == P.bound and space == P.space then return end
    P.bound, P.space = target, space
    ClearOverrideBindings(P.button)
    if target then
        P.button:SetAttribute("clickbutton", target)
        SetOverrideBindingClick(P.button, true, "ENTER", P.NAME, "LeftButton")
        if space then SetOverrideBindingClick(P.button, true, "SPACE", P.NAME, "LeftButton") end
    end
end

-- Does a popup own this key right now? The talk window behind it must let the key
-- through, since a frame that takes keyboard input blocks every binding.
function P.Holds(key)
    if key == "SPACE" then return P.space == true end
    return key == "ENTER" and P.bound ~= nil
end

-- Wait a frame: the game fills the popup after showing it.
function P.Soon()
    if C_Timer and C_Timer.After then C_Timer.After(0, P.Update) else P.Update() end
end

function P.Enable()
    if P.button then return P.Update() end
    -- After a /reload in combat the secure button can only be created once combat ends.
    if InCombatLockdown() then return DUI.AfterCombat(P.Enable, "npc:popups") end
    local b = CreateFrame("Button", P.NAME, UIParent, "SecureActionButtonTemplate")
    b:SetAttribute("type", "click")
    b:RegisterForClicks("AnyDown")
    P.button = b
    for i = 1, P.MAX do
        local d = _G["StaticPopup" .. i]
        if type(d) == "table" and d.HookScript then
            d:HookScript("OnShow", P.Soon)
            d:HookScript("OnHide", P.Soon)
        end
    end
    -- A popup that's already shown can be reused for another question.
    if type(StaticPopup_Show) == "function" then hooksecurefunc("StaticPopup_Show", P.Soon) end
    DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function()
        if P.bound then
            P.bound, P.space = nil, false
            ClearOverrideBindings(P.button)
        end
    end)
    DUI.RegisterEvent("PLAYER_REGEN_ENABLED", P.Update)
    P.Update()
end
