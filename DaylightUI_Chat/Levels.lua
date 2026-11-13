-- A player's level beside their name in chat ("[60] Name"), setting `levels`.
-- The game's chat line only carries a name, so levels are remembered from
-- wherever the game tells them: your group, guild, friends, /who answers and
-- anyone you target or mouse over. Someone never seen gets no level.
--
-- Names are kept as the chat link spells them: "Name" on your own realm,
-- "Name-Realm" from another. Only plain values are kept; a secret name or
-- level (enemies in a PvP match) is skipped.

local _, ns = ...
local DUI = DaylightUI

local Levels = {}
ns.Levels = Levels

Levels.known = {}

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

local myRealm
local function realm()
    if not myRealm then
        local r = call(GetNormalizedRealmName)
        if type(r) == "string" and r ~= "" and not secret(r) then myRealm = r end
    end
    return myRealm
end

-- The name as a chat link spells it: your own realm's left off.
function Levels.Key(name, server)
    if type(name) ~= "string" or secret(name) or name == "" then return nil end
    if type(server) == "string" and not secret(server) and server ~= "" then
        name = name .. "-" .. string.gsub(server, "%s", "")
    end
    local base, r = string.match(name, "^([^%-]+)%-(.+)$")
    if base and r == realm() then return base end
    return name
end

function Levels.Remember(name, level, server)
    if secret(level) or type(level) ~= "number" or level <= 0 then return end
    local key = Levels.Key(name, server)
    if key then Levels.known[key] = level end
end

function Levels.Of(name)
    local key = Levels.Key(name)
    return key and Levels.known[key]
end

function Levels.ReadUnit(unit)
    if call(UnitIsPlayer, unit) ~= true then return end
    local name, server = call(UnitFullName, unit)
    Levels.Remember(name, call(UnitLevel, unit), server)
end

function Levels.ReadGroup()
    if call(IsInRaid) == true then
        for i = 1, 40 do Levels.ReadUnit("raid" .. i) end
    else
        for i = 1, 4 do Levels.ReadUnit("party" .. i) end
    end
    Levels.ReadUnit("player")
end

function Levels.ReadGuild()
    if call(IsInGuild) ~= true then return end
    local n = call(GetNumGuildMembers)
    if type(n) ~= "number" then return end
    for i = 1, n do
        local ok, name, _, _, level = pcall(GetGuildRosterInfo, i)
        if ok then Levels.Remember(name, level) end
    end
end

function Levels.ReadFriends()
    local FL = C_FriendList
    if type(FL) ~= "table" then return end
    local n = call(FL.GetNumFriends)
    for i = 1, type(n) == "number" and n or 0 do
        local f = call(FL.GetFriendInfoByIndex, i)
        if type(f) == "table" and f.connected then Levels.Remember(f.name, f.level) end
    end
    local _, online = call(BNGetNumFriends)
    local BN = C_BattleNet
    if type(BN) ~= "table" or type(online) ~= "number" then return end
    for i = 1, online do
        local a = call(BN.GetFriendAccountInfo, i)
        local g = type(a) == "table" and a.gameAccountInfo
        if type(g) == "table" and g.isOnline and g.clientProgram == (BNET_CLIENT_WOW or "WoW") then
            Levels.Remember(g.characterName, g.characterLevel, g.realmName)
        end
    end
end

function Levels.ReadWho()
    local FL = C_FriendList
    if type(FL) ~= "table" then return end
    local n = call(FL.GetNumWhoResults)
    for i = 1, type(n) == "number" and n or 0 do
        local w = call(FL.GetWhoInfo, i)
        if type(w) == "table" then Levels.Remember(w.fullName, w.level) end
    end
end

Levels.EVENTS = {
    GROUP_ROSTER_UPDATE = Levels.ReadGroup,
    PLAYER_ENTERING_WORLD = Levels.ReadGroup,
    PLAYER_LEVEL_UP = function(level) Levels.Remember(call(UnitName, "player"), level) end,
    GUILD_ROSTER_UPDATE = Levels.ReadGuild,
    FRIENDLIST_UPDATE = Levels.ReadFriends,
    BN_FRIEND_INFO_CHANGED = Levels.ReadFriends,
    WHO_LIST_UPDATE = Levels.ReadWho,
    PLAYER_TARGET_CHANGED = function() Levels.ReadUnit("target") end,
    UPDATE_MOUSEOVER_UNIT = function() Levels.ReadUnit("mouseover") end,
    UNIT_LEVEL = function(unit) if type(unit) == "string" and not secret(unit) then Levels.ReadUnit(unit) end end,
}

-- Listens only while the setting is on.
function Levels.Apply(cfg)
    local on = cfg.levels == true
    Levels.on = on
    if not Levels.frame then
        Levels.frame = CreateFrame("Frame")
        Levels.frame:SetScript("OnEvent", function(_, event, ...)
            local fn = Levels.EVENTS[event]
            if fn then DUI.SafeCall(fn, ...) end
        end)
    end
    local f = Levels.frame
    for event in pairs(Levels.EVENTS) do
        if on then pcall(f.RegisterEvent, f, event) else f:UnregisterEvent(event) end
    end
    if on and not Levels.read then
        Levels.read = true
        Levels.ReadGroup()
        Levels.ReadGuild()
        Levels.ReadFriends()
    end
end

-- "[60] " before the line's first player link (the one who spoke), in the
-- time stamp's tan. Lines from someone never seen stay as they are.
local function mark(link, name)
    local level = Levels.Of(name)
    if not level then return nil end
    return (Levels.color or "") .. "[" .. level .. "]|r " .. link
end

function Levels.Mark(msg)
    if not Levels.on or type(msg) ~= "string" or secret(msg) then return msg end
    Levels.color = ns.Tags.stampColor
    return (string.gsub(msg, "(|Hplayer:([^:|]+)[^|]*|h)", mark, 1))
end
