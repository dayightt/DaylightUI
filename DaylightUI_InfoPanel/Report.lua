-- Report window for the damage meter: pick a channel, a line count and Send.
-- Numbers are secret in combat and chat refuses them from addon code, so Send
-- waits for combat to end.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style = DUI.Style

local Report = {}
ns.Report = Report

Report.W = 250          -- the window's width
Report.PAD = 12
Report.MAX = 20         -- lines at most (the slider's top)

-- Where a report can go, in the order the chips show; can() = there now.
Report.CHANNELS = {
    { key = "party", chat = "PARTY", text = L["Party"],
      can = function() return IsInGroup and IsInGroup() end },
    { key = "raid", chat = "RAID", text = L["Raid"],
      can = function() return IsInRaid and IsInRaid() end },
    { key = "instance", chat = "INSTANCE_CHAT", text = L["Instance"],
      can = function() return LE_PARTY_CATEGORY_INSTANCE and IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) end },
    { key = "guild", chat = "GUILD", text = L["Guild"],
      can = function() return IsInGuild and IsInGuild() end },
    { key = "say", chat = "SAY", text = L["Say"], can = function() return true end },
    { key = "whisper", chat = "WHISPER", text = L["Whisper"], can = function() return true end },
}

local function secret(v) return issecretvalue and issecretvalue(v) end

local function db()
    local mod = DUI:GetModule("InfoPanel")
    return mod and mod.db and mod.db.report
end

-- The picked channel if it's there now, else the biggest group you're in.
function Report.Channel()
    local want = db() and db().channel
    local byKey = {}
    for _, c in ipairs(Report.CHANNELS) do byKey[c.key] = c end
    if byKey[want] and byKey[want].can() then return byKey[want] end
    for _, k in ipairs({ "raid", "instance", "party", "say" }) do
        if byKey[k].can() then return byKey[k] end
    end
end

-- One player's spells (who: their source), n at most: a header naming
-- them, then one line each.
local function spellLines(m, n, who)
    -- Picked in a fight, their source then was secret: the same player in
    -- the meter now (by the GUID the meter knows), plain.
    local want = ns.Meter.GuidOf(who)
    local recap = who.deathRecapID
    if issecretvalue(recap) or type(recap) ~= "number" or recap <= 0 then recap = nil end
    local sources = (want or recap) and m.Sources()
    for _, s in ipairs(type(sources) == "table" and sources or {}) do
        -- (a death: that death, by its recap; anyone else: by GUID)
        local same
        if recap then same = not issecretvalue(s.deathRecapID) and s.deathRecapID == recap
        else same = ns.Meter.GuidOf(s) == want end
        if same then who = s break end
    end
    local spells, why = ns.Breakdown.Spells(who, m)
    if not spells then return nil, why or L["Nothing to report yet"] end
    local sum = 0
    for _, s in ipairs(spells) do
        if secret(s.amount) or secret(s.name) then return nil, L["After the fight"] end
        if type(s.amount) == "number" then sum = sum + s.amount end
    end
    local name = who.name
    if secret(name) then return nil, L["After the fight"] end
    if Ambiguate and type(name) == "string" then name = Ambiguate(name, "short") end
    local md = m.Mode()
    local out = { string.format(L["%s: %s (%s)"], type(name) == "string" and name or "?", L[md.name], (m.FightTitle())) }
    for i = 1, math.min(n, #spells) do
        local s = spells[i]
        local amount = type(s.amount) == "number" and s.amount or 0
        local pct = sum > 0 and math.floor(amount / sum * 100 + 0.5) or 0
        out[#out + 1] = string.format(L["%d. %s %s (%d%%)"], i, tostring(s.name), ns.Meter.Short(amount), pct)
    end
    return out
end

-- Lines to send for meter m: a header and up to n players, or one player's
-- spells when `who` is given. Returns nil and a reason when there's nothing.
function Report.Lines(m, n, who)
    if InCombatLockdown and InCombatLockdown() then return nil, L["After the fight"] end
    if m.Sample and m.Sample() then return nil, L["Not with sample data"] end
    if who then return spellLines(m, n, who) end
    local sources, session = m.Sources()
    if type(sources) ~= "table" or #sources == 0 then return nil, L["Nothing to report yet"] end
    local md = m.Mode()
    local deaths, rate = md.key == "deaths", md.rate
    local sum = 0
    for _, src in ipairs(sources) do
        local a = src.totalAmount
        if secret(a) or secret(src.name) or secret(src.amountPerSecond) then return nil, L["After the fight"] end
        if type(a) == "number" then sum = sum + a end
    end
    local title, length = m.FightTitle()
    local time = session and session.durationSeconds
    if type(time) == "nil" then time = length end
    local out = {}
    if type(time) == "number" and not secret(time) and time > 0 then
        out[1] = string.format(L["%s: %s (%s)"], L[md.name], title, DUI.FormatClock(time))
    else
        out[1] = string.format(L["%s: %s"], L[md.name], title)
    end
    for i = 1, math.min(n, #sources) do
        local src = sources[i]
        local name = src.name
        if Ambiguate and type(name) == "string" then name = Ambiguate(name, "short") end
        name = type(name) == "string" and name or "?"
        local amount = type(src.totalAmount) == "number" and src.totalAmount or 0
        local pct = sum > 0 and math.floor(amount / sum * 100 + 0.5) or 0
        if deaths then
            out[#out + 1] = string.format(L["%d. %s %s"], i, name, DUI.FormatClock(src.deathTimeSeconds or 0))
        elseif rate and type(src.amountPerSecond) == "number" then
            out[#out + 1] = string.format(L["%d. %s %s (%s/s, %d%%)"], i, name,
                ns.Meter.Short(amount), ns.Meter.Short(src.amountPerSecond), pct)
        else
            out[#out + 1] = string.format(L["%d. %s %s (%d%%)"], i, name, ns.Meter.Short(amount), pct)
        end
    end
    return out
end

-- Sends the report to the picked place. True when it went.
function Report.Send(m)
    local f = Report.frame
    local d = db()
    local c = Report.Channel()
    if not (d and c) then return false end
    local lines = Report.Lines(m, d.lines or 5, Report.who)
    if not lines then return false end
    local target
    if c.key == "whisper" then
        target = f and f.name:GetText() or ""
        if type(target) ~= "string" then target = "" end
        if target == "" then return false end
    end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok and locked == true then return false end
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    for _, line in ipairs(lines) do send(line, c.chat, nil, target) end
    return true
end

-- ---------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------

local function targetName()
    if not (UnitExists and UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target")) then return "" end
    local n = UnitName("target")   -- who to whisper, not a shown name
    if type(n) ~= "string" or secret(n) then return "" end
    return n
end

local function build()
    local W = DUI.Widgets
    local SIZE = Style.SIZE
    local f = CreateFrame("Frame", "DaylightUIMeterReport", UIParent)
    DUI.Movers.FollowScale(f)
    f:SetFrameStrata("DIALOG")
    f:SetWidth(Report.W)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()
    Style.Shell(f)
    local pad = Report.PAD

    f.title = Style.Text(f, SIZE.head, "LEFT")
    Style.InkText(f.title, "TITLE")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -pad)
    f.title:SetText(L["Report"])
    f.close = W.Close(f, function() DUI.Motion.Vanish(f) end)
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)

    -- What will be sent: the mode and the fight.
    f.what = Style.Text(f, SIZE.small, "LEFT")
    Style.InkText(f.what, "LABEL")
    f.what:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
    f.what:SetPoint("RIGHT", f, "RIGHT", -pad, 0)
    f.what:SetWordWrap(false)

    f.chips = {}
    for _, c in ipairs(Report.CHANNELS) do
        local chip = W.Chip(f, _G[c.chat] or c.text)
        chip.FitWidth()
        chip.channel = c
        chip:SetScript("OnClick", function()
            db().channel = c.key
            Report.Refresh()
        end)
        f.chips[#f.chips + 1] = chip
    end

    f.name = W.Input(f, { hint = L["Name"], maxLetters = 48, onChange = function() Report.Refresh(true) end })
    f.name:SetScript("OnEnterPressed", function() Report.Go() end)

    f.lines = W.CompactRow(f, {}, Report.LINES_ITEM, Report.W - 2 * pad)

    f.send = W.Button(f, L["Send"], 26)
    f.send:SetScript("OnClick", function() Report.Go() end)

    -- Send turns on and off as a fight starts and ends. Closed: nothing
    -- (Report.Toggle lays it out again on open).
    f:SetScript("OnEvent", function(self) if self:IsShown() then Report.Refresh(true) end end)
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:RegisterEvent("PLAYER_GUILD_UPDATE")
    DUI.Motion.Window(f, 6)
    Report.frame = f
    return f
end

Report.LINES_ITEM = {
    type = "slider", label = "Lines", min = 1, max = Report.MAX, step = 1,
    get = function() local d = db(); return d and d.lines or 5 end,
    set = function(v) local d = db(); if d then d.lines = v end end,
    default = function() return 5 end,
}
ns.LOOSE_ITEMS = ns.LOOSE_ITEMS or {}
table.insert(ns.LOOSE_ITEMS, Report.LINES_ITEM)

-- Lays out the available channels, the whisper name box (whisper only) and
-- Send. `quiet` means the name box is being typed in, so its text is kept.
function Report.Refresh(quiet)
    local f = Report.frame
    if not f then return end
    local m = Report.meter
    local pad, gap = Report.PAD, DUI.Widgets.CHIP_GAP
    local md = m and m.Mode()
    local what = md and string.format(L["%s: %s"], L[md.name], (m.FightTitle())) or ""
    -- One player's spells: their name first (plain once the fight's over).
    local who = Report.who and Report.who.name
    if md and type(who) == "string" and not secret(who) then what = string.format(L["%s · %s"], who, what) end
    f.what:SetText(what)
    local picked = Report.Channel()
    local x, y = pad, -50
    local right = Report.W - pad
    for _, chip in ipairs(f.chips) do
        local can = chip.channel.can() and true or false
        chip:SetShown(can)
        if can then
            local w = chip:GetWidth()
            if x > pad and x + w > right then
                x, y = pad, y - DUI.Widgets.CHIP_HEIGHT - gap
            end
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
            x = x + w + gap
            chip.SetOn(picked == chip.channel)
        end
    end
    y = y - DUI.Widgets.CHIP_HEIGHT - 10
    local whisper = picked and picked.key == "whisper"
    f.name:SetShown(whisper)
    if whisper then
        f.name:ClearAllPoints()
        f.name:SetPoint("TOPLEFT", f, "TOPLEFT", pad, y)
        f.name:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad, y)
        y = y - f.name:GetHeight() - 10
    end
    f.lines:ClearAllPoints()
    f.lines:SetPoint("TOPLEFT", f, "TOPLEFT", pad, y)
    if not quiet then f.lines.Refresh() end
    y = y - f.lines:GetHeight() - 12
    f.send:ClearAllPoints()
    f.send:SetPoint("TOPLEFT", f, "TOPLEFT", pad, y)
    f.send:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad, y)
    y = y - f.send:GetHeight() - pad
    f:SetHeight(-y)
    -- Send says why it can't go, when it can't.
    local lines, why = nil, nil
    if m then lines, why = Report.Lines(m, 1, Report.who) end
    if lines and whisper and (f.name:GetText() or "") == "" then lines, why = nil, L["Who to whisper?"] end
    f.send.text:SetText(lines and L["Send"] or why or L["Send"])
    f.send.SetOff(not lines)
end

-- Send, then close.
function Report.Go()
    if Report.meter and Report.Send(Report.meter) then DUI.Motion.Vanish(Report.frame) end
end

-- Toggles the report window beside meter m. `who` reports one player's spells
-- (Shift-click on their row) instead of the whole list.
function Report.Toggle(m, button, who)
    local f = Report.frame or build()
    if DUI.Motion.Shown(f) and Report.meter == m and Report.who == who then
        DUI.Motion.Vanish(f)
        return
    end
    Report.meter, Report.who = m, who
    local area = (m.Area and m.Area()) or (button and button:GetParent() and button:GetParent():GetParent())
    f:ClearAllPoints()
    if area then
        f:SetPoint("BOTTOMRIGHT", area, "BOTTOMLEFT", -8, 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    if (f.name:GetText() or "") == "" then f.name:SetText(targetName()) end
    Report.Refresh()
    f:Show()
end
