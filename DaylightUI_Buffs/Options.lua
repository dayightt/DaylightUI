-- The Buffs & Debuffs options pages. The two bar pages are plain settings. The
-- Categories page draws custom editors: the category list (border, name,
-- consolidate, hide, order, delete), assigning a buff by name, and the history
-- of reassignments.

local _, BL = ...
local DUI = DaylightUI
local L = DUI.L

local BW = BL.Widgets

-- The options window's widgets exist once the core has loaded.
local function UI() return DUI.Widgets end
local function colors() return DUI.Widgets.COLORS end

local LINE = 30 -- height of a category or history line
local HISTORY_SHOWN = 12 -- history lines shown (newest first)

local function refreshPanel()
    local panel = DUI.OptionsPanel
    if panel and panel.IsShown() then panel.Refresh() end
end

local function off(key) return function(get) return get(key) ~= true end end
-- Nothing to combine until a category is set to Combine.
local function noneCombine() return not (BL.Categories and BL.Categories.AnyConsolidated()) end

-- ---------------------------------------------------------------------
-- Small pieces
-- ---------------------------------------------------------------------

-- A text pill that is lit (accent) while its flag is on.
local function pill(parent, text)
    local b = UI().Button(parent, text, 20)
    b.text:SetFont(UI().BODY, DUI.Style.SIZE.body, "")
    b.FitWidth(70)
    function b.SetUsable(on)
        b:SetAlpha(on and 1 or 0.25)
        b:EnableMouse(on and true or false)
    end
    return b
end

local function categoryKeys()
    local keys, names = {}, {}
    for _, id in ipairs(BL.Categories.Order()) do
        local cat = BL.Categories.Get(id)
        if cat then
            keys[#keys + 1] = id
            names[id] = BL.Categories.Label(id)
        end
    end
    return keys, names
end

-- The options window's own menu, listing every category.
local function pickCategory(owner, current, onPick)
    local keys, names = categoryKeys()
    UI().OpenMenu(owner, keys, names, current, onPick, 180)
end

-- ---------------------------------------------------------------------
-- The category list
-- ---------------------------------------------------------------------

local function buildLine(list)
    local W, C = UI(), colors()
    local line = CreateFrame("Frame", nil, list)
    line:SetHeight(LINE)

    line.swatch = CreateFrame("Button", nil, line)
    line.swatch:SetSize(16, 16)
    line.swatch:SetPoint("LEFT", line, "LEFT", 0, 0)
    line.swatch.fill = W.Round(line.swatch, "ARTWORK")
    line.swatch.fill:SetAllPoints(line.swatch)
    line.swatch:SetScript("OnClick", function()
        if BL.Categories.Get(line.id) then BL.EdgeEditor.Open(line.id, line.swatch) end
    end)
    line.swatch:SetScript("OnEnter", function(self) W.Tooltip(self, L["Border"], L["How this category's buffs are edged: one color or a gradient. Click to change."]) end)
    line.swatch:SetScript("OnLeave", W.HideTooltip)

    line.name = CreateFrame("Button", nil, line)
    line.name:SetPoint("LEFT", line.swatch, "RIGHT", 10, 0)
    line.name:SetSize(170, LINE - 6)
    line.name.text = W.Font(line.name, W.BODY, DUI.Style.SIZE.body, C.text)
    line.name.text:SetPoint("LEFT", line.name, "LEFT", 0, 0)
    line.name.text:SetPoint("RIGHT", line.name, "RIGHT", 0, 0)
    line.name:SetScript("OnClick", function()
        local cat = BL.Categories.Get(line.id)
        if not cat then return end
        local id = line.id
        local shown = BL.Categories.Label(id)
        BW.Prompt("RENAME", string.format(L["Rename %s:"], shown), function(text) BL.Categories.Rename(id, text) end, shown)
    end)
    line.name:SetScript("OnEnter", function(self)
        W.TextDaylight(self.text)
        W.Tooltip(self, L["Name"], L["Click to rename."])
    end)
    line.name:SetScript("OnLeave", function(self)
        W.TextColor(self.text, C.text)
        W.HideTooltip()
    end)

    -- Right to left: delete, down, up, hide, consolidate.
    -- Delete takes two clicks: the first shows "Delete?" beside it for a
    -- few seconds.
    local del = W.DeleteButton(line)
    del:SetPoint("RIGHT", line, "RIGHT", 0, 0)
    del.text = W.Font(line, W.BODY, DUI.Style.SIZE.small, C.warn, "RIGHT")
    del.text:SetPoint("RIGHT", del, "LEFT", -4, 0)
    local token = 0
    function del.Arm(on)
        del.armed = on
        del.text:SetText(on and L["Delete?"] or "")
        W.Tint(del.icon, on and C.warn or C.dim)
    end
    del:SetScript("OnClick", function()
        if not del.armed then
            del.Arm(true)
            token = token + 1
            local mine = token
            C_Timer.After(3, function() if token == mine then del.Arm(false) end end)
            return
        end
        token = token + 1
        del.Arm(false)
        BL.Categories.Delete(line.id)
    end)
    del:SetScript("OnLeave", function() W.Tint(del.icon, del.armed and C.warn or C.dim) end)
    line.delete = del
    line.move = W.MoveButtons(line)
    line.move:SetPoint("RIGHT", line.delete, "LEFT", -64, 0)   -- room for "Delete?"
    line.up, line.down = line.move.up, line.move.down
    line.down:SetScript("OnClick", function() BL.Categories.Move(line.id, 1) end)
    line.up:SetScript("OnClick", function() BL.Categories.Move(line.id, -1) end)

    line.hide = pill(line, L["Hide"])
    line.hide:SetPoint("RIGHT", line.move, "LEFT", -10, 0)
    line.hide:SetScript("OnClick", function()
        local cat = BL.Categories.Get(line.id)
        if cat then BL.Categories.SetHidden(line.id, not cat.hidden) end
    end)
    line.consolidate = pill(line, L["Combine"])
    line.consolidate.FitWidth(96)
    line.consolidate:SetPoint("RIGHT", line.hide, "LEFT", -6, 0)
    line.consolidate:SetScript("OnClick", function()
        local cat = BL.Categories.Get(line.id)
        if cat then BL.Categories.SetConsolidate(line.id, not cat.consolidate) end
    end)
    local tips = {
        { line.hide, L["Hide"], L["Leave this category off the bar entirely."] },
        { line.consolidate, L["Combine"], L["Combine this category into one icon when it holds two or more buffs; hover the icon to see them all."] },
        { line.up, L["Move up"], nil }, { line.down, L["Move down"], nil },
    }
    for _, t in ipairs(tips) do
        local b, title, desc = t[1], t[2], t[3]
        b:HookScript("OnEnter", function() W.Tooltip(b, title, desc or L["Where this category sits on the bar."]) end)
        b:HookScript("OnLeave", W.HideTooltip)
    end
    return line
end

local function updateLine(line, id, order)
    local cat = BL.Categories.Get(id)
    line.id = id
    BW.PaintEdge(line.swatch.fill, id)
    local tag = cat.builtin and "" or "  " .. DUI.Win.Parts.Hex(DUI.Style.INK.LABEL) .. L["custom"] .. "|r"
    line.name.text:SetText(BL.Categories.Label(id) .. tag)
    line.hide.SetActive(cat.hidden == true)
    line.consolidate.SetActive(cat.consolidate == true)
    local isOther = id == "other"
    line.hide.SetUsable(not isOther)
    line.delete.SetUsable(cat.deletable ~= false and not isOther)
    line.up.SetUsable(not isOther and order[1] ~= id)
    line.down.SetUsable(not isOther and order[#order - 1] ~= id)
    -- A pooled line may come back showing another category, so disarm it.
    if line.shownId ~= id then line.delete.Arm(false) end
    line.shownId = id
end

local categoryList = {
    type = "custom", label = "Categories",
    build = function(row)
        row.lines = {}
        row.list = CreateFrame("Frame", nil, row)
        row.list:SetPoint("TOPLEFT", row, "TOPLEFT", UI().PAD, -4)
        row.list:SetPoint("TOPRIGHT", row, "TOPRIGHT", -UI().PAD, -4)
    end,
    update = function(row)
        local order = BL.Categories.Order()
        local n = 0
        for _, id in ipairs(order) do
            if BL.Categories.Get(id) then
                n = n + 1
                local line = row.lines[n]
                if not line then
                    line = buildLine(row.list)
                    row.lines[n] = line
                end
                line:ClearAllPoints()
                line:SetPoint("TOPLEFT", row.list, "TOPLEFT", 0, -(n - 1) * LINE)
                line:SetPoint("TOPRIGHT", row.list, "TOPRIGHT", 0, -(n - 1) * LINE)
                updateLine(line, id, order)
                UI().Stripe(line, n % 2 == 0)
                line:Show()
            end
        end
        for i = n + 1, #row.lines do row.lines[i]:Hide() end
        row.count = n
        row.list:SetHeight(math.max(1, n * LINE))
    end,
    height = function(row) return (row.count or #BL.Categories.Order()) * LINE + 8 end,
}

-- ---------------------------------------------------------------------
-- Assign a buff by name
-- ---------------------------------------------------------------------

local assign = {
    type = "custom", label = "Assign a buff",
    build = function(row)
        local W, C = UI(), colors()
        local box = W.Input(row, { hint = L["A buff's exact name"] })
        box:SetPoint("LEFT", row, "LEFT", W.PAD, 0)
        box:SetPoint("RIGHT", row, "RIGHT", -(W.PAD + 130), 0)
        local go = W.Button(row, L["Assign to..."], 26)
        go:SetWidth(120)
        go:SetPoint("RIGHT", row, "RIGHT", -W.PAD, 0)
        local function open()
            local name = strtrim(box:GetText() or "")
            if name == "" then return end
            pickCategory(go, BL.Classify.GetOverride(name), function(id)
                BL.Classify.Assign(name, id, "settings")
                box:SetText("")
                box:ClearFocus()
            end)
        end
        go:SetScript("OnClick", open)
        box:SetScript("OnEnterPressed", open)
        row.box = box
    end,
    height = function() return 42 end,
}

-- ---------------------------------------------------------------------
-- History
-- ---------------------------------------------------------------------

local function categoryText(id)
    local c = BL.Categories.Get(id)
    if not c then return DUI.Win.Parts.Hex(DUI.Style.INK.OFF) .. tostring(id) .. "|r" end
    return BW.ColorText({ BL.Categories.TextColor(id) }, BL.Categories.Label(id))
end

local history = {
    type = "custom", label = "History",
    build = function(row)
        row.lines = {}
        row.empty = UI().Font(row, UI().BODY, 13, colors().dim)
        row.empty:SetPoint("TOPLEFT", row, "TOPLEFT", UI().PAD, -8)
        row.empty:SetText(L["No buffs moved yet. Shift-click a buff on the bar to move it."])
    end,
    update = function(row)
        local W, C = UI(), colors()
        local list = BL.Classify.History()
        local n = math.min(#list, HISTORY_SHOWN)
        for i = 1, n do
            local e = list[i]
            local line = row.lines[i]
            if not line then
                line = CreateFrame("Button", nil, row)
                line:SetHeight(LINE - 6)
                line:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                line.text = W.Font(line, W.BODY, DUI.Style.SIZE.body, C.text)
                line.text:SetPoint("LEFT", line, "LEFT", 0, 0)
                line.text:SetPoint("RIGHT", line, "RIGHT", -110, 0)
                line.when = W.Font(line, W.BODY, DUI.Style.SIZE.small, C.faint, "RIGHT")
                line.when:SetPoint("RIGHT", line, "RIGHT", 0, 0)
                line:SetScript("OnClick", function(self)
                    local name = self.buffName
                    if not name then return end
                    pickCategory(self.text, BL.Classify.GetOverride(name), function(id)
                        BL.Classify.Assign(name, id, "history")
                    end)
                end)
                line:SetScript("OnEnter", function(self) W.Tooltip(self, self.buffName, L["Click to move this buff again."]) end)
                line:SetScript("OnLeave", W.HideTooltip)
                row.lines[i] = line
            end
            line.buffName = e.buffName
            line.text:SetText(string.format("%s:  %s  >  %s", e.buffName, categoryText(e.from), categoryText(e.to)))
            line.when:SetText(e.time and date("%b %d %H:%M", e.time) or "")
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", row, "TOPLEFT", W.PAD, -4 - (i - 1) * (LINE - 6))
            line:SetPoint("TOPRIGHT", row, "TOPRIGHT", -W.PAD, -4 - (i - 1) * (LINE - 6))
            line:Show()
        end
        for i = n + 1, #row.lines do row.lines[i]:Hide() end
        row.count = n
        row.empty:SetShown(n == 0)
    end,
    height = function(row)
        local n = row.count or 0
        if n == 0 then return 36 end
        return n * (LINE - 6) + 10
    end,
}

-- ---------------------------------------------------------------------
-- Pages
-- ---------------------------------------------------------------------

local function barItems(debuff)
    local p = debuff and "settings.debuff." or "settings."
    local items = {
        { type = "slider", key = p .. "iconSize", label = "Icon size", min = 12, max = 64, step = 1, unit = "px",
          desc = "Each icon's width and height." },
        { type = "slider", key = p .. "borderPx", label = "Border thickness", min = 0, max = 6, step = 1, unit = "px",
          desc = "Border around each icon. Separate from the Appearance border setting." },
        { type = "slider", key = p .. "spacing", label = "Spacing", min = 0, max = 12, step = 1, unit = "px",
          desc = "The gap between this bar's icons." },
        { type = "slider", key = p .. "columns", label = "Icons per row", min = 1, max = 40, step = 1,
          desc = "Icons on a row before it wraps to the next." },
        { type = "toggle", key = p .. "growLeft", label = "Grow to the left",
          desc = "Icons fill from the bar's right edge leftward, toward the middle of the screen." },
        { type = "toggle", key = p .. "showBackground", label = "Background",
          desc = "A framed panel behind the bar." },
    }
    for _, item in ipairs(DaylightUI.Options.BackAlphaRows(p .. "backgroundAlpha", debuff and "Debuff bar" or "Buff bar",
            function(get) return get(p .. "showBackground") ~= true end)) do
        if item.type == "slider" then
            item.desc = item.desc or "How see-through the panel behind this bar is."
        end
        items[#items + 1] = item
    end
    for _, item in ipairs(DaylightUI.Fade.Items(p .. "fade.", nil, nil, debuff and "Debuffs" or "Buffs")) do items[#items + 1] = item end
    if not debuff then
        table.insert(items, 3, { type = "slider", key = "settings.categoryGap", label = "Gap between categories",
            min = 0, max = 32, step = 1, unit = "px", desc = "Extra room between one category's buffs and the next." })
    end
    return items
end

-- Per bar: when attached, it sits beside the info panel and follows it.
local function attachItem(debuff)
    return { type = "toggle", key = debuff and "settings.debuff.attach" or "settings.attach",
        label = "Attach to the info panel",
        desc = (debuff and "Just left of the panel, the first row resting on its bottom edge"
                or "Just left of the panel, level with its top")
            .. ", following it as the minimap or damage meter changes size. Turn it off to move the bar yourself in unlock mode." }
end

local PREVIEW = { type = "button", label = "Preview",
    text = function() return BL.Preview.Active() and "Hide" or "Show" end,
    desc = "Fills the bar with a sample of every buff it knows, sorted and colored as they would be.",
    func = function()
        if BL.Preview.Active() then BL.Preview.Set(nil) else BL.Preview.Set(BL.PREVIEW_SHARE, BL.PREVIEW_MAX) end
    end }

BL.OPTIONS = { pages = {
    { id = "buffs", label = "Buffs",
      desc = "Your buffs, sorted into colored categories. Right-click a buff to cancel it; shift-click to move it to another category. The bar sits beside the info panel; to move it, turn off Attach to the info panel.",
      groups = {
        { label = "Bar", items = barItems(false) },
        { label = "Position", items = { attachItem(false) } },
        { label = "Text", desc = "Applies to both the buff and debuff bars.", items = {
            { type = "toggle", key = "settings.showTimers", label = "Show time left",
              desc = "How long each buff and debuff has left, on its icon." },
            { type = "dropdown", key = "settings.timePos", label = "Time left position",
              values = { top = "Top", middle = "Middle", bottom = "Bottom" }, order = { "top", "middle", "bottom" },
              desc = "Where the time sits: on the icon's top edge, across its middle, or on its bottom edge.",
              disabled = function(get) return get("settings.showTimers") ~= true end },
            { type = "toggle", key = "settings.expiring", label = "Orange timer when running out",
              desc = "A buff's time turns orange and gently pulses in its last 5 seconds.",
              disabled = function(get) return get("settings.showTimers") ~= true end },
            { type = "toggle", key = "settings.newGlow", label = "Slide icons in and out",
              desc = "Buffs and debuffs slide in as they land and lift away as they leave." },
            { type = "slider", key = "settings.timeSize", label = "Time left text size", min = 0, max = 20, step = 1,
              desc = "Set to 0 to follow the icon's size.", disabled = function(get) return get("settings.showTimers") ~= true end },
            { type = "slider", key = "settings.countSize", label = "Stack count size", min = 6, max = 20, step = 1,
              desc = "The number on an icon showing how many stacks it has." },
            { type = "dropdown", key = "settings.textOutline", label = "Text outline",
              values = { general = "Same as General", none = "None", thin = "Thin", thick = "Thick" },
              order = { "general", "none", "thin", "thick" },
              desc = "The outline round the time and stack count on buffs and debuffs, apart from General > Appearance's, so the time stays easy to read over any icon." },
        } },
        { label = "Missing group buffs",
          desc = "On a ready check, and when you enter a dungeon or raid in a group, a short line shows the group buffs you don't have yet: only ones someone in your group can give. It fades once they land. Move it in unlock mode.",
          items = {
            { type = "toggle", key = "settings.reminder.enabled", label = "Show missing group buffs",
              desc = "Fortitude, Mark of the Wild, Arcane Intellect, a blessing per paladin and the like, by your class. Never in a fight, a boss encounter or a battleground, where buffs can't be read." },
            { type = "slider", key = "settings.reminder.seconds", label = "Show for (seconds)", min = 3, max = 30, step = 1,
              desc = "How long it stays before fading, unless the buffs land first.",
              disabled = off("settings.reminder.enabled") },
            { type = "button", label = "Preview", text = "Show",
              desc = "Shows a sample of the line where it sits.",
              disabled = off("settings.reminder.enabled"),
              func = function() if BL.Reminder then BL.Reminder.ShowSample(true) end end },
        } },
        { label = "Combine into one icon", desc = "Categories set to Combine show as one icon; hover it to see them all.", items = {
            { type = "toggle", key = "settings.consolidateOnlyGroup", label = "Combine only in a group",
              desc = "Needs a category set to Combine (Categories page).", disabled = noneCombine },
            { type = "toggle", key = "settings.consolidateOnlyRaid", label = "Combine only in a raid",
              desc = "Needs a category set to Combine (Categories page).", disabled = noneCombine },
        } },
        { label = "More", items = {
            PREVIEW,
            { type = "toggle", key = "settings.hideBlizzardFrames", invert = true, label = "Show the game's buff frames",
              desc = "The game's own buff frames show beside DaylightUI's bars. When off, our bars replace them (they still show while Edit Mode is open)." },
        } },
    } },
    { id = "debuffs", label = "Debuffs",
      desc = "Debuffs on you, soonest to expire first, with a border colored by dispel type.",
      groups = {
        { label = "Bar", items = barItems(true) },
        { label = "Position", items = { attachItem(true) } },
        { label = "Boss debuffs",
          desc = "Some boss abilities put debuffs on you that addons can't see. The game draws them itself, in a row under your debuffs.",
          items = {
            { type = "toggle", key = "settings.debuff.privateAuras", label = "Show boss debuffs",
              desc = "Up to three, at the debuffs' size, with a countdown. They only appear when a boss uses them. With the game's buff frames shown, the game shows them there instead.",
              disabled = function(get) return get("settings.hideBlizzardFrames") == false end },
        } },
    } },
    { id = "categories", label = "Categories",
      desc = "Click a color or name to change it. Shift-click a buff on the bar to move it to another category.",
      groups = {
        { label = "Categories", items = {
            categoryList,
            { type = "button", label = "New category", text = "New",
              desc = "Makes a new category with the name you type, then opens it so you can pick its color.",
              func = function()
                  BW.Prompt("NEW_CATEGORY", L["Name for the new category:"], function(text)
                      local id = BL.Categories.Create(text, { 0.8, 0.8, 0.8 })
                      BL.EdgeEditor.Open(id)
                  end)
              end },
            { type = "button", label = "Combine every category",
              desc = "Sets every category to Combine, so each shows as one icon. Click None to set them all back.",
              text = function() return BL.Categories.AllConsolidated() and "None" or "All" end,
              func = function() BL.Categories.SetConsolidateAll(not BL.Categories.AllConsolidated()) end },
            { type = "button", label = "Restore the default categories", text = "Restore", confirm = true,
              desc = "Brings back any default category you deleted, in its original place. Your own categories and moved buffs stay.",
              func = function() BL.Categories.ResetToDefault() end },
        } },
        { label = "Assign a buff", desc = "Type a buff's name and pick where it belongs.", items = { assign } },
        { label = "Moved buffs", desc = "The newest first. Click one to move it again.", items = {
            history,
            { type = "button", label = "Clear the list", text = "Clear", confirm = true,
              desc = "Only clears this list. Moved buffs stay in their new categories.",
              disabled = function() return #BL.Classify.History() == 0 end,
              func = function() BL.Classify.ClearHistory() end },
        } },
    } },
} }

BL.On("CATEGORIES_CHANGED", refreshPanel)
BL.On("OVERRIDES_CHANGED", refreshPanel)
BL.On("CATEGORY_COLOR_CHANGED", refreshPanel)
BL.On("AURAS_CHANGED", refreshPanel)
