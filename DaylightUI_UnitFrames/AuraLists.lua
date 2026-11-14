-- Aura lists: named lists of spells shared by every unit frame, like ElvUI's
-- filters. A "hide" list leaves its spells off a row, a "show only" list makes
-- the row show nothing else. Each aura row picks one of each (and debuff rows
-- can also show only boss debuffs or leave out long ones).
--
-- The client's aura containers do the matching (candidateFilters), so no aura
-- is ever read in a fight. They change a group's filters in place, so a list
-- edit reaches every row at once without a reload.
--
-- The client only matches spell ids where it can't give away a fight's
-- secrets (AuraContainerUtil.CanApplyIdentityCandidateFilters): buffs on
-- anyone you can help, debuffs on enemies, and a few harmless spells it marks
-- never secret (Sated, Exhaustion) anywhere. Elsewhere a hide list does
-- nothing and a show-only list shows nothing, so those rows don't offer one.
--
-- Settings: auraLists.<id> = { name, mode = "hide" | "only", spells = "id id id" }.
-- Each spell is kept by id, every rank its own id.

local _, ns = ...
local DUI = DaylightUI
local isSecret = DUI.IsSecret
local L = DUI.L

local AL = {}
ns.AuraLists = AL

AL.KEY = "auraLists"
AL.BUILTIN = { "hidden", "watch" }
AL.NONE = "none"
AL.MODES = { hide = "Hide these", only = "Show only these" }

-- Which container kinds may use a show-only list (spell ids are matched there),
-- and which are debuff rows (boss only, longest shown).
AL.ONLY_KINDS = { buff = true, selfbuff = true, tilebuff = true, debuff = true }
AL.DEBUFF_KINDS = { debuff = true, selfdebuff = true, gdebuff = true }

local function lists()
    local t = DUI:Get("UnitFrames", AL.KEY)
    return type(t) == "table" and t or {}
end

-- Every list as { id, name, mode }: the two built in first, then the player's
-- own in the order they were made.
function AL.All()
    local out, t = {}, lists()
    for _, id in ipairs(AL.BUILTIN) do
        if type(t[id]) == "table" then out[#out + 1] = id end
    end
    local own = {}
    for id, v in pairs(t) do
        if type(v) == "table" and type(id) == "string" and id:match("^l%d+$") then own[#own + 1] = id end
    end
    table.sort(own, function(a, b) return tonumber(a:sub(2)) < tonumber(b:sub(2)) end)
    for _, id in ipairs(own) do out[#out + 1] = id end
    return out
end

function AL.Get(id)
    local v = type(id) == "string" and lists()[id]
    return type(v) == "table" and v or nil
end

function AL.IsBuiltin(id) return id == "hidden" or id == "watch" end

function AL.ModeOf(id)
    local v = AL.Get(id)
    return v and (v.mode == "only" and "only" or "hide") or nil
end

-- The list's name as shown: a built-in one translated.
function AL.Label(id)
    local v = AL.Get(id)
    if not v then return "" end
    local name = type(v.name) == "string" and v.name ~= "" and v.name or id
    return AL.IsBuiltin(id) and L[name] or name
end

-- Choices for a row's pick of mode ("hide" or "only"): None, then each list
-- of that mode.
function AL.Choices(mode)
    local values, order = { [AL.NONE] = "None" }, { AL.NONE }
    for _, id in ipairs(AL.All()) do
        if AL.ModeOf(id) == mode then values[id], order[#order + 1] = AL.Label(id), id end
    end
    return values, order
end

-- A list's spell ids as a set, or nil when it's empty or gone. Cached by the
-- saved text, so the same table goes to every container.
local setCache = {}
local function parse(text)
    if type(text) ~= "string" or text == "" then return nil end
    local hit = setCache[text]
    if hit ~= nil then return hit or nil end
    local set, any = {}, false
    for n in text:gmatch("%d+") do
        set[tonumber(n)] = true
        any = true
    end
    setCache[text] = any and set or false
    return any and set or nil
end

function AL.Ids(id)
    local v = AL.Get(id)
    return v and parse(v.spells) or nil
end

-- ---------------------------------------------------------------------
-- What each container shows
-- ---------------------------------------------------------------------

-- A row's picks from a unit row's settings (targetAuras...): kind is "debuff"
-- or "buff".
function AL.FromRow(cfg, kind)
    cfg = type(cfg) == "table" and cfg or {}
    return { hide = cfg[kind .. "Hide"], only = cfg[kind .. "Only"],
             boss = cfg[kind .. "Boss"] == true, maxTime = tonumber(cfg[kind .. "MaxTime"]) or 0 }
end

-- A party or raid aura group's picks (auras.debuffs, auras.x1...).
function AL.FromGroup(g)
    g = type(g) == "table" and g or {}
    return { hide = g.hide, only = g.only, boss = g.boss == true, maxTime = tonumber(g.maxTime) or 0 }
end

-- The candidate filters for group g of container c, from the group's own
-- spell list (heals, a plugin's) and the row's picks. nil when there are none.
function AL.Filters(c, g)
    local p = c and c.dluiPicks or nil
    local kind = c and c.dluiKind
    local own = g and g.ids and g.ids() or nil
    local cand = {}
    local any = false
    local include = own
    local only = p and AL.ONLY_KINDS[kind] and AL.ModeOf(p.only) == "only" and AL.Ids(p.only) or nil
    if only then
        if include then
            local both = {}
            for id in pairs(include) do if only[id] then both[id] = true end end
            include = both
        else
            include = only
        end
    end
    if include then cand.includeSpellIDs, any = include, true end
    local hide = p and AL.ModeOf(p.hide) == "hide" and AL.Ids(p.hide) or nil
    if hide then cand.excludeSpellIDs, any = hide, true end
    if p and AL.DEBUFF_KINDS[kind] then
        if p.boss then cand.isBossAura, any = true, true end
        local t = tonumber(p.maxTime) or 0
        if t > 0 then cand.maxDuration, any = t, true end
    end
    return any and cand or nil
end

-- Containers given picks, so a list edit reaches them all.
local known = setmetatable({}, { __mode = "k" })
local version = 0

local function sigOf(p)
    if not p then return "" end
    return table.concat({ tostring(p.hide), tostring(p.only), tostring(p.boss), tostring(p.maxTime), version }, "|")
end

local groupsOfKind

-- Puts the current filters on every group c has. A container the client
-- won't change right now (under restrictions) gets them once that lifts.
local function push(c)
    if not (c and c.dluiGroups and c.SetAuraGroupCandidateFilters) or ns.Auras.IsPlain(c) then return end
    local failed = false
    for _, g in ipairs(groupsOfKind(c.dluiKind)) do
        if c.dluiGroups[g.key] then
            local ok = pcall(c.SetAuraGroupCandidateFilters, c, g.key, AL.Filters(c, g))
            failed = failed or not ok
        end
    end
    if failed then
        c.dluiSig = nil
        DUI.AfterRestrictions(function() AL.Push(c) end, c)
    end
end

function groupsOfKind(kind)
    local k = ns.Auras.KINDS[kind]
    return k and k.groups or {}
end

-- Gives container c a row's picks. Groups added later take them as they're
-- made (Auras.AddGroup); the ones it has change only when the picks did.
function AL.Use(c, picks)
    if not c then return end
    known[c] = true
    c.dluiPicks = picks
    local sig = sigOf(picks)
    if c.dluiSig == sig then return end
    local had = c.dluiSig ~= nil or next(c.dluiGroups or {}) ~= nil
    c.dluiSig = sig
    if had then push(c) end
end

function AL.Push(c)
    if not c then return end
    c.dluiSig = sigOf(c.dluiPicks)
    push(c)
end

-- A list changed: every container takes its new spells.
function AL.Changed()
    version = version + 1
    for c in pairs(known) do AL.Push(c) end
end

-- ---------------------------------------------------------------------
-- Editing lists (the Aura Lists page)
-- ---------------------------------------------------------------------

local function save(id, field, value)
    DUI:Set("UnitFrames", AL.KEY .. "." .. id .. "." .. field, value)
end

local function writeIds(id, set)
    local ids = {}
    for n in pairs(set) do ids[#ids + 1] = n end
    table.sort(ids)
    for i, n in ipairs(ids) do ids[i] = tostring(n) end
    save(id, "spells", table.concat(ids, " "))
end

local function nameOf(id)
    local ok, name = pcall(C_Spell.GetSpellName, id)
    return ok and type(name) == "string" and name ~= "" and name or nil
end
AL.NameOf = nameOf

local function iconOf(id)
    local ok, icon = pcall(C_Spell.GetSpellTexture, id)
    return ok and icon or nil
end

-- Whether the client matches this spell on every unit (it marks it never
-- secret), not just buffs on friends and debuffs on enemies.
function AL.Everywhere(id)
    local get = C_Secrets and C_Secrets.GetSpellAuraSecrecy
    local levels = Enum and Enum.SecrecyLevel
    if not (get and levels) then return false end
    local ok, s = pcall(get, id)
    return ok and s == levels.NeverSecret
end

-- Spells seen on units around you, by name: { [name] = { [id] = true } }.
-- Gathered when the page asks, out of combat, so the name box can suggest
-- them and every rank seen is added with a name.
local seen = {}
AL.SEEN_MAX = 40

local SCAN_UNITS = { "player", "target", "focus", "pet", "mouseover" }
local function remember(name, id)
    if type(name) ~= "string" or name == "" or type(id) ~= "number" then return end
    seen[name] = seen[name] or {}
    seen[name][id] = true
end

-- Reads the auras on you, your target, focus, pet and group. Skipped while
-- they're secret (a fight, a restricted area).
function AL.Scan()
    if InCombatLockdown() or DUI.Restricted() then return end
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not get then return end
    local units = {}
    for _, u in ipairs(SCAN_UNITS) do units[#units + 1] = u end
    local raid = IsInRaid()
    for i = 1, raid and 40 or 4 do units[#units + 1] = (raid and "raid" or "party") .. i end
    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
                for i = 1, AL.SEEN_MAX do
                    local ok, a = pcall(get, unit, i, filter)
                    if not ok or type(a) ~= "table" then break end
                    local name, id = a.name, a.spellId
                    if isSecret(name) or isSecret(id) then break end
                    remember(name, id)
                end
            end
        end
    end
end

-- Your class's heals and buffs (HealSpells.lua), every rank, as more names to find.
local function classSpells(each)
    for _, fam in ipairs(ns.HealSpells.Mine()) do
        for id in pairs(ns.HealSpells.Ranks(fam.id)) do each(id) end
    end
end

-- Every id known under name: seen on a unit, your class's lists, your spellbook.
local function idsNamed(name)
    local out = {}
    for id in pairs(seen[name] or {}) do out[id] = true end
    classSpells(function(id) if nameOf(id) == name then out[id] = true end end)
    local ok, info = pcall(C_Spell.GetSpellInfo, name)
    if ok and type(info) == "table" and type(info.spellID) == "number" then out[info.spellID] = true end
    return out
end

-- Names that start with what was typed, for the name box (W.Complete).
function AL.Suggest(text)
    text = strtrim(text or "")
    if #text < 2 or text:match("^%d+$") then return nil end
    local low, names, have = text:lower(), {}, {}
    local function try(name)
        if name and not have[name] and name:lower():find(low, 1, true) == 1 then
            have[name] = true
            names[#names + 1] = name
        end
    end
    for name in pairs(seen) do try(name) end
    classSpells(function(id) try(nameOf(id)) end)
    table.sort(names)
    return names
end

-- Adds a spell to list id by name or spell id, every rank known with it.
-- Returns the name added, or nil and why not.
function AL.Add(id, text)
    local v = AL.Get(id)
    text = strtrim(text or "")
    if not v or text == "" then return nil end
    local ids, name
    local n = tonumber(text)
    AL.Scan()
    if n then
        name = nameOf(n)
        if not name then return nil, L["No spell has that ID."] end
        ids = idsNamed(name)
        ids[n] = true
    else
        ids = idsNamed(text)
        if next(ids) == nil then
            -- Typed in another case than the game's.
            local low = text:lower()
            for seenName in pairs(seen) do
                if seenName:lower() == low then text = seenName; ids = idsNamed(seenName); break end
            end
        end
        if next(ids) == nil then
            return nil, L["No aura by that name seen yet. Type its spell ID, or add it while it's on you, your target or your group."]
        end
        name = text
    end
    local set = {}
    for k in pairs(AL.Ids(id) or {}) do set[k] = true end
    for k in pairs(ids) do set[k] = true end
    writeIds(id, set)
    return name
end

-- Takes every rank of name off list id.
function AL.Remove(id, name)
    local set = {}
    for k in pairs(AL.Ids(id) or {}) do
        if nameOf(k) ~= name then set[k] = true end
    end
    writeIds(id, set)
end

-- The list's spells for drawing, one line per name: { name, ids, icon, everywhere }.
function AL.Entries(id)
    local byName, order = {}, {}
    for n in pairs(AL.Ids(id) or {}) do
        local name = nameOf(n) or tostring(n)
        local e = byName[name]
        if not e then
            e = { name = name, ids = {}, icon = iconOf(n), everywhere = false }
            byName[name] = e
            order[#order + 1] = e
        end
        e.ids[#e.ids + 1] = n
        e.everywhere = e.everywhere or AL.Everywhere(n)
    end
    table.sort(order, function(a, b) return a.name < b.name end)
    return order
end

-- A new empty list of mode; returns its id.
function AL.New(name, mode)
    local top = 0
    for id in pairs(lists()) do
        local n = type(id) == "string" and tonumber(id:match("^l(%d+)$"))
        if n and n > top then top = n end
    end
    local id = "l" .. (top + 1)
    save(id, "name", name)
    save(id, "mode", mode == "only" and "only" or "hide")
    save(id, "spells", "")
    return id
end

function AL.Rename(id, name)
    if AL.Get(id) and not AL.IsBuiltin(id) and type(name) == "string" and strtrim(name) ~= "" then
        save(id, "name", strtrim(name))
    end
end

-- A built-in list can't be deleted, only emptied. Rows that picked a
-- deleted list show as if they picked None.
function AL.Delete(id)
    if AL.IsBuiltin(id) then
        save(id, "spells", "")
    elseif AL.Get(id) then
        DUI:Set("UnitFrames", AL.KEY .. "." .. id, nil)
    end
end

-- The module's OnSettingChanged hands list edits here instead of a layout.
function AL.IsListPath(path)
    return type(path) == "string" and (path == AL.KEY or path:find("^" .. AL.KEY .. "%.") ~= nil)
end
