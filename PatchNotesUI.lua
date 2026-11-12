-- The Patch Notes section in /dui, drawn from DUI.PatchNotes, plus the "new"
-- glow on its sidebar button until the newest release's notes are opened. The
-- last version read is saved account-wide (DaylightUIDB.notesSeen). A first
-- install starts caught up.

local _, DUI = ...
local L = DUI.L
local SIZE = DUI.Style.SIZE -- the text size scale

local Notes = {}
DUI.Notes = Notes

Notes.SECTION = "patchnotes"
Notes.KINDS = {
    { key = "new", label = "New" },
    { key = "changed", label = "Changed" },
    { key = "fixed", label = "Fixed" },
}
local UNRELEASED = "Unreleased"

-- The newest version that has shipped (the list is newest first).
function Notes.Latest()
    for _, v in ipairs(DUI.PatchNotes or {}) do
        if v.version ~= UNRELEASED then return v.version end
    end
end

-- Problems with a notes list, as text (empty when it's fine).
function Notes.Validate(list)
    local errors = {}
    local function fail(at, why) errors[#errors + 1] = at .. ": " .. why end
    if type(list) ~= "table" then
        fail("PatchNotes", "not a table")
        return errors
    end
    local seen = {}
    for i, v in ipairs(list) do
        local at = "PatchNotes[" .. i .. "]"
        if type(v.version) ~= "string" then
            fail(at, "missing version")
        else
            if seen[v.version] then fail(at, "duplicate version " .. v.version) end
            seen[v.version] = true
            if v.version == UNRELEASED and i ~= 1 then fail(at, "Unreleased must be first") end
        end
        if v.date ~= nil and not (type(v.date) == "string" and string.match(v.date, "^%d%d%d%d%-%d%d%-%d%d$")) then
            fail(at, "date must be YYYY-MM-DD")
        end
        if v.summary ~= nil and type(v.summary) ~= "string" then fail(at, "summary must be text") end
        for _, kind in ipairs(Notes.KINDS) do
            local lines = v[kind.key]
            if lines ~= nil and type(lines) ~= "table" then
                fail(at, kind.key .. " must be a list")
            elseif lines then
                for j, line in ipairs(lines) do
                    if type(line) ~= "table" or type(line[1]) ~= "string" or type(line[2]) ~= "string" then
                        fail(at .. "." .. kind.key .. "[" .. j .. "]", "want { area, text }")
                    end
                end
            end
        end
    end
    return errors
end

function Notes.IsNew()
    local latest = Notes.Latest()
    return latest ~= nil and DUI.DB.Root().notesSeen ~= latest
end

function Notes.MarkSeen()
    local latest = Notes.Latest()
    if latest then DUI.DB.Root().notesSeen = latest end
end

-- A first install has nothing to catch up on.
function Notes.OnLogin()
    if DUI.DB.fresh and DUI.DB.Root().notesSeen == nil then Notes.MarkSeen() end
end
DUI.On("Login", Notes.OnLogin)

-- The page: one card per version, newest first. All text uses the Appearance
-- font (Style.FONT), read on every draw so a new pick shows on the next refresh.

local TITLE_H = 44 -- a card's title row (click to fold)
local SUB_H = 22      -- a "New" / "Changed" / "Fixed" subhead
local LINE_GAP = 6
local TEXT = SIZE.body
local DOT = 14 -- room for the accent dot left of each line

local open = {} -- version -> true/false once clicked (not saved)

local function hasLines(v)
    for _, kind in ipairs(Notes.KINDS) do
        if v[kind.key] and #v[kind.key] > 0 then return true end
    end
    return false
end

-- Unreleased only shows once it has lines.
function Notes.Shown()
    local list = {}
    for _, v in ipairs(DUI.PatchNotes or {}) do
        if v.version ~= UNRELEASED or hasLines(v) then list[#list + 1] = v end
    end
    return list
end

-- Unreleased and the newest release start open, older ones folded.
function Notes.IsOpen(version)
    if open[version] ~= nil then return open[version] end
    return version == UNRELEASED or version == Notes.Latest()
end

function Notes.Toggle(version)
    open[version] = not Notes.IsOpen(version)
    if DUI.OptionsPanel and DUI.OptionsPanel.Refresh then DUI.OptionsPanel.Refresh() end
end

local function setFont(fs, size) fs:SetFont(DUI.Style.FONT, size, "") end

-- Height of a wrapped string (falls back to one line).
local function textHeight(fs, size)
    local h = fs.GetStringHeight and fs:GetStringHeight()
    if type(h) ~= "number" or h <= 0 then h = size + 2 end
    return h
end

-- The options window's own accent, never the player's.
local function accentHex()
    local m = DUI.Style.GRADIENT_MID
    local r, g, b = m[1], m[2], m[3]
    return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function makeCard(row)
    local W = DUI.Widgets
    local C = W.COLORS
    local card = CreateFrame("Frame", nil, row)
    card.bg = W.Round(card, "BACKGROUND")
    card.bg:SetAllPoints(card)
    W.Tint(card.bg, C.card)
    card.head = CreateFrame("Button", nil, card)
    card.head:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    card.head:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
    card.head:SetHeight(TITLE_H)
    card.head:SetScript("OnClick", function() Notes.Toggle(card.version) end)
    card.head:SetScript("OnEnter", function() W.Tint(card.chevron, C.text) end)
    card.head:SetScript("OnLeave", function() W.Tint(card.chevron, C.dim) end)
    card.chevron = W.Icon(card.head, "ui-chevron.png", 12, C.dim)
    card.chevron:SetPoint("LEFT", card.head, "LEFT", W.PAD, 0)
    card.title = W.Font(card.head, DUI.Style.FONT, SIZE.head, C.text)
    card.title:SetPoint("LEFT", card.chevron, "RIGHT", 8, 0)
    card.date = W.Font(card.head, DUI.Style.FONT, SIZE.small, C.faint, "RIGHT")
    card.date:SetPoint("RIGHT", card.head, "RIGHT", -W.PAD, 0)
    card.summary = W.Font(card, DUI.Style.FONT, TEXT, C.dim)
    card.summary:SetWordWrap(true)
    card.pieces = {}   -- subheads and lines, reused between draws
    return card
end

local function piece(card, i)
    local p = card.pieces[i]
    if not p then
        local W = DUI.Widgets
        p = {}
        p.dot = card:CreateTexture(nil, "ARTWORK")
        p.dot:SetTexture(DUI.MEDIA .. "ui-pill.png")
        p.dot:SetSize(5, 5)
        p.text = W.Font(card, DUI.Style.FONT, TEXT, W.COLORS.text)
        p.text:SetWordWrap(true)
        card.pieces[i] = p
    end
    return p
end

-- Draws one version into its card and returns the card's height.
local function drawCard(card, v, width)
    local W = DUI.Widgets
    local C = W.COLORS
    local isOpen = Notes.IsOpen(v.version)
    card.version = v.version
    setFont(card.title, SIZE.head)
    setFont(card.date, SIZE.small)
    card.title:SetText(v.version == UNRELEASED and L["Coming next"] or ("DaylightUI " .. v.version))
    card.date:SetText(v.date or "")
    -- Chevron points down when open, right when folded.
    card.chevron:SetRotation(isOpen and 0 or math.pi / 2)
    local y, used = TITLE_H, 0
    local full = width - W.PAD * 2
    card.summary:SetShown(isOpen and v.summary ~= nil)
    if isOpen and v.summary then
        setFont(card.summary, TEXT)
        card.summary:ClearAllPoints()
        card.summary:SetPoint("TOPLEFT", card, "TOPLEFT", W.PAD, -y)
        card.summary:SetWidth(full)
        card.summary:SetText(v.summary)
        card.summary.english = true -- notes stay in English (they're posted to Discord too)
        y = y + textHeight(card.summary, TEXT) + 10
    end
    if isOpen then
        local hex = accentHex()
        for _, kind in ipairs(Notes.KINDS) do
            local lines = v[kind.key]
            if lines and #lines > 0 then
                used = used + 1
                local sub = piece(card, used)
                sub.dot:Hide()
                setFont(sub.text, SIZE.small)
                W.TextColor(sub.text, C.dim)
                sub.text:ClearAllPoints()
                sub.text:SetPoint("TOPLEFT", card, "TOPLEFT", W.PAD, -y)
                sub.text:SetWidth(full)
                sub.text:SetText(L[kind.label])
                sub.text.english = nil
                sub.text:Show()
                y = y + SUB_H
                for _, line in ipairs(lines) do
                    used = used + 1
                    local p = piece(card, used)
                    setFont(p.text, TEXT)
                    W.TextColor(p.text, C.text)
                    p.text:ClearAllPoints()
                    p.text:SetPoint("TOPLEFT", card, "TOPLEFT", W.PAD + DOT, -y)
                    p.text:SetWidth(full - DOT)
                    p.text:SetText("|cff" .. hex .. line[1] .. "|r  -  " .. line[2])
                    p.text.english = true
                    p.text:Show()
                    W.TintDaylight(p.dot)
                    p.dot:ClearAllPoints()
                    p.dot:SetPoint("TOPLEFT", card, "TOPLEFT", W.PAD + 2, -(y + 5))
                    p.dot:Show()
                    y = y + textHeight(p.text, TEXT) + LINE_GAP
                end
                y = y + 8
            end
        end
    end
    for i = used + 1, #card.pieces do
        card.pieces[i].text:Hide()
        card.pieces[i].dot:Hide()
    end
    local h = isOpen and (y + 8) or TITLE_H
    card:SetHeight(h)
    return h
end

local list = {
    type = "custom", label = "Patch notes",
    build = function(row)
        row.cards = {}
        Notes.row = row
    end,
    update = function(row)
        -- Opening the page marks the newest notes as read.
        Notes.MarkSeen()
        local W = DUI.Widgets
        local width = row:GetWidth()
        if type(width) ~= "number" or width <= 0 then width = DUI.OptionsPanel.CONTENT_WIDTH end
        local shown = Notes.Shown()
        local y = 0
        for i, v in ipairs(shown) do
            local card = row.cards[i] or makeCard(row)
            row.cards[i] = card
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -y)
            card:SetWidth(width)
            card:Show()
            y = y + drawCard(card, v, width) + W.CARD_GAP
        end
        for i = #shown + 1, #row.cards do row.cards[i]:Hide() end
        row.total = math.max(1, y - W.CARD_GAP)
    end,
    height = function(row) return row.total or 1 end,
}

DUI.Options.RegisterSection(Notes.SECTION, "Patch Notes", 1000).badge = Notes.IsNew   -- drawn through Options.Text
DUI.Options.RegisterPage({
    id = "patchnotes", section = Notes.SECTION, label = "Patch Notes",
    scope = "general", defaults = DUI.DB.GENERAL_DEFAULTS,
    desc = "What changed in each version. Click a version to open or close it.",
    groups = { { label = "Patch notes", bare = true, items = { list } } },
})

DUI.RegisterCommand("notes", function() DUI.OptionsPanel.Show("patchnotes") end, L["/dui notes - what's new"])
