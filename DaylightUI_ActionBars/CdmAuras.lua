-- Aura spells the game's Cooldown Manager doesn't display. Each gets a holder in the
-- layout slot with a client AuraContainer inside: given a unit, filter and spell ids,
-- the client finds the aura and draws the button only while it's up. Its buttons are
-- never read. Whether the aura is up (A.IsUp) comes from spell id lookups out of
-- combat, and in combat from the game's own aura item, your casts and the last known
-- duration.

local _, ns = ...
local DUI = DaylightUI
local Style, Skin, Pixel, Motion = DUI.Style, ns.Skin, DUI.Pixel, DUI.Motion

local A = {}
ns.CdmAuras = A

local holders = {}   -- [id] = holder frame
local makeFace, placeFace, paintFace   -- self-debuff face, defined below

local function plain(v)
    return type(v) == "number" and not (issecretvalue and issecretvalue(v)) and v or nil
end

local function infoOf(id)
    local CV = _G.C_CooldownViewer
    if type(CV) ~= "table" or type(CV.GetCooldownViewerCooldownInfo) ~= "function" then return nil end
    local ok, info = pcall(CV.GetCooldownViewerCooldownInfo, id)
    if ok and type(info) == "table" then return info end
end

local function nameOf(sid)
    if not sid or not C_Spell or not C_Spell.GetSpellName then return nil end
    local ok, n = pcall(C_Spell.GetSpellName, sid)
    if ok and type(n) == "string" and not (issecretvalue and issecretvalue(n)) then return n end
end

-- { [spellID] = true } for the spell and every rank of it (by name), learned or not.
function A.SpellIDs(id)
    local C = ns.CdmCustom
    if C and C.Is(id) then return C.Ranks(id) end
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
    local CV, cats = _G.C_CooldownViewer, type(_G.Enum) == "table" and _G.Enum.CooldownViewerCategory
    if name and type(CV) == "table" and type(CV.GetCooldownViewerCategorySet) == "function" and type(cats) == "table" then
        local seen = {}
        for _, cat in pairs(cats) do
            if type(cat) == "number" then
                local ok, list = pcall(CV.GetCooldownViewerCategorySet, cat, true)
                if ok and type(list) == "table" then
                    for _, cid in ipairs(list) do
                        local info = not seen[cid] and plain(cid) and infoOf(cid)
                        seen[cid] = true
                        if info and nameOf(plain(info.spellID)) == name then add(info) end
                    end
                end
            end
        end
    end
    return ids
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
    return base and C.KeyOfAuraSpell(base) or nil
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

-- Cooldowns the game shows by their aura while it's up (Rend, Thunder Clap).
-- Same test as CooldownViewerItemDataMixin:CanUseAuraForDisplay: hasAura set
-- and the HideAura flag clear.
function A.Follows(id)
    if ns.CdmCustom and ns.CdmCustom.Is(id) then return false end   -- custom pieces follow their track
    local info = infoOf(id)
    if not info or (issecretvalue and issecretvalue(info.hasAura)) or info.hasAura ~= true then return false end
    local flags = plain(info.flags)
    local F = type(_G.Enum) == "table" and _G.Enum.CooldownSetSpellFlags
    local hide = type(F) == "table" and plain(F.HideAura) or 1
    return not (flags and math.floor(flags / hide) % 2 == 1)
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
    local function try(fn, ...) pcall(fn, ...) end
    -- The layout only positions the button. Without a size it stays 0x0.
    try(btn.SetSize, btn, h.size, h.size)
    h.buttons = h.buttons or {}
    h.buttons[#h.buttons + 1] = btn
    local parts = {}
    h.parts = h.parts or {}
    h.parts[btn] = parts
    local okB, box = pcall(CreateFrame, "Frame", nil, btn)
    if okB and box then
        parts.box = box
        try(box.SetFrameLevel, box, math.max(0, btn:GetFrameLevel() - 1))
        local okS, s = pcall(Style.Shell, box, Skin.ShellOpts())
        -- Kept out of the normal style repaint because the client locks the
        -- button. placeButton repaints it once restrictions lift.
        if okS and s then parts.shell = s; Style.Untrack(s) end
    end
    local icon = btn:CreateTexture(nil, "ARTWORK")
    parts.icon = icon
    try(icon.SetTexCoord, icon, Skin.CROP[1], Skin.CROP[2], Skin.CROP[3], Skin.CROP[4])
    try(btn.SetIcon, btn, icon)
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, btn, "CooldownFrameTemplate")
    if ok and cd then
        try(cd.SetAllPoints, cd, icon)
        try(Skin.StyleCooldown, cd)
        try(btn.SetDurationCooldown, btn, cd)
        parts.cd = cd
        -- The countdown ending is the one signal that the buff expired when
        -- auras can't be read (combat, dungeons). Hooked here during creation
        -- because the client refuses show/hide scripts on the button.
        try(cd.HookScript, cd, "OnCooldownDone", function() DUI.SafeCall(ns.CdmEffects.AuraHeard, h, "time out") end)
    end
    local shade = btn:CreateTexture(nil, "ARTWORK", nil, 3)
    parts.shade = shade
    try(shade.SetAllPoints, shade, icon)
    try(shade.SetTexture, shade, Skin.SHADE_FILE)
    try(shade.SetVertexColor, shade, 0, 0, 0, Skin.SHADE)
    local ok2, count = pcall(btn.CreateFontString, btn, nil, "OVERLAY")
    if ok2 and count then
        parts.count = count
        try(count.SetPoint, count, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
        try(btn.SetApplicationCount, btn, count)
    end
    if parts.box then placeButton(h, btn) end
    if btn.SetMouseMotionEnabled then try(btn.SetMouseMotionEnabled, btn, false) end
    ns.CdmEffects.MakeSlide(btn, h)
end

-- h.layoutFor and h.init let other holders (CdmBars' aura bars) use their own button
-- shape. cand: candidate filters from A.SelfDebuffGroup, else match by spell id.
local function build(h, unit, filter, ids, cand)
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, h, "CustomAuraContainerTemplate")
    if not ok or not c then h.err = tostring(c); return end
    pcall(c.EnableMouse, c, false)
    pcall(c.SetAllPoints, c, h)
    -- One button, from the holder's top left corner.
    local fd = _G.AnchorUtil and _G.AnchorUtil.FlowDirection
    pcall(c.SetFlowLayoutAnchorPoint, c, "TOPLEFT")
    if type(fd) == "table" then pcall(c.SetFlowLayoutGrowthDirection, c, fd.Right, fd.Down) end
    local layout = (h.layoutFor or layoutFor)(h)
    pcall(c.SetFlowLayoutMaximumLineSize, c, layout.elementWidth)
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
    pcall(c.SetUnit, c, unit)
    pcall(c.SetEnabled, c, true)
    c:Show()
    h.containers[#h.containers + 1] = { c = c, unit = unit, selfDebuff = cand ~= nil or nil, filter = filter,
                                        maxDuration = cand and cand.maxDuration or nil }
end

-- Containers for a spell id: your buffs, then your debuffs on the target, the same
-- order the game scans. Only self auras skip the target, since selfAura false
-- doesn't mean "on the target" (Battle Shout reports false).
local function setup(h, id)
    h.id, h.containers, h.err = id, {}, nil
    h.builtAt = GetTime()     -- a buff already up appears with the new container; not a proc
    -- When auras can't be read, wait for a buff that's already up to show its
    -- button, then ask again. No button means down.
    if A.Readable and not A.Readable() then
        local quiet = (ns.CdmEffects and ns.CdmEffects.AURA_QUIET) or 0.3
        C_Timer.After(quiet + 0.05, function() if ns.CdmRows then ns.CdmRows.Refresh() end end)
    end
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
    if custom and C.IsPet(id) then
        -- Your pet isn't an aura: drawn by the addon, up while it's out and alive.
        h.petWatch = true
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
        if type(self_) ~= "boolean" or (issecretvalue and issecretvalue(self_)) then self_ = nil end
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
    if h.selfDebuff then
        -- The client's container shows nothing for a debuff on yourself, whether
        -- matched by spell id (refused on a unit you can assist) or by caster and
        -- duration. So it's drawn by the addon: read by spell id where auras are
        -- plain, counted from your own casts where they aren't.
        h.mineOnly = true
        makeFace(h)
        if A.Readable() then A.IsUp(h) end
        paintFace(h)
        return
    end
    build(h, "player", "HELPFUL", ids)
    -- A spell added by ID can also be a debuff on you (Weakened Soul after a
    -- self-shield), so watch your debuffs as well as the target's.
    local added = custom and C.IsAdded(id)
    if added then
        local filter, cand = A.SelfDebuffGroup(id, ids)
        build(h, "player", filter, ids, cand)
        h.mineOnly = filter == "HARMFUL|PLAYER" or nil
    end
    if self_ ~= true then
        build(h, "target", "HARMFUL|PLAYER", ids)
    end
end

-- Shield unit: a friendly target, else the player.
function A.ShieldUnit()
    local ok, friend = pcall(UnitIsFriend, "player", "target")
    if ok and not (issecretvalue and issecretvalue(friend)) and friend == true then return "target" end
    return "player"
end

A.Setup = setup

-- Other holders with containers (CdmBars' aura bars), retargeted and rebuilt
-- alongside these.
local others = setmetatable({}, { __mode = "k" })
function A.Track(h) others[h] = true end

local function each(fn)
    for _, h in pairs(holders) do fn(h) end
    for h in pairs(others) do fn(h) end
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
-- the aura is down.
function A.Acquire(id, parent, always)
    local h = holders[id]
    if not h then
        h = CreateFrame("Frame", nil, parent)
        h.size = 36
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
    for _, k in ipairs(h.containers) do pcall(k.c.SetEnabled, k.c, true) end
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
        pcall(k.c.SetAuraGroupLayout, k.c, "a", layoutFor(h))
        pcall(k.c.SetFlowLayoutMaximumLineSize, k.c, size)
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
        for _, k in ipairs(h.containers or {}) do pcall(k.c.SetAlpha, k.c, on and 0 or 1) end
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
        local ok, yes = pcall(S.ShouldAurasBeSecret)
        if not ok or (issecretvalue and issecretvalue(yes)) or yes == true then return false end
    end
    return true
end

A.Readable = readable   -- /dui cdm report

-- After this long, a new container with no button means the aura is down
-- (matches CdmEffects' quiet time).
local function settled(h)
    local quiet = (ns.CdmEffects and ns.CdmEffects.AURA_QUIET) or 0.3
    return h.builtAt ~= nil and GetTime() - h.builtAt >= quiet
end

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

-- Show state, time and stacks. Fades use FAST so combat info isn't delayed.
-- Hide (Buff up) keeps it hidden while up.
function paintFace(h)
    local f = h.face
    if not f then return end
    local now = GetTime()
    local up = h.up == true and (h.endsAt == nil or h.endsAt > now)
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
    end
    local a = (up and not h.hideUp) and 1 or 0
    if f.alphaTo == a then return end
    local from = f:GetAlpha()
    f.alphaTo = a
    Motion.Tween(f, from, a, Motion.FAST, function(v) f:SetAlpha(v) end)
end

-- Expire the aura by the clock, since in combat nothing else reports it. One timer
-- per holder; if a recast pushed the end back, it keeps waiting.
local function watchEnd(h)
    if h.endTimer or not h.endsAt then return end
    h.endTimer = true
    C_Timer.After(math.max(0, h.endsAt - GetTime()) + 0.05, function()
        h.endTimer = nil
        if not h.endsAt then return end
        if GetTime() < h.endsAt then return watchEnd(h) end
        h.endsAt = nil
        local was = h.up
        if readable() or h.selfDebuff then A.IsUp(h) elseif was then h.up = false end
        paintFace(h)
        if h.up ~= was and h.wantsUp and ns.CdmRows then ns.CdmRows.Refresh() end
    end)
end

-- Buff durations per piece, saved per character (cdmAuraLasts[piece id] = seconds).
-- Learned where auras can be read, so a reload inside a dungeon still knows when
-- a cast's buff runs out.
local function book()
    local c = DUI.DB and DUI.DB.Character()
    if type(c) ~= "table" then return {} end
    if type(c.cdmAuraLasts) ~= "table" then c.cdmAuraLasts = {} end
    return c.cdmAuraLasts
end

-- Fallback before a duration is learned: parse the spell text.
local TEXT_LASTS = { "[Ff]or (%d+%.?%d*) sec", "[Ll]asts (%d+%.?%d*) sec" }
local function textLasts(sid)
    local ok, desc = pcall(C_Spell.GetSpellDescription, sid)
    if not ok or type(desc) ~= "string" or (issecretvalue and issecretvalue(desc)) then return nil end
    for _, pat in ipairs(TEXT_LASTS) do
        local n = tonumber(string.match(desc, pat))
        if n and n > 0 then return n end
    end
end

-- Debuffs on you (Weakened Soul, Arcane Blast's stack). Containers refuse to match
-- a debuff on an assistable unit by spell id unless the spell is never secret
-- (AuraContainerUtil.CanApplyIdentityCandidateFilters). So match any debuff of
-- yours no longer than the spell's duration (learned, else from its text, else
-- A.SELF_DEBUFF_CAP seconds). Returns the group filter and candidate filters.
A.SELF_DEBUFF_CAP = 30
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
function A.SelfDebuffGroup(id, ids)
    ids = ids or {}
    if neverSecret(ids) then return "HARMFUL", { includeSpellIDs = ids } end
    local n = id ~= nil and book()[id] or nil
    if not n then
        for sid in pairs(ids) do
            n = textLasts(sid)
            if n then break end
        end
    end
    return "HARMFUL|PLAYER", { maxDuration = n and (math.ceil(n) + 1) or A.SELF_DEBUFF_CAP }
end

-- Buffs consumed by your blocks (Shield Block, Holy Shield). Max charges seen are
-- saved per character (cdmAuraCharges[piece id]). In a dungeon fight nothing else
-- says the buff ended early, but counting blocks does.
local function charges()
    local c = DUI.DB and DUI.DB.Character()
    if type(c) ~= "table" then return {} end
    if type(c.cdmAuraCharges) ~= "table" then c.cdmAuraCharges = {} end
    return c.cdmAuraCharges
end

-- Fallback before charges are seen: parse the spell text. Forever's Shield Block
-- blocks 2 attacks, Holy Shield has 4 charges. If nothing matches, don't count at
-- all and rely on the clock. Guessing 1 ended Shield Block after its first block.
local TEXT_CHARGES = { "block (%d+) attacks?", "(%d+) charges?" }
local function textCharges(sid)
    local ok, desc = pcall(C_Spell.GetSpellDescription, sid)
    if not ok or type(desc) ~= "string" or (issecretvalue and issecretvalue(desc)) then return nil end
    for _, pat in ipairs(TEXT_CHARGES) do
        local n = tonumber(string.match(desc, pat))
        if n and n > 0 then return n end
    end
end

-- Remember a found aura's duration and end time for casts in combat (A.Cast).
local function learn(h, a, unit)
    h.upUnit = unit
    local n = plain(a.applications)
    if n and h.selfDebuff then
        h.selfStacks, h.selfRead = n, true
        if n > (h.selfMax or 0) then h.selfMax = n end
    end
    if n and n > 0 and h.id ~= nil and ns.CdmOwn and ns.CdmOwn.Stacks(h.id) then
        local was = charges()[h.id]
        if not was or n > was then charges()[h.id] = n end
    end
    local dur, ends = plain(a.duration), plain(a.expirationTime)
    if not dur then return end
    h.auraLasts = dur
    if dur > 0 and h.id ~= nil then book()[h.id] = dur end
    h.endsAt = dur > 0 and ends or nil
    watchEnd(h)
end

local ON_YOU = { { unit = "player" } }   -- self debuffs have no container (makeFace)
local function found(h)
    local get = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
    if type(get) ~= "function" or type(h.ids) ~= "table" then return false end
    for _, k in ipairs(h.selfDebuff and ON_YOU or h.containers or {}) do
        for sid in pairs(h.ids) do
            local ok, a = pcall(get, k.unit, sid)
            -- On the target, only your own debuff counts (HARMFUL|PLAYER).
            local fromOther = not (issecretvalue and issecretvalue(a and a.isFromPlayerOrPlayerPet))
                and type(a) == "table" and a.isFromPlayerOrPlayerPet == false
            -- On you, someone else's debuff isn't shown by the HARMFUL|PLAYER group,
            -- so counting it would leave an empty spot.
            local otherDebuff = h.mineOnly and fromOther and type(a) == "table" and a.isHarmful == true
            if ok and type(a) == "table" and not otherDebuff and (k.unit == "player" or not fromOther) then
                learn(h, a, k.unit)
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
        if issecretvalue and issecretvalue(v) then return "secret" end
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
    local ok, yes = pcall(UnitExists, "pet")
    if not ok or (issecretvalue and issecretvalue(yes)) or yes ~= true then return false end
    local okD, dead = pcall(UnitIsDead, "pet")
    return not (okD and not (issecretvalue and issecretvalue(dead)) and dead == true)
end

function A.IsUp(h)
    if type(h) ~= "table" then return nil end
    if h.petWatch then
        h.up = A.PetOut()
        return h.up
    end
    if found(h) then
        h.up = true
    elseif h.selfDebuff then
        -- Not finding it by id means nothing, since Arcane Blast's stack can't be
        -- tracked that way in game. It's down once the counted time runs out, or
        -- when it was found before and is now gone where auras can be read.
        if not (h.endsAt and h.endsAt > GetTime()) or (h.selfRead and readable()) then
            h.up, h.endsAt, h.selfStacks, h.selfRead = false, nil, nil, nil
        end
    elseif readable() and #(h.containers or {}) > 0 then
        h.up = false
    elseif h.up == nil and #(h.containers or {}) > 0 and settled(h) then
        -- Unreadable (dungeon, reload in combat) and no button appeared since the
        -- container was made, so it's down. A.Shown corrects this if it lands.
        h.up = false
    end
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
            if readable() or h.petWatch then A.IsUp(h) end
            paintFace(h)
            if h.wantsUp and h.up ~= was then moved = true end
        elseif h.wantsUp and h:IsShown() then
            local was = h.up
            if A.IsUp(h) ~= was then moved = true end
        end
    end)
    if moved and ns.CdmRows then ns.CdmRows.Refresh() end
end

-- Coalesce bursts of UNIT_AURA (pre-pull rebuffs, raid fights) into one pass
-- on the next frame.
local changeQueued = false
function A.AuraChangedSoon()
    if changeQueued then return end
    changeQueued = true
    C_Timer.After(0, function()
        changeQueued = false
        DUI.SafeCall(A.AuraChanged)
    end)
end

-- In combat your own cast events stay plain while the aura and its button don't,
-- so a cast is the one reliable sign it's up. A harmful spell's aura is on the
-- target, so switching targets clears it (A.TargetChanged).
function A.Cast(h, sid)
    h.up = true
    local ok, harmful = pcall(C_Spell.IsSpellHarmful, sid)
    h.upUnit = ok and harmful == true and not h.selfDebuff and "target" or "player"
    -- Duration: read this session, else saved, else from the spell text. Without
    -- one it would stay up forever, since the client's button says nothing in a
    -- dungeon fight.
    h.auraLasts = h.auraLasts or (h.id ~= nil and book()[h.id]) or textLasts(sid)
    h.endsAt = h.auraLasts and h.auraLasts > 0 and GetTime() + h.auraLasts or nil
    h.blocksLeft = h.id ~= nil and ns.CdmOwn and ns.CdmOwn.Stacks(h.id) and (charges()[h.id] or textCharges(sid)) or nil
    watchEnd(h)
    if ns.CdmRows then ns.CdmRows.Refresh() end
end

-- Max stacks parsed from the spell text ("stacks up to 4 times"). nil = no cap.
local function textStacks(sid)
    local ok, desc = pcall(C_Spell.GetSpellDescription, sid)
    if not ok or type(desc) ~= "string" or (issecretvalue and issecretvalue(desc)) then return nil end
    return tonumber(string.match(desc, "[Ss]tacks up to (%d+) times"))
end

-- Count casts of a spell whose debuff lands on you (Arcane Blast), since the stack
-- can't be tracked by spell id. The first cast starts the timer and each later one
-- adds a stack. The duration runs from the first application, so recasts don't
-- extend it. Dying clears it.
local function selfCast(h, sid)
    -- If it was just read by id, trust the read over the count. The aura event
    -- can arrive before the cast and would be counted twice.
    if h.selfRead and readable() then
        A.AuraChangedSoon()
        return
    end
    local now = GetTime()
    local facts = A.SelfDebuffFacts(h.id) or {}
    h.auraLasts = h.auraLasts or (h.id ~= nil and book()[h.id]) or textLasts(sid) or facts.lasts
    if h.up == true and h.endsAt and h.endsAt > now then
        local cap = facts.stacks or h.selfMax or textStacks(sid)
        local n = (h.selfStacks or 1) + 1
        h.selfStacks = cap and math.min(n, cap) or n
    else
        h.up, h.upUnit, h.selfStacks = true, "player", 1
        h.endsAt = h.auraLasts and h.auraLasts > 0 and now + h.auraLasts or nil
        watchEnd(h)
    end
    paintFace(h)
    if ns.CdmRows then ns.CdmRows.Refresh() end
end

local casts = CreateFrame("Frame")
casts:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
casts:SetScript("OnEvent", function(_, _, _, _, sid)
    if type(sid) ~= "number" or (issecretvalue and issecretvalue(sid)) then return end
    local plainNow = readable()
    each(function(h)
        if type(h.ids) == "table" and h.ids[sid] then
            if h.face then selfCast(h, sid) elseif h.wantsUp and not plainNow then A.Cast(h, sid) end
        end
    end)
end)

DUI.RegisterEvent("PLAYER_DEAD", function()
    each(function(h)
        if h.face and h.up == true then
            h.up, h.endsAt, h.selfStacks = false, nil, nil
            paintFace(h)
            if h.wantsUp and ns.CdmRows then ns.CdmRows.Refresh() end
        end
    end)
end)

-- The client's button appeared (CdmEffects' slide OnPlay). In combat this is the
-- only sign that a buff you didn't cast (a proc, someone else's) is up. With no
-- known duration it stays up until auras can be read again. Applies to every
-- holder, since a buff already up appears before the pass says what it wants.
function A.Shown(h)
    if h.up == true or readable() then return end
    h.up = true
    if ns.CdmRows then ns.CdmRows.Refresh() end
end

-- The client's button went away (CdmEffects), so the buff is down.
function A.Hidden(h)
    -- Hiding the holder hides the button too; that isn't the buff ending.
    if h.up == false or readable() or not h:IsVisible() then return end
    h.up, h.endsAt = false, nil
    if ns.CdmRows then ns.CdmRows.Refresh() end
end

-- Blocked hits (UNIT_COMBAT "BLOCK", or "WOUND" flagged BLOCK / BLOCK_REDUCED;
-- action and flag stay plain) use up a charge of block buffs. When the last is
-- gone the buff is down. Only used where auras can't be read.
local blocks = CreateFrame("Frame")
blocks:RegisterUnitEvent("UNIT_COMBAT", "player")
blocks:SetScript("OnEvent", function(_, _, _, action, flag)
    if (issecretvalue and (issecretvalue(action) or issecretvalue(flag))) or readable() then return end
    if not (action == "BLOCK" or (action == "WOUND" and (flag == "BLOCK" or flag == "BLOCK_REDUCED"))) then return end
    each(function(h)
        if h.up == true and h.blocksLeft then
            h.blocksLeft = h.blocksLeft - 1
            if h.blocksLeft <= 0 then
                h.blocksLeft = nil
                DUI.SafeCall(ns.CdmEffects.AuraHeard, h, "blocked")
            end
        end
    end)
end)

-- Reported by the game's own aura item via CdmRows: true, or nil when down.
function A.Told(h, up)
    h.up = up
    if not up then h.endsAt = nil end
    return up or nil
end

-- New target in combat: auras on the old one can no longer be tracked.
function A.TargetChanged()
    if readable() then return end
    each(function(h)
        if h.wantsUp and h.up == true and h.upUnit == "target" then
            h.up, h.endsAt = false, nil
            if ns.CdmRows then ns.CdmRows.Refresh() end
        end
    end)
end

function A.ReleaseExcept(used)
    for id, h in pairs(holders) do
        if not used[id] and h:IsShown() then
            h:Hide()
            for _, k in ipairs(h.containers) do pcall(k.c.SetEnabled, k.c, false) end
        end
    end
end

-- New target. Containers follow it on their own; this extra refresh is harmless.
function A.Retarget()
    each(function(h)
        for _, k in ipairs(h.containers or {}) do
            -- Same unit token, new unit. The container only re-reads on an aura
            -- change or when told.
            if k.shield then
                -- Still on you (enemy or no target): leave it alone, or the
                -- client rebuilds its button and the bar flashes.
                local unit = A.ShieldUnit()
                if not (unit == "player" and k.unit == "player") then
                    k.unit = unit
                    pcall(k.c.SetUnit, k.c, k.unit)
                    pcall(k.c.UpdateAllAuras, k.c)
                    if ns.CdmBars then ns.CdmBars.Retarget(h, k.unit) end
                    if holders[h.id] == h then h.shieldUnit = k.unit; A.UpdateShield(h) end
                end
            elseif k.unit == "target" then
                pcall(k.c.SetUnit, k.c, "target")
                pcall(k.c.UpdateAllAuras, k.c)
            end
        end
    end)
end

-- Spells changed, so ranks may have too.
function A.Rebuild()
    each(function(h)
        if not InCombatLockdown() and h.containers and h.id then
            h.ids = A.SpellIDs(h.id)
            for _, k in ipairs(h.containers) do
                local filters = { includeSpellIDs = h.ids }
                if k.selfDebuff then filters = select(2, A.SelfDebuffGroup(h.id, h.ids)) end
                pcall(k.c.SetAuraGroupCandidateFilters, k.c, "a", filters)
            end
        end
    end)
end

-- The pet came, went or died: pet pieces show it at once.
function A.PetChanged()
    local moved = false
    each(function(h)
        if h.petWatch then
            local was = h.up
            A.IsUp(h)
            paintFace(h)
            if h.up ~= was then moved = true end
        end
    end)
    if moved and ns.CdmRows then ns.CdmRows.Refresh() end
end

local pets = CreateFrame("Frame")
pets:RegisterUnitEvent("UNIT_PET", "player")
pets:RegisterUnitEvent("UNIT_FLAGS", "pet")
pets:RegisterUnitEvent("UNIT_HEALTH", "pet")
pets:SetScript("OnEvent", function() DUI.SafeCall(A.PetChanged) end)

DUI.RegisterEvent("PLAYER_TARGET_CHANGED", function() A.Retarget(); A.TargetChanged(); A.AuraChanged() end)
-- Out of combat, lookups are readable again.
DUI.RegisterEvent("PLAYER_REGEN_ENABLED", function() A.AuraChanged() end)
DUI.RegisterEvent("SPELLS_CHANGED", function() A.Rebuild() end)
-- Shield absorbs changed: update the amounts.
DUI.RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED", function()
    for _, h in pairs(holders) do
        if h.amountOn and h:IsShown() then A.UpdateShield(h) end
    end
end)
