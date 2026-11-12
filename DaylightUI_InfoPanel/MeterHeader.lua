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
Header.BACK = 0.95            -- the band under a "hover" header, over the top row
Header.ICON = 14
-- The buttons, left to right: their icon (Media/) and their name.
Header.BUTTONS = {
    { key = "fight", icon = "ui-meter-fight.png", tip = "Which fight" },
    { key = "mode", icon = "ui-meter-mode.png", tip = "What it counts" },
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
    h.back = h:CreateTexture(nil, "BACKGROUND")
    h.back:SetAllPoints(h)
    local c = Style.BACKGROUND
    h.back:SetColorTexture(c[1], c[2], c[3], Header.BACK)
    h.back:Hide()
    h.icon = h:CreateTexture(nil, "ARTWORK")
    h.icon:SetSize(Header.ICON, Header.ICON)
    h.icon:SetPoint("LEFT", h, "LEFT", 2, 0)
    h.mode = Style.Text(h, Style.SIZE.tiny, "LEFT")
    h.mode:SetPoint("LEFT", h.icon, "RIGHT", 5, 0)
    Style.InkText(h.mode, "LABEL")
    h.fight = Style.Text(h, Style.SIZE.small, "LEFT")
    h.fight:SetPoint("LEFT", h.mode, "RIGHT", 6, 0)
    h.fight:SetWordWrap(false)
    Style.InkText(h.fight, "TEXT")
    -- The right side: the total and the clock, or the buttons.
    h.info = CreateFrame("Frame", nil, h)
    h.info:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, 0)
    h.info:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
    h.timer = Style.Text(h.info, Style.SIZE.small, "RIGHT")
    h.timer:SetPoint("RIGHT", h.info, "RIGHT", -2, 0)
    Style.InkText(h.timer, "VALUE")
    h.total = Style.Text(h.info, Style.SIZE.small, "RIGHT")
    h.total:SetPoint("RIGHT", h.timer, "LEFT", -8, 0)
    h.total:Hide()
    h.tools = CreateFrame("Frame", nil, h)
    h.tools:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, 0)
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
    h.tools:SetWidth(#Header.BUTTONS * W.ICON_BUTTON)
    Header.PlaceFight(h)
    h.hovered = false
    return h
end

-- Lays it out for its setting: above the rows, or over them on hover only.
function Header.Apply(h, cfg)
    local over = cfg.header == "hover"
    h.over = over
    h.back:SetShown(over)
    h.total:SetShown(cfg.headerTotal == true)
    Header.PlaceFight(h)
    if over then
        if not h.hovered then DUI.Motion.AlphaTo(h, 0, 0, true) end
    else
        h:SetAlpha(1)
        h:Show()
    end
end

-- The words, the icon and the numbers, from the meter (m) as it is now.
function Header.Update(h, m, cfg, session)
    local md = m.Mode()
    h.icon:SetTexture(ns.Meter.ICON(md.icon or "damage"))
    h.icon:SetVertexColor(Style.Accent())
    h.mode:SetText(md.label)
    local name, length = m.FightTitle()
    h.fight:SetText(name or "")
    if not m.fight and not m.Sample() and C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds then
        local st = m.SessionType()
        if st ~= nil then
            local ok, s = pcall(C_DamageMeter.GetSessionDurationSeconds, st)
            if ok then length = s end
        end
    end
    if type(length) == "number" and not isSecret(length) then
        h.timer:SetText(DUI.FormatClock(length))
    else
        h.timer:SetText("")
    end
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
function Header.PlaceFight(h)
    local stop = h.hovered and h.tools or (h.total:IsShown() and h.total or h.timer)
    h.fight:SetPoint("RIGHT", stop, "LEFT", -6, 0)
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
    if h.over then M.AlphaTo(h, on and 1 or 0, M.FAST, true) end
end
