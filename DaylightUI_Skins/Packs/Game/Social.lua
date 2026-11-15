-- The game's own Social window, in the Daylight UI look, for players who pick it over
-- Daylight UI's (Win.Swap). Never walked while Daylight UI's window covers it.

local _, ns = ...
local Engine = ns.Engine

-- This client's friends window (Blizzard_SocialUI): one window with icon tabs down
-- the right side (pooled, made on open), a Battle.net bar on top, a page per tab
-- (friends, recent allies, quick join, requests, recruit a friend, raid), and side
-- windows (broadcast, ignore list, raid info). Friends are cards in a scrolling
-- list; they get the row look, and their invite button becomes an icon button.
local PAGES = { "FriendsList", "RecentAlliesList", "QuickJoinFrame", "FriendRequestsList",
                "RecruitAFriendFrame", "RaidFrame" }
local SIDES = { "BattleNetBroadcastFrame", "BattleNetUnavailableNoticeFrame", "IgnoreListFrame", "RaidInfoFrame" }

local function friendCard(card)
    if type(card) ~= "table" or type(card.TextHolder) ~= "table" or type(card.PresenceHolder) ~= "table" then return end
    local Kit = ns.Kit
    Kit.Row(card)
    Kit.IconButton(card.PartyButton)
end

local function covered()
    local S = DaylightUI.Social and DaylightUI.Social.Window
    return type(S) == "table" and type(S.Covers) == "function" and S.Covers() == true
end

Engine.Window({ key = "socialui", pack = "social", addon = "Blizzard_SocialUI", frame = "SocialUIFrame", watch = true,
    skip = covered,
    hide = { ".TopFade", ".BottomFade", ".BattleNetBar.Background" },
    auto = { skip = { ".BattleNetBar.ControlsContainer.BattleNetMenuButton" } },
    after = function(Kit, f)
        local pool = f.socialTabPool
        if type(pool) == "table" and pool.EnumerateActive then
            for tab in pool:EnumerateActive() do Kit.SideTab(tab, nil, nil, true) end
        end
        local controls = type(f.BattleNetBar) == "table" and f.BattleNetBar.ControlsContainer
        if type(controls) == "table" then
            Kit.Inset(controls)
            Kit.IconButton(controls.BattleNetMenuButton)
        end
        for _, key in ipairs(PAGES) do
            local page = f[key]
            if type(page) == "table" then
                Kit.Hide(page.TopDivider)
                Kit.Hide(page.BottomDivider)
                Kit.Button(page.ActionButton)
                Kit.EachRow(page.ScrollBox, friendCard, "socialcard")
            end
        end
        for _, key in ipairs(SIDES) do
            local side = f[key]
            if type(side) == "table" then
                Kit.Panel(side)
                Kit.Hide(side.Border)
                Kit.Hide(side.NineSlice)
            end
        end
    end })
