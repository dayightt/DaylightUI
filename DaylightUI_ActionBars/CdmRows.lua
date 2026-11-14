-- The player's Cooldown Manager layout on screen: one layout frame per talent set
-- (at screen center), one of our frames per piece inside it (placed from
-- CdmData.Layout), and the claiming of the game's items into them. The game keeps
-- making and laying out its items; after each of its passes we move the ones the
-- player placed into their slot. We never reparent, show, hide or scale the game's
-- frames, and all bookkeeping is in weak tables.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local CD = ns.Cooldowns
local Data = ns.CdmData
local Fx = ns.CdmEffects

local Rows = {}
ns.CdmRows = Rows

local KINDS = {
    EssentialCooldownViewer = "icon", UtilityCooldownViewer = "icon",
    BuffIconCooldownViewer = "icon", BuffBarCooldownViewer = "bar",
}
-- Viewers that hold auras (the others hold cooldowns). Decides what we draw when a
-- spell sits in a block of the other shape.
local AURA_VIEWERS = { BuffIconCooldownViewer = true, BuffBarCooldownViewer = true }


local weak = { __mode = "k" }
local frames = {}                          -- [g] = { layout = frame, pieces = { [id] = frame } }
local claimed = setmetatable({}, weak)     -- item -> piece id
local sizes = setmetatable({}, weak)       -- bar item -> { w, h }
local faded = setmetatable({}, weak)       -- item -> true
local ours = setmetatable({}, weak)        -- our own bar (CdmBars) -> piece id, this pass
local blocks = {}                          -- [id] = the piece's block of one (Data.PieceBlock), this pass
local drawn = {}                           -- [cooldownID] = what shows it, this pass (Rows.DrawnBy)
local hooked = setmetatable({}, weak)
local pending, ready = false, false
local lastItems, lastExtra, lastOn = {}, {}, false   -- the last pass's items, for Rows.Away

local function num(v)
    if type(v) ~= "number" or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

function Rows.Owns(item) return claimed[item] ~= nil or ours[item] ~= nil end

-- The block of one a held item (or one of our bars) sits in, or nil.
function Rows.BlockOf(item)
    local id = claimed[item] or ours[item]
    return id ~= nil and blocks[id] or nil
end
function Rows.Size(item)
    local s = sizes[item]
    if s then return s[1], s[2] end
end
-- What shows placed spell id now: "game", "cooldown bar", "aura bar", "aura and
-- cooldown bar", "aura icon", "own icon", "stand-in", or nil (nothing).
function Rows.DrawnBy(id) return drawn[id] end
function Rows.Bars() return ns.CdmBars end

-- Every item the game's viewers hold right now that has an id.
function Rows.EachItem(fn)
    for _, name in ipairs(CD.VIEWERS) do
        local v = _G[name]
        if type(v) == "table" then
            local kind = KINDS[name]
            CD.EachItem(v, function(item)
                local id = num(item.cooldownID)
                if id then fn(item, id, kind) end
            end)
        end
    end
end

-- Makes the layout frames once: one per talent set, a point at screen center that
-- the pieces are placed from.
function Rows.Init()
    if ready then return end
    ready = true
    for g = 1, Data.SETS do
        local f = CreateFrame("Frame", "DaylightUICdmLayout" .. g, UIParent)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        f:SetSize(1, 1)
        f:Hide()
        frames[g] = { layout = f, pieces = {} }
    end
end

-- The fade engine's area ("ActionBars.cdm"): the shown pieces for mouseover, and the
-- layout frame that carries them. Alpha only goes on the layout frame (its pieces
-- follow) and on the game's viewers. Their items belong to the game and are never
-- ours to hide, so it's alpha only, multiplied by the viewer's own Edit Mode
-- opacity (which the game sets with SetAlpha).
local fadeList = {}
function Rows.FadeFrames()
    for i = #fadeList, 1, -1 do fadeList[i] = nil end
    local fr = ready and frames[Data.CurrentIndex()]
    if not (fr and fr.layout:IsShown()) then return fadeList end
    fadeList[1] = fr.layout
    for _, f in pairs(fr.pieces) do
        if f:IsShown() then fadeList[#fadeList + 1] = f end
    end
    return fadeList
end

local function viewerOpacity(v)
    local enum = Enum and Enum.EditModeCooldownViewerSetting
    if not (enum and enum.Opacity and type(v.GetSettingValue) == "function") then return 1 end
    local ok, o = pcall(v.GetSettingValue, v, enum.Opacity)
    if not ok or type(o) ~= "number" or (issecretvalue and issecretvalue(o)) then return 1 end
    return math.max(0, math.min(1, o / 100))
end

function Rows.PaintFade(f, a)
    local fr = ready and frames[Data.CurrentIndex()]
    if not (fr and f == fr.layout) then return end
    f:SetAlpha(a)
    for _, name in ipairs(CD.VIEWERS) do
        local v = _G[name]
        if type(v) == "table" and v.SetAlpha then v:SetAlpha(a * viewerOpacity(v)) end
    end
end

local function pieceFrame(g, id)
    local t = frames[g].pieces
    if not t[id] then
        t[id] = CreateFrame("Frame", "DaylightUICdmPiece" .. g .. "_" .. tostring(id), frames[g].layout)
        t[id]:SetSize(36, 36)
    end
    return t[id]
end

local function usable(item)
    return not (InCombatLockdown() and item.IsProtected and item:IsProtected())
end

-- A shield placed as a bar that fills by the shield left (CdmBars.IsShield). Only
-- our aura bar can do that, so the game's own bar for it steps aside.
local function byShield(set, id, kind)
    return kind == "bar" and ns.CdmBars ~= nil and ns.CdmBars.IsShield(id)
        and Fx.Get(set.pieces[id], "fillBy") ~= "time"
end

-- A shield placed as an icon showing its amount ("Show shield amount"). Only our aura
-- holder can do that (CdmAuras.SetAmount), so the game's buff icon steps aside too.
local function shieldIcon(set, id)
    return ns.CdmBars ~= nil and ns.CdmBars.IsShield(id)
        and set.pieces[id].shape ~= "bar" and Fx.Get(set.pieces[id], "shieldAmount") ~= false
end

local function release(item)
    Fx.Clear(item)
    DUI.SafeCall(CD.ClearIconText, item)
    if claimed[item] or faded[item] or sizes[item] then
        claimed[item], faded[item], sizes[item] = nil, nil, nil
        item:SetAlpha(1)
        item:EnableMouse(true)
        return true
    end
end

local function touch() Rows.Refresh() end

-- The game's layout pass hides every item and shows it again before putting it in
-- its grid (RefreshLayout releases the pool), so a held item's OnHide/OnShow is the
-- moment to claim it back. No hook on its SetPoint: hooks on the game's own methods
-- broke its calls before.
local function hook(item)
    if hooked[item] then return end
    hooked[item] = true
    if item.HookScript then
        item:HookScript("OnShow", touch)
        item:HookScript("OnHide", touch)
    end
end

-- A shown, held item that isn't anchored to its block, because the game laid it out
-- at a moment we didn't hear about (Cooldowns.lua checks every CD.SCAN). Hidden ones
-- are skipped; they're placed when they show.
function Rows.Drifted()
    local fr = ready and frames[Data.CurrentIndex()]
    if not fr then return false end
    for item, id in pairs(claimed) do
        if item:IsShown() then
            if item:GetNumPoints() == 0 then return true end
            local _, rel = item:GetPoint(1)
            if not (issecretvalue and issecretvalue(rel)) and rel ~= fr.pieces[id] then return true end
        end
    end
    return false
end

-- Fits the item to its piece's frame f (sized by the layout).
local function place(item, block, f, button)
    local r = f:GetEffectiveScale() / item:GetEffectiveScale()
    item:ClearAllPoints()
    local w, h = block.size * r, block.size * r
    if block.kind == "bar" then w = block.width * r end
    item:SetPoint("CENTER", f, "CENTER", 0, 0)
    item:SetSize(w, h)
    if block.kind == "bar" and not item.placeholder then
        sizes[item] = { w, h }
        ns.BuffBars.LayoutBar(item, w, h)
        -- Our own bars also fit their timer pieces (CdmBars).
        if item.fitBar then item.fitBar(item, w, h, block, button) end
    end
end

-- Moves a piece to its spot. One already showing that moves (its chain closing up,
-- or opening for a piece coming back) glides; one just shown snaps. Piece frames
-- are ours, so the items anchored to them follow, in fights too.
local function put(f, layout, x, y)
    if f.goalX == x and f.goalY == y and f.atX then return end
    f.goalX, f.goalY = x, y
    local fx, fy = x, y
    if f.atX and f:IsShown() and not (InCombatLockdown() and f:IsProtected()) then fx, fy = f.atX, f.atY end
    f.moveKey = f.moveKey or {}
    DUI.Motion.Tween(f.moveKey, 0, 1, (fx == x and fy == y) and 0 or DUI.Motion.NORMAL, function(p)
        f.atX, f.atY = fx + (x - fx) * p, fy + (y - fy) * p
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", layout, "CENTER", f.atX, f.atY)
    end)
end

-- One pass's scratch tables, wiped at its start. A pass runs on every aura shown or
-- hidden, so no fresh tables each time. items and extra come in two pairs: a pass
-- fills the one Rows.Away isn't reading and only hands it over once complete, so a
-- pass that breaks partway (under SafeCall) leaves the last complete layout to the
-- show rules.
local mine, elsewhere, elsewhereAura = {}, {}, {}
-- id -> the game's aura item for a spell we draw as "Cooldown and buff".
local auraItems = {}
local usedOwn, usedHolders, usedHolds, usedBars = {}, {}, {}, {}
local shown, downs, told = {}, {}, {}
-- id -> our aura holder whose buff is down and gave up its spot (slide over).
local closed = {}
-- id -> true when it closed because it's up and hidden (Buff up Hide).
local closedUp = {}
local pairA, pairB = { items = {}, extra = {} }, { items = {}, extra = {} }
local items, extra = pairA.items, pairA.extra
local function wipe(t) for k in pairs(t) do t[k] = nil end end

-- The pass now running (Rows.Update), read by claim() and drawOurs().
local passSet, passOn, passHide, passName, passKnown

-- The spell list, read once per pass (in combat Own.Known isn't cached).
local function knownNow()
    passKnown = passKnown or ns.CdmOwn.Known()
    return passKnown
end

-- One of the game's items (in viewer passName): held in its piece, hidden so ours
-- can draw it, or released.
local function claim(item)
    local id = num(item.cooldownID)
    if not id or not usable(item) then return end
    local set, name = passSet, passName
    local kind = KINDS[name]
    local block = passOn and blocks[id]
    -- The game's item shows the wrong thing for the spell's Track (CdmOwn.Track):
    -- a buff item tracked as its cooldown or both (Shield Block, Charge; it hides
    -- while the buff is down), or a cooldown item the player set to Cooldown or Buff
    -- only (Rend, Thunder Clap). Ours draws it below and the game's stays hidden.
    local cooldown = false
    local Own = ns.CdmOwn
    if block and Own then
        local p = set.pieces[id]
        if AURA_VIEWERS[name] then
            local t = Own.Track(id, p, knownNow())
            cooldown = t == "cooldown" or t == "both"
        else
            -- Left unset it stays the game's icon (Rend, Moonfire too: shown all
            -- the time, with its aura while up).
            local t = Own.Track(id, p, knownNow())
            local pick = Own.Picked(p)
            -- Also moved to ours: Hide (Buff up), since the game's icon can't say
            -- when it's showing the aura; any buff request for an aura the game's
            -- icon never shows (Bloodrage, one learned from a cast, or one picked
            -- before any is known); a buff sound, since only ours hears the aura
            -- land or end; and a buff's charges (Shield Block, Holy Shield;
            -- Own.Stacks).
            local follows = ns.CdmAuras ~= nil and ns.CdmAuras.Follows(id)
            cooldown = t ~= nil and (pick == "cooldown" or pick == "buff" or (pick == nil and t == "buff")
                or Fx.Get(p, "hideActive") == true or Fx.Get(p, "buffSound") ~= "none"
                or Fx.Get(p, "buffEndSound") ~= "none"
                or (t == "both" and (not follows or Own.Stacks(id))))
        end
    end
    if block and ns.CdmAuras and ns.CdmAuras.SelfDebuff(id) then
        -- The debuff lands on you (Arcane Blast's stack). The game's item never
        -- sees it, so it says nothing either way. Ours draws it from your debuffs
        -- and the game's stays hidden and ignored.
        release(item)
        faded[item] = true
        item:SetAlpha(0)
        item:EnableMouse(false)
    elseif cooldown then
        release(item)
        faded[item] = true
        item:SetAlpha(0)
        item:EnableMouse(false)
        -- The game's aura item, though hidden, still shows only while the aura is
        -- up, in a fight too. It's the one plain signal when the aura ends early.
        if AURA_VIEWERS[name] then
            hook(item)
            auraItems[id] = item
        end
    elseif block and (not Data.Native(block, kind) or byShield(set, id, kind)
        or (AURA_VIEWERS[name] and shieldIcon(set, id))) then
        -- Placed in the other shape (or a shield bar filled by the shield left,
        -- which the game's bar can't do): ours draws the spell and the game's item
        -- stays hidden. Its showing and hiding still tells whether the aura is up
        -- (a closing gap), so it's still listened to (hook).
        release(item)
        faded[item] = true
        item:SetAlpha(0)
        item:EnableMouse(false)
        hook(item)
        elsewhere[id], elsewhereAura[id] = item, AURA_VIEWERS[name] == true
    elseif block then
        faded[item] = nil
        claimed[item] = id
        item:SetAlpha(1)
        item:EnableMouse(true)
        hook(item)
        mine[id] = item
    else
        release(item)
        if passHide then
            faded[item] = true
            item:SetAlpha(0)
            item:EnableMouse(false)
        end
    end
end


-- drawOurs results that are aura holders themselves.
local HOLDS = { ["aura icon"] = true, ["aura bar"] = true, ["aura and cooldown bar"] = true }

-- A spell the game has no item of this shape for, drawn by us in piece frame f.
-- Bar: our cooldown bar or aura bar (CdmBars). Icon: our own icon, or for an aura the
-- game's aura display in a holder of ours (CdmAuras). track = a buff spell's pick
-- (CdmOwn.Track), "cooldown" or "both".
local function drawOurs(id, p, block, f, always, aura, track)
    local set, Own = passSet, ns.CdmOwn
    local item
    if block.kind == "bar" then
        local Bars = ns.CdmBars
        if not Bars then return nil end
        -- A cooldown the game shows by its aura while up (Rend): the aura's bar,
        -- over the cooldown when it has a real one (Thunder Clap), like the
        -- game's icon.
        local under = false
        if track == "both" then
            aura, under = true, true
        elseif not track and not aura and ns.CdmAuras and ns.CdmAuras.Follows(id) then
            aura = true
            under = Own ~= nil and Own.HasCooldown(Own.SpellOf(id))
        end
        -- A shield filled by the shield left: no cooldown under it (a full bar for
        -- ready read as a shield). An empty bar in its spot while it's down,
        -- unless Hide (Buff missing).
        local keep = always
        if aura and under and byShield(set, id, "bar") then
            under, keep = false, Fx.Get(p, "hideMissing") ~= true
        end
        item = aura and Bars.Aura(id, f, under, keep, block.width, block.size, block, p) or Bars.Cooldown(id, f)
        usedBars[item] = true
        ours[item] = id
        drawn[id] = under and "aura and cooldown bar" or aura and "aura bar" or "cooldown bar"
    elseif track == "both" then
        -- Our cooldown icon, with the buff's button over it while up.
        item = Own.Acquire(id, f)
        usedOwn[id] = true
        drawn[id] = "own icon"
        if ns.CdmAuras then
            local text = CD.TextLook(block)
            local holder = ns.CdmAuras.Acquire(id, item, nil, block.size, text)
            ns.CdmAuras.Over(holder, item, block.size, text)
            ns.CdmAuras.SetAmount(holder, shieldIcon(set, id), text)
            ns.CdmAuras.SetSwipe(holder, Fx.Get(p, "noDurationSwipe"), Fx.Get(p, "reverse"))
            usedHolders[id] = true
            drawn[id] = "aura and cooldown icon"
        end
    elseif aura then
        if not ns.CdmAuras then return nil end
        local text = CD.TextLook(block)
        item = ns.CdmAuras.Acquire(id, f, always, block.size, text)
        ns.CdmAuras.Resize(item, block.size, text)
        ns.CdmAuras.SetAmount(item, shieldIcon(set, id), text)
        ns.CdmAuras.SetSwipe(item, Fx.Get(p, "noDurationSwipe"), Fx.Get(p, "reverse"))
        usedHolders[id] = true
        extra[item] = true
        drawn[id] = "aura icon"
    else
        item = Own.Acquire(id, f)
        usedOwn[id] = true
        drawn[id] = "own icon"
    end
    return item
end

function Rows.Update()
    pending = false
    if not ready then return end
    -- A layout pass may have made fresh pool items, so apply our look first.
    CD.Scan()
    local g = Data.CurrentIndex()
    local set = Data.Get(g)
    local on = Data.Switch("on") and next(set.pieces) ~= nil and frames[g] ~= nil
    -- With the layout on, the game's own items stay hidden even when the set has no
    -- pieces yet (the game keeps adding newly learned spells).
    local hide = Data.Switch("on") and Data.Switch("hideUnplaced")

    for k in pairs(blocks) do blocks[k] = nil end
    if on then
        for id in pairs(set.pieces) do blocks[id] = Data.PieceBlock(set, id) end
    end

    -- Only this set's layout shows.
    for gg, fr in pairs(frames) do
        local show = on and gg == g
        fr.layout:SetShown(show)
        for id, f in pairs(fr.pieces) do
            if not (show and set.pieces[id]) then f:Hide() end
        end
    end

    -- Claim items by piece.
    wipe(mine); wipe(elsewhere); wipe(elsewhereAura); wipe(auraItems)
    for k in pairs(ours) do ours[k] = nil end
    for k in pairs(drawn) do drawn[k] = nil end
    passSet, passOn, passHide, passKnown = set, on, hide, nil
    for name in pairs(KINDS) do
        local v = _G[name]
        if type(v) == "table" then
            passName = name
            -- A viewer the game hides (Cooldown Manager off, viewer set to Hidden,
            -- or In combat while out of a fight) hides its items and stops updating
            -- them. They're released and ours draws their spells. When it shows
            -- again they're claimed back (hook).
            hook(v)
            if v:IsShown() then CD.EachItem(v, claim) else CD.EachItem(v, release) end
        end
    end

    -- What shows each piece, which pieces are up, then every piece's box from the
    -- tree (a hidden piece closes up) with the items placed into them.
    wipe(usedOwn); wipe(usedHolders); wipe(usedHolds); wipe(usedBars)
    local fill = lastItems == pairA.items and pairB or pairA
    items, extra = fill.items, fill.extra
    wipe(extra); wipe(shown); wipe(items)
    -- id -> true when its buff is down, false when up (nil: not a buff, or can't
    -- tell yet because CdmAuras.IsUp has no answer).
    wipe(downs); wipe(closed); wipe(closedUp)
    if on then
        local Own = ns.CdmOwn
        for id, p in pairs(set.pieces) do
            local block = blocks[id]
            local f = pieceFrame(g, id)
            local always = block.always == true   -- "Show when missing", per spell
            local item = mine[id]
            if item then drawn[id] = "game" end
            local k
            if Own and (not item or always) then k = Own.Entry(id, knownNow()) end
            local away = not item and elsewhere[id]
            local awayAura = elsewhereAura[id]
            if away then
                -- The game draws it in the other shape. An aura that's down (the
                -- game hid its item) closes up; "Show missing buffs" keeps it, empty.
                local up = away:IsShown()
                if awayAura then downs[id] = not up end
                if always or not block.collapse or not awayAura or up then
                    -- A cooldown set to Cooldown and buff by hand keeps the cooldown
                    -- under the aura bar even when we can't tell.
                    local both = not awayAura and Own and Own.Picked(p) == "both" and "both" or nil
                    item = drawOurs(id, p, block, f, always, awayAura, both)
                    if item and block.kind == "bar" and awayAura then
                        Fx.Flash(item, item.Bar, always and not up
                            and Fx.Get(p, "inactiveFlash") == true)
                    end
                end
            elseif not item and k then
                local track = Own.Track(id, p, knownNow())
                if track == "buff" then
                    item = drawOurs(id, p, block, f, always, true)
                elseif track then
                    item = drawOurs(id, p, block, f, always, false, track)
                else
                    item = drawOurs(id, p, block, f, always, k.aura)
                end
            elseif item and Own then
                -- The game's buff item (a bar, or an aura family icon), shown while
                -- the buff is up.
                local e = k or Own.Entry(id, knownNow())
                if block.kind == "bar" or (e and e.aura) then downs[id] = not item:IsShown() end
            end
            -- Our aura holder (icon or bar): the missing glow and Hide (Buff up) ask
            -- CdmAuras.IsUp, unless the game's item already answered.
            local holder = item and ns.CdmAuras and (HOLDS[drawn[id]] and item
                or drawn[id] == "aura and cooldown icon" and ns.CdmAuras.Frame(id))
            local closedNow = false
            if holder then
                local hide = Fx.Get(p, "hideActive") == true
                local sound = Fx.Get(p, "buffSound") ~= "none"
                -- An end sound needs the ups as well as the downs.
                local ends = Fx.Get(p, "buffEndSound") ~= "none"
                -- "Slide over when a buff drops": a buff of ours that's down gives
                -- up its spot like the game's own (which hide). Not a shield bar,
                -- which stays as an empty bar, nor a bar with its cooldown under it.
                local canSlide = block.collapse and HOLDS[drawn[id]] == true
                    and drawn[id] ~= "aura and cooldown bar"
                local slides = canSlide and not always
                    and not (byShield(set, id, block.kind) and Fx.Get(p, "hideMissing") ~= true)
                -- Hidden while up (Buff up Hide) has nothing to keep a spot for,
                -- whatever Keep its spot says, since that's about while it's missing.
                -- Otherwise a missing buff set to Show stayed off the group's middle.
                local hideSlides = canSlide and hide
                local glowUp = Fx.UpGlows(p)
                -- A cooldown with its buff over it, faded or hidden on cooldown or
                -- while ready: while the buff is up it shows (CdmEffects), so it
                -- needs the ups too.
                local cdFx = drawn[id] ~= nil and string.find(drawn[id], "aura and cooldown", 1, true) ~= nil
                    and (Fx.Get(p, "onCd") ~= "show" or Fx.Get(p, "onReady") ~= "show"
                        or Fx.Get(p, "onUnusable") ~= "show" or Fx.Get(p, "onShort") ~= "show")
                holder.wantsUp = (hide or sound or ends or slides or glowUp or cdFx or Fx.Get(p, "missingGlow") == true) or nil
                holder.soundPiece, holder.soundItem = sound and p or nil, sound and item or nil
                if holder.wantsUp then
                    local seen = auraItems[id] or (awayAura and away)
                    local up = seen and ns.CdmAuras.Told(holder, seen:IsShown()) or ns.CdmAuras.IsUp(holder)
                    if downs[id] == nil and (up == false or (up == true and (hide or sound or ends or glowUp or cdFx))) then downs[id] = not up end
                    -- Only a known "down"; one we can't tell keeps its spot.
                    closedNow = (slides and up == false) or (hideSlides and up == true)
                    if closedNow and up == true then closedUp[id] = true end
                end
                ns.CdmAuras.SetHideUp(holder, hide)
            end
            if item and drawn[id] == "game" and always and k and (k.aura or block.kind == "bar") and not item:IsShown() then
                -- Hidden by the game, but "Show missing buffs" is on: use a stand-in.
                item = Own.Placeholder(id, f, block.kind, Fx.Get(p, "hideActive") == true)
                usedHolds[id .. block.kind] = true
                extra[item] = true
                drawn[id] = "stand-in"
                downs[id] = true
            end
            -- A cooldown hidden by On cooldown or When ready Hide gives up its spot
            -- too with Slide over (Grow from Middle recenters). So does Buff up Hide
            -- on the game's buff item or our cooldown icon under a buff, whatever
            -- Keep its spot says (Fx.GoneUp).
            if item and not closedNow and block.collapse and Fx.Gone(item)
                and (not always or Fx.GoneUp(item)) then
                closedNow = true
                if Fx.GoneUp(item) then closedUp[id] = true end
            end
            if closedNow then
                closed[id] = item
            elseif item and (always or not block.collapse or item:IsShown()) then
                shown[id] = true
                items[id] = item
            end
        end
        local layout = frames[g].layout
        local boxes = Data.Layout(set, shown)
        -- A closed-up buff of ours stays shown where it gave up its spot, with
        -- nothing visible while down. Its holder keeps listening, and the client's
        -- button coming up there (CdmAuras.Shown) reopens the spot.
        for id, item in pairs(closed) do
            local b, f = boxes[id], pieceFrame(g, id)
            -- Its closed box has no size, and its corner is where its parent's edge
            -- is. Above or left of the parent, a full-size frame there would cover
            -- the parent, so a buff landing in a fight came up on top of it. It waits
            -- just past that edge instead, where it comes up anyway.
            local w, h = Data.Dims(set, id)
            local side = set.pieces[id] and set.pieces[id].side
            local x, y = b.x, b.y
            if side == "up" then y = y + h elseif side == "left" then x = x - w end
            put(f, layout, x, y)
            f:SetSize(w, h)
            f:Show()
            place(item, blocks[id], f, set.pieces[id])
        end
        for id, item in pairs(items) do
            local b, f = boxes[id], pieceFrame(g, id)
            put(f, layout, b.x, b.y)
            f:SetSize(b.w, b.h)
            f:Show()
            place(item, blocks[id], f, set.pieces[id])
        end
        for id in pairs(set.pieces) do
            if not shown[id] and not closed[id] then pieceFrame(g, id):Hide() end
        end
    end
    if ns.CdmOwn then ns.CdmOwn.ReleaseExcept(usedOwn, usedHolds) end
    if ns.CdmAuras then ns.CdmAuras.ReleaseExcept(usedHolders) end
    if ns.CdmBars then ns.CdmBars.ReleaseExcept(usedBars) end

    -- Each held item's own effects, once it's in place.
    for id, item in pairs(mine) do
        local kind = blocks[id].kind
        Fx.Apply(item, set.pieces[id], kind, nil, ns.CdmOwn.BuffOnly(id, set.pieces[id], knownNow()))
        -- A bar takes its chain's look (color, icon, text, time); an icon its text.
        if kind == "bar" then DUI.SafeCall(CD.StyleText, item) else DUI.SafeCall(CD.StyleIconText, item, blocks[id]) end
    end
    -- Our own icons and bars (CdmOwn, CdmBars) take the same options: On cooldown,
    -- While ready, the glows. Not the aura holders or stand-ins.
    local function applyOwn(id, item)
        if mine[id] ~= item and not extra[item] then
            Fx.Apply(item, set.pieces[id], blocks[id].kind, true, ns.CdmOwn.BuffOnly(id, set.pieces[id], knownNow()))
            if blocks[id].kind == "icon" then DUI.SafeCall(CD.StyleIconText, item, blocks[id]) end
        end
    end
    for id, item in pairs(items) do applyOwn(id, item) end
    -- One closed up by its Hide keeps listening for its cooldown. One closed while
    -- its buff is up keeps its Hide's alpha.
    for id, item in pairs(closed) do
        if Fx.Gone(item) or closedUp[id] then applyOwn(id, item) end
    end
    -- Our own bars too (CdmBars: Rend, spells the game draws as icons). Their fill
    -- and background colors come from the same pass.
    for item, id in pairs(ours) do
        if (items[id] == item or closed[id] == item) and blocks[id].kind == "bar" then
            item.button = set.pieces[id]
            DUI.SafeCall(CD.StyleText, item)
        end
    end

    -- The keybind for each icon, whatever draws it.
    DUI.SafeCall(CD.PaintKeys, items, blocks)

    -- Buff up or down: the missing and up glows and "Hide while active".
    wipe(told)
    for id, item in pairs(items) do
        told[item] = true
        Fx.SetDown(item, set.pieces[id], downs[id])
    end
    -- Closed while up: pass along what this pass read (a drop reopens its spot).
    for id in pairs(closedUp) do
        told[closed[id]] = true
        Fx.SetDown(closed[id], set.pieces[id], downs[id] == true)
    end
    Fx.EndPass(told)
    -- Done here, not above, since a buff that's down may have closed up out of items.
    for id, isDown in pairs(downs) do Fx.BuffMoment(set.pieces[id], items[id], isDown) end

    -- The chain's show rules (out of combat, group, target, mounted, where).
    lastItems, lastExtra, lastOn = items, extra, on
    passSet, passKnown = nil, nil
    Rows.Away()

    -- Anything released waits for the game's own next layout pass. Never call the
    -- viewer's RefreshLayout from here: run from addon code it's tainted, fails
    -- partway on secret values and leaves the game's items emptied (no cooldownID,
    -- hidden) until a reload.
    -- The time on the game's bars, now that each spell has its bar.
    if ns.BuffBars then DUI.SafeCall(ns.BuffBars.SyncClocks) end
    if Rows.onUpdate then Rows.onUpdate() end
end

-- What the chains' show rules depend on right now (all plain in a fight).
function Rows.Now()
    local kind = select(2, IsInInstance())
    return { fight = InCombatLockdown(), group = IsInGroup(), target = UnitExists("target"),
        mounted = IsMounted(), instance = kind == "party" or kind == "raid" or kind == "pvp" or kind == "arena" }
end

-- A chain hidden by its show rules goes see-through. Alpha only, since the game's
-- items can't be moved in combat. With the editor open (Rows.editing) the whole
-- layout is hidden and the previews stand in. Cheap: it reuses the last pass's
-- items, so a target change or mounting doesn't trigger a layout.
function Rows.Away()
    if not lastOn then return end
    local now = Rows.Now()
    for id, item in pairs(lastItems) do
        local block = blocks[id]
        local gone = Rows.editing or (block ~= nil and Data.Away(block, now))
        Fx.SetAway(item, gone)
        if gone then
            item:SetAlpha(0)
            if claimed[item] then item:EnableMouse(false) end
        elseif lastExtra[item] then
            item:SetAlpha(1)
        end
    end
    -- A closed-up buff of ours follows its chain's rules too, since its button may
    -- come up before the next pass knows.
    for id, item in pairs(closed) do
        local block = blocks[id]
        local gone = Rows.editing or (block ~= nil and Data.Away(block, now))
        Fx.SetAway(item, gone)
        -- A cooldown closed up by its Hide has its alpha set by the effects. One
        -- hidden while up uses its Hide's alpha (Fx.SetDown).
        if gone or not (Fx.Gone(item) or closedUp[id]) then item:SetAlpha(gone and 0 or 1) end
    end
end

-- /dui cdm why: one line per placed spell saying what the last pass did with it.
-- Ends up in the player's saved settings file for bug reports.
local function word(v)
    if issecretvalue and issecretvalue(v) then return "secret" end
    if type(v) == "number" and v % 1 ~= 0 then return string.format("%.2f", v) end
    return tostring(v)
end
function Rows.Why()
    local out = {}
    local g = Data.CurrentIndex()
    local set = Data.Get(g)
    local fr = frames[g]
    local okS, secret = false, nil
    if C_Secrets and type(C_Secrets.ShouldAurasBeSecret) == "function" then okS, secret = pcall(C_Secrets.ShouldAurasBeSecret) end
    out[#out + 1] = string.format("set %s, on %s, hideUnplaced %s, editing %s, combat %s, pieces %s, auras readable %s (restricted %s, auras secret %s)",
        word(g), word(Data.Switch("on")), word(Data.Switch("hideUnplaced")), word(Rows.editing),
        word(InCombatLockdown()), word(fr ~= nil), word(ns.CdmAuras ~= nil and ns.CdmAuras.Readable()),
        word(DUI.Restricted()), okS and word(secret) or "unknown")
    local games = {}
    Rows.EachItem(function(item, id, kind)
        local t = games[id] or {}
        games[id] = t
        local rel
        if item:GetNumPoints() > 0 then rel = select(2, item:GetPoint(1)) end
        local at = (issecretvalue and issecretvalue(rel)) and "anchor secret"
            or ((fr and rel == fr.pieces[id]) and "in its piece" or "elsewhere")
        t[#t + 1] = string.format("%s shown %s alpha %s %s%s", kind, word(item:IsShown()), word(item:GetAlpha()),
            at, claimed[item] and " held" or (faded[item] and " faded" or ""))
    end)
    local now = Rows.Now()
    local ids = {}
    for id in pairs(set.pieces) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
    for _, id in ipairs(ids) do
        local p, block = set.pieces[id], blocks[id]
        local f = fr and fr.pieces[id]
        local item = lastItems[id]
        -- Our aura holder: what it knows about its buff (for slide over).
        local h = closed[id] or (HOLDS[drawn[id]] and item) or nil
        local buff = ""
        if h then
            buff = string.format(", buff up %s (asked %s, slid out %s, containers %s, heard %s)", word(h.up), word(h.wantsUp),
                word(closed[id] ~= nil), word(type(h.containers) == "table" and #h.containers),
                type(h.heard) == "table" and #h.heard > 0 and table.concat(h.heard, " / ") or "nothing")
            if type(h.containers) == "table" and ns.CdmAuras then
                local okW, line = pcall(ns.CdmAuras.Why, h)
                buff = buff .. ", " .. (okW and line or ("why failed: " .. tostring(line)))
            end
        end
        out[#out + 1] = string.format("%s: %s%s, track %s, slide %s, keep %s, drawn %s%s, away %s, piece %s, item %s alpha %s; game: %s",
            word(id), word(p.shape), p.parent and (" on " .. word(p.parent) .. " " .. word(p.side)) or "",
            word(p.track), word(block ~= nil and block.collapse), word(block ~= nil and block.always),
            word(drawn[id]), buff, word(block ~= nil and Data.Away(block, now)),
            f and (f:IsShown() and "shown" or "hidden") or "none",
            item and (item:IsShown() and "shown" or "hidden") or "none", item and word(item:GetAlpha()) or "-",
            games[id] and table.concat(games[id], " | ") or "none")
    end
    return out
end

-- While the on-screen editor (CdmEditor) is open, the live layout steps aside.
Rows.editing = false
function Rows.SetEditing(on)
    Rows.editing = on and true or false
    Rows.Refresh()
end

-- At most once per frame. The pass runs in this frame's OnUpdate, after events and
-- before drawing. The game lays its items out inside an event (a new target's full
-- aura update), and a pass on a timer ran after the frame was drawn, so a held icon
-- flickered to the game's spot and back. The timer stays as a fallback for calls
-- made after the OnUpdates.
local function runPending()
    Rows.now:Hide()
    if pending then DUI.SafeCall(Rows.Update) end
end

Rows.now = CreateFrame("Frame")
Rows.now:Hide()
Rows.now:SetScript("OnUpdate", runPending)

function Rows.Refresh()
    if pending then return end
    pending = true
    Rows.now:Show()
    C_Timer.After(0, runPending)
end

-- /dui cdm place <icon|bar>: every item the game currently draws in that shape that
-- isn't in the layout yet becomes one new chain (icons in a row, bars in a column)
-- below what's there.
function Rows.PlaceAll(kind)
    local set = Data.Current()
    local ids = {}
    for name, k in pairs(KINDS) do
        local v = _G[name]
        if k == kind and type(v) == "table" then
            CD.EachItem(v, function(item)
                local id = num(item.cooldownID)
                if id and not set.pieces[id] then ids[#ids + 1] = id end
            end)
        end
    end
    if #ids == 0 then return 0 end
    table.sort(ids)
    local low = Data.ORIGIN[2]
    for _, b in pairs(Data.Layout(set)) do
        if b.y - b.h - 12 < low then low = b.y - b.h - 12 end
    end
    Data.AddChain(set, ids, kind, Data.ORIGIN[1], low)
    Rows.Refresh()
    return #ids
end

DUI.RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", function() Rows.Refresh() end)
-- A spell learned (level, trainer, talent) may need our own icon now.
DUI.RegisterEvent("SPELLS_CHANGED", function() Rows.Refresh() end)
-- "Hide out of combat" blocks show and hide with combat.
DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function() Rows.Refresh() end)
DUI.RegisterEvent("PLAYER_REGEN_ENABLED", function() Rows.Refresh() end)
-- The other show rules only need the alpha pass.
for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE", "PLAYER_MOUNT_DISPLAY_CHANGED",
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
    DUI.RegisterEvent(e, function() Rows.Away() end)
end
DUI.On("SettingChanged", function(scope, path)
    if scope == "ActionBars" and type(path) == "string" and path:sub(1, 3) == "cdm" then Rows.Refresh() end
end)
