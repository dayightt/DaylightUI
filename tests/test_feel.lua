local stub = require("stub")

-- The window kit's motion (Windows/Feel.lua): never slow, never a jump cut.

local function setMotion(on) DaylightUI.DB.General().motion = on end

local function window()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    f:Hide()
    return f
end

local function y(f) return select(5, f:GetPoint(1)) end

-- Runs the shared driver for `s` seconds in small frames.
local function run(Feel, s)
    local d = Feel.Driver()
    local t = 0
    while d and t < s - 1e-9 do
        stub.RunOnUpdate(d, 1 / 60)
        t = t + 1 / 60
    end
end

T.test("feel: a window opens from clear and low, and lands exactly at rest", function()
    local DUI = stub.Load()
    local Feel = DUI.Win.Feel
    local f = window()
    Feel.Open(f)
    T.eq(f:IsShown(), true)
    T.eq(f:GetAlpha(), 0, "starts clear")
    T.near(y(f), -116 - Feel.RISE, 1e-6, "starts low")
    run(Feel, 0.08)
    T.truthy(f:GetAlpha() > 0.45, "readable early: " .. f:GetAlpha())
    run(Feel, Feel.OPEN)
    T.eq(f:GetAlpha(), 1)
    T.eq(y(f), -116, "at rest, no drift")
    T.eq(f:GetNumPoints(), 1)
    T.eq(Feel.Moving(f), false)
end)

T.test("feel: the rise steps in fractions of a pixel (no whole-pixel steps)", function()
    local DUI = stub.Load()
    local Feel = DUI.Win.Feel
    local f = window()
    Feel.Open(f)
    run(Feel, 0.05)
    local v = y(f)
    T.truthy(v ~= math.floor(v), "fractional offset: " .. v)
end)

T.test("feel: closing sinks and fades, counts as closed at once, hides at the end", function()
    local DUI = stub.Load()
    local Feel = DUI.Win.Feel
    local f = window()
    f:Show()
    local done = false
    Feel.Close(f, function() done = true end)
    T.eq(Feel.IsOpen(f), false, "closed from the first frame")
    T.eq(f:IsShown(), true)
    run(Feel, Feel.CLOSE / 2)
    T.truthy(y(f) < -116, "sinking")
    T.truthy(f:GetAlpha() < 1 and f:GetAlpha() > 0)
    run(Feel, Feel.CLOSE)
    T.eq(f:IsShown(), false); T.eq(done, true)
    T.eq(f:GetAlpha(), 1, "ready for the next open")
    T.eq(y(f), -116, "back at rest")
end)

T.test("feel: opened again mid-close, it comes back from where it is (no jump)", function()
    local DUI = stub.Load()
    local Feel = DUI.Win.Feel
    local f = window()
    f:Show()
    Feel.Close(f)
    run(Feel, Feel.CLOSE / 2)
    local a, at = f:GetAlpha(), y(f)
    Feel.Open(f)
    T.eq(Feel.IsOpen(f), true)
    T.near(f:GetAlpha(), a, 1e-6, "same alpha")
    T.near(y(f), at, 1e-6, "same spot")
    run(Feel, Feel.OPEN)
    T.eq(f:IsShown(), true, "the close never finishes")
    T.eq(f:GetAlpha(), 1); T.eq(y(f), -116)
end)

T.test("feel: a re-layout mid-move becomes the new rest spot", function()
    local DUI = stub.Load()
    local Feel = DUI.Win.Feel
    local f = window()
    Feel.Open(f)
    run(Feel, 0.05)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -200)
    run(Feel, Feel.OPEN)
    T.eq(select(4, f:GetPoint(1)), 40)
    T.eq(y(f), -200)
end)

T.test("feel: page pieces lift in one after another, the last within 0.2 s", function()
    local DUI = stub.Load()
    local Feel = DUI.Win.Feel
    local f = window(); f:Show()
    local pieces = {}
    for i = 1, 12 do
        local p = CreateFrame("Frame", nil, f)
        p:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -20 * i)
        pieces[i] = p
    end
    Feel.Stagger(pieces)
    T.eq(pieces[1]:GetAlpha(), 0)
    T.eq(select(5, pieces[2]:GetPoint(1)), -40 - Feel.LIFT, "waits low")
    run(Feel, Feel.STEP)
    T.truthy(pieces[1]:GetAlpha() > pieces[2]:GetAlpha(), "one after another")
    run(Feel, 0.2)
    for i, p in ipairs(pieces) do
        T.eq(p:GetAlpha(), 1, "piece " .. i)
        T.eq(select(5, p:GetPoint(1)), -20 * i, "piece " .. i .. " at rest")
    end
end)

T.test("feel: a piece with two anchors only fades", function()
    local DUI = stub.Load()
    local Feel = DUI.Win.Feel
    local f = window(); f:Show()
    local p = CreateFrame("Frame", nil, f)
    p:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); p:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    Feel.Stagger({ p })
    run(Feel, 0.3)
    T.eq(p:GetNumPoints(), 2); T.eq(p:GetAlpha(), 1)
end)

T.test("feel: motion off snaps everything", function()
    local DUI = stub.Load()
    local Feel = DUI.Win.Feel
    setMotion(false)
    local f = window()
    Feel.Open(f)
    T.eq(f:GetAlpha(), 1); T.eq(y(f), -116); T.eq(Feel.Moving(f), false)
    local done
    Feel.Close(f, function() done = true end)
    T.eq(f:IsShown(), false); T.eq(done, true)
end)

T.test("feel: Settle lands a moving window at rest", function()
    local DUI = stub.Load()
    local Feel = DUI.Win.Feel
    local f = window()
    Feel.Open(f)
    run(Feel, 0.03)
    Feel.Settle(f)
    T.eq(f:GetAlpha(), 1); T.eq(y(f), -116); T.eq(Feel.Moving(f), false)
end)

-- A move's callback that errored was swallowed by a bare pcall, so the player
-- never saw it in BugSack. It reaches the error handler, and the rest still runs.
T.test("feel: an error in a move's callback is reported, and the driver goes on", function()
    local DUI = stub.Load()
    local Feel = DUI.Win.Feel
    local f, g = window(), window()
    Feel.Open(f); Feel.Open(g)
    run(Feel, 1)
    local after = false
    Feel.Close(f, function() error("feel callback boom") end)
    Feel.Close(g, function() after = true end)
    run(Feel, 1)
    local found = false
    for _, e in ipairs(stub.errors) do if e:find("feel callback boom", 1, true) then found = true end end
    T.truthy(found, "the error reaches BugSack")
    T.truthy(after, "the other window still closes")
    T.falsy(f:IsShown())
end)
