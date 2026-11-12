-- Quest details card next to the tracker (right-click a quest > Quest details):
-- title, level and zone, the quest text, objectives and rewards. Uses its own
-- frame and plain reads only, since the game's quest popup runs quest map code
-- that an addon click would taint. Click the card, press Escape or pick Quest
-- details again to close it.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style = DUI.Style

local Details = {}
ns.Details = Details

Details.WIDTH = 280
Details.PAD = 12
Details.GAP = 6              -- between sections
Details.SIZES = { title = Style.SIZE.title, sub = Style.SIZE.small, text = Style.SIZE.body, head = Style.SIZE.head }
Details.GREY = Style.INK.LABEL   -- level line and close hint
Details.TEXT = Style.INK.TEXT
Details.DONE = Style.INK.GOOD    -- finished objective
Details.ICON = 14            -- inline reward icon size
Details.HEAD = { objectives = L["Objectives"], rewards = L["Rewards"] }
Details.CHOICE = L["+ a choice of %d items"]
Details.CLOSE = L["Click or Escape to close"]

local card

local function pick(ok, ...) if ok then return ... end end
local function call(fn, ...)
    if type(fn) == "function" then return pick(pcall(fn, ...)) end
end
local function plain(v) return type(v) == "string" and not (issecretvalue and issecretvalue(v)) and v ~= "" end

-- Rewards as text lines: money, experience, items given. Choice items are only
-- counted, because the game reads those from its selected quest, which addon
-- code shouldn't change.
function Details.Rewards(id)
    local out = {}
    local money = call(GetQuestLogRewardMoney, id)
    if type(money) == "number" and money > 0 then out[#out + 1] = DUI.MoneyString(money) end
    local xp = call(GetQuestLogRewardXP, id)
    if type(xp) == "number" and xp > 0 then
        out[#out + 1] = (type(BreakUpLargeNumbers) == "function" and BreakUpLargeNumbers(xp) or tostring(xp)) .. " XP"
    end
    local n = call(GetNumQuestLogRewards, id)
    for i = 1, (type(n) == "number" and n or 0) do
        local name, icon, count = call(GetQuestLogRewardInfo, i, id)
        if plain(name) then
            local line = name
            if type(icon) == "number" or plain(icon) then line = ("|T%s:%d|t %s"):format(icon, Details.ICON, line) end
            if type(count) == "number" and count > 1 then line = line .. " x" .. count end
            out[#out + 1] = line
        end
    end
    local choices = call(GetNumQuestLogChoices, id)
    if type(choices) == "number" and choices > 0 then out[#out + 1] = Details.CHOICE:format(choices) end
    return out
end

-- Every line on the card, top to bottom: { text, size, color, gapBefore }.
function Details.Lines(q)
    local look = ns.Tracker.Look()
    local lines = {}
    local function add(text, size, color, gap) lines[#lines + 1] = { text = text, size = size, color = color, gap = gap or 0 } end
    local r, g, b = ns.Look.TitleColor(look, q)
    add(q.title, Details.SIZES.title, { r, g, b })
    add(ns.Look.LevelLine(q), Details.SIZES.sub, Details.GREY, 2)
    local text = call(GetQuestLogQuestText, q.logIndex)
    if plain(text) then add(text, Details.SIZES.text, Details.TEXT, Details.GAP) end
    if #q.objs > 0 then
        add(Details.HEAD.objectives, Details.SIZES.head, { Style.Pop() }, Details.GAP)
        for _, o in ipairs(q.objs) do
            local right = o.kind == "count" and (" " .. o.have .. "/" .. o.need) or (o.kind == "bar" and (" " .. o.pct .. "%")) or ""
            add("\194\183 " .. o.text .. right, Details.SIZES.text, o.done and Details.DONE or Details.TEXT, 2)
        end
    end
    local rewards = Details.Rewards(q.id)
    if #rewards > 0 then
        add(Details.HEAD.rewards, Details.SIZES.head, { Style.Pop() }, Details.GAP)
        for _, line in ipairs(rewards) do add(line, Details.SIZES.text, Details.TEXT, 2) end
    end
    add(Details.CLOSE, Details.SIZES.sub, Details.GREY, Details.GAP)
    return lines
end

local function build()
    card = CreateFrame("Button", "DaylightUIQuestDetails", UIParent)
    DUI.Movers.FollowScale(card)
    card:SetSize(Details.WIDTH, 60)
    card:SetFrameStrata("MEDIUM")
    card:SetClampedToScreen(true)
    Style.Shell(card, { window = true })
    card.texts = {}
    card:SetScript("OnClick", function() Details.Close() end)
    card:Hide()
    DUI.Motion.Window(card, 6)
    -- Controller buttons, matching the game's quest log popup (QuestMapFrame.lua
    -- QuestLogPopupDetailMixin:SetupGamepad): X focuses the quest, Y opens the quest
    -- menu (the tracker's right-click menu), B closes.
    card.padKeys = {
        { key = "X", label = CONTEXT_ACTION_LABEL_FOCUS or L["Focus"], run = function() ns.Clicks.Focus(card.quest) end,
          when = function() return card.quest ~= nil end },
        { key = "Y", label = CONTEXT_ACTION_LABEL_OPTIONS or L["Options"], run = function() ns.Clicks.Menu(card.quest, card) end,
          when = function() return card.quest ~= nil end },
    }
    card.padSelect = function() return false end   -- A does nothing here, same as the game's
    Details.card = card
end

function Details.Show(q)
    if not card then build() end
    card.questID, card.quest = q.id, q
    local width = Details.WIDTH - 2 * Details.PAD
    local y = Details.PAD
    local lines = Details.Lines(q)
    for i, l in ipairs(lines) do
        local fs = card.texts[i]
        if not fs then
            -- Tracker font, so its ruler (Tracker.Measure) gives the heights.
            fs = Style.Text(card, l.size, "LEFT", ns.MEDIA.font)
            fs:SetWordWrap(true)
            card.texts[i] = fs
        end
        Style.SetTextSize(fs, l.size)
        fs:SetWidth(width)
        fs:SetText(l.text)
        fs:SetTextColor(l.color[1], l.color[2], l.color[3])
        y = y + l.gap
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", card, "TOPLEFT", Details.PAD, -y)
        fs:Show()
        y = y + math.max(1, ns.Tracker.Measure(l.text, l.size, width))
    end
    for i = #lines + 1, #card.texts do card.texts[i]:Hide() end
    card:SetHeight(y + Details.PAD)
    -- Next to the list, clear of the item column, like the quest tooltip.
    card:ClearAllPoints()
    card:SetPoint("TOPRIGHT", ns.Tracker.view, "TOPLEFT", -ns.Clicks.TIP_GAP, 0)
    card:Show()
end

function Details.Close()
    if card then DUI.Motion.Vanish(card) end
end

-- Quest details menu entry: opens the card, or closes it if it already shows that quest.
function Details.Toggle(q)
    if card and DUI.Motion.Shown(card) and card.questID == q.id then return Details.Close() end
    Details.Show(q)
end

-- A quest leaving the log closes its card.
function Details.OnRemoved(id)
    if card and card.questID == id then Details.Close() end
end
