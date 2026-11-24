-- Gear slots: icon with a quality outline, name and one detail line.
-- Clicks are handled by the game: its whole PaperDollItemsFrame is reparented
-- here with each button sitting invisibly over the slot's icon. Moving the frame
-- rather than single buttons keeps their parent and swap-menu setup intact, so
-- hover, the Alt menu and clicks work in combat. Borrowed and returned only
-- out of combat.

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char
local L = DUI.L
local Style = DUI.Style

local Slots = {}
ns.Slots = Slots

Slots.ICON = 48
Slots.AMMO = 22           -- ammo slot size, small as in the game's window
Slots.AMMO_GAP = 10       -- ranged to ammo icon, clears both outlines with room to spare
Slots.EDGE = 3            -- quality outline width
Slots.GAP = 10            -- icon to name
Slots.NAME_SIZE, Slots.LINE_SIZE, Slots.CORNER_SIZE = Style.SIZE.body, Style.SIZE.small, Style.SIZE.tiny
Slots.CORNER_BG_ALPHA, Slots.CORNER_BG_PAD = 0.65, 1   -- the dark square behind the corner's number
Slots.ENCHANT_SIZE = Style.SIZE.small
Slots.MARK = 5                                -- enchant marker size in icons-only mode
Slots.DOT = 7
Slots.DIM = DUI.Style.INK.LABEL     -- line under a name
Slots.OFF = DUI.Style.INK.OFF       -- empty slot text
Slots.EMPTY_EDGE = { 0.22, 0.22, 0.24 }
Slots.EMPTY_TINT = { 0.5, 0.5, 0.52, 0.6 }   -- dimmed empty-slot texture
Slots.AMBER = { 1, 0.69, 0.25 }
Slots.RED = { 1, 0.35, 0.35 }
Slots.RING = { 1, 1, 1, 0.35 }               -- hover
Slots.GLOW = { 1, 1, 1, 0.22 }               -- held item fits this slot
Slots.SWAP_GLOW = { size = 0.7, thick = 0.08 }   -- the lights round a slot an equipment set will change
Slots.HOLD_DIM = 0.55                         -- other slots while holding an item
Slots.SOFT = 0.25                             -- how much to soften quality colors on names
Slots.HOVER_TICK = 0.05
Slots.BAND_DIM = 0.45     -- outline band brightness, matching the bags
Slots.SHADE = DUI.MEDIA .. "inner-shadow.png"
Slots.SHADE_ALPHA = 0.55
Slots.WHITE = "Interface\\Buttons\\WHITE8X8"

Slots.frames = {}
Slots.byButton = {}
Slots.lent = false
local home, buttonHome, flyHome = nil, {}, nil   -- original spots of the game's frames, for returning them

-- ItemButtonMixin:SetAlpha only fades the icon parts. Fading the whole button
-- needs the widget's own SetAlpha.
function Slots.RawAlpha(b, a)
    local mt = getmetatable(b)
    local base = mt and type(mt.__index) == "table" and mt.__index.SetAlpha
    if type(base) == "function" then base(b, a) else b:SetAlpha(a) end
end

local function square(parent, layer, sub, inset, rgba)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(Slots.WHITE)
    t:SetPoint("TOPLEFT", -inset, inset)
    t:SetPoint("BOTTOMRIGHT", inset, -inset)
    t:SetVertexColor(rgba[1], rgba[2], rgba[3], rgba[4] or 1)
    return t
end

-- A band around the icon from `from` to `to` px out, as four non-overlapping
-- strips. A filled square behind the icon showed through it while the window
-- faded and washed common items out to white.
local Band = {}
Band.__index = Band
function Band:SetVertexColor(r, g, b, a) for _, t in ipairs(self) do t:SetVertexColor(r, g, b, a or 1) end end
function Band:SetShown(on) self.shown = on == true; for _, t in ipairs(self) do t:SetShown(on) end end
function Band:Show() self:SetShown(true) end
function Band:Hide() self:SetShown(false) end
function Band:IsShown() return self.shown end
function Band:Ease(on)
    if on == (self.shown == true) then return end
    self.shown = on
    local M = DUI.Motion
    for _, t in ipairs(self) do M.AlphaTo(t, on and 1 or 0, M.FAST, true) end
end

local function band(icon, sub, from, to, rgba)
    local o = setmetatable({ shown = true }, Band)
    local function strip(p1, x1, y1, p2, x2, y2)
        local t = icon:CreateTexture(nil, "BACKGROUND", nil, sub)
        t:SetTexture(Slots.WHITE)
        t:SetPoint("TOPLEFT", icon, p1, x1, y1)
        t:SetPoint("BOTTOMRIGHT", icon, p2, x2, y2)
        o[#o + 1] = t
    end
    strip("TOPLEFT", -to, to, "TOPRIGHT", to, from)                -- top, full width
    strip("BOTTOMLEFT", -to, -from, "BOTTOMRIGHT", to, -to)        -- bottom, full width
    strip("TOPLEFT", -to, from, "BOTTOMLEFT", -from, -from)        -- left, between them
    strip("TOPRIGHT", from, from, "BOTTOMRIGHT", to, -from)        -- right, between them
    o:SetVertexColor(rgba[1], rgba[2], rgba[3], rgba[4])
    return o
end

-- Quality outline in the bags' style: a soft rounded shell around the icon.
local Edge = {}
Edge.__index = Edge
-- The outline sits a whole number of screen pixels out, so no side is
-- thinner. Called again when the scale changes.
function Edge:Fit()
    local f, icon = self.frame, self.icon
    local out = DUI.Pixel.Snap(f, self.px)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", icon, "TOPLEFT", -out, out)
    f:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", out, -out)
end

function Edge:SetVertexColor(r, g, b)
    local k = Slots.BAND_DIM
    Style.SetShellColors(self.shell, { r, g, b }, { r * k, g * k, b * k })
end

-- icon is a frame or a texture (then the edge goes on its parent). px is the
-- outline width, Slots.EDGE by default. Used by every item icon in the UI.
function Slots.Edge(icon, px)
    px = px or Slots.EDGE
    local parent = icon:GetObjectType() == "Texture" and icon:GetParent() or icon
    local f = CreateFrame("Frame", nil, parent)
    local o = setmetatable({ frame = f, icon = icon, px = px }, Edge)
    o:Fit()
    o.shell = Style.Shell(f, { borderPx = px, noBevel = true, noBackground = true })
    o:SetVertexColor(Slots.EMPTY_EDGE[1], Slots.EMPTY_EDGE[2], Slots.EMPTY_EDGE[3])
    return o
end

-- side: "left" puts the icon left of the text, "right" mirrors it.
-- size defaults to Slots.ICON. into is the table to store the slot in,
-- Slots.frames by default. The inspect window passes its own.
function Slots.Make(parent, key, side, size, into)
    local h = CreateFrame("Frame", nil, parent)
    h.key, h.side, h.size = key, side, size or Slots.ICON
    h.icon = CreateFrame("Frame", nil, h)
    h.icon:SetSize(h.size, h.size)
    h.glow = band(h.icon, -2, Slots.EDGE, Slots.EDGE + 3, Slots.GLOW)
    h.glow:Hide()
    h.ring = band(h.icon, -1, Slots.EDGE, Slots.EDGE + 1, Slots.RING)
    h.ring:Hide()
    h.edge = Slots.Edge(h.icon)
    -- Dark backing under the icon only. The empty-slot texture sits on it.
    h.back = square(h.icon, "BACKGROUND", 0, 0, Slots.EMPTY_EDGE)
    h.tex = h.icon:CreateTexture(nil, "ARTWORK")
    h.tex:SetAllPoints()
    Style.CropIcon(h.tex)
    h.shade = h.icon:CreateTexture(nil, "ARTWORK", nil, 3)
    h.shade:SetTexture(Slots.SHADE)
    h.shade:SetVertexColor(0, 0, 0, Slots.SHADE_ALPHA)
    h.shade:SetAllPoints()
    h.shade:Hide()
    h.dot = h.icon:CreateTexture(nil, "OVERLAY")
    h.dot:SetTexture(Slots.WHITE)
    h.dot:SetSize(Slots.DOT, Slots.DOT)
    h.dot:SetPoint("TOPRIGHT", h.icon, "TOPRIGHT", -2, -2)
    h.dot:Hide()
    -- A dark square behind the corner's number, so it doesn't melt into the icon's art.
    h.cornerBg = h.icon:CreateTexture(nil, "OVERLAY")
    h.cornerBg:SetTexture(Slots.WHITE)
    h.cornerBg:SetVertexColor(0, 0, 0, Slots.CORNER_BG_ALPHA)
    h.cornerBg:Hide()
    h.corner = Style.Text(h.icon, Slots.CORNER_SIZE, "CENTER")
    h.cornerBg:SetPoint("BOTTOMRIGHT", h.icon, "BOTTOMRIGHT", 0, 0)
    h.corner:SetPoint("CENTER", h.cornerBg, "CENTER", 0, 0)   -- the number in the middle of its square
    local justify = side == "right" and "RIGHT" or "LEFT"
    h.name = Style.Text(h, Slots.NAME_SIZE, justify)
    h.name:SetWordWrap(false)
    h.line = Style.Text(h, Slots.LINE_SIZE, justify)
    h.line:SetWordWrap(false)
    h.enchant = Style.Text(h, Slots.ENCHANT_SIZE, justify)
    h.enchant:SetWordWrap(false)
    h.mark = h.icon:CreateTexture(nil, "OVERLAY")
    h.mark:SetTexture(Slots.WHITE)
    h.mark:SetSize(Slots.MARK, Slots.MARK)
    h.mark:SetPoint("TOPLEFT", h.icon, "TOPLEFT", 2, -2)
    h.mark:Hide()
    local kept = into or Slots.frames
    kept[key] = h
    return h
end

-- into as in Slots.Make. unit decides whether there's an ammo slot (player by default).
function Slots.MakeAll(parent, into, unit)
    into = into or Slots.frames
    for _, key in ipairs(ns.Gear.LEFT) do Slots.Make(parent, key, "left", nil, into) end
    for _, key in ipairs(ns.Gear.RIGHT) do Slots.Make(parent, key, "right", nil, into) end
    for _, key in ipairs(ns.Gear.BOTTOM) do Slots.Make(parent, key, "left", nil, into) end
    -- Small ammo slot beside the ranged icon, placed by the page. Shown from the
    -- start so the game's ammo button gets borrowed correctly.
    Slots.Make(parent, "Ammo", "left", Slots.AMMO, into)
    into.Ammo:SetShown(ns.Gear.UsesAmmo(unit))
    return into
end

-- Width the ammo slot adds beside the ranged icon.
function Slots.AmmoRoom() return Slots.AMMO_GAP + Slots.AMMO end

-- A text's width as it would run on one line, whatever room it has.
local function natural(fs)
    local ok, w = pcall(function()
        local v = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()
        if type(v) ~= "number" then v = fs:GetStringWidth() end
        return v
    end)
    if ok and type(w) == "number" and not DUI.IsSecret(w) then return w end
    return 0   -- not measurable (a secret): it is left on one line
end

-- Text beside the icon. Name and line are centered on it, or with an enchant
-- all three lines span its height. A name too long for one line (h.wrap) takes two and
-- the lines span the icon's height the same way. With no line under it (the level is in
-- the icon's corner, or the line is off) the name is centered on the icon.
local function stack(h, three)
    h.three = three
    local right = h.side == "right"
    local p, edge = right and "RIGHT" or "LEFT", right and "LEFT" or "RIGHT"
    local x = right and -h.gap or h.gap
    h.name:ClearAllPoints()
    h.line:ClearAllPoints()
    h.enchant:ClearAllPoints()
    if three then
        h.name:SetPoint("TOP" .. p, h.icon, "TOP" .. edge, x, 1)
        h.line:SetPoint("TOP" .. p, h.name, "BOTTOM" .. p, 0, -1)
        h.enchant:SetPoint("TOP" .. p, h.line, "BOTTOM" .. p, 0, -1)
    elseif h.lineWrap then
        -- A line on two rows: the words are centered on the icon as a block.
        local nameH = h.name:GetStringHeight()
        local lineH = h.line:GetStringHeight()
        if type(nameH) ~= "number" or DUI.IsSecret(nameH) then nameH = Slots.NAME_SIZE + 3 end
        if type(lineH) ~= "number" or DUI.IsSecret(lineH) then lineH = 2 * (Slots.LINE_SIZE + 3) end
        h.name:SetPoint("TOP" .. p, h.icon, edge, x, (nameH + 1 + lineH) / 2)
        h.line:SetPoint("TOP" .. p, h.name, "BOTTOM" .. p, 0, -1)
        h.enchant:SetPoint("TOP" .. p, h.line, "BOTTOM" .. p, 0, -1)
    elseif h.lineless then
        h.name:SetPoint(p, h.icon, edge, x, 0)
        h.line:SetPoint("TOP" .. p, h.name, "BOTTOM" .. p, 0, -1)
        h.enchant:SetPoint("TOP" .. p, h.line, "BOTTOM" .. p, 0, -1)
    elseif h.wrap then
        h.name:SetPoint("TOP" .. p, h.icon, "TOP" .. edge, x, 1)
        h.line:SetPoint("TOP" .. p, h.name, "BOTTOM" .. p, 0, -1)
        h.enchant:SetPoint("TOP" .. p, h.line, "BOTTOM" .. p, 0, -1)
    else
        h.name:SetPoint("BOTTOM" .. p, h.icon, edge, x, 1)
        h.line:SetPoint("TOP" .. p, h.icon, edge, x, -1)
    end
end

-- The words fit the room beside the icon: a long name takes a second line, and so does a
-- long line under it ("Repair soon", "Broken" in a long language), so none ends in dots
-- (a slot with an enchant has no room for one). The whole name is in the tooltip.
function Slots.FitText(h)
    if not h.entry then return end
    local lineless = h.lineFull == ""
    if lineless ~= (h.lineless == true) then
        h.lineless = lineless
        stack(h, h.three == true)
    end
    if not h.names then return end
    local width = h.name:GetWidth() or 0
    if width <= 0 then return end
    local wrap = h.three ~= true and h.entry.empty ~= true and natural(h.name) > width + 0.5
    local lw = h.three ~= true and not lineless and h.entry.empty ~= true
        and natural(h.line) > (h.line:GetWidth() or 0) + 0.5
    local lineWrap = lw == true
    local changed = wrap ~= (h.wrap == true) or lineWrap ~= (h.lineWrap == true)
    if wrap ~= (h.wrap == true) then
        h.wrap = wrap
        h.name:SetWordWrap(wrap)
        h.name:SetMaxLines(wrap and 2 or 0)
    end
    if lineWrap ~= (h.lineWrap == true) then
        h.lineWrap = lineWrap
        h.line:SetWordWrap(lineWrap)
        h.line:SetMaxLines(lineWrap and 2 or 0)
    end
    -- A text that changed under the same wrap (another item in the slot) moves the block.
    if changed or h.lineWrap then stack(h, h.three == true) end
end

-- width is the slot's full width. names toggles text beside the icon. lead is
-- extra space between icon and text (Ranged uses it for the ammo slot).
function Slots.Layout(h, width, names, lead)
    lead = lead or 0
    local gap = Slots.GAP + lead
    -- A whole number of screen pixels, so the outline is the same on every
    -- side. Snapped on every layout, since the window's scale can change.
    h.px = DUI.Pixel.Snap(h.icon, h.size)
    h.icon:SetSize(h.px, h.px)
    h.edge:Fit()
    h:SetSize(width, h.px)
    h.gap = gap
    h.icon:ClearAllPoints()
    if h.side == "right" then
        h.icon:SetPoint("RIGHT", h, "RIGHT", 0, 0)
    else
        h.icon:SetPoint("LEFT", h, "LEFT", 0, 0)
    end
    stack(h, h.three == true)
    local textW = math.max(0, width - h.px - gap)
    h.name:SetWidth(textW)
    h.line:SetWidth(textW)
    h.enchant:SetWidth(textW)
    h.name:SetShown(names)
    h.line:SetShown(names)
    h.names = names
    Slots.FitText(h)
end

-- opts.itemLevel shows the item level line.
-- Gear swapped while the window is open fades in. Stepped by hand, since the
-- window can't use alpha animations.
-- Only the picture and the words the slot shows: fading up shows a hidden text,
-- and the ammo slot's name and count would land on the ranged weapon's.
local function arrive(h)
    local M = DUI.Motion
    for _, r in ipairs({ h.tex, h.name, h.line }) do
        if r == h.tex or h.names then
            r:SetAlpha(0)
            M.AlphaTo(r, 1, M.NORMAL)
        end
    end
end

function Slots.Paint(h, e, opts)
    local swapped = h.entry and not e.empty and h.entry.name ~= e.name and h:IsVisible()
    h.entry, h.opts = e, opts
    local itemLevel = opts.itemLevel ~= false
    if e.empty then
        local t = Slots.EMPTY_TINT
        h.tex:SetTexture(e.emptyIcon)
        h.tex:SetVertexColor(t[1], t[2], t[3])
        h.tex:SetAlpha(t[4])
        h.edge:SetVertexColor(Slots.EMPTY_EDGE[1], Slots.EMPTY_EDGE[2], Slots.EMPTY_EDGE[3], 1)
        h.name:SetText(e.label)
        h.name:SetTextColor(Slots.OFF[1], Slots.OFF[2], Slots.OFF[3])
        h.shade:Hide()
    else
        h.shade:Show()
        h.tex:SetTexture(e.icon)
        h.tex:SetVertexColor(1, 1, 1)
        h.tex:SetAlpha(1)
        local r, g, b = ns.Gear.QualityColor(e.quality)
        h.edge:SetVertexColor(r, g, b, 1)
        h.name:SetText(e.name or e.label)
        h.name:SetTextColor(Style.Soften(r, g, b, Slots.SOFT, 1))
    end
    local text, kind = ns.Gear.Line(e)
    if kind == "dim" and not e.empty and not e.ammo and not itemLevel then text = "" end
    -- The level in the icon's corner: no line of it under the name (a shirt's own word stays).
    if kind == "dim" and not e.empty and not e.ammo and opts.levelInIcon == true and not ns.Gear.NO_LEVEL[e.key] then text = "" end
    h.line:SetText(text)
    h.lineFull = text
    local c = (kind == "red" and Slots.RED) or (kind == "amber" and Slots.AMBER) or (e.empty and Slots.OFF) or Slots.DIM
    h.line:SetTextColor(c[1], c[2], c[3])
    if swapped then arrive(h) end
    h.dot:SetShown(e.wear ~= nil)
    if e.wear then
        local d = e.wear == "broken" and Slots.RED or Slots.AMBER
        h.dot:SetVertexColor(d[1], d[2], d[3], 1)
    end
    -- Icons-only mode shows the item level in the corner, or the ammo count.
    local corner = ""
    if not h.names or opts.levelInIcon == true then
        -- (the ammo's count is in the footer, whole, beside the durability)
        if e.ammo then corner = ""
        elseif itemLevel and e.level and not ns.Gear.NO_LEVEL[e.key] then corner = tostring(e.level) end
    end
    h.corner:SetText(corner)
    h.cornerBg:SetShown(corner ~= "")
    if corner ~= "" then
        -- A square, the same room all round the digits: as wide as the text (or as tall as its size,
        -- if that is more) plus the pad on each side. The text gets the whole-pixel width it is
        -- centered in, so a two-digit number does not sit off to one side.
        local w = math.max(math.ceil(h.corner:GetStringWidth()), Slots.CORNER_SIZE)
        h.corner:SetWidth(w)
        local side = w + 2 * Slots.CORNER_BG_PAD
        h.cornerBg:SetSize(side, side)
    end
    Slots.PaintEnchant(h, e, opts.missingEnchants == true and ns.Gear.MissingEnchant(e))
    Slots.FitText(h)
    if h.over then Style.InkText(h.name, "VALUE") end
end

-- Enchant as a third line, or a small mark in icons-only mode. A new
-- enchant fades in. The first paint doesn't animate.
function Slots.PaintEnchant(h, e, missing)
    local text = (not e.empty and e.enchant) or nil
    -- In the accent, so it stands apart from green item names and the white
    -- lines. A slot that could have one says so softly.
    local r, g, b = DUI.Style.Accent()
    h.mark:SetVertexColor(r, g, b, 1)
    if text then
        h.enchant:SetTextColor(r, g, b)
    elseif missing then
        text = L["No enchant"]
        DUI.Style.InkText(h.enchant, "OFF")
    end
    local three = h.names == true and text ~= nil
    if three ~= (h.three == true) then stack(h, three) end
    h.enchant:SetShown(three)
    h.mark:SetShown(text ~= nil and not h.names and not missing)
    if text == h.enchantText then return end
    local fresh = h.enchantPainted and text ~= nil
    h.enchantText, h.enchantPainted = text, true
    h.enchant:SetText(text or "")
    if fresh then
        local M = DUI.Motion
        M.Fade(h.names and h.enchant or h.mark, 0, 1, M.SLOW)
    end
end

-- Borrowing the game's slot frame

local function gameButtons()
    local items = PaperDollItemsFrame
    local out = {}
    if type(items) ~= "table" then return out end
    local seen = {}
    for _, list in ipairs({ items.EquipmentSlots or {}, items.WeaponSlots or {} }) do
        for _, b in ipairs(list) do out[#out + 1] = b; seen[b] = true end
    end
    -- The ammo button may not be in either list since it hangs off the ranged
    -- one. Missing it left it beside the Ranged slot instead of on Ammo.
    local ammo = _G.CharacterAmmoSlot
    if type(ammo) == "table" and not seen[ammo] then out[#out + 1] = ammo end
    return out
end

local function pointsOf(f)
    local out = {}
    for i = 1, (f:GetNumPoints() or 0) do out[i] = { f:GetPoint(i) } end
    return out
end

local function restore(f, points)
    f:ClearAllPoints()
    for _, p in ipairs(points) do f:SetPoint(unpack(p)) end
end

local function onIcon(b, h)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", h.icon, "TOPLEFT", 0, 0)
    b:SetPoint("BOTTOMRIGHT", h.icon, "BOTTOMRIGHT", 0, 0)
end

local function slotFor(b)
    local id = b:GetID()
    for key, h in pairs(Slots.frames) do
        if ns.Gear.SlotId(key) == id then return h end
    end
end

function Slots.Lend() DUI.AfterCombat(Slots.DoLend, "characterLend") end

function Slots.DoLend()
    local f, items = ns.window, PaperDollItemsFrame
    if Slots.lent or InCombatLockdown() then return end
    if not (f and type(items) == "table" and ns.Follow and ns.Follow.parked and next(Slots.frames)) then return end
    -- Parent to the Character page so the invisible buttons hide on other pages.
    local _, any = next(Slots.frames)
    local host = any:GetParent() or f
    home = { parent = items:GetParent(), points = pointsOf(items), w = items:GetWidth(), h = items:GetHeight(),
             level = items:GetFrameLevel() }
    items:SetParent(host)
    items:ClearAllPoints()
    items:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    items:SetSize(1, 1)   -- so it never covers the tabs
    for _, b in ipairs(gameButtons()) do
        buttonHome[b] = { points = pointsOf(b), mouse = b:IsMouseEnabled(), level = b:GetFrameLevel() }
        Slots.RawAlpha(b, 0)
        local h = slotFor(b)
        if h then
            onIcon(b, h)
            -- The controller should stop on the slot, not the game's button,
            -- since A on the game's picks the item up (ns.CharacterPage.PadSetup).
            DUI.Widgets.PadSkip(b)
            h.button = b
            Slots.byButton[b] = h
            Slots.Catch(b, h)
        else
            -- No matching slot here, so move it aside and stop it catching clicks.
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", items, "TOPLEFT", 0, 0)
            b:EnableMouse(false)
        end
    end
    Slots.lent = true
end

function Slots.Return()
    if not Slots.lent or InCombatLockdown() then return false end
    -- A new parent drops a frame to one level above it, and the game keeps its
    -- model under the slots only by level, so the old levels go back too.
    local items = PaperDollItemsFrame
    items:SetParent(home.parent)
    if home.level then items:SetFrameLevel(home.level) end
    restore(items, home.points)
    if (home.w or 0) > 0 then items:SetSize(home.w, home.h) end
    for b, saved in pairs(buttonHome) do
        restore(b, saved.points)
        if saved.level then b:SetFrameLevel(saved.level) end
        b:EnableMouse(saved.mouse ~= false)
        Slots.RawAlpha(b, 1)
    end
    buttonHome = {}
    local fly = EquipmentFlyoutFrame
    if flyHome and type(fly) == "table" then fly:SetParent(flyHome) end
    flyHome = nil
    for _, h in pairs(Slots.frames) do h.button = nil end
    Slots.byButton = {}
    Slots.lent = false
    Slots.Lift()
    return true
end

local function descendants(f, out)
    for _, c in ipairs({ f:GetChildren() }) do
        out[#out + 1] = c
        descendants(c, out)
    end
    return out
end

-- The game means each slot to sit one level above its holder (100), over the
-- model (50), but in game they can load at level 4, under the model, which
-- then takes every hover and click. Each slot goes back to one above its
-- holder, its own pieces (border, Alt arrow, outline) moved by the same amount.
-- The slots aren't protected, so this works in a fight too.
function Slots.Lift()
    local items = PaperDollItemsFrame
    if Slots.lent or type(items) ~= "table" then return end
    local base = items:GetFrameLevel()
    for _, b in ipairs(gameButtons()) do
        local level = b:GetFrameLevel()
        if b:GetParent() == items and level <= base then
            local kids = descendants(b, {})
            local was = {}
            for i, c in ipairs(kids) do was[i] = c:GetFrameLevel() end
            local shift = base + 1 - level
            b:SetFrameLevel(base + 1)
            -- Only the ones the client didn't already carry along.
            for i, c in ipairs(kids) do
                if c:GetFrameLevel() == was[i] then c:SetFrameLevel(was[i] + shift) end
            end
        end
    end
end

-- The Alt swap menu attaches to the parked page each time it fills, so move it here after.
function Slots.FlyoutToUs()
    local fly, f = EquipmentFlyoutFrame, ns.window
    if not (Slots.lent and f and type(fly) == "table" and type(fly.button) == "table") then return end
    if Slots.byButton[fly.button] and fly:GetParent() ~= f then
        flyHome = flyHome or fly:GetParent()
        fly:SetParent(f)
        fly:SetFrameStrata("HIGH")
    end
end

local hooked = false
function Slots.Hook()
    if hooked then return end
    hooked = true
    if type(EquipmentFlyout_UpdateItems) == "function" then hooksecurefunc("EquipmentFlyout_UpdateItems", Slots.FlyoutToUs) end
end

-- Hover, held items, pinning

-- Hover comes from the game's button: a soft ring on the icon and a brighter
-- name. If no ring is lit and the mouse is off the page, skip checking each slot.
local lit = 0
function Slots.Hover(page)
    if lit == 0 and page and not page:IsMouseOver() then return end
    for _, h in pairs(Slots.frames) do
        local over = h.button ~= nil and h.button:IsMouseOver() == true
        if over ~= (h.over == true) then
            h.over = over
            lit = lit + (over and 1 or -1)
            h.ring:SetShown(over)
            if h.entry then Slots.Paint(h, h.entry, h.opts or {}) end
        end
    end
end

local function yes(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, ...)
    return ok and not DUI.IsSecret(v) and v == true
end

-- A spell waiting for an item target (enchant, armor kit), from
-- ItemButtonUtil.GetItemContext like the game's item buttons. nil if none.
function Slots.Aimed()
    if not (C_Spell and C_Item and type(ItemLocation) == "table") then return nil end
    if yes(C_Spell.TargetSpellIsEnchanting) then return C_Item.DoesItemMatchTargetEnchantingSpell end
    if yes(C_Spell.TargetSpellChecksItemCondition) then return C_Item.DoesItemMatchSpellItemCondition end
end

-- Whether the worn piece in slot id takes the waiting spell (test from Slots.Aimed).
function Slots.Fits(test, id)
    local loc = ItemLocation:CreateFromEquipmentSlot(id)
    return yes(C_Item.DoesItemExist, loc) and yes(test, loc)
end

-- A hidden slot (no ammo for this class) only gets the alpha, since AlphaTo
-- would show it. restAlpha is where the page's opening fade stops too.
local function dim(h, on)
    if on == (h.dimmed == true) then return end
    h.dimmed = on
    local to, M = on and Slots.HOLD_DIM or 1, DUI.Motion
    h.restAlpha = to
    if h:IsShown() then M.AlphaTo(h, to, M.FAST) else h:SetAlpha(to) end
end

-- While holding an item or targeting one with a spell, matching slots glow and
-- the rest dim a little.
function Slots.Holding()
    local holding = type(CursorHasItem) == "function" and CursorHasItem() == true
    local can = C_PaperDollInfo and C_PaperDollInfo.CursorCanGoInSlot
    local test = not holding and Slots.Aimed() or nil
    for key, h in pairs(Slots.frames) do
        local id = ns.Gear.SlotId(key)
        local fits = id ~= nil and ((holding and can ~= nil and can(id) == true) or (test ~= nil and Slots.Fits(test, id)))
        h.glow:Ease(fits)
        dim(h, (holding or test ~= nil) and not fits)
    end
end

-- The slots an equipment set is about to change get the circling lights.
-- slots: { [slot id] = true }, nil for none.
function Slots.Swap(slots)
    local W = DUI.Widgets
    for key, h in pairs(Slots.frames) do
        local id = ns.Gear.SlotId(key)
        local on = slots ~= nil and id ~= nil and slots[id] == true and h:IsShown()
        if on or h.swapGlow then
            if not h.swapGlow then
                h.swapGlow = CreateFrame("Frame", nil, h.icon)
                h.swapGlow:SetAllPoints(h.icon)
                h.swapGlow:SetFrameLevel(h.icon:GetFrameLevel() + 6)
            end
            h.swapping = on
            W.GlowAround(h.swapGlow, on, { frame = h.icon, inset = -Slots.EDGE, thick = DUI.Pixel.Px(h.icon, 2),
                scale = Slots.SWAP_GLOW, parent = h.swapGlow, layer = "OVERLAY", sub = 7 })
        end
    end
end

-- A borrowed button only takes clicks while its slot shows, so a hidden ammo
-- slot leaves no invisible button behind.
function Slots.Catch(b, h)
    local want = h:IsShown() == true
    if b:IsMouseEnabled() ~= want then b:EnableMouse(want) end
end

-- The game re-places the ranged and ammo buttons when the ammo slot shows or
-- hides. Put them back, out of combat.
function Slots.Pin()
    if not Slots.lent or InCombatLockdown() then return end
    for b, h in pairs(Slots.byButton) do
        local _, rel = b:GetPoint(1)
        if rel ~= h.icon then onIcon(b, h) end
        Slots.Catch(b, h)
    end
end
