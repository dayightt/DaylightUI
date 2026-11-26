-- Daylight UI's loot roll window: the game's roll popups keep working underneath,
-- unseen and without the mouse, the way the crowd control alert keeps the game's
-- frame. The game hides its popup the moment you pick and its roll listener
-- can't be switched off without taint, so the window is frames of Daylight UI's
-- own, fed by the game's events, its Loot History and the chat lines.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Engine, Kit = ns.Engine, ns.Kit
local Style, Motion = DUI.Style, DUI.Motion

local RollStack = {}
ns.RollStack = RollStack

-- The game's roll buttons on its popup (GroupLootFrame.xml).
RollStack.BUTTONS = { "NeedButton", "GreedButton", "PassButton", "TransmogButton", "DisenchantButton" }

-- With the controller UI on the game rolls in its own gamepad window instead.
local function gamepad()
    return type(InputUtil) == "table" and type(InputUtil.IsGamepadUIEnabled) == "function"
        and InputUtil.IsGamepadUIEnabled() == true
end

function RollStack.On()
    if gamepad() then return false end
    return DUI:Get("Skins", "rolls.enabled") ~= false
end

-- Every rolls setting, defaults filled in.
function RollStack.Settings()
    local out = {}
    local defaults = ns.DEFAULTS.rolls or {}
    for key, value in pairs(defaults) do
        local v = DUI:Get("Skins", "rolls." .. key)
        if v == nil then v = value end
        out[key] = v
    end
    return out
end

local quiet = setmetatable({}, { __mode = "k" })

local function noMouse(f)
    if type(f) == "table" and f.EnableMouse then f:EnableMouse(false) end
end

-- One game popup out of sight and out of the way: alpha 0 and no mouse on it and
-- its buttons, so clicks where no card of ours sits reach the world. Methods
-- only: no fields written on the game's frame, no Show or Hide.
function RollStack.Quiet(f)
    if RollStack.broken or type(f) ~= "table" or not f.GetObjectType then return end
    if f.IsForbidden and f:IsForbidden() then return end
    Kit.Hide(f)
    if quiet[f] then return end
    quiet[f] = true
    noMouse(f)
    noMouse(f.IconFrame)
    local box = f.LootButtonContainer
    if type(box) == "table" then
        for _, key in ipairs(RollStack.BUTTONS) do noMouse(box[key]) end
    end
end

-- Daylight UI's cards failed to draw (the error is reported): the game's own
-- popups come back into sight and take the mouse, so no roll is ever missed.
function RollStack.GiveBack()
    RollStack.broken = true
    local function back(f)
        if type(f) ~= "table" or not f.GetObjectType or (f.IsForbidden and f:IsForbidden()) then return end
        f:SetAlpha(1)
        if not quiet[f] then return end
        quiet[f] = nil
        f:EnableMouse(true)
        if type(f.IconFrame) == "table" then f.IconFrame:EnableMouse(true) end
        local box = f.LootButtonContainer
        if type(box) == "table" then
            for _, key in ipairs(RollStack.BUTTONS) do
                if type(box[key]) == "table" then box[key]:EnableMouse(true) end
            end
        end
    end
    for i = 1, 4 do back(_G["GroupLootFrame" .. i]) end
    if RollStack.frame then
        RollStack.frame:SetScript("OnUpdate", nil)
        RollStack.frame:Hide()
    end
end

local function quietAll()
    for i = 1, 4 do RollStack.Quiet(_G["GroupLootFrame" .. i]) end
    local c = _G.GroupLootContainer
    if type(c) == "table" and type(c.rollFrames) == "table" then
        for _, f in pairs(c.rollFrames) do RollStack.Quiet(f) end
    end
end

-- ---------------------------------------------------------------------
-- The stack: one card per roll over the Loot Rolls handle.
-- ---------------------------------------------------------------------

local Data, Card = ns.RollData, ns.RollCard
local fit
local cards = {}     -- rollID -> its card
local spare = {}     -- cards that left, ready for the next roll
local order = {}     -- the cards in the order Shown() gives
local chosen = {}    -- rollID -> true/false: its list opened or folded by a click
RollStack.brackets = {}

local function now() return GetTime() end

local function fighting() return InCombatLockdown and InCombatLockdown() == true end

-- Every held roll, oldest first, with copies of one item next to each other.
local function all()
    local list = {}
    for _, d in pairs(Data.drops) do list[#list + 1] = d end
    table.sort(list, function(a, b)
        if a.start ~= b.start then return a.start < b.start end
        return a.rollID < b.rollID
    end)
    if RollStack.Settings().twins == false then return list end
    local out, placed = {}, {}
    for _, d in ipairs(list) do
        if not placed[d] then
            out[#out + 1] = d
            placed[d] = true
            for _, twin in ipairs(Data.Twins(d)) do
                if not placed[twin] then out[#out + 1] = twin; placed[twin] = true end
            end
        end
    end
    return out
end

-- At most maxShown, and a roll still waiting on your pick always comes first:
-- its game popup is out of sight, so a roll you never saw would time out as a
-- pass. Rolls you've picked, or that are over, fill the places left.
function RollStack.Shown()
    local list = all()
    local max = RollStack.Settings().maxShown or 4
    local chosen, count = {}, 0
    for _, d in ipairs(list) do
        if count < max and not d.done and not d.mine and not d.watch then chosen[d], count = true, count + 1 end
    end
    for _, d in ipairs(list) do
        if count < max and not chosen[d] then chosen[d], count = true, count + 1 end
    end
    local out = {}
    for _, d in ipairs(list) do if chosen[d] then out[#out + 1] = d end end
    return out
end

function RollStack.Waiting()
    return math.max(0, #all() - #RollStack.Shown())
end

function RollStack.Cards() return order end

function RollStack.Mode()
    local s = RollStack.Settings()
    if fighting() and s.fightCompact ~= false then return "compact" end
    if #RollStack.Shown() > 1 and s.compact ~= false then return "compact" end
    return "full"
end

local function hovered(drop)
    local card = cards[drop.rollID]
    return card ~= nil and card:IsShown() and card:IsMouseOver() == true
end

local function lingering(drop, t)
    return drop.done and drop.doneAt and t <= drop.doneAt + (RollStack.Settings().linger or 5)
end

local function hoverOnly(s)
    return s.list == "hover" or (fighting() and s.fightCompact ~= false)
end

-- The one list shown on compact cards: the card under the mouse, else the
-- roll just finished, else the only roll.
local function openCompact()
    local shown, s = RollStack.Shown(), RollStack.Settings()
    for _, d in ipairs(shown) do if hovered(d) then return d end end
    if hoverOnly(s) then return nil end
    local newest
    local t = now()
    for _, d in ipairs(shown) do
        if lingering(d, t) and (not newest or d.doneAt > newest.doneAt) then newest = d end
    end
    if newest then return newest end
    if #shown == 1 then return shown[1] end
    return nil
end

-- Whether a roll's group list shows.
local function listOpen(drop, mode)
    local s = RollStack.Settings()
    -- Until you've picked, a roll stays small: the list comes after your roll.
    if s.list == "off" or not (drop.mine or drop.done or drop.watch) then return false end
    -- A click on the card has the last word, until the roll leaves.
    if chosen[drop.rollID] ~= nil then return chosen[drop.rollID] end
    if hoverOnly(s) then return hovered(drop) end
    if mode == "full" then return true end
    return openCompact() == drop
end

function RollStack.Open()
    local mode = RollStack.Mode()
    for _, d in ipairs(RollStack.Shown()) do
        if listOpen(d, mode) then return d end
    end
    return nil
end

local function makeFrame()
    if RollStack.frame then return RollStack.frame end
    local f = CreateFrame("Frame", "DaylightUIRollStack", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetSize(300, 1)
    f:EnableMouse(false)
    f:Hide()
    RollStack.frame = f
    RollStack.waiting = Style.Text(f, Style.SIZE.small, "CENTER")
    Style.InkText(RollStack.waiting, "LABEL")
    RollStack.waiting:Hide()
    return f
end

-- A leaving card fades where it was while other cards glide into that spot,
-- so nothing on it may take a click meant for them: the card's own mouse is
-- not enough, its buttons and icon take the mouse on their own.
local function mouseOff(card)
    local off = card.mouseOff or {}
    card.mouseOff = off
    local function walk(f)
        for _, child in ipairs({ f:GetChildren() }) do
            if child:IsMouseEnabled() then
                child:EnableMouse(false)
                off[#off + 1] = child
            end
            walk(child)
        end
    end
    walk(card)
end

local function mouseBack(card)
    local off = card.mouseOff
    if not off then return end
    for i = #off, 1, -1 do
        off[i]:EnableMouse(true)
        off[i] = nil
    end
end

local function cardFor(drop)
    local card = cards[drop.rollID]
    if card then return card, false end
    card = table.remove(spare) or Card.New(RollStack.frame)
    card.leaving = nil
    mouseBack(card)
    card:EnableMouse(true)
    card:SetScript("OnEnter", function() RollStack.Layout() end)
    card:SetScript("OnLeave", function() RollStack.Layout() end)
    card:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then RollStack.PutAway(self)
        elseif button == "LeftButton" then RollStack.Toggle(self) end
    end)
    card.onHeight = function() RollStack.Place() end
    Motion.AlphaTo(card, 1, 0)
    card:SetAlpha(1)
    card:Show()
    cards[drop.rollID] = card
    return card, true
end

-- A card that was on screen fades out where it stood. One made in this same
-- pass that has no room after all (atOnce) was never placed: shown, it would
-- sit wherever that card last stood, over another roll, so it goes at once.
local function leave(rollID, atOnce)
    local card = cards[rollID]
    if not card then return end
    cards[rollID] = nil
    card.leaving = true
    card.drop = nil
    -- Waiting for room is not leaving: the roll keeps the list state its
    -- player clicked for it.
    if not atOnce then chosen[rollID] = nil end
    local R = DUI.APIReport
    if R then
        R.Gone("rollcard", card, false)
        R.SetInfo(card, nil)
    end
    card:EnableMouse(false)
    mouseOff(card)
    -- A slide-in still playing would hold the card in sight over the fade.
    Motion.Settle(card)
    Motion.AlphaTo(card, 0, atOnce and 0 or Motion.NORMAL, true)
    spare[#spare + 1] = card
end

-- A click opens or folds a card's list. Before your pick there is no list yet,
-- only your buttons, so the click does nothing then.
function RollStack.Toggle(card)
    local drop = card and card.drop
    if not drop or card.leaving or RollStack.Settings().list == "off" then return end
    if not (drop.mine or drop.watch or drop.done) then return end
    chosen[drop.rollID] = not (card.look and card.look.open)
    if DUI.Sound then DUI.Sound.Play("click") end
    RollStack.Layout()
end

-- A right-click puts a card away once nothing is asked of you on it: you've
-- picked, it's only watched, or it's over. One still waiting on your pick keeps
-- its place, since putting it away would pass for you unseen.
function RollStack.PutAway(card)
    local drop = card and card.drop
    if not drop or card.leaving or not (drop.mine or drop.watch or drop.done) then return end
    Data.Remove(drop.rollID)
end

-- Where the stack hangs: the first roll slot, the one the Loot Rolls handle
-- stands over (core GameMovers). Anchored to UIParent, never to the game's
-- roll container. That one is a managed frame: when its last popup goes (your
-- own pick can end a roll at once) the game hides it and clears all its
-- points, and everything hung from it would vanish.
local function hangSpot(up)
    local x, y, _, h = DUI.GameMovers.RollSlot()
    return "CENTER", x, up and y - h / 2 or y + h / 2
end

local function anchor()
    local f, s = RollStack.frame, RollStack.Settings()
    local up = s.grow ~= "down"
    local scale = DUI.Movers.Scale(DUI.GameMovers.Key("GroupLootContainer"))
    if math.abs((f:GetScale() or 1) - scale) > 0.001 then f:SetScale(scale) end
    local rel, x, y = hangSpot(up)
    local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    f:ClearAllPoints()
    f:SetPoint(up and "BOTTOM" or "TOP", UIParent, rel, x / k, y / k)
end

local function bracket(i)
    local b = RollStack.brackets[i]
    if not b then
        b = RollStack.frame:CreateTexture(nil, "ARTWORK")
        b:SetTexture("Interface\\Buttons\\WHITE8X8")
        RollStack.brackets[i] = b
    end
    return b
end

-- Puts each card in its place from the live heights: run as a card grows or folds.
function RollStack.Place()
    local f = RollStack.frame
    if not f then return end
    local s = RollStack.Settings()
    local up = s.grow ~= "down"
    local y, gap = 0, s.spacing or 6
    for _, card in ipairs(order) do
        card:ClearAllPoints()
        if up then card:SetPoint("BOTTOM", f, "BOTTOM", 0, y)
        else card:SetPoint("TOP", f, "TOP", 0, -y) end
        card.y = y
        y = y + (card:GetHeight() or 0) + gap
    end
    local w = RollStack.waiting
    w:ClearAllPoints()
    if w:IsShown() then
        if up then w:SetPoint("BOTTOM", f, "BOTTOM", 0, y) else w:SetPoint("TOP", f, "TOP", 0, -y) end
        y = y + Style.SIZE.small + gap
    end
    f:SetSize(s.width or 300, math.max(1, y))
end

-- A thin line in the item's color down the left of copies of one item.
local function layBrackets(shown, up)
    local used = 0
    local i = 1
    while i < #shown do
        local a = shown[i]
        local last = i
        while shown[last + 1] and shown[last + 1].itemID ~= nil and shown[last + 1].itemID == a.itemID do last = last + 1 end
        if last > i and RollStack.Settings().twins ~= false then
            used = used + 1
            local b = bracket(used)
            local low, high = order[i], order[last]
            if not up then low, high = high, low end
            b:ClearAllPoints()
            b:SetWidth(DUI.Pixel.Px(RollStack.frame, 1))
            b:SetPoint("TOPRIGHT", high, "TOPLEFT", -4, 0)
            b:SetPoint("BOTTOMRIGHT", low, "BOTTOMLEFT", -4, 0)
            local c = ns.LootRoll.QualityColor(a.quality) or Style.INK.LABEL
            b:SetVertexColor(c[1], c[2], c[3], 0.8)
            b:Show()
        end
        i = last + 1
    end
    for n = used + 1, #RollStack.brackets do RollStack.brackets[n]:Hide() end
end

-- The room left between the stack's handle and the screen's edge it grows
-- toward, in the stack's own units; nil while that can't be measured.
RollStack.MARGIN = 8
function RollStack.Room()
    local f = RollStack.frame
    if not f then return nil end
    local up = RollStack.Settings().grow ~= "down"
    local edge = up and f:GetBottom() or f:GetTop()
    local screen = up and UIParent:GetTop() or UIParent:GetBottom()
    local mine, ui = f:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if type(edge) ~= "number" or type(screen) ~= "number" or not mine or mine <= 0 then return nil end
    local room = up and (screen * ui - edge * mine) or (edge * mine - screen * ui)
    return room / mine - RollStack.MARGIN
end

local function needed(s)
    local h, gap = 0, s.spacing or 6
    for _, card in ipairs(order) do h = h + Card.Height(card, card.look) + gap end
    return h + Style.SIZE.small + gap
end

-- Keeps the stack on screen: lists fold first (the one under the mouse keeps
-- its own), then rolls past what fits wait their turn, the ones you've picked
-- or that are over first. A roll waiting on your pick keeps its place.
function fit(shown, s, keep)
    local room = RollStack.Room()
    if not room or needed(s) <= room then return shown end
    for i, card in ipairs(order) do
        local d = shown[i]
        if card.look and card.look.open and not hovered(d) then
            Card.Fill(card, d, { mode = "compact", open = false, settings = s })
        end
    end
    while #order > 1 and needed(s) > room do
        local drop = #order
        for i = #order, 1, -1 do
            local d = shown[i]
            if d.done or d.mine or d.watch then drop = i break end
        end
        keep[shown[drop].rollID] = nil
        table.remove(order, drop)
        table.remove(shown, drop)
    end
    return shown
end

-- Fills every card and lays the stack out: new cards slide in, cards that
-- change places glide there, leaving ones fade.
local layout
function RollStack.Layout()
    if RollStack.broken or not RollStack.frame then return end
    if not DUI.SafeCall(layout) then RollStack.GiveBack() end
end

layout = function()
    local f = RollStack.frame
    anchor()
    local s = RollStack.Settings()
    local shown = RollStack.Shown()
    local mode = RollStack.Mode()
    local up = s.grow ~= "down"
    local was, before = {}, {}
    for i, card in ipairs(order) do was[card], before[card] = i, card.y end
    wipe(order)
    local keep = {}
    for i, d in ipairs(shown) do
        keep[d.rollID] = true
        local card, new = cardFor(d)
        order[i] = card
        card:SetWidth(s.width or 300)
        Card.Fill(card, d, { mode = mode, open = listOpen(d, mode), settings = s })
        card.isNew = new
    end
    shown = fit(shown, s, keep)
    for rollID, card in pairs(cards) do
        if not keep[rollID] then leave(rollID, card.isNew) end
    end
    local waiting = #all() - #shown
    RollStack.waiting:SetShown(waiting > 0)
    if waiting > 0 then RollStack.waiting:SetText(L["%d more waiting"]:format(waiting)) end

    RollStack.Place()
    for i, card in ipairs(order) do
        if card.isNew then
            Motion.SlideIn(card, 0, up and -12 or 12, Motion.NORMAL)
            card.isNew = nil
        elseif before[card] and was[card] ~= i then
            local dy = before[card] - card.y
            Motion.Glide(card, 0, up and dy or -dy, Motion.SLOW)
        end
    end
    layBrackets(shown, up)

    if #shown > 0 then
        RollStack.closing = nil
        anchor()
        f:Show()
        if not f:GetScript("OnUpdate") then f:SetScript("OnUpdate", RollStack.OnUpdate) end
    elseif f:IsShown() and not RollStack.closing then
        -- The last cards fade out first; the stack hides once they're gone,
        -- unless a new roll came up meanwhile.
        f:SetScript("OnUpdate", nil)
        RollStack.closing = true
        Motion.Tween(RollStack, 0, 1, Motion.NORMAL, nil, function()
            if RollStack.closing and #order == 0 then f:Hide() end
            RollStack.closing = nil
        end)
    end
end

-- The one driver, running only while a roll is held: timers, rolls that ran
-- out, and finished ones leaving after their linger.
function RollStack.Tick(t)
    t = t or now()
    for _, card in ipairs(order) do Card.Tick(card, t) end
    Data.Expire(t)
    local s, gone = RollStack.Settings(), false
    for id, d in pairs(Data.drops) do
        if d.done and d.doneAt and t > d.doneAt + (s.linger or 5)
            and not (s.holdOnHover ~= false and hovered(d)) then
            Data.Remove(id)
            gone = true
        end
    end
    if gone then RollStack.Layout() end
    if not next(Data.drops) and RollStack.frame then RollStack.frame:SetScript("OnUpdate", nil) end
end

function RollStack.OnUpdate()
    DUI.SafeCall(RollStack.Tick, now())
end

-- The game's "You won" toast (LOOT_ITEM_ROLL_WON) for a roll a card is showing:
-- the card already says who won with what, and the toast lands right over it
-- (the game anchors toasts above its roll popups, which are gone by then).
-- Dismissed the way the game's own right-click does it. Only roll toasts carry
-- the need/greed icon, so plain loot keeps its toast.
function RollStack.WonToast(f)
    if RollStack.broken or not RollStack.On() then return end
    if type(f) ~= "table" or f.queue == nil or f.queue ~= _G.LootAlertSystem then return end
    local icon = f.RollTypeIcon
    if type(icon) ~= "table" or not icon:IsShown() then return end
    local held = false
    for _, card in pairs(cards) do
        if card.drop and card:IsShown() and Data.SameItem(card.drop, f.hyperlink) then held = true; break end
    end
    if not held then return end
    for _, key in ipairs({ "animIn", "waitAndAnimOut" }) do
        if type(f[key]) == "table" then f[key]:Stop() end
    end
    for _, key in ipairs({ "glow", "shine" }) do
        local g = f[key]
        if type(g) == "table" and type(g.animIn) == "table" then g.animIn:Stop() end
    end
    f:Hide()
end

-- After a setting changes or the look repaints.
function RollStack.Refresh()
    if RollStack.frame then RollStack.Layout() end
end

function RollStack.Apply()
    Data.Wire()
    -- A popup the game opens later is quieted as it shows, before it's ever drawn.
    for _, fn in ipairs({ "GroupLootContainer_AddFrame", "GroupLootContainer_Update" }) do
        if type(_G[fn]) == "function" then
            hooksecurefunc(fn, function() DUI.SafeCall(quietAll) end)
        end
    end
    quietAll()
    if type(_G.AlertFrame_ShowNewAlert) == "function" then
        hooksecurefunc("AlertFrame_ShowNewAlert", function(f) DUI.SafeCall(RollStack.WonToast, f) end)
    end
    makeFrame()
    -- Every change shows at once: picks and the winner never wait.
    DUI.On("RollChanged", function() RollStack.Layout() end)
    DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        Data.Rebuild(now())
        RollStack.Layout()
    end)
    DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function() RollStack.Layout() end)
    DUI.RegisterEvent("PLAYER_REGEN_ENABLED", function() RollStack.Layout() end)
    DUI.On("StyleChanged", RollStack.Refresh)
    -- The Loot Rolls handle moving (dragged, snapped, nudged, reset, sized):
    -- the cards come along as it goes.
    DUI.On("RollSlotMoved", function()
        if RollStack.frame and RollStack.frame:IsShown() then DUI.SafeCall(anchor) end
    end)
    Data.Rebuild(now())
    RollStack.Layout()
end

Engine.Register({ key = "rolls", skip = function() return not RollStack.On() end, apply = RollStack.Apply })
