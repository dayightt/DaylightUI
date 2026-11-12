-- Social window, Requests page: pending friend requests, newest first, each with Accept
-- and Decline on its line. Accept runs a soft light across and the line eases out as the
-- game takes it; Decline offers Decline or Block (the game's two options). The count
-- shows on the tab in the accent (Window.Header).

local _, DUI = ...
DUI.Social = DUI.Social or {}
local ns = DUI.Social
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win

local Requests = {}
ns.Requests = Requests

Requests.TOP = 8
Requests.ROW = 44
Requests.BUTTON = 22

local function W() return DUI.Widgets end
local function Data() return ns.Data end

local function makeRow(parent)
    local b = CreateFrame("Frame", nil, parent)
    b.hi = b:CreateTexture(nil, "BACKGROUND")
    b.hi:SetTexture(Win.Parts.WHITE)
    local c = Win.Parts.HI
    b.hi:SetVertexColor(c[1], c[2], c[3], c[4])
    b.hi:SetAllPoints(b)
    b.hi:Hide()
    b.shine = b:CreateTexture(nil, "OVERLAY", nil, 7)
    b.shine:SetTexture(Win.Parts.WHITE)
    b.shine:SetBlendMode("ADD")
    b.shine:SetHeight(Requests.ROW)
    b.shine:Hide()
    b.accept = W().Button(b, L["Accept"], Requests.BUTTON)
    b.accept.FitWidth(64)
    b.accept.text:SetTextColor(Win.Parts.YES[1], Win.Parts.YES[2], Win.Parts.YES[3], 1)
    b.accept:SetPoint("RIGHT", b, "RIGHT", -8, 0)
    b.decline = W().Button(b, DECLINE or L["Decline"], Requests.BUTTON)
    b.decline.FitWidth(64)
    b.decline:SetPoint("RIGHT", b.accept, "LEFT", -6, 0)
    b.name = Style.Text(b, Style.SIZE.body, "LEFT")
    b.name:SetPoint("TOPLEFT", b, "TOPLEFT", 10, -8)
    b.name:SetPoint("RIGHT", b.decline, "LEFT", -10, 0)
    b.name:SetWordWrap(false)
    Style.InkText(b.name, "VALUE")
    b.sub = Style.Text(b, Style.SIZE.small, "LEFT")
    b.sub:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -3)
    Style.InkText(b.sub, "LABEL")
    b:EnableMouse(true)
    b:SetScript("OnEnter", function(self) Win.Parts.Light(self.hi, true) end)
    b:SetScript("OnLeave", function(self) Win.Parts.Light(self.hi, false) end)
    return b
end

-- Removing from the list: the light, then the line eases out, then the game call.
local function leave(b, shine, act)
    b.accept.SetOff(true)
    b.decline.SetOff(true)
    if shine then Win.Parts.Shine(b) end
    local M = DUI.Motion
    if not M then return act() end
    M.Tween(b, 1, 0, M.NORMAL, function(a) b:SetAlpha(a) end, act)
end

function Requests.Menu(owner, r, b)
    W().OpenMenu(owner, { "decline", "block" }, { decline = DECLINE or L["Decline"], block = L["Block requests from them"] }, nil,
        function(k)
            if k == "block" then leave(b, false, function() Data().Block(r.id) end)
            else leave(b, false, function() Data().Decline(r.id) end) end
        end, 200)
end

function Requests.Render(keep)
    local page = Requests.page
    if not (page and page:IsShown()) then return end
    local s = page.stack
    local at = keep and s:Scrolled()
    local list = Data().Invites()
    s:Begin()
    for _, r in ipairs(list) do
        local b = s:Piece("request", makeRow, Requests.ROW, 2)
        b:SetAlpha(1)
        b.name:SetText(r.account)
        b.sub:SetText(r.age and string.format(L["Sent %s"], Data().Ago(r.age)) or "")
        b.accept.SetOff(false)
        b.decline.SetOff(false)
        b.accept:SetScript("OnClick", function() leave(b, true, function() Data().Accept(r.id) end) end)
        b.decline:SetScript("OnClick", function(self) Requests.Menu(self, r, b) end)
        Win.Parts.Light(b.hi, b:IsMouseOver() == true, true)
    end
    page.pieces = s:End()
    if at then s:ScrollTo(at) end
    page.note:SetShown(#list == 0)
end

function Requests.Build(page)
    Requests.page = page
    page.stack = Win.Parts.Stack(page, { top = Requests.TOP, bottom = 12 })
    page.note = Style.Text(page, Style.SIZE.body, "CENTER")
    page.note:SetPoint("CENTER", page, "CENTER", 0, 0)
    page.note:SetText(L["No requests yet."])
    Style.InkText(page.note, "LABEL")
    page.note:Hide()
    -- The window (Social/Window.lua) listens for the invite events, so the tab count stays
    -- current whatever page is shown.
end

function Requests.Fill() Requests.Render() end

function Requests.Pieces(page)
    local out = {}
    for i, p in ipairs(page.pieces or {}) do
        if i > 12 then break end
        out[#out + 1] = p
    end
    return out
end
