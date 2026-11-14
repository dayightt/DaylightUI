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
    -- The game paints the add entry after the row is dressed. Kit.EachRow runs
    -- this again next frame, after the list's update, so it comes out calm.
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
local watched = setmetatable({}, { __mode = "k" })
local tipped = setmetatable({}, { __mode = "k" })
local refit = setmetatable({}, { __mode = "k" })
local finderHooked = setmetatable({}, { __mode = "k" })
local subs = setmetatable({}, { __mode = "k" })
local listWide = setmetatable({}, { __mode = "k" })
local joinBtns = setmetatable({}, { __mode = "k" })
local followed = setmetatable({}, { __mode = "k" })
local placeSubtitle

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
    if type(btn) ~= "table" or not btn.HookScript or watched[btn] then return end
    watched[btn] = true
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
            if not refit[btn] and btn.HookScript then
                refit[btn] = true
                btn:HookScript("OnClick", function() placeClubIcon(frame) end)
            end
        end
    end
end

local function tipButton(btn, text)
    if type(btn) ~= "table" or type(text) ~= "string" or text == "" or tipped[btn] or not btn.HookScript then return end
    if not DUI.Tips then return end
    tipped[btn] = true
    btn:HookScript("OnEnter", function(self)
        if self.IsEnabled and not self:IsEnabled() then return end
        local tip = _G.GameTooltip
        if type(tip) ~= "table" or not tip.SetOwner then return end
        DUI.Tips.Clear()
        DUI.Tips.Title(text)
        DUI.Tips.Flush(tip)
    end)
    btn:HookScript("OnLeave", function()
        DUI.Tips.Clear()
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
    if not b then return end
    local show = empty and (not disabled.IsShown or disabled:IsShown())
    if b.__duiJoin == show then return end
    b.__duiJoin = show
    local Motion = DUI.Motion
    if show then
        b:Show()
        if Motion and Motion.Fade then Motion.Fade(b, 0, 1, Motion.FAST) else b:SetAlpha(1) end
    elseif Motion and Motion.Fade and b.CreateAnimationGroup then
        local g = Motion.Fade(b, b:GetAlpha() or 1, 0, Motion.FAST)
        if type(g) == "table" and g.SetScript then
            g:SetScript("OnFinished", function()
                if (b:GetAlpha() or 1) < 0.05 then b:Hide(); b:SetAlpha(1) end
            end)
        else
            b:Hide()
            b:SetAlpha(1)
        end
    else
        b:Hide()
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

-- Run fn after one of the window's own callbacks. CommunitiesFrame is a
-- callback registry (ClubSelected, DisplayModeChanged); the game calls those
-- inside its own functions, so ours waits for the next frame, once however
-- many fire. No method of the window is hooked.
local frameOwner = {}
local function onFrame(frame, names, fn)
    if followed[frame] then return end
    if type(frame) ~= "table" or type(frame.RegisterCallback) ~= "function" or type(frame.Event) ~= "table" then return end
    followed[frame] = true
    local pending = false
    local function soon()
        if pending or not (C_Timer and C_Timer.After) then return end
        pending = true
        C_Timer.After(0, function()
            pending = false
            DUI.SafeCall(fn, frame)
        end)
    end
    for _, name in ipairs(names) do
        local event = frame.Event[name]
        if event then pcall(frame.RegisterCallback, frame, event, soon, frameOwner) end
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
        -- The icon goes back to the header when the club or the display mode
        -- changes: the window's own callbacks, not a hook on its methods.
        onFrame(f, { "ClubSelected", "DisplayModeChanged" }, placeClubIcon)
        dressFinder(Kit, f.GuildFinderFrame)
        dressFinder(Kit, f.CommunityFinderFrame)
        placeJoin(f)
        local list = f.CommunitiesList
        if type(list) == "table" then
            Kit.Strip(list)
            Kit.Strip(list.FilligreeOverlay)
            Kit.Inset(list.InsetFrame)
            -- The inset sits over the cards as a border. Its shade is drawn
            -- under them; the frame itself is only that border, so it goes.
            if type(list.InsetFrame) == "table" and list.InsetFrame.SetAlpha then list.InsetFrame:SetAlpha(0) end
            Kit.EachRow(list.ScrollBox, clubCard, "clubcard")
            -- The empty column and the join button follow the club list: Kit.EachRow
            -- runs this after every update, next frame, with no hook on the list.
            Kit.EachRow(list.ScrollBox, function() placeJoin(f) end, "join")
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
