-- Daylight UI's own Cooldown Manager layout in the fake game, shared by the CDM tests: the
-- hand-made stand-in, next to cdmworld.lua, which runs the game's real code.
local stub = require("stub")

local M = {}

-- The made-up spell ids in these tests (100 + a cooldown id, small numbers) are real
-- spells in the game's spell facts (CdmSpells.FACTS), which would give them real
-- cooldowns and buffs. So a test's world loads without the facts, unless it asks
-- for them with realFacts().
local theFacts
function M.loadWorld(opts)
    stub.neverSecretAuras = {}
    local DUI, unitFrames = stub.Load(opts)
    local S = stub.actionbars and stub.actionbars.CdmSpells
    if S then
        theFacts = S.FACTS
        S.FACTS = {}
    end
    return DUI, unitFrames
end

function M.realFacts()
    stub.actionbars.CdmSpells.FACTS = theFacts
    stub.actionbars.CdmCustom.Forget()
end

-- Makes every aura one the game never hides (C_Secrets calls it NeverSecret), so a
-- lookup by spell id answers in a fight too, as the client's does for such an aura.
-- For a buff the game has no item of its own for: its holder reads it by itself.
-- Call it before the first layout pass, which is when a holder is made. It ends
-- with its world (loadWorld).
function M.plainAuras()
    stub.neverSecretAuras = setmetatable({}, { __index = function() return true end })
end

function M.data()
    M.loadWorld({ actionbars = true })
    return stub.actionbars.CdmData
end

function M.empty() return { v = 2, pieces = {}, chains = {} } end

-- A set with one row of icons 11, 12, 13 at 0, 0 (36 px, gap 4).
function M.filled(D)
    local set = M.empty()
    D.AddChain(set, { 11, 12, 13 }, "icon", 0, 0)
    return set
end

function M.box(b) return { b.x, b.y, b.w, b.h } end

-- A logged-in Warrior (profiles are per class).
function M.profileWorld(class)
    local DUI = M.loadWorld({ actionbars = true })
    stub.units.player = stub.units.player or { isPlayer = true, name = "Tester" }
    stub.units.player.class = class or "WARRIOR"
    return DUI, stub.actionbars.CdmData
end

-- An old per-character layout (before profiles), moved as at login.
function M.oldLayout(DUI, D, g, set)
    local cdm = D.Store()
    cdm.sets = cdm.sets or {}
    cdm.sets[g] = set
    D.MoveToProfiles(true)
    return D.Get(g)
end

-- An old-format set (format 1): blocks, and buttons with block + order.
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

-- A layout from 1.6.0 or older, parked in cdmSaved under profile name.
function M.parked(DUI, name, g)
    local root = DUI.DB.Root()
    root.cdmSaved = root.cdmSaved or {}
    root.cdmSaved[name] = root.cdmSaved[name] or {}
    root.cdmSaved[name][g or 1] = M.oldSet({ M.oldBlock("icon") }, M.inBlock(1, { 11, 12 }))
end

-- From a player's report: two characters with the same first name shared one
-- entry in 1.6.3, and after 1.6.4 the second one's CDM was empty.
function M.boopy(last, class, db)
    local DUI = M.loadWorld({ actionbars = true, before = function()
        _G.GetRealmName = function() return "R" end
        stub.units.player = { name = "Boopy", lastName = last, isPlayer = true, class = class }
        DaylightUIDB = db or DaylightUIDB
    end })
    return DUI, stub.actionbars.CdmData
end

-- A player's saved file, cut down: one entry "Nightz-Realm" shared by a paladin
-- (Nightz Pali) and a hunter. The hunter logged in first on 1.6.4, so the
-- paladin's layout became p1, a HUNTER profile "Nightz". The paladin, seeing
-- nothing, opened the editor and got p2, empty, picked.
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
    D.Get(1)   -- the first layout pass, as in game
    return DUI, D
end

-- A viewer of the game's shape: items with a cooldownID (nil = unused pool item).
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
        -- The game's own rule (Blizzard_CooldownViewer CooldownViewer.lua). A buff
        -- item is active only while its aura is up, and a row that hides inactive
        -- icons (the default for buffs) shows it only then. A cooldown icon is
        -- always active and says it shows its aura with wasSetFromAura.
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
        -- A cooldown icon's aura landing or ending, as the game's viewer does it on
        -- UNIT_AURA: the removed alert first, the item's own refresh, the applied
        -- alert last.
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
    -- The game's RefreshLayout (CooldownViewer.lua): every item is released
    -- (hidden, anchors cleared), acquired again and shown, then put back in the
    -- viewer's own grid. Only the game's code runs it: on its settings changing
    -- (EventRegistry "CooldownViewerSettings.OnDataChanged"), a full aura update,
    -- Edit Mode, or the viewer showing.
    function v:RefreshLayout()
        self.__laid = (self.__laid or 0) + 1
        for _, item in ipairs(items) do item:Hide(); item:ClearAllPoints() end
        for i, item in ipairs(items) do
            if item.cooldownID then
                item:Show()
                -- (a test's own bare frame has no state of its own)
                if item.UpdateShownState then item:UpdateShownState() end
                item:SetPoint("TOPLEFT", self, "TOPLEFT", (i - 1) * 40, 0)
            end
        end
    end
    -- A bar's content (Edit Mode "Icon and name" 1, "Name only" 3). The game
    -- hides or shows the icon frame and adds a LEFT point to the bar.
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

-- The game's event hub (CallbackRegistry). Callbacks are kept per event and
-- called as fn(owner, ...).
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

-- Essential: ids 11, 12, 13; BuffBar: 21, 22.
-- buffIcons: ids for a Tracked Buffs icon viewer too (5th in the items).
function M.rowsWorld(buffIcons, alsoLoad)
    alsoLoad = alsoLoad or {}
    local ess, bars, icons
    local DUI, unitFrames = M.loadWorld({ actionbars = true, module = alsoLoad.module, buffs = alsoLoad.buffs, before = function()
        M.fakeRegistry()
        _, ess = M.fakeViewer("EssentialCooldownViewer", { 11, 12, 13 })
        _, bars = M.fakeViewer("BuffBarCooldownViewer", { 21, 22 })
        if buffIcons then _, icons = M.fakeViewer("BuffIconCooldownViewer", buffIcons) end
    end })
    stub.RunTimers()
    return DUI, stub.actionbars, ess, bars, icons, alsoLoad.module and unitFrames or nil
end

-- The addon's own icons and bars ease their alpha (CdmEffects setAlpha), so let it land.
function M.eased(DUI)
    local d = DUI.Motion.Driver()
    if d then stub.RunOnUpdate(d, 1) end
end

function M.settledPass(AB)
    AB.CdmRows.Refresh()
    stub.RunTimers()
    M.eased(DaylightUI)
end

function M.layoutFrame(g) return _G["DaylightUICdmLayout" .. g] end

function M.pieceFrame(g, id) return _G["DaylightUICdmPiece" .. g .. "_" .. id] end

function M.shownPieceIds(set, g)
    local ids = {}
    for id in pairs(set.pieces) do
        local frame = M.pieceFrame(g, id)
        if frame and frame:IsShown() then ids[id] = true end
    end
    return ids
end

function M.changeSpecTo(DUI, g)
    DUI.DB.SpecGroup = function() return g end
    stub.FireEvent("ACTIVE_TALENT_GROUP_CHANGED")
end

function M.pressEditorKey(key)
    local overlay = _G.DaylightUICdmEditor
    overlay:GetScript("OnKeyDown")(overlay, key)
end

function M.stepEditor(Ed) stub.RunOnUpdate(Ed.Overlay(), 0) end

-- Drags group 11 to dx right of the screen's center.
function M.dragGroup(Ed, dx, whileDragging)
    local isMouseButtonDown = _G.IsMouseButtonDown
    _G.IsMouseButtonDown = function() return true end
    local ok, err = pcall(function()
        stub.cursorPos = { 960 + dx, 540 }
        Ed.StartDrag(11, 0, 0)
        M.stepEditor(Ed)
        if whileDragging then whileDragging(Ed.Dragging()) end
        _G.IsMouseButtonDown = function() return false end
        M.stepEditor(Ed)
    end)
    _G.IsMouseButtonDown = isMouseButtonDown
    if not ok then error(err, 0) end
end

function M.selectAndSettle(Ed, id)
    Ed.Select(id)
    M.eased(DaylightUI)
end

-- UIParent units from the screen's bottom-left.
function M.moveLead(frame, l, b, w, h)
    frame:SetSize(w, h)
    frame.__center = { l + w / 2, b + h / 2 }
end

function M.lead(key, l, b, w, h)
    local frame = CreateFrame("Frame", nil, UIParent)
    DaylightUI.Movers.Register(frame, key, key, { "TOP", nil, "CENTER", 0, 0 })
    if l then M.moveLead(frame, l, b, w, h) end
    return frame
end

function M.hangOff(frame, relative)
    frame:ClearAllPoints()
    frame:SetPoint("TOP", relative, "BOTTOM", 0, 0)
end

return M
