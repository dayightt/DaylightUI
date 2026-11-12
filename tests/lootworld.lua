-- A fake LootFrame (the game's Blizzard_UIPanels_Game/Mainline/LootFrame.xml, .lua
-- and ScrollingFlatPanel.xml), only what its skin touches: the pieces by their
-- keys, a list of pooled rows, and what LootFrameElementMixin:Init writes to a row.
-- Its window logic isn't copied.
local stub = require("stub")

local LW = {}
local ROW_H, SPACING, PAD = 46, 2, 6   -- ScrollBoxElementHeight, Spacing, Pad

local function box(parent)
    local b = CreateFrame("Frame", nil, parent)
    b.rows, b.callbacks = {}, {}
    b.ScrollTarget = CreateFrame("Frame", nil, b)
    b.ScrollTarget:SetAllPoints(b)
    function b:ForEachFrame(fn) for _, r in ipairs(self.rows) do fn(r) end end
    function b:RegisterCallback(event, fn, owner)
        self.callbacks[event] = self.callbacks[event] or {}
        self.callbacks[event][owner] = fn
    end
    function b:TriggerEvent(event, ...)
        for owner, fn in pairs(self.callbacks[event] or {}) do fn(owner, ...) end
    end
    return b
end

-- LootFrameItemElementTemplate. money = LootFrameMoneyElementTemplate, with no
-- quality tag and its text a different size.
local function row(parent, money)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(157, ROW_H)
    r.Item = CreateFrame("Button", nil, r)
    r.Item:SetSize(37, 37)
    r.Item:SetPoint("TOPLEFT", r, "TOPLEFT", 5, -4)
    r.Item.icon = r.Item:CreateTexture()
    r.Item.icon:SetAllPoints(r.Item)
    r.Item.IconBorder = r.Item:CreateTexture()
    r.Item.Count = r.Item:CreateFontString()
    r.NameFrame = r:CreateTexture(nil, "BACKGROUND")
    r.BorderFrame = r:CreateTexture(nil, "BORDER")
    r.IconQuestTexture = r:CreateTexture(nil, "OVERLAY")
    r.HighlightNameFrame = r:CreateTexture(nil, "OVERLAY")
    r.PushedNameFrame = r:CreateTexture(nil, "OVERLAY")
    if not money then
        r.QualityStripe = r:CreateTexture(nil, "BACKGROUND")
        r.QualityText = r:CreateFontString()
    end
    -- The game's own per-row fade in (LootFrame.xml: 0.1 s, alpha 0 to 1,
    -- setToFinalAlpha), played at the end of every Init.
    r.ShowAnim = r:CreateAnimationGroup()
    r.ShowAnim:CreateAnimation("Alpha")
    r.Text = r:CreateFontString()
    r.Text:SetSize(money and 93 or 150, money and 38 or 30)
    r.Text:SetPoint("TOPLEFT", r.Item, "TOPRIGHT", 8, -8)
    r.Item:SetScript("OnEnter", function() r.HighlightNameFrame:Show() end)
    r.Item:SetScript("OnLeave", function() r.HighlightNameFrame:Hide() end)
    function r:GetSlotIndex() return self.slot end
    function r:GetQuality() return self.quality end
    -- The fake game has no layout: where the list puts a row, and (outside snaps,
    -- which measure with the real fonts) how tall a name is.
    function r:GetRect() return 300, 400, 204, ROW_H end
    if not stub.measure then
        function r.Text:GetStringHeight() return #(self:GetText() or "") > 30 and 30 or 15 end
    end
    return r
end

local function info(slot) return LW.slots[slot] end

function LW.Install()
    Enum.LootSlotType = { None = 0, Item = 1, Money = 2, Currency = 3 }
    _G.ScrollBoxListMixin = _G.ScrollBoxListMixin or {}
    _G.ScrollBoxListMixin.Event = _G.ScrollBoxListMixin.Event
        or { OnUpdate = "OnUpdate", OnInitializedFrame = "OnInitializedFrame" }
    _G.GOLD_AMOUNT, _G.SILVER_AMOUNT, _G.COPPER_AMOUNT = "%d Gold", "%d Silver", "%d Copper"
    _G.MONEY, _G.CURRENCY, _G.INVTYPE_FINGER, _G.INVTYPE_WRIST = "Money", "Currency", "Finger", "Wrist"
    LW.slots = {}
    LW.pool = {}
    _G.GetNumLootItems = function() return #LW.slots end
    _G.GetLootSlotInfo = function(slot)
        local s = info(slot)
        if s then return s.icon, s.name, s.count or 1, nil, s.quality, false, false, nil, false, s.money end
    end
    _G.GetLootSlotType = function(slot)
        local s = info(slot)
        if not s then return Enum.LootSlotType.None end
        return s.money and Enum.LootSlotType.Money or s.currency and Enum.LootSlotType.Currency
            or Enum.LootSlotType.Item
    end
    _G.GetLootSlotLink = function(slot)
        local s = info(slot)
        return s and s.link or nil
    end
    _G.C_Item = _G.C_Item or {}
    local words = {
        ["item:1"] = { "Armor", "Miscellaneous", "INVTYPE_FINGER", 4, 0 },
        ["item:2"] = { "Armor", "Mail", "INVTYPE_WRIST", 4, 3 },
        ["item:3"] = { "Tradeskill", "Cloth", "", 7, 5 },
    }
    _G.C_Item.GetItemInfoInstant = function(link)
        local w = words[link]
        if w then return 1, w[1], w[2], w[3], 134400, w[4], w[5] end
    end
    _G.C_Item.GetItemQualityColor = function(q)
        local c = ({ [0] = { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0.64, 0.21, 0.93 } })[q]
        if c then return c[1], c[2], c[3] end
    end

    local f = CreateFrame("Frame", "LootFrame", UIParent)
    f:SetSize(220, 290)
    f.panelMaxHeight = 290
    f:SetPoint("LEFT", UIParent, "LEFT", 300, 100)
    f:SetFrameStrata("HIGH")
    f:Hide()
    f.NineSlice = CreateFrame("Frame", nil, f)
    f.Bg = f:CreateTexture()
    f.TitleContainer = CreateFrame("Frame", nil, f)
    f.TitleContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.TitleContainer:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    f.TitleContainer:SetHeight(20)
    f.TitleContainer.TitleText = f.TitleContainer:CreateFontString()
    f.TitleContainer.TitleText:SetText("Items")
    f.ClosePanelButton = CreateFrame("Button", nil, f)
    f.ClosePanelButton:SetSize(20, 20)
    f.ClosePanelButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    f.ScrollBox = box(f)
    f.ScrollBox:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -22)
    f.ScrollBox:SetPoint("BOTTOM", f, "BOTTOM", 0, 4)
    f.ScrollBox:SetWidth(216)
    return f
end

-- The game's Init on a row: what it writes each time the row is filled.
function LW.Fill(r, slot)
    local s = info(slot)
    r.slot, r.quality = slot, s.quality or 1
    r.Text:SetText(s.name)
    local rq, gq, bq = C_Item.GetItemQualityColor(r.quality)
    r.Text:SetVertexColor(rq, gq, bq)
    r.NameFrame:SetVertexColor(rq, gq, bq)
    r.Item.icon:SetTexture(s.icon or 134400)
    r.Item.IconBorder:SetVertexColor(rq, gq, bq)
    r.Item.IconBorder:Show()
    r.Item.Count:SetText(s.count and s.count > 1 and tostring(s.count) or "")
    if r.QualityText then r.QualityText:SetText("Quality" .. r.quality) end
    r.ShowAnim:Play()
end

-- LOOT_OPENED, in LootFrameMixin:Open's order. The list is filled while the window
-- is hidden, only as many rows as its last height holds, then it shows. Only then
-- does Resize give it this corpse's height, and the list makes the rest of its rows
-- as it grows (ScrollBox OnSizeChanged). ShowAnim, the window's own 0.1 s fade in,
-- plays from there.
function LW.Open(f, slots, autoLoot)
    LW.slots = slots
    f.isAutoLoot = autoLoot or false
    local b = f.ScrollBox
    b.rows = {}
    local function add(i)
        local s = slots[i]
        local key = s.money and "money" or "item"
        LW.pool[key] = LW.pool[key] or {}
        local r = table.remove(LW.pool[key]) or row(b.ScrollTarget, s.money)
        r.poolKey = key
        r:ClearAllPoints()
        local y = -PAD - (i - 1) * (ROW_H + SPACING)
        r:SetPoint("TOPLEFT", b.ScrollTarget, "TOPLEFT", PAD, y)
        r:SetPoint("TOPRIGHT", b.ScrollTarget, "TOPRIGHT", -PAD, y)
        r:SetHeight(ROW_H)
        r:Show()
        LW.Fill(r, i)
        b.rows[i] = r
        b:TriggerEvent("OnInitializedFrame", r, {})
    end
    local fits = math.max(1, math.floor((f:GetHeight() - 46 + SPACING) / (ROW_H + SPACING)))
    for i = 1, math.min(#slots, fits) do add(i) end
    b:TriggerEvent("OnUpdate")
    f:Show()
    local n = #slots
    f:SetHeight(math.min(math.max(n, 1) * ROW_H + math.max(n - 1, 0) * SPACING + 26 + 20, f.panelMaxHeight))
    for i = fits + 1, n do add(i) end
    b:TriggerEvent("OnUpdate")
end

-- LOOT_SLOT_CLEARED: a click took it, so the game hides the row at once.
function LW.Take(f, slot)
    stub.FireEvent("LOOT_SLOT_CLEARED", slot)
    for _, r in ipairs(f.ScrollBox.rows) do
        if r.slot == slot then r:Hide() end
    end
end

function LW.Close(f)
    f:Hide()
    for _, r in ipairs(f.ScrollBox.rows) do
        r:Hide()
        table.insert(LW.pool[r.poolKey], r)
    end
end

-- The usual corpse: coin, an epic, a green, and three cloth.
function LW.Corpse()
    return {
        { name = "3 Silver\n24 Copper", money = true, quality = 0, icon = 133784 },
        { name = "Dawnforged Signet", link = "item:1", quality = 4, icon = 133345 },
        { name = "Ironbark Bracers", link = "item:2", quality = 2, icon = 132602 },
        { name = "Linen Cloth", link = "item:3", quality = 1, count = 3, icon = 132889 },
    }
end

return LW
