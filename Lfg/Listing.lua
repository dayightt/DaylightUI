-- List yourself page. Labels sit beside their rows; the note is one line; the current
-- listing shows in the header and footer rather than a separate box. Rows: role
-- buttons (the class's possible roles), playstyle (required for a new listing), the
-- note, New player friendly, category buttons, and the selected category's activities
-- to tick (16 max, levels in the game's trivial/difficult colors). Footer: List me
-- (Update while listed) and Clear (Unlist while listed). Rules from LFGListingMixin:
-- only the leader lists a group, a category that selects every activity needs a note,
-- and a group as big as an activity's max can't list for it.
--
-- The note box is the game's own LFGListingComment, because the client reads the
-- listing note from it and addon code can't fill it. It's borrowed into this page while
-- shown, styled like the other text boxes, and returned afterwards.

local _, DUI = ...
DUI.Lfg = DUI.Lfg or {}
local ns = DUI.Lfg
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win

local Listing = {}
ns.Listing = Listing

Listing.EDGE = 16
Listing.NOTE_H = 30      -- one line; the game's box scrolls longer notes
Listing.LABEL_W = 72     -- label column (Roles, Playstyle, Note)
Listing.ROW_GAP = 8
Listing.COUNT_W = 60     -- the "0 / 255" counter on the note box's right
Listing.MAX_NOTE = 255
Listing.EVENTS = { "LFG_LIST_ACTIVE_ENTRY_UPDATE", "LFG_LIST_ROLE_UPDATE", "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED",
    "LFG_LIST_AVAILABILITY_UPDATE", "LFG_LIST_ENTRY_CREATION_FAILED", "PLAYER_ROLES_ASSIGNED" }

local function W() return DUI.Widgets end
local function Data() return ns.Data end

Listing.sel = {}   -- activity id -> true when ticked

-- Selection, and whether it can be posted

local function picked()
    local out = {}
    for id in pairs(Listing.sel) do out[#out + 1] = id end
    table.sort(out)
    return out
end

-- Load the player's listing into the page (created, changed, or page opened).
function Listing.Load()
    local e = Data().Entry()
    if not e then return false end
    local a = Data().Activity(e.activityIDs[1])
    Listing.cat = a and a.categoryID or Listing.cat
    Listing.sel = {}
    for _, id in ipairs(e.activityIDs) do Listing.sel[id] = true end
    Listing.npf = e.newPlayerFriendly == true
    local style = Data().Plain(e.generalPlaystyle)
    if Data().PlaystyleWord(style) then Listing.style = style end
    return true
end

function Listing.NoteText()
    local sf = _G.LFGListingComment
    local box = type(sf) == "table" and sf.EditBox
    if type(box) ~= "table" then return "" end
    local t = Data().Plain(box:GetText())
    return type(t) == "string" and t or ""
end

-- Something differs from the current listing (or, when not listed, something is ticked).
function Listing.Changed()
    local e = Data().Entry()
    local ids = picked()
    if not e then return #ids > 0 end
    if #ids ~= #e.activityIDs then return true end
    local was = {}
    for _, id in ipairs(e.activityIDs) do was[id] = true end
    for _, id in ipairs(ids) do if not was[id] then return true end end
    if (e.newPlayerFriendly == true) ~= (Listing.npf == true) then return true end
    if Data().Plain(e.generalPlaystyle) ~= Listing.style then return true end
    local note = Data().Plain(e.comment)
    if type(note) == "string" and note ~= Listing.NoteText() then return true end
    return false
end

-- Why it can't be posted (the game's wording where available), or nil.
function Listing.Refusal()
    local listed = Data().Entry() ~= nil
    if not Data().CanEdit() then
        return listed and (LFG_LIST_ONLY_LEADER_UPDATE or L["Only your group's leader can change the listing."])
            or (LFG_LIST_ONLY_LEADER_CREATE or L["Only your group's leader can list the group."])
    end
    local ids = picked()
    if #ids > 0 and not Data().PlaystyleWord(Listing.style) then
        return GROUP_FINDER_PLAYSTYLE_REQUIRED or L["Pick a playstyle to list."]
    end
    if #ids > Data().MAX_ACTIVITIES then
        return LFG_LIST_TOO_MANY_ACTIVITIES_SELECTED or string.format(L["Pick %d activities at most."], Data().MAX_ACTIVITIES)
    end
    local cat = Data().Category(Listing.cat)
    if cat and cat.auto and #ids > 0 and Listing.NoteText() == "" then
        return string.format(L["Write a note to list for %s."], cat.name)
    end
    local size = Data().GroupSize()
    if size > 1 then
        local least
        for _, id in ipairs(ids) do
            local a = Data().Activity(id)
            local room = a and a.maxNumPlayers or 0
            if room ~= 0 and room <= size and (not least or room < least) then least = room end
        end
        if least then
            return LFG_LIST_TOO_MANY_FOR_ACTIVITY and string.format(LFG_LIST_TOO_MANY_FOR_ACTIVITY, least)
                or string.format(L["Your group is too big for a %d-player activity."], least)
        end
    end
    return nil
end

-- Posting

-- List me / Update (LFGListingMixin:CreateOrUpdateListing). Nothing ticked while listed
-- removes the listing. Roles are saved with it. The playstyle is sent with updates too
-- (same LfgListingCreateData; the game's page only sends it on create), so changing it
-- sticks.
function Listing.Post()
    if Listing.Refusal() or not Listing.Changed() then return end
    local ids = picked()
    local e = Data().Entry()
    if e and #ids == 0 then return Listing.Unlist() end
    local spec = { activityIDs = ids, newPlayerFriendly = Listing.npf == true, generalPlaystyle = Listing.style }
    Listing.posting = e and "update" or "create"
    Data().Ask(e and "UpdateListing" or "CreateListing", spec)
    Data().SetRoles(Listing.Roles())
end

function Listing.Unlist()
    if not Data().Entry() then return end
    Listing.posting = "remove"
    Data().Ask("RemoveListing")
end

-- Clear: untick everything and empty the note (C_LFGList.ClearCreationTextFields empties
-- the game's box).
function Listing.Clear()
    Listing.sel = {}
    Data().Ask("ClearCreationTextFields")
    Listing.Render()
end

-- The listing changed (LFG_LIST_ACTIVE_ENTRY_UPDATE): re-read it. A new listing sends
-- the window to Find a group, where the game searches for it.
function Listing.EntryChanged(created)
    local was = Listing.posting
    Listing.posting = nil
    -- The game's page still hears this event and plays the new-listing sound itself; these
    -- two it only plays after its own button (PENDING_LISTING_UPDATE).
    if was == "update" and Data().Entry() then DUI.Sound.Kit("PVP_ENTER_QUEUE", "confirms")
    elseif was == "remove" and not Data().Entry() then DUI.Sound.Kit("LFG_DENIED", "confirms") end
    if Data().Entry() then
        Listing.Load()
        if created == true and ns.Window then return ns.Window.Listed() end
        if was == "update" and Listing.page and Listing.page:IsVisible() then
            Listing.Render()
            Win.Parts.Shine(Listing.page.saved)
            return
        end
    end
    if Listing.page and Listing.page:IsVisible() then Listing.Render() end
end

-- Roles

Listing.ROLE_WORD = { TANK = function() return TANK or L["Tank"] end, HEALER = function() return HEALER or L["Healer"] end,
    DAMAGER = function() return DAMAGER or L["Damage"] end }

function Listing.Roles()
    Listing.roles = Listing.roles or Data().Roles()
    return Listing.roles
end

-- Role button. Solo: toggles, but never the last one off, and a role the game rejects
-- flips back (the game's own buttons do the same). In a group: one role, lit once the
-- game confirms (PLAYER_ROLES_ASSIGNED).
function Listing.ToggleRole(role)
    if Data().Grouped() then return Data().SetGroupRole(role) end
    local roles = Listing.Roles()
    local key = Data().ROLE_KEY[role]
    roles[key] = not roles[key]
    if not (roles.tank or roles.healer or roles.dps) then roles[key] = true end
    if not Data().SetRoles(roles) then Listing.roles = nil end
    Listing.Paint()
end

-- Playstyle (kept for the session, like the game's page).
function Listing.PickStyle(id)
    if not Data().CanEdit() then return end
    Listing.style = id
    Listing.Paint()
end

-- The note: the game's box, borrowed

local home   -- the game's original spot: { parent, points }
local lentArt = {}

function Listing.LendNote(page)
    local sf = _G.LFGListingComment
    if type(sf) ~= "table" or type(sf.EditBox) ~= "table" or (InCombatLockdown() and sf:IsProtected()) then
        page.noteMissing:Show()
        return false
    end
    page.noteMissing:Hide()
    if not home then
        home = { parent = sf:GetParent(), points = {} }
        for i = 1, sf:GetNumPoints() do home.points[i] = { sf:GetPoint(i) } end
    end
    local holder = page.noteBox
    sf:SetParent(holder)
    sf:ClearAllPoints()
    sf:SetPoint("TOPLEFT", holder, "TOPLEFT", 8, -8)
    sf:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -Listing.COUNT_W, 4)
    sf:Show()
    -- Its own art goes transparent while borrowed; the box drawn here provides the edge.
    for _, r in ipairs({ sf:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "Texture" and r:GetAlpha() > 0 then
            lentArt[r] = true
            r:SetAlpha(0)
        end
    end
    Listing.FitNote()
    if not Listing.hooked then
        Listing.hooked = true
        sf.EditBox:HookScript("OnTextChanged", function() Listing.NoteChanged() end)
        sf.EditBox:HookScript("OnEditFocusGained", function() Listing.Glow(true) end)
        sf.EditBox:HookScript("OnEditFocusLost", function() Listing.Glow(false) end)
    end
    Listing.lent = true
    Listing.NoteChanged()
    return true
end

-- Return it to the game's spot (the page hid).
function Listing.ReturnNote()
    local sf = _G.LFGListingComment
    if not (Listing.lent and home and type(sf) == "table") then return end
    if InCombatLockdown() and sf:IsProtected() then
        DUI.AfterCombat(Listing.ReturnNote, "lfg:note")
        return
    end
    if sf.EditBox and sf.EditBox.ClearFocus then sf.EditBox:ClearFocus() end
    sf:SetParent(home.parent)
    sf:ClearAllPoints()
    for _, p in ipairs(home.points) do sf:SetPoint(unpack(p)) end
    for r in pairs(lentArt) do r:SetAlpha(1) end
    lentArt = {}
    Listing.lent = nil
end

function Listing.Glow(on)
    local page = Listing.page
    if not page then return end
    local lit = page.noteLit
    local M = DUI.Motion
    local from = page.noteGlow or 0
    local to = on and 1 or 0
    -- The glow fades via the accent color's alpha, since a gradient ignores SetAlpha in game.
    if M then
        M.Tween(lit, from, to, M.FAST, function(v) page.noteGlow = v; Style.PaintAccent(lit, v) end)
    else
        page.noteGlow = to
        Style.PaintAccent(lit, to)
    end
end

function Listing.NoteChanged()
    local page = Listing.page
    if not (page and page:IsShown()) then return end
    local n = #Listing.NoteText()
    page.noteCount:SetText(string.format(L["%d / %d"], n, Listing.MAX_NOTE))
    Listing.PaintFooter()
end

-- Size the game's edit box to the drawn box. It doesn't follow its anchors, so this
-- runs again when the window's grip resizes it.
function Listing.FitNote()
    local sf, page = _G.LFGListingComment, Listing.page
    if not (page and type(sf) == "table" and type(sf.EditBox) == "table" and sf:GetParent() == page.noteBox) then return end
    local w = page.noteBox:GetWidth()
    if type(w) == "number" and w > Listing.COUNT_W + 16 then sf.EditBox:SetWidth(w - Listing.COUNT_W - 16) end
end

-- Drawing

-- A row of buttons from (x0, y), wrapping to a second line when out of room. Returns
-- the height used.
local function layoutRow(list, y, x0, room)
    x0 = x0 or Listing.EDGE
    local x, top = x0, y
    local right = (Listing.page:GetWidth() or 0) - Listing.EDGE - (room or 0)
    for _, b in ipairs(list) do
        if b:IsShown() then
            -- Tight chip padding so four playstyles fit beside their label.
            local tw = b.text:GetStringWidth()
            if type(tw) ~= "number" or tw <= 0 then tw = 60 end
            local w = math.floor(tw + 2 * W().CHIP_PAD + 0.5)
            b:SetWidth(w)
            if x > x0 and right > 0 and x + w > right then
                x, y = x0, y + W().CHIP_HEIGHT + W().CHIP_GAP
            end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", Listing.page, "TOPLEFT", x, -y)
            x = x + w + W().CHIP_GAP
        end
    end
    return y - top + W().CHIP_HEIGHT
end

-- A button for a choice (role, playstyle, category), switched on when selected.
local function pickButton(page, onClick)
    local b = W().Button(page, "", W().CHIP_HEIGHT)
    b:SetScript("OnClick", onClick)
    return b
end

-- Row label in the left column, level with the row's first line.
local function label(page, key, text, y)
    local fs = page[key]
    fs:SetText(text)
    Style.InkText(fs, "LABEL")
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", page, "TOPLEFT", Listing.EDGE, -(y + W().CHIP_HEIGHT / 2))
    fs:Show()
    return fs
end

-- Top part: roles, playstyle and note (labels on the left), the switch, and the category
-- buttons as the list's heading. The listing itself shows in the header ("Listed: ...")
-- and footer (Update / Unlist). Returns where the activities start.
local function top(page)
    local y = 10
    local x0 = Listing.EDGE + Listing.LABEL_W
    local canEdit = Data().CanEdit()
    page.canEdit = canEdit
    page.locked:SetShown(not canEdit)
    if not canEdit then
        page.locked:ClearAllPoints()
        page.locked:SetPoint("TOPLEFT", page, "TOPLEFT", Listing.EDGE, -y)
        page.locked:SetText(Listing.Refusal() or "")
        y = y + 22
    end
    local y0 = y
    -- Roles: solo, the ones listed with; in a group, the single role (leader or not). All
    -- three are offered to everyone like the game's page; ones not recommended for the
    -- class are just dimmer, with the game's text on hover.
    local grouped = Data().Grouped()
    label(page, "rolesHead", L["Roles"], y)
    local roles, advised, mine = Listing.Roles(), Data().Recommended(), Data().GroupRole()
    for i, role in ipairs(Data().ROLES) do
        local b = page.roleChips[i]
        local key = Data().ROLE_KEY[role]
        b.text:SetText(W().RoleText(role, 14) .. " " .. Listing.ROLE_WORD[role]())
        local lit = mine == role
        if not grouped then lit = roles[key] == true end
        b.SetActive(lit)
        b.notAdvised = advised[key] ~= true
        if b.notAdvised and not lit then Style.InkText(b.text, "OFF") end
    end
    y = y + layoutRow(page.roleChips, y, x0) + Listing.ROW_GAP
    -- Playstyle: one of four, required to list (for whoever can edit the listing).
    page.styleHead:SetShown(canEdit)
    for i, b in ipairs(page.styleChips) do
        local word = Data().PlaystyleWord(Data().PLAYSTYLES[i])
        b.text:SetText(word or "")
        b.SetActive(Listing.style == Data().PLAYSTYLES[i])
        b:SetShown(canEdit and word ~= nil)
    end
    if canEdit then
        label(page, "styleHead", L["Playstyle"], y)
        y = y + layoutRow(page.styleChips, y, x0) + Listing.ROW_GAP
    end
    label(page, "noteHead", L["Note"], y + (Listing.NOTE_H - W().CHIP_HEIGHT) / 2)
    page.noteBox:ClearAllPoints()
    page.noteBox:SetPoint("TOPLEFT", page, "TOPLEFT", x0, -y)
    page.noteBox:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Listing.EDGE, -y)
    y = y + Listing.NOTE_H + Listing.ROW_GAP + 2
    page.npfText:ClearAllPoints()
    page.npfText:SetPoint("TOPLEFT", page, "TOPLEFT", Listing.EDGE, -y - 2)
    page.npf:ClearAllPoints()
    page.npf:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Listing.EDGE, -y)
    page.npf.SetOn(Listing.npf == true)
    page.npf:SetEnabled(canEdit)
    y = y + 26
    -- After an update, a shine sweeps the settings.
    page.saved:ClearAllPoints()
    page.saved:SetPoint("TOPLEFT", page, "TOPLEFT", Listing.EDGE, -y0)
    page.saved:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Listing.EDGE, -y0)
    page.saved:SetHeight(math.max(1, y - y0))
    page.saved.shine:SetHeight(math.max(1, y - y0))
    -- Categories: the list's heading.
    local cats = Data().Categories()
    for i, c in ipairs(cats) do
        local b = page.catChips[i]
        if not b then
            b = pickButton(page, function(self) Listing.PickCat(self.cat) end)
            page.catChips[i] = b
        end
        b.cat = c.id
        b.text:SetText(c.name)
        b.SetActive(c.id == Listing.cat)
        b:Show()
    end
    for i = #cats + 1, #page.catChips do page.catChips[i]:Hide() end
    -- Sort (level or A to Z) to the right of the categories, like Who.
    local word = Listing.SORT_WORD[Data().SortMode()]()
    page.sort.text:SetText(string.format(L["Sort: %s"], word))
    page.sort.FitWidth(0)
    page.sort:ClearAllPoints()
    page.sort:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Listing.EDGE, -y)
    y = y + layoutRow(page.catChips, y, nil, page.sort:GetWidth() + W().CHIP_GAP) + 4
    return y
end

Listing.SORT_WORD = { level = function() return LEVEL or L["Level"] end, name = function() return NAME or L["Name"] end }

-- Only two orders, so a click flips between them (no menu).
function Listing.ToggleSort()
    local sorts, cur = Data().SORTS, Data().SortMode()
    local nextKey = sorts[1]
    for i, k in ipairs(sorts) do
        if k == cur then nextKey = sorts[i % #sorts + 1] end
    end
    DUI:Set("GroupFinder", "activitySort", nextKey)
    Listing.Render()
end

function Listing.PickCat(id)
    if id == Listing.cat then return end
    Listing.cat = id
    -- Switching category clears what was ticked (a listing covers one category's
    -- activities); a category that selects all of them ticks them all.
    Listing.sel = {}
    local c = Data().Category(id)
    if c and c.auto then for _, a in ipairs(Data().Filtered(id)) do Listing.sel[a] = true end end
    Listing.Render()
end

function Listing.Toggle(id)
    if not Data().CanEdit() then return end
    if Listing.sel[id] then
        Listing.sel[id] = nil
    else
        if #picked() >= Data().MAX_ACTIVITIES then return end
        Listing.sel[id] = true
    end
    local b = Listing.rows and Listing.rows[id]
    if b then ns.Rows.Pick(b, Listing.sel[id] == true) end
    Listing.PaintFooter()
end

function Listing.PaintFooter()
    local page = Listing.page
    if not page then return end
    local listed = Data().Entry() ~= nil
    local why = Listing.Refusal()
    page.why:SetText(why or "")
    page.why:SetShown(why ~= nil and Data().CanEdit())
    local can = Data().CanEdit()
    local list = { { text = listed and (LFG_LIST_UPDATE or L["Update"]) or L["List me"], primary = true,
        off = why ~= nil or not Listing.Changed(), onClick = Listing.Post } }
    if listed then
        list[2] = { text = L["Unlist"], tone = "no", off = not can, onClick = Listing.Unlist }
    else
        list[2] = { text = L["Clear"], off = next(Listing.sel) == nil, onClick = Listing.Clear }
    end
    page.foot:Set(list)
end

-- Update colors and states without a refill (a role, the switch, the note).
function Listing.Paint()
    local page = Listing.page
    if not (page and page:IsVisible()) then return end
    top(page)
    Listing.PaintFooter()
end

function Listing.Render(page)
    page = page or Listing.page
    if not page then return end
    if not Listing.cat or not Data().Category(Listing.cat) then
        local cats = Data().Categories()
        Listing.cat = cats[1] and cats[1].id or nil
    end
    local y = top(page)
    local s = page.stack
    s.scroll:SetPoint("TOPLEFT", page, "TOPLEFT", Win.Parts.EDGE, -y)
    s:Begin()
    Listing.rows = {}
    local c = Listing.cat and Data().Category(Listing.cat)
    local note
    if not c then
        note = L["Nothing to list for at your level yet."]
    elseif c.auto then
        note = string.format(L["Listing for %s: say what you're doing in the note."], c.name)
    else
        -- One group: the category button is its heading; several: each gets a name.
        local groups = Data().Groups(c.id)
        for _, g in ipairs(groups) do
            if g.name ~= "" and #groups > 1 then s:Section(g.name) end
            for _, a in ipairs(g.acts) do
                Listing.rows[a.id] = ns.Rows.Row(s, { kind = "act", height = ns.Rows.ACTIVITY, text = a.name,
                    color = Data().LevelColor(a.info), value = Data().Levels(a.info), valueColor = Style.INK.LABEL,
                    picked = Listing.sel[a.id] == true, dim = not Data().CanEdit(),
                    onClick = function() Listing.Toggle(a.id) end })
            end
        end
    end
    page.pieces = s:End()
    page.note:SetText(note or "")
    page.note:SetShown(note ~= nil)
    Listing.PaintFooter()
    Listing.NoteChanged()
end

-- The page

function Listing.Build(page)
    Listing.page = page
    local C = W().COLORS
    page.saved = CreateFrame("Frame", nil, page)
    page.saved.shine = page.saved:CreateTexture(nil, "OVERLAY", nil, 7)
    page.saved.shine:SetTexture("Interface\\Buttons\\WHITE8X8")
    page.saved.shine:SetBlendMode("ADD")
    page.saved.shine:Hide()
    page.locked = Style.Text(page, Style.SIZE.body, "LEFT")
    Style.InkText(page.locked, "WARN")
    page.rolesHead = Style.Text(page, Style.SIZE.small, "LEFT")
    page.noteHead = Style.Text(page, Style.SIZE.small, "LEFT")
    page.roleChips = {}
    for i, role in ipairs(Data().ROLES) do
        local b = pickButton(page, function() Listing.ToggleRole(role) end)
        b:HookScript("OnEnter", function()
            if b.notAdvised then W().Tooltip(b, Listing.ROLE_WORD[role](), CLASS_ROLE_NOT_RECOMMENDED or L["Not recommended for your class."]) end
        end)
        b:HookScript("OnLeave", function() W().HideTooltip() end)
        page.roleChips[i] = b
    end
    page.styleHead = Style.Text(page, Style.SIZE.small, "LEFT")
    page.styleChips = {}
    for i, id in ipairs(Data().PLAYSTYLES) do
        local b = pickButton(page, function() Listing.PickStyle(id) end)
        page.styleChips[i] = b
    end
    -- Note box: same look as W.Input, with the game's box inside.
    page.noteBox = CreateFrame("Frame", nil, page)
    page.noteBox:SetHeight(Listing.NOTE_H)
    page.noteBg = W().Round(page.noteBox, "BACKGROUND")
    page.noteBg:SetAllPoints(page.noteBox)
    W().Tint(page.noteBg, C.control)
    page.noteEdge = W().Round(page.noteBox, "BORDER", 0, true)
    page.noteEdge:SetAllPoints(page.noteBox)
    W().Tint(page.noteEdge, C.cardEdge)
    page.noteLit = W().Round(page.noteBox, "BORDER", 1, true)
    page.noteLit:SetAllPoints(page.noteBox)
    Style.PaintAccent(page.noteLit, 0)
    page.noteCount = Style.Text(page.noteBox, Style.SIZE.tiny, "RIGHT")
    page.noteCount:SetPoint("RIGHT", page.noteBox, "RIGHT", -10, 0)
    Style.InkText(page.noteCount, "OFF")
    page.noteMissing = Style.Text(page.noteBox, Style.SIZE.body, "LEFT")
    page.noteMissing:SetPoint("LEFT", page.noteBox, "LEFT", 10, 0)
    page.noteMissing:SetText(L["The note box shows after the fight."])
    Style.InkText(page.noteMissing, "OFF")
    page.noteMissing:Hide()
    page.npfText = Style.Text(page, Style.SIZE.body, "LEFT")
    page.npfText:SetText(LFG_LIST_NEW_PLAYER_FRIENDLY or L["New player friendly"])
    Style.InkText(page.npfText, "TEXT")
    page.npf = W().Switch(page)
    page.npf:SetScript("OnClick", function()
        Listing.npf = not Listing.npf
        if type(SetCVar) == "function" then pcall(SetCVar, "lfgNewPlayerFriendly", Listing.npf and "1" or "0") end
        page.npf.SetOn(Listing.npf)
        Listing.PaintFooter()
    end)
    page.catChips = {}
    page.sort = W().Button(page, L["Sort"], W().CHIP_HEIGHT)
    page.sort:SetScript("OnClick", function() Listing.ToggleSort() end)
    page.stack = Win.Parts.Stack(page, { top = 200, bottom = 74 })
    page.note = Style.Text(page, Style.SIZE.body, "CENTER")
    page.note:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 40, 110)
    page.note:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -40, 110)
    Style.InkText(page.note, "LABEL")
    page.note:Hide()
    page.why = Style.Text(page, Style.SIZE.small, "LEFT")
    page.why:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", Listing.EDGE, 56)
    page.why:SetPoint("RIGHT", page, "RIGHT", -Listing.EDGE, 0)
    Style.InkText(page.why, "WARN")
    page.foot = Win.Parts.Footer(page)
    page:HookScript("OnHide", Listing.ReturnNote)
    for _, e in ipairs(Listing.EVENTS) do
        DUI.RegisterEvent(e, function(event, ...)
            if event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then return Listing.EntryChanged(...) end
            if event == "LFG_LIST_ROLE_UPDATE" then Listing.roles = nil end
            if event == "LFG_LIST_ENTRY_CREATION_FAILED" then Listing.posting = nil end
            if event == "LFG_LIST_AVAILABILITY_UPDATE" then Data().Forget() end
            -- Leadership changed: the rows above the list change, and whether activities can be ticked.
            if page.canEdit ~= Data().CanEdit() and page:IsVisible() then return Listing.Render(page) end
            Listing.Paint()
        end)
    end
end

function Listing.Fill(page)
    page = page or Listing.page
    if not Listing.Load() and Listing.npf == nil then
        Listing.npf = type(GetCVarBool) == "function" and GetCVarBool("lfgNewPlayerFriendly") == true or false
    end
    Listing.roles = nil
    Listing.Render(page)
    Listing.LendNote(page)
end

function Listing.Pieces(page)
    local out = {}
    for _, b in ipairs(page.roleChips) do if b:IsShown() then out[#out + 1] = b end end
    for _, b in ipairs(page.styleChips) do if b:IsShown() then out[#out + 1] = b end end
    out[#out + 1] = page.noteBox
    for _, b in ipairs(page.catChips) do if b:IsShown() then out[#out + 1] = b end end
    out[#out + 1] = page.sort
    for i, p in ipairs(page.pieces or {}) do
        if i > 8 then break end
        out[#out + 1] = p
    end
    return out
end
