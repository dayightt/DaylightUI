-- Small read-only window for someone else's profession, opened from a linked
-- profession or a guild member. One column: owner and skill, a search, and their
-- recipes by category with materials. No crafting, tabs or spells. The game's frame
-- stays parked under the veil like for the player's own (Window.lua), so closing one
-- closes the other; both read the same trade skill, so only one shows at a time.

local _, DUI = ...
DUI.Craft = DUI.Craft or {}
local ns = DUI.Craft
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win

local View = {}
ns.View = View

View.NAME = "DaylightUICraftView"
View.W, View.H = 340, 480
View.EDGE = 12
View.BAR_Y = 12        -- skill bar
View.SEARCH_Y = 26     -- search box under it
View.TOP = 62          -- where the recipes start
View.ITEM_WAIT = 0.2   -- s to let item info settle before re-reading the list

local function open() return View.frame ~= nil and Win.IsOpen(View.frame) end

local function keep(recipe)
    return not View.filter or string.find(string.lower(recipe.name), View.filter, 1, true) ~= nil
end

-- Click: Shift links the recipe, like the player's own list. Nothing else here.
local function onClick(b)
    local r = b.lineSpec and b.lineSpec.recipe
    if not (r and IsModifiedClick and IsModifiedClick("CHATLINK")) then return end
    local link = ns.Data.RecipeLink(r)
    local insert = ChatFrameUtil and ChatFrameUtil.InsertLink or ChatEdit_InsertLink
    if link and type(insert) == "function" then insert(link) end
end

function View.Render(keepScroll)
    local page, data = View.page, View.data
    if not (page and data) then return end
    local s = page.stack
    local at = keepScroll and s:Scrolled() or 0
    local spots = page:IsVisible() and keepScroll and s:Spots() or nil
    s:Begin()
    View.lines = {}
    local any = false
    for _, section in ipairs(data.sections) do
        local shown = {}
        for _, r in ipairs(section.recipes) do if keep(r) then shown[#shown + 1] = r end end
        if #shown > 0 then
            any = true
            s:Section(section.name)
            for _, r in ipairs(shown) do
                View.lines[r.id] = s:Line({ recipe = r, icon = r.icon, text = r.name,
                    color = ns.Data.NameColor(r, true), sub = r.sub, onClick = onClick,
                    tooltip = ns.List.Tip, id = "recipe:" .. tostring(r.id) })   -- skill-up text doesn't apply here
            end
        end
    end
    page.pieces = s:End()
    page.note:SetShown(not any)
    page.note:SetText(View.filter and L["No recipes match."] or L["No recipes yet."])
    s:ScrollTo(at)
    s:Ease(spots)
end

local function header(f, data)
    local prof, owner = data.prof, ns.Data.Viewing()
    if not prof then return end
    local skill, max = prof.skill + prof.bonus, prof.max
    Win.SetTitle(f, prof.name, nil, type(owner) == "string"
        and string.format(L["%s, skill %d / %d"], owner, skill, max)
        or string.format(L["Skill %d / %d"], skill, max))
    local icon = ns.Data.Icon(prof.id)
    if icon then Win.SetIcon(f, icon) end
    f.portrait:SetShown(icon ~= nil)
    f.portraitRim:SetShown(icon ~= nil)
    local bar = View.page.bar
    bar:SetMinMaxValues(0, math.max(1, max))
    Style.SetBarValue(bar, math.min(skill, max), not Win.IsOpen(f))
    DUI.Widgets.BarAccent(bar)
end

-- Re-read. Another person or profession starts from the top with a fresh search.
local function read(keepScroll)
    if ns.Data.Changing() then return end   -- TRADE_SKILL_LIST_UPDATE comes back here
    View.data = ns.Data.Read()
    local prof, owner = View.data.prof, ns.Data.Viewing()
    local who = tostring(owner) .. ":" .. tostring(prof and prof.id)
    local same = keepScroll and who == View.who
    if who ~= View.who and View.filter then View.page.search:SetText("") end
    View.who = who
    header(View.frame, View.data)
    View.Render(same)
    return not same
end

local function build(page)
    View.page = page
    local W = DUI.Widgets
    page.bar = W.Bar(page, W.BAR_H)
    page.bar:SetPoint("TOPLEFT", page, "TOPLEFT", View.EDGE, -View.BAR_Y)
    page.bar:SetPoint("TOPRIGHT", page, "TOPRIGHT", -View.EDGE, -View.BAR_Y)
    page.search = W.Input(page, { search = true, hint = SEARCH or L["Search"], onChange = function(t)
        View.filter = (type(t) == "string" and t ~= "") and string.lower(t) or nil
        View.Render()
    end })
    page.search:SetPoint("TOPLEFT", page, "TOPLEFT", View.EDGE, -View.SEARCH_Y)
    page.search:SetPoint("TOPRIGHT", page, "TOPRIGHT", -View.EDGE, -View.SEARCH_Y)
    page.stack = Win.Parts.Stack(page, { top = View.TOP, bottom = 10 })
    page.note = Style.Text(page, Style.SIZE.body, "CENTER")
    page.note:SetPoint("CENTER", page, "CENTER", 0, 0)
    Style.InkText(page.note, "LABEL")
    page.note:Hide()
end

local function rows(page)
    local out = {}
    for i, p in ipairs(page.pieces or {}) do
        if i > 12 then break end
        out[#out + 1] = p
    end
    return out
end

local function pieces(page)
    local out = { page.search }
    for _, p in ipairs(rows(page)) do out[#out + 1] = p end
    return out
end

-- The list arrives after the window, from the server, in bursts. Read once it settles,
-- only while shown, like List.Soon.
function View.Soon(wait)
    if not open() then return end
    local at = GetTime() + wait
    if View.pending and View.pending <= at then return end
    View.pending = at
    C_Timer.After(wait, function()
        if View.pending ~= at then return end
        View.pending = nil
        if open() and ns.Data.Viewing() ~= nil then read(true) end
    end)
end

function View.Build()
    if View.frame then return View.frame end
    local f = Win.New({ name = View.NAME, back = "Professions", w = View.W, h = View.H, portrait = true })
    View.frame = f
    f.onClose = function() ns.Window.Close() end
    Win.AddPage(f, "view", { Build = build, pieces = pieces, w = View.W, h = View.H })
    Win.Build(f, "view")
    Win.ShowPage(f, "view")
    Win.Drag(f, { save = ns.Window.SaveSpot, reset = ns.Window.ResetSpot })
    Win.WheelScale(f, function() return ns.Setting("scale") end, function(v) DUI:Set("Professions", "scale", v) end)
    DUI.RegisterEvent("TRADE_SKILL_LIST_UPDATE", function() View.Soon(0) end)
    DUI.RegisterEvent("GET_ITEM_INFO_RECEIVED", function() View.Soon(View.ITEM_WAIT) end)
    View.Apply()
    return f
end

function View.Open()
    local f = View.Build()
    if Win.IsOpen(f) then
        if read(true) then Win.Feel.Stagger(rows(View.page), 0) end
        return
    end
    View.who = nil
    ns.Window.Place(f)
    read()
    Win.Open(f)
end

-- Close this one; the game's frame is up to the caller (Window.lua).
function View.Shut()
    if open() then ns.Window.Shut(View.frame) end
end

function View.Apply()
    local f = View.frame
    if not f then return end
    f:SetScale(Win.Scale(ns.Setting("scale")))
    Win.Repaint(f)
    if Win.IsOpen(f) then
        ns.Window.Place(f)
        View.Render(true)
        if View.data then header(f, View.data) end
    end
end
