-- Skins the Cooldown Manager's buff bars (BuffBarCooldownViewer) that the player put
-- in one of their bar blocks (CdmRows): a small square icon plus a thin bar, sized
-- by the block. Bars in no block stay the game's, sized in Edit Mode.

local _, ns = ...
local DUI = DaylightUI
local Pixel = DUI.Pixel
local CD = ns.Cooldowns

local BB = {}
ns.BuffBars = BB

BB.VIEWER = "BuffBarCooldownViewer"
-- A number that is safe to do math on (never a secret).
local function num(v)
    if type(v) ~= "number" or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

local function usable(item)
    return not (InCombatLockdown() and item.IsProtected and item:IsProtected())
end

-- Lays out one bar at width x height: square icon on the left, bar filling the rest
-- after a 1px gap (or all of it with the icon off).
local sizing = false
local function layoutBar(item, p, w, h)
    local icon, bar = p.host, p.bar
    item:SetSize(w, h)
    -- The bar sits one border width inside its space, since its border frame
    -- (CD.PlaceSlot) fills the space exactly.
    local T = p.slot and Pixel.Px(bar, DUI.Style.BorderPx(p.slot)) or 0
    bar:ClearAllPoints()
    if BB.WantIcon(item, p) then
        if not icon:IsShown() then icon:Show() end
        local is, fs = num(icon:GetEffectiveScale()), num(item:GetEffectiveScale())
        local side = (is and fs and is > 0) and h * fs / is or h
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", item, "TOPLEFT", 0, 0)
        icon:SetSize(side, side)
        bar:SetPoint("TOPLEFT", icon, "TOPRIGHT", Pixel.Px(bar, 1) + T, -T)
    else
        bar:SetPoint("TOPLEFT", item, "TOPLEFT", T, -T)
    end
    bar:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", -T, T)
    CD.PlaceSlot(item)
end

-- The block's Show icon setting overrides the game's bar content (Edit Mode's
-- "Name only" hides the icon). Only for bars in a block.
function BB.WantIcon(item, p)
    local block = ns.CdmRows and ns.CdmRows.BlockOf(item)
    return block ~= nil and ns.CdmData.Look(block, "icon") ~= false and p.host ~= item
end

-- A bar in a block takes the block's size (w, h in the item's own units), given or
-- remembered. A bar in no block is left alone.
function BB.LayoutBar(item, w, h)
    local R = ns.CdmRows
    if not (R and R.Owns(item)) then return end
    if not w then w, h = R.Size(item) end
    local p = CD.Parts(item)
    if sizing or not (p and p.bar and w and h) or not usable(item) then return end
    sizing = true
    DUI.SafeCall(layoutBar, item, p, w, h)
    sizing = false
end

-- Bars skinned at least once. While in a block they are reshaped whenever the game
-- sizes them, and their icon is kept. The time text stays the game's: a post-hook on
-- it made the game's own SetText fail ("attempt to call a nil value" in
-- CooldownViewer.lua RefreshCooldownInfo).
local attached = setmetatable({}, { __mode = "k" })
function BB.Attach(item)
    if attached[item] then return end
    attached[item] = true
    local p = CD.Parts(item)
    -- When the game hides the icon for its bar content (Edit Mode "Name only" via
    -- SetBarContent, which also adds a point to the bar), show it again and re-lay
    -- the bar the next frame, as long as the block wants it shown. SetBarContent
    -- always comes with a layout pass, so the reclaim pass (CD.Soon) covers it.
    -- No hooks on the game's Hide/SetShown/SetBarContent: hooking its own methods
    -- broke its calls.
    if p and p.host ~= item and p.host.HookScript then
        local soon = false
        local function keepIcon()
            soon = false
            if BB.WantIcon(item, p) and not p.host:IsShown() then
                p.host:Show()
                BB.LayoutBar(item)
            end
        end
        p.host:HookScript("OnHide", function()
            if soon or not BB.WantIcon(item, p) then return end
            soon = true
            C_Timer.After(0, function() DUI.SafeCall(keepIcon) end)
        end)
    end
    if item.HookScript then item:HookScript("OnSizeChanged", function() BB.LayoutBar(item) end) end
end

-- Time on the game's bars as M:SS ---------------------------------------
-- The game writes a bar's time as whole seconds ("178") with string.format, and the
-- text can't be hooked (see BB.Attach). So each spell on a game bar gets a clock
-- over the bar's right end: a holder with the client's aura container inside
-- (CdmAuras.Setup), whose one button carries a time text the client updates itself,
-- in and out of combat, in our format. The game's text is hidden underneath. A bar
-- timing a totem (no aura to find) or showing Edit Mode's sample keeps the game's
-- text, as does a spell first seen in combat until the fight ends, since aura
-- containers can only be made out of combat.
BB.CLOCK_W = 48      -- width of the clock box at the bar's right end
BB.CLOCK_PAD = 4     -- gap between the time and the bar's right edge

local clocks = {}    -- [cooldownID] = holder
local clockGen = 0   -- bumped on a style change so every clock re-fits
DUI.On("StyleChanged", function() clockGen = clockGen + 1 end)

local function clockLayout(h)
    return { layoutIndex = 1, elementWidth = h.w, elementHeight = h.h, elementSpacing = 0 }
end

-- Only inside the client's initializeFrame or after restrictions. Otherwise the
-- client has locked the button and its text.
local function dressClock(h, btn, fs)
    btn:SetSize(h.w, h.h)
    fs:SetFont(DUI.Style.FontFile(ns.MEDIA.font), h.size, DUI.Style.Outline())
    CD.Ink(fs, h.color or DUI.Style.INK.VALUE)
end

local function initClock(h, btn)
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- Anchored to the holder, not the button: the client sizes and places its
    -- button itself, which put the time too low on the bar.
    fs:SetPoint("RIGHT", h, "RIGHT", -BB.CLOCK_PAD, 0)
    fs:SetJustifyH("RIGHT")
    h.parts = h.parts or {}
    h.parts[btn] = fs
    pcall(dressClock, h, btn, fs)
    pcall(DUI.Style.SetAuraTime, btn, fs, nil, DUI.Style.ClockFormatter())
    if btn.SetMouseMotionEnabled then pcall(btn.SetMouseMotionEnabled, btn, false) end
end

local function clockFor(id)
    local h = clocks[id]
    if h then return h end
    if InCombatLockdown() or not ns.CdmAuras then return nil end
    h = CreateFrame("Frame", nil, UIParent)
    h.w, h.h, h.size = BB.CLOCK_W, 18, CD.TEXT
    h.layoutFor, h.init = clockLayout, initClock
    h:Hide()
    clocks[id] = h
    DUI.SafeCall(ns.CdmAuras.Setup, h, id)
    ns.CdmAuras.Track(h)
    return h
end

-- Sets the bar height and the time's size and color. The container slot changes at
-- once, the client's button only after restrictions.
local function fitClock(h, height, size, color)
    local key = table.concat({ tostring(height), tostring(size), color[1], color[2], color[3], clockGen }, "|")
    if key == h.fitAs then return end
    h.fitAs, h.h, h.size, h.color = key, height, size, color
    for _, k in ipairs(h.containers or {}) do
        pcall(k.c.SetAuraGroupLayout, k.c, "a", clockLayout(h))
        pcall(k.c.SetFlowLayoutMaximumLineSize, k.c, h.w)
    end
    DUI.AfterRestrictions(function()
        for btn, fs in pairs(h.parts or {}) do pcall(dressClock, h, btn, fs) end
    end, "cdm:clock:" .. tostring(h.id))
end

-- Reads the game's own item through its getters (never secret).
local function says(item, method)
    local get = item[method]
    if type(get) ~= "function" then return false end
    local ok, v = pcall(get, item)
    return ok and type(v) ~= "nil" and not (issecretvalue and issecretvalue(v)) and v ~= false
end

local function look(item)
    local block = ns.CdmRows and ns.CdmRows.BlockOf(item)
    if block and block.kind == "bar" then
        local t = CD.BarText(block)
        return ns.CdmData.Look(block, "time") ~= false, t.timeSize, t.timeColor
    end
    return true, CD.TEXT, DUI.Style.INK.VALUE
end

local used = {}
local function syncOne(item)
    local bar = item.Bar
    local text = type(bar) == "table" and bar.Duration
    if type(text) ~= "table" or not text.SetShown then return end
    local id = num(item.cooldownID)
    local on, size, color = look(item)
    local h = id and not used[id] and not says(item, "GetTotemData") and not says(item, "HasEditModeData")
        and clockFor(id)
    if h and (h.err or #(h.containers or {}) == 0) then h = nil end
    if not h then
        if text:IsShown() ~= on then text:SetShown(on) end
        return
    end
    used[id] = true
    if h.item ~= item then
        -- Follow the spell's current bar, since the game recycles its pooled bars.
        h:SetParent(bar)
        h:ClearAllPoints()
        h:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
        h:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
        h:SetWidth(BB.CLOCK_W)
        h:SetFrameLevel(bar:GetFrameLevel() + 4)
        if not h.item then
            for _, k in ipairs(h.containers) do pcall(k.c.SetEnabled, k.c, true) end
        end
        h.item = item
    end
    fitClock(h, num(bar:GetHeight()) or 18, size, color)
    h:SetAlpha(on and 1 or 0)
    if not h:IsShown() then h:Show() end
    if text:IsShown() then text:SetShown(false) end
end

-- Gives every visible game bar either our clock or the game's own time. Called from
-- the reclaim pass, the scan tick (a totem going up or down) and style changes.
function BB.SyncClocks()
    local v = _G[BB.VIEWER]
    if type(v) ~= "table" then return end
    wipe(used)
    CD.EachItem(v, function(item) DUI.SafeCall(syncOne, item) end)
    for id, h in pairs(clocks) do
        if not used[id] and h.item then
            h.item = nil
            h:Hide()
            for _, k in ipairs(h.containers or {}) do pcall(k.c.SetEnabled, k.c, false) end
        end
    end
end

function BB.Clock(id) return clocks[id] end
