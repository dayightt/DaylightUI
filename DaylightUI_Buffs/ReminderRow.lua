-- The missing-buffs row: a centered row of icons above you, dressed like the
-- Cooldown Manager's, one per missing buff, its name under it. A raid buff you give shows how many have
-- it; a buff running low counts down on its tile in the warn color. A tile you
-- can click wears the accent edge and breathes a few times as it appears.
--
-- A click casts through a secure button the client owns, laid over the tile
-- out of combat only and never anchored to it (anchoring would make the row
-- protected in a fight). In a fight nothing moves: raid buffs dim, the rest
-- fade away, and the row re-centers once the fight ends.

local _, BL = ...
local DUI = DaylightUI
local L = DUI.L
local Style, Motion = DUI.Style, DUI.Motion
local INK = Style.INK

local Row = {}
BL.ReminderRow = Row

Row.MOVER = "buffs.reminders"
Row.DEFAULT = { "CENTER", nil, "CENTER", 0, 200 }
Row.BORDER_PX = 3     -- the border in screen pixels, as on the Cooldown Manager's icons
Row.NAME_Y = -10      -- the name's middle under the tile's bottom
Row.BREATHS = 3       -- laps of the glow on a tile you can click
Row.GLOW_SCALE = { size = 0.7, thick = 0.08 } -- the glow's light and strip, as shares of the icon
Row.HOLDER_W, Row.HOLDER_H = 300, 70
Row.tiles = {}        -- every tile made, shown or not
Row.buttons = {}      -- DaylightUIBuffReminderCast<i>

local function cfg() return BL.Reminder and BL.Reminder.Config() or nil end

local function size()
    local c = cfg()
    local s = c and tonumber(c.size)
    return s and s >= 16 and s or 36
end

local function gap()
    local c = cfg()
    local g = c and tonumber(c.gap)
    return g and g >= 0 and g or 24
end

local function namesOn()
    local c = cfg()
    return not c or c.names ~= false
end

local function fightAlpha()
    local c = cfg()
    local a = c and tonumber(c.fightAlpha)
    return a and math.max(0, math.min(1, a)) or 0.5
end

local function clickable(e)
    if not e or e.sample then return false end
    if e.kind == "give" then return e.spell ~= nil end
    return e.macro ~= nil
end
Row.Clickable = clickable

local function raid(e) return e and (e.kind == "give" or e.kind == "get") end

-- ---------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------

function Row.Build()
    if Row.holder then return Row.holder end
    local holder = CreateFrame("Frame", "DaylightUIBuffRemindersHolder", UIParent)
    holder:SetSize(Row.HOLDER_W, Row.HOLDER_H)
    holder:SetFrameStrata("MEDIUM")
    Row.holder = holder
    DUI.Movers.Register(holder, Row.MOVER, "Missing Buffs", Row.DEFAULT)
    return holder
end

local function hideKey(key)
    if not key or BL.Reminder.sample then return end
    BL.Reminder.hidden[key] = true
    BL.Reminder.RefreshSoon()
end

local function showTip(owner, tile)
    local e = tile and tile.entry
    if not e or not GameTooltip then return end
    local Tips = DUI.Tips
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    Tips.Clear()
    Tips.Title(e.short or "")
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
        if e.item then Tips.Hint(string.format(L["Click: use %s"], e.short or ""))
        else Tips.Hint(string.format(L["Click: cast %s"], what or "")) end
    end
    if not e.sample then Tips.Hint(L["Middle-click: hide until the next loading screen"]) end
    Tips.Flush(GameTooltip)
    GameTooltip:Show()
end
Row.ShowTip = showTip

local function hideTip() if GameTooltip then GameTooltip:Hide() end end

-- An icon dressed like the Cooldown Manager's: the icon square inside a thin
-- border, no bevel.
local function paintTile(t)
    local s = size()
    t:SetSize(s, s)
    Style.Shell(t)
    local T = DUI.Pixel.Px(t, Row.BORDER_PX)
    t.icon:ClearAllPoints()
    t.icon:SetPoint("TOPLEFT", t, "TOPLEFT", T, -T)
    t.icon:SetSize(math.max(1, s - 2 * T), math.max(1, s - 2 * T))
    t.name:SetShown(namesOn())
end

-- A tile on parent: the row's, or a preview's (which keeps its own).
local function makeTile(parent)
    local t = CreateFrame("Frame", nil, parent)
    t:EnableMouse(true)
    t.shell = Style.Shell(t, { borderPx = Row.BORDER_PX, noBevel = true })
    t.icon = t:CreateTexture(nil, "ARTWORK")
    Style.CropIcon(t.icon)
    -- Running low: the icon dims under its countdown.
    t.dim = t:CreateTexture(nil, "ARTWORK", nil, 2)
    t.dim:SetAllPoints(t.icon)
    local c = Style.BORDER
    t.dim:SetColorTexture(c[1], c[2], c[3], 0.55)
    t.time = Style.Text(t, Style.SIZE.head, "CENTER")
    t.time:SetPoint("CENTER", t.icon, "CENTER", 0, 0)
    -- The count a giver sees, in the icon's corner like a stack count.
    t.count = Style.Text(t, Style.SIZE.tiny, "RIGHT")
    t.count:SetPoint("BOTTOMRIGHT", t.icon, "BOTTOMRIGHT", -1, 1)
    t.name = Style.Text(t, Style.SIZE.small, "CENTER")
    t.name:SetPoint("CENTER", t, "BOTTOM", 0, Row.NAME_Y)
    t:SetScript("OnEnter", function(self) showTip(self, self) end)
    t:SetScript("OnLeave", hideTip)
    t:SetScript("OnMouseUp", function(self, button)
        if button == "MiddleButton" and self.entry and not self.entry.sample then hideKey(self.entry.key) end
    end)
    t:Hide()
    paintTile(t)
    return t
end

local function newTile()
    local t = makeTile(Row.Build())
    t:SetFrameStrata("MEDIUM")
    Row.tiles[#Row.tiles + 1] = t
    return t
end

local function timeText(e)
    if not e.expireAt then return nil end
    return BL.FormatTime(math.max(0, e.expireAt - GetTime()))
end

local function fill(t, e)
    t.entry = e
    t.key = e.key
    t.icon:SetTexture(e.icon or 134400)
    t.name:SetText(e.short or "")
    local n = INK.TEXT
    t.name:SetTextColor(n[1], n[2], n[3])
    if e.kind == "give" and e.total then
        t.count:SetText(string.format("%d/%d", e.have or 0, e.total))
        Style.InkText(t.count, "pop")
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
    -- A dark border on every icon, as on the Cooldown Manager's: the glow marks
    -- the one you can click (a lit border's mitered corners read as angled bars).
    Style.SetShellColors(t.shell)
end

-- ---------------------------------------------------------------------
-- The glow on a tile you can click
-- ---------------------------------------------------------------------

local function breathe(t)
    local W = DUI.Widgets
    if not W or not W.GlowAround then return end
    t.breath = (t.breath or 0) + 1
    local mine = t.breath
    -- As the Cooldown Manager lays its glows: on the icon's edge, over everything,
    -- sized by the icon.
    W.GlowAround(t, true, { style = "breathe", frame = t, inset = 0, thick = DUI.Pixel.Px(t, 2),
                            scale = Row.GLOW_SCALE, parent = t, layer = "OVERLAY", sub = 7 })
    local lap = W.GLOW_LAP and W.GLOW_LAP.breathe or 2.8
    C_Timer.After(lap * Row.BREATHS, function()
        if t.breath == mine then W.GlowAround(t, false) end
    end)
end

local function stopBreath(t)
    t.breath = (t.breath or 0) + 1
    local W = DUI.Widgets
    if W and W.GlowAround and t.glowDriver then W.GlowAround(t, false) end
end

-- ---------------------------------------------------------------------
-- Laying out
-- ---------------------------------------------------------------------

Row.active = {}   -- the tiles in the row, in order

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

-- A tile's spot, from the holder's middle.
local function spotX(i, n) return (i - (n + 1) / 2) * step() end
Row.SpotX = spotX

local function place(t, x)
    t:ClearAllPoints()
    t:SetPoint("CENTER", Row.holder, "CENTER", x, 0)
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

-- Lays the row out for a list of entries and eases the changes: new tiles
-- appear, gone ones fade, the rest glide to their new spot. sample: the test
-- mode and preview tiles (no clicks).
function Row.Set(list, sample)
    Row.Build()
    list = list or {}
    local byKey = {}
    for _, t in ipairs(Row.tiles) do
        if t.key and t:IsShown() then byKey[t.key] = t end
    end
    local n = #list
    local now = {}
    local rebreathe = Row.rebreathe
    Row.rebreathe = nil
    for i, e in ipairs(list) do
        if sample then
            local copy = {}
            for k, v in pairs(e) do copy[k] = v end
            copy.sample = true
            e = copy
        end
        local x = spotX(i, n)
        local t = byKey[e.key]
        local wasClick = t and clickable(t.entry)
        if t then
            byKey[e.key] = nil
            t.leaving = nil
            fill(t, e)
            if t.x ~= x then
                local dx = (t.x or x) - x
                place(t, x)
                if dx ~= 0 then Motion.Glide(t, dx, 0, Motion.NORMAL) end
            end
            if t:GetAlpha() < 1 or t.fightOut then
                t.fightOut = nil
                Motion.AlphaTo(t, 1, Motion.NORMAL)
            end
        else
            t = nil
            for _, free in ipairs(Row.tiles) do
                if not free:IsShown() and not free.key then t = free break end
            end
            t = t or newTile()
            paintTile(t)
            fill(t, e)
            place(t, x)
            t:SetAlpha(1)
            t:Show()
            Motion.Appear(t, 6)
        end
        report(t, e.key, sample == true)
        if clickable(e) and (not wasClick or rebreathe) then breathe(t) end
        if not clickable(e) then stopBreath(t) end
        now[#now + 1] = t
    end
    -- Gone ones fade out where they stand.
    for _, t in pairs(byKey) do
        t.leaving = true
        stopBreath(t)
        reportGone(t)
        local key = t.key
        t.key = nil
        t.entry = nil
        Motion.AlphaTo(t, 0, Motion.FAST, true)
        if not Motion.On() then t:Hide() end
        t.goneKey = key
    end
    Row.active = now
    armTicker()
    if not sample then DUI.AfterCombat(Row.PlaceButtons, "buffs:reminderButtons") end
    if sample then Row.ClearButtons() end
end

-- New size, gap or names: lay every tile out again.
function Row.Relayout()
    if not Row.holder then return end
    for _, t in ipairs(Row.tiles) do paintTile(t) end
    local n = #Row.active
    for i, t in ipairs(Row.active) do place(t, spotX(i, n)) end
    if not BL.Reminder.sample then DUI.AfterCombat(Row.PlaceButtons, "buffs:reminderButtons") end
end

-- ---------------------------------------------------------------------
-- A fight
-- ---------------------------------------------------------------------

-- The pull: nothing moves. Raid buffs dim, the rest fade away (your own buff's
-- macro does nothing in a fight anyway). Fight info never waits: at once, FAST.
function Row.Fight(on)
    if not on then
        Row.rebreathe = true
        return
    end
    local a = fightAlpha()
    local buttonOf = {}
    for _, b in ipairs(Row.buttons) do if b.tile then buttonOf[b.tile] = b end end
    for _, t in ipairs(Row.active) do
        stopBreath(t)
        local b = buttonOf[t]
        if raid(t.entry) and a > 0 then
            Motion.AlphaTo(t, a, Motion.FAST)
        else
            t.fightOut = true
            Motion.AlphaTo(t, 0, Motion.FAST, true)
            -- Its button can't hide in a fight: it goes see-through instead.
            if b then b:SetAlpha(0) end
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
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(20)
    -- The client acts on a secure button's down half while its key-down setting
    -- is on (the default); this button takes only the up half, so it says so.
    b:RegisterForClicks("LeftButtonUp", "MiddleButtonUp")
    b:SetAttribute("useOnKeyDown", false)
    b:SetScript("OnEnter", function(self) showTip(self, self.tile) end)
    b:SetScript("OnLeave", hideTip)
    b:SetScript("PostClick", function(self, which)
        if which == "MiddleButton" and self.entry then hideKey(self.entry.key) end
    end)
    b:Hide()
    Row.buttons[i] = b
    return b
end

-- The tile's spot on the screen, in UIParent's units (never an anchor to it).
local function screenSpot(t)
    local h = Row.holder
    local hx, hy = h:GetCenter()
    local hs = h:GetEffectiveScale() or 1
    local us = UIParent:GetEffectiveScale() or 1
    local k = hs / us
    local s = size() * k
    if hx and hy then return "BOTTOMLEFT", hx * k + (t.x or 0) * k, hy * k, s end
    -- No layout yet (the frame isn't drawn): from the holder's own spot.
    local _, _, _, ox, oy = h:GetPoint(1)
    return "CENTER", (ox or 0) * k + (t.x or 0) * k, (oy or 0) * k, s
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

-- One button over each tile you can click: a spell at a unit for a raid buff,
-- a macro with [nocombat] for the rest. Left button only casts.
function Row.PlaceButtons()
    if InCombatLockdown() then return end
    local i = 0
    for _, t in ipairs(Row.active) do
        local e = t.entry
        if clickable(e) then
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
            local point, x, y, s = screenSpot(t)
            b:ClearAllPoints()
            b:SetPoint("CENTER", UIParent, point, x, y)
            b:SetSize(s, s)
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

-- A new font or accent: paint the tiles again.
DUI.On("StyleChanged", function()
    for _, t in ipairs(Row.active) do if t.entry then fill(t, t.entry) end end
end)

-- ---------------------------------------------------------------------
-- A preview (the setup guide and the What's New page)
-- ---------------------------------------------------------------------

Row.PREVIEW_STAGGER = 0.08   -- s between one tile rising in and the next
Row.PREVIEW_RISE = 6

-- The sample row on its own frame: the real tiles, filled with the sample
-- buffs, a raid buff you give breathing as yours does when it shows. Nothing
-- can be clicked and nothing is reported to plugins. Each time it shows, the
-- tiles rise in one after another.
function Row.Preview(parent)
    local box = CreateFrame("Frame", nil, parent)
    box.tiles = {}
    for i, e in ipairs(BL.ReminderData.SAMPLE) do
        local t = makeTile(box)
        local copy = {}
        for k, v in pairs(e) do copy[k] = v end
        copy.sample = true
        t.sampleEntry = copy
        box.tiles[i] = t
    end
    function box.Layout()
        local n = #box.tiles
        local s = size()
        for i, t in ipairs(box.tiles) do
            paintTile(t)
            fill(t, t.sampleEntry)
            t:ClearAllPoints()
            t:SetPoint("TOP", box, "TOP", spotX(i, n), 0)
            t:Show()
        end
        box:SetSize(math.max(1, n * s + (n - 1) * gap()), s + (namesOn() and -Row.NAME_Y + Style.SIZE.small or 0))
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
