-- A choice between two looks of one thing, both drawn live side by side, each
-- inside a card you click to pick it: the portrait look (set into the frame
-- or classic) and the tooltip look (rich or simple). The setup guide's tour
-- shows them as a group ({ look = kind }), the 2.0 welcome as its slides.
--
-- The picked card lights up (outline, tick, circling lights and a soft
-- bloom), the other look dims, and a fresh page plays both cards in one
-- after the other. The previews show the standard look, never the player's
-- own settings: the unit frames' portrait sample and the tooltip's card
-- sample draw the real thing, and the nameplates' crowd is drawn here from
-- the defaults.

local _, DUI = ...
local L = DUI.L
local W = DUI.Widgets
local Style = DUI.Style

local Looks = {}
DUI.InstallerLooks = Looks

Looks.PAD = 12        -- around the preview inside its card
Looks.DIM = 0.4       -- the look that isn't picked
Looks.RISE = 10       -- how far the pair lifts in as a page shows
Looks.STAGGER = 0.14  -- between the two cards rising
Looks.FIRST = 0.12    -- the page slides in first
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
    plateClassIcon = {
        title = "Class icons on nameplates", rail = "Class icons",
        desc = "Friendly players can show their class icon by their name, so you can spot the healer in a crowd. Pick the look you like.",
        -- On puts the icon above the name: friendly plates show only the name
        -- unless their bars are on, so there's open space over it.
        keys = { "above", "none" }, new = "above",
        ref = { "Nameplates", "friendly.classIcon" },
        -- Any spot of the icon counts as on: it was placed already.
        shown = function(v) return (v == nil or v == "none") and "none" or "above" end,
        available = function()
            return DUI:GetModule("Nameplates") ~= nil and DUI.InstallerPages.Find("Nameplates", "friendly.classIcon") ~= nil
        end,
        box = function(parent) return Looks.Crowd(parent) end,
        -- On only switches it on: an icon already placed before or after the name stays there.
        apply = function(k, set)
            if k == "none" or DUI:Get("Nameplates", "friendly.classIcon") == "none" then
                set("Nameplates", "friendly.classIcon", k)
            end
        end,
    },
    -- Players who had Daylight UI before Proc Alerts start with them off
    -- (DB.ProcsOff), so the welcome offers them with a live flare.
    procAlerts = {
        title = "Proc Alerts",
        desc = "New: a painted flare lights up around your character when a proc like Clearcasting or Overpower is ready. Want them on?",
        keys = { "on", "off" }, new = "on",
        ref = { "Procs", "enabled" },
        shown = function(v) return v == false and "off" or "on" end,
        available = function()
            local ns = moduleNs("Procs")
            return type(ns) == "table" and type(ns.Sample) == "table" and type(ns.Sample.Looks) == "function"
        end,
        box = function(parent) return moduleNs("Procs").Sample.Looks(parent) end,
        apply = function(k, set) set("Procs", "enabled", k == "on") end,
    },
    -- Spell costs on the action buttons start off for everyone. The guide asks;
    -- the welcome after an update doesn't (it isn't in Welcome.CHOICES).
    spellCosts = {
        title = "Spell costs",
        desc = "Each spell's mana, rage or energy cost, right on its button. It turns red while you're short.",
        keys = { "on", "off" }, new = "on",
        ref = { "ActionBars", "look.costs" },
        shown = function(v) return v == true and "on" or "off" end,
        available = function() return DUI:GetModule("ActionBars") ~= nil end,
        box = function(parent) return Looks.Costs(parent) end,
        apply = function(k, set) set("ActionBars", "look.costs", k == "on") end,
    },
}

-- The nameplates' preview: a few friendly players' names over the world, in
-- their class colors at the standard name size, with or without the default
-- class icon above each, as the plates draw it. Same shape as the other
-- previews. x is a name's middle across, y its row down (0 top, 1 bottom).
Looks.CROWD = {
    { name = "Navani", class = "PRIEST", x = 0.26, y = 0 },
    { name = "Kaladin", class = "WARRIOR", x = 0.68, y = 0.5 },
    { name = "Jasnah", class = "MAGE", x = 0.38, y = 1 },
}
Looks.CROWD_H = 104
Looks.CROWD_LOOKS = {
    { key = "above", name = "Class icons", line = "The class icon above each name." },
    { key = "none", name = "Names only", line = "Just the name, as before." },
}
Looks.ICON_LIFT = 1   -- the gap under the icon, as on the plates
Looks.CROWD_GAP = 14  -- between the crowd and its caption

-- The friendly name size and icon share the nameplates start with.
local function plateSizes()
    local ns = moduleNs("Nameplates")
    local f = type(ns) == "table" and type(ns.DEFAULTS) == "table" and ns.DEFAULTS.friendly or {}
    local size = tonumber(f.nameSize) or Style.SIZE.body
    return size, math.floor(size * (tonumber(f.classIconScale) or 1.3) + 0.5)
end

function Looks.Crowd(parent)
    local box = CreateFrame("Frame", nil, parent)
    box.frames, box.names, box.lines = {}, {}, {}
    local size, iconSize = plateSizes()
    for _, look in ipairs(Looks.CROWD_LOOKS) do
        local f = CreateFrame("Frame", nil, box)
        f.people = {}
        for i, who in ipairs(Looks.CROWD) do
            local p = { who = who }
            p.name = Style.Text(f, size, "CENTER")
            p.name:SetText(who.name)
            p.icon = f:CreateTexture(nil, "ARTWORK")
            p.icon:SetTexture(DUI.MEDIA .. "class\\" .. string.lower(who.class) .. ".tga")
            p.icon:SetSize(iconSize, iconSize)
            p.icon:SetPoint("BOTTOM", p.name, "TOP", 0, Looks.ICON_LIFT)
            p.icon:SetShown(look.key ~= "none")
            f.people[i] = p
        end
        -- Each name keeps room over it for an icon, in both looks, so the
        -- two crowds stand in the same spots.
        f.iconUp = iconSize + Looks.ICON_LIFT
        f.block = f.iconUp + size
        box.frames[look.key] = f
        box.names[look.key] = Style.Text(box, Style.SIZE.body, "CENTER")
        box.names[look.key]:SetText(L[look.name])
        box.lines[look.key] = Style.Text(box, Style.SIZE.small, "CENTER")
        box.lines[look.key]:SetText(L[look.line])
    end
    box.HEIGHT = Looks.CROWD_H + Looks.CROWD_GAP + Style.SIZE.body + 4 + Style.SIZE.small + 2
    function box.Refresh(width)
        width = (type(width) == "number" and width > 0) and width or 460
        box:SetSize(width, box.HEIGHT)
        local half = width / 2
        for i, look in ipairs(Looks.CROWD_LOOKS) do
            local f, mid = box.frames[look.key], (i - 0.5) * half
            local fw = half - 32
            f:SetSize(fw, Looks.CROWD_H)
            f:ClearAllPoints()
            f:SetPoint("TOP", box, "TOPLEFT", mid, 0)
            for _, p in ipairs(f.people) do
                p.name:ClearAllPoints()
                p.name:SetPoint("TOP", f, "TOPLEFT", p.who.x * fw, -(f.iconUp + p.who.y * (Looks.CROWD_H - f.block)))
                p.name:SetTextColor(Style.ClassTextColor(p.who.class))
            end
            local name, line = box.names[look.key], box.lines[look.key]
            Style.InkText(name, "VALUE")
            Style.InkText(line, "LABEL")
            name:ClearAllPoints()
            name:SetPoint("TOP", box, "TOPLEFT", mid, -(Looks.CROWD_H + Looks.CROWD_GAP))
            name:SetWidth(half - 8)
            line:ClearAllPoints()
            line:SetPoint("TOP", name, "BOTTOM", 0, -4)
            line:SetWidth(half - 8)
        end
    end
    return box
end

-- The spell costs' preview: a short strip of action buttons, with each
-- spell's cost in its corner or without, one of them short of mana. Drawn as
-- the buttons draw it: a lighter shade of the power color, red when short,
-- that button's icon faded.
Looks.COST_ICONS = {
    { icon = "Interface\\Icons\\Spell_Fire_Fireball02", cost = 275 },
    { icon = "Interface\\Icons\\Spell_Frost_FrostBolt02", cost = 70 },
    { icon = "Interface\\Icons\\Spell_Holy_FlashHeal", cost = 725, short = true },
    { icon = "Interface\\Icons\\Spell_Nature_Lightning", cost = 135 },
}
Looks.COST_LOOKS = {
    { key = "on", name = "Spell costs", line = "The cost in each corner." },
    { key = "off", name = "Icons only", line = "Just the icon and its key." },
}
Looks.COST_BUTTON = 38   -- a button at the standard size, near enough
Looks.COST_GAP = 4       -- between buttons
Looks.COST_LIFT = 0.4    -- as the buttons' Skin.COST_LIFT, when Action Bars is off
Looks.COST_CAPTION = 14  -- between the strip and its caption

function Looks.Costs(parent)
    local box = CreateFrame("Frame", nil, parent)
    box.frames, box.names, box.lines = {}, {}, {}
    local ns = moduleNs("ActionBars")
    local Skin = type(ns) == "table" and type(ns.Skin) == "table" and ns.Skin or {}
    local size, gap = Looks.COST_BUTTON, Looks.COST_GAP
    for _, look in ipairs(Looks.COST_LOOKS) do
        local f = CreateFrame("Frame", nil, box)
        f:SetSize(#Looks.COST_ICONS * (size + gap) - gap, size)
        f.costs = {}
        for i, spell in ipairs(Looks.COST_ICONS) do
            local b = CreateFrame("Frame", nil, f)
            b:SetSize(size, size)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * (size + gap), 0)
            Style.Shell(b, { lean = true })
            local icon = b:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
            icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
            icon:SetTexture(spell.icon)
            Style.CropIcon(icon)
            if spell.short then icon:SetAlpha(Skin.OUT_OF_RANGE or 0.4) end
            if look.key == "on" then
                local fs = Style.Text(b, Style.SIZE.small, "LEFT")
                local at = Skin.COST_POS and Skin.COST_POS.bottomleft or { "BOTTOMLEFT", 3, 3 }
                fs:SetPoint(at[1], b, at[1], at[2], at[3])
                fs:SetText(AbbreviateNumbers(spell.cost))
                fs.short = spell.short
                f.costs[#f.costs + 1] = fs
            end
        end
        box.frames[look.key] = f
        box.names[look.key] = Style.Text(box, Style.SIZE.body, "CENTER")
        box.names[look.key]:SetText(L[look.name])
        box.lines[look.key] = Style.Text(box, Style.SIZE.small, "CENTER")
        box.lines[look.key]:SetText(L[look.line])
    end
    box.HEIGHT = size + Looks.COST_CAPTION + Style.SIZE.body + 4 + Style.SIZE.small + 2
    function box.Refresh(width)
        width = (type(width) == "number" and width > 0) and width or 460
        box:SetSize(width, box.HEIGHT)
        local half = width / 2
        local r, g, b = Style.PowerColor("MANA")
        r, g, b = Style.Lighten(r, g, b, Skin.COST_LIFT or Looks.COST_LIFT)
        local bad = Style.INK.BAD
        for i, look in ipairs(Looks.COST_LOOKS) do
            local f, mid = box.frames[look.key], (i - 0.5) * half
            f:ClearAllPoints()
            f:SetPoint("TOP", box, "TOPLEFT", mid, 0)
            for _, fs in ipairs(f.costs) do
                if fs.short then fs:SetTextColor(bad[1], bad[2], bad[3]) else fs:SetTextColor(r, g, b) end
            end
            local name, line = box.names[look.key], box.lines[look.key]
            Style.InkText(name, "VALUE")
            Style.InkText(line, "LABEL")
            name:ClearAllPoints()
            name:SetPoint("TOP", box, "TOPLEFT", mid, -(Looks.COST_BUTTON + Looks.COST_CAPTION))
            name:SetWidth(half - 8)
            line:ClearAllPoints()
            line:SetPoint("TOP", name, "BOTTOM", 0, -4)
            line:SetWidth(half - 8)
        end
    end
    return box
end

function Looks.Available(kind)
    local spec = Looks.KINDS[kind]
    if not spec then return false end
    local on = false
    DUI.SafeCall(function() on = spec.available() == true end)
    return on
end

-- The setting in use, as the tour reads it.
function Looks.Current(kind)
    local spec = Looks.KINDS[kind]
    local v = DUI:Get(spec.ref[1], spec.ref[2])
    if spec.shown then v = spec.shown(v) end
    return v
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

    -- The pair rises in as one piece; the second look only fades in, a moment
    -- after the first. Moving each card, drawing and word on its own made them
    -- drop and shake out of step in game: the drawings are shrunk with
    -- SetScale and laid out again as they show. The dimming of the look not
    -- picked waits until everything has landed.
    function f.Play()
        if not M.On() then return end
        f.Paint(false, true)
        local Feel = DUI.Win.Feel
        Feel.Piece(f, Looks.FIRST, M.SLOW, Looks.RISE)
        for i, k in ipairs(spec.keys) do
            if i > 1 then
                local art, name, line = parts(box, k)
                for _, r in ipairs({ f.cards[k], art or false, name or false, line or false }) do
                    if r then Feel.Piece(r, Looks.FIRST + (i - 1) * Looks.STAGGER, M.SLOW, 0) end
                end
            end
        end
        C_Timer.After(Looks.FIRST + #spec.keys * Looks.STAGGER + M.SLOW, function()
            if f:IsVisible() then f.Paint(true) end
        end)
    end

    return f
end
