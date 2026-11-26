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
        set = function(v) DaylightUI:Set("general", path, v) end,
        default = function() return DaylightUI.DB.GENERAL_DEFAULTS.lastNames[element] == true end }
end

local _, ns = ...
local UF = ns.UF

-- disabled() helpers. get reads another setting on the same page.
local function off(key) return function(get) return get(key) ~= true end end

-- A frame's two end menus (Options.EndRows): slant/slantUnder hold its inner
-- end (the one the bars fill toward), slantOuter/slantUnderOuter the outer
-- one. The target, its target and the PvP frames mirror the player, so their
-- inner end is the left. With a portrait, the outer end stays straight while
-- the portrait sits on the frame (UF.FrameEnds): the ring covers it.
-- prefix is the settings table ("player", "raid", "partyPet"), name labels
-- the rows ("Frame", "Pet bar"), note ends both descriptions.
local INNER_END = { target = "left", targettarget = "left", arena = "left" }
local function frameEndRows(prefix, id, name, disabled, portrait, note)
    local k = function(s) return prefix .. "." .. s end
    local inner = INNER_END[id] or "right"
    local outer = inner == "right" and "left" or "right"
    local ends = {
        [inner] = { on = k("slant"), flip = k("slantUnder") },
        [outer] = { on = k("slantOuter"), flip = k("slantUnderOuter") },
    }
    if portrait then
        ends[outer].note = "Stays straight while the portrait sits on the frame, since the ring covers it."
        ends[outer].disabled = function(get)
            return get(k("portrait")) ~= "none" and get(k("portraitAt")) ~= "free"
        end
    end
    return DaylightUI.Options.EndRows({ name = name, left = ends.left, right = ends.right,
        disabled = disabled, note = note })
end

-- A frame's own angle: a switch and its slider, read by UF.AngleOf. o.own and
-- o.lean are the keys, o.name labels both ("Swing timer"), o.what names the
-- bar in the text ("the swing timer's"), o.note ends both descriptions, and
-- o.disabled / o.hidden gray out or hide both. Use as angleRows(o)[1], [2].
local function angleRows(o)
    local dis = o.disabled or function() return false end
    local note = o.note and (" " .. o.note) or ""
    return {
        { type = "toggle", key = o.own, label = o.name .. " own angle", since = o.since,
          desc = "Gives " .. o.what .. " angled ends their own angle, set below. When off, they follow the Slant angle on Unit Frames > Look." .. note,
          disabled = dis, hidden = o.hidden },
        { type = "slider", key = o.lean, label = o.name .. " angle", since = o.since, min = 0.01, max = 1, step = 0.01, unit = "%",
          desc = "How far " .. o.what .. " angled ends lean: how far the cut reaches in, as a share of the bar's height. Near 0 is almost square, 100 is 45 degrees. Needs its own angle on." .. note,
          disabled = function(get) return dis(get) or get(o.own) ~= true end, hidden = o.hidden },
    }
end
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
-- "plain"; with "pair" the bars take their pairs from the Gradients page.
local FILL_STYLES = { plain = "One color", daylight = "Daylight gradient", pair = "Two-color gradient",
    customGradient = "Custom gradient" }
local FILL_ORDER = { "plain", "daylight", "pair", "customGradient" }
-- Class color has no place in a fill that's one gradient for everything.
local function noClassFill(key)
    return function(get) return get(key) == "daylight" or get(key) == "customGradient" end
end
local function fillIs(key, v) return function(get) return get(key) == v end end
local function fillIsNot(key, v) return function(get) return get(key) ~= v end end

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

local NAME_COLORS = { global = "Same as the Look page", white = "White", class = "Class and reaction",
    classGradient = "Class gradient", custom = "One color" }
local NAME_COLOR_ORDER = { "global", "white", "class", "classGradient", "custom" }
local TEXT_COLORS = { white = "White", class = "Class color", custom = "One color" }
local TEXT_COLOR_ORDER = { "white", "class", "custom" }
local function notCustom(key) return function(get) return get(key) ~= "custom" end end

-- A "Show % sign" row: off with its text, and grayed while the format isn't Percent.
local function signOff(off, formatKey)
    return function(get) return off(get) or get(formatKey) ~= "percent" end
end

-- The shield texture picks (Look page): stripes, plain, then every shared
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
local SPOT_VALUES = { topleft = "Top left", top = "Top", topright = "Top right", left = "Left", center = "Middle",
    right = "Right", bottomleft = "Bottom left", bottom = "Bottom", bottomright = "Bottom right" }
for _, s in ipairs(ns.Spots.ORDER) do SPOT_VALUES[s] = SPOT_VALUES[s] or ns.Spots.LABELS[s] end
-- A party button's role, marker and crown: at home (UF.ICON_HOME), or any spot.
local HOME_SPOTS, HOME_ORDER = { [UF.ICON_HOME] = "With the name or portrait" }, { UF.ICON_HOME }
for _, s in ipairs(ns.Spots.ORDER) do
    HOME_SPOTS[s], HOME_ORDER[#HOME_ORDER + 1] = SPOT_VALUES[s], s
end
-- The level badge: on the portrait (with the socket look, a tag where the
-- ring meets the frame), at the ring's foot, or any spot.
local LEVEL_SPOTS, LEVEL_ORDER = { ring = "On the portrait", foot = "Under the portrait" }, { "ring", "foot" }
for _, s in ipairs(ns.Spots.ORDER) do
    LEVEL_SPOTS[s], LEVEL_ORDER[#LEVEL_ORDER + 1] = ns.Spots.LABELS[s], s
end
-- The two spots on the portrait itself, which take no nudges.
local function portraitSpot(v) return v == "ring" or v == "foot" end

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
                    UF.ICON_STYLES[style] or "Daylight UI"))
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

-- Where each tile icon sits and how big it is, for raid tiles and party frames,
-- one list per icon (role, marker, leader, dispel, ready, summon, rez) so a page can
-- put each with its own switch. k maps a key to its setting, dis is the "page
-- is off" check. skip (optional) leaves out items the page already has
-- (markerSize) or relabels the px crown (leaderPxLabel, leaderPxDesc). home
-- (party): the role, marker and crown spots offer "With the name or portrait"
-- (UF.ICON_HOME), and their sizes say they fit there until changed.
local function iconItems(k, dis, skip, home)
    skip = skip or {}
    -- An icon's rows gray out while its own switch is off.
    local function gated(switch)
        return function(get) return dis(get) or get(k(switch)) == false end
    end
    local function spot(key, label, homed, disabled)
        local item = { type = "dropdown", key = k(key), label = label .. " position", values = SPOT_VALUES,
                 desc = "Where the " .. string.lower(label) .. " sits on each frame, or just outside it.",
                 order = ns.Spots.ORDER, disabled = disabled }
        if homed then
            item.values, item.order = HOME_SPOTS, HOME_ORDER
            item.desc = "Where the " .. string.lower(label) .. " sits: with the name tab or portrait"
                .. " (in a corner when the frame has neither), or any spot on or around the frame."
        end
        return item
    end
    local function size(key, label, disabled, desc)
        return { type = "slider", key = k(key), label = label .. " size", min = 6, max = 32, step = 1, unit = "px",
                 desc = desc or ("How big the " .. string.lower(label) .. " is."
                     .. (home and " With the name or portrait it fits there until you change this." or "")),
                 disabled = disabled }
    end
    -- The two nudges after a piece's spot and size (written by Design mode's
    -- drag and arrow keys).
    local function nudges(items, key, label, disabled, what)
        what = what or string.lower(label)
        items[#items + 1] = { type = "slider", key = k(key .. "X"), label = label .. " left / right", min = -50, max = 50, step = 1,
            unit = "px", desc = "Nudges the " .. what .. " sideways from its position.", disabled = disabled }
        items[#items + 1] = { type = "slider", key = k(key .. "Y"), label = label .. " up / down", min = -50, max = 50, step = 1,
            unit = "px", desc = "Nudges the " .. what .. " up or down from its position.", disabled = disabled }
    end
    local roleOff = gated("showRole")
    local role = { spot("rolePos", "Role icon", home, roleOff), size("roleSize", "Role icon", roleOff) }
    nudges(role, "role", "Role icon", roleOff)
    role[#role + 1] = { type = "toggle", key = k("roleHideDamage"), invert = true, label = "Show the damage role icon",
        desc = "Damage dealers get a role icon too. When off, only tanks and healers get one.", disabled = roleOff }
    role[#role + 1] = { type = "toggle", key = k("roleHideInCombat"), invert = true, label = "Show role icon in combat",
        desc = "The role icon stays in a fight. When off, it hides while you're fighting.", disabled = roleOff }
    local markerOff = gated("showMarker")
    local marker = { spot("markerPos", "Raid marker", home, markerOff) }
    if not skip.markerSize then marker[#marker + 1] = size("markerSize", "Raid marker", markerOff) end
    nudges(marker, "marker", "Raid marker", markerOff)
    local leaderOff = gated("showLeader")
    local leader = { spot("leaderPos", "Leader crown", home, leaderOff),
        size("leaderPx", skip.leaderPxLabel or "Leader crown", leaderOff, skip.leaderPxDesc) }
    nudges(leader, "leader", "Leader crown", leaderOff)
    leader[#leader + 1] = { type = "toggle", key = k("leaderHideInCombat"), invert = true, label = "Show leader crown in combat",
        desc = "The leader's crown stays in a fight. When off, it hides while you're fighting.", disabled = leaderOff }
    local dispelOff = gated("showDispel")
    local dispel = { spot("dispelPos", "Dispel icon", false, dispelOff) }
    nudges(dispel, "dispel", "Dispel icon", dispelOff)
    local readyOff = gated("showReady")
    local ready = {
        { type = "toggle", key = k("showReady"), label = "Ready check answers",
          desc = "During a ready check, a tick, a cross or a question mark on each member: ready, not ready, or no answer yet. They stay a few seconds after the check ends.",
          disabled = dis },
        { type = "dropdown", key = k("readyPos"), label = "Ready check position", values = SPOT_VALUES,
          desc = "Where the ready check answer sits on each frame, or just outside it.",
          order = ns.Spots.ORDER, disabled = readyOff },
        { type = "slider", key = k("readySize"), label = "Ready check size", min = 6, max = 32, step = 1,
          desc = "How big the ready check answer is.", unit = "px", disabled = readyOff },
    }
    nudges(ready, "ready", "Ready check", readyOff, "ready check answer")
    local summonOff = gated("showSummon")
    local summon = {
        { type = "toggle", key = k("showSummon"), label = "Summon icon",
          desc = "A swirl on a member who's being summoned: in your accent while they decide, green once they accept, red if they decline.",
          disabled = dis },
        { type = "dropdown", key = k("summonPos"), label = "Summon position", values = SPOT_VALUES,
          desc = "Where the summon icon sits on each frame, or just outside it.",
          order = ns.Spots.ORDER, disabled = summonOff },
        { type = "slider", key = k("summonSize"), label = "Summon size", min = 6, max = 32, step = 1,
          desc = "How big the summon icon is.", unit = "px", disabled = summonOff },
    }
    nudges(summon, "summon", "Summon", summonOff, "summon icon")
    local rezOff = gated("showRez")
    local rez = {
        { type = "toggle", key = k("showRez"), label = "Rez icon",
          desc = "An angel on a dead member while someone casts a rez on them, in your accent, then green while they can accept it. Saves two healers rezzing the same player.",
          disabled = dis },
        { type = "dropdown", key = k("rezPos"), label = "Rez position", values = SPOT_VALUES,
          desc = "Where the rez icon sits on each frame, or just outside it.",
          order = ns.Spots.ORDER, disabled = rezOff },
        { type = "slider", key = k("rezSize"), label = "Rez size", min = 6, max = 32, step = 1,
          desc = "How big the rez icon is.", unit = "px", disabled = rezOff },
    }
    nudges(rez, "rez", "Rez", rezOff, "rez icon")
    return { role = role, marker = marker, leader = leader, dispel = dispel, ready = ready, summon = summon, rez = rez }
end

-- Whether a group frame has neither portrait nor name tab showing (so level
-- and PvP have no home, and the corner icons are in use). Uses the builder's
-- own portrait rule, so a frame too short for a portrait counts as none.
local function noHome(k)
    return function(get)
        local cfg = { portrait = get(k("portrait")), height = get(k("height")), style = get(k("style")),
                      tabHeight = get(k("tabHeight")), showPower = get(k("showPower")), ribbonGap = get(k("ribbonGap")),
                      powerHeight = get(k("powerHeight")) }
        local mode = UF.PortraitMode({ portrait = true, spec = { styled = true } }, cfg)
        -- A style's name row also counts as a home while the health number is on it.
        local tab = (get(k("showName")) ~= false and get(k("nameOnBar")) ~= true)
            or (UF.StyleDef(cfg).row and get(k("showPercent")) == true)
        return mode == "none" and not tab
    end
end

-- The dispel items for a group page. gate is the page's on/off key, sizeMax the
-- icon size ceiling, what is the thing a highlight lights up ("frame"/"tile").
local function dispelItems(k, gate, sizeMax, what, place)
    local shown = off(gate)
    local items = {
        { type = "toggle", key = k("showDispel"), label = "Dispel icon",
          desc = "A small icon in a corner for a debuff you can remove, edged in its type's color.", disabled = shown },
        { type = "slider", key = k("dispelSize"), label = "Dispel icon size", min = 6, max = sizeMax, step = 1,
          desc = "How big the dispel icon is.", disabled = offAny(gate, k("showDispel")) },
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
    -- The icon's position and nudges sit right under its size.
    for i, item in ipairs(place or {}) do table.insert(items, 2 + i, item) end
    return items
end

-- Your target's outline on a group page. gate is the page's on/off key.
local function targetItems(k, gate)
    return {
        { type = "toggle", key = k("targetMark"), label = "Target outline",
          desc = "Outlines the member you have targeted, so you can find them at a glance.", disabled = off(gate) },
        { type = "dropdown", key = k("targetMarkColor"), label = "Target outline color",
          values = { accent = "Accent color", custom = "One color" }, order = { "accent", "custom" },
          desc = "Accent color follows your accent (General > Appearance). One color uses the one you pick.",
          disabled = offAny(gate, k("targetMark")) },
        { type = "color", key = k("targetMarkCustom"), label = "Custom target outline color",
          desc = "The outline's color when Target outline color is One color.",
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
              or "Across the bar keeps the name inside, with the alignment below. Any other spot puts it there, on or round the frame; outside spots need space between frames.", disabled = dis },
    }
    if not big and not small then
        items[#items + 1] = { type = "dropdown", key = k("nameAlign"), label = "Name alignment",
          values = { left = "Left", center = "Center", right = "Right" }, order = { "left", "center", "right" },
          desc = desc or "Where the name sits across the bar: left, center or right.", disabled = dis,
          hidden = function(get) local p = get(k("namePos")); return p ~= nil and p ~= "bar" end }
        items[#items + 1] = { type = "toggle", key = k("nameTag"), label = "Name tab", since = "1.8.0",
          desc = "A dark tab behind the name while it sits outside the tile, like the player frame's name. When off, the name floats on its own.",
          disabled = dis, hidden = function(get) return not UF.TAG_SPOTS[get(k("namePos")) or ""] end }
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

-- Puts rows that belong together side by side: each text's rows from its
-- switch to its nudges, each bar's size before its look. A row the table
-- doesn't know stays right after the row it followed.
local function fieldOf(key)
    local size = string.match(key, "Text%.(%a+)$")
    if size then return "size." .. size end
    if string.match(key, "^lastNames%.") then return "lastNames" end
    return string.match(key, "^[^%.]+%.(.+)$") or key
end
local function ordered(items, rank)
    local list, last = {}, 0
    for i, it in ipairs(items) do
        last = (type(it.key) == "string" and rank[fieldOf(it.key)]) or last
        list[i] = { it = it, r = last, i = i }
    end
    table.sort(list, function(a, b)
        if a.r ~= b.r then return a.r < b.r end
        return a.i < b.i
    end)
    for i, e in ipairs(list) do items[i] = e.it end
    return items
end
local TEXT_ORDER = {
    showName = 10, lastNames = 11, nameOnBar = 12, namePos = 13, nameAlign = 14, nameTag = 15, nameX = 16, nameY = 17,
    nameColor = 18, nameCustom = 19, nameLimitLen = 20, ["media.nameFont"] = 21, ["size.name"] = 22,
    showPercent = 30, healthText = 31, percentSign = 32, hideFullHealth = 33, healthTextPos = 33, percentColor = 34, percentCustom = 35,
    ["media.healthFont"] = 36, ["size.percent"] = 37, bigNumber = 38, ["size.big"] = 39, healthTextX = 40, healthTextY = 41,
    showPowerText = 50, powerFormat = 51, powerPercentSign = 52, hideFullPower = 53, powerTextPos = 54,
    ["media.powerFont"] = 55, ["size.power"] = 56, powerTextX = 57, powerTextY = 58,
}
local BAR_ORDER = {
    stripHeight = 1, ["media.health"] = 2, ["media.healthBack"] = 3, colorHealth = 4, colorHealthCustom = 5,
    backHealth = 6, backHealthColor = 7, backHealthBright = 8, backHealthAlpha = 9,
    showPower = 20, powerAt = 21, powerWidth = 22, powerHeight = 23, ribbonGap = 24,
    -- The power bar's two end menus share a rank, so they keep their order: left, then right.
    powerSlant = 25, powerSlantBoth = 25, ["media.power"] = 28, ["media.powerBack"] = 29,
    colorPower = 30, colorPowerCustom = 31, backPower = 32, backPowerColor = 33, backPowerBright = 34, backPowerAlpha = 35,
    reverseFill = 40, predictHeals = 41, predictAbsorbs = 42,
}

-- An aura group's layout rows, added to items: position, size, count, timers
-- and nudges. g maps a field to its key. dis grays it out, noTimers grays out
-- the "Only under a minute" row, gone hides it. kind names the icons in the
-- labels: one = "Debuff", many = "debuffs".
local function groupRows(items, g, dis, noTimers, gone, kind)
    local Spots = ns.Spots
    local one, many = kind.one, kind.many
    local Many = many:sub(1, 1):upper() .. many:sub(2)
    local function also(fn)
        if not gone then return fn end
        return function(get) return gone(get) or (fn ~= nil and fn(get)) or false end
    end
    local rows = {
        { type = "dropdown", key = g("spot"), label = one .. " position", values = Spots.LABELS,
          order = Spots.ORDER, desc = "Where the " .. many .. " sit, on or around each frame. Outside spots may need more space between frames.",
          disabled = dis },
        { type = "dropdown", key = g("grow"), label = one .. " grow direction", values = Spots.GROW_LABELS,
          order = Spots.GROW_ORDER, disabled = dis,
          desc = "Which way the row of icons fills from its first icon.",
          hidden = also(function(get) local s = get(g("spot")); return s == "outleft" or s == "outright" end) },
        { type = "slider", key = g("size"), label = one .. " icon size", min = 10, max = 32, step = 1, unit = "px",
          desc = "How big each icon is.", disabled = dis },
        { type = "slider", key = g("max"), label = one .. " max shown", min = 1, max = 12, step = 1,
          desc = "The most icons this group shows at once.", disabled = dis },
        { type = "slider", key = g("rows"), label = one .. " rows", min = 1, max = 4, step = 1,
          desc = "The icons wrap onto up to this many rows. Not used while icons per row is set.",
          disabled = function(get) return (dis and dis(get)) or (tonumber(get(g("perRow"))) or 0) > 0 end },
        { type = "slider", key = g("perRow"), label = one .. " icons per row", since = "1.9.5", min = 0, max = 12, step = 1,
          desc = "How many icons sit side by side before the next row starts. 0 spreads them evenly over the rows. Inside the frame a row never runs past its edge.",
          disabled = dis },
        { type = "slider", key = g("spacing"), label = one .. " spacing", min = 0, max = 12, step = 1, unit = "px",
          desc = "The gap between icons.", disabled = dis },
        { type = "toggle", key = g("timers"), label = "Time left on " .. many, desc = "The time left as a number on each icon.",
          disabled = dis },
        { type = "toggle", key = g("shortTimers"), label = one .. " time left only under a minute",
          desc = "Hides the number while a minute or more is left, so long ones stay quiet.", disabled = noTimers },
        { type = "slider", key = g("timeSize"), label = one .. " time left text size", since = "1.8.0", min = 6, max = 16, step = 1,
          desc = "How big the time left is on each icon.", disabled = noTimers },
        { type = "toggle", key = g("counts"), label = one .. " stack count", since = "1.8.0",
          desc = "The number of stacks in the corner of each icon.", disabled = dis },
        { type = "slider", key = g("countSize"), label = one .. " stack count size", since = "1.8.0", min = 6, max = 16, step = 1,
          desc = "How big the number of stacks is on each icon.",
          disabled = function(get) return dis(get) or get(g("counts")) == false end },
        { type = "toggle", key = g("swipe"), label = one .. " cooldown swipe",
          desc = "Each icon darkens like a clock as its time runs out.", disabled = dis },
        { type = "toggle", key = g("tooltips"), label = one .. " tooltip on hover",
          desc = "Hovering an icon says what it is. While the mouse is on an icon, mouseover casting misses that player. Clicks always go through to the frame.",
          disabled = dis },
        { type = "slider", key = g("x"), label = Many .. " left / right", min = -50, max = 50, step = 1, unit = "px",
          desc = "Nudges the " .. many .. " sideways from their position.", disabled = dis },
        { type = "slider", key = g("y"), label = Many .. " up / down", min = -50, max = 50, step = 1, unit = "px",
          desc = "Nudges the " .. many .. " up or down from their position.", disabled = dis },
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

-- Aura list rows for one aura row (AuraLists.lua). keyOf(field) is the row's
-- setting for hide | only | boss | maxTime. what = "buffs" | "debuffs" names
-- the icons; only = the row may pick a show-only list (spell ids are matched
-- there: buffs, or debuffs on an enemy); debuffs on yourself or your group get
-- the boss and duration rows instead. Extra hidden/disabled rules come in.
-- name (optional) starts the labels ("Crowd control"); enemy: the frame can
-- show an enemy, where buffs can't be matched.
local LIST_SINCE = "1.8.1"
local function auraListRows(keyOf, what, only, dis, hidden, name, enemy)
    local AL = ns.AuraLists
    local friendlyDebuffs = what == "debuffs" and not only
    name = name or (what == "buffs" and "Buff" or "Debuff")
    local items = {
        { type = "dropdown", key = keyOf("hide"), label = name .. " hide list", since = LIST_SINCE,
          choices = function() return AL.Choices("hide") end, disabled = dis, hidden = hidden,
          desc = friendlyDebuffs
              and "Debuffs on this list never show here. The game only lets addons hide a few harmless debuffs on you and your group, like Sated; the Aura Lists page marks which. Make and fill lists on Unit Frames > Aura Lists."
              or "The " .. what .. " on this list never show here. Make and fill lists on Unit Frames > Aura Lists." },
    }
    if only then
        items[#items + 1] = { type = "dropdown", key = keyOf("only"), label = name .. " show-only list", since = LIST_SINCE,
            choices = function() return AL.Choices("only") end, disabled = dis, hidden = hidden,
            desc = what == "buffs" and enemy
                and "Shows only the buffs on this list, with the filter above still applying. An empty list shows them all. Buffs on an enemy can't be matched, so none show there while a list is picked."
                or "Shows only the " .. what .. " on this list, with the filter above still applying. An empty list shows them all." }
    end
    if friendlyDebuffs and keyOf("boss") then
        items[#items + 1] = { type = "toggle", key = keyOf("boss"), label = "Only boss debuffs", since = LIST_SINCE,
            disabled = dis, hidden = hidden,
            desc = "Shows only the debuffs bosses put on players, the ones a fight is about." }
        items[#items + 1] = { type = "slider", key = keyOf("maxTime"), label = "Longest debuff shown", since = LIST_SINCE,
            min = 0, max = 600, step = 5, disabled = dis, hidden = hidden,
            desc = "Leaves out debuffs that last longer than this many seconds, and ones that never run out, like long curses and Resurrection Sickness. 0 shows them all." }
    end
    return items
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
            { type = "dropdown", key = g("debuffWhich"), label = "Extra aura filter", values = dv, order = dorder,
              desc = "Which debuffs this group shows.", hidden = isNot("debuffs"), disabled = dis },
            { type = "dropdown", key = g("buffWhich"), label = "Extra aura filter", values = bv, order = border,
              desc = "Which buffs this group shows.", hidden = isNot("buffs"), disabled = dis },
        }
        for _, it in ipairs(auraListRows(g, "debuffs", false, dis, isNot("debuffs"), "Extra aura")) do items[#items + 1] = it end
        -- The buff rows share the slot's hide key with its debuff rows, one of them hidden.
        for _, it in ipairs(auraListRows(g, "buffs", true, dis, isNot("buffs"), "Extra aura")) do items[#items + 1] = it end
        groupRows(items, g, dis, offAny(gate, g("timers")), gone, { one = "Extra aura", many = "extra auras" })
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
    id = tonumber(id)
    local name = id and C_Spell.GetSpellName(id)
    if type(name) == "string" and not DaylightUI.IsSecret(name) then return name end
end

-- Your cast bar's spell colors: a name box to add a spell, then a line per
-- spell with its icon, name, color swatch and an X.
local SPELL_LINE, SPELL_ADD_H, SPELL_NOTE = 28, 42, 22
local function spellColorLine(row)
    local W, Style, Motion = DaylightUI.Widgets, DaylightUI.Style, DaylightUI.Motion
    local CB = ns.CastBar
    local line = CreateFrame("Frame", nil, row.list)
    line:SetHeight(SPELL_LINE)
    line.icon = line:CreateTexture(nil, "ARTWORK")
    line.icon:SetSize(SPELL_LINE - 8, SPELL_LINE - 8)
    line.icon:SetPoint("LEFT", line, "LEFT", 2, 0)
    Style.CropIcon(line.icon)
    line.delete = W.DeleteButton(line)
    line.delete:SetPoint("RIGHT", line, "RIGHT", 0, 0)
    line.swatch = W.Swatch(line, line, function()
        local e = (CB.cfg.spellColors or {})[line.index]
        return e and e.color
    end, function(rgb) CB.SetSpellColor(line.index, rgb) end)
    line.swatch:SetPoint("RIGHT", line.delete, "LEFT", -8, 0)
    line.text = W.Font(line, W.BODY, Style.SIZE.body, W.COLORS.text)
    line.text:SetPoint("LEFT", line.icon, "RIGHT", 8, 0)
    line.text:SetPoint("RIGHT", line.swatch, "LEFT", -8, 0)
    line.delete:SetScript("OnClick", function()
        if line.going then return end
        line.going = true
        Motion.Fade(line, 1, 0, Motion.FAST)
        local i = line.index
        C_Timer.After(Motion.FAST, function()
            line.going = nil
            CB.RemoveSpellColor(i)
        end)
    end)
    return line
end

local spellColorItem = {
    type = "custom", label = "Spell colors", since = "2.2.5",
    build = function(row)
        local W, Style, L = DaylightUI.Widgets, DaylightUI.Style, DaylightUI.L
        local CB = ns.CastBar
        row.lines = {}
        row.input = W.Input(row, { hint = L["A spell's name or ID"], maxLetters = 80 })
        row.input:SetPoint("TOPLEFT", row, "TOPLEFT", W.PAD, -8)
        row.input:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(W.PAD + 90), -8)
        row.add = W.Button(row, ADD or L["Add"], W.INPUT_H)
        row.add:SetWidth(80)
        row.add:SetPoint("TOPRIGHT", row, "TOPRIGHT", -W.PAD, -8)
        local function add()
            local name, why = CB.AddSpellColor(row.input:GetText())
            row.why = why
            if name then
                row.fresh = name
                row.input:SetText("")
            end
            -- A refused name changes no setting, and an added one should fade in.
            local panel = DaylightUI.OptionsPanel
            if panel and panel.IsShown() then panel.Refresh() end
        end
        row.add:SetScript("OnClick", add)
        row.input:SetScript("OnEnterPressed", add)
        W.Complete(row.input, CB.SuggestSpells)
        row.note = W.Font(row, W.BODY, Style.SIZE.small, Style.INK.WARN)
        row.note:SetPoint("TOPLEFT", row, "TOPLEFT", W.PAD, -SPELL_ADD_H)
        row.note:SetPoint("TOPRIGHT", row, "TOPRIGHT", -W.PAD, -SPELL_ADD_H)
        row.list = CreateFrame("Frame", nil, row)
        row.empty = W.Font(row.list, W.BODY, Style.SIZE.body, Style.INK.LABEL)
        row.empty:SetPoint("TOPLEFT", row.list, "TOPLEFT", 0, -6)
        row.empty:SetText(L["No spells yet."])
    end,
    update = function(row)
        local W, Motion = DaylightUI.Widgets, DaylightUI.Motion
        local list = ns.CastBar.cfg.spellColors or {}
        local top = SPELL_ADD_H + (row.why and SPELL_NOTE or 0)
        row.note:SetText(row.why or "")
        row.note:SetShown(row.why ~= nil)
        row.list:ClearAllPoints()
        row.list:SetPoint("TOPLEFT", row, "TOPLEFT", W.PAD, -top)
        row.list:SetPoint("TOPRIGHT", row, "TOPRIGHT", -W.PAD, -top)
        for i, e in ipairs(list) do
            local line = row.lines[i]
            if not line then
                line = spellColorLine(row)
                row.lines[i] = line
            end
            line.index = i
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", row.list, "TOPLEFT", 0, -(i - 1) * SPELL_LINE)
            line:SetPoint("TOPRIGHT", row.list, "TOPRIGHT", 0, -(i - 1) * SPELL_LINE)
            line.icon:SetTexture(e.icon or 134400)
            line.text:SetText(e.name or "")
            line.swatch.Refresh()
            W.Stripe(line, i % 2 == 0)
            line:Show()
            if e.name == row.fresh then Motion.Fade(line, 0, 1, Motion.FAST)
            elseif not line.going then line:SetAlpha(1) end
        end
        row.fresh = nil
        for i = #list + 1, #row.lines do row.lines[i]:Hide() end
        row.count, row.top = #list, top
        row.empty:SetShown(#list == 0)
        row.list:SetHeight(math.max(SPELL_LINE, #list * SPELL_LINE))
    end,
    height = function(row)
        return (row.top or SPELL_ADD_H) + math.max(1, row.count or 0) * SPELL_LINE + 6
    end,
}

-- Your spells with a range, highest rank, by name. A pick saved on another
-- character stays listed so the menu never shows a blank.
local function rangeSpellChoices()
    local values, order = { none = "None, your group only" }, {}
    local SD = DaylightUI.Book and DaylightUI.Book.SpellData
    local seen, list = {}, {}
    local data = SD and SD.Read(false)
    for _, section in ipairs(data and data.sections or {}) do
        for _, e in ipairs(section.spells) do
            local id = e.spellID
            if type(id) == "number" and not e.passive and not e.future and not e.pet and not seen[e.name]
                and C_Spell.SpellHasRange and C_Spell.SpellHasRange(id) == true then
                seen[e.name] = true
                list[#list + 1] = { key = tostring(id), name = e.name }
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    local saved = DaylightUI:Get("UnitFrames", "range.spell")
    local savedId = tonumber(saved)
    if savedId and not values[saved] then
        local listed = false
        for _, e in ipairs(list) do if e.key == saved then listed = true end end
        local name = not listed and spellName(savedId)
        if name then list[#list + 1] = { key = saved, name = name } end
    end
    order[1] = "none"
    for _, e in ipairs(list) do values[e.key], order[#order + 1] = e.name, e.key end
    return values, order
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
            { type = "toggle", key = s("show"), label = "Heal indicator on", disabled = dis, hidden = gone,
              desc = "Shows this indicator on each member while its spell is on them. Group buffs (Mark of the Wild, Fortitude, the Blessings) show from anyone, and count down their last minute." },
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
              values = { spell = "The spell's own", custom = "One color" }, order = { "spell", "custom" },
              desc = "The spell's own color (Renew green, a shield blue), or one you pick.",
              disabled = sdis, hidden = gone },
            { type = "color", key = s("custom"), label = "Custom heal indicator color", disabled = sdis,
              desc = "The indicator's color when Heal indicator color is One color.",
              hidden = function(get) return gone(get) or get(s("paint")) ~= "custom" end },
            { type = "dropdown", key = s("spot"), label = "Heal indicator position", values = ns.Spots.LABELS,
              desc = "Where on the frame this indicator sits.",
              order = ns.Spots.ORDER, disabled = sdis, hidden = gone },
            { type = "slider", key = s("x"), label = "Heal indicator left / right", min = -50, max = 50, step = 1,
              desc = "Nudges this indicator sideways from its position.",
              unit = "px", disabled = sdis, hidden = gone },
            { type = "slider", key = s("y"), label = "Heal indicator up / down", min = -50, max = 50, step = 1,
              desc = "Nudges this indicator up or down from its position.",
              unit = "px", disabled = sdis, hidden = gone },
        } }
    end
    return { DaylightUI.Options.PickCard({ label = "Heal indicators",
        desc = "Small colored squares or spell icons on each member for your heals over time and shields, like Renew or Power Word: Shield. Each one shows while your spell is on them.",
        lead = {
            { type = "toggle", key = n("show"), label = "Show heal indicators", disabled = off(gate),
              desc = "A small square or icon on each member while one of your heals over time or shields is on them. On in the Healer setup. Each class has its own picks; change them below." },
            { type = "slider", key = n("size"), label = "Heal indicator size", min = 4, max = 20, step = 1, unit = "px",
              desc = "How big every indicator is.", disabled = dis },
            { type = "toggle", key = n("swipe"), label = "Heal indicator cooldown swipe",
              desc = "Each indicator darkens like a clock as your spell runs out.", disabled = dis },
            { type = "dropdown", key = n("look"), label = "Heal indicator look",
              values = { square = "Colored square", icon = "Spell icon" }, order = { "square", "icon" },
              desc = "A square in the spell's color, or the spell's own icon edged in that color.", disabled = dis },
        },
        pickDesc = "Which of the six indicators the rows below set.",
        pickHidden = gone, disabled = dis,
        choices = choices }) }
end

-- Each group's name in its rows' labels.
local GROUP_KINDS = { debuffs = { one = "Debuff", many = "debuffs" }, cc = { one = "Crowd control", many = "crowd control icons" },
                      buffs = { one = "Buff", many = "buffs" } }
-- The frame's icon borders (Auras.SetBorder), one card per frame. key(s):
-- the full settings key of s in the frame's aura settings. glow: the frame's
-- icons have the soft light behind what you can dispel or purge (target and focus).
local function borderCard(key, gate, glow)
    local function k(s) return key("iconBorder." .. s) end
    local dis = gate and off(gate) or nil
    local items = {
        { type = "slider", key = k("px"), label = "Icon border size", min = 0, max = ns.Auras.BORDER_MAX, step = 1,
          unit = "px", since = "2.4.1", disabled = dis,
          desc = "How thick the border round each buff and debuff icon is. At 0 the icons have none." },
        { type = "dropdown", key = k("debuff"), label = "Debuff border color", since = "2.4.1", disabled = dis,
          values = { dispel = "Dispel type color", wine = "Dark red", plain = "Plain" }, order = { "dispel", "wine", "plain" },
          desc = "Dispel type color shows Magic in blue, Poison in green and so on, so you see what you can remove. Dark red marks every debuff the same, and Plain matches the buffs." },
        { type = "dropdown", key = k("noType"), label = "Untyped debuff border color", since = "2.4.1",
          values = { wine = "Dark red", plain = "Plain" }, order = { "wine", "plain" },
          desc = "The border of a debuff nothing can dispel, while Debuff border color is Dispel type color.",
          disabled = function(get) return (dis and dis(get)) or get(k("debuff")) ~= "dispel" end },
        { type = "dropdown", key = k("buff"), label = "Buff border color", since = "2.4.1", disabled = dis,
          values = { plain = "Plain", accent = "Accent color", class = "Class color", custom = "One color" },
          order = { "plain", "accent", "class", "custom" },
          desc = "Plain is the frame's own dark border. Accent color follows your accent (General > Appearance), Class color is your class's." },
        { type = "color", key = k("color"), label = "Custom buff border color", since = "2.4.1", disabled = dis,
          desc = "The buffs' border when Buff border color is One color.",
          hidden = function(get) return get(k("buff")) ~= "custom" end },
    }
    if glow then
        items[#items + 1] = { type = "toggle", key = k("glow"), label = "Dispel and purge glow", since = "2.4.1", disabled = dis,
            desc = "A soft light behind a debuff you can dispel and a buff you can purge or steal. Turn it off for plain icons." }
    end
    return { label = "Icon borders", desc = "The border round this frame's buff and debuff icons.", items = items }
end

local function auraCards(k, gate)
    local AG, Spots = ns.AuraGroups, ns.Spots
    local cards = {}
    for _, def in ipairs(AG.DEFS) do
        local function g(key) return k("auras." .. def.key .. "." .. key) end
        local dis = offAny(gate, g("show"))
        local kind = GROUP_KINDS[def.key] or { one = def.label, many = string.lower(def.label) }
        local items = { { type = "toggle", key = g("show"), label = "Show " .. string.lower(def.label),
            desc = "Shows " .. string.lower(kind.one) .. " icons on each member.", disabled = off(gate) } }
        if #def.choices > 1 then
            local values, order = filterValues(def)
            items[#items + 1] = { type = "dropdown", key = g("which"), label = kind.one .. " filter", values = values,
                                  desc = "Which " .. string.lower(def.label) .. " show.", order = order, disabled = dis }
        end
        local what = def.key == "buffs" and "buffs" or "debuffs"
        local keyOf = def.key == "cc" and function(f) return f == "hide" and g(f) or nil end or g
        for _, it in ipairs(auraListRows(keyOf, what, def.key == "buffs", dis, nil, kind.one)) do items[#items + 1] = it end
        groupRows(items, g, dis, offAny(gate, g("show"), g("timers")), nil, kind)
        if def.key == "cc" and AG.Refused(def, "cc") then
            for _, it in ipairs(items) do it.hidden = function() return true end end
        end
        -- Private auras (GroupPrivate.lua): the client draws them, this only
        -- provides the spot. The switch sits with the debuffs.
        if def.key == "debuffs" then
            items[#items + 1] = { type = "toggle", key = k("privateAuras"), label = "Show hidden boss debuffs",
                desc = "The boss debuffs addons can't read, drawn by the game: up to two big icons in the middle, with a sweep for the time left. They only appear when a boss uses them.",
                disabled = off(gate) }
        end
        cards[#cards + 1] = { label = def.label, desc = def.desc, items = items }
        if def.key == "buffs" then
            for _, card in ipairs(indicatorCards(k, gate)) do cards[#cards + 1] = card end
        end
    end
    cards[#cards + 1] = borderCard(k, gate)
    return cards
end

-- Raid sizes (Raid.lua): the Raid 20 and Raid 40 pages open with this card.
-- Same as Raid 10 (on by default) uses the 10-player frames and grays out the
-- page's rows (raidLocked). Off, the size gets its own, starting as a copy.
-- "Copy from" (ns.CopyFrame): a card at the end of each frame's page. id is
-- the page's settings key, hidden (optional) hides the card.
local COPY_NAMES = { player = "Player", target = "Target", focus = "Focus", targettarget = "Target of Target", focustarget = "Focus Target",
                     pet = "Pet", party = "Party", raid = "Raid 10", raid20 = "Raid 20", raid40 = "Raid 40",
                     arena = "PvP Frames", partyTarget = "Party Targets" }
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
        { type = "toggle", key = rowKey("growCenter"), since = "2.2.4", label = "Grow from the middle", disabled = gate,
          desc = "The frames start from the middle of the line instead of its end, so a group that isn't full stays centered.",
          get = function() return read("growCenter") == true end,
          set = function(v) write("growCenter", v == true) end,
          default = function() return false end },
    }
end

-- These rows still work while it follows (anySize).
local function raidSizeCard(size)
    local R = ns.Raid
    return { label = "Raid size", desc = string.format("Raid frames for %s players, swapped in as the raid grows.", size == 20 and "11 to 20" or "21 to 40"), items = {
        { type = "toggle", label = "Same as Raid 10", anySize = true, disabled = off("raid.enabled"),
          desc = "Uses the Raid 10 frames, and the rest of this page is hidden. Turn it off to give this raid size its own, starting from a copy of Raid 10.",
          get = function() return R.Locked(size) end,
          set = function(v) R.SetFollow(size, v == true) end,
          default = function() return true end },
        { type = "toggle", key = "raid" .. size .. ".ownSpot", label = "Raid " .. size .. " own position", anySize = true, disabled = off("raid.enabled"),
          desc = string.format("Raid %d frames sit in a spot of their own, with their own handle when you unlock (/dui unlock), so a bigger raid can go where it fits. When off, they sit where Raid 10's do.", size) },
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
            desc = "Sets the auras and name on this page's raid frames to the " .. label .. " look. Click twice to confirm.",
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
    local one = kind == "buff" and "Buff" or "Debuff"
    return {
        { type = "dropdown", key = k("Spot"), label = one .. " position", values = ns.Spots.LABELS, order = ns.Spots.ORDER,
          desc = "Where the " .. kind .. " icons sit, on or around the frame. When debuffs and buffs share a spot over or under the frame, the buffs sit nearest it. Outside spots may need room around the frame.",
          disabled = dis },
        { type = "dropdown", key = k("Grow"), label = one .. " grow direction", values = ns.Spots.GROW_LABELS,
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
-- (no "mine, then others" on yourself). own = "pet": the same, with a buff
-- filter of all or only yours.
local function unitAuraCards(prefix, own, desc)
    local k = function(s) return prefix .. "." .. s end
    local dOff, bOff = off(k("debuffs")), off(k("buffs"))
    local debuffs = {
        { type = "toggle", key = k("debuffs"), label = "Show debuffs", desc = "Debuff icons by this frame." },
        { type = "slider", key = k("debuffSize"), label = "Debuff size", min = 16, max = 48, step = 1, unit = "px",
          desc = "How big each debuff icon is.", disabled = dOff },
    }
    if own then
        debuffs[#debuffs + 1] = { type = "dropdown", key = k("debuffFilter"), label = "Debuff filter", since = "1.8.0",
            values = { all = "All debuffs", dispel = "Only ones I can dispel" }, order = { "all", "dispel" },
            desc = own == "pet" and "Every debuff on your pet, or only the ones your class can remove."
                or "Every debuff on you, or only the ones your class can remove.", disabled = dOff }
        debuffs[#debuffs + 1] = { type = "slider", key = k("maxDebuffs"), label = "Debuff max shown", min = 1, max = 16, step = 1,
                                  desc = "The most debuff icons at once.", disabled = dOff }
    else
        debuffs[#debuffs + 1] = { type = "dropdown", key = k("debuffFilter"), label = "Debuff filter", since = "1.8.0",
            values = { mine = "Only mine", all = "Mine first, then others" }, order = { "mine", "all" },
            desc = "Only the debuffs you put on it, or yours first and then everyone else's.", disabled = dOff }
        debuffs[#debuffs + 1] = { type = "slider", key = k("maxDebuffs"), label = "Max of my debuffs", min = 1, max = 16, step = 1,
                                  desc = "The most of your own debuffs shown at once.", disabled = dOff }
        debuffs[#debuffs + 1] = { type = "slider", key = k("maxOtherDebuffs"), label = "Max debuffs from others", min = 0, max = 16,
            step = 1, desc = "The most debuffs from other players, shown after yours. Only with Mine first, then others.",
            disabled = function(get) return get(k("debuffs")) ~= true or get(k("debuffFilter")) ~= "all" end }
    end
    debuffs[#debuffs + 1] = { type = "slider", key = k("debuffSpacing"), label = "Debuff spacing", min = 0, max = 12, step = 1,
                              desc = "The gap between debuff icons.", unit = "px", disabled = dOff }
    debuffs[#debuffs + 1] = { type = "slider", key = k("debuffRows"), label = "Debuff rows", min = 1, max = 6, step = 1,
                              desc = "The debuffs wrap onto up to this many rows.", disabled = dOff }
    debuffs[#debuffs + 1] = { type = "slider", key = k("debuffPerRow"), label = "Debuffs per row", since = "1.9.5", min = 0, max = 16, step = 1,
                              desc = "How many debuff icons sit side by side before the next row starts. 0 fits them to the frame's width.",
                              disabled = dOff }
    debuffs[#debuffs + 1] = { type = "slider", key = k("debuffTimeSize"), label = "Debuff time left text size", min = 6, max = 20, step = 1,
                              desc = "How big the time left is on each debuff icon.", disabled = dOff }
    debuffs[#debuffs + 1] = { type = "slider", key = k("debuffCountSize"), label = "Debuff stack count size", min = 6, max = 20, step = 1,
                              desc = "How big the number of stacks is on each debuff icon.", disabled = dOff }
    local buffs = {
        { type = "toggle", key = k("buffs"), label = "Show buffs", desc = "Buff icons by this frame." },
        { type = "slider", key = k("buffSize"), label = "Buff size", min = 12, max = 36, step = 1, unit = "px",
          desc = "How big each buff icon is.", disabled = bOff },
        { type = "slider", key = k("maxBuffs"), label = "Buff max shown", min = 1, max = 12, step = 1,
          desc = "The most buff icons at once.", disabled = bOff },
        { type = "slider", key = k("buffSpacing"), label = "Buff spacing", min = 0, max = 12, step = 1, unit = "px",
          desc = "The gap between buff icons.", disabled = bOff },
        { type = "slider", key = k("buffRows"), label = "Buff rows", min = 1, max = 6, step = 1,
          desc = "The buffs wrap onto up to this many rows.", disabled = bOff },
        { type = "slider", key = k("buffPerRow"), label = "Buffs per row", since = "1.9.5", min = 0, max = 16, step = 1,
          desc = "How many buff icons sit side by side before the next row starts. 0 fits them to the frame's width.",
          disabled = bOff },
        { type = "slider", key = k("buffTimeSize"), label = "Buff time left text size", min = 6, max = 20, step = 1,
          desc = "How big the time left is on each buff icon.", disabled = bOff },
        { type = "slider", key = k("buffCountSize"), label = "Buff stack count size", min = 6, max = 20, step = 1,
          desc = "How big the number of stacks is on each buff icon.", disabled = bOff },
    }
    if own == "pet" then
        table.insert(buffs, 3, { type = "dropdown", key = k("buffFilter"), label = "Buff filter", since = "1.8.0",
            values = { all = "All buffs", mine = "Only mine" }, order = { "all", "mine" }, disabled = bOff,
            desc = "Every buff on your pet, or only the ones you cast on it." })
    elseif not own then
        table.insert(buffs, 3, { type = "dropdown", key = k("buffFilter"), label = "Buff filter", since = "1.8.0",
            values = { all = "All buffs", purge = "Only ones I can purge or steal", mine = "Only mine" },
            order = { "all", "purge", "mine" }, disabled = bOff,
            desc = "Every buff, only the ones your class can take off an enemy, or only the ones you cast. A class that can't purge shows none with the second." })
    end
    -- Time numbers, sweep and tooltips: the same switches the party and raid icons have.
    local function look(list, kind, show)
        local dis = off(k(show))
        local one = kind == "buff" and "Buff" or "Debuff"
        list[#list + 1] = { type = "toggle", key = k(kind .. "Timers"), label = "Time left on " .. show, since = "1.8.0",
                            desc = "The time left as a number on each icon.", disabled = dis }
        list[#list + 1] = { type = "toggle", key = k(kind .. "ShortTimers"), label = one .. " time left only under a minute", since = "1.8.0",
                            desc = "Hides the number while a minute or more is left, so long ones stay quiet.",
                            disabled = offAny(k(show), k(kind .. "Timers")) }
        list[#list + 1] = { type = "toggle", key = k(kind .. "Swipe"), label = one .. " cooldown swipe", since = "1.8.0",
                            desc = "Each icon darkens like a clock as its time runs out.", disabled = dis }
        list[#list + 1] = { type = "toggle", key = k(kind .. "Tips"), label = one .. " tooltip on hover", since = "1.8.0",
                            desc = "Hovering an icon says what it is. When off, the mouse goes straight through to what's behind it.",
                            disabled = dis }
    end
    -- Aura lists right after each row's filter (the third row).
    local function lists(list, kind, what, only)
        local keyOf = function(f) return k(kind .. f:sub(1, 1):upper() .. f:sub(2)) end
        for i, it in ipairs(auraListRows(keyOf, what, only, off(k(what)), nil, nil, not own)) do table.insert(list, 3 + i, it) end
    end
    lists(debuffs, "debuff", "debuffs", not own)
    lists(buffs, "buff", "buffs", true)
    look(debuffs, "debuff", "debuffs")
    look(buffs, "buff", "buffs")
    for _, it in ipairs(spotItems(prefix, "debuff", k("debuffs"))) do debuffs[#debuffs + 1] = it end
    for _, it in ipairs(spotItems(prefix, "buff", k("buffs"))) do buffs[#buffs + 1] = it end
    return { { label = "Debuffs", desc = desc.debuffs, items = debuffs },
             { label = "Buffs", desc = desc.buffs, items = buffs },
             borderCard(k, nil, not own) }
end

local TARGET_AURA_GROUPS = unitAuraCards("targetAuras", false, {
    debuffs = "Over the frame from its right end by default. Yours come first.",
    buffs = "Small icons over the frame from its left end by default." })
-- Off by default, since the buff bars by the info panel show the same.
local PLAYER_AURA_GROUPS = unitAuraCards("playerAuras", true, {
    debuffs = "Every debuff on you, over your frame from its right end. Your buff bars show them too.",
    buffs = "Small icons over your frame from its left end. Your buff bars show them too." })

local FOCUS_AURA_GROUPS = unitAuraCards("focusAuras", false, {
    debuffs = "Over the focus from its right end. Only yours by default.",
    buffs = "Small icons over the focus from its left end." })

local PET_AURA_GROUPS = unitAuraCards("petAuras", "pet", {
    debuffs = "Every debuff on your pet, under its frame.",
    buffs = "Small icons under your pet's frame." })

-- The personal display's own rows, dimmed with the display.
local PERSONAL_AURA_GROUPS = unitAuraCards("personal.auras", true, {
    debuffs = "Every debuff on you, by your personal display.",
    buffs = "Buff icons by your personal display." })

-- Each frame's aura rows dim with the frame itself, as its other cards do.
local function dimWith(cards, key)
    for _, card in ipairs(cards) do
        for _, item in ipairs(card.items) do
            local was = item.disabled
            item.disabled = function(get) return get(key) ~= true or (was ~= nil and was(get)) end
        end
    end
end
dimWith(PERSONAL_AURA_GROUPS, "personal.enabled")
dimWith(PLAYER_AURA_GROUPS, "player.enabled")
dimWith(TARGET_AURA_GROUPS, "target.enabled")
dimWith(FOCUS_AURA_GROUPS, "focus.enabled")
dimWith(PET_AURA_GROUPS, "pet.enabled")

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
        mediaRow("back", key .. "Back", label .. " background texture", "The empty part of " .. what .. ", behind the fill." .. GENERAL_BACK, dis) }
end
local function fontRow(key, label, what, dis)
    return mediaRow("font", key, label, what .. "." .. GENERAL_FONT, dis)
end
-- Which frame strata a piece draws in (ns.STRATA), for frames that overlap.
local STRATA_HOW = " Where two pieces overlap, the higher layer draws on top: Background, Low, Medium, High, then Dialogue."
local function strataRow(key, label, what, dis, more, withFrame)
    return { type = "dropdown", key = key, label = label,
             values = withFrame and ns.CASTBAR_STRATA_LABELS or ns.STRATA_LABELS,
             order = withFrame and ns.CASTBAR_STRATA or ns.STRATA,
             desc = what .. STRATA_HOW .. (more or ""), disabled = dis }
end

-- The swing timer's group rows that only apply detached as a group.
local function groupAttached(get) return get("swing.enabled") ~= true or get("swing.attach") == true end

-- Each swing bar detached on its own: a "Settings for" card showing one bar's
-- rows at a time (swing.bars.<hand>), each with its own handle in /dui unlock.
local SWING_HANDS = { { "main", "Main hand", "swing.mainHand" }, { "off", "Off hand", "swing.offHand" },
                      { "ranged", "Ranged", "swing.ranged" } }
local SWING_BAR_FIELDS = { "visibility", "width", "height", "textSize", "showName", "showTime", "showIcon", "slant", "slantUnder", "slantUnderLeft", "ownAngle", "lean", "reverseFill" }
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
            { type = "dropdown", key = b("visibility"), label = name .. " bar visibility",
              values = { swinging = "While swinging", combat = "In combat", always = "Always" },
              order = { "swinging", "combat", "always" },
              desc = "While swinging: only while its swing runs. In combat: while you're fighting. Only when detached on its own.",
              disabled = dis, hidden = attached },
            { type = "slider", key = b("width"), label = name .. " bar width", min = 80, max = 500, step = 1,
              desc = "How wide the " .. lower .. " bar is. Only when detached on its own.", disabled = dis, hidden = attached },
            { type = "slider", key = b("height"), label = name .. " bar height", min = 6, max = 30, step = 1, unit = "px",
              desc = "How tall the " .. lower .. " bar is. Only when detached on its own.", disabled = dis, hidden = attached },
            { type = "slider", key = b("textSize"), label = name .. " bar text size", min = 6, max = 24, step = 1,
              desc = "The hand and time on the bar. Only when detached on its own.", disabled = dis, hidden = attached },
            { type = "toggle", key = b("showName"), label = name .. " bar name",
              desc = "The hand (or the queued attack, or the range) written on the bar, attached or detached.",
              disabled = textOff },
            { type = "toggle", key = b("showTime"), label = name .. " bar time left",
              desc = "The time to the next swing, written on the bar, attached or detached.", disabled = textOff },
            { type = "toggle", key = b("showIcon"), label = name .. " bar weapon icon",
              desc = "The weapon's picture at the start of the bar. Only when detached on its own.", disabled = dis, hidden = attached },
            DaylightUI.Options.EndRows({ name = name .. " bar", note = "Only when detached on its own.", disabled = dis, hidden = attached,
                left = { on = b("slantLeft"), flip = b("slantUnderLeft") }, right = { on = b("slant"), flip = b("slantUnder") } })[1],
            DaylightUI.Options.EndRows({ name = name .. " bar", note = "Only when detached on its own.", disabled = dis, hidden = attached,
                left = { on = b("slantLeft"), flip = b("slantUnderLeft") }, right = { on = b("slant"), flip = b("slantUnder") } })[2],
            angleRows({ own = b("ownAngle"), lean = b("lean"), name = name .. " bar", what = "the " .. lower .. " bar's", since = "2.0",
                        note = "Only when detached on its own.", hidden = attached,
                        disabled = function(get) return dis(get) or (get(b("slant")) ~= true and get(b("slantLeft")) ~= true) end })[1],
            angleRows({ own = b("ownAngle"), lean = b("lean"), name = name .. " bar", what = "the " .. lower .. " bar's", since = "2.0",
                        note = "Only when detached on its own.", hidden = attached,
                        disabled = function(get) return dis(get) or (get(b("slant")) ~= true and get(b("slantLeft")) ~= true) end })[2],
            { type = "toggle", key = b("reverseFill"), label = name .. " bar fills right to left",
              desc = "The " .. lower .. " bar fills from the right. Only when detached on its own.", disabled = dis, hidden = attached },
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
-- bar's rows. "global" follows the Look page.
local HEALTH_COLORS = { global = "Same as the Look page", class = "Class and reaction", classGradient = "Class gradient",
    gradient = "By health (green to red)", custom = "One color", customGradient = "Custom gradient",
    dark = "Dark (missing health colored)" }
local HEALTH_COLOR_ORDER = { "global", "class", "classGradient", "gradient", "custom", "customGradient", "dark" }
-- Your own frame can also take the Daylight gradient or your accent.
local PLAYER_HEALTH_COLORS = { daylight = "Daylight gradient", accent = "Accent color" }
local PLAYER_HEALTH_ORDER = { "global", "daylight", "accent" }
for k, v in pairs(HEALTH_COLORS) do PLAYER_HEALTH_COLORS[k] = v end
for i = 2, #HEALTH_COLOR_ORDER do PLAYER_HEALTH_ORDER[#PLAYER_HEALTH_ORDER + 1] = HEALTH_COLOR_ORDER[i] end
local POWER_COLORS = { global = "Same as the Look page", type = "By power type", gradient = "Power gradient",
    custom = "One color", customGradient = "Custom gradient" }
local POWER_COLOR_ORDER = { "global", "type", "gradient", "custom", "customGradient" }

-- The color rows of a bar's custom gradient, shown while its color menu (key)
-- is on Custom gradient.
local function stopsRows(key, menu, what, bar, dis)
    return DaylightUI.Options.StopsRows(key, { what = what, bar = bar, disabled = dis, since = "2.2",
        shown = function(get) return get(menu) == "customGradient" end })
end

local function healthColorRows(id, dis)
    local k = function(s) return id .. "." .. s end
    return DaylightUI.Options.Join({
        { type = "dropdown", key = k("colorHealth"), label = "Health bar color",
          values = id == "player" and PLAYER_HEALTH_COLORS or HEALTH_COLORS,
          order = id == "player" and PLAYER_HEALTH_ORDER or HEALTH_COLOR_ORDER, disabled = dis,
          desc = id == "player"
              and "Your frame's own health color, so it can look unlike the others. Same as the Look page follows the color every frame shares; Daylight gradient is the logo's blue to orange; Accent color follows your accent on General > Appearance, gradient included."
              or "This frame's own health color, so it can look unlike the others. Same as the Look page follows the color every frame shares." },
        { type = "color", key = k("colorHealthCustom"), label = "Custom health color", disabled = dis,
          desc = "The health bar's color when Health bar color is One color.",
          hidden = notCustom(k("colorHealth")) },
    }, stopsRows(k("colorHealthGradient"), k("colorHealth"), "health", "the health bar", dis))
end

local function powerColorRows(id, dis)
    local k = function(s) return id .. "." .. s end
    return DaylightUI.Options.Join({
        { type = "dropdown", key = k("colorPower"), label = "Power bar color", values = POWER_COLORS,
          order = POWER_COLOR_ORDER, disabled = dis,
          desc = "This frame's own power color. Same as the Look page follows the color every frame shares." },
        { type = "color", key = k("colorPowerCustom"), label = "Custom power color", disabled = dis,
          desc = "The power bar's color when Power bar color is One color.",
          hidden = notCustom(k("colorPower")) },
    }, stopsRows(k("colorPowerGradient"), k("colorPower"), "power", "the power bar", dis))
end

-- The empty part of one bar on this frame (bar "Health" or "Power"): its own
-- color and opacity, or the Look page's.
local BACK_COLORS = { global = "Same as the Look page", dim = "Dimmed bar color", custom = "One color" }
local BACK_COLOR_ORDER = { "global", "dim", "custom" }
local function backColorRows(id, bar, dis)
    local key = id .. ".back" .. bar
    local what = string.lower(bar)
    local shared = function(get) return get(key) ~= "dim" and get(key) ~= "custom" end
    return {
        { type = "dropdown", key = key, label = bar .. " background color", values = BACK_COLORS,
          order = BACK_COLOR_ORDER, disabled = dis,
          desc = "The empty part of this frame's " .. what .. " bar, behind the fill: a darker copy of the bar's color, or one you pick. Same as the Look page follows the look every frame shares." },
        { type = "slider", key = key .. "Bright", label = bar .. " background brightness", min = 0, max = 1, step = 0.05,
          unit = "%", disabled = dis, hidden = function(get) return get(key) ~= "dim" end,
          desc = "How much of the bar's color the empty part keeps. Lower is darker." },
        { type = "color", key = key .. "Color", label = "Custom " .. what .. " background color", disabled = dis,
          hidden = notCustom(key),
          desc = "The empty part's color when " .. bar .. " background color is One color." },
        { type = "slider", key = key .. "Alpha", label = bar .. " background opacity", min = 0, max = 1, step = 0.05,
          unit = "%", disabled = dis, hidden = shared,
          desc = "How solid the empty part of this frame's " .. what .. " bar is. Lower lets the world show through it." },
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
        DaylightUI.Options.MediaPick("back", key .. "Back", label .. " background texture", "The empty part of the bar, behind the fill." .. follow,
            { disabled = dis, follows = { slot = slot .. ".back", label = "Player frame" } }),
    }
    local values, order = { player = "Player frame" }, { "player" }
    local from = bar == "health" and PLAYER_HEALTH_COLORS or POWER_COLORS
    for _, k in ipairs(bar == "health" and PLAYER_HEALTH_ORDER or POWER_COLOR_ORDER) do
        values[k], order[#order + 1] = from[k], k
    end
    local mode = bar == "health" and "personal.colorHealth" or "personal.colorPower"
    rows[3] = { type = "dropdown", key = mode, label = label .. " color", values = values, order = order, disabled = dis,
                desc = "The bar's own color, so it can look unlike your player frame. Same as the Look page follows the color every frame shares." }
    rows[4] = { type = "color", key = mode .. "Custom", label = "Custom " .. bar .. " color", disabled = dis,
                desc = "The bar's color when it's set to One color.", hidden = notCustom(mode) }
    return DaylightUI.Options.Join(rows, stopsRows(mode .. "Gradient", mode, bar, "the " .. bar .. " bar", dis))
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
        { type = "toggle", key = k("showPercent"), label = "Personal health text",
          desc = "Your health written on the personal display's health bar.",
          disabled = offAny("personal.enabled", k("showHealth")) },
        { type = "dropdown", key = k("healthText"), label = "Personal health text format", values = UF.HEALTH_FORMATS,
          order = UF.HEALTH_FORMAT_ORDER, desc = "How the health text is written. Missing health shows nothing while you're at full.", disabled = health },
        { type = "toggle", key = k("percentSign"), label = "Personal health text % sign",
          desc = "62% rather than 62, when the health text shows a percent.", disabled = signOff(health, k("healthText")) },
        { type = "toggle", key = k("hideFullHealth"), invert = true, label = "Show personal health text at full",
          desc = "The health text shows at full health too. When off, it disappears while you're at full.", disabled = health },
        { type = "dropdown", key = k("healthTextPos"), label = "Personal health text position", values = UF.POWER_TEXT_POS,
          order = UF.POWER_TEXT_POS_ORDER, desc = "Where along the health bar the health text sits.", disabled = health },
        { type = "slider", key = k("healthTextSize"), label = "Personal health text size", min = 0, max = 24, step = 1,
          desc = "How big the health text is. 0 fits it to the bar.", disabled = health },
        font("health", "Personal health text font", health),
        { type = "toggle", key = k("showPowerText"), label = "Personal power text",
          desc = "Your mana, rage or energy written on the personal display's power bar.",
          disabled = offAny("personal.enabled", k("showPower")) },
        { type = "dropdown", key = k("powerFormat"), label = "Personal power text format", values = UF.POWER_FORMATS,
          order = UF.POWER_FORMAT_ORDER, desc = "How the power text is written.", disabled = power },
        { type = "toggle", key = k("powerPercentSign"), label = "Personal power text % sign",
          desc = "80% rather than 80, when the power text shows a percent.", disabled = signOff(power, k("powerFormat")) },
        { type = "toggle", key = k("hideFullPower"), invert = true, label = "Show personal power text at full",
          desc = "The power text shows while mana, rage or energy is full too. When off, it disappears at full.", disabled = power },
        { type = "dropdown", key = k("powerTextPos"), label = "Personal power text position", values = UF.POWER_TEXT_POS,
          order = UF.POWER_TEXT_POS_ORDER, desc = "Where along the power bar the power text sits.", disabled = power },
        { type = "slider", key = k("powerTextSize"), label = "Personal power text size", min = 0, max = 24, step = 1,
          desc = "How big the power text is. 0 fits it to the bar.", disabled = power },
        font("power", "Personal power text font", power),
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
-- Only with a name tab (a style's name row has no shell), while the name is in it.
local TAB_SLANTS = { frame = "Same as the frame", on = "Angled", off = "Straight" }
local TAB_AT = { outer = "Outer end", middle = "Middle", inner = "Inner end" }
local TAB_WIDTHS = { fit = "Fit the name", full = "Full width", fixed = "Fixed width" }
local TAB_ALIGNS = { left = "Left", center = "Center", right = "Right" }
local TAB_COLORS = { dark = "Dark", class = "Your class", accent = "Accent", custom = "Custom" }

local function tabCard(id, onRow)
    local k = function(s) return id .. ".tab." .. s end
    local f = function(s) return id .. "." .. s end
    local noTab = function(get)
        return get(f("enabled")) == false or get(f("showName")) == false or get(f("nameOnBar")) == true
    end
    local dis = function(get) return noTab(get) or get(k("own")) ~= true end
    return { label = "Name tab",
        desc = "The small tab that holds the name above the frame: its own border, corners, shadow, place and width.",
        items = {
            { type = "toggle", key = k("own"), label = "Own name tab look", disabled = noTab, hidden = onRow,
              desc = "Gives the name tab the border, corners and shadow below. When off, it matches the frame." },
            { type = "slider", key = k("borderPx"), label = "Name tab border thickness", min = 0, max = 16, step = 1,
              desc = "How thick the name tab's outline is. 0 leaves none.", unit = "px", disabled = dis, hidden = onRow },
            { type = "slider", key = k("cornerPx"), label = "Name tab corner rounding", min = 0, max = 24, step = 1,
              desc = "How round the name tab's corners are. 0 keeps them sharp.", unit = "px", disabled = dis, hidden = onRow },
            { type = "slider", key = k("shadowPx"), label = "Name tab shadow size", min = 0, max = 12, step = 1,
              desc = "How far the name tab's shadow spreads. 0 leaves no shadow.", unit = "px", disabled = dis, hidden = onRow },
            { type = "dropdown", key = k("slant"), label = "Name tab angled end", values = TAB_SLANTS,
              desc = "Whether the name tab's end is cut at an angle. Same as the frame follows the frame's own end.",
              order = { "frame", "on", "off" }, disabled = noTab, hidden = onRow },
            { type = "dropdown", key = k("at"), label = "Name tab position", values = TAB_AT,
              order = { "outer", "middle", "inner" },
              desc = "Where along the frame's top the tab sits. A full-width tab always starts at the outer end. Or drag the tab in Design mode.",
              disabled = function(get) return noTab(get) or get(k("width")) == "full" end, hidden = onRow },
            { type = "slider", key = k("x"), label = "Name tab left / right", min = -100, max = 100, step = 1,
              desc = "Nudges the name tab sideways along the frame's top.", unit = "px", disabled = noTab, hidden = onRow },
            { type = "slider", key = k("y"), label = "Name tab up / down", min = -10, max = 40, step = 1, unit = "px",
              desc = "Lift the tab off the frame to float it above with a gap.", disabled = noTab, hidden = onRow },
            { type = "dropdown", key = k("width"), label = "Name tab width", values = TAB_WIDTHS,
              order = { "fit", "full", "fixed" },
              desc = "Fit the name grows and shrinks with each name. Full width runs along the whole top of the frame.",
              disabled = noTab, hidden = onRow },
            { type = "slider", key = k("widthPx"), label = "Fixed name tab width", min = 30, max = 400, step = 1,
              desc = "How wide the name tab is when Name tab width is Fixed width.", unit = "px", disabled = function(get) return noTab(get) or get(k("width")) ~= "fixed" end, hidden = onRow },
            { type = "slider", key = f("tabHeight"), label = "Name tab height", min = 10, max = 28, step = 1, unit = "px",
              desc = "How tall the tab holding the name above the frame is.",
              disabled = function(get) return get(f("enabled")) ~= true end, hidden = onRow },
            { type = "dropdown", key = k("align"), label = "Name alignment in the tab", values = TAB_ALIGNS,
              desc = "Where the name sits inside its tab: left, center or right.",
              order = { "left", "center", "right" }, disabled = noTab, hidden = onRow },
            { type = "dropdown", key = k("color"), since = "2.2.1", label = "Name tab color", values = TAB_COLORS,
              order = { "dark", "class", "accent", "custom" },
              desc = "The color behind the name: dark like the frame, your class color, the accent, or a color you pick, to match a themed UI.",
              disabled = noTab, hidden = onRow },
            { type = "color", key = k("colorCustom"), since = "2.2.1", label = "Custom name tab color",
              desc = "The color behind the name when Name tab color is Custom.",
              disabled = function(get) return noTab(get) or get(k("color")) ~= "custom" end, hidden = onRow },
        } }
end

local function petCard()
    local p = function(s) return "partyPet." .. s end
    local petOff = offAny("party.enabled", p("enabled"))
    return { label = "Pets", desc = "A small bar beside each party member who has a pet out. Your own pet keeps its own frame.", items = {
        { type = "toggle", key = p("enabled"), label = "Show pets", disabled = off("party.enabled"),
          desc = "A small pet bar beside each party member whose pet is out." },
        { type = "dropdown", key = p("spot"), label = "Pet position", values = ns.PartyPets.SPOTS, order = ns.PartyPets.SPOT_ORDER,
          desc = "Which side of its owner's frame each pet bar sits on.", disabled = petOff },
        { type = "slider", key = p("x"), label = "Pets left / right", min = -50, max = 50, step = 1, unit = "px",
          desc = "Nudges the pet bars sideways from their position.", disabled = petOff },
        { type = "slider", key = p("y"), label = "Pets up / down", min = -50, max = 50, step = 1, unit = "px",
          desc = "Nudges the pet bars up or down from their position.", disabled = petOff },
        { type = "slider", key = p("width"), label = "Pet width", min = 20, max = 200, step = 1,
          desc = "How wide each pet bar is.", disabled = petOff },
        { type = "slider", key = p("height"), label = "Pet height", min = 10, max = 120, step = 1,
          desc = "How tall each pet bar is. It can be as tall as a party frame, for a narrow pet bar standing beside each member.", disabled = petOff },
        { type = "toggle", key = p("fillVertical"), label = "Pets fill upward",
          desc = "Each pet's health bar fills bottom to top instead of across, for tall, narrow pet bars.", disabled = petOff },
        barRows(p("media.health"), "the pets' health bars", "Pet health bar", petOff)[1],
        barRows(p("media.health"), "the pets' health bars", "Pet health bar", petOff)[2],
        frameEndRows("partyPet", "partyPet", "Pet bar", petOff)[1],
        frameEndRows("partyPet", "partyPet", "Pet bar", petOff)[2],
        { type = "dropdown", key = p("color"), label = "Pet bar color", values = ns.PartyPets.COLORS, order = ns.PartyPets.COLOR_ORDER,
          desc = "Its owner's class tells at a glance whose pet it is.", disabled = petOff },
        { type = "toggle", key = p("showPower"), label = "Pet power bar",
          desc = "A thin power bar under each pet's health.", disabled = offAny("party.enabled", p("enabled")) },
        { type = "slider", key = p("powerHeight"), label = "Pet power bar height", min = 2, max = 12, step = 1,
          desc = "How tall the pets' power bars are.", disabled = offAny("party.enabled", p("enabled"), p("showPower")) },
        barRows(p("media.power"), "the pets' power bars", "Pet power bar", offAny("party.enabled", p("enabled"), p("showPower")))[1],
        barRows(p("media.power"), "the pets' power bars", "Pet power bar", offAny("party.enabled", p("enabled"), p("showPower")))[2],
        { type = "toggle", key = p("showName"), label = "Pet name",
          desc = "Shows each pet's name.", disabled = petOff },
        { type = "slider", key = "partyPetText.name", label = "Pet name size", min = 6, max = 24, step = 1,
          desc = "How big the pets' names are.", disabled = offAny("party.enabled", p("enabled"), p("showName")) },
        fontRow(p("media.nameFont"), "Pet name font", "The pets' names", offAny("party.enabled", p("enabled"), p("showName"))),
        { type = "toggle", key = p("showPercent"), label = "Pet health text",
          desc = "Shows each pet's health as text.", disabled = petOff },
        { type = "dropdown", key = p("healthText"), label = "Pet health text format",
          values = UF.HEALTH_FORMATS, order = UF.HEALTH_FORMAT_ORDER, desc = "How the pets' health text is written.",
          disabled = offAny("party.enabled", p("enabled"), p("showPercent")) },
        { type = "dropdown", key = p("healthTextPos"), label = "Pet health text position",
          values = UF.POWER_TEXT_POS, order = UF.POWER_TEXT_POS_ORDER, desc = "Where along each pet's bar the health text sits.",
          disabled = offAny("party.enabled", p("enabled"), p("showPercent")) },
        { type = "slider", key = "partyPetText.percent", label = "Pet health text size", min = 6, max = 24, step = 1,
          desc = "How big the pets' health text is.", disabled = offAny("party.enabled", p("enabled"), p("showPercent")) },
        fontRow(p("media.healthFont"), "Pet health text font", "The pets' health text", offAny("party.enabled", p("enabled"), p("showPercent"))),
    } }
end

-- The frames' style (Defaults.lua, UF.StyleOf). A pick writes through
-- ns.SetStyle, so each frame takes that style's own heights before anything
-- redraws. own: a frame's pick, which can follow the Look page's.
local function styleDesc()
    local parts = {}
    for _, key in ipairs(ns.STYLE_ORDER) do parts[#parts + 1] = ns.STYLES[key].desc end
    return table.concat(parts, " ")
end
-- The current settings, for a row that asks outside its page's get.
local function liveGet(key) return DaylightUI:Get("UnitFrames", key) end

-- Every Frame style row, so a plugin's style (ns.TakePluginStyles) joins
-- their menus, the setup guide's cards and their descriptions. The tables are
-- filled in place: the guide and the options panel keep the row's own.
local styleRows = {}
local function fillStyleRow(row)
    local values, order = row.values, row.order
    for k in pairs(values) do values[k] = nil end
    for i = #order, 1, -1 do order[i] = nil end
    if row.ownPick then
        values.global = "Default"
        order[1] = "global"
    end
    for _, s in ipairs(ns.STYLE_ORDER) do
        values[s] = ns.STYLES[s].label
        order[#order + 1] = s
    end
    row.desc = styleDesc() .. (row.ownPick
        and " Default uses the style set for every frame on Unit Frames > Look. Each style keeps its own heights."
        or " Each frame can pick its own on its page.")
end
function ns.StyleRowsChanged()
    for _, row in ipairs(styleRows) do fillStyleRow(row) end
end

local function styleRow(key, own, dis)
    local values, order = {}, {}
    -- A frame's "Default" names the style it gives: "Default (Daylight)".
    local function choices()
        if not own then return values, order end
        local named = {}
        for s, label in pairs(values) do named[s] = label end
        named.global = "Default (" .. UF.StyleDef({ style = "global" }).label .. ")"
        return named, order
    end
    local row = { type = "dropdown", key = key, label = "Frame style", values = values, order = order, choices = choices,
             ownPick = own,
             get = function() return DaylightUI:Get("UnitFrames", key) end,
             set = function(v) ns.SetStyle(key, v) end,
             default = function() return own and "global" or "daylight" end,
             disabled = dis }
    fillStyleRow(row)
    styleRows[#styleRows + 1] = row
    return row
end

-- Tabs on a frame page: Basics first (position, size and shape, when it
-- shows), then its bars, text, auras and the rest. A card's tab is decided by
-- its title, and cards are sorted by tab while keeping their order within one.
local TAB_ORDER = { "Basics", "Bars", "Portrait", "Name", "Text", "Cast bar", "Auras", "Extras", "Layers" }
local TAB_OF = { Layers = "Layers", Portrait = "Portrait", ["Raid size"] = "Basics", ["Quick looks"] = "Basics", Layout = "Basics", Frame = "Basics", Position = "Basics",
    [DaylightUI.Fade.CARD_LABEL] = "Basics", ["Health and power"] = "Bars", ["Health bar"] = "Bars",
    ["Border and shadow"] = "Bars", ["Bar animation"] = "Bars", Text = "Text", Name = "Name", ["Name tab"] = "Name", Debuffs = "Auras", Buffs = "Auras",
    ["Heal indicators"] = "Auras", Dispels = "Auras", ["Icon borders"] = "Auras" }
local function tabOf(label)
    if TAB_OF[label] then return TAB_OF[label] end
    if string.find(label, "^Extra text") then return "Text" end
    if string.find(label, "^Extra aura group") then return "Auras" end
    for _, def in ipairs(ns.AuraGroups.DEFS) do
        if def.label == label then return "Auras" end
    end
    return "Extras"
end
-- The name's rows (TEXT_ORDER's first block) leave the Text card for a Name card of their
-- own, ahead of the name tab's, so everything about a frame's name is on the Name tab.
local NAME_ORDER_END = 30
local function nameCard(groups)
    local out, at, named = {}, nil, nil
    for _, g in ipairs(groups) do
        if g.label == "Text" and type(g.items) == "table" and not named then
            -- Only the rows TEXT_ORDER lists as the name's go to the Name card. A row it doesn't
            -- know stays on Text, so a text row added later can't slip onto the Name tab.
            local name, rest = {}, {}
            for _, it in ipairs(g.items) do
                local r = type(it.key) == "string" and TEXT_ORDER[fieldOf(it.key)]
                if r and r < NAME_ORDER_END then name[#name + 1] = it else rest[#rest + 1] = it end
            end
            if #name > 0 then
                named = { label = "Name", desc = "How this frame's name looks and where it sits: its text, color and size, and the tab behind it.", items = name }
                g.items = rest
            end
        end
    end
    for _, g in ipairs(groups) do
        if g.label == "Name tab" and named then out[#out + 1] = named; named = nil; at = true end
        if not (g.label == "Text" and #g.items == 0) then out[#out + 1] = g end
    end
    if named then
        -- No name tab card: the Name card sits where the Text card was.
        for i, g in ipairs(out) do
            if g.label == "Text" then table.insert(out, i, named); named = nil; break end
        end
    end
    if named then out[#out + 1] = named end
    return out
end
local function tabbed(groups)
    groups = nameCard(groups)
    local rank = {}
    for i, t in ipairs(TAB_ORDER) do rank[t] = i end
    local list = {}
    for i, g in ipairs(groups) do
        g.tab = g.tab or tabOf(g.label)
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
local BASIC_FIELDS = { enabled = true, style = true, width = true, height = true, spacing = true,
    tabHeight = true, slant = true, slantOuter = true, fillVertical = true,
    showInParty = true, direction = true, growLeft = true, growUp = true, growCenter = true, sortBy = true, groups = true, groupSpacing = true, perLine = true, hideSelf = true,
    strata = true }
-- The portrait's own rows get a card (and tab) of their own.
local PORTRAIT_FIELDS = { portrait = true, portraitShape = true, portraitLook = true, portraitAt = true, portraitIconsStay = true, portraitRing = true,
    portraitRingWidth = true, portraitRingLine = true, portraitDragon = true, portraitDragonColor = true, portraitScale = true }
local function splitFrame(prefix, items, power)
    local basic, bars, portrait = {}, {}, {}
    for _, it in ipairs(items) do
        local field = type(it.key) == "string" and string.match(it.key, "^" .. prefix .. "%.([^%.]+)$")
        if field and BASIC_FIELDS[field] then basic[#basic + 1] = it
        elseif field and PORTRAIT_FIELDS[field] then portrait[#portrait + 1] = it
        else bars[#bars + 1] = it end
    end
    return { label = "Frame", items = basic },
           { label = power and "Health and power" or "Health bar", items = ordered(bars, BAR_ORDER) },
           #portrait > 0 and { label = "Portrait", desc = "The picture at the frame's outer end: what it shows, its shape, size and ring.",
                               items = portrait } or nil
end

-- The Bar animation card for a frame's bars (the core's Options.BarFxCard):
-- health, and power when powerGate is given. pets adds the party pets' bars
-- (Party page); read is where its previews read (a raid size's own setup),
-- pickHidden hides its "Settings for" pick (a raid size following Raid 10).
local function barFxCard(id, powerGate, gate, pets, read, pickHidden)
    local function choice(key, what, kind, g)
        return { id = key .. kind, label = what, base = key .. ".barFx." .. kind .. ".", kind = kind, gate = g }
    end
    local choices = { choice(id, "Health bar", "health", gate) }
    if powerGate then choices[#choices + 1] = choice(id, "Power bar", "power", powerGate) end
    if pets then
        local petOff = function(get) return gate(get) or get("partyPet.enabled") ~= true end
        choices[#choices + 1] = choice("partyPet", "Pets' health bar", "health", petOff)
        choices[#choices + 1] = choice("partyPet", "Pets' power bar", "power",
            function(get) return petOff(get) or get("partyPet.showPower") == false end)
    end
    return DaylightUI.Options.BarFxCard({ module = "UnitFrames", choices = choices, read = read, pickHidden = pickHidden })
end

local function framePage(id, label, desc, opts)
    local k = function(s) return id .. "." .. s end
    local shown = off(k("enabled"))
    -- In a party the raid frames can take the party frames' place, and then
    -- nothing on the Party page shows.
    if id == "party" then
        shown = function(get)
            return get(k("enabled")) ~= true or (get("raid.enabled") ~= false and get("raid.showInParty") == true)
        end
    end
    -- No power bar here, since the frame's own switch is off.
    local function powerOff(get)
        return shown(get) or get(k("showPower")) == false
    end
    local function powerTextOff(get) return powerOff(get) or get(k("showPowerText")) ~= true end
    -- The spell cost and regen sweep also run on the personal display's bar.
    local function powerSpellOff(get) return shown(get) or (powerOff(get) and get("personal.enabled") ~= true) end
    -- A frame that can take a style (Defaults.lua, ns.STYLES): its pick, plus
    -- the rows that mean something else with a style's pieces, shown in their
    -- terms (the bar's height, the name row, the power line), each hidden
    -- without that piece.
    local styled = false
    for _, f in ipairs(ns.STYLE_FRAMES) do styled = styled or f == id end
    local function has(get, piece)
        if not styled then return false end
        local s = get(k("style"))
        if s == nil or s == "global" then s = get("look.style") end
        local style = ns.STYLES[s] or ns.STYLES.daylight
        return style[piece] == true
    end
    local function onRow(get) return has(get, "row") end
    local function noRow(get) return not has(get, "row") end
    local function onLine(get) return has(get, "line") end
    local function noLine(get) return not has(get, "line") end
    local function onCard(get) return has(get, "backdrop") end
    local function noCard(get) return not has(get, "backdrop") end
    -- A name tab shows in neither a name row's style nor a card's.
    local function noTabStyle(get) return has(get, "row") or has(get, "backdrop") end
    -- Too short for a portrait (UF.PortraitHeight; with a style's ring, the whole frame).
    local function tooShort(get)
        local cfg = { height = get(k("height")), tabHeight = get(k("tabHeight")), showPower = get(k("showPower")),
                      ribbonGap = get(k("ribbonGap")), powerHeight = get(k("powerHeight")), style = get(k("style")) }
        return UF.PortraitHeight({ spec = { styled = styled } }, cfg) < UF.MIN_PORTRAIT_HEIGHT
    end
    local frame = {
        { type = "toggle", key = k("enabled"), label = opts.showLabel or ("Show the " .. string.lower(label) .. " frame"),
          desc = opts.showDesc or ("Turn the " .. label .. " frame on or off.") },
    }
    if styled then frame[#frame + 1] = styleRow(k("style"), true, shown) end
    frame[#frame + 1] = { type = "slider", key = k("width"), label = "Width", min = opts.minWidth or SIZE.min, max = SIZE.max, step = 1,
        desc = "How wide this frame is.", disabled = shown }
    frame[#frame + 1] = { type = "slider", key = k("height"), label = "Height", min = 10, max = opts.maxHeight or 80, step = 1,
        desc = "How tall this frame is.", disabled = shown, hidden = onLine }
    if styled then
        frame[#frame + 1] = { type = "slider", key = k("height"), label = "Bar height", min = 10, max = opts.maxHeight or 80,
            step = 1, desc = "The slim health bar. The name, the health number and the power line sit outside it.",
            disabled = shown, hidden = noLine }
        frame[#frame + 1] = { type = "slider", key = k("stripHeight"), label = "Health strip height", min = 3, max = 20,
            step = 1, unit = "px", desc = "The health bar along the card's foot. The picture takes the rest of the card.",
            disabled = shown, hidden = noCard }
    end
    frame[#frame + 1] = strataRow(k("strata"), "Frame layer",
        opts.strataWhat or ("The layer the " .. string.lower(label) .. " frame draws in."), shown)
    local m = function(s) return id .. ".media." .. s end
    for _, it in ipairs(barRows(m("health"), "this frame's health bar", "Health bar", shown)) do frame[#frame + 1] = it end
    for _, it in ipairs(healthColorRows(id, shown)) do frame[#frame + 1] = it end
    for _, it in ipairs(backColorRows(id, "Health", shown)) do frame[#frame + 1] = it end
    if opts.powerToggle then
        frame[#frame + 1] = { type = "toggle", key = k("showPower"), label = "Power bar",
            desc = "A mana, rage or energy bar under the health. When off, the frame is all health.",
            disabled = shown }
    end
    if opts.power then
        frame[#frame + 1] = { type = "slider", key = k("powerHeight"), label = "Power bar height", min = 2, max = opts.maxHeight or 80,
            step = 1, desc = "How tall the power bar is. Inside the frame, the frame grows to keep some health showing.",
            disabled = powerOff, hidden = onLine }
        if styled then
            frame[#frame + 1] = { type = "slider", key = k("powerHeight"), label = "Power line height", min = 2, max = 20,
                step = 1, desc = "The thin power bar under the health bar.", disabled = powerOff, hidden = noLine }
            frame[#frame + 1] = { type = "slider", key = k("ribbonGap"), label = "Gap above the power line", min = 0, max = 12,
                step = 1, unit = "px", desc = "The space between the health bar and the power line under it.",
                disabled = powerOff, hidden = noLine }
        end
    end
    if opts.power or opts.powerToggle then
        for _, it in ipairs(barRows(m("power"), "this frame's power bar", "Power bar", powerOff)) do frame[#frame + 1] = it end
        for _, it in ipairs(powerColorRows(id, powerOff)) do frame[#frame + 1] = it end
        for _, it in ipairs(backColorRows(id, "Power", powerOff)) do frame[#frame + 1] = it end
    end
    if opts.powerFree then
        local notFree = function(get) return powerOff(get) or get(k("powerAt")) ~= "free" end
        local AT = { inside = "Inside the frame", free = "On its own (unlock to move)" }
        local AT_LINE = { inside = "Under the frame", free = AT.free }
        frame[#frame + 1] = { type = "dropdown", key = k("powerAt"), label = "Power bar position",
            values = AT, order = { "inside", "free" },
            -- With a style's power line "inside" is the line under the frame.
            choices = function()
                return (onLine(liveGet) and AT_LINE or AT), { "inside", "free" }
            end,
            desc = "On its own, the power bar leaves the frame and you can move it anywhere in unlock mode, like the middle of the screen. The frame is then all health.",
            disabled = powerOff }
        frame[#frame + 1] = { type = "slider", key = k("powerWidth"), label = "Power bar width", min = 40, max = 500, step = 1,
            desc = "How wide the power bar is. Only while it's on its own.", disabled = notFree }
        -- Its ends: powerSlant is the end on the frame's angled side, powerSlantBoth
        -- the other; the flips go by left and right.
        local inner = INNER_END[id] or "right"
        local pends = {
            [inner] = { on = k("powerSlant") },
            [inner == "right" and "left" or "right"] = { on = k("powerSlantBoth") },
        }
        pends.right.flip, pends.left.flip = k("powerSlantUnder"), k("powerSlantUnderLeft")
        local powerEnds = DaylightUI.Options.EndRows({ name = "Power bar", left = pends.left, right = pends.right,
            note = "Only while it's on its own. A cast bar hung under it follows its ends.", disabled = notFree })
        frame[#frame + 1] = powerEnds[1]
        frame[#frame + 1] = powerEnds[2]
        local powerAngle = angleRows({ own = k("powerOwnAngle"), lean = k("powerLean"), name = "Power bar", what = "the power bar's", since = "2.0",
            note = "Only while the power bar is on its own. A cast bar sliding out from under it continues the line.",
            disabled = function(get) return notFree(get) or (get(k("powerSlant")) == false and get(k("powerSlantBoth")) ~= true) end })
        frame[#frame + 1] = powerAngle[1]
        frame[#frame + 1] = powerAngle[2]
    end
    if opts.tile then
        frame[#frame + 1] = { type = "toggle", key = k("fillVertical"), label = "Fill upward",
            desc = "The health bar fills bottom to top instead of across.", disabled = shown }
    end
    if opts.spacing then
        frame[#frame + 1] = { type = "slider", key = k("spacing"), label = "Frame spacing", min = 0, max = 80, step = 1,
            desc = id == "arena" and "The gap between one PvP frame and the next." or "The gap between one party frame and the next.", disabled = shown }
    end
    if opts.portrait then
        frame[#frame + 1] = { type = "dropdown", key = k("portrait"), label = "Portrait",
            values = UF.PORTRAIT_MODES, order = UF.PORTRAIT_ORDER,
            desc = "A ring over the outer end. Class icons show for players; NPCs show their face."
                .. " Needs a frame at least " .. UF.MIN_PORTRAIT_HEIGHT .. " tall.",
            disabled = function(get) return shown(get) or tooShort(get) end, hidden = onCard }
        if styled then
            frame[#frame + 1] = { type = "dropdown", key = k("portrait"), label = "Card picture",
                values = UF.PORTRAIT_MODES, order = UF.PORTRAIT_ORDER,
                desc = "What fills the card behind the name: the 3D model, the face, or the class icon (NPCs show their face). None leaves only the unit's colors.",
                disabled = shown, hidden = noCard }
        end
        frame[#frame + 1] = { type = "dropdown", key = k("portraitShape"), label = "Shape", since = "1.8.1",
            values = UF.PORTRAIT_SHAPES, order = UF.PORTRAIT_SHAPE_ORDER,
            desc = "A round ring, a square, or a square with its outer side angled like the frame's end. The aggro fill, arrival light and elite frame follow the shape.",
            disabled = function(get) return shown(get) or get(k("portrait")) == "none" or tooShort(get) end, hidden = onCard }
        frame[#frame + 1] = { type = "dropdown", key = k("portraitLook"), label = "Portrait look", since = "2.0",
            values = ns.Socket.LOOKS, order = ns.Socket.LOOK_ORDER,
            desc = "2.0 runs the frame's border on around the portrait, so the two read as one piece. Classic lays the ring over the frame's end, as before. A portrait on its own wears the same border as a ring.",
            disabled = function(get) return shown(get) or get(k("portrait")) == "none" or tooShort(get) end, hidden = onCard }
        if opts.portraitFree then
            frame[#frame + 1] = { type = "dropdown", key = k("portraitAt"), label = "Portrait position",
                values = { frame = "On the frame", free = "On its own (unlock to move)" }, order = { "frame", "free" },
                desc = "On its own, the portrait leaves the frame and you can move it anywhere in unlock mode. The frame is then all bars.",
                disabled = function(get) return shown(get) or get(k("portrait")) == "none" or tooShort(get) end, hidden = onCard }
            frame[#frame + 1] = { type = "toggle", key = k("portraitIconsStay"), label = "Icons stay on the frame",
                desc = "With the portrait on its own, " .. (opts.combat and "the crown, resting Zzz, PvP flag and level badge"
                    or opts.dots and "the crown, PvP flag, level badge and DoT skull" or "the crown, PvP flag and level badge")
                    .. " stay on the frame instead of going with it.",
                disabled = function(get) return shown(get) or get(k("portrait")) == "none" or tooShort(get)
                    or get(k("portraitAt")) ~= "free" end, hidden = onCard }
        end
        frame[#frame + 1] = { type = "dropdown", key = k("portraitRing"), label = "Ring color",
            values = UF.RING_COLORS, order = UF.RING_COLOR_ORDER,
            desc = "Class gradient: the unit's class colors (an NPC's are by how friendly it is), and the red aggro ring is shaded to match. Accent color: your accent on every frame. Daylight gradient: the logo's colors on every frame. Light: a gray ring. Dark: the same dark border as the frame.",
            disabled = function(get) return shown(get) or get(k("portrait")) == "none" or tooShort(get) end, hidden = onCard }
        frame[#frame + 1] = { type = "dropdown", key = k("portraitRingWidth"), label = "Ring thickness", since = "1.8.1",
            values = UF.RING_WIDTH_NAMES, order = UF.RING_WIDTH_ORDER,
            desc = "How thick the ring is. A thicker ring leaves a smaller picture inside. The red aggro ring and its lights follow it.",
            disabled = function(get) return shown(get) or get(k("portrait")) == "none" or tooShort(get) end, hidden = onCard }
        frame[#frame + 1] = { type = "toggle", key = k("portraitRingLine"), label = "Line round the middle", since = "1.8.1",
            desc = "The thin dark line round the middle of the ring. When off, the ring is one smooth band. A portrait set into its frame has a thin ring with no line.",
            disabled = function(get) return shown(get) or get(k("portrait")) == "none" or tooShort(get)
                or get(k("portraitLook")) ~= "classic" end, hidden = onCard }
        if opts.dragon then
            frame[#frame + 1] = { type = "toggle", key = k("portraitDragon"), label = "Dragon around the portrait",
                desc = "The elite dragon wraps your own portrait too.",
                disabled = function(get) return shown(get) or get(k("portrait")) == "none" or tooShort(get) end, hidden = onCard }
            frame[#frame + 1] = { type = "dropdown", key = k("portraitDragonColor"), label = "Dragon color",
                values = UF.DRAGON_COLORS, order = UF.DRAGON_COLOR_ORDER,
                desc = "Gold or silver like an elite's, your accent color, or your class colors.",
                disabled = function(get) return shown(get) or get(k("portrait")) == "none" or tooShort(get)
                    or not get(k("portraitDragon")) end, hidden = onCard }
        end
    end
    if opts.power or opts.flip then
        frame[#frame + 1] = { type = "toggle", key = k("reverseFill"), label = "Fill from the other end",
            desc = opts.power and "Health and power bars fill from the opposite side."
                or "The health bar fills from the opposite side.", disabled = shown }
    end
    if opts.tab then
        if styled then
            frame[#frame + 1] = { type = "slider", key = k("tabHeight"), label = "Name row height", min = 10, max = 28, step = 1,
                unit = "px", desc = "The row above the bar that holds the name and the health number.",
                disabled = shown, hidden = noRow }
        end
    end
    if opts.portrait then
        frame[#frame + 1] = { type = "slider", key = k("portraitScale"), label = "Portrait size", min = 0.6, max = 1.5, step = 0.05, unit = "%",
            desc = "How big the portrait ring is next to the frame's height.",
            disabled = function(get) return shown(get) or tooShort(get) end, hidden = onCard }
    end
    for _, row in ipairs(frameEndRows(id, id, "Frame", shown, opts.portrait, opts.endNote)) do
        frame[#frame + 1] = row
    end
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

    local nameOff = offAny(k("enabled"), k("showName"))
    local text = {
        { type = "toggle", key = k("showName"), label = "Name",
          desc = (opts.tab and not opts.small) and "The unit's name, in a small tab above the frame. Long names are cut short."
              or "Shows the unit's name on this frame.",
          disabled = shown, hidden = noTabStyle },
        lastNames(id),
        { type = "dropdown", key = k("nameColor"), label = "Name color", values = NAME_COLORS, order = NAME_COLOR_ORDER,
          desc = "This frame's own name color. Same as the Look page follows the name color every frame shares.",
          disabled = nameOff },
        { type = "color", key = k("nameCustom"), label = "Custom name color", hidden = notCustom(k("nameColor")),
          desc = "The name's color when Name color is One color.", disabled = nameOff },
        { type = "slider", key = k("nameLimitLen"), label = "Max name length", min = 0, max = 24, step = 1,
          desc = "Letters shown before a long name is shortened. 0 shows names in full. In instances some names can't be shortened and show in full.", disabled = nameOff },
    }
    if opts.tab then
        table.insert(text, 2, { type = "toggle", key = k("nameOnBar"), label = "Name on the bar",
            desc = opts.small and "Keeps the name inside the bar. When off, it sits in a small tab above the frame, like the other frames' names."
                or "Puts the name inside the health bar, beside the portrait, instead of in the tab above (which can cover a cast bar placed there).",
            disabled = offAny(k("enabled"), k("showName")), hidden = onCard })
        -- Where the name sits on the bar (on a tile: across it, or a spot). On
        -- a card the name has one place, and only its nudges move it.
        local onBar = function(get)
            if onCard(get) then return shown(get) or get(k("showName")) == false end
            return shown(get) or get(k("showName")) == false or get(k("nameOnBar")) ~= true
        end
        for n, it in ipairs(nameItems(k, onBar, "Where the name sits across the bar: left, center or right. With a portrait, the name sits beside it instead.",
            not opts.tile and not opts.small, opts.small)) do
            if it.key ~= k("nameX") and it.key ~= k("nameY") then
                local was = it.hidden
                it.hidden = function(get) return onCard(get) or (was ~= nil and was(get)) end
            end
            -- Beside a portrait the name keeps the frame's outer end (UF.PlaceBarName).
            if it.key == k("nameAlign") and opts.portrait then
                local dis = it.disabled
                it.disabled = function(get)
                    return dis(get) or (get(k("portrait")) ~= "none" and not tooShort(get))
                end
            end
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
            disabled = shown, hidden = noRow })
        table.insert(text, 2, { type = "toggle", key = k("showName"), label = "Name",
            desc = "The name sits on the card's picture, at its top outer corner. Long names are cut short.",
            disabled = shown, hidden = noCard })
    end
    text[#text + 1] = fontRow(m("nameFont"), "Name font", opts.portrait and "This frame's names, and its level badge" or "This frame's names", shown)
    if opts.healthText then
        text[#text + 1] = { type = "toggle", key = k("showPercent"), label = "Health text",
            desc = "The unit's health written on this frame.", disabled = shown }
        text[#text + 1] = { type = "dropdown", key = k("healthText"), label = "Health text format",
            values = UF.HEALTH_FORMATS, order = UF.HEALTH_FORMAT_ORDER,
            desc = "How the health text is written. Missing health shows nothing while the unit is at full.",
            disabled = offAny(k("enabled"), k("showPercent")) }
        text[#text + 1] = { type = "toggle", key = k("percentSign"), label = "Health text % sign",
            desc = "62% rather than 62, when the health text shows a percent.",
            disabled = signOff(offAny(k("enabled"), k("showPercent")), k("healthText")) }
        text[#text + 1] = { type = "toggle", key = k("hideFullHealth"), invert = true, label = "Show health text at full",
            desc = "The health text shows at full health too. When off, it disappears while the unit is at full.",
            disabled = offAny(k("enabled"), k("showPercent")) }
        text[#text + 1] = { type = "dropdown", key = k("healthTextPos"), label = "Health text position",
            values = UF.POWER_TEXT_POS, order = UF.POWER_TEXT_POS_ORDER,
            desc = "Where along the health bar the health text sits. The left / right nudge moves it from there.",
            disabled = offAny(k("enabled"), k("showPercent")) }
    end
    if opts.healthText then
        text[#text + 1] = { type = "dropdown", key = k("percentColor"), label = "Health text color",
            values = TEXT_COLORS, order = TEXT_COLOR_ORDER, desc = "White, the unit's class color, or one you pick.",
            disabled = offAny(k("enabled"), k("showPercent")) }
        text[#text + 1] = { type = "color", key = k("percentCustom"), label = "Custom health text color",
            desc = "The health text's color when Health text color is One color.",
            hidden = notCustom(k("percentColor")), disabled = offAny(k("enabled"), k("showPercent")) }
        text[#text + 1] = fontRow(m("healthFont"), "Health text font", opts.big and "This frame's health text and large number" or "This frame's health text",
            offAny(k("enabled"), k("showPercent")))
    end
    if opts.big then
        text[#text + 1] = { type = "toggle", key = k("bigNumber"), label = "Large health number",
            desc = "Shows the health text large, in the Health text color, at the end Health text position picks (in Ribbon, on the row above the bar).",
            disabled = offAny(k("enabled"), k("showPercent")) }
    end
    if opts.power then
        text[#text + 1] = { type = "toggle", key = k("showPowerText"), label = "Power text",
            desc = "A small mana, rage or energy number on the power bar.", disabled = powerOff }
        text[#text + 1] = { type = "dropdown", key = k("powerFormat"), label = "Power text format",
            values = UF.POWER_FORMATS, order = UF.POWER_FORMAT_ORDER, desc = "How the power text is written.",
            disabled = powerTextOff }
        text[#text + 1] = { type = "toggle", key = k("powerPercentSign"), label = "Power text % sign",
            desc = "80% rather than 80, when the power text shows a percent.",
            disabled = signOff(powerTextOff, k("powerFormat")) }
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
        desc = "How big the name is on this frame.", disabled = nameOff }
    if opts.healthText then
        -- The large health number is the same text, sized by Large number size.
        text[#text + 1] = { type = "slider", key = t("percent"), label = "Health text size", min = 6, max = 24, step = 1,
            desc = opts.big and "How big the health text is on this frame, while Large health number is off."
                or "How big the health text is on this frame.",
            disabled = function(get)
                return get(k("enabled")) ~= true or get(k("showPercent")) ~= true or (opts.big and get(k("bigNumber")) == true)
            end }
    end
    if opts.powerPos then
        text[#text + 1] = { type = "slider", key = t("power"), label = "Power text size", min = 0, max = 24, step = 1,
            desc = "How big the power text is. 0 fits it to the bar.", disabled = powerTextOff }
    end
    if opts.big then
        text[#text + 1] = { type = "slider", key = t("big"), label = "Large number size", min = 10, max = 40, step = 1,
            desc = "How big the large health number is.", disabled = offAny(k("enabled"), k("showPercent"), k("bigNumber")) }
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
        local function waitOff(get)
            local mode = get(k("fade.mode"))
            return shown(get) or (mode ~= "ooc" and mode ~= "always" and mode ~= "float")
        end
        fadeExtra = { { type = "toggle", key = k("fade.fullHealth"), label = "Only at full health",
            desc = "Fades only while " .. who .. " health is full; comes back as soon as it drops. Show on mouseover still works.",
            disabled = waitOff } }
        if id == "player" then
            fadeExtra[2] = { type = "toggle", key = k("fade.fullMana"), label = "Only at full mana",
                desc = "Fades only while your mana is full; stays while it refills after a spell or a fight. Does nothing while your bar shows rage or energy.",
                disabled = waitOff }
        end
    end
    local basic, bars, portraitCard = splitFrame(id, frame, opts.power or opts.powerToggle)
    local groups = {
        basic, bars,
        shellCard(id, k("enabled")),
    }
    if portraitCard then groups[#groups + 1] = portraitCard end
    if opts.place then
        -- Each frame sits beside its party member (PartyTargets.lua).
        table.insert(groups, 2, { label = "Position", items = {
            { type = "dropdown", key = k("spot"), label = "Party target position", since = "1.8.0", values = ns.PartyTargets.SPOTS, order = ns.PartyTargets.SPOT_ORDER,
              desc = "Which side of the party member's frame their target sits on. Past a party pet on the same side.", disabled = shown },
            { type = "slider", key = k("x"), label = "Party targets left / right", since = "1.8.0", min = -100, max = 100, step = 1, unit = "px",
              desc = "Nudges every party target sideways from its position.", disabled = shown },
            { type = "slider", key = k("y"), label = "Party targets up / down", since = "1.8.0", min = -100, max = 100, step = 1, unit = "px",
              desc = "Nudges every party target up or down from its position.", disabled = shown },
        } })
    end
    if opts.tab then groups[#groups + 1] = tabCard(id, noTabStyle) end
    groups[#groups + 1] = DaylightUI.Fade.Card(id .. ".fade.", fadeExtra, shown, nil,
        { noFloat = ns.FLOAT[id] == false, noTarget = ns.WITH_TARGET[id] == true })
    groups[#groups + 1] = { label = "Text", items = ordered(text, TEXT_ORDER) }
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
    -- A party frame's role, marker and crown each get a card of their own,
    -- headed by its switch (see the tile cards below); other frames keep them here.
    local iconRows = {}
    local function iconRow(item) if opts.tile then iconRows[#iconRows + 1] = item else extras[#extras + 1] = item end end
    if opts.marker then
        iconRow({ type = "toggle", key = k("showMarker"), label = "Raid marker",
            desc = "Skull, cross and the rest, shown in the name tab before the name.", disabled = shown })
        iconRow({ type = "slider", key = k("markerSize"), label = "Raid marker size", min = 8, max = 32, step = 1, unit = "px",
            desc = "How big the raid marker is.", disabled = offAny(k("enabled"), k("showMarker")) })
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
            order = LEVEL_ORDER, desc = "Where the level badge sits: on the portrait, under it at the ring's foot, or any spot on or around the frame. You can also drag it in Design mode.", disabled = levelOff }
        extras[#extras + 1] = { type = "slider", key = k("levelX"), label = "Level left / right", min = -50, max = 50, step = 1,
            desc = "Nudges the level badge sideways. Not while it sits on or under the portrait.", unit = "px", disabled = function(get) return levelOff(get) or portraitSpot(get(k("levelPos"))) end }
        extras[#extras + 1] = { type = "slider", key = k("levelY"), label = "Level up / down", min = -50, max = 50, step = 1,
            desc = "Nudges the level badge up or down. Not while it sits on or under the portrait.", unit = "px", disabled = function(get) return levelOff(get) or portraitSpot(get(k("levelPos"))) end }
        iconRow({ type = "toggle", key = k("showLeader"), label = "Leader crown",
            desc = "A crown on top of the portrait ring (or over the name tab) for the party or raid leader.", disabled = shown })
        iconRow({ type = "slider", key = k("leaderSize"), label = "Leader crown size", min = 0.5, max = 2, step = 0.05, unit = "%",
            desc = "How big the leader's crown is.", disabled = opts.tile and offAny(k("enabled"), k("showLeader")) or shown })
    end
    if opts.combat then
        extras[#extras + 1] = { type = "toggle", key = k("druidMana"), label = "Druid mana in forms",
            desc = "A thin mana strip along the bottom of the power bar while a form hides your mana.", disabled = powerOff }
        local function druidOff(get) return shown(get) or get(k("druidBars.enabled")) ~= true end
        extras[#extras + 1] = { type = "toggle", key = k("druidBars.enabled"), label = "Druid resource bars",
            desc = "A bar for your mana while bear or cat form shows rage or energy. Move it in unlock mode.",
            disabled = shown }
        extras[#extras + 1] = { type = "slider", key = k("druidBars.width"), label = "Druid bars width", min = 40, max = 300, step = 1, unit = "px",
            desc = "How long the bar is.", disabled = druidOff }
        extras[#extras + 1] = { type = "slider", key = k("druidBars.height"), label = "Druid bars height", min = 3, max = 20, step = 1, unit = "px",
            desc = "How tall the bar is.", disabled = druidOff }
        extras[#extras + 1] = { type = "toggle", key = k("druidBars.showText"), label = "Druid bars numbers",
            desc = "How much mana you have, on the bar.", disabled = druidOff }
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
        extras[#extras + 1] = { type = "toggle", key = k("regenTicks"), since = "2.2.4", label = "Keep ticking",
            desc = "After the 5 seconds, a softer light runs to each mana regen tick until your mana is full. It learns the tick from your mana's own gains, so it starts after the first two.",
            disabled = function(get) return powerSpellOff(get) or get(k("regenSweep")) == "off" end,
            hidden = function() return not ns.PowerBar.HasMana() end }
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
            values = { square = "Color square", icon = "Mood face", frame = "In the frame" },
            order = { "square", "icon", "frame" },
            desc = "A square filled with the mood's color, the pet's mood face, or a stripe inside the frame.",
            disabled = happyOff }
        local function besideOff(get) return happyOff(get) or get(k("happinessLook")) == "frame" end
        local function stripeOff(get) return happyOff(get) or get(k("happinessLook")) ~= "frame" end
        extras[#extras + 1] = { type = "dropdown", key = k("happinessSide"), label = "Happiness side", since = "1.8.0",
            values = { left = "Left", right = "Right" }, order = { "left", "right" },
            desc = "Which end of the frame the stripe sits in. On an angled end it follows the angle.",
            disabled = stripeOff }
        extras[#extras + 1] = { type = "dropdown", key = k("happinessSpot"), label = "Happiness position", values = ns.Spots.LABELS,
            order = ns.Spots.ORDER, desc = "Where the happiness square or face sits, on or around the frame.", disabled = besideOff }
        extras[#extras + 1] = { type = "slider", key = k("happinessSize"), label = "Happiness size", min = 8, max = 40, step = 1, unit = "px",
            desc = "How big the happiness square or face is.", disabled = besideOff }
        extras[#extras + 1] = { type = "slider", key = k("happinessX"), label = "Happiness left / right", min = -50, max = 50, step = 1, unit = "px",
            desc = "Nudges the happiness square or face sideways.", disabled = besideOff }
        extras[#extras + 1] = { type = "slider", key = k("happinessY"), label = "Happiness up / down", min = -50, max = 50, step = 1, unit = "px",
            desc = "Nudges the happiness square or face up or down.", disabled = besideOff }
        extras[#extras + 1] = { type = "toggle", key = k("happinessBar"), label = "Color health bar by happiness",
            desc = "The pet's health bar takes the mood color instead: red unhappy, yellow content, green happy. Turn Pet happiness off to have only this.",
            disabled = shown }
    end
    if opts.role then
        iconRow({ type = "toggle", key = k("showRole"), label = "Role icon",
            desc = "Tank, healer or damage, from the role they picked. Nothing shows for an unknown or unset role.",
            disabled = shown })
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
        local icons = iconItems(k, shown, { markerSize = true, leaderPxLabel = "Leader crown pixel",
            leaderPxDesc = "How big the leader's crown is, in pixels. With the name or portrait it fits there until you change this, and Leader crown size scales it." },
            true)
        groups[#groups + 1] = { label = "Dispels", desc = "How a debuff you can remove shows on each party frame: an icon, a highlight or a glow.",
            items = dispelItems(k, k("enabled"), 32, "frame", icons.dispel) }
        local function row(key) for _, item in ipairs(iconRows) do if item.key == k(key) then return item end end end
        local home = " It rides with the name tab or portrait until you pick a spot for it."
        groups[#groups + 1] = { label = "Role icon", desc = "Tank, healer or damage on each party frame." .. home,
            items = cat({ row("showRole") }, icons.role) }
        groups[#groups + 1] = { label = "Raid marker", desc = "Skull, cross and the rest on a marked member's frame." .. home,
            items = cat({ row("showMarker"), row("markerSize") }, icons.marker) }
        groups[#groups + 1] = { label = "Leader crown", desc = "A crown on the party leader's frame." .. home,
            items = cat({ row("showLeader"), row("leaderSize") }, icons.leader) }
        groups[#groups + 1] = { label = "Ready check, summon and rez", desc = "Answers to a ready check, who's being summoned, and who's being rezzed, on each party frame.",
            items = cat(icons.ready, icons.summon, icons.rez) }
    end
    if opts.layout then
        table.insert(groups, 1, { label = "Layout", items = {
            growRows(k, "Lines", shown)[1],
            growRows(k, "Lines", shown)[2],
            growRows(k, "Lines", shown)[3],
            { type = "slider", key = k("perLine"), label = "Frames per line", min = 1, max = 5, step = 1,
              desc = "At 5 the party is one line. Fewer makes a grid.", disabled = shown },
            { type = "slider", key = k("groupSpacing"), label = "Line spacing", min = 0, max = 80, step = 1,
              desc = "The gap between lines, when there's more than one.", disabled = shown },
            { type = "dropdown", key = k("sortBy"), label = "Sort frames by", values = SORT_VALUES, order = SORT_ORDER,
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
    -- A page with a Cast bar tab shows its cast in the test, so the tab has something to look at
    -- (your own frame has no test switch: it is always real).
    if opts.castCards and preview then preview[#preview + 1] = "castbars" end
    -- Its cast bar's cards: their own tab.
    if opts.castCards then
        for _, card in ipairs(opts.castCards) do
            card.tab = "Cast bar"
            groups[#groups + 1] = card
        end
    end
    groups[#groups + 1] = barFxCard(id, (opts.power or opts.powerToggle) and powerOff or nil, shown, opts.pets)
    if ns.Layers.PARTS[id] then
        groups[#groups + 1] = { label = "Layers", items = ns.Layers.Rows(id, shown),
            desc = "Which part draws on top where this frame's parts overlap. A part higher in the list draws over the ones below it. A part standing on its own can also take a layer of its own." }
    end
    groups[#groups + 1] = copyCard(id)
    return { id = id, label = label, desc = desc, groups = tabbed(groups), preview = preview,
             sample = function(parent) return ns.PageSample.New(id, parent) end }
end

-- The cast bar cards: where each bar sits (CastBar.AT) and what grays out
-- there. ownSize: a bar of its own (not inside the frame, not hung under it).
local CB = ns.CastBar
-- Each cast bar's name at the start of its row labels.
local CAST_WHO = { player = "Your cast bar", target = "Target cast bar", focus = "Focus cast bar", party = "Party cast bar" }
local function atChoice(unit, desc)
    local values = {}
    for _, v in ipairs(CB.AT[unit]) do values[v] = CB.AT_LABELS[v] end
    if unit == "player" then values.below = "Under the frame (slides out)" end
    if unit == "party" then values.free = "Detached, beside the frame" end
    -- In a style with a power line it's a thin line, and with power bars off there's
    -- none, so no cast can go inside it. A bar set to sit there sits below
    -- instead (CB.At).
    local outsideOrder = {}
    for _, v in ipairs(CB.AT[unit]) do
        if v ~= "power" then outsideOrder[#outsideOrder + 1] = v end
    end
    local function outside()
        local cfg = liveGet(unit)
        return UF.StyleDef(cfg).line or UF.StyleDef(cfg).backdrop or not UF.ShowsPower(cfg)
    end
    return { type = "dropdown", key = unit .. "Castbar.at", since = "1.5.1", label = CAST_WHO[unit] .. " position", values = values, order = CB.AT[unit],
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
    return { type = "slider", key = unit .. "Castbar." .. axis, label = CAST_WHO[unit] .. (x and " left / right" or " up / down"),
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
    return { type = "toggle", key = unit .. "Castbar.fitFrame", label = CAST_WHO[unit] .. " matches the frame's width",
             desc = "Above or below the frame, the bar is as wide as the frame. When off, it takes the width below.",
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
-- A cast bar's spell name and time, each with its own switch, size, position,
-- nudge and color. who: the bar's name in labels ("Target"); whose: in
-- sentences ("your target's"). inside: the rows for the text inside the frame.
local TEXT_SPOTS = { left = "Left", center = "Center", right = "Right" }
local TEXT_SPOT_ORDER = { "left", "center", "right" }
-- Rows that place the pips on a frame: off while they're off or on their own.
local function comboAttached(get)
    return get("combo.enabled") ~= true or get("combo.anchor") == "free"
end

local function castTextCard(unit, who, whose, inside)
    local bar = unit .. "Castbar"
    local function rows(kind, name, items)
        local k = function(s) return bar .. "." .. kind .. "." .. s end
        local dis = offAny(bar .. ".enabled", k("show"))
        local lower = string.lower(name)
        items[#items + 1] = { type = "slider", key = k("size"), label = who .. " " .. lower .. " text size", min = 6, max = 24, step = 1,
            desc = "The " .. lower .. " on " .. whose .. " cast bar." .. (unit ~= "player" and " Inside the frame, left at its default, it shrinks to fit the power bar." or ""),
            disabled = dis }
        items[#items + 1] = { type = "dropdown", key = k("pos"), label = who .. " " .. lower .. " position",
            values = TEXT_SPOTS, order = TEXT_SPOT_ORDER,
            desc = "Where the " .. lower .. " sits on " .. whose .. " cast bar.", disabled = dis }
        items[#items + 1] = { type = "slider", key = k("x"), label = who .. " " .. lower .. " left / right", min = -100, max = 100, step = 1, unit = "px",
            desc = "Moves the " .. lower .. " sideways from its position.", disabled = dis }
        items[#items + 1] = { type = "slider", key = k("y"), label = who .. " " .. lower .. " up / down", min = -40, max = 40, step = 1, unit = "px",
            desc = "Moves the " .. lower .. " up or down. It can sit outside the bar.", disabled = dis }
        items[#items + 1] = { type = "color", key = k("color"), label = who .. " " .. lower .. " color",
            desc = "The " .. lower .. "'s color on " .. whose .. " cast bar.", disabled = dis }
    end
    local items = {
        { type = "toggle", key = bar .. ".spell.show", label = who .. " spell name",
          desc = "The spell's name on " .. whose .. " cast bar.", disabled = off(bar .. ".enabled") },
    }
    rows("spell", "Spell name", items)
    items[#items + 1] = { type = "toggle", key = bar .. ".time.show", label = who .. " cast time",
        desc = "The time on " .. whose .. " cast bar.", disabled = off(bar .. ".enabled") }
    items[#items + 1] = { type = "dropdown", key = bar .. ".time.format", label = who .. " cast time format",
        values = { left = "Time left (1.2)", total = "Left / total (1.2 / 2.5)" }, order = { "left", "total" },
        desc = "What's left of the cast, or what's left out of the whole cast.",
        disabled = offAny(bar .. ".enabled", bar .. ".time.show") }
    rows("time", "Cast time", items)
    if inside then
        items[#items + 1] = { type = "slider", key = bar .. ".insideTextSize", label = who .. " text size inside the frame", min = 0, max = 20, step = 1,
            desc = "The spell name and time while the bar sits inside the frame, even past the power bar's height. 0 keeps each text's own size, shrinking a default one to fit the power bar.",
            disabled = notInside(unit) }
        if unit == "target" then
            items[#items + 1] = { type = "slider", key = bar .. ".insideTextX", label = "Target text left / right inside the frame", min = -100, max = 100, step = 1, unit = "px",
                desc = "Moves the spell name and time sideways together while the bar sits inside the target frame.",
                disabled = notInside(unit) }
            items[#items + 1] = { type = "slider", key = bar .. ".insideTextY", label = "Target text up / down inside the frame", min = -40, max = 40, step = 1, unit = "px",
                desc = "Moves the spell name and time up or down together while the bar sits inside the target frame. They can sit outside the bar.",
                disabled = notInside(unit) }
        end
    end
    return { label = who .. " cast bar text", items = items }
end
local attached = notOwnSize("player")
-- Between the frames, the bar takes the gap's width, has no icon, and fills left to right.
local function notMiddleOwn(get) return attached(get) or atOf(get, "player") == "middle" end
-- A cast bar's two end menus (Options.EndRows). rightDis / leftDis gray out
-- one end, note ends both descriptions.
local function castEnds(unit, rightDis, leftDis, note)
    local k = function(s) return unit .. "Castbar." .. s end
    return DaylightUI.Options.EndRows({ name = CAST_WHO[unit], note = note,
        left = { on = k("slantLeft"), flip = k("slantUnderLeft"), disabled = leftDis },
        right = { on = k("slant"), flip = k("slantUnder"), disabled = rightDis } })
end
-- Its own angle, on the same bars the flip works on.
local function castAngle(unit, who, notOwn)
    return angleRows({ own = unit .. "Castbar.ownAngle", lean = unit .. "Castbar.lean", name = CAST_WHO[unit], what = who .. " cast bar's", since = "2.0",
        note = unit == "player" and "Not while under the frame, between the frames or under the personal display."
            or (unit == "target" or unit == "focus") and "Not inside the frame or sliding out under it." or "Not inside the frame.",
        disabled = function(get)
            return notOwn(get) or (unit == "player" and atOf(get, "player") == "personal")
                or (get(unit .. "Castbar.slant") ~= true and get(unit .. "Castbar.slantLeft") ~= true)
        end })
end

-- A raid page: Raid 10, 20 or 40 (Raid.lua's setups by raid size).
local RAID_PAGE_DESC = {
    [10] = "Small tiles for a raid of up to 10: one column per group, left to right. Raid 20 and Raid 40 use these too while they're Same as Raid 10. Show, fade, textures and fonts here count for every raid size; your party has its own page.",
    [20] = "The raid frames for 11 to 20 players. Show, fade, textures and fonts are on the Raid 10 page.",
    [40] = "The raid frames for 21 to 40 players. Show, fade, textures and fonts are on the Raid 10 page.",
}

local function raidPage(size)
    local raidIcons = iconItems(function(key) return "raid." .. key end, off("raid.enabled"))
    local frameCard, barsCard = splitFrame("raid", {
        { type = "toggle", key = "raid.enabled", label = "Show raid frames", desc = "Replaces the game's raid frames while you're in a raid." },
        { type = "toggle", key = "raid.showInParty", label = "Use raid frames in a party",
          desc = "Shows these raid frames in a party too, in place of the party frames.", disabled = off("raid.enabled") },
        growRows(function(f) return ns.Raid.MapKey("raid." .. f, size) end, "Lines", off("raid.enabled"),
                 function(f) return "raid." .. f end)[1],
        growRows(function(f) return ns.Raid.MapKey("raid." .. f, size) end, "Lines", off("raid.enabled"),
                 function(f) return "raid." .. f end)[2],
        growRows(function(f) return ns.Raid.MapKey("raid." .. f, size) end, "Lines", off("raid.enabled"),
                 function(f) return "raid." .. f end)[3],
        { type = "dropdown", key = "raid.sortBy", label = "Sort frames by",
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
        backColorRows("raid", "Health", off("raid.enabled"))[1],
        backColorRows("raid", "Health", off("raid.enabled"))[2],
        backColorRows("raid", "Health", off("raid.enabled"))[3],
        backColorRows("raid", "Health", off("raid.enabled"))[4],
        { type = "slider", key = "raid.spacing", label = "Frame spacing", min = 0, max = 20, step = 1,
          desc = "The gap between one raid tile and the next in a line.", disabled = off("raid.enabled") },
        { type = "slider", key = "raid.groupSpacing", label = "Line spacing", min = 0, max = 30, step = 1,
          desc = "The gap between lines of tiles, like one raid group and the next.", disabled = off("raid.enabled") },
        { type = "slider", key = "raid.perLine", label = "Frames per line", min = 1, max = 40, step = 1,
          desc = "At 5, each group gets its own line. Any other number lists everyone in order and wraps, up to 40 in one line.",
          disabled = off("raid.enabled") },
        { type = "toggle", key = "raid.hideSelf", invert = true, label = "Show yourself",
          desc = "Your own tile sits with the raid's. When off, only the rest of the raid shows.", disabled = off("raid.enabled") },
        frameEndRows("raid", "raid", "Tile", off("raid.enabled"))[1],
        frameEndRows("raid", "raid", "Tile", off("raid.enabled"))[2],
        { type = "toggle", key = "raid.fillVertical", label = "Fill upward",
          desc = "The health bar fills bottom to top instead of across.", disabled = off("raid.enabled") },
        { type = "toggle", key = "raid.showPower", label = "Power bar",
          desc = "A thin mana, rage or energy bar at the foot of each tile.", disabled = off("raid.enabled") },
        { type = "slider", key = "raid.powerHeight", label = "Power bar height", min = 2, max = 80, step = 1,
          desc = "How tall each tile's power bar is.", disabled = offAny("raid.enabled", "raid.showPower") },
        barRows("raid.media.power", "the raid tiles' power bars", "Power bar", offAny("raid.enabled", "raid.showPower"))[1],
        barRows("raid.media.power", "the raid tiles' power bars", "Power bar", offAny("raid.enabled", "raid.showPower"))[2],
        powerColorRows("raid", offAny("raid.enabled", "raid.showPower"))[1],
        powerColorRows("raid", offAny("raid.enabled", "raid.showPower"))[2],
        backColorRows("raid", "Power", offAny("raid.enabled", "raid.showPower"))[1],
        backColorRows("raid", "Power", offAny("raid.enabled", "raid.showPower"))[2],
        backColorRows("raid", "Power", offAny("raid.enabled", "raid.showPower"))[3],
        backColorRows("raid", "Power", offAny("raid.enabled", "raid.showPower"))[4],
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
        { label = "Text", items = ordered(cat({
            { type = "toggle", key = "raid.showName", label = "Name",
              desc = "Each member's name on their tile.", disabled = off("raid.enabled") },
            lastNames("raid"),
            { type = "dropdown", key = "raid.nameColor", label = "Name color", values = NAME_COLORS, order = NAME_COLOR_ORDER,
              desc = "The raid tiles' own name color. Same as the Look page follows the name color every frame shares.",
              disabled = offAny("raid.enabled", "raid.showName") },
            { type = "color", key = "raid.nameCustom", label = "Custom name color", hidden = notCustom("raid.nameColor"),
              desc = "The names' color when Name color is One color.", disabled = offAny("raid.enabled", "raid.showName") },
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
            { type = "toggle", key = "raid.percentSign", label = "Health text % sign",
              desc = "62% rather than 62, when the health text shows a percent.",
              disabled = signOff(offAny("raid.enabled", "raid.showPercent"), "raid.healthText") },
            { type = "dropdown", key = "raid.healthTextPos", label = "Health text position",
              values = UF.POWER_TEXT_POS, order = UF.POWER_TEXT_POS_ORDER,
              desc = "Where along each tile the health text sits. The left / right nudge moves it from there.",
              disabled = offAny("raid.enabled", "raid.showPercent") },
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
        }), TEXT_ORDER) },
        { label = "Extras", items = cat({
            { type = "toggle", key = "raid.predictHeals", label = "Incoming heals",
              desc = "Heals on their way, as a soft green stretch past the health.", disabled = off("raid.enabled") },
            { type = "toggle", key = "raid.predictAbsorbs", label = "Absorbs",
              desc = "Damage shields, as a pale stretch after any incoming heals.", disabled = off("raid.enabled") },
            { type = "toggle", key = "raid.showMarker", label = "Raid marker",
              desc = "Skull, cross and the rest, on the tile of a marked member.", disabled = off("raid.enabled") },
            { type = "toggle", key = "raid.showLeader", label = "Leader crown",
              desc = "A small crown on the raid leader's tile.", disabled = off("raid.enabled") },
        }, {
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
            { type = "dropdown", key = "leader.opens", label = "Leader tools open toward", anySize = true,
              values = { auto = "The middle of the screen", left = "The left", right = "The right" }, order = { "auto", "left", "right" },
              desc = "Which way the card opens from the crown tab. The middle of the screen keeps it on screen wherever you move the tab.",
              disabled = function(get) return get("leader.enabled") ~= true or (get("raid.enabled") ~= true and get("party.enabled") ~= true) end },
            { type = "toggle", key = "leader.slim", label = "Slim leader tools", anySize = true,
              desc = "A smaller card without the section titles. The arrow in the card's top right corner switches it too.",
              disabled = function(get) return get("leader.enabled") ~= true or (get("raid.enabled") ~= true and get("party.enabled") ~= true) end },
            { type = "toggle", key = "pull.enabled", label = "Pull timer", anySize = true,
              desc = "A big number in the middle of your screen counts down any pull your group starts, in place of the game's bar. Move it in unlock mode. In a dungeon or raid the game may keep its own bar for a countdown someone else starts." },
        } },
    }, auraCards(function(s) return "raid." .. s end, "raid.enabled"), {
        { label = "Dispels", desc = "How a debuff you can remove shows on each raid tile: an icon, a highlight or a glow.",
          items = dispelItems(function(s) return "raid." .. s end, "raid.enabled", 24, "tile", raidIcons.dispel) },
        { label = "Icon positions and sizes", desc = "Where the role, marker and crown sit on a tile, and the ready check, summon and rez icons.",
          items = cat(raidIcons.role, raidIcons.marker, raidIcons.leader, raidIcons.ready, raidIcons.summon, raidIcons.rez) },
        barFxCard("raid", offAny("raid.enabled", "raid.showPower"), off("raid.enabled"), false,
                  function(key) return DaylightUI:Get("UnitFrames", ns.Raid.MapKey(key, size)) end,
                  size ~= 10 and function() return ns.Raid.Locked(size) end or nil),
    }, extraTextCards("raid", "raid.enabled"), extraAuraCards("raid", "raid.enabled")), size),
        { copyCard(size == 10 and "raid" or "raid" .. size,
                   size ~= 10 and function() return ns.Raid.Locked(size) end or nil) })) }
end

-- Each cast bar's cards, which sit on its frame's page under the Cast bar tab (framePage).
-- The player's border card says whose it is, since the frame has a border card of its own.
local function castShell(bar)
    local card = shellCard(bar, bar .. ".enabled", true)
    card.label = "Cast bar border and shadow"
    return card
end
local PLAYER_CAST = {
    { label = "Player cast bar", items = {
        { type = "toggle", key = "playerCastbar.enabled", label = "Show your cast bar",
          desc = "Replaces the game's own cast bar." },
        atChoice("player", "Under the frame it continues the frame's angle and slides out as you cast. Between your frame and the target's it fills the gap, both ends angled like the frames beside it, with the swing timers fanning out under it. Above the frame or on its own it has its own size."),
        { type = "dropdown", key = "playerCastbar.from", label = "Your cast bar slides out from",
          values = { frame = "The player frame", power = "The power bar" }, order = { "frame", "power" },
          desc = "With the power bar on its own (Player > Power bar), the cast bar and the swing timer under it can slide out from under the power bar instead of the frame. Under a flipped end of the power bar they lean back in.",
          disabled = function(get)
              return get("playerCastbar.enabled") ~= true or get("playerCastbar.at") ~= "below" or get("player.powerAt") ~= "free"
          end },
        nudge("player", "x"),
        nudge("player", "y"),
        { type = "slider", key = "playerCastbar.width", label = "Your cast bar width", min = 80, max = 500, step = 1,
          desc = "How wide your cast bar is. Not while under the frame or between the frames: there it fills the space it has.", disabled = notMiddleOwn },
        { type = "slider", key = "playerCastbar.height", label = "Your cast bar height", min = 8, max = 40, step = 1,
          desc = "How tall your cast bar is.", disabled = off("playerCastbar.enabled") },
        barRows("playerCastbar.media.bar", "your cast bar", "Your cast bar", off("playerCastbar.enabled"))[1],
        barRows("playerCastbar.media.bar", "your cast bar", "Your cast bar", off("playerCastbar.enabled"))[2],
        fontRow("playerCastbar.media.font", "Your cast bar font", "The spell name and time on your cast bar", off("playerCastbar.enabled")),
        { type = "toggle", key = "playerCastbar.showIcon", label = "Your cast bar spell icon",
          desc = "The spell's icon at the end of your cast bar. Not while under the frame, where the portrait ring covers that spot, or between the frames.", disabled = notMiddleOwn },
        castEnds("player", off("playerCastbar.enabled"),
            function(get) return notMiddleOwn(get) or atOf(get, "player") == "personal" end,
            "Under the frame it follows the frame's own ends (Straight there keeps it square), between the frames both ends lean, and under the personal display it takes the display's.")[1],
        castEnds("player", off("playerCastbar.enabled"),
            function(get) return notMiddleOwn(get) or atOf(get, "player") == "personal" end,
            "Under the frame it follows the frame's own ends (Straight there keeps it square), between the frames both ends lean, and under the personal display it takes the display's.")[2],
        castAngle("player", "your", notMiddleOwn)[1],
        castAngle("player", "your", notMiddleOwn)[2],
        { type = "toggle", key = "playerCastbar.reverseFill", label = "Your cast bar fills right to left",
          desc = "Your cast bar fills from the right. Not while under the frame or between the frames.", disabled = notMiddleOwn },
        strataRow("playerCastbar.strata", "Your cast bar layer", "The layer your cast bar draws in.",
            function(get) return notMiddleOwn(get) or atOf(get, "player") == "personal" end,
            " Under the frame, between the frames or under the personal display, it draws with the frame instead."),
    } },
    castShell("playerCastbar"),
    DaylightUI.Fade.Card("playerCastbar.fade.", nil, off("playerCastbar.enabled"), "Your cast bar", { noFloat = true }),
    castTextCard("player", "Player", "your"),
}
local TARGET_CAST = {
    { label = "Target cast bar", items = {
        { type = "toggle", key = "targetCastbar.enabled", label = "Show the target cast bar",
          desc = "Your target's casts, while they last." },
        atChoice("target", "Inside the frame it covers the power bar, as wide as it (in the Ribbon style it sits below the frame instead). Above, below or on its own it's a bar you size here; on its own you move it in unlock mode. Under the frame it slides out during a cast, and the buffs below keep room for it."),
        nudge("target", "x"),
        nudge("target", "y"),
        fitRow("target"),
        { type = "slider", key = "targetCastbar.width", label = "Target cast bar width", min = 80, max = 500, step = 1,
          desc = "How wide your target's cast bar is. Not inside the frame, or while it matches the frame's width.",
          disabled = notOwnWidth("target") },
        { type = "slider", key = "targetCastbar.height", label = "Target cast bar height", min = 8, max = 40, step = 1,
          desc = "How tall your target's cast bar is. Not inside the frame, where it takes the power bar's place.",
          disabled = notOwnSize("target") },
        barRows("targetCastbar.media.bar", "your target's cast bar", "Target cast bar", off("targetCastbar.enabled"))[1],
        barRows("targetCastbar.media.bar", "your target's cast bar", "Target cast bar", off("targetCastbar.enabled"))[2],
        fontRow("targetCastbar.media.font", "Target cast bar font", "The spell name and time on your target's cast bar", off("targetCastbar.enabled")),
        { type = "toggle", key = "targetCastbar.showIcon", label = "Target cast bar spell icon",
          desc = "The spell's icon at the end of your target's cast bar. Not inside the frame or sliding out under it.",
          disabled = notOwnBar("target") },
        castEnds("target", notOwnBar("target"), notOwnBar("target"), "Not inside the frame or sliding out under it, where it follows the frame's own ends.")[1],
        castEnds("target", notOwnBar("target"), notOwnBar("target"), "Not inside the frame or sliding out under it, where it follows the frame's own ends.")[2],
        castAngle("target", "your target's", notOwnBar("target"))[1],
        castAngle("target", "your target's", notOwnBar("target"))[2],
        { type = "toggle", key = "targetCastbar.reverseFill", label = "Target cast bar fills right to left",
          desc = "Your target's cast bar fills from the right. Not inside the frame or sliding out under it.",
          disabled = notOwnBar("target") },
        strataRow("targetCastbar.strata", "Target cast bar layer", "The layer your target's cast bar draws in.",
            notOwnBar("target"), " Inside the frame or sliding out under it, it draws with the frame instead. Same as frame keeps it with the frame wherever it stands.", true),
    } },
    castTextCard("target", "Target", "your target's", true),
}
local FOCUS_CAST = {
    { label = "Focus cast bar", items = {
        { type = "toggle", key = "focusCastbar.enabled", label = "Show the focus cast bar",
          desc = "Your focus's casts, while they last. It uses the target cast bar's colors." },
        atChoice("focus", "Inside the frame it covers the power bar, as wide as it (in the Ribbon style it sits below the frame instead). Above, below or on its own it's a bar you size here; on its own you move it in unlock mode. Under the frame it slides out during a cast, and the buffs below keep room for it."),
        nudge("focus", "x"),
        nudge("focus", "y"),
        fitRow("focus"),
        { type = "slider", key = "focusCastbar.width", label = "Focus cast bar width", min = 80, max = 500, step = 1,
          desc = "How wide your focus's cast bar is. Not inside the frame, or while it matches the frame's width.",
          disabled = notOwnWidth("focus") },
        { type = "slider", key = "focusCastbar.height", label = "Focus cast bar height", min = 8, max = 40, step = 1,
          desc = "How tall your focus's cast bar is. Not inside the frame, where it takes the power bar's place.",
          disabled = notOwnSize("focus") },
        barRows("focusCastbar.media.bar", "your focus's cast bar", "Focus cast bar", off("focusCastbar.enabled"))[1],
        barRows("focusCastbar.media.bar", "your focus's cast bar", "Focus cast bar", off("focusCastbar.enabled"))[2],
        fontRow("focusCastbar.media.font", "Focus cast bar font", "The spell name and time on your focus's cast bar", off("focusCastbar.enabled")),
        { type = "toggle", key = "focusCastbar.showIcon", label = "Focus cast bar spell icon",
          desc = "The spell's icon at the end of your focus's cast bar. Not inside the frame or sliding out under it.",
          disabled = notOwnBar("focus") },
        castEnds("focus", notOwnBar("focus"), notOwnBar("focus"), "Not inside the frame or sliding out under it, where it follows the frame's own ends.")[1],
        castEnds("focus", notOwnBar("focus"), notOwnBar("focus"), "Not inside the frame or sliding out under it, where it follows the frame's own ends.")[2],
        castAngle("focus", "your focus's", notOwnBar("focus"))[1],
        castAngle("focus", "your focus's", notOwnBar("focus"))[2],
        { type = "toggle", key = "focusCastbar.reverseFill", label = "Focus cast bar fills right to left",
          desc = "Your focus's cast bar fills from the right. Not inside the frame or sliding out under it.",
          disabled = notOwnBar("focus") },
        strataRow("focusCastbar.strata", "Focus cast bar layer", "The layer your focus's cast bar draws in.",
            notOwnBar("focus"), " Inside the frame or sliding out under it, it draws with the frame instead. Same as frame keeps it with the frame wherever it stands.", true),
    } },
    castTextCard("focus", "Focus", "your focus's"),
}
local PARTY_CAST = {
    { label = "Party cast bars", items = {
        { type = "toggle", key = "partyCastbar.enabled", label = "Show party cast bars",
          desc = "Each party member's casts on their own frame, while they last. They use the target cast bar's colors." },
        atChoice("party", "Inside the frame it covers the power bar (in the Ribbon style, or with power bars off, it slides out under the frame instead). Under the frame it slides out during a cast: give it room with the party's spacing. Detached, it's a bar you size here, beside each frame."),
        { type = "dropdown", key = "partyCastbar.spot", label = "Party cast bar side", values = ns.PartyCasts.SPOTS, order = ns.PartyCasts.SPOT_ORDER,
          desc = "Which side of each party frame a detached cast bar sits on.", disabled = notOwnBar("party") },
        { type = "slider", key = "partyCastbar.x", label = "Party cast bar left / right", min = -200, max = 200, step = 1, unit = "px",
          desc = "Moves the detached cast bars sideways from their side.", disabled = notOwnBar("party") },
        { type = "slider", key = "partyCastbar.y", label = "Party cast bar up / down", min = -100, max = 100, step = 1, unit = "px",
          desc = "Moves the detached cast bars up or down from their side.", disabled = notOwnBar("party") },
        { type = "slider", key = "partyCastbar.width", label = "Party cast bar width", min = 40, max = 400, step = 1,
          desc = "How wide each detached cast bar is. Under the frame it matches the frame's width.",
          disabled = notOwnBar("party") },
        { type = "slider", key = "partyCastbar.height", label = "Party cast bar height", min = 6, max = 40, step = 1,
          desc = "How tall each party cast bar is, inside its border. Not inside the frame, where it takes the power bar's place.",
          disabled = notOwnSize("party") },
        barRows("partyCastbar.media.bar", "the party's cast bars", "Party cast bar", off("partyCastbar.enabled"))[1],
        barRows("partyCastbar.media.bar", "the party's cast bars", "Party cast bar", off("partyCastbar.enabled"))[2],
        fontRow("partyCastbar.media.font", "Party cast bar font", "The spell name and time on the party's cast bars", off("partyCastbar.enabled")),
        { type = "toggle", key = "partyCastbar.showIcon", label = "Party cast bar spell icon",
          desc = "The spell's icon at the end of each detached cast bar.", disabled = notOwnBar("party") },
        castEnds("party", notOwnBar("party"), notOwnBar("party"), "Each detached cast bar. Sliding out under its frame, it follows the frame's own ends.")[1],
        castEnds("party", notOwnBar("party"), notOwnBar("party"), "Each detached cast bar. Sliding out under its frame, it follows the frame's own ends.")[2],
        { type = "toggle", key = "partyCastbar.reverseFill", label = "Party cast bar fills right to left",
          desc = "Each detached cast bar fills from the right.", disabled = notOwnBar("party") },
    } },
    castTextCard("party", "Party", "each party member's", true),
}

-- The combo pips' two end menus. Their inner end (slant) is the one by the
-- frame's angled end: the left under the target, the right under the player.
-- One pair per placement, the other hidden.
local function comboEnds(inner, hidden)
    local outer = inner == "right" and "left" or "right"
    local ends = {
        [inner] = { on = "combo.slant", flip = "combo.slantUnder" },
        [outer] = { on = "combo.slantOuter", flip = "combo.slantUnderOuter" },
    }
    return DaylightUI.Options.EndRows({ name = "Combo point", left = ends.left, right = ends.right,
        disabled = off("combo.enabled"), hidden = hidden })
end

ns.OPTIONS = { pages = {
    framePage("player", "Player", "Your own frame.",
        { castCards = PLAYER_CAST, power = true, powerToggle = true, powerFree = true, portraitFree = true, powerPos = true, tab = true, healthText = true, textPos = true, big = true, portrait = true, dragon = true, combat = true, auras = PLAYER_AURA_GROUPS,
          endNote = "The bars, and a cast bar hung under the frame, follow it." }),
    framePage("target", "Target", "Mirrors the player frame, with raid markers, the elite crest, and its buffs and debuffs.",
        { castCards = TARGET_CAST, power = true, powerToggle = true, powerFree = true, portraitFree = true, powerPos = true, tab = true, healthText = true, textPos = true, big = true, marker = true, crest = true, portrait = true, threat = true, threatTag = true, auras = TARGET_AURA_GROUPS, dots = true }),
    framePage("focus", "Focus", "The unit you set as focus.",
        { castCards = FOCUS_CAST, power = true, powerToggle = true, powerFree = true, portraitFree = true, powerPos = true, tab = true, healthText = true, textPos = true, marker = true, portrait = true, threat = true,
          auras = FOCUS_AURA_GROUPS }),
    framePage("party", "Party", "Your party: bars like your own frame, or square tiles (Portrait None and Name on the bar). Set how they line up, what shows, and move them as one in unlock mode.",
        { castCards = PARTY_CAST, power = true, powerPos = true, tab = true, healthText = true, textPos = true, big = true, marker = true, portrait = true, groupThreat = true,
          spacing = true, auraGroups = true, role = true, targetMark = true, pets = true,
          layout = true, tile = true, powerToggle = true, minWidth = 20, maxHeight = 120, strataWhat = "The layer the party frames draw in.",
          showDesc = "Turn the party frames on or off. While Use raid frames in a party (Unit Frames > Raid 10) is on, the raid frames show in a party instead and the rows on this page do nothing." }),
    raidPage(10), raidPage(20), raidPage(40),
    framePage("arena", "PvP Frames", "Enemy players carrying a flag in a battleground, one frame each. Right-click one to set it as your focus.",
        { power = true, powerToggle = true, powerPos = true, tab = true, healthText = true, textPos = true, marker = true, portrait = true, spacing = true,
          strataWhat = "The layer the PvP frames draw in.",
          showLabel = "Show the PvP frames", showDesc = "Turn the PvP frames on or off. When off, the game shows its own after a reload." }),
    framePage("targettarget", "Target of Target", "Who your target is looking at.", { healthText = true, textPos = true, flip = true,
        power = true, powerToggle = true, powerPos = true, portrait = true }),
    framePage("focustarget", "Focus Target", "Who your focus is looking at.", { healthText = true, textPos = true,
        power = true, powerToggle = true, powerPos = true, portrait = true }),
    framePage("partyTarget", "Party Targets", "Who each party member is targeting, in a small frame beside them. Click one to target it too.",
        { healthText = true, textPos = true, flip = true, power = true, powerToggle = true, powerPos = true, place = true,
          strataWhat = "The layer the party targets draw in.",
          showLabel = "Show party targets", showDesc = "A small frame beside each party member showing who they're targeting." }),
    framePage("pet", "Pet", "Your pet or minion.", { happiness = true, power = true, powerToggle = true, powerPos = true, healthText = true, textPos = true,
        tab = true, small = true, portrait = true, auras = PET_AURA_GROUPS }),

    { id = "colors", label = "Look", desc = "The frames' shape, class icons, and the bars' and names' colors on every unit frame.", groups = {
        { label = "Frame shape", items = {
            styleRow("look.style", false),
            { type = "slider", key = "look.slant", label = "Slant angle", min = 0.05, max = 0.4, step = 0.01, unit = "%",
              desc = "How far the frames' angled ends lean, on every unit frame and cast bar. 21% is the usual look." },
        } },
        { label = "Health and names", items = DaylightUI.Options.Join({
            { type = "dropdown", key = "colors.health", label = "Health bar color",
              values = { class = "Class and reaction", classGradient = "Class gradient", gradient = "By health (green to red)",
                         custom = "One color", customGradient = "Custom gradient", dark = "Dark (missing health colored)" },
              order = { "class", "classGradient", "gradient", "custom", "customGradient", "dark" },
              desc = "Class and reaction: players by class color, others by friendly, neutral or hostile. Dark: a near-black bar with the missing health in the class or reaction color." },
            { type = "color", key = "colors.healthColor", label = "Custom health color",
              desc = "Every health bar's color when Health bar color is One color.", disabled = function(get) return get("colors.health") ~= "custom" end },
        }, stopsRows("colors.healthGradient", "colors.health", "health", "every health bar"), {
            { type = "toggle", key = "colors.mirrorGradient", label = "Mirror the target's gradient",
              desc = "The target's and target of target's health and power gradients run the other way, so they mirror yours. Only for a horizontal gradient.",
              disabled = function(get)
                  local h, p = get("colors.health"), get("colors.power")
                  return h ~= "classGradient" and h ~= "customGradient" and p ~= "gradient" and p ~= "customGradient"
              end },
            { type = "slider", key = "colors.backBrightness", label = "Bar background brightness", min = 0, max = 1,
              step = 0.05, unit = "%", desc = "How much color the empty part of every health and power bar keeps. Lower is darker.",
              disabled = function(get) return get("colors.backMode") == "custom" end },
            { type = "dropdown", key = "colors.backMode", label = "Bar background color",
              values = { dim = "Dimmed bar color", custom = "One color" }, order = { "dim", "custom" },
              desc = "The empty part of every health and power bar: a dimmed copy of the bar's own color, or one you pick." },
            { type = "color", key = "colors.backColor", label = "Custom bar background color",
              desc = "The empty part's color when Bar background color is One color.", disabled = function(get) return get("colors.backMode") ~= "custom" end },
            { type = "slider", key = "colors.backAlpha", label = "Bar background opacity", min = 0, max = 1,
              step = 0.05, unit = "%",
              desc = "How solid the empty part of every health and power bar is. Lower lets the world show through it, like the game's own frames." },
            { type = "color", key = "colors.dotTint", label = "DoT damage left color", alpha = true,
              desc = "The shade over the health your damage over time spells will still take, on the target and on enemy nameplates." },
            { type = "dropdown", key = "colors.name", label = "Name color",
              values = { white = "White", class = "Class and reaction", classGradient = "Class gradient" },
              order = { "white", "class", "classGradient" },
              desc = "The names on every unit frame, unless a frame picks its own. Class and reaction: players by class color, others by friendly, neutral or hostile." },
        }) },
        { label = "Dead, offline and NPCs", desc = "The bar's color for dead and offline players and tapped NPCs, and for NPCs by how they feel about you. The NPC colors show with Class and reaction or Dark; Class gradient uses the pairs on General > Gradients.", items = {
            { type = "color", key = "colors.dead", label = "Dead", desc = "The health bar's color for a dead unit." },
            { type = "color", key = "colors.offline", label = "Offline", desc = "The health bar's color for a player who went offline." },
            { type = "color", key = "colors.tapped", label = "Tapped by someone else",
              desc = "The health bar's color for an NPC someone else tagged first." },
            { type = "color", key = "colors.hostile", label = "Hostile", desc = "The health bar's color for an NPC that attacks you." },
            { type = "color", key = "colors.neutral", label = "Neutral", desc = "The health bar's color for an NPC that leaves you alone until you hit it." },
            { type = "color", key = "colors.friendly", label = "Friendly", desc = "The health bar's color for a friendly NPC." },
        } },
        { label = "Dispel types", desc = "The border of a debuff you can dispel, and the raid tile's dispel icon.", items = {
            { type = "color", key = "colors.dispelMagic", label = "Magic", desc = "The color of a Magic debuff's border and dispel icon." },
            { type = "color", key = "colors.dispelCurse", label = "Curse", desc = "The color of a Curse debuff's border and dispel icon." },
            { type = "color", key = "colors.dispelDisease", label = "Disease", desc = "The color of a Disease debuff's border and dispel icon." },
            { type = "color", key = "colors.dispelPoison", label = "Poison", desc = "The color of a Poison debuff's border and dispel icon." },
        } },
        { label = "Power", items = DaylightUI.Options.Join({
            { type = "dropdown", key = "colors.power", label = "Power bar color",
              values = { type = "By power type", gradient = "Power gradient", custom = "One color", customGradient = "Custom gradient" },
              order = { "type", "gradient", "custom", "customGradient" },
              desc = "Power gradient: each power type's pair from the Gradients page (mana, rage, energy, focus)." },
            { type = "color", key = "colors.powerColor", label = "Custom power color",
              desc = "Every power bar's color when Power bar color is One color.", disabled = function(get) return get("colors.power") ~= "custom" end },
        }, stopsRows("colors.powerGradient", "colors.power", "power", "every power bar")) },
        { label = "Aggro", desc = "The ring (or name tab, or raid tile) that turns red while something is attacking the unit; an elite's dragon keeps its color, its eyes catch fire.", items = {
            { type = "dropdown", key = "colors.threat", label = "Aggro color",
              values = { health = "Same as Hostile", custom = "One color" }, order = { "health", "custom" },
              desc = "The color of a ring, name tab or raid tile while something is attacking the unit: the Hostile color, or one you pick." },
            { type = "color", key = "colors.threatColor", label = "Custom aggro color",
              desc = "The aggro color when Aggro color is One color.", disabled = function(get) return get("colors.threat") ~= "custom" end },
            { type = "color", key = "colors.threatWarn", label = "Close to pulling",
              desc = "In a group or with a pet, the target's ring (and threat tag) turns this color as you get close to pulling it." },
        } },
        { label = "Heals and shields", desc = "The bars that hang off the end of the health for incoming heals and absorb shields. An overshield (a shield bigger than the health missing) follows the shield.", items = {
            { type = "color", key = "colors.healColor", label = "Incoming heals",
              desc = "The color of the stretch past the health for heals on their way." },
            { type = "toggle", key = "colors.overheal", label = "Overheal",
              desc = "A heal bigger than the health missing runs a little past the health's end, so you see it would overheal. When off, the heal stops where the health is full." },
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
              values = { shield = "Same as shields", custom = "One color" }, order = { "shield", "custom" },
              desc = "The overshield in the absorb shields' color, or a color of its own.",
              disabled = function(get) return get("colors.overshield") == false end },
            { type = "color", key = "colors.overshieldColor", label = "Custom overshield color",
              desc = "The overshield's color when Overshield color is One color.",
              disabled = function(get) return get("colors.overshield") == false or get("colors.overshieldPaint") ~= "custom" end },
            { type = "dropdown", key = "colors.overshieldStyle", label = "Overshield texture", fallback = "shield",
              choices = function() return shieldTextures(true) end,
              desc = "The overshield's look: the same as the shield texture, or its own.",
              disabled = function(get) return get("colors.overshield") == false end },
        } },
        { label = "Class icons", desc = "On the portrait rings of the player, target and focus frames.", items = {
            { type = "dropdown", key = "portraits.icons", label = "Icon style",
              choices = UF.IconStyleChoices,
              desc = "Daylight UI's own icons, the Classic class icons, or with the Jiberish Fabled Icons addon installed, its Fabled styles "
                  .. "(art by JiberishUI and its artists, read from that addon's own folder)." },
            { type = "text", label = function()
                if UF.HasIconPack() then
                    return DaylightUI.L["Jiberish Fabled Icons is installed. Pick an icon for each class below, any style or one of its specs. The first icon on each line follows the Icon style."]
                end
                return DaylightUI.L["Install the Jiberish Fabled Icons addon to unlock more class icon styles."]
            end },
            classIconPicker,
        } },
    } },

    { id = "castbars", label = "Cast Bars", preview = { "castbars", "target", "focus", "party" },
      sample = function(parent) return ns.PageSample.NewCasts(parent) end, desc = "Animation, fill, colors and interrupts for every cast bar. Each bar's own settings are on its frame's page.", groups = {
        DaylightUI.Options.BarFxCard({ module = "UnitFrames", choices = {
            { id = "player", label = "Your cast bar", base = "playerCastbar.barFx.", kind = "cast", gate = off("playerCastbar.enabled") },
            { id = "target", label = "Target cast bar", base = "targetCastbar.barFx.", kind = "cast", gate = off("targetCastbar.enabled") },
            { id = "focus", label = "Focus cast bar", base = "focusCastbar.barFx.", kind = "cast", gate = off("focusCastbar.enabled") },
            { id = "party", label = "Party cast bars", base = "partyCastbar.barFx.", kind = "cast", gate = off("partyCastbar.enabled") },
        } }),
        { label = "Cast bar fill", items = {
            { type = "dropdown", key = "casts.fill", label = "Cast bar fill style", values = FILL_STYLES, order = FILL_ORDER,
              desc = "How every cast bar (yours, target's, focus's and party's) is filled: one color each, the Daylight gradient (the logo's blue to orange), a two-color gradient per kind of cast (set on the Gradients page), or a gradient in colors you pick." },
            { type = "toggle", key = "casts.flash", label = "Show interrupts",
              desc = "When a cast is interrupted, the bar stays full for a moment and says Interrupted." },
            { type = "toggle", key = "casts.channelTicks", label = "Channel ticks", since = "2.2.2",
              desc = "Thin lines on your cast bar where each tick of a channel lands (Drain Life, Mind Flay, Arcane Missiles, Penance...), so you can stop it right after one." },
            { type = "button", label = "Cast bar gradients", text = "Edit",
              desc = "Opens the Gradients page, where the Casts pairs are.",
              hidden = fillIsNot("casts.fill", "pair"),
              func = function() DaylightUI.OptionsPanel.Show("gradients") end },
        } },
        { label = "Your cast bar's colors", items = DaylightUI.Options.Join({
            { type = "toggle", key = "casts.classColor", label = "Class color on your cast bar",
              desc = "Your casts and channels in your class color, or your class's gradient with a two-color fill. Not with the Daylight gradient or a custom gradient.",
              disabled = noClassFill("casts.fill") },
            { type = "color", key = "casts.cast", label = "Casting color", hidden = fillIsNot("casts.fill", "plain"),
              desc = "Your cast bar's color while you cast." },
            { type = "color", key = "casts.channel", label = "Channeling color", hidden = fillIsNot("casts.fill", "plain"),
              desc = "Your cast bar's color while you channel." },
            { type = "color", key = "casts.interrupted", label = "Interrupted color", hidden = fillIs("casts.fill", "pair"),
              desc = "Your cast bar's color for a moment after your cast is interrupted.",
              disabled = function(get) return get("casts.flash") ~= true end },
            { type = "color", key = "casts.locked", label = "Can't be interrupted", hidden = fillIs("casts.fill", "pair"),
              desc = "The bar's color while the cast can't be interrupted." },
        }, stopsRows("casts.customGradient", "casts.fill", "cast bar", "your cast bar")) },
        { label = "Spell colors",
          desc = "Your cast bar in a color of its own for the spells you pick, like Drain Life in green and Drain Soul in purple. Every rank takes it, whatever the fill style. A cast that can't be interrupted keeps its warning color.",
          items = { spellColorItem } },
        { label = "Other cast bars' colors", items = DaylightUI.Options.Join({
            { type = "toggle", key = "targetCasts.classColor", label = "Class color on other cast bars",
              desc = "A player's casts in their class color, or their class's gradient with a two-color fill. Creatures' casts keep the fill style. Not with the Daylight gradient or a custom gradient.",
              disabled = noClassFill("casts.fill") },
            { type = "color", key = "targetCasts.cast", label = "Casting color", hidden = fillIsNot("casts.fill", "plain"),
              desc = "The target, focus and party cast bars' color while they cast." },
            { type = "color", key = "targetCasts.channel", label = "Channeling color", hidden = fillIsNot("casts.fill", "plain"),
              desc = "The target, focus and party cast bars' color while they channel." },
            { type = "color", key = "targetCasts.interrupted", label = "Interrupted color", hidden = fillIs("casts.fill", "pair"),
              desc = "The target, focus and party cast bars' color for a moment after their cast is interrupted.",
              disabled = function(get) return get("casts.flash") ~= true end },
            { type = "color", key = "targetCasts.locked", label = "Can't be interrupted", hidden = fillIs("casts.fill", "pair"),
              desc = "The bar's color while the cast can't be interrupted." },
        }, stopsRows("targetCasts.customGradient", "casts.fill", "target cast bar", "the target, focus and party cast bars")) },
        { label = "Interrupts", items = {
            { type = "toggle", key = "casts.kickMark", label = "Interrupt ready mark", since = "1.7.2",
              desc = "While your interrupt is on cooldown, a thin line on an enemy target's or focus's cast bar shows where it comes back. No line: it's ready now, or it won't be back before the cast ends." },
            { type = "dropdown", key = "casts.kickStyle", label = "Interrupt animation",
              values = DaylightUI.Motion.KICK_NAMES, order = DaylightUI.Motion.KICKS,
              desc = "What a target's, focus's or party member's cast bar does when its cast is interrupted. Your own interrupts light up in your accent color." },
            { type = "toggle", key = "casts.kickedBy", label = "Show who interrupted",
              desc = "\"Kicked by\" and the player's name in their class color, beside a target's, focus's or party member's cast bar for a moment." },
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
            { type = "dropdown", key = "swing.visibility", label = "Swing timer visibility",
              values = { swinging = "While swinging", combat = "In combat", always = "Always" },
              order = { "swinging", "combat", "always" },
              desc = "While swinging: each bar only while its swing runs, gone between swings. In combat: all your bars while you're fighting. A bar detached on its own has its own.",
              disabled = off("swing.enabled") },
            { type = "toggle", key = "swing.attach", invert = true, label = "Detach as group",
              desc = "Takes the bars out from under the player frame so you can move them together (/dui unlock); they slide out of their own box. When off, they hang under the player frame, under the cast bar while it hangs there, even with the cast bar detached. With your cast bar between your frame and the target's, they fan out under it instead, each a little wider.",
              disabled = function(get)
                  return get("swing.enabled") ~= true or (get("personal.enabled") == true and get("personal.swing") == true)
              end },
            { type = "slider", key = "swing.width", label = "Swing timer width", min = 80, max = 500, step = 1,
              desc = "How wide the swing timer bars are. Only when detached as a group. Hung under the player frame, the bars match its width.",
              disabled = groupAttached },
            { type = "slider", key = "swing.height", label = "Swing timer height", min = 6, max = 30, step = 1, unit = "px",
              desc = "How tall each swing timer bar is.", disabled = off("swing.enabled") },
            barRows("swing.media.bar", "the swing timer", "Swing timer", off("swing.enabled"))[1],
            barRows("swing.media.bar", "the swing timer", "Swing timer", off("swing.enabled"))[2],
            DaylightUI.Options.EndRows({ name = "Swing timer", disabled = groupAttached, note = "Hung under the frame it follows the frame's own ends.",
                left = { on = "swing.slantLeft", flip = "swing.slantUnderLeft" }, right = { on = "swing.slant", flip = "swing.slantUnder" } })[1],
            DaylightUI.Options.EndRows({ name = "Swing timer", disabled = groupAttached, note = "Hung under the frame it follows the frame's own ends.",
                left = { on = "swing.slantLeft", flip = "swing.slantUnderLeft" }, right = { on = "swing.slant", flip = "swing.slantUnder" } })[2],
            angleRows({ own = "swing.ownAngle", lean = "swing.lean", name = "Swing timer", what = "the swing timer's", since = "2.0",
                        note = "Only when detached as a group.",
                        disabled = function(get) return groupAttached(get) or (get("swing.slant") ~= true and get("swing.slantLeft") ~= true) end })[1],
            angleRows({ own = "swing.ownAngle", lean = "swing.lean", name = "Swing timer", what = "the swing timer's", since = "2.0",
                        note = "Only when detached as a group.",
                        disabled = function(get) return groupAttached(get) or (get("swing.slant") ~= true and get("swing.slantLeft") ~= true) end })[2],
            { type = "toggle", key = "swing.showIcon", label = "Swing timer weapon icon",
              desc = "The weapon's picture at the start of each bar. Only when detached as a group.", disabled = groupAttached },
            { type = "slider", key = "swing.textSize", label = "Swing timer text size", min = 6, max = 24, step = 1,
              desc = "The hand and time on each bar. Attached under the cast bar, it's kept small enough for the bar.",
              disabled = off("swing.enabled") },
            fontRow("swing.media.font", "Swing timer font", "The swing timer's hand and time", off("swing.enabled")),
            { type = "toggle", key = "swing.reverseFill", label = "Swing timer fills right to left",
              desc = "The bars fill from the right. Only when detached as a group.", disabled = groupAttached },
            { type = "slider", key = "swing.spacing", label = "Swing timer spacing", min = 0, max = 10, step = 1, unit = "px",
              desc = "The gap between the swing timer bars. Only when detached as a group.", disabled = groupAttached },
            { type = "toggle", key = "swing.growUp", label = "Swing timers grow upward",
              desc = "Main hand at the bottom, the others above it. Only when detached as a group.",
              disabled = groupAttached },
            strataRow("swing.strata", "Swing timer layer", "The layer the swing timer draws in when detached, as a group or a bar on its own.",
                off("swing.enabled"), " Hung under the player frame or the cast bar, it draws with them instead."),
        } },
        DaylightUI.Fade.Card("swing.fade.", nil, off("swing.enabled"), "Swing timer", { noFloat = true }),
        shellCard("swing", "swing.enabled", true),
        DaylightUI.Options.BarFxCard({ module = "UnitFrames", choices = {
            { id = "swing", label = "Swing timer", base = "swing.barFx.", kind = "swing", gate = off("swing.enabled") },
        } }),
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
        { label = "Colors", items = DaylightUI.Options.Join({
            { type = "dropdown", key = "swing.fill", label = "Swing timer fill style", values = FILL_STYLES, order = FILL_ORDER,
              desc = "How each hand's bar is filled: one color each, the Daylight gradient (the logo's blue to orange), a two-color gradient per hand (set on the Gradients page), or a gradient in colors you pick. A queued attack always keeps its own color.",
              disabled = off("swing.enabled") },
            { type = "toggle", key = "swing.classColor", label = "Class color on the swing timer",
              desc = "Every hand's bar in your class color, or your class's gradient with a two-color fill. A queued attack keeps its own color. Not with the Daylight gradient or a custom gradient.",
              disabled = function(get) return get("swing.enabled") ~= true or noClassFill("swing.fill")(get) end },
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
            { type = "button", label = "Swing timer gradients", text = "Edit",
              desc = "Opens the Gradients page, where the Swing timers pairs are.",
              hidden = fillIsNot("swing.fill", "pair"),
              func = function() DaylightUI.OptionsPanel.Show("gradients") end },
        }, stopsRows("swing.customGradient", "swing.fill", "swing timer", "the swing timer bars", off("swing.enabled"))) },
    } },

    { id = "personal", label = "Personal Display", preview = { "personal" },
      sample = function(parent) return ns.PageSample.New("personal", parent) end, desc = "Your health and power just under your character, the way Legion's personal display sat at your feet.", groups = {
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
            DaylightUI.Options.EndRows({ name = "Personal display", disabled = off("personal.enabled"),
                note = "Docked cast and swing bars are cut at the same ends, leaning the usual way.",
                left = { on = "personal.slantLeft", flip = "personal.slantUnderLeft" }, right = { on = "personal.slant", flip = "personal.slantUnder" } })[1],
            DaylightUI.Options.EndRows({ name = "Personal display", disabled = off("personal.enabled"),
                note = "Docked cast and swing bars are cut at the same ends, leaning the usual way.",
                left = { on = "personal.slantLeft", flip = "personal.slantUnderLeft" }, right = { on = "personal.slant", flip = "personal.slantUnder" } })[2],
            angleRows({ own = "personal.ownAngle", lean = "personal.lean", name = "Personal display", what = "the personal display's", since = "2.0",
                        note = "Docked cast and swing bars lean with it.",
                        disabled = function(get) return get("personal.enabled") ~= true or (get("personal.slant") ~= true and get("personal.slantLeft") ~= true) end })[1],
            angleRows({ own = "personal.ownAngle", lean = "personal.lean", name = "Personal display", what = "the personal display's", since = "2.0",
                        note = "Docked cast and swing bars lean with it.",
                        disabled = function(get) return get("personal.enabled") ~= true or (get("personal.slant") ~= true and get("personal.slantLeft") ~= true) end })[2],
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
            strataRow("personal.strata", "Personal display layer", "The layer the personal display draws in. Low keeps it under your other frames.",
                off("personal.enabled")),
        } },
        { label = "Combo points", desc = "Rogues and druids: your combo points under the personal display's bars.", items = {
            { type = "toggle", key = "personal.combo", label = "Combo points on the personal display",
              desc = "Rogues and druids: your combo points under the bars, in the colors from Unit Frames > Combo Points & Range.", disabled = off("personal.enabled") },
            { type = "toggle", key = "personal.comboStretch", label = "Personal combo points match the width",
              desc = "Spreads the combo point pips across the personal display. Turn it off to set the pips' own width.",
              disabled = offAny("personal.enabled", "personal.combo") },
            { type = "slider", key = "personal.comboSize", label = "Personal combo point width", min = 8, max = 40, step = 1, unit = "px",
              desc = "How wide each combo point pip under the personal display is. Not while the pips match the display's width.",
              disabled = function(get) return get("personal.enabled") ~= true or get("personal.combo") == false or get("personal.comboStretch") ~= false end },
            { type = "slider", key = "personal.comboHeight", label = "Personal combo point height", min = 0, max = 30, step = 1, unit = "px",
              desc = "How tall the combo point pips under the personal display are. Set to 0 for automatic height.",
              disabled = offAny("personal.enabled", "personal.combo") },
            { type = "slider", key = "personal.comboX", label = "Personal combo points left / right", min = -50, max = 50, step = 1, unit = "px",
              desc = "Nudges the personal display's row of combo points sideways.", disabled = offAny("personal.enabled", "personal.combo") },
            { type = "slider", key = "personal.comboY", label = "Personal combo points up / down", min = -50, max = 50, step = 1, unit = "px",
              desc = "Nudges the personal display's row of combo points up or down. Docked cast and swing bars stay below it.", disabled = offAny("personal.enabled", "personal.combo") },
        } },
        { label = "Docked bars", desc = "Your cast bar and swing timers under the personal display, as wide as it and cut like it.", items = {
            { type = "toggle", key = "personal.swing", label = "Swing timers on the personal display",
              desc = "Moves your swing timers under the personal display, as wide as it.", disabled = off("personal.enabled") },
            { type = "toggle", key = "personal.castbar", label = "Cast bar on the personal display",
              desc = "Moves your cast bar under the personal display, as wide as it.", disabled = off("personal.enabled") },
        } },
        shellCard("personal", "personal.enabled"),
        DaylightUI.Options.BarFxCard({ module = "UnitFrames", choices = {
            { id = "health", label = "Health bar", base = "personal.barFx.health.", kind = "health",
              gate = function(get) return get("personal.enabled") ~= true or get("personal.showHealth") == false end },
            { id = "power", label = "Power bar", base = "personal.barFx.power.", kind = "power",
              gate = function(get) return get("personal.enabled") ~= true or get("personal.showPower") == false end },
        } }),
        personalTextCard(),
        PERSONAL_AURA_GROUPS[1],
        PERSONAL_AURA_GROUPS[2],
        PERSONAL_AURA_GROUPS[3],
        DaylightUI.Fade.Card("personal.fade.", nil, off("personal.enabled"), "Personal display"),
    } },

    { id = "extras", label = "Combo Points & Range", desc = "Combo points for rogues and druids, and how frames fade out of range.", groups = {
        { label = "Combo points", desc = "For rogues, and druids in cat form. Small pips on your target or player frame.", items = DaylightUI.Options.Join({
            { type = "toggle", key = "combo.enabled", label = "Show combo points",
              desc = "Replaces the game's own combo points." },
            { type = "dropdown", key = "combo.anchor", label = "Attach to",
              values = { target = "Target frame", player = "Player frame", free = "On its own" }, order = { "target", "player", "free" },
              desc = "Which frame the pips sit on. On its own, they show with your target and you move them anywhere with /dui unlock.", disabled = off("combo.enabled") },
            { type = "dropdown", key = "combo.side", label = "Combo points side",
              values = { below = "Below the frame", above = "Above the frame" }, order = { "below", "above" },
              desc = "Under the frame, or over it, clear of the name. The target's buffs or debuffs on that side move out of the way.",
              disabled = comboAttached },
            { type = "dropdown", key = "combo.align", label = "Combo points alignment",
              values = { inner = "Inner end", center = "Centered", outer = "Outer end" }, order = { "inner", "center", "outer" },
              desc = "Where along the frame the row starts: the angled end facing the middle of your screen, the middle, or the far end.",
              disabled = function(get) return comboAttached(get) or get("combo.stretch") == true end },
            { type = "slider", key = "combo.x", label = "Combo points left / right", min = -50, max = 50, step = 1, unit = "px",
              desc = "Nudges the row of pips sideways.", disabled = comboAttached },
            { type = "slider", key = "combo.y", label = "Combo points up / down", min = -50, max = 50, step = 1, unit = "px",
              desc = "Nudges the row of pips up or down.", disabled = comboAttached },
            { type = "toggle", key = "combo.stretch", label = "Match frame width",
              desc = "The pips widen to span the whole frame, so the row reads like a bar. On its own, the row takes the target frame's width.",
              disabled = off("combo.enabled") },
            { type = "slider", key = "combo.size", label = "Pip width", min = 8, max = 40, step = 1, unit = "px",
              desc = "How wide each combo point pip is. Not while the pips match the frame's width.", disabled = function(get) return get("combo.enabled") ~= true or get("combo.stretch") == true end },
            { type = "slider", key = "combo.height", label = "Pip height", min = 0, max = 30, step = 1, unit = "px",
              desc = "How tall each combo point pip is. 0 picks a height to suit the frame.", disabled = off("combo.enabled") },
            { type = "slider", key = "combo.gap", label = "Combo point spacing", min = 0, max = 10, step = 1, unit = "px",
              desc = "The gap between combo point pips.", disabled = off("combo.enabled") },
            barRows("combo.media.bar", "the combo points", "Combo point", off("combo.enabled"))[1],
            barRows("combo.media.bar", "the combo points", "Combo point", off("combo.enabled"))[2],
            { type = "slider", key = "combo.border", label = "Combo point border", min = 0, max = 4, step = 1, unit = "px",
              desc = "How thick the border round each pip is. 0 leaves none.", disabled = off("combo.enabled") },
            comboEnds("left", function(get) return get("combo.anchor") == "player" end)[1],
            comboEnds("left", function(get) return get("combo.anchor") == "player" end)[2],
            comboEnds("right", function(get) return get("combo.anchor") ~= "player" end)[1],
            comboEnds("right", function(get) return get("combo.anchor") ~= "player" end)[2],
            { type = "dropdown", key = "combo.colorMode", label = "Combo point colors",
              values = { color = "One color", blend = "Color to full color", class = "Class color",
                         gradient = "One gradient", points = "A gradient per point", customGradient = "Custom gradient" },
              order = { "color", "blend", "class", "gradient", "points", "customGradient" },
              desc = "One color on every pip; colors shading from Combo point color to Full color along the row; your class color; two-color pairs from the Gradients page (Combo points), one for all pips or one each; or colors you pick, running along the row. Your nameplates' combo points use the same colors.",
              disabled = off("combo.enabled") },
        }, stopsRows("combo.customGradient", "combo.colorMode", "combo point", "the row of combo points", off("combo.enabled")), {
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
            { type = "slider", key = "combo.empty", label = "Empty pip brightness", min = 0, max = 1, step = 0.05, unit = "%",
              desc = "How bright the pips you haven't filled are, as a share of their color. Lower makes the filled ones stand out more.",
              disabled = off("combo.enabled") },
        }) },
        { label = "Range fade", desc = "Dims units that are out of reach: target, focus, their targets, party, party targets, raid and PvP frames. Your group by your heal, anyone else by the spell you pick.", items = {
            { type = "toggle", key = "range.enabled", label = "Fade when out of range",
              desc = "Your group fades by your heal's range, or the game's own check without one. Anyone else fades only with a range spell picked below." },
            { type = "dropdown", key = "range.spell", label = "Range spell", since = "1.8.0", fallback = "none",
              desc = "Target, focus and the PvP frames fade when this spell can't reach someone outside your group, like an enemy you want to cast on. Units it can't be cast on stay as they are.",
              disabled = function(get) return get("range.enabled") ~= true end,
              choices = rangeSpellChoices },
            { type = "slider", key = "range.alpha", label = "Out of range opacity", min = 0.1, max = 0.9, step = 0.05, unit = "%",
              desc = "How see-through a frame gets while its unit is out of range.", disabled = function(get) return get("range.enabled") ~= true end },
            { type = "toggle", key = "range.groupOwn", label = "Separate opacity for party and raid",
              desc = "Party and raid frames fade to their own opacity instead of the one above.",
              disabled = function(get) return get("range.enabled") ~= true end },
            { type = "slider", key = "range.alphaGroup", label = "Party and raid out of range opacity", min = 0.1, max = 0.9, step = 0.05, unit = "%",
              desc = "How see-through party and raid frames get while a member is out of range.", disabled = function(get) return get("range.enabled") ~= true or get("range.groupOwn") ~= true end },
        } },
    } },
    -- Click-casting (ClickCastPage.lua).
    ns.ClickCastPage,
    -- Aura lists (AuraListsPage.lua).
    ns.AuraListsPage,
} }
