-- Procs only the game can see (Redoubt, Vengeance, Rapid Killing...): nothing
-- an addon can read changes when they land, and their buff is hidden from
-- addons in a fight. The client's aura container can still show a frame of
-- Daylight UI's while a given buff is on the player, in a fight too: each such
-- proc gets a slot whose button carries its painted flare. Daylight UI never
-- learns when it shows, so these play no sound and hold their lane always.
--
-- The client locks its aura buttons, and everything made on them, once
-- initializeFrame returns whenever auras are secret (a fight, a boss, a PvP
-- match). So every texture and animation is made inside initializeFrame, and
-- a later change of look waits for DUI.AfterRestrictions.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Game = { slots = {}, spots = {} }
ns.Game = Game

local container, broken
-- Set by the fight's own events: PLAYER_REGEN_DISABLED comes just before the lockdown.
local inCombat = InCombatLockdown() == true
local SLOT = "DaylightUIProcs_%s_%d"

local function procs()
    local out = {}
    for _, p in ipairs(ns.Data.Mine()) do
        if p.mode == "aura" and #(p.buffIds or {}) > 0 then out[#out + 1] = p end
    end
    return out
end

local function moduleOn() return DUI:Get("Procs", "enabled") ~= false end

-- The client looks a buff up by its id as a key (includeSpellIDs[spellId]),
-- so a plain list of ids would match no buff at all.
local function idSet(list)
    local out = {}
    for _, id in ipairs(list) do out[id] = true end
    return out
end

-- A slot's brightness: the lowest one shown carries the stack count's whole
-- look; each one above adds what one more stack brings, so the pile the
-- client shows reads as the current count.
local function dimOf(p, n)
    if not p.stacks then return 1 end
    local from = ns.Alerts.Get(p.key, "fromStacks") or p.stacks
    if n == from then return 0.45 + 0.55 * n / p.stacks end
    return 0.55 / p.stacks
end

-- Places, paints and hands the client the loop of one slot. Only inside
-- initializeFrame or once restrictions have lifted.
local function style(p, slot)
    slot.design = ns.Alerts.Get(p.key, "design")
    local d = ns.Data.DESIGNS[slot.design]
    slot.spot = d and d.spot or "side"
    slot.dim = dimOf(p, slot.n)
    slot.anim = ns.Alerts.Get(p.key, "anim")
    ns.Flares.Layout(slot, 1)
    ns.Flares.Paint(slot)
    local btn = slot.button
    btn:ClearAuraShownAnimations()
    local shown = ns.Data.SPOTS[slot.spot].mirrored and 2 or 1
    local moving = ns.Flares.Moving(slot)
    local anim = moving and slot.anim or "still"
    local kind = ns.Flares.KINDS[anim]
    local speed = ns.Alerts.Get(p.key, "speed")
    for i = 1, shown do
        local part = slot.parts[i]
        ns.Flares.SetSpeed(part, speed, kind and kind.live)
        -- The client shows these with the button and plays their groups.
        local embers = moving and ns.Flares.Embers(p.key)
        part.liveTex:SetShown(moving)
        part.emberTex:SetShown(embers)
        for _, g in ipairs(ns.Flares.LoopsOf(part, anim)) do
            if g ~= part.embers or embers then btn:AddAuraShownAnimation(g) end
        end
    end
    -- GUESS: the client plays a non-looping group it was handed once each time
    -- the buff shows. Impact's sparks again (burst.again) are left out: started
    -- with the rest, they would cut into the first spray.
    if moving then btn:AddAuraShownAnimation(slot.burst.group) end
    slot.body:SetAlpha(ns.Flares.Opacity(p.key))
end

local function build(p, n, btn)
    local slot = Game.slots[p.key][n]
    slot.button = btn
    btn:ClearAllPoints()
    btn:SetAllPoints(container)
    btn:EnableMouse(false)
    -- A stacking proc's light lives in a bar the client shows from n stacks up.
    local body
    if p.stacks then
        body = CreateFrame("StatusBar", nil, btn)
        btn:SetApplicationBar(body, { minApplications = n, maxApplications = p.stacks })
        slot.bar = body
    else
        body = CreateFrame("Frame", nil, btn)
    end
    body:SetAllPoints(btn)
    slot.body, slot.rel = body, btn
    slot.parts = { ns.Flares.NewPart(body), ns.Flares.NewPart(body) }
    slot.burst = ns.Flares.NewBurst(body)
    -- Never a strike or a burn here: Daylight UI doesn't learn when it shows.
    slot.reveal = 1
    style(p, slot)
end

local function newContainer()
    -- The client refuses an AuraContainer it doesn't know: a read that may fail on purpose.
    local ok, c = pcall(CreateFrame, "AuraContainer", "DaylightUIProcsAuras", UIParent, "CustomAuraContainerTemplate")
    if not ok or not c then
        broken = true
        DUI.Print(L["Proc Alerts: this client has no aura container, so procs only the game can see (like Redoubt) can't show."])
        return nil
    end
    c:SetUnit("player")
    c:EnableMouse(false)
    c:SetAllPoints(ns.Flares.holder)
    return c
end

-- Which slots the client may show now.
function Game.Sync()
    if not container then return end
    for _, p in ipairs(procs()) do
        local on = moduleOn() and ns.Alerts.Get(p.key, "enabled") ~= false
            and not (ns.Alerts.Get(p.key, "combatOnly") and not inCombat)
        local from = p.stacks and (ns.Alerts.Get(p.key, "fromStacks") or p.stacks) or 1
        local d = ns.Data.DESIGNS[ns.Alerts.Get(p.key, "design")]
        local spot = d and d.spot or "side"
        local held = moduleOn() and ns.Alerts.Get(p.key, "enabled") ~= false
        for n, slot in pairs(Game.slots[p.key] or {}) do
            local want = on and n >= from
            if slot.enabled ~= want then
                slot.enabled = want
                -- A container call (never the locked button): fine in a fight.
                DUI.SafeCall(container.SetAuraSlotEnabled, container, slot.skey, want)
            end
        end
        -- Its lane is held while it may show, at its design's spot.
        local had = Game.spots[p.key]
        if had and (had ~= spot or not held) then ns.Flares.FreeLane(had, p.key) end
        Game.spots[p.key] = nil
        if held and Game.slots[p.key] then
            local lane = ns.Flares.TakeLane(spot, p.key)
            for _, slot in pairs(Game.slots[p.key]) do slot.lane = lane end
            Game.spots[p.key] = spot
        end
    end
end

-- A proc's look changed (design, size, colors, animation): its buttons are
-- restyled once nothing locks them.
function Game.Restyle(key)
    local list = Game.slots[key]
    if not list then return end
    DUI.AfterRestrictions(function()
        local p = ns.Data.BY[key]
        for _, slot in pairs(list) do
            if slot.button then DUI.SafeCall(style, p, slot) end
        end
    end, "procs:game:" .. key)
end

function Game.RestyleAll()
    for key in pairs(Game.slots) do Game.Restyle(key) end
end

local function setup()
    if broken or not ns.Flares.holder then return end
    container = container or newContainer()
    if not container then return end
    for _, p in ipairs(procs()) do
        if not Game.slots[p.key] then
            local list = {}
            Game.slots[p.key] = list
            local d = ns.Data.DESIGNS[ns.Alerts.Get(p.key, "design")]
            local lane = ns.Flares.TakeLane(d and d.spot or "side", p.key)
            Game.spots[p.key] = d and d.spot or "side"
            for n = 1, p.stacks or 1 do
                local slot = { key = p.key, n = n, lane = lane, skey = string.format(SLOT, p.key, n), enabled = true, frac = 1 }
                list[n] = slot
                local ok = DUI.SafeCall(container.AddAuraSlot, container, slot.skey, "HELPFUL", {
                    initializeFrame = function(btn) DUI.SafeCall(build, p, n, btn) end,
                    candidateFilters = { includeSpellIDs = idSet(p.buffIds) },
                })
                if not ok then list[n] = nil end
            end
        end
    end
    Game.Sync()
end

function Game.Setup()
    DUI.AfterRestrictions(setup, "procs:game:setup")
end

DUI.On("SettingChanged", function(scope)
    if scope ~= "Procs" or not container then return end
    Game.Sync()
    Game.RestyleAll()
end)
DUI.On("StyleChanged", function() if container then Game.RestyleAll() end end)
DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function() inCombat = true; Game.Sync() end)
DUI.RegisterEvent("PLAYER_REGEN_ENABLED", function() inCombat = false; Game.Sync() end)
