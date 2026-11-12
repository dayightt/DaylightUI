-- Chat motion. Everything that moves here is ours, layered around the game's
-- lines; the lines and their fade stay the game's, and nothing is written on the
-- chat frames.
-- * The line under the selected tab glides to the next selected tab.
-- * A tab with unread lines (the game's own alert, its flash art cleared) pulses
--   in the accent, a whisper tab in the whisper color.
-- * The edit box outline eases to the color of the channel you're typing in.
-- * An incoming whisper sends one light around the panel border.
-- * Scrolled up, a "New messages" pill fades in over the bottom. The game's own
--   jump-to-bottom button (art cleared) sits under it, so the click is the game's.
-- * Scrolled up, a thin scroll bar shows your position until you're back at the
--   newest line.
-- * A level-up, achievement or epic item sends one light along the tab line.
-- * The panel border lights up while the resize grip is dragged.
-- * Floating, each new line fades in (alpha only, on the game's line).

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel
local L = DUI.L

local Feel = {}
ns.Feel = Feel

Feel.BREATH = 2.4 -- seconds per pulse of an unread tab; slow and calm, a loop
Feel.SHINE = { width = 90, height = 14, dur = 0.6, alpha = 0.55 } -- big-moment light (the XP bar's rep shine)
Feel.PILL_Y = 6 -- pill over the chat's bottom edge
Feel.BAR_X = 2 -- scroll bar, right of the lines
Feel.BAR_LIT = 0.85 -- thumb alpha in the accent while scrolled up
Feel.EPIC = 4 -- your items of this quality or better light the tab line

local holder, panel, area, tabRow, rule
local gameRow -- Classic tab row on the game's dock; tabRow is the Daylight box's while that's on
local line = {} -- main panel's tab line: { tex, at, row }
local light, trace -- whisper light around the panel
local shine -- big-moment light
local pill -- main panel's pill: { chip, goal, fresh }
local pillButton
local breath = 0

local function M() return DUI.Motion end

-- ---------------------------------------------------------------------
-- Borders easing to a color (the edit box, the panel while resizing)
-- ---------------------------------------------------------------------

local borderNow = setmetatable({}, { __mode = "k" }) -- shell -> its current color
local borderGoal = setmetatable({}, { __mode = "k" })
local borderBufs = setmetatable({}, { __mode = "k" }) -- shell -> its two color tables

-- to is {r, g, b}, or nil for the shell's normal border, restored at the end.
-- A chat panel's normal border is its Border color (Chat.BorderRest), eased back
-- to and fully repainted at the end (Chat.PaintBorder handles the sweep and band).
function Feel.EaseBorder(s, to, dur)
    if not s then return end
    local rest = ns.Chat.BorderRest(s) or Style.BORDER
    local goal = to or rest
    if borderGoal[s] == goal then return end
    borderGoal[s] = goal
    local from = borderNow[s] or rest
    local fr, fg, fb = from[1], from[2], from[3]
    -- Two tables per shell used alternately instead of a new one per frame: the shell
    -- keeps the last one and compares the next by value.
    local bufs = borderBufs[s]
    if not bufs then bufs = { {}, {}, n = 1 }; borderBufs[s] = bufs end
    M().Tween(s, 0, 1, dur or M().FAST, function(p)
        bufs.n = 3 - bufs.n
        local c = bufs[bufs.n]
        c[1], c[2], c[3] = fr + (goal[1] - fr) * p, fg + (goal[2] - fg) * p, fb + (goal[3] - fb) * p
        borderNow[s] = c
        Style.SetShellColors(s, c)
    end, function()
        if to then return end
        borderNow[s] = nil
        ns.Chat.PaintBorder(s)
    end)
end

-- ---------------------------------------------------------------------
-- The gliding tab line
-- ---------------------------------------------------------------------

local function nums(...)
    for i = 1, select("#", ...) do if type((select(i, ...))) ~= "number" then return false end end
    return true
end

local function rest(g, b)
    g.at = b
    g.tex:ClearAllPoints()
    g.tex:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT")
    g.tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT")
end

-- A separate tab line for another row of tabs.
function Feel.NewLine(row)
    local tex = row:CreateTexture(nil, "OVERLAY")
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    tex:SetHeight(2)
    tex:Hide()
    return { tex = tex, row = row }
end

-- Tab b was just selected: glide the line from under the previous tab (or jump
-- straight there the first time, or if the previous tab is gone).
-- g is its line (Feel.NewLine), else the main panel's.
function Feel.Glide(b, g)
    g = g or line
    local tex, row = g.tex, g.row
    if not tex then return end
    local was = g.at
    tex:Show()
    Style.PaintAccent(tex, 1)
    if not (was and was ~= b and was:IsShown() and M().On()) then rest(g, b); return end
    local x0, y0 = row:GetLeft(), row:GetBottom()
    local fl, fr, tl, tr, ty = was:GetLeft(), was:GetRight(), b:GetLeft(), b:GetRight(), b:GetBottom()
    if not nums(x0, y0, fl, fr, tl, tr, ty) then rest(g, b); return end
    g.at = b
    M().Tween(tex, 0, 1, M().NORMAL, function(p)
        local l, r = fl + (tl - fl) * p, fr + (tr - fr) * p
        tex:ClearAllPoints()
        tex:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", l - x0, ty - y0)
        tex:SetWidth(math.max(0.01, r - l))
    end, function() if g.at == b then rest(g, b) end end)
end

-- ---------------------------------------------------------------------
-- Pulsing unread tabs
-- ---------------------------------------------------------------------

-- The game's own "something new" flag (it flashes the tab glow, which we clear):
-- an unselected tab pulses until you look at it.
function Feel.Alert(tab, cf, b)
    local U = _G.ChatFrameUtil
    local on = not b.picked and type(U) == "table" and type(U.IsTabAlerting) == "function"
        and U.IsTabAlerting(tab) == true
    local color
    if on then
        -- Every watcher tick reuses one color table per tab.
        color = b.alertColor or {}
        b.alertColor = color
        local kind = cf.chatType
        local info = (kind == "WHISPER" or kind == "BN_WHISPER") and type(ChatTypeInfo) == "table"
            and ChatTypeInfo[kind] or nil
        if type(info) == "table" and type(info.r) == "number" then
            color[1], color[2], color[3] = info.r, info.g, info.b
        else
            color[1], color[2], color[3] = Style.Accent()
        end
    end
    if (b.alert ~= nil) ~= (on == true) then
        b.alert = on and color or nil
        if not on then b.Paint(b.hover == true) end
    elseif on then
        b.alert = color
    end
end

local function breatheIn(labels, k, lo)
    for _, b in pairs(labels) do
        local c = b.alert
        if c and not b.hover and b:IsShown() then
            b.text:SetTextColor(lo[1] + (c[1] - lo[1]) * k, lo[2] + (c[2] - lo[2]) * k, lo[3] + (c[3] - lo[3]) * k)
        end
    end
end

local function breathe(dt)
    breath = (breath + (dt or 0)) % Feel.BREATH
    local k = M().On() and (0.5 - 0.5 * math.cos(breath / Feel.BREATH * 2 * math.pi)) or 1
    local lo = Style.INK.LABEL
    breatheIn(ns.Chat.Labels(), k, lo)
    breatheIn(ns.Box.Labels(), k, lo)
    ns.Tiles.Breathe(k) -- unread whisper tiles pulse with them
end

-- ---------------------------------------------------------------------
-- The edit box in its channel's color
-- ---------------------------------------------------------------------

local backs = setmetatable({}, { __mode = "k" }) -- game's edit box -> our shell behind it
local typedTo = setmetatable({}, { __mode = "k" })

function Feel.InputBack(eb, back) backs[eb] = back end

-- Color of the box's target: the game's own (ChatTypeInfo), channels by number.
function Feel.ChannelColor(eb)
    local kind = eb.GetAttribute and eb:GetAttribute("chatType")
    if type(kind) ~= "string" or (issecretvalue and issecretvalue(kind)) then return nil end
    local info = type(ChatTypeInfo) == "table" and ChatTypeInfo or {}
    local entry
    if kind == "CHANNEL" then
        local target = eb:GetAttribute("channelTarget")
        if type(target) == "number" or type(target) == "string" then entry = info["CHANNEL" .. target] end
    end
    entry = entry or info[kind]
    if type(entry) ~= "table" or type(entry.r) ~= "number" then return nil end
    return kind, { entry.r, entry.g, entry.b }
end

-- Checked every frame while the box is ours, so a channel change eases over.
function Feel.InputColor(eb, typing)
    local back = backs[eb]
    if not (back and typing) then return end
    local kind, color = Feel.ChannelColor(eb)
    local key = kind and (kind .. (kind == "CHANNEL" and tostring(eb:GetAttribute("channelTarget")) or ""))
    if key == typedTo[eb] then return end
    typedTo[eb] = key
    Feel.EaseBorder(Style.GetShell(back), color, M().FAST)
end

-- ---------------------------------------------------------------------
-- The whisper light
-- ---------------------------------------------------------------------

-- One light around the panel border, then it fades. Parented to the holder so a
-- floating chat still shows where the whisper landed.
function Feel.Whisper()
    if not (trace and M().On()) then return end
    light:SetAlpha(1)
    trace.Snap(0)
    M().Tween(trace, 0, 1, M().SLOW, function(p) trace.Draw(p, true) end, function()
        M().Tween(light, 1, 0, M().SLOW, function(a) light:SetAlpha(a) end, function() trace.Draw(0) end)
    end)
end

-- ---------------------------------------------------------------------
-- New messages while scrolled up
-- ---------------------------------------------------------------------

local jumps = setmetatable({}, { __mode = "k" }) -- the game's jump buttons, restyled

local function regions(f, ...)
    if type(f) ~= "table" or not f.GetRegions then return end
    for i = 1, select("#", f:GetRegions()) do
        local r = select(i, f:GetRegions())
        if type(r) == "table" and r.GetObjectType and r:GetObjectType() == "Texture" then r:SetTexture(nil) end
    end
end

-- The game's jump-to-bottom button with its art cleared (the game still shows,
-- fades and flashes it). It takes no clicks until it's under our pill.
function Feel.DressJump(btn)
    if type(btn) ~= "table" or jumps[btn] or not btn.HookScript then return end
    jumps[btn] = true
    regions(btn)
    if type(btn.Flash) == "table" then
        if btn.Flash.GetObjectType and btn.Flash:GetObjectType() == "Texture" then btn.Flash:SetTexture(nil)
        else regions(btn.Flash) end
    end
    btn:EnableMouse(false)
    btn:HookScript("OnEnter", function() if pill and pill.goal then pill.chip:GetScript("OnEnter")(pill.chip) end end)
    btn:HookScript("OnLeave", function() if pill then pill.chip:GetScript("OnLeave")(pill.chip) end end)
    btn:HookScript("OnClick", function() if DUI.Sound then DUI.Sound.Play("click") end end)
end

local function showPill(p, on)
    if p.goal == on then return end
    p.goal = on
    local chip = p.chip
    if on then
        chip:SetAlpha(0)
        chip:Show()
    end
    M().Tween(chip, chip:GetAlpha(), on and 1 or 0, M().FAST, function(a) chip:SetAlpha(a) end,
        function() if not p.goal then chip:Hide() end end)
    if on then M().SlideIn(chip, 0, -6, M().NORMAL) end
end

-- Every watcher tick; the label is only rewritten when it changes.
local function pillWords(p)
    local words = p.fresh and L["New messages"] or L["Newest"]
    if p.chip.words ~= words then
        p.chip.words = words
        p.chip.text:SetText(words)
        p.chip.FitWidth()
    end
end

-- A pill over area. onClick is the Daylight box's; in Classic the game's button
-- sits under it for the click (Feel.Pill).
function Feel.NewPill(parent, area, onClick)
    local chip = DUI.Widgets.Chip(parent, L["Newest"])
    chip:SetFrameStrata("MEDIUM") -- over the chat lines (LOW), like the grip
    chip:EnableMouse(false)
    chip:SetScript("OnClick", onClick)
    chip:SetPoint("BOTTOM", area, "BOTTOM", 0, Feel.PILL_Y)
    chip.FitWidth()
    chip:Hide()
    return { chip = chip }
end

-- A window's scroll bar. The game counts in messages from the newest (0), the bar
-- from the oldest, so the thumb sits at the bottom at the newest line. Hidden at
-- rest: the chat never closes, so its OnUpdate must not run all the time.
local bars = setmetatable({}, { __mode = "k" })

function Feel.Bar(cf) return bars[cf] end

local function barOf(cf, parent)
    if type(cf) ~= "table" then return nil end
    local bar = bars[cf]
    if bar then return bar end
    if type(cf.GetMaxScrollRange) ~= "function" or type(cf.GetScrollOffset) ~= "function"
        or type(cf.SetScrollOffset) ~= "function" or type(cf.GetNumVisibleLines) ~= "function" then
        return nil
    end
    bar = DUI.Widgets.Scroll(cf, { parent = parent, x = Feel.BAR_X, wheel = false,
        read = function()
            local max = cf:GetMaxScrollRange()
            return max - cf:GetScrollOffset(), max, cf:GetNumVisibleLines()
        end,
        write = function(v) cf:SetScrollOffset(math.floor(cf:GetMaxScrollRange() - v + 0.5)) end })
    bar:Hide()
    bars[cf] = bar
    return bar
end

-- Accent-colored while scrolled up: the usual pale thumb is meant to go unnoticed,
-- this one is meant to be seen.
local function wake(bar, up)
    local W = DUI.Widgets
    bar.leave = nil
    bar:Show()
    if up then
        local r, g, b = Style.Accent()
        W.Tint(bar.thumb, { r, g, b, Feel.BAR_LIT })
        bar.lit = true
    elseif bar.lit then
        W.Tint(bar.thumb, W.SCROLL.thumb)
        bar.lit = nil
    end
    bar.Wake()
end

-- From the watcher: the bar stays while scrolled up or hovering the lines, then
-- fades out like any W.Scroll and gets hidden.
local function trackBar(p, cf, up)
    local bar = barOf(cf, ns.Box.IsList(cf) and cf or p.chip:GetParent())
    if p.bar and p.bar ~= bar then p.bar:Hide() end
    p.bar = bar
    if not bar then return end
    if up or cf:IsMouseOver() == true or (bar:IsShown() and bar:IsMouseOver() == true) then
        wake(bar, up)
    elseif bar:IsShown() then
        local now = GetTime()
        bar.leave = bar.leave or now + DUI.Widgets.SCROLL.linger + M().SLOW
        if now >= bar.leave then bar:Hide() end
    end
end

-- A box list scrolled (wheel, keys, pill): update the bar right away.
function Feel.Scrolled(cf)
    local bar = barOf(cf, cf)
    if bar then wake(bar, not cf:AtBottom()) end
end

-- Daylight chat box lists: the pill is the button.
function Feel.ListPill(p, cf)
    local up = cf:IsShown() and not cf:AtBottom()
    if not up then p.fresh = nil end
    p.chip:EnableMouse(up)
    trackBar(p, cf, up)
    pillWords(p)
    showPill(p, up)
end

-- A line for the current tab while scrolled up.
function Feel.Line(p)
    p = p or pill
    if p and p.goal then p.fresh = true end
end

-- From the watcher: the pill over the selected docked window while it's not at
-- the newest line, with the game's button under it for the click.
function Feel.Pill()
    if not pill then return end
    local cf = ns.Chat.Selected()
    if cf ~= nil and cf == ns.Box.Frame() then
        if pillButton then pillButton:EnableMouse(false); pillButton = nil end
        Feel.ListPill(pill, cf)
        return
    end
    pill.chip:EnableMouse(false)
    local btn = type(cf) == "table" and cf.ScrollToBottomButton
    local docked = type(cf) == "table" and (cf == _G.ChatFrame1 or cf.isDocked)
    local up = docked and jumps[btn] and type(cf.AtBottom) == "function" and not cf:AtBottom()
    if not up then pill.fresh = nil end
    if pillButton and pillButton ~= btn then pillButton:EnableMouse(false); pillButton = nil end
    if up and btn ~= pillButton then
        pillButton = btn
        btn:ClearAllPoints()
        btn:SetAllPoints(pill.chip)
    end
    if pillButton then pillButton:EnableMouse(up and true or false) end
    trackBar(pill, cf, up)
    pillWords(pill)
    showPill(pill, up and true or false)
end

-- ---------------------------------------------------------------------
-- Big moments
-- ---------------------------------------------------------------------

function Feel.Shine()
    if not shine then return end
    shine:SetHeight(Feel.SHINE.height)
    local r, g, b = Style.Accent()
    M().Sweep(shine, rule, { width = Feel.SHINE.width, dur = Feel.SHINE.dur, alpha = Feel.SHINE.alpha,
        color = { r, g, b } })
end

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- Your own epic-or-better loot (by the link's quality, once the item is cached).
function Feel.EpicLoot(msg, ...)
    local guid = select(11, ...)
    if secret(msg) or secret(guid) or type(msg) ~= "string" then return false end
    if type(guid) == "string" and type(UnitGUID) == "function" and guid ~= UnitGUID("player") then return false end
    local link = msg:match("|H(item:[^|]+)|h")
    if not link or not (C_Item and C_Item.GetItemInfo) then return false end
    local ok, _, _, quality = pcall(C_Item.GetItemInfo, link)
    return ok and type(quality) == "number" and quality >= Feel.EPIC
end

-- ---------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------

function Feel.Sizing(on, which)
    Feel.EaseBorder(Style.GetShell(which or panel), on and { Style.Accent() } or nil, M().FAST)
end

function Feel.Repaint()
    if line.tex and line.tex:IsShown() then Style.PaintAccent(line.tex, 1) end
    if pill then pill.chip.Paint() end
    local side = ns.Box.side
    if side.line and side.line.tex:IsShown() then Style.PaintAccent(side.line.tex, 1) end
    if side.pill then side.pill.chip.Paint() end
end

-- The row the tab line glides along: the Daylight chat box's (row), or the
-- Classic one on the game's dock (nil).
function Feel.UseRow(row)
    tabRow = row or gameRow
    line.row = tabRow
    if not line.tex then return end
    line.tex:SetParent(tabRow)
    line.tex:Hide()
    line.at = nil
end

-- Exposed for the tests.
function Feel.Parts() return { glider = line.tex, light = light, pill = pill and pill.chip, shine = shine } end

-- ---------------------------------------------------------------------
-- Floating: new lines fade in
-- ---------------------------------------------------------------------

-- Each visible line keeps its message's arrival time (the game's own timestamp,
-- a plain GetTime). Lines younger than Motion.NORMAL ease up from transparent,
-- alpha only, nothing written on the window. The game shows them at full alpha at
-- that age, and its own fade only starts lineTime later.
-- The game redraws through its "display refreshed" callback
-- (ScrollingMessageFrameSecureMixin, meant for addons), so a new line is caught
-- the frame it's drawn and the watcher, running after the game's update, carries
-- the fade on. In combat, under restrictions, or with motion off, lines just show.
local arriving = setmetatable({}, { __mode = "k" }) -- chat frame -> true while a line is fading in

-- Floating, or always in the Daylight chat box: new lines fade in.
local function arriveOn(cf)
    local box = ns.Box.IsList(cf) and ns.Box.LineFadeIn()
    return (ns.Chat.FloatWanted(cf == ns.Box.side.frame) or box) and M().On()
        and not (ns.Chat.fight or InCombatLockdown() or DUI.Restricted())
end

-- Sets each new line of cf to its point in the fade (on = false: all full).
-- Returns true while one is still fading. A line just past the end is set full once.
local function arrive(cf, on)
    local lines = cf.visibleLines
    if type(lines) ~= "table" then return false end
    local now, dur, easing = GetTime(), M().NORMAL, false
    for _, line in ipairs(lines) do
        local info = line.messageInfo
        local ts = type(info) == "table" and info.timestamp
        if type(ts) == "number" and not issecretvalue(ts) and line:IsShown() then
            local t = (now - ts) / dur
            if t < 2 then
                local k = (on and t < 1) and 1 - (1 - math.max(t, 0)) ^ 2 or 1
                line:SetAlpha(k)
                easing = easing or k < 1
            end
        end
    end
    return easing
end

-- Hovering a floating chat brings every line back. The game sets them all to full
-- in one frame, so each is eased up from where it was (Motion.SLOW, with the
-- panel): its alpha is noted before the game's redraw and held from there.
-- In combat, under restrictions, or with motion off, the game's way.
local revealing = setmetatable({}, { __mode = "k" }) -- chat frame -> { at, from = { line -> alpha } }

local function calm()
    return M().On() and not (ns.Chat.fight or InCombatLockdown() or DUI.Restricted())
end

function Feel.Reveal(cf)
    local lines = cf.visibleLines
    if type(lines) ~= "table" or not calm() then return end
    local from = {}
    for _, line in ipairs(lines) do
        local a = line:IsShown() and line:GetAlpha() or 0
        from[line] = (type(a) == "number" and not issecretvalue(a)) and a or 1
    end
    revealing[cf] = { at = GetTime(), from = from }
end

local function reveal(cf, r)
    local t = (GetTime() - r.at) / M().SLOW
    if t >= 1 or not calm() then
        t = 1
        revealing[cf] = nil
    end
    local k = 1 - (1 - math.max(t, 0)) ^ 2
    for _, line in ipairs(cf.visibleLines) do
        if line:IsShown() then
            local a = r.from[line] or 1
            line:SetAlpha(a + (1 - a) * k)
        end
    end
end

-- The game's redraw, with each line set to its own alpha.
local function redrawn(cf)
    local r = revealing[cf]
    if r then reveal(cf, r) end
    if arriveOn(cf) and arrive(cf, true) then arriving[cf] = true end
end

function Feel.WatchLines(cf)
    if type(cf.AddOnDisplayRefreshedCallback) ~= "function" then return end
    cf:AddOnDisplayRefreshedCallback(function(f) DUI.SafeCall(redrawn, f) end)
end

local done = {}
function Feel.Step(dt)
    breathe(dt)
    for cf, r in pairs(revealing) do reveal(cf, r) end
    if not next(arriving) then return end
    for cf in pairs(arriving) do
        if not arrive(cf, arriveOn(cf)) then done[#done + 1] = cf end
    end
    for i = #done, 1, -1 do arriving[done[i]] = nil; done[i] = nil end
end

function Feel.Build(parts)
    holder, panel, area, tabRow, rule = parts.holder, parts.panel, parts.area, parts.tabRow, parts.rule
    gameRow = tabRow
    line = Feel.NewLine(tabRow)
    light = CreateFrame("Frame", nil, holder)
    light:SetAllPoints(panel)
    light:SetFrameLevel(panel:GetFrameLevel() + 5)
    trace = DUI.Widgets.Trace(light, 0, Pixel.Px(panel, 1), "OVERLAY")
    shine = panel:CreateTexture(nil, "OVERLAY")
    shine:SetTexture(DUI.MEDIA .. "glow.png")
    shine:SetBlendMode("ADD")
    shine:Hide()
    -- (in the Daylight chat box the pill handles the click, Feel.Pill)
    pill = Feel.NewPill(holder, area, function()
        local box = ns.Box.Frame()
        if box and ns.Box.On() then box:ScrollToBottom() end
    end)
    for _, e in ipairs(ns.Whisper.EVENTS) do DUI.RegisterEvent(e, Feel.Whisper) end
    for _, e in ipairs({ "PLAYER_LEVEL_UP", "CHAT_MSG_ACHIEVEMENT", "CHAT_MSG_GUILD_ACHIEVEMENT" }) do
        DUI.RegisterEvent(e, Feel.Shine)
    end
    DUI.RegisterEvent("CHAT_MSG_LOOT", function(_, ...) if Feel.EpicLoot(...) then Feel.Shine() end end)
    for _, e in ipairs(ns.Chat.WAKE_EVENTS) do
        DUI.RegisterEvent(e, function(event, ...)
            if pill.goal and ns.Chat.ShowsMain(event, ...) then Feel.Line() end
            local p = ns.Box.side.pill
            if p and p.goal and ns.Box.Shows(ns.Box.side, event, ...) then Feel.Line(p) end
        end)
    end
end
