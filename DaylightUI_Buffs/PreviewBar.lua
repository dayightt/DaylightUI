-- PreviewBar: /dui buffs test (and DaylightUI's frame preview) draws a sample
-- of known buffs with our own buttons, laid out by the same flow algorithm
-- the client uses for the live bar, so the categorized look can be judged
-- without a raid. The live bar is hidden underneath while it shows.

local _, BL = ...
local DUI = DaylightUI
local L = DUI.L

local W = BL.Widgets
local Layout = BL.Layout

local frame
local pool, active = {}, {}
local TIMER_INTERVAL = 0.1
BL.PREVIEW_SHARE = 0.4 -- fraction of known buffs a preview shows
BL.PREVIEW_MAX = 20 -- capped at this many (a fraction given by name isn't capped)

local function acquire(i)
    local b = pool[i]
    if b then return b end
    b = W.CreateIconButton(frame)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", function(self)
        if not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        local Tips = DUI.Tips
        Tips.Clear()
        Tips.Title(self.entry.name or L["Preview"])
        Tips.Sub(L["Sample buff"])
        local id = BL.Classify.Resolve(self.entry)
        local cat = BL.Categories.Get(id)
        if cat then
            Tips.Line(L["Category"], BL.Categories.Label(id), type(cat.color) == "table" and cat.color or nil)
        end
        Tips.Hint(L["Shift-click: change its category"])
        Tips.Flush(GameTooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        if IsShiftKeyDown() and self.entry and self.entry.name then
            local name = self.entry.name
            W.CategoryMenu(self, BL.Classify.Resolve(self.entry), function(id)
                BL.Classify.Assign(name, id, "preview")
            end)
        end
    end)
    pool[i] = b
    return b
end

local function ensureFrame()
    if frame then return end
    frame = CreateFrame("Frame", "DaylightUIBuffsPreview", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(1, 1)
    frame.accum = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.accum = self.accum + elapsed
        if self.accum < TIMER_INTERVAL then return end
        self.accum = 0
        local now = BL.Clock()
        for _, b in ipairs(active) do
            local e = b.entry
            if e then b:SetTimeLeft(e.timed and (e.expirationTime - now) or nil, e.timed) end
        end
    end)
    frame:Hide()
end

-- The bar's optional background, drawn behind the sample the same way as behind
-- the live bar (same padding, room for times, opacity).
local function sampleBackground(f, s, room)
    local bg = f.background
    if not bg then
        bg = CreateFrame("Frame", nil, f)
        bg:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
        bg:EnableMouse(false)
        DUI.Style.Shell(bg, { borderPx = 2, noBevel = true })
        f.background = bg
    end
    local pad = BL.BACKGROUND_PAD or 6
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", -pad, pad + room)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", pad, -pad)
    bg:SetShown(s.showBackground and true or false)
    local shell = DUI.Style.GetShell(bg)
    if shell then shell.opts.bgAlpha = DUI.Style.BackAlpha(s.backgroundAlphaOwn, s.backgroundAlpha) end
    DUI.Style.LayoutShell(shell)
end

local function render()
    local entries = BL.Preview.Entries()
    if not entries or not BL.DB then
        if frame then frame:Hide() end
        return
    end
    ensureFrame()
    local s = BL.DB.settings
    local size, spacing = s.iconSize, s.spacing
    local height = W.Height(size)
    local room = math.ceil(W.TimeSize(size) / 2) + 1
    local corner = s.growLeft and "TOPRIGHT" or "TOPLEFT"
    local state = { inGroup = IsInGroup(), inRaid = IsInRaid() }

    -- Same inputs the live bar gives the client.
    local clusters = Layout.ClusterEntries(entries, BL.DB.categories, BL.Categories.Order())
    local byKey, groups = {}, {}
    for _, cluster in ipairs(clusters) do
        local cat = BL.Categories.Get(cluster.categoryId)
        local collapsed = Layout.ConsolidateAllowed(cat, s, state) and #cluster.entries >= 2
        byKey[cluster.categoryId] = { entries = cluster.entries, collapsed = collapsed }
        groups[#groups + 1] = {
            key = cluster.categoryId, count = collapsed and 1 or #cluster.entries,
            elementWidth = size, elementHeight = height, elementSpacing = spacing,
            lineSpacing = spacing + room, groupSpacing = s.categoryGap or 0,
        }
    end
    local columns = math.max(1, math.floor(tonumber(s.columns) or 1))
    local flow = Layout.Flow(groups, {
        anchorPoint = corner, horizontal = s.growLeft and Layout.LEFT or Layout.RIGHT, vertical = Layout.DOWN,
        maximumLineSize = columns * (size + spacing),
    })

    frame:ClearAllPoints()
    local holder = BL.Bar and BL.Bar.holder or UIParent
    frame:SetPoint(corner, holder, corner, 0, 0)
    frame:SetScale(DUI.Movers.Scale("buffs.buff"))
    frame:SetSize(math.max(flow.width, size), math.max(flow.height, height))
    sampleBackground(frame, s, room)

    active = {}
    for i, e in ipairs(flow.elements) do
        local group = byKey[e.key]
        local entry = group.entries[e.index]
        local b = acquire(i)
        b.entry = entry
        b:SetIconSize(size, BL.GetSetting("borderPx"))
        b:SetEdgeCategory(e.key)
        b.Icon:SetTexture(entry.icon or W.QUESTION_ICON)
        if group.collapsed then
            b.Count:SetText(#group.entries)
            b.Count:Show()
        else
            b:SetCount(entry.applications)
        end
        b:ClearAllPoints()
        b:SetPoint(corner, frame, corner, e.x, e.y)
        b:Show()
        active[#active + 1] = b
    end
    for i = #flow.elements + 1, #pool do pool[i]:Hide() end
    frame:Show()
end

-- ---------------------------------------------------------------------
-- Sample debuffs: one of each dispel type, edged as the live bar edges them.
-- ---------------------------------------------------------------------

-- The dispel types as the sample's tooltip names them.
local DISPEL_SHOWN = {
    None = L["No dispel type"], Magic = L["Magic"], Curse = L["Curse"], Disease = L["Disease"],
    Poison = L["Poison"], Bleed = L["Bleed"],
}

BL.SAMPLE_DEBUFFS = {
    { name = "Frost Nova", dispel = "Magic", icon = "Interface\\Icons\\Spell_Frost_FrostNova", left = 8 },
    { name = "Curse of Agony", dispel = "Curse", icon = "Interface\\Icons\\Spell_Shadow_CurseOfSargeras", left = 22 },
    { name = "Corrupted Blood", dispel = "Disease", icon = "Interface\\Icons\\Spell_Shadow_CorpseExplode", left = 45 },
    { name = "Deadly Poison", dispel = "Poison", icon = "Interface\\Icons\\Ability_Rogue_DualWeild", left = 12, stacks = 3 },
    { name = "Rend", dispel = "Bleed", icon = "Interface\\Icons\\Ability_Gouge", left = 18 },
    { name = "Weakened Soul", dispel = "None", icon = "Interface\\Icons\\Spell_Holy_AshesToAshes", left = 140 },
}

local dFrame
local dPool, dActive = {}, {}

local function ensureDebuffFrame()
    if dFrame then return end
    dFrame = CreateFrame("Frame", "DaylightUIDebuffsPreview", UIParent)
    dFrame:SetFrameStrata("MEDIUM")
    dFrame:SetSize(1, 1)
    dFrame.accum = 0
    dFrame:SetScript("OnUpdate", function(self, elapsed)
        self.accum = self.accum + elapsed
        if self.accum < TIMER_INTERVAL then return end
        self.accum = 0
        local now = BL.Clock()
        for _, b in ipairs(dActive) do
            if b.expires then b:SetTimeLeft(b.expires - now, true) end
        end
    end)
    dFrame:Hide()
end

local function renderDebuffs()
    if not BL.Preview.Active() or not BL.DB then
        if dFrame then dFrame:Hide() end
        return
    end
    ensureDebuffFrame()
    local s = BL.DB.settings.debuff
    local size, spacing = s.iconSize, s.spacing
    local height = W.Height(size)
    local room = math.ceil(W.TimeSize(size) / 2) + 1
    local corner = s.growLeft and "TOPRIGHT" or "TOPLEFT"
    local columns = math.max(1, math.floor(tonumber(s.columns) or 1))
    local samples = BL.SAMPLE_DEBUFFS
    local flow = Layout.Flow({ {
        key = "debuffs", count = #samples, elementWidth = size, elementHeight = height,
        elementSpacing = spacing, lineSpacing = spacing + room, groupSpacing = 0,
    } }, {
        anchorPoint = corner, horizontal = s.growLeft and Layout.LEFT or Layout.RIGHT, vertical = Layout.DOWN,
        maximumLineSize = columns * (size + spacing),
    })
    dFrame:ClearAllPoints()
    local holder = BL.DebuffBar and BL.DebuffBar.holder or UIParent
    dFrame:SetPoint(corner, holder, corner, 0, 0)
    dFrame:SetScale(DUI.Movers.Scale("buffs.debuff"))
    dFrame:SetSize(math.max(flow.width, size), math.max(flow.height, height))
    sampleBackground(dFrame, s, room)
    -- Soonest first, as the live bar sorts them.
    local order = {}
    for i = 1, #samples do order[i] = samples[i] end
    table.sort(order, function(a, b) return a.left < b.left end)
    local now = BL.Clock()
    dActive = {}
    for i, e in ipairs(flow.elements) do
        local sample = order[e.index]
        local b = dPool[i]
        if not b then
            b = W.CreateIconButton(dFrame)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                local Tips = DUI.Tips
                Tips.Clear()
                Tips.Title(self.sample.name)
                Tips.Sub(L["Sample debuff"])
                Tips.Line(L["Type"], DISPEL_SHOWN[self.sample.dispel] or self.sample.dispel)
                Tips.Flush(GameTooltip)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            dPool[i] = b
        end
        b.sample = sample
        b:SetIconSize(size, BL.GetSetting("borderPx", "debuff"))
        local c = BL.DispelColor(sample.dispel)
        b:SetEdgeColor(DUI.Style.Soften(c[1], c[2], c[3]))
        b.Icon:SetTexture(sample.icon)
        b:SetCount(sample.stacks)
        -- Each preview starts its clocks afresh.
        b.expires = now + sample.left * 60
        b:SetTimeLeft(sample.left * 60, true)
        b:ClearAllPoints()
        b:SetPoint(corner, dFrame, corner, e.x, e.y)
        b:Show()
        dActive[#dActive + 1] = b
    end
    for i = #flow.elements + 1, #dPool do dPool[i]:Hide() end
    dFrame:Show()
end

local function rerender()
    if BL.Preview.Active() then
        render()
        renderDebuffs()
    end
end

BL.On("AURAS_CHANGED", render)
BL.On("AURAS_CHANGED", renderDebuffs)
BL.On("CATEGORIES_CHANGED", rerender)
BL.On("CATEGORY_COLOR_CHANGED", rerender)
BL.On("OVERRIDES_CHANGED", rerender)
BL.On("SETTINGS_CHANGED", rerender)
DUI.RegisterEvent("GROUP_ROSTER_UPDATE", rerender)
-- A font change reaches the preview's text too.
DUI.On("StyleChanged", rerender)

-- DaylightUI's frame preview also shows sample buffs. Ending it only ends the
-- sample if the preview started it. Its test box can leave them out.
local startedByTestMode = false
local function sync()
    local on = DUI.testMode and DUI.TestPartShown("buffs")
    if on and not BL.Preview.Active() then
        startedByTestMode = true
        BL.Preview.Set(BL.PREVIEW_SHARE, BL.PREVIEW_MAX)
    elseif not on and startedByTestMode then
        startedByTestMode = false
        BL.Preview.Set(nil)
    end
end
DUI.On("TestModeChanged", sync)
DUI.RegisterTestPart("buffs", "Buffs", 80)
DUI.On("TestPartChanged", function(key) if key == "buffs" then sync() end end)

-- The tour stop (Tour.lua): sample buffs shown, Shift-click explained.
DUI.Tour.Add("buffs", {
    order = 20,
    title = L["Buffs in groups"],
    text = function()
        return string.format(L["Your buffs sort themselves into groups. A buff in the wrong one? %s it and pick its group."],
            DUI.Tour.Pop(L["Shift-right-click"]))
    end,
    available = function() return BL.module ~= nil end,
    enter = function() DUI.SetTestSolo({ "buffs" }) end,
    leave = function() DUI.SetTestSolo(nil) end,
    part = function() return unpack(active) end,
})
