-- Daylight's own Cooldown Manager layout in the fake game, shared by the CDM tests.
local stub = require("stub")
local H = require("helpers")

local M = {}

-- The made-up spell ids are real spells in CdmSpells.FACTS, so worlds load without the facts.
local theFacts
function M.loadWorld(opts)
    stub.neverSecretAuras = {}
    local DUI = stub.Load(opts)
    local S = stub.actionbars and stub.actionbars.CdmSpells
    if S then
        theFacts = S.FACTS
        S.FACTS = {}
    end
    return DUI
end

function M.realFacts()
    stub.actionbars.CdmSpells.FACTS = theFacts
    stub.actionbars.CdmCustom.Forget()
end

-- Every aura NeverSecret, so a spell id lookup answers in a fight. Call before the first layout pass.
function M.plainAuras()
    stub.neverSecretAuras = setmetatable({}, { __index = function() return true end })
end

function M.data()
    M.loadWorld({ actionbars = true })
    return stub.actionbars.CdmData
end

function M.empty() return { v = 2, pieces = {}, chains = {} } end

-- Default icons: 36 px, gap 4.
function M.filled(D)
    local set = M.empty()
    D.AddChain(set, { 11, 12, 13 }, "icon", 0, 0)
    return set
end

function M.box(b) return { b.x, b.y, b.w, b.h } end

-- Profiles are per class.
function M.profileWorld(class)
    local DUI = M.loadWorld({ actionbars = true })
    stub.units.player = stub.units.player or { isPlayer = true, name = "Tester" }
    stub.units.player.class = class or "WARRIOR"
    return DUI, stub.actionbars.CdmData
end

-- A pre-profiles per-character layout, moved as at login.
function M.oldLayout(DUI, D, g, set)
    local cdm = D.Store()
    cdm.sets = cdm.sets or {}
    cdm.sets[g] = set
    D.MoveToProfiles(true)
    return D.Get(g)
end

-- A format 1 set.
function M.oldSet(blocks, buttons) return { blocks = blocks, buttons = buttons } end

function M.oldBlock(kind, over)
    local b = kind == "bar"
        and { kind = "bar", dir = "column", x = 0, y = 0, grow = "end", wrap = "right", size = 18, width = 220,
              spacing = 2, collapse = true, combat = false, always = false, color = "class", icon = true, text = 11, time = true }
        or { kind = "icon", dir = "row", x = 0, y = 0, grow = "center", wrap = "down", size = 36, spacing = 4,
              perLine = 8, collapse = true, combat = false, always = false }
    for k, v in pairs(over or {}) do b[k] = v end
    return b
end

function M.inBlock(i, ids)
    local t = {}
    for n, id in ipairs(ids) do t[id] = { block = i, order = n } end
    return t
end

-- A layout as 1.6.0 and older parked it.
function M.parked(DUI, name, g)
    local root = DUI.DB.Root()
    root.cdmSaved = root.cdmSaved or {}
    root.cdmSaved[name] = root.cdmSaved[name] or {}
    root.cdmSaved[name][g or 1] = M.oldSet({ M.oldBlock("icon") }, M.inBlock(1, { 11, 12 }))
end

-- A player's report: same-named characters shared one entry in 1.6.3, and 1.6.4 emptied one's CDM.
function M.boopy(last, class, db)
    local DUI = M.loadWorld({ actionbars = true, before = function()
        _G.GetRealmName = function() return "R" end
        stub.units.player = { name = "Boopy", lastName = last, isPlayer = true, class = class }
        DaylightUIDB = db or DaylightUIDB
    end })
    return DUI, stub.actionbars.CdmData
end

-- A player's file: a paladin and a hunter shared one entry, so 1.6.4 made the paladin's layout the
-- hunter's p1, and the paladin's editor picked a new, empty p2.
function M.nightzFile()
    return { version = 2, profileData = { Nightz = {} }, cdmMoved = 2, cdmNextProfile = 2, cdmSaved = {},
        cdmProfiles = {
            p1 = { class = "HUNTER", name = "Nightz", set = { v = 2, chains = {}, pieces = {
                ["s1311649"] = { shape = "icon", x = 1, y = -176 },
                [200265] = { shape = "icon", parent = "s1311649", side = "left", align = "center" } } } },
            p2 = { class = "PALADIN", name = "Paladin", set = { v = 2, chains = {}, pieces = {} } },
        },
        characters = { ["Nightz-R"] = { class = "PALADIN", mailName = "Nightz Pali", profile = "Nightz",
            install = "installed", cdm = { use = { "p2" } } } } }
end

function M.nightz(last, class, db)
    local DUI = M.loadWorld({ actionbars = true, before = function()
        _G.GetRealmName = function() return "R" end
        stub.units.player = { name = "Nightz", lastName = last, isPlayer = true, class = class }
        DaylightUIDB = db
    end })
    local D = stub.actionbars.CdmData
    D.Get(1)   -- first layout pass, as in game
    return DUI, D
end

-- An item with no cooldownID is an unused pool item.
function M.fakeViewer(name, ids)
    local v = CreateFrame("Frame", name, UIParent)
    local items = {}
    for i, id in ipairs(ids) do
        local item = CreateFrame("Frame", nil, v)
        item:SetSize(40, 40)
        item.cooldownID = id
        item.layoutIndex = i
        item.Icon = item:CreateTexture()
        item.Cooldown = CreateFrame("Cooldown", nil, item)
        if name == "BuffBarCooldownViewer" then
            item.Icon = CreateFrame("Frame", nil, item)
            item.Icon.Icon = item.Icon:CreateTexture()
            item.Bar = CreateFrame("StatusBar", nil, item)
            item.Bar.Name = item.Bar:CreateFontString()
            item.Bar.Duration = item.Bar:CreateFontString()
        end
        -- The game's rule: a buff item is active only while its aura is up; a cooldown icon always is.
        local aura = name == "BuffIconCooldownViewer" or name == "BuffBarCooldownViewer"
        item.allowHideWhenInactive = aura or nil
        item.hideWhenInactive = aura
        item.isActive = true
        item.wasSetFromAura = false
        function item:GetCooldownID() return self.cooldownID end
        function item:IsActive() return self.isActive end
        function item:ShouldBeShown()
            if self:GetCooldownID() then
                if not self.allowHideWhenInactive then return true end
                if not self.hideWhenInactive then return true end
                if self:IsActive() then return true end
            end
            return false
        end
        function item:UpdateShownState() self:SetShown(self:ShouldBeShown()) end
        function item:OnActiveStateChanged() self:UpdateShownState() end
        function item:SetIsActive(active)
            if active ~= self.isActive then
                self.isActive = active
                self:OnActiveStateChanged()
            end
        end
        function item:SetHideWhenInactive(hide)
            self.hideWhenInactive = hide
            self:UpdateShownState()
        end
        function item:TriggerAuraAppliedAlert() end
        function item:TriggerAuraRemovedAlert() end
        function item:TriggerAvailableAlert() end
        -- As the game on UNIT_AURA: removed alert, the item's refresh, applied alert.
        function item:SetAura(on)
            if not on then self:TriggerAuraRemovedAlert() end
            self.wasSetFromAura = on and true or false
            self.auraInstanceID = on and 7 or nil
            if on then self:TriggerAuraAppliedAlert() end
        end
        items[i] = item
    end
    v.itemFramePool = { EnumerateActive = function()
        local i = 0
        return function() i = i + 1; return items[i] end
    end }
    -- As the game's: every item released and unanchored, then the used ones shown in its own grid.
    function v:RefreshLayout()
        self.__laid = (self.__laid or 0) + 1
        for _, item in ipairs(items) do item:Hide(); item:ClearAllPoints() end
        for i, item in ipairs(items) do
            if item.cooldownID then
                item:Show()
                if item.UpdateShownState then item:UpdateShownState() end
                item:SetPoint("TOPLEFT", self, "TOPLEFT", (i - 1) * 40, 0)
            end
        end
    end
    -- Edit Mode bar content: 1 "Icon and name", 3 "Name only".
    if name == "BuffBarCooldownViewer" then
        for _, item in ipairs(items) do
            function item:SetBarContent(c)
                if c == 3 then self.Icon:Hide() else self.Icon:Show() end
                self.Bar:SetPoint("LEFT", self.Icon, c == 3 and "LEFT" or "RIGHT", c == 3 and 0 or 2, 0)
            end
        end
    end
    if _G.EventRegistry then
        _G.EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", v.RefreshLayout, v)
    end
    v:RegisterUnitEvent("UNIT_AURA", "player", "target")
    v:SetScript("OnEvent", function(self, event, _, info)
        if event == "UNIT_AURA" and (not info or info.isFullUpdate) then self:RefreshLayout() end
    end)
    return v, items
end

function M.fakeRegistry()
    local cbs = {}
    _G.EventRegistry = {
        RegisterCallback = function(_, e, fn, owner)
            cbs[e] = cbs[e] or {}
            cbs[e][#cbs[e] + 1] = { fn, owner }
        end,
        UnregisterCallback = function() end,
        TriggerEvent = function(_, e, ...)
            for _, c in ipairs(cbs[e] or {}) do c[1](c[2], ...) end
        end,
    }
end

function M.rowsWorld(buffIcons)
    local ess, bars, icons
    local DUI = M.loadWorld({ actionbars = true, before = function()
        M.fakeRegistry()
        _, ess = M.fakeViewer("EssentialCooldownViewer", { 11, 12, 13 })
        _, bars = M.fakeViewer("BuffBarCooldownViewer", { 21, 22 })
        if buffIcons then _, icons = M.fakeViewer("BuffIconCooldownViewer", buffIcons) end
    end })
    stub.RunTimers()
    return DUI, stub.actionbars, ess, bars, icons
end

function M.runGlidesFor(seconds)
    local driver = DaylightUI.Motion.Driver()
    if driver then stub.RunOnUpdate(driver, seconds) end
end

function M.layoutFrame(g) return _G["DaylightUICdmLayout" .. g] end

function M.pieceFrame(g, id) return _G["DaylightUICdmPiece" .. g .. "_" .. id] end

function M.changeSpecTo(DUI, g)
    DUI.DB.SpecGroup = function() return g end
    stub.FireEvent("ACTIVE_TALENT_GROUP_CHANGED")
end

function M.pressEditorKey(key, shifted)
    local overlay = _G.DaylightUICdmEditor
    H.withShiftHeld(shifted, function() overlay:GetScript("OnKeyDown")(overlay, key) end)
end

return M
