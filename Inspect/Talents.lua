-- Talents page: their three trees, drawn by the spellbook's tree code (Book/Talents.lua)
-- in read-only mode (box.readOnly: a click only links to chat, the tooltip has no learn
-- hints, nothing is ever spent). Read from the inspect trait config
-- (Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID, as Blizzard_ClassTalentsFrame does).
-- Works for any class with spent ranks plain, and C_Traits has no secret returns in the
-- game's docs, so combat reads the same. A line under the trees shows points per tree
-- in each tree's color.
--
-- Insp.Refill calls Fill often (re-reads after INSPECT_READY, item events), so the trees
-- are only redrawn when the player or a rank changed (page.drawn). A style change
-- clears it (Insp.Apply).

local _, DUI = ...
DUI.Inspect = DUI.Inspect or {}
local ns = DUI.Inspect
local L = DUI.L
local Style = DUI.Style

local Page = {}
ns.TalentsPage = Page

Page.FOOT = 40   -- room under the trees for the points line

local function configID()
    local c = Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID
    return c or -1
end

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

local function hex(r, g, b)
    return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function tree() return DUI.Book and DUI.Book.Talents end

-- What was drawn: the player, their class and every rank. A secret guid (identity
-- restricted) can't be a key, so it always redraws.
local function keyOf(unit, token, data)
    local guid = UnitGUID(unit)
    if secret(guid) or type(guid) ~= "string" then return nil end
    local out = { guid, tostring(token) }
    for _, t in ipairs(data.trees) do
        out[#out + 1] = "|"
        for _, n in ipairs(t.nodes) do out[#out + 1] = n.id .. ":" .. n.rank end
    end
    return table.concat(out, ",")
end

function Page.Build(page)
    page.trees = {}
    local T = tree()
    page.split = Style.Text(page, Style.SIZE.small, "LEFT")
    Style.InkText(page.split, "LABEL")   -- the dots; names and numbers carry their own color
    page.split:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", T.EDGE + 4, 14)
    page.note = Style.Text(page, Style.SIZE.body, "CENTER")
    Style.InkText(page.note, "LABEL")
    page.note:SetPoint("CENTER", page, "CENTER", 0, 0)
    page.note:SetText(L["No talents yet."])
    page.note:Hide()
    page:HookScript("OnHide", function(self) self.shownBefore = nil end)
end

local function empty(page)
    for _, box in ipairs(page.trees) do box:Hide() end
    page.split:SetText("")
    page.note:Show()
    page.drawn = nil
    page.shownBefore = page:IsVisible() or nil   -- trees that arrive later fade in
end

function Page.Fill(page)
    local unit = ns.Window.unit
    local T = tree()
    local data = unit and T and DUI.Book.TalentData.Read(configID()) or nil
    if not data or #data.trees == 0 then return empty(page) end
    local _, token = UnitClass(unit)
    if secret(token) then token = nil end
    local key = keyOf(unit, token, data)
    if key and key == page.drawn then return end
    local fresh = page.shownBefore and page:IsVisible()   -- new data while shown: fade in
    page.note:Hide()
    local W, H = ns.Window.W, ns.Window.H - DUI.Win.HEADER - 1
    local n = #data.trees
    local w = math.floor((W - 2 * T.EDGE - (n - 1) * T.GAP) / n)
    local h = H - T.EDGE - Page.FOOT
    local pitch, size, px = T.Fit(data, w, h)
    local INK = Style.INK
    local parts = {}
    for i, t in ipairs(data.trees) do
        local box = page.trees[i]
        if not box then box = T.MakeTree(page); page.trees[i] = box end
        box.readOnly, box.token, box.index = true, token, i
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", page, "TOPLEFT", T.EDGE + (i - 1) * (w + T.GAP), -T.EDGE)
        box:SetSize(w, h)
        box:Show()
        T.FillTree(box, t, pitch, size, data, px)
        Style.InkText(box.pts, t.spent > 0 and "pop" or "OFF")   -- points are a number a glance needs
        if fresh then DUI.Motion.Tween(box, 0, 1, DUI.Motion.FAST, function(a) box:SetAlpha(a) end) end
        local r, g, b = T.TreeColor(i, token)
        local nr, ng, nb = r * 0.85 + INK.LABEL[1] * 0.15, g * 0.85 + INK.LABEL[2] * 0.15, b * 0.85 + INK.LABEL[3] * 0.15
        local num = t.spent > 0 and { Style.Pop() } or INK.OFF
        parts[#parts + 1] = string.format("%s%s|r %s%d|r", hex(nr, ng, nb), t.name, hex(num[1], num[2], num[3]), t.spent)
    end
    for i = n + 1, #page.trees do page.trees[i]:Hide() end
    page.split:SetText(table.concat(parts, "  ·  "))
    page.drawn = key
    page.shownBefore = true
end

-- Lift-in order: trees left to right, then the points line.
function Page.Pieces(page)
    local out = {}
    for _, box in ipairs(page.trees) do if box:IsShown() then out[#out + 1] = box end end
    out[#out + 1] = page.note:IsShown() and page.note or page.split
    return out
end

ns.PAGES[#ns.PAGES + 1] = { id = "talents", text = TALENTS or L["Talents"], Build = Page.Build, Fill = Page.Fill,
    pieces = Page.Pieces }
