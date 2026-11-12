-- Social window, Raid page. The window glides wider. Top: count out of 40, tanks,
-- healers, damage, and the everyone-is-assistant switch. Then the eight groups side by
-- side in two rows: names in class colors, leader and assistant marks, role, ready
-- check, dead in red, offline dimmed. Saved raids below. Outside a raid: one line and
-- Convert to raid.
--
-- Clicking a name targets that player; click and hold moves them.
-- Targeting needs the game's secure unit buttons, and a frame holding one can't be
-- shown, hidden or moved by addon code in combat. So they don't live in the window
-- (that would lock it). They sit in their own transparent layer under UIParent, laid
-- over the rows out of combat only (repositioned whenever the rows move, Raid.Watch),
-- and the game's state driver hides that layer in combat. The page still shows
-- everything then, and hover and right-click still work on the rows; only click to
-- target waits.
-- Moving (the game's drag, RaidFrameSocialPlayerMixin) is for the leader or an
-- assistant, out of combat: SwapRaidSubgroup onto a person, SetRaidSubgroup onto a
-- group with room.

local _, DUI = ...
DUI.Social = DUI.Social or {}
local ns = DUI.Social
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win

local Raid = {}
ns.Raid = Raid

Raid.EDGE = 16
Raid.TOP = 12          -- counts line
Raid.GRID = 44         -- where the groups start
Raid.COLS = 4
Raid.GAP = 8
Raid.SLOT = 22         -- member line
Raid.CARD_HEAD = 20
Raid.CARD = Raid.CARD_HEAD + 5 * Raid.SLOT + 6
Raid.SAVED = Raid.GRID + 2 * Raid.CARD + Raid.GAP + 10   -- saved raids list
Raid.MAX = 40
Raid.ABOVE = 20        -- frame levels the target layer sits above the window
Raid.LEADER = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
Raid.ASSIST = "Interface\\GroupFrame\\UI-Group-AssistantIcon"
Raid.READY = { ready = "Interface\\RaidFrame\\ReadyCheck-Ready", notready = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    waiting = "Interface\\RaidFrame\\ReadyCheck-Waiting" }

local WHITE = "Interface\\Buttons\\WHITE8X8"
local function W() return DUI.Widgets end
local function Data() return ns.Data end
local function Rows() return DUI.Lfg.Rows end

local function maxLevel()
    local m = type(GetMaxLevelForPlayerExpansion) == "function" and GetMaxLevelForPlayerExpansion()
    return type(m) == "number" and m or MAX_PLAYER_LEVEL or 60
end

local function firstName(name) return (type(name) == "string" and name:match("^(%S+)")) or name or "" end

-- Card and menu

function Raid.Tip(owner, m)
    if not (GameTooltip and m) then return end
    local T = DUI.Tips
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    T.Clear()
    local r, g, b = Style.ClassTextColor(m.token)
    T.Title(m.name, r, g, b)
    T.Sub(((m.level and string.format(L["Level %s"], m.level) .. " ") or "") .. (m.class or "") .. " · " .. string.format(L["Group %d"], m.group))
    if m.rank == 2 then T.Text(L["Raid leader"], Style.INK.LABEL) elseif m.rank == 1 then T.Text(L["Assistant"], Style.INK.LABEL) end
    if m.zone then T.Line(L["Zone"], m.zone) end
    if not m.online then T.Text(L["Offline"], Style.INK.OFF)
    elseif m.dead then T.Text(L["Dead"], Style.INK.BAD) end
    T.Gap()
    if InCombatLockdown() then
        T.Hint(L["Click to target after the fight"])
    else
        T.Hint(L["Click: target"])
        if Data().CanMove() then T.Hint(L["Hold: move to another group"]) end
    end
    T.Hint(L["Right-click: more"])
    T.Flush(GameTooltip)
    GameTooltip:Show()
end

local function call(fn, ...) if type(fn) == "function" then pcall(fn, ...) end end

function Raid.Menu(owner, m)
    local keys, values = {}, {}
    local function add(k, v) keys[#keys + 1] = k; values[k] = v end
    local me = UnitIsUnit and UnitIsUnit(m.unit, "player")
    if not me then add("whisper", WHISPER or L["Whisper"]) end
    if Data().Leads() and not me then
        add("leader", L["Make leader"])
        add("assist", m.rank == 1 and L["Remove assistant"] or L["Make assistant"])
        add("remove", L["Remove from the raid"])
    end
    if #keys == 0 then return end
    -- The client only has these in C_PartyInfo (PartyInfoDocumentation); the game's own
    -- menu passes the roster's full name, exact match.
    local P = C_PartyInfo or {}
    W().OpenMenu(owner, keys, values, nil, function(k)
        if k == "whisper" then Data().Whisper(m.name)
        elseif k == "leader" then call(P.PromoteToLeader, m.name, true)
        elseif k == "assist" then
            if m.rank == 1 then call(P.DemoteAssistant, m.name, true) else call(P.PromoteToAssistant, m.name, true) end
        elseif k == "remove" then call(P.UninviteUnit, m.name, nil, true) end
    end, nil, { atCursor = true })
end

-- Visible rows

local function tex(parent, layer, c)
    local t = parent:CreateTexture(nil, layer)
    t:SetTexture(WHITE)
    if c then t:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
    return t
end

local function makeSlot(card)
    local b = CreateFrame("Button", nil, card)
    b:RegisterForClicks("RightButtonUp")
    b:SetHeight(Raid.SLOT)
    b.hi = tex(b, "BACKGROUND", Win.Parts.HI)
    b.hi:SetAllPoints(b)
    b.hi:Hide()
    b.shine = b:CreateTexture(nil, "OVERLAY", nil, 7)
    b.shine:SetTexture(WHITE)
    b.shine:SetBlendMode("ADD")
    b.shine:SetHeight(Raid.SLOT)
    b.shine:Hide()
    b.mark = b:CreateTexture(nil, "ARTWORK")
    b.mark:SetSize(12, 12)
    b.mark:SetPoint("LEFT", b, "LEFT", 6, 0)
    b.ready = b:CreateTexture(nil, "ARTWORK")
    b.ready:SetSize(12, 12)
    b.ready:SetPoint("RIGHT", b, "RIGHT", -6, 0)
    b.role = W().Role(b, 14)
    b.role:SetPoint("RIGHT", b.ready, "LEFT", -4, 0)
    b.level = Style.Text(b, Style.SIZE.small, "RIGHT")
    b.level:SetPoint("RIGHT", b.role, "LEFT", -5, 0)
    Style.InkText(b.level, "LABEL")
    b.name = Style.Text(b, Style.SIZE.body, "LEFT")
    b.name:SetPoint("LEFT", b, "LEFT", 22, 0)
    b.name:SetPoint("RIGHT", b.level, "LEFT", -4, 0)
    b.name:SetWordWrap(false)
    b:SetScript("OnEnter", function(self) Raid.Enter(self) end)
    b:SetScript("OnLeave", function(self) Raid.Leave(self) end)
    b:SetScript("OnClick", function(self, button) if button == "RightButton" and self.member then Raid.Menu(self, self.member) end end)
    -- A controller's Y opens the same menu.
    b.padMore = function(self) if self.member then return function() Raid.Menu(self, self.member) end end end
    -- Holding moves them from the row too (in combat, or if the target layer is ever not
    -- over it); only click to target needs the layer.
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self) Raid.Lift(self) end)
    b:SetScript("OnDragStop", function() Raid.Drop() end)
    return b
end

function Raid.Enter(slot)
    if not slot.member then return end
    Win.Parts.Light(slot.hi, true)
    Raid.Tip(slot, slot.member)
end

function Raid.Leave(slot)
    Win.Parts.Light(slot.hi, false)
    if GameTooltip and GameTooltip:IsOwned(slot) then GameTooltip:Hide() end
end

local function makeCard(parent, g)
    local c = CreateFrame("Frame", nil, parent)
    c.bg = tex(c, "BACKGROUND", { 1, 1, 1, 0.03 })
    c.bg:SetAllPoints(c)
    c.drop = tex(c, "BORDER")
    c.drop:SetAllPoints(c)
    c.drop:Hide()
    c.head = Style.Text(c, Style.SIZE.tiny, "LEFT")
    c.head:SetPoint("TOPLEFT", c, "TOPLEFT", 10, -6)
    c.head:SetText(string.upper(string.format(L["Group %d"], g)))
    c.group = g
    c.slots = {}
    for i = 1, Data().GROUP_SIZE do
        local s = makeSlot(c)
        s:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -Raid.CARD_HEAD - (i - 1) * Raid.SLOT)
        s:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, -Raid.CARD_HEAD - (i - 1) * Raid.SLOT)
        c.slots[i] = s
    end
    return c
end

local function paintSlot(s, m)
    s.member = m
    if not m then
        s.name:SetText(L["Empty"])
        Style.InkText(s.name, "OFF")
        s.name:SetAlpha(0.6)
        s.mark:Hide(); s.ready:Hide(); s.role:Hide()
        s.level:SetText("")
        s:EnableMouse(false)
        return
    end
    s:EnableMouse(true)
    s.name:SetAlpha(1)
    s.name:SetText(firstName(m.name))
    if not m.online then Style.InkText(s.name, "OFF")
    elseif m.dead then Style.InkText(s.name, "BAD")
    else s.name:SetTextColor(Style.ClassTextColor(m.token)) end
    s.mark:SetShown(m.rank >= 1)
    if m.rank >= 1 then s.mark:SetTexture(m.rank == 2 and Raid.LEADER or Raid.ASSIST) end
    s.level:SetText((m.level and m.level < maxLevel()) and tostring(m.level) or "")
    s.role.Set(m.role)
    local art = m.ready and Raid.READY[m.ready]
    s.ready:SetShown(art ~= nil)
    if art then s.ready:SetTexture(art) end
    s:SetAlpha(Raid.dragging == m.index and 0.35 or 1)
end

-- Target layer (secure, out of combat only)

local layer, inner
Raid.buttons = {}

local function makeLayer()
    if layer or InCombatLockdown() then return layer end
    layer = CreateFrame("Frame", "DaylightUISocialRaidTargets", UIParent)
    layer:SetAllPoints(UIParent)
    RegisterStateDriver(layer, "visibility", "[combat] hide; show")
    inner = CreateFrame("Frame", nil, layer)
    inner:SetAllPoints(layer)
    inner:Hide()
    for i = 1, Raid.MAX do
        local b = CreateFrame("Button", "DaylightUISocialRaidTarget" .. i, inner, "SecureUnitButtonTemplate")
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:RegisterForDrag("LeftButton")
        b:SetAttribute("type1", "target")
        b:SetScript("OnEnter", function(self) if self.slot then Raid.Enter(self.slot) end end)
        b:SetScript("OnLeave", function(self) if self.slot then Raid.Leave(self.slot) end end)
        b:SetScript("PostClick", function(self, button)
            if button == "RightButton" and self.slot and self.slot.member then Raid.Menu(self, self.slot.member) end
        end)
        b:SetScript("OnDragStart", function(self) Raid.Lift(self.slot) end)
        b:SetScript("OnDragStop", function() Raid.Drop() end)
        b:Hide()
        Raid.buttons[i] = b
    end
    return layer
end

-- A region's position in UIParent units.
local function box(r)
    local l, t, w, h = r:GetLeft(), r:GetTop(), r:GetWidth(), r:GetHeight()
    if type(l) ~= "number" or type(t) ~= "number" then return nil end
    local k = r:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return l * k, t * k, w * k, h * k
end

-- Place each member's button over its row (out of combat, else after combat).
function Raid.Sync()
    if InCombatLockdown() then
        DUI.AfterCombat(Raid.Sync, "social:raid")
        return
    end
    local page = Raid.page
    local open = page and page:IsVisible() and Data().InRaid() and ns.Window.frame and Win.IsOpen(ns.Window.frame)
    if not open then
        if inner then inner:Hide() end
        return
    end
    makeLayer()
    local used = 0
    for _, card in ipairs(page.cards) do
        for _, s in ipairs(card.slots) do
            local m = s.member
            if m then
                used = used + 1
                local b = Raid.buttons[used]
                local l, t, w, h = box(s)
                if b and l then
                    b.slot = s
                    b:SetAttribute("unit", m.unit)
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
                    b:SetSize(w, h)
                    b:Show()
                end
            end
        end
    end
    for i = used + 1, Raid.MAX do
        local b = Raid.buttons[i]
        if b then b.slot = nil; b:Hide() end
    end
    -- Just above the window, never above whatever covers it (bags, another window).
    -- Children keep their own levels when the parent's level changes, so each one is set,
    -- putting the buttons above every row.
    local f = ns.Window.frame
    local level = f:GetFrameLevel() + Raid.ABOVE
    layer:SetFrameStrata(f:GetFrameStrata())
    layer:SetFrameLevel(level)
    inner:SetFrameLevel(level + 1)
    for i = 1, used do Raid.buttons[i]:SetFrameLevel(level + 2) end
    inner:Show()
    local l, t = box(page.cards[1])
    Raid.at = { l, t, f:GetFrameLevel() }
end

-- Every frame while the page shows, out of combat: if the rows moved (the window
-- glided, was dragged, or made room for another), the buttons follow.
function Raid.Watch()
    if InCombatLockdown() or not Raid.page then return end
    local first = Raid.page.cards[1]
    local l, t = box(first)
    local at = Raid.at
    local level = ns.Window.frame and ns.Window.frame:GetFrameLevel()
    if not at or at[1] ~= l or at[2] ~= t or at[3] ~= level then Raid.Sync() end
end

function Raid.Closed()
    if InCombatLockdown() then
        if inner then DUI.AfterCombat(function() if not (Raid.page and Raid.page:IsVisible()) then inner:Hide() end end, "social:raid") end
        return
    end
    if inner then inner:Hide() end
    Raid.Drop(true)
end

function Raid.Moved() Raid.at = nil end

-- Click and hold to move (leader or assistant, out of combat)

local function ghost()
    if Raid.ghost then return Raid.ghost end
    local g = CreateFrame("Frame", nil, UIParent)
    DUI.Movers.FollowScale(g)
    g:SetFrameStrata("TOOLTIP")
    g:SetSize(140, Raid.SLOT + 6)
    Style.Shell(g, {})
    g.name = Style.Text(g, Style.SIZE.body, "LEFT")
    g.name:SetPoint("LEFT", g, "LEFT", 10, 0)
    g:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local k = self:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / k + 12, y / k)
        for _, card in ipairs(Raid.page and Raid.page.cards or {}) do
            local over = card:IsMouseOver() and card.group ~= Raid.liftGroup
            card.drop:SetShown(over)
            if over then Style.PaintAccent(card.drop, 0.12) end
        end
    end)
    g:Hide()
    Raid.ghost = g
    return g
end

function Raid.Lift(slot)
    local m = slot and slot.member
    if not m or InCombatLockdown() or not Data().CanMove() then return end
    Raid.dragging, Raid.liftGroup = m.index, m.group
    slot:SetAlpha(0.35)
    if GameTooltip and GameTooltip:IsOwned(slot) then GameTooltip:Hide() end
    local g = ghost()
    g.name:SetText(firstName(m.name))
    g.name:SetTextColor(Style.ClassTextColor(m.token))
    g:SetAlpha(0)
    g:Show()
    if DUI.Motion then DUI.Motion.Tween(g, 0, 1, DUI.Motion.FAST, function(a) g:SetAlpha(a) end) else g:SetAlpha(1) end
end

-- Release: onto a person in another group (swap), else onto a group with room.
function Raid.Drop(cancel)
    local index = Raid.dragging
    Raid.dragging, Raid.liftGroup = nil, nil
    if Raid.ghost then Raid.ghost:Hide() end
    local page = Raid.page
    if not page then return end
    local from
    for _, card in ipairs(page.cards) do
        card.drop:Hide()
        for _, s in ipairs(card.slots) do
            if s.member and s.member.index == index then from = s.member; s:SetAlpha(1) end
        end
    end
    if cancel or not from then return end
    for _, card in ipairs(page.cards) do
        if card:IsMouseOver() and card.group ~= from.group then
            for _, s in ipairs(card.slots) do
                if s.member and s:IsMouseOver() then
                    if Data().Swap(from, s.member) then Raid.moved = { [from.name] = true, [s.member.name] = true } end
                    return
                end
            end
            if card.count < Data().GROUP_SIZE and Data().Move(from, card.group) then Raid.moved = { [from.name] = true } end
            return
        end
    end
end

-- The page

function Raid.Layout(page)
    local w = Win.GoalGrowth(page) + (page:GetWidth() or 0)
    if w <= 0 then w = ns.Window.RAID_W end
    local cardW = math.floor((w - 2 * Raid.EDGE - (Raid.COLS - 1) * Raid.GAP) / Raid.COLS)
    for i, card in ipairs(page.cards) do
        local col, row = (i - 1) % Raid.COLS, math.floor((i - 1) / Raid.COLS)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", page, "TOPLEFT", Raid.EDGE + col * (cardW + Raid.GAP), -Raid.GRID - row * (Raid.CARD + Raid.GAP))
        card:SetSize(cardW, Raid.CARD)
    end
    Raid.at = nil
end

local function paintTop(page)
    local t, h, d = Data().Counts()
    local n = #Raid.roster
    local pop = Win.Parts.Hex({ Style.Pop() })
    page.count:SetText(string.format(L["%s / %d"], pop .. n .. "|r", Raid.MAX))
    page.roles:SetText(W().RoleText("TANK", 14) .. " " .. pop .. t .. "|r    " .. W().RoleText("HEALER", 14) .. " " .. pop .. h
        .. "|r    " .. W().RoleText("DAMAGER", 14) .. " " .. pop .. d .. "|r")
    local leads = Data().Leads()
    page.assist.off = not leads or nil
    page.assist:SetEnabled(leads)
    page.assist.SetOn(Data().EveryoneAssists())
end

function Raid.Render()
    local page = Raid.page
    if not (page and page:IsShown()) then return end
    local inRaid = Data().InRaid()
    page.inRaid:SetShown(inRaid)
    page.noRaid:SetShown(not inRaid)
    if not inRaid then
        page.convert.SetOff(not Data().CanConvert())
        if inner and not InCombatLockdown() then inner:Hide() end
        return
    end
    Raid.roster = Data().Roster()
    Raid.Layout(page)
    for _, card in ipairs(page.cards) do card.count = 0 end
    local byGroup = {}
    for _, m in ipairs(Raid.roster) do
        local g = m.group
        byGroup[g] = byGroup[g] or {}
        table.insert(byGroup[g], m)
    end
    for _, card in ipairs(page.cards) do
        local list = byGroup[card.group] or {}
        card.count = #list
        for i, s in ipairs(card.slots) do
            paintSlot(s, list[i])
            if list[i] and Raid.moved and Raid.moved[list[i].name] then Win.Parts.Shine(s) end
        end
        Style.InkText(card.head, "pop")
    end
    Raid.moved = nil
    paintTop(page)
    -- Saved raids below.
    local st = page.stack
    st:Begin()
    local saved = Data().Saved()
    if #saved > 0 then
        st:Section(L["Saved raids"])
        for _, r in ipairs(saved) do
            local sub = (r.bosses and r.killed) and string.format(L["%d / %d bosses"], r.killed, r.bosses) or ""
            st:Line({ text = r.name, sub = sub, value = r.reset and string.format(L["resets in %s"], Data().Span(r.reset)) or "",
                valueColor = Style.INK.LABEL })
        end
    end
    page.pieces = st:End()
    Raid.Sync()
end

function Raid.Clicked() Data().AskSaved() end

function Raid.Build(page)
    Raid.page = page
    Raid.roster = {}
    page.inRaid = CreateFrame("Frame", nil, page)
    page.inRaid:SetAllPoints(page)
    page.count = Style.Text(page.inRaid, Style.SIZE.body, "LEFT")
    page.count:SetPoint("TOPLEFT", page.inRaid, "TOPLEFT", Raid.EDGE, -Raid.TOP - 4)
    Style.InkText(page.count, "TEXT")
    page.roles = Style.Text(page.inRaid, Style.SIZE.body, "LEFT")
    page.roles:SetPoint("LEFT", page.count, "RIGHT", 18, 0)
    Style.InkText(page.roles, "TEXT")
    page.assist = W().Switch(page.inRaid)
    page.assist:SetPoint("TOPRIGHT", page.inRaid, "TOPRIGHT", -Raid.EDGE, -Raid.TOP)
    page.assist:SetScript("OnClick", function(self) Data().SetEveryoneAssists(not self.on) end)
    page.assistLabel = Style.Text(page.inRaid, Style.SIZE.small, "RIGHT")
    page.assistLabel:SetPoint("RIGHT", page.assist, "LEFT", -8, 0)
    page.assistLabel:SetText(L["Everyone is assistant"])
    Style.InkText(page.assistLabel, "LABEL")
    page.cards = {}
    for g = 1, Data().GROUPS do page.cards[g] = makeCard(page.inRaid, g) end
    page.stack = Win.Parts.Stack(page.inRaid, { top = Raid.SAVED, bottom = 12 })
    -- Not in a raid.
    page.noRaid = CreateFrame("Frame", nil, page)
    page.noRaid:SetAllPoints(page)
    page.noRaid:Hide()
    local title = Style.Text(page.noRaid, Style.SIZE.head, "CENTER")
    title:SetPoint("CENTER", page.noRaid, "CENTER", 0, 40)
    title:SetText(L["You're not in a raid."])
    Style.InkText(title, "LABEL")
    local says = Style.Text(page.noRaid, Style.SIZE.body, "CENTER")
    says:SetPoint("TOP", title, "BOTTOM", 0, -10)
    says:SetWidth(340)
    says:SetText(L["Make your party a raid to bring up to 40 players. Only the party leader can."])
    Style.InkText(says, "TEXT")
    page.convert = W().Button(page.noRaid, CONVERT_TO_RAID or L["Convert to raid"], 28)
    page.convert.FitWidth(140)
    page.convert.text:SetTextColor(Win.Parts.YES[1], Win.Parts.YES[2], Win.Parts.YES[3], 1)
    page.convert:SetPoint("TOP", says, "BOTTOM", 0, -16)
    page.convert:SetScript("OnClick", function() Data().Convert() end)
    page.noRaidPieces = { title, says, page.convert }
    page:HookScript("OnShow", function() Raid.at = nil end)
    page:HookScript("OnHide", function() Raid.Closed() end)
    page:HookScript("OnUpdate", function() Raid.Watch() end)
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "RAID_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "PLAYER_ROLES_ASSIGNED",
        "UNIT_CONNECTION", "READY_CHECK", "READY_CHECK_CONFIRM", "READY_CHECK_FINISHED", "UPDATE_INSTANCE_INFO" }) do
        DUI.RegisterEvent(e, function() ns.Window.Refresh("raid") end)
    end
end

function Raid.Fill() Raid.Render() end

function Raid.Pieces(page)
    if not Data().InRaid() then return page.noRaidPieces end
    local out = { page.count, page.roles, page.assist }
    for _, c in ipairs(page.cards) do out[#out + 1] = c end
    for _, p in ipairs(page.pieces or {}) do out[#out + 1] = p end
    return out
end

-- A controller's A on a raid member targets them, as a click on the row does.
function Raid.PadTarget(b)
    local m = type(b) == "table" and b.member
    if type(m) ~= "table" or type(m.unit) ~= "string" then return nil end
    return { type = "target", unit = m.unit }
end
