-- Group frames: a party or raid shown as buttons that a secure group header
-- creates, sorts and places by itself, even in combat (using bare buttons made
-- ahead, see Group:MakeAhead). One Group object per group: a plain holder that
-- carries the position and mover, the header attached to it, and plain sample
-- buttons for test mode. The raid makes one (Raid.lua) and the party another
-- (Party.lua), each saying what its buttons are made of and which settings it
-- reads. Every button is set up by the same builder as the other frames, the
-- first time it gets a member.

local _, ns = ...
local DUI = DaylightUI
local UF, Style, Pixel = ns.UF, DUI.Style, DUI.Pixel
local GP = ns.GroupParts

local Group = {}
Group.__index = Group
ns.Group = Group

Group.PER_GROUP = 5
Group.all = {}   -- every group created, in creation order

Group.ROLE_ORDER = "TANK,HEALER,DAMAGER,NONE"

-- For a header's visibility driver. [group] and [group:raid] keep the value
-- they had when combat began, so a group joined mid-fight reads as solo until
-- it ends, while unit tokens follow the roster right away. raid1 only exists in
-- a raid, party1 only with someone else in the party, and [group] holds for a
-- group of one.
Group.IN_RAID = "[@raid1,exists]"
Group.IN_PARTY = "[@party1,exists][group]"

-- Sorting (sortBy): anything other than "group" lists members in one order.
Group.SORT_ATTRS = {
    role  = { groupBy = "ASSIGNEDROLE", groupingOrder = Group.ROLE_ORDER, sortMethod = "INDEX" },
    class = { groupBy = "CLASS", sortMethod = "INDEX",
              groupingOrder = "WARRIOR,PALADIN,DEATHKNIGHT,DRUID,MONK,DEMONHUNTER,EVOKER,SHAMAN,ROGUE,HUNTER,MAGE,WARLOCK,PRIEST" },
    name  = { sortMethod = "NAME" },
}
-- "Group, then role" (raid only): one header per raid group, each sorted by
-- role. A single header using it (the party, one group) just sorts by role.
Group.SORT_ATTRS.grouprole = Group.SORT_ATTRS.role

Group.SAMPLE_DISPEL_ICON = "Interface\\Icons\\Spell_Shadow_CurseOfTounges"

-- The header's size snippet runs in its secure environment, then hands the new
-- button's name back to Lua to be set up.
local INIT = [[
    local header = self:GetParent()
    self:SetWidth(header:GetAttribute("unitWidth"))
    self:SetHeight(header:GetAttribute("unitHeight"))
    self:SetAttribute("*type1", "target")
    self:SetAttribute("*type2", "togglemenu")
    local clickcast = header:GetFrameRef("clickcast_header")
    if clickcast then
        clickcast:SetAttribute("clickcast_button", self)
        clickcast:RunAttribute("clickcast_register")
    end
    header:CallMethod("initialConfigFunction", self:GetName())
]]

-- opts (what makes one group differ from another):
--   key            "raid" or "party": its settings table and mover ("unitframes." .. key)
--   name           global name stem: <name>Holder, <name>Header
--   spec           what its buttons are made of (UF.Build)
--   maxCount       the most members it ever shows (raid 40, party 5)
--   attrs          the header's fixed attributes ({ showRaid = true, ... })
--   config()       -> cfg, text, db: the settings in use (nil before login)
--   count(cfg)     -> how many members the holder makes room for now
--   previewCount(cfg) -> how many samples test mode shows
--   visibility(cfg)   -> the header's state-driver condition while it's on
--   solo(cfg)      -> optional: the header's showSolo (you alone, out of a group)
--   sampleFor(i, cfg) -> sample member i for test mode
--   sampleUnit(i)  -> the unit a sample button stands for
-- Optional:
--   hideInTest()      -> true keeps its samples hidden in this test mode
--   hideHeaderInTest  true: the real buttons go see-through while previewing
--   dress(b)          extra parts for a new button (and for each sample)
--   auraGroups        true: each button gets the aura groups (AuraGroups.lua) as b.auraSet
--   showSample(b, i, cfg) / hideSample(b)  those parts' test-mode samples
--   layoutButton(b)   extra parts laid out with each real button (the party's pets)
--   isOn(cfg)         -> is it switched on (default cfg.enabled; the raid: its 10-player switch)
--   groupHeaders      n: also make a header per raid group 1..n, for "Group, then role"
function Group.New(opts)
    local g = setmetatable({ opts = opts, key = opts.key, buttons = {}, bare = {}, headers = {} }, Group)
    Group.all[#Group.all + 1] = g
    return g
end

-- Every set-up button of every group, party and raid alike:
--   for _, b in Group.Buttons() do ... end
function Group.Buttons()
    local gi, bi = 1, 0
    return function()
        while Group.all[gi] do
            bi = bi + 1
            local b = Group.all[gi].buttons[bi]
            if b then return bi, b end
            gi, bi = gi + 1, 0
        end
    end
end

-- Tiles per line: a group's five by default (the header then keeps each group
-- together). Any other number lists members in order. "Group, then role"
-- always puts one group per line.
function Group.PerLine(cfg)
    if cfg.sortBy == "grouprole" then return Group.PER_GROUP end
    local n = cfg.perLine
    if type(n) ~= "number" or n < 1 then return Group.PER_GROUP end
    return math.floor(n)
end

-- Raid groups shown: 1 to n (raid.groups), anything else means all of them.
function Group.GroupsShown(cfg, groups)
    local n = tonumber(cfg.groups)
    if n and n >= 1 and n < groups then return math.floor(n) end
    return groups
end

-- Which way the tiles run: "columns" (each line a column, left to right) or
-- "rows" (each line a row, stacked down).
function Group.Direction(cfg)
    return cfg.direction == "rows" and "rows" or "columns"
end

-- The holder corner the tiles start from: top left, unless they grow up from
-- the bottom (growUp) or leftward from the right (growLeft), so a small group
-- sits near that edge.
function Group.Corner(cfg)
    return (cfg.growUp == true and "BOTTOM" or "TOP") .. (cfg.growLeft == true and "RIGHT" or "LEFT")
end

-- The y offset from the holder's corner, past Ribbon's reach (Group:Pads).
local function cornerY(cfg, holder)
    if cfg.growUp == true then return holder.padDown or 0 end
    return -(holder.padUp or 0)
end

-- How much room count members take, laid out per cfg in rows or columns. w, h
-- are the button's size (defaults to the settings'). Returns width, height.
function Group.Footprint(cfg, count, rows, w, h)
    w, h = w or cfg.width, h or cfg.height
    local per = Group.PerLine(cfg)
    local lines = math.max(1, math.ceil(count / per))
    per = math.min(per, count)
    local long = per * (rows and w or h) + (per - 1) * cfg.spacing
    local across = lines * (rows and h or w) + (lines - 1) * cfg.groupSpacing
    if rows then return long, across end
    return across, long
end

-- Ribbon (UF.RibbonReach): the first frame's name row reaches above the holder
-- and the last one's power line below it, so the holder (the unlock handle)
-- includes them and the frames start this far down inside it. Returns up,
-- down, or 0, 0 for a group that can't use Ribbon.
function Group:Pads(cfg)
    if not self.opts.spec.ribbon then return 0, 0 end
    return UF.RibbonReach(cfg, self.holder or UIParent)
end

-- The settings in use: a sweep step's (Sweep.lua), or the group's own.
function Group:Config()
    if self.sweep then
        local _, _, d = self.opts.config()
        return self.sweep.cfg, self.sweep.text, d or { range = {} }
    end
    return self.opts.config()
end

function Group:IsOn(cfg)
    if self.opts.isOn then return self.opts.isOn(cfg) end
    return cfg.enabled == true
end

-- "Group, then role" is on for a group that has per-group headers.
function Group:Split(cfg)
    return #self.headers > 0 and cfg.sortBy == "grouprole"
end

-- A button the header just made: bare, sized by the snippet, cheap. It's set up
-- the moment it first gets a member, in combat too. Setting up a button takes
-- about 60 ms, so nobody pays for the raid's forty until they're in a raid.
function Group:Take(b)
    if b.taken then return end
    b.taken = true
    self.bare[#self.bare + 1] = b
    local g = self
    b:HookScript("OnAttributeChanged", function(btn, name, value)
        if name ~= "unit" or g.making then return end
        if not btn.spec then
            if value ~= nil then g:Dress(btn) end
            return
        end
        -- The header sets this on every roster update, usually to the same unit.
        -- Only an actual change rewires the events and auras.
        if value == btn.unitToken then return end
        btn.unitToken = value
        -- Record who it is now, so the roster pass a frame later (Units.lua)
        -- doesn't redo all of this.
        btn.rosterWho = type(value) == "string" and UnitExists(value) and ns.WhoOn(value) or nil
        UF.RegisterUnitEvents(btn)
        GP.PointAuras(btn)
        ns.GroupPrivate.Update(btn)
        UF.UpdateAll(btn, true)
        GP.UpdateTargetMark(btn)
        -- Notify once it's redrawn, so a listener reads the new member's tile.
        DUI.APIReport.Unit(g.key, btn, type(value) == "string" and value or nil, false)
    end)
    -- Right-clicks open the unit menu like the other frames. Protected.
    if InCombatLockdown() then
        DUI.AfterCombat(function() b:RegisterForClicks("AnyUp") end, "clicks:" .. (b:GetName() or tostring(b)))
    else
        b:RegisterForClicks("AnyUp")
    end
    if b:GetAttribute("unit") ~= nil then self:Dress(b) end
end

-- Sets up a button for its first member, possibly in combat. Nothing here is
-- protected and its size came from the snippet. In combat its aura rows and
-- containers (protected parent) are laid out once the fight is over.
function Group:Dress(b)
    if b.spec then return end
    for i, bare in ipairs(self.bare) do
        if bare == b then table.remove(self.bare, i); break end
    end
    UF.Build(b, self.opts.spec)
    b.group = self
    GP.CreateDispel(b)
    GP.CreateTint(b)
    GP.CreateGlow(b)
    GP.MakeTargetMark(b)
    if self.opts.auraGroups then
        b.auraSet = ns.AuraGroups.Create(b, type(b.unitToken) == "string" and b.unitToken or nil)
    end
    if self.opts.dress then self.opts.dress(b) end
    ns.GroupPrivate.Create(b)
    self.buttons[#self.buttons + 1] = b
    if type(ClickCastFrames) == "table" then ClickCastFrames[b] = true end
    -- Click-casting bindings (ClickCast.lua).
    ns.ClickCast.Dress(b)
    -- Unit first, so Wire registers its unit events once and the roster pass a
    -- frame later knows who it already drew.
    b.unitToken = b:GetAttribute("unit")
    b.rosterWho = type(b.unitToken) == "string" and UnitExists(b.unitToken) and ns.WhoOn(b.unitToken) or nil
    UF.Wire(b)
    GP.PointAuras(b)
    local cfg, text, d = self:Config()
    if cfg then
        local fighting = InCombatLockdown()
    -- The snippet sized it. Out of combat here, so the layout below reads the
    -- header's size regardless of what ran first.
        local hdr = b:GetParent() or self.header
        local w, ht = hdr:GetAttribute("unitWidth"), hdr:GetAttribute("unitHeight")
        if not fighting and type(w) == "number" and type(ht) == "number" then b:SetSize(w, ht) end
        self:LayoutButton(b, cfg, text, d.range, fighting)
        if fighting then
            -- Placed now so a member who joins mid-fight shows auras. The
            -- containers aren't protected and their counts are allowed in
            -- combat. The client's locked buttons take their size once
            -- restrictions lift (Auras.lua). Done again after the fight.
            pcall(self.LayoutAuras, self, b, cfg, text)
            local g = self
            DUI.AfterCombat(function()
                local c, t = g:Config()
                if c then g:LayoutAuras(b, c, t) end
            end, "dress:" .. (b:GetName() or tostring(b)))
        end
    end
    UF.UpdateAll(b, true)
    DUI.APIReport.Made(self.key, b, type(b.unitToken) == "string" and b.unitToken or nil, false)
end

-- One button's settings: fades, the frame and its parts. Its size is the
-- header's. noAuras leaves the aura containers to the caller (in combat the
-- header may create a button mid-fight, see Group:Dress).
function Group:LayoutButton(b, cfg, text, range, noAuras)
    b.rangeFade, b.rangeAlpha = range.enabled, UF.RangeAlpha(range, true)
    self:WearIcons(b)
    UF.Layout(b, cfg, text, true)
    GP.LayoutTargetMark(b, cfg)
    GP.UpdateTargetMark(b)
    if not noAuras then self:LayoutAuras(b, cfg, text) end
    if self.opts.layoutButton then self.opts.layoutButton(b) end
end

-- The class icon style and each class's pick (Extras), as the single frames
-- use them (Units.lua).
function Group:WearIcons(b)
    local _, _, d = self.opts.config()
    local p = d and d.portraits
    b.iconStyle, b.classIcons = p and p.icons, p and p.classIcons
end

-- The button's aura containers: dispel and the aura groups. Containers on a
-- protected parent are allowed in combat (Group:Dress) and redone afterwards.
-- The boss debuff slots too (their anchors wait out combat on their own).
function Group:LayoutAuras(b, cfg)
    GP.LayoutDispel(b, cfg)
    ns.GroupPrivate.Layout(b, cfg)
    if b.auraSet then
        local box = ns.AuraGroups.Box(b, cfg)
        DUI.SafeCall(ns.AuraGroups.Place, b.auraSet, b, cfg.auras, box)
        DUI.SafeCall(ns.Indicators.Place, b.auraSet, b, cfg.indicators, box)
    end
end

-- Sets up one secure header: its buttons' template, the fixed attributes, the
-- size snippet, Clique, and setup for each button it creates.
function Group:MakeHeader(name, parent)
    local h = CreateFrame("Frame", name, parent, "SecureGroupHeaderTemplate")
    h:SetAttribute("template", UF.BUTTON_TEMPLATE)   -- also pingable (UnitFrames.lua)
    for k, v in pairs(self.opts.attrs) do h:SetAttribute(k, v) end
    h:SetAttribute("initialConfigFunction", INIT)
    -- Clique's own header integration: point the header at Clique's click-cast
    -- header so every member button it creates registers for click-casting.
    -- A group header has no SetFrameRef method, so the game's helper sets it.
    if ClickCastHeader and SecureHandlerSetFrameRef then
        SecureHandlerSetFrameRef(h, "clickcast_header", ClickCastHeader)
    end
    local g = self
    h.initialConfigFunction = function(_, n)
        local b = _G[n]
        if b then g:Take(b) end
    end
    return h
end

function Group:Create()
    local o = self.opts
    local holder = CreateFrame("Frame", o.name .. "Holder", UIParent)
    local h = self:MakeHeader(o.name .. "Header", holder)
    h:SetAttribute("groupBy", "GROUP")
    h:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
    h:SetAttribute("maxColumns", math.ceil(o.maxCount / Group.PER_GROUP))
    h:SetAttribute("unitsPerColumn", Group.PER_GROUP)
    -- Members top to bottom, lines as columns, left to right.
    h:SetAttribute("point", "TOP")
    h:SetAttribute("columnAnchorPoint", "LEFT")
    h:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    -- "Group, then role": one header per raid group, each its own line, members
    -- by role. Off until that sort is picked (SetEnabled).
    for i = 1, o.groupHeaders or 0 do
        local gh = self:MakeHeader(o.name .. "Group" .. i .. "Header", holder)
        gh:SetAttribute("groupFilter", tostring(i))
        gh:SetAttribute("groupBy", "ASSIGNEDROLE")
        gh:SetAttribute("groupingOrder", Group.ROLE_ORDER)
        gh:SetAttribute("sortMethod", "INDEX")
        gh:SetAttribute("unitsPerColumn", Group.PER_GROUP)
        gh:SetAttribute("maxColumns", 1)
        self.headers[i] = gh
    end
    self.holder, self.header = holder, h
    return holder
end

-- The headers' growth for a direction. Protected, out of combat only.
function Group:ApplyDirection(cfg)
    local h = self.header
    local rows = Group.Direction(cfg) == "rows"
    local up, left, s = cfg.growUp == true, cfg.growLeft == true, cfg.spacing
    -- The game's header steps each member by the offset's own sign past the
    -- point's other side (see its group header code), so up and left are
    -- positive y and negative x.
    local point, xo, yo, anchor = up and "BOTTOM" or "TOP", 0, up and s or -s, left and "RIGHT" or "LEFT"
    if rows then point, xo, yo, anchor = left and "RIGHT" or "LEFT", left and -s or s, 0, up and "BOTTOM" or "TOP" end
    for _, hh in ipairs({ h, unpack(self.headers) }) do
        hh:SetAttribute("point", point)
        hh:SetAttribute("xOffset", xo)
        hh:SetAttribute("yOffset", yo)
        hh:SetAttribute("columnAnchorPoint", anchor)
        hh:SetAttribute("columnSpacing", cfg.groupSpacing)
    end
    -- Tiles per line: by group (five), or members listed in order.
    local per = Group.PerLine(cfg)
    local sort = Group.SORT_ATTRS[cfg.sortBy]
    if sort then
        h:SetAttribute("groupBy", sort.groupBy)
        h:SetAttribute("groupingOrder", sort.groupingOrder)
        h:SetAttribute("sortMethod", sort.sortMethod)
    elseif per == Group.PER_GROUP then
        h:SetAttribute("groupBy", "GROUP")
        h:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
        h:SetAttribute("sortMethod", "INDEX")
    else
        h:SetAttribute("groupBy", nil)
        h:SetAttribute("groupingOrder", nil)
        h:SetAttribute("sortMethod", "INDEX")
    end
    -- Raid groups shown: 1 to n (showing all leaves the filter off).
    local groups = math.ceil(self.opts.maxCount / Group.PER_GROUP)
    local n = Group.GroupsShown(cfg, groups)
    if n < groups then
        local list = {}
        for i = 1, n do list[i] = i end
        h:SetAttribute("groupFilter", table.concat(list, ","))
    else
        h:SetAttribute("groupFilter", nil)
    end
    h:SetAttribute("unitsPerColumn", per)
    h:SetAttribute("maxColumns", math.ceil(self.opts.maxCount / per))
    self.rows = rows
    return rows
end

-- "Group, then role": each group header at its group's slot in the holder, with
-- the main header's tile size and "Hide yourself" setting. Slots are fixed, so
-- group 3 is always the third line even if 1 or 2 is empty.
-- Protected, out of combat only.
function Group:PlaceGroupHeaders(cfg, w, ht, rows)
    local corner, y0 = Group.Corner(cfg), cornerY(cfg, self.holder)
    local sx, sy = cfg.growLeft == true and -1 or 1, cfg.growUp == true and 1 or -1
    for i, gh in ipairs(self.headers) do
        gh:SetAttribute("unitWidth", w)
        gh:SetAttribute("unitHeight", ht)
        gh:SetAttribute("showPlayer", cfg.hideSelf ~= true)
        gh:ClearAllPoints()
        if rows then
            gh:SetPoint(corner, self.holder, corner, 0, y0 + sy * (i - 1) * (ht + cfg.groupSpacing))
        else
            gh:SetPoint(corner, self.holder, corner, sx * (i - 1) * (w + cfg.groupSpacing), y0)
        end
    end
end

-- Sizes the holder to the group shown (in test mode, the preview's). Kept to
-- what's there so it never reaches past the screen edge, since it's clamped
-- to it. Protected, out of combat only.
function Group:Resize(cfg)
    local holder = self.holder
    local rows, count
    if self:Previewing() and self.preview then
        rows = self:PreviewRows(cfg)
        count = self.opts.previewCount(cfg)
    else
        rows = Group.Direction(cfg) == "rows"
        count = self.opts.count(cfg)
    end
    local fw, fh = Group.Footprint(cfg, count, rows, holder.tileW, holder.tileH)
    holder:SetSize(fw, fh + (holder.padUp or 0) + (holder.padDown or 0))
end

-- Protected (header attributes, sizes), so only call through DUI.AfterCombat.
function Group:Layout(cfg, text, range)
    if self.sweep then cfg, text = self.sweep.cfg, self.sweep.text end
    local h, holder = self.header, self.holder
    local g = DUI.DB.General()
    holder:SetScale(DUI.Movers.Scale("unitframes." .. tostring(self.key)))
    local w = 2 * Pixel.Snap(holder, cfg.width / 2)
    local ht = 2 * Pixel.Snap(holder, cfg.height / 2)
    h:SetAttribute("unitWidth", w)
    h:SetAttribute("unitHeight", ht)
    holder.padUp, holder.padDown = self:Pads(cfg)
    h:ClearAllPoints()
    local corner = Group.Corner(cfg)
    h:SetPoint(corner, holder, corner, 0, cornerY(cfg, holder))
    local rows = self:ApplyDirection(cfg)
    self:PlaceGroupHeaders(cfg, w, ht, rows)
    holder.tileW, holder.tileH = w, ht
    self:Resize(cfg)
    for _, b in ipairs(self.bare) do b:SetSize(w, ht) end
    for _, b in ipairs(self.buttons) do
        b:SetSize(w, ht)
        self:LayoutButton(b, cfg, text, range)
        UF.UpdateAll(b, true)
        DUI.APIReport.Styled(self.key, b, false)
    end
    local on = self:IsOn(cfg)
    self:LayoutPreview(cfg, text, w, ht)
    -- Redraw the samples so a setting changed in test mode shows.
    if DUI.testMode then self:ShowPreview(on) end
    -- You can be left out of your own group.
    h:SetAttribute("showPlayer", cfg.hideSelf ~= true)
    if self.opts.solo then h:SetAttribute("showSolo", self.opts.solo(cfg) == true) end
    self:ApplyTestAlpha()
    self:SetEnabled(on, cfg)
    self:MakeAhead()
end

-- Creates every button bare before it's needed. The client never runs a
-- header's initialConfigFunction for a button made during combat (no error,
-- just an empty frame with no size), so someone joining then would show
-- nothing. A header creates buttons for a negative startingIndex regardless of
-- who's in the group (SecureGroupHeaders.lua, configureChildren; EllesmereUI,
-- Grid2 and Cell do the same), and the second SetAttribute restores everyone.
-- Setting them all up here cost about 2 seconds at 3 fps after every load, so
-- Group:Take leaves that until the first member arrives.
function Group:MakeOn(h, want)
    if not h:GetAttribute("child" .. want) then
        local shown, first = h:IsShown(), h:GetAttribute("startingIndex")
        self.making = true   -- the members' units shift for a moment, which isn't a real change
        h:Show()
        h:SetAttribute("startingIndex", 1 - want)
        h:SetAttribute("startingIndex", first)
        if not shown then h:Hide() end
        self.making = false
    end
    -- One that got its member during the shift.
    for i = #self.bare, 1, -1 do
        local b = self.bare[i]
        if b:GetAttribute("unit") ~= nil then self:Dress(b) end
    end
end

-- Called from Group:Layout, so out of combat (the module itself is built after
-- combat). No header ever needs a button it doesn't have during a fight.
function Group:MakeAhead()
    if self.sweep then return end
    local cfg = self:Config()
    if not cfg or not self:IsOn(cfg) then return end
    if self:Split(cfg) then
        for i = 1, Group.GroupsShown(cfg, #self.headers) do self:MakeOn(self.headers[i], Group.PER_GROUP) end
    else
        self:MakeOn(self.header, self.opts.maxCount)
    end
end

local function drive(h, cond)
    if cond then
        RegisterStateDriver(h, "visibility", cond)
    else
        UnregisterStateDriver(h, "visibility")
        h:Hide()
    end
end

-- On: the single header, or with "Group, then role" a header per shown group.
function Group:SetEnabled(on, cfg)
    local cond = on and self.opts.visibility(cfg) or nil
    local split = cond ~= nil and self:Split(cfg)
    drive(self.header, not split and cond or nil)
    local n = Group.GroupsShown(cfg, #self.headers)
    for i, gh in ipairs(self.headers) do
        drive(gh, split and i <= n and cond or nil)
    end
end

-- While test mode shows samples, the real buttons can step aside. Alpha works
-- in combat too (test mode ends when combat starts).
function Group:ApplyTestAlpha()
    if not self.header then return end
    local a = (self:Previewing() and self.opts.hideHeaderInTest) and 0 or 1
    self.header:SetAlpha(a)
    for _, gh in ipairs(self.headers) do gh:SetAlpha(a) end
end

-- Test mode is on and this group's samples are wanted. The test box can untick
-- them, but a sweep shows its group either way.
function Group:Previewing()
    return DUI.testMode and (self.sweep ~= nil or DUI.TestPartShown(self.key))
end

-- Samples: plain buttons filled with sample members. Test mode uses the
-- group's own on its holder. Other windows (an options page's live sample)
-- make their own on their own frame.

function Group:PreviewRows(cfg)
    return cfg.direction == "rows"
end

-- A plain sample button on parent, built like the group's own, with its sample
-- dispel icon and highlight. dress (optional) adds the group's extra parts.
function Group:NewSampleButton(parent, i, dress)
    local b = CreateFrame("Button", nil, parent)
    UF.Build(b, self.opts.spec)
    b.unitToken = self.opts.sampleUnit(i)
    b.preview = true
    b.group = self
    b.sampleDispel = CreateFrame("Frame", nil, b)
    b.sampleDispel:SetFrameLevel(b:GetFrameLevel() + 8)
    b.sampleDispel.edge = b.sampleDispel:CreateTexture(nil, "BACKGROUND")
    b.sampleDispel.edge:SetAllPoints(b.sampleDispel)
    b.sampleDispel.edge:SetColorTexture(1, 1, 1, 1)
    b.sampleDispel.icon = b.sampleDispel:CreateTexture(nil, "ARTWORK")
    b.sampleDispel.icon:SetPoint("TOPLEFT", b.sampleDispel, "TOPLEFT", 1, -1)
    b.sampleDispel.icon:SetPoint("BOTTOMRIGHT", b.sampleDispel, "BOTTOMRIGHT", -1, 1)
    b.sampleDispel.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    b.sampleDispel:Hide()
    b.sampleHLFrame = CreateFrame("Frame", nil, b)
    b.sampleHLFrame:SetAllPoints(b)
    b.sampleHLFrame:SetFrameLevel(b:GetFrameLevel() + 7)
    b.sampleHL = GP.MakeHighlight(b.sampleHLFrame)
    b.sampleHLFrame:Hide()
    -- The glow sits under the portrait, like the real one (GP.CreateGlow).
    b.sampleGlowFrame = CreateFrame("Frame", nil, b)
    b.sampleGlowFrame:SetAllPoints(b)
    b.sampleGlowFrame:SetFrameLevel(b:GetFrameLevel() + 1)
    b.sampleHL.glow = GP.MakeGlow(b.sampleGlowFrame)
    b.sampleGlowFrame:Hide()
    GP.MakeTargetMark(b)
    if dress then dress(b) end
    return b
end

function Group:CreatePreview()
    self.preview = {}
    for i = 1, self.opts.maxCount do
        local b = self:NewSampleButton(self.holder, i, self.opts.dress)
        b:Hide()
        self.preview[i] = b
    end
end

-- Lays sample buttons out from the holder's corner (Group.Corner) the same way
-- real ones are placed: w by h each, in lines of Group.PerLine, across or down.
-- top, down: Ribbon's reach above and below them (Group:Pads).
function Group:LayoutSamples(list, holder, cfg, text, w, h, top, down)
    top, down = top or 0, down or 0
    local per = Group.PerLine(cfg)
    local rows = self:PreviewRows(cfg)
    local corner = Group.Corner(cfg)
    local sx, sy = cfg.growLeft == true and -1 or 1, cfg.growUp == true and 1 or -1
    local y0 = cfg.growUp == true and down or -top
    for i, b in ipairs(list) do
        local line = math.floor((i - 1) / per)
        local member = (i - 1) % per
        local x, y
        if rows then
            x, y = member * (w + cfg.spacing), line * (h + cfg.groupSpacing)
        else
            x, y = line * (w + cfg.groupSpacing), member * (h + cfg.spacing)
        end
        b:ClearAllPoints()
        b:SetSize(w, h)
        b:SetPoint(corner, holder, corner, sx * x, y0 + sy * y)
        self:WearIcons(b)
        UF.Layout(b, cfg, text, true)
        local T = Pixel.Px(b, Style.BorderPx(b))
        local spot = cfg.dispelPos or "topright"
        UF.PlaceSpot(b.sampleDispel, b, b, spot, T + UF.CornerPad(b, spot) - 1, T, cfg.dispelX, cfg.dispelY)
        b.sampleDispel:SetSize(cfg.dispelSize, cfg.dispelSize)
        b.showDispel = cfg.showDispel
        b.showHighlight = cfg.dispelGlow == true or (cfg.dispelHighlight or "none") ~= "none"
        GP.StyleHighlight(b.sampleHL, b, cfg)
        GP.LayoutTargetMark(b, cfg)
        b.tintAlpha = cfg.dispelAlpha or 0.3
    end
end

function Group:LayoutPreview(cfg, text, w, h)
    if not self.preview then return end
    self:LayoutSamples(self.preview, self.holder, cfg, text, w, h, self.holder.padUp, self.holder.padDown)
end

-- Fills the first count sample buttons with sample members and hides the rest.
function Group:FillSamples(list, count, cfg)
    for i, b in ipairs(list) do
        if i <= count then
            -- The options page's single tile (b.fullSample) carries every piece.
            b.test = b.fullSample and self.opts.fullSample and self.opts.fullSample(cfg) or self.opts.sampleFor(i, cfg)
            b:Show()
            -- Registered with the API as a preview while shown (never a lookup).
            if b.apiSeen then DUI.APIReport.Unit(self.key, b, b.unitToken, true)
            else b.apiSeen = true; DUI.APIReport.Made(self.key, b, b.unitToken, true) end
            UF.ShowSample(b)
            local kind = b.test.dispel
            local d = b.sampleDispel
            if kind and b.showDispel then
                local c = ns.Auras.DISPEL_COLORS[kind]
                d.edge:SetVertexColor(Style.Soften(c[1], c[2], c[3]))
                d.icon:SetTexture(Group.SAMPLE_DISPEL_ICON)
            end
            d:SetShown(kind ~= nil and b.showDispel == true)
            local hl = b.sampleHL
            if kind and b.showHighlight then
                local c = ns.Auras.DISPEL_COLORS[kind]
                local r, g, bl = Style.Soften(c[1], c[2], c[3])
                -- Strength goes into the color itself. A texture's own alpha
                -- didn't take effect in game.
                hl.tint:SetAlpha(1)
                hl.tint:SetColorTexture(r, g, bl, b.tintAlpha or 0.3)
                for _, t in ipairs(hl.strips) do t:SetVertexColor(r, g, bl, 1) end
                for _, t in pairs(hl.glow) do t:SetVertexColor(r, g, bl, 1) end
            end
            b.sampleHLFrame:SetShown(kind ~= nil and b.showHighlight == true)
            b.sampleGlowFrame:SetShown(kind ~= nil and b.showHighlight == true)
            local mark = b.test.target == true and b.markOn == true
            b.targetMark:SetShown(mark)
            b.targetMark:SetAlpha(mark and 1 or 0)
            if self.opts.showSample then self.opts.showSample(b, i, cfg) end
            ns.GroupPrivate.ShowSample(b, i, cfg)
        else
            b.test = nil
            b:Hide()
            if b.apiSeen then DUI.APIReport.Gone(self.key, b, true) end   -- stays known, showing it again is only a unit change
            b.targetMark:Hide()
            if self.opts.hideSample then self.opts.hideSample(b) end
            ns.GroupPrivate.HideSample(b)
        end
    end
end

function Group:ShowPreview(on)
    if not self.preview then return end
    on = on and self:Previewing() and not (self.opts.hideInTest and self.opts.hideInTest())
    local cfg = self:Config()
    local count = cfg and self.opts.previewCount(cfg) or #self.preview
    self:FillSamples(self.preview, on and count or 0, cfg)
end
