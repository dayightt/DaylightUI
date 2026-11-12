-- The "DaylightUI" Edit Mode layout. Frames the game positions itself (action
-- bars, the quest tracker) can't be moved by addon code without tainting
-- them, so their places go into an Edit Mode layout the game applies. Each
-- module adds a part: a function that fills its systems into the layout,
-- and optionally one that says whether an existing layout is out of date.
--
-- Writing a layout taints Edit Mode until the next reload, so every write
-- asks for one. The layout is written when a character is installed
-- (Installer.lua), again whenever a part reports the saved one out of date
-- where it's in use, and on request (a move in unlock mode, a reset).

local _, DUI = ...
local L = DUI.L

local EditMode = {}
DUI.EditMode = EditMode

-- Each profile has its own layout, found by name: the standard profile's
-- (DPS/Tank) is "DaylightUI - DPS/Tank", another's "DaylightUI - <profile>".
-- The game validates layout names; if it rejects one, the plain spelling is used.
-- Layouts from before the name changed still count as the standard one's.
EditMode.NAME = "DaylightUI - DPS/Tank"
EditMode.PLAIN_NAME = "DaylightUI DPS Tank"
EditMode.OLD_NAMES = { ["DaylightUI"] = true, ["DaylightUI DPS Tank"] = true }

local parts = {} -- { key, fill = fn(layout), current = fn(layout) or nil }

-- fill(layout) writes this part's systems. current(layout) returns false when
-- the saved layout needs rewriting for this part (a new part, a changed spot).
function EditMode.Add(key, fill, current)
    parts[#parts + 1] = { key = key, fill = fill, current = current }
end

-- Helpers for parts

function EditMode.FindSystem(layout, system, index)
    for _, entry in ipairs(layout.systems or {}) do
        if entry.system == system and entry.systemIndex == index then return entry end
    end
end

-- relativeTo is a frame name ("UIParent" if nil).
function EditMode.Anchor(entry, point, relPoint, x, y, relativeTo)
    local a = entry.anchorInfo
    if type(a) ~= "table" then a = {}; entry.anchorInfo = a end
    a.point, a.relativeTo, a.relativePoint, a.offsetX, a.offsetY = point, relativeTo or "UIParent", relPoint, x, y
    entry.isInDefaultPosition = false
end

function EditMode.Setting(entry, key, value)
    if key == nil or value == nil then return end
    local rows = entry.settings
    if type(rows) ~= "table" then rows = {}; entry.settings = rows end
    for _, row in ipairs(rows) do
        if row.setting == key then row.value = value; return end
    end
    rows[#rows + 1] = { setting = key, value = value }
end

function EditMode.GetSetting(entry, key)
    for _, row in ipairs(entry and entry.settings or {}) do
        if row.setting == key then return row.value end
    end
end

-- Reading and writing the layout

-- The profile a layout call is for: the one given, else the active one.
local function profileOf(profile) return profile or DUI.DB.ActiveName() end

local function isDefault(profile) return profile == DUI.DB.DEFAULT end

-- A profile's layout names: the intended one and the plain one.
function EditMode.LayoutNames(profile)
    profile = profileOf(profile)
    if isDefault(profile) then return EditMode.NAME, EditMode.PLAIN_NAME end
    return "DaylightUI - " .. profile, "DaylightUI " .. (string.gsub(profile, "[^%w ]", ""))
end

-- The name a new layout for a profile gets.
function EditMode.Name(profile)
    local name, plain = EditMode.LayoutNames(profile)
    local valid = C_EditMode and C_EditMode.IsValidLayoutName
    if type(valid) == "function" then
        local ok, yes = pcall(valid, name)
        if ok and yes == false then return plain end
    end
    return name
end

local function isOurs(l, profile)
    if type(l) ~= "table" then return false end
    profile = profileOf(profile)
    local name, plain = EditMode.LayoutNames(profile)
    if l.layoutName == name or l.layoutName == plain then return true end
    return isDefault(profile) and EditMode.OLD_NAMES[l.layoutName] == true
end

-- Any profile's layout (they all start with "DaylightUI").
local function isAnyOurs(l)
    return type(l) == "table" and type(l.layoutName) == "string" and string.sub(l.layoutName, 1, 10) == "DaylightUI"
end

-- A profile's saved layout (the active profile's when not given), or nil.
function EditMode.Ours(profile)
    if not (C_EditMode and C_EditMode.GetLayouts) then return nil end
    local info = C_EditMode.GetLayouts()
    for _, l in ipairs(info and info.layouts or {}) do
        if isOurs(l, profile) then return l end
    end
end

function EditMode.Exists(profile) return EditMode.Ours(profile) ~= nil end

local function presetsCopy()
    local PLM = EditModePresetLayoutManager
    return PLM and PLM.GetCopyOfPresetLayouts and PLM:GetCopyOfPresetLayouts() or {}
end

-- The game's own preset list, for reading only. It's built once at load and
-- never changes, while GetCopyOfPresetLayouts deep-copies every system of
-- every preset, which is a lot of garbage for something asked often.
local function presetsRead()
    local PLM = EditModePresetLayoutManager
    local own = PLM and rawget(PLM, "presetLayoutInfo")
    if type(own) == "table" then return own end
    return presetsCopy()
end

-- A system's entry in the game's first preset (Modern), i.e. its default spot.
function EditMode.PresetSystem(system, index)
    local p = presetsCopy()[1]
    return type(p) == "table" and EditMode.FindSystem(p, system, index) or nil
end

-- This character's active layout when it's a saved one. The game keeps the
-- active layout per character, and presets come first in its count.
local function activeSaved()
    if not (C_EditMode and C_EditMode.GetLayouts) then return nil end
    local info = C_EditMode.GetLayouts()
    local i = (info and info.activeLayout or 0) - #presetsRead()
    return info and type(info.layouts) == "table" and info.layouts[i] or nil
end

-- Whether the on-load check for another profile's layout (below) is done. A
-- profile switch made this session counts: until the reload the new
-- profile's layout is meant to be active, and the check would undo it.
local profileChecked = false

-- Whether a layout was written this session. Until the reload Edit Mode runs
-- tainted, and the game fires its layouts event after each write. A part
-- that never agrees with what the game stored (it rounds or clamps a value)
-- would make every event write again, an endless loop of blocked actions
-- that once froze a player's game. See EditMode.AutoSave.
local written = false

-- Whether the profile's layout (the active one when not given) is active.
function EditMode.IsActive(profile) return isOurs(activeSaved(), profile) end

-- Whether any profile's layout is active.
function EditMode.AnyActive() return isAnyOurs(activeSaved()) end

-- Whether the controller UI is on. Its Edit Mode keeps gamepad layouts, and
-- switching to our keyboard-and-mouse one while it's on crashes the game.
-- Only its presets reveal it: GamePadEnable (gamepad input) stays on even
-- with the controller UI off.
function EditMode.GamepadMode()
    local pad = Enum.InputDeviceInterfaceType and Enum.InputDeviceInterfaceType.Gamepad
    local p = presetsRead()[1]
    return pad ~= nil and type(p) == "table" and p.interfaceStyle == pad
end

-- Whether a layout can be written now. Returns nil, or a reason why not.
local function notReady()
    if InCombatLockdown() then return L["you're in combat"] end
    if EditMode.GamepadMode() then
        return L["controller mode is on; turn it off (Options > Controller), install, then turn it back on"]
    end
    local mgr = EditModeManagerFrame
    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts and Enum.EditModeSystem
            and EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts) then
        return L["this game client's Edit Mode isn't one DaylightUI knows"]
    end
    if not (mgr and mgr.accountSettings) then return L["Edit Mode hasn't loaded its layouts yet; try again in a moment"] end
    if mgr.editModeActive or mgr:IsShown() then return L["Edit Mode is open; close it first"] end
    return nil
end

-- The game's layouts as Edit Mode keeps them: presets first, then saved ones
-- (account layouts before character ones).
local function merged(info)
    local all = presetsCopy()
    for _, l in ipairs(info.layouts or {}) do all[#all + 1] = l end
    return all
end

-- What a new layout starts from: the bundled DaylightUI layout
-- (EditModeBase.lua), converted back into a layout by the game itself, or
-- failing that a copy of the Modern preset. Install lays our parts over
-- either. The second return says whether it's the bundled one.
function EditMode.Base()
    local str = EditMode.BASE
    local convert = C_EditMode and C_EditMode.ConvertStringToLayoutInfo
    local presets = presetsCopy()
    if type(str) == "string" and type(convert) == "function" then
        local ok, layout = pcall(convert, str)
        if ok and EditMode.Plausible(layout, presets) then return layout, true end
    end
    local base = presets[1]
    local modern = Enum.EditModePresetLayouts and Enum.EditModePresetLayouts.Modern
    for _, p in ipairs(presets) do
        if modern ~= nil and p.layoutIndex == modern then base = p end
    end
    if not base then return nil, false end
    return CopyTable(base), false
end

-- Whether a layout the game parsed from text looks real: a known input style
-- (keyboard and mouse, or gamepad) and about as many systems as the game's
-- own presets. Text that isn't quite Edit Mode's share format can still be
-- parsed into nonsense the game then refuses to save.
function EditMode.Plausible(layout, presets)
    if type(layout) ~= "table" or type(layout.systems) ~= "table" or #layout.systems == 0 then return false end
    local style = layout.interfaceStyle
    if style ~= nil then
        local known = false
        for _, v in pairs(Enum.InputDeviceInterfaceType or {}) do
            if v == style then known = true end
        end
        if not known then return false end
    end
    local p = presets and presets[1]
    if type(p) == "table" and type(p.systems) == "table" and #p.systems > 0 then
        return #layout.systems >= #p.systems * 0.8
    end
    return true
end

-- Sets this character up: makes the profile's layout (the active profile's
-- when not given) the active one, adding it first if it doesn't exist, in
-- the same place and way the game adds a new account layout (after the last
-- account layout, else after the presets, then notifying the game, which
-- makes it active). base is the layout a new one starts from (default
-- EditMode.Base()). Returns true, or false and a reason.
function EditMode.Install(base, profile)
    local why = notReady()
    if why then return false, why end
    local info = C_EditMode.GetLayouts()
    if not (info and type(info.layouts) == "table") then return false, L["the game hasn't given its layouts yet"] end
    local all = merged(info)
    for i, l in ipairs(all) do
        if isOurs(l, profile) then
            C_EditMode.SetActiveLayout(i)
            return true
        end
    end
    local account = Enum.EditModeLayoutType and Enum.EditModeLayoutType.Account
    local count, highest = 0, nil
    for i, l in ipairs(all) do
        if l.layoutType == account then
            count = count + 1
            highest = i
        end
    end
    local max = Constants and Constants.EditModeConsts and Constants.EditModeConsts.EditModeMaxLayoutsPerType
    if type(max) == "number" and count >= max then
        return false, L["you have the most account layouts the game allows; delete one in Edit Mode first"]
    end
    local layout = base or EditMode.Base()
    if not layout then return false, L["the game has no layout to start from"] end
    -- Lay our parts over it, as EditMode.Write does. The bundled layout has
    -- pieces at the game's default spots that parts move (the extra action
    -- button, the leave-vehicle button). Left as is, the next login found it out
    -- of date and asked for a second reload right after the setup guide's.
    for _, p in ipairs(parts) do DUI.SafeCall(p.fill, layout) end
    layout.layoutIndex = nil
    layout.layoutType = account
    layout.layoutName = EditMode.Name(profile)
    local index = highest and (highest + 1) or (#presetsRead() + 1)
    table.insert(all, index, layout)
    if type(info.activeLayout) == "number" and info.activeLayout >= index then
        info.activeLayout = info.activeLayout + 1
    end
    info.layouts = all
    written = true
    if not pcall(C_EditMode.SaveLayouts, info) then return false, L["the game refused the layout"] end
    if C_EditMode.OnLayoutAdded then
        C_EditMode.OnLayoutAdded(index, true, false)
    else
        C_EditMode.SetActiveLayout(index)
    end
    return true
end

-- A profile's layout (the active one when not given) in Edit Mode's share
-- format, or nil.
function EditMode.Export(profile)
    local ours = EditMode.Ours(profile)
    local convert = C_EditMode and C_EditMode.ConvertLayoutInfoToString
    if not (ours and type(convert) == "function") then return nil end
    local ok, s = pcall(convert, ours)
    return ok and type(s) == "string" and s or nil
end

-- Parses a layout from share text, or nil.
local function fromText(str)
    local convert = C_EditMode and C_EditMode.ConvertStringToLayoutInfo
    if type(str) ~= "string" or type(convert) ~= "function" then return nil end
    local ok, layout = pcall(convert, str)
    if ok and EditMode.Plausible(layout, presetsCopy()) then return layout end
end

-- Puts a profile's layout in place for this character: made active, or added
-- first. A new one starts from the layout the profile brought (an import, or
-- a copy made when it was created), else from the active one (so a new
-- profile starts where you are), else the bundled one. Returns true, or false
-- and a reason.
function EditMode.UseProfile(profile)
    profileChecked = true
    if EditMode.Exists(profile) then return EditMode.Install(nil, profile) end
    local data = DUI.DB.Root().profileData[profile]
    local base = fromText(type(data) == "table" and data.pendingLayout)
    if not base then
        local current = activeSaved()
        if isAnyOurs(current) then base = CopyTable(current) end
    end
    local ok, why = EditMode.Install(base, profile)
    if ok and type(data) == "table" then data.pendingLayout = nil end
    return ok, why
end

-- Renames a profile's layout to match the profile's new name. Returns true
-- (also when there's no layout yet), or false and a reason.
function EditMode.RenameLayout(old, new)
    -- The standard layout keeps its name, like the standard profile does.
    if EditMode.LayoutNames(old) == EditMode.NAME then return false, L["it's the standard layout"] end
    local why = notReady()
    if why then return false, why end
    local info = C_EditMode.GetLayouts()
    if not (info and type(info.layouts) == "table") then return false, L["the game hasn't given its layouts yet"] end
    local all = merged(info)
    for _, l in ipairs(all) do
        if isOurs(l, old) then
            l.layoutName = EditMode.Name(new)
            info.layouts = all
            if not pcall(C_EditMode.SaveLayouts, info) then return false, L["the game refused the layout"] end
            return true
        end
    end
    return true
end

-- Rewrites our layout with every part (a part's spot changed, a bar moved in
-- unlock mode) and makes it active, installing it if missing. Returns true,
-- or false and a reason.
function EditMode.Write()
    local why = notReady()
    if why then return false, why end
    local info = C_EditMode.GetLayouts()
    if not (info and type(info.layouts) == "table") then return false, L["the game hasn't given its layouts yet"] end
    local all = merged(info)
    local index
    for i, l in ipairs(all) do
        if isOurs(l) then index = i end
    end
    if not index then return EditMode.Install() end
    for _, p in ipairs(parts) do DUI.SafeCall(p.fill, all[index]) end
    info.layouts = all
    -- Marked before the write even if the game refuses it: one attempt per session.
    written = true
    if not pcall(C_EditMode.SaveLayouts, info) then return false, L["the game refused the layout"] end
    C_EditMode.SetActiveLayout(index)
    return true
end

-- Writes waiting to be saved (EditMode.WriteSetting, below).
local pending = {}
local function pendingKey(system, index, key)
    return tostring(system) .. ":" .. tostring(index) .. ":" .. tostring(key)
end

-- One setting of one system in this character's active layout, when it's a
-- saved one (nil on the game's presets). A pending write counts, otherwise a
-- slider reading the layout would jump back to the old value.
function EditMode.ActiveSetting(system, index, key)
    local l = activeSaved()
    if not l then return nil end
    local w = pending[pendingKey(system, index, key)]
    if w then return w.value end
    return EditMode.GetSetting(EditMode.FindSystem(l, system, index), key)
end

-- Game settings shown in our options that Edit Mode stores in its layout
-- (minimap rotation, bag bar size). The game reapplies them from the layout
-- each time it applies one (every login), so a live-only change gets undone.
-- These go into the active saved layout with SaveLayouts alone, passing
-- presets first as the game does (EllesmereUI does the same). No
-- SetActiveLayout means no reload. The caller shows the change live.
-- Writes wait until half a second after the last one, so a slider drag is a
-- single save (each save makes the game reapply the layout, which would snap
-- the frame back mid-drag), and also wait for combat and Edit Mode to end.
-- On a preset there's nothing to write to.
local writeTurn = 0
local writePending

-- Only the newest pending wait saves; earlier ones find their turn gone.
local function writeSoon(seconds)
    writeTurn = writeTurn + 1
    local turn = writeTurn
    C_Timer.After(seconds, function()
        if turn == writeTurn then writePending() end
    end)
end

writePending = function()
    if not next(pending) then return end
    if InCombatLockdown() then
        DUI.AfterCombat(writePending, "editmode:settings")
        return
    end
    local mgr = EditModeManagerFrame
    if mgr and (mgr.editModeActive or mgr:IsShown()) then
        writeSoon(1)
        return
    end
    local list = pending
    pending = {}
    if notReady() then return end
    local info = C_EditMode.GetLayouts()
    if not (info and type(info.layouts) == "table") then return end
    local all = merged(info)
    local layout = (info.activeLayout or 0) > #presetsRead() and all[info.activeLayout] or nil
    if not layout then return end
    local changed = false
    for _, w in pairs(list) do
        local entry = EditMode.FindSystem(layout, w.system, w.index)
        if entry and EditMode.GetSetting(entry, w.key) ~= w.value then
            EditMode.Setting(entry, w.key, w.value)
            changed = true
        end
    end
    if not changed then return end
    info.layouts = all
    pcall(C_EditMode.SaveLayouts, info)
end

function EditMode.WriteSetting(system, index, key, value)
    if system == nil or key == nil or value == nil then return end
    pending[pendingKey(system, index, key)] = { system = system, index = index, key = key, value = value }
    writeSoon(0.5)
end

-- Keys of the parts that consider the saved layout out of date, or nil when
-- there's no layout of ours to check.
function EditMode.Stale()
    local ours = EditMode.Ours()
    if not ours then return nil end
    local list = {}
    for _, p in ipairs(parts) do
        if p.current then
            local ok, fine = pcall(p.current, ours)
            if ok and fine == false then list[#list + 1] = p.key end
        end
    end
    return list
end

-- Whether every part is happy with the saved layout.
function EditMode.UpToDate()
    local stale = EditMode.Stale()
    return stale ~= nil and #stale == 0
end

function EditMode.AskReload(text)
    -- While the setup guide is open this waits: Finish reloads anyway, and
    -- closing the guide shows it then (Installer.HoldReload).
    local I = DUI.Installer
    if I and I.HoldReload and I.HoldReload(function() EditMode.AskReload(text) end) then return end
    StaticPopupDialogs.DAYLIGHTUI_RELOAD = StaticPopupDialogs.DAYLIGHTUI_RELOAD or {
        button1 = RELOADUI or L["Reload"], button2 = LATER or L["Later"],
        OnAccept = function() ReloadUI() end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopupDialogs.DAYLIGHTUI_RELOAD.text = text
    StaticPopup_Show("DAYLIGHTUI_RELOAD")
end

-- Writes, then asks for the reload that applies it.
function EditMode.Save(text)
    if EditMode.Write() then EditMode.AskReload(text) end
end

-- Save for writes nobody asked for (a part out of date), only when the layout
-- is out of date and nothing was written yet this session.
function EditMode.AutoSave(text)
    if written or EditMode.UpToDate() then return end
    EditMode.Save(text)
end

-- Once the game has its layouts: a character not set up yet is asked to
-- install (Installer.lua), which writes ours and makes it active. Where ours
-- is in use, it's rewritten when a part asks. A character on another layout
-- (it said "not now") is left alone. A character on another profile's layout
-- (it switched profiles) is moved to its own profile's. That check runs only
-- once, on the first layouts the game provides, because the event fires
-- again on loading screens (Deeprun Tram) when the active layout can briefly
-- read wrong.
local function layoutsGiven()
    local info = C_EditMode and C_EditMode.GetLayouts and C_EditMode.GetLayouts()
    return type(info) == "table" and type(info.layouts) == "table" and (info.activeLayout or 0) >= 1
end

-- A set-up character (the guide was finished) that's on the game's own layout,
-- or whose layout was deleted: put back on its profile's without asking.
local function setUpElsewhere()
    local I = DUI.Installer
    return I and I.State and I.State() == "installed" and not EditMode.AnyActive()
end

DUI.RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function()
    if #parts == 0 then return end
    local check = not profileChecked and layoutsGiven()
    if check then profileChecked = true end
    if (EditMode.AnyActive() or setUpElsewhere()) and not EditMode.IsActive() then
        if check and EditMode.UseProfile(DUI.DB.ActiveName()) then
            EditMode.AskReload(L["DaylightUI put this profile's Edit Mode layout in place. Reload to use it?"])
        end
        return
    end
    -- A character not set up yet is asked first. One that's set up (was shown the
    -- guide once) still gets its layout kept up to date below, with the reload
    -- prompt waiting for the guide.
    local I = DUI.Installer
    if I and I.Needed() then
        I.Show()
        if not EditMode.IsActive() then return end
    end
    if not EditMode.IsActive() then return end
    EditMode.AutoSave(L["DaylightUI updated its layout. Reload to put it in place?"])
end)

-- The event above can fire before our parts are added (they wait for
-- PLAYER_LOGIN), and a character that never used the addon may not get it
-- again, so nothing would ask it to install. Once in the world, check whether
-- the game has its layouts by now and the event hasn't been handled.
local askedOnEntry = false
DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if askedOnEntry or #parts == 0 or not (C_EditMode and C_EditMode.GetLayouts) then return end
    local info = C_EditMode.GetLayouts()
    if type(info) ~= "table" or type(info.layouts) ~= "table" or (info.activeLayout or 0) < 1 then return end
    askedOnEntry = true
    if EditMode.AnyActive() and not EditMode.IsActive() then return end
    local I = DUI.Installer
    if I and I.Needed() then I.Show() end
end)
