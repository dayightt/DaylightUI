-- Inspect window. The game still runs the inspect: InspectUnit / InspectFrame_Show ask
-- the server (NotifyInspect), its INSPECT_READY handler shows InspectFrame, and its
-- OnHide calls ClearInspectPlayer. That frame is parked under the kit's veil
-- (Win.Follow) so all of it keeps running, and this window shows in its place for the
-- unit it holds (InspectFrame.unit) and closes with it.
-- If opened in combat before it was ever parked, the game's own window shows (parking
-- waits for combat to end), same as the other followers.

local _, DUI = ...
DUI.Inspect = DUI.Inspect or {}
local ns = DUI.Inspect
local L = DUI.L
local Win = DUI.Win

local Insp = {}
ns.Window = Insp

Insp.NAME = "DaylightUIInspect"
Insp.W, Insp.H = 660, 534

function ns.Setting(key) return ns.module and ns.module.db and ns.module.db[key] end

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

function Insp.Game()
    local g = _G.InspectFrame
    return type(g) == "table" and g or nil
end

-- The unit the game's frame is inspecting (its own field, which GetInspectUnit reads).
function Insp.UnitOf()
    local g = Insp.Game()
    local u = g and g.unit
    if secret(u) then return nil end
    return type(u) == "string" and u or nil
end

-- Title: their name in class color; sub line: level, class, guild.
-- A secret class (identity restricted) keeps a plain white title and is left out of the
-- sub line.
local function header(f, unit)
    local className, token = UnitClass(unit)
    local color = { DUI.Style.ClassTextColor(token) }
    local level = UnitLevel(unit)
    local guild = type(GetGuildInfo) == "function" and GetGuildInfo(unit) or nil
    if secret(guild) or type(guild) ~= "string" or guild == "" then guild = nil end
    local sub = ""
    if type(level) == "number" and not secret(level) then
        if type(className) == "string" and not secret(className) then
            sub = guild and string.format(L["Level %d %s · %s"], level, className, guild)
                or string.format(L["Level %d %s"], level, className)
        else
            sub = string.format(L["Level %d"], level)
        end
    end
    Win.SetTitle(f, DUI.UnitName(unit, "inspect") or "", color, sub)
    Win.SetPortrait(f, unit)
end

-- Dragged position (header, Win.Drag, saved per profile in the module's `spot`), else
-- the game's own spot: anchored to the top-left of its veiled window, the left panel
-- spot, like the character and NPC windows. The spot itself is Win.Spot (Insp.spot,
-- created in Insp.Build).
local function spot() return Insp.spot and Insp.spot.Get() end

local function place(f)
    local s = spot()
    if s then return Win.PlaceTop(f, s[1], s[2]) end
    f:ClearAllPoints()
    local g = Insp.Game()
    if g then f:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
    else f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116) end
end

-- A page of this window only; the game's frame keeps its own tab.
function Insp.Show(page)
    local f = Insp.frame
    page = page or f.current or (ns.PAGES[1] and ns.PAGES[1].id)
    if not (page and f.defs[page]) then return end
    Win.PickTab(f, page)
    Win.ShowPage(f, page)
end

-- Re-read for the unit the game holds (a new inspect, late gear links).
function Insp.Refill()
    local f = Insp.frame
    if not (f and Win.IsOpen(f)) then return end
    Insp.unit = Insp.UnitOf() or Insp.unit
    if not Insp.unit then return end
    header(f, Insp.unit)
    local def = f.current and f.defs[f.current]
    local page = f.current and f.pages[f.current]
    if def and def.Fill and page then def.Fill(page) end
end

function Insp.Open()
    local f = Insp.frame
    Insp.unit = Insp.UnitOf()
    if not Insp.unit then return false end
    if Win.IsOpen(f) then Insp.Refill(); return true end
    place(f)
    header(f, Insp.unit)
    Insp.Show(ns.PAGES[1] and ns.PAGES[1].id)
    Win.Open(f)
    return true
end

-- Closing under the mouse: the hovered piece never gets OnLeave, so its tooltip is
-- hidden with it (Win.Shut).
local function shut(f) Win.Shut(f) end

-- Close this one now; the game's closes its own way (HideUIPanel, whose OnHide clears
-- the inspect), after combat if addon code can't close it during.
function Insp.Close()
    local f = Insp.frame
    if not f then return end
    shut(f)
    local g = Insp.Game()
    if not (g and g:IsShown()) then return end
    if InCombatLockdown() then
        DUI.AfterCombat(function()
            local now = Insp.Game()
            if now and now:IsShown() and not Win.IsOpen(Insp.frame) then HideUIPanel(now) end
        end, "inspect:close")
        return
    end
    HideUIPanel(g)
end

-- Follower callback: the game's frame shown or hidden. Shown with no readable unit: use
-- the game's own window for now, otherwise nothing would show at all.
function Insp.Changed(_, shown)
    local f = Insp.frame
    if not shown then
        Insp.unit = nil
        -- Forget who each page showed, so the next open (even of the same player) dresses the
        -- model fresh.
        for _, page in pairs(f and f.pages or {}) do page.unitShown = nil end
        if Win.IsOpen(f) then shut(f) end
        return
    end
    if Insp.Open() then return end
    if not Win.Followers.Lend(Insp.follow, "inspect") then
        DUI.AfterCombat(function()
            local g = Insp.Game()
            if g and g:IsShown() and not Insp.UnitOf() then Win.Followers.Lend(Insp.follow, "inspect") end
        end, "inspect:lend")
    end
end

-- INSPECT_READY: the server answered for this guid; refill if it's the one shown here.
-- A second inspect while open makes the game hide and show its frame in the same frame,
-- so the follower never sees it close. The first answer comes before this window opens
-- (the game's frame shows from this same event, this one a frame later), so the
-- re-reads start anyway and fill it once open.
function Insp.Ready(guid)
    if not Insp.frame then return end
    local unit = Insp.UnitOf() or Insp.unit
    if not unit then return end
    local now = UnitGUID(unit)
    if not (secret(guid) or issecretvalue(now) or now == guid) then return end
    -- Identity can't be read (a PvP match, a restricted map): a new answer may be someone
    -- else on the same unit, so the pages redraw fresh (Gear.Fill's `unitShown` knows
    -- someone was shown, not who, and their slots still fade in). Re-reads after it are the
    -- same player.
    if secret(guid) or issecretvalue(now) then
        for _, page in pairs(Insp.frame.pages or {}) do
            if page.unitShown then page.unitShown = "unread" end
        end
    end
    -- Only for this window: open, or the game's frame shown (from this same event, maybe
    -- after this handler, so check again next frame). Neither means another addon's
    -- inspect, nothing to read.
    local function ours()
        local g = Insp.Game()
        return Win.IsOpen(Insp.frame) or (g and g:IsShown())
    end
    local function read()
        Insp.Refill()
        Insp.ReadAgain()
    end
    if ours() then
        read()
    else
        C_Timer.After(0, function() if ours() then read() end end)
    end
end

-- Gear links arrive a moment after INSPECT_READY (in game, 1 of 11 at once and the rest
-- about a second later), with or without an item event, so re-read a few times while
-- it settles.
Insp.AGAIN = { 0.5, 1.5, 3 }
function Insp.ReadAgain()
    Insp.wave = (Insp.wave or 0) + 1
    local wave = Insp.wave
    for _, s in ipairs(Insp.AGAIN) do
        C_Timer.After(s, function() if Insp.wave == wave then Insp.Refill() end end)
    end
end

-- Their items changed (a late link, or a gear swap).
function Insp.ItemsChanged(unit)
    if secret(unit) or not Insp.unit or unit ~= Insp.unit then return end
    Insp.Refill()
end

-- Dragged by the header: just saved (no SettingChanged, nothing to refill).
function Insp.SaveSpot(x, y) Insp.spot.Save(x, y) end

-- Right-click on the header (or /dui reset): back to the game's spot.
function Insp.ResetSpot() return Insp.spot and Insp.spot.Reset() end

function Insp.Apply()
    local f = Insp.frame
    if not f then return end
    f:SetScale(Win.Scale(ns.Setting("scale")))
    if spot() and Win.IsOpen(f) then place(f) end   -- new UI scale keeps the dragged spot
    Win.Repaint(f)
    for _, page in pairs(f.pages or {}) do page.drawn = nil end   -- pages that skip an identical refill repaint anyway
    Insp.Refill()
    if Insp.follow then Win.Followers.WriteWidth(Insp.follow) end
end

function Insp.Build(mod)
    ns.module = mod
    if Insp.frame then return Insp.frame end
    local f = Win.New({ name = Insp.NAME, back = "Inspect", w = Insp.W, h = Insp.H, portrait = true })
    Insp.frame = f
    f.onClose = Insp.Close
    Insp.spot = Win.Spot(f, function() return ns.module and ns.module.db end, place)
    local tabs = {}
    for _, p in ipairs(ns.PAGES) do
        Win.AddPage(f, p.id, { Build = p.Build, Fill = p.Fill, w = p.w or Insp.W, h = p.h or Insp.H, pieces = p.pieces })
        Win.Build(f, p.id)
        tabs[#tabs + 1] = { id = p.id, text = p.text }
    end
    if #tabs > 1 then Win.Tabs(f, tabs, Insp.Show) end
    -- Controller: like the game's inspect window, Y opens the dressing room on a gear slot.
    local function link(b)
        local e, unit = type(b) == "table" and b.entry, Insp.unit
        if not (unit and type(e) == "table" and e.id and not e.empty) then return nil end
        return GetInventoryItemLink(unit, e.id)
    end
    f.padKeys = { { key = "Y", label = DRESSUP_FRAME or L["Dressing room"], when = function(b) return link(b) ~= nil end,
        run = function(b) DressUpLink(link(b)) end } }
    Win.Drag(f, { save = Insp.SaveSpot, reset = Insp.ResetSpot })
    Win.WheelScale(f, function() return ns.Setting("scale") end, function(v) DUI:Set("Inspect", "scale", v) end)
    DUI.Movers.onResetAll[#DUI.Movers.onResetAll + 1] = Insp.ResetSpot   -- /dui reset
    DUI.RegisterEvent("INSPECT_READY", function(_, guid) Insp.Ready(guid) end)
    DUI.RegisterEvent("UNIT_INVENTORY_CHANGED", function(_, unit) Insp.ItemsChanged(unit) end)
    Insp.follow = Win.Follow({ key = "inspect", frames = { inspect = Insp.Game }, veil = { inspect = true },
        changed = Insp.Changed, width = function() return Insp.W * Win.Scale(ns.Setting("scale")) end })
    Insp.Apply()
    return f
end
