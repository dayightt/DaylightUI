-- Skins Questie's windows. Swapping its objective icons for our art (while this
-- switch is on) and hiding its tracker in favor of ours is done in the core's
-- QuestieAside.lua, which also restores them when Skins is off. Questie keeps
-- its tooltips, windows and minimap button (in the info panel's drawer).
-- Its windows are AceGUI (Questie_Camelot.toc on Forever): the options
-- (QuestieConfigFrame, created on load), My Journey (QuestieJourneyFrame, at
-- login) and their popups, all dressed by Packs/Addons/Ace3.lua. What's left
-- here is the plain game buttons it adds on top (the options' "My Journey").

local _, ns = ...
local DUI = DaylightUI
local Engine = ns.Engine

Engine.AddonSwitch({ key = "questie", addon = "Questie", label = "Questie",
    desc = "Its options and My Journey windows, and its quest objective icons on the maps, each quest in its own color." })

local function isTable(x) return type(x) == "table" end

-- The plain buttons Questie adds to one of its AceGUI windows.
local function buttons(Kit, widget)
    local f = isTable(widget) and widget.frame
    if not isTable(f) or not f.GetChildren then return end
    for _, c in ipairs({ f:GetChildren() }) do
        if c.GetObjectType and c:GetObjectType() == "Button" and isTable(c.Left) and isTable(c.Right) then
            Kit.Button(c)
        end
    end
end

Engine.Register({ key = "questie", pack = "addons", addon = "Questie", switch = "questie", label = "Questie",
    thirdParty = true, apply = function(Kit, def)
        local config = _G.QuestieConfigFrame
        if not isTable(config) or not isTable(config.frame) then return false end
        buttons(Kit, config)
        local journey = _G.QuestieJourneyFrame
        local function again() buttons(Kit, _G.QuestieConfigFrame); buttons(Kit, _G.QuestieJourneyFrame) end
        config.frame:HookScript("OnShow", Engine.Safe(def, again))
        if isTable(journey) and isTable(journey.frame) then
            buttons(Kit, journey)
            journey.frame:HookScript("OnShow", Engine.Safe(def, again))
        end
    end })
