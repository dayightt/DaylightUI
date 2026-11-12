-- Gear page: same slot look as the character window (Character/Slots.lua), eight per
-- side with weapons below, their model in the middle, and a footer with average item
-- level. Plain tiles, since someone else's items can't be used and nothing of the
-- game's needs borrowing. A slot that can take a permanent enchant but has none says so
-- in the warn color. Item links arrive late (about a second after INSPECT_READY), so the
-- window refills (Insp.Refill) and newly filled slots fade in.

local _, DUI = ...
DUI.Inspect = DUI.Inspect or {}
local ns = DUI.Inspect
local L = DUI.L
local Style = DUI.Style

local Page = {}
ns.GearPage = Page

Page.EDGE, Page.TOP, Page.ROW, Page.COL, Page.GAP = 16, 12, 46, 176, 8
Page.FOOT_Y = 14   -- item level line, up from the page's bottom

-- Slots that take a permanent enchant (enchanting, plus head, leg and shoulder
-- enchants); empty ones show "No enchant".
ns.ENCHANTABLE = { Head = true, Shoulder = true, Back = true, Chest = true, Wrist = true, Hands = true,
    Legs = true, Feet = true, MainHand = true, SecondaryHand = true, Ranged = true }

local function C() return DUI.Char end

local function each(fn)
    local Gear = C().Gear
    for _, list in ipairs({ Gear.LEFT, Gear.RIGHT, Gear.BOTTOM }) do
        for i, key in ipairs(list) do fn(key, i, list) end
    end
end

-- The game's item tooltip for the slot, with the Shift compare like the game.
function Page.Tip(h)
    local unit = ns.Window.unit
    local e = h.entry
    if not (unit and e and e.id and not e.empty and GameTooltip) then return end
    GameTooltip:SetOwner(h, "ANCHOR_RIGHT")
    GameTooltip:SetInventoryItem(unit, e.id)
    if type(IsModifiedClick) == "function" and IsModifiedClick("COMPAREITEMS")
        and type(GameTooltip_ShowCompareItem) == "function" then
        GameTooltip_ShowCompareItem(GameTooltip)
    end
    GameTooltip:Show()
end

local function leave(h)
    h.ring:Hide()
    if GameTooltip and GameTooltip:GetOwner() == h then GameTooltip:Hide() end
end

function Page.Build(page)
    local Slots = C().Slots
    page.slots = {}
    each(function(key, _, list)
        local side = list == C().Gear.RIGHT and "right" or "left"
        local h = Slots.Make(page, key, side, nil, page.slots)
        h:EnableMouse(true)
        h.UpdateTooltip = Page.Tip   -- the game's tooltip re-asks on Shift
        h:SetScript("OnEnter", function(self)
            self.ring:SetShown(self.entry ~= nil and not self.entry.empty)
            Page.Tip(self)
        end)
        h:SetScript("OnLeave", leave)
        -- Shift links, Ctrl tries it on: the game's modified clicks.
        h:SetScript("OnMouseUp", function(self)
            local unit, e = ns.Window.unit, self.entry
            if not (unit and e and e.id and not e.empty) then return end
            DUI.Win.Parts.ItemClick(function() return GetInventoryItemLink(unit, e.id) end)
        end)
    end)
    page.model = ns.Model.Build(page)
    page.foot = CreateFrame("Frame", nil, page)
    page.level = Style.Text(page.foot, Style.SIZE.head, "LEFT")
    page.levelLabel = Style.Text(page.foot, Style.SIZE.small, "LEFT")
    Style.InkText(page.levelLabel, "LABEL")
    page.note = Style.Text(page, Style.SIZE.body, "CENTER")
    Style.InkText(page.note, "LABEL")
    page.note:SetText(L["No gear yet."])
    page.note:Hide()
    Page.Place(page)
end

function Page.Place(page)
    local Slots, Gear = C().Slots, C().Gear
    local W = ns.Window.W
    local E, T, R = Page.EDGE, Page.TOP, Page.ROW
    local rightX = W - E - Page.COL
    each(function(key, i, list)
        local h = page.slots[key]
        h:ClearAllPoints()
        if list == Gear.BOTTOM then
            local n = #Gear.BOTTOM
            local w = math.floor((W - 2 * E - (n - 1) * Page.GAP) / n)
            Slots.Layout(h, w, true)
            h:SetPoint("TOPLEFT", page, "TOPLEFT", E + (i - 1) * (w + Page.GAP), -T - 8 * R)
        else
            Slots.Layout(h, Page.COL, true)
            h:SetPoint("TOPLEFT", page, "TOPLEFT", list == Gear.LEFT and E or rightX, -T - (i - 1) * R)
        end
    end)
    local mx = E + Page.COL + Page.GAP
    page.model:ClearAllPoints()
    page.model:SetPoint("TOPLEFT", page, "TOPLEFT", mx, -T)
    page.model:SetSize(rightX - Page.GAP - mx, 8 * R - (R - Slots.ICON))
    page.note:ClearAllPoints()
    page.note:SetPoint("CENTER", page.model, "CENTER", 0, 0)
    page.foot:ClearAllPoints()
    page.foot:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", E, Page.FOOT_Y)
    page.foot:SetSize(W - 2 * E, Style.SIZE.head + 4)
    page.level:ClearAllPoints()
    page.level:SetPoint("BOTTOMLEFT", page.foot, "BOTTOMLEFT", 0, 0)
    page.levelLabel:ClearAllPoints()
    page.levelLabel:SetPoint("BOTTOMLEFT", page.level, "BOTTOMRIGHT", 6, 1)
end

-- A slot that just filled (a late link, a new player) fades in, FAST.
local function arrive(h)
    local M = DUI.Motion
    M.Fade(h.icon, 0, 1, M.FAST)
    M.Fade(h.name, 0, 1, M.FAST)
    M.Fade(h.line, 0, 1, M.FAST)
end

local function paint(h, key, e)
    local Slots = C().Slots
    local missing = not e.empty and not e.enchant and ns.ENCHANTABLE[key] == true
    if missing then
        local copy = {}
        for k, v in pairs(e) do copy[k] = v end
        copy.enchant = L["No enchant"]
        e = copy
    end
    Slots.Paint(h, e, { itemLevel = true })
    if missing then
        Style.InkText(h.enchant, "WARN")
    else
        h.enchant:SetTextColor(Slots.ENCHANT[1], Slots.ENCHANT[2], Slots.ENCHANT[3])
    end
end

function Page.Fill(page)
    local unit = ns.Window.unit
    if not unit then return end
    local Gear = C().Gear
    local all = Gear.All(nil, unit)
    -- Who is shown: their guid, or the unit when the guid is secret (then never compared).
    -- Insp.Changed clears it on close, so every open dresses the model fresh.
    local guid = UnitGUID(unit)
    if issecretvalue and issecretvalue(guid) then guid = nil end
    local who = guid or ("unit:" .. unit)
    local same = page.unitShown == who
    local any, changed = false, false
    each(function(key)
        local h, e = page.slots[key], all[key]
        local was = h.entry and not h.entry.empty and h.entry.name or nil
        local now = not e.empty and e.name or nil
        if not e.empty then any = true end
        if was ~= now then changed = true end
        paint(h, key, e)
        if page:IsVisible() and not e.empty and (not same or was ~= e.name) and page.unitShown then arrive(h) end
    end)
    local sum = Gear.Summary(all, unit)
    -- Someone new: their average counts up from zero while their gear fades in; for the
    -- same player, late links count from the previous value.
    local M, fmt = DUI.Motion, function(n) return n and tostring(n) or "" end
    if not same and page:IsVisible() and sum.level then
        M.CountTo(page.level, nil, fmt)
        M.CountTo(page.level, 0, fmt)
        M.CountTo(page.level, sum.level, fmt, M.SLOW)
    else
        M.CountTo(page.level, sum.level, fmt)
    end
    Style.InkText(page.level, "pop")
    page.levelLabel:SetText(sum.level and L["average item level"] or "")
    page.note:SetShown(not any)
    if not same then
        page.unitShown = who
        ns.Model.SetUnit(unit)
    elseif changed then
        ns.Model.Dress(unit)   -- late links or a swap: same player, update gear on the model
    end
end

-- Lift-in reading order: down the left, the model, down the right, weapons, footer.
function Page.Pieces(page)
    local Gear = C().Gear
    local out = {}
    for _, key in ipairs(Gear.LEFT) do out[#out + 1] = page.slots[key] end
    out[#out + 1] = page.model
    for _, key in ipairs(Gear.RIGHT) do out[#out + 1] = page.slots[key] end
    for _, key in ipairs(Gear.BOTTOM) do out[#out + 1] = page.slots[key] end
    out[#out + 1] = page.foot
    return out
end

ns.PAGES[#ns.PAGES + 1] = { id = "gear", text = CHARACTER or L["Character"], Build = Page.Build, Fill = Page.Fill,
    pieces = Page.Pieces }
