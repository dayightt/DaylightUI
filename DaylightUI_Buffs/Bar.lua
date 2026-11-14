-- Bar: the buff bar (and, through the same factory, the debuff bar).
--
-- The bar is one of the client's own aura containers. We never read aura
-- data to draw it: we register one aura group per category, filtered by
-- spell ID, tell the client how to lay the groups out (order, gaps, row
-- width, growth direction) and hand each button a texture, a cooldown
-- and two font strings. The client fills them, sorts them, moves them
-- and handles right-click canceling - in combat too, where addon code
-- is not allowed to look at auras at all.
--
-- The client also hides which of its buttons are live (their shown
-- state, icon and geometry are secret or deliberately stale), so nothing
-- here asks a button anything. Interaction works from data instead: out
-- of combat we know each group's members and their client order, and
-- Layout.Flow is the client's own layout algorithm, so a cursor position
-- maps to (group, index) and from there to a buff by name.
--
-- The buttons wear the target auras' look (Widgets.lua): the edge is the
-- category's color on buffs and the dispel type's on debuffs.

local _, BL = ...
local DUI = DaylightUI
local L = DUI.L
local Style = DUI.Style

local W = BL.Widgets
local Layout = BL.Layout

local POPOUT_LEAVE_DELAY = 0.3
local POPOUT_PAD = 8
local POPOUT_COLUMNS = 8
local HOVER_INTERVAL = 0.1
local WEAPON_INTERVAL = 0.2
local WEAPON_IDLE_INTERVAL = 1 -- no enchant up: the game's events bring one in at once
local ENCHANT_KEY = "weapon"
local NONE = {} -- shared empty list, never written to
local BACKGROUND_PAD = 6

-- Dispel colors for the debuff edge (same as the target's debuffs).
BL.DISPEL_COLORS = {
    None = { 0.6, 0.16, 0.18 }, Magic = { 0.25, 0.55, 0.95 }, Curse = { 0.62, 0.3, 0.9 }, Disease = { 0.7, 0.5, 0.18 },
    Poison = { 0.3, 0.7, 0.25 }, Bleed = { 0.78, 0.14, 0.14 }, Enrage = { 0.6, 0.16, 0.18 },
}

-- A dispel type's color: the one picked on the unit frames' Colors page
-- (colors.dispelMagic...) when that module is on, else ours.
function BL.DispelColor(key)
    local c = DUI:Get("UnitFrames", "colors.dispel" .. key)
    if type(c) == "table" then return c end
    return BL.DISPEL_COLORS[key]
end

local function inCombat() return InCombatLockdown() end

-- Room above each icon row for the time, which sits centered on the top edge.
BL.BACKGROUND_PAD = BACKGROUND_PAD
local function textRoom(size) return math.ceil(W.TimeSize(size) / 2) + 1 end

-- Frames anchored to a container must opt out of untrusted layout scripts
-- once the container has groups; inherit the opt-in template when it exists.
local function createCompanion(frameType, parent, extraTemplate)
    local templates = extraTemplate and ("DisableUntrustedLayoutScriptsTemplate," .. extraTemplate) or "DisableUntrustedLayoutScriptsTemplate"
    local ok, f = pcall(CreateFrame, frameType, nil, parent, templates)
    if ok and f then return f end
    return CreateFrame(frameType, nil, parent, extraTemplate)
end

-- Cursor position in UI units (the space GetLeft/GetTop use).
local function cursorUI()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    return x / scale, y / scale
end

-- Registers edge to be tinted by the aura's dispel type: our colors on a white
-- square (using the enum style and color objects, since this client silently
-- ignores the plain-string form), or the client's colors as a fallback.
-- asset, coords: another texture (a corner cap) and its { left, right, top,
-- bottom } crop, since the client resets the crop when it sets the texture.
local function registerDispelEdge(btn, edge, asset, coords)
    Style.DispelEdge(btn, edge, BL.DispelColor, { asset = asset or W.WHITE, coords = coords })
end

-- ---------------------------------------------------------------------
-- Shift state. Shields (see below) only take the mouse while Shift is
-- held; the modifier event is the reliable source on this client.
-- ---------------------------------------------------------------------

local shields = {}
local shiftHeld = false
local editModeActive = false
local popout, popoutBack, popoutLeaveAt, popoutOwner, popoutRect, popoutShown
local popoutFade = {} -- tween key for its fade; .a = current value

local function applyShields()
    for _, sh in ipairs(shields) do
        pcall(sh.EnableMouse, sh, (shiftHeld and not sh.suspended) and true or false)
    end
end

local function setShiftHeld(down)
    if down == shiftHeld then return end
    shiftHeld = down
    applyShields()
end

DUI.RegisterEvent("MODIFIER_STATE_CHANGED", function(_, key, state)
    key, state = BL.Plain(key), BL.Plain(state)
    if type(key) ~= "string" or not string.find(key, "SHIFT") then return end
    setShiftHeld((state == 1) or (state == true) or (state == "1"))
end)
DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function() setShiftHeld(false) end)

-- A shield covers a container and takes clicks while Shift is held;
-- onClick receives the cursor in UI units.
local function createShield(container, strata, onClick)
    local sh = createCompanion("Button", UIParent)
    sh:SetAllPoints(container)
    sh:SetFrameStrata(strata)
    sh:SetFrameLevel(50)
    sh:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    sh:EnableMouse(false)
    sh.suspended = false
    sh:SetScript("OnClick", function()
        local x, y = cursorUI()
        onClick(x, y)
    end)
    shields[#shields + 1] = sh
    return sh
end

-- ---------------------------------------------------------------------
-- Bar mixin
-- ---------------------------------------------------------------------

local BarMixin = {}

function BarMixin:Setting(key) return BL.GetSetting(key, self.scope) end
function BarMixin:IsDebuff() return self.scope == "debuff" end
function BarMixin:Corner() return self:Setting("growLeft") and "TOPRIGHT" or "TOPLEFT" end
function BarMixin:Size() return self:Setting("iconSize") end
function BarMixin:BorderPx() return self:Setting("borderPx") end
function BarMixin:Height() return W.Height(self:Setting("iconSize")) end

-- Position -------------------------------------------------------------

-- The holder is our own plain frame that carries the position (unlock mode
-- moves it). The imbue strip and the container both hang off its corner, with
-- the container pushed past the strip. The client sets the container's own
-- geometry with secret values, so it can't be moved and read back directly.
function BarMixin:ApplyPosition()
    local weapons = self.weaponFrame
    if weapons then
        local corner = self:Corner()
        weapons:ClearAllPoints()
        weapons:SetPoint(corner, self.holder, corner, 0, 0)
    end
    self:PlaceContainer()
end

-- Places the container past the imbue strip. Never anchored to the strip
-- itself: the frame a container hangs off becomes protected in combat, so the
-- strip couldn't grow then. The container's own anchor may change in combat,
-- and the holder only moves out of combat (unlock mode, ApplyAttach).
-- Where the container sits past the imbue strip, in bar units: beside it, or
-- with each kind on its own row, one row below it so the imbues are a row of
-- their own.
function BarMixin:ContainerOffset()
    local weapons = self.weaponWidth or 0
    if weapons <= 0 then return 0, 0 end
    if self:Rows() then
        return 0, self:Height() + self:Setting("spacing") + textRoom(self:Size())
    end
    return weapons, 0
end

function BarMixin:PlaceContainer()
    local corner = self:Corner()
    local along, down = self:ContainerOffset()
    self.frame:ClearAllPoints()
    self.frame:SetPoint(corner, self.holder, corner, along * (corner == "TOPRIGHT" and -1 or 1), -down)
end

-- The holder doubles as the unlock handle: one row wide, one icon tall.
function BarMixin:ApplySize()
    local size, spacing = self:Size(), self:Setting("spacing")
    local columns = math.max(1, math.floor(tonumber(self:Setting("columns")) or 1))
    local width = math.max(120, math.min(columns, 8) * (size + spacing))
    self.holder:SetSize(width, self:Height() + textRoom(size))
    self:ApplyPosition()
end

-- Attached (the default), the bar sits at its anchor beside the info panel
-- regardless of any saved position, and follows the panel as it resizes; it
-- has no unlock handle. Detached, unlock mode moves it and it keeps its spot.
-- The first time it's detached (no spot of its own yet) it stays where it was
-- beside the panel instead of jumping to the mover default.
function BarMixin:ApplyAttach()
    local attached = self:Setting("attach") ~= false
    local key = self.moverKey
    local e = DUI.Movers.Get(key)
    if not attached and e and e.suspended and not DUI.DB.Positions()[key] then
        DUI.Movers.Save(key, true)
    end
    DUI.Movers.Suspend(key, attached)
    if not attached then return end
    local d, holder = self.default, self.holder
    DUI.AfterCombat(function()
        holder:ClearAllPoints()
        holder:SetPoint(d[1], _G[d[2]] or UIParent, d[3], d[4], d[5])
    end, "buffs:attach:" .. self.moverKey)
end

-- The master scale times the bar's own (mouse wheel in unlock mode). The holder
-- stays at 1, since the hover math reads it in UI units.
function BarMixin:Scale()
    return DUI.Movers.Scale(self.moverKey)
end

function BarMixin:ApplyScale()
    local scale = self:Scale()
    self.frame:SetScale(scale)
    if self.weaponFrame then self.weaponFrame:SetScale(scale) end
end

-- An optional dark panel behind the bar, in the info panel's style. Its top
-- clears the time above the first row, which follows the icon size.
function BarMixin:ApplyBackground()
    local bg, c = self.background, self.frame
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", c, "TOPLEFT", -BACKGROUND_PAD, BACKGROUND_PAD + textRoom(self:Size()))
    bg:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", BACKGROUND_PAD, -BACKGROUND_PAD)
    bg:SetShown(self:Setting("showBackground") and true or false)
    local s = Style.GetShell(bg)
    if s then s.opts.bgAlpha = DUI.Style.BackAlpha(self:Setting("backgroundAlphaOwn"), self:Setting("backgroundAlpha")) end
    Style.LayoutShell(s)
end

-- Container ------------------------------------------------------------

function BarMixin:Create()
    if self.frame then return end
    local ok, c = pcall(CreateFrame, "AuraContainer", self.frameName, UIParent, "CustomAuraContainerTemplate")
    if not ok or not c then
        BL.Print("This client has no aura container support (" .. tostring(c) .. "); the " .. self.scope .. " bar can't be shown.")
        return
    end
    self.frame = c
    self.groups = {}        -- [groupKey] = true once registered with the container
    self.buttons = {}       -- [groupKey] = { button, ... } created by the client for that group
    self.consolidated = {}  -- [groupKey] = true while the group is collapsed to one icon
    self.memberCounts = {}  -- [groupKey] = n, refreshed whenever auras are readable
    self.badged = {} -- [groupKey] = how many of its buttons show the count above
    self.lastCount = 0

    c:SetUnit("player")
    c:SetFrameStrata("LOW")
    c:EnableMouse(false)

    local holder = CreateFrame("Frame", self.frameName .. "Holder", UIParent)
    holder:SetFrameStrata("LOW")
    self.holder = holder
    -- Plugins find the bar by its scope ("buff" or "debuff") and attach to this
    -- holder (ours): the client's aura buttons inside lock in fights.
    DUI.APIReport.Made("buffbar", holder, self.scope, false)
    DUI.Movers.Register(holder, self.moverKey, self.label, self.default, {
        scale = function()
            if self.frame then self:ApplyScale() end
            BL.PlaceAnchor() -- the anchors make room at the bars' drawn size
        end })
    self:ApplyAttach()

    local background = createCompanion("Frame", c)
    background:SetFrameLevel(math.max(0, c:GetFrameLevel() - 1))
    background:EnableMouse(false)
    Style.Shell(background, { borderPx = 2, noBevel = true })
    self.background = background

    if not self:IsDebuff() then
        self:CreateWeapons()
        self.shield = createShield(c, "MEDIUM", function(x, y) self:OnShiftClick(x, y) end)
        holder.accum = 0
        holder:SetScript("OnUpdate", function(_, elapsed)
            holder.accum = holder.accum + elapsed
            if holder.accum < HOVER_INTERVAL then return end
            holder.accum = 0
            self:PollHover()
        end)
    end

    self:ApplyScale()
    self:ApplyBackground()
    self:ApplySize()
    self:ApplyFlow()
    self:ApplyGroups()
end

function BarMixin:FlowOptions()
    local size, spacing = self:Size(), self:Setting("spacing")
    local columns = math.max(1, math.floor(tonumber(self:Setting("columns")) or 1))
    return {
        anchorPoint = self:Corner(),
        horizontal = self:Setting("growLeft") and Layout.LEFT or Layout.RIGHT,
        vertical = Layout.DOWN,
        maximumLineSize = columns * (size + spacing),
    }
end

function BarMixin:ApplyFlow()
    local c = self.frame
    if not c then return end
    self.flow = nil
    local o = self:FlowOptions()
    pcall(function()
        c:SetFlowLayoutMaximumLineSize(o.maximumLineSize)
        c:SetFlowLayoutAnchorPoint(o.anchorPoint)
        c:SetFlowLayoutGrowthDirection(o.horizontal, o.vertical)
    end)
end

function BarMixin:GroupLayout(index)
    local size, spacing = self:Size(), self:Setting("spacing")
    return {
        layoutIndex = index,
        elementWidth = size,
        elementHeight = W.Height(size),
        elementSpacing = spacing,
        lineSpacing = spacing + textRoom(size),
        -- The client's own default for this is 0, which would let a wrapped
        -- category's times run into the row above.
        groupLineSpacing = spacing + textRoom(size),
        groupSpacing = self:IsDebuff() and 0 or (self:Setting("categoryGap") or 0),
        forceNewLine = self:Rows() and BL.Categories.StartsRow(index),
    }
end

-- Each kind on its own row (buff bar only): class buffs, then weapon,
-- consumable and the rest.
function BarMixin:Rows()
    return not self:IsDebuff() and self:Setting("categoryRows") == true
end

local function groupState()
    return { inGroup = IsInGroup(), inRaid = IsInRaid() }
end

-- Registers or updates every group. Safe in combat, since it only talks to the
-- container, never to the buttons.
function BarMixin:ApplyGroups()
    local c = self.frame
    if not c then return end
    self:InvalidateMembers()
    if self:IsDebuff() then
        if not self.groups.debuffs then
            local ok, err = pcall(c.AddAuraGroup, c, "debuffs", "HARMFUL", {
                sortMethod = AuraContainerSortMethod.ExpirationOnly,
                sortDirection = AuraContainerSortDirection.Normal,
                layout = self:GroupLayout(1),
                initializeFrame = function(btn) self:InitButton(btn, "debuffs") end,
            })
            if ok then self.groups.debuffs = true else BL.Print("Debuff group failed: " .. tostring(err)) end
        else
            pcall(c.SetAuraGroupLayout, c, "debuffs", self:GroupLayout(1))
        end
        self:Restyle()
        return
    end

    local sets = BL.Spells.Sets()
    local settings = BL.DB.settings
    local state = groupState()
    -- What a roster change can affect here (see GROUP_ROSTER_UPDATE).
    self.appliedInGroup, self.appliedInRaid = state.inGroup, state.inRaid
    self:ApplyEnchants()
    local present = {}
    for index, id in ipairs(BL.Categories.Order()) do
        local cat = BL.Categories.Get(id)
        present[id] = true
        -- Weapon covers the weapon enchants (the container's own slots and
        -- our imbue strip) plus a normal aura group for buffs a player moves
        -- into it.
        if id == ENCHANT_KEY then self.weaponLayoutDirty = true end
        if cat then
            local filters
            if id == "other" then
                filters = { excludeSpellIDs = sets.categorised }
            else
                filters = { includeSpellIDs = sets.byCategory[id] or {} }
            end
            local collapsed = Layout.ConsolidateAllowed(cat, settings, state)
            local max = cat.hidden and 0 or (collapsed and 1 or math.huge)
            self.consolidated[id] = (collapsed and not cat.hidden) or nil
            local layout = self:GroupLayout(index)
            if not self.groups[id] then
                local ok, err = pcall(c.AddAuraGroup, c, id, "HELPFUL", {
                    candidateFilters = filters,
                    sortMethod = AuraContainerSortMethod.ExpirationOnly,
                    sortDirection = AuraContainerSortDirection.Normal,
                    maxFrameCount = max,
                    layout = layout,
                    initializeFrame = function(btn) self:InitButton(btn, id) end,
                })
                if ok then self.groups[id] = true else BL.Print("Group " .. id .. " failed: " .. tostring(err)) end
            else
                pcall(c.SetAuraGroupCandidateFilters, c, id, filters)
                pcall(c.SetAuraGroupLayout, c, id, layout)
                pcall(c.SetAuraGroupMaxFrameCount, c, id, max)
            end
        end
    end
    -- Groups for categories that no longer exist stay registered but empty.
    for key in pairs(self.groups) do
        if not present[key] then
            pcall(c.SetAuraGroupMaxFrameCount, c, key, 0)
            self.consolidated[key] = nil
        end
    end
    self:Restyle()
    self:RefreshCounts()
end

-- Weapon enchants ------------------------------------------------------------
--
-- Oils, stones and poisons belong to the container: one item enchantment slot
-- per weapon (Blizzard_CustomAuraContainer.lua), ahead of the buffs, where the
-- stock frame keeps them. The client fills, places and cancels them like any
-- buff, in combat too, so one applied mid-fight shows immediately. A slot can't
-- be removed, only switched off, which is what hiding the Weapon category does.
--
-- WoW Forever's shaman imbues (Rockbiter, Windfury...) are a different enchant
-- type the container never sees (it reads C_PaperDollInfo's temporary enchant;
-- Auras.CollectWeapons asks that same read what it draws). Those are ours:
-- plain buttons fed by the weapon enchant API, which isn't aura data and stays
-- readable in combat. They sit at the start of the bar with the container
-- hanging off the strip's far edge, so only the strip's width moves (in combat
-- too, unless the client marks the strip protected; see UpdateWeapons).

local ENCHANT_SLOTS = { "MainHand", "OffHand", "Ranged" }

-- Declares the weapon slots once, then keeps their layout and on/off state in
-- sync with the settings. Only talks to the container, so it's safe in combat.
function BarMixin:ApplyEnchants()
    local c = self.frame
    local slots = AuraContainerItemEnchantmentSlot
    if self:IsDebuff() or not (c and c.AddItemEnchantment and type(slots) == "table") then return end
    self.enchantSlots = self.enchantSlots or {}
    for _, name in ipairs(ENCHANT_SLOTS) do
        local slot = slots[name]
        if slot ~= nil and not self.enchantSlots[name] then
            local ok, err = pcall(c.AddItemEnchantment, c, slot, {
                hidePermanent = true,
                initializeFrame = function(btn) self:InitButton(btn, "enchants", ENCHANT_KEY) end,
            })
            if ok then self.enchantSlots[name] = slot else BL.Print("Weapon slot " .. name .. " failed: " .. tostring(err)) end
        end
    end
    local layout = self:GroupLayout(0)
    local place = CustomAuraContainerItemEnchantmentPlacement
    layout.placement = type(place) == "table" and place.BeforeAuraGroups or nil
    pcall(c.SetItemEnchantmentLayout, c, layout)
    -- Main hand at the bar's start, as the strip always had it.
    local sorts = AuraContainerItemEnchantmentSortMethod
    if type(sorts) == "table" then
        pcall(c.SetItemEnchantmentSortMethod, c, sorts.Slot, AuraContainerSortDirection.Normal)
    end
    local cat = BL.Categories.Get(ENCHANT_KEY)
    local on = not (cat and cat.hidden)
    for _, slot in pairs(self.enchantSlots) do pcall(c.SetItemEnchantmentEnabled, c, slot, on) end
    self.enchantsOn = on
end

function BarMixin:CreateWeapons()
    local f = CreateFrame("Frame", self.frameName .. "Weapons", UIParent)
    f:SetFrameStrata("LOW")
    f:SetSize(0.001, 1)
    f.buttons = {}
    f.accum = WEAPON_IDLE_INTERVAL -- check on the very first frame
    f:SetScript("OnUpdate", function(_, elapsed)
        f.accum = f.accum + elapsed
        -- The countdown needs the fast tick. With no enchant known a slow check
        -- is enough, since the enchant and inventory events below update the
        -- strip the moment one lands.
        local every = (#self.weaponEntries > 0 or (self.weaponCount or 0) > 0) and WEAPON_INTERVAL or WEAPON_IDLE_INTERVAL
        if f.accum < every then return end
        f.accum = 0
        self:UpdateWeapons()
    end)
    self.weaponFrame = f
    self.weaponWidth = 0
    self.weaponEntries = {}
    self.weaponScratch = {} -- the next read fills this, then the two swap
end

local function weaponButtonOnEnter(btn)
    local e = btn.entry
    if not e then return end
    GameTooltip:SetOwner(btn, "ANCHOR_BOTTOMLEFT")
    -- It's your equipped weapon, so "always compare" would show it next to
    -- itself. The game's flag lasts until the tooltip hides (SetOwner hides it
    -- on a new owner).
    if type(GameTooltip_SuppressAutomaticCompareItem) == "function" then
        GameTooltip_SuppressAutomaticCompareItem(GameTooltip)
    end
    if not pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", e.slot) then
        GameTooltip:SetText(e.name or L["Weapon Enchant"], 1, 1, 1)
    end
    GameTooltip:Show()
end

-- Plain buttons with no right-click cancel. The game's secure "cancelaura" by
-- weapon slot errors on Forever (SecureTemplates.lua:478 reads CANCELABLE_ITEMS,
-- which this client never defines), and CancelTemporaryEnchantment is
-- restricted to the game's own code. Being plain, they can be laid out in
-- combat, so an imbue cast mid-fight shows at once.
function BarMixin:WeaponButton(i)
    local f = self.weaponFrame
    local b = f.buttons[i]
    if b then return b end
    b = W.CreateIconButton(f)
    b:SetScript("OnEnter", weaponButtonOnEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.buttons[i] = b
    return b
end

-- Places a button per entry and sizes the strip when the enchants or the look
-- changed.
function BarMixin:LayoutWeapons(entries)
    local f = self.weaponFrame
    local n = #entries
    local size, spacing = self:Size(), self:Setting("spacing")
    local corner = self:Corner()
    local dir = corner == "TOPRIGHT" and -1 or 1
    local shown = self.weaponSlots or {}
    for i = 1, n do
        local btn = self:WeaponButton(i)
        btn.slot = entries[i].slot
        shown[i] = btn.slot
        btn:SetIconSize(size, self:BorderPx())
        btn:SetEdgeCategory(ENCHANT_KEY)
        btn:ClearAllPoints()
        btn:SetPoint(corner, f, corner, dir * (i - 1) * (size + spacing), 0)
        btn:SetAlpha(1)
        btn.shownAlpha = 1
        btn:Show()
    end
    for i = #shown, n + 1, -1 do shown[i] = nil end
    self.weaponSlots = shown
    for i = n + 1, #f.buttons do
        f.buttons[i].entry = nil
        f.buttons[i].slot = nil
        f.buttons[i]:Hide()
    end
    local width = 0
    if n > 0 then width = n * size + (n - 1) * spacing + (self:Setting("categoryGap") or 0) end
    f:SetSize(math.max(width, 0.001), self:Height())
    if width ~= self.weaponWidth then
        self.weaponWidth = width
        self:PlaceContainer()
    end
end

-- Whether the laid-out slots (in order) match the slots just read.
local function sameSlots(shown, entries)
    if not shown or #shown ~= #entries then return false end
    for i = 1, #entries do
        if shown[i] ~= entries[i].slot then return false end
    end
    return true
end

-- The last enchant read for a slot (as a slot-keyed table would hold it).
local function entryFor(entries, slot)
    for i = #entries, 1, -1 do
        if entries[i].slot == slot then return entries[i] end
    end
end

-- Draws an enchant on its button. Runs five times a second with mostly the same
-- values, so each piece is only set when its computed value changed.
local function paintWeapon(b, e, now)
    local icon = e.icon or W.QUESTION_ICON
    local plainIcon = BL.Plain(icon)
    if plainIcon == nil or plainIcon ~= b.shownIcon then
        b.shownIcon = plainIcon
        b.Icon:SetTexture(icon)
    end
    if e.applications ~= b.shownCount then
        b.shownCount = e.applications
        b:SetCount(e.applications)
    end
    local left = e.expirationTime - now
    local text, soon = BL.FormatTime(left), left < W.SOON
    if text ~= b.shownTime or soon ~= b.shownSoon then
        b.shownTime, b.shownSoon = text, soon
        b:SetTimeLeft(left, true)
    end
end

function BarMixin:UpdateWeapons()
    local f = self.weaponFrame
    if not f then return end
    -- The container draws oils, stones and poisons; the strip keeps the rest
    -- (imbues).
    local skip = self.enchantSlots and next(self.enchantSlots) and true or nil
    local entries, restricted, drawn = BL.Auras.CollectWeapons(true, self.weaponScratch, skip)
    -- A refused read keeps the last known enchants. Their expiry times are
    -- absolute, so the countdown continues. A good read swaps the two lists so
    -- the next read refills the older one.
    if restricted then
        entries = self.weaponEntries
    else
        -- How many the container draws feeds our copy of its layout.
        drawn = self.enchantsOn and drawn or 0
        if drawn ~= self.enchantCount then
            self.enchantCount = drawn
            self.flow = nil
        end
        self.weaponScratch, self.weaponEntries = self.weaponEntries, entries
    end
    local cat = BL.Categories.Get(ENCHANT_KEY)
    if (cat and cat.hidden) or self.previewActive or editModeActive then entries = NONE end
    -- Re-laid out when the slots (in order) change, so a swap re-points the
    -- buttons. The strip is plain and the container may be re-anchored in
    -- combat (PlaceContainer), so an imbue cast mid-fight shows at once. If the
    -- client ever marks either protected, it waits until after combat.
    if (not sameSlots(self.weaponSlots, entries) or self.weaponLayoutDirty)
        and not (inCombat() and (f:IsProtected() or self.frame:IsProtected())) then
        self.weaponCount = #entries
        self.weaponLayoutDirty = false
        self:LayoutWeapons(entries)
    end
    -- Each shown button draws the enchant on its own slot. In combat one that
    -- ran out just turns transparent until the strip can re-layout.
    local now = BL.Clock()
    for i = 1, self.weaponCount or 0 do
        local b = f.buttons[i]
        local e = b and entryFor(entries, b.slot)
        if b then
            b.entry = e
            local alpha = e and 1 or 0
            if alpha ~= b.shownAlpha then
                b.shownAlpha = alpha
                b:SetAlpha(alpha)
            end
        end
        if e then paintWeapon(b, e, now) end
    end
end

-- Buttons --------------------------------------------------------------

-- Called by the client once per button it creates for a group. The button
-- belongs to the client: we only decorate it and register the pieces it should
-- drive, and never read anything back. edgeKey: the category whose color it
-- uses when that's not its group's (the weapon slots, kept apart from the
-- Weapon group so its count badge stays off them).
function BarMixin:InitButton(btn, groupKey, edgeKey)
    btn.groupKey = groupKey
    btn.edgeKey = edgeKey
    W.Dress(btn)
    btn:SetIcon(btn.Icon)

    btn.Cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    btn.Cooldown:SetAllPoints(btn.Icon)
    btn.Cooldown:SetHideCountdownNumbers(true)
    btn.Cooldown:SetDrawSwipe(false)
    btn.Cooldown:SetDrawEdge(false)
    btn.Cooldown:SetDrawBling(false)
    btn.Cooldown:EnableMouse(false)
    btn:SetDurationCooldown(btn.Cooldown)
    btn:SetApplicationCount(btn.Count)

    -- Our own badge for consolidated groups (member count).
    btn.Badge = btn:CreateFontString(nil, "OVERLAY")
    DUI.Style.InkText(btn.Badge, "MONEY")
    btn.Badge:Hide()

    if self:IsDebuff() then
        -- The edge is the debuff's whole border, tinted by the client from its
        -- dispel type: both halves and the corner caps. Wine-colored until
        -- the client colors it.
        local w = BL.DISPEL_COLORS.None
        W.SetEdgeRGB(btn, w[1], w[2], w[3])
        registerDispelEdge(btn, btn.Edge)
        registerDispelEdge(btn, btn.EdgeR)
        for _, key in ipairs(W.CORNERS) do
            local c = W.CAP_COORDS[key]
            registerDispelEdge(btn, btn.Caps[key], W.FILLET, { left = c[1], right = c[2], top = c[3], bottom = c[4] })
        end
    else
        btn:SetCancelAuraButtons("RightButtonUp")
    end
    pcall(btn.SetTooltipAnchorPoint, btn, "ANCHOR_BOTTOMLEFT")
    -- Slides in when a new aura lands (played by the client; see BL.Feel).
    BL.Feel.MakeSlide(btn)

    self.buttons[groupKey] = self.buttons[groupKey] or {}
    table.insert(self.buttons[groupKey], btn)
    self:StyleButton(btn, groupKey)
end

function BarMixin:StyleButton(btn, groupKey)
    W.Fit(btn, self:Size(), self:BorderPx())
    -- The buff bar's time warms in its last seconds (BL.Feel). Rebound on every
    -- restyle so setting or motion changes reach it.
    Style.SetAuraTime(btn, btn.Duration, (not self:IsDebuff()) and BL.Feel.TimeColor() or nil)
    BL.Feel.TuneSlide(btn)
    if not self:IsDebuff() then
        W.PaintButtonEdge(btn, btn.edgeKey or groupKey)
    end
end

-- Re-applies sizes and colors to every button. Buttons can't be touched while
-- the client hides aura data (combat), so in that case it waits for the next
-- PLAYER_REGEN_ENABLED.
function BarMixin:Restyle()
    if not self.frame then return end
    -- The client's aura buttons are locked while auras are secret (combat, a
    -- PvP match, a boss), so restyle once that lifts.
    if DUI.Restricted() then
        self.restylePending = true
        DUI.AfterRestrictions(function() if self.restylePending then self:Restyle() end end,
            "buffs:restyle:" .. tostring(self))
        return
    end
    self.restylePending = false
    for key, list in pairs(self.buttons) do
        for _, btn in ipairs(list) do pcall(self.StyleButton, self, btn, key) end
    end
    self.weaponLayoutDirty = true
end

-- Readable data (out of combat) ------------------------------------------

-- Every group's members at once: { [groupKey] = members }, or nil when
-- restricted. Cached until the next aura change or group update, so the hover
-- poll doesn't re-read auras and rebuild spell sets ten times a second. Uses the
-- auras Learn already read for this change instead of reading again. Weapon
-- enchants aren't auras and have no members (the container's weapon slots are
-- counted in FlowGroups, the imbues belong to the strip).
function BarMixin:AllMembers()
    if self.membersCache then return self.membersCache end
    local entries = self.freshEntries
    if not entries then
        local restricted
        entries, restricted = BL.Auras.Collect("HELPFUL")
        if restricted then return nil end
    end
    local sets = BL.Spells.Sets()
    local byGroup = {}
    for _, id in ipairs(BL.Categories.Order()) do byGroup[id] = {} end
    for _, e in ipairs(entries) do
        local id = e.spellId
        local key = (id ~= nil and sets.categorised[id]) and sets.category[id] or "other"
        if not byGroup[key] then key = "other" end
        table.insert(byGroup[key], e)
    end
    for key, list in pairs(byGroup) do byGroup[key] = Layout.SortLikeClient(list) end
    self.membersCache = byGroup
    return byGroup
end

function BarMixin:InvalidateMembers()
    self.membersCache = nil
    self.freshEntries = nil
    self.flow = nil
end

-- The icon flow for these members (buff bar) or this many debuffs, cached until
-- they or the layout change, since the hover asks ten times a second.
function BarMixin:Flow(members)
    if self.flow and self.flowFor == members then return self.flow end
    local flow
    if self:IsDebuff() then
        local g = self:GroupLayout(1)
        g.key, g.count = "debuffs", members
        flow = Layout.Flow({ g }, self:FlowOptions())
    else
        flow = Layout.Flow(self:FlowGroups(members), self:FlowOptions())
    end
    self.flow, self.flowFor = flow, members
    return flow
end

-- The client's flow layout input for this bar, from readable data: first the
-- weapon slots it draws (their count from the enchant read, plain in combat
-- too), then one group per category in layout order with the number of buttons
-- it shows. The imbue strip is outside the container.
function BarMixin:FlowGroups(members)
    local groups = {}
    if (self.enchantCount or 0) > 0 then
        local layout = self:GroupLayout(0)
        groups[1] = {
            key = "enchants", count = self.enchantCount,
            elementWidth = layout.elementWidth, elementHeight = layout.elementHeight,
            elementSpacing = layout.elementSpacing, lineSpacing = layout.lineSpacing, groupSpacing = layout.groupSpacing,
            groupLineSpacing = layout.groupLineSpacing, forceNewLine = layout.forceNewLine,
        }
    end
    for index, id in ipairs(BL.Categories.Order()) do
        local cat = BL.Categories.Get(id)
        if cat then
            local layout = self:GroupLayout(index)
            local count = #(members[id] or NONE)
            if cat.hidden then
                count = 0
            elseif self.consolidated[id] then
                count = math.min(count, 1)
            end
            groups[#groups + 1] = {
                key = id, count = count,
                elementWidth = layout.elementWidth, elementHeight = layout.elementHeight,
                elementSpacing = layout.elementSpacing, lineSpacing = layout.lineSpacing, groupSpacing = layout.groupSpacing,
                groupLineSpacing = layout.groupLineSpacing, forceNewLine = layout.forceNewLine,
            }
        end
    end
    return groups
end

-- Maps the cursor (UI units) to the element under it, plus the group's
-- members, or nil. Only meaningful out of combat.
function BarMixin:ElementAt(x, y)
    if inCombat() or not self.holder then return nil end
    local members = self:AllMembers()
    if not members then return nil end
    local flow = self:Flow(members)
    local corner = self:Corner()
    local originX = corner == "TOPRIGHT" and self.holder:GetRight() or self.holder:GetLeft()
    local originY = self.holder:GetTop()
    if not originX or not originY then return nil end
    local scale = self:Scale()
    -- The container starts after the imbue strip.
    local along, down = self:ContainerOffset()
    local offset = along * scale
    originX = corner == "TOPRIGHT" and (originX - offset) or (originX + offset)
    originY = originY - down * scale
    local element = Layout.HitTest(flow, corner, (x - originX) / scale, (y - originY) / scale)
    if not element then return nil end
    return element, members[element.key] or {}, originX, originY, scale
end

-- The icon flow from readable data, or nil while auras can't be read.
function BarMixin:CurrentFlow()
    if inCombat() then return nil end
    if self:IsDebuff() then
        -- The count is read here, once per aura change, rather than on every
        -- change, since only this needs it.
        if self.countStale and not DUI.Restricted() then
            local entries, restricted = BL.Auras.Collect("HARMFUL")
            if not restricted then
                self.lastCount = #entries
                self.countStale = false
            end
        end
        return self:Flow(self.lastCount or 0)
    end
    local members = self:AllMembers()
    return members and self:Flow(members)
end

-- Whether the cursor is over the bar (icons, their times, the imbue strip). The
-- container's geometry is secret so asking it always says no; the answer comes
-- from our own layout numbers instead. The size is the last one measured out of
-- combat, so it still works in a fight.
function BarMixin:CursorOver()
    local holder = self.holder
    if not holder or self.previewActive or editModeActive then return false end
    local flow = self:CurrentFlow()
    if flow then self.flowWidth, self.flowHeight = flow.width, flow.height end
    local corner = self:Corner()
    local originX = corner == "TOPRIGHT" and holder:GetRight() or holder:GetLeft()
    local top = holder:GetTop()
    if type(originX) ~= "number" or type(top) ~= "number" then return false end
    local scale = self:Scale()
    local weapons = self.weaponWidth or 0
    local along, down = self:ContainerOffset()
    local width = math.max(along + (self.flowWidth or 0), weapons) * scale
    local height = math.max(down + (self.flowHeight or 0), weapons > 0 and self:Height() or 0) * scale
    if width <= 0 or height <= 0 then return false end
    local x, y = cursorUI()
    local along = corner == "TOPRIGHT" and (originX - x) or (x - originX)
    return along >= 0 and along <= width and y <= top + textRoom(self:Size()) * scale and y >= top - height
end

-- Learns spell ids from whatever is readable and refreshes counts.
function BarMixin:Learn()
    if self:IsDebuff() then
        -- The count is only needed by the hover (CurrentFlow), which reads it
        -- then.
        self.countStale = true
        return
    end
    self:InvalidateMembers()
    local entries, restricted = BL.Auras.Collect("HELPFUL")
    if restricted then return end
    self.lastCount = #entries
    -- Kept for AllMembers until the next change: one read per change.
    self.freshEntries = entries
    local changed = BL.Spells.Learn(entries)
    if not changed then self:RefreshCounts() end
    -- On a change, SPELLS_CHANGED re-applies the groups, which refreshes counts.
end

-- A consolidated group's count on its button. The buttons are the client's, so
-- a refused change is skipped.
local function setBadge(btn, n)
    if n > 1 then
        btn.Badge:SetText(n)
        btn.Badge:Show()
    else
        btn.Badge:Hide()
    end
end

function BarMixin:RefreshCounts()
    if not self.frame then return end
    -- The badges are on the client's aura buttons, which are locked while auras
    -- are secret (combat, a PvP match, a boss), so recount once that lifts.
    if DUI.Restricted() then
        DUI.AfterRestrictions(function() self:RefreshCounts() end, "buffs:counts:" .. tostring(self))
        return
    end
    if self:IsDebuff() then
        self.countStale = true
        return
    end
    -- Counts only show on consolidated groups, so with none (the default)
    -- nothing is read. This runs on every change to your auras, and re-reading
    -- them all with every learned spell's category made enough garbage to
    -- cause hitches.
    local members = next(self.consolidated) ~= nil and self:AllMembers() or nil
    for key, list in pairs(self.buttons) do
        local n = 0
        if self.consolidated[key] then
            n = members and #(members[key] or NONE) or (self.memberCounts[key] or 0)
        end
        -- Only set when the count or the buttons changed (or the last try was
        -- refused).
        if n ~= self.memberCounts[key] or #list ~= self.badged[key] then
            local ok = true
            for _, btn in ipairs(list) do ok = pcall(setBadge, btn, n) and ok end
            self.badged[key] = ok and #list or nil
        end
        self.memberCounts[key] = n
    end
end

-- /dui buffs debug: what each group is set to and how many members it has.
function BarMixin:PrintStatus()
    if not self.frame then
        BL.Print(self.scope .. " bar: no container")
        return
    end
    local state = groupState()
    BL.Print(string.format("%s bar: %s, in group %s, in raid %s", self.scope,
        inCombat() and "in combat (aura data withheld)" or "out of combat", tostring(state.inGroup), tostring(state.inRaid)))
    if self:IsDebuff() then return end
    local members = self:AllMembers()
    for _, id in ipairs(BL.Categories.Order()) do
        local cat = BL.Categories.Get(id)
        if cat then
            local list = members and (id == ENCHANT_KEY and BL.Auras.CollectWeapons(true) or members[id])
            local n = members and #(list or NONE) or -1
            BL.Print(string.format("  %s: consolidate=%s hidden=%s -> %s, members=%d",
                cat.name, tostring(cat.consolidate), tostring(cat.hidden),
                self.consolidated[id] and "one icon" or "all icons", n))
        end
    end
end

-- Interaction ------------------------------------------------------------

function BarMixin:OpenCategoryMenu(entry, owner)
    local name = entry and BL.Plain(entry.name)
    if type(name) ~= "string" then return end
    W.CategoryMenu(owner or self.shield or UIParent, BL.Classify.Resolve(entry), function(id)
        BL.Classify.Assign(name, id, "bar")
    end)
end

function BarMixin:OnShiftClick(x, y)
    if inCombat() then
        BL.Print(L["Buff categories can't be changed while in combat."])
        return
    end
    local element, members = self:ElementAt(x, y)
    if not element then return end
    local entry = members[element.index]
    if entry then self:OpenCategoryMenu(entry) end
end

-- Hover for consolidated groups. The client's buttons can't tell us when the
-- cursor enters them, so a light poll maps the cursor through the layout.
function BarMixin:PollHover()
    if not next(self.consolidated) or inCombat() or self.previewActive then return end
    if popoutShown then return end
    local x, y = cursorUI()
    local element, members, originX, originY, scale = self:ElementAt(x, y)
    if not element or not self.consolidated[element.key] then return end
    local l, b, r = Layout.ElementRect(element, self:Corner())
    self:ShowPopout(element.key, members, originX + (l + r) / 2 * scale, originY + b * scale)
end

-- Consolidated popout: a second container showing the whole group ----------

function BarMixin:EnsurePopout()
    if popout then return popout end
    local ok, c = pcall(CreateFrame, "AuraContainer", "DaylightUIBuffsPopout", UIParent, "CustomAuraContainerTemplate")
    if not ok or not c then return nil end
    popout = c
    c:SetUnit("player")
    c:SetFrameStrata("DIALOG")
    c:SetClampedToScreen(true)
    c:EnableMouse(false)
    c:Hide()
    local back = createCompanion("Frame", UIParent)
    back:SetFrameStrata("DIALOG")
    back:SetFrameLevel(math.max(0, c:GetFrameLevel() - 1))
    back:EnableMouse(false)
    Style.Shell(back, { borderPx = 2, noBevel = true, bgAlpha = 0.95 })
    back:Hide()
    popoutBack = back
    c.back = back
    c.shield = createShield(c, "DIALOG", function(x, y)
        local bar = c.bar
        if bar then bar:OnPopoutShiftClick(x, y) end
    end)
    -- Keep the popout while the cursor is inside it or over its owner slot.
    -- Both rectangles come from our own layout numbers, since the frames'
    -- geometry derives from the container's secret size and can't be read.
    local function inside(rect, x, y)
        return rect and x >= rect.left and x <= rect.right and y >= rect.bottom and y <= rect.top
    end
    back:SetScript("OnUpdate", function()
        if not popoutShown or not popoutLeaveAt then return end
        local x, y = cursorUI()
        -- The consolidated icon's tooltip is the client's own aura tooltip,
        -- not GameTooltip, so nothing of ours hides it. GameTooltip is never
        -- hidden from our code.
        if inside(popoutRect, x, y) or inside(popoutOwner, x, y) then
            popoutLeaveAt = BL.Clock() + POPOUT_LEAVE_DELAY
            return
        end
        -- Its cancel buttons are secure, so if a fight starts while it's open
        -- it stays until the fight ends.
        if BL.Clock() >= popoutLeaveAt and not inCombat() then
            popoutShown = false
            popoutOwner = nil
            popoutLeaveAt = nil
            BL.FadePopout(c, back, 0, function()
                if popoutShown then return end
                c:Hide()
                back:Hide()
                -- Hidden at full alpha, since a show under a restriction can't set it back.
                pcall(c.SetAlpha, c, 1)
                back:SetAlpha(1)
                popoutFade.a = nil
            end)
        end
    end)
    return c
end

-- The popout fades in and out together with its backing, FAST. The client's
-- container goes through pcall and only while nothing is restricted (its buttons
-- lock then); under a restriction it shows and hides instantly.
function BL.FadePopout(c, back, to, done)
    local M = DUI.Motion
    -- Start from where a running fade had it (hovered again mid-fade).
    local from = popoutFade.a or (1 - to)
    if DUI.Restricted() or not M.On() then from = to end
    M.Tween(popoutFade, from, to, M.FAST, function(a)
        popoutFade.a = a
        pcall(c.SetAlpha, c, a)
        back:SetAlpha(a)
    end, done)
end

-- anchorX/anchorY: UI-unit point (bottom center of the owning icon).
function BarMixin:ShowPopout(groupKey, members, anchorX, anchorY)
    local c = self:EnsurePopout()
    if not c then return end
    local sets = BL.Spells.Sets()
    local filters = (groupKey == "other") and { excludeSpellIDs = sets.categorised } or { includeSpellIDs = sets.byCategory[groupKey] or {} }
    local layout = self:GroupLayout(1)
    layout.groupSpacing = 0
    c.bar = self
    c.groupKey = groupKey
    c.members = members
    if not c.hasGroup then
        local ok = pcall(c.AddAuraGroup, c, "members", "HELPFUL", {
            candidateFilters = filters,
            sortMethod = AuraContainerSortMethod.ExpirationOnly,
            sortDirection = AuraContainerSortDirection.Normal,
            layout = layout,
            initializeFrame = function(btn) self:InitPopoutButton(btn) end,
        })
        c.hasGroup = ok
    else
        pcall(c.SetAuraGroupCandidateFilters, c, "members", filters)
        pcall(c.SetAuraGroupLayout, c, "members", layout)
    end
    local size, spacing = self:Size(), self:Setting("spacing")
    local room = textRoom(size)
    c.flowOptions = { anchorPoint = "TOPLEFT", horizontal = Layout.RIGHT, vertical = Layout.DOWN, maximumLineSize = POPOUT_COLUMNS * (size + spacing) }
    c.flowGroup = { key = groupKey, count = #members, elementWidth = size, elementHeight = W.Height(size), elementSpacing = spacing,
        lineSpacing = layout.lineSpacing, groupSpacing = 0 }
    pcall(function()
        c:SetFlowLayoutMaximumLineSize(c.flowOptions.maximumLineSize)
        c:SetFlowLayoutAnchorPoint("TOPLEFT")
        c:SetFlowLayoutGrowthDirection(Layout.RIGHT, Layout.DOWN)
    end)
    -- Centered under the icon in UI units, with room above each row for the
    -- time on the icons' top edges.
    local scale = self:Scale()
    local flow = Layout.Flow({ c.flowGroup }, c.flowOptions)
    -- Member tooltips hang below the whole popout, clear of every row.
    c.tooltipOffset = -(flow.height - W.Height(size) + POPOUT_PAD)
    for _, btn in ipairs(c.buttons or {}) do pcall(self.StylePopoutButton, self, btn, groupKey) end
    c.originX = anchorX - flow.width * scale / 2
    c.originY = anchorY - POPOUT_PAD - room
    c:SetScale(scale)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", c.originX / scale, c.originY / scale)
    popoutBack:ClearAllPoints()
    popoutBack:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", c.originX - POPOUT_PAD, c.originY + POPOUT_PAD + room)
    popoutBack:SetSize(flow.width * scale + 2 * POPOUT_PAD, flow.height * scale + 2 * POPOUT_PAD + room)
    Style.LayoutShell(Style.GetShell(popoutBack))
    popoutOwner = { left = anchorX - size * scale / 2, right = anchorX + size * scale / 2, bottom = anchorY, top = anchorY + W.Height(size) * scale }
    popoutRect = {
        left = c.originX - POPOUT_PAD, right = c.originX + flow.width * scale + POPOUT_PAD,
        top = c.originY + POPOUT_PAD + room, bottom = c.originY - flow.height * scale - POPOUT_PAD,
    }
    popoutLeaveAt = BL.Clock() + POPOUT_LEAVE_DELAY
    local was = popoutShown
    popoutShown = true
    c:Show()
    popoutBack:Show()
    if not was then BL.FadePopout(c, popoutBack, 1) end
end

function BarMixin:OnPopoutShiftClick(x, y)
    local c = popout
    if not c or inCombat() then return end
    local scale = self:Scale()
    local flow = Layout.Flow({ c.flowGroup }, c.flowOptions)
    local element = Layout.HitTest(flow, "TOPLEFT", (x - c.originX) / scale, (y - c.originY) / scale)
    local entry = element and c.members and c.members[element.index]
    if entry then self:OpenCategoryMenu(entry, c.shield) end
end

function BarMixin:InitPopoutButton(btn)
    local c = popout
    c.buttons = c.buttons or {}
    table.insert(c.buttons, btn)
    W.Dress(btn)
    btn:SetIcon(btn.Icon)
    btn.Cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    btn.Cooldown:SetAllPoints(btn.Icon)
    btn.Cooldown:SetHideCountdownNumbers(true)
    btn.Cooldown:SetDrawSwipe(false)
    btn.Cooldown:SetDrawEdge(false)
    btn.Cooldown:SetDrawBling(false)
    btn:SetDurationCooldown(btn.Cooldown)
    Style.SetAuraTime(btn, btn.Duration, BL.Feel.TimeColor())
    btn:SetApplicationCount(btn.Count)
    btn:SetCancelAuraButtons("RightButtonUp")
    self:StylePopoutButton(btn, c.groupKey)
end

function BarMixin:StylePopoutButton(btn, groupKey)
    W.Fit(btn, self:Size(), self:BorderPx())
    W.PaintButtonEdge(btn, groupKey)
    -- The client places these tooltips itself; its anchor API is the only way
    -- to move them.
    local offset = popout and popout.tooltipOffset or -POPOUT_PAD
    pcall(btn.SetTooltipAnchorPoint, btn, "ANCHOR_BOTTOM", 0, offset)
end

-- Preview (fake buffs) hides the live container while it runs ---------------

-- The fade engine is held off the bar meanwhile, or its next step would bring
-- the live bar back through the preview (Edit Mode holds it too).
function BarMixin:FadeKey() return self:IsDebuff() and "Buffs.debuffs" or "Buffs.buffs" end

function BarMixin:SetPreviewActive(active)
    if not self.frame then return end
    self.previewActive = active
    if active then DUI.Fade.Hold(self:FadeKey(), true) end
    self.frame:SetAlpha(active and 0 or 1)
    if not active and not editModeActive then DUI.Fade.Hold(self:FadeKey(), false) end
    self:UpdateWeapons()
    if self.shield then
        self.shield.suspended = active and true or false
        applyShields()
    end
end

-- Coalesced refresh ---------------------------------------------------------

function BarMixin:MarkDirty()
    self.flow = nil -- categories or settings changed, so re-layout
    if self.scheduled or not self.frame then return end
    self.scheduled = true
    C_Timer.After(0, function()
        self.scheduled = false
        self:ApplyGroups()
    end)
end

-- Everything that depends on the settings, re-applied.
function BarMixin:ApplyAll()
    if not self.frame then return end
    self:ApplyScale()
    self:ApplyBackground()
    self:ApplySize()
    self:ApplyFlow()
    self:MarkDirty()
end

function BL.CreateBar(spec)
    local bar = Mixin({}, BarMixin)
    bar.scope = spec.scope
    bar.frameName = spec.frameName
    bar.label = spec.label
    bar.moverKey = spec.moverKey
    bar.default = spec.default
    return bar
end

-- ---------------------------------------------------------------------
-- The buff bar
-- ---------------------------------------------------------------------

-- Where the bars start: just left of the info panel's framed body (under the XP
-- bar), clear of its fold tab. The buffs' first row is level with its top (the
-- time above the icons touching it) and the debuffs' first row sits on the
-- body's bottom edge. Anchored to the panel itself, so the bars slide along when
-- it narrows (meter folded away, hidden out of a group) or widens, with nothing
-- to watch. Without the panel they use the screen's top-right corner, debuffs a
-- few rows lower. A bar the player has moved keeps its spot.
BL.ANCHOR = "DaylightUIBuffsAnchor"
BL.DEBUFF_ANCHOR = "DaylightUIDebuffsAnchor"
BL.PANEL = "DaylightUIInfoPanelBody"
BL.PANEL_EDGE = "DaylightUIInfoPanelEdge"
BL.ANCHOR_GAP = 20 -- from the panel's left edge (its fold tab is 14)
BL.ANCHOR_EDGE = 12 -- from the screen corner, without the panel
BL.DEBUFF_DROP = 120 -- without the panel: debuffs this far below the buffs

local anchor = CreateFrame("Frame", BL.ANCHOR, UIParent)
anchor:SetSize(1, 1)
local debuffAnchor = CreateFrame("Frame", BL.DEBUFF_ANCHOR, UIParent)
debuffAnchor:SetSize(1, 1)

-- A bar setting, usable before the database exists too.
local function setting(key, scope)
    if not BL.DB then
        local d = BL.DEFAULTS.settings
        return (scope == "debuff" and d.debuff or d)[key]
    end
    return BL.GetSetting(key, scope)
end

function BL.PlaceAnchor()
    local panel = _G[BL.PANEL]
    -- The bars' containers are scaled; these frames aren't.
    local scale = BL.DB and DUI.Movers.Scale("buffs.buff") or 1
    local room = textRoom(setting("iconSize")) * scale
    local dScale = BL.DB and DUI.Movers.Scale("buffs.debuff") or 1
    local dHeight = W.Height(setting("iconSize", "debuff")) * dScale
    anchor:ClearAllPoints()
    debuffAnchor:ClearAllPoints()
    if panel then
        -- The buffs follow the panel's edge as the info panel reports it,
        -- pushed out past its threat meter while that's slid out.
        local edge = _G[BL.PANEL_EDGE] or panel
        anchor:SetPoint("TOPRIGHT", edge, "TOPLEFT", -BL.ANCHOR_GAP, -room)
        debuffAnchor:SetPoint("TOPRIGHT", panel, "BOTTOMLEFT", -BL.ANCHOR_GAP, dHeight)
    else
        anchor:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -BL.ANCHOR_EDGE, -(BL.ANCHOR_EDGE + room))
        debuffAnchor:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, -BL.DEBUFF_DROP)
    end
end
BL.PlaceAnchor()
-- The panel is built at login, after this module (modules enable in load
-- order), so place again once every module is up.
DUI.On("Login", function() BL.PlaceAnchor() end)
DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function() BL.PlaceAnchor() end)

BL.Bar = BL.CreateBar({ scope = "buff", frameName = "DaylightUIBuffs", label = "Buffs", moverKey = "buffs.buff",
    default = { "TOPRIGHT", BL.ANCHOR, "TOPRIGHT", 0, 0 } })

function BL.EachBar(fn)
    if BL.Bar and BL.Bar.frame then fn(BL.Bar) end
    if BL.DebuffBar and BL.DebuffBar.frame then fn(BL.DebuffBar) end
end
local eachBar = BL.EachBar

-- ---------------------------------------------------------------------
-- Hiding the client's own buff/debuff frames
-- ---------------------------------------------------------------------

local hidingHooked = false
local pendingHide = false

local guarding = false
local function guardShow(frame)
    if guarding or editModeActive or not BL.DB.settings.hideBlizzardFrames then return end
    if inCombat() then
        -- Still at alpha 0 from the last hide; really hidden once the fight ends.
        pendingHide = true
    else
        guarding = true
        frame:Hide()
        frame:SetAlpha(0)
        guarding = false
    end
end

local function setStockFramesHidden(hidden)
    for _, frame in ipairs({ BuffFrame, DebuffFrame }) do
        if hidden then
            frame:Hide()
            frame:SetAlpha(0)
        else
            frame:SetAlpha(1)
            frame:Show()
        end
    end
end

-- Never trust our own Edit Mode flag alone; ask the client.
local function refreshEditModeFlag()
    if EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive then
        local ok, active = pcall(EditModeManagerFrame.IsEditModeActive, EditModeManagerFrame)
        if ok then editModeActive = (active == true) end
    end
end

function BL.ApplyBlizzardHiding()
    if not (BuffFrame and DebuffFrame) then return end
    if inCombat() then
        pendingHide = true
        return
    end
    pendingHide = false
    refreshEditModeFlag()
    if not hidingHooked then
        hidingHooked = true
        -- The game re-shows them with Show (Edit Mode) or SetShown
        -- (AuraFrameEditModeMixin:UpdateShownState). Both fire OnShow at once,
        -- so the re-hide lands in the same frame. Neither frame has an OnShow in
        -- the game's XML, so HookScript just sets ours.
        for _, frame in ipairs({ BuffFrame, DebuffFrame }) do
            frame:HookScript("OnShow", guardShow)
        end
        -- The game re-shows these when Edit Mode (re)applies its layout.
        if EventRegistry and EventRegistry.RegisterCallback then
            pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.SavedLayouts.LayoutsApplied", function()
                if not editModeActive then BL.ApplyBlizzardHiding() end
            end, BL)
        end
    end
    setStockFramesHidden(BL.DB.settings.hideBlizzardFrames and not editModeActive)
end

-- ---------------------------------------------------------------------
-- Edit Mode: while it's open the stock frames show (so the game's layout can be
-- edited as usual) and our bars step aside, then return on exit. Our bars are
-- moved in DaylightUI's unlock mode.
-- ---------------------------------------------------------------------

local function onEditModeEnter()
    -- The preview sets the bars' alpha itself while Edit Mode is open.
    DUI.Fade.Hold("Buffs.buffs", true); DUI.Fade.Hold("Buffs.debuffs", true)
    editModeActive = true
    if BuffFrame and DebuffFrame and not inCombat() then setStockFramesHidden(false) end
    eachBar(function(bar) bar.frame:SetAlpha(0); bar:UpdateWeapons() end)
end

local function onEditModeExit()
    editModeActive = false
    eachBar(function(bar)
        bar.frame:SetAlpha(bar.previewActive and 0 or 1)
        bar:UpdateWeapons()
    end)
    BL.ApplyBlizzardHiding()
    -- A running preview keeps its hold.
    eachBar(function(bar) if not bar.previewActive then DUI.Fade.Hold(bar:FadeKey(), false) end end)
end

if EventRegistry and EventRegistry.RegisterCallback then
    pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Enter", onEditModeEnter, BL)
    pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Exit", onEditModeExit, BL)
end

-- ---------------------------------------------------------------------
-- Building, and the events that keep the bars current
-- ---------------------------------------------------------------------

function BL.BuildBars()
    DUI.SafeCall(function() BL.Bar:Create() end)
    DUI.SafeCall(function() if BL.DebuffBar then BL.DebuffBar:Create() end end)
    DUI.SafeCall(BL.ApplyBlizzardHiding)
    eachBar(function(bar) DUI.SafeCall(bar.Learn, bar) end)
    -- One list per area, refilled, since the fade asks often. The fade can't
    -- see the mouse over a container, so the bar answers (`over`).
    local buffs, debuffs = {}, {}
    DUI.Fade.Register{ key = "Buffs.buffs", scope = BL.MODULE, path = "settings.fade", page = "Buffs.buffs",
        frames = function()
            buffs[1], buffs[2] = BL.Bar.frame, BL.Bar.weaponFrame
            return buffs
        end, whole = true, over = function() return BL.Bar:CursorOver() end }
    if BL.DebuffBar and BL.DebuffBar.frame then
        DUI.Fade.Register{ key = "Buffs.debuffs", scope = BL.MODULE, path = "settings.debuff.fade", page = "Buffs.debuffs",
            frames = function()
                debuffs[1] = BL.DebuffBar.frame
                return debuffs
            end, whole = true, over = function() return BL.DebuffBar:CursorOver() end }
    end
end

DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    eachBar(function(bar) bar:Learn() end)
    if BL.Bar.frame then C_Timer.After(1, BL.ApplyBlizzardHiding) end
end)
-- A specialization change reapplies the game's layout without the layouts
-- event (EditModeManager.lua).
for _, e in ipairs({ "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_SPECIALIZATION_CHANGED" }) do
    DUI.RegisterEvent(e, function()
        if BL.Bar.frame and not editModeActive then BL.ApplyBlizzardHiding() end
    end)
end

-- Out of combat every aura change is a chance to learn a new spell id. In combat
-- the client keeps the bar current by itself. A weapon enchant applied, removed
-- or swapped shows at once (as the game's buff frame does), regardless of the
-- strip's tick.
BL.OnPlayer("UNIT_INVENTORY_CHANGED", function()
    if BL.Bar.frame then BL.Bar:UpdateWeapons() end
end)
local function weaponsChanged()
    if BL.Bar.frame then BL.Bar:UpdateWeapons() end
end
DUI.RegisterEvent("WEAPON_ENCHANT_CHANGED", weaponsChanged)
DUI.RegisterEvent("WEAPON_SLOT_CHANGED", weaponsChanged)

local function learnAll() eachBar(function(bar) bar:Learn() end) end
-- Once next frame, however many came in: a pre-pull rebuff sends a burst.
local learnQueued = false
local function learnSoon()
    if learnQueued then return end
    learnQueued = true
    C_Timer.After(0, function()
        learnQueued = false
        DUI.SafeCall(learnAll)
    end)
end

BL.OnPlayer("UNIT_AURA", function(_, unit)
    -- Registered for the player only. Under restrictions the client sends the
    -- unit token itself as a secret (SecretWhenAurasRestricted in the game
    -- docs), so a secret one is the player too.
    local secret = issecretvalue and issecretvalue(unit)
    if (not secret and unit ~= "player") or inCombat() then return end
    -- Under a boss, keystone or PvP restriction the auras are secret, so read
    -- once when it lifts instead of failing on every change.
    if DUI.Restricted() then
        DUI.AfterRestrictions(learnAll, "buffs:learn")
        return
    end
    learnSoon()
    if BL.Bar.frame and BL.DB.settings.hideBlizzardFrames and BuffFrame and BuffFrame:IsShown() then
        BL.ApplyBlizzardHiding()
    end
end)

-- Float: an aura gained or lost (not refreshed) brings its bar back for a
-- while. Each aura seen arriving is remembered with its bar, so its removal
-- wakes that bar; one that can't be read (secret, or present from before) wakes
-- both.
local auraBar = {}   -- auraInstanceID -> "buffs" | "debuffs"
-- A table that's safe to look into: not a secret value or a secret table.
local function readable(t)
    return type(t) == "table" and not (issecretvalue and issecretvalue(t)) and BL.PlainTable(t) ~= nil
end
local function wakeAuras(info)
    local buffs, debuffs = false, false
    local function wake(kind)
        if kind == "buffs" then buffs = true
        elseif kind == "debuffs" then debuffs = true
        else buffs, debuffs = true, true end
    end
    if not readable(info) then
        wake()
    elseif not issecretvalue(info.isFullUpdate) and info.isFullUpdate == true then
        wipe(auraBar) -- a loading screen: everything is read again, nothing is new
        return
    else
        local added, removed = info.addedAuras, info.removedAuraInstanceIDs
        if type(added) == "table" then
            if not readable(added) then wake() else
                for _, a in ipairs(added) do
                    local id, harmful
                    if readable(a) then id, harmful = BL.Plain(a.auraInstanceID), BL.Plain(a.isHarmful) end
                    local kind = harmful == true and "debuffs" or harmful == false and "buffs" or nil
                    if id ~= nil and kind then auraBar[id] = kind end
                    wake(kind)
                end
            end
        end
        if type(removed) == "table" then
            if not readable(removed) then wake() else
                for _, id in ipairs(removed) do
                    id = BL.Plain(id)
                    local kind = id ~= nil and auraBar[id] or nil
                    if id ~= nil then auraBar[id] = nil end
                    wake(kind)
                end
            end
        end
    end
    if buffs then DUI.Fade.Wake("Buffs.buffs") end
    if debuffs then DUI.Fade.Wake("Buffs.debuffs") end
end
BL.OnPlayer("UNIT_AURA", function(_, _, info)
    if DUI.Fade.Floats("Buffs.buffs") or DUI.Fade.Floats("Buffs.debuffs") then wakeAuras(info) end
end)

-- Of the roster, only being in a group or raid matters to the groups (the "only
-- in a group/raid" consolidation). Other roster changes, which come in bursts
-- in a raid, are ignored.
DUI.RegisterEvent("GROUP_ROSTER_UPDATE", function()
    local bar = BL.Bar
    if bar.frame and (IsInGroup() ~= bar.appliedInGroup or IsInRaid() ~= bar.appliedInRaid) then
        bar:MarkDirty()
    end
end)

DUI.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if pendingHide then BL.ApplyBlizzardHiding() end
    eachBar(function(bar)
        bar:InvalidateMembers()
        if bar.restylePending then bar:Restyle() end
        bar:Learn()
    end)
end)

BL.On("CATEGORIES_CHANGED", function() if BL.Bar.frame then BL.Bar:MarkDirty() end end)
BL.On("CATEGORY_COLOR_CHANGED", function() if BL.Bar.frame then BL.Bar:Restyle() end end)
BL.On("OVERRIDES_CHANGED", function() if BL.Bar.frame then BL.Bar:MarkDirty() end end)
BL.On("SPELLS_CHANGED", function() if BL.Bar.frame then BL.Bar:MarkDirty() end end)
BL.On("AURAS_CHANGED", function()
    eachBar(function(bar) bar:SetPreviewActive(BL.Preview.Active()) end)
end)
-- Settings both bars share (their text).
local SHARED = { timeSize = true, countSize = true, showTimers = true, timePos = true, textOutline = true }

BL.On("SETTINGS_CHANGED", function(key, scope)
    -- Opacity and fade belong to the fade engine; nothing to lay out.
    if string.find(key, "^fade%.") then return end
    if SHARED[key] then
        eachBar(function(bar) bar:Restyle(); bar:ApplyAll() end)
        return
    end
    if key == "hideBlizzardFrames" then
        BL.ApplyBlizzardHiding()
        return
    end
    if key == "expiring" then
        if BL.Bar.frame then BL.Bar:Restyle() end
        return
    end
    if key == "newGlow" then
        eachBar(function(bar) bar:Restyle() end)
        return
    end
    if key == "borderPx" then
        local bar = (scope == "debuff") and BL.DebuffBar or BL.Bar
        if bar and bar.frame then bar:Restyle(); bar:ApplyAll() end
        return
    end
    if key == "attach" then
        local bar = (scope == "debuff") and BL.DebuffBar or BL.Bar
        if bar and bar.frame then bar:ApplyAttach() end
        return
    end
    local bar = (scope == "debuff") and BL.DebuffBar or BL.Bar
    if bar and bar.frame then bar:ApplyAll() end
end)
