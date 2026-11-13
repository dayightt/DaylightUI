-- Action buttons in the same icon look as the auras and buffs. Covers our own bars'
-- buttons and the game's stance, pet, possess and totem buttons we hold: the shell's
-- border around a square, cropped icon with a soft inner shadow, and our font for
-- keybinds, counts and macro names. The character is in how they behave:
--   * empty slots can be hidden, and show again while something is dragged;
--   * out of range, or short of rage, mana or energy, the icon fades (the keybind
--     stays white);
--   * the border carries a proc (the accent), the way aggro colors the unit frames;
--   * a press dips the icon.
-- Border thickness, text and every color are settings applied live: db.look for all
-- bars, with a bar's own changes on top in db.barLooks[key] (Skin.LookFor). Each
-- button reads its bar's look (parts.L). The module-wide values below (BORDER_PX,
-- CROP, SWIPE, COUNT...) are the Cooldown Manager's look (barLooks.cdm on top of
-- db.look), read by its files; the bag bar and micro menu read the shared look
-- (Skin.shared). Our buttons are painted by Buttons.lua's painters. On the game's
-- buttons the art is hidden by alpha, never replaced, and nothing is stored on them.

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel

local Skin = {}
ns.Skin = Skin

Skin.ART = { "SlotArt", "SlotBackground", "Border", "NewActionTexture", "FloatingBG", "RightDivider", "BottomDivider",
             -- The bright casting animations (a yellow fill and frame over the
             -- icon). The accent checked tint already marks the spell.
             "SpellCastAnimFrame", "InterruptDisplay", "TargetReticleAnimFrame" }
-- The icon look the auras and buffs use: the shell's border around a square icon,
-- cropped, with a soft inner shadow.
Skin.BORDER_PX = 3           -- edge width in screen pixels (same weight as the aura icons); a setting
Skin.SHELL = { borderPx = function() return Skin.BORDER_PX end, noBevel = true }
Skin.ICON_MASKS = { "IconMask", "CircleMask", "SquareMask" }   -- the game's masks on an action button's icon

-- Each button gets its own copy of the shell settings. A shell keeps the table it's
-- given and a proc's border color is set on it, so a shared one would color every
-- button.
function Skin.ShellOpts()
    local o = {}
    for k, v in pairs(Skin.SHELL) do o[k] = v end
    return o
end
-- The same for the bag bar and micro menu, using the shared look's border.
function Skin.SharedShellOpts()
    local o = Skin.ShellOpts()
    o.borderPx = function() return Skin.BorderPx(Skin.LookFor(nil)) end
    Skin.StyleShellOpts(o, Skin.LookFor(nil))
    return o
end

-- Button shapes (Button shape), with media from tools/make_shapes.py. A shaped
-- button keeps its shell for the empty-slot alpha but draws none of it; the shape's
-- own pieces sit on the shell frame instead (Skin.Shape).
Skin.SHAPES = { circle = true, diamond = true, hexagon = true, octagon = true, shield = true }
Skin.SHADOW_K = 128 / 96          -- shadow image size relative to its shape's (make_shapes.py SHADOW_INNER)
function Skin.ShapeOf(L)
    local s = L and L.shape
    return Skin.SHAPES[s] and s or nil
end
local function shapeFile(name, kind)
    return DUI.MEDIA .. "shape-" .. name .. (kind and "-" .. kind or "") .. ".png"
end

-- A look's border thickness. "none" draws no border, so the icon fills the button.
function Skin.BorderPx(L)
    return L.borderStyle == "none" and 0 or L.border
end

-- Applies a look's border style to a shell's options (Border style, Corners, Shadow).
-- Returns true when it changed anything.
function Skin.StyleShellOpts(o, L)
    local shaped = Skin.ShapeOf(L) ~= nil
    local flat, none = L.borderStyle == "flat" or shaped, L.borderStyle == "none" or shaped
    local shadow = (L.shadow == false or shaped) and 0 or nil
    local corner = (L.corners == "square" or shaped) and 0 or nil
    local noBack = shaped or nil
    if o.flat == flat and o.noBorder == none and o.shadowAlpha == shadow and o.cornerPx == corner
        and o.noBackground == noBack then return false end
    o.flat, o.noBorder, o.shadowAlpha, o.cornerPx, o.noBackground = flat, none, shadow, corner, noBack
    return true
end

-- Shapes a button. st keeps its pieces (a button's parts, a CDM item's), host makes
-- the mask, s is its shell frame (the pieces go on it, under the icon, and fade with
-- it), icon and overlays take the mask, and cds get a sweep in the shape. Square (no
-- shape) restores everything. Returns true when shaped.
function Skin.Shape(st, host, s, icon, overlays, cds, L)
    local name = Skin.ShapeOf(L)
    st.masked = st.masked or {}
    if not name then
        if not st.shape then return false end
        for tex in pairs(st.masked) do pcall(tex.RemoveMaskTexture, tex, st.shapeMask) end
        for k in pairs(st.masked) do st.masked[k] = nil end
        for _, k in ipairs({ "shapeShadow", "shapeOuter", "shapeBand", "shapeBg" }) do st[k]:Hide() end
        for _, cd in ipairs(cds) do
            if cd.SetSwipeTexture then pcall(cd.SetSwipeTexture, cd, Skin.SWIPE_FILE) end
            if cd.SetUseCircularEdge then pcall(cd.SetUseCircularEdge, cd, false) end
        end
        st.shape = nil
        return false
    end
    local file = shapeFile(name)
    if not st.shapeMask then
        st.shapeMask = host:CreateMaskTexture()
        st.shapeShadow = s:CreateTexture(nil, "BACKGROUND", nil, -8)
        st.shapeOuter = s:CreateTexture(nil, "BORDER", nil, 0)
        st.shapeBand = s:CreateTexture(nil, "BORDER", nil, 1)
        st.shapeBg = s:CreateTexture(nil, "BORDER", nil, 2)
        -- The border and band are filled shapes. Cut the middle out of them so the
        -- background shows the world through it, as a square button's does.
        st.shapeHole = s:CreateMaskTexture()
        st.shapeOuter:AddMaskTexture(st.shapeHole)
        st.shapeBand:AddMaskTexture(st.shapeHole)
    end
    st.shape = name
    st.shapeMask:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    st.shapeMask:ClearAllPoints()
    st.shapeMask:SetAllPoints(icon)
    local list = { icon }
    for _, tex in pairs(overlays) do list[#list + 1] = tex end     -- overlays may have holes
    for _, tex in ipairs(list) do
        if not st.masked[tex] and tex.AddMaskTexture then
            if pcall(tex.AddMaskTexture, tex, st.shapeMask) then st.masked[tex] = true end
        end
    end
    local T = Pixel.Px(host, Skin.BorderPx(L))
    local band = Pixel.Px(host, 1)
    local w = host:GetWidth() or 0
    local e = w * (Skin.SHADOW_K - 1) / 2
    st.shapeShadow:SetTexture(shapeFile(name, "shadow"))
    local g = DUI.DB.General()
    st.shapeShadow:SetVertexColor(0, 0, 0, type(g) == "table" and g.shadowAlpha or 0.6)
    st.shapeShadow:ClearAllPoints()
    st.shapeShadow:SetPoint("TOPLEFT", host, "TOPLEFT", -e, e)
    st.shapeShadow:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", e, -e)
    st.shapeShadow:SetShown(L.shadow ~= false)
    st.shapeOuter:SetTexture(file)
    st.shapeOuter:ClearAllPoints()
    st.shapeOuter:SetAllPoints(host)
    st.shapeOuter:SetShown(T > 0)
    st.shapeBand:SetTexture(file)
    st.shapeBand:ClearAllPoints()
    st.shapeBand:SetPoint("TOPLEFT", host, "TOPLEFT", band, -band)
    st.shapeBand:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -band, band)
    -- The warm band of the Daylight look, when there's room for it.
    st.shapeBand:SetShown(L.borderStyle == "daylight" and T >= 3 * band)
    st.shapeBg:SetTexture(file)
    st.shapeBg:ClearAllPoints()
    st.shapeBg:SetPoint("TOPLEFT", host, "TOPLEFT", T, -T)
    st.shapeBg:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -T, T)
    local bg = Style.BACKGROUND
    st.shapeBg:SetVertexColor(bg[1], bg[2], bg[3], Style.BACKGROUND_ALPHA or 1)
    st.shapeHole:SetTexture(shapeFile(name, "hole"), "CLAMPTOWHITE", "CLAMPTOWHITE")
    st.shapeHole:ClearAllPoints()
    st.shapeHole:SetPoint("TOPLEFT", host, "TOPLEFT", T, -T)
    st.shapeHole:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -T, T)
    st.shapeBg:Show()
    for _, cd in ipairs(cds) do
        if cd.SetSwipeTexture then pcall(cd.SetSwipeTexture, cd, file) end
        if cd.SetUseCircularEdge then pcall(cd.SetUseCircularEdge, cd, name == "circle") end
    end
    Skin.PaintShape(st, nil, nil)
    return true
end

-- A Cooldown Manager icon in its look's shape, with the border in its color.
function Skin.ShapeCdm(st, host, s, icon, overlays, cds)
    if type(s) ~= "table" or not icon then return end
    local L = Skin.LookFor("cdm")
    if Skin.Shape(st, host, s, icon, overlays, cds, L) then
        local c = L.borderColor == "accent" and { Style.Accent() } or Skin.BorderOf(L)
        Skin.PaintShape(st, c, nil)
    end
end

-- A shape's border and band colors (nil = the shell's own).
function Skin.PaintShape(st, border, band)
    if not st.shape then return end
    local b, n = border or Style.BORDER, band or Style.BAND
    st.shapeOuter:SetVertexColor(b[1], b[2], b[3], 1)
    st.shapeBand:SetVertexColor(n[1], n[2], n[3], 1)
end
Skin.CROP_BASE = DaylightUI.Style.ICON_CROP
Skin.CROP = Skin.CROP_BASE    -- the Cooldown Manager's, zoom added (Skin.Configure)
Skin.SHADE_FILE = DUI.MEDIA .. "inner-shadow.png"
Skin.SHADE = 0.55            -- inner shadow strength
-- The cooldown sweep: dark and square, over the icon.
Skin.SWIPE_FILE = "Interface\\Buttons\\WHITE8X8"
Skin.SWIPE = { 0, 0, 0, 0.7 }
Skin.DIP = 1                 -- how far a pressed icon sinks in, each side
Skin.HOTKEY = { size = 10, color = { 0.86, 0.82, 0.74 } }   -- warm, a touch brighter than INK.LABEL
Skin.COUNT = 11
Skin.COUNT_COLOR = { 1, 1, 1 }
Skin.NORMAL = { 0, 0, 0 }    -- the border at rest: the shell's own
Skin.OUT_OF_RANGE = 0.4      -- icon opacity while out of range or short of power
Skin.NO_POWER_COLOR = { 0.45, 0.55, 1 }   -- short of power, when out of range is shown by color
Skin.UNUSABLE = { 0.4, 0.4, 0.4 }   -- an action that can't be used now (our own buttons), grayed like the game does
-- The rest of the look comes from the settings (Skin.Configure).
Skin.showKeybind, Skin.showMacro = true, true
Skin.PRESSED = { 0, 0, 0, 0.3 }
Skin.HIGHLIGHT = { 1, 1, 1, 0.12 }
Skin.CHECKED = nil           -- nil = the accent
Skin.CHECKED_ALPHA = 0.3
Skin.PROC = nil              -- nil = the accent
Skin.rangeMode = "fade"      -- or "color"
Skin.RANGE_COLOR = { 0.9, 0.25, 0.22 }
Skin.keybindPos, Skin.countPos = "topright", "bottomright"
Skin.MACRO_SIZE = 9
Skin.MACRO_Y = 2              -- the macro name's distance above the bottom edge, when nudged
Skin.cooldownNumbers, Skin.COOLDOWN_SIZE = true, 14
Skin.shortKeys = false
Skin.tooltips = "always"     -- "nocombat" or "never"

-- Where the keybind and count sit: point, x, y.
Skin.KEYBIND_POS = {
    topright = { "TOPRIGHT", -2, -3 }, topleft = { "TOPLEFT", 3, -3 }, bottom = { "BOTTOM", 0, 3 },
}
Skin.COUNT_POS = { bottomright = { "BOTTOMRIGHT", -2, 3 }, bottomleft = { "BOTTOMLEFT", 3, 3 } }

-- Shorter keybinds: modifiers as one letter, mouse buttons and the number pad as a
-- letter and number.
Skin.SHORT_KEYS = {
    { "Mouse Wheel Up", "WU" }, { "Mouse Wheel Down", "WD" }, { "Middle Mouse", "M3" },
    { "Mouse Button ", "M" }, { "Num Pad ", "N" }, { "Spacebar", "Sp" }, { "Backspace", "Bs" },
    { "Capslock", "Cp" }, { "Page Up", "PU" }, { "Page Down", "PD" }, { "Insert", "INS" }, { "Delete", "DEL" },
    { "SHIFT%-", "S" }, { "CTRL%-", "C" }, { "ALT%-", "A" },
    { "^s%-", "S" }, { "^c%-", "C" }, { "^a%-", "A" }, { "([SCA])s%-", "%1S" }, { "([SCA])c%-", "%1C" },
}

-- The same in the player's language, using the game's own names for these keys
-- (KEY_NUMPAD5 is "5 du pavé num." in French) and modifiers.
Skin.LOCAL_KEYS = {
    NUMPADDIVIDE = "N/", NUMPADMULTIPLY = "N*", NUMPADMINUS = "N-", NUMPADPLUS = "N+",
    NUMPADDECIMAL = "N.", MOUSEWHEELUP = "WU", MOUSEWHEELDOWN = "WD", BUTTON3 = "M3",
    SPACE = "Sp", BACKSPACE = "Bs", CAPSLOCK = "Cp",
    PAGEUP = "PU", PAGEDOWN = "PD", INSERT = "INS", DELETE = "DEL",
}
for i = 0, 9 do Skin.LOCAL_KEYS["NUMPAD" .. i] = "N" .. i end
for i = 4, 31 do Skin.LOCAL_KEYS["BUTTON" .. i] = "M" .. i end
Skin.LOCAL_MODS = { SHIFT_KEY_TEXT = "S", CTRL_KEY_TEXT = "C", ALT_KEY_TEXT = "A" }

local function literal(s) return (string.gsub(s, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end

-- Built once (the names don't change while playing), longest first so "Mouse Button
-- 10" isn't caught by "Mouse Button 1".
local function localRules()
    if Skin.localRules then return Skin.localRules end
    local rules = {}
    for key, short in pairs(Skin.LOCAL_KEYS) do
        local name = _G["KEY_" .. key]
        if type(name) == "string" and name ~= "" then rules[#rules + 1] = { name, short } end
    end
    for global, short in pairs(Skin.LOCAL_MODS) do
        local name = _G[global]
        if type(name) == "string" and name ~= "" then rules[#rules + 1] = { name .. "-", short } end
    end
    table.sort(rules, function(a, b) return #a[1] > #b[1] end)
    for _, r in ipairs(rules) do r[1] = literal(r[1]) end
    Skin.localRules = rules
    return rules
end

function Skin.Shorten(text)
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return text end
    for _, pair in ipairs(localRules()) do text = string.gsub(text, pair[1], pair[2]) end
    for _, pair in ipairs(Skin.SHORT_KEYS) do text = string.gsub(text, pair[1], pair[2]) end
    return text
end

-- A look's text colors and the swipe color, as the settings hold them.
Skin.LOOK_COLORS = { "pressed", "highlight", "checkedColor", "checkedBorderColor", "procColor", "rangeColor", "borderCustom",
    "swipeColor", "edgeColor", "keybindColor", "countColor", "macroColor", "cooldownTextColor" }

-- The look a bar wears: db.look with the bar's own changes on top (key nil or no
-- changes = db.look itself). Cached until the next Configure.
Skin.shared = nil
local looks = {}
function Skin.LookFor(key)
    if not Skin.shared then
        -- Before the first Configure (the bars are built at file load).
        local db = ns.Settings()
        Skin.shared = db and type(db.look) == "table" and db.look or ns.DEFAULTS.look
    end
    local shared = Skin.shared
    if key == nil then return shared end
    local L = looks[key]
    if L then return L end
    if key == "padRound" then
        L = shared
        if not Skin.ShapeOf(shared) then
            L = {}
            for k, v in pairs(shared) do L[k] = v end
            L.shape = "circle"
        end
        looks[key] = L
        return L
    end
    local db = ns.Settings()
    local over = db and type(db.barLooks) == "table" and db.barLooks[key]
    if type(over) ~= "table" or next(over) == nil then
        L = shared
    else
        L = {}
        for k, v in pairs(shared) do L[k] = v end
        for k, v in pairs(over) do
            if shared[k] ~= nil and type(v) == type(shared[k]) then L[k] = v end
        end
    end
    looks[key] = L
    return L
end

-- The icon's crop with the zoom added (zoom = a share of the icon, 0-0.4).
-- aspect = the icon's height over its width when it isn't square: the square art is
-- cut down to that shape around its middle, so it's never stretched.
function Skin.CropOf(L, aspect)
    local c, z = Skin.CROP_BASE, (L and tonumber(L.zoom) or 0) / 2
    local l, r, t, b = c[1] + z, c[2] - z, c[3] + z, c[4] - z
    aspect = tonumber(aspect)
    if aspect and aspect > 0 and aspect ~= 1 then
        if aspect < 1 then
            local mid, half = (t + b) / 2, (b - t) * aspect / 2
            t, b = mid - half, mid + half
        else
            local mid, half = (l + r) / 2, (r - l) / aspect / 2
            l, r = mid - half, mid + half
        end
    end
    return { l, r, t, b }
end

-- Buttons whose height isn't their width (Skin.SetAspect).
local aspectOf = setmetatable({}, { __mode = "k" })

-- The border's color at rest (nil = the shell's own).
function Skin.BorderOf(L)
    local m = L and L.borderColor
    if m == "class" then
        local _, token = UnitClass("player")
        local r, g, b = Style.ClassColor(token)
        return r and { r, g, b } or nil
    elseif m == "custom" then
        return L.borderCustom
    end
    return nil
end

-- Takes the action bar settings (db.look, db.barLooks).
function Skin.Configure(db)
    local look = type(db) == "table" and db.look
    if type(look) ~= "table" then return end
    Skin.shared = look
    for k in pairs(looks) do looks[k] = nil end
    -- The module-wide values: the Cooldown Manager's look.
    local C = Skin.LookFor("cdm")
    Skin.BORDER_PX = Skin.BorderPx(C)
    Skin.HOTKEY.size = C.keybindSize
    Skin.COUNT = C.countSize
    Skin.showKeybind, Skin.showMacro = C.keybind ~= false, C.macroNames ~= false
    local p, h = look.pressed, look.highlight
    Skin.PRESSED = { p[1], p[2], p[3], look.pressedAlpha }
    Skin.HIGHLIGHT = { h[1], h[2], h[3], look.highlightAlpha }
    Skin.DIP = C.dip and 1 or 0
    Skin.CHECKED = C.checked == "custom" and C.checkedColor or nil
    Skin.CHECKED_ALPHA = C.checkedAlpha
    Skin.PROC = look.proc == "custom" and look.procColor or nil
    Skin.rangeMode = C.range
    Skin.RANGE_COLOR = C.rangeColor
    local sc = C.swipeColor
    Skin.SWIPE = { sc[1], sc[2], sc[3], C.cooldownAlpha }
    Skin.CROP = Skin.CropOf(C)
    Skin.keybindPos, Skin.countPos = C.keybindPos, C.countPos
    Skin.MACRO_SIZE = C.macroSize
    Skin.cooldownNumbers, Skin.COOLDOWN_SIZE = C.cooldownNumbers ~= false, C.cooldownSize
    Skin.shortKeys = C.shortKeys == true
    Skin.tooltips = C.tooltips
    Skin.COUNT_COLOR = C.countColor
    Skin.cdmGen = (Skin.cdmGen or 0) + 1     -- the Cooldown Manager holders lay out again (CdmAuras)
    DUI.Fire("ActionButtonLookChanged")      -- other buttons in this look (DUI.ActionButtonLook)
end

-- A Cooldown Manager shell in its look's border style and color.
function Skin.PaintCdmShell(s)
    if type(s) ~= "table" or type(s.opts) ~= "table" then return end
    local L = Skin.LookFor("cdm")
    if Skin.StyleShellOpts(s.opts, L) then Style.LayoutShell(s) end
    if L.borderColor == "accent" then
        Style.LightShell(s)
    else
        Style.SetShellColors(s, Skin.BorderOf(L), nil)
    end
end

-- The keybind: our own label (parts.key) shows the game's text, shortened if set, and
-- the game's own text is invisible and left as the game writes it. No hooks on that
-- text: the game's button code calls its SetText and SetVertexColor from its
-- protected update (every range check), and with a hook on them the call fails
-- ("attempt to call a nil value"). Instead it's copied over the frame after the
-- events that change it, and by the watcher. An unbound button gets the game's range
-- dot instead, which our font has no glyph for (it draws a box), so it's blanked.
function Skin.UpdateKey(btn)
    if Skin.IsPad(btn) then return end     -- the game's button picture shows it
    local parts, hk = Skin.GetParts(btn), btn.HotKey
    if not (parts and parts.key and type(hk) == "table" and hk.GetText) then return end
    local raw = hk:GetText() or ""
    -- The slow pass asks every 0.2 s, so only re-shorten when the game's text or the
    -- short-names setting changed (Shorten runs 30+ gsubs).
    local short = parts.L.shortKeys == true
    if raw == parts.rawKey and parts.rawShort == short and parts.keyText ~= nil then return end
    parts.rawKey, parts.rawShort = raw, short
    local text = raw
    if text == (RANGE_INDICATOR or "●") then
        text = ""
    elseif short then
        text = Skin.Shorten(text)
    end
    if parts.keyText ~= text then
        parts.keyText = text
        parts.key:SetText(text)
    end
end
-- The backing's color per state; nothing special keeps it black.
Skin.STATE = {
    proc = {},               -- the accent, filled in when skinning
    lit = {},                -- Border color "accent": marks a lit border (Style.LightShell)
}

local skinned = setmetatable({}, { __mode = "k" })
local dragging = false
local hovered                  -- the skinned button under the mouse (its OnEnter/OnLeave)
local others = {}              -- the game's buttons we dress (not our own), in skin order

-- A button whose height isn't its width (an action bar's Button height). Its icon
-- is cropped to that shape; a change redoes the look.
function Skin.SetAspect(btn, aspect)
    if aspect == 1 then aspect = nil end
    if aspectOf[btn] == aspect then return end
    aspectOf[btn] = aspect
    if skinned[btn] then Skin.Apply(btn) end
end
function Skin.AspectOf(btn) return aspectOf[btn] end

local function styleText(fs, size)
    Style.DressText(fs, size, { slot = ns.MEDIA.font })
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

-- The slot a button shows. Our own buttons keep it in their "action" attribute (bar
-- 1's changes with the page), the game's in a field.
local function actionOf(btn)
    local a = btn.GetAttribute and btn:GetAttribute("action")
    if type(a) == "number" then return a end
    a = btn.action
    if type(a) == "number" then return a end
end

local petButtons = setmetatable({}, { __mode = "k" })
-- The game's controller buttons (PadSkin.lua).
local padButtons = setmetatable({}, { __mode = "k" })
function Skin.IsPad(btn) return padButtons[btn] == true end
-- The picture on a controller button with no action of its own (Interact, Back,
-- Jump: the top bar's face buttons), when it shows one.
local function specialOf(btn)
    local tex = padButtons[btn] and btn.SpecialActionIcon
    if tex and tex:IsShown() then return tex end
end
function Skin.SetPet(btn) petButtons[btn] = true end

-- Which bar a button is on (Bars.DEFS key), for its look; none means the shared one.
local barOf = setmetatable({}, { __mode = "k" })
function Skin.SetBar(btn, key) barOf[btn] = key end

-- Our own buttons. Nothing of the game's grays them, so the skin does
-- (Skin.UpdateState).
local ownButtons = setmetatable({}, { __mode = "k" })
function Skin.SetOwn(btn) ownButtons[btn] = true end
-- A controller button gets the bars' shared look, round where the game's is (the
-- face buttons) unless every button already has a shape.
function Skin.SetPad(btn, round)
    padButtons[btn] = true
    barOf[btn] = round and "padRound" or nil
end

-- a = the button's slot when the caller already has it.
local function hasAction(btn, a)
    if specialOf(btn) then return true end
    if petButtons[btn] and btn.GetID then
        return call(GetPetActionInfo, btn:GetID()) ~= nil
    end
    a = a or actionOf(btn)
    if not a then return true end
    local has = call(HasAction, a)
    if has == nil and C_ActionBar then has = call(C_ActionBar.HasAction, a) end
    return has ~= false
end

-- A button's icon. A game button that uses our own icon (the leave button's arrow)
-- passes it through Skin.SetIcon, since a field on it would mark the game's frame
-- (/dui taint).
local ownIcon = setmetatable({}, { __mode = "k" })
function Skin.SetIcon(btn, icon) ownIcon[btn] = icon end
function Skin.IconOf(btn) return ownIcon[btn] or btn.icon or btn.Icon end
local iconOf = Skin.IconOf

-- Places the icon inside the border, a little further in while pressed. The inner
-- shadow follows it.
local function placeIcon(btn, parts)
    local icon = iconOf(btn)
    if not icon then return end
    local L = parts.L
    local T = Pixel.Px(btn, Skin.BorderPx(L))
    if (parts.pressed or parts.keyDown) and L.dip then T = T + Pixel.Px(btn, 1) end
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", T, -T)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -T, T)
    parts.shade:ClearAllPoints()
    parts.shade:SetAllPoints(icon)
end

-- On release the icon (and its shading, since a Scale animation is visual only and
-- the shade needs its own) springs back from the dip instead of snapping. Textures
-- only, never the protected button, so it runs in combat.
local function spring(btn, parts)
    if not parts.L.dip then return end
    local icon = iconOf(btn)
    if icon then DUI.Motion.Bump(icon, 0.94, DUI.Motion.FAST) end
    DUI.Motion.Bump(parts.shade, 0.94, DUI.Motion.FAST)
end

-- ---------------------------------------------------------------------
-- State: empty slots and the backing's color
-- ---------------------------------------------------------------------

-- With "hide empty" on, an empty slot vanishes unless something is being dragged
-- onto the bars. Alpha only, since the buttons are protected.
Skin.hideEmpty = true
Skin.EMPTY_ALPHA = 0.45      -- a shown empty slot's backing is see-through; its keybind stays solid

-- Every change fades FAST from our own last-written alphas (never read back):
-- something picked up or dropped (Skin.SetDragging), bar 1's paging (a stance or
-- form, via the icon painter), a refresh. Asked again for the goal it's already
-- heading to, it just continues. snap = a fresh skin (Apply) or motion off, so it's
-- instant. The icon itself is set instantly by the icon painter; only the empty
-- backing, keybind and highlight ease.
local function emptyAlphas(parts, back, key, hl, hlTex)
    parts.eB, parts.eK, parts.eH = back, key, hl
    parts.back:SetAlpha(back)
    if parts.key then parts.key:SetAlpha(key) end
    if hlTex then hlTex:SetAlpha(hl) end
end

-- One step function per button that reads its fade's ends off parts, so there's no
-- table or closure per call (the icon painter asks on every page change).
local function emptyStepper(parts)
    parts.emptyStep = function(p)
        emptyAlphas(parts, parts.e0B + (parts.egB - parts.e0B) * p, parts.e0K + (parts.egK - parts.e0K) * p,
            parts.e0H + (parts.egH - parts.e0H) * p, parts.eHl)
    end
    parts.emptyDone = function() parts.emptyEasing = nil end
    parts.emptyKey = {}
end

function Skin.UpdateEmpty(btn, snap)
    local parts = skinned[btn]
    if not parts then return end
    local empty = not dragging and not hasAction(btn)
    -- A controller's crosses keep their shape, since those buttons are always there.
    local hidden = empty and Skin.hideEmpty and not padButtons[btn]
    local back = hidden and 0 or empty and Skin.EMPTY_ALPHA or 1
    local key = (hidden or parts.L.keybind == false) and 0 or 1
    local hl = hidden and 0 or 1
    -- The edge shading is meant for an icon; on an empty slot it would draw a hard
    -- ring inside the soft backing.
    Skin.UpdateRange(btn)
    local hlTex = btn:GetHighlightTexture()
    if not parts.emptyStep then emptyStepper(parts) end
    local same = parts.egB == back and parts.egK == key and parts.egH == hl
    if same and parts.emptyEasing and not snap then return end    -- already on its way there
    parts.egB, parts.egK, parts.egH, parts.eHl = back, key, hl, hlTex
    if not snap and not same and parts.eB ~= nil and DUI.Motion.On() then
        parts.e0B, parts.e0K, parts.e0H = parts.eB, parts.eK, parts.eH
        parts.emptyEasing = true
        DUI.Motion.Tween(parts.emptyKey, 0, 1, DUI.Motion.FAST, parts.emptyStep, parts.emptyDone)
    else
        parts.emptyEasing = nil
        DUI.Motion.Tween(parts.emptyKey, 0, 0, 0)   -- ends a fade in progress
        emptyAlphas(parts, back, key, hl, hlTex)
    end
end

-- Out of range, or short of rage, mana or energy, the icon (and its edge shading)
-- fades the same either way. Set to color instead, it's tinted: out of range in its
-- color, short of power blue. The keybind keeps our white, undoing the game's red,
-- and when fading the icon drops the game's blue no-power tint.
-- The change glides FAST from our own last-written values (never read back from the
-- icon). It snaps with motion off, on a fresh skin (Skin.Apply), and for an empty
-- slot. A color is only written while it's ours, since the game grays its own stance
-- and pet buttons.
local WHITE = { 1, 1, 1 }

local function tintGoal(parts)
    -- On a real cooldown: the look's "Opacity on cooldown".
    local cd = parts.cooling and parts.L.cdAlpha or 1
    if parts.formOff then cd = cd * Skin.FORM_OFF end
    if parts.L.range == "color" then
        return cd, parts.outOfRange and parts.L.rangeColor or parts.noPower and Skin.NO_POWER_COLOR
            or parts.unusable and Skin.UNUSABLE or nil
    end
    local off = parts.outOfRange or parts.noPower
    local a = (off and Skin.OUT_OF_RANGE or 1) * cd
    if parts.unusable and not off then return a, Skin.UNUSABLE end
    if parts.noPower then return a, WHITE end      -- undo the game's blue for no power
    return a, nil
end

-- r nil = no color of ours (one we had goes back to white, once).
local function setTint(btn, parts, a, r, g, b, shadeOn)
    local icon = iconOf(btn)
    if icon then
        if icon.SetVertexColor then
            if r then icon:SetVertexColor(r, g, b)
            elseif parts.tintR then icon:SetVertexColor(1, 1, 1) end
        end
        if not specialOf(btn) then icon:SetAlpha(a) end    -- the game keeps that one at 0
    end
    parts.shade:SetAlpha(shadeOn and a or 0)
    parts.tintA, parts.tintR, parts.tintG, parts.tintB = a, r, g, b
end

local function lerp(x, y, p) return x + (y - x) * p end

-- has = whether the slot holds anything, when the caller already checked.
function Skin.UpdateRange(btn, has)
    local parts = skinned[btn]
    if not parts then return end
    local a, col = tintGoal(parts)
    local r, g, b = col and col[1], col and col[2], col and col[3]
    local shadeOn
    if has ~= nil then shadeOn = has else shadeOn = hasAction(btn) end
    local same = parts.gA == a and parts.gR == r and parts.gG == g and parts.gB == b
    -- Our own buttons already at this goal need no write (every usable and range
    -- pass asks). Nothing of the game's writes their icon, but the game's buttons
    -- we dress still get ours reapplied over its writes.
    if same and shadeOn == parts.gShade and ownButtons[btn] and not parts.tweening
        and not parts.snapTint and parts.tintA ~= nil then return end
    parts.gA, parts.gR, parts.gG, parts.gB, parts.gShade = a, r, g, b, shadeOn
    -- Already gliding there (an emptied slot or a fresh skin still snaps).
    if same and parts.tweening and shadeOn and not parts.snapTint then return end
    local snap = parts.snapTint or parts.tintA == nil or not shadeOn or not DUI.Motion.On()
    parts.snapTint = nil
    if snap or same then
        if parts.tweening then
            parts.tweening = nil
            DUI.Motion.Tween(parts, 0, 0, 0)               -- stop the glide
        end
        setTint(btn, parts, a, r, g, b, shadeOn)
        return
    end
    local a0, r0, g0, b0 = parts.tintA, parts.tintR or 1, parts.tintG or 1, parts.tintB or 1
    local colour = r ~= nil or parts.tintR ~= nil
    local r1, g1, b1 = r or 1, g or 1, b or 1
    parts.tweening = true
    DUI.Motion.Tween(parts, 0, 1, DUI.Motion.FAST, function(p)
        if colour then
            setTint(btn, parts, lerp(a0, a, p), lerp(r0, r1, p), lerp(g0, g1, p), lerp(b0, b1, p), shadeOn)
        else
            setTint(btn, parts, lerp(a0, a, p), nil, nil, nil, shadeOn)
        end
    end, function()
        parts.tweening = nil
        setTint(btn, parts, a, r, g, b, shadeOn)
    end)
end

-- The border: the accent on a proc, else the shell's own. Short of power, the icon
-- fades as it does out of range (Skin.UpdateRange). a, usable and noMana are the
-- slot and IsUsableAction's answer, when the caller (the Buttons painter) already
-- has them.
function Skin.UpdateState(btn, a, usable, noMana)
    local parts = skinned[btn]
    if not parts then return end
    if a == nil then
        a = actionOf(btn)
        usable, noMana = call(IsUsableAction, a)
    end
    if noMana == nil and a and C_ActionBar then usable, noMana = call(C_ActionBar.IsUsableAction, a) end
    local has = hasAction(btn, a)
    parts.noPower = noMana == true
    parts.unusable = ownButtons[btn] == true and usable == false and noMana ~= true and has
    Skin.UpdateRange(btn, has)
    Skin.PaintBorder(btn, parts)
end

-- The spell on one of our buttons that's queued or being cast (Heroic Strike waiting
-- for the swing), from the Buttons "checked" painter. Attacks and auto-repeat have
-- their own blink and run all fight, so they don't count.
local activeOf = setmetatable({}, { __mode = "k" })

-- The border's color right now: a proc first, then pressed or hovered (Light border
-- when pressed / on mouseover), then your current stance or an active spell (Light
-- the border on an active spell), else its own resting color (Border color), else
-- the shell's. Into and out of a lit press or hover it glides FAST; everything else
-- snaps.
local function paintColor(parts, color)
    if parts.shape then
        local c = color ~= Skin.NORMAL and (color == Skin.STATE.lit and { Style.Accent() } or color) or nil
        local band = c and color ~= parts.rest and { c[1] * 0.45, c[2] * 0.45, c[3] * 0.45 } or nil
        Skin.PaintShape(parts, c, band)
        return
    end
    if color == Skin.NORMAL then
        Style.SetShellColors(parts.back, nil, nil)
    elseif color == Skin.STATE.lit then
        Style.LightShell(parts.back)
    elseif color == parts.rest then
        Style.SetShellColors(parts.back, color, nil)
    else
        Style.SetShellColors(parts.back, color, { color[1] * 0.45, color[2] * 0.45, color[3] * 0.45 })
    end
end
-- The plain color a state shows as (for the glide's ends).
local function plainOf(color)
    if color == Skin.NORMAL then return Style.BORDER end
    if color == Skin.STATE.lit then return { Style.Accent() } end
    return color
end
function Skin.PaintBorder(btn, parts)
    local L, color, lit = parts.L, nil, false
    if parts.proc then
        color = parts.procColor
    elseif (parts.pressed or parts.keyDown) and L.pressBorder then
        color, lit = parts.pressLit, true
    elseif parts.hover and L.hoverBorder then
        color, lit = parts.hoverLit, true
    elseif parts.formOn then
        color, lit = L.checked == "custom" and L.checkedColor or Skin.STATE.lit, true
    elseif L.checkedBorder and activeOf[btn] then
        color, lit = parts.activeLit, true
    end
    color = color or (L.borderColor == "accent" and Skin.STATE.lit) or parts.rest or Skin.NORMAL
    if parts.color == color then return end
    local was, wasLit = parts.color, parts.lit
    parts.color, parts.lit = color, lit
    if was == nil or not (lit or wasLit) or not DUI.Motion.On() then
        DUI.Motion.Tween(parts.back, 0, 0, 0)          -- stop a glide
        paintColor(parts, color)
        return
    end
    local a, b = plainOf(was), plainOf(color)
    DUI.Motion.Tween(parts.back, 0, 1, DUI.Motion.FAST, function(p)
        local c = { lerp(a[1], b[1], p), lerp(a[2], b[2], p), lerp(a[3], b[3], p) }
        local band = { c[1] * 0.45, c[2] * 0.45, c[3] * 0.45 }
        if parts.shape then Skin.PaintShape(parts, c, band) else Style.SetShellColors(parts.back, c, band) end
    end, function() paintColor(parts, color) end)
end

-- An active spell's border and glow, as the look says.
function Skin.PaintActive(btn, parts)
    Skin.PaintBorder(btn, parts)
    local Fx, L = ns.CdmEffects, parts.L
    if not Fx then return end
    Fx.SetGlow(btn, L.checkedGlow == true and activeOf[btn] == true,
        L.checkedBorderMode ~= "accent" and parts.activeLit or nil)
end

function Skin.SetActive(btn, on)
    on = on == true or nil
    if activeOf[btn] == on then return end
    activeOf[btn] = on
    local parts = skinned[btn]
    if parts then Skin.PaintActive(btn, parts) end
end

-- A color by its mode: the accent, your class color, or the setting's own.
function Skin.ModeColor(mode, own)
    if mode == "accent" then return { Style.Accent() } end
    if mode == "class" then
        local _, token = UnitClass("player")
        local r, g, b = Style.ClassColor(token)
        if r then return { r, g, b } end
        return { Style.Accent() }
    end
    return own
end

function Skin.GetParts(btn) return skinned[btn] end

-- A real cooldown (not the global one) started or ended on one of our buttons
-- (tracked by Ping.lua, plain in combat too). The icon grays and dims as the look
-- says, gliding FAST.
function Skin.SetCooling(btn, on)
    local parts = skinned[btn]
    if not parts then return end
    on = on == true
    if parts.cooling == on then return end
    parts.cooling = on
    Skin.UpdateRange(btn)
    Skin.PaintGray(btn, parts)
end

function Skin.PaintGray(btn, parts)
    local icon = iconOf(btn)
    if not (icon and icon.SetDesaturation) then return end
    local goal = ((parts.cooling and parts.L.cdGray) or parts.formOff) and 1 or 0
    if parts.gray == goal then return end
    local from = parts.gray or 0
    parts.gray = goal
    parts.grayKey = parts.grayKey or {}
    DUI.Motion.Tween(parts.grayKey, from, goal, DUI.Motion.FAST, function(v) icon:SetDesaturation(v) end)
end

-- The stance bar (stances, forms, auras, aspects): the one you're in gets a lit
-- border in the "Active spell" color and the others go gray and dim, so a glance
-- tells them apart even at the bar's small size. In no form at all nothing dims, so
-- a druid in caster form still sees every form in color. It all glides FAST through
-- the border and tint above. Only the game's buttons' textures and our shell are
-- touched, so it works in a fight too.
Skin.FORM_OFF = 0.5
local function formActive(btn)
    local _, on = call(GetShapeshiftFormInfo, btn:GetID())
    if issecretvalue and issecretvalue(on) then return nil, true end
    return on and true or false
end
function Skin.UpdateForms()
    local any = false
    for _, btn in ipairs(others) do
        if barOf[btn] == "stance" then
            local on, unknown = formActive(btn)
            if unknown then return end        -- can't be read, so the last answer stays
            any = any or on
        end
    end
    for _, btn in ipairs(others) do
        if barOf[btn] == "stance" then
            local parts, on = skinned[btn], formActive(btn)
            local off = any and not on
            if parts.formOn ~= on or parts.formOff ~= off then
                parts.formOn, parts.formOff = on, off
                Skin.UpdateRange(btn)
                Skin.PaintGray(btn, parts)
                Skin.PaintBorder(btn, parts)
            end
        end
    end
end

-- A key bound to the button is down (Keys.lua): the pressed tint and the dip.
function Skin.SetKeyDown(btn, on)
    local parts = skinned[btn]
    if not parts then return end
    on = on == true
    if parts.keyDown == on then return end
    parts.keyDown = on
    placeIcon(btn, parts)
    if parts.L.pressBorder then Skin.PaintBorder(btn, parts) end
    if not on and not parts.pressed then spring(btn, parts) end
    parts.press:SetAlpha(on and 1 or 0)
end

function Skin.SetDragging(on)
    on = on == true
    -- Every cursor change asks (a new icon on it, a spell picked up again).
    if dragging == on then return end
    dragging = on
    for btn in pairs(skinned) do Skin.UpdateEmpty(btn) end
end

-- ---------------------------------------------------------------------
-- Skinning
-- ---------------------------------------------------------------------

-- The hover wash in the button's look, over its icon. Separate for a button whose
-- highlight the game rewrites (the leave-vehicle button).
function Skin.PaintHighlight(btn)
    local parts, hl = skinned[btn], btn:GetHighlightTexture()
    if not (parts and hl) then return hl end
    local L, icon = parts.L, iconOf(btn)
    local c = L.highlight
    hl:SetColorTexture(c[1], c[2], c[3], L.highlightAlpha)
    hl:ClearAllPoints()
    if icon then hl:SetAllPoints(icon) end
    return hl
end

-- The hover, pressed and checked washes over the icon. Returns those textures.
local function paintWashes(btn, L, icon)
    local hl = Skin.PaintHighlight(btn)
    local pc = L.pressed
    local pushed = btn:GetPushedTexture()
    if pushed then
        pushed:SetColorTexture(pc[1], pc[2], pc[3], L.pressedAlpha)
        if icon then pushed:SetAllPoints(icon) end
    end
    local checked = btn.GetCheckedTexture and btn:GetCheckedTexture() or nil
    if checked then
        local r, g, b = Style.Accent()
        local c = L.checked == "custom" and L.checkedColor or { r, g, b }
        checked:SetColorTexture(c[1], c[2], c[3], L.checkedAlpha)
        if icon then checked:SetAllPoints(icon) end
    end
    return hl, pushed, checked
end

-- The game rewrote a controller button's art (PadSkin.lua), so put ours back over it
-- in the same call. down = whether it's held now, when the game just said.
function Skin.Redress(btn, down)
    local parts = skinned[btn]
    if not parts then return end
    Skin.Hide(btn)
    paintWashes(btn, parts.L, iconOf(btn))
    if type(btn.cooldown) == "table" then Skin.StyleSwipe(btn.cooldown, parts.L) end
    if down ~= nil then Skin.SetKeyDown(btn, down) end
end

function Skin.Apply(btn)
    local parts = skinned[btn]
    local L = Skin.LookFor(barOf[btn])
    if not parts then
        parts = { L = L }
        skinned[btn] = parts
        if not ownButtons[btn] then others[#others + 1] = btn end
        -- The shell (border, background, shadow) is the button's backing. Its alpha
        -- hides an empty slot and its border color marks a proc. Its thickness
        -- comes from the button's own look.
        local opts = Skin.ShellOpts()
        opts.borderPx = function() return Skin.BorderPx(parts.L) end
        Skin.StyleShellOpts(opts, L)
        parts.opts = opts
        parts.back = Style.Shell(btn, opts)
        parts.shade = btn:CreateTexture(nil, "ARTWORK", nil, 3)
        parts.shade:SetTexture(Skin.SHADE_FILE)
        parts.shade:SetVertexColor(0, 0, 0, Skin.SHADE)
        -- The pressed look for a key (Skin.SetKeyDown). Our buttons' keys press the
        -- game's hidden buttons, so ours never enters its own pushed state.
        parts.press = btn:CreateTexture(nil, "OVERLAY", nil, 1)
        parts.press:SetAlpha(0)
        -- Our keybind label (Skin.UpdateKey), where the game's text sits. The
        -- game's is made invisible so its range tint never shows.
        local over = btn.TextOverlayContainer
        if not (type(over) == "table" and over.CreateFontString) then over = btn end
        parts.key = over:CreateFontString(nil, "OVERLAY")
        if type(btn.HotKey) == "table" and btn.HotKey.SetAlpha then btn.HotKey:SetAlpha(0) end
        -- The game's own mask rounds the icon's corners for its art. Without it the
        -- icon is square in the border. The controller buttons' two masks too, left
        -- on the game's special icons.
        local icon = iconOf(btn)
        for _, key in ipairs(Skin.ICON_MASKS) do
            local m = btn[key]
            if icon and type(m) == "table" then pcall(icon.RemoveMaskTexture, icon, m) end
        end
        -- No hooks on the button's own functions (Update, UpdateButtonArt,
        -- SetButtonState...): they taint the game's button code, which then errors
        -- on secret cooldown and charge values. The game's redraws are followed from
        -- events (Skin.Wire) and a watcher (Skin.Tick) instead.
        -- Tooltips: out of combat only, or never, when set to. Hidden by alpha,
        -- since hiding the game's tooltip from here runs its hide handlers under
        -- our taint.
        btn:HookScript("OnEnter", function()
            hovered = btn
            parts.hover = true
            if parts.L.hoverBorder then Skin.PaintBorder(btn, parts) end
            local mode = parts.L.tooltips
            if mode == "never" or (mode == "nocombat" and InCombatLockdown()) then
                GameTooltip:SetAlpha(0)
                parts.mutedTip = true
            end
        end)
        -- Skipped by a full refresh while hidden, so redo it when it shows.
        btn:HookScript("OnShow", function()
            if parts.redoStale then Skin.RedoSoon(btn) end
        end)
        btn:HookScript("OnLeave", function()
            if hovered == btn then hovered = nil end
            parts.hover = nil
            if parts.L.hoverBorder or parts.lit then Skin.PaintBorder(btn, parts) end
            if parts.mutedTip then
                parts.mutedTip = nil
                GameTooltip:SetAlpha(1)
            end
        end)
    else
        parts.L = L
        Skin.StyleShellOpts(parts.opts, L)
        -- Again, since the border may have another thickness or style now.
        Style.Shell(btn)
    end
    local r, g, b = Style.Accent()
    local proc = Skin.PROC or { r, g, b }
    Skin.STATE.proc[1], Skin.STATE.proc[2], Skin.STATE.proc[3] = proc[1], proc[2], proc[3]
    parts.procColor = L.proc == "custom" and L.procColor or Skin.STATE.proc
    parts.rest = Skin.BorderOf(L)
    parts.hoverLit = Skin.ModeColor(L.hoverBorderMode, L.hoverBorderColor)
    parts.pressLit = Skin.ModeColor(L.pressBorderMode, L.pressBorderColor)
    parts.activeLit = L.checkedBorderMode == "accent" and Skin.STATE.lit
        or Skin.ModeColor(L.checkedBorderMode, L.checkedBorderColor)
    parts.color = nil        -- the proc and border colors may have changed, so set again
    Skin.Hide(btn)
    placeIcon(btn, parts)
    local icon = iconOf(btn)
    if icon then
        local c = Skin.CropOf(L, aspectOf[btn])
        icon:SetTexCoord(c[1], c[2], c[3], c[4])
        local cd = btn.cooldown or btn.Cooldown
        if type(cd) == "table" and cd.SetAllPoints then
            cd:ClearAllPoints()
            cd:SetAllPoints(icon)
            Skin.StyleCooldown(cd, L)
        end
    end
    local key = parts.key
    styleText(key, L.keybindSize)
    local c = L.keybindColor
    key:SetTextColor(c[1], c[2], c[3])
    -- Keybind tucked into the icon's top-right corner, count in the bottom-right.
    local at = Skin.KEYBIND_POS[L.keybindPos] or Skin.KEYBIND_POS.topright
    key:ClearAllPoints()
    key:SetPoint(at[1], btn, at[1], at[2] + L.keybindX, at[3] + L.keybindY)
    key:SetJustifyH(at[1] == "TOPLEFT" and "LEFT" or at[1] == "BOTTOM" and "CENTER" or "RIGHT")
    parts.keyText = nil
    Skin.UpdateKey(btn)
    styleText(btn.Count, L.countSize)
    if type(btn.Count) == "table" and btn.Count.SetPoint then
        local at = Skin.COUNT_POS[L.countPos] or Skin.COUNT_POS.bottomright
        btn.Count:ClearAllPoints()
        btn.Count:SetPoint(at[1], btn, at[1], at[2] + L.countX, at[3] + L.countY)
        local cc = L.countColor
        btn.Count:SetTextColor(cc[1], cc[2], cc[3])
    end
    styleText(btn.Name, L.macroSize)
    if type(btn.Name) == "table" and btn.Name.SetAlpha then
        btn.Name:SetAlpha(L.macroNames ~= false and 1 or 0)
        -- Only moved when nudged; otherwise the template's own spot stays.
        if L.macroX ~= 0 or L.macroY ~= 0 or parts.nameMoved then
            parts.nameMoved = true
            btn.Name:ClearAllPoints()
            btn.Name:SetPoint("BOTTOM", btn, "BOTTOM", L.macroX, Skin.MACRO_Y + L.macroY)
        end
        local mc = L.macroColor
        btn.Name:SetTextColor(mc[1], mc[2], mc[3])
    end
    local hl, pushed, checked = paintWashes(btn, L, icon)
    local pc = L.pressed
    parts.press:SetColorTexture(pc[1], pc[2], pc[3], L.pressedAlpha)
    parts.press:ClearAllPoints()
    if icon then parts.press:SetAllPoints(icon) end
    local overlays = { parts.shade, parts.press, hl, pushed, checked }
    local cds = {}
    for _, k in ipairs({ "cooldown", "chargeCooldown", "lossOfControlCooldown" }) do
        if type(btn[k]) == "table" and btn[k].SetSwipeTexture then cds[#cds + 1] = btn[k] end
    end
    if icon then Skin.Shape(parts, btn, parts.back, icon, overlays, cds, L) end
    Skin.PaintGray(btn, parts)
    parts.snapTint = true        -- a fresh skin (first paint, a re-layout), no glide
    Skin.UpdateEmpty(btn, true)
    Skin.UpdateState(btn)
    Skin.PaintActive(btn, parts)
end

-- A square cooldown sweep in the look's shade, without the bright flash when it ends,
-- plus the edge line when the look has one. L = the look (else the Cooldown
-- Manager's).
function Skin.StyleCooldown(cd, L)
    if type(cd) ~= "table" then return end
    L = L or Skin.LookFor("cdm")
    Skin.StyleSwipe(cd, L)
    -- The game's countdown numbers: on or off, in our font at their size and color.
    if cd.SetHideCountdownNumbers then pcall(cd.SetHideCountdownNumbers, cd, L.cooldownNumbers == false) end
    local fs = cd.GetCountdownFontString and cd:GetCountdownFontString()
    if type(fs) == "table" and fs.SetFont then
        pcall(fs.SetFont, fs, Style.FONT, L.cooldownSize, Style.Outline())
        local tc = L.cooldownTextColor
        if fs.SetTextColor then pcall(fs.SetTextColor, fs, tc[1], tc[2], tc[3]) end
        Skin.PlaceCountdown(cd, L)
    end
end

-- The countdown numbers in the middle, nudged.
function Skin.PlaceCountdown(cd, L)
    L = L or Skin.LookFor("cdm")
    local fs = cd.GetCountdownFontString and cd:GetCountdownFontString()
    if type(fs) ~= "table" or not fs.SetPoint then return end
    fs:ClearAllPoints()
    fs:SetPoint("CENTER", cd, "CENTER", L.cooldownX, L.cooldownY)
end

-- Just the sweep: its texture, shade color and edge line.
function Skin.StyleSwipe(cd, L)
    L = L or Skin.LookFor("cdm")
    local shape = Skin.ShapeOf(L)
    if cd.SetSwipeTexture then pcall(cd.SetSwipeTexture, cd, shape and shapeFile(shape) or Skin.SWIPE_FILE) end
    local c = L.swipeColor
    if cd.SetSwipeColor then pcall(cd.SetSwipeColor, cd, c[1], c[2], c[3], L.cooldownAlpha) end
    if cd.SetDrawBling then pcall(cd.SetDrawBling, cd, false) end
    local edge = Skin.EdgeOf(L)
    if cd.SetDrawEdge then pcall(cd.SetDrawEdge, cd, edge ~= nil) end
    if edge and cd.SetEdgeColor then pcall(cd.SetEdgeColor, cd, edge[1], edge[2], edge[3], 1) end
end

-- The cooldown edge's color (nil = no edge line).
function Skin.EdgeOf(L)
    local m = L and L.edge
    if m == "accent" then return { Style.Accent() } end
    if m == "class" then
        local _, token = UnitClass("player")
        local r, g, b = Style.ClassColor(token)
        if r then return { r, g, b } end
        return { Style.Accent() }
    end
    if m == "custom" then return L.edgeColor end
    return nil
end

function Skin.Hide(btn)
    local nt = btn:GetNormalTexture()
    if nt then nt:SetAlpha(0) end
    for _, key in ipairs(Skin.ART) do
        local r = btn[key]
        if type(r) == "table" and r.SetAlpha then r:SetAlpha(0) end
    end
end

function Skin.IsSkinned(btn) return skinned[btn] ~= nil end

-- ---------------------------------------------------------------------
-- Events the buttons' own updates don't cover
-- ---------------------------------------------------------------------

-- A proc: the game's alert is up on the button (its own frame, read only).
local function procShown(btn)
    local alert = btn.SpellActivationAlert or btn.overlay
    return type(alert) == "table" and alert.IsShown ~= nil and alert:IsShown() == true
end

local procOn = setmetatable({}, { __mode = "k" })   -- buttons whose border shows a proc

-- Rechecks one button's proc. Also called by the Buttons painter right after it
-- shows or hides the game's alert on one of ours.
function Skin.UpdateProc(btn)
    local parts = skinned[btn]
    if not parts then return end
    local on = procShown(btn)
    if parts.proc ~= on then
        parts.proc = on
        procOn[btn] = on or nil
        Skin.UpdateState(btn)
    end
end

local function refreshProcs()
    for btn in pairs(skinned) do Skin.UpdateProc(btn) end
end

-- Redo everything on the next frame, since the game's own handlers for the same
-- event may run after ours and redraw its art, keybind and colors. A usable event
-- only redoes the game's buttons we dress (Buttons' usable painter does our own),
-- and a proc event only the procs.
local queueRangeTouched
local want = { full = false, usable = false, procs = false }
local function redo(btn)
    Skin.Hide(btn)
    Skin.UpdateKey(btn)
    Skin.UpdateEmpty(btn)
    Skin.UpdateState(btn)
end
local function refreshAfter()
    local full, usable, procs = want.full, want.usable, want.procs
    want.full, want.usable, want.procs = false, false, false
    if full then
        -- Only visible buttons (bars 5-8 start hidden, a stance or pet bar may be
        -- empty). A hidden one is marked and redone when it shows.
        for btn, parts in pairs(skinned) do
            if btn:IsVisible() then
                parts.redoStale = nil
                redo(btn)
            else
                parts.redoStale = true
            end
        end
        Skin.UpdateForms()
    elseif usable then
        -- Runs on every cast and power tick; a hidden one is redone when it shows.
        for _, btn in ipairs(others) do
            if btn:IsVisible() then redo(btn) else skinned[btn].redoStale = true end
        end
    end
    if full or procs then refreshProcs() end
end

-- Buttons a full refresh skipped while hidden and that are now shown. Redone on the
-- next frame, since the game's own OnShow may redraw its art first.
local staleShown, staleQueued = {}, false
local function redoStale()
    staleQueued = false
    for btn in pairs(staleShown) do
        staleShown[btn] = nil
        local parts = skinned[btn]
        if parts and parts.redoStale then
            parts.redoStale = nil
            redo(btn)
        end
    end
end
function Skin.RedoSoon(btn)
    staleShown[btn] = true
    if staleQueued then return end
    staleQueued = true
    C_Timer.After(0, function() DUI.SafeCall(redoStale) end)
end

-- Buttons a range event touched: their art and key restored on the next frame.
local rangeTouched, rangeQueued = {}, false
local function redoTouched()
    rangeQueued = false
    for btn in pairs(rangeTouched) do
        rangeTouched[btn] = nil
        Skin.Hide(btn)
        Skin.UpdateKey(btn)
    end
end
queueRangeTouched = function()
    if rangeQueued then return end
    rangeQueued = true
    C_Timer.After(0, function() DUI.SafeCall(redoTouched) end)
end

local afterQueued = false
-- kind = "usable", "procs", or nil for everything.
function Skin.QueueRefresh(kind)
    want[kind or "full"] = true
    if afterQueued then return end
    afterQueued = true
    C_Timer.After(0, function()
        afterQueued = false
        DUI.SafeCall(refreshAfter)
    end)
end

-- The watcher: whether a button is held down by a click, for the icon's dip (keys go
-- through Skin.SetKeyDown), and every so often, art the game showed again and procs
-- that ended (the alert fades out after the event). While a mouse button is down
-- only the button under the mouse is checked (a click presses that one), plus any
-- still showing pressed until released (the mouse may be up or elsewhere by then).
-- That way holding a mouse button to turn the camera doesn't check 100 buttons every
-- frame.
Skin.SLOW_EVERY = 0.2
local slowIn = 0
local held = setmetatable({}, { __mode = "k" })   -- buttons showing pressed
local function mouseDown()
    if type(IsMouseButtonDown) ~= "function" then return true end   -- can't tell, so check every frame
    return IsMouseButtonDown() == true
end
local function watchPress(btn, parts)
    local pressed = btn.GetButtonState ~= nil and btn:GetButtonState() == "PUSHED"
    if parts.pressed ~= pressed then
        parts.pressed = pressed
        held[btn] = pressed or nil
        placeIcon(btn, parts)
        if not pressed and not parts.keyDown then spring(btn, parts) end
        if parts.L.pressBorder then Skin.PaintBorder(btn, parts) end
    end
end
function Skin.Tick(elapsed)
    local over = hovered and skinned[hovered]
    if over and mouseDown() then watchPress(hovered, over) end
    for btn in pairs(held) do watchPress(btn, skinned[btn]) end
    slowIn = slowIn - (elapsed or Skin.SLOW_EVERY)
    if slowIn > 0 then return end
    slowIn = Skin.SLOW_EVERY
    -- Only the game's buttons we dress (the pet and stance bars rewrite their own
    -- art and keys). Ours only change on the events that already redo them
    -- (Skin.QueueRefresh, the range touch). Only shown ones (no pet or stances means
    -- nothing to check); one that shows is checked on the next pass.
    for _, btn in ipairs(others) do
        if btn:IsVisible() then
            local nt = btn:GetNormalTexture()
            if nt and nt:GetAlpha() > 0 then Skin.Hide(btn) end
            Skin.UpdateKey(btn)          -- the pet bar rewrites its keybinds on its own
        end
    end
    -- A proc turning on comes with its event (Skin.QueueRefresh, and on our own
    -- buttons the Buttons painter too). Here we only look for one ending, since the
    -- alert fades out after its event.
    for btn in pairs(procOn) do Skin.UpdateProc(btn) end
end

function Skin.Wire()
    -- The game shows every slot while something is on the cursor.
    DUI.RegisterEvent("ACTIONBAR_SHOWGRID", function() Skin.SetDragging(true) end)
    DUI.RegisterEvent("ACTIONBAR_HIDEGRID", function() Skin.SetDragging(false) end)
    -- Once on the next frame however many came: a bar swap sends up to 120
    -- ACTIONBAR_SLOT_CHANGED, and each used to redo every button at once.
    local function full() Skin.QueueRefresh() end
    for _, e in ipairs({ "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
                         "PET_BAR_UPDATE", "UPDATE_BINDINGS", "PLAYER_ENTERING_WORLD", "EDIT_MODE_LAYOUTS_UPDATED",
                         "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS" }) do
        pcall(DUI.RegisterEvent, e, full)
    end
    -- Usable changes come with every cast and power tick. Our own buttons are
    -- repainted by Buttons' usable painter, so only the game's here.
    local function usable() Skin.QueueRefresh("usable") end
    pcall(DUI.RegisterEvent, "ACTIONBAR_UPDATE_USABLE", usable)
    pcall(DUI.RegisterEvent, "SPELL_UPDATE_USABLE", usable)
    local function procs() Skin.QueueRefresh("procs") end
    pcall(DUI.RegisterEvent, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", procs)
    pcall(DUI.RegisterEvent, "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", procs)
    -- Range: the client reports it per slot (a target change sends one for every
    -- range-checked slot). Buttons handles our own through its slot index; the
    -- game's buttons we dress are found here. The game reddens the keybind while
    -- handling the same event, so those buttons' art and key are redone on the next
    -- frame. Only those: a full refresh of every button per target change caused a
    -- hitch.
    pcall(DUI.RegisterEvent, "ACTION_RANGE_CHECK_UPDATE", function(_, slot, inRange, checksRange)
        local B = ns.Buttons
        local own = B and B.On and B.On(slot)
        if own then
            for _, btn in ipairs(own) do
                if skinned[btn] then rangeTouched[btn] = true end
            end
        end
        for _, btn in ipairs(others) do
            local parts = skinned[btn]
            if actionOf(btn) == slot then
                parts.outOfRange = checksRange == true and inRange == false
                Skin.UpdateRange(btn)
                rangeTouched[btn] = true
            end
        end
        queueRangeTouched()
    end)
    if not Skin.watcher then
        Skin.watcher = CreateFrame("Frame")
        Skin.watcher:SetScript("OnUpdate", function(_, elapsed) Skin.Tick(elapsed) end)
    end
end

-- Non-action buttons in the action bars' look (the Skins module's OPie ring). They
-- use the shared look (every bar's, Skin.LookFor(nil)) and the functions that paint
-- it, read live. ActionButtonLookChanged fires after each Configure, so they follow
-- option changes at once.
-- Tint(st): st = { L, outOfRange, noPower, unusable, cooling } -> alpha, color or
-- nil (tintGoal). PaintBorder(st, color): st = { back (the shell), shape, rest },
-- color = NORMAL, LIT or a color (paintColor).
DUI.ActionButtonLook = {
    Look = function() return Skin.LookFor(nil) end,
    BorderPx = Skin.BorderPx, StyleShellOpts = Skin.StyleShellOpts, BorderOf = Skin.BorderOf,
    ModeColor = Skin.ModeColor, CropOf = Skin.CropOf, Shape = Skin.Shape,
    StyleCooldown = Skin.StyleCooldown, EdgeOf = Skin.EdgeOf, Shorten = Skin.Shorten,
    Text = function(fs, size) styleText(fs, size) end,
    Tint = function(st) return tintGoal(st) end,
    PaintBorder = function(st, color) paintColor(st, color) end,
    NORMAL = Skin.NORMAL, LIT = Skin.STATE.lit,
    KEYBIND_POS = Skin.KEYBIND_POS, COUNT_POS = Skin.COUNT_POS,
    SHADE_FILE = Skin.SHADE_FILE, SHADE = Skin.SHADE,
}
