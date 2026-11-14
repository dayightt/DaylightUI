-- Puts the game's own action bars away while ours run. Each one is reparented under
-- a hidden frame and never hidden itself: Show and Hide on the game's bars are its
-- own Lua, and calling them from here leads to blocked actions later. Bar 1 keeps its
-- events, since the game still writes its page and our keybinds press its hidden
-- buttons. The twin buttons stay in place under the parked bar, which keeps them out
-- of sight. Nothing is written on them: an attribute an addon writes keeps the
-- addon's taint, so the game's own UpdateShownButtons, reading "statehidden" in a
-- fight (a slot changing as you loot), had its SetShown on them blocked.

local _, ns = ...
local DUI = DaylightUI

local Park = {}
ns.Park = Park

-- Bars 2-8: parked and silenced. Some clients lack a few; those are skipped.
Park.MULTI = { "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
               "MultiBar5", "MultiBar6", "MultiBar7" }

Park.LEAVE_GAP = 4          -- gap between the leave-vehicle button and our bar 1

local parked
function Park.Frame()
    if not parked then
        parked = CreateFrame("Frame", "DaylightUIParkedBars", UIParent)
        parked:SetAllPoints(UIParent)
        parked:Hide()
    end
    return parked
end

-- Moves one game frame under the hidden one (out of combat).
function Park.Bar(frame)
    if type(frame) == "table" and frame:GetParent() ~= Park.Frame() then frame:SetParent(Park.Frame()) end
end

-- The game's button events frame hands every event to each button on its list,
-- the hidden twins too. On "slot changed" in a fight a twin works out its slot from
-- its bar's page, which bar paging writes, and then shows or hides every button of
-- its bar, so the game blocked that SetShown. A pressed key works out its slot when
-- it's pressed and needs none of these updates, so the twins of every bar come off
-- the list (set to nil in place, as Buttons.Unlist does).
function Park.UnlistTwins()
    local prefixes = { "ActionButton" }
    for _, name in ipairs(Park.MULTI) do prefixes[#prefixes + 1] = name .. "Button" end
    for _, prefix in ipairs(prefixes) do
        for i = 1, 12 do
            local b = _G[prefix .. i]
            if type(b) == "table" then ns.Buttons.Unlist(b) end
        end
    end
end

-- Parks bars 1-8 and silences 2-8.
function Park.Apply()
    for _, name in ipairs(Park.MULTI) do
        local bar = _G[name]
        if type(bar) == "table" then
            bar:UnregisterAllEvents()
            Park.Bar(bar)
        end
    end
    local main = _G.MainActionBar
    if type(main) == "table" then
        Park.Bar(main)
        main:EnableMouse(false)
    end
    -- The game's per-action updates (cooldowns, alerts, animations) would run on
    -- every button in its list under our taint. Ours are painted by Buttons.lua and
    -- the twins are hidden.
    local events = _G.ActionBarActionEventsFrame
    if type(events) == "table" then events:UnregisterAllEvents() end
    Park.UnlistTwins()
    if not Park.wired then
        Park.wired = true
        local function recheck() DUI.AfterCombat(Park.Recheck, "park:recheck") end
        DUI.RegisterEvent("PLAYER_ENTERING_WORLD", recheck)
        pcall(DUI.RegisterEvent, "PLAYER_TALENT_UPDATE", recheck)
    end
end

-- The leave-vehicle button (also "land early" on a flight) is a child of the game's
-- bar 1, so parking the bar would take it along. It moves to UIParent beside our
-- bar 1 and is kept there, since the game's Edit Mode re-anchors it. Whether it
-- shows stays up to the game: never Show, Hide or SetShown it from here.
-- No hook on its SetPoint: Edit Mode calls that from protected code, and with a hook
-- on the button the call failed ("attempt to call a nil value", on every layout
-- update). Instead it's moved back beside ours a frame after the events that move it.
-- It has its own unlock-mode handle (a proxy that stands in while the button is
-- hidden); once moved, it's held at that spot instead.
Park.LEAVE_EVENTS = { "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_ENTERING_WORLD", "UPDATE_VEHICLE_ACTIONBAR",
                      "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE" }
Park.LEAVE_KEY = "actionbars.leave"

local function ratio(f) return f:GetEffectiveScale() / UIParent:GetEffectiveScale() end

function Park.PlaceLeave()
    local b, holder = Park.leave, Park.leaveHolder
    if not (b and holder) then return end
    local saved = DUI.DB.Positions()[Park.LEAVE_KEY]
    local _, rel, _, x, y = b:GetPoint(1)
    if saved then
        local r = ratio(b)
        local sx, sy = saved[1] / r, saved[2] / r
        if b:GetNumPoints() == 1 and rel == UIParent and x == sx and y == sy then return end
        b:ClearAllPoints()
        b:SetPoint("CENTER", UIParent, "CENTER", sx, sy)
        return
    end
    if b:GetNumPoints() == 1 and rel == holder then return end
    b:ClearAllPoints()
    b:SetPoint("BOTTOMRIGHT", holder, "BOTTOMLEFT", -Park.LEAVE_GAP, 0)
end

-- Its default spot beside our bar 1, as a CENTER offset from UIParent's CENTER in
-- UIParent units. The handle's spot while it was never moved.
function Park.LeaveHome()
    local b, holder = Park.leave, Park.leaveHolder
    local left, bottom = holder:GetLeft(), holder:GetBottom()
    if not left then return nil end
    local hr, br = ratio(holder), ratio(b)
    return left * hr - (Park.LEAVE_GAP + b:GetWidth() / 2) * br - UIParent:GetWidth() / 2,
           bottom * hr + b:GetHeight() / 2 * br - UIParent:GetHeight() / 2
end

function Park.LeaveButton(holder)
    local b = _G.MainMenuBarVehicleLeaveButton
    if type(b) ~= "table" or not holder then return end
    Park.leave, Park.leaveHolder = b, holder
    b:SetParent(UIParent)
    Park.PlaceLeave()
    if Park.leaveWired then return end
    Park.leaveWired = true
    local function now() DUI.AfterCombat(Park.PlaceLeave, "park:leave") end
    if not DUI.Movers.Get(Park.LEAVE_KEY) then
        DUI.Movers.Register(b, Park.LEAVE_KEY, LEAVE_VEHICLE or "Leave Vehicle", nil, { proxy = true,
            minW = 32, minH = 32, home = Park.LeaveHome, onMoved = now })
    end
    -- Once on the next frame however many events came (vehicle events arrive for
    -- every unit in the group).
    local queued = false
    local function later()
        queued = false
        now()
    end
    local function soon()
        if queued then return end
        queued = true
        C_Timer.After(0, later)
    end
    for _, event in ipairs(Park.LEAVE_EVENTS) do pcall(DUI.RegisterEvent, event, soon) end
    -- The game shows it on its own events (a vehicle, a flight), and its OnShow puts
    -- it at its Edit Mode spot, so move it back right after.
    b:HookScript("OnShow", now)
    -- Leaving Edit Mode puts it back at its Edit Mode spot.
    local em = _G.EditModeManagerFrame
    if type(em) == "table" and em.HookScript then em:HookScript("OnHide", soon) end
end

-- The button in our Edit Mode layout. At the game's default spot it counts as one of
-- the game's bottom bars (EditModeUtil.GetBottomActionBars), and the game restacks
-- those whenever one shows or hides, including the pet bar on a vehicle or a fight
-- starting or ending. That pulled it off our spot with no event of its own. Off its
-- default, the game leaves it alone, as with the totem bar (Totems.FillLayout). The
-- spot written is the game's own; ours places it.
local function leaveEntry(layout)
    local sys = Enum.EditModeSystem and Enum.EditModeSystem.VehicleLeaveButton
    return sys ~= nil and DUI.EditMode.FindSystem(layout, sys, nil) or nil
end

function Park.FillLayout(layout)
    local entry = leaveEntry(layout)
    if not (entry and entry.isInDefaultPosition) then return end
    local a = type(entry.anchorInfo) == "table" and entry.anchorInfo or {}
    DUI.EditMode.Anchor(entry, a.point or "BOTTOM", a.relativePoint or "BOTTOM", a.offsetX or 0, a.offsetY or 0)
end

-- False while the saved layout still has it at the game's default.
function Park.LayoutCurrent(layout)
    local entry = leaveEntry(layout)
    return not (entry and entry.isInDefaultPosition)
end

-- It wears bar 1's look (Skin.SetBar). Its art is one picture, wood and arrow
-- together, so the arrow is ours, tinted like an icon. The game rewrites its
-- highlight on a click during a flight and whenever it can't be used (hidden by
-- then), so the look's wash is reapplied after the first and when it shows. Called
-- from Bars.SkinAll and again on every look change.
function Park.SkinLeave()
    local b = Park.leave
    if not b then return end
    if not ns.Skin.IconOf(b) then
        local arrow = b:CreateTexture(nil, "ARTWORK")
        arrow:SetTexture(DUI.MEDIA .. "ui-leave.png")
        ns.Skin.SetIcon(b, arrow)
        local function wash() ns.Skin.PaintHighlight(b) end
        b:HookScript("OnShow", wash)
        b:HookScript("OnClick", wash)
    end
    ns.Skin.SetBar(b, "main")
    ns.Skin.Apply(b)
end

-- The game can take a bar back (a loading screen, a talent swap), so park it again.
function Park.Recheck()
    for _, name in ipairs(Park.MULTI) do Park.Bar(_G[name]) end
    Park.Bar(_G.MainActionBar)
    local b = Park.leave
    if b and b:GetParent() ~= UIParent then b:SetParent(UIParent) end
end
