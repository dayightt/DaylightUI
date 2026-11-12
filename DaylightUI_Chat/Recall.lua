-- Up/Down in the edit box recall your last 50 sent lines; Down past the newest
-- restores the draft. This client's edit box doesn't recall on plain arrows, so
-- the history is kept here. Lines come from the game's pre-send callback
-- (EventRegistry ChatFrame.OnEditBoxPreSendText). Keys come from a hook on the
-- box's OnKeyDown, which only real key presses fire. OnHide and OnTextChanged
-- also run inside the game's send code, so they are never hooked.
-- Alt+Up/Down keeps the game's own history. Protected commands (/cast, /ping...)
-- are never stored, since text put in the box by addon code can't send them.
-- Slash commands the game handles itself (/dance, /who) are cleared from the box
-- before that callback, so Enter keeps them ("/s hi" stays as typed, not "hi").
-- While the game blocks addon chat (boss fights, Mythic+), recall pauses and
-- says so once.

local _, ns = ...

local Recall = {}
ns.Recall = Recall

Recall.MAX = 50
Recall.NOTICE = DaylightUI.Win.Parts.Hex(DaylightUI.Style.INK.LABEL) .. DaylightUI.L["Arrow-key recall is paused here. Alt+Up and Alt+Down still work."] .. "|r"

local lines = {} -- sent lines, oldest first
local pos = 0 -- 0 = the draft, n = nth newest line
local draft = "" -- box text when recall started
local lastSet -- text recall last put in the box
local noticed = false
local enteredAt -- GetTime() of the Enter that kept a slash command
local boxes = setmetatable({}, { __mode = "k" }) -- box -> its alt-arrow mode before ours

local function secret(v) return issecretvalue and issecretvalue(v) end
local function held(fn) return type(fn) == "function" and fn() end

function Recall.Lines() return lines end

-- Skip empty, secret, protected, or a repeat of the newest line.
local function keep(text)
    if type(text) ~= "string" or secret(text) or text == "" then return end
    local cmd = string.match(text, "^%s*(/%S+)")
    if cmd and type(IsSecureCmd) == "function" and IsSecureCmd(cmd) then return end
    if lines[#lines] == text then return end
    lines[#lines + 1] = text
    if #lines > Recall.MAX then table.remove(lines, 1) end
end

local function now() return type(GetTime) == "function" and GetTime() or 0 end

function Recall.OnSend(eb)
    pos, lastSet = 0, nil
    ns.Box.Asked()   -- whatever the game answers shows on the tab you're on
    ns.Tabs.Heard(eb)
    if type(eb) ~= "table" or type(eb.GetText) ~= "function" then return end
    if enteredAt and enteredAt == now() then enteredAt = nil return end
    enteredAt = nil
    keep(eb:GetText())
end

local function restricted()
    if type(GetCVarBool) == "function" and GetCVarBool("addonChatRestrictionsForced") then return true end
    if C_ChatInfo and type(C_ChatInfo.InChatMessagingLockdown) == "function"
        and C_ChatInfo.InChatMessagingLockdown() then return true end
    if C_ChallengeMode and type(C_ChallengeMode.IsChallengeModeActive) == "function"
        and C_ChallengeMode.IsChallengeModeActive() then return true end
    return false
end

function Recall.OnKey(eb, key)
    if key == "ENTER" then
        local text = eb:GetText()
        enteredAt = nil
        if type(text) == "string" and not secret(text) and string.find(text, "^%s*/") then
            keep(text)
            enteredAt = now()
        end
        return
    end
    if not Recall.enabled or (key ~= "UP" and key ~= "DOWN") then return end
    if held(IsAltKeyDown) or held(IsControlKeyDown) or held(IsShiftKeyDown) then return end
    if restricted() then
        if not noticed then
            noticed = true
            local cf = eb.chatFrame or _G.DEFAULT_CHAT_FRAME
            if type(cf) == "table" and cf.AddMessage then cf:AddMessage(Recall.NOTICE) end
        end
        return
    end
    if #lines == 0 then return end
    local text = eb:GetText()
    if secret(text) then return end
    -- The text changed or the box reopened since the last step: start over.
    if pos == 0 or text ~= lastSet then
        pos, draft = 0, type(text) == "string" and text or ""
    end
    if key == "UP" then pos = math.min(pos + 1, #lines) else pos = math.max(pos - 1, 0) end
    local show = pos == 0 and draft or lines[#lines - pos + 1]
    lastSet = show
    eb:SetText(show)
end

-- Plain arrows only reach the box with its alt-arrow mode off. The old mode is
-- restored when recall is turned off.
function Recall.SetMode(eb)
    if type(eb.SetAltArrowKeyMode) ~= "function" then return end
    if Recall.enabled then eb:SetAltArrowKeyMode(false) else eb:SetAltArrowKeyMode(boxes[eb]) end
end

function Recall.Watch(eb)
    if type(eb) ~= "table" or boxes[eb] ~= nil or type(eb.HookScript) ~= "function" then return end
    boxes[eb] = type(eb.GetAltArrowKeyMode) == "function" and eb:GetAltArrowKeyMode() and true or false
    eb:HookScript("OnKeyDown", Recall.OnKey)
    Recall.SetMode(eb)
end

function Recall.Apply(cfg)
    Recall.enabled = cfg.arrowHistory and true or false
    for eb in pairs(boxes) do Recall.SetMode(eb) end
    if Recall.registered or not (EventRegistry and EventRegistry.RegisterCallback) then return end
    Recall.registered = true
    EventRegistry:RegisterCallback("ChatFrame.OnEditBoxPreSendText", function(_, eb) Recall.OnSend(eb) end, Recall)
end
