-- The character window: header (name, level, tabs, close) and a page host.
-- It's anchored to the parked game window, so it opens in the game's usual
-- panel spot. Follow.lua decides when it opens and closes.
--
-- Also the module wiring: build, settings and events. Events are registered
-- only while open and batched to one update per frame.

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char
local L = DUI.L
local Style = DUI.Style

local Window = {}
ns.Window = Window

Window.NAME = "DaylightUICharacter"
-- Header metrics, from Win.Header.
Window.HEADER = DUI.Win.HEADER
Window.W, Window.W_ICONS, Window.H = 834, 690, 482 + Window.HEADER
Window.EDGE = DUI.Win.EDGE
Window.GAP = 20            -- space before the next window (Follow.WriteWidth)
Window.TAB_MIN = 30
Window.WHITE = "Interface\\Buttons\\WHITE8X8"

-- Pages in tab order, with the game's frame for each (its
-- CharacterFrame.activeSubframe value). Pet has none: the game shows the pet as
-- a side tab inside its Character page, so the game's window stays where it was.
Window.PAGES = {
    { id = "character", label = L["Character"], frame = "PaperDollFrame" },
    { id = "pet", label = L["Pet"] },
    { id = "reputation", label = L["Reputation"], frame = "ReputationFrame" },
    { id = "skills", label = L["Skills"], frame = "SkillsFrame" },
    { id = "pvp", label = L["PvP"], frame = "PVPRankFrame" },
    { id = "currency", label = L["Currency"], frame = "TokenFrame" },
    { id = "statistics", label = L["Statistics"], frame = "StatisticsFrame" },
}

Window.EVENTS = { "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "UPDATE_INVENTORY_DURABILITY", "UNIT_STATS",
    "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER", "UNIT_ATTACK_SPEED", "UNIT_DAMAGE", "UNIT_RANGEDDAMAGE",
    "UNIT_RESISTANCES", "COMBAT_RATING_UPDATE", "PLAYER_LEVEL_UP", "KNOWN_TITLES_UPDATE", "EQUIPMENT_SETS_CHANGED",
    "CURSOR_CHANGED", "CURRENT_SPELL_CAST_CHANGED", "UNIT_MODEL_CHANGED", "GET_ITEM_INFO_RECEIVED", "PLAYER_REGEN_ENABLED",
    "PLAYER_REGEN_DISABLED", "PLAYER_MOUNT_DISPLAY_CHANGED" }   -- mounting changes movement speed

-- id -> page definition.
Window.pages = {}

function ns.Setting(key) return ns.module and ns.module.db and ns.module.db[key] end

function Window.Register(id, def) Window.pages[id] = def end
function Window.HasPage(id) return Window.pages[id] ~= nil end
function Window.Width() return ns.Setting("names") == false and Window.W_ICONS or Window.W end

function Window.PageInfo(id)
    for _, p in ipairs(Window.PAGES) do if p.id == id then return p end end
end

-- A tab shows only for pages this character has.
function Window.TabShown(id)
    local def = Window.pages[id]
    if not def then return false end
    if def.Available then return def.Available() == true end
    return not ns.Follow or ns.Follow.Available(id)
end

local function sound(key)
    local id = SOUNDKIT and SOUNDKIT[key]
    if id and type(PlaySound) == "function" then pcall(PlaySound, id) end
end

-- The dragged position, saved per profile in the module's `spot` (Window.spot,
-- created in Window.Build).
local function spot() return Window.spot and Window.spot.Get() end

-- Saved on drag. Nothing else needs refreshing.
function Window.SaveSpot(x, y) Window.spot.Save(x, y) end

-- Right-click the header (or /dui reset) to return to the game's spot. The
-- window holds the game's slot buttons, so it only moves out of combat. Opening
-- doesn't re-place it, so a closed window is moved now too.
function Window.ResetSpot()
    if not (Window.spot and Window.spot.Reset()) then return end
    if ns.window and not Window.IsOpen() then
        DUI.AfterCombat(function() Window.Place(ns.window) end, "characterPlace")
    end
end

-- The dragged spot, else the game's left panel spot via the parked window.
function Window.Place(f)
    local s = spot()
    if s then return DUI.Win.PlaceTop(f, s[1], s[2]) end
    f:ClearAllPoints()
    if type(CharacterFrame) == "table" then
        f:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 0, 0)
    else
        f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    end
end

local function tabButton(f, page)
    local b = DUI.Widgets.Tab(f, page.label, { size = DUI.Win.TAB_SIZE,
        paintLine = function(t) ns.Colors.Tab(t, 1) end })
    b.id = page.id
    b:SetScript("OnClick", function(self) if ns.Follow then ns.Follow.Select(self.id) end end)
    return b
end

function Window.BuildHeader(f)
    -- Title is your name, the sub line is your level. The X closes through Follow.Close.
    DUI.Win.Header(f, { onClose = function() if ns.Follow then ns.Follow.Close() else Window.Close() end end })
    f.nameText = f.title
    -- Clicking your name opens the title menu. PaintHeader sizes it to the name.
    f.nameButton = CreateFrame("Button", nil, f)
    f.nameButton:SetPoint("TOPLEFT", f.nameText, "TOPLEFT", 0, 0)
    f.nameButton:SetPoint("BOTTOMLEFT", f.nameText, "BOTTOMLEFT", 0, 0)
    f.nameButton:SetWidth(1)
    f.nameButton:SetScript("OnClick", function(self) if ns.Menus then ns.Menus.Titles(self) end end)

    f.tabs = {}
    for _, p in ipairs(Window.PAGES) do f.tabs[#f.tabs + 1] = tabButton(f, p) end
end

-- Lays out visible tabs right to left from the X.
function Window.LayoutTabs()
    local f = ns.window
    local right = f.close
    for i = #f.tabs, 1, -1 do
        local b = f.tabs[i]
        local on = Window.TabShown(b.id)
        b:SetShown(on)
        if on then
            b.FitWidth(4, Window.TAB_MIN)
            b:ClearAllPoints()
            b:SetPoint("RIGHT", right, "LEFT", -DUI.Win.TAB_GAP, 0)
            right = b
        end
    end
    -- Keep the name and level line clear of the tabs.
    if right ~= f.close then
        f.title:SetPoint("RIGHT", right, "LEFT", -DUI.Win.TAB_GAP, 0)
        f.sub:SetPoint("RIGHT", right, "LEFT", -DUI.Win.TAB_GAP, 0)
    end
end

-- Highlights the selected tab with its underline, in the color picked in options.
function Window.PaintTabs()
    local f = ns.window
    if not f then return end
    for _, b in ipairs(f.tabs) do b.Pick(b.id == f.current, true) end
end

function Window.PaintHeader()
    local f = ns.window
    local className, token = UnitClass("player")
    f.nameText:SetText(DUI.UnitName("player", "character") or "")   -- first and last name, per its own setting
    if token then f.nameText:SetTextColor(Style.ClassColor(token)) else Style.InkText(f.nameText, "VALUE") end
    local w = f.nameText:GetStringWidth()
    f.nameButton:SetWidth(type(w) == "number" and math.max(1, w) or 1)
    local race = UnitRace and UnitRace("player") or ""
    local class = className and ns.Colors.Wrap(className, Style.ClassColor(token)) or ""
    f.sub:SetText(string.format(L["Level %s %s %s"], ns.Colors.Wrap(tostring(UnitLevel("player") or 1), Style.Pop()), race or "", class))
end

-- Builds a page's frame on first use.
function Window.EnsurePage(id)
    local f, def = ns.window, Window.pages[id]
    if not (f and def) then return nil end
    local page = f.pages[id]
    if not page then
        page = CreateFrame("Frame", nil, f.host)
        page:SetAllPoints(f.host)
        page:Hide()
        f.pages[id] = page
        def.Build(page)
        if def.Place then def.Place(page) end
    end
    return page
end

-- force: the window is opening, so animate the page in even if it's already current.
function Window.ShowPage(id, force)
    local f = ns.window
    if not f then return end
    if not Window.pages[id] then id = "character" end
    local def = Window.pages[id]
    if not def then return end
    local page = Window.EnsurePage(id)
    if f.current == id and page:IsShown() and not force then return end
    local old = f.current and f.pages[f.current]
    if old and old ~= page then old:Hide() end
    f.current = id
    page:Show()
    Window.PaintTabs()
    if def.Open then def.Open(page) end
    if def.Refresh then def.Refresh(page) end
    -- Switching tabs while open: the page rises in, the header stays put.
    if Window.IsOpen() and old and old ~= page then Window.PageIn(page, 0) end
end

-- Open and close motion from the window kit (Feel), stepped by hand. Never use
-- an alpha animation group here: the client applies an ancestor's alpha
-- animation over a 3D model's own alpha and leaves the model invisible.
-- Moving the window by its anchor carries the model along.
local function Feel() return DUI.Win.Feel end

-- A page coming into view. The header stays and the page's pieces lift in.
function Window.PageIn(page, base)
    page:SetAlpha(1)
    Feel().Stagger(Feel().Pieces(page), base)
end

-- Counts as closed as soon as the fade out starts.
function Window.IsOpen()
    local f = ns.window
    return f ~= nil and Feel().IsOpen(f)
end

function Window.Open(id)
    local f = ns.window
    if not f then return end
    local opening = not Window.IsOpen()
    Window.LayoutTabs()
    Window.ShowPage(id, opening)
    if opening then
        sound("IG_CHARACTER_INFO_OPEN")
        Feel().Open(f)   -- reopened mid-fade, so it comes back from there
        local page = f.current and f.pages[f.current]
        if page then Window.PageIn(page, Feel().HEAD) end
    end
end

function Window.Close()
    local f = ns.window
    if not (f and Window.IsOpen()) then return end
    sound("IG_CHARACTER_INFO_CLOSE")
    Feel().Close(f)
end

-- At most once a frame, unless `now`.
local pending = false
function Window.Refresh(now)
    local f = ns.window
    if not f then return end
    if not now then
        if pending then return end
        pending = true
        C_Timer.After(0, function()
            pending = false
            Window.Refresh(true)
        end)
        return
    end
    Window.PaintHeader()
    local def = f.current and Window.pages[f.current]
    local page = f.current and f.pages[f.current]
    if def and def.Refresh and page then def.Refresh(page) end
end

-- The cursor changes on every unit or object the mouse passes over. Only
-- picking up or dropping an item triggers a full refresh, since it can change
-- bags and the ammo count. Swapping the held item only re-lights matching slots.
local held
local function holding() return type(CursorHasItem) == "function" and CursorHasItem() == true end
function Window.OnCursor()
    local f = ns.window
    local now = holding()
    if now ~= held then
        held = now
        return Window.Refresh()
    end
    if now and f.current == "character" and ns.Slots then ns.Slots.Holding() end
end

-- The Character page listens to Window.EVENTS (gear, stats, model). Other pages
-- only get their own `events`. These go to every page: level for the header,
-- and combat start/end for what locks.
Window.SHARED = { PLAYER_LEVEL_UP = true, PLAYER_REGEN_ENABLED = true, PLAYER_REGEN_DISABLED = true }
local NO_EVENTS = {}

-- Unit events some page also wants for your pet (its `petEvents`).
local function forPet(event)
    for _, def in pairs(Window.pages) do
        for _, e in ipairs(def.petEvents or NO_EVENTS) do if e == event then return true end end
    end
    return false
end

-- On UNIT_PET the Pet tab shows or hides, and the window leaves the Pet page
-- if there's no pet left.
function Window.PetChanged()
    local f = ns.window
    if not f then return end
    Window.LayoutTabs()
    if f.current == "pet" and not Window.TabShown("pet") then Window.ShowPage("character") end
end
function Window.Wants(id, event)
    if id == "character" or Window.SHARED[event] then return true end
    local def = Window.pages[id]
    for _, e in ipairs(def and def.events or NO_EVENTS) do
        if e == event then return true end
    end
    for _, e in ipairs(def and def.petEvents or NO_EVENTS) do
        if e == event then return true end
    end
    return false
end

function Window.OnEvent(_, event, ...)
    local f = ns.window
    local unit = ...
    if string.sub(event, 1, 5) == "UNIT_" and unit ~= "player" then
        -- Pet events only go to the page that asked, while it's open. Otherwise
        -- the Character page would rebuild your model on UNIT_MODEL_CHANGED.
        if unit ~= "pet" or not forPet(event) then return end
        local def = f.current and Window.pages[f.current]
        if not (def and def.petEvents) then return end
    end
    if event == "UNIT_PET" then Window.PetChanged() end
    if event == "CURSOR_CHANGED" then
        if f.current == "character" then return Window.OnCursor() end
        held = holding()   -- tracked for when the page comes back
        return
    end
    -- Fires on every cast, so only re-light the slots. No full refresh.
    if event == "CURRENT_SPELL_CAST_CHANGED" then
        if f.current == "character" and ns.Slots then ns.Slots.Holding() end
        return
    end
    if not Window.Wants(f.current, event) then return end
    local def = f.current and Window.pages[f.current]
    if def and def.OnEvent then def.OnEvent(f.pages[f.current], event, ...) end
    Window.Refresh()
end

-- Unit events are registered for you and, for petEvents, your pet only.
local function register(f, e)
    if string.sub(e, 1, 5) == "UNIT_" then
        if forPet(e) then return pcall(f.RegisterUnitEvent, f, e, "player", "pet") end
        pcall(f.RegisterUnitEvent, f, e, "player")
    else
        pcall(f.RegisterEvent, f, e)
    end
end

local function listen(f)
    held = holding()   -- the opening refresh shows it
    for _, e in ipairs(Window.EVENTS) do register(f, e) end
    for _, def in pairs(Window.pages) do
        for _, e in ipairs(def.events or {}) do register(f, e) end
        for _, e in ipairs(def.petEvents or {}) do register(f, e) end
    end
end

-- Applies size, scale and position, re-lays out every page and reports the width to the game.
function Window.Apply()
    local f = ns.window
    if not f then return end
    f:SetSize(Window.Width(), Window.H)
    f:SetScale(DUI.Win.Scale(ns.Setting("scale")))
    DUI.Win.Repaint(f)
    Window.Place(f)
    for id, page in pairs(f.pages) do
        local def = Window.pages[id]
        if def.Place then def.Place(page) end
    end
    Window.LayoutTabs()
    Window.PaintTabs()
    if f:IsShown() then Window.Refresh() end
    if ns.Follow then DUI.AfterCombat(ns.Follow.WriteWidth, "characterWidth") end
end

function Window.Build(mod)
    ns.module = mod
    if ns.window then return ns.window end
    local f = CreateFrame("Frame", Window.NAME, UIParent)
    ns.window = f
    Window.spot = DUI.Win.Spot(f, function() return ns.module and ns.module.db end, function(w) Window.Place(w) end)
    DUI.Win.WheelScale(f, function() return ns.Setting("scale") end,
        function(v) DUI:Set("Character", "scale", v) end)
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f.room = true   -- other open windows glide aside for it (Win.Room)
    f:EnableMouse(true)
    f:Hide()
    Style.Shell(f, { window = "Character" })
    Window.BuildHeader(f)
    DUI.Win.Drag(f, { save = Window.SaveSpot, reset = Window.ResetSpot })
    DUI.Movers.onResetAll[#DUI.Movers.onResetAll + 1] = Window.ResetSpot   -- /dui reset
    f.host = CreateFrame("Frame", nil, f)
    f.host:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -Window.HEADER)
    f.host:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    f.pages = {}
    f:SetScript("OnShow", function(self)
        listen(self)
        Window.Refresh(true)
    end)
    f:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        DUI.Fire("CharacterWindowClosed")
    end)
    f:SetScript("OnEvent", Window.OnEvent)
    DUI.Pad.Follow(f, function() f.close:Click() end)   -- after the scripts, since it hooks them
    if ns.CharacterPage then ns.CharacterPage.PadSetup(f) end
    -- Motion goes through Window.Open/Close. Escape closes the game's window
    -- and this one follows.
    if ns.Slots then ns.Slots.Hook() end
    Window.Apply()
    -- Built at login so the slot buttons are borrowed before any combat.
    Window.EnsurePage("character")
    if ns.Follow then ns.Follow.Start() end
    return f
end
