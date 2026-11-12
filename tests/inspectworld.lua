-- The fake game's inspect for the inspect tests: Blizzard_InspectUI as Forever
-- runs it (Blizzard_InspectUI/Camelot/Blizzard_InspectUI.lua). It loads on demand
-- (made the first time, ADDON_LOADED inside the load). InspectFrame_Show(unit)
-- calls NotifyInspect and sets frame.unit, INSPECT_READY(guid) shows it
-- (ShowUIPanel), a target change hides it, and its OnHide calls ClearInspectPlayer.
-- Built on the character world (CW) and the book world (BW: the talent tree, with
-- the inspected one under config -1, INSPECT_TRAIT_CONFIG_ID).
--
-- IW.world(spec) is stub.Load's "before". A test then plays
-- IW.Inspect("target"), IW.Hide(), and reads IW.Calls(kind).
local stub = require("stub")
local CW = require("charworld")
local BW = require("bookworld")

local IW = {}
IW.CONFIG = -1

local function S() return IW.state end
local function record(kind, ...) table.insert(S().calls, { kind = kind, args = { ... } }) end
function IW.Calls(kind)
    local out = {}
    for _, c in ipairs(S().calls) do if c.kind == kind then out[#out + 1] = c.args end end
    return out
end

-- The game's own code runs untainted (stub.inSecure).
local function asGame(fn, ...)
    stub.inSecure = (stub.inSecure or 0) + 1
    local ok, err = pcall(fn, ...)
    stub.inSecure = stub.inSecure - 1
    if not ok then error(err, 2) end
end

local function inspectFrame()
    if _G.InspectFrame then return _G.InspectFrame end
    local f = CreateFrame("Frame", "InspectFrame", UIParent)
    f:Hide()
    f:SetScript("OnHide", function(self) self.unit = nil; ClearInspectPlayer() end)
    f:RegisterEvent("INSPECT_READY")
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    f:SetScript("OnEvent", function(self, event, guid)
        if event == "INSPECT_READY" and self.unit and UnitGUID(self.unit) == guid then
            asGame(ShowUIPanel, self)
        elseif event == "PLAYER_TARGET_CHANGED" and self.unit == "target" then
            asGame(HideUIPanel, self)
        end
    end)
    record("LoadAddOn", "Blizzard_InspectUI")
    stub.FireEvent("ADDON_LOADED", "Blizzard_InspectUI")
    return f
end

function IW.Load() return inspectFrame() end

-- InspectUnit(unit) as the game does it: load, ask, and the server answers
-- (INSPECT_READY) the next frame. spec.late means no gear links until the test
-- calls IW.Arrive, since the fake's timers keep no time and a test decides when.
function IW.Inspect(unit)
    unit = unit or "target"
    asGame(function()
        local f = inspectFrame()
        HideUIPanel(f)
        NotifyInspect(unit)
        f.unit = unit
    end)
    C_Timer.After(0, function()
        S().ready[unit] = not S().late
        stub.FireEvent("INSPECT_READY", UnitGUID(unit))
    end)
end

-- spec.late: their links land now, with the game's UNIT_INVENTORY_CHANGED for them
-- (quiet means no event, since in game the links may come without one).
function IW.Arrive(unit, quiet)
    unit = unit or "target"
    S().ready[unit] = true
    if not quiet then stub.FireEvent("UNIT_INVENTORY_CHANGED", unit) end
end

function IW.Hide() asGame(function() HideUIPanel(inspectFrame()) end) end

local function install()
    _G.ShowUIPanel = function(f) record("ShowUIPanel", f:GetName()); f:Show() end
    _G.HideUIPanel = function(f) record("HideUIPanel", f:GetName()); f:Hide() end
    _G.NotifyInspect = function(unit) record("NotifyInspect", unit) end
    _G.CanInspect = function(unit) return UnitIsPlayer(unit) end
    _G.ClearInspectPlayer = function() record("ClearInspectPlayer") end
    _G.InspectUnit = IW.Inspect
    _G.Constants = _G.Constants or {}
    Constants.TraitConsts = Constants.TraitConsts or {}
    Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID = IW.CONFIG
    _G.C_PaperDollInfo = _G.C_PaperDollInfo or {}
    C_PaperDollInfo.GetInspectItemLevel = function(unit) return S().itemLevel[unit] or 0 end
    -- Someone else's slots come from IW.state.gear[unit]. Yours stay CW's.
    for _, name in ipairs({ "GetInventoryItemLink", "GetInventoryItemQuality", "GetInventoryItemTexture",
        "GetInventoryItemID", "GetInventoryItemCount" }) do
        local mine = _G[name]
        _G[name] = function(unit, id)
            if unit == "player" or unit == nil then return mine(unit, id) end
            local x = S().ready[unit] and S().gear[unit] and S().gear[unit][id]
            if not x then return nil end
            if name == "GetInventoryItemLink" then
                return "|cffa335ee|Hitem:" .. CW.ItemId(x) .. ":" .. (x.enchantId or 0) .. "|h[" .. x.name .. "]|h|r"
            end
            if name == "GetInventoryItemQuality" then return x.quality end
            if name == "GetInventoryItemTexture" then return "icon:" .. x.name end
            if name == "GetInventoryItemID" then return CW.ItemId(x) end
            return 1
        end
    end
    -- Their tooltip data (the enchant line) and their items' levels, by unit.
    local function theirs(unit, id)
        return S().ready[unit] and S().gear[unit] and S().gear[unit][id]
    end
    local tip = C_TooltipInfo.GetInventoryItem
    C_TooltipInfo.GetInventoryItem = function(unit, id)
        if unit == "player" or unit == nil then return tip(unit, id) end
        local x = theirs(unit, id)
        if not x then return nil end
        local lines = { { type = 0, leftText = x.name } }
        if x.enchant then lines[2] = { type = 15, leftText = string.format(ENCHANTED_TOOLTIP_LINE, x.enchant) } end
        return { lines = lines }
    end
    local level = C_Item.GetDetailedItemLevelInfo
    C_Item.GetDetailedItemLevelInfo = function(link)
        for _, list in pairs(S().gear) do
            for _, x in pairs(list) do
                if type(link) == "string" and string.find(link, "[" .. x.name .. "]", 1, true) then return x.level end
            end
        end
        return level(link)
    end
end

-- spec: gear = { [unit] = { [slotId] = CW.item(...) } }, itemLevel = { [unit] = n },
-- tree = BW.NewTree spec for the inspected tree (default: the Warrior's),
-- late = no links until IW.Arrive, units = stub.SetUnits table (default: you and a
-- target Warrior), enabled = the module's switch (default true), char = CW.world's
-- spec, book = BW.world's spec.
function IW.world(spec)
    spec = spec or {}
    return function()
        BW.world(spec.book or {})()
        CW.world(spec.char or {})()
        IW.state = { calls = {}, gear = spec.gear or {}, itemLevel = spec.itemLevel or {}, ready = {}, late = spec.late }
        _G.InspectFrame = nil
        install()
        BW.trees[IW.CONFIG] = BW.NewTree(spec.tree or {})
        stub.SetUnits(spec.units or {
            player = { name = "Me", class = "MAGE", level = 60, isPlayer = true, guid = "Player-1" },
            target = { name = "Garrick", lastName = "Stone", class = "WARRIOR", level = 60, isPlayer = true, guid = "Player-2" },
        })
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { Inspect = { enabled = spec.enabled ~= false } } } } }
    end
end

return IW
