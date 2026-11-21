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
-- The holder that last took each balloon. The client pools balloons, so one can
-- move to another holder before its old holder hears about it.
local ownerOf = setmetatable({}, { __mode = "kv" })
-- Balloons left faded because they were locked when handed back. The client
-- unlocks pooled bubbles again outside instances, so they're given back then.
local owed = setmetatable({}, WEAK)

-- Inside an instance the client makes its bubbles forbidden, so they're left to
-- the game there, even pooled ones hooked outside before.
local inside = false

local function on()
    local mod = ns.module
    return not inside and mod and mod.db and mod.db.bubbles == true
end

local function inInstance()
    if type(IsInInstance) ~= "function" then return false end
    local isIn, kind = IsInInstance()
    return isIn == true and kind ~= "none"
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
    return child ~= nil and pcall(child.SetAlpha, child, a)
end

-- Gives a balloon its alpha back, or remembers it for later if it's locked now.
local function giveBack(child)
    if not child then return end
    owed[child] = not setGameAlpha(child, 1) or nil
end

-- Hands back the holder's balloon, unless another holder has taken it since.
local function releaseChild(outer)
    local child = childOf[outer]
    childOf[outer] = nil
    if child and ownerOf[child] == outer then
        ownerOf[child] = nil
        giveBack(child)
    end
end

-- Tries every balloon still owed its alpha.
function Bubbles.PayBack()
    for child in pairs(owed) do giveBack(child) end
end

local function face(f)
    local size = (ns.module and ns.module.db and ns.module.db.bubbleSize) or 12
    Style.SetFace(f.text, Style.FontFile(ns.MEDIA.font), size, Style.Outline())
    return size
end

local function newOverlay()
    local f = CreateFrame("Frame", nil, UIParent)
    -- Under the rest of the UI, as the game's bubbles are.
    f:SetFrameStrata("BACKGROUND")
    f:EnableMouse(false)
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetPoint("CENTER")
    f.text:SetWordWrap(true)
    -- The client refuses words on a font string that has no font yet.
    face(f)
    f:Hide()
    Style.Shell(f)
    return f
end

-- A measurement can be refused or secret while the client places the bubble.
-- Only a plain positive number counts; a missing reading gives `missing`.
local function positive(region, method, missing)
    if type(method) ~= "function" then return missing end
    local ok, v = pcall(method, region)
    if not ok or DUI.IsSecret(v) then return nil end
    if v == nil then return missing end
    if type(v) == "number" and v > 0 then return v end
end

-- The world layer ignores the UI scale, so a stand-in on UIParent would shrink
-- with a small UI scale. Match the balloon's real size instead.
local function matchScale(f)
    local child = f.balloon
    if not child then return end
    local k = positive(child, child.GetEffectiveScale)
    local ui = UIParent:GetEffectiveScale()
    if not k or type(ui) ~= "number" or DUI.IsSecret(ui) or ui <= 0 then return end
    f:SetScale(k / ui)
end

local function layout(f)
    matchScale(f)
    local size = face(f)
    local wrap = Bubbles.WRAP * size / 12
    f.text:SetWidth(wrap)
    -- The unbounded width can read 0 for a fresh line, so the bounded one is
    -- tried next. With neither, the stand-in can't show the words: say so.
    local w = positive(f.text, f.text.GetUnboundedStringWidth)
        or positive(f.text, f.text.GetStringWidth)
    if not w then return false end
    local width = math.ceil(math.min(w, wrap)) + 1
    f.text:SetWidth(width)
    local h = positive(f.text, f.text.GetStringHeight, size)
    if not h then return false end
    f:SetSize(width + 2 * Bubbles.PAD, h + 2 * Bubbles.PAD)
    return true
end

-- Lets go of the game's frame: a stand-in that's fading out stays where it is,
-- pinned to UIParent, so nothing of Daylight UI hangs on the world layer once the
-- bubble is done.
local function unpin(f)
    local ok, x, y = pcall(f.GetCenter, f)
    f:ClearAllPoints()
    if not ok or type(x) ~= "number" or type(y) ~= "number" or DUI.IsSecret(x) or DUI.IsSecret(y) then
        return false
    end
    f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    return true
end

local function hide(f)
    f:Hide()
    f:ClearAllPoints()
end

-- Gives the game its bubble back and lets the stand-in fade away.
local function release(outer)
    local f = overlay[outer]
    shown[outer] = nil
    releaseChild(outer)
    if not f then return end
    if not f:IsShown() then return hide(f) end
    f.token = (f.token or 0) + 1
    local token = f.token
    if not Motion.On() or not unpin(f) then return hide(f) end
    Motion.Fade(f, f:GetAlpha(), 0, Motion.FAST)
    C_Timer.After(Motion.FAST, function()
        if f.token == token then hide(f) end
    end)
end

local function draw(outer)
    if not on() then return end
    local ok, child, fs, isShown = pcall(parts, outer)
    if not ok or not child then return end
    if childOf[outer] and childOf[outer] ~= child then releaseChild(outer) end
    if not isShown then return release(outer) end
    local okText, text = pcall(fs.GetText, fs)
    -- Secret words can be shown but not measured: the game's own bubble stays.
    if not okText or type(text) ~= "string" or DUI.IsSecret(text) or text == "" then
        return release(outer)
    end
    local f = overlay[outer]
    if not f then
        f = newOverlay()
        overlay[outer] = f
    end
    local was = shown[outer] and f:IsShown()
    if was and f.said == text and childOf[outer] == child then return end
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
    f.balloon = child
    if not layout(f) then
        hide(f)
        return release(outer)
    end
    f:ClearAllPoints()
    if not pcall(f.SetPoint, f, "CENTER", child, "CENTER", 0, 0) then
        hide(f)
        return release(outer)
    end
    shown[outer] = true
    childOf[outer] = child
    ownerOf[child] = outer
    if not was then Motion.Fade(f, 0, 1, Motion.FAST) end
    setGameAlpha(child, 0)
    owed[child] = nil
end

local function hook(outer)
    if hooked[outer] then return end
    hooked[outer] = true
    pcall(outer.HookScript, outer, "OnShow", function(self) DUI.SafeCall(draw, self) end)
    pcall(outer.HookScript, outer, "OnHide", function(self) DUI.SafeCall(release, self) end)
end

function Bubbles.DressAll()
    if next(owed) then Bubbles.PayBack() end
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
            if f and not layout(f) then
                hide(f)
                release(outer)
            end
        else
            release(outer)
        end
    end
end

function Bubbles.ReleaseAll()
    for outer in pairs(shown) do release(outer) end
    Bubbles.PayBack()
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
        -- With the skin off, still look when balloons are owed their alpha.
        if not on() and (inside or not next(owed)) then return end
        local now = GetTime()
        if queuedAt == now then return end
        queuedAt = now
        C_Timer.After(0, Bubbles.DressAll)
    end
    for _, e in ipairs(Bubbles.EVENTS) do DUI.RegisterEvent(e, onMessage) end
    -- A loading screen can turn the pooled bubbles forbidden: give them back first.
    DUI.RegisterEvent("LOADING_SCREEN_ENABLED", Bubbles.ReleaseAll)
    inside = inInstance()
    DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        inside = inInstance()
        if inside then Bubbles.ReleaseAll() else Bubbles.PayBack() end
    end)
    -- A pooled bubble can outlive a reload: never leave one faded out.
    DUI.RegisterEvent("PLAYER_LOGOUT", Bubbles.ReleaseAll)
end
