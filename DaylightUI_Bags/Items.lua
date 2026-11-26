-- One bag slot. It's the game's own bag button, so using, dragging, splitting,
-- linking and selling all stay the game's. Restyled here and filled the same
-- way the game fills its own bags.
--
-- The button's bag is its holder's ID (Bags.lua) and its slot is its own ID.
-- Never call the button's SetBagID: it sets a secure attribute, and setting that
-- from addon code taints item use.

local _, ns = ...
local DUI = DaylightUI
local isSecret = DUI.IsSecret
local Style, Pixel = DUI.Style, DUI.Pixel

local Items = {}
ns.Items = Items

Items.TEMPLATE = "ContainerFrameItemButtonTemplate"
-- A slot is a colored ring between two thin black lines, all inside the button,
-- around a square cropped icon with a soft inner shadow. The ring is one flat
-- color (two pixels is too thin for the shell's heavy band) and casts no shadow,
-- so slots sit as close as their spacing says. An empty slot has a thinner, dim
-- ring around a dark well.
Items.EDGE_PX = 1            -- black line outside the ring
Items.BORDER_PX = 2          -- the ring
Items.THIN_PX = 1            -- an empty slot's ring
Items.GAP_PX = 1             -- black line between the ring and the icon
Items.SHELL = { noBevel = true, noBackground = true, shadowPx = 0, shadowAlpha = 0 }
Items.BLACK = Style.BORDER

-- A shell keeps the opts table it's given and its border color is written into
-- it, so each slot needs its own copy or coloring one colors them all.
function Items.ShellOpts()
    local o = {}
    for k, v in pairs(Items.SHELL) do o[k] = v end
    o.borderPx = function() return o.thin and Items.THIN_PX or Items.BORDER_PX end
    return o
end

-- How far in from the button's edge the icon (or an empty slot's well) starts.
function Items.Inset(btn, thin)
    return Pixel.Px(btn, Items.EDGE_PX + (thin and Items.THIN_PX or Items.BORDER_PX) + Items.GAP_PX)
end

-- The ring for a slot-looking button: a black backing the size of the button
-- (it shows as the two black lines) under a ring shell one pixel in. Returns the
-- shell and the backing.
function Items.Frame(btn)
    local shell = Style.Shell(btn, Items.ShellOpts())
    local back = shell:CreateTexture(nil, "BACKGROUND", nil, -7)
    back:SetAllPoints(btn)
    local c = Items.BLACK
    back:SetColorTexture(c[1], c[2], c[3], 1)
    Items.FitRing(btn, shell)
    return shell, back
end

-- Keeps the ring one pixel inside the button (the pixel depends on the button's
-- scale, so this runs on every layout).
function Items.FitRing(btn, shell)
    local e = Pixel.Px(btn, Items.EDGE_PX)
    if shell.dluiEdge == e then return end
    shell.dluiEdge = e
    shell:ClearAllPoints()
    shell:SetPoint("TOPLEFT", btn, "TOPLEFT", e, -e)
    shell:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -e, e)
    Style.Shell(btn, shell.opts)
end
Items.CROP = DaylightUI.Style.ICON_CROP
Items.SHADE = DUI.MEDIA .. "inner-shadow.png"
Items.SHADE_ALPHA = 0.55
Items.COUNT_SIZE = Style.SIZE.tiny
Items.FREE_SIZE = Style.SIZE.small
-- Ring colors for an empty slot (a dim warm line), common (a light gray, so
-- every item reads as a slot), poor (a darker gray) and the Hearthstone (light
-- blue, easy to spot). Everything else uses its quality color.
Items.EMPTY = { 0.165, 0.149, 0.125 }
Items.WELL = { 0.063, 0.063, 0.071 }   -- inside an empty slot, a shade under the window
Items.COMMON = { 0.6, 0.6, 0.6 }
Items.POOR = { 0.36, 0.36, 0.36 }
Items.POOR_ALPHA = 0.5
Items.HEARTH = { 0.45, 0.75, 1 }
-- Profession bag colors by the bag type bit the game reports. Their empty slots
-- and plain (common or poor) items use this color.
Items.BAG_COLORS = {
    { bit = 1,    color = { 0.67, 0.83, 0.45 } },  -- quiver, hunter green
    { bit = 2,    color = { 0.67, 0.83, 0.45 } },  -- ammo pouch
    { bit = 4,    color = { 0.58, 0.4, 0.9 } },    -- soul bag, warlock purple
    { bit = 8,    color = { 0.8, 0.62, 0.42 } },   -- leatherworking, light brown
    { bit = 16,   color = { 0.35, 0.55, 0.85 } },  -- inscription, ink blue
    { bit = 32,   color = { 0.2, 0.6, 0.45 } },    -- herbs, deep leaf green
    { bit = 64,   color = { 0.9, 0.5, 0.85 } },    -- enchanting, pink
    { bit = 128,  color = { 0.9, 0.78, 0.3 } },    -- engineering, brass
    { bit = 512,  color = { 0.35, 0.85, 0.85 } },  -- gems, cyan
    { bit = 1024, color = { 0.48, 0.32, 0.2 } },   -- mining, dark brown
}

-- Which profession bag type a bag is: its index in BAG_COLORS (0 = ordinary bag).
function Items.BagKind(bag)
    if type(bag) ~= "number" then return 0 end
    local _, family = Items.FreeAt(bag)
    if type(family) ~= "number" or family <= 0 then return 0 end
    for i, e in ipairs(Items.BAG_COLORS) do
        if family % (e.bit * 2) >= e.bit then return i end
    end
    return 0
end

-- A profession bag's color (nil for an ordinary bag).
function Items.BagColor(bag)
    local e = Items.BAG_COLORS[Items.BagKind(bag)]
    return e and e.color
end
-- Item overlays. Bind type is only shown while unbound.
Items.BIND_TEXT = { [2] = "BoE", [3] = "BoU" }   -- bind type: 2 on equip, 3 on use
Items.BIND_SIZE = Style.SIZE.tiny
Items.BIND_COLOR = { Style.INK.GOOD[1], Style.INK.GOOD[2], Style.INK.GOOD[3], 0.8 }   -- BoE can still be sold or traded
Items.SET_SIZE = 5           -- equipment set mark, px
Items.LOCK_SIZE = 11         -- lock mark, px
Items.DOT_GLOW = 2.2        -- glow size, times the dot
Items.DOT_GLOW_ALPHA = 0.3
Items.DOT_PX = 6            -- new-item dot, centered on the slot's top left corner
Items.KEEP_PX = 2           -- line under a kept slot (Keep.lua)
Items.LOCK_ATLAS = "QuestSharing-Padlock"   -- the game's own padlock (from its action button level lock)
Items.LEVEL_SIZE = Style.SIZE.tiny   -- gear item level, bottom left (same size as the character window's)
Items.COOLDOWN_SIZE = Style.SIZE.body   -- the game's countdown text ("37m"), fits the smallest slot
-- The game's art has its own fixed size, drawn for a 37 px slot. It never follows
-- the button, so Items.Place scales it (ContainerFrame.xml).
Items.GAME_SLOT = 37
Items.GAME_SIZED = { "IconQuestTexture", "NewItemTexture", "BattlepayItemTexture" }
Items.HOVER_MIX = 1          -- how far a hovered ring moves toward the accent
-- Loot shine: a new item of uncommon or better gets one diagonal glint across
-- its icon while its border flashes bright and settles back.
Items.SHINE_QUALITY = 2      -- uncommon and up
Items.SHINE_DUR = 0.6        -- glint duration, seconds
Items.SHINE_ALPHA = 0.7      -- peak alpha
Items.SHINE_WIDTH = 0.5      -- band width as a fraction of the icon
Items.SHINE_TILT = -math.pi / 6   -- leans 30 degrees, like /
Items.SHINE_LIFT = 0.6       -- flash: how far the border color moves toward white
Items.WHITE = "Interface\\Buttons\\WHITE8x8"

local dressed = setmetatable({}, { __mode = "k" })   -- button -> its pieces
local EMPTY = {}

local function call(obj, method, ...)
    local fn = obj and obj[method]
    if type(fn) == "function" then return pcall(fn, obj, ...) end
end

local function run(fn, ...)
    if type(fn) == "function" then return pcall(fn, ...) end
end

local function font(fs, size) Style.DressText(fs, size) end

-- What's in a bag slot (nil if empty or the game refused). Shared by the bag
-- helpers (Stack, Swap, Junk) so cursor and combat checks live in one place.
-- Saved copies (Saved.lua) are read from there.
function Items.InfoAt(bag, slot)
    if ns.Saved.Is(bag) then return ns.Saved.Info(bag, slot) end
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    return ok and info or nil
end

-- A bag's free slots and family (what it can hold), like the game's
-- GetContainerNumFreeSlots. nil when the game refused.
function Items.FreeAt(bag)
    if ns.Saved.Is(bag) then return ns.Saved.Free(bag) end
    local ok, n, family = pcall(C_Container.GetContainerNumFreeSlots, bag)
    if ok then return n, family end
end
function Items.CursorBusy() return type(CursorHasItem) == "function" and CursorHasItem() end
function Items.InCombat() return InCombatLockdown and InCombatLockdown() end

function Items.Parts(btn) return dressed[btn] end

-- The template replaces its button's SetAlpha with one that only sets the icon,
-- quality frame and count (ItemButtonMixin:SetAlpha), so a fade through it left
-- the ring popping in, an empty slot's picture back and a grayed item bright.
-- Slots fade through the frame's own SetAlpha instead.
local function frameSetAlpha(btn)
    local mt = getmetatable(btn)
    local index = mt and mt.__index
    if type(index) == "table" then return index.SetAlpha end
    if type(index) == "function" then return index(btn, "SetAlpha") end
end

-- What to fade for a region in the bag: a slot's stand-in that sets the
-- button's own alpha (one per slot, so tweens keep their key), else the region.
local faders = setmetatable({}, { __mode = "k" })
function Items.Fader(r)
    if not dressed[r] then return r end
    local f = faders[r]
    if f then return f end
    local set = frameSetAlpha(r)
    if type(set) ~= "function" then return r end
    f = {
        SetAlpha = function(_, a) set(r, a) end,
        GetAlpha = function() return r:GetAlpha() end,
        IsShown = function() return r:IsShown() end,
        Show = function() r:Show() end,
        Hide = function() r:Hide() end,
    }
    faders[r] = f
    return f
end

-- The window a slot belongs to (via its holder), and that window's settings.
local function windowOf(btn)
    local h = btn:GetParent()
    return h and h.dluiWindow
end
-- A mouse right-click on a bag item uses it through the game's secure item
-- action ("bag slot", like /use), not through the slot's own click: the slot is
-- this addon's button, so the game's click code runs tainted, and the use left
-- the game's state tainted until a reload (the controller then refused its own
-- calls). One secure button follows the pointer: out of combat it sits on the
-- slot under it and takes right-clicks only; left clicks, drags and hovering go
-- through to the slot. It takes the pointer too (a frame that ignores the pointer
-- gets no clicks), so it shows the slot's tooltip and highlight while on it.
-- Only with the game's controller UI on, where the taint matters: with it off a
-- right-click stays exactly the game's. Also off (the slot's own click instead)
-- in a fight, with a modifier key down, with an item on the cursor, while a
-- spell is targeting (Disenchant goes through the slot, so a locked slot can
-- refuse it, see Guard.lua), on a locked slot, and where a right-click hands the
-- item over (Window.HandsOver: vendor, bank, mail, trade, auction house...).
local useButton    -- the secure use button, made on the first hover
local useSlot      -- the slot under the pointer, kept through a fight
local enteringFromUseButton = false

-- One strata above the slot's: the bag is a top-level window, so a click raises
-- it and its slots above anything at their own strata, this button included.
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
local function strataAbove(strata)
    for i, strataName in ipairs(STRATA) do
        if strataName == strata then return STRATA[math.min(i + 1, #STRATA)] end
    end
    return "HIGH"
end

-- The same bag and slot as the controller's X (padItem in Window.lua).
local function bagAndSlotOf(slotButton)
    local holder = slotButton:GetParent()
    local bag = slotButton.GetBagID and slotButton:GetBagID() or (holder and holder.GetID and holder:GetID())
    return bag, slotButton:GetID()
end

local function controllerUIOn()
    return DUI.Pad ~= nil and DUI.Pad.On() == true
end

local function spellTargeting()
    return type(SpellIsTargeting) == "function" and SpellIsTargeting() == true
end

-- Whether the slot (or this button over it) is still the frame under the pointer.
-- A menu or popup that opened over the slot since then keeps it, so the button
-- isn't put back on top of it.
local function stillUnderPointer(slotButton)
    if type(GetMouseFoci) == "function" then
        local foci = GetMouseFoci()
        local topFrame = type(foci) == "table" and foci[1] or nil
        return topFrame == slotButton or (useButton ~= nil and topFrame == useButton)
    end
    return slotButton.IsMouseOver ~= nil and slotButton:IsMouseOver() == true
end

-- The magnifier over an item the dressing-room key would try on, or one that can
-- be read. The game's slot picks its pointer from hasItem and readable, which
-- Items.Fill leaves alone, and sets it again on every tooltip refresh. So this
-- runs after the slot's own enter and after each of the tooltip's updates.
local cursorSlot   -- the slot under the pointer
local tooltipWatched = false

function Items.Cursor()
    local slotButton = cursorSlot
    if not slotButton or spellTargeting() or type(ShowInspectCursor) ~= "function" then return end
    local tryOn = slotButton.dluiShown ~= nil and type(IsModifiedClick) == "function" and IsModifiedClick("DRESSUP")
    local selling = type(CanSellItems) == "function" and CanSellItems()
    if tryOn or (slotButton.dluiReadable and not selling) then ShowInspectCursor() end
end

local function cursorOver(slotButton)
    -- Only the game's own bag button: an alt's saved item has no pointer of its own.
    if not slotButton.GetBagID then return end
    cursorSlot = slotButton
    if not tooltipWatched and GameTooltip and GameTooltip.HookScript then
        tooltipWatched = true
        GameTooltip:HookScript("OnUpdate", function(tip)
            if cursorSlot and tip:GetOwner() == cursorSlot then Items.Cursor() end
        end)
    end
    Items.Cursor()
end

-- keepSlot: remember the slot, so a later event can put the button back on it.
-- enteringCombat: called from PLAYER_REGEN_DISABLED, which comes just before the
-- lockdown, so the button can still be moved off even if the game says combat.
function Items.UseOff(keepSlot, enteringCombat)
    if not keepSlot then useSlot = nil end
    if not useButton or (Items.InCombat() and not enteringCombat) then return end
    useButton:Hide()
    useButton:ClearAllPoints()
end

-- After an event (modifier, cursor, cast, end of a fight): back over the slot
-- only if the pointer is still on it.
local function useAgain()
    if useSlot then Items.UseOver(useSlot, true) end
end

local function makeUseButton()
    if useButton then return useButton end
    useButton = CreateFrame("Button", "DaylightUIBagUse", UIParent, "SecureActionButtonTemplate")
    -- Both presses: the game acts on the down or the up one depending on
    -- ActionButtonUseKeyDown (SecureActionButton_OnClick), and ignores the other.
    useButton:RegisterForClicks("RightButtonDown", "RightButtonUp")
    -- A /use macro, not the "item" action: that one equips anything wearable by
    -- name first, so a quest item you can also wear was put on instead of
    -- starting its quest. /use on a bag slot is UseContainerItem, the bag's own
    -- right click.
    useButton:SetAttribute("type2", "macro")
    if useButton.SetPassThroughButtons then
        useButton:SetPassThroughButtons("LeftButton", "MiddleButton", "Button4", "Button5")
    end
    -- The slot's tooltip and highlight while the pointer is on this instead.
    -- The slot's own enter runs again (the game's tooltip); the hooks in
    -- Items.Dress skip what already ran for this slot.
    useButton:SetScript("OnEnter", function()
        local slotButton = useSlot
        if not slotButton then return end
        if slotButton.LockHighlight then slotButton:LockHighlight() end
        local onEnter = slotButton:GetScript("OnEnter")
        if onEnter then
            enteringFromUseButton = true
            DUI.SafeCall(onEnter, slotButton)
            enteringFromUseButton = false
        end
    end)
    useButton:SetScript("OnLeave", function()
        local slotButton = useSlot
        Items.UseOff()
        if not slotButton then return end
        if slotButton.UnlockHighlight then slotButton:UnlockHighlight() end
        -- Back onto the slot itself: it gets its own enter. Otherwise it's left.
        if not (slotButton.IsMouseOver and slotButton:IsMouseOver()) then
            local onLeave = slotButton:GetScript("OnLeave")
            if onLeave then onLeave(slotButton) end
        end
    end)
    -- Alt-right-click picks the item's group (Items.Dress): a modifier keeps
    -- this off, so the slot's own click does it.
    useButton:Hide()
    -- Before the fight's lockdown: off the slot, so nothing protected hangs on it.
    DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function() Items.UseOff(true, true) end)
    -- After it: back on the slot still under the pointer, without a new hover.
    DUI.RegisterEvent("PLAYER_REGEN_ENABLED", useAgain)
    DUI.RegisterEvent("MODIFIER_STATE_CHANGED", useAgain)
    DUI.RegisterEvent("CURSOR_CHANGED", useAgain)
    -- A spell starts or stops targeting (Disenchant on the cursor).
    DUI.RegisterEvent("CURRENT_SPELL_CAST_CHANGED", useAgain)
    return useButton
end

-- fromEvent: called again after an event, not by the slot's own enter.
function Items.UseOver(slotButton, fromEvent)
    useSlot = slotButton
    if Items.InCombat() then return end
    local bag, slot = bagAndSlotOf(slotButton)
    local ours = ns.window and windowOf(slotButton) == ns.window
    if not ours or not controllerUIOn() or type(bag) ~= "number" or type(slot) ~= "number"
        or slotButton.dluiGuarded or spellTargeting()
        or (IsModifierKeyDown and IsModifierKeyDown()) or Items.CursorBusy()
        or (ns.Window and ns.Window.HandsOver(Items.InfoAt(bag, slot)))
        or (fromEvent and not stillUnderPointer(slotButton)) then
        return Items.UseOff(true)
    end
    local button = makeUseButton()
    button:SetAttribute("macrotext", "/use " .. bag .. " " .. slot)
    button:ClearAllPoints()
    button:SetAllPoints(slotButton)
    button:SetFrameStrata(strataAbove(slotButton:GetFrameStrata()))
    button:Show()
end

local function setting(btn, key)
    local w = windowOf(btn)
    if w and w.Setting then return w.Setting(key) end
    return ns.Setting(key)
end

-- Hide the game's slot art and quality ring; the border is colored by quality
-- here instead. Done on every paint because the game can swap in a new slot
-- texture later and the art would come back.
local GAME_ART = { "IconBorder", "ItemSlotBackground" }
local function hideGameArt(btn)
    local normal = btn.GetNormalTexture and btn:GetNormalTexture()
    if type(normal) == "table" and normal.SetAlpha then normal:SetAlpha(0) end
    for _, key in ipairs(GAME_ART) do
        local r = btn[key]
        if type(r) == "table" and r.SetAlpha then r:SetAlpha(0) end
    end
    -- The template's own SetAlpha also sets its quality border's alpha, so every
    -- fade of a slot (new loot easing in, a bag hovered in the strip) brought back
    -- the game's white frame. With no anchor it can't draw at all.
    local border = btn.IconBorder
    if type(border) == "table" and border.ClearAllPoints and border:GetNumPoints() > 0 then
        border:ClearAllPoints()
    end
end

-- Reports a slot to plugins (DaylightUI.API's "bagslot" kind, unit "bag:slot",
-- saved viewer copies as previews) and lets them paint it after every fill.
-- The info table is one per button, refilled each time.
function Items.Report(btn, bag, slot, info)
    local R = DUI.APIReport
    if type(R) ~= "table" or type(bag) ~= "number" or type(slot) ~= "number" then return end
    local t = btn.dluiApiInfo
    if not t then t = {}; btn.dluiApiInfo = t end
    t.bag, t.slot = bag, slot
    t.itemID = info and info.itemID or nil
    t.link = info and info.hyperlink or nil
    t.quality = info and info.quality or nil
    t.count = info and info.stackCount or nil
    R.SetInfo(btn, t)
    local key, preview = bag .. ":" .. slot, ns.Saved.Is(bag) == true
    if not btn.dluiApi then
        btn.dluiApi = true
        R.Made("bagslot", btn, key, preview)   -- painted as soon as it's created
        return
    end
    R.Unit("bagslot", btn, key, preview)
    if R.Painting("bagslot") then R.Painted("bagslot", btn, t) end
end

-- Paints the ring: one color for border and band. A lit slot (its bag hovered)
-- is all accent; a hovered one eases toward it.
function Items.Ring(p, color)
    local c = color or p.color
    if not c then return end
    if p.lit then
        Style.LightShell(p.shell, 1)
        return
    end
    local t = p.hoverT or 0
    if t > 0 then
        local r, g, b = Style.Accent()
        t = t * Items.HOVER_MIX
        c = { c[1] + (r - c[1]) * t, c[2] + (g - c[2]) * t, c[3] + (b - c[3]) * t }
    end
    Style.SetShellColors(p.shell, c, c)
end

-- Eases a slot's ring toward the accent while the pointer is on it.
function Items.Hover(btn, on, snap)
    local p = dressed[btn]
    if not p then return end
    p.hover = on or nil
    if snap then
        if not on and (p.hoverT or 0) == 0 then return end
        p.hoverT = 0
        if p.hoverState then DUI.Motion.Tween(p.hoverState, 0, 0, 0) end
        Items.Ring(p)
        return
    end
    local from = p.hoverT or 0
    local to = on and 1 or 0
    if from == to then return end
    p.hoverState = p.hoverState or {}
    DUI.Motion.Tween(p.hoverState, from, to, DUI.Motion.FAST, function(t)
        p.hoverT = t
        if not p.flash then Items.Ring(p) end
    end)
end

-- The game's new-item glows on a slot. Its store glow (BattlepayItemTexture, a
-- blue square) starts out shown, and the game's UpdateNewItem shows it for a new
-- store item. Blue squares were seen staying in emptied slots after selling.
local GLOWS = { "flash", "NewItemTexture", "BattlepayItemTexture" }
local function hideGlows(btn)
    for _, key in ipairs(GLOWS) do
        local t = btn[key]
        if type(t) == "table" and t.Hide then t:Hide() end
    end
end

-- Restyles a new button (once).
function Items.Dress(btn)
    if dressed[btn] then return dressed[btn] end
    local p = {}
    dressed[btn] = p
    p.shell, p.back = Items.Frame(btn)
    p.well = p.shell:CreateTexture(nil, "BACKGROUND", nil, -6)
    local w = Items.WELL
    p.well:SetColorTexture(w[1], w[2], w[3], 1)
    p.well:Hide()
    hideGameArt(btn)
    hideGlows(btn)
    -- Original size of each piece of the game's art (Items.ScaleArt).
    p.art = {}
    for _, key in ipairs(Items.GAME_SIZED) do
        local r = btn[key]
        if type(r) == "table" and r.GetSize and r.SetSize then
            local w, h = r:GetSize()
            if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
                p.art[#p.art + 1] = { r, w, h }
            end
        end
    end
    local cd = btn.Cooldown or btn.cooldown
    local countdown = type(cd) == "table" and cd.GetCountdownFontString and cd:GetCountdownFontString()
    if countdown then font(countdown, Items.COOLDOWN_SIZE) end
    p.shade = btn:CreateTexture(nil, "ARTWORK", nil, 3)
    p.shade:SetTexture(Items.SHADE)
    p.shade:SetVertexColor(0, 0, 0, Items.SHADE_ALPHA)
    -- Overlays: bind type top left, equipment set mark top right, gear item level
    -- bottom left (the count stays bottom right).
    p.bind = btn:CreateFontString(nil, "OVERLAY")
    p.bind:Hide()
    p.level = btn:CreateFontString(nil, "OVERLAY")
    p.level:Hide()
    p.set = btn:CreateTexture(nil, "OVERLAY", nil, 3)
    p.set:SetColorTexture(1, 1, 1, 1)
    p.set:Hide()
    -- Locked item (never sold or disenchanted): a small padlock top right, with the
    -- set mark next to it.
    p.lock = btn:CreateTexture(nil, "OVERLAY", nil, 4)
    p.lock:SetAtlas(Items.LOCK_ATLAS)
    p.lock:SetDesaturated(true)
    p.lock:Hide()
    -- A slot Clean Up leaves alone (Keep.lua): an accent line along the bottom.
    p.keep = btn:CreateTexture(nil, "OVERLAY", nil, 2)
    p.keep:SetColorTexture(1, 1, 1, 1)
    p.keep:Hide()
    -- New item not looked at yet: a small accent dot on the top left corner (clear of
    -- the bind text, which sits just inside it). Hovering the slot clears it.
    p.newGlow = btn:CreateTexture(nil, "OVERLAY", nil, 4)
    p.newGlow:SetColorTexture(1, 1, 1, 1)
    p.newGlow:Hide()
    p.newDot = btn:CreateTexture(nil, "OVERLAY", nil, 5)
    p.newDot:SetColorTexture(1, 1, 1, 1)
    p.newDot:Hide()
    for _, t in ipairs({ p.newGlow, p.newDot }) do
        local m = btn:CreateMaskTexture()
        m:SetTexture(DUI.Win.MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(t)
        t:AddMaskTexture(m)
    end
    -- The game's upgrade arrow is always hidden; its junk coin is a setting.
    if type(btn.UpgradeIcon) == "table" and btn.UpgradeIcon.SetAlpha then btn.UpgradeIcon:SetAlpha(0) end
    -- Free slot count on a grouped section's free tile.
    p.free = btn:CreateFontString(nil, "OVERLAY")
    p.free:SetPoint("CENTER", btn, "CENTER", 0, 0)
    p.free:Hide()
    -- Loot glint: a soft band (two halves fading out from the middle) in a clipping
    -- frame over the icon. Hidden until a shine.
    p.clip = CreateFrame("Frame", nil, btn)
    p.clip:SetClipsChildren(true)
    p.glint = CreateFrame("Frame", nil, p.clip)
    p.glint:Hide()
    for i, side in ipairs({ "left", "right" }) do
        local t = p.glint:CreateTexture(nil, "OVERLAY")
        t:SetTexture(Items.WHITE)
        t:SetBlendMode("ADD")
        t:SetRotation(Items.SHINE_TILT)
        if CreateColor then
            local a, b = CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 1)
            t:SetGradient("HORIZONTAL", i == 1 and a or b, i == 1 and b or a)
        end
        p[side] = t
    end
    local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if hl then hl:SetColorTexture(1, 1, 1, 0.12) end
    local pushed = btn.GetPushedTexture and btn:GetPushedTexture()
    if pushed then pushed:SetColorTexture(0, 0, 0, 0.3) end
    -- Alt-right-click picks this item's group (the game does nothing with that
    -- click on a bag item). A plain right click or an Alt-left-click at the
    -- Auction House puts the item on the Sell tab of Daylight UI's auction
    -- window; the auction addon decides which of the two its setting takes.
    btn:HookScript("OnClick", function(self, button)
        local alt = IsAltKeyDown and IsAltKeyDown()
        local other = (IsShiftKeyDown and IsShiftKeyDown()) or (IsControlKeyDown and IsControlKeyDown())
        if button == "RightButton" and alt then
            if ns.Categories then ns.Categories.Menu(self) end
            return
        end
        if not DUI.AuctionHouseSell or other then return end
        local click = (button == "RightButton" and not alt and "right")
            or (button == "LeftButton" and alt and "alt") or nil
        if not click then return end
        local bag, slot = bagAndSlotOf(self)
        if type(bag) == "number" and type(slot) == "number" then DUI.AuctionHouseSell(bag, slot, click) end
    end)
    -- A locked item's slot takes no clicks at a vendor or while Disenchant is targeting.
    -- Looking at a new item clears its dot.
    -- Reaching for a slot mid-cleanup shows the real items first (Window.SortTouched).
    btn:HookScript("OnEnter", function(self)
        Items.NoCompare(self)
        Items.Hover(self, true)
        cursorOver(self)
        -- Entered again through the secure use button over it (Items.UseOver):
        -- the pointer never left this slot, so the rest already ran.
        if enteringFromUseButton then return end
        Items.UseOver(self)
        -- Disenchant staying on: its cast button goes over this slot.
        if ns.Disenchant and ns.window and windowOf(self) == ns.window then ns.Disenchant.SlotOver(self) end
        if ns.Window then ns.Window.SortTouched(windowOf(self)) end
        if self.dluiNew then Items.SeeNew(self) end
    end)
    btn:HookScript("OnLeave", function(self)
        -- The pointer just went onto the secure use button over this slot: still here.
        if useSlot == self and useButton and useButton:IsShown() and useButton:IsMouseOver() then return end
        -- The same for Disenchant's cast button (staying on).
        if ns.Disenchant and ns.Disenchant.Covers(self) then return end
        Items.Hover(self, false)
        if cursorSlot == self then cursorSlot = nil end
        if useSlot == self then Items.UseOff() end
    end)
    -- No leave comes when the slot hides under the pointer, so let go here.
    btn:HookScript("OnHide", function(self)
        Items.Hover(self, false, true)
        if cursorSlot == self then cursorSlot = nil end
        if useSlot == self then Items.UseOff() end
        if ns.Disenchant and not Items.InCombat() then ns.Disenchant.SlotOff(self) end
    end)
    btn:HookScript("PreClick", function(self)
        if ns.Window then ns.Window.SortTouched(windowOf(self)) end
    end)
    btn:HookScript("OnMouseUp", function(self, button)
        if self.dluiGuarded then ns.Guard.Refused(self, button) end
    end)
    -- A split made while trade, mail or the auction house is open gets put down in
    -- a free bag slot (Stack.AfterSplit).
    if ns.Stack then ns.Stack.Hook(btn) end
    Items.Place(btn)
    return p
end

-- With compareItems off, a bag item's tooltip stands alone: the game's slot
-- has just shown the worn item beside it (its "always compare" setting), so
-- that goes, and the flag keeps the 0.2 s refresh from bringing it back until
-- the tooltip hides. Holding Shift still compares, as in the game.
function Items.NoCompare(btn)
    if ns.Setting("compareItems") ~= false then return end
    local tip = _G.GameTooltip
    if type(tip) ~= "table" or tip:GetOwner() ~= btn then return end
    if type(GameTooltip_SuppressAutomaticCompareItem) == "function" then
        GameTooltip_SuppressAutomaticCompareItem(tip)
    end
    if IsModifiedClick and IsModifiedClick("COMPAREITEMS") then return end
    if type(GameTooltip_HideShoppingTooltips) == "function" and type(tip.shoppingTooltips) == "table" then
        GameTooltip_HideShoppingTooltips(tip)
    end
end

-- Scales the game's art to this slot's size, keeping the shape and position it
-- was drawn for. Only when the size changed, since every layout places every slot.
function Items.ScaleArt(btn, p)
    local size = btn:GetWidth()
    if type(size) ~= "number" or size <= 0 or p.artSize == size then return end
    p.artSize = size
    local k = size / Items.GAME_SLOT
    for _, a in ipairs(p.art) do a[1]:SetSize(a[2] * k, a[3] * k) end
end

-- A corner dot's glow size. It never reaches more than a pixel past the gap
-- into the next slot, so small spacing shrinks it, down to no glow at all.
function Items.GlowSize(btn, dot)
    local w = windowOf(btn)
    local gap = w and w.Setting and tonumber(w.Setting("spacing")) or 2
    return math.min(dot * Items.DOT_GLOW, math.max(dot, (gap - 1) * 2))
end

-- Icon inside the border, and everything positioned off it; text in the addon font.
function Items.Place(btn)
    local p = dressed[btn]
    if not p then return end
    Items.ScaleArt(btn, p)
    Items.FitRing(btn, p.shell)
    local T = Items.Inset(btn)
    local W = Items.Inset(btn, true)
    p.well:ClearAllPoints()
    p.well:SetPoint("TOPLEFT", btn, "TOPLEFT", W, -W)
    p.well:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -W, W)
    local icon = btn.icon or btn.Icon
    if icon then
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", btn, "TOPLEFT", T, -T)
        icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -T, T)
        icon:SetTexCoord(Items.CROP[1], Items.CROP[2], Items.CROP[3], Items.CROP[4])
        p.shade:ClearAllPoints()
        p.shade:SetAllPoints(icon)
        p.clip:ClearAllPoints()
        p.clip:SetAllPoints(icon)
        for _, key in ipairs({ "IconOverlay", "IconOverlay2", "searchOverlay", "ItemContextOverlay" }) do
            local r = btn[key]
            if type(r) == "table" and r.ClearAllPoints then
                r:ClearAllPoints()
                r:SetAllPoints(icon)
            end
        end
        local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
        if hl then hl:ClearAllPoints(); hl:SetAllPoints(icon) end
        local pushed = btn.GetPushedTexture and btn:GetPushedTexture()
        if pushed then pushed:ClearAllPoints(); pushed:SetAllPoints(icon) end
        local cd = btn.Cooldown or btn.cooldown
        if type(cd) == "table" and cd.ClearAllPoints then
            cd:ClearAllPoints()
            cd:SetAllPoints(icon)
        end
    end
    font(p.bind, Items.BIND_SIZE)
    p.bind:ClearAllPoints()
    p.bind:SetPoint("TOPLEFT", btn, "TOPLEFT", T + 1, -T - 1)
    local c = Items.BIND_COLOR
    p.bind:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    font(p.level, Items.LEVEL_SIZE)
    p.level:ClearAllPoints()
    p.level:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", T + 1, T + 2)
    Style.InkText(p.level, "VALUE")
    local m = Pixel.Px(btn, Items.SET_SIZE)
    p.set:ClearAllPoints()
    p.set:SetSize(m, m)
    p.set:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -T - 1, -T - 1)
    p.setBeside = nil
    local k = Pixel.Px(btn, Items.LOCK_SIZE)
    p.lock:ClearAllPoints()
    p.lock:SetSize(k, k)
    p.lock:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -T, -T)
    local dot = Pixel.Px(btn, Items.DOT_PX)
    p.newDot:ClearAllPoints()
    p.newDot:SetSize(dot, dot)
    p.newDot:SetPoint("CENTER", btn, "TOPLEFT", -2, 2)
    local glow = Items.GlowSize(btn, dot)
    p.newGlow:ClearAllPoints()
    p.newGlow:SetSize(glow, glow)
    p.newGlow:SetPoint("CENTER", p.newDot, "CENTER", 0, 0)
    p.keep:ClearAllPoints()
    p.keep:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", T, T)
    p.keep:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -T, T)
    p.keep:SetHeight(Pixel.Px(btn, Items.KEEP_PX))
    font(btn.Count, Items.COUNT_SIZE)
    if type(btn.Count) == "table" and btn.Count.ClearAllPoints then
        btn.Count:ClearAllPoints()
        btn.Count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -T - 1, T)
    end
    font(p.free, Items.FREE_SIZE)
end

-- One color table per quality, made once. Paint only repaints the border when the
-- color table changes, so a fresh table per fill would repaint every time.
local qualityColors = {}
local function qualityColor(quality)
    if type(quality) ~= "number" then return Items.COMMON end
    if quality <= 0 then return Items.POOR end
    if quality == 1 then return Items.COMMON end
    if qualityColors[quality] then return qualityColors[quality] end
    local getColor = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor
    if type(getColor) == "function" then
        local ok, r, g, b = pcall(getColor, quality)
        if ok and type(r) == "number" then
            qualityColors[quality] = { r, g, b }
            return qualityColors[quality]
        end
    end
    return Items.COMMON
end
Items.QualityColor = qualityColor

-- Paints the current contents: border color, icon hidden on an empty slot (the
-- game draws an empty-slot picture there), grayed on poor items.
function Items.Paint(btn, hasItem, quality, itemID, bag)
    local p = dressed[btn]
    if not p then return end
    hideGameArt(btn)
    local plain = not hasItem or type(quality) ~= "number" or quality <= 1
    local color = plain and Items.BagColor(bag) or not hasItem and Items.EMPTY
        or itemID == ns.Categories.HEARTHSTONE and Items.HEARTH or qualityColor(quality)
    if p.color ~= color then
        p.color = color
        p.flash = nil
        Items.Ring(p)
    end
    local thin = not hasItem
    if (p.shell.opts.thin or false) ~= thin then
        p.shell.opts.thin = thin
        Style.Shell(btn, p.shell.opts)
        Items.Ring(p)
    end
    local icon = btn.icon or btn.Icon
    local poor = hasItem and type(quality) == "number" and quality <= 0 and setting(btn, "greyPoor") == true
    if icon then
        icon:SetAlpha(not hasItem and 0 or poor and Items.POOR_ALPHA or 1)
        if poor then icon:SetDesaturated(true) end
    end
    p.shade:SetShown(hasItem and true or false)
    p.well:SetShown(not hasItem)
end

-- Loot shine. While filling, a slot whose item is new and uncommon or better is
-- marked on its button (btn.dluiShine = bag:slot:item). It shines once seen:
-- right away if filled while the window is open, otherwise from Items.ShineNew
-- after the window opens (Prep fills slots while closed). Each bag:slot:item
-- shines once per session.
local shone = {}

local seen = {}   -- bag:slot:item keys whose dot was cleared by a hover

function Items.NoteNew(btn, bag, slot, info)
    btn.dluiShine, btn.dluiNew = nil, nil
    local quality = info and info.quality
    local p = dressed[btn]
    if type(quality) == "number" and quality >= Items.SHINE_QUALITY and not ns.Saved.Is(bag) then
        local id = info.itemID or info.hyperlink
        if id ~= nil and C_NewItems and C_NewItems.IsNewItem then
            local ok, new = pcall(C_NewItems.IsNewItem, bag, slot)
            if ok and new == true then
                local key = bag .. ":" .. slot .. ":" .. tostring(id)
                if not shone[key] then btn.dluiShine = key end
                if not seen[key] then btn.dluiNew = key end
            end
        end
    end
    if p then Items.PaintDot(btn, p) end
end

-- The dot follows btn.dluiNew; the accent is read each time it's painted.
function Items.PaintDot(btn, p)
    local on = btn.dluiNew ~= nil
    if on then
        local r, g, b = Style.Accent()
        p.newDot:SetVertexColor(r, g, b, 1)
        p.newGlow:SetVertexColor(r, g, b, Items.DOT_GLOW_ALPHA)
    end
    if on == (p.dotOn == true) then return end
    p.dotOn = on
    if on then
        p.newDot:Show(); p.newGlow:Show()
        p.newDot:SetAlpha(1); p.newGlow:SetAlpha(1)
        if btn:IsVisible() and p.dotPainted then
            DUI.Motion.Fade(p.newDot, 0, 1, DUI.Motion.FAST)
            DUI.Motion.Fade(p.newGlow, 0, 1, DUI.Motion.FAST)
        end
    else
        Items.HideDot(btn, p)
    end
    p.dotPainted = true
end

-- Fades the dot out, then hides it unless it came back meanwhile.
function Items.HideDot(btn, p)
    if btn:IsVisible() then
        DUI.Motion.Fade(p.newDot, 1, 0, DUI.Motion.FAST)
        DUI.Motion.Fade(p.newGlow, 1, 0, DUI.Motion.FAST)
        C_Timer.After(DUI.Motion.FAST + 0.05, function()
            if not p.dotOn then p.newDot:Hide(); p.newGlow:Hide() end
        end)
    else
        p.newDot:Hide(); p.newGlow:Hide()
    end
end

-- The cheapest junk in the bag (Junk.MarkCheapest): a dot like the new-item one,
-- in the warn color on the bottom left corner, so a full bag shows what to throw
-- away. Made the first time a slot gets it; only one slot has it at a time.
function Items.PaintCheap(btn, on)
    local p = dressed[btn]
    if not p then return end
    if on and not p.cheapDot then
        p.cheapGlow = btn:CreateTexture(nil, "OVERLAY", nil, 4)
        p.cheapDot = btn:CreateTexture(nil, "OVERLAY", nil, 5)
        for _, t in ipairs({ p.cheapGlow, p.cheapDot }) do
            t:SetColorTexture(1, 1, 1, 1)
            local m = btn:CreateMaskTexture()
            m:SetTexture(DUI.Win.MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(t)
            t:AddMaskTexture(m)
            t:Hide()
        end
    end
    if not p.cheapDot then return end
    if on then
        local dot = Pixel.Px(btn, Items.DOT_PX)
        p.cheapDot:ClearAllPoints()
        p.cheapDot:SetSize(dot, dot)
        p.cheapDot:SetPoint("CENTER", btn, "BOTTOMLEFT", -2, -2)
        p.cheapGlow:ClearAllPoints()
        local glow = Items.GlowSize(btn, dot)
        p.cheapGlow:SetSize(glow, glow)
        p.cheapGlow:SetPoint("CENTER", p.cheapDot, "CENTER", 0, 0)
        local c = Style.INK.WARN
        p.cheapDot:SetVertexColor(c[1], c[2], c[3], 1)
        p.cheapGlow:SetVertexColor(c[1], c[2], c[3], Items.DOT_GLOW_ALPHA)
    end
    if on == (p.cheapOn == true) then return end
    p.cheapOn = on
    local visible = btn:IsVisible()
    if on then
        p.cheapDot:Show(); p.cheapGlow:Show()
        if visible then
            DUI.Motion.Fade(p.cheapDot, 0, 1, DUI.Motion.FAST)
            DUI.Motion.Fade(p.cheapGlow, 0, 1, DUI.Motion.FAST)
        else
            p.cheapDot:SetAlpha(1); p.cheapGlow:SetAlpha(1)
        end
    elseif visible then
        DUI.Motion.Fade(p.cheapDot, 1, 0, DUI.Motion.FAST)
        DUI.Motion.Fade(p.cheapGlow, 1, 0, DUI.Motion.FAST)
        C_Timer.After(DUI.Motion.FAST + 0.05, function()
            if not p.cheapOn then p.cheapDot:Hide(); p.cheapGlow:Hide() end
        end)
    else
        p.cheapDot:Hide(); p.cheapGlow:Hide()
    end
end

-- Hover: the item is seen, its dot fades out and stays gone for this bag:slot:item.
function Items.SeeNew(btn)
    local p = dressed[btn]
    seen[btn.dluiNew] = true
    btn.dluiNew = nil
    if not p then return end
    p.dotPainted = true
    p.dotOn = false
    Items.HideDot(btn, p)
end

-- Plays a marked slot's shine once. Nothing with motion off.
function Items.MaybeShine(btn)
    local key, p = btn.dluiShine, dressed[btn]
    if not key or not p or not DUI.Motion.On() then return end
    btn.dluiShine = nil
    shone[key] = true
    Items.Shine(btn)
end

-- Shines every marked slot of a window that just finished fading in.
function Items.ShineNew(f)
    C_Timer.After(DUI.Motion.NORMAL, function()
        if not f:IsShown() then return end
        for _, s in ipairs(f.set.Slots()) do
            if s.button.dluiShine then Items.MaybeShine(s.button) end
        end
    end)
end

-- The shine itself. The glint crosses the icon (not in combat, since the button
-- is the game's and the glint moves by anchor), and the border flashes toward
-- white, then settles back to whatever its color is by then (same as Light).
function Items.Shine(btn)
    local p = dressed[btn]
    if not p or not p.color then return end
    local Motion = DUI.Motion
    if not (InCombatLockdown and InCombatLockdown()) then
        local s = p.clip:GetHeight() or 0
        if s <= 0 then s = btn:GetHeight() or 0 end
        local w, h = s * Items.SHINE_WIDTH, s * 2
        local q = w / 4
        local cx, cy = q * math.cos(Items.SHINE_TILT), q * math.sin(Items.SHINE_TILT)
        p.left:SetSize(w / 2, h)
        p.left:ClearAllPoints()
        p.left:SetPoint("CENTER", p.glint, "CENTER", -cx, -cy)
        p.right:SetSize(w / 2, h)
        p.right:ClearAllPoints()
        p.right:SetPoint("CENTER", p.glint, "CENTER", cx, cy)
        p.glint:SetHeight(h)
        Motion.Sweep(p.glint, p.clip, { width = w, dur = Items.SHINE_DUR, alpha = Items.SHINE_ALPHA, inset = -w })
    end
    local c, L = p.color, Items.SHINE_LIFT
    local bright = { c[1] + (1 - c[1]) * L, c[2] + (1 - c[2]) * L, c[3] + (1 - c[3]) * L }
    p.flash = bright
    Motion.Tween(p, 0, 1, Motion.SLOW, function(t)
        local to = p.color
        if p.lit or p.flash ~= bright or not to then return end
        local col = t >= 1 and to or {
            bright[1] + (to[1] - bright[1]) * t,
            bright[2] + (to[2] - bright[2]) * t,
            bright[3] + (to[3] - bright[3]) * t }
        Items.Ring(p, col)
    end, function()
        if p.flash == bright then
            p.flash = nil
            Items.Ring(p)
        end
    end)
end

-- Items the player can't use (level, class, skill or "Already known" shown in
-- red in the tooltip) get the vendor red over the icon (Npc/Shop.lua BAD_ICON,
-- same red as the NPC window). Read once per item link by building a tooltip;
-- Items.ForgetUsable clears it after leveling or learning a skill or recipe.
-- Only gear, usable items and recipes are checked, nothing else has requirements.
Items.UNUSABLE = DUI.Npc.Shop.BAD_ICON
Items.RECIPE = Enum and Enum.ItemClass and Enum.ItemClass.Recipe or 9
local unusable = {}   -- link -> true / false

function Items.ForgetUsable() wipe(unusable) end

-- Red as the game writes it (RED_FONT_COLOR 1 / 0.125 / 0.125, read back rounded).
-- nil when the color is secret (client restrictions), so unknown.
local function red(c)
    if isSecret(c) then return nil end
    if type(c) ~= "table" then return false end
    local r, g, b = c.r, c.g, c.b
    if isSecret(r) or isSecret(g) or isSecret(b) then return nil end
    return type(r) == "number" and type(g) == "number" and type(b) == "number" and r > 0.9 and g < 0.2 and b < 0.2
end

-- The words before the first number of the game's durability line, read once.
local durability
local function durabilityPrefix()
    if durability == nil and type(DURABILITY_TEMPLATE) == "string" then
        durability = DURABILITY_TEMPLATE:match("^(.-)%%")
    end
    return durability
end

-- Red lines that aren't about usability: broken gear, salvage, combat notes.
local function notAboutUse(text)
    if type(text) ~= "string" then return false end
    if text == ITEM_SCRAPABLE_NOT or text == CANNOT_UNEQUIP_COMBAT or text == ITEM_DISENCHANT_NOT_DISENCHANTABLE then return true end
    local prefix = durabilityPrefix()
    return prefix ~= nil and prefix ~= "" and text:sub(1, #prefix) == prefix
end

-- One of the game's format strings as an anchored pattern that reads its line
-- back, each number captured. Other languages number the holes (%1$d) and
-- write plurals as |4one:many;, so those are folded before escaping.
function Items.Pattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local f = fmt:gsub("|4[^;]*;", "\1")
    f = f:gsub("%%%d*%$?([ds])", function(kind) return kind == "d" and "\2" or "\1" end)
    f = f:gsub("%%%%", "%%")
    f = f:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    f = f:gsub("\1", ".-"):gsub("\2", "(%%d+)")
    return "^" .. f .. "$"
end

-- The game's "Requires Cooking (110)" line as a pattern, built once from its
-- own words so it reads in every language.
local skillLine
local function skillPattern()
    if skillLine == nil then
        skillLine = Items.Pattern(ITEM_MIN_SKILL) or false
    end
    return skillLine or nil
end

-- A recipe the game calls usable can still need more profession skill: its
-- own red "Requires <profession> (<skill>)" line says so. Other red lines
-- belong to the item it makes (its level), so they don't count.
local function recipeSkillTooLow(bag, slot)
    local pattern = skillPattern()
    if not (pattern and C_TooltipInfo and C_TooltipInfo.GetBagItem) then return false end
    local ok, tip = pcall(C_TooltipInfo.GetBagItem, bag, slot)
    if not ok or type(tip) ~= "table" or isSecret(tip.lines) or type(tip.lines) ~= "table" then return nil end
    for _, line in ipairs(tip.lines) do
        if type(line) == "table" then
            local text = line.leftText
            if isSecret(text) then return nil end
            if type(text) == "string" and text:find(pattern) then
                local r = red(line.leftColor)
                if r == nil then return nil end
                if r then return true end
            end
        end
    end
    return false
end

local function readUnusable(bag, slot, link)
    -- Not loaded yet: the tooltip is a single red "Retrieving item information" line.
    -- Unknown for now; the slot's fill after loading asks again.
    if C_Item.GetItemInfo and C_Item.GetItemInfo(link) == nil then return nil end
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(link)
    if classID == Items.RECIPE then
        -- A recipe's tooltip includes the crafted item's lines (its level in red too),
        -- so ask the game whether the recipe can be learned instead.
        if not C_Item.IsUsableItem then return false end
        local ok, usable = pcall(C_Item.IsUsableItem, link)
        if not ok or isSecret(usable) then return nil end
        if not usable then return true end
        return recipeSkillTooLow(bag, slot)
    end
    local equip = C_Item.IsEquippableItem and C_Item.IsEquippableItem(link)
    local spell = C_Item.GetItemSpell and C_Item.GetItemSpell(link)
    if not equip and not spell then return false end
    if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return false end
    -- Use the slot's own tooltip so the link's bonus IDs give the real required level.
    local ok, tip = pcall(C_TooltipInfo.GetBagItem, bag, slot)
    if not ok or type(tip) ~= "table" or isSecret(tip.lines) or type(tip.lines) ~= "table" then
        return nil
    end
    for _, line in ipairs(tip.lines) do
        if type(line) == "table" then
            local left, right = red(line.leftColor), red(line.rightColor)
            if left == nil or right == nil then return nil end
            local text = line.leftText
            if isSecret(text) then return nil end
            if right or (left and not notAboutUse(text)) then return true end
        end
    end
    return false
end

-- True if the item in bag/slot can't be used (info = the slot's info). nil when
-- that can't be known yet (not loaded, or read back secret).
function Items.Unusable(bag, slot, info)
    local link = info and info.hyperlink
    -- A saved copy may belong to another character, so it's never judged.
    if type(link) ~= "string" or ns.Saved.Is(bag) then return false end
    local known = unusable[link]
    if known ~= nil then return known end
    local ok, bad = pcall(readUnusable, bag, slot, link)
    if not ok or bad == nil then return nil end     -- unknown for now, asked again on the next fill
    unusable[link] = bad
    return bad
end

-- Re-checks a slot's red tint as part of Items.Fill: the setting, the answer,
-- and the same item keeps its red while the answer is unknown (a skill rising in
-- a fight under client restrictions) instead of flickering off.
local function tintSlot(btn, bag, slot, info, texture)
    local link = info and info.hyperlink
    local bad = texture ~= nil and setting(btn, "redUnusable") == true and Items.Unusable(bag, slot, info)
    if bad == nil then bad = btn.dluiTintLink == link and btn.dluiUnusable or false end
    btn.dluiTintLink = link
    Items.Tint(btn, bad)
end

-- After leveling or learning a skill or recipe (Items.ForgetUsable): re-check the
-- tint only, no fill. all = every slot with an item; otherwise only slots that
-- can change in a fight (red ones, and recipes whose IsUsableItem is cheap),
-- since weapon skill rises often there and gear needs a tooltip read.
function Items.Retint(btn, all)
    if btn.dluiShown == nil then return end
    local holder = btn:GetParent()
    local bag, slot = holder and holder:GetID(), btn:GetID()
    local info = Items.InfoAt(bag, slot)
    if not all and not btn.dluiUnusable then
        local link = info and info.hyperlink
        local classID = type(link) == "string" and select(6, C_Item.GetItemInfoInstant(link))
        if classID ~= Items.RECIPE then return end
    end
    tintSlot(btn, bag, slot, info, info and (info.iconFileID or btn.dluiShown))
end

-- Icon in the vendor red, or normal.
function Items.Tint(btn, bad)
    btn.dluiUnusable = bad or nil
    local icon = btn.icon or btn.Icon
    if not icon then return end
    local c = bad and Items.UNUSABLE
    if c then icon:SetVertexColor(c[1], c[2], c[3]) else icon:SetVertexColor(1, 1, 1) end
end

local function bindTypeOf(item) return (select(14, C_Item.GetItemInfo(item))) end

-- Item overlays: bind type (while unbound), gear item level, equipment set mark,
-- junk coin. Returns true when bind type or level isn't known yet (not loaded),
-- so the slot gets filled again once it is.
function Items.Details(btn, info, bag, slot)
    local p = dressed[btn]
    if not p then return false end
    local pending = false
    local text
    if info and setting(btn, "showBind") and not info.isBound then
        local ok, bindType = pcall(bindTypeOf, info.hyperlink or info.itemID)
        if ok and type(bindType) == "number" then
            text = Items.BIND_TEXT[bindType]
        elseif info.hyperlink or info.itemID then
            pending = true
        end
    end
    p.bind:SetText(text or "")
    p.bind:SetShown(text ~= nil)
    local level
    if info and setting(btn, "showLevel") then
        local item = info.hyperlink or info.itemID
        level = DUI.ItemLevel(item)
        if not level and item and C_Item.GetItemInfo then
            local ok, name = pcall(C_Item.GetItemInfo, item)
            if ok and name == nil then pending = true end
        end
    end
    p.level:SetText(level and tostring(math.floor(level + 0.5)) or "")
    p.level:SetShown(level ~= nil)
    local inSet = false
    if info and setting(btn, "showSet") and C_Container.GetContainerItemEquipmentSetInfo then
        local ok, yes = pcall(C_Container.GetContainerItemEquipmentSetInfo, bag, slot)
        inSet = ok and yes == true
    end
    if inSet then
        local r, g, b = Style.Accent()
        p.set:SetVertexColor(r, g, b, 1)
    end
    p.set:SetShown(inSet)
    local locked = info ~= nil and ns.Categories ~= nil and ns.Categories.IsLocked(info.itemID)
    if locked then
        local r, g, b = Style.Accent()
        p.lock:SetVertexColor(r, g, b, 1)
    end
    if locked ~= p.lock:IsShown() then
        p.lock:SetShown(locked)
        -- Fade the lock in when it's newly set (not on a slot's first fill).
        if locked and p.lockSeen and btn:IsVisible() and DUI.Motion then DUI.Motion.Fade(p.lock, 0, 1, DUI.Motion.FAST) end
    end
    p.lockSeen = true
    local keptSlot = ns.Keep.Offered(btn, bag, slot) and ns.Keep.At(bag, slot) ~= nil
    if keptSlot then Style.PaintAccent(p.keep, 1, "HORIZONTAL") end
    if keptSlot ~= p.keep:IsShown() then
        p.keep:SetShown(keptSlot)
        if keptSlot and btn:IsVisible() and DUI.Motion then DUI.Motion.Fade(p.keep, 0, 1, DUI.Motion.FAST) end
    end
    if inSet and locked ~= (p.setBeside == true) then
        local T = Items.Inset(btn)
        p.set:ClearAllPoints()
        if locked then p.set:SetPoint("TOPRIGHT", p.lock, "TOPLEFT", -1, -1)
        else p.set:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -T - 1, -T - 1) end
        p.setBeside = locked or nil
    end
    if type(btn.JunkIcon) == "table" and btn.JunkIcon.SetAlpha then
        btn.JunkIcon:SetAlpha(setting(btn, "showJunk") and 1 or 0)
    end
    if type(btn.UpgradeIcon) == "table" and btn.UpgradeIcon.SetAlpha then btn.UpgradeIcon:SetAlpha(0) end
    return pending
end

-- A slot's picture. The slot can report an item with no icon (seen on a freshly
-- looted pattern, and on a rune right after one was used), and the item's own icon
-- can be missing too until its data loads. The item's basic info is always on hand,
-- and an icon seen once for an item is kept, so a slot never goes blank.
local knownIcons = {}
function Items.IconOf(info)
    if not info then return nil end
    local id = info.itemID
    local icon = info.iconFileID
    if type(icon) == "nil" and type(id) == "number" and C_Item then
        if C_Item.GetItemIconByID then
            local ok, i = pcall(C_Item.GetItemIconByID, id)
            if ok and type(i) ~= "nil" then icon = i end
        end
        if type(icon) == "nil" and C_Item.GetItemInfoInstant then
            local ok, _, _, _, _, i = pcall(C_Item.GetItemInfoInstant, id)
            if ok and type(i) ~= "nil" then icon = i end
        end
        if type(icon) == "nil" then icon = knownIcons[id] end
    end
    if type(icon) ~= "nil" and type(id) == "number" then knownIcons[id] = icon end
    return icon
end

-- Fills a slot from the game in the same order the game fills its own
-- (ContainerFrameMixin:UpdateItems). Each call is guarded, so methods this
-- client lacks are skipped.
function Items.Fill(btn, tooltipOwner)
    local holder = btn:GetParent()
    local bag, slot = holder and holder:GetID(), btn:GetID()
    local info = Items.InfoAt(bag, slot)
    local texture = info and info.iconFileID
    -- A slot can report an item with no icon yet (seen on a freshly looted pattern
    -- in Forever) and still have none after the single wait below. Fall back to the
    -- item's own icon, otherwise it stayed blank until the item moved.
    local shown = Items.IconOf(info)
    local count = info and info.stackCount
    local locked = info and info.isLocked
    local quality = info and info.quality
    local readable = info and info.isReadable
    local link = info and info.hyperlink
    local noValue = info and info.hasNoValue
    local bound = info and info.isBound
    local qok, quest = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
    if not qok or type(quest) ~= "table" then quest = nil end
    local q = quest or EMPTY

    run(ClearItemButtonOverlay, btn)
    ns.Guard.Apply(btn, info)
    btn.dluiTexture, btn.dluiShown = texture, shown
    -- The item this slot shows on screen, so an eased layout can glide it from here.
    btn.dluiKey = info and (info.itemID or info.hyperlink) or nil
    btn.dluiReadable = readable or nil
    -- Never the button's SetHasItem, SetReadable or UpdateCooldown (it calls
    -- SetHasItem): run from here they leave hasItem and readable tainted on the
    -- slot. With the controller UI on, the game's own bag reads both straight off
    -- the slot the D-pad is on, each time any bag item is clicked or a quest is
    -- accepted, and from that read on it refuses its own controller calls until a
    -- reload. What those fields did here is done by Items.Cooldown,
    -- Items.Cursor and the tooltip check below.
    call(btn, "SetItemButtonTexture", shown)
    -- The game's SetItemButtonTexture puts the whole picture back, so the icon's own
    -- frame showed inside the ring until the next layout. Crop it again every fill.
    local icon = btn.icon or btn.Icon
    if type(icon) == "table" and icon.SetTexCoord then Style.CropIcon(icon) end
    run(SetItemButtonQuality, btn, quality, link, false, bound)
    -- Combined stacks (categories view): the total goes on the stack that represents them.
    run(SetItemButtonCount, btn, btn.dluiCount or count)
    -- ...but the game's split box (Shift-click) reads .count, so it only splits this one stack.
    if btn.dluiCount then btn.count = count or 0 end
    run(SetItemButtonDesaturated, btn, locked)
    call(btn, "UpdateExtended")
    call(btn, "UpdateQuestItem", q.isQuestItem, q.questID, q.isActive)
    call(btn, "UpdateNewItem", quality)
    -- No shimmer and no glow frame: stop the sweep and pulse the game just started and
    -- hide its glows (white on common items, a second frame around the ring; the store
    -- item's blue square too). New loot is marked by the Recent group and the small
    -- new-item dot instead.
    if type(btn.flashAnim) == "table" and btn.flashAnim.Stop then btn.flashAnim:Stop() end
    if type(btn.newitemglowAnim) == "table" and btn.newitemglowAnim.Stop then btn.newitemglowAnim:Stop() end
    hideGlows(btn)
    -- An item marked as junk by hand gets the game's junk coin like a gray one.
    local marked = info and ns.Categories.IsMarkedJunk(info.itemID)
    call(btn, "UpdateJunkItem", marked and 0 or quality, noValue)
    call(btn, "UpdateItemContextMatching")
    Items.Cooldown(btn, bag, slot, shown ~= nil)
    -- The slot under the pointer changed: its tooltip follows, or goes with the item.
    if tooltipOwner == btn then
        if shown then call(btn, "UpdateTooltip") elseif GameTooltip then GameTooltip:Hide() end
    end
    -- The addon's search decides (the game's own name search is kept empty).
    local w = windowOf(btn)
    call(btn, "SetMatchesSearch", Items.Fits(bag, slot, info, w, quest))

    -- Keep the game's quality ring hidden (SetItemButtonQuality shows it).
    if type(btn.IconBorder) == "table" and btn.IconBorder.SetAlpha then btn.IconBorder:SetAlpha(0) end
    Items.Paint(btn, shown ~= nil, quality, info and info.itemID, bag)
    tintSlot(btn, bag, slot, info, shown)
    local pending = Items.Details(btn, info, bag, slot)
    ns.Plugins.Paint(btn, info, bag, slot)   -- other addons' marks (Plugins.lua)
    ns.ItemTree.Paint(btn, info, bag)        -- ItemTree's keep, sell or use-now dot
    Items.Report(btn, bag, slot, info)
    Items.NoteNew(btn, bag, slot, info)
    if w and w:IsShown() and not w.opening then Items.MaybeShine(btn) end

    -- An item the client hasn't loaded comes back half empty (no icon, link or bind
    -- type yet) and is filled again once it loads. One wait per slot and item
    -- (btn.dluiWaiting), so fills while it's pending don't ask again. If it's loaded
    -- and still half empty (keystone: and battlepet: cages never get a bind type),
    -- it isn't asked again for that item (btn.dluiWaited). Otherwise each answer's
    -- fill asked again and the game answered again, every frame.
    local waitFor = info and (not texture or not link or pending) and (info.itemID or link or texture) or nil
    -- Reads empty, but the game holds an item there whose data hasn't arrived (new
    -- quest reward, loot, mail). No bag update follows when it does, so the window
    -- handles that bag's update then (layout and fill).
    local loading = false
    if not info and not ns.Saved.Is(bag) then
        local hok, has = pcall(C_Container.HasContainerItem, bag, slot)
        if hok and has == true then
            local iok, id = pcall(C_Container.GetContainerItemID, bag, slot)
            loading, waitFor = true, (iok and id) or "loading"
        end
    end
    if btn.dluiWaited ~= waitFor then btn.dluiWaited = nil end
    if waitFor and btn.dluiWaiting ~= waitFor and btn.dluiWaited ~= waitFor and Item then
        -- A saved copy has no real bag slot, so load its item by link.
        local iok, item
        if ns.Saved.Is(bag) then
            if link and Item.CreateFromItemLink then iok, item = pcall(Item.CreateFromItemLink, Item, link) end
        elseif Item.CreateFromBagAndSlot then
            iok, item = pcall(Item.CreateFromBagAndSlot, Item, bag, slot)
        end
        if iok and item and not item:IsItemEmpty() then
            btn.dluiWaiting, btn.dluiWaited = waitFor, waitFor
            item:ContinueOnItemLoad(function()
                if btn.dluiWaiting == waitFor then btn.dluiWaiting = nil end
                if loading and w and ns.Window then ns.Window.Changed(w, { [bag] = true })
                elseif w and w.sorting and ns.Window then ns.Window.MarkDirty(w, bag)   -- filled when the cleanup ends
                else Items.Fill(btn) end
            end)
        end
    end
    -- In the list view the row beside the slot reads the same item.
    if btn.dluiRow then ns.Layout.PaintRow(btn) end
    -- A new item shown twice (Recent and its own group): the copy follows.
    if btn.dluiTwin and btn.dluiTwin:IsShown() then Items.Fill(btn.dluiTwin, tooltipOwner) end
    return shown ~= nil
end

-- Only updates whether the slot stands out under its window's search (new search,
-- nothing else about the slot changed).
function Items.Match(btn)
    local holder = btn:GetParent()
    local bag, slot = holder and holder:GetID(), btn:GetID()
    call(btn, "SetMatchesSearch", Items.Fits(bag, slot, Items.InfoAt(bag, slot), windowOf(btn)))
    if btn.dluiTwin and btn.dluiTwin:IsShown() then Items.Match(btn.dluiTwin) end
end

-- Whether a slot stands out: it matches the window's search and, in the grid view,
-- sits in the picked chip's groups (the categories view hides those slots instead).
function Items.Fits(bag, slot, info, w, quest)
    local fits = ns.Search.Matches(bag, slot, info, w and w.match, quest)
    if fits and info and w and w.chip and not ns.Layout.Grouped(w.Setting("view")) then
        fits = ns.Window.ItemInChip(w, ns.Categories.Facts(bag, slot, info))
    end
    -- Disenchant staying on: what it can't take dims, so the rest stands out.
    if fits and w and w == ns.window and ns.Disenchant and ns.Disenchant.on then
        fits = ns.Disenchant.Takes(bag, slot, info)
    end
    -- At the bank: what can't go into the bank shown dims, as the game's bags do.
    if fits and info and w and w == ns.window and ns.Bank and ns.Bank.Refuses(bag, slot) then
        fits = false
    end
    return fits
end

-- The slot now holds something other than its last fill: the bag update arrived
-- before the item did (mail, loot).
function Items.Outdated(btn, info)
    return (info and info.iconFileID) ~= btn.dluiTexture
end

-- Only the locked look (an item picked up or put down). If outdated (only the
-- unlock follows the item), fill the whole slot instead.
function Items.FillLocked(btn)
    local holder = btn:GetParent()
    local info = Items.InfoAt(holder:GetID(), btn:GetID())
    if Items.Outdated(btn, info) then return Items.Fill(btn) end
    run(SetItemButtonDesaturated, btn, info and info.isLocked)
    Items.Paint(btn, info ~= nil and (info.iconFileID or btn.dluiShown) ~= nil, info and info.quality, info and info.itemID, holder:GetID())
    if btn.dluiTwin and btn.dluiTwin:IsShown() then Items.FillLocked(btn.dluiTwin) end
end

-- The game's junk coin shows only while a vendor's window is open (its
-- UpdateJunkItem reads MerchantFrame), so it's asked again when one opens or
-- closes. A slot filled while the bag was shut kept no coin at the vendor.
function Items.FillJunk(btn)
    local holder = btn:GetParent()
    local bag = holder and holder:GetID()
    if type(bag) ~= "number" or ns.Saved.Is(bag) then return end
    local info = Items.InfoAt(bag, btn:GetID())
    if not info then return end
    local marked = ns.Categories.IsMarkedJunk(info.itemID)
    call(btn, "UpdateJunkItem", marked and 0 or info.quality, info.hasNoValue)
    if btn.dluiTwin and btn.dluiTwin:IsShown() then Items.FillJunk(btn.dluiTwin) end
end

-- The cooldown sweep, and the dimmed icon of an item that can't be used yet, drawn
-- the way the button's own UpdateCooldown does (see Items.Fill for why not by it).
function Items.Cooldown(btn, bag, slot, has)
    local cd = btn.Cooldown
    if type(cd) ~= "table" or ns.Saved.Is(bag) then return end
    if not has then cd:Hide() return end
    local read, set = C_Container.GetContainerItemCooldown, CooldownFrame_Set
    if type(read) ~= "function" or type(set) ~= "function" then return end
    local start, duration, enable = read(bag, slot)
    if type(start) ~= "number" or type(duration) ~= "number" or isSecret(start) or isSecret(duration) or isSecret(enable) then
        return
    end
    set(cd, start, duration, enable)
    local icon = btn.icon or btn.Icon
    if type(icon) == "table" and icon.SetVertexColor then
        local v = (duration > 0 and enable == 0) and 0.4 or 1
        icon:SetVertexColor(v, v, v)
    end
end

-- Only the cooldown. onlyFull skips empty slots (their last Fill cleared it).
function Items.FillCooldown(btn, onlyFull)
    local holder = btn:GetParent()
    local ok, has = pcall(C_Container.HasContainerItem, holder:GetID(), btn:GetID())
    if onlyFull and not (ok and has) then return end
    Items.Cooldown(btn, holder:GetID(), btn:GetID(), ok and has)
    -- The cooldown paints the icon white or dim on every call, which took the
    -- red off items that can't be used.
    if btn.dluiUnusable then Items.Tint(btn, true) end
    if btn.dluiTwin and btn.dluiTwin:IsShown() then Items.FillCooldown(btn.dluiTwin, onlyFull) end
end

-- Lit (a bag hovered in the strip): accent border, empty or not, so the whole bag
-- reads at a glance. Unlit restores its own color.
function Items.Light(btn, on)
    local p = dressed[btn]
    if not p then return end
    p.lit = on or nil
    Items.Ring(p)
end

-- Free count on a grouped section's tile (nil = none).
function Items.SetFree(btn, n)
    local p = dressed[btn]
    if not p then return end
    if n then
        p.free:SetText(n)
        p.free:Show()
    else
        p.free:Hide()
    end
end

-- What plugins get for a slot (DaylightUI.API Paint, kind "bagslot"): icon, count
-- and quality border, painted back by the slot's next fill.
if DUI.APIReport then
    DUI.APIReport.Parts("bagslot", function(btn)
        local p = dressed[btn]
        local shell = p and p.shell
        return { icon = btn.icon or btn.Icon, count = btn.Count, border = shell and shell.border }
    end)
    DUI.APIReport.Repainter("bagslot", function(btn) Items.Fill(btn) end)
end
