-- A fake BigWigs (BigWigs_Plugins v427.8 and its LibCandyBar), only what its skin
-- touches: the styles table (BigWigsAPI), the Bars plugin's settings, and pooled
-- bars whose lifecycle follows Bars.lua and LibCandyBar. New resets a bar and sets
-- its font and texture, and each look change sets them again and ends in the
-- current style's ApplyStyle. BarStopped comes first when a look is undone or a
-- bar stops.
local BWW = {}

BWW.TEXTURE = "Interface/AddOns/BigWigs/Media/Textures/BantoBar"
BWW.FONT = "Fonts/ARIALN.TTF"

local function noop() end

local proto = {}

function BWW.Install(stub)
    stub.installedAddOns.BigWigs = true
    stub.installedAddOns.BigWigs_Plugins = true
    stub.loadedAddOns.BigWigs = true
    local W = {
        styles = { Default = { ApplyStyle = noop, BarStopped = noop, GetSpacing = noop } },
        db = { profile = { fontSize = 10, fontSizeEmph = 13, normalHeight = 16, normalWidth = 200,
                           expHeight = 22, expWidth = 260, barStyle = "Default" } },
        running = {},
        pool = {},
    }
    W.styles.Other = { ApplyStyle = noop, BarStopped = noop, GetSpacing = noop }
    _G.BigWigsAPI = { GetBarStyle = function(_, key) return W.styles[key] end }
    _G.BigWigs = { GetPlugin = function(_, name) if name == "Bars" then return { db = W.db } end end }
    function W.Style() return W.styles[W.db.profile.barStyle] end
    return W
end

-- BigWigs_Plugins loading: the "Default" style and the plugin exist from here.
function BWW.LoadPlugins(stub)
    stub.loadedAddOns.BigWigs_Plugins = true
    stub.FireEvent("ADDON_LOADED", "BigWigs_Plugins")
end

function proto:Set(k, v) self.data[k] = v end
function proto:Get(k) return self.data[k] end
function proto:IsIconVisible() return self.data.LCBiconVisible end
function proto:GetIconPosition() return self.data.LCBiconPosition end
function proto:SetFont(file, size, flags)
    self.candyBarLabel:SetFont(file, size, flags)
    self.candyBarDuration:SetFont(file, size, flags)
end
function proto:SetTexture(file)
    self.candyBarBar:SetStatusBarTexture(file)
    self.candyBarBar:GetStatusBarTexture():SetTexture(file)
    self.candyBarBackground:SetTexture(file)
end
-- LibCandyBar's restyleBar, called by its SetHeight.
function proto:Restyle()
    local fill, icon = self.candyBarBar, self.candyBarIconFrame
    fill:ClearAllPoints()
    icon:ClearAllPoints()
    if self:IsIconVisible() then
        icon:SetWidth(self.height)
        icon:SetPoint("TOPLEFT", self, "TOPLEFT")
        icon:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT")
        fill:SetPoint("TOPLEFT", icon, "TOPRIGHT")
        fill:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT")
    else
        fill:SetPoint("TOPLEFT", self, "TOPLEFT")
        fill:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT")
    end
end
function proto:SetHeight(height)
    self.height = height
    self.FrameSetHeight(self, height)
    self:Restyle()
end

local function newBar(W, text, icon)
    local bar = table.remove(W.pool)
    if not bar then
        -- The bar is the frame, with its methods on top (LibCandyBar's metatable).
        bar = CreateFrame("Frame", nil, UIParent)
        bar.FrameSetHeight = bar.SetHeight
        for name, fn in pairs(proto) do bar[name] = fn end
        bar:SetFrameLevel(100)
        bar.candyBarIconFrame = bar:CreateTexture()
        local fill = CreateFrame("StatusBar", nil, bar)
        bar.candyBarBar = fill
        fill:SetStatusBarTexture(BWW.TEXTURE)
        bar.candyBarBackground = fill:CreateTexture(nil, "BACKGROUND")
        bar.candyBarLabel = fill:CreateFontString(nil, "OVERLAY")
        bar.candyBarDuration = fill:CreateFontString(nil, "OVERLAY")
    end
    bar.data = { LCBiconPosition = "LEFT", LCBiconVisible = true }
    bar.width, bar.height = W.db.profile.normalWidth, W.db.profile.normalHeight
    bar:SetWidth(bar.width)
    bar.FrameSetHeight(bar, bar.height)
    bar:Show()
    bar.candyBarLabel:ClearAllPoints()
    bar.candyBarLabel:SetPoint("TOPLEFT", bar.candyBarBar, "TOPLEFT", 2, 0)
    bar.candyBarLabel:SetPoint("BOTTOMRIGHT", bar.candyBarBar, "BOTTOMRIGHT", -2, 0)
    bar.candyBarDuration:ClearAllPoints()
    bar.candyBarDuration:SetPoint("TOPLEFT", bar.candyBarBar, "TOPLEFT", 2, 0)
    bar.candyBarDuration:SetPoint("BOTTOMRIGHT", bar.candyBarBar, "BOTTOMRIGHT", -2, 0)
    bar:SetTexture(BWW.TEXTURE)
    bar:SetFont(BWW.FONT, W.db.profile.fontSize)
    bar.candyBarLabel:SetText(text)
    bar.candyBarIconFrame:SetTexture(icon)
    bar:Set("bigwigs:anchor", "normalPosition")
    return bar
end

-- Bars.lua's BigWigs_StartBar.
function BWW.Start(W, text, icon)
    local bar = newBar(W, text, icon)
    bar:Restyle()
    W.running[bar] = true
    W.Style().ApplyStyle(bar)
    return bar
end

-- Bars.lua's EmphasizeBar on a running bar.
function BWW.Emphasize(W, bar)
    local db = W.db.profile
    bar:Set("bigwigs:anchor", "expPosition")
    W.Style().BarStopped(bar)
    bar:SetFont(BWW.FONT, db.fontSizeEmph)
    bar:SetHeight(db.expHeight)
    bar:SetWidth(db.expWidth)
    bar:SetFrameLevel(105)
    W.Style().ApplyStyle(bar)
    bar:Set("bigwigs:emphasized", true)
end

-- Bars.lua's updateProfile: a setting changed.
function BWW.Update(W)
    for bar in pairs(W.running) do
        W.Style().BarStopped(bar)
        bar:SetHeight(W.db.profile.normalHeight)
        bar:SetFont(BWW.FONT, W.db.profile.fontSize)
        bar:SetTexture(BWW.TEXTURE)
        W.Style().ApplyStyle(bar)
    end
end

-- Bars.lua's SetBarStyle.
function BWW.PickStyle(W, key)
    for bar in pairs(W.running) do
        W.Style().BarStopped(bar)
        W.styles[key].ApplyStyle(bar)
    end
    W.db.profile.barStyle = key
end

-- LibCandyBar's Stop: back into the pool.
function BWW.Stop(W, bar)
    W.Style().BarStopped(bar)
    W.running[bar] = nil
    bar:Hide()
    W.pool[#W.pool + 1] = bar
end

return BWW
