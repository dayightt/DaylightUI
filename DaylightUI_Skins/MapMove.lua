-- Lets the world map be dragged by its title bar and resized by a grip in the
-- bottom-right corner (it scales, keeping the top-left corner in place). The game
-- re-docks the map on the left whenever it lays out its panels (the map opening,
-- another window opening beside it, going back to small), so after each of those
-- it's put back where the player left it. We post-hook the global panel
-- functions and the map's OnShow for that. When maximized it's the game's (its
-- own size, scale 1). Right-click the title bar, or /dui reset, to restore it.
--
-- Nothing of the game's is overwritten or called: just our own drag strip and
-- grip, SetPoint/SetScale/StartMoving on the map, post-hooks on globals, and
-- EventRegistry callbacks.
--
-- With OpenMap loaded, it owns moving and sizing (its own title bar and grips),
-- so this stands down: no strip, grip, saved spot or scale, the same way OpenMap
-- treats Move Any. The slim top row stays ours, since the skin draws it either
-- way (the game's two rows left a tall header and cut off the quest journal's
-- search). It never sets the window size in that case.

local _, ns = ...
local DUI = DaylightUI

local MapMove = {}
ns.MapMove = MapMove

MapMove.BAR_HEIGHT = 22
MapMove.BUTTONS = 70 -- room at the bar's right end for maximize and close
MapMove.MIN, MapMove.MAX = 0.6, 1.4 -- grip scale range
MapMove.GRIP = 16
MapMove.GRIP_LEVEL = 700 -- above the quest log's corner; our journal covers that side at 500 (Journal.LEVEL)
-- The top in one row. The game reserves 67 px above the map
-- (TITLE_CANVAS_SPACER_FRAME_HEIGHT: title row, then the zone buttons). Ours is
-- SLIM, with the zone buttons NAV_Y down and NAV_H tall (the game's own bar
-- height, 67 - 25 - 9).
MapMove.TOP, MapMove.SLIM = 67, 37
MapMove.NAV_Y, MapMove.NAV_H = 2, 33

local cfg, hooked = nil, false

local function map()
    local f = _G.WorldMapFrame
    return type(f) == "table" and f or nil
end

local function maximized(f)
    if type(f.IsMaximized) == "function" then return f:IsMaximized() and true or false end
    return f.isMaximized == true
end

local function ratio(f)
    return f:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

-- The saved spot, only if it's two numbers (a damaged import may have neither).
local function savedSpot()
    local s = cfg and cfg.mapSpot
    if type(s) == "table" and type(s[1]) == "number" and type(s[2]) == "number" then return s end
    return nil
end

-- Moves the map to its saved spot: top-left corner, in UIParent units from
-- UIParent's bottom-left. Does nothing if unsaved, hidden or maximized.
-- MapMove.Scale returns the grip's scale (1 = the game's size).
function MapMove.Scale()
    local s = cfg and cfg.mapScale
    if type(s) ~= "number" then return 1 end
    return math.max(MapMove.MIN, math.min(MapMove.MAX, s))
end

local function isFrame(x) return type(x) == "table" and type(x.SetPoint) == "function" end

-- Moves the zone buttons up into the title row, and the map up and the window
-- shorter by the same amount, so the map keeps its size. We only hold on to what
-- the game never resets (the map's top anchor, the bar's right end, the title's
-- alpha). The game resets the window height and the bar's top-left on every
-- maximize/minimize, so each layout puts them back (maximized: the game's own
-- size, computed with our top). When unskinned, the game's anchors go back once.
-- LogBeside: extra width for the quest list beside a maximized map, or 0.
function MapMove.LogBeside(f)
    if not (cfg and cfg.mapLogBeside ~= false) then return 0 end
    local log = f.QuestLog
    if not (type(log) == "table" and log.IsShown and log:IsShown()) then return 0 end
    return type(f.questLogWidth) == "number" and f.questLogWidth or 0
end

function MapMove.Slim(f, on)
    local spacer, sc, nav = f.TitleCanvasSpacerFrame, f.ScrollContainer, f.NavBar
    if not (isFrame(spacer) and isFrame(sc) and isFrame(nav) and type(f.minimizedHeight) == "number") then return end
    if not on and not MapMove.slimmed then return end
    MapMove.slimmed = on or nil
    local consts = _G.WorldMapConstants
    local navX = type(consts) == "table" and type(consts.NAVBAR_X_OFFSET) == "number" and consts.NAVBAR_X_OFFSET or -4
    local border = f.BorderFrame
    local title = type(border) == "table" and border.TitleContainer
    local bar = MapMove.bar
    -- OpenMap sizes the window and restores its own size after anyone else's,
    -- so the map just takes the freed row.
    local sized = not DUI.OpenMap.Loaded()
    if on then
        local cut = MapMove.TOP - MapMove.SLIM
        if not sized then
            -- OpenMap owns the window size
        elseif maximized(f) then
            -- The game's UpdateMaximizedSize, with our top in place of its 67.
            -- With mapLogBeside on, the window grows by the quest list's width
            -- (as far as the screen allows) so the map keeps its size, like the
            -- windowed map does. The game's own version takes the room out of
            -- the map.
            local pw, ph = f:GetParent():GetSize()
            local minW = type(f.minimizedWidth) == "number" and f.minimizedWidth or 0
            local full = (ph - MapMove.SLIM) * minW / (f.minimizedHeight - MapMove.TOP)
            local logW = MapMove.LogBeside(f)
            local w = math.min(pw - 30, full + logW)
            local h = full > 0 and ((ph - MapMove.SLIM) * ((w - logW) / full) + MapMove.SLIM) or 0
            w, h = math.floor(w), math.floor(h)
            if w > 0 and h > 0 and (math.abs(f:GetWidth() - w) > 0.01 or math.abs(f:GetHeight() - h) > 0.01) then
                f:SetSize(w, h)
            end
        elseif math.abs(f:GetHeight() - (f.minimizedHeight - cut)) > 0.01 then
            f:SetHeight(f.minimizedHeight - cut)
        end
        sc:SetPoint("TOPLEFT", spacer, "BOTTOMLEFT", 0, cut)
        nav:SetPoint("TOPLEFT", spacer, "TOPLEFT", 8, -MapMove.NAV_Y)
        -- The spacer ends at the quest log, or without one at the window's
        -- edge under maximize and close.
        local log = f.QuestLog
        local logShown = type(log) == "table" and log.IsShown and log:IsShown()
        nav:SetPoint("BOTTOMRIGHT", spacer, "TOPRIGHT", navX - (logShown and 0 or MapMove.BUTTONS),
            -(MapMove.NAV_Y + MapMove.NAV_H))
        if isFrame(title) then title:SetAlpha(0) end
        -- The drag strip sits under the zone buttons, which take their own
        -- clicks; the empty part of the row drags.
        if bar then
            bar:SetFrameStrata(nav:GetFrameStrata())
            bar:SetFrameLevel(nav:GetFrameLevel())
            bar:SetHeight(MapMove.SLIM)
        end
    else
        sc:SetPoint("TOPLEFT", spacer, "BOTTOMLEFT", 0, 0)
        nav:SetPoint("BOTTOMRIGHT", spacer, "BOTTOMRIGHT", navX, 9)
        if isFrame(title) then title:SetAlpha(1) end
        if bar then
            bar:SetFrameStrata(bar.strata)
            bar:SetFrameLevel(bar.level)
            bar:SetHeight(MapMove.BAR_HEIGHT)
        end
        -- Windowed and no longer ours: back to the game's height (maximized,
        -- the game sets its own).
        if sized and not maximized(f) then f:SetHeight(f.minimizedHeight) end
    end
end

function MapMove.Apply()
    local f = map()
    if not f then return end
    if DUI.OpenMap.Loaded() then
        if MapMove.bar then MapMove.bar:Hide() end
        if MapMove.grip then MapMove.grip:Hide() end
        -- Just the top row (MapMove.Slim sets no size with OpenMap).
        if not f:IsShown() then return end
        if InCombatLockdown() and f:IsProtected() then
            DUI.AfterCombat(MapMove.Apply, "skins:mapmove")
            return
        end
        MapMove.Slim(f, MapMove.slim)
        return
    end
    if not f:IsShown() then return end
    if InCombatLockdown() and f:IsProtected() then
        DUI.AfterCombat(MapMove.Apply, "skins:mapmove")
        return
    end
    local big = maximized(f)
    MapMove.Slim(f, MapMove.slim)
    local want = big and 1 or MapMove.Scale()
    if math.abs((f:GetScale() or 1) - want) > 0.001 then f:SetScale(want) end
    if MapMove.grip then MapMove.grip:SetShown(not big) end
    local spot = savedSpot()
    if not spot or big then return end
    local r = ratio(f)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", spot[1] / r, spot[2] / r)
end

local function save(f)
    local cx, cy = f:GetCenter()
    if not cx then return end
    local r = ratio(f)
    cfg.mapSpot = { DUI.Pixel.Snap(UIParent, (cx - f:GetWidth() / 2) * r),
                    DUI.Pixel.Snap(UIParent, (cy + f:GetHeight() / 2) * r) }
    MapMove.Apply()
end

-- Forgets the saved spot, so the game's own layout places the map from the
-- next time it lays it out (opening it, at the latest).
function MapMove.Reset()
    if cfg then cfg.mapSpot, cfg.mapScale = nil, nil end
    MapMove.Apply()
end

-- The grip: the right edge follows the cursor, offset by where it was grabbed
-- so it doesn't jump. The top-left corner stays.
local function cursorX()
    local x = GetCursorPosition()
    return (x or 0) / UIParent:GetEffectiveScale()
end

function MapMove.SizeStep()
    local f, spot, grip = map(), savedSpot(), MapMove.grip
    if not (f and spot and grip and grip.grab) then return end
    local w = f:GetWidth()
    if type(w) ~= "number" or w <= 0 then return end
    local s = (cursorX() + grip.grab - spot[1]) / w
    cfg.mapScale = math.floor(math.max(MapMove.MIN, math.min(MapMove.MAX, s)) * 100 + 0.5) / 100
    MapMove.Apply()
end

local function makeGrip(f)
    local grip = CreateFrame("Button", nil, f)
    MapMove.grip = grip
    grip:SetSize(MapMove.GRIP, MapMove.GRIP)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    local border = type(f.BorderFrame) == "table" and f.BorderFrame or f
    grip:SetFrameStrata("HIGH")
    grip:SetFrameLevel(math.max(border:GetFrameLevel() + 20, MapMove.GRIP_LEVEL))
    grip.icon = grip:CreateTexture(nil, "OVERLAY")
    grip.icon:SetTexture(DUI.MEDIA .. "ui-grip.png")
    grip.icon:SetAllPoints(grip)
    grip.icon:SetVertexColor(0.62, 0.62, 0.65, 0.8)
    grip:SetScript("OnEnter", function() grip.icon:SetVertexColor(1, 1, 1, 1) end)
    grip:SetScript("OnLeave", function() if not grip.grab then grip.icon:SetVertexColor(0.62, 0.62, 0.65, 0.8) end end)
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or maximized(f) or (InCombatLockdown() and f:IsProtected()) then return end
        -- From here on we place it: save the spot first, then scale from there.
        if not savedSpot() then save(f) end
        local spot = savedSpot()
        if not spot then return end
        grip.grab = spot[1] + f:GetWidth() * f:GetScale() - cursorX()
        grip:SetScript("OnUpdate", MapMove.SizeStep)
    end)
    grip:SetScript("OnMouseUp", function()
        if not grip.grab then return end
        MapMove.SizeStep()
        grip.grab = nil
        grip:SetScript("OnUpdate", nil)
        if not grip:IsMouseOver() then grip.icon:SetVertexColor(0.62, 0.62, 0.65, 0.8) end
        save(f)
    end)
end

local function makeBar(f)
    local bar = CreateFrame("Frame", nil, f)
    MapMove.bar = bar
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -MapMove.BUTTONS, 0)
    bar:SetHeight(MapMove.BAR_HEIGHT)
    -- Over the border frame's art so it gets the mouse, leaving the buttons at
    -- the right end free.
    local border = type(f.BorderFrame) == "table" and f.BorderFrame or f
    bar:SetFrameLevel(border:GetFrameLevel() + 1)
    bar.strata, bar.level = bar:GetFrameStrata(), bar:GetFrameLevel()
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function()
        if maximized(f) or (InCombatLockdown() and f:IsProtected()) then return end
        f:SetMovable(true)
        f:SetClampedToScreen(true)
        f:StartMoving()
    end)
    bar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        -- Saved by us, not in the game's layout cache.
        f:SetUserPlaced(false)
        save(f)
    end)
    bar:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then MapMove.Reset() end
    end)
end

local function hook(f)
    if hooked then return end
    hooked = true
    makeBar(f)
    makeGrip(f)
    -- The skin may have laid out the top before the strip existed.
    MapMove.Apply()
    -- Some ways of opening skip the panel functions, so apply next frame too.
    f:HookScript("OnShow", function()
        MapMove.Apply()
        C_Timer.After(0, MapMove.Apply)
    end)
    for _, name in ipairs({ "ShowUIPanel", "HideUIPanel", "UpdateUIPanelPositions" }) do
        if type(_G[name]) == "function" then hooksecurefunc(name, MapMove.Apply) end
    end
    -- Maximized: back to the game's size and scale 1. Minimized: ours again.
    -- These fire before the game sets its own size and the zone buttons' spot,
    -- so apply next frame too.
    local reg = _G.EventRegistry
    if type(reg) == "table" and type(reg.RegisterCallback) == "function" then
        local function soon()
            MapMove.Apply()
            C_Timer.After(0, MapMove.Apply)
        end
        reg:RegisterCallback("WorldMapMaximized", soon, MapMove)
        reg:RegisterCallback("WorldMapMinimized", soon, MapMove)
        -- When maximized, the window grows or shrinks as the quest list opens
        -- or closes (MapMove.LogBeside).
        local log = f.QuestLog
        if type(log) == "table" and log.HookScript then
            log:HookScript("OnShow", soon)
            log:HookScript("OnHide", soon)
        end
    end
end

-- Waits for the map like a skin (retried as addons load) but in no pack, so it
-- works whether or not the map is skinned.
ns.Engine.Register({ key = "worldmap.move", apply = function()
    local f = map()
    if not f then return false end
    hook(f)
end })

DUI.Movers.onResetAll[#DUI.Movers.onResetAll + 1] = MapMove.Reset

function MapMove.Start(c)
    cfg = c
    MapMove.Apply()
end
