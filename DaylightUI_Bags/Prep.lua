-- Prepares the bag while it's closed. After login, and after changes while it
-- stays closed, layout and slot fills run quietly a couple of ms per idle frame,
-- out of combat. Opening then only fills what's left (Window.FillDirty), so it
-- opens without a hitch.

local _, ns = ...
local DUI = DaylightUI

local Prep = {}
ns.Prep = Prep

Prep.DELAY = 3      -- seconds after the bag is built before background work starts
Prep.BUDGET = 2     -- ms of work per frame (always at least one slot)
Prep.SETTLE = 1     -- seconds of quiet after the last change before work resumes
                    -- (loot and casts come in bursts, this gives one layout and one cooldown pass)

local worker, ready
local settle = 0    -- GetTime() before which work waits
local running       -- set inside Prep.Run so its own re-marks don't restart the wait
-- Bag being filled and its next slot; next slot for the cooldown pass.
local cur = { bag = nil, slot = 1, cd = nil }

local function inCombat() return InCombatLockdown and InCombatLockdown() end

function Prep.Wake()
    if ready and worker and not inCombat() then worker:Show() end
end

-- A bag was marked dirty (nil = all). Restart it if it's the one being filled.
function Prep.Dirtied(f, bag)
    if f == ns.window then
        if bag == nil or bag == cur.bag then cur.bag = nil end
        if not running then settle = GetTime() + Prep.SETTLE end
    end
    Prep.Wake()
end

-- A cooldown changed while closed: restart the cooldown pass.
function Prep.CooldownsDirtied(f)
    if f == ns.window then
        cur.cd = nil
        if not running then settle = GetTime() + Prep.SETTLE end
    end
    Prep.Wake()
end

-- One unit of work on the closed window, stopping at `stop` ms. Returns false
-- when nothing is left.
local function work(f, stop)
    if f.stale then
        if not ns.CanLayout(f) then return false end
        -- Same slots (categories view after loot): lay out again and refill only the
        -- bags whose counts changed, like an open window does (Window.Changed). Never
        -- in combat, the worker stops there.
        local changed = f.set.Sync(f.items)
        ns.Window.Relayout(f, true, not changed)
        cur.cd = nil   -- the slot list may have changed
        return true
    end
    if f.dirtyAll then
        for _, b in ipairs(f.set.List()) do f.dirty[b.id] = true end
        f.dirtyAll = false
    end
    if cur.bag == nil then
        cur.bag, cur.slot = next(f.dirty), 1
        if cur.bag == nil then
            -- Cooldowns, one frame budget at a time. cdDirty stays set until the last
            -- slot, so opening the bag still fills them all.
            if not f.cdDirty then return false end
            cur.cd = cur.cd or 1
            local slots = f.set.Slots()
            repeat
                local s = slots[cur.cd]
                if not s then
                    cur.cd, f.cdDirty = nil, false
                    return true
                end
                ns.Items.FillCooldown(s.button, true)   -- empty slot, Fill already cleared it
                cur.cd = cur.cd + 1
            until debugprofilestop() >= stop
            return true
        end
    end
    local bag = cur.bag
    repeat
        local btn = f.set.Button(bag, cur.slot)
        if not btn then
            f.dirty[bag], cur.bag = nil, nil
            return true
        end
        ns.Items.Fill(btn)
        cur.slot = cur.slot + 1
    until cur.bag ~= bag or debugprofilestop() >= stop
    return true
end

-- One frame of work. Returns false once the window is ready.
function Prep.Run(f)
    local stop, more = debugprofilestop() + Prep.BUDGET, true
    running = true
    repeat more = work(f, stop) until not more or debugprofilestop() >= stop
    running = false
    return more
end

-- Hooked up once the bag window exists.
function Prep.Start(f)
    if worker then return end
    worker = CreateFrame("Frame")
    worker:Hide()
    Prep.worker = worker
    worker:SetScript("OnUpdate", function(self)
        local w = ns.window
        if not w or w:IsShown() or inCombat() then self:Hide() return end
        if GetTime() < settle then return end   -- more changes may be coming
        if not Prep.Run(w) then self:Hide() end
    end)
    -- On show, OnShow fills the rest. On hide, pick up anything marked meanwhile.
    f:HookScript("OnShow", function() cur.bag, cur.cd = nil, nil end)
    f:HookScript("OnHide", Prep.Wake)
    DUI.RegisterEvent("PLAYER_REGEN_ENABLED", Prep.Wake)
    -- Stay out of the login burst.
    C_Timer.After(Prep.DELAY, function()
        ready = true
        Prep.Wake()
    end)
end
