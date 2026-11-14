-- The action bars' option pages, as data: the buttons' look and each bar's shape,
-- both applied live (a shape change re-lays the bars via Bars.LayoutBar).

local _, ns = ...

-- Effects that need General > Appearance > Motion effects on.
local function motionOff() return DaylightUI:Get("general", "motion") == false end

local function always() return true end

local function unless(key, value)
    return function(get) return get(key) ~= value end
end

local SHOW = { hidden = "Hidden", shown = "Shown" }
local SHOW_ORDER = { "hidden", "shown" }
-- The bag bar or micro menu size. It's the game's Edit Mode setting, stored in its
-- layout (Hide.SetSize), not in ours.
local function menuSize(key, label)
    local s = ns.Hide.SIZE[key]
    return { type = "slider", label = label, min = s.min / 100, max = s.max / 100, step = s.step / 100, unit = "%",
             desc = "How big it is, as a percent of its normal size. This is Edit Mode's own size setting, kept in your Edit Mode layout.",
             get = function() return ns.Hide.GetSize(key) end,
             set = function(v) ns.Hide.SetSize(key, v) end,
             default = function() return 1 end,
             disabled = unless(key, "shown") }
end
local ACCENT = { accent = "The accent", custom = "Your own color" }
local ACCENT_ORDER = { "accent", "custom" }

-- The look rows below apply to whatever "Settings for" picks: every bar (db.look),
-- one bar, or the Cooldown Manager (db.barLooks[key], only what differs from the
-- all-bars look). Rows marked cdm also show for the Cooldown Manager; the rest are
-- for action buttons only.
local DUI = DaylightUI
local lookFor = "all"
local function targets()
    local values, order = { all = "All bars" }, { "all" }
    for _, def in ipairs(ns.Bars.DEFS) do
        values[def.key] = def.label
        order[#order + 1] = def.key
    end
    values.cdm, order[#order + 1] = "Cooldown Manager", "cdm"
    return values, order
end
local function copyOf(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = x end
    return t
end
local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
-- A look setting of the picked target: its own if set, else the all-bars value.
local function lookGet(field, target)
    target = target or lookFor
    if target ~= "all" then
        local v = DUI:Get("ActionBars", "barLooks." .. target .. "." .. field)
        if v ~= nil then return v end
    end
    return DUI:Get("ActionBars", "look." .. field)
end
local function lookSet(field, v)
    if lookFor == "all" then return DUI:Set("ActionBars", "look." .. field, v) end
    -- Same as the all-bars value means no override of its own (it follows them again).
    if same(v, DUI:Get("ActionBars", "look." .. field)) then v = nil end
    DUI:Set("ActionBars", "barLooks." .. lookFor .. "." .. field, copyOf(v))
end
-- get(key) for a row's disabled/hidden: "look.x" reads the picked target.
local function lookGetter(get)
    return function(key)
        local field = type(key) == "string" and string.match(key, "^look%.(.+)$")
        if field then return lookGet(field) end
        return get(key)
    end
end
local function perLook(group)
    for _, item in ipairs(group.items) do
        local field = type(item.key) == "string" and string.match(item.key, "^look%.(.+)$")
        if field then
            item.key = nil
            item.get = function() return lookGet(field) end
            item.set = function(v) lookSet(field, v) end
            item.default = function()
                if lookFor == "all" then return copyOf(ns.DEFAULTS.look[field]) end
                return copyOf(DUI:Get("ActionBars", "look." .. field))
            end
            local dis = item.disabled
            if dis then item.disabled = function(get) return dis(lookGetter(get)) end end
        end
    -- Rows that don't apply to the Cooldown Manager hide while it's picked.
        local hid, cdm = item.hidden, item.cdm
        item.cdm = nil
        item.hidden = function(get)
            if lookFor == "cdm" and not cdm then return true end
            return hid ~= nil and hid(lookGetter(get)) == true
        end
    end
    return group
end

-- Copy look from...: copies another bar's own changes (or none, from All bars) onto
-- the picked one.
local copyFrom
local function copyChoicesLook()
    local values, order = targets()
    local v, o = {}, {}
    for _, k in ipairs(order) do
        if k ~= lookFor then v[k] = values[k]; o[#o + 1] = k end
    end
    return v, o
end
local function refreshPanel()
    local P = DUI.OptionsPanel
    if P and P.IsShown() then P.Refresh() end
end
local notAll = function() return lookFor == "all" end
-- Opens the look rows for one target (the Cooldown Manager page's button).
function ns.ShowLook(target)
    lookFor, copyFrom = target, nil
    DUI.OptionsPanel.Show("ActionBars.bars")
end
local custom = function(key) return function(get) return get(key) ~= "custom" end end
local COLOR_MODE = { shell = "Default", accent = "The accent", class = "Class color", custom = "Your own color" }
local COLOR_MODE_ORDER = { "shell", "accent", "class", "custom" }
local LIT = { accent = "The accent", class = "Class color", custom = "Your own color" }
local LIT_ORDER = { "accent", "class", "custom" }
local EDGE = { off = "None", accent = "The accent", class = "Class color", custom = "Your own color" }
local EDGE_ORDER = { "off", "accent", "class", "custom" }

-- A text's offset in px from its spot. cdm = the Cooldown Manager has it too.
local function nudge(field, label, cdm)
    return { type = "slider", key = "look." .. field, label = label, min = -20, max = 20, step = 1, unit = "px", cdm = cdm,
             desc = "Nudges this text away from its spot on the button, in pixels." }
end

local look = {
    { label = "Buttons", tab = "Basics", items = {
        { type = "toggle", key = "hideEmpty", invert = true, label = "Show empty buttons",
          desc = "Slots with nothing on them show as empty frames. When off, they disappear and show again while you drag a spell or item." },
        { type = "toggle", key = "readyPing", label = "Ping when ready", disabled = motionOff,
          desc = "A spell's icon pops and lights up once when it comes off a real cooldown (never for the global cooldown). Needs Motion effects (General > Appearance)." },
        { type = "toggle", key = "rankUp", label = "New ranks on your bars",
          desc = "When you learn a new rank of a spell, it takes the place of the rank before it on your bars. A lower rank you keep on purpose, like rank 1 to save mana, stays. Not macros." },
    } },
    perLook({ label = "Look", desc = "Pick All bars to change every bar at once, or one bar to give it a look of its own.", items = {
        { type = "dropdown", label = "Settings for", noSearch = true, cdm = true,
          desc = "Which buttons the look rows on this page change. A bar keeps what you change for it; the rest follows All bars.",
          choices = targets,
          get = function() return lookFor end,
          set = function(k) lookFor = k; copyFrom = nil; refreshPanel() end },
        { type = "dropdown", label = "Copy look from", noSearch = true, cdm = true,
          desc = "Another bar whose look to copy onto the one picked in Settings for.",
          choices = copyChoicesLook, hidden = notAll,
          get = function() return copyFrom end,
          set = function(k) copyFrom = k end },
        { type = "button", label = "Copy the look", text = "Copy", confirm = true, noSearch = true, cdm = true,
          desc = "Replaces the picked bar's look with a copy of the one above.",
          hidden = notAll,
          disabled = function() return copyFrom == nil end,
          func = function()
              if lookFor == "all" or copyFrom == nil then return end
              local own = copyFrom ~= "all" and DUI:Get("ActionBars", "barLooks." .. copyFrom)
              local t = {}
              if type(own) == "table" then for k, v in pairs(own) do t[k] = copyOf(v) end end
              DUI:Set("ActionBars", "barLooks." .. lookFor, t)
              copyFrom = nil
          end },
        { type = "dropdown", key = "look.shape", label = "Button shape", cdm = true,
          values = { square = "Square", circle = "Circle", diamond = "Diamond", hexagon = "Hexagon", octagon = "Octagon", shield = "Shield" },
          order = { "square", "circle", "diamond", "hexagon", "octagon", "shield" },
          desc = "The outline every button is cut to. The icon, border and cooldown shade all follow it." },
        { type = "dropdown", key = "look.borderStyle", label = "Border style", cdm = true,
          values = { daylight = "Daylight", flat = "Flat", none = "None" }, order = { "daylight", "flat", "none" },
          desc = "Daylight is the warm band inside a dark outline, Flat a plain outline. With None the icon fills the whole button." },
        { type = "slider", key = "look.border", label = "Border", min = 1, max = 6, step = 1, unit = "px", cdm = true,
          desc = "How thick the border around each button is.",
          disabled = function(get) return get("look.borderStyle") == "none" end },
        { type = "dropdown", key = "look.corners", label = "Corners", cdm = true,
          hidden = function(get) return get("look.shape") ~= "square" end,
          values = { round = "Rounded", square = "Square" }, order = { "round", "square" },
          desc = "Rounded follows the corner size on General > Appearance." },
        { type = "toggle", key = "look.shadow", label = "Button shadow", cdm = true,
          desc = "A soft shadow round each button." },
        { type = "dropdown", key = "look.borderColor", label = "Border color", values = COLOR_MODE, order = COLOR_MODE_ORDER,
          cdm = true, desc = "The edge round each button. A proc still lights it up." },
        { type = "color", key = "look.borderCustom", label = "Custom border color", cdm = true,
          desc = "The border color when Border color is set to Your own color.",
          hidden = custom("look.borderColor") },
        { type = "slider", key = "look.zoom", label = "Icon zoom", min = 0, max = 0.4, step = 0.02, unit = "%", cdm = true,
          desc = "Crops into the spell's icon so its art fills more of the button." },
    } }),
    perLook({ label = "Keybinds", tab = "Text", items = {
        { type = "button", label = "Quick keybind", text = "Bind keys",
          desc = "Hover a button and press a key to bind it, or Escape to clear it. Click Okay when you're done. Out of combat only.",
          disabled = function() return InCombatLockdown() end,
          func = function() ns.Keys.OpenQuick() end },
        { type = "toggle", key = "look.keybind", label = "Keybinds",
          desc = "Shows each button's key on the button. When off, the keys still work, you just don't see them." },
        { type = "slider", key = "look.keybindSize", label = "Keybind size", min = 6, max = 18, step = 1,
          desc = "Text size of the key shown on each button.",
          disabled = function(get) return get("look.keybind") ~= true end },
        { type = "color", key = "look.keybindColor", label = "Keybind color",
          desc = "Color of the key shown on each button.",
          disabled = function(get) return get("look.keybind") ~= true end },
        { type = "dropdown", key = "look.keybindPos", label = "Keybind position",
          values = { topright = "Top right", topleft = "Top left", bottom = "Bottom" }, order = { "topright", "topleft", "bottom" },
          desc = "Where on the button its key shows." },
        nudge("keybindX", "Keybind X offset"), nudge("keybindY", "Keybind Y offset"),
        { type = "toggle", key = "look.shortKeys", label = "Short keybinds",
          desc = "Shift, Ctrl and Alt as S, C and A; mouse buttons as M4, M5; the number pad as N1..." },
    } }),
    perLook({ label = "Text", items = {
        DaylightUI.Options.FontRow("media.font", "Button font", "Keybinds, stack counts, macro names and cooldown numbers on every bar, the Cooldown Manager and totems",
            nil, { cdm = true }),
        { type = "slider", key = "look.countSize", label = "Stack count size", min = 6, max = 20, step = 1, cdm = true,
          desc = "Text size of the count on a button, like charges or how many of an item you carry." },
        { type = "color", key = "look.countColor", label = "Stack count color", cdm = true,
          desc = "Color of the count on a button, like charges or how many of an item you carry." },
        { type = "dropdown", key = "look.countPos", label = "Stack count position",
          values = { bottomright = "Bottom right", bottomleft = "Bottom left" }, order = { "bottomright", "bottomleft" },
          desc = "Which corner of the button its count shows in." },
        nudge("countX", "Stack count X offset"), nudge("countY", "Stack count Y offset"),
        { type = "toggle", key = "look.macroNames", label = "Macro names",
          desc = "Shows a macro's name on its button. When off, macros show their icon only." },
        { type = "slider", key = "look.macroSize", label = "Macro name size", min = 6, max = 16, step = 1,
          desc = "Text size of the macro names on buttons.",
          disabled = function(get) return get("look.macroNames") ~= true end },
        { type = "color", key = "look.macroColor", label = "Macro name color",
          desc = "Color of the macro names on buttons.",
          disabled = function(get) return get("look.macroNames") ~= true end },
        nudge("macroX", "Macro name X offset"), nudge("macroY", "Macro name Y offset"),
        { type = "toggle", key = "look.cooldownNumbers", label = "Cooldown numbers", cdm = true,
          desc = "Shows the game's countdown on buttons that are on cooldown." },
        { type = "slider", key = "look.cooldownSize", label = "Cooldown number size", min = 8, max = 28, step = 1, cdm = true,
          desc = "Text size of the countdown on a button that's on cooldown.",
          disabled = function(get) return get("look.cooldownNumbers") ~= true end },
        { type = "color", key = "look.cooldownTextColor", label = "Cooldown number color", cdm = true,
          desc = "Color of the countdown on a button that's on cooldown.",
          disabled = function(get) return get("look.cooldownNumbers") ~= true end },
        nudge("cooldownX", "Cooldown number X offset", true), nudge("cooldownY", "Cooldown number Y offset", true),
        { type = "dropdown", key = "look.tooltips", label = "Button tooltips",
          values = { always = "Always", nocombat = "Out of combat only", never = "Never" },
          order = { "always", "nocombat", "never" },
          desc = "When hovering a button shows its spell or item tooltip." },
    } }),
    perLook({ label = "Bar background", tab = "Extras", desc = "A panel behind the whole bar.", items = {
        { type = "toggle", key = "look.back", label = "Bar background",
          desc = "A panel behind the whole bar, so its buttons sit on one strip." },
        { type = "color", key = "look.backColor", label = "Bar background color", alpha = true,
          desc = "Color and opacity of the panel behind the bar.",
          disabled = function(get) return get("look.back") ~= true end },
        { type = "toggle", key = "look.backBorder", label = "Bar background border",
          desc = "A border and shadow around the panel behind the bar. When off, the panel is a plain fill.",
          disabled = function(get) return get("look.back") ~= true end },
        { type = "slider", key = "look.backPad", label = "Bar background padding", min = 0, max = 16, step = 1, unit = "px",
          desc = "How far the panel reaches past the buttons on every side.",
          disabled = function(get) return get("look.back") ~= true end },
    } }),
    perLook({ label = "Colors", items = {
        { type = "color", key = "look.pressed", label = "Pressed color", desc = "A color over the icon while you press it." },
        { type = "toggle", key = "look.pressBorder", label = "Light the border when pressed",
          desc = "The button's border lights up while you press it." },
        { type = "dropdown", key = "look.pressBorderMode", label = "Pressed border color", values = LIT, order = LIT_ORDER,
          desc = "The color the border lights up in while you press a button.",
          disabled = function(get) return get("look.pressBorder") ~= true end },
        { type = "color", key = "look.pressBorderColor", label = "Custom pressed border color",
          desc = "The pressed border's color when Pressed border color is set to Your own color.",
          hidden = custom("look.pressBorderMode") },
        { type = "slider", key = "look.pressedAlpha", label = "Pressed opacity", min = 0, max = 1, step = 0.05,
          unit = "%", desc = "How strong the pressed color over the icon is." },
        { type = "toggle", key = "look.dip", label = "Shrink icon when pressed",
          desc = "A pressed button's icon sinks in a little and springs back as you let go." },
        { type = "color", key = "look.highlight", label = "Mouseover color",
          desc = "A color over the icon while the mouse is over it." },
        { type = "toggle", key = "look.hoverBorder", label = "Light the border on mouseover",
          desc = "The button's border lights up while the mouse is over it." },
        { type = "dropdown", key = "look.hoverBorderMode", label = "Mouseover border color", values = LIT, order = LIT_ORDER,
          desc = "The color the border lights up in while the mouse is over a button.",
          disabled = function(get) return get("look.hoverBorder") ~= true end },
        { type = "color", key = "look.hoverBorderColor", label = "Custom mouseover border color",
          desc = "The mouseover border's color when Mouseover border color is set to Your own color.",
          hidden = custom("look.hoverBorderMode") },
        { type = "slider", key = "look.highlightAlpha", label = "Mouseover opacity", min = 0, max = 1, step = 0.05,
          unit = "%", desc = "How strong the mouseover color over the icon is." },
        { type = "dropdown", key = "look.checked", label = "Active spell", values = ACCENT, order = ACCENT_ORDER,
          desc = "Highlights a spell that is active (an aura, auto attack, a stance) or being cast." },
        { type = "color", key = "look.checkedColor", label = "Active spell color", disabled = unless("look.checked", "custom"),
          desc = "The highlight's color when Active spell is set to Your own color." },
        { type = "slider", key = "look.checkedAlpha", label = "Active spell opacity", min = 0, max = 1, step = 0.05,
          unit = "%", desc = "How strong the highlight on an active spell is." },
        { type = "toggle", key = "look.checkedBorder", label = "Light the border on an active spell",
          desc = "The button's border lights up while its spell is queued, like Heroic Strike waiting for your next swing, or being cast." },
        { type = "toggle", key = "look.checkedGlow", label = "Glow on an active spell",
          desc = "A moving glow around the button while its spell is queued or being cast." },
        { type = "dropdown", key = "look.checkedBorderMode", label = "Active border and glow color", values = LIT, order = LIT_ORDER,
          desc = "The color of the lit border and the glow on an active spell.",
          disabled = function(get) return get("look.checkedBorder") ~= true and get("look.checkedGlow") ~= true end },
        { type = "color", key = "look.checkedBorderColor", label = "Custom active border and glow color",
          desc = "Their color when Active border and glow color is set to Your own color.",
          hidden = custom("look.checkedBorderMode") },
        -- Hidden: WoW Forever has no proc glows (the code stays, idle).
        { type = "dropdown", key = "look.proc", label = "Proc border", values = ACCENT, order = ACCENT_ORDER,
          desc = "The glowing border on a button when its spell procs.", hidden = always },
        { type = "color", key = "look.procColor", label = "Proc border color", hidden = always,
          desc = "The proc border's color when Proc border is set to Your own color." },
        { type = "dropdown", key = "look.range", label = "Out of range", values = { fade = "Fade the icon", color = "Tint the icon" },
          order = { "fade", "color" }, desc = "What a button does while your target is out of range. Not enough mana, rage or energy does the same (blue when tinted)." },
        { type = "color", key = "look.rangeColor", label = "Out of range color", disabled = unless("look.range", "color"),
          desc = "The tint on a button while your target is out of range, when Out of range is set to Tint the icon." },
        { type = "color", key = "look.swipeColor", label = "Cooldown shade color", cdm = true,
          desc = "The shade that sweeps over a button while it's on cooldown." },
        { type = "slider", key = "look.cooldownAlpha", label = "Cooldown shade opacity", min = 0, max = 1, step = 0.05,
          unit = "%", cdm = true, desc = "How dark the shade that sweeps over a button on cooldown is." },
        { type = "toggle", key = "look.cdGray", label = "Gray out on cooldown",
          desc = "A spell's icon turns gray while it's on cooldown. The global cooldown doesn't count." },
        { type = "slider", key = "look.cdAlpha", label = "Opacity on cooldown", min = 0.1, max = 1, step = 0.05, unit = "%",
          desc = "How see-through a spell's icon is while it's on cooldown. The global cooldown doesn't count." },
        { type = "dropdown", key = "look.edge", label = "Cooldown edge", values = EDGE, order = EDGE_ORDER, cdm = true,
          desc = "A bright line along the cooldown shade's moving edge." },
        { type = "color", key = "look.edgeColor", label = "Custom cooldown edge color", cdm = true,
          desc = "The cooldown edge's color when Cooldown edge is set to Your own color.",
          hidden = custom("look.edge") },
    } }),
    { label = "Bag bar and micro menu", tab = "Bag bar and menu", desc = "Their keybinds work even when hidden. Move them in unlock mode.", items = {
        { type = "dropdown", key = "bagBar", label = "Bag bar", values = SHOW, order = SHOW_ORDER,
          desc = "Shows or hides the row of bag buttons. Your bag keys still open your bags when it's hidden." },
        menuSize("bagBar", "Bag bar size"),
        { type = "dropdown", key = "microMenu", label = "Micro menu", values = SHOW, order = SHOW_ORDER,
          desc = "Shows or hides the row of small buttons that open your character, spellbook, talents and other windows. Their keys still work when it's hidden." },
        menuSize("microMenu", "Micro menu size"),
        { type = "toggle", key = "skinMenus", label = "Daylight UI style micro menu", reload = true,
          desc = "Gives the micro menu and bag bar the Daylight UI look: square frames in your action button border style." },
    } },
    { label = "Bag bar fade", desc = "When the shown bag bar fades and how far.",
      items = DaylightUI.Fade.Items("bagBarFade.", nil, unless("bagBar", "shown"), "Bag bar") },
    { label = "Micro menu fade", desc = "When the shown micro menu fades and how far.",
      items = DaylightUI.Fade.Items("microMenuFade.", nil, unless("microMenu", "shown"), "Micro menu") },
    { label = "Positions", tab = "Basics", items = {
        { type = "button", label = "Reset bar positions",
          desc = "Puts every bar back in the default arrangement.",
          func = function()
              ns.Bars.ResetPositions()
          end },
    } },
}
-- A bar's single Visible row combines its fade choices (bars.<bar>.fade.mode) and its
-- hiding ones (bars.<bar>.visible; a hidden bar can't be clicked, unlike a faded
-- one) in one list. It's keyed on the visible setting so a search jump finds it, and
-- it reads and writes both.
local visibleRow, pagingItems
local HIDES = { hidden = "Hidden", nocombat = "Hidden in combat", combat = "Hidden out of combat" }
local HIDE_ORDER = { "nocombat", "combat", "hidden" }
visibleRow = function(def, k)
    local caps = ns.Bars.KINDS[def.kind].Caps
    local show = ns.Bars.CHOICES[caps.show]
    local Fade = DaylightUI.Fade
    local values, order = {}, {}
    for _, m in ipairs(Fade.MODE_ORDER) do
        values[m] = m == "never" and show.values.always or Fade.MODES[m]
        order[#order + 1] = m
    end
    for _, v in ipairs(HIDE_ORDER) do
        if show.values[v] then values["hide:" .. v] = HIDES[v]; order[#order + 1] = "hide:" .. v end
    end
    local function pick(visible, mode)
        if visible ~= nil and visible ~= "always" and values["hide:" .. visible] then return "hide:" .. visible end
        return values[mode or "never"] and mode or "never"
    end
    return { type = "dropdown", key = k("visible"), alsoKeys = { k("fade.mode") }, label = "Visible", values = values, order = order,
        desc = Fade.MODE_DESC .. " Hidden (in combat, out of combat or always): gone, and its buttons can't be clicked.",
        get = function() return pick(DUI:Get("ActionBars", k("visible")), DUI:Get("ActionBars", k("fade.mode"))) end,
        set = function(v)
            local hide = string.match(v, "^hide:(.+)$")
            DUI:Set("ActionBars", k("visible"), hide or "always")
            DUI:Set("ActionBars", k("fade.mode"), hide and "never" or v)
        end,
        default = function()
            local d = ns.DEFAULTS.bars[def.key]
            return pick(d.visible, d.fade and d.fade.mode)
        end }
end

-- Bars 2-8 paging (Paging.lua): one page choice per stance, form, held modifier or target
-- the player has. Each page is named by the bar that shows it, pages 7-10 by the
-- form that shows them on bar 1. The menu lists the bars by their own number, then
-- the forms' pages, then the spare ones: the game's page numbers jump around.
local function pageChoices()
    local L, Paging = DaylightUI.L, ns.Paging
    local values, order, named = { [0] = L["No change"] }, { 0 }, {}
    local function add(page, name)
        if named[page] then return end
        named[page] = true
        values[page] = name
        order[#order + 1] = page
    end
    for _, def in ipairs(ns.Bars.DEFS) do
        if def.kind == "action" and def.page then add(def.page, L[def.label]) end
    end
    for _, state in ipairs(Paging.STATES) do
        local n = tonumber(string.match(state.cond, "^%[bonusbar:(%d)%]$"))
        if n and Paging.Has(state) then add(6 + n, string.format(L["Action Bar 1 in %s"], L[state.name])) end
    end
    for page = 1, Paging.PAGES do add(page, string.format(L["Spare page %d"], page)) end
    return values, order
end

pagingItems = function(def, k, hidden)
    local Paging = ns.Paging
    local intro = def.paged
        and "Paging: this bar can show another page of buttons while you hold a key, or when your target is friendly or an enemy. Your stances and forms change it too, unless you switch that off below. Pick a spare page to fill it with spells of its own."
        or "Paging: this bar can show another page of buttons while you're in a stance or form, while you hold a key, or when your target is friendly or an enemy. Pick a spare page to fill it with spells of its own."
    local items = { { type = "text", label = intro, hidden = hidden } }
    if def.paged then
        items[#items + 1] = { type = "toggle", key = k("autoPage"), label = "Change with forms and stances",
            desc = "Your stances, forms, stealth and the page keys swap this bar's buttons, as in the game. Off, it always shows its own buttons. Vehicles still take it over.",
            disabled = hidden }
        items[#items + 1] = { type = "text", label = "Powershifting: the game takes a moment to confirm a new form, and shows your caster bar until it does. Put /click DaylightUICat (or DaylightUIBear, DaylightUIMoonkin) at the top of your shift macro and this bar swaps the moment you press it.",
            hidden = function(get)
                if type(hidden) == "function" and hidden(get) then return true end
                return hidden == true or Paging.Class() ~= "DRUID"
            end }
    end
    for _, state in ipairs(Paging.STATES) do
        if state.held or not def.paged then   -- bar 1's forms already page it
            items[#items + 1] = { type = "dropdown", key = k("paging." .. state.id), label = state.name .. " page",
                desc = "Which page of buttons this bar shows " .. state.when .. ". Your keybinds cast what the bar shows. No change keeps the bar's own buttons."
                    .. ((state.id == "help" or state.id == "harm") and " A held key's page comes first, then this one, then your stance or form." or ""),
                choices = pageChoices,
                hidden = function(get) return not Paging.Has(state) end,
                disabled = hidden }
        end
    end
    return items
end

local CORNERS = { topleft = "Top left", topright = "Top right", bottomleft = "Bottom left", bottomright = "Bottom right" }
local CORNER_ORDER = { "topleft", "topright", "bottomleft", "bottomright" }

-- One group per bar, from Bars.DEFS and each kind's Caps: its shape and how it fades.
local function barGroup(def)
    local caps = ns.Bars.KINDS[def.kind].Caps
    local R = ns.Shape.RANGES
    local k = function(s) return "bars." .. def.key .. "." .. s end
    -- A hidden bar's shape and fade options wait until it shows again.
    local hidden = function(get) return get(k("visible")) == "hidden" end
    local items = {}
    if caps.icons then
        items[#items + 1] = { type = "slider", key = k("icons"), label = "Buttons", min = caps.icons[1], max = caps.icons[2], step = 1,
                              desc = "How many buttons this bar shows.",
                              disabled = hidden }
    end
    if caps.rows then
        items[#items + 1] = { type = "slider", key = k("rows"), label = "Rows", min = R.rows[1], max = R.rows[2], step = 1,
                              desc = "How many rows the buttons wrap into (columns when the bar is vertical).", disabled = hidden }
    end
    items[#items + 1] = { type = "slider", key = k("size"), label = "Button size", min = R.size[1], max = R.size[2],
                          step = R.size[3], desc = "Size as a percent of the button's normal size.", disabled = hidden }
    if caps.height then
        items[#items + 1] = { type = "slider", key = k("height"), label = "Button height", min = R.height[1], max = R.height[2],
                              step = R.height[3], disabled = hidden,
                              desc = "Each button's height as a percent of its width. 100 is square; lower makes wide, flat buttons. The icon is cropped to fit, never stretched." }
    end
    items[#items + 1] = { type = "slider", key = k("pad"), label = "Spacing", min = R.pad[1], max = R.pad[2], step = 1, unit = "px",
                              desc = "The gap between this bar's buttons.",
                          disabled = hidden }
    items[#items + 1] = { type = "toggle", key = k("vertical"), label = "Vertical bar",
                          desc = "Buttons run top to bottom instead of left to right.", disabled = hidden }
    if caps.rows then
        -- No saved pick follows the bar's own way (Bars.Corner), so the row reads it.
        items[#items + 1] = { type = "dropdown", key = k("corner"), label = "Start corner",
                              values = CORNERS, order = CORNER_ORDER, disabled = hidden,
                              desc = "The corner the first button sits in. The buttons fill away from it, row by row (column by column on a vertical bar). Bottom left with 3 buttons a row puts 1, 2, 3 along the bottom, like a side-button mouse.",
                              get = function() return ns.Bars.Corner(def) end,
                              set = function(v) DUI:Set("ActionBars", k("corner"), v) end,
                              default = function() return ns.Bars.Corner(def, ns.DEFAULTS.bars[def.key]) end }
    end
    for _, item in ipairs(DaylightUI.Fade.Items("bars." .. def.key .. ".fade.", nil, hidden, def.label)) do
        -- The fade's Visible row is replaced by the bar's own, which can also hide it (visibleRow).
        if item.key == k("fade.mode") then items[#items + 1] = visibleRow(def, k) else items[#items + 1] = item end
    end
    if def.kind == "action" and def.page then
        for _, item in ipairs(pagingItems(def, k, hidden)) do items[#items + 1] = item end
    end
    return { label = def.label, items = items }
end

-- Every bar in one card. "Settings for" picks which bar the rows apply to, and an
-- action bar can copy another's shape and fade.
local SHAPE_FIELDS = { "icons", "rows", "size", "height", "pad", "vertical", "corner", "visible" }
local function isAction(key)
    for _, def in ipairs(ns.Bars.DEFS) do
        if def.key == key then return def.kind == "action" end
    end
    return false
end
local barChoices = {}
for _, def in ipairs(ns.Bars.DEFS) do
    barChoices[#barChoices + 1] = { id = def.key, label = def.label, items = barGroup(def).items }
end
local layoutGroups = { DaylightUI.Options.PickCard({ label = "Bars",
    desc = "Each bar's size, shape and when it shows. Pick the bar with Settings for.",
    pickDesc = "Which bar the rows below set.",
    choices = barChoices,
    copy = { label = "Copy from", desc = "Another action bar whose shape and fade to copy onto the one picked in Settings for.",
             button = "Copy the bar", buttonDesc = "Replaces the picked bar's size, shape and fade with the one above's. Where it sits stays.",
             can = isAction,
             fn = function(from, to)
                 local function copy(field)
                     local v = DUI:Get("ActionBars", "bars." .. from .. "." .. field)
                     -- An unset corner follows the bar's own way, so it's copied unset too.
                     if v ~= nil or field == "corner" then DUI:Set("ActionBars", "bars." .. to .. "." .. field, v) end
                 end
                 for _, f in ipairs(SHAPE_FIELDS) do copy(f) end
                 for _, f in ipairs(DaylightUI.Fade.FIELDS) do copy("fade." .. f) end
             end } }) }
-- The totem timers aren't a bar, but they sit with the totem bar.
local timersOff = function(get) return get("totemTimers") ~= true end
local timerItems = {
    { type = "toggle", key = "totemTimers", label = "Show totem timers",
      desc = "A countdown icon for each totem you have down." },
}
for _, item in ipairs(DaylightUI.Fade.Items("totemTimersFade.", nil, timersOff)) do timerItems[#timerItems + 1] = item end
layoutGroups[#layoutGroups + 1] = { label = "Totem Timers",
    desc = "The countdown icons for your totems, above the player frame. Move them in unlock mode.", items = timerItems }
local layoutDesc = "Each bar's shape and when it shows. Changes apply at once. Move bars in unlock mode."

-- The Cooldown Manager gets its own section next to Action Bars: one page with its
-- per-character toggles (the layout itself is built on screen).
local Data = ns.CdmData
-- Profiles: named layouts for your class, one picked per talent set. New, Copy,
-- Rename and Delete act on the profile of the talent set in use.
local function inUse() return DaylightUI.DB.SpecGroup() end
local function refreshAll()
    ns.CdmRows.Refresh()
    local Panel = DaylightUI.OptionsPanel
    if Panel and Panel.Refresh then Panel.Refresh() end
end
local function profileChoices()
    local values, order = { none = DaylightUI.L["None"] }, { "none" }
    for _, p in ipairs(Data.Profiles()) do values[p.id] = p.name; order[#order + 1] = p.id end
    return values, order
end
local function setRow(g)
    return { type = "dropdown", key = "cdm.use" .. g, label = string.format("Talent set %d", g),
        desc = "Which profile this talent set uses. Your class's profiles show here, from every character of this class.",
        disabled = function(get) return get("cooldowns") ~= true end,
        choices = profileChoices,
        get = function() return Data.Use(g) or "none" end,
        set = function(id) Data.Assign(g, id ~= "none" and id or nil); refreshAll() end }
end
local function current() return Data.Use(inUse()) end
local function currentName()
    local p = Data.Profile(current())
    return p and tostring(p.name) or ""
end
-- Everything below the master switch does nothing while it's off.
local cdmOff = function(get) return get("cooldowns") ~= true end
local noProfile = function(get) return cdmOff(get) or current() == nil end
local cdmPages = {
    { id = "cdm.layout", label = "Layout",
      desc = "Your own cooldown layout: every spell the Cooldown Manager tracks as an icon or a bar, placed where you like and snapped together. Layouts are profiles: as many per class as you like, one for each talent set.",
      groups = {
          { label = "Layout", items = {
              { type = "toggle", key = "cooldowns", label = "Use DaylightUI's Cooldown Manager", reload = true,
                desc = "DaylightUI style layout and look for the game's Cooldown Manager. When off, it's left exactly as the game draws it and /cdm opens the game's own settings." },
              { type = "button", label = "Edit layout", text = "Edit on screen",
                desc = "Opens the layout editor right on your screen, on the profile your talent set uses: pull spells up from the tray, drag them where you want them, hook them together, click one to change it. Type /cdm to open it any time. Out of combat only.",
                disabled = cdmOff,
                func = function() ns.CdmEditor.Open(inUse()) end },
          } },
          { label = "Profiles", items = {
              setRow(1),
              setRow(2),
              { type = "text", label = function()
                    local L = DaylightUI.L
                    local name = currentName()
                    if name == "" then
                        return string.format(L["You're on talent set %d, which has no profile. New and Import make one for it."], inUse())
                    end
                    return string.format(L["You're on talent set %d. The buttons below work on its profile, %s."], inUse(), name)
                end },
              { type = "button", key = "cdm.new", label = "New profile", text = "New",
                desc = "An empty profile, used by the talent set you're in.",
                disabled = cdmOff,
                func = function()
                    DaylightUI.Widgets.Prompt(DaylightUI.L["Name for the new profile:"], "", function(name)
                        Data.Assign(inUse(), Data.NewProfile(name))
                        refreshAll()
                    end)
                end },
              { type = "button", key = "cdm.copy", label = "Copy profile", text = function() local n = currentName(); return n ~= "" and string.format(DaylightUI.L["Copy %s"], n) or DaylightUI.L["Copy"] end,
                desc = "A copy of the profile you're using, used by the talent set you're in from now on.",
                disabled = noProfile,
                func = function()
                    local id = current()
                    DaylightUI.Widgets.Prompt(DaylightUI.L["Name for the copy:"], currentName(), function(name)
                        local new = Data.CopyProfile(id, name)
                        if new then Data.Assign(inUse(), new) end
                        refreshAll()
                    end)
                end },
              { type = "button", key = "cdm.rename", label = "Rename profile", text = function() local n = currentName(); return n ~= "" and string.format(DaylightUI.L["Rename %s"], n) or DaylightUI.L["Rename"] end,
                desc = "A new name for the profile you're using.",
                disabled = noProfile,
                func = function()
                    local id = current()
                    DaylightUI.Widgets.Prompt(string.format(DaylightUI.L["Rename %s:"], currentName()), currentName(), function(name)
                        Data.RenameProfile(id, name)
                        refreshAll()
                    end)
                end },
              { type = "button", key = "cdm.delete", label = "Delete profile", text = function() local n = currentName(); return n ~= "" and string.format(DaylightUI.L["Delete %s"], n) or DaylightUI.L["Delete"] end, confirm = true,
                desc = "Deletes the profile you're using, for every character of this class. Talent sets that used it have none.",
                disabled = noProfile,
                func = function()
                    Data.DeleteProfile(current())
                    refreshAll()
                end },
              { type = "button", key = "cdm.import", label = "Import a layout", text = "Paste a string",
                desc = "A layout string from the game's own Cooldown Manager (its Export), a guide or another UI. It becomes a new profile, used by the talent set you're in.",
                disabled = cdmOff,
                func = function() ns.CdmImport.Open(inUse(), refreshAll) end },
          } },
          { label = "Look", items = {
              { type = "button", label = "Icon look", text = "Change the look",
                desc = "Border, icon zoom, cooldown shade and text colors for the Cooldown Manager's icons, on the Action Bars page.",
                disabled = cdmOff,
                func = function() ns.ShowLook("cdm") end },
              DaylightUI.Options.BarRow("media.cdm", "Cooldown bar", "the Cooldown Manager's bars", cdmOff),
              DaylightUI.Options.BackRow("media.cdm", "Cooldown bar", "the Cooldown Manager's bars", cdmOff),
              { type = "toggle", key = "cdm.on", label = "Use my layout on this character",
                desc = "Your own layout on this character. When off, this character's spells show where the game puts them, still in DaylightUI's look. Saved for this character.",
                disabled = cdmOff,
                get = function() return Data.Switch("on") end,
                set = function(v) Data.SetSwitch("on", v); ns.CdmRows.Refresh() end },
              { type = "toggle", key = "cdm.hideUnplaced", invert = true, label = "Show spells not in the layout",
                desc = "Spells the game tracks that aren't in your layout still show. When off, they're faded out. Saved for this character.",
                disabled = function(get) return cdmOff(get) or not Data.Switch("on") end,
                get = function() return Data.Switch("hideUnplaced") end,
                set = function(v) Data.SetSwitch("hideUnplaced", v); ns.CdmRows.Refresh() end },
              { type = "toggle", key = "cdmKeybinds", since = "1.5.2", label = "Show keybinds on icons",
                desc = "The key that casts each spell, on its icon. It reads your action bars, so a spell on no bar shows none. Any icon can change this in the layout editor.",
                disabled = cdmOff },
          } },
          DaylightUI.Fade.Card("cdmFade.", nil, cdmOff, "Cooldown Manager"),
      } },
}

do
    local Options = DaylightUI.Options
    local abOrder = 110
    Options.RegisterSection("CooldownManager", "Cooldown Manager", abOrder + 1)
    for i, p in ipairs(cdmPages) do
        Options.RegisterPage({
            id = p.id, section = "CooldownManager", label = p.label, desc = p.desc, order = i * 10,
            scope = "ActionBars", defaults = ns.DEFAULTS, groups = p.groups,
        })
    end
end

ns.OPTIONS = { pages = {
    { id = "bars", label = "Action Bars", desc = "Button look, bag bar and micro menu. Each bar's size and shape is on the Bar Layout page.",
      groups = look },
    { id = "barlayout", label = "Bar Layout",
      desc = layoutDesc,
      groups = layoutGroups },
} }
