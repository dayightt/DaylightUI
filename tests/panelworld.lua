local stub = require("stub")

-- The info panel's world for its tests (test_infopanel, test_meters): the game's
-- minimap and its cluster, experience, the tooltip and pop-ups, and C_Spell for the
-- meter's spells (the damage meter is the fake game's own, stub.DamageMeter).
-- PW.login() loads the panel with its meter shown.
local PW = {}

function PW.world()
    -- The damage meter is the fake game's own (stub.DamageMeter), filled through stub.meter.
    _G.GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
    _G.StaticPopupDialogs = {}
    _G.StaticPopup_Show = function(which) stub.popup = which end
    _G.C_Spell = {
        GetSpellName = function(id) return ({ [1] = "Fireball", [2] = "Fire Blast" })[id] end,
        GetSpellTexture = function(id) return 1000 + id end,
    }
    _G.UnitGUID = function(u) if u == "player" then return "Player-1" end end
    stub.cvars, stub.cvarWrites = {}, 0
    _G.SetCVar = function(k, v) stub.cvars[k] = v; stub.cvarWrites = stub.cvarWrites + 1 end
    _G.GetCVar = function(k) return stub.cvars[k] end
    local cluster = CreateFrame("Frame", "MinimapCluster", UIParent)
    cluster.IndicatorFrame = CreateFrame("Frame", nil, cluster)
    -- Forever's own template (Blizzard_Minimap/Camelot): 32 x 24 with art as big, hidden.
    local mailFrame = CreateFrame("Frame", nil, cluster.IndicatorFrame)
    mailFrame:SetSize(32, 24)
    mailFrame.MailIcon = mailFrame:CreateTexture()
    mailFrame:Hide()
    cluster.IndicatorFrame.MailFrame = mailFrame
    cluster.Tracking = CreateFrame("Frame", nil, cluster)
    CreateFrame("Button", "GameTimeFrame", cluster)
    local mm = CreateFrame("Frame", "Minimap", cluster)
    mm.ZoomIn = CreateFrame("Button", nil, mm)
    function mm:SetMaskTexture(t) self.__mask = t end
    mm.__blob = {}
    function mm:SetQuestBlobRingScalar(v) self.__blob.questScalar = v end
    function mm:SetQuestBlobRingAlpha(v) self.__blob.questAlpha = v end
    function mm:SetTaskBlobRingScalar(v) self.__blob.taskScalar = v end
    -- Zoom as in the client: 6 levels, MINIMAP_UPDATE_ZOOM fired after the call.
    -- The picture as seen in game: after a loading screen in a city, indoors or
    -- in a dungeon the map can come up empty (__picture = "empty", set by a
    -- test). Each frame in which the zoom changes moves it one step on: empty,
    -- then drawing, then filled. A zoom while the map can't be seen (the panel
    -- at 0 before the login fade-in) moves nothing, nor one while it's even
    -- slightly see-through: seen in game, at 90% the map stopped updating.
    mm.__zoom, mm.__zoomCalls = 2, 0
    function mm:GetZoom() return self.__zoom end
    function mm:GetZoomLevels() return 6 end
    function mm:SetZoom(z)
        self.__zoomCalls = self.__zoomCalls + 1
        if z == self.__zoom then return end
        self.__zoom = z
        local now = GetTime()
        if self.__picture and self.__picture ~= "filled" and self.__steppedAt ~= now
            and self:IsVisible() and self:GetEffectiveAlpha() > 0.999 then
            self.__steppedAt = now
            self.__picture = self.__picture == "empty" and "drawing" or "filled"
        end
        C_Timer.After(0, function() stub.FireEvent("MINIMAP_UPDATE_ZOOM") end)
    end
    CreateFrame("Frame", "MainStatusTrackingBarContainer", UIParent)
    -- The game's right-side column and the armor figure it lays out.
    local right = CreateFrame("Frame", "RightManagedFrameContainer", UIParent)
    CreateFrame("Frame", "DurabilityFrame", right)
    _G.UnitXP = function() return 300 end
    _G.UnitXPMax = function() return 1200 end
    _G.GetXPExhaustion = function() return 400 end
    _G.IsPlayerAtEffectiveMaxLevel = function() return false end
end

-- Runs the meter's open/fold slide to its end.
function PW.settle()
    stub.RunOnUpdate(stub.infopanel.Panel.slide.driver, 1)
end

-- The meter shown (it's folded away by default), with the minimap and the meter's
-- rows at the earlier sizes these tests were measured with.
function PW.login(more)
    local DUI = stub.Load({ infopanel = true, before = function()
        PW.world()
        if more then more() end
    end })
    DaylightUI:Set("InfoPanel", "meter.enabled", true)
    DaylightUI:Set("InfoPanel", "map.size", 208)
    DaylightUI:Set("InfoPanel", "meter.rowHeight", 18)
    stub.RunTimers()
    PW.settle()
    return DUI
end

-- A meter's bars (its area also holds other pieces). The first meter's area is
-- stub.infopanel.Panel.meterArea.
function PW.bars(area)
    local out = {}
    for _, c in ipairs(stub.Children(area)) do
        if c.amount then out[#out + 1] = c end
    end
    return out
end

-- The drop-down's rows, while it's open.
function PW.menuRows()
    local W, out = DaylightUI.Widgets, {}
    for n = 1, 20 do
        local r = W.MenuRow(n)
        if r and r:IsShown() then out[#out + 1] = r end
    end
    return out
end

return PW
