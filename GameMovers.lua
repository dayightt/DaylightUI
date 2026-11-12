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
GM.FRAMES = {
    { name = "GroupLootContainer", label = "Loot Rolls", minW = 280, minH = 100,
      pieces = { "GroupLootFrame1", "GroupLootFrame2", "GroupLootFrame3", "GroupLootFrame4",
                 "BonusRollLootWonFrame", "BonusRollMoneyWonFrame" } },
    -- Every toast stacks up from it, including the "You won" loot ones.
    { name = "AlertFrame", label = "Alerts & Loot Won", minW = 280, minH = 80, toasts = true },
    { name = "UIWidgetTopCenterContainerFrame", label = "Top Center Status", minW = 200, minH = 40 },
    { name = "UIErrorsFrame", label = "Error Messages", minW = 300, minH = 40 },
    { name = "TicketStatusFrame", label = "Ticket Status", minW = 200, minH = 40 },
    -- Battle.net friend toasts (logins, broadcasts, invites) stack from a corner
    -- of this small frame by the chat, so once moved it's sized to one toast
    -- (fit) and the toast fills the handle.
    { name = "ChatAlertFrame", label = "Battle.net Logins", minW = 250, minH = 50, fit = true, toasts = true },
}

function GM.Key(name) return "game." .. name end

-- name -> { parent, points }: where the game had a frame before we moved it,
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

-- Puts a frame at its moved spot if it has one. One that was moved but no
-- longer has a spot (reset) goes back to where the game had it.
local function place(spec)
    local name = spec.name
    local f = _G[name]
    if type(f) ~= "table" then return end
    local saved = DUI.DB.Positions()[GM.Key(name)]
    if not DUI.Movers.Valid(saved) then saved = nil end
    if not (saved or origin[name]) then return end
    if f.IsProtected and f:IsProtected() and InCombatLockdown() then
        DUI.AfterCombat(function() place(spec) end, "gamemovers:" .. name)
        return
    end
    if not saved then
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
    local r = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if spec.fit then
        local s = DUI.Movers.Scale(GM.Key(name))
        f:SetSize(spec.minW * s / r, spec.minH * s / r)
    end
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", saved[1] / r, saved[2] / r)
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

local queued = false
local function soon()
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        placeAll()
    end)
end

-- The game's Edit Mode pieces (loot window, crowd control alert). Addon code
-- never moves them because that would taint them. The handle records the
-- spot, and when unlock mode ends it's written into this profile's Edit Mode
-- layout (like the game's quest tracker) and a reload applies it. Nothing is
-- written into a layout of the player's own; they move it in Edit Mode.
-- size: for a piece the game scales itself (its Edit Mode Size), the game's
-- value with ours on top, reapplied every time the game sets it.

GM.EDIT_FRAMES = {
    -- With "Open loot window at mouse" on, the game opens it at the cursor.
    { name = "LootFrame", system = "LootFrame", label = "Loot Window", minW = 260, minH = 300,
      active = function()
          local cvar = _G.GetCVarBool
          return not (cvar and cvar("lootUnderMouse"))
      end,
      savedText = L["DaylightUI saved the loot window's position. Reload to put it in place?"],
      ownText = L["The loot window's spot is kept by the game's Edit Mode, and you're on an Edit Mode layout of your own: move it there (Esc > Edit Mode)."] },
    -- The Skins look is a child of it (Packs/LossOfControl.lua), so it follows
    -- wherever the game puts it.
    { name = "LossOfControlFrame", system = "LossOfControl", label = "CC Alert", minW = 256, minH = 58,
      size = function(f)
          local set = Enum.EditModeLossOfControlSetting
          local v = set and type(f.GetSettingValue) == "function" and f:GetSettingValue(set.Size)
          return type(v) == "number" and v > 0 and v / 100 or 1
      end,
      savedText = L["DaylightUI saved the crowd control alert's position. Reload to put it in place?"],
      ownText = L["The crowd control alert's spot is kept by the game's Edit Mode, and you're on an Edit Mode layout of your own: move it there (Esc > Edit Mode)."] },
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

-- Offsets are in UIParent units, as Edit Mode stores them (its
-- ApplySystemAnchor divides by the frame's own scale).
function GM.FillEdit(layout)
    for _, spec in ipairs(GM.EDIT_FRAMES) do
        local entry, sys = editEntry(layout, spec)
        local saved = DUI.DB.Positions()[GM.Key(spec.name)]
        if entry and saved then
            DUI.EditMode.Anchor(entry, "CENTER", "CENTER", saved[1], saved[2])
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
            if entry.isInDefaultPosition or type(a) ~= "table" or a.point ~= "CENTER" or a.relativePoint ~= "CENTER"
                or a.relativeTo ~= "UIParent" or math.abs((a.offsetX or 0) - saved[1]) > 1
                or math.abs((a.offsetY or 0) - saved[2]) > 1 then
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
        for _, spec in pairs(moved) do DUI.Print(spec.ownText) end
        return
    end
    if not EM.UpToDate() then
        for _, spec in pairs(moved) do text, count = spec.savedText, count + 1 end
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
                home = spec.fit and function() return fitHome(spec) end or nil,
                onMoved = function() DUI.SafeCall(place, spec) end })
            if f.HookScript then f:HookScript("OnShow", soon) end
            DUI.SafeCall(place, spec)
        end
    end
    if type(_G.AlertFrame_ShowNewAlert) == "function" then
        hooksecurefunc("AlertFrame_ShowNewAlert", function(f) DUI.SafeCall(sizeToast, f) end)
    end
    for _, event in ipairs(GM.PLACE_EVENTS) do pcall(DUI.RegisterEvent, event, soon) end
    local em = _G.EditModeManagerFrame
    if type(em) == "table" and em.HookScript then em:HookScript("OnHide", soon) end
end

DUI.On("Login", GM.Setup)
