local stub = require("stub")

-- The fake world around the panel (slide, login, meter) lives in
-- tests/panelworld.lua, shared with tests/test_meters.lua.
local PW = require("panelworld")
local world, settle, login, menuRows = PW.world, PW.settle, PW.login, PW.menuRows
-- The first meter's bars.
local function bars() return PW.bars(stub.infopanel.Panel.meterArea) end

T.test("info panel: top right, movable, XP frame above the framed panel", function()
    local DUI = login()
    local P = stub.infopanel.Panel
    T.truthy(DUI.Movers.Get("infopanel"), "unlock handle")
    local p = P.holder:GetPoint(1)
    T.eq(p, "TOPRIGHT")
    T.truthy(DUI.Style.GetShell(P.panel), "the unit frames' border")
    local cfg = DUI:Get("InfoPanel", "map.size")
    T.truthy(P.holder:GetWidth() > cfg + DUI:Get("InfoPanel", "meter.width"), "meter and map side by side")
    DUI:Set("InfoPanel", "meter.enabled", false)
    settle()
    T.truthy(P.holder:GetWidth() < cfg + 60, "narrows to the map alone")
end)

-- Puts the panel where a drag would leave it, since the fake game has no
-- layout. x, y are its center's offset from the screen's center.
local function panelAt(x, y)
    stub.infopanel.Panel.holder.__center = { UIParent:GetWidth() / 2 + x, UIParent:GetHeight() / 2 + y }
end

T.test("info panel: moved, it's pinned by the map's outer corner, so the meter opening never moves the map", function()
    local DUI = login()
    local P = stub.infopanel.Panel
    -- Saved by its middle, as every move was before.
    DUI.DB.Positions().infopanel = { 300, 200 }
    panelAt(300, 200)
    DUI:Set("InfoPanel", "meter.enabled", false)
    settle()
    local saved = DUI.DB.Positions().infopanel
    T.eq(saved.at, "TOPRIGHT", "saved again by the map's outer corner")
    T.near(saved[1], 300, 1, "where it was: nothing moved")
    T.eq(P.holder:GetPoint(1), "TOPRIGHT", "pinned there")
    T.eq(DUI.Movers.Corner("infopanel"), "TOPRIGHT")
    local edge = saved.ax
    DUI:Set("InfoPanel", "meter.enabled", true)
    settle()
    T.eq(DUI.DB.Positions().infopanel.ax, edge, "the meter opened: the pinned edge stayed")
end)

T.test("info panel: the meter can come out of the map's right side, the threat meter with it", function()
    local DUI = login()
    local P, TM = stub.infopanel.Panel, stub.infopanel.ThreatMeter
    T.eq(P.side, "left", "at the screen's top-right corner: toward the middle")
    DUI:Set("InfoPanel", "map.meterSide", "right")
    settle()
    T.eq(P.side, "right")
    T.eq(DUI.Movers.Corner("infopanel"), "TOPLEFT", "pinned by the map's outer corner")
    T.eq(P.mapArea:GetPoint(1), "TOPLEFT", "the map on the left")
    T.eq(P.meterClip:GetPoint(1), "TOPRIGHT", "the meter on the right")
    T.eq(select(3, P.meterArea:GetPoint(1)), "TOPRIGHT", "riding the right edge as it slides")
    local a = { P.arrow:GetPoint(1) }
    T.eq(a[1], "LEFT"); T.eq(a[3], "RIGHT", "the fold tab on the right edge")
    DUI.SetTestMode(true)
    stub.RunOnUpdate(TM.slider.driver, 1)
    local c = { TM.clip:GetPoint(1) }
    T.eq(c[1], "TOPLEFT"); T.eq(c[2], P.panel); T.eq(c[3], "TOPRIGHT", "threat slides out of the right edge")
    T.eq(select(3, TM.tab:GetPoint(1)), "TOPRIGHT")
    T.near(_G.DaylightUIInfoPanelEdge:GetWidth(), 0, 0.01, "the buffs on the left stay put")
    DUI.SetTestMode(false)
    stub.RunOnUpdate(TM.slider.driver, 1)
    DUI:Set("InfoPanel", "map.meterSide", "auto")
    settle()
    T.eq(P.side, "left")
    T.eq(P.mapArea:GetPoint(1), "TOPRIGHT")
end)

T.test("info panel: on Automatic, moved past the screen's middle, the meter comes out of the other side", function()
    local DUI = login()
    local P = stub.infopanel.Panel
    panelAt(-500, 200)
    DUI.Movers.Save("infopanel", true)
    T.eq(P.side, "right", "on the left half: toward the middle")
    local saved = DUI.DB.Positions().infopanel
    T.eq(saved.at, "TOPLEFT", "pinned by the map's outer corner now")
    T.near(saved[1], -500, 1, "and it didn't move")
    T.eq(P.mapArea:GetPoint(1), "TOPLEFT")
    panelAt(500, 200)
    DUI.Movers.Save("infopanel", true)
    T.eq(P.side, "left", "back on the right half")
    T.eq(DUI.DB.Positions().infopanel.at, "TOPRIGHT")
    DUI.Movers.Reset("infopanel")
    T.eq(P.side, "left", "reset: the screen's corner")
end)

T.test("info panel: the minimap's box has its own background and border", function()
    local DUI = login()
    local P = stub.infopanel.Panel
    local box, xp = DUI.Style.GetShell(P.panel).opts, DUI.Style.GetShell(P.xp).opts
    T.eq(box.bgAlpha, xp.bgAlpha, "at first: the same as the others")
    DUI:Set("InfoPanel", "map.alphaOwn", true)
    DUI:Set("InfoPanel", "map.alpha", 0.3)
    DUI:Set("InfoPanel", "map.border", false)
    T.eq(box.bgAlpha, 0.3, "its own background")
    T.eq(box.noBorder, true, "its own border")
    T.eq(DUI.Style.GetShell(P.arrow).opts.noBorder, true, "its fold tab with it")
    T.truthy(xp.bgAlpha ~= 0.3, "the experience bar keeps the panel's")
    T.falsy(xp.noBorder)
    DUI:Set("InfoPanel", "panelBorder", false)
    DUI:Set("InfoPanel", "map.border", true)
    T.falsy(box.noBorder, "the panel's border switch leaves the map's box alone")
    T.eq(xp.noBorder, true)
end)

T.test("info panel: a profile whose panel looked different keeps that look on the map's box, once", function()
    login()
    local up = stub.infopanel.UpgradeMapBox
    local p = { modules = { InfoPanel = { panelBorder = false, panelAlphaOwn = true, panelAlpha = 0.4 } } }
    up(p)
    local map = p.modules.InfoPanel.map
    T.eq(map.border, false); T.eq(map.alphaOwn, true); T.eq(map.alpha, 0.4)
    T.eq(p.mapBox1, true)
    map.border = true
    up(p)
    T.eq(map.border, true, "only once")
    local plain = { modules = { InfoPanel = {} } }
    up(plain)
    T.isnil(plain.modules.InfoPanel.map, "nothing changed: nothing saved")
end)

T.test("info panel: the XP bar shows experience and rested, and hides the game's", function()
    login()
    local XP = stub.infopanel.XP
    T.eq(select(2, XP.bar:GetMinMaxValues()), 1200)
    T.eq(XP.bar:GetValue(), 300)
    T.eq(XP.rested:GetValue(), 700, "rested runs ahead of it")
    local Style = DaylightUI.Style
    T.falsy(Style.BarBack(XP.bar):IsShown(), "no background over the rested part")
    T.truthy(Style.BarBack(XP.rested):IsShown(), "the background under it instead")
    T.eq(XP.rested.__barColor and XP.rested.__barColor[4] or 1, 1, "rested solid")
    -- Hidden where it is: the game's updates call into its parent.
    T.falsy(MainStatusTrackingBarContainer:IsShown(), "the game's XP bar hidden")
    T.eq(MainStatusTrackingBarContainer:GetParent(), UIParent, "and left in place")
    MainStatusTrackingBarContainer:SetShown(true)
    T.falsy(MainStatusTrackingBarContainer:IsShown(), "and kept hidden")
end)

T.test("info panel: the XP bar off keeps the game's hidden unless asked for", function()
    login()
    DaylightUI:Set("InfoPanel", "xp.enabled", false)
    T.falsy(MainStatusTrackingBarContainer:IsShown(), "no bar at all by default")
    MainStatusTrackingBarContainer:SetShown(true)
    T.falsy(MainStatusTrackingBarContainer:IsShown(), "and the game can't bring it back")
    DaylightUI:Set("InfoPanel", "xp.gameBar", true)
    T.truthy(MainStatusTrackingBarContainer:IsShown(), "the game's bar back when asked for")
    DaylightUI:Set("InfoPanel", "xp.enabled", true)
    T.falsy(MainStatusTrackingBarContainer:IsShown(), "and hidden again with the bar on")
end)

-- A quest log: a header, two finished quests (one under a folded header,
-- past the shown entries), one still going, one failed.
local function questLog()
    local log = {
        { isHeader = true, title = "Elwynn" },
        { questID = 1, xp = 250, done = true },
        { questID = 2, xp = 900 },
        { questID = 3, xp = 500, done = true, failed = true },
        { questID = 4, xp = 150, done = true },
    }
    local function find(id) for _, q in ipairs(log) do if q.questID == id then return q end end end
    _G.C_QuestLog = {
        GetNumQuestLogEntries = function() return 3, 4 end,
        GetInfo = function(i) return log[i] end,
        IsComplete = function(id) return find(id).done == true end,
        ReadyForTurnIn = function(id) return find(id).done == true end,
        IsFailed = function(id) return find(id).failed == true end,
    }
    _G.GetQuestLogRewardXP = function(id) return find(id).xp end
    return log
end

T.test("info panel: the XP bar shows the XP waiting in finished quests, rested after it", function()
    local log = questLog()
    local DUI = login()
    local XP = stub.infopanel.XP
    T.eq(XP.bankedXP, 400, "the two finished quests, not the failed or unfinished ones")
    T.eq(XP.bankedQuests, 2)
    T.truthy(XP.banked:IsShown())
    T.eq(XP.banked:GetValue(), 700, "right after the fill (300 + 400)")
    T.eq(XP.rested:GetValue(), 1100, "rested runs on past it")
    T.rgb(XP.banked.__barColor, DUI.Style.INK.GOOD, "green: done")
    -- A quest done: it grows; turned in, it shrinks.
    log[3].done = true
    stub.FireEvent("QUEST_LOG_UPDATE")
    T.eq(XP.bankedXP, 1300)
    T.eq(XP.banked:GetValue(), 1200, "capped at the level's end")
    T.eq(XP.rested:GetValue(), 1200)
    table.remove(log, 2)
    stub.FireEvent("QUEST_LOG_UPDATE")
    T.eq(XP.bankedXP, 1050)
    -- The switch off: gone, rested back on the fill.
    DUI:Set("InfoPanel", "xp.banked", false)
    T.eq(XP.bankedXP, 0)
    T.eq(XP.banked:GetValue(), 0)
    T.eq(XP.rested:GetValue(), 700)
    _G.C_QuestLog, _G.GetQuestLogRewardXP = nil, nil
end)

T.test("info panel: the XP bar's text shows the numbers, the percent, or both", function()
    local DUI = login()
    local XP = stub.infopanel.XP
    T.falsy(XP.text:IsShown(), "no text by default")
    DUI:Set("InfoPanel", "xp.showPercent", true)
    T.truthy(XP.text:IsShown())
    T.eq(XP.text:GetText(), "25%", "percent alone")
    DUI:Set("InfoPanel", "xp.showText", true)
    T.eq(XP.text:GetText(), "300 / 1,200   25%   (+400)", "numbers, percent, then rested")
    DUI:Set("InfoPanel", "xp.showPercent", false)
    T.eq(XP.text:GetText(), "300 / 1,200   (+400)", "numbers alone")
    T.eq(XP.text.__font[2], 9, "small by default")
    DUI:Set("InfoPanel", "xp.textSize", 24)
    T.eq(XP.text.__font[2], 24, "at its own size")
end)

T.test("info panel: the XP bar can grow much bigger", function()
    local DUI = login()
    local P = stub.infopanel.Panel
    T.truthy(P.XP_MAX[1] >= 2000 and P.XP_MAX[2] >= 60, "room to grow")
    DUI:Set("InfoPanel", "xp.detached", true)
    DUI:Set("InfoPanel", "xp.width", 1500)
    DUI:Set("InfoPanel", "xp.height", 50)
    local xT = DUI.Pixel.Px(P.xp, DUI.Style.BorderPx(P.xp))
    T.eq(P.xp:GetWidth(), 1500)
    T.eq(P.xp:GetHeight(), 50 + 2 * xT)
end)

T.test("info panel: the separate XP and reputation bars can stand upright, filling bottom to top", function()
    local DUI = login()
    local P, XP, Rep = stub.infopanel.Panel, stub.infopanel.XP, stub.infopanel.RepBar
    _G.C_Reputation = { GetWatchedFactionData = function()
        return { name = "Stormwind", reaction = 5, currentReactionThreshold = 0, nextReactionThreshold = 3000, currentStanding = 1800 }
    end }
    DUI:Set("InfoPanel", "xp.orientation", "vertical")
    T.eq(XP.bar.__orientation, "HORIZONTAL", "attached to the panel it stays across")
    DUI:Set("InfoPanel", "xp.detached", true)
    DUI:Set("InfoPanel", "xp.width", 300)
    DUI:Set("InfoPanel", "xp.height", 12)
    local xT = DUI.Pixel.Px(P.xp, DUI.Style.BorderPx(P.xp))
    T.eq(P.xp:GetHeight(), 300, "the width setting is how tall it stands")
    T.eq(P.xp:GetWidth(), 12 + 2 * xT, "the height setting how thick")
    for _, b in ipairs({ XP.bar, XP.banked, XP.rested, XP.repBar }) do T.eq(b.__orientation, "VERTICAL") end
    T.eq(XP.text.__rotation, XP.TURN, "the text reads along it")
    XP.Update()
    local g = XP.bar:GetStatusBarTexture().__gradient
    T.truthy(g and g[1] == "VERTICAL", "the gradient runs bottom to top: " .. tostring(g and g[1]))
    DUI:Set("InfoPanel", "rep.enabled", true)
    DUI:Set("InfoPanel", "rep.orientation", "vertical")
    DUI:Set("InfoPanel", "rep.width", 250)
    T.eq(Rep.frame:GetHeight(), 250)
    T.eq(Rep.bar.__orientation, "VERTICAL")
    local rg = Rep.bar:GetStatusBarTexture().__gradient
    T.truthy(rg and rg[1] == "VERTICAL", "reputation keeps its gradient, upright")
    DUI:Set("InfoPanel", "xp.orientation", "horizontal")
    T.eq(P.xp:GetWidth() > 100, true, "back across")
    T.eq(XP.bar.__orientation, "HORIZONTAL")
    DUI:Set("InfoPanel", "rep.enabled", false)
    _G.C_Reputation = nil
end)

T.test("info panel: the XP bar wears the accent by default", function()
    local DUI = login()
    local XP = stub.infopanel.XP
    local fill = XP.bar:GetStatusBarTexture()
    T.eq(XP.colorMode, "accent")
    T.truthy(fill.__gradient, "a gradient on a one-color accent too")
    local before = fill.__gradient[3]
    DUI:Set("general", "accent", "custom")
    DUI:Set("general", "accentColor", { 0.1, 0.9, 0.3 })
    XP.Update()
    T.truthy(fill.__gradient[3] ~= before, "a new accent repaints it")
    DUI:Set("InfoPanel", "xp.gradient", false)
    T.rgb({ XP.bar.__barColor[1], XP.bar.__barColor[2], XP.bar.__barColor[3] }, { 0.1, 0.9, 0.3 })
end)

T.test("info panel: the XP bar's gradient, in its own color or the class's", function()
    local DUI = login()
    local XP = stub.infopanel.XP
    local fill = XP.bar:GetStatusBarTexture()
    DUI:Set("InfoPanel", "xp.color", "class")
    T.truthy(fill.__gradient, "the class pair")
    local class = fill.__gradient[3]
    DUI:Set("InfoPanel", "xp.classColor", false)
    T.truthy(fill.__gradient and fill.__gradient[3] ~= class, "its own blue instead")
    DUI:Set("InfoPanel", "xp.gradient", false)
    T.eq(XP.bar.__barColor[1], XP.COLOR[1], "back to flat blue")
end)

T.test("info panel: the XP bar's color pick: accent, class, blue, or a pair of your own", function()
    local DUI = login()
    local XP = stub.infopanel.XP
    local fill = XP.bar:GetStatusBarTexture()
    DUI:Set("InfoPanel", "xp.color", "class")
    local class = fill.__gradient[3]
    DUI:Set("InfoPanel", "xp.color", "blue")
    T.truthy(fill.__gradient[3] ~= class, "blue is not the class pair")
    DUI:Set("InfoPanel", "xp.color", "custom")
    DUI:Set("InfoPanel", "xp.customHi", { 0, 1, 0 })
    T.truthy(fill.__gradient, "the custom pair as a gradient")
    DUI:Set("InfoPanel", "xp.gradient", false)
    T.eq(XP.bar.__barColor[2], 1, "plain: the pair's bright end")
    DUI:Set("InfoPanel", "xp.gradient", true)
    DUI:Set("InfoPanel", "xp.color", "class")
    DUI:Set("InfoPanel", "xp.classColor", false)
    T.eq(XP.colorMode, "blue", "the old Class color switch off still means blue")
    DUI:Set("InfoPanel", "xp.color", "accent")
    T.eq(XP.colorMode, "blue", "over the new default too")
end)

T.test("info panel: XP bar segments: 19 lines across the bar, only on experience", function()
    local DUI = login()
    local XP = stub.infopanel.XP
    T.falsy(XP.tickFrame:IsShown(), "off by default")
    DUI:Set("InfoPanel", "xp.ticks", true)
    T.truthy(XP.tickFrame:IsShown(), "on")
    T.eq(#XP.tickList, 19, "20 segments")
    XP.bar:SetWidth(200)
    XP.LayoutTicks()
    local _, _, _, x = XP.tickList[1]:GetPoint(1)
    T.near(x, 10, 1, "the first line at 5%")
    _G.IsPlayerAtEffectiveMaxLevel = function() return true end
    _G.C_Reputation = { GetWatchedFactionData = function()
        return { name = "Darnassus", reaction = 7, currentReactionThreshold = 0,
                 nextReactionThreshold = 1000, currentStanding = 400 }
    end }
    XP.Update()
    T.falsy(XP.tickFrame:IsShown(), "reputation has no segments")
    _G.IsPlayerAtEffectiveMaxLevel = function() return false end
    _G.C_Reputation = nil
end)

T.test("info panel: XP hover details open toward the screen's middle, or where picked", function()
    local DUI = login()
    local XP = stub.infopanel.XP
    local f = XP.frame
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    f.__w, f.__center = 200, { sw - 150, sh - 20 }
    T.eq(XP.TipSide(f), "left", "the panel's bar, top right: left")
    f.__center = { 150, sh / 2 }
    T.eq(XP.TipSide(f), "right", "on the left half: right")
    f.__w, f.__center = sw / 2, { sw / 2, 20 }
    T.eq(XP.TipSide(f), "above", "a wide bar at the bottom: above")
    DUI:Set("InfoPanel", "xp.tipSide", "below")
    T.eq(XP.TipSide(f), "below", "picked by hand")
end)

T.test("info panel: at the cap, reputation's gradient is its standing's pair", function()
    local DUI = login()
    local XP, G = stub.infopanel.XP, DUI.Gradients
    _G.IsPlayerAtEffectiveMaxLevel = function() return true end
    _G.C_Reputation = { GetWatchedFactionData = function()
        return { name = "Darnassus", reaction = 7, currentReactionThreshold = 0,
                 nextReactionThreshold = 1000, currentStanding = 400 }
    end }
    DUI:Set("InfoPanel", "xp.gradient", true)
    DUI:Set("InfoPanel", "xp.classColor", true)
    local _, hi = G.Colors("REP_7")
    T.eq(XP.bar:GetStatusBarTexture().__gradient[3], hi, "Revered's pair, not the class's")
    for i = 1, 8 do T.truthy(G.Has("REP_" .. i), "a pair for standing " .. i) end
    _G.IsPlayerAtEffectiveMaxLevel = function() return false end
    _G.C_Reputation = nil
end)

T.test("info panel: a reputation gain turns the XP bar to it for a few seconds, then back", function()
    local DUI = login()
    local XP = stub.infopanel.XP
    local standing = 400
    _G.C_Reputation = { GetWatchedFactionData = function()
        return { name = "Stormwind", reaction = 5, currentReactionThreshold = 0,
                 nextReactionThreshold = 1000, currentStanding = standing }
    end }
    local function settleTweens()
        local d = DUI.Motion.Driver()
        for _ = 1, 40 do stub.RunOnUpdate(d, 0.05) end
    end
    stub.FireEvent("UPDATE_FACTION")
    settleTweens()
    T.eq(XP.repBar:GetAlpha(), 0, "the first read only remembers")
    standing = 425
    stub.FireEvent("UPDATE_FACTION")
    settleTweens()
    T.eq(XP.repBar:GetAlpha(), 1, "a gain shows the faction")
    T.eq(XP.repBar:GetValue(), 425)
    stub.Advance(XP.REP_HOLD)
    stub.RunTimers()
    settleTweens()
    T.eq(XP.repBar:GetAlpha(), 0, "back to experience after the hold")
    -- The mouse over the bar holds the faction until it leaves.
    XP.frame.__scripts.OnEnter(XP.frame)
    settleTweens()
    T.eq(XP.repBar:GetAlpha(), 1, "hover shows it")
    XP.frame.__scripts.OnLeave(XP.frame)
    settleTweens()
    T.eq(XP.repBar:GetAlpha(), 0, "leaving lets it go")
    -- A loss, or another faction watched, doesn't turn the bar.
    standing = 300
    stub.FireEvent("UPDATE_FACTION")
    settleTweens()
    T.eq(XP.repBar:GetAlpha(), 0, "a loss stays experience")
    _G.C_Reputation = nil
end)

T.test("info panel: the separate reputation bar shows the watched faction, sizes, moves and takes the gains", function()
    local DUI = login()
    local XP, Rep = stub.infopanel.XP, stub.infopanel.RepBar
    local standing, watched = 1800, true
    _G.C_Reputation = { GetWatchedFactionData = function()
        if not watched then return nil end
        return { name = "Stormwind", reaction = 5, currentReactionThreshold = 0,
                 nextReactionThreshold = 3000, currentStanding = standing }
    end }
    local function settleTweens()
        local d = DUI.Motion.Driver()
        for _ = 1, 40 do stub.RunOnUpdate(d, 0.05) end
    end
    T.falsy(Rep.frame:IsShown(), "off by default")
    T.truthy(DUI.Movers.Get("infopanel.rep").suspended, "no unlock handle while off")
    DUI:Set("InfoPanel", "rep.enabled", true)
    T.truthy(Rep.frame:IsShown(), "on: shown")
    T.falsy(DUI.Movers.Get("infopanel.rep").suspended, "a handle to move it")
    T.eq(select(2, Rep.bar:GetMinMaxValues()), 3000)
    T.eq(Rep.text:GetText(), "Stormwind   60%", "name and percent by default")
    DUI:Set("InfoPanel", "rep.showText", true)
    T.eq(Rep.text:GetText(), "Stormwind   1,800 / 3,000   60%")
    DUI:Set("InfoPanel", "rep.width", 400)
    DUI:Set("InfoPanel", "rep.height", 20)
    local T2 = DUI.Pixel.Px(Rep.frame, DUI.Style.BorderPx(Rep.frame))
    T.eq(Rep.frame:GetWidth(), 400)
    T.eq(Rep.frame:GetHeight(), 20 + 2 * T2)
    -- A gain goes to this bar; the experience bar stays experience.
    stub.FireEvent("UPDATE_FACTION")
    standing = 1900
    stub.FireEvent("UPDATE_FACTION")
    settleTweens()
    T.eq(XP.repBar:GetAlpha(), 0, "the XP bar doesn't turn")
    T.eq(Rep.text:GetText(), "Stormwind   1,900 / 3,000   63%")
    -- No faction watched: away, but a sample while unlocked.
    watched = false
    stub.FireEvent("UPDATE_FACTION")
    T.falsy(Rep.frame:IsShown(), "nothing watched: away")
    DUI.Movers.Unlock()
    T.truthy(Rep.frame:IsShown(), "unlocked: a sample to place")
    DUI.Movers.Lock()
    T.falsy(Rep.frame:IsShown())
    DUI:Set("InfoPanel", "rep.enabled", false)
    _G.C_Reputation = nil
end)

T.test("info panel: the meter draws the game's sources in class colors", function()
    local DUI = login()
    local M = stub.infopanel.Meter
    stub.meter.sources = {
        { name = "Teft-Realm", classFilename = "WARRIOR", totalAmount = 5000 },
        { name = "Rock", classFilename = "HUNTER", totalAmount = 2500 },
    }
    M.Draw()
    T.eq(stub.meter.asked[1], Enum.DamageMeterSessionType.Current)
    T.eq(stub.meter.asked[2], Enum.DamageMeterType.DamageDone)
    local rows = bars()
    local first = rows[1]
    T.truthy(first:IsShown())
    T.eq(select(2, first.bar:GetMinMaxValues()), 5000, "scaled to the top source")
    T.eq(first.bar:GetValue(), 5000)
    T.truthy(not rows[3]:IsShown(), "no source, no bar")
    T.eq(stub.cvars.damageMeterEnabled, "0", "the game's own meter off")
    local writes = stub.cvarWrites
    M.Apply(stub.infopanel.module.db.meter)
    T.eq(stub.cvarWrites, writes, "not written again when it's already off")
end)

T.test("info panel: secret amounts and names go through untouched", function()
    login()
    local M = stub.infopanel.Meter
    stub.meter.sources = {
        { name = stub.Secret("Kaladin"), classFilename = "WARRIOR", totalAmount = stub.Secret(900) },
    }
    M.Draw()
    T.truthy(bars()[1]:IsShown())
end)

T.test("info panel: a 40-player raid scrolls all the way to the last", function()
    login()
    -- A height the rows don't fill exactly, so the column ends in a cut-off row.
    DaylightUI:Set("InfoPanel", "map.size", 196)
    stub.RunTimers()
    local M, area = stub.infopanel.Meter, stub.infopanel.Panel.meterArea
    stub.meter.sources = {}
    for i = 1, 40 do
        stub.meter.sources[i] = { name = "Player" .. i, classFilename = "MAGE", totalAmount = 1000 - i }
    end
    M.Draw()
    local rows = {}
    for _, r in ipairs(bars()) do if r.fits then rows[#rows + 1] = r end end
    local tail = rows[#rows]
    T.truthy(tail:IsShown(), "a row cut off at the bottom still shows")
    for _ = 1, 100 do area:GetScript("OnMouseWheel")(area, -1) end
    local shown = {}
    for _, r in ipairs(rows) do if r:IsShown() then shown[#shown + 1] = r end end
    T.eq(shown[#shown].bar:GetValue(), 1000 - 40, "player 40 at the bottom, in full")
    T.falsy(tail:IsShown(), "nothing below the last player")
    for _ = 1, 100 do area:GetScript("OnMouseWheel")(area, 1) end
    T.eq(shown[1].bar:GetValue(), 1000 - 1, "and back up to the top")
end)

T.test("info panel: the mode button opens a drop-down of every mode", function()
    local DUI = login()
    local M, area = stub.infopanel.Meter, stub.infopanel.Panel.meterArea
    T.eq(#M.MODES, 11, "every mode the game keeps")
    area:GetScript("OnEnter")(area)
    local b = M.header.buttons.mode
    T.eq(b.kind, "mode")
    T.eq(stub.Text(M.header.mode), "DAMAGE")
    b:GetScript("OnClick")(b)
    T.eq(DUI.Widgets.menuOwner, b, "a drop-down opens")
    local rows = menuRows()
    T.eq(rows[3].text.__text, "Damage per second")
    rows[3]:GetScript("OnClick")(rows[3])
    T.eq(DUI:Get("InfoPanel", "meter.mode"), "dps")
    T.isnil(DUI.Widgets.menuOwner, "closed after a pick")
    stub.RunTimers()
    M.Draw()
    T.eq(stub.Text(M.header.mode), "DPS")
    -- Deaths: a full bar and when it happened.
    DUI:Set("InfoPanel", "meter.mode", "deaths")
    stub.RunTimers()
    stub.meter.sources = { { name = "Teft", classFilename = "WARRIOR", deathTimeSeconds = 83 } }
    M.Draw()
    local first = bars()[1]
    T.eq(first.bar:GetValue(), 1)
    T.eq(first.amount.__text, "1:23")
end)

T.test("info panel: the meter's header buttons are the shared icon buttons, tan at rest", function()
    local DUI = login()
    local M, area = stub.infopanel.Meter, stub.infopanel.Panel.meterArea
    area:GetScript("OnEnter")(area)
    T.truthy(M.header.modeLink and M.header.fightLink, "the mode and the fight are words to click")
    for _, k in ipairs({ "report", "reset", "new", "options" }) do
        local r = M.header.buttons[k].icon:GetVertexColor()
        T.near(r, DUI.Style.INK.LABEL[1], 1e-6, k .. " tan at rest")
    end
end)

T.test("info panel: the fight drop-down lists overall, current, and earlier fights by name", function()
    local DUI = login()
    local M, area = stub.infopanel.Meter, stub.infopanel.Panel.meterArea
    stub.meter.fights = {
        { sessionID = 1, name = "Hogger", durationSeconds = 42 },
        { sessionID = 2, name = "Van Cleef", durationSeconds = 125 },
        { sessionID = 3, name = stub.Secret("Mystery"), durationSeconds = 10 },
    }
    local h = M.header
    T.falsy(h.tools:IsShown(), "the buttons wait for the mouse")
    function area:IsMouseOver() return true end
    area:GetScript("OnEnter")(area)
    T.truthy(h.tools:IsShown())
    local b = h.buttons.fight
    b:GetScript("OnClick")(b)
    local rows = menuRows()
    T.eq(#rows, 4, "overall, current, and only the fights that exist")
    T.eq(rows[1].text.__text, "Overall")
    T.eq(rows[2].text.__text, "Current: Combat", "a secret name reads as Combat")
    T.eq(rows[3].text.__text, "Van Cleef  2:05", "named for what was fought")
    T.eq(rows[4].text.__text, "Hogger  0:42")
    rows[3]:GetScript("OnClick")(rows[3])
    T.eq(stub.Text(h.fight), "Van Cleef", "the header names it")
    T.eq(stub.Text(h.timer), "2:05", "and how long it ran")
    M.Draw()
    T.eq(stub.meter.asked[1], "id"); T.eq(stub.meter.asked[2], 2)
    b:GetScript("OnClick")(b)
    menuRows()[1]:GetScript("OnClick")(menuRows()[1])
    T.eq(DUI:Get("InfoPanel", "meter.session"), "overall")
    M.Draw()
    T.eq(stub.meter.asked[1], Enum.DamageMeterSessionType.Overall)
    -- A picked fight the game has since dropped falls back to current.
    b:GetScript("OnClick")(b)
    menuRows()[4]:GetScript("OnClick")(menuRows()[4])
    stub.meter.gone = 1
    M.Draw()
    T.isnil(M.fight)
    -- Leaving the meter puts the buttons away.
    function area:IsMouseOver() return false end
    area:GetScript("OnUpdate")(area)
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 1)
    T.falsy(h.tools:IsShown())
end)

T.test("info panel: test mode shows a different list for each mode", function()
    local DUI = login()
    local M = stub.infopanel.Meter
    DUI.SetTestMode(true)
    M.Draw()
    T.eq(bars()[1].name.__text, "Kaladin", "damage: the sample raid")
    DUI:Set("InfoPanel", "meter.mode", "healing")
    T.eq(bars()[1].name.__text, "Navani", "healing: a healer leads")
    DUI:Set("InfoPanel", "meter.mode", "taken")
    T.eq(M.SampleFor("taken")[1].classFilename, "WARRIOR", "damage taken: a tank leads")
    DUI:Set("InfoPanel", "meter.mode", "enemy")
    T.eq(bars()[1].name.__text, "Chasmfiend", "enemy damage taken: enemies")
    for _, m in ipairs(M.MODES) do T.truthy(#M.SampleFor(m.key) > 0, m.key .. " has sample rows") end
end)

T.test("info panel: hovering a bar breaks their number down by spell", function()
    local DUI = login()
    local M, B, area = stub.infopanel.Meter, stub.infopanel.Breakdown, stub.infopanel.Panel.meterArea
    stub.meter.sources = { { name = "Sigzil", classFilename = "MAGE", totalAmount = 1000, sourceGUID = "Player-2" } }
    stub.meter.spells = { { spellID = 1, totalAmount = 750 }, { spellID = 2, totalAmount = 250 } }
    M.Draw()
    local bar = bars()[1]
    -- The hover watcher opens it for the bar under the mouse.
    function bar:IsMouseOver() return true end
    function area:IsMouseOver() return true end
    area:GetScript("OnEnter")(area)
    area:GetScript("OnUpdate")(area)
    local f = B.Frame()
    T.truthy(f and f:IsShown(), "open beside the panel")
    T.eq(stub.meter.askedSource[3], "Player-2", "asked about that player")
    T.eq(stub.meter.askedSource[2], Enum.DamageMeterType.DamageDone, "for the mode on show")
    local rows = {}
    for _, c in ipairs(stub.Children(f)) do if c.amount and c:IsShown() then rows[#rows + 1] = c end end
    T.eq(#rows, 2)
    T.eq(rows[1].name.__text, "Fireball")
    T.eq(rows[1].amount.__text, "750  75%", "amount and share")
    T.eq(rows[1].icon.__texture, 1001)
    -- Moving off the meter closes it.
    function area:IsMouseOver() return false end
    area:GetScript("OnUpdate")(area)
    T.falsy(f:IsShown())
end)

T.test("info panel: in combat, your own breakdown works, others wait until after", function()
    login()
    local M, B = stub.infopanel.Meter, stub.infopanel.Breakdown
    stub.meter.spells = { { spellID = 1, totalAmount = stub.Secret(40) } }
    local mine = { name = "Me", classFilename = "MAGE", totalAmount = stub.Secret(40),
                   sourceGUID = stub.Secret("Player-1"), isLocalPlayer = true }
    local spells = B.Spells(mine)
    T.eq(stub.meter.askedSource[3], "Player-1", "your plain GUID, not the secret one")
    T.eq(#spells, 1)
    local theirs = { name = "Them", classFilename = "ROGUE", totalAmount = stub.Secret(40),
                     sourceGUID = stub.Secret("Player-9"), isLocalPlayer = false }
    local none, why = B.Spells(theirs)
    T.isnil(none); T.eq(why, B.WAIT)
    -- A secret amount shows without a share, and nothing is compared.
    M.Draw()
    stub.meter.sources = { mine }
    M.Draw()
    B.Show(bars()[1])
    T.truthy(B.Frame():IsShown())
end)

T.test("info panel: no breakdown for deaths; test mode has sample spells", function()
    local DUI = login()
    local B = stub.infopanel.Breakdown
    DUI:Set("InfoPanel", "meter.mode", "deaths")
    T.isnil(B.Spells({ name = "Teft", sourceGUID = "Player-3" }))
    DUI:Set("InfoPanel", "meter.mode", "healing")
    DUI.SetTestMode(true)
    local spells = B.Spells({ name = "Navani", totalAmount = 1000 })
    T.eq(spells[1].name, B.SAMPLE.healing[1][1])
    T.eq(spells[1].amount, 410)
end)

T.test("info panel: amounts read total, then per second", function()
    local DUI = login()
    local M = stub.infopanel.Meter
    DUI:Set("InfoPanel", "meter.showShare", false)
    stub.RunTimers()
    stub.meter.sources = { { name = "Sigzil", classFilename = "MAGE", totalAmount = 2640, amountPerSecond = 335.7 } }
    M.Draw()
    T.eq(stub.Text(bars()[1].amount), "335 (2.6K)", "the rate drops its fraction")
    stub.meter.sources = { { name = "Safiyah", classFilename = "MAGE", totalAmount = 37, amountPerSecond = 0.71153846153846 } }
    M.Draw()
    T.eq(stub.Text(bars()[1].amount), "0 (37)", "below one: whole, never a long decimal")
    -- In a fight the rate is secret and can't be floored here, so the
    -- shortener must round it itself (it once read "0.1298239838983").
    T.eq(stub.Plain(M.Short(stub.Secret(0.1298239838983))), "0", "a secret below one: whole too")
    T.eq(stub.Plain(M.Short(stub.Secret(335.7))), "335", "a secret rate drops its fraction")
    T.eq(stub.Plain(M.Short(stub.Secret(2640))), "2.6K")
    -- Secret numbers in combat go straight through.
    stub.meter.sources = { { name = "Sigzil", classFilename = "MAGE", totalAmount = stub.Secret(2640),
                             amountPerSecond = stub.Secret(335) } }
    M.Draw()
    T.truthy(bars()[1]:IsShown())
    stub.meter.sources = { { name = "Sigzil", classFilename = "MAGE", totalAmount = 400, amountPerSecond = 32.54 } }
    M.Draw()
    T.eq(stub.Text(bars()[1].amount), "32 (400)", "no decimals")
    -- Counts stay counts.
    DUI:Set("InfoPanel", "meter.mode", "interrupts")
    stub.meter.sources = { { name = "Lopen", classFilename = "ROGUE", totalAmount = 6, amountPerSecond = 0.1 } }
    M.Draw()
    T.eq(stub.Text(bars()[1].amount), "6")
end)

T.test("info panel: meter numbers in full", function()
    local DUI = login()
    local M = stub.infopanel.Meter
    DUI:Set("InfoPanel", "meter.numbers", "full")
    DUI:Set("InfoPanel", "meter.showShare", false)
    stub.RunTimers()
    stub.meter.sources = { { name = "Sigzil", classFilename = "MAGE", totalAmount = 123456, amountPerSecond = 1234.7 } }
    M.Draw()
    T.eq(stub.Text(bars()[1].amount), "1,234 (123,456)", "whole, with the game's separator")
    T.eq(stub.Plain(M.Short(stub.Secret(12000))), "12,000", "a secret goes through")
    T.eq(stub.Plain(M.Short(stub.Secret(335.27))), "335", "a secret rate in full: whole")
    T.eq(stub.Plain(M.Short(stub.Secret(0.1298239838983))), "0", "below one in full: whole")
    DUI:Set("InfoPanel", "meter.numbers", "short")
    M.Draw()
    T.eq(stub.Text(bars()[1].amount), "1.2K (123.4K)", "back to short")
end)

T.test("info panel: bars are outlined and glide, but snap when the view changes", function()
    local DUI = login()
    local M = stub.infopanel.Meter
    stub.meter.sources = { { name = "Sigzil", classFilename = "MAGE", totalAmount = 400 } }
    M.Draw()
    local row = bars()[1]
    T.isnil(row.box, "no outline round a row")
    stub.meter.sources[1].totalAmount = 500
    M.Draw()
    T.truthy(row.bar.__interp ~= nil, "a new value glides in")
    DUI:Set("InfoPanel", "meter.mode", "healing")
    T.isnil(row.bar.__interp, "a new mode jumps straight there")
end)

T.test("info panel: the meter can wait for a group, for combat, or both", function()
    local DUI = login()
    local P = stub.infopanel.Panel
    local wide = P.holder:GetWidth()
    DUI:Set("InfoPanel", "meter.inGroup", true)
    settle()
    T.falsy(P.meterArea:IsShown(), "solo: away")
    T.falsy(P.arrow:IsShown(), "no tab while it waits: a click would switch it off")
    T.truthy(P.holder:GetWidth() < wide, "the panel narrows to the minimap")
    stub.inGroup = true
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    T.truthy(P.meterArea:IsShown(), "in a group: back")
    DUI:Set("InfoPanel", "meter.inCombat", true)
    settle()
    T.falsy(P.meterArea:IsShown(), "both on: a group isn't enough")
    stub.EnterCombat()
    T.truthy(P.meterArea:IsShown(), "in a group and in combat")
    stub.LeaveCombat()
    settle()
    T.falsy(P.meterArea:IsShown())
    DUI.SetTestMode(true)
    T.truthy(P.meterArea:IsShown(), "test mode always shows it")
end)

T.test("info panel: joining a group keeps, asks about, or resets the fights", function()
    local DUI = login()
    stub.meter.fights = { { sessionID = 1 } }
    stub.inGroup = true
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    T.falsy(stub.meter.reset, "keeps them by default")
    stub.inGroup = false
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    DUI:Set("InfoPanel", "meter.onJoin", "ask")
    stub.inGroup = true
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    T.eq(stub.popup, "DAYLIGHTUI_METER_RESET"); T.falsy(stub.meter.reset)
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    stub.inGroup = false
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    DUI:Set("InfoPanel", "meter.onJoin", "reset")
    stub.inGroup = true
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    T.truthy(stub.meter.reset)
    stub.meter.reset = nil
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    T.falsy(stub.meter.reset, "only on joining, not every roster change")
end)

-- Goes through a loading screen into `instance` (an id, or nil for outside).
local function zoneTo(instance, ...)
    stub.instance = instance and "party" or "none"
    _G.GetInstanceInfo = function() return "Dungeon", stub.instance, 1, "Normal", 5, 0, false, instance end
    stub.FireEvent("PLAYER_ENTERING_WORLD", ...)
end

T.test("info panel: entering an instance keeps, asks about, or resets the fights", function()
    local DUI = login()
    stub.meter.fights = { { sessionID = 1 } }
    stub.popup = nil
    zoneTo(33)
    T.eq(stub.popup, "DAYLIGHTUI_METER_RESET", "asks by default"); T.falsy(stub.meter.reset)
    stub.popup = nil
    zoneTo(nil)
    DUI:Set("InfoPanel", "meter.onInstance", "nothing")
    zoneTo(34)
    T.isnil(stub.popup, "keeps them"); T.falsy(stub.meter.reset)
    zoneTo(nil)
    T.isnil(stub.popup, "leaving isn't entering")
    DUI:Set("InfoPanel", "meter.onInstance", "reset")
    zoneTo(36)
    T.truthy(stub.meter.reset)
    stub.meter.reset = nil
    zoneTo(36)
    T.falsy(stub.meter.reset, "a loading screen inside the same instance")
end)

T.test("info panel: joining and entering each have their own setting", function()
    local DUI = login()
    stub.meter.fights = { { sessionID = 1 } }
    DUI:Set("InfoPanel", "meter.onInstance", "reset")
    stub.inGroup = true
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    T.falsy(stub.meter.reset, "joining still keeps them")
    zoneTo(33)
    T.truthy(stub.meter.reset, "entering resets")
    stub.meter.reset = nil
    zoneTo(nil)
    stub.inGroup = false
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    DUI:Set("InfoPanel", "meter.onInstance", "nothing")
    DUI:Set("InfoPanel", "meter.onJoin", "reset")
    zoneTo(33)
    T.falsy(stub.meter.reset, "entering still keeps them")
    stub.inGroup = true
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    T.truthy(stub.meter.reset, "joining resets")
end)

T.test("info panel: both on Ask, answering yes on joining isn't asked again at the door", function()
    local DUI = login()
    stub.popup = nil
    DUI:Set("InfoPanel", "meter.onJoin", "ask")
    DUI:Set("InfoPanel", "meter.onInstance", "ask")
    stub.meter.fights = { { sessionID = 1 } }
    stub.inGroup = true
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    T.eq(stub.popup, "DAYLIGHTUI_METER_RESET")
    stub.popup = nil
    StaticPopupDialogs.DAYLIGHTUI_METER_RESET.OnAccept()
    stub.meter.fights = {}
    zoneTo(33)
    T.isnil(stub.popup, "nothing left to clear")
end)

T.test("info panel: a /reload or login inside and the run back after dying aren't entering", function()
    local DUI = login()
    stub.meter.fights = { { sessionID = 1 } }
    DUI:Set("InfoPanel", "meter.onInstance", "reset")
    zoneTo(33, false, true)
    T.falsy(stub.meter.reset, "a /reload inside")
    zoneTo(nil)
    zoneTo(33, true, false)
    T.falsy(stub.meter.reset, "a login inside")
    _G.UnitIsDeadOrGhost = function() return true end
    zoneTo(nil)
    _G.UnitIsDeadOrGhost = function() return false end
    zoneTo(33)
    T.falsy(stub.meter.reset, "the run back keeps the wipe's fights")
    zoneTo(nil)
    zoneTo(33)
    T.truthy(stub.meter.reset, "walking in again alive is a new run")
    _G.UnitIsDeadOrGhost = nil
end)

T.test("info panel: the tab is the meter's Show switch, on the panel", function()
    local DUI = login()
    local P = stub.infopanel.Panel
    local wide = P.holder:GetWidth()
    T.truthy(P.arrow:IsShown())
    P.arrow:GetScript("OnClick")(P.arrow)
    T.falsy(DUI:Get("InfoPanel", "meter.enabled"), "the same setting as the options' Show")
    settle()
    T.falsy(P.meterArea:IsShown())
    T.truthy(P.holder:GetWidth() < wide)
    T.truthy(P.arrow:IsShown(), "still there to bring it back")
    P.arrow:GetScript("OnClick")(P.arrow)
    T.truthy(P.meterArea:IsShown())
    settle()
    T.eq(P.holder:GetWidth(), wide)
end)

T.test("info panel: the meter slides open and folded, not in one jump", function()
    local DUI = login()
    local P = stub.infopanel.Panel
    local wide = P.holder:GetWidth()
    P.arrow:GetScript("OnClick")(P.arrow)
    T.eq(P.holder:GetWidth(), wide, "starts where it was")
    T.truthy(P.meterArea:IsShown(), "still there while it folds")
    stub.RunOnUpdate(P.slide.driver, P.SLIDE / 2)
    local mid = P.holder:GetWidth()
    T.truthy(mid < wide, "part way")
    T.truthy(P.meterClip:GetAlpha() > 0 and P.meterClip:GetAlpha() < 1, "fading as it goes")
    settle()
    local narrow = P.holder:GetWidth()
    T.truthy(narrow < mid)
    T.falsy(P.meterArea:IsShown())
    T.falsy(P.slide.driver:IsShown(), "stops once there")
    -- Clicked again half way back: turns round from where it is.
    P.arrow:GetScript("OnClick")(P.arrow)
    stub.RunOnUpdate(P.slide.driver, P.SLIDE / 2)
    local back = P.holder:GetWidth()
    P.arrow:GetScript("OnClick")(P.arrow)
    T.eq(P.holder:GetWidth(), back, "no jump on turning round")
    settle()
    T.eq(P.holder:GetWidth(), narrow)
    -- With the minimap off the panel comes and goes with the meter: no slide.
    DUI:Set("InfoPanel", "map.enabled", false)
    DUI:Set("InfoPanel", "meter.enabled", true)
    T.truthy(P.meterArea:IsShown())
    T.falsy(P.slide.driver:IsShown(), "no minimap to slide against: straight there")
end)

T.test("info panel: detached, the meter gets its own movable window", function()
    local DUI = login()
    local P = stub.infopanel.Panel
    local wide = P.holder:GetWidth()
    DUI:Set("InfoPanel", "meter.detached", true)
    T.eq(P.meterArea:GetParent(), P.meterFrame)
    T.truthy(P.meterFrame:IsShown())
    T.truthy(DUI.Style.GetShell(P.meterFrame), "framed like the panel")
    settle()
    T.truthy(P.holder:GetWidth() < wide, "the panel keeps just the minimap")
    T.falsy(P.arrow:IsShown(), "no arrow: it isn't in the panel")
    T.truthy(DUI.Movers.Get("infopanel.meter"))
    DUI:Set("InfoPanel", "meter.detached", false)
    T.eq(P.meterArea:GetParent(), P.meterClip)
    T.falsy(P.meterFrame:IsShown())
end)

T.test("info panel: the tab only shows while the mouse is near the panel", function()
    local DUI = login()
    local P = stub.infopanel.Panel
    T.isnil(P.holder:GetScript("OnUpdate"), "no watcher on the panel itself: only while the tab shows")
    T.isnil(P.arrow:GetScript("OnUpdate"), "one shared look for the tabs (Panel.WatchHover), none per frame")
    local function tick() stub.RunOnUpdate(P.hoverDriver, P.HOVER_EVERY) end
    tick()
    T.eq(P.arrow:GetAlpha(), 0, "out of sight")
    function P.holder:IsMouseOver() return true end
    tick()
    T.truthy(P.arrow:GetAlpha() < 1, "it eases in, never pops (rule 6)")
    local d = DUI.Motion.Driver()
    for _ = 1, 10 do stub.Advance(0.05); stub.RunOnUpdate(d, 0.05) end
    T.eq(P.arrow:GetAlpha(), 1, "over the panel: there")
    -- Hidden while the mouse is near, back after it has left: right at once.
    P.arrow:Hide()
    function P.holder:IsMouseOver() return false end
    P.arrow:Show()
    T.eq(P.arrow:GetAlpha(), 0, "shown again: out of sight before its first frame")
end)

T.test("info panel: unlocked, the separate meter window resizes from its corner", function()
    local DUI = login()
    local P = stub.infopanel.Panel
    DUI:Set("InfoPanel", "meter.detached", true)
    T.falsy(P.grip:IsShown(), "locked: no grip")
    DUI.Movers.Unlock()
    T.truthy(P.grip:IsShown(), "unlocked: a grip in the corner")
    local edge = P.meterFrame:GetWidth() - DUI:Get("InfoPanel", "meter.width")
    P.grip:GetScript("OnMouseDown")(P.grip)
    P.meterFrame:SetSize(260 + edge, 300 + edge)
    P.grip:GetScript("OnMouseUp")(P.grip)
    T.eq(DUI:Get("InfoPanel", "meter.width"), 260, "the new size kept")
    T.eq(DUI:Get("InfoPanel", "meter.height"), 300)
    P.meterFrame:SetSize(5000 + edge, 10 + edge)
    P.grip:GetScript("OnMouseUp")(P.grip)
    T.eq(DUI:Get("InfoPanel", "meter.width"), P.METER_MAX[1], "within its limits")
    T.eq(DUI:Get("InfoPanel", "meter.height"), P.METER_MIN[2])
    DUI.Movers.Lock()
    T.falsy(P.grip:IsShown())
    DUI:Set("InfoPanel", "meter.detached", false)
    DUI.Movers.Unlock()
    T.falsy(P.grip:IsShown(), "docked: no grip")
end)

T.test("info panel: the experience bar stays locked to the panel by default", function()
    local DUI = login()
    local P = stub.infopanel.Panel
    T.eq(P.xp:GetParent(), P.holder)
    local p, rel = P.xp:GetPoint(1)
    T.eq(p, "TOPLEFT"); T.eq(rel, P.holder)
    T.truthy(P.holder:GetHeight() > P.panel:GetHeight(), "its height counts toward the panel's")
    T.falsy(DUI.Movers.Get("infopanel.xp").frame == nil)
end)

T.test("info panel: free to move, the experience bar gets its own place and size", function()
    local DUI = login()
    local P = stub.infopanel.Panel
    local tall = P.holder:GetHeight()
    DUI:Set("InfoPanel", "xp.detached", true)
    T.eq(P.xp:GetParent(), UIParent)
    T.eq(P.xp:GetWidth(), DUI:Get("InfoPanel", "xp.width"))
    T.truthy(P.holder:GetHeight() < tall, "no longer part of the panel's height")
    DUI:Set("InfoPanel", "xp.detached", false)
    T.eq(P.xp:GetParent(), P.holder)
    T.eq(P.holder:GetHeight(), tall)
end)

T.test("info panel: a free experience bar sits under the action bar, as wide", function()
    local DUI = login()
    local P = stub.infopanel.Panel
    local span = P.BarsSpan
    P.BarsSpan = function() return { left = 600, right = 1100, bottom = 26 } end
    DUI:Set("InfoPanel", "xp.detached", true)
    T.eq(P.xp:GetWidth(), 500)
    local d = P.xpDefault
    T.eq(d[1], "BOTTOM"); T.eq(d[4], 850)
    T.truthy(d[5] >= 0 and d[5] + P.xp:GetHeight() <= 26, "in the gap under the buttons")
    DUI:Set("InfoPanel", "xp.matchBars", false)
    T.eq(P.xp:GetWidth(), DUI:Get("InfoPanel", "xp.width"), "its own width once unmatched")
    P.BarsSpan = span
    DUI:Set("InfoPanel", "xp.matchBars", true)
    DUI:Set("InfoPanel", "xp.detached", false)
end)

T.test("info panel: unlocked, the free experience bar resizes from its corner", function()
    local DUI = login()
    local P = stub.infopanel.Panel
    DUI:Set("InfoPanel", "xp.detached", true)
    T.falsy(P.xpGrip:IsShown(), "locked: no grip")
    DUI.Movers.Unlock()
    T.truthy(P.xpGrip:IsShown(), "unlocked: a grip in the corner")
    local xT = DUI.Pixel.Px(P.xp, DUI.Style.BorderPx(P.xp))
    P.xpGrip:GetScript("OnMouseDown")(P.xpGrip)
    P.xp:SetSize(180, 14 + 2 * xT)
    P.xpGrip:GetScript("OnMouseUp")(P.xpGrip)
    T.eq(DUI:Get("InfoPanel", "xp.width"), 180, "the new size kept")
    T.eq(DUI:Get("InfoPanel", "xp.height"), 14)
    P.xp:SetSize(5000, 1)
    P.xpGrip:GetScript("OnMouseUp")(P.xpGrip)
    T.eq(DUI:Get("InfoPanel", "xp.width"), P.XP_MAX[1], "within its limits")
    T.eq(DUI:Get("InfoPanel", "xp.height"), P.XP_MIN[2])
    DUI.Movers.Lock()
    T.falsy(P.xpGrip:IsShown())
    DUI:Set("InfoPanel", "xp.detached", false)
    DUI.Movers.Unlock()
    T.falsy(P.xpGrip:IsShown(), "locked to the panel: no grip")
end)

T.test("info panel: reset asks first, then clears every fight", function()
    local DUI = login()
    local M, area = stub.infopanel.Meter, stub.infopanel.Panel.meterArea
    area:GetScript("OnEnter")(area)
    local b = M.header.buttons.reset
    T.eq(b.kind, "reset")
    b:GetScript("OnClick")(b, "LeftButton")
    T.eq(stub.popup, "DAYLIGHTUI_METER_RESET")
    T.falsy(stub.meter.reset, "nothing cleared until confirmed")
    StaticPopupDialogs.DAYLIGHTUI_METER_RESET.OnAccept()
    T.truthy(stub.meter.reset)
    T.eq(DUI:Get("InfoPanel", "meter.session"), "current")
end)

T.test("info panel: the meter's gradient switch paints class and one-color bars", function()
    local DUI = login()
    DUI.SetTestMode(true)
    local function grad() return bars()[1].bar:GetStatusBarTexture().__gradient end
    stub.infopanel.Meter.Draw()
    T.truthy(grad(), "on by default, class mode: a gradient")
    DUI:Set("InfoPanel", "meter.barColor", "custom")
    stub.infopanel.Meter.Draw()
    T.truthy(grad(), "one color: a gradient from it")
    -- (The stub never clears a gradient on a plain color; the game does.)
end)

T.test("info panel: test mode fills the meter with a sample group", function()
    local DUI = login()
    DUI.SetTestMode(true)
    stub.infopanel.Meter.Draw()
    local first = bars()[1]
    T.truthy(first:IsShown())
    T.eq(first.bar:GetValue(), stub.infopanel.Meter.SAMPLE[1].totalAmount)
    T.eq(#stub.infopanel.Meter.SAMPLE, 20, "a raid's worth")
    -- The wheel scrolls through the rest, and stops at the end.
    local area = stub.infopanel.Panel.meterArea
    area:GetScript("OnMouseWheel")(area, -1)
    T.eq(first.bar:GetValue(), stub.infopanel.Meter.SAMPLE[2].totalAmount, "scrolled one down")
    for _ = 1, 40 do area:GetScript("OnMouseWheel")(area, -1) end
    local shown = {}
    for _, r in ipairs(bars()) do if r:IsShown() then shown[#shown + 1] = r end end
    T.eq(shown[#shown].bar:GetValue(), stub.infopanel.Meter.SAMPLE[20].totalAmount, "the last one at the bottom")
end)

T.test("info panel: the minimap moves into the panel, square, cluster hidden", function()
    login()
    local P = stub.infopanel.Panel
    T.eq(Minimap:GetParent(), P.mapArea)
    T.eq(Minimap.__mask, stub.infopanel.Minimap.MASK)
    T.eq(MinimapCluster:GetParent(), UIParent, "the cluster stays shown: hidden, the map went black")
    T.eq(MinimapCluster:GetAlpha(), 0, "see-through")
    T.eq(MinimapCluster.IndicatorFrame:GetParent(), Minimap, "mail kept, on the map")
    T.eq(Minimap.ZoomIn:GetParent(), P.hiddenParent)
    T.eq(GetMinimapShape(), "SQUARE")
    T.eq(GameTimeFrame:GetParent(), Minimap, "calendar on the map")
    T.eq(select(3, GameTimeFrame:GetPoint(1)), "TOPRIGHT", "in its top-right corner")
    T.eq(MinimapCluster.Tracking:GetParent(), Minimap, "tracking on the map")
    T.eq(select(2, MinimapCluster.Tracking:GetPoint(1)), GameTimeFrame, "under the calendar")
    DaylightUI:Set("InfoPanel", "map.buttons", false)
    stub.RunTimers()
    T.eq(GameTimeFrame:GetParent(), P.hiddenParent, "switched off: hidden")
    T.eq(MinimapCluster.Tracking:GetParent(), P.hiddenParent)
    DaylightUI:Set("InfoPanel", "map.buttons", true)
    stub.RunTimers()
    T.eq(GameTimeFrame:GetParent(), Minimap)
    T.eq(Minimap.__blob.questScalar, 0, "no round rim on quest areas")
    T.eq(Minimap.__blob.questAlpha, 0)
    T.eq(Minimap.__blob.taskScalar, 0, "or bonus-objective areas")
    -- When Edit Mode's layout moves it back, that's undone a frame later.
    -- No hook on its SetPoint: the game's protected layout code calls it,
    -- and a hook makes that call fail.
    T.isnil(rawget(Minimap, "SetPoint"), "no hook on the map's SetPoint")
    T.isnil(rawget(GameTimeFrame, "SetPoint"), "or the calendar's")
    Minimap:ClearAllPoints(); Minimap:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    stub.RunTimers()
    local _, rel = Minimap:GetPoint(1)
    T.eq(rel, P.mapArea)
end)

T.test("info panel: turning with you, the map is round (the game turns its mask with it); back to a square after", function()
    login()
    local Map = stub.infopanel.Minimap
    local P = stub.infopanel.Panel
    local size = Minimap:GetWidth()
    Minimap:SetFrameLevel(50)   -- the game's own level, before ours lowers it (in game the ring stayed up there)
    local rotate = false
    local old = GetCVarBool
    GetCVarBool = function(k) if k == "rotateMinimap" then return rotate end return old and old(k) end
    rotate = true
    stub.FireEvent("CVAR_UPDATE", "rotateMinimap", "1")
    stub.RunTimers()
    T.eq(Minimap.__mask, Map.ROUND_MASK, "a disc: the same at every angle")
    T.eq(Minimap:GetWidth(), size, "the square's size, nothing past the panel")
    T.eq(GetMinimapShape(), "ROUND")
    T.truthy(Map.ring:IsShown(), "a ring round it")
    T.eq(Map.ring:GetParent(), Minimap, "on the map, in its strata with the texts")
    T.eq(Map.ring:GetFrameStrata(), Map.location:GetFrameStrata())
    T.truthy(Map.location:GetFrameLevel() > Map.ring:GetFrameLevel(), "the zone name over the ring")
    T.truthy(Map.coords:GetFrameLevel() > Map.ring:GetFrameLevel(), "the coordinates over the ring")
    -- The N sits on the ring's band: it must draw over the ring's art, never under it.
    local order = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
    T.truthy(order[Map.ring.north:GetDrawLayer()] > order[Map.ring.tex:GetDrawLayer()], "the N over the ring")
    local oldFacing = GetPlayerFacing
    GetPlayerFacing = function() return math.pi / 2 end
    Map.ring:GetScript("OnUpdate")(Map.ring)
    local _, _, _, nx, ny = Map.ring.north:GetPoint(1)
    T.truthy(nx > 0 and math.abs(ny) < 0.01, "facing west, north is on the right")
    GetPlayerFacing = function() return nil end
    Map.ring:GetScript("OnUpdate")(Map.ring)
    T.falsy(Map.ring.north:IsShown(), "no facing, no N")
    GetPlayerFacing = oldFacing
    local _, rel = Minimap:GetPoint(1)
    T.eq(rel, P.mapArea)
    rotate = false
    stub.FireEvent("CVAR_UPDATE", "rotateMinimap", "0")
    stub.RunTimers()
    T.eq(Minimap.__mask, Map.MASK)
    T.eq(GetMinimapShape(), "SQUARE")
    T.falsy(Map.ring:IsShown(), "no ring on the square")
    GetCVarBool = old
end)

T.test("info panel: a round map without turning has its ring, N fixed at the top, nothing each frame", function()
    local DUI = login()
    local Map = stub.infopanel.Minimap
    T.eq(DUI:Get("InfoPanel", "map.shape"), "square", "square by default")
    T.eq(GetMinimapShape(), "SQUARE")
    DUI:Set("InfoPanel", "map.shape", "round")
    stub.RunTimers()
    T.eq(Minimap.__mask, Map.ROUND_MASK, "round without rotating")
    T.eq(GetMinimapShape(), "ROUND", "addons put their buttons round it")
    T.truthy(Map.ring:IsShown(), "the ring")
    T.isnil(Map.ring:GetScript("OnUpdate"), "the N never moves, so nothing runs each frame")
    T.truthy(Map.ring.north:IsShown(), "the N")
    local _, _, _, nx, ny = Map.ring.north:GetPoint(1)
    T.truthy(math.abs(nx) < 0.01 and ny > 0, "north at the top")
    -- Rotating takes over the N; switched off again, it goes back to the top.
    local rotate = true
    local old = GetCVarBool
    GetCVarBool = function(k) if k == "rotateMinimap" then return rotate end return old and old(k) end
    stub.FireEvent("CVAR_UPDATE", "rotateMinimap", "1")
    stub.RunTimers()
    T.truthy(Map.ring:GetScript("OnUpdate"), "the N follows the facing while turning")
    rotate = false
    stub.FireEvent("CVAR_UPDATE", "rotateMinimap", "0")
    stub.RunTimers()
    T.eq(Minimap.__mask, Map.ROUND_MASK, "still round: the player picked round")
    T.isnil(Map.ring:GetScript("OnUpdate"))
    GetCVarBool = old
    DUI:Set("InfoPanel", "map.shape", "square")
    stub.RunTimers()
    T.eq(Minimap.__mask, Map.MASK, "back to the square")
    T.eq(GetMinimapShape(), "SQUARE")
    T.falsy(Map.ring:IsShown(), "no ring on the square")
end)

-- The game's Hybrid Minimap, loaded on demand where the map is drawn from art
-- (dungeons). It's a child of the map filling it, fixed at BACKGROUND strata
-- level 100 under the map (whose terrain it turns off), with a black background
-- and the map art both masked by a round CircleMask 3 px in.
local function hybridMinimap()
    local h = CreateFrame("Frame", "HybridMinimap", Minimap)
    h:SetAllPoints(Minimap)
    h:SetFrameStrata("BACKGROUND")
    h:SetFrameLevel(100)
    h.Background = h:CreateTexture(nil, "BACKGROUND")
    h.CircleMask = h:CreateMaskTexture()
    h.CircleMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    h.CircleMask:SetPoint("TOPLEFT", h, "TOPLEFT", 3, -3)
    h.CircleMask:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -3, 3)
    h.MapCanvas = CreateFrame("Frame", nil, h)
    h.MapCanvas:SetFrameStrata("BACKGROUND")
    h:Hide()
    return h
end

-- Dungeon maps came up blank. The game draws them on the Hybrid Minimap, a
-- BACKGROUND frame, which ended up under the panel's own LOW background.
T.test("info panel: the game's hybrid map (dungeons) draws over the panel's background, in the map's shape", function()
    login()
    local Map = stub.infopanel.Minimap
    local P = stub.infopanel.Panel
    local h = hybridMinimap()
    stub.FireEvent("ADDON_LOADED", "Blizzard_HybridMinimap")
    stub.RunTimers()
    T.eq(h:GetFrameStrata(), Minimap:GetFrameStrata(), "in the map's strata, not under the panel")
    T.eq(h.MapCanvas:GetFrameStrata(), Minimap:GetFrameStrata(), "its map art too")
    T.truthy(h:GetFrameLevel() < Minimap:GetFrameLevel(), "under the map: your arrow and the dots draw over it")
    T.truthy(h:GetFrameLevel() >= P.mapArea:GetFrameLevel(), "over the panel's background")
    T.eq(h.CircleMask.__texture, Map.MASK, "square, as the map")
    T.eq(select(2, h.CircleMask:GetPoint(1)), h)
    T.eq(select(4, h.CircleMask:GetPoint(1)) or 0, 0, "to the edge, no 3 px rim")
    -- Turning on: the map is round, so is its art.
    local old = GetCVarBool
    GetCVarBool = function(k) if k == "rotateMinimap" then return true end return old and old(k) end
    stub.FireEvent("CVAR_UPDATE", "rotateMinimap", "1")
    stub.RunTimers()
    T.eq(h.CircleMask.__texture, Map.ROUND_MASK, "round with the map")
    GetCVarBool = old
    stub.FireEvent("CVAR_UPDATE", "rotateMinimap", "0")
    stub.RunTimers()
    T.eq(h.CircleMask.__texture, Map.MASK)
end)

T.test("info panel: a hybrid map loaded before the panel is set up is dressed at login", function()
    login(function() hybridMinimap() end)
    T.eq(HybridMinimap:GetFrameStrata(), Minimap:GetFrameStrata())
    T.eq(HybridMinimap.CircleMask.__texture, stub.infopanel.Minimap.MASK)
end)

T.test("info panel: waiting mail is an envelope of ours on the map, in and out with the game's frame", function()
    login()
    local Map = stub.infopanel.Minimap
    local mail = MinimapCluster.IndicatorFrame.MailFrame
    local d = Map.mail
    T.truthy(d, "dressed at login")
    T.eq(mail.MailIcon:GetAlpha(), 0, "the game's envelope erased")
    T.eq(d.case:GetParent(), Minimap, "ours lives on the map, to fade out after the game's hides")
    T.eq(mail:GetWidth(), stub.infopanel.Drawer.SIZE, "the game's frame the square's size")
    T.eq(d.case:GetWidth(), stub.infopanel.Drawer.SIZE)
    T.eq(d.case:GetAlpha(), 0, "no mail: nothing to see")
    mail:Show()
    T.eq(d.goal, 1, "mail comes: it fades in")
    mail:Hide()
    T.eq(d.goal, 0, "read: it fades out")
    local again = Map.DressMail(mail, Minimap)
    T.eq(again, d, "a refresh keeps the one look")
    DaylightUI:Set("general", "accent", "gradient")
    Map.DressMail(mail, Minimap)
    T.truthy(d.glyph.__gradient, "a gradient accent sweeps across the envelope")
end)

T.test("info panel: in a fight a protected map waits, the mail icon doesn't, nothing is blocked", function()
    login()
    local P = stub.infopanel.Panel
    -- The map counts as protected through a protected child. Seen in game as
    -- ADDON_ACTION_BLOCKED on its SetParent after a group change.
    stub.secure = true
    Minimap.__protected = true
    local mail = MinimapCluster.IndicatorFrame
    Minimap:ClearAllPoints(); Minimap:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    mail:ClearAllPoints(); mail:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    stub.errors = {}
    stub.combat = true
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(select(2, mail:GetPoint(1)), Minimap, "the mail icon needs no wait")
    T.eq(select(2, Minimap:GetPoint(1)), UIParent, "the map stays put in the fight")
    stub.combat = false
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    stub.RunTimers()
    T.eq(select(2, Minimap:GetPoint(1)), P.mapArea, "back on its spot after the fight")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("info panel: calendar and tracking in our square, out of sight until the mouse is over the map", function()
    login(function()
        -- The game's art: one picture each, set again on every hover and press.
        GameTimeFrame.StateTexture = GameTimeFrame:CreateTexture()
        GameTimeFrame.AddTexture = GameTimeFrame:CreateTexture()
        _G.GameTimeCalendarInvitesTexture = GameTimeFrame:CreateTexture()
        GameTimeCalendarInvitesTexture:Hide()
        local track = MinimapCluster.Tracking
        track.Background = track:CreateTexture()
        track.Button = CreateFrame("Button", nil, track)
        track.Button.StateTexture = track.Button:CreateTexture()
        track.Button.AddTexture = track.Button:CreateTexture()
    end)
    local Map, P = stub.infopanel.Minimap, stub.infopanel.Panel
    local track = MinimapCluster.Tracking
    local cal, tr = Map.Dressed(GameTimeFrame), Map.Dressed(track.Button)
    T.truthy(cal and tr, "both dressed")
    T.eq(GameTimeFrame.StateTexture:GetAlpha(), 0, "the game's picture erased")
    T.eq(track.Button.AddTexture:GetAlpha(), 0)
    T.eq(track.Background:GetAlpha(), 0, "the tracking holder's backing too")
    T.eq(GameTimeFrame:GetWidth(), stub.infopanel.Drawer.SIZE, "the drawer button's size")
    T.eq(track.Button:GetWidth(), stub.infopanel.Drawer.SIZE)
    T.eq(cal.case:GetParent(), GameTimeFrame, "our square on the game's button: its clicks stay the game's")
    local function run()
        Map.WatchButtons()
        local d = DaylightUI.Motion.Driver()
        if d then stub.RunOnUpdate(d, 1) end
    end
    P.mapArea.IsMouseOver = function() return false end
    run()
    T.eq(GameTimeFrame:GetAlpha(), 0, "out of sight at rest")
    T.eq(track:GetAlpha(), 0)
    P.mapArea.IsMouseOver = function() return true end
    run()
    T.eq(GameTimeFrame:GetAlpha(), 1, "the mouse over the map: shown")
    T.eq(track:GetAlpha(), 1)
    P.mapArea.IsMouseOver = function() return false end
    run()
    T.eq(GameTimeFrame:GetAlpha(), 0, "and gone again after")
    GameTimeCalendarInvitesTexture:Show()
    run()
    T.eq(GameTimeFrame:GetAlpha(), 1, "an invite waiting keeps the calendar shown")
    T.truthy(cal.alert, "and lit")
    T.eq(track:GetAlpha(), 0, "tracking stays away")
    P.mapArea.IsMouseOver = nil
end)

T.test("info panel: the minimap isn't zoomed at a door or after the player's own zoom (players saw it zoom in and out)", function()
    login()
    stub.RunTimers()
    Minimap.__zoomCalls = 0
    stub.FireEvent("ZONE_CHANGED_INDOORS")
    stub.FireEvent("MINIMAP_UPDATE_ZOOM")
    stub.RunTimers()
    T.eq(Minimap.__zoomCalls, 0)
    T.eq(MinimapCluster:IsShown(), true, "the game's cluster stays shown (hidden, the map went blank)")
end)

-- Seen in game: after a /reload in Stormwind (indoors, in dungeons too) the
-- map stayed empty until a scroll, while EllesmereUI's drew at once. It zooms
-- out and back in one frame after each loading screen; two of those, with the
-- map on screen, drew ours.
-- Seen in game: the redraw run once the login fade-in started (the map at 1%)
-- left it empty; with the map outside the panel, shown from the loading
-- screen on, it drew. So the map doesn't wait for the fade-in.
T.test("info panel: the minimap skips the login fade-in, so it's redrawn as the loading screen goes", function()
    stub.Load({ infopanel = true, intro = true, before = PW.world })
    local F = DaylightUI.Fade
    local P = stub.infopanel.Panel
    local queue = {}
    C_Timer.After = function(d, fn) queue[#queue + 1] = { at = GetTime() + (d or 0), fn = fn } end
    local function frames(n)
        for _ = 1, n do
            stub.Advance(1 / 60)
            F.Step()
            stub.RunOnUpdate(F.driver, 1 / 60)
            local due = queue
            queue = {}
            for _, t in ipairs(due) do
                if t.at <= GetTime() then t.fn() else queue[#queue + 1] = t end
            end
        end
    end
    T.eq(P.holder:GetAlpha(), 0, "the panel waits for the fade-in")
    T.eq(Minimap:GetEffectiveAlpha(), 1, "the map doesn't")
    Minimap.__picture, Minimap.__zoomCalls = "empty", 0
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.FireEvent("LOADING_SCREEN_DISABLED")
    frames(45)
    T.eq(Minimap.__picture, "filled", "drawn right after the loading screen")
    -- The game's own zoom as the world comes in, and the fade-in after it.
    stub.FireEvent("MINIMAP_UPDATE_ZOOM")
    for _ = 1, 15 do frames(60) end
    T.eq(P.holder:GetAlpha(), 1, "the panel came in")
    T.eq(stub.infopanel.Minimap.early, false, "the map follows the panel's fade again")
    T.eq(Minimap:GetEffectiveAlpha(), 1)
    T.eq(Minimap.__picture, "filled")
    stub.ResetTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("info panel: after a loading screen the minimap is redrawn unseen once it shows, so a city's map isn't left empty", function()
    login()
    stub.RunTimers()
    local queue = {}
    C_Timer.After = function(d, fn) queue[#queue + 1] = { at = GetTime() + (d or 0), fn = fn } end
    local function frames(n)
        for _ = 1, n do
            stub.Advance(1 / 60)
            local due = queue
            queue = {}
            for _, t in ipairs(due) do
                if t.at <= GetTime() then t.fn() else queue[#queue + 1] = t end
            end
        end
    end
    local P = stub.infopanel.Panel
    -- A /reload: the panel waits at 0 for the login fade-in.
    P.holder:SetAlpha(0)
    Minimap.__picture, Minimap.__zoomCalls = "empty", 0
    stub.FireEvent("LOADING_SCREEN_DISABLED")
    frames(120)
    T.eq(Minimap.__picture, "empty")
    T.eq(Minimap.__zoomCalls, 0, "nothing while the map can't be seen: the game would ignore it")
    P.holder:SetAlpha(0.02)
    frames(60)
    T.eq(Minimap.__picture, "empty", "barely there: the game would ignore it, so it waits")
    P.holder:SetAlpha(0.5)
    frames(60)
    T.eq(Minimap.__picture, "empty", "still see-through")
    P.holder:SetAlpha(1)
    frames(60)
    T.eq(Minimap.__picture, "filled", "drawn once the fade-in is done")
    T.eq(Minimap:GetZoom(), 2, "at the zoom it had")
    local calls = Minimap.__zoomCalls
    T.eq(calls, 4, "two zooms out and back")
    P.holder:SetAlpha(1)
    stub.FireEvent("MINIMAP_UPDATE_ZOOM")
    stub.FireEvent("ZONE_CHANGED_INDOORS")
    frames(120)
    T.eq(Minimap.__zoomCalls, calls, "once per loading screen: never after the player's zoom or at a door")
    -- No fade-in (the map already shows): right after the loading screen.
    Minimap.__picture = "empty"
    stub.FireEvent("LOADING_SCREEN_DISABLED")
    frames(60)
    T.eq(Minimap.__picture, "filled")
    stub.ResetTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: the game stops updating a see-through minimap. Players with
-- the panel at 70% walked into a hut or a cave and the map went empty, and
-- one faded out in a fight came back empty too. So the map stays solid at
-- the panel's opacity, and solid again after a fade it's redrawn.
T.test("info panel: the minimap faded out and back is redrawn, so walking indoors meanwhile doesn't leave it empty", function()
    login()
    stub.RunTimers()
    local queue = {}
    C_Timer.After = function(d, fn) queue[#queue + 1] = { at = GetTime() + (d or 0), fn = fn } end
    local F = DaylightUI.Fade
    local P = stub.infopanel.Panel
    local function frames(n)
        for _ = 1, n do
            stub.Advance(1 / 60)
            F.Step()
            stub.RunOnUpdate(F.driver, 1 / 60)
            local due = queue
            queue = {}
            for _, t in ipairs(due) do
                if t.at <= GetTime() then t.fn() else queue[#queue + 1] = t end
            end
        end
    end
    DaylightUI:Set("InfoPanel", "fade.mode", "combat")
    DaylightUI:Set("InfoPanel", "fade.delay", 0)
    DaylightUI:Set("InfoPanel", "fade.opacity", 0.7)
    frames(60)
    stub.EnterCombat()
    frames(120)
    T.eq(Minimap:GetAlpha(), 0, "faded in the fight")
    -- Into a cave while it can't be seen: the game leaves its picture empty.
    Minimap.__picture, Minimap.__zoomCalls = "empty", 0
    stub.FireEvent("ZONE_CHANGED_INDOORS")
    frames(60)
    T.eq(Minimap.__zoomCalls, 0, "nothing while it can't be seen")
    stub.LeaveCombat()
    frames(120)
    T.near(P.holder:GetAlpha(), 0.7, 0.01, "the panel back at its opacity after the fight")
    T.eq(Minimap:GetEffectiveAlpha(), 1, "the map solid: a see-through map isn't kept up to date")
    T.eq(Minimap.__picture, "filled", "and drawn")
    T.eq(Minimap:GetZoom(), 2, "at the zoom it had")
    local calls = Minimap.__zoomCalls
    stub.FireEvent("ZONE_CHANGED_INDOORS")
    frames(120)
    T.eq(Minimap.__zoomCalls, calls, "never at a door while it shows")
    stub.ResetTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("info panel: the armor figure leaves the game's right-side column and is put back after it shows", function()
    login()
    stub.RunTimers()
    local df = _G.DurabilityFrame
    -- The game's column places it from protected code (SetPoint). With a hook
    -- on it, that failed thousands of times.
    T.isnil(rawget(df, "SetPoint"), "no hook on its SetPoint")
    T.eq(df:GetParent(), UIParent, "out of the column, so the column's layouts skip it")
    local p, rel, rp, x, y = df:GetPoint(1)
    T.eq(p, "TOPRIGHT")
    -- Shown again, the game takes it back into the column.
    df:Hide()
    df:SetParent(RightManagedFrameContainer)
    df:ClearAllPoints(); df:SetPoint("TOPRIGHT", RightManagedFrameContainer, "TOPRIGHT", 0, 0)
    df:Show()
    stub.RunTimers()
    T.eq(df:GetParent(), UIParent, "out again, the frame after")
    T.eq(df:GetNumPoints(), 1)
    local p2, rel2, rp2, x2, y2 = df:GetPoint(1)
    T.eq(rel2, rel, "back at its spot"); T.eq(rp2, rp); T.eq(x2, x); T.eq(y2, y)
end)

T.test("info panel: the armor figure moved in Edit Mode stays where the player put it", function()
    login()
    stub.RunTimers()
    local df = _G.DurabilityFrame
    -- Dropped in Edit Mode, EditModeManager marks it moved
    -- (systemInfo.isInDefaultPosition = false) and places it on UIParent.
    df.systemInfo = { isInDefaultPosition = false }
    df:ClearAllPoints(); df:SetPoint("CENTER", UIParent, "CENTER", 120, -40)
    -- Leaving Edit Mode and anything showing used to pin it back.
    df:Hide(); df:Show()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    stub.RunTimers()
    local p, rel, rp, x, y = df:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(rel, UIParent); T.eq(rp, "CENTER"); T.eq(x, 120); T.eq(y, -40)
    -- Reset to its default spot in Edit Mode: under the panel again.
    df.systemInfo.isInDefaultPosition = true
    df:Hide(); df:Show()
    stub.RunTimers()
    local p2, rel2 = df:GetPoint(1)
    T.eq(p2, "TOPRIGHT"); T.isnil(rel2:GetName(), "back on the panel's spot")
end)

T.test("info panel: Edit Mode can't save one of our names for the armor figure, and old saves still find it", function()
    login()
    stub.RunTimers()
    -- Edit Mode saves the anchor's name; a nameless one saves as UIParent.
    local _, rel = _G.DurabilityFrame:GetPoint(1)
    T.isnil(rel:GetName(), "hangs from a nameless spot")
    -- A layout saved before this names the body; it's there from file load.
    T.eq(_G.DaylightUIInfoPanelBody, stub.infopanel.Panel.panel)
end)

T.test("info panel: the experience bar's own fade, attached or separate, and back to the panel's", function()
    login()
    local F = DaylightUI.Fade
    local function settle()
        F.Step()
        for _ = 1, 120 do stub.RunOnUpdate(F.driver, 1 / 60) end
    end
    local P = stub.infopanel.Panel
    local function set(k, v) DaylightUI:Set("InfoPanel", k, v) end
    local function rest() stub.Advance(3); settle() end
    set("fade.delay", 0)
    set("xp.fade.delay", 0)
    -- Off (the default): attached, a child that shows the panel's fade.
    T.falsy(P.xp:IsIgnoringParentAlpha(), "attached and no own fade: it follows the panel")
    set("xp.fade.mode", "always")
    set("xp.fade.alpha", 0.2)
    rest()
    T.eq(P.xp:GetAlpha(), 1, "its fade waits for the switch")
    -- On, attached: the bar fades alone and stays while the panel fades.
    set("xp.ownFade", true)
    rest()
    T.near(P.xp:GetAlpha(), 0.2, 0.01, "its own fade")
    T.eq(P.holder:GetAlpha(), 1, "the panel stays")
    set("xp.fade.mode", "never")
    set("fade.mode", "always")
    set("fade.alpha", 0)
    rest()
    T.eq(P.holder:GetAlpha(), 0, "the panel faded")
    T.truthy(P.xp:IsIgnoringParentAlpha(), "the bar doesn't")
    T.eq(P.xp:GetAlpha(), 1, "and stays shown")
    -- Separate, the same, then the switch off hands it to the panel's fade.
    set("xp.detached", true)
    rest()
    T.eq(P.xp:GetAlpha(), 1, "separate: still its own")
    set("xp.ownFade", false)
    rest()
    T.eq(P.xp:GetAlpha(), 0, "switch off: separate, on the panel's fade")
    set("xp.detached", false)
    rest()
    T.eq(P.xp:GetAlpha(), 1, "attached again: no alpha left over from the panel's fade")
    T.eq(P.holder:GetAlpha(), 0, "it shows the panel's")
    T.falsy(P.xp:IsIgnoringParentAlpha())
    -- Float: an XP gain brings the bar back; the options list its rows.
    set("fade.mode", "never")
    set("xp.ownFade", true)
    set("xp.fade.mode", "float")
    rest()
    T.near(P.xp:GetAlpha(), 0.2, 0.01, "float: down to its faded opacity")
    stub.FireEvent("PLAYER_XP_UPDATE", "player")
    settle()
    T.eq(P.xp:GetAlpha(), 1, "float: back on a gain")
end)

T.test("info panel: faded out, the minimap goes see-through, never hidden (its icons can't fade with the panel)", function()
    login()
    -- Hidden and shown again, the game's map lost its picture (blank at login
    -- and after talking to an NPC in town). Only its alpha changes now.
    local hides = 0
    local hide = Minimap.Hide
    Minimap.Hide = function(self) hides = hides + 1; return hide(self) end
    local F = DaylightUI.Fade
    local function settle()
        F.Step()
        for _ = 1, 120 do stub.RunOnUpdate(F.driver, 1 / 60) end
    end
    local P = stub.infopanel.Panel
    DaylightUI:Set("InfoPanel", "fade.mode", "ooc")
    DaylightUI:Set("InfoPanel", "fade.delay", 0)
    stub.Advance(3)
    settle()
    T.eq(P.holder:GetAlpha(), 0, "panel faded")
    T.eq(Minimap:GetAlpha(), 0, "faded: map hidden")
    stub.EnterCombat()
    settle()
    T.eq(Minimap:GetAlpha(), 1, "in a fight: map back")
    stub.LeaveCombat()
    stub.Advance(3)
    settle()
    T.eq(Minimap:GetAlpha(), 0, "faded again")
    DaylightUI:Set("InfoPanel", "fade.mode", "never")
    stub.Advance(3)
    settle()
    T.eq(Minimap:GetAlpha(), 1, "option off: map back")
    -- Faded only part way, the panel still shows: so does the map.
    DaylightUI:Set("InfoPanel", "fade.mode", "ooc")
    DaylightUI:Set("InfoPanel", "fade.alpha", 0.3)
    stub.Advance(3)
    settle()
    T.near(P.holder:GetAlpha(), 0.3, 0.01, "panel part faded")
    T.near(Minimap:GetAlpha(), 0.3, 0.01, "part faded: the map fades with it")
    -- Opacity 0: gone for good, the map's icons too.
    DaylightUI:Set("InfoPanel", "fade.mode", "never")
    DaylightUI:Set("InfoPanel", "fade.opacity", 0)
    stub.Advance(3)
    settle()
    T.eq(P.holder:GetAlpha(), 0, "opacity 0: panel gone")
    T.eq(Minimap:GetAlpha(), 0, "opacity 0: map hidden")
    DaylightUI:Set("InfoPanel", "fade.opacity", 1)
    stub.Advance(3)
    settle()
    T.eq(Minimap:GetAlpha(), 1, "opacity back up: map back")
    -- A hush (sitting at the campfire) takes it to 0 too: the map's icons go with it.
    F.Hush("test", { "InfoPanel." })
    for _ = 1, 20 do stub.Advance(0.5); settle() end
    T.eq(P.holder:GetAlpha(), 0, "hushed: panel gone")
    T.eq(Minimap:GetAlpha(), 0, "hushed: map hidden")
    F.Unhush("test", true)
    settle()
    T.eq(Minimap:GetAlpha(), 1, "hush lifted: map back")
    Minimap.Hide = hide
    T.eq(hides, 0, "the map is never hidden")
    T.truthy(Minimap:IsShown())
end)

T.test("info panel: old fade settings move to the fade engine", function()
    local p = { general = { oocAlpha = 0.2 },
                modules = { InfoPanel = { fadeOOC = true, tracker = { fadeOOC = true, oocAlpha = 0.5 } } } }
    local DUI = stub.Load()
    DUI.FadeUpgrade.Run(p)
    local ip = p.modules.InfoPanel
    T.eq(ip.fade.mode, "ooc"); T.eq(ip.fade.alpha, 0.2, "General's opacity")
    T.eq(ip.tracker.fade.mode, "ooc"); T.eq(ip.tracker.fade.alpha, 0.5)
    T.isnil(ip.fadeOOC); T.isnil(ip.tracker.fadeOOC)
end)

T.test("info panel: minimap clock shows local or server time, 12/24-hour", function()
    login()
    stub.SetTime(os.time({ year = 2024, month = 1, day = 1, hour = 15, min = 5, sec = 0 }))
    stub.SetGameTime(3, 9)
    local Map = stub.infopanel.Minimap
    Map.UpdateClock()
    T.eq(Map.clock.text:GetText(), "15:05", "24-hour local by default")
    DaylightUI:Set("InfoPanel", "map.clock.useServer", true)
    T.eq(Map.clock.text:GetText(), "03:09", "server time once switched on")
    DaylightUI:Set("InfoPanel", "map.clock.twentyFour", false)
    T.eq(Map.clock.text:GetText(), "3:09 AM")
    DaylightUI:Set("InfoPanel", "map.clock.enabled", false)
    T.truthy(not Map.clock:IsShown())
end)

T.test("info panel: the minimap's rotate switch is the game's own rotateMinimap setting", function()
    login()
    local item
    for _, page in ipairs(stub.infopanel.OPTIONS.pages) do
        for _, g in ipairs(page.groups) do
            for _, it in ipairs(g.items) do
                if it.label == "Rotate as you turn" then item = it end
            end
        end
    end
    T.truthy(item, "on the Minimap page")
    _G.GetCVarBool = function(k) return stub.cvars ~= nil and stub.cvars[k] == "1" end
    local redrawn = 0
    DaylightUI.On("SettingChanged", function() redrawn = redrawn + 1 end)
    T.eq(item.get(), false, "off by default")
    item.set(true)
    T.eq(stub.cvars.rotateMinimap, "1")
    T.eq(item.get(), true)
    T.truthy(redrawn > 0, "the options window redraws, so the switch slides")
    item.set(false)
    T.eq(stub.cvars.rotateMinimap, "0")
    _G.GetCVarBool = nil
end)

T.test("info panel: coordinates at the top of the map, blank without a position", function()
    login()
    local x, y = 0.4523, 0.618
    _G.C_Map = {
        GetBestMapForUnit = function() return 1429 end,
        GetPlayerMapPosition = function() if x then return { GetXY = function() return x, y end } end end,
    }
    local Map = stub.infopanel.Minimap
    Map.UpdateCoords()
    T.eq(Map.coords.text:GetText(), "45.2, 61.8")
    T.truthy(Map.coords:IsShown(), "on by default")
    x = nil
    Map.UpdateCoords()
    T.eq(Map.coords.text:GetText(), "", "blank in an instance")
    DaylightUI:Set("InfoPanel", "map.coords.enabled", false)
    T.truthy(not Map.coords:IsShown(), "off once switched off")
    _G.C_Map = nil
end)

T.test("info panel: location at the top of the map, coordinates under it", function()
    login()
    local zone = "Goldshire"
    _G.GetMinimapZoneText = function() return zone end
    local Map = stub.infopanel.Minimap
    Map.UpdateLocation()
    T.eq(Map.location.text:GetText(), "Goldshire")
    T.truthy(Map.location:IsShown(), "on by default")
    local _, rel = Map.coords:GetPoint(1)
    T.eq(rel, Map.location, "coordinates hang under the location")
    zone = "Elwynn Forest"
    stub.FireEvent("ZONE_CHANGED")
    T.eq(Map.location.text:GetText(), "Elwynn Forest", "follows the zone")
    DaylightUI:Set("InfoPanel", "map.location.enabled", false)
    T.truthy(not Map.location:IsShown(), "off once switched off")
    _, rel = Map.coords:GetPoint(1)
    T.eq(rel, Minimap, "coordinates move up to the top")
    _G.GetMinimapZoneText = nil
end)

T.test("info panel: framerate beside the clock, with an on switch", function()
    login()
    _G.GetFramerate = function() return 129.6 end
    local Map = stub.infopanel.Minimap
    T.truthy(not Map.fps:IsShown(), "off by default (the data strip shows it)")
    DaylightUI:Set("InfoPanel", "map.fps.enabled", true)
    Map.UpdateFps()
    T.eq(Map.fps.text:GetText(), "130 fps")
    T.truthy(Map.fps:IsShown(), "on once switched on")
    DaylightUI:Set("InfoPanel", "map.fps.enabled", false)
    T.truthy(not Map.fps:IsShown(), "off once switched off")
    T.truthy(Map.clock:IsShown(), "clock stays")
    local p, rel, rp, x = Map.clock:GetPoint(1)
    T.eq(p, "BOTTOM", "the clock alone sits in the middle")
    T.eq(rel, Minimap)
    T.eq(rp, "BOTTOM")
    T.eq(x, 0)
    T.eq(Map.clock:GetNumPoints(), 1)
    T.eq(Map.clock.text:GetJustifyH(), "CENTER")
    _G.GetFramerate = nil
end)

T.test("info panel: clock and framerate text sizes", function()
    login()
    local Map = stub.infopanel.Minimap
    local function size(fs) return select(2, fs:GetFont()) end
    T.eq(size(Map.clock.text), 11, "clock 11 by default")
    T.eq(size(Map.fps.text), 11, "framerate 11 by default")
    DaylightUI:Set("InfoPanel", "map.clock.textSize", 16)
    DaylightUI:Set("InfoPanel", "map.fps.textSize", 9)
    T.eq(size(Map.clock.text), 16, "clock follows its slider")
    T.eq(size(Map.fps.text), 9, "framerate follows its own")
    T.eq(Map.clock:GetHeight(), 17, "the clock's frame grows with it")
    T.truthy(Map.clock:GetWidth() > 70, "and widens")
end)

T.test("info panel: the framerate tooltip opens at the mouse and follows it", function()
    login()
    _G.GetFramerate = function() return 60 end
    local Map = stub.infopanel.Minimap
    Map.UpdateFps()
    local f, off = Map.fps, Map.FPS_CURSOR
    T.truthy(f.__duiOwnTooltipSpot, "the Tooltip module leaves it be")
    function GameTooltip:IsOwned(o) return o == f end
    local s = GameTooltip:GetEffectiveScale()
    stub.cursorPos = { 300, 900 }               -- top half of the screen
    f:GetScript("OnEnter")(f)
    local point, _, _, x, y = GameTooltip:GetPoint(1)
    T.eq(point, "TOPLEFT", "grows down from the mouse")
    T.eq(x, 300 / s + off.x)
    T.eq(y, 900 / s - off.down)
    stub.cursorPos = { 310, 900 }
    f:GetScript("OnUpdate")(f, 0.02)
    T.eq((select(4, GameTooltip:GetPoint(1))), 310 / s + off.x, "follows the mouse")
    f:GetScript("OnLeave")(f)
    T.falsy(f:GetScript("OnUpdate"), "stops once the mouse leaves")
    stub.cursorPos = { 300, 100 }               -- minimap moved to the bottom
    f:GetScript("OnEnter")(f)
    point, _, _, _, y = GameTooltip:GetPoint(1)
    T.eq(point, "BOTTOMLEFT", "grows up near the bottom")
    T.eq(y, 100 / s + off.up)
    f:GetScript("OnLeave")(f)
    _G.GetFramerate = nil
end)

-- Runs the drawer's opening or closing to its end.
local function settleDrawer(D)
    for _ = 1, 100 do
        if not D.driver:GetScript("OnUpdate") then return end
        stub.RunOnUpdate(D.driver, 0.05)
    end
end

T.test("info panel: addon minimap buttons go in a drawer in the map's corner", function()
    login()
    local D, P = stub.infopanel.Drawer, stub.infopanel.Panel
    T.truthy(not D.glyph:IsShown(), "no addon buttons yet: no corner button")
    -- A LibDBIcon-style button, the way addons make them.
    local btn = CreateFrame("Button", "LibDBIcon10_Test", Minimap)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.border = btn:CreateTexture(nil, "OVERLAY")
    D.Collect()
    T.truthy(D.glyph:IsShown(), "a button found: the corner button shows")
    T.eq(btn:GetParent(), D.CellOf(btn), "the addon's button is in its square in the drawer")
    T.eq(btn.border:GetAlpha(), 0, "its round ring is gone")
    T.eq(GameTimeFrame:GetParent(), Minimap, "the calendar stays on the map")
    -- Everything inside the map: nothing hangs below the panel onto the
    -- quest tracker.
    for _, f in ipairs({ D.glyph, D.strip }) do
        local point, rel, relPoint = f:GetPoint(1)
        T.eq(point, "BOTTOMRIGHT"); T.eq(rel, P.mapArea); T.eq(relPoint, "BOTTOMRIGHT", "in the map's corner")
    end
    T.truthy(not D.strip:IsShown(), "closed at first")
    D.Toggle()
    T.truthy(D.strip:IsShown(), "open")
    settleDrawer(D)
    T.eq(D.CellOf(btn):GetAlpha(), 1, "its square has faded in")
    -- No hooks on the button's Show/Hide/SetPoint. The game's own map buttons
    -- land in the drawer too, and the game calls those from protected code
    -- ("attempt to call a nil value").
    T.isnil(rawget(btn, "Show"), "no hook on its Show")
    T.isnil(rawget(btn, "Hide"), "or its Hide")
    T.isnil(rawget(btn, "SetPoint"), "or its SetPoint")
    local other = CreateFrame("Button", "LibDBIcon10_Other", Minimap)
    D.Collect()
    other:Hide()
    T.eq(#D.Shown(), 1, "a button hiding re-packs the grid")
    other:Show()
    T.eq(#D.Shown(), 2, "and showing again")
    D.Toggle()
    settleDrawer(D)
    T.truthy(not D.strip:IsShown(), "closed again")
    btn:ClearAllPoints(); btn:SetPoint("CENTER", Minimap, "CENTER", 0, 0)   -- the addon moves it back
    D.Toggle()
    T.eq(btn:GetNumPoints(), 1); T.eq(select(2, btn:GetPoint(1)), D.CellOf(btn), "back in the drawer as it opens")
    D.Close(true)
    DaylightUI:Set("InfoPanel", "map.drawer", false)
    T.truthy(not D.glyph:IsShown(), "option off: no corner button")
end)

T.test("info panel: an addon's button made late goes in the drawer without opening it", function()
    login()
    local D = stub.infopanel.Drawer
    stub.RunTimers()
    -- Made long after login (an addon that waits, or one loaded on demand),
    -- it still must not sit on the map until the drawer opens.
    local btn = CreateFrame("Button", "LateAddonMinimapButton", Minimap)
    btn:SetScript("OnClick", function() end)
    btn:SetWidth(32)
    D.Watch()
    T.eq(btn:GetParent(), D.CellOf(btn), "picked up on the next look for the mouse")
    T.falsy(D.IsOpen(), "the drawer stays closed")
    DaylightUI:Set("InfoPanel", "map.drawer", false)
end)

T.test("info panel: an unnamed minimap button wearing the ring goes in the drawer", function()
    login()
    local D = stub.infopanel.Drawer
    local btn = CreateFrame("Button", nil, Minimap)
    local ring = btn:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(136430)
    D.Collect()
    T.eq(btn:GetParent(), D.CellOf(btn), "in its square, though it has no name")
    T.eq(ring:GetAlpha(), 0, "its ring is gone")
    -- An unnamed button without the ring is something else: left alone.
    local plainBtn = CreateFrame("Button", nil, Minimap)
    D.Collect()
    T.eq(plainBtn:GetParent(), Minimap, "a plain unnamed button stays on the map")
    DaylightUI:Set("InfoPanel", "map.drawer", false)
end)

T.test("info panel: map pins (Questie, HandyNotes) stay on the map, out of the drawer", function()
    -- HereBeDragons-Pins parents every pin to the Minimap and keeps it there,
    -- hidden, after its addon removes it. Questie ships it renamed as
    -- "HereBeDragonsQuestie-Pins-2.0".
    local hbd = { minimapPins = {}, activeMinimapPins = {} }
    local libs = { ["HereBeDragonsQuestie-Pins-2.0"] = hbd, Other = {} }
    _G.LibStub = setmetatable({
        libs = libs,
        IterateLibraries = function(self) return pairs(self.libs) end,
    }, { __call = function(self, name) return self.libs[name] end })
    login()
    local D = stub.infopanel.Drawer
    local pin = CreateFrame("Button", "QuestieFrame1", Minimap)
    hbd.minimapPins[pin] = {}; hbd.activeMinimapPins[pin] = {}
    local gone = CreateFrame("Button", "QuestieFrame2", Minimap)
    gone:Hide()
    D.Collect()
    _G.LibStub = nil
    T.eq(pin:GetParent(), Minimap, "a pin on the map stays a pin")
    T.eq(gone:GetParent(), Minimap, "a hidden one (a removed pin) is left alone too")
    T.isnil(D.CellOf(pin)); T.isnil(D.CellOf(gone))
    DaylightUI:Set("InfoPanel", "map.drawer", false)
end)

-- Questie adds pins as you move, so the map's child count changes and the
-- drawer looks again several times a second. Walking every library for every
-- child made each look about 11 ms in a profile.
T.test("info panel: one look over a map full of pins walks the libraries once", function()
    local hbd = { minimapPins = {}, activeMinimapPins = {} }
    local libs = { ["HereBeDragonsQuestie-Pins-2.0"] = hbd }
    for i = 1, 30 do libs["Lib" .. i] = {} end
    local walks = 0
    _G.LibStub = setmetatable({
        libs = libs,
        IterateLibraries = function(self) walks = walks + 1; return pairs(self.libs) end,
    }, { __call = function(self, name) return self.libs[name] end })
    login()
    local D = stub.infopanel.Drawer
    local pins = {}
    for i = 1, 200 do
        local pin = CreateFrame("Button", "QuestieFrame" .. i, Minimap)
        if i % 2 == 0 then pin:Hide() end
        hbd.minimapPins[pin] = {}
        pins[i] = pin
    end
    -- A pin wearing the ring is still a pin.
    local ringPin = CreateFrame("Button", "SomePin", Minimap)
    ringPin:CreateTexture(nil, "ARTWORK"):SetTexture(136430)
    hbd.minimapPins[ringPin] = {}
    local real = CreateFrame("Button", "LibDBIcon10_Questie", Minimap)
    walks = 0
    D.Collect()
    local counted = walks
    _G.LibStub = nil
    T.truthy(counted <= 1, "libraries walked " .. counted .. " times")
    T.eq(real:GetParent(), D.CellOf(real), "the real button still goes in")
    T.eq(ringPin:GetParent(), Minimap, "a pin with the ring stays a pin")
    T.eq(pins[1]:GetParent(), Minimap, "pins stay on the map")
    DaylightUI:Set("InfoPanel", "map.drawer", false)
end)

-- The game's addon compartment, with entries as addons register them.
local compartment
local function withCompartment()
    local cluster = MinimapCluster
    local f = CreateFrame("Button", "AddonCompartmentFrame", cluster)
    compartment = { clicks = {} }
    f.registeredAddons = {
        { text = "|cffff8800Zeta|r Tools", icon = "Interface\\Icons\\Zeta",
          func = function(_, input) compartment.clicks[#compartment.clicks + 1] = input.buttonName end },
        { text = "Alpha", func = function() end },
        { text = "Test", func = function() end },      -- also has a LibDBIcon button
    }
end

local function shownIn(D)
    local seen = {}
    for _, thing in ipairs(D.Items()) do seen[thing] = true end
    return seen
end

-- The client returns children on Lua's stack, which holds about 8000 values.
-- Past that GetChildren fails with "stack overflow". Addons' map pins all sit
-- on the map and stay there, so a player's map can get that big.
T.test("info panel: a map crowded with pins can't overflow the drawer's look, and it still finds buttons", function()
    login()
    local D = stub.infopanel.Drawer
    Minimap.GetNumChildren = function() return 9000 end
    Minimap.GetChildren = function() error("stack overflow") end
    -- The client's locked aura buttons refuse every method; the walk meets them.
    local locked = CreateFrame("Frame")
    locked.GetParent = function() error("bad self") end
    local btn = CreateFrame("Button", "LibDBIcon10_Crowded", Minimap)
    btn:SetScript("OnClick", function() end)
    local ok, err = pcall(D.Collect)
    T.truthy(ok, err)
    T.eq(btn:GetParent(), D.CellOf(btn), "the button is in the drawer all the same")
    -- The count wobbles as pins come and go. That must not trigger a walk of
    -- every frame ten times a second.
    local walks, walk = 0, _G.EnumerateFrames
    _G.EnumerateFrames = function(prev)
        if prev == nil then walks = walks + 1 end
        return walk(prev)
    end
    Minimap.GetNumChildren = function() return 9001 end
    D.Watch()
    D.Watch()
    _G.EnumerateFrames = walk
    Minimap.GetNumChildren, Minimap.GetChildren = nil, nil
    T.eq(walks, 0, "the watcher leaves a crowded map alone")
end)

T.test("info panel: the game's addon menu is one square in the drawer, its entries never squares", function()
    login(withCompartment)
    local D = stub.infopanel.Drawer
    T.truthy(AddonCompartmentFrame:GetParent() ~= Minimap, "the game's compartment button is off the map")
    local reg = AddonCompartmentFrame.registeredAddons
    -- The same addon in both lists, however it's named, gets one square.
    reg[#reg + 1] = { text = "Dungeon Journal Classic", icon = 134401, func = function() end }
    local btn = CreateFrame("Button", "LibDBIcon10_DungeonJournal", Minimap)
    local other = CreateFrame("Button", "LibDBIcon10_Test", Minimap)
    D.Collect()
    local items = D.Items()
    T.eq(#items, 3, "two buttons and the menu's square")
    T.eq(items[1], btn, "buttons by name"); T.eq(items[2], other)
    local more = items[3]
    T.eq(more, D.more, "the menu's square last")
    for _, data in ipairs(reg) do T.isnil(D.CellOf(data), "no square for an entry") end
    -- Its menu: the game's entries in the game's order, without their colors.
    local b = more.button
    b:GetScript("OnClick")(b, "LeftButton")
    local W = DaylightUI.Widgets
    T.eq(W.menuOwner, b, "the menu is open")
    T.eq(W.MenuRow(1).text:GetText(), "Alpha")
    T.eq(W.MenuRow(4).text:GetText(), "Zeta Tools")
    W.MenuRow(4):GetScript("OnClick")(W.MenuRow(4))
    T.eq(compartment.clicks[1], "LeftButton", "picked: the entry's own function runs with the mouse button")
    DaylightUI:Set("InfoPanel", "map.drawer", false)
    T.eq(AddonCompartmentFrame:GetParent(), Minimap, "drawer off: the game's compartment is back on the map")
end)

T.test("info panel: the drawer stays open while its addon menu is", function()
    login(withCompartment)
    local D = stub.infopanel.Drawer
    D.Collect()
    D.Toggle()
    local b = D.more.button
    b:GetScript("OnClick")(b, "LeftButton")
    stub.Advance(D.LINGER + 1)
    D.Watch()
    T.truthy(D.IsOpen(), "not folded away under the menu")
    DaylightUI.Widgets.CloseMenu()
    stub.Advance(D.LINGER + 1)
    D.Watch()
    T.falsy(D.IsOpen(), "closes after")
    DaylightUI:Set("InfoPanel", "map.drawer", false)
end)

T.test("info panel: a drawer square dragged along the strip takes its new place, kept", function()
    login(withCompartment)
    local D = stub.infopanel.Drawer
    -- Addons' buttons drag round the map: they carry a drag script.
    local function addonButton(name)
        local b = CreateFrame("Button", "LibDBIcon10_" .. name, Minimap)
        b:SetScript("OnDragStart", function() end)
        return b
    end
    local a, b = addonButton("Alpha"), addonButton("Beta")
    D.Collect()
    D.Toggle()
    settleDrawer(D)
    T.eq(D.Items()[1], a); T.eq(D.Items()[2], b); T.eq(D.Items()[3], D.more, "by name, the menu last")
    -- The fake game has no layout: the strip's corner at (500, 100).
    D.clip.GetRight = function() return 500 end
    D.clip.GetBottom = function() return 100 end
    local cellA = D.CellOf(a)
    stub.cursorPos = { 500 + cellA.x - 10, 100 + cellA.y + 10 }
    a:GetScript("OnDragStart")(a, "LeftButton")
    T.truthy(D.Dragging(), "picked up")
    -- Over the menu's square, the far end.
    local more = D.CellOf(D.more)
    stub.cursorPos = { 500 + more.x - 10, 100 + more.y + 10 }
    stub.RunOnUpdate(D.dragger, 0.02)
    T.eq(cellA.x, more.x, "it follows the mouse")
    stub.Advance(D.LINGER + 1)
    D.Watch()
    T.truthy(D.IsOpen(), "stays open while dragging")
    a:GetScript("OnDragStop")(a)
    T.falsy(D.Dragging())
    T.eq(D.Items()[1], b); T.eq(D.Items()[2], D.more); T.eq(D.Items()[3], a, "dropped at the end")
    local saved = DaylightUI:Get("InfoPanel", "map.drawerOrder")
    T.eq(saved[1], "Beta"); T.eq(saved[2], D.MENU_KEY); T.eq(saved[3], "Alpha", "the order is saved")
    -- A new addon goes after the player's order, and the order outlives a re-lay out.
    local c = addonButton("Aardvark")
    D.Collect()
    T.eq(D.Items()[3], a); T.eq(D.Items()[4], c, "unsaved ones after")
    D.Close(true)
    DaylightUI:Set("InfoPanel", "map.drawer", false)
end)

T.test("info panel: with nothing on the game's addon menu there is no square for it", function()
    login()
    local D = stub.infopanel.Drawer
    local btn = CreateFrame("Button", "LibDBIcon10_Test", Minimap)
    D.Collect()
    T.eq(#D.Items(), 1); T.eq(D.Items()[1], btn)
    DaylightUI:Set("InfoPanel", "map.drawer", false)
end)

T.test("info panel: a button that isn't one stays on the map", function()
    local hbd = { minimapPins = {}, activeMinimapPins = {} }
    _G.LibStub = setmetatable({
        libs = { Pins = hbd },
        IterateLibraries = function(self) return pairs(self.libs) end,
    }, { __call = function(self, name) return self.libs[name] end })
    login()
    local D = stub.infopanel.Drawer
    -- A pin wearing the ring's art.
    local ringPin = CreateFrame("Button", "SomePin", Minimap)
    ringPin:CreateTexture(nil, "ARTWORK"):SetTexture(136430)
    hbd.minimapPins[ringPin] = {}
    -- A pooled frame shown between pins. Its addon reuses it before the
    -- library knows, so the library doesn't list it for that moment.
    local pooled = CreateFrame("Button", "QuestieFrame12", Minimap)
    pooled:SetScript("OnClick", function() end)
    -- A pin by its name, no number, no library.
    local named = CreateFrame("Button", "HandyNotesThing", Minimap)
    named:SetScript("OnClick", function() end)
    named:SetWidth(24)
    -- Something shown with no click at all, and something pin sized.
    local inert = CreateFrame("Button", "SomeMapDecoration", Minimap)
    inert:SetWidth(24)
    local small = CreateFrame("Button", "SomeMapDot", Minimap)
    small:SetScript("OnClick", function() end)
    small:SetWidth(12)
    -- Questie's real button, though the pin names start with Questie.
    local real = CreateFrame("Button", "LibDBIcon10_Questie", Minimap)
    D.Collect()
    _G.LibStub = nil
    T.eq(ringPin:GetParent(), Minimap, "a pin is a pin, whatever it wears")
    T.eq(pooled:GetParent(), Minimap, "a numbered pool frame stays on the map")
    T.eq(named:GetParent(), Minimap, "a pin addon's name stays on the map")
    T.eq(inert:GetParent(), Minimap, "nothing to click: no button")
    T.eq(small:GetParent(), Minimap, "pin sized: no button")
    T.eq(real:GetParent(), D.CellOf(real), "an addon's real button goes in, whatever it's called")
    DaylightUI:Set("InfoPanel", "map.drawer", false)
end)

T.test("info panel: the drawer ripples open from the corner and closes after the mouse leaves", function()
    login(withCompartment)
    local D, P = stub.infopanel.Drawer, stub.infopanel.Panel
    CreateFrame("Button", "LibDBIcon10_First", Minimap)
    CreateFrame("Button", "LibDBIcon10_Second", Minimap)
    D.Collect()
    D.Open()
    stub.RunOnUpdate(D.driver, 0.06)
    local items = D.Items()
    local first, last = D.CellOf(items[1]):GetAlpha(), D.CellOf(items[#items]):GetAlpha()
    T.truthy(first > last, "the square nearest the corner comes in first")
    T.truthy(D.strip:GetWidth() < 2 * D.PAD + 4 * D.SIZE + 3 * D.GAP, "the strip is still sweeping out")
    settleDrawer(D)
    T.near(D.strip:GetWidth(), 2 * D.PAD + 4 * D.SIZE + 3 * D.GAP, 1e-6, "open: the corner button and three squares")
    -- The mouse on the map keeps it open; a moment after it leaves, it closes.
    P.mapArea.IsMouseOver = function() return true end
    D.Watch()
    P.mapArea.IsMouseOver = function() return false end
    stub.Advance(0.5); D.Watch()
    T.truthy(D.IsOpen(), "still open half a second later")
    stub.Advance(0.6); D.Watch()
    T.falsy(D.IsOpen(), "closed once the mouse has been away a second")
    settleDrawer(D)
    T.truthy(not D.strip:IsShown(), "and out of sight")
    -- Motion off: it snaps.
    DaylightUI.DB.General().motion = false
    D.Open()
    T.isnil(D.driver:GetScript("OnUpdate"), "motion off: no animation")
    T.eq(D.CellOf(items[#items]):GetAlpha(), 1, "every square there at once")
    DaylightUI.DB.General().motion = true
end)

T.test("info panel: pressing a LibDBIcon button in the drawer doesn't error", function()
    login()
    local D = stub.infopanel.Drawer
    -- LibDBIcon's press handler reads the data from the icon's parent.
    local btn = CreateFrame("Button", "LibDBIcon10_Press", Minimap)
    btn.dataObject = {}
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon.UpdateCoord = function(self)
        local coords = self:GetParent().dataObject.iconCoords or { 0, 1, 0, 1 }
        self:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    end
    D.Collect()
    T.truthy(pcall(btn.icon.UpdateCoord, btn.icon), "press: no error")
    DaylightUI:Set("InfoPanel", "map.drawer", false)
    T.truthy(not D.glyph:IsShown(), "option off: no corner button")
end)

T.test("info panel: a button with a masked icon goes in the drawer square, without an error", function()
    login()
    local D = stub.infopanel.Drawer
    local btn = CreateFrame("Button", "LibDBIcon10_Masked", Minimap)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon = icon
    icon:AddMaskTexture(btn:CreateMaskTexture())
    -- The client's rule as seen in game, on this icon only.
    function icon:GetNumMaskTextures() return #(self.__masks or {}) end
    function icon:GetMaskTexture(i) return (self.__masks or {})[i] end
    local setCoord = icon.SetTexCoord
    function icon:SetTexCoord(...)
        if self:GetNumMaskTextures() > 0 then
            error("Texture:SetTextCoord(): Cannot set tex coords when texture has mask.")
        end
        return setCoord(self, ...)
    end
    D.Collect()
    T.eq(btn:GetParent(), D.CellOf(btn), "it's in its square")
    T.eq(icon:GetNumMaskTextures(), 0, "its round mask is gone")
    local left, right = icon:GetTexCoord()
    T.eq(left, D.CROP[1], "the icon is cropped")
    T.eq(right, D.CROP[2])
end)

T.test("info panel: a button whose icon has an old SetMask mask goes in the drawer, without an error", function()
    login()
    local D = stub.infopanel.Drawer
    local btn = CreateFrame("Button", "LibDBIcon10_OldMask", Minimap)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon = icon
    -- The client's rule: a SetMask mask isn't counted by GetNumMaskTextures,
    -- and still refuses tex coords.
    function icon:GetNumMaskTextures() return 0 end
    function icon:GetMaskTexture() return nil end
    function icon:SetMask(file) self.__oldMask = file end
    local setCoord = icon.SetTexCoord
    function icon:SetTexCoord(...)
        if self.__oldMask then
            error("Texture:SetTextCoord(): Cannot set tex coords when texture has mask.")
        end
        return setCoord(self, ...)
    end
    icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    D.Collect()
    T.eq(btn:GetParent(), D.CellOf(btn), "it's in its square")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    if icon.UpdateCoord then icon:UpdateCoord() end
    T.eq(#stub.errors, 0, "a press keeps working: " .. tostring(stub.errors[1]))
end)

T.test("info panel: the meter and the map are as far apart as each is from the edge", function()
    login()
    local P = stub.infopanel.Panel
    local border = DaylightUI.Pixel.Px(P.panel, DaylightUI.Style.BorderPx(P.panel))
    local edge = border + P.PAD
    local m = DaylightUI:Get("InfoPanel", "meter.width")
    T.near(P.holder:GetWidth(), 3 * edge + m + P.mapSize, 1e-6, "edge, meter, gap, map, edge")
end)

T.test("info panel: the meter's bars in one color, at a text size", function()
    local DUI = login()
    local M = stub.infopanel.Meter
    DUI:Set("InfoPanel", "meter.gradient", false)
    DUI:Set("InfoPanel", "meter.barColor", "custom")
    DUI:Set("InfoPanel", "meter.barCustom", { 0, 0, 1 })
    DUI:Set("InfoPanel", "meter.textSize", 14)
    stub.meter.sources = { { name = "Sigzil", classFilename = "MAGE", totalAmount = 2640, amountPerSecond = 335 } }
    M.Draw()
    T.rgb(bars()[1].bar.__barColor, { DaylightUI.Style.Soften(0, 0, 1) })
    T.eq(bars()[1].name.__font[2], 14)
end)

T.test("info panel: the meter's names are white, or the chosen color", function()
    local DUI = login()
    local M = stub.infopanel.Meter
    stub.meter.sources = { { name = "Sigzil", classFilename = "MAGE", totalAmount = 2640, amountPerSecond = 335 } }
    M.Draw()
    T.rgb(bars()[1].name.__textColor, { 1, 1, 1 }, "white by default")
    DUI:Set("InfoPanel", "meter.nameColor", { 1, 0.5, 0 })
    M.Draw()
    T.rgb(bars()[1].name.__textColor, { 1, 0.5, 0 })
end)

T.test("info panel: the meter's names and numbers in class colors, bars with no background", function()
    local DUI = login()
    local M, Style = stub.infopanel.Meter, DUI.Style
    stub.meter.sources = { { name = "Sigzil", classFilename = "MAGE", totalAmount = 2640 } }
    DUI:Set("InfoPanel", "meter.classText", true)
    M.Draw()
    local row = bars()[1]
    T.rgb(row.name.__textColor, { Style.ClassTextColor("MAGE") }, "the name in its class color")
    T.rgb(row.amount.__textColor, { Style.ClassTextColor("MAGE") }, "the number too")
    DUI:Set("InfoPanel", "meter.classText", false)
    M.Draw()
    T.rgb(row.amount.__textColor, Style.INK.VALUE, "the number white again")
    T.eq(Style.BarBack(row.bar):GetAlpha(), 1, "solid at first")
    DUI:Set("InfoPanel", "meter.trackAlpha", 0)
    row = bars()[1]
    T.eq(Style.BarBack(row.bar):GetAlpha(), 0, "the empty part gone")
    DUI:Set("InfoPanel", "meter.trackAlpha", 1)
end)

T.test("info panel: the meter's names alone in class colors, the numbers left as they are", function()
    local DUI = login()
    local M, Style = stub.infopanel.Meter, DUI.Style
    stub.meter.sources = { { name = "Sigzil", classFilename = "MAGE", totalAmount = 2640 },
                           { name = "Nobody", classFilename = nil, totalAmount = 10 } }
    DUI:Set("InfoPanel", "meter.nameColor", { 1, 0.5, 0 })
    DUI:Set("InfoPanel", "meter.nameColorBy", "class")
    M.Draw()
    T.rgb(bars()[1].name.__textColor, { Style.ClassTextColor("MAGE") }, "the name in its class color")
    T.rgb(bars()[1].amount.__textColor, Style.INK.VALUE, "the number keeps its color")
    T.rgb(bars()[2].name.__textColor, Style.INK.VALUE, "no class known: white")
    DUI:Set("InfoPanel", "meter.nameColorBy", "custom")
    M.Draw()
    T.rgb(bars()[1].name.__textColor, { 1, 0.5, 0 }, "back to the picked color")
    DUI:Set("InfoPanel", "meter.nameColor", { 1, 1, 1 })
end)

T.test("info panel: a meter's own window can have its own background", function()
    local DUI = login()
    local P = stub.infopanel.Panel
    DUI:Set("InfoPanel", "meter.detached", true)
    settle()
    local own, xp = DUI.Style.GetShell(P.meterFrame).opts, DUI.Style.GetShell(P.xp).opts
    T.eq(own.bgAlpha, xp.bgAlpha, "the panel's at first")
    DUI:Set("InfoPanel", "meter.alphaOwn", true)
    DUI:Set("InfoPanel", "meter.alpha", 0)
    settle()
    T.eq(own.bgAlpha, 0, "see-through")
    T.truthy(xp.bgAlpha > 0, "the experience bar keeps the panel's")
end)

T.test("options: the info panel is split into tabs and every setting has one home", function()
    login()
    local section
    for _, s in ipairs(DaylightUI.Options.Sections()) do
        if s.id == "InfoPanel" then section = s end
    end
    T.truthy(section, "an Info Panel section")
    T.eq(#section.pages, 6, "six tabs (every meter on one Meters page)")
    local ids = {}
    for _, page in ipairs(section.pages) do ids[#ids + 1] = page.id end
    T.eq(table.concat(ids, ","), "InfoPanel.panel,InfoPanel.meter,InfoPanel.map,InfoPanel.data,InfoPanel.databar,InfoPanel.tracker", "tab order")
    local seen, sliders = {}, 0
    for _, page in ipairs(section.pages) do
        for _, g in ipairs(page.groups) do
            for _, item in ipairs(g.items) do
                if item.key then
                    T.falsy(seen[item.key], "only once: " .. item.key)
                    seen[item.key] = true
                elseif item.type == "slider" then
                    sliders = sliders + 1
                end
            end
        end
    end
    for _, key in ipairs({
        "panelAlpha", "panelBorder",
        "xp.enabled", "xp.showText", "xp.showPercent", "xp.textSize", "xp.gradient", "xp.color", "xp.ticks", "xp.tipSide", "xp.height", "xp.detached", "xp.width",
        "meter.enabled", "meter.detached", "meter.numbers", "meter.onJoin", "meter.onInstance", "panelAlphaOwn",
        "meters.sameFight", "meters.backToCurrent",
        -- Every window's own (the Meters page edits the one picked):
        "win.enabled", "win.mode", "win.session", "win.width", "win.height", "win.inGroup", "win.inCombat", "win.inInstance",
        "win.border", "win.rowHeight", "win.rowGap", "win.textSize", "win.barColor", "win.gradient", "win.barCustom",
        "win.nameColor", "win.nameColorBy", "win.classText", "win.trackAlpha", "win.alphaOwn", "win.alpha", "win.rank", "win.icons",
        "win.showTotal", "win.showRate", "win.showShare", "win.showMe", "win.header", "win.headerTotal",
        "win.auto", "win.at", "win.unit", "win.rows", "win.belowRows", "win.pullLine", "win.pullColor",
        "win.columns.damage", "threat.fade.mode",
        "tracker.enabled", "tracker.fade.mode", "fade.mode", "tracker.fade.alpha", "fade.alpha",
        "map.enabled", "map.size", "map.buttons", "map.meterSide", "map.alphaOwn", "map.alpha", "map.border",
        "map.clock.enabled", "map.clock.twentyFour", "map.clock.useServer", "map.fps.enabled", "map.coords.enabled", "map.location.enabled",
        "data.enabled", "data.count", "data.labels", "data.textSize", "data.slot1", "data.slot5",
    }) do
        T.truthy(seen[key], "not dropped: " .. key)
    end
    T.eq(sliders, 0, "the faded opacity sliders have keys now")
end)

T.test("options: with the Quest Tracker module drawing ours, the game tracker's tab is gone", function()
    login()
    DaylightUI.questsOwnTracker = true
    for _, s in ipairs(DaylightUI.Options.Sections()) do
        for _, page in ipairs(s.pages) do T.truthy(page.id ~= "InfoPanel.tracker", "not listed") end
    end
    T.falsy(DaylightUI.Options.GetPage("InfoPanel.tracker"), "can't be opened")
    T.eq(#DaylightUI.Options.Search("place under the info panel"), 0, "not searched")
end)

-- ---------------------------------------------------------------------
-- XP gain effects
-- ---------------------------------------------------------------------

local function setXP(value, max)
    _G.UnitXP = function() return value end
    _G.UnitXPMax = function() return max or 1200 end
    stub.FireEvent("PLAYER_XP_UPDATE")
end

local function xpWidth(XP)
    XP.bar:SetWidth(200)   -- the stub lays nothing out; give the bar a width
    return 200
end

T.test("info panel: an XP gain flashes the gained piece and shows +N, adding up", function()
    login()
    local XP, G = stub.infopanel.XP, stub.infopanel.XPGain
    xpWidth(XP)
    T.eq(G.flash, nil, "login: no effect")
    setXP(300)
    T.eq(G.flash, nil, "same value: no effect")
    setXP(420)
    T.truthy(G.flash and G.flash:IsShown(), "the gained piece flashes")
    T.eq(G.flash:GetWidth(), 200 * 120 / 1200, "as wide as the gain")
    local _, _, _, x = G.flash:GetPoint(1)
    T.eq(x, 200 * 300 / 1200, "starting where the old value ended")
    T.eq(G.riser.text:GetText(), "+120")
    T.truthy(G.riser:IsShown())
    setXP(470)
    T.eq(G.riser.text:GetText(), "+170", "kills in a row add up while it shows")
    G.riser.group.__playing = false
    G.riser.group:GetScript("OnFinished")(G.riser.group)
    T.falsy(G.riser:IsShown())
    setXP(500)
    T.eq(G.riser.text:GetText(), "+30", "after it is gone, a fresh count")
    setXP(100)
    T.eq(G.riser.text:GetText(), "+30", "losing XP shows nothing")
end)

T.test("info panel: a level up sweeps once, with no gain flash, then the bar empties", function()
    login()
    local XP, G = stub.infopanel.XP, stub.infopanel.XPGain
    xpWidth(XP)
    local level = 10
    _G.UnitLevel = function() return level end
    setXP(1100)           -- a gain at level 10
    G.flash:Hide()
    level = 11
    _G.UnitXP = function() return 40 end
    _G.UnitXPMax = function() return 1500 end
    stub.FireEvent("PLAYER_LEVEL_UP", 11)
    T.truthy(G.band and G.band:IsShown(), "the band crosses")
    T.eq(G.band:GetWidth(), 200 * G.BAND)
    T.eq(XP.bar:GetValue(), 1500, "held full while it crosses")
    T.falsy(G.flash:IsShown(), "no gain flash on a level up")
    stub.RunTimers()
    T.eq(XP.bar:GetValue(), 40, "then it empties to the new value")
    -- the game may report the level a beat after the event
    setXP(60, 1500)
    local shown = G.band:IsShown()
    G.band.group.__playing = false
    G.band.group:GetScript("OnFinished")(G.band.group)
    T.falsy(G.band:IsShown(), "sweep hides at its end")
    _G.UnitLevel = nil
    T.eq(shown, true)
end)

T.test("info panel: no gain effects for a changed max, a secret value, motion off or the setting off", function()
    login()
    local XP, G = stub.infopanel.XP, stub.infopanel.XPGain
    xpWidth(XP)
    setXP(300)
    setXP(500, 2000)
    T.eq(G.flash, nil, "another max (a rank change): plain")
    T.eq(XP.bar:GetValue(), 500)
    local real = _G.issecretvalue
    _G.issecretvalue = function(v) return v == 777 end
    setXP(777, 2000)
    T.eq(G.flash, nil, "a secret value skips the effect")
    T.eq(XP.bar:GetValue(), 777, "and sets the bar plainly")
    _G.issecretvalue = real
    setXP(800, 2000)
    DaylightUI.DB.General().motion = false
    setXP(900, 2000)
    T.falsy(G.flash and G.flash:IsShown(), "motion off: none")
    T.eq(XP.bar:GetValue(), 900, "the value still lands")
    DaylightUI.DB.General().motion = true
    DaylightUI:Set("InfoPanel", "xpGain", false)
    setXP(1000, 2000)
    T.falsy(G.flash and G.flash:IsShown(), "setting off: none")
    T.eq(XP.bar:GetValue(), 1000)
    DaylightUI:Set("InfoPanel", "xpGain", true)
end)

-- ---------------------------------------------------------------------
-- The XP text counting up, and the rested shimmer
-- ---------------------------------------------------------------------

local function tweens(dt)
    local d = DaylightUI.Motion.Driver()
    if d then stub.RunOnUpdate(d, dt or 1) end
end

T.test("info panel: the XP text counts up to a gain, gold while it rises", function()
    login()
    local XP = stub.infopanel.XP
    xpWidth(XP)
    DaylightUI:Set("InfoPanel", "xp.showText", true)
    T.eq(XP.text:GetText(), "300 / 1,200   (+400)", "the first read: no count")
    local before = { XP.text:GetTextColor() }
    setXP(600)
    T.eq(XP.text:GetText(), "300 / 1,200   (+400)", "starts from what was on screen")
    T.rgb({ XP.text:GetTextColor() }, XP.GAIN, "tinted gold while it rises")
    tweens(0.1)
    local mid = tonumber((XP.text:GetText():match("^([%d,]+) /"):gsub(",", "")))
    T.truthy(mid > 300 and mid < 600, "partway: " .. XP.text:GetText())
    _G.GetXPExhaustion = function() return 100 end
    stub.FireEvent("UPDATE_EXHAUSTION")   -- the same value again (rest used up): the count goes on
    tweens(0.05)
    T.truthy(XP.text:GetText():find("(+100)", 1, true), "with the new rest")
    T.falsy(XP.text:GetText():find("^600 /"), "still counting")
    tweens(1)
    T.eq(XP.text:GetText(), "600 / 1,200   (+100)")
    T.rgb({ XP.text:GetTextColor() }, before, "its own color again")
    _G.GetXPExhaustion = function() return 400 end
end)

T.test("info panel: the XP text writes at once for a loss, a level up, reputation, a secret or motion off", function()
    login()
    local XP = stub.infopanel.XP
    xpWidth(XP)
    DaylightUI:Set("InfoPanel", "xp.showText", true)
    setXP(200)
    T.eq(XP.text:GetText(), "200 / 1,200   (+400)", "a loss: at once")
    local level = 10
    _G.UnitLevel = function() return level end
    setXP(1100)
    tweens()
    level = 11
    _G.UnitXP = function() return 40 end
    _G.UnitXPMax = function() return 1500 end
    stub.FireEvent("PLAYER_LEVEL_UP", 11)
    T.eq(XP.text:GetText(), "40 / 1,500   (+400)", "a level up: at once")
    _G.UnitLevel = nil
    local real = _G.issecretvalue
    _G.issecretvalue = function(v) return v == 777 end
    setXP(777, 1500)
    T.eq(XP.text:GetText(), "777 / 1,500   (+400)", "a secret value: at once")
    _G.issecretvalue = real
    DaylightUI.DB.General().motion = false
    setXP(900, 1500)
    T.eq(XP.text:GetText(), "900 / 1,500   (+400)", "motion off: at once")
    DaylightUI.DB.General().motion = true
    _G.IsPlayerAtEffectiveMaxLevel = function() return true end
    _G.C_Reputation = { GetWatchedFactionData = function()
        return { name = "Stormwind", reaction = 5, currentReactionThreshold = 3000, nextReactionThreshold = 9000,
                 currentStanding = 4000 }
    end }
    stub.FireEvent("UPDATE_FACTION")
    T.eq(XP.text:GetText(), "1,000 / 6,000", "reputation: at once")
    _G.IsPlayerAtEffectiveMaxLevel = function() return false end
    _G.C_Reputation = nil
end)

T.test("info panel: starting to rest shimmers once along the rested part; never at login, without rest or on reputation", function()
    login(function() stub.resting = true end)
    local XP = stub.infopanel.XP
    xpWidth(XP)
    local function rest(on)
        stub.resting = on
        stub.FireEvent("PLAYER_UPDATE_RESTING")
    end
    T.falsy(XP.shimmer:IsShown(), "already resting at login: nothing")
    rest(false)
    T.falsy(XP.shimmer:IsShown(), "leaving: nothing")
    rest(true)
    T.truthy(XP.shimmer:IsShown(), "starting to rest: the light runs")
    local _, rel, _, x = XP.restedSpan:GetPoint(1)
    T.eq(rel, XP.bar)
    T.eq(x, 200 * 300 / 1200, "from the XP fill's end")
    T.eq(XP.restedSpan:GetWidth(), 200 * 400 / 1200, "to the rested end")
    tweens(0.5)
    T.truthy(XP.shimmer:IsShown(), "a slow light")
    tweens(1)
    T.falsy(XP.shimmer:IsShown(), "once")
    rest(true)
    T.falsy(XP.shimmer:IsShown(), "still resting: no second light")
    _G.GetXPExhaustion = function() return 0 end
    rest(false); rest(true)
    T.falsy(XP.shimmer:IsShown(), "no rested XP: nothing")
    _G.GetXPExhaustion = function() return 400 end
    _G.IsPlayerAtEffectiveMaxLevel = function() return true end
    _G.C_Reputation = { GetWatchedFactionData = function()
        return { name = "Stormwind", reaction = 5, currentReactionThreshold = 0, nextReactionThreshold = 9000 }
    end }
    stub.FireEvent("UPDATE_FACTION")
    rest(false); rest(true)
    T.falsy(XP.shimmer:IsShown(), "the reputation bar: nothing")
    _G.IsPlayerAtEffectiveMaxLevel = function() return false end
    _G.C_Reputation = nil
    stub.resting = false
end)

-- ---------------------------------------------------------------------
-- No work repeated for nothing (each counts the work it saves)
-- ---------------------------------------------------------------------

T.test("info panel: roster changes and pulls re-lay out the panel only when the meter comes or goes", function()
    local DUI = login()
    local P, Map = stub.infopanel.Panel, stub.infopanel.Minimap
    local layouts, maps = 0, 0
    local layout, apply = P.Layout, Map.Apply
    P.Layout = function(...) layouts = layouts + 1; return layout(...) end
    Map.Apply = function(...) maps = maps + 1; return apply(...) end
    for _ = 1, 3 do stub.FireEvent("GROUP_ROSTER_UPDATE") end
    stub.EnterCombat()
    stub.LeaveCombat()
    T.eq(layouts, 0, "the meter shows either way: nothing laid out again")
    T.eq(maps, 0, "the minimap and its drawer left alone")
    T.truthy(P.meterArea:IsShown())
    DUI:Set("InfoPanel", "meter.inCombat", true)
    settle()
    layouts, maps = 0, 0
    local DT = stub.infopanel.DataTexts
    local texts, dtApply = 0, DT.Apply
    DT.Apply = function(...) texts = texts + 1; return dtApply(...) end
    stub.EnterCombat()
    T.eq(layouts, 1, "waiting for combat: one layout as the fight starts")
    T.truthy(P.meterArea:IsShown(), "and the meter is out")
    T.eq(maps, 0, "the meter coming: the minimap left alone")
    T.eq(texts, 0, "and the data texts (no events registered again, no guild roster asked)")
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    T.eq(layouts, 1, "a roster change mid-fight changes nothing")
    stub.LeaveCombat()
    settle()
    T.eq(layouts, 2, "one more as it ends")
    T.falsy(P.meterArea:IsShown())
    T.eq(maps + texts, 0, "the meter going: still only the meter")
    P.Layout, Map.Apply, DT.Apply = layout, apply, dtApply
end)

T.test("info panel: the meter paints a row's colors only when its player's class changes", function()
    local DUI = login()
    local M = stub.infopanel.Meter
    local paints = 0
    local paint = M.PaintBar
    M.PaintBar = function(...) paints = paints + 1; return paint(...) end
    stub.meter.sources = {
        { name = "Teft", classFilename = "WARRIOR", totalAmount = 5000 },
        { name = "Rock", classFilename = "HUNTER", totalAmount = 2500 },
    }
    M.Draw()
    T.eq(paints, 2, "both rows painted")
    stub.meter.sources[1].totalAmount = 6000
    M.Draw(); M.Draw()
    T.eq(paints, 2, "new numbers, same players: no repaint")
    T.eq(bars()[1].bar:GetValue(), 6000, "the numbers still follow")
    stub.meter.sources[1], stub.meter.sources[2] = stub.meter.sources[2], stub.meter.sources[1]
    M.Draw()
    T.eq(paints, 4, "players swapped places: both rows repainted")
    stub.meter.sources[1] = { name = "Them", classFilename = stub.Secret("MAGE"), totalAmount = 1 }
    M.Draw(); M.Draw()
    T.eq(paints, 6, "a secret class is painted every time, never compared")
    stub.meter.sources[1] = { name = "Teft", classFilename = "WARRIOR", totalAmount = 5000 }
    M.Draw()
    paints = 0
    stub.combat = true   -- a color change mid-fight shows at once
    DUI:Set("InfoPanel", "meter.nameColor", { 0.25, 0.5, 0.75 })
    M.Draw()
    T.eq(paints, 2, "a setting changed: every row repainted")
    T.eq(bars()[1].name.__textColor[1], 0.25, "in the new color")
    stub.combat = false
    M.PaintBar = paint
end)

T.test("info panel: the hover breakdown lays itself out only when its shape changes", function()
    login()
    local M, B = stub.infopanel.Meter, stub.infopanel.Breakdown
    stub.meter.sources = { { name = "Sigzil", classFilename = "MAGE", totalAmount = 1000, sourceGUID = "Player-2" } }
    stub.meter.spells = { { spellID = 1, totalAmount = 750 }, { spellID = 2, totalAmount = 250 } }
    M.Draw()
    local fits = 0
    local R = stub.infopanel.Rows
    local fit = R.Layout
    R.Layout = function(...) fits = fits + 1; return fit(...) end
    B.Show(bars()[1])
    T.eq(fits, 2, "laid out as it opens")
    stub.meter.spells[1].totalAmount = 900
    for _ = 1, 3 do B.Refresh() end
    T.eq(fits, 2, "new numbers only: no layout")
    local rows = {}
    for _, c in ipairs(stub.Children(B.Frame())) do if c.amount and c:IsShown() then rows[#rows + 1] = c end end
    T.eq(rows[1].amount.__text, "900  78%", "the numbers still follow")
    stub.meter.spells[3] = { spellID = 2, totalAmount = 50 }
    B.Refresh()
    T.eq(fits, 5, "a third spell: laid out again")
    R.Layout = fit
end)

T.test("info panel: the drawer's corner button is painted only when it lights up or dims", function()
    login(withCompartment)
    local D = stub.infopanel.Drawer
    D.Collect()
    local paints = 0
    local dot = D.glyph.dots[1]
    local set = dot.SetVertexColor
    dot.SetVertexColor = function(...) paints = paints + 1; return set(...) end
    for _ = 1, 5 do D.Watch() end
    T.eq(paints, 0, "nothing changed: no paint")
    function D.glyph:IsMouseOver() return true end
    for _ = 1, 5 do D.Watch() end
    T.eq(paints, 1, "lit once as the mouse comes")
    function D.glyph:IsMouseOver() return false end
    D.Watch()
    T.eq(paints, 2, "dimmed once as it leaves")
    dot.SetVertexColor = set
end)

T.test("info panel: coordinates and clock write only what changed; coordinates off runs nothing", function()
    login()
    local x, y = 0.4523, 0.618
    _G.C_Map = {
        GetBestMapForUnit = function() return 1429 end,
        GetPlayerMapPosition = function() return { GetXY = function() return x, y end } end,
    }
    local Map = stub.infopanel.Minimap
    Map.UpdateCoords()
    local writes = 0
    local set = Map.coords.text.SetText
    Map.coords.text.SetText = function(...) writes = writes + 1; return set(...) end
    stub.RunTickers(); stub.RunTickers()
    T.eq(writes, 0, "standing still: nothing written")
    x = 0.4524
    stub.RunTickers()
    T.eq(writes, 0, "a step too small to show: nothing written")
    x = 0.4611
    stub.RunTickers()
    T.eq(writes, 1)
    T.eq(Map.coords.text:GetText(), "46.1, 61.8")
    DaylightUI:Set("InfoPanel", "map.coords.enabled", false)
    local reads = 0
    _G.C_Map.GetBestMapForUnit = function() reads = reads + 1; return 1429 end
    stub.RunTickers()
    T.eq(reads, 0, "switched off: no ticker reading the position")
    DaylightUI:Set("InfoPanel", "map.coords.enabled", true)
    x = 0.5
    stub.RunTickers()
    T.eq(Map.coords.text:GetText(), "50.0, 61.8", "back on: running again")
    _G.C_Map = nil
    -- The clock: once a minute, not once a second.
    stub.SetTime(os.time({ year = 2024, month = 1, day = 1, hour = 15, min = 5, sec = 0 }))
    Map.UpdateClock()
    local clockWrites = 0
    local setClock = Map.clock.text.SetText
    Map.clock.text.SetText = function(...) clockWrites = clockWrites + 1; return setClock(...) end
    stub.SetTime(os.time({ year = 2024, month = 1, day = 1, hour = 15, min = 5, sec = 30 }))
    Map.UpdateClock()
    T.eq(clockWrites, 0, "the same minute: nothing written")
    stub.SetTime(os.time({ year = 2024, month = 1, day = 1, hour = 15, min = 6, sec = 0 }))
    Map.UpdateClock()
    T.eq(clockWrites, 1)
    T.eq(Map.clock.text:GetText(), "15:06")
end)

T.test("info panel: the panel at full strength doesn't ask the fade engine about the map", function()
    login()
    local P, F = stub.infopanel.Panel, DaylightUI.Fade
    local asks = 0
    local state = F.State
    F.State = function(...) asks = asks + 1; return state(...) end
    for _ = 1, 5 do P.holder:SetAlpha(1) end
    T.eq(asks, 0)
    T.truthy(Minimap:IsShown())
    F.State = state
end)

-- The game sets rotateMinimap from its Edit Mode layout every time it applies
-- it, at each login. The switch must write it there too or it resets on reload.
T.test("info panel: the rotate switch is saved into the active Edit Mode layout", function()
    login()
    local item
    for _, page in ipairs(stub.infopanel.OPTIONS.pages) do
        for _, g in ipairs(page.groups) do
            for _, it in ipairs(g.items) do
                if it.label == "Rotate as you turn" then item = it end
            end
        end
    end
    local function copy(t)
        local c = {}
        for k, v in pairs(t) do c[k] = type(v) == "table" and copy(v) or v end
        return c
    end
    Enum.EditModeSystem = { Minimap = 2 }
    Enum.EditModeMinimapSetting = { RotateMinimap = 1 }
    _G.EditModePresetLayoutManager = { GetCopyOfPresetLayouts = function() return { { layoutType = 0, systems = {} } } end }
    local saved = { activeLayout = 2, layouts = { { layoutType = 1, layoutName = "DaylightUI - DPS/Tank", systems = {
        { system = 2, settings = { { setting = 1, value = 0 } }, anchorInfo = {} } } } } }
    _G.C_EditMode = {
        GetLayouts = function() return { activeLayout = saved.activeLayout, layouts = copy(saved.layouts) } end,
        SaveLayouts = function(info)
            saved.layouts = {}
            for _, l in ipairs(info.layouts) do if l.layoutType ~= 0 then saved.layouts[#saved.layouts + 1] = l end end
            saved.count = (saved.count or 0) + 1
        end,
        SetActiveLayout = function() error("no layout switch") end,
    }
    _G.EditModeManagerFrame = _G.EditModeManagerFrame or CreateFrame("Frame", "EditModeManagerFrame")
    EditModeManagerFrame.accountSettings = {}
    EditModeManagerFrame:Hide()
    item.set(true)
    T.eq(stub.cvars.rotateMinimap, "1", "turns at once")
    stub.RunTimers()
    T.eq(saved.layouts[1].systems[1].settings[1].value, 1, "kept in the layout")
    item.set(false)
    stub.RunTimers()
    T.eq(saved.layouts[1].systems[1].settings[1].value, 0)
    T.eq(saved.count, 2, "one save per change")
end)

-- ---------------------------------------------------------------------
-- The threat meter
-- ---------------------------------------------------------------------

-- A party of three on your target's threat list: a tank, you, a mage.
local function threatParty(boss)
    stub.SetGroup(true)
    stub.units.player = { name = "Navani", isPlayer = true, class = "PRIEST" }
    stub.units.party1 = { name = "Kaladin", isPlayer = true, class = "WARRIOR", role = "TANK" }
    stub.units.party2 = { name = "Shallan", isPlayer = true, class = "MAGE" }
    stub.units.target = { name = "Sadeas", isPlayer = false, reaction = 2, boss = boss, threatList = {
        party1 = { status = 3, scaled = 100, raw = 100, value = 10000 },
        player = { status = 0, scaled = 80, raw = 88, value = 8800 },
        party2 = { status = 0, scaled = 50, raw = 65, value = 6500 },
    } }
end

local function threatSettle()
    stub.RunOnUpdate(stub.infopanel.ThreatMeter.slider.driver, 1)
end

local function threatRows()
    local out = {}
    for _, r in ipairs(stub.infopanel.ThreatMeter.rows) do
        if r:IsShown() then out[#out + 1] = r end
    end
    return out
end

T.test("threat meter: slides out of the meter's left edge in combat in a group, back after", function()
    login()
    local TM, P = stub.infopanel.ThreatMeter, stub.infopanel.Panel
    T.eq(TM.host, P.panel, "hangs off the panel")
    T.falsy(TM.clip:IsShown(), "tucked away out of combat")
    threatParty()
    stub.EnterCombat()
    T.truthy(TM.clip:IsShown())
    T.truthy(TM.slider.p < 1, "slides, not a jump")
    threatSettle()
    T.eq(TM.slider.p, 1)
    T.eq(select(2, TM.clip:GetPoint(1)), P.panel)
    TM.Draw()
    local rows = threatRows()
    T.eq(#rows, 3, "one row per member on the list")
    T.eq(rows[1].name:GetText(), "Kaladin", "highest threat first")
    T.eq(rows[1].amount:GetText(), "100%")
    T.eq(rows[3].name:GetText(), "Shallan")
    T.eq(rows[2].amount:GetText(), "80%", "your percent of the pull")
    T.truthy(rows[2].mine, "your own row known")
    T.falsy(rows[1].mine, "the others not")
    -- The pull line: your threat / your percent = 11000 (the tank's x 1.1), the bars' top.
    T.truthy(TM.line:IsShown(), "the pull line")
    local g = TM.geo
    local x = select(4, TM.line:GetPoint(1))
    T.near(x, g.barLeft + g.barWidth / TM.ROOM, 1e-6, "the highest mark, with room past it so it never hides at the bars' end")
    T.truthy(x < g.barLeft + g.barWidth - 4)
    T.near(rows[1].bar:GetValue(), 10000, 1e-6)
    stub.LeaveCombat()
    threatSettle()
    T.falsy(TM.clip:IsShown(), "back in after the fight")
    stub.SetGroup(false)
end)

T.test("threat meter: solo it stays in; its tab slides it out and back by hand", function()
    login()
    local TM = stub.infopanel.ThreatMeter
    stub.EnterCombat()
    T.falsy(TM.clip:IsShown(), "solo: not wanted")
    TM.tab:GetScript("OnClick")(TM.tab)
    threatSettle()
    T.truthy(TM.clip:IsShown(), "out by hand")
    TM.Draw()
    T.truthy(TM.win.empty:IsShown(), "no target: says so")
    T.eq(TM.win.empty:GetText(), "No target")
    TM.tab:GetScript("OnClick")(TM.tab)
    threatSettle()
    T.falsy(TM.clip:IsShown(), "and back")
    stub.LeaveCombat()
end)

T.test("threat meter: alone with a pet it slides out, your pet in the list; it leaves with the pet", function()
    login()
    local TM = stub.infopanel.ThreatMeter
    stub.units.player = { name = "Navani", isPlayer = true, class = "HUNTER" }
    stub.units.pet = { name = "Spot", class = "WARRIOR" }
    stub.units.target = { name = "Sadeas", isPlayer = false, reaction = 2, threatList = {
        pet = { status = 3, scaled = 100, raw = 100, value = 10000 },
        player = { status = 0, scaled = 80, raw = 88, value = 8800 },
    } }
    stub.EnterCombat()
    threatSettle()
    T.truthy(TM.clip:IsShown(), "a pet is company: out in a fight")
    TM.Draw()
    local rows = threatRows()
    T.eq(#rows, 2, "you and your pet")
    T.eq(rows[1].name:GetText(), "Spot", "the pet holds it")
    T.eq(rows[2].amount:GetText(), "80%")
    T.truthy(TM.line:IsShown(), "the pull line, from the pet's threat")
    stub.units.pet = nil
    stub.RunTickers()
    threatSettle()
    T.falsy(TM.clip:IsShown(), "the pet gone: back in, without waiting for the fight's end")
    stub.LeaveCombat()
    stub.units.target = nil
end)

T.test("threat meter: in a group your pet has its row too", function()
    login()
    local TM = stub.infopanel.ThreatMeter
    threatParty()
    stub.units.pet = { name = "Spot", class = "WARRIOR" }
    stub.units.target.threatList.pet = { status = 0, scaled = 60, raw = 70, value = 7000 }
    stub.EnterCombat()
    threatSettle()
    TM.Draw()
    local rows = threatRows()
    T.eq(#rows, 4, "the party and the pet")
    T.eq(rows[3].name:GetText(), "Spot", "by its threat")
    stub.LeaveCombat()
    stub.units.pet = nil
    stub.SetGroup(false)
end)

T.test("threat meter: can wait for you to be the tank, or for its tab only", function()
    local DUI = login()
    local TM = stub.infopanel.ThreatMeter
    threatParty()
    DUI:Set("InfoPanel", "threat.auto", "tank")
    stub.EnterCombat()
    threatSettle()
    T.falsy(TM.clip:IsShown(), "not the tank")
    stub.LeaveCombat()
    stub.units.player.role = "TANK"
    stub.FireEvent("PLAYER_ROLES_ASSIGNED")
    stub.EnterCombat()
    threatSettle()
    T.truthy(TM.clip:IsShown(), "the tank: out")
    stub.LeaveCombat()
    stub.units.player.role = nil
    DUI:Set("InfoPanel", "threat.auto", "off")
    stub.EnterCombat()
    threatSettle()
    T.falsy(TM.clip:IsShown(), "only from its tab")
    stub.LeaveCombat()
    DUI:Set("InfoPanel", "threat.enabled", false)
    T.falsy(TM.tab:IsShown(), "switched off: no tab either")
    stub.SetGroup(false)
end)

T.test("threat meter: on a boss the numbers are secret: drawn whole in a fixed order, no pull line", function()
    login()
    local TM = stub.infopanel.ThreatMeter
    threatParty(true)
    stub.EnterCombat()
    threatSettle()
    TM.Draw()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local rows = threatRows()
    T.eq(#rows, 3)
    T.eq(rows[1].name:GetText(), "Kaladin", "the tank (by role) first")
    T.eq(rows[2].name:GetText(), stub.units.player.name, "then you")
    T.eq(type(rows[2].amount:GetText()), "table", "a secret percent, written by the client")
    T.falsy(TM.line:IsShown(), "no pull line from hidden numbers")
    stub.LeaveCombat()
    stub.SetGroup(false)
end)

T.test("threat meter: test mode shows a sample group with you in it", function()
    local DUI = login()
    local TM = stub.infopanel.ThreatMeter
    DUI.SetTestMode(true)
    threatSettle()
    T.truthy(TM.clip:IsShown())
    TM.Draw()
    local rows = threatRows()
    T.eq(#rows, 6)
    T.eq(TM.win.header:GetText(), TM.SAMPLE_TARGET)
    local mine = 0
    for _, r in ipairs(rows) do if r.mine then mine = mine + 1 end end
    T.eq(mine, 1, "you, outlined")
    T.truthy(TM.line:IsShown())
    DUI.SetTestMode(false)
    threatSettle()
    T.falsy(TM.clip:IsShown())
end)

T.test("threat meter: its top stays level with its host's, whichever of them has a border", function()
    local DUI = login()
    local TM = stub.infopanel.ThreatMeter
    DUI.SetTestMode(true)
    threatSettle()
    local function clipY() return select(5, TM.clip:GetPoint(1)) end
    local function tabY() return select(5, TM.tab:GetPoint(1)) end
    local M, hT = TM.MARGIN, TM.hostT
    T.near(clipY(), M, 1e-6, "both framed: the outer edges line up")
    local tabFramed = tabY()
    -- The map's box with no border draws its background a border's width inside its frame.
    DUI:Set("InfoPanel", "map.border", false)
    T.near(clipY(), M - hT, 1e-6, "no border on the panel: down to where its background starts")
    T.near(tabY(), tabFramed - hT, 1e-6, "the tab comes down with the window")
    DUI:Set("InfoPanel", "threat.border", false)
    T.near(clipY(), M, 1e-6, "neither framed: both backgrounds start a border in")
    DUI:Set("InfoPanel", "map.border", true)
    T.near(clipY(), M + hT, 1e-6, "only the panel framed: up to its outer edge")
    DUI:Set("InfoPanel", "threat.border", true)
    DUI:Set("InfoPanel", "meter.detached", true)
    DUI:Set("InfoPanel", "meter.border", false)
    T.near(clipY(), M - hT, 1e-6, "beside a separate meter window with no border: the same")
    DUI:Set("InfoPanel", "meter.detached", false)
    DUI.SetTestMode(false)
    threatSettle()
end)

T.test("threat meter: out, it pushes the panel's left edge (the buffs' anchor) out with it", function()
    local DUI = login()
    local TM, P = stub.infopanel.ThreatMeter, stub.infopanel.Panel
    local edge = _G.DaylightUIInfoPanelEdge
    T.eq(select(2, edge:GetPoint(1)), P.panel)
    T.near(edge:GetWidth(), 0, 0.01, "tucked away: the panel's own edge")
    DUI.SetTestMode(true)
    T.truthy(TM.slider.p < 1)
    T.truthy(edge:GetWidth() < TM.geo.W - TM.geo.T, "slides with it")
    threatSettle()
    T.near(edge:GetWidth(), TM.geo.W - TM.geo.T, 1e-6, "out: past the window")
    DUI:Set("InfoPanel", "meter.detached", true)
    T.near(edge:GetWidth(), 0, 0.01, "beside a separate meter window: the panel's edge again")
    DUI:Set("InfoPanel", "meter.detached", false)
    DUI.SetTestMode(false)
    threatSettle()
    T.near(edge:GetWidth(), 0, 0.01, "back in")
end)

T.test("threat meter: under the meter, it rises out of its bottom, as wide, short, and the meter's rows make room", function()
    local DUI = login()
    local TM, P, M = stub.infopanel.ThreatMeter, stub.infopanel.Panel, stub.infopanel.Meter
    DUI:Set("InfoPanel", "threat.at", "below")
    stub.RunTimers()
    DUI:Set("InfoPanel", "meter.enabled", false)
    stub.RunTimers()
    T.falsy(TM.clip:IsShown(), "the meter folded away: gone with it")
    T.falsy(TM.tab:IsShown(), "its tab too")
    DUI:Set("InfoPanel", "meter.enabled", true)
    DUI.SetTestMode(true)
    stub.RunTimers()
    T.truthy(TM.below, "the meter in view: under it")
    T.eq(TM.clip:GetParent(), P.meterArea, "inside the panel")
    T.eq(select(2, TM.clip:GetPoint(1)), P.meterArea)
    T.eq(select(3, TM.clip:GetPoint(1)), "BOTTOMLEFT", "on the meter's bottom edge")
    T.eq(TM.geo.W, DUI:Get("InfoPanel", "meter.width"), "as wide as the meter")
    threatSettle()
    TM.Draw()
    T.eq(#threatRows(), 3, "short: three rows")
    T.near(TM.clip:GetHeight(), TM.height, 1e-6, "all the way out")
    T.near(M.Reserved(), TM.height + TM.BELOW_GAP, 1e-6, "the meter's rows stop above it")
    T.falsy(DaylightUI.Style.GetShell(TM.win).opts.noBorder == false, "no box of its own")
    T.near(_G.DaylightUIInfoPanelEdge:GetWidth(), 0, 0.01, "the buffs stay put")
    DUI.SetTestMode(false)
    stub.RunTimers()
    threatSettle()
    T.eq(M.Reserved(), 0, "back in: the meter has its room again")
    DUI:Set("InfoPanel", "threat.at", "left")
    DUI.SetTestMode(true)
    stub.RunTimers()
    T.eq(TM.clip:GetParent(), UIParent, "left again")
    T.eq(M.Reserved(), 0)
    DUI.SetTestMode(false)
end)

T.test("threat meter: the panel's fold tab stays on the panel unless the window reaches down to it", function()
    local DUI = login()
    local TM, P = stub.infopanel.ThreatMeter, stub.infopanel.Panel
    DUI:Set("InfoPanel", "threat.rows", 2)
    DUI.SetTestMode(true)
    stub.RunTimers()
    threatSettle()
    TM.Draw()
    local a = { P.arrow:GetPoint(1) }
    T.eq(a[2], P.panel)
    T.truthy(a[4] >= 0, "a short window: the tab stays on the panel's edge, not out in the open")
    DUI:Set("InfoPanel", "threat.rows", 10)
    DUI:Set("InfoPanel", "threat.rowHeight", 26)
    stub.RunTimers()
    threatSettle()
    TM.Draw()
    a = { P.arrow:GetPoint(1) }
    T.truthy(a[4] < -100, "a tall one covering it: the tab rides the window's edge")
    DUI.SetTestMode(false)
    stub.RunTimers()
    threatSettle()
    a = { P.arrow:GetPoint(1) }
    T.truthy(a[4] >= 0, "back in: on the panel")
end)

T.test("threat meter: undocked, its own window moves and resizes in unlock mode", function()
    local DUI = login()
    local TM, P = stub.infopanel.ThreatMeter, stub.infopanel.Panel
    local e = DUI.Movers.Get(TM.MOVER)
    T.truthy(e.suspended, "docked: no handle of its own")
    DUI:Set("InfoPanel", "threat.at", "free")
    stub.RunTimers()
    T.falsy(e.suspended, "undocked: a handle in unlock mode")
    T.eq(TM.host, TM.freeFrame)
    T.eq(TM.clip:GetParent(), TM.freeFrame, "inside its own window")
    T.falsy(TM.clip:IsShown(), "out of combat solo: away")
    -- In a fight in a group it fades in where it was put.
    threatParty()
    stub.EnterCombat()
    threatSettle()
    T.truthy(TM.clip:IsShown())
    T.eq(TM.win:GetAlpha(), 1)
    T.falsy(TM.tab:IsShown(), "no slide tab on its own window")
    T.near(_G.DaylightUIInfoPanelEdge:GetWidth(), 0, 0.01, "the buffs stay put")
    stub.LeaveCombat()
    threatSettle()
    -- Unlocked: its sample shows, and the corner grip sizes it.
    T.falsy(TM.grip:IsShown(), "locked: no grip")
    DUI.Movers.Unlock()
    threatSettle()
    T.truthy(TM.clip:IsShown(), "unlocked: its sample, to see what you're moving")
    T.truthy(TM.grip:IsShown(), "and a grip in the corner")
    local f, M = TM.freeFrame, TM.MARGIN
    TM.grip:GetScript("OnMouseDown")(TM.grip)
    local step = DUI:Get("InfoPanel", "threat.rowHeight") + stub.infopanel.Meter.SPACING
    f:SetSize(220 + 2 * M, TM.MinHeight() + 2 * step + 3 + 2 * M)
    TM.grip:GetScript("OnMouseUp")(TM.grip)
    T.eq(DUI:Get("InfoPanel", "threat.width"), 220, "the new width kept")
    T.eq(DUI:Get("InfoPanel", "threat.rows"), 4, "as many rows as fit")
    T.eq(TM.win:GetWidth(), 220)
    f:SetSize(5000, 10)
    TM.grip:GetScript("OnMouseUp")(TM.grip)
    T.eq(DUI:Get("InfoPanel", "threat.width"), TM.FREE_MAX_W, "within its limits")
    T.eq(DUI:Get("InfoPanel", "threat.rows"), TM.ROWS_RANGE[1])
    DUI.Movers.Lock()
    threatSettle()
    T.falsy(TM.grip:IsShown())
    T.falsy(TM.clip:IsShown(), "locked again: away")
    DUI:Set("InfoPanel", "threat.at", "left")
    stub.RunTimers()
    T.truthy(e.suspended, "docked again")
    T.eq(TM.host, P.panel)
    stub.SetGroup(false)
end)

T.test("threat meter: docked, it shows only while the damage meter is open", function()
    local DUI = login()
    local TM = stub.infopanel.ThreatMeter
    DUI.SetTestMode(true)
    stub.RunTimers()
    threatSettle()
    T.truthy(TM.clip:IsShown(), "meter open: out")
    T.truthy(TM.tab:IsShown())
    DUI:Set("InfoPanel", "meter.enabled", false)
    stub.RunTimers()
    threatSettle()
    T.falsy(TM.clip:IsShown(), "meter folded: gone")
    T.falsy(TM.tab:IsShown(), "tab and all")
    DUI:Set("InfoPanel", "threat.at", "free")
    stub.RunTimers()
    threatSettle()
    T.truthy(TM.clip:IsShown(), "its own window doesn't need the meter")
    DUI:Set("InfoPanel", "threat.at", "left")
    DUI:Set("InfoPanel", "meter.enabled", true)
    stub.RunTimers()
    threatSettle()
    T.truthy(TM.tab:IsShown(), "meter back: so is it")
    DUI.SetTestMode(false)
end)

T.test("threat meter: the window is as tall as the rows it shows", function()
    local DUI = login()
    local TM = stub.infopanel.ThreatMeter
    threatParty()
    stub.EnterCombat()
    threatSettle()
    TM.Draw()
    local g = TM.geo
    local rowStep = g.rowH + stub.infopanel.Meter.SPACING
    T.near(TM.win:GetHeight(), g.H - 3 * rowStep, 1e-6, "three members: three rows, no empty space")
    stub.units.target = nil
    TM.Draw()
    T.near(TM.win:GetHeight(), g.H - 4 * rowStep, 1e-6, "no target: a small body, never a sliver")
    T.truthy(TM.win.empty:IsShown())
    T.eq(TM.win.header:GetText(), "", "no name over it")
    stub.LeaveCombat()
    stub.SetGroup(false)
end)

T.test("threat meter: its own size, fade and window, and it follows a separate meter", function()
    local DUI = login()
    local TM, P = stub.infopanel.ThreatMeter, stub.infopanel.Panel
    T.truthy(DUI.Fade.State("InfoPanel.threat"), "its own fade")
    DUI:Set("InfoPanel", "threat.width", 200)
    DUI:Set("InfoPanel", "threat.rows", 4)
    DUI:Set("InfoPanel", "threat.rowHeight", 20)
    T.eq(TM.win:GetWidth(), 200)
    local T0 = TM.geo.H
    DUI:Set("InfoPanel", "threat.rows", 5)
    T.near(TM.geo.H - T0, 21, 1e-6, "a row more: one bar and its gap taller")
    DUI:Set("InfoPanel", "meter.detached", true)
    T.eq(TM.host, P.meterFrame, "hangs off the separate meter window")
    DUI:Set("InfoPanel", "meter.detached", false)
    T.eq(TM.host, P.panel)
end)

T.test("info panel: warm text, the accent on what a glance needs", function()
    login()
    local Style, INK = DaylightUI.Style, DaylightUI.Style.INK
    local function is(fs, c, why)
        local r, g, b = fs:GetTextColor()
        T.near(r, c[1], 0.01, why); T.near(g, c[2], 0.01, why); T.near(b, c[3], 0.01, why)
    end
    T.deq(stub.infopanel.DataTexts.LABEL, INK.LABEL, "data text words: warm label")
    -- Threat meter: the mob's name soft white, its icon in the accent, and
    -- "No target" in the label color.
    local TM = stub.infopanel.ThreatMeter
    T.truthy(TM.win, "threat meter built")
    is(TM.win.header, INK.TEXT, "the mob's name: soft white")
    T.rgb({ TM.view.icon:GetVertexColor() }, { Style.Accent() }, "its icon in the accent")
    is(TM.win.empty, INK.LABEL, "no target: label")
    DaylightUI:Set("general", "accent", "custom")
    DaylightUI:Set("general", "accentColor", { 0.2, 0.9, 0.3 })
    stub.RunTimers()
    T.rgb({ TM.view.icon:GetVertexColor() }, { Style.Accent() }, "the icon follows an accent change")
    -- The meter's header: the mode in the label's tan.
    is(stub.infopanel.Meter.header.mode, INK.LABEL, "the mode's word")
    -- Breakdown: the mode name pops.
    local B = stub.infopanel.Breakdown
    stub.meter.sources = { { name = "Me", classFilename = "MAGE", totalAmount = 40, isLocalPlayer = true } }
    stub.infopanel.Meter.Draw()
    B.Show(bars()[1])
    is(B.total, { Style.Accent() }, "the breakdown's total pops")
    is(B.sub, INK.LABEL, "its mode and fight: a label")
    -- Minimap: clock, framerate and coordinates are values; the zone wears its PvP color.
    local Map = stub.infopanel.Minimap
    is(Map.clock.text, INK.VALUE, "clock")
    is(Map.fps.text, INK.VALUE, "fps")
    is(Map.coords.text, INK.VALUE, "coords")
    _G.GetMinimapZoneText = function() return "Hillsbrad" end
    _G.C_PvP = _G.C_PvP or {}
    local kind = "contested"
    _G.C_PvP.GetZonePVPInfo = function() return kind end
    Map.UpdateLocation()
    local d = DaylightUI.Motion.Driver()
    T.truthy(d and d:GetScript("OnUpdate"), "a new place: its color blends over")
    stub.RunOnUpdate(d, 1)
    is(Map.location.text, INK.WARN, "contested zone: amber")
    kind = nil
    Map.UpdateLocation()
    is(Map.location.text, INK.VALUE, "no PvP kind: value")
    -- Each map text takes its own size and color from the options.
    kind = "contested"
    DaylightUI:Set("InfoPanel", "map.location.colorBy", "custom")
    DaylightUI:Set("InfoPanel", "map.location.color", { 0.2, 0.4, 0.6 })
    DaylightUI:Set("InfoPanel", "map.coords.color", { 0.6, 0.4, 0.2 })
    DaylightUI:Set("InfoPanel", "map.clock.color", { 0.3, 0.3, 0.9 })
    DaylightUI:Set("InfoPanel", "map.coords.textSize", 16)
    DaylightUI:Set("InfoPanel", "map.location.textSize", 14)
    stub.RunTimers()
    is(Map.location.text, { 0.2, 0.4, 0.6 }, "zone name in one color, PvP kind ignored")
    is(Map.coords.text, { 0.6, 0.4, 0.2 }, "coords color")
    is(Map.clock.text, { 0.3, 0.3, 0.9 }, "clock color")
    T.eq(Map.coords:GetHeight(), 17, "coords frame grows with its size")
    T.eq(Map.location:GetHeight(), 15, "zone frame grows with its size")
    local _, size = Map.coords.text:GetFont()
    T.eq(size, 16, "coords text size")
    _G.C_PvP.GetZonePVPInfo = nil
    _G.GetMinimapZoneText = nil
end)

T.test("info panel: the XP gain number wears the bar's color, lifted", function()
    login()
    local XP, G = stub.infopanel.XP, stub.infopanel.XPGain
    xpWidth(XP)
    setXP(300); setXP(420)
    local r, g, b = G.riser.text:GetTextColor()
    local er, eg, eb = G.TextColor(XP)
    T.near(r, er, 0.01); T.near(g, eg, 0.01); T.near(b, eb, 0.01)
    T.truthy(not (math.abs(r - g) < 0.03 and math.abs(g - b) < 0.03), "not a neutral gray or white")
end)

-- ---------------------------------------------------------------------
-- Reporting the meter
-- ---------------------------------------------------------------------

local function reportWorld()
    stub.sent = {}
    _G.SendChatMessage = function(msg, chat, lang, target) stub.sent[#stub.sent + 1] = { msg, chat, target } end
    stub.meter.sources = {
        { name = "Thrall", classFilename = "SHAMAN", totalAmount = 6000, amountPerSecond = 100 },
        { name = "Jaina", classFilename = "MAGE", totalAmount = 3000, amountPerSecond = 50 },
        { name = "Uther", classFilename = "PALADIN", totalAmount = 1000, amountPerSecond = 17 },
    }
    stub.meter.fights = { { sessionID = 7, name = "Hogger", durationSeconds = 83 } }
end

local function openReport()
    local M, area = stub.infopanel.Meter, stub.infopanel.Panel.meterArea
    area:GetScript("OnEnter")(area)
    local b = M.header.buttons.report
    T.eq(b.kind, "report")
    b:GetScript("OnClick")(b)
    return stub.infopanel.Report.frame
end

local function chip(f, key)
    for _, c in ipairs(f.chips) do if c.channel.key == key then return c end end
end

T.test("meter report: the Report button opens a window, Send posts the top lines and closes it", function()
    login()
    reportWorld()
    stub.inGroup = true
    local f = openReport()
    T.truthy(f:IsShown())
    T.truthy(chip(f, "party"):IsShown(), "party while in a group")
    T.falsy(chip(f, "raid"):IsShown(), "no raid outside one")
    T.truthy(chip(f, "party").on, "picked: the group you're in")
    T.falsy(f.name:IsShown(), "the name box only for a whisper")
    T.falsy(f.send.off)
    f.lines.control.Refresh()
    T.eq(f.lines.control.slider:GetValue(), 5, "five lines by default")
    local slider = f.lines.control.slider
    slider:GetScript("OnValueChanged")(slider, 2)
    f.send:GetScript("OnClick")(f.send)
    T.eq(#stub.sent, 3, "the header and two lines")
    T.eq(stub.sent[1][1], "Damage done: Hogger (1:23)")
    T.eq(stub.sent[2][1], "1. Thrall 6K (100/s, 60%)")
    T.eq(stub.sent[3][1], "2. Jaina 3K (50/s, 30%)")
    T.eq(stub.sent[1][2], "PARTY")
    T.eq(DaylightUI:Get("InfoPanel", "report.lines"), 2, "the line count is kept")
    T.falsy(DaylightUI.Motion.Shown(f), "closes once sent")
end)

T.test("meter report: a whisper goes to the name typed, your target's at first", function()
    login()
    reportWorld()
    stub.SetUnits{ target = { name = "Garrosh", isPlayer = true } }
    local f = openReport()
    chip(f, "whisper"):GetScript("OnClick")(chip(f, "whisper"))
    T.eq(DaylightUI:Get("InfoPanel", "report.channel"), "whisper")
    T.truthy(f.name:IsShown())
    T.eq(f.name:GetText(), "Garrosh")
    f.send:GetScript("OnClick")(f.send)
    T.eq(stub.sent[1][2], "WHISPER")
    T.eq(stub.sent[1][3], "Garrosh")
end)

T.test("meter report: Send waits for the fight's end and refuses sample data", function()
    local DUI = login()
    reportWorld()
    local f = openReport()
    stub.EnterCombat()
    f:GetScript("OnEvent")(f, "PLAYER_REGEN_DISABLED")
    T.truthy(f.send.off, "off in a fight")
    T.eq(f.send.text:GetText(), "After the fight")
    f.send:GetScript("OnClick")(f.send)
    T.eq(#stub.sent, 0)
    stub.LeaveCombat()
    f:GetScript("OnEvent")(f, "PLAYER_REGEN_ENABLED")
    T.falsy(f.send.off)
    DUI.SetTestMode(true)
    stub.infopanel.Report.Refresh()
    T.truthy(f.send.off, "not the sample raid")
    DUI.SetTestMode(false)
end)
