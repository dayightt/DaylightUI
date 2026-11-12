-- The ready ping: a button coming off a real cooldown (not the global one) pops its
-- icon and lights it up once. Visual only, using the icon's scale animation and a
-- flash texture; the secure button itself is never touched.
--
-- What counts as real (tested in combat): C_Spell.GetSpellCooldown's isOnGCD is
-- plain, true on the GCD and absent on a real cooldown. The action's own copy
-- (C_ActionBar) is gone in combat, so it's only a fallback for actions that aren't a
-- spell (items), which may ping after a GCD in combat. Right after a cast the GCD
-- can show before the real cooldown, so "a real one was seen" is remembered until
-- the ping.

local _, ns = ...
local DUI = DaylightUI

local Ping = {}
ns.Ping = Ping

Ping.SCALE = 1.15        -- the icon pops from this back to 1
Ping.FLASH_ALPHA = 0.7   -- starting brightness of the flash

local function enabled()
    return not (type(ns.db) == "table" and ns.db.readyPing == false)
end

local function plain(v)
    if type(issecretvalue) == "function" and issecretvalue(v) then return nil end
    return v
end

-- The flash and the hooks, once per button (made out of combat at login).
function Ping.Setup(btn)
    local st = ns.Buttons.State(btn)
    if st.pingFlash then return end
    local flash = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    -- The icon's own picture added on top, so it brightens in its own colors rather
    -- than going under a flat white square.
    flash:SetBlendMode("ADD")
    flash:SetVertexColor(1, 1, 1, Ping.FLASH_ALPHA)
    if type(btn.icon) == "table" then flash:SetAllPoints(btn.icon) else flash:SetAllPoints(btn) end
    flash:Hide()
    st.pingFlash = flash
    if type(btn.cooldown) == "table" then
        btn.cooldown:HookScript("OnCooldownDone", function() Ping.Done(btn) end)
    end
    if type(btn.chargeCooldown) == "table" then
        btn.chargeCooldown:HookScript("OnCooldownDone", function() Ping.ChargeDone(btn) end)
    end
end
DUI.On("ActionButtonMade", Ping.Setup)

-- A wand shot (Shoot, or any auto-repeat shot except the hunter's Auto Shot) puts
-- every spell on a cooldown as long as the weapon speed, and the game doesn't call
-- that the GCD. Read as real, every button pinged after it. So nothing counts as
-- real until the shot's lockout is over, and a repaint then catches a real cooldown
-- that started under it. Erring long only delays the ping.
Ping.AUTO_SHOT = 75
Ping.LOCK_MIN = 2.1      -- seconds, minimum (GreyOnCooldown Classic uses 2.01 for wands)
Ping.LOCK_UNKNOWN = 3    -- seconds, when the ranged speed can't be read
Ping.LOCK_PAD = 0.3      -- seconds past a slow wand's speed, since its cooldown starts a moment after the cast event
Ping.lockUntil = 0
local REPAINT = { cooldown = true }

function Ping.Shot(spellID)
    if type(spellID) ~= "number" or spellID == Ping.AUTO_SHOT then return end
    local repeats = (C_Spell and C_Spell.IsAutoRepeatSpell) or _G.IsAutoRepeatSpell
    if type(repeats) ~= "function" then return end
    local ok, on = pcall(repeats, spellID)
    if not ok or plain(on) ~= true then return end
    local speed = type(UnitRangedDamage) == "function" and plain((UnitRangedDamage("player")))
    local hold = type(speed) == "number" and math.max(speed + Ping.LOCK_PAD, Ping.LOCK_MIN) or Ping.LOCK_UNKNOWN
    Ping.shotAt = GetTime()
    Ping.lockUntil = Ping.shotAt + hold
    C_Timer.After(hold + 0.05, function() ns.Buttons.QueuePaint(REPAINT) end)
end

local events = CreateFrame("Frame")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:SetScript("OnEvent", function(_, _, _, _, spellID)
    if type(issecretvalue) == "function" and issecretvalue(spellID) then return end
    DUI.SafeCall(Ping.Shot, spellID)
end)

-- A spell cooldown (C_Spell.GetSpellCooldown's table) that's only the last wand
-- shot's lockout: it began with the shot and ends inside it. A cooldown from before
-- the shot, or longer than it, is real. Returns false when secret.
Ping.SHOT_SLACK = 0.15   -- seconds between the shot's event and the cooldown's start
function Ping.IsShotCooldown(info)
    if type(info) ~= "table" or not Ping.shotAt or GetTime() >= Ping.lockUntil then return false end
    local start, d = plain(info.startTime), plain(info.duration)
    if type(start) ~= "number" or type(d) ~= "number" then return false end
    return start >= Ping.shotAt - Ping.SHOT_SLACK and start + d <= Ping.lockUntil + Ping.SHOT_SLACK
end

-- In a fight a cooldown's start and duration are secret, so inside a shot's lockout
-- it can't be told apart from a real one. The caller goes by what it knew before
-- the shot (CdmEffects).
function Ping.ShotBlind(info)
    if type(info) ~= "table" or not Ping.shotAt or GetTime() >= Ping.lockUntil then return false end
    return type(plain(info.startTime)) ~= "number" or type(plain(info.duration)) ~= "number"
end

-- Is the cooldown on this slot a real one? info = the action's cooldown.
function Ping.Real(slot, info)
    if GetTime() < Ping.lockUntil then return false end
    local id = ns.Buttons.SpellOf(slot)
    local S = C_Spell
    if type(id) == "number" and type(S) == "table" and type(S.GetSpellCooldown) == "function" then
        local cd = S.GetSpellCooldown(id)
        if type(cd) == "table" then return cd.isActive == true and plain(cd.isOnGCD) ~= true end
    end
    return type(info) == "table" and info.isActive == true and plain(info.isOnGCD) ~= true
end

-- Called from the cooldown painter after the sweeps (Buttons.lua). info and charges
-- are the action's cooldown and charges as the painter read them.
function Ping.Note(btn, slot, info, charges)
    local st = ns.Buttons.State(btn)
    if st.pingSlot ~= slot then
        st.pingSlot, st.realCD, st.chargeSeen = slot, false, false
    end
    -- Check isActive, not the painter's "shown": loss of control hides a cooldown
    -- that's still running.
    if type(info) == "table" and info.isActive == true then
        if not st.realCD and Ping.Real(slot, info) then st.realCD = true end
    elseif st.realCD then
        Ping.Fire(btn)   -- ready (or reset) before the sweep finished
    end
    if type(charges) == "table" and charges.isActive == true then st.chargeSeen = true end
    ns.Skin.SetCooling(btn, st.realCD)
end

-- The sweep ran out. An idle sweep's Clear can land here too; the flags keep that
-- quiet.
function Ping.Done(btn)
    if ns.Buttons.State(btn).realCD then Ping.Fire(btn) end
end

-- A charge came back.
function Ping.ChargeDone(btn)
    local st = ns.Buttons.State(btn)
    if not st.chargeSeen then return end
    st.chargeSeen = false
    Ping.Fire(btn)
end

function Ping.Fire(btn)
    local st = ns.Buttons.State(btn)
    st.realCD = false
    ns.Skin.SetCooling(btn, false)
    if not enabled() then return end
    Ping.Light(btn, Ping.SCALE)
end

-- The light-up itself: the icon pops from `scale` and its copy flashes on top.
function Ping.Light(btn, scale)
    local M = DUI.Motion
    if type(M) ~= "table" then return end
    Ping.Setup(btn)
    local icon, flash = btn.icon, ns.Buttons.State(btn).pingFlash
    if type(icon) == "table" then
        flash:SetTexture(icon:GetTexture())
        local a, b, c, d, e, f, g, h = icon:GetTexCoord()
        if type(a) == "number" then flash:SetTexCoord(a, b, c, d, e, f, g, h) end
        M.Bump(icon, scale, M.NORMAL)
        M.Bump(flash, scale, M.NORMAL)   -- the copy pops with it
    end
    M.Flash(flash, M.SLOW)
end

-- The login reveal (Fade.Reveal): each shown bar's buttons light up one after another
-- as the ripple reaches the bar, softer than a ping. Empty slots stay dark. A fight
-- starting stops it, since fight info comes first.
Ping.WAVE_STEP = 0.03    -- seconds between one button and the next
Ping.WAVE_SCALE = 1.08
function Ping.Wave()
    local M = DUI.Motion
    if type(M) ~= "table" or not M.On() then return end
    local Bars = ns.Bars
    for _, def in ipairs(Bars.DEFS) do
        local holder, list = Bars.holders[def.key], Bars.buttons[def.key]
        if holder and list and holder:IsVisible() then
            local at = (DUI.Fade.RippleDelay(holder) or 0) + M.FAST
            for i, btn in ipairs(list) do
                C_Timer.After(at + (i - 1) * Ping.WAVE_STEP, function()
                    if InCombatLockdown() or not btn:IsVisible() then return end
                    local icon = btn.icon
                    if type(icon) ~= "table" or not icon:IsShown() or type(icon:GetTexture()) == "nil" then return end
                    Ping.Light(btn, Ping.WAVE_SCALE)
                end)
            end
        end
    end
end
DUI.On("LoginReveal", function() Ping.Wave() end)
