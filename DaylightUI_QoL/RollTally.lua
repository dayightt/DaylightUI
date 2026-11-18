-- Loot roll counts: on each of the game's loot roll popups, how many players
-- picked Need, Greed or Pass, as a count in the corner of its button
-- (rollCounts), and who they are, then who hasn't picked yet, in the button's
-- tooltip (rollTooltip). The tooltip's sections are adapted from
-- BetterGroupLoot (MIT, see RollTally-LICENSE.txt); the data is RollData.lua.
--
-- It adds to the game's popups and never replaces, moves or resizes them, so
-- the loot roll skin and the "Loot Rolls" handle keep them, and it works on the
-- plain popups too. What it adds lives in its own tables, never in fields on
-- the game's frames. The only hooks are OnShow on each popup (one opened from
-- the queue sends no event) and OnEnter on each button, set once. Popups are
-- looked at a frame after the loot roll and loot history events.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style = DUI.Style
local RollData = ns.RollData

local Rolls = {
    COUNT_AT = { "BOTTOMRIGHT", "BOTTOMRIGHT", 2, -2 },   -- the count's point, the button's, offset
    EVENTS = { "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS", "LOOT_HISTORY_UPDATE_DROP",
        "LOOT_HISTORY_UPDATE_ENCOUNTER", "LOOT_HISTORY_CLEAR_HISTORY", "PLAYER_ENTERING_WORLD" },
    -- A popup's buttons by kind, under its LootButtonContainer.
    BUTTONS = { need = "NeedButton", greed = "GreedButton", transmog = "TransmogButton", pass = "PassButton" },
    -- The game's own word for each section a button lists.
    WORDS = { need = "NEED", greed = "GREED", pass = "PASS" },
}
ns.RollTally = Rolls
ns.features[#ns.features + 1] = Rolls

local mod, soon
local paired = {}                                       -- rollID -> drop key, while its popup is open
local buttonsOf = setmetatable({}, { __mode = "k" })    -- popup -> its buttons by kind, once hooked
local placeOf = setmetatable({}, { __mode = "k" })      -- button -> { popup, kind }
local tallyOf = setmetatable({}, { __mode = "k" })      -- popup -> its Tally, nil without roll data
local counts = setmetatable({}, { __mode = "k" })       -- button -> its count text, once it had one
local lastAdded                                         -- the button whose tooltip got lines last

local function on(key) return mod ~= nil and mod.db ~= nil and mod.db[key] ~= false end
function Rolls.Counting() return on("rollCounts") end
function Rolls.Listing() return on("rollTooltip") end
function Rolls.Active() return Rolls.Counting() or Rolls.Listing() end

local function owns(b)
    local tip = GameTooltip
    return tip ~= nil and tip:IsShown() and tip:IsOwned(b)
end

-- ---------------------------------------------------------------------
-- What it draws (real popups and the samples alike)
-- ---------------------------------------------------------------------

-- A count is made the first time its button has one, on a frame of its own
-- above the button's art.
local function countOf(b)
    local fs = counts[b]
    if fs then return fs end
    local over = CreateFrame("Frame", nil, b)
    over:SetAllPoints(b)
    over:SetFrameLevel(b:GetFrameLevel() + 2)
    fs = Style.Text(over, Style.SIZE.small, "CENTER")
    local at = Rolls.COUNT_AT
    fs:SetPoint(at[1], b, at[2], at[3], at[4])
    counts[b] = fs
    return fs
end

-- buttons: kind -> button. tally: a Tally, or nil without roll data. Nobody
-- picked, no data, or counts off: blank, never a 0.
function Rolls.PaintCounts(buttons, tally)
    for kind, b in pairs(buttons) do
        local section = Rolls.Counting() and tally and tally[RollData.SECTION_OF_BUTTON[kind]]
        local n = section and section.total or 0
        if n > 0 or counts[b] then
            local fs = countOf(b)
            fs:SetText(n > 0 and tostring(n) or "")
            Style.InkText(fs, "VALUE")
        end
    end
end

-- The game's off-spec wording, a format around the name ("%s (Off Spec)", in
-- whatever order the language has). Ours only when the client has none.
local function offSpec()
    local fmt = LOOT_HISTORY_OFF_SPEC_FMT
    if type(fmt) == "string" then
        local rest, n = fmt:gsub("%%s", "")
        if n == 1 and not rest:find("%", 1, true) then return fmt end
    end
    return L["%s (off spec)"]
end

local function rgb(c) return c[1], c[2], c[3] end

-- One section: its word and how many, then a row each, cut with "+N more".
-- The name is in its class color, an Off-spec Need's tag muted around it, the
-- roll on the right; the winner's row all in the good color.
local function addSection(tip, word, section)
    if section.total == 0 then return end
    local INK, Hex = Style.INK, DUI.Win.Parts.Hex
    tip:AddLine(" ")
    tip:AddLine(string.format("%s (%d)", word, section.total), rgb(INK.LABEL))
    for _, row in ipairs(section.rows) do
        local name = row.name
        if not row.winner then name = Hex({ Style.ClassTextColor(row.class) }) .. name .. "|r" end
        if row.choice == "offspec" then
            local off = Hex(INK.OFF)
            if row.winner then name = Hex(INK.GOOD) .. name .. "|r" end
            name = off .. string.format(offSpec(), name .. off) .. "|r"
        end
        if row.isSelf then name = string.format(L["%s (you)"], name) end
        local left = row.winner and INK.GOOD or INK.TEXT
        local right = row.winner and INK.GOOD or INK.VALUE
        tip:AddDoubleLine(name, row.roll and tostring(row.roll) or "", left[1], left[2], left[3], rgb(right))
    end
    if section.more > 0 then tip:AddLine(string.format(L["+%d more"], section.more), rgb(INK.OFF)) end
end

-- The Tally for a button of `kind`, under the tooltip's own lines: its
-- section, then the players yet to pick. tally nil: no roll data yet.
function Rolls.AddLines(tip, kind, tally)
    if not Rolls.Listing() then return end
    if not tally then
        tip:AddLine(" ")
        tip:AddLine(L["No roll data yet."], rgb(Style.INK.OFF))
        return
    end
    local key = RollData.SECTION_OF_BUTTON[kind]
    addSection(tip, _G[Rolls.WORDS[key]], tally[key])
    addSection(tip, L["Undecided"], tally.undecided)
end

-- ---------------------------------------------------------------------
-- The game's popups
-- ---------------------------------------------------------------------

local function addLines(b)
    local place = placeOf[b]
    if not (place and GameTooltip:IsOwned(b)) then return end
    lastAdded = b
    Rolls.AddLines(GameTooltip, place.kind, tallyOf[place.popup])
    GameTooltip:Show()
end

-- An open tooltip is built again, the button's own lines first. The client
-- may or may not run the hooks with GetScript's handler, so the lines are
-- added here only if that didn't.
local function refreshTooltip(buttons)
    for _, b in pairs(buttons) do
        if owns(b) then
            local enter = b:GetScript("OnEnter")
            lastAdded = nil
            if enter then enter(b, false) end
            if lastAdded ~= b then addLines(b) end
        end
    end
end

-- A popup the game reuses for the next roll shows nothing of the last one
-- until it has its own.
local function onShow(popup)
    tallyOf[popup] = nil
    Rolls.PaintCounts(buttonsOf[popup], nil)
    soon()
end

local function adopt(popup)
    if buttonsOf[popup] then return end
    local buttons, box = {}, popup.LootButtonContainer
    for kind, key in pairs(Rolls.BUTTONS) do
        local b = type(box) == "table" and box[key]
        if type(b) == "table" and b.HookScript then
            buttons[kind] = b
            placeOf[b] = { popup = popup, kind = kind }
            b:HookScript("OnEnter", function(self) DUI.SafeCall(addLines, self) end)
        end
    end
    buttonsOf[popup] = buttons
    popup:HookScript("OnShow", function(self) DUI.SafeCall(onShow, self) end)
end

-- The popups on screen, each adopted the first time it's seen.
local function readPopups()
    local list, met = {}, {}
    local function visit(popup)
        if met[popup] or type(popup) ~= "table" or not popup.HookScript or popup:IsForbidden() then return end
        met[popup] = true
        adopt(popup)
        local rollID = popup.rollID
        if popup:IsShown() and type(rollID) == "number" and not DUI.IsSecret(rollID) then
            local link = type(GetLootRollItemLink) == "function" and GetLootRollItemLink(rollID) or nil
            if DUI.IsSecret(link) then link = nil end
            list[#list + 1] = { frame = popup, rollID = rollID, link = link, itemID = RollData.ItemID(link) }
        end
    end
    local i = 1
    while _G["GroupLootFrame" .. i] do
        visit(_G["GroupLootFrame" .. i])
        i = i + 1
    end
    local c = _G.GroupLootContainer
    if type(c) == "table" and type(c.rollFrames) == "table" then
        for _, popup in pairs(c.rollFrames) do visit(popup) end
    end
    return list
end

-- Pairs each popup on screen with its drop and draws its Tally. With both
-- switches off it reads nothing, and what was drawn goes blank.
function Rolls.Scan()
    if not Rolls.Active() then
        paired = {}
        for popup, buttons in pairs(buttonsOf) do
            tallyOf[popup] = nil
            Rolls.PaintCounts(buttons, nil)
        end
        return
    end
    local popups = readPopups()
    if #popups == 0 then return end
    local drops = RollData.Drops()
    paired = RollData.Pair(popups, drops, paired)
    local byKey = {}
    for _, drop in ipairs(drops) do byKey[drop.key] = drop end
    for _, popup in ipairs(popups) do
        local drop = byKey[paired[popup.rollID]]
        local tally = drop and RollData.Tally(drop.rows) or nil
        tallyOf[popup.frame] = tally
        Rolls.PaintCounts(buttonsOf[popup.frame], tally)
        refreshTooltip(buttonsOf[popup.frame])
    end
end

-- Counts take the text color as it is now.
local function repaint()
    for _, fs in pairs(counts) do Style.InkText(fs, "VALUE") end
end

function Rolls.Enable(m)
    mod = m
    if soon then return end
    soon = DUI.Soon(Rolls.Scan)
    for _, event in ipairs(Rolls.EVENTS) do DUI.RegisterEvent(event, soon) end
    DUI.On("StyleChanged", repaint)
    soon()   -- popups already up after a /reload
end

function Rolls.Refresh(m)
    mod = m
    Rolls.Scan()
end
