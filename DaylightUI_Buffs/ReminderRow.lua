-- The missing-buffs row: a row of icons above you, one per missing buff, its
-- name under it, laid out by the player's look settings (size, shape, border,
-- name, item count, glow, opacity, which edge stays put). A raid buff you give
-- shows how many have it; an item shows how many you carry; a buff with Show
-- Below counts down on its icon in the warn color.
--
-- A click casts through a secure button the client owns, laid over the icon
-- out of combat only and never anchored to it (anchoring would make the row
-- protected in a fight). With "Raid buffs at the cursor" the raid buffs you
-- give ride the mouse on plain frames instead, and can't be clicked.

local _, BL = ...
local DUI = DaylightUI
local L = DUI.L
local Style, Motion = DUI.Style, DUI.Motion
local INK = Style.INK

local Row = {}
BL.ReminderRow = Row

Row.MOVER = "buffs.reminders"
Row.DEFAULT = { "CENTER", nil, "CENTER", 0, 200 }
Row.BREATHS = 3       -- laps of the glow on an icon you can click, as it appears (no glow picked)
Row.GLOW_SCALE = { size = 0.7, thick = 0.08 } -- the glow's light and strip, as shares of the icon
Row.HOLDER_W, Row.HOLDER_H = 300, 70
Row.CURSOR_Y = 60     -- the cursor icons sit this far above the mouse
Row.CURSOR_LEVEL = 9980
Row.SHAPES = { circle = true, diamond = true, hexagon = true, octagon = true, shield = true }
Row.tiles = {}        -- every icon of the row made, shown or not
Row.cursorTiles = {}
Row.buttons = {}      -- DaylightUIBuffReminderCast<i>
Row.active = {}       -- the icons in the row, in order
Row.cursorActive = {} -- the icons at the cursor

local function cfg() return BL.Reminder and BL.Reminder.Config() or nil end

local function num(key, default, lo, hi)
    local c = cfg()
    local v = c and tonumber(c[key])
    if not v then return default end
    if lo and v < lo then v = lo end
    if hi and v > hi then v = hi end
    return v
end

local function opt(key, default)
    local c = cfg()
    local v = c and c[key]
    if v == nil then return default end
    return v
end

local function color(key, default)
    local v = opt(key)
    if type(v) == "table" and type(v[1]) == "number" then return v end
    return default
end

local function size() return math.floor(num("size", 40, 20, 120) + 0.5) end
local function gap() return num("gap", 14, 0, 50) end

local function shape()
    local s = opt("shape", "none")
    if s == "cropped" or Row.SHAPES[s] then return s end
    return "none"
end

-- An icon's width and height: a cropped icon loses crop% off its top and bottom.
local function dims()
    local w = size()
    if shape() == "cropped" then
        local crop = num("crop", 10, 5, 25) / 100
        return w, math.max(1, math.floor(w * (1 - 2 * crop) + 0.5))
    end
    return w, w
end
Row.Dims = dims

local function fightAlpha() return num("fightAlpha", 0.5, 0, 1) end

local function strata()
    local s = opt("strata", "MEDIUM")
    return type(s) == "string" and s or "MEDIUM"
end

local function namesOn() return opt("names", true) ~= false end

local function fontFile(key)
    if key == nil or key == DUI.Media.GENERAL then return nil end
    return Style.FontFileOf(key)
end

local function clickable(e)
    if not e or e.sample then return false end
    if e.kind == "give" then return e.spell ~= nil end
    return e.macro ~= nil
end
Row.Clickable = clickable

local function raid(e) return e and (e.kind == "give" or e.kind == "get") end

local function fighting() return BL.Reminder and BL.Reminder.Fighting() or false end

-- The raid buffs you give ride the mouse while cursor attach is on (with
-- "only in a fight", only then).
local function onCursor(e)
    if not e or e.kind ~= "give" or e.sample or opt("cursor", false) ~= true then return false end
    if opt("cursorCombat", false) == true then return fighting() end
    return true
end

-- ---------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------

function Row.Build()
    if Row.holder then return Row.holder end
    local holder = CreateFrame("Frame", "DaylightUIBuffRemindersHolder", UIParent)
    holder:SetSize(Row.HOLDER_W, Row.HOLDER_H)
    holder:SetFrameStrata(strata())
    Row.holder = holder
    DUI.Movers.Register(holder, Row.MOVER, "Missing Buffs", Row.DEFAULT)
    -- The cursor's icons: a tiny frame that follows the mouse while it shows.
    local cur = CreateFrame("Frame", "DaylightUIBuffRemindersCursor", UIParent)
    cur:SetSize(1, 1)
    cur:SetFrameStrata("TOOLTIP")
    cur:SetFrameLevel(Row.CURSOR_LEVEL)
    cur:EnableMouse(false)
    cur:Hide()
    cur:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local s = self:GetEffectiveScale() or 1
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s + Row.CURSOR_Y)
    end)
    Row.cursor = cur
    return holder
end

local function hideKey(key)
    if not key or BL.Reminder.sample then return end
    BL.Reminder.hidden[key] = true
    BL.Reminder.RefreshSoon()
end

-- The game's spell or item tooltip, then Daylight UI's lines under it. An
-- item's goes through Parts.ItemTip, which redraws it for Shift's compare.
local function drawTip(owner)
    local tile = owner.tipTile
    local e = tile and tile.entry
    if not e or not GameTooltip then return end
    local Tips = DUI.Tips
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    Tips.Clear()
    local game = false
    local item, spell = e.tipItem or e.item, e.tipSpell or e.spell
    if item and GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(item)
        game = true
    elseif spell and GameTooltip.SetSpellByID then
        GameTooltip:SetSpellByID(spell)
        game = true
    end
    if not game then Tips.Title(e.short or "") end
    if e.count == 0 then Tips.Text(L["You don't have this item in your bags"], INK.BAD) end
    if e.substitute then Tips.Text(L["Your pick is out: using another you carry"], INK.MONEY) end
    if e.kind == "give" and e.total then
        Tips.Sub(string.format(L["Missing on %d of %d"], e.total - e.have, e.total))
        for _, u in ipairs(e.lacking or {}) do
            local _, class = UnitClass(u)
            local r, g, b = Style.ClassTextColor(BL.Plain(class))
            local name = BL.Plain(DUI.UnitName(u))
            if type(name) == "string" then Tips.Text(name, { r, g, b }) end
        end
    elseif e.kind == "get" then
        Tips.Sub(L["Someone in your group can give it."])
    end
    if e.expireAt then
        Tips.Sub(string.format(L["Runs out in %s"], BL.FormatTime(math.max(0, e.expireAt - GetTime()))))
    end
    if clickable(e) then
        local what = e.spell and C_Spell and C_Spell.GetSpellName and BL.Plain(C_Spell.GetSpellName(e.spell)) or e.short
        if e.item then Tips.Hint(string.format(L["Click: use %s"], e.itemName or e.short or ""))
        else Tips.Hint(string.format(L["Click: cast %s"], what or "")) end
    end
    if e.picks then Tips.Hint(L["Right-click: choose another"]) end
    if not e.sample then Tips.Hint(L["Middle-click: hide until the next loading screen"]) end
    Tips.Flush(GameTooltip)
    GameTooltip:Show()
    if item then return "item:" .. item end
end

local itemTip
local function showTip(owner, tile)
    local e = tile and tile.entry
    if not e or not GameTooltip or opt("tooltips", true) == false then return end
    owner.tipTile = tile
    local Parts = DUI.Win and DUI.Win.Parts
    if (e.tipItem or e.item) and Parts and Parts.ItemTip then
        itemTip = itemTip or Parts.ItemTip(drawTip)
        itemTip(owner)
    else
        drawTip(owner)
    end
end
Row.ShowTip = showTip

local function hideTip() if GameTooltip then GameTooltip:Hide() end end

-- A left click on an icon that can't cast now (a fight): one line in the
-- game's error frame, at most every 2.5 s.
Row.SAY_EVERY = 2.5
local saidAt
local function noClick()
    if not fighting() then return end
    local now = GetTime()
    if saidAt and now - saidAt < Row.SAY_EVERY then return end
    saidAt = now
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        local c = INK.BAD
        UIErrorsFrame:AddMessage(L["Click-to-use is disabled in combat"], c[1], c[2], c[3])
    end
end

local function shapeFile(name, kind)
    return DUI.MEDIA .. "shape-" .. name .. (kind and "-" .. kind or "") .. ".png"
end

-- The icon's texture coordinates: zoom trims every side, a cropped icon its
-- top and bottom too, so the art isn't squashed.
local function coords(w, h)
    local z = num("zoom", 7, 0, 15) / 100
    local l, r, t, b = z, 1 - z, z, 1 - z
    if h < w then
        local cut = (1 - h / w) / 2 * (b - t)
        t, b = t + cut, b - cut
    end
    return l, r, t, b
end

local NAME_SPOTS = { BOTTOM = { "TOP", "BOTTOM" }, TOP = { "BOTTOM", "TOP" }, CENTER = { "CENTER", "CENTER" },
                     LEFT = { "RIGHT", "LEFT" }, RIGHT = { "LEFT", "RIGHT" } }

-- Lays one icon out by the look settings. A preview's icons keep the strata
-- of the window they sit in.
local function paintTile(t)
    local w, h = dims()
    t:SetSize(w, h)
    if not t.preview then t:SetFrameStrata(t.onCursor and "TOOLTIP" or strata()) end
    local base = t:GetFrameLevel()
    local border = opt("border", "daylight")
    local px = num("borderPx", 3, 0, 6)
    local shaped = Row.SHAPES[shape()] and shape() or nil
    local T = (border == "none" or px <= 0) and 0 or DUI.Pixel.Px(t, px)
    local behind = opt("borderBehind", false) == true
    t.art:SetFrameLevel(base + 2)
    t.edge:SetFrameLevel(base + (behind and 1 or 3))
    t.over:SetFrameLevel(base + 4)
    -- The edge: Daylight UI's shell, shifted by the player's offsets.
    local sx, sy = num("borderShiftX", 0, -10, 10), num("borderShiftY", 0, -10, 10)
    t.edge:ClearAllPoints()
    t.edge:SetPoint("TOPLEFT", t, "TOPLEFT", sx, sy)
    t.edge:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", sx, sy)
    local o = t.shellOpts
    o.borderPx, o.noBevel = px, true
    o.flat = border == "flat" or nil
    o.noBorder = (border == "none" or px <= 0) or nil
    -- In front of the icon the shell draws no fill, which would cover it.
    o.noBackground = (not behind) or nil
    t.shell = Style.Shell(t.edge, o)
    local bc = color("borderColor", Style.BORDER)
    if t.shell then Style.SetShellColors(t.shell, { bc[1], bc[2], bc[3] }) end
    t.edge:SetShown(not shaped)
    -- A shape: the action bars' art, the icon masked once.
    if shaped then
        t.shapeOuter:SetTexture(shapeFile(shaped))
        t.shapeOuter:SetVertexColor(bc[1], bc[2], bc[3], 1)
        t.shapeOuter:ClearAllPoints()
        t.shapeOuter:SetAllPoints(t)
        t.shapeOuter:SetShown(T > 0)
        t.shapeHole:SetTexture(shapeFile(shaped, "hole"), "CLAMPTOWHITE", "CLAMPTOWHITE")
        t.shapeHole:ClearAllPoints()
        t.shapeHole:SetPoint("TOPLEFT", t, "TOPLEFT", T, -T)
        t.shapeHole:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -T, T)
        t.shapeMask:SetTexture(shapeFile(shaped), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        t.shapeMask:ClearAllPoints()
        t.shapeMask:SetAllPoints(t.icon)
        if not t.masked then
            t.icon:AddMaskTexture(t.shapeMask)
            t.dim:AddMaskTexture(t.shapeMask)
            t.masked = true
        end
    else
        t.shapeOuter:Hide()
        if t.masked then
            t.icon:RemoveMaskTexture(t.shapeMask)
            t.dim:RemoveMaskTexture(t.shapeMask)
            t.masked = nil
        end
    end
    t.icon:ClearAllPoints()
    t.icon:SetPoint("TOPLEFT", t, "TOPLEFT", T, -T)
    t.icon:SetSize(math.max(1, w - 2 * T), math.max(1, h - 2 * T))
    t.icon:SetTexCoord(coords(w, h))
    -- The name.
    local spot = NAME_SPOTS[opt("nameAnchor", "BOTTOM")] or NAME_SPOTS.BOTTOM
    t.name:ClearAllPoints()
    t.name:SetPoint(spot[1], t, spot[2], num("nameX", 0, -50, 50), num("nameY", -5, -50, 50))
    Style.SetTextFont(t.name, fontFile(opt("nameFont")))
    Style.SetTextSize(t.name, num("nameSize", 12, 6, 30))
    local nc = color("nameColor", INK.TEXT)
    t.name:SetTextColor(nc[1], nc[2], nc[3])
    t.name:SetShown(namesOn())
    -- The count in the corner.
    t.count:ClearAllPoints()
    t.count:SetPoint("BOTTOMRIGHT", t.icon, "BOTTOMRIGHT", num("countX", 0, -50, 50), num("countY", 0, -50, 50))
    Style.SetTextFont(t.count, fontFile(opt("countFont")))
    Style.SetTextSize(t.count, num("countSize", 16, 6, 30))
end

-- An icon on parent: the row's, the cursor's, or a preview's.
local function makeTile(parent, cursor)
    local t = CreateFrame("Frame", nil, parent)
    t.onCursor = cursor or nil
    t:EnableMouse(not cursor)
    t.shellOpts = {}
    t.edge = CreateFrame("Frame", nil, t)
    t.art = CreateFrame("Frame", nil, t)
    t.art:SetAllPoints(t)
    t.over = CreateFrame("Frame", nil, t)
    t.over:SetAllPoints(t)
    t.icon = t.art:CreateTexture(nil, "ARTWORK")
    t.shapeOuter = t.art:CreateTexture(nil, "BORDER")
    t.shapeHole = t.art:CreateMaskTexture()
    t.shapeOuter:AddMaskTexture(t.shapeHole)
    t.shapeMask = t.art:CreateMaskTexture()
    -- Running low: the icon dims under its countdown.
    t.dim = t.art:CreateTexture(nil, "ARTWORK", nil, 2)
    t.dim:SetAllPoints(t.icon)
    local c = Style.BORDER
    t.dim:SetColorTexture(c[1], c[2], c[3], 0.55)
    -- An item's cooldown.
    t.cd = CreateFrame("Cooldown", nil, t.art)
    t.cd:SetAllPoints(t.icon)
    t.cd:Hide()
    t.time = Style.Text(t.over, Style.SIZE.head, "CENTER")
    t.time:SetPoint("CENTER", t.icon, "CENTER", 0, 0)
    t.count = Style.Text(t.over, 16, "RIGHT")
    t.name = Style.Text(t.over, Style.SIZE.small, "CENTER")
    if not cursor then
        t:SetScript("OnEnter", function(self) showTip(self, self) end)
        t:SetScript("OnLeave", hideTip)
        t:SetScript("OnMouseUp", function(self, button)
            local e = self.entry
            if not e or e.sample then return end
            if button == "MiddleButton" then hideKey(e.key)
            elseif button == "LeftButton" then noClick()
            elseif button == "RightButton" and BL.ReminderPicker then BL.ReminderPicker.Open(self) end
        end)
    end
    t:Hide()
    return t
end

local function newTile(cursor)
    local t = makeTile(cursor and Row.cursor or Row.Build(), cursor)
    local pool = cursor and Row.cursorTiles or Row.tiles
    pool[#pool + 1] = t
    paintTile(t)
    return t
end

-- A hunter's target tracking when the target's kind is secret: the seven
-- trackings side by side behind the icon's window, slid by a status bar's
-- fill. SetValue takes the secret kind, so the client picks the column and
-- nothing here reads it. Kinds already tracked or not known stay blank.
local WHITE = "Interface\\Buttons\\WHITE8X8"
local function strip(t)
    if t.strip then return t.strip end
    local v = CreateFrame("Frame", nil, t.art)
    v:SetClipsChildren(true)
    v:SetAllPoints(t.icon)
    local bar = CreateFrame("StatusBar", nil, v)
    bar:SetStatusBarTexture(WHITE)
    bar:GetStatusBarTexture():SetAlpha(0)
    bar:SetMinMaxValues(1, 7)
    bar:SetReverseFill(true)
    local row = CreateFrame("Frame", nil, v)
    v.bar, v.row, v.icons = bar, row, {}
    for i, id in ipairs(BL.ReminderData.TRACKING) do
        local tex = row:CreateTexture(nil, "ARTWORK")
        local icon = C_Spell and C_Spell.GetSpellTexture and BL.Plain(C_Spell.GetSpellTexture(id))
        tex:SetTexture(icon or 134400)
        v.icons[i] = tex
    end
    t.strip = v
    return v
end

local function fillStrip(t, e)
    local v = strip(t)
    local w, h = t.icon:GetWidth() or 0, t.icon:GetHeight() or 0
    v.bar:ClearAllPoints()
    v.bar:SetPoint("TOPLEFT", v, "TOPLEFT", 0, 0)
    v.bar:SetSize(math.max(1, 6 * w), math.max(1, h))
    v.row:ClearAllPoints()
    v.row:SetPoint("TOPLEFT", v.bar:GetStatusBarTexture(), "TOPLEFT", -6 * w, 0)
    v.row:SetSize(math.max(1, 7 * w), math.max(1, h))
    local l, r, tt, b = t.icon:GetTexCoord()
    for i, tex in ipairs(v.icons) do
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", v.row, "TOPLEFT", (i - 1) * w, 0)
        tex:SetSize(math.max(1, w), math.max(1, h))
        tex:SetTexCoord(l, r, tt, b)
        tex:SetAlpha(bit.band(e.trackMask or 0, 2 ^ (i - 1)) ~= 0 and 0 or 1)
    end
    v.bar:SetValue(e.secretType)
    v:Show()
end

local function timeText(e)
    if not e.expireAt then return nil end
    return BL.FormatTime(math.max(0, e.expireAt - GetTime()))
end

local function fill(t, e)
    t.entry = e
    t.key = e.key
    t.icon:SetTexture(e.icon or 134400)
    t.icon:SetDesaturated(e.count == 0 or e.gray == true)
    if e.secretType ~= nil then
        t.icon:Hide()
        fillStrip(t, e)
    else
        t.icon:Show()
        if t.strip then t.strip:Hide() end
    end
    t.name:SetText(e.short or "")
    local nc = color("nameColor", INK.TEXT)
    t.name:SetTextColor(nc[1], nc[2], nc[3])
    -- The corner: a giver's count (whatever the setting), else the bag count
    -- of what the click uses, a rank, or a badge such as 2/3.
    if e.kind == "give" and e.total then
        t.count:SetText(string.format("%d/%d", e.have or 0, e.total))
        Style.InkText(t.count, "pop")
        t.count:Show()
    elseif (e.count or e.badge) and opt("count", true) ~= false then
        t.count:SetText(e.badge or tostring(e.count))
        local c = INK.VALUE
        if e.count == 0 then c = INK.BAD elseif e.substitute then c = INK.MONEY end
        t.count:SetTextColor(c[1], c[2], c[3])
        t.count:Show()
    else
        t.count:Hide()
    end
    local left = timeText(e)
    if e.left and not e.expireAt then left = BL.FormatTime(e.left) end
    if left then
        t.time:SetText(left)
        local w = INK.WARN
        t.time:SetTextColor(w[1], w[2], w[3])
        t.time:Show(); t.dim:Show()
    else
        t.time:Hide(); t.dim:Hide()
    end
    if e.cooldown then
        t.cd:SetCooldown(e.cooldown[1], e.cooldown[2])
        t.cd:Show()
    else
        t.cd:Hide()
    end
end

-- ---------------------------------------------------------------------
-- Glows: the player's pick loops on every icon while it shows; with none,
-- an icon you can click breathes a few laps as it appears
-- ---------------------------------------------------------------------

local function glowColors()
    local mode = opt("glowColor", "accent")
    if mode == "custom" then
        local c = color("glowCustom", Style.ACCENT)
        return { c[1], c[2], c[3] }, { c[1], c[2], c[3] }
    elseif mode == "class" then
        local _, class = UnitClass("player")
        local r, g, b = Style.ClassColor(BL.Plain(class))
        if r then return { r, g, b }, { r, g, b } end
    end
    return nil
end

local function looping()
    local g = opt("glow", "none")
    return g ~= "none" and DUI.Widgets.GLOW_STYLES[g] ~= nil
end

local function glowShape(t, style)
    local lo, hi = glowColors()
    return { style = style, frame = t, parent = t.over, inset = 0, thick = DUI.Pixel.Px(t, 2),
             scale = Row.GLOW_SCALE, layer = "OVERLAY", sub = 7, lo = lo, hi = hi }
end

local function glowOn(t)
    local W = DUI.Widgets
    if not W or not W.GlowAround or not looping() or (t.entry and t.entry.noGlow) then return false end
    t.breath = (t.breath or 0) + 1
    t.glowLoop = opt("glow")
    W.GlowAround(t, true, glowShape(t, opt("glow")))
    return true
end

local function breathe(t)
    local W = DUI.Widgets
    if not W or not W.GlowAround then return end
    if glowOn(t) then return end
    t.breath = (t.breath or 0) + 1
    t.glowLoop = nil
    local mine = t.breath
    W.GlowAround(t, true, glowShape(t, "breathe"))
    local lap = W.GLOW_LAP and W.GLOW_LAP.breathe or 2.8
    C_Timer.After(lap * Row.BREATHS, function()
        if t.breath == mine then W.GlowAround(t, false) end
    end)
end

local function stopBreath(t)
    t.breath = (t.breath or 0) + 1
    t.glowLoop = nil
    local W = DUI.Widgets
    if W and W.GlowAround and t.glowDriver then W.GlowAround(t, false) end
end

-- ---------------------------------------------------------------------
-- Laying out
-- ---------------------------------------------------------------------

-- Plugins hear of each icon (API kind "buffreminder", unit = the buff's key);
-- the test mode and preview icons come as previews.
local function report(t, key, preview)
    local R = DUI.APIReport
    if not R then return end
    if t.reportedAs ~= nil and t.reportedAs ~= preview then R.Gone("buffreminder", t, t.reportedAs); t.reportedAs = nil end
    if not t.made then
        t.made = true
        R.Made("buffreminder", t, key, preview)
    else
        R.Unit("buffreminder", t, key, preview)
    end
    t.reportedAs = preview
    R.Styled("buffreminder", t, preview)
end

local function reportGone(t)
    local R = DUI.APIReport
    if R and t.reportedAs ~= nil then R.Gone("buffreminder", t, t.reportedAs) end
    t.reportedAs = nil
end

local function step() return size() + gap() end

-- An icon's spot, from the holder's middle: centered, or growing left from
-- the holder's right edge, or right from its left edge (that edge stays put).
local function spotX(i, n, centered)
    local grow = centered and "CENTER" or opt("grow", "CENTER")
    local s = size()
    if grow == "LEFT" then return Row.HOLDER_W / 2 - s / 2 - (n - i) * step() end
    if grow == "RIGHT" then return -Row.HOLDER_W / 2 + s / 2 + (i - 1) * step() end
    return (i - (n + 1) / 2) * step()
end
Row.SpotX = spotX

local function place(t, x)
    t:ClearAllPoints()
    t:SetPoint("CENTER", t.onCursor and Row.cursor or Row.holder, "CENTER", x, 0)
    t.x = x
end

local ticker
local function tick()
    local any, ended = false, false
    for _, t in ipairs(Row.active) do
        local e = t.entry
        if e and e.expireAt then
            any = true
            local left = e.expireAt - GetTime()
            if left <= 0 then ended = true end
            t.time:SetText(BL.FormatTime(math.max(0, left)))
        end
    end
    if not any and ticker then ticker:Cancel(); ticker = nil end
    if ended and BL.Reminder then BL.Reminder.RefreshSoon() end
end

local function armTicker()
    local any = false
    for _, t in ipairs(Row.active) do if t.entry and t.entry.expireAt then any = true end end
    if any and not ticker then ticker = C_Timer.NewTicker(1, tick)
    elseif not any and ticker then ticker:Cancel(); ticker = nil end
end

-- Lays one set of icons out (the row or the cursor's) and eases the changes:
-- new ones appear, gone ones fade, the rest glide to their new spot. In a
-- fight (hold) nothing already shown moves: a secure button sits over it.
local function layout(list, cursor, sample, rebreathe, hold)
    local pool = cursor and Row.cursorTiles or Row.tiles
    local byKey = {}
    local right
    for _, t in ipairs(pool) do
        if t.key and t:IsShown() then
            byKey[t.key] = t
            if t.x and (not right or t.x > right) then right = t.x end
        end
    end
    local n = #list
    local now = {}
    local nextX = right and (right + step()) or nil
    for i, e in ipairs(list) do
        local x = spotX(i, n, cursor)
        local t = byKey[e.key]
        local wasClick = t and clickable(t.entry)
        if t then
            byKey[e.key] = nil
            t.leaving = nil
            fill(t, e)
            if not hold and t.x ~= x then
                local dx = (t.x or x) - x
                place(t, x)
                if dx ~= 0 then Motion.Glide(t, dx, 0, Motion.NORMAL) end
            end
            if not cursor and not hold and (t:GetAlpha() < 1 or t.fightOut) then
                t.fightOut = nil
                Motion.AlphaTo(t, 1, Motion.NORMAL)
            end
        else
            t = nil
            for _, free in ipairs(pool) do
                if not free:IsShown() and not free.key then t = free break end
            end
            t = t or newTile(cursor)
            paintTile(t)
            fill(t, e)
            if hold and nextX then
                place(t, nextX)
                nextX = nextX + step()
            else
                place(t, x)
            end
            t:SetAlpha(hold and raid(e) and fightAlpha() > 0 and fightAlpha() or 1)
            t:Show()
            Motion.Appear(t, 6)
        end
        if not cursor then report(t, e.key, sample == true) end
        if looping() and not e.noGlow then
            if not (t.glowLoop == opt("glow") and t.glowDriver and t.glowDriver:IsShown()) then glowOn(t) end
        elseif clickable(e) and not cursor and not hold and (not wasClick or rebreathe) then
            breathe(t)
        elseif not clickable(e) or cursor then
            stopBreath(t)
        end
        now[#now + 1] = t
    end
    -- Gone ones fade out where they stand.
    for _, t in pairs(byKey) do
        t.leaving = true
        stopBreath(t)
        if not cursor then reportGone(t) end
        local key = t.key
        t.key = nil
        t.entry = nil
        Motion.AlphaTo(t, 0, Motion.FAST, true)
        if not Motion.On() then t:Hide() end
        t.goneKey = key
    end
    if hold then
        table.sort(now, function(a, b) return (a.x or 0) < (b.x or 0) end)
    end
    return now
end

-- Lays the row out for a list of entries. sample: the test mode and preview
-- icons (no clicks).
function Row.Set(list, sample)
    Row.Build()
    list = list or {}
    local rebreathe = Row.rebreathe
    Row.rebreathe = nil
    local hold = not sample and fighting()
    local inRow, atCursor = {}, {}
    for _, e in ipairs(list) do
        if sample then
            local copy = {}
            for k, v in pairs(e) do copy[k] = v end
            copy.sample = true
            e = copy
        end
        if onCursor(e) then atCursor[#atCursor + 1] = e else inRow[#inRow + 1] = e end
    end
    local a = num("opacity", 1, 0, 1)
    Row.holder:SetAlpha(a)
    Row.cursor:SetAlpha(a)
    Row.active = layout(inRow, false, sample, rebreathe, hold)
    Row.cursorActive = layout(atCursor, true, sample, rebreathe, false)
    Row.cursor:SetShown(#atCursor > 0)
    armTicker()
    if hold then
        Row.Fight(true)
        -- A button whose raid buff left in the fight can't hide: see-through.
        local live = {}
        for _, t in ipairs(Row.active) do
            local e = t.entry
            if e and not t.leaving and raid(e) and not e.extra then live[e.key] = true end
        end
        for _, b in ipairs(Row.buttons) do
            if b:IsShown() and b.entry then b:SetAlpha(live[b.entry.key] and 1 or 0) end
        end
    end
    if not sample then DUI.AfterCombat(Row.PlaceButtons, "buffs:reminderButtons") end
    if sample then Row.ClearButtons() end
    if BL.ReminderPicker then BL.ReminderPicker.Validate(Row.active) end
end

-- A look setting changed: lay every icon out again.
function Row.Relayout()
    if not Row.holder then return end
    Row.holder:SetFrameStrata(strata())
    local a = num("opacity", 1, 0, 1)
    Row.holder:SetAlpha(a)
    if Row.cursor then Row.cursor:SetAlpha(a) end
    for _, t in ipairs(Row.tiles) do paintTile(t) end
    for _, t in ipairs(Row.cursorTiles) do paintTile(t) end
    if not fighting() then
        local n = #Row.active
        for i, t in ipairs(Row.active) do place(t, spotX(i, n)) end
    end
    local n = #Row.cursorActive
    for i, t in ipairs(Row.cursorActive) do place(t, spotX(i, n, true)) end
    for _, set in ipairs({ Row.active, Row.cursorActive }) do
        for _, t in ipairs(set) do
            if t.entry then fill(t, t.entry) end
            if looping() and not (t.entry and t.entry.noGlow) then glowOn(t)
            elseif t.glowLoop then stopBreath(t) end
        end
    end
    if not BL.Reminder.sample then DUI.AfterCombat(Row.PlaceButtons, "buffs:reminderButtons") end
end

-- ---------------------------------------------------------------------
-- A fight
-- ---------------------------------------------------------------------

-- The pull: nothing moves. Raid buffs dim, the rest fade away (a macro does
-- nothing in a fight anyway). Only the first raid buff you give keeps its
-- button: a second one's button and icon go. Fight info never waits: at
-- once, FAST.
function Row.Fight(on)
    if not on then
        Row.rebreathe = true
        for _, t in ipairs(Row.active) do t.fightIn = nil end
        return
    end
    local a = fightAlpha()
    local buttonOf = {}
    for _, b in ipairs(Row.buttons) do if b.tile then buttonOf[b.tile] = b end end
    for _, t in ipairs(Row.active) do
        if t:IsShown() and not t.leaving then
            if not looping() then stopBreath(t) end
            local b = buttonOf[t]
            local e = t.entry
            if raid(e) and not e.extra and a > 0 then
                if not t.fightIn then Motion.AlphaTo(t, a, Motion.FAST) end
                t.fightIn = true
            else
                t.fightOut = true
                Motion.AlphaTo(t, 0, Motion.FAST, true)
                -- Its button can't hide in a fight: it goes see-through instead.
                if b then b:SetAlpha(0) end
            end
        end
    end
end

-- ---------------------------------------------------------------------
-- Secure buttons
-- ---------------------------------------------------------------------

local ATTRS = { "type1", "spell1", "unit1", "macrotext1", "item1" }

local function button(i)
    local b = Row.buttons[i]
    if b then return b end
    b = CreateFrame("Button", "DaylightUIBuffReminderCast" .. i, UIParent, "SecureActionButtonTemplate")
    b:SetFrameStrata(strata())
    b:SetFrameLevel(20)
    -- The client acts on a secure button's down half while its key-down setting
    -- is on (the default); this button takes only the up half, so it says so.
    b:RegisterForClicks("LeftButtonUp", "MiddleButtonUp", "RightButtonUp")
    b:SetAttribute("useOnKeyDown", false)
    b:SetScript("OnEnter", function(self) showTip(self, self.tile) end)
    b:SetScript("OnLeave", hideTip)
    b:SetScript("PostClick", function(self, which)
        if which == "MiddleButton" and self.entry then hideKey(self.entry.key)
        elseif which == "RightButton" and self.tile and BL.ReminderPicker then BL.ReminderPicker.Open(self.tile, self) end
    end)
    b:Hide()
    Row.buttons[i] = b
    return b
end

-- The raid buff your button was bound to before the fight, or nil.
function Row.BoundKey()
    for _, b in ipairs(Row.buttons) do
        if b:IsShown() and b.entry and b.entry.kind == "give" and not b.entry.extra then return b.entry.key end
    end
    return nil
end

-- The icon's spot on the screen, in UIParent's units (never an anchor to it).
local function screenSpot(t)
    local h = Row.holder
    local hx, hy = h:GetCenter()
    local hs = h:GetEffectiveScale() or 1
    local us = UIParent:GetEffectiveScale() or 1
    local k = hs / us
    local w, ht = dims()
    if hx and hy then return "BOTTOMLEFT", hx * k + (t.x or 0) * k, hy * k, w * k, ht * k end
    -- No layout yet (the frame isn't drawn): from the holder's own spot.
    local _, _, _, ox, oy = h:GetPoint(1)
    return "CENTER", (ox or 0) * k + (t.x or 0) * k, (oy or 0) * k, w * k, ht * k
end

function Row.ClearButtons()
    if InCombatLockdown() then return end
    for _, b in ipairs(Row.buttons) do
        if b:IsShown() or b.entry then
            for _, k in ipairs(ATTRS) do b:SetAttribute(k, nil) end
            b.entry, b.tile = nil, nil
            b:Hide()
        end
    end
end

-- One button over each icon you can click: a spell at a unit for a raid buff,
-- a macro with [nocombat] for the rest. Only the left button casts.
function Row.PlaceButtons()
    if InCombatLockdown() then return end
    local i = 0
    local st = strata()
    for _, t in ipairs(Row.active) do
        local e = t.entry
        if clickable(e) and t:IsShown() and not t.leaving then
            i = i + 1
            local b = button(i)
            for _, k in ipairs(ATTRS) do b:SetAttribute(k, nil) end
            if e.kind == "give" then
                b:SetAttribute("type1", "spell")
                b:SetAttribute("spell1", e.spell)
                b:SetAttribute("unit1", e.unit)
            else
                b:SetAttribute("type1", "macro")
                b:SetAttribute("macrotext1", e.macro)
            end
            local point, x, y, w, h = screenSpot(t)
            b:SetFrameStrata(st)
            b:ClearAllPoints()
            b:SetPoint("CENTER", UIParent, point, x, y)
            b:SetSize(w, h)
            b.entry, b.tile = e, t
            b:SetAlpha(1)
            b:Show()
        end
    end
    for j = i + 1, #Row.buttons do
        local b = Row.buttons[j]
        if b.entry or b:IsShown() then
            for _, k in ipairs(ATTRS) do b:SetAttribute(k, nil) end
            b.entry, b.tile = nil, nil
            b:Hide()
        end
    end
end

-- The holder moved (unlock mode): the buttons follow out of combat.
DUI.On("MoverApplied", function(key)
    if key == Row.MOVER and Row.holder then DUI.AfterCombat(Row.PlaceButtons, "buffs:reminderButtons") end
end)

-- A new font or accent: paint the icons again.
DUI.On("StyleChanged", function()
    for _, t in ipairs(Row.active) do if t.entry then fill(t, t.entry) end end
end)

-- ---------------------------------------------------------------------
-- A preview (the setup guide and the What's New page)
-- ---------------------------------------------------------------------

Row.PREVIEW_STAGGER = 0.08   -- s between one icon rising in and the next
Row.PREVIEW_RISE = 6

-- The sample row on its own frame: the real icons, filled with the sample
-- buffs, a raid buff you give breathing as yours does when it shows. Nothing
-- can be clicked and nothing is reported to plugins. Each time it shows, the
-- icons rise in one after another.
function Row.Preview(parent)
    local box = CreateFrame("Frame", nil, parent)
    box.tiles = {}
    for i, e in ipairs(BL.ReminderData.SAMPLE) do
        local t = makeTile(box)
        t.preview = true
        local copy = {}
        for k, v in pairs(e) do copy[k] = v end
        copy.sample = true
        t.sampleEntry = copy
        box.tiles[i] = t
    end
    function box.Layout()
        local n = #box.tiles
        local w, h = dims()
        for i, t in ipairs(box.tiles) do
            paintTile(t)
            fill(t, t.sampleEntry)
            t:ClearAllPoints()
            t:SetPoint("TOP", box, "TOP", spotX(i, n, true), 0)
            t:Show()
        end
        local below = namesOn() and opt("nameAnchor", "BOTTOM") == "BOTTOM"
            and (-num("nameY", -5, -50, 50) + num("nameSize", 12, 6, 30)) or 0
        box:SetSize(math.max(1, n * w + (n - 1) * gap()), h + math.max(0, below))
    end
    box:SetScript("OnShow", function()
        box.Layout()
        local Feel = DUI.Win and DUI.Win.Feel
        for i, t in ipairs(box.tiles) do
            if Feel then Feel.Piece(t, i * Row.PREVIEW_STAGGER, Motion.SLOW, Row.PREVIEW_RISE) end
            if t.sampleEntry.kind == "give" then
                C_Timer.After(#box.tiles * Row.PREVIEW_STAGGER + Motion.SLOW, function()
                    if box:IsVisible() then breathe(t) end
                end)
            end
        end
    end)
    box:SetScript("OnHide", function()
        for _, t in ipairs(box.tiles) do stopBreath(t) end
    end)
    box.Layout()
    return box
end
