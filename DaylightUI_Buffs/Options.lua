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

-- Per bar: when attached, it sits beside the info panel and follows it.
local function attachItem(debuff)
    return { type = "toggle", key = debuff and "settings.debuff.attach" or "settings.attach",
        label = "Attach to the info panel",
        desc = (debuff and "Just left of the panel, the first row resting on its bottom edge"
                or "Just left of the panel, level with its top")
            .. ", following it as the minimap or damage meter changes size. Turn it off to move the bar yourself in unlock mode." }
end

-- Something along the top of the screen can sit where an attached bar goes,
-- so it can be nudged up or down from there.
local function attachNudge(debuff)
    local p = debuff and "settings.debuff." or "settings."
    return { type = "slider", key = p .. "attachY", label = debuff and "Debuff bar up / down" or "Buff bar up / down",
        min = -200, max = 200, step = 1, unit = "px", since = "1.9.6",
        disabled = function(get) return get(p .. "attach") == false end,
        desc = "Nudges the bar up or down from its spot beside the info panel, in pixels. Only while it's attached to the panel." }
end

local function barItems(debuff)
    local p = debuff and "settings.debuff." or "settings."
    local items = {
        attachItem(debuff),
        attachNudge(debuff),
        { type = "slider", key = p .. "iconSize", label = "Icon size", min = 12, max = 64, step = 1, unit = "px",
          desc = "Each icon's width and height." },
        { type = "slider", key = p .. "borderPx", label = "Border thickness", min = 0, max = 6, step = 1, unit = "px",
          desc = "Border around each icon. Separate from the border setting on General > Appearance." },
        { type = "slider", key = p .. "spacing", label = "Spacing", min = 0, max = 12, step = 1, unit = "px",
          desc = "The gap between this bar's icons." },
        { type = "slider", key = p .. "columns", label = "Icons per row", min = 1, max = 40, step = 1,
          desc = "Icons on a row before it wraps to the next." },
        { type = "toggle", key = p .. "growLeft", label = "Grow to the left",
          desc = "Icons fill from the bar's right edge leftward, toward the middle of the screen." },
        { type = "dropdown", key = p .. "sortOrder", label = debuff and "Debuff order" or "Buff order", since = "2.2.2",
          values = { soonest = "Soonest to run out first", longest = "Longest first" }, order = { "soonest", "longest" },
          desc = debuff
              and "Which debuffs come first on the bar. Longest first starts with debuffs that never run out, then the longest timers."
              or "Which buffs come first within each category. Longest first starts with buffs that never run out, like forms and auras, then the longest timers." },
        { type = "toggle", key = p .. "showBackground", label = "Bar background",
          desc = "A framed panel behind the bar." },
    }
    for _, item in ipairs(DaylightUI.Options.LookRows(p .. "frameStyle",
            function(get) return get(p .. "showBackground") ~= true end)) do
        items[#items + 1] = item
    end
    for _, item in ipairs(DaylightUI.Fade.Items(p .. "fade.", nil, nil, debuff and "Debuffs" or "Buffs")) do items[#items + 1] = item end
    if not debuff then
        table.insert(items, 4, { type = "slider", key = "settings.categoryGap", label = "Gap between categories",
            min = 0, max = 32, step = 1, unit = "px", desc = "Extra room between one category's buffs and the next." })
        table.insert(items, 5, { type = "toggle", key = "settings.categoryRows", label = "Each category on its own row", since = "1.7.2",
            desc = "Class buffs share one row, then weapon, consumable, world and other buffs each start a row of their own, in the order set on the Categories page. A long row still wraps at Icons per row." })
    end
    return items
end

-- The aura lists live in the Unit Frames module: with it off there are none to
-- pick, so the list rows hide.
local NEW = "1.8.3"
local function noLists() return not DUI.AuraLists end
local function listChoices(mode)
    return function()
        if DUI.AuraLists then return DUI.AuraLists.Choices(mode) end
        return { none = "None" }, { "none" }
    end
end

local function filterItems(debuff)
    if debuff then
        local p = "settings.debuff."
        return {
            { type = "dropdown", key = p .. "filter", label = "Debuff filter", since = NEW,
              values = { all = "All debuffs", dispel = "Only ones I can dispel" }, order = { "all", "dispel" },
              desc = "Every debuff on you, or only the ones your class can remove." },
            { type = "dropdown", key = p .. "hideList", label = "Hide list", since = NEW,
              choices = listChoices("hide"), hidden = noLists,
              desc = "Debuffs on this list never show here. The game only lets addons hide a few harmless debuffs on you, like Sated; the Aura Lists page marks which. Make and fill lists on Unit Frames > Aura Lists." },
            { type = "toggle", key = p .. "bossOnly", label = "Only boss debuffs", since = NEW,
              desc = "Shows only the debuffs a boss puts on you, the ones a fight is about." },
            { type = "slider", key = p .. "maxTime", label = "Longest debuff shown", since = NEW,
              min = 0, max = 600, step = 5,
              desc = "Leaves out debuffs that last longer than this many seconds, and ones that never run out, like long curses and Resurrection Sickness. 0 shows them all." },
        }
    end
    return {
        { type = "dropdown", key = "settings.hideList", label = "Hide list", since = NEW,
          choices = listChoices("hide"), hidden = noLists,
          desc = "The buffs on this list never show here. Make and fill lists on Unit Frames > Aura Lists." },
        { type = "dropdown", key = "settings.onlyList", label = "Show only list", since = NEW,
          choices = listChoices("only"), hidden = noLists,
          desc = "Shows only the buffs on this list. An empty list shows them all. Make and fill lists on Unit Frames > Aura Lists." },
    }
end

-- Missing buffs (Reminder.lua and its parts, ReminderRow.lua): five cards with
-- EllesmereUI's sections, his rows and defaults, in Daylight UI's words.
local R = "settings.reminder."
local RSEARCH = "Missing buffs Reminder"
local function remOff(get) return get(R .. "enabled") ~= true end
local function rem(t)
    t.search = RSEARCH .. (t.search and (" " .. t.search) or "")
    local own = t.disabled
    t.disabled = function(get) return remOff(get) or (own and own(get)) or false end
    return t
end
local function rToggle(key, label, desc, extra)
    local t = { type = "toggle", key = R .. key, label = label, desc = desc }
    for k, v in pairs(extra or {}) do t[k] = v end
    return rem(t)
end
local function rSlider(key, label, min, max, step, desc, extra)
    local t = { type = "slider", key = R .. key, label = label, min = min, max = max, step = step, desc = desc }
    for k, v in pairs(extra or {}) do t[k] = v end
    return rem(t)
end
local function rDrop(key, label, values, order, desc, extra)
    local t = { type = "dropdown", key = R .. key, label = label, values = values, order = order, desc = desc }
    for k, v in pairs(extra or {}) do t[k] = v end
    return rem(t)
end
local function rColor(key, label, desc, extra)
    local t = { type = "color", key = R .. key, label = label, desc = desc }
    for k, v in pairs(extra or {}) do t[k] = v end
    return rem(t)
end

local function myClass()
    local _, class = UnitClass("player")
    class = BL.Plain(class)
    return type(class) == "string" and class or "WARRIOR"
end

-- A label, then a menu button whose menu ticks things on and off.
local function switchMenu(label, desc, keys, values, isOn, flip, summary, hidden)
    return { type = "custom", label = label, desc = desc, hidden = hidden,
        build = function(row)
            local W = UI()
            row.name = DUI.Style.Text(row, DUI.Style.SIZE.body, "LEFT")
            row.name:SetPoint("LEFT", row, "LEFT", W.PAD, 0)
            row.name:SetText(L[label])
            DUI.Style.InkText(row.name, "TEXT")
            local b = W.MenuButton(row, "")
            b:SetPoint("RIGHT", row, "RIGHT", -W.PAD, 0)
            b:SetScript("OnClick", function(self)
                local k, v = keys(), values()
                W.OpenMenu(self, k, v, nil, function(key) flip(key); refreshPanel() end, 220,
                    { keepOpen = true, rows = #k, checked = function(key) return isOn(key) end })
            end)
            row.button = b
        end,
        update = function(row)
            row.button.SetLabel(summary(), 160)
            local off = DaylightUI:Get(BL.MODULE, R .. "enabled") ~= true
            row:SetAlpha(off and 0.4 or 1)
            row.button:EnableMouse(not off)
        end,
        height = function() return 36 end }
end

local PLACES = { open_world = "Open world", dungeon = "Dungeons", raid = "Raids", in_combat = "In combat" }
local function whereRow(sectionKey, label, withCombat)
    local path = R .. sectionKey .. ".where."
    local function keys()
        local k = { "open_world", "dungeon", "raid" }
        if withCombat then k[#k + 1] = "in_combat" end
        return k
    end
    local function on(key) return DaylightUI:Get(BL.MODULE, path .. key) ~= false end
    return switchMenu(label, "Where this section's icons show. Battlegrounds and arenas always show them.", keys,
        function() local v = {} for _, k in ipairs(keys()) do v[k] = L[PLACES[k]] end return v end,
        on, function(key) DaylightUI:Set(BL.MODULE, path .. key, not on(key)) end,
        function()
            local shown = {}
            for _, k in ipairs(keys()) do if on(k) then shown[#shown + 1] = L[PLACES[k]] end end
            return #shown == 0 and L["Nowhere"] or table.concat(shown, ", ")
        end)
end

local function soundRow(sectionKey, label)
    return rem({ type = "dropdown", key = R .. sectionKey .. ".sound", label = label, search = "Sound",
        choices = function() return DUI.Sound.AlertChoices() end,
        hover = function(k) DUI.Sound.AlertHover(k) end,
        onPick = function(k) DUI.Sound.AlertSample(k) end,
        desc = "Plays once when an icon of this section appears. None plays nothing." })
end

-- A weapon hand's pick (nil = Auto), kept per class.
local function handRow(hand, label, isImbue, hidden, disabled)
    local function path() return R .. "hands." .. myClass() .. "." .. hand end
    return rem({ type = "dropdown", label = label, hidden = hidden, disabled = disabled, search = "Weapon",
        choices = function()
            local values, order = { auto = L["Auto"], off = L["Off"] }, { "auto", "off" }
            for _, b in ipairs(BL.ReminderData.WEAPON_BUFFS) do
                if (b.imbue == true) == isImbue and (not b.class or b.class == myClass()) then
                    local name = b.name or (b.spells and C_Spell and BL.Plain(C_Spell.GetSpellName(b.spells[1]))) or b.key
                    values[b.key] = name
                    order[#order + 1] = b.key
                end
            end
            return values, order
        end,
        get = function() return DaylightUI:Get(BL.MODULE, path()) or "auto" end,
        set = function(v) DaylightUI:Set(BL.MODULE, path(), v ~= "auto" and v or nil) end,
        default = function() return "auto" end,
        desc = "Auto uses the first you have, in the usual order. Off never reminds for this hand." })
end

local function rankRow(key, label, desc, disabled)
    return rem({ type = "dropdown", label = label, disabled = disabled,
        values = { high = "Highest owned", low = "Lowest owned" }, order = { "high", "low" },
        get = function() return DaylightUI:Get(BL.MODULE, R .. key) == true and "low" or "high" end,
        set = function(v) DaylightUI:Set(BL.MODULE, R .. key, v == "low") end,
        default = function() return "high" end, desc = desc })
end

local function hasImbue() return BL.ReminderSelf and BL.ReminderSelf.HasImbue(myClass()) end
local function canDual() return type(CanDualWield) == "function" and BL.Plain(CanDualWield()) == true end

-- Missing buffs: the switch, cursor, tooltips, picker, preview.
local function reminderCore()
    return {
        { type = "toggle", key = R .. "enabled", label = "Show missing buffs", search = RSEARCH,
          desc = "A row above you shows the buffs you're missing: raid buffs, your own buffs and consumables. Left-click casts out of a fight, middle-click hides one until the next loading screen." },
        rToggle("cursor", "Raid buffs at the cursor",
            "The raid buffs you can give follow your mouse instead of sitting in the row. They can't be clicked there."),
        rToggle("cursorCombat", "Only at the cursor in a fight",
            "Out of a fight your raid buffs stay in the row, where they can be clicked.",
            { disabled = function(get) return get(R .. "cursor") ~= true end }),
        rToggle("tooltips", "Missing buffs tooltips",
            "Hovering an icon shows the spell or item and who is missing it. When off, nothing shows on hover."),
        rToggle("picker", "Right-click to choose",
            "Right-click a spell group, a class buff, Well Fed or a scroll to choose what the icon uses. Scroll over a spell to choose its rank."),
        rem({ type = "button", label = "Preview the missing buffs", text = function()
              return BL.Reminder and BL.Reminder.sample and "Hide" or "Preview"
          end,
          desc = "Shows a sample row where it sits: a raid buff you give, one from others, your own buff and a weapon oil.",
          func = function()
              local Rm = BL.Reminder
              if Rm then Rm.ShowSample(not Rm.sample) end
          end }),
    }
end

-- Missing buffs look: his Display rows on Daylight UI's pieces.
local function reminderLook()
    local glowValues, glowOrder = { none = "None" }, { "none" }
    for _, k in ipairs(DUI.Motion.GLOW_STYLE_ORDER) do glowValues[k] = DUI.Motion.GLOW_STYLES[k]; glowOrder[#glowOrder + 1] = k end
    local function cropped(get) return get(R .. "shape") ~= "cropped" end
    local function noNames(get) return get(R .. "names") == false end
    local function noCount(get) return get(R .. "count") == false end
    local function noBorder(get) return get(R .. "border") == "none" end
    local nameFont = DUI.Options.FontRow(R .. "nameFont", "Missing buffs name font", "The font of each icon's name", noNames)
    local countFont = DUI.Options.FontRow(R .. "countFont", "Missing buffs count font", "The font of the count in each icon's corner", noCount)
    rem(nameFont); rem(countFont)
    return {
        rSlider("size", "Missing buffs icon size", 20, 120, 1, "How big each icon in the row is.", { unit = "px" }),
        rDrop("shape", "Missing buffs icon shape",
            { none = "Square", cropped = "Cropped", circle = "Circle", diamond = "Diamond", hexagon = "Hexagon",
              octagon = "Octagon", shield = "Shield" },
            { "none", "cropped", "circle", "diamond", "hexagon", "octagon", "shield" },
            "Cropped trims each icon's top and bottom so it's wider than tall. The other shapes are the action bars' button shapes."),
        rSlider("zoom", "Missing buffs icon zoom", 0, 15, 0.5, "How far the icon's art is zoomed in, trimming its edges."),
        rSlider("crop", "Missing buffs crop", 5, 25, 1,
            "How much is trimmed from each icon's top and bottom, per side, when the shape is Cropped.",
            { unit = nil, hidden = cropped }),
        rDrop("grow", "Missing buffs grow direction", { CENTER = "Centered", LEFT = "Grow left", RIGHT = "Grow right" },
            { "CENTER", "LEFT", "RIGHT" }, "Which part of the row stays in place as icons come and go."),
        rDrop("strata", "Missing buffs frame strata",
            { BACKGROUND = "Background", LOW = "Low", MEDIUM = "Medium", HIGH = "High", DIALOG = "Dialog" },
            { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" }, "Which layer of the screen the row and its click buttons sit in."),
        rSlider("gap", "Missing buffs spacing", 0, 50, 1, "The space between two icons in the row.", { unit = "px" }),
        rDrop("border", "Missing buffs border style", { daylight = "Daylight", flat = "Flat", none = "None" },
            { "daylight", "flat", "none" }, "The edge round each icon: Daylight UI's shell, a flat line, or none."),
        rSlider("borderPx", "Missing buffs border size", 0, 6, 1, "How thick the edge round each icon is.", { unit = "px", disabled = noBorder }),
        rColor("borderColor", "Missing buffs border color", "The color of the edge round each icon.", { disabled = noBorder }),
        rSlider("borderShiftX", "Missing buffs border shift X", -10, 10, 1, "Moves the edge left or right of the icon.", { disabled = noBorder }),
        rSlider("borderShiftY", "Missing buffs border shift Y", -10, 10, 1, "Moves the edge up or down from the icon.", { disabled = noBorder }),
        rToggle("borderBehind", "Missing buffs border behind the icon",
            "Draws the edge under the icon instead of over it, with its background.", { disabled = noBorder }),
        rToggle("names", "Missing buffs names", "Each buff's short name by its icon. When off, hover an icon to see it."),
        nameFont,
        rSlider("nameSize", "Missing buffs name size", 6, 30, 1, "Text size of each icon's name.", { disabled = noNames }),
        rDrop("nameAnchor", "Missing buffs name position",
            { BOTTOM = "Below the icon", TOP = "Above the icon", CENTER = "On the icon", LEFT = "Left of the icon", RIGHT = "Right of the icon" },
            { "BOTTOM", "TOP", "CENTER", "LEFT", "RIGHT" }, "Where each icon's name sits.", { disabled = noNames }),
        rSlider("nameX", "Missing buffs name X", -50, 50, 1, "Moves the names left or right.", { disabled = noNames }),
        rSlider("nameY", "Missing buffs name Y", -50, 50, 1, "Moves the names up or down.", { disabled = noNames }),
        rColor("nameColor", "Missing buffs name color", "The color of each icon's name.", { disabled = noNames }),
        rToggle("count", "Item count", "How many of the item you carry, in the icon's corner. Red 0 when you have none. A raid buff's count of who has it always shows."),
        countFont,
        rSlider("countSize", "Missing buffs count size", 6, 30, 1, "Text size of the count in each icon's corner.", { disabled = noCount }),
        rSlider("countX", "Missing buffs count X", -50, 50, 1, "Moves the counts left or right.", { disabled = noCount }),
        rSlider("countY", "Missing buffs count Y", -50, 50, 1, "Moves the counts up or down.", { disabled = noCount }),
        rDrop("glow", "Missing buffs glow", glowValues, glowOrder,
            "A light that runs round every icon while it shows. None: an icon you can click glows a few times as it appears."),
        rDrop("glowColor", "Missing buffs glow color", { accent = "Accent color", class = "Class color", custom = "One color" },
            { "accent", "class", "custom" }, "The color of the glow.", { disabled = function(get) return get(R .. "glow") == "none" end }),
        rColor("glowCustom", "Custom missing buffs glow color", "The glow's color when Missing buffs glow color is One color.",
            { hidden = function(get) return get(R .. "glowColor") ~= "custom" end }),
        rSlider("opacity", "Missing buffs opacity", 0, 1, 0.05, "How see-through the whole row is.", { unit = "%" }),
        rSlider("fightAlpha", "Raid buffs opacity in a fight", 0, 1, 0.05,
            "In a fight raid buff icons dim to this and the rest fade away until it ends.", { unit = "%" }),
    }
end

local RAID_NAMES = { fortitude = "Power Word: Fortitude", wild = "Mark of the Wild", intellect = "Arcane Intellect",
                     spirit = "Divine Spirit", shout = "Battle Shout" }

local function reminderRaid()
    local rows = {
        whereRow("raid", "Raid buffs: where to show", true),
        rToggle("raid.others", "Others are missing my buff",
            "A raid buff you can give shows while someone in your group lacks it, with how many have it. When off, it shows only while you lack it."),
        rToggle("raid.mine", "I'm missing others' buffs",
            "The raid buffs someone in your group could give you and you lack. They can't be clicked."),
        soundRow("raid", "Raid buffs sound"),
    }
    for _, key in ipairs({ "fortitude", "wild", "intellect", "spirit", "shout" }) do
        rows[#rows + 1] = rToggle("raid.on." .. key, RAID_NAMES[key], "Reminds of this raid buff. When off, it never shows.", { search = "Raid buffs" })
    end
    rows[#rows + 1] = rToggle("raid.blessings", "Blessings", "A paladin's blessings you lack, one per paladin in your group.", { search = "Raid buffs" })
    rows[#rows + 1] = rToggle("raid.shadow", "Shadow Protection", "Asked for only once someone in your group already wears it.", { search = "Raid buffs" })
    return rows
end

-- Self buffs: a class's buffs as a menu of switches, the rest by class.
local function classBuffMenu()
    local function list() return BL.ReminderData.CLASS_BUFFS[myClass()] or {} end
    local function name(b)
        if b.menu then return b.menu end
        local line = b.lines[#b.lines]
        return (C_Spell and BL.Plain(C_Spell.GetSpellName(line[1]))) or b.key
    end
    return switchMenu("Class buffs", "Reminds you when one of your class's own buffs is missing. Click the icon to cast it.",
        function()
            local k = {}
            for _, b in ipairs(list()) do k[#k + 1] = b.key end
            if myClass() == "HUNTER" then k[#k + 1] = "huntertracking" end
            return k
        end,
        function()
            local v = { huntertracking = L["Target tracking"] }
            for _, b in ipairs(list()) do v[b.key] = name(b) end
            return v
        end,
        function(key)
            if key == "huntertracking" then return DaylightUI:Get(BL.MODULE, R .. "self.hunterTracking") == true end
            for _, b in ipairs(list()) do if b.key == key then return BL.ReminderSelf.ClassBuffOn(b) end end
            return false
        end,
        function(key)
            if key == "huntertracking" then
                DaylightUI:Set(BL.MODULE, R .. "self.hunterTracking", DaylightUI:Get(BL.MODULE, R .. "self.hunterTracking") ~= true)
                return
            end
            for _, b in ipairs(list()) do
                if b.key == key then DaylightUI:Set(BL.MODULE, R .. "self.picks." .. key, not BL.ReminderSelf.ClassBuffOn(b)) end
            end
        end,
        function()
            local n = 0
            for _, b in ipairs(list()) do if BL.ReminderSelf.ClassBuffOn(b) then n = n + 1 end end
            return string.format(L["%d on"], n)
        end,
        function() return myClass() == "MAGE" or #list() == 0 and myClass() ~= "HUNTER" end)
end

-- Typed-in spells: a box to add one, then a line per spell with its class
-- menu and Remove.
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local LINE_H = 28
local customList = { type = "custom", label = "Custom spells",
    build = function(row)
        local W = UI()
        row.input = W.Input(row, { numeric = true, hint = L["Spell ID"], onChange = function(text) row.typed = text end })
        row.input:SetPoint("TOPLEFT", row, "TOPLEFT", W.PAD, -4)
        row.input:SetWidth(140)
        local function add()
            if BL.ReminderSelf.AddCustom(row.typed) then row.input:SetText(""); refreshPanel() end
        end
        row.input:HookScript("OnEnterPressed", add)
        row.add = W.Button(row, L["Add"], 24)
        row.add:SetPoint("LEFT", row.input, "RIGHT", 8, 0)
        row.add:SetScript("OnClick", add)
        row.lines = {}
    end,
    update = function(row)
        local W = UI()
        local custom = DaylightUI:Get(BL.MODULE, R .. "self.custom") or {}
        local ids = custom.ids or {}
        for i, id in ipairs(ids) do
            local line = row.lines[i]
            if not line then
                line = CreateFrame("Frame", nil, row)
                line:SetHeight(LINE_H)
                line.text = DUI.Style.Text(line, DUI.Style.SIZE.body, "LEFT")
                line.text:SetPoint("LEFT", line, "LEFT", 0, 0)
                line.del = W.DeleteButton(line)
                line.del:SetPoint("RIGHT", line, "RIGHT", 0, 0)
                line.classes = W.MenuButton(line, L["Classes"], 22)
                line.classes:SetPoint("RIGHT", line.del, "LEFT", -6, 0)
                row.lines[i] = line
            end
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", row, "TOPLEFT", W.PAD, -8 - i * LINE_H)
            line:SetPoint("RIGHT", row, "RIGHT", -W.PAD, 0)
            local name = C_Spell and BL.Plain(C_Spell.GetSpellName(id)) or tostring(id)
            line.text:SetText(string.format("%s  %s", name or "", DUI.Win.Parts.Hex(DUI.Style.INK.LABEL) .. id .. "|r"))
            DUI.Style.InkText(line.text, "TEXT")
            line.del:SetScript("OnClick", function() BL.ReminderSelf.RemoveCustom(id); refreshPanel() end)
            line.classes:SetScript("OnClick", function(self)
                local values = {}
                for _, c in ipairs(CLASSES) do values[c] = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c]) or c end
                W.OpenMenu(self, CLASSES, values, nil, function(c)
                    local cl = (DaylightUI:Get(BL.MODULE, R .. "self.custom.classes") or {})[id]
                    BL.ReminderSelf.SetCustomClass(id, c, type(cl) == "table" and cl[c] == false)
                end, 180, { keepOpen = true, rows = #CLASSES, checked = function(c)
                    local cl = (DaylightUI:Get(BL.MODULE, R .. "self.custom.classes") or {})[id]
                    return not (type(cl) == "table" and cl[c] == false)
                end })
            end)
            line:Show()
        end
        for i = #ids + 1, #row.lines do row.lines[i]:Hide() end
        row.count = #ids
    end,
    height = function(row) return 40 + (row.count or 0) * LINE_H end }

-- Spell groups: one card row per group with its spells, add, rename, remove.
local groupList = { type = "custom", label = "Spell groups",
    build = function(row)
        local W = UI()
        row.new = W.Button(row, L["New spell group"], 24)
        row.new:SetPoint("TOPLEFT", row, "TOPLEFT", W.PAD, -4)
        row.new.FitWidth(120)
        row.new:SetScript("OnClick", function()
            W.Prompt(L["Name for the new spell group:"], "", function(text)
                if BL.ReminderSelf.NewGroup(text) then refreshPanel() end
            end)
        end)
        row.blocks = {}
    end,
    update = function(row)
        local W = UI()
        local groups = DaylightUI:Get(BL.MODULE, R .. "self.groups") or {}
        local y = -36
        for gi, g in ipairs(groups) do
            local b = row.blocks[gi]
            if not b then
                b = CreateFrame("Frame", nil, row)
                b.title = DUI.Style.Text(b, DUI.Style.SIZE.small, "LEFT")
                b.title:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -4)
                b.input = W.Input(b, { numeric = true, hint = L["Spell ID"], onChange = function(text) b.typed = text end })
                b.input:SetWidth(120)
                b.input:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -24)
                b.input:HookScript("OnEnterPressed", function() if b.addFn then b.addFn() end end)
                b.add = W.Button(b, L["Add"], 24)
                b.add:SetPoint("LEFT", b.input, "RIGHT", 8, 0)
                b.rename = W.Button(b, L["Rename"], 24)
                b.rename:SetPoint("LEFT", b.add, "RIGHT", 6, 0)
                b.remove = W.Button(b, L["Remove"], 24)
                b.remove:SetPoint("LEFT", b.rename, "RIGHT", 6, 0)
                b.lines = {}
                row.blocks[gi] = b
            end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", row, "TOPLEFT", W.PAD, y)
            b:SetPoint("RIGHT", row, "RIGHT", -W.PAD, 0)
            b.title:SetText(string.upper(g.name or ""))
            DUI.Style.InkText(b.title, "pop")
            local function add() if BL.ReminderSelf.AddToGroup(gi, b.typed) then b.input:SetText(""); refreshPanel() end end
            b.add:SetScript("OnClick", add)
            b.addFn = add
            b.rename:SetScript("OnClick", function()
                W.Prompt(L["New name for the group:"], g.name or "", function(text)
                    if BL.ReminderSelf.RenameGroup(gi, text) then refreshPanel() end
                end)
            end)
            W.Confirm(b.remove, L["Remove"], function() BL.ReminderSelf.RemoveGroup(gi); refreshPanel() end)
            local ids = g.ids or {}
            for li, id in ipairs(ids) do
                local line = b.lines[li]
                if not line then
                    line = CreateFrame("Frame", nil, b)
                    line:SetHeight(LINE_H)
                    line.text = DUI.Style.Text(line, DUI.Style.SIZE.body, "LEFT")
                    line.text:SetPoint("LEFT", line, "LEFT", 0, 0)
                    line.del = W.DeleteButton(line)
                    line.del:SetPoint("RIGHT", line, "RIGHT", 0, 0)
                    b.lines[li] = line
                end
                line:ClearAllPoints()
                line:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -54 - (li - 1) * LINE_H)
                line:SetPoint("RIGHT", b, "RIGHT", 0, 0)
                local name = C_Spell and BL.Plain(C_Spell.GetSpellName(id)) or ""
                line.text:SetText(string.format("%s  %s", name or "", DUI.Win.Parts.Hex(DUI.Style.INK.LABEL) .. id .. "|r"))
                DUI.Style.InkText(line.text, "TEXT")
                line.del:SetScript("OnClick", function() BL.ReminderSelf.RemoveFromGroup(gi, id); refreshPanel() end)
                line:Show()
            end
            for li = #ids + 1, #b.lines do b.lines[li]:Hide() end
            local h = 58 + #ids * LINE_H
            b:SetHeight(h)
            b:Show()
            y = y - h - 6
        end
        for gi = #groups + 1, #row.blocks do row.blocks[gi]:Hide() end
        row.total = -y
    end,
    height = function(row) return (row.total or 36) + 4 end }

local function reminderSelf()
    local function notClass(c) return function() return myClass() ~= c end end
    local function off(key) return function(get) return get(R .. key) ~= true end end
    return {
        whereRow("self", "Self buffs: where to show"),
        soundRow("self", "Self buffs sound"),
        rToggle("self.mageArmor", "Mage armors",
            "Reminds you when no Frost Armor, Ice Armor or Mage Armor is up. The icon is the one you last had on; click it to cast it.",
            { hidden = notClass("MAGE") }),
        classBuffMenu(),
        rToggle("self.imbue", myClass() == "ROGUE" and "Poisons" or "Weapon imbues",
            "Reminds you when a weapon has no poison or imbue. Click the icon to put one on.",
            { hidden = function() return not hasImbue() end, search = "Poison Imbue" }),
        handRow("mhImbue", myClass() == "ROGUE" and "Main hand poison" or "Main hand imbue", true,
            function() return not hasImbue() end, off("self.imbue")),
        handRow("ohImbue", myClass() == "ROGUE" and "Off hand poison" or "Off hand imbue", true,
            function() return not hasImbue() or not canDual() end, off("self.imbue")),
        rankRow("self.lowRank", "Weapon rank to use",
            "Which of the items you carry a weapon reminder uses: the highest or the lowest rank. Shared with stones and oils."),
        rToggle("self.hideNoItem", "Hide weapons when none in bags",
            "A hand set to an item you don't carry shows nothing. When off, it still shows, grayed. A warlock's stone shows its Create spell instead."),
        rSlider("self.weaponBelow", "Weapons show below, in minutes", 0, 10, 1,
            "Shows a weapon reminder before a poison, imbue, stone or oil runs out. At 0 only once it has run out."),
        rToggle("self.sacrifice", C_Spell and BL.Plain(C_Spell.GetSpellName(18788)) or "Demonic Sacrifice",
            "With the Demonic Sacrifice talent, reminds you when its buff is missing. Click to summon the demon, then again to sacrifice it.",
            { hidden = notClass("WARLOCK") }),
        rDrop("self.demon", "Demon to sacrifice",
            { auto = "Auto", imp = "Imp", voidwalker = "Voidwalker", succubus = "Succubus", felhunter = "Felhunter" },
            { "auto", "imp", "voidwalker", "succubus", "felhunter" },
            "Auto: any sacrifice buff counts, and the demon that is out is sacrificed (else the Imp is summoned).",
            { hidden = notClass("WARLOCK"), disabled = off("self.sacrifice") }),
        rToggle("self.gather", "Gathering tracking", "Reminds you when no gathering tracking is on. Click to track herbs first, else minerals."),
        rToggle("self.gatherClassTrack", "Ignore if class tracking is on",
            "A class's own tracking on the minimap (a hunter's, a paladin's) hides the gathering reminder.", { disabled = off("self.gather") }),
        rToggle("self.treasure", C_Spell and BL.Plain(C_Spell.GetSpellName(2481)) or "Find Treasure", "Reminds dwarves when Find Treasure is off."),
        customList,
        groupList,
    }
end

-- Scrolls and elixirs: which stats, per class, as a menu of switches.
local function statMenu()
    local function path(key) return R .. "items.stats." .. myClass() .. "." .. key end
    local function locked(key) return BL.ReminderItems.Locked(key, myClass()) end
    return switchMenu("Scrolls and elixirs", "Reminds you when a ticked stat has no scroll or elixir buff while you carry one. Click the icon to use it.",
        function() local k = {} for _, s in ipairs(BL.ReminderData.STATS) do k[#k + 1] = s.key end return k end,
        function()
            local v = {}
            for _, s in ipairs(BL.ReminderData.STATS) do
                v[s.key] = locked(s.key) and string.format(L["%s (you know its buff)"], s.label) or s.label
            end
            return v
        end,
        function(key) return not locked(key) and DaylightUI:Get(BL.MODULE, path(key)) == true end,
        function(key)
            if locked(key) then return end
            DaylightUI:Set(BL.MODULE, path(key), DaylightUI:Get(BL.MODULE, path(key)) ~= true)
        end,
        function()
            local n = 0
            for _, s in ipairs(BL.ReminderData.STATS) do
                if DaylightUI:Get(BL.MODULE, path(s.key)) == true and not locked(s.key) then n = n + 1 end
            end
            return n == 0 and L["None"] or string.format(L["%d on"], n)
        end)
end

local function reminderItemsCard()
    local function off(key) return function(get) return get(R .. key) ~= true end end
    return {
        whereRow("items", "Consumables: where to show"),
        soundRow("items", "Consumables sound"),
        rToggle("items.camp", "Camp Benefits", "Reminds you when the Camp Benefits campfire buff is missing.", { search = "Campfire" }),
        rToggle("items.bag", "Sleeping bag",
            "Reminds you when your Well-Rested buff is missing or under 3 stacks. Only while a Cozy Sleeping Bag is in your bags and you are below max level. Click the icon to use it."),
        rSlider("items.bagBelow", "Sleeping bag show below, in minutes", 0, 10, 1,
            "Also reminds you this many minutes before Well-Rested runs out. At 0, never early.", { disabled = off("items.bag") }),
        rToggle("items.bagTimer", "Sleep timer", "Counts down to three Well-Rested stacks while you sleep in the bag.", { disabled = off("items.bag") }),
        rToggle("items.wellFed", "Well Fed", "Reminds you when you have no Well Fed buff. Click the icon to eat.", { search = "Food" }),
        rSlider("items.wellFedBelow", "Well Fed show below, in minutes", 0, 10, 1,
            "Also reminds you this many minutes before Well Fed runs out. At 0, never early.", { disabled = off("items.wellFed") }),
        rToggle("items.censer", "Arcane Censer",
            "Reminds you in dungeons when Magical Awareness is missing, while an Arcane Censer is in your bags. Click the icon to use it."),
        statMenu(),
        rToggle("items.separate", "Scrolls and elixirs separately", "One icon for each ticked stat instead of one for the first."),
        rToggle("items.stronger", "Show stronger buffs",
            "Suggests a scroll or elixir from your bags when it gives more of its stat than the buff you have."),
        rankRow("items.statLowRank", "Scrolls and elixirs rank to use",
            "The highest or the lowest scroll or elixir you carry for each stat. A choice made by right-clicking wins."),
        rSlider("items.statBelow", "Scrolls and elixirs show below, in minutes", 0, 10, 1,
            "Shows a countdown before a scroll or elixir buff runs out. At 0 only once it has run out."),
        rToggle("items.oil", "Weapon stones and oils", "Reminds you when a weapon has no stone or oil. Click the icon to put one on from your bags.",
            { search = "Sharpening Weightstone Wizard Oil" }),
        handRow("mhTemp", "Main hand stone or oil", false, nil, off("items.oil")),
        handRow("ohTemp", "Off hand stone or oil", false, function() return not canDual() end, off("items.oil")),
    }
end

local PREVIEW = { type = "button", label = "Preview the buff bar",
    text = function() return BL.Preview.Active() and "Hide" or "Show" end,
    desc = "Fills the bar with a sample of every buff it knows, sorted and colored as they would be.",
    func = function()
        if BL.Preview.Active() then BL.Preview.Set(nil) else BL.Preview.Set(BL.PREVIEW_SHARE, BL.PREVIEW_MAX) end
    end }

-- Time left and stack count rows cover both bars, so the same rows sit on the
-- Buffs and the Debuffs page.
local TEXT_DESC = "Applies to both the buff and debuff bars."
local TEXT_ITEMS = {
    { type = "toggle", key = "settings.showTimers", label = "Show time left",
      desc = "How long each buff and debuff has left, on its icon." },
    { type = "dropdown", key = "settings.timePos", label = "Time left position",
      values = { top = "Top", middle = "Middle", bottom = "Bottom" }, order = { "top", "middle", "bottom" },
      desc = "Where the time sits: on the icon's top edge, across its middle, or on its bottom edge.",
      disabled = function(get) return get("settings.showTimers") ~= true end },
    { type = "toggle", key = "settings.expiring", label = "Orange timer when running out",
      desc = "A buff's time turns orange and gently pulses in its last 5 seconds. Debuffs keep their usual time color.",
      disabled = function(get) return get("settings.showTimers") ~= true end },
    { type = "toggle", key = "settings.newGlow", label = "Slide icons in and out",
      desc = "Buffs and debuffs slide in as they land and lift away as they leave. Needs Motion effects (General > Appearance).",
      disabled = function() return DaylightUI:Get("general", "motion") == false end },
    { type = "slider", key = "settings.timeSize", label = "Time left text size", min = 0, max = 20, step = 1,
      desc = "Text size of the time left on each icon. At 0 it follows the icon's size.", disabled = function(get) return get("settings.showTimers") ~= true end },
    { type = "slider", key = "settings.countSize", label = "Stack count size", min = 6, max = 20, step = 1,
      desc = "The number on an icon showing how many stacks it has." },
    { type = "dropdown", key = "settings.textOutline", label = "Text outline",
      values = { general = "Same as General", none = "None", thin = "Thin", thick = "Thick" },
      order = { "general", "none", "thin", "thick" },
      desc = "The outline round the time and stack count on buffs and debuffs, apart from General > Appearance's, so the time stays easy to read over any icon." },
}

BL.OPTIONS = { pages = {
    { id = "buffs", label = "Buffs",
      desc = "Your buffs, sorted into colored categories. Right-click a buff to cancel it; shift-click to move it to another category. The bar sits beside the info panel; to move it, turn off Attach to the info panel.",
      groups = {
        { label = "Bar", items = barItems(false) },
        { label = "Filter", desc = "Which buffs show, from the lists on Unit Frames > Aura Lists.", items = filterItems(false) },
        { label = "Text", desc = TEXT_DESC, items = TEXT_ITEMS },
        { label = "Missing buffs",
          desc = "A row of icons above you shows the buffs you're missing. Middle-click one to hide it until the next loading screen. Move the row in unlock mode.",
          items = reminderCore() },
        { label = "Missing buffs look", desc = "How the row of missing buffs looks.", items = reminderLook() },
        { label = "Raid buffs", desc = "The raid buffs you give, and the ones others give that you lack.", items = reminderRaid() },
        { label = "Self buffs", desc = "Your class's own buffs, weapon poisons and imbues, tracking and spells you add. Out of a fight only.", items = reminderSelf() },
        { label = "Consumables", desc = "Food, scrolls and elixirs, the sleeping bag, the Arcane Censer, stones and oils. Out of a fight only.", items = reminderItemsCard() },
        { label = "Combine into one icon", desc = "Categories set to Combine show as one icon; hover it to see them all.", items = {
            { type = "toggle", key = "settings.consolidateOnlyGroup", label = "Combine only in a group",
              desc = "Needs a category set to Combine (Categories page).", disabled = noneCombine },
            { type = "toggle", key = "settings.consolidateOnlyRaid", label = "Combine only in a raid",
              desc = "Needs a category set to Combine (Categories page).", disabled = noneCombine },
        } },
        { label = "More", items = {
            PREVIEW,
            { type = "toggle", key = "settings.hideBlizzardFrames", invert = true, label = "Show the game's buff frames",
              desc = "The game's own buff frames show beside Daylight UI's bars. When off, Daylight UI's bars replace them (the game's still show while Edit Mode is open)." },
        } },
    } },
    { id = "debuffs", label = "Debuffs",
      desc = "Debuffs on you, soonest to expire first, with a border colored by dispel type.",
      groups = {
        { label = "Bar", items = barItems(true) },
        { label = "Filter", desc = "Which debuffs show on this bar.", items = filterItems(true) },
        { label = "Text", desc = TEXT_DESC, items = TEXT_ITEMS },
        { label = "Hidden boss debuffs",
          desc = "Some boss abilities put debuffs on you that addons can't see. The game draws them itself, in a row under your debuffs.",
          items = {
            { type = "toggle", key = "settings.debuff.privateAuras", label = "Show hidden boss debuffs",
              desc = "Boss debuffs that addons can't read, drawn by the game itself. Up to three, at the debuffs' size, with a countdown. They only appear when a boss uses them. With the game's buff frames shown, the game shows them there instead.",
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
