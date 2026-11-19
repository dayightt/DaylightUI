-- Keeps this window in step with the game's CharacterFrame. The game's frame is
-- parked under a hidden parent, so every way of opening it (keybinds, micro
-- button, other addons, Escape) still runs the game's own code, just out of
-- sight. This window shows while that one is open, on the same page. A frame
-- under a hidden parent never gets OnShow, so it's polled with one IsShown per frame.
--
-- The X and tabs go through ToggleCharacter so the two can't disagree. In combat
-- the game refuses HideUIPanel from addons, so the X fades this window at once
-- and closes the game's after combat.

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char

local Follow = {}
ns.Follow = Follow

-- Parented to UIParent so the parked window keeps its scale and position.
Follow.hidden = CreateFrame("Frame", nil, UIParent)
Follow.hidden:Hide()
Follow.parked = false
-- State held while the game's window can't follow (closed with the X in combat).
Follow.override = nil
-- True while the player picked the game's own window: it's never parked then.
Follow.given = false

function Follow.Game() return type(CharacterFrame) == "table" and CharacterFrame or nil end

function Follow.PageOfFrame(name)
    for _, p in ipairs(ns.Window.PAGES) do if p.frame == name then return p.id end end
end

-- Whether the game offers this page for this character. It marks hidden pages
-- (PvP without a rank), and currency and statistics come from their own addons.
function Follow.Available(id)
    local p = ns.Window.PageInfo(id)
    local f = p and _G[p.frame]
    return type(f) == "table" and f.hidden ~= true
end

-- The game's current page as a page key ("character" for ones not drawn here).
function Follow.CurrentPage()
    local g = Follow.Game()
    local id = g and type(g.activeSubframe) == "string" and Follow.PageOfFrame(g.activeSubframe)
    if id and ns.Window.HasPage(id) then return id end
    return "character"
end

-- The game's CharacterFrame keeps its own panel width. It sets that layout
-- attribute itself, so the game reads it and never the frame's size, and
-- Daylight UI never writes one: an attribute keeps the taint of whoever wrote it,
-- and the game's next ShowUIPanel then ran tainted (blocked in a fight).

-- Out of combat only. Waits while the game's window is un-parked (currency transfer).
function Follow.Park()
    local g = Follow.Game()
    if not g or Follow.given or Follow.parked or g:IsShown() then return end
    g:SetParent(Follow.hidden)
    Follow.parked = true
    if ns.Slots then ns.Slots.Lend() end
end

-- Brings the game's window back on screen for pages it must show itself, like
-- the currency transfer. Out of combat only. It's parked again once closed.
function Follow.Unpark(frameName)
    local g = Follow.Game()
    if not (g and Follow.parked) or InCombatLockdown() then return false end
    if ns.Slots then ns.Slots.Return() end
    Follow.parked = false
    g:SetParent(UIParent)
    if g:IsShown() then ToggleCharacter(frameName, true) else ToggleCharacter(frameName) end
    DUI.Fire("GameWindowBack", "character", "character", g)
    return true
end

function Follow.Want()
    if not Follow.parked then return false end
    if Follow.override ~= nil then return Follow.override end
    local g = Follow.Game()
    return g ~= nil and g:IsShown() == true
end

function Follow.Close()
    local g = Follow.Game()
    if not g then return end
    if InCombatLockdown() then
        Follow.override = false
        DUI.AfterCombat(Follow.Sync, "characterSync")
        return
    end
    if g:IsShown() then ToggleCharacter(g.activeSubframe or "PaperDollFrame") end
end

-- After combat, bring the game's window in line with this one.
function Follow.Sync()
    local g = Follow.Game()
    local want = Follow.override
    Follow.override = nil
    if not g then return end
    if want == false and g:IsShown() then ToggleCharacter(g.activeSubframe or "PaperDollFrame") end
    if want == true and not g:IsShown() then
        local p = ns.Window.PageInfo(ns.window and ns.window.current or "character")
        ToggleCharacter(p and p.frame or "PaperDollFrame")
    end
end

-- Pressing C after closing with the X in combat: the game's hidden window was
-- still open, so the press closed it. The player wanted it open, so open this
-- one now and the game's after combat.
function Follow.Toggled()
    local g = Follow.Game()
    if Follow.override ~= false or not g or g:IsShown() then return end
    if not InCombatLockdown() then Follow.override = nil; return end
    Follow.override = true
    DUI.AfterCombat(Follow.Sync, "characterSync")
end

-- Switching tabs also switches the game's page, which works in combat. Pages
-- with no game frame are local only. With a controller only this window
-- switches: the game's page change runs its gamepad focus code
-- (UpdateSmartNavFocus), and calling it from addon code taints it so every
-- later controller ability is refused.
function Follow.Select(id)
    local p = ns.Window.PageInfo(id)
    if not p then return end
    local g = Follow.Game()
    if not DUI.Pad.On() and Follow.Available(id) and g and g:IsShown() then ToggleCharacter(p.frame, true) end
    ns.Window.ShowPage(id)
end

-- Lets other parts of Daylight UI open the window in combat, where the game
-- refuses ToggleCharacter from addon code.
function Follow.Ready()
    return Follow.Game() ~= nil and Follow.parked and Follow.watcher:IsShown() == true
end

-- From addon code in combat (a data text click, say), this window toggles now
-- and the game's follows after combat. Returns false when the window is
-- turned off, so the caller should wait for combat to end.
function Follow.ToggleInFight()
    if not Follow.Ready() then return false end
    if Follow.Want() then Follow.Close(); return true end
    Follow.override = true
    DUI.AfterCombat(Follow.Sync, "characterSync")
    return true
end

local wasOpen, wasPage = false, nil
-- What the last full look saw. Most frames nothing moved, so the look stops
-- after one IsShown.
local seenShown, seenPage, seenParked, seenOverride, seen = nil, nil, nil, nil, false
function Follow.Tick()
    local g = Follow.Game()
    if not g or Follow.given then return end
    local shown, page = g:IsShown(), g.activeSubframe
    if seen and Follow.parked and shown == seenShown and page == seenPage and Follow.parked == seenParked
        and Follow.override == seenOverride then
        return
    end
    if Follow.override ~= nil and g:IsShown() == Follow.override then Follow.override = nil end
    local open = Follow.Want()
    if open ~= wasOpen then
        wasOpen, wasPage = open, page
        if open then ns.Window.Open(Follow.CurrentPage()) else ns.Window.Close() end
        if open then DUI.Pad.Forget(g) end   -- keep the D-pad off the hidden window
    elseif open and page ~= wasPage then
        wasPage = page
        ns.Window.ShowPage(Follow.CurrentPage())
    end
    if not Follow.parked and not g:IsShown() then DUI.AfterCombat(Follow.Park, "characterPark") end
    seen, seenShown, seenPage = true, g:IsShown(), g.activeSubframe
    seenParked, seenOverride = Follow.parked, Follow.override
end

local watcher = CreateFrame("Frame")
watcher:Hide()
watcher:SetScript("OnUpdate", function() Follow.Tick() end)
Follow.watcher = watcher

function Follow.Start()
    if not Follow.Game() or Follow.given then return false end
    DUI.AfterCombat(Follow.Park, "characterPark")
    if not Follow.hooked and type(ToggleCharacter) == "function" then
        Follow.hooked = true
        hooksecurefunc("ToggleCharacter", Follow.Toggled)
    end
    watcher:Show()
    return true
end

-- The player picked the game's own window. A parked one comes back for good, with
-- its slot buttons and its own panel width; an open one shows as itself where
-- this window was. Out of combat only (Win.Swap waits for the fight to end).
function Follow.Release()
    Follow.given = true
    Follow.override = nil
    watcher:Hide()
    wasOpen, wasPage, seen = false, nil, false
    if ns.Window then ns.Window.Close() end
    local g = Follow.Game()
    if not (g and Follow.parked) then return end
    if ns.Slots then ns.Slots.Return() end
    Follow.parked = false
    g:SetParent(UIParent)
    if DUI.Pad then DUI.Pad.Remember(g) end
    DUI.Fire("GameWindowBack", "character", "character", g)   -- the skins dress it now it shows as itself
end

-- Switched back to this window. An open game window goes out of sight at once and
-- the next look opens this one on the same page; a closed one is parked as at login.
function Follow.Reclaim()
    Follow.given = false
    local g = Follow.Game()
    if not g then return end
    if g:IsShown() and not Follow.parked and not InCombatLockdown() then
        g:SetParent(Follow.hidden)
        Follow.parked = true
        if ns.Slots then ns.Slots.Lend() end
    end
    seen = false
    Follow.Start()
end

-- The game's window sits out of sight under this one, or will when it opens, so
-- the Skins leave it alone. Picked by the player, or lent for a currency transfer,
-- it shows as itself.
function Follow.Covers()
    if Follow.given or DUI:Get("Character", "enabled") == false then return false end
    local g = Follow.Game()
    return not (g and g:IsShown() and not Follow.parked)
end
