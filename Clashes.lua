-- Other addons doing the same job as a part of Daylight UI (Platynator and
-- the nameplates, Baganator and the bags...). At login one box lists every
-- part with more than one addon drawing it; the player picks one for each,
-- and the others are turned off for this character with one reload.
--
-- The list is InstallerPages.CLASHES. The setup guide asks about whole
-- modules itself, so this box shows only on a character that is set up.
-- "Keep both" is remembered per addon, account-wide (clashKept): an addon
-- installed later still gets asked about. Escape or the X saves nothing and
-- asks again next login.

local ADDON_NAME, DUI = ...
local L = DUI.L
local Style = DUI.Style
local SIZE = Style.SIZE

local Clash = {}
DUI.Clashes = Clash

Clash.W = 420        -- the box: room for a row with three chips
Clash.ROW_H = 30     -- one part's row
Clash.DELAY = 3      -- after login: after the setup guide, welcome and plugins' guides look
Clash.WAIT = 5       -- while the setup guide's window is up, look again this often
Clash.TRIES = 24     -- for about two minutes
Clash.OURS = "ours"  -- a row's pick when Daylight UI keeps the part

local function pages() return DUI.InstallerPages end

-- The parts with a clash right now, one row each, in the list's order:
-- { what, ours = the entry saying what Daylight UI's side is, addons = { entry, ... }, pick }.
function Clash.Due()
    local P = pages()
    local kept = DUI.DB.Root().clashKept or {}
    local rows, byWhat = {}, {}
    for _, c in ipairs(P.Clashes()) do
        if not kept[c.addon] and P.ClashOurs(c) then
            local row = byWhat[c.what]
            if not row then
                row = { what = c.what, ours = c, addons = {}, pick = Clash.OURS }
                byWhat[c.what] = row
                rows[#rows + 1] = row
            end
            row.addons[#row.addons + 1] = c
        end
    end
    return rows
end

-- Turns Daylight UI's side of a clash off for this character.
local function offOurs(c, me)
    local api = C_AddOns
    if c.core then
        api.DisableAddOn(ADDON_NAME, me)
    elseif c.settings then
        for _, s in ipairs(c.settings) do DUI:Set(s[1], s[2], false) end
    else
        local mod = pages().Module(c.module)
        if mod then api.DisableAddOn(mod.addon, me) end
    end
end

-- Each row keeps its pick and turns the rest off. Runs in the reload click,
-- before the /reload.
function Clash.Apply(rows)
    local api = C_AddOns
    local me = pages().Character()
    if not (me and api and api.DisableAddOn) then return false end
    for _, row in ipairs(rows) do
        if row.pick ~= Clash.OURS then offOurs(row.ours, me) end
        for _, c in ipairs(row.addons) do
            if c.addon ~= row.pick then api.DisableAddOn(c.addon, me) end
        end
    end
    return true
end

function Clash.KeepAll(rows)
    local root = DUI.DB.Root()
    root.clashKept = root.clashKept or {}
    for _, row in ipairs(rows) do
        for _, c in ipairs(row.addons) do root.clashKept[c.addon] = true end
    end
end

-- A part's name as a row's label: its word with a capital.
local function partName(what)
    local s = L[what]
    return (string.gsub(s, "^%l", string.upper))
end

-- The hover on an addon that clashes only through some of its options.
local function optionsTip(chip, c)
    local on = c.options and c.options()
    if not on then return end
    DUI.Widgets.Tooltip(chip, c.label, string.format(
        L["Its options that fight Daylight UI: %s. Picking Daylight UI turns %s off. To keep both, turn those options off in %s, then pick Keep both."],
        table.concat(on, ", "), c.label, c.label))
end

local function paintRow(line)
    for _, chip in ipairs(line.chips) do
        if chip:IsShown() then chip.SetOn(chip.key == line.row.pick) end
    end
end

local function chipFor(line, i)
    local W = DUI.Widgets
    local chip = line.chips[i]
    if chip then return chip end
    chip = W.Chip(line, "")
    chip:SetScript("OnClick", function(b)
        line.row.pick = b.key
        paintRow(line)
    end)
    chip:HookScript("OnEnter", function(b) if b.entry then optionsTip(b, b.entry) end end)
    chip:HookScript("OnLeave", function() W.HideTooltip() end)
    line.chips[i] = chip
    return chip
end

-- Lays the rows out in the question box's holder (W.Ask's preview).
function Clash.Fill(holder, rows)
    local W = DUI.Widgets
    holder.lines = holder.lines or {}
    for i, row in ipairs(rows) do
        local line = holder.lines[i]
        if not line then
            line = CreateFrame("Frame", nil, holder)
            line:SetHeight(Clash.ROW_H)
            line.label = Style.Text(line, SIZE.body, "LEFT")
            line.label:SetPoint("LEFT", line, "LEFT", 0, 0)
            Style.InkText(line.label, "TEXT")
            line.chips = {}
            holder.lines[i] = line
        end
        line.row = row
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -(i - 1) * Clash.ROW_H)
        line:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
        line:Show()
        W.Stripe(line, i % 2 == 0)
        line.label:SetText(partName(row.what))
        local picks = { { key = Clash.OURS, text = L["Daylight UI"] } }
        for _, c in ipairs(row.addons) do picks[#picks + 1] = { key = c.addon, text = c.label, entry = c } end
        -- Right-aligned, Daylight UI first.
        local prev
        for j = #picks, 1, -1 do
            local chip = chipFor(line, j)
            chip.key, chip.entry = picks[j].key, picks[j].entry
            chip.text:SetText(picks[j].text)
            chip.FitWidth()
            chip:ClearAllPoints()
            if prev then
                chip:SetPoint("RIGHT", prev, "LEFT", -W.CHIP_GAP, 0)
            else
                chip:SetPoint("RIGHT", line, "RIGHT", 0, 0)
            end
            chip:Show()
            prev = chip
        end
        for j = #picks + 1, #line.chips do line.chips[j]:Hide() end
        paintRow(line)
    end
    for i = #rows + 1, #holder.lines do holder.lines[i]:Hide() end
end

-- The box. True when it was asked (or is waiting its turn).
function Clash.Show()
    local rows = Clash.Due()
    if #rows == 0 then return false end
    local many = false
    for _, row in ipairs(rows) do
        if #row.addons > 1 then many = true end
    end
    Clash.rows = rows
    DUI.Widgets.Ask({
        key = "clashes",
        title = L["Other addons"],
        text = L["These do the same job as a part of Daylight UI, and only one can. Pick one for each; the others are turned off for this character."],
        width = Clash.W,
        preview = { height = #rows * Clash.ROW_H, show = function(holder) Clash.Fill(holder, rows) end },
        yes = L["Apply and reload"],
        no = many and L["Keep all"] or L["Keep both"],
        reload = true,
        onYes = function() Clash.Apply(rows) end,
        onNo = function() Clash.KeepAll(rows) end,
        onClose = function() end,
    })
    return true
end

local tries = 0
local function atLogin()
    if DUI.Installer.State() ~= "installed" then return end
    if DUI.InstallerUI.IsShown() then
        tries = tries + 1
        if tries < Clash.TRIES then C_Timer.After(Clash.WAIT, atLogin) end
        return
    end
    Clash.Show()
end

DUI.RegisterEvent("PLAYER_LOGIN", function()
    C_Timer.After(Clash.DELAY, atLogin)
end)
