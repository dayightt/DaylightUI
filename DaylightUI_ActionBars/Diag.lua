-- /dui bars: what the action bars are doing, for checking in game. Bar 1's
-- page against the one the game's own controller would pick (MATCH or
-- MISMATCH), each bar's state, and the conditions the paging reads.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Diag = {}
ns.Diag = Diag

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if ok then return v end
end

-- The page the game's own controller gives bar 1, in its order: a vehicle,
-- an override bar, a temporary shapeshift, then forms (only on page 1), then
-- the page picked by hand.
function Diag.GamePage()
    local AB = type(C_ActionBar) == "table" and C_ActionBar or {}
    if call(AB.HasVehicleActionBar) or call(HasVehicleActionBar) then return call(GetVehicleBarIndex) or 31 end
    if call(AB.HasOverrideActionBar) or call(HasOverrideActionBar) then return call(GetOverrideBarIndex) or 33 end
    if call(AB.HasTempShapeshiftActionBar) or call(HasTempShapeshiftActionBar) then
        return call(GetTempShapeshiftBarIndex) or 32
    end
    local page = call(AB.GetActionBarPage) or call(GetActionBarPage) or 1
    local offset = call(GetBonusBarOffset) or 0
    if page == 1 and offset > 0 then return call(GetBonusBarIndex) or (6 + offset) end
    return page
end

function Diag.Lines()
    local B = ns.Bars
    local out = {}
    local ours = tonumber(B.holders.main:GetAttribute("actionpage")) or 1
    local game = type(MainActionBar) == "table" and MainActionBar:GetAttribute("actionpage")
    local twin = type(ActionButton1) == "table" and ActionButton1.action
    local want = Diag.GamePage()
    out[#out + 1] = string.format("Bar 1: page %d (the game's bar 1: %s, ActionButton1: %s, ours: %s); the game would pick %s: %s",
        ours, tostring(game), tostring(twin), tostring(B.buttons.main[1]:GetAttribute("action")), tostring(want),
        ours == want and "MATCH" or "MISMATCH")
    for _, def in ipairs(B.DEFS) do
        local list = B.buttons[def.key] or {}
        local n = B.KINDS[def.kind].Count(def, B.Config(def))
        local first = list[1]
        local key = def.command and GetBindingKey(def.command .. 1)
        out[#out + 1] = string.format("%s: %s, %d buttons, button 1 slot %s, key %s", def.label,
            B.holders[def.key]:IsShown() and "shown" or "hidden", n,
            tostring(first and first.GetAttribute and first:GetAttribute("action")), tostring(key or "-"))
    end
    out[#out + 1] = "Bonus bar offset: " .. tostring(call(GetBonusBarOffset))
    local conds = {}
    for _, c in ipairs({ "possessbar", "vehicleui", "overridebar", "shapeshift" }) do
        conds[#conds + 1] = c .. "=" .. tostring(SecureCmdOptionParse("[" .. c .. "] yes; no"))
    end
    out[#out + 1] = "Conditions: " .. table.concat(conds, ", ")
    return out
end

DUI.RegisterCommand("bars", function()
    for _, line in ipairs(Diag.Lines()) do DUI.Print(line) end
end, L["/dui bars - what the action bars are doing (pages, slots, keys)"])
