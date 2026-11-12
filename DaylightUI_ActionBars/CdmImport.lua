-- Builds a layout from a Cooldown Manager string, the text the game's own Cooldown
-- Manager exports (its settings' Export, the strings guides and other UIs share).
-- The string is only read here and never handed to the game, so the game's own
-- settings stay untouched.
-- Format, from Blizzard_CooldownViewer/CooldownViewerSettingsDataStoreSerialization.lua:
-- "<encoding version>|<payload>", version 1 = base64 of deflate of CBOR. The table:
-- [1] format version (1-5), [2] the active layout per class-and-spec tag, [3] layouts
-- by tag then layout id (v4+; by name before that), [4] layout id -> name (v4+).
-- A layout: [1] every cooldown id in order, [2] category -> ids moved there from
-- their default. Tag = class id * 10 + spec index.
-- Each of the game's four rows becomes a grid drawn the way the game draws that row
-- on this screen (Import.ViewerLooks: position, size, padding, items per line,
-- direction): Essential and Utility icons, tracked buffs as icons, tracked bars as
-- bars. The result is a new profile (CdmData), picked for the talent set.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Import = {}
ns.CdmImport = Import

local Data = ns.CdmData

-- The game's categories (Enum.CooldownViewerCategory) and where hidden ones go (its
-- data provider's cooldownCategoryToHiddenCategoryMapping).
Import.ESSENTIAL, Import.UTILITY, Import.BUFF, Import.BAR = 0, 1, 2, 3
Import.ROWS = { 0, 1, 2, 3 }
local ALL_CATEGORIES = { 0, 1, 2, 3, 7, 8, 5, 6 }
-- Enum.CooldownSetSpellFlags.HideByDefault (HideAura is 1). Most spells have two
-- entries: a cooldown one that's shown and a buff one with this flag, hidden.
local HIDE_BY_DEFAULT = 2

local function codec()
    local E = C_EncodingUtil
    if type(E) == "table" and E.DecodeBase64 and E.DecompressString and E.DeserializeCBOR then return E end
end

-- The string's table, or nil and the reason.
function Import.Read(text)
    if type(text) ~= "string" then return nil, L["nothing pasted"] end
    text = string.gsub(text, "%s", "")
    if text == "" then return nil, L["nothing pasted"] end
    local version, payload = string.match(text, "^(%d+)|(.+)$")
    if version ~= "1" then return nil, L["that isn't a Cooldown Manager string"] end
    local E = codec()
    if not E then return nil, L["this game client can't read it"] end
    local deflate = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate
    local ok, v = pcall(E.DecodeBase64, payload)
    if ok then ok, v = pcall(E.DecompressString, v, deflate) end
    if ok then ok, v = pcall(E.DeserializeCBOR, v) end
    if not ok or type(v) ~= "table" then return nil, L["it's damaged (was all of it copied?)"] end
    local fmt = v[1]
    if type(fmt) ~= "number" or fmt < 1 then return nil, L["it's damaged (was all of it copied?)"] end
    if fmt > 5 then return nil, L["it's from a newer game version"] end
    if type(v[3]) ~= "table" or next(v[3]) == nil then return nil, L["it has no layouts in it"] end
    return v
end

local function myClass()
    local _, _, id = UnitClass("player")
    return tonumber(id)
end

local function mySpec()
    local S = C_SpecializationInfo
    if type(S) == "table" and type(S.GetSpecialization) == "function" then
        local ok, spec = pcall(S.GetSpecialization)
        if ok and type(spec) == "number" then return spec end
    end
end

local function className(classID)
    if type(GetClassInfo) == "function" then
        local ok, name = pcall(GetClassInfo, classID)
        if ok and type(name) == "string" then return name end
    end
    return tostring(classID)
end

-- Picks the layout for this character's class: this spec's active one first, then
-- any of this spec, then any of this class. Returns { layout, name, tag } or nil and
-- the reason.
function Import.Pick(t)
    local class, spec = myClass(), mySpec()
    local active = type(t[2]) == "table" and t[2] or {}
    local names = type(t[4]) == "table" and t[4] or {}
    local mine, other = {}, nil
    for tag, layouts in pairs(t[3]) do
        local n = tonumber(tag)
        if n and type(layouts) == "table" then
            if math.floor(n / 10) == class then
                for key, layout in pairs(layouts) do
                    if type(layout) == "table" then
                        local name = names[key] or (type(key) == "string" and key) or nil
                        mine[#mine + 1] = { layout = layout, name = name, tag = n, key = key }
                    end
                end
            else
                other = other or n
            end
        end
    end
    if #mine == 0 then
        if other then return nil, string.format(L["it's made for a %s"], className(math.floor(other / 10))) end
        return nil, L["it has no layouts in it"]
    end
    local function score(c)
        local s = 0
        if spec and c.tag % 10 == spec then
            s = 2
            if active[c.tag] == c.key then s = 3 end
        end
        return s
    end
    table.sort(mine, function(a, b)
        local sa, sb = score(a), score(b)
        if sa ~= sb then return sa > sb end
        if a.tag ~= b.tag then return a.tag < b.tag end
        return tostring(a.key) < tostring(b.key)
    end)
    return mine[1]
end

local function info(id)
    local CV = C_CooldownViewer
    if type(CV) ~= "table" or type(CV.GetCooldownViewerCooldownInfo) ~= "function" then return nil end
    local ok, i = pcall(CV.GetCooldownViewerCooldownInfo, id)
    if ok and type(i) == "table" then return i end
end

local function defaultCategory(i)
    local cat = i.category
    local flags = tonumber(i.flags) or 0
    if bit and bit.band and bit.band(flags, HIDE_BY_DEFAULT) ~= 0 and (cat == 0 or cat == 1 or cat == 2 or cat == 3) then
        return -1   -- hidden, not in any row
    end
    return cat
end

-- The cooldown ids in each of the four rows, in the order the game itself rebuilds
-- from a string (CooldownViewerSettingsDataProvider CheckBuildDisplayData): the
-- string's order list, keeping only ids in this game's category sets, then every
-- other id of those sets in the sets' order (new since the string was made, or moved
-- without being listed; a move changes the row, not the place in line). Each goes in
-- its category (moved, else default). Like the game's rows, only what this character
-- knows: other races' racials, other specs' talents and unlearned spells are left out.
function Import.Rows(layout)
    local moved = {}
    if type(layout[2]) == "table" then
        for cat, ids in pairs(layout[2]) do
            if type(ids) == "table" then
                for _, id in ipairs(ids) do moved[id] = tonumber(cat) end
            end
        end
    end
    local defaults, inGame = {}, nil
    local CV = C_CooldownViewer
    if type(CV) == "table" and type(CV.GetCooldownViewerCategorySet) == "function" then
        inGame = {}
        for _, cat in ipairs(ALL_CATEGORIES) do
            local ok, ids = pcall(CV.GetCooldownViewerCategorySet, cat, true)
            if ok and type(ids) == "table" then
                for _, id in ipairs(ids) do
                    id = tonumber(id)
                    if id then defaults[#defaults + 1] = id; inGame[id] = true end
                end
            end
        end
    end
    local order, seen = {}, {}
    local function add(id)
        id = tonumber(id)
        if id and not seen[id] and (not inGame or inGame[id]) then seen[id] = true; order[#order + 1] = id end
    end
    if type(layout[1]) == "table" then for _, id in ipairs(layout[1]) do add(id) end end
    for _, id in ipairs(defaults) do add(id) end
    local rows = { [0] = {}, [1] = {}, [2] = {}, [3] = {} }
    for _, id in ipairs(order) do
        local i = info(id)
        if i and i.isKnown == true then
            local cat = moved[id]
            if cat == nil then cat = defaultCategory(i) end
            if rows[cat] then table.insert(rows[cat], id) end
        end
    end
    return rows
end

-- How the game draws each of its four rows, read off its viewers: their Edit Mode
-- settings kept on the viewer by CooldownViewerMixin (iconLimit, iconPadding,
-- iconScale, isHorizontal, iconDirection) and the item template sizes from
-- CooldownViewer.xml. That way an import comes out as the same grid in the same
-- spot, whatever the profile. EllesmereUI measures the laid-out items instead, but
-- ours are claimed into our layout, so the settings are read. The viewers are never
-- moved; their spot is the game's Edit Mode spot.
Import.VIEWERS = { [0] = "EssentialCooldownViewer", [1] = "UtilityCooldownViewer",
    [2] = "BuffIconCooldownViewer", [3] = "BuffBarCooldownViewer" }
Import.ITEM = { [0] = { 50, 50 }, [1] = { 30, 30 }, [2] = { 40, 40 }, [3] = { 220, 30 } }
Import.PAD_OFFSET = -4   -- CooldownViewerMixin:GetAdditionalPaddingOffset
local LEFT_DIR = 0       -- Enum.CooldownViewerIconDirection.Left (Right is 1)

local function plain(v) return type(v) == "number" and not (issecretvalue and issecretvalue(v)) and v == v end
local function field(v, key)
    local x = v[key]
    if issecretvalue and issecretvalue(x) then return nil end
    return x
end

-- { [category] = { x, y = the viewer's middle; vw, vh = its current size; point = its
-- anchor point; w, h = an item's size; gap; per = items per line; horizontal;
-- reverse = lines run left (across) or up (down) } } in Data's units (UIParent, from
-- screen center, y up). A viewer that's missing or returns nothing plain is left out.
function Import.ViewerLooks()
    local out = {}
    local us = UIParent and UIParent:GetEffectiveScale()
    if not plain(us) or us <= 0 then return out end
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    for cat, name in pairs(Import.VIEWERS) do
        local v = _G[name]
        if type(v) == "table" and type(v.GetCenter) == "function" then
            local ok, cx, cy = pcall(v.GetCenter, v)
            local okS, vs = pcall(v.GetEffectiveScale, v)
            local okW, vw, vh = pcall(function() return v:GetWidth(), v:GetHeight() end)
            if ok and okS and plain(cx) and plain(cy) and plain(vs) and vs > 0 then
                local k = vs / us
                local okP, point = pcall(v.GetPoint, v, 1)
                local scale = field(v, "iconScale")
                if not plain(scale) or scale <= 0 then scale = 1 end
                local pad = field(v, "iconPadding")
                if not plain(pad) then pad = 5 end
                local per = field(v, "iconLimit")
                if not plain(per) or per < 1 then per = 99 end
                local horizontal = field(v, "isHorizontal")
                if type(horizontal) ~= "boolean" then horizontal = cat ~= 3 end
                local dir = field(v, "iconDirection")
                local item = Import.ITEM[cat]
                out[cat] = {
                    x = cx * k - W / 2, y = cy * k - H / 2,
                    vw = (okW and plain(vw)) and vw * k or nil, vh = (okW and plain(vh)) and vh * k or nil,
                    point = (okP and type(point) == "string") and point or "CENTER",
                    w = item[1] * scale * k, h = item[2] * scale * k,
                    gap = math.max(0, (pad + Import.PAD_OFFSET) * k),
                    per = math.floor(per), horizontal = horizontal,
                    -- Horizontal rows follow the direction; vertical columns run
                    -- up when it says Right (CooldownViewerMixin:RefreshLayout).
                    reverse = horizontal and dir == LEFT_DIR or (not horizontal and dir ~= nil and dir ~= LEFT_DIR),
                }
            end
        end
    end
    return out
end

local function round(v) return math.floor(v + 0.5) end

-- How a row is drawn when the game has no viewer for it: Data's own sizes, in one
-- line, stacked around Essential (Utility under, buffs over, bars to the left).
local function fallback(cat, looks, counts)
    local ess = looks[0]
    local size, small = Data.LOOK.size, 30
    local base = ess or { x = Data.ORIGIN[1], y = Data.ORIGIN[2] - size / 2, w = size, h = size, gap = Data.GAP, per = 99 }
    local essTop = base.y + base.h / 2
    local essH = counts[0] > 0 and math.ceil(counts[0] / math.max(1, base.per)) * (base.h + base.gap) or 0
    if cat == 0 then
        return { x = base.x, y = base.y, point = "CENTER", w = size, h = size, gap = Data.GAP, per = 99, horizontal = true }
    elseif cat == 1 then
        return { x = base.x, y = essTop - essH - small / 2, point = "TOP", w = small, h = small, gap = Data.GAP, per = 99, horizontal = true }
    elseif cat == 2 then
        return { x = base.x, y = essTop + 6 + small / 2, point = "BOTTOM", w = small, h = small, gap = Data.GAP, per = 99, horizontal = true }
    end
    local wide = math.max(1, counts[0]) * (base.w + base.gap)
    return { x = base.x - wide / 2 - 12 - Data.LOOK.width / 2, y = essTop, point = "TOP",
        w = Data.LOOK.width, h = Data.LOOK.height, gap = 2, per = 99, horizontal = false }
end

-- One row as a grid of pieces, like the game's: `per` items per line, the next line
-- below (horizontal rows) or to the right (vertical columns), placed by the viewer's
-- anchor point. Its middle stays where the game's is unless it's anchored by an edge.
local function grid(set, ids, shape, look)
    local n = #ids
    if n == 0 then return end
    local per = math.max(1, math.min(look.per, n))
    local lines = math.ceil(n / per)
    local w, h, gap = look.w, look.h, look.gap
    local gw, gh
    if look.horizontal then
        gw, gh = per * w + (per - 1) * gap, lines * h + (lines - 1) * gap
    else
        gw, gh = lines * w + (lines - 1) * gap, per * h + (per - 1) * gap
    end
    local p = look.point
    local vw, vh = look.vw or gw, look.vh or gh   -- the game's row as it is now
    local left = p:find("LEFT") and look.x - vw / 2 or p:find("RIGHT") and look.x + vw / 2 - gw or look.x - gw / 2
    local top = p:find("TOP") and look.y + vh / 2 or p:find("BOTTOM") and look.y - vh / 2 + gh or look.y + gh / 2
    -- The anchor point says which edge the game keeps fixed as items come and go,
    -- so that edge stays fixed here too.
    local grow
    if look.horizontal then
        grow = p:find("LEFT") and "start" or p:find("RIGHT") and "end" or "center"
        if look.reverse and grow ~= "center" then grow = grow == "start" and "end" or "start" end
    else
        grow = p:find("TOP") and "start" or p:find("BOTTOM") and "end" or "center"
        if look.reverse and grow ~= "center" then grow = grow == "start" and "end" or "start" end
    end
    local along, across
    if look.horizontal then
        along, across = look.reverse and "left" or "right", "down"
    else
        along, across = look.reverse and "up" or "down", "right"
    end
    -- The first piece's top-left: the grid corner the lines start from.
    local fx = (along == "left") and (left + gw - w) or left
    local fy = (along == "up") and (top - gh + h) or top
    local first, lineFirst, prev
    for i, id in ipairs(ids) do
        if i == 1 then
            Data.AddPiece(set, id, shape, round(fx), round(fy))
            first, lineFirst = id, id
        else
            Data.AddPiece(set, id, shape, 0, 0)
            if (i - 1) % per == 0 then
                Data.Hook(set, id, lineFirst, across, "start")
                lineFirst = id
            else
                Data.Hook(set, id, prev, along, "center")
            end
        end
        prev = id
    end
    local chain = Data.Chain(set, first)
    chain.grow = grow
    chain.spacing = round(gap)
    if shape == "bar" then
        chain.look = { width = round(w), height = round(h) }
    else
        chain.look = { size = round(w) }
    end
end

-- Replaces set's layout with the four rows, each drawn the way the game draws it on
-- this screen (looks from Import.ViewerLooks; a row without one falls back to Data's
-- sizes around Essential).
function Import.Build(set, rows, looks)
    looks = looks or {}
    Data.Changed()
    set.v = Data.FORMAT
    set.pieces, set.chains = {}, {}
    set.blocks, set.buttons = nil, nil
    local counts = {}
    for cat = 0, 3 do counts[cat] = #(rows[cat] or {}) end
    for cat = 0, 3 do
        local look = looks[cat] or fallback(cat, looks, counts)
        grid(set, rows[cat] or {}, cat == 3 and "bar" or "icon", look)
    end
    return set
end

-- A sentence describing the picked layout, for the paste box.
function Import.Summary(pick, rows)
    local parts = {}
    local function n(count, one, many)
        if count > 0 then parts[#parts + 1] = string.format(count == 1 and one or many, count) end
    end
    n(#rows[0], L["%d cooldown"], L["%d cooldowns"])
    n(#rows[1], L["%d utility"], L["%d utility"])
    n(#rows[2], L["%d buff"], L["%d buffs"])
    n(#rows[3], L["%d bar"], L["%d bars"])
    local what = #parts > 0 and table.concat(parts, ", ") or L["no spells this character has"]
    if pick.name and pick.name ~= "" then
        return string.format(L["Layout %s: %s."], pick.name, what)
    end
    return string.format(L["The layout: %s."], what)
end

-- The paste box (Profiles.ShowPaste) for talent set g. The string is read as it's
-- typed, and Import makes it a new profile (named after the string's layout) picked
-- for g. refresh runs after.
function Import.Open(g, refresh)
    local Profiles = DUI.Profiles
    if not (Profiles and Profiles.ShowPaste) then return end
    Profiles.ShowPaste({
        title = L["Import a Cooldown Manager layout"],
        hint = string.format(L["Paste a layout string from the game's Cooldown Manager (its Export), a guide or another UI (Ctrl+V). It becomes a new profile, used by talent set %d."], g),
        read = function(text)
            local t, why = Import.Read(text)
            if not t then return nil, why end
            local pick, why2 = Import.Pick(t)
            if not pick then return nil, why2 end
            local rows = Import.Rows(pick.layout)
            local count = #rows[0] + #rows[1] + #rows[2] + #rows[3]
            if count == 0 then return nil, L["none of its spells are in this game"] end
            return { pick = pick, rows = rows }, Import.Summary(pick, rows)
        end,
        go = function(what)
            if InCombatLockdown() then return L["not in combat"] end
            if not Data.MyClass() then return L["try again in a moment"] end
            local set = Import.Build({ v = Data.FORMAT, pieces = {}, chains = {} }, what.rows, Import.ViewerLooks())
            local name = what.pick.name
            if type(name) ~= "string" or name == "" then name = L["Imported"] end
            local id = Data.NewProfile(name, nil, set)
            Data.Assign(g, id)
            if refresh then refresh() end
            DUI.Print(string.format(L["Imported the Cooldown Manager profile %s, used by talent set %d."],
                tostring(Data.Profile(id).name), g))
        end,
    })
end
