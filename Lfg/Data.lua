-- What the group finder window reads from C_LFGList, mirroring
-- Blizzard_GroupFinder_VanillaStyle: categories with activities at the player's level,
-- the player's listing, search results in the game's sort order, and the who list.
-- Names, notes and leaders come back secret during the client's chat lockdown. Secret
-- fields are left out (never compared or used as keys), and results whose basics are
-- secret are skipped.

local _, DUI = ...
DUI.Lfg = DUI.Lfg or {}
local ns = DUI.Lfg
local Style = DUI.Style

local Data = {}
ns.Data = Data

Data.MAX_ACTIVITIES = 16   -- Constants.LFGConstsExposed.GROUP_FINDER_MAX_ACTIVITY_CAPACITY
Data.MAX_WHO = 50          -- MAX_WHOS_FROM_SERVER
Data.ROLES = { "TANK", "HEALER", "DAMAGER" }
Data.ROLE_KEY = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }   -- C_LFGListRoles field names
-- A dungeon's slots (LFGBROWSE_DUNGEON_NUM_*_EXPECTED): one tank, one healer, three damage.
Data.DUNGEON = { TANK = 1, HEALER = 1, DAMAGER = 3 }

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end
function Data.Plain(v) if secret(v) then return nil end return v end
local plain = Data.Plain

local function api() return type(C_LFGList) == "table" and C_LFGList or nil end

-- Guarded call to C_LFGList[name]; returns everything, or nil.
function Data.Ask(name, ...)
    local L = api()
    local fn = L and L[name]
    if type(fn) ~= "function" then return nil end
    local res = { pcall(fn, ...) }
    if not res[1] then return nil end
    return select(2, unpack(res))
end
local ask = Data.Ask

function Data.Level()
    local l = UnitLevel and plain(UnitLevel("player"))
    return type(l) == "number" and l or 1
end

-- Activities and categories

Data.activities = {}   -- id -> the game's info table, read once

function Data.Activity(id)
    if type(id) ~= "number" then return nil end
    local a = Data.activities[id]
    if a then return a end
    a = ask("GetActivityInfoTable", id)
    if type(a) ~= "table" then return nil end
    Data.activities[id] = a
    return a
end

-- Short name when there is one, like LFGUtil_GetActivityInfoName.
function Data.ActivityName(id)
    local a = Data.Activity(id)
    if not a then return "" end
    local short = plain(a.shortName)
    return (type(short) == "string" and short ~= "") and short or (plain(a.fullName) or "")
end

-- "13-18", "60", or nothing (LFD_LEVEL_FORMAT_RANGE / _SINGLE).
function Data.Levels(a)
    local lo, hi = a.minLevelSuggestion or 0, a.maxLevelSuggestion or 0
    if lo == 0 and hi == 0 then return "" end
    if lo == hi or hi == 0 then return tostring(lo) end
    return lo .. "-" .. hi
end

-- Activity color relative to the player's level (like the game's trivial and difficult
-- fonts): too low is dimmed, too high warns, otherwise plain.
function Data.LevelColor(a)
    local me = Data.Level()
    local lo, hi = a.minLevelSuggestion or 0, a.maxLevelSuggestion or 0
    if hi ~= 0 and hi < me then return Style.INK.OFF end
    if lo ~= 0 and lo > me then return Style.INK.WARN end
    return Style.INK.VALUE
end

local function filterOff()
    if type(GetCVarBool) ~= "function" then return false end
    local ok, on = pcall(GetCVarBool, "disableSuggestedLevelActivityFilter")
    return ok and on == true
end

-- A category's activities at the player's level (LFGUtil_GetFilteredActivities): the
-- suggested range must include it unless that filter is off. The player's listed
-- activities always stay.
function Data.Filtered(cat)
    local ids = ask("GetAvailableActivities", cat)
    if type(ids) ~= "table" then return {} end
    local listed = {}
    local entry = Data.Entry()
    for _, id in ipairs(entry and entry.activityIDs or {}) do listed[id] = true end
    local me, keepAll = Data.Level(), filterOff()
    local out = {}
    for _, id in ipairs(ids) do
        local a = Data.Activity(id)
        if a then
            local lo, hi = a.minLevelSuggestion or 0, a.maxLevelSuggestion or 0
            if keepAll or listed[id] or not ((lo > 0 and lo > me) or (hi > 0 and hi < me)) then out[#out + 1] = id end
        end
    end
    return out
end

-- What the categories were read for: level, level filter, listed activities. Any change
-- re-reads them, and so does LFG_LIST_AVAILABILITY_UPDATE (Data.Forget).
local cats, catsFor
local function catsStamp()
    local e = Data.Entry()
    return Data.Level() .. "|" .. tostring(filterOff()) .. "|" .. table.concat(e and e.activityIDs or {}, ",")
end

function Data.Forget()
    Data.activities = {}
    cats, catsFor = nil, nil
end

-- Categories with something to do at the player's level: { id, name, auto }. Cached and
-- returned as the same table until an input changes, since every note keystroke and
-- roster change repaints the listing page.
function Data.Categories()
    local stamp = catsStamp()
    if cats and catsFor == stamp then return cats end
    local out = {}
    for _, id in ipairs(ask("GetAvailableCategories") or {}) do
        local c = ask("GetLfgCategoryInfo", id)
        if type(c) == "table" and #Data.Filtered(id) > 0 then
            out[#out + 1] = { id = id, name = plain(c.name) or "", auto = c.autoChooseActivity == true }
        end
    end
    cats, catsFor = out, stamp
    return out
end

function Data.Category(id)
    for _, c in ipairs(Data.Categories()) do if c.id == id then return c end end
    return nil
end

-- How List yourself (and Find's activity menu) sorts a category's activities: "level"
-- by suggested level (lowest first, none last) or "name" A to Z, from the
-- `activitySort` setting. Ties keep the game's order.
Data.SORTS = { "level", "name" }

local function levelKey(a)
    local lo, hi = a.minLevelSuggestion or 0, a.maxLevelSuggestion or 0
    if lo == 0 and hi == 0 then return math.huge, math.huge end
    if lo == 0 then lo = hi end
    if hi == 0 then hi = lo end
    return lo, hi
end

local function gameOrder(x, y)
    local ox, oy = x.info.orderIndex or 0, y.info.orderIndex or 0
    if ox ~= oy then return ox < oy end
    if x.name ~= y.name then return x.name < y.name end
    return x.id < y.id
end

local ORDER = {
    level = function(x, y)
        local xl, xh = levelKey(x.info)
        local yl, yh = levelKey(y.info)
        if xl ~= yl then return xl < yl end
        if xh ~= yh then return xh < yh end
        return gameOrder(x, y)
    end,
    name = function(x, y)
        local xn, yn = x.name:lower(), y.name:lower()
        if xn ~= yn then return xn < yn end
        return gameOrder(x, y)
    end,
}

function Data.SortMode()
    local mode = ns.Setting and ns.Setting("activitySort")
    return ORDER[mode] and mode or "level"
end

-- A category's activities under their groups (groups in the game's order,
-- LFGUtil_SortActivityGroupIDs), each group sorted by Data.SortMode.
function Data.Groups(cat)
    local byGroup, groups = {}, {}
    for _, id in ipairs(Data.Filtered(cat)) do
        local a = Data.Activity(id)
        local gid = a.groupFinderActivityGroupID or 0
        if not byGroup[gid] then
            local name, order = ask("GetActivityGroupInfo", gid)
            byGroup[gid] = { id = gid, name = plain(name) or "", order = plain(order) or 0, acts = {} }
            groups[#groups + 1] = byGroup[gid]
        end
        table.insert(byGroup[gid].acts, { id = id, name = Data.ActivityName(id), info = a })
    end
    table.sort(groups, function(x, y)
        if x.order ~= y.order then return x.order < y.order end
        if x.name ~= y.name then return x.name < y.name end
        return x.id < y.id
    end)
    local order = ORDER[Data.SortMode()]
    for _, g in ipairs(groups) do table.sort(g.acts, order) end
    return groups
end

-- The player's listing and group

-- The player's listing (plain), or nil.
function Data.Entry()
    if not ask("HasActiveEntryInfo") then return nil end
    local e = ask("GetActiveEntryInfo")
    if type(e) ~= "table" or secret(e.activityIDs) or type(e.activityIDs) ~= "table" then return nil end
    return e
end

-- LFGListingUtil_CanEditListing: solo, or group leader.
function Data.CanEdit()
    if not (IsInGroup and IsInGroup()) then return true end
    return UnitIsGroupLeader ~= nil and UnitIsGroupLeader("player") == true
end

function Data.GroupSize()
    if not (IsInGroup and IsInGroup()) then return 1 end
    local n = GetNumGroupMembers and plain(GetNumGroupMembers())
    return type(n) == "number" and n or 1
end

-- In a group of their own. The game's listing page checks the home party, so an
-- instance group alone still lists solo.
function Data.Grouped()
    return IsInGroup ~= nil and IsInGroup(LE_PARTY_CATEGORY_HOME) == true
end

-- Roles the player lists with (C_LFGListRoles), and the ones the game recommends for
-- the class (UnitGetAvailableRoles). Recommendations only; the game's page offers all
-- three to everyone. Never C_LFGList.GetAvailableRoles, which is spec-based, and an
-- Arms warrior can still list as a tank.
function Data.Roles()
    local R = type(C_LFGListRoles) == "table" and C_LFGListRoles or nil
    local ok, r = false, nil
    if R and R.GetRoles then ok, r = pcall(R.GetRoles) end
    r = (ok and type(r) == "table") and r or {}
    return { tank = r.tank == true, healer = r.healer == true, dps = r.dps == true }
end

function Data.SetRoles(roles)
    local R = type(C_LFGListRoles) == "table" and C_LFGListRoles or nil
    if not (R and R.SetRoles) then return false end
    local ok, took = pcall(R.SetRoles, { tank = roles.tank == true, healer = roles.healer == true, dps = roles.dps == true })
    return ok and took == true
end

-- In a group the role is a single pick (the game's listing menu calls UnitSetRole and
-- the answer is PLAYER_ROLES_ASSIGNED). nil: none, or secret.
function Data.GroupRole()
    return UnitGroupRolesAssigned and plain(UnitGroupRolesAssigned("player")) or nil
end

function Data.SetGroupRole(role)
    if type(UnitSetRole) == "function" then pcall(UnitSetRole, "player", role) end
end

function Data.Recommended()
    local t, h, d
    if type(UnitGetAvailableRoles) == "function" then t, h, d = UnitGetAvailableRoles("player") end
    t, h, d = plain(t), plain(h), plain(d)
    if t == nil and h == nil and d == nil then return { tank = true, healer = true, dps = true } end
    return { tank = t == true, healer = h == true, dps = d == true }
end

-- Playstyles (Enum.LFGEntryGeneralPlaystyle). A new listing needs one
-- (GROUP_FINDER_PLAYSTYLE_REQUIRED) and results carry theirs.

Data.PLAYSTYLES = { 1, 2, 3, 4 }   -- Learning, FunRelaxed, FunSerious, Expert

-- The game's label ("Learning", "Relaxed", "Competitive", "Carry Offered"), or nil.
function Data.PlaystyleWord(id)
    if type(id) ~= "number" or id < 1 or id > 4 then return nil end
    if type(GetGeneralPlaystyleString) == "function" then
        local ok, s = pcall(GetGeneralPlaystyleString, id)
        s = ok and plain(s) or nil
        if type(s) == "string" and s ~= "" then return s end
    end
    local s = _G["GROUP_FINDER_GENERAL_PLAYSTYLE" .. id]
    if type(s) == "string" and s ~= "" then return s end
    return DUI.L[({ "Learning", "Relaxed", "Competitive", "Carry Offered" })[id]]
end

-- Playstyle color by meaning: easygoing green, serious soft red, carry gold. Unknown
-- ones get none.
local STYLE_INK = { "GOOD", "GOOD", "DAMAGE", "MONEY" }
function Data.PlaystyleInk(id)
    local role = id and STYLE_INK[id]
    return role and Style.INK[role] or nil
end

-- Search results

-- One listing as the window shows it, or nil (gone, or its basics are secret).
-- { id, acts (ids), text (activity), leader { name, class, level },
-- members { { name, class, level, role, leader } }, solo, size (activity's max, 0 none),
-- counts (the game's), roles (a solo player's lfgRoles), note, age, mine, delisted,
-- newcomers, style (playstyle label), styleInk (its color) }
-- Members and leader carry zone (the client's areaName; a solo player is their own
-- leader), nil when not given.
function Data.Result(id)
    local r = ask("GetSearchResultInfo", id)
    if type(r) ~= "table" then return nil end
    local n, acts = plain(r.numMembers), plain(r.activityIDs)
    if type(n) ~= "number" or type(acts) ~= "table" then return nil end
    local out = { id = id, acts = acts, mine = plain(r.hasSelf) == true, delisted = plain(r.isDelisted) == true,
        age = plain(r.age), note = plain(r.comment), newcomers = plain(r.newPlayerFriendly) == true,
        style = Data.PlaystyleWord(plain(r.generalPlaystyle)), styleInk = Data.PlaystyleInk(plain(r.generalPlaystyle)),
        solo = n <= 1, members = {} }
    if type(out.note) == "string" and out.note == "" then out.note = nil end
    for i = 1, n do
        local m = ask("GetSearchResultPlayerInfo", id, i)
        if type(m) == "table" then
            local zone = plain(m.areaName)
            out.members[#out.members + 1] = { name = plain(m.name), class = plain(m.classFilename), level = plain(m.level),
                role = plain(m.assignedRole), leader = plain(m.isLeader) == true or i == 1, zone = zone ~= "" and zone or nil }
            if i == 1 then
                local lr = plain(m.lfgRoles)
                if type(lr) == "table" then out.roles = { tank = plain(lr.tank) == true, healer = plain(lr.healer) == true, dps = plain(lr.dps) == true } end
            end
        end
    end
    local lead = out.members[1] or {}
    out.leader = { name = lead.name or plain(r.leaderName), class = lead.class, level = lead.level, zone = lead.zone }
    local c = ask("GetSearchResultMemberCounts", id)
    out.counts = type(c) == "table" and c or {}
    -- Largest group size among its activities (LFGBrowseUtil_GetBestDisplayTypeForActivityIDs).
    local size, names = 0, {}
    for _, aid in ipairs(acts) do
        local a = Data.Activity(aid)
        if a and (a.maxNumPlayers or 0) > size then size = a.maxNumPlayers end
        names[#names + 1] = Data.ActivityName(aid)
    end
    out.size = size
    out.text = #names == 1 and names[1] or table.concat(names, ", ")
    return out
end

-- How many of each role a group has and still wants: { have = {}, open = {} }. For
-- five-player dungeons these are the game's REMAINING counts; bigger groups just count.
function Data.Places(r)
    local have, open = {}, {}
    for _, role in ipairs(Data.ROLES) do
        have[role] = plain(r.counts[role]) or 0
        open[role] = plain(r.counts[role .. "_REMAINING"]) or 0
    end
    return have, open
end

-- Does the listing have an open slot for one of the player's roles (HasRemainingSlotsForLocalPlayerRole).
local function slotFor(r, mine)
    local _, open = Data.Places(r)
    local t = open.TANK > 0 and mine.tank
    local h = open.HEALER > 0 and mine.healer
    local d = open.DAMAGER > 0 and mine.dps
    return (t or h or d) == true, t == true, h == true
end

-- The game's sort (LFGBrowseUtil_SortSearchResults): own listing first, then listings
-- matching the player's activities, then solo players first when in a group (groups
-- first when alone). Solo players by role (tank, healer, damage); groups by a slot for
-- the player's role, size, then tank and healer slots; then older first, then id.
function Data.Sort(list)
    local entry = Data.Entry()
    local listed = {}
    for _, id in ipairs(entry and entry.activityIDs or {}) do listed[id] = true end
    local inGroup = IsInGroup and IsInGroup() == true
    local mine = Data.Roles()
    local function match(r)
        for _, id in ipairs(r.acts) do if listed[id] then return true end end
        return false
    end
    local lead = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }
    table.sort(list, function(a, b)
        if a.mine ~= b.mine then return a.mine end
        if entry then
            local ma, mb = match(a), match(b)
            if ma ~= mb then return ma end
        end
        if a.solo ~= b.solo then
            if inGroup then return a.solo end
            return b.solo
        end
        if a.solo then
            for _, role in ipairs(Data.ROLES) do
                local ca = a.roles and a.roles[lead[role]] == true
                local cb = b.roles and b.roles[lead[role]] == true
                if ca ~= cb then return ca end
                if ca then break end
            end
        else
            local sa, ta, ha = slotFor(a, mine)
            local sb, tb, hb = slotFor(b, mine)
            if sa ~= sb then return sa end
            if #a.members ~= #b.members then return #a.members > #b.members end
            if ta ~= tb then return ta end
            if ha ~= hb then return ha end
        end
        local aa, ab = a.age or 0, b.age or 0
        if aa ~= ab then return aa > ab end
        return a.id < b.id
    end)
    return list
end

-- The last search's results (GetFilteredSearchResults), read and sorted.
function Data.Results()
    local _, ids = ask("GetFilteredSearchResults")
    local out = {}
    for _, id in ipairs(type(ids) == "table" and ids or {}) do
        local r = plain(id) and Data.Result(id)
        if r then out[#out + 1] = r end
    end
    return Data.Sort(out)
end

-- Invite: a solo listed player, when the player is alone, leads or assists
-- (LFGBrowseUtil_GetInviteActionForResult).
function Data.CanInvite(r)
    if not (r and r.solo and not r.mine and r.leader.name) then return false end
    if not (IsInGroup and IsInGroup()) then return true end
    return (UnitIsGroupLeader and UnitIsGroupLeader("player") == true) or (UnitIsGroupAssistant and UnitIsGroupAssistant("player") == true) or false
end

-- Whispers and invites, done the game's way

function Data.Whisper(name)
    if type(name) ~= "string" or name == "" then return end
    if type(ChatFrameUtil) == "table" and type(ChatFrameUtil.SendTell) == "function" then
        ChatFrameUtil.SendTell(name)
    elseif type(ChatFrame_SendTell) == "function" then
        ChatFrame_SendTell(name)
    end
end

function Data.Invite(name)
    if type(name) ~= "string" or name == "" then return end
    if type(C_PartyInfo) == "table" and type(C_PartyInfo.InviteUnit) == "function" then
        C_PartyInfo.InviteUnit(name)
    elseif type(InviteUnit) == "function" then
        InviteUnit(name)
    end
end

-- Who list

-- { { name, guild, level, race, class (label), token, zone } }, plus the total the
-- server found (more than 50 come back as 50).
function Data.Who()
    local F = type(C_FriendList) == "table" and C_FriendList or nil
    if not (F and F.GetNumWhoResults and F.GetWhoInfo) then return {}, 0 end
    local ok, num, total = pcall(F.GetNumWhoResults)
    num, total = ok and plain(num) or 0, ok and plain(total) or 0
    local out = {}
    for i = 1, (type(num) == "number" and num or 0) do
        local w = F.GetWhoInfo(i)
        if type(w) == "table" then
            out[#out + 1] = { name = plain(w.fullName), guild = plain(w.fullGuildName), level = plain(w.level), race = plain(w.raceStr),
                class = plain(w.classStr), token = plain(w.filename), zone = plain(w.area) }
        end
    end
    return out, type(total) == "number" and total or #out
end
