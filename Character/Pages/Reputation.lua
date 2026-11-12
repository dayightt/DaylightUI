-- The Reputation page: factions under their group
-- names, each with its standing (in its pair's light end) and a thin bar
-- in that standing's gradient pair; the picked faction's pane, with the
-- game's three switches. Folding a group is the game's own fold.

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char
local L = DUI.L

local Reputation = {}
ns.Reputation = Reputation

Reputation.GREY = DUI.Style.INK.LABEL   -- a standing with no color of its own
Reputation.LAST = 8                         -- Exalted

function Reputation.StandingName(reaction)
    if type(GetText) == "function" then
        local ok, s = pcall(GetText, "FACTION_STANDING_LABEL" .. tostring(reaction), UnitSex and UnitSex("player") or 2)
        if ok and type(s) == "string" then return s end
    end
    return _G["FACTION_STANDING_LABEL" .. tostring(reaction)] or ""
end

local function plainColor(reaction)
    local c = type(FACTION_BAR_COLORS) == "table" and FACTION_BAR_COLORS[reaction]
    if c then return { c.r, c.g, c.b } end
    return Reputation.GREY
end

function Reputation.Read()
    local C, out = C_Reputation, {}
    if type(C) ~= "table" or type(C.GetNumFactions) ~= "function" then return out end
    for i = 1, C.GetNumFactions() do
        local d = C.GetFactionDataByIndex(i)
        if d then
            out[#out + 1] = { index = i, id = d.factionID, name = d.name or "", header = d.isHeader == true,
                child = d.isChild == true, collapsed = d.isCollapsed == true, reaction = d.reaction or 4,
                min = d.currentReactionThreshold or 0, max = d.nextReactionThreshold or 0, value = d.currentStanding or 0,
                atWar = d.atWarWith == true, canWar = d.canToggleAtWar == true, canInactive = d.canSetInactive == true,
                watched = d.isWatched == true, desc = d.description }
        end
    end
    return out
end

function Reputation.Bar(f)
    local key = "REP_" .. f.reaction
    local span = f.max - f.min
    if span <= 0 then return { value = 1, max = 1, key = key, rgb = plainColor(f.reaction) } end
    return { value = f.value - f.min, max = span, key = key, rgb = plainColor(f.reaction) }
end

function Reputation.Items(factions)
    local items = {}
    for _, f in ipairs(factions) do
        if f.header then
            items[#items + 1] = { kind = "head", key = "h" .. f.index, text = f.name, folded = f.collapsed,
                                  indent = f.child and 1 or 0, data = f }
        else
            items[#items + 1] = { kind = "row", key = "f" .. tostring(f.id or f.index), text = f.name,
                right = Reputation.StandingName(f.reaction),
                rightColor = ns.List.Light("REP_" .. f.reaction) or plainColor(f.reaction),
                bar = Reputation.Bar(f), indent = f.child and 1 or 0, data = f }
        end
    end
    return items
end

function Reputation.Progress(f)
    if f.reaction >= Reputation.LAST or f.max <= f.value then return nil end
    return string.format(L["%s more to %s"], ns.List.Number(f.max - f.value), Reputation.StandingName(f.reaction + 1))
end

local function picked(page)
    for _, item in ipairs(page.list.items) do
        if item.kind == "row" and item.key == page.list.selectedKey then return item.data end
    end
end

function Reputation.ShowPane(page)
    local P, f = page.pane, picked(page)
    P:SetShown(f ~= nil)
    if not f then return end
    P.title:SetText(f.name)
    P.sub:SetText(Reputation.StandingName(f.reaction))
    local c = ns.List.Light("REP_" .. f.reaction) or plainColor(f.reaction)
    P.sub:SetTextColor(c[1], c[2], c[3])
    local b = Reputation.Bar(f)
    P.bar:SetMinMaxValues(0, b.max)
    -- The same faction gaining: the fill glides; another one picked: at once.
    DUI.Style.SetBarValue(P.bar, b.value, P.faction ~= f)
    ns.List.PaintBar(P.bar, b.key, b.rgb)
    P.barText:SetText(Reputation.Progress(f) or "")
    P.body:SetText(f.desc or "")
    local C = C_Reputation
    local active = type(C.IsFactionActive) ~= "function" or C.IsFactionActive(f.index)
    ns.List.SetToggle(P.toggles[1], f.watched, true, f.id or f.index)
    ns.List.SetToggle(P.toggles[2], f.atWar, f.canWar, f.id or f.index)
    ns.List.SetToggle(P.toggles[3], not active, f.canInactive, f.id or f.index)
    P.faction = f
end

function Reputation.Build(page)
    page.list = ns.List.Make(page, {
        row = ns.List.BAR_ROW,
        onPick = function() Reputation.ShowPane(page) end,
        onFold = function(item)
            local C = C_Reputation
            if item.data.collapsed then C.ExpandFactionHeader(item.data.index) else C.CollapseFactionHeader(item.data.index) end
            ns.Window.Refresh()
        end,
    })
    page.pane = ns.List.Pane(page)
    local P = page.pane
    ns.List.AddToggle(P, L["Inactive"], function()
        local f = P.faction
        if f then C_Reputation.SetFactionActive(f.index, not C_Reputation.IsFactionActive(f.index)) end
        ns.Window.Refresh()
    end)
    ns.List.AddToggle(P, L["At war"], function()
        if P.faction then C_Reputation.ToggleFactionAtWar(P.faction.index) end
        ns.Window.Refresh()
    end)
    ns.List.AddToggle(P, L["Show on the experience bar"], function(t)
        if P.faction then C_Reputation.SetWatchedFactionByIndex(t.on and 0 or P.faction.index) end
        ns.Window.Refresh()
    end)
    -- Built bottom up; read top down: watch, at war, inactive.
    P.toggles = { P.toggles[3], P.toggles[2], P.toggles[1] }
end

function Reputation.Place(page)
    local E, W = ns.List.EDGE, ns.Window.Width()
    local paneW = ns.List.PANE_W
    ns.List.Place(page.list, E, W - 3 * E - paneW)
    ns.List.PlacePane(page.pane, W - E - paneW, paneW)
end

function Reputation.Refresh(page)
    local items = Reputation.Items(Reputation.Read())
    local L = page.list
    local found = false
    for _, item in ipairs(items) do if item.key == L.selectedKey then found = true end end
    if not found then
        L.selectedKey = nil
        for _, item in ipairs(items) do
            if item.kind == "row" then L.selectedKey = item.key; break end
        end
    end
    ns.List.Set(L, items)
    Reputation.ShowPane(page)
end

Reputation.events = { "UPDATE_FACTION" }
Reputation.Available = function() return type(C_Reputation) == "table" and type(C_Reputation.GetNumFactions) == "function" end

ns.Window.Register("reputation", Reputation)
