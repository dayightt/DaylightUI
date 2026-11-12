-- Whisper tiles: a row over the chat's top-right corner (or top-left, per
-- whisperSide), one small tile per recent conversation, newest next to the corner
-- and pinned first. Each shows the person's initial in their class color and an
-- unread count. Click opens their conversation beside the chat (Convo.lua),
-- right-click opens its menu, hover shows who it is and their last line.
-- * Tiles rise from under the chat's top edge (a clip frame whose bottom is the
--   chat's top). An unread tile rises on its own; all of them rise in turn while
--   hovering the chat or tiles, or while a conversation is open, and sink AWAKE
--   seconds later. A light runs along the chat's top when a new whisper lands.
--   Another line from the same person just bumps the count. In combat they
--   appear at once.
-- * The conversation slides out of the chat's side like the damage meter
--   (Motion.Slider on a clip frame's width).
-- * A new whisper can show a preview above the tiles for a few seconds.
-- * The speech bubble in the tab row (with the unread count) opens the hub.
-- * Everything is parented to the panel and floats away with it, but a new
--   whisper's tiles still fade in for a while (Tiles.Peek).

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel
local L = DUI.L

local Tiles = {}
ns.Tiles = Tiles

Tiles.SIZE = 34
Tiles.GAP = 4 -- gap between tiles
Tiles.JOIN = 2 -- gap between the chat and the conversation
Tiles.LIFT = 6 -- tile row height over the chat's top edge
Tiles.STAGGER = 0.06 -- stagger delay between tiles, seconds
Tiles.CLOSE = 14 -- tile close button hit box
Tiles.SLICES = 8 -- bands in the initial's class gradient, top (light) to bottom
Tiles.MAX = 6
Tiles.PREVIEW = 6 -- seconds a preview stays
Tiles.PREVIEW_W = 240
Tiles.FIGHT_ALPHA = 0.7 -- softer preview in combat
Tiles.ICON = DaylightUI.MEDIA .. "ui-section-chat.png" -- the Whispers link's bubble
Tiles.SLIDE = DaylightUI.Motion.SLOW -- tiles rising, conversation sliding out
Tiles.AWAKE = 1.5 -- seconds tiles stay up after the mouse leaves
Tiles.GLOW = 0.5 -- unread tile light at the peak of its pulse

local cfg
local column, preview, link
local drawer, cardSlide, sweep
local awakeUntil = 0
local tiles = {} -- pooled
local shownKeys = {} -- tile -> key it last showed

local function M() return DUI.Motion end
local function W() return DUI.Widgets end

function Tiles.Apply(c) cfg = c end
function Tiles.Column() return column end
function Tiles.Drawer() return drawer end
function Tiles.Sliders() return nil, cardSlide end
function Tiles.Tiles() return tiles end
function Tiles.Side() return (cfg and cfg.whisperSide == "left") and "left" or "right" end

-- A Battle.net friend's name as plain letters: the BattleTag before the #.
-- The conversation's own name is a protected string that only a FontString can
-- draw, so it can't be split into letters.
local function tagName(c)
    local info = C_BattleNet and C_BattleNet.GetAccountInfoByID and C_BattleNet.GetAccountInfoByID(c.bn)
    local tag = type(info) == "table" and info.battleTag
    if type(tag) ~= "string" or (issecretvalue ~= nil and issecretvalue(tag)) then return nil end
    local name = string.match(tag, "^[^#]+")
    return name
end

-- First two characters (Th for Thornwick), whole UTF-8 characters so accents and
-- other scripts work. Bn for a Battle.net friend with no known tag.
local CHAR = "[%z\1-\127\194-\244][\128-\191]*"
local function initial(c)
    local name
    if c.bn then
        name = tagName(c)
        if not name then return "Bn" end
    else
        name = (type(Ambiguate) == "function" and c.name and Ambiguate(c.name, "short")) or c.name or "?"
    end
    local first, second = string.match(name, "^(" .. CHAR .. ")(" .. CHAR .. ")")
    if not first then return string.match(name, "^" .. CHAR) or "?" end
    return first .. string.lower(second)
end

-- ---------------------------------------------------------------------
-- A tile
-- ---------------------------------------------------------------------

local function tip(b)
    local c = b.key and ns.Talk.Get(b.key)
    if not c then return end
    local Tips = DUI.Tips
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    Tips.Title(ns.Thread.Name(c), Style.ClassTextColor(c.class))
    local note = ns.Talk.Note(c)
    if note then Tips.Sub(note) end
    local last = c.msgs[#c.msgs]
    if last then Tips.Text((last.me and (L["You"] .. ": ") or "") .. last.text) end
    Tips.Hint(L["Click: open the conversation"])
    Tips.Hint(L["Right-click: pin, invite, note, ignore, close"])
    Tips.Flush()
end

local function menu(b)
    local c = b.key and ns.Talk.Get(b.key)
    if not c then return end
    local keys, values = { "pin", "note", "close", "forget" },
        { pin = c.pinned and L["Unpin"] or L["Pin"], note = L["Note"], close = L["Close"], forget = L["Forget conversation"] }
    if ns.Thread.CanInvite(c) then table.insert(keys, 2, "invite"); values.invite = L["Invite"] end
    if ns.Thread.CanIgnore(c) then table.insert(keys, #keys, "ignore"); values.ignore = IGNORE or L["Ignore"] end
    W().OpenMenu(b, keys, values, nil, function(k)
        if k == "pin" then ns.Talk.Pin(c, not c.pinned)
        elseif k == "invite" then ns.Thread.Invite(c)
        elseif k == "note" then W().Prompt(L["A note about this player"], ns.Talk.Note(c) or "", function(t) ns.Talk.SetNote(c, t) end)
        elseif k == "close" then
            if ns.Convo.Showing(c.key) then ns.Convo.Close() end
            ns.Talk.Close(c)
        elseif k == "ignore" then ns.Thread.Ignore(c)
        elseif k == "forget" then ns.Thread.Forget(c)
        end
    end, 170, { atCursor = true, confirm = { forget = true } })
end

-- The tile's X: the tile sinks away, the conversation stays in the hub.
function Tiles.CloseTile(b)
    local c = b.key and ns.Talk.Get(b.key)
    if not c then return end
    if ns.Convo.Showing(c.key) then ns.Convo.Close() end
    GameTooltip:Hide()
    ns.Talk.Read(c)
    ns.Talk.Close(c)
end

local function tile(i)
    local b = tiles[i]
    if b then return b end
    b = CreateFrame("Button", nil, column)
    b:SetSize(Tiles.SIZE, Tiles.SIZE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    Style.Shell(b, { flat = true, borderPx = 1 })
    b.wash = b:CreateTexture(nil, "ARTWORK")
    b.wash:SetTexture("Interface\\Buttons\\WHITE8X8")
    b.wash:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    b.wash:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    -- Unread light, pulsing in the whisper's color (Tiles.Breathe).
    b.glow = b:CreateTexture(nil, "ARTWORK", nil, -1)
    b.glow:SetTexture(DUI.MEDIA .. "glow.png")
    b.glow:SetBlendMode("ADD")
    b.glow:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    b.glow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.glow:SetAlpha(0)
    b.letter = Style.Text(b, Style.SIZE.head, "CENTER")
    b.letter:SetPoint("CENTER", b, "CENTER", 0, 1)
    -- The initial in its class gradient. A FontString takes one color, so the letter
    -- is drawn SLICES times, each copy clipped to a band and colored by its position
    -- (light at the top, dark at the bottom). Each band runs from its top to the
    -- tile's bottom and the next one overlaps it (frame levels), so only top edges
    -- cut the letter. Separate bands met at fractional pixels and left dark seams.
    b.slices = {}
    local band = (Style.SIZE.head + 6) / Tiles.SLICES
    for i = 1, Tiles.SLICES do
        local clip = CreateFrame("Frame", nil, b)
        clip:SetClipsChildren(true)
        clip:SetFrameLevel(b:GetFrameLevel() + i)
        clip:SetPoint("LEFT", b, "LEFT")
        clip:SetPoint("RIGHT", b, "RIGHT")
        clip:SetPoint("TOP", b, "CENTER", 0, (Style.SIZE.head + 6) / 2 + 1 - (i - 1) * band)
        clip:SetPoint("BOTTOM", b, "BOTTOM")
        local fs = Style.Text(clip, Style.SIZE.head, "CENTER")
        fs:SetPoint("CENTER", b, "CENTER", 0, 1)
        b.slices[i] = fs
    end
    b.count = Style.Text(b, Style.SIZE.tiny, "RIGHT")
    b.count:SetPoint("TOPRIGHT", b, "TOPRIGHT", -3, -2)
    Style.InkText(b.count, "pop")
    b.pin = b:CreateTexture(nil, "OVERLAY")
    b.pin:SetTexture("Interface\\Buttons\\WHITE8X8")
    b.pin:SetHeight(2)
    b.pin:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 1, 1)
    b.pin:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then menu(self) else ns.Convo.Toggle(self.key) end
    end)
    -- A small X on hover closes the tile. The conversation stays in the hub and a
    -- new whisper brings the tile back.
    b.close = W().Close(b, function() Tiles.CloseTile(b) end, Tiles.CLOSE, 8)
    b.close:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.close:SetFrameLevel(b:GetFrameLevel() + Tiles.SLICES + 1)
    b.close:SetAlpha(0)
    b.close:EnableMouse(false)
    local function showClose(on)
        b.close:EnableMouse(on)
        M().Tween(b.close, b.close:GetAlpha(), on and 1 or 0, M().FAST, function(a) b.close:SetAlpha(a) end)
    end
    b.close:HookScript("OnLeave", function() if not b:IsMouseOver() then showClose(false) end end)
    b:SetScript("OnEnter", function(self)
        tip(self)
        showClose(true)
        M().Tween(self.wash, self.wash:GetAlpha(), 1, M().FAST, function(a) self.wash:SetAlpha(a) end)
    end)
    b:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if not self.close:IsMouseOver() then showClose(false) end
        M().Tween(self.wash, self.wash:GetAlpha(), 0, M().FAST, function(a) self.wash:SetAlpha(a) end)
    end)
    tiles[i] = b
    return b
end

-- A class's gradient pair as the accent uses it (dark end lifted by
-- Style.CLASS_LIFT so the letter stays readable), or nil.
local function classPair(token)
    local G = DUI.Gradients
    if not (G and type(token) == "string" and G.Has(token)) then return nil end
    local lo, hi = G.RGB(token)
    local k = Style.CLASS_LIFT
    return { lo[1] + (hi[1] - lo[1]) * k, lo[2] + (hi[2] - lo[2]) * k, lo[3] + (hi[3] - lo[3]) * k }, hi
end

local function paintLetter(b, c)
    -- Class icon instead (per the setting), from the unit frames' icon set.
    local file, l, r, top, bt
    if cfg and cfg.tileArt == "icon" then file, l, r, top, bt = ns.Thread.ClassIcon(c.class) end
    if not b.icon then
        b.icon = b:CreateTexture(nil, "ARTWORK", nil, 1)
        b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
        b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
    end
    b.icon:SetShown(file ~= nil)
    if file then
        b.icon:SetTexture(file)
        b.icon:SetTexCoord(l, r, top, bt)
        b.letter:Hide()
        for _, fs in ipairs(b.slices) do fs:Hide() end
        return
    end
    local text = initial(c)
    local lo, hi = classPair(c.class)
    b.letter:SetShown(lo == nil)
    for i, fs in ipairs(b.slices) do
        fs:SetShown(lo ~= nil)
        if lo then
            local t = (i - 0.5) / #b.slices
            fs:SetText(text)
            fs:SetTextColor(hi[1] + (lo[1] - hi[1]) * t, hi[2] + (lo[2] - hi[2]) * t, hi[3] + (lo[3] - hi[3]) * t)
        end
    end
    if not lo then
        b.letter:SetText(text)
        b.letter:SetTextColor(Style.ClassTextColor(c.class))
    end
end

-- The whisper's color (the game's, or Battle.net's for a bn: conversation), else
-- the accent.
function Tiles.WhisperColor(c)
    local kind = c and type(c.key) == "string" and c.key:find("^bn:") and "BN_WHISPER" or "WHISPER"
    local info = type(ChatTypeInfo) == "table" and ChatTypeInfo[kind]
    if type(info) == "table" and type(info.r) == "number" then return { info.r, info.g, info.b } end
    return { Style.Accent() }
end

-- Unread: the border takes the whisper color and a light inside pulses with the
-- chat's unread tabs (Feel's pulse) until read, then fades. Easy to catch out of
-- the corner of your eye mid-fight.
local alerting = 0 -- tiles pulsing now
local function paintAlert(b, c, unread)
    if unread == (b.alerting == true) then
        if unread then b.glow:SetVertexColor(unpack(Tiles.WhisperColor(c))) end
        return
    end
    b.alerting = unread or nil
    alerting = alerting + (unread and 1 or -1)
    local a = b.glow:GetAlpha()
    M().Tween(b.glow, a, a) -- stops a fade still running
    if unread then
        b.glow:SetVertexColor(unpack(Tiles.WhisperColor(c)))
    else
        M().Tween(b.glow, b.glow:GetAlpha(), 0, M().NORMAL, function(a) b.glow:SetAlpha(a) end)
    end
end

-- Each pulse step from Feel (k 0-1, 1 with motion off).
function Tiles.Breathe(k)
    if alerting <= 0 then return end
    for _, b in ipairs(tiles) do
        if b.alerting and b:IsShown() then b.glow:SetAlpha(Tiles.GLOW * (0.3 + 0.7 * k)) end
    end
end

local function paintTile(b, c, picked)
    paintLetter(b, c)
    -- Every tile is the same plain dark tile; only the letter carries the class.
    -- Hover brightens it slightly (a faint light, no color).
    b.wash:SetColorTexture(1, 1, 1, 0.06)
    if not b:IsMouseOver() then b.wash:SetAlpha(0) end
    b.count:SetText((c.unread or 0) > 0 and tostring(c.unread) or "")
    Style.InkText(b.count, "pop")
    b.pin:SetShown(c.pinned == true)
    if c.pinned then Style.PaintAccent(b.pin, 1) end
    local unread = (c.unread or 0) > 0
    paintAlert(b, c, unread)
    Style.SetShellColors(Style.GetShell(b), picked and { Style.Accent() } or unread and Tiles.WhisperColor(c) or nil)
end

-- ---------------------------------------------------------------------
-- The row
-- ---------------------------------------------------------------------

local count = 0 -- tiles currently in the row

function Tiles.Refresh()
    if not column then return end
    local on = ns.Talk.On()
    -- The header bubble (Box.lua) shows the unread count.
    ns.Box.PaintActions(ns.Talk.Unread())
    local list, n = on and ns.Talk.List() or {}, 0
    local most = cfg and cfg.tilesMax or Tiles.MAX
    for _, c in ipairs(list) do
        if not c.closed and n < most then
            n = n + 1
            local b = tile(n)
            local wasKey, wasCount = shownKeys[b], b.unread
            shownKeys[b] = c.key
            b.key = c.key
            b.unread = c.unread or 0
            paintTile(b, c, ns.Convo.Showing(c.key))
            b:Show()
            b:SetAlpha(1)
            -- A different conversation in this slot: it rises again from below.
            if wasKey ~= c.key then b.rise, b.goal = 0, nil end
            -- Pop the count when it goes up.
            if wasKey == c.key and (b.unread or 0) > (wasCount or 0) and M().On() then M().Pop(b.count) end
        end
    end
    for i = n + 1, #tiles do
        local b = tiles[i]
        if b:IsShown() then
            shownKeys[b] = nil
            M().Tween(b, b:GetAlpha(), 0, M().FAST, function(a) b:SetAlpha(a) end, function()
                if not shownKeys[b] then b:Hide(); b:SetAlpha(1) end
            end)
        end
    end
    count = n
    Tiles.shown = n
    Tiles.Update()
    Tiles.Layout()
end

function Tiles.Size() return cfg and cfg.tileSize or Tiles.SIZE end

local function smooth(t) return t * t * (3 - 2 * t) end

-- Lays everything out for the current slide positions: each tile as high as its
-- turn in the stagger, the conversation as wide as its slide.
function Tiles.Layout()
    if not column then return end
    local panel = ns.Chat.Panel()
    local left = Tiles.Side() == "left"
    local size = Tiles.Size()
    local step = size + Tiles.GAP
    -- Row bottom on the chat's top, at the corner.
    column:ClearAllPoints()
    if left then column:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 0, 0)
    else column:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0, 0) end
    column:SetHeight(size + Tiles.LIFT + 2)
    column:SetWidth(math.max(1, count * step))
    -- Each tile at its own height. Risen (or rising) tiles take the slots from the
    -- corner, in order.
    local slot, any = 0, false
    for i = 1, count do
        local b = tiles[i]
        local r = b.rise or 0
        if r > 0 or b.goal == 1 then
            slot = slot + 1
            any = any or r > 0
            local k = smooth(r)
            local y = Tiles.LIFT - (1 - k) * (size + Tiles.LIFT + 2)
            local x = (slot - 1) * step
            b:SetSize(size, size)
            b:ClearAllPoints()
            if left then b:SetPoint("BOTTOMLEFT", column, "BOTTOMLEFT", x, y)
            else b:SetPoint("BOTTOMRIGHT", column, "BOTTOMRIGHT", -x, y) end
            b:EnableMouse(k > 0.5)
            b.slotted = true
        else
            b:EnableMouse(false)
            b.slotted = nil
        end
        b:SetShown(b.slotted == true)
    end
    column:SetShown(any)
    -- While dragging or resizing, the mouse owns the drawer.
    if ns.Convo.moving or ns.Convo.sizing then return end
    local cw, ch = ns.Convo.Size()
    local pc = cardSlide.p
    local at = ns.Convo.At()
    local card = ns.Convo.Card()
    drawer:ClearAllPoints()
    if card then card:ClearAllPoints() end
    if at == "side" then
        -- The conversation slides out of the chat's side, at the chat's height.
        if left then drawer:SetPoint("TOPRIGHT", panel, "TOPLEFT", -Tiles.JOIN, 0)
        else drawer:SetPoint("TOPLEFT", panel, "TOPRIGHT", Tiles.JOIN, 0) end
        drawer:SetHeight(math.max(1, ns.Chat.PanelHeight()))
        drawer:SetWidth(math.max(0.01, pc * cw))
        if card then
            if left then card:SetPoint("TOPRIGHT", drawer, "TOPRIGHT")
            else card:SetPoint("TOPLEFT", drawer, "TOPLEFT") end
        end
    else
        local spot = at == "free" and ns.Convo.Spot()
        if spot then
            -- Where it was dragged: it fades in there (using the slide's alpha).
            local s, u = drawer:GetEffectiveScale(), UIParent:GetEffectiveScale()
            local k = (s and s > 0 and u) and u / s or 1
            drawer:SetPoint("CENTER", UIParent, "CENTER", spot[1] * k, spot[2] * k)
            drawer:SetHeight(ch)
        else
            -- Above the tile row at the chat's corner, rising out of it.
            local above = Tiles.AboveTiles()
            if left then drawer:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 0, above)
            else drawer:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0, above) end
            drawer:SetHeight(math.max(0.01, pc * ch))
        end
        drawer:SetWidth(cw)
        if card then card:SetPoint("BOTTOMLEFT", drawer, "BOTTOMLEFT") end
    end
    drawer:SetAlpha(pc)
    drawer:SetShown(pc > 0)
end

-- How far the tile row reaches above the chat, gap included. The preview and a
-- conversation opened above sit on it.
function Tiles.AboveTiles() return Tiles.Size() + Tiles.LIFT + Tiles.GAP + 2 end

-- Should all tiles be up? Hovering the chat or tiles (plus a short delay), or a
-- conversation is open.
function Tiles.Over() return column ~= nil and column:IsShown() and column:IsMouseOver() end

-- Floating, the tile row follows the panel's alpha, but a new whisper shows it
-- anyway for as long as the preview, fading in, then back to the panel's alpha.
local peek, peekGoal, peekUntil = 0, 0, 0

local function paintPeek()
    if peek <= 0 then
        column:SetIgnoreParentAlpha(false)
        column:SetAlpha(1)
        return
    end
    local panelNow = ns.Chat.float * (DUI.Fade.State("Chat.chat") or 1)
    column:SetIgnoreParentAlpha(true)
    column:SetAlpha(math.max(peek, panelNow))
end

local function peekTo(goal, dur)
    peekGoal = goal
    M().Tween("chatTilesPeek", peek, goal, dur, function(v) peek = v; paintPeek() end)
end

function Tiles.Peek()
    if not column then return end
    peekUntil = GetTime() + (cfg and cfg.previewTime or Tiles.PREVIEW)
    peekTo(1, InCombatLockdown() and M().FAST or M().NORMAL)
end

function Tiles.All(over)
    if not (column and ns.Talk.On()) then return false end
    local now = GetTime()
    if over or (column:IsShown() and column:IsMouseOver()) then awakeUntil = now + Tiles.AWAKE end
    return now < awakeUntil or ns.Convo.Key() ~= nil
end

local riseKeys = setmetatable({}, { __mode = "k" })
local function riseTo(b, goal, delay)
    b.goal = goal
    if InCombatLockdown() or not M().On() then
        b.rise = goal
        Tiles.Layout()
        return
    end
    local key = riseKeys[b] or {}
    riseKeys[b] = key
    local function go()
        if b.goal ~= goal then return end
        M().Tween(key, b.rise or 0, goal, Tiles.SLIDE, function(v) b.rise = v; Tiles.Layout() end, function()
            -- Light for a new whisper only; hovering to raise them all stays quiet.
            local c = b.key and ns.Talk.Get(b.key)
            if goal == 1 and b.goal == 1 and c and (c.unread or 0) > 0 then Tiles.flourish() end
        end)
    end
    if delay and delay > 0 then C_Timer.After(delay, go) else go() end
end

-- From the chat's watcher (Chat.UpdateFade), and right away for a new whisper:
-- each tile up if all are wanted or it has unread, else down. In combat they
-- move at once; nothing waits on a slide there.
function Tiles.Update(over)
    if not column then return end
    if peek > 0 then
        if peekGoal == 1 and GetTime() >= peekUntil then peekTo(0, M().NORMAL) else paintPeek() end
    end
    local all = Tiles.All(over)
    local on = ns.Talk.On()
    local n = 0
    for i = 1, count do
        local b = tiles[i]
        local c = b.key and ns.Talk.Get(b.key)
        local goal = (on and (all or (c and (c.unread or 0) > 0))) and 1 or 0
        if b.goal ~= goal then
            if goal == 1 then n = n + 1 end
            -- Each rise lays out the row as it goes (riseTo), so a quiet pass (the watcher,
            -- 4 per second) changes nothing.
            riseTo(b, goal, goal == 1 and (n - 1) * Tiles.STAGGER or 0)
        end
    end
end

-- The conversation sliding out (Convo.lua) or back in (done once it's in).
function Tiles.Card(open, done)
    if not drawer then if done then done() end return end
    Tiles.cardDone = done
    if open then awakeUntil = GetTime() + Tiles.AWAKE; Tiles.Update() end
    if InCombatLockdown() then
        cardSlide:Jump(open and 1 or 0)
        Tiles.cardDone = nil
        if done and not open then done() end
    else
        cardSlide:To(open and 1 or 0)
    end
end

-- One light along the chat's top edge as tiles arrive (once per moment, however
-- many land).
local lastFlourish = 0
function Tiles.flourish()
    if not (sweep and M().On()) or InCombatLockdown() then return end
    if GetTime() - lastFlourish < 0.5 then return end
    lastFlourish = GetTime()
    local r, g, b = Style.Accent()
    M().Sweep(sweep, Tiles.edge, { width = 90, dur = 0.6, alpha = 0.55, color = { r, g, b } })
end

-- ---------------------------------------------------------------------
-- The preview
-- ---------------------------------------------------------------------

local function buildPreview()
    preview = CreateFrame("Button", nil, ns.Chat.Holder())
    preview:SetSize(Tiles.PREVIEW_W, 58)
    preview:SetFrameStrata("HIGH") -- above action bars and unit frames, like the card
    Style.Shell(preview, { window = true })
    preview.name = Style.Text(preview, Style.SIZE.body, "LEFT")
    preview.name:SetPoint("TOPLEFT", preview, "TOPLEFT", 10, -8)
    preview.name:SetPoint("RIGHT", preview, "RIGHT", -10, 0)
    preview.text = Style.Text(preview, Style.SIZE.small, "LEFT")
    preview.text:SetPoint("TOPLEFT", preview.name, "BOTTOMLEFT", 0, -4)
    preview.text:SetPoint("RIGHT", preview, "RIGHT", -10, 0)
    preview.text:SetMaxLines(2)
    Style.InkText(preview.text, "TEXT")
    preview.bar = W().Bar(preview, W().BAR_H)
    preview.bar:SetPoint("BOTTOMLEFT", preview, "BOTTOMLEFT", 10, 6)
    preview.bar:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -10, 6)
    preview.bar:SetMinMaxValues(0, 1)
    preview:SetScript("OnClick", function(self)
        Tiles.HidePreview()
        if self.key then ns.Convo.Open(self.key) end
    end)
    preview:Hide()
end

function Tiles.HidePreview()
    if not (preview and preview:IsShown()) then return end
    preview.goal = nil
    M().Tween(preview, preview:GetAlpha(), 0, M().FAST, function(a) preview:SetAlpha(a) end, function()
        if not preview.goal then preview:Hide() end
    end)
end

function Tiles.Preview(c)
    if not (cfg and cfg.whisperPreview ~= false) or ns.Convo.Showing(c.key) then return end
    if not preview then buildPreview() end
    local last = c.msgs[#c.msgs]
    if not last then return end
    local fight = InCombatLockdown()
    preview.key = c.key
    preview.goal = fight and Tiles.FIGHT_ALPHA or 1
    preview.name:SetText(ns.Thread.Name(c))
    preview.name:SetTextColor(Style.ClassTextColor(c.class))
    preview.text:SetText(last.text)
    W().BarAccent(preview.bar)
    -- Above the tiles, or above an open conversation card, never over it.
    preview:ClearAllPoints()
    local panel = ns.Chat.Panel()
    local above = Tiles.AboveTiles()
    -- A conversation open above the tiles: the preview sits on it.
    if ns.Convo.Key() and ns.Convo.At() == "above" then above = above + select(2, ns.Convo.Size()) + Tiles.GAP end
    if Tiles.Side() == "left" then preview:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 0, above)
    else preview:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0, above) end
    preview:SetAlpha(0)
    preview:Show()
    local dur = fight and M().FAST or M().NORMAL
    M().Tween(preview, 0, preview.goal, dur, function(a) preview:SetAlpha(a) end)
    if not fight then M().SlideIn(preview, -12, 0, M().NORMAL) end
    -- The bar drains while it's up, then it goes.
    local key = c.key
    M().Tween(preview.bar, 1, 0, cfg.previewTime or Tiles.PREVIEW, function(v) preview.bar:SetValue(v) end, function()
        if preview.key == key then Tiles.HidePreview() end
    end)
end

-- ---------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------

function Tiles.Build()
    if column then return end
    local panel = ns.Chat.Panel()
    -- The tile row has no frame of its own. Its bottom is the chat's top, so a sunk
    -- tile below it is out of sight.
    column = CreateFrame("Frame", "DaylightUIChatTiles", panel)
    column:SetClipsChildren(true)
    column:SetSize(1, 1)
    column:Hide()
    -- The conversation's slide frame.
    drawer = CreateFrame("Frame", "DaylightUIChatDrawer", panel)
    drawer:SetClipsChildren(true)
    drawer:SetSize(0.01, 1)
    drawer:Hide()
    -- The chat's top edge, for the arrival light.
    Tiles.edge = CreateFrame("Frame", nil, panel)
    Tiles.edge:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -1)
    Tiles.edge:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -1)
    Tiles.edge:SetHeight(4)
    sweep = Tiles.edge:CreateTexture(nil, "OVERLAY")
    sweep:SetTexture(DUI.MEDIA .. "glow.png")
    sweep:SetBlendMode("ADD")
    sweep:SetHeight(12)
    sweep:Hide()
    cardSlide = M().Slider(function() Tiles.Layout() end, { p = 0, dur = Tiles.SLIDE, parent = panel,
        done = function(sl)
            local fn = Tiles.cardDone
            Tiles.cardDone = nil
            if fn and sl.p == 0 then fn() end
        end })
    DUI.On("ChatTalk", function(key, what)
        Tiles.Refresh()
        ns.Convo.Changed(key, what)
        ns.Hub.Changed(key, what)
        if what == "heard" and ns.Talk.On() then
            local c = ns.Talk.Get(key)
            Tiles.Update()
            if c and (c.unread or 0) > 0 then Tiles.Peek() end
            if c then Tiles.Preview(c) end
        end
    end)
end

-- (The whisper bubble lives in the chat's header: Box.BuildActions.)
function Tiles.Place() end

function Tiles.Repaint()
    Tiles.Refresh()
end
