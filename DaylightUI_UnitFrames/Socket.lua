-- The "set into the frame" portrait look. The frame's border runs on around
-- the portrait: the ring's outer band is drawn in the frame shell's own border
-- layers (Style.ShellJoin), so it merges with the bar's border instead of
-- lying over it, and the bar is cut back where the ring sits. The portrait's
-- own ring is drawn a little smaller inside that band. A portrait on its own
-- (portraitAt "free") wears the same band, closed all the way round, on the
-- portrait itself, and its frame is left with a plain whole end.
-- Nothing here is protected or runs per frame: it is laid out with the frame.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style
local Pixel = DUI.Pixel

local L = DUI.L

local Socket = {}
ns.Socket = Socket

Socket.LOOKS = { socket = "2.0", classic = "Classic" }
Socket.LOOK_ORDER = { "socket", "classic" }
-- The socket's own ring (tools/make_socket_art.py): a thin flat line round the
-- picture, black on either side. In the portrait's radius R: the picture is
-- PICTURE of it, then a HAIR of black, then the line (its inside is the
-- width's share of its outside), then black out to the frame's band.
Socket.RING_OUTER = 0.60      -- the line's outside, as a share of its image's half-size
Socket.RING_WIDTHS = { thin = 0.918, normal = 0.897, thick = 0.858 }
Socket.PICTURE = 0.755
Socket.HAIR = 0.03
Socket.GAP_PX = 2             -- the black between picture and line never narrower than this, in screen pixels
Socket.SIZE = 1.2             -- drawn this much bigger than Classic at the same Portrait size
Socket.TAG_AT = 0.7           -- the level tag's middle, past the ring's middle toward the bar
Socket.SHADOW_FILL = 0.85     -- the shadow art's solid part, as a share of its half-size
Socket.CAST_REACH = 0.15      -- the shadow cast on the bar, past the ring, as a share of its half-size
Socket.CAST_SHIFT = 2         -- px toward the bar and down: light from above the ring's far side
Socket.CAST_ALPHA = 0.35
Socket.SHADOW_K = 0.6          -- the ring's drop shadow against the frame's: a round blob reads darker than an edge
Socket.VIGNETTE_ALPHA = 1
-- Where a round ring meets the bar's top and bottom edges the border curves on
-- into the bar (a fillet), the same top and bottom; square and angled meet it
-- at a right angle. The fillet's numbers match the art
-- (tools/make_socket_art.py), in the ring's radius.
Socket.FILLET = { turn = 0.34, reach = 0.4 }
Socket.FILLET_FILE = DUI.MEDIA .. "socket-fillet.png"
Socket.DISC = DUI.MEDIA .. "socket-disc.png"
Socket.VIGNETTE = DUI.MEDIA .. "portrait-vignette.png"

-- The ring's size on the classic ring's radius R: the line's outer radius,
-- its inside as a share of that, and the picture's radius (Classic's size).
function Socket.RingSize(R, width)
    local ratio = Socket.RING_WIDTHS[width] or Socket.RING_WIDTHS.normal
    local inside = (Socket.PICTURE + Socket.HAIR) * R
    return inside / ratio, ratio, Socket.PICTURE * R
end


-- The line's art, plain and shaded from above, for a shape (UF.ShapeArt).
function Socket.RingFiles(width, art)
    width = Socket.RING_WIDTHS[width] and width or "normal"
    local base = DUI.MEDIA .. "socket-" .. (art and art .. "-" or "") .. "ring-" .. width
    return base .. ".png", base .. "-lit.png"
end

local function solidArt(art)
    return art and (DUI.MEDIA .. "portrait-" .. art .. "-hole.png") or Socket.DISC
end
local function shadowArt(art)
    return DUI.MEDIA .. "portrait-" .. (art and art .. "-" or "") .. "shadow.png"
end

-- The shell the socket joins: a full one with a border.
local function shellFor(f)
    local s = Style.GetShell(f)
    if not s or s.lean or s.opts.noBorder then return nil end
    return s
end

function Socket.Wanted(f, cfg, mode)
    return cfg.portraitLook ~= "classic" and mode ~= "none" and shellFor(f) ~= nil
end

-- Where pixels are measured: the holder of a portrait on its own carries its
-- mover's scale.
local function measure(f)
    return (f.portraitFree and f.portraitHolder) or f
end

-- How much the inner ring shrinks to leave room for the outer band.
function Socket.Inset(f)
    local m = measure(f)
    local one = Pixel.Px(m, 1)
    local T = Pixel.Px(m, Style.BorderPx(f))
    return math.max(0, T - one)
end

-- The socket's outer edge, built out from the classic radius R: the line, then
-- the frame's whole border (its inner black line is the gap). A shape's is
-- worked out on its half-side and given back as a radius like R. free says
-- where it will sit, since the frame may not know yet.
function Socket.Outer(f, R, width, shapeArt, free)
    local s = shapeArt and ns.UF.SQUARE or 1
    local line = Socket.RingSize(R, width)
    local m = measure(f)
    if free ~= nil then m = (free and f.portraitHolder) or f end
    local T = Pixel.Px(m, Style.BorderPx(f))
    return (line * s + T) / s
end

-- The set in use: the portrait's own for a portrait on its own, else the
-- shell's join. nil with the look off.
function Socket.Join(f)
    if not f.socketOn then return nil end
    if f.portraitFree then return f.portrait and f.portrait.own end
    local s = Style.GetShell(f)
    return s and s.join
end

-- The part of the square [cx-r, cx+r] x [cy-r, cy+r] inside the box, and its
-- texture coordinates (v grows downward). nil when they don't overlap.
function Socket.Crop(cx, cy, r, left, right, bottom, top)
    local x0, x1 = math.max(cx - r, left), math.min(cx + r, right)
    local y0, y1 = math.max(cy - r, bottom), math.min(cy + r, top)
    if x1 <= x0 or y1 <= y0 or r <= 0 then return nil end
    local d = 2 * r
    local u0, u1 = (x0 - (cx - r)) / d, (x1 - (cx - r)) / d
    local v0, v1 = ((cy + r) - y1) / d, ((cy + r) - y0) / d
    return x0, x1, y0, y1, u0, u1, v0, v1
end

-- How far along the bar, from its outer end, the outline crosses the bar's
-- bottom edge. nil when the shape is shorter than the bar.
function Socket.JoinX(reach, dy, off, square)
    if not (reach > dy) then return nil end
    if square then return reach - off end
    return math.sqrt(reach * reach - dy * dy) - off
end

local function hideSet(set)
    if not set then return end
    set.outline:Hide(); set.band:Hide(); set.shadow:Hide()
    for _, t in ipairs(set.outlines or {}) do t:Hide() end
    for _, t in ipairs(set.bands or {}) do t:Hide() end
end

-- A set that goes away also loses its aggro color, so a portrait detached
-- mid-fight leaves nothing red behind.
local function clearSet(set)
    if not set then return end
    hideSet(set)
    set.color, set.flag = nil, nil
end

-- The ring's part over the bar: its own frame just under the portrait, above
-- every bar, so nothing of the bar draws over it. Not on the portrait itself,
-- which pops in on arrival: the socket is part of the frame and holds still.
local function makeSocket(f)
    local fr = CreateFrame("Frame", nil, f)
    fr:SetAllPoints(f)
    fr:EnableMouse(false)
    fr.cast = fr:CreateTexture(nil, "BACKGROUND", nil, -1)
    fr.gap = fr:CreateTexture(nil, "BACKGROUND", nil, 0)
    fr.gapBand = fr:CreateTexture(nil, "BACKGROUND", nil, 1)
    fr.cast:Hide(); fr.gap:Hide(); fr.gapBand:Hide()
    f.socket = fr
    return fr
end

local function makeVignette(p)
    p.vignette = p.top:CreateTexture(nil, "ARTWORK", nil, 0)
    p.vignette:SetTexture(Socket.VIGNETTE)
    p.vignette:SetVertexColor(0, 0, 0, Socket.VIGNETTE_ALPHA)
    p.vignette:SetPoint("CENTER", p, "CENTER", 0, 0)
    p.vignetteMask = p.top:CreateMaskTexture()
    p.vignetteMask:SetPoint("CENTER", p, "CENTER", 0, 0)
    p.vignette:AddMaskTexture(p.vignetteMask)
    p.vignette:Hide()
end

local function makeOwn(p)
    p.own = {
        shadow = p:CreateTexture(nil, "BACKGROUND", nil, -8),
        outline = p:CreateTexture(nil, "BACKGROUND", nil, -6),
        band = p:CreateTexture(nil, "BACKGROUND", nil, -5),
    }
    hideSet(p.own)
end

-- Places a cropped piece: the part of a square of half-size r at (cx, cy)
-- that lies inside the bar.
local function placeCrop(tex, f, cx, cy, r, box)
    local x0, x1, y0, y1, u0, u1, v0, v1 = Socket.Crop(cx, cy, r, box[1], box[2], box[3], box[4])
    if not x0 then
        tex:Hide()
        return
    end
    tex:ClearAllPoints()
    tex:SetTexCoord(u0, u1, v0, v1)
    tex:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x0, y0)
    tex:SetPoint("TOPRIGHT", f, "BOTTOMLEFT", x1, y1)
    tex:Show()
end

local function placeWhole(tex, rel, size, x, y, point)
    tex:ClearAllPoints()
    tex:SetSize(size, size)
    tex:SetPoint("CENTER", rel, point or "CENTER", x or 0, y or 0)
end

-- The drop shadow fades out over the frame's own shadow width from the
-- ring's edge, like the shell's: its art's solid part stays under the ring.
local function shadowSize(m, shell, half)
    local S = Pixel.Px(m, shell.opts.shadowPx or DUI:Get("general", "shadowPx") or 0)
    return 2 * (half + S)
end

-- The fillet's box for a ring of radius r whose middle is e from the bar's
-- edge, in the ring's own terms (x along the bar from the ring's middle, y away
-- from the bar's middle): x0, x1, y0, y1. nil when the ring doesn't reach past
-- the edge.
function Socket.FilletBox(r, e)
    if not (r > e) or e <= 0 then return nil end
    local jx = math.sqrt(r * r - e * e)
    local t = math.atan2(e, jx) + Socket.FILLET.turn
    return r * math.cos(t), jx + Socket.FILLET.reach * r, e, r * math.sin(t)
end

-- Places a piece drawn for the top edge with the bar to the right (the art's
-- way) at its box, mirrored for the other end and the bottom edge.
local function placeBox(tex, f, cx, cy, dir, vdir, x0, x1, y0, y1)
    local ax, bx = cx + dir * x0, cx + dir * x1
    local ay, by = cy + vdir * y0, cy + vdir * y1
    local l, r = math.min(ax, bx), math.max(ax, bx)
    local b, t = math.min(ay, by), math.max(ay, by)
    tex:ClearAllPoints()
    tex:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", l, b)
    tex:SetPoint("TOPRIGHT", f, "BOTTOMLEFT", r, t)
    local u0, u1 = 0, 1
    if dir < 0 then u0, u1 = 1, 0 end
    local v0, v1 = 0, 1
    if vdir < 0 then v0, v1 = 1, 0 end
    tex:SetTexCoord(u0, u1, v0, v1)
    tex:Show()
end

local function edgePieces(shell, join)
    if join.outlines then return end
    join.outlines, join.bands = {}, {}
    for i = 1, 2 do
        join.outlines[i] = shell:CreateTexture(nil, "BORDER", nil, 0)
        join.bands[i] = shell:CreateTexture(nil, "BORDER", nil, 3)
    end
end

-- The frame's border flowing into the ring: a fillet where a round ring meets
-- the bar's top and bottom edges. Edges the ring doesn't reach past get
-- none.
function Socket.LayoutEdges(f, shell, join, geo, cx, cy, one, heavy)
    edgePieces(shell, join)
    local H = f:GetHeight()
    local dir = geo.outerRight and -1 or 1
    local half = geo.half
    if geo.shapeArt then
        -- A square or angled portrait meets the bar at a clean right angle.
        for i = 1, 2 do join.outlines[i]:Hide(); join.bands[i]:Hide() end
        return
    end
    for i, vdir in ipairs({ 1, -1 }) do
        local e = vdir > 0 and (H - cy) or cy
        -- One piece, the band's color with its own dark edge (all outline with
        -- no band), reaching a pixel into the bar so it covers the bar's
        -- outline where the two meet.
        local piece, other = join.bands[i], join.outlines[i]
        if not heavy then piece, other = other, piece end
        other:Hide()
        piece:SetTexture(Socket.FILLET_FILE)
        local x0, x1, y0, y1 = Socket.FilletBox(half, e)
        if x0 then placeBox(piece, f, cx, cy, dir, vdir, x0, x1, y0 - one, y1) else piece:Hide() end
    end
end

-- geo = { R, half, off, outerRight, shapeArt, opening, free }, or nil for off.
function Socket.Layout(f, geo)
    local p = f.portrait
    local shell = shellFor(f)
    local join = shell and Style.ShellJoin(f)
    if not geo or not shell or not p then
        f.socketOn = false
        f.socketJoinX = nil
        clearSet(join)
        if p then
            clearSet(p.own)
            if p.vignette then p.vignette:Hide() end
        end
        if f.socket then f.socket.gap:Hide(); f.socket.gapBand:Hide(); f.socket.cast:Hide() end
        return
    end
    f.socketOn = true
    local side = geo.outerRight and "right" or "left"
    local solid, soft = solidArt(geo.shapeArt), shadowArt(geo.shapeArt)
    local half = geo.half
    local m = measure(f)
    local one = Pixel.Px(m, 1)
    local heavy = Style.IsHeavy(shell)

    -- The picture's shading, both on the frame and on its own.
    if not p.vignette then makeVignette(p) end
    -- It reaches past the picture into the black gap. Cut at the picture's own
    -- edge, its soft edge pixels were shaded less than the ones just inside and
    -- showed as a ring of bright specks round the art.
    local open = 2 * geo.opening + 2 * Pixel.Px(m, Socket.GAP_PX)
    p.vignette:SetSize(open, open)
    p.vignetteMask:SetTexture(solid, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    p.vignetteMask:SetSize(open, open)
    p.vignette:Show()

    local socket = f.socket or makeSocket(f)
    socket:SetFrameLevel(math.max(0, p:GetFrameLevel() - 1))

    if geo.free then
        clearSet(join)
        socket.gap:Hide(); socket.gapBand:Hide(); socket.cast:Hide()
        f.socketJoinX = nil
        if not p.own then makeOwn(p) end
        local own = p.own
        own.side, own.shadowK = side, Socket.SHADOW_K
        own.outline:SetTexture(solid)
        own.band:SetTexture(solid)
        own.shadow:SetTexture(soft)
        placeWhole(own.outline, p, 2 * half)
        placeWhole(own.band, p, 2 * (half - one))
        placeWhole(own.shadow, p, shadowSize(m, shell, half), 0, -one)
        own.outline:Show()
        own.band:SetShown(heavy)
        own.shadow:Show()
        Style.PaintJoin(own, shell)
        Socket.Threat(f, f.threatNow, f.threatFlag)
        return
    end

    clearSet(p.own)
    local W, H = f:GetWidth(), f:GetHeight()
    local T = Pixel.Px(f, Style.BorderPx(f))
    local cx = geo.outerRight and (W + geo.off) or -geo.off
    local cy = H / 2 + (f.portraitY or 0)

    join.side, join.shadowK = side, Socket.SHADOW_K
    -- The bar's lit top line would end at the ring on top, with nothing like
    -- it below: off, so the frame meets the ring the same top and bottom.
    shell.opts.noLit = true
    join.outline:SetTexture(solid)
    join.band:SetTexture(solid)
    join.shadow:SetTexture(soft)
    placeWhole(join.outline, f, 2 * half, cx, cy, "BOTTOMLEFT")
    placeWhole(join.band, f, 2 * (half - one), cx, cy, "BOTTOMLEFT")
    placeWhole(join.shadow, f, shadowSize(f, shell, half), cx, cy - one, "BOTTOMLEFT")
    join.outline:Show()
    join.band:SetShown(heavy)
    join.shadow:Show()
    Socket.LayoutEdges(f, shell, join, geo, cx, cy, one, heavy)
    join.rings = { socket.gapBand }
    Style.PaintJoin(join, shell)

    -- Inside the bar the ring keeps its whole border, outline and band, so it
    -- is as thick there as outside, with a soft shadow it casts on the bar.
    local box = { T, W - T, T, H - T }
    local bc = shell.opts.borderColor or Style.BORDER
    socket.gap:SetTexture(solid)
    socket.gap:SetVertexColor(bc[1], bc[2], bc[3], 1)
    placeCrop(socket.gap, f, cx, cy, half, box)
    socket.gapBand:SetTexture(solid)
    placeCrop(socket.gapBand, f, cx, cy, half - one, box)
    if not heavy then socket.gapBand:Hide() end
    local toward = geo.outerRight and -1 or 1
    local shift = Pixel.Px(f, Socket.CAST_SHIFT)
    socket.cast:SetTexture(soft)
    socket.cast:SetVertexColor(0, 0, 0, Socket.CAST_ALPHA)
    placeCrop(socket.cast, f, cx + toward * shift, cy - shift,
        half * (1 + Socket.CAST_REACH), box)

    -- The level tag sits on the bottom join, when the ring reaches past it.
    f.socketJoinX = Socket.JoinX(half, cy, geo.off, geo.shapeArt ~= nil)
        and (Socket.TAG_AT * geo.R - geo.off) or nil
    -- The set just shown takes the threat color the frame has now.
    Socket.Threat(f, f.threatNow, f.threatFlag)
end

-- Threat colors the whole ring, its outer band too, but never the bar's own
-- border: the player's frame would be red-edged for a whole fight. The band is
-- fight information, so it changes at once while the inner ring fills.
function Socket.Threat(f, color, flag)
    local j = Socket.Join(f)
    local s = Style.GetShell(f)
    if not (j and s) then return end
    if color then
        Style.SetJoinBand(j, s, color)
    elseif type(flag) ~= "nil" then
        Style.JoinBandFromBoolean(j, s, flag, ns.UF.THREAT_COLORS.aggro)
    else
        Style.SetJoinBand(j, s, nil)
    end
end

-- Players who had the classic ring before are asked once per account which
-- look they want, with the two side by side. New profiles start set into the
-- frame and are never asked.
Socket.ASK_DELAY = 3     -- seconds after login
Socket.ASK_KEY = "portraitLook"

Socket.ASK_FRAMES = { "player", "target", "focus", "party", "arena" }

function Socket.ShouldAsk()
    local DB = DUI.DB
    if DB.Root().portraitLookAsked or DB.fresh or DB.Unsaved() then return false end
    if not ns.module then return false end
    for _, id in ipairs(Socket.ASK_FRAMES) do
        local shows = DUI:Get("UnitFrames", id .. ".portrait")
        if shows ~= nil and shows ~= "none" and DUI:Get("UnitFrames", id .. ".portraitLook") == "classic" then
            return true
        end
    end
    return false
end

function Socket.Ask()
    if not Socket.ShouldAsk() then return end
    if DUI.InstallerUI and DUI.InstallerUI.IsShown() then return end
    if DUI.Tour and DUI.Tour.AskShown and DUI.Tour.AskShown() then
        C_Timer.After(Socket.ASK_DELAY, Socket.Ask)
        return
    end
    if InCombatLockdown() then return DUI.AfterCombat(Socket.Ask, "portrait ask") end
    local function done() DUI.DB.Root().portraitLookAsked = true end
    DUI.Widgets.Ask({
        key = Socket.ASK_KEY, title = L["New portrait mode"],
        text = L["Portraits can now be set into their frame: the border runs around both as one piece. Which do you want? Each frame's page has it under Portrait look."],
        yes = L["2.0"], no = L["Keep Classic"],
        preview = {
            height = ns.Sample.LOOK_FRAME + ns.Sample.LOOK_GAP + Style.SIZE.body + 4 + Style.SIZE.small + 2,
            show = function(holder)
                local box = Socket.askBox or ns.Sample.Looks(holder)
                Socket.askBox = box
                box:SetParent(holder)
                box:ClearAllPoints()
                box:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
                box.Refresh(holder:GetWidth())
                box:Show()
            end,
            hide = function() if Socket.askBox then Socket.askBox:Hide() end end,
        },
        onYes = function()
            done()
            for _, id in ipairs(Socket.ASK_FRAMES) do DUI:Set("UnitFrames", id .. ".portraitLook", "socket") end
        end,
        onNo = done,
    })
end

DUI.RegisterEvent("PLAYER_LOGIN", function() C_Timer.After(Socket.ASK_DELAY, Socket.Ask) end)
