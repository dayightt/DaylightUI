-- Gives Deadly Boss Mods' timer bars the player's look: font, outline and shadow
-- from Appearance, the chosen bar texture on the fill, our border (border
-- settings, right end angled like the cast bar), and cropped icons. Everything
-- else stays DBM's: sizes, positions, colors, font size, alpha, its own
-- animations and journal icons. Option changes apply immediately.
-- How (DBM-StatusBarTimers/DBT.lua, v12.1.18): the global DBT; each bar is a
-- frame "DBT_Bar_<n>" with a StatusBar "<frame>Bar" holding Name, Timer,
-- Icon1/2, Background and Variance by name. Every look change goes through the
-- bar's ApplyStyle (on the shared metatable prototype), which resets font and
-- texture, so ours go back on after it. Bars are created in fights and their
-- text and values are secret in boss fights, so nothing here reads them: only
-- fonts, files, masks and our own frame behind the bar.

local _, ns = ...
local DUI = DaylightUI
local Engine = ns.Engine
local Style, Pixel = DUI.Style, DUI.Pixel

local ADDON = "DBM-StatusBarTimers"

Engine.AddonSwitch({ key = "dbm", addon = ADDON, label = "Deadly Boss Mods",
    desc = "Its timer bars in your font, bar texture and border. Sizes, colors and spots stay DBM's." })

local DBMSkin = {
    SLANT = 0.6, -- angled cut as a fraction of the height, same as the breath bar
}
ns.DBMSkin = DBMSkin
DBMSkin.holders = setmetatable({}, { __mode = "k" }) -- bar frame -> our border frame behind it

local function isTable(x) return type(x) == "table" end
local function plain(v) return type(v) == "number" and not (issecretvalue and issecretvalue(v)) end

-- Its pieces, by name.
local function parts(frame)
    local n = frame:GetName()
    if type(n) ~= "string" then return end
    return _G[n .. "Bar"], _G[n .. "BarName"], _G[n .. "BarTimer"], _G[n .. "BarIcon1"], _G[n .. "BarIcon2"],
        _G[n .. "BarBackground"], _G[n .. "BarVariance"]
end

local function shown(tex) return isTable(tex) and tex:IsShown() end

-- Our border around the bar and any icons beside it, sized to the border
-- settings at the bar's scale (DBM scales its big bars). The right end is
-- angled unless an icon sits there.
local function layout(h)
    local bar = h.bar
    local T = Pixel.Px(h, Style.BorderPx(h))
    local left = shown(h.icon1) and h.icon1 or bar
    local right = shown(h.icon2) and h.icon2 or bar
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", left, "TOPLEFT", -T, T)
    h:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", T, -T)
    local inner = bar:GetHeight()
    if not plain(inner) or inner <= 0 then return end
    local height = inner + 2 * T
    local cut = right == bar and Pixel.Snap(h, height * DBMSkin.SLANT) or 0
    Style.Slant(h, cut > 0 and "right" or nil, cut)
    Style.AngleFill(bar, cut > 0 and "right" or nil, cut * inner / height)
end

-- One bar, after each ApplyStyle.
function DBMSkin.Dress(obj)
    if not isTable(obj) or not isTable(obj.frame) then return end
    local frame = obj.frame
    local bar, name, timer, icon1, icon2, back, variance = parts(frame)
    if not isTable(bar) or not bar.GetStatusBarTexture then return end
    local h = DBMSkin.holders[frame]
    if not h then
        h = CreateFrame("Frame", nil, frame)
        h.bar, h.icon1, h.icon2 = bar, icon1, icon2
        h:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
        Style.Shell(h)
        Style.Slant(h, nil, 0)
        Style.Clip(h, bar:GetStatusBarTexture(), "inner")
        if isTable(back) then Style.Clip(h, back, "inner") end
        if isTable(variance) then Style.Clip(h, variance, "inner") end
        if isTable(icon1) then Style.CropIcon(icon1) end
        if isTable(icon2) then Style.CropIcon(icon2) end
        DBMSkin.holders[frame] = h
    end
    -- DBM's size with our font face; the font scale applies on top, as on ours.
    local opts = isTable(_G.DBT) and _G.DBT.Options
    local size = isTable(opts) and plain(opts.FontSize) and opts.FontSize or nil
    if isTable(name) then Style.DressText(name, size) end
    if isTable(timer) then Style.DressText(timer, size) end
    Style.TrackBar(bar)
    layout(h)
end

-- Finds the shared bar prototype from the first bar DBM creates.
local function watch(def, obj)
    if not isTable(obj) then return end
    if not DBMSkin.proto then
        local mt = getmetatable(obj)
        local proto = isTable(mt) and mt.__index
        if not isTable(proto) or type(proto.ApplyStyle) ~= "function" then return end
        DBMSkin.proto = proto
        hooksecurefunc(proto, "ApplyStyle", Engine.Safe(def, DBMSkin.Dress))
    end
    DBMSkin.Dress(obj)
end

Engine.Register({ key = "dbm", pack = "addons", addon = ADDON, switch = "dbm", label = "Deadly Boss Mods",
    thirdParty = true, apply = function(_, def)
    local dbt = _G.DBT
    if not isTable(dbt) or type(dbt.CreateBar) ~= "function" or type(dbt.GetBar) ~= "function" then return false end
    -- Until the first bar. Once the prototype is hooked, each new bar's
    -- ApplyStyle dresses it.
    hooksecurefunc(dbt, "CreateBar", Engine.Safe(def, function(self, _, id)
        if not DBMSkin.proto and type(id) ~= "nil" then watch(def, self:GetBar(id)) end
    end))
    -- Bars made before the skin started (a fight at login).
    if type(dbt.GetBarIterator) == "function" then
        for obj in dbt:GetBarIterator() do watch(def, obj) end
    end
    -- A border setting changed: resize each border. Fonts, shells and the bar
    -- texture update on their own.
    DUI.On("StyleChanged", Engine.Safe(def, function()
        for _, h in pairs(DBMSkin.holders) do layout(h) end
    end))
end })
