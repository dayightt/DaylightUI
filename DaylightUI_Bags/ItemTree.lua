local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style
local Pixel = DUI.Pixel

-- ItemTree (an optional addon) judges every item: keep it, sell it, use it now.
-- Its own bag marks only find the game's bags and a list of other bag addons,
-- so Daylight UI asks its public API (the global ItemTreeAPI) and draws the
-- answer on its own slots: a dot on the top right corner, search words, and
-- junk selling that leaves alone what ItemTree says to keep. Only this
-- character's live bags and bank: a saved copy belongs to another character,
-- and ItemTree judges for the one logged in.

local IT = {}
ns.ItemTree = IT

IT.VERSION = 1   -- the API version this file reads

-- Which dot a verdict gets, and its color (read at paint time).
IT.MARKS = {
    act = function() return Style.Pop() end,             -- open it, use it now, start its quest
    keep = function() return unpack(Style.INK.GOOD) end,  -- hold on to it
    sell = function() return unpack(Style.INK.MONEY) end, -- vendor, auction or disenchant it
}

-- ItemTree's tags that mean "let it go".
IT.SELL_TAGS = { vendor = true, auction = true, disenchant = true, worthless = true }

local function api()
    local a = rawget(_G, "ItemTreeAPI")
    if type(a) == "table" and a.version == IT.VERSION and type(a.GetItemFacts) == "function" then return a end
    return nil
end

-- ItemTree is loaded and its data is in.
function IT.On()
    local a = api()
    return a ~= nil and a.IsReady() == true
end

function IT.Installed() return api() ~= nil end

-- Facts are asked once per item a frame: a fill pass reads the same item many
-- times (slot, search, groups, junk), and ItemTree's answer can move with any bag
-- change, quest or setting, so nothing is kept past the frame.
local cache, clearing = {}, false
local function clearSoon()
    if clearing then return end
    clearing = true
    C_Timer.After(0, function() clearing = false; wipe(cache) end)
end

-- ItemTree's facts table for an item, or nil (not installed, off, not ready,
-- or a saved copy of another character's bag).
function IT.Facts(itemID, link, bag)
    if type(itemID) ~= "number" or DUI.IsSecret(itemID) or not IT.On() then return nil end
    if bag ~= nil and ns.Saved.Is(bag) then return nil end
    local key = type(link) == "string" and link or itemID
    local f = cache[key]
    if f == nil then
        f = api().GetItemFacts(itemID, type(link) == "string" and link or nil) or false
        cache[key] = f
        clearSoon()
    end
    return f or nil
end

local function has(list, word)
    if type(list) ~= "table" then return false end
    for _, v in ipairs(list) do if v == word then return true end end
    return false
end

-- True when ItemTree says to keep the item (the player's own "never" on it is
-- respected: then it's not a keep).
function IT.IsKeep(facts)
    local k = type(facts) == "table" and facts.keep
    if type(k) ~= "table" or k.off == true or k.never == true then return false end
    return k.marked == true or k.always == true or has(k.tags, "keep")
end

-- "act", "keep", "sell" or nil.
function IT.Verdict(facts)
    local k = type(facts) == "table" and facts.keep
    if type(k) ~= "table" or k.off == true then return nil end
    local a = k.action
    if type(a) == "table" and a.now == true then return "act" end
    if IT.IsKeep(facts) then return "keep" end
    if type(k.tags) == "table" then
        for _, tag in ipairs(k.tags) do
            if IT.SELL_TAGS[tag] then return "sell" end
        end
    end
    return nil
end

-- Whether a bag item must never be sold for the player (Sell junk, auto-sell,
-- the Junk group), while the player leaves that switch on.
function IT.Keeps(info, bag)
    if not info or ns.Setting("itemTreeKeep") == false then return false end
    return IT.IsKeep(IT.Facts(info.itemID, info.hyperlink, bag))
end

-- The dot on a slot's top right corner, made the first time a slot needs one.
local function makeDot(btn, p)
    p.itGlow = btn:CreateTexture(nil, "OVERLAY", nil, 4)
    p.itDot = btn:CreateTexture(nil, "OVERLAY", nil, 5)
    for _, t in ipairs({ p.itGlow, p.itDot }) do
        t:SetColorTexture(1, 1, 1, 1)
        local m = btn:CreateMaskTexture()
        m:SetTexture(DUI.Win.MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(t)
        t:AddMaskTexture(m)
        t:Hide()
    end
end

local function place(btn, p)
    local Items = ns.Items
    local dot = Pixel.Px(btn, Items.DOT_PX)
    p.itDot:ClearAllPoints()
    p.itDot:SetSize(dot, dot)
    p.itDot:SetPoint("CENTER", btn, "TOPRIGHT", 2, 2)
    local glow = Items.GlowSize(btn, dot)
    p.itGlow:ClearAllPoints()
    p.itGlow:SetSize(glow, glow)
    p.itGlow:SetPoint("CENTER", p.itDot, "CENTER", 0, 0)
end

-- Shows, recolors or fades out a slot's dot. A gray item never gets the sell
-- dot: it's already dimmed as junk.
function IT.Paint(btn, info, bag)
    local p = ns.Items.Parts(btn)
    if not p then return end
    local verdict
    if info and ns.Setting("itemTreeMarks") ~= false then
        verdict = IT.Verdict(IT.Facts(info.itemID, info.hyperlink, bag))
        if verdict == "sell" and info.quality == 0 then verdict = nil end
    end
    if verdict and not p.itDot then makeDot(btn, p) end
    if not p.itDot then return end
    if verdict then
        place(btn, p)
        local r, g, b = IT.MARKS[verdict]()
        p.itDot:SetVertexColor(r, g, b, 1)
        p.itGlow:SetVertexColor(r, g, b, ns.Items.DOT_GLOW_ALPHA)
    end
    local on = verdict ~= nil
    p.itVerdict = verdict
    if on == (p.itOn == true) then return end
    p.itOn = on
    local visible = btn:IsVisible()
    if on then
        p.itDot:Show(); p.itGlow:Show()
        if visible and p.itPainted then
            DUI.Motion.Fade(p.itDot, 0, 1, DUI.Motion.FAST)
            DUI.Motion.Fade(p.itGlow, 0, 1, DUI.Motion.FAST)
        else
            p.itDot:SetAlpha(1); p.itGlow:SetAlpha(1)
        end
    elseif visible then
        DUI.Motion.Fade(p.itDot, 1, 0, DUI.Motion.FAST)
        DUI.Motion.Fade(p.itGlow, 1, 0, DUI.Motion.FAST)
        C_Timer.After(DUI.Motion.FAST + 0.05, function()
            if not p.itOn then p.itDot:Hide(); p.itGlow:Hide() end
        end)
    else
        p.itDot:Hide(); p.itGlow:Hide()
    end
    p.itPainted = true
end

-- Search words (Search.KEYWORDS), each true or false from ItemTree's answer.
-- They read Search.Facts' itemID, link and bag.
local function factsOf(f) return IT.Facts(f.itemID, f.link, f.bag) end
IT.WORDS = {
    keep = function(f) return IT.IsKeep(factsOf(f)) end,
    sell = function(f) return IT.Verdict(factsOf(f)) == "sell" end,
    usenow = function(f) return IT.Verdict(factsOf(f)) == "act" end,
    needed = function(f)
        local q = (factsOf(f) or {}).quests
        return type(q) == "table" and type(q.needs) == "table" and #q.needs > 0
    end,
}
for _, tag in ipairs({ "vendor", "auction", "disenchant", "worthless" }) do
    IT.WORDS[tag] = function(f)
        local k = (factsOf(f) or {}).keep
        return type(k) == "table" and has(k.tags, tag)
    end
end

-- Repaints every live slot (ItemTree's data arrived, or its answers moved).
local queued = false
function IT.Refresh()
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        wipe(cache)
        for _, f in ipairs(ns.windows or {}) do
            if not f.spec.still and f.set then
                for _, s in ipairs(f.set.Slots()) do
                    IT.Paint(s.button, ns.Items.InfoAt(s.bag, s.button:GetID()), s.bag)
                end
                if f.match and ns.Window then ns.Window.MatchAll(f) end
            end
        end
        -- Groups and junk lean on the answers too.
        if ns.Relayout then ns.Relayout() end
    end)
end

local hooked = false
function IT.Hook()
    local a = api()
    if hooked or not a then return end
    hooked = true
    -- Only with ItemTree there: without it "keep" would match nothing instead of names.
    local K = ns.Search.KEYWORDS
    for word, test in pairs(IT.WORDS) do
        if K[word] == nil then K[word] = test end
    end
    -- Its data loads on demand; ask for it, and draw once it's in.
    if type(a.RegisterReadyCallback) == "function" then a.RegisterReadyCallback(IT.Refresh) end
    if type(a.RegisterChangeCallback) == "function" then a.RegisterChangeCallback(IT.Refresh) end
    if type(a.RequestData) == "function" and not a.IsReady() then a.RequestData() end
end

function IT.Register()
    IT.Hook()
    if not hooked then
        DUI.RegisterEvent("ADDON_LOADED", function(_, name) if name == "ItemTree" then IT.Hook() end end)
    end
end
