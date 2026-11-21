-- Replaces a game window with a Daylight UI one without touching the game's code.
-- The game's window is reparented ("parked") under a hidden frame, so every
-- way of opening and closing it still runs the game's own code, just out of
-- sight. A frame under a hidden parent gets no OnShow/OnHide, so this polls
-- IsShown every frame and report changes.
--
--   Win.Follow({ key = "npc", frames = { gossip = function() return GossipFrame end, ... },
--                width = function() return 400 end,          -- panel width the window takes
--                changed = function(kind, shown) ... end,    -- a game window was shown or hidden
--                onPark = function(kind, frame, parked) ... end })  -- optional: parked (true) or given back
--                pin = function(kind, frame) ... end      -- optional: each poll while parked and shown, out of combat
--                leave = function(kind) ... end    -- optional: true leaves that window the game's (the player picked it)
--
-- Parking only happens out of combat. Until then the game's own window shows
-- instead. Load-on-demand addons (the trainer) are parked as they load.
--
-- def.aside = { kind = true } parks under the aside holder instead: shown, but
-- see-through and tiny, and never clipped. Needed for windows that check
-- IsVisible as they open (the trainer closes itself otherwise) or end their
-- session in OnHide. The window then takes the game's spot with Follow.PlaceOn,
-- since the parked frame itself is a dot in the corner. def.veil (the same, but
-- clipped to a pixel off screen) is on its way out.
-- Follow.Lend gives a shown window back for a while (Beast Training) and it is
-- parked again once hidden. Follow.Unpark hands a hidden window back right as
-- combat starts, so the game's window can open untainted in the fight.
--
-- Another addon (TradeSkillMaster's vendor, say) may take over a parked window
-- by moving it off screen, shrinking it, or reparenting it. That reads as
-- changed(kind, false, true): the Daylight UI window closes but leaves the game's session open.
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
-- Windows that must stay really shown (the trainer closes itself unless it is
-- visible, others end their session in OnHide) wait here: see-through, and
-- small enough that nothing in them can be clicked. Never a clipping frame.
Follow.ASIDE_SCALE = 0.001
Follow.aside = CreateFrame("Frame", nil, UIParent)
Follow.aside:SetSize(1, 1)
Follow.aside:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
Follow.aside:SetAlpha(0)
Follow.aside:SetScale(Follow.ASIDE_SCALE)
Follow.aside:EnableMouse(false)
Follow.GAP = 20   -- space between the window and the next game window
Follow.AWAY = 10000    -- offsets this large mean the window was moved off screen on purpose
Follow.SHRUNK = 0.01   -- scales below this mean the window was shrunk away

local list = {}

local function plain(v) return type(v) == "number" and not DUI.IsSecret(v) end

local function homeOf(def, kind)
    if def.aside and def.aside[kind] then return Follow.aside end
    if def.veil and def.veil[kind] then return Follow.veil end
    return Follow.hidden
end

local function frameOf(def, kind)
    local get = def.frames[kind]
    local f = get and get()
    return type(f) == "table" and f or nil
end

-- The game opens its next window beside the open one, as far over as that
-- one's width (GetUIPanelWidth): its "width" layout attribute if it has one,
-- else the frame's own width. Daylight UI never writes layout attributes. An
-- attribute keeps the taint of whoever wrote it, so the game's next ShowUIPanel
-- read it back and ran tainted, and in a fight it was then blocked from what it
-- did next (the spellbook's action bar grids). Sizing the parked frame itself
-- leaves nothing tainted behind. A window with a layout width of its own is
-- left alone, since the game reads that and not the frame.
local function ownWidth(f)
    local own = type(UIPanelWindows) == "table" and UIPanelWindows[f:GetName() or ""]
    if type(own) == "table" and own.width ~= nil then return true end
    return type(f.GetAttribute) == "function" and f:GetAttribute("UIPanelLayout-width") ~= nil
end

-- Out of combat only, since another addon may have put secure buttons in it.
local function writeWidth(def, f, kind)
    if not def.width or ownWidth(f) then return end
    if InCombatLockdown() then
        DUI.AfterCombat(function() Follow.WriteWidth(def) end, "follow:width:" .. def.key)
        return
    end
    if def.home[kind] == nil then
        local w = f:GetWidth()
        if not plain(w) then return end
        def.home[kind] = w
    end
    f:SetWidth(math.floor(def.width() + Follow.GAP + 0.5))
end

-- The game's own width back, before it shows the window as itself.
local function restoreWidth(def, kind, f)
    local w = def.home[kind]
    if w == nil then return end
    if InCombatLockdown() and f:IsProtected() then
        DUI.AfterCombat(function()
            if not def.parked[kind] or Follow.Away(def, kind) then restoreWidth(def, kind, f) end
        end, "follow:home:" .. def.key .. kind)
        return
    end
    def.home[kind] = nil
    f:SetWidth(w)
end

local function giveBack(def, kind, f)
    f:SetParent(UIParent)
    def.parked[kind] = nil
    if DUI.Pad then DUI.Pad.Remember(f) end
    restoreWidth(def, kind, f)
    if def.onPark then DUI.SafeCall(def.onPark, kind, f, false) end
    DUI.Fire("GameWindowBack", def.key, kind, f)   -- the skins dress it now it shows as itself
end

local function park(def)
    for kind in pairs(def.frames) do
        local f = frameOf(def, kind)
        if f and not def.parked[kind] and not f:IsShown() and not (def.lent and def.lent[kind])
            and not (def.leave and def.leave(kind)) then
            f:SetParent(homeOf(def, kind))
            def.parked[kind] = true
            writeWidth(def, f, kind)
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

-- Park a window while it is still shown: a lent profession overview that turns
-- into a recipe list, or one the player switches back from the game's look. Aside
-- or veil only: a hidden parent would fire its OnHide and close the trade skill. Out of
-- combat only.
function Follow.Reclaim(def, kind)
    local f = frameOf(def, kind)
    if not (f and not def.parked[kind] and homeOf(def, kind) ~= Follow.hidden) then return false end
    if InCombatLockdown() or not f:IsShown() then return false end
    def.lent[kind] = nil
    f:SetParent(homeOf(def, kind))
    def.parked[kind] = true
    writeWidth(def, f, kind)
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

-- The player picked the game's window: a parked one goes back for good, lent if
-- it's open (Daylight UI's closes), else simply let go. Out of combat only.
function Follow.Release(def, kind)
    local f = frameOf(def, kind)
    if not (f and def.parked[kind]) or InCombatLockdown() then return false end
    if f:IsShown() then return Follow.Lend(def, kind) end
    giveBack(def, kind, f)
    return true
end

function Follow.Parked(def, kind) return def.parked[kind] == true end

-- Has another addon taken this parked, shown window?
function Follow.Away(def, kind)
    local f = frameOf(def, kind)
    if not (f and def.parked[kind]) then return false end
    if f:GetParent() ~= homeOf(def, kind) then return true end
    local scale = f:GetScale()
    if plain(scale) and scale < Follow.SHRUNK then return true end
    local _, _, _, x, y = f:GetPoint(1)
    return (plain(x) and math.abs(x) >= Follow.AWAY) or (plain(y) and math.abs(y) >= Follow.AWAY) or false
end
-- Where the game placed g's top-left corner, as offsets from UIParent's top
-- left in UIParent units, whatever g's parent is. Read from its anchor, since a
-- parked frame's own position is the holder's corner. Nil when it hangs on
-- another frame or a number can't be read.
local function share(name, a, b)
    if name:find(a) then return 0 end
    if name:find(b) then return 1 end
    return 0.5
end

function Follow.Home(g)
    local point, rel, relPoint, x, y = g:GetPoint(1)
    if point == nil or (rel ~= nil and rel ~= UIParent) then return nil end
    local s, w, h = g:GetScale(), g:GetWidth(), g:GetHeight()
    if not (plain(x) and plain(y) and plain(s) and plain(w) and plain(h)) then return nil end
    relPoint = relPoint or point
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local left = share(relPoint, "LEFT", "RIGHT") * W + x * s - share(point, "LEFT", "RIGHT") * w * s
    local top = -share(relPoint, "TOP", "BOTTOM") * H + y * s + share(point, "TOP", "BOTTOM") * h * s
    return left, top
end

-- Put f's top-left corner where the game placed g.
function Follow.PlaceOn(f, g)
    local x, y = Follow.Home(g)
    if not x then return false end
    local s = f:GetScale()
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x / s, y / s)
    return true
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
                -- Another addon showing it as itself gets it at the game's width.
                if away then restoreWidth(def, kind, f) elseif on then writeWidth(def, f, kind) end
                if def.changed then DUI.SafeCall(def.changed, kind, on, away) end
            end
            if on and DUI.Pad then DUI.Pad.KeepOff(f) end   -- keep gamepad focus off the hidden window
            -- Game windows are protected in combat, so pinning waits.
            if on and def.pin and not InCombatLockdown() then def.pin(kind, f) end
            if f and def.lent[kind] and not f:IsShown() then def.lent[kind] = nil end
            if f and not def.parked[kind] and not (def.leave and def.leave(kind)) then need = true end
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
    def.parked, def.shown, def.lent, def.home = {}, {}, {}, {}
    -- Built once. Tick queues this every frame in combat while a window is
    -- unparked, and a fresh closure and string each time would be garbage.
    def.parkFn = function() park(def) end
    def.parkKey = "follow:" .. def.key
    list[#list + 1] = def
    DUI.AfterCombat(def.parkFn, def.parkKey)
    watcher:Show()
    return def
end

-- Call when the window is resized or rescaled.
function Follow.WriteWidth(def)
    for kind in pairs(def.frames) do
        local f = frameOf(def, kind)
        if f and def.parked[kind] then writeWidth(def, f, kind) end
    end
end
