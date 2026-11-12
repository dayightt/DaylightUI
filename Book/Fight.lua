-- Keeps this spellbook usable in combat (setting fightBook) instead of
-- handing over to the game's book. The window itself is never protected, so
-- it can still open, fade and refresh in combat. Everything that must be
-- secure lives on a separate layer, Fight.h, parented to UIParent and never
-- anchored to the window, since a protected child would make the window
-- protected too.
--
--   - One secure cast button per spell row, laid out on PLAYER_REGEN_DISABLED
--     (the last moment that's allowed). The mouse wheel scrolls them in a
--     secure snippet and reports the offset back (Fight.Scrolled) so the
--     visible rows follow.
--   - The spellbook and talent keys get override bindings to secure toggles
--     that open that page, or close it if it's already showing.
--   - The close button, the tabs and Escape each get a secure button on top,
--     so the layer always knows whether the book is open.
--
-- Insecure code can't update secure attributes in combat, so the cast list is
-- frozen when the fight starts: search, filters, folds and the ranks switch
-- wait (Spells.Freeze), and the window can't move or resize (Win.Held).
-- Dragging spells to bars needs the game's book; turning the setting off
-- restores that.

local _, DUI = ...
DUI.Book = DUI.Book or {}   -- the book window's own namespace
local ns = DUI.Book
local Win = DUI.Win

local Fight = {}
ns.Fight = Fight

Fight.NAME = "DaylightUIBookFight"
-- Binding names from Bindings_Camelot.xml and the page each opens.
Fight.KEYS = { { "TOGGLESPELLBOOK", "spells" }, { "TOGGLEPETBOOK", "spells" }, { "TOGGLETALENTS", "talents" } }
Fight.PAGES = { "spells", "talents", "training" }
Fight.TOGGLES = { spells = Fight.NAME .. "Spells", talents = Fight.NAME .. "Talents" }

-- Shows the close button, tabs and list for the current page, and binds
-- Escape to close while open.
Fight.REFRESH = [[
    local open, page = self:GetAttribute("open"), self:GetAttribute("page") or "spells"
    local a, close, list = self:GetFrameRef("anchor"), self:GetFrameRef("close"), self:GetFrameRef("list")
    if open then
        close:ClearAllPoints()
        close:SetPoint("TOPLEFT", a, "TOP", close:GetAttribute("x-" .. page) or 0, close:GetAttribute("y") or 0)
        close:Show()
        self:SetBindingClick(true, "ESCAPE", close:GetName())
    else
        close:Hide()
        self:ClearBinding("ESCAPE")
    end
    for i = 1, self:GetAttribute("tabs") or 0 do
        local t = self:GetFrameRef("tab" .. i)
        if open then
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", a, "TOP", t:GetAttribute("x-" .. page) or 0, t:GetAttribute("y") or 0)
            t:Show()
        else
            t:Hide()
        end
    end
    if open and page == "spells" then list:Show() else list:Hide() end
]]

-- Open on this page, or close if it's already showing.
Fight.TOGGLE = [[
    local h = self:GetFrameRef("h")
    local want = self:GetAttribute("page")
    if h:GetAttribute("open") and h:GetAttribute("page") == want then
        h:SetAttribute("open", false)
    else
        h:SetAttribute("open", true)
        h:SetAttribute("page", want)
    end
    h:RunAttribute("refresh")
]]
Fight.CLOSE = [[
    local h = self:GetFrameRef("h")
    h:SetAttribute("open", false)
    h:RunAttribute("refresh")
]]
Fight.TAB = [[
    local h = self:GetFrameRef("h")
    h:SetAttribute("page", self:GetAttribute("page"))
    h:RunAttribute("refresh")
]]

-- Position the cast buttons for scroll offset `at`, clipped to the visible
-- part of each row and hidden when the row is out of view.
Fight.LAY = [[
    local at, view = self:GetAttribute("at") or 0, self:GetAttribute("view") or 0
    for i = 1, self:GetAttribute("n") or 0 do
        local b = self:GetFrameRef("b" .. i)
        local y, h = (b:GetAttribute("y") or 0) - at, b:GetAttribute("h") or 0
        local top, bottom = math.max(y, 0), math.min(y + h, view)
        if bottom - top >= 1 then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", "$parent", "TOPLEFT", b:GetAttribute("x") or 0, -top)
            b:SetHeight(bottom - top)
            b:Show()
        else
            b:Hide()
        end
    end
]]
Fight.WHEEL = [[
    local at = (self:GetAttribute("at") or 0) - delta * (self:GetAttribute("step") or 40)
    at = math.max(0, math.min(self:GetAttribute("max") or 0, at))
    if at == self:GetAttribute("at") then return end
    self:SetAttribute("at", at)
    self:RunAttribute("lay")
    self:CallMethod("Scrolled", at)
]]

-- Off with the controller UI, which always uses the game's windows.
function Fight.On()
    return Fight.h ~= nil and ns.Setting("fightBook") ~= false and not (DUI.Pad and DUI.Pad.On())
end

-- True while the secure layer is in charge and the book is open.
function Fight.Holds()
    return Fight.armed == true and Fight.h:GetAttribute("open") == true
end

local function above(f)
    local strata = f:GetFrameStrata()
    for i, s in ipairs(Win.CAST_STRATA) do
        if s == strata then return Win.CAST_STRATA[math.min(i + 1, #Win.CAST_STRATA)] end
    end
    return "HIGH"
end

local function run(target, name, ...)
    local fn = target and target:GetScript(name)
    if fn then fn(target, ...) end
end

-- Secure button over one of the window's buttons. It forwards hover and,
-- after the snippet, the click, so the real button still animates and plays its sound.
local function cover(h, name, target, snippet)
    local b = CreateFrame("Button", name, h, "SecureHandlerClickTemplate")
    b:RegisterForClicks("LeftButtonUp")
    b:SetAttribute("_onclick", snippet)
    SecureHandlerSetFrameRef(b, "h", h)
    b:SetScript("OnEnter", function() run(target, "OnEnter") end)
    b:SetScript("OnLeave", function() run(target, "OnLeave") end)
    b:SetScript("PostClick", function(_, button) if target then target:Click(button) end end)
    b:Hide()
    return b
end

-- Created on demand as the list grows.
local function castButton(i)
    local list = Fight.h.list
    local b = Fight.casts[i]
    if b then return b end
    b = CreateFrame("Button", Fight.NAME .. "Cast" .. i, list, "SecureActionButtonTemplate")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetAttribute("useOnKeyDown", false)   -- cast on release, like Win.Caster
    b:SetScript("OnEnter", function(self) if self.row and ns.Spells then ns.Spells.Enter(self.row) end end)
    b:SetScript("OnLeave", function(self) if self.row and ns.Spells then ns.Spells.Leave(self.row) end end)
    -- The secure click only casts unmodified clicks; modified ones (links) go here.
    b:SetScript("PostClick", function(self, button) if self.row and ns.Spells then ns.Spells.Modified(self.row, button) end end)
    b:Hide()
    SecureHandlerSetFrameRef(list, "b" .. i, b)
    Fight.casts[i] = b
    return b
end

-- Built with the window, out of combat. Nothing shows until combat starts.
function Fight.Build(f)
    if Fight.h then return end
    -- After a /reload in combat, secure frames can't be created yet. Until
    -- it's built, Fight.On is false and the game's book is used.
    if InCombatLockdown() then
        DUI.AfterCombat(function() Fight.Build(f) end, "bookFight")
        return
    end
    local ok, h = pcall(CreateFrame, "Frame", Fight.NAME, UIParent, "SecureHandlerBaseTemplate")
    if not ok or type(h) ~= "table" then return end
    Fight.h, Fight.casts = h, {}
    h:SetAllPoints(UIParent)
    h:EnableMouse(false)
    h:SetFrameStrata(above(f))
    h:SetAttribute("refresh", Fight.REFRESH)
    h:SetAttribute("open", false)
    h.anchor = CreateFrame("Frame", nil, h, "SecureHandlerBaseTemplate")
    h.anchor:SetSize(1, 1)
    SecureHandlerSetFrameRef(h, "anchor", h.anchor)
    h.close = cover(h, Fight.NAME .. "Close", f.close, Fight.CLOSE)
    SecureHandlerSetFrameRef(h, "close", h.close)
    h.tabs = {}
    for i, tab in ipairs(f.tabs or {}) do
        local t = cover(h, Fight.NAME .. "Tab" .. i, tab, Fight.TAB)
        t:SetAttribute("page", tab.id)
        h.tabs[i] = t
        SecureHandlerSetFrameRef(h, "tab" .. i, t)
    end
    h:SetAttribute("tabs", #h.tabs)
    h.toggles = {}
    for page, name in pairs(Fight.TOGGLES) do
        local t = CreateFrame("Button", name, h, "SecureHandlerClickTemplate")
        t:RegisterForClicks("AnyDown")   -- open on key press, like the game
t:SetAttribute("_onclick", Fight.TOGGLE)
        t:SetAttribute("page", page)
        SecureHandlerSetFrameRef(t, "h", h)
        t:SetScript("PostClick", function() Fight.Follow() end)
        t:SetSize(1, 1)
        t:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
        t:EnableMouse(false)   -- clicked by bindings only
        h.toggles[page] = t
    end
    local list = CreateFrame("Frame", nil, h, "SecureHandlerMouseWheelTemplate")
    list:SetClipsChildren(true)
    list:EnableMouse(false)   -- leave hover to the rows, only take the wheel
    list:EnableMouseWheel(true)
    list:SetAttribute("lay", Fight.LAY)
    list:SetAttribute("_onmousewheel", Fight.WHEEL)
    list.Scrolled = function(_, at) Fight.Scrolled(at) end
    list:Hide()
    h.list = list
    SecureHandlerSetFrameRef(h, "list", list)
    f.held = function() return Fight.armed == true end
    -- Safety net: if the window closes behind the layer's back, an open layer
    -- would leave invisible cast buttons on screen, so reopen the window.
    f:HookScript("OnHide", function()
        if Fight.Holds() and not Win.IsOpen(f) then ns.Window.Open(Fight.h:GetAttribute("page")) end
    end)
end

-- Pin the layer to the window's top center so the close button, tabs and
-- list line up on every page.
local function anchorTo(f)
    local p, rel, rp, x, y = f:GetPoint(1)
    if p ~= "TOP" or (rel ~= nil and rel ~= UIParent) or type(x) ~= "number" or type(y) ~= "number" then return false end
    Fight.point = { rp or "TOP", x, y }
    local h = Fight.h
    h:SetScale(f:GetScale() or 1)
    h.anchor:ClearAllPoints()
    h.anchor:SetPoint("TOP", UIParent, rp or "TOP", x, y)
    return true
end

-- Precompute close and tab positions per page from each page's width,
-- matching Win.Header and Win.Tabs.
local function layHeader(f)
    local h = Fight.h
    local cw, ch = f.close:GetWidth(), f.close:GetHeight()
    local cy = Win.CloseY(f.spec and f.spec.compact)
    h.close:SetSize(cw, ch)
    h.close:SetAttribute("y", cy)
    local tabY = {}
    for i, tab in ipairs(f.tabs or {}) do
        local tw, th = tab:GetWidth(), tab:GetHeight()
        h.tabs[i]:SetSize(tw, th)
        tabY[i] = cy - ch / 2 + th / 2
        h.tabs[i]:SetAttribute("y", tabY[i])
    end
    for _, page in ipairs(Fight.PAGES) do
        local w = ns.Window.PageSize(page)
        local left = w / 2 + Win.CLOSE_X - cw
        h.close:SetAttribute("x-" .. page, left)
        for i = #h.tabs, 1, -1 do
            left = left - Win.TAB_GAP - f.tabs[i]:GetWidth()
            h.tabs[i]:SetAttribute("x-" .. page, left)
        end
    end
end

-- Set up cast buttons from Spells.Rows at the spells page's size.
local function layList(f)
    local h, S = Fight.h, ns.Spells
    local page = f.pages.spells
    if not (page and S) then return false end
    local w, ht = ns.Window.PageSize("spells")
    local s = page.stack
    local side = s.side or Win.Parts.EDGE
    local view = ht - (Win.HEADER + 1) - S.TOP - S.FOOT
    local list = h.list
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", h.anchor, "TOP", -w / 2 + side, -(Win.HEADER + 1) - S.TOP)
    list:SetSize(w - 2 * side, view)
    local rows = S.Rows(page)
    local cast = ns.Cast
    for i, r in ipairs(rows) do
        local b = castButton(i)
        local attrs = cast.Attributes(r.row.cell) or {}
        for _, key in ipairs(Win.CAST_KEYS) do b:SetAttribute(key, attrs[key]) end
        b.row = r.row
        b:SetWidth(r.w)
        b:SetAttribute("x", r.x)
        b:SetAttribute("y", r.y)
        b:SetAttribute("h", r.h)
    end
    for i = #rows + 1, #Fight.casts do
        local b = Fight.casts[i]
        b.row = nil
        for _, key in ipairs(Win.CAST_KEYS) do b:SetAttribute(key, nil) end
        b:Hide()
    end
    local max = math.max(0, (s.height or 0) - view)
    list:SetAttribute("n", #rows)
    list:SetAttribute("view", view)
    list:SetAttribute("max", max)
    list:SetAttribute("step", Win.Parts.WHEEL)
    list:SetAttribute("at", math.max(0, math.min(max, s:Scrolled())))
    SecureHandlerExecute(list, [[ self:RunAttribute("lay") ]])
    return true
end

-- Runs on PLAYER_REGEN_DISABLED, while protected changes are still allowed.
-- Returns false when the game's book should take over for this fight.
function Fight.Arm()
    if Fight.armed then return true end
    if not Fight.On() then return false end
    local W = ns.Window
    local f = W.frame
    if not f then return false end
    local open = Win.IsOpen(f)
    if open then Win.Feel.Settle(f) else W.Place(f) end
    if not anchorTo(f) then return false end
    -- Lay out the list at the spells page's size, at the window's position.
    if ns.Spells then ns.Spells.Prepare(f) end
    if not layList(f) then return false end
    layHeader(f)
    local h = Fight.h
    h:SetAttribute("open", open)
    h:SetAttribute("page", f.current or "spells")
    SecureHandlerExecute(h, [[ self:RunAttribute("refresh") ]])
    for _, k in ipairs(Fight.KEYS) do
        local keys = { GetBindingKey(k[1]) }
        for _, key in ipairs(keys) do
            if type(key) == "string" and key ~= "" then SetOverrideBindingClick(h, true, key, Fight.TOGGLES[k[2]]) end
        end
    end
    Fight.armed = true
    if ns.Spells then ns.Spells.Freeze(true) end
    return true
end

-- After combat: release the key bindings and hand the list back to the
-- hover caster. The window stays as it is.
function Fight.Disarm()
    if not Fight.armed then return false end
    Fight.armed = false
    local h = Fight.h
    ClearOverrideBindings(h)
    h:SetAttribute("open", false)
    h.close:Hide()
    for _, t in ipairs(h.tabs) do t:Hide() end
    h.list:Hide()
    Fight.point = nil
    if ns.Spells then ns.Spells.Freeze(false) end
    return true
end

-- In combat the window opens where the layer is pinned. Returns false when
-- not armed.
function Fight.Place(f)
    local p = Fight.armed and Fight.point
    if not p then return false end
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, p[1], p[2], p[3])
    return true
end

-- After a secure toggle, sync the window to the layer's state.
function Fight.Follow()
    local W = ns.Window
    local f = W.frame
    local h = Fight.h
    if h:GetAttribute("open") then
        local page = h:GetAttribute("page") or "spells"
        if not (Win.IsOpen(f) and f.current == page) then W.Open(page) end
    else
        W.Close()
    end
end

-- The secure list scrolled; scroll the visible list to match.
function Fight.Scrolled(at)
    if ns.Spells then ns.Spells.ScrollTo(at) end
end
