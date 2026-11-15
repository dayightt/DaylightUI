-- Which profession window opens, Daylight UI's or the game's own (Win.Swap): the
-- header's swap icon, a link on the game's window, the options switch.

local _, DUI = ...
DUI.Craft = DUI.Craft or {}
local ns = DUI.Craft

local Swap = {}
ns.Swap = Swap

local function apply(ours)
    DUI.craftOwnWindow = ours
    local W = ns.Window
    if ours and W and not W.frame then W.Build(ns.module) end
    if ns.Key and ns.Key.ready then ns.Key.Apply() end
    if W and W.follow then
        if ours then W.TakeBack() else W.GiveAway() end
    end
end

function Swap.Ours() return Swap.it ~= nil and Swap.it.Ours() end
function Swap.Use(ours) if Swap.it then Swap.it.Use(ours) end end
function Swap.Apply() if Swap.it then Swap.it.Apply() end end
function Swap.Paint() if Swap.it then Swap.it.Paint() end end

function Swap.Init()
    Swap.it = DUI.Win.Swap({
        scope = "Professions",
        game = function() return ns.Window and ns.Window.Game() end,
        addon = "Blizzard_Professions",
        blocked = function() return DUI.craftMogul == true end,
        lent = function() return ns.Window ~= nil and ns.Window.handed == true end,
        take = function() if ns.Window and ns.Window.follow then ns.Window.TakeBack() end end,
        apply = apply,
    })
end
