-- Options window navigation: the section rail and the page list column next
-- to it (logo, version, search, pages, unlock button). Panel.lua decides what
-- to show and calls nav.Layout(state). Clicks go to the handlers from Nav.New.

local _, DUI = ...
local W, Theme = DUI.Widgets, DUI.OptionsTheme
local SIZE = DUI.Style.SIZE
local C = W.COLORS
local L = DUI.L
local T = DUI.Options.Text
local Options = DUI.Options
local MEDIA = DUI.MEDIA

local Nav = {}
DUI.OptionsNav = Nav

Nav.RAIL = 66               -- rail width
Nav.LIST = 160              -- page list width
Nav.RAIL_BUTTON = 44        -- section button height, icon and name
Nav.ICON = 20
Nav.PAGE_ROW = 26
Nav.LOGO = { 136, 34 }      -- wordmark size (the image is 4:1)
Nav.PAGES_TOP = 136         -- page list offset from the column's top
Nav.ICON_ALPHA = { on = 1, off = 0.6, empty = 0.25 }

-- Scroll bar sits inside the list's right edge.
local function scrollArea(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sf)
    child:SetHeight(1)
    sf:SetScrollChild(child)
    sf.bar = W.Scroll(sf, { x = -8, step = 40 })
    return sf, child
end

-- ---------------------------------------------------------------------
-- The rail
-- ---------------------------------------------------------------------

local function paintSection(b)
    local alpha = (b.on or b.hover) and Nav.ICON_ALPHA.on or (b.empty and Nav.ICON_ALPHA.empty or Nav.ICON_ALPHA.off)
    b.icon:SetAlpha(alpha)
    W.TextColor(b.text, (b.on or b.hover) and C.text or (b.empty and C.faint or C.dim))
    b.wash:SetShown(b.on)
end

local function sectionButton(nav, section)
    local look = Theme.Section(section.id)
    local c = look.color
    local b = CreateFrame("Button", nil, nav.railChild)
    b:SetHeight(Nav.RAIL_BUTTON)
    b:SetWidth(Nav.RAIL)
    b.section, b.look = section, look
    b.wash = b:CreateTexture(nil, "BACKGROUND")
    b.wash:SetAllPoints(b)
    b.wash:SetColorTexture(c[1], c[2], c[3], 0.14)
    b.wash:Hide()
    -- Left-edge bar marks the current section, or pending news.
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetColorTexture(c[1], c[2], c[3], 1)
    b.bar:SetWidth(3)
    b.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    b.bar:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexture(Theme.IconFile(look.icon))
    b.icon:SetSize(Nav.ICON, Nav.ICON)
    b.icon:SetPoint("TOP", b, "TOP", 0, -6)
    W.Tint(b.icon, c)
    b.text = W.Font(b, W.BODY, SIZE.small, C.dim, "CENTER")
    b.text:SetPoint("TOP", b.icon, "BOTTOM", 0, -3)
    b.text:SetWidth(Nav.RAIL - 6)
    b.text:SetText(T(look.short))
    -- Match count while searching.
    b.count = W.Font(b, W.BODY, SIZE.tiny, C.faint, "RIGHT")
    b.count:SetPoint("TOPRIGHT", b, "TOPRIGHT", -5, -4)
    b:SetScript("OnClick", function() DUI.Sound.Play("click"); nav.on.Section(section.id) end)
    -- Gamepad works like the game's Settings list: the D-pad landing here
    -- shows the section, A enters it.
    b.OnSmartNavSelect = function()
        local on = Options.GetPage(DUI.OptionsPanel.Current() or "")
        if not (on and on.section == section.id) then
            DUI.Sound.Play("click")
            nav.on.Section(section.id)
        end
        DUI.OptionsPanel.PadAimList(b)
    end
    b.OnSmartNavClick = function() DUI.OptionsPanel.PadEnter() end
    b:SetScript("OnEnter", function(self)
        self.hover = true
        paintSection(self)
        W.Tooltip(self, T(section.label), T(look.blurb))
    end)
    b:SetScript("OnLeave", function(self)
        self.hover = false
        paintSection(self)
        W.HideTooltip()
    end)
    -- Sections with news (section.badge) pulse their bar and show NEW.
    if section.badge then
        b.pulse = Nav.Pulse(b, b.bar)
        b.tag = W.Title(b, SIZE.tiny, C.text, "RIGHT")
        b.tag:SetPoint("TOPRIGHT", b, "TOPRIGHT", -5, -4)
        b.tag:SetText(L["NEW"])
        W.TextDaylight(b.tag)
        b.tag:Hide()
    end
    return b
end

-- Pulses a bar between full alpha and Nav.PULSE_LOW. Stepped with Motion.Tween
-- rather than an alpha animation group, and only while the button is visible
-- so a closed window runs nothing. Stop() returns the bar to full.
Nav.PULSE_LOW = 0.35
function Nav.Pulse(owner, tex)
    local M = DUI.Motion
    local p = { playing = false }
    local function set(a) tex:SetAlpha(a) end
    local function leg(from, to)
        p.resting = false
        M.Tween(tex, from, to, 2 * M.SLOW, set, function()
            if p.playing and owner:IsVisible() then leg(to, from) else p.resting = p.playing end
        end)
    end
    function p:Play()
        if self.playing then return end
        self.playing = true
        if M.On() and owner:IsVisible() then leg(1, Nav.PULSE_LOW) else self.resting = true end
    end
    function p:Stop()
        self.playing, self.resting = false, false
        M.Tween(tex, 1, 1, 0, set)   -- cancels a running leg
    end
    function p:IsPlaying() return self.playing end
    owner:HookScript("OnShow", function()
        if p.playing and p.resting and M.On() then leg(1, Nav.PULSE_LOW) end
    end)
    return p
end

-- "Plugins" heading above plugin sections (Plugins.lua), shown only while
-- a plugin has pages.
Nav.PLUGINS_HEAD = 26
local function pluginsHeading(nav)
    if nav.pluginsHead then return nav.pluginsHead end
    local h = CreateFrame("Frame", nil, nav.railChild)
    h:SetSize(Nav.RAIL, Nav.PLUGINS_HEAD)
    h.rule = h:CreateTexture(nil, "ARTWORK")
    h.rule:SetColorTexture(1, 1, 1, 0.06)
    h.rule:SetHeight(1)
    h.rule:SetPoint("TOPLEFT", h, "TOPLEFT", 10, -4)
    h.rule:SetPoint("TOPRIGHT", h, "TOPRIGHT", -10, -4)
    h.text = W.Font(h, W.BODY, SIZE.tiny, C.dim, "CENTER")
    h.text:SetPoint("TOP", h.rule, "BOTTOM", 0, -5)
    h.text:SetWidth(Nav.RAIL - 4)
    h.text:SetText(L["Plugins"])
    nav.pluginsHead = h
    return h
end

local function layoutRail(nav, state)
    local y = 8
    local headed = false
    for _, section in ipairs(state.sections) do
        local b = nav.sectionButtons[section.id]
        if not b then
            b = sectionButton(nav, section)
            nav.sectionButtons[section.id] = b
        end
        local shown = #section.pages > 0
        b:SetShown(shown)
        if shown and section.plugin and not headed then
            headed = true
            local h = pluginsHeading(nav)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", nav.railChild, "TOPLEFT", 0, -y)
            h:Show()
            y = y + Nav.PLUGINS_HEAD
        end
        if shown then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", nav.railChild, "TOPLEFT", 0, -y)
            y = y + Nav.RAIL_BUTTON + 2
        end
        b.on = section.id == state.section
        local n = state.sectionCounts and state.sectionCounts[section.id]
        b.count:SetText(n and n > 0 and tostring(n) or "")
        b.empty = n == 0
        local news = section.badge ~= nil and not b.on and section.badge() == true
        b.bar:SetShown(b.on or news)
        if b.pulse then
            if news then
                if not b.pulse:IsPlaying() then b.pulse:Play() end
            else
                b.pulse:Stop()
                b.bar:SetAlpha(1)
            end
        end
        if b.tag then b.tag:SetShown(news and state.sectionCounts == nil) end
        paintSection(b)
    end
    if not headed and nav.pluginsHead then nav.pluginsHead:Hide() end
    nav.railChild:SetHeight(y + 8)
end

-- ---------------------------------------------------------------------
-- The page list
-- ---------------------------------------------------------------------

Nav.PICK_BAR = 14   -- picked page's accent bar height, px

-- Page names run to the row's end, clear of the scroll bar. While searching
-- they stop short to leave room for the match count.
Nav.PAGE_TEXT_END = -14
Nav.PAGE_COUNT_ROOM = 20

-- The picked page grows its bar from the middle and fades in its wash.
-- The fade goes into the tint itself, not SetAlpha: in game a texture's
-- SetAlpha replaces its tint's alpha, which turned the 5% wash solid white.
Nav.WASH = 0.05

local function shadePick(b, v)
    b.pickShade = v
    W.Tint(b.bg, { 1, 1, 1 }, Nav.WASH * v)
    W.TintDaylight(b.bar, v)
    b.bg:SetShown(v > 0); b.bar:SetShown(v > 0)
end

local function paintPick(b)
    local was = b.picked
    b.picked = b.on
    if was == b.on then return end
    local M = DUI.Motion
    b.pickKey = b.pickKey or {}
    if was == nil or not b:IsVisible() or not M.On() then
        M.Tween(b.bar, 0, 0, 0); M.Tween(b.pickKey, 0, 0, 0)
        b.bar:SetHeight(Nav.PICK_BAR)
        shadePick(b, b.on and 1 or 0)
        return
    end
    M.Tween(b.pickKey, b.pickShade or 0, b.on and 1 or 0, M.FAST, function(v) shadePick(b, v) end)
    local h = b.bar:GetHeight() or Nav.PICK_BAR
    M.Tween(b.bar, b.on and 1 or h, b.on and Nav.PICK_BAR or 1, M.FAST, function(v) b.bar:SetHeight(v) end)
end

local function paintPage(b)
    paintPick(b)
    W.TextColor(b.text, (b.on or b.hover) and C.text or (b.empty and C.faint or C.dim))
end

local function pageButton(nav, page)
    local b = CreateFrame("Button", nil, nav.pagesChild)
    b:SetHeight(Nav.PAGE_ROW)
    b:SetWidth(Nav.LIST)
    b.page = page
    b.bg = W.Round(b, "BACKGROUND")
    b.bg:SetPoint("TOPLEFT", b, "TOPLEFT", 8, 0)
    b.bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -8, 0)
    b.bg:Hide()
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetTexture(MEDIA .. "ui-pill.png")
    b.bar:SetSize(3, 14)
    b.bar:SetPoint("LEFT", b, "LEFT", 12, 0)
    b.bar:Hide()
    b.text = W.Font(b, W.BODY, SIZE.body, C.dim)
    b.text:SetPoint("LEFT", b, "LEFT", 22, 0)
    b.text:SetPoint("RIGHT", b, "RIGHT", Nav.PAGE_TEXT_END, 0)
    b.text:SetText(T(page.label))
    b.count = W.Font(b, W.BODY, SIZE.tiny, C.faint, "RIGHT")
    b.count:SetPoint("RIGHT", b, "RIGHT", Nav.PAGE_TEXT_END, 0)
    b:SetScript("OnClick", function() DUI.Sound.Play("click"); nav.on.Page(page.id) end)
    -- Gamepad behaves like the game's Settings list (Blizzard_CategoryList.lua):
    -- the D-pad landing on a page shows it, A enters it.
    b.OnSmartNavSelect = function()
        if DUI.OptionsPanel.Current() ~= page.id then
            DUI.Sound.Play("click")
            nav.on.Page(page.id)
        end
        DUI.OptionsPanel.PadAimList(b)
    end
    b.OnSmartNavClick = function()
        if DUI.OptionsPanel.Current() ~= page.id then nav.on.Page(page.id) end
        DUI.OptionsPanel.PadEnter()
    end
    b:SetScript("OnEnter", function(self)
        self.hover = true
        paintPage(self)
    end)
    b:SetScript("OnLeave", function(self)
        self.hover = false
        paintPage(self)
    end)
    return b
end

local function sectionOf(state)
    for _, s in ipairs(state.sections) do
        if s.id == state.section then return s end
    end
end

local function layoutPages(nav, state)
    local section = sectionOf(state)
    -- A new section's pages slide in from below. A search keystroke only
    -- recounts the same list.
    local switched = nav.laidSection ~= nil and nav.laidSection ~= state.section
    nav.laidSection = state.section
    nav.listTitle:SetText(section and T(section.label) or "")
    if section then W.TextColor(nav.listTitle, Theme.Section(section.id).color) end
    -- Hide only pages that are leaving, so ones that stay can ease their
    -- pick state while visible.
    local keep = {}
    for _, page in ipairs(section and section.pages or {}) do keep[page.id] = true end
    for id, b in pairs(nav.pageButtons) do
        if not keep[id] or switched then b:Hide() end
    end
    local y = 0
    for _, page in ipairs(section and section.pages or {}) do
        local b = nav.pageButtons[page.id]
        if not b then
            b = pageButton(nav, page)
            nav.pageButtons[page.id] = b
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", nav.pagesChild, "TOPLEFT", 0, -y)
        y = y + Nav.PAGE_ROW
        b.on = page.id == state.page
        local n = state.pageCounts and state.pageCounts[page.id]
        local counted = n and n > 0
        b.count:SetText(counted and tostring(n) or "")
        b.text:SetPoint("RIGHT", b, "RIGHT", Nav.PAGE_TEXT_END - (counted and Nav.PAGE_COUNT_ROOM or 0), 0)
        b.empty = n == 0
        paintPage(b)
        b:Show()
    end
    nav.pagesChild:SetHeight(y + 4)
    if switched and nav.pagesChild:IsVisible() then
        DUI.Motion.SlideIn(nav.pagesChild, 0, -DUI.OptionsPanel.SLIDE)
    end
end

-- ---------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------

local function buildRail(nav, frame)
    local rail = CreateFrame("Frame", nil, frame)
    rail:SetWidth(Nav.RAIL)
    rail.bg = rail:CreateTexture(nil, "BACKGROUND")
    rail.bg:SetAllPoints(rail)
    rail.bg:SetColorTexture(C.sidebar[1], C.sidebar[2], C.sidebar[3], 1)
    nav.rail = rail
    nav.railScroll, nav.railChild = scrollArea(rail)
    nav.railScroll:SetAllPoints(rail)
    nav.railChild:SetWidth(Nav.RAIL)
end

local function buildList(nav, frame)
    local list = CreateFrame("Frame", nil, frame)
    list:SetWidth(Nav.LIST)
    list.bg = list:CreateTexture(nil, "BACKGROUND")
    list.bg:SetAllPoints(list)
    list.bg:SetColorTexture(C.list[1], C.list[2], C.list[3], 1)
    list.edge = list:CreateTexture(nil, "BORDER")
    list.edge:SetColorTexture(1, 1, 1, 0.05)
    list.edge:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)
    list.edge:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)
    list.edge:SetWidth(1)
    nav.list = list

    -- Logo (Media/logo-wordmark.png).
    local logo = list:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(MEDIA .. "logo-wordmark.png")
    logo:SetSize(Nav.LOGO[1], Nav.LOGO[2])
    logo:SetPoint("TOPLEFT", list, "TOPLEFT", 12, -14)
    nav.version = W.Font(list, W.BODY, SIZE.small, C.faint)
    nav.version:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", Nav.LOGO[2] * 1.02 + 2, 2)
    nav.version:SetText("v" .. tostring(DUI.VERSION))   -- kept short so the Discord link fits
    -- Discord link. The game can't open a browser, so a click shows the
    -- invite to copy.
    local discord = W.Link(list, SIZE.small, { own = true })
    discord.SetLabel("·  " .. DUI.GradientText("Discord"))
    discord:SetHeight(16)
    discord:SetPoint("LEFT", nav.version, "RIGHT", 4, 0)
    discord:HookScript("OnEnter", function(self)
        W.Tooltip(self, L["DaylightUI Discord"], L["Click to copy the invite link."])
    end)
    discord:HookScript("OnLeave", W.HideTooltip)
    discord:SetScript("OnClick", function() nav.on.Discord() end)
    nav.discord = discord

    local box = W.Input(list, { height = 28, search = true, hint = L["Search settings"],
        onChange = function(text) nav.on.Search(text) end })
    box:SetPoint("TOPLEFT", list, "TOPLEFT", 10, -76)
    box:SetPoint("TOPRIGHT", list, "TOPRIGHT", -10, -76)
    nav.searchBox = box

    -- Section name above its pages, in the section color.
    nav.listTitle = W.Font(list, W.BODY, SIZE.small, C.dim)
    nav.listTitle:SetPoint("TOPLEFT", list, "TOPLEFT", 14, -(Nav.PAGES_TOP - 18))

    nav.pagesScroll, nav.pagesChild = scrollArea(list)
    nav.pagesScroll:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -Nav.PAGES_TOP)
    nav.pagesScroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 52)
    nav.pagesChild:SetWidth(Nav.LIST)

    nav.unlock = W.Button(list, L["Unlock frames"], 28)
    nav.unlock:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 12, 12)
    nav.unlock:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -12, 12)
    nav.unlock:SetScript("OnClick", function() nav.on.Unlock() end)

    -- Shown while the setup guide is unfinished (DB.Unsaved), because changes
    -- aren't saved until then. A click opens the guide.
    nav.setup = W.Button(list, L["Finish setup"], 28)
    nav.setup:SetPoint("BOTTOMLEFT", nav.unlock, "TOPLEFT", 0, 6)
    nav.setup:SetPoint("BOTTOMRIGHT", nav.unlock, "TOPRIGHT", 0, 6)
    nav.setup.SetActive(true)
    nav.setup:HookScript("OnEnter", function(self) DUI.Installer.UnsavedTip(self) end)
    nav.setup:HookScript("OnLeave", W.HideTooltip)
    nav.setup:SetScript("OnClick", function() DUI.Installer.OpenToSave() end)
    nav.setup:Hide()
    function nav.SyncSetup()
        local show = DUI.DB.Unsaved()
        nav.setup:SetShown(show)
        nav.pagesScroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, show and 86 or 52)
    end
end

-- Builds the rail and page list on frame. on holds the handlers
-- { Section(id), Page(id), Search(text), Unlock(), Discord() }.
function Nav.New(frame, on)
    local nav = { on = on, sectionButtons = {}, pageButtons = {} }
    buildRail(nav, frame)
    buildList(nav, frame)
    -- state = { sections, section, page, sectionCounts, pageCounts }.
    -- The two count tables map id to matches and are nil unless searching.
    function nav.Layout(state)
        layoutRail(nav, state)
        layoutPages(nav, state)
    end
    return nav
end
