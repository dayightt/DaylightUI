-- Footer gold counts from the old amount to the new one. Runs after
-- Window.UpdateFooter has already printed the new amount, puts the old number
-- back and tweens it. A hidden window and the bank's deposit figure just set it.

local _, ns = ...
local DUI = DaylightUI

local MoneyRoll = {}
ns.MoneyRoll = MoneyRoll

MoneyRoll.GAIN = DUI.Style.INK.MONEY   -- color of the text while gold goes up

local function enabled()
    return ns.Setting("moneyRoll") ~= false and DUI.Motion ~= nil and DUI.Motion.On()
end

local function key(f) return "bagsMoney" .. tostring(f) end

local function print_(f, amount)
    f.rollShown = amount
    f.money:SetText(DUI.MoneyString(amount))
end

local function untint(f)
    if f.rollColor then f.money:SetTextColor(unpack(f.rollColor)); f.rollColor = nil end
end

function MoneyRoll.Step(f)
    if not (f and f.money) or f.spec.updateFooter then return end
    local now = GetMoney and GetMoney() or 0
    local from = f.rollShown
    if from == nil or not f:IsShown() or not enabled() then
        DUI.Motion.Tween(key(f), now, now)   -- stops any tween in progress
        untint(f)
        f.rollTarget = now
        f.rollShown = now
        return
    end
    if now == f.rollTarget then
        -- Refreshed for some other reason: leave the count where it is.
        if from ~= now then print_(f, from) end
        return
    end
    f.rollTarget = now
    if now > from and not f.rollColor then
        f.rollColor = { f.money:GetTextColor() }
        f.money:SetTextColor(MoneyRoll.GAIN[1], MoneyRoll.GAIN[2], MoneyRoll.GAIN[3])
    end
    DUI.Motion.Tween(key(f), from, now, DUI.Motion.SLOW,
        function(v) print_(f, math.floor(v + 0.5)) end,
        function() untint(f) end)
end

if ns.Window then hooksecurefunc(ns.Window, "UpdateFooter", MoneyRoll.Step) end
