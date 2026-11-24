-- Unlock-mode handles for the game's own pop-ups (loot rolls, alerts...).
-- Each is a proxy mover: the handle records the spot, and the frame is put
-- back there on the frame after the game may have placed it (when it shows,
-- after a loading screen, on Edit Mode layout changes). There is no hook on
-- its SetPoint. The game lays some of these out from protected code (loot
-- rolls sit in its bottom column), and with a hook on the frame that call
-- fails with "attempt to call a nil value". A frame nobody moved isn't touched.
--
-- Size: each follows the master Scale and its handle's mouse wheel. Most
-- scale as a whole, but loot rolls and toasts don't hang from the frame the
-- handle stands for. The game parents them to UIParent and only anchors them
-- to it, so its scale never reaches them (`pieces` and `toasts` below).
-- Nothing is written at scale 1.

local _, DUI = ...
local L = DUI.L

local GM = {}
DUI.GameMovers = GM

-- Only frames that exist on this client, aren't protected and aren't Edit
-- Mode systems. Sizes are for the handle while the frame is hidden.
-- pieces: frames it holds that aren't its children, scaled with it (the
-- game creates them once, so a fight never sees them unscaled).
-- toasts: frames that only anchor to it. It keeps its size and each toast is
-- sized as it shows.
GM.ROLL_W = 300 -- a roll card's width, so the Loot Rolls handle covers one

GM.FRAMES = {
    { name = "GroupLootContainer", label = "Loot Rolls", minW = GM.ROLL_W, minH = 100, slot = true,
      pieces = { "GroupLootFrame1", "GroupLootFrame2", "GroupLootFrame3", "GroupLootFrame4",
                 "BonusRollLootWonFrame", "BonusRollMoneyWonFrame", "DaylightUIRollStack" } },
    -- Every toast stacks up from it, including the "You won" loot ones.
    { name = "AlertFrame", label = "Alerts & Loot Won", minW = 280, minH = 80, toasts = true },
    { name = "UIWidgetTopCenterContainerFrame", label = "Top Center Status", minW = 200, minH = 40 },
    -- Capture bars (a battleground's flags, world PvP towers). The game hangs
    -- them under its minimap's spot, which the info panel covers, so the panel
    -- gives them a home of their own (GM.SetHome) even before anyone moves them.
    { name = "UIWidgetBelowMinimapContainerFrame", label = "Capture Bars", minW = 200, minH = 40, homed = true },
    { name = "UIErrorsFrame", label = "Error Messages", minW = 300, minH = 40 },
    { name = "TicketStatusFrame", label = "Ticket Status", minW = 200, minH = 40 },
    -- Battle.net friend toasts (logins, broadcasts, invites) stack from a corner
    -- of this small frame by the chat, so once moved it's sized to one toast
    -- (fit) and the toast fills the handle.
    { name = "ChatAlertFrame", label = "Battle.net Logins", minW = 250, minH = 50, fit = true, toasts = true },
}

function GM.Key(name) return "game." .. name end

-- name -> fn() giving the anchor an unmoved frame takes instead of the
-- game's spot ({ point, relativeTo, relativePoint, x, y }), or nil to leave
-- it to the game.
GM.homes = {}

local function homeOf(name)
    local fn = GM.homes[name]
    if not fn then return nil end
    local at
    DUI.SafeCall(function() at = fn() end)
    if type(at) == "table" and type(at[2]) == "table" and at[2].GetCenter then return at end
end

-- Where the handle of a frame at its home stands, as CENTER offsets in
-- UIParent units: the same anchor applied to a handle-sized box.
local function homeSpot(spec)
    local at = homeOf(spec.name)
    local f = _G[spec.name]
    if not (at and type(f) == "table") then return nil end
    local rel = at[2]
    local rcx, rcy = rel:GetCenter()
    if not rcx then return nil end
    local ui = UIParent:GetEffectiveScale()
    local rr = rel:GetEffectiveScale() / ui
    local r = f:GetEffectiveScale() / ui
    local s = DUI.Movers.Scale(GM.Key(spec.name))
    local px, py = DUI.Movers.PointOf(at[3], rcx * rr, rcy * rr, rel:GetWidth() * rr, rel:GetHeight() * rr)
    local sign = DUI.Movers.ANCHOR_SIGN[at[1]] or DUI.Movers.ANCHOR_SIGN.CENTER
    return px + (at[4] or 0) * r - sign[1] * spec.minW * s / 2 - UIParent:GetWidth() / 2,
           py + (at[5] or 0) * r - sign[2] * spec.minH * s / 2 - UIParent:GetHeight() / 2
end

-- Where a frame's handle was moved to, as CENTER offsets in UIParent units, or
-- nil while it stands where the game puts it.
function GM.Spot(name)
    local saved = DUI.DB.Positions()[GM.Key(name)]
    if DUI.Movers.Valid(saved) then return saved[1], saved[2] end
end

-- Loot rolls stack from one slot, the first popup's place, whatever the
-- game's container grows to (a slot per popup, around its center once moved).
-- The handle stands over that slot and Daylight UI's roll cards hang from it.
local near      -- defined below with standsAt
local rollLive  -- the handle's spot while it's being moved
local rollSeen  -- where the game's column last had the container's bottom

-- The first roll slot's center as CENTER offsets in UIParent units, and its
-- width and height.
function GM.RollSlot()
    local c, name = _G.GroupLootContainer, "GroupLootContainer"
    local s = DUI.Movers.Scale(GM.Key(name))
    local r = type(c) == "table" and c:GetEffectiveScale() / UIParent:GetEffectiveScale() or s
    local w = GM.ROLL_W * s
    local h = (type(c) == "table" and type(c.reservedSize) == "number" and c.reservedSize or 100) * r
    if rollLive then return rollLive[1], rollLive[2], w, h end
    local sx, sy = GM.Spot(name)
    if sx then return sx, sy, w, h end
    if type(c) == "table" and c:GetNumPoints() > 0 then
        local left, bottom, width = c:GetLeft(), c:GetBottom(), c:GetWidth()
        if type(left) == "number" and type(bottom) == "number" and type(width) == "number" then
            local x, y = (left + width / 2) * r - UIParent:GetWidth() / 2, bottom * r - UIParent:GetHeight() / 2
            if not (rollSeen and near(rollSeen[1], x) and near(rollSeen[2], y)) then
                rollSeen = { x, y }
                -- A handle up while the game first lays its column out moves to it.
                local hd = DUI.Movers.Handle(GM.Key(name))
                if hd and hd:IsShown() and not hd.moving and not hd.glide then
                    DUI.Movers.PlaceHandle(DUI.Movers.Get(GM.Key(name)), hd)
                end
            end
        end
    end
    if rollSeen then return rollSeen[1], rollSeen[2] + h / 2, w, h end
    return 0, -200 + h / 2, w, h
end

local function rollDrag(x, y)
    rollLive = { x, y }
    DUI.Fire("RollSlotMoved")
end

-- name -> { parent, points }: where the game had a frame before it was moved,
-- so a reset can put it back (the game only re-places it when it shows).
local origin = {}

local function remember(f, fit)
    local o = { parent = f:GetParent(), points = {} }
    if fit then o.w, o.h = f:GetWidth(), f:GetHeight() end
    for i = 1, f:GetNumPoints() do o.points[i] = { f:GetPoint(i) } end
    return o
end

local function restore(f, o)
    if o.parent and f:GetParent() ~= o.parent then f:SetParent(o.parent) end
    if o.w then f:SetSize(o.w, o.h) end
    f:ClearAllPoints()
    for _, pt in ipairs(o.points) do f:SetPoint(unpack(pt, 1, 5)) end
end

-- True when the frame already stands where place() would put it. These are
-- placed again after every loading screen and every toast, and most of the
-- time the game hasn't touched them, so nothing needs writing. A secret
-- answer counts as "not there" and the frame is written as before.
near = function(a, b)
    return type(a) == "number" and not DUI.IsSecret(a) and math.abs(a - b) < 0.01
end
local function standsAt(f, x, y, w, h)
    if f:GetNumPoints() ~= 1 then return false end
    local p, rel, rp, px, py = f:GetPoint(1)
    if DUI.IsSecret(p) or DUI.IsSecret(rel) or DUI.IsSecret(rp) then return false end
    if p ~= "CENTER" or rel ~= UIParent or rp ~= "CENTER" then return false end
    if not (near(px, x) and near(py, y)) then return false end
    if w and not (near(f:GetWidth(), w) and near(f:GetHeight(), h)) then return false end
    return true
end

-- Puts a frame at its moved spot if it has one. One that was moved but no
-- longer has a spot (reset) goes back to where the game had it.
local function place(spec)
    local name = spec.name
    local f = _G[name]
    if type(f) ~= "table" then return end
    local sx, sy = GM.Spot(name)
    local saved = sx and { sx, sy } or nil
    local home = not saved and spec.homed and homeOf(name) or nil
    if not (saved or home or origin[name]) then return end
    if f.IsProtected and f:IsProtected() and InCombatLockdown() then
        DUI.AfterCombat(function() place(spec) end, "gamemovers:" .. name)
        return
    end
    if not (saved or home) then
        restore(f, origin[name])
        origin[name] = nil
        return
    end
    -- Save the game's spot the first time, and again whenever the game took a
    -- managed frame back into its column (laid out fresh).
    if not origin[name] or (f.isManagedFrame and f:GetParent() ~= UIParent) then
        origin[name] = remember(f, spec.fit)
    end
    -- Pull it out of the game's managed column (the game takes it back when it
    -- shows) so the column's layout skips it.
    if f.isManagedFrame and f:GetParent() ~= UIParent then f:SetParent(UIParent) end
    if home then
        if f:GetNumPoints() == 1 then
            local p, rel, rp, px, py = f:GetPoint(1)
            if not (DUI.IsSecret(p) or DUI.IsSecret(rel) or DUI.IsSecret(rp))
                and p == home[1] and rel == home[2] and rp == home[3]
                and near(px, home[4] or 0) and near(py, home[5] or 0) then
                return
            end
        end
        f:ClearAllPoints()
        f:SetPoint(home[1], home[2], home[3], home[4] or 0, home[5] or 0)
        return
    end
    local r = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local w, h
    if spec.fit then
        local s = DUI.Movers.Scale(GM.Key(name))
        w, h = spec.minW * s / r, spec.minH * s / r
    end
    local x, y = saved[1] / r, saved[2] / r
    if standsAt(f, x, y, w, h) then return end
    if w then f:SetSize(w, h) end
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

-- An unmoved fit frame's handle stands where its toast will show: on the
-- corner the game hangs it from, left or right depending on the chat's side.
local function fitHome(spec)
    local f = _G[spec.name]
    local cx, cy = f:GetCenter()
    if not cx then return nil end
    local r = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local side = f.GetJustification and f:GetJustification() == "RIGHT" and -1 or 1
    local s = DUI.Movers.Scale(GM.Key(spec.name))
    return cx * r - UIParent:GetWidth() / 2 + side * (spec.minW * s - f:GetWidth() * r) / 2,
           cy * r - UIParent:GetHeight() / 2 + (spec.minH * s - f:GetHeight() * r) / 2
end

local function scaleTo(f, s)
    if type(f) ~= "table" or not f.SetScale then return end
    if math.abs((f:GetScale() or 1) - s) > 0.001 then f:SetScale(s) end
end

-- Scale callback for Movers, runs out of combat. A moved frame is placed
-- again since its offsets are in its own units and change with the scale.
local function sized(spec, s)
    if not spec.toasts then scaleTo(_G[spec.name], s) end
    if spec.pieces then
        for _, name in ipairs(spec.pieces) do scaleTo(_G[name], s) end
    end
    DUI.SafeCall(place, spec)
    if spec.slot then DUI.Fire("RollSlotMoved") end
end

-- Toasts come from a pool, created as needed and parented to UIParent, so
-- each is sized as it shows. AlertFrames.lua sends every one through this
-- function (Battle.net's too), and the post-hook runs before it's drawn. One
-- that's part of something protected waits and uses this size from then on.
local function sizeToast(f)
    if type(f) ~= "table" then return end
    local container = f.GetAlertContainer and f:GetAlertContainer()
    local name = container == _G.ChatAlertFrame and "ChatAlertFrame" or "AlertFrame"
    local s = DUI.Movers.Scale(GM.Key(name))
    if f.IsProtected and f:IsProtected() and InCombatLockdown() then
        DUI.AfterCombat(function() scaleTo(f, s) end)
    else
        scaleTo(f, s)
    end
end

-- The game reapplies its layout on PLAYER_SPECIALIZATION_CHANGED (there's no layouts event).
GM.PLACE_EVENTS = { "PLAYER_ENTERING_WORLD", "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_SPECIALIZATION_CHANGED" }

local editSized -- defined below with the Edit Mode pieces

local function placeAll()
    for _, spec in ipairs(GM.FRAMES) do DUI.SafeCall(place, spec) end
    for _, spec in ipairs(GM.EDIT_FRAMES) do
        if spec.size then DUI.SafeCall(editSized, spec) end
    end
end

local soon = DUI.Soon(placeAll)

-- Something of Daylight UI's covers where the game puts a frame: fn() names
-- the anchor it takes until the player moves it (nil hands it back to the
-- game). Call GM.PlaceSoon when that anchor changes.
function GM.SetHome(name, fn)
    GM.homes[name] = fn
    soon()
end

function GM.PlaceSoon() soon() end

-- The game's Edit Mode pieces (loot window, crowd control alert). Addon code
-- never moves them because that would taint them. The handle records the
-- spot, and when unlock mode ends it's written into this profile's Edit Mode
-- layout (like the game's quest tracker) and a reload applies it. Nothing is
-- written into a layout of the player's own; they move it in Edit Mode.
-- size: for a piece the game scales itself (its Edit Mode Size), the game's
-- value with Daylight UI's on top, reapplied every time the game sets it.

GM.EDIT_FRAMES = {
    -- With "Open loot window at mouse" on, the game opens it at the cursor.
    { name = "LootFrame", system = "LootFrame", label = "Loot Window", minW = 260, minH = 300,
      active = function()
          local cvar = _G.GetCVarBool
          return not (cvar and cvar("lootUnderMouse"))
      end,
      savedText = function() return L["DaylightUI saved the loot window's position. Reload to put it in place?"] end,
      ownText = function() return L["The loot window's spot is kept by the game's Edit Mode, and you're on an Edit Mode layout of your own: move it there (Esc > Edit Mode)."] end },
    -- The Skins look is a child of it (Packs/LossOfControl.lua), so it follows
    -- wherever the game puts it.
    { name = "LossOfControlFrame", system = "LossOfControl", label = "CC Alert", minW = 256, minH = 58,
      size = function(f)
          local set = Enum.EditModeLossOfControlSetting
          local v = set and type(f.GetSettingValue) == "function" and f:GetSettingValue(set.Size)
          return type(v) == "number" and v > 0 and v / 100 or 1
      end,
      savedText = function() return L["DaylightUI saved the crowd control alert's position. Reload to put it in place?"] end,
      ownText = function() return L["The crowd control alert's spot is kept by the game's Edit Mode, and you're on an Edit Mode layout of your own: move it there (Esc > Edit Mode)."] end },
    -- The breath bar's container, which holds the breath, fatigue, feign death and
    -- release bars: the game's Timer Bars piece. The Skins look is a child of each
    -- bar (Packs/Breath.lua), so it follows. Its bars hang down from the top, so
    -- the spot is kept by the top edge (top). It's hidden and empty until a timer
    -- runs and has no spot to read, so its handle starts at the game's default,
    -- the top of the screen and 100 down (home).
    { name = "MirrorTimerContainer", system = "TimerBars", label = "Breath bar", minW = 220, minH = 30, top = true,
      home = function(spec)
          local s = DUI.Movers.Scale(GM.Key(spec.name))
          return 0, UIParent:GetHeight() / 2 - 100 - spec.minH * s / 2
      end,
      size = function(f)
          local set = Enum.EditModeTimerBarsSetting
          local v = set and type(f.GetSettingValue) == "function" and f:GetSettingValue(set.Size)
          return type(v) == "number" and v > 0 and v / 100 or 1
      end,
      savedText = function() return L["DaylightUI saved the breath bar's position. Reload to put it in place?"] end,
      ownText = function() return L["The breath bar's spot is kept by the game's Edit Mode, and you're on an Edit Mode layout of your own: move it there (Esc > Edit Mode)."] end },
}

local editMoved = {} -- name -> spec: handle moved or reset since unlocking
local editReset = {} -- name -> true: reset this session, so the game's own spot goes back in

local function editEntry(layout, spec)
    local sys = Enum.EditModeSystem and Enum.EditModeSystem[spec.system]
    return sys ~= nil and DUI.EditMode.FindSystem(layout, sys, nil) or nil, sys
end

local function copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

-- Where the layout anchors a piece for a handle at saved = { x, y } from the screen's
-- center: the piece's center, or its top edge for one that hangs from the top.
local function anchorOf(spec, saved)
    if spec.top then
        local h = (spec.minH or 0) * DUI.Movers.Scale(GM.Key(spec.name))
        return "TOP", saved[1], saved[2] - UIParent:GetHeight() / 2 + h / 2
    end
    return "CENTER", saved[1], saved[2]
end

-- Offsets are in UIParent units, as Edit Mode stores them (its
-- ApplySystemAnchor divides by the frame's own scale).
function GM.FillEdit(layout)
    for _, spec in ipairs(GM.EDIT_FRAMES) do
        local entry, sys = editEntry(layout, spec)
        local saved = DUI.DB.Positions()[GM.Key(spec.name)]
        if entry and saved then
            local point, x, y = anchorOf(spec, saved)
            DUI.EditMode.Anchor(entry, point, point, x, y)
        elseif entry and editReset[spec.name] then
            local preset = DUI.EditMode.PresetSystem(sys, nil)
            if preset and type(preset.anchorInfo) == "table" then
                entry.anchorInfo = copy(preset.anchorInfo)
                entry.anchorInfo2 = type(preset.anchorInfo2) == "table" and copy(preset.anchorInfo2) or nil
                entry.isInDefaultPosition = true
            end
        end
    end
end

-- False while the saved layout doesn't have a piece where it was put.
function GM.EditCurrent(layout)
    for _, spec in ipairs(GM.EDIT_FRAMES) do
        local entry = editEntry(layout, spec)
        local saved = DUI.DB.Positions()[GM.Key(spec.name)]
        local a = entry and entry.anchorInfo
        if entry and saved then
            local point, x, y = anchorOf(spec, saved)
            if entry.isInDefaultPosition or type(a) ~= "table" or a.point ~= point or a.relativePoint ~= point
                or a.relativeTo ~= "UIParent" or math.abs((a.offsetX or 0) - x) > 1
                or math.abs((a.offsetY or 0) - y) > 1 then
                return false
            end
        elseif entry and editReset[spec.name] and not entry.isInDefaultPosition then
            return false
        end
    end
    return true
end

local function saveEdit()
    local EM = DUI.EditMode
    local moved, text, count = editMoved, nil, 0
    editMoved = {}
    if not EM.IsActive() then
        for _, spec in pairs(moved) do DUI.Print(spec.ownText()) end
        return
    end
    if not EM.UpToDate() then
        for _, spec in pairs(moved) do text, count = spec.savedText(), count + 1 end
        EM.Save(count == 1 and text or L["DaylightUI saved these positions. Reload to put them in place?"])
    end
end

-- Unlock mode locks itself when a fight starts, so the write waits for the end.
DUI.On("UnlockChanged", function(unlocked)
    if unlocked or not next(editMoved) then return end
    DUI.AfterCombat(saveEdit, "gamemovers:edit")
end)

editSized = function(spec)
    local f = _G[spec.name]
    if type(f) ~= "table" or not f.SetScale then return end
    if f.IsProtected and f:IsProtected() and InCombatLockdown() then
        DUI.AfterCombat(function() editSized(spec) end, "gamemovers:size:" .. spec.name)
        return
    end
    local s = DUI.Movers.Scale(GM.Key(spec.name))
    scaleTo(f, spec.size and spec.size(f) * s or s)
end

local function setupEdit()
    local any = false
    for _, spec in ipairs(GM.EDIT_FRAMES) do
        local f = _G[spec.name]
        local key = GM.Key(spec.name)
        local sys = Enum.EditModeSystem and Enum.EditModeSystem[spec.system]
        if type(f) == "table" and f.GetCenter and sys ~= nil and not DUI.Movers.Get(key) then
            DUI.Movers.Register(f, key, spec.label, nil, { proxy = true,
                minW = spec.minW, minH = spec.minH, active = spec.active,
                home = spec.home and function() return spec.home(spec) end or nil,
                scale = function() editSized(spec) end,
                onMoved = function()
                    editMoved[spec.name] = spec
                    editReset[spec.name] = DUI.DB.Positions()[key] == nil or nil
                end })
            any = true
        end
    end
    if any then DUI.EditMode.Add("gamemovers", GM.FillEdit, GM.EditCurrent) end
end

function GM.Setup()
    DUI.SafeCall(setupEdit)
    for _, spec in ipairs(GM.FRAMES) do
        local f = _G[spec.name]
        local key = GM.Key(spec.name)
        if type(f) == "table" and f.SetPoint and not DUI.Movers.Get(key) then
            DUI.Movers.Register(f, key, spec.label, nil, { proxy = true,
                minW = spec.minW, minH = spec.minH,
                scale = function(s) sized(spec, s) end,
                home = spec.fit and function() return fitHome(spec) end
                    or spec.slot and function() return GM.RollSlot() end
                    or spec.homed and function() return homeSpot(spec) end or nil,
                size = spec.slot and function() return select(3, GM.RollSlot()) end or nil,
                onDrag = spec.slot and rollDrag or nil,
                onMoved = function()
                    DUI.SafeCall(place, spec)
                    if spec.slot then
                        rollLive = nil
                        DUI.Fire("RollSlotMoved")
                    end
                end })
            if f.HookScript then f:HookScript("OnShow", soon) end
            DUI.SafeCall(place, spec)
        end
    end
    if type(_G.AlertFrame_ShowNewAlert) == "function" then
        hooksecurefunc("AlertFrame_ShowNewAlert", function(f) DUI.SafeCall(sizeToast, f) end)
    end
    for _, event in ipairs(GM.PLACE_EVENTS) do DUI.RegisterEvent(event, soon) end
    local em = _G.EditModeManagerFrame
    if type(em) == "table" and em.HookScript then em:HookScript("OnHide", soon) end
end

DUI.On("Login", GM.Setup)
