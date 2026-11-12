-- Beta and PTR clients show Blizzard's "Issue Reporter" bug button
-- (Blizzard_PTRFeedback), and general.hidePTRButton hides it. Its frames are
-- anonymous: the label box is the parent of PTR_IssueReporter.Body and the bug
-- icon is the global "Bug". Live clients have neither, so nothing runs there.
-- The game also hangs an "any issues?" survey under QuestFrame on a quest's
-- reward page. With the NPC window on, QuestFrame is parked out of sight, so
-- the survey moves under the NPC window instead. The same setting hides it.

local _, DUI = ...

local PB = {}
DUI.PTRButton = PB

function PB.Available()
    return type(_G.PTR_IssueReporter) == "table"
end

local hooked = {}
local hiddenByUs = {} -- frames we hid, kept here rather than on the game frame

-- The frames to hide, whichever of them exist.
function PB.Frames()
    local out = {}
    local rep = _G.PTR_IssueReporter
    if type(rep) ~= "table" then return out end
    local body = rep.Body
    if type(body) == "table" and body.GetParent then
        local box = body:GetParent()
        if type(box) == "table" and box ~= UIParent and box.Hide then out[#out + 1] = box end
    end
    local bug = _G.Bug
    if type(bug) == "table" and bug.Hide and bug.GetParent then out[#out + 1] = bug end
    return out
end

local function wanted() return DUI.DB.General().hidePTRButton == true end

function PB.Apply()
    if not PB.Available() then return end
    for _, f in ipairs(PB.Frames()) do
        if not hooked[f] and f.HookScript then
            hooked[f] = true
            f:HookScript("OnShow", function(self) if wanted() then self:Hide() end end)
        end
        if wanted() then
            f:Hide()
        elseif hiddenByUs[f] then
            f:Show() -- only restore what we hid
        end
        hiddenByUs[f] = wanted() or nil
    end
end

-- Surveys the game attaches to its windows (created on first use, one per window).
local function attached()
    local data = type(_G.PTR_IssueReporter) == "table" and _G.PTR_IssueReporter.Data
    local t = type(data) == "table" and data.FrameAttachedSurveyFrames
    return type(t) == "table" and t or nil
end

PB.SURVEY_GAP = 6

-- The game re-places the quest survey every time it pops up, so move it under
-- the NPC window (or hide it) one frame after QUEST_COMPLETE.
function PB.ApplySurveys()
    local list = attached()
    if not list then return end
    for owner, survey in pairs(list) do
        if type(survey) == "table" and survey.Hide then
            if not hooked[survey] and survey.HookScript then
                hooked[survey] = true
                survey:HookScript("OnShow", function(self) if wanted() then self:Hide() end end)
            end
            if wanted() then
                survey:Hide()
            else
                local npc = DUI.Npc and DUI.Npc.Window
                local win = DUI.npcOwnWindow and npc and npc.frame
                if owner == _G.QuestFrame and win then
                    survey:ClearAllPoints()
                    survey:SetPoint("TOP", win, "BOTTOM", 0, -PB.SURVEY_GAP)
                end
            end
        end
    end
end

-- Blizzard builds the button shortly after login, so after a reload it may not
-- exist yet. Retry a few times over the next few seconds.
local function applySoon()
    DUI.SafeCall(PB.Apply)
    for _, delay in ipairs({ 1, 3, 6 }) do
        C_Timer.After(delay, function() DUI.SafeCall(PB.Apply) end)
    end
end

DUI.On("Login", applySoon)
DUI.On("SettingChanged", function(scope)
    if scope == "general" then DUI.SafeCall(PB.Apply); DUI.SafeCall(PB.ApplySurveys) end
end)
DUI.RegisterEvent("QUEST_COMPLETE", function()
    if PB.Available() then C_Timer.After(0, function() DUI.SafeCall(PB.ApplySurveys) end) end
end)
DUI.RegisterEvent("PLAYER_ENTERING_WORLD", applySoon)
DUI.RegisterEvent("ADDON_LOADED", function(_, name)
    if name == "Blizzard_PTRFeedback" then applySoon() end
end)
