-- The player's Cooldown Manager layout on screen: one layout frame per talent set
-- (at screen center), one of Daylight UI's frames per piece inside it (placed from
-- CdmData.Layout), and the claiming of the game's items into them. The game keeps
-- making and laying out its items; after each of its passes the ones the
-- player placed move into their slot. It never reparents, shows, hides or scales the game's
-- frames, and all bookkeeping is in weak tables.

local _, ns = ...
local DUI = DaylightUI
local isSecret = DUI.IsSecret
local L = DUI.L
local CD = ns.Cooldowns
local Data = ns.CdmData
local Fx = ns.CdmEffects
local Tether = ns.CdmTether

local Rows = {}
ns.CdmRows = Rows

local KINDS = {
    EssentialCooldownViewer = "icon", UtilityCooldownViewer = "icon",
    BuffIconCooldownViewer = "icon", BuffBarCooldownViewer = "bar",
}
-- Viewers that hold auras (the others hold cooldowns). Decides what gets drawn when a
-- spell sits in a block of the other shape.
local AURA_VIEWERS = { BuffIconCooldownViewer = true, BuffBarCooldownViewer = true }


local weak = { __mode = "k" }
local frames = {}                          -- [g] = { layout, pieces[id], tethers[root] }, all frames
local claimed = setmetatable({}, weak)     -- item -> piece id
local sizes = setmetatable({}, weak)       -- bar item -> { w, h }
local faded = setmetatable({}, weak)       -- item -> true
local ours = setmetatable({}, weak)        -- Daylight UI's own bar (CdmBars) -> piece id, this pass
local blocks = {}                          -- [id] = the piece's block of one (Data.PieceBlock)
local blocksSet, blocksVersion             -- the set and Data.version the blocks were made from
local drawn = {}                           -- [cooldownID] = what shows it, this pass (Rows.DrawnBy)
local hooked = setmetatable({}, weak)
local pending, ready = false, false
local lastItems, lastExtra, lastOn = {}, {}, false   -- the last pass's items, for Rows.Away

local function num(v)
    if type(v) ~= "number" or isSecret(v) then return nil end
    return v
end

function Rows.Owns(item) return claimed[item] ~= nil or ours[item] ~= nil end

-- The block of one a held item (or one of Daylight UI's bars) sits in, or nil.
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
-- Whether anything can tell if placed spell id's buff is up: true, false (it's drawn
-- and nothing more, so the card leaves its state rows out), or nil when the last
-- pass didn't draw it.
function Rows.Tracked(id) return Rows.tracked[id] end

-- The game's buff rows set to Hidden in Edit Mode, by viewer name. Such a row never
-- shows its icons, so none of its buffs can be told up or down, in a fight or out.
function Rows.HiddenBuffRows()
    local out = {}
    local E = Enum and Enum.CooldownViewerVisibleSetting
    if not (E and E.Hidden ~= nil) then return out end
    for _, name in ipairs(CD.VIEWERS) do
        local v = _G[name]
        if AURA_VIEWERS[name] and type(v) == "table" and v.visibleSetting == E.Hidden then out[#out + 1] = name end
    end
    return out
end

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
        frames[g] = { layout = f, pieces = {}, tethers = {} }
    end
end

-- The fade engine's area ("ActionBars.cdm"): the shown pieces for mouseover, and the
-- layout frame that carries them. Alpha only goes on the layout frame (its pieces
-- follow) and on the game's viewers. Their items belong to the game and are never
-- Daylight UI's to hide, so it's alpha only, multiplied by the viewer's own Edit Mode
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
    if not ok or type(o) ~= "number" or isSecret(o) then return 1 end
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

-- Queues one layout pass for the fight's end.
local function heldUntilFightEnds(f)
    if usable(f) then return false end
    DUI.AfterCombat(Rows.Refresh, "cdm:tether")
    return true
end

-- Leads that are ours and unprotected carry the tether themselves; any other lead's
-- is placed from its position when it moves, never anchored to it.
local function anchorTether(f, relative, point, x, y)
    if f.tetherRelative == relative and f.tetherPoint == point and f.tetherX == x and f.tetherY == y then return end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", relative, point, x, y)
    f.tetherRelative, f.tetherPoint, f.tetherX, f.tetherY = relative, point, x, y
end

local function isHung(f)
    return f.tetherRelative ~= nil and f.tetherRelative ~= f:GetParent()
end

-- A protected tether would make its lead protected too, so it can't move in a fight.
local function hangsOff(f, key)
    return Tether.Hangable(key, f.lead) and not f:IsProtected()
end

-- Nil when it follows nothing or its lead can't be measured now.
local function leadSpot(f)
    if not f.lead then return nil end
    local pointX, pointY = Tether.PointAt(f.lead, f.leadAt)
    if not pointX then return nil end
    return pointX + f.fromLeadX, pointY + f.fromLeadY
end

-- Tethers placed beside a lead rather than hung off it: placed again on each pass, and
-- whenever the lead is placed or laid out.
local following = {}
local function setFollowing(f, placedFromLead)
    following[f] = placedFromLead or nil
end

-- Spans an attached group's shown pieces, so they move together and clamp on screen as one.
local function tetherFrame(g, root)
    local tethers = frames[g].tethers
    local f = tethers[root]
    if not f then
        f = CreateFrame("Frame", "DaylightUICdmTether" .. g .. "_" .. tostring(root), frames[g].layout)
        f:SetClampedToScreen(true)
        tethers[root] = f
    end
    return f
end

local function holdsFrame(framesByKey, f)
    for _, member in pairs(framesByKey) do
        if member == f then return true end
    end
    return false
end

-- Anything hung off these can't be a group's lead.
function Rows.IsCdmFrame(f)
    if type(f) ~= "table" then return false end
    if Rows.pieceInfo[f] then return true end
    for _, talentSetFrames in pairs(frames) do
        if talentSetFrames.layout == f or holdsFrame(talentSetFrames.pieces, f)
            or holdsFrame(talentSetFrames.tethers, f) then
            return true
        end
    end
    return false
end

-- Plugins (DaylightUI.API, kind "cdmpiece"): each shown piece's frame (Daylight UI's,
-- whatever draws the spell inside it), by its key, with what it shows. Two
-- tables kept and swapped, so a pass makes no garbage.
Rows.pieceInfo = setmetatable({}, weak)   -- piece frame -> { key, spellID, shape, drawnBy, chain, item }
local toldNow, toldLast, toldEver = {}, {}, setmetatable({}, weak)
function Rows.ReportPieces(g, items, blocks)
    local R = DUI.APIReport
    for f in pairs(toldNow) do toldNow[f] = nil end
    local set = Data.Get(g)
    for id, item in pairs(items) do
        local f = frames[g] and frames[g].pieces[id]
        if f then
            local key = tostring(id)
            local info = Rows.pieceInfo[f]
            if not info then info = {}; Rows.pieceInfo[f] = info end
            info.key, info.shape, info.drawnBy = key, blocks[id] and blocks[id].kind, drawn[id]
            info.spellID = (ns.CdmOwn and ns.CdmOwn.SpellOf(id)) or Fx.SpellOf(item)
            info.item = item
            local root = set.pieces[id] and Data.Root(set, id)
            info.chain = root ~= nil and tostring(root) or key
            toldNow[f] = key
            if not toldEver[f] then
                toldEver[f] = true
                R.Made("cdmpiece", f, key, false)
            else
                R.Unit("cdmpiece", f, key, false)
            end
        end
    end
    for f in pairs(toldLast) do
        if not toldNow[f] then R.Gone("cdmpiece", f, false) end
    end
    toldNow, toldLast = toldLast, toldNow
end

-- Whether a piece (its spell and key) is what a plugin asked for: a piece key
-- ("11", "s100"), or a spell id of any rank.
function Rows.Matches(want, spellID, key)
    if type(want) == "string" then return key == want end
    if type(want) ~= "number" then return false end
    if spellID == want or key == tostring(want) then return true end
    local C = ns.CdmCustom
    local fam = C and C.KeyOfSpell(want)
    if not fam then return false end
    return key == fam or (type(spellID) == "number" and C.KeyOfSpell(spellID) == fam)
end

-- The shown piece for a spell (any rank) or a piece key, or nil.
function Rows.PieceOf(want)
    for f, key in pairs(toldLast) do
        local info = Rows.pieceInfo[f]
        if info and (info.spellID == want or key == tostring(want)) then return f end
    end
    for f, key in pairs(toldLast) do
        local info = Rows.pieceInfo[f]
        if info and Rows.Matches(want, info.spellID, key) then return f end
    end
end

-- What a shown piece reads now (Fx.State plus what it is), or nil.
function Rows.StateOf(f)
    local info = toldLast[f] and Rows.pieceInfo[f]
    if not (info and info.item) then return nil end
    local t = Fx.State(info.item)
    t.key, t.spellID, t.shape, t.drawnBy, t.chain = info.key, info.spellID, info.shape, info.drawnBy, info.chain
    return t
end

-- A shield placed as a bar that fills by the shield left (CdmBars.IsShield). Only
-- Daylight UI's aura bar can do that, so the game's own bar for it steps aside.
local function byShield(set, id, kind)
    return kind == "bar" and ns.CdmBars ~= nil and ns.CdmBars.IsShield(id)
        and Fx.Get(set.pieces[id], "fillBy") ~= "time"
end

-- A shield placed as an icon showing its amount ("Show shield amount"). Only Daylight UI's aura
-- holder can do that (CdmAuras.SetAmount), so the game's buff icon steps aside too.
local function shieldIcon(set, id)
    return ns.CdmBars ~= nil and ns.CdmBars.IsShield(id)
        and set.pieces[id].shape ~= "bar" and Fx.Get(set.pieces[id], "shieldAmount") ~= false
end

local function release(item)
    Fx.Clear(item)
    DUI.SafeCall(CD.ClearIconText, item)
    -- A bar goes back to the game's look, its animation off.
    if type(item.Bar) == "table" then DUI.SafeCall(CD.StyleText, item) end
    if claimed[item] or faded[item] or sizes[item] then
        claimed[item], faded[item], sizes[item] = nil, nil, nil
        item:SetAlpha(1)
        Fx.GameMouse(item)
        return true
    end
end

local function touch() Rows.Refresh() end

-- The moments the game's own item changes what it says about its buff: it turns
-- active or inactive, its aura lands or ends, its cooldown comes back. The pass
-- they ask for runs after the game's handler is done, so it reads the settled item.
local STATE_HOOKS = { "OnActiveStateChanged", "TriggerAuraAppliedAlert", "TriggerAuraRemovedAlert",
    "TriggerAvailableAlert" }

-- The game's layout pass hides every item and shows it again before putting it in
-- its grid (RefreshLayout releases the pool), so a held item's OnHide/OnShow is the
-- moment to claim it back. A row that shows its inactive icons never hides one as
-- its buff drops, so the item's own state changes are listened to as well. These
-- run after the game's code and change nothing of its own.
local function hook(item)
    if hooked[item] then return end
    hooked[item] = true
    if item.HookScript then
        item:HookScript("OnShow", touch)
        item:HookScript("OnHide", touch)
    end
    for _, m in ipairs(STATE_HOOKS) do
        if type(item[m]) == "function" then hooksecurefunc(item, m, touch) end
    end
end

-- Whether the game's own item says its buff is up: true, false, or nil when it
-- can't say. A buff item (Tracked Buffs, Tracked Bars) is active only while its
-- aura is. A cooldown icon is always active and marks the aura it's showing with
-- wasSetFromAura. Both read plain in a fight. Whether the item is shown says
-- nothing: a row that shows inactive icons keeps it up while the buff is down.
local function itemUp(item, auraItem)
    local v
    if auraItem then v = item.isActive else v = item.wasSetFromAura end
    if isSecret(v) or type(v) ~= "boolean" then return nil end
    -- A buff item also lights up for a linked aura it finds on your target, after
    -- looking on you. For a buff that lands on you, that's another aura: Touch of
    -- Weakness links the debuff it leaves on whoever hit you, so its item stayed
    -- active for two minutes after the buff was used up.
    if v and auraItem then
        local unit = item.auraDataUnit
        if unit == "target" and not isSecret(unit) then
            local info = Data.Info(num(item.cooldownID))
            if type(info) == "table" and info.selfAura == true then return false end
        end
    end
    return v
end

-- A shown, held item that isn't anchored to its block, because the game laid it out
-- at a moment no event announced (Cooldowns.lua checks every CD.SCAN). Hidden ones
-- are skipped; they're placed when they show.
function Rows.Drifted()
    local fr = ready and frames[Data.CurrentIndex()]
    if not fr then return false end
    for item, id in pairs(claimed) do
        if item:IsShown() then
            if item:GetNumPoints() == 0 then return true end
            local _, rel = item:GetPoint(1)
            if not isSecret(rel) and rel ~= fr.pieces[id] then return true end
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
        -- Daylight UI's own bars also fit their timer pieces (CdmBars).
        if item.fitBar then item.fitBar(item, w, h, block, button) end
    end
end

-- x, y are from the layout's center; relative sits originX, originY from it. A move glides,
-- a new anchor snaps. Items anchored to piece frames follow, in combat too.
local function put(f, relative, relativePoint, originX, originY, x, y)
    local sameAnchor = f.goalRelative == relative and f.goalPoint == relativePoint
    if sameAnchor and f.goalOriginX == originX and f.goalOriginY == originY
        and f.goalX == x and f.goalY == y and f.atX then
        return
    end
    f.goalRelative, f.goalPoint, f.goalX, f.goalY = relative, relativePoint, x, y
    f.goalOriginX, f.goalOriginY = originX, originY
    local fx, fy = x, y
    if sameAnchor and f.atX and f:IsShown() and not (InCombatLockdown() and f:IsProtected()) then
        fx, fy = f.atX, f.atY
    end
    f.moveKey = f.moveKey or {}
    DUI.Motion.Tween(f.moveKey, 0, 1, (fx == x and fy == y) and 0 or DUI.Motion.NORMAL, function(p)
        f.atX, f.atY = fx + (x - fx) * p, fy + (y - fy) * p
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", relative, relativePoint, f.atX - originX, f.atY - originY)
    end)
end

-- By root piece; reused across passes, which run on every aura change.
local attachedChains = {}

local function forgetAttachedChains()
    for _, chain in pairs(attachedChains) do
        chain.key, chain.left, chain.tether = nil, nil, nil
    end
end

local function readAttachedChains(set)
    forgetAttachedChains()
    for _, root in ipairs(Data.Index(set).roots) do
        local key, offsetX, offsetY, at = Tether.Of(set, root)
        if key then
            local chain = attachedChains[root]
            if not chain then
                chain = {}
                attachedChains[root] = chain
            end
            local p = set.pieces[root]
            chain.key, chain.at, chain.offsetX, chain.offsetY = key, at, offsetX, offsetY
            chain.rootX, chain.rootY = tonumber(p.x) or 0, tonumber(p.y) or 0
        end
    end
end

local function coverBox(set, id, box)
    local chain = attachedChains[Data.Root(set, id)]
    if not (chain and chain.key) then return end
    local right, bottom = box.x + box.w, box.y - box.h
    if chain.left == nil then
        chain.left, chain.top, chain.right, chain.bottom = box.x, box.y, right, bottom
        return
    end
    chain.left, chain.top = math.min(chain.left, box.x), math.max(chain.top, box.y)
    chain.right, chain.bottom = math.max(chain.right, right), math.min(chain.bottom, bottom)
end

local function sizeTether(f, width, height)
    if f.tetherW == width and f.tetherH == height then return end
    f:SetSize(width, height)
    f.tetherW, f.tetherH = width, height
end

-- At the saved spot when there's no lead or it can't be measured.
local function placeTether(f, chain)
    if heldUntilFightEnds(f) or (isHung(f) and heldUntilFightEnds(f.tetherRelative)) then return end
    f.extentLeft, f.extentTop = chain.left, chain.top
    sizeTether(f, math.max(1, chain.right - chain.left), math.max(1, chain.top - chain.bottom))
    f:Show()
    f.lead, f.leadAt = Tether.Lead(chain.key), chain.at
    f.fromLeadX = chain.offsetX + (chain.left - chain.rootX)
    f.fromLeadY = chain.offsetY + (chain.top - chain.rootY)
    local hung = f.lead ~= nil and hangsOff(f, chain.key)
    setFollowing(f, f.lead ~= nil and not hung)
    if hung then
        anchorTether(f, f.lead, f.leadAt, f.fromLeadX, f.fromLeadY)
    else
        local x, y = leadSpot(f)
        anchorTether(f, f:GetParent(), "CENTER", x or chain.left, y or chain.top)
    end
end

local function hideTether(f)
    if not f:IsShown() or heldUntilFightEnds(f) then return end
    setFollowing(f, false)
    f:Hide()
end

-- Closed-up buffs count by their closed box, so they never push a group off the screen edge.
local function placeTethers(g, set, items, closed, boxes)
    readAttachedChains(set)
    for id in pairs(items) do coverBox(set, id, boxes[id]) end
    for id in pairs(closed) do coverBox(set, id, boxes[id]) end
    for root, chain in pairs(attachedChains) do
        if chain.key and chain.left then
            local f = tetherFrame(g, root)
            placeTether(f, chain)
            if f:IsShown() then chain.tether = f end
        end
    end
    for root, f in pairs(frames[g].tethers) do
        local chain = attachedChains[root]
        if not (chain and chain.tether == f) then hideTether(f) end
    end
end

local function putPiece(f, set, id, layout, x, y)
    local chain = attachedChains[Data.Root(set, id)]
    local tether = chain and chain.tether
    if tether then
        put(f, tether, "TOPLEFT", tether.extentLeft, tether.extentTop, x, y)
    else
        put(f, layout, "CENTER", 0, 0, x, y)
    end
end

-- One pass's scratch tables, wiped at its start. A pass runs on every aura shown or
-- hidden, so no fresh tables each time. items and extra come in two pairs: a pass
-- fills the one Rows.Away isn't reading and only hands it over once complete, so a
-- pass that breaks partway (under SafeCall) leaves the last complete layout to the
-- show rules.
local mine, elsewhere, elsewhereAura = {}, {}, {}
-- id -> the game's aura item for a spell drawn as "Cooldown and buff".
local auraItems = {}
-- id -> the game's cooldown item of a spell with an aura that Daylight UI draws
-- instead (Lightning Shield). It stays shown, but it keeps the aura it's showing
-- and lets go of it the moment the aura ends, in a fight too.
local auraHolders = {}
-- spell id -> the game's buff item for that spell, placed or not. A piece placed by
-- its cooldown (or one of Daylight UI's own spells) has another id than the game's
-- buff entry of the same spell, so it finds its buff's item here.
local buffItems = {}
-- spell id -> true for the buff items of a game row set to show only in combat,
-- while it's out of sight. Those items answer again once a fight starts, and until
-- then auras read plainly, so such a buff can be told all the time.
local asleep = {}
-- Game items from the buff rows (the others are cooldown icons).
local auraKind = setmetatable({}, weak)
local usedOwn, usedHolders, usedHolds, usedBars = {}, {}, {}, {}
local shown, downs, told = {}, {}, {}
-- id -> whether anything can tell if the piece's buff is up (the game's own item, or
-- its holder by itself). false = drawn and nothing more: no state options apply.
local tracked = {}
Rows.tracked = tracked
-- id -> Daylight UI's aura holder whose buff is down and gave up its spot (slide over).
local closed = {}
-- id -> true when it closed because it's up and hidden (Buff up Hide).
local closedUp = {}
-- id -> whether it's time to cast it again (the recast glow, CdmAuras.Clip).
local clips = {}
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

-- What each placed spell shows (CdmOwn.Track), worked out once per pass.
local tracks = {}
local function trackOf(id, p)
    local t = tracks[id]
    if t == nil then
        t = ns.CdmOwn.Track(id, p, knownNow()) or false
        tracks[id] = t
    end
    return t or nil
end

local INFO_SPELLS = { "spellID", "overrideSpellID", "overrideTooltipSpellID", "linkedSpellID" }

-- What the game's buff items for these spell ids say: up when any of them is up,
-- down when the ones that answer are all down, nil when none does. A piece can
-- stand for several of the game's buffs (a paladin's Aura or Seal: any one counts),
-- so one item alone isn't the answer.
local function buffUp(ids)
    local up
    for sid in pairs(ids or {}) do
        local item = buffItems[sid]
        if item then
            local v = itemUp(item, true)
            if v == true then return true end
            if v == false then up = false end
        end
    end
    return up
end

-- Whether the game's items say piece id's buff is up: true, false, or nil when the
-- game has no item for it, or has one that can't see this aura.
local function truthUp(id, holder)
    local A = ns.CdmAuras
    -- A piece Daylight UI draws from its own knowledge (the pet, a debuff on you)
    -- isn't an aura the game's item looks for. Nor is a trap's debuff or a pet's buff.
    if holder and holder.face then return nil end
    if A and A.Unseen(id) then return nil end
    -- A buff someone else can put up too (Battle Shout): the item only counts your
    -- own cast. Where the holder can read it whoever cast it, that's the better
    -- word, though the item saying yours is up still counts; where it can't,
    -- yours being up or down is the best there is.
    if A and A.GameBlind(id) and A.Knows(holder) then
        if holder.anyCaster and buffUp(holder.ids) == true then return true end
        return nil
    end
    -- A row that doesn't list the rank you know: its item saying up is still true
    -- (a lower rank), but its silence isn't a down.
    if A and A.Short(id) then return buffUp(holder and holder.ids) == true or nil end
    local item = auraItems[id] or (elsewhereAura[id] and elsewhere[id]) or nil
    if item then return itemUp(item, true) end
    if auraHolders[id] then return itemUp(auraHolders[id], false) end
    -- The game's cooldown icon, out of sight because the piece is a bar: it still
    -- marks the aura it would be showing.
    if elsewhere[id] and ns.CdmAuras and ns.CdmAuras.Follows(id) then return itemUp(elsewhere[id], false) end
    return buffUp(holder and holder.ids)
end

-- Every spell id the game's row for a cooldown id stands for.
local function eachSpell(id, fn)
    local info = Data.Info(id)
    if type(info) ~= "table" then return end
    for _, key in ipairs(INFO_SPELLS) do
        local sid = num(info[key])
        if sid then fn(sid) end
    end
    if type(info.linkedSpellIDs) == "table" then
        for _, sid in ipairs(info.linkedSpellIDs) do
            sid = num(sid)
            if sid then fn(sid) end
        end
    end
end

-- A buff row the game hides until a fight. Its items carry nothing while hidden,
-- so the buffs it shows come from the game's list for the row: the ones shown by
-- default, and the hidden ones Daylight UI switched on. Kept until the game's
-- spell data changes.
local ROW_OF = { BuffIconCooldownViewer = 2, BuffBarCooldownViewer = 3 }
local HIDE_BY_DEFAULT = 2   -- Enum.CooldownSetSpellFlags.HideByDefault
local rowSpells = {}
local function sleepRow(v, name)
    CD.EachItem(v, release)
    local row, CV = ROW_OF[name], C_CooldownViewer
    if not row or type(CV) ~= "table" or type(CV.GetCooldownViewerCategorySet) ~= "function" then return end
    local spells = rowSpells[row]
    if not spells then
        spells = {}
        rowSpells[row] = spells
        local on = DUI.DB.Character().cdmSwitched
        local ids = CV.GetCooldownViewerCategorySet(row, false)
        for _, id in ipairs(type(ids) == "table" and ids or {}) do
            local info = Data.Info(id)
            local flags = info and tonumber(info.flags) or 0
            if bit.band(flags, HIDE_BY_DEFAULT) == 0 or (type(on) == "table" and on[id] == row) then
                eachSpell(id, function(sid) spells[sid] = true end)
            end
        end
    end
    for sid in pairs(spells) do asleep[sid] = true end
end
for _, e in ipairs(Data.INFO_EVENTS) do DUI.RegisterEvent(e, function() wipe(rowSpells) end) end

local function sleeps(ids)
    for sid in pairs(ids or {}) do
        if asleep[sid] then return true end
    end
    return false
end

-- One of the game's items (in viewer passName): held in its piece, hidden so Daylight UI's
-- can draw it, or released.
local function claim(item)
    local id = num(item.cooldownID)
    if not id or not usable(item) then return end
    local set, name = passSet, passName
    local kind = KINDS[name]
    local block = passOn and blocks[id]
    auraKind[item] = AURA_VIEWERS[name] or nil
    if AURA_VIEWERS[name] then
        hook(item)
        eachSpell(id, function(sid)
            if not buffItems[sid] then buffItems[sid] = item end
        end)
    end
    -- The game's item doesn't show what the spell is set to show (CdmOwn.GameDraws
    -- has the whole rule): a buff item tracked as its cooldown or both (Shield
    -- Block, Charge; it hides while the buff is down), or a cooldown icon set to
    -- Cooldown or Buff only (Rend, Death Wish). Daylight UI draws it below and the
    -- game's stays hidden. Only the spell's facts and the player's What it shows
    -- pick decide this. Hide (Buff up), the glows and the sounds never do: they
    -- work on whichever draws the spell.
    local cooldown = false
    local Own = ns.CdmOwn
    -- An aura the game's item can't see (a buff on your pet, a trap's debuff past
    -- its first rank, a summoned hawk): Daylight UI's holder shows it instead.
    local blind = block and ns.CdmAuras ~= nil and ns.CdmAuras.GameBlind(id)
    if block and Own then
        cooldown = not Own.GameDraws(id, trackOf(id, set.pieces[id]), AURA_VIEWERS[name] == true)
    end
    if block and ns.CdmAuras and ns.CdmAuras.SelfDebuff(id) then
        -- The debuff lands on you (Arcane Blast's stack). The game's item never
        -- sees it, so it says nothing either way. Daylight UI draws it from your debuffs
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
        -- up, in a fight too. It's the one plain signal when the aura ends early,
        -- unless it can't see the aura at all.
        if AURA_VIEWERS[name] and not blind then
            hook(item)
            auraItems[id] = item
        elseif not blind and ns.CdmAuras and ns.CdmAuras.Follows(id) then
            auraHolders[id] = item
        end
    elseif block and (not Data.Native(block, kind) or byShield(set, id, kind)
        or (AURA_VIEWERS[name] and shieldIcon(set, id))) then
        -- Placed in the other shape (or a shield bar filled by the shield left,
        -- which the game's bar can't do): Daylight UI draws the spell and the game's item
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
        Fx.GameMouse(item)
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


-- Every item of one of the game's viewers, for this pass. A viewer the game hides
-- stops updating its items, so they're let go and Daylight UI draws their spells.
local function claimAll(v, name)
    -- Edit Mode's Visibility choice for the row: shown only in a fight.
    local E = Enum and Enum.CooldownViewerVisibleSetting
    if v:IsShown() then
        CD.EachItem(v, claim)
    elseif AURA_VIEWERS[name] and E and E.InCombat ~= nil and v.visibleSetting == E.InCombat then
        sleepRow(v, name)
    else
        CD.EachItem(v, release)
    end
end

-- The editor's card leaves out the rows a buff can't use. A spell placed a moment
-- ago had its card drawn before a pass looked at it, so the card is drawn again
-- when the answer for the picked spell changed.
local cardFor, cardTold
local function redrawCard()
    local Ed, Card = ns.CdmEditor, ns.CdmCard
    local sel = Ed and Card and Ed.IsOpen() and Ed.Selected() or nil
    if sel == nil or not Card.Shown() then
        cardFor, cardTold = nil, nil
        return
    end
    if cardFor == sel and cardTold == tracked[sel] then return end
    local first = cardFor ~= sel
    cardFor, cardTold = sel, tracked[sel]
    if not first or tracked[sel] == false then DUI.SafeCall(Card.Draw) end
end

-- Starts or ends a pass for claim() and drawOurs().
local function setPass(set, on, hide)
    passSet, passOn, passHide, passKnown = set, on, hide, nil
    wipe(tracks)
end

-- A placed spell the game's own item draws: whether its buff is up, and its recast
-- glow. A buff item answers for itself, and so does a cooldown icon that shows its
-- aura while it's up (Rend). A cooldown icon that never shows its aura (Mortal
-- Strike) asks the game's buff item of the same spell.
local function heldState(id, p, item)
    local A = ns.CdmAuras
    local t = trackOf(id, p)
    local up
    if auraKind[item] then
        up = itemUp(item, true)
    elseif A and A.Follows(id) and not A.GameBlind(id) then
        up = itemUp(item, false)
        -- A buff under a linked spell (Bloodrage's): the game's buff item of the
        -- spell sees it as well, and either one saying up is the game's word.
        if up == false and not A.Follows(id, true) then
            if buffUp(A.Watch(id).ids) then up = true end
        end
    elseif A and t then
        local w = A.Watch(id)
        up = buffUp(w.ids)
        -- A row that doesn't list the rank you know can't call the buff down.
        if up == false and A.Short(id) then up = nil end
        -- The game's buff item is in a row that only shows in a fight: until then
        -- the aura reads plainly. With no item at all nothing can tell, and the
        -- card leaves its state rows out.
        tracked[id] = sleeps(w.ids)
        w.reads = (up == nil and tracked[id]) or nil
        if w.reads then up = A.Read(w) end
    end
    if up ~= nil then downs[id], tracked[id] = not up, true end
    -- Glow to recast runs on your own cast's clock, whoever draws the spell.
    if A and t and Fx.ClipGlows(p) then
        local w = A.Watch(id)
        w.wantsClip = true
        A.Told(w, up)
        if up ~= false then clips[id] = A.Clip(w, ns.CdmOwn.SpellOf(id)) end
    end
end

-- drawOurs results that are aura holders themselves.
local HOLDS = { ["aura icon"] = true, ["aura bar"] = true, ["aura and cooldown bar"] = true }

-- A spell the game has no item of this shape for, drawn by Daylight UI in piece frame f.
-- Bar: Daylight UI's cooldown bar or aura bar (CdmBars). Icon: Daylight UI's own icon, or for an aura the
-- game's aura display in a Daylight UI holder (CdmAuras). track = a buff spell's pick
-- (CdmOwn.Track), "cooldown" or "both".
local function drawOurs(id, p, block, f, always, aura, track)
    local set, Own = passSet, ns.CdmOwn
    local item
    -- A totem with its buff known (CdmOwn.Track "both"): Totem and buff. A bar
    -- shows the totem's time alone.
    local C = ns.CdmCustom
    local element = C ~= nil and C.Element(id) ~= nil
    local buffTotem = track == "both" and C ~= nil and Own ~= nil and (element or C.Totem(Own.SpellOf(id)) ~= nil)
    if buffTotem and block.kind == "bar" then track, buffTotem = "totem", false end
    if block.kind == "bar" then
        local Bars = ns.CdmBars
        if not Bars then return nil end
        -- A cooldown the game shows by its aura while up (Rend): the aura's bar,
        -- over the cooldown when it has a real one (Death Wish), like the
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
        -- Daylight UI's cooldown icon, with the buff's button over it while up.
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
    -- A totem's icon or bar runs on the totem's time (CdmCustom.TotemUp).
    local totem = (track == "totem" or buffTotem) or nil
    -- It dims only once a cast has taught its buff (CdmCustom.TotemBuffKnown): until
    -- then nothing could cover it, so it stays full. An element piece asks for each
    -- totem as it stands (CdmOwn.Update).
    local dims = (buffTotem and (element or C.TotemBuffKnown(Own.SpellOf(id)))) or nil
    if item and (item.totem ~= totem or item.totemBuff ~= dims) then
        item.totem, item.totemBuff = totem, dims
        if block.kind == "bar" then
            if ns.CdmBars then ns.CdmBars.UpdateCooldown(item) end
        else
            Own.Update(item)
        end
    end
    if totem and item then
        drawn[id] = buffTotem and "totem and buff icon" or block.kind == "bar" and "totem bar" or "totem icon"
    end
    return item
end

function Rows.Update()
    pending = false
    if not ready then return end
    -- A layout pass may have made fresh pool items, so apply Daylight UI's look first.
    CD.Scan()
    local g = Data.CurrentIndex()
    local set = Data.Get(g)
    local on = Data.Switch("on") and next(set.pieces) ~= nil and frames[g] ~= nil
    -- With the layout on, the game's own items stay hidden even when the set has no
    -- pieces yet (the game keeps adding newly learned spells).
    local hide = Data.Switch("on") and Data.Switch("hideUnplaced")
    -- An older layout's unset spells keep what they showed, before anything reads it.
    if on and ns.CdmOwn and (not set.tracksKept or set.tracksLeft) then ns.CdmOwn.KeepOldTracks(set) end

    -- A block comes from the saved layout alone, and every write to it goes through
    -- Data.Changed. Passes run on every aura change in a fight, so the blocks are
    -- kept until the layout or the set in use changes.
    local want = on and set or nil
    if blocksSet ~= want or blocksVersion ~= Data.version then
        for k in pairs(blocks) do blocks[k] = nil end
        if on then
            for id in pairs(set.pieces) do blocks[id] = Data.PieceBlock(set, id) end
        end
        blocksSet, blocksVersion = want, Data.version
    end

    -- Only this set's layout shows.
    for gg, fr in pairs(frames) do
        local show = on and gg == g
        fr.layout:SetShown(show)
        for id, f in pairs(fr.pieces) do
            if not (show and set.pieces[id]) then f:Hide() end
        end
        if not show then
            for _, f in pairs(fr.tethers) do hideTether(f) end
        end
    end

    -- Claim items by piece.
    wipe(mine); wipe(elsewhere); wipe(elsewhereAura); wipe(auraItems); wipe(auraHolders); wipe(buffItems)
    for k in pairs(ours) do ours[k] = nil end
    for k in pairs(drawn) do drawn[k] = nil end
    setPass(set, on, hide)
    wipe(asleep)
    for name in pairs(KINDS) do
        local v = _G[name]
        if type(v) == "table" then
            passName = name
            -- A viewer the game hides (Cooldown Manager off, viewer set to Hidden,
            -- or In combat while out of a fight) hides its items and stops updating
            -- them. They're released and Daylight UI draws their spells. When it shows
            -- again they're claimed back (hook).
            hook(v)
            claimAll(v, name)
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
    wipe(downs); wipe(closed); wipe(closedUp); wipe(clips); wipe(tracked)
    if ns.CdmAuras then ns.CdmAuras.ClipPass() end
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
                -- The game draws it in the other shape. An aura the game's item
                -- says is down closes up; "Show missing buffs" keeps it, empty.
                local up = awayAura and itemUp(away, true)
                if awayAura and up ~= nil then downs[id] = not up end
                if always or not block.collapse or not awayAura or up ~= false then
                    -- A cooldown set to Cooldown and buff by hand keeps the cooldown
                    -- under the aura bar even when that can't be told.
                    local both = not awayAura and Own and Own.Picked(p) == "both" and "both" or nil
                    item = drawOurs(id, p, block, f, always, awayAura, both)
                    if item and block.kind == "bar" and awayAura then
                        Fx.Flash(item, item.Bar, always and not up
                            and Fx.Get(p, "inactiveFlash") == true)
                    end
                end
            elseif not item and k then
                local track = trackOf(id, p)
                if track == "buff" then
                    item = drawOurs(id, p, block, f, always, true)
                elseif track then
                    item = drawOurs(id, p, block, f, always, false, track)
                else
                    item = drawOurs(id, p, block, f, always, k.aura)
                end
            elseif item and Own then
                heldState(id, p, item)
            end
            -- Daylight UI's aura holder (icon or bar). Whether its buff is up is the
            -- game's own item's to say, else the holder's where it really knows
            -- (CdmAuras.Knows). A buff nothing can tell about is drawn and nothing
            -- more: every option that needs its state stays off.
            local holder = item and ns.CdmAuras and (HOLDS[drawn[id]] and item
                or drawn[id] == "aura and cooldown icon" and ns.CdmAuras.Frame(id))
            local closedNow = false
            if holder then
                local up = truthUp(id, holder)
                local knows = up ~= nil or ns.CdmAuras.Knows(holder)
                -- The game's item for this buff sits in a row that only shows in a
                -- fight. It answers there, and out of one the aura reads plainly, so
                -- the buff's options work all the time and the card keeps them.
                local hasRow = not knows and not ns.CdmAuras.Unseen(id) and sleeps(holder.ids)
                holder.reads = hasRow or nil
                if hasRow then
                    up = ns.CdmAuras.Read(holder)
                    knows = up ~= nil
                end
                tracked[id] = knows or hasRow
                local hide = knows and Fx.Get(p, "hideActive") == true
                local sound = knows and Fx.Get(p, "buffSound") ~= "none"
                -- An end sound needs the ups as well as the downs.
                local ends = knows and Fx.Get(p, "buffEndSound") ~= "none"
                -- "Slide over when a buff drops": a Daylight UI buff that's down gives
                -- up its spot like the game's own (which hide). Not a shield bar,
                -- which stays as an empty bar, nor a bar with its cooldown under it.
                local canSlide = knows and block.collapse and HOLDS[drawn[id]] == true
                    and drawn[id] ~= "aura and cooldown bar"
                local slides = canSlide and not always
                    and not (byShield(set, id, block.kind) and Fx.Get(p, "hideMissing") ~= true)
                -- Hidden while up (Buff up Hide) has nothing to keep a spot for,
                -- whatever Keep its spot says, since that's about while it's missing.
                -- Otherwise a missing buff set to Show stayed off the group's middle.
                local hideSlides = canSlide and hide
                local glowUp = knows and Fx.UpGlows(p)
                local clip = Fx.ClipGlows(p)
                -- A cooldown with its buff over it, faded or hidden on cooldown or
                -- while ready: while the buff is up it shows (CdmEffects), so it
                -- needs the ups too.
                local cdFx = knows and drawn[id] ~= nil and string.find(drawn[id], "aura and cooldown", 1, true) ~= nil
                    and (Fx.Get(p, "onCd") ~= "show" or Fx.Get(p, "onReady") ~= "show"
                        or Fx.Get(p, "onUnusable") ~= "show" or Fx.Get(p, "onShort") ~= "show")
                local missing = knows and Fx.Get(p, "missingGlow") == true
                holder.wantsUp = (hide or sound or ends or slides or glowUp or cdFx or missing) or nil
                -- Glow to recast runs on your own cast's clock (CdmAuras.Clip), so it
                -- works with no word on the buff too; a "down" still turns it off.
                holder.wantsClip = clip or nil
                if up ~= nil then
                    ns.CdmAuras.Told(holder, up)
                elseif knows then
                    -- Asked only when an option needs it; the holder keeps its own
                    -- answer fresh on aura and cast events.
                    if holder.wantsUp then up = ns.CdmAuras.IsUp(holder) else up = holder.up end
                else
                    ns.CdmAuras.Told(holder, nil)
                end
                if holder.wantsUp then
                    if downs[id] == nil and (up == false or (up == true and (hide or sound or ends or glowUp or cdFx))) then downs[id] = not up end
                    -- Only a known "down"; an unknown one keeps its spot.
                    closedNow = (slides and up == false) or (hideSlides and up == true)
                    if closedNow and up == true then closedUp[id] = true end
                end
                if clip and up ~= false then clips[id] = ns.CdmAuras.Clip(holder, Own.SpellOf(id)) end
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
            -- on the game's buff item or Daylight UI's cooldown icon under a buff, whatever
            -- Keep its spot says (Fx.GoneUp).
            if item and not closedNow and block.collapse and Fx.Gone(item)
                and (not always or Fx.GoneUp(item) or Fx.GoneForm(item)) then
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
        placeTethers(g, set, items, closed, boxes)
        -- A closed-up Daylight UI buff stays shown where it gave up its spot, with
        -- nothing visible while down, so its button comes up there the moment the
        -- buff does. The game's item saying "up" reopens the spot.
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
            putPiece(f, set, id, layout, x, y)
            f:SetSize(w, h)
            f:Show()
            place(item, blocks[id], f, set.pieces[id])
        end
        for id, item in pairs(items) do
            local b, f = boxes[id], pieceFrame(g, id)
            putPiece(f, set, id, layout, b.x, b.y)
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
    -- Daylight UI's own icons and bars (CdmOwn, CdmBars) take the same options: On cooldown,
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
    -- Daylight UI's own bars too (CdmBars: Rend, spells the game draws as icons). Their fill
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
        Fx.SetDown(item, set.pieces[id], downs[id], clips[id])
    end
    -- Closed while up: pass along what this pass read (a drop reopens its spot).
    for id in pairs(closedUp) do
        told[closed[id]] = true
        Fx.SetDown(closed[id], set.pieces[id], downs[id] == true, clips[id])
    end
    Fx.EndPass(told)
    -- Done here, not above, since a buff that's down may have closed up out of items.
    for id, isDown in pairs(downs) do Fx.BuffMoment(set.pieces[id], items[id], isDown, id) end

    DUI.SafeCall(Rows.ReportPieces, g, items, blocks)

    -- The chain's show rules (out of combat, group, target, mounted, where).
    lastItems, lastExtra, lastOn = items, extra, on
    setPass(nil, false, false)
    Rows.Away()

    -- Anything released waits for the game's own next layout pass. Never call the
    -- viewer's RefreshLayout from here: run from addon code it's tainted, fails
    -- partway on secret values and leaves the game's items emptied (no cooldownID,
    -- hidden) until a reload.
    -- The time on the game's bars, now that each spell has its bar.
    if ns.BuffBars then DUI.SafeCall(ns.BuffBars.SyncClocks) end
    redrawCard()
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
    -- A closed-up Daylight UI buff follows its chain's rules too, since its button may
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
    if isSecret(v) then return "secret" end
    if type(v) == "number" and v % 1 ~= 0 then return string.format("%.2f", v) end
    return tostring(v)
end
function Rows.Why()
    local out = {}
    local g = Data.CurrentIndex()
    local set = Data.Get(g)
    local fr = frames[g]
    local okS, secret = false, nil
    if C_Secrets and type(C_Secrets.ShouldAurasBeSecret) == "function" then okS, secret = true, C_Secrets.ShouldAurasBeSecret() end
    out[#out + 1] = string.format("set %s, on %s, hideUnplaced %s, editing %s, combat %s, pieces %s, auras readable %s (restricted %s, auras secret %s)",
        word(g), word(Data.Switch("on")), word(Data.Switch("hideUnplaced")), word(Rows.editing),
        word(InCombatLockdown()), word(fr ~= nil), word(ns.CdmAuras ~= nil and ns.CdmAuras.Readable()),
        word(DUI.Restricted()), okS and word(secret) or "unknown")
    -- Each of the game's rows: a buff row hidden in Edit Mode, or one with no items
    -- at all, is why every buff of a layout reads "game: none".
    local rows, switched = {}, DUI.DB.Character().cdmSwitched
    for _, name in ipairs(CD.VIEWERS) do
        local v, n = _G[name], 0
        if type(v) == "table" then
            CD.EachItem(v, function() n = n + 1 end)
            rows[#rows + 1] = string.format("%s shown %s visibility %s items %d", name, word(v:IsShown()), word(v.visibleSetting), n)
        end
    end
    local count = 0
    for _ in pairs(type(switched) == "table" and switched or {}) do count = count + 1 end
    out[#out + 1] = string.format("%s; game's CVar %s, buffs switched on %d", table.concat(rows, ", "),
        word(type(GetCVar) == "function" and GetCVar(CD.GAME_SWITCH) or nil), count)
    local games = {}
    Rows.EachItem(function(item, id, kind)
        local t = games[id] or {}
        games[id] = t
        local rel
        if item:GetNumPoints() > 0 then rel = select(2, item:GetPoint(1)) end
        local at = isSecret(rel) and "anchor secret"
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
        -- Daylight UI's aura holder: what it knows about its buff (for slide over).
        local h = closed[id] or (HOLDS[drawn[id]] and item) or nil
        local buff = ""
        if h then
            buff = string.format(", buff up %s (asked %s, tracked %s, slid out %s, containers %s)", word(h.up), word(h.wantsUp),
                word(tracked[id]), word(closed[id] ~= nil), word(type(h.containers) == "table" and #h.containers))
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
-- A spell learned (level, trainer, talent) may need Daylight UI's own icon now.
DUI.RegisterEvent("SPELLS_CHANGED", function() Rows.Refresh() end)
-- "Hide out of combat" blocks show and hide with combat.
DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function() Rows.Refresh() end)
-- Leads built or moved in combat can be followed now.
DUI.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    Tether.Stale()
    Rows.Refresh()
end)
-- The other show rules only need the alpha pass.
for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE", "PLAYER_MOUNT_DISPLAY_CHANGED",
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
    DUI.RegisterEvent(e, function() Rows.Away() end)
end
local function isFollowed(key)
    for _, chain in pairs(attachedChains) do
        if chain.key == key then return true end
    end
    return false
end

-- Any frame placed may carry a lead hung off it, so a group placed from a lead is
-- placed again. Settings place every frame again: one pass for the burst.
DUI.On("MoverApplied", function()
    local leadChanged = Tether.Restate()
    if leadChanged or next(following) ~= nil then Rows.Refresh() end
end)
-- Party and raid frames laid out again move without being placed.
DUI.On("FrameLaidOut", function(key)
    if isFollowed(key) then Rows.Refresh() end
end)
DUI.On("UnlockChanged", function()
    if next(following) ~= nil then Rows.Refresh() end
end)
-- Any setting may switch a lead on or off, or make it loop. Only that needs a pass:
-- a group whose lead moves is placed again when the lead is placed or laid out, else on
-- the next pass.
DUI.On("SettingChanged", function(scope, path)
    local leadChanged = Tether.Restate()
    local isCdmSetting = scope == "ActionBars" and type(path) == "string" and path:sub(1, 3) == "cdm"
    if leadChanged or isCdmSetting then Rows.Refresh() end
end)
