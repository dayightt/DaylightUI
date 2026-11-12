-- Boss debuffs on you that addons can't read (private auras): up to three, drawn
-- by the client into our slots (DUI.PrivateAuras) in a row just under the debuff
-- bar's first row, at its icon size and growing the same way. The game's own
-- debuff frame carries these anchors; when it's hidden (hideBlizzardFrames) ours
-- take over. Always at full opacity and never part of the debuff fade, since a
-- boss mechanic must never be faded out.

local _, BL = ...
local DUI = DaylightUI

local Private = {}
BL.Private = Private

Private.COUNT = 3

local function textRoom(size) return math.ceil(BL.Widgets.TimeSize(size) / 2) + 1 end

function Private.Build()
    if Private.set or not DUI.PrivateAuras.Available() then return end
    local bar = BL.DebuffBar
    if not (bar and bar.holder) then return end
    local f = CreateFrame("Frame", "DaylightUIDebuffsPrivate", UIParent)
    f:SetFrameStrata("LOW")
    f:SetSize(1, 1)
    f:EnableMouse(false)
    Private.frame = f
    Private.set = DUI.PrivateAuras.New(f, Private.COUNT, { numbers = true })
    Private.Apply()
end

-- Whether ours are needed: the switch is on and the game's frame is hidden
-- (otherwise its own anchors show them).
function Private.Wanted()
    local d = BL.DB and BL.DB.settings
    if type(d) ~= "table" then return false end
    return d.hideBlizzardFrames ~= false and d.debuff.privateAuras ~= false
end

-- Placed where a second row of debuffs would start, at the bar's scale.
function Private.Apply()
    local set, bar = Private.set, BL.DebuffBar
    if not (set and bar and bar.holder) then return end
    local size = bar:Size()
    local spacing = bar:Setting("spacing") or 0
    local f = Private.frame
    f:SetScale(bar:Scale())
    local corner = bar:Corner()
    local left = corner == "TOPRIGHT"
    f:ClearAllPoints()
    f:SetPoint(corner, bar.holder, corner, 0, -(BL.Widgets.Height(size) + spacing + textRoom(size)))
    for i, slot in ipairs(set.slots) do
        slot:ClearAllPoints()
        if i == 1 then
            slot:SetPoint(corner, f, corner, 0, 0)
        elseif left then
            slot:SetPoint("RIGHT", set.slots[i - 1], "LEFT", -spacing, 0)
        else
            slot:SetPoint("LEFT", set.slots[i - 1], "RIGHT", spacing, 0)
        end
    end
    DUI.PrivateAuras.Want(set, Private.Wanted() and "player" or nil, BL.Widgets.Height(size))
end

-- The preview (the Preview button, /dui test) shows where one would land.
BL.On("AURAS_CHANGED", function()
    if Private.set then DUI.PrivateAuras.ShowSample(Private.set, BL.Preview.Active() and 1 or 0) end
end)
BL.On("SETTINGS_CHANGED", function(key, scope)
    if scope == "debuff" or key == "hideBlizzardFrames" then Private.Apply() end
end)
