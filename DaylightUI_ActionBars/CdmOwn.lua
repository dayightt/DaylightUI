-- Icons for spells the player knows but the game's Cooldown Manager doesn't display
-- (set to "Not Displayed"). The game builds no item frame for those, so a placed one
-- gets a frame of ours with a cooldown swipe.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Own = {}
ns.CdmOwn = Own

local AURA = { TrackedBuff = true, TrackedBar = true, HiddenAura = true }
local frames = {}   -- [id] = frame
local holds = {}    -- [id .. kind] = placeholder frame

-- { [id] = { kind = "icon"|"bar", aura = bool } } for every spell the game lists for
-- this spec that the character knows, shown or not. Read only.
-- Cached between layout passes (one per aura shown or hidden) and re-read via
-- Own.Forget after a spell, talent or spec change and after the game's own layout
-- pass, since its Cooldown Manager settings may have moved a spell. An empty answer
-- (game not ready at login) or one read in combat or under restrictions (ids may
-- come back secret) isn't cached.
local known
local unsure, unsureFor   -- Own.Learn's list, and the layout (set, Data.version) it was built for
function Own.Forget() known, unsure = nil, nil end
function Own.Known()
    if known then return known end
    local out = Own.Read()
    if next(out) and not InCombatLockdown() and not (DUI.Restricted and DUI.Restricted()) then known = out end
    return out
end
-- What a placed piece is: a spell the game lists (Known), else one from the custom
-- list (CdmCustom.Entry). nil = nothing to draw. known = a layout pass's Own.Known(),
-- since in combat it isn't cached and each call would read it again.
function Own.Entry(id, known)
    local k = (known or Own.Known())[id]
    if k == nil and ns.CdmCustom then k = ns.CdmCustom.Entry(id) end
    return k
end
for _, e in ipairs({ "SPELLS_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
                     "PLAYER_TALENT_UPDATE", "COOLDOWN_VIEWER_DATA_LOADED", "COOLDOWN_VIEWER_TABLE_HOTFIXED" }) do
    pcall(DUI.RegisterEvent, e, Own.Forget)
end

function Own.Read()
    local out = {}
    local CV, cats = _G.C_CooldownViewer, type(_G.Enum) == "table" and _G.Enum.CooldownViewerCategory
    if type(CV) ~= "table" or type(CV.GetCooldownViewerCategorySet) ~= "function" or type(cats) ~= "table" then
        return out
    end
    for name, cat in pairs(cats) do
        if type(cat) == "number" then
            local ok, ids = pcall(CV.GetCooldownViewerCategorySet, cat, false)
            if ok and type(ids) == "table" then
                for _, id in ipairs(ids) do
                    -- In two categories the cooldown one wins (pairs order isn't fixed).
                    local had = type(id) == "number" and not (issecretvalue and issecretvalue(id)) and out[id]
                    if had == nil or (had and had.aura and not AURA[name]) then
                        out[id] = { kind = name == "TrackedBar" and "bar" or "icon", aura = AURA[name] or false, cat = name }
                    end
                end
            end
        end
    end
    -- The game files some cooldowns as buffs (Charge, which tracks the stun). An
    -- icon spell with a real cooldown is treated as a cooldown.
    for id, k in pairs(out) do
        if k.aura and k.kind == "icon" and Own.HasCooldown(Own.SpellOf(id)) then k.aura = false end
    end
    return out
end

-- Every placed spell rests on two facts: does it have a real cooldown
-- (Own.HasCooldown), and does it have a buff or debuff (the aura family, or a cooldown
-- the game shows by its aura, CdmAuras.Follows). One rule turns those into its Track
-- (card Behavior tab; the piece's own `track` wins): both -> "both" (the buff while
-- up, then the cooldown), a buff from the game's buff rows alone -> "buff" (shown only
-- while up), no aura -> nil (a plain cooldown, nothing to pick). A cooldown-row spell
-- left unset stays like the game's own icon, shown all the time with its aura while
-- up, cooldown or not (Rend, Moonfire). Own.Picked tells a real pick from the guess.
Own.TRACKS = { "both", "cooldown", "buff" }
local function valid(t) return t == "both" or t == "cooldown" or t == "buff" end

function Own.HasAura(id, k)
    if k and AURA[k.cat] then return true end
    return (ns.CdmAuras ~= nil and ns.CdmAuras.Follows(id)) or Own.QuietAura(id)
end

function Own.Track(id, p, known)
    local C = ns.CdmCustom
    if C and C.Is(id) then
        -- A spell of the addon's own list shows one thing (CdmCustom.Track), or both.
        return C.Track(id) == "both" and "both" or nil
    end
    local k = (known or Own.Known())[id]
    if not k then return nil end
    -- No buff known yet: a plain cooldown, unless the player picked something else.
    -- The buff is watched by the spell's own id until a cast teaches the real one.
    if not Own.HasAura(id, k) then
        local t = Own.Picked(p)
        return t ~= "cooldown" and t or nil
    end
    local t = Own.Picked(p)
    if t then return t end
    -- The game's icon never shows a quiet aura, so left alone it stays a cooldown
    -- until a Buff up or Buff missing row needs the buff. With no real cooldown
    -- (Slice and Dice) there's nothing to stay as. A buff that holds charges
    -- (Shield Block, Holy Shield; Own.Stacks) shows them while up, since the count
    -- is why it's placed.
    local hasCooldown = Own.HasCooldown(Own.SpellOf(id))
    if hasCooldown and not AURA[k.cat] and Own.QuietAura(id) then
        return (Own.Stacks(id) or type(p) == "table" and (p.hideActive == true or p.missingGlow == true or p.upGlow == true))
            and "both" or "cooldown"
    end
    -- A cooldown-row spell with no cooldown of its own (Rend, Moonfire) stays up
    -- like the game's icon: its aura while up, else ready. Only spells from the buff
    -- rows show just while up.
    return (hasCooldown or not AURA[k.cat]) and "both" or "buff"
end

-- Shows only its buff, never its cooldown.
function Own.BuffOnly(id, p, known)
    local C = ns.CdmCustom
    if C and C.Is(id) then return C.Track(id) == "aura" end
    return Own.Track(id, p, known) == "buff"
end

-- The player's own pick (not the rule's guess), or nil. Hide (Buff missing) implies
-- Buff only: shown just while the buff is up.
function Own.Picked(p)
    if type(p) == "table" and p.hideMissing == true then return "buff" end
    local t = type(p) == "table" and p.track
    if valid(t) then return t end
end

-- Spells seen on a real cooldown, per character (DB.Character().cdmCooldowns[spellID]
-- = true). The game doesn't always say (Forever's API docs lack
-- GetSpellBaseCooldown), so the first press outside restrictions teaches it.
local function learned()
    local c = DUI.DB and DUI.DB.Character()
    if type(c) ~= "table" then return {} end
    if type(c.cdmCooldowns) ~= "table" then c.cdmCooldowns = {} end
    return c.cdmCooldowns
end
function Own.Learned(sid) return sid ~= nil and learned()[sid] == true end

-- Placed spells with an aura whose cooldown is still unknown, checked on each
-- cooldown update (a short list, usually empty). Rebuilt after a layout change
-- (Data.version) or a talent set swap.
local function plainNum(v) if type(v) == "number" and not (issecretvalue and issecretvalue(v)) then return v end end
function Own.Learn()
    if not (ns.Cooldowns and ns.Cooldowns.enabled) then return end
    local set = ns.CdmData and ns.CdmData.Current()
    local stamp = set and tostring(set) .. ":" .. tostring(ns.CdmData.version)
    if unsure == nil or unsureFor ~= stamp then
        unsure, unsureFor = {}, stamp
        local known = Own.Known()
        for id in pairs(set and set.pieces or {}) do
            local sid = Own.SpellOf(id)
            if sid and Own.HasAura(id, known[id]) and not Own.HasCooldown(sid) then unsure[#unsure + 1] = sid end
        end
    end
    if #unsure == 0 or not (C_Spell and C_Spell.GetSpellCooldown) then return end
    local got = false
    for i = #unsure, 1, -1 do
        local sid = unsure[i]
        local ok, cd = pcall(C_Spell.GetSpellCooldown, sid)
        local dur = ok and type(cd) == "table" and plainNum(cd.duration)
        local gcd = ok and type(cd) == "table" and cd.isOnGCD
        if dur and dur > 1.6 and not (issecretvalue and issecretvalue(gcd)) and gcd ~= true then
            learned()[sid] = true
            table.remove(unsure, i)
            got = true
        end
    end
    if got then
        known = nil   -- Own.Read's "filed as a buff, but a cooldown" check changes
        if ns.CdmRows then ns.CdmRows.Refresh() end
    end
end
DUI.RegisterEvent("SPELL_UPDATE_COOLDOWN", function() DUI.SafeCall(Own.Learn) end)

-- The spell has a real cooldown (longer than the global cooldown): the game's base
-- cooldown, else one we've seen it run.
function Own.HasCooldown(sid)
    if not sid then return false end
    if Own.Learned(sid) then return true end
    local get = _G.GetSpellBaseCooldown or (C_Spell and C_Spell.GetSpellBaseCooldown)
    if type(get) ~= "function" then return false end
    local ok, ms = pcall(get, sid)
    if not ok or type(ms) ~= "number" or (issecretvalue and issecretvalue(ms)) then return false end
    return ms > 1500
end

local function infoOf(id)
    local CV = _G.C_CooldownViewer
    if type(CV) ~= "table" or type(CV.GetCooldownViewerCooldownInfo) ~= "function" then return nil end
    local ok, info = pcall(CV.GetCooldownViewerCooldownInfo, id)
    if ok and type(info) == "table" then return info end
end

local function plainNumber(v)
    if type(v) == "number" and not (issecretvalue and issecretvalue(v)) then return v end
end

function Own.SpellOf(id)
    local C = ns.CdmCustom
    if C and C.Is(id) then return C.SpellOf(id) end
    local info = infoOf(id)
    return info and plainNumber(info.spellID)
end

-- A cooldown with a buff or debuff the game's icon doesn't show (Bloodrage). Either
-- the game says it has an aura but flags it HideAura, or it says none and our spell
-- list (CdmSpells) knows one. It can still be picked on the card.
-- Racials the game files with no aura though they give a buff. Eureka! (Gnome) has
-- one rank per power type, and its buff carries the same spell id.
Own.RACIAL_AURAS = {
    [1259812] = true, [1259813] = true, [1259817] = true, [1259821] = true, [1259823] = true, -- Eureka!
}

function Own.QuietAura(id)
    local C = ns.CdmCustom
    if C and C.Is(id) then return false end
    if ns.CdmAuras and ns.CdmAuras.Follows(id) then return false end
    local info = infoOf(id)
    if info and not (issecretvalue and issecretvalue(info.hasAura)) and info.hasAura == true then return true end
    local sid = info and plainNumber(info.spellID)
    if sid ~= nil and Own.RACIAL_AURAS[sid] then return true end
    return sid ~= nil and ((C ~= nil and C.KeyOfAuraSpell(sid) ~= nil) or Own.AuraOf(sid) ~= nil)
end

-- Buffs and debuffs learned from your own casts, per character:
-- DB.Character().cdmAuraIDs[cast spell id] = { [aura spell id] = true }. Nothing
-- lists every spell's aura, so a placed spell's cast where auras can be read looks
-- for it, by id and by name (the aura's id can differ from the cast's).
local function auraBook()
    local c = DUI.DB and DUI.DB.Character()
    if type(c) ~= "table" then return {} end
    if type(c.cdmAuraIDs) ~= "table" then c.cdmAuraIDs = {} end
    return c.cdmAuraIDs
end

-- { [aura spell id] = true } learned for this cast spell id, or nil.
function Own.AuraOf(sid)
    local t = sid ~= nil and auraBook()[sid]
    return type(t) == "table" and next(t) ~= nil and t or nil
end

-- Spell ids of every placed piece, as { [cast spell id] = true }.
local function placedSpells()
    local set = ns.CdmData and ns.CdmData.Current()
    local out = {}
    local C = ns.CdmCustom
    for id in pairs(set and set.pieces or {}) do
        if C and C.Is(id) then
            if not C.IsPet(id) then
                for s in pairs(C.Ranks(id)) do out[s] = true end
            end
        else
            local s = Own.SpellOf(id)
            if s then out[s] = true end
        end
    end
    return out
end

-- Your aura from this cast: on you, then your own on the target. By id first,
-- then by the spell's name.
local LOOKS = { { unit = "player", filter = "HELPFUL" }, { unit = "target", filter = "HARMFUL|PLAYER" } }
local function auraFrom(sid)
    local U = C_UnitAuras
    if type(U) ~= "table" then return nil end
    local name
    local okN, n = pcall(C_Spell.GetSpellName, sid)
    if okN and type(n) == "string" and not (issecretvalue and issecretvalue(n)) then name = n end
    for _, look in ipairs(LOOKS) do
        local a
        if type(U.GetUnitAuraBySpellID) == "function" then
            local ok, got = pcall(U.GetUnitAuraBySpellID, look.unit, sid)
            -- On the target, only your own debuff.
            if ok and type(got) == "table" and (look.unit == "player"
                or got.isFromPlayerOrPlayerPet == true or got.sourceUnit == "player") then
                a = got
            end
        end
        if not a and name and type(U.GetAuraDataBySpellName) == "function" then
            local ok, got = pcall(U.GetAuraDataBySpellName, look.unit, name, look.filter)
            if ok and type(got) == "table" then a = got end
        end
        local found = a and plainNumber(a.spellId)
        if found then return found end
    end
end

-- After a cast of a placed spell, out of a fight: remember the aura it put up.
Own.AURA_LOOK_DELAY = 0.3
function Own.LearnAura(sid)
    if not (ns.Cooldowns and ns.Cooldowns.enabled) then return end
    local A = ns.CdmAuras
    if not (A and A.Readable and A.Readable()) then return end
    if not placedSpells()[sid] then return end
    local found = auraFrom(sid)
    if not found then return end
    local book = auraBook()
    if type(book[sid]) == "table" and book[sid][found] then return end
    book[sid] = type(book[sid]) == "table" and book[sid] or {}
    book[sid][found] = true
    known = nil
    A.Rebuild()
    if ns.CdmRows then ns.CdmRows.Refresh() end
end

local casts = CreateFrame("Frame")
casts:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
casts:SetScript("OnEvent", function(_, _, _, _, sid)
    if type(sid) ~= "number" or (issecretvalue and issecretvalue(sid)) or InCombatLockdown() then return end
    -- The aura lands a moment after the cast event.
    C_Timer.After(Own.AURA_LOOK_DELAY, function() DUI.SafeCall(Own.LearnAura, sid) end)
end)

-- Cooldowns whose buff holds charges, every rank. The game's cooldown icon shows the
-- buff but never its count (its cooldown items only draw spell charges, see
-- CooldownViewer.lua), so ours draws them, with the client's aura button counting
-- the charges left.
local STACKS = {
    [2565] = true,                                 -- Shield Block
    [20925] = true, [20927] = true, [20928] = true, -- Holy Shield
}
function Own.Stacks(id)
    local sid = Own.SpellOf(id)
    return sid ~= nil and STACKS[sid] == true
end

-- A gear slot cooldown (trinkets) with nothing equipped there. The game lists one on
-- every character; the tray leaves it out.
function Own.EmptySlot(id)
    local info = infoOf(id)
    local slot = info and plainNumber(info.equipSlot)
    if not slot or type(GetInventoryItemID) ~= "function" then return false end
    return GetInventoryItemID("player", slot) == nil
end

-- Cooldowns with no spell, as the game draws them (CooldownViewerItemData.lua,
-- spellCategoryMetadataLookup): potions and healthstones by spell category.
local CATEGORY = {
    [4] = { icon = "Interface/ICONS/INV_POTION_114", title = "COOLDOWN_VIEWER_TOOLTIP_POTION_COMBAT_TITLE", fallback = L["Combat potion"] },
    [30] = { icon = "Interface/ICONS/INV_POTION_54", title = "COOLDOWN_VIEWER_TOOLTIP_POTION_HEALTH_TITLE", fallback = L["Healing potion"] },
    [1711] = { icon = "Interface/ICONS/Warlock_ Healthstone", title = "COOLDOWN_VIEWER_TOOLTIP_POTION_HEALTHSTONE_TITLE", fallback = L["Healthstone"] },
    [2566] = { icon = "Interface/ICONS/Warlock_ Bloodstone", title = "COOLDOWN_VIEWER_TOOLTIP_POTION_DEMONIC_HEALTHSTONE_TITLE", fallback = L["Demonic Healthstone"] },
}

local SPELL_KEYS = { "overrideTooltipSpellID", "overrideSpellID", "spellID" }

-- A cooldown's name and icon (either may be nil): its spell, else the item in its
-- equipment slot (trinkets), else its spell category's (potions).
function Own.Look(id)
    local C = ns.CdmCustom
    if C and C.Is(id) then return C.Look(id) end
    local info = infoOf(id)
    if not info then return nil, nil end
    -- Same order as the game (CooldownViewerItemData.lua GetSpellID): tooltip
    -- override, override, then base spell; the first this client has.
    local first
    for _, key in ipairs(SPELL_KEYS) do
        local sid = plainNumber(info[key])
        if sid then
            first = first or sid
            local okN, name = pcall(C_Spell.GetSpellName, sid)
            local okT, tex = pcall(C_Spell.GetSpellTexture, sid)
            name = okN and type(name) == "string" and name or nil
            tex = okT and type(tex) ~= "nil" and tex or nil
            if name or tex then return name, tex end
        end
    end
    if first then return nil, nil end
    local slot = plainNumber(info.equipSlot)
    if slot then
        local tex = type(GetInventoryItemTexture) == "function" and GetInventoryItemTexture("player", slot) or nil
        local item = type(GetInventoryItemID) == "function" and GetInventoryItemID("player", slot)
        local get = item and type(C_Item) == "table" and C_Item.GetItemNameByID
        local ok, name = false, nil
        if type(get) == "function" then ok, name = pcall(get, item) end
        return ok and type(name) == "string" and name or nil, tex
    end
    local cat = CATEGORY[plainNumber(info.spellCategoryID) or 0]
    if cat then
        local title = _G[cat.title]
        return type(title) == "string" and title or cat.fallback, cat.icon
    end
    return nil, nil
end

function Own.Frame(id) return frames[id] end

function Own.Update(f)
    local sid = f.cooldownInfo and f.cooldownInfo.spellID
    if not sid or type(f.Cooldown) ~= "table" then return end
    local ok, dur
    local C = ns.CdmCustom
    if C and C.ItemOf(f.cooldownID) then   -- an item added by ID: the item's cooldown and count
        local _, d = C.ItemCooldown(f.cooldownID)
        ok, dur = true, d
        local n = C.ItemCount(f.cooldownID)
        f.ChargeCount.Current:SetText(n and tostring(n) or "")
    else
        ok, dur = pcall(C_Spell.GetSpellCooldownDuration, sid)
    end
    if ok and type(dur) ~= "nil" then
        pcall(f.Cooldown.SetCooldownFromDurationObject, f.Cooldown, dur, true)
    else
        f.Cooldown:Clear()
    end
end

function Own.UpdateAll()
    for _, f in pairs(frames) do
        if f:IsShown() then Own.Update(f) end
    end
    -- Our cooldown bars (CdmBars) follow the same events.
    if ns.CdmBars then ns.CdmBars.UpdateAll() end
end

function Own.Acquire(id, parent)
    local f = frames[id]
    if not f then
        f = CreateFrame("Frame", nil, parent)
        f.Icon = f:CreateTexture(nil, "ARTWORK")
        f.Icon:SetAllPoints()
        f.Icon:SetTexture(134400)
        f.Cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        f.Cooldown:SetAllPoints()
        -- A count (for an item added by ID) in the game items' spot and shape, so
        -- the skin's count styling reaches it. It sits over the swipe rather than
        -- on the Cooldown, which hides when cleared.
        local over = CreateFrame("Frame", nil, f)
        over:SetAllPoints(f)
        over:SetFrameLevel(f.Cooldown:GetFrameLevel() + 2)
        local count = over:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        f.ChargeCount = { Current = count }
        f.cooldownID = id
        f.cooldownInfo = {}
        if ns.Cooldowns and ns.Cooldowns.SkinItem then DUI.SafeCall(ns.Cooldowns.SkinItem, f) end
        frames[id] = f
    elseif f:GetParent() ~= parent then
        f:SetParent(parent)
    end
    -- The game may not have the spell's info yet at login, so keep asking until it
    -- does. With no spell (a trinket slot, a potion) use the item's icon.
    if not f.cooldownInfo.spellID then
        f.cooldownInfo.spellID = Own.SpellOf(id)
        local _, tex = Own.Look(id)
        if type(tex) ~= "nil" then f.Icon:SetTexture(tex) end
    end
    -- Coming back from "Hide out of combat" (Rows set it to 0). The effects set
    -- their own alpha after this.
    f:SetAlpha(1)
    f:Show()
    Own.Update(f)
    return f
end

function Own.ReleaseExcept(used, usedHolds)
    for id, f in pairs(frames) do
        if not used[id] and f:IsShown() then
            if ns.CdmEffects then ns.CdmEffects.Clear(f) end
            f:Hide()
        end
    end
    for key, f in pairs(holds) do
        if not (usedHolds and usedHolds[key]) and f:IsShown() then
            if f.Bar and ns.CdmEffects then ns.CdmEffects.Flash(f, f.Bar, false) end
            f:Hide()
        end
    end
end

-- "Show missing buffs": a stand-in for a buff or bar the game is hiding right now. An
-- icon is the spell's texture grayed; a bar is an empty skinned bar with the name.
function Own.Placeholder(id, parent, kind, bright)
    local key = id .. kind
    local f = holds[key]
    if not f then
        f = CreateFrame("Frame", nil, parent)
        f.Icon = f:CreateTexture(nil, "ARTWORK")
        f.Icon:SetAllPoints()
        f.Icon:SetDesaturated(true)
        f.Icon:SetAlpha(0.5)
        if kind == "bar" then
            f.Bar = CreateFrame("StatusBar", nil, f)
            f.Bar:SetAllPoints()
            f.Bar:SetMinMaxValues(0, 1)
            f.Bar:SetValue(0)
            DUI.Style.TrackBar(f.Bar, nil, ns.MEDIA.bars.cdm)
            -- Our own dark empty bar. The game bars' skin leaves its backdrop
            -- untinted here, and it came out white.
            local back = f.Bar:CreateTexture(nil, "BACKGROUND", nil, -8)
            back:SetAllPoints()
            DUI.Style.TrackBack(back, ns.MEDIA.bars.cdm)
            back:SetVertexColor(0, 0, 0, DUI.Style.BAR_BACK_ALPHA)
            f.Back = back
            DUI.SafeCall(DUI.Style.Shell, f, { borderPx = ns.Cooldowns and ns.Cooldowns.BarBorder or 1,
                heavyMinPx = ns.Cooldowns and ns.Cooldowns.BAR_HEAVY_MIN })
            f.Text = f.Bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            f.Text:SetPoint("LEFT", f.Bar, "LEFT", 4, 0)
            f.Text:SetTextColor(DUI.Style.INK.OFF[1], DUI.Style.INK.OFF[2], DUI.Style.INK.OFF[3])
        end
        if kind == "bar" then
            f.Icon:SetAlpha(0)
        elseif ns.Cooldowns and ns.Cooldowns.SkinItem then
            -- An icon wears the layout's look like our cooldown icons: border,
            -- crop, shade and shape, with the grayed icon inside the border.
            DUI.SafeCall(ns.Cooldowns.SkinItem, f)
        end
        f.placeholder = true
        holds[key] = f
    elseif f:GetParent() ~= parent then
        f:SetParent(parent)
    end
    if not f.set then
        local name, tex = Own.Look(id)
        if type(tex) ~= "nil" then
            f.Icon:SetTexture(tex)
            if kind == "bar" and name then f.Text:SetText(name) end
            f.set = true
        end
    end
    if kind ~= "bar" and (f.bright or false) ~= (bright == true) then
        -- With Hide (Buff up) too, the stand-in is only a reminder, in full color.
        f.bright = bright == true
        f.Icon:SetDesaturated(not f.bright)
        local from, to = f.bright and 0.5 or 1, f.bright and 1 or 0.5
        DUI.Motion.Tween(f.Icon, from, to, DUI.Motion.FAST, function(v) f.Icon:SetAlpha(v) end)
    end
    if kind == "bar" then
        -- The spell's own bar colors, read each time so a change shows.
        local set = ns.CdmData.Current()
        local b = set and set.pieces and set.pieces[id]
        local Fx, S = ns.CdmEffects, DUI.Style
        local mode = Fx.Get(b, "barMode")
        local c = Fx.Get(b, "barColor")
        local pair = Fx.Get(b, "barGradient")
        if mode == "solid" and type(c) == "table" then
            f.Bar:SetStatusBarColor(c[1], c[2], c[3], 1)
        elseif mode == "gradient" and type(pair) == "table" and DUI.Gradients then
            f.Bar:SetStatusBarColor(DUI.Gradients.MidOf(pair.lo, pair.hi))
        else
            f.Bar:SetStatusBarColor(1, 1, 1, 1)
        end
        local back, v
        if ns.Cooldowns then
            back, v = ns.Cooldowns.BackOf(b, b and ns.CdmData.PieceBlock(set, id))
            ns.Cooldowns.OwnBack(S.GetShell(f), back ~= nil)
            ns.Cooldowns.PlaceName(f.Text, f.Bar, Fx.Get(b, "showName") ~= false, Fx.Get(b, "nameAlign") == "center")
        end
        if back then
            ns.Cooldowns.PaintBack(f.Back, back, v)
        else
            f.Back:SetVertexColor(0, 0, 0, S.BAR_BACK_ALPHA)
        end
        Fx.Flash(f, f.Bar, Fx.Get(b, "inactiveFlash") == true)
    end
    f:Show()
    return f
end

function Own.PlaceholderFrame(id, kind) return holds[id .. kind] end

-- Cooldown and charge events: CdmEffects' single pass on the next frame (Fx.Soon)
-- updates our icons too.
