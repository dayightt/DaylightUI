-- A choice between two looks of one thing, both drawn live side by side, each
-- inside a card you click to pick it: the portrait look (set into the frame
-- or classic) and the tooltip look (rich or simple). The setup guide's tour
-- shows them as a group ({ look = kind }), the 2.0 welcome as its slides.
--
-- The picked card lights up (outline, tick, circling lights and a soft
-- bloom), the other look dims, and a fresh page plays both cards in one
-- after the other. The previews come from the modules that draw the real
-- thing (the unit frames' portrait sample, the tooltip's card sample), so
-- they follow the player's settings.

local _, DUI = ...
local L = DUI.L
local W = DUI.Widgets
local Style = DUI.Style

local Looks = {}
DUI.InstallerLooks = Looks

Looks.PAD = 12        -- around the preview inside its card
Looks.DIM = 0.4       -- the look that isn't picked
Looks.RISE = 16       -- how far each card rises as a page shows
Looks.STAGGER = 0.09  -- between the two cards rising
Looks.BLOOM = 0.22    -- the picked card's bloom at its brightest

-- Every frame one portrait pick reaches. A frame with its portrait off is left
-- as it is, so turning one on later still gets the default.
Looks.PORTRAIT_FRAMES = { "player", "target", "targettarget", "pet", "focus", "party", "arena" }

local function moduleNs(name)
    local mod = DUI:GetModule(name)
    return mod and mod.ns
end

-- Each kind: the two keys in the preview's order, the one that's new in 2.0,
-- the setting that says which is in use (ref), whether it can show, its
-- preview box (HEIGHT, Refresh(width), names/lines and frames or cards per
-- key) and how a pick is written (apply(key, set(scope, path, value))).
Looks.KINDS = {
    portraitLook = {
        title = "Portraits",
        desc = "Portraits can now sit in their frame, with the border running around both as one piece. Pick the look you like.",
        keys = { "socket", "classic" }, new = "socket",
        ref = { "UnitFrames", "player.portraitLook" },
        available = function()
            local ns = moduleNs("UnitFrames")
            return type(ns) == "table" and type(ns.Sample) == "table" and type(ns.Sample.Looks) == "function"
        end,
        box = function(parent) return moduleNs("UnitFrames").Sample.Looks(parent) end,
        apply = function(k, set)
            for _, id in ipairs(Looks.PORTRAIT_FRAMES) do
                local shows = DUI:Get("UnitFrames", id .. ".portrait")
                if DUI:Get("UnitFrames", id .. ".portraitLook") ~= nil and shows ~= nil and shows ~= "none" then
                    set("UnitFrames", id .. ".portraitLook", k)
                end
            end
        end,
    },
    tooltipStyle = {
        title = "Tooltips",
        desc = "Rich tooltips are Daylight UI's own cards: the name up top with tags, then every number in tidy rows. Pick the look you like.",
        keys = { "rich", "simple" }, new = "rich",
        ref = { "Tooltip", "style" },
        available = function()
            local ns = moduleNs("Tooltip")
            if DUI.PrettyAside and DUI.PrettyAside.Draws() then return false end
            return type(ns) == "table" and type(ns.RichSample) == "table"
        end,
        box = function(parent) return moduleNs("Tooltip").RichSample.Looks(parent) end,
        apply = function(k, set) set("Tooltip", "style", k) end,
    },
}

function Looks.Available(kind)
    local spec = Looks.KINDS[kind]
    if not spec then return false end
    local on = false
    DUI.SafeCall(function() on = spec.available() == true end)
    return on
end

-- The setting in use, as the tour reads it.
function Looks.Current(kind)
    local r = Looks.KINDS[kind].ref
    return DUI:Get(r[1], r[2])
end

function Looks.Apply(kind, k, set)
    Looks.KINDS[kind].apply(k, set or function(scope, path, v) DUI:Set(scope, path, v) end)
end

-- The options page that holds the setting, for "Change it later".
function Looks.Later(kind)
    local r = Looks.KINDS[kind].ref
    local page = DUI.InstallerPages.Find(r[1], r[2])
    return page and page.id or nil
end

-- One look's pieces in the preview box: its drawing, its name, its line.
local function parts(box, k)
    local art = box.frames and box.frames[k] or (box.cards and box.cards[k] and box.cards[k].wrap)
    return art, box.names and box.names[k], box.lines and box.lines[k]
end

-- The picker: opts = { width, get() -> key or nil, set(key) }. Returns a frame
-- with height, Refresh() (lays the previews out again and shows the pick) and
-- Play() (the cards rise in, one after the other).
function Looks.Picker(parent, kind, opts)
    local spec = Looks.KINDS[kind]
    local Cards, M = DUI.InstallerCards, DUI.Motion
    local f = CreateFrame("Frame", nil, parent)
    local width = opts.width
    local half = width / 2
    local box = spec.box(f)
    f.height = box.HEIGHT + 2 * Looks.PAD
    f:SetSize(width, f.height)
    f.box, f.cards = box, {}
    for i, k in ipairs(spec.keys) do
        local c = Cards.Card(f)
        c.key = k
        c:SetSize(half - Cards.GAP / 2, f.height)
        c:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * (half + Cards.GAP / 2), 0)
        -- A soft wash of the accent that blooms as the card is picked.
        c.bloom = W.Round(c.inner, "ARTWORK")
        c.bloom:SetAllPoints(c.inner)
        c.bloom:SetBlendMode("ADD")
        c.bloom:Hide()
        c:SetScript("OnClick", function()
            if opts.get() == k then return end
            -- The pick fires SettingChanged, whose refresh would snap the
            -- dimming the eased paint below does.
            f.picking = true
            DUI.SafeCall(opts.set, k)
            f.picking = false
            if DUI.Sound then DUI.Sound.Play("toggle") end
            local r, g, b = Style.Accent()
            c.bloom:SetVertexColor(r, g, b, Looks.BLOOM)
            M.Flash(c.bloom, M.SLOW)
            f.Paint(true)
        end)
        f.cards[k] = c
    end
    -- The previews over the cards: they take no clicks, so a click anywhere
    -- on a card picks it.
    box:SetParent(f)
    box:SetFrameLevel(f:GetFrameLevel() + 10)
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -Looks.PAD)

    -- The pick: outline, tick and circling lights on it, the "New" tag on the
    -- new look while it isn't picked, and the other look dimmed.
    function f.Paint(animate, keepLit)
        local v = opts.get()
        for _, k in ipairs(spec.keys) do
            local c, on = f.cards[k], v == k
            c.SetSelected(on)
            c.SetTag((k == spec.new and not on) and L["New"] or nil)
            W.GlowAround(c, on, { frame = c.inner })
            local a = (keepLit or v == nil or on) and 1 or Looks.DIM
            local art, name, line = parts(box, k)
            for _, r in ipairs({ art or false, name or false, line or false }) do
                if r then M.AlphaTo(r, a, animate and M.NORMAL or 0) end
            end
        end
    end

    function f.Refresh()
        DUI.SafeCall(box.Refresh, width)
        if not f.picking then f.Paint(false) end
    end

    -- Both looks rise in, the first a moment before the second; the dimming
    -- of the one not picked waits until they've landed.
    function f.Play()
        if not M.On() then return end
        f.Paint(false, true)
        for i, k in ipairs(spec.keys) do
            local delay = (i - 1) * Looks.STAGGER
            local art, name, line = parts(box, k)
            for _, r in ipairs({ f.cards[k], art or false, name or false, line or false }) do
                if r then M.SlideIn(r, 0, -Looks.RISE, M.NORMAL, delay) end
            end
        end
        C_Timer.After(#spec.keys * Looks.STAGGER + M.NORMAL, function()
            if f:IsVisible() then f.Paint(true) end
        end)
    end

    return f
end
