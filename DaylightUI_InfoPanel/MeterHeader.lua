-- A meter's header. Left: mode icon, mode name and the fight's name. Right:
-- the group total and fight length, which cross-fade to the buttons (fight,
-- mode, report, reset, new window, options) while the mouse is over the meter.
-- cfg.header "hover" shows it over the top row only on mouseover.
--
-- Redrawn every tick in combat so the clock runs. A secret total goes
-- straight into its text.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style = DUI.Style

local Header = {}
ns.MeterHeader = Header

Header.H = 20                 -- as tall as an icon button (W.ICON_BUTTON)
Header.BACK = 1               -- the band under a "hover" header, over the top row (solid: no row shows through)
Header.ICON = 14
-- The buttons, left to right: their icon (Media/) and their name. The mode
-- and the fight are words to click (links), not icons.
Header.BUTTONS = {
    { key = "report", icon = "ui-meter-report.png", tip = "Report to chat" },
    { key = "reset", icon = "ui-reset.png", tip = "Reset every fight" },
    { key = "new", icon = "ui-meter-new.png", tip = "New meter window" },
    { key = "options", icon = "ui-options.png", tip = "Options" },
}

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- How tall a meter's header is in its layout: "hover" lies over the rows.
function Header.Height(cfg)
    return (cfg and cfg.header == "hover") and 0 or Header.H
end

-- actions[key] = fn(button): what each button does (the meter's).
function Header.New(area, actions)
    local W = DUI.Widgets
    local h = CreateFrame("Frame", nil, area)
    h:SetFrameLevel(area:GetFrameLevel() + 10)
    h:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
    h:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, 0)
    h:SetHeight(Header.H)
    -- Everything sits on an inner frame pinned to h's bottom: in "hover"
    -- mode h clips it and grows down from the top edge (a blind rolling
    -- down over the first row), never fading words over words.
    h:SetClipsChildren(true)
    local p = CreateFrame("Frame", nil, h)
    p:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 0)
    p:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
    p:SetHeight(Header.H)
    h.inner = p
    h.back = p:CreateTexture(nil, "BACKGROUND")
    h.back:SetAllPoints(p)
    local c = Style.BACKGROUND
    h.back:SetColorTexture(c[1], c[2], c[3], Header.BACK)
    h.back:Hide()
    h.icon = p:CreateTexture(nil, "ARTWORK")
    h.icon:SetSize(Header.ICON, Header.ICON)
    h.icon:SetPoint("LEFT", p, "LEFT", 2, 0)
    -- The mode and the fight: quiet words that open their menus (W.Link).
    local function link(key, size, ink)
        local b = W.Link(p, size, { own = true })
        b.kind = key
        b:SetScript("OnClick", function(self)
            if W.menuOwner == self then W.CloseMenu() return end
            local act = actions[key]
            if act then act(self) end
        end)
        Style.DressText(b.text, size)
        Style.InkText(b.text, ink)
        b.text:SetWordWrap(false)
        return b
    end
    h.modeLink = link("mode", Style.SIZE.tiny, "LABEL")
    h.modeLink:SetPoint("LEFT", h.icon, "RIGHT", 5, 0)
    h.mode = h.modeLink.text
    h.fightLink = link("fight", Style.SIZE.small, "TEXT")
    h.fightLink:SetPoint("LEFT", h.modeLink, "RIGHT", 6, 0)
    h.fight = h.fightLink.text
    h.fight:ClearAllPoints()
    h.fight:SetPoint("LEFT", h.fightLink, "LEFT", 0, 0)
    h.fight:SetPoint("RIGHT", h.fightLink, "RIGHT", 0, 0)
    -- The right side: the total and the clock, or the buttons.
    h.info = CreateFrame("Frame", nil, p)
    h.info:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 0)
    h.info:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
    h.timer = Style.Text(h.info, Style.SIZE.small, "RIGHT")
    h.timer:SetPoint("RIGHT", h.info, "RIGHT", -2, 0)
    Style.InkText(h.timer, "VALUE")
    h.total = Style.Text(h.info, Style.SIZE.small, "RIGHT")
    h.total:SetPoint("RIGHT", h.timer, "LEFT", -8, 0)
    h.total:Hide()
    h.tools = CreateFrame("Frame", nil, p)
    h.tools:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 0)
    h.tools:SetHeight(Header.H)
    h.tools:SetAlpha(0)
    h.tools:Hide()
    h.buttons = {}
    local prev
    for i = #Header.BUTTONS, 1, -1 do
        local def = Header.BUTTONS[i]
        local b = W.IconButton(h.tools, def.icon, L[def.tip], function(self)
            if W.menuOwner == self then W.CloseMenu() return end
            local act = actions[def.key]
            if act then act(self) end
        end)
        b.kind = def.key
        if prev then b:SetPoint("RIGHT", prev, "LEFT", 0, 0) else b:SetPoint("RIGHT", h.tools, "RIGHT", 0, 0) end
        prev = b
        h.buttons[def.key] = b
    end
    h.buttons.mode, h.buttons.fight = h.modeLink, h.fightLink
    h.tools:SetWidth(#Header.BUTTONS * W.ICON_BUTTON)
    Header.PlaceFight(h, true)
    h.hovered = false
    return h
end

-- Lays it out for its setting: above the rows, or over them on hover only.
function Header.Apply(h, cfg)
    local over = cfg.header == "hover"
    h.over = over
    h.fullH = Header.H
    h.inner:SetHeight(h.fullH)
    h.back:SetShown(over)
    h.total:SetShown(cfg.headerTotal == true)
    Header.PlaceFight(h)
    if over then
        if not h.hovered then Header.Blind(h, 0, true) end
    else
        DUI.Motion.Tween(h.inner, 0, 0, 0)
        h:SetHeight(h.fullH)
        h:SetAlpha(1)
        h:Show()
    end
end

-- The words, the icon and the numbers, from the meter (m) as it is now.
function Header.Update(h, m, cfg, session)
    local md = m.Mode()
    h.icon:SetTexture(ns.Meter.ICON(md.icon or "damage"))
    h.icon:SetVertexColor(Style.Accent())
    h.modeLink.SetLabel(md.label)
    local name, length = m.FightTitle()
    h.fight:SetText(name or "")
    if not m.fight and not m.Sample() and C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds then
        local st = m.SessionType()
        if st ~= nil then
            local ok, s = pcall(C_DamageMeter.GetSessionDurationSeconds, st)
            if ok and type(s) == "number" then length = s end   -- (none: the fight list's stays)
        end
    end
    -- None from the game's clock or the fight list: the fight's own length.
    if type(length) ~= "number" and m.Seconds then length = m.Seconds(session) end
    if type(length) == "number" and not isSecret(length) then
        h.timer:SetText(DUI.FormatClock(length))
    else
        h.timer:SetText("")
    end
    Header.PlaceFight(h)   -- the clock's width changed
    if cfg.headerTotal == true then
        local t   -- (secret in a fight: only ever asked whether it's there)
        if type(session) == "table" then t = session.totalAmount end
        if type(t) == "nil" then t = 0 end
        h.total:SetText(ns.Meter.Short(t))
        Style.InkText(h.total, "pop")
    end
end

-- The fight's name reaches to the clock (or the total) at rest, and to the
-- buttons while they're out: never cut short by buttons that aren't there.
function Header.PlaceFight(h, snap)
    -- Measured from the header's own edge: the clock's text can be empty.
    local room = 6
    if h.hovered then
        room = room + h.tools:GetWidth()
    else
        local w = h.timer:GetStringWidth()
        if type(w) == "number" and w > 0 then room = room + w + 2 end
        if h.total:IsShown() then
            local t = h.total:GetStringWidth()
            if type(t) == "number" and t > 0 then room = room + t + 8 end
        end
    end
    -- The link is as wide as its words, up to the room left (glides there).
    local function place(r)
        h.fightRoom = r
        h.fightLink:SetPoint("RIGHT", h.inner, "RIGHT", -r, 0)
    end
    if snap or h.fightRoom == nil then
        DUI.Motion.Tween(h.fightLink, 0, 0, 0)
        place(room)
    elseif math.abs(h.fightRoom - room) > 0.5 then
        DUI.Motion.Tween(h.fightLink, h.fightRoom, room, DUI.Motion.FAST, place)
    end
end

-- A "hover" header rolling down (to 1) or back up (to 0) from the top
-- edge, NORMAL, from wherever it is; snap: at once.
function Header.Blind(h, to, snap)
    local function step(v)
        h.blindAt = v
        h:SetHeight(math.max(0.01, v * (h.fullH or Header.H)))
        h:SetAlpha(math.min(1, v * 2))
    end
    local from = h.blindAt or (h:IsShown() and 1 or 0)
    if to > 0 then h:Show() end
    local done = to <= 0 and function() h:Hide() end or nil
    if snap then
        DUI.Motion.Tween(h.inner, to, to, 0)
        step(to)
        if done then done() end
        return
    end
    DUI.Motion.Tween(h.inner, from, to, DUI.Motion.NORMAL, step, done)
end

-- The mouse came or went: the buttons cross-fade with the clock (and a
-- "hover" header comes and goes whole). FAST.
function Header.Hover(h, on)
    on = on == true
    if h.hovered == on then return end
    h.hovered = on
    Header.PlaceFight(h)
    local M = DUI.Motion
    M.AlphaTo(h.tools, on and 1 or 0, M.FAST, true)
    M.AlphaTo(h.info, on and 0 or 1, M.FAST)
    if h.over then Header.Blind(h, on and 1 or 0) end
end
