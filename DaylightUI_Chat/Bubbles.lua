-- Restyles the speech bubbles over units' heads with the Daylight frame and font.
-- The game's bubbles live in the world layer with the nameplates, so nothing is
-- built on them: a frame on UIParent follows each one and shows its words, and
-- the game's own balloon is only faded out while that frame stands in for it.
-- Addons can't touch bubbles inside instances, so those are left alone.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style
local Motion = DUI.Motion

local Bubbles = {}
ns.Bubbles = Bubbles

-- Wrap width at text size 12; it grows with the size.
Bubbles.WRAP = 240
Bubbles.PAD = 8

local WEAK = { __mode = "k" }
local overlay = setmetatable({}, WEAK)  -- the game's bubble -> the frame drawing it
local hooked = setmetatable({}, WEAK)
local shown = setmetatable({}, WEAK)    -- bubbles drawn by a frame right now
local childOf = setmetatable({}, WEAK)  -- the bubble's balloon, kept to hand it back

local function on()
    local mod = ns.module
    return mod and mod.db and mod.db.bubbles == true
end

-- Every touch of the game's frame goes through pcall: the client can make a
-- pooled bubble forbidden under us on a zone change, and any call on it errors then.
local function parts(outer)
    if outer:IsForbidden() then return nil end
    local child = outer:GetChildren()
    if type(child) ~= "table" or child:IsForbidden() then return nil end
    local fs = child.String
    if type(fs) ~= "table" then
        for i = 1, select("#", child:GetRegions()) do
            local r = select(i, child:GetRegions())
            if r:GetObjectType() == "FontString" then fs = r; break end
        end
    end
    if type(fs) ~= "table" then return nil end
    return child, fs, outer:IsShown()
end

local function setGameAlpha(child, a)
    if child then pcall(child.SetAlpha, child, a) end
end

local function newOverlay()
    local f = CreateFrame("Frame", nil, UIParent)
    -- Under the rest of the UI, as the game's bubbles are.
    f:SetFrameStrata("BACKGROUND")
    f:EnableMouse(false)
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetPoint("CENTER")
    f.text:SetWordWrap(true)
    f:Hide()
    Style.Shell(f)
    return f
end

local function layout(f)
    local size = (ns.module and ns.module.db and ns.module.db.bubbleSize) or 12
    Style.SetFace(f.text, Style.FontFile(ns.MEDIA.font), size, Style.Outline())
    local wrap = Bubbles.WRAP * size / 12
    f.text:SetWidth(wrap)
    local w = f.text.GetUnboundedStringWidth and f.text:GetUnboundedStringWidth() or f.text:GetStringWidth()
    if type(w) ~= "number" or w > wrap then w = wrap end
    f.text:SetWidth(math.ceil(w) + 1)
    local h = f.text:GetStringHeight()
    if type(h) ~= "number" then h = size end
    f:SetSize(f.text:GetWidth() + 2 * Bubbles.PAD, h + 2 * Bubbles.PAD)
end

-- Gives the game its bubble back and lets the stand-in fade away.
local function release(outer, child)
    local f = overlay[outer]
    shown[outer] = nil
    setGameAlpha(child or childOf[outer], 1)
    if not f or not f:IsShown() then return end
    f.token = (f.token or 0) + 1
    local token = f.token
    if not Motion.On() then f:Hide(); return end
    Motion.Fade(f, f:GetAlpha(), 0, Motion.FAST)
    C_Timer.After(Motion.FAST, function()
        if f.token == token then f:Hide() end
    end)
end

local function draw(outer)
    if not on() then return end
    local ok, child, fs, isShown = pcall(parts, outer)
    if not ok or not child then return end
    if not isShown then return release(outer, child) end
    local okText, text = pcall(fs.GetText, fs)
    -- Secret words can be shown but not measured: the game's own bubble stays.
    if not okText or type(text) ~= "string" or DUI.IsSecret(text) or text == "" then
        return release(outer, child)
    end
    local f = overlay[outer]
    if not f then
        f = newOverlay()
        overlay[outer] = f
    end
    local was = shown[outer] and f:IsShown()
    if was and f.said == text then return end
    f.said = text
    f.text:SetText(text)
    -- The game colors a bubble by its kind of chat; keep that color.
    local okC, r, g, b = pcall(fs.GetTextColor, fs)
    if okC and type(r) == "number" and not (DUI.IsSecret(r) or DUI.IsSecret(g) or DUI.IsSecret(b)) then
        f.text:SetTextColor(r, g, b)
    else
        f.text:SetTextColor(unpack(Style.INK.TEXT))
    end
    f.token = (f.token or 0) + 1
    if not was then f:SetAlpha(0) end
    f:Show()
    layout(f)
    f:ClearAllPoints()
    if not pcall(f.SetPoint, f, "CENTER", child, "CENTER", 0, 0) then
        f:Hide()
        return release(outer, child)
    end
    shown[outer] = true
    childOf[outer] = child
    if not was then Motion.Fade(f, 0, 1, Motion.FAST) end
    setGameAlpha(child, 0)
end

local function hook(outer)
    if hooked[outer] then return end
    hooked[outer] = true
    pcall(outer.HookScript, outer, "OnShow", function(self) DUI.SafeCall(draw, self) end)
    pcall(outer.HookScript, outer, "OnHide", function(self) DUI.SafeCall(release, self) end)
end

function Bubbles.DressAll()
    if not on() then return end
    if type(C_ChatBubbles) ~= "table" or type(C_ChatBubbles.GetAllChatBubbles) ~= "function" then return end
    -- Without forbidden ones: those can't be read or faded.
    local ok, list = pcall(C_ChatBubbles.GetAllChatBubbles)
    if not ok or type(list) ~= "table" then return end
    for _, outer in pairs(list) do
        if type(outer) == "table" then
            hook(outer)
            DUI.SafeCall(draw, outer)
        end
    end
end

-- Hands every bubble back, or lays the shown ones out again after a change.
function Bubbles.Refresh()
    for outer in pairs(shown) do
        if on() then
            local f = overlay[outer]
            if f then layout(f) end
        else
            release(outer)
        end
    end
end

function Bubbles.ReleaseAll()
    for outer in pairs(shown) do release(outer) end
end

-- For the tests: the frame drawing a game bubble.
function Bubbles.OverlayOf(outer) return overlay[outer] end

-- Say, yell and party lines (and monster versions) show bubbles; whispers, guild
-- and the rest never do.
Bubbles.EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_PARTY" }

local built = false
function Bubbles.Build(mod)
    ns.module = mod
    if built then return end
    built = true
    -- A burst of lines in one frame (a whole group talking) looks once, the next
    -- frame; a line in a later frame checks again.
    local queuedAt
    local function onMessage()
        if not on() then return end
        local now = GetTime()
        if queuedAt == now then return end
        queuedAt = now
        C_Timer.After(0, Bubbles.DressAll)
    end
    for _, e in ipairs(Bubbles.EVENTS) do DUI.RegisterEvent(e, onMessage) end
    -- A loading screen can turn the pooled bubbles forbidden: give them back first.
    DUI.RegisterEvent("LOADING_SCREEN_ENABLED", Bubbles.ReleaseAll)
end
