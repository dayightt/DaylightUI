-- The rich card for a player: a banner in their class light (icon, first and
-- last name, spec and level tags), their guild, item level and target, their
-- health and power, and a friendly player's buffs out of combat.

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
    local level = Players.ItemLevel(unit)
    if level then
        Panel.Row(p, L["Item level"], tostring(level), rgb(Style.Accent()))
        added = added + 1
    end
    local target = unit .. "target"
    if cfg.showTarget and plain(UnitExists(target)) == true then
        local name = plain(DUI.UnitName(target, "tooltip"))
        if type(name) == "string" then
            local color
            if plain(UnitIsUnit(target, "player")) == true then
                name, color = L["You"], Style.INK.WARN
            else
                local r, g, b = Tip.UnitColor(target)
                color = r and rgb(r, g, b) or Style.INK.VALUE
            end
            Panel.Row(p, L["Targeting"], name, color)
            added = added + 1
        end
    end
    return added
end

-- Lines in the tooltip beyond the game's own (another addon's), after a rule.
function Players.OtherLines(p, n, lines, from)
    if n < from then return end
    ns.RichPanel.Rule(p)
    ns.Rich.Lines(p, n, lines, from)
end

-- Builds the card. data: the unit's tooltip data (its own lines come first
-- in the tooltip; anything after them is another addon's).
function Players.Card(p, tip, unit, data, n, lines)
    local Panel, Tip = ns.RichPanel, ns.Tooltip
    local cfg = Tip.Config()
    local token = plain((select(2, UnitClass(unit))))
    local pair = Players.ClassPair(unit)
    local light = pair and { pair[2], pair[1] } or nil
    Panel.Begin(p, "unit", light)
    local title = Players.Title(unit) or (lines[1] and lines[1].left) or ""
    local cr, cg, cb
    if token then cr, cg, cb = Style.ClassColor(token) end
    local tags = {}
    local spec = Players.SpecOrClass(unit)
    if spec then tags[#tags + 1] = { spec, cr and rgb(cr, cg, cb) or Style.INK.LABEL } end
    local level, race = plain(UnitLevel(unit)), plain((UnitRace(unit)))
    if type(level) == "number" then
        local lv = level > 0 and tostring(level) or "??"
        tags[#tags + 1] = { type(race) == "string" and string.format(L["%s · %s"], lv, race) or lv, Style.INK.LABEL }
    end
    local icon, coords
    if token then icon, coords = Players.Icon(token) end
    Panel.Header(p, { icon = icon, iconCoords = coords, iconSize = Players.ICON, iconInset = Players.ICON_INSET,
        iconTile = pair, title = title, tags = tags, wash = cr and rgb(cr, cg, cb) or nil })
    Panel.Gap(p, Players.AFTER_BANNER)
    if rows(p, unit) == 0 then p.count = p.count - 1 end -- no rows: no room for them
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
    local own = type(data) == "table" and type(data.lines) == "table" and #data.lines or n
    Players.OtherLines(p, n, lines, own + 1)
    Panel.Finish(p)
end
