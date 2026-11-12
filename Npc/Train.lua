-- Trainer page of the NPC window. Learnable now comes first, then what's coming later
-- by level (or by skill at a profession trainer), dimmed, and "N already known"
-- collapsed at the end. A click only selects a line; the Train button learns it,
-- since Classic spells are expensive and a stray click must never spend gold. Train
-- all learns what the player can afford, one line after another. No key ever learns.
--
-- ClassTrainerFrame is parked under the kit's veil rather than the hidden parent: the
-- game closes a trainer whose window isn't visible when it opens
-- (Blizzard_TrainerUI_Bootstrap.lua). Its OnShow/OnHide/OnEvent still run (OnHide
-- calls CloseTrainer). Learning only goes through BuyTrainerService.

local _, DUI = ...
DUI.Npc = DUI.Npc or {}
local ns = DUI.Npc
local L = DUI.L
local Style = DUI.Style

local Train = {}
ns.Train = Train

Train.W = 440               -- window width while the trainer is open
Train.STEP = 0.2            -- s between Train all's purchases (same pace as QoL's Train All)
Train.CONFIRM = DUI.Widgets.CONFIRM   -- s a "click again" waits (new profession)
Train.SKILL_H = 34          -- height of the profession skill bar under the header
Train.LATER_ORDER = 1e6     -- "Not yet" sorts after every level and skill group

local Win = DUI.Win
local Parts = Win.Parts

local function fn(f) return type(f) == "function" end
local function call(f, ...) if fn(f) then return f(...) end end
local function now() return fn(GetTime) and GetTime() or 0 end
local function sample() return ns.Window.state.sample == true end

-- pick and confirm hold a line's Train.Key (ranks share a name).
local S = { pick = nil, confirm = nil, busy = false, knownOpen = false, asked = {} }
Train.state = S

-- Reading the trainer

-- Every service the trainer lists: { index, name, kind (available | unavailable |
-- used), icon, level, sub, cost, profession, skill, skillRank, skillMet, step,
-- quality (for recipes) }.
function Train.Services()
    if sample() then return Train.sampleList or {} end
    local out = {}
    local step = call(GetTrainerServiceStepIndex)
    for i = 1, call(GetNumTrainerServices) or 0 do
        local name, kind, icon, level, sub = call(GetTrainerServiceInfo, i)
        if name then
            local cost, profession = call(GetTrainerServiceCost, i)
            local skill, rank, met = call(GetTrainerServiceSkillReq, i)
            out[#out + 1] = { index = i, name = name, kind = kind, icon = icon, level = level or 0,
                sub = sub ~= "" and sub or nil, cost = type(cost) == "number" and cost or 0, profession = profession == true,
                skill = skill, skillRank = rank, skillMet = met, step = step == i,
                quality = ns.Shop.QualityOf(call(GetTrainerServiceItemLink, i)) }
        end
    end
    return out
end

-- Profession skill: name, rank, max (nil at a class trainer).
function Train.Skill(list)
    if sample() then return Train.sampleSkill and Train.sampleSkill.name, Train.sampleSkill and Train.sampleSkill.rank, Train.sampleSkill and Train.sampleSkill.max end
    local rank, max = call(GetTrainerTradeskillRankValues)
    if type(rank) ~= "number" or rank <= 0 then return nil end
    local name
    for _, s in ipairs(list) do if s.skill then name = s.skill; break end end
    return name, rank, max
end

function Train.Money() return ns.Shop.MoneyNow() end

-- Both profession slots are used, so no new profession can be learned.
function Train.NoSlot()
    if sample() then return false end
    return select(2, call(GetProfessions)) ~= nil
end

Train.SAMPLE_LEVEL = 20
local function playerLevel()
    if sample() then return Train.SAMPLE_LEVEL end
    return call(UnitLevel, "player") or 0
end

-- Group for a line that can't be learned yet: the level it needs, else the skill,
-- else "Not yet". Returns a label and a sort order.
local function laterGroup(s)
    if (s.level or 0) > playerLevel() then return string.format(L["Level %d"], s.level), s.level end
    if s.skillRank and not s.skillMet then return string.format(L["Needs skill %d"], s.skillRank), 1000 + s.skillRank end
    return L["Not yet"], Train.LATER_ORDER
end

-- Stable key for a line: spell name plus rank. With the name alone, Train all
-- stopped after one rank of each spell.
function Train.Key(s) return s.name .. "|" .. (s.sub or "") end

-- What Train all would learn right now, in order, within the player's money.
function Train.Affordable(list)
    local out, left = {}, Train.Money()
    for _, s in ipairs(list) do
        if s.kind == "available" and not s.profession and not S.asked[Train.Key(s)] and s.cost <= left then
            out[#out + 1] = s
            left = left - s.cost
        end
    end
    return out
end

-- Actions

local function costText(c) return c > 0 and DUI.MoneyString and DUI.MoneyString(c) or "" end

local function buy(s, line)
    if sample() then
        Train.SampleBuy(s)
    else
        BuyTrainerService(s.index)
    end
    S.asked[Train.Key(s)] = true
    if S.pick == Train.Key(s) then S.pick = nil end
    if DUI.Sound then DUI.Sound.Play("done") end
    if line then
        Parts.Shine(line)
        if s.cost > 0 then ns.Shop.Ghost(line, "-" .. costText(s.cost)) end
    end
end

-- Sample mode: spend the money and mark it known, without touching the game.
function Train.SampleBuy(s)
    ns.Shop.sampleMoney = math.max(0, (ns.Shop.sampleMoney or 0) - s.cost)
    s.kind = "used"
    ns.Shop.RollMoney()
    C_Timer.After(0.35, Train.Refresh)
end

function Train.Learn(s, line)
    if s.kind ~= "available" or S.busy then return end
    local bump = function() if line and DUI.Motion then DUI.Motion.Bump(line, 0.98) end end
    if s.cost > Train.Money() then return bump() end
    if s.profession then
        if Train.NoSlot() then return bump() end
        -- A new profession uses one of two slots, so it needs a second click.
        if not (S.confirm and S.confirm.key == Train.Key(s) and now() - S.confirm.at < Train.CONFIRM) then
            S.confirm = { key = Train.Key(s), at = now() }
            if line then
                line.sub:SetText(L["Press Train again: it takes a profession slot"])
                Style.InkText(line.sub, "WARN")
            end
            Train.PaintFooter()
            return
        end
    end
    S.confirm = nil
    buy(s, line)
end

-- The page line for a service, by Train.Key.
local function lineOf(key)
    local page = ns.Window.frame and ns.Window.frame.pages.train
    for _, p in ipairs(page and page.pieces or {}) do
        if p.lineSpec and p.lineSpec.service and Train.Key(p.lineSpec.service) == key then return p end
    end
end

-- The selected line, if it can still be learned.
function Train.Picked(list)
    if not S.pick then return nil end
    for _, s in ipairs(list or Train.Services()) do
        if s.kind == "available" and Train.Key(s) == S.pick then return s end
    end
end

-- A click selects a line (never learns it); the footer's Train button shows the cost.
function Train.Pick(s)
    if S.busy then return end
    local key = Train.Key(s)
    if S.pick ~= key then S.confirm = nil end
    S.pick = key
    local page = ns.Window.frame and ns.Window.frame.pages.train
    for _, p in ipairs(page and page.pieces or {}) do
        if p.lineSpec and p.lineSpec.service then Parts.PickLine(p, Train.Key(p.lineSpec.service) == key) end
    end
    Train.PaintFooter(page)
end

-- Train button: learn the selected line.
function Train.TrainPicked()
    local s = Train.Picked()
    if s then Train.Learn(s, lineOf(Train.Key(s))) end
end

-- Train all: the first affordable line, then the next a moment later. The list is
-- re-read each time because learning shifts the game's indexes.
local function step()
    if not S.busy then return end
    if not Win.IsOpen(ns.Window.frame) or ns.Window.state.mode ~= "trainer" then S.busy = false; return end
    local s = Train.Affordable(Train.Services())[1]
    if not s then
        S.busy = false
        Train.PaintFooter()
        return
    end
    buy(s, lineOf(Train.Key(s)))
    C_Timer.After(Train.STEP, step)
end

-- Train all can spend a lot, so it needs a second click (the footer says "Click again
-- to train all"; a double-click doesn't count).
Train.ALL = "*all"   -- S.confirm key while Train all is asking (line keys always contain a "|")

function Train.All()
    if S.busy then return end
    if #Train.Affordable(Train.Services()) == 0 then return end
    local c = S.confirm
    if not (c and c.key == Train.ALL and now() - c.at < Train.CONFIRM) then
        local at = now()
        S.confirm = { key = Train.ALL, at = at }
        Train.PaintFooter()
        C_Timer.After(Train.CONFIRM, function()
            if S.confirm and S.confirm.key == Train.ALL and S.confirm.at == at then
                S.confirm = nil
                Train.PaintFooter()
            end
        end)
        return
    end
    if now() - c.at < DUI.Widgets.CONFIRM_GAP then return end   -- second half of a double-click
    S.confirm = nil
    S.busy = true
    Train.PaintFooter()
    step()
end

-- The page

local function tooltip(s)
    return function(b)
        if not GameTooltip then return end
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        if sample() or not GameTooltip.SetTrainerService then
            GameTooltip:SetText(s.name)
        else
            GameTooltip:SetTrainerService(s.index)
        end
        GameTooltip:Show()
    end
end

local function lineFor(s, cash, noSlot)
    local spec = { service = s, icon = s.icon, text = s.name, sub = s.sub, value = costText(s.cost),
        tooltip = tooltip(s) }
    if s.kind ~= "available" then
        spec.dim = true
        if s.kind == "used" then spec.value = "" end
        return spec
    end
    -- Recipe names in their item's quality color (uncommon and up; white stays warm).
    if type(s.quality) == "number" and s.quality >= 2 then
        local r, g, b = Parts.QualityColor(s.quality)
        spec.color = { r, g, b }
    end
    local bad = ns.Shop.BAD
    spec.valueColor = s.cost > cash and bad or DUI.Style.INK.MONEY
    if s.profession then
        if noSlot then
            spec.sub, spec.subColor, spec.valueColor = L["No free profession slot"], bad, bad
        else
            spec.sub = L["A new profession"]
        end
    end
    spec.picked = S.pick == Train.Key(s)
    spec.onClick = function()
        Train.Pick(s)
        if DUI.Pad.On() then Train.TrainPicked() end   -- A trains, like the game's trainer
    end
    return spec
end

local function makeSkill(page)
    local f = CreateFrame("Frame", nil, page)
    f:SetPoint("TOPLEFT", page, "TOPLEFT", Parts.EDGE, -10)
    f:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Parts.EDGE, -10)
    f:SetHeight(Train.SKILL_H - 10)
    f.text = Style.Text(f, Style.SIZE.body, "LEFT")
    f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.value = Style.Text(f, Style.SIZE.body, "RIGHT")
    f.value:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    Style.InkText(f.text, "VALUE")
    Style.InkText(f.value, "VALUE")
    -- Progress bar: an accent gradient pill that glides.
    f.bar = DUI.Widgets.Bar(f, DUI.Widgets.BAR_H)
    f.bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    f.bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    f:Hide()
    return f
end

function Train.Build(page)
    page.skill = makeSkill(page)
    page.stack = Parts.Stack(page, { top = 10, bottom = ns.Window.FOOT })
    page.foot = Parts.Footer(page)
end

local function paintSkill(page, name, rank, max)
    local f = page.skill
    local on = rank ~= nil
    f:SetShown(on)
    -- The list starts under the bar when there is one.
    page.stack.scroll:SetPoint("TOPLEFT", page, "TOPLEFT", Parts.EDGE, -(on and (10 + Train.SKILL_H) or 10))
    if not on then return end
    f.text:SetText(name or L["Skill"])
    f.value:SetText(string.format("%d / %d", rank, max or rank))
    DUI.Style.InkText(f.value, "pop")   -- skill numbers pop
    -- Same as the profession window's skill bar: set the range, glide to the rank (instant
    -- while the window isn't open yet), accent read at paint time.
    local top = math.max(1, max or rank)
    f.bar:SetMinMaxValues(0, top)
    Style.SetBarValue(f.bar, math.min(rank, top), not Win.IsOpen(ns.Window.frame))
    DUI.Widgets.BarAccent(f.bar)
end

function Train.Fill(page)
    local list = Train.Services()
    local cash, noSlot = Train.Money(), Train.NoSlot()
    if not Train.Picked(list) then S.pick, S.confirm = nil, nil end   -- learned, or gone
    paintSkill(page, Train.Skill(list))
    local s = page.stack
    s:Begin()
    local nowList, later, known = {}, {}, {}
    for _, svc in ipairs(list) do
        if svc.kind == "available" then nowList[#nowList + 1] = svc
        elseif svc.kind == "used" then known[#known + 1] = svc
        else later[#later + 1] = svc end
    end
    -- The profession's next rank goes first in its group.
    local function stepFirst(a, b)
        if a.step ~= b.step then return a.step end
        return a.index < b.index
    end
    table.sort(nowList, stepFirst)
    s:Section(string.format(L["Learn now · %d"], #nowList))
    if #nowList == 0 then
        s:Text(L["Nothing new to learn right now."], { color = Parts.DIM })
    end
    for _, svc in ipairs(nowList) do s:Line(lineFor(svc, cash, noSlot)) end
    -- Coming later, grouped.
    local groups, order = {}, {}
    for _, svc in ipairs(later) do
        local label, rank = laterGroup(svc)
        if not groups[label] then
            groups[label] = { rank = rank, list = {} }
            order[#order + 1] = label
        end
        table.insert(groups[label].list, svc)
    end
    table.sort(order, function(a, b) return groups[a].rank < groups[b].rank end)
    for _, label in ipairs(order) do
        s:Section(label)
        table.sort(groups[label].list, stepFirst)
        for _, svc in ipairs(groups[label].list) do s:Line(lineFor(svc, cash, noSlot)) end
    end
    -- Already known, collapsed.
    page.known = nil
    if #known > 0 then
        s:Gap(6)
        local row = s:Row({ text = string.format(S.knownOpen and L["- %d already known"] or L["+ %d already known"], #known),
            color = Parts.DIM,
            onEnter = function(b) DUI.Style.InkText(b.text, "VALUE") end,
            onLeave = function(b) DUI.Style.InkText(b.text, "LABEL") end,
            onClick = function()
                S.knownOpen = not S.knownOpen
                Train.Refresh()
            end })
        page.known = row.text
        if S.knownOpen then
            for _, svc in ipairs(known) do s:Line(lineFor(svc, cash, noSlot)) end
        end
    end
    page.pieces = s:End()
    if page.skill:IsShown() then table.insert(page.pieces, 1, page.skill) end
    Train.PaintFooter(page, list)
end

-- list: the services Fill just read, or nil to read them here.
function Train.PaintFooter(page, list)
    page = page or (ns.Window.frame and ns.Window.frame.pages.train)
    if not (page and page.foot) then return end
    list = list or Train.Services()
    local total = 0
    for _, s in ipairs(Train.Affordable(list)) do total = total + s.cost end
    local esc = ns.Setting("keys") ~= false and L["Esc"] or nil
    local s = Train.Picked(list)
    local text = L["Train"]
    if s and S.confirm and S.confirm.key == Train.Key(s) then text = L["Click again to train"]
    elseif s and s.cost > 0 then text = string.format(L["Train · %s"], costText(s.cost)) end
    local cant = not s or s.cost > Train.Money() or (s.profession and Train.NoSlot())
    local all = total > 0 and string.format(L["Train all · %s"], costText(total)) or L["Train all"]
    if total > 0 and S.confirm and S.confirm.key == Train.ALL then all = L["Click again to train all"] end
    page.foot:Set({
        { text = text, primary = true, off = cant or S.busy, onClick = Train.TrainPicked },
        { text = all,
          off = total == 0 or S.busy, onClick = Train.All },
        { text = L["Goodbye"], key = esc, onClick = ns.Window.Goodbye },
    })
end

-- Refill in place (trainer or money changed): no lift-in, scroll position kept.
function Train.Refresh()
    local f = ns.Window.frame
    local page = f and f.pages.train
    if not (page and page:IsShown()) then return end
    local sf = page.stack.scroll
    local y = sf:GetVerticalScroll() or 0
    Train.Fill(page)
    local max = math.max(0, (page.stack.height or 0) - (sf:GetHeight() or 0))
    sf:SetVerticalScroll(math.min(y, max))
end

-- Trainer opened: list every kind. These are the game's own type filters, saved by
-- the game, and its window would show the same with them on.
function Train.Opened()
    S.pick, S.confirm, S.busy, S.knownOpen, S.asked = nil, nil, false, false, {}
    if sample() then return end
    for _, kind in ipairs({ "available", "unavailable", "used" }) do
        if fn(GetTrainerServiceTypeFilter) and not GetTrainerServiceTypeFilter(kind) then
            call(SetTrainerServiceTypeFilter, kind, true)
        end
    end
end

-- The game's list changed (learned, or a name loaded): the pending request is now
-- known or refused, and Train all re-reads.
function Train.Updated()
    if not S.busy then S.asked = {} end
end

function Train.Closed() S.busy, S.confirm = false, nil end

-- Sample trainer (the sample talk's "I'd like to train.")

local SAMPLE_ICON = 135808
local function sampleService(i, name, sub, kind, level, cost)
    return { index = i, name = name, sub = sub, kind = kind, level = level, cost = cost, icon = SAMPLE_ICON }
end

function Train.StartSample()
    Train.sampleList = {
        sampleService(1, L["Frostbolt"], L["Rank 4"], "available", 20, 9000),
        sampleService(2, L["Blizzard"], L["Rank 1"], "available", 20, 10000),
        sampleService(3, L["Evocation"], nil, "available", 20, 10000),
        sampleService(4, L["Remove Lesser Curse"], nil, "available", 18, 7000),
        sampleService(5, L["Fireball"], L["Rank 5"], "unavailable", 22, 12000),
        sampleService(6, L["Counterspell"], nil, "unavailable", 24, 13000),
        sampleService(7, L["Frost Nova"], L["Rank 1"], "used", 10, 500),
    }
    Train.sampleSkill = nil
    ns.Shop.sampleMoney = 30000
    ns.Shop.shown = nil
end
