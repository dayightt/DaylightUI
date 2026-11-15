-- The Aura Lists options page (Unit Frames > Aura Lists): pick a list, add
-- spells to it by name or spell id (suggesting names seen on you, your target
-- and your group), take them off, and make, rename or delete lists. Each aura
-- row on the frame pages picks which lists it uses (AuraLists.lua).

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local AL = ns.AuraLists

local LINE = 28
local ADD_H = 42   -- the name box's row
local NOTE = 22  -- a line for "couldn't add that"

local function UI() return DUI.Widgets end

local function refreshPanel()
    local panel = DUI.OptionsPanel
    if panel and panel.IsShown() then panel.Refresh() end
end

-- The list the page is editing: the Hidden list until another is picked.
local picked
local function current()
    if picked and AL.Get(picked) then return picked end
    picked = AL.All()[1]
    return picked
end

local function listChoices()
    local values, order = {}, {}
    for _, id in ipairs(AL.All()) do
        local mode = AL.ModeOf(id) == "only" and L["show only"] or L["hide"]
        values[id] = string.format("%s (%s)", AL.Label(id), mode)
        order[#order + 1] = id
    end
    return values, order
end

-- A spell's line: icon, name, ranks, where it works, and an X.
local function spellLine(row)
    local W, Style, Motion = UI(), DUI.Style, DUI.Motion
    local line = CreateFrame("Frame", nil, row.list)
    line:SetHeight(LINE)
    line.icon = line:CreateTexture(nil, "ARTWORK")
    line.icon:SetSize(LINE - 8, LINE - 8)
    line.icon:SetPoint("LEFT", line, "LEFT", 2, 0)
    Style.CropIcon(line.icon)
    line.text = W.Font(line, W.BODY, Style.SIZE.body, W.COLORS.text)
    line.text:SetPoint("LEFT", line.icon, "RIGHT", 8, 0)
    line.tag = W.Font(line, W.BODY, Style.SIZE.small, Style.INK.GOOD, "RIGHT")
    line.tag:SetPoint("RIGHT", line, "RIGHT", -(W.LIST_TOOL + 12), 0)
    line.text:SetPoint("RIGHT", line.tag, "LEFT", -8, 0)
    line.delete = W.DeleteButton(line)
    line.delete:SetPoint("RIGHT", line, "RIGHT", 0, 0)
    line.delete:SetScript("OnClick", function()
        if line.going then return end
        line.going = true
        Motion.Fade(line, 1, 0, Motion.FAST)
        local list, name = line.listId, line.name
        C_Timer.After(Motion.FAST, function()
            line.going = nil
            AL.Remove(list, name)
            refreshPanel()
        end)
    end)
    return line
end

local function suggest(text)
    local names = AL.Suggest(text)
    if not names or #names == 0 then return nil end
    local out = {}
    for i, name in ipairs(names) do
        if i > 8 then break end
        out[#out + 1] = { insert = name, from = 1, to = #text, label = name }
    end
    return out
end

local spellList = {
    type = "custom", label = "Spells on this list",
    build = function(row)
        local W, Style = UI(), DUI.Style
        row.lines = {}
        row.input = W.Input(row, { hint = L["A spell's name or ID"], maxLetters = 80 })
        row.input:SetPoint("TOPLEFT", row, "TOPLEFT", W.PAD, -8)
        row.input:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(W.PAD + 90), -8)
        row.add = W.Button(row, ADD or L["Add"], W.INPUT_H)
        row.add:SetWidth(80)
        row.add:SetPoint("TOPRIGHT", row, "TOPRIGHT", -W.PAD, -8)
        local function add()
            local name, why = AL.Add(current(), row.input:GetText())
            row.why = why
            if name then
                row.fresh = name
                row.input:SetText("")
            end
            refreshPanel()
        end
        row.add:SetScript("OnClick", add)
        row.input:SetScript("OnEnterPressed", add)   -- keeps focus for the next one
        W.Complete(row.input, suggest)
        row.note = W.Font(row, W.BODY, Style.SIZE.small, Style.INK.WARN)
        row.note:SetPoint("TOPLEFT", row, "TOPLEFT", W.PAD, -ADD_H)
        row.note:SetPoint("TOPRIGHT", row, "TOPRIGHT", -W.PAD, -ADD_H)
        row.list = CreateFrame("Frame", nil, row)
        row.empty = W.Font(row.list, W.BODY, Style.SIZE.body, Style.INK.LABEL)
        row.empty:SetPoint("TOPLEFT", row.list, "TOPLEFT", 0, -6)
        row.empty:SetText(L["No spells yet."])
        -- Names seen around you right now, for the suggestions.
        AL.Scan()
    end,
    update = function(row)
        local W, Style, Motion = UI(), DUI.Style, DUI.Motion
        local id = current()
        local top = ADD_H + (row.why and NOTE or 0)
        row.note:SetText(row.why or "")
        row.note:SetShown(row.why ~= nil)
        row.list:ClearAllPoints()
        row.list:SetPoint("TOPLEFT", row, "TOPLEFT", W.PAD, -top)
        row.list:SetPoint("TOPRIGHT", row, "TOPRIGHT", -W.PAD, -top)
        local entries = AL.Entries(id)
        for i, e in ipairs(entries) do
            local line = row.lines[i]
            if not line then
                line = spellLine(row)
                row.lines[i] = line
            end
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", row.list, "TOPLEFT", 0, -(i - 1) * LINE)
            line:SetPoint("TOPRIGHT", row.list, "TOPRIGHT", 0, -(i - 1) * LINE)
            line.listId, line.name = id, e.name
            line.icon:SetTexture(e.icon or 134400)
            local ranks = #e.ids > 1 and "  " .. DUI.Win.Parts.Hex(Style.INK.LABEL)
                .. string.format(L["%d ranks"], #e.ids) .. "|r" or ""
            line.text:SetText(e.name .. ranks)
            line.tag:SetText(e.everywhere and L["works on every unit"] or "")
            W.Stripe(line, i % 2 == 0)
            line:Show()
            if e.name == row.fresh then Motion.Fade(line, 0, 1, Motion.FAST)
            elseif not line.going then line:SetAlpha(1) end
        end
        row.fresh = nil
        for i = #entries + 1, #row.lines do row.lines[i]:Hide() end
        row.count = #entries
        row.top = top
        row.empty:SetShown(#entries == 0)
        row.list:SetHeight(math.max(LINE, #entries * LINE))
    end,
    height = function(row)
        return (row.top or ADD_H) + math.max(1, row.count or 0) * LINE + 6
    end,
}

local function own() return AL.IsBuiltin(current()) end

local function newList(mode)
    local W = UI()
    local ask = mode == "only" and L["Name the new show-only list:"] or L["Name the new hide list:"]
    W.Prompt(ask, "", function(name)
        picked = AL.New(name, mode)
        refreshPanel()
    end)
end

local page = { id = "auralists", label = "Aura Lists",
    desc = "Lists of buffs and debuffs every frame can hide or show only, like other UIs' blacklists and whitelists.",
    groups = {
        { label = "Edit a list",
          desc = "A hide list leaves its spells off every aura row that picks it; Hidden is picked everywhere until you change it. A show-only list makes a row show nothing else. Each frame's Buffs and Debuffs cards pick the lists they use.",
          items = {
            { type = "dropdown", label = "List", since = "1.8.1",
              desc = "Which list the spells below belong to.",
              choices = listChoices, get = current, default = function() return AL.All()[1] end,
              set = function(v) picked = v; refreshPanel() end },
            spellList,
          } },
        { label = "Your lists",
          desc = "The game only lets addons match buffs on anyone you can help and debuffs on enemies by spell. On debuffs on you and your group, only a few harmless ones like Sated can be hidden: those say so in the list.",
          items = {
            { type = "button", label = "New hide list", text = "New", since = "1.8.1",
              desc = "A list of spells to leave off the aura rows that pick it.",
              func = function() newList("hide") end },
            { type = "button", label = "New show-only list", text = "New", since = "1.8.1",
              desc = "A list of spells an aura row shows on its own, leaving everything else off.",
              func = function() newList("only") end },
            { type = "button", label = "Rename this list", text = "Rename", since = "1.8.1",
              desc = "Gives the list picked above a new name. Hidden and Watch list keep theirs.",
              disabled = own,
              func = function()
                  local id = current()
                  UI().Prompt(L["New name for the list:"], AL.Label(id), function(name)
                      AL.Rename(id, name)
                      refreshPanel()
                  end)
              end },
            { type = "button", label = "Delete this list", text = function() return own() and L["Empty"] or DELETE or L["Delete"] end,
              confirm = true, since = "1.8.1",
              desc = "Deletes the list picked above; rows that used it then use none. Hidden and Watch list are only emptied.",
              func = function()
                  AL.Delete(current())
                  picked = nil
                  refreshPanel()
              end },
          } },
    } }

ns.AuraListsPage = page
