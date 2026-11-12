-- The player's profession spells as a row of icons under the recipe list: each
-- profession's own (Tailoring, Smelting, Find Minerals, Fishing...), the same ones the
-- game's profession book shows (GetProfessionInfo numSpells from spellOffset, minus
-- passives and future spells). This window replaces that book, so this is where they
-- get dragged to an action bar. Drag picks one up, Shift-click links it. No click to
-- cast: a secure button here would lock the whole window in combat.

local _, DUI = ...
DUI.Craft = DUI.Craft or {}
local ns = DUI.Craft
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win

local Spells = {}
ns.Spells = Spells

Spells.ICON = 28      -- footer height, so the row lines up with the recipe buttons
Spells.GAP = 6
Spells.BORDER = 2     -- icon border, same as the spellbook
Spells.FOOT = 52      -- room under the list (matches Make.FOOT on the recipe side)

local WHITE = "Interface\\Buttons\\WHITE8X8"

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end
local function num(v) return type(v) == "number" and not secret(v) and v or nil end

local function bank()
    return Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
end

-- { { slot, bank, spellID, icon, name } } in the game's profession order.
function Spells.Read()
    local out = {}
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return out end
    if not (C_SpellBook and type(C_SpellBook.GetSpellBookItemInfo) == "function") then return out end
    local spell = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    local list = { GetProfessions() }
    for i = 1, 7 do
        local idx = list[i]
        if idx then
            local _, _, _, _, n, offset = GetProfessionInfo(idx)
            n, offset = num(n), num(offset)
            for k = 1, (n and offset) and math.min(n, 2) or 0 do   -- the game's book shows two at most
                local slot = offset + k
                local info = C_SpellBook.GetSpellBookItemInfo(slot, bank())
                if type(info) == "table" and not info.isPassive and (spell == nil or info.itemType == spell) then
                    out[#out + 1] = { slot = slot, bank = bank(), spellID = num(info.spellID),
                                      icon = info.iconID, name = info.name }
                end
            end
        end
    end
    return out
end

-- Icon

local function makeIcon(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(Spells.ICON, Spells.ICON)
    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("LeftButton")
    b.well = CreateFrame("Frame", nil, b)
    b.well:SetAllPoints(b)
    Style.Shell(b.well, { borderPx = Spells.BORDER, noBevel = true })
    b.icon = b.well:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b.well)
    Style.CropIcon(b.icon)
    b.hover = b.well:CreateTexture(nil, "OVERLAY")
    b.hover:SetTexture(WHITE)
    b.hover:SetAllPoints(b.icon)
    b.hover:SetBlendMode("ADD")
    b.hover:SetVertexColor(1, 1, 1, 0.18)
    b.hover:Hide()
    b:SetScript("OnEnter", function(self) Spells.Enter(self) end)
    b:SetScript("OnLeave", function(self) Spells.Leave(self) end)
    b:SetScript("OnDragStart", function(self) Spells.Drag(self) end)
    b:SetScript("OnClick", function(self, button) Spells.Modified(self, button) end)
    return b
end

function Spells.Enter(b)
    local s = b.spell
    if not s then return end
    Win.Parts.Light(b.hover, true)
    local tip = GameTooltip
    if not tip then return end
    tip:SetOwner(b, "ANCHOR_RIGHT")
    if type(tip.SetSpellBookItem) == "function" then tip:SetSpellBookItem(s.slot, s.bank)
    elseif s.spellID and type(tip.SetSpellByID) == "function" then tip:SetSpellByID(s.spellID) end
    if InCombatLockdown() then
        local w = Style.INK.WARN
        tip:AddLine(L["Clicking and dragging work out of combat."], w[1], w[2], w[3], true)
    else
        local r, g, bl = Style.Accent()
        tip:AddLine(L["Drag it to an action bar."], r, g, bl, true)
    end
    tip:Show()
end

function Spells.Leave(b)
    Win.Parts.Light(b.hover, false)
    if GameTooltip and GameTooltip:IsOwned(b) then GameTooltip:Hide() end
end

-- The game blocks picking up spells from addon code in combat.
function Spells.Drag(b)
    local s = b.spell
    if not s or InCombatLockdown() then return end
    C_SpellBook.PickupSpellBookItem(s.slot, s.bank)
end

-- Shift-click links it, trade skill link first, like the game's book
-- (ProfessionSpellButtonMixin:OnModifiedClick).
function Spells.Modified(b, button)
    local s = b.spell
    if not s or button ~= "LeftButton" or not IsModifiedClick("CHATLINK") then return end
    local insert = ChatFrameUtil and ChatFrameUtil.InsertLink or ChatEdit_InsertLink
    if type(insert) ~= "function" then return end
    local link = C_SpellBook.GetSpellBookItemTradeSkillLink and C_SpellBook.GetSpellBookItemTradeSkillLink(s.slot, s.bank)
    link = link or (C_SpellBook.GetSpellBookItemLink and C_SpellBook.GetSpellBookItemLink(s.slot, s.bank))
    if link then insert(link) end
end

-- The row

-- Under the list (pane), level with the recipe side's footer, with the same faint line
-- above it.
function Spells.Build(pane)
    local row = CreateFrame("Frame", nil, pane)
    row:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", Win.Parts.EDGE, 12)
    row:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -Win.Parts.EDGE, 12)
    row:SetHeight(Spells.ICON)
    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetTexture(WHITE)
    row.line:SetVertexColor(1, 1, 1, 0.06)
    row.line:SetHeight(1)
    row.line:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 10)
    row.line:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 10)
    -- A label before the icons, so it's clear they're spells to drag to a bar.
    row.label = Style.Text(row, Style.SIZE.small, "LEFT")
    row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.label:SetText(L["Abilities"])
    Style.InkText(row.label, "LABEL")
    row.icons = {}
    Spells.row = row
    DUI.RegisterEvent("SPELLS_CHANGED", function() if row:IsVisible() then Spells.Fill() end end)
    return row
end

-- Icons start after the label plus a gap. The label is measured now so a font or
-- language change moves the icons with it.
Spells.LABEL_GAP = 10
function Spells.Lead()
    local label = Spells.row and Spells.row.label
    local w = label and label:GetStringWidth()
    if type(w) ~= "number" or w <= 0 then return 0 end
    return math.ceil(w) + Spells.LABEL_GAP
end

-- As many as fit (Spells.Read rarely returns more than six).
function Spells.Fill()
    local row = Spells.row
    if not row then return end
    local list = Spells.Read()
    local w = row:GetWidth()
    if type(w) ~= "number" or w <= 0 then w = ns.List.W - 2 * Win.Parts.EDGE end
    local lead = Spells.Lead()
    local fit = math.max(0, math.floor((w - lead + Spells.GAP) / (Spells.ICON + Spells.GAP)))
    for i = 1, math.max(#list, #row.icons) do
        local s = i <= fit and list[i] or nil
        local b = row.icons[i]
        if s and not b then
            b = makeIcon(row)
            row.icons[i] = b
        end
        if b then b:SetPoint("LEFT", row, "LEFT", lead + (i - 1) * (Spells.ICON + Spells.GAP), 0) end
        if b then
            b.spell = s
            if s then b.icon:SetTexture(s.icon) end
            b:SetShown(s ~= nil)
        end
    end
    row:SetShown(#list > 0)
end

-- Lift-in pieces.
function Spells.Pieces()
    local out = {}
    for _, b in ipairs(Spells.row and Spells.row.icons or {}) do
        if b:IsShown() then out[#out + 1] = b end
    end
    return out
end
