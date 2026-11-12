-- Skins the game's Cooldown Manager to match the action buttons: each icon square
-- inside the shell's border, cropped and softly shaded, with the same dark sweep and
-- our font on its numbers. The viewers and their icons stay the game's. Layout,
-- sizes, spells and Edit Mode settings are untouched, and their own art is only
-- hidden by alpha.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style, Pixel = DUI.Style, DUI.Pixel
local Skin = ns.Skin

local CD = {}
ns.Cooldowns = CD

CD.VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
CD.ADDON = "Blizzard_CooldownViewer"
CD.TEXT = 12                 -- bar names and times
-- Buff bars are thin, so half the general border (at least a pixel) matches the
-- rest. The full one looked heavy.
function CD.BarBorder(general) return math.max(1, math.floor((general or 2) / 2)) end
-- Under 4px the heavy border's outline, band and line are a pixel each and turn to
-- mud, so a bar's border stays plain until it has room.
CD.BAR_HEAVY_MIN = 4
CD.PALETTE = {               -- a buff bar's color per spell (color "spell"), by spell ID % 8
    { 0.36, 0.62, 0.86 }, { 0.86, 0.46, 0.36 }, { 0.46, 0.76, 0.46 }, { 0.80, 0.66, 0.30 },
    { 0.68, 0.48, 0.82 }, { 0.36, 0.76, 0.74 }, { 0.84, 0.50, 0.68 }, { 0.62, 0.70, 0.36 },
}
CD.SCAN = 0.5                -- seconds between checks for icons and moves nothing else caught

local skinned = setmetatable({}, { __mode = "k" })   -- item -> its pieces
local hooked = setmetatable({}, { __mode = "k" })
local mine = setmetatable({}, { __mode = "k" })      -- our own textures, never hidden

local function kind(x)
    if type(x) ~= "table" or type(x.GetObjectType) ~= "function" then return nil end
    return x:GetObjectType()
end

local function styleText(fs, size)
    Style.DressText(fs, size, { slot = ns.MEDIA.font })
end

-- The icon texture and the frame it sits on (a buff bar's icon is a small frame
-- holding the texture).
function CD.IconOf(item)
    local icon = item.Icon
    if kind(icon) == "Texture" then return icon, item end
    if type(icon) == "table" and kind(icon.Icon) == "Texture" then return icon.Icon, icon end
end

-- The game's art on the icon: every texture on its frame except the icon, its
-- out-of-range tint, its debuff border and ours. Found once and cached, since every
-- OnShow of a reused icon hides it again. Only searched again when a frame gained
-- regions (regions are never removed).
local function regionCount(p)
    local host, owner = p.host, p.icon:GetParent()
    if type(host.GetNumRegions) ~= "function" then return nil end
    local n = host:GetNumRegions()
    if owner and owner ~= host then n = n + owner:GetNumRegions() end
    if p.bar then n = n + p.bar:GetNumRegions() end
    return n
end

local function hideArt(item, p)
    local count = regionCount(p)
    local fill = p.bar and p.bar.GetStatusBarTexture and p.bar:GetStatusBarTexture()
    if p.art and count and p.artCount == count and p.artFill == fill then
        for _, r in ipairs(p.art) do r:SetAlpha(0) end
        return
    end
    local art = {}
    p.art, p.artCount, p.artFill = art, count, fill
    local frames = { p.host }
    local owner = p.icon:GetParent()
    if owner and owner ~= p.host then frames[2] = owner end
    for _, f in ipairs(frames) do
        for _, r in ipairs({ f:GetRegions() }) do
            if r ~= p.icon and r ~= item.OutOfRange and r ~= item.DebuffBorder and not mine[r] and kind(r) == "Texture" then
                r:SetAlpha(0)
                art[#art + 1] = r
            end
        end
    end
    -- The bar view (BuffBarCooldownViewer): its own backdrop and border art,
    -- everything except the fill, which Style.TrackBar recolors.
    if p.bar then
        for _, r in ipairs({ p.bar:GetRegions() }) do
            if r ~= fill and not mine[r] and kind(r) == "Texture" then
                r:SetAlpha(0)
                art[#art + 1] = r
            end
        end
    end
end

-- Places the icon inside the border, as on an action button. The game moving the
-- icon back re-runs this (`placing` guards against a loop).
local placing = false
function CD.Place(item)
    local p = skinned[item]
    if not p or placing then return end
    placing = true
    local host, icon = p.host, p.icon
    local T = Pixel.Px(host, Skin.BORDER_PX)
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", host, "TOPLEFT", T, -T)
    icon:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -T, T)
    icon:SetTexCoord(Skin.CROP[1], Skin.CROP[2], Skin.CROP[3], Skin.CROP[4])
    Skin.PaintCdmShell(p.shell)
    -- Icons take the look's shape; a bar's icon stays square.
    if kind(item.Bar) ~= "StatusBar" then
        Skin.ShapeCdm(p, host, p.shell, icon, { p.shade }, kind(item.Cooldown) == "Cooldown" and { item.Cooldown } or {})
    end
    if kind(item.Cooldown) == "Cooldown" then
        Skin.StyleSwipe(item.Cooldown)
        Skin.PlaceCountdown(item.Cooldown)
    end
    p.shade:ClearAllPoints()
    p.shade:SetAllPoints(icon)
    local cd = item.Cooldown
    if kind(cd) == "Cooldown" then
        cd:ClearAllPoints()
        cd:SetAllPoints(icon)
    end
    local range = item.OutOfRange
    if kind(range) == "Texture" then
        range:ClearAllPoints()
        range:SetAllPoints(icon)
    end
    placing = false
end

-- A bar's name or time in its color. The game's own color is kept to restore once
-- the bar leaves our blocks, since the game recycles its pooled bars.
local inked = setmetatable({}, { __mode = "k" })    -- fs -> the game's { r, g, b }
local function inkKept(fs, c)
    if type(fs) ~= "table" or not fs.GetTextColor then return end
    if not inked[fs] then
        local r, g, b = fs:GetTextColor()
        if type(r) ~= "number" or (issecretvalue and issecretvalue(r)) then r, g, b = 1, 1, 1 end
        inked[fs] = { r, g, b }
    end
    CD.Ink(fs, c)
end
local function inkBack(fs)
    if type(fs) == "table" and inked[fs] then
        CD.Ink(fs, inked[fs])
        inked[fs] = nil
    end
end

-- Fonts and the bar's fill; redone on a style change.
function CD.StyleText(item)
    local own = CD.TextOf(item)
    local charges = item.ChargeCount
    local cc = own and own.countColor or Skin.COUNT_COLOR
    if type(charges) == "table" then
        styleText(charges.Current, own and own.countSize or Skin.COUNT)
        if kind(charges.Current) == "FontString" then charges.Current:SetTextColor(cc[1], cc[2], cc[3]) end
    end
    local stacks = item.Applications
    if type(stacks) == "table" then
        styleText(stacks.Applications, own and own.countSize or Skin.COUNT)
        if kind(stacks.Applications) == "FontString" then stacks.Applications:SetTextColor(cc[1], cc[2], cc[3]) end
    end
    local bar = item.Bar
    if kind(bar) == "StatusBar" then
        Style.TrackBar(bar, nil, ns.MEDIA.bars.cdm)
        -- Only a bar in one of the player's bar blocks gets its block's look.
        -- The others keep the game's, with just our font and border.
        local p = skinned[item]
        local block = p and ns.CdmRows and ns.CdmRows.BlockOf(item)
        if not (block and block.kind == "bar") then
            styleText(bar.Name, CD.TEXT)
            styleText(bar.Duration, CD.TEXT)
            inkBack(bar.Name); inkBack(bar.Duration)
            CD.PlaceName(bar.Name, bar, true, false)
            if p and type(p.host) == "table" and p.host.SetAlpha then p.host:SetAlpha(1) end
            return
        end
        local Look = ns.CdmData.Look
        local t = CD.BarText(block)
        styleText(bar.Name, t.nameSize)
        inkKept(bar.Name, t.nameColor)
        -- Its time shows through our clock or the game's own text (BB.SyncClocks,
        -- which follows the block's Show time).
        styleText(bar.Duration, t.timeSize)
        inkKept(bar.Duration, t.timeColor)
        if p.host and p.host.SetAlpha then p.host:SetAlpha(Look(block, "icon") ~= false and 1 or 0) end
        CD.Colour(item, bar, p, Look(block, "color"), block)
    end
end

-- Icon text (the card's Look > Text) ------------------------------------
-- A piece's cooldown numbers (on or off, size), its stack / charge count (size,
-- position) and the low-time color. Values the player never set follow the action
-- bars' look (Skin).

CD.COUNT_SPOTS = { br = { "BOTTOMRIGHT", -1, 1 }, tr = { "TOPRIGHT", -1, -1 }, tl = { "TOPLEFT", 1, -1 },
    center = { "CENTER", 0, 0 }, bottom = { "BOTTOM", 0, 1 } }
CD.LOW_AT = 3                -- default seconds left when the low-time color starts

local textOf = setmetatable({}, { __mode = "k" })   -- item -> its resolved text look
local movedCount = setmetatable({}, { __mode = "k" }) -- count text -> true once moved off the game's spot
function CD.TextOf(item) return textOf[item] end

-- The block's text keys with the fallbacks filled in.
function CD.TextLook(block)
    local t = type(block) == "table" and block.iconText or {}
    local low = t.low == true
    return { numbers = t.cdNumbers == nil and Skin.cooldownNumbers or t.cdNumbers == true,
        cdSize = t.cdSize or Skin.COOLDOWN_SIZE, countSize = t.countSize or Skin.COUNT,
        countSpot = CD.COUNT_SPOTS[t.countSpot] and t.countSpot or "br",
        low = low, lowAt = t.lowAt or CD.LOW_AT, lowColor = t.lowColor or Style.INK.BAD,
        cdColor = t.cdColor or Skin.LookFor("cdm").cooldownTextColor, countColor = t.countColor or Skin.COUNT_COLOR }
end

-- A bar's text (the card's Look > Bar): its name's and time's own size and color,
-- else the block's text size in white.
function CD.BarText(block)
    local t = type(block) == "table" and block.barText or {}
    local size = type(block) == "table" and ns.CdmData.Look(block, "text") or CD.TEXT
    local w = Style.INK.VALUE
    return { nameSize = t.nameSize or size, timeSize = t.timeSize or size,
        nameColor = t.nameColor or w, timeColor = t.timeColor or w }
end

-- Colors a text (pcall'd: some belong to the client and lock under restrictions).
function CD.Ink(fs, c)
    if type(fs) == "table" and fs.SetTextColor and type(c) == "table" then pcall(fs.SetTextColor, fs, c[1], c[2], c[3]) end
end

-- Puts a count text at its spot on the icon.
function CD.PlaceCount(fs, icon, spot)
    if type(fs) ~= "table" or not fs.SetPoint or type(icon) ~= "table" then return end
    local s = CD.COUNT_SPOTS[spot] or CD.COUNT_SPOTS.br
    fs:ClearAllPoints()
    fs:SetPoint(s[1], icon, s[1], s[2], s[3])
end

-- The cooldown's numbers: shown or not, in our font at the given size.
function CD.StyleNumbers(cd, t)
    if kind(cd) ~= "Cooldown" then return end
    if cd.SetHideCountdownNumbers then pcall(cd.SetHideCountdownNumbers, cd, not t.numbers) end
    local fs = cd.GetCountdownFontString and cd:GetCountdownFontString()
    if type(fs) == "table" and fs.SetFont then
        pcall(fs.SetFont, fs, Style.FONT, t.cdSize, Style.Outline())
        CD.Ink(fs, t.cdColor or Skin.LookFor("cdm").cooldownTextColor)
    end
    return fs
end

-- Low-time color: a client color curve evaluated on the spell's cooldown duration.
-- Secret-safe, since the client does the math and SetTextColor takes the result.
-- Runs every LOW_TICK while any piece has it on.
CD.LOW_TICK = 0.1
local lows = setmetatable({}, { __mode = "k" })     -- item -> { fs, curve }
local curves = {}                                   -- "r,g,b,at" -> curve
local lowTicker
local function lowCurve(t)
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local c, w = t.lowColor, t.cdColor or Skin.LookFor("cdm").cooldownTextColor
    local key = table.concat({ c[1], c[2], c[3], t.lowAt, w[1], w[2], w[3] }, ",")
    if curves[key] == nil then
        curves[key] = false
        local ok, cv = pcall(C_CurveUtil.CreateColorCurve)
        if ok and cv then
            if Enum.LuaCurveType and cv.SetType then pcall(cv.SetType, cv, Enum.LuaCurveType.Step) end
            cv:AddPoint(0, CreateColor(c[1], c[2], c[3], 1))
            cv:AddPoint(t.lowAt, CreateColor(w[1], w[2], w[3], 1))
            curves[key] = cv
        end
    end
    return curves[key] or nil
end

local function paintLow(item, l)
    local w = l.color
    -- The game's icon counting its buff down (not the cooldown) keeps the plain color.
    local aura = item.wasSetFromAura
    if issecretvalue and issecretvalue(aura) then aura = nil end
    local sid = ns.CdmEffects and ns.CdmEffects.SpellOf(item)
    local dur
    local C = ns.CdmCustom
    if C and C.ItemOf(item.cooldownID) then   -- an item added by ID
        if aura ~= true then dur = select(2, C.ItemCooldown(item.cooldownID)) end
    elseif sid and aura ~= true then
        local ok, d = pcall(C_Spell.GetSpellCooldownDuration, sid)
        if ok then dur = d end
    end
    if type(dur) == "nil" then l.fs:SetTextColor(w[1], w[2], w[3], 1); return end
    local ok, col = pcall(dur.EvaluateRemainingDuration, dur, l.curve)
    if ok and type(col) == "table" and col.GetRGBA then
        l.fs:SetTextColor(col:GetRGBA())
    end
end

local function lowTick()
    local any = false
    for item, l in pairs(lows) do
        any = true
        if item:IsVisible() then paintLow(item, l) end
    end
    if not any and lowTicker then lowTicker:Cancel(); lowTicker = nil end
end

local function watchLow(item, fs, t)
    local curve = t.low and type(fs) == "table" and lowCurve(t) or nil
    local w = t.cdColor or Skin.LookFor("cdm").cooldownTextColor
    if not curve then
        if lows[item] then
            lows[item].fs:SetTextColor(w[1], w[2], w[3], 1)
            lows[item] = nil
        end
        return
    end
    -- Reused and refilled, since every layout pass comes through here.
    local l = lows[item]
    if l then
        l.fs, l.curve, l.color = fs, curve, w
    else
        l = { fs = fs, curve = curve, color = w }
        lows[item] = l
    end
    paintLow(item, l)
    if not lowTicker then lowTicker = C_Timer.NewTicker(CD.LOW_TICK, lowTick) end
end

-- One icon's text (the game's item or our own icon), from its block.
function CD.StyleIconText(item, block)
    local t = CD.TextLook(block)
    textOf[item] = t
    local fs = CD.StyleNumbers(item.Cooldown, t)
    local icon = CD.IconOf(item) or item.Icon
    local charges, stacks = item.ChargeCount, item.Applications
    for _, c in ipairs({ type(charges) == "table" and charges.Current, type(stacks) == "table" and stacks.Applications }) do
        if c then
            styleText(c, t.countSize)
            CD.Ink(c, t.countColor)
            -- Left where the game put it until a spot is picked.
            if t.countSpot ~= "br" or movedCount[c] then
                movedCount[c] = true
                CD.PlaceCount(c, icon, t.countSpot)
            end
        end
    end
    watchLow(item, fs, t)
end

-- The keybind that casts a piece, shown on its icon (the page's "Show keybinds", a
-- piece's own `keyShown`). It's a frame on the item, so it follows the item's alpha
-- (fades, hide on cooldown) whatever draws the piece.
CD.KEY_LEVEL = 12            -- above the item's cooldown and its text
local keyLabels = setmetatable({}, { __mode = "k" })   -- item -> its label frame
local keyed = setmetatable({}, { __mode = "k" })       -- item -> { block, name } currently shown

function CD.KeyLabel(item) return keyLabels[item] end

-- Hide (Buff up) on one of our aura holders: its keybind hides with the buff and
-- comes back with the grayed icon when it drops (CdmAuras.SetHideUp).
function CD.FollowHide(item)
    local l = keyLabels[item]
    if not l then return end
    local a = (item.hideUp and item.up == true) and 0 or 1
    if l.hideAlpha == a then return end
    local from = l.hideAlpha or a
    l.hideAlpha = a
    DUI.Motion.Tween(l.text, from, a, DUI.Motion.FAST, function(v) l.text:SetAlpha(v) end)
end

function CD.ClearKey(item)
    keyed[item] = nil
    if keyLabels[item] then keyLabels[item]:Hide() end
end

-- The keybind text for a piece's icon, or nil; also uses its text keys.
function CD.KeyText(block, name)
    local t = block.iconText or {}
    local on = t.keyShown
    if on == nil then on = ns.Settings().cdmKeybinds == true end
    if on ~= true then return nil, t end
    local text = ns.Keys.CastKey(name)
    -- Controller glyphs (Keys.PadGlyph, |A:...|a) are already short, and a swap
    -- inside one would break its name.
    if text and Skin.LookFor("cdm").shortKeys == true and not text:find("|A:", 1, true) then text = Skin.Shorten(text) end
    return text, t
end

-- Applies the keybind look to a text on any frame (the real icons, the editor's).
function CD.StyleKey(fs, on, t)
    local look = Skin.LookFor("cdm")
    styleText(fs, t.keySize or look.keybindSize)
    CD.Ink(fs, look.keybindColor)
    CD.PlaceCount(fs, on, CD.COUNT_SPOTS[t.keySpot] and t.keySpot or "tr")
end

function CD.PaintKey(item, block, name)
    local text, t = CD.KeyText(block, name)
    if not text then return CD.ClearKey(item) end
    local l = keyLabels[item]
    if not l then
        l = CreateFrame("Frame", nil, item)
        l:SetAllPoints(item)
        l.text = l:CreateFontString(nil, "OVERLAY")
        l:Hide()
        keyLabels[item] = l
    end
    l:SetFrameLevel(item:GetFrameLevel() + CD.KEY_LEVEL)
    CD.StyleKey(l.text, l, t)
    l.text:SetText(text)
    keyed[item] = { block, name }
    CD.FollowHide(item)
    if not l:IsShown() then
        l:Show()
        DUI.Motion.Fade(l, 0, 1, DUI.Motion.FAST)
    end
end

-- Bindings or bars changed: repaint only the labels, no layout pass.
function CD.RepaintKeys()
    local now = {}
    for item, k in pairs(keyed) do now[item] = k end
    for item, k in pairs(now) do CD.PaintKey(item, k[1], k[2]) end
end

-- Each piece drawn this pass (id -> item). Labels on anything else are removed.
function CD.PaintKeys(items, blocks)
    local gone = {}
    for item in pairs(keyed) do gone[item] = true end
    for id, item in pairs(items) do
        gone[item] = nil
        if blocks[id].kind == "icon" then
            CD.PaintKey(item, blocks[id], ns.CdmOwn.Look(id))
        else
            CD.ClearKey(item)
        end
    end
    for item in pairs(gone) do CD.ClearKey(item) end
end

-- The item is released: back to the action bars' look.
function CD.ClearIconText(item)
    if not textOf[item] then return end
    textOf[item] = nil
    watchLow(item, nil, { low = false })
    if kind(item.Cooldown) == "Cooldown" then Skin.StyleCooldown(item.Cooldown) end
    CD.StyleText(item)
    local icon = CD.IconOf(item) or item.Icon
    for _, k in ipairs({ "ChargeCount", "Applications" }) do
        local c = type(item[k]) == "table" and (item[k].Current or item[k].Applications)
        if c and movedCount[c] then CD.PlaceCount(c, icon, "br") end
    end
end

-- The fill in its color and the empty part (our own backdrop, p.back) dark. Never
-- the fill's own color dimmed, which read as one color (a priest's white bar on a
-- gray-white track).
local function paint(p)
    return function(bar, r, g, b)
        bar:SetStatusBarColor(r, g, b, 1)
        local back = p.back
        if back then
            local c = Style.BACKGROUND
            back:SetVertexColor(c[1], c[2], c[3], Style.BAR_BACK_ALPHA)
        end
    end
end

-- A bar's name: shown or not, on the left (where the game put it) or centered. The
-- game's own anchors are kept so they can be restored.
local namePoints = setmetatable({}, { __mode = "k" })
function CD.PlaceName(fs, bar, show, center)
    if type(fs) ~= "table" or not fs.SetAlpha then return end
    fs:SetAlpha(show and 1 or 0)
    local saved = namePoints[fs]
    if center and not saved then
        saved = { justify = fs.GetJustifyH and fs:GetJustifyH() or "LEFT" }
        for i = 1, (fs.GetNumPoints and fs:GetNumPoints() or 0) do saved[i] = { fs:GetPoint(i) } end
        namePoints[fs] = saved
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", bar, "CENTER", 0, 0)
        if fs.SetJustifyH then fs:SetJustifyH("CENTER") end
    elseif not center and saved then
        namePoints[fs] = nil
        fs:ClearAllPoints()
        for _, pt in ipairs(saved) do fs:SetPoint(unpack(pt)) end
        if fs.SetJustifyH then fs:SetJustifyH(saved.justify) end
    end
end

-- A spell's own background color is the bar's whole background. The shell's dark
-- fill behind it is turned off so its opacity is exactly what was set.
function CD.OwnBack(shell, own)
    if type(shell) ~= "table" or type(shell.opts) ~= "table" then return end
    own = own and true or nil
    if shell.opts.noBackground == own then return end
    shell.opts.noBackground = own
    Style.LayoutShell(shell)
end

-- What a background color shows before one is picked (the card shows it too).
function CD.BackDefault(key)
    if key == "backColor" then return { 0, 0, 0, Style.BAR_BACK_ALPHA } end
    if key == "backGradient" and DUI.Gradients then
        local G = DUI.Gradients
        local lo, hi = G.RGB(G.KeyFor("player"))
        return { lo = lo, hi = hi }
    end
end

-- A bar's background: the spell's own (its card's Look tab), else its group's
-- (block.back), else nil for dark (see paint).
-- Returns "solid", {r,g,b,a} | "gradient", {lo,hi} | nil.
function CD.BackOf(button, block)
    local Fx = ns.CdmEffects
    local mode = Fx and Fx.Get(button, "backMode")
    local c, pair
    if mode == "solid" or mode == "gradient" then
        c, pair = Fx.Get(button, "backColor"), Fx.Get(button, "backGradient")
    elseif type(block) == "table" and (block.back == "solid" or block.back == "gradient") then
        mode, c, pair = block.back, block.backColor, block.backGradient
    else
        return nil
    end
    if mode == "solid" then
        if type(c) ~= "table" then c = CD.BackDefault("backColor") end
        return "solid", c
    end
    if type(pair) ~= "table" then pair = CD.BackDefault("backGradient") end
    if type(pair) ~= "table" then return nil end
    return "gradient", pair
end

-- Paints a background texture from CD.BackOf's result (nil leaves it alone).
function CD.PaintBack(tex, mode, v)
    if not tex then return end
    if mode == "solid" then
        tex:SetVertexColor(v[1], v[2], v[3], v[4] or Style.BAR_BACK_ALPHA)
    elseif mode == "gradient" and DUI.Gradients then
        DUI.Gradients.PaintPair(tex, v.lo, v.hi, Style.BAR_BACK_ALPHA)
    end
end

-- The fill color by the block's color mode: your class's pair from the Gradients
-- page (like the unit frames and swing timer), the Daylight gradient, or one color
-- per spell. The background comes from CD.BackOf.
function CD.Colour(item, bar, p, mode, block)
    CD.ColourBase(item, bar, p, mode)
    local Fx = ns.CdmEffects
    local b = Fx and Fx.ButtonOf(item) or item.button
    local back, v
    if p.back then back, v = CD.BackOf(b, block) end
    CD.OwnBack(p.barShell, back ~= nil)
    CD.PlaceName(bar.Name, bar, Fx == nil or Fx.Get(b, "showName") ~= false,
        Fx ~= nil and Fx.Get(b, "nameAlign") == "center")
    CD.PaintBack(p.back, back, v)
end

-- button = the spell's saved options when the item isn't held yet (CdmBars).
function CD.ColourBase(item, bar, p, mode, button)
    local Fx = ns.CdmEffects
    local b = button or (Fx and Fx.ButtonOf(item)) or item.button
    local own = Fx and Fx.Get(b, "barMode")
    if own == "solid" and type(Fx.Get(b, "barColor")) == "table" then
        local c = b.barColor
        Style.SetBarGradient(bar, false)
        paint(p)(bar, c[1], c[2], c[3])
        return
    elseif own == "gradient" and type(Fx.Get(b, "barGradient")) == "table" and DUI.Gradients then
        local G, pair = DUI.Gradients, b.barGradient
        Style.SetBarGradient(bar, false)
        paint(p)(bar, G.MidOf(pair.lo, pair.hi))
        bar:SetStatusBarColor(1, 1, 1, 1)
        G.PaintPair(bar:GetStatusBarTexture(), pair.lo, pair.hi)
        return
    end
    if mode == "class" then
        Style.SetBarGradient(bar, false)
        local G = DUI.Gradients
        if G then
            G.Paint(bar, G.KeyFor("player"), paint(p))
        else
            local _, token = UnitClass("player")
            paint(p)(bar, Style.ClassColor(token))
        end
    elseif mode == "spell" then
        Style.SetBarGradient(bar, false)
        -- Spell IDs can be secret in combat, so only look them up outside it and
        -- keep the last color otherwise.
        if not p.spellColour and not InCombatLockdown() then
            local id
            if type(item.GetSpellID) == "function" then
                local ok, v = pcall(item.GetSpellID, item)
                if ok then id = v end
            end
            if id == nil and type(item.cooldownInfo) == "table" then id = item.cooldownInfo.spellID end
            if type(id) == "number" and not issecretvalue(id) then
                p.spellColour = CD.PALETTE[id % #CD.PALETTE + 1]
            end
        end
        local c = p.spellColour or CD.PALETTE[1]
        paint(p)(bar, c[1], c[2], c[3])
    else
        local sweep = Style.SetBarGradient(bar, true)
        local m = Style.GRADIENT_MID
        paint(p)(bar, m[1], m[2], m[3])
        if sweep then bar:SetStatusBarColor(1, 1, 1, 1) end
    end
end

-- The bar's border frame: around the bar, one border width out.
function CD.PlaceSlot(item)
    local p = skinned[item]
    if not (p and p.slot) then return end
    local T = Pixel.Px(p.slot, Style.BorderPx(p.slot))
    p.slot:ClearAllPoints()
    p.slot:SetPoint("TOPLEFT", p.bar, "TOPLEFT", -T, T)
    p.slot:SetPoint("BOTTOMRIGHT", p.bar, "BOTTOMRIGHT", T, -T)
    Style.LayoutShell(p.barShell)
end

function CD.SkinItem(item)
    if type(item) ~= "table" then return end
    if skinned[item] then
        hideArt(item, skinned[item])
        CD.Place(item)
        return
    end
    local icon, host = CD.IconOf(item)
    if not icon then return end
    local p = { icon = icon, host = host }
    skinned[item] = p
    -- The game's own mask rounds the icon for its art. Without it, it's square.
    local masks = icon.GetNumMaskTextures and icon:GetNumMaskTextures()
    if type(masks) == "number" then
        for i = masks, 1, -1 do
            local m = icon:GetMaskTexture(i)
            if m then pcall(icon.RemoveMaskTexture, icon, m) end
        end
    end
    p.shell = Style.Shell(host, Skin.ShellOpts())
    Skin.PaintCdmShell(p.shell)
    -- The shade goes on the icon's own frame so it draws over the icon.
    local owner = icon:GetParent() or host
    p.shade = owner:CreateTexture(nil, "ARTWORK", nil, 3)
    p.shade:SetTexture(Skin.SHADE_FILE)
    p.shade:SetVertexColor(0, 0, 0, Skin.SHADE)
    mine[p.shade] = true
    -- The game's debuff-type border is a square line just inside the icon. Hide it
    -- with alpha rather than moving it: the icon is laid out around it, so
    -- re-anchoring it collapsed the whole icon.
    local rim = item.DebuffBorder
    if type(rim) == "table" and rim.SetAlpha then rim:SetAlpha(0) end
    -- The game's mask comes from its XML and is removed above once. Its Lua never
    -- adds one again, so there's no hook on the icon's AddMaskTexture.
    if kind(item.Cooldown) == "Cooldown" then Skin.StyleCooldown(item.Cooldown) end
    -- The bar view (BuffBarCooldownViewer): the bar sits in a bordered frame just
    -- outside it, like our own bars (a border on the bar itself sits under its
    -- fill), plus a dim backdrop for the empty part. The fill is Style.TrackBar's
    -- (CD.StyleText) and the game's own backdrop is hidden below (hideArt).
    if kind(item.Bar) == "StatusBar" then
        local bar = item.Bar
        p.bar = bar
        p.slot = CreateFrame("Frame", nil, item)
        p.slot:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
        p.barShell = Style.Shell(p.slot, { borderPx = CD.BarBorder, heavyMinPx = CD.BAR_HEAVY_MIN })
        p.back = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
        p.back:SetAllPoints(bar)
        Style.TrackBack(p.back, ns.MEDIA.bars.cdm)
        mine[p.back] = true
        CD.PlaceSlot(item)
    end
    hideArt(item, p)
    CD.StyleText(item)
    if p.bar then DUI.SafeCall(ns.BuffBars.Attach, item) end
    -- The game resizes icons from its Edit Mode settings, re-places them as auras
    -- come and go, and shows reused icons again. Its Lua never anchors the icon
    -- itself, so there's no hook on the icon's SetPoint; hooks on the game's own
    -- methods broke its calls before.
    if host.HookScript then host:HookScript("OnSizeChanged", function() CD.Place(item) end) end
    if item.HookScript then item:HookScript("OnShow", function() DUI.SafeCall(CD.SkinItem, item) end) end
    CD.Place(item)
end

local function eachItem(viewer, fn)
    local pool = viewer.itemFramePool
    if type(pool) == "table" and pool.EnumerateActive then
        for item in pool:EnumerateActive() do fn(item) end
        return
    end
    for _, child in ipairs({ viewer:GetChildren() }) do
        if type(child) == "table" and child.Icon then fn(child) end
    end
end

CD.EachItem = eachItem
function CD.Parts(item) return skinned[item] end

function CD.SkinViewer(viewer)
    -- The game's layout pass may have moved a spell to another category, so the
    -- known spells are read again.
    if ns.CdmOwn then ns.CdmOwn.Forget() end
    eachItem(viewer, function(item) DUI.SafeCall(CD.SkinItem, item) end)
    -- The player's rows, after the game's layout pass.
    if ns.CdmRows then DUI.SafeCall(ns.CdmRows.Refresh) end
end

-- The reclaim pass. The game lays its items out again (RefreshLayout: the viewer
-- showing, its settings changing, Edit Mode, a full aura update) and puts every item
-- back in its own grid, sometimes with a fresh pool item among them. On the next
-- frame our layout skins and claims them again (CdmRows.Update scans first). No
-- hooks on the game's own methods (RefreshLayout, OnAcquireItemFrame, the items'
-- SetPoint): every moment it lays out is a script, event or EventRegistry callback
-- we hear too, and the items it hides and shows again run their OnHide/OnShow.
-- forget = its settings may have moved a spell to another category, so re-read the
-- known spells.
function CD.Soon(forget)
    if forget and ns.CdmOwn then ns.CdmOwn.Forget() end
    if ns.CdmRows then ns.CdmRows.Refresh() end
end

-- Hooks each viewer the game has made. Returns true once all are hooked.
function CD.Hook()
    local all = true
    for _, name in ipairs(CD.VIEWERS) do
        local v = _G[name]
        if type(v) ~= "table" then
            all = false
        elseif not hooked[v] then
            hooked[v] = true
            -- Its OnShow runs its layout pass, so every icon is there.
            v:HookScript("OnShow", function(self) CD.SkinViewer(self) end)
            -- Its grid resized: a layout pass with more or fewer items.
            v:HookScript("OnSizeChanged", function() CD.Soon() end)
            CD.SkinViewer(v)
        end
    end
    return all
end

-- The game's other layout moments. The viewers hear them too, in no fixed order
-- relative to us, so each one only requests the pass, which runs after they're done.
local heard = false
local function listen()
    if heard then return end
    heard = true
    local R = _G.EventRegistry
    if type(R) == "table" and R.RegisterCallback then
        pcall(R.RegisterCallback, R, "CooldownViewerSettings.OnDataChanged", function() CD.Soon(true) end, CD)
        for _, e in ipairs({ "EditMode.RefreshCooldownViewer", "EditMode.Enter", "EditMode.Exit" }) do
            pcall(R.RegisterCallback, R, e, function() CD.Soon() end, CD)
        end
    end
    -- Edit Mode applying a layout (login, talent swap) re-runs each viewer's
    -- settings and with them its layout.
    DUI.RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function() CD.Soon() end)
    DUI.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function() CD.Soon() end)
    -- A viewer only lays out again on a full aura update (its OnUnitAura); a plain
    -- added or removed aura just updates its items. isFullUpdate is secret in combat
    -- and under restrictions (seen after a reload in combat) on every UNIT_AURA, and
    -- a raid boss's target sends several a second. In that case only the cheap
    -- check runs the next frame (a new item, or one the game put back in its grid),
    -- and the full pass only if it finds one.
    local watch = CreateFrame("Frame")
    watch:RegisterUnitEvent("UNIT_AURA", "player", "target")
    watch:SetScript("OnEvent", function(_, _, _, info)
        local full = type(info) ~= "table" or (not issecretvalue(info.isFullUpdate) and info.isFullUpdate)
        if full then CD.Soon() elseif issecretvalue(info.isFullUpdate) then CD.LookSoon() end
        -- Our holders' missing glow (CdmAuras.IsUp).
        if ns.CdmAuras then ns.CdmAuras.AuraChangedSoon() end
    end)
end

local listening = false
local scanner

-- Icons can appear without a layout pass (a buff icon when an aura lands), so a
-- light check every so often catches anything nothing else did. Returns true when
-- it skinned one.
local function scan()
    local found = false
    for _, name in ipairs(CD.VIEWERS) do
        local v = _G[name]
        if type(v) == "table" and v.IsShown and v:IsShown() then
            eachItem(v, function(item)
                if not skinned[item] then
                    found = true
                    DUI.SafeCall(CD.SkinItem, item)
                end
            end)
        end
    end
    return found
end
CD.Scan = scan

-- The check every CD.SCAN: a new icon, or a placed item that isn't in its block (a
-- layout moment we missed), triggers the reclaim pass.
local function look()
    local R = ns.CdmRows
    if scan() or (R and R.Drifted()) then CD.Soon() end
end

-- The check on the next frame, once however many asked this frame.
local looking = false
local function lookNow()
    looking = false
    look()
end
function CD.LookSoon()
    if looking then return end
    looking = true
    C_Timer.After(0, lookNow)
end

function CD.Tick()
    look()
    -- A totem going up or down changes no layout, so its bar's time is checked here.
    if ns.BuffBars then DUI.SafeCall(ns.BuffBars.SyncClocks) end
end

function CD.Apply()
    CD.enabled = true
    if ns.CdmRows then DUI.SafeCall(ns.CdmRows.Init) end
    DUI.WarnIfLoaded("EllesmereUICooldownManager", "EllesmereUI Cooldown Manager", "Cooldown Manager icons")
    if not scanner and C_Timer and C_Timer.NewTicker then scanner = C_Timer.NewTicker(CD.SCAN, CD.Tick) end
    listen()
    if CD.Hook() or listening then return end
    -- The viewers belong to one of the game's own addons, which may load later.
    listening = true
    DUI.RegisterEvent("ADDON_LOADED", function(_, name)
        if name == CD.ADDON and CD.enabled then DUI.SafeCall(CD.Hook) end
    end)
end

function CD.Refresh()
    for item in pairs(skinned) do
        DUI.SafeCall(CD.StyleText, item)
        DUI.SafeCall(CD.Place, item)
    end
    if ns.BuffBars then DUI.SafeCall(ns.BuffBars.SyncClocks) end
end

-- Old reports used to be kept in the addon's saved settings (cdmProbe, cdmProbeIds,
-- cdmAuraProbe). Clear them; that belongs to the dev tools now.
DUI.RegisterEvent("PLAYER_LOGIN", function()
    local db = _G.DaylightUIDB
    if type(db) == "table" then db.cdmProbe, db.cdmProbeIds, db.cdmAuraProbe = nil, nil, nil end
end)

DUI.RegisterCommand("cdm", function(arg)
    local word, n = string.match(string.lower(arg or ""), "^(%S*)%s*(%S*)")
    if word == "place" and not CD.enabled then
        ns.CdmEditor.Open()          -- reports that it's switched off
    elseif word == "report" then
        -- A player's report, saved in their settings file (DaylightUI.lua) at the
        -- next /reload, to attach to a bug report.
        local lines = ns.CdmRows.Why()
        if type(_G.DaylightUIDB) == "table" then _G.DaylightUIDB.cdmWhy = lines end
        DUI.Print(L["Cooldown layout report saved. Type /reload, then send your DaylightUI.lua file."])
    elseif word == "place" then
        if n == "icon" or n == "bar" then
            local count = ns.CdmRows.PlaceAll(n)
            DUI.Print(string.format(L["%d spells added to the layout."], count))
        else
            DUI.Print(L["/dui cdm place <icon|bar>"])
        end
    -- The dev tools' probes (DaylightUI_Dev, never shipped) get their words first.
    -- Anything else opens the layout editor.
    elseif not (DUI.devCdm and DUI.devCdm(word)) then
        ns.CdmEditor.Open()
    end
end)
