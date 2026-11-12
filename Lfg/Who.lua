-- Who page: a search box (the game's /who syntax: name, zone, class, guild, level or a
-- range like "20-25"), a Sort chip (name, class, level via C_FriendList.SortWho), how
-- many the server found, then the results: name in class color with guild, level, race
-- and class below and zone on the right. Click selects one for the footer's Whisper and
-- Invite; right-click offers the same at the cursor. Who results are routed to this page
-- only while it shows (C_FriendList.SetWhoToUi, which is one client-wide switch; the
-- game's page does the same).

local _, DUI = ...
DUI.Lfg = DUI.Lfg or {}
local ns = DUI.Lfg
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win

local Who = {}
ns.Who = Who

Who.EDGE = 16
Who.TOP = 64
Who.SORTS = { "level", "name", "class" }   -- the game's WHO_SORT_* keys

local function W() return DUI.Widgets end
local function Data() return ns.Data end

local function friends() return type(C_FriendList) == "table" and C_FriendList or nil end

-- A /who from the search box (Enter) or a tab click. Empty search = everyone at the
-- player's level.
function Who.Send(text)
    local F = friends()
    if not (F and F.SendWho) then return end
    text = type(text) == "string" and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if text == "" then text = tostring(Data().Level()) end
    Who.asked = text
    Who.searching = true
    local origin = Enum and Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social
    pcall(F.SendWho, text, origin)
    Who.Render()
end

function Who.Sort(mode)
    Who.sort = mode
    local F = friends()
    if F and F.SortWho then pcall(F.SortWho, mode) end
    Who.Render()
end

function Who.SortMenu(owner)
    local values = { level = LEVEL or L["Level"], name = NAME or L["Name"], class = CLASS or L["Class"] }
    W().OpenMenu(owner, Who.SORTS, values, Who.sort or "level", Who.Sort, 120)
end

local function pick(name)
    Who.picked = name
    for _, b in ipairs(Who.rows or {}) do ns.Rows.Pick(b, b.spec.person.name == name) end
    Who.PaintFooter()
end

function Who.PaintFooter()
    local page = Who.page
    if not page then return end
    local name = Who.picked
    page.foot:Set({
        { text = WHISPER or L["Whisper"], primary = true, off = name == nil, onClick = function() Data().Whisper(name) end },
        { text = INVITE or L["Invite"], off = name == nil, onClick = function() Data().Invite(name) end },
    })
end

function Who.Render(page)
    page = page or Who.page
    if not (page and page:IsShown()) then return end
    local list, total = Data().Who()
    local s = page.stack
    s:Begin()
    Who.rows = {}
    local still = false
    for _, p in ipairs(list) do
        local guild = (type(p.guild) == "string" and p.guild ~= "") and ("  " .. Win.Parts.Hex(Style.INK.LABEL) .. "<" .. p.guild .. ">|r") or ""
        local sub = string.format(L["Level %s %s %s"], Win.Parts.Hex({ Style.Pop() }) .. tostring(p.level or "") .. "|r", p.race or "", p.class or "")
        local b = ns.Rows.Row(s, { kind = "person", height = ns.Rows.PERSON, person = p,
            text = ns.Rows.Named(p.name, p.token) .. guild, sub = sub,
            value = p.zone or "", valueColor = Style.INK.TEXT, picked = p.name == Who.picked,
            onClick = function() pick(p.name) end,
            onMenu = function(row) ns.Rows.Menu(row, p.name, true) end })
        Who.rows[#Who.rows + 1] = b
        if p.name == Who.picked then still = true end
    end
    if not still then Who.picked = nil end
    page.pieces = s:End()
    if Who.fresh then Win.Feel.Stagger(page.pieces, 0) end
    Who.fresh = nil
    -- "N found". The server sends 50 at most, so say when there were more.
    local count = #list
    if Who.searching and count == 0 then
        page.found:SetText(L["Asking who's about..."])
    elseif total > count then
        page.found:SetText(string.format(L["%s found, showing %d: narrow the search"], Win.Parts.Hex({ Style.Pop() }) .. total .. "|r", count))
    else
        page.found:SetText(string.format(L["%s found"], Win.Parts.Hex({ Style.Pop() }) .. count .. "|r"))
    end
    page.note:SetShown(count == 0 and not Who.searching)
    page.note:SetText(Who.asked and L["No one matches."] or L["Search for a name, zone, class, guild or level."])
    local sortWord = { level = LEVEL or L["Level"], name = NAME or L["Name"], class = CLASS or L["Class"] }
    page.sort.text:SetText(string.format(L["Sort: %s"], sortWord[Who.sort or "level"]))
    page.sort.FitWidth(0)
    Who.PaintFooter()
end

function Who.Build(page)
    Who.page = page
    page.search = W().Input(page, { search = true, hint = L["Name, zone, class, guild or level"], maxLetters = 64 })
    page.search:SetPoint("TOPLEFT", page, "TOPLEFT", Who.EDGE, -10)
    page.search:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Who.EDGE - 110, -10)
    page.search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        Who.Send(self:GetText())
    end)
    page.sort = W().Button(page, L["Sort"], W().CHIP_HEIGHT)
    page.sort:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Who.EDGE, -11)
    page.sort:SetScript("OnClick", function(self) Who.SortMenu(self) end)
    page.found = Style.Text(page, Style.SIZE.small, "LEFT")
    page.found:SetPoint("TOPLEFT", page, "TOPLEFT", Who.EDGE, -44)
    Style.InkText(page.found, "LABEL")
    page.stack = Win.Parts.Stack(page, { top = Who.TOP, bottom = 52 })
    page.note = Style.Text(page, Style.SIZE.body, "CENTER")
    page.note:SetPoint("CENTER", page, "CENTER", 0, 0)
    Style.InkText(page.note, "LABEL")
    page.note:Hide()
    page.foot = Win.Parts.Footer(page)
    page:HookScript("OnShow", function()
        local F = friends()
        if F and F.SetWhoToUi then pcall(F.SetWhoToUi, true) end
    end)
    page:HookScript("OnHide", function()
        local F = friends()
        if F and F.SetWhoToUi then pcall(F.SetWhoToUi, false) end
    end)
    DUI.RegisterEvent("WHO_LIST_UPDATE", function()
        Who.searching = false
        -- Closed but the page still counts as shown: only draw while visible (opening fills it).
        -- Fresh results: rows lift in one after another.
        if page:IsVisible() then Who.fresh = true; Who.Render(page) end
    end)
end

function Who.Fill(page)
    Who.Render(page)
end

function Who.Pieces(page)
    local out = { page.search, page.sort, page.found }
    for i, p in ipairs(page.pieces or {}) do
        if i > 10 then break end
        out[#out + 1] = p
    end
    return out
end
