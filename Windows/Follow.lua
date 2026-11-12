-- Replaces a game window with one of ours without touching the game's code.
-- The game's window is reparented ("parked") under a hidden frame, so every
-- way of opening and closing it still runs the game's own code, just out of
-- sight. A frame under a hidden parent gets no OnShow/OnHide, so we poll
-- IsShown every frame and report changes.
--
--   Win.Follow({ key = "npc", frames = { gossip = function() return GossipFrame end, ... },
--                width = function() return 400 end,          -- panel width our window takes
--                changed = function(kind, shown) ... end,    -- a game window was shown or hidden
--                onPark = function(kind, frame, parked) ... end })  -- optional: parked (true) or given back
--                pin = function(kind, frame) ... end      -- optional: each poll while parked and shown, out of combat
--
-- Parking only happens out of combat. Until then the game's own window shows
-- instead. Load-on-demand addons (the trainer) are parked as they load.
--
-- def.veil = { kind = true } parks under the veil instead: shown, alpha 0 and
-- clipped to a pixel off screen. Needed for windows that check IsVisible as
-- they open (the trainer closes itself otherwise).
-- Follow.Lend gives a shown window back for a while (Beast Training) and it is
-- parked again once hidden. Follow.Unpark hands a hidden window back right as
-- combat starts, so the game's window can open untainted in the fight.
--
-- Another addon (TradeSkillMaster's vendor, say) may take over a parked window
-- by moving it off screen, shrinking it, or reparenting it. That reads as
-- changed(kind, false, true): ours closes but leaves the game's session open.
-- If it is given back, changed(kind, true).

local _, DUI = ...

local Win = DUI.Win

local Follow = {}
Win.Followers = Follow

Follow.hidden = CreateFrame("Frame", nil, UIParent)   -- child of UIParent so parked windows keep their scale and position
Follow.hidden:Hide()
Follow.veil = CreateFrame("Frame", nil, UIParent)
Follow.veil:SetSize(1, 1)
Follow.veil:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", -64, -64)
Follow.veil:SetAlpha(0)
Follow.veil:SetClipsChildren(true)
Follow.veil:EnableMouse(false)
Follow.GAP = 20   -- space between our window and the next game window
Follow.AWAY = 10000    -- offsets this large mean the window was moved off screen on purpose
Follow.SHRUNK = 0.01   -- scales below this mean the window was shrunk away

local list = {}

local function frameOf(def, kind)
    local get = def.frames[kind]
    local f = get and get()
    return type(f) == "table" and f or nil
end

-- Tell the game's panel layout how wide our window is so the next panel opens
-- beside it. The game sets this in an OnShow that never runs while parked.
-- In combat this is blocked (ADDON_ACTION_BLOCKED on SetAttributeNoHandler,
-- which pcall doesn't catch), so it waits until after combat.
local function writeWidth(def, f)
    if not def.width or type(SetUIPanelAttribute) ~= "function" then return end
    if InCombatLockdown() then
        DUI.AfterCombat(function() Follow.WriteWidth(def) end, "follow:width:" .. def.key)
        return
    end
    pcall(SetUIPanelAttribute, f, "width", math.floor(def.width() + Follow.GAP + 0.5))
end

-- Restore the game's own panel width (from UIPanelWindows, or nil for the
-- frame's own width) so it doesn't keep ours.
local function giveBack(def, kind, f)
    f:SetParent(UIParent)
    def.parked[kind] = nil
    if DUI.Pad then DUI.Pad.Remember(f) end
    if def.width and type(SetUIPanelAttribute) == "function" then
        local own = type(UIPanelWindows) == "table" and UIPanelWindows[f:GetName() or ""]
        pcall(SetUIPanelAttribute, f, "width", type(own) == "table" and own.width or nil)
    end
    if def.onPark then DUI.SafeCall(def.onPark, kind, f, false) end
end

local function park(def)
    for kind in pairs(def.frames) do
        local f = frameOf(def, kind)
        if f and not def.parked[kind] and not f:IsShown() and not (def.lent and def.lent[kind]) then
            f:SetParent(def.veil and def.veil[kind] and Follow.veil or Follow.hidden)
            def.parked[kind] = true
            writeWidth(def, f)
            if def.onPark then DUI.SafeCall(def.onPark, kind, f, true) end
        end
    end
end

-- Temporarily hand a parked, shown window back to the game. Out of combat
-- only. It gets parked again once it hides.
function Follow.Lend(def, kind)
    local f = frameOf(def, kind)
    if not (f and def.parked[kind]) then return false end
    if InCombatLockdown() then return false end
    def.lent[kind] = true
    giveBack(def, kind, f)
    return true
end

-- Re-park a lent window while it is still shown, e.g. when a lent profession
-- overview turns into a recipe list. Veil only: a hidden parent would fire its
-- OnHide and close the trade skill. Out of combat only.
function Follow.Reclaim(def, kind)
    local f = frameOf(def, kind)
    if not (f and def.lent[kind] and def.veil and def.veil[kind]) then return false end
    if InCombatLockdown() or not f:IsShown() then return false end
    def.lent[kind] = nil
    f:SetParent(Follow.veil)
    def.parked[kind] = true
    writeWidth(def, f)
    if def.onPark then DUI.SafeCall(def.onPark, kind, f, true) end
    return true
end

-- Hand a parked, hidden window back for the fight about to start. Called from
-- PLAYER_REGEN_DISABLED, where InCombatLockdown may already return true, so it
-- doesn't check. A shown window stays parked until it closes.
function Follow.Unpark(def, kind)
    local f = frameOf(def, kind)
    if not (f and def.parked[kind]) or f:IsShown() then return false end
    giveBack(def, kind, f)
    return true
end

function Follow.Parked(def, kind) return def.parked[kind] == true end

local function plain(v) return type(v) == "number" and not (issecretvalue and issecretvalue(v)) end

-- Has another addon taken this parked, shown window?
function Follow.Away(def, kind)
    local f = frameOf(def, kind)
    if not (f and def.parked[kind]) then return false end
    if f:GetParent() ~= (def.veil and def.veil[kind] and Follow.veil or Follow.hidden) then return true end
    local scale = f:GetScale()
    if plain(scale) and scale < Follow.SHRUNK then return true end
    local _, _, _, x, y = f:GetPoint(1)
    return (plain(x) and math.abs(x) >= Follow.AWAY) or (plain(y) and math.abs(y) >= Follow.AWAY) or false
end
function Follow.Shown(def, kind) return def.shown[kind] == true end

-- Runs every frame while anything is followed.
function Follow.Tick()
    for _, def in ipairs(list) do
        local need = false
        for kind in pairs(def.frames) do
            local f = frameOf(def, kind)
            local on = f ~= nil and def.parked[kind] == true and f:IsShown() == true
            local away = on and Follow.Away(def, kind)
            if away then on = false end
            if on ~= (def.shown[kind] == true) then
                def.shown[kind] = on
                if def.changed then DUI.SafeCall(def.changed, kind, on, away) end
            end
            if on and DUI.Pad then DUI.Pad.KeepOff(f) end   -- keep gamepad focus off the hidden window
            -- Game windows are protected in combat, so pinning waits.
            if on and def.pin and not InCombatLockdown() then def.pin(kind, f) end
            if f and def.lent[kind] and not f:IsShown() then def.lent[kind] = nil end
            if f and not def.parked[kind] then need = true end
        end
        if need then DUI.AfterCombat(def.parkFn, def.parkKey) end
    end
end

local watcher = CreateFrame("Frame")
watcher:Hide()
watcher:SetScript("OnUpdate", function() Follow.Tick() end)
Follow.watcher = watcher

-- A load-on-demand addon's windows exist now and aren't shown yet.
DUI.RegisterEvent("ADDON_LOADED", function()
    if InCombatLockdown() then return end
    for _, def in ipairs(list) do park(def) end
end)

function Win.Follow(def)
    def.parked, def.shown, def.lent = {}, {}, {}
    -- Built once. Tick queues this every frame in combat while a window is
    -- unparked, and a fresh closure and string each time would be garbage.
    def.parkFn = function() park(def) end
    def.parkKey = "follow:" .. def.key
    list[#list + 1] = def
    DUI.AfterCombat(def.parkFn, def.parkKey)
    watcher:Show()
    return def
end

-- Call when our window is resized or rescaled.
function Follow.WriteWidth(def)
    for kind in pairs(def.frames) do
        local f = frameOf(def, kind)
        if f and def.parked[kind] then writeWidth(def, f) end
    end
end
