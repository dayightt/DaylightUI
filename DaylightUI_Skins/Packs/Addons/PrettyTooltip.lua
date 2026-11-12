-- Skins PrettyTooltip: its panels get the same shell as our tooltips, while its
-- layout, text, stat and school colors are kept.
-- How (Panel/Layout.lua, Panel/Render.lua, v1.3.8): it hides the game's tooltip
-- (alpha 0) and draws its own panel on top. The game's tooltip comes back when a
-- line can't be read (secret, in combat) or while its "original tooltip" key is
-- held. It's all private with no globals: each panel sits alone in a host frame
-- on UIParent, created the first time a tooltip gets data of a kind it draws.
-- So panels are found by shape (PS.IsPanel), right after such a fill
-- (PS.OnData). Its own art is plain fields on the panel. Every render repaints
-- that art (alpha 0 didn't stick: its gold band and edges showed over our shell
-- in game, since its SetVertexColor and SetGradient carry an alpha) and ends in
-- the panel's SetHeight (finishPanel). A post-hook on that frame's own method
-- hides the art again before it's drawn (PS.HideArt) and picks up pieces it
-- creates later plus the item's color. Nothing is written to its settings.
-- Its accent is read back off its left and right edges: drawChrome paints those
-- in its accent times EDGE, or a dual school's two colors when they differ.
-- It reads its font from the game's tooltip font objects, so those get ours
-- here, since the Tooltip module that normally does it is off while
-- PrettyTooltip draws (DUI.PrettyAside). Nothing here reads game data, only the
-- plain numbers it painted.

local _, ns = ...
local DUI = DaylightUI
local Engine = ns.Engine
local Style = DUI.Style

local ADDON = "PrettyTooltip"

Engine.AddonSwitch({ key = "prettytooltip", addon = ADDON, label = "PrettyTooltip",
    desc = "Its tooltips in the Daylight UI frame, in your background opacity. Its layout, words and stat colors stay." })

local PS = {
    EDGE = 0.36, -- edge brightness as a fraction of its accent
    PLAIN = 0.08, -- r, g, b within this of each other = white or gray, no border color
    BORDER = 3, -- same as our tooltips (Tooltip.lua Tip.BORDER)
    -- Its art on the panel, hidden. Icon, level badge and rules stay.
    ART = { "halo", "background", "glow", "header" },
    ART_LISTS = { "edges", "shades" },
    FONTS = { "GameTooltipHeaderText", "GameTooltipText", "GameTooltipTextSmall" },
}
ns.PrettySkin = PS
PS.shells = setmetatable({}, { __mode = "k" }) -- its panel or Equipped tab -> our shell
PS.closed = setmetatable({}, { __mode = "k" }) -- its X, dressed
PS.seen = setmetatable({}, { __mode = "k" }) -- tooltips already searched for a panel
PS.hiddenAt = setmetatable({}, { __mode = "k" }) -- panel -> time it last hid
PS.fades = setmetatable({}, { __mode = "k" }) -- panel -> its running fade

local function isTable(x) return type(x) == "table" end
local function plain(v) return type(v) == "number" and not (issecretvalue and issecretvalue(v)) end

function PS.Shell(f) return PS.shells[f] end

function PS.IsPanel(f)
    return isTable(f) and isTable(f.halo) and isTable(f.background) and isTable(f.header)
        and isTable(f.edges) and isTable(f.shades) and isTable(f.iconBorder)
end

local function opts()
    local alpha = DUI:Get("Tooltip", "bgAlpha")
    return { borderPx = PS.BORDER, flat = true, noBevel = true, bgAlpha = plain(alpha) and alpha or nil }
end

-- The tab above a compare panel, like our tooltips' (Tip.SkinHeader).
function PS.Tag(tag)
    if PS.shells[tag] then return end
    tag.border:Hide()
    tag.fill:Hide()
    PS.shells[tag] = Style.Shell(tag, opts())
    Style.DressText(tag.text, Style.SIZE.tiny)
    Style.InkText(tag.text, "LABEL")
end

-- Its accent, read off its edges: one color, two when a dual school's ends
-- differ, or nil for white/gray (our normal border).
function PS.Accent(panel)
    local left, right = panel.edges[3], panel.edges[4]
    local lr, lg, lb = left:GetVertexColor()
    local rr, rg, rb = right:GetVertexColor()
    if not (plain(lr) and plain(lg) and plain(lb) and plain(rr) and plain(rg) and plain(rb)) then return nil end
    local k = PS.EDGE
    local lo, hi = { lr / k, lg / k, lb / k }, { rr / k, rg / k, rb / k }
    if math.abs(lr - rr) + math.abs(lg - rg) + math.abs(lb - rb) > 0.01 then return lo, { lo, hi } end
    if math.max(lo[1], lo[2], lo[3]) - math.min(lo[1], lo[2], lo[3]) < PS.PLAIN then return nil end
    return lo
end

-- Its X is two lines tinted on hover. Ours replaces it and theirs is hidden.
function PS.Close(close)
    if PS.closed[close] then return end
    PS.closed[close] = true
    local x = DUI.Widgets.DressClose(close)
    for _, r in ipairs({ close:GetRegions() }) do
        if r ~= x and r.GetObjectType and r:GetObjectType() == "Texture" then r:Hide() end
    end
end

function PS.HideArt(panel)
    for _, key in ipairs(PS.ART) do
        if isTable(panel[key]) then panel[key]:Hide() end
    end
    for _, list in ipairs(PS.ART_LISTS) do
        for _, piece in ipairs(panel[list]) do piece:Hide() end
    end
    if isTable(panel.nativeBorder) then panel.nativeBorder:Hide() end
end

-- After each render.
function PS.Paint(panel)
    local s = PS.shells[panel]
    if not s then return end
    s:SetFrameLevel(math.max(0, panel:GetFrameLevel() - 1))
    PS.HideArt(panel)
    if isTable(panel.close) then PS.Close(panel.close) end
    if isTable(panel.equipped) then PS.Tag(panel.equipped) end
    local alpha = DUI:Get("Tooltip", "bgAlpha")
    if plain(alpha) and s.opts.bgAlpha ~= alpha then
        s.opts.bgAlpha = alpha
        Style.LayoutShell(s)
    end
    local color, pair = PS.Accent(panel)
    Style.SetShellColors(s, color, nil, pair)
    local tag = isTable(panel.equipped) and PS.shells[panel.equipped]
    if tag then Style.SetShellColors(tag, color, nil, pair) end
end

-- It shows and hides its panel itself and never sets the panel's alpha, so we
-- give it the same fade as our tooltips (Tip.FadeIn: eased value squared,
-- NORMAL). Hidden and shown in the same frame (a refill) counts as never having
-- left. In combat it appears instantly. It disappears with its own Hide.
function PS.OnShow(panel)
    local hidden = PS.hiddenAt[panel]
    PS.hiddenAt[panel] = nil
    if hidden == GetTime() then return end
    local M = DUI.Motion
    local mine = {}
    PS.fades[panel] = mine
    if not M.On() or InCombatLockdown() then
        panel:SetAlpha(1)
        return
    end
    M.Tween(panel, 0, 1, M.NORMAL, function(e)
        if PS.fades[panel] == mine then panel:SetAlpha(e * e) end
    end)
end

function PS.OnHide(panel)
    PS.hiddenAt[panel] = GetTime()
end

function PS.Dress(panel, def)
    if PS.shells[panel] then return end
    local s = Style.Shell(panel, opts())
    if not s then return end
    PS.shells[panel] = s
    hooksecurefunc(panel, "SetHeight", Engine.Safe(def, PS.Paint))
    panel:HookScript("OnShow", Engine.Safe(def, PS.OnShow))
    panel:HookScript("OnHide", Engine.Safe(def, PS.OnHide))
    PS.Paint(panel)
end

-- Each host holds one frame, so most of UIParent's children are skipped by
-- their child count. Runs only a few times a session (PS.OnData).
function PS.Walk(def)
    for _, host in ipairs({ UIParent:GetChildren() }) do
        if not (host.IsForbidden and host:IsForbidden()) and host:GetNumChildren() == 1 then
            local panel = host:GetChildren()
            if PS.IsPanel(panel) then PS.Dress(panel, def) end
        end
    end
end

-- The first fill of a kind it draws on each tooltip. It creates that tooltip's
-- panel during the same fill and its post-call runs before ours (it starts on
-- load, ours at login), so the panel is dressed before it's drawn. Repeated next
-- frame in case that ordering doesn't hold.
function PS.OnData(def, tip, data)
    if PS.seen[tip] or not DUI.PrettyAside.Covers(data) then return end
    PS.seen[tip] = true
    PS.Walk(def)
    C_Timer.After(0, Engine.Safe(def, function() PS.Walk(def) end))
end

Engine.Register({ key = "prettytooltip", pack = "addons", addon = ADDON, switch = "prettytooltip",
    label = "PrettyTooltip", thirdParty = true, apply = function(_, def)
    local TDP = _G.TooltipDataProcessor
    if not (isTable(TDP) and TDP.AddTooltipPostCall and TDP.AllTypes) then return end
    for _, name in ipairs(PS.FONTS) do Style.DressText(_G[name]) end
    TDP.AddTooltipPostCall(TDP.AllTypes, Engine.Safe(def, function(tip, data) PS.OnData(def, tip, data) end))
    -- Panels created before now (none after a /reload, but a late start could).
    PS.Walk(def)
end })
