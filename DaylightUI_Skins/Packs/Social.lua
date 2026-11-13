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
-- The "join or create" entry is a card too, painted green by the game after
-- the row is dressed. These are the only icons it uses for that entry.
local ADD_ICON = { ["communities-icon-addgroupplus"] = true, ["communities-icon-searchmagnifyingglass"] = true }

local function calmEntry(card)
    if type(card) ~= "table" then return end
    local Kit = ns.Kit
    local icon = card.Icon
    if Kit.Kind(icon) == "Texture" and icon.GetAtlas and ADD_ICON[icon:GetAtlas()] then
        if icon.SetDesaturated then icon:SetDesaturated(true) end
        local c = DUI.Style.INK.TEXT
        icon:SetVertexColor(c[1], c[2], c[3])
    end
    if Kit.Kind(card.Name) == "FontString" then
        Kit.Font(card.Name, DUI.Style.SIZE.body)
        Kit.Light(card.Name, DUI.Style.INK.TEXT)
    end
    if Kit.Kind(card.Background) == "Texture" then card.Background:SetAlpha(0) end
end

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
    calmEntry(card)
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

-- Header icon, same place as Win.Header's portrait. The list used to start
-- under the old title (y -23); it moves down so the icon isn't on the first card.
-- Frames hung off the list's top keep the spot they had.
local CLUB_ICON = DUI.Win.PORTRAIT
local CLUB_ICON_Y = -8
local LIST_TOP = CLUB_ICON_Y - CLUB_ICON - 6
local LIST_WAS = -23
local listHeld = setmetatable({}, { __mode = "k" })
local tipped = setmetatable({}, { __mode = "k" })
local finderHooked = setmetatable({}, { __mode = "k" })
local subs = setmetatable({}, { __mode = "k" })
local addHooked = false
local joinHooked = false
local listWide = setmetatable({}, { __mode = "k" })
local joinBtns = setmetatable({}, { __mode = "k" })
local subHooked = false
local placeSubtitle
local hookAddFlow

local rims = setmetatable({}, { __mode = "k" })

local function cropClubIcon(tex)
    if type(tex) ~= "table" or not tex.SetTexCoord then return end
    -- KeepCrop holds the crop when the game sets the texture again.
    ns.Kit.KeepCrop(tex, DUI.Style.ICON_CROP[1])
end

-- The spells window's portrait: the icon cropped out of its square border,
-- circled, and ringed with the same rim.
local function rimClubIcon(overlay, portrait)
    local rim = rims[overlay]
    if not rim and overlay.CreateTexture then
        rim = overlay:CreateTexture(nil, "OVERLAY")
        rim:SetTexture(DUI.MEDIA .. "portrait-rim.png")
        rims[overlay] = rim
    end
    if not rim then return end
    rim:ClearAllPoints()
    rim:SetPoint("TOPLEFT", portrait, "TOPLEFT", -3, 3)
    rim:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 3, -3)
    local band = DUI.Style.BAND
    rim:SetVertexColor(band[1], band[2], band[3], 1)
end

local function placeClubIcon(frame)
    local overlay = frame.PortraitOverlay
    local portrait = type(overlay) == "table" and overlay.Portrait
    if type(overlay) == "table" then
        overlay:Show()
        if type(portrait) == "table" then
            portrait:ClearAllPoints()
            portrait:SetSize(CLUB_ICON, CLUB_ICON)
            portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", DUI.Win.EDGE, CLUB_ICON_Y)
            cropClubIcon(portrait)
            local mask = overlay.CircleMask
            if type(mask) == "table" and mask.SetAllPoints then
                mask:ClearAllPoints()
                mask:SetAllPoints(portrait)
            end
            rimClubIcon(overlay, portrait)
        end
        for _, key in ipairs({ "TabardBackground", "TabardEmblem", "TabardBorder" }) do
            local tex = overlay[key]
            if type(tex) == "table" and tex.ClearAllPoints then
                tex:ClearAllPoints()
                tex:SetSize(CLUB_ICON, CLUB_ICON)
                tex:SetPoint("CENTER", type(portrait) == "table" and portrait or frame, "CENTER")
            end
        end
    end
    local title = type(frame.TitleContainer) == "table" and frame.TitleContainer.TitleText
    if type(title) == "table" and title.SetPoint then
        title:SetPoint("TOPLEFT", frame, "TOPLEFT", DUI.Win.EDGE + CLUB_ICON + 12, DUI.Win.TITLE_Y)
        placeSubtitle(frame, title)
    end
    local list = frame.CommunitiesList
    if type(list) ~= "table" or not list.SetPoint then return end
    local x = -1
    local point, _, _, px = list:GetPoint(1)
    if point == "TOPLEFT" and type(px) == "number" then x = px end
    list:SetPoint("TOPLEFT", frame, "TOPLEFT", x, LIST_TOP)
    local shift = LIST_TOP - LIST_WAS
    for _, key in ipairs({ "GuildFinderFrame", "CommunityFinderFrame", "ApplicantList", "Chat",
                           "InvitationFrame", "ClubFinderInvitationFrame" }) do
        local child = frame[key]
        if type(child) == "table" and child.GetNumPoints then
            for i = 1, child:GetNumPoints() do
                local p, rel, rp, cx, cy = child:GetPoint(i)
                if rel == list and p == "TOPLEFT" and type(cy) == "number" then
                    if listHeld[child] == nil then listHeld[child] = cy end
                    child:SetPoint(p, rel, rp, cx, listHeld[child] - shift)
                end
            end
        end
    end
end

-- The spellbook's second line. Here it is the community on screen, else the
-- guild, else the game's own "not in a guild".
local function clubLine(frame)
    local id
    if type(frame.GetSelectedClubId) == "function" then
        local ok, v = pcall(frame.GetSelectedClubId, frame)
        if ok then id = v end
    end
    if id and type(C_Club) == "table" and type(C_Club.GetClubInfo) == "function" then
        local ok, info = pcall(C_Club.GetClubInfo, id)
        if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
            return info.name
        end
    end
    if type(IsInGuild) == "function" and IsInGuild() and type(GetGuildInfo) == "function" then
        local ok, name = pcall(GetGuildInfo, "player")
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    local none = _G.ERR_GUILD_PLAYER_NOT_IN_GUILD
    if type(none) == "string" and none ~= "" then return none end
end

function placeSubtitle(frame, title)
    local Kit = ns.Kit
    if not Kit or type(frame.CreateFontString) ~= "function" then return end
    local sub = subs[frame]
    if not sub then
        sub = frame:CreateFontString(nil, "OVERLAY")
        subs[frame] = sub
    end
    Kit.Font(sub, DUI.Style.SIZE.small)
    Kit.Light(sub, DUI.Style.INK.LABEL)
    sub:ClearAllPoints()
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    local close = frame.CloseButton
    if type(close) == "table" then
        sub:SetPoint("RIGHT", close, "LEFT", -12, 0)
    else
        sub:SetPoint("RIGHT", frame, "RIGHT", -80, 0)
    end
    sub:SetJustifyH("LEFT")
    if sub.SetWordWrap then sub:SetWordWrap(false) end
    local line = clubLine(frame)
    if type(line) == "string" then sub:SetText(line); if sub.Show then sub:Show() end
    elseif sub.Hide then sub:Hide() end
end

-- The down chevron is minimize. On the finder page the game disables it,
-- because there is no chat view to shrink to, and a bare chevron still looks
-- clickable. Dim it while it is off.
local function paintChevron(btn, c)
    if type(c) ~= "table" or not c.SetVertexColor then return end
    local on = type(btn.IsEnabled) ~= "function" or btn:IsEnabled()
    local ink = on and DUI.Style.INK.LABEL or DUI.Style.INK.OFF
    c:SetVertexColor(ink[1], ink[2], ink[3], on and 1 or 0.45)
end

local function watchChevron(btn, c)
    if type(btn) ~= "table" or not btn.HookScript or tipped["chev" .. tostring(btn)] then return end
    tipped["chev" .. tostring(btn)] = true
    local function paint() paintChevron(btn, c) end
    btn:HookScript("OnEnable", paint)
    btn:HookScript("OnDisable", paint)
    btn:HookScript("OnShow", paint)
    btn:HookScript("OnEnter", paint)
    btn:HookScript("OnLeave", paint)
    paint()
end

local function levelHeaderButtons(frame, mm)
    local close = frame.CloseButton
    if type(close) ~= "table" or not mm.SetPoint then return end
    -- Same spot and size as the spells window's close, not the game's corner button.
    local size = DUI.Widgets and DUI.Widgets.CLOSE or 24
    close:SetSize(size, size)
    close:ClearAllPoints()
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", DUI.Win.CLOSE_X, DUI.Win.CloseY(false))
    mm:ClearAllPoints()
    mm:SetSize(size, size)
    mm:SetPoint("RIGHT", close, "LEFT", -DUI.Win.HEADER_ICON_GAP, 0)
    for _, key in ipairs({ "MinimizeButton", "MaximizeButton" }) do
        local btn = mm[key]
        if type(btn) == "table" and btn.SetAllPoints then
            btn:ClearAllPoints()
            btn:SetAllPoints(mm)
            if not tipped[btn] and btn.HookScript then
                tipped[btn] = true
                btn:HookScript("OnClick", function() placeClubIcon(frame) end)
            end
        end
    end
end

local function tipButton(btn, text)
    if type(btn) ~= "table" or type(text) ~= "string" or tipped["tip" .. tostring(btn)] or not btn.HookScript then return end
    tipped["tip" .. tostring(btn)] = true
    btn:HookScript("OnEnter", function(self)
        if self.IsEnabled and not self:IsEnabled() then return end
        local tip = _G.GameTooltip
        if type(tip) ~= "table" or not tip.SetOwner then return end
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:SetText(text)
        if tip.Show then tip:Show() end
    end)
    btn:HookScript("OnLeave", function()
        local tip = _G.GameTooltip
        if type(tip) == "table" and tip.Hide then tip:Hide() end
    end)
end

local function lightFinderText(Kit, disabled)
    if type(disabled) ~= "table" then return end
    Kit.Font(disabled.Title, DUI.Style.SIZE.title)
    Kit.Light(disabled.Title, DUI.Style.INK.TITLE)
    Kit.Font(disabled.Description, DUI.Style.SIZE.body)
    Kit.Light(disabled.Description, DUI.Style.INK.TEXT)
end

-- No clubs yet: the join row is the only thing in the left column, and its
-- label wraps into three short lines. The column closes and the action sits
-- under the guild text, as one button.
local function loneJoin(list)
    local box = type(list) == "table" and list.ScrollBox
    local provider = type(box) == "table" and box.GetDataProvider and box:GetDataProvider()
    if type(provider) == "table" and type(provider.GetSize) == "function" then
        local ok, n = pcall(provider.GetSize, provider)
        if ok and type(n) == "number" then return n <= 1 end
    end
    if type(C_Club) ~= "table" or type(C_Club.GetSubscribedClubs) ~= "function" then return false end
    local ok, clubs = pcall(C_Club.GetSubscribedClubs)
    if not ok or type(clubs) ~= "table" or #clubs > 0 then return false end
    if type(IsInGuild) == "function" and IsInGuild() then return false end
    return true
end

local function setListColumn(list, open)
    for i = 1, list.GetNumPoints and list:GetNumPoints() or 0 do
        local p, rel, rp, x, y = list:GetPoint(i)
        if p == "BOTTOMRIGHT" and type(x) == "number" then
            if listWide[list] == nil then listWide[list] = x end
            list:SetPoint(p, rel, rp, open and listWide[list] or 0, y)
        end
    end
    -- Hiding the column also drops the vertical rule that split it from the text.
    if list.Show and list.Hide then
        if open then list:Show() else list:Hide() end
    end
    if type(list.ScrollBox) == "table" and list.ScrollBox.SetAlpha then
        list.ScrollBox:SetAlpha(open and 1 or 0)
    end
end

local function placeJoin(frame)
    local list = type(frame) == "table" and frame.CommunitiesList
    if type(list) ~= "table" then return end
    local empty = loneJoin(list)
    setListColumn(list, not empty)
    local finder = frame.GuildFinderFrame
    local disabled = type(finder) == "table" and finder.DisabledFrame
    if type(disabled) ~= "table" or not DUI.Widgets then return end
    local label = _G.COMMUNITIES_JOIN_COMMUNITY
    if type(label) ~= "string" or label == "" then label = _G.COMMUNITIES_ADD_DIALOG_LABEL end
    if type(label) ~= "string" then label = "" end
    local b = joinBtns[frame]
    if not b and label ~= "" then
        -- The description font string is far taller than the window, so a button
        -- hung on its bottom lands outside the frame. Pin it to the window's
        -- own bottom edge instead, still drawn with the empty-state page.
        b = DUI.Widgets.Button(disabled, label, 26)
        local wide = b.text and b.text.GetStringWidth and b.text:GetStringWidth()
        b:SetWidth(type(wide) == "number" and wide > 40 and math.ceil(wide) + 36 or 280)
        b:SetPoint("BOTTOM", frame, "BOTTOM", 0, 22)
        b:SetScript("OnClick", function()
            if type(AddCommunitiesFlow_Toggle) == "function" then AddCommunitiesFlow_Toggle() end
        end)
        joinBtns[frame] = b
    end
    if b then
        local show = empty and (not disabled.IsShown or disabled:IsShown())
        if show then b:Show() else b:Hide() end
    end
end

local function dressFinder(Kit, finder)
    if type(finder) ~= "table" then return end
    local disabled = finder.DisabledFrame
    if type(disabled) == "table" then
        -- The dragon illustration and the inset edge around it.
        Kit.Strip(disabled)
        Kit.Hide(disabled.NineSlice)
        lightFinderText(Kit, disabled)
        if not finderHooked[disabled] and disabled.HookScript then
            finderHooked[disabled] = true
            disabled:HookScript("OnShow", function() lightFinderText(Kit, disabled) end)
        end
    end
    local inset = finder.InsetFrame
    if type(inset) == "table" then
        Kit.Strip(inset)
        Kit.Hide(inset.NineSlice)
        Kit.Light(inset.GuildDescription, DUI.Style.INK.TEXT)
        Kit.Light(inset.ErrorDescription, DUI.Style.INK.TEXT)
    end
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
        -- The club icon sits in the header, the same slot as our own windows'
        -- portrait. The game hides it while the window is small and hangs the
        -- big one off the top-left corner when it's large; either way it comes
        -- back here, left of the title. A guild with no tabard repaints that
        -- emblem with SetVertexColor(1, 1, 1, 1), which is fine once it isn't
        -- behind the title.
        placeClubIcon(f)
        hookAddFlow()
        -- Maximize/minimize as bare chevrons, level with the X. The button
        -- grows or shrinks the window; the game never says so.
        local mm = f.MaximizeMinimizeFrame
        if type(mm) == "table" then
            watchChevron(mm.MinimizeButton, Kit.BareButton(mm.MinimizeButton, "down"))
            watchChevron(mm.MaximizeButton, Kit.BareButton(mm.MaximizeButton, "up"))
            levelHeaderButtons(f, mm)
            tipButton(mm.MaximizeButton, _G.MAXIMIZE)
            tipButton(mm.MinimizeButton, _G.MINIMIZE)
        end
        if not subHooked and type(hooksecurefunc) == "function" and type(CommunitiesFrameMixin) == "table" then
            subHooked = true
            for _, name in ipairs({ "OnClubSelected", "SetDisplayMode" }) do
                if type(CommunitiesFrameMixin[name]) == "function" then
                    hooksecurefunc(CommunitiesFrameMixin, name, function(self) placeClubIcon(self) end)
                end
            end
        end
        dressFinder(Kit, f.GuildFinderFrame)
        dressFinder(Kit, f.CommunityFinderFrame)
        placeJoin(f)
        if not joinHooked and type(hooksecurefunc) == "function" and type(CommunitiesListMixin) == "table"
            and type(CommunitiesListMixin.Update) == "function" then
            joinHooked = true
            hooksecurefunc(CommunitiesListMixin, "Update", function(self)
                local parent = self.GetParent and self:GetParent()
                if type(parent) == "table" then placeJoin(parent) end
            end)
        end
        local list = f.CommunitiesList
        if type(list) == "table" then
            Kit.Strip(list)
            Kit.Strip(list.FilligreeOverlay)
            Kit.Inset(list.InsetFrame)
            -- The inset sits over the cards as a border. Its shade is drawn
            -- under them; the frame itself is only that border, so it goes.
            if type(list.InsetFrame) == "table" and list.InsetFrame.SetAlpha then list.InsetFrame:SetAlpha(0) end
            Kit.EachRow(list.ScrollBox, clubCard, "clubcard")
        end
        if not addHooked and type(hooksecurefunc) == "function" and type(CommunitiesListEntryMixin) == "table" then
            addHooked = true
            for _, name in ipairs({ "SetAddCommunity", "SetFindCommunity", "SetGuildFinder" }) do
                if type(CommunitiesListEntryMixin[name]) == "function" then
                    hooksecurefunc(CommunitiesListEntryMixin, name, calmEntry)
                end
            end
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

-- "Añadir comunidad" is a forbidden frame: reading it can abort every skin,
-- and pcall does not catch that. The list opens it through AddCommunitiesFlow_Toggle,
-- which is ordinary addon code. That call shows our own window instead, and
-- the same club APIs do the join and the create.
local addFlow
local flowHooked = false

local function gameText(key, ...)
    local s = _G[key]
    if type(s) ~= "string" then return "" end
    if select("#", ...) == 0 then return s end
    local ok, formatted = pcall(string.format, s, ...)
    return ok and formatted or s
end

local function clubType(kind)
    local types = _G.Enum and Enum.ClubType
    if type(types) == "table" and types[kind] ~= nil then return types[kind] end
    return kind == "BattleNet" and 1 or 0
end

local function factionName()
    if type(UnitFactionGroup) ~= "function" then return "" end
    local _, name = UnitFactionGroup("player")
    return type(name) == "string" and name or ""
end

local function ink(fs, which)
    DUI.Style.InkText(fs, which)
end

local ADD_COL = 350 -- room for a description line before it wraps

local function block(parent, y, title, body)
    local head = DUI.Style.Text(parent, DUI.Style.SIZE.head, "LEFT")
    head:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -y)
    head:SetWidth(ADD_COL)
    head:SetWordWrap(true)
    head:SetText(title)
    ink(head, "TITLE")
    local copy = DUI.Style.Text(parent, DUI.Style.SIZE.small, "LEFT")
    copy:SetWidth(ADD_COL)
    copy:SetWordWrap(true)
    copy:SetText(body)
    ink(copy, "TEXT")
    return head, copy
end

-- The same hairline that closes a window header, sitting under a section title
-- and stopping short of the picture button beside it.
local function underTitle(parent, title, copy, right)
    local rule = parent:CreateTexture(nil, "ARTWORK")
    rule:SetTexture("Interface\\Buttons\\WHITE8X8")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    rule:SetPoint("RIGHT", right, "LEFT", -12, 0)
    local classic = DUI.Style.Look and DUI.Style.Look() == "classic"
    if classic and DUI.Style.LOOKS and DUI.Style.LOOKS.classic then
        local hi = DUI.Style.LOOKS.classic.GOLD[2]
        rule:SetVertexColor(hi[1], hi[2], hi[3], 0.55)
    else
        rule:SetVertexColor(1, 1, 1, 0.06)
    end
    copy:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -6)
    return rule
end

local function artButton(parent, up, down, w, h)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    local function atlas(tex, name)
        if tex.SetAtlas then tex:SetAtlas(name) else tex:SetTexture(name) end
    end
    local normal = b:CreateTexture(nil, "ARTWORK")
    normal:SetAllPoints()
    atlas(normal, up)
    b:SetNormalTexture(normal)
    local pushed = b:CreateTexture(nil, "ARTWORK")
    pushed:SetAllPoints()
    atlas(pushed, down)
    b:SetPushedTexture(pushed)
    return b
end

local function showPage(f, page)
    f.choose:SetShown(page == "choose")
    f.create:SetShown(page == "create")
    f.page = page
end

local function paintCreate(f, kind)
    f.creating = kind
    local bnet = kind == "BattleNet"
    DUI.Win.SetTitle(f, gameText(bnet and "COMMUNITIES_CREATE_DIALOG_BATTLE_NET_LABEL" or "COMMUNITIES_CREATE_DIALOG_WOW_LABEL"))
    local typeId = clubType(kind)
    f.avatarId = 1
    if type(C_Club) == "table" and type(C_Club.GetAvatarIdList) == "function" then
        local ok, list = pcall(C_Club.GetAvatarIdList, typeId)
        if ok and type(list) == "table" and #list > 0 then
            f.avatarId = list[math.random(1, #list)]
        end
    end
    if type(C_Club) == "table" and type(C_Club.SetAvatarTexture) == "function" then
        pcall(C_Club.SetAvatarTexture, f.avatar, f.avatarId, typeId)
    end
    f.name:SetText("")
    f.short:SetText("")
    f.about.edit:SetText("")
    if f.about.hint then
        f.about.hint:SetText(gameText(bnet and "COMMUNITIES_CREATE_DIALOG_DESCRIPTION_INSTRUCTIONS_BATTLE_NET"
            or "COMMUNITIES_CREATE_DIALOG_DESCRIPTION_INSTRUCTIONS"))
    end
    local createLabel = gameText(bnet and "COMMUNITIES_CREATE_GROUP" or "COMMUNITIES_CREATE_COMMUNITY")
    if f.createBtn.text and f.createBtn.text.SetText then f.createBtn.text:SetText(createLabel) end
    showPage(f, "create")
end

local function validClubText(kind, text, field)
    if type(C_Club) ~= "table" or type(C_Club.ValidateText) ~= "function" then
        return type(text) == "string" and text ~= ""
    end
    local fields = _G.Enum and Enum.ClubFieldType
    local fieldId = type(fields) == "table" and fields[field] or nil
    if fieldId == nil then return text ~= "" end
    local ok, result = pcall(C_Club.ValidateText, clubType(kind), text, fieldId)
    local success = _G.Enum and Enum.ValidateNameResult and Enum.ValidateNameResult.Success
    if not ok or success == nil then return text ~= "" end
    return result == success
end

function hookAddFlow()
    if flowHooked or type(AddCommunitiesFlow_Toggle) ~= "function" then return end
    if not (DUI.Win and DUI.Win.New and DUI.Widgets) then return end
    flowHooked = true
    local W = DUI.Widgets
    local f = DUI.Win.New({ name = "DaylightCommunitiesAdd", w = 560, h = 480, strata = "DIALOG", compact = true })
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, "TOP", 0, -140)
    addFlow = f
    f:HookScript("OnShow", function(self)
        local faction = factionName()
        DUI.Win.SetTitle(self, gameText("COMMUNITIES_ADD_DIALOG_LABEL"))
        self.wowHead:SetText(gameText("COMMUNITIES_ADD_DIALOG_CREATE_WOW_LABEL", faction))
        self.wowCopy:SetText(gameText("COMMUNITIES_ADD_DIALOG_CREATE_WOW_DESCRIPTION", faction))
        self.invite:SetText("")
        showPage(self, "choose")
        local allowWow = not (type(C_Club) == "table" and type(C_Club.ShouldAllowClubType) == "function")
            or C_Club.ShouldAllowClubType(clubType("Character"))
        local allowBnet = not (type(C_Club) == "table" and type(C_Club.ShouldAllowClubType) == "function")
            or C_Club.ShouldAllowClubType(clubType("BattleNet"))
        self.wowBtn:SetEnabled(allowWow)
        self.bnetBtn:SetEnabled(allowBnet)
        if self.wowBtn.GetNormalTexture and self.wowBtn:GetNormalTexture() then
            self.wowBtn:GetNormalTexture():SetDesaturated(not allowWow)
        end
        if self.bnetBtn.GetNormalTexture and self.bnetBtn:GetNormalTexture() then
            self.bnetBtn:GetNormalTexture():SetDesaturated(not allowBnet)
        end
    end)

    local choose = CreateFrame("Frame", nil, f.host)
    choose:SetAllPoints(f.host)
    f.choose = choose
    local wowHead, wowCopy = block(choose, 18,
        gameText("COMMUNITIES_ADD_DIALOG_CREATE_WOW_LABEL", factionName()),
        gameText("COMMUNITIES_ADD_DIALOG_CREATE_WOW_DESCRIPTION", factionName()))
    f.wowHead, f.wowCopy = wowHead, wowCopy
    local wowBtn = artButton(choose, "communities-create-button-wow-up", "communities-create-button-wow-down", 132, 70)
    wowBtn:SetPoint("TOPRIGHT", choose, "TOPRIGHT", -20, -18)
    f.wowBtn = wowBtn
    local mark = wowBtn:CreateTexture(nil, "OVERLAY")
    mark:SetSize(42, 42)
    mark:SetPoint("RIGHT", wowBtn, "RIGHT", -18, 0)
    local tag = type(UnitFactionGroup) == "function" and UnitFactionGroup("player")
    local markAtlas = tag == "Horde" and "communities-create-button-wow-horde" or "communities-create-button-wow-alliance"
    if mark.SetAtlas then mark:SetAtlas(markAtlas) else mark:SetTexture(markAtlas) end
    wowBtn:SetScript("OnClick", function() paintCreate(f, "Character") end)

    -- A short gap under the WoW block, enough to read as its own section.
    local bnetHead, bnetCopy = block(choose, 152,
        gameText("COMMUNITIES_ADD_DIALOG_CREATE_BNET_LABEL"),
        gameText("COMMUNITIES_ADD_DIALOG_CREATE_BNET_DESCRIPTION"))
    local bnetBtn = artButton(choose, "communities-create-button-bnet-up", "communities-create-button-bnet-down", 116, 67)
    bnetBtn:SetPoint("TOPRIGHT", choose, "TOPRIGHT", -28, -152)
    f.bnetBtn = bnetBtn
    bnetBtn:SetScript("OnClick", function() paintCreate(f, "BattleNet") end)
    underTitle(choose, wowHead, wowCopy, wowBtn)
    underTitle(choose, bnetHead, bnetCopy, bnetBtn)

    local rule = choose:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", bnetCopy, "BOTTOMLEFT", 0, -28)
    rule:SetPoint("TOPRIGHT", bnetCopy, "BOTTOMLEFT", 520, -28)
    rule:SetHeight(1)
    local line = DUI.Style.NEUTRAL
    rule:SetColorTexture(line[1], line[2], line[3], 0.45)

    local inviteHead = DUI.Style.Text(choose, DUI.Style.SIZE.head, "LEFT")
    inviteHead:SetText(gameText("COMMUNITIES_ADD_DIALOG_INVITE_LINK_LABEL"))
    ink(inviteHead, "TITLE")
    local inviteCopy = DUI.Style.Text(choose, DUI.Style.SIZE.small, "LEFT")
    inviteCopy:SetWidth(500)
    inviteCopy:SetWordWrap(true)
    inviteCopy:SetText(gameText("COMMUNITIES_ADD_DIALOG_INVITE_LINK_DESCRIPTION"))
    ink(inviteCopy, "TEXT")

    local join = W.Button(choose, gameText("COMMUNITIES_ADD_DIALOG_INVITE_LINK_JOIN"), 26)
    join:SetWidth(110)
    join:SetPoint("BOTTOMRIGHT", choose, "BOTTOMRIGHT", -20, 18)
    f.join = join
    local invite = W.Input(choose, { maxLetters = 120 })
    invite:SetPoint("LEFT", choose, "LEFT", 20, 0)
    invite:SetPoint("RIGHT", join, "LEFT", -12, 0)
    invite:SetPoint("BOTTOM", join, "BOTTOM", 0, 0)
    f.invite = invite
    -- The heading and the field are one piece. The gap stays above them,
    -- between this piece and the two create blocks.
    inviteCopy:SetPoint("BOTTOMLEFT", invite, "TOPLEFT", 0, 8)
    inviteHead:SetPoint("BOTTOMLEFT", inviteCopy, "TOPLEFT", 0, 4)
    local function redeem()
        local text = invite:GetText()
        if type(text) ~= "string" or text == "" then return end
        if type(C_Club) == "table" and type(C_Club.RedeemTicket) == "function" then
            C_Club.RedeemTicket(text)
        end
        f:Hide()
    end
    join:SetScript("OnClick", redeem)
    invite:HookScript("OnEnterPressed", redeem)

    local create = CreateFrame("Frame", nil, f.host)
    create:SetAllPoints(f.host)
    create:Hide()
    f.create = create
    f.avatar = create:CreateTexture(nil, "ARTWORK")
    f.avatar:SetSize(64, 64)
    f.avatar:SetPoint("TOPLEFT", create, "TOPLEFT", 20, -16)
    local nameLabel = DUI.Style.Text(create, DUI.Style.SIZE.small, "LEFT")
    nameLabel:SetPoint("TOPLEFT", f.avatar, "TOPRIGHT", 16, 0)
    nameLabel:SetText(gameText("COMMUNITIES_SETTINGS_NAME_LABEL"))
    ink(nameLabel, "LABEL")
    local function refreshCreate()
        if not f.name or not f.short or not f.createBtn then return end
        local ok = validClubText(f.creating, f.name:GetText(), "ClubName")
            and validClubText(f.creating, f.short:GetText(), "ClubShortName")
        f.createBtn:SetEnabled(ok)
    end
    f.name = W.Input(create, { maxLetters = 50, onChange = refreshCreate })
    f.name:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -4)
    f.name:SetPoint("RIGHT", create, "RIGHT", -20, 0)
    local shortLabel = DUI.Style.Text(create, DUI.Style.SIZE.small, "LEFT")
    shortLabel:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -12)
    shortLabel:SetText(gameText("COMMUNITIES_CREATE_DIALOG_SHORT_NAME_LABEL"))
    ink(shortLabel, "LABEL")
    f.short = W.Input(create, { maxLetters = 6, onChange = refreshCreate })
    f.short:SetPoint("TOPLEFT", shortLabel, "BOTTOMLEFT", 0, -4)
    f.short:SetPoint("RIGHT", create, "RIGHT", -20, 0)
    local aboutLabel = DUI.Style.Text(create, DUI.Style.SIZE.small, "LEFT")
    aboutLabel:SetPoint("TOPLEFT", f.short, "BOTTOMLEFT", 0, -12)
    aboutLabel:SetText(gameText("COMMUNITIES_CREATE_DIALOG_DESCRIPTION_LABEL"))
    ink(aboutLabel, "LABEL")
    -- A one-line box made multi-line collapses to a hairline. This is the
    -- scrolling area the game uses, stretched down to the buttons.
    f.about = W.TextArea(create, { width = 500, maxLetters = 500,
        hint = gameText("COMMUNITIES_CREATE_DIALOG_DESCRIPTION_INSTRUCTIONS") })
    f.about:SetPoint("TOPLEFT", aboutLabel, "BOTTOMLEFT", 0, -4)
    f.about:SetPoint("RIGHT", create, "RIGHT", -20, 0)
    local cancel = W.Button(create, gameText("CANCEL"), 26)
    cancel:SetWidth(110)
    cancel:SetPoint("BOTTOMRIGHT", create, "BOTTOMRIGHT", -20, 18)
    cancel:SetScript("OnClick", function() f:Hide() end)
    local createBtn = W.Button(create, gameText("COMMUNITIES_CREATE_COMMUNITY"), 26)
    createBtn:SetWidth(160)
    createBtn:SetPoint("RIGHT", cancel, "LEFT", -8, 0)
    f.createBtn = createBtn
    f.about:SetPoint("BOTTOM", createBtn, "TOP", 0, 16)
    createBtn:SetScript("OnClick", function()
        if not createBtn:IsEnabled() then return end
        if type(C_Club) == "table" and type(C_Club.CreateClub) == "function" then
            C_Club.CreateClub(f.name:GetText(), f.short:GetText(), f.about.edit:GetText(), clubType(f.creating), f.avatarId)
        end
        f:Hide()
    end)
    showPage(f, "choose")

    local clubs = _G.CommunitiesFrame
    if type(clubs) == "table" and clubs.HookScript then
        clubs:HookScript("OnHide", function() if f:IsShown() then f:Hide() end end)
    end

    _G.AddCommunitiesFlow_IsShown = function() return f:IsShown() end
    _G.AddCommunitiesFlow_Hide = function() f:Hide() end
    _G.AddCommunitiesFlow_Toggle = function()
        if f:IsShown() then f:Hide() else f:Show() end
    end
end

Engine.Register({ key = "communitiesadddialog", pack = "social", addon = "Blizzard_Communities", apply = function()
    if type(AddCommunitiesFlow_Toggle) ~= "function" then return false end
    hookAddFlow()
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
