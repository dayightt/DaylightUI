-- Lets the game's windows in Move.WINDOWS be dragged by their title bar. The
-- game places most of these itself and re-places them whenever it lays out its
-- panels (a window opening or closing, the dressing room maximizing), so after
-- each of those they're put back where they were dragged, like the world map
-- (MapMove.lua). Saved per profile by window name (windowSpots). Right-click
-- the title bar, or /dui reset, to restore the game's spot.
--
-- Nothing of the game's is called or replaced: just a drag strip, SetPoint
-- and StartMoving on the window, and post-hooks on global functions. Windows
-- that hold secure buttons (collections, professions) can't move in a fight,
-- so those wait for it to end.

local _, ns = ...
local DUI = DaylightUI

local Move = {}
ns.WindowMove = Move

-- Every game window Daylight UI skins that stands on its own. Left out: the
-- world map (MapMove.lua drags and sizes it), the auction house's side
-- dressing room (it hangs off the auction house and goes with it), the loot
-- window (an Edit Mode piece with its own unlock handle), and pop-ups, toasts
-- and the stack split box, which the game puts by what they belong to.
Move.WINDOWS = {
    -- Collections and journals
    "DressUpFrame", "CollectionsJournal", "AchievementFrame", "EncounterJournal",
    -- Guild, calendar, trade
    "CommunitiesFrame", "CommunitiesGuildLogFrame", "CommunitiesGuildTextEditFrame",
    "CommunitiesGuildNewsFiltersFrame", "CalendarFrame", "GuildBankFrame", "TradeFrame",
    -- Things an NPC or an item opens
    "ItemTextFrame", "PetStableFrame", "TabardFrame", "PetitionFrame", "GuildRegistrarFrame", "TaxiFrame",
    "FlightMapFrame", "ClassTrainerFrame", "AuctionHouseFrame", "ItemSocketingFrame",
    "ItemUpgradeFrame", "ScrappingMachineFrame",
    -- The game's own menus
    "ProfessionsBookFrame", "GameMenuFrame", "AddonList", "MacroFrame", "TimeManagerFrame",
}
Move.BAR_HEIGHT = 26 -- title row height, down to the dressing room's set menu (the guild window's dropdowns start 26-28 down)
Move.BUTTONS = 70 -- room at the bar's right end for maximize/minimize and close
Move.BAR_LIFT = 20 -- above the window's model, which starts under the title
-- A window whose title row holds something else to click gets a strip that
-- leaves it free: { height = px, right = px kept free at the right end }.
Move.SHAPE = {
    -- The calendar's month arrows sit in the middle of its title row and its
    -- filter button at the right, so it drags by the left part of the row.
    CalendarFrame = { right = 440 },
    -- The flight map starts 20 down; below that a drag should move the map.
    FlightMapFrame = { height = 20 },
}
Move.bars = {} -- [name] = drag strip

local cfg
local windows = {}   -- [name] = frame
local home = {} -- [name] = the game's last anchor, for restoring

local function spots()
    if not cfg then return nil end
    if type(cfg.windowSpots) ~= "table" then cfg.windowSpots = {} end
    return cfg.windowSpots
end

-- The saved spot, only if it's two numbers (a damaged import may have neither).
function Move.Spot(name)
    local t = spots()
    local s = t and t[name]
    if type(s) == "table" and type(s[1]) == "number" and type(s[2]) == "number" then return s end
    return nil
end

local function ratio(f)
    return f:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

local function locked(f)
    return InCombatLockdown() and f:IsProtected()
end

-- A game window Daylight UI's own window stands in for is kept out of sight
-- under a parent of its own (the trainer, until Beast Training lends it back):
-- it stays where that parent keeps it.
local function parked(f)
    local follow = DUI.Win and DUI.Win.Followers
    local p = f:GetParent()
    return follow ~= nil and p ~= nil and (p == follow.hidden or p == follow.aside)
end

-- Moves a window to its saved spot: top-left corner, in UIParent units from
-- UIParent's bottom-left. Does nothing if unsaved or hidden.
function Move.Apply(name)
    local f, spot = windows[name], Move.Spot(name)
    if not (f and spot and f:IsShown()) or parked(f) then return end
    if locked(f) then
        DUI.AfterCombat(function() Move.Apply(name) end, "skins:windowMove:" .. name)
        return
    end
    -- Remember the game's own anchor if it just placed it (the saved ones are BOTTOMLEFT).
    local point, rel, relPoint, x, y = f:GetPoint(1)
    if relPoint ~= "BOTTOMLEFT" then home[name] = { point, rel, relPoint, x, y } end
    local r = ratio(f)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", spot[1] / r, spot[2] / r)
end

function Move.ApplyAll()
    for name in pairs(windows) do Move.Apply(name) end
end

local function save(name, f)
    local cx, cy = f:GetCenter()
    if not cx then return end
    local r = ratio(f)
    spots()[name] = { DUI.Pixel.Snap(UIParent, (cx - f:GetWidth() / 2) * r),
                      DUI.Pixel.Snap(UIParent, (cy + f:GetHeight() / 2) * r) }
    Move.Apply(name)
end

-- Forgets the saved spot and, if the window is open, puts it straight back
-- where the game had it. Its next layout keeps it there.
function Move.Forget(name)
    local t = spots()
    if t then t[name] = nil end
    local f, a = windows[name], home[name]
    if f and a and f:IsShown() and not locked(f) and not parked(f) then
        f:ClearAllPoints()
        f:SetPoint(a[1], a[2], a[3], a[4], a[5])
    end
end

function Move.Reset()
    for name in pairs(windows) do Move.Forget(name) end
end

local function makeBar(name, f)
    local shape = Move.SHAPE[name] or {}
    local bar = CreateFrame("Frame", nil, f)
    Move.bars[name] = bar
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(shape.right or Move.BUTTONS), 0)
    bar:SetHeight(shape.height or Move.BAR_HEIGHT)
    bar:SetFrameLevel(f:GetFrameLevel() + Move.BAR_LIFT)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function()
        if locked(f) or parked(f) then return end
        f:SetMovable(true)
        f:SetClampedToScreen(true)
        f:StartMoving()
    end)
    bar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        -- Saved in the addon's settings, not in the game's layout cache.
        f:SetUserPlaced(false)
        save(name, f)
    end)
    bar:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then Move.Forget(name) end
    end)
end

local function hook(name, f)
    if windows[name] then return end
    windows[name] = f
    makeBar(name, f)
    -- Some ways of opening skip the panel functions, so apply next frame too.
    f:HookScript("OnShow", function()
        Move.Apply(name)
        C_Timer.After(0, function() Move.Apply(name) end)
    end)
    Move.Apply(name)
end

-- Waits for each window like a skin but in no pack, so it moves whether or
-- not it's skinned.
for _, name in ipairs(Move.WINDOWS) do
    ns.Engine.Register({ key = "windowmove." .. name, apply = function()
        local f = _G[name]
        if type(f) ~= "table" or type(f.GetObjectType) ~= "function" then return false end
        if f.IsForbidden and f:IsForbidden() then return end
        hook(name, f)
    end })
end

local started = false
function Move.Start(c)
    cfg = c
    if not started then
        started = true
        for _, fn in ipairs({ "ShowUIPanel", "HideUIPanel", "UpdateUIPanelPositions" }) do
            if type(_G[fn]) == "function" then hooksecurefunc(fn, Move.ApplyAll) end
        end
        DUI.Movers.onResetAll[#DUI.Movers.onResetAll + 1] = Move.Reset
    end
    Move.ApplyAll()
end
