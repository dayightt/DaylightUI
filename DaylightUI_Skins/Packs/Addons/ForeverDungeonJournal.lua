-- Skins ForeverDungeonJournal: its journal, favorites and settings windows get
-- our window, buttons, tabs, lists, scroll bars, font and text colors. Each
-- dungeon's picture stays (home page cards, the dungeon page's backdrop art);
-- its per-dungeon tints and parchment go.
-- How (Core/Journal.lua): ForeverDungeonJournalFrame is created at PLAYER_LOGIN
-- as a BackdropTemplate window, and its panels and rows (boss, loot and quest
-- buttons, home cards, built by local helpers as you browse) are
-- BackdropTemplate frames too. Its local ApplyTheme / RefreshAll repaint them
-- (colors, font objects, parchment alpha) whenever you pick a dungeon, boss or
-- quest. Those are locals and can't be hooked, so every click in its windows
-- (and every page shown, and its exported refreshes) triggers a pass over
-- everything shown on the next frame: every backdrop hidden, every text our
-- font and ink. A step that fails on one frame only skips that frame, since its
-- frames change between versions.
-- It also repaints without a click, from its own events (item data arriving,
-- quest log updates). The quest page ends in the exported ApplyQuestDetailScroll,
-- so that page and its list are redone right there in the same frame and its
-- dark ink never shows. Other pages (loot, home cards) are redone two frames
-- later, since its quest refresh waits a frame itself.
-- The picked boss or quest is read from the addon (FDJ.GetSelectedDungeon, its
-- saved lastQuest), never from a color. Its Bosses / Quests / Map / Route
-- buttons are disabled while selected; they become our tabs, with the label it
-- draws itself (tab.text) in our ink. Its standard buttons, X, scroll bars,
-- checkboxes and input boxes are left to Kit.Auto.

local _, ns = ...
local DUI = DaylightUI
local Engine = ns.Engine
local Style = DUI.Style

local ADDON = "ForeverDungeonJournal"

Engine.AddonSwitch({ key = "fdj", addon = ADDON, label = "Dungeon Journal",
    desc = "The dungeon journal, its favorites and settings windows; each dungeon's picture kept." })

local function isTable(x) return type(x) == "table" end
local function kind(x) return isTable(x) and x.GetObjectType and x:GetObjectType() or nil end
local function forbidden(f) return isTable(f) and f.IsForbidden and f:IsForbidden() end

local FDJ = {}
ns.FDJ = FDJ
FDJ.shelled = setmetatable({}, { __mode = "k" }) -- frame -> true (our shell or row on it)
FDJ.clicks = setmetatable({}, { __mode = "k" }) -- button -> true (clicking it triggers a pass over the window)
FDJ.DEPTH = 14 -- how deep its windows go

-- Its tints and parchment over the panels, erased (it resets their alpha).
FDJ.ERASE = { "homeParchment", "contentParchment", "headerParchment", "leftParchment", "rightParchment",
    "questLeftParchment", "questRightParchment", "questParchment", "atmosphere", "mistTop" }
-- Its Bosses / Quests / Map / Route buttons become tabs, selected while disabled.
FDJ.TABS = { "bossesTab", "questsTab", "mapTab", "dungeonRouteButton" }
-- Titles (white) and section headings (tan), by the keys it uses.
FDJ.TITLES = { "mainTitle", "dungeonTitle", "selectedBossName", "selectedQuestName", "homeTitle",
    "routeTitle", "dungeonMapTitle" }
FDJ.HEADINGS = { "lootTitle", "bossListTitle", "questListTitle", "questObjectiveHeader", "questDescHeader",
    "questRequiredItemsHeader", "questProvidedItemHeader", "questStartsHeader", "questTurninHeader",
    "questNotesHeader", "questRewardHeader", "questAlsoReceiveHeader" }

-- A BackdropTemplate frame whose pieces exist (SetBackdrop has run).
local function backdropped(f)
    return kind(f.Center) == "Texture" and f.SetBackdrop ~= nil
end

-- A row it draws as its own box: a button wide enough to hold a line.
local function isRow(f)
    if kind(f) ~= "Button" then return false end
    local w = f:GetWidth()
    return type(w) == "number" and not (issecretvalue and issecretvalue(w)) and w >= 120
end

-- Whether this is its picked boss or quest, as the addon reports it.
local function picked(row)
    local api = _G.ForeverDungeonJournal_NS
    if type(row.index) == "number" and isTable(row.portrait) and isTable(api) and type(api.GetSelectedDungeon) == "function" then
        return select(2, api.GetSelectedDungeon()) == row.index
    end
    local db = _G.ForeverDungeonJournalDB
    if type(row.questIndex) == "number" and isTable(db) then return db.lastQuest == row.questIndex end
    return false
end

-- A button showing an item (loot row, reward): text keeps its quality color,
-- only dark parchment ink is lightened.
local function itemButton(f)
    return kind(f.icon) == "Texture" or kind(f.Icon) == "Texture"
end

local ink = {} -- font string -> its ink (titles, headings)

-- The gold it bakes into heading text, which SetTextColor can't override.
local function dropRuns(fs)
    local text = fs:GetText()
    if type(text) ~= "string" or not string.find(text, "|c", 1, true) then return end
    text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    fs:SetText((string.gsub(text, "|r", "")))
end

-- A finished objective in its muted parchment brown becomes our dim ink.
FDJ.DONE_RUN = "|cff6e5c40"
local function dimDone(fs)
    local text = fs:GetText()
    if type(text) ~= "string" or not string.find(text, FDJ.DONE_RUN, 1, true) then return end
    fs:SetText((string.gsub(text, FDJ.DONE_RUN, DUI.Win.Parts.Hex(Style.INK.OFF))))
end

-- One frame: backdrop hidden, our shell (once), its texts ours.
local function dress(Kit, f, depth, again)
    if backdropped(f) then
        Kit.Backdrop(f)
        if not FDJ.shelled[f] then
            FDJ.shelled[f] = true
            if isRow(f) then
                Kit.Row(f, "art", picked)
            elseif kind(f) == "Button" then
                Kit.Shell(f, "control")
            elseif depth > 0 then
                Kit.Shell(f, "row", { noBackground = true })
            end
        end
    end
    -- A click can make it fill or repaint anything, so do another pass.
    if (kind(f) == "Button" or kind(f) == "CheckButton") and not FDJ.clicks[f] then
        FDJ.clicks[f] = true
        f:HookScript("OnClick", function()
            Kit.RepaintSoon()
            C_Timer.After(0, again)
        end)
    end
    local keep = itemButton(f)
    -- Our tabs and buttons paint their own labels (picked, hover, disabled).
    local own = Kit.TabOf(f) or Kit.ButtonOf(f)
    for _, r in ipairs({ f:GetRegions() }) do
        if kind(r) == "FontString" then
            Kit.Refont(r)
            if own and not ink[r] then
                -- they paint it themselves
            elseif keep then
                -- keep quality colors, drop the dark ink
            elseif ink[r] == "pop" then
                Style.InkText(r, "pop")
            else
                if ink[r] then dropRuns(r) end
                Kit.Light(r, ink[r] or Style.INK.TEXT)
                dimDone(r)
            end
        end
    end
    if keep then Kit.InkGameText(f) end
end

local function walk(Kit, f, depth, shownOnly, again)
    if not isTable(f) or not f.GetChildren or depth > FDJ.DEPTH or forbidden(f) then return end
    if shownOnly and f.IsShown and not f:IsShown() then return end
    local ok, err = pcall(dress, Kit, f, depth, again)
    if not ok and C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("DaylightUI_Dev") then
        geterrorhandler()(err)
    end
    for _, c in ipairs({ f:GetChildren() }) do walk(Kit, c, depth + 1, shownOnly, again) end
end

local function tabPicked(tab) return tab.IsEnabled and not tab:IsEnabled() end

-- Titles and headings by key (some are created the first time a quest needs one).
local function inkTexts(f)
    for _, key in ipairs(FDJ.TITLES) do
        if kind(f[key]) == "FontString" then ink[f[key]] = Style.INK.VALUE end
    end
    for _, key in ipairs(FDJ.HEADINGS) do
        if kind(f[key]) == "FontString" then ink[f[key]] = Style.INK.LABEL end
    end
end

local function journal(Kit, f, shownOnly, again)
    for _, key in ipairs(FDJ.ERASE) do Kit.Erase(f[key]) end
    for _, edge in ipairs(isTable(f.questInsetEdges) and f.questInsetEdges or {}) do Kit.Erase(edge) end
    inkTexts(f)
    for _, key in ipairs(FDJ.TABS) do
        local tab = f[key]
        if isTable(tab) then
            Kit.Tab(tab, tabPicked)
            if kind(tab.text) == "FontString" then ink[tab.text] = tabPicked(tab) and "pop" or Style.INK.LABEL end
        end
    end
    if kind(f.mainTitle) == "FontString" then Kit.Font(f.mainTitle, Style.SIZE.title) end
    -- Its search box is a custom one.
    if kind(f.searchEditBox) == "EditBox" then
        Kit.Backdrop(f.searchEditBox)
        FDJ.shelled[f.searchEditBox] = true
        Kit.EditBox(f.searchEditBox)
    end
    walk(Kit, f, 0, shownOnly, again)
end

-- The first pass covers the whole window; later ones only what's shown.
FDJ.seen = setmetatable({}, { __mode = "k" })
local function shownOnly(f)
    local before = FDJ.seen[f] == true
    FDJ.seen[f] = true
    return before
end

local journalDef = { key = "fdj", pack = "addons", addon = ADDON, switch = "fdj", label = "Dungeon Journal",
    thirdParty = true, frame = "ForeverDungeonJournalFrame", watch = true,
    auto = { skip = { ".bossesTab", ".questsTab", ".mapTab", ".dungeonRouteButton" } } }
local function journalAgain() if journalDef.again then journalDef.again() end end

-- Its quest page just redrew: redo that page and its list right now. Only text
-- and rows are touched, so it's safe in combat too.
function FDJ.QuestPage(Kit, f)
    inkTexts(f)
    walk(Kit, f.questTextInset, 1, true, journalAgain)
    walk(Kit, f.questListScroll, 1, true, journalAgain)
end

-- It repainted from one of its own events, so do a pass once its refresh is done.
function FDJ.Later()
    local f = _G.ForeverDungeonJournalFrame
    if FDJ.waiting or not isTable(f) or not f:IsShown() then return end
    FDJ.waiting = true
    C_Timer.After(0, function()
        C_Timer.After(0, function()
            FDJ.waiting = false
            journalAgain()
        end)
    end)
end
journalDef.after = function(Kit, f)
    journal(Kit, f, shownOnly(f), journalAgain)
    -- What it fills through its exported refreshes (home cards, loot list)
    -- gets another pass.
    local api = _G.ForeverDungeonJournal_NS
    if not FDJ.hooked and isTable(api) then
        FDJ.hooked = true
        for _, name in ipairs({ "RefreshHomeCards", "RefreshLootNow", "RefreshLootFilterResults" }) do
            if type(api[name]) == "function" then
                hooksecurefunc(api, name, Engine.Safe(journalDef, function() C_Timer.After(0, journalAgain) end))
            end
        end
        -- Windows it creates the first time they open.
        for _, name in ipairs({ "ToggleSettingsPanel", "ToggleFavouritesWindow" }) do
            if type(api[name]) == "function" then
                hooksecurefunc(api, name, Engine.Safe(journalDef, function() FDJ.Others() end))
            end
        end
        for _, name in ipairs({ "ApplyQuestDetailScroll" }) do
            if type(api[name]) == "function" then
                hooksecurefunc(api, name, Engine.Safe(journalDef, function() FDJ.QuestPage(Kit, f) end))
            end
        end
        for _, name in ipairs({ "ScheduleQuestRefresh" }) do
            if type(api[name]) == "function" then
                hooksecurefunc(api, name, Engine.Safe(journalDef, FDJ.Later))
            end
        end
        DUI.RegisterEvent("GET_ITEM_INFO_RECEIVED", Engine.Safe(journalDef, FDJ.Later))
    end
end
Engine.Window(journalDef)

FDJ.others = {}
for _, spec in ipairs({ { "fdjSettings", "ForeverDungeonJournalSettings" }, { "fdjFavourites", "ForeverDungeonJournalFavourites" } }) do
    local def = { key = spec[1], pack = "addons", addon = ADDON, switch = "fdj", label = "Dungeon Journal",
        thirdParty = true, frame = spec[2], watch = true }
    local function again() if def.again then def.again() end end
    def.after = function(Kit, f) walk(Kit, f, 0, shownOnly(f), again) end
    FDJ.others[#FDJ.others + 1] = { frame = spec[2], reg = Engine.Window(def) }
end

-- A window it just created: dress it now (the skin was waiting for it).
function FDJ.Others()
    for _, o in ipairs(FDJ.others) do
        if not o.reg.done and _G[o.frame] then Engine.Try(o.reg) end
    end
end
