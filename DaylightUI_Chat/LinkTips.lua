-- Tooltips for item, spell and quest links on mouseover. Placed above the chat
-- panel so it never covers the lines, at the cursor, or at the Tooltip module's
-- anchor, after linkTooltipDelay seconds.
-- Uses the game's EventRegistry callbacks (ChatFrame.OnHyperlinkEnter/Leave),
-- which keep taint out: nothing is hooked or written on the chat frames.
-- Secret links (chat lockdown) are ignored.

local _, ns = ...

local LinkTips = {}
ns.LinkTips = LinkTips

LinkTips.TYPES = { item = true, spell = true, enchant = true, quest = true, talent = true,
                   achievement = true, currency = true, instancelock = true, unit = true }

local shownFor -- chat frame whose link tooltip is showing
local anchoredOn -- panel the tooltip is anchored to
local lifted -- extra offset above the panel for a tall compare tooltip
local waiting -- the hover the delay is waiting on (a fresh table per hover)
local driver -- runs only while a tooltip sits above the chat

local function secret(v) return issecretvalue and issecretvalue(v) end

local function place(tip, y)
    tip:ClearAllPoints()
    tip:SetPoint("BOTTOMLEFT", anchoredOn, "TOPLEFT", 0, ns.Chat.GAP + y)
end

-- The game anchors the "Equipped" compare tooltip to our tooltip's top, so a
-- taller compare would hang down over the chat. Raise the tooltip by the
-- difference. The compare can appear late (Shift), so check each frame while
-- shown and only move on a change.
function LinkTips.Lift()
    local tip = _G.GameTooltip
    if not (anchoredOn and shownFor) or type(tip) ~= "table" or not tip:IsShown()
        or tip:GetOwner() ~= shownFor then
        if driver then driver:Hide() end
        return
    end
    local height = tip:GetHeight()
    if type(height) ~= "number" or secret(height) then return end
    local tallest = height
    for _, shop in ipairs(type(tip.shoppingTooltips) == "table" and tip.shoppingTooltips or {}) do
        local h = shop:IsShown() and shop:GetHeight()
        if type(h) == "number" and not secret(h) and h > tallest then tallest = h end
    end
    local want = tallest - height
    if math.abs(want - lifted) < 1 then return end
    lifted = want
    place(tip, want)
end

function LinkTips.Show(cf, link)
    local tip = _G.GameTooltip
    if type(tip) ~= "table" then return end
    anchoredOn = nil
    if LinkTips.spot == "cursor" then
        tip:SetOwner(cf, "ANCHOR_CURSOR")
    elseif LinkTips.spot == "game" and _G.DaylightUITooltipAnchor then
        -- The Tooltip module's anchor, regardless of its Position setting.
        tip:SetOwner(cf, "ANCHOR_NONE")
        tip:ClearAllPoints()
        tip:SetPoint("BOTTOMRIGHT", _G.DaylightUITooltipAnchor, "BOTTOMRIGHT", 0, 0)
    elseif LinkTips.spot == "game" and type(GameTooltip_SetDefaultAnchor) == "function" then
        GameTooltip_SetDefaultAnchor(tip, cf) -- Tooltip module disabled: use the game's default spot
    else
        tip:SetOwner(cf, "ANCHOR_NONE")
        anchoredOn, lifted = ns.Chat.PanelOf(cf) or cf, 0
        place(tip, 0)
    end
    -- Off: Shift still compares. The game's OnHide resets this for the next tooltip.
    if not LinkTips.compare and type(GameTooltip_SuppressAutomaticCompareItem) == "function" then
        GameTooltip_SuppressAutomaticCompareItem(tip)
    end
    tip:SetHyperlink(link)
    tip:Show()
    shownFor = cf
    if anchoredOn then
        if not driver then
            driver = CreateFrame("Frame")
            driver:SetScript("OnUpdate", LinkTips.Lift)
        end
        driver:Show()
    end
end

function LinkTips.OnEnter(cf, link)
    if not LinkTips.enabled or type(link) ~= "string" or secret(link) then return end
    if not LinkTips.TYPES[string.match(link, "^([^:]+)") or ""] then return end
    local delay = LinkTips.delay or 0
    if delay <= 0 then return LinkTips.Show(cf, link) end
    local hover = {}
    waiting = hover
    C_Timer.After(delay, function()
        if waiting ~= hover then return end
        waiting = nil
        if LinkTips.enabled then LinkTips.Show(cf, link) end
    end)
end

-- Only hide it if it's still ours; another tooltip may have taken it over.
function LinkTips.OnLeave(cf)
    waiting = nil
    local tip = _G.GameTooltip
    if shownFor and shownFor == cf and type(tip) == "table" and tip:GetOwner() == cf then tip:Hide() end
    shownFor, anchoredOn = nil, nil
    if driver then driver:Hide() end
end

function LinkTips.Apply(cfg)
    LinkTips.enabled = cfg.linkTooltips and true or false
    LinkTips.spot = cfg.linkTooltipSpot
    LinkTips.compare = cfg.linkTooltipCompare and true or false
    LinkTips.delay = cfg.linkTooltipDelay
    if LinkTips.registered or not (EventRegistry and EventRegistry.RegisterCallback) then return end
    LinkTips.registered = true
    EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkEnter",
        function(_, cf, link) LinkTips.OnEnter(cf, link) end, LinkTips)
    EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkLeave",
        function(_, cf) LinkTips.OnLeave(cf) end, LinkTips)
end
