local stub = require("stub")
local NW = require("npcworld")

-- Beta clients' Issue Reporter (Blizzard_PTRFeedback). The quest survey it hangs
-- under QuestFrame on a reward page goes under the NPC window instead, and the
-- "Hide Issue Reporter" setting hides it.

local survey

-- The game's side: on QUEST_COMPLETE the survey is made once, then anchored
-- TOP to QuestFrame's BOTTOM and shown, as PopFrameAttachedSurvey does.
local function reporter()
    local rep = CreateFrame("Frame", "PTR_IssueReporter", UIParent)
    rep.Data = { FrameAttachedSurveyFrames = {} }
    rep.Body = CreateFrame("Frame", nil, CreateFrame("Frame", nil, UIParent))
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("QUEST_COMPLETE")
    ev:SetScript("OnEvent", function()
        local q = _G.QuestFrame
        if not q:IsShown() then return end
        survey = rep.Data.FrameAttachedSurveyFrames[q]
        if not survey then
            survey = CreateFrame("Frame", "PTRIssueReporterAlertFrame", UIParent)
            rep.Data.FrameAttachedSurveyFrames[q] = survey
        end
        survey:ClearAllPoints()
        survey:SetPoint("TOP", q, "BOTTOM", 0, 0)
        survey:Show()
    end)
end

local function load(hide)
    survey = nil
    local world = NW.world({})
    stub.Load({ before = function(...)
        world(...)
        reporter()
    end })
    if hide then DaylightUI:Set("general", "hidePTRButton", true) end
end

local function complete()
    NW.Quest("COMPLETE", NW.Candles())
    for _ = 1, 3 do stub.RunTimers() end
end

T.test("the quest survey moves under our NPC window", function()
    load(false)
    complete()
    T.truthy(survey, "the game made its survey")
    local point, rel, relPoint = survey:GetPoint(1)
    T.eq(point, "TOP")
    T.eq(rel, _G.DaylightUINpc)
    T.eq(relPoint, "BOTTOM")
    T.truthy(survey:IsShown())
end)

T.test("Hide Issue Reporter hides the quest survey too", function()
    load(true)
    complete()
    T.truthy(survey, "the game made its survey")
    T.falsy(survey:IsShown())
    complete()   -- popped again, the OnShow hook still keeps it away
    T.falsy(survey:IsShown())
end)
