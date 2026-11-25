-- Social pack: guild and communities, the calendar, trade and the guild bank.
-- Friends, mail and the group finder have Daylight UI windows of their own; the
-- game's, when a player picks them instead, are in Packs/Game. Each is
-- Engine.Window plus anything unique to it.

local _, ns = ...
local DUI = DaylightUI
local Engine = ns.Engine


-- The guild window (Blizzard_Communities, the game's layout kept): guild and
-- community cards down the left, icon tabs down the right (chat, roster,
-- benefits, info), the roster list, guild info and news, perks and rewards, and
-- the member card beside the roster. Parchment, marble and filigree go, panels
-- become insets on the window, and every list entry gets the row look.
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

-- The flare the other windows play around their portrait as they open (spells,
-- professions), here around the club icon. Made once. It plays a frame after
-- the window shows, once the game has put the icon where it goes, from the
-- frame's OnShow script rather than a hook on its methods.
local glows = setmetatable({}, { __mode = "k" })

-- Whichever of the icon's pieces the game is showing: the club's icon, or for a
-- guild the tabard in its place (UpdatePortrait hides one and shows the other).
-- They share one slot, so the flare is the same round either way.
local function shownClubIcon(overlay, portrait)
    for _, key in ipairs({ "Portrait", "TabardEmblem", "TabardBackground" }) do
        local piece = overlay[key]
        if type(piece) == "table" and piece.IsShown and piece:IsShown() then return piece end
    end
    return portrait
end

local function glowClubIcon(frame)
    local overlay = type(frame) == "table" and frame.PortraitOverlay
    local portrait = type(overlay) == "table" and overlay.Portrait
    if type(overlay) ~= "table" then return end
    local Win = DUI.Win
    if type(portrait) ~= "table" or not (Win and Win.MakeGlow and Win.PlayGlow) then return end
    if glows[frame] then return end
    glows[frame] = Win.MakeGlow(frame, portrait)
    frame:HookScript("OnShow", function()
        if not (C_Timer and C_Timer.After) then return end
        C_Timer.After(0, function()
            -- The game's icon frame sits at a fixed level (300) well above the
            -- window's own, so the flare goes over it, as it does on ours.
            local level = overlay:GetFrameLevel()
            if type(level) == "number" then glows[frame]:SetFrameLevel(level + 2) end
            DUI.SafeCall(Win.PlayGlow, glows[frame], shownClubIcon(overlay, portrait))
        end)
    end)
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

-- The game builds the club list's data in the list's own OnShow, and the
-- window's OnShow then scrolls that list to the selected club. A list hidden
-- before its first show has no data yet, so that scroll errors.
local function listHasData(list)
    local box = type(list) == "table" and list.ScrollBox
    return type(box) == "table" and type(box.GetDataProvider) == "function" and box:GetDataProvider() ~= nil
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
    -- Until the game has filled the list it stays shown, only see-through.
    if list.Show and list.Hide then
        if open then list:Show() elseif listHasData(list) then list:Hide() end
    end
    if list.SetAlpha then list:SetAlpha(open and 1 or 0) end
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
-- inside its own functions, so the restyle waits for the next frame, once however
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
        if event then DUI.SafeCall(frame.RegisterCallback, frame, event, soon, frameOwner) end
    end
end

Engine.Window({ key = "communities", pack = "social", addon = "Blizzard_Communities", frame = "CommunitiesFrame", watch = true,
    auto = { lines = true, skip = { ".MaximizeMinimizeFrame", ".GuildMemberDetailFrame" } },
    after = function(Kit, f)
        -- These tabs sit against the window's right edge, so each wears the
        -- whole tab look joined to the window. An outline around the icon alone
        -- floated off it, as it did on the friends window.
        for _, key in ipairs({ "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab", "GuildPreferredPlaySettingsTab" }) do
            Kit.SideTab(f[key], nil, Kit.SIDE_TAB_CROP, true)
        end
        -- The club icon sits in the header, the same slot as Daylight UI windows'
        -- portrait. The game hides it while the window is small and hangs the
        -- big one off the top-left corner when it's large; either way it comes
        -- back here, left of the title. A guild with no tabard repaints that
        -- emblem with SetVertexColor(1, 1, 1, 1), which is fine once it isn't
        -- behind the title.
        placeClubIcon(f)
        glowClubIcon(f)
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
            -- Guild reputation: the game's fill on the Daylight bar look.
            local faction = benefits.FactionFrame
            local bar = type(faction) == "table" and faction.Bar
            if type(bar) == "table" and Kit.Kind(bar.Progress) == "Texture" then
                Kit.Strip(bar, { [bar.Progress] = true })
                Kit.Shell(bar, "bar")
            end
        end
        -- The member card beside the roster: a panel, with the notes as insets.
        -- Dressed quietly, and left out of the automatic walk. A click on a
        -- member fills the card in one go: the game resizes it, shows the rank
        -- menu, enables Remove, then compares the member's details, which can
        -- be secret and only the game's own untainted code may compare. Any
        -- Daylight UI script on the card's pieces ran inside that and tainted
        -- it, and the card never opened (no promote, demote or remove).
        local card = f.GuildMemberDetailFrame
        if type(card) == "table" then
            Kit.Strip(card)
            Kit.Shell(card, "window", { quiet = true })
            Kit.Hide(card.Border)
            Kit.Inset(card.NoteBackground)
            Kit.Inset(card.OfficerNoteBackground)
            Kit.Close(card.CloseButton)
            Kit.Button(card.RemoveButton, card)
            Kit.Button(card.GroupInviteButton, card)
            Kit.Dropdown(card.RankDropdown)
            Kit.InkGameText(card)
            Kit.InkGameText(card.NoteBackground)
            Kit.InkGameText(card.OfficerNoteBackground)
        end
    end })

-- The guild's side windows: guild log, editing the message of the day or info
-- text, and news filters.
for _, name in ipairs({ "CommunitiesGuildLogFrame", "CommunitiesGuildTextEditFrame", "CommunitiesGuildNewsFiltersFrame" }) do
    Engine.Window({ key = string.lower(name), pack = "social", addon = "Blizzard_Communities", frame = name,
        after = function(Kit, f) Kit.Inset(f.Container) end })
end
Engine.Window({ key = "calendar", pack = "social", addon = "Blizzard_Calendar", frame = "CalendarFrame", watch = true })

-- Trade: both sides' items and money, and the Trade/Cancel buttons. Kit.Auto
-- finds most of it. Your own money boxes are forbidden frames (TradeFrame_OnLoad
-- calls SetForbidden on them), so they keep the game's look: no addon can touch
-- them. Each item row (TradeItemTemplate) is a plain frame holding the slot and
-- its name, drawn as a list line with the slot in the item look.
local Trade = {}
ns.Trade = Trade
Trade.NAME_X = 14        -- the names line up with the item slots under them
Trade.THEIR_X = 182
Trade.HEAD_TOP = -8      -- the header band, between the accent line and the money row
Trade.HEAD_BOTTOM = -54
Trade.BUTTON_W = 110
Trade.BUTTON_GAP = 8
Trade.BUTTON_Y = 6
Trade.ACCEPT_WASH = 0.08 -- how strongly an accepted side is tinted

local function tradeItems(Kit, prefix)
    for i = 1, 7 do
        local row = _G[prefix .. i]
        local slot = _G[prefix .. i .. "ItemButton"]
        if type(row) == "table" then Kit.Row(row, nil, nil, false, slot) end
        if type(slot) == "table" then Kit.Item(slot) end
    end
end

-- Each name in its class color, read when the window opens: the game sets the
-- names on TRADE_SHOW, just before.
local function classColored(fs, unit)
    if type(fs) ~= "table" then return end
    local _, token = UnitClass(unit)
    fs:SetTextColor(DUI.Style.ClassTextColor(token))
end

function Trade.PaintNames()
    classColored(_G.TradeFramePlayerNameText, "player")
    classColored(_G.TradeFrameRecipientNameText, "NPC")   -- the game's unit for the other trader
end

-- The game shows green art over a side once it accepts. Here: an outline and a
-- faint wash in the "good" color, easing in.
local accepted = setmetatable({}, { __mode = "k" }) -- the game's highlight -> its replacement
local function acceptLook(Kit, h)
    if type(h) ~= "table" or not h.HookScript or accepted[h] then return end
    Kit.Strip(h)
    local look = CreateFrame("Frame", nil, h)
    look:SetAllPoints(h)
    look:EnableMouse(false)
    local good = DUI.Style.INK.GOOD
    Kit.Paint(Kit.Shell(look, "row", { noBackground = true }), good)
    local wash = look:CreateTexture(nil, "BACKGROUND")
    wash:SetAllPoints(look)
    wash:SetColorTexture(good[1], good[2], good[3], Trade.ACCEPT_WASH)
    accepted[h] = look
    h:HookScript("OnShow", function()
        look:SetAlpha(0)
        DUI.Motion.AlphaTo(look, 1, DUI.Motion.FAST)
    end)
end

Engine.Window({ key = "trade", pack = "social", frame = "TradeFrame",
    after = function(Kit, f)
        local Style = DUI.Style
        tradeItems(Kit, "TradePlayerItem")
        tradeItems(Kit, "TradeRecipientItem")
        -- Each side's item, enchant and money boxes are inset frames with the
        -- game's marble art. They're named but not keyed, so the window walk
        -- doesn't know them as insets: dressed here like every other inset.
        for _, side in ipairs({ "Player", "Recipient" }) do
            Kit.Inset(_G["Trade" .. side .. "ItemsInset"])
            Kit.Inset(_G["Trade" .. side .. "EnchantInset"])
        end
        Kit.Inset(_G.TradePlayerInputMoneyInset)
        Kit.Inset(_G.TradeRecipientMoneyInset)
        Kit.Strip(_G.TradeRecipientMoneyFrame)
        -- Their money sits on a gold-edged box: a text box's look instead.
        local theirBox = _G.TradeRecipientMoneyBg
        if type(theirBox) == "table" and not Kit.ShellOf(theirBox) then
            Kit.Strip(theirBox)
            Kit.Shell(theirBox, "input")
        end
        -- The other player's round portrait and gold ring are on their own
        -- frame (RecipientOverlay, level 550, above the names), so the window
        -- strip misses them. Erased like every skinned window's portrait.
        local overlay = f.RecipientOverlay
        if type(overlay) == "table" then
            Kit.Erase(overlay.portrait)
            Kit.Erase(overlay.portraitFrame)
        end
        -- The two names head their columns. Their own boxes (TradeFrame.xml:
        -- yours 100 wide, theirs 80) are too narrow for a first and last name,
        -- so each gets its column's width and the band down to the money row,
        -- a long name wrapping to a second line.
        local mine, theirs = _G.TradeFramePlayerNameText, _G.TradeFrameRecipientNameText
        if mine and theirs then
            mine:ClearAllPoints()
            mine:SetPoint("TOPLEFT", f, "TOPLEFT", Trade.NAME_X, Trade.HEAD_TOP)
            mine:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", Trade.THEIR_X - 16, Trade.HEAD_BOTTOM)
            theirs:ClearAllPoints()
            theirs:SetPoint("TOPLEFT", f, "TOPLEFT", Trade.THEIR_X, Trade.HEAD_TOP)
            theirs:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -30, Trade.HEAD_BOTTOM)
            for _, fs in ipairs({ mine, theirs }) do
                Kit.Font(fs, Style.SIZE.head)
                fs:SetWordWrap(true)
                fs:SetMaxLines(2)
                fs:SetJustifyH("LEFT")
                fs:SetJustifyV("MIDDLE")
            end
            Trade.PaintNames()
            if not Trade.hooked then
                Trade.hooked = true
                f:HookScript("OnShow", Trade.PaintNames)
            end
        end
        -- "Will not be traded" is a label over the last slot.
        for _, name in ipairs({ "TradeFramePlayerEnchantText", "TradeFrameRecipientEnchantText" }) do
            Kit.Font(_G[name], Style.SIZE.small, Style.INK.LABEL)
        end
        for _, name in ipairs({ "TradeHighlightPlayer", "TradeHighlightRecipient",
                                "TradeHighlightPlayerEnchant", "TradeHighlightRecipientEnchant" }) do
            acceptLook(Kit, _G[name])
        end
        -- Trade and Cancel as a footer: centered, the same width, the main one first.
        local trade, cancel = f.TradeButton or _G.TradeFrameTradeButton, f.CancelButton or _G.TradeFrameCancelButton
        Kit.Button(trade)
        Kit.Button(cancel)
        if type(trade) == "table" and type(cancel) == "table" then
            trade:ClearAllPoints()
            trade:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -Trade.BUTTON_GAP / 2, Trade.BUTTON_Y)
            cancel:ClearAllPoints()
            cancel:SetPoint("BOTTOMLEFT", f, "BOTTOM", Trade.BUTTON_GAP / 2, Trade.BUTTON_Y)
            trade:SetWidth(Trade.BUTTON_W)
            cancel:SetWidth(Trade.BUTTON_W)
        end
    end })

-- Guild bank: the item slots and GuildItemSearchBox (a child of the frame but
-- not a keyed part) already get the Daylight look from the generic pass. The game's own
-- search marks matching slots too (SetMatchesSearch from GetGuildBankItemInfo's
-- isFiltered) and flags tabs with a match. On top of that, slots that don't
-- match are dimmed to 0.3 alpha, in case the skin hides the game's overlay
-- (not yet confirmed in game). Slots are Column1..7 / Button1..14, each with a
-- fixed ID 1-98 passed straight to GetGuildBankItemInfo.
local bankItems = setmetatable({}, { __mode = "k" }) -- bank window -> its 98 slots
local bankDimmed = setmetatable({}, { __mode = "k" }) -- bank window -> true if any were dimmed
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
