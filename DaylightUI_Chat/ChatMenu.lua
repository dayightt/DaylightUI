-- The game's chat menu (language, emotes, say, yell...). The side buttons are
-- hidden by default, so the game's own menu button sits invisibly over an icon
-- in the Daylight box's header and takes the click itself.
-- A menu of our own can't replace it: the language lives on the game's edit box,
-- and setting it from addon code taints everything the box sends. Picked with a
-- real click in the game's menu, it stays clean.
--
-- The button is seated only once the game has set your language. Showing it runs
-- its OnShow from our code, and with no language yet that OnShow writes the first
-- one (ChatFrameMenuButtonMixin.ValidateSelectedLanguage). For the same reason it
-- stays shown and only its mouse input is toggled.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local ChatMenu = {}
ns.ChatMenu = ChatMenu

local seat, home, icon
local mouse

local function box()
    local cf = _G.DEFAULT_CHAT_FRAME
    return type(cf) == "table" and cf.editBox or nil
end

local function forward(script)
    return function()
        local run = icon and icon:GetScript(script)
        if run then run(icon) end
    end
end

local function setMouse(btn, on)
    if mouse == on then return end
    mouse = on
    btn:EnableMouse(on)
end

local function sit(btn, want)
    icon = want
    if not seat then
        seat = CreateFrame("Frame", nil, UIParent)
        home = btn:GetParent()
        btn:HookScript("OnEnter", forward("OnEnter"))
        btn:HookScript("OnLeave", forward("OnLeave"))
        btn:HookScript("OnMouseDown", function()
            if icon then DUI.Motion.Bump(icon.icon, 0.85) end
            DUI.Sound.Play("click")
        end)
    end
    seat:SetFrameStrata(icon:GetFrameStrata())
    seat:SetFrameLevel(icon:GetFrameLevel() + 2)
    seat:ClearAllPoints()
    seat:SetAllPoints(icon)
    btn:SetParent(seat)
    btn:ClearAllPoints()
    btn:SetAllPoints(seat)
    btn:SetFrameStrata(icon:GetFrameStrata())
    btn:SetFrameLevel(seat:GetFrameLevel() + 1)
    btn:SetAlpha(0)
end

-- Handed back only when "Show the chat side buttons" is on. Otherwise it stays
-- on the seat with mouse input off.
local function leave(btn)
    icon = nil
    setMouse(btn, false)
    if DUI:Get("Chat", "hideButtons") then return end
    btn:SetParent(home)
    btn:ClearAllPoints()
    btn:SetPoint("BOTTOM", home, "BOTTOM")
    btn:SetFrameStrata("MEDIUM")
    btn:SetAlpha(1)
    setMouse(btn, true)
end

function ChatMenu.Pass()
    local btn = _G.ChatFrameMenuButton
    if type(btn) ~= "table" then return end
    local want = ns.Box.MenuIcon()
    if want then
        local eb = box()
        if not icon and (not eb or type(eb.languageID) == "nil") then return end
        if icon ~= want then sit(btn, want) end
        setMouse(btn, want:IsVisible() and true or false)
    elseif icon then
        leave(btn)
    end
end

-- Icon label, plus the current language when you know more than one.
function ChatMenu.Tip()
    local eb = box()
    local count = _G.GetNumLanguages and _G.GetNumLanguages() or 0
    if eb and eb.language and count > 1 then
        return string.format(L["Chat menu: emotes and languages (speaking %s)"], eb.language)
    end
    return L["Chat menu: emotes and languages"]
end
