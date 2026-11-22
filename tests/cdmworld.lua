-- The game's own Cooldown Manager in the fake game. The four viewers and their
-- items are built from Blizzard's code and XML (tests/blizzard/, fetched by
-- tools/fetch_blizzard.py), so a test sees the game's real rules: when an item
-- is active, when it shows, when it marks its aura, what a layout pass does to
-- the pool. The catalogue (which spells a class has rows for) comes from the
-- game's data in tests/cooldown_sets.lua.
--
--     local CW = require("cdmworld")
--     stub.Load({ actionbars = true, before = function()
--         CW.Install({ with = 6673, known = { 6673, 772 }, shown = { 199688 } })
--     end })
--
-- What is the game's own code here, and what stands in for a part that can't
-- run (the settings window and its data provider, Edit Mode, the C side), is
-- said at each piece below.

local stub = require("stub")
local Blizz = require("blizzard")

local CW = {}

-- The game's files, in the order its .toc files load them.
CW.SHARED = { "Mixin.lua", "TableUtil.lua", "FunctionUtil.lua", "EnumUtil.lua", "Flags.lua", "MathUtil.lua",
              "SecureTypes.lua", "ProxyUtil.lua", "FrameUtil.lua", "Pools.lua", "CallbackRegistry.lua",
              "GlobalCallbackRegistry.lua", "CvarUtil.lua", "AnchorUtil.lua", "GridLayoutUtil.lua",
              "LayoutFrame.lua", "Cooldown.lua", "VisualAlertTarget.lua", "ManagedFrameSystem.lua" }
CW.VIEWER = { "CooldownViewerSettingsConstants.lua", "CooldownViewerUtil.lua", "CooldownViewerSecure.lua",
              "CooldownViewerVisualAlertTarget.lua", "CooldownViewerAlert.lua", "CooldownViewerItemData.lua",
              "CooldownViewer.lua" }
CW.NAMES = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }

-- The API docs that hold the enums and constants the game's code reads.
local ENUM_DOCS = { "CooldownViewerConstantsDocumentation.lua", "EditModeManagerConstantsDocumentation.lua",
                    "FrameScriptDocumentation.lua", "VisualAlertConstantsDocumentation.lua",
                    "SpellConstantsDocumentation.lua" }

-- Edit Mode's default for each viewer setting (Blizzard_EditMode
-- EditModePresetLayouts.lua, the Modern layout), by the viewer's system index.
local PRESET = {
    [0] = { Orientation = 0, IconLimit = 12, IconDirection = 1 },   -- Essential
    [1] = { Orientation = 0, IconLimit = 7, IconDirection = 1 },    -- Utility
    [2] = { Orientation = 0, IconLimit = 1, IconDirection = 1 },    -- BuffIcon
    [3] = { Orientation = 1, IconLimit = 1, IconDirection = 1, BarContent = 0, BarWidthScale = 100 },   -- BuffBar
}
local PRESET_ALL = { IconSize = 100, IconPadding = 2, Opacity = 100, VisibleSetting = 0, HideWhenInactive = 1,
                     ShowTimer = 1, ShowTooltips = 1 }

local function fresh(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = fresh(x) end
    return out
end

-- Enumerations and constants from the game's API docs.
local docEnums, docConstants
local function enums()
    if docEnums then return docEnums, docConstants end
    docEnums, docConstants = {}, {}
    local docs = {}
    function docs:AddDocumentationTable(t)
        for _, e in ipairs(t.Tables or {}) do
            if e.Type == "Enumeration" then
                local out = {}
                for _, f in ipairs(e.Fields or {}) do out[f.Name] = f.EnumValue end
                docEnums[e.Name] = out
            elseif e.Type == "Constants" then
                local out = {}
                for _, v in ipairs(e.Values or {}) do out[v.Name] = v.Value end
                docConstants[e.Name] = out
            end
        end
    end
    local env = setmetatable({ APIDocumentation = docs }, { __index = function() return Blizz.INERT end })
    for _, file in ipairs(ENUM_DOCS) do
        local chunk = loadfile(Blizz.DIR .. "api/" .. file)
        if not chunk then
            error("tests/blizzard/api/" .. file .. " is missing: run `py tools/fetch_blizzard.py` once on this PC", 3)
        end
        setfenv(chunk, env)
        chunk()
    end
    return docEnums, docConstants
end

local catalogue
local function rows()
    if not catalogue then
        catalogue = dofile("tests/cooldown_sets.lua")
    end
    return catalogue
end

-- Every row of the catalogue (read only).
function CW.Catalogue() return rows() end

-- The catalogue set (a class's rows) that lists a spell.
function CW.SetWith(spellID)
    local best, count = nil, {}
    for _, r in ipairs(rows()) do count[r.set] = (count[r.set] or 0) + 1 end
    for _, r in ipairs(rows()) do
        if r.spell == spellID and (not best or count[r.set] > count[best]) then best = r.set end
    end
    return best
end

-- The game's GetSpellBaseCooldown, in milliseconds. In game it reports a cooldown
-- kept on a spell category too (Charge, the shocks), which is what the spell
-- facts' cd holds: both come from the game's data. 0 for a spell with none.
local facts
function CW.BaseCooldown(spellID)
    if not facts then
        local ns = {}
        assert(loadfile("DaylightUI_ActionBars/CdmSpells.lua"))("DaylightUI_ActionBars", ns)
        facts = ns.CdmSpells.FACTS
    end
    local f = facts[spellID]
    return f and f.cd and f.cd * 1000 or 0
end

local HIDE_AURA, HIDE_BY_DEFAULT, HIGHEST_RANK = 1, 2, 4
local function has(flags, bit) return math.floor(flags / bit) % 2 == 1 end

-- ---------------------------------------------------------------------
-- The world
-- ---------------------------------------------------------------------

-- opts.with    a spell of the class whose rows to use (opts.set = the set's id)
-- opts.known   the spells the player knows, lowest rank first. A row is known
--              when its spell or one of its linked spells is.
-- opts.shown   cooldown ids the player's layout shows though the game hides
--              them by default (on WoW: Forever that is every buff);
--              opts.showAll = all of them
-- opts.bars    cooldown ids the player's layout moved to Tracked Bars (the data
--              files no spell there: a buff is a bar only once the player says so)
-- opts.info    { [cooldownID] = { field = value } } over what the data gives
function CW.Install(opts)
    opts = opts or {}
    local E, constants = enums()
    local game = Blizz.Game()
    local G = game.G
    G.Constants = constants
    CW.game, CW.G = game, G
    CW.items, CW.auraSeq, CW.cooldowns, CW.charges, CW.alerts = {}, 100, {}, {}, {}
    CW.cvars = { cooldownViewerEnabled = "1" }
    CW.settingsShown = false
    local added = {}
    local function global(name, v)
        if rawget(_G, name) == nil then added[#added + 1] = name end
        _G[name] = v
    end
    stub.onReset = stub.onReset or {}
    stub.onReset[#stub.onReset + 1] = function()
        for _, name in ipairs(added) do _G[name] = nil end
        for name in pairs(CW.enumsAdded or {}) do _G.Enum[name] = nil end
        CW.enumsAdded, CW.game, CW.G, CW.items = nil, nil, nil, {}
    end

    -- Enums are the client's, so addon code sees them too.
    CW.enumsAdded = {}
    for name, values in pairs(E) do
        if _G.Enum[name] == nil then
            _G.Enum[name] = values
            CW.enumsAdded[name] = true
        end
    end

    -- The catalogue as the C side hands it out.
    local set = opts.set or CW.SetWith(opts.with or 6673)
    local known, rank = {}, {}
    for i, id in ipairs(opts.known or {}) do known[id], rank[id] = true, i end
    local byID, order, layout = {}, {}, {}
    for _, r in ipairs(rows()) do
        if r.set == set then
            byID[r.id] = r
            order[#order + 1] = r
        end
    end
    table.sort(order, function(a, b) return a.order < b.order end)
    for _, id in ipairs(opts.shown or {}) do layout[id] = true end
    local TRACKED_BAR = E.CooldownViewerCategory.TrackedBar
    for _, id in ipairs(opts.bars or {}) do layout[id] = TRACKED_BAR end
    CW.rows, CW.layout = byID, layout

    local function rowKnown(r)
        if known[r.spell] then return true end
        for _, id in ipairs(r.links) do if known[id] then return true end end
        return false
    end
    -- A row flagged SelectHighestLevelLinkedSpell names the highest rank known.
    local function rowSpell(r)
        local best = r.spell
        if has(r.flags, HIGHEST_RANK) then
            for _, id in ipairs(r.links) do
                if known[id] and (not known[best] or rank[id] > rank[best]) then best = id end
            end
        end
        return best
    end
    local function info(id)
        local r = byID[id]
        if not r then return nil end
        local out = {
            cooldownID = r.id, spellID = rowSpell(r), linkedSpellIDs = fresh(r.links),
            selfAura = r.selfAura, hasAura = r.aura, charges = false, isKnown = rowKnown(r), isInvisible = false,
            flags = r.flags, category = r.category,
            spellCategoryID = r.spellCategory ~= 0 and r.spellCategory or nil,
            equipSlot = r.equipSlot ~= 0 and r.equipSlot or nil,
        }
        for k, v in pairs(opts.info and opts.info[id] or {}) do out[k] = v end
        return out
    end
    CW.Info = info
    -- The public calls. Each read hands out a new table, as the client's do.
    global("C_CooldownViewer", {
        GetCooldownViewerCategorySet = function(category, allowUnlearned)
            -- The client takes only the docs' 0 to 8. The settings code's negative
            -- HiddenActive and HiddenPassive are refused.
            if type(category) ~= "number" or category < 0 or category > 8 then
                error("bad argument #1 to '?' (Usage: local cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(category [, allowUnlearned]))", 2)
            end
            local out = {}
            for _, r in ipairs(order) do
                if r.category == category and (allowUnlearned or rowKnown(r)) then out[#out + 1] = r.id end
            end
            return out
        end,
        GetCooldownViewerCooldownInfo = info,
        GetValidAlertTypes = function()
            local t = E.CooldownViewerAlertEventType
            return { t.Available, t.PandemicTime, t.OnCooldown, t.ChargeGained, t.OnAuraApplied, t.OnAuraRemoved }
        end,
        IsCooldownViewerAvailable = function() return true, "" end,
    })
    global("GetSpellBaseCooldown", function(spellID) return CW.BaseCooldown(spellID), 0 end)
    global("C_CVar", {
        GetCVar = function(name) return CW.cvars[name] end,
        GetCVarBool = function(name) return CW.cvars[name] == "1" end,
        GetCVarDefault = function() return "1" end,
        SetCVar = function(name, value)
            CW.cvars[name] = tostring(value)
            stub.FireEvent("CVAR_UPDATE", name, tostring(value))
        end,
    })

    -- What the game's code needs from the C side and reads plain, being
    -- untainted. Each is the client's call of that name.
    local function mine(a) return a.sourceUnit == "player" or a.isFromPlayerOrPlayerPet == true end
    local function auras(unit, kind) return stub.auras[unit] and stub.auras[unit][kind] or {} end
    game.Space("C_UnitAuras", {
        GetUnitAuras = function(unit, filter)
            local kind = string.find(filter or "", "HARMFUL", 1, true) and "HARMFUL" or "HELPFUL"
            local own = string.find(filter or "", "PLAYER", 1, true) ~= nil
            local out = {}
            for _, a in ipairs(auras(unit, kind)) do
                if not own or mine(a) then out[#out + 1] = fresh(a) end
            end
            return out
        end,
        GetUnitAuraBySpellID = function(unit, spellID)
            for _, kind in ipairs({ "HELPFUL", "HARMFUL" }) do
                for _, a in ipairs(auras(unit, kind)) do
                    if a.spellId == spellID then return fresh(a) end
                end
            end
            return nil
        end,
        GetRefreshCarryOverDuration = function() return 0 end,
    })
    game.Space("C_Spell", {
        GetSpellCooldown = function(id)
            local c = CW.cooldowns[id]
            if not c then return { startTime = 0, duration = 0, isEnabled = true, modRate = 1, isOnGCD = false } end
            return { startTime = c.start, duration = c.duration, isEnabled = true, modRate = 1, isOnGCD = c.gcd == true }
        end,
        GetSpellCharges = function(id) return fresh(CW.charges[id]) end,
        GetSpellCastCount = function() return 0 end,
        IsSpellUsable = function() return true, false end,
        SpellHasRange = function() return false end,
        EnableSpellRangeCheck = function() end,
        IsSpellInRange = function() return nil end,
        GetSpellTexture = function(id) return id, id, nil end,
        GetLastCategoryCooldownSource = function() return nil end,
        GetItemCooldown = function() return nil end,
    })
    game.Space("C_SpellActivationOverlay", { IsSpellOverlayed = function() return false end })
    G.GetInventoryItemCooldown = function() return 0, 0, 1, false end
    G.GetNumTotemSlots = function() return 4 end
    G.UnitGUID = function(unit) return stub.units[unit] and (stub.units[unit].guid or unit) or nil end
    G.UnitAffectingCombat = function() return stub.combat == true end
    G.GetCVar = function(name) return CW.cvars[name] end
    G.GetCVarDefault = function() return "1" end
    G.COOLDOWN_DURATION_SEC = "%d"
    -- Helpers the client makes in C, or in a file the tests don't fetch.
    G.secretunwrap = stub.Plain
    G.securecall = function(fn, ...) return fn(...) end
    G.secureexecuterange = function(t, fn, ...) for k, v in pairs(t) do fn(k, v, ...) end end
    G.AddSourceLocationExclude = function() end
    G.nop = function() end
    G.tDeleteItem = function(t, item)
        local n = 0
        for i = #t, 1, -1 do
            if t[i] == item then table.remove(t, i); n = n + 1 end
        end
        return n
    end
    -- Tables the client refuses to tainted code. Only a proxy can be watched
    -- here (its metatable does the reading), which is what the game's aura map is.
    G.settablesecurity = function(t, option)
        if option ~= E.TableSecurityOption.DisallowTaintedAccess then return end
        local mt = getmetatable(t)
        if not mt or rawget(mt, "__guarded") then return end
        mt.__guarded = true
        local index, newindex = mt.__index, mt.__newindex
        local function guard()
            if (stub.inGame or 0) == 0 then
                error("attempted to index a table that cannot be accessed while tainted", 3)
            end
        end
        mt.__index = function(self, k) guard(); return index(self, k) end
        mt.__newindex = function(self, k, v) guard(); return newindex(self, k, v) end
    end
    G.ActionButtonSpellAlertManager = {
        ShowAlert = function(_, item) item.__spellAlert = true end,
        HideAlert = function(_, item) item.__spellAlert = nil end,
    }
    G.AuraUtil = { SetAuraBorderAtlasFromAura = function() end }
    -- A color as the game's code uses one (ColorMixin's readers).
    G.CreateColor = function(r, g, b, a)
        return { r = r, g = g, b = b, a = a,
                 GetRGB = function(c) return c.r, c.g, c.b end,
                 GetRGBA = function(c) return c.r, c.g, c.b, c.a end }
    end
    G.ItemUtil = { GetEquipSlotTexture = function() return nil end }

    for _, file in ipairs(CW.SHARED) do game.Load(file) end

    -- The registries are frames in the client (their XML mixes these in).
    local cvars = Mixin(CreateFrame("Frame"), G.CVarCallbackRegistry)
    game.Own(cvars)
    G.CVarCallbackRegistry = cvars
    game.Run(function() cvars:OnLoad() end)
    game.Own(G.EventRegistry.frameEventFrame)
    -- An addon's callback runs tainted, whatever the game was doing when it fired.
    local register = G.EventRegistry.RegisterCallback
    function G.EventRegistry:RegisterCallback(event, fn, owner, ...)
        if type(fn) == "function" and stub.IsAddonHandler(fn) then
            local addonFn = fn
            fn = function(...) return Blizz.Tainted(addonFn, ...) end
        end
        return register(self, event, fn, owner, ...)
    end
    global("EventRegistry", G.EventRegistry)

    -- The settings window and its data. The real window, data provider and
    -- layout manager aren't run. This stand-in answers what the viewers ask:
    -- which ids a row holds, the one info table per id (the items write their
    -- linked and override spell into it, as in game), and the alerts.
    local infos = {}
    local provider = {}
    -- The layout's row for an id beats the data's.
    local function rowOf(r) return type(layout[r.id]) == "number" and layout[r.id] or r.category end
    function provider:GetCooldownInfoForID(id)
        if infos[id] == nil then
            infos[id] = info(id) or false
            if infos[id] then infos[id].category = rowOf(byID[id]) end
        end
        return infos[id] or nil
    end
    function provider:GetCooldownDefaults(id)
        local r = byID[id]
        if not r then return nil end
        local buff = r.category == E.CooldownViewerCategory.TrackedBuff or r.category == E.CooldownViewerCategory.TrackedBar
        return { category = has(r.flags, HIDE_BY_DEFAULT) and (buff and -2 or -1) or r.category }
    end
    function provider:GetOrderedCooldownIDsForCategory(category, allowUnknown)
        local out = {}
        for _, r in ipairs(order) do
            local hidden = has(r.flags, HIDE_BY_DEFAULT) and not (opts.showAll or layout[r.id])
            if rowOf(r) == category and not hidden and (allowUnknown or rowKnown(r)) then out[#out + 1] = r.id end
        end
        return out
    end
    CW.provider = provider
    G.CooldownViewerSettings = {
        IsVisible = function() return CW.settingsShown end,
        GetDataProvider = function() return provider end,
        GetLayoutManager = function() return { GetAlerts = function(_, id) return CW.alerts[id] end } end,
    }

    -- Edit Mode. The real system mixin isn't run: this keeps each viewer's
    -- settings and hands them over the way the game's mixin does
    -- (EditModeCooldownViewerSystemMixin, EditModeSystemTemplates.lua).
    local S = E.EditModeCooldownViewerSetting
    local system = {}
    function system:OnSystemLoad()
        self.__settings = {}
        for k, v in pairs(PRESET_ALL) do self.__settings[S[k]] = v end
        for k, v in pairs(PRESET[self.systemIndex] or {}) do self.__settings[S[k]] = v end
    end
    function system:GetSettingValue(setting) return self.__settings[setting] end
    function system:HighlightSystem() end
    function system:ClearHighlight() end
    function system:UpdateSystemSettingOrientation() self.orientationSetting = self:GetSettingValue(S.Orientation) end
    function system:UpdateSystemSettingIconLimit() self.iconLimit = self:GetSettingValue(S.IconLimit) end
    function system:UpdateSystemSettingIconDirection() self.iconDirection = self:GetSettingValue(S.IconDirection) end
    function system:UpdateSystemSettingIconSize() self.iconScale = self:GetSettingValue(S.IconSize) / 100 end
    function system:UpdateSystemSettingIconPadding() self.iconPadding = self:GetSettingValue(S.IconPadding) end
    function system:UpdateSystemSettingOpacity() self:SetAlpha(self:GetSettingValue(S.Opacity) / 100) end
    function system:UpdateSystemSettingVisibleSetting()
        self.visibleSetting = self:GetSettingValue(S.VisibleSetting)
        self:UpdateShownState()
    end
    function system:UpdateSystemSettingBarContent() self:SetBarContent(self:GetSettingValue(S.BarContent)) end
    function system:UpdateSystemSettingHideWhenInactive()
        self:SetHideWhenInactive(self:GetSettingValue(S.HideWhenInactive) == 1)
    end
    function system:UpdateSystemSettingShowTimer() self:SetTimerShown(self:GetSettingValue(S.ShowTimer) == 1) end
    function system:UpdateSystemSettingShowTooltips() self:SetTooltipsShown(self:GetSettingValue(S.ShowTooltips) == 1) end
    function system:UpdateSystemSettingBarWidthScale() self:SetBarWidthScale(self:GetSettingValue(S.BarWidthScale) / 100) end
    G.EditModeCooldownViewerSystemMixin = system
    stub.TEMPLATES.EditModeCooldownViewerSystemTemplate = function(f) f.Selection = CreateFrame("Frame", nil, f) end
    stub.TEMPLATES.BottomManagedFrameTemplate = function() end
    stub.TEMPLATES.PingableCooldownViewerItemTemplate = function() end
    stub.TEMPLATES.CooldownPandemicFXTemplate = function() end
    stub.TEMPLATES.CooldownPandemicBarFXTemplate = function() end
    -- The managed frame containers stack the viewers at the screen's bottom.
    -- Nothing here reads that, so a managed frame just stays where it is.
    G.ManagedFrameMixin = { OnShow = function() end, OnHide = function() end }

    local addonTable = {}
    for _, file in ipairs(CW.VIEWER) do game.Load(file, "Blizzard_CooldownViewer", addonTable) end
    game.UI("LayoutFrame.xml")

    -- Every item the game makes is kept, to hide from addon code what the
    -- client hides.
    function game.made(f, template)
        if string.find(template or "", "^CooldownViewer.+ItemTemplate$") then CW.items[#CW.items + 1] = f end
    end
    game.UI("CooldownViewer.xml")
    game.enter, game.leave = CW.ShowSecrets, CW.HideSecrets

    CW.viewers = {}
    for _, name in ipairs(CW.NAMES) do CW.viewers[name] = _G[name] end
    -- Edit Mode hands every setting over as the UI loads, then the layout runs.
    game.Run(function()
        for _, name in ipairs(CW.NAMES) do
            local v = _G[name]
            for key in pairs(S) do
                local update = v["UpdateSystemSetting" .. key]
                if update and v:GetSettingValue(S[key]) ~= nil then update(v) end
            end
            v:RefreshLayout()
        end
    end)
    return CW
end

-- ---------------------------------------------------------------------
-- What addon code may not read. The game's code is untainted and works with
-- plain values. What it leaves on an item from a secret source reads secret to
-- an addon (seen in game on a warrior, in a fight): the aura's instance and
-- spell id, and the cooldown's times and "is it running" while one is drawn.
-- isActive, wasSetFromAura, isOnGCD and the shown state stay plain.
-- ---------------------------------------------------------------------

local AURA_FIELDS = { "auraInstanceID", "auraSpellID" }
local TIME_FIELDS = { "cooldownStartTime", "cooldownDuration", "cooldownIsActive", "isOnActualCooldown",
                      "availableAlertTriggerTime" }

local function hideField(item, k)
    local v = rawget(item, k)
    if v ~= nil and not issecretvalue(v) then rawset(item, k, stub.Secret(v)) end
end
function CW.HideSecrets()
    if stub.plainSecrets or not stub.AurasRestricted() then return end
    for _, item in ipairs(CW.items or {}) do
        local sid = rawget(item, "auraSpellID")
        if sid ~= nil and not stub.neverSecretAuras[stub.Plain(sid)] then
            for _, k in ipairs(AURA_FIELDS) do hideField(item, k) end
        end
        if item.wasSetFromAura or item.wasSetFromCooldown or item.wasSetFromCharges or item.wasSetFromItem then
            for _, k in ipairs(TIME_FIELDS) do hideField(item, k) end
        end
    end
end
function CW.ShowSecrets()
    for _, item in ipairs(CW.items or {}) do
        for _, list in ipairs({ AURA_FIELDS, TIME_FIELDS }) do
            for _, k in ipairs(list) do
                local v = rawget(item, k)
                if issecretvalue(v) then rawset(item, k, stub.Plain(v)) end
            end
        end
    end
end

-- ---------------------------------------------------------------------
-- A test's hands on the world
-- ---------------------------------------------------------------------

-- Runs fn as the game's own code.
function CW.Run(fn, ...) return CW.game.Run(fn, ...) end

-- The cooldown id of a spell's row in a category (0 Essential, 1 Utility,
-- 2 Tracked Buffs, 3 Tracked Bars).
function CW.ID(spellID, category)
    for id, r in pairs(CW.rows) do
        if r.spell == spellID and r.category == category then return id end
    end
end

-- The game's item showing a cooldown id, in any viewer (nil when it made none).
function CW.Item(cooldownID)
    for _, name in ipairs(CW.NAMES) do
        for item in CW.viewers[name].itemFramePool:EnumerateActive() do
            if item:GetCooldownID() == cooldownID then return item, CW.viewers[name] end
        end
    end
end

-- A viewer's Edit Mode setting ("HideWhenInactive", 0 or 1), changed the way
-- Edit Mode does it: the setting, its hand-over, then a layout pass.
function CW.Setting(name, key, value)
    local v = CW.viewers[name]
    CW.Run(function()
        v.__settings[Enum.EditModeCooldownViewerSetting[key]] = value
        v["UpdateSystemSetting" .. key](v)
        v:RefreshLayout()
    end)
end

-- The game lays a viewer's items out again (its settings changing, Edit Mode, a
-- full aura update): every item is released, taken again and filled.
function CW.Layout(name)
    local v = CW.viewers[name]
    CW.Run(function() v:RefreshLayout() end)
end

-- An aura lands on a unit, cast by you unless a.sourceUnit says otherwise.
-- UNIT_AURA follows, as the client sends it. Returns its instance id.
function CW.Aura(unit, spellID, a)
    a = fresh(a or {})
    CW.auraSeq = CW.auraSeq + 1
    a.spellId, a.auraInstanceID = spellID, CW.auraSeq
    a.name = a.name or ("Spell " .. spellID)
    a.icon = a.icon or spellID
    if a.sourceUnit == nil then a.sourceUnit = "player" end
    a.isFromPlayerOrPlayerPet = a.sourceUnit == "player"
    a.duration = a.duration or 30
    a.expirationTime = a.expirationTime or (a.duration > 0 and GetTime() + a.duration or 0)
    a.applications = a.applications or 0
    a.timeMod = a.timeMod or 1
    local kind = a.harmful and "HARMFUL" or "HELPFUL"
    a.isHelpful, a.isHarmful = not a.harmful, a.harmful == true
    stub.auras[unit] = stub.auras[unit] or {}
    stub.auras[unit][kind] = stub.auras[unit][kind] or {}
    table.insert(stub.auras[unit][kind], a)
    stub.FireEvent("UNIT_AURA", unit, { isFullUpdate = false, addedAuras = { fresh(a) } })
    return a.auraInstanceID
end

-- That aura is gone again (dispelled, clicked off, run out).
function CW.Unaura(unit, spellID)
    local gone = {}
    for _, kind in ipairs({ "HELPFUL", "HARMFUL" }) do
        local list = stub.auras[unit] and stub.auras[unit][kind] or {}
        for i = #list, 1, -1 do
            if list[i].spellId == spellID then
                gone[#gone + 1] = list[i].auraInstanceID
                table.remove(list, i)
            end
        end
    end
    if #gone > 0 then stub.FireEvent("UNIT_AURA", unit, { isFullUpdate = false, removedAuraInstanceIDs = gone }) end
end

-- A spell goes on cooldown (gcd = the global cooldown), or comes off it.
function CW.Cooldown(spellID, duration, gcd)
    CW.cooldowns[spellID] = duration and { start = GetTime(), duration = duration, gcd = gcd } or nil
    stub.spellCooldowns = stub.spellCooldowns or {}
    stub.spellCooldowns[spellID] = duration and (gcd and "gcd" or true) or nil
    -- The event names the spell, its base spell, its category and the category
    -- that started it (the global cooldown's own, when it is one).
    local gcdCategory = gcd and duration and CW.G.Constants.SpellCooldownConsts.GLOBAL_RECOVERY_CATEGORY or nil
    stub.FireEvent("SPELL_UPDATE_COOLDOWN", spellID, nil, nil, gcdCategory)
end

return CW
