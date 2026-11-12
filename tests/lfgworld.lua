-- The fake game's group finder for the group finder window's tests, as Forever has
-- it (Blizzard_GroupFinder_VanillaStyle, plus what was seen in game):
--   * LFGParentFrame (UIPanelWindows left) holds three pages: LFGListingFrame,
--     LFGBrowseFrame, LFGWhoListFrame. LFGVanilla_ToggleFrame(tab) shows it on
--     that tab (selectedTab), or hides it when that tab already shows. It's made
--     on the first open (ADDON_LOADED "Blizzard_GroupFinder_VanillaStyle").
--   * The note box LFGListingComment.EditBox is the game's secure one. Addon code
--     may not SetText it (SetSecurityDisableSetText); the player types in it, and
--     CreateListing reads it.
--   * The game's listing page hears LFG_LIST_ACTIVE_ENTRY_UPDATE(created). A new
--     listing switches the game to its browse tab and searches the listing's
--     activities (LFGParentFrame_SearchActiveEntry).
--   * Search answers a frame later (LFG_LIST_SEARCH_RESULTS_RECEIVED, 0.4 s in
--     game). GetFilteredSearchResults returns the last search's results.
--   * SendWho answers a frame later (WHO_LIST_UPDATE). SetWhoToUi is one switch
--     for the whole client.
--   * A new listing needs a playstyle (Enum.LFGEntryGeneralPlaystyle 1-4). The
--     game's page keeps List off without one (GROUP_FINDER_PLAYSTYLE_REQUIRED);
--     that the client refuses one without it (LFG_LIST_ENTRY_CREATION_FAILED) is a
--     guess. Results and your listing carry generalPlaystyle.
--
-- LW.world(spec) is stub.Load's "before". A test then plays LW.Toggle(tab),
-- LW.Close(), LW.Type(text) (the player types a note), LW.Group(n, leader), and
-- reads LW.Calls(kind).
local stub = require("stub")

local LW = {}

local function S() return LW.state end
local function record(kind, ...) table.insert(S().calls, { kind = kind, args = { ... } }) end
function LW.Calls(kind)
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
LW.AsGame = asGame

-- Categories and activities as read in game at level 14 (Dungeons, Quests & Zones,
-- Custom), plus a raid out of your level's reach.
LW.CATEGORIES = {
    [2] = { name = "Dungeons", groups = { 285 } },
    [114] = { name = "Raids", groups = { 290 } },
    [116] = { name = "Quests & Zones", groups = { 300 } },
    [120] = { name = "Custom", autoChooseActivity = true, groups = { 0 } },
}
LW.GROUPS = { [285] = { "Dungeons", 20 }, [290] = { "Raids", 30 }, [300] = { "Zones", 10 }, [0] = { "Custom", 1 } }
LW.ACTIVITIES = {
    [798] = { fullName = "Ragefire Chasm", shortName = "", categoryID = 2, groupFinderActivityGroupID = 285, minLevelSuggestion = 13, maxLevelSuggestion = 18, maxNumPlayers = 5, displayType = 1, orderIndex = 0 },
    [799] = { fullName = "Wailing Caverns", shortName = "", categoryID = 2, groupFinderActivityGroupID = 285, minLevelSuggestion = 12, maxLevelSuggestion = 25, maxNumPlayers = 5, displayType = 1, orderIndex = 1 },
    [800] = { fullName = "Scarlet Monastery", shortName = "", categoryID = 2, groupFinderActivityGroupID = 285, minLevelSuggestion = 26, maxLevelSuggestion = 45, maxNumPlayers = 5, displayType = 1, orderIndex = 2 },
    [900] = { fullName = "Molten Core", shortName = "", categoryID = 114, groupFinderActivityGroupID = 290, minLevelSuggestion = 60, maxLevelSuggestion = 60, maxNumPlayers = 40, displayType = 2, orderIndex = 0 },
    [950] = { fullName = "The Barrens", shortName = "", categoryID = 116, groupFinderActivityGroupID = 300, minLevelSuggestion = 10, maxLevelSuggestion = 25, maxNumPlayers = 5, displayType = 1, orderIndex = 0 },
    [990] = { fullName = "Custom", shortName = "", categoryID = 120, groupFinderActivityGroupID = 0, minLevelSuggestion = 0, maxLevelSuggestion = 0, maxNumPlayers = 0, displayType = 6, orderIndex = 0 },
}

-- Listings out there: a group of three (tank, healer, damage), and two players alone.
function LW.Sample()
    return {
        { id = 17, activityIDs = { 798 }, age = 26, comment = "need dps", generalPlaystyle = 2,
          members = { { name = "Gorrak Stonefist", classFilename = "WARRIOR", level = 15, assignedRole = "TANK", areaName = "Westfall" },
                      { name = "Mira Dawnsong", classFilename = "PRIEST", level = 14, assignedRole = "HEALER" },
                      { name = "Tuk", classFilename = "HUNTER", level = 15, assignedRole = "DAMAGER" } } },
        { id = 18, activityIDs = { 798 }, age = 1218, comment = "",
          members = { { name = "Ularanu Seachaser", classFilename = "HUNTER", level = 15, assignedRole = "DAMAGER", lfgRoles = { tank = false, healer = false, dps = true } } } },
        { id = 19, activityIDs = { 799 }, age = 40, comment = "heals or dps",
          members = { { name = "Sela", classFilename = "DRUID", level = 16, assignedRole = "HEALER", areaName = "The Barrens", lfgRoles = { tank = true, healer = true, dps = false } } } },
    }
end

LW.WHO = {
    { fullName = "Daemon Process", fullGuildName = "", level = 14, raceStr = "Orc", classStr = "Warlock", area = "Agama'gor", filename = "WARLOCK" },
    { fullName = "Lava Flows", fullGuildName = "Stormcallers", level = 14, raceStr = "Windshaper Skyborne", classStr = "Shaman", area = "Boulder Lode Mine", filename = "SHAMAN" },
}

local function result(id)
    for _, r in ipairs(S().results) do if r.id == id then return r end end
    return nil
end

local function counts(r)
    local c = { TANK = 0, HEALER = 0, DAMAGER = 0, NOROLE = 0 }
    for _, m in ipairs(r.members) do c[m.assignedRole] = (c[m.assignedRole] or 0) + 1 end
    c.TANK_REMAINING = math.max(0, 1 - c.TANK)
    c.HEALER_REMAINING = math.max(0, 1 - c.HEALER)
    c.DAMAGER_REMAINING = math.max(0, 3 - c.DAMAGER)
    local lead = r.members[1].lfgRoles or {}
    c.LEADER_ROLE_TANK, c.LEADER_ROLE_HEALER, c.LEADER_ROLE_DAMAGER = lead.tank == true, lead.healer == true, lead.dps == true
    return c
end

local function frame()
    if _G.LFGParentFrame then return _G.LFGParentFrame end
    local p = CreateFrame("Frame", "LFGParentFrame", UIParent)
    p:Hide()
    p.selectedTab = 1
    local listing = CreateFrame("Frame", "LFGListingFrame", p)
    local browse = CreateFrame("Frame", "LFGBrowseFrame", p)
    local who = CreateFrame("Frame", "LFGWhoListFrame", p)
    listing.ActivityView = CreateFrame("Frame", "LFGListingFrameActivityView", listing)
    local comment = CreateFrame("ScrollFrame", "LFGListingComment", listing.ActivityView)
    comment:SetPoint("BOTTOM", listing.ActivityView, "BOTTOM", 0, 150)
    comment:SetSize(394, 47)
    comment.EditBox = CreateFrame("EditBox", nil, comment)
    local set = comment.EditBox.SetText
    comment.EditBox.SetText = function(self, t)   -- SetSecurityDisableSetText: only the game's code may
        if (stub.inSecure or 0) == 0 then error("SetText: this edit box's text can't be set by addon code", 2) end
        return set(self, t)
    end
    listing.ActivityView.Comment = comment
    p.ListingFrame, p.BrowseFrame, p.WhoFrame = listing, browse, who
    -- The game's listing page (LFGListingMixin:OnEvent): a new listing searches
    -- its activities on the browse tab.
    listing:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
    listing:SetScript("OnEvent", function(_, _, created)
        local e = S().entry
        if e and created then
            asGame(function()
                LW.SetTab(2)
                C_LFGList.Search(LW.ACTIVITIES[e.activityIDs[1]].categoryID, 0, 0, nil, false, nil, e.activityIDs)
            end)
        end
    end)
    who:SetScript("OnShow", function() C_FriendList.SetWhoToUi(true) end)
    who:SetScript("OnHide", function() C_FriendList.SetWhoToUi(false) end)
    record("Loaded")
    stub.FireEvent("ADDON_LOADED", "Blizzard_GroupFinder_VanillaStyle")
    return p
end

function LW.Load() return frame() end

-- LFGParentFrame_SetActiveTab: the game's pages, one shown at a time.
function LW.SetTab(tab)
    local p = frame()
    p.selectedTab = tab
    p.ListingFrame:SetShown(tab == 1)
    p.BrowseFrame:SetShown(tab == 2)
    p.WhoFrame:SetShown(tab == 3)
end

-- LFGVanilla_ToggleFrame(tab): the key (tab 1), the micro button, the eye.
function LW.Toggle(tab)
    asGame(function()
        local p = frame()
        local pages = { p.ListingFrame, p.BrowseFrame, p.WhoFrame }
        local current = tab and pages[tab] and pages[tab]:IsShown() and tab == p.selectedTab
        if (p:IsShown() and not tab) or (p:IsShown() and current) then
            HideUIPanel(p)
        else
            ShowUIPanel(p)
            LW.SetTab(tab or p.selectedTab)
        end
    end)
end

function LW.Close() asGame(function() HideUIPanel(frame()) end) end

-- The player types a note into the game's box (a hardware event, in the game's code).
function LW.Type(text) asGame(function() frame().ListingFrame.ActivityView.Comment.EditBox:SetText(text) end) end
function LW.Note() return frame().ListingFrame.ActivityView.Comment.EditBox:GetText() end

-- In a group of n (you lead it, or not).
function LW.Group(n, lead)
    S().group = n
    S().lead = lead ~= false
    stub.FireEvent("GROUP_ROSTER_UPDATE")
end

-- A listing out there changes (a member joins, it's delisted).
function LW.Update(id, change)
    local r = result(id)
    for k, v in pairs(change) do r[k] = v end
    stub.FireEvent("LFG_LIST_SEARCH_RESULT_UPDATED", id)
end

local original = {}
local function keep(t, name)
    local key = tostring(t) .. name
    if original[key] == nil then original[key] = t[name] or false end
    return original[key] or nil
end

local function filtered(cat)
    local out = {}
    for id, a in pairs(LW.ACTIVITIES) do
        if a.categoryID == cat then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

local function entryInfo()
    local e = S().entry
    if not e then return nil end
    return { activityIDs = { unpack(e.activityIDs) }, comment = e.comment, newPlayerFriendly = e.newPlayerFriendly,
        generalPlaystyle = e.generalPlaystyle, duration = 1800 }
end

local function setEntry(t, created)
    local style = (t.generalPlaystyle and t.generalPlaystyle ~= 0) and t.generalPlaystyle or (S().entry and S().entry.generalPlaystyle)
    S().entry = { activityIDs = { unpack(t.activityIDs) }, comment = LW.Note(), newPlayerFriendly = t.newPlayerFriendly == true, generalPlaystyle = style }
    local me = { id = 99, activityIDs = S().entry.activityIDs, age = 0, comment = S().entry.comment, hasSelf = true, generalPlaystyle = style,
        members = { { name = "Sunwalker", classFilename = "SHAMAN", level = 14, assignedRole = "DAMAGER", lfgRoles = S().roles } } }
    for i, r in ipairs(S().results) do if r.id == 99 then table.remove(S().results, i); break end end
    table.insert(S().results, me)
    C_Timer.After(0, function()
        stub.FireEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE", created)
        -- The game's own listing page on a new listing (LFGParentFrame_SearchActiveEntry
        -- in Blizzard_LFGVanilla_Browse.lua): its untainted code searches only your
        -- listing's activities (SetSelectedSearchActivities, then LFGBrowse_DoSearch).
        if created then
            local a = LW.ACTIVITIES[S().entry.activityIDs[1]]
            record("GameSearch", a and a.categoryID, S().entry.activityIDs)
            S().searched = { cat = a and a.categoryID, acts = { unpack(S().entry.activityIDs) } }
            C_Timer.After(0, function() stub.FireEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED") end)
        end
    end)
    return true
end

local function install()
    _G.ShowUIPanel = function(f) record("ShowUIPanel", f:GetName()); f:Show() end
    _G.HideUIPanel = function(f) record("HideUIPanel", f:GetName()); f:Hide() end
    -- The player's level and group are the test's only while it sets them
    -- (LW.Group); otherwise they're the world's (the hostile sweep's battleground).
    local level, inGroup, members, leader = keep(_G, "UnitLevel"), keep(_G, "IsInGroup"), keep(_G, "GetNumGroupMembers"), keep(_G, "UnitIsGroupLeader")
    _G.UnitLevel = function(u)
        if u == "player" and S().level then return S().level end
        return level and level(u) or 1
    end
    _G.LE_PARTY_CATEGORY_HOME = 1
    _G.UnitGetAvailableRoles = function() return false, true, true end   -- a shaman's class roles
    _G.IsInGroup = function(cat, ...)
        if S().instanceGroup then return cat ~= LE_PARTY_CATEGORY_HOME end
        if S().group then return S().group > 1 end
        return inGroup and inGroup(cat, ...) or false
    end
    _G.GetNumGroupMembers = function(...)
        if S().group then return S().group end
        return members and members(...) or 0
    end
    _G.UnitIsGroupLeader = function(u, ...)
        if S().group then return u == "player" and S().group > 1 and S().lead end
        return leader and leader(u, ...) or false
    end
    _G.UnitIsGroupAssistant = _G.UnitIsGroupAssistant or function() return false end
    -- Your role in a group. The game's listing page menu calls UnitSetRole
    -- (HasRestrictions in the docs, so a click runs it), and the game answers with the event.
    _G.UnitGroupRolesAssigned = function(u) return u == "player" and S().role or "NONE" end
    _G.UnitSetRole = function(u, role)
        if not stub.HardwareOnly("UnitSetRole") then return false end
        record("UnitSetRole", u, role)
        S().role = role
        stub.FireEvent("PLAYER_ROLES_ASSIGNED")
        return true
    end
    local cvar = keep(_G, "GetCVarBool")
    _G.GetCVarBool = function(k)
        if S().cvars[k] ~= nil then return S().cvars[k] == "1" end
        return cvar and cvar(k) or false
    end
    -- The client tells everyone a CVar changed (CVAR_UPDATE, name and value).
    _G.SetCVar = function(k, v)
        S().cvars[k] = tostring(v == true and "1" or v == false and "0" or v)
        stub.FireEvent("CVAR_UPDATE", k, S().cvars[k])
    end
    -- The game's playstyle words (GlobalStrings, as the dropdown shows them in game).
    _G.GROUP_FINDER_PLAYSTYLE_REQUIRED = "Select Playstyle (required)"
    _G.GROUP_FINDER_GENERAL_PLAYSTYLE1, _G.GROUP_FINDER_GENERAL_PLAYSTYLE2 = "Learning", "Relaxed"
    _G.GROUP_FINDER_GENERAL_PLAYSTYLE3, _G.GROUP_FINDER_GENERAL_PLAYSTYLE4 = "Competitive", "Carry Offered"
    _G.CreateAtlasMarkup = function(atlas, w, h) return "|A:" .. atlas .. ":" .. (h or 0) .. ":" .. (w or 0) .. "|a" end
    _G.ChatFrameUtil = { SendTell = function(name) record("SendTell", name) end }
    _G.C_PartyInfo = _G.C_PartyInfo or {}
    C_PartyInfo.InviteUnit = function(name) record("InviteUnit", name) end
    _G.C_LFGInfo = { CanPlayerUsePremadeGroup = function() return true end }
    _G.C_LFGListRoles = {
        GetRoles = function() local r = S().roles; return { tank = r.tank, healer = r.healer, dps = r.dps } end,
        GetSavedRoles = function() local r = S().roles; return { tank = r.tank, healer = r.healer, dps = r.dps } end,
        -- The game's rule: LFG_LIST_ROLE_UPDATE is synchronous, and false means not taken.
        SetRoles = function(t)
            record("SetRoles", t)
            if S().rolesRefused then return false end
            S().roles = { tank = t.tank == true, healer = t.healer == true, dps = t.dps == true }
            stub.FireEvent("LFG_LIST_ROLE_UPDATE")
            return true
        end,
    }
    _G.C_LFGList = {
        GetPremadeGroupFinderStyle = function() return 2 end,
        IsPremadeGroupFinderEnabled = function() return true end,
        GetAvailableCategories = function() return { 2, 114, 116, 120 } end,
        GetLfgCategoryInfo = function(id)
            local c = LW.CATEGORIES[id]
            return c and { name = c.name, autoChooseActivity = c.autoChooseActivity == true, separateRecommended = false } or nil
        end,
        GetAvailableActivityGroups = function(cat) local c = LW.CATEGORIES[cat]; return c and { unpack(c.groups) } or {} end,
        GetActivityGroupInfo = function(gid) local g = LW.GROUPS[gid]; if g then return g[1], g[2] end end,
        GetAvailableActivities = function(cat) return filtered(cat) end,
        GetActivityInfoTable = function(id) local a = LW.ACTIVITIES[id]; if not a then return nil end; local t = {}; for k, v in pairs(a) do t[k] = v end; return t end,
        IsPlayerAuthenticatedForLFG = function() return true end,
        -- What your spec does (the dungeon finder grays the rest). The listing
        -- page never asks it, so a warrior in Arms can still list as a tank.
        GetAvailableRoles = function() return false, false, true end,
        HasActiveEntryInfo = function() return S().entry ~= nil end,
        GetActiveEntryInfo = entryInfo,
        -- HasRestrictions: a guess that they need a click or a key like retail's
        -- (in game they were only tried from a typed command).
        CreateListing = function(t)
            if not stub.HardwareOnly("C_LFGList.CreateListing") then return false end
            record("CreateListing", t)
            local style = t.generalPlaystyle
            if type(style) ~= "number" or style < 1 or style > 4 then
                C_Timer.After(0, function() stub.FireEvent("LFG_LIST_ENTRY_CREATION_FAILED") end)
                return false
            end
            return setEntry(t, true)
        end,
        UpdateListing = function(t)
            if not stub.HardwareOnly("C_LFGList.UpdateListing") then return false end
            record("UpdateListing", t); return setEntry(t, false)
        end,
        RemoveListing = function()
            record("RemoveListing")
            S().entry = nil
            for i, r in ipairs(S().results) do if r.id == 99 then r.isDelisted = true end end
            C_Timer.After(0, function() stub.FireEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE") end)
        end,
        Search = function(cat, filter, preferred, lang, cross, adv, acts)
            if not stub.HardwareOnly("C_LFGList.Search") then return end
            record("Search", cat, acts)
            S().searched = { cat = cat, acts = acts }
            C_Timer.After(0, function() stub.FireEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED") end)
        end,
        GetFilteredSearchResults = function()
            local q = S().searched
            local ids = {}
            if q then
                for _, r in ipairs(S().results) do
                    local a = LW.ACTIVITIES[r.activityIDs[1]]
                    local want = not q.acts or #q.acts == 0
                    for _, id in ipairs(q.acts or {}) do if id == r.activityIDs[1] then want = true end end
                    if a.categoryID == q.cat and want then ids[#ids + 1] = r.id end
                end
            end
            return #ids, ids
        end,
        GetSearchResultInfo = function(id)
            local r = result(id)
            if not r then return nil end
            local lead = r.members[1]
            return { searchResultID = id, activityIDs = { unpack(r.activityIDs) }, leaderName = lead.name, comment = r.comment,
                numMembers = #r.members, age = r.age, isDelisted = r.isDelisted == true, hasSelf = r.hasSelf == true,
                newPlayerFriendly = r.newPlayerFriendly == true, generalPlaystyle = r.generalPlaystyle, voiceMode = 0 }
        end,
        GetSearchResultMemberCounts = function(id) local r = result(id); return r and counts(r) or nil end,
        GetSearchResultPlayerInfo = function(id, i)
            local r = result(id)
            local m = r and r.members[i]
            if not m then return nil end
            return { name = m.name, level = m.level, areaName = m.areaName, classFilename = m.classFilename, assignedRole = m.assignedRole,
                lfgRoles = m.lfgRoles or { tank = false, healer = false, dps = false }, isLeader = i == 1 }
        end,
        GetSearchResultEncounterInfo = function() return nil end,
        ClearCreationTextFields = function() record("ClearCreationTextFields") end,
        RequestAvailableActivities = function() end,
    }
    local who = keep(_G, "C_FriendList")
    _G.C_FriendList = setmetatable({
        SendWho = function(text, origin)
            if not stub.HardwareOnly("C_FriendList.SendWho") then return end
            record("SendWho", text, origin)
            C_Timer.After(0, function() stub.FireEvent("WHO_LIST_UPDATE") end)
        end,
        GetNumWhoResults = function() return #LW.WHO, #LW.WHO end,
        GetWhoInfo = function(i) return LW.WHO[i] end,
        SetWhoToUi = function(on) record("SetWhoToUi", on); S().whoToUi = on end,
        SortWho = function(mode, up) record("SortWho", mode, up) end,
    }, { __index = who or nil })
    Enum.SocialWhoOrigin = Enum.SocialWhoOrigin or { Unknown = 0, Social = 1, Chat = 2, Item = 3 }
end

-- spec: results (default LW.Sample()), level (14), roles, enabled (the module's
-- switch, default true here since the tests are about Daylight UI's window).
function LW.world(spec)
    spec = spec or {}
    return function()
        LW.state = { calls = {}, results = spec.results or LW.Sample(), level = (spec.level == nil) and 14 or (spec.level or nil),
            roles = spec.roles or { tank = false, healer = false, dps = true }, cvars = {} }
        _G.LFGParentFrame, _G.LFGListingFrame, _G.LFGBrowseFrame, _G.LFGWhoListFrame, _G.LFGListingComment = nil, nil, nil, nil, nil
        install()
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { GroupFinder = { enabled = spec.enabled ~= false } } } } }
    end
end

return LW
