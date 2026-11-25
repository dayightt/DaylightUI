-- The game's minimap, made square and placed in the panel's right side. Its
-- border, zoom buttons and surrounding cluster are hidden; the wheel zooms.
-- The game re-anchors these frames during its layout passes, so each one is
-- put back the frame after (see pin).

local _, ns = ...
local DUI = DaylightUI
local isSecret = DUI.IsSecret
local L = DUI.L
local Style = DUI.Style

local Map = {}
ns.Minimap = Map

Map.MASK = "Interface\\Buttons\\WHITE8X8"
-- With rotateMinimap on, the game rotates a square of terrain and the map's mask
-- with it, and ignores clipping parents. That gave empty corners and diamond
-- shapes, so a rotating map is drawn round, like the game's.
Map.ROUND_MASK = DUI.MEDIA .. "mask-map-round.png"
-- A round map (map.shape "round", or any rotating map) gets a thin ring with an
-- N marker. GetPlayerFacing: 0 is north, turning left increases it, nil in some
-- instances (the N hides). The N follows the facing only while rotating, and
-- sits still at the top otherwise, with nothing running each frame.
Map.RING = DUI.MEDIA .. "map-ring.png"
Map.NORTH_INSET = 9     -- the N's middle, in from the ring
Map.TEXT_LIFT = 4       -- the map's texts sit this many levels over it: above the ring (+2)
Map.DECOR = { "MinimapBackdrop", "MinimapCompassTexture" }
-- Quest, bonus-objective and dig-site areas are drawn with a hatched ring
-- where they meet the edge of a round map. On a square map that ring shows
-- as a big circle, so it is scaled and faded to nothing; the area itself
-- still fills the map.
Map.BLOB_RINGS = { "QuestBlob", "TaskBlob", "ArchBlob" }
Map.QUEUE_SCALE = 0.5         -- the game's LFG eye at the map's bottom-left
Map.BUTTON_INSET = 4        -- the calendar and tracking buttons, from the map's top-right corner (as the drawer's, Drawer.PAD)
Map.BUTTON_GAP = 2           -- between them

local area
local places = {}            -- frame -> its place function

-- Places a frame now, and again the frame after the game's layout may have
-- moved it (Edit Mode layouts, the frame showing, spec changes). A group change
-- moves none of them: the game's queue eye re-anchors only with the map's scale
-- and Edit Mode, and shows through OnShow. Never hook its SetPoint: the game
-- calls it from protected layout code and a hook there made it fail with
-- "attempt to call a nil value" thousands of times.
Map.PLACE_EVENTS = { "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_ENTERING_WORLD",
                    "UPDATE_PENDING_MAIL" }

-- A protected frame can't be moved in combat (the map can become protected
-- through a child). Those wait for combat to end; the rest move now.
local function placeOne(frame, place)
    if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
        DUI.AfterCombat(function() placeOne(frame, places[frame]) end, frame)
        return
    end
    DUI.SafeCall(place, frame)
end

local function placeAll()
    for frame, place in pairs(places) do placeOne(frame, place) end
end

local soon = DUI.Soon(placeAll)

local function pin(frame, place)
    if type(frame) ~= "table" or not frame.SetPoint then return end
    if not places[frame] and frame.HookScript then frame:HookScript("OnShow", soon) end
    places[frame] = place
    if not Map.placeWired then
        Map.placeWired = true
        for _, event in ipairs(Map.PLACE_EVENTS) do DUI.RegisterEvent(event, soon) end
        -- Leaving Edit Mode puts frames back at their Edit Mode spots.
        local em = _G.EditModeManagerFrame
        if type(em) == "table" and em.HookScript then em:HookScript("OnHide", soon) end
    end
    placeOne(frame, place)
end
Map.Pin = pin

-- Setters that skip a frame already as asked. The game's frames here are
-- re-placed after many events and every style repaint; writing them again
-- unchanged is work in the game's own layout for nothing, and on the map
-- itself it dropped its picture.
local function near(a, b) return math.abs((a or 0) - (b or 0)) < 0.01 end

function Map.IsAt(f, point, rel, relPoint, x, y)
    if f:GetNumPoints() ~= 1 then return false end
    local p, r, rp, px, py = f:GetPoint(1)
    -- An anchor that went secret can't be compared: place it again.
    if isSecret(px) or isSecret(py) then return false end
    return p == point and r == rel and rp == relPoint and near(px, x) and near(py, y)
end

function Map.PlaceAt(f, point, rel, relPoint, x, y)
    x, y = x or 0, y or 0
    if Map.IsAt(f, point, rel, relPoint, x, y) then return end
    f:ClearAllPoints()
    f:SetPoint(point, rel, relPoint, x, y)
end

function Map.ParentTo(f, parent)
    if f:GetParent() ~= parent then f:SetParent(parent) end
end

function Map.SizeTo(f, w, h)
    local fw, fh = f:GetSize()
    if isSecret(fw) or isSecret(fh) or not (near(fw, w) and near(fh, h)) then f:SetSize(w, h) end
end

function Map.ScaleTo(f, scale)
    local s = f:GetScale()
    if isSecret(s) or not near(s, scale) then f:SetScale(scale) end
end

function Map.LevelTo(f, level)
    if f:GetFrameLevel() ~= level then f:SetFrameLevel(level) end
end

function Map.Turning()
    return type(GetCVarBool) == "function" and GetCVarBool("rotateMinimap") == true
end

-- The size of the game's icons on the map (nodes, party members, quest spots),
-- apart from the map's own size. Edit Mode stores it in its layout as a slider
-- step and sets it again each time it applies one, so it's written there too.
Map.ICON_SCALE = DUI.Fade.MAP_ICON_SCALE

local function iconSetting()
    local sys, set = Enum.EditModeSystem, Enum.EditModeMinimapSetting
    return sys and sys.Minimap, set and set.IconScale
end

Map.GetIconScale = DUI.Fade.MapIconScale

function Map.SetIconScale(scale)
    local S, system, setting = Map.ICON_SCALE, iconSetting()
    local pct = math.max(S.min, math.min(S.max, math.floor(scale * 100 / S.step + 0.5) * S.step))
    -- Out of sight, the icons stay at 0 until the map is back (Fade.MapDots).
    if Minimap and Minimap.SetIconScale and not DUI.Fade.MapDotsGone() then Minimap:SetIconScale(pct / 100) end
    if system ~= nil and setting ~= nil then
        DaylightUI.EditMode.WriteSetting(system, nil, setting, (pct - S.min) / S.step)
    end
    DaylightUI.Fire("SettingChanged", "InfoPanel", "map.iconScale", pct / 100)
end

-- Round by choice, or because it turns: a turning square showed empty corners.
-- cfg: the map's settings, when asked before the map has been laid out.
function Map.Round(cfg)
    cfg = cfg or Map.cfg
    return Map.Turning() or (type(cfg) == "table" and cfg.shape == "round")
end

-- Puts the N on the ring at this facing (nil hides it).
function Map.PlaceNorth(f, facing)
    f.facing = facing
    f.north:SetShown(facing ~= nil)
    if not facing then return end
    local r = Minimap:GetWidth() / 2 - Map.NORTH_INSET
    f.north:ClearAllPoints()
    f.north:SetPoint("CENTER", f, "CENTER", r * math.sin(facing), r * math.cos(facing))
end

-- The ring's OnUpdate while the map turns: moves the N only when the facing changes.
function Map.FollowNorth(f)
    local facing = type(GetPlayerFacing) == "function" and GetPlayerFacing() or nil
    if facing == f.facing then return end
    Map.PlaceNorth(f, facing)
end

-- The ring and the N on a round map (made once, on the map's area).
function Map.Ring()
    if Map.ring and Map.ring:GetParent() == Minimap then return Map.ring end
    -- On the map itself, as its texts: the game keeps the map in its own
    -- strata, and on the panel the ring drew over them at any level.
    local f = CreateFrame("Frame", nil, Minimap)
    f:SetAllPoints(Minimap)
    -- Under the N (an OVERLAY text on the ring's band): in the same layer
    -- the ring's art drew over it and the N was gone.
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexture(Map.RING)
    f.north = Style.Text(f, Style.SIZE.body, "CENTER")
    f.north:SetText(L["N"])
    f:Hide()
    Map.ring = f
    return f
end

-- Shown on a round map, painted at paint time (the accent can change). Only a
-- turning map moves its N each frame; a still one has it fixed at the top.
function Map.PaintRing(round, turning)
    if not (round or Map.ring) then return end
    local f = Map.Ring()
    f:SetFrameLevel(Minimap:GetFrameLevel() + 2)
    f.tex:SetVertexColor(Style.BAND_LIT[1], Style.BAND_LIT[2], Style.BAND_LIT[3], 1)
    Style.InkText(f.north, "pop")
    if round and turning then
        f.facing = false
        f:SetScript("OnUpdate", Map.FollowNorth)
    else
        f:SetScript("OnUpdate", nil)
        Map.PlaceNorth(f, 0)
    end
    if round and not f:IsShown() then
        f:Show(); DUI.Motion.Fade(f, 0, 1, DUI.Motion.NORMAL)
    elseif not round then
        f:Hide()
    end
end

-- Addons that put buttons round the minimap ask this for its shape.
function GetMinimapShape() return Map.Round() and "ROUND" or "SQUARE" end

-- ---------------------------------------------------------------------
-- Clock at the bottom of the map, local or server time. Hover shows both.
-- ---------------------------------------------------------------------

-- The data texts' clock (DataTexts.lua loads after this file: read when
-- the clock is drawn, never at load).
local function readClock(useServer) return ns.DataTexts.ReadClock(useServer) end
local function formatClock(h, m, twentyFour, s) return ns.DataTexts.FormatClock(h, m, twentyFour, s) end

local function clockOnEnter(self)
    local cfg = Map.cfg and Map.cfg.clock
    if not cfg then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    local lh, lm, ls = readClock(false)
    local sh, sm = readClock(true)
    if not cfg.seconds then ls = nil end
    local Tips = DUI.Tips
    Tips.Clear()
    Tips.Title(L["Time"])
    Tips.Line(L["Local"], formatClock(lh, lm, cfg.twentyFour, ls))
    Tips.Line(L["Server"], formatClock(sh, sm, cfg.twentyFour, ls))
    ns.DataTexts.ClockHint()
    Tips.Flush(GameTooltip)
    GameTooltip:Show()
    -- The game's own clock button takes the click out of a fight, laid over this.
    DUI.SafeCall(ns.DataTexts.WindowOver, self)
end

local function ensureClock(mm)
    if Map.clock then return Map.clock end
    local f = CreateFrame("Button", nil, mm)
    f:SetFrameLevel(mm:GetFrameLevel() + Map.TEXT_LIFT)   -- over the ring and the map's dots
    f:SetSize(70, 12)
    f:EnableMouse(true)
    f.text = Style.Text(f, 11, "CENTER", ns.MEDIA.font)
    Style.InkText(f.text, "VALUE")
    -- Left and right only: the text keeps its own height, so a big or tall
    -- font isn't cropped by its frame (tall letters got their tops cut off).
    f.text:SetPoint("LEFT", f, "LEFT"); f.text:SetPoint("RIGHT", f, "RIGHT")
    -- A click opens the game's alarm and stopwatch window, as its own clock does.
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.key = "time"   -- the data texts' secure button opens what the Time text opens
    f:SetScript("OnEnter", clockOnEnter)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:SetScript("OnClick", function() ns.DataTexts.ClockClick() end)
    f.enter, f.leave = clockOnEnter, f:GetScript("OnLeave")
    Map.clock = f
    return f
end

-- Redraws the shown time; started on a light ticker once the map's up.
-- Written only when the shown time (or the 12/24-hour choice) has changed.
function Map.UpdateClock()
    local f = Map.clock
    local cfg = Map.cfg and Map.cfg.clock
    if not f then return end
    if not (cfg and cfg.enabled) then
        f:Hide()
        f.h = nil
        return
    end
    local h, m, s = readClock(cfg.useServer)
    if not cfg.seconds then s = nil end
    local twentyFour = cfg.twentyFour
    if f.h ~= nil and h == f.h and m == f.m and s == f.s and twentyFour == f.twentyFour then return end
    f.h, f.m, f.s, f.twentyFour = h, m, s, twentyFour
    f:Show()
    f.text:SetText(formatClock(h, m, twentyFour, s))
end

-- ---------------------------------------------------------------------
-- Framerate beside the clock. Hover shows the game's own performance tooltip,
-- the one from the Game Menu button.
-- ---------------------------------------------------------------------

Map.FPS_TITLE = L["Performance"]
-- From the mouse: right of it, and below the pointer (or above it when the
-- mouse is in the screen's bottom half).
Map.FPS_CURSOR = { x = 12, down = 24, up = 12 }

local function fpsAtCursor()
    local tip = GameTooltip
    local x, y = GetCursorPosition()
    local s = tip:GetEffectiveScale()
    if type(x) ~= "number" or type(s) ~= "number" or s <= 0 then return end
    local off = Map.FPS_CURSOR
    tip:ClearAllPoints()
    if y > UIParent:GetHeight() * UIParent:GetEffectiveScale() / 2 then
        tip:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s + off.x, y / s - off.down)
    else
        tip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / s + off.x, y / s + off.up)
    end
end

local function fpsTooltip(self)
    if type(MainMenuBarPerformanceBarFrame_OnEnter) == "function" then
        self.tooltipText = Map.FPS_TITLE
        if not pcall(MainMenuBarPerformanceBarFrame_OnEnter, self) then return end
    else
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        DUI.Tips.Clear()
        DUI.Tips.Title(Map.FPS_TITLE)
        DUI.Tips.Line(L["Framerate"], string.format("%.0f fps", GetFramerate()))
        DUI.Tips.Flush(GameTooltip)
        GameTooltip:Show()
    end
    -- The game's tooltip goes to its default corner; this one sits at the mouse.
    fpsAtCursor()
end

local function fpsFollow(self)
    if GameTooltip:IsOwned(self) then fpsAtCursor() end
end

local function ensureFps(mm)
    if Map.fps then return Map.fps end
    local f = CreateFrame("Frame", nil, mm)
    f:SetFrameLevel(mm:GetFrameLevel() + Map.TEXT_LIFT)   -- over the ring and the map's dots
    f:SetSize(50, 12)
    f:EnableMouse(true)
    f.__duiOwnTooltipSpot = true   -- the Tooltip module leaves its tooltip to this frame
    f.text = Style.Text(f, 11, "CENTER", ns.MEDIA.font)
    Style.InkText(f.text, "VALUE")
    -- Left and right only: the text keeps its own height, so a big or tall
    -- font isn't cropped by its frame (tall letters got their tops cut off).
    f.text:SetPoint("LEFT", f, "LEFT"); f.text:SetPoint("RIGHT", f, "RIGHT")
    f:SetScript("OnEnter", function(self)
        self.hover = true
        fpsTooltip(self)
        self:SetScript("OnUpdate", fpsFollow)
    end)
    f:SetScript("OnLeave", function(self)
        self.hover = false
        self:SetScript("OnUpdate", nil)
        GameTooltip:Hide()
    end)
    Map.fps = f
    return f
end

-- Redraws the framerate (and the open tooltip); on the clock's ticker.
function Map.UpdateFps()
    local f = Map.fps
    if not f then return end
    if not (Map.cfg and Map.cfg.fps and Map.cfg.fps.enabled) or type(GetFramerate) ~= "function" then
        f:Hide()
        return
    end
    f:Show()
    f.text:SetText(string.format("%.0f fps", GetFramerate()))
    if f.hover and GameTooltip:IsOwned(f) then fpsTooltip(f) end
end

-- ---------------------------------------------------------------------
-- Coordinates at the top middle of the map. Blank where the game gives no
-- position (dungeons, raids).
-- ---------------------------------------------------------------------

Map.COORDS_EVERY = 0.2   -- seconds between redraws

function Map.ReadCoords()
    if type(C_Map) ~= "table" or type(C_Map.GetBestMapForUnit) ~= "function"
        or type(C_Map.GetPlayerMapPosition) ~= "function" then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if type(mapID) ~= "number" then return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if type(pos) ~= "table" or type(pos.GetXY) ~= "function" then return end
    local x, y = pos:GetXY()
    if type(x) ~= "number" or type(y) ~= "number" then return end
    return x * 100, y * 100
end

local function ensureCoords(mm)
    if Map.coords then return Map.coords end
    local f = CreateFrame("Frame", nil, mm)
    f:SetFrameLevel(mm:GetFrameLevel() + Map.TEXT_LIFT)   -- over the ring and the map's dots
    f:SetSize(80, 12)
    f.text = Style.Text(f, 11, "CENTER", ns.MEDIA.font)
    Style.InkText(f.text, "VALUE")
    -- Left and right only: the text keeps its own height, so a big or tall
    -- font isn't cropped by its frame (tall letters got their tops cut off).
    f.text:SetPoint("LEFT", f, "LEFT"); f.text:SetPoint("RIGHT", f, "RIGHT")
    Map.coords = f
    return f
end

-- Written only when the position (or the shown text) has changed: standing
-- still costs nothing.
function Map.UpdateCoords()
    local f = Map.coords
    if not f then return end
    if not (Map.cfg and Map.cfg.coords and Map.cfg.coords.enabled) then
        f:Hide()
        f.shown = nil
        return
    end
    f:Show()
    local x, y = Map.ReadCoords()
    if f.shown ~= nil and x == f.x and y == f.y then return end
    f.x, f.y = x, y
    local text = x and string.format("%.1f, %.1f", x, y) or ""
    if text == f.shown then return end
    f.shown = text
    f.text:SetText(text)
end

-- Runs only while the coordinates are switched on.
local coordsTicker
local function startCoordsTicker(on)
    if not on then
        if coordsTicker then coordsTicker:Cancel() end
        coordsTicker = nil
        return
    end
    if coordsTicker then return end
    coordsTicker = C_Timer.NewTicker(Map.COORDS_EVERY, Map.UpdateCoords)
end

-- ---------------------------------------------------------------------
-- Zone or subzone name at the top middle of the map, coordinates under it.
-- Kept clear of the corner buttons; long names are truncated.
-- ---------------------------------------------------------------------

Map.LOCATION_INSET = 28      -- room left at each side for the corner buttons
-- The zone name wears its PvP color (the game's kinds, softened like Daylight UI's
-- tooltips'); no kind = a plain value.
local INK = Style.INK
Map.ZONE_COLORS = {
    sanctuary = { 0.55, 0.80, 0.92 },
    friendly = INK.GOOD,
    contested = INK.WARN,
    hostile = INK.BAD, arena = INK.BAD, combat = INK.BAD,
}
function Map.ZoneColor()
    local get = C_PvP and C_PvP.GetZonePVPInfo
    local kind = type(get) == "function" and get()
    if type(kind) == "string" and not isSecret(kind) and Map.ZONE_COLORS[kind] then
        return Map.ZONE_COLORS[kind]
    end
    return INK.VALUE
end
-- A text's saved color (map.<text>.color), its default white when unset.
function Map.TextColor(cfg)
    local c = cfg and cfg.color
    if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number" then
        return c
    end
    return INK.VALUE
end
-- The zone name's color: its PvP color, or the player's own pick.
function Map.LocationColor()
    local cfg = Map.cfg and Map.cfg.location
    if cfg and cfg.colorBy == "custom" then return Map.TextColor(cfg) end
    return Map.ZoneColor()
end
Map.LOCATION_EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }

local function ensureLocation(mm)
    if Map.location then return Map.location end
    local f = CreateFrame("Frame", nil, mm)
    f:SetFrameLevel(mm:GetFrameLevel() + Map.TEXT_LIFT)   -- over the ring and the map's dots
    f:SetSize(120, 12)
    f.text = Style.Text(f, 11, "CENTER", ns.MEDIA.font)
    -- Left and right only: the text keeps its own height, so a big or tall
    -- font isn't cropped by its frame (tall letters got their tops cut off).
    f.text:SetPoint("LEFT", f, "LEFT"); f.text:SetPoint("RIGHT", f, "RIGHT")
    if f.text.SetWordWrap then f.text:SetWordWrap(false) end
    Map.location = f
    for _, event in ipairs(Map.LOCATION_EVENTS) do
        DUI.RegisterEvent(event, function() Map.UpdateLocation() end)
    end
    return f
end

function Map.UpdateLocation()
    local f = Map.location
    if not f then return end
    if not (Map.cfg and Map.cfg.location and Map.cfg.location.enabled) then
        f:Hide()
        return
    end
    f:Show()
    local name = type(GetMinimapZoneText) == "function" and GetMinimapZoneText()
    name = type(name) == "string" and name or ""
    local c = Map.LocationColor()
    -- A new place: its name rises in (NORMAL) and its color (city, contested,
    -- sanctuary) blends over from the last one's. The first, and the same
    -- name again (events come in bursts), at once.
    local was, from = f.name, f.color
    f.name, f.color = name, { c[1], c[2], c[3] }
    f.text:SetText(name)
    if was and was ~= name and from then
        DUI.Motion.SlideIn(f, 0, -4, DUI.Motion.NORMAL)
        f.colorKey = f.colorKey or {}   -- one key: a quick second zone change replaces the blend
        DUI.Motion.Tween(f.colorKey, 0, 1, DUI.Motion.NORMAL, function(k)
            f.text:SetTextColor(from[1] + (c[1] - from[1]) * k, from[2] + (c[2] - from[2]) * k,
                from[3] + (c[3] - from[3]) * k)
        end)
    else
        f.text:SetTextColor(c[1], c[2], c[3])
    end
end

-- Clock and framerate share the map's bottom middle: side by side when both
-- show, each centered alone.
Map.BOTTOM_GAP = 6
Map.TEXT_SIZE = 11   -- each map text's size when none is saved
-- Each text's frame grows with its size (made for 70 x 12 and 50 x 12 at 11);
-- no w: only its height (the zone name's width is the map's).
local function sizeText(f, cfg, w)
    local size = (cfg and tonumber(cfg.textSize)) or Map.TEXT_SIZE
    Style.SetTextSize(f.text, size)
    if w then
        f:SetSize(math.ceil(w * size / Map.TEXT_SIZE), size + 1)
    else
        f:SetHeight(size + 1)
    end
end
-- Clock, framerate and coordinates in their saved colors (the zone name's
-- is painted by UpdateLocation).
function Map.PaintTexts()
    local cfg = Map.cfg or {}
    for key, f in pairs({ clock = Map.clock, fps = Map.fps, coords = Map.coords }) do
        local c = Map.TextColor(cfg[key])
        f.text:SetTextColor(c[1], c[2], c[3])
    end
end
function Map.PlaceBottom(mm)
    local clock, fps = Map.clock, Map.fps
    if not (clock and fps) then return end
    local cfg = Map.cfg or {}
    sizeText(clock, cfg.clock, cfg.clock and cfg.clock.seconds and 90 or 70)
    sizeText(fps, cfg.fps, 50)
    local showClock = cfg.clock and cfg.clock.enabled
    local showFps = cfg.fps and cfg.fps.enabled
    clock:ClearAllPoints()
    fps:ClearAllPoints()
    if showClock and showFps then
        clock:SetPoint("BOTTOMRIGHT", mm, "BOTTOM", -Map.BOTTOM_GAP / 2, 3)
        clock.text:SetJustifyH("RIGHT")
        fps:SetPoint("BOTTOMLEFT", mm, "BOTTOM", Map.BOTTOM_GAP / 2, 3)
        fps.text:SetJustifyH("LEFT")
    else
        clock:SetPoint("BOTTOM", mm, "BOTTOM", 0, 3)
        clock.text:SetJustifyH("CENTER")
        fps:SetPoint("BOTTOM", mm, "BOTTOM", 0, 3)
        fps.text:SetJustifyH("CENTER")
    end
end

local function tick()
    Map.UpdateClock()
    Map.UpdateFps()
end

-- Runs only while the clock or the framerate is shown.
local clockTicker
local function startClockTicker(on)
    if not on then
        if clockTicker then clockTicker:Cancel() end
        clockTicker = nil
        return
    end
    if clockTicker then return end
    clockTicker = C_Timer.NewTicker(1, tick)
end

Map.DURABILITY_GAP = 4       -- the armor figure, left of the panel's bottom-left corner

-- The durability figure, just left of the panel's bottom-left corner. It's
-- pulled out of the game's right-side column so that column's layouts skip it;
-- the game takes it back when it shows and the pin moves it out again.
-- It's anchored to an unnamed frame, not the panel: it's an Edit Mode frame,
-- and Edit Mode saves the anchor's name, which doesn't exist yet at the next
-- login. Once the player moves it in Edit Mode (isInDefaultPosition false) it
-- stays where they put it; Edit Mode's reset brings it back here.
function Map.DurabilityMoved(f)
    if f.isDragging then return true end
    local info = f.systemInfo
    return type(info) == "table" and info.isInDefaultPosition == false
end

function Map.PlaceDurability()
    pin(_G.DurabilityFrame, function(f)
        if Map.DurabilityMoved(f) then return end
        local panel = ns.Panel.panel
        if type(panel) ~= "table" then return end
        if f:GetParent() ~= UIParent then f:SetParent(UIParent) end
        local spot = Map.durabilitySpot
        if not spot then
            spot = CreateFrame("Frame", nil, UIParent)
            spot:SetSize(1, 1)
            Map.durabilitySpot = spot
        end
        Map.PlaceAt(spot, "TOPRIGHT", panel, "BOTTOMLEFT", -Map.DURABILITY_GAP, -ns.Panel.GAP)
        Map.PlaceAt(f, "TOPRIGHT", spot, "TOPRIGHT")
        -- The capture bars stand aside for it.
        if DUI.GameMovers then DUI.GameMovers.PlaceSoon() end
    end)
end

-- The game hangs its capture bars (a battleground's flags, world PvP towers)
-- under its own minimap's spot, which the panel covers. Until the player moves
-- them (their "Capture Bars" handle), they stand just left of the panel's
-- bottom-left corner, left of the armor figure while that shows there too.
Map.CAPTURE = "UIWidgetBelowMinimapContainerFrame"

function Map.CaptureHome()
    local panel = ns.Panel.panel
    local f = _G[Map.CAPTURE]
    if type(panel) ~= "table" or not panel:IsShown() or type(f) ~= "table" then return nil end
    local spot = Map.captureSpot
    if not spot then
        spot = CreateFrame("Frame", nil, UIParent)
        spot:SetSize(1, 1)
        Map.captureSpot = spot
    end
    Map.PlaceAt(spot, "TOPRIGHT", panel, "BOTTOMLEFT", -Map.DURABILITY_GAP, -ns.Panel.GAP)
    local x = 0
    local df = _G.DurabilityFrame
    if type(df) == "table" and df:IsShown() and not Map.DurabilityMoved(df) then
        local w = df:GetWidth() * df:GetEffectiveScale() / f:GetEffectiveScale()
        x = -(w + Map.DURABILITY_GAP)
    end
    return { "TOPRIGHT", spot, "TOPRIGHT", x, 0 }
end

function Map.PlaceCapture()
    local GM = DUI.GameMovers
    if not (GM and GM.SetHome) then return end
    if not Map.captureHomed then
        Map.captureHomed = true
        GM.SetHome(Map.CAPTURE, Map.CaptureHome)
        -- Hidden, the armor figure no longer needs the room.
        local df = _G.DurabilityFrame
        if type(df) == "table" and df.HookScript then df:HookScript("OnHide", GM.PlaceSoon) end
        return
    end
    GM.PlaceSoon()
end

function Map.Build(parent)
    area = parent
end

-- Restyles the calendar and tracking buttons like the drawer's corner button:
-- the game's art is hidden and a glyph drawn on top, and they only show while
-- the mouse is over the map. A pending invite keeps the calendar shown and lit.
-- Clicks, menus and tooltips stay the game's. The extra regions are kept in
-- this table, never stored on the game's buttons.
Map.ERASE = DUI.MEDIA .. "mask-none.png"     -- a fully see-through mask
Map.GLYPH = 12               -- the magnifier
Map.BUTTON_BG = 0.6          -- the square's fill, as the drawer's button
Map.WATCH = 0.1              -- seconds between looks for the mouse
Map.INVITE_ART = { "GameTimeCalendarInvitesTexture", "GameTimeCalendarInvitesGlow",
                   "GameTimeCalendarEventAlarmTexture" }

local dressed = {}           -- the game's button -> its look

-- Game textures erased for good: the game sets their art and alpha again
-- on every hover and press, a see-through mask stays on whatever it does.
local function erase(owner, regions)
    local mask
    for _, r in ipairs(regions) do
        if type(r) == "table" and r.SetAlpha then
            r:SetAlpha(0)
            if r.AddMaskTexture and owner.CreateMaskTexture then
                if not mask then
                    mask = owner:CreateMaskTexture()
                    mask:SetTexture(Map.ERASE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                    mask:SetAllPoints(owner)
                end
                pcall(r.AddMaskTexture, r, mask)
            end
        end
    end
end

local function invitePending()
    local t = _G.GameTimeCalendarInvitesTexture
    return type(t) == "table" and t:IsShown() == true
end

local function menuOpen(btn)
    return type(btn.IsMenuOpen) == "function" and btn:IsMenuOpen() == true
end

local function setDay(d)
    local now = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
    if type(now) == "table" and now.monthDay then d.glyph:SetText(now.monthDay) end
end

-- Quiet at rest, the accent under the mouse or with its menu open; an
-- invite waiting lights the square too.
function Map.PaintButton(d)
    local alert = d.kind == "calendar" and invitePending()
    local lit = alert or d.btn:IsMouseOver() == true or menuOpen(d.btn)
    if d.lit == lit and d.alert == alert then return end
    d.lit, d.alert = lit, alert
    if d.kind == "calendar" then
        Style.InkText(d.glyph, lit and "pop" or "LABEL")
    elseif lit then
        d.glyph:SetVertexColor(Style.Accent())
    else
        local c = ns.Panel.ARROW_COLOR
        d.glyph:SetVertexColor(c[1], c[2], c[3])
    end
    if d.shell then
        if alert then Style.LightShell(d.shell) else Style.SetShellColors(d.shell, nil) end
    end
end

-- Dresses one of the game's minimap buttons. btn is the button that takes the
-- clicks, frame is what gets placed and faded (for the tracking button that's
-- the game's holder around it).
function Map.DressButton(btn, frame, kind)
    if type(btn) ~= "table" or not btn.CreateTexture then return end
    if dressed[btn] then return dressed[btn] end
    local d = { btn = btn, frame = frame, kind = kind, goal = 0, alpha = 0 }
    local regions = { btn.StateTexture, btn.AddTexture }
    if kind == "calendar" then
        for _, name in ipairs(Map.INVITE_ART) do regions[#regions + 1] = _G[name] end
    end
    erase(btn, regions)
    if frame ~= btn and type(frame.Background) == "table" then frame.Background:SetAlpha(0) end
    local case = CreateFrame("Frame", nil, btn)
    case:SetAllPoints(btn)
    local s = Style.Shell(case, { borderPx = ns.Panel.XP_BORDER })
    if s and s.bg then s.bg:SetAlpha(Map.BUTTON_BG) end
    d.case, d.shell = case, s
    if kind == "calendar" then
        d.glyph = Style.Text(case, Style.SIZE.small, "CENTER")
        d.glyph:SetPoint("CENTER", case, "CENTER", 0, 0)
        setDay(d)
    else
        d.glyph = case:CreateTexture(nil, "OVERLAY")
        d.glyph:SetTexture(DUI.MEDIA .. "ui-search.png")
        d.glyph:SetSize(Map.GLYPH, Map.GLYPH)
        d.glyph:SetPoint("CENTER", case, "CENTER", 0, 0)
    end
    btn:HookScript("OnEnter", function() Map.PaintButton(d) end)
    btn:HookScript("OnLeave", function() Map.PaintButton(d) end)
    btn:HookScript("OnMouseDown", function() DUI.Motion.Bump(case, 0.88) end)
    frame:SetAlpha(0)
    dressed[btn] = d
    Map.PaintButton(d)
    return d
end

function Map.Dressed(btn) return dressed[btn] end

-- New mail: an accent-colored envelope in the map's top corner, shown while the
-- game's mail frame is. It lives on the map, not anchored to the game's frame,
-- so it can fade out after that frame hides.
Map.MAIL_GLYPH = 20

function Map.PaintMail(d)
    Style.PaintAccent(d.glyph)
end

function Map.PlaceMail(case, mm)
    case:ClearAllPoints()
    case:SetPoint("TOPLEFT", mm, "TOPLEFT", Map.BUTTON_INSET, -Map.BUTTON_INSET)
end

function Map.DressMail(btn, mm)
    if type(btn) ~= "table" or not btn.CreateTexture then return end
    local d = Map.mail
    if d then
        Map.PaintMail(d)
        return d
    end
    erase(btn, { btn.MailIcon })
    local case = CreateFrame("Frame", nil, mm)
    case:SetSize(ns.Drawer.SIZE, ns.Drawer.SIZE)
    Map.PlaceMail(case, mm)
    case:SetFrameLevel(mm:GetFrameLevel() + 5)
    local glyph = case:CreateTexture(nil, "OVERLAY")
    glyph:SetTexture(DUI.MEDIA .. "ui-mail.png")
    glyph:SetSize(Map.MAIL_GLYPH, Map.MAIL_GLYPH)
    glyph:SetPoint("CENTER", case, "CENTER", 0, 0)
    d = { btn = btn, case = case, glyph = glyph, goal = btn:IsShown() and 1 or 0 }
    d.alpha = d.goal
    case:SetAlpha(d.alpha)
    local function fade(want)
        if d.goal == want then return end
        d.goal = want
        Map.PaintMail(d)
        DUI.Motion.Tween("infopanel:mapButton:mail", d.alpha, want, DUI.Motion.FAST, function(v)
            d.alpha = v
            case:SetAlpha(v)
        end)
    end
    btn:HookScript("OnShow", function() fade(1) end)
    btn:HookScript("OnHide", function() fade(0) end)
    Map.mail = d
    Map.PaintMail(d)
    return d
end

-- Every WATCH seconds: each shows while the mouse is over the map or the
-- button itself, its menu is open, or (the calendar) an invite waits.
function Map.WatchButtons()
    if not (area and Map.cfg and Map.cfg.buttons) then return end
    local over = area:IsMouseOver() == true
    for btn, d in pairs(dressed) do
        local invite = d.kind == "calendar" and invitePending()
        -- At rest (the mouse away from the map, the button gone, unlit, no invite):
        -- nothing more to ask. The buttons sit on the map, so over one is over the map.
        if over or invite or d.goal ~= 0 or d.lit then
            Map.WatchButton(btn, d, over, invite)
        end
    end
end

-- One dressed button: shown while the mouse is on the map or it, its menu is open
-- or (the calendar) an invite waits.
function Map.WatchButton(btn, d, over, invite)
    local want = (over or btn:IsMouseOver() == true or menuOpen(btn) or invite) and 1 or 0
    if d.goal ~= want then
        d.goal = want
        if want == 1 and d.kind == "calendar" then setDay(d) end
        DUI.Motion.Tween("infopanel:mapButton:" .. d.kind, d.alpha, want, DUI.Motion.FAST, function(v)
            d.alpha = v
            d.frame:SetAlpha(v)
        end)
    end
    Map.PaintButton(d)
end

-- Never nudge the zoom to force the map to redraw: players saw it zoom in and
-- out. The black map actually came from hiding the game's cluster (Map.QuietCluster).

-- Location, then coordinates, at the top middle of the map's square.
function Map.PlaceTop(mm, location, coords)
    local cfg = Map.cfg or {}
    sizeText(location, cfg.location)
    sizeText(coords, cfg.coords, 80)
    location:ClearAllPoints()
    location:SetPoint("TOP", mm, "TOP", 0, -3)
    coords:ClearAllPoints()
    if cfg.location and cfg.location.enabled then
        coords:SetPoint("TOP", location, "BOTTOM", 0, -1)
    else
        coords:SetPoint("TOP", mm, "TOP", 0, -3)
    end
end

-- Rotation toggled (by Daylight UI, Edit Mode at login, or another addon). Apply
-- re-runs every pin so the map and everything on it follow. A protected map
-- waits for combat to end.
function Map.Fit()
    local cfg = Map.cfg
    if not (cfg and cfg.enabled and area) then return end
    -- The game sets its own mask when the setting changes: Daylight UI's goes on again.
    Map.maskSet = nil
    if InCombatLockdown() then
        DUI.AfterCombat(Map.Fit, "infopanel:mapFit")
        return
    end
    -- Turning makes the map round, so a panel without a box around a round
    -- map lays itself out again (which applies the map too).
    local mod = ns.module
    if mod and ns.Panel.Bare(mod.db) ~= ns.Panel.bare then return ns.Refresh(mod) end
    Map.Apply(cfg)
end

DUI.RegisterEvent("CVAR_UPDATE", function(_, name)
    if name == "rotateMinimap" then Map.Fit() end
end)

-- After a loading screen in a city, indoors or in a dungeon, the moved map came
-- up empty until its zoom changed. EllesmereUI forces a redraw after its own
-- setup: zoom out and back in the same frame, which never shows. The game
-- ignores that while the map can't be seen (the panel waits at 0 for the
-- login fade-in), so it waits until the map shows. A second one a moment later
-- fills in what loaded meanwhile. Once per loading screen, never at doors.
Map.REDRAW_AGAIN = 0.5   -- seconds between the two
Map.REDRAW_LOOK = 0.1    -- how often to look whether the map shows yet

function Map.Redraw()
    local mm = Minimap
    if not (Map.cfg and Map.cfg.enabled and type(mm) == "table" and mm.SetZoom) then return end
    local z = mm:GetZoom()
    if type(z) ~= "number" then return end
    local levels = mm.GetZoomLevels and mm:GetZoomLevels() or 1
    local other = z > 0 and z - 1 or (levels > 1 and z + 1 or nil)
    if not other then return end
    mm:SetZoom(other)
    mm:SetZoom(z)
end

-- Solid and on screen: the game ignores a redraw of a see-through map.
local function mapShows()
    local mm = Minimap
    if not (type(mm) == "table" and mm:IsVisible()) then return false end
    local a = mm:GetEffectiveAlpha()
    return type(a) == "number" and a > 0.999
end

local asks = 0
local function redrawOnceShown(mine)
    if mine ~= asks or not (Map.cfg and Map.cfg.enabled) then return end
    if not mapShows() then
        C_Timer.After(Map.REDRAW_LOOK, function() redrawOnceShown(mine) end)
        return
    end
    DUI.SafeCall(Map.Redraw)
    C_Timer.After(Map.REDRAW_AGAIN, function() DUI.SafeCall(Map.Redraw) end)
end

local function redrawSoon()
    asks = asks + 1
    local mine = asks
    C_Timer.After(0, function() redrawOnceShown(mine) end)
end

DUI.RegisterEvent("LOADING_SCREEN_DISABLED", redrawSoon)

-- The quest areas the client draws on the map (their fill and glowing edge)
-- ignore its alpha, as the arrow does, but stay inside its mask. So while the
-- map is fully out of sight it wears a see-through mask, and its own shape
-- comes back with it.
Map.areasAway = false
function Map.PutMask(mm)
    if type(mm) ~= "table" or type(mm.SetMaskTexture) ~= "function" then return end
    local mask = Map.areasAway and Map.ERASE or (Map.Round() and Map.ROUND_MASK or Map.MASK)
    if Map.maskSet == mask then return end
    if InCombatLockdown() and mm.IsProtected and mm:IsProtected() then
        DUI.AfterCombat(function() Map.PutMask(Minimap) end, "infopanel:mapMask")
        return
    end
    mm:SetMaskTexture(mask)
    Map.maskSet = mask
end

-- The game stops updating the minimap's picture while it's even slightly
-- see-through: walk indoors meanwhile and it stays empty, at full alpha
-- again too, until its zoom changes. So the map ignores the panel's opacity
-- and stays solid at rest. It still fades out and in with the panel, the AFK
-- screen and the NPC scene, and once it's solid again it gets the loading
-- screen's redraw.
Map.early = false   -- set by the panel while the map skips the login fade-in
Map.dim = false     -- has been see-through since it was last redrawn

function Map.Follow()
    local mm, cfg = Minimap, Map.cfg
    if not (cfg and cfg.enabled and area and type(mm) == "table") then return end
    if not mm:IsIgnoringParentAlpha() then mm:SetIgnoreParentAlpha(true) end
    local want
    if DUI.Fade.MapIsAway() then
        want = 0
    elseif Map.early then
        want = 1
    else
        -- How far the panel is through its fade: its alpha now over the
        -- alpha it rests at (the panel's opacity setting). At full strength,
        -- the most common case, there's nothing to ask.
        local now = area:GetEffectiveAlpha()
        if type(now) ~= "number" or now > 0.999 then
            want = 1
        else
            local _, _, _, opacity = DUI.Fade.State("InfoPanel.panel")
            local rest = type(opacity) == "number" and math.max(opacity, 0.01) or 1
            want = math.min(1, now / rest)
            if want > 0.999 then want = 1 elseif want < 0.001 then want = 0 end
        end
    end
    local was = mm:GetAlpha()
    if type(was) ~= "number" or math.abs(was - want) > 0.0001 then mm:SetAlpha(want) end
    -- Its arrow and dots ignore its alpha: fully out of sight, they go too.
    DUI.Fade.MapDots(want > 0)
    -- So do the quest areas, which stay inside its mask.
    Map.areasAway = want == 0
    Map.PutMask(mm)
    if want < 1 then
        Map.dim = true
    elseif Map.dim then
        Map.dim = false
        redrawSoon()
    end
end
DUI.Fade.mapFollow = function() DUI.SafeCall(Map.Follow) end
-- The map's alpha comes from the whole screen's too, and the screen can be
-- dimmed by something that never touches the panel. Without this, the map
-- stayed invisible after the screen came back, until the next reload.
DUI.On("UIAlpha", DUI.Fade.mapFollow)

-- In dungeons the game uses Blizzard_HybridMinimap, which draws map art on its
-- own BACKGROUND-strata frame under the map. That ended up under the panel's
-- background, so dungeons showed a blank map. It's moved into the map's strata
-- just below the map, using the map's mask instead of its round one set 3 px in.
function Map.DressHybrid()
    local h = _G.HybridMinimap
    local mm = Minimap
    if type(h) ~= "table" or not h.SetFrameStrata or not (mm and area) then return end
    if InCombatLockdown() and h.IsProtected and h:IsProtected() then
        DUI.AfterCombat(Map.DressHybrid, "infopanel:hybrid")
        return
    end
    local strata, level = mm:GetFrameStrata(), math.max(0, mm:GetFrameLevel() - 1)
    for _, f in ipairs({ h, type(h.MapCanvas) == "table" and h.MapCanvas or nil }) do
        -- Fixed in the game's XML: unfixed to move it, fixed again after (as the drawer's buttons).
        if f:GetFrameStrata() ~= strata then
            if f.SetFixedFrameStrata then f:SetFixedFrameStrata(false) end
            f:SetFrameStrata(strata)
            if f.SetFixedFrameStrata then f:SetFixedFrameStrata(true) end
        end
    end
    if h:GetFrameLevel() ~= level then
        if h.SetFixedFrameLevel then h:SetFixedFrameLevel(false) end
        h:SetFrameLevel(level)
        if h.SetFixedFrameLevel then h:SetFixedFrameLevel(true) end
    end
    local mask = h.CircleMask
    local want = Map.Round() and Map.ROUND_MASK or Map.MASK
    if type(mask) == "table" and mask.SetTexture and Map.hybridMask ~= want then
        mask:SetTexture(want, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:ClearAllPoints()
        mask:SetAllPoints(h)
        Map.hybridMask = want
    end
end

DUI.RegisterEvent("ADDON_LOADED", function(_, name)
    if name == "Blizzard_HybridMinimap" and Map.cfg and Map.cfg.enabled then Map.DressHybrid() end
end)

-- The game's minimap cluster stays shown but transparent and mouse-disabled,
-- never hidden: hiding it made the map go black in cities and at doors. What's
-- left on it (zone text, border) is moved to the hidden frame instead.
function Map.QuietCluster(cluster)
    if type(cluster) ~= "table" or not cluster.GetChildren then return end
    Map.ParentTo(cluster, UIParent)
    if cluster:GetAlpha() ~= 0 then cluster:SetAlpha(0) end
    if cluster.EnableMouse and cluster:IsMouseEnabled() then cluster:EnableMouse(false) end
    for _, child in ipairs({ cluster:GetChildren() }) do
        if child ~= Minimap then ns.Panel.Park(child) end
    end
end

-- The wheel zooms the map: one function, so it's set once and found again.
function Map.Wheel(self, delta)
    if delta > 0 then
        if self:GetZoom() < self:GetZoomLevels() - 1 then self:SetZoom(self:GetZoom() + 1) end
    elseif self:GetZoom() > 0 then
        self:SetZoom(self:GetZoom() - 1)
    end
end

function Map.Apply(cfg)
    local mm = Minimap
    if not (cfg.enabled and mm) then return end
    local size = ns.Panel.mapSize or cfg.size
    Map.cfg = cfg
    -- Only set what changed. Setting the map's parent, point, size or mask
    -- again, even unchanged, can blank it (it went black on roster changes in
    -- a group). Events mostly re-place the buttons; the map itself rarely moves.
    pin(mm, function(f)
        Map.ParentTo(f, area)
        Map.PlaceAt(f, "TOPLEFT", area, "TOPLEFT")
        Map.SizeTo(f, size, size)
        Map.PutMask(f)
    end)
    -- The map's layer first: the ring (+2) and texts (+TEXT_LIFT) go over it.
    Map.LevelTo(mm, area:GetFrameLevel() + 1)
    Map.DressHybrid()
    Map.PaintRing(Map.Round(), Map.Turning())
    for _, key in ipairs({ "location", "coords", "clock", "fps" }) do
        local t = Map[key]
        if t then t:SetFrameLevel(mm:GetFrameLevel() + Map.TEXT_LIFT) end
    end
    -- The game never sets the blob rings itself, so once is enough.
    if not Map.blobsSet then
        Map.blobsSet = true
        for _, kind in ipairs(Map.BLOB_RINGS) do
            for _, part in ipairs({ "RingScalar", "RingAlpha" }) do
                local set = mm["Set" .. kind .. part]
                if type(set) == "function" then DUI.SafeCall(set, mm, 0) end
            end
        end
    end
    if not mm:IsMouseWheelEnabled() then mm:EnableMouseWheel(true) end
    if mm:GetScript("OnMouseWheel") ~= Map.Wheel then mm:SetScript("OnMouseWheel", Map.Wheel) end

    -- Keep what's useful, then park the rest of the cluster.
    local cluster = MinimapCluster
    local indicators = cluster and (cluster.IndicatorFrame or cluster.MailFrame)
    pin(indicators, function(f)
        Map.ParentTo(f, mm)
        Map.PlaceAt(f, "TOPLEFT", mm, "TOPLEFT", Map.BUTTON_INSET, -Map.BUTTON_INSET)
        -- The mouse's spot for the game's tooltip: the square's size, not its 32 x 24.
        if type(f.MailFrame) == "table" then Map.SizeTo(f.MailFrame, ns.Drawer.SIZE, ns.Drawer.SIZE) end
    end)
    if type(indicators) == "table" then Map.DressMail(indicators.MailFrame, mm) end
    -- The game's queue eye is big for a square map: half size.
    pin(QueueStatusButton, function(f)
        Map.ParentTo(f, mm)
        Map.ScaleTo(f, Map.QUEUE_SCALE)
        Map.PlaceAt(f, "BOTTOMLEFT", mm, "BOTTOMLEFT", 0, 0)
    end)
    -- The calendar and the tracking button, down the map's right edge. They
    -- are the game's own (their clicks and menus unchanged). Switched off,
    -- they go back into the hidden cluster, their parent, rather than under
    -- a Daylight UI frame.
    local calendar = GameTimeFrame
    local tracking = cluster and cluster.Tracking or MiniMapTrackingButton
    local trackButton = type(tracking) == "table" and type(tracking.Button) == "table" and tracking.Button or tracking
    local square = ns.Drawer.SIZE
    pin(calendar, function(f)
        if not Map.cfg.buttons then
            ns.Panel.Park(f)
            return
        end
        Map.ParentTo(f, mm)
        Map.SizeTo(f, square, square)
        Map.LevelTo(f, mm:GetFrameLevel() + 5)
        Map.PlaceAt(f, "TOPRIGHT", mm, "TOPRIGHT", -Map.BUTTON_INSET, -Map.BUTTON_INSET)
    end)
    pin(tracking, function(f)
        if not Map.cfg.buttons then
            ns.Panel.Park(f)
            return
        end
        Map.ParentTo(f, mm)
        Map.LevelTo(f, mm:GetFrameLevel() + 5)
        Map.SizeTo(f, square, square)
        if trackButton ~= f then Map.SizeTo(trackButton, square, square) end
        if type(calendar) == "table" then
            Map.PlaceAt(f, "TOP", calendar, "BOTTOM", 0, -Map.BUTTON_GAP)
        else
            Map.PlaceAt(f, "TOPRIGHT", mm, "TOPRIGHT", -Map.BUTTON_INSET, -Map.BUTTON_INSET)
        end
    end)
    Map.DressButton(calendar, calendar, "calendar")
    if type(trackButton) == "table" then Map.DressButton(trackButton, tracking, "tracking") end
    if not Map.buttonTicker then
        Map.buttonTicker = C_Timer.NewTicker(Map.WATCH, function() DUI.SafeCall(Map.WatchButtons) end)
    end
    -- The game's addon compartment (every addon that lists itself there,
    -- Daylight UI's included): the map's bottom-right corner, with the other buttons.
    -- With the drawer on, its entries are in the drawer and the drawer's
    -- button has that corner.
    pin(_G.AddonCompartmentFrame, function(f)
        if not Map.cfg.buttons or Map.cfg.drawer then
            ns.Panel.Park(f)
            return
        end
        Map.ParentTo(f, mm)
        Map.LevelTo(f, mm:GetFrameLevel() + 5)
        Map.PlaceAt(f, "BOTTOMRIGHT", mm, "BOTTOMRIGHT", -Map.BUTTON_INSET, Map.BUTTON_INSET)
    end)
    for _, key in ipairs({ "ZoomIn", "ZoomOut", "ZoomHitArea" }) do ns.Panel.Park(mm[key]) end
    for _, name in ipairs(Map.DECOR) do ns.Panel.Park(_G[name]) end
    Map.QuietCluster(cluster)
    Map.PlaceDurability()
    Map.PlaceCapture()

    -- The clock and framerate, bottom middle of the map.
    local clock = ensureClock(mm)
    local fps = ensureFps(mm)
    for _, f in ipairs({ clock, fps }) do
        f:SetParent(mm)
        f:SetFrameLevel(mm:GetFrameLevel() + 5)
    end
    Map.PlaceBottom(mm)
    tick()
    startClockTicker((cfg.clock and cfg.clock.enabled) or (cfg.fps and cfg.fps.enabled))

    -- Location, then coordinates, top middle of the map.
    local location = ensureLocation(mm)
    location:SetParent(mm)
    location:SetFrameLevel(mm:GetFrameLevel() + 5)
    location:SetWidth(math.max(40, size - 2 * Map.LOCATION_INSET))
    Map.UpdateLocation()
    local coords = ensureCoords(mm)
    coords:SetParent(mm)
    coords:SetFrameLevel(mm:GetFrameLevel() + 5)
    Map.PlaceTop(mm, location, coords)
    Map.PaintTexts()
    Map.UpdateCoords()
    startCoordsTicker(cfg.coords and cfg.coords.enabled)

    -- Addon buttons: gathered into the drawer in the map's corner.
    ns.Drawer.Apply(cfg)
    Map.Follow()
end
