-- The Pet page: your hunter pet or warlock demon, while one is out
-- (HasPetUI, as the game's own pet side tab). Its name and "Level 60 Wolf"
-- over its model (ns.PetModel, the same glow and drag as yours), a thin XP
-- bar under it while it can still level, the stats pane on the right as on
-- the Character page (the game's pet rows, ns.Stats.PET_GROUPS), and in the
-- footer a hunter pet's mood and what it does to its damage.

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char
local L = DUI.L
local Style = DUI.Style

local PetPage = {}
ns.PetPage = PetPage

PetPage.HEAD = 44            -- the name and level lines over the model
PetPage.NAME_SIZE, PetPage.SUB_SIZE, PetPage.FOOT_SIZE = Style.SIZE.head, Style.SIZE.small, Style.SIZE.small
PetPage.GAP = 20             -- the model's room to the stats pane
PetPage.XP_H = 4             -- the XP bar
PetPage.XP_GAP = 10          -- under the model
PetPage.FACE = 18            -- the mood face in the footer
-- The game's mood faces (PetHappiness.lua) and our colors for them.
PetPage.MOOD = {
    [1] = { atlas = "UI-PetMad", color = Style.INK.BAD },
    [2] = { atlas = "UI-PetNeutral", color = Style.INK.WARN },
    [3] = { atlas = "UI-PetHappiness", color = Style.INK.GOOD },
}

local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end
local function plain(v, kind) return type(v) == kind and not isSecret(v) end

-- A pet to show: true for a hunter pet or a warlock demon, and whether it's
-- a hunter's (mood, loyalty and XP are theirs only).
function PetPage.Has()
    if type(HasPetUI) ~= "function" then return false, false end
    local ok, has, hunter = pcall(HasPetUI)
    return ok and has == true, ok and hunter == true
end

PetPage.Available = function() return (PetPage.Has()) end

-- What the page shows, read now; nil without a pet. Only plain values (a
-- secret one is left out).
function PetPage.Read()
    local has, hunter = PetPage.Has()
    if not has then return nil end
    local d = { hunter = hunter }
    local name = DUI.UnitName("pet", "pet")
    d.name = plain(name, "string") and name or nil
    local level = UnitLevel("pet")
    d.level = plain(level, "number") and level or nil
    local family = type(UnitCreatureFamily) == "function" and UnitCreatureFamily("pet")
    d.family = plain(family, "string") and family or nil
    if not hunter then return d end
    local loyalty = C_PetInfo and type(C_PetInfo.GetPetLoyalty) == "function" and C_PetInfo.GetPetLoyalty()
    d.loyalty = plain(loyalty, "string") and loyalty ~= "" and loyalty or nil
    if type(GetPetExperience) == "function" then
        local cur, need = GetPetExperience()
        if plain(cur, "number") and plain(need, "number") and need > 0 then d.xp, d.xpNeed = cur, need end
    end
    if C_PetInfo and type(C_PetInfo.GetPetHappiness) == "function" then
        local ok, mood, damage, rate = pcall(C_PetInfo.GetPetHappiness)
        if ok and plain(mood, "number") and PetPage.MOOD[mood] then
            d.mood = mood
            d.damage = plain(damage, "number") and damage or nil
            d.loyaltyRate = plain(rate, "number") and rate or nil
        end
    end
    return d
end

-- "Level 60 Wolf (Loyalty Level 3)": the level pops, the loyalty dimmer.
function PetPage.SubLine(d)
    local C = ns.Colors
    local level = d.level and C.Wrap(tostring(d.level), Style.Pop()) or "?"
    local text = string.format(L["Level %s %s"], level, d.family or "")
    if d.loyalty then
        local c = Style.INK.LABEL
        text = text .. " " .. C.Wrap("(" .. d.loyalty .. ")", c[1], c[2], c[3])
    end
    return text
end

-- Where everything goes, as { x, y (down is negative), w, h } from the
-- page's top left. Pure: tested without frames.
function PetPage.Rects(width, height)
    local CP = ns.CharacterPage
    local E, T, FOOT = CP.EDGE, CP.TOP, CP.FOOTER
    local bodyH = height - FOOT - CP.FOOT_LIFT
    local R = {}
    R.stats = { x = width - E - CP.STATS_W, y = -T, w = CP.STATS_W, h = bodyH - T - 4 }
    local w = R.stats.x - PetPage.GAP - E
    R.head = { x = E, y = -T, w = w, h = PetPage.HEAD }
    local modelY = -T - PetPage.HEAD
    R.xp = { x = E, y = -(bodyH - PetPage.XP_GAP - PetPage.XP_H), w = w, h = PetPage.XP_H }
    R.model = { x = E, y = modelY, w = w, h = -R.xp.y - PetPage.XP_GAP - (-modelY) }
    R.footer = { x = E, y = -bodyH, w = width - 2 * E, h = FOOT }
    return R
end

local function put(page, f, r)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", page, "TOPLEFT", r.x, r.y)
    if r.w then f:SetWidth(r.w) end
    if r.h then f:SetHeight(r.h) end
end

function PetPage.Place(page)
    local R = PetPage.Rects(ns.Window.Width(), ns.Window.H - ns.Window.HEADER)
    put(page, page.head, R.head)
    put(page, page.model, R.model)
    put(page, page.xp, R.xp)
    put(page, page.stats, R.stats)
    page.stats.content:SetWidth(ns.CharacterPage.STATS_W - 2 * ns.CharacterPage.STATS_PAD)
    put(page, page.foot, R.footer)
    ns.PetModel.Spread(0)
end

-- What the game's own mood face says on hover (PetHappiness.lua): the mood,
-- the damage it does, loyalty rising or falling, what it eats.
function PetPage.MoodTip(owner)
    local d = PetPage.Read()
    if not (d and d.mood) or type(GameTooltip) ~= "table" then return end
    local Tips, c = DUI.Tips, PetPage.MOOD[d.mood].color
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    Tips.Clear()
    Tips.Title(_G["PET_HAPPINESS" .. d.mood] or L["Happiness"], c[1], c[2], c[3])
    if d.damage and PET_DAMAGE_PERCENTAGE then Tips.Sub(string.format(PET_DAMAGE_PERCENTAGE, d.damage)) end
    if d.loyaltyRate and d.loyaltyRate < 0 and LOSING_LOYALTY then Tips.Text(LOSING_LOYALTY, Tips.BAD)
    elseif d.loyaltyRate and d.loyaltyRate > 0 and GAINING_LOYALTY then Tips.Text(GAINING_LOYALTY, Tips.GOOD) end
    local ok, diet = pcall(C_PetInfo.GetPetFoodTypes)
    if ok and type(diet) == "table" and PET_DIET_TEMPLATE then
        local list = #diet > 0 and table.concat(diet, PET_FOOD_DELIMIT or ", ") or (NONE or L["None"])
        Tips.Sub(string.format(PET_DIET_TEMPLATE, list))
    end
    Tips.Flush(GameTooltip)
    GameTooltip:Show()
end

local function hideTip() if type(GameTooltip) == "table" then GameTooltip:Hide() end end

function PetPage.BuildFooter(page)
    local CP = ns.CharacterPage
    local foot = CreateFrame("Frame", nil, page)
    CP.FootLine(foot)
    foot.mood = CreateFrame("Frame", nil, foot)
    foot.mood:SetHeight(PetPage.FACE)
    foot.mood:SetPoint("LEFT", foot, "LEFT", 0, 0)
    foot.mood:EnableMouse(true)
    foot.mood:SetScript("OnEnter", PetPage.MoodTip)
    foot.mood:SetScript("OnLeave", hideTip)
    foot.face = foot.mood:CreateTexture(nil, "ARTWORK")
    foot.face:SetSize(PetPage.FACE, PetPage.FACE)
    foot.face:SetPoint("LEFT", foot.mood, "LEFT", 0, 0)
    foot.moodText = Style.Text(foot.mood, PetPage.FOOT_SIZE, "LEFT")
    foot.moodText:SetPoint("LEFT", foot.face, "RIGHT", 6, 0)
    foot.xpText = Style.Text(foot, PetPage.FOOT_SIZE, "LEFT")
    foot.xpText:SetTextColor(CP.DIM[1], CP.DIM[2], CP.DIM[3])
    return foot
end

function PetPage.Build(page)
    page.head = CreateFrame("Frame", nil, page)
    page.name = Style.Text(page.head, PetPage.NAME_SIZE, "CENTER")
    page.name:SetPoint("TOP", page.head, "TOP", 0, -2)
    page.sub = Style.Text(page.head, PetPage.SUB_SIZE, "CENTER")
    page.sub:SetPoint("TOP", page.name, "BOTTOM", 0, -4)
    Style.InkText(page.sub, "LABEL")
    page.model = ns.PetModel.Build(page)
    local base = page:GetFrameLevel() or 0
    page.model:SetFrameLevel(base)
    if ns.PetModel.scene then ns.PetModel.scene:SetFrameLevel(base) end
    page.xp = DUI.Widgets.Bar(page, PetPage.XP_H)
    page.xp:Hide()
    page.stats = ns.CharacterPage.BuildStats(page, ns.Stats.PET_GROUPS)
    page.foot = PetPage.BuildFooter(page)
end

-- The model rises in with the page (Character page's Open).
function PetPage.Open()
    ns.PetModel.SetUp(0)
end

function PetPage.PaintFooter(page, d)
    local foot = page.foot
    local mood = d.mood and PetPage.MOOD[d.mood]
    foot.mood:SetShown(mood ~= nil)
    if mood then
        foot.face:SetAtlas(mood.atlas)
        local word = _G["PET_HAPPINESS" .. d.mood] or ""
        local text = ns.Colors.Wrap(word, mood.color[1], mood.color[2], mood.color[3])
        if d.damage then
            local c = Style.INK.LABEL
            text = text .. ns.Colors.Wrap("  " .. string.format(L["%s damage"], ns.Colors.Wrap(d.damage .. "%", Style.Pop())), c[1], c[2], c[3])
        end
        foot.moodText:SetText(text)
        foot.mood:SetWidth(PetPage.FACE + 6 + math.ceil(foot.moodText:GetStringWidth() or 0))
    end
    foot.xpText:ClearAllPoints()
    if mood then foot.xpText:SetPoint("LEFT", foot.mood, "RIGHT", 24, 0)
    else foot.xpText:SetPoint("LEFT", foot, "LEFT", 0, 0) end
    if d.xp then
        foot.xpText:SetText(string.format(L["Experience %s / %s"],
            ns.Colors.Wrap(ns.List.Number(d.xp), Style.Pop()), ns.List.Number(d.xpNeed)))
    else
        foot.xpText:SetText("")
    end
end

function PetPage.Refresh(page)
    local d = PetPage.Read()
    if not d then return end
    page.name:SetText(d.name or "")
    Style.InkText(page.name, "VALUE")
    page.sub:SetText(PetPage.SubLine(d))
    page.xp:SetShown(d.xp ~= nil)
    if d.xp then
        DUI.Widgets.BarAccent(page.xp)
        Style.SetBarRange(page.xp, 0, d.xpNeed)
        Style.SetBarValue(page.xp, d.xp)
    end
    PetPage.PaintFooter(page, d)
    ns.PetModel.Paint()
    ns.CharacterPage.RefreshStats(page)
end

-- Another pet out (a new summon, a tamed beast) or its look changed: set
-- the model up again.
function PetPage.OnEvent(_, event, unit)
    if event == "UNIT_PET" or (event == "UNIT_MODEL_CHANGED" and unit == "pet") then
        if PetPage.Available() then ns.PetModel.SetUp() end
    end
end

PetPage.events = { "UNIT_PET", "UNIT_PET_EXPERIENCE", "PET_STATS_UPDATE" }
-- Asked for "player" and "pet" both (Window.lua): your stats feed your pet's.
PetPage.petEvents = { "UNIT_HAPPINESS", "UNIT_MODEL_CHANGED", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_STATS",
    "UNIT_ATTACK_POWER", "UNIT_DAMAGE", "UNIT_RESISTANCES", "UNIT_MAXHEALTH" }

ns.Window.Register("pet", PetPage)
