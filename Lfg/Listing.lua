-- List yourself page. The settings sit in one soft panel, a row to each with its accent
-- label beside it and a thin line between them; the note is one line; the current
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
Listing.LABEL_W = 72     -- label column at least this wide (Roles, Playstyle, Note...)
Listing.LABEL_MAX = 150  -- and at most this wide
Listing.ROW_GAP = 10
Listing.IN = 12          -- inside the settings panel, from its edges
Listing.ROLE_ICON, Listing.ROLE_GAP = 16, 6   -- a role button's badge, and the space before its word
Listing.DROP_LABEL = 14  -- room for the word over a drop-down
Listing.PANEL = { 1, 1, 1, 0.035 }
Listing.RULE = { 1, 1, 1, 0.07 }
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
local function layoutRow(list, y, x0, room, pad)
    x0 = x0 or Listing.EDGE
    local x, top = x0, y
    local page = Listing.page
    local wide = (page:GetWidth() or 0) + (Win.GoalGrowth and Win.GoalGrowth(page) or 0)
    local right = wide - Listing.EDGE - (pad or 0) - (room or 0)
    for _, b in ipairs(list) do
        if b:IsShown() then
            -- Tight chip padding so four playstyles fit beside their label.
            local tw = b.text:GetStringWidth()
            if type(tw) ~= "number" or tw <= 0 then tw = 60 end
            local w = math.floor(tw + 2 * W().CHIP_PAD + (b.extraW or 0) + 0.5)
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
    fs:SetPoint("LEFT", page, "TOPLEFT", Listing.EDGE + Listing.IN, -(y + W().CHIP_HEIGHT / 2))
    fs:Show()
    return fs
end

-- Top part: roles, playstyle and note (labels on the left), the switch, and the category
-- buttons as the list's heading. The listing itself shows in the header ("Listed: ...")
-- and footer (Update / Unlist). Returns where the activities start.
local function top(page)
    local y = 10
    -- The label column is as wide as the longest label (in any language), so none is cut.
    local widest = 0
    for _, words in ipairs({ ROLES or L["Roles"], GROUP_FINDER_FILTER_PLAYSTYLE or L["Playstyle"], LABEL_NOTE or L["Note"],
                             CATEGORY or L["Category"], WHO_SORT_LABEL or L["Sort by"] }) do
        page.probe:SetText(words)
        local w = page.probe:GetStringWidth()
        if type(w) == "number" then widest = math.max(widest, w) end
    end
    Listing.labelW = math.min(Listing.LABEL_MAX, math.max(Listing.LABEL_W, math.ceil(widest) + 12))
    local x0 = Listing.EDGE + Listing.IN + Listing.labelW
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
    y = y + Listing.IN
    local rule = 0
    -- A thin line between two rows of the panel, in the middle of the gap under the one above.
    local function divide(at)
        rule = rule + 1
        local t = page.rules[rule]
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", page, "TOPLEFT", Listing.EDGE + Listing.IN, -at)
        t:SetPoint("TOPRIGHT", page, "TOPRIGHT", -(Listing.EDGE + Listing.IN), -at)
        t:Show()
    end
    for _, t in ipairs(page.rules) do t:Hide() end
    -- Roles: solo, the ones listed with; in a group, the single role (leader or not). All
    -- three are offered to everyone like the game's page; ones not recommended for the
    -- class are just dimmer, with the game's text on hover.
    local grouped = Data().Grouped()
    label(page, "rolesHead", ROLES or L["Roles"], y)
    local roles, advised, mine = Listing.Roles(), Data().Recommended(), Data().GroupRole()
    for i, role in ipairs(Data().ROLES) do
        local b = page.roleChips[i]
        local key = Data().ROLE_KEY[role]
        b.text:SetText(Listing.ROLE_WORD[role]())
        b.icon.Set(role)
        local lit = mine == role
        if not grouped then lit = roles[key] == true end
        b.SetActive(lit)
        b.notAdvised = advised[key] ~= true
        b.icon:SetAlpha((b.notAdvised and not lit) and 0.5 or 1)
        if b.notAdvised and not lit then Style.InkText(b.text, "OFF") end
    end
    y = y + layoutRow(page.roleChips, y, x0, 0, Listing.IN) + Listing.ROW_GAP
    divide(y - Listing.ROW_GAP / 2)
    -- Playstyle: one of four, required to list (for whoever can edit the listing).
    page.styleHead:SetShown(canEdit)
    for i, b in ipairs(page.styleChips) do
        local word = Data().PlaystyleWord(Data().PLAYSTYLES[i])
        b.text:SetText(word or "")
        b.SetActive(Listing.style == Data().PLAYSTYLES[i])
        b:SetShown(canEdit and word ~= nil)
    end
    if canEdit then
        label(page, "styleHead", GROUP_FINDER_FILTER_PLAYSTYLE or L["Playstyle"], y)
        y = y + layoutRow(page.styleChips, y, x0, 0, Listing.IN) + Listing.ROW_GAP
        divide(y - Listing.ROW_GAP / 2)
    end
    label(page, "noteHead", LABEL_NOTE or L["Note"], y + (Listing.NOTE_H - W().CHIP_HEIGHT) / 2)
    page.noteBox:ClearAllPoints()
    page.noteBox:SetPoint("TOPLEFT", page, "TOPLEFT", x0, -y)
    page.noteBox:SetPoint("TOPRIGHT", page, "TOPRIGHT", -(Listing.EDGE + Listing.IN), -y)
    y = y + Listing.NOTE_H + Listing.ROW_GAP + 2
    divide(y - Listing.ROW_GAP / 2 - 1)
    -- The game's own sentence for this switch, wrapped beside it.
    local wide = (page:GetWidth() or 0) + (Win.GoalGrowth and Win.GoalGrowth(page) or 0)
    local npfH = page.npf:GetHeight()
    if type(npfH) ~= "number" or npfH <= 0 then npfH = 18 end
    local npfW = page.npf:GetWidth()
    if type(npfW) ~= "number" or npfW <= 0 then npfW = 36 end
    page.npfText:SetWidth(math.max(60, wide - 2 * (Listing.EDGE + Listing.IN) - npfW - 16))
    local textH = page.npfText:GetStringHeight()
    if type(textH) ~= "number" or textH <= 0 then textH = Style.SIZE.small + 2 end
    local rowH = math.max(npfH, textH)
    page.npfText:ClearAllPoints()
    page.npfText:SetPoint("LEFT", page, "TOPLEFT", Listing.EDGE + Listing.IN, -(y + rowH / 2))
    page.npf:ClearAllPoints()
    page.npf:SetPoint("TOPRIGHT", page, "TOPRIGHT", -(Listing.EDGE + Listing.IN), -(y + (rowH - npfH) / 2))
    page.npf.SetOn(Listing.npf == true)
    page.npf:SetEnabled(canEdit)
    y = y + rowH + Listing.ROW_GAP
    divide(y - Listing.ROW_GAP / 2)
    -- Category and Sort by: the list's filters, rows of the same panel.
    local dw = math.max(120, math.floor(wide - (Listing.EDGE + Listing.IN) - x0))
    for _, row in ipairs({ { "catLabel", "cat", CATEGORY or L["Category"] },
                           { "sortByLabel", "sortBy", WHO_SORT_LABEL or L["Sort by"] } }) do
        label(page, row[1], row[3], y)
        local b = page[row[2]]
        b:SetWidth(dw)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", page, "TOPLEFT", x0, -y)
        y = y + W().CHIP_HEIGHT + Listing.ROW_GAP
        if row[2] == "cat" then divide(y - Listing.ROW_GAP / 2) end
    end
    page.cat.text:SetText(Listing.CategoryWord())
    page.sortBy.text:SetText(Listing.SORT_WORD[Data().SortMode()]())
    y = y - Listing.ROW_GAP + Listing.IN
    -- The panel behind the settings; after an update, a shine sweeps it.
    page.saved:ClearAllPoints()
    page.saved:SetPoint("TOPLEFT", page, "TOPLEFT", Listing.EDGE, -y0)
    page.saved:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Listing.EDGE, -y0)
    page.saved:SetHeight(math.max(1, y - y0))
    page.saved.shine:SetHeight(math.max(1, y - y0))
    y = y + 12   -- air between the panel and the activities
    return y
end

Listing.SORT_WORD = { level = function() return LEVEL or L["Level"] end, name = function() return NAME or L["Name"] end }

-- The category shown on its drop-down, and the choices in it.
function Listing.CategoryWord()
    for _, c in ipairs(Data().Categories()) do if c.id == Listing.cat then return c.name end end
    return ""
end

function Listing.CategoryMenu(owner)
    local keys, values = {}, {}
    for _, c in ipairs(Data().Categories()) do keys[#keys + 1] = c.id; values[c.id] = c.name end
    W().OpenMenu(owner, keys, values, Listing.cat, Listing.PickCat, owner:GetWidth())
end

function Listing.PickSort(mode)
    if mode == Data().SortMode() then return end
    DUI:Set("GroupFinder", "activitySort", mode)
    Listing.Render()
end

function Listing.SortMenu(owner)
    local values = {}
    for _, k in ipairs(Data().SORTS) do values[k] = Listing.SORT_WORD[k]() end
    W().OpenMenu(owner, Data().SORTS, values, Data().SortMode(), Listing.PickSort, owner:GetWidth())
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
                Listing.rows[a.id] = ns.Rows.Row(s, { kind = "act", height = ns.Rows.ACTIVITY, text = a.name, sep = true,
                    color = Data().LevelColor(a.info), value = Data().Levels(a.info), valueColor = Style.INK.LABEL,
                    picked = Listing.sel[a.id] == true, check = Listing.sel[a.id] == true, dim = not Data().CanEdit(),
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
    page.saved.fill = page.saved:CreateTexture(nil, "BACKGROUND")
    page.saved.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    page.saved.fill:SetVertexColor(Listing.PANEL[1], Listing.PANEL[2], Listing.PANEL[3], Listing.PANEL[4])
    page.saved.fill:SetAllPoints(page.saved)
    page.saved.edge = page.saved:CreateTexture(nil, "BORDER")
    page.saved.edge:SetTexture("Interface\\Buttons\\WHITE8X8")
    page.saved.edge:SetWidth(ns.Rows.EDGE_W)
    page.saved.edge:SetPoint("TOPLEFT", page.saved, "TOPLEFT", 0, 0)
    page.saved.edge:SetPoint("BOTTOMLEFT", page.saved, "BOTTOMLEFT", 0, 0)
    Style.PaintAccent(page.saved.edge, 0.9)
    page.rules = {}
    for i = 1, 6 do
        local t = page:CreateTexture(nil, "BORDER")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetVertexColor(Listing.RULE[1], Listing.RULE[2], Listing.RULE[3], Listing.RULE[4])
        t:SetHeight(1)
        t:Hide()
        page.rules[i] = t
    end
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
        -- The role's badge and the word, side by side and the pair centered in the button
        -- (a badge drawn inside the text sits crooked): the button is as wide as the pair.
        b.icon = W().Role(b, Listing.ROLE_ICON)
        b.icon:SetPoint("LEFT", b, "LEFT", W().CHIP_PAD, 0)
        b.text:ClearAllPoints()
        b.text:SetPoint("LEFT", b.icon, "RIGHT", Listing.ROLE_GAP, 0)
        b.text:SetJustifyH("LEFT")
        b.extraW = Listing.ROLE_ICON + Listing.ROLE_GAP
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
    page.npfText = Style.Text(page, Style.SIZE.small, "LEFT")   -- like the other labels of the panel
    page.npfText:SetText(LFG_LIST_NEW_PLAYER_FRIENDLY_TOOLTIP or LFG_LIST_NEW_PLAYER_FRIENDLY or L["New player friendly"])
    page.npfText:SetWordWrap(true)
    page.npfText:SetJustifyH("LEFT")
    Style.InkText(page.npfText, "LABEL")
    page.npf = W().Switch(page)
    page.npf:SetScript("OnClick", function()
        Listing.npf = not Listing.npf
        if type(SetCVar) == "function" then pcall(SetCVar, "lfgNewPlayerFriendly", Listing.npf and "1" or "0") end
        page.npf.SetOn(Listing.npf)
        Listing.PaintFooter()
    end)
    page.probe = Style.Text(page, Style.SIZE.small, "LEFT")   -- measures the labels
    page.probe:Hide()
    local function dropdown(key, word, onClick)
        local b = W().MenuButton(page, "", W().CHIP_HEIGHT)
        b.text:SetPoint("RIGHT", b.chevron, "LEFT", -6, 0)
        b.text:SetWordWrap(false)
        b:SetScript("OnClick", onClick)
        page[key] = b
        local fs = Style.Text(page, Style.SIZE.small, "LEFT")
        fs:SetText(word)
        Style.InkText(fs, "LABEL")
        page[key .. "Label"] = fs
    end
    dropdown("cat", _G.CATEGORY or L["Category"], function(self) Listing.CategoryMenu(self) end)
    dropdown("sortBy", _G.WHO_SORT_LABEL or L["Sort by"], function(self) Listing.SortMenu(self) end)
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
    out[#out + 1] = page.cat
    out[#out + 1] = page.sortBy
    for i, p in ipairs(page.pieces or {}) do
        if i > 8 then break end
        out[#out + 1] = p
    end
    return out
end
