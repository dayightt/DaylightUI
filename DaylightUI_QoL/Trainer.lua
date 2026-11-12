-- Train All button: learn every affordable spell at a class trainer in one click.

local _, ns = ...
local L = DaylightUI.L

local Trainer = {}
ns.Trainer = Trainer
ns.features[#ns.features + 1] = Trainer

local mod, registered, button, busy, learned, spent
-- What this run already asked for, by name and rank: on a slow server a
-- line still reads available after its buy, and was bought again.
local asked = {}

local money = DaylightUI.MoneyString

local function shown()
    local f = _G.ClassTrainerFrame
    return type(f) == "table" and type(f.IsShown) == "function" and f:IsShown()
end

-- Beast Training (hunter spell) reuses this window but buying there is
-- Blizzard-only; it has no NPC, so only offer the button at a real trainer.
-- A pet trainer charges training points, not gold: no button there either.
local PET_TRAINER = 3 -- Enum.TrainerType.Pet
local function atNpc()
    if type(C_Trainer) == "table" and type(C_Trainer.GetTrainerType) == "function"
        and C_Trainer.GetTrainerType() == PET_TRAINER then return false end
    return type(UnitExists) ~= "function" or UnitExists("npc") == true
end

local function keyOf(name, sub) return tostring(name) .. "|" .. tostring(sub or "") end

-- Returns the first service we can buy now, how many there are, their total
-- cost and the first one's key. `budget` is the money still free to spend.
-- `skip` is this run's already-asked list; without it nothing is skipped.
local function scan(budget, skip)
    if type(GetNumTrainerServices) ~= "function" or type(GetTrainerServiceInfo) ~= "function" then return nil, 0, 0 end
    local first, count, total, firstKey = nil, 0, 0, nil
    for i = 1, GetNumTrainerServices() do
        local name, status, _, _, sub = GetTrainerServiceInfo(i)
        local key = keyOf(name, sub)
        if status == "available" and not (skip and skip[key]) then
            local cost, isProfession
            if type(GetTrainerServiceCost) == "function" then cost, isProfession = GetTrainerServiceCost(i) end
            -- Only a plain number is a gold cost. A new profession is never
            -- learned here: it uses up a profession slot (the game asks first).
            if type(cost) == "number" and not (issecretvalue and issecretvalue(cost))
                and isProfession ~= true and total + cost <= budget then
                total = total + cost
                count = count + 1
                if not first then first, firstKey = i, key end
            end
        end
    end
    return first, count, total, firstKey
end

local function budget()
    return type(GetMoney) == "function" and GetMoney() or 0
end

function Trainer.Update()
    if not button then return end
    local _, count = scan(budget())
    button:SetText(L["Train all (%d)"]:format(count))
    if count > 0 then button:Enable() else button:Disable() end
end

local function step()
    if not busy then return end
    if not (mod and mod.db and mod.db.trainAll == true) or not shown() then busy = false; return end
    local i, _, _, key = scan(budget(), asked)
    if not i then
        busy = false
        if learned > 0 then
            DaylightUI.Print(L["Learned %d skills for %s."]:format(learned, money(spent)))
        end
        Trainer.Update()
        return
    end
    local cost = GetTrainerServiceCost(i)
    asked[key] = true
    BuyTrainerService(i)
    learned, spent = learned + 1, spent + cost
    C_Timer.After(0.2, step)
end

function Trainer.Click()
    if busy or type(BuyTrainerService) ~= "function" or not atNpc() then return end
    busy, learned, spent = true, 0, 0
    asked = {}
    step()
end

local function tooltip(self)
    if type(GameTooltip) ~= "table" then return end
    local _, count, total = scan(budget())
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local Tips = DaylightUI.Tips
    Tips.Clear()
    Tips.Title(L["Learn %d available skills"]:format(count))
    Tips.Line(L["Total cost"], money(total), Tips.MONEY)
    Tips.Flush(GameTooltip)
    GameTooltip:Show()
end

local function build()
    if button then return end
    local frame = _G.ClassTrainerFrame
    if type(frame) ~= "table" or type(CreateFrame) ~= "function" then return end
    button = CreateFrame("Button", "DaylightUITrainAllButton", frame, "UIPanelButtonTemplate")
    button:SetSize(84, 22)
    DaylightUI.Widgets.DressButton(button)
    local train = _G.ClassTrainerTrainButton
    if type(train) == "table" then
        button:SetPoint("RIGHT", train, "LEFT", -2, 0)
    else
        button:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -90, 54)
    end
    button:SetScript("OnClick", Trainer.Click)
    button:SetScript("OnEnter", tooltip)
    button:SetScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
    Trainer.Update()
end

local function onShow()
    if not (mod and mod.db and mod.db.trainAll == true) then return end
    if not atNpc() then
        busy = false
        if button then button:Hide() end
        return
    end
    build()
    if button then button:Show(); Trainer.Update() end
end

function Trainer.Enable(m)
    mod = m
    if registered then return end
    registered = true
    DaylightUI.RegisterEvent("TRAINER_SHOW", onShow)
    DaylightUI.RegisterEvent("TRAINER_UPDATE", function() if shown() then onShow() end end)
    DaylightUI.RegisterEvent("TRAINER_CLOSED", function() busy = false end)
    DaylightUI.RegisterEvent("ADDON_LOADED", function(_, name)
        if name == "Blizzard_TrainerUI" then onShow() end
    end)
    if C_AddOns and C_AddOns.IsAddOnLoaded("Blizzard_TrainerUI") then onShow() end
end

function Trainer.Refresh(m)
    mod = m
    if button and not (m.db and m.db.trainAll == true) then button:Hide() end
end
