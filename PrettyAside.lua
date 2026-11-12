-- When PrettyTooltip is on it replaces the Tooltip module entirely: the module
-- builds nothing, its options page goes away, and Skins dresses PrettyTooltip's
-- panels. This file answers when it draws and for which tooltip data. It lives
-- in core because both of those callers need it while the other may be off.
-- PrettyTooltip's namespace is private, so only its saved PrettyTooltipDB can
-- be read, the same way its own ns.option does.

local _, DUI = ...

local PA = {}
DUI.PrettyAside = PA

PA.ADDON = "PrettyTooltip"

-- Tooltip data kinds it draws, mapped to the setting that turns each on (from
-- its Core/Settings.lua TOOLTIP_TYPES, v1.3.8). Mail, flight paths and imbues
-- are detected from the lines alone, with no data kind.
PA.KINDS = { Item = "itemPanels", Spell = "spellPanels", Unit = "unitPanels", Corpse = "unitPanels",
    UnitAura = "auraPanels", Object = "objectPanels", Quest = "questPanels", QuestPartyProgress = "questPanels",
    Macro = "macroPanels", PetAction = "petPanels", MinimapMouseover = "minimapPanels" }

local function isTable(x) return type(x) == "table" end
local function plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

function PA.Loaded()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
    return type(loaded) == "function" and loaded(PA.ADDON) == true
end

-- Does it draw panels at all, or panels of this kind (a PA.KINDS setting)?
-- Its settings are only saved once changed, so unset means on.
function PA.Draws(option)
    if not PA.Loaded() then return false end
    local db = _G.PrettyTooltipDB
    if not isTable(db) then return true end
    if db.layout == "blizzard" then return false end
    return option == nil or db[option] ~= false
end

-- Does it draw this tooltip data?
local byKind
function PA.Covers(data)
    if not PA.Loaded() or not isTable(data) then return false end
    if not byKind then
        local kinds = Enum and Enum.TooltipDataType
        if not isTable(kinds) then return false end
        byKind = {}
        for name, option in pairs(PA.KINDS) do
            if kinds[name] ~= nil then byKind[kinds[name]] = option end
        end
    end
    local kind = plain(data.type)
    local option = kind ~= nil and byKind[kind] or nil
    return option ~= nil and PA.Draws(option)
end
