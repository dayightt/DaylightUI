-- Data for the social window: Battle.net friends, friend requests, recent allies,
-- ignores and the raid, read entry by entry into plain tables, plus the game's own
-- calls for each action (mirroring FriendsListUtil, FriendRequestsList,
-- Blizzard_RecentAllies and RaidFrameSocialView).
--
-- Friends are read with BNGetNumFriends + C_BattleNet.GetFriendAccountInfo(i), never
-- C_BattleNet.SearchFriends (flagged HasRestrictions); the search box filters what's
-- read. None of this is documented as secret, but a name that ever came back secret
-- would simply be left out.

local _, DUI = ...
DUI.Social = DUI.Social or {}
local ns = DUI.Social
local L = DUI.L

local Data = {}
ns.Data = Data

Data.CLIENT_WOW = "WoW"   -- BNET_CLIENT_WOW: a friend in some version of World of Warcraft
Data.GROUP_SIZE = 5       -- players per raid group (PLAYERS_PER_GROUP)
Data.GROUPS = 8           -- NUM_RAID_GROUPS

local secret = DUI.IsSecret
local function str(v) return type(v) == "string" and not secret(v) and v ~= "" and v or nil end
local function num(v) return type(v) == "number" and not secret(v) and v or nil end
local function plainBool(v) if type(v) == "boolean" and not secret(v) then return v end end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j, k, l = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h, i, j, k, l end
end

local function bn() return type(C_BattleNet) == "table" and C_BattleNet or nil end
local function allies() return type(C_RecentAllies) == "table" and C_RecentAllies or nil end
local function party() return type(C_PartyInfo) == "table" and C_PartyInfo or nil end

-- Seconds since a wall-clock time (lastOnlineTime, an interaction's timestamp).
local function ago(t)
    t = num(t)
    if not t or t <= 0 then return nil end
    return math.max(0, time() - t)
end

-- A duration as a count and its unit: minutes, hours, days or weeks.
local function span(seconds)
    if seconds < 3600 then return math.max(1, math.floor(seconds / 60)), "min" end
    if seconds < 86400 then return math.floor(seconds / 3600), "hour" end
    if seconds < 86400 * 14 then return math.floor(seconds / 86400), "day" end
    return math.floor(seconds / (86400 * 7)), "week"
end

-- A duration in words: "20 min", "2 hours", "3 days", "2 weeks".
function Data.Span(seconds)
    if type(seconds) ~= "number" then return "" end
    local n, unit = span(seconds)
    local fmt = unit == "min" and L["%d min"] or unit == "week" and L["%d weeks"]
        or unit == "hour" and (n == 1 and L["%d hour"] or L["%d hours"])
        or (n == 1 and L["%d day"] or L["%d days"])
    return string.format(fmt, n)
end

-- "3 days ago", "just now" (lastOnline, interactions). Each is a whole sentence
-- so a language can change the words around the number (German "vor 3 Tagen").
function Data.Ago(seconds)
    if type(seconds) ~= "number" then return "" end
    if seconds < 60 then return L["just now"] end
    local n, unit = span(seconds)
    local fmt = unit == "min" and L["%d min ago"] or unit == "week" and L["%d weeks ago"]
        or unit == "hour" and (n == 1 and L["%d hour ago"] or L["%d hours ago"])
        or (n == 1 and L["%d day ago"] or L["%d days ago"])
    return string.format(fmt, n)
end

-- Short age for a row's right edge: "20 min", "3 h", "2 d".
function Data.Short(seconds)
    if type(seconds) ~= "number" then return "" end
    if seconds < 3600 then return string.format(L["%d min"], math.max(1, math.floor(seconds / 60))) end
    if seconds < 86400 then return string.format(L["%d h"], math.floor(seconds / 3600)) end
    return string.format(L["%d d"], math.floor(seconds / 86400))
end

-- Friends (Battle.net, including title friends)

-- A friend's ruleset word ("PvP"), or the realm name whole when it has none.
function Data.Ruleset(realm) return DUI.Alts.RulesetOf(realm) or realm end

-- An unknown ruleset keeps the invite option: the game has the final say.
function Data.SameRuleset(realm) return DUI.Alts.SameRuleset(realm) end

Data.FACTIONS = { Alliance = true, Horde = true }

-- A faction as the game's token ("Alliance" or "Horde"): the Battle.net info gives that,
-- and a client that hands over the localized name gets it by the game's own words.
function Data.FactionOf(name)
    name = str(name)
    if not name then return nil end
    if Data.FACTIONS[name] then return name end
    if name == _G.FACTION_ALLIANCE then return "Alliance" end
    if name == _G.FACTION_HORDE then return "Horde" end
    return nil
end

-- Whether this server lets the two factions group (retail's cross-faction parties). The
-- game's party button asks this before it asks the friend's faction.
function Data.CanCrossFaction()
    local P = party()
    return P ~= nil and call(P.CanFormCrossFactionParties) == true
end

-- Same faction as the player's, as the game's party button asks, unless the server lets
-- the factions group. A friend whose faction isn't known is left to the game, like an
-- unknown ruleset.
function Data.SameFaction(f)
    local mine = type(UnitFactionGroup) == "function" and Data.FactionOf(UnitFactionGroup("player")) or nil
    return f == nil or f.faction == nil or mine == nil or f.faction == mine or Data.CanCrossFaction()
end

-- One game account's part of a friend: the character in this World of Warcraft, the
-- realm, or the other game they're in.
local function play(f, g)
    f.gameAccountID = num(g.gameAccountID)
    f.inGame = g.clientProgram == Data.CLIENT_WOW and (g.wowProjectID == nil or g.wowProjectID == WOW_PROJECT_ID)
    if f.inGame then
        f.char, f.class, f.level = str(g.characterName), str(g.classFilename), num(g.characterLevel)
        f.zone, f.race = str(g.areaName), str(g.raceName)
        f.faction = Data.FactionOf(g.factionName)
        -- What the game's party button reads besides: the game account to invite, its
        -- realm (0 = no info yet) and whether it's in this region.
        f.guid, f.realmID, f.region = str(g.playerGuid), num(g.realmID), plainBool(g.isInCurrentRegion)
        f.realmName = str(g.realmName)   -- to tell two players of one name apart
    end
    -- Like the game's own card: the display name, only within the player's region.
    if g.clientProgram == Data.CLIENT_WOW and g.isInCurrentRegion ~= false then
        f.realm = str(g.realmDisplayName) or str(g.realmName)
        f.ruleset = Data.Ruleset(f.realm)
    end
    if not f.char then f.game = str(g.richPresence) or (g.clientProgram == Data.CLIENT_WOW and L["World of Warcraft"]) or L["Battle.net"] end
    return f
end

-- The Battle.net app itself and its launcher count as game accounts too; the game's
-- own card leaves them out (BNET_CLIENT_APP, BNET_CLIENT_CLNT).
local function launcher(program)
    return program == (_G.BNET_CLIENT_APP or "App") or program == (_G.BNET_CLIENT_CLNT or "CLNT")
end

-- A friend can play on several game accounts at once (two copies of the game on one
-- Battle.net account). GetFriendAccountInfo gives only the one in focus; the rest are
-- read one by one, as the game's own friends card does.
local function accounts(index, focus)
    local B = bn()
    local n = index and B and num(call(B.GetFriendNumGameAccounts, index)) or 0
    if n < 2 then return nil end
    local out = {}
    for a = 1, n do
        local g = call(B.GetFriendGameAccountInfo, index, a)
        if type(g) == "table" and g.isOnline ~= false and g.hasFocus ~= true and not launcher(g.clientProgram)
            and not (focus and num(g.gameAccountID) == focus) then
            out[#out + 1] = play({}, g)
        end
    end
    return #out > 0 and out or nil
end

-- One friend: { id, account, tag, favorite, status ("on", "away", "busy", "off"),
-- inGame (in this World of Warcraft), char, class, level, zone, race, faction
-- ("Alliance" or "Horde"), ruleset, game (another game's name), lastOnline (seconds
-- ago), note, broadcast, gameAccountID, others (the other game accounts online, each
-- with the same character fields) }. index: its place in the friends list, to read
-- the other game accounts.
local function friend(info, index)
    if type(info) ~= "table" then return nil end
    local g = type(info.gameAccountInfo) == "table" and info.gameAccountInfo or {}
    local f = { id = num(info.bnetAccountID), account = str(info.accountName) or str(info.battleTag) or "?",
        tag = str(info.battleTag), favorite = info.isFavorite == true, note = str(info.note),
        broadcast = str(info.customMessage), gameAccountID = num(g.gameAccountID) }
    local online = g.isOnline == true
    if not online then
        f.status = "off"
        f.lastOnline = ago(info.lastOnlineTime)
        return f
    end
    if info.isDND == true or g.isGameBusy == true then f.status = "busy"
    elseif info.isAFK == true or g.isGameAFK == true then f.status = "away"
    else f.status = "on" end
    play(f, g)
    local others = accounts(index, f.gameAccountID)
    -- In focus is whatever they touched last: when that's another game and a character
    -- is in this one, the character leads, so the row, the filter and Invite see it.
    if others and not f.inGame then
        for i, o in ipairs(others) do
            if o.inGame then
                others[i] = play({}, g)
                for _, k in ipairs({ "inGame", "char", "class", "level", "zone", "race", "faction", "guid", "realmID",
                    "region", "realmName", "realm", "ruleset", "game", "gameAccountID" }) do
                    f[k] = o[k]
                end
                break
            end
        end
    end
    f.others = others
    return f
end

-- One friend by Battle.net account id (from a whisper conversation).
function Data.Friend(id)
    local B = C_BattleNet
    if type(B) == "table" and type(id) == "number" and type(B.GetAccountInfoByID) == "function" then
        -- Its place in the list too, so its other game accounts are read.
        local n, index = num(call(BNGetNumFriends)) or 0, nil
        for i = 1, n do
            local info = call(B.GetFriendAccountInfo, i)
            if type(info) == "table" and num(info.bnetAccountID) == id then index = i; break end
        end
        return friend(B.GetAccountInfoByID(id), index)
    end
end

-- Every friend in the client's order (online first).
function Data.Friends()
    local out = {}
    local B = bn()
    local n = call(BNGetNumFriends)
    if not (B and num(n)) then return out end
    for i = 1, n do
        local f = friend(call(B.GetFriendAccountInfo, i), i)
        if f then
            f.index = i
            out[#out + 1] = f
        end
    end
    return out
end

function Data.Online()
    local _, on = call(BNGetNumFriends)
    return num(on) or 0
end

function Data.Ignores()
    local out = {}
    local F = type(C_FriendList) == "table" and C_FriendList
    local n = F and num(call(F.GetNumIgnores)) or 0
    for i = 1, n do
        local name = str(call(F.GetIgnoreName, i))
        if name then out[#out + 1] = name end
    end
    return out
end

-- The player's own Battle.net status ("on", "away", "busy" or "hidden" when appearing
-- offline) and broadcast. BNGetInfo's 8th return says whether you appear offline, read
-- first like the game's own SocialUIUtil.GetPresenceTypeSelf.
function Data.Me()
    local _, tag, _, broadcast, afk, dnd, _, hidden = call(BNGetInfo)
    local status = hidden == true and "hidden" or afk == true and "away" or dnd == true and "busy" or "on"
    return status, str(broadcast), str(tag)
end

-- Only from a click (the calls are HasRestrictions). One call per click: two in a row (set Away, then
-- clear Busy) leave the game on Busy, and a later click can't undo it. Available clears the one that is
-- on; any pick while appearing offline shows you again first.
function Data.SetStatus(status)
    local B = bn()
    if not B then return end
    local now = Data.Me()
    if status == "hidden" then call(B.SetAppearOffline, true)
    elseif now == "hidden" then call(B.SetAppearOffline, false)
    elseif status == "away" then call(B.SetAFK, true)
    elseif status == "busy" then call(B.SetDND, true)
    elseif now == "away" then call(B.SetAFK, false)
    elseif now == "busy" then call(B.SetDND, false) end
end

function Data.Broadcast(text)
    local B = bn()
    if B then call(B.SetCustomMessage, text or "") end
end

function Data.WhisperFriend(f)
    if not (f and f.account) then return end
    DUI.Pad.Whisper({ bn = f.id, name = f.account })
end

-- Invite when they're in this game, on the same ruleset and faction (or a server that
-- lets them group), with their realm and region known, like the game's party button
-- (FriendsFrame_GetInviteRestriction). That function can't be asked: its player's
-- faction and realm are set only when the game's own friends window is shown, and
-- ours takes its place.
function Data.CanInviteFriend(f)
    return f ~= nil and f.inGame == true and f.gameAccountID ~= nil
        and f.realmID ~= 0 and f.region ~= false
        and Data.SameRuleset(f.realm) and Data.SameFaction(f)
        and not Data.InGroup(f.char, f.realmName)
end

-- The game's FriendsFrame_InviteOrRequestToJoin: a friend who is already in a group is
-- asked to be invited ("request"), anyone else is invited. The type comes from the
-- game's GetDisplayedInviteType when this client has it.
-- What the button does for this friend: "INVITE", or "REQUEST_INVITE" (ask to join theirs).
function Data.InviteKind(f)
    local kind = (f and f.guid and type(GetDisplayedInviteType) == "function") and call(GetDisplayedInviteType, f.guid) or nil
    return kind == "REQUEST_INVITE" and "REQUEST_INVITE" or "INVITE"
end

function Data.InviteFriend(f)
    local B = bn()
    if not (B and Data.CanInviteFriend(f)) then return end
    if Data.InviteKind(f) == "REQUEST_INVITE" and type(BNRequestInviteFriend) == "function" then
        call(BNRequestInviteFriend, f.gameAccountID)
    else
        call(B.InviteFriend, f.gameAccountID)
    end
end

function Data.SetNote(f, note) if f and f.id then call(BNSetFriendNote, f.id, note or "") end end
function Data.SetFavorite(f, on) if f and f.id then call(BNSetFriendFavoriteFlag, f.id, on == true) end end
function Data.Remove(f) if f and f.id then call(BNRemoveFriend, f.id) end end
function Data.Unignore(name) if type(C_FriendList) == "table" then call(C_FriendList.DelIgnore, name) end end

-- Add friend, in the game's order (AddFriendFrame_Accept): a BattleTag (or email) goes
-- to Battle.net, otherwise a title friend by character name, otherwise the old
-- character friends list.
function Data.AddFriend(text)
    text = str(text)
    if not text then return end
    local B = bn()
    local _, tag, _, _, _, _, realID = call(BNGetInfo)
    if (tag and text:find("#", 1, true)) or (realID and text:find("@", 1, true)) then
        call(BNSendFriendInvite, text, "")
    elseif B and call(B.AreTitleFriendsEnabled) then
        call(B.SendTitleFriendInviteByName, text)
    elseif type(C_FriendList) == "table" and call(C_FriendList.IsLegacyFriendSystemEnabled) then
        call(C_FriendList.AddFriend, text)
    end
end

-- Friend requests

function Data.Invites()
    local out = {}
    local B = bn()
    local n = num(call(BNGetNumFriendInvites)) or 0
    for i = 1, n do
        local info = B and call(B.GetFriendInviteInfo, i)
        if type(info) == "table" and num(info.inviteID) then
            out[#out + 1] = { id = info.inviteID, account = str(info.accountName) or "?", age = ago(info.creationTimestamp) }
        end
    end
    return out
end

function Data.Accept(id) call(BNAcceptFriendInvite, id) end
function Data.Decline(id) call(BNDeclineFriendInvite, id) end
-- Same as CONFIRM_BLOCK_INVITES' OnAccept in the game's dialog defs.
function Data.Block(id)
    local B = bn()
    if B then call(B.SetBlocked, id, true) end
    call(BNDeclineFriendInvite, id)
end

-- Recent allies

-- Shared activity by the game's interaction types (Enum.RolodexType): the chip groups,
-- and row text when the game gives none.
Data.KIND = { [1] = "party", [2] = "party", [12] = "party", [13] = "party", [14] = "party", [15] = "party",
    [16] = "party", [17] = "party", [3] = "trade", [5] = "trade", [6] = "trade", [7] = "trade", [8] = "trade",
    [9] = "trade", [10] = "trade", [4] = "whisper", [23] = "legacy" }
DUI.WithLanguage(function()
    Data.KIND_WORDS = { party = L["Grouped with you"], trade = L["Traded with you"], whisper = L["Whispered"], legacy = L["Legacy friend"] }
end)

local function classToken(id)
    local info = id and type(C_CreatureInfo) == "table" and call(C_CreatureInfo.GetClassInfo, id)
    return type(info) == "table" and str(info.classFile) or nil
end

-- One ally: { guid, name, class, level, online, status, pinned, legacy,
-- kind, what, when (seconds ago), note, location }.
local function ally(a)
    if type(a) ~= "table" or type(a.characterData) ~= "table" then return nil end
    local c, s = a.characterData, type(a.stateData) == "table" and a.stateData or {}
    local i = type(a.interactionData) == "table" and a.interactionData or {}
    local last = type(i.interactions) == "table" and i.interactions[1] or nil
    local out = { guid = str(c.guid), name = str(c.fullName) or str(c.name), short = str(c.name), class = classToken(num(c.classID)),
        level = num(c.level), online = s.isOnline == true, pinned = num(s.pinExpirationDate) ~= nil,
        legacy = s.isConvertedLegacyFriend == true, note = str(i.note), location = str(s.currentLocation),
        realm = str(c.realmName) }
    -- The race and its faction, from the character's race id.
    local raceID = num(c.raceID)
    local C = type(C_CreatureInfo) == "table" and C_CreatureInfo or nil
    if raceID and C then
        local race = call(C.GetRaceInfo, raceID)
        if type(race) == "table" then out.race = str(race.raceName) end
        local faction = call(C.GetFactionInfo, raceID)
        if type(faction) == "table" then out.faction = Data.FactionOf(faction.groupTag) or Data.FactionOf(faction.name) end
    end
    if not (out.guid and out.name) then return nil end
    out.status = not out.online and "off" or s.isDND == true and "busy" or s.isAFK == true and "away" or "on"
    if type(last) == "table" then
        out.kind = Data.KIND[last.type] or "other"
        out.what = str(last.description) or Data.KIND_WORDS[out.kind] or L["Met you"]
        out.when = ago(last.timestamp)
    else
        out.kind, out.what = out.legacy and "legacy" or "other", out.legacy and L["Legacy friend"] or L["Met you"]
    end
    return out
end

function Data.AlliesReady()
    local A = allies()
    return A ~= nil and call(A.IsRecentAllyDataReady) == true
end

-- The client's order (pinned, online, most recent).
function Data.Allies()
    local out = {}
    local A = allies()
    local list = A and call(A.GetRecentAllies)
    if type(list) ~= "table" then return out end
    for _, a in ipairs(list) do
        local x = ally(a)
        if x then out[#out + 1] = x end
    end
    return out
end

function Data.Pin(a, on) local A = allies(); if A and a then call(A.SetRecentAllyPinned, a.guid, on == true) end end
function Data.AllyNote(a, note) local A = allies(); if A and a then call(A.SetRecentAllyNote, a.guid, note or "") end end

-- Whispers and invites by character name (shared with the group finder)

-- A realm as the game spells it in a unit's name (no spaces or hyphens), so a display name
-- ("Area 52") and a unit's ("Area52") compare.
local function realmKey(r)
    r = str(r)
    return r and (r:gsub("[%s%-]", "")) or nil
end

-- The player's own realm, which a unit's name leaves out when it's the same.
local function myRealm()
    return realmKey(call(GetNormalizedRealmName)) or realmKey(call(GetRealmName))
end

-- A name and its realm: "Name-Realm" says it itself, else the realm given (nil: not known).
local function nameAndRealm(name, realm)
    local short, inlined = name:match("^([^%-]+)%-(.+)$")
    return short or name, realmKey(inlined) or realmKey(realm)
end

-- Is this character already in the player's party or raid? The name and, when the realm is
-- known, the realm too: another player of the same name on another realm isn't them.
function Data.InGroup(name, realm)
    name = str(name)
    if not name then return false end
    local short
    short, realm = nameAndRealm(name, realm)
    local mine = myRealm()
    local function same(unit)
        local n, r = call(UnitName, unit)
        n, r = str(n), str(r)
        if n ~= short then return false end
        if not realm then return true end
        local theirs = realmKey(r) or mine
        return theirs == nil or theirs == realm
    end
    if call(IsInRaid) == true then
        for i = 1, num(call(GetNumGroupMembers)) or 0 do
            if same("raid" .. i) then return true end
        end
    elseif call(IsInGroup) == true then
        for i = 1, 4 do
            if same("party" .. i) then return true end
        end
    end
    return false
end

-- Is this character already a friend: the character of a Battle.net friend, or an old
-- character friend. A name with no realm given is one of the player's own realm.
function Data.IsFriendName(name, realm)
    name = str(name)
    if not name then return false end
    local short
    short, realm = nameAndRealm(name, realm)
    local mine = myRealm()
    realm = realm or mine
    short = string.lower(short)
    for _, f in ipairs(Data.Friends()) do
        if f.char and string.lower(f.char) == short then
            local theirs = realmKey(f.realmName)
            if not (theirs and realm) or theirs == realm then return true end
        end
    end
    -- The old character friends are all of the player's realm.
    if realm ~= nil and mine ~= nil and realm ~= mine then return false end
    local FL = type(C_FriendList) == "table" and C_FriendList or nil
    return FL ~= nil and type(call(FL.GetFriendInfo, short)) == "table"
end

-- A recent ally who's online and isn't in the group yet.
function Data.CanInviteAlly(a)
    return a ~= nil and a.online == true and not Data.InGroup(a.name, a.realm)
end

-- A recent ally who isn't a friend yet (a legacy friend already is one).
function Data.CanFriendAlly(a)
    return a ~= nil and a.legacy ~= true and not Data.IsFriendName(a.name, a.realm)
end

function Data.Whisper(name) DUI.Lfg.Data.Whisper(name) end
function Data.Invite(name) DUI.Lfg.Data.Invite(name) end
function Data.Ignore(name)
    if type(C_FriendList) == "table" and type(name) == "string" then call(C_FriendList.AddIgnore, name) end
end

-- The raid

function Data.InRaid() return call(IsInRaid) == true end
function Data.Leads() return call(UnitIsGroupLeader, "player") == true end
function Data.CanMove() return Data.Leads() or call(UnitIsGroupAssistant, "player") == true end

-- Roster entries: { index, unit, name, rank (2 leader, 1 assistant), group, level,
-- class, token, zone, online, dead, role ("TANK", "HEALER", "DAMAGER" or nil), ready
-- ("ready", "notready", "waiting" or nil) }.
function Data.Roster()
    local out = {}
    if not Data.InRaid() then return out end
    local n = num(call(GetNumGroupMembers)) or 0
    for i = 1, math.min(n, Data.GROUPS * Data.GROUP_SIZE) do
        local name, rank, group, level, class, token, zone, online, dead, _, _, role = call(GetRaidRosterInfo, i)
        -- Nothing documents these as plain (legacy call), so a secret value is treated as
        -- online, alive, no role, and never compared.
        name = str(name)
        online, dead, role = plainBool(online), plainBool(dead), str(role)
        if name then
            local unit = "raid" .. i
            out[#out + 1] = { index = i, unit = unit, name = name, rank = num(rank) or 0, group = num(group) or 1,
                level = num(level), class = str(class), token = str(token), zone = str(zone), online = online ~= false,
                dead = dead == true, role = (role == "TANK" or role == "HEALER" or role == "DAMAGER") and role or nil,
                ready = str(call(GetReadyCheckStatus, unit)) }
        end
    end
    return out
end

-- Tank, healer and damage counts, as the game counts them.
function Data.Counts()
    local c = call(GetGroupMemberCountsForDisplay)
    if type(c) ~= "table" then return 0, 0, 0 end
    return num(c.TANK) or 0, num(c.HEALER) or 0, num(c.DAMAGER) or 0
end

-- Move a member to a group, or swap two (the game's drag, out of combat only; the page
-- is frozen in combat). False when it can't.
function Data.Move(member, group)
    if InCombatLockdown() or not (member and Data.CanMove()) or member.group == group then return false end
    call(SetRaidSubgroup, member.index, group)
    return true
end

function Data.Swap(a, b)
    if InCombatLockdown() or not (a and b and Data.CanMove()) or a.group == b.group then return false end
    call(SwapRaidSubgroup, a.index, b.index)
    return true
end

function Data.EveryoneAssists()
    local P = party()
    return P ~= nil and call(P.IsEveryoneAssistant) == true
end

function Data.SetEveryoneAssists(on)
    local P = party()
    if P and Data.Leads() then call(P.SetEveryoneIsAssistant, on == true) end
end

function Data.CanConvert()
    local P = party()
    return P ~= nil and call(P.AllowedToDoPartyConversion, true) == true
end

function Data.Convert()
    local P = party()
    if P and Data.CanConvert() then call(P.ConvertToRaid) end
end

-- Saved raids: { name, reset (seconds left), killed, bosses }, locked ones only.
function Data.Saved()
    local out = {}
    local n = num(call(GetNumSavedInstances)) or 0
    for i = 1, n do
        local name, _, reset, _, locked, _, _, isRaid, _, _, bosses, killed = call(GetSavedInstanceInfo, i)
        if str(name) and locked and isRaid ~= false then
            out[#out + 1] = { name = name, reset = num(reset), bosses = num(bosses), killed = num(killed) }
        end
    end
    return out
end

function Data.AskSaved() call(RequestRaidInfo) end
