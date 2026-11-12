-- With Questie loaded, asks once per account which quest tracker to use: this one
-- (Questie's tracker steps aside) or Questie's. The answer is the profile's
-- `tracker` setting, so switching profiles carries its own choice. The journal,
-- map marker, arrow and NPC tooltips stay either way, and the switch applies
-- right away. Only asked after the setup guide is done and out of combat; while
-- the guide is open, its modules page asks the same question (InstallerSteps.lua).

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style = DUI.Style

local Choice = {
    NAME = "DaylightUIQuestieChoice",
    W = 380, H = 190,
    WAIT = 3,   -- seconds after login, so the world loads first
}
ns.Choice = Choice

local function guideDone()
    local I = DUI.Installer
    if not I or I.flow ~= nil then return false end
    return I.State and I.State() ~= nil
end

local function build()
    local Win = DUI.Win
    local f = Win.New({ name = Choice.NAME, w = Choice.W, h = Choice.H, strata = "DIALOG" })
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    f.title:SetText(L["Questie is on"])
    if f.sub then f.sub:SetText(L["Which quest tracker?"]) end
    Win.AddPage(f, "ask", {
        Build = function(page)
            page.text = Style.Text(page, Style.SIZE.body, "LEFT")
            Style.InkText(page.text, "TEXT")
            page.text:SetPoint("TOPLEFT", page, "TOPLEFT", Win.EDGE, -12)
            page.text:SetPoint("RIGHT", page, "RIGHT", -Win.EDGE, 0)
            page.text:SetText(L["Daylight UI's journal, marker and arrow stay either way. You can change it later on the Quests options page."])
            page.foot = Win.Parts.Footer(page, { equal = true })
            page.foot:Set({
                { text = L["DaylightUI tracker (works with Questie)"], primary = true, onClick = function() Choice.Pick("ours") end },
                { text = L["Questie's tracker"], onClick = function() Choice.Pick("questie") end },
            })
        end,
        Fill = function() end,
    })
    Win.ShowPage(f, "ask")
    -- The X keeps the current setting and doesn't ask again.
    f.onClose = function() DUI.DB.Root().questieAsked = true; Choice.Close() end
    Choice.frame = f
    return f
end

function Choice.Close()
    local f = Choice.frame
    if f then DUI.Win.Close(f) end
end

-- Asks if needed: Questie loaded, not asked yet on this account, setup guide
-- done. Waits for combat to end.
function Choice.Maybe()
    if not (ns.Bridge and ns.Bridge.Loaded()) then return false end
    local root = DUI.DB.Root()
    if root.questieAsked or not guideDone() then return false end
    if InCombatLockdown() then
        DUI.AfterCombat(Choice.Maybe, "questie choice")
        return false
    end
    DUI.Win.Open(Choice.frame or build())
    return true
end

-- "ours" or "questie": sets the profile's tracker and marks the question answered.
-- Applies right away (Tracker.Follow), no reload.
function Choice.Pick(v)
    DUI.DB.Root().questieAsked = true
    Choice.Close()
    local want = v ~= "questie"
    if DUI:Get("Quests", "tracker") ~= want then DUI:Set("Quests", "tracker", want) end
end

function Choice.Enable()
    if not (ns.Bridge and ns.Bridge.Loaded()) then return end
    C_Timer.After(Choice.WAIT, Choice.Maybe)
end
