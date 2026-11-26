-- Restyles the speech bubbles over units' heads with the Daylight frame and font.
-- The game's bubbles live in the world layer with the nameplates, so nothing is
-- built on them: a frame on UIParent follows each one and shows its words, and
-- the game's own balloon is only faded out while that frame stands in for it.
-- Addons can't touch bubbles inside instances, so those are left alone.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style
local Motion = DUI.Motion
local Pixel = DUI.Pixel

local Bubbles = {}
ns.Bubbles = Bubbles

-- Wrap width at text size 12; it grows with the size.
Bubbles.WRAP = 240
Bubbles.PAD = 8
-- Square corners with the bottom-right one cut at 45 degrees, as on the rich
-- tooltip's cards. The accent band runs along the bottom, and the tail hangs
-- under it, its tip over the speaker, kept clear of the cut.
Bubbles.CUT = 0.29 -- of the bubble's height, so a bigger bubble keeps the same look
Bubbles.BAND = 4
Bubbles.TAIL_W = 10
Bubbles.TAIL_H = 10
Bubbles.TAIL_AT = 0.17 -- where along the line the tail's edge color is taken

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

local function setting(key, fallback)
    local db = ns.module and ns.module.db
    local v = db and db[key]
    if v == nil then return fallback end
    return v
end

local function face(f)
    local size = setting("bubbleSize", 12)
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
    -- A hairline of its own: the General border width is made for bars and
    -- windows, and at a bubble's size a heavy one swallows the box.
    f.look = { borderPx = 1, cornerPx = 0, flat = true, noBevel = true, shadowAlpha = 0, bgAlpha = setting("bubbleAlpha", 0.92),
        borderColor = { 0.29, 0.27, 0.25 } }
    Style.Shell(f, f.look)
    -- The band lives in the shell, over the background but under the hairline,
    -- so the outline along the cut corner is always drawn on top of it.
    local shell = Style.GetShell(f)
    local bg = shell.bg
    f.band = shell:CreateTexture(nil, "BACKGROUND", nil, 7)
    f.band:SetTexture("Interface\\Buttons\\WHITE8x8")
    f.band:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT")
    f.band:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT")
    -- The tail is a small square with its corner cut away at 45 degrees,
    -- leaving a triangle that points down at the speaker. It is dark like the
    -- bubble, and the band's color runs down its two edges.
    f.tail = CreateFrame("Frame", nil, f)
    f.tail.tex = f.tail:CreateTexture(nil, "ARTWORK")
    f.tail.tex:SetTexture("Interface\\Buttons\\WHITE8x8")
    f.tail.tex:SetAllPoints()
    f.tail.side = f.tail:CreateLine(nil, "OVERLAY")
    f.tail.slope = f.tail:CreateLine(nil, "OVERLAY")
    return f
end

-- The speaker's class pair, its dark end lifted as the class accent does so
-- the line still reads on the dark bubble. nil when it isn't known.
local function classPair(token)
    local G = DUI.Gradients
    if type(token) ~= "string" or not G or not G.Has(token) then return nil end
    local lo, hi = G.RGB(token)
    local k = Style.CLASS_LIFT
    return { lo[1] + (hi[1] - lo[1]) * k, lo[2] + (hi[2] - lo[2]) * k, lo[3] + (hi[3] - lo[3]) * k }, hi
end

-- Read the accent when painting, not at load: the player can change it any time.
local function paint(f)
    local lo, hi
    if setting("bubbleColor", "accent") == "class" then lo, hi = classPair(f.class) end
    local r, g, b
    if lo then
        f.band:SetVertexColor(1, 1, 1, 1)
        f.band:SetGradient("HORIZONTAL", CreateColor(lo[1], lo[2], lo[3], 1), CreateColor(hi[1], hi[2], hi[3], 1))
        local t = Bubbles.TAIL_AT
        r, g, b = lo[1] + (hi[1] - lo[1]) * t, lo[2] + (hi[2] - lo[2]) * t, lo[3] + (hi[3] - lo[3]) * t
    else
        Style.PaintAccent(f.band)
        r, g, b = Style.AccentAt(Bubbles.TAIL_AT)
    end
    local bg = Style.BACKGROUND
    f.tail.tex:SetVertexColor(bg[1], bg[2], bg[3], f.look.bgAlpha)
    -- With the line taken away, the tail's edges are the bubble's own hairline.
    if not f.band:IsShown() then
        local c = f.look.borderColor
        r, g, b = c[1], c[2], c[3]
    end
    f.tail.side:SetColorTexture(r, g, b, 1)
    f.tail.slope:SetColorTexture(r, g, b, 1)
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

-- How far the speaker is from the balloon's middle, read from the game's own
-- tail. The stand-in shares the balloon's scale and center, so the offset
-- carries over as it is. Without a plain reading the balloon is taken to be
-- centered over the speaker.
local function speakerOffset(child)
    local tail = child and child.Tail
    if type(tail) ~= "table" then return 0 end
    local tx = positive(tail, tail.GetCenter)
    local cx = positive(child, child.GetCenter)
    if not tx or not cx then return 0 end
    return tx - cx
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
    local alpha = setting("bubbleAlpha", 0.92)
    if f.look.bgAlpha ~= alpha then
        f.look.bgAlpha = alpha
        Style.Shell(f, f.look)
    end
    local band = Pixel.Snap(f, setting("bubbleBand", Bubbles.BAND))
    local height = h + 2 * Bubbles.PAD + band
    local cut = setting("bubbleCut", true) and Pixel.Snap(f, height * Bubbles.CUT) or 0
    local total = width + 2 * Bubbles.PAD
    f:SetSize(total, height)
    -- Centered over the band, so the words sit in the middle of the dark part.
    f.text:ClearAllPoints()
    f.text:SetPoint("CENTER", f, "CENTER", 0, band / 2)
    f.band:SetHeight(math.max(band, 1))
    f.band:SetShown(band > 0)
    -- The band lies on the cut corner too, so it takes the same mask.
    Style.CutShell(f, cut)
    Style.CutCorner(f, cut, f.band)
    local tw, th = Pixel.Snap(f, Bubbles.TAIL_W), Pixel.Snap(f, Bubbles.TAIL_H)
    f.tail:SetSize(tw, th)
    f.tail:ClearAllPoints()
    -- The tip sits under the speaker, kept inside the bubble and off the cut.
    local tip = total / 2 + speakerOffset(f.balloon)
    tip = math.max(0, math.min(tip, total - cut - tw))
    f.tail:SetPoint("TOPLEFT", f, "BOTTOMLEFT", Pixel.Snap(f, tip), 0)
    Style.CutCorner(f.tail, tw, f.tail.tex)
    local edge = Pixel.Px(f, band > 0 and 2 or 1)
    f.tail.side:SetThickness(edge)
    f.tail.side:SetStartPoint("TOPLEFT", f.tail, edge / 2, 0)
    f.tail.side:SetEndPoint("BOTTOMLEFT", f.tail, edge / 2, 0)
    f.tail.slope:SetThickness(edge)
    f.tail.slope:SetStartPoint("TOPRIGHT", f.tail, 0, 0)
    f.tail.slope:SetEndPoint("BOTTOMLEFT", f.tail, edge / 2, 0)
    paint(f)
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

-- The class of whoever last said each line, so a bubble can wear its speaker's
-- color: the bubble itself doesn't say who is talking. Only a few lines are
-- kept, and only plain ones (chat lockdown makes them secret).
Bubbles.SPEAKERS = 20
local spoken, spokenOrder = {}, {}

function Bubbles.Heard(text, guid)
    if DUI.IsSecret(text) or DUI.IsSecret(guid) then return end
    if type(text) ~= "string" or text == "" or type(guid) ~= "string" or guid == "" then return end
    if type(GetPlayerInfoByGUID) ~= "function" then return end
    local _, class = GetPlayerInfoByGUID(guid)
    if DUI.IsSecret(class) or type(class) ~= "string" then return end
    if spoken[text] == nil then
        spokenOrder[#spokenOrder + 1] = text
        if #spokenOrder > Bubbles.SPEAKERS then
            spoken[table.remove(spokenOrder, 1)] = nil
        end
    end
    spoken[text] = class
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
    f.class = spoken[text]
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
    local function onMessage(event, text, _, _, _, _, _, _, _, _, _, _, guid)
        if event ~= "CHAT_MSG_MONSTER_SAY" and event ~= "CHAT_MSG_MONSTER_YELL" then Bubbles.Heard(text, guid) end
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
