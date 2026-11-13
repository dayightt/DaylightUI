-- One bag slot. It's the game's own bag button, so using, dragging, splitting,
-- linking and selling all stay the game's. Restyled here and filled the same
-- way the game fills its own bags.
--
-- The button's bag is its holder's ID (Bags.lua) and its slot is its own ID.
-- Never call the button's SetBagID: it sets a secure attribute, and setting that
-- from addon code taints item use.

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel

local Items = {}
ns.Items = Items

Items.TEMPLATE = "ContainerFrameItemButtonTemplate"
-- Same look as aura icons: shell border around a square cropped icon with a soft
-- inner shadow. No background, so an empty slot is only its outline.
Items.BORDER_PX = 3
Items.SHELL = { borderPx = Items.BORDER_PX, noBevel = true, noBackground = true }

-- A shell keeps the opts table it's given and its border color is written into
-- it, so each slot needs its own copy or coloring one colors them all.
function Items.ShellOpts()
    local o = {}
    for k, v in pairs(Items.SHELL) do o[k] = v end
    return o
end
Items.CROP = DaylightUI.Style.ICON_CROP
Items.SHADE = DUI.MEDIA .. "inner-shadow.png"
Items.SHADE_ALPHA = 0.55
Items.COUNT_SIZE = Style.SIZE.tiny
Items.FREE_SIZE = Style.SIZE.small
-- Border colors for an empty slot, common, poor and the Hearthstone (light blue,
-- easy to spot). Everything else uses its quality color.
Items.EMPTY = { 0.28, 0.28, 0.3 }
Items.COMMON = { 0.55, 0.55, 0.58 }
Items.POOR = { 0.36, 0.36, 0.38 }
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
Items.BAND_DIM = 0.45        -- heavy border band, as a dimmed border color
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

-- The window a slot belongs to (via its holder), and that window's settings.
local function windowOf(btn)
    local h = btn:GetParent()
    return h and h.dluiWindow
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

-- Restyles a new button (once).
function Items.Dress(btn)
    if dressed[btn] then return dressed[btn] end
    local p = {}
    dressed[btn] = p
    p.shell = Style.Shell(btn, Items.ShellOpts())
    hideGameArt(btn)
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
    -- click on a bag item).
    btn:HookScript("OnClick", function(self, button)
        if button == "RightButton" and IsAltKeyDown and IsAltKeyDown() and ns.Categories then
            ns.Categories.Menu(self)
        end
    end)
    -- A locked item's slot takes no clicks at a vendor or while Disenchant is targeting.
    -- Looking at a new item clears its dot.
    btn:HookScript("OnEnter", function(self)
        if self.dluiNew then Items.SeeNew(self) end
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

-- Scales the game's art to this slot's size, keeping the shape and position it
-- was drawn for. Only when the size changed, since every layout places every slot.
function Items.ScaleArt(btn, p)
    local size = btn:GetWidth()
    if type(size) ~= "number" or size <= 0 or p.artSize == size then return end
    p.artSize = size
    local k = size / Items.GAME_SLOT
    for _, a in ipairs(p.art) do a[1]:SetSize(a[2] * k, a[3] * k) end
end

-- Icon inside the border, and everything positioned off it; text in the addon font.
function Items.Place(btn)
    local p = dressed[btn]
    if not p then return end
    Items.ScaleArt(btn, p)
    local T = Pixel.Px(btn, Items.BORDER_PX)
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
    local glow = dot * Items.DOT_GLOW
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
        btn.Count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 3)
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
        local k = Items.BAND_DIM
        Style.SetShellColors(p.shell, color, { color[1] * k, color[2] * k, color[3] * k })
    end
    local icon = btn.icon or btn.Icon
    local poor = hasItem and type(quality) == "number" and quality <= 0 and setting(btn, "greyPoor") == true
    if icon then
        icon:SetAlpha(not hasItem and 0 or poor and Items.POOR_ALPHA or 1)
        if poor then icon:SetDesaturated(true) end
    end
    p.shade:SetShown(hasItem and true or false)
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
    local c, L, k = p.color, Items.SHINE_LIFT, Items.BAND_DIM
    local bright = { c[1] + (1 - c[1]) * L, c[2] + (1 - c[2]) * L, c[3] + (1 - c[3]) * L }
    p.flash = bright
    Motion.Tween(p, 0, 1, Motion.SLOW, function(t)
        local to = p.color
        if p.lit or p.flash ~= bright or not to then return end
        local col = t >= 1 and to or {
            bright[1] + (to[1] - bright[1]) * t,
            bright[2] + (to[2] - bright[2]) * t,
            bright[3] + (to[3] - bright[3]) * t }
        Style.SetShellColors(p.shell, col, { col[1] * k, col[2] * k, col[3] * k })
    end, function() if p.flash == bright then p.flash = nil end end)
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
    if issecretvalue and issecretvalue(c) then return nil end
    if type(c) ~= "table" then return false end
    local r, g, b = c.r, c.g, c.b
    if issecretvalue and (issecretvalue(r) or issecretvalue(g) or issecretvalue(b)) then return nil end
    return type(r) == "number" and type(g) == "number" and type(b) == "number" and r > 0.9 and g < 0.2 and b < 0.2
end

-- Red lines that aren't about usability: broken gear, salvage, combat notes.
local function notAboutUse(text)
    if type(text) ~= "string" then return false end
    if text == ITEM_SCRAPABLE_NOT or text == CANNOT_UNEQUIP_COMBAT or text == ITEM_DISENCHANT_NOT_DISENCHANTABLE then return true end
    local durability = type(DURABILITY_TEMPLATE) == "string" and DURABILITY_TEMPLATE:match("^(.-)%%") or nil
    return durability ~= nil and durability ~= "" and text:sub(1, #durability) == durability
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
        if not ok or issecretvalue and issecretvalue(usable) then return nil end
        return not usable
    end
    local equip = C_Item.IsEquippableItem and C_Item.IsEquippableItem(link)
    local spell = C_Item.GetItemSpell and C_Item.GetItemSpell(link)
    if not equip and not spell then return false end
    if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return false end
    -- Use the slot's own tooltip so the link's bonus IDs give the real required level.
    local ok, tip = pcall(C_TooltipInfo.GetBagItem, bag, slot)
    if not ok or type(tip) ~= "table" or (issecretvalue and issecretvalue(tip.lines)) or type(tip.lines) ~= "table" then
        return nil
    end
    for _, line in ipairs(tip.lines) do
        if type(line) == "table" then
            local left, right = red(line.leftColor), red(line.rightColor)
            if left == nil or right == nil then return nil end
            local text = line.leftText
            if issecretvalue and issecretvalue(text) then return nil end
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
        local T = Pixel.Px(btn, Items.BORDER_PX)
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
    local shown = texture
    if shown == nil and info and type(info.itemID) == "number" and C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, info.itemID)
        if ok and type(icon) ~= "nil" then shown = icon end
    end
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
    call(btn, "SetHasItem", shown)
    call(btn, "SetItemButtonTexture", shown)
    run(SetItemButtonQuality, btn, quality, link, false, bound)
    -- Combined stacks (categories view): the total goes on the stack that represents them.
    run(SetItemButtonCount, btn, btn.dluiCount or count)
    -- ...but the game's split box (Shift-click) reads .count, so it only splits this one stack.
    if btn.dluiCount then btn.count = count or 0 end
    run(SetItemButtonDesaturated, btn, locked)
    call(btn, "UpdateExtended")
    call(btn, "UpdateQuestItem", q.isQuestItem, q.questID, q.isActive)
    call(btn, "UpdateNewItem", quality)
    -- No shimmer: stop the sweep and pulse the game just started. The glow stays as
    -- a still, quality-colored one (Stop resets its alpha to 0).
    if type(btn.flashAnim) == "table" and btn.flashAnim.Stop then btn.flashAnim:Stop() end
    if type(btn.newitemglowAnim) == "table" and btn.newitemglowAnim.Stop then btn.newitemglowAnim:Stop() end
    if type(btn.flash) == "table" and btn.flash.Hide then btn.flash:Hide() end
    if type(btn.NewItemTexture) == "table" and btn.NewItemTexture.SetAlpha then btn.NewItemTexture:SetAlpha(1) end
    call(btn, "UpdateJunkItem", quality, noValue)
    call(btn, "UpdateItemContextMatching")
    call(btn, "UpdateCooldown", shown)
    call(btn, "SetReadable", readable)
    call(btn, "CheckUpdateTooltip", tooltipOwner)
    -- The addon's search decides (the game's own name search is kept empty).
    local w = windowOf(btn)
    call(btn, "SetMatchesSearch", Items.Fits(bag, slot, info, w, quest))

    -- Keep the game's quality ring hidden (SetItemButtonQuality shows it).
    if type(btn.IconBorder) == "table" and btn.IconBorder.SetAlpha then btn.IconBorder:SetAlpha(0) end
    Items.Paint(btn, shown ~= nil, quality, info and info.itemID, bag)
    tintSlot(btn, bag, slot, info, shown)
    local pending = Items.Details(btn, info, bag, slot)
    ns.Plugins.Paint(btn, info, bag, slot)   -- other addons' marks (Plugins.lua)
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
                else Items.Fill(btn) end
            end)
        end
    end
    return shown ~= nil
end

-- Only updates whether the slot stands out under its window's search (new search,
-- nothing else about the slot changed).
function Items.Match(btn)
    local holder = btn:GetParent()
    local bag, slot = holder and holder:GetID(), btn:GetID()
    call(btn, "SetMatchesSearch", Items.Fits(bag, slot, Items.InfoAt(bag, slot), windowOf(btn)))
end

-- Whether a slot stands out: it matches the window's search and, in the grid view,
-- sits in the picked chip's groups (the categories view hides those slots instead).
function Items.Fits(bag, slot, info, w, quest)
    local fits = ns.Search.Matches(bag, slot, info, w and w.match, quest)
    if fits and info and w and w.chip and w.Setting("view") ~= "categories" then
        fits = ns.Window.InChip(w, ns.Categories.Assign(ns.Categories.Facts(bag, slot, info)))
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
end

-- Only the cooldown. onlyFull skips empty slots (their last Fill cleared it).
function Items.FillCooldown(btn, onlyFull)
    local holder = btn:GetParent()
    local ok, has = pcall(C_Container.HasContainerItem, holder:GetID(), btn:GetID())
    if onlyFull and not (ok and has) then return end
    call(btn, "UpdateCooldown", ok and has)
end

-- Lit (a bag hovered in the strip): accent border, empty or not, so the whole bag
-- reads at a glance. Unlit restores its own color.
function Items.Light(btn, on)
    local p = dressed[btn]
    if not p then return end
    p.lit = on or nil
    if on then
        Style.LightShell(p.shell, Items.BAND_DIM)
        return
    end
    local color = p.color
    if not color then return end
    local k = Items.BAND_DIM
    Style.SetShellColors(p.shell, color, { color[1] * k, color[2] * k, color[3] * k })
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
