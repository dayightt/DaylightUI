-- The cooldown layout's first-time tour: four short stops over the editor
-- (add a spell, make a group, change a spell, the top bar), each lighting the
-- part it talks about, on the same card, dim and keys as the main tour
-- (Tour.lua). The mouse reaches the editor the whole time, so the player tries
-- each thing while reading, and a stop moves on by itself once it's done, the
-- way the bags' stop waits for the bags. It opens by itself the first time
-- the editor opens on an account with no layout yet; /cdm tour shows it again.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Guide = {}
ns.CdmGuide = Guide

Guide.KEY = "cdm"
Guide.DELAY = 0.3 -- lets the editor fade in before the card joins it

local function Ed() return ns.CdmEditor end
local function pop(text) return DUI.Tour.Pop(text) end

-- How many spells are placed, and how many of them hang off another.
local function tally()
    local n, hooked = 0, 0
    for _, p in pairs(Ed().Set().pieces) do
        n = n + 1
        if p.parent ~= nil then hooked = hooked + 1 end
    end
    return n, hooked
end

-- The picked spell on screen, else the first placed one.
local function somePiece()
    local id = Ed().Selected()
    if id ~= nil and Ed().PreviewOf(id) then return Ed().PreviewOf(id) end
    local first
    for key in pairs(Ed().Set().pieces) do
        if first == nil or tostring(key) < tostring(first) then first = key end
    end
    return first ~= nil and Ed().PreviewOf(first) or nil
end

-- A piece being dragged moves every frame: the light waits for the drop.
local function still() return not Ed().Dragging() end

local start = {}

Guide.STEPS = {
    { id = "add",
      title = L["Add a spell"],
      text = function()
          return string.format(L["The tray lists every spell your class can track. %s one to add it, or drag it up to where you want it, then pick %s or %s."],
              pop(L["Click"]), pop(L["Icon"]), pop(L["Bar"]))
      end,
      enter = function() start.pieces = tally() end,
      part = function()
          local ch = Ed().Chooser()
          if ch and ch:IsShown() then return ch end
          return Ed().Tray()
      end,
      follow = still,
      done = function() return (tally()) > (start.pieces or 0) end },
    { id = "group",
      title = L["Make a group"],
      text = function()
          return string.format(L["Click a spell on screen, press a %s on one of its sides and pick another spell: it hooks on there. A group moves as one and shares its look, so drag any of its spells to move them all."],
              pop("+"))
      end,
      enter = function() start.hooked = select(2, tally()) end,
      part = function()
          if Ed().Attach() then return Ed().Tray() end
          local E = Ed()
          return somePiece(), E.Plus("up"), E.Plus("down"), E.Plus("left"), E.Plus("right")
      end,
      avoid = function() return ns.CdmCard.Frame() end,
      follow = still,
      done = function() return select(2, tally()) > (start.hooked or 0) end },
    { id = "card",
      title = L["Change how it works"],
      text = function()
          return string.format(L["Click a spell to open its card. %s: size, border and text. %s: what it does when it's ready, on cooldown, or when its buff is up or missing, like a glow, a fade or a sound. %s: where the group sits and which way it grows."],
              pop(L["Look"]), pop(L["Behavior"]), pop(L["Group"]))
      end,
      part = function()
          local c = ns.CdmCard.Frame()
          if c and c:IsShown() then return c end
          return somePiece()
      end,
      avoid = somePiece,
      follow = still },
    { id = "top",
      title = L["Your layouts"],
      text = function()
          return string.format(L["Each talent set has its own layout: click it up here to switch. %s brings in a layout from the game's Cooldown Manager. Everything saves as you go, and %s shows this tour again."],
              pop(L["Import"]), pop("/cdm tour"))
      end,
      part = function() return Ed().Pill() end },
}

-- Opens the editor if it isn't open, then the tour once it's faded in.
function Guide.Start()
    if DUI.Tour.Running() then return false end
    DUI.DB.Root().cdmGuideSeen = true
    if not (Ed().IsOpen() or Ed().Open()) then return false end
    local token = {}
    Guide.waiting = token
    C_Timer.After(Guide.DELAY, function()
        if Guide.waiting ~= token or not Ed().IsOpen() then return end
        Guide.waiting = nil
        DUI.Tour.Run(Guide.STEPS, {
            key = Guide.KEY,
            through = true,
            skipped = string.format(L["Tour skipped. %s shows it again."], pop("/cdm tour")),
        })
    end)
    return true
end

-- The editor just opened: the first time on this account, the tour comes
-- with it. A player who already has a layout knows the way round.
function Guide.Offer()
    local root = DUI.DB.Root()
    if root.cdmGuideSeen or DUI.Tour.Running() then return end
    if ns.CdmData.AnyPlaced() then
        root.cdmGuideSeen = true
        return
    end
    Guide.Start()
end

function Guide.Running() return DUI.Tour.Running(Guide.KEY) end

-- The editor closed, so the tour goes with it.
function Guide.Stop()
    Guide.waiting = nil
    if Guide.Running() then DUI.Tour.Stop() end
end
