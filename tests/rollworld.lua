-- A fake of the game's group loot rolls, only what the loot roll skin and the
-- roll counts read: the popups (GroupLootFrame.xml, forever) with their button
-- row, GroupLootContainer's list, the loot roll functions, a loot history to
-- script (tests/blizzard/api/LootHistoryDocumentation.lua), the game's words
-- for the choices, and a GameTooltip that keeps its lines. The game's popup
-- logic isn't copied: a test opens and closes rolls itself.
local stub = require("stub")

local RW = {}

-- Item links: a cloak, the same cloak with a suffix (same item, another link),
-- a sword.
RW.CLOAK = "|cffa335ee|Hitem:21701::::::::60:::::|h[Cloak of the Sleeping Wyrm]|h|r"
RW.CLOAK_OF_THE_BEAR = "|cff0070dd|Hitem:21701::::::1179::60:::::|h[Cloak of the Sleeping Wyrm of the Bear]|h|r"
RW.SWORD = "|cffa335ee|Hitem:21702::::::::60:::::|h[Wyrmfang Blade]|h|r"

RW.POPUPS = 4   -- GroupLootFrame1-4, as in the game's XML
RW.CANT_NEED = "You can't need this item."
local STATE = { NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5 }
local STATE_OF = { need = 0, offspec = 1, transmog = 2, greed = 3, none = 4, pass = 5 }
local WORD = { Need = "Need", Greed = "Greed", Pass = "Pass", Transmog = "Transmog" }
local QUALITY = { [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 } }
-- The game's class colors (RAID_CLASS_COLORS) for the classes the tests roll with.
local CLASSES = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
    ROGUE = { r = 1, g = 0.96, b = 0.41 }, DRUID = { r = 1, g = 0.49, b = 0.04 },
    SHAMAN = { r = 0, g = 0.44, b = 0.87 }, WARLOCK = { r = 0.53, g = 0.53, b = 0.93 },
}

-- A tooltip that keeps its lines: { text, right, color = { r, g, b }, rightColor }.
local function tooltip()
    local tip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
    tip.lines = {}
    function tip:SetOwner(owner, anchor) self.owner, self.anchor, self.lines = owner, anchor, {} end
    function tip:IsOwned(f) return self.owner == f end
    function tip:GetOwner() return self.owner end
    function tip:ClearLines() self.lines = {} end
    -- The tooltip's SetText starts it over with that one line.
    function tip:SetText(text, r, g, b) self.lines = { { text = text, color = { r, g, b } } } end
    function tip:AddLine(text, r, g, b) self.lines[#self.lines + 1] = { text = text, color = { r, g, b } } end
    function tip:AddDoubleLine(left, right, lr, lg, lb, rr, rg, rb)
        self.lines[#self.lines + 1] = { text = left, right = right, color = { lr, lg, lb }, rightColor = { rr, rg, rb } }
    end
    tip:Hide()
    return tip
end

-- A button as the game's template makes it: its art, and its tooltip (the
-- choice's word, and why it's off when it is).
local function button(box, kind)
    local b = CreateFrame("Button", nil, box)
    b:SetSize(32, 32)
    local art, glow = b:CreateTexture(), b:CreateTexture()
    art:SetTexture("dice"); glow:SetTexture("dice glow")
    function b:GetNormalTexture() return art end
    function b:GetHighlightTexture() return glow end
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(_G[string.upper(kind)] or WORD[kind], 1, 1, 1)
        if not self:IsEnabled() then GameTooltip:AddLine(RW.CANT_NEED, 1, 0.1, 0.1) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function() _G.RollOnLoot(b:GetParent():GetParent().rollID, kind) end)
    box[kind .. "Button"] = b
end

local function popup(i)
    local f = CreateFrame("Frame", "GroupLootFrame" .. i, UIParent)
    f:SetSize(277, 67)
    f:SetFrameStrata("DIALOG")
    f.Background = f:CreateTexture(); f.Background:SetTexture("gold frame")
    f.IconFrame = CreateFrame("Button", nil, f)
    f.IconFrame:SetSize(34, 34)
    f.IconFrame.Icon = f.IconFrame:CreateTexture()
    f.IconFrame.Border = f.IconFrame:CreateTexture()
    f.Name = f:CreateFontString()
    f.Timer = CreateFrame("StatusBar", nil, f)
    f.Timer:SetMinMaxValues(0, 60000)
    local box = CreateFrame("Frame", nil, f)
    f.LootButtonContainer = box
    for _, kind in ipairs({ "Need", "Greed", "Pass", "Transmog" }) do button(box, kind) end
    box.TransmogButton:Hide()
    f:Hide()
    return f
end

-- Run from stub.Load's `before`.
function RW.Install()
    Enum.EncounterLootDropRollState = STATE
    _G.NEED, _G.GREED, _G.PASS, _G.TRANSMOG = WORD.Need, WORD.Greed, WORD.Pass, WORD.Transmog
    -- Worded unlike Roll Tally's own fallback, so a test can tell which one shows.
    _G.LOOT_HISTORY_OFF_SPEC_FMT = "%s (Off Spec)"
    -- Copies, so the next test file finds the fake game's own tables.
    local colors = {}
    for k, v in pairs(RAID_CLASS_COLORS) do colors[k] = v end
    for k, v in pairs(CLASSES) do colors[k] = v end
    _G.RAID_CLASS_COLORS = colors
    _G.C_Item = setmetatable({ GetItemQualityColor = function(q)
        local c = QUALITY[q] or { 1, 1, 1 }
        return c[1], c[2], c[3]
    end }, { __index = C_Item })

    RW.rolls, RW.encounters, RW.rollCalls = {}, {}, {}
    _G.GetLootRollItemLink = function(rollID) return RW.rolls[rollID] and RW.rolls[rollID].link end
    -- texture, name, count, quality, bind on pickup
    _G.GetLootRollItemInfo = function(rollID)
        local r = RW.rolls[rollID]
        if r then return 133345, r.link:match("%[(.-)%]"), 1, r.quality or 4, true end
    end
    _G.RollOnLoot = function(...) RW.rollCalls[#RW.rollCalls + 1] = { "RollOnLoot", ... } end
    _G.ConfirmLootRoll = function(...) RW.rollCalls[#RW.rollCalls + 1] = { "ConfirmLootRoll", ... } end
    _G.C_LootHistory = {
        GetAllEncounterInfos = function()
            local out = {}
            for i, e in ipairs(RW.encounters) do out[i] = { encounterID = e.id, encounterName = "Boss " .. e.id } end
            return out
        end,
        GetSortedDropsForEncounter = function(id)
            for _, e in ipairs(RW.encounters) do
                if e.id == id then
                    local out = {}
                    for i, d in ipairs(e.drops) do out[i] = d end
                    return out
                end
            end
        end,
    }

    tooltip()
    local c = CreateFrame("Frame", "GroupLootContainer", UIParent)
    c:SetSize(277, 100)
    c:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 152)
    c.rollFrames = {}
    for i = 1, RW.POPUPS do popup(i) end
end

-- Driving the game -----------------------------------------------------------

function RW.Popup(i) return _G["GroupLootFrame" .. i] end

-- Popup i's button of a kind: "need", "greed", "pass" or "transmog".
function RW.Button(i, kind)
    return RW.Popup(i).LootButtonContainer[kind:sub(1, 1):upper() .. kind:sub(2) .. "Button"]
end

-- A roll starts on popup `frame` (1 by default). queued: it opens from the
-- game's queue, so the popup shows with no event. transmog: Transmog in
-- Greed's place. canNeed false: the Need button is off.
function RW.Open(spec)
    local i = spec.frame or 1
    local f = RW.Popup(i)
    RW.rolls[spec.rollID] = { link = spec.link, quality = spec.quality }
    f.rollID = spec.rollID
    local box = f.LootButtonContainer
    box.GreedButton:SetShown(not spec.transmog)
    box.TransmogButton:SetShown(spec.transmog == true)
    box.NeedButton:SetEnabled(spec.canNeed ~= false)
    GroupLootContainer.rollFrames[i] = f
    f:Show()
    if not spec.queued then stub.FireEvent("START_LOOT_ROLL", spec.rollID, 60000) end
    return f
end

function RW.Close(rollID)
    RW.rolls[rollID] = nil
    for i = 1, RW.POPUPS do
        local f = RW.Popup(i)
        if f.rollID == rollID and f:IsShown() then
            f:Hide()
            GroupLootContainer.rollFrames[i] = nil
        end
    end
    stub.FireEvent("CANCEL_LOOT_ROLL", rollID)
end

-- A drop in the loot history. rolls: { name, class, choice, roll, winner = bool,
-- self = bool, secret = { field = true } }, choice one of need, offspec,
-- transmog, greed, none, pass. Encounters and drops are listed in the order
-- they were first set, as the game lists them.
function RW.SetDrop(encounterID, lootListKey, spec)
    local enc
    for _, e in ipairs(RW.encounters) do if e.id == encounterID then enc = e end end
    if not enc then
        enc = { id = encounterID, drops = {} }
        RW.encounters[#RW.encounters + 1] = enc
    end
    local infos, winner = {}, nil
    for i, r in ipairs(spec.rolls or {}) do
        local info = { playerName = r[1], playerClass = r[2], state = STATE_OF[r[3]], roll = r[4],
            isWinner = r.winner == true, isSelf = r.self == true }
        for field, on in pairs(r.secret or {}) do
            if on then info[field] = stub.Secret(info[field]) end
        end
        infos[i] = info
        if r.winner then winner = info end
    end
    local drop = { lootListKey = lootListKey, itemHyperlink = spec.link, rollInfos = infos, winner = winner,
        allPassed = spec.allPassed == true }
    for i, d in ipairs(enc.drops) do
        if d.lootListKey == lootListKey then
            enc.drops[i] = drop
            return drop
        end
    end
    enc.drops[#enc.drops + 1] = drop
    return drop
end

-- A drop changes: SetDrop, then the game's event.
function RW.UpdateDrop(encounterID, lootListKey, spec)
    RW.SetDrop(encounterID, lootListKey, spec)
    stub.FireEvent("LOOT_HISTORY_UPDATE_DROP", encounterID, lootListKey)
end

-- What a player sees -----------------------------------------------------------

-- The tooltip's lines while it shows.
function RW.Lines()
    if not GameTooltip:IsShown() then return {} end
    local out = {}
    for i, l in ipairs(GameTooltip.lines) do out[i] = l end
    return out
end

function RW.Hover(b)
    stub.MouseEnter(b)
    return RW.Lines()
end

function RW.Unhover(b) stub.MouseLeave(b) end

-- The visible texts drawn on a frame or anything in it, in the order made.
function RW.Texts(frame)
    local out = {}
    local function walk(f)
        for _, c in ipairs(stub.Children(f)) do
            if c:GetObjectType() == "FontString" then
                local t = c:GetText()
                if c:IsVisible() and type(t) == "string" and t ~= "" then out[#out + 1] = c end
            elseif c:IsVisible() then
                walk(c)
            end
        end
    end
    walk(frame)
    return out
end

-- The count a player reads on a button: its text ("" when none) and the text itself.
function RW.Count(b)
    local texts = RW.Texts(b)
    assert(#texts <= 1, "more than one count on a button")
    return texts[1] and texts[1]:GetText() or "", texts[1]
end

-- Text without its color codes.
function RW.Plain(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- The lines as plain text, the right column after " | " when there is one.
function RW.LineTexts(lines)
    local out = {}
    for i, l in ipairs(lines) do
        local text = RW.Plain(l.text)
        if l.right and l.right ~= "" then text = text .. " | " .. RW.Plain(l.right) end
        out[i] = text
    end
    return out
end

return RW
