-- Social pack: friends, guild and communities, calendar, mail, trade, the guild
-- bank and the group finder. Each is Engine.Window plus anything unique to it.

local _, ns = ...
local DUI = DaylightUI
local Engine = ns.Engine


Engine.Window({ key = "friends", pack = "social", frame = "FriendsFrame", watch = true })

-- This client's rebuilt friends window (Blizzard_SocialUI): one window with icon
-- tabs down the right side (pooled, created on open), a Battle.net bar on top,
-- Lua-built pages per tab (friends, recent allies, quick join, requests,
-- recruit a friend, raid), and side windows (broadcast, ignore list, raid info).
-- Friends are cards in a scrolling list; they get our rows, and their invite
-- button becomes one of our icon buttons.
local SOCIAL_PAGES = { "FriendsList", "RecentAlliesList", "QuickJoinFrame", "FriendRequestsList",
                       "RecruitAFriendFrame", "RaidFrame" }
local SOCIAL_SIDES = { "BattleNetBroadcastFrame", "BattleNetUnavailableNoticeFrame", "IgnoreListFrame", "RaidInfoFrame" }

local function friendCard(card)
    if type(card) ~= "table" or type(card.TextHolder) ~= "table" or type(card.PresenceHolder) ~= "table" then return end
    local Kit = ns.Kit
    Kit.Row(card)
    Kit.IconButton(card.PartyButton)
end

Engine.Window({ key = "socialui", pack = "social", addon = "Blizzard_SocialUI", frame = "SocialUIFrame", watch = true,
    skip = function() return DaylightUI.socialOwnWindow == true end, -- the Daylight UI social window shows instead
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
        for _, key in ipairs(SOCIAL_PAGES) do
            local page = f[key]
            if type(page) == "table" then
                Kit.Hide(page.TopDivider)
                Kit.Hide(page.BottomDivider)
                Kit.Button(page.ActionButton)
                Kit.EachRow(page.ScrollBox, friendCard, "socialcard")
            end
        end
        for _, key in ipairs(SOCIAL_SIDES) do
            local side = f[key]
            if type(side) == "table" then
                Kit.Panel(side)
                Kit.Hide(side.Border)
                Kit.Hide(side.NineSlice)
            end
        end
    end })
-- The guild window (Blizzard_Communities, the game's layout kept): guild and
-- community cards down the left, icon tabs down the right (chat, roster,
-- benefits, info), the roster list, guild info and news, perks and rewards, and
-- the member card beside the roster. Parchment, marble and filigree go, panels
-- become insets on our window, and every list entry gets our rows.
local function stripAll(Kit, parent, keys)
    if type(parent) ~= "table" then return end
    for _, key in ipairs(keys) do Kit.Strip(parent[key]) end
end

-- What a card keeps: guild banner or community icon, and its invitation,
-- unread and favorite marks. The icon ring, blue card art and new-card flash go.
local CLUB_KEEP = { "Icon", "GuildTabardBackground", "GuildTabardEmblem", "GuildTabardBorder",
                    "InvitationIcon", "UnreadNotificationIcon", "FavoriteIcon" }
local clubHooked = setmetatable({}, { __mode = "k" })

local function clubCard(card)
    if type(card) ~= "table" or not card.CreateTexture or type(card.Selection) ~= "table" then return end
    local Kit = ns.Kit
    local keep = {}
    for _, key in ipairs(CLUB_KEEP) do
        if Kit.Kind(card[key]) == "Texture" then keep[card[key]] = true end
    end
    Kit.Row(card, keep, card.Selection, false)
    Kit.Hide(card.IconRing)
    Kit.Erase(card.NewCommunityFlash)
    -- The game selects the card after the click, so repaint then.
    if not clubHooked[card] then
        clubHooked[card] = true
        card:HookScript("OnMouseUp", Kit.RepaintSoon)
    end
end

-- A roster row keeps its class icon and voice mark (presence and rank icons are
-- in its NameFrame, untouched). The profession view's header is a row of its
-- own with its +/- kept.
local function memberRow(row)
    if type(row) ~= "table" or not row.CreateTexture or type(row.NameFrame) ~= "table" then return end
    local Kit = ns.Kit
    local keep = {}
    for _, key in ipairs({ "Class", "VoiceChatStatusIcon" }) do
        if Kit.Kind(row[key]) == "Texture" then keep[row[key]] = true end
    end
    Kit.Row(row, keep, nil, false)
    if type(row.ProfessionHeader) == "table" then Kit.Row(row.ProfessionHeader, "art", nil, false) end
end

-- News, perks and rewards: one row each, keeping the icon (plus a reward's lock
-- and coins). A perk's two borders (normal and unusable) go.
local function iconRow(row)
    if type(row) ~= "table" or not row.CreateTexture then return end
    local Kit = ns.Kit
    local keep = {}
    for _, key in ipairs({ "icon", "Icon", "Lock" }) do
        if Kit.Kind(row[key]) == "Texture" then keep[row[key]] = true end
    end
    Kit.Row(row, keep, nil, false)
    Kit.Strip(row.NormalBorder)
    Kit.Strip(row.DisabledBorder)
end

Engine.Window({ key = "communities", pack = "social", addon = "Blizzard_Communities", frame = "CommunitiesFrame", watch = true,
    auto = { lines = true, skip = { ".MaximizeMinimizeFrame" } },
    after = function(Kit, f)
        -- These tabs sit against the window's right edge, so each wears the
        -- whole tab look joined to the window. An outline around the icon alone
        -- floated off it, as it did on the friends window.
        for _, key in ipairs({ "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab", "GuildPreferredPlaySettingsTab" }) do
            Kit.SideTab(f[key], nil, Kit.SIDE_TAB_CROP, true)
        end
        -- The round portrait (club avatar or guild tabard) is on its own frame,
        -- PortraitOverlay, so the window strip misses it. It has to go like
        -- every portrait or the left-aligned title runs over it. Erased, not
        -- faded: for a guild with no tabard the game repaints the "no logo"
        -- emblem with SetVertexColor(1, 1, 1, 1) on each UpdatePortrait, and a
        -- texture's vertex alpha is its alpha.
        local overlay = f.PortraitOverlay
        if type(overlay) == "table" then
            for _, key in ipairs({ "Portrait", "TabardBackground", "TabardEmblem", "TabardBorder" }) do
                Kit.Erase(overlay[key])
            end
        end
        -- Maximize/minimize as bare chevrons next to the X, like the world map.
        -- The walk's boxed button stuck up over the window's top edge.
        local mm = f.MaximizeMinimizeFrame
        if type(mm) == "table" then
            Kit.BareButton(mm.MinimizeButton, "down")
            Kit.BareButton(mm.MaximizeButton, "up")
        end
        local list = f.CommunitiesList
        if type(list) == "table" then
            Kit.Strip(list)
            Kit.Strip(list.FilligreeOverlay)
            Kit.Inset(list.InsetFrame)
            Kit.EachRow(list.ScrollBox, clubCard, "clubcard")
        end
        local members = f.MemberList
        if type(members) == "table" then
            Kit.Strip(members)
            Kit.Strip(members.ColumnDisplay)
            Kit.Inset(members.InsetFrame)
            Kit.EachRow(members.ScrollBox, memberRow, "member")
        end
        if type(f.Chat) == "table" then
            Kit.Strip(f.Chat)
            Kit.Inset(f.Chat.InsetFrame)
        end
        local details = f.GuildDetailsFrame
        if type(details) == "table" then
            Kit.Strip(details)
            Kit.Inset(details.Info)
            Kit.Inset(details.News)
            if type(details.Info) == "table" then
                -- A challenge's tick stays.
                for _, c in ipairs(details.Info.Challenges or {}) do
                    if type(c) == "table" then
                        Kit.Strip(c, Kit.Kind(c.check) == "Texture" and { [c.check] = true } or nil)
                    end
                end
            end
            if type(details.News) == "table" then Kit.EachRow(details.News.ScrollBox, iconRow, "news") end
        end
        local benefits = f.GuildBenefitsFrame
        if type(benefits) == "table" then
            Kit.Strip(benefits)
            stripAll(Kit, benefits, { "Perks", "Rewards" })
            for _, key in ipairs({ "Perks", "Rewards" }) do
                local page = benefits[key]
                if type(page) == "table" then Kit.EachRow(page.ScrollBox, iconRow, key) end
            end
            -- Guild reputation: the game's fill on our bar look.
            local faction = benefits.FactionFrame
            local bar = type(faction) == "table" and faction.Bar
            if type(bar) == "table" and Kit.Kind(bar.Progress) == "Texture" then
                Kit.Strip(bar, { [bar.Progress] = true })
                Kit.Shell(bar, "bar")
            end
        end
        -- The member card beside the roster: our panel, with the notes as insets.
        local card = f.GuildMemberDetailFrame
        if type(card) == "table" then
            Kit.Panel(card)
            Kit.Hide(card.Border)
            Kit.Inset(card.NoteBackground)
            Kit.Inset(card.OfficerNoteBackground)
        end
    end })

-- The guild's side windows: guild log, editing the message of the day or info
-- text, and news filters.
for _, name in ipairs({ "CommunitiesGuildLogFrame", "CommunitiesGuildTextEditFrame", "CommunitiesGuildNewsFiltersFrame" }) do
    Engine.Window({ key = string.lower(name), pack = "social", addon = "Blizzard_Communities", frame = name,
        after = function(Kit, f) Kit.Inset(f.Container) end })
end
Engine.Window({ key = "calendar", pack = "social", addon = "Blizzard_Calendar", frame = "CalendarFrame", watch = true })

-- Mail: inbox and send (one window, two tabs), plus an opened letter, whose
-- text is printed for parchment.
Engine.Window({ key = "mail", pack = "social", frame = "MailFrame", watch = true,
    skip = function() return DaylightUI.mailOwnWindow == true or DaylightUI.mailMogul == true end })
-- Opening another letter while one is open refills and recolors it without
-- re-showing the window, so relight after.
local letterHooked = false
Engine.Window({ key = "openmail", pack = "social", frame = "OpenMailFrame", light = true,
    skip = function() return DaylightUI.mailOwnWindow == true or DaylightUI.mailMogul == true end,
    after = function(Kit, f)
        if letterHooked or type(InboxFrame_OnClick) ~= "function" then return end
        letterHooked = true
        hooksecurefunc("InboxFrame_OnClick", function() Kit.LightAll(f, nil, 8, true) end)
    end })

-- Trade: both sides' items and money, and the Trade/Cancel buttons. Kit.Auto
-- finds most of it. Money frames are the one thing it deliberately skips (it
-- never descends into one, so the game's coin buttons stay as they are), same
-- as on the merchant.
local function tradeItems(Kit, prefix)
    for i = 1, 7 do
        local btn = _G[prefix .. i]
        if btn then Kit.Item(btn) end
    end
end

Engine.Window({ key = "trade", pack = "social", frame = "TradeFrame",
    after = function(Kit, f)
        tradeItems(Kit, "TradePlayerItem")
        tradeItems(Kit, "TradeRecipientItem")
        for _, name in ipairs({ "TradePlayerInputMoneyFrame", "TradeRecipientMoneyFrame" }) do
            local mf = _G[name]
            if type(mf) == "table" then
                Kit.Strip(mf)
                Kit.Inset(mf)
            end
        end
        Kit.Button(f.TradeButton or _G.TradeFrameTradeButton)
        Kit.Button(f.CancelButton or _G.TradeFrameCancelButton)
        -- The other player's round portrait and gold ring are on their own
        -- frame (RecipientOverlay, level 550, above the names), so the window
        -- strip misses them. Erased like every skinned window's portrait.
        local overlay = f.RecipientOverlay
        if type(overlay) == "table" then
            Kit.Erase(overlay.portrait)
            Kit.Erase(overlay.portraitFrame)
        end
        -- The two names sit in fixed boxes (TradeFrame.xml: yours 100 wide at
        -- x 65, theirs 80 at x 230), too narrow for a first and last name in our
        -- font. Each gets its half of the title row instead: yours from the left
        -- edge to the middle, theirs from TradeRecipientBG (-172) to the X. A
        -- very long name may still wrap to a second line.
        local mine, theirs = _G.TradeFramePlayerNameText, _G.TradeFrameRecipientNameText
        if mine and theirs then
            mine:ClearAllPoints()
            mine:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -5)
            mine:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -184, -33)
            theirs:ClearAllPoints()
            theirs:SetPoint("TOPLEFT", f, "TOPRIGHT", -166, -5)
            theirs:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -30, -33)
            for _, fs in ipairs({ mine, theirs }) do
                fs:SetWordWrap(true)
                fs:SetMaxLines(2)
                fs:SetJustifyV("TOP")
            end
        end
    end })

-- Guild bank: the item slots and GuildItemSearchBox (a child of the frame but
-- not a keyed part) already get our look from the generic pass. The game's own
-- search marks matching slots too (SetMatchesSearch from GetGuildBankItemInfo's
-- isFiltered) and flags tabs with a match. On top of that, slots that don't
-- match are dimmed to 0.3 alpha, in case the skin hides the game's overlay
-- (not yet confirmed in game). Slots are Column1..7 / Button1..14, each with a
-- fixed ID 1-98 passed straight to GetGuildBankItemInfo.
local bankItems = setmetatable({}, { __mode = "k" }) -- bank window -> its 98 slots
local bankDimmed = setmetatable({}, { __mode = "k" }) -- bank window -> true if we've dimmed any
local function guildBankItems(f)
    if bankItems[f] then return bankItems[f] end
    local out = {}
    for c = 1, 7 do
        local col = f["Column" .. c]
        for b = 1, 14 do
            local btn = col and col["Button" .. b]
            if btn then out[#out + 1] = btn end
        end
    end
    if #out > 0 then bankItems[f] = out end
    return out
end

local function guildBankFilter(f)
    local box = _G.GuildItemSearchBox
    local text = box and box.GetText and box:GetText()
    local term = type(text) == "string" and text ~= "" and string.lower(text) or nil
    -- Nothing typed and nothing dimmed: skip the pass.
    if not term and not bankDimmed[f] then return end
    bankDimmed[f] = term ~= nil
    local tab = GetCurrentGuildBankTab and GetCurrentGuildBankTab()
    for _, btn in ipairs(guildBankItems(f)) do
        local show = true
        if term then
            local ok, link
            if tab then ok, link = pcall(GetGuildBankItemLink, tab, btn:GetID()) end
            local name = ok and type(link) == "string" and string.match(link, "%[(.-)%]")
            show = type(name) == "string" and string.find(string.lower(name), term, 1, true) ~= nil
        end
        btn:SetAlpha(show and 1 or 0.3)
    end
end

local guildBankHooked = false
local searchHooked = setmetatable({}, { __mode = "k" })

Engine.Window({ key = "guildbank", pack = "social", addon = "Blizzard_GuildBankUI", frame = "GuildBankFrame", watch = true,
    after = function(_, f)
        local box = _G.GuildItemSearchBox
        if type(box) == "table" and box.HookScript and not searchHooked[box] then
            searchHooked[box] = true
            box:HookScript("OnTextChanged", function() guildBankFilter(f) end)
        end
        if not guildBankHooked then
            guildBankHooked = true
            DUI.RegisterEvent("GUILDBANKBAGSLOTS_CHANGED", function() if f:IsShown() then guildBankFilter(f) end end)
        end
        guildBankFilter(f)
    end })

-- This client's group finder: one window with three pages drawn over it, each a
-- framed window of its own (list yourself, browse groups, who's around). The
-- pages' frames go so they sit on ours. Category buttons keep their pictures,
-- on our row outline.
local function groupFinderPage(Kit, page)
    if type(page) ~= "table" or not page.GetRegions then return end
    Kit.Strip(page)
    Kit.Hide(page.NineSlice)
    Kit.Strip(page.PortraitContainer)
    Kit.Inset(page.Inset)
    Kit.Strip(page.RolesSection)
    Kit.Strip(page.DividerFrame)
    -- Backgrounds the game re-sets as you pick a category: kept hidden.
    if type(page.Inset) == "table" then Kit.Erase(page.Inset.CustomBG) end
    Kit.Erase(page.Bg)
    Kit.Erase(page.BackgroundArt)
    -- Each page has its own title (the page covers the window), placed in the
    -- title row like every window's.
    local title = type(page.TitleContainer) == "table" and page.TitleContainer.TitleText
    Kit.Font(title, DUI.Style.SIZE.title)
    Kit.Light(title)
    Kit.Title(page, title)
end

local function categoryButton(Kit, b)
    if type(b) ~= "table" or not b.CreateTexture then return end
    Kit.Hide(b.Cover)
    local keep = {}
    if Kit.Kind(b.Icon) == "Texture" then keep[b.Icon] = true end
    Kit.Row(b, keep)
    Kit.Font(b.Label)
end

-- The Daylight UI group finder replaces it while that's on.
Engine.Window({ key = "groupfinder", pack = "social", frame = "LFGParentFrame", watch = true,
    skip = function() return DaylightUI.lfgOwnWindow == true end,
    after = function(Kit, f)
        for _, key in ipairs({ "ListingTab", "BrowsingTab", "WhoListingTab" }) do
            Kit.SideTab(f[key], nil, Kit.SIDE_TAB_CROP)
        end
        for _, name in ipairs({ "LFGListingFrame", "LFGBrowseFrame", "LFGWhoListFrame" }) do
            groupFinderPage(Kit, _G[name])
        end
        local listing = _G.LFGListingFrame
        local view = type(listing) == "table" and listing.CategoryView
        local selection = type(view) == "table" and view.CategorySelection
        if type(selection) == "table" and type(selection.CategoryButtons) == "table" then
            for _, b in ipairs(selection.CategoryButtons) do categoryButton(Kit, b) end
        end
    end })
