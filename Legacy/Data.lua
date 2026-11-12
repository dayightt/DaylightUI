-- Reads for the Legacy window, based on Forever's Blizzard_LegacySystem. Returns plain
-- tables for the pages and draws nothing. None of it is secret.
--
-- Points: earned = the Legacy faction's renown level; to spend = the trees' currency
-- (the first tree's, like LegacySystem.GetCurrencyInfo), shared by all three trees.
-- Progress: the faction's renown levels and their rewards.
-- Challenges: achievement lists filtered the game's way (LegacySystem.GetChallengeIndices
-- / IsChallengeVisible), worth Legacy Points (GetTraitCurrencyForAchievement).
-- Trees: three trait trees, each with its own config.

local _, DUI = ...
DUI.Legacy = DUI.Legacy or {}
local ns = DUI.Legacy
local L = DUI.L

local Data = {}
ns.Data = Data

-- All returns (GetAchievementInfo has 13), or nothing on failure.
local function answers(ok, ...) if ok then return ... end end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    return answers(pcall(fn, ...))
end

local function api(space, name)
    local t = _G[space]
    return type(t) == "table" and t[name] or nil
end

function Data.Consts()
    local C = type(Constants) == "table" and Constants.LegacyConsts
    return type(C) == "table" and C or {}
end

function Data.FactionID() return Data.Consts().LEGACY_REWARD_TRACK_FACTION_ID end

-- The game only opens its window past renown 0 (ToggleLegacySystemUI).
function Data.Earned()
    local n = call(api("C_MajorFactions", "GetCurrentRenownLevel"), Data.FactionID())
    return type(n) == "number" and n or 0
end

-- Trees and points

-- The game's LegacyTreeData (Blizzard_LegacySystemConstants.lua), rebuilt from the
-- client's constants because the game's addon only loads with its window.
function Data.Trees()
    local C = Data.Consts()
    return {
        { treeID = C.LEGACY_TREE_PROFESSIONS_ID, atlas = "UI-Legacy-Tree-Professions", name = LEGACY_TREE_PROFESSIONS or L["Professions"] },
        { treeID = C.LEGACY_TREE_ADVENTURE_ID, atlas = "UI-Legacy-Tree-Adventure", name = LEGACY_TREE_ADVENTURE or L["Adventure"] },
        { treeID = C.LEGACY_TREE_PROGRESSION_ID, atlas = "UI-Legacy-Tree-Progression", name = LEGACY_TREE_PROGRESSION or L["Progression"] },
    }
end

function Data.ConfigOf(treeID)
    local id = treeID and call(api("C_Traits", "GetConfigIDByTreeID"), treeID)
    return type(id) == "number" and id or nil
end

-- { earned, left, cap, max, currencyID }: earned = renown (every point on the account),
-- left = unspent in the trees, cap = this season's maximum (maxQuantity), max = the
-- overall maximum (GetMaxAvailableTraitCurrency).
function Data.Points()
    local out = { earned = Data.Earned(), left = 0 }
    local tree = Data.Trees()[1]
    local configID = Data.ConfigOf(tree.treeID)
    local info = configID and call(api("C_Traits", "GetTreeCurrencyInfo"), configID, tree.treeID, false)
    local c = type(info) == "table" and info[1]
    if type(c) == "table" then
        out.left = type(c.quantity) == "number" and c.quantity or 0
        out.cap = type(c.maxQuantity) == "number" and c.maxQuantity or nil
        out.currencyID = c.traitCurrencyID
        local max = c.traitCurrencyID and call(api("C_Traits", "GetMaxAvailableTraitCurrency"), c.traitCurrencyID, false)
        out.max = type(max) == "number" and max or nil
    end
    return out
end

-- Progress: the reward track

-- One-word reward type, using the game's string where it has one.
function Data.Kind(r)
    if r.mountID then return MOUNT or L["Mount"] end
    if r.titleMaskID then return L["Title"] end
    if r.transmogID or r.transmogSetID or r.transmogIllusionSourceID then return L["Appearance"] end
    if r.itemID then
        if call(api("C_ToyBox", "GetToyInfo"), r.itemID) then return TOY or L["Toy"] end
        if call(api("C_PetJournal", "GetPetInfoByItemID"), r.itemID) then return PET or L["Pet"] end
        local _, itemType, subType, equipLoc = call(api("C_Item", "GetItemInfoInstant"), r.itemID)
        if equipLoc == "INVTYPE_TABARD" then return INVTYPE_TABARD or L["Tabard"] end
        if type(subType) == "string" and subType ~= "" then return subType end
        if type(itemType) == "string" and itemType ~= "" then return itemType end
        return L["Item"]
    end
    if r.spellID then return L["Spell"] end
    return ""
end

-- Reward icon, name, description, type and quality, as the game gives them
-- (RenownRewardUtil, unformatted: "Spectral Bear Cub", never "Item: ...").
-- Items not loaded yet arrive later through onLoad.
function Data.Reward(r, onLoad)
    local out = { kind = Data.Kind(r), itemID = r.itemID }
    local U = RenownRewardUtil
    if type(U) == "table" and type(U.GetUnformattedRenownRewardInfo) == "function" then
        local icon, name, _, desc = call(U.GetUnformattedRenownRewardInfo, r, onLoad or function() end)
        out.icon, out.name, out.desc = icon, name, desc
    end
    out.icon = out.icon or r.icon
    out.name = out.name or r.name or ""
    out.desc = out.desc or r.description
    if r.itemID then
        local q = call(api("C_Item", "GetItemQualityByID"), r.itemID)
        out.quality = type(q) == "number" and q or nil
    end
    return out
end

-- { earned, levels = { { level, rewards = { Data.Reward... } } } }, or nil until the
-- faction's data is available (the game waits the same way).
function Data.Track(onLoad)
    local fid = Data.FactionID()
    local info = fid and call(api("C_MajorFactions", "GetMajorFactionData"), fid)
    if type(info) ~= "table" then return nil end
    local levels = call(api("C_MajorFactions", "GetRenownLevels"), fid)
    local out = { earned = Data.Earned(), levels = {} }
    for _, lv in ipairs(type(levels) == "table" and levels or {}) do
        if type(lv) == "table" and type(lv.level) == "number" then
            local rewards = call(api("C_MajorFactions", "GetRenownRewardsForLevel"), fid, lv.level)
            local row = { level = lv.level, rewards = {} }
            for _, r in ipairs(type(rewards) == "table" and rewards or {}) do row.rewards[#row.rewards + 1] = Data.Reward(r, onLoad) end
            out.levels[#out.levels + 1] = row
        end
    end
    table.sort(out.levels, function(a, b) return a.level < b.level end)
    return out
end

-- Challenges

-- Chip state: "all", "todo" (not done) or "done" (the game's Completed / Incomplete
-- filters). Kept for the session.
Data.show = "all"

local function wantDone() return Data.show ~= "todo" end
local function wantTodo() return Data.show ~= "done" end

-- Search result: the achievements it lets through (like
-- LegacySystem.GetFilteredChallenges), or nil while there's no answer yet.
function Data.Filtered()
    local n = call(GetNumFilteredAchievements)
    if type(n) ~= "number" or n == 0 then return nil end
    local out = {}
    for i = 1, n do
        local id = call(GetFilteredAchievementID, i)
        if id then out[id] = true end
    end
    return out
end

-- Set the search the way the game's page does, on every show too, since the client
-- drops its search data on each loading screen. ACHIEVEMENT_SEARCH_UPDATED answers.
function Data.Search(text)
    Data.searching = text or ""
    call(SetAchievementSearchString, Data.searching)
end

-- Like the game's GetChallengeIndices: completed ones come first in a category.
local function indices(catID)
    local _, done, todo = call(GetCategoryNumAchievements, catID)
    done, todo = type(done) == "number" and done or 0, type(todo) == "number" and todo or 0
    if wantDone() and wantTodo() then return 0, done + todo end
    if wantTodo() then return done, todo end
    return 0, done
end

-- Earned by another character counts as not done (like the game's
-- AchievementFrame_ShowAsComplete and IsChallengeVisible).
local function visible(filtered, id, mine)
    if filtered and not filtered[id] then return false end
    if not mine and not wantTodo() then return false end
    return true
end

-- A challenge in the shape a row needs.
function Data.Challenge(catID, i)
    local id, name, _, completed, month, day, year, desc, flags, icon, _, _, mine = call(GetAchievementInfo, catID, i)
    if type(id) ~= "number" then return nil end
    local done = completed == true and mine == true
    local pts = call(api("C_Traits", "GetTraitCurrencyForAchievement"), Data.Consts().LEGACY_POINTS_TRAIT_CURRENCY_ID, id)
    local date
    if done and day and month and year then
        date = type(FormatShortDate) == "function" and call(FormatShortDate, day, month, year) or string.format("%d/%d/%02d", month, day, year)
    end
    local ACCOUNT = ACHIEVEMENT_FLAGS_ACCOUNT or 0x20000
    return { id = id, name = name or "", desc = desc or "", icon = icon, done = done, date = date, mine = mine == true,
        points = type(pts) == "number" and pts or 0, account = type(flags) == "number" and bit and bit.band(flags, ACCOUNT) == ACCOUNT or false }
end

-- A category's challenges that pass the chips and search.
function Data.Challenges(catID, filtered)
    local out = {}
    local from, count = indices(catID)
    for i = from + 1, from + count do
        local c = Data.Challenge(catID, i)
        if c and visible(filtered, c.id, c.mine) then out[#out + 1] = c end
    end
    return out
end

-- done, total in a category (chips don't affect it; it's the whole list).
function Data.Count(catID)
    local total, done = call(GetCategoryNumAchievements, catID)
    return type(done) == "number" and done or 0, type(total) == "number" and total or 0
end

-- Like the game's HasChallenges and AllChallengesFiltered: stops at the first visible
-- challenge (only its id and owner are read).
local function shows(catID, filtered)
    local _, done, todo = call(GetCategoryNumAchievements, catID)
    done, todo = done or 0, todo or 0
    if not ((wantDone() and done > 0) or (wantTodo() and todo > 0)) then return false end
    local from, count = indices(catID)
    for i = from + 1, from + count do
        local id, _, _, _, _, _, _, _, _, _, _, _, mine = call(GetAchievementInfo, catID, i)
        if type(id) == "number" and visible(filtered, id, mine == true) then return true end
    end
    return false
end

-- Categories left after chips and search, as a tree (like the game's
-- GenerateDataProvider): { { id, name, kids = { ... }, has = has its own challenges } }
-- in the game's order. A parent shows when any child does.
function Data.Categories(filtered)
    local list = call(GetCategoryList)
    list = type(list) == "table" and list or {}
    local keep, info, has = {}, {}, {}
    for _, id in ipairs(list) do
        local name, parent = call(GetCategoryInfo, id)
        info[id] = { id = id, name = name or "", parent = parent, kids = {} }
        has[id] = shows(id, filtered)   -- read once per category
    end
    for _, id in ipairs(list) do
        if has[id] then
            local at = id
            while at and at ~= -1 and info[at] and not keep[at] do
                keep[at] = true
                at = info[at].parent
            end
        end
    end
    local roots = {}
    for _, id in ipairs(list) do
        if keep[id] then
            local c = info[id]
            c.has = has[id]
            local p = c.parent ~= -1 and info[c.parent] and keep[c.parent] and info[c.parent]
            if p then p.kids[#p.kids + 1] = c else roots[#roots + 1] = c end
        end
    end
    return roots
end

-- The category the game opens on for the player's class (LegacyChallengeDefaultCategories).
function Data.DefaultCategory()
    local _, token = UnitClass("player")
    return token and Data.Consts()["LEGACY_DEFAULT_CATEGORY_" .. token] or nil
end

function Data.CategoryOf(id)
    local cat = call(GetAchievementCategory, id)
    return type(cat) == "number" and cat or nil
end

-- A newly earned challenge not viewed yet (Blizzard_LegacyChallengeTracker, loaded with
-- the game, which saves it per character).
function Data.Unviewed(catID)
    local U = _G.LegacyChallengeViewedUtil
    return type(U) == "table" and call(U.CategoryHasUnviewedChallenges, catID) == true or false
end

function Data.MarkViewed(catID)
    local U = _G.LegacyChallengeViewedUtil
    if type(U) == "table" then call(U.MarkCategoryViewed, catID) end
end

-- How many; the game keeps them per character (LegacyChallengesUnviewed).
function Data.UnviewedCount()
    local t = _G.LegacyChallengesUnviewed
    local n = 0
    if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
    return n
end

-- A challenge's steps: { text, done, have, need (counted steps get a bar) }.
function Data.Steps(id)
    local out = {}
    local n = call(GetAchievementNumCriteria, id)
    local BAR = EVALUATION_TREE_FLAG_PROGRESS_BAR or 1
    for i = 1, type(n) == "number" and n or 0 do
        local text, _, done, have, need, _, flags = call(GetAchievementCriteriaInfo, id, i)
        local counted = type(flags) == "number" and type(need) == "number" and need > 0 and bit and bit.band(flags, BAR) == BAR
        out[#out + 1] = { text = text or "", done = done == true, have = counted and math.max(0, math.min(have or 0, need)) or nil, need = counted and need or nil }
    end
    return out
end

-- Tracking, same as the achievement window's checkbox (C_ContentTracking).
local function trackType()
    local E = Enum and Enum.ContentTrackingType
    return E and E.Achievement
end

function Data.Tracked(id)
    return call(api("C_ContentTracking", "IsTracking"), trackType(), id) == true
end

-- true when it worked; the game's own message when the list is full.
function Data.SetTracked(id, on)
    local CT = _G.C_ContentTracking
    if type(CT) ~= "table" then return false end
    if not on then
        local stop = Enum and Enum.ContentTrackingStopType and Enum.ContentTrackingStopType.Manual
        call(CT.StopTracking, trackType(), id, stop)
        return true
    end
    local ids = call(CT.GetTrackedIDs, trackType())
    local most = type(Constants) == "table" and type(Constants.ContentTrackingConsts) == "table" and Constants.ContentTrackingConsts.MaxTrackedAchievements
    if type(ids) == "table" and type(most) == "number" and #ids >= most then
        if UIErrorsFrame and ACHIEVEMENT_WATCH_TOO_MANY then UIErrorsFrame:AddMessage(string.format(ACHIEVEMENT_WATCH_TOO_MANY, most), 1, 0.1, 0.1, 1) end
        return false
    end
    local err = call(CT.StartTracking, trackType(), id)
    if err and type(ContentTrackingUtil) == "table" then call(ContentTrackingUtil.DisplayTrackingError, err) end
    return not err
end

-- Shift-click: link the challenge in chat.
function Data.Link(id, open)
    local link = call(GetAchievementLink, id)
    local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
    if not link then return end
    if insert and call(insert, link) then return end
    -- No chat line open (controllers have no shift-click): open one with it, like the game.
    local openChat = open and ((ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat)
    if openChat then call(openChat, link) end
end
