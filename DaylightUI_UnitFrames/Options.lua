-- The unit frames' options pages as data. The core window draws them in its
-- "Unit Frames" section.

-- First and last names: a switch per element, stored in general.lastNames.
-- Nameplates and tooltips have the same switch on their own pages.
local function lastNames(element)
    local path = "lastNames." .. element
    return { type = "toggle", key = path, label = "First and last names",
        desc = "Players' last names after their first, on this frame only. "
            .. "Where the game hides names (in combat, in places) only the first name shows.",
        get = function() return DaylightUI:Get("general", path) == true end,
        set = function(v) DaylightUI:Set("general", path, v) end }
end

local _, ns = ...
local UF = ns.UF

-- disabled() helpers. get reads another setting on the same page.
local function off(key) return function(get) return get(key) ~= true end end
local function offAny(...)
    local keys = { ... }
    return function(get)
        for _, k in ipairs(keys) do
            if get(k) ~= true then return true end
        end
        return false
    end
end

-- The cast bars' and swing timer's Fill style. Its flat colors show with
-- "plain" and its pairs (the same ones as the Gradients page) with "pair".
local FILL_STYLES = { plain = "One color", daylight = "Daylight gradient", pair = "Two-color gradient" }
local FILL_ORDER = { "plain", "daylight", "pair" }
local function fillIs(key, v) return function(get) return get(key) == v end end
local function fillIsNot(key, v) return function(get) return get(key) ~= v end end
local function gradientRow(pair, label, hidden)
    local item = DaylightUI.Gradients.Item(pair, label)
    item.hidden = hidden
    return item
end

-- The dispel highlight's tint strength only matters for a tint.
local DISPEL_HIGHLIGHTS = { none = "None", border = "Border", tint = "Tint", both = "Both" }
local LEADER_SHOW = { lead = "Only while you lead", tank = "A party's tank too", party = "Everyone in a party" }
local function noTint(key, ...)
    local pageOff = offAny(...)
    return function(get)
        local mode = get(key)
        return pageOff(get) or (mode ~= "tint" and mode ~= "both")
    end
end

local SIZE = { min = 60, max = 400 }

local NAME_COLORS = { global = "Same as the Colors page", white = "White", class = "Class",
    classGradient = "Class gradient", custom = "Custom" }
local NAME_COLOR_ORDER = { "global", "white", "class", "classGradient", "custom" }
local TEXT_COLORS = { white = "White", class = "Class", custom = "Custom" }
local TEXT_COLOR_ORDER = { "white", "class", "custom" }
local function notCustom(key) return function(get) return get(key) ~= "custom" end end

-- The shield texture picks (Colors page): stripes, plain, then every shared
-- bar texture. The overshield's list starts with "Same as shields".
local function shieldTextures(withShield)
    local values, order = { stripes = "Stripes", plain = "Plain" }, { "stripes", "plain" }
    if withShield then
        values.shield = "Same as shields"
        table.insert(order, 1, "shield")
    end
    local Media = DaylightUI.Media
    local shared, sharedOrder = Media.List("statusbar", { [Media.OWN_BAR] = true })
    for _, key in ipairs(sharedOrder) do
        values[key] = shared[key]
        order[#order + 1] = key
    end
    return values, order
end

local SORT_VALUES = { group = "Group", role = "Role (tank, healer, damage)", class = "Class", name = "Name" }
local SORT_ORDER = { "group", "role", "class", "name" }
local RAID_SORT_VALUES = { group = "Group", grouprole = "Group, then role", role = "Role (tank, healer, damage)",
                           class = "Class", name = "Name" }
local RAID_SORT_ORDER = { "group", "grouprole", "role", "class", "name" }
local SORT_DESC = "Group keeps each raid group together. Group, then role does too, with tanks, then healers, then damage at the top of each. The others list everyone in one order and wrap by tiles per line."

-- An icon's spot: the nine on the frame, then the eight around it (Spots).
local SPOT_VALUES = { topleft = "Top left", top = "Top", topright = "Top right", left = "Left", center = "Center",
    right = "Right", bottomleft = "Bottom left", bottom = "Bottom", bottomright = "Bottom right" }
for _, s in ipairs(ns.Spots.ORDER) do SPOT_VALUES[s] = SPOT_VALUES[s] or ns.Spots.LABELS[s] end
-- A party button's role, marker and crown: at home (UF.ICON_HOME), or any spot.
local HOME_SPOTS, HOME_ORDER = { [UF.ICON_HOME] = "With the name or portrait" }, { UF.ICON_HOME }
for _, s in ipairs(ns.Spots.ORDER) do
    HOME_SPOTS[s], HOME_ORDER[#HOME_ORDER + 1] = SPOT_VALUES[s], s
end
-- The level badge: its own spot at the portrait's foot, or any spot.
local LEVEL_SPOTS, LEVEL_ORDER = { ring = "On the portrait" }, { "ring" }
for _, s in ipairs(ns.Spots.ORDER) do
    LEVEL_SPOTS[s], LEVEL_ORDER[#LEVEL_ORDER + 1] = ns.Spots.LABELS[s], s
end

-- Per-class icons: one line per class with every icon it can use in a row, and
-- a ring marking its pick. The first icon means "same as the Icon style".
local PICK_LINE, PICK_SIZE, PICK_GAP, PICK_NAME = 34, 26, 5, 110
local function UI() return DaylightUI.Widgets end

local function className(token)
    local names = LOCALIZED_CLASS_NAMES_MALE
    local n = type(names) == "table" and names[token]
    if type(n) == "string" then return n end
    return token:sub(1, 1) .. token:sub(2):lower()
end

local function picksTable()
    local t = DaylightUI:Get("UnitFrames", "portraits.classIcons")
    return type(t) == "table" and t or {}
end

local function buildPickLine(parent, token)
    local W, C = UI(), UI().COLORS
    local line = CreateFrame("Frame", nil, parent)
    line:SetHeight(PICK_LINE)
    line.name = W.Font(line, W.BODY, 13, C.text)
    line.name:SetPoint("LEFT", line, "LEFT", 0, 0)
    local r, g, b = DaylightUI.Style.RawClassColor(token)
    if r then line.name:SetTextColor(r, g, b, 1) end
    line.name:SetText(className(token))
    line.cells = {}
    local keys = { "" }
    for _, k in ipairs(UF.ClassIconChoices(token)) do keys[#keys + 1] = k end
    for i, key in ipairs(keys) do
        local b = CreateFrame("Button", nil, line)
        b:SetSize(PICK_SIZE, PICK_SIZE)
        b:SetPoint("LEFT", line, "LEFT", PICK_NAME + (i - 1) * (PICK_SIZE + PICK_GAP), 0)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints(b)
        b.ring = W.Round(b, "OVERLAY", 0, true)
        b.ring:SetPoint("TOPLEFT", b, "TOPLEFT", -3, 3)
        b.ring:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 3, -3)
        W.TintDaylight(b.ring)
        b.key = key
        b:SetScript("OnClick", function()
            DaylightUI:Set("UnitFrames", "portraits.classIcons." .. token, key ~= "" and key or nil)
        end)
        b:SetScript("OnEnter", function(self)
            local style = DaylightUI:Get("UnitFrames", "portraits.icons")
            if key == "" then
                W.Tooltip(self, DaylightUI.L["Same as Icon style"], string.format(DaylightUI.L["Follows the Icon style above (%s)."],
                    UF.ICON_STYLES[style] or "DaylightUI"))
            else
                W.Tooltip(self, UF.ClassIconName(key), className(token))
            end
        end)
        b:SetScript("OnLeave", W.HideTooltip)
        line.cells[i] = b
    end
    function line.Update()
        local pick = picksTable()[token]
        if type(pick) ~= "string" then pick = "" end
        local style = DaylightUI:Get("UnitFrames", "portraits.icons")
        for _, b in ipairs(line.cells) do
            local file, l, r, t, btm = UF.ClassIcon(token, b.key == "" and style or b.key)
            if file then
                b.icon:SetTexture(file)
                b.icon:SetTexCoord(l, r, t, btm)
            end
            b.ring:SetShown(b.key == pick)
        end
    end
    return line
end

local classIconPicker = {
    type = "custom", label = "Icon per class",
    hidden = function() return not UF.HasIconPack() end,
    build = function(row)
        local W = UI()
        row.lines = {}
        for i, token in ipairs(UF.ICON_CLASSES) do
            local line = buildPickLine(row, token)
            line:SetPoint("TOPLEFT", row, "TOPLEFT", W.PAD, -4 - (i - 1) * PICK_LINE)
            line:SetPoint("TOPRIGHT", row, "TOPRIGHT", -W.PAD, -4 - (i - 1) * PICK_LINE)
            W.Stripe(line, i % 2 == 0)
            row.lines[i] = line
        end
    end,
    update = function(row)
        for _, line in ipairs(row.lines) do line.Update() end
    end,
    height = function() return #UF.ICON_CLASSES * PICK_LINE + 8 end,
}

-- Where each tile icon sits and how big it is, for raid tiles and party frames.
-- k maps a key to its setting, dis is the "page is off" check. skip (optional)
-- leaves out items the page already has (markerSize) or relabels the px crown
-- (leaderPxLabel, leaderPxDesc). home (party): the role, marker and crown
-- spots offer "With the name or portrait" (UF.ICON_HOME), and their sizes say
-- they fit there until changed.
local function iconItems(k, dis, skip, home)
    skip = skip or {}
    local cornerDis = dis
    local function spot(key, label, homed)
        local item = { type = "dropdown", key = k(key), label = label .. " spot", values = SPOT_VALUES,
                 desc = "Where the " .. string.lower(label) .. " sits on each frame, or just outside it.",
                 order = ns.Spots.ORDER, disabled = cornerDis }
        if homed then
            item.values, item.order = HOME_SPOTS, HOME_ORDER
            item.desc = "Where the " .. string.lower(label) .. " sits: with the name tab or portrait"
                .. " (in a corner when the frame has neither), or any spot on or around the frame."
        end
        return item
    end
    local function size(key, label, desc)
        return { type = "slider", key = k(key), label = label .. " size", min = 6, max = 32, step = 1, unit = "px",
                 desc = desc or ("How big the " .. string.lower(label) .. " is."
                     .. (home and " With the name or portrait it fits there until you change this." or "")),
                 disabled = cornerDis }
    end
    -- The two nudges after a piece's spot and size (written by Design mode's
    -- drag and arrow keys).
    local function nudges(items, key, label, disabled)
        items[#items + 1] = { type = "slider", key = k(key .. "X"), label = label .. " left / right", min = -50, max = 50, step = 1,
            unit = "px", desc = "Nudges it sideways from its spot.", disabled = disabled }
        items[#items + 1] = { type = "slider", key = k(key .. "Y"), label = label .. " up / down", min = -50, max = 50, step = 1,
            unit = "px", desc = "Nudges it up or down from its spot.", disabled = disabled }
    end
    local items = { spot("rolePos", "Role icon", home), size("roleSize", "Role icon") }
    nudges(items, "role", "Role icon", cornerDis)
    local more = {
        { type = "toggle", key = k("roleHideDamage"), invert = true, label = "Show the damage role icon",
          desc = "Damage dealers get a role icon too. When off, only tanks and healers get one.", disabled = dis },
        { type = "toggle", key = k("roleHideInCombat"), invert = true, label = "Show role icon in combat",
          desc = "The role icon stays in a fight. When off, it hides while you're fighting.", disabled = dis },
        spot("markerPos", "Raid marker", home),
    }
    for _, item in ipairs(more) do items[#items + 1] = item end
    if not skip.markerSize then items[#items + 1] = size("markerSize", "Raid marker") end
    nudges(items, "marker", "Raid marker", cornerDis)
    items[#items + 1] = spot("leaderPos", "Leader crown", home)
    items[#items + 1] = size("leaderPx", skip.leaderPxLabel or "Leader crown", skip.leaderPxDesc)
    nudges(items, "leader", "Leader crown", cornerDis)
    items[#items + 1] = { type = "toggle", key = k("leaderHideInCombat"), invert = true, label = "Show leader crown in combat",
                          desc = "The leader's crown stays in a fight. When off, it hides while you're fighting.", disabled = dis }
    local dispelPos = spot("dispelPos", "Dispel icon")
    dispelPos.disabled = dis
    items[#items + 1] = dispelPos
    nudges(items, "dispel", "Dispel icon", dis)
    local readyOff = function(get) return dis(get) or get(k("showReady")) == false end
    items[#items + 1] = { type = "toggle", key = k("showReady"), label = "Ready check answers",
        desc = "During a ready check, a tick, a cross or a question mark on each member: ready, not ready, or no answer yet. They stay a few seconds after the check ends.",
        disabled = dis }
    items[#items + 1] = { type = "dropdown", key = k("readyPos"), label = "Ready check spot", values = SPOT_VALUES,
        desc = "Where the ready check answer sits on each frame, or just outside it.",
        order = ns.Spots.ORDER, disabled = readyOff }
    items[#items + 1] = { type = "slider", key = k("readySize"), label = "Ready check size", min = 6, max = 32, step = 1,
        desc = "How big the ready check answer is.", unit = "px", disabled = readyOff }
    nudges(items, "ready", "Ready check", readyOff)
    return items
end

-- Whether a group frame has neither portrait nor name tab showing (so level
-- and PvP have no home, and the corner icons are in use). Uses the builder's
-- own portrait rule, so a frame too short for a portrait counts as none.
local function noHome(k)
    return function(get)
        local cfg = { portrait = get(k("portrait")), height = get(k("height")), style = get(k("style")),
                      tabHeight = get(k("tabHeight")), showPower = get(k("showPower")), ribbonGap = get(k("ribbonGap")),
                      powerHeight = get(k("powerHeight")) }
        local mode = UF.PortraitMode({ portrait = true, spec = { ribbon = true } }, cfg)
        -- Ribbon's row also counts as a home while the health number is on it.
        local tab = (get(k("showName")) ~= false and get(k("nameOnBar")) ~= true)
            or (UF.StyleOf(cfg) == "ribbon" and get(k("showPercent")) == true)
        return mode == "none" and not tab
    end
end

-- The dispel items for a group page. gate is the page's on/off key, sizeMax the
-- icon size ceiling, what is the thing a highlight lights up ("frame"/"tile").
local function dispelItems(k, gate, sizeMax, what)
    local shown = off(gate)
    return {
        { type = "toggle", key = k("showDispel"), label = "Dispellable debuff",
          desc = "A small icon in a corner for a debuff you can remove, edged in its type's color.", disabled = shown },
        { type = "slider", key = k("dispelSize"), label = "Dispel icon size", min = 6, max = sizeMax, step = 1,
          desc = "How big the dispellable debuff's icon is.", disabled = offAny(gate, k("showDispel")) },
        { type = "dropdown", key = k("dispelHighlight"), label = "Dispel highlight",
          values = DISPEL_HIGHLIGHTS, order = { "none", "border", "tint", "both" },
          desc = "Lights up the whole " .. what .. " in the debuff's type color: its border, a tint over the health bar, or both.",
          disabled = shown },
        { type = "toggle", key = k("dispelGlow"), label = "Dispel glow",
          desc = "A soft light round the " .. what .. " in the debuff's type color.", disabled = shown },
        { type = "slider", key = k("dispelAlpha"), label = "Dispel tint strength", min = 0.1, max = 0.8, step = 0.05,
          desc = "How strongly the debuff's color tints the health bar. Only for a Tint or Both highlight.", disabled = noTint(k("dispelHighlight"), gate) },
        { type = "toggle", key = k("dispelOnlyMine"), label = "Only debuffs I can dispel",
          desc = "When off, any debuff with a type (Magic, Curse, Disease, Poison) shows, even one you can't remove.",
          disabled = shown },
    }
end

-- Your target's outline on a group page. gate is the page's on/off key.
local function targetItems(k, gate)
    return {
        { type = "toggle", key = k("targetMark"), label = "Target outline",
          desc = "Outlines the member you have targeted, so you can find them at a glance.", disabled = off(gate) },
        { type = "dropdown", key = k("targetMarkColor"), label = "Target outline color",
          values = { accent = "Accent", custom = "Custom color" }, order = { "accent", "custom" },
          desc = "Accent follows your accent color (General > Appearance), or pick your own.",
          disabled = offAny(gate, k("targetMark")) },
        { type = "color", key = k("targetMarkCustom"), label = "Custom target outline color",
          desc = "The outline's color when Target outline color is Custom color.",
          disabled = offAny(gate, k("targetMark")), hidden = notCustom(k("targetMarkColor")) },
    }
end

-- The name's alignment and offsets, for frames with the name on the bar. dis
-- is the "these don't apply" check (page off, name hidden, or not on the bar).
-- Where a tile's name sits (namePos): across the bar, or a Spots spot.
local NAME_POS_VALUES, NAME_POS_ORDER = { bar = "Across the bar" }, { "bar" }
for _, s in ipairs(ns.Spots.ORDER) do
    NAME_POS_VALUES[s] = ns.Spots.LABELS[s]
    NAME_POS_ORDER[#NAME_POS_ORDER + 1] = s
end

-- big: a frame with a portrait end (player, target, focus), where "bar" keeps
-- the name beside the portrait and there's no alignment row.
local BIG_NAME_POS_VALUES = {}
for key, v in pairs(NAME_POS_VALUES) do BIG_NAME_POS_VALUES[key] = v end
BIG_NAME_POS_VALUES.bar = "Beside the portrait"

-- small: a small frame (pet, target of target). Across its bar it stays
-- centered, so no alignment row either.
local function nameItems(k, dis, desc, big, small)
    local items = {
        { type = "dropdown", key = k("namePos"), label = "Name position",
          values = big and BIG_NAME_POS_VALUES or NAME_POS_VALUES, order = NAME_POS_ORDER,
          desc = big and "Beside the portrait keeps it at the frame's outer end. Any other spot puts it there, on or round the frame. You can also drag it in Design mode."
              or small and "Across the bar keeps it inside. Any other spot puts it there, on or round the frame, so a long name has room. You can also drag it in Design mode."
              or "Across the bar keeps the alignment below. Beside the tile needs space between tiles.", disabled = dis },
    }
    if not big and not small then
        items[#items + 1] = { type = "dropdown", key = k("nameAlign"), label = "Name alignment",
          values = { left = "Left", center = "Center", right = "Right" }, order = { "left", "center", "right" },
          desc = desc or "Where the name sits across the bar: left, center or right.", disabled = dis,
          hidden = function(get) local p = get(k("namePos")); return p ~= nil and p ~= "bar" end }
    end
    items[#items + 1] = { type = "slider", key = k("nameX"), label = "Name left / right", min = -50, max = 50, step = 1,
        desc = "Nudges the name sideways from its position.", unit = "px", disabled = dis }
    items[#items + 1] = { type = "slider", key = k("nameY"), label = "Name up / down", min = -50, max = 50, step = 1,
        desc = "Nudges the name up or down from its position.", unit = "px", disabled = dis }
    return items
end

-- Item lists joined into one.
local function cat(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, it in ipairs(list) do out[#out + 1] = it end
    end
    return out
end

-- An aura group's layout rows, added to items: position, size, count, timers
-- and nudges. g maps a field to its key. dis grays it out, noTimers grays out
-- the "Only under a minute" row, gone hides it.
local function groupRows(items, g, dis, noTimers, gone)
    local Spots = ns.Spots
    local function also(fn)
        if not gone then return fn end
        return function(get) return gone(get) or (fn ~= nil and fn(get)) or false end
    end
    local rows = {
        { type = "dropdown", key = g("spot"), label = "Position", values = Spots.LABELS,
          order = Spots.ORDER, desc = "Outside spots may need more space between frames.", disabled = dis },
        { type = "dropdown", key = g("grow"), label = "Grow direction", values = Spots.GROW_LABELS,
          order = Spots.GROW_ORDER, disabled = dis,
          desc = "Which way the row of icons fills from its first icon.",
          hidden = also(function(get) local s = get(g("spot")); return s == "outleft" or s == "outright" end) },
        { type = "slider", key = g("size"), label = "Icon size", min = 10, max = 32, step = 1, unit = "px",
          desc = "How big each icon is.", disabled = dis },
        { type = "slider", key = g("max"), label = "Max shown", min = 1, max = 12, step = 1,
          desc = "The most icons this group shows at once.", disabled = dis },
        { type = "slider", key = g("rows"), label = "Rows", min = 1, max = 4, step = 1,
          desc = "Max shown is split over the rows.", disabled = dis },
        { type = "slider", key = g("spacing"), label = "Spacing", min = 0, max = 12, step = 1, unit = "px",
          desc = "The gap between icons.", disabled = dis },
        { type = "toggle", key = g("timers"), label = "Time left on icons", desc = "The time left as a number on each icon.",
          disabled = dis },
        { type = "toggle", key = g("shortTimers"), label = "Only under a minute",
          desc = "Hides the number while a minute or more is left, so long buffs stay quiet.", disabled = noTimers },
        { type = "toggle", key = g("swipe"), label = "Cooldown swipe",
          desc = "Each icon darkens like a clock as its time runs out.", disabled = dis },
        { type = "toggle", key = g("tooltips"), label = "Tooltip on hover",
          desc = "Hovering an icon says what it is. While the mouse is on an icon, mouseover casting misses that player. Clicks always go through to the frame.",
          disabled = dis },
        { type = "slider", key = g("x"), label = "Icons left / right", min = -50, max = 50, step = 1, unit = "px",
          desc = "Nudges the icons sideways from their position.", disabled = dis },
        { type = "slider", key = g("y"), label = "Icons up / down", min = -50, max = 50, step = 1, unit = "px",
          desc = "Nudges the icons up or down from their position.", disabled = dis },
    }
    for _, it in ipairs(rows) do
        if gone and not it.hidden then it.hidden = gone end
        items[#items + 1] = it
    end
end

-- The filter choices the client allows for def, as dropdown values.
local function filterValues(def)
    local AG = ns.AuraGroups
    local values, order = {}, {}
    for _, c in ipairs(def.choices) do
        if not AG.Refused(def, c) then
            values[c] = AG.CHOICE_LABELS[def.key][c]
            order[#order + 1] = c
        end
    end
    return values, order
end

-- Add piece (Design mode): a card per extra aura group slot (party, raid),
-- shown only while the slot is in use. frame: "raid"; gate: its Show key.
local function extraAuraCards(frame, gate)
    local AG = ns.AuraGroups
    local cards = {}
    for i, slot in ipairs(ns.AURA_SLOTS) do
        local function g(key) return frame .. ".auras." .. slot .. "." .. key end
        local function gone(get) return get(g("show")) ~= true end
        local function isNot(what) return function(get) return gone(get) or get(g("what")) ~= what end end
        local dis = off(gate)
        local dv, dorder = filterValues(AG.BY_KEY.debuffs)
        local bv, border = filterValues(AG.BY_KEY.buffs)
        local items = {
            { type = "dropdown", key = g("what"), label = "Debuffs or buffs",
              values = { debuffs = "Debuffs", buffs = "Buffs" }, order = { "debuffs", "buffs" },
              desc = "Whether this extra group shows debuffs or buffs.", hidden = gone, disabled = dis },
            { type = "dropdown", key = g("debuffWhich"), label = "Filter", values = dv, order = dorder,
              desc = "Which debuffs this group shows.", hidden = isNot("debuffs"), disabled = dis },
            { type = "dropdown", key = g("buffWhich"), label = "Filter", values = bv, order = border,
              desc = "Which buffs this group shows.", hidden = isNot("buffs"), disabled = dis },
        }
        groupRows(items, g, dis, offAny(gate, g("timers")), gone)
        items[#items + 1] = { type = "button", label = "Remove this aura group", text = "Remove", hidden = gone,
            desc = "Takes this extra aura group off the frame. Add another in Design mode.",
            func = function() ns.Texts.Remove(ns.Raid.PageFrame(frame), "auras", slot) end }
        cards[#cards + 1] = { label = "Extra aura group " .. i,
            desc = "Added with Add piece in Design mode: one more row of auras, with its own filter.", items = items }
    end
    return cards
end

-- Add piece (Design mode): a card per extra text slot, shown only while the
-- slot is in use. frame: "target"; gate: its Show key.
local function extraTextCards(frame, gate)
    local Spots, Texts = ns.Spots, ns.Texts
    local cards = {}
    for i, slot in ipairs(ns.TEXT_SLOTS) do
        local function t(key) return frame .. ".texts." .. slot .. "." .. key end
        local function gone(get) return get(t("show")) ~= true end
        -- A format row shows while any of the text's parts is of that kind.
        local function isNot(kind)
            return function(get)
                return gone(get) or (get(t("kind")) ~= kind and get(t("kind2")) ~= kind and get(t("kind3")) ~= kind)
            end
        end
        local function single(get)
            return gone(get) or ((get(t("kind2")) or "none") == "none" and (get(t("kind3")) or "none") == "none")
        end
        local dis = off(gate)
        cards[#cards + 1] = { label = "Extra text " .. i,
            desc = "Added with Add piece in Design mode. Drag it on the preview to move it. Up to three parts in one line, each in its own color.", items = {
            { type = "dropdown", key = t("kind"), label = "Extra text: first part", values = Texts.LABELS, order = Texts.KINDS,
              desc = "What this extra text shows first, like the name, the level or the guild.",
              hidden = gone, disabled = dis },
            { type = "dropdown", key = t("kind2"), label = "Extra text: second part", values = Texts.MORE_LABELS,
              order = Texts.MORE_KINDS, hidden = gone, disabled = dis,
              desc = "Another thing after the first on the same line, like the level after a name." },
            { type = "dropdown", key = t("kind3"), label = "Extra text: third part", values = Texts.MORE_LABELS,
              order = Texts.MORE_KINDS, hidden = gone, disabled = dis,
              desc = "One more thing at the end of the same line, after the second part." },
            { type = "dropdown", key = t("sep"), label = "Text separator", values = Texts.SEP_LABELS,
              order = Texts.SEP_ORDER, hidden = single, disabled = dis,
              desc = "What sits between the text's parts." },
            { type = "dropdown", key = t("healthFormat"), label = "Health text format",
              desc = "How this extra text writes the health.",
              values = UF.HEALTH_FORMATS, order = UF.HEALTH_FORMAT_ORDER, hidden = isNot("health"), disabled = dis },
            { type = "dropdown", key = t("powerFormat"), label = "Power text format",
              desc = "How this extra text writes the power.",
              values = UF.POWER_FORMATS, order = UF.POWER_FORMAT_ORDER, hidden = isNot("power"), disabled = dis },
            { type = "dropdown", key = t("spot"), label = "Position", values = Spots.LABELS, order = Spots.ORDER,
              desc = "Where this extra text sits on the frame, or just outside it.", hidden = gone, disabled = dis },
            { type = "slider", key = t("size"), label = "Text size", min = 6, max = 30, step = 1,
              desc = "How big this extra text is.", hidden = gone, disabled = dis },
            { type = "slider", key = t("x"), label = "Text left / right", min = -50, max = 50, step = 1, unit = "px",
              desc = "Nudges this extra text sideways from its position.", hidden = gone, disabled = dis },
            { type = "slider", key = t("y"), label = "Text up / down", min = -50, max = 50, step = 1, unit = "px",
              desc = "Nudges this extra text up or down from its position.", hidden = gone, disabled = dis },
            { type = "button", label = "Remove this text", text = "Remove", hidden = gone,
              desc = "Takes this extra text off the frame. Add another in Design mode.",
              func = function() Texts.Remove(ns.Raid.PageFrame(frame), "texts", slot) end },
        } }
    end
    return cards
end

-- The cards for a frame's aura groups (AuraGroups.DEFS), one per group in the
-- same order. k maps a key to its setting ("raid." .. key); gate is the
-- frame's own switch.
-- Heal indicators (Indicators.lua): a card for the whole set, then one per
-- square, shown while indicators are on.
local function spellName(id)
    local ok, name = pcall(C_Spell.GetSpellName, id)
    if ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) then return name end
end

local function indicatorCards(k, gate)
    local HS, Ind = ns.HealSpells, ns.Indicators
    local function n(key) return k("indicators." .. key) end
    local dis = offAny(gate, n("show"))
    local function gone(get) return get(n("show")) ~= true end
    local choices = {}
    for i, slot in ipairs(Ind.SLOTS) do
        local function s(key) return n(slot .. "." .. key) end
        local sdis = offAny(gate, n("show"), s("show"))
        choices[#choices + 1] = { id = slot, label = "Heal indicator " .. i, items = {
            { type = "toggle", key = s("show"), label = "Use this heal indicator", disabled = dis, hidden = gone,
              desc = "Shows this square on each member while its spell is on them. Group buffs (Mark of the Wild, Fortitude, the Blessings) show from anyone, and count down their last minute." },
            { type = "dropdown", key = s("spell"), label = "Heal indicator spell", fallback = "auto", disabled = sdis,
              hidden = gone,
              desc = "Your class's pick follows your class on every character. Pick one to watch it instead.",
              choices = function()
                  local pick = HS.SpellFor(i, "auto")
                  local name = pick and spellName(pick)
                  -- One whole sentence with a slot for the spell, since the spell's
                  -- name differs per character and "Your class's pick (Renew)" can't be a key.
                  local values = { auto = name and string.format(DaylightUI.L["Your class's pick (%s)"], name)
                      or "Your class's pick" }
                  local order = { "auto" }
                  for _, f in ipairs(HS.Mine()) do
                      local key = tostring(f.id)
                      values[key], order[#order + 1] = f.name, key
                  end
                  return values, order
              end },
            { type = "dropdown", key = s("paint"), label = "Heal indicator color",
              values = { spell = "The spell's own", custom = "Custom color" }, order = { "spell", "custom" },
              desc = "The spell's own color (Renew green, a shield blue), or one you pick.",
              disabled = sdis, hidden = gone },
            { type = "color", key = s("custom"), label = "Custom heal indicator color", disabled = sdis,
              desc = "The square's color when Heal indicator color is Custom color.",
              hidden = function(get) return gone(get) or get(s("paint")) ~= "custom" end },
            { type = "dropdown", key = s("spot"), label = "Heal indicator position", values = ns.Spots.LABELS,
              desc = "Where on the frame this square sits.",
              order = ns.Spots.ORDER, disabled = sdis, hidden = gone },
            { type = "slider", key = s("x"), label = "Heal indicator left / right", min = -50, max = 50, step = 1,
              desc = "Nudges this square sideways from its position.",
              unit = "px", disabled = sdis, hidden = gone },
            { type = "slider", key = s("y"), label = "Heal indicator up / down", min = -50, max = 50, step = 1,
              desc = "Nudges this square up or down from its position.",
              unit = "px", disabled = sdis, hidden = gone },
        } }
    end
    return { DaylightUI.Options.PickCard({ label = "Heal indicators",
        desc = "Small colored squares on each member for your heals over time and shields, like Renew or Power Word: Shield. Each square shows while your spell is on them.",
        lead = {
            { type = "toggle", key = n("show"), label = "Show heal indicators", disabled = off(gate),
              desc = "On in the Healer setup. Each class has its own picks; change them below." },
            { type = "slider", key = n("size"), label = "Heal indicator size", min = 4, max = 20, step = 1, unit = "px",
              desc = "How big every square is.", disabled = dis },
            { type = "toggle", key = n("swipe"), label = "Heal indicator swipe",
              desc = "Each square darkens like a clock as your spell runs out.", disabled = dis },
            { type = "dropdown", key = n("look"), label = "Heal indicator look",
              values = { square = "Colored square", icon = "Spell icon" }, order = { "square", "icon" },
              desc = "A square in the spell's color, or the spell's own icon edged in that color.", disabled = dis },
        },
        pickDesc = "Which of the six squares the rows below set.",
        pickHidden = gone, disabled = dis,
        choices = choices }) }
end

local function auraCards(k, gate)
    local AG, Spots = ns.AuraGroups, ns.Spots
    local cards = {}
    for _, def in ipairs(AG.DEFS) do
        local function g(key) return k("auras." .. def.key .. "." .. key) end
        local dis = offAny(gate, g("show"))
        local items = { { type = "toggle", key = g("show"), label = "Show " .. string.lower(def.label),
            desc = "Shows " .. string.lower(def.label) .. " icons on each member.", disabled = off(gate) } }
        if #def.choices > 1 then
            local values, order = filterValues(def)
            items[#items + 1] = { type = "dropdown", key = g("which"), label = "Filter", values = values,
                                  desc = "Which " .. string.lower(def.label) .. " show.", order = order, disabled = dis }
        end
        groupRows(items, g, dis, offAny(gate, g("show"), g("timers")))
        if def.key == "cc" and AG.Refused(def, "cc") then
            for _, it in ipairs(items) do it.hidden = function() return true end end
        end
        cards[#cards + 1] = { label = def.label, desc = def.desc, items = items }
        if def.key == "buffs" then
            for _, card in ipairs(indicatorCards(k, gate)) do cards[#cards + 1] = card end
        end
    end
    -- Private auras (GroupPrivate.lua): the client draws them, this only provides the spot.
    cards[#cards + 1] = { label = "Boss debuffs",
        desc = "Some boss abilities put debuffs on players that addons can't see. The game draws them itself, in the middle of the frame.",
        items = { { type = "toggle", key = k("privateAuras"), label = "Show boss debuffs",
                    desc = "Up to two big icons in the middle, with a sweep for the time left. They only appear when a boss uses them.",
                    disabled = off(gate) } } }
    return cards
end

-- Raid sizes (Raid.lua): the Raid 20 and Raid 40 pages open with this card.
-- Same as Raid 10 (on by default) uses the 10-player frames and grays out the
-- page's rows (raidLocked). Off, the size gets its own, starting as a copy.
-- "Copy from" (ns.CopyFrame): a card at the end of each frame's page. id is
-- the page's settings key, hidden (optional) hides the card.
local COPY_NAMES = { player = "Player", target = "Target", focus = "Focus", targettarget = "Target of Target", focustarget = "Focus Target",
                     pet = "Pet", party = "Party", raid = "Raid 10", raid20 = "Raid 20", raid40 = "Raid 40",
                     arena = "PvP Frames" }
local copyPick = {}
local function copyCard(id, hidden)
    local function others()
        local values, order = {}, {}
        for _, key in ipairs(ns.COPY_FRAMES) do
            if key ~= id then values[key], order[#order + 1] = COPY_NAMES[key], key end
        end
        return values, order
    end
    local function pick()
        local _, order = others()
        return copyPick[id] or order[1]
    end
    return { label = "Copy from", desc = "Start from another frame's setup instead of setting this one up from scratch.", items = {
        { type = "dropdown", label = "Copy from", hidden = hidden,
          desc = "The frame whose setup to copy onto this one.",
          choices = others, get = pick, set = function(v) copyPick[id] = v end,
          default = function() local _, order = others(); return order[1] end },
        { type = "button", label = "Copy its setup", text = "Copy", confirm = true, hidden = hidden,
          desc = "Replaces this frame's size, bars, names, texts, icons and auras with the frame above's. Whether it's shown, its fade, where it sits and how a group is laid out stay.",
          func = function() ns.CopyFrame(pick(), id) end },
    } }
end

-- Frames grow / Lines grow (party and raid): two picks over the settings
-- direction, growUp and growLeft (Group.Corner), covering all eight ways.
-- keyOf(field) is that setting's path, rowKey(field) the row's key as its page
-- names it (a raid page maps it to its size), lines is what a line is called.
local GROW_WAYS = { down = "Down", up = "Up", right = "Right", left = "Left" }
local function growRows(keyOf, lines, gate, rowKey)
    rowKey = rowKey or keyOf
    local function read(f) return DaylightUI:Get("UnitFrames", keyOf(f)) end
    local function write(f, v) DaylightUI:Set("UnitFrames", keyOf(f), v) end
    local function across() return read("direction") == "rows" end
    return {
        { type = "dropdown", key = rowKey("direction"), label = "Frames grow", values = GROW_WAYS,
          order = { "down", "up", "right", "left" }, disabled = gate,
          desc = "Which way the frames run from the first one. Up or Left starts them at the bottom or the right, so a small group sits by that edge.",
          get = function()
              if across() then return read("growLeft") == true and "left" or "right" end
              return read("growUp") == true and "up" or "down"
          end,
          set = function(v)
              local sideways = v == "right" or v == "left"
              write("direction", sideways and "rows" or "columns")
              if sideways then write("growLeft", v == "left") else write("growUp", v == "up") end
          end,
          default = function() return "down" end },
        { type = "dropdown", key = rowKey("growLeft"), label = lines .. " grow", disabled = gate,
          desc = "Where the next line of frames goes once one is full.",
          choices = function()
              if across() then return { down = "Down", up = "Up" }, { "down", "up" } end
              return { right = "Right", left = "Left" }, { "right", "left" }
          end,
          get = function()
              if across() then return read("growUp") == true and "up" or "down" end
              return read("growLeft") == true and "left" or "right"
          end,
          set = function(v)
              if v == "up" or v == "down" then write("growUp", v == "up") else write("growLeft", v == "left") end
          end,
          default = function() return across() and "down" or "right" end },
    }
end

-- These rows still work while it follows (anySize).
local function raidSizeCard(size)
    local R = ns.Raid
    return { label = "Raid size", desc = string.format("Raid frames for %s players, swapped in as the raid grows.", size == 20 and "11 to 20" or "21 to 40"), items = {
        { type = "toggle", label = "Same as Raid 10", anySize = true, disabled = off("raid.enabled"),
          desc = "Uses the Raid 10 frames, and the rows below are grayed out. Turn it off to give this raid size its own, starting from a copy of Raid 10.",
          get = function() return R.Locked(size) end,
          set = function(v) R.SetFollow(size, v == true) end,
          default = function() return true end },
        { type = "toggle", key = "raid" .. size .. ".ownSpot", label = "Own spot", anySize = true, disabled = off("raid.enabled"),
          desc = string.format("Raid %d frames sit in a spot of their own, with their own handle when you unlock (/dui unlock), so a bigger raid can go where it fits. Off, they sit where Raid 10's do.", size) },
        { type = "button", label = "Copy Raid 10", text = "Copy", confirm = true, anySize = true,
          desc = "Replaces this raid size's frames with a copy of Raid 10.",
          hidden = function() return R.Locked(size) end,
          func = function() R.CopyTen(size) end },
    } }
end

-- A raid page's rows while its size follows 10: grayed out, except its Raid
-- size card.
local function raidLocked(size)
    return function(key, item)
        if not ns.Raid.Locked(size) or (item and item.anySize) then return false end
        if type(key) == "string" then
            local field = string.match(key, "^raid%.([^%.]+)")
            if field then return not ns.RAID_SHARED[field] end
            return string.find(key, "^raidText%.") ~= nil
        end
        return item ~= nil and item.type == "button"
    end
end

-- A row every raid size shares, only shown on the Raid 10 page.
local function raidShared(item)
    if item.anySize then return true end
    if item.key == "lastNames.raid" then return true end   -- a General setting, one for every size
    local field = type(item.key) == "string" and string.match(item.key, "^raid%.([^%.]+)")
    return field ~= nil and ns.RAID_SHARED[field] == true
end

-- Fits a raid page's cards to its size. Each card and row is copied, since the
-- builders may share tables between the three pages. Using a row first tells
-- Raid.lua which size it edits (for a row used from search results with no
-- page open). Raid 20 and 40 leave out the shared rows.
local function forRaidSize(groups, size)
    local function editing(fn)
        if type(fn) ~= "function" then return fn end
        return function(...)
            ns.Raid.SetEditing(size)
            return fn(...)
        end
    end
    local function always() return true end
    local out = {}
    for _, g in ipairs(groups) do
        if g then   -- false means a card this size leaves out
            local card = {}
            for k, v in pairs(g) do card[k] = v end
            card.items = {}
            for i, it in ipairs(g.items or {}) do
                local c = {}
                for k, v in pairs(it) do c[k] = v end
                c.set, c.func, c.onPick = editing(c.set), editing(c.func), editing(c.onPick)
                if size ~= 10 and raidShared(c) then c.hidden = always end
                card.items[i] = c
            end
            out[#out + 1] = card
        end
    end
    return out
end

-- One button per quick look (Looks.lua) for frame ("raid").
local function looksCard(frame)
    local items = {}
    for _, look in ipairs(ns.Looks.ORDER) do
        local label = ns.Looks.LABELS[look]
        items[#items + 1] = { type = "button", label = label, text = "Use",
            desc = "Change your raid frames' auras and name to the " .. label .. " look. Click twice to confirm.",
            confirm = true, func = function() ns.Looks.Apply(look, ns.Raid.PageFrame(frame)) end }
    end
    return { label = "Quick looks", desc = "One click sets where the auras and the name sit. Change anything after.",
             items = items }
end

-- Where one of a frame's rows sits (Spots.lua): spot, grow, nudges. prefix is
-- its settings ("targetAuras"), kind is "debuff" or "buff", gate its Show key.
local function spotItems(prefix, kind, gate)
    local k = function(s) return prefix .. "." .. kind .. s end
    local dis = off(gate)
    return {
        { type = "dropdown", key = k("Spot"), label = "Position", values = ns.Spots.LABELS, order = ns.Spots.ORDER,
          desc = "Over or under the frame, the buffs sit nearest it when both share a spot. Outside spots may need room around the frame.",
          disabled = dis },
        { type = "dropdown", key = k("Grow"), label = "Grow direction", values = ns.Spots.GROW_LABELS,
          order = ns.Spots.GROW_ORDER, disabled = dis,
          desc = "Which way the row of icons fills from its first icon.",
          hidden = function(get) local s = get(k("Spot")); return s == "outleft" or s == "outright" end },
        { type = "slider", key = k("X"), label = (kind == "buff" and "Buffs" or "Debuffs") .. " left / right", min = -50, max = 50, step = 1, unit = "px",
          desc = "Nudges the " .. kind .. " icons sideways from their position.", disabled = dis },
        { type = "slider", key = k("Y"), label = (kind == "buff" and "Buffs" or "Debuffs") .. " up / down", min = -150, max = 150, step = 1, unit = "px",
          desc = "Nudges the " .. kind .. " icons up or down from their position.", disabled = dis },
    }
end

-- A frame's buffs and debuffs: two cards at the bottom of its page. prefix is
-- its settings. own: the player's own rows, where every debuff is one row
-- (no "mine, then others" on yourself).
local function unitAuraCards(prefix, own, desc)
    local k = function(s) return prefix .. "." .. s end
    local dOff, bOff = off(k("debuffs")), off(k("buffs"))
    local debuffs = {
        { type = "toggle", key = k("debuffs"), label = "Show debuffs", desc = "Debuff icons by this frame." },
        { type = "slider", key = k("debuffSize"), label = "Debuff size", min = 16, max = 48, step = 1, unit = "px",
          desc = "How big each debuff icon is.", disabled = dOff },
    }
    if own then
        debuffs[#debuffs + 1] = { type = "slider", key = k("maxDebuffs"), label = "Max shown", min = 1, max = 16, step = 1,
                                  desc = "The most debuff icons at once.", disabled = dOff }
    else
        debuffs[#debuffs + 1] = { type = "dropdown", key = k("debuffFilter"), label = "Debuff filter",
            values = { mine = "Only mine", all = "Mine first, then others" }, order = { "mine", "all" },
            desc = "Only the debuffs you put on it, or yours first and then everyone else's.", disabled = dOff }
        debuffs[#debuffs + 1] = { type = "slider", key = k("maxDebuffs"), label = "Max of my debuffs", min = 1, max = 16, step = 1,
                                  desc = "The most of your own debuffs shown at once.", disabled = dOff }
        debuffs[#debuffs + 1] = { type = "slider", key = k("maxOtherDebuffs"), label = "Max debuffs from others", min = 0, max = 16,
            step = 1, desc = "The most debuffs from other players, shown after yours. Only with Mine first, then others.",
            disabled = function(get) return get(k("debuffs")) ~= true or get(k("debuffFilter")) ~= "all" end }
    end
    debuffs[#debuffs + 1] = { type = "slider", key = k("debuffSpacing"), label = "Spacing", min = 0, max = 12, step = 1,
                              desc = "The gap between debuff icons.", unit = "px", disabled = dOff }
    debuffs[#debuffs + 1] = { type = "slider", key = k("debuffRows"), label = "Rows", min = 1, max = 6, step = 1,
                              desc = "The debuffs wrap onto up to this many rows.", disabled = dOff }
    debuffs[#debuffs + 1] = { type = "slider", key = k("debuffTimeSize"), label = "Time left text size", min = 6, max = 20, step = 1,
                              desc = "How big the time left is on each debuff icon.", disabled = dOff }
    debuffs[#debuffs + 1] = { type = "slider", key = k("debuffCountSize"), label = "Stack count size", min = 6, max = 20, step = 1,
                              desc = "How big the number of stacks is on each debuff icon.", disabled = dOff }
    local buffs = {
        { type = "toggle", key = k("buffs"), label = "Show buffs", desc = "Buff icons by this frame." },
        { type = "slider", key = k("buffSize"), label = "Buff size", min = 12, max = 36, step = 1, unit = "px",
          desc = "How big each buff icon is.", disabled = bOff },
        { type = "slider", key = k("maxBuffs"), label = "Max shown", min = 1, max = 12, step = 1,
          desc = "The most buff icons at once.", disabled = bOff },
        { type = "slider", key = k("buffSpacing"), label = "Spacing", min = 0, max = 12, step = 1, unit = "px",
          desc = "The gap between buff icons.", disabled = bOff },
        { type = "slider", key = k("buffRows"), label = "Rows", min = 1, max = 6, step = 1,
          desc = "The buffs wrap onto up to this many rows.", disabled = bOff },
        { type = "slider", key = k("buffTimeSize"), label = "Time left text size", min = 6, max = 20, step = 1,
          desc = "How big the time left is on each buff icon.", disabled = bOff },
        { type = "slider", key = k("buffCountSize"), label = "Stack count size", min = 6, max = 20, step = 1,
          desc = "How big the number of stacks is on each buff icon.", disabled = bOff },
    }
    for _, it in ipairs(spotItems(prefix, "debuff", k("debuffs"))) do debuffs[#debuffs + 1] = it end
    for _, it in ipairs(spotItems(prefix, "buff", k("buffs"))) do buffs[#buffs + 1] = it end
    return { { label = "Debuffs", desc = desc.debuffs, items = debuffs },
             { label = "Buffs", desc = desc.buffs, items = buffs } }
end

local TARGET_AURA_GROUPS = unitAuraCards("targetAuras", false, {
    debuffs = "Above the name tab by default, running inward. Yours come first.",
    buffs = "Small icons in their own row, under the frame by default." })
-- Off by default, since the buff bars by the info panel show the same.
local PLAYER_AURA_GROUPS = unitAuraCards("playerAuras", true, {
    debuffs = "Every debuff on you, over your frame. Off by default: your buff bars show them too.",
    buffs = "Small icons over your frame, nearest it. Off by default: your buff bars show them too." })

-- The personal display's own rows, dimmed with the display.
local PERSONAL_AURA_GROUPS = unitAuraCards("personal.auras", true, {
    debuffs = "Every debuff on you, by your personal display. Off by default.",
    buffs = "Buff icons by your personal display. Off by default." })
for _, card in ipairs(PERSONAL_AURA_GROUPS) do
    for _, item in ipairs(card.items) do
        local was = item.disabled
        item.disabled = function(get) return get("personal.enabled") ~= true or (was ~= nil and was(get)) end
    end
end

-- The Party page's pets (PartyPets.lua): one card, off by default.
-- Bar textures and fonts are per frame (<frame>.media.*, UF.MEDIA), each row
-- next to the setting it belongs to (the health bar's by its size, the name's
-- font after the name rows). "General" means General > Appearance.
local function mediaRow(kind, key, label, desc, dis)
    local item = DaylightUI.Options.MediaPick(kind, key, label, desc)
    item.disabled = dis
    return item
end
local GENERAL_BAR = " General uses the bar texture on General > Appearance."
local GENERAL_BACK = " General uses the bar background on General > Appearance."
local GENERAL_FONT = " General uses the font on General > Appearance."
-- A bar's two rows as a list, for keys like "player.media.health" (key, key .. "Back").
local function barRows(key, what, label, dis)
    return { mediaRow("bar", key, label .. " texture", "The fill of " .. what .. "." .. GENERAL_BAR, dis),
        mediaRow("back", key .. "Back", label .. " background", "The empty part of " .. what .. ", behind the fill." .. GENERAL_BACK, dis) }
end
local function fontRow(key, label, what, dis)
    return mediaRow("font", key, label, what .. "." .. GENERAL_FONT, dis)
end
-- Which frame strata a piece draws in (ns.STRATA), for frames that overlap.
local STRATA_HOW = " Where two pieces overlap, the higher layer draws on top: Background, Low, Medium, High, then Dialogue."
local function strataRow(key, label, what, dis, more)
    return { type = "dropdown", key = key, label = label, values = ns.STRATA_LABELS, order = ns.STRATA,
             desc = what .. STRATA_HOW .. (more or ""), disabled = dis }
end

-- The swing timer's group rows that only apply detached as a group.
local function groupAttached(get) return get("swing.enabled") ~= true or get("swing.attach") == true end

-- Each swing bar detached on its own: a "Settings for" card showing one bar's
-- rows at a time (swing.bars.<hand>), each with its own handle in /dui unlock.
local SWING_HANDS = { { "main", "Main hand", "swing.mainHand" }, { "off", "Off hand", "swing.offHand" },
                      { "ranged", "Ranged", "swing.ranged" } }
local SWING_BAR_FIELDS = { "visibility", "width", "height", "textSize", "showName", "showTime", "showIcon", "slant", "reverseFill" }
local function swingBarCard()
    local choices = {}
    for _, hand in ipairs(SWING_HANDS) do
        local key, name, show = hand[1], hand[2], hand[3]
        local lower = string.lower(name)
        local function b(f) return "swing.bars." .. key .. "." .. f end
        local function gone(get)
            return get("swing.enabled") ~= true or get(show) ~= true
                or (get("personal.enabled") == true and get("personal.swing") == true)
        end
        local function dis(get) return gone(get) or get(b("detach")) ~= true end
        -- Its own size and look rows appear once it's detached. While attached,
        -- the group's rows above set those.
        local function attached(get) return get(b("detach")) ~= true end
        -- Name and time apply while attached too, under the group's switch for both.
        local function textOff(get) return gone(get) or (get(b("detach")) ~= true and get("swing.showText") ~= true) end
        choices[#choices + 1] = { id = key, label = name, items = {
            { type = "toggle", key = b("detach"), label = "Detach the " .. lower .. " bar",
              desc = "Takes the " .. lower .. " bar out of the group onto a handle of its own (/dui unlock), with the settings below. It rises into place as it fades in.",
              disabled = gone },
            { type = "dropdown", key = b("visibility"), label = name .. ": when to show",
              values = { swinging = "While swinging", combat = "In combat", always = "Always" },
              order = { "swinging", "combat", "always" },
              desc = "While swinging: only while its swing runs. In combat: while you're fighting. Only when detached on its own.",
              disabled = dis, hidden = attached },
            { type = "slider", key = b("width"), label = name .. " bar width", min = 80, max = 500, step = 1,
              desc = "Only when detached on its own.", disabled = dis, hidden = attached },
            { type = "slider", key = b("height"), label = name .. " bar height", min = 6, max = 30, step = 1, unit = "px",
              desc = "Only when detached on its own.", disabled = dis, hidden = attached },
            { type = "slider", key = b("textSize"), label = name .. " bar text size", min = 6, max = 24, step = 1,
              desc = "The hand and time on the bar. Only when detached on its own.", disabled = dis, hidden = attached },
            { type = "toggle", key = b("showName"), label = name .. " bar name",
              desc = "The hand (or the queued attack, or the range) written on the bar, attached or detached.",
              disabled = textOff },
            { type = "toggle", key = b("showTime"), label = name .. " bar time left",
              desc = "The time to the next swing, written on the bar, attached or detached.", disabled = textOff },
            { type = "toggle", key = b("showIcon"), label = name .. " bar weapon icon",
              desc = "The weapon's picture at the start of the bar. Only when detached on its own.", disabled = dis, hidden = attached },
            { type = "toggle", key = b("slant"), label = name .. " bar angled end",
              desc = "Only when detached on its own.", disabled = dis, hidden = attached },
            { type = "toggle", key = b("reverseFill"), label = name .. " bar fills right to left",
              desc = "Only when detached on its own.", disabled = dis, hidden = attached },
        } }
    end
    return DaylightUI.Options.PickCard({ label = "Detached bars",
        desc = "Detach the main hand, off hand or ranged bar from the others to move and size it on its own.",
        pickDesc = "Which bar the rows below set.", disabled = off("swing.enabled"),
        choices = choices,
        copy = { label = "Copy from", desc = "Another swing bar whose look to copy onto the one picked in Settings for.",
                 button = "Copy the bar", buttonDesc = "Replaces the picked bar's size, text and look with the one above's. Whether it's detached and where it sits stay.",
                 fn = function(from, to)
                     for _, f in ipairs(SWING_BAR_FIELDS) do
                         local v = DaylightUI:Get("UnitFrames", "swing.bars." .. from .. "." .. f)
                         if v ~= nil then DaylightUI:Set("UnitFrames", "swing.bars." .. to .. "." .. f, v) end
                     end
                 end } })
end

-- A frame's own bar colors (<frame>.colorHealth / colorPower), each next to its
-- bar's rows. "global" follows the Colors page.
local HEALTH_COLORS = { global = "Same as the Colors page", class = "Class and reaction", classGradient = "Class gradient",
    gradient = "By health (green to red)", custom = "One color", dark = "Dark (missing health colored)" }
local HEALTH_COLOR_ORDER = { "global", "class", "classGradient", "gradient", "custom", "dark" }
-- Your own frame can also take the Daylight gradient or your accent.
local PLAYER_HEALTH_COLORS = { daylight = "Daylight gradient", accent = "Accent color" }
local PLAYER_HEALTH_ORDER = { "global", "daylight", "accent" }
for k, v in pairs(HEALTH_COLORS) do PLAYER_HEALTH_COLORS[k] = v end
for i = 2, #HEALTH_COLOR_ORDER do PLAYER_HEALTH_ORDER[#PLAYER_HEALTH_ORDER + 1] = HEALTH_COLOR_ORDER[i] end
local POWER_COLORS = { global = "Same as the Colors page", type = "By power type", gradient = "Power gradient",
    custom = "One color" }
local POWER_COLOR_ORDER = { "global", "type", "gradient", "custom" }

local function healthColorRows(id, dis)
    local k = function(s) return id .. "." .. s end
    return {
        { type = "dropdown", key = k("colorHealth"), label = "Health bar color",
          values = id == "player" and PLAYER_HEALTH_COLORS or HEALTH_COLORS,
          order = id == "player" and PLAYER_HEALTH_ORDER or HEALTH_COLOR_ORDER, disabled = dis,
          desc = id == "player"
              and "Your frame's own health color, so it can look unlike the others. Same as the Colors page follows the color every frame shares; Daylight gradient is the logo's blue to orange; Accent color follows your accent on General > Appearance, gradient included."
              or "This frame's own health color, so it can look unlike the others. Same as the Colors page follows the color every frame shares." },
        { type = "color", key = k("colorHealthCustom"), label = "Custom health color", disabled = dis,
          desc = "The health bar's color when Health bar color is One color.",
          hidden = notCustom(k("colorHealth")) },
    }
end

local function powerColorRows(id, dis)
    local k = function(s) return id .. "." .. s end
    return {
        { type = "dropdown", key = k("colorPower"), label = "Power bar color", values = POWER_COLORS,
          order = POWER_COLOR_ORDER, disabled = dis,
          desc = "This frame's own power color. Same as the Colors page follows the color every frame shares." },
        { type = "color", key = k("colorPowerCustom"), label = "Custom power color", disabled = dis,
          desc = "The power bar's color when Power bar color is One color.",
          hidden = notCustom(k("colorPower")) },
    }
end

-- The personal display's rows for one bar: texture, background and color, each
-- using the player frame's until given its own. bar: "health" | "power".
local function personalBarRows(bar, dis)
    local key = "personal.media." .. bar
    local slot = ns.UF.MEDIA.player.bars[bar]
    local label = bar == "health" and "Health bar" or "Power bar"
    local follow = " General uses your player frame's, or the one on General > Appearance when that has none."
    local rows = {
        DaylightUI.Options.MediaPick("bar", key, label .. " texture", "The fill of the bar." .. follow,
            { disabled = dis, follows = { slot = slot, label = "Player frame" } }),
        DaylightUI.Options.MediaPick("back", key .. "Back", label .. " background", "The empty part of the bar, behind the fill." .. follow,
            { disabled = dis, follows = { slot = slot .. ".back", label = "Player frame" } }),
    }
    local values, order = { player = "Player frame" }, { "player" }
    local from = bar == "health" and PLAYER_HEALTH_COLORS or POWER_COLORS
    for _, k in ipairs(bar == "health" and PLAYER_HEALTH_ORDER or POWER_COLOR_ORDER) do
        values[k], order[#order + 1] = from[k], k
    end
    local mode = bar == "health" and "personal.colorHealth" or "personal.colorPower"
    rows[3] = { type = "dropdown", key = mode, label = label .. " color", values = values, order = order, disabled = dis,
                desc = "The bar's own color, so it can look unlike your player frame. Same as the Colors page follows the color every frame shares." }
    rows[4] = { type = "color", key = mode .. "Custom", label = "Custom " .. bar .. " color", disabled = dis,
                desc = "The bar's color when it's set to One color.", hidden = notCustom(mode) }
    return rows
end
local PERSONAL_HEALTH = personalBarRows("health", offAny("personal.enabled", "personal.showHealth"))
local PERSONAL_POWER = personalBarRows("power", offAny("personal.enabled", "personal.showPower"))

-- The numbers on its bars: the player frame's rows, plus a position and a size.
local function personalTextCard()
    local k = function(s) return "personal." .. s end
    local font = function(bar, label, dis)
        return DaylightUI.Options.MediaPick("font", k("media." .. bar .. "Font"), label,
            "The number on the bar. General uses your player frame's, or the one on General > Appearance when that has none.",
            { disabled = dis, follows = { slot = ns.UF.MEDIA.player.fonts[bar], label = "Player frame" } })
    end
    local health = offAny("personal.enabled", k("showHealth"), k("showPercent"))
    local power = offAny("personal.enabled", k("showPower"), k("showPowerText"))
    return { label = "Text", items = {
        { type = "toggle", key = k("showPercent"), label = "Health text",
          desc = "Your health written on the personal display's health bar.",
          disabled = offAny("personal.enabled", k("showHealth")) },
        { type = "dropdown", key = k("healthText"), label = "Health text format", values = UF.HEALTH_FORMATS,
          order = UF.HEALTH_FORMAT_ORDER, desc = "Missing health shows nothing while you're at full.", disabled = health },
        { type = "toggle", key = k("percentSign"), label = "Show % sign",
          desc = "62% rather than 62, when the health text shows a percent.", disabled = health },
        { type = "toggle", key = k("hideFullHealth"), invert = true, label = "Show health text at full",
          desc = "The health text shows at full health too. When off, it disappears while you're at full.", disabled = health },
        { type = "dropdown", key = k("healthTextPos"), label = "Health text position", values = UF.POWER_TEXT_POS,
          order = UF.POWER_TEXT_POS_ORDER, desc = "Where along the health bar the health text sits.", disabled = health },
        { type = "slider", key = k("healthTextSize"), label = "Health text size", min = 0, max = 24, step = 1,
          desc = "Set to 0 to fit the bar.", disabled = health },
        font("health", "Health text font", health),
        { type = "toggle", key = k("showPowerText"), label = "Power text",
          desc = "Your mana, rage or energy written on the personal display's power bar.",
          disabled = offAny("personal.enabled", k("showPower")) },
        { type = "dropdown", key = k("powerFormat"), label = "Power text format", values = UF.POWER_FORMATS,
          order = UF.POWER_FORMAT_ORDER, desc = "How the power text is written.", disabled = power },
        { type = "toggle", key = k("hideFullPower"), invert = true, label = "Show power text at full",
          desc = "The power text shows while mana, rage or energy is full too. When off, it disappears at full.", disabled = power },
        { type = "dropdown", key = k("powerTextPos"), label = "Power text position", values = UF.POWER_TEXT_POS,
          order = UF.POWER_TEXT_POS_ORDER, desc = "Where along the power bar the power text sits.", disabled = power },
        { type = "slider", key = k("powerTextSize"), label = "Power text size", min = 0, max = 24, step = 1,
          desc = "Set to 0 to fit the bar.", disabled = power },
        font("power", "Power text font", power),
    } }
end

-- A frame's own border, corners and shadow (<frame>.shell). gate: its Show key.
local function shellCard(id, gate, bar)
    local k = function(s) return id .. ".shell." .. s end
    local dis = offAny(gate, k("own"))
    return { label = "Border and shadow",
        desc = bar and "This bar's own outline, corners and shadow, to match a power bar of its own or stand apart."
            or "This frame's own outline, corners and shadow, so it can stand apart from the rest of your UI.",
        items = {
            { type = "toggle", key = k("own"), label = "Own border and shadow", disabled = off(gate),
              desc = bar and "Gives this bar the border, corners and shadow below. When off, it follows General > Appearance."
                  or "Gives this frame the border, corners and shadow below. When off, it follows General > Appearance." },
            { type = "slider", key = k("borderPx"), label = "Border thickness", min = 0, max = 16, step = 1, unit = "px",
              desc = "0 leaves just the bars, with no outline round them.", disabled = dis },
            { type = "slider", key = k("cornerPx"), label = "Corner rounding", min = 0, max = 24, step = 1, unit = "px",
              desc = "How round this frame's corners are. 0 keeps them sharp.", disabled = dis },
            { type = "slider", key = k("shadowPx"), label = "Shadow size", min = 0, max = 12, step = 1, unit = "px",
              desc = "How far this frame's shadow spreads. 0 leaves no shadow.", disabled = dis },
        } }
end

-- The name tab's own look and placement (<frame>.tab, Defaults.lua TAB_FRAMES).
-- Daylight only (Ribbon's row has no shell), while the name is in its tab.
local TAB_SLANTS = { frame = "Same as the frame", on = "Angled", off = "Straight" }
local TAB_AT = { outer = "Outer end", middle = "Middle", inner = "Inner end" }
local TAB_WIDTHS = { fit = "Fit the name", full = "Full width", fixed = "Fixed width" }
local TAB_ALIGNS = { left = "Left", center = "Center", right = "Right" }
local function tabCard(id, ribbon)
    local k = function(s) return id .. ".tab." .. s end
    local f = function(s) return id .. "." .. s end
    local noTab = function(get)
        return get(f("enabled")) == false or get(f("showName")) == false or get(f("nameOnBar")) == true
    end
    local dis = function(get) return noTab(get) or get(k("own")) ~= true end
    return { label = "Name tab",
        desc = "The small tab that holds the name above the frame: its own border, corners, shadow, place and width.",
        items = {
            { type = "toggle", key = k("own"), label = "Own name tab look", disabled = noTab, hidden = ribbon,
              desc = "Gives the name tab the border, corners and shadow below. When off, it matches the frame." },
            { type = "slider", key = k("borderPx"), label = "Name tab border thickness", min = 0, max = 16, step = 1,
              desc = "How thick the name tab's outline is. 0 leaves none.", unit = "px", disabled = dis, hidden = ribbon },
            { type = "slider", key = k("cornerPx"), label = "Name tab corner rounding", min = 0, max = 24, step = 1,
              desc = "How round the name tab's corners are. 0 keeps them sharp.", unit = "px", disabled = dis, hidden = ribbon },
            { type = "slider", key = k("shadowPx"), label = "Name tab shadow size", min = 0, max = 12, step = 1,
              desc = "How far the name tab's shadow spreads. 0 leaves no shadow.", unit = "px", disabled = dis, hidden = ribbon },
            { type = "dropdown", key = k("slant"), label = "Name tab angled end", values = TAB_SLANTS,
              desc = "Whether the name tab's end is cut at an angle. Same as the frame follows the frame's own end.",
              order = { "frame", "on", "off" }, disabled = noTab, hidden = ribbon },
            { type = "dropdown", key = k("at"), label = "Name tab position", values = TAB_AT,
              order = { "outer", "middle", "inner" },
              desc = "Where along the frame's top the tab sits. A full-width tab always starts at the outer end. Or drag the tab in Design mode.",
              disabled = function(get) return noTab(get) or get(k("width")) == "full" end, hidden = ribbon },
            { type = "slider", key = k("x"), label = "Name tab left / right", min = -100, max = 100, step = 1,
              desc = "Nudges the name tab sideways along the frame's top.", unit = "px", disabled = noTab, hidden = ribbon },
            { type = "slider", key = k("y"), label = "Name tab up / down", min = -10, max = 40, step = 1, unit = "px",
              desc = "Lift the tab off the frame to float it above with a gap.", disabled = noTab, hidden = ribbon },
            { type = "dropdown", key = k("width"), label = "Name tab width", values = TAB_WIDTHS,
              order = { "fit", "full", "fixed" },
              desc = "Fit the name grows and shrinks with each name. Full width runs along the whole top of the frame.",
              disabled = noTab, hidden = ribbon },
            { type = "slider", key = k("widthPx"), label = "Fixed name tab width", min = 30, max = 400, step = 1,
              desc = "How wide the name tab is when Name tab width is Fixed width.", unit = "px", disabled = function(get) return noTab(get) or get(k("width")) ~= "fixed" end, hidden = ribbon },
            { type = "dropdown", key = k("align"), label = "Name alignment in the tab", values = TAB_ALIGNS,
              desc = "Where the name sits inside its tab: left, center or right.",
              order = { "left", "center", "right" }, disabled = noTab, hidden = ribbon },
        } }
end

local function petCard()
    local p = function(s) return "partyPet." .. s end
    local petOff = offAny("party.enabled", p("enabled"))
    return { label = "Pets", desc = "A small bar beside each party member who has a pet out. Your own pet keeps its own frame.", items = {
        { type = "toggle", key = p("enabled"), label = "Show pets", disabled = off("party.enabled"),
          desc = "A small pet bar beside each party member whose pet is out." },
        { type = "dropdown", key = p("spot"), label = "Position", values = ns.PartyPets.SPOTS, order = ns.PartyPets.SPOT_ORDER,
          desc = "Which side of its owner's frame each pet bar sits on.", disabled = petOff },
        { type = "slider", key = p("x"), label = "Pets left / right", min = -50, max = 50, step = 1, unit = "px",
          desc = "Nudges the pet bars sideways from their position.", disabled = petOff },
        { type = "slider", key = p("y"), label = "Pets up / down", min = -50, max = 50, step = 1, unit = "px",
          desc = "Nudges the pet bars up or down from their position.", disabled = petOff },
        { type = "slider", key = p("width"), label = "Width", min = 30, max = 200, step = 1,
          desc = "How wide each pet bar is.", disabled = petOff },
        { type = "slider", key = p("height"), label = "Height", min = 10, max = 40, step = 1,
          desc = "How tall each pet bar is.", disabled = petOff },
        barRows(p("media.health"), "the pets' health bars", "Health bar", petOff)[1],
        barRows(p("media.health"), "the pets' health bars", "Health bar", petOff)[2],
        { type = "toggle", key = p("slant"), label = "Angled end",
          desc = "Cuts one end of each pet bar at an angle. When off, the ends are straight.", disabled = petOff },
        { type = "dropdown", key = p("color"), label = "Bar color", values = ns.PartyPets.COLORS, order = ns.PartyPets.COLOR_ORDER,
          desc = "Its owner's class tells at a glance whose pet it is.", disabled = petOff },
        { type = "toggle", key = p("showPower"), label = "Power bar",
          desc = "A thin power bar under each pet's health.", disabled = offAny("party.enabled", p("enabled")) },
        { type = "slider", key = p("powerHeight"), label = "Power bar height", min = 2, max = 12, step = 1,
          desc = "How tall the pets' power bars are.", disabled = offAny("party.enabled", p("enabled"), p("showPower")) },
        barRows(p("media.power"), "the pets' power bars", "Power bar", offAny("party.enabled", p("enabled"), p("showPower")))[1],
        barRows(p("media.power"), "the pets' power bars", "Power bar", offAny("party.enabled", p("enabled"), p("showPower")))[2],
        { type = "toggle", key = p("showName"), label = "Name",
          desc = "Shows each pet's name.", disabled = petOff },
        { type = "slider", key = "partyPetText.name", label = "Name size", min = 6, max = 24, step = 1,
          desc = "How big the pets' names are.", disabled = offAny("party.enabled", p("enabled"), p("showName")) },
        fontRow(p("media.nameFont"), "Name font", "The pets' names", offAny("party.enabled", p("enabled"), p("showName"))),
        { type = "toggle", key = p("showPercent"), label = "Health text",
          desc = "Shows each pet's health as text.", disabled = petOff },
        { type = "dropdown", key = p("healthText"), label = "Health text format",
          values = UF.HEALTH_FORMATS, order = UF.HEALTH_FORMAT_ORDER, desc = "How the pets' health text is written.",
          disabled = offAny("party.enabled", p("enabled"), p("showPercent")) },
        { type = "slider", key = "partyPetText.percent", label = "Health text size", min = 6, max = 24, step = 1,
          desc = "How big the pets' health text is.", disabled = offAny("party.enabled", p("enabled"), p("showPercent")) },
        fontRow(p("media.healthFont"), "Health text font", "The pets' health text", offAny("party.enabled", p("enabled"), p("showPercent"))),
    } }
end

-- The frames' style (Defaults.lua, UF.StyleOf). A pick writes through
-- ns.SetStyle, so each frame takes that style's own heights before anything
-- redraws. own: a frame's pick, which can follow the Extras page's.
local STYLE_DESC = "Daylight: the frame with its name in a tab above it and the power bar inside."
    .. " Ribbon: a slim bar with the name and health floating above it and the power as a thin line under it."
-- The current settings, for a row that asks outside its page's get.
local function liveGet(key) return DaylightUI:Get("UnitFrames", key) end

local function styleRow(key, own, dis)
    local values = { daylight = UF.STYLES.daylight, ribbon = UF.STYLES.ribbon }
    local order = { "daylight", "ribbon" }
    if own then
        values.global = "Default"
        order = { "global", "daylight", "ribbon" }
    end
    -- A frame's "Default" names the style it gives: "Default (Daylight)".
    local function choices()
        if not own then return values, order end
        local named = { daylight = values.daylight, ribbon = values.ribbon }
        local every = liveGet("look.style") == "ribbon" and values.ribbon or values.daylight
        named.global = "Default (" .. every .. ")"
        return named, order
    end
    return { type = "dropdown", key = key, label = "Frame style", values = values, order = order, choices = choices,
             desc = STYLE_DESC .. (own
                 and " Default uses the style set for every frame (Extras > Frame style). Each style keeps its own heights."
                 or " Each frame can pick its own on its page."),
             get = function() return DaylightUI:Get("UnitFrames", key) end,
             set = function(v) ns.SetStyle(key, v) end,
             default = function() return own and "global" or "daylight" end,
             disabled = dis }
end

-- Tabs on a frame page: Basics first (position, size and shape, when it
-- shows), then its bars, text, auras and the rest. A card's tab is decided by
-- its title, and cards are sorted by tab while keeping their order within one.
local TAB_ORDER = { "Basics", "Bars", "Text", "Auras", "Extras" }
local TAB_OF = { ["Raid size"] = "Basics", ["Quick looks"] = "Basics", Layout = "Basics", Frame = "Basics",
    [DaylightUI.Fade.CARD_LABEL] = "Basics", ["Health and power"] = "Bars", ["Health bar"] = "Bars",
    ["Border and shadow"] = "Bars", Text = "Text", ["Name tab"] = "Text", Debuffs = "Auras", Buffs = "Auras",
    ["Heal indicators"] = "Auras", ["Boss debuffs"] = "Auras", Dispels = "Auras" }
local function tabOf(label)
    if TAB_OF[label] then return TAB_OF[label] end
    if string.find(label, "^Extra text") then return "Text" end
    if string.find(label, "^Extra aura group") then return "Auras" end
    for _, def in ipairs(ns.AuraGroups.DEFS) do
        if def.label == label then return "Auras" end
    end
    return "Extras"
end
local function tabbed(groups)
    local rank = {}
    for i, t in ipairs(TAB_ORDER) do rank[t] = i end
    local list = {}
    for i, g in ipairs(groups) do
        g.tab = tabOf(g.label)
        list[i] = { g = g, i = i }
    end
    table.sort(list, function(a, b)
        local ra, rb = rank[a.g.tab], rank[b.g.tab]
        if ra ~= rb then return ra < rb end
        return a.i < b.i
    end)
    local out = {}
    for i, e in ipairs(list) do out[i] = e.g end
    return out
end
-- A frame's own rows that cover its size and shape (Basics). The rest of its
-- Frame card (bar textures and colors, power, heals and absorbs) becomes its
-- "Health and power" card.
local BASIC_FIELDS = { enabled = true, style = true, width = true, height = true, spacing = true, portrait = true,
    portraitRing = true, portraitDragon = true, portraitDragonColor = true, portraitScale = true, tabHeight = true, slant = true, fillVertical = true,
    showInParty = true, direction = true, sortBy = true, groups = true, groupSpacing = true, perLine = true, hideSelf = true,
    strata = true }
local function splitFrame(prefix, items, power)
    local basic, bars = {}, {}
    for _, it in ipairs(items) do
        local field = type(it.key) == "string" and string.match(it.key, "^" .. prefix .. "%.([^%.]+)$")
        if field and BASIC_FIELDS[field] then basic[#basic + 1] = it else bars[#bars + 1] = it end
    end
    return { label = "Frame", items = basic },
           { label = power and "Health and power" or "Health bar", items = bars }
end

local function framePage(id, label, desc, opts)
    local k = function(s) return id .. "." .. s end
    local shown = off(k("enabled"))
    -- No power bar here, since the frame's own switch is off.
    local function powerOff(get)
        return shown(get) or get(k("showPower")) == false
    end
    local function powerTextOff(get) return powerOff(get) or get(k("showPowerText")) ~= true end
    -- The spell cost and regen sweep also run on the personal display's bar.
    local function powerSpellOff(get) return shown(get) or (powerOff(get) and get("personal.enabled") ~= true) end
    -- A frame that can use Ribbon (Defaults.lua): its pick, plus the rows that
    -- mean something else there, shown in that style's terms (the bar's
    -- height, the name's row, the power line), each hidden in the other style.
    local styled = false
    for _, f in ipairs(ns.RIBBON_FRAMES) do styled = styled or f == id end
    local function ribbon(get)
        if not styled then return false end
        local s = get(k("style"))
        if s == nil or s == "global" then s = get("look.style") end
        return s == "ribbon"
    end
    local function daylight(get) return not ribbon(get) end
    -- Too short for a portrait (UF.PortraitHeight; in Ribbon, the whole ribbon).
    local function tooShort(get)
        local cfg = { height = get(k("height")), tabHeight = get(k("tabHeight")), showPower = get(k("showPower")),
                      ribbonGap = get(k("ribbonGap")), powerHeight = get(k("powerHeight")), style = get(k("style")) }
        return UF.PortraitHeight({ spec = { ribbon = styled } }, cfg) < UF.MIN_PORTRAIT_HEIGHT
    end
    local frame = {
        { type = "toggle", key = k("enabled"), label = opts.showLabel or ("Show the " .. string.lower(label) .. " frame"),
          desc = opts.showDesc or ("Turn the " .. label .. " frame on or off.") },
    }
    if styled then frame[#frame + 1] = styleRow(k("style"), true, shown) end
    frame[#frame + 1] = { type = "slider", key = k("width"), label = "Width", min = opts.minWidth or SIZE.min, max = SIZE.max, step = 1,
        desc = "How wide this frame is.", disabled = shown }
    frame[#frame + 1] = { type = "slider", key = k("height"), label = "Height", min = 10, max = opts.maxHeight or 80, step = 1,
        desc = "How tall this frame is.", disabled = shown, hidden = ribbon }
    if styled then
        frame[#frame + 1] = { type = "slider", key = k("height"), label = "Bar height", min = 10, max = opts.maxHeight or 80,
            step = 1, desc = "The slim health bar. The name, the health number and the power line sit outside it.",
            disabled = shown, hidden = daylight }
    end
    frame[#frame + 1] = strataRow(k("strata"), "Frame layer",
        opts.strataWhat or ("The layer the " .. string.lower(label) .. " frame draws in."), shown)
    local m = function(s) return id .. ".media." .. s end
    for _, it in ipairs(barRows(m("health"), "this frame's health bar", "Health bar", shown)) do frame[#frame + 1] = it end
    for _, it in ipairs(healthColorRows(id, shown)) do frame[#frame + 1] = it end
    if opts.powerToggle then
        frame[#frame + 1] = { type = "toggle", key = k("showPower"), label = "Power bar",
            desc = "A mana, rage or energy bar under the health. When off, the frame is all health.",
            disabled = shown }
    end
    if opts.power then
        frame[#frame + 1] = { type = "slider", key = k("powerHeight"), label = "Power bar height", min = 2, max = 20, step = 1,
            desc = "How tall the power bar is.", disabled = powerOff, hidden = ribbon }
        if styled then
            frame[#frame + 1] = { type = "slider", key = k("powerHeight"), label = "Power line height", min = 2, max = 20,
                step = 1, desc = "The thin power bar under the health bar.", disabled = powerOff, hidden = daylight }
            frame[#frame + 1] = { type = "slider", key = k("ribbonGap"), label = "Gap above the power line", min = 0, max = 12,
                step = 1, unit = "px", desc = "The space between the health bar and the power line under it.",
                disabled = powerOff, hidden = daylight }
        end
    end
    if opts.power or opts.powerToggle then
        for _, it in ipairs(barRows(m("power"), "this frame's power bar", "Power bar", powerOff)) do frame[#frame + 1] = it end
        for _, it in ipairs(powerColorRows(id, powerOff)) do frame[#frame + 1] = it end
    end
    if opts.powerFree then
        local notFree = function(get) return powerOff(get) or get(k("powerAt")) ~= "free" end
        local AT = { inside = "Inside the frame", free = "On its own (unlock to move)" }
        local AT_RIBBON = { inside = "Under the frame", free = AT.free }
        frame[#frame + 1] = { type = "dropdown", key = k("powerAt"), label = "Power bar position",
            values = AT, order = { "inside", "free" },
            -- In Ribbon "inside" is the line under the frame.
            choices = function()
                return (ribbon(liveGet) and AT_RIBBON or AT), { "inside", "free" }
            end,
            desc = "On its own, the power bar leaves the frame and you can move it anywhere in unlock mode, like the middle of the screen. The frame is then all health.",
            disabled = powerOff }
        frame[#frame + 1] = { type = "slider", key = k("powerWidth"), label = "Power bar width", min = 40, max = 500, step = 1,
            desc = "Only while the power bar is on its own.", disabled = notFree }
        frame[#frame + 1] = { type = "toggle", key = k("powerSlant"), label = "Power bar angled end",
            desc = "Only while the power bar is on its own. When off, both ends are straight.", disabled = notFree }
    end
    if opts.tile then
        frame[#frame + 1] = { type = "toggle", key = k("fillVertical"), label = "Fill upward",
            desc = "The health bar fills bottom to top instead of across.", disabled = shown }
    end
    if opts.spacing then
        frame[#frame + 1] = { type = "slider", key = k("spacing"), label = "Spacing", min = 0, max = 80, step = 1,
            desc = id == "arena" and "The gap between one PvP frame and the next." or "The gap between one party frame and the next.", disabled = shown }
    end
    if opts.portrait then
        frame[#frame + 1] = { type = "dropdown", key = k("portrait"), label = "Portrait",
            values = UF.PORTRAIT_MODES, order = UF.PORTRAIT_ORDER,
            desc = "A ring over the outer end. Class icons show for players; NPCs show their face."
                .. " Needs a frame at least " .. UF.MIN_PORTRAIT_HEIGHT .. " tall.",
            disabled = function(get) return shown(get) or tooShort(get) end }
        frame[#frame + 1] = { type = "dropdown", key = k("portraitRing"), label = "Ring color",
            values = UF.RING_COLORS, order = UF.RING_COLOR_ORDER,
            desc = "Class gradient: the unit's class colors (an NPC's are by how friendly it is), and the red aggro ring is shaded to match. Accent color: your accent on every frame. Daylight gradient: the logo's colors on every frame. Light: a gray ring. Dark: the same dark border as the frame.",
            disabled = function(get) return shown(get) or get(k("portrait")) == "none" or tooShort(get) end }
        if opts.dragon then
            frame[#frame + 1] = { type = "toggle", key = k("portraitDragon"), label = "Dragon around the portrait",
                desc = "The elite dragon wraps your own portrait too.",
                disabled = function(get) return shown(get) or get(k("portrait")) == "none" or tooShort(get) end }
            frame[#frame + 1] = { type = "dropdown", key = k("portraitDragonColor"), label = "Dragon color",
                values = UF.DRAGON_COLORS, order = UF.DRAGON_COLOR_ORDER,
                desc = "Gold or silver like an elite's, your accent color, or your class colors.",
                disabled = function(get) return shown(get) or get(k("portrait")) == "none" or tooShort(get)
                    or not get(k("portraitDragon")) end }
        end
    end
    if opts.power or opts.flip then
        frame[#frame + 1] = { type = "toggle", key = k("reverseFill"), label = "Fill from the other end",
            desc = opts.power and "Health and power bars fill from the opposite side."
                or "The health bar fills from the opposite side.", disabled = shown }
    end
    if opts.tab then
        frame[#frame + 1] = { type = "slider", key = k("tabHeight"), label = "Name tab height", min = 10, max = 28, step = 1, unit = "px",
            desc = "How tall the tab holding the name above the frame is.", disabled = shown, hidden = ribbon }
        if styled then
            frame[#frame + 1] = { type = "slider", key = k("tabHeight"), label = "Name row height", min = 10, max = 28, step = 1,
                unit = "px", desc = "The row above the bar that holds the name and the health number.",
                disabled = shown, hidden = daylight }
        end
    end
    if opts.portrait then
        frame[#frame + 1] = { type = "slider", key = k("portraitScale"), label = "Portrait size", min = 0.6, max = 1.5, step = 0.05, unit = "%",
            desc = "How big the portrait ring is next to the frame's height.",
            disabled = function(get) return shown(get) or tooShort(get) end }
    end
    frame[#frame + 1] = { type = "toggle", key = k("slant"), label = "Angled end",
        desc = opts.slantDesc or "Cuts the frame's inner end at an angle; the bars follow it.", disabled = shown }
    frame[#frame + 1] = { type = "toggle", key = k("predictHeals"), label = "Incoming heals",
        desc = "Heals on their way, as a soft green stretch past the health.", disabled = shown }
    frame[#frame + 1] = { type = "toggle", key = k("predictAbsorbs"), label = "Absorbs",
        desc = "Damage shields, as a pale stretch after any incoming heals.", disabled = shown }
    if opts.dots then
        frame[#frame + 1] = { type = "toggle", key = k("dotTint"), label = "DoT damage left",
            desc = "Your damage over time spells: the end of the health they will still take is shaded darker.", disabled = shown }
        frame[#frame + 1] = { type = "toggle", key = k("dotSkull"), label = "Skull when your DoTs will kill it",
            desc = "A small skull on the portrait once your damage over time is enough to finish the target.", disabled = shown }
    end

    local text = {
        { type = "toggle", key = k("showName"), label = (opts.tab and not opts.small) and "Name tab" or "Name",
          desc = (opts.tab and not opts.small) and "The name sits in a small tab above the frame. Long names are cut short."
              or "Shows the unit's name on this frame.",
          disabled = shown, hidden = ribbon },
        lastNames(id),
        { type = "dropdown", key = k("nameColor"), label = "Name color", values = NAME_COLORS, order = NAME_COLOR_ORDER,
          desc = "This frame's own name color. Same as the Colors page follows the name color every frame shares.",
          disabled = shown },
        { type = "color", key = k("nameCustom"), label = "Custom name color", hidden = notCustom(k("nameColor")),
          desc = "The name's color when Name color is Custom.", disabled = shown },
        { type = "slider", key = k("nameLimitLen"), label = "Max name length", min = 0, max = 24, step = 1,
          desc = "Letters shown before a long name is shortened. 0 shows names in full. In instances some names can't be shortened and show in full.", disabled = shown },
    }
    if opts.tab then
        table.insert(text, 2, { type = "toggle", key = k("nameOnBar"), label = "Name on the bar",
            desc = opts.small and "Keeps the name inside the bar. When off, it sits in a small tab above the frame, like the other frames' names."
                or "Puts the name inside the health bar, beside the portrait, instead of in the tab above (which can cover a cast bar placed there).",
            disabled = offAny(k("enabled"), k("showName")) })
        -- Where the name sits on the bar (on a tile: across it, or a spot).
        local onBar = function(get)
            return shown(get) or get(k("showName")) == false or get(k("nameOnBar")) ~= true
        end
        for n, it in ipairs(nameItems(k, onBar, "Where the name sits across the bar, while it's on the bar: left, center or right.",
            not opts.tile and not opts.small, opts.small)) do
            table.insert(text, 2 + n, it)
        end
    else
        -- A small frame's name: on its bar, or at a spot around it.
        for n, it in ipairs(nameItems(k, offAny(k("enabled"), k("showName")), nil, false, true)) do
            table.insert(text, 2 + n, it)
        end
    end
    if styled then
        table.insert(text, 2, { type = "toggle", key = k("showName"), label = "Name",
            desc = "The name floats above the bar, at its outer end. Long names are cut short.",
            disabled = shown, hidden = daylight })
    end
    text[#text + 1] = fontRow(m("nameFont"), "Name font", "This frame's names, and its level badge", shown)
    if opts.healthText then
        text[#text + 1] = { type = "toggle", key = k("showPercent"), label = "Health text",
            desc = "The unit's health written on this frame.", disabled = shown }
        text[#text + 1] = { type = "dropdown", key = k("healthText"), label = "Health text format",
            values = UF.HEALTH_FORMATS, order = UF.HEALTH_FORMAT_ORDER,
            desc = "Missing health shows nothing while the unit is at full.",
            disabled = offAny(k("enabled"), k("showPercent")) }
        text[#text + 1] = { type = "toggle", key = k("percentSign"), label = "Show % sign",
            desc = "62% rather than 62, when the health text shows a percent.",
            disabled = offAny(k("enabled"), k("showPercent")) }
        text[#text + 1] = { type = "toggle", key = k("hideFullHealth"), invert = true, label = "Show health text at full",
            desc = "The health text shows at full health too. When off, it disappears while the unit is at full.",
            disabled = offAny(k("enabled"), k("showPercent")) }
    end
    if opts.healthText then
        text[#text + 1] = { type = "dropdown", key = k("percentColor"), label = "Health text color",
            values = TEXT_COLORS, order = TEXT_COLOR_ORDER, desc = "White, the unit's class color, or one you pick.",
            disabled = offAny(k("enabled"), k("showPercent")) }
        text[#text + 1] = { type = "color", key = k("percentCustom"), label = "Custom health text color",
            desc = "The health text's color when Health text color is Custom.",
            hidden = notCustom(k("percentColor")), disabled = offAny(k("enabled"), k("showPercent")) }
        text[#text + 1] = fontRow(m("healthFont"), "Health text font", "This frame's health text and large number",
            offAny(k("enabled"), k("showPercent")))
    end
    if opts.big then
        text[#text + 1] = { type = "toggle", key = k("bigNumber"), label = "Large health number",
            desc = "Shows the health text large and white in the frame's inner corner (in Ribbon, at the inner end of the row above the bar).",
            disabled = offAny(k("enabled"), k("showPercent")) }
    end
    if opts.power then
        text[#text + 1] = { type = "toggle", key = k("showPowerText"), label = "Power text",
            desc = "A small mana, rage or energy number on the power bar.", disabled = powerOff }
        text[#text + 1] = { type = "dropdown", key = k("powerFormat"), label = "Power text format",
            values = UF.POWER_FORMATS, order = UF.POWER_FORMAT_ORDER, desc = "How the power text is written.",
            disabled = powerTextOff }
        text[#text + 1] = { type = "toggle", key = k("hideFullPower"), invert = true, label = "Show power text at full",
            desc = "The power text shows while mana, rage or energy is full too. When off, it disappears at full.",
            disabled = powerTextOff }
        if opts.powerPos then
            text[#text + 1] = { type = "dropdown", key = k("powerTextPos"), label = "Power text position",
                values = UF.POWER_TEXT_POS, order = UF.POWER_TEXT_POS_ORDER,
                desc = "Where along the power bar the power text sits.", disabled = powerTextOff }
        end
        text[#text + 1] = fontRow(m("powerFont"), "Power text font", "This frame's power text",
            powerTextOff)
    end
    -- Sizes: this frame's own (the party's are shared by all four).
    local t = function(s) return id .. "Text." .. s end
    text[#text + 1] = { type = "slider", key = t("name"), label = "Name size", min = 6, max = 24, step = 1,
        desc = "How big the name is on this frame.", disabled = shown }
    if opts.healthText then
        text[#text + 1] = { type = "slider", key = t("percent"), label = "Health text size", min = 6, max = 24, step = 1,
            desc = "How big the health text is on this frame.", disabled = shown }
    end
    if opts.powerPos then
        text[#text + 1] = { type = "slider", key = t("power"), label = "Power text size", min = 0, max = 24, step = 1,
            desc = "Set to 0 to fit the bar.", disabled = powerTextOff }
    end
    if opts.big then
        text[#text + 1] = { type = "slider", key = t("big"), label = "Large number size", min = 10, max = 40, step = 1,
            desc = "How big the large health number is.", disabled = shown }
    end
    if opts.textPos then
        text[#text + 1] = { type = "slider", key = k("healthTextX"), label = "Health text left / right",
            desc = "Nudges the health text sideways from its place.",
            min = -50, max = 50, step = 1, unit = "px", disabled = offAny(k("enabled"), k("showPercent")) }
        text[#text + 1] = { type = "slider", key = k("healthTextY"), label = "Health text up / down",
            desc = "Nudges the health text up or down from its place.",
            min = -50, max = 50, step = 1, unit = "px", disabled = offAny(k("enabled"), k("showPercent")) }
        if opts.power then
            text[#text + 1] = { type = "slider", key = k("powerTextX"), label = "Power text left / right",
                desc = "Nudges the power text sideways from its place.",
                min = -50, max = 50, step = 1, unit = "px", disabled = powerTextOff }
            text[#text + 1] = { type = "slider", key = k("powerTextY"), label = "Power text up / down",
                desc = "Nudges the power text up or down from its place.",
                min = -50, max = 50, step = 1, unit = "px", disabled = powerTextOff }
        end
    end

    local fadeExtra
    if id == "player" or id == "pet" then
        local who = id == "pet" and "your pet's" or "your"
        fadeExtra = { { type = "toggle", key = k("fade.fullHealth"), label = "Only at full health",
            desc = "Fades only while " .. who .. " health is full; comes back as soon as it drops. Show on mouseover still works.",
            disabled = function(get)
                local mode = get(k("fade.mode"))
                return shown(get) or (mode ~= "ooc" and mode ~= "always" and mode ~= "float")
            end } }
    end
    local basic, bars = splitFrame(id, frame, opts.power or opts.powerToggle)
    local groups = {
        basic, bars,
        shellCard(id, k("enabled")),
    }
    if opts.tab then groups[#groups + 1] = tabCard(id, ribbon) end
    groups[#groups + 1] = DaylightUI.Fade.Card(id .. ".fade.", fadeExtra, shown, nil, { noFloat = ns.FLOAT[id] == false })
    groups[#groups + 1] = { label = "Text", items = text }
    local extras = {}
    local needHome, homeDis = "", shown
    if opts.tile then
        local noHomeFn = noHome(k)
        needHome = " Needs the portrait or the name tab."
        homeDis = function(get) return shown(get) or noHomeFn(get) end
    end
    if opts.portrait then
        extras[#extras + 1] = { type = "toggle", key = k("showPvP"), label = "PvP flag",
            desc = "Crossed swords, tinted by faction, while the unit is flagged for PvP." .. needHome, disabled = homeDis }
        extras[#extras + 1] = { type = "slider", key = k("pvpSize"), label = "PvP flag size", min = 0.5, max = 2, step = 0.05, unit = "%",
            desc = "How big the PvP flag is.", disabled = homeDis }
    end
    if opts.marker then
        extras[#extras + 1] = { type = "toggle", key = k("showMarker"), label = "Raid marker",
            desc = "Skull, cross and the rest, shown in the name tab before the name.", disabled = shown }
        extras[#extras + 1] = { type = "slider", key = k("markerSize"), label = "Raid marker size", min = 8, max = 32, step = 1, unit = "px",
            desc = "How big the raid marker is.", disabled = offAny(k("enabled"), k("showMarker")) }
    end
    if opts.crest then
        extras[#extras + 1] = { type = "toggle", key = k("showClassification"), label = "Elite and rare crest",
            desc = "Gold for elites and bosses, silver for rares: a dragon around the portrait, or a small horned-helm crest on the name tab when portraits are off.",
            disabled = shown }
    end
    if opts.portrait then
        extras[#extras + 1] = { type = "toggle", key = k("showLevel"), label = "Level",
            desc = "A small badge at the foot of the portrait" .. (opts.tile and "" or " (or the frame's corner without one)")
                .. ", colored by how hard the unit is for you." .. needHome,
            disabled = homeDis }
        local levelOff = function(get) return homeDis(get) or get(k("showLevel")) == false end
        extras[#extras + 1] = { type = "dropdown", key = k("levelPos"), label = "Level position", values = LEVEL_SPOTS,
            order = LEVEL_ORDER, desc = "Or drag the badge in Design mode.", disabled = levelOff }
        extras[#extras + 1] = { type = "slider", key = k("levelX"), label = "Level left / right", min = -50, max = 50, step = 1,
            desc = "Nudges the level badge sideways. Not while it sits on the portrait.", unit = "px", disabled = function(get) return levelOff(get) or get(k("levelPos")) == "ring" end }
        extras[#extras + 1] = { type = "slider", key = k("levelY"), label = "Level up / down", min = -50, max = 50, step = 1,
            desc = "Nudges the level badge up or down. Not while it sits on the portrait.", unit = "px", disabled = function(get) return levelOff(get) or get(k("levelPos")) == "ring" end }
        extras[#extras + 1] = { type = "toggle", key = k("showLeader"), label = "Leader crown",
            desc = "A crown on top of the portrait ring (or over the name tab) for the party or raid leader.", disabled = shown }
        extras[#extras + 1] = { type = "slider", key = k("leaderSize"), label = "Leader crown size", min = 0.5, max = 2, step = 0.05, unit = "%",
            desc = "How big the leader's crown is.", disabled = shown }
    end
    if opts.combat then
        extras[#extras + 1] = { type = "toggle", key = k("druidMana"), label = "Druid mana in forms",
            desc = "A thin mana strip along the bottom of the power bar while a form hides your mana.", disabled = powerOff }
        local function druidOff(get) return shown(get) or get(k("druidBars.enabled")) ~= true end
        extras[#extras + 1] = { type = "toggle", key = k("druidBars.enabled"), label = "Druid resource bars",
            desc = "Small bars for the druid powers you're not using right now: rage and energy in caster form, mana in bear or cat form. Each shows once you know its form. Move them in unlock mode.",
            disabled = shown }
        extras[#extras + 1] = { type = "slider", key = k("druidBars.width"), label = "Druid bars width", min = 40, max = 300, step = 1, unit = "px",
            desc = "How long each bar is.", disabled = druidOff }
        extras[#extras + 1] = { type = "slider", key = k("druidBars.height"), label = "Druid bars height", min = 3, max = 20, step = 1, unit = "px",
            desc = "How tall each bar is.", disabled = druidOff }
        extras[#extras + 1] = { type = "toggle", key = k("druidBars.showText"), label = "Druid bars numbers",
            desc = "How much of each power you have, on its bar.", disabled = druidOff }
        extras[#extras + 1] = { type = "toggle", key = k("costPreview"), label = "Spell cost preview",
            desc = "While you cast, the power the spell will use is shaded on your power bar.", disabled = powerSpellOff }
        extras[#extras + 1] = { type = "color", key = k("costColor"), label = "Spell cost color",
            desc = "The color of the shaded spell cost on your power bar.",
            disabled = function(get) return powerSpellOff(get) or get(k("costPreview")) ~= true end }
        extras[#extras + 1] = { type = "slider", key = k("costAlpha"), label = "Spell cost opacity",
            desc = "How strongly the spell cost shows on your power bar.", min = 0.1, max = 1, step = 0.05, unit = "%",
            disabled = function(get) return powerSpellOff(get) or get(k("costPreview")) ~= true end }
        extras[#extras + 1] = { type = "dropdown", key = k("regenSweep"), since = "1.5.1.1", label = "Mana regen sweep",
            values = { off = "Off", spark = "Spark", trail = "Soft trail", line = "Draining line" },
            order = { "off", "spark", "trail", "line" },
            desc = "After you cast a spell that costs mana, a light crosses your mana bar for the 5 seconds until your Spirit regen is back. Shows on your player frame and personal display.",
            disabled = powerSpellOff, hidden = function() return not ns.PowerBar.HasMana() end }
        extras[#extras + 1] = { type = "toggle", key = k("showResting"), label = "Resting",
            desc = "Zzz on your portrait ring while you rest in an inn or city.", disabled = shown }
        extras[#extras + 1] = { type = "slider", key = k("restSize"), label = "Resting size", min = 0.5, max = 2, step = 0.05, unit = "%",
            desc = "How big the resting Zzz is.", disabled = shown }
    end
    if opts.combat then
        extras[#extras + 1] = { type = "toggle", key = k("showThreat"), label = "Red ring in combat",
            desc = "Your portrait ring, or your name tab without a portrait, turns red while you're in combat.",
            disabled = shown }
    end
    if opts.groupThreat then
        extras[#extras + 1] = { type = "toggle", key = k("showThreat"), label = "Aggro colors",
            desc = "A member's ring (or name tab without a portrait) turns red while something is attacking them.",
            disabled = shown }
    end
    if opts.threat then
        extras[#extras + 1] = { type = "toggle", key = k("showThreat"), label = "Threat colors",
            desc = "Red while it's attacking you, on the portrait ring or the name tab without a portrait. In a group it goes orange first, as you get close to pulling it.",
            disabled = shown }
    end
    local tagRows = {}
    if opts.threatTag then
        tagRows[#tagRows + 1] = { type = "toggle", key = k("threatTag"), label = "Threat % tag",
            desc = "In a group or with a pet, a small tag on the frame's top inner corner: your threat on it, where 100% means it turns on you. Orange as you get close, red once it's on you.",
            disabled = offAny(k("enabled"), k("showThreat")) }
        local tagOff = offAny(k("enabled"), k("showThreat"), k("threatTag"))
        local notOnFrame = function(get) return tagOff(get) or get(k("threatTagAt")) == "free" end
        tagRows[#tagRows + 1] = { type = "dropdown", key = k("threatTagAt"), label = "Threat tag position",
            values = { frame = "On the frame", free = "On its own (unlock to move)" }, order = { "frame", "free" },
            desc = "On its own, the tag leaves the frame and you can move it anywhere in unlock mode, like near the middle of the screen.",
            disabled = tagOff }
        tagRows[#tagRows + 1] = { type = "slider", key = k("threatTagX"), label = "Threat tag left / right", min = -100, max = 100, step = 1,
            unit = "px", desc = "Nudges the tag sideways. Only while it sits on the frame.", disabled = notOnFrame }
        tagRows[#tagRows + 1] = { type = "slider", key = k("threatTagY"), label = "Threat tag up / down", min = -100, max = 100, step = 1,
            unit = "px", desc = "Nudges the tag up or down. Only while it sits on the frame.", disabled = notOnFrame }
        tagRows[#tagRows + 1] = { type = "slider", key = k("threatTagWidth"), label = "Threat tag width", min = 20, max = 120, step = 1,
            unit = "px", desc = "How wide the tag is.", disabled = tagOff }
        tagRows[#tagRows + 1] = { type = "slider", key = k("threatTagHeight"), label = "Threat tag height", min = 0, max = 40, step = 1,
            unit = "px", desc = "How tall the tag is. 0 matches the name tab.", disabled = tagOff }
        tagRows[#tagRows + 1] = { type = "slider", key = k("threatTagSize"), label = "Threat tag text size", min = 0, max = 30, step = 1,
            desc = "How big the number is. 0 fits it to the tag.", disabled = tagOff }
        tagRows[#tagRows + 1] = DaylightUI.Options.MediaPick("font", k("media.threatFont"), "Threat tag font",
            "The threat number. General uses this frame's health text font.",
            { disabled = tagOff, follows = { slot = ns.UF.MEDIA.target.fonts.health, label = "Health text" } })
        tagRows[#tagRows + 1] = { type = "dropdown", key = k("threatTagColor"), label = "Threat tag color",
            values = { threat = "By threat (orange, then red)", white = "White", accent = "Accent color" },
            order = { "threat", "white", "accent" },
            desc = "The number's color. By threat goes orange as you get close to pulling, red once it's on you.",
            disabled = tagOff }
        tagRows[#tagRows + 1] = { type = "toggle", key = k("threatTagBox"), label = "Threat tag box",
            desc = "The small framed box behind the number. When off, only the number shows.", disabled = tagOff }
        tagRows[#tagRows + 1] = { type = "toggle", key = k("threatTagSlant"), label = "Threat tag angled end",
            desc = "The tag's end is angled like the frame. When off, both ends are straight.", disabled = tagOff }
    end
    if opts.happiness then
        local function happyOff(get) return shown(get) or get(k("happiness")) ~= true end
        extras[#extras + 1] = { type = "toggle", key = k("happiness"), label = "Pet happiness (hunters)",
            desc = "Your pet's mood beside the frame: red while it's unhappy, yellow while content, green while happy. Hover for its damage, loyalty and diet.",
            disabled = shown }
        extras[#extras + 1] = { type = "dropdown", key = k("happinessLook"), label = "Happiness look",
            values = { square = "Color square", icon = "Mood face" }, order = { "square", "icon" },
            desc = "A square filled with the mood's color, or the pet's mood face edged in it.", disabled = happyOff }
        extras[#extras + 1] = { type = "dropdown", key = k("happinessSpot"), label = "Happiness position", values = ns.Spots.LABELS,
            order = ns.Spots.ORDER, desc = "Where on or around the frame it sits.", disabled = happyOff }
        extras[#extras + 1] = { type = "slider", key = k("happinessSize"), label = "Happiness size", min = 8, max = 40, step = 1, unit = "px",
            desc = "How big it is.", disabled = happyOff }
        extras[#extras + 1] = { type = "slider", key = k("happinessX"), label = "Happiness left / right", min = -50, max = 50, step = 1, unit = "px",
            desc = "Nudges it sideways.", disabled = happyOff }
        extras[#extras + 1] = { type = "slider", key = k("happinessY"), label = "Happiness up / down", min = -50, max = 50, step = 1, unit = "px",
            desc = "Nudges it up or down.", disabled = happyOff }
        extras[#extras + 1] = { type = "toggle", key = k("happinessBar"), label = "Color health bar by happiness",
            desc = "The pet's health bar takes the mood color instead: red unhappy, yellow content, green happy. Turn Pet happiness off to have only this.",
            disabled = shown }
    end
    if opts.role then
        extras[#extras + 1] = { type = "toggle", key = k("showRole"), label = "Role icon",
            desc = "Tank, healer or damage, from the role they picked. Nothing shows for an unknown or unset role.",
            disabled = shown }
    end
    if opts.targetMark then
        for _, item in ipairs(targetItems(k, k("enabled"))) do extras[#extras + 1] = item end
    end
    if #extras > 0 then groups[#groups + 1] = { label = "Extras", items = extras } end
    if #tagRows > 0 then groups[#groups + 1] = { label = "Threat % tag", items = tagRows } end
    if opts.auraGroups then
        for _, card in ipairs(auraCards(k, k("enabled"))) do groups[#groups + 1] = card end
    end
    if opts.pets then groups[#groups + 1] = petCard() end
    if opts.tile then
        groups[#groups + 1] = { label = "Dispels", desc = "A debuff you can remove, as tiles show it.",
            items = dispelItems(k, k("enabled"), 32, "frame") }
        groups[#groups + 1] = { label = "Icon positions and sizes",
            desc = "The role, marker and crown ride with the name tab or portrait until you pick a spot for them. The dispel icon sits in a corner.",
            items = iconItems(k, shown, { markerSize = true, leaderPxLabel = "Leader crown pixel",
                leaderPxDesc = "How big the leader's crown is, in pixels. With the name or portrait it fits there until you change this, and Leader crown size scales it." },
                true) }
    end
    if opts.layout then
        table.insert(groups, 1, { label = "Layout", items = {
            growRows(k, "Lines", shown)[1],
            growRows(k, "Lines", shown)[2],
            { type = "slider", key = k("perLine"), label = "Frames per line", min = 1, max = 5, step = 1,
              desc = "At 5 the party is one line. Fewer makes a grid.", disabled = shown },
            { type = "slider", key = k("groupSpacing"), label = "Line spacing", min = 0, max = 80, step = 1,
              desc = "The gap between lines, when there's more than one.", disabled = shown },
            { type = "dropdown", key = k("sortBy"), label = "Sort by", values = SORT_VALUES, order = SORT_ORDER,
              desc = "Group keeps the party's own order.", disabled = shown },
            { type = "toggle", key = k("hideSelf"), invert = true, label = "Show yourself",
              desc = "Your own frame sits with the party's. When off, only the rest of the party shows.", disabled = shown },
            { type = "toggle", key = k("showSolo"), label = "Show when alone",
              desc = "Your own frame shows here even when you're not in a group.", disabled = shown },
        } })
    end
    if opts.auras then
        for _, g in ipairs(opts.auras) do groups[#groups + 1] = g end
    end
    if ns.Texts.FRAMES[id] then
        for _, card in ipairs(extraTextCards(id, k("enabled"))) do groups[#groups + 1] = card end
    end
    if opts.auraGroups then
        for _, card in ipairs(extraAuraCards(id, k("enabled"))) do groups[#groups + 1] = card end
    end
    -- The page's "Test frame" switch shows just this frame (not for the player,
    -- which is always real). Its live sample sits above its settings.
    local preview = id ~= "player" and { id } or nil
    groups[#groups + 1] = copyCard(id)
    return { id = id, label = label, desc = desc, groups = tabbed(groups), preview = preview,
             sample = function(parent) return ns.PageSample.New(id, parent) end }
end

-- The cast bar cards: where each bar sits (CastBar.AT) and what grays out
-- there. ownSize: a bar of its own (not inside the frame, not hung under it).
local CB = ns.CastBar
local function atChoice(unit, desc)
    local values = {}
    for _, v in ipairs(CB.AT[unit]) do values[v] = CB.AT_LABELS[v] end
    if unit == "player" then values.below = "Under the frame (slides out)" end
    if unit == "party" then values.free = "Detached, beside the frame" end
    -- In Ribbon the frame's power is a thin line, and with power bars off there's
    -- none, so no cast can go inside it. A bar set to sit there sits below
    -- instead (CB.At).
    local outsideOrder = {}
    for _, v in ipairs(CB.AT[unit]) do
        if v ~= "power" then outsideOrder[#outsideOrder + 1] = v end
    end
    local function outside()
        local cfg = liveGet(unit)
        return UF.StyleOf(cfg) == "ribbon" or not UF.ShowsPower(cfg)
    end
    return { type = "dropdown", key = unit .. "Castbar.at", since = "1.5.1", label = "Position", values = values, order = CB.AT[unit],
             choices = function()
                 if outside() then return values, outsideOrder end
                 return values, CB.AT[unit]
             end,
             shownAs = function(v) if v == "power" and outside() then return values.below or values.slide end end,
             desc = desc,
             disabled = function(get)
                 return get(unit .. "Castbar.enabled") ~= true
                     or (unit == "player" and get("personal.enabled") == true and get("personal.castbar") == true)
             end }
end
local function atOf(get, unit) return CB.At(unit, { at = get(unit .. "Castbar.at") }) end
local function notOwnSize(unit)
    local inside = unit == "player" and "below" or "power"
    return function(get) return get(unit .. "Castbar.enabled") ~= true or atOf(get, unit) == inside end
end
local function notInside(unit)
    return function(get) return get(unit .. "Castbar.enabled") ~= true or atOf(get, unit) ~= "power" end
end
-- A nudge for a bar above or below its frame: axis "x" (sideways) or "y".
local function nudge(unit, axis)
    local x = axis == "x"
    return { type = "slider", key = unit .. "Castbar." .. axis, label = x and "Cast bar left / right" or "Cast bar up / down",
             min = x and -200 or -100, max = x and 200 or 100, step = 1, unit = "px",
             desc = x and "Above or below the frame: moves the bar sideways from the middle."
                 or "Above or below the frame: moves the bar up or down.",
             disabled = function(get)
                 local at = atOf(get, unit)
                 if not x and at == "middle" then return get(unit .. "Castbar.enabled") ~= true end
                 return get(unit .. "Castbar.enabled") ~= true or not (at == "above" or (at == "below" and unit ~= "player"))
             end }
end
-- Above or below the frame, the bar can take the frame's width (fitFrame).
local function fitRow(unit)
    return { type = "toggle", key = unit .. "Castbar.fitFrame", label = "Match the frame's width",
             desc = "Above or below the frame, the bar is as wide as the frame. Off: the Width below.",
             disabled = function(get)
                 local at = atOf(get, unit)
                 return get(unit .. "Castbar.enabled") ~= true or not (at == "above" or at == "below")
             end }
end
-- Hung under the frame ("slide"), a bar takes the frame's width and angle.
local function notOwnBar(unit)
    local notOwn = notOwnSize(unit)
    return function(get) return notOwn(get) or atOf(get, unit) == "slide" end
end
local function notOwnWidth(unit)
    local notOwn = notOwnBar(unit)
    return function(get)
        local at = atOf(get, unit)
        return notOwn(get) or ((at == "above" or at == "below") and get(unit .. "Castbar.fitFrame") ~= false)
    end
end
local attached = notOwnSize("player")
-- Between the frames, the bar takes the gap's width, has no icon, and fills left to right.
local function notMiddleOwn(get) return attached(get) or atOf(get, "player") == "middle" end

-- A raid page: Raid 10, 20 or 40 (Raid.lua's setups by raid size).
local RAID_PAGE_DESC = {
    [10] = "Small tiles for a raid of up to 10: one column per group, left to right. Show, fade, textures and fonts here count for every raid size; your party has its own page.",
    [20] = "The raid frames for 11 to 20 players. Show, fade, textures and fonts are on the Raid 10 page.",
    [40] = "The raid frames for 21 to 40 players. Show, fade, textures and fonts are on the Raid 10 page.",
}

local function raidPage(size)
    local frameCard, barsCard = splitFrame("raid", {
        { type = "toggle", key = "raid.enabled", label = "Show raid frames", desc = "Replaces the game's raid frames while you're in a raid." },
        { type = "toggle", key = "raid.showInParty", label = "Use raid frames in a party",
          desc = "Shows these raid frames in a party too, in place of the party frames.", disabled = off("raid.enabled") },
        growRows(function(f) return ns.Raid.MapKey("raid." .. f, size) end, "Groups", off("raid.enabled"),
                 function(f) return "raid." .. f end)[1],
        growRows(function(f) return ns.Raid.MapKey("raid." .. f, size) end, "Groups", off("raid.enabled"),
                 function(f) return "raid." .. f end)[2],
        { type = "dropdown", key = "raid.sortBy", label = "Sort tiles by",
          values = RAID_SORT_VALUES, order = RAID_SORT_ORDER, desc = SORT_DESC, disabled = off("raid.enabled") },
        { type = "slider", key = "raid.groups", label = "Show groups up to", min = 1, max = 8, step = 1,
          desc = "Hides the higher raid groups, e.g. 4 for a 20-player raid.", disabled = off("raid.enabled") },
        { type = "slider", key = "raid.width", label = "Width", min = 40, max = 160, step = 1,
          desc = "How wide each raid tile is.", disabled = off("raid.enabled") },
        { type = "slider", key = "raid.height", label = "Height", min = 14, max = 80, step = 1,
          desc = "How tall each raid tile is.", disabled = off("raid.enabled") },
        strataRow("raid.strata", "Frame layer", "The layer the raid frames draw in, for every raid size.", off("raid.enabled")),
        barRows("raid.media.health", "the raid tiles' health bars", "Health bar", off("raid.enabled"))[1],
        barRows("raid.media.health", "the raid tiles' health bars", "Health bar", off("raid.enabled"))[2],
        healthColorRows("raid", off("raid.enabled"))[1],
        healthColorRows("raid", off("raid.enabled"))[2],
        { type = "slider", key = "raid.spacing", label = "Spacing", min = 0, max = 20, step = 1,
          desc = "Gap between members of a group.", disabled = off("raid.enabled") },
        { type = "slider", key = "raid.groupSpacing", label = "Group spacing", min = 0, max = 30, step = 1,
          desc = "Gap between groups.", disabled = off("raid.enabled") },
        { type = "slider", key = "raid.perLine", label = "Tiles per line", min = 1, max = 40, step = 1,
          desc = "At 5, each group gets its own line. Any other number lists everyone in order and wraps, up to 40 in one line.",
          disabled = off("raid.enabled") },
        { type = "toggle", key = "raid.hideSelf", invert = true, label = "Show yourself",
          desc = "Your own tile sits with the raid's. When off, only the rest of the raid shows.", disabled = off("raid.enabled") },
        { type = "toggle", key = "raid.slant", label = "Angled end",
          desc = "Cuts each tile's right end at an angle, like your own frame; the bars follow it.",
          disabled = off("raid.enabled") },
        { type = "toggle", key = "raid.fillVertical", label = "Fill upward",
          desc = "The health bar fills bottom to top instead of across.", disabled = off("raid.enabled") },
        { type = "toggle", key = "raid.showPower", label = "Power bar",
          desc = "A thin mana, rage or energy bar at the foot of each tile.", disabled = off("raid.enabled") },
        { type = "slider", key = "raid.powerHeight", label = "Power bar height", min = 2, max = 20, step = 1,
          desc = "How tall each tile's power bar is.", disabled = offAny("raid.enabled", "raid.showPower") },
        barRows("raid.media.power", "the raid tiles' power bars", "Power bar", offAny("raid.enabled", "raid.showPower"))[1],
        barRows("raid.media.power", "the raid tiles' power bars", "Power bar", offAny("raid.enabled", "raid.showPower"))[2],
        powerColorRows("raid", offAny("raid.enabled", "raid.showPower"))[1],
        powerColorRows("raid", offAny("raid.enabled", "raid.showPower"))[2],
    }, true)
    return { id = size == 10 and "raid" or "raid" .. size, label = "Raid " .. size, preview = { "raid" },
      mapKey = function(key) return ns.Raid.MapKey(key, size) end, locked = raidLocked(size),
      onShow = function() ns.Raid.SetEditing(size) end,
      sample = function(parent) return ns.PageSample.New("raid", parent, size) end, desc = RAID_PAGE_DESC[size],
      -- While following Raid 10, only the Raid size card shows (Options.IsHidden).
      hideLocked = size ~= 10,
      groups = tabbed(cat(size ~= 10 and { raidSizeCard(size) } or {}, forRaidSize(cat({
        looksCard("raid"),
        frameCard, barsCard,
        shellCard("raid", "raid.enabled"),
        -- Shared by every size, so only on Raid 10 (false leaves it out).
        size == 10 and DaylightUI.Fade.Card("raid.fade.", nil, off("raid.enabled"), "Raid"),
        { label = "Text", items = cat({
            { type = "toggle", key = "raid.showName", label = "Name",
              desc = "Each member's name on their tile.", disabled = off("raid.enabled") },
            lastNames("raid"),
            { type = "dropdown", key = "raid.nameColor", label = "Name color", values = NAME_COLORS, order = NAME_COLOR_ORDER,
              desc = "The raid tiles' own name color. Same as the Colors page follows the name color every frame shares.",
              disabled = offAny("raid.enabled", "raid.showName") },
            { type = "color", key = "raid.nameCustom", label = "Custom name color", hidden = notCustom("raid.nameColor"),
              desc = "The names' color when Name color is Custom.", disabled = offAny("raid.enabled", "raid.showName") },
            { type = "slider", key = "raid.nameLimitLen", label = "Max name length", min = 0, max = 24, step = 1,
              desc = "Letters shown before a long name is shortened. 0 shows names in full. In instances some names can't be shortened and show in full.",
              disabled = offAny("raid.enabled", "raid.showName") },
        }, nameItems(function(s) return "raid." .. s end, offAny("raid.enabled", "raid.showName")), {
            fontRow("raid.media.nameFont", "Name font", "The raid tiles' names", offAny("raid.enabled", "raid.showName")),
            { type = "toggle", key = "raid.showPercent", label = "Health text",
              desc = "Each member's health written on their tile.", disabled = off("raid.enabled") },
            { type = "toggle", key = "raid.hideFullHealth", invert = true, label = "Show health text at full",
              desc = "The health text shows at full health too. When off, it disappears while the unit is at full.",
              disabled = offAny("raid.enabled", "raid.showPercent") },
            { type = "dropdown", key = "raid.healthText", label = "Health text format",
              values = UF.HEALTH_FORMATS, order = UF.HEALTH_FORMAT_ORDER,
              desc = "How the tiles' health text is written. Missing health shows nothing while the member is at full.",
              disabled = offAny("raid.enabled", "raid.showPercent") },
            { type = "toggle", key = "raid.percentSign", label = "Show % sign",
              desc = "62% rather than 62, when the health text shows a percent.", disabled = offAny("raid.enabled", "raid.showPercent") },
            fontRow("raid.media.healthFont", "Health text font", "The raid tiles' health text", offAny("raid.enabled", "raid.showPercent")),
            { type = "slider", key = "raidText.name", label = "Name size", min = 6, max = 20, step = 1,
              desc = "How big the names on the tiles are.", disabled = off("raid.enabled") },
            { type = "slider", key = "raidText.percent", label = "Health text size", min = 6, max = 20, step = 1,
              desc = "How big the health text on the tiles is.", disabled = off("raid.enabled") },
            { type = "slider", key = "raid.healthTextX", label = "Health text left / right", min = -50, max = 50, step = 1,
              desc = "Nudges the health text sideways from its place.",
              unit = "px", disabled = offAny("raid.enabled", "raid.showPercent") },
            { type = "slider", key = "raid.healthTextY", label = "Health text up / down", min = -50, max = 50, step = 1,
              desc = "Nudges the health text up or down from its place.",
              unit = "px", disabled = offAny("raid.enabled", "raid.showPercent") },
        }) },
        { label = "Extras", items = cat({
            { type = "toggle", key = "raid.predictHeals", label = "Incoming heals",
              desc = "Heals on their way, as a soft green stretch past the health.", disabled = off("raid.enabled") },
            { type = "toggle", key = "raid.predictAbsorbs", label = "Absorbs",
              desc = "Damage shields, as a pale stretch after any incoming heals.", disabled = off("raid.enabled") },
            { type = "toggle", key = "raid.showMarker", label = "Raid marker",
              desc = "Skull, cross and the rest, on the tile of a marked member.", disabled = off("raid.enabled") },
            { type = "toggle", key = "raid.showLeader", label = "Leader crown",
              desc = "A small crown on the raid leader's tile.", disabled = off("raid.enabled") },
        }, dispelItems(function(s) return "raid." .. s end, "raid.enabled", 24, "tile"), {
            { type = "toggle", key = "raid.showThreat", label = "Aggro colors",
              desc = "A member's border turns red while something is attacking them.", disabled = off("raid.enabled") },
            { type = "toggle", key = "raid.showRole", label = "Role icon",
              desc = "Tank, healer or damage, from the role they picked. Nothing shows for an unknown or unset role.",
              disabled = off("raid.enabled") },
        }, targetItems(function(s) return "raid." .. s end, "raid.enabled")) },
        size == 10 and { label = "Leader tools", items = {
            { type = "toggle", key = "leader.enabled", label = "Leader tools", anySize = true,
              desc = "A small crown tab that opens ready check, role check, a pull timer, and target and world markers. It shows while you lead the group or assist in a raid. When off, these are only in the game's slash commands.",
              disabled = function(get) return get("raid.enabled") ~= true and get("party.enabled") ~= true end },
            { type = "dropdown", key = "leader.show", label = "Show leader tools", anySize = true,
              values = LEADER_SHOW, order = { "lead", "tank", "party" },
              desc = "Who else gets the crown tab in a party, for the markers: the party's tank, or everyone. Ready check and the pull timer stay with the leader. In a raid only the leader and assists can mark.",
              disabled = function(get) return get("leader.enabled") ~= true or (get("raid.enabled") ~= true and get("party.enabled") ~= true) end },
            { type = "toggle", key = "pull.enabled", label = "Pull timer", anySize = true,
              desc = "A big number in the middle of your screen counts down any pull your group starts, in place of the game's bar. Move it in unlock mode. In a dungeon or raid the game may keep its own bar for a countdown someone else starts." },
        } },
    }, auraCards(function(s) return "raid." .. s end, "raid.enabled"), {
        { label = "Icon positions and sizes", desc = "Where the role, marker, crown and dispel icons sit on a tile.",
          items = iconItems(function(key) return "raid." .. key end, off("raid.enabled")) },
    }, extraTextCards("raid", "raid.enabled"), extraAuraCards("raid", "raid.enabled")), size),
        { copyCard(size == 10 and "raid" or "raid" .. size,
                   size ~= 10 and function() return ns.Raid.Locked(size) end or nil) })) }
end

ns.OPTIONS = { pages = {
    framePage("player", "Player", "Your own frame.",
        { power = true, powerToggle = true, powerFree = true, powerPos = true, tab = true, healthText = true, textPos = true, big = true, portrait = true, dragon = true, combat = true, auras = PLAYER_AURA_GROUPS,
          slantDesc = "Cuts the right end at an angle; the bars and an attached cast bar follow it." }),
    framePage("target", "Target", "Mirrors the player frame, with raid markers, the elite crest, and its buffs and debuffs.",
        { power = true, powerToggle = true, powerPos = true, tab = true, healthText = true, textPos = true, big = true, marker = true, crest = true, portrait = true, threat = true, threatTag = true, auras = TARGET_AURA_GROUPS, dots = true,
          slantDesc = "Cuts the left end at an angle; the bars follow it." }),
    framePage("focus", "Focus", "The unit you set as focus.",
        { power = true, powerToggle = true, powerPos = true, tab = true, healthText = true, textPos = true, marker = true, portrait = true, threat = true }),
    framePage("party", "Party", "Your party: bars like your own frame, or square tiles. Set how they line up, what shows, and move them as one in unlock mode.",
        { power = true, powerPos = true, tab = true, healthText = true, textPos = true, big = true, marker = true, portrait = true, groupThreat = true,
          spacing = true, auraGroups = true, role = true, targetMark = true, pets = true,
          layout = true, tile = true, powerToggle = true, minWidth = 20, maxHeight = 120, strataWhat = "The layer the party frames draw in.", slantDesc = "Cuts the right end at an angle; the bars follow it." }),
    raidPage(10), raidPage(20), raidPage(40),
    framePage("arena", "PvP Frames", "Enemy players carrying a flag in a battleground, one frame each. Right-click one to set it as your focus.",
        { power = true, powerToggle = true, powerPos = true, tab = true, healthText = true, textPos = true, marker = true, portrait = true, spacing = true,
          strataWhat = "The layer the PvP frames draw in.",
          showLabel = "Show the PvP frames", showDesc = "Turn the PvP frames on or off. When off, the game shows its own after a reload." }),
    framePage("targettarget", "Target of Target", "Who your target is looking at.", { healthText = true, textPos = true, flip = true,
        power = true, powerToggle = true, powerPos = true }),
    framePage("focustarget", "Focus Target", "Who your focus is looking at.", { healthText = true, textPos = true,
        power = true, powerToggle = true, powerPos = true }),
    framePage("pet", "Pet", "Your pet or minion.", { happiness = true, power = true, powerToggle = true, powerPos = true, healthText = true, textPos = true,
        tab = true, small = true }),

    { id = "colors", label = "Colors", desc = "The bars' and names' colors on every unit frame.", groups = {
        { label = "Health", items = {
            { type = "dropdown", key = "colors.health", label = "Health bar color",
              values = { class = "Class and reaction", classGradient = "Class gradient", gradient = "By health (green to red)",
                         custom = "One color", dark = "Dark (missing health colored)" },
              order = { "class", "classGradient", "gradient", "custom", "dark" },
              desc = "Class and reaction: players by class color, others by friendly, neutral or hostile. Dark: a near-black bar with the missing health in the class or reaction color." },
            { type = "color", key = "colors.healthColor", label = "Custom health color",
              desc = "Every health bar's color when Health bar color is One color.", disabled = function(get) return get("colors.health") ~= "custom" end },
            { type = "toggle", key = "colors.mirrorGradient", label = "Mirror the target's gradient",
              desc = "The target's and target of target's class and power gradients run the other way, so they mirror yours. Only for a horizontal gradient.",
              disabled = function(get) return get("colors.health") ~= "classGradient" and get("colors.power") ~= "gradient" end },
            { type = "slider", key = "colors.backBrightness", label = "Missing health brightness", min = 0, max = 1,
              step = 0.05, unit = "%", desc = "How much color the empty part of a bar keeps.",
              disabled = function(get) return get("colors.backMode") == "custom" end },
            { type = "dropdown", key = "colors.backMode", label = "Missing health color",
              values = { dim = "Dimmed bar color", custom = "Custom color" }, order = { "dim", "custom" },
              desc = "The empty part of every health bar: a dimmed copy of the bar's own color, or one you pick." },
            { type = "color", key = "colors.backColor", label = "Custom missing health color",
              desc = "The empty part's color when Missing health color is Custom color.", disabled = function(get) return get("colors.backMode") ~= "custom" end },
            { type = "slider", key = "colors.backAlpha", label = "Missing health opacity", min = 0, max = 1,
              step = 0.05, unit = "%",
              desc = "How solid the empty part of every health and power bar is. Lower lets the world show through it, like the game's own frames." },
            { type = "color", key = "colors.dotTint", label = "DoT damage left color", alpha = true,
              desc = "The shade over the health your damage over time spells will still take, on the target and on enemy nameplates." },
        } },
        { label = "Dead, offline and NPCs", desc = "The bar's color for dead and offline players and tapped NPCs, and for NPCs by how they feel about you.", items = {
            { type = "color", key = "colors.dead", label = "Dead", desc = "The health bar's color for a dead unit." },
            { type = "color", key = "colors.offline", label = "Offline", desc = "The health bar's color for a player who went offline." },
            { type = "color", key = "colors.tapped", label = "Tapped by someone else",
              desc = "The health bar's color for an NPC someone else tagged first." },
            { type = "color", key = "colors.hostile", label = "Hostile", desc = "The health bar's color for an NPC that attacks you." },
            { type = "color", key = "colors.neutral", label = "Neutral", desc = "The health bar's color for an NPC that leaves you alone until you hit it." },
            { type = "color", key = "colors.friendly", label = "Friendly", desc = "The health bar's color for a friendly NPC." },
        } },
        { label = "Dispel types", desc = "The border of a debuff you can dispel, and the raid tile's dispel icon. Debuffs already on screen change after /reload.", items = {
            { type = "color", key = "colors.dispelMagic", label = "Magic", desc = "The color of a Magic debuff's border and dispel icon." },
            { type = "color", key = "colors.dispelCurse", label = "Curse", desc = "The color of a Curse debuff's border and dispel icon." },
            { type = "color", key = "colors.dispelDisease", label = "Disease", desc = "The color of a Disease debuff's border and dispel icon." },
            { type = "color", key = "colors.dispelPoison", label = "Poison", desc = "The color of a Poison debuff's border and dispel icon." },
        } },
        { label = "Power", items = {
            { type = "dropdown", key = "colors.power", label = "Power bar color",
              values = { type = "By power type", gradient = "Power gradient", custom = "One color" },
              order = { "type", "gradient", "custom" },
              desc = "Power gradient: each power type's pair from the Gradients page (mana, rage, energy, focus)." },
            { type = "color", key = "colors.powerColor", label = "Custom power color",
              desc = "Every power bar's color when Power bar color is One color.", disabled = function(get) return get("colors.power") ~= "custom" end },
        } },
        { label = "Aggro", desc = "The ring (or name tab, or raid tile) that turns red while something is attacking the unit; an elite's dragon keeps its color, its eyes catch fire.", items = {
            { type = "dropdown", key = "colors.threat", label = "Aggro color",
              values = { health = "Same red as health bars", custom = "Custom color" }, order = { "health", "custom" },
              desc = "The red of a ring, name tab or raid tile while something is attacking the unit, or a color you pick." },
            { type = "color", key = "colors.threatColor", label = "Custom aggro color",
              desc = "The aggro color when Aggro color is Custom color.", disabled = function(get) return get("colors.threat") ~= "custom" end },
            { type = "color", key = "colors.threatWarn", label = "Close to pulling",
              desc = "In a group or with a pet, the target's ring (and threat tag) turns this color as you get close to pulling it." },
        } },
        { label = "Heals and shields", desc = "The bars that hang off the end of the health for incoming heals and absorb shields. An overshield (a shield bigger than the health missing) follows the shield.", items = {
            { type = "color", key = "colors.healColor", label = "Incoming heals",
              desc = "The color of the stretch past the health for heals on their way." },
            { type = "color", key = "colors.absorbColor", label = "Absorb shields",
              desc = "The color of the stretch for damage shields." },
            { type = "dropdown", key = "colors.absorbStyle", label = "Shield texture", fallback = "stripes",
              choices = function() return shieldTextures() end,
              desc = "Stripes say \"shield\" at a glance. Plain is a flat fill; a shared-media bar uses that bar's look." },
            { type = "toggle", key = "colors.overshield", label = "Overshield",
              desc = "When a shield is bigger than the health missing, the part that doesn't fit runs back over the health with a bright line. When off, only the shield that fits shows." },
            { type = "toggle", key = "colors.overshieldReverse", label = "Overshield from the other end",
              desc = "The overshield grows from where the health starts instead of from the frame's end.",
              disabled = function(get) return get("colors.overshield") == false end },
            { type = "dropdown", key = "colors.overshieldPaint", label = "Overshield color",
              values = { shield = "Same as shields", custom = "Custom color" }, order = { "shield", "custom" },
              desc = "The overshield in the absorb shields' color, or a color of its own.",
              disabled = function(get) return get("colors.overshield") == false end },
            { type = "color", key = "colors.overshieldColor", label = "Custom overshield color",
              desc = "The overshield's color when Overshield color is Custom color.",
              disabled = function(get) return get("colors.overshield") == false or get("colors.overshieldPaint") ~= "custom" end },
            { type = "dropdown", key = "colors.overshieldStyle", label = "Overshield texture", fallback = "shield",
              choices = function() return shieldTextures(true) end,
              desc = "The overshield's look: the same as the shield texture, or its own.",
              disabled = function(get) return get("colors.overshield") == false end },
        } },
        { label = "Names", items = {
            { type = "dropdown", key = "colors.name", label = "Name color",
              values = { white = "White", class = "Class and reaction", classGradient = "Class gradient" },
              order = { "white", "class", "classGradient" },
              desc = "The names on every unit frame, unless a frame picks its own. Class and reaction: players by class color, others by friendly, neutral or hostile." },
        } },
    } },

    { id = "castbars", label = "Cast Bars", preview = { "castbars", "target", "focus", "party" }, desc = "Spell casts for you, your target, focus and party.", groups = {
        { label = "Player cast bar", items = {
            { type = "toggle", key = "playerCastbar.enabled", label = "Show your cast bar",
              desc = "Replaces the game's own cast bar." },
            atChoice("player", "Under the frame it continues the frame's angle and slides out as you cast. Between your frame and the target's it fills the gap, both ends angled like the frames beside it, with the swing timers fanning out under it. Above the frame or on its own it has its own size."),
            { type = "dropdown", key = "playerCastbar.from", label = "Slides out from",
              values = { frame = "The player frame", power = "The power bar" }, order = { "frame", "power" },
              desc = "With the power bar on its own (Player > Power bar), the cast bar and the swing timer under it can slide out from under the power bar instead of the frame.",
              disabled = function(get)
                  return get("playerCastbar.enabled") ~= true or get("playerCastbar.at") ~= "below" or get("player.powerAt") ~= "free"
              end },
            nudge("player", "x"),
            nudge("player", "y"),
            { type = "slider", key = "playerCastbar.height", label = "Height", min = 8, max = 40, step = 1,
              desc = "How tall your cast bar is.", disabled = off("playerCastbar.enabled") },
            barRows("playerCastbar.media.bar", "your cast bar", "Cast bar", off("playerCastbar.enabled"))[1],
            barRows("playerCastbar.media.bar", "your cast bar", "Cast bar", off("playerCastbar.enabled"))[2],
            fontRow("playerCastbar.media.font", "Cast bar font", "The spell name and time on your cast bar", off("playerCastbar.enabled")),
            { type = "toggle", key = "playerCastbar.showIcon", label = "Spell icon",
              desc = "Not while under the frame (the portrait ring covers that spot) or between the frames.", disabled = notMiddleOwn },
            { type = "slider", key = "playerCastbar.width", label = "Width", min = 80, max = 500, step = 1,
              desc = "Not while under the frame or between the frames: there it fills the space it has.", disabled = notMiddleOwn },
            { type = "toggle", key = "playerCastbar.slant", label = "Angled end",
              desc = "Under the frame, it continues the frame's angle. When off, its end is straight.",
              disabled = off("playerCastbar.enabled") },
            { type = "slider", key = "playerCastbar.textSize", label = "Cast bar text size", min = 6, max = 24, step = 1,
              desc = "The spell name and time on your cast bar.", disabled = off("playerCastbar.enabled") },
            { type = "toggle", key = "playerCastbar.reverseFill", label = "Fill right to left",
              desc = "Not while under the frame or between the frames.", disabled = notMiddleOwn },
            strataRow("playerCastbar.strata", "Cast bar layer", "The layer your cast bar draws in.",
                function(get) return notMiddleOwn(get) or atOf(get, "player") == "personal" end,
                " Under the frame, between the frames or under the personal display, it draws with the frame instead."),
        } },
        shellCard("playerCastbar", "playerCastbar.enabled", true),
        { label = "Target cast bar", items = {
            { type = "toggle", key = "targetCastbar.enabled", label = "Show the target cast bar",
              desc = "Your target's casts, while they last." },
            atChoice("target", "Inside the frame it covers the power bar, as wide as it (in the Ribbon style it sits below the frame instead). Above, below or on its own it's a bar you size here; on its own you move it in unlock mode. Under the frame it slides out during a cast, and the buffs below keep room for it."),
            nudge("target", "x"),
            nudge("target", "y"),
            fitRow("target"),
            { type = "slider", key = "targetCastbar.width", label = "Width", min = 80, max = 500, step = 1,
              desc = "How wide your target's cast bar is. Not inside the frame, or while it matches the frame's width.",
              disabled = notOwnWidth("target") },
            { type = "slider", key = "targetCastbar.height", label = "Height", min = 8, max = 40, step = 1,
              desc = "How tall your target's cast bar is. Not inside the frame, where it takes the power bar's place.",
              disabled = notOwnSize("target") },
            barRows("targetCastbar.media.bar", "your target's cast bar", "Cast bar", off("targetCastbar.enabled"))[1],
            barRows("targetCastbar.media.bar", "your target's cast bar", "Cast bar", off("targetCastbar.enabled"))[2],
            fontRow("targetCastbar.media.font", "Cast bar font", "The spell name and time on your target's cast bar", off("targetCastbar.enabled")),
            { type = "toggle", key = "targetCastbar.showIcon", label = "Spell icon",
              desc = "The spell's icon at the end of your target's cast bar. Not inside the frame or sliding out under it.",
              disabled = notOwnBar("target") },
            { type = "toggle", key = "targetCastbar.slant", label = "Angled end",
              desc = "Cuts the end of your target's cast bar at an angle. When off, its end is straight. Not inside the frame or sliding out under it.",
              disabled = notOwnBar("target") },
            { type = "slider", key = "targetCastbar.textSize", label = "Target cast bar text size", min = 6, max = 24, step = 1,
              desc = "The spell name and time on your target's cast bar. Not inside the frame: there it's Text size inside the frame.",
              disabled = notOwnSize("target") },
            { type = "toggle", key = "targetCastbar.reverseFill", label = "Fill right to left",
              desc = "Your target's cast bar fills from the right. Not inside the frame or sliding out under it.",
              disabled = notOwnBar("target") },
            { type = "slider", key = "targetCastbar.insideTextSize", label = "Text size inside the frame", min = 0, max = 20, step = 1,
              desc = "The spell name and timer while the bar sits inside the target frame, even past the power bar's height. 0 sizes them to fit the power bar.",
              disabled = notInside("target") },
            { type = "slider", key = "targetCastbar.insideTextX", label = "Text left / right", min = -100, max = 100, step = 1, unit = "px",
              desc = "Moves the spell name and timer sideways while the bar sits inside the target frame.",
              disabled = notInside("target") },
            { type = "slider", key = "targetCastbar.insideTextY", label = "Text up / down", min = -40, max = 40, step = 1, unit = "px",
              desc = "Moves the spell name and timer up or down while the bar sits inside the target frame. They can sit outside the bar.",
              disabled = notInside("target") },
            { type = "color", key = "targetCastbar.textColor", label = "Text color",
              desc = "The spell name and timer on the target's cast bar.",
              disabled = off("targetCastbar.enabled") },
            strataRow("targetCastbar.strata", "Target cast bar layer", "The layer your target's cast bar draws in.",
                notOwnBar("target"), " Inside the frame or sliding out under it, it draws with the frame instead."),
        } },
        { label = "Focus cast bar", items = {
            { type = "toggle", key = "focusCastbar.enabled", label = "Show the focus cast bar",
              desc = "Your focus's casts, while they last. It uses the target cast bar's colors." },
            atChoice("focus", "Inside the frame it covers the power bar, as wide as it (in the Ribbon style it sits below the frame instead). Above, below or on its own it's a bar you size here; on its own you move it in unlock mode."),
            nudge("focus", "x"),
            nudge("focus", "y"),
            fitRow("focus"),
            { type = "slider", key = "focusCastbar.width", label = "Width", min = 80, max = 500, step = 1,
              desc = "How wide your focus's cast bar is. Not inside the frame, or while it matches the frame's width.",
              disabled = notOwnWidth("focus") },
            { type = "slider", key = "focusCastbar.height", label = "Height", min = 8, max = 40, step = 1,
              desc = "How tall your focus's cast bar is. Not inside the frame, where it takes the power bar's place.",
              disabled = notOwnSize("focus") },
            barRows("focusCastbar.media.bar", "your focus's cast bar", "Cast bar", off("focusCastbar.enabled"))[1],
            barRows("focusCastbar.media.bar", "your focus's cast bar", "Cast bar", off("focusCastbar.enabled"))[2],
            fontRow("focusCastbar.media.font", "Cast bar font", "The spell name and time on your focus's cast bar", off("focusCastbar.enabled")),
            { type = "toggle", key = "focusCastbar.showIcon", label = "Spell icon",
              desc = "The spell's icon at the end of your focus's cast bar. Not while it sits inside the frame.",
              disabled = notOwnSize("focus") },
            { type = "toggle", key = "focusCastbar.slant", label = "Angled end",
              desc = "Cuts the end of your focus's cast bar at an angle. When off, its end is straight. Not while it sits inside the frame.",
              disabled = notOwnSize("focus") },
            { type = "slider", key = "focusCastbar.textSize", label = "Focus cast bar text size", min = 6, max = 24, step = 1,
              desc = "The spell name and time on your focus's cast bar. Inside the frame it's kept small enough for the power bar.",
              disabled = off("focusCastbar.enabled") },
            { type = "toggle", key = "focusCastbar.reverseFill", label = "Fill right to left",
              desc = "Your focus's cast bar fills from the right. Not while it sits inside the frame.",
              disabled = notOwnSize("focus") },
            strataRow("focusCastbar.strata", "Focus cast bar layer", "The layer your focus's cast bar draws in.",
                notOwnSize("focus"), " Inside the frame, it draws with the frame instead."),
        } },
        { label = "Party cast bars", items = {
            { type = "toggle", key = "partyCastbar.enabled", label = "Show party cast bars",
              desc = "Each party member's casts on their own frame, while they last. They use the target cast bar's colors." },
            atChoice("party", "Inside the frame it covers the power bar (in the Ribbon style, or with power bars off, it slides out under the frame instead). Under the frame it slides out during a cast: give it room with the party's spacing. Detached, it's a bar you size here, beside each frame."),
            { type = "dropdown", key = "partyCastbar.spot", label = "Side", values = ns.PartyCasts.SPOTS, order = ns.PartyCasts.SPOT_ORDER,
              desc = "Which side of each party frame a detached cast bar sits on.", disabled = notOwnBar("party") },
            { type = "slider", key = "partyCastbar.x", label = "Cast bar left / right", min = -200, max = 200, step = 1, unit = "px",
              desc = "Moves the detached cast bars sideways from their side.", disabled = notOwnBar("party") },
            { type = "slider", key = "partyCastbar.y", label = "Cast bar up / down", min = -100, max = 100, step = 1, unit = "px",
              desc = "Moves the detached cast bars up or down from their side.", disabled = notOwnBar("party") },
            { type = "slider", key = "partyCastbar.width", label = "Width", min = 40, max = 400, step = 1,
              desc = "How wide each detached cast bar is. Under the frame it matches the frame's width.",
              disabled = notOwnBar("party") },
            { type = "slider", key = "partyCastbar.height", label = "Height", min = 6, max = 40, step = 1,
              desc = "How tall each party cast bar is. Not inside the frame, where it takes the power bar's place.",
              disabled = notOwnSize("party") },
            barRows("partyCastbar.media.bar", "the party's cast bars", "Cast bar", off("partyCastbar.enabled"))[1],
            barRows("partyCastbar.media.bar", "the party's cast bars", "Cast bar", off("partyCastbar.enabled"))[2],
            fontRow("partyCastbar.media.font", "Cast bar font", "The spell name and time on the party's cast bars", off("partyCastbar.enabled")),
            { type = "toggle", key = "partyCastbar.showIcon", label = "Spell icon",
              desc = "The spell's icon at the end of each detached cast bar.", disabled = notOwnBar("party") },
            { type = "toggle", key = "partyCastbar.slant", label = "Angled end",
              desc = "Cuts the end of each detached cast bar at an angle. When off, its end is straight.", disabled = notOwnBar("party") },
            { type = "slider", key = "partyCastbar.textSize", label = "Party cast bar text size", min = 6, max = 24, step = 1,
              desc = "The spell name and time on the party's cast bars. Inside the frame it's kept small enough for the power bar.",
              disabled = off("partyCastbar.enabled") },
            { type = "slider", key = "partyCastbar.insideTextSize", label = "Text size inside the frame", min = 0, max = 20, step = 1,
              desc = "The spell name and timer while the bar sits inside a party frame, even past the power bar's height. 0 sizes them to fit the power bar.",
              disabled = notInside("party") },
            { type = "toggle", key = "partyCastbar.reverseFill", label = "Fill right to left",
              desc = "Each detached cast bar fills from the right.", disabled = notOwnBar("party") },
            { type = "color", key = "partyCastbar.textColor", label = "Text color",
              desc = "The spell name and timer on the party's cast bars.", disabled = off("partyCastbar.enabled") },
        } },
        { label = "Text", items = {
            { type = "toggle", key = "casts.showName", label = "Spell name",
              desc = "The spell's name on every cast bar." },
            { type = "dropdown", key = "casts.timer", label = "Timer",
              values = { left = "Time left (1.2)", total = "Left / total (1.2 / 2.5)", none = "None" },
              order = { "left", "total", "none" },
              desc = "The time on every cast bar: what's left, what's left out of the whole cast, or nothing." },
        } },
        { label = "Cast bar fill", items = {
            { type = "dropdown", key = "casts.fill", label = "Cast bar fill style", values = FILL_STYLES, order = FILL_ORDER,
              desc = "How every cast bar (yours, target's, focus's) is filled: one color each, the Daylight gradient (the logo's blue to orange), or a two-color gradient per kind of cast, set right here." },
            { type = "toggle", key = "casts.flash", label = "Show interrupts",
              desc = "When a cast is interrupted, the bar stays full for a moment and says Interrupted." },
            gradientRow("CAST", "Casting gradient", fillIsNot("casts.fill", "pair")),
            gradientRow("CHANNEL", "Channeling gradient", fillIsNot("casts.fill", "pair")),
            gradientRow("CAST_INTERRUPTED", "Interrupted gradient", fillIsNot("casts.fill", "pair")),
            gradientRow("CAST_LOCKED", "Can't interrupt gradient", fillIsNot("casts.fill", "pair")),
        } },
        { label = "Your cast bar's colors", items = {
            { type = "toggle", key = "casts.classColor", label = "Class color on your cast bar",
              desc = "Your casts and channels in your class color, or your class's gradient with a two-color fill. Not with the Daylight gradient.",
              disabled = fillIs("casts.fill", "daylight") },
            { type = "color", key = "casts.cast", label = "Casting color", hidden = fillIsNot("casts.fill", "plain"),
              desc = "Your cast bar's color while you cast." },
            { type = "color", key = "casts.channel", label = "Channeling color", hidden = fillIsNot("casts.fill", "plain"),
              desc = "Your cast bar's color while you channel." },
            { type = "color", key = "casts.interrupted", label = "Interrupted color", hidden = fillIsNot("casts.fill", "plain"),
              desc = "Your cast bar's color for a moment after your cast is interrupted.",
              disabled = function(get) return get("casts.flash") ~= true end },
            { type = "color", key = "casts.locked", label = "Can't be interrupted",
              desc = "The bar's color while the cast can't be interrupted, whatever the fill style." },
        } },
        { label = "Target and focus cast bars' colors", items = {
            { type = "toggle", key = "targetCasts.classColor", label = "Class color on target and focus cast bars",
              desc = "A player's casts in their class color, or their class's gradient with a two-color fill. Creatures' casts keep the fill style. Not with the Daylight gradient.",
              disabled = fillIs("casts.fill", "daylight") },
            { type = "color", key = "targetCasts.cast", label = "Casting color", hidden = fillIsNot("casts.fill", "plain"),
              desc = "The target and focus cast bars' color while they cast." },
            { type = "color", key = "targetCasts.channel", label = "Channeling color", hidden = fillIsNot("casts.fill", "plain"),
              desc = "The target and focus cast bars' color while they channel." },
            { type = "color", key = "targetCasts.interrupted", label = "Interrupted color", hidden = fillIsNot("casts.fill", "plain"),
              desc = "The target and focus cast bars' color for a moment after their cast is interrupted.",
              disabled = function(get) return get("casts.flash") ~= true end },
            { type = "color", key = "targetCasts.locked", label = "Can't be interrupted",
              desc = "The bar's color while the cast can't be interrupted." },
        } },
        { label = "Target and focus interrupts", items = {
            { type = "dropdown", key = "casts.kickStyle", label = "Interrupt animation",
              values = DaylightUI.Motion.KICK_NAMES, order = DaylightUI.Motion.KICKS,
              desc = "What the target's or focus's cast bar does when its cast is interrupted. Your own interrupts light up in your accent color." },
            { type = "toggle", key = "casts.kickedBy", label = "Show who interrupted",
              desc = "\"Kicked by\" and the player's name in their class color, beside the target's or focus's cast bar for a moment." },
            { type = "dropdown", key = "casts.kickedByPos", label = "Who interrupted position",
              values = { right = "Right of the cast bar", below = "Under the cast bar" }, order = { "right", "below" },
              desc = "Where \"Kicked by\" and the name show: beside the cast bar or under it.",
              disabled = function(get) return get("casts.kickedBy") ~= true end },
        } },
    } },

    { id = "swing", label = "Swing Timer", preview = { "swing" }, desc = "When your next auto-attack lands: a bar for each hand you swing with.", groups = {
        { label = "Swing timer", items = {
            { type = "toggle", key = "swing.enabled", label = "Show the swing timer",
              desc = "Replaces the game's own swing timer. A bar fills over each swing; when your target is out of range it dims and its time turns red." },
            { type = "dropdown", key = "swing.visibility", label = "When to show",
              values = { swinging = "While swinging", combat = "In combat", always = "Always" },
              order = { "swinging", "combat", "always" },
              desc = "While swinging: each bar only while its swing runs, gone between swings. In combat: all your bars while you're fighting. A bar detached on its own has its own.",
              disabled = off("swing.enabled") },
            { type = "toggle", key = "swing.attach", invert = true, label = "Detach as group",
              desc = "Takes the bars out from under the player frame so you can move them together (/dui unlock); they slide out of their own box. When off, they hang under the player frame, under the cast bar while it hangs there, even with the cast bar detached. With your cast bar between your frame and the target's, they fan out under it instead, each a little wider.",
              disabled = function(get)
                  return get("swing.enabled") ~= true or (get("personal.enabled") == true and get("personal.swing") == true)
              end },
            { type = "slider", key = "swing.width", label = "Width", min = 80, max = 500, step = 1,
              desc = "Only when detached as a group. Hung under the player frame, the bars match its width.",
              disabled = groupAttached },
            { type = "slider", key = "swing.height", label = "Bar height", min = 6, max = 30, step = 1, unit = "px",
              desc = "How tall each swing timer bar is.", disabled = off("swing.enabled") },
            barRows("swing.media.bar", "the swing timer", "Swing timer", off("swing.enabled"))[1],
            barRows("swing.media.bar", "the swing timer", "Swing timer", off("swing.enabled"))[2],
            { type = "toggle", key = "swing.slant", label = "Angled end",
              desc = "Only when detached as a group.", disabled = groupAttached },
            { type = "toggle", key = "swing.showIcon", label = "Weapon icon",
              desc = "Only when detached as a group.", disabled = groupAttached },
            { type = "slider", key = "swing.textSize", label = "Swing timer text size", min = 6, max = 24, step = 1,
              desc = "The hand and time on each bar. Attached under the cast bar, it's kept small enough for the bar.",
              disabled = off("swing.enabled") },
            fontRow("swing.media.font", "Swing timer font", "The swing timer's hand and time", off("swing.enabled")),
            { type = "toggle", key = "swing.reverseFill", label = "Fill right to left",
              desc = "Only when detached as a group.", disabled = groupAttached },
            { type = "slider", key = "swing.spacing", label = "Space between bars", min = 0, max = 10, step = 1, unit = "px",
              desc = "Only when detached as a group.", disabled = groupAttached },
            { type = "toggle", key = "swing.growUp", label = "Stack upward",
              desc = "Only when detached as a group. Main hand at the bottom, the others above it.",
              disabled = groupAttached },
            strataRow("swing.strata", "Swing timer layer", "The layer the swing timer draws in when detached, as a group or a bar on its own.",
                off("swing.enabled"), " Hung under the player frame or the cast bar, it draws with them instead."),
        } },
        shellCard("swing", "swing.enabled", true),
        { label = "Bars", items = {
            { type = "toggle", key = "swing.mainHand", label = "Main hand",
              desc = "Your main hand's bar. Turn it off to keep only your other bars, like a hunter's ranged bar.",
              disabled = off("swing.enabled") },
            { type = "toggle", key = "swing.offHand", label = "Off hand",
              desc = "While you have a weapon in your off hand.", disabled = off("swing.enabled") },
            { type = "toggle", key = "swing.ranged", label = "Ranged",
              desc = "While you have a bow, gun, crossbow, thrown weapon or wand.", disabled = off("swing.enabled") },
            { type = "toggle", key = "swing.stopCue", label = "Auto Shot stop-moving line",
              desc = "Hunters: a line on the ranged bar where Auto Shot's wind-up starts, adjusted for haste and your ping. Moving past it holds the shot back, so the bar stays full and says Stop moving until you stand still.",
              disabled = function(get) return get("swing.enabled") ~= true or get("swing.ranged") ~= true end },
            { type = "toggle", key = "swing.rangeText", label = "Range on the ranged bar",
              desc = "The ranged bar shows how far your target is instead of its name: Melee, Dead zone, 10 to 35 yd, Max range or Out of range.",
              disabled = function(get) return get("swing.enabled") ~= true or get("swing.ranged") ~= true end },
            { type = "toggle", key = "swing.showText", label = "Show names and time left",
              desc = "Each bar's hand (or the queued attack) and the time to the next swing, written on the bar. Each bar's own switches under Detached bars can turn off one or the other.",
              disabled = off("swing.enabled") },
            { type = "toggle", key = "swing.queue", label = "Queued attacks",
              desc = "While Heroic Strike, Cleave or Maul waits for your next swing, the melee bars change color and show its name.",
              disabled = off("swing.enabled") },
        } },
        swingBarCard(),
        { label = "Colors", items = {
            { type = "dropdown", key = "swing.fill", label = "Swing timer fill style", values = FILL_STYLES, order = FILL_ORDER,
              desc = "How each hand's bar is filled: one color each, the Daylight gradient (the logo's blue to orange), or a two-color gradient per hand, set right here. A queued attack always keeps its own color.",
              disabled = off("swing.enabled") },
            { type = "toggle", key = "swing.classColor", label = "Class color on the swing timer",
              desc = "Every hand's bar in your class color, or your class's gradient with a two-color fill. A queued attack keeps its own color. Not with the Daylight gradient.",
              disabled = function(get) return get("swing.enabled") ~= true or get("swing.fill") == "daylight" end },
            { type = "color", key = "swing.colors.main", label = "Main hand color", hidden = fillIsNot("swing.fill", "plain"),
              desc = "The main hand bar's color.",
              disabled = function(get) return get("swing.enabled") ~= true or get("swing.classColor") == true end },
            { type = "color", key = "swing.colors.off", label = "Off hand color", hidden = fillIsNot("swing.fill", "plain"),
              desc = "The off hand bar's color.",
              disabled = function(get) return get("swing.enabled") ~= true or get("swing.classColor") == true end },
            { type = "color", key = "swing.colors.ranged", label = "Ranged color", hidden = fillIsNot("swing.fill", "plain"),
              desc = "The ranged bar's color.",
              disabled = function(get) return get("swing.enabled") ~= true or get("swing.classColor") == true end },
            { type = "color", key = "swing.colors.queued", label = "Attack queued color", hidden = fillIs("swing.fill", "pair"),
              desc = "The melee bars' color while Heroic Strike, Cleave or Maul waits for your next swing.", disabled = off("swing.enabled") },
            gradientRow("SWING_MAIN", "Main hand gradient", fillIsNot("swing.fill", "pair")),
            gradientRow("SWING_OFF", "Off hand gradient", fillIsNot("swing.fill", "pair")),
            gradientRow("SWING_RANGED", "Ranged gradient", fillIsNot("swing.fill", "pair")),
            gradientRow("SWING_QUEUED", "Attack queued gradient", fillIsNot("swing.fill", "pair")),
        } },
    } },

    { id = "personal", label = "Personal Display", preview = { "personal" }, desc = "Your health and power just under your character, the way Legion's personal display sat at your feet.", groups = {
        { label = "Personal display", items = {
            { type = "toggle", key = "personal.enabled", label = "Show the personal display",
              desc = "Your health bar, your power under it and, for rogues and druids, your combo points, just under your character. It follows the camera as you zoom." },
            { type = "dropdown", key = "personal.follow", label = "Personal display position",
              values = { feet = "At your feet", fixed = "Where you put it" }, order = { "feet", "fixed" },
              desc = "At your feet: it stays under your character as you zoom the camera in and out. Where you put it: it stays where you drag it in unlock mode (/dui unlock).",
              disabled = off("personal.enabled") },
            { type = "slider", key = "personal.x", label = "Personal display left / right", min = -300, max = 300, step = 1, unit = "px",
              desc = "Moves it sideways from under your character.",
              disabled = function(get) return get("personal.enabled") ~= true or get("personal.follow") == "fixed" end },
            { type = "slider", key = "personal.y", label = "Personal display up / down", min = -200, max = 200, step = 1, unit = "px",
              desc = "Moves it up or down from where the camera puts it.",
              disabled = function(get) return get("personal.enabled") ~= true or get("personal.follow") == "fixed" end },
        } },
        { label = "Bars", items = {
            { type = "slider", key = "personal.width", label = "Personal display width", min = 60, max = 400, step = 1, unit = "px",
              desc = "How wide the bars are.", disabled = off("personal.enabled") },
            strataRow("personal.strata", "Personal display layer", "The layer the personal display draws in. Low keeps it under your other frames.",
                off("personal.enabled")),
            { type = "toggle", key = "personal.showHealth", since = "1.6.0.2", label = "Personal health bar",
              desc = "Your health on the display. Turn it off to keep just your power bar. Needs the power bar on.",
              disabled = offAny("personal.enabled", "personal.showPower") },
            { type = "slider", key = "personal.height", label = "Personal health bar height", min = 4, max = 30, step = 1, unit = "px",
              desc = "How tall the health bar is.", disabled = offAny("personal.enabled", "personal.showHealth") },
            PERSONAL_HEALTH[1], PERSONAL_HEALTH[2], PERSONAL_HEALTH[3], PERSONAL_HEALTH[4],
            { type = "toggle", key = "personal.predictHeals", since = "1.5.1.2", label = "Personal incoming heals",
              desc = "Heals on their way, as a soft green stretch past the health.",
              disabled = offAny("personal.enabled", "personal.showHealth") },
            { type = "toggle", key = "personal.predictAbsorbs", since = "1.5.1.2", label = "Personal absorbs",
              desc = "Damage shields, as a pale stretch after any incoming heals.",
              disabled = offAny("personal.enabled", "personal.showHealth") },
            { type = "toggle", key = "personal.showPower", label = "Personal power bar",
              desc = "Your mana, rage or energy under the health bar. Needs the health bar on.",
              disabled = offAny("personal.enabled", "personal.showHealth") },
            { type = "slider", key = "personal.powerHeight", label = "Personal power bar height", min = 2, max = 30, step = 1, unit = "px",
              desc = "How tall the power bar is.",
              disabled = function(get) return get("personal.enabled") ~= true or get("personal.showPower") ~= true end },
            PERSONAL_POWER[1], PERSONAL_POWER[2], PERSONAL_POWER[3], PERSONAL_POWER[4],
            { type = "toggle", key = "personal.combo", label = "Combo points on the personal display",
              desc = "Rogues and druids: your combo points under the bars, in the colors from Extras.", disabled = off("personal.enabled") },
            { type = "toggle", key = "personal.slant", label = "Personal display angled ends",
              desc = "Cuts the right end of each bar at an angle. When off, the ends are square.", disabled = off("personal.enabled") },
            { type = "slider", key = "personal.angle", label = "Personal display angle", min = 0, max = 0.6, step = 0.01, unit = "%",
              desc = "How far the angled end leans, docked bars included. Set to 0 to use the Slant angle on Extras.",
              disabled = offAny("personal.enabled", "personal.slant") },
            { type = "toggle", key = "personal.swing", label = "Swing timers on the personal display",
              desc = "Moves your swing timers under the personal display, as wide as it.", disabled = off("personal.enabled") },
            { type = "toggle", key = "personal.castbar", label = "Cast bar on the personal display",
              desc = "Moves your cast bar under the personal display, as wide as it.", disabled = off("personal.enabled") },
        } },
        shellCard("personal", "personal.enabled"),
        personalTextCard(),
        PERSONAL_AURA_GROUPS[1],
        PERSONAL_AURA_GROUPS[2],
        DaylightUI.Fade.Card("personal.fade.", nil, off("personal.enabled"), "Personal display"),
    } },

    { id = "extras", label = "Extras", desc = "Combo points, portrait icons and range fade.", groups = {
        { label = "Frame shape", items = {
            styleRow("look.style", false),
            { type = "slider", key = "look.slant", label = "Slant angle", min = 0.05, max = 0.4, step = 0.01, unit = "%",
              desc = "How far the frames' angled ends lean, on every unit frame and cast bar. 21% is the usual look." },
        } },
        { label = "Combo points", desc = "For rogues, and druids in cat form. Small pips on your target frame.", items = {
            { type = "toggle", key = "combo.enabled", label = "Show combo points",
              desc = "Replaces the game's own combo points." },
            { type = "dropdown", key = "combo.anchor", label = "Attach to",
              values = { target = "Target frame", player = "Player frame" }, order = { "target", "player" },
              desc = "Which frame the pips sit on.", disabled = off("combo.enabled") },
            { type = "dropdown", key = "combo.side", label = "Side",
              values = { below = "Below the frame", above = "Above the frame" }, order = { "below", "above" },
              desc = "Under the frame, or over it, clear of the name. The target's buffs or debuffs on that side move out of the way.",
              disabled = off("combo.enabled") },
            { type = "dropdown", key = "combo.align", label = "Alignment",
              values = { inner = "Inner end", center = "Centered", outer = "Outer end" }, order = { "inner", "center", "outer" },
              desc = "Where along the frame the row starts: the angled end facing the middle of your screen, the middle, or the far end.",
              disabled = function(get) return get("combo.enabled") ~= true or get("combo.stretch") == true end },
            { type = "toggle", key = "combo.stretch", label = "Match frame width",
              desc = "The pips widen to span the whole frame, so the row reads like a bar.",
              disabled = off("combo.enabled") },
            { type = "slider", key = "combo.size", label = "Pip width", min = 8, max = 40, step = 1, unit = "px",
              desc = "How wide each combo point pip is. Not while the pips match the frame's width.", disabled = function(get) return get("combo.enabled") ~= true or get("combo.stretch") == true end },
            barRows("combo.media.bar", "the combo points", "Combo point", off("combo.enabled"))[1],
            barRows("combo.media.bar", "the combo points", "Combo point", off("combo.enabled"))[2],
            { type = "slider", key = "combo.height", label = "Pip height", min = 0, max = 30, step = 1, unit = "px",
              desc = "Set to 0 for automatic height.", disabled = off("combo.enabled") },
            { type = "slider", key = "combo.gap", label = "Spacing", min = 0, max = 10, step = 1, unit = "px",
              desc = "The gap between combo point pips.", disabled = off("combo.enabled") },
            { type = "slider", key = "combo.x", label = "Combo points left / right", min = -50, max = 50, step = 1, unit = "px",
              desc = "Nudges the row of pips sideways.", disabled = off("combo.enabled") },
            { type = "slider", key = "combo.y", label = "Combo points up / down", min = -50, max = 50, step = 1, unit = "px",
              desc = "Nudges the row of pips up or down.", disabled = off("combo.enabled") },
            { type = "slider", key = "combo.border", label = "Outline", min = 0, max = 4, step = 1, unit = "px",
              desc = "Set to 0 for no outline.", disabled = off("combo.enabled") },
            { type = "toggle", key = "combo.slant", label = "Angled ends",
              desc = "Each pip leans like the frames' angled ends. When off, their ends are straight.", disabled = off("combo.enabled") },
            { type = "dropdown", key = "combo.colorMode", label = "Colors",
              values = { color = "One color", blend = "Color to full color", class = "Class color",
                         gradient = "One gradient (Gradients page)", points = "A gradient per point (Gradients page)" },
              order = { "color", "blend", "class", "gradient", "points" },
              desc = "One color on every pip; colors shading from Combo point color to Full color along the row; your class color; or two-color pairs from the Gradients page (Combo points), one for all pips or one each. Your nameplates' combo points use the same colors.",
              disabled = off("combo.enabled") },
            { type = "color", key = "combo.color", label = "Combo point color",
              desc = "The pips' color with One color, or the color they start from with Color to full color.",
              hidden = function(get) local m = get("combo.colorMode"); return m ~= "color" and m ~= "blend" end,
              disabled = off("combo.enabled") },
            { type = "button", label = "Combo point gradients", text = "Edit",
              desc = "Opens the Gradients page, where the Combo points pairs are.",
              hidden = function(get) local m = get("combo.colorMode"); return m ~= "gradient" and m ~= "points" end,
              func = function() DaylightUI.OptionsPanel.Show("gradients") end },
            { type = "toggle", key = "combo.fullRed", label = "Last point in full color",
              desc = "The fifth pip fills in Full color (red to start with), so a full row stands out at a glance.",
              disabled = off("combo.enabled") },
            { type = "toggle", key = "combo.fullAll", label = "Whole row in full color at max points",
              desc = "At your most combo points every pip turns Full color, not just the last one: hard to miss.",
              disabled = function(get) return get("combo.enabled") ~= true or get("combo.fullRed") ~= true end },
            { type = "color", key = "combo.fullColor", label = "Full color",
              desc = "The color of the last pip, or the whole row at max points, and the end of Color to full color.",
              disabled = function(get)
                  return get("combo.enabled") ~= true or (get("combo.fullRed") ~= true and get("combo.colorMode") ~= "blend")
              end },
            { type = "slider", key = "combo.empty", label = "Empty pips", min = 0, max = 1, step = 0.05, unit = "%",
              desc = "How bright the pips you haven't filled are, as a share of their color. Lower makes the filled ones stand out more.",
              disabled = off("combo.enabled") },
        } },
        { label = "Class icons", desc = "On the portrait rings of the player, target and focus frames.", items = {
            { type = "dropdown", key = "portraits.icons", label = "Icon style",
              choices = UF.IconStyleChoices,
              desc = "Daylight UI's own icons, the game's own round class icons, or with the Jiberish Fabled Icons addon installed, its Fabled styles "
                  .. "(art by JiberishUI and its artists, read from that addon's own folder)." },
            { type = "text", label = function()
                if UF.HasIconPack() then
                    return DaylightUI.L["Jiberish Fabled Icons is installed. Pick an icon for each class below, any style or one of its specs. The first icon on each line follows the Icon style."]
                end
                return DaylightUI.L["Install the Jiberish Fabled Icons addon to unlock more class icon styles."]
            end },
            classIconPicker,
        } },
        { label = "Portrait rings", desc = "The ring round every portrait, on every frame. Each frame picks its ring's color on its own page.", items = {
            { type = "dropdown", key = "portraits.ringWidth", label = "Ring thickness",
              values = UF.RING_WIDTH_NAMES, order = UF.RING_WIDTH_ORDER,
              desc = "How thick the ring is. A thicker ring leaves a smaller picture inside. The red aggro ring and its lights follow it." },
            { type = "toggle", key = "portraits.ringLine", label = "Line round the middle",
              desc = "The thin dark line round the middle of the ring. When off, the ring is one smooth band." },
        } },
        { label = "Range fade", desc = "Dims friendly units that are out of reach: target, focus, target of target, party and raid frames, when they're in your group.", items = {
            { type = "toggle", key = "range.enabled", label = "Fade when out of range",
              desc = "The game only reports range for your group; anyone else stays at full opacity." },
            { type = "slider", key = "range.alpha", label = "Faded opacity", min = 0.1, max = 0.9, step = 0.05, unit = "%",
              desc = "How see-through a frame gets while its unit is out of range.", disabled = function(get) return get("range.enabled") ~= true end },
            { type = "toggle", key = "range.groupOwn", label = "Separate opacity for party and raid",
              desc = "Party and raid frames fade to their own opacity instead of the one above.",
              disabled = function(get) return get("range.enabled") ~= true end },
            { type = "slider", key = "range.alphaGroup", label = "Party and raid faded opacity", min = 0.1, max = 0.9, step = 0.05, unit = "%",
              desc = "How see-through party and raid frames get while a member is out of range.", disabled = function(get) return get("range.enabled") ~= true or get("range.groupOwn") ~= true end },
        } },
    } },
    -- Click-casting (ClickCastPage.lua).
    ns.ClickCastPage,
} }
