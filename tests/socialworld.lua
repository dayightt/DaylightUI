-- The fake game's social window for the social window's tests, as Forever has it:
--   * O calls ToggleFriendsFrame() (Camelot FriendsFrame.lua), which calls
--     SocialUIControl.Toggle(), which is ToggleUIPanel(SocialUIFrame) while
--     C_SocialUI.IsSystemEnabled(). ToggleRaidFrame() and ToggleFriendsFrame(tab)
--     open it on a tab (SocialUIControl.ToggleToTab). When shown it selects the
--     tab, or closes when that tab already shows or isn't available. When hidden
--     it calls SetDeferredOpenTab, then toggles. Its OnShow (Reset) builds the
--     available tabs and consumes the deferred tab. Parked under a hidden frame
--     that never runs, so the tab waits (ConsumeDeferredOpenTab hands it over).
--   * Battle.net friends: BNGetNumFriends, C_BattleNet.GetFriendAccountInfo(i)
--     (BNetAccountInfo, with gameAccountInfo inside), invites. SetAFK/SetDND and
--     SetCustomMessage are flagged HasRestrictions (a click or a key: stub.HardwareOnly).
--   * Recent allies: C_RecentAllies (GetRecentAllies presorted by the client:
--     pinned, online, most recent). Pins fire RECENT_ALLY_DATA_UPDATED.
--   * The raid: GetRaidRosterInfo's full answer, SetRaidSubgroup / SwapRaidSubgroup
--     (leader or assistant only; a full group refuses), GROUP_ROSTER_UPDATE a frame
--     later, GetGroupMemberCountsForDisplay, and saved raids.
--
-- SW.world(spec) is stub.Load's "before". A test then plays SW.Toggle(tab),
-- SW.Close(), SW.Login(index), SW.Invite(name), SW.Raid(list, lead), and reads
-- SW.Calls(kind).

local stub = require("stub")

local SW = {}

local function S() return SW.state end
local function record(kind, ...) table.insert(S().calls, { kind = kind, args = { ... } }) end
function SW.Calls(kind)
    local out = {}
    for _, c in ipairs(S().calls) do if c.kind == kind then out[#out + 1] = c.args end end
    return out
end

local function asGame(fn, ...)
    stub.inSecure = (stub.inSecure or 0) + 1
    local ok, err = pcall(fn, ...)
    stub.inSecure = stub.inSecure - 1
    if not ok then error(err, 2) end
end
SW.AsGame = asGame

SW.TAB = { Friends = 1, FriendRequests = 2, QuickJoin = 3, RaidList = 4, RecruitAFriend = 5, RecentAllies = 6 }
SW.ORDER = { 1, 6, 2, 4 }   -- the tabs this client has (tabOrder: Friends, RecentAllies, QuickJoin, FriendRequests, RAF, RaidList; QuickJoin and RAF off)

-- Friends: two favorites (one offline), two online, one in another game, and two
-- offline. lastOnlineTime is a wall clock time (time()).
function SW.Friends()
    local now = time()
    local function wow(char, class, level, zone, extra)
        local g = { gameAccountID = 100 + #char, clientProgram = "WoW", isOnline = true, wowProjectID = WOW_PROJECT_ID,
            characterName = char, classFilename = class, characterLevel = level, areaName = zone, raceName = "Dwarf",
            isGameAFK = false, isGameBusy = false }
        for k, v in pairs(extra or {}) do g[k] = v end
        return g
    end
    return {
        { bnetAccountID = 1, accountName = "Mara", battleTag = "Mara#1111", isFavorite = true, note = "Heals on Tuesdays",
          customMessage = "Running ZF later", gameAccountInfo = wow("Ysella Dawnwhisper", "PRIEST", 44, "Tanaris") },
        { bnetAccountID = 2, accountName = "Jonno", battleTag = "Jonno#2222", isFavorite = true, isAFK = true,
          gameAccountInfo = wow("Brannoc Ironvein", "WARRIOR", 42, "Stranglethorn Vale") },
        { bnetAccountID = 3, accountName = "Kit", battleTag = "Kit#3333", gameAccountInfo = wow("Thessaly Moor", "MAGE", 39, "Arathi Highlands") },
        { bnetAccountID = 4, accountName = "Riven", battleTag = "Riven#4444", isDND = true, gameAccountInfo = wow("Dorrik Ashgrove", "HUNTER", 51, "Un'Goro Crater") },
        { bnetAccountID = 5, accountName = "Sol", battleTag = "Sol#5555", gameAccountInfo = { gameAccountID = 105, clientProgram = "Fen", isOnline = true, richPresence = "Diablo IV" } },
        { bnetAccountID = 6, accountName = "Pip", battleTag = "Pip#6666", lastOnlineTime = now - 7200, gameAccountInfo = { isOnline = false, clientProgram = "" } },
        { bnetAccountID = 7, accountName = "Ambrose", battleTag = "Ambrose#7777", isFavorite = true, lastOnlineTime = now - 3 * 86400, gameAccountInfo = { isOnline = false, clientProgram = "" } },
    }
end

function SW.Allies()
    local now = time()
    local function ally(guid, name, classID, level, online, kind, ago, extra)
        local a = { characterData = { guid = guid, name = name, fullName = name, realmName = "", level = level, classID = classID, raceID = 3, sex = 2 },
            stateData = { isOnline = online, isAFK = false, isDND = false, isConvertedLegacyFriend = false, friendRequestSentThisSession = false },
            interactionData = { interactions = { { type = kind, description = "", timestamp = now - ago } } } }
        for k, v in pairs(extra or {}) do a.stateData[k] = v end
        return a
    end
    return {
        ally("Player-1", "Halvar Stonefist", 1, 41, true, 1, 1200, { pinExpirationDate = now + 86400 * 30 }),
        ally("Player-6", "Sabine Kett", 5, 37, true, 23, 86400 * 9, { isConvertedLegacyFriend = true }),
        ally("Player-2", "Lirien Vale", 11, 40, true, 1, 1200),
        ally("Player-3", "Odessa Reed", 7, 43, true, 3, 3600),
        ally("Player-4", "Fenwick Harrow", 9, 38, false, 4, 3 * 3600),
        ally("Player-5", "Garrett Lowe", 8, 42, false, 1, 86400),
    }
end

-- A 12-person raid: name, class token, level, group, role, rank (2 leader, 1 assist).
function SW.Roster()
    return {
        { "Sunwalker Dawn", "SHAMAN", 60, 1, "HEALER", 2 },   -- you
        { "Brannoc Ironvein", "WARRIOR", 60, 1, "TANK", 0 },
        { "Ysella Dawnwhisper", "PRIEST", 60, 1, "HEALER", 1 },
        { "Thessaly Moor", "MAGE", 60, 1, "DAMAGER", 0 },
        { "Dorrik Ashgrove", "HUNTER", 60, 1, "DAMAGER", 0 },
        { "Lirien Vale", "DRUID", 60, 2, "HEALER", 0 },
        { "Odessa Reed", "SHAMAN", 60, 2, "DAMAGER", 0 },
        { "Fenwick Harrow", "WARLOCK", 58, 2, "DAMAGER", 0, { dead = true } },
        { "Wren Haddock", "ROGUE", 60, 2, "DAMAGER", 0, { offline = true } },
        { "Corvin Hale", "PALADIN", 60, 2, "HEALER", 0 },
        { "Garrett Lowe", "MAGE", 60, 3, "DAMAGER", 0 },
        { "Halvar Stonefist", "WARRIOR", 60, 3, "TANK", 0 },
    }
end

local CLASS_WORD = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
    SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
local CLASS_ID = { [1] = "WARRIOR", [2] = "PALADIN", [3] = "HUNTER", [4] = "ROGUE", [5] = "PRIEST", [7] = "SHAMAN", [8] = "MAGE", [9] = "WARLOCK", [11] = "DRUID" }

local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end

-- ---------------------------------------------------------------------
-- SocialUIFrame and its toggles (SocialUI.lua, SocialUIControl.lua)
-- ---------------------------------------------------------------------

local function frame()
    if _G.SocialUIFrame then return _G.SocialUIFrame end
    local f = CreateFrame("Frame", "SocialUIFrame", UIParent)
    f:Hide()
    f:SetSize(410, 675)
    f.availableTabData = {}
    function f:SetDeferredOpenTab(tab) self.deferredOpenTabType = tab end
    function f:ConsumeDeferredOpenTab()
        local t = self.deferredOpenTabType
        self.deferredOpenTabType = nil
        return t
    end
    function f:GetDataForAvailableTab(tab)
        for _, d in ipairs(self.availableTabData) do if d.tabType == tab then return d end end
        return nil
    end
    function f:GetSelectedTab() return self.selectedTab end
    function f:SelectTab(tab)
        if tab ~= nil and not self:GetDataForAvailableTab(tab) then return end
        self.selectedTab = tab
        if tab then self.lastSelectedTabType = tab end
    end
    -- OnShow runs Reset: the tabs, then the deferred tab or the last one, else the first.
    f:SetScript("OnShow", function(self)
        record("GameOnShow")
        self.availableTabData = {}
        for _, t in ipairs(SW.ORDER) do self.availableTabData[#self.availableTabData + 1] = { tabType = t } end
        local want = self:ConsumeDeferredOpenTab()
        if not (want and self:GetDataForAvailableTab(want)) then want = self.lastSelectedTabType or SW.ORDER[1] end
        self:SelectTab(want)
    end)
    f:SetScript("OnHide", function(self)
        self.availableTabData = {}
        self.selectedTab = nil
    end)
    return f
end
SW.Frame = frame

local function toggleToTab(tab)
    local f = frame()
    local already = f:GetSelectedTab() == tab
    if f:IsShown() and (already or not f:GetDataForAvailableTab(tab)) then
        ToggleUIPanel(f)
    elseif f:IsShown() then
        f:SelectTab(tab)
    else
        f:SetDeferredOpenTab(tab)
        ToggleUIPanel(f)
    end
end

-- The O key (no tab), ToggleFriendsFrame(tab) and ToggleRaidFrame, as the game's code does them.
function SW.Toggle(tab)
    asGame(function()
        if not C_SocialUI.IsSystemEnabled() then return end
        if tab then toggleToTab(tab) else ToggleUIPanel(frame()) end
    end)
end

function SW.Close() asGame(function() HideUIPanel(frame()) end) end

-- ---------------------------------------------------------------------
-- The world's changes, as a test plays them
-- ---------------------------------------------------------------------

-- Friend i logs in (into Ironforge) or out.
function SW.Login(i, on)
    local f = S().friends[i]
    if on == false then
        f.gameAccountInfo = { isOnline = false, clientProgram = "" }
        f.lastOnlineTime = time()
    else
        f.gameAccountInfo = { gameAccountID = 300 + i, clientProgram = "WoW", isOnline = true, wowProjectID = WOW_PROJECT_ID,
            characterName = "Wren Haddock", classFilename = "ROGUE", characterLevel = 33, areaName = "Ironforge", raceName = "Gnome" }
        f.lastOnlineTime = nil
    end
    stub.FireEvent("BN_FRIEND_INFO_CHANGED", i)
end

-- A friend request arrives.
function SW.Invite(name)
    local id = 900 + #S().invites
    table.insert(S().invites, 1, { inviteID = id, accountName = name, creationTimestamp = time() })
    stub.FireEvent("BN_FRIEND_INVITE_ADDED", id)
    return id
end

-- In a raid (SW.Roster() or your own list) that you lead (default), assist ("assist"), or neither (false).
function SW.Raid(list, lead)
    S().roster = list or SW.Roster()
    if lead == "assist" then S().roster[1][6] = 1
    elseif lead == false then S().roster[1][6] = 0; S().roster[2][6] = 2 end
    stub.FireEvent("GROUP_ROSTER_UPDATE")
end

function SW.LeaveRaid()
    S().roster = nil
    stub.FireEvent("GROUP_ROSTER_UPDATE")
end

-- ---------------------------------------------------------------------
-- The game's functions
-- ---------------------------------------------------------------------

local original = {}
local function keep(t, name)
    local key = tostring(t) .. name
    if original[key] == nil then original[key] = t[name] or false end
    return original[key] or nil
end

local function me() local r = S().roster; return r and r[1] end
local function canMove() local m = me(); return m ~= nil and m[6] >= 1 end

local function later(event, ...)
    local args = { ... }
    C_Timer.After(0, function() stub.FireEvent(event, unpack(args)) end)
end

local function install()
    _G.ShowUIPanel = function(f) record("ShowUIPanel", f:GetName()); f:Show() end
    -- UIParentPanelManager's rule: from addon code in combat it does nothing.
    _G.HideUIPanel = function(f)
        record("HideUIPanel", f:GetName())
        if stub.combat and (stub.inSecure or 0) == 0 then return end
        f:Hide()
    end
    _G.ToggleUIPanel = function(f) if f:IsShown() then HideUIPanel(f) else ShowUIPanel(f) end end
    _G.SocialUITabType = SW.TAB
    _G.C_SocialUI = { IsSystemEnabled = function() return S().enabled ~= false end }
    _G.SocialUIControl = {
        IsEnabled = function() return C_SocialUI.IsSystemEnabled() and _G.SocialUIFrame ~= nil end,
        Toggle = function() ToggleUIPanel(frame()) end,
        ToggleToTab = toggleToTab,
        Hide = function() HideUIPanel(frame()) end,
    }
    _G.ToggleFriendsFrame = function(tab) SW.Toggle(tab) end
    _G.ToggleRaidFrame = function() SW.Toggle(SW.TAB.RaidList) end
    _G.WOW_PROJECT_ID = _G.WOW_PROJECT_ID or 18

    -- Battle.net
    _G.BNConnected = function() return true end
    _G.BNFeaturesEnabledAndConnected = function() return true end
    _G.BNGetInfo = function()
        local s = S()
        return 1, "Curt#1674", nil, s.broadcast or "", s.afk == true, s.dnd == true, false
    end
    _G.BNGetNumFriends = function()
        local on = 0
        for _, f in ipairs(S().friends) do if f.gameAccountInfo and f.gameAccountInfo.isOnline then on = on + 1 end end
        return #S().friends, on
    end
    _G.BNGetNumFriendInvites = function() return #S().invites end
    local function byID(id) for i, f in ipairs(S().friends) do if f.bnetAccountID == id then return f, i end end end
    _G.BNSetFriendNote = function(id, note) record("BNSetFriendNote", id, note); local f = byID(id); if f then f.note = note end; later("BN_FRIEND_INFO_CHANGED") end
    _G.BNSetFriendFavoriteFlag = function(id, on) record("BNSetFriendFavoriteFlag", id, on); local f = byID(id); if f then f.isFavorite = on end; later("BN_FRIEND_INFO_CHANGED") end
    _G.BNRemoveFriend = function(id)
        record("BNRemoveFriend", id)
        local _, i = byID(id)
        if i then table.remove(S().friends, i) end
        later("BN_FRIEND_LIST_SIZE_CHANGED")
    end
    _G.BNSendFriendInvite = function(text, note) record("BNSendFriendInvite", text, note) end
    local function inviteIndex(id) for i, v in ipairs(S().invites) do if v.inviteID == id then return i end end end
    _G.BNAcceptFriendInvite = function(id)
        record("BNAcceptFriendInvite", id)
        local i = inviteIndex(id)
        if not i then return end
        local inv = table.remove(S().invites, i)
        later("BN_FRIEND_INVITE_REMOVED")
        table.insert(S().friends, { bnetAccountID = 50 + id, accountName = (inv.accountName:gsub("#.*", "")), battleTag = inv.accountName,
            gameAccountInfo = { isOnline = false, clientProgram = "" }, lastOnlineTime = time() })
        later("BN_FRIEND_LIST_SIZE_CHANGED")
    end
    _G.BNDeclineFriendInvite = function(id)
        record("BNDeclineFriendInvite", id)
        local i = inviteIndex(id)
        if i then table.remove(S().invites, i) end
        later("BN_FRIEND_INVITE_REMOVED")
    end
    local bn = keep(_G, "C_BattleNet")
    _G.C_BattleNet = setmetatable({
        GetFriendAccountInfo = function(i) return copy(S().friends[i]) end,
        GetFriendInviteInfo = function(i) return copy(S().invites[i]) end,
        InviteFriend = function(gameAccountID) record("InviteFriend", gameAccountID) end,
        SetAFK = function(on)
            if not stub.HardwareOnly("C_BattleNet.SetAFK") then return end
            record("SetAFK", on); S().afk = on; later("BN_INFO_CHANGED")
        end,
        SetDND = function(on)
            if not stub.HardwareOnly("C_BattleNet.SetDND") then return end
            record("SetDND", on); S().dnd = on; later("BN_INFO_CHANGED")
        end,
        SetCustomMessage = function(text)
            if not stub.HardwareOnly("C_BattleNet.SetCustomMessage") then return end
            record("SetCustomMessage", text); S().broadcast = text; later("BN_CUSTOM_MESSAGE_CHANGED")
        end,
        SetBlocked = function(id, on) record("SetBlocked", id, on) end,
        AreTitleFriendsEnabled = function() return true end,
        SendTitleFriendInviteByName = function(name)
            if not stub.HardwareOnly("C_BattleNet.SendTitleFriendInviteByName") then return end
            record("SendTitleFriendInviteByName", name)
        end,
        IsBattleNetFriendsListEnabled = function() return true end,
    }, { __index = bn or nil })
    local chat = keep(_G, "ChatFrameUtil")
    _G.ChatFrameUtil = setmetatable({
        SendTell = function(name) record("SendTell", name) end,
        SendBNetTell = function(name) record("SendBNetTell", name) end,
    }, { __index = chat or nil })

    -- Ignores (C_FriendList), keeping the rest of it (the who list).
    local fl = keep(_G, "C_FriendList")
    _G.C_FriendList = setmetatable({
        GetNumIgnores = function() return #S().ignores end,
        GetIgnoreName = function(i) return S().ignores[i] end,
        DelIgnore = function(name)
            record("DelIgnore", name)
            for i, n in ipairs(S().ignores) do if n == name then table.remove(S().ignores, i); break end end
            later("IGNORELIST_UPDATE")
            return true
        end,
        AddIgnore = function(name) record("AddIgnore", name); table.insert(S().ignores, name); later("IGNORELIST_UPDATE"); return true end,
        IsLegacyFriendSystemEnabled = function() return false end,
    }, { __index = fl or nil })

    -- Recent allies
    local function ally(guid) for _, a in ipairs(S().allies) do if a.characterData.guid == guid then return a end end end
    _G.C_RecentAllies = {
        IsSystemEnabled = function() return true end,
        IsRecentAllyDataReady = function() return S().alliesReady ~= false end,
        TryRequestRecentAlliesData = function()
            -- refused to addon code even from a click (the tab click gave "the game
            -- blocked UNKNOWN()" in game). The game's own list asks from its OnShow,
            -- untainted.
            if (stub.inSecure or 0) == 0 then
                stub.errors[#stub.errors + 1] = "ADDON_ACTION_BLOCKED: C_RecentAllies.TryRequestRecentAlliesData"
                return
            end
            record("TryRequestRecentAlliesData")
            if S().alliesReady == false then S().alliesReady = true; later("RECENT_ALLIES_CACHE_UPDATE") end
        end,
        GetRecentAllies = function()
            if S().alliesReady == false then return {} end
            local list = copy(S().allies)
            -- the client's order: pinned (and legacy friends), online, most recent
            local function rank(a) return (a.stateData.pinExpirationDate or a.stateData.isConvertedLegacyFriend) and 0 or 1 end
            table.sort(list, function(a, b)
                if rank(a) ~= rank(b) then return rank(a) < rank(b) end
                if a.stateData.isOnline ~= b.stateData.isOnline then return a.stateData.isOnline end
                return a.interactionData.interactions[1].timestamp > b.interactionData.interactions[1].timestamp
            end)
            return list
        end,
        IsRecentAllyPinned = function(guid) local a = ally(guid); return a ~= nil and a.stateData.pinExpirationDate ~= nil end,
        SetRecentAllyPinned = function(guid, on)
            record("SetRecentAllyPinned", guid, on)
            local a = ally(guid)
            if a then a.stateData.pinExpirationDate = on and (time() + 86400 * 30) or nil end
            later("RECENT_ALLY_DATA_UPDATED", guid)
        end,
        CanSetRecentAllyNote = function() return true end,
        SetRecentAllyNote = function(guid, note) record("SetRecentAllyNote", guid, note); local a = ally(guid); if a then a.interactionData.note = note end; later("RECENT_ALLY_DATA_UPDATED", guid) end,
    }
    -- RolodexConstantsDocumentation (a few of its kinds)
    Enum.RolodexType = Enum.RolodexType or { None = 0, PartyMember = 1, RaidMember = 2, Trade = 3, Whisper = 4, CompleteDungeon = 12, KillRaidBoss = 13, LegacyFriend = 23 }
    _G.C_ClassInfo = _G.C_ClassInfo or {}
    local classInfo = keep(C_ClassInfo, "GetClassInfo")
    C_ClassInfo.GetClassInfo = function(id)
        local token = CLASS_ID[id]
        if token then return { className = CLASS_WORD[token], classFile = token, classID = id } end
        return classInfo and classInfo(id)
    end

    -- The raid (otherwise the world's own group, the hostile sweep's battleground)
    local inRaid, members, leader, assist, roster = keep(_G, "IsInRaid"), keep(_G, "GetNumGroupMembers"), keep(_G, "UnitIsGroupLeader"),
        keep(_G, "UnitIsGroupAssistant"), keep(_G, "GetRaidRosterInfo")
    local inGroup = keep(_G, "IsInGroup")
    _G.IsInRaid = function(...) if S().roster then return true end return inRaid and inRaid(...) or false end
    _G.IsInGroup = function(...) if S().roster then return true end return inGroup and inGroup(...) or false end
    _G.GetNumGroupMembers = function(...) if S().roster then return #S().roster end return members and members(...) or 0 end
    _G.UnitIsGroupLeader = function(u, ...) if S().roster then return u == "player" and me()[6] == 2 end return leader and leader(u, ...) or false end
    _G.UnitIsGroupAssistant = function(u, ...) if S().roster then return u == "player" and me()[6] == 1 end return assist and assist(u, ...) or false end
    _G.GetRaidRosterInfo = function(i)
        local r = S().roster
        if not r then return roster and roster(i) end
        local m = r[i]
        if not m then return nil end
        local x = m[7] or {}
        return m[1], m[6], m[4], m[3], CLASS_WORD[m[2]], m[2], "Molten Core", not x.offline, x.dead == true, nil, false, m[5]
    end
    _G.GetGroupMemberCountsForDisplay = function()
        local c = { TANK = 0, HEALER = 0, DAMAGER = 0, NOROLE = 0 }
        for _, m in ipairs(S().roster or {}) do c[m[5]] = c[m[5]] + 1 end
        return c
    end
    local function groupCount(g) local n = 0; for _, m in ipairs(S().roster or {}) do if m[4] == g then n = n + 1 end end return n end
    _G.SetRaidSubgroup = function(i, g)
        record("SetRaidSubgroup", i, g)
        local m = S().roster and S().roster[i]
        if not (m and canMove()) or groupCount(g) >= 5 then return end
        m[4] = g
        later("GROUP_ROSTER_UPDATE")
    end
    _G.SwapRaidSubgroup = function(i, j)
        record("SwapRaidSubgroup", i, j)
        local r = S().roster
        local a, b = r and r[i], r and r[j]
        if not (a and b and canMove()) then return end
        a[4], b[4] = b[4], a[4]
        later("GROUP_ROSTER_UPDATE")
    end
    _G.GetReadyCheckStatus = function(unit) return S().ready and S().ready[unit] or nil end
    local party = keep(_G, "C_PartyInfo")
    _G.C_PartyInfo = setmetatable({
        IsRaidListEnabled = function() return true end,
        IsEveryoneAssistant = function() return S().allAssist == true end,
        SetEveryoneIsAssistant = function(on)
            if not stub.HardwareOnly("C_PartyInfo.SetEveryoneIsAssistant") then return end
            record("SetEveryoneIsAssistant", on); S().allAssist = on; later("GROUP_ROSTER_UPDATE")
        end,
        ConvertToRaid = function()
            if not stub.HardwareOnly("C_PartyInfo.ConvertToRaid") then return end
            record("ConvertToRaid")
        end,
        AllowedToDoPartyConversion = function(toRaid) return toRaid and S().partyLead == true end,
        InviteUnit = function(name) record("InviteUnit", name) end,
        -- The client only has these here (PartyInfoDocumentation.lua). The game's
        -- own menu calls them with the full name, as an exact match.
        PromoteToLeader = function(name, exact) record("PromoteToLeader", name, exact) end,
        PromoteToAssistant = function(name, exact) record("PromoteToAssistant", name, exact) end,
        DemoteAssistant = function(name, exact) record("DemoteAssistant", name, exact) end,
        UninviteUnit = function(name, reason, exact) record("UninviteUnit", name, reason, exact) end,
    }, { __index = party or nil })
    _G.PromoteToLeader, _G.PromoteToAssistant, _G.DemoteAssistant, _G.UninviteUnit = nil, nil, nil, nil
    _G.RequestRaidInfo = function() record("RequestRaidInfo") end
    _G.GetNumSavedInstances = function() return #S().saved end
    _G.GetSavedInstanceInfo = function(i)
        local s = S().saved[i]
        if not s then return nil end
        return s[1], i, s[2], 9, true, false, 0, true, 40, "40 Player", s[3], s[4]
    end
end

-- spec: friends, invites, allies, ignores, saved (defaults: the samples above),
-- enabled (the module's switch, default true), raid (a roster, in a raid from the
-- start), alliesReady (false: the client has none cached yet).
function SW.world(spec)
    spec = spec or {}
    return function()
        SW.state = { calls = {}, friends = spec.friends or SW.Friends(),
            invites = spec.invites or { { inviteID = 21, accountName = "Bramblefoot#2231", creationTimestamp = time() - 2 * 86400 },
                { inviteID = 22, accountName = "Nyx#9810", creationTimestamp = time() - 600 } },
            allies = spec.allies or SW.Allies(), ignores = spec.ignores or { "Grimble Sootfoot", "Vexx Darkmantle" },
            saved = spec.saved or { { "Molten Core", 3 * 86400, 10, 6 }, { "Onyxia's Lair", 4 * 86400, 1, 1 } },
            roster = spec.raid, alliesReady = spec.alliesReady, enabled = spec.system }
        _G.SocialUIFrame = nil
        install()
        frame()   -- Blizzard_SocialUI loads with the game (not on demand), so its frame exists before the addon's
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { Social = { enabled = spec.enabled ~= false } } } } }
    end
end

return SW
