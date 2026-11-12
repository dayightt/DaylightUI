-- Quest item buttons. Custom secure buttons (the game's would call a protected
-- function from tainted code) in a column beside the list, each lined up with its
-- quest's title. Being secure, they're only created, moved, shown and hidden out
-- of combat. They're parented to a holder on UIParent and placed in screen
-- coordinates, never anchored to the list (no anchors between protected frames and addon frames).
-- In combat the tracker holds any layout that would move them; cooldowns, range
-- and alpha still update.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style

local Items = {}
ns.Items = Items

Items.SIZE = 24
Items.GAP = 10              -- between a button and the list
Items.RANGE_TICK = 0.2
Items.OUT_OF_RANGE = { 1, 0.35, 0.35 }

local buttons, want = {}, {}
Items.buttons = buttons

local holder = CreateFrame("Frame", "DaylightUIQuestItems", UIParent)
holder:SetAllPoints(UIParent)
holder:SetFrameStrata("LOW")
holder:EnableMouse(false)
Items.holder = holder

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- Each quest's block key ("quest:123"), built once instead of every frame.
local keyOf = setmetatable({}, { __index = function(t, id)
    local k = "quest:" .. id
    t[id] = k
    return k
end })
local NONE = {}

-- What a button was last given, so the same values aren't set again: position
-- (side, x, y, alpha, plain numbers computed from the addon's own frames),
-- cooldown and range tint. Cleared whenever anything else moves, shows, hides or
-- fades it.
local function forget(btn)
    btn.atSide, btn.atX, btn.atY, btn.atA = nil, nil, nil, nil
    btn.cdStart, btn.cdDur, btn.tint = nil, nil, nil
end

local function make(id)
    local b = CreateFrame("Button", "DaylightUIQuestItem" .. id, holder, "SecureActionButtonTemplate")
    b:SetSize(Items.SIZE, Items.SIZE)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    Style.CropIcon(b.icon)
    -- The icon sits inside the border like on action buttons, otherwise it covers
    -- the shell and the button looks like a bare game icon.
    Style.Shell(b, { borderPx = 2, noBevel = true })
    local T = DUI.Pixel.Px(b, 2)
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", T, -T)
    b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -T, T)
    b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints(b.icon)
    b.count = Style.Text(b, Style.SIZE.tiny, "RIGHT")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b:SetScript("OnEnter", function(self)
        if GameTooltip and self.link then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end

function Items.Any()
    for id in pairs(want) do if buttons[id] and buttons[id]:IsShown() then return true end end
    return false
end

-- The list's view, used to line buttons up and to tell what's scrolled out of sight.
local function view() return ns.Tracker and ns.Tracker.view end

-- top, vt, vb: the block's top and the view's top and bottom, if the caller
-- already has them.
function Items.InView(f, top, vt, vb)
    if top == nil then
        local v = view()
        top, vt, vb = f:GetTop(), v and v:GetTop(), v and v:GetBottom()
    end
    if type(top) ~= "number" or type(vt) ~= "number" or type(vb) ~= "number" then return true end
    return top <= vt + 1 and top - Items.SIZE >= vb - 1
end

function Items.Sync(blocks, frames)
    Items.blocks, Items.frames = blocks, frames
    DUI.AfterCombat(Items.Place, "quests:items")
end

function Items.Place()
    for k in pairs(want) do want[k] = nil end
    for _, b in ipairs(Items.blocks or {}) do
        local q = b.kind == "quest" and b.quest
        if q and q.item then
            want[q.id] = true
            local btn = buttons[q.id] or make(q.id)
            buttons[q.id] = btn
            local itemID = q.item.link:match("item:(%d+)")
            btn.link, btn.logIndex, btn.questID = q.item.link, q.logIndex, q.id
            btn:SetAttribute("type", "item")
            btn:SetAttribute("item", itemID and ("item:" .. itemID) or q.item.link)
            btn.icon:SetTexture(q.item.icon)
            local charges = q.item.charges
            btn.count:SetText((type(charges) == "number" and not secret(charges) and charges > 1) and charges or "")
            btn:SetAlpha(1)
            forget(btn)
        end
    end
    for id, btn in pairs(buttons) do
        if not want[id] then
            btn:Hide()
            forget(btn)
        end
    end
    Items.Follow()
    Items.Refresh()
    Items.Tick()
end

-- Lines each button up with its quest as the list moves (out of combat). Runs
-- every frame something in the list moves, so buttons already in place are
-- left alone.
function Items.Follow()
    if not next(want) or InCombatLockdown() then return end
    local v = view()
    local frames = Items.frames or NONE
    local side = DUI:GetModule("Quests").db.itemSide
    local left, right = v and v:GetLeft(), v and v:GetRight()
    local vt, vb = v and v:GetTop(), v and v:GetBottom()
    local ui = UIParent:GetEffectiveScale()
    for id in pairs(want) do
        local btn, f = buttons[id], frames[keyOf[id]]
        local top = f and f:GetTop()
        if btn and f and f:IsShown() and type(top) == "number" and type(left) == "number" and Items.InView(f, top, vt, vb) then
            local s = f:GetEffectiveScale() / ui
            local onRight = side == "right" and type(right) == "number"
            local x = onRight and (right * s + Items.GAP) or (left * s - Items.GAP)
            local y = top * s + 1
            local a = f:GetAlpha()
            if secret(a) then a = nil end
            if not (btn.atSide == onRight and btn.atX == x and btn.atY == y and a ~= nil and btn.atA == a and btn:IsShown()
                and btn.atS == s) then
                -- Same scale as the list next to it (master scale times the tracker's own), with
                -- offsets in its own scale.
                if btn.atS ~= s then btn:SetScale(s) end
                btn:ClearAllPoints()
                btn:SetPoint(onRight and "TOPLEFT" or "TOPRIGHT", UIParent, "BOTTOMLEFT", x / s, y / s)
                btn:SetAlpha(a or f:GetAlpha())
                btn:Show()
                btn.atSide, btn.atX, btn.atY, btn.atA, btn.atS = onRight, x, y, a, s
            end
        elseif btn and not (f and type(top) ~= "number") then
            btn:Hide()
            forget(btn)
        elseif btn then
            btn:Show()      -- the test stub (and a frame not laid out yet) has no positions: show it, place it next time
            forget(btn)
        end
    end
end

-- The list moved without a relayout (dragged in unlock mode, reset, the panel above
-- resized, UI scale changed). The buttons follow, after combat if in one.
local lastLeft, lastTop
function Items.FollowIfMoved()
    local v = view()
    local left, top = v and v:GetLeft(), v and v:GetTop()
    if type(left) ~= "number" or type(top) ~= "number" then return end
    if left == lastLeft and top == lastTop then return end
    if InCombatLockdown() then return end
    lastLeft, lastTop = left, top
    Items.Follow()
end

-- A shown button under the mouse (it wakes the tracker's fade).
function Items.Hovered()
    for id in pairs(want) do
        local btn = buttons[id]
        if btn and btn:IsShown() and btn:IsMouseOver() == true then return true end
    end
    return false
end

-- Cooldowns and range are allowed in combat since they don't change the secure
-- button. Each is only set when it changed (checked every 0.2 s).
function Items.Refresh()
    if not next(want) then return end
    for id, btn in pairs(buttons) do
        if want[id] and btn.logIndex then
            local start, dur = nil, nil
            if type(GetQuestLogSpecialItemCooldown) == "function" then start, dur = GetQuestLogSpecialItemCooldown(btn.logIndex) end
            if secret(start) or secret(dur) then
                -- SetCooldown refuses secrets from addon code (AllowedWhenUntainted in the
                -- game's API docs), and these items have no duration object, so the sweep is
                -- left as it was.
            elseif type(start) == "number" and type(dur) == "number" and dur > 0 then
                if btn.cdStart ~= start or btn.cdDur ~= dur then
                    btn.cooldown:SetCooldown(start, dur)
                    btn.cdStart, btn.cdDur = start, dur
                end
            elseif btn.cdStart ~= false then
                btn.cooldown:Clear()
                btn.cdStart, btn.cdDur = false, false
            end
            local inRange = type(IsQuestLogSpecialItemInRange) == "function" and IsQuestLogSpecialItemInRange(btn.logIndex)
            local out = not secret(inRange) and inRange == 0
            if btn.tint ~= out then
                btn.tint = out
                if out then
                    btn.icon:SetVertexColor(unpack(Items.OUT_OF_RANGE))
                else
                    btn.icon:SetVertexColor(1, 1, 1)
                end
            end
        end
    end
end

-- The 0.2 s cooldown and range check only runs while a button is showing.
local function refreshTick() DUI.SafeCall(Items.Refresh) end
function Items.Tick()
    local any = next(want) ~= nil
    if any and not Items.ticker then
        Items.ticker = C_Timer.NewTicker(Items.RANGE_TICK, refreshTick)
    elseif not any and Items.ticker then
        Items.ticker:Cancel()
        Items.ticker = nil
    end
end

-- In combat, a button whose quest no longer has its item goes transparent (it
-- can't be hidden until combat ends).
function Items.Dim(snap)
    local has = {}
    for _, g in ipairs(snap.groups) do
        for _, q in ipairs(g.quests) do if q.item then has[q.id] = true end end
    end
    for id, btn in pairs(buttons) do
        if want[id] and not has[id] then
            btn:SetAlpha(0)
            forget(btn)
        end
    end
end

pcall(DUI.RegisterEvent, "BAG_UPDATE_COOLDOWN", function() Items.Refresh() end)
