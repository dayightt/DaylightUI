-- Places the game's quest tracker under the panel when DaylightUI_Quests is
-- off or deferring to another tracker addon.
--
-- The tracker is an Edit Mode system with secure item buttons, and moving,
-- reparenting, hiding or re-laying it out from addon code taints the game's
-- quest code. So its position goes into the Edit Mode layout as plain offsets
-- from the screen's top-right (Tracker.Fill), matching DaylightUITrackerAnchor
-- under the minimap. Moving it in unlock mode saves a new spot; locking writes
-- the layout and asks for a reload. Only its position and fade are changed.

local _, ns = ...
local DUI = DaylightUI
local EditMode = DUI.EditMode

local Tracker = {}
ns.Tracker = Tracker

Tracker.ANCHOR = "DaylightUITrackerAnchor"
-- Inset from the panel's right edge, so the section collapse buttons (which
-- stick out past the tracker) stay inside the panel's line.
Tracker.EDGE = 12
-- Where the anchor starts, before the panel has been laid out (so the
-- tracker always has somewhere to hang): the panel's usual bottom-right.
Tracker.START = { -12, -260 }
Tracker.RETRY = 0.2          -- seconds between tries while the panel has no place yet
-- Size of the unlock-mode stand-in for the tracker (width until the tracker
-- can be measured). Its top-right corner is where the tracker's goes.
Tracker.MOVER = "infopanel.tracker"
Tracker.HANDLE = { 248, 160 }

local cfg

-- The anchor exists from the moment this file loads, before the game applies
-- its Edit Mode layout (which looks it up by name), with a starting spot.
local anchor = CreateFrame("Frame", Tracker.ANCHOR, UIParent)
anchor:SetSize(1, 1)
anchor:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", Tracker.START[1], Tracker.START[2])
Tracker.anchor = anchor

-- Our own tracker (DaylightUI_Quests) has stopped the game's: then only the
-- anchor it hangs from is placed here; nothing of the game's is touched.
function Tracker.Replaced() return DUI.questsOwnTracker == true end
-- The frame behind the unlock handle (never shown). The real tracker can't be
-- moved, so the handle moves this and the spot goes into the layout.
local stand = CreateFrame("Frame", nil, UIParent)
stand:SetSize(Tracker.HANDLE[1], Tracker.HANDLE[2])
stand:Hide()
Tracker.stand = stand

-- ---------------------------------------------------------------------
-- Placement
-- ---------------------------------------------------------------------

-- The spot the tracker was moved to in unlock mode for this profile, or nil
-- for under the panel. With the Quests tracker on, that spot belongs to its
-- own handle (migrated once), and the anchor stays under the panel.
local function moved()
    if Tracker.Replaced() then return nil end
    return DUI.DB.Positions()[Tracker.MOVER]
end

-- Under the panel, where the tracker's corner goes: in UIParent units from the screen's bottom-left. nil until the
-- panel has a place.
local function underPanel()
    local panel = ns.Panel.panel
    if not (panel and panel:GetRight() and panel:GetBottom()) then return nil end
    local s = panel:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return panel:GetRight() * s, panel:GetBottom() * s - ns.Panel.GAP
end

-- Where that corner goes: the handle's top-right corner where it was moved
-- to, else under the panel.
local function corner()
    local saved = moved()
    if not saved then return underPanel() end
    return UIParent:GetWidth() / 2 + saved[1] + stand:GetWidth() / 2,
        UIParent:GetHeight() / 2 + saved[2] + stand:GetHeight() / 2
end
Tracker.Corner = corner

-- The handle's spot when it hasn't been moved: under the panel, as a CENTER
-- offset from UIParent's CENTER (what unlock mode saves).
function Tracker.Home()
    local x, y = underPanel()
    if not x then return nil end
    return x - stand:GetWidth() / 2 - UIParent:GetWidth() / 2,
        y - stand:GetHeight() / 2 - UIParent:GetHeight() / 2
end

-- Places the anchor in plain screen coordinates, not attached to the panel,
-- so moving the panel in combat can't drag a protected frame. Out of combat only.
local retrying = false

-- When the data text strip appears, disappears or changes height, a saved
-- spot that was "under the panel" follows it, so the strip never covers the
-- tracker and no gap is left. For the Quests tracker, a migrated spot at the
-- panel's corner is dropped so it follows the anchor again.
-- Only spots this code wrote (marked `follows`) are adjusted. A spot the
-- player placed by hand stays put, even right under the panel.
-- Older saves without the mark: a spot exactly at the panel's corner is
-- assumed to be ours and gets the mark.
Tracker.OWN_MOVER = "quests.tracker"
local last = {}       -- mover key -> { x, y }: the corner spot when last looked
local function follows(key, saved, x, y)
    local was = last[key]
    last[key] = { x, y }
    if not DUI.Movers.Valid(saved) then return false end
    if saved.follows ~= true then
        local function at(p) return math.abs(saved[1] - p[1]) < 1 and math.abs(saved[2] - p[2]) < 1 end
        if at({ x, y }) or (was and at(was)) then saved.follows = true end
    end
    return saved.follows == true
end
local function followOwn(pos, room)
    local saved, h = pos[Tracker.OWN_MOVER], _G.DaylightUIQuestTracker
    if not h then return end
    local x, y = underPanel()
    if not x then return end
    -- The spot that hangs the tracker's top-right at the anchor.
    local cx = x - Tracker.EDGE - h:GetWidth() / 2 - UIParent:GetWidth() / 2
    local cy = y - h:GetHeight() / 2 - UIParent:GetHeight() / 2
    if not follows(Tracker.OWN_MOVER, saved, cx, cy) then return end
    local right = UIParent:GetWidth() / 2 + saved[1] + h:GetWidth() / 2
    local top = UIParent:GetHeight() / 2 + saved[2] + h:GetHeight() / 2
    local atX = math.abs(right - x) < 1 or math.abs(right - (x - Tracker.EDGE)) < 1
    if atX and math.abs(top - y) <= room + 1 then
        pos[Tracker.OWN_MOVER] = nil
        if DUI.Movers.Get(Tracker.OWN_MOVER) then DUI.Movers.Apply(Tracker.OWN_MOVER) end
    end
end

function Tracker.FollowStrip()
    local pos = DUI.DB.Positions()
    local room = ns.DataTexts.Room(ns.module and ns.module.db, true)
    if Tracker.Replaced() then return followOwn(pos, room) end
    local saved = pos[Tracker.MOVER]
    local hx, hy = Tracker.Home()
    if not hx then return end
    if not follows(Tracker.MOVER, saved, hx, hy) then return end
    local dy = math.abs(saved[2] - hy)
    if math.abs(saved[1] - hx) < 1 and dy >= 1 and dy <= room + 1 then
        pos[Tracker.MOVER] = { hx, hy, follows = true }
    end
end

function Tracker.PlaceAnchor()
    if not anchor then return end
    Tracker.FollowStrip()
    local cx, cy = corner()
    if not cx then
        -- Laid out on the next frames: try again shortly.
        if not retrying then
            retrying = true
            C_Timer.After(Tracker.RETRY, function()
                retrying = false
                DUI.AfterCombat(Tracker.PlaceAnchor, "tracker:anchor")
            end)
        end
        return
    end
    local x, y = cx - Tracker.EDGE, cy
    local changed = anchor.x ~= x or anchor.y ~= y
    if changed then
        anchor.x, anchor.y = x, y
        anchor:ClearAllPoints()
        anchor:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", x, y)
    end
    if Tracker.Replaced() then return end
    -- The layout gets this spot as plain screen offsets. It's rewritten when
    -- unlock mode ends after a move or reset, and when the panel moves or
    -- resizes. A reload applies it.
    if not EditMode.Exists() then return end
    if Tracker.movedByHand then
        Tracker.movedByHand = false
        -- Saving activates the layout, so on a layout of the player's own the
        -- spot is theirs to set in Edit Mode, as GameMovers does.
        if not EditMode.IsActive() then
            DUI.Print(DUI.L["The quest tracker's spot is kept by the game's Edit Mode, and you're on an Edit Mode layout of your own: move it there (Esc > Edit Mode)."])
        elseif not EditMode.UpToDate() then
            EditMode.Save(DUI.L["DaylightUI saved the quest tracker's position. Reload to put it in place?"])
        end
    elseif changed then
        EditMode.AutoSave(DUI.L["DaylightUI moved the quest tracker to fit the panel. Reload to put it in place?"])
    end
    -- Once the tracker really sits under the panel, that spot is kept: later
    -- panel moves leave it alone and ask for no reload. Reset puts it back.
    if not moved() and EditMode.UpToDate() then
        local hx, hy = Tracker.Home()
        if hx then DUI.DB.Positions()[Tracker.MOVER] = { hx, hy, follows = true } end
    end
end

-- Where the tracker's top-right corner goes, as offsets from the screen's
-- top-right corner; nil until the panel has a place.
function Tracker.Spot()
    if not (anchor and anchor.x and anchor.y) then return nil end
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local function round(v) return math.floor(v * 10 + 0.5) / 10 end
    return round(anchor.x - w), round(anchor.y - h)
end

-- The tracker's entry in the Edit Mode layout. Only its position is set; the
-- rest (like its background) stays the player's. Written as offsets from the
-- screen corner, never anchored to an addon frame: the tracker measures itself
-- against its anchor, and an addon-placed anchor taints its code (it then
-- refuses to read auras).
function Tracker.Fill(layout)
    if not (cfg and cfg.enabled) then return end
    local sys = Enum.EditModeSystem.ObjectiveTracker
    local entry = sys ~= nil and EditMode.FindSystem(layout, sys, nil)
    if not entry then return end
    local x, y = Tracker.Spot()
    if x then EditMode.Anchor(entry, "TOPRIGHT", "TOPRIGHT", x, y, "UIParent") end
end

-- Whether the saved layout already puts the tracker at our spot (within a
-- pixel). Before the panel has a place there is nothing to compare.
function Tracker.Current(layout)
    if not (cfg and cfg.enabled) then return true end
    local sys = Enum.EditModeSystem.ObjectiveTracker
    local entry = sys ~= nil and EditMode.FindSystem(layout, sys, nil)
    if not entry then return true end
    local x, y = Tracker.Spot()
    if not x then return true end
    local a = entry.anchorInfo
    return type(a) == "table" and a.relativeTo == "UIParent" and a.point == "TOPRIGHT" and a.relativePoint == "TOPRIGHT"
        and type(a.offsetX) == "number" and type(a.offsetY) == "number"
        and math.abs(a.offsetX - x) < 1 and math.abs(a.offsetY - y) < 1
end

-- ---------------------------------------------------------------------
-- Build and apply
-- ---------------------------------------------------------------------

local function placeSoon()
    C_Timer.After(0, function()
        if Tracker.Replaced() or (cfg and cfg.enabled) then DUI.AfterCombat(Tracker.PlaceAnchor, "tracker:anchor") end
    end)
end

function Tracker.Build(mod)
    cfg = mod.db.tracker
    -- Re-place after a loading screen (the panel is laid out by then) and
    -- after a window or UI scale change, since the anchor is placed from the
    -- bottom-left. Otherwise the saved spot would drift and the next login
    -- would ask for a reload. Done next frame, once the screen has its new size.
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
        pcall(DUI.RegisterEvent, e, placeSoon)
    end
    if Tracker.Replaced() then return end
    local list, none = {}, {}   -- (kept: the fade asks often)
    DUI.Fade.Register{ key = "InfoPanel.tracker", scope = "InfoPanel", path = "tracker.fade", page = "InfoPanel.tracker",
        frames = function()
            if not (mod.db.tracker.enabled and ObjectiveTrackerFrame) then return none end
            list[1] = ObjectiveTrackerFrame
            return list
        end }
    EditMode.Add("tracker", Tracker.Fill, Tracker.Current)
    -- Unlock mode: a handle of its own. The game's tracker stays put until
    -- the reload that unlocking ends with (it's placed by the layout).
    DUI.Movers.Register(stand, Tracker.MOVER, "Quest Tracker", nil, { proxy = true,
        active = function() return cfg and cfg.enabled end,
        home = Tracker.Home,
        onMoved = function() Tracker.movedByHand = true end })
end

function Tracker.Apply(c)
    cfg = c
    if not (Tracker.Replaced() or c.enabled) then return end
    -- The handle as wide as the tracker (the game's width doesn't change,
    -- so a moved spot stays put).
    local otf = ObjectiveTrackerFrame
    local w = not Tracker.Replaced() and otf and otf.GetWidth and otf:GetWidth()
    if type(w) == "number" and w > 0 then
        stand:SetWidth(w * otf:GetEffectiveScale() / UIParent:GetEffectiveScale())
    end
    DUI.AfterCombat(Tracker.PlaceAnchor, "tracker:anchor")
end
