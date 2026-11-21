-- The rich card for a player: a banner in their class light (icon, first and
-- last name, level at the right, spec and race tags), their guild, where a
-- group member is, item level and target, their health and power, and a
-- friendly player's buffs out of combat.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style
local isSecret = DUI.IsSecret
local L = DUI.L

local Players = {}
ns.RichPlayers = Players

Players.ICON = 38
Players.ICON_INSET = 2
Players.AFTER_BANNER = 16 -- the banner's own room under it, then the rows
Players.BEFORE_BARS = 12
Players.BAR_GAP = 3
Players.FACTION_COLORS = { Alliance = { 0.50, 0.72, 1.00 }, Horde = { 1.00, 0.52, 0.48 } }

local function plain(v)
    if isSecret(v) then return nil end
    return v
end

function Players.Is(unit) return plain(UnitIsPlayer(unit)) == true end

-- The class's icon: the unit frames' pick when that module is on, else
-- Daylight UI's own.
function Players.Icon(token)
    if type(DUI.ClassIcon) == "function" then
        local file, l, r, t, b = DUI.ClassIcon(token)
        if file then return file, { l or 0, r or 1, t or 0, b or 1 } end
    end
    return DUI.MEDIA .. "class\\" .. string.lower(token) .. ".tga", { 0, 1, 0, 1 }
end

-- Their spec's name when the client knows it (only after an inspect, never
-- asked for here), else their class's.
function Players.SpecOrClass(unit)
    local CS = C_SpecializationInfo
    local byID = _G.GetSpecializationInfoByID
    if CS and type(CS.GetInspectSpecialization) == "function" and type(byID) == "function"
        and plain(UnitIsUnit(unit, "player")) ~= true then
        local id = plain(CS.GetInspectSpecialization(unit))
        if type(id) == "number" and id > 0 then
            local _, name = byID(id)
            name = plain(name)
            if type(name) == "string" and name ~= "" then return name end
        end
    end
    return plain((UnitClass(unit)))
end

-- Their item level, only when the game already has it (yours, or someone's
-- after an inspect).
function Players.ItemLevel(unit)
    local v
    if plain(UnitIsUnit(unit, "player")) == true then
        if type(_G.GetAverageItemLevel) == "function" then
            local overall, equipped = _G.GetAverageItemLevel()
            v = plain(equipped) or plain(overall)
        end
    elseif C_PaperDollInfo and type(C_PaperDollInfo.GetInspectItemLevel) == "function" then
        v = plain(C_PaperDollInfo.GetInspectItemLevel(unit))
    end
    if type(v) == "number" and v > 0 then return math.floor(v) end
    return nil
end

-- The class's pair as { dark, light } and its plain color.
function Players.ClassPair(unit)
    local G = DUI.Gradients
    if not G then return nil end
    local lo, hi = G.PaintRGB(G.KeyFor(unit))
    if type(lo) ~= "table" or type(hi) ~= "table" then return nil end
    return { lo, hi }
end

local function hexOf(c) return DUI.Win.Parts.Hex(c) end

-- The first name white, the last name tan, as one title.
function Players.Title(unit)
    local first = plain(UnitName(unit))
    local full = plain(DUI.UnitName(unit, "tooltip"))
    if type(first) ~= "string" then return full end
    if type(full) == "string" and #full > #first and full:sub(1, #first) == first then
        local last = full:sub(#first + 1):gsub("^%s+", "")
        if last ~= "" then return first .. " " .. hexOf(Style.INK.LABEL) .. last .. "|r" end
    end
    return first
end

local function rgb(r, g, b) return { r, g, b } end

-- Who a unit is targeting, as { name, color }: "You" in WARN, anyone else in
-- their class or reaction color. Nil when nothing, or when it's hidden.
function Players.Target(unit)
    local target = unit .. "target"
    if plain(UnitExists(target)) ~= true then return nil end
    local name = plain(DUI.UnitName(target, "tooltip"))
    if type(name) ~= "string" then return nil end
    if plain(UnitIsUnit(target, "player")) == true then return { L["You"], Style.INK.WARN } end
    local r, g, b = ns.Tooltip.UnitColor(target)
    return { name, r and rgb(r, g, b) or Style.INK.VALUE }
end

-- The rows under the banner. Returns how many it added.
local function rows(p, unit)
    local Panel, Tip = ns.RichPanel, ns.Tooltip
    local cfg = Tip.Config()
    local added = 0
    local guild, rank = Tip.GuildOf(unit)
    if guild then
        local value = guild
        if cfg.guildRank and rank then value = guild .. " " .. hexOf(Style.INK.LABEL) .. "· " .. rank .. "|r" end
        Panel.Row(p, GUILD or L["Guild"], value, Style.INK.TEXT)
        added = added + 1
    end
    local zone = Tip.ZoneOf(unit)
    if zone then
        Panel.Row(p, ZONE or L["Zone"], zone, Style.INK.TEXT)
        added = added + 1
    end
    local level = Players.ItemLevel(unit)
    if level then
        Panel.Row(p, L["Item level"], tostring(level), rgb(Style.Accent()))
        added = added + 1
    end
    local target = cfg.showTarget and Players.Target(unit) or nil
    if target then
        Panel.Row(p, L["Targeting"], target[1], target[2])
        added = added + 1
    end
    return added
end

-- Builds the card. data: the unit's tooltip data (its own lines come first
-- in the tooltip; anything after them is another addon's, in p.foreign).
function Players.Card(p, tip, unit, data, n, lines)
    local Panel, Tip = ns.RichPanel, ns.Tooltip
    local cfg = Tip.Config()
    local token = plain((select(2, UnitClass(unit))))
    local pair = Players.ClassPair(unit)
    local light = pair and { pair[2], pair[1] } or nil
    Panel.Begin(p, "unit", light)
    -- A name the game hides (a PvP match) is still drawn: the header only shows it.
    local title = Players.Title(unit) or (lines[1] and lines[1].left) or DUI.UnitName(unit, "tooltip") or ""
    local cr, cg, cb
    if token then cr, cg, cb = Style.ClassColor(token) end
    local tags, Tag = {}, ns.RichItems.Tag
    local spec = Players.SpecOrClass(unit)
    if spec then tags[#tags + 1] = Tag(spec, cr and rgb(cr, cg, cb) or Style.INK.TEXT) end
    -- The level sits big at the right of the name, in how hard they are for
    -- you, the same spot as on a creature's card.
    local lv, lvInk = ns.RichWorld.Level(unit)
    -- The race in its faction's color: the other side reads at a glance.
    local race = plain((UnitRace(unit)))
    if type(race) == "string" then
        local faction = plain((UnitFactionGroup(unit)))
        tags[#tags + 1] = Tag(race, Players.FACTION_COLORS[faction] or Style.INK.TEXT)
    end
    local icon, coords
    local cfg = ns.Tooltip.Config()
    if token and not (cfg and cfg.portraits == false) then icon, coords = Players.Icon(token) end
    Panel.Header(p, { icon = icon, iconCoords = coords, iconSize = Players.ICON, iconInset = Players.ICON_INSET,
        iconTile = icon and pair or nil, title = title, tags = tags, wash = cr and rgb(cr, cg, cb) or nil,
        right = lv, rightColor = lvInk, rightSize = Style.SIZE.title })
    -- The same room under the banner with or without rows: without it the
    -- health sat right on the banner, inside its wash.
    Panel.Gap(p, Players.AFTER_BANNER)
    rows(p, unit)
    -- Other addons' lines mixed in with the rows, when set so (Rich/Foreign.lua).
    ns.RichForeign.Place(p, "mixed")
    Panel.Gap(p, Players.BEFORE_BARS)
    Panel.Bar(p, { unit = unit, health = true, h = 7, caption = HEALTH or L["Health"],
        pct = function(fs) DUI.Health.Write(fs, "percent", unit, true) end })
    local _, power = UnitPowerType(unit)
    power = plain(power)
    if type(power) == "string" then
        local r, g, b = Style.PowerColor(power)
        local lo, hi = DUI.Gradients.PairFrom({ r, g, b })
        Panel.Gap(p, Players.BAR_GAP)
        Panel.Bar(p, { unit = unit, power = true, h = 4, pair = { lo, hi } })
    end
    if cfg.buffs and not InCombatLockdown() and plain(UnitIsFriend("player", unit)) == true then
        local icons, count = Tip.BuffList(unit)
        if icons then
            Panel.Gap(p, Players.BEFORE_BARS)
            Panel.Icons(p, icons, count)
        end
    end
    ns.RichForeign.Place(p, "own")
    Panel.Finish(p)
end
