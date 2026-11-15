-- The game's own Mail window, in the Daylight UI look, for players who pick it over
-- Daylight UI's (Win.Swap). Never walked while Daylight UI's window covers it.

local _, ns = ...
local Engine = ns.Engine

local function covered(kind)
    if DaylightUI.mailMogul == true then return true end
    local W = DaylightUI.Mail and DaylightUI.Mail.Window
    return type(W) == "table" and type(W.Covers) == "function" and W.Covers(kind) == true
end

-- Inbox and send, one window with two tabs.
Engine.Window({ key = "mail", pack = "social", frame = "MailFrame", watch = true,
    skip = function() return covered("mail") end })

-- An opened letter, whose text is printed for parchment. Opening another letter
-- while one is open refills and recolors it without showing the window again, so
-- its text is made light again after.
local letterHooked = false
Engine.Window({ key = "openmail", pack = "social", frame = "OpenMailFrame", light = true,
    skip = function() return covered("letter") end,
    after = function(Kit, f)
        if letterHooked or type(InboxFrame_OnClick) ~= "function" then return end
        letterHooked = true
        hooksecurefunc("InboxFrame_OnClick", function()
            if not covered("letter") then Kit.LightAll(f, nil, 8, true) end
        end)
    end })
