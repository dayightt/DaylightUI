-- The small bars: stance (and paladin auras), pet and possess. They keep the game's
-- own buttons, moved into our holders, so their keybinds and updates stay the
-- game's. We only place, size and show them.

local _, ns = ...

local Small = {}
ns.Small = Small

local base = {}          -- bar key -> one button's own width, measured before any scaling

-- Moves the game's buttons prefix1..n into our holder (at file load, out of combat).
-- They were anchored to the game's own container.
local function adopt(def, holder, prefix, n)
    local list = {}
    for i = 1, n do
        local b = _G[prefix .. i]
        if type(b) == "table" then
            b:SetParent(holder)
            b:ClearAllPoints()
            list[#list + 1] = b
        end
    end
    local w = list[1] and list[1]:GetWidth()
    base[def.key] = (type(w) == "number" and w > 0) and w or ns.Shape.SMALL_BUTTON
    return list
end

local function baseOf(def) return base[def.key] or ns.Shape.SMALL_BUTTON end

local function forms()
    local n = type(GetNumShapeshiftForms) == "function" and GetNumShapeshiftForms() or 0
    return tonumber(n) or 0
end

-- Hidden wherever the game hides bars 2-8 (pet battle, vehicle, override bar).
local AWAY = "[petbattle][vehicleui][overridebar] hide; "

Small.KINDS = {
    -- Stance or aura: one button per form, up to the Buttons setting.
    stance = {
        Setup = function(def, holder)
            ns.Park.Bar(_G.StanceBar)     -- its events still update the buttons, untainted
            return adopt(def, holder, "StanceButton", 10)
        end,
        Count = function(_, cfg) return math.max(0, math.min(tonumber(cfg.icons) or 10, forms())) end,
        Base = baseOf,
        Rule = function()
            if forms() == 0 then return AWAY .. "hide; " end
            return AWAY
        end,
        Events = { "UPDATE_SHAPESHIFT_FORMS" },
        InUse = function() return forms() > 0 end,   -- no forms means no unlock handle
        Caps = { icons = { 1, 10 }, rows = true, show = "stance" },
    },
    pet = {
        Setup = function(def, holder)
            -- Not parked, because its OnUpdate colors the buttons out of range. It's
            -- unseen and unclickable; its own show and hide stay the game's.
            local bar = _G.PetActionBar
            if type(bar) == "table" then
                bar:SetAlpha(0)
                bar:EnableMouse(false)
            end
            return adopt(def, holder, "PetActionButton", 10)
        end,
        Count = function(_, cfg) return math.max(1, math.min(tonumber(cfg.icons) or 10, 10)) end,
        Base = baseOf,
        Rule = function() return AWAY .. "[nopet] hide; " end,
        Caps = { icons = { 1, 10 }, rows = true, show = "pet" },
    },
    -- Something possessed: its two buttons (the second is "cancel").
    possess = {
        Setup = function(def, holder)
            ns.Park.Bar(_G.PossessActionBar)
            return adopt(def, holder, "PossessButton", 2)
        end,
        Count = function() return 2 end,
        Base = baseOf,
        Rule = function() return "[nopossessbar] hide; " end,
        Caps = { show = "possess" },
    },
}
