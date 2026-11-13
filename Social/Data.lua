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

local function secret(v) return issecretvalue and issecretvalue(v) end
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

-- A duration in words: "20 min", "2 hours", "3 days", "2 weeks".
function Data.Span(seconds)
    if type(seconds) ~= "number" then return "" end
    if seconds < 3600 then return string.format(L["%d min"], math.max(1, math.floor(seconds / 60))) end
    if seconds < 86400 then
        local h = math.floor(seconds / 3600)
        return string.format(h == 1 and L["%d hour"] or L["%d hours"], h)
    end
    if seconds < 86400 * 14 then
        local d = math.floor(seconds / 86400)
        return string.format(d == 1 and L["%d day"] or L["%d days"], d)
    end
    return string.format(L["%d weeks"], math.floor(seconds / (86400 * 7)))
end

-- "3 days ago", "just now" (lastOnline, interactions).
function Data.Ago(seconds)
    if type(seconds) ~= "number" then return "" end
    if seconds < 60 then return L["just now"] end
    return string.format(L["%s ago"], Data.Span(seconds))
end

-- Short age for a row's right edge: "20 min", "3 h", "2 d".
function Data.Short(seconds)
    if type(seconds) ~= "number" then return "" end
    if seconds < 3600 then return string.format(L["%d min"], math.max(1, math.floor(seconds / 60))) end
    if seconds < 86400 then return string.format(L["%d h"], math.floor(seconds / 3600)) end
    return string.format(L["%d d"], math.floor(seconds / 86400))
end

-- Friends (Battle.net, including title friends)

-- The ruleset part of a realm name: "CAMWOW US1 Realm 8 PvP" gives "PvP". C_GameRules
-- only answers for the player, so the realm name is all there is for a friend. A name
-- with no ruleset word is returned whole.
local function rulesetWord(realm)
    if not realm then return nil end
    local s = string.lower(realm)
    if s:find("%f[%a]hardcore%f[%A]") then return L["Hardcore"] end
    if s:find("%f[%a]rp[%s%-]*p?vp%f[%A]") then return L["RP PvP"] end
    if s:find("%f[%a]pvp%f[%A]") then return L["PvP"] end
    if s:find("%f[%a]pve%f[%A]") then return L["PvE"] end
    if s:find("%f[%a]rp%f[%A]") then return L["RP"] end
end

function Data.Ruleset(realm) return rulesetWord(realm) or realm end

-- Is this realm on the player's ruleset? Only the realm name can tell, so a name with no
-- ruleset word (on either side) gets the benefit of the doubt: the invite option stays
-- and the game has the final say.
function Data.SameRuleset(realm)
    local mine = rulesetWord(str(GetRealmName and GetRealmName()))
    local theirs = rulesetWord(realm)
    return mine == nil or theirs == nil or mine == theirs
end

Data.FACTIONS = { Alliance = true, Horde = true }

-- One friend: { id, account, tag, favorite, status ("on", "away", "busy", "off"),
-- inGame (in this World of Warcraft), char, class, level, zone, race, faction
-- ("Alliance" or "Horde"), ruleset, game (another game's name), lastOnline (seconds
-- ago), note, broadcast, gameAccountID }.
local function friend(info)
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
    f.inGame = g.clientProgram == Data.CLIENT_WOW and (g.wowProjectID == nil or g.wowProjectID == WOW_PROJECT_ID)
    if f.inGame then
        f.char, f.class, f.level = str(g.characterName), str(g.classFilename), num(g.characterLevel)
        f.zone, f.race = str(g.areaName), str(g.raceName)
        f.faction = Data.FACTIONS[str(g.factionName) or ""] and g.factionName or nil
    end
    -- Like the game's own card: the display name, only within the player's region.
    if g.clientProgram == Data.CLIENT_WOW and g.isInCurrentRegion ~= false then
        f.realm = str(g.realmDisplayName) or str(g.realmName)
        f.ruleset = Data.Ruleset(f.realm)
    end
    if not f.char then f.game = str(g.richPresence) or (g.clientProgram == Data.CLIENT_WOW and L["World of Warcraft"]) or L["Battle.net"] end
    return f
end

-- One friend by Battle.net account id (from a whisper conversation).
function Data.Friend(id)
    local B = C_BattleNet
    if type(B) == "table" and type(id) == "number" and type(B.GetAccountInfoByID) == "function" then
        return friend(B.GetAccountInfoByID(id))
    end
end

-- Every friend in the client's order (online first).
function Data.Friends()
    local out = {}
    local B = bn()
    local n = call(BNGetNumFriends)
    if not (B and num(n)) then return out end
    for i = 1, n do
        local f = friend(call(B.GetFriendAccountInfo, i))
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

-- The player's own Battle.net status ("on", "away" or "busy") and broadcast.
function Data.Me()
    local _, tag, _, broadcast, afk, dnd = call(BNGetInfo)
    local status = dnd == true and "busy" or afk == true and "away" or "on"
    return status, str(broadcast), str(tag)
end

-- Only from a click (the calls are HasRestrictions). Available clears both.
function Data.SetStatus(status)
    local B = bn()
    if not B then return end
    call(B.SetAFK, status == "away")
    call(B.SetDND, status == "busy")
end

function Data.Broadcast(text)
    local B = bn()
    if B then call(B.SetCustomMessage, text or "") end
end

function Data.WhisperFriend(f)
    if not (f and f.account) then return end
    local C = type(ChatFrameUtil) == "table" and ChatFrameUtil
    if C and type(C.SendBNetTell) == "function" then C.SendBNetTell(f.account)
    elseif type(ChatFrame_SendBNetTell) == "function" then ChatFrame_SendBNetTell(f.account) end
end

-- Invite when they're in this game, on the same ruleset, and not already in the group
-- (like the game's party button).
function Data.CanInviteFriend(f)
    return f ~= nil and f.inGame == true and f.gameAccountID ~= nil and Data.SameRuleset(f.realm)
end

function Data.InviteFriend(f)
    local B = bn()
    if B and Data.CanInviteFriend(f) then call(B.InviteFriend, f.gameAccountID) end
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
Data.KIND_WORDS = { party = L["Grouped with you"], trade = L["Traded with you"], whisper = L["Whispered"], legacy = L["Legacy friend"] }

local function classToken(id)
    local info = id and type(C_ClassInfo) == "table" and call(C_ClassInfo.GetClassInfo, id)
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
        legacy = s.isConvertedLegacyFriend == true, note = str(i.note), location = str(s.currentLocation) }
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
