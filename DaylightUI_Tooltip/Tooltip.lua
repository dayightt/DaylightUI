-- Skins the game's tooltips. The game's frame and art stay (hidden), with Daylight UI's
-- shell behind the text, Daylight UI's font, and a slim health bar under unit tooltips.
-- Player names and the border take the class color (other units their
-- reaction), items take their quality color on the border. Positioned at Daylight UI's
-- unlock handle or at the cursor. World tooltips vanish the moment the mouse
-- leaves, or fade like the game's with the Fade out option.
--
-- Tooltips are shared with secure code, so nothing here replaces the game's
-- functions: everything is a post-hook, and anything read from a unit is
-- checked for secret values first.

local _, ns = ...
local DUI = DaylightUI
local isSecret = DUI.IsSecret
local L = DUI.L
local Style = DUI.Style

local Tip = {}
ns.Tooltip = Tip

-- Skinned at login, along with every other tooltip that exists by then
-- (Tip.SkinAll). Ones created later are skinned the first time they show with
-- data. The aura buttons' tooltip is different: see Tip.StyleAuraTooltip.
Tip.NAMED = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
              "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "EmbeddedItemTooltip", "BuffFrameTooltip" }
-- A plain border, as thick as the tooltips' own setting or General's. No warm
-- band, since a tooltip has no bars inside to cover the band's corner
-- pieces. Class and quality colors tint all of it.
Tip.BAR_GAP = 3 -- gap between the tooltip and its health bar
-- Free-standing tooltips the Size setting scales (embedded ones scale with
-- their parent frame).
Tip.SCALED = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
               "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "BuffFrameTooltip" }
Tip.MIN_QUALITY = 2 -- uncommon and up get a quality border
Tip.MOVER_KEY = "tooltip"
Tip.ANCHOR_NAME = "DaylightUITooltipAnchor"
-- The anchor's size (only visible as the unlock handle) and its default spot,
-- roughly where the game puts the tooltip.
Tip.ANCHOR_SIZE = { 200, 80 }
Tip.ANCHOR_DEFAULT = { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", -100, 100 }

local cfg

-- The tooltips' border, shadow and background (Style.LookOf): their own, or
-- General's with the tooltips' own design on top (a little more solid). The
-- simple look's box is always flat; the rich card takes the heavy border.
local LOOK = "Tooltip"
Tip.LOOK = LOOK
local function backAlpha() return Style.BackAlpha(LOOK) end
local skinned = setmetatable({}, { __mode = "k" }) -- tooltip -> its shell

function Tip.Config() return cfg end

-- The rich card is a touch more solid than the simple look on the global
-- style; with the tooltips' own look both take its opacity.
Tip.RICH_ALPHA = 0.95

-- The background opacity of the skinned look, or of the rich card ("rich").
function Tip.BackAlpha(which)
    if which == "rich" and not Style.LookOwn(LOOK) then return Tip.RICH_ALPHA end
    return backAlpha()
end

-- The flat tooltip boxes are filled with the border color edge to edge, so
-- General's thickness (made for the heavy band on windows) turns them into a
-- fat colored frame. On the global style they keep the thickness tooltips
-- always had; with their own look on, the player's number is used as set.
Tip.FLAT_PX = 3
function Tip.FlatPx(g)
    if Style.LookOwn(LOOK) then return g end
    return Tip.FLAT_PX
end

-- The tooltips' border thickness, for the game's aura tooltips we can only
-- hand a backdrop to.
function Tip.BorderPx() return Tip.FlatPx(Style.LookOf(LOOK).borderPx) end

-- To get rid of a tooltip, set alpha 0, never Hide(). Hiding the game's
-- tooltip from Daylight UI's code runs its hide handlers tainted, and the game's tooltip
-- code (SetWorldCursor first) then errors on secret values. It comes back the
-- next time the game clears it for new content or hides it.
-- The reason is "combat" for a unit hidden in combat, which Shift brings back
-- (KeepMuted), or "gone" when the mouse left something in the world. A "gone" one
-- is also parked offscreen (Tip.Park), because the game's fade sets the alpha back
-- itself, and so is a default-placed "combat" one (Tip.MuteUnit). A parked tooltip
-- has clamped[tip] set.
local muted = setmetatable({}, { __mode = "k" })
local clamped = setmetatable({}, { __mode = "k" }) -- parked tooltip -> whether it was clamped to the screen
function Tip.Mute(tip, why)
    muted[tip] = why or true
    tip:SetAlpha(0)
end

function Tip.HideArt(tip)
    local art = type(tip) == "table" and tip.NineSlice
    if type(art) == "table" and art.GetAlpha and art:GetAlpha() ~= 0 then art:SetAlpha(0) end
end

function Tip.Unmute(tip)
    if not muted[tip] then return end
    muted[tip] = nil
    local parked = clamped[tip] ~= nil
    if parked then
        tip:SetClampedToScreen(clamped[tip])
        clamped[tip] = nil
    end
    tip:SetAlpha(1)
    -- Bring it back from offscreen now, not a frame later.
    if parked and Tip.Place then Tip.Place(tip) end
end

local function plain(v)
    if isSecret(v) then return nil end
    return v
end

function Tip.Shell(tip) return skinned[tip] end

-- ---------------------------------------------------------------------
-- Look
-- ---------------------------------------------------------------------

-- The shell sits one level below the tooltip so text stays on top. A tooltip at
-- the lowest level is raised by one to make room.
local scaled = {}
-- The Size setting, on top of the general UI scale.
function Tip.Size()
    return (tonumber(cfg and cfg.scale) or 1) * DUI.Movers.Scale()
end

local function keepUnder(tip)
    local s = skinned[tip]
    if not s then return end
    -- Re-apply the Size setting on every show, in case the game set its own.
    if scaled[tip] and cfg and math.abs(tip:GetScale() - Tip.Size()) > 0.001 then tip:SetScale(Tip.Size()) end
    local level = tip:GetFrameLevel()
    if level < 1 then
        tip:SetFrameLevel(1)
        level = 1
    end
    s:SetFrameLevel(level - 1)
    if s.over then s.over:SetFrameLevel(level + 10) end
end

-- A clicked link's X, at the same spot as every window's (compact header: level
-- with the first line). The rich card is pinned to the tooltip's corner at its
-- own size, which can be smaller than the tooltip: the X goes on the card while
-- it shows. A hidden card keeps its last size, so then the tooltip it is.
-- cardShown is given by the card's own OnHide, where it may still say shown.
function Tip.PlaceClose(tip, cardShown)
    local close = tip.CloseButton
    if type(close) ~= "table" then return end
    if close.IsProtected and close:IsProtected() and InCombatLockdown() then return end
    local card = ns.RichPanel and ns.RichPanel.Get and ns.RichPanel.Get(tip)
    if card and cardShown == nil then cardShown = card:IsShown() end
    if not cardShown then card = nil end
    close:ClearAllPoints()
    close:SetPoint("TOPRIGHT", card or tip, "TOPRIGHT", DUI.Win.CLOSE_X, DUI.Win.CloseY(true))
end

function Tip.Skin(tip)
    if type(tip) ~= "table" or skinned[tip] or type(tip.NineSlice) ~= "table" then return end
    -- Forbidden tooltips refuse any change (a forbidden CreateTexture at login,
    -- from the shell).
    if tip.IsForbidden and tip:IsForbidden() then return end
    -- The game's art is kept (it restyles it on every show) but hidden. Some
    -- world tooltips bring it back into view, and its gray edge showed as a gap
    -- inside Daylight UI's border, so it's hidden again on show, on new content and every
    -- frame (Tip.HideArt). No hook on its SetAlpha: the game's own calls to a
    -- hooked method failed with "attempt to call a nil value".
    Tip.HideArt(tip)
    local s = Style.Shell(tip, { look = LOOK, flat = true, noBevel = true, borderPx = Tip.FlatPx })
    skinned[tip] = s
    -- A clicked item's close button (ItemRefTooltip.CloseButton). Done here,
    -- not in Skins, since this module can run without it.
    if type(tip.CloseButton) == "table" then
        DUI.Widgets.DressClose(tip.CloseButton)
        Tip.PlaceClose(tip)
        -- The card re-places it as it comes and goes (Panel.For): a second link
        -- clicked while the tooltip is open refills it without showing it again.
        tip:HookScript("OnShow", function() Tip.PlaceClose(tip); C_Timer.After(0, function() Tip.PlaceClose(tip) end) end)
    end
    -- First: a ghost still fading hands the rich card back before it's built.
    tip:HookScript("OnShow", function(self) Tip.ghostFrom[self] = ns.TipGhost.Cancel(self) end)
    tip:HookScript("OnShow", keepUnder)
    tip:HookScript("OnShow", function(self) Tip.Settle(self); Tip.HideArt(self); Tip.KeepMuted(self); Tip.Place(self); Tip.OnCompareShown(self) end)
    tip:HookScript("OnShow", function(self) DUI.SafeCall(ns.Rich.Shown, self) end)
    tip:HookScript("OnShow", Tip.FadeIn)
    tip:HookScript("OnHide", function(self)
        DUI.SafeCall(ns.TipGhost.Take, self)
        Tip.OnFadeHide(self); Tip.ResetColors(self); Tip.Unmute(self)
        DUI.SafeCall(ns.Rich.Hidden, self)
    end)
    tip:HookScript("OnTooltipCleared", function(self)
        Tip.ResetColors(self, Tip.Refilling(self))
        Tip.HideArt(self)
        Tip.OnCleared(self)
        ns.Rich.Cleared(self)
    end)
    -- Runs right after the tooltip's own update and before it's drawn. Puts
    -- back placement, art, and a muted tooltip's alpha.
    if tip == GameTooltip then
        tip:HookScript("OnUpdate", function(self)
            Tip.hookRan = true
            Tip.OnUpdate(self)
        end)
    elseif ns.Rich.TIPS[tip.GetName and tip:GetName() or ""] then
        -- A compare tooltip: its card is rebuilt when lines come after the
        -- fill (the game's stat changes, other addons') and kept fitted.
        tip:HookScript("OnUpdate", function(self)
            DUI.SafeCall(ns.Rich.Step, self)
            -- A clicked item's popup re-shows and re-places its compares from
            -- its own update every 0.2 s: fit them and put the hands in order
            -- before the draw, or they jump for a frame.
            local shops = self.shoppingTooltips
            if type(shops) == "table" then
                DUI.SafeCall(Tip.HandOrder, self)
                for _, shop in ipairs(shops) do
                    if type(shop) == "table" and shop:IsShown() then DUI.SafeCall(ns.Rich.Step, shop) end
                end
            end
        end)
    end
    keepUnder(tip)
    Tip.SkinHeader(tip)
end

-- A compare tooltip's "Equipped" tab (the game's CompareHeader with its art and
-- gold label, ShoppingTooltipTemplate) gets Daylight UI's shell instead, its bottom tucked
-- under the tooltip's top border so they read as one piece, in the tooltip's
-- border color (Tip.Colors), with a tan label. The game only sets text and
-- width on show, so this is done once.
local headers = setmetatable({}, { __mode = "k" }) -- tooltip -> its header's shell
function Tip.SkinHeader(tip)
    local h = tip.CompareHeader
    if type(h) ~= "table" or headers[tip] then return end
    for _, r in ipairs({ h:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "Texture" then r:SetAlpha(0) end
    end
    local s = Style.Shell(h, { look = LOOK, flat = true, noBevel = true, borderPx = Tip.FlatPx })
    if not s then return end
    s:ClearAllPoints()
    -- The header's left edge is the tooltip's.
    s:SetPoint("TOPRIGHT", h, "TOPRIGHT")
    s:SetPoint("BOTTOMLEFT", tip, "TOPLEFT", 0, -DUI.Pixel.Px(tip, Style.BorderPx(h)))
    Style.LayoutShell(s)
    headers[tip] = s
    if type(h.Label) == "table" then Style.InkText(h.Label, "LABEL") end
end

function Tip.HeaderShell(tip) return headers[tip] end

-- The skinned look's shell and header tab, shown or not: the rich card
-- draws its own.
function Tip.ShowShell(tip, on)
    local s = skinned[tip]
    if s and s:IsShown() ~= on then s:SetShown(on) end
    local hs = headers[tip]
    if hs and hs:IsShown() ~= on then hs:SetShown(on) end
end

-- Border colors for a tooltip and its header tab (nil = normal).
function Tip.Colors(tip, c, pair)
    local s = skinned[tip]
    if s then Style.SetShellColors(s, c, nil, pair) end
    local hs = headers[tip]
    if hs then Style.SetShellColors(hs, c, nil, pair) end
end

local barR, barG, barB -- Daylight UI's health bar color, if any
local barKey -- or its gradient pair (Gradient on)
local barStops -- or a custom gradient's saved colors

-- Puts the health bar back to the game's own color: none of Daylight UI's left.
local function forgetBar()
    barR, barG, barB, barKey, barStops = nil, nil, nil, nil, nil
    if type(GameTooltipStatusBar) == "table" and GameTooltipStatusBar.GetStatusBarTexture then
        DUI.Style.ClearBarStops(GameTooltipStatusBar)
    end
end

-- The game refilling a tooltip from data (an item's, every 0.2 s while hovered)
-- empties its info, clears the tooltip and runs the data post-calls (which tint
-- it again) right away, before anything is drawn
-- (TooltipDataHandlerMixin:InternalProcessInfo). So the border reset waits for
-- those post-calls and the same color again means no change. Resetting and then
-- tinting would lay the shell out twice per refill. A compare tooltip that's
-- already up works the same (TooltipComparisonManager:SetItemTooltip).
function Tip.Refilling(tip)
    if type(tip.CompareHeader) == "table" and tip:IsShown() then return true end
    local list = tip.infoList
    return type(list) == "table" and next(list) == nil
end

local pending = setmetatable({}, { __mode = "k" }) -- tooltip -> border reset is pending
local flushQueued = false

-- Runs the pending reset: after the data post-calls, on show, every frame for
-- the main tooltip, and next frame for others in case the post-calls never came
-- (another addon's pre-call can stop a refill).
function Tip.Settle(tip)
    if not pending[tip] then return end
    pending[tip] = nil
    local s = skinned[tip]
    if s then Tip.Colors(tip, nil) end
end

local function flushPending()
    flushQueued = false
    for tip in pairs(pending) do Tip.Settle(tip) end
end

-- Back to the normal border (and the game's health bar color). later: wait for
-- the refill's post-calls (Tip.Refilling).
function Tip.ResetColors(tip, later)
    local s = skinned[tip]
    if s and later then
        pending[tip] = true
        if tip ~= GameTooltip and not flushQueued then
            flushQueued = true
            C_Timer.After(0, flushPending)
        end
    elseif s then
        pending[tip] = nil
        Tip.Colors(tip, nil)
    end
    if tip == GameTooltip then
        forgetBar()
        Tip.PaintHiddenClass(nil)
    end
end

-- Tints the border. pair: optional { lo, hi } gradient instead. The same color
-- again (a refill) hands back the shell's own table so nothing is allocated.
function Tip.Tint(tip, r, g, b, pair)
    local s = skinned[tip]
    if not s then return end
    pending[tip] = nil
    local c = s.opts.borderColor
    if not (type(c) == "table" and c[1] == r and c[2] == g and c[3] == b and c[4] == nil) then c = { r, g, b } end
    Tip.Colors(tip, c, pair)
end

-- The unit's class (or reaction) gradient for the border when Gradient border
-- is on, else nil. Returns the existing table if the border already uses it.
function Tip.BorderPair(unit, tip)
    if not (cfg.borderGradient and DUI.Gradients) then return nil end
    local lo, hi = DUI.Gradients.PaintRGB(DUI.Gradients.KeyFor(unit))
    local s = tip and skinned[tip]
    local now = s and s.opts.borderPair
    if type(now) == "table" and now[1] == lo and now[2] == hi then return now end
    return { lo, hi }
end

-- The game's tooltip fonts, set to Daylight UI's. They're shared font objects, so every
-- tooltip (and anything else using them) follows. Each has its own size and
-- font setting: titles, text, small text.
Tip.FONTS = {
    { name = "GameTooltipHeaderText", size = "titleSize", font = "title" },
    { name = "GameTooltipText", size = "textSize" },
    { name = "GameTooltipTextSmall", size = "smallSize", font = "small" },
}

local shadowed = setmetatable({}, { __mode = "k" })
function Tip.ApplyFonts()
    local scale = DUI.DB.General().fontScale or 1
    for _, f in ipairs(Tip.FONTS) do
        local obj = _G[f.name]
        if type(obj) == "table" and obj.SetFont then
            local slot = f.font and ns.MEDIA.fonts[f.font] or ns.MEDIA.font
            local size = tonumber(cfg[f.size]) or ns.DEFAULTS[f.size]
            DUI.GameFonts.SetObjectFont(obj, Style.FontFile(slot), size * scale, "")
            -- Every tooltip draws with these, so they're only touched once.
            if not shadowed[obj] then
                shadowed[obj] = true
                obj:SetShadowOffset(Style.TEXT_SHADOW[1], Style.TEXT_SHADOW[2])
                obj:SetShadowColor(0, 0, 0, 0.9)
            end
        end
    end
end

-- ---------------------------------------------------------------------
-- Health bar
-- ---------------------------------------------------------------------

function Tip.StyleBar()
    local bar = GameTooltipStatusBar
    if type(bar) ~= "table" or not bar.SetStatusBarTexture then return end
    if not Tip.barStyled then
        Tip.barStyled = true
        Style.TrackBar(bar, nil, ns.MEDIA.bars.health)
        local back = bar:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints(bar)
        Style.TrackBack(back, ns.MEDIA.bars.health)
        back:SetVertexColor(0, 0, 0, 0.6)
        -- A plain 1 px black edge; a bar this thin is too small for the
        -- rounded shell.
        local edge = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
        edge:SetColorTexture(0, 0, 0, 1)
        Tip.barEdge = edge
        -- The game recolors it by health as the value changes, so Daylight UI's color (class
        -- or reaction) is put back after. Use a script hook, never a hook on
        -- the bar's method: that taints the game's health code, which then
        -- fails on the secret health values it gets.
        bar:HookScript("OnValueChanged", function(self)
            if barStops then DUI.Gradients.PaintStops(self, barStops)
            elseif barKey then DUI.Gradients.Paint(self, barKey)
            elseif barR then self:SetStatusBarColor(barR, barG, barB) end
        end)
    end
    -- The game's own bar: placed again only when its height or a pixel's size
    -- changed, never on a repaint that changed nothing.
    local px = DUI.Pixel.Px(bar, 1)
    local laid = cfg.barHeight .. "|" .. px
    if Tip.barLaid ~= laid then
        Tip.barLaid = laid
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, -Tip.BAR_GAP)
        bar:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", 0, -Tip.BAR_GAP)
        bar:SetHeight(cfg.barHeight)
        Tip.barEdge:ClearAllPoints()
        Tip.barEdge:SetPoint("TOPLEFT", bar, "TOPLEFT", -px, px)
        Tip.barEdge:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", px, -px)
    end
    Tip.ShowBar(not Tip.barHidden)
end

-- The health bar under the tooltip, as its setting says, or put away (the
-- rich card draws its own).
function Tip.ShowBar(on)
    local bar = GameTooltipStatusBar
    Tip.barHidden = not on
    if type(bar) == "table" and bar.SetAlpha then bar:SetAlpha((on and cfg and cfg.healthBar) and 1 or 0) end
end

-- Whether the health bar uses a gradient: set here, or matching the unit
-- frames' health bars.
function Tip.BarGradient()
    if not DUI.Gradients then return false end
    local mode = cfg.barGradient
    if mode == "frames" then return DUI:Get("UnitFrames", "colors.health") == "classGradient" end
    return mode == "gradient"
end

-- The custom gradient the health bar wears (its own, or the unit frames'
-- health bars' when it matches them), or nil.
function Tip.BarStops()
    if not DUI.Gradients then return nil end
    local mode = cfg.barGradient
    if mode == "frames" and DUI:Get("UnitFrames", "colors.health") == "customGradient" then
        return DUI:Get("UnitFrames", "colors.healthGradient")
    end
    if mode == "customGradient" then return cfg.barStops end
    return nil
end

-- Another bar painted like the health bar right now (the fading copy of it).
function Tip.PaintLike(other, bar)
    if barStops then DUI.Gradients.PaintStops(other, barStops)
    elseif barKey then DUI.Gradients.Paint(other, barKey)
    elseif barR then other:SetStatusBarColor(barR, barG, barB)
    else
        local r, g, b, a = bar:GetStatusBarColor()
        if type(r) == "number" then other:SetStatusBarColor(r, g, b, a) end
    end
end

-- The unit's color, its class (or reaction) gradient pair, or a custom gradient.
local function colorBar(unit, r, g, b)
    local bar = GameTooltipStatusBar
    if type(bar) ~= "table" then return end
    barR, barG, barB = r, g, b
    barStops = Tip.BarStops()
    barKey = not barStops and Tip.BarGradient() and DUI.Gradients.KeyFor(unit) or nil
    if barStops then DUI.Gradients.PaintStops(bar, barStops)
    elseif barKey then DUI.Gradients.Paint(bar, barKey)
    else
        bar:SetStatusBarColor(r, g, b)
        DUI.Style.NoteFillRGB(bar:GetStatusBarTexture(), r, g, b)
    end
    Tip.PaintHiddenClass(nil)
end

-- The health bar's class layers for a hidden class id (DUI.Gradients), created
-- on first use; nil hides them.
function Tip.PaintHiddenClass(id)
    local bar = GameTooltipStatusBar
    if type(bar) ~= "table" then return end
    -- A custom gradient isn't by class: it stays, with no class over it.
    if type(id) == "nil" or Tip.BarStops() then
        if Tip.classLayers then DUI.Gradients.PaintClassLayers(Tip.classLayers, nil, nil) end
        return
    end
    Tip.classLayers = Tip.classLayers or DUI.Gradients.ClassLayers(bar)
    DUI.Gradients.PaintClassLayers(Tip.classLayers, id, Tip.BarGradient() and "classGradient" or "class")
end

-- A player whose class the game hides (battlegrounds): class layers on the bar
-- and the name in the client's class color (secret numbers). The border keeps
-- its normal color since it can't take a secret.
function Tip.HiddenClass(tip, unit)
    if not DUI.Gradients then return end
    local id = DUI.Gradients.HiddenClassID(unit)
    if type(id) == "nil" then return end
    if tip == GameTooltip then Tip.PaintHiddenClass(id) end
    if not cfg.classColors then return end
    local r, g, b = DUI.Gradients.HiddenClassColor(unit)
    local first = Tip.Line(tip, 1)
    if type(r) ~= "nil" and type(first) == "table" and first.SetTextColor then first:SetTextColor(r, g, b) end
end

-- ---------------------------------------------------------------------
-- Units and items
-- ---------------------------------------------------------------------

-- A unit's color: class for players, reaction otherwise, nil if unknown.
function Tip.UnitColor(unit)
    if plain(UnitIsPlayer(unit)) == true then
        local _, token = UnitClass(unit)
        token = plain(token)
        if type(token) == "string" then return Style.ClassColor(token) end
        return nil
    end
    local reaction = plain(UnitReaction(unit, "player"))
    if type(reaction) == "number" then return Style.ReactionColor(reaction) end
    return nil
end

-- A tooltip's left text line i (its global, e.g. GameTooltipTextLeft1), or the
-- right one with side "Right". Each name is built once per tooltip.
local lineNames = { Left = {}, Right = {} }
function Tip.Line(tip, i, side)
    side = side or "Left"
    local name = tip.GetName and tip:GetName()
    if type(name) ~= "string" then return nil end
    local names = lineNames[side][name]
    if not names then
        names = {}
        lineNames[side][name] = names
    end
    local key = names[i]
    if not key then
        key = name .. "Text" .. side .. i
        names[i] = key
    end
    return _G[key]
end

-- The game puts what you wear beside an item whenever its "always compare"
-- setting is on. With compareItems off only Shift brings it up, everywhere.
function Tip.NoAutoCompare(tip)
    if not (cfg and cfg.compareItems == false) then return end
    if type(GameTooltip_SuppressAutomaticCompareItem) == "function" then
        GameTooltip_SuppressAutomaticCompareItem(tip)
    end
end

-- With the option on, unit tooltips only show in combat while Shift is held.
function Tip.HideNow(tip)
    return cfg and cfg.hideInCombat and tip == GameTooltip and InCombatLockdown() and not IsShiftKeyDown()
end

-- Fishing is the one spell the game names Fishing in every rank, so the
-- channel's name says whether the line is in.
Tip.FISHING = 7620

function Tip.Fishing()
    local name = UnitChannelInfo("player")   -- your own channel stays plain
    if type(name) ~= "string" or isSecret(name) then return false end
    local fishing = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(Tip.FISHING)
    return type(fishing) == "string" and name == fishing
end

-- While the line is in, the only thing in the world under the mouse is
-- almost always the bobber. Muted, never hidden: the game keeps it shown, so
-- a click on the bobber still reels in.
function Tip.OnObject(tip)
    if not (cfg and cfg.hideBobber and tip == GameTooltip) then return end
    if Tip.Fishing() then Tip.Mute(tip, "bobber") end
end

function Tip.OnUnit(tip)
    if not skinned[tip] then return end
    -- Still dressed, so pressing Shift shows it as it is.
    if Tip.HideNow(tip) then Tip.MuteUnit(tip) end
    local ok, _, unit = pcall(tip.GetUnit, tip)
    unit = ok and plain(unit) or nil
    if type(unit) ~= "string" then return end
    Tip.AddExtras(tip, unit)
    Tip.LastName(tip, unit)
    local r, g, b = Tip.UnitColor(unit)
    if not r then return Tip.HiddenClass(tip, unit) end
    if tip == GameTooltip then colorBar(unit, r, g, b) end
    if cfg.classBorder ~= false then Tip.Tint(tip, r, g, b, Tip.BorderPair(unit, tip)) end
    if not cfg.classColors then return end
    local first = Tip.Line(tip, 1)
    if type(first) == "table" and first.SetTextColor then first:SetTextColor(r, g, b) end
end

-- Under a quest on a mob, the game names whose progress each block is: those
-- names go in their class colors. Only plain lines can be matched to a member.
function Tip.PaintQuestPlayers(tip, data)
    if not skinned[tip] or ns.Rich.On(tip) then return end
    local lines = type(data) == "table" and plain(data.lines) or nil
    if type(lines) ~= "table" then return end
    for i, line in ipairs(lines) do
        local kind = type(line) == "table" and plain(line.type) or nil
        if kind == ns.Rich.QUEST_PLAYER then
            local token = ns.Rich.QuestPlayerClass(plain(line.leftText))
            local fs = token and Tip.Line(tip, plain(line.lineIndex) or i)
            if type(fs) == "table" then fs:SetTextColor(Style.ClassTextColor(token)) end
        end
    end
end

-- With Last names on, appends the last name to a player's first line (the game
-- only gives the first name). Only when the line is exactly that first name, so
-- nothing else on it is lost.
function Tip.LastName(tip, unit)
    local line = Tip.Line(tip, 1)
    if type(line) ~= "table" or plain(UnitIsPlayer(unit)) ~= true then return end
    local first, full = plain(UnitName(unit)), plain(DUI.UnitName(unit, "tooltip"))
    if type(first) == "string" and type(full) == "string" and full ~= first and plain(line:GetText()) == first then
        line:SetText(full)
    end
end

-- Extra lines: a player's guild rank after their guild, and who the unit is
-- targeting (in their color). Nothing the game hides is read.
-- A player's guild and rank, plain, or nil.
function Tip.GuildOf(unit)
    if not GetGuildInfo then return nil end
    local ok, guild, rank = pcall(GetGuildInfo, unit)
    guild, rank = ok and plain(guild) or nil, ok and plain(rank) or nil
    if type(guild) ~= "string" or guild == "" then return nil end
    if type(rank) ~= "string" or rank == "" then rank = nil end
    return guild, rank
end

-- Where a group member is, plain, or nil for anyone else (you, strangers,
-- someone offline). The raid roster names the zone even inside an instance;
-- a party member's comes from their map.
function Tip.ZoneOf(unit)
    if plain(UnitIsPlayer(unit)) ~= true or plain(UnitIsUnit(unit, "player")) == true then return nil end
    local index = plain(UnitInRaid(unit))
    if type(index) ~= "number" and plain(UnitInParty(unit)) ~= true then return nil end
    if plain(UnitIsConnected(unit)) == false then return nil end
    local zone
    if type(index) == "number" and type(GetRaidRosterInfo) == "function" then
        zone = plain((select(7, GetRaidRosterInfo(index))))
    end
    local M = C_Map
    if (type(zone) ~= "string" or zone == "") and type(M) == "table"
        and type(M.GetBestMapForUnit) == "function" and type(M.GetMapInfo) == "function" then
        local id = plain(M.GetBestMapForUnit(unit))
        local info = type(id) == "number" and M.GetMapInfo(id) or nil
        zone = type(info) == "table" and plain(info.name) or nil
    end
    if type(zone) ~= "string" or zone == "" then return nil end
    return zone
end

Tip.ZONE_LABEL = (ZONE or L["Zone"]) .. ":"

-- Why a tooltip is muted ("combat", "gone", "pill"), or nil.
function Tip.Muted(tip) return muted[tip] end

function Tip.AddExtras(tip, unit)
    if cfg.guildRank then
        local guild, rank = Tip.GuildOf(unit)
        if guild and rank then
            for i = 2, 4 do
                local line = Tip.Line(tip, i)
                local text = line and plain(line:GetText())
                if type(text) == "string" and string.find(text, guild, 1, true) and not string.find(text, rank, 1, true) then
                    line:SetText(text .. " - " .. rank)
                    break
                end
            end
        end
    end
    -- The rich card draws the buffs, the target and the zone itself.
    if ns.Rich.On(tip) then return end
    local zone = Tip.ZoneOf(unit)
    if zone and not Tip.HasLine(tip, zone) and not Tip.HasLine(tip, Tip.ZONE_LABEL) then
        local ar, ag, ab = Style.Accent()
        local ink = Style.INK.TEXT
        tip:AddDoubleLine(Tip.ZONE_LABEL, zone, ar, ag, ab, ink[1], ink[2], ink[3])
        if tip.Show and tip:IsShown() then tip:Show() end
    end
    if cfg.buffs and plain(UnitIsPlayer(unit)) == true and plain(UnitIsFriend("player", unit)) == true then
        local rows = Tip.BuffIcons(unit)
        if rows then
            for _, row in ipairs(rows) do tip:AddLine(row) end
            if tip.Show and tip:IsShown() then tip:Show() end
        end
    end
    if cfg.showTarget then
        local target = unit .. "target"
        if UnitExists(target) then
            local name = plain(DUI.UnitName(target, "tooltip"))
            if type(name) == "string" then
                if plain(UnitIsUnit(target, "player")) == true then name = L[">> You <<"] end
                local r, g, b = Tip.UnitColor(target)
                local ar, ag, ab = Style.Accent()
                tip:AddDoubleLine(Tip.TARGET_LABEL, name, ar, ag, ab, r or 1, g or 1, b or 1)
                -- Re-fit to the new line, but only if it's already shown:
                -- showing it from here would run its show handlers tainted.
                if tip.Show and tip:IsShown() then tip:Show() end
            end
        end
    end
end

Tip.TARGET_LABEL = L["Target:"]

-- A friendly player's buffs as icons in rows of Tip.BUFF_ROW, up to
-- Tip.BUFF_MAX. Aura data is secret in combat and under the client's
-- restrictions, and then nothing is added.
Tip.BUFF_ROW, Tip.BUFF_MAX, Tip.BUFF_SIZE = 10, 40, 16
-- Each icon's text is made once: the tooltip fills again on every unit update.
local iconText, iconSize = {}, nil
local function buffIcon(icon)
    if iconSize ~= Tip.BUFF_SIZE then
        iconSize = Tip.BUFF_SIZE
        for k in pairs(iconText) do iconText[k] = nil end
    end
    local t = iconText[icon]
    if not t then
        local c = Style.ICON_CROP
        t = string.format("|T%s:%d:%d:0:0:64:64:%d:%d:%d:%d|t", tostring(icon), iconSize, iconSize,
            c[1] * 64, c[2] * 64, c[3] * 64, c[4] * 64)
        iconText[icon] = t
    end
    return t
end
-- The icons of a unit's buffs (a reused list) and how many, or nil.
local buffList = {}
function Tip.BuffList(unit)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    local n = 0
    for i = 1, Tip.BUFF_MAX do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok or type(a) ~= "table" then break end
        local icon = plain(a.icon)
        if icon == nil then return nil end -- secret, none of it is readable
        n = n + 1
        buffList[n] = icon
    end
    if n == 0 then return nil end
    return buffList, n
end

function Tip.BuffIcons(unit)
    local list, n = Tip.BuffList(unit)
    if not list then return nil end
    local icons = {}
    for i = 1, n do icons[i] = buffIcon(list[i]) end
    local rows = {}
    for i = 1, #icons, Tip.BUFF_ROW do
        rows[#rows + 1] = table.concat(icons, " ", i, math.min(#icons, i + Tip.BUFF_ROW - 1))
    end
    return rows
end

-- An item's quality from its link.
function Tip.Quality(link)
    if type(link) ~= "string" then return nil end
    local q
    if C_Item and C_Item.GetItemQualityByID then
        local ok, v = pcall(C_Item.GetItemQualityByID, link)
        if ok then q = plain(v) end
    end
    if q == nil and C_Item and C_Item.GetItemInfo then
        local ok, _, _, v = pcall(C_Item.GetItemInfo, link)
        if ok then q = plain(v) end
    end
    if type(q) == "number" then return q end
    return nil
end

function Tip.QualityColor(q)
    if C_Item and C_Item.GetItemQualityColor then
        local ok, r, g, b = pcall(C_Item.GetItemQualityColor, q)
        if ok and type(r) == "number" then return r, g, b end
    end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return nil
end

-- The item link in a data post-call, found the same way as the game's
-- TooltipUtil.GetDisplayedItem: the guid, else the hyperlink. tip:GetItem alone
-- isn't enough: compare tooltips don't have it (ShoppingTooltipTemplate is only
-- TooltipDataHandlerMixin; GetItem comes from GameTooltipDataMixin), and an
-- equipped item's data only has the guid.
function Tip.ItemLink(tip, data)
    if type(data) == "table" then
        local guid = plain(data.guid)
        if type(guid) == "string" and C_Item and C_Item.GetItemLinkByGUID then
            local ok, link = pcall(C_Item.GetItemLinkByGUID, guid)
            link = ok and plain(link) or nil
            if type(link) == "string" then return link end
        end
        local link = plain(data.hyperlink)
        if type(link) == "string" and link ~= "" then return link end
    end
    if type(tip.GetItem) == "function" then
        local ok, _, link = pcall(tip.GetItem, tip)
        return ok and plain(link) or nil
    end
    return nil
end

function Tip.OnItem(tip, data)
    if not skinned[tip] or not cfg.qualityBorder then return end
    local q = Tip.Quality(Tip.ItemLink(tip, data))
    if not q or q < Tip.MIN_QUALITY then return end
    local r, g, b = Tip.QualityColor(q)
    if r then Tip.Tint(tip, r, g, b) end
end

-- ---------------------------------------------------------------------
-- Item level and IDs (both off by default)
-- ---------------------------------------------------------------------

-- Added after the game's lines from the data post-calls. A refill (an item's,
-- every 0.2 s) clears the tooltip first, so each fill adds them once. Lines
-- already present (the game's own item level, or the same data twice in one
-- tooltip) aren't added again.
Tip.LEVEL_COLOR = { 0.95, 0.82, 0.45 } -- soft gold, like the game's own item level line
Tip.ID_VALUE = DUI.Style.INK.LABEL -- number in warm tan
Tip.ITEM_ID = L["Item ID"]
Tip.SPELL_KINDS = { "Spell", "UnitAura" } -- data kinds whose id is a spell id
Tip.SPELL_ID = L["Spell ID"]

-- The game's "Item Level %d", and the text before the number (to spot its own line).
function Tip.LevelFormat()
    local f = type(ITEM_LEVEL) == "string" and ITEM_LEVEL:find("%d", 1, true) and ITEM_LEVEL or "Item Level %d"
    return f, f:match("^(.-)%%d")
end

-- Whether the tooltip has a line whose left text is left (or starts with
-- prefix) and, if right is given, whose right text is right.
function Tip.HasLine(tip, left, right, prefix)
    local n = tip.NumLines and plain(tip:NumLines())
    if type(n) ~= "number" then return false end
    for i = 1, n do
        local line = Tip.Line(tip, i)
        local text = line and line.GetText and plain(line:GetText())
        if type(text) == "string" and (text == left or (prefix and prefix ~= "" and text:find(prefix, 1, true) == 1)) then
            if right == nil then return true end
            local other = Tip.Line(tip, i, "Right")
            if other and other.GetText and plain(other:GetText()) == right then return true end
        end
    end
    return false
end

-- A piece of gear's item level, or nil for anything else or if not known yet
-- (the game refills the tooltip once it is). Shared with the bags via the core.
function Tip.ItemLevel(link)
    if type(link) ~= "string" then return nil end
    return DUI.ItemLevel(link)
end

-- "Item ID 12345" / "Spell ID 12345" at the bottom.
function Tip.AddID(tip, label, id)
    id = plain(id)
    if type(id) ~= "number" then return end
    local text = tostring(id)
    if Tip.HasLine(tip, label, text) then return end
    local v = Tip.ID_VALUE
    local ar, ag, ab = Style.Accent() -- label in the accent, like Daylight UI's own tooltips
    tip:AddDoubleLine(label, text, ar, ag, ab, v[1], v[2], v[3])
    -- On the rich card it's Daylight UI's own row, never hidden with other addons' lines.
    ns.Rich.Piece(tip, { kind = "row", label = label, value = text, color = v, labelColor = { ar, ag, ab } })
end

-- Short green stats, an idea from EasyGreenStats: an item's "Equip:" sentence in
-- a few words, "Equip: Improves your chance to hit by 1%." -> "+1% Hit".
-- English only (matches the game's sentences). Anything else (procs, use
-- effects, set bonuses) is left as is. Each entry is a pattern for the text
-- after "Equip: " and its short form (%1, %2 = captures).
Tip.GREEN_STATS = {
    { "^Improves your chance to hit with spells by (%d+)%%%.$", "+%1%% Spell Hit" },
    { "^Improves your chance to get a critical strike with spells by (%d+)%%%.$", "+%1%% Spell Crit" },
    { "^Improves your chance to hit by (%d+)%%%.$", "+%1%% Hit" },
    { "^Improves your chance to get a critical strike by (%d+)%%%.$", "+%1%% Crit" },
    { "^Increases your attack speed by (%d+)%%%.$", "+%1%% Attack Speed" },
    { "^Increases damage and healing done by magical spells and effects by up to (%d+)%.$", "+%1 Spell Power" },
    { "^Increases healing done by spells and effects by up to (%d+)%.$", "+%1 Healing" },
    { "^Increases healing done by up to (%d+) and damage done by up to (%d+) for all magical spells and effects%.$", "+%1 Healing\n+%2 Spell Damage" },
    { "^Increases damage done by (%a+) spells and effects by up to (%d+)%.$", "+%2 %1 Damage" },
    { "^Restores (%d+) mana per 5 sec%.$", "+%1 Mana per 5 sec" },
    { "^Restores (%d+) health per 5 sec%.$", "+%1 Health per 5 sec" },
    { "^Restores (%d+) health every 5 sec%.$", "+%1 Health per 5 sec" },
    { "^Increases attack power by (%d+)%.$", "+%1 Attack Power" },
    { "^Increases ranged attack power by (%d+)%.$", "+%1 Ranged Attack Power" },
    { "^%+(%d+) Attack Power%.$", "+%1 Attack Power" },
    { "^%+(%d+) ranged Attack Power%.$", "+%1 Ranged Attack Power" },
    { "^Increased Defense %+(%d+)%.$", "+%1 Defense" },
    { "^Increases your chance to dodge an attack by (%d+)%%%.$", "+%1%% Dodge" },
    { "^Increases your chance to parry an attack by (%d+)%%%.$", "+%1%% Parry" },
    { "^Increases your chance to block attacks with a shield by (%d+)%%%.$", "+%1%% Block" },
    { "^Increases the block value of your shield by (%d+)%.$", "+%1 Block Value" },
    { "^Decreases the magical resistances of your spell targets by (%d+)%.$", "+%1 Spell Penetration" },
    { "^Increased ([%a%- ]+) %+(%d+)%.$", "+%2 %1 Skill" },
}

-- Short form of one tooltip line (plain text; ShortenStats colors it), or nil to leave it.
function Tip.ShortStat(text)
    local prefix = type(ITEM_SPELL_TRIGGER_ONEQUIP) == "string" and ITEM_SPELL_TRIGGER_ONEQUIP or "Equip:"
    if type(text) ~= "string" or text:sub(1, #prefix) ~= prefix then return nil end
    return Tip.ShortText(text:sub(#prefix + 1):gsub("^%s+", ""))
end

-- The same for an effect's own words (after "Equip:", or a set bonus's), or nil.
function Tip.ShortText(rest)
    if type(rest) ~= "string" then return nil end
    for _, s in ipairs(Tip.GREEN_STATS) do
        if rest:find(s[1]) then return (rest:gsub(s[1], s[2])) end
    end
end

-- A color per stat: each school (damage and resistance) by its element, melee
-- stats warm, caster stats blue and violet, defense steel, healing and health
-- green.
Tip.SCHOOL_COLORS = {
    Fire   = { 1.00, 0.52, 0.28 },
    Frost  = { 0.52, 0.82, 1.00 },
    Nature = { 0.52, 0.90, 0.40 },
    Shadow = { 0.66, 0.48, 1.00 },
    Arcane = { 0.96, 0.56, 0.96 },
    Holy   = { 1.00, 0.90, 0.52 },
}
local MELEE, CASTER, DEFENSE = { 0.94, 0.48, 0.42 }, { 0.80, 0.62, 1.00 }, { 0.70, 0.80, 0.92 }
Tip.STAT_COLORS = {
    Strength = MELEE, ["Attack Power"] = MELEE, ["Ranged Attack Power"] = MELEE,
    Agility = { 0.96, 0.80, 0.42 }, ["Attack Speed"] = { 0.96, 0.80, 0.42 },
    Stamina = { 0.96, 0.64, 0.38 },
    Intellect = { 0.46, 0.70, 1.00 },
    Spirit = { 0.52, 0.88, 0.84 },
    Hit = { 1.00, 0.86, 0.56 }, Crit = { 1.00, 0.62, 0.48 },
    ["Spell Power"] = CASTER, ["Spell Damage"] = CASTER,
    ["Spell Hit"] = { 0.62, 0.76, 1.00 }, ["Spell Crit"] = { 0.90, 0.64, 1.00 },
    ["Spell Penetration"] = { 0.72, 0.56, 0.96 },
    Healing = Style.INK.GOOD, ["Health per 5 sec"] = Style.INK.GOOD,
    Defense = DEFENSE, Dodge = DEFENSE, Parry = DEFENSE, Block = DEFENSE, ["Block Value"] = DEFENSE,
    Armor = { 0.82, 0.77, 0.68 },
    ["All Resistances"] = { 0.92, 0.86, 0.74 },
}

-- A stat's color by name ("Fire Resistance", "Spell Hit"), or nil.
function Tip.StatColor(name)
    if name == "Mana per 5 sec" then return { Style.PowerColor("MANA") } end
    local school = name:match("^(%a+) Resistance$") or name:match("^(%a+) Damage$")
    if school and Tip.SCHOOL_COLORS[school] then return Tip.SCHOOL_COLORS[school] end
    if Tip.STAT_COLORS[name] then return Tip.STAT_COLORS[name] end
    if name:find(" Skill$") then return MELEE end
end

-- The game's own formats for the base stats and resistances, so a stat line
-- is read in the client's language. Korean puts the name before the number,
-- so the whole line is matched, not a "+N name" shape.
Tip.STAT_FORMATS = {
    ITEM_MOD_STRENGTH = "Strength", ITEM_MOD_AGILITY = "Agility", ITEM_MOD_STAMINA = "Stamina",
    ITEM_MOD_INTELLECT = "Intellect", ITEM_MOD_SPIRIT = "Spirit",
}
Tip.RESIST_SCHOOLS = { "Holy", "Fire", "Nature", "Frost", "Shadow", "Arcane" }   -- DAMAGE_SCHOOL2..7

local statReads
local function statPatterns()
    if statReads then return statReads end
    statReads = {}
    local function add(fmt, color)
        if type(fmt) == "string" and fmt:find("%", 1, true) and color then
            statReads[#statReads + 1] = { "^" .. DUI.GamePattern(fmt) .. "$", color }
        end
    end
    for global, key in pairs(Tip.STAT_FORMATS) do add(_G[global], Tip.STAT_COLORS[key]) end
    add(ITEM_RESIST_ALL, Tip.STAT_COLORS["All Resistances"])
    if type(ITEM_RESIST_SINGLE) == "string" then
        for i, key in ipairs(Tip.RESIST_SCHOOLS) do
            local school = _G["DAMAGE_SCHOOL" .. (i + 1)]
            if type(school) == "string" and school ~= "" then
                -- The school's word goes in its hole, leaving only the sign and number.
                add((ITEM_RESIST_SINGLE:gsub("%%%d?%$?s", (school:gsub("%%", "%%%%")))), Tip.SCHOOL_COLORS[key])
            end
        end
    end
    return statReads
end

-- A stat line ("+24 Strength", "+5 Feuerwiderstand"): its signed
-- number, the words around it, and the stat's color (nil when unknown). nil
-- when the line isn't a stat.
function Tip.ReadStat(text)
    -- Every stat line has a signed number; most lines have none.
    if type(text) ~= "string" or not text:find("[%+%-]%d") then return nil end
    for _, r in ipairs(statPatterns()) do
        local sign, n = text:match(r[1])
        if sign then
            local num = sign .. n
            local s, e = text:find(num, 1, true)
            local name = (text:sub(1, s - 1) .. text:sub(e + 1)):gsub("^%s+", ""):gsub("%s+$", "")
            return num, name, r[2]
        end
    end
    local num, name = text:match("^([%+%-]%d[%d,%.]*%%?) (.+)$")
    if num then return num, name, Tip.StatColor(name) end
end

local function h(v) return math.max(0, math.min(255, math.floor(v * 255 + 0.5))) end
local function hex(c)
    return string.format("|cff%02x%02x%02x", h(c[1]), h(c[2]), h(c[3]))
end

-- "+44 Healing\n+15 Spell Damage" (one stat per line) with each stat colored, or
-- nil if any part isn't a known stat. Items refill every 0.2 s, so one table is reused.
local statParts = {}
function Tip.PaintStats(text)
    if type(text) ~= "string" then return nil end
    local n = 0
    for part in (text .. "\n"):gmatch("(.-)\n") do
        -- A loss keeps the game's own look.
        local num, _, c = Tip.ReadStat(part)
        if not (c and num:sub(1, 1) == "+") then
            for i = n, 1, -1 do statParts[i] = nil end
            return nil
        end
        n = n + 1
        statParts[n] = hex(c) .. part .. "|r"
    end
    local out = table.concat(statParts, "\n", 1, n)
    for i = n, 1, -1 do statParts[i] = nil end
    return out
end

-- Food, drink, potions and bandages in a few words, the same idea as the
-- short stats: "Use: Restores 530 health over 24 sec. Must remain seated
-- while eating. If you spend at least 10 seconds eating you will become well
-- fed and gain 5 Stamina for 15 min." reads "530 health over 24 sec" and
-- "+5 Stamina (15 min)". English only, like the stats. Every sentence must
-- be one it knows, or the line stays the game's.
Tip.USE_RESTORES = {
    { "^Restores ([%d,]+) health and ([%d,]+) mana over (%d+) sec$", "both" },
    { "^Restores ([%d,]+%%?) (%a+) over (%d+) sec$", "over" },
    { "^Restores ([%d,]+) to ([%d,]+) (%a+)$", "range" },
    { "^Restores ([%d,]+%%?) (%a+)$", "now" },
    { "^Heals ([%d,]+) damage over (%d+) sec$", "bandage" },
}
Tip.USE_SEATED = "^Must remain seated while %a+$"
Tip.WELL_FED = L["Well Fed:"]
Tip.USE_FED = "^If you spend at least %d+ seconds %a+ you will become well fed and gain (.+) for (%d+ %a+)$"

-- A restored amount in the color of what it fills: health heal green, mana its power color.
local function amount(n, what)
    if what == "health" then return hex(Style.INK.GOOD) .. n .. "|r" end
    if what == "mana" then return hex({ Style.PowerColor("MANA") }) .. n .. "|r" end
end

local function restored(sentence)
    sentence = sentence:gsub("^Instantly r", "R")
    for _, r in ipairs(Tip.USE_RESTORES) do
        local a, b, c = sentence:match(r[1])
        if a then
            local kind = r[2]
            if kind == "both" then
                return string.format("%s health and %s mana over %s sec", amount(a, "health"), amount(b, "mana"), c)
            elseif kind == "over" then
                local n = amount(a, b)
                return n and string.format("%s %s over %s sec", n, b, c)
            elseif kind == "range" then
                local n = amount(a .. "-" .. b, c)
                return n and (n .. " " .. c)
            elseif kind == "now" then
                local n = amount(a, b)
                return n and (n .. " " .. b)
            else
                return string.format("%s health over %s sec", amount(a, "health"), b)
            end
        end
    end
end

local function titled(words)
    return (words:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

-- "5 Stamina and 5% increased experience from kills" -> "+5 Stamina, +5% XP",
-- each in its color; "12 Stamina and Spirit" gives both 12. nil if any part is unknown.
local fedParts = {}
local function wellFed(gain, length)
    local n, last = 0, nil
    local list = gain:gsub(", and ", ", "):gsub(" and ", ", ")
    for piece in list:gmatch("[^,]+") do
        piece = piece:gsub("^%s+", ""):gsub("%s+$", "")
        local part
        local xp = piece:match("^(%d+)%% .*experience")
        if xp then
            part = hex({ Style.Pop() }) .. "+" .. xp .. "% XP|r"
        else
            local num, name = piece:match("^([%d,]+%%?) (%a[%a ]*)$")
            if num then last = num else name = piece:match("^(%a[%a ]*)$") end
            num = num or last
            if not (num and name) then
                for i = n, 1, -1 do fedParts[i] = nil end
                return nil
            end
            name = titled(name)
            part = hex(Tip.StatColor(name) or { Style.Pop() }) .. "+" .. num .. " " .. name .. "|r"
        end
        n = n + 1
        fedParts[n] = part
    end
    local out = table.concat(fedParts, ", ", 1, n)
    for i = n, 1, -1 do fedParts[i] = nil end
    local secs = tonumber(length:match("^(%d+) sec$"))
    if secs and secs >= 60 and secs % 60 == 0 then length = (secs / 60) .. " min" end
    return n > 0 and (out .. " (" .. length .. ")") or nil
end

-- The words after "Use:" as (what it restores, the well fed buff or nil), or nil to leave the line.
function Tip.ShortUse(rest)
    if type(rest) ~= "string" then return nil end
    local text = rest:gsub("%.%s*$", "")
    local use, fed
    for sentence in (text .. ". "):gmatch("(.-)%.%s+") do
        if sentence:find(Tip.USE_SEATED) then
            -- Said by every food and drink: dropped.
        elseif not use and restored(sentence) then
            use = restored(sentence)
        else
            local gain, length = sentence:match(Tip.USE_FED)
            fed = not fed and gain and wellFed(gain, length) or nil
            if not fed then return nil end
        end
    end
    if use then return use, fed end
end

-- Whether item lines are shortened (the "Short, colored item stats" switch).
function Tip.ShortsOn() return cfg and cfg.greenStats and true or false end

-- An item's stat lines: green Equip sentences shortened, then those and the
-- game's white "+10 Stamina" / "+5 Fire Resistance" lines colored.
function Tip.ShortenStats(tip)
    local n = tip.NumLines and plain(tip:NumLines())
    if type(n) ~= "number" then return end
    for i = 2, n do
        local line = Tip.Line(tip, i)
        local text = line and line.GetText and plain(line:GetText())
        -- Only "Equip: ..." and "+N ..." lines can change. Both check a prefix
        -- first, so other lines cost no pattern match.
        local short = Tip.ShortStat(text)
        local painted = Tip.PaintStats(short or text)
        local useWord = type(ITEM_SPELL_TRIGGER_ONUSE) == "string" and ITEM_SPELL_TRIGGER_ONUSE or "Use:"
        local use, fed
        if not (short or painted) and type(text) == "string" and text:sub(1, #useWord) == useWord then
            use, fed = Tip.ShortUse((text:sub(#useWord + 1):gsub("^%s+", "")))
        end
        if use then
            local c = Style.INK.GOOD
            line:SetText(useWord .. " " .. use .. (fed and ("\n" .. Tip.WELL_FED .. " " .. fed) or ""))
            line:SetTextColor(c[1], c[2], c[3])
        elseif painted then
            line:SetText(painted)
        elseif short then
            local c = Style.INK.GOOD
            line:SetText(DUI.Tips.Numbers(short))
            line:SetTextColor(c[1], c[2], c[3])
        end
    end
end

-- Swaps the coins in the game's money text (MoneyFormatterUtil: digits, then
-- |A:coin-gold:...|a) for Daylight UI's: sell price, repair cost. nil otherwise.
local COPPER_OF = { gold = 10000, silver = 100, copper = 1 }
local function ownCoin(digits, what)
    local n = tonumber((digits:gsub("%D", "")))
    if not (n and COPPER_OF[what]) then return nil end
    return DUI.Widgets.Money(n * COPPER_OF[what])
end
function Tip.OwnCoins(text)
    if type(text) ~= "string" or not text:find("|A:coin-", 1, true) then return nil end
    return (text:gsub("(%d[%d,%. \194\160]*)|A:coin%-(%a+):[^|]*|a", ownCoin))
end

-- The game's "Sell Price:" line reads "Vendor:", shorter and the word players use.
function Tip.VendorText(text)
    local word = SELL_PRICE
    if type(word) == "string" and word ~= "" and text:sub(1, #word) == word then
        return L["Vendor"] .. text:sub(#word + 1)
    end
    return text
end

function Tip.PaintCoins(tip)
    local n = tip.NumLines and plain(tip:NumLines())
    if type(n) ~= "number" then return end
    for i = 2, n do
        local line = Tip.Line(tip, i)
        local coins = Tip.OwnCoins(line and line.GetText and plain(line:GetText()))
        if coins then line:SetText(Tip.VendorText(coins)) end
    end
end

-- How many of an item fit in one bag slot, or nil when it doesn't stack (or
-- isn't loaded yet: the game refills the tooltip once it is).
function Tip.StackSize(link)
    if type(link) ~= "string" or not (C_Item and C_Item.GetItemInfo) then return nil end
    local ok, n = pcall(function() return select(8, C_Item.GetItemInfo(link)) end)
    n = ok and plain(n) or nil
    if type(n) == "number" and n > 1 then return n end
    return nil
end

-- "Stacks to 20": the words in the label color, the number in the accent.
function Tip.AddStack(tip, link)
    local n = Tip.StackSize(link)
    if not n then return end
    local text = L["Stacks to %s"]:format(DUI.Win.Parts.Hex({ Style.Pop() }) .. n .. "|r")
    if Tip.HasLine(tip, text) then return end
    local c = Style.INK.LABEL
    tip:AddLine(text, c[1], c[2], c[3])
end

-- The client leaves the sell price out of a quest reward's tooltip data (in the
-- quest log and at the NPC), and the game only prints a price it's given.
Tip.QUEST_GETTERS = { GetQuestItem = true, GetQuestLogItem = true }

local function questCount(info)
    local args = type(info.getterArgs) == "table" and info.getterArgs or {}
    local kind, i, questID = args[1], args[2], args[3]
    local read, ok, n
    if info.getterName == "GetQuestItem" then
        read = GetQuestItemInfo
        if type(read) == "function" then ok, _, _, n = pcall(read, kind, i) end
    else
        read = kind == "choice" and GetQuestLogChoiceInfo or GetQuestLogRewardInfo
        if type(read) == "function" then ok, _, _, n = pcall(read, i, questID) end
    end
    n = ok and plain(n) or nil
    return (type(n) == "number" and n > 1) and n or 1
end

local function hasSellLine(data)
    local kind = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.SellPrice
    if not (kind and type(data) == "table" and type(data.lines) == "table") then return false end
    for _, line in ipairs(data.lines) do
        if type(line) == "table" and plain(line.type) == kind then return true end
    end
    return false
end

-- A quest reward's vendor value for the whole stack, as the bags show it, or nil.
function Tip.QuestPrice(tip, data)
    local info
    if type(tip.GetPrimaryTooltipInfo) == "function" then
        local ok, v = pcall(tip.GetPrimaryTooltipInfo, tip)
        info = ok and v or nil
    elseif type(tip.infoList) == "table" then
        info = tip.infoList[1]
    end
    if not (type(info) == "table" and Tip.QUEST_GETTERS[info.getterName]) then return nil end
    if hasSellLine(data) or not (C_Item and C_Item.GetItemInfo) then return nil end
    local key = Tip.ItemLink(tip, data) or (type(data) == "table" and plain(data.id))
    if not key then return nil end
    local ok, price = pcall(function() return select(11, C_Item.GetItemInfo(key)) end)
    price = ok and plain(price) or nil
    if type(price) ~= "number" or price <= 0 then return nil end
    return price * questCount(info)
end

function Tip.AddQuestPrice(tip, data)
    local price = Tip.QuestPrice(tip, data)
    if not price then return end
    local coins = DUI.Widgets.Money(price)
    local text = ("%s: %s"):format(L["Vendor"], coins)
    if Tip.HasLine(tip, text) then return end
    local c = Style.INK.VALUE
    tip:AddLine(text, c[1], c[2], c[3])
    -- Marked as the sell price, so the Rich card puts it at its foot by what
    -- it is: another addon's line can start with the same word.
    ns.Rich.Piece(tip, { kind = "row", label = L["Vendor"], value = coins, sell = true })
end

-- An item: a quest reward's sell price, its level (gear only) with Item level
-- on, how many fit in a stack, its ID with IDs on.
function Tip.OnItemLines(tip, data)
    if skinned[tip] then Tip.PaintCoins(tip) end
    if skinned[tip] then Tip.AddQuestPrice(tip, data) end
    -- The rich card has its own stat lines, item level tag and no stack line.
    local rich = ns.Rich.On(tip)
    if skinned[tip] and cfg and cfg.greenStats and not rich then Tip.ShortenStats(tip) end
    if not (skinned[tip] and cfg and (cfg.itemLevel or cfg.showIDs or cfg.stackSize)) then return end
    local link = Tip.ItemLink(tip, data)
    if cfg.itemLevel and not rich then
        local level = Tip.ItemLevel(link)
        if level then
            local format, prefix = Tip.LevelFormat()
            local text = format:format(math.floor(level + 0.5))
            if not Tip.HasLine(tip, text, nil, prefix) then
                local c = Tip.LEVEL_COLOR
                tip:AddLine(text, c[1], c[2], c[3])
            end
        end
    end
    if cfg.stackSize and not rich then Tip.AddStack(tip, link) end
    if cfg.showIDs then
        local id = type(data) == "table" and plain(data.id) or nil
        if type(id) ~= "number" and type(link) == "string" and C_Item and C_Item.GetItemInfoInstant then
            local ok, v = pcall(C_Item.GetItemInfoInstant, link)
            id = ok and plain(v) or nil
        end
        Tip.AddID(tip, Tip.ITEM_ID, id)
    end
end

-- Repaints a spell's lines to match Daylight UI's tooltips. The cost gets its
-- power's color, other short lines become labels, and the description and other
-- sentences get the text color with their numbers colored by DUI.Tips.Numbers.
-- Only the game's white and yellow lines change, so the title, red lines (an
-- unmet requirement) and lines with their own color codes keep theirs. A recipe's
-- item keeps the game's colors, like an item tooltip. Secret text is skipped.
local function isYellow(r, g, b) return DUI.Tips.GameColor(r, g, b) == "yellow" end
local function isWhite(r, g, b) return DUI.Tips.GameColor(r, g, b) == "white" end
local function isRed(r, g, b) return DUI.Tips.GameColor(r, g, b) == "red" end
Tip.SHORT_LINE = DUI.Tips.SHORT_LINE
local function itemNameOf(data)
    local kind = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemName
    if not (kind and type(data) == "table" and type(data.lines) == "table") then return nil end
    for _, line in ipairs(data.lines) do
        if type(line) == "table" and plain(line.type) == kind then
            local text = plain(line.leftText)
            if type(text) == "string" and text ~= "" then return text end
        end
    end
end

-- Whether the data's line i is yellow: true/false, or nil if unknown (no such
-- line, or its color is secret).
local function dataYellow(lines, i)
    local line = lines and lines[i]
    local c = type(line) == "table" and line.leftColor or nil
    if type(c) ~= "table" or isSecret(c) then return nil end
    local r, g, b = c.r, c.g, c.b
    if isSecret(r) or type(r) ~= "number" then return nil end
    return isYellow(r, g, b) and true or false
end

-- The data's own line types, where they read plain. A macro fills the tooltip
-- with its spell's lines (or its item's) under the Macro type, so these tell a
-- spell's description apart when every line reads secret.
local function lineType(lines, i)
    local line = lines and lines[i]
    return type(line) == "table" and plain(line.type) or nil
end
function Tip.HasSpellLines(lines)
    local kinds = Enum and Enum.TooltipDataLineType
    if not (lines and kinds) then return false end
    for i = 1, #lines do
        local t = lineType(lines, i)
        if t ~= nil and (t == kinds.SpellName or t == kinds.SpellDescription) then return true end
    end
    return false
end

local SIDES = { "Left", "Right" } -- never written to
function Tip.PaintSpell(tip, data)
    if type(tip.NumLines) ~= "function" or type(tip.GetName) ~= "function" then return end
    local name = tip:GetName()
    if type(name) ~= "string" then return end
    local INK, Tips = Style.INK, DUI.Tips
    local itemName = itemNameOf(data)
    -- During the global cooldown (its "Cooldown remaining" line) every line's
    -- text AND color read secret. Then the yellow line is found from the data's
    -- lines, or else a spell's last data line is its description.
    local dataLines = type(data) == "table" and type(data.lines) == "table" and data.lines or nil
    local lastData = dataLines and #dataLines or nil
    local types = Enum and Enum.TooltipDataType
    local kind = type(data) == "table" and types ~= nil and plain(data.type) or nil
    local isSpell = kind ~= nil and (kind == types.Spell
        or (kind == types.Macro and Tip.HasSpellLines(dataLines)))
    local descType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.SpellDescription
    for i = 2, tip:NumLines() or 0 do
        local left = Tip.Line(tip, i)
        local lt = type(left) == "table" and left.GetText and left:GetText()
        -- In combat the text reads secret but its color doesn't (per the
        -- game's FontString docs), so a secret line is judged by color alone.
        local hidden = isSecret(lt)
        if hidden or type(lt) == "string" then
            if not hidden and lt == itemName then return end
            local r, g, b = left:GetTextColor()
            if isSecret(r) then r = nil end
            -- a line the game drew in its own color (not white, yellow or
            -- requirement red): a recipe's item in its quality
            if type(r) == "number" and (hidden or (lt ~= "" and not lt:find("|[cC]")))
                and not (isWhite(r, g, b) or isYellow(r, g, b) or isRed(r, g, b)) then return end
        end
        for _, side in ipairs(SIDES) do
            local fs = side == "Left" and left or Tip.Line(tip, i, side)
            local text = type(fs) == "table" and fs.GetText and fs:GetText()
            if type(text) ~= "nil" and isSecret(text) then
                -- secret: only the yellow description becomes text color (no numbers to read)
                local r, g, b = fs:GetTextColor()
                local yellow
                if not isSecret(r) then yellow = isYellow(r, g, b)
                elseif side == "Left" then
                    yellow = dataYellow(dataLines, i)
                    if yellow == nil and descType ~= nil and lineType(dataLines, i) == descType then yellow = true end
                    if yellow == nil then yellow = isSpell and i == lastData end
                end
                if yellow then fs:SetTextColor(INK.TEXT[1], INK.TEXT[2], INK.TEXT[3]) end
            elseif type(text) == "string" and text ~= "" and not text:find("|[cC]") then
                local r, g, b = fs:GetTextColor()
                if isSecret(r) then r = nil end
                if isYellow(r, g, b) then
                    -- the description: yellow becomes Daylight UI's text color (like a
                    -- creature's lines), with its numbers colored
                    fs:SetText(Tips.Numbers(text))
                    fs:SetTextColor(INK.TEXT[1], INK.TEXT[2], INK.TEXT[3])
                elseif isWhite(r, g, b) then
                    local power = text:find("%d") and Tips.PowerIn(text)
                    if power then
                        fs:SetTextColor(Style.PowerColor(power))
                    else
                        -- a short line (cast time, range) is a label, a sentence (an aura's) is text
                        fs:SetText(Tips.Numbers(text))
                        local c = #text <= Tip.SHORT_LINE and Tips.LABEL or Tips.TEXT
                        fs:SetTextColor(c[1], c[2], c[3])
                    end
                end
            end
        end
    end
end

-- Plugins' lines (DaylightUI.API: me.AddTooltipLines(kind, fn(lines, data))),
-- after Daylight UI's own, in the same look. Item tooltips refill several
-- times a second, so a line already there is never added twice. Each piece
-- is also a plain line, so one plugin works in both looks: Simple shows the
-- line, the rich card draws the piece (Rich.Piece) and keeps the line only
-- for its frame-only look in a fight.
local INK = Style.INK
local adding                                -- the tooltip lines go to while a plugin runs
local added = false
local function inkOf(c, fallback)
    if type(c) == "table" and type(c[1]) == "number" then return c[1], c[2], c[3] end
    return fallback[1], fallback[2], fallback[3]
end
local function colorOf(c)
    if type(c) == "table" and type(c[1]) == "number" then return { c[1], c[2], c[3] } end
    return nil
end
local function str(v)
    if v == nil or isSecret(v) then return nil end
    return tostring(v)
end
local function row(left, right, color)
    local tip = adding
    if not tip or type(left) ~= "string" then return end
    right = str(right) or ""
    if Tip.HasLine(tip, left, right) then return end
    local lr, lg, lb = inkOf(nil, INK.TEXT)
    local r, g, b = inkOf(color, INK.VALUE)
    tip:AddDoubleLine(left, right, lr, lg, lb, r, g, b)
    ns.Rich.Piece(tip, { kind = "row", label = left, value = right, color = colorOf(color) })
    added = true
end
local function line(text, r, g, b, piece)
    local tip = adding
    if not tip or type(text) ~= "string" or Tip.HasLine(tip, text) then return end
    tip:AddLine(text, r, g, b, true)
    ns.Rich.Piece(tip, piece)
    added = true
end
Tip.PLUGIN_LINES = {
    -- A label and its value: label soft white, value white unless colored.
    Line = row,
    Row = row,
    -- A sentence, wrapped.
    Text = function(text, color)
        local r, g, b = inkOf(color, INK.TEXT)
        line(text, r, g, b, { kind = "text", text = text, color = colorOf(color) })
    end,
    -- What a click does, in the accent.
    Hint = function(text)
        local r, g, b = Style.Accent()
        line(text, r, g, b, { kind = "hint", text = text })
    end,
    Gap = function()
        local tip = adding
        if not tip then return end
        tip:AddLine(" ")
        ns.Rich.Piece(tip, { kind = "gap" })
        added = true
    end,
    -- A label, its value out of max and a thin bar (1.12). Simple: "12 / 20".
    Bar = function(label, value, max, color)
        if type(label) ~= "string" or type(value) ~= "number" or type(max) ~= "number" or isSecret(value) or isSecret(max) then return end
        local shown, most = str(value), str(max)
        local text = string.format(L["%s / %s"], shown, most)
        local tip = adding
        if not tip or Tip.HasLine(tip, label, text) then return end
        local lr, lg, lb = inkOf(nil, INK.TEXT)
        local r, g, b = inkOf(color, INK.VALUE)
        tip:AddDoubleLine(label, text, lr, lg, lb, r, g, b)
        ns.Rich.Piece(tip, { kind = "bar", label = label, value = math.max(0, math.min(value, max)), max = max,
            shown = shown, shownMax = most, color = colorOf(color) })
        added = true
    end,
    -- A tag in the card's header (1.12). Simple: a line of its own.
    Tag = function(text, color)
        local r, g, b = inkOf(color, INK.LABEL)
        line(text, r, g, b, { kind = "tag", text = text, color = colorOf(color) })
    end,
    -- A small heading in the accent (1.12).
    Section = function(title)
        local r, g, b = Style.Accent()
        line(title, r, g, b, { kind = "section", text = title })
    end,
    -- Value tiles side by side, { { value, caption }, ... } (1.12). Simple:
    -- one line, "value caption · value caption".
    Tiles = function(list)
        if type(list) ~= "table" then return end
        local tiles, words = {}, {}
        for _, t in ipairs(list) do
            local value, caption = type(t) == "table" and str(t[1]), type(t) == "table" and str(t[2])
            if value then
                tiles[#tiles + 1] = { value, caption or "", colorOf(t[3]) }
                words[#words + 1] = caption and (value .. " " .. caption) or value
            end
        end
        if #tiles == 0 then return end
        line(table.concat(words, L[" · "]), INK.TEXT[1], INK.TEXT[2], INK.TEXT[3], { kind = "tiles", tiles = tiles })
    end,
}

-- kind = "unit" | "item" | "spell" | "world" | "compare". Returns whether
-- anything was added.
function Tip.Plugins(kind, tip, data)
    local R = DUI.APIReport
    if not (skinned[tip] and type(R) == "table" and R.TooltipLines) then return false end
    local list = R.TooltipLines(kind)
    if not list or #list == 0 then return false end
    adding, added = tip, false
    for _, e in ipairs(list) do DUI.SafeCallAs(e.owner, e.fn, Tip.PLUGIN_LINES, data) end
    adding = nil
    return added
end

-- Which look a tooltip is in, for plugins: "rich" or "simple".
function Tip.StyleOf(tip) return ns.Rich.On(tip) and "rich" or "simple" end

-- What a plugin's function is told about the tooltip: plain values only (nil
-- when the game keeps one secret).
function Tip.PluginData(kind, tip, data)
    local style = Tip.StyleOf(tip)
    if kind == "unit" then
        local _, unit = tip.GetUnit and tip:GetUnit()
        return { unit = plain(unit), style = style }
    end
    if kind == "item" or kind == "compare" then
        local link = Tip.ItemLink and Tip.ItemLink(tip, data) or nil
        local id = type(data) == "table" and plain(data.id) or nil
        return { link = plain(link), itemID = type(id) == "number" and id or nil, style = style }
    end
    if kind == "world" then
        local first = Tip.Line(tip, 1)
        local name = first and first.GetText and plain(first:GetText())
        return { name = type(name) == "string" and name or nil, style = style }
    end
    local id = type(data) == "table" and plain(data.id) or nil
    return { spellID = type(id) == "number" and id or nil, style = style }
end

-- Runs the plugins for a tooltip already on show and fits it to the new lines
-- (Show only while it's shown: called when it isn't, it runs the game's show
-- handlers under the addon's taint).
function Tip.PluginsShown(kind, tip, data)
    if Tip.Plugins(kind, tip, Tip.PluginData(kind, tip, data)) and tip:IsShown() then tip:Show() end
end

-- A spell or aura: its ID line with IDs on. Left out when the game keeps it
-- secret (an aura in a boss fight or battleground). The rich card reads the
-- game's own colors and paints the lines itself only in a fight.
function Tip.OnSpellLines(tip, data)
    if skinned[tip] and not ns.Rich.On(tip) then Tip.PaintSpell(tip, data) end
    if not (skinned[tip] and cfg and cfg.showIDs and type(data) == "table") then return end
    Tip.AddID(tip, Tip.SPELL_ID, data.id)
end

-- ---------------------------------------------------------------------
-- Placement: the game's, the cursor, or a moved spot
-- ---------------------------------------------------------------------

-- With the cursor setting, the main tooltip follows the cursor whenever the game
-- has put it at its default spot. That is tracked here, since the game's own
-- markers (`default`, the anchor type) can read back secret for a world tooltip.
-- The post-hooks only set a flag; the tooltip is moved each frame from a script
-- hook and never re-owned (SetOwner from Daylight UI's code clears it and runs the game's
-- clear handlers tainted).
local atDefault = false
local defaultOwner -- owner when the game put it at its default spot
function Tip.OnDefaultAnchor(tip, parent)
    if tip ~= GameTooltip then return end
    -- Daylight UI's frames marked __duiOwnTooltipSpot (the minimap's fps) use the game's
    -- tooltip code but place the tooltip themselves, so leave those alone.
    atDefault = not (type(parent) == "table" and parent.__duiOwnTooltipSpot)
    defaultOwner = parent or UIParent
    -- The game shows a world unit's tooltip a moment before its unit data
    -- arrives, so mute it from the start and it never flashes. Anything that
    -- turns out not to be a unit comes back (OnData).
    if Tip.HideNow(tip) then Tip.MuteUnit(tip) end
    if atDefault then Tip.Place(tip) end
end

-- A unit hidden in combat. Alpha 0 alone flashed it for each new enemy: the
-- game's fill ends with Show() after Daylight UI's post-calls, which restores the alpha
-- (and stops a fade) before any update from here runs. So one at the game's spot
-- (placed here, so it can be restored) is also parked offscreen. One placed by
-- its owner keeps its spot.
function Tip.MuteUnit(tip)
    Tip.Mute(tip, "combat")
    if atDefault then Tip.Park(tip) end
end

function Tip.OnData(tip, data)
    if tip ~= GameTooltip or not muted[tip] then return end
    local kind = type(data) == "table" and plain(data.type) or nil
    local unitType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit
    if kind ~= unitType then Tip.Unmute(tip) end
end
-- The tooltip was emptied: a new owner (SetOwner clears it) or a refresh. A
-- different owner or anchor means it's no longer at the default spot. New
-- content un-mutes a tooltip (the unit hook mutes it again if it's another unit
-- in combat). A world unit (owned by UIParent) stays muted in combat, or its
-- refresh would flicker.
function Tip.OnCleared(tip)
    if tip ~= GameTooltip then
        if not Tip.HideNow(tip) then Tip.Unmute(tip) end
        return
    end
    Tip.questLines = nil
    -- Either can read back secret for a world tooltip in combat. Treat unknown
    -- (nil here) as unchanged, never as a different owner.
    local owner = tip.GetOwner and plain(tip:GetOwner())
    local anchor = tip.GetAnchorType and plain(tip:GetAnchorType())
    if (owner ~= nil and owner ~= defaultOwner) or (type(anchor) == "string" and anchor ~= "ANCHOR_NONE") then
        atDefault = false
    end
    if Tip.HideNow(tip) and (owner == nil or owner == UIParent) then return end
    Tip.Unmute(tip)
end

-- A default-placed tooltip goes to the cursor or to Daylight UI's handle, never the game's
-- Edit Mode spot. The handle starts about where the game puts it, so an unmoved
-- one looks the same. It may have been re-owned without a clear seen here (the
-- minimap does this every frame with UIParent, the world's owner), and its
-- anchor tells. Anything else that puts it at the game's spot counts too:
-- anchored to the game's container means default-placed. Anchored to anything else, the screen or Daylight UI's
-- handle, means its owner placed it.
function Tip.Place(tip)
    if not (cfg and tip == GameTooltip) or muted[tip] == "gone" or clamped[tip] ~= nil then return end
    local anchor = tip.GetAnchorType and plain(tip:GetAnchorType())
    if type(anchor) == "string" and anchor ~= "ANCHOR_NONE" then
        atDefault = false
        Tip.FitSide(tip, anchor)
        return
    end
    local rel = Tip.AnchoredTo(tip)
    if rel ~= nil and rel == (_G.GameTooltipDefaultContainer or _G.SharedTooltipDefaultContainer) then
        atDefault = true
        defaultOwner = tip.GetOwner and plain(tip:GetOwner())
    elseif rel ~= nil and rel ~= UIParent and rel ~= Tip.anchor and not (Tip.ByButton() and rel == defaultOwner) then
        atDefault = false
    end
    if atDefault then Tip.PlaceNow(tip) end
end

-- A tooltip its owner put on the right (a loot row, a shop item) flips to the
-- left when the right side can't fit it plus its compare tooltips. Otherwise the
-- game stacks the compares back over the owner (the loot window) and they cover
-- everything. Only mirrored toward the side with more room. The compares hang
-- off the tooltip, so they follow. Runs on show, every frame, and when a compare
-- tooltip shows (Shift).
Tip.MIRROR = { ANCHOR_RIGHT = "ANCHOR_LEFT", ANCHOR_TOPRIGHT = "ANCHOR_TOPLEFT",
               ANCHOR_BOTTOMRIGHT = "ANCHOR_BOTTOMLEFT" }

-- A frame's edge or width in screen pixels (nil if unknown or secret).
local function px(f, v)
    local s = f:GetEffectiveScale()
    v = plain(v)
    if type(v) ~= "number" or type(s) ~= "number" or isSecret(s) then return nil end
    return v * s
end

function Tip.FitSide(tip, anchor)
    local mirror = Tip.MIRROR[anchor]
    if not mirror or not tip.SetAnchorType then return end
    local owner = tip.GetOwner and plain(tip:GetOwner())
    if type(owner) ~= "table" or owner == UIParent or not owner.GetLeft then return end
    local left, right = px(owner, owner:GetLeft()), px(owner, owner:GetRight())
    local need = px(tip, tip:GetWidth())
    local screen = px(UIParent, UIParent:GetWidth())
    if not (left and right and need and screen) then return end
    for _, shop in ipairs(type(tip.shoppingTooltips) == "table" and tip.shoppingTooltips or {}) do
        if shop:IsShown() then need = need + (px(shop, shop:GetWidth()) or 0) end
    end
    local room = screen - right
    if room >= need or left <= room then return end
    tip:SetAnchorType(mirror)
end

-- A compare tooltip of GameTooltip's is showing: check its side now, not a
-- frame later.
function Tip.OnCompareShown(shop)
    local tip = GameTooltip
    if shop == tip or type(tip) ~= "table" or type(tip.shoppingTooltips) ~= "table" then return end
    for _, s in ipairs(tip.shoppingTooltips) do
        if s == shop then
            local anchor = tip.GetAnchorType and plain(tip:GetAnchorType())
            if type(anchor) == "string" then Tip.FitSide(tip, anchor) end
            return
        end
    end
end

-- What its single anchor is attached to (nil if none, several, or unreadable).
function Tip.AnchoredTo(tip)
    if plain(tip:GetNumPoints()) ~= 1 then return nil end
    local ok, _, rel = pcall(tip.GetPoint, tip, 1)
    return ok and plain(rel) or nil
end

-- Only re-anchors when the spot changed. This runs every frame a tooltip shows,
-- and each new anchor makes the client re-layout the tooltip and its text. When
-- the tooltip shows a secret (a mob in a restricted dungeon, its quest lines),
-- its anchoring becomes secret: every GetPoint return reads secret, point and
-- frame too, and comparing them errors every frame. If unreadable, just re-anchor.
local function anchorTo(tip, point, rel, relPoint, x, y)
    if plain(tip:GetNumPoints()) == 1 then
        local ok, p, r, rp, px, py = pcall(tip.GetPoint, tip, 1)
        p, r, rp, px, py = plain(p), plain(r), plain(rp), plain(px), plain(py)
        if ok and p == point and r == rel and rp == relPoint and type(px) == "number" and type(py) == "number"
            and math.abs(px - x) < 0.01 and math.abs(py - y) < 0.01 then
            return
        end
    end
    tip:ClearAllPoints()
    tip:SetPoint(point, rel, relPoint, x, y)
end

-- The game menu button's tooltip (latency, fps, addons) is the one micro button
-- tooltip the game sends to its default corner; the others attach to their
-- button (ANCHOR_RIGHT). This one does too, whatever the setting: up and right
-- of the button, flipped where the screen runs out. The game rewrites it every
-- second, so it's read each frame since its lines arrive after the anchor.
function Tip.ByButton()
    local button = _G.MainMenuMicroButton
    return type(button) == "table" and defaultOwner == button
end

function Tip.AtButton(tip, button)
    local right, top = px(button, button:GetRight()), px(button, button:GetTop())
    local w, h = px(tip, tip:GetWidth()), px(tip, tip:GetHeight())
    local sw, sh = px(UIParent, UIParent:GetWidth()), px(UIParent, UIParent:GetHeight())
    if not (right and top and w and h and sw and sh) then return false end
    local above = top + h <= sh
    local side = right + w <= sw and "LEFT" or "RIGHT"
    anchorTo(tip, (above and "BOTTOM" or "TOP") .. side, button, (above and "TOP" or "BOTTOM") .. "RIGHT", 0, 0)
    return true
end

-- Where the fight pill goes, as the tooltip itself would: "cursor"; "handle"
-- and the handle's corner (a default-placed tooltip at Daylight UI's spot);
-- or "tooltip" (placed by its owner: the pill takes its spot).
function Tip.PillSpot(tip)
    if Tip.ByButton() then return "tooltip" end
    if atDefault and cfg.anchor == "cursor" then return "cursor" end
    if atDefault and Tip.anchor then return "handle", DUI.Movers.Corner(Tip.MOVER_KEY) or "BOTTOMRIGHT" end
    return "tooltip"
end

function Tip.PlaceNow(tip)
    if Tip.ByButton() and Tip.AtButton(tip, defaultOwner) then return end
    if cfg.anchor == "cursor" then
        local x, y = GetCursorPosition()
        local s = tip:GetEffectiveScale()
        if type(x) ~= "number" or type(s) ~= "number" or s <= 0 then return end
        anchorTo(tip, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / s + (cfg.cursorX or 12), y / s + (cfg.cursorY or 12))
    elseif Tip.anchor then
        -- Anchor to the handle's chosen corner so it grows away from it.
        local at = DUI.Movers.Corner(Tip.MOVER_KEY) or "BOTTOMRIGHT"
        anchorTo(tip, at, Tip.anchor, at, 0, 0)
    end
end

-- ---------------------------------------------------------------------
-- Leaving something in the world: hide at once, or the game's fade
-- ---------------------------------------------------------------------

-- The game fades the tooltip when the mouse leaves a unit or object in the world
-- (on the world cursor update, with nothing under the mouse). With the fade off,
-- or for units hidden in combat, it's muted instead: alpha 0, held there every
-- frame until new content arrives or the game hides it. No hook on FadeOut: the
-- game's own calls to a hooked method failed. The fade is the client's own
-- update setting the alpha every frame and can run after this, so alpha 0 alone
-- still showed it fading. The tooltip is also parked offscreen (unclamped)
-- until then.
Tip.PARK = 100

function Tip.Park(tip)
    if clamped[tip] == nil then
        clamped[tip] = tip:IsClampedToScreen() == true
        tip:SetClampedToScreen(false)
    end
    anchorTo(tip, "TOPRIGHT", UIParent, "BOTTOMLEFT", -Tip.PARK, -Tip.PARK)
end

function Tip.OnWorldCursor()
    local tip = GameTooltip
    if not (cfg and type(tip) == "table" and tip:IsShown()) then return end
    -- The fight pill goes the moment the mouse leaves, whatever the fade.
    local pill = muted[tip] == "pill"
    -- Fading like the game, unless it's a unit hidden in combat.
    if cfg.fadeOut and not Tip.HideNow(tip) and not pill then return end
    -- Still over a unit. The client can answer GetWorldCursor with nothing for
    -- an enemy (it vanished while hovered, reported by a player).
    if UnitExists and UnitExists("mouseover") then return end
    if not (C_TooltipInfo and C_TooltipInfo.GetWorldCursor) then return end
    local ok, data = pcall(C_TooltipInfo.GetWorldCursor)
    if not ok or data ~= nil then return end
    -- In combat the world tooltip's owner can read back secret. That still
    -- counts as the world's (as in OnCleared), never another owner.
    local owner = tip.GetOwner and tip:GetOwner()
    if not isSecret(owner) and owner ~= UIParent then return end
    if pill then ns.RichPill.Leave() end
    if pill and cfg.fadeOut then return end
    DUI.SafeCall(ns.TipGhost.Take, tip)
    Tip.Mute(tip, "gone")
    Tip.Park(tip)
end

-- Keeps a muted tooltip at alpha 0, since the game restores the alpha itself.
function Tip.KeepMuted(tip)
    if not muted[tip] then return end
    -- Shift pressed (or combat over) while a hidden unit is hovered.
    if muted[tip] == "combat" and not Tip.HideNow(tip) then return Tip.Unmute(tip) end
    local a = tip:GetAlpha()
    if type(a) ~= "number" or isSecret(a) or a > 0 then tip:SetAlpha(0) end
    if muted[tip] == "gone" or clamped[tip] ~= nil then Tip.Park(tip) end
end

-- Fade in (NORMAL) when a tooltip shows, using the eased value squared, since
-- ease-out alone puts half the alpha on in the first sixth and reads as a pop.
-- Not Motion.FadeIn: the client's Show resets a tooltip's alpha to 1 (the
-- fill's own Show, on every refill too), and that fade yields to anything that
-- sets the alpha. This one holds through a higher alpha and is reapplied every
-- frame before drawing (Tip.OnUpdate). It only yields to a lower alpha (the
-- game's own fade) and to muting. Off with the general Motion switch, and in
-- combat the tooltip appears instantly.
local fades = setmetatable({}, { __mode = "k" }) -- tooltip -> { v = current alpha }

-- When each was last hidden. An owner's UpdateTooltip (every 0.2 s) can hide the
-- tooltip and refill it in one go (DialogueUI's reward items). Hidden and shown
-- in the same frame means it never left the screen, so don't fade from zero (a
-- flicker five times a second) and let a running fade continue. GetTime is
-- constant within a frame.
local hiddenAt = setmetatable({}, { __mode = "k" })
-- The alpha its fading ghost was at as it showed again (Tip.Skin's first OnShow).
Tip.ghostFrom = setmetatable({}, { __mode = "k" })

function Tip.OnFadeHide(tip) hiddenAt[tip] = GetTime() end

-- Still held here? Not once muted, or once the alpha drops below the one set.
local function holds(tip, s)
    local a = tip:GetAlpha()
    if muted[tip] or type(a) ~= "number" or isSecret(a) or a < s.v - 0.02 then
        fades[tip] = nil
        return false
    end
    return true
end

function Tip.FadeStep(tip)
    local s = fades[tip]
    if s and holds(tip, s) then tip:SetAlpha(s.v) end
end

function Tip.FadeIn(tip)
    local hidden = hiddenAt[tip]
    hiddenAt[tip] = nil
    -- Its ghost was still fading: the new one rises from there, not from nothing.
    local from = Tip.ghostFrom[tip] or 0
    Tip.ghostFrom[tip] = nil
    if hidden == GetTime() then return Tip.FadeStep(tip) end
    fades[tip] = nil
    local M = DUI.Motion
    if muted[tip] or not M.On() or InCombatLockdown() then return end
    local s = { v = from }
    fades[tip] = s
    tip:SetAlpha(from)
    M.Tween(s, 0, 1, M.NORMAL, function(e)
        if fades[tip] ~= s or not holds(tip, s) then return end
        local v = from + (1 - from) * e * e
        s.v = v
        tip:SetAlpha(v)
        if e >= 1 then fades[tip] = nil end
    end)
end

-- Questie's objective rows come from a post-call that runs after this one, so
-- they're repainted here before drawing, once per fill (Tip.OnCleared resets
-- the count). Its drop chance ("[37%]") is hardcoded gray and becomes the
-- accent. A finished row (three spaces, its color, then 3/3) goes dim with
-- "Complete" in place of the chance, since there's nothing left to farm. Secret
-- text is left as is.
Tip.DROP_GRAY = "|c%x%x999999(%[[%d%.]+%%%])|r"
Tip.QUEST_ROW = "^   (|c%x%x%x%x%x%x%x%x)"

function Tip.PaintQuestRow(text)
    local color = text:match(Tip.QUEST_ROW)
    if not color then return text end
    local Hex = DUI.Win.Parts.Hex
    local off = Hex(Style.INK.OFF)
    if color == off then return text end
    local have, need = text:match("(%d+)/(%d+)")
    if have and have == need and tonumber(need) > 0 then
        text = text:gsub("%s*" .. Tip.DROP_GRAY, "")
        return "   " .. off .. text:sub(#color + 4) .. "  " .. Hex(Style.INK.GOOD) .. L["Complete"] .. "|r"
    end
    return (text:gsub(Tip.DROP_GRAY, Hex({ Style.Accent() }) .. "%1|r"))
end

function Tip.PaintQuestRows(tip)
    -- The rich card lays these rows out itself (Rich.Lines).
    if ns.Rich.On(tip) then return end
    local n = plain(tip:NumLines())
    if type(n) ~= "number" or n == Tip.questLines then return end
    Tip.questLines = n
    local refit = false
    for i = 2, n do
        local line = Tip.Line(tip, i)
        local text = line and plain(line:GetText())
        if type(text) == "string" then
            local painted = Tip.PaintQuestRow(text)
            if painted ~= text then
                line:SetText(painted)
                refit = true
            end
        end
    end
    if refit and tip:IsShown() then tip:Show() end
end

-- ---------------------------------------------------------------------
-- Main hand and off hand on the compare tooltips
-- ---------------------------------------------------------------------

-- With a weapon in each hand both compare tooltips just say "Equipped". Which
-- hand each item is in, read from the compare tooltip's data (an equipped
-- item's guid against the two weapon slots): 16 main hand, 17 off hand.
Tip.MAIN_HAND, Tip.OFF_HAND = 16, 17
Tip.hands = setmetatable({}, { __mode = "k" })

function Tip.HandOf(data)
    local guid = type(data) == "table" and plain(data.guid) or nil
    if type(guid) ~= "string" or not (C_Item and C_Item.GetItemGUID and type(ItemLocation) == "table"
        and ItemLocation.CreateFromEquipmentSlot) then return nil end
    for _, slot in ipairs({ Tip.MAIN_HAND, Tip.OFF_HAND }) do
        local loc = ItemLocation:CreateFromEquipmentSlot(slot)
        if plain(C_Item.DoesItemExist(loc)) == true and plain(C_Item.GetItemGUID(loc)) == guid then return slot end
    end
    return nil
end

-- From the item post-call: a compare tooltip's hand, for its card and its place.
function Tip.NoteHand(tip, data)
    if type(tip.CompareHeader) ~= "table" then return end
    Tip.hands[tip] = Tip.HandOf(data)
end

-- The hand's name, the game's own words for its slots.
function Tip.HandWord(slot)
    if slot == Tip.MAIN_HAND then return INVTYPE_WEAPONMAINHAND or L["Main Hand"] end
    if slot == Tip.OFF_HAND then return INVTYPE_WEAPONOFFHAND or L["Off Hand"] end
    return nil
end

-- A compare tooltip's points, as { point, relativeTo, relativePoint, x, y }
-- each, or nil when any of them can't be read.
local function pointsOf(f)
    local n = plain(f:GetNumPoints())
    if type(n) ~= "number" or n < 1 then return nil end
    local out = {}
    for i = 1, n do
        local a, rel, b, x, y = f:GetPoint(i)
        a, rel, b, x, y = plain(a), plain(rel), plain(b), plain(x), plain(y)
        if type(a) ~= "string" or type(rel) ~= "table" then return nil end
        out[i] = { a, rel, b or a, x or 0, y or 0 }
    end
    return out
end

-- The game hangs one compare tooltip on the item's tooltip and the other on
-- that one, and which goes next to the item depends on the side they open
-- to: opening to the right, the off hand sat next to the item where the eye
-- reads it as the main hand. The main hand always goes next to the item: the
-- two trade places, each taking the other's points. The game places them
-- again on each refill, before this runs (from the tooltip's update).
function Tip.HandOrder(tip)
    local shops = tip.shoppingTooltips
    if type(shops) ~= "table" then return end
    local a, b = shops[1], shops[2]
    if not (type(a) == "table" and type(b) == "table" and a:IsShown() and b:IsShown()) then return end
    local pa, pb = pointsOf(a), pointsOf(b)
    if not (pa and pb) then return end
    local function hangsOn(points, f)
        for _, pt in ipairs(points) do if pt[2] == f then return true end end
        return false
    end
    -- The near one hangs on the tooltip only; the far one on the near one.
    local near, far, pn, pf
    if hangsOn(pb, a) and not hangsOn(pa, b) then
        near, far, pn, pf = a, b, pa, pb
    elseif hangsOn(pa, b) and not hangsOn(pb, a) then
        near, far, pn, pf = b, a, pb, pa
    else
        return
    end
    if not (Tip.hands[near] == Tip.OFF_HAND and Tip.hands[far] == Tip.MAIN_HAND) then return end
    near:ClearAllPoints()
    far:ClearAllPoints()
    for _, pt in ipairs(pn) do far:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
    for _, pt in ipairs(pf) do
        near:SetPoint(pt[1], pt[2] == near and far or pt[2], pt[3], pt[4], pt[5])
    end
end

function Tip.OnUpdate(tip)
    Tip.PaintQuestRows(tip)
    Tip.Settle(tip)
    Tip.HideArt(tip)
    Tip.KeepMuted(tip)
    Tip.FadeStep(tip)
    Tip.Place(tip)
    DUI.SafeCall(ns.Rich.Step, tip)
    -- Its compare tooltips are refilled from inside this update (an item
    -- button's UpdateTooltip, every 0.2 s with Shift held), after their own
    -- update may have run this frame: their cards catch up before the draw.
    local shops = tip.shoppingTooltips
    if type(shops) == "table" then
        DUI.SafeCall(Tip.HandOrder, tip)
        for _, shop in ipairs(shops) do
            if type(shop) == "table" and shop:IsShown() then
                DUI.SafeCall(ns.Rich.Step, shop)
                ns.TipGhost.Note(shop)
            end
        end
    end
    ns.TipGhost.Note(tip)
end

-- Driven from Daylight UI's own frame because the game stops the tooltip's OnUpdate while
-- it fades, which left it off the cursor. When the tooltip's own update is
-- running, its hook has already done the work since Daylight UI's last tick, so nothing
-- to do (once per frame, not twice). Shown only while the tooltip is.
function Tip.Tick()
    if Tip.hookRan then
        Tip.hookRan = false
        return
    end
    local tip = GameTooltip
    if type(tip) == "table" and tip:IsShown() then Tip.OnUpdate(tip) end
end

-- ---------------------------------------------------------------------
-- Build and refresh
-- ---------------------------------------------------------------------

local hooked = false

-- Skins every tooltip that exists now. Asks every frame what it is, the client's
-- locked aura buttons included, so in combat or under restrictions it waits
-- (DUI.AfterRestrictions). Frames the client still won't let addons touch are skipped.
function Tip.SkinAll()
    if type(EnumerateFrames) ~= "function" then return end
    if DUI.Restricted() then
        DUI.AfterRestrictions(Tip.SkinAll, "Tooltip.SkinAll")
        return
    end
    local f = EnumerateFrames()
    while f do
        local ok, what = pcall(f.GetObjectType, f)
        if ok and what == "GameTooltip" then DUI.SafeCall(Tip.Skin, f) end
        f = EnumerateFrames(f)
    end
end

function Tip.Build(mod)
    cfg = mod.db
    if not Tip.anchor then
        Tip.anchor = CreateFrame("Frame", Tip.ANCHOR_NAME, UIParent)
        Tip.anchor:SetSize(Tip.ANCHOR_SIZE[1], Tip.ANCHOR_SIZE[2])
        DUI.Movers.Register(Tip.anchor, Tip.MOVER_KEY, "Tooltip", Tip.ANCHOR_DEFAULT, { scale = false, corner = "BOTTOMRIGHT" }) -- the tooltips have their own scale
    end
    for _, name in ipairs(Tip.NAMED) do Tip.Skin(_G[name]) end
    Tip.SkinAll()
    -- Tooltips the game's own addons create as they load: walked after the
    -- next loading screen, and only if an addon loaded since the last walk (a
    -- walk visits every frame there is).
    local loaded = false
    DUI.RegisterEvent("ADDON_LOADED", function() loaded = true end)
    DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        if not loaded then return end
        loaded = false
        DUI.SafeCall(Tip.SkinAll)
    end)
    if not hooked then
        hooked = true
        local TDP = TooltipDataProcessor
        local types = Enum and Enum.TooltipDataType
        if TDP and TDP.AddTooltipPostCall then
            -- A refill's border reset waits for these (Tip.Refilling). The unit
            -- and item post-calls settle it after tinting; this one covers
            -- every other data type.
            local tinted = {}
            if types and types.Unit then tinted[types.Unit] = true end
            if types and types.Item then tinted[types.Item] = true end
            if TDP.AllTypes then TDP.AddTooltipPostCall(TDP.AllTypes, function(tip, data)
                DUI.SafeCall(Tip.Skin, tip)
                DUI.SafeCall(Tip.OnData, tip, data)
                local kind = type(data) == "table" and plain(data.type) or nil
                if kind == nil or not tinted[kind] then Tip.Settle(tip) end
                ns.Rich.Filled(tip, data)
            end) end
            if types and types.Unit then
                TDP.AddTooltipPostCall(types.Unit, function(tip, data)
                    DUI.SafeCall(Tip.OnUnit, tip)
                    DUI.SafeCall(Tip.PaintQuestPlayers, tip, data)
                    DUI.SafeCall(Tip.Plugins, "unit", tip, Tip.PluginData("unit", tip, data))
                    Tip.Settle(tip)
                end)
            end
            -- Before the game's item rules run, so its own flag keeps the
            -- automatic compare away (its OnHide clears the flag again).
            if types and types.Item and TDP.AddTooltipPreCall then
                TDP.AddTooltipPreCall(types.Item, function(tip) DUI.SafeCall(Tip.NoAutoCompare, tip) end)
            end
            if types and types.Item then
                TDP.AddTooltipPostCall(types.Item, function(tip, data)
                    DUI.SafeCall(Tip.NoteHand, tip, data)
                    DUI.SafeCall(Tip.OnItem, tip, data)
                    Tip.Settle(tip)
                    DUI.SafeCall(Tip.OnItemLines, tip, data)
                    DUI.SafeCall(Tip.PluginsShown, "item", tip, data)
                    -- A compare tooltip's item (what you have on) also runs "compare" (1.12).
                    if type(tip.CompareHeader) == "table" then DUI.SafeCall(Tip.PluginsShown, "compare", tip, data) end
                end)
            end
            -- Things in the world that aren't units: nodes, chests, a mailbox (1.12).
            for _, kind in ipairs({ "Object", "Corpse" }) do
                if types and types[kind] then
                    TDP.AddTooltipPostCall(types[kind], function(tip, data)
                        if kind == "Object" then DUI.SafeCall(Tip.OnObject, tip) end
                        DUI.SafeCall(Tip.PluginsShown, "world", tip, data)
                    end)
                end
            end
            for _, kind in ipairs(Tip.SPELL_KINDS) do
                if types and types[kind] then
                    TDP.AddTooltipPostCall(types[kind], function(tip, data)
                        DUI.SafeCall(Tip.OnSpellLines, tip, data)
                        DUI.SafeCall(Tip.PluginsShown, "spell", tip, data)
                    end)
                end
            end
            -- A macro on an action bar shows its spell's lines under its own data
            -- type. Its id is the macro's, so it gets the look but no Spell ID.
            if types and types.Macro then
                TDP.AddTooltipPostCall(types.Macro, function(tip, data)
                    if skinned[tip] and not ns.Rich.On(tip) then DUI.SafeCall(Tip.PaintSpell, tip, data) end
                end)
            end
        end
        -- Post-hooks only (they run after the game's code). Re-owning the
        -- tooltip from a hook taints the game's world cursor tooltip code,
        -- which then errors. Daylight UI's own frame keeps a default-placed tooltip on
        -- the cursor.
        Tip.driver = CreateFrame("Frame", nil, UIParent)
        Tip.driver:SetScript("OnUpdate", Tip.Tick)
        if type(GameTooltip) == "table" and GameTooltip.HookScript then
            Tip.driver:SetShown(GameTooltip:IsShown() == true)
            GameTooltip:HookScript("OnShow", function() Tip.driver:Show() end)
            GameTooltip:HookScript("OnHide", function() Tip.driver:Hide() end)
        end
        -- SetOwner runs inside GameTooltip_SetDefaultAnchor, before this
        -- post-hook, so only a default-placed tooltip gets flagged. No hooks on
        -- GameTooltip's own methods (SetOwner, SetPoint, SetAlpha, Show,
        -- FadeOut): the game's own calls to them then failed with "attempt to
        -- call a nil value" on every mouseover. Its scripts (Tip.Skin) and the
        -- world cursor event do the work instead.
        if type(GameTooltip_SetDefaultAnchor) == "function" and type(GameTooltip) == "table" then
            hooksecurefunc("GameTooltip_SetDefaultAnchor", Tip.OnDefaultAnchor)
        end
        -- This event fires on every cursor move, many times a frame, so the
        -- handler is created once and only checks once, next frame.
        DUI.RegisterEvent("WORLD_CURSOR_TOOLTIP_UPDATE", DUI.Soon(function() DUI.SafeCall(Tip.OnWorldCursor) end))
    end
    Tip.Refresh(mod)
end

-- With PrettyTooltip on (and this module off, see Module.lua) its unit panels
-- borrow the game's health bar, so only that stays Daylight UI's: its look
-- (Tip.StyleBar) and the unit's color. Always shown, since the bar's setting has
-- no options page while the module is off.
function Tip.BarOnly(mod)
    cfg = mod.db
    Tip.StyleBar()
    local bar, TDP = GameTooltipStatusBar, TooltipDataProcessor
    if type(bar) == "table" and bar.SetAlpha then bar:SetAlpha(1) end
    local kind = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit
    if not hooked and kind and TDP and TDP.AddTooltipPostCall then
        hooked = true
        TDP.AddTooltipPostCall(kind, function(tip) DUI.SafeCall(Tip.OnBarUnit, tip) end)
    end
end

function Tip.OnBarUnit(tip)
    if tip ~= GameTooltip then return end
    forgetBar()
    Tip.PaintHiddenClass(nil)
    local ok, _, unit = pcall(tip.GetUnit, tip)
    unit = ok and plain(unit) or nil
    if type(unit) ~= "string" then return end
    local r, g, b = Tip.UnitColor(unit)
    if r then return colorBar(unit, r, g, b) end
    local id = DUI.Gradients and DUI.Gradients.HiddenClassID(unit)
    if type(id) ~= "nil" then Tip.PaintHiddenClass(id) end
end

-- The aura buttons' tooltip (buffs, debuffs, target auras) belongs to the client
-- and no addon can reach it. The client accepts a backdrop for it through
-- AuraContainerInbound, so it gets one as close to Daylight UI's as a plain backdrop
-- gets: Daylight UI's background and border colors and border thickness.
Tip.WHITE = "Interface\\Buttons\\WHITE8X8"

function Tip.StyleAuraTooltip()
    local inbound = _G.AuraContainerInbound
    if type(inbound) ~= "table" or type(inbound.SetTooltipBackdrop) ~= "function" or not CreateColor then return end
    local look = Style.LookOf(LOOK)
    local edge = DUI.Pixel.Px(UIParent, look.borderPx)
    local bg, border = Style.BackColor(LOOK), Style.BORDER
    DUI.SafeCall(inbound.SetTooltipBackdrop, {
        backdropInfo = {
            bgFile = Tip.WHITE, edgeFile = Tip.WHITE, edgeSize = edge,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        },
        centerColor = CreateColor(bg[1], bg[2], bg[3], backAlpha()),
        borderColor = CreateColor(border[1], border[2], border[3], look.borderAlpha),
    })
end

function Tip.Refresh(mod)
    cfg = mod.db
    Tip.ApplyFonts()
    Tip.StyleBar()
    DUI.SafeCall(Tip.StyleAuraTooltip)
    for _, name in ipairs(Tip.SCALED) do
        local tip = _G[name]
        if type(tip) == "table" and tip.SetScale then
            scaled[tip] = true
            local size = Tip.Size()
            if math.abs((tip:GetScale() or 1) - size) > 0.0001 then tip:SetScale(size) end
        end
    end
    for tip, s in pairs(skinned) do
        Style.LayoutShell(s)
        keepUnder(tip)
    end
    for _, s in pairs(headers) do Style.LayoutShell(s) end
    -- The look switched, or the card's settings changed: built again (or
    -- put away) before the next draw.
    for tip in pairs(skinned) do
        local p = ns.RichPanel.Get(tip)
        if p then ns.RichPanel.Repaint(p) end
        ns.Rich.Refresh(tip)
    end
    ns.RichPill.Layout()
    -- Plugins hear when the look switches (API 1.12), not at the first load.
    local style = cfg.style == "rich" and "rich" or "simple"
    if Tip.style and Tip.style ~= style and DUI.APIReport then DUI.APIReport.Event("TooltipStyleChanged", style) end
    Tip.style = style
    -- Following the cursor, there's nothing to place, so no handle.
    DUI.Movers.Suspend(Tip.MOVER_KEY, cfg.anchor == "cursor")
end
