local stub = require("stub")

-- The level-up animation (QoL/LevelUp.lua): our "Sunrise" on PLAYER_LEVEL_UP,
-- and the game's level-up banner set to alpha 0 while it shows.

local function login(levelUp)
    stub.Load({ qol = true, before = function()
        local m = CreateFrame("Frame", "EventToastManagerFrame", UIParent)
        m:EnableMouse(true)
        m:Hide()
    end })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    if levelUp ~= nil then DaylightUI:Set("QoL", "levelUp", levelUp) end
    return stub.qol.LevelUp
end

local function settle()
    local d = DaylightUI.Motion.Driver()
    for _ = 1, 120 do
        if not (d and d:GetScript("OnUpdate")) then return end
        stub.RunOnUpdate(d, 1 / 30)
    end
end

T.test("level up: plays with the new level and the gains, then goes away", function()
    login()
    stub.FireEvent("PLAYER_LEVEL_UP", 11, 18, 15, 1, 0, 2, 0, 1, 0)
    local f = _G.DaylightUILevelUp
    T.truthy(f and f:IsShown(), "shown on a level up")
    T.eq(f.new:GetText(), "11")
    T.eq(f.old:GetText(), "10")
    local good = DaylightUI.Win.Parts.Hex(DaylightUI.Style.INK.GOOD)
    T.truthy(f.gains:GetText():find(good .. "+18|r Health", 1, true), "health gain, the number green: " .. tostring(f.gains:GetText()))
    T.truthy(f.gains:GetText():find(good .. "+2|r Strength", 1, true), "strength gain")
    T.falsy(f.gains:GetText():find("Agility", 1, true), "no zero gains")
    T.eq(f.talents:GetText(), "1 new talent point")
    T.falsy(f:IsMouseEnabled(), "takes no clicks")
    stub.RunTimers()
    settle()
    T.falsy(f:IsShown(), "gone after the hold")
end)

T.test("level up: plays in combat too", function()
    login()
    stub.EnterCombat()
    stub.FireEvent("PLAYER_LEVEL_UP", 20, 30, 0, 0, 0, 0, 0, 0, 0)
    T.truthy(_G.DaylightUILevelUp:IsShown(), "shown in a fight")
    stub.RunTimers(); settle()
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("level up: switched off, nothing plays", function()
    login(false)
    stub.FireEvent("PLAYER_LEVEL_UP", 11, 18, 15, 1, 0, 2, 0, 1, 0)
    local f = _G.DaylightUILevelUp
    T.falsy(f and f:IsShown(), "not shown")
end)

T.test("level up: the preview and /dui levelup play it", function()
    local LU = login()
    LU.Preview()
    T.truthy(_G.DaylightUILevelUp:IsShown())
    stub.RunTimers(); settle()
    DaylightUI.RunCommand("levelup")
    T.truthy(_G.DaylightUILevelUp:IsShown(), "the command plays it")
end)

T.test("level up: the game's level-up banner is blanked, its other toasts are not", function()
    login()
    local m = _G.EventToastManagerFrame
    m.currentDisplayingToast = { toastInfo = { eventType = Enum.EventToastEventType and Enum.EventToastEventType.LevelUp or 0 } }
    m:Show()
    T.eq(m:GetAlpha(), 0, "level-up toast hidden")
    T.falsy(m:IsMouseEnabled(), "and takes no clicks")
    -- The game moves on to its next toast without hiding.
    m.currentDisplayingToast = { toastInfo = { eventType = 1 } }
    stub.qol.LevelUp.CheckToast()   -- what the watcher runs every frame
    T.eq(m:GetAlpha(), 1, "the next toast shows")
    T.truthy(m:IsMouseEnabled(), "mouse back")
    m:Hide()
    T.eq(m:GetAlpha(), 1)
end)

T.test("level up: switched off, the game's banner stays", function()
    login(false)
    local m = _G.EventToastManagerFrame
    m.currentDisplayingToast = { toastInfo = { eventType = 0 } }
    m:Show()
    T.eq(m:GetAlpha(), 1, "the game's banner shows")
end)

-- Players with several monitors put it on their game screen: it has an unlock
-- handle, and untouched it sits exactly where it always did.
T.test("level up: an unlock handle; untouched it stays where it was, moved it follows", function()
    local LU = login()
    local M = DaylightUI.Movers
    DaylightUI.DB.General().scale = 1.25
    M.ApplyAll()
    local holder = _G.DaylightUILevelUpHolder
    T.truthy(M.Get("qol.levelup") and holder, "a mover and its holder")
    T.near(holder:GetScale(), M.Scale(), 0.001, "the holder takes the scale the banner had")
    local p, rel, rp, x, y = holder:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(rel, UIParent); T.eq(rp, "TOP"); T.eq(x, 0)
    T.near(y, LU.Y, 0.001, "the old spot, in the banner's own scale")
    stub.FireEvent("PLAYER_LEVEL_UP", 11, 18, 15, 1, 0, 2, 0, 1, 0)
    local f = _G.DaylightUILevelUp
    T.eq(f:GetParent(), holder, "the banner inside it")
    local fp, frel, frp, fx, fy = f:GetPoint(1)
    T.eq(fp, "CENTER"); T.eq(frel, holder); T.eq(frp, "CENTER"); T.eq(fx, 0); T.eq(fy, 0)
    DaylightUI.DB.Positions()["qol.levelup"] = { 400, -100 }
    M.Apply("qol.levelup")
    local _, rel2, rp2, x2, y2 = holder:GetPoint(1)
    T.eq(rel2, UIParent); T.eq(rp2, "CENTER")
    T.near(x2, 400 / M.Scale(), 0.001, "moved")
    T.near(y2, -100 / M.Scale(), 0.001)
    M.Unlock()
    T.truthy(M.Handle("qol.levelup") and M.Handle("qol.levelup"):IsShown(), "unlock shows its handle")
    M.Lock()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
