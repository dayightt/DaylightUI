-- Spoken (quest voice-over addon) support: a Play button on each voiced quest's
-- title in the tracker, like Questie's tracker has. This is the only file that
-- reads Spoken. Spoken_Quests keeps its quest part in the global `VoiceOver`, and
-- its QuestOverlayUI offers every tracker the same two calls Questie uses (as of
-- Spoken_Quests 3.8.4, QuestOverlayUI.lua):
-- - QuestOverlayUI:ShowsTrackerButton(questID): its quest part is on, its own
--   "Play button in the objective tracker" setting is on, and a voice pack has
--   the quest's line.
-- - QuestOverlayUI:BindPlayButton(button, questID, title, origin): sets the
--   button's OnClick (and with `button.setPlayState`, stop and replay too.
--   QuestOverlayUI.FollowQueue calls `button:SetState("play"|"stop"|"replay")`
--   whenever its queue changes, via AUDIO_CHANGED).
-- Every read is pcall'd and type-checked, so any change on Spoken's side just
-- reads as "no voice" and the tracker shows no button.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Voice = {
    ORIGIN = "Daylight UI's quest tracker",   -- Spoken's debug log shows who queued a line
    SIZE = 16,                                -- hit box size; the icon is W.ICON_BUTTON_ICON
    ICONS = { play = "ui-play.png", stop = "ui-stop.png", replay = "ui-play.png" },
}
ns.Voice = Voice
Voice.TIPS = { play = L["Play the quest's voice"], stop = L["Stop the voice"], replay = L["Play it again"] }

function Voice.Overlay()
    local V, S = _G.VoiceOver, _G.Spoken
    if type(V) ~= "table" or type(S) ~= "table" then return nil end
    local ok, Q = pcall(function() return V.QuestOverlayUI end)
    if not ok or type(Q) ~= "table" or type(Q.ShowsTrackerButton) ~= "function"
        or type(Q.BindPlayButton) ~= "function" or type(Q.FollowQueue) ~= "function" then
        return nil
    end
    return Q
end

-- Whether the quest gets a Play button, per Spoken.
function Voice.Has(questID)
    local Q = Voice.Overlay()
    if not Q or type(questID) ~= "number" then return false end
    local ok, yes = pcall(Q.ShowsTrackerButton, Q, questID)
    return ok and yes == true
end

-- The glyph follows what Spoken's queue says the quest's line is doing.
local function setState(b, state)
    b.state = Voice.ICONS[state] and state or "play"
    b.SetIcon(Voice.ICONS[b.state])
end

-- One button per title line (Rows.lua creates it, hidden). row is the quest's
-- block, kept highlighted while the mouse is over its button.
function Voice.New(row)
    local W = DUI.Widgets
    local b
    b = W.IconButton(row,Voice.ICONS.play, function() return Voice.TIPS[b and b.state or "play"] end, nil, Voice.SIZE)
    b.SetState = setState
    b.setPlayState = function(self) local Q = Voice.Overlay(); if Q then pcall(Q.FollowQueue, self) end end
    -- Spoken sets its own OnEnter/OnLeave (the game tooltip in its own words) when
    -- it binds. Put these back on afterward, keeping the row highlighted.
    local enter, leave = b:GetScript("OnEnter"), b:GetScript("OnLeave")
    b.enter = function(self)
        enter(self)
        if ns.Tracker then ns.Tracker.HoverDim(row) end
    end
    b.leave = function(self)
        leave(self)
        if ns.Tracker then ns.Tracker.HoverDim(nil) end
    end
    b:SetScript("OnEnter", b.enter)
    b:SetScript("OnLeave", b.leave)
    b:Hide()
    return b
end

-- Hands the button to Spoken for this quest (rebinding only when it showed another
-- quest), and paints its state now.
function Voice.Bind(b, questID, title)
    local Q = Voice.Overlay()
    if not Q then return false end
    if b.questID ~= questID or b.title ~= title then
        b.soundData = nil    -- Spoken's line for the quest it used to show
        local ok = pcall(Q.BindPlayButton, Q, b, questID, title, Voice.ORIGIN)
        b:SetScript("OnEnter", b.enter)
        b:SetScript("OnLeave", b.leave)
        if not ok then b.questID = nil; return false end
        b.questID, b.title = questID, title
    end
    b.setPlayState(b)
    return true
end

-- Spoken's packs load after the first look at the log, and its quest part can be
-- toggled, so the tracker checks again (onChange) when either happens.
local listening = false
function Voice.Enable(onChange)
    local S = _G.Spoken
    if listening or type(S) ~= "table" or type(S.RegisterCallback) ~= "function" then return end
    listening = true
    pcall(S.RegisterCallback, S, "VOICE_PACKS_LOADED", function() onChange() end)
    pcall(S.RegisterCallback, S, "PART_SWITCHED", function(key) if key == "quests" then onChange() end end)
end
