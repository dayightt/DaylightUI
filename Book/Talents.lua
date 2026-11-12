-- Talents page: the class's three trees side by side, built from TalentData
-- with the game's arrows, ranks and rules. Each tree has a header (icon,
-- name, points spent) over its grid. The top row has the talent set tabs and
-- search; the footer shows points left, the per-tree split, and Apply/Undo,
-- or Activate for an inactive set.
--
-- Spending goes through Spend, which uses the game's staging. Click buys a
-- rank, right-click refunds a staged one, and a refused click shakes the
-- tile. When a talent is maxed, light runs down its arrows and wakes the
-- talents it unlocks; a newly reached row wakes left to right; Undo drains
-- it all back. Each tile's ring fills clockwise from the top with its ranks.
-- After a successful Apply, a gold band sweeps down each tree and newly
-- learned talents turn gold as it passes.
--
-- Tiles and arrows are pooled per tree and reused on every fill. The page
-- reads the tree when shown, and again one frame after any talent event.

local _, DUI = ...
DUI.Book = DUI.Book or {}   -- the book window's own namespace
local ns = DUI.Book
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win
local Motion = DUI.Motion

local Talents = {}
ns.Talents = Talents

Talents.EDGE = 12        -- page edge
Talents.GAP = 6          -- between trees
Talents.TOP = 40         -- sets and search row
Talents.FOOT = 60        -- footer
Talents.HEAD = 38        -- tree header
Talents.PAD = 8          -- padding around each grid
Talents.TILE = 0.74      -- tile size as a fraction of the pitch
Talents.WIDE = 1.2       -- column spacing relative to rows, when there's room
Talents.MAX_PITCH = 52
Talents.DIM = 0.28       -- alpha for tiles the search doesn't match
Talents.WAKE_STEP = 0.06 -- delay between tiles when a row wakes
Talents.RING = 3         -- ring width around a tile
Talents.TIP = 11         -- glowing tip on a sweeping ring, px
Talents.WAVE = 0.8       -- seconds for the Apply wave to cross a tree
Talents.WAVE_H = 70      -- wave band height

-- Ring colors. Partly learned rings use the accent.
Talents.LOCKED = { 0.14, 0.13, 0.11 }
Talents.AVAIL = { 0.29, 0.28, 0.25 }
Talents.AVAIL_LIGHT = 0.62  -- icon brightness for an available talent with no points
Talents.FULL = { 0.95, 0.76, 0.31 }
Talents.STAGED = { 0.39, 0.82, 0.48 }
Talents.WAKE = { 1, 0.93, 0.8 }

-- Per-tree text color: the label tint mixed 35% toward the class gradient
-- (tree 1 one end, tree 2 the middle, tree 3 the other end), so the trees
-- read apart without turning into a rainbow.
Talents.TREE_MIX = 0.35
function Talents.TreeColor(i, token)
    local base = Style.INK.LABEL
    local G = DUI.Gradients
    local lo, hi
    if G and G.RGB and token then lo, hi = G.RGB(token) end
    if type(lo) ~= "table" or type(hi) ~= "table" then return base[1], base[2], base[3] end
    local t = i == 1 and 0 or i == 2 and 0.5 or 1
    local m = Talents.TREE_MIX
    local out = {}
    for k = 1, 3 do
        local c = lo[k] + (hi[k] - lo[k]) * t
        out[k] = base[k] + (c - base[k]) * m
    end
    return out[1], out[2], out[3]
end

local function classToken()
    local _, token = UnitClass("player")
    return token
end

local function hex(r, g, b)
    return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

Talents.EVENTS = { "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "TRAIT_TREE_CURRENCY_INFO_UPDATED",
    "PLAYER_TALENT_UPDATE", "ACTIVE_COMBAT_CONFIG_CHANGED", "SPELLS_CHANGED", "CONFIG_COMMIT_FAILED",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }

local WHITE = "Interface\\Buttons\\WHITE8X8"

local function tex(parent, layer, sub)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(WHITE)
    return t
end

local function rgb(t, c, a) t:SetVertexColor(c[1], c[2], c[3], a or 1) end
local function color(fs, c) fs:SetTextColor(c[1], c[2], c[3], 1) end
local function sound(name) if DUI.Sound then DUI.Sound.Play(name) end end

-- ---------------------------------------------------------------------
-- Tiles
-- ---------------------------------------------------------------------

local function makeTile(parent)
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local r = Talents.RING
    b.ring = tex(b, "BACKGROUND", -1)   -- track for the rank ring
    b.ring:SetPoint("TOPLEFT", b, "TOPLEFT", -r, r)
    b.ring:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", r, -r)
    b.arc = {}
    for i = 1, 5 do b.arc[i] = tex(b, "BACKGROUND") end
    b.tip = b:CreateTexture(nil, "OVERLAY", nil, 5)
    b.tip:SetTexture(DUI.MEDIA .. "glow.png")
    b.tip:SetBlendMode("ADD")
    b.tip:SetSize(Talents.TIP, Talents.TIP)
    b.tip:Hide()
    b.well = tex(b, "BACKGROUND", 1)
    b.well:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
    b.well:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
    b.well:SetVertexColor(0.02, 0.02, 0.025, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    Style.CropIcon(b.icon)
    -- Wake flash over the ring, and the Apply shine across the icon.
    b.flash = tex(b, "OVERLAY", 6)
    b.flash:SetPoint("TOPLEFT", b, "TOPLEFT", -3, 3)
    b.flash:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 3, -3)
    b.flash:SetBlendMode("ADD")
    rgb(b.flash, Talents.WAKE, 0.55)
    b.flash:Hide()
    b.shine = tex(b, "OVERLAY", 7)
    b.shine:SetBlendMode("ADD")
    b.shine:Hide()
    b.badge = CreateFrame("Frame", nil, b)
    b.badge:SetSize(24, 13)
    b.badge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 6, -6)
    b.badge:SetFrameLevel(b:GetFrameLevel() + 2)
    b.badge.bg = tex(b.badge, "BACKGROUND")
    b.badge.bg:SetAllPoints(b.badge)
    b.badge.bg:SetVertexColor(0.047, 0.047, 0.055, 1)
    b.rank = Style.Text(b.badge, Style.SIZE.tiny, "CENTER")
    b.rank:SetPoint("CENTER", b.badge, "CENTER", 0, 0)
    b:SetScript("OnEnter", function(self)
        self.over = true
        Talents.PaintTile(self)
        Talents.Tip(self)
    end)
    b:SetScript("OnLeave", function(self)
        self.over = nil
        if Talents.waiting == self then Talents.waiting = nil end
        Talents.PaintTile(self)
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    b:SetScript("OnClick", function(self, button) Talents.Click(self, button) end)
    return b
end

-- "max" | "part" | "avail" | "locked"
function Talents.StateOf(node)
    if node.rank >= node.max then return "max" end
    if node.rank > 0 then return "part" end
    if node.available then return "avail" end
    return "locked"
end

-- Still green: unapplied, or applied but the Apply wave hasn't reached it yet.
function Talents.Staged(node)
    return node.staged or (Talents.wave ~= nil and Talents.wave[node.id] == true)
end

-- ---------------------------------------------------------------------
-- Rank ring: five strips around the tile (top right half, right, bottom,
-- left, top left half), lit clockwise from top center up to fraction v.
-- ---------------------------------------------------------------------

local function arcPieces(b)
    local t = Talents.RING
    local W = (b.side or b:GetWidth() or 30) + 2 * t
    return W, t, {
        W / 2,      -- top, middle to the right corner
        W - t,      -- right side, down
        W - t,      -- bottom, right to left
        W - t,      -- left side, up
        W / 2 - t,  -- top, left corner to the middle
    }
end

-- Box (x, y, w, h) of strip i lit for len px, in ring space with y down
-- from the top-left, plus the leading point.
local function arcBox(i, len, W, t)
    if i == 1 then return W / 2, 0, len, t, W / 2 + len, t / 2 end
    if i == 2 then return W - t, t, t, len, W - t / 2, t + len end
    if i == 3 then return W - t - len, W - t, len, t, W - t - len, W - t / 2 end
    if i == 4 then return 0, W - t - len, t, len, t / 2, W - t - len end
    return t, 0, len, t, t + len, t / 2
end

-- tipA is the tip's alpha; nil hides the tip.
function Talents.DrawArc(b, v, tipA)
    b.arcAt = v
    local W, t, lens = arcPieces(b)
    local total = 0
    for _, l in ipairs(lens) do total = total + l end
    local left = math.max(0, math.min(v, 1)) * total
    local tx, ty
    for i, l in ipairs(lens) do
        local s = b.arc[i]
        local len = math.min(left, l)
        if len >= 0.5 then
            local x, y, w, h, px, py = arcBox(i, len, W, t)
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", b, "TOPLEFT", x - t, -(y - t))
            s:SetSize(w, h)
            s:Show()
            tx, ty = px, py
        else
            s:Hide()
        end
        left = left - l
    end
    if tipA and tx then
        b.tip:ClearAllPoints()
        b.tip:SetPoint("CENTER", b, "TOPLEFT", tx - t, -(ty - t))
        b.tip:SetAlpha(tipA)
        b.tip:Show()
    else
        b.tip:Hide()
    end
end

-- Animate the ring between two rank fractions. A ring that closes flashes,
-- then done runs (usually the arrow fill). Snaps when motion is off.
function Talents.Sweep(b, from, to, done)
    b.sweepKey = b.sweepKey or {}
    b.sweeping = true
    Talents.DrawArc(b, from)
    local up = to > from
    Motion.Tween(b.sweepKey, from, to, up and Motion.SLOW or Motion.NORMAL, function(v)
        Talents.DrawArc(b, v, math.min(1, math.abs(to - v) / 0.08 + 0.35))
    end, function()
        b.sweeping = nil
        local node = b.node   -- may differ if the set was switched mid-sweep
        Talents.DrawArc(b, node and node.max > 0 and node.rank / node.max or to)
        if up then
            b.swept = (b.swept or 0) + 1
            Motion.Bump(b.badge, 1.3, Motion.NORMAL)
            if to >= 1 then Motion.Flash(b.flash, Motion.SLOW) end
        end
            if done then done() end
    end)
end

-- Cancel the sweep when a pooled tile is reused for another talent.
function Talents.StopSweep(b)
    if not b.sweeping then return end
    b.sweeping = nil
    Motion.Tween(b.sweepKey, 0, 0, 0)   -- from == to drops the tween
    b.tip:Hide()
end

function Talents.PaintTile(b)
    local node = b.node
    if not node then return end
    local state = Talents.StateOf(node)
    local arc
    if Talents.Staged(node) then arc = Talents.STAGED
    elseif state == "max" then arc = Talents.FULL
    else arc = { Style.Accent() } end
    for _, s in ipairs(b.arc) do rgb(s, arc) end
    local tr, tg, tb = arc[1] + (1 - arc[1]) * 0.6, arc[2] + (1 - arc[2]) * 0.6, arc[3] + (1 - arc[3]) * 0.6
    b.tip:SetVertexColor(tr, tg, tb, 1)
    local ring = state == "locked" and Talents.LOCKED or Talents.AVAIL
    local hit = b.hit
    if hit then ring = { Style.Accent() } end
    rgb(b.ring, ring)
    if not b.sweeping then Talents.DrawArc(b, node.max > 0 and node.rank / node.max or 0) end
    b.icon:SetDesaturated(state == "locked")
    local light = (b.over and 1) or (state == "locked" and 0.36) or (state == "avail" and Talents.AVAIL_LIGHT) or 1
    if b.over and state == "locked" then light = 0.52 end
    b.icon:SetVertexColor(light, light, light, 1)
    b.badge:SetShown(state ~= "locked")
    b.rank:SetText(string.format("%d/%d", node.rank, node.max))
    local c = Talents.Staged(node) and Talents.STAGED or state == "max" and Talents.FULL or state == "part" and { Style.Pop() } or state == "avail" and Style.INK.LABEL or Style.INK.OFF
    b.rank:SetTextColor(c[1], c[2], c[3], 1)
    b:SetAlpha(b.dim and Talents.DIM or 1)
end

-- Requirement line: the number in red since it's what to read, the tree
-- name in its tree color, a talent name in white.
local function waitLine(line, token)
    local INK = Style.INK
    local B = INK.BAD
    local text = string.gsub(line.text, "%d+", function(d) return hex(B[1], B[2], B[3]) .. d .. "|r" end, 1)
    local name = line.name
    if type(name) == "string" and name ~= "" then
        local r, g, b
        if line.tree then r, g, b = Talents.TreeColor(line.tree.index or 1, token)
        else r, g, b = INK.VALUE[1], INK.VALUE[2], INK.VALUE[3] end
        local s, e = string.find(text, name, 1, true)
        if s then text = string.sub(text, 1, s - 1) .. hex(r, g, b) .. name .. "|r" .. string.sub(text, e + 1) end
    end
    return text
end

-- Rank count colored like the badge.
local function rankLine(node)
    local INK = Style.INK
    local state = Talents.StateOf(node)
    local c = node.staged and Talents.STAGED or state == "max" and Talents.FULL or state == "part" and { Style.Pop() } or INK.OFF
    return string.format(L["Rank %s/%d"], hex(c[1], c[2], c[3]) .. node.rank .. "|r", node.max)
end

-- Add a rank's full game tooltip lines, repainted through Tips.GameLine, or
-- just the description if there are none. Returns true while the spell is
-- still loading.
local function rankText(TD, Tips, node, rank)
    local lines = TD.EntryLines(node, rank)
    if lines then
        for _, l in ipairs(lines) do
            if l then Tips.GameLine(l.left, l.lc, l.right, l.rc) else Tips.Gap() end
        end
        return TD.Loading(node)
    end
    local text, loading = TD.Description(node, rank)
    if text then Tips.Text(Tips.Numbers(text)) end
    return loading
end

-- Name, rank, this rank's and the next rank's tooltip, unmet requirements,
-- then click hints in the game's own wording. If the spell isn't loaded yet
-- it's requested, and Talents.SpellLoaded redraws the tooltip when it arrives.
function Talents.Tip(b)
    local node = b.node
    if not (node and GameTooltip) then return end
    local TD, Tips = ns.TalentData, DUI.Tips
    local Spend = (b.box and b.box.spend) or ns.Spend
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    Tips.Clear()
    Tips.Title(node.name)
    Tips.Text(rankLine(node), Style.INK.LABEL)
    if rankText(TD, Tips, node, node.rank) then
        Talents.waiting = b
        TD.LoadSpell(node)
    end
    if node.rank > 0 and node.rank < node.max then
        Tips.Gap()
        Tips.Sub(L["Next rank:"])
        rankText(TD, Tips, node, node.rank + 1)
    end
    local box = b.box
    local data = (box and box.data) or Talents.data
    local missing = TD.Missing(node, data)
    if missing then
        Tips.Gap()
        local token = (box and box.token) or classToken()
        for _, line in ipairs(missing) do Tips.Text(waitLine(line, token)) end
    end
    -- Read-only trees (inspect) get no click hints.
    if not (box and box.readOnly) then
        local buy, back = Spend.CanBuy(node, data), Spend.CanRefund(node)
        if buy or back then Tips.Gap() end
        if buy then Tips.Hint(TALENT_BUTTON_TOOLTIP_PURCHASE_INSTRUCTIONS or L["Click to learn"]) end
        if back then Tips.Hint(TALENT_BUTTON_TOOLTIP_REFUND_INSTRUCTIONS or L["Right-click to unlearn"]) end
    end
    Tips.Flush(GameTooltip)
    GameTooltip:Show()
end

-- Redraw the hovered tooltip once its spell data has loaded.
function Talents.SpellLoaded(spellID)
    local b = Talents.waiting
    if not b or (issecretvalue and issecretvalue(spellID)) then return end
    if not (b.node and b.node.spellID == spellID) then return end
    Talents.waiting = nil
    if b.over and GameTooltip and GameTooltip:IsOwned(b) then Talents.Tip(b) end
end
DUI.RegisterEvent("SPELL_DATA_LOAD_RESULT", function(_, spellID) Talents.SpellLoaded(spellID) end)

-- Shift-click (CHATLINK, either button) links the talent, as in the game's
-- tree. Click buys, right-click refunds a staged rank, and a refused click
-- shakes the tile. Read-only trees only link.
function Talents.Click(b, button)
    local node = b.node
    if not node then return end
    if type(IsModifiedClick) == "function" and IsModifiedClick("CHATLINK") and node.spellID then
        local link = type(C_Spell) == "table" and C_Spell.GetSpellLink and C_Spell.GetSpellLink(node.spellID)
        local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
        if link and insert then insert(link) end
        return
    end
    local box = b.box
    if box and box.readOnly then return end
    local Spend = (box and box.spend) or ns.Spend
    local soon = (box and box.changed) or Talents.Soon
    if button == "RightButton" then
        if Spend.Refund(node) then sound("refund") ; soon()
        elseif node.rank > 0 then Talents.Shake(b) end
        return
    end
    local took = Spend.Buy(node, (box and box.data) or Talents.data, b)
    if took == "asked" then return end   -- choice node opened its menu (Legacy trees)
    if took then
        sound("spend")
        soon()
    else
        Talents.Shake(b)
    end
end

-- ---------------------------------------------------------------------
-- Tile animations: shake, wake, shine. Arrow fills live in Arrows.lua.
-- ---------------------------------------------------------------------

function Talents.Shake(b)
    sound("nope")
    if not (b.at and Motion.On()) then return end
    local x, y = b.at[1], b.at[2]
    local parent = b:GetParent()
    b.shakeKey = b.shakeKey or {}
    Motion.Tween(b.shakeKey, 0, 1, Motion.SLOW, function(p)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x + math.sin(p * math.pi * 5) * 3 * (1 - p), y)
    end, function()
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    end)
end

-- A newly available talent gets a bump and a warm flash.
function Talents.Wake(b, delay)
    local function go()
        if not (b:IsVisible() and b.node) then return end
        b.woke = (b.woke or 0) + 1
        Motion.Bump(b, 1.18, Motion.NORMAL)
        Motion.Flash(b.flash, Motion.SLOW)
    end
    if delay and delay > 0 and Motion.On() then C_Timer.After(delay, go) else go() end
end

-- Turn a newly learned talent gold: ring, outgoing arrows (with an
-- immediate spark), and a soft gold sweep across the icon.
function Talents.Shine(b, box)
    local node = b.node
    if Talents.wave and node then
        Talents.wave[node.id] = nil
        if not next(Talents.wave) then Talents.wave = nil end
    end
    b.shone = (b.shone or 0) + 1
    if not node then return end
    Talents.PaintTile(b)
    for _, a in ipairs(box and box.links or {}) do
        if a.from and a.from.id == node.id and not a.running then ns.Arrows.Paint(a, Talents.ArrowState(a.from), true) end
    end
    b.shine:SetHeight(b:GetHeight() or 30)
    Motion.Sweep(b.shine, b, { width = (b:GetWidth() or 30) * 0.6, dur = 0.5, alpha = 0.6, color = Talents.FULL, key = b.shine })
end

-- After a successful Apply, roll a gold band down each tree with newly
-- learned talents. Each turns gold as the band's center passes it, and
-- Talents.wave keeps it green until then. With motion off, all at once.
function Talents.Wave(page, ids)
    local found = {}
    for _, box in ipairs(page.trees) do
        local tiles = {}
        for _, id in ipairs(ids) do
            local b = box:IsShown() and box.byNode and box.byNode[id]
            if b then tiles[#tiles + 1] = b ; found[id] = true end
        end
        if #tiles > 0 then
            local band = box.wave
            local h, bh = box:GetHeight() or 0, Talents.WAVE_H
            local function release(y)
                for i = #tiles, 1, -1 do
                    local b = tiles[i]
                    if not y or Talents.HEAD - b.at[2] + (b.side or 0) / 2 <= y then
                        table.remove(tiles, i)
                        Talents.Shine(b, box)
                    end
                end
            end
            if Motion.On() then
                band:SetSize((box:GetWidth() or 0) + 40, bh)
                band:SetAlpha(0)
                band:Show()
                Motion.Tween(band, 0, 1, Talents.WAVE, function(e)
                    -- Undo the tween's ease-out and apply smoothstep, so
                    -- the band eases in and out at both ends.
                    local t = 1 - (1 - e) ^ (1 / 3)
                    local p = t * t * (3 - 2 * t)
                    local y = -bh / 2 + p * (h + bh)
                    band:ClearAllPoints()
                    band:SetPoint("CENTER", box, "TOP", 0, -y)
                    band:SetAlpha(p < 0.1 and p / 0.1 or (p > 0.85 and (1 - p) / 0.15 or 1))
                    release(y)
                end, function()
                    band:Hide()
                    release()
                end)
            else
                release()
            end
        end
    end
    -- Talents not shown in any tree don't wait for the wave.
    for _, id in ipairs(ids) do
        if Talents.wave and not found[id] then Talents.wave[id] = nil end
    end
    if Talents.wave and not next(Talents.wave) then Talents.wave = nil end
end

-- ---------------------------------------------------------------------
-- Trees
-- ---------------------------------------------------------------------

-- Other windows (inspect, Legacy) can set these before FillTree:
--   box.readOnly  clicks only link, no learn/unlearn hints
--   box.token     class whose colors to use (nil = the player's)
--   box.index     tree number, 1-3
--   box.spend     object with CanBuy/CanRefund/Buy/Refund (nil = Spend.lua)
--   box.changed   called after a successful click (nil = Talents.Soon)
function Talents.MakeTree(page)
    local box = CreateFrame("Frame", nil, page)
    box.bg = tex(box, "BACKGROUND")
    box.bg:SetAllPoints(box)
    box.bg:SetVertexColor(0.06, 0.06, 0.068, 0.9)
    box.glow = box:CreateTexture(nil, "BACKGROUND", nil, 1)
    box.glow:SetTexture(WHITE)
    box.glow:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    box.glow:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
    box.glow:SetHeight(Talents.HEAD + 30)
    box.icon = box:CreateTexture(nil, "ARTWORK")
    box.icon:SetSize(22, 22)
    box.icon:SetPoint("LEFT", box, "TOPLEFT", Talents.PAD + 2, -Talents.HEAD / 2)
    box.mask = box:CreateMaskTexture()
    box.mask:SetTexture(Win.MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    box.mask:SetAllPoints(box.icon)
    box.icon:AddMaskTexture(box.mask)
    box.name = Style.Text(box, Style.SIZE.head, "LEFT")
    box.name:SetPoint("LEFT", box.icon, "RIGHT", 7, 0)
    box.pts = Style.Text(box, Style.SIZE.body, "RIGHT")
    box.pts:SetPoint("RIGHT", box, "TOPRIGHT", -Talents.PAD - 2, -Talents.HEAD / 2)
    box.name:SetPoint("RIGHT", box.pts, "LEFT", -6, 0)
    box.name:SetWordWrap(false)
    box.grid = CreateFrame("Frame", nil, box)
    box.tiles, box.arrows = {}, {}
    -- Apply wave layer above the tiles, clipped to the tree.
    box.over = CreateFrame("Frame", nil, box)
    box.over:SetAllPoints(box)
    box.over:SetFrameLevel(box:GetFrameLevel() + 20)
    box.over:SetClipsChildren(true)
    box.wave = box.over:CreateTexture(nil, "OVERLAY")
    box.wave:SetTexture(DUI.MEDIA .. "glow.png")
    box.wave:SetBlendMode("ADD")
    rgb(box.wave, Talents.FULL)
    box.wave:Hide()
    return box
end

local function tile(box, i)
    local b = box.tiles[i]
    if not b then
        b = makeTile(box.grid)
        b.box = box
        box.tiles[i] = b
    end
    return b
end

local function arrow(box, i)
    local a = box.arrows[i]
    if not a then
        a = ns.Arrows.New(box.grid)
        box.arrows[i] = a
    end
    return a
end

-- Lit once the source talent is maxed, green while that's still unapplied.
function Talents.ArrowState(src)
    if src.rank < src.max then return "off" end
    return Talents.Staged(src) and "staged" or "lit"
end

function Talents.FillTree(box, t, pitch, size, data, px)
    box.data = data
    box.tree = t
    if t.icon then box.icon:SetTexture(t.icon) end
    box.icon:SetShown(t.icon ~= nil)
    box.name:SetText(t.name)
    box.pts:SetText(tostring(t.spent))
    Style.InkText(box.pts, t.spent > 0 and "VALUE" or "OFF")
    box.name:SetTextColor(Talents.TreeColor(box.index or 1, box.token or classToken()))
    local ar, ag, ab = Style.Accent()
    box.glow:SetGradient("VERTICAL", CreateColor(ar, ag, ab, 0), CreateColor(ar, ag, ab, 0.1))
    local gw, gh = (t.cols - 1) * px + size, (t.rows - 1) * pitch + size
    box.grid:ClearAllPoints()
    box.grid:SetPoint("TOP", box, "TOP", 0, -Talents.HEAD)
    box.grid:SetSize(gw, gh)
    local byID = {}
    box.byNode = {}
    for i, node in ipairs(t.nodes) do
        local b = tile(box, i)
        if b.node and b.node.id ~= node.id then Talents.StopSweep(b) end
        b.node = node
        b.icon:SetTexture(node.icon)
        b.at = { node.col * px, -node.row * pitch }
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", box.grid, "TOPLEFT", b.at[1], b.at[2])
        b:SetSize(size, size)
        b.side = size
        b:Show()
        byID[node.id] = node
        box.byNode[node.id] = b
        Talents.PaintTile(b)
        -- Refresh the tooltip right away if this tile is hovered.
        if b.over and GameTooltip and GameTooltip:IsOwned(b) then Talents.Tip(b) end
    end
    for i = #t.nodes + 1, #box.tiles do box.tiles[i]:Hide(); box.tiles[i].node = nil end
    local n = 0
    box.links = {}
    for _, src in ipairs(t.nodes) do
        for _, e in ipairs(src.edges) do
            local to = byID[e.to] or (data and data.byID[e.to])
            if to and to.tree == t then
                n = n + 1
                local a = arrow(box, n)
                -- Keep a running fill only if the pooled arrow still links
                -- the same two talents.
                if a.running and not (a.from and a.from.id == src.id and a.to and a.to.id == to.id) then ns.Arrows.Stop(a) end
                a.from, a.to = src, to
                ns.Arrows.Place(a, src, to, pitch, size, px)
                if not a.running then ns.Arrows.Paint(a, Talents.ArrowState(src)) end
                box.links[n] = a
            end
        end
    end
    for i = n + 1, #box.arrows do ns.Arrows.Hide(box.arrows[i]) end
end

-- ---------------------------------------------------------------------
-- Change animations: fill, drain and wake
-- ---------------------------------------------------------------------

local function open(node) return node.available and node.edgesMet end

-- Snapshot what the page shows, to diff against on the next fill.
function Talents.Remember(page, data)
    local seen = { configID = data.configID, nodes = {} }
    for id, node in pairs(data.byID) do
        seen.nodes[id] = { full = node.rank >= node.max, staged = node.staged, open = open(node), rank = node.rank }
    end
    page.seen = seen
end

-- Animate only between two fills of the same set while the page stays
-- open; opening the page or switching sets doesn't animate. Works on any
-- page with tree boxes in page.trees, including the Legacy window.
function Talents.Animate(page, data)
    local seen = page.seen
    if not (seen and seen.configID == data.configID and page.shownBefore) then return end
    local A = ns.Arrows
    local woken, closing = {}, {}
    -- Sweep rings whose rank changed. When a ring closes, its outgoing
    -- arrows wait for the sweep to finish before filling.
    for _, box in ipairs(page.trees) do
        if box:IsShown() then
            for _, b in ipairs(box.tiles) do
                local node = b.node
                local was = node and b:IsShown() and seen.nodes[node.id]
                if was and was.rank and was.rank ~= node.rank and node.max > 0 then
                    local wait = {}
                    if node.rank >= node.max then closing[node.id] = wait end
                    Talents.Sweep(b, was.rank / node.max, node.rank / node.max, function()
                        for _, fn in ipairs(wait) do fn() end
                    end)
                end
            end
        end
    end
    for _, box in ipairs(page.trees) do
        if box:IsShown() then
            for _, a in ipairs(box.links or {}) do
                local was = seen.nodes[a.from.id]
                local full = a.from.rank >= a.from.max
                if was and not was.full and full then
                    local target = box.byNode[a.to.id]
                    woken[a.to.id] = true
                    local from = a.from
                    local function fill()
                        if a.from ~= from then return end   -- arrow was reused meanwhile
                        A.Fill(a, Talents.ArrowState(a.from), function()
                            if a.from then A.Paint(a, Talents.ArrowState(a.from)) end
                            if target and target.node and open(target.node) then Talents.Wake(target) end
                        end)
                    end
                    A.Paint(a, "off")
                    local wait = closing[from.id]
                    if wait then wait[#wait + 1] = fill else fill() end
                elseif was and was.full and not full then
                    A.Drain(a, was.staged and "staged" or "lit")
                end
            end
        end
    end
    -- Newly unlocked talents wake left to right.
    for _, box in ipairs(page.trees) do
        if box:IsShown() then
            for _, b in ipairs(box.tiles) do
                local node = b.node
                local was = node and seen.nodes[node.id]
                if was and not was.open and open(node) and not woken[node.id] then
                    Talents.Wake(b, node.col * Talents.WAKE_STEP)
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------
-- Talent set tabs (Primary / Secondary)
-- ---------------------------------------------------------------------

local function makeSet(page, i)
    local b = DUI.Widgets.Tab(page, "", { justify = "LEFT", inset = 12 })
    b.dot = tex(b, "ARTWORK")
    b.dot:SetSize(5, 5)
    b.dot:SetPoint("LEFT", b, "LEFT", 2, 0)
    rgb(b.dot, Talents.STAGED)
    b.group = i
    b:SetScript("OnClick", function(self) Talents.ShowSet(self.group) end)
    b:HookScript("OnEnter", function(self)
        local W = DUI.Widgets
        if self.off then
            W.Tooltip(self, self.text:GetText(), TALENT_SPEC_LOCKED or L["Learn Dual Talent Specialization to use a second set of talents."])
        elseif self.group == ns.TalentData.ActiveGroup() then
            W.Tooltip(self, self.text:GetText(), L["The talents you're using now."])
        else
            W.Tooltip(self, self.text:GetText(), L["Not in use: look, or switch to it with Activate."])
        end
    end)
    b:HookScript("OnLeave", function() DUI.Widgets.HideTooltip() end)
    return b
end

local function paintSets(page)
    local TD = ns.TalentData
    local active, count = TD.ActiveGroup(), TD.NumGroups()
    local shown = Talents.group or active
    local names = { DUAL_SPEC_PRIMARY or L["Primary"], DUAL_SPEC_SECONDARY or L["Secondary"] }
    local x = Talents.EDGE - 2
    for i, b in ipairs(page.sets) do
        b.SetOff(i > count)
        b.text:SetText(names[i])
        b.FitWidth(2)
        b:ClearAllPoints()
        b:SetPoint("LEFT", page, "TOPLEFT", x, -20)
        x = x + b:GetWidth() + 10
        b.dot:SetShown(count > 1 and i == active)
        b.Pick(i == shown, true)
    end
end

-- View a set; nil means the active one.
function Talents.ShowSet(group)
    if group == ns.TalentData.ActiveGroup() then group = nil end
    if Talents.group == group then return end
    Talents.group = group
    if Talents.page then Talents.page.shownBefore = nil; Talents.Fill(Talents.page) end
end

-- ---------------------------------------------------------------------
-- Footer buttons: Apply and Undo, or Activate
-- ---------------------------------------------------------------------

function Talents.Undo()
    if ns.Spend.Undo() then sound("refund"); Talents.Soon() end
end

function Talents.Activate()
    local shown = Talents.group or ns.TalentData.ActiveGroup()
    if ns.Spend.Activate(shown) and Talents.page then Talents.Buttons(Talents.page) end
end

function Talents.Buttons(page)
    local Spend, TD = ns.Spend, ns.TalentData
    local bar = page.actions
    local shown = Talents.group or TD.ActiveGroup()
    if shown ~= TD.ActiveGroup() then
        local busy = Spend.activating == shown or InCombatLockdown()
        bar:Set({ { text = TALENT_SPEC_ACTIVATE or L["Activate"], primary = true, off = busy,
            onClick = function() if Spend.Activate(shown) then Talents.Buttons(page) end end } })
        bar.why = busy and InCombatLockdown() and (ERR_NOT_IN_COMBAT or L["Not in combat."]) or nil
        Talents.FitFoot(page)
        return
    end
    local ok, reason = Spend.CanApply()
    local changes = Spend.HasChanges()
    bar:Set({
        { text = TALENT_FRAME_APPLY_BUTTON_TEXT or L["Apply"], primary = true, off = not ok,
            onClick = function() Talents.Apply() end },
        { text = L["Undo"], off = not changes, onClick = Talents.Undo },
    })
    bar.why = (not ok and changes) and reason or nil
    Talents.FitFoot(page)
end

-- Size the button strip to its buttons, since long translated labels
-- ("Appliquer changements") overlapped Undo in a fixed-width strip. The
-- per-tree split drops tree names when it would run into the buttons.
Talents.FOOT_GAP = 8   -- matches the footer gap in Parts.lua
function Talents.FitFoot(page)
    local foot, bar = page.foot, page.actions
    if not (foot and bar) then return end
    local w, n = 0, 0
    for _, b in ipairs(bar.buttons) do
        if b:IsShown() then w, n = w + (b:GetWidth() or 0), n + 1 end
    end
    w = w + Talents.FOOT_GAP * math.max(n - 1, 0)
    bar.frame:SetWidth(math.max(w, 1))
    if not foot.long then return end
    local room = (foot:GetWidth() or 0) + 8 - w - 16
    local used = (foot.left:GetStringWidth() or 0) + 6 + (foot.label:GetStringWidth() or 0) + 14
    foot.split:SetText(foot.long)
    if used + (foot.split:GetStringWidth() or 0) > room then foot.split:SetText(foot.short) end
end

function Talents.Apply()
    local staged = {}
    for _, node in pairs(Talents.data and Talents.data.byID or {}) do
        if node.staged then staged[#staged + 1] = node.id end
    end
    if ns.Spend.Apply(staged) and Talents.page then Talents.Buttons(Talents.page) end   -- disable while the commit is pending
end

-- sent is the list of node ids that were staged, or nil if the commit failed.
function Talents.Applied(sent)
    local page = Talents.page
    if not page then return end
    local shown = page:IsVisible()
    Talents.wave = nil
    if sent and shown then
        Talents.wave = {}
        for _, id in ipairs(sent) do Talents.wave[id] = true end
    end
    if shown then Talents.Fill(page) end
    if Talents.wave then Talents.Wave(page, sent) end
end

-- ---------------------------------------------------------------------
-- Page
-- ---------------------------------------------------------------------

function Talents.Build(page)
    Talents.page = page
    ns.Spend.Init()
    local Parts = Win.Parts
    local box = DUI.Widgets.Input(page, { height = 24, search = true, hint = SEARCH or L["Search"],
        onChange = function(t) Talents.Search(t) end })
    box:SetWidth(150)
    box:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Talents.EDGE, -8)
    page.search = box
    page.sets = { makeSet(page, 1), makeSet(page, 2) }
    ns.Builds.Build(page)
    page.trees = {}
    -- Footer: points left and the per-tree split on the left, Apply and
    -- Undo on the right in their own strip.
    local foot = CreateFrame("Frame", nil, page)
    foot:SetSize(600, 28)
    foot:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", Talents.EDGE + 4, 12)
    foot.line = tex(foot, "ARTWORK")
    foot.line:SetHeight(1)
    foot.line:SetPoint("TOPLEFT", foot, "TOPLEFT", -4, 10)
    foot.line:SetPoint("TOPRIGHT", foot, "TOPRIGHT", 4, 10)
    foot.line:SetVertexColor(1, 1, 1, 0.06)
    foot.left = Style.Text(foot, 22, "LEFT")
    foot.left:SetPoint("LEFT", foot, "LEFT", 0, 0)
    foot.label = Style.Text(foot, Style.SIZE.small, "LEFT")
    foot.label:SetPoint("BOTTOMLEFT", foot.left, "BOTTOMRIGHT", 6, 3)
    Style.InkText(foot.label, "LABEL")
    foot.split = Style.Text(foot, Style.SIZE.small, "LEFT")
    foot.split:SetPoint("BOTTOMLEFT", foot.label, "BOTTOMRIGHT", 14, 0)
    Style.InkText(foot.split, "LABEL")   -- separators; names and numbers set their own colors
    page.foot = foot
    local bar = Parts.Footer(page, { edge = Talents.EDGE })
    bar.frame:ClearAllPoints()
    bar.frame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -Talents.EDGE, 12)
    bar.frame:SetSize(228, 28)   -- width is set by Talents.FitFoot
    bar.frame.line:Hide()
    page.actions = bar
    Talents.Buttons(page)
    -- A disabled Apply explains why, using the game's error text.
    for _, b in ipairs(bar.buttons) do
        b:HookScript("OnEnter", function(self)
            if self.spec and self.spec.off and bar.why then DUI.Widgets.Tooltip(self, self.text:GetText(), bar.why) end
        end)
        b:HookScript("OnLeave", function() DUI.Widgets.HideTooltip() end)
    end
    page.note = Style.Text(page, Style.SIZE.body, "CENTER")
    page.note:SetPoint("CENTER", page, "CENTER", 0, 0)
    Style.InkText(page.note, "LABEL")
    page.note:Hide()
    page:HookScript("OnHide", function(self) self.shownBefore = nil end)
    for _, e in ipairs(Talents.EVENTS) do
        DUI.RegisterEvent(e, function() Talents.Soon() end)
    end
end

-- Talent events arrive in bursts, so refill once on the next frame, and
-- only while visible.
function Talents.Soon()
    local page = Talents.page
    if not (page and page:IsVisible()) or Talents.pending then return end
    Talents.pending = true
    C_Timer.After(0, function()
        Talents.pending = nil
        if page:IsVisible() then Talents.Fill(page) end
    end)
end

-- Largest tile-to-tile pitch that fits every tree in w x h.
local function pitchFor(data, w, h)
    local cols, rows = 4, 7
    for _, t in ipairs(data.trees) do
        if t.cols > cols then cols = t.cols end
        if t.rows > rows then rows = t.rows end
    end
    local byW = (w - 2 * Talents.PAD) / (cols - 1 + Talents.TILE)
    local byH = (h - Talents.HEAD - Talents.PAD) / (rows - 1 + Talents.TILE)
    return math.floor(math.min(byW, byH, Talents.MAX_PITCH)), cols
end

-- Trees usually have spare width, so spread columns a bit wider than rows
-- without exceeding the tree's width.
local function pitchAcross(pitch, size, cols, w)
    local fit = (w - 2 * Talents.PAD - size) / math.max(cols - 1, 1)
    return math.max(pitch, math.floor(math.min(pitch * Talents.WIDE, fit)))
end

-- Row pitch, tile size and column pitch for one tree's area of w x h.
function Talents.Fit(data, w, h)
    local pitch, cols = pitchFor(data, w, h)
    local size = math.floor(pitch * Talents.TILE)
    return pitch, size, pitchAcross(pitch, size, cols, w)
end

function Talents.Fill(page)
    local TD = ns.TalentData
    -- Reset if the viewed set no longer exists or became the active one.
    if Talents.group and (Talents.group > TD.NumGroups() or Talents.group == TD.ActiveGroup()) then Talents.group = nil end
    paintSets(page)
    local configID = TD.ConfigID(Talents.group)
    local data = configID and TD.Read(configID) or nil
    Talents.data = data
    local foot = page.foot
    Talents.Buttons(page)
    if not data or #data.trees == 0 then
        for _, box in ipairs(page.trees) do box:Hide() end
        foot:Hide()
        page.search:Hide()
        page.builds:Hide()
        page.note:SetText(Talents.group and L["This set hasn't been used yet. Activate it to spend its points."]
            or L["Talents aren't available yet."])
        page.note:Show()
        page.actions.frame:SetShown(Talents.group ~= nil)
        page.seen = nil
        return
    end
    page.note:Hide()
    foot:Show()
    page.search:Show()
    page.builds:Show()
    page.actions.frame:Show()
    Talents.Layout(page, data, ns.Window.PageSize("talents"))
    -- Count to the new value, with a bump when points go up (level up, reset).
    local was = foot.leftShown
    foot.leftShown = data.left
    if Motion.CountTo(foot.left, data.left, function(n) return n and tostring(n) or "" end) and data.left > was then
        Motion.Bump(foot.left, 1.15, Motion.NORMAL)
    end
    Style.InkText(foot.left, (data.left or 0) > 0 and "pop" or "OFF")
    foot.label:SetText(L["points left"])
    local parts, short, token = {}, {}, classToken()
    local INK = Style.INK
    for i, t in ipairs(data.trees) do
        local r, g, b = Talents.TreeColor(i, token)
        local nr, ng, nb = r * 0.85 + INK.LABEL[1] * 0.15, g * 0.85 + INK.LABEL[2] * 0.15, b * 0.85 + INK.LABEL[3] * 0.15
        local num = t.spent > 0 and { Style.Pop() } or INK.OFF   -- accent read at paint time
        parts[#parts + 1] = string.format("%s%s|r %s%d|r", hex(nr, ng, nb), t.name, hex(num[1], num[2], num[3]), t.spent)
        short[#short + 1] = string.format("%s%d|r", hex(nr, ng, nb), t.spent)   -- tree color identifies the tree
    end
    foot.long, foot.short = table.concat(parts, "  ·  "), table.concat(short, "  ·  ")
    Talents.FitFoot(page)
    Talents.Search(page.search:GetText() or "")
    Talents.Animate(page, data)
    Talents.Remember(page, data)
    page.shownBefore = true
end

-- Lay out the trees for a window size: equal shares of the width, with the
-- pitch fitted to the space.
function Talents.Layout(page, data, ww, wh)
    local pw, ph = ww, wh - Win.HEADER - 1
    local n = #data.trees
    local w = math.floor((pw - 2 * Talents.EDGE - (n - 1) * Talents.GAP) / n)
    local h = ph - Talents.TOP - Talents.FOOT
    local pitch, size, px = Talents.Fit(data, w, h)
    for i, t in ipairs(data.trees) do
        local box = page.trees[i]
        if not box then
            box = Talents.MakeTree(page)
            page.trees[i] = box
        end
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", page, "TOPLEFT", Talents.EDGE + (i - 1) * (w + Talents.GAP), -Talents.TOP)
        box:SetSize(w, h)
        box:Show()
        box.index = i
        Talents.FillTree(box, t, pitch, size, data, px)
    end
    for i = n + 1, #page.trees do page.trees[i]:Hide() end
    page.foot:SetWidth(pw - 2 * Talents.EDGE - 8)
    Talents.FitFoot(page)
end

-- Highlight talents whose name contains the text and dim the rest.
function Talents.Search(text)
    local page = Talents.page
    if not page then return end
    local want = type(text) == "string" and text ~= "" and string.lower(text) or nil
    Talents.filter = want
    for _, box in ipairs(page.trees) do
        for _, b in ipairs(box.tiles) do
            if b.node then
                local hit = want and string.find(string.lower(b.node.name), want, 1, true) ~= nil
                b.hit = hit or nil
                b.dim = (want and not hit) or nil
                Talents.PaintTile(b)
            end
        end
    end
end

-- Pieces in the order they animate in when the page opens.
function Talents.Pieces(page)
    local out = { page.sets[1], page.sets[2], page.builds, page.search }
    for _, box in ipairs(page.trees) do if box:IsShown() then out[#out + 1] = box end end
    out[#out + 1] = page.foot
    out[#out + 1] = page.actions.frame
    return out
end

-- ---------------------------------------------------------------------
-- A controller: the game's talent buttons (SetUpTalentsGamepad in
-- Blizzard_PlayerSpellsFrame.lua). A adds a point, Y takes one back and held
-- undoes every change, X held applies them, LB and RB step the talent sets.
-- ---------------------------------------------------------------------

local function padNode(b)
    if type(b) ~= "table" or type(b.node) ~= "table" then return nil end
    if b.box and b.box.readOnly then return nil end
    return b.node
end

local function viewingActive() return (Talents.group or ns.TalentData.ActiveGroup()) == ns.TalentData.ActiveGroup() end

function Talents.PadSelect(b)
    if padNode(b) and viewingActive() then return GAMEPAD_TALENT_ADD_POINT or L["Add point"] end
    return nil
end

-- The talent sets, when there's a second one to switch to.
function Talents.PadTabs()
    local page = Talents.page
    local out, at = {}, nil
    if not (page and page.sets) or ns.TalentData.NumGroups() < 2 then return out end
    local shown = Talents.group or ns.TalentData.ActiveGroup()
    for i, b in ipairs(page.sets) do
        if b:IsShown() and not b.off then
            out[#out + 1] = b
            if i == shown then at = #out end
        end
    end
    return out, at
end

function Talents.PadKeys(on)
    local Spend = function() return ns.Spend end
    return {
        { key = "Y", when = function(b) return on() and viewingActive() and (padNode(b) ~= nil or Spend().HasChanges()) end,
          label = function(b)
              local node = padNode(b)
              return node and node.rank > 0 and (GAMEPAD_TALENT_REMOVE_POINT or L["Remove point"]) or nil
          end,
          run = function(b)
              local node = padNode(b)
              if node and node.rank > 0 then Talents.Click(b, "RightButton") end
          end,
          hold = { label = L["Undo"], when = function() return Spend().HasChanges() end, run = Talents.Undo } },
        { key = "X", label = TALENT_SPEC_ACTIVATE or L["Activate"],
          when = function() return on() and not viewingActive() and not InCombatLockdown() end,
          run = Talents.Activate },
        { key = "X", when = function() return on() and viewingActive() and Spend().HasChanges() end,
          hold = { label = TALENT_FRAME_APPLY_BUTTON_TEXT or L["Apply"],
                   when = function() return (Spend().CanApply()) end, run = Talents.Apply } },
    }
end
