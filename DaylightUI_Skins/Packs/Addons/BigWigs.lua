-- Gives BigWigs' timer bars (and LittleWigs', which uses BigWigs' plugins) the
-- player's look: font, outline and shadow from Appearance, the chosen bar
-- texture on fill and background, and our border with the right end angled like
-- the cast bar. Everything else stays BigWigs' own, as with DBM.lua: sizes,
-- positions, colors, font size, its messages and other panels.
-- How (BigWigs_Plugins v427.8): bars are pooled LibCandyBar bars, each with
-- candyBarBar, candyBarBackground, candyBarIconFrame, candyBarLabel,
-- candyBarDuration and a plain `height`. Every look change ends in the current
-- bar style's ApplyStyle and every reset starts with its BarStopped (Bars.lua).
-- Both are looked up from the style table on each call, so post-hooking the
-- "Default" style dresses bars for anyone using it, writes nothing to BigWigs'
-- settings, and leaves any other style the player picks alone.
-- BigWigs_Plugins loads on demand. Bar names and icons can be secret in boss
-- fights, so nothing here reads text or icons, only the bar's plain numbers.

local _, ns = ...
local DUI = DaylightUI
local Engine = ns.Engine
local Style, Pixel = DUI.Style, DUI.Pixel

local ADDON = "BigWigs"
local LABEL = "BigWigs and LittleWigs"

Engine.AddonSwitch({ key = "bigwigs", addon = ADDON, label = LABEL,
    desc = "Their timer bars in your font, bar texture and border, on BigWigs' Default bar style. Sizes, colors and spots stay BigWigs'." })

local BigWigsSkin = {
    SLANT = 0.6, -- angled cut as a fraction of the height, same as the breath bar
    TEXT_X = 2, -- LibCandyBar's text inset
}
ns.BigWigsSkin = BigWigsSkin
BigWigsSkin.holders = setmetatable({}, { __mode = "k" }) -- bar -> our border frame behind it

local function isTable(x) return type(x) == "table" end
local function plain(v) return type(v) == "number" and not (issecretvalue and issecretvalue(v)) end

-- Recognizes a bar by the shape LibCandyBar gives it.
local function isBar(bar)
    return isTable(bar) and isTable(bar.candyBarBar) and isTable(bar.candyBarLabel)
        and isTable(bar.candyBarDuration) and isTable(bar.candyBarIconFrame) and plain(bar.height)
end

local function barsDB()
    local bw = _G.BigWigs
    local plugin = isTable(bw) and type(bw.GetPlugin) == "function" and bw:GetPlugin("Bars", true)
    local db = isTable(plugin) and plugin.db
    return isTable(db) and isTable(db.profile) and db.profile or nil
end

-- The font size BigWigs wants. Emphasized bars are only flagged after the style
-- runs, so tell them apart by position or height. Always use the setting, never
-- the text's current size, which already includes our font scale.
local function fontSize(bar)
    local db = barsDB()
    if not db then return nil end
    local big = bar:Get("bigwigs:emphasized") or bar:Get("bigwigs:anchor") == "expPosition"
        or (plain(db.normalHeight) and bar.height > db.normalHeight)
    local size = big and db.fontSizeEmph or db.fontSize
    return plain(size) and size or nil
end

-- The bar keeps BigWigs' size and position, and our border becomes its edge. The
-- fill and icon move in by the border width, since BigWigs' default 1 px gap has
-- no room for a border outside. The right end is angled unless an icon sits there.
local function layout(bar, h)
    local T = Pixel.Px(h, Style.BorderPx(h))
    local outer = bar.height
    local inner = outer - 2 * T
    local fill, icon = bar.candyBarBar, bar.candyBarIconFrame
    local right = false
    fill:ClearAllPoints()
    if bar:IsIconVisible() then
        right = bar:GetIconPosition() == "RIGHT"
        icon:ClearAllPoints()
        icon:SetWidth(inner)
        local side, x = right and "RIGHT" or "LEFT", right and -T or T
        icon:SetPoint("TOP" .. side, bar, "TOP" .. side, x, -T)
        icon:SetPoint("BOTTOM" .. side, bar, "BOTTOM" .. side, x, T)
        if right then
            fill:SetPoint("TOPLEFT", bar, "TOPLEFT", T, -T)
            fill:SetPoint("BOTTOMRIGHT", icon, "BOTTOMLEFT", -T, 0)
        else
            fill:SetPoint("TOPLEFT", icon, "TOPRIGHT", T, 0)
            fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -T, T)
        end
    else
        fill:SetPoint("TOPLEFT", bar, "TOPLEFT", T, -T)
        fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -T, T)
    end
    local cut = (not right and outer > 0) and Pixel.Snap(h, outer * BigWigsSkin.SLANT) or 0
    Style.Slant(h, cut > 0 and "right" or nil, cut)
    Style.AngleFill(fill, cut > 0 and "right" or nil, outer > 0 and cut * inner / outer or 0)
    -- Keep the time clear of the angled end.
    local time = bar.candyBarDuration
    time:ClearAllPoints()
    time:SetPoint("TOPLEFT", fill, "TOPLEFT", BigWigsSkin.TEXT_X, 0)
    time:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", -(BigWigsSkin.TEXT_X + cut), 0)
end

-- One bar, after the style's ApplyStyle.
function BigWigsSkin.Dress(bar)
    if not isBar(bar) then return end
    local fill, back = bar.candyBarBar, bar.candyBarBackground
    local h = BigWigsSkin.holders[bar]
    if not h then
        h = CreateFrame("Frame", nil, bar)
        h:SetAllPoints(bar)
        Style.Shell(h)
        Style.Slant(h, nil, 0)
        Style.Clip(h, fill:GetStatusBarTexture(), "inner")
        if isTable(back) then Style.Clip(h, back, "inner") end
        BigWigsSkin.holders[bar] = h
    end
    -- Below the bar, since its icon is drawn on the bar's own frame.
    h:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
    h:Show()
    local size = fontSize(bar)
    Style.DressText(bar.candyBarLabel, size)
    Style.DressText(bar.candyBarDuration, size)
    Style.TrackBar(fill)
    if isTable(back) then Style.TrackBack(back) end
    layout(bar, h)
end

-- After the style's BarStopped: the bar is going back to the pool or getting a
-- different look (another style, a resize). Restore LibCandyBar's own anchors,
-- the way BigWigs' own styles do (BarStyles.lua).
function BigWigsSkin.Undress(bar)
    if not isBar(bar) then return end
    local h = BigWigsSkin.holders[bar]
    if not h then return end
    h:Hide()
    Style.Slant(h, nil, 0)
    Style.AngleFill(bar.candyBarBar, nil, 0)
    bar:SetHeight(bar.height) -- LibCandyBar re-anchors the fill and icon on this
    local time = bar.candyBarDuration
    time:ClearAllPoints()
    time:SetPoint("TOPLEFT", bar.candyBarBar, "TOPLEFT", BigWigsSkin.TEXT_X, 0)
    time:SetPoint("BOTTOMRIGHT", bar.candyBarBar, "BOTTOMRIGHT", -BigWigsSkin.TEXT_X, 0)
end

Engine.Register({ key = "bigwigs", pack = "addons", addon = "BigWigs_Plugins", switch = "bigwigs", label = LABEL,
    thirdParty = true, apply = function(_, def)
    local api = _G.BigWigsAPI
    local style = isTable(api) and type(api.GetBarStyle) == "function" and api:GetBarStyle("Default")
    if not isTable(style) or type(style.ApplyStyle) ~= "function" or type(style.BarStopped) ~= "function" then
        return false
    end
    hooksecurefunc(style, "ApplyStyle", Engine.Safe(def, BigWigsSkin.Dress))
    hooksecurefunc(style, "BarStopped", Engine.Safe(def, BigWigsSkin.Undress))
    -- A border setting changed: resize each border. Fonts, shells and bar
    -- textures update on their own.
    DUI.On("StyleChanged", Engine.Safe(def, function()
        for bar, h in pairs(BigWigsSkin.holders) do
            if h:IsShown() then layout(bar, h) end
        end
    end))
end })
