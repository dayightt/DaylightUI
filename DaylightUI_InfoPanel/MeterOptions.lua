-- The Meters options page. The Windows tab lists every meter window with
-- rename, move and delete. The other tabs edit one window at a time, chosen
-- with "Settings for": rows are keyed "win.<setting>" and mapKey points them at
-- that window's settings (Windows.Path). Rows that don't apply to the window's
-- kind are hidden and locked, so Reset never writes them into the wrong window.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local MO = {}
ns.MeterOptions = MO

MO.PAGE = "InfoPanel.meter"
MO.picked = "main"            -- the window the rows edit (a session's pick)
MO.LINE = 30                  -- the window list's lines

local function Widgets() return DUI.Widgets end
local function Windows() return ns.Windows end

-- The picked window ({ id, kind, cfg, builtin, path }), the panel's meter
-- when the pick is gone.
function MO.Entry()
    local e = Windows().Get(nil, MO.picked)
    if not e then
        MO.picked = "main"
        e = Windows().Get(nil, "main")
    end
    return e
end

local function kind() local e = MO.Entry(); return e and e.kind end

-- Where a row applies: kinds = { meter = true, ... }; only = "main" (the
-- panel's meter), "threat" (the threat meter beside it) or "own" (one of
-- the player's windows).
local function applies(item)
    local e = MO.Entry()
    if not e then return false end
    if item.kinds and not item.kinds[e.kind] then return false end
    if item.only == "main" and e.id ~= "main" then return false end
    if item.only == "threat" and e.id ~= "threat" then return false end
    if item.only == "own" and e.builtin then return false end
    if item.notOnly == "main" and e.id == "main" then return false end
    if item.when and not item.when(e) then return false end
    return true
end

-- A row of the picked window's: hidden where it doesn't apply (its own
-- rule on top).
local function win(item)
    local own = item.hidden
    item.applies = applies
    item.hidden = function(get)
        if not applies(item) then return true end
        if own then return own(get) == true end
        return false
    end
    return item
end

local METER = { meter = true }
local THREAT = { threat = true }
local SUMMARY = { summary = true }
local LISTS = { meter = true, summary = true }
local BARS = { meter = true, threat = true }
local ALL = { meter = true, threat = true, summary = true }

local function off(get) return get("win.enabled") ~= true end

-- The mode names, from the meter's own list.
local function modeChoices()
    local names, order = {}, {}
    for _, m in ipairs(ns.Meter.MODES) do
        names[m.key] = m.name
        order[#order + 1] = m.key
    end
    return names, order
end

-- ---------------------------------------------------------------------
-- Picking, and the window list
-- ---------------------------------------------------------------------

-- Redraws the page if it's on screen (its rows read the new window).
local function refresh()
    local P = DUI.OptionsPanel
    if P and P.IsShown and P.IsShown() and P.Current and P.Current() == MO.PAGE and P.Refresh then
        DUI.SafeCall(P.Refresh)
    end
end

-- The rows edit window id from now on ("main" when nil or gone).
function MO.Pick(id)
    MO.picked = id or "main"
    MO.Entry()
    refresh()
end

DUI.On("MeterWindowsChanged", function()
    MO.Entry()   -- a removed pick falls back to the panel's meter
    refresh()
end)

-- A new window from a preset, picked at once.
function MO.New(presetKey)
    local id = Windows().Add(presetKey)
    if not id then
        DUI.Print(string.format(L["There are already %d meter windows of your own: remove one to make another."], Windows().MAX))
        return nil
    end
    if DUI.Sound then DUI.Sound.Play("open") end   -- a window opens
    MO.Pick(id)
    return id
end

-- What a window shows and where it is, for its line.
local function whatOf(e)
    if e.kind == "threat" then return L["Threat"] end
    if e.kind == "summary" then return L["Every number, by player"] end
    for _, m in ipairs(ns.Meter.MODES) do
        if m.key == e.cfg.mode then return L[m.name] end
    end
    return ""
end

local function whereOf(e)
    if e.id == "main" then return e.cfg.detached and L["Own window"] or L["In the info panel"] end
    if e.id == "threat" then
        local at = e.cfg.at
        return at == "free" and L["Own window"] or at == "below" and L["Under the meter"] or L["Beside the meter"]
    end
    return L["Own window"]
end

local function iconOf(e)
    if e.kind == "threat" then return "threat" end
    if e.kind == "summary" then return "summary" end
    for _, m in ipairs(ns.Meter.MODES) do
        if m.key == e.cfg.mode then return m.icon end
    end
    return "damage"
end

local function buildLine(list)
    local W, Style = Widgets(), DUI.Style
    local line = CreateFrame("Frame", nil, list)
    line:SetHeight(MO.LINE)
    line.icon = line:CreateTexture(nil, "ARTWORK")
    line.icon:SetSize(16, 16)
    line.icon:SetPoint("LEFT", line, "LEFT", 4, 0)
    line.name = W.Link(line, Style.SIZE.body)
    line.name:SetPoint("LEFT", line.icon, "RIGHT", 10, 6)
    line.name:SetScript("OnClick", function()
        local e = Windows().Get(nil, line.id)
        if not e then return end
        W.Prompt(string.format(L["Rename %s:"], Windows().Name(e)), Windows().Name(e), function(text)
            Windows().Rename(line.id, text)
        end)
    end)
    line.name:HookScript("OnEnter", function(self) W.Tooltip(self, L["Name"], L["Click to rename."]) end)
    line.name:HookScript("OnLeave", W.HideTooltip)
    line.sub = Style.Text(line, Style.SIZE.small, "LEFT")
    line.sub:SetPoint("LEFT", line.icon, "RIGHT", 10, -7)
    Style.InkText(line.sub, "LABEL")
    -- Right to left: delete (two clicks), move, edit.
    local del = W.DeleteButton(line)
    del:SetPoint("RIGHT", line, "RIGHT", 0, 0)
    del.text = Style.Text(line, Style.SIZE.small, "RIGHT")
    del.text:SetPoint("RIGHT", del, "LEFT", -4, 0)
    Style.InkText(del.text, "WARN")
    local token = 0
    function del.Arm(on)
        del.armed = on
        del.text:SetText(on and L["Click again"] or "")
    end
    del:SetScript("OnClick", function()
        if not del.armed then
            del.Arm(true)
            token = token + 1
            local mine = token
            C_Timer.After(W.CONFIRM or 3, function() if token == mine then del.Arm(false) end end)
            return
        end
        token = token + 1
        del.Arm(false)
        -- The sound an "Are you sure?" makes when it goes through (W.Confirm's).
        if Windows().Remove(line.id) and DUI.Sound then DUI.Sound.Play("gone") end
    end)
    del:HookScript("OnEnter", function(self) W.Tooltip(self, L["Delete"], L["Removes this window and its settings. Click twice."]) end)
    del:HookScript("OnLeave", W.HideTooltip)
    line.delete = del
    line.move = W.MoveButtons(line)
    line.move:SetPoint("RIGHT", del, "LEFT", -76, 0)   -- room for "Click again"
    line.move.up:SetScript("OnClick", function() Windows().Move(line.id, -1) end)
    line.move.down:SetScript("OnClick", function() Windows().Move(line.id, 1) end)
    line.edit = W.Link(line, Style.SIZE.small)
    line.edit.SetLabel(L["Settings"])
    line.edit:SetPoint("RIGHT", line.move, "LEFT", -12, 0)
    line.edit:SetScript("OnClick", function()
        MO.Pick(line.id)
        local P = DUI.OptionsPanel
        if P and P.SetTab then P.SetTab("Shows") end
    end)
    return line
end

local function updateLine(line, e, i, own)
    local Style = DUI.Style
    line.id = e.id
    line.icon:SetTexture(ns.Meter.ICON(iconOf(e)))
    line.icon:SetVertexColor(Style.Accent())
    line.name.SetLabel(Windows().Name(e))
    local state = e.cfg.enabled == false and (" · " .. L["Off"]) or ""
    line.sub:SetText(whatOf(e) .. " · " .. whereOf(e) .. state)
    line.delete:SetShown(not e.builtin)
    line.move:SetShown(not e.builtin)
    if not e.builtin then
        line.move.up.SetUsable(own[1] ~= e.id)
        line.move.down.SetUsable(own[#own] ~= e.id)
    end
    if line.shownId ~= e.id then line.delete.Arm(false) end
    line.shownId = e.id
    Widgets().Stripe(line, i % 2 == 0)
end

function MO.UpdateList(row)
    local list = Windows().List()
    local ownIds = {}
    for _, e in ipairs(list) do if not e.builtin then ownIds[#ownIds + 1] = e.id end end
    for i, e in ipairs(list) do
        local line = row.lines[i]
        if not line then
            line = buildLine(row.list)
            row.lines[i] = line
        end
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", row.list, "TOPLEFT", 0, -(i - 1) * MO.LINE)
        line:SetPoint("TOPRIGHT", row.list, "TOPRIGHT", 0, -(i - 1) * MO.LINE)
        updateLine(line, e, i, ownIds)
        line:Show()
    end
    for i = #list + 1, #row.lines do row.lines[i]:Hide() end
    row.count = #list
    row.list:SetHeight(math.max(1, #list * MO.LINE))
end

local windowList = {
    type = "custom", label = "Your windows",
    build = function(row)
        row.lines = {}
        row.list = CreateFrame("Frame", nil, row)
        row.list:SetPoint("TOPLEFT", row, "TOPLEFT", Widgets().PAD, -4)
        row.list:SetPoint("TOPRIGHT", row, "TOPRIGHT", -Widgets().PAD, -4)
        MO.list = row
    end,
    update = function(row) MO.UpdateList(row) end,
    height = function(row) return (row.count or #Windows().List()) * MO.LINE + 8 end,
}

local newWindow = {
    type = "custom", label = "New window",
    build = function(row)
        local W = Widgets()
        local b = W.MenuButton(row, L["New window"])
        b:SetWidth(200)
        b:SetPoint("LEFT", row, "LEFT", W.PAD, 0)
        b:SetScript("OnClick", function(self)
            local keys, values = {}, {}
            for _, p in ipairs(Windows().PRESETS) do
                keys[#keys + 1] = p.key
                values[p.key] = L[p.label]
            end
            W.OpenMenu(self, keys, values, nil, function(k) MO.New(k) end, 220)
        end)
        local hint = DUI.Style.Text(row, DUI.Style.SIZE.small, "LEFT")
        hint:SetPoint("LEFT", b, "RIGHT", 12, 0)
        hint:SetPoint("RIGHT", row, "RIGHT", -W.PAD, 0)
        DUI.Style.InkText(hint, "LABEL")
        row.hint = hint
    end,
    update = function(row)
        row.hint:SetText(string.format(L["Up to %d of your own, each with its own settings and spot. Move them in unlock mode."], Windows().MAX))
    end,
    height = function() return 40 end,
}

-- "Settings for": which window the rows below edit (one per tab).
local function picker()
    return {
        type = "custom", label = "Settings for",
        build = function(row)
            local W = Widgets()
            row.label = DUI.Style.Text(row, DUI.Style.SIZE.body, "LEFT")
            row.label:SetPoint("LEFT", row, "LEFT", W.PAD, 0)
            row.label:SetText(L["Settings for"])
            DUI.Style.InkText(row.label, "TEXT")
            local b = W.MenuButton(row, "")
            b:SetWidth(220)
            b:SetPoint("RIGHT", row, "RIGHT", -W.PAD, 0)
            b:SetScript("OnClick", function(self)
                local keys, values = {}, {}
                for _, e in ipairs(Windows().List()) do
                    keys[#keys + 1] = e.id
                    values[e.id] = Windows().Name(e)
                end
                W.OpenMenu(self, keys, values, MO.picked, function(id) MO.Pick(id) end, 220)
            end)
            row.button = b
        end,
        update = function(row) row.button.SetLabel(Windows().Name(MO.Entry()), 220) end,
        height = function() return 36 end,
    }
end

-- ---------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------

local KEEP = { nothing = "Keep old fights", ask = "Ask to reset", reset = "Reset" }
local KEEP_ORDER = { "nothing", "ask", "reset" }

local function barColorChoices()
    if kind() == "threat" then
        return { class = "Class color", threat = "By threat", custom = "One color" }, { "class", "threat", "custom" }
    end
    return { class = "Class color", custom = "One color" }, { "class", "custom" }
end
local function headerChoices()
    if kind() == "threat" then return { always = "Always", off = "Off" }, { "always", "off" } end
    return { always = "Always", hover = "With the mouse over it" }, { "always", "hover" }
end

local SUMMARY_COLS = {
    { "damage", "Damage column" }, { "dps", "DPS column" }, { "healing", "Healing column" }, { "hps", "HPS column" },
    { "interrupts", "Interrupts column" }, { "dispels", "Dispels column" }, { "deaths", "Deaths column" },
}

function MO.Page()
    local shows = {
        picker(),
        win({ type = "toggle", key = "win.enabled", label = "Show this window", notOnly = "main",
              desc = "Switched off, the window is gone (its settings stay). The threat meter beside the meter shows by its own rules below." }),
        win({ type = "dropdown", key = "win.mode", label = "Meter mode", kinds = METER, choices = modeChoices, disabled = off,
              desc = "What this meter lists: damage, DPS, healing, absorbs, damage taken, interrupts, dispels, deaths and more. The button in its header changes it too." }),
        win({ type = "dropdown", key = "win.session", label = "Meter fight", kinds = LISTS, disabled = off,
              values = { current = "This fight", overall = "Overall" }, order = { "current", "overall" },
              desc = "Whether this window counts the fight you're in or every fight since the last reset." }),
        win({ type = "toggle", key = "win.inGroup", label = "Show only in a group", kinds = LISTS, disabled = off,
              desc = "The window hides while you play solo." }),
        win({ type = "toggle", key = "win.inCombat", label = "Show only in combat", kinds = LISTS, disabled = off,
              desc = "With more than one of these on, it shows only when all of them hold." }),
        win({ type = "toggle", key = "win.inInstance", label = "Show only in an instance", kinds = LISTS, disabled = off,
              desc = "The window hides outside dungeons, raids, battlegrounds and arenas." }),
        win({ type = "dropdown", key = "win.auto", label = "Slide out automatically", kinds = THREAT, disabled = off,
              values = { group = "In a group or with a pet", tank = "When I'm the tank", off = "Only from its tab" },
              order = { "group", "tank", "off" },
              desc = "Never shown solo: then everything is on you. The threat meter beside the meter slides back once the fight ends, and a click on its tab overrides this until the next fight. A threat window of your own set to Never shows in every fight in a group." }),
        win({ type = "dropdown", key = "win.at", label = "Threat meter position", kinds = THREAT, only = "threat", disabled = off,
              values = { left = "Beside the meter", below = "Under the meter", free = "Its own window" },
              order = { "left", "below", "free" },
              desc = "Under the meter it rises out of the damage meter's bottom, as wide as the meter. Docked, it shows only while the damage meter is open. Its own window goes anywhere: move it in unlock mode." }),
        win({ type = "dropdown", key = "win.unit", label = "Whose threat", kinds = THREAT, only = "own", disabled = off,
              values = { target = "Your target", focus = "Your focus", smart = "Your target, else your target's target" },
              order = { "target", "focus", "smart" },
              desc = "The last one follows your target when you can attack it, else the mob your friendly target is on: handy for a healer watching the tank." }),
        win({ type = "slider", key = "win.rows", label = "Threat meter rows", kinds = THREAT, min = 2, max = 10, step = 1, disabled = off,
              hidden = function(get) return MO.picked == "threat" and get("win.at") == "below" end,
              desc = "The most group members it lists at once." }),
        win({ type = "slider", key = "win.belowRows", label = "Threat meter rows under the meter", kinds = THREAT, only = "threat",
              min = 2, max = 6, step = 1, disabled = off,
              hidden = function(get) return get("win.at") ~= "below" end,
              desc = "The most group members it lists under the damage meter." }),
        { type = "toggle", key = "meter.enabled", label = "Show the damage meter", only = "main",
          desc = "Replaces the game's damage meter window. The tab on the panel's edge, on the meter's side, also shows or hides it." },
    }
    win(shows[#shows])
    for _, c in ipairs(SUMMARY_COLS) do
        shows[#shows + 1] = win({ type = "toggle", key = "win.columns." .. c[1], label = c[2], kinds = SUMMARY, disabled = off,
                                  desc = "Whether the summary shows this column." })
    end

    local rows = {
        picker(),
        win({ type = "slider", key = "win.rowHeight", label = "Bar height", kinds = ALL, min = 10, max = 32, step = 1, unit = "px",
              desc = "How tall each bar is." }),
        win({ type = "slider", key = "win.rowGap", label = "Bar spacing", kinds = METER, min = 0, max = 8, step = 1, unit = "px",
              desc = "The space between two bars." }),
        win({ type = "slider", key = "win.textSize", label = "Text size", kinds = ALL, min = 7, max = 18, step = 1,
              desc = "Size of the names and numbers on the bars." }),
        win({ type = "toggle", key = "win.rank", label = "Rank numbers", kinds = METER,
              desc = "Each player's place, before their icon." }),
        win({ type = "dropdown", key = "win.icons", label = "Bar icons", kinds = METER,
              values = { class = "Class", none = "None" }, order = { "class", "none" },
              desc = "The small square before each name: the player's class icon, or nothing." }),
        win({ type = "toggle", key = "win.showTotal", label = "Show totals", kinds = METER,
              desc = "Each player's total, the first number on their bar." }),
        win({ type = "toggle", key = "win.showRate", label = "Show per second", kinds = METER,
              desc = "Damage or healing per second, in brackets after the total." }),
        win({ type = "toggle", key = "win.showShare", label = "Show share", kinds = METER,
              desc = "Each player's share of everyone's total, in brackets. The game hides the numbers during a fight, so it shows once the fight is over." }),
        win({ type = "toggle", key = "win.showMe", label = "Always show yourself", kinds = METER,
              desc = "When you'd be scrolled out of view, your bar stays in the last row with your place." }),
        win({ type = "dropdown", key = "win.header", label = "Window header", kinds = BARS, choices = headerChoices,
              desc = "The line on top: the mode, the fight and its length (a meter), or the mob and your own threat (a threat meter). A meter's buttons show in it while the mouse is over the window." }),
        win({ type = "toggle", key = "win.headerTotal", label = "Group total in the header", kinds = METER,
              desc = "Everyone's total for the fight, beside its length." }),
        win({ type = "dropdown", key = "win.barColor", label = "Bar color", kinds = BARS, choices = barColorChoices,
              desc = "Each bar in its player's class color or all in one color; a threat meter can color each bar by how close that player is to pulling." }),
        win({ type = "toggle", key = "win.angled", label = "Angled bar ends", kinds = BARS, since = "1.7.0",
              desc = "The bars' filled part ends in a slanted edge. When off, it ends square." }),
        win({ type = "toggle", key = "win.gradient", label = "Bar gradient", kinds = BARS,
              desc = "The bars shade from dark to bright instead of one flat color. The color pairs are on General > Gradients." }),
        win({ type = "color", key = "win.barCustom", label = "Custom bar color", kinds = BARS,
              hidden = function(get) return get("win.barColor") ~= "custom" end,
              desc = "The bars' color when Bar color is One color." }),
        win({ type = "toggle", key = "win.classText", label = "Class-colored names and numbers", kinds = METER,
              desc = "Each bar's name and number in that player's class color." }),
        win({ type = "color", key = "win.nameColor", label = "Name color", kinds = BARS,
              disabled = function(get) return get("win.classText") == true end,
              desc = "The color of the names on the bars." }),
        win({ type = "slider", key = "win.trackAlpha", label = "Bar background opacity", kinds = BARS, min = 0, max = 1, step = 0.05, unit = "%",
              desc = "How solid the empty part and outline of each bar are. At 0 only the colored bars show." }),
        win({ type = "toggle", key = "win.pullLine", label = "Pull line", kinds = THREAT,
              desc = "A thin line across the bars where your threat would pull the mob: 110% of the tank's in melee, 130% at range. Not shown against a boss, whose numbers the game keeps hidden." }),
        win({ type = "color", key = "win.pullColor", label = "Pull line color", kinds = THREAT,
              disabled = function(get) return get("win.pullLine") ~= true end,
              desc = "The color of the pull line across the threat bars." }),
        win({ type = "toggle", label = "First and last names", kinds = THREAT,
              get = function() return DUI:Get("general", "lastNames.threat") == true end,
              set = function(v) DUI:Set("general", "lastNames.threat", v) end,
              default = function() return false end,
              desc = "Players' last names after their first on the threat meters. When off, first names only, which fit the narrow rows better." }),
    }
    local what = "every meter's and threat meter's bars"
    rows[#rows + 1] = DUI.Options.BarRow("media.meter", "Meter bar", what)
    rows[#rows + 1] = DUI.Options.BackRow("media.meter", "Meter bar", what)
    rows[#rows + 1] = DUI.Options.FontRow("media.meterFont", "Meter font", "Names and numbers on every meter and threat meter")

    -- The panel's meter inside the panel has no window of its own.
    local function ownWindow(e) return e.id ~= "main" or e.cfg.detached == true end
    local back = DUI.Options.BackAlphaRows("win.alpha", "Meter window")
    back[1].desc = "Gives this window its own background opacity, set in the row below. When off, it's as see-through as the info panel's boxes (General page)."
    back[2].desc = "How solid this window's background is: 0 is fully see-through, leaving only the bars."
    back[1].kinds, back[2].kinds, back[1].when, back[2].when = ALL, ALL, ownWindow, ownWindow
    local window = {
        picker(),
        { type = "toggle", key = "meter.detached", label = "Separate window", only = "main",
          desc = "Takes the damage meter out of the panel into its own window in the bottom-right corner; move it in unlock mode." },
        win({ type = "slider", key = "win.width", label = "Width", kinds = ALL, min = 100, max = 600, step = 1, unit = "px",
              hidden = function(get) return MO.picked == "threat" and get("win.at") == "below" end,
              desc = "How wide the window is. Dragging its corner in unlock mode sets it too." }),
        win({ type = "slider", key = "win.height", label = "Window height", kinds = LISTS, min = 80, max = 500, step = 1, unit = "px",
              when = ownWindow,
              desc = "How tall the window is. Dragging its corner in unlock mode sets it too." }),
        win({ type = "toggle", key = "win.border", label = "Window border", kinds = ALL, when = ownWindow,
              desc = "A border and shadow around the window." }),
        win(back[1]), win(back[2]),
    }
    win(window[2])

    local shared = {
        { type = "dropdown", key = "meter.numbers", label = "Meter numbers",
          values = ns.Meter.NUMBERS, order = ns.Meter.NUMBER_ORDER,
          desc = "Amounts shortened (12.3K) or in full (12,345), on every meter, the breakdowns and reports." },
        { type = "toggle", key = "meters.sameFight", label = "Windows show the same fight",
          desc = "Picking an earlier fight in one window shows it in every window on This fight. Windows on Overall stay there." },
        { type = "toggle", key = "meters.backToCurrent", label = "Back to the current fight on a pull",
          desc = "A window showing an earlier fight goes back to this fight (or Overall) as the next one starts." },
        { type = "dropdown", key = "meter.onJoin", label = "Meter on joining a group",
          values = KEEP, order = KEEP_ORDER,
          desc = "What happens to the fights you have so far when you join a group: keep them, ask whether to reset, or reset at once." },
        { type = "dropdown", key = "meter.onInstance", label = "Meter in a new instance",
          values = KEEP, order = KEEP_ORDER,
          desc = "What happens to the fights you have so far when you enter a dungeon, raid or battleground: keep them, ask whether to reset, or reset at once. Running back after you die doesn't count." },
    }

    local threatFade = DUI.Fade.Card("threat.fade.", { { type = "text", label = "The threat meter and your threat windows fade together, apart from the panel." } }, nil, "Threat meter")
    threatFade.label = "Threat meter fade"
    threatFade.tab = nil

    return { id = "meter", label = "Meters",
        desc = "Damage, healing and threat meters: the one in the info panel, the threat meter beside it, and as many windows of your own as you like.",
        mapKey = function(key)
            if type(key) == "string" and key:sub(1, 4) == "win." then
                return Windows().Path(MO.Entry().id) .. "." .. key:sub(5)
            end
            return key
        end,
        -- Rows that don't apply to the picked window: never written.
        locked = function(_, item) return item.applies ~= nil and not item.applies(item) end,
        groups = {
            { label = "Your windows", tab = "Windows", desc = "Click a name to rename it. A click on Settings edits that window on the other tabs.",
              items = { windowList, newWindow } },
            { label = "All meters", items = shared },
            { label = "When it shows", tab = "Shows", items = shows },
            { label = "Bars", tab = "Bars", items = rows },
            { label = "Window", tab = "Window", items = window },
            threatFade,
        },
    }
end
