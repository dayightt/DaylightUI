-- Classifies chat lines by kind (guild, trade, loot...) so each tab of the
-- Daylight chat box (Box.lua) can filter them.
--
-- Each line comes with the game's chat type id (ChatTypeInfo[type].id). Player
-- messages also carry the event (CHAT_MSG_GUILD...) and its arguments, see the
-- game's AddMessage(text, r, g, b, id, accessID, typeID, event, eventArgs) in
-- ChatFrameOverrides.lua. The game's own messages (loot, system, skill-ups) only
-- have the id. Secret values are never matched; such a line counts as "system"
-- unless its plain id or event says otherwise.

local _, ns = ...
local L = DaylightUI.L

local Kinds = {}
ns.Kinds = Kinds

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- Chat type (event name minus "CHAT_MSG_") -> kind.
Kinds.BY_TYPE = {
    SAY = "say", YELL = "yell", EMOTE = "emote", TEXT_EMOTE = "emote",
    GUILD = "guild", GUILD_ACHIEVEMENT = "guild", GUILD_ITEM_LOOTED = "guild", OFFICER = "officer",
    PARTY = "party", PARTY_LEADER = "party", RAID = "raid", RAID_LEADER = "raid", RAID_WARNING = "warning",
    INSTANCE_CHAT = "instance", INSTANCE_CHAT_LEADER = "instance",
    WHISPER = "whisper", WHISPER_INFORM = "whisper", BN_WHISPER = "bnet", BN_WHISPER_INFORM = "bnet",
    AFK = "whisper", DND = "whisper", BN_WHISPER_PLAYER_OFFLINE = "bnet",
    LOOT = "loot", OPENING = "opening", TRADESKILLS = "tradeskill", MONEY = "money", CURRENCY = "currency",
    COMBAT_XP_GAIN = "progress", COMBAT_HONOR_GAIN = "progress", COMBAT_FACTION_CHANGE = "reputation",
    SKILL = "skill", ACHIEVEMENT = "achievement",
    MONSTER_SAY = "npc", MONSTER_YELL = "npc", MONSTER_EMOTE = "npc", MONSTER_WHISPER = "npc",
    MONSTER_PARTY = "npc", RAID_BOSS_EMOTE = "boss", RAID_BOSS_WHISPER = "boss",
    PET_INFO = "pet", COMBAT_MISC_INFO = "misc", TARGETICONS = "icons", BN_INLINE_TOAST_ALERT = "bnalert",
    BG_SYSTEM_HORDE = "pvp", BG_SYSTEM_ALLIANCE = "pvp", BG_SYSTEM_NEUTRAL = "pvp",
}

-- The other two trade channels, shown as "Trade (Services) - English" and
-- "Trade (Local) - Ironforge". Each keeps its own per-channel kind (OfChannel) so
-- existing switches and short tags keep working; these names just let the tabs
-- and tags recognize them.
Kinds.SERVICES = "ch:trade (services)"
Kinds.TRADE_LOCAL = "ch:trade (local)"

-- Channel base name (lower case, without " - Zone") -> kind. The channel list
-- calls the other two trade channels "Services" and "TradeLocal", while their
-- lines say "Trade (Services)" and "Trade (Local)".
Kinds.CHANNELS = {
    general = "general", trade = "trade", localdefense = "defense", ["local defense"] = "defense",
    lookingforgroup = "lfg", ["looking for group"] = "lfg", services = Kinds.SERVICES, newcomerchat = "general",
    worlddefense = "defense", tradelocal = Kinds.TRADE_LOCAL,
    -- Spanish clients name the channels in Spanish.
    comercio = "trade", defensalocal = "defense", ["defensa local"] = "defense", buscargrupo = "lfg",
    ["buscar grupo"] = "lfg", defensamundial = "defense", ["defensa mundial"] = "defense",
    defensaglobal = "defense", ["defensa global"] = "defense", servicios = Kinds.SERVICES, novatos = "general",
    ["comercio (servicios)"] = Kinds.SERVICES, ["comercio (local)"] = Kinds.TRADE_LOCAL,
}

-- Kinds that were misnamed: old -> correct. A switch or tag saved on the old
-- name moves to the correct one.
Kinds.RENAMED = { ["ch:tradelocal"] = Kinds.TRADE_LOCAL }

-- Every kind, in tab editor order.
Kinds.ORDER = { "say", "yell", "emote", "whisper", "bnet", "bnalert", "party", "instance", "raid", "warning",
                "icons", "pvp", "guild", "officer", "general", "trade", "lfg", "defense", "channel", "loot",
                "currency", "money", "tradeskill", "opening", "progress", "reputation", "skill", "achievement",
                "pet", "misc", "npc", "boss", "system" }

-- Kinds that used to be one. Keyed by the tab version that split them:
-- old kind -> its new kinds. Applied by Kinds.Upgrade once per tab.
Kinds.SPLIT = {
    [2] = { say = { "yell", "emote" }, party = { "instance" }, raid = { "warning" }, loot = { "money" },
            progress = { "reputation", "skill", "achievement" }, npc = { "boss" } },
    [3] = { whisper = { "bnet" } },
    [4] = { trade = { Kinds.SERVICES, Kinds.TRADE_LOCAL } },
    [5] = {}, -- not a split, see Kinds.RENAMED
    -- The rest of the game's chat settings, one switch each.
    [6] = { loot = { "tradeskill", "opening" }, money = { "currency" },
            system = { "pvp", "pet", "misc", "icons", "bnalert" } },
}
Kinds.VERSION = 6

-- Upgrades a saved tab: each old kind turns on its new kinds, only for splits
-- not yet applied, so anything switched off since stays off. A channel's own
-- switch predates its split, so if it was saved off it stays off.
function Kinds.Upgrade(tab)
    if type(tab) ~= "table" or (tab.v or 1) >= Kinds.VERSION then return end
    if type(tab.kinds) == "table" then
        for v = (tab.v or 1) + 1, Kinds.VERSION do
            for old, more in pairs(Kinds.SPLIT[v]) do
                if tab.kinds[old] then
                    for _, k in ipairs(more) do
                        if tab.kinds[k] == nil then tab.kinds[k] = true end
                    end
                end
            end
        end
        for old, real in pairs(Kinds.RENAMED) do
            if tab.kinds[old] == false then tab.kinds[real] = false end
            tab.kinds[old] = nil
        end
    end
    tab.v = Kinds.VERSION
end

-- The game's own lines (loot, money, XP...) reach AddMessage without an event,
-- and their type id doesn't identify them in game (all read "system"). A message
-- filter runs just before AddMessage on the same window, so it records which
-- event the next line came from. It only reads; the line is untouched.
Kinds.QUIET_EVENTS = { "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_CURRENCY", "CHAT_MSG_SKILL",
    "CHAT_MSG_OPENING", "CHAT_MSG_TRADESKILLS", "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_COMBAT_HONOR_GAIN",
    "CHAT_MSG_COMBAT_FACTION_CHANGE", "CHAT_MSG_ACHIEVEMENT", "CHAT_MSG_GUILD_ACHIEVEMENT",
    "CHAT_MSG_PET_INFO", "CHAT_MSG_COMBAT_MISC_INFO", "CHAT_MSG_TARGETICONS", "CHAT_MSG_BN_INLINE_TOAST_ALERT",
    "CHAT_MSG_BG_SYSTEM_HORDE", "CHAT_MSG_BG_SYSTEM_ALLIANCE", "CHAT_MSG_BG_SYSTEM_NEUTRAL" }

local heardFrom, heardEvent, heardAt

function Kinds.Filter(cf, event)
    heardFrom, heardEvent, heardAt = cf, event, GetTime()
    return false
end

-- The event of the line this window just received, consumed once.
function Kinds.Heard(cf)
    if heardFrom ~= cf or heardAt ~= GetTime() then return nil end
    heardFrom = nil
    return heardEvent
end

local listening = false
function Kinds.Listen()
    if listening then return end
    local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if type(add) ~= "function" then return end
    listening = true
    for _, e in ipairs(Kinds.QUIET_EVENTS) do add(e, Kinds.Filter) end
end

-- The game's chat type id -> type, from ChatTypeInfo (re-read for unknown ids).
local byId = {}
function Kinds.TypeOfId(id)
    if type(id) ~= "number" or secret(id) then return nil end
    if not byId[id] and type(ChatTypeInfo) == "table" then
        for t, info in pairs(ChatTypeInfo) do
            if type(info) == "table" and type(info.id) == "number" then byId[info.id] = t end
        end
    end
    return byId[id]
end

-- A channel's kind from its name. World channels share a kind; any other channel
-- gets its own ("ch:name") so a tab can pick it alone.
function Kinds.OfChannel(base)
    -- Strip " - Zone" and the number the game appends to some world channel names
    -- ("LookingForGroup 84").
    local name = string.lower(string.gsub(string.gsub(base, "%s*%-.*$", ""), "%s+%d+$", ""))
    return Kinds.CHANNELS[name] or ("ch:" .. name)
end

-- A custom channel's kind (not in Kinds.ORDER)?
function Kinds.Own(kind) return type(kind) == "string" and string.sub(kind, 1, 3) == "ch:" end

-- The kind for a channel number, cached until channels change (CHANNEL_UI_UPDATE).
local listKind
local function kindOfNumber(num)
    if type(num) ~= "number" or secret(num) then return nil end
    if not listKind then
        listKind = {}
        for _, c in ipairs(Kinds.Joined()) do listKind[c.id] = c.kind end
    end
    return listKind[num]
end
function Kinds.ChannelsChanged() listKind = nil end
DaylightUI.RegisterEvent("CHANNEL_UI_UPDATE", Kinds.ChannelsChanged)

-- A channel line's kind from the event's 9th argument, the channel base name, or
-- "channel" if unreadable. A community uses one name in the channel list
-- ("Community:123:1", which its switch uses) and another on its lines, so custom
-- channels are matched by number (8th argument).
local function channelKind(args)
    local base = type(args) == "table" and args[9]
    if type(base) ~= "string" or secret(base) or base == "" then return "channel" end
    local kind = Kinds.OfChannel(base)
    if Kinds.Own(kind) then return kindOfNumber(args[8]) or kind end
    return kind
end

-- Joined channels in the game's order (same list as ChatConfigFrame.lua):
-- { id, name, kind }, one per kind.
local function joined(...)
    local out, seen = {}, {}
    for i = 1, select("#", ...), 3 do
        local id, name = select(i, ...)
        if type(id) == "number" and not secret(id) and type(name) == "string" and not secret(name) then
            local kind = Kinds.OfChannel(name)
            if not seen[kind] then
                seen[kind] = true
                local util = ChatFrameUtil
                local shown = type(util) == "table" and type(util.ResolveChannelName) == "function"
                    and util.ResolveChannelName(name) or name
                out[#out + 1] = { id = id, name = shown, kind = kind }
            end
        end
    end
    return out
end

function Kinds.Joined()
    if type(GetChannelList) ~= "function" then return {} end
    return joined(GetChannelList())
end

-- An addon that joins its own channels at login, before the game has joined
-- General and Trade, takes their numbers, and /1 then talks in that addon's
-- channel. The world channels are put back in front, in their own order, with the
-- same swap the game's Channels settings make when you drag one.
local function isWorld(name)
    local C = C_ChatInfo
    if type(C) == "table" and type(C.GetChannelInfoFromIdentifier) == "function" then
        local info = C.GetChannelInfoFromIdentifier(name)
        local zone = type(info) == "table" and info.zoneChannelID
        if type(zone) == "number" and not secret(zone) then return zone ~= 0 end
    end
    local base = string.lower(string.gsub(string.gsub(name, "%s*%-.*$", ""), "%s+%d+$", ""))
    return Kinds.CHANNELS[base] ~= nil
end

-- Moves left this session: enough for a login's joins one by one, but it stops if
-- something keeps moving them back.
Kinds.WORLD_MOVES = 30
local moves, pending = 0, nil

local function swapColors(a, b)
    local Chat = ns.Chat
    if not Chat then return end
    local ca, cb = Chat.ColorOf("CHANNEL" .. a), Chat.ColorOf("CHANNEL" .. b)
    if ca[1] == cb[1] and ca[2] == cb[2] and ca[3] == cb[3] then return end
    Chat.SetColor("CHANNEL" .. a, cb)
    Chat.SetColor("CHANNEL" .. b, ca)
end

function Kinds.WorldFirst()
    pending = nil
    if DaylightUI:Get("Chat", "worldChannelsFirst") == false or moves >= Kinds.WORLD_MOVES then return end
    local C = C_ChatInfo
    if type(GetChannelList) ~= "function" or type(C) ~= "table"
        or type(C.SwapChatChannelsByChannelIndex) ~= "function" then return end
    if InCombatLockdown() then return DaylightUI.AfterCombat(Kinds.WorldFirst, "chatWorldFirst") end
    if DaylightUI.Restricted() then return DaylightUI.AfterRestrictions(Kinds.WorldFirst, "chatWorldFirst") end
    local ids, world, other, at, here = {}, {}, {}, {}, {}
    local list = { GetChannelList() }
    for i = 1, #list, 3 do
        local id, name = list[i], list[i + 1]
        if type(id) ~= "number" or secret(id) or type(name) ~= "string" or secret(name) then return end
        ids[#ids + 1] = id
        local into = isWorld(name) and world or other
        into[#into + 1] = name
        at[name], here[id] = id, name
    end
    table.sort(ids)
    local want = world
    for _, name in ipairs(other) do want[#want + 1] = name end
    for k, id in ipairs(ids) do
        local name, from = want[k], at[want[k]]
        if from ~= id then
            local there = here[id]
            C.SwapChatChannelsByChannelIndex(from, id)
            swapColors(from, id)
            moves = moves + 1
            here[id], here[from], at[name], at[there] = name, there, id, from
        end
    end
end

-- The list changes several times while logging in: look once it settles.
DaylightUI.RegisterEvent("CHANNEL_UI_UPDATE", function()
    if pending and GetTime() - pending < 2 then return end
    pending = GetTime()
    C_Timer.After(1, Kinds.WorldFirst)
end)

-- The line's chat type ("GUILD", "CHANNEL"...) and kind.
function Kinds.Of(id, event, args)
    local t
    if type(event) == "string" and not secret(event) then t = string.match(event, "^CHAT_MSG_(.+)$") end
    t = t or Kinds.TypeOfId(id)
    if not t then return nil, "system" end
    -- Other people's community lines arrive by their own event, as a channel line
    -- with the same number and name (ChatFrameOverrides.lua).
    if t == "CHANNEL" or t == "COMMUNITIES_CHANNEL" or string.find(t, "^CHANNEL%d") then return t, channelKind(args) end
    return t, Kinds.BY_TYPE[t] or "system"
end

-- Default tabs for a new chat box: everything, guild, trade and loot (named with
-- the game's own strings).
function Kinds.DefaultTabs()
    local tabs = {
        { name = _G.GENERAL or L["General"], all = true },
        { name = _G.GUILD or L["Guild"], kinds = { guild = true, officer = true } },
        { name = _G.TRADE or L["Trade"], kinds = { trade = true, [Kinds.SERVICES] = true, [Kinds.TRADE_LOCAL] = true } },
        { name = _G.LOOT or L["Loot"], kinds = { loot = true, money = true, currency = true, tradeskill = true,
            opening = true, progress = true,
            reputation = true, skill = true, achievement = true } },
    }
    for _, tab in ipairs(tabs) do tab.v = Kinds.VERSION end
    return tabs
end

-- Does this tab show this kind? A custom channel without its own switch follows
-- "Other channels".
function Kinds.Shows(tab, kind)
    if type(tab) ~= "table" then return false end
    if tab.all then return true end
    if type(tab.kinds) ~= "table" then return false end
    local on = tab.kinds[kind]
    if on == nil and Kinds.Own(kind) then on = tab.kinds.channel end
    return on == true
end
