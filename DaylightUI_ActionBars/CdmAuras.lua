-- Aura spells the game's Cooldown Manager doesn't display: a holder of ours in
-- the layout slot with the game's own aura container inside. We tell the
-- container a unit, a filter and spell ids; the game finds the aura, shows a
-- button only while it's up and draws icon, swipe, time and stacks. The
-- client's buttons are never read. The missing glow and Hide (Buff up) ask
-- whether the aura is up (A.IsUp): by spell id, plain only out of a fight; in
-- one, the game's own aura item says (CdmRows), else your own cast and how
-- long the aura lasted when last read.

local _, ns = ...
local DUI = DaylightUI
local Style, Skin, Pixel, Motion = DUI.Style, ns.Skin, DUI.Pixel, DUI.Motion

local A = {}
ns.CdmAuras = A

local holders = {}   -- [id] = holder frame
local makeFace, placeFace, paintFace   -- a debuff on you, drawn by ours (below)

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

-- { [spellID] = true } for the spell and every rank of it (same name), learned or not.
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
    -- Our list's ranks: a cooldown whose aura only the list knows (Bloodrage).
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

-- The spell puts its debuff on YOU (Arcane Blast's stack): a piece of our
-- list, or the game's piece of that spell. The game's own item never sees
-- it (it looks on you for HELPFUL|PLAYER only, CooldownViewerItemData.lua
-- GetTargetAurasFilterString), so ours draws it (CdmRows' claim).
-- Our list's key of the piece (itself, or the family of the game item's spell).
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

-- Its length and most stacks from the game's data (CdmCustom.SELF_DEBUFF).
function A.SelfDebuffFacts(id)
    local own = ownKey(id)
    return own ~= nil and ns.CdmCustom.SelfDebuffFacts and ns.CdmCustom.SelfDebuffFacts(own) or nil
end

-- A cooldown the game shows by its aura while that's up (Rend, Thunder
-- Clap): the game's Essential icon does (CooldownViewerItemDataMixin
-- :CanUseAuraForDisplay: hasAura, and the HideAura flag not set).
function A.Follows(id)
    if ns.CdmCustom and ns.CdmCustom.Is(id) then return false end   -- ours follow their track
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

-- The button's look, made once inside initializeFrame (afterwards the client
-- may lock it): our icon crop, border, shade, swipe and stack count.
-- The border goes on a box of ours with a size of its own and one anchor,
-- as on the aura bars (CdmBars' iconBox): a frame laid on the client's
-- button by all its points came out 0x0 in game (`/dui cdm shells`), so
-- the shell drew nothing. The icon sits inside the border, sized the same way.
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
    -- A shield's amount (A.SetAmount) sits where the time was.
    if h.amountOn and parts.cd then try(parts.cd.SetHideCountdownNumbers, parts.cd, true) end
    -- "Hide duration swipe" (A.SetSwipe): the time stays.
    if parts.cd then try(parts.cd.SetDrawSwipe, parts.cd, not h.noSwipe) end
    -- "Reverse swipe" (A.SetSwipe).
    if parts.cd then try(parts.cd.SetReverse, parts.cd, h.reverse == true) end
end

local function initButton(h, btn)
    local function try(fn, ...) pcall(fn, ...) end
    -- The layout only places the button: its size is ours to set, or it's 0x0.
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
        -- Kept out of the style repaint: the client locks the button, so
        -- placeButton (after restrictions) is its repaint.
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
        -- The buff's time running out: the client's countdown on it ends,
        -- in fights and dungeons too, where auras can't be read. Hooked
        -- here, in the creation window (no show or hide scripts in the
        -- button: the client refuses those).
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

-- h.layoutFor / h.init: another holder's own button shape and dress
-- (CdmBars' aura bars); the icon's otherwise.
-- cand: the group's candidate filters, else by spell id (A.SelfDebuffGroup).
local function build(h, unit, filter, ids, cand)
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, h, "CustomAuraContainerTemplate")
    if not ok or not c then h.err = tostring(c); return end
    pcall(c.EnableMouse, c, false)
    pcall(c.SetAllPoints, c, h)
    -- One button, from the holder's top left corner (like the Buffs bars).
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

-- The holder's containers for spell id: the player's buffs, then the
-- target's debuffs of yours, the order the game looks in
-- (CooldownViewerItemData.lua scanUnits). Only a self aura skips the target:
-- selfAura false doesn't mean "on the target" (Battle Shout says false).
local function setup(h, id)
    h.id, h.containers, h.err = id, {}, nil
    h.builtAt = GetTime()     -- a buff already up comes up with the new container: not a proc
    -- Auras can't be read (a dungeon): once a buff already up has had its
    -- button come up, the pass asks again (A.IsUp: none came = down).
    if A.Readable and not A.Readable() then
        local quiet = (ns.CdmEffects and ns.CdmEffects.AURA_QUIET) or 0.3
        C_Timer.After(quiet + 0.05, function() if ns.CdmRows then ns.CdmRows.Refresh() end end)
    end
    local C = ns.CdmCustom
    local custom = C ~= nil and C.Is(id)
    -- One of our own list: its containers are made out of combat only
    -- (whether the client lets addon code make one in a fight isn't
    -- settled); placed or reloaded mid-fight, it fills once the fight ends.
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
    local self_
    if custom then
        self_ = C.SelfOnly(id) or nil
    else
        local info = infoOf(id)
        self_ = info and info.selfAura
        if type(self_) ~= "boolean" or (issecretvalue and issecretvalue(self_)) then self_ = nil end
    end
    -- A debuff the spell puts on you (Arcane Blast's stack): your own
    -- debuffs too, and never the target's.
    h.selfDebuff = A.SelfDebuff(id)
    if ns.CdmBars and ns.CdmBars.IsShield(id) then
        -- A shield (Power Word: Shield): on your friendly target, else on
        -- you; one container whose unit follows the target (A.Retarget).
        build(h, A.ShieldUnit(), "HELPFUL", ids)
        local k = h.containers[#h.containers]
        if k then k.shield = true; h.shieldUnit = k.unit end
        return
    end
    if h.selfDebuff then
        -- A debuff the spell puts on you (Arcane Blast's stack): the client's
        -- container showed nothing for it, by spell id (refused for a debuff
        -- on a unit you can assist) or by caster and length alike. Ours draws
        -- it: read by spell id where auras are plain (the game's own item
        -- finds it that way, CooldownViewerItemData.lua
        -- FindLinkedSpellForCurrentAuras), counted from your own casts where
        -- they aren't. Never the target's.
        h.mineOnly = true
        makeFace(h)
        if A.Readable() then A.IsUp(h) end
        paintFace(h)
        return
    end
    build(h, "player", "HELPFUL", ids)
    -- Added by its ID, it may be a debuff on you as well (Weakened Soul
    -- after a self-shield): your debuffs too, and still the target's.
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

-- Whose shield shows: a friendly target's, else yours.
function A.ShieldUnit()
    local ok, friend = pcall(UnitIsFriend, "player", "target")
    if ok and not (issecretvalue and issecretvalue(friend)) and friend == true then return "target" end
    return "player"
end

A.Setup = setup

-- Other holders with containers (CdmBars' aura bars): retargeted and
-- rebuilt with ours.
local others = setmetatable({}, { __mode = "k" })
function A.Track(h) others[h] = true end

local function each(fn)
    for _, h in pairs(holders) do fn(h) end
    for h in pairs(others) do fn(h) end
end

-- The grayed icon inside its border (the border's width from the action bars' look).
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

-- The holder for placed aura spell id, inside parent. always ("Show missing
-- buffs"): the dim underlay shows while the aura is down.
function A.Acquire(id, parent, always)
    local h = holders[id]
    if not h then
        h = CreateFrame("Frame", nil, parent)
        h.size = 36
        -- The grayed icon in the action buttons' border and shade, as the
        -- client's button wears them while the aura is up.
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
        -- Ours may have a picture of their own (the Seal); else the spell's.
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
    -- The grayed icon while the aura is down, only with "Show missing buffs":
    -- the client's button covers it while up, so off, nothing shows while down.
    h.under:SetShown(always == true)
    h.underBox:SetShown(always == true)
    h.underOn = always == true
    h.overIcon = false   -- A.Over says otherwise
    for _, k in ipairs(h.containers) do pcall(k.c.SetEnabled, k.c, true) end
    h:Show()
    return h
end

-- "Cooldown and buff" (CdmOwn.Track): the holder over our own cooldown
-- icon, no dim underlay: the buff's button covers the icon while it's up,
-- the cooldown shows once it's gone.
function A.Over(h, icon, size, text)
    h.under:Hide()
    h.underBox:Hide()
    h.underOn = false
    h.overIcon = true    -- its buff fades in over the icon, no drop (Fx.TuneSlide)
    -- On the icon's spot, not the icon: going on cooldown the icon dips
    -- (Fx.Dip resizes it), and the client's button, its size locked, only
    -- slid with it ("down 2px then back up").
    local spot = icon:GetParent() or icon
    h:ClearAllPoints()
    h:SetPoint("CENTER", spot, "CENTER", 0, 0)
    h:SetSize(size, size)
    h:SetFrameLevel(icon:GetFrameLevel() + 10)
    A.Resize(h, size, text)
end

-- What a holder was last laid out for, value by value in h.look (kept, so a
-- layout pass that changed nothing makes no new table or string).
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

-- A holder's size changed: tell the containers (the holder itself is sized by Rows).
-- A border or count size setting changed too: the buttons are placed again.
-- text: the piece's icon text (Cooldowns.CD.TextLook), nil = the action bars'.
function A.Resize(h, size, text)
    if sameLook(h, size, text) then return end
    h.size, h.text = size, text
    placeUnder(h)
    placeFace(h)
    -- The client's aura buttons are locked while auras are secret (combat, a
    -- PvP match, a boss): they take the size once that lifts.
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

-- A shield's icon (Power Word: Shield): the shield left as a number over
-- it, in place of its time ("Show shield amount"). The amount is the game's
-- total of shields on the unit (UnitGetTotalAbsorbs, secret always): only
-- drawn. Any amount fills a 0-1 gate bar whose fill clips the text, so no
-- shield shows no number (CdmBars' shield bar does the same).
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

-- The client's buttons dressed again (the time, the swipe): after restrictions.
local function replace(h)
    DUI.AfterRestrictions(function()
        for _, btn in ipairs(h.buttons or {}) do placeButton(h, btn) end
    end, "cdm:auras:place:" .. tostring(h))
end

-- on: a shield's icon with "Show shield amount" (CdmRows, each pass);
-- text: the piece's icon text (its cooldown number size and color).
function A.SetAmount(h, on, text)
    on = on == true and h.shieldUnit ~= nil
    if on and not h.amount then makeAmount(h) end
    if h.amount then
        h.amount:SetShown(on)
        if on then
            -- Over the client's button (its container sits on the holder).
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

-- hide: the piece's "Hide duration swipe"; reverse: its "Reverse swipe"
-- (CdmRows, each pass).
function A.SetSwipe(h, hide, reverse)
    hide, reverse = hide == true or nil, reverse == true or nil
    if h.noSwipe == hide and h.reverse == reverse then return end
    h.noSwipe, h.reverse = hide, reverse
    replace(h)
    placeFace(h)
end

-- on: the piece's Hide (Buff up), each pass. The container goes see-through,
-- so the client's button can't show however a fight reads the aura; the
-- grayed icon of Keep its spot shows only while the aura isn't up.
function A.SetHideUp(h, on)
    on = on == true or nil
    if h.hideUp ~= on then
        h.hideUp = on
        for _, k in ipairs(h.containers or {}) do pcall(k.c.SetAlpha, k.c, on and 0 or 1) end
        paintFace(h)
    end
    if ns.Cooldowns then ns.Cooldowns.FollowHide(h) end
    if not h.underOn then return end
    -- Hide (Buff up) with Show missing buffs: the icon is only a reminder
    -- that the buff is down, so it shows in full color (a Paladin's
    -- Righteous Fury); otherwise the dim gray of a buff that's just down.
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

-- Is the holder's aura up: true, false, or nil (never known yet). Out of a
-- fight and restrictions the lookups by spell id are plain. In one they
-- quietly return nothing, so only a found aura counts and
-- otherwise the last answer stays.
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

-- How long after a container is made a buff already up has had its button
-- come up (CdmEffects' quiet time for the same): past it, none = down.
local function settled(h)
    local quiet = (ns.CdmEffects and ns.CdmEffects.AURA_QUIET) or 0.3
    return h.builtAt ~= nil and GetTime() - h.builtAt >= quiet
end

-- A debuff on you, drawn by ours (setup: h.selfDebuff): the client's button
-- look (shell, cropped icon, shade, swipe, stack count), made of our own
-- frames, so it's never locked. Up from h.up, h.endsAt, h.auraLasts and
-- h.selfStacks (read where plain, else counted from your casts: selfCast).
function makeFace(h)
    if h.face then return end
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
    -- The count over the swipe, as on the client's button.
    f.top = CreateFrame("Frame", nil, f.box)
    f.top:SetAllPoints(f.box)
    f.top:SetFrameLevel(f.cd:GetFrameLevel() + 1)
    f.count = f.top:CreateFontString(nil, "OVERLAY")
    f.count:SetPoint("BOTTOMRIGHT", f.icon, "BOTTOMRIGHT", -1, 1)
    f.shape = {}
    h.face = f
    local tex = h.under and h.under:GetTexture()
    if type(tex) ~= "nil" then f.icon:SetTexture(tex) end
    placeFace(h)
end

-- The look again (placeButton's, for our own face): size, border, count.
function placeFace(h)
    local f = h.face
    if not f then return end
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

-- Up or down, its time and its stacks: fades in and out (FAST: a fight's
-- word never waits). Hide (Buff up) keeps it out of sight while up.
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
                f.cd:SetCooldown(h.endsAt - dur, dur)
            end
        elseif f.shownEnd then
            f.shownEnd = nil
            f.cd:Clear()
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

-- When the aura runs out, by the clock: in a fight nothing else says so. One
-- timer per holder; a recast moved the end later, so it waits on.
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

-- Each piece's buff length, per character (DB.Character().cdmAuraLasts
-- [piece id] = seconds): learned where auras can be read, so a reload
-- inside a dungeon still knows when a cast's buff runs out (A.Cast).
local function book()
    local c = DUI.DB and DUI.DB.Character()
    if type(c) ~= "table" then return {} end
    if type(c.cdmAuraLasts) ~= "table" then c.cdmAuraLasts = {} end
    return c.cdmAuraLasts
end

-- Never read yet: the spell's own text ("... for 5 sec.", "Lasts 12 sec.").
local TEXT_LASTS = { "[Ff]or (%d+%.?%d*) sec", "[Ll]asts (%d+%.?%d*) sec" }
local function textLasts(sid)
    local ok, desc = pcall(C_Spell.GetSpellDescription, sid)
    if not ok or type(desc) ~= "string" or (issecretvalue and issecretvalue(desc)) then return nil end
    for _, pat in ipairs(TEXT_LASTS) do
        local n = tonumber(string.match(desc, pat))
        if n and n > 0 then return n end
    end
end

-- A debuff on you (Weakened Soul after a self-shield, Arcane Blast's stack):
-- the client's containers refuse to pick a debuff on a unit you can assist by
-- spell id unless the spell is never secret
-- (AuraContainerUtil.CanApplyIdentityCandidateFilters; a player's empty spot,
-- 2026-11-11). So it's picked by what's left: a debuff of yours, no longer
-- than the spell's (learned, else its text, else A.SELF_DEBUFF_CAP s).
-- Returns the group's filter and its candidate filters.
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

-- A buff whose charges your blocks use up (Shield Block, Holy Shield:
-- CdmOwn.Stacks), per character (cdmAuraCharges[piece id] = the most seen):
-- in a dungeon fight nothing says it ended early, but your blocks do.
local function charges()
    local c = DUI.DB and DUI.DB.Character()
    if type(c) ~= "table" then return {} end
    if type(c.cdmAuraCharges) ~= "table" then c.cdmAuraCharges = {} end
    return c.cdmAuraCharges
end

-- Never read yet: the spell's own text. WoW Forever's Shield Block "will
-- only block 2 attacks" (it was 1), Holy Shield has "4 charges". None found:
-- no counting at all (the clock alone), never a guess (a guessed 1 folded
-- Shield Block after its first block, seen in game 2026-11-09).
local TEXT_CHARGES = { "block (%d+) attacks?", "(%d+) charges?" }
local function textCharges(sid)
    local ok, desc = pcall(C_Spell.GetSpellDescription, sid)
    if not ok or type(desc) ~= "string" or (issecretvalue and issecretvalue(desc)) then return nil end
    for _, pat in ipairs(TEXT_CHARGES) do
        local n = tonumber(string.match(desc, pat))
        if n and n > 0 then return n end
    end
end

-- A found aura's length and end, kept for a fight's cast (A.Cast).
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

local ON_YOU = { { unit = "player" } }   -- a debuff on you: no container (makeFace)
local function found(h)
    local get = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
    if type(get) ~= "function" or type(h.ids) ~= "table" then return false end
    for _, k in ipairs(h.selfDebuff and ON_YOU or h.containers or {}) do
        for sid in pairs(h.ids) do
            local ok, a = pcall(get, k.unit, sid)
            -- On the target: only your own debuff (the container's HARMFUL|PLAYER).
            local fromOther = not (issecretvalue and issecretvalue(a and a.isFromPlayerOrPlayerPet))
                and type(a) == "table" and a.isFromPlayerOrPlayerPet == false
            -- On you, a debuff of someone else's isn't one the debuff group
            -- shows (HARMFUL|PLAYER, A.SelfDebuffGroup): a spot it opened stayed empty.
            local otherDebuff = h.mineOnly and fromOther and type(a) == "table" and a.isHarmful == true
            if ok and type(a) == "table" and not otherDebuff and (k.unit == "player" or not fromOther) then
                learn(h, a, k.unit)
                return true
            end
        end
    end
    return false
end

-- /dui cdm report: what the holder watches, what the client put in it and
-- what the game says of each spell id on you (plain only out of a fight).
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

function A.IsUp(h)
    if type(h) ~= "table" then return nil end
    if found(h) then
        h.up = true
    elseif h.selfDebuff then
        -- Not found by its id says nothing: Arcane Blast's stack can't be
        -- tracked that way in game (ArcAuras counts the casts, as selfCast
        -- does). Down once the counted time has run out.
        -- Found before and gone now, where auras read: down.
        if not (h.endsAt and h.endsAt > GetTime()) or (h.selfRead and readable()) then
            h.up, h.endsAt, h.selfStacks, h.selfRead = false, nil, nil, nil
        end
    elseif readable() and #(h.containers or {}) > 0 then
        h.up = false
    elseif h.up == nil and #(h.containers or {}) > 0 and settled(h) then
        -- Can't be read (a dungeon, a reload in a fight): no button came up
        -- since the container was made, so it isn't there (A.Shown says so
        -- if it lands).
        h.up = false
    end
    return h.up
end

-- A buff landing or falling off: holders whose piece cares whether it's up
-- (h.wantsUp, set by CdmRows: the missing glow, Hide) ask again; a change runs the layout pass.
function A.AuraChanged()
    local moved = false
    each(function(h)
        if h.face and h:IsShown() then
            -- Ours draws it, asked or not: its time and stacks too.
            local was = h.up
            if readable() then A.IsUp(h) end
            paintFace(h)
            if h.wantsUp and h.up ~= was then moved = true end
        elseif h.wantsUp and h:IsShown() then
            local was = h.up
            if A.IsUp(h) ~= was then moved = true end
        end
    end)
    if moved and ns.CdmRows then ns.CdmRows.Refresh() end
end

-- Once the frame after, however many UNIT_AURA came (a pre-pull rebuff,
-- a raid boss's target).
local changeQueued = false
function A.AuraChangedSoon()
    if changeQueued then return end
    changeQueued = true
    C_Timer.After(0, function()
        changeQueued = false
        DUI.SafeCall(A.AuraChanged)
    end)
end

-- Your own cast of it in a fight, the one plain word that it's up (your cast
-- events stay plain; the aura and its button don't). A harmful spell's aura is
-- on the target, so a new target takes it away (A.TargetChanged).
function A.Cast(h, sid)
    h.up = true
    local ok, harmful = pcall(C_Spell.IsSpellHarmful, sid)
    h.upUnit = ok and harmful == true and not h.selfDebuff and "target" or "player"
    -- Its length: read this session, else kept from before, else its text.
    -- Without one it would read up for good (the client's button gives no
    -- word in a dungeon fight, seen in game 2026-11-09).
    h.auraLasts = h.auraLasts or (h.id ~= nil and book()[h.id]) or textLasts(sid)
    h.endsAt = h.auraLasts and h.auraLasts > 0 and GetTime() + h.auraLasts or nil
    h.blocksLeft = h.id ~= nil and ns.CdmOwn and ns.CdmOwn.Stacks(h.id) and (charges()[h.id] or textCharges(sid)) or nil
    watchEnd(h)
    if ns.CdmRows then ns.CdmRows.Refresh() end
end

-- Never read yet: the most stacks, from the spell's own text ("Effect stacks
-- up to 4 times"). None found: no cap.
local function textStacks(sid)
    local ok, desc = pcall(C_Spell.GetSpellDescription, sid)
    if not ok or type(desc) ~= "string" or (issecretvalue and issecretvalue(desc)) then return nil end
    return tonumber(string.match(desc, "[Ss]tacks up to (%d+) times"))
end

-- Your own cast of a spell whose debuff lands on you (Arcane Blast), read or
-- not (its stack can't be tracked by spell id in game; ArcAuras counts the
-- casts too): the first starts it for its length, each one after adds a
-- stack (WoW Forever's text: "lasts 18 sec from time of initial
-- application", so a recast doesn't move the end). Dying clears it.
local function selfCast(h, sid)
    -- Read by its id just now (it can be, here): the read says, not the count
    -- (the aura's change may come before the cast's: counted twice).
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

-- The client's button came up for a new aura (the slide's OnPlay,
-- CdmEffects): in a fight the one word that a buff you didn't cast (a proc,
-- someone else's) is up. No length is known, so it reads up until the auras
-- can be read again.
-- Not only for holders that ask yet: a buff already up comes up with a new
-- container, before the pass says what it wants.
function A.Shown(h)
    if h.up == true or readable() then return end
    h.up = true
    if ns.CdmRows then ns.CdmRows.Refresh() end
end

-- Its button went away (the client stopped its shown animations, CdmEffects):
-- the buff is down, read or not.
function A.Hidden(h)
    -- The holder or its piece hiding hides the button too: not the buff.
    if h.up == false or readable() or not h:IsVisible() then return end
    h.up, h.endsAt = false, nil
    if ns.CdmRows then ns.CdmRows.Refresh() end
end

-- A hit you blocked (the game's CombatFeedback.lua: UNIT_COMBAT "BLOCK", or
-- "WOUND" flagged BLOCK / BLOCK_REDUCED; action and flag stay plain): a
-- charge of a buff your blocks use up. The last one gone, it's down. Only
-- where auras can't be read (out of one, they're read).
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

-- The game's own aura item says (CdmRows): true, or nil when it's down.
function A.Told(h, up)
    h.up = up
    if not up then h.endsAt = nil end
    return up or nil
end

-- A new target in a fight: what was up on the old one can't be told any more.
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

-- A new target: the containers follow it themselves; asked once more, harmless.
function A.Retarget()
    each(function(h)
        for _, k in ipairs(h.containers or {}) do
            -- Same unit token, new unit: the container only re-reads on an
            -- aura change or when told (like the target frame's auras).
            if k.shield then
                -- Still you (an enemy or no target): left alone, so the
                -- client doesn't rebuild its button (the bar flashed).
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

-- Spells learned: ranks may have changed.
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

DUI.RegisterEvent("PLAYER_TARGET_CHANGED", function() A.Retarget(); A.TargetChanged(); A.AuraChanged() end)
-- A fight's end: the lookups are plain again.
DUI.RegisterEvent("PLAYER_REGEN_ENABLED", function() A.AuraChanged() end)
DUI.RegisterEvent("SPELLS_CHANGED", function() A.Rebuild() end)
-- A shield soaking, landing or breaking: the icons' amounts.
DUI.RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED", function()
    for _, h in pairs(holders) do
        if h.amountOn and h:IsShown() then A.UpdateShield(h) end
    end
end)
