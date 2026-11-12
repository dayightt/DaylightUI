-- Private boss debuffs (auras addon code can't read) on party and raid buttons.
-- Up to two big icons in the middle of the health bar, with a cooldown swipe.
-- The client draws them into slots from DUI.PrivateAuras; this file only picks
-- the unit and size. Slot anchors follow the button's unit, size and shown
-- state, and can only change out of combat.

local _, ns = ...
local DUI = DaylightUI

local GPA = {}
ns.GroupPrivate = GPA

GPA.MAX = 2       -- icons per tile
GPA.GAP = 2       -- between the two
GPA.SHARE = 0.8   -- share of the health bar's height
GPA.MIN, GPA.LIMIT = 10, 40

-- Sample tiles that carry a stand-in, for test mode and the Party page preview.
-- [group key] = { [sample index] = icons }. Most members carry none.
GPA.SAMPLE_TILES = { raid = { [5] = 1, [22] = 2 }, party = { [3] = 1 } }

local function slotFrame(b)
    local f = CreateFrame("Frame", nil, b)
    f:SetAllPoints(b.health or b)
    -- Above the aura groups, since crowd control also sits in the middle.
    f:SetFrameLevel(b:GetFrameLevel() + 12)
    f:EnableMouse(false)
    return f
end

-- Set up a button the header just made. The header hides buttons it doesn't
-- need, so the anchors are kept up as it shows and hides.
function GPA.Create(b)
    if b.privateSet or not DUI.PrivateAuras.Available() then return end
    b.privateFrame = slotFrame(b)
    b.privateSet = DUI.PrivateAuras.New(b.privateFrame, GPA.MAX)
    b:HookScript("OnShow", GPA.Update)
    b:HookScript("OnHide", GPA.Update)
end

-- Icon size for a tile cfg: a share of the health bar's height, capped so
-- both icons fit across the tile.
function GPA.Size(cfg)
    local h = tonumber(cfg.height) or 28
    -- Ribbon's power is a line under the frame, not inside it.
    if ns.UF.ShowsPower(cfg) and ns.UF.StyleOf(cfg) ~= "ribbon" then h = h - (tonumber(cfg.powerHeight) or 0) end
    local s = math.floor(h * GPA.SHARE + 0.5)
    local w = tonumber(cfg.width) or 72
    s = math.min(s, math.floor((w - 4 - GPA.GAP) / GPA.MAX))
    return math.max(GPA.MIN, math.min(GPA.LIMIT, s))
end

-- The first goes in the middle and the second beside it, so the usual single
-- boss debuff sits centered.
local function place(set, size)
    local a, b = set.slots[1], set.slots[2]
    a:ClearAllPoints()
    a:SetPoint("CENTER", a:GetParent(), "CENTER", 0, 0)
    if b then
        b:ClearAllPoints()
        b:SetPoint("LEFT", a, "RIGHT", GPA.GAP, 0)
    end
    for _, s in ipairs(set.slots) do s:SetSize(size, size) end
end

-- The unit whose private auras the button should carry now, or nil.
function GPA.Unit(b)
    local cfg = b.privateCfg
    if not cfg or cfg.privateAuras == false then return nil end
    if not b:IsShown() or type(b.unitToken) ~= "string" then return nil end
    return b.unitToken
end

-- Unit, shown state or size changed. The anchors follow after combat.
function GPA.Update(b)
    if not b.privateSet or not b.privateSize then return end
    DUI.PrivateAuras.Want(b.privateSet, GPA.Unit(b), b.privateSize)
end

-- Called from the button's layout (Group:LayoutAuras).
function GPA.Layout(b, cfg)
    local set = b.privateSet
    if not set then return end
    b.privateCfg = cfg
    b.privateSize = GPA.Size(cfg)
    place(set, b.privateSize)
    GPA.Update(b)
end

-- Sample tile i (never a real anchor). Shows a stand-in where a boss debuff lands.
function GPA.ShowSample(b, i, cfg)
    local n = 0
    local tiles = b.group and GPA.SAMPLE_TILES[b.group.key]
    -- The options page's one full tile keeps its middle for crowd control.
    if tiles and not b.fullSample and cfg and cfg.privateAuras ~= false then n = tiles[i] or 0 end
    if n == 0 and not b.privateSet then return end
    if not b.privateSet then
        b.privateFrame = slotFrame(b)
        b.privateSet = DUI.PrivateAuras.New(b.privateFrame, GPA.MAX)
    end
    place(b.privateSet, GPA.Size(cfg))
    DUI.PrivateAuras.ShowSample(b.privateSet, n)
end

function GPA.HideSample(b)
    if b.privateSet then DUI.PrivateAuras.ShowSample(b.privateSet, 0) end
end
