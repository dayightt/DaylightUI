-- The options window. Navigation on the left (Nav.lua), the current page on
-- the right: header, optional live sample (SampleStrip.lua) and scrolling cards.
-- Pages come from the registry, so modules show up without window code here.

local _, DUI = ...
local Style, W, Options, Nav, Theme = DUI.Style, DUI.Widgets, DUI.Options, DUI.OptionsNav, DUI.OptionsTheme
local SIZE = DUI.Style.SIZE
local C = W.COLORS
local L = DUI.L
local T = Options.Text

local Panel = {}
DUI.OptionsPanel = Panel

Panel.SIZE = { 1000, 680 }   -- default window size
Panel.MIN = { 860, 560 }     -- minimum resize
Panel.CONTENT_LEFT, Panel.CONTENT_RIGHT = 20, 26   -- page margins
Panel.TOP = 12               -- title line offset, matches Win.TITLE_Y
Panel.HEADER = 56            -- title plus description, matches Win.HEADER
Panel.SAMPLE_GAP = 12        -- gap between the live sample and the settings
Panel.CHIPS_GAP = 10         -- gap between the chips and the cards
Panel.BUG_ICON = 18          -- the Report a bug icon beside the chips
Panel.JUMP_MARGIN = 8        -- space kept above a setting we jump to
Panel.MIN_QUERY = 2          -- letters needed before search results show
Panel.SLIDE = 12             -- slide-in distance for a page switch, px
-- Page area width. PatchNotesUI reads it; updated on resize.
Panel.CONTENT_WIDTH = Panel.SIZE[1] - 2 - Nav.RAIL - Nav.LIST - Panel.CONTENT_LEFT - Panel.CONTENT_RIGHT

local frame, nav, topLine, grip
local header, resetPage, testSwitch, designSwitch, sampleStrip, chips, bugButton, tabRow, results, scroll, scrollBar, emptyText
local designPages = {}       -- page id -> true while in Design mode (session only)
local pageFrames = {}
local lastPage = {}          -- section id -> last page shown
local current, query = nil, ""
local pageScroll = 0         -- scroll position when a search began
-- Where the window was when unlocking hid it, so locking can restore it.
-- Panel.Show clears this.
local hiddenForUnlock, hiddenPage, hiddenScroll = false, nil, 0
local hiddenTab, hiddenFocus

local function trim(s) return (string.gsub(s or "", "^%s*(.-)%s*$", "%1")) end

local function border() return DUI.Pixel.Px(frame, DUI.DB.General().borderPx) end

-- Page area width: window minus rail, page list, border and margins.
local function contentWidth()
    if not frame then return Panel.CONTENT_WIDTH end
    local w = frame:GetWidth()
    if type(w) ~= "number" or w <= 0 then w = Panel.SIZE[1] end
    return math.floor(w - 2 * border() - Nav.RAIL - Nav.LIST - Panel.CONTENT_LEFT - Panel.CONTENT_RIGHT)
end
Panel.ContentWidth = contentWidth

local function sectionOf(page)
    for _, s in ipairs(Options.Sections()) do
        if s.id == page.section then return s end
    end
end

-- ---------------------------------------------------------------------
-- Scrolling
-- ---------------------------------------------------------------------

local function scrollRange(sf)
    local child = sf:GetScrollChild()
    local h = child and child:GetHeight() or 0
    local view = sf:GetHeight()
    if type(h) ~= "number" or type(view) ~= "number" then return 0, 0 end
    return math.max(0, h - view), view
end

local function updateScrollBar()
    if scrollBar then scrollBar.Stop(); scrollBar.Update() end
end

-- ---------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------

Panel.DISCORD = "https://discord.gg/eeSYZDd6ar"
Panel.KOFI = "https://ko-fi.com/daylightui"
Panel.PATREON = "https://www.patreon.com/cw/DaylightUI"
Panel.PROFILES_SITE = "https://www.daylightui.com/profiles"
Panel.DONATORS = "donators"   -- page id (Donators.lua)

-- Popup with a pre-selected link to copy, since addons can't open a browser.
local function showLink(which, url, text)
    if not StaticPopupDialogs[which] then
        local function fill(box)
            box:SetText(url)
            box:HighlightText()
            box:SetFocus()
        end
        StaticPopupDialogs[which] = {
            text = text,
            button1 = CLOSE or L["Close"],
            hasEditBox = true, editBoxWidth = 260, timeout = 0, whileDead = true, hideOnEscape = true,
            preferredIndex = 3,
            OnShow = function(self)
                local box = self.editBox or self.EditBox
                if box then fill(box) end
            end,
            -- Typing can't change the link; it snaps back, still selected.
            EditBoxOnTextChanged = function(box)
                if box:GetText() ~= url then fill(box) end
            end,
            EditBoxOnEnterPressed = function(box) box:GetParent():Hide() end,
            EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
        }
    end
    StaticPopup_Show(which)
end

function Panel.ShowDiscord()
    showLink("DAYLIGHTUI_DISCORD", Panel.DISCORD,
        L["Join the DaylightUI Discord: press Ctrl+C to copy the link, then paste it in your browser."])
end

function Panel.ShowKofi()
    showLink("DAYLIGHTUI_KOFI", Panel.KOFI,
        L["Support DaylightUI on Ko-fi: press Ctrl+C to copy the link, then paste it in your browser."])
end

function Panel.ShowPatreon()
    showLink("DAYLIGHTUI_PATREON", Panel.PATREON,
        L["Become a Daylight UI VIP on Patreon: press Ctrl+C to copy the link, then paste it in your browser."])
end

function Panel.ShowProfilesSite()
    showLink("DAYLIGHTUI_PROFILES_SITE", Panel.PROFILES_SITE,
        L["Profiles shared by Daylight UI players: press Ctrl+C to copy the link, then paste it in your browser."])
end

-- An attention-grabbing button: lifted band, lit outline, gradient text and
-- a light sweep on show and hover. Used for the home page's support buttons
-- and the shared profiles card.
function Panel.SupportButton(parent, text, onClick, h, minW)
    local b = W.Button(parent, DUI.GradientText(text), h or 24)
    b.main = true
    b.Paint()
    b.SetActive(true)
    b.FitWidth(minW or 100)
    b.shine = b:CreateTexture(nil, "OVERLAY")
    b.shine:SetTexture(DUI.MEDIA .. "glow.png")
    b.shine:SetBlendMode("ADD")
    b.shine:SetHeight((h or 24) + 12)
    b.shine:Hide()
    local function shine()
        local M = DUI.Motion
        M.Sweep(b.shine, b, { width = 40, dur = M.SLOW + M.NORMAL, alpha = 0.55,
            color = { Style.SweepAt() } })
    end
    b:SetScript("OnClick", onClick)
    b:HookScript("OnShow", shine)
    b:HookScript("OnEnter", shine)
    return b
end

local function buildHeader()
    local close = W.Close(frame, function() DUI.Motion.Vanish(frame) end)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", DUI.Win.CLOSE_X, DUI.Win.CloseY())   -- same spot as every window's X

    header = CreateFrame("Frame", nil, frame)
    header:SetHeight(Panel.HEADER)
    header.title = W.Title(header, SIZE.title, DUI.Style.INK.TITLE)   -- same as Win.Header's title
    header.title:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
    -- Section name after the page title, in the section color.
    header.section = W.Font(header, W.BODY, SIZE.small, C.dim)
    header.section:SetPoint("BOTTOMLEFT", header.title, "BOTTOMRIGHT", 10, 2)
    -- One-line description, truncated if needed; the full text on hover.
    header.desc = W.Font(header, W.BODY, SIZE.small, C.dim)
    -- Home page support buttons (Patreon, Ko-fi, donators page), placed by
    -- placeHeaderButtons. Plain links blended into the page, so these are
    -- full buttons.
    local function supportButton(text, onClick)
        return Panel.SupportButton(header, text, onClick)
    end
    header.donators = supportButton(L["Top Donators"], function() Panel.Show(Panel.DONATORS) end)
    header.tip = supportButton(L["Tip Daylight"], function() Panel.ShowKofi() end)
    header.vip = supportButton(L["Be a VIP supporter"], function() Panel.ShowPatreon() end)
    header.desc:SetPoint("TOPLEFT", header.title, "BOTTOMLEFT", 0, -4)
    header.descHit = CreateFrame("Frame", nil, header)
    header.descHit:SetAllPoints(header.desc)
    header.descHit:EnableMouse(true)
    header.descHit:SetScript("OnEnter", function(self)
        local page = Options.GetPage(current)
        if page and page.desc then W.Tooltip(self, T(page.label), T(page.desc)) end
    end)
    header.descHit:SetScript("OnLeave", W.HideTooltip)
    -- Faint rule under the header, like Win.Lines.
    header.rule = header:CreateTexture(nil, "ARTWORK")
    header.rule:SetTexture("Interface\\Buttons\\WHITE8X8")
    header.rule:SetVertexColor(1, 1, 1, 0.06)
    header.rule:SetHeight(1)
    header.rule:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    header.rule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 48 - Panel.CONTENT_RIGHT, 0)

    resetPage = W.Button(header, L["Reset page"], 24)
    resetPage:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
    resetPage.fit = 96
    W.Confirm(resetPage, L["Reset page"], function()
        local page = Options.GetPage(current)
        if page then Options.ResetPage(page) end
    end)
    resetPage:HookScript("OnEnter", function()
        W.Tooltip(resetPage, L["Reset page"], L["Puts every setting on this page back to its default."])
    end)
    resetPage:HookScript("OnLeave", W.HideTooltip)

    -- "Test frame" switch for pages with preview parts. Shows a test sample
    -- of just that frame (DUI.SetTestSolo).
    testSwitch = CreateFrame("Frame", nil, header)
    testSwitch:SetSize(124, 24)
    testSwitch:EnableMouse(true)
    W.toggle(testSwitch, nil, {
        get = function() return DUI.testSolo ~= nil end,
        set = function(on)
            local page = Options.GetPage(current)
            DUI.SetTestSolo(on and page and page.preview or nil)
            Panel.Refresh()   -- reflect it if combat blocked the change
        end,
    })
    testSwitch.control:SetPoint("RIGHT", testSwitch, "RIGHT", 0, 0)
    testSwitch.label = W.Font(testSwitch, W.BODY, SIZE.body, C.text)
    testSwitch.label:SetPoint("RIGHT", testSwitch.control, "LEFT", -10, 0)
    testSwitch.label:SetText(L["Test frame"])
    local function tip()
        W.Tooltip(testSwitch, L["Test frame"], L["Shows a sample of just this frame while you edit it, and every change "
            .. "as you make it. Stays on across pages until you switch it off; combat ends it."])
    end
    for _, f in ipairs({ testSwitch, testSwitch.control }) do
        f:HookScript("OnEnter", tip)
        f:HookScript("OnLeave", W.HideTooltip)
    end
    testSwitch:Hide()

    -- Design mode, for pages whose preview has movable pieces. The preview
    -- grows into a bigger stage. Remembered per page.
    designSwitch = CreateFrame("Frame", nil, header)
    designSwitch:SetSize(134, 24)
    designSwitch:EnableMouse(true)
    W.toggle(designSwitch, nil, {
        get = function() return designPages[current] == true end,
        set = function(on) Panel.SetDesign(on) end,
    })
    designSwitch.control:SetPoint("RIGHT", designSwitch, "RIGHT", 0, 0)
    designSwitch.label = W.Font(designSwitch, W.BODY, SIZE.body, C.text)
    designSwitch.label:SetPoint("RIGHT", designSwitch.control, "LEFT", -10, 0)
    designSwitch.label:SetText(L["Design mode"])
    local function designTip()
        W.Tooltip(designSwitch, L["Design mode"], L["Drag the pieces of the preview to move them: each stays where you let go, "
            .. "or catches on a dot right beside it. Click one, and the arrow keys nudge it (Shift for bigger steps). "
            .. "Every move changes the same settings as the cards below."])
    end
    for _, f in ipairs({ designSwitch, designSwitch.control }) do
        f:HookScript("OnEnter", designTip)
        f:HookScript("OnLeave", W.HideTooltip)
    end
    designSwitch:Hide()
end

-- Saves a Design mode drag (Strip.New's onMove) the same way a card would.
local function saveMove(changes)
    local page = Options.GetPage(current)
    if not page then return end
    for _, c in ipairs(changes) do
        if c[1] ~= nil and c[2] ~= nil and not Options.Locked(page, { key = c[1] }) then
            DUI:Set(page.scope, Options.Key(page, c[1]), c[2])
        end
    end
end

local function buildScroll()
    -- Live sample between the header and the settings.
    sampleStrip = DUI.SampleStrip.New(frame, function(keys) Panel.JumpTo(keys) end, saveMove, function(keys)
        designPages[current] = nil
        Panel.JumpTo(keys)
    end)
    -- Arrow key nudges start from the current setting value.
    sampleStrip.onRead = function(key)
        local page = Options.GetPage(current)
        return page and DUI:Get(page.scope, Options.Key(page, key))
    end
    -- Zoom changes the preview height, so the page has to relayout.
    sampleStrip.onZoom = function() Panel.Refresh() end
    -- The added piece is selected, so Design mode's filter shows its card.
    sampleStrip.onAdded = function() Panel.Refresh() end
    -- While a grip is dragged, write straight into the saved table with no
    -- SettingChanged, or the real frames would relayout on every step.
    -- saveMove sends the final value on release.
    sampleStrip.onPreview = function(key, value)
        local page = Options.GetPage(current)
        local mod = page and DUI:GetModule(page.scope)
        if mod and type(mod.db) == "table" then DUI.DB.SetPath(mod.db, Options.Key(page, key), value) end
    end
    -- Same quiet write for a slider being dragged on a page with a preview.
    -- The slider saves for real on release (Options.Preview).
    Options.previewer = function(page, item, value)
        local mod = DUI:GetModule(page.scope)
        local into = page.scope == "general" and DUI.DB.General() or (mod and mod.db)
        if query ~= "" or page ~= Options.GetPage(current) or not sampleStrip:IsShown()
            or not sampleStrip.lastWidth or type(into) ~= "table" then
            return false
        end
        DUI.DB.SetPath(into, Options.Key(page, item.key), value)
        sampleStrip.Redraw(sampleStrip.lastWidth, sampleStrip.lastRoom)
        return true
    end
    -- One chip per card; picking one shows that card alone.
    chips = W.Chips(frame, function(card) Panel.Focus(card) end)
    -- Report a bug, at the right end of the home page's chips.
    bugButton = W.IconButton(frame, "ui-bug.png", L["Report a bug"], function()
        Panel.Toggle()
        if DUI.BugReport then DUI.BugReport.Show() end
    end, W.CHIP_HEIGHT)
    bugButton.icon:SetSize(Panel.BUG_ICON, Panel.BUG_ICON)
    bugButton:Hide()
    -- Tabs for long pages, shown instead of the chips.
    tabRow = CreateFrame("Frame", nil, frame)
    tabRow:SetHeight(W.TAB_H)
    tabRow.buttons = {}
    tabRow:Hide()

    scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetScript("OnSizeChanged", updateScrollBar)
    scrollBar = W.Scroll(scroll, { x = 12, onWheel = function() W.CloseMenu() end })
    scrollBar:HookScript("OnMouseDown", function() W.CloseMenu() end)

    -- Search results (Results.lua).
    results = DUI.OptionsResults.New(scroll, function(pageId, keys) Panel.OpenResult(pageId, keys) end)
    results:Hide()

    emptyText = W.Font(frame, W.BODY, SIZE.body, C.dim, "CENTER")
    emptyText:SetPoint("TOP", scroll, "TOP", 0, -60)
    emptyText:Hide()
end

-- Window scale (Ctrl + mouse wheel), saved along with its size.
Panel.SCALE_MIN, Panel.SCALE_MAX = 0.7, 1.3
function Panel.Scale()
    local s = DUI.DB.Root().optionsWindow
    local v = type(s) == "table" and tonumber(s.scale) or 1
    return math.max(Panel.SCALE_MIN, math.min(Panel.SCALE_MAX, v))
end

-- Screen size in the window's own units, since it may be scaled.
local function screen()
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    if type(sw) ~= "number" or sw <= 0 then sw = 1920 end
    if type(sh) ~= "number" or sh <= 0 then sh = 1080 end
    local k = Panel.Scale()
    return sw / k, sh / k
end

-- Saved window size, clamped to the screen.
local function clamp(w, h)
    local sw, sh = screen()
    w = math.max(Panel.MIN[1], math.min(sw, tonumber(w) or Panel.SIZE[1]))
    h = math.max(Panel.MIN[2], math.min(sh, tonumber(h) or Panel.SIZE[2]))
    return math.floor(w + 0.5), math.floor(h + 0.5)
end

local function savedSize()
    local s = DUI.DB.Root().optionsWindow
    if type(s) == "table" then return clamp(s.w, s.h) end
    return clamp(Panel.SIZE[1], Panel.SIZE[2])
end

local layoutContent, fillTabs

-- Corner resize grip (Win.Grip). Size is the start size plus mouse travel,
-- not StartSizing, which could jump to a huge size at the start. Clamped to
-- the screen with the top-left pinned. Panel.Resize saves it on release.
local function buildGrip()
    grip = DUI.Win.Grip(frame, { min = Panel.MIN, place = function() end,
        set = function(w, h) Panel.Resize(w, h) end })
end

local function build()
    frame = CreateFrame("Frame", "DaylightUIOptions", UIParent)
    -- Start hidden. A new frame is shown by default, so the first open
    -- would never fire OnShow and the fade-in would be skipped.
    frame:Hide()
    frame:SetScale(Panel.Scale())
    frame:SetSize(savedSize())
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnHide", function()
        W.CloseMenu()
        W.HideTooltip()
    end)
    Style.Shell(frame, { bgAlpha = 0.97 })
    frame.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
    frame.bg:SetColorTexture(C.window[1], C.window[2], C.window[3], 0.97)
    topLine = frame:CreateTexture(nil, "ARTWORK")
    topLine:SetTexture(Style.GRADIENT_FILE)
    topLine:SetHeight(2)
    -- Fade only, no lift: moving a window this full costs fps.
    -- Escape closes it through the motion kit's stand-in so it still fades.
    DUI.Motion.Window(frame)
    nav = Nav.New(frame, {
        Section = function(id) Panel.ShowSection(id) end,
        Page = function(id) Panel.Show(id) end,
        Search = function(text) Panel.Search(text) end,
        Unlock = function()
            if DUI.Movers.unlocked then DUI.Movers.Lock() else DUI.Movers.Unlock() end
        end,
        Discord = function() Panel.ShowDiscord() end,
    })
    buildHeader()
    buildScroll()
    buildGrip()
    -- Ctrl + mouse wheel scales it, like our other windows.
    DUI.Win.WheelScale(frame, Panel.Scale, function(v) Panel.SetScale(v) end, Panel.SCALE_MIN, Panel.SCALE_MAX)
    Panel.PadKeys()
    -- Reflow the page live while the corner is dragged.
    frame:SetScript("OnSizeChanged", function()
        if current then layoutContent() end
    end)
end

-- Stacks header, live sample (if any) and scroll area down the page area.
function layoutContent()
    local T = border()
    local left = T + Nav.RAIL + Nav.LIST + Panel.CONTENT_LEFT
    local cw = contentWidth()
    Panel.CONTENT_WIDTH = cw
    local top = Panel.TOP   -- same title offset as every window
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -top)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(T + 48), -top)
    top = top + Panel.HEADER - Panel.TOP
    header:SetHeight(Panel.HEADER - Panel.TOP)
    top = top + 12   -- space under the rule, matches Parts.Stack
    sampleStrip:ClearAllPoints()
    sampleStrip:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -top)
    sampleStrip:SetWidth(cw)
    if sampleStrip:IsShown() then top = top + sampleStrip:GetHeight() + Panel.SAMPLE_GAP end
    if chips:IsShown() then
        chips:ClearAllPoints()
        chips:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -top)
        bugButton:ClearAllPoints()
        bugButton:SetPoint("TOPRIGHT", frame, "TOPLEFT", left + cw, -top)
        local room = bugButton:IsShown() and bugButton:GetWidth() + W.CHIP_GAP or 0
        top = top + chips.Layout(cw - room) + Panel.CHIPS_GAP
    end
    if tabRow:IsShown() then
        tabRow:ClearAllPoints()
        tabRow:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -top)
        tabRow:SetWidth(cw)
        top = top + W.TAB_H + Panel.CHIPS_GAP
    end
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -top)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(T + Panel.CONTENT_RIGHT), T + 14)
    local pf = pageFrames[current]
    if pf and pf:GetWidth() ~= cw then
        pf:SetWidth(cw)
        pf.Layout(query)
    end
    updateScrollBar()
end

-- Places the rail and page list inside the border, whatever its thickness,
-- plus the gradient line on top.
local function layoutFrame()
    local T = border()
    nav.rail:ClearAllPoints()
    nav.rail:SetPoint("TOPLEFT", frame, "TOPLEFT", T, -T)
    nav.rail:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", T, T)
    nav.list:ClearAllPoints()
    nav.list:SetPoint("TOPLEFT", nav.rail, "TOPRIGHT", 0, 0)
    nav.list:SetPoint("BOTTOMLEFT", nav.rail, "BOTTOMRIGHT", 0, 0)
    frame.bg:ClearAllPoints()
    frame.bg:SetPoint("TOPLEFT", frame, "TOPLEFT", T, -T)
    frame.bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -T, T)
    topLine:ClearAllPoints()
    topLine:SetPoint("TOPLEFT", frame, "TOPLEFT", T, -T)
    topLine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -T, -T)
end

-- State for the nav: current page, and while searching the match counts
-- per section and page. hits is the same Options.Search the results use.
local function navState(hits)
    local page = Options.GetPage(current)
    local state = { sections = Options.Sections(), section = page and page.section, page = current }
    if query ~= "" then
        local byPage = {}
        for _, hit in ipairs(hits or Options.Search(query)) do
            byPage[hit.page.id] = (byPage[hit.page.id] or 0) + 1
        end
        state.sectionCounts, state.pageCounts = {}, {}
        for _, s in ipairs(state.sections) do
            local total = 0
            for _, p in ipairs(s.pages) do
                local n = byPage[p.id] or 0
                state.pageCounts[p.id] = n
                total = total + n
            end
            state.sectionCounts[s.id] = total
        end
    end
    return state
end

-- Support buttons only show on the home page. The description always gets
-- the full line.
local function placeDonators(on)
    header.donators:SetShown(on)
    header.tip:SetShown(on)
    header.vip:SetShown(on)
    header.desc:ClearAllPoints()
    header.desc:SetPoint("TOPLEFT", header.title, "BOTTOMLEFT", 0, -4)
    header.desc:SetPoint("RIGHT", header, "RIGHT", 0, 0)
end

local function fillHeader(page)
    placeDonators(page.id == "home")
    local section = sectionOf(page)
    header.title:SetText(T(page.label))
    local sectionLabel = section and section.label or ""
    header.section:SetText(sectionLabel ~= page.label and T(sectionLabel) or "")
    W.TextColor(header.section, Theme.Section(page.section).color)
    header.desc:SetText(T(page.desc or ""))
end

-- Fades in the header text and sample with an incoming page or results.
-- The old ones are removed instantly.
local function fadeInChrome()
    local M = DUI.Motion
    M.Fade(header.title, 0, 1, M.NORMAL)
    M.Fade(header.section, 0, 1, M.NORMAL)
    M.Fade(header.desc, 0, 1, M.NORMAL)
    if header.donators:IsShown() then M.Fade(header.donators, 0, 1, M.NORMAL) end
    if header.tip:IsShown() then M.Fade(header.tip, 0, 1, M.NORMAL) end
    if header.vip:IsShown() then M.Fade(header.vip, 0, 1, M.NORMAL) end
    if sampleStrip:IsShown() then M.Fade(sampleStrip, 0, 1, M.NORMAL) end
end

-- The empty-results line fades in once; further typing leaves it alone.
local function showEmpty(on)
    local fresh = on and not emptyText:IsShown()
    emptyText:SetShown(on)
    if fresh then DUI.Motion.Fade(emptyText, 0, 1, DUI.Motion.FAST) end
end

-- Empties the search box, which ends the search (Panel.Search).
local function clearSearch()
    if nav and (nav.searchBox:GetText() or "") ~= "" then nav.searchBox:SetText("") end
    Panel.Search("")
end

-- Ends the search without restoring the old page, because Panel.Show is
-- about to open another one.
local function dropSearch()
    query = ""
    results:Hide()
    -- The box's onChange calls Panel.Search(""), which does the rest.
    if nav and (nav.searchBox:GetText() or "") ~= "" then nav.searchBox:SetText("") end
end

-- Header buttons, right to left: Reset page, Test frame, Design mode, then
-- the home page's support buttons. All centered on the 24 px button row.
local function placeHeaderButtons()
    testSwitch:ClearAllPoints()
    local x = resetPage:IsShown() and -(resetPage:GetWidth() + 16) or 0
    testSwitch:SetPoint("TOPRIGHT", header, "TOPRIGHT", x, 0)
    if testSwitch:IsShown() then x = x - testSwitch:GetWidth() - 16 end
    designSwitch:ClearAllPoints()
    designSwitch:SetPoint("TOPRIGHT", header, "TOPRIGHT", x, 0)
    if designSwitch:IsShown() then x = x - designSwitch:GetWidth() - 16 end
    header.donators:ClearAllPoints()
    header.donators:SetPoint("RIGHT", header, "TOPRIGHT", x, -12)
    header.tip:ClearAllPoints()
    header.tip:SetPoint("RIGHT", header.donators, "LEFT", -10, 0)
    header.vip:ClearAllPoints()
    header.vip:SetPoint("RIGHT", header.tip, "LEFT", -10, 0)
end

-- ---------------------------------------------------------------------
-- Pages
-- ---------------------------------------------------------------------

-- Shows search results in place of the page. hits = Options.Search(query).
local function refreshResults(hits)
    local n = results.Fill(query, contentWidth(), Options.GetPage(current), hits)
    header.title:SetText(SEARCH or L["Search"])
    header.section:SetText("")
    placeDonators(false)
    header.desc:SetText(n == 1 and L["1 setting matches."] or string.format(L["%d settings match."], n))
    emptyText:SetText(string.format(L["No settings match \"%s\"."], query))
    showEmpty(n == 0)
    resetPage:Hide()
    testSwitch:Hide()
    designSwitch:Hide()
    chips:Hide()
    bugButton:Hide()
    tabRow:Hide()
end

-- Builds the tab row for a page and marks the current tab.
function fillTabs(pf, live)
    local gap = DUI.Win and DUI.Win.TAB_GAP or 14
    local x = 0
    for i, name in ipairs(live) do
        local b = tabRow.buttons[i]
        if not b then
            b = W.Tab(tabRow, "", { size = SIZE.body })
            b:SetScript("OnClick", function(self) Panel.SetTab(self.tab) end)
            tabRow.buttons[i] = b
        end
        b.tab = name
        b.text:SetText(T(name))
        b.FitWidth(8)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", tabRow, "TOPLEFT", x, 0)
        x = x + b:GetWidth() + gap
        b.Pick(pf.tab == name, b:IsVisible())
        b:Show()
    end
    for i = #live + 1, #tabRow.buttons do tabRow.buttons[i]:Hide() end
end

-- Re-reads every setting on the page (or the results) and updates the
-- surrounding chrome.
function Panel.Refresh()
    if not frame then return end
    local page = Options.GetPage(current)
    local pf = page and pageFrames[current]
    if not pf then return end
    nav.unlock.text:SetText(DUI.Movers.unlocked and L["Lock frames"] or L["Unlock frames"])
    nav.unlock.SetActive(DUI.Movers.unlocked == true)
    nav.SyncSetup()
    -- One search per keystroke serves both the counts and the results.
    local hits = query ~= "" and Options.Search(query) or nil
    nav.Layout(navState(hits))
    if query ~= "" then
        refreshResults(hits)
        layoutContent()
        return
    end
    pf.Refresh()
    pf.Layout("")
    emptyText:Hide()
    resetPage:SetShown(Options.HasValues(page))
    testSwitch:SetShown(page.preview ~= nil)
    testSwitch.control.Refresh()
    chips.Set(pf.cards, pf.focus)
    -- Only tabs with something to show right now.
    local live = {}
    if pf.tabs then
        for _, name in ipairs(pf.tabs) do
            for _, card in ipairs(pf.cards) do
                if card.tab == name and (card.count or 0) > 0 then live[#live + 1] = name; break end
            end
        end
        local on = false
        for _, name in ipairs(live) do on = on or name == pf.tab end
        if not on and live[1] then
            pf.SetTab(live[1])
            pf.Layout("")
        end
    end
    local tabbed = #live >= 2
    chips:SetShown(chips.count >= 2 and not tabbed and not pf.tabs)
    bugButton:SetShown(chips:IsShown() and current == "home")
    if tabbed then fillTabs(pf, live) end
    tabRow:SetShown(tabbed)
    local design = designPages[current] == true
    sampleStrip.SetDesign(design)
    sampleStrip.Redraw(contentWidth(), DUI.SampleStrip.Room(frame:GetHeight(), design))
    designSwitch:SetShown(sampleStrip:IsShown() and sampleStrip.Movable())
    designSwitch.control.Refresh()
    placeHeaderButtons()
    -- Design mode shows only the selected piece's cards, none until one is picked.
    local filter
    if design and designSwitch:IsShown() then
        filter = {}
        local part = sampleStrip.SelectedPart()
        for _, key in ipairs(part and part.keys or {}) do
            local card = pf.Find(key)
            if card then
                filter[card] = true
                if card.group.reveal then card.group.reveal(key) end
            end
        end
        chips:Hide()
        bugButton:Hide()
        tabRow:Hide()
        emptyText:SetText(DUI.SampleStrip.DESIGN_EMPTY)
        showEmpty(part == nil)
    end
    local was = pf.filter
    pf.SetFilter(filter)
    if filter or was then pf.Layout("") end
    layoutContent()
end

-- Gamepad support, modeled on the game's Settings window. Each row is a stop
-- (W.PadRow). A activates, Y resets to default, X picks a color pair's light
-- end, LB/RB switch tabs or pages, and the right stick scrolls.
-- This finds the page's first stop, where A from the page list lands.
function Panel.FirstStop()
    local pf = pageFrames[current]
    if not pf or not pf:IsVisible() then return nil end
    -- Cards are laid out top left first, so take the first row in view.
    for _, card in ipairs(pf.cards or {}) do
        for _, row in ipairs(card.rows or {}) do
            if row.padRow and row:IsVisible() then return row end
        end
    end
    -- Custom pages (Home, Profiles list) use their top-left button.
    local best, bestTop, bestLeft
    local function consider(f)
        if not f:IsVisible() then return end
        local top, left = f:GetTop(), f:GetLeft()
        if type(top) ~= "number" or type(left) ~= "number" then return end
        if not best or top > bestTop + 1 or (math.abs(top - bestTop) <= 1 and left < bestLeft) then
            best, bestTop, bestLeft = f, top, left
        end
    end
    local function walk(f)
        if f.padRow then return consider(f) end
        if f:IsObjectType("Button") and f:IsEnabled() and f:IsMouseEnabled() then return consider(f) end
        for _, child in ipairs({ f:GetChildren() }) do walk(child) end
    end
    walk(pf)
    return best
end

function Panel.PadEnter()
    DUI.Pad.Settle(Panel.FirstStop())
end

-- The rows of the page in view that the D-pad stops on.
function Panel.PadRows()
    local out = {}
    local pf = pageFrames[current]
    if not pf or not pf:IsVisible() then return out end
    for _, card in ipairs(pf.cards or {}) do
        for _, row in ipairs(card.rows or {}) do
            if row.padRow and row:IsVisible() then out[#out + 1] = row end
        end
    end
    return out
end

-- Left and right between settings go across to the setting beside this one,
-- as in the game's Settings window. Left of the first column is the page in
-- the list. Without this the game's guess often jumped up to the tabs.
-- Set as plain frame targets (the game's jump overrides) when the D-pad lands
-- on a row, so they follow whatever the page shows now.
Panel.COLUMN_SLACK = 20

local function aim(b, dir, target)
    if target then
        SmartNavigation_AddJumpNavigationOverride(b, dir, target)
    else
        SmartNavigation_ClearJumpNavigationOverridesInDirection(b, dir)
    end
end

-- The nearest row by height in the column next to x, on the given side (1 right, -1 left).
local function across(rows, row, side)
    local x, top = row:GetLeft(), row:GetTop()
    if type(x) ~= "number" or type(top) ~= "number" then return nil end
    local column
    for _, r in ipairs(rows) do
        local l = r:GetLeft()
        if type(l) == "number" and (l - x) * side > Panel.COLUMN_SLACK
            and (not column or (l - column) * side < 0) then column = l end
    end
    if not column then return nil end
    local best, gap
    for _, r in ipairs(rows) do
        local l, t = r:GetLeft(), r:GetTop()
        if type(l) == "number" and type(t) == "number" and math.abs(l - column) <= Panel.COLUMN_SLACK then
            local d = math.abs(t - top)
            if not best or d < gap then best, gap = r, d end
        end
    end
    return best
end

function Panel.PadAim(row)
    if InCombatLockdown() or type(SmartNavigation_AddJumpNavigationOverride) ~= "function"
        or type(SMART_NAV_INPUT_DIRECTION) ~= "table" then return end
    local D = SMART_NAV_INPUT_DIRECTION
    local rows = Panel.PadRows()
    aim(row, D.RIGHT, across(rows, row, 1))
    aim(row, D.LEFT, across(rows, row, -1) or Panel.PageButton(current))
end

-- Right from the page in the list goes into the page, like A.
function Panel.PadAimList(b)
    if InCombatLockdown() or type(SmartNavigation_AddJumpNavigationOverride) ~= "function"
        or type(SMART_NAV_INPUT_DIRECTION) ~= "table" then return end
    aim(b, SMART_NAV_INPUT_DIRECTION.RIGHT, Panel.FirstStop())
end

function Panel.PadKeys()
    frame.padScroll = scroll
    -- On open the D-pad starts on the current page in the list, like the game's
    -- Settings window (SmartNavPanelInfoAdded).
    frame.padFirst = function() return Panel.PageButton(current) end
    frame.padSelect = function(at)
        if not (at and at.padRow) then return nil end
        if not at.padA or at.disabled then return false end
        local t = at.item.type
        if t == "slider" then
            return at.padEditing and (DONE or L["Done"]) or L["Change"]
        elseif t == "toggle" then
            return Options.Get(at.page, at.item) == true and L["Turn off"] or L["Turn on"]
        elseif t == "dropdown" then
            return L["Choose"]
        elseif t == "color" then
            return COLOR or L["Color"]
        elseif t == "gradient" then
            return L["Dark end"]
        elseif t == "button" and at.control.text then
            return at.control.text:GetText()
        end
    end
    frame.padKeys = {
        { key = "X", label = L["Light end"], run = function(at) at.padX() end,
          when = function(at) return at ~= nil and at.padX ~= nil and not at.disabled end },
        { key = "Y", label = RESET or L["Reset"], run = function(at) Options.ResetItem(at.page, at.item) end,
          when = function(at)
              return at ~= nil and at.padRow == true and not at.disabled and at.reset ~= nil and at.reset:IsShown()
          end },
    }
    frame.padTabs = function()
        local list, at = {}, nil
        if tabRow:IsShown() then
            local pf = pageFrames[current]
            for _, b in ipairs(tabRow.buttons) do
                if b:IsShown() then
                    list[#list + 1] = b
                    if pf and b.tab == pf.tab then at = #list end
                end
            end
            frame.padTabsLabel = L["Tabs"]
            return list, at
        end
        local s = sectionOf(Options.GetPage(current) or {})
        for _, p in ipairs(s and s.pages or {}) do
            local b = Panel.PageButton(p.id)
            if b and b:IsShown() then
                list[#list + 1] = b
                if p.id == current then at = #list end
            end
        end
        frame.padTabsLabel = L["Pages"]
        return list, at
    end
end

-- A page's position in the full page list across sections. 0 if unlisted
-- (home).
local function listIndex(id)
    local n = 0
    for _, s in ipairs(Options.Sections()) do
        for _, p in ipairs(s.pages) do
            n = n + 1
            if p.id == id then return n end
        end
    end
    return 0
end

-- Parent for a page being built. With the controller UI on, build it off to
-- the side: the game rescans the whole window for every frame created inside
-- it (it hooks CreateFrame), and hundreds of frames froze the game for 5 s.
-- The finished page moves in and the game scans once.
function Panel.PageHome()
    if not DUI.Pad.On() then return scroll end
    if not Panel.offstage then
        Panel.offstage = CreateFrame("Frame", nil, UIParent)
        Panel.offstage:SetSize(1, 1)
        Panel.offstage:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", -64, -64)
    end
    return Panel.offstage
end

function Panel.Show(id)
    if not frame then build() end
    hiddenForUnlock = false
    -- Only slide when switching inside an open window. Opening has its own
    -- fade, and leaving search just swaps in place.
    local from = Panel.IsShown() and query == "" and current or nil
    if query ~= "" then dropSearch() end
    id = id or current or "home"
    if not Options.GetPage(id) then id = "home" end
    local page = Options.GetPage(id)
    if not page then return end
    W.CloseMenu()
    resetPage.Disarm()   -- don't carry an armed reset over to a new page
    current = id
    -- Page state first, e.g. which raid size the raid pages edit.
    if page.onShow then page.onShow() end
    layoutFrame()
    if not pageFrames[id] then pageFrames[id] = W.Page(Panel.PageHome(), page, contentWidth()) end
    for pid, pf in pairs(pageFrames) do pf:SetShown(pid == id) end
    pageFrames[id].SetFocus(nil)
    if pageFrames[id].tabs then pageFrames[id].SetTab(pageFrames[id].tabs[1]) end
    sampleStrip.SetPage(page)
    if pageFrames[id]:GetParent() ~= scroll then pageFrames[id]:SetParent(scroll) end
    scroll:SetScrollChild(pageFrames[id])
    scroll:SetVerticalScroll(0)
    -- Pages further down the list slide up from below, and vice versa.
    local switched = from and from ~= id
    if switched then
        local dir = listIndex(id) > listIndex(from) and 1 or -1
        DUI.Motion.SlideIn(pageFrames[id], 0, -Panel.SLIDE * dir)
    end
    fillHeader(page)
    lastPage[page.section] = id
    -- The test preview follows you to the next frame's page.
    if DUI.testSolo and page.preview then DUI.SetTestSolo(page.preview) end
    frame:Show()
    Panel.Refresh()
    DUI.Pad.Rescan(frame)
    DUI.Pad.Refresh(frame)   -- LB/RB now cycle this page's tabs or section pages
    if switched then fadeInChrome() end
end

-- Opens a section on its last shown page, or its first.
function Panel.ShowSection(id)
    local s = Options.Section(id)
    if not (s and s.pages[1]) then return end
    local want = lastPage[id]
    for _, p in ipairs(s.pages) do
        if p.id == want then return Panel.Show(want) end
    end
    return Panel.Show(s.pages[1].id)
end

-- With MIN_QUERY letters or more, results replace the page. Clearing the
-- search restores the page and its scroll position.
function Panel.Search(text)
    local q = string.lower(trim(text))
    if #q < Panel.MIN_QUERY then q = "" end
    if q == query then return end
    local was = query
    query = q
    W.CloseMenu()
    local pf = frame and pageFrames[current]
    if not pf then return end
    if query ~= "" then
        if was == "" then pageScroll = scroll:GetVerticalScroll() end
        pf:Hide()
        sampleStrip.SetPage(nil)
        results:Show()
        scroll:SetScrollChild(results)
        scroll:SetVerticalScroll(0)
        Panel.Refresh()
        -- Animate in once; more letters only refill it.
        if was == "" then
            DUI.Motion.SlideIn(results, 0, -Panel.SLIDE)
            fadeInChrome()
        end
        return
    end
    local page = Options.GetPage(current)
    results:Hide()
    pf:Show()
    scroll:SetScrollChild(pf)
    sampleStrip.SetPage(page)
    fillHeader(page)
    Panel.Refresh()
    scroll:SetVerticalScroll(math.min(scrollRange(scroll), pageScroll))
    -- The page animates back in.
    DUI.Motion.SlideIn(pf, 0, -Panel.SLIDE)
    fadeInChrome()
    updateScrollBar()
end

-- Opens a result heading's page at those settings.
function Panel.OpenResult(pageId, keys)
    Panel.Show(pageId)   -- also ends the search quietly
    Panel.JumpTo(keys)
end

-- Switches tabs; the cards slide in from the tab's side.
function Panel.SetTab(name)
    local pf = pageFrames[current]
    if not (pf and pf.tabs) or pf.tab == name then return end
    local from, to = 0, 0
    for i, t in ipairs(pf.tabs) do
        if t == pf.tab then from = i end
        if t == name then to = i end
    end
    pf.SetTab(name)
    scroll:SetVerticalScroll(0)
    Panel.Refresh()
    DUI.Motion.SlideIn(pf, Panel.SLIDE * (to > from and 1 or -1), 0)
end

-- Shows one card on its own, or all of them with nil. Picking the card
-- that's already focused goes back to all.
function Panel.Focus(card)
    local pf = pageFrames[current]
    if not pf then return end
    if card ~= nil and card == pf.focus then card = nil end
    local changed = card ~= pf.focus
    pf.SetFocus(card)
    scroll:SetVerticalScroll(0)
    Panel.Refresh()
    -- Animate the cards in like a page.
    if changed and pf:IsVisible() then DUI.Motion.SlideIn(pf, 0, -Panel.SLIDE) end
end

-- Jumps to settings, e.g. from a click on the live sample. If they all sit in
-- one card, that card shows alone. Scrolls to the first one and highlights
-- the rows. Clears a search that would hide them. A setting that's currently
-- hidden (it depends on another) scrolls to its card instead.
-- Returns the highlighted rows.
function Panel.JumpTo(keys)
    local pf = pageFrames[current]
    if not pf then return {} end
    if query ~= "" then clearSearch() end
    local holder, many = nil, false
    for _, key in ipairs(keys) do
        local card = pf.Find(key)
        -- Picker cards: select the thing the setting belongs to.
        if card and card.group.reveal then card.group.reveal(key) end
        if card then
            if holder and card ~= holder then many = true end
            holder = holder or card
        end
    end
    -- On a tabbed page, switch to the first setting's tab with all cards.
    if pf.tabs and holder then pf.SetTab(holder.tab) end
    pf.SetFocus((chips.count >= 2 and not many and not pf.tabs) and holder or nil)
    Panel.Refresh()
    local rows, at = {}, nil
    for _, key in ipairs(keys) do
        local card, row = pf.Find(key)
        if card and card:IsShown() then
            local y = card.offsetY or 0
            if row:IsShown() then
                y = y + (row.offsetY or 0)
                rows[#rows + 1] = row
            end
            if not at or y < at then at = y end
        end
    end
    if at then
        local max = scrollRange(scroll)
        scroll:SetVerticalScroll(math.min(max, math.max(0, at - Panel.JUMP_MARGIN)))
        updateScrollBar()
    end
    W.Flash(rows)
    return rows
end

-- Applies a new size after a grip drag: clamped, saved per account, page
-- reflowed.
function Panel.Resize(w, h)
    if not frame then build() end
    w, h = clamp(w, h)
    frame:SetSize(w, h)
    local k = Panel.Scale()
    DUI.DB.Root().optionsWindow = { w = w, h = h, scale = k ~= 1 and k or nil }
    if current then
        layoutFrame()
        Panel.Refresh()
    end
end

-- Rescaling keeps the window centered where it was, and shrinks it if it
-- no longer fits the screen.
function Panel.SetScale(v)
    if not frame then build() end
    local old = frame:GetScale()
    local cx, cy = frame:GetCenter()
    local root = DUI.DB.Root()
    local s = type(root.optionsWindow) == "table" and root.optionsWindow or {}
    root.optionsWindow = s
    s.scale = v ~= 1 and v or nil
    v = Panel.Scale()
    frame:SetScale(v)
    if type(cx) == "number" and type(cy) == "number" then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx * old / v, cy * old / v)
    end
    local w, h = frame:GetWidth(), frame:GetHeight()
    local cw, ch = clamp(w, h)
    if cw ~= math.floor(w + 0.5) or ch ~= math.floor(h + 0.5) then Panel.Resize(cw, ch) end
end

function Panel.Toggle()
    if Panel.IsShown() then
        DUI.Motion.Vanish(frame)
    else
        Panel.Show()
    end
end

-- A window that's fading out counts as closed, so a toggle reopens it.
function Panel.IsShown() return frame ~= nil and DUI.Motion.Shown(frame) end
function Panel.Current() return current end
function Panel.Frame() return frame end
function Panel.PageFrame(id) return pageFrames[id or current] end
function Panel.ResetButton() return resetPage end
function Panel.TestSwitch() return testSwitch end
function Panel.DesignSwitch() return designSwitch end

-- Design mode for the current page, remembered for the session.
function Panel.SetDesign(on)
    if not current then return end
    designPages[current] = on == true or nil
    Panel.Refresh()
end
function Panel.Strip() return sampleStrip end
function Panel.Chips() return chips end
function Panel.BugButton() return bugButton end
function Panel.Tabs() return tabRow end
function Panel.Results() return results end
function Panel.EmptyText() return emptyText end
function Panel.Header() return header end
function Panel.Nav() return nav end
function Panel.NavButton(sectionId) return nav and nav.sectionButtons[sectionId] end
function Panel.PageButton(pageId) return nav and nav.pageButtons[pageId] end

local function refreshIfShown()
    if Panel.IsShown() then Panel.Refresh() end
end

-- General changes trigger a style repaint next frame, and StyleChanged below
-- refreshes the window then, so skip it here to avoid doing it twice. In
-- combat the repaint is deferred, so refresh now. Settings marked
-- DUI.NoRepaint also refresh here, or their switches never show the click.
--
-- Unlocking hides the window so it's not in the way, and locking again puts
-- it back where it was. Opening the window while unlocked cancels that.
DUI.On("SettingChanged", function(scope, path)
    if scope == "general" and not DUI.NoRepaint(path) and not InCombatLockdown() then return end
    refreshIfShown()
end)
DUI.On("UnlockChanged", function(unlocked)
    if unlocked then
        if Panel.IsShown() then
            local pf = pageFrames[current]
            hiddenForUnlock, hiddenPage, hiddenScroll = true, current, scroll:GetVerticalScroll()
            hiddenTab, hiddenFocus = pf and pf.tab, pf and pf.focus
            DUI.Motion.Vanish(frame)
        end
    elseif hiddenForUnlock then
        hiddenForUnlock = false
        Panel.Show(hiddenPage)
        -- Show resets to the first tab with every card, so restore what was open.
        local pf = pageFrames[current]
        if pf and current == hiddenPage then
            if pf.tabs and hiddenTab then pf.SetTab(hiddenTab) end
            pf.SetFocus(hiddenFocus)
            Panel.Refresh()
        end
        scroll:SetVerticalScroll(hiddenScroll)
        updateScrollBar()
    else
        refreshIfShown()
    end
end)
DUI.On("TestModeChanged", refreshIfShown)
DUI.On("StyleChanged", function()
    if Panel.IsShown() then
        layoutFrame()
        Panel.Refresh()
    end
end)
DUI.On("OptionsChanged", function()
    if Panel.IsShown() then nav.Layout(navState()) end
end)

-- ---------------------------------------------------------------------
-- Entry points: /dui, the addon compartment and the game's AddOns settings.
-- ---------------------------------------------------------------------

DUI.RegisterCommand("", Panel.Toggle, L["/dui - open options"])

function DaylightUI_OpenOptions() Panel.Toggle() end

DUI.On("Login", function()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    pcall(function()
        local f = CreateFrame("Frame")
        local b = W.Button(f, L["Open DaylightUI options"], 28)
        b:SetWidth(220)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
        b:SetScript("OnClick", function()
            if SettingsPanel and HideUIPanel then HideUIPanel(SettingsPanel) end
            Panel.Show()
        end)
        Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(f, "DaylightUI"))
    end)
end)
