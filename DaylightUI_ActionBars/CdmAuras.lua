-- Aura spells the game's Cooldown Manager doesn't display. Each gets a holder in the
-- layout slot with a client AuraContainer inside: given a unit, filter and spell ids,
-- the client finds the aura and draws the button only while it's up. Its buttons are
-- never read. Whether the aura is up is the game's own Cooldown Manager item's to
-- say (CdmRows asks it). A holder answers by itself only for what it really knows:
-- the pet, a debuff it counts from your own casts, an aura the game never hides, and
-- a buff or debuff anyone's cast counts for (its own button says, A.WatchShown).
-- Any other buff with no item of the game's is drawn and nothing more.

local _, ns = ...
local DUI = DaylightUI
local isSecret = DUI.IsSecret
local Style, Skin, Pixel, Motion = DUI.Style, ns.Skin, DUI.Pixel, DUI.Motion

local A = {}
ns.CdmAuras = A

local holders = {}   -- [id] = holder frame
local makeFace, placeFace, paintFace   -- self-debuff face, defined below
local selfCast                          -- counts a self debuff from your casts, below

local function plain(v)
    return type(v) == "number" and not isSecret(v) and v or nil
end

local function infoOf(id) return ns.CdmData.Info(id) end

local function nameOf(sid)
    if not sid or not C_Spell or not C_Spell.GetSpellName then return nil end
    local ok, n = pcall(C_Spell.GetSpellName, sid)
    if ok and type(n) == "string" and not isSecret(n) then return n end
end

-- Add the auras your casts of these spells were seen to put up (CdmOwn.AuraOf),
-- for the spells the game's data has no aura id for (a totem's buff, a trinket's).
local function withLearned(ids)
    local Own = ns.CdmOwn
    if not (Own and Own.AuraOf) then return ids end
    local more
    for s in pairs(ids) do
        local got = Own.AuraOf(s)
        if got then
            more = more or {}
            for a in pairs(got) do more[a] = true end
        end
    end
    for a in pairs(more or {}) do ids[a] = true end
    return ids
end

-- { [spellID] = true } for the spell and every rank of it (by name), learned or not,
-- and the auras seen from its casts.
function A.SpellIDs(id)
    local C = ns.CdmCustom
    if C and C.Is(id) then return withLearned(C.Ranks(id)) end
    local ids = {}
    local own = infoOf(id)
    local base = own and plain(own.spellID)
    local name = nameOf(base)
    local function add(info)
        for _, k in ipairs({ "spellID", "overrideSpellID", "overrideTooltipSpellID", "linkedSpellID" }) do
            local s = plain(info[k]); if s then ids[s] = true end
        end
        if type(info.linkedSpellIDs) == "table" then
            for _, s in ipairs(info.linkedSpellIDs) do if plain(s) then ids[s] = true end end
        end
    end
    if own then add(own) end
    -- Some cooldowns' auras are only known from the spell list (Bloodrage).
    local key = C and base and C.KeyOfAuraSpell(base)
    if key then
        for s in pairs(C.Ranks(key)) do ids[s] = true end
    end
    local cats = name and ns.CdmData.Categories()
    if cats then
        local CV, seen = _G.C_CooldownViewer, {}
        for _, cat in pairs(cats) do
            local list = CV.GetCooldownViewerCategorySet(cat, true)
            for _, cid in ipairs(type(list) == "table" and list or {}) do
                local info = not seen[cid] and plain(cid) and infoOf(cid)
                seen[cid] = true
                if info and nameOf(plain(info.spellID)) == name then add(info) end
            end
        end
    end
    -- The aura's own ids from the game's data, when the cast's id isn't the aura's
    -- (Bloodrage, Prayer of Mending).
    local more
    for s in pairs(ids) do
        local fact = C and C.Fact(s)
        for _, a in ipairs(fact and fact.auras or {}) do
            more = more or {}
            more[a] = true
        end
    end
    for a in pairs(more or {}) do ids[a] = true end
    return withLearned(ids)
end

-- Spells that put a debuff on you (Arcane Blast's stack). The game's item only
-- looks for HELPFUL|PLAYER on you (GetTargetAurasFilterString), so it never sees
-- these and the addon draws them instead.
-- CdmCustom key for a piece: itself, or the family of the game item's spell.
local function ownKey(id)
    local C = ns.CdmCustom
    if not C then return nil end
    if C.Is(id) then return id end
    local info = infoOf(id)
    local base = info and plain(info.spellID)
    if not base then return nil end
    local key = C.KeyOfAuraSpell(base)
    if key then return key end
    -- A debuff on you that's on no class list has a game row of its own too
    -- (Weakened Soul). Its item lights up but never finds the time, so the row
    -- goes to the same piece as the spell added by its ID.
    if C.SELF_DEBUFF[base] then return "s" .. base end
    return nil
end

function A.SelfDebuff(id)
    local own = ownKey(id)
    return own ~= nil and ns.CdmCustom.SelfDebuff(own) or nil
end

-- Duration and max stacks from CdmCustom.SELF_DEBUFF.
function A.SelfDebuffFacts(id)
    local own = ownKey(id)
    return own ~= nil and ns.CdmCustom.SelfDebuffFacts and ns.CdmCustom.SelfDebuffFacts(own) or nil
end

-- A trap: its cast puts nothing up, the debuff comes when a mob walks in.
function A.Trap(id)
    local own = ownKey(id)
    return own ~= nil and ns.CdmCustom.Trap(own) or false
end

-- Its buff lands on your pet (Bestial Wrath).
function A.OnPet(id)
    local own = ownKey(id)
    return own ~= nil and ns.CdmCustom.OnPet(own) or false
end

-- A helper summoned for a while (Summon Hawk): { lasts, most }, or nil.
function A.SummonFacts(id)
    local own = ownKey(id)
    return own ~= nil and ns.CdmCustom.SummonFacts and ns.CdmCustom.SummonFacts(own) or nil
end

-- The game's own item can't show this aura: it looks on you and your target only,
-- by the ids its data links (a trap's first rank, never your pet, never a summon),
-- and only for auras you cast, so a group buff or a one-copy debuff from someone
-- else stays dark. CdmRows hands such a spell to Daylight UI's holder whenever its
-- aura is wanted.
function A.GameBlind(id)
    local own, C = ownKey(id), ns.CdmCustom
    return own ~= nil and (C.Trap(own) or C.OnPet(own) or C.SummonFacts(own) ~= nil
        or C.Shared(own) or C.Unique(own) or A.Short(id))
end

-- The game's item finds an aura only by the spell ids its row lists, and some rows
-- stop short of the ranks a spell has: Sap's lists none of the debuffs its higher
-- ranks leave, Touch of Weakness's none of the buff's. With such a rank learned the
-- item stays dark while the aura is up, so its "down" means nothing. True when the
-- highest rank you know puts up an aura under its own id that no row of the spell
-- lists. Kept per piece until the spells or the game's rows change.
local short = {}
function A.Short(id)
    local v = short[id]
    if v ~= nil then return v end
    v = false
    local own, C = ownKey(id), ns.CdmCustom
    local top = own ~= nil and C.Learned(own) or nil
    local fact = top and C.Fact(top)
    local cats = fact and fact.on ~= nil and fact.auras == nil and ns.CdmData.Categories()
    if cats then
        local CV, ranks, listed, rows = _G.C_CooldownViewer, C.Ranks(own), {}, 0
        for _, cat in pairs(cats) do
            local list = CV.GetCooldownViewerCategorySet(cat, true)
            for _, cid in ipairs(type(list) == "table" and list or {}) do
                local info = plain(cid) and infoOf(cid)
                if info and (cid == id or ranks[plain(info.spellID)]) then
                    rows = rows + 1
                    for _, k in ipairs({ "spellID", "overrideSpellID", "overrideTooltipSpellID", "linkedSpellID" }) do
                        local s = plain(info[k]); if s then listed[s] = true end
                    end
                    for _, s in ipairs(type(info.linkedSpellIDs) == "table" and info.linkedSpellIDs or {}) do
                        if plain(s) then listed[s] = true end
                    end
                end
            end
        end
        v = rows > 0 and not listed[top]
    end
    short[id] = v
    return v
end
local function forgetShort() for k in pairs(short) do short[k] = nil end end
DUI.RegisterEvent("SPELLS_CHANGED", forgetShort)
for _, e in ipairs(ns.CdmData.INFO_EVENTS) do DUI.RegisterEvent(e, forgetShort) end

-- A buff anyone's cast counts for (Battle Shout) or a debuff the target holds one
-- copy of (Sunder Armor). The game's item lights for your own cast alone, so with
-- someone else's up it says down. The holder watches every caster's, so its own
-- button is the word (A.WatchShown).
function A.AnyCaster(id)
    local own, C = ownKey(id), ns.CdmCustom
    return own ~= nil and (C.Shared(own) or C.Unique(own)) or false
end

-- The game's item never sees this aura at all: a trap's debuff, a buff on your pet,
-- a summoned helper. (A buff others can cast too it does see, only never theirs.)
function A.Unseen(id)
    local own, C = ownKey(id), ns.CdmCustom
    return own ~= nil and (C.Trap(own) or C.OnPet(own) or C.SummonFacts(own) ~= nil) or false
end

-- A buff you cast on a friend (Renew, Prayer of Mending): watched on your friendly
-- target, else on you, as the game's own icon looks for it.
function A.Friend(id)
    local own = ownKey(id)
    return own ~= nil and ns.CdmCustom.Friend(own) or false
end

-- A debuff the target carries one copy of: anyone's counts (CdmCustom.UNIQUE).
function A.Unique(id)
    local own = ownKey(id)
    return own ~= nil and ns.CdmCustom.Unique(own) or false
end

-- Whether one of a cooldown's linked spells is itself a buff or debuff, by the
-- game's spell data. A rank that only triggers one under another id (Charge and
-- its stun) doesn't count: the icon looks for the linked ids alone.
local function linkedAura(info)
    local C = ns.CdmCustom
    local links = info.linkedSpellIDs
    if not C or type(links) ~= "table" then return false end
    local own = C.Fact(plain(info.spellID))
    local listed = {}
    for _, sid in ipairs(own and own.auras or {}) do listed[sid] = true end
    for _, sid in ipairs(links) do
        sid = plain(sid)
        local fact = sid and C.Fact(sid)
        if sid and (listed[sid] or (fact and fact.on ~= nil and fact.auras == nil)) then return true end
    end
    return false
end

-- Cooldowns the game shows by their aura while it's up (Rend, Death Wish,
-- Bloodrage). The game's icon takes any aura of yours whose spell is the row's
-- own or one of its linked spells (CooldownViewerItemDataMixin's
-- GetAssociatedAuraSpellPriority), unless the row is flagged HideAura
-- (CanUseAuraForDisplay). Bloodrage's own spell puts no aura on you, so the game
-- says hasAura false for it, and its icon still shows the buff: a linked spell.
-- own = by the row's own spell alone, the rule older layouts were saved under.
function A.Follows(id, own)
    if ns.CdmCustom and ns.CdmCustom.Is(id) then return false end   -- custom pieces follow their track
    local info = infoOf(id)
    if not info then return false end
    local flags = plain(info.flags)
    local F = type(_G.Enum) == "table" and _G.Enum.CooldownSetSpellFlags
    local hide = type(F) == "table" and plain(F.HideAura) or 1
    if flags and math.floor(flags / hide) % 2 == 1 then return false end
    if not isSecret(info.hasAura) and info.hasAura == true then return true end
    return own ~= true and linkedAura(info)
end

-- Every one of these spells' auras is never secret (C_Secrets), so a lookup by id
-- answers in a fight as well.
local function neverSecret(ids)
    local get = C_Secrets and C_Secrets.GetSpellAuraSecrecy
    local never = Enum and Enum.SecrecyLevel and Enum.SecrecyLevel.NeverSecret
    if type(get) ~= "function" or never == nil or next(ids) == nil then return false end
    for sid in pairs(ids) do
        local ok, v = pcall(get, sid)
        if not ok or v ~= never then return false end
    end
    return true
end

local function layoutFor(h)
    return { layoutIndex = 1, elementWidth = h.size, elementHeight = h.size, elementSpacing = 0 }
end

-- Dress the button inside initializeFrame, since the client may lock it afterwards.
-- The border sits on a separate box with its own size and one anchor, like CdmBars'
-- iconBox. Anchoring a frame to the client's button by all points came out 0x0 in
-- game, so the shell drew nothing.
local function placeButton(h, btn)
    local parts = h.parts and h.parts[btn]
    if not parts then return end
    local function try(fn, ...) pcall(fn, ...) end
    local size = h.size
    ns.CdmEffects.TuneSlide(btn)
    local T = Pixel.Px(h, Skin.BORDER_PX)
    try(parts.box.ClearAllPoints, parts.box)
    try(parts.box.SetPoint, parts.box, "TOPLEFT", btn, "TOPLEFT", 0, 0)
    try(parts.box.SetSize, parts.box, size, size)
    if parts.shell then
        try(Style.Shell, parts.box)
        try(Skin.PaintCdmShell, parts.shell)
        try(Skin.ShapeCdm, parts, parts.box, parts.shell, parts.icon, { parts.shade }, { parts.cd })
    end
    try(parts.icon.SetTexCoord, parts.icon, Skin.CROP[1], Skin.CROP[2], Skin.CROP[3], Skin.CROP[4])
    try(parts.icon.ClearAllPoints, parts.icon)
    try(parts.icon.SetPoint, parts.icon, "TOPLEFT", btn, "TOPLEFT", T, -T)
    try(parts.icon.SetSize, parts.icon, math.max(1, size - 2 * T), math.max(1, size - 2 * T))
    local t = h.text
    if parts.count then
        try(parts.count.SetFont, parts.count, Style.FONT, t and t.countSize or Skin.COUNT, Style.Outline())
        local cc = t and t.countColor or Skin.COUNT_COLOR
        try(parts.count.SetTextColor, parts.count, cc[1], cc[2], cc[3])
        if t then try(ns.Cooldowns.PlaceCount, parts.count, parts.icon, t.countSpot) end
    end
    if t and parts.cd then try(ns.Cooldowns.StyleNumbers, parts.cd, t) end
    -- The shield amount (A.SetAmount) replaces the countdown.
    if h.amountOn and parts.cd then try(parts.cd.SetHideCountdownNumbers, parts.cd, true) end
    -- Hide duration swipe keeps the countdown text.
    if parts.cd then try(parts.cd.SetDrawSwipe, parts.cd, not h.noSwipe) end
    if parts.cd then try(parts.cd.SetReverse, parts.cd, h.reverse == true) end
end

local function initButton(h, btn)
    local function try(fn, ...) DUI.SafeCall(fn, ...) end
    -- The layout only positions the button. Without a size it stays 0x0.
    try(btn.SetSize, btn, h.size, h.size)
    h.buttons = h.buttons or {}
    h.buttons[#h.buttons + 1] = btn
    local parts = {}
    h.parts = h.parts or {}
    h.parts[btn] = parts
    local box = CreateFrame("Frame", nil, btn)
    parts.box = box
    try(box.SetFrameLevel, box, math.max(0, btn:GetFrameLevel() - 1))
    local s = Style.Shell(box, Skin.ShellOpts())
    -- Kept out of the normal style repaint because the client locks the
    -- button. placeButton repaints it once restrictions lift.
    if s then parts.shell = s; Style.Untrack(s) end
    local icon = btn:CreateTexture(nil, "ARTWORK")
    parts.icon = icon
    try(icon.SetTexCoord, icon, Skin.CROP[1], Skin.CROP[2], Skin.CROP[3], Skin.CROP[4])
    try(btn.SetIcon, btn, icon)
    local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    if cd then
        try(cd.SetAllPoints, cd, icon)
        try(Skin.StyleCooldown, cd)
        try(btn.SetDurationCooldown, btn, cd)
        parts.cd = cd
    end
    local shade = btn:CreateTexture(nil, "ARTWORK", nil, 3)
    parts.shade = shade
    try(shade.SetAllPoints, shade, icon)
    try(shade.SetTexture, shade, Skin.SHADE_FILE)
    try(shade.SetVertexColor, shade, 0, 0, 0, Skin.SHADE)
    local count = btn:CreateFontString(nil, "OVERLAY")
    if count then
        parts.count = count
        -- The client writes the stacks in as it takes the text, so it needs a font first.
        try(count.SetFont, count, Style.FONT, h.text and h.text.countSize or Skin.COUNT, Style.Outline())
        try(count.SetPoint, count, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
        try(btn.SetApplicationCount, btn, count)
    end
    if parts.box then placeButton(h, btn) end
    if btn.SetMouseMotionEnabled then try(btn.SetMouseMotionEnabled, btn, false) end
    ns.CdmEffects.MakeSlide(btn, h)
    if h.anyCaster then A.WatchShown(h, btn) end
end

-- The client plays a button's shown animations as it comes up for an aura and stops
-- them once it has none (ApplyVisibility in Blizzard_CustomAuraButton.lua), in a
-- fight too, while the aura itself and the button's own shown state are secret. An
-- empty looping group handed to it tells whether any of the holder's buttons is up.
local function shownChanged(h, btn, up)
    h.shownButtons = h.shownButtons or {}
    local was = next(h.shownButtons) ~= nil
    h.shownButtons[btn] = up or nil
    if was ~= (next(h.shownButtons) ~= nil) and h.wantsUp and ns.CdmRows then ns.CdmRows.Refresh() end
end

function A.WatchShown(h, btn)
    if type(btn.AddAuraShownAnimation) ~= "function" then return end
    local ag = btn:CreateAnimationGroup()
    local still = ag:CreateAnimation("Translation")
    still:SetOffset(0, 0)
    still:SetDuration(3600)
    ag:SetLooping("REPEAT")
    ag:SetScript("OnPlay", function() shownChanged(h, btn, true) end)
    ag:SetScript("OnStop", function() shownChanged(h, btn, false) end)
    DUI.SafeCall(btn.AddAuraShownAnimation, btn, ag)
end

-- h.layoutFor and h.init let other holders (CdmBars' aura bars) use their own button
-- shape. cand: candidate filters from A.SelfDebuffGroup, else match by spell id.
local function build(h, unit, filter, ids, cand)
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, h, "CustomAuraContainerTemplate")
    if not ok or not c then h.err = tostring(c); return end
    DUI.SafeCall(c.EnableMouse, c, false)
    DUI.SafeCall(c.SetAllPoints, c, h)
    -- One button, from the holder's top left corner.
    local fd = _G.AnchorUtil and _G.AnchorUtil.FlowDirection
    DUI.SafeCall(c.SetFlowLayoutAnchorPoint, c, "TOPLEFT")
    if type(fd) == "table" then DUI.SafeCall(c.SetFlowLayoutGrowthDirection, c, fd.Right, fd.Down) end
    local layout = (h.layoutFor or layoutFor)(h)
    DUI.SafeCall(c.SetFlowLayoutMaximumLineSize, c, layout.elementWidth)
    local SM, SD = _G.AuraContainerSortMethod, _G.AuraContainerSortDirection
    local init = h.init or initButton
    local opts = {
        candidateFilters = cand or { includeSpellIDs = ids },
        maxFrameCount = 1,
        sortMethod = type(SM) == "table" and SM.ExpirationOnly or nil,
        sortDirection = type(SD) == "table" and SD.Normal or nil,
        layout = layout,
        initializeFrame = function(btn) init(h, btn) end,
    }
    local ok2, err = pcall(c.AddAuraGroup, c, "a", filter, opts)
    if not ok2 then h.err = tostring(err); return end
    DUI.SafeCall(c.SetUnit, c, unit)
    DUI.SafeCall(c.SetEnabled, c, true)
    c:Show()
    h.containers[#h.containers + 1] = { c = c, unit = unit, selfDebuff = cand ~= nil or nil, filter = filter,
                                        maxDuration = cand and cand.maxDuration or nil }
end

-- Containers for a spell id: your buffs, then your debuffs on the target, the same
-- order the game scans. Only self auras skip the target, since selfAura false
-- doesn't mean "on the target" (Battle Shout reports false).
local function setup(h, id)
    h.id, h.containers, h.err = id, {}, nil
    h.anyCaster, h.shownButtons = nil, nil
    local C = ns.CdmCustom
    local custom = C ~= nil and C.Is(id)
    -- Custom pieces only build containers out of combat, since it's unclear whether
    -- the client allows creating them mid-fight. They fill in after combat.
    if custom and InCombatLockdown() then
        DUI.AfterCombat(function()
            if h.id == id and #h.containers == 0 then
                DUI.SafeCall(setup, h, id)
                if ns.CdmRows then ns.CdmRows.Refresh() end
            end
        end, "cdm:auras:setup:" .. tostring(h))
        return
    end
    local ids = A.SpellIDs(id)
    h.ids = ids
    -- An aura the game never hides can be read by its id, in a fight too.
    h.neverSecret = neverSecret(ids) or nil
    if custom and C.IsPet(id) then
        -- Your pet isn't an aura: drawn by the addon, up while it's out and alive.
        h.petWatch = true
        makeFace(h)
        A.IsUp(h)
        paintFace(h)
        return
    end
    if custom and C.Weapon(id) then
        -- A weapon enchant isn't an aura either: drawn by the addon from the weapon.
        h.weapon = C.Weapon(id)
        makeFace(h)
        A.IsUp(h)
        paintFace(h)
        return
    end
    local self_
    if custom then
        self_ = C.SelfOnly(id) or nil
    else
        local info = infoOf(id)
        self_ = info and info.selfAura
        if type(self_) ~= "boolean" or isSecret(self_) then self_ = nil end
    end
    -- Self debuffs (Arcane Blast's stack) watch your debuffs, never the target's.
    h.selfDebuff = A.SelfDebuff(id)
    if ns.CdmBars and ns.CdmBars.IsShield(id) then
        -- Shields (Power Word: Shield) show on a friendly target, else on you.
        -- One container whose unit follows the target (A.Retarget).
        build(h, A.ShieldUnit(), "HELPFUL", ids)
        local k = h.containers[#h.containers]
        if k then k.shield = true; h.shieldUnit = k.unit end
        return
    end
    h.trap, h.onPet = A.Trap(id) or nil, A.OnPet(id) or nil
    h.summon, h.summons = A.SummonFacts(id), nil
    if h.summon then
        -- A summoned helper is no aura at all: drawn by the addon, timed from your casts.
        makeFace(h)
        A.IsUp(h)
        paintFace(h)
        return
    end
    if h.selfDebuff then
        -- The client's container shows nothing for a debuff on yourself, whether
        -- matched by spell id (refused on a unit you can assist) or by caster and
        -- duration. So it's drawn by the addon: read by spell id where auras are
        -- plain, counted from your own casts where they aren't.
        h.mineOnly = true
        local facts = A.SelfDebuffFacts(id)
        h.selfFrom = nil
        if facts and type(facts.from) == "table" then
            h.selfFrom = {}
            for _, sid in ipairs(facts.from) do h.selfFrom[sid] = true end
        end
        makeFace(h)
        if A.Readable() then A.IsUp(h) end
        paintFace(h)
        return
    end
    if self_ ~= true and A.Friend(id) then
        -- One container that follows your friendly target (A.Retarget), else
        -- watches you. Only your own cast counts on someone else.
        build(h, A.ShieldUnit(), "HELPFUL|PLAYER", ids)
        local k = h.containers[#h.containers]
        if k then k.follow = true end
        return
    end
    -- Set before the containers exist: the client makes their buttons right away.
    h.anyCaster = A.AnyCaster(id) or nil
    build(h, "player", "HELPFUL", ids)
    if h.onPet then build(h, "pet", "HELPFUL", ids) end
    -- A spell added by ID can also be a debuff on you (Weakened Soul after a
    -- self-shield), so watch your debuffs as well as the target's.
    local added = custom and C.IsAdded(id)
    if added then
        local filter, cand = A.SelfDebuffGroup(id, ids)
        build(h, "player", filter, ids, cand)
        h.mineOnly = filter == "HARMFUL|PLAYER" or nil
    end
    if self_ ~= true then
        h.unique = A.Unique(id) or nil
        build(h, "target", h.unique and "HARMFUL" or "HARMFUL|PLAYER", ids)
    end
end

-- Shield unit: a friendly target, else the player.
function A.ShieldUnit()
    local friend = UnitIsFriend("player", "target")
    if not isSecret(friend) and friend == true then return "target" end
    return "player"
end

A.Setup = setup

-- Other holders with containers (CdmBars' aura bars), retargeted and rebuilt
-- alongside these.
local others = setmetatable({}, { __mode = "k" })
function A.Track(h) others[h] = true end

-- A spell the game's own item draws has no holder. Two things still need its aura
-- ids: finding the game's buff item of the same spell, and the recast glow's clock,
-- which runs on your own casts whoever draws the spell. A watch is that much of a
-- holder and no frame: the ids, and where a read may find the aura.
local watches = {}   -- [id] = watch
local WATCH_UNITS = { { unit = "player" }, { unit = "target" } }
function A.Watch(id)
    local w = watches[id]
    if not w then
        w = { id = id, ids = A.SpellIDs(id), units = WATCH_UNITS, watch = true }
        watches[id] = w
    end
    return w
end

local function each(fn)
    for _, h in pairs(holders) do fn(h) end
    for h in pairs(others) do fn(h) end
    for _, w in pairs(watches) do fn(w) end
end

-- The grayed icon inside its border, using the action bars' border width.
local function placeUnder(h)
    if not h.underBox then return end
    local T = Pixel.Px(h, Skin.BORDER_PX)
    h.under:ClearAllPoints()
    h.under:SetPoint("TOPLEFT", h.underBox, "TOPLEFT", T, -T)
    h.under:SetPoint("BOTTOMRIGHT", h.underBox, "BOTTOMRIGHT", -T, T)
    h.under:SetTexCoord(Skin.CROP[1], Skin.CROP[2], Skin.CROP[3], Skin.CROP[4])
    local s = Style.Shell(h.underBox)
    Skin.PaintCdmShell(s)
    h.underShape = h.underShape or {}
    Skin.ShapeCdm(h.underShape, h.underBox, s, h.under, { h.underShade }, {})
end

-- Holder for an aura piece. always = Show missing buffs: a dim icon shows while
-- the aura is down. size and text: the look it's about to get (A.Resize). The
-- client makes and lays out its buttons the moment the containers exist, and in a
-- fight they can't be laid out again, so they're made at that size, not a guess.
function A.Acquire(id, parent, always, size, text)
    local h = holders[id]
    if not h then
        h = CreateFrame("Frame", nil, parent)
        h.size, h.text = size or 36, text
        -- Grayed icon with the same border and shade as the live button.
        h.underBox = CreateFrame("Frame", nil, h)
        h.underBox:SetAllPoints(h)
        Style.Shell(h.underBox, Skin.ShellOpts())
        h.under = h.underBox:CreateTexture(nil, "ARTWORK")
        h.under:SetDesaturated(true)
        h.under:SetAlpha(0.35)
        h.under:SetTexCoord(Skin.CROP[1], Skin.CROP[2], Skin.CROP[3], Skin.CROP[4])
        h.underShade = h.underBox:CreateTexture(nil, "ARTWORK", nil, 3)
        h.underShade:SetAllPoints(h.under)
        h.underShade:SetTexture(Skin.SHADE_FILE)
        h.underShade:SetVertexColor(0, 0, 0, Skin.SHADE)
        placeUnder(h)
        holders[id] = h
        DUI.SafeCall(setup, h, id)
    elseif h:GetParent() ~= parent then
        h:SetParent(parent)
    end
    if not h.sid then
        local sid = ns.CdmOwn and ns.CdmOwn.SpellOf(id)
        -- Custom pieces may have their own icon (the seal), else the spell's.
        local C = ns.CdmCustom
        local tex = C and C.Is(id) and select(2, C.Look(id))
        if type(tex) == "nil" or tex == false then
            tex = sid and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
        end
        if type(tex) ~= "nil" then
            h.sid = sid
            h.under:SetTexture(tex)
            if h.face then h.face.icon:SetTexture(tex) end
        end
    end
    -- The grayed icon only shows with Show missing buffs. While the aura is up
    -- the client's button covers it.
    h.under:SetShown(always == true)
    h.underBox:SetShown(always == true)
    h.underOn = always == true
    h.overIcon = false   -- set by A.Over
    for _, k in ipairs(h.containers) do DUI.SafeCall(k.c.SetEnabled, k.c, true) end
    h:Show()
    return h
end

-- Cooldown and buff mode: the holder sits over the cooldown icon with no underlay.
-- The buff covers the icon while up and the cooldown shows once it's gone.
function A.Over(h, icon, size, text)
    h.under:Hide()
    h.underBox:Hide()
    h.underOn = false
    h.overIcon = true    -- buff fades in over the icon without the drop (Fx.TuneSlide)
    -- Anchor to the icon's parent, not the icon. Fx.Dip resizes the icon when it
    -- goes on cooldown, and the locked client button just slid along with it.
    local spot = icon:GetParent() or icon
    h:ClearAllPoints()
    h:SetPoint("CENTER", spot, "CENTER", 0, 0)
    h:SetSize(size, size)
    h:SetFrameLevel(icon:GetFrameLevel() + 10)
    A.Resize(h, size, text)
end

-- Last layout values per holder in h.look, so an unchanged pass allocates nothing.
local lookNow = {}
local function sameLook(h, size, text)
    local L = lookNow
    L[1], L[2], L[3], L[4], L[5], L[6] = size, Skin.BORDER_PX, Skin.COUNT, Style.FONT, Skin.cdmGen, text ~= nil
    L[7] = h.overIcon == true
    local n = 7
    if text then
        L[8], L[9], L[10], L[11] = text.numbers, text.cdSize, text.countSize, text.countSpot
        L[12], L[13], L[14] = text.cdColor[1], text.cdColor[2], text.cdColor[3]
        L[15], L[16], L[17] = text.countColor[1], text.countColor[2], text.countColor[3]
        n = 17
    end
    local old = h.look
    local same = type(old) == "table" and old.n == n
    if same then
        for i = 1, n do if old[i] ~= L[i] then same = false; break end end
    end
    if same then return true end
    old = type(old) == "table" and old or {}
    for i = 1, n do old[i] = L[i] end
    old.n = n
    h.look = old
    return false
end

-- Size, border or count settings changed: update the containers and re-place the
-- buttons. Rows sizes the holder itself. text: the piece's icon text
-- (Cooldowns.CD.TextLook), or nil for the action bars' default.
function A.Resize(h, size, text)
    if sameLook(h, size, text) then return end
    h.size, h.text = size, text
    placeUnder(h)
    placeFace(h)
    -- Client aura buttons are locked while auras are secret (combat, PvP
    -- matches, boss fights), so resize them once that lifts.
    DUI.AfterRestrictions(function()
        for _, btn in ipairs(h.buttons or {}) do
            pcall(btn.SetSize, btn, h.size, h.size)
            placeButton(h, btn)
        end
    end, "cdm:auras:" .. tostring(h))
    for _, k in ipairs(h.containers or {}) do
        DUI.SafeCall(k.c.SetAuraGroupLayout, k.c, "a", layoutFor(h))
        DUI.SafeCall(k.c.SetFlowLayoutMaximumLineSize, k.c, size)
    end
end

function A.Frame(id) return holders[id] end

-- Show shield amount: the remaining absorb as a number instead of the time.
-- UnitGetTotalAbsorbs is always secret, so it's only drawn. A 0-1 gate bar whose
-- fill clips the text hides the number when there's no shield (same trick as
-- CdmBars' shield bar).
function A.UpdateShield(h)
    if not (h.amountOn and h.amount) then return end
    local v = UnitGetTotalAbsorbs(h.shieldUnit or "player")
    if type(v) == "nil" then return end
    h.amount.text:SetText(AbbreviateNumbers(v))
    h.amount:SetValue(v)
end

local function makeAmount(h)
    local g = CreateFrame("StatusBar", nil, h)
    g:SetAllPoints(h)
    g:SetStatusBarTexture(Style.BarFile("fill"))
    g:GetStatusBarTexture():SetAlpha(0)
    g:SetMinMaxValues(0, 1)
    g:SetValue(0)
    local clip = CreateFrame("Frame", nil, g)
    clip:SetClipsChildren(true)
    clip:SetAllPoints(g:GetStatusBarTexture())
    g.text = clip:CreateFontString(nil, "OVERLAY")
    g.text:SetPoint("CENTER", h, "CENTER", 0, 0)
    h.amount = g
end

-- Re-dress the client's buttons once restrictions lift.
local function replace(h)
    DUI.AfterRestrictions(function()
        for _, btn in ipairs(h.buttons or {}) do placeButton(h, btn) end
    end, "cdm:auras:place:" .. tostring(h))
end

-- on: Show shield amount for a shield piece. text: the piece's icon text settings.
function A.SetAmount(h, on, text)
    on = on == true and h.shieldUnit ~= nil
    if on and not h.amount then makeAmount(h) end
    if h.amount then
        h.amount:SetShown(on)
        if on then
            -- Above the client's button.
            h.amount:SetFrameLevel(h:GetFrameLevel() + 20)
            local t = text or h.text
            h.amount.text:SetFont(Style.FONT, t and t.cdSize or Skin.COUNT, Style.Outline())
            local c = t and t.cdColor or Style.INK.VALUE
            h.amount.text:SetTextColor(c[1], c[2], c[3])
        end
    end
    if (h.amountOn or false) == on then
        if on then A.UpdateShield(h) end
        return
    end
    h.amountOn = on or nil
    replace(h)
    if on then A.UpdateShield(h) end
end

-- The piece's Hide duration swipe and Reverse swipe settings.
function A.SetSwipe(h, hide, reverse)
    hide, reverse = hide == true or nil, reverse == true or nil
    if h.noSwipe == hide and h.reverse == reverse then return end
    h.noSwipe, h.reverse = hide, reverse
    replace(h)
    placeFace(h)
end

-- Hide (Buff up). The container goes transparent so the client's button never
-- shows, however combat reads the aura. Keep its spot's grayed icon shows only
-- while the aura is down.
function A.SetHideUp(h, on)
    on = on == true or nil
    if h.hideUp ~= on then
        h.hideUp = on
        for _, k in ipairs(h.containers or {}) do DUI.SafeCall(k.c.SetAlpha, k.c, on and 0 or 1) end
        paintFace(h)
    end
    if ns.Cooldowns then ns.Cooldowns.FollowHide(h) end
    if not h.underOn then return end
    -- With Hide (Buff up) and Show missing buffs, the icon is a reminder that the
    -- buff is missing (Righteous Fury), so it shows in full color instead of gray.
    if h.underBright ~= on then
        h.underBright = on
        h.under:SetDesaturated(not on)
        local from, to = on and 0.35 or 1, on and 1 or 0.35
        Motion.Tween(h.under, from, to, Motion.FAST, function(v) h.under:SetAlpha(v) end)
    end
    local a = on and h.up == true and 0 or 1
    if h.underAlpha == a then return end
    local from = h.underAlpha or a
    h.underAlpha = a
    Motion.Tween(h.underBox, from, a, Motion.FAST, function(v) h.underBox:SetAlpha(v) end)
end

-- Whether the holder's aura is up: true, false, or nil if never known. Spell id
-- lookups only work outside combat and restrictions. Inside, they quietly return
-- nothing, so only a found aura counts and otherwise the last answer stands.
local function readable()
    if DUI.Restricted() then return false end
    local S = C_Secrets
    if S and type(S.ShouldAurasBeSecret) == "function" then
        local yes = S.ShouldAurasBeSecret()
        if isSecret(yes) or yes == true then return false end
    end
    return true
end

A.Readable = readable   -- /dui cdm report

-- Self-debuff face (h.selfDebuff): looks like the client's button but built from
-- addon frames, so it's never locked. Driven by h.up, h.endsAt, h.auraLasts and
-- h.selfStacks, read where plain or counted from your casts (selfCast).
function makeFace(h)
    if h.face then return end
    if h.ownBar == "aura" then
        -- An aura bar (CdmBars) draws it as a bar, laid out with the bar.
        h.face = ns.CdmBars.MakeFace(h)
        placeFace(h)
        return
    end
    local f = CreateFrame("Frame", nil, h)
    f:SetAllPoints(h)
    f:SetFrameLevel(h:GetFrameLevel() + 2)
    f:SetAlpha(0)
    f.box = CreateFrame("Frame", nil, f)
    f.box:SetAllPoints(f)
    f.shell = Style.Shell(f.box, Skin.ShellOpts())
    f.icon = f.box:CreateTexture(nil, "ARTWORK")
    f.cd = CreateFrame("Cooldown", nil, f.box, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f.icon)
    Skin.StyleCooldown(f.cd)
    f.shade = f.box:CreateTexture(nil, "ARTWORK", nil, 3)
    f.shade:SetAllPoints(f.icon)
    f.shade:SetTexture(Skin.SHADE_FILE)
    f.shade:SetVertexColor(0, 0, 0, Skin.SHADE)
    -- Stack count above the swipe.
    f.top = CreateFrame("Frame", nil, f.box)
    f.top:SetAllPoints(f.box)
    f.top:SetFrameLevel(f.cd:GetFrameLevel() + 1)
    f.count = f.top:CreateFontString(nil, "OVERLAY")
    f.count:SetPoint("BOTTOMRIGHT", f.icon, "BOTTOMRIGHT", -1, 1)
    f.shape = {}
    function f.SetTime(start, dur)
        if start then f.cd:SetCooldown(start, dur) else f.cd:Clear() end
    end
    h.face = f
    local tex = h.under and h.under:GetTexture()
    if type(tex) ~= "nil" then f.icon:SetTexture(tex) end
    placeFace(h)
end

-- placeButton's equivalent for the self-debuff face.
function placeFace(h)
    local f = h.face
    if not f then return end
    if f.parts then return ns.CdmBars.LayoutFace(h) end
    local size = h.size
    local T = Pixel.Px(h, Skin.BORDER_PX)
    Style.Shell(f.box)
    Skin.PaintCdmShell(f.shell)
    Skin.ShapeCdm(f.shape, f.box, f.shell, f.icon, { f.shade }, { f.cd })
    f.icon:SetTexCoord(Skin.CROP[1], Skin.CROP[2], Skin.CROP[3], Skin.CROP[4])
    f.icon:ClearAllPoints()
    f.icon:SetPoint("TOPLEFT", f.box, "TOPLEFT", T, -T)
    f.icon:SetSize(math.max(1, size - 2 * T), math.max(1, size - 2 * T))
    local t = h.text
    f.count:SetFont(Style.FONT, t and t.countSize or Skin.COUNT, Style.Outline())
    local cc = t and t.countColor or Skin.COUNT_COLOR
    f.count:SetTextColor(cc[1], cc[2], cc[3])
    if t then ns.Cooldowns.PlaceCount(f.count, f.icon, t.countSpot) end
    if t then ns.Cooldowns.StyleNumbers(f.cd, t) end
    f.cd:SetDrawSwipe(not h.noSwipe)
    f.cd:SetReverse(h.reverse == true)
end

-- The game takes a debuff on you off a moment after its time runs out, and a cast
-- landing in that moment still adds to the old stack. So a counted self debuff
-- stays this long past its end before it counts as gone.
A.SELF_LATE = 1

-- When the holder's aura is gone: its end, plus SELF_LATE for a counted self debuff.
local function goneAt(h)
    if not h.endsAt then return nil end
    return h.selfDebuff and h.endsAt + A.SELF_LATE or h.endsAt
end

-- Show state, time and stacks. Fades use FAST so combat info isn't delayed.
-- Hide (Buff up) keeps it hidden while up.
function paintFace(h)
    local f = h.face
    if not f then return end
    local now = GetTime()
    local up = h.up == true and (h.endsAt == nil or goneAt(h) > now)
    if up then
        local dur = h.auraLasts
        if h.endsAt and dur and dur > 0 then
            if f.shownEnd ~= h.endsAt then
                f.shownEnd = h.endsAt
                f.SetTime(h.endsAt - dur, dur)
            end
        elseif f.shownEnd then
            f.shownEnd = nil
            f.SetTime(nil)
        end
        local n = h.selfStacks
        f.count:SetText(n and n > 1 and tostring(n) or "")
        local icon = h.weapon and h.weaponIcon
        if type(icon) ~= "nil" and icon ~= false and f.shownIcon ~= icon then
            f.shownIcon = icon
            local tex = f.icon or (f.parts and f.parts.icon)
            if tex then tex:SetTexture(icon) end
            if h.under then h.under:SetTexture(icon) end
        end
    end
    local a = (up and not h.hideUp) and 1 or 0
    if f.alphaTo == a then return end
    local from = f:GetAlpha()
    f.alphaTo = a
    Motion.Tween(f, from, a, Motion.FAST, function(v) f:SetAlpha(v) end)
end

-- One timer per holder for the end it knows: a counted debuff's or summon's time,
-- or the recast glow's. A later end keeps it waiting.
local function watchEnd(h)
    if h.endTimer or not h.endsAt then return end
    h.endTimer = true
    C_Timer.After(math.max(0, goneAt(h) - GetTime()) + 0.05, function()
        h.endTimer = nil
        if not h.endsAt then return end
        if GetTime() < goneAt(h) then return watchEnd(h) end
        h.endsAt = nil
        local was = h.up
        if h.face then A.IsUp(h) end
        paintFace(h)
        if h.up ~= was and h.wantsUp and ns.CdmRows then ns.CdmRows.Refresh() end
    end)
end

-- Debuffs on you (Weakened Soul, Arcane Blast's stack). Containers refuse to match
-- a debuff on an assistable unit by spell id unless the spell is never secret
-- (AuraContainerUtil.CanApplyIdentityCandidateFilters). So match any debuff of
-- yours no longer than the spell's duration (from the game's data, else
-- A.SELF_DEBUFF_CAP seconds). Returns the group filter and candidate filters.
A.SELF_DEBUFF_CAP = 30
function A.SelfDebuffGroup(id, ids)
    ids = ids or {}
    if neverSecret(ids) then return "HARMFUL", { includeSpellIDs = ids } end
    local n
    for sid in pairs(ids) do
        local fact = ns.CdmCustom and ns.CdmCustom.Fact(sid)
        n = fact and fact.lasts
        if n then break end
    end
    return "HARMFUL|PLAYER", { maxDuration = n and (math.ceil(n) + 1) or A.SELF_DEBUFF_CAP }
end

-- A found aura's stacks, length and end: a counted debuff's face shows them, and
-- the recast glow needs the end.
local function learn(h, a)
    local n = plain(a.applications)
    if h.selfDebuff then
        -- Read by id, so its going says it's down (a debuff that never stacks has no count).
        h.selfRead = true
        if n then
            h.selfStacks = n
            if n > (h.selfMax or 0) then h.selfMax = n end
        end
    end
    local dur, ends = plain(a.duration), plain(a.expirationTime)
    if not dur then return end
    h.auraLasts = dur
    h.endsAt = dur > 0 and ends or nil
    watchEnd(h)
end

local ON_YOU = { { unit = "player" } }   -- self debuffs have no container (makeFace)
local function found(h)
    local get = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
    if type(get) ~= "function" or type(h.ids) ~= "table" then return false end
    for _, k in ipairs(h.selfDebuff and ON_YOU or h.units or h.containers or {}) do
        for sid in pairs(h.ids) do
            local ok, a = pcall(get, k.unit, sid)
            -- On the target, only your own debuff counts (HARMFUL|PLAYER), unless
            -- the target carries one copy whoever cast it (h.unique).
            local fromOther = not isSecret(a and a.isFromPlayerOrPlayerPet)
                and type(a) == "table" and a.isFromPlayerOrPlayerPet == false
            -- On you, someone else's debuff isn't shown by the HARMFUL|PLAYER group,
            -- so counting it would leave an empty spot.
            local otherDebuff = h.mineOnly and fromOther and type(a) == "table" and a.isHarmful == true
            if ok and type(a) == "table" and not otherDebuff and (k.unit == "player" or not fromOther or h.unique) then
                learn(h, a)
                return true
            end
        end
    end
    return false
end

-- For /dui cdm report: what the holder watches, what the client put in it, and
-- what the game says about each spell id on you (only readable out of combat).
function A.Why(h)
    local function w(v)
        if isSecret(v) then return "secret" end
        return tostring(v)
    end
    local parts = {}
    for _, k in ipairs(h.containers or {}) do
        local okN, n = pcall(k.c.GetAuraGroupFrameCount, k.c, "a")
        parts[#parts + 1] = string.format("%s %s%s, buttons %s", w(k.unit), w(k.filter),
            k.maxDuration and (" up to " .. w(k.maxDuration) .. " s") or "", okN and w(n) or "?")
    end
    local ids = {}
    for sid in pairs(h.ids or {}) do ids[#ids + 1] = sid end
    table.sort(ids)
    local on = {}
    local get = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
    if type(get) == "function" then
        for _, sid in ipairs(ids) do
            local ok, a = pcall(get, "player", sid)
            if ok and type(a) == "table" then
                on[#on + 1] = string.format("%d on you (harmful %s, from %s, lasts %s, stacks %s)", sid,
                    w(a.isHarmful), w(a.sourceUnit), w(a.duration), w(a.applications))
            end
        end
    end
    local face = h.face and string.format("drawn by ours (alpha %s, stacks %s, ends in %s)", w(h.face.alphaTo),
        w(h.selfStacks), h.endsAt and string.format("%.1f", h.endsAt - GetTime()) or "-")
    return string.format("watches %s; ids %s%s; %s", face or table.concat(parts, ", "),
        table.concat(ids, ","), h.err and (", err " .. w(h.err)) or "",
        #on > 0 and table.concat(on, "; ") or "none of them on you")
end

-- Your pet is out and alive. Neither answer is secret, in a fight too.
function A.PetOut()
    local yes = UnitExists("pet")
    if isSecret(yes) or yes ~= true then return false end
    local dead = UnitIsDead("pet")
    return not (not isSecret(dead) and dead == true)
end

-- A weapon piece's enchant, read again: up while there is one, its time and charges.
-- The client gives only the time left, so the full length is the time left when it
-- was put on (a new enchant, or one that now ends later than before).
local function readWeapon(h)
    local list, refused = DUI.Weapons.Read(h.weapon.slot, h.weaponRead)
    h.weaponRead = list
    if refused then return h.up end
    local e = list[1]
    if not e then
        h.up, h.endsAt, h.selfStacks, h.weaponID = false, nil, nil, nil
        return false
    end
    local now = GetTime()
    local ends = e.msLeft > 0 and now + e.msLeft / 1000 or nil
    if ends and (h.weaponID ~= e.enchantID or not h.auraLasts or not h.endsAt or ends > h.endsAt + 1) then
        h.auraLasts = e.msLeft / 1000
    end
    h.up, h.endsAt, h.weaponID = true, ends, e.enchantID
    h.selfStacks = e.charges > 0 and e.charges or nil
    h.weaponIcon = e.icon
    watchEnd(h)
    return true
end

-- Whether the holder's aura is up, for the few holders that can say so themselves:
-- the pet piece, a weapon enchant, the pieces counted from your own casts, and an
-- aura the game never hides (read by its id, in a fight too). Every other buff is the game's own item's
-- to answer (CdmRows); without one nobody knows, and this returns nil.
function A.IsUp(h)
    if type(h) ~= "table" then return nil end
    if h.petWatch then
        h.up = A.PetOut()
        return h.up
    end
    if h.weapon then return readWeapon(h) end
    if h.summon then
        -- Each helper leaves when its own time runs out.
        local now, left, newest = GetTime(), {}, nil
        for _, e in ipairs(h.summons or {}) do
            if e > now then
                left[#left + 1] = e
                if not newest or e > newest then newest = e end
            end
        end
        h.summons = left
        h.up, h.endsAt = #left > 0, newest
        h.selfStacks = #left > 0 and #left or nil
        return h.up
    end
    if h.selfDebuff then
        if found(h) then
            h.up, h.castAt = true, nil
        elseif not (h.endsAt and goneAt(h) > GetTime()) or (h.selfRead and readable()) then
            -- Not finding it by id means nothing, since Arcane Blast's stack can't be
            -- tracked that way in game. It's down once the counted time runs out, or
            -- when it was found before and is now gone where auras can be read.
            h.up, h.endsAt, h.selfStacks, h.selfRead = false, nil, nil, nil
        end
        return h.up
    end
    if h.anyCaster and not h.neverSecret then
        -- Anyone's copy counts: read where auras are plain, else whether the
        -- client's button for it is up.
        if readable() then h.up = found(h) else h.up = next(h.shownButtons or {}) ~= nil end
        return h.up
    end
    if not h.neverSecret then return nil end
    h.up = found(h)
    return h.up
end

-- Whether the holder can tell by itself if it's up, in a fight too (A.IsUp).
function A.Knows(h)
    return type(h) == "table" and (h.face ~= nil or h.neverSecret == true or h.anyCaster == true)
end

-- The aura read straight off the unit: true or false where auras read plainly,
-- nil in a fight or under the client's restrictions. For a buff whose game icon
-- sits in a row the game shows only in combat, while out of one.
function A.Read(h)
    if type(h) ~= "table" or not readable() then return nil end
    h.up = found(h)
    return h.up
end

-- A buff changed. Holders that care whether they're up (h.wantsUp, set by CdmRows)
-- check again, and any change runs the layout pass.
function A.AuraChanged()
    local moved = false
    each(function(h)
        if h.face and h:IsShown() then
            -- Self-debuff faces always update, including time and stacks.
            local was = h.up
            if readable() or h.petWatch or h.weapon then
                A.IsUp(h)
            elseif h.castAt then
                -- Cast while auras could still be read and not seen landing before
                -- the fight hid them (the pull): count it now.
                local sid, at = h.castSpell, h.castAt
                h.castSpell, h.castAt = nil, nil
                if GetTime() - at <= A.CAST_LANDS then selfCast(h, sid) end
            end
            paintFace(h)
            if h.wantsUp and h.up ~= was then moved = true end
        elseif h.wantsUp and (h.neverSecret or h.anyCaster) and h:IsShown() then
            local was = h.up
            if A.IsUp(h) ~= was then moved = true end
        elseif h.reads and readable() then
            -- No game icon answers for it, so the aura itself is the word.
            local was = h.up
            if A.Read(h) ~= was then moved = true end
        end
    end)
    if moved and ns.CdmRows then ns.CdmRows.Refresh() end
    -- An aura read where it's plain gives the recast glow its real end.
    if A.ClipCheck then A.ClipCheck() end
end

-- Coalesce bursts of UNIT_AURA (pre-pull rebuffs, raid fights) into one pass
-- on the next frame.
A.AuraChangedSoon = DUI.Soon(function() DUI.SafeCall(A.AuraChanged) end)

-- How long after a cast its aura may still land: a spell's flight time.
A.CAST_LANDS = 3

-- Glow to recast is the one thing still worked out from your own cast: in a fight
-- the game never says when an aura ends. The length is the one last read, else the
-- game's data; a read where auras are plain replaces the end (learn).
local function castClock(h, sid)
    local fact = ns.CdmCustom and ns.CdmCustom.Fact(sid)
    local lasts = h.auraLasts or (fact and fact.lasts)
    h.endsAt = lasts and lasts > 0 and GetTime() + lasts or nil
    watchEnd(h)
end

-- Count casts of a spell whose debuff lands on you (Arcane Blast), since the stack
-- can't be tracked by spell id. The first cast starts the timer and each later one
-- adds a stack. The duration runs from the first application, so recasts don't
-- extend it. Dying clears it.
selfCast = function(h, sid)
    -- If it was just read by id, trust the read over the count. The aura event
    -- can arrive before the cast and would be counted twice. The cast is kept in
    -- case the fight it starts hides the aura before it's read (A.AuraChanged).
    if h.selfRead and readable() then
        h.castSpell, h.castAt = sid, GetTime()
        A.AuraChangedSoon()
        return
    end
    local now = GetTime()
    local facts = A.SelfDebuffFacts(h.id) or {}
    local fact = ns.CdmCustom and ns.CdmCustom.Fact(sid)
    h.auraLasts = h.auraLasts or facts.lasts or (fact and fact.lasts)
    if h.up == true and h.endsAt and goneAt(h) > now then
        local cap = facts.stacks or h.selfMax or (fact and fact.stacks)
        local n = (h.selfStacks or 1) + 1
        h.selfStacks = cap and math.min(n, cap) or n
    else
        h.up, h.selfStacks = true, 1
        h.endsAt = h.auraLasts and h.auraLasts > 0 and now + h.auraLasts or nil
        watchEnd(h)
    end
    paintFace(h)
    if ns.CdmRows then ns.CdmRows.Refresh() end
end

-- A summon (Summon Hawk): each cast brings one more helper for its own time, the
-- oldest leaving once there are as many as the game allows. Your casts stay plain
-- in a fight, so this works anywhere.
local function summonCast(h)
    local facts, now = h.summon, GetTime()
    local lasts = facts.lasts or 0
    if lasts <= 0 then return end
    local list = {}
    for _, e in ipairs(h.summons or {}) do if e > now then list[#list + 1] = e end end
    table.sort(list)
    list[#list + 1] = now + lasts
    while facts.most and #list > facts.most do table.remove(list, 1) end
    h.summons, h.auraLasts = list, lasts
    -- Each helper leaving changes the count, so look again when this one goes.
    local ends = now + lasts
    local function gone()
        if not h.summons then return end
        if GetTime() < ends then
            C_Timer.After(ends - GetTime() + 0.05, gone)
            return
        end
        local was, count = h.up, h.selfStacks
        A.IsUp(h)
        paintFace(h)
        if (h.up ~= was or h.selfStacks ~= count) and h.wantsUp and ns.CdmRows then ns.CdmRows.Refresh() end
    end
    C_Timer.After(lasts + 0.05, gone)
    A.IsUp(h)
    paintFace(h)
    if ns.CdmRows then ns.CdmRows.Refresh() end
end

local casts = CreateFrame("Frame")
casts:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
casts:SetScript("OnEvent", function(_, _, _, _, sid)
    if type(sid) ~= "number" or isSecret(sid) then return end
    each(function(h)
        -- Laying a trap down puts nothing up: its debuff comes when a mob walks in.
        if h.selfFrom and h.selfFrom[sid] and h.face and A.ShieldUnit() == "player" then
            -- Another spell puts this debuff on you (Weakened Soul from your own
            -- shield), so count it under the debuff's own id.
            selfCast(h, next(h.ids))
        elseif type(h.ids) == "table" and h.ids[sid] and not h.trap then
            if h.summon then
                summonCast(h)
            elseif h.face then
                selfCast(h, sid)
            elseif h.wantsClip then
                castClock(h, sid)
            end
        end
    end)
end)

DUI.RegisterEvent("PLAYER_DEAD", function()
    each(function(h)
        if h.face and h.up == true then
            h.up, h.endsAt, h.selfStacks, h.summons = false, nil, nil, nil
            paintFace(h)
            if h.wantsUp and ns.CdmRows then ns.CdmRows.Refresh() end
        end
    end)
end)

-- Recast glow. On WoW Forever an aura cast again before it runs out loses the time
-- it had left (a damage over time spell loses its remaining ticks), so the moment to
-- cast it again is when that cast would land just as the old one ends. Your own
-- casts stay plain in a fight, so it's worked out from them and the clock alone:
-- when you're free (your current cast or channel, then the global cooldown) plus the
-- spell's cast time, against the end a read or your cast's clock gave the holder.
A.GCD = 1.5
local castEnd, castSpell, gcdEnd, gcdLen = 0, nil, 0, A.GCD
local offGcd = {}      -- [spell id] = true for a spell seen to start no global cooldown
local castTimes = {}   -- [spell id] = cast time in seconds

local function castTime(sid)
    local c = castTimes[sid]
    if c then return c end
    local ok, info = pcall(C_Spell.GetSpellInfo, sid)
    local ms = ok and type(info) == "table" and plain(info.castTime) or nil
    c = ms and ms > 0 and ms / 1000 or 0
    castTimes[sid] = c
    return c
end

local function readCast()
    local _, _, _, _, e, _, _, _, sid = UnitCastingInfo("player")
    if not plain(e) then
        _, _, _, _, e, _, _, sid = UnitChannelInfo("player")
    end
    if plain(e) then
        castEnd, castSpell = e / 1000, plain(sid)
    else
        castEnd, castSpell = 0, nil
    end
end

-- A cast or channel just started the global cooldown. Its times read secret in a
-- fight, so its length is the last one read, and a spell once seen to start none
-- never does.
local function startGcd(sid)
    if offGcd[sid] then return end
    local ok, cd = pcall(C_Spell.GetSpellCooldown, sid)
    if ok and type(cd) == "table" then
        local s, d = plain(cd.startTime), plain(cd.duration)
        local g = cd.isOnGCD
        if isSecret(g) then g = nil end
        if g == true and s and d and d > 0 then
            gcdLen, gcdEnd = d, s + d
            return
        end
        if g ~= true and d == 0 then offGcd[sid] = true; return end
    end
    gcdEnd = GetTime() + gcdLen
end

-- Whether it's time to cast sid again for the aura on holder h, and if not yet,
-- when it will be (given what you're doing now).
function A.ClipDue(h, sid)
    if type(h) ~= "table" or h.up == false or type(sid) ~= "number" then return false end
    if readable() and not found(h) then return false end
    local now, ends = GetTime(), h.endsAt
    if not ends or ends <= now then return false end
    -- Already casting it: that cast is the refresh.
    if castSpell and castEnd > now and (castSpell == sid or nameOf(castSpell) == nameOf(sid)) then return false end
    local at = ends - castTime(sid)
    if at <= math.max(now, castEnd, gcdEnd) then return true end
    return false, at
end

-- Holders with the recast glow, told by each pass: [holder] = { sid, due }.
local clipWatch = setmetatable({}, { __mode = "k" })
local wakeAt = math.huge
local clipCheck

-- One timer, for the soonest answer that will change. An earlier one replaces it.
local function schedule(at)
    if at >= wakeAt then return end
    wakeAt = at
    local function fire()
        if wakeAt ~= at then return end
        if GetTime() + 0.01 < at then
            C_Timer.After(at - GetTime() + 0.02, fire)
            return
        end
        wakeAt = math.huge
        clipCheck()
    end
    C_Timer.After(math.max(0, at - GetTime()) + 0.02, fire)
end

-- Only a holder whose answer changed asks for a pass.
clipCheck = function()
    for h, w in pairs(clipWatch) do
        local due, at = A.ClipDue(h, w.sid)
        if at then schedule(at) end
        if due ~= w.due then
            if ns.CdmRows then ns.CdmRows.Refresh() end
            return
        end
    end
end

A.ClipCheck = function() if next(clipWatch) ~= nil then clipCheck() end end

function A.ClipPass()
    for h in pairs(clipWatch) do clipWatch[h] = nil end
    -- A watch only keeps a clock while the pass asks for one.
    for _, w in pairs(watches) do w.wantsClip = nil end
end

-- From the pass: the recast glow's answer for this holder now.
function A.Clip(h, sid)
    local due, at = A.ClipDue(h, sid)
    clipWatch[h] = { sid = sid, due = due }
    if at then schedule(at) end
    return due
end

local clipCasts = CreateFrame("Frame")
for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELL_HASTE" }) do
    clipCasts:RegisterUnitEvent(e, "player")
end
for _, e in ipairs({ "SPELLS_CHANGED", "PLAYER_EQUIPMENT_CHANGED" }) do clipCasts:RegisterEvent(e) end
clipCasts:SetScript("OnEvent", function(_, event, _, _, sid)
    if event == "UNIT_SPELL_HASTE" or event == "SPELLS_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" then
        for k in pairs(castTimes) do castTimes[k] = nil end
        return
    end
    if next(clipWatch) == nil then return end
    sid = plain(sid)
    readCast()
    -- A cast with a cast time started the global cooldown as it began; an instant
    -- does as it goes off.
    if sid and (event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START"
        or (event == "UNIT_SPELLCAST_SUCCEEDED" and castTime(sid) == 0 and castEnd <= GetTime())) then
        startGcd(sid)
    end
    clipCheck()
end)

-- From CdmRows: what the game's own item for this buff says, up or down, and that's
-- final. nil = there's no such item and the holder can't tell either.
function A.Told(h, up)
    h.up = up
    if up == false then h.endsAt = nil end
end

function A.ReleaseExcept(used)
    for id, h in pairs(holders) do
        if not used[id] and h:IsShown() then
            h:Hide()
            for _, k in ipairs(h.containers) do DUI.SafeCall(k.c.SetEnabled, k.c, false) end
        end
    end
end

-- New target. Containers follow it on their own; this extra refresh is harmless.
function A.Retarget()
    each(function(h)
        for _, k in ipairs(h.containers or {}) do
            -- Same unit token, new unit. The container only re-reads on an aura
            -- change or when told.
            if k.shield or k.follow then
                -- Still on you (enemy or no target): leave it alone, or the
                -- client rebuilds its button and the bar flashes.
                local unit = A.ShieldUnit()
                if not (unit == "player" and k.unit == "player") then
                    k.unit = unit
                    DUI.SafeCall(k.c.SetUnit, k.c, k.unit)
                    DUI.SafeCall(k.c.UpdateAllAuras, k.c)
                    if k.shield then
                        if ns.CdmBars then ns.CdmBars.Retarget(h, k.unit) end
                        if holders[h.id] == h then h.shieldUnit = k.unit; A.UpdateShield(h) end
                    end
                end
            elseif k.unit == "target" then
                DUI.SafeCall(k.c.SetUnit, k.c, "target")
                DUI.SafeCall(k.c.UpdateAllAuras, k.c)
            end
        end
    end)
end

local function sameIDs(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k in pairs(a) do if not b[k] then return false end end
    for k in pairs(b) do if not a[k] then return false end end
    return true
end

-- Spells changed, so ranks may have too. SPELLS_CHANGED comes often, and new
-- filters make the client hand every button its aura again, which replays the
-- slide-in, so they're only sent when the ids really changed.
function A.Rebuild()
    each(function(h)
        if h.watch then
            h.ids = A.SpellIDs(h.id)
        elseif not InCombatLockdown() and h.containers and h.id then
            local ids = A.SpellIDs(h.id)
            if sameIDs(ids, h.ids) then return end
            h.ids = ids
            for _, k in ipairs(h.containers) do
                local filters = { includeSpellIDs = h.ids }
                if k.selfDebuff then filters = select(2, A.SelfDebuffGroup(h.id, h.ids)) end
                DUI.SafeCall(k.c.SetAuraGroupCandidateFilters, k.c, "a", filters)
            end
        end
    end)
end

-- The pet came, went or died: pet pieces show it at once.
function A.PetChanged(newPet)
    local moved = false
    each(function(h)
        if h.petWatch then
            local was = h.up
            A.IsUp(h)
            paintFace(h)
            if h.up ~= was then moved = true end
        end
        -- Same unit token, maybe a new pet: the container reads it again when told.
        for _, k in ipairs(newPet and h.containers or {}) do
            if k.unit == "pet" then
                DUI.SafeCall(k.c.SetUnit, k.c, "pet")
                DUI.SafeCall(k.c.UpdateAllAuras, k.c)
            end
        end
    end)
    if moved and ns.CdmRows then ns.CdmRows.Refresh() end
end

-- A weapon enchant went on, came off, lost a charge or the weapon changed.
function A.WeaponsChanged()
    local moved = false
    each(function(h)
        if h.weapon then
            local was, count = h.up, h.selfStacks
            A.IsUp(h)
            paintFace(h)
            if h.up ~= was or h.selfStacks ~= count then moved = true end
        end
    end)
    if moved and ns.CdmRows then ns.CdmRows.Refresh() end
end
DUI.RegisterEvent("WEAPON_ENCHANT_CHANGED", function() A.WeaponsChanged() end)
DUI.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() A.WeaponsChanged() end)
DUI.RegisterEvent("UNIT_INVENTORY_CHANGED", function(_, unit)
    if unit == "player" then A.WeaponsChanged() end
end)

local pets = CreateFrame("Frame")
pets:RegisterUnitEvent("UNIT_PET", "player")
pets:RegisterUnitEvent("UNIT_FLAGS", "pet")
pets:RegisterUnitEvent("UNIT_HEALTH", "pet")
-- Buffs on your pet (Bestial Wrath): holders that watch it look again.
pets:RegisterUnitEvent("UNIT_AURA", "pet")
pets:SetScript("OnEvent", function(_, event)
    if event == "UNIT_AURA" then A.AuraChangedSoon() return end
    DUI.SafeCall(A.PetChanged, event == "UNIT_PET")
end)

DUI.RegisterEvent("PLAYER_TARGET_CHANGED", function() A.Retarget(); A.AuraChanged() end)
-- Out of combat, lookups are readable again.
DUI.RegisterEvent("PLAYER_REGEN_ENABLED", function() A.AuraChanged() end)
DUI.RegisterEvent("SPELLS_CHANGED", function() A.Rebuild() end)
-- Shield absorbs changed: update the amounts.
DUI.RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED", function()
    for _, h in pairs(holders) do
        if h.amountOn and h:IsShown() then A.UpdateShield(h) end
    end
end)
