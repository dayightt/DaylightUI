-- The fake NPC world for the NPC window tests: the game's GossipFrame and
-- QuestFrame as the game drives them (Mainline CustomGossipFrameBase.lua,
-- Shared/GossipFrameShared.lua, QuestFrame.lua), the gossip and quest functions,
-- and a server that answers a moment later (C_Timer.After: stub.RunTimers).
--
-- NW.world(spec) is stub.Load's "before". A test then talks:
--   NW.Gossip({ text, options = {...}, available = {...}, active = {...} })
--   NW.Quest("DETAIL", { title, text, objective, choices = {...}, rewards = {...}, money, xp })
-- and reads what was called: NW.Calls("SelectOptionByIndex").
local stub = require("stub")

local NW = {}

local function S() return NW.state end
local function record(kind, ...) table.insert(S().calls, { kind = kind, args = { ... } }) end

function NW.Calls(kind)
    local out = {}
    for _, c in ipairs(S().calls) do if c.kind == kind then out[#out + 1] = c.args end end
    return out
end

local function later(fn) C_Timer.After(0, fn) end

-- The game's left-panel slot: opening one left window replaces the other
-- (SetUIPanel in UIParentPanelManager, oldFrame:Hide()).
local function showPanel(f)
    for _, other in ipairs({ _G.GossipFrame, _G.QuestFrame, _G.MerchantFrame, _G.ClassTrainerFrame }) do
        if other and other ~= f and other:IsShown() then other:Hide() end
    end
    stub.PlacePanel(f)
    f:Show()
end

local function buildFrames()
    local gossip = CreateFrame("Frame", "GossipFrame", UIParent)
    gossip:Hide()
    local quest = CreateFrame("Frame", "QuestFrame", UIParent)
    quest:Hide()
    _G.ShowUIPanel = function(f) record("ShowUIPanel", f:GetName()); showPanel(f) end
    _G.HideUIPanel = function(f) record("HideUIPanel", f:GetName()); f:Hide() end
    _G.SetUIPanelAttribute = function(f, key, value) S().panel[f:GetName() .. "." .. key] = value end

    -- The game's gossip manager (CustomGossipFrameBase.lua plus HandleShow).
    local gm = CreateFrame("Frame")
    gm:RegisterEvent("GOSSIP_SHOW")
    gm:RegisterEvent("GOSSIP_CLOSED")
    gm:SetScript("OnEvent", function(_, event)
        if event == "GOSSIP_SHOW" then
            local g = S().gossip
            local opts = C_GossipInfo.GetOptions()
            if #g.available == 0 and #g.active == 0 and #opts == 1 and opts[1].selectOptionWhenOnlyOption then
                C_GossipInfo.SelectOptionByIndex(opts[1].orderIndex)
                return
            end
            if not gossip:IsShown() then ShowUIPanel(gossip) end
        else
            HideUIPanel(gossip)
        end
    end)

    -- The game's quest frame (QuestFrame.lua): the frame itself takes the events.
    -- Each page is a panel, and a panel's OnShow runs QuestInfo_Display, which sets
    -- QuestInfo.lua's ACTIVE_TEMPLATE. The client only runs OnShow for a frame that
    -- becomes visible (the stub's Show always runs it), so a panel shown under a
    -- parked QuestFrame never sets it, and QUEST_ITEM_UPDATE then errors in
    -- QuestInfo_ShowRewards. Seen in game.
    local panels = {}
    for _, key in ipairs({ "Greeting", "Detail", "Progress", "Reward" }) do
        local p = CreateFrame("Frame", "QuestFrame" .. key .. "Panel", quest)
        p:Hide()
        p:SetScript("OnShow", function(self)
            if key ~= "Greeting" and self:IsVisible() then S().questTemplate = key end
        end)
        panels[key] = p
    end
    quest:SetScript("OnShow", function(self)
        if not self:IsVisible() then return end
        for key, p in pairs(panels) do if key ~= "Greeting" and p:IsShown() then S().questTemplate = key end end
    end)
    local PANEL = { QUEST_GREETING = "Greeting", QUEST_DETAIL = "Detail", QUEST_PROGRESS = "Progress", QUEST_COMPLETE = "Reward" }
    for _, e in ipairs({ "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED", "QUEST_ITEM_UPDATE" }) do
        quest:RegisterEvent(e)
    end
    quest:SetScript("OnEvent", function(_, event, startItem)
        if event == "QUEST_FINISHED" then HideUIPanel(quest); return end
        if event == "QUEST_ITEM_UPDATE" then
            if not quest:IsShown() then return end
            if (panels.Detail:IsShown() or panels.Reward:IsShown()) and not S().questTemplate then
                error("attempt to index upvalue 'ACTIVE_TEMPLATE' (a nil value)")
            end
            return
        end
        if event == "QUEST_DETAIL" and type(startItem) == "number" and startItem ~= 0 then
            CloseQuest()   -- started by an item: the tracker's pop-up, no window
            return
        end
        S().questPanel = event
        for _, p in pairs(panels) do p:Hide() end
        panels[PANEL[event]]:Show()
        ShowUIPanel(quest)
    end)

    -- The game's vendor (Mainline/MerchantFrame.lua, through the player interaction
    -- manager): MERCHANT_SHOW shows it, MERCHANT_CLOSED hides it.
    local merchant = CreateFrame("Frame", "MerchantFrame", UIParent)
    merchant:Hide()
    -- Its own OnShow and OnHide (MerchantFrame.lua, MerchantFrame_OnShow/OnHide).
    merchant:SetScript("OnShow", function(self)
        OpenAllBags(self, true)
        ResetSetMerchantFilter()
    end)
    merchant:SetScript("OnHide", function(self)
        CloseMerchant()
        CloseAllBags(self, true)
        ResetCursor()
    end)
    local mm = CreateFrame("Frame")
    mm:RegisterEvent("MERCHANT_SHOW")
    mm:RegisterEvent("MERCHANT_CLOSED")
    mm:SetScript("OnEvent", function(_, event)
        if event == "MERCHANT_SHOW" then ShowUIPanel(merchant) else HideUIPanel(merchant) end
    end)

    _G.CloseAllWindows = function()
        for _, f in ipairs({ gossip, quest, merchant, _G.ClassTrainerFrame }) do if f and f:IsShown() then HideUIPanel(f) end end
    end
    _G.GetUIPanel = function()
        for _, f in ipairs({ gossip, quest, merchant, _G.ClassTrainerFrame }) do if f and f:IsShown() then return f end end
    end
end

-- The game's trainer (Blizzard_TrainerUI, loaded on demand). The player interaction
-- manager runs the bootstrap's show function (Blizzard_TrainerUI_Bootstrap.lua):
-- load the addon (which makes the frame), ShowUIPanel, and if the window still
-- isn't visible, CloseTrainer() at once. TRAINER_SHOW fires too. The frame's
-- OnHide calls CloseTrainer (Mainline/Blizzard_TrainerUI.lua), and the server
-- answers TRAINER_CLOSED.
-- The client draws text no smaller than a few pixels, so a text in a frame
-- shrunk far down measures much wider in that frame's own units. Tests use 7 px
-- a letter at a normal size.
NW.TINY_TEXT = 0.01
local function measured(fs)
    local text = fs:GetText()
    if type(text) ~= "string" then return 0 end
    local scale = fs:GetEffectiveScale()
    local w = #text * 7
    if scale < NW.TINY_TEXT then w = w * NW.TINY_TEXT / scale end
    return w
end

-- What the game's OnShow sizes from its text (ClassTrainerFrame_OnShow ->
-- ClassTrainerFrame_Update): the filter button fits its words
-- (DropdownTextMixin:UpdateText, resizeToText with 60 padding), and each row's
-- name fits beside its TP cost (Blizzard_TrainerUI_Camelot.lua UpdateNameWidth).
local function trainerParts(f)
    local drop = CreateFrame("Button", nil, f)
    drop.Text = drop:CreateFontString(nil, "OVERLAY")
    drop:SetSize(100, 18)
    function drop:UpdateText()
        self.Text:SetText(self.text)
        self:SetWidth(measured(self.Text) + 60)
    end
    function drop:SetText(text) self.text = text; self:UpdateText() end
    f.FilterDropdown = drop
    local box = CreateFrame("Frame", nil, f)
    box.rows = {}
    box.view = { ForEachFrame = function(_, fn) for _, r in ipairs(box.rows) do fn(r) end end }
    function box:GetView() return self.view end
    function box:ForEachFrame(fn) return self:GetView():ForEachFrame(fn) end
    f.ScrollBox = box
    for i = 1, 3 do
        local row = CreateFrame("Button", nil, box)
        row:SetSize(300, 46)
        row.name = row:CreateFontString(nil, "OVERLAY")
        row.alternateCost = row:CreateFontString(nil, "OVERLAY")
        function row:UpdateNameWidth()
            local price = self.alternateCost:IsShown() and measured(self.alternateCost) + 15 or 0
            local room = self:GetWidth() + 5 - price - 48 - 5
            self.name:SetWidth(math.max(1, math.min(measured(self.name), room)))
        end
        box.rows[i] = row
    end
end

local function trainerFill(f)
    f.FilterDropdown:SetText("Filter")
    for i, row in ipairs(f.ScrollBox.rows) do
        row.name:SetText(({ "Bite", "Dash", "Dive" })[i])
        row.alternateCost:SetText(i .. " TP")
        row:UpdateNameWidth()
    end
end

local function trainerFrame()
    local f = _G.ClassTrainerFrame
    if f then return f end
    f = CreateFrame("Frame", "ClassTrainerFrame", UIParent)
    f:Hide()
    f:SetSize(338, 424)
    trainerParts(f)
    f:SetScript("OnShow", function(self)
        S().trainerOnShow = (S().trainerOnShow or 0) + 1
        trainerFill(self)
    end)
    f:SetScript("OnHide", function() CloseTrainer() end)
    record("LoadAddOn", "Blizzard_TrainerUI")
    stub.FireEvent("ADDON_LOADED", "Blizzard_TrainerUI")   -- inside the load, before the show
    return f
end

local function TR() return S().trainer end
-- The game only lists the kinds its filter lets through, and indexes count those.
local function trainerList()
    local out = {}
    for _, s in ipairs(TR().services) do if TR().filter[s.kind] then out[#out + 1] = s end end
    return out
end

local function installTrainer()
    _G.Enum.TrainerType = _G.Enum.TrainerType or { General = 0, TalentsObsolete = 1, Tradeskills = 2, Pet = 3 }
    _G.C_Trainer = {
        GetTrainerType = function() return TR().type or 0 end,
        GetCategorizeTrainerUI = function() return false end,
        SetCategorizeTrainerUI = function() end,
    }
    _G.GetNumTrainerServices = function() return #trainerList() end
    _G.GetTrainerServiceInfo = function(i)
        local s = trainerList()[i]
        if not s then return nil end
        return s.name, s.kind, s.icon or 135808, s.level or 0, s.sub, s.category
    end
    _G.GetTrainerServiceCost = function(i)
        local s = trainerList()[i]
        if not s then return 0 end
        return s.cost or 0, s.profession == true
    end
    _G.GetTrainerServiceItemLink = function(i)
        local s = trainerList()[i]
        return s and s.link
    end
    _G.GetTrainerServiceSkillReq = function(i)
        local s = trainerList()[i]
        if not (s and s.skill) then return nil end
        return s.skill.name, s.skill.rank, (TR().rank or 0) >= s.skill.rank
    end
    _G.GetTrainerServiceStepIndex = function()
        for i, s in ipairs(trainerList()) do if s.step then return i end end
    end
    _G.GetTrainerTradeskillRankValues = function()
        if not TR().rank then return nil end
        return TR().rank, TR().maxRank or 75, TR().modifier or 0
    end
    -- Another spell a service needs first: its `needs` ("Frostbolt Rank 3"), met
    -- once that one is known (Blizzard_TrainerUI.lua's ability requirements).
    _G.GetTrainerServiceNumAbilityReq = function(i)
        local s = trainerList()[i]
        return s and s.needs and 1 or 0
    end
    _G.GetTrainerServiceAbilityReq = function(i, n)
        local s = trainerList()[i]
        if not (s and s.needs and n == 1) then return nil end
        local met = false
        for _, t in ipairs(TR().services) do
            if t.name .. " " .. (t.sub or "") == s.needs and t.kind == "used" then met = true end
        end
        return s.needs, met
    end
    _G.GetTrainerServiceTypeFilter = function(kind) return TR().filter[kind] == true end
    _G.SetTrainerServiceTypeFilter = function(kind, on)
        record("SetTrainerServiceTypeFilter", kind, on and true or false)
        TR().filter[kind] = on and true or false
        later(function() stub.FireEvent("TRAINER_UPDATE") end)
    end
    _G.BuyTrainerService = function(i)
        local s = trainerList()[i]
        record("BuyTrainerService", i, s and s.name)
        if not s or s.kind ~= "available" or (s.cost or 0) > S().money then return end
        S().money = S().money - (s.cost or 0)
        s.kind = "used"
        -- The next rank opens as this one is learned (a service's `needs` is
        -- "Name Rank n" of the one before it).
        for _, t in ipairs(trainerList()) do
            if t.needs == s.name .. " " .. (s.sub or "") and t.kind == "unavailable" then t.kind = "available" end
        end
        later(function() stub.FireEvent("PLAYER_MONEY"); stub.FireEvent("TRAINER_UPDATE") end)
    end
    _G.CloseTrainer = function()
        record("CloseTrainer")
        if TR().open then
            TR().open = false
            later(function()
                stub.FireEvent("TRAINER_CLOSED")
                if _G.ClassTrainerFrame and _G.ClassTrainerFrame:IsShown() then HideUIPanel(_G.ClassTrainerFrame) end
            end)
        end
    end
    _G.GetProfessions = function() return unpack(S().professions or {}) end
    _G.C_PetInfo = _G.C_PetInfo or {}
    _G.C_PetInfo.GetPetTrainingPoints = function() return 10, 0 end
end

-- A trainer from the server: services { name, kind (available|unavailable|used),
-- level, sub, cost, skill = { name, rank }, profession, step }, rank/maxRank (a
-- profession), type (Enum.TrainerType).
function NW.Trainer(spec)
    spec = spec or {}
    S().trainer = { services = spec.services or NW.Spells(), rank = spec.rank, maxRank = spec.maxRank,
        modifier = spec.modifier, type = spec.type, open = true, filter = S().trainer.filter }
    if stub.units and stub.units.player then stub.units.player.level = spec.level or 20 end
    local f = trainerFrame()
    ShowUIPanel(f)
    if not f:IsVisible() then CloseTrainer() end   -- the bootstrap's own check
    stub.FireEvent("TRAINER_SHOW")
end

-- A mage trainer at level 20: five to learn (4g 50s in all), three later, two known.
function NW.Spells()
    return {
        { name = "Frostbolt", sub = "Rank 4", kind = "available", level = 20, cost = 9000 },
        { name = "Blizzard", sub = "Rank 1", kind = "available", level = 20, cost = 10000 },
        { name = "Evocation", kind = "available", level = 20, cost = 10000 },
        { name = "Fire Ward", sub = "Rank 1", kind = "available", level = 20, cost = 9000 },
        { name = "Remove Lesser Curse", kind = "available", level = 18, cost = 7000 },
        { name = "Fireball", sub = "Rank 5", kind = "unavailable", level = 22, cost = 12000 },
        { name = "Scorch", sub = "Rank 2", kind = "unavailable", level = 22, cost = 12000 },
        { name = "Counterspell", kind = "unavailable", level = 24, cost = 13000 },
        { name = "Frost Nova", sub = "Rank 1", kind = "used", level = 10, cost = 500 },
        { name = "Arcane Intellect", sub = "Rank 1", kind = "used", level = 8, cost = 400 },
    }
end

-- A tailoring trainer at skill 118: the next rank, two recipes, two later.
function NW.Recipes()
    return {
        { name = "Expert Tailoring", kind = "unavailable", level = 20, cost = 10000, step = true, skill = { name = "Tailoring", rank = 125 } },
        { name = "Gray Woolen Shirt", kind = "available", level = 0, cost = 500, skill = { name = "Tailoring", rank = 100 } },
        { name = "Woolen Bag", kind = "available", level = 0, cost = 500, skill = { name = "Tailoring", rank = 80 },
            link = "|cnIQ2:|Hitem:4245::::::::20:::::::::|h[Woolen Bag]|h|r" },
        { name = "Heavy Woolen Gloves", kind = "unavailable", level = 0, cost = 1500, skill = { name = "Tailoring", rank = 125 } },
        { name = "Small Silk Pack", kind = "unavailable", level = 0, cost = 2000, skill = { name = "Tailoring", rank = 135 } },
    }
end

local function M() return S().merchant end
local function installMerchant()
    _G.GetMoney = function() return S().money end
    _G.GetMerchantNumItems = function() return #M().items end
    _G.C_MerchantFrame = {
        GetItemInfo = function(i)
            local it = M().items[i]
            if not it then return nil end
            return { name = it.name, texture = it.texture or 134400, price = it.price or 0, stackCount = it.stack or 1,
                numAvailable = it.available or -1, isPurchasable = it.purchasable ~= false, isUsable = it.usable ~= false,
                hasExtendedCost = it.extended == true, isQuestStartItem = it.quest == true, currencyID = it.currencyID }
        end,
        GetNumJunkItems = function() return M().junk end,
        IsSellAllJunkEnabled = function() return M().sellAllJunk ~= false end,
        SellAllJunkItems = function() record("SellAllJunkItems") end,
    }
    -- A currency sold in a container shows the container's name, icon and amount
    -- (the game's CurrencyContainerUtil, from the merchant item's `container`).
    _G.CurrencyContainerUtil = { GetCurrencyContainerInfo = function(id, amount, name, texture)
        for _, it in ipairs(M().items) do
            if it.currencyID == id and it.container then
                return it.container.name, it.container.texture, it.container.amount
            end
        end
        return name, texture, amount
    end }
    -- The bags, for junk: NW.Merchant's `bags` = { [bag] = { { quality, sell, count } } },
    -- `skip` = { [bag] = true } for a bag set to "Ignore" Sell Junk (the game's flag).
    _G.Enum.BagSlotFlags = _G.Enum.BagSlotFlags or { DisableAutoSort = 1, ClassEquipment = 2, ExcludeJunkSell = 64 }
    local function bagItem(bag, slot) return ((M().bags or {})[bag] or {})[slot] end
    _G.C_Container = {
        GetContainerNumSlots = function(bag) return #((M().bags or {})[bag] or {}) end,
        GetContainerNumFreeSlots = function() return 16 end,
        GetContainerItemInfo = function(bag, slot)
            local it = bagItem(bag, slot)
            if not it then return nil end
            return { quality = it.quality or 0, itemID = 7000 + bag * 100 + slot, stackCount = it.count or 1,
                hyperlink = "|Hitem:" .. (7000 + bag * 100 + slot) .. "|h[Junk]|h" }
        end,
        GetBackpackSellJunkDisabled = function() return (M().skip or {})[0] == true end,
        GetBagSlotFlag = function(bag, flag)
            return flag == Enum.BagSlotFlags.ExcludeJunkSell and (M().skip or {})[bag] == true
        end,
    }
    -- The game's repair cursor (MerchantRepairItemButton_OnClick) and guild repairs.
    _G.ShowRepairCursor = function() record("ShowRepairCursor"); S().repairMode = true end
    _G.HideRepairCursor = function() record("HideRepairCursor"); S().repairMode = false end
    _G.InRepairMode = function() return S().repairMode == true end
    _G.CanGuildBankRepair = function() return M().guild ~= nil end
    _G.GetGuildBankWithdrawMoney = function() return M().guild and M().guild.allowance or 0 end
    _G.GetGuildBankMoney = function() return M().guild and M().guild.money or 0 end
    _G.GetMerchantItemLink = function(i) local it = M().items[i]; return it and ("|Hitem:" .. i .. "|h[" .. it.name .. "]|h") end
    _G.GetMerchantItemCostItem = function(i, n)
        local c = (M().items[i].costs or {})[n]
        if c then return c.texture or 133784, c.value, c.link, c.currency end
    end
    _G.GetMerchantItemMaxStack = function(i) return M().items[i].maxStack or 20 end
    _G.BuyMerchantItem = function(i, n) record("BuyMerchantItem", i, n) end
    _G.PickupMerchantItem = function(i) record("PickupMerchantItem", i) end
    _G.GetNumBuybackItems = function() return #M().buyback end
    _G.GetBuybackItemInfo = function(i) local b = M().buyback[i]; return b.name, 134400, b.price, b.count or 1 end
    _G.GetBuybackItemLink = function() return nil end
    _G.BuybackItem = function(i) record("BuybackItem", i) end
    _G.CanMerchantRepair = function() return M().canRepair ~= false end
    _G.GetRepairAllCost = function() return M().repair or 0, (M().repair or 0) > 0 end
    _G.RepairAllItems = function(guild) record("RepairAllItems", guild) end
    _G.CloseMerchant = function()
        record("CloseMerchant")
        C_Timer.After(0, function() stub.FireEvent("MERCHANT_CLOSED") end)
    end
    _G.ResetSetMerchantFilter = function() record("ResetSetMerchantFilter") end
    _G.OpenAllBags = function(owner) record("OpenAllBags", owner and owner:GetName()) end
    _G.CloseAllBags = function(owner) record("CloseAllBags", owner and owner:GetName()) end
    _G.ResetCursor = function() record("ResetCursor") end
    _G.SetCursor = function(c) record("SetCursor", c) end
    _G.ShowBuybackSellCursor = function(i) record("ShowBuybackSellCursor", i) end
    _G.CanAffordMerchantItem = function(i) return (M().items[i].price or 0) <= GetMoney() end
end

-- A vendor from the server: items { name, price, stack, usable, extended }, junk, repair.
function NW.Merchant(spec)
    spec = spec or {}
    S().merchant = { items = spec.items or NW.Goods(), junk = spec.junk or 0, repair = spec.repair or 0,
        buyback = spec.buyback or {}, canRepair = spec.canRepair, bags = spec.bags, skip = spec.skip,
        guild = spec.guild, sellAllJunk = spec.sellAllJunk }
    stub.FireEvent("MERCHANT_SHOW")
end

function NW.Goods()
    return { { name = "Refreshing Spring Water", price = 25, stack = 5 }, { name = "Tough Jerky", price = 25, stack = 5 },
        { name = "Traveler's Backpack", price = 25000 }, { name = "Plate Helm", price = 100, usable = false },
        { name = "Black Lotus", price = 2000000 } }
end

local function copyList(list)
    local out = {}
    for i, v in ipairs(list or {}) do
        local c = {}
        for k, x in pairs(v) do c[k] = x end
        c.orderIndex = c.orderIndex or (i - 1)
        out[i] = c
    end
    return out
end

local function installGossip()
    _G.C_GossipInfo = {
        GetText = function() return S().gossip.text end,
        GetOptions = function() return copyList(S().gossip.options) end,
        GetAvailableQuests = function() return copyList(S().gossip.available) end,
        GetActiveQuests = function() return copyList(S().gossip.active) end,
        SelectOptionByIndex = function(i) record("SelectOptionByIndex", i); S().picked = { "option", i } end,
        SelectAvailableQuest = function(id) record("SelectAvailableQuest", id); S().picked = { "available", id } end,
        SelectActiveQuest = function(id) record("SelectActiveQuest", id); S().picked = { "active", id } end,
        CloseGossip = function()
            record("CloseGossip")
            later(function() stub.FireEvent("GOSSIP_CLOSED", false) end)
        end,
        ForceGossip = function() return false end,
    }
    -- Talking to an NPC is the game's own UI's alone: from addon code the client refuses
    -- it outright, out of a fight too, with "has been blocked from an action only
    -- available to the Blizzard UI" (ADDON_ACTION_FORBIDDEN, seen in game). Nothing runs.
    _G.C_PlayerInteractionManager = {
        InteractUnit = function(unit, exact)
            record("InteractUnit", unit, exact)
            stub.errors[#stub.errors + 1] = "ADDON_ACTION_FORBIDDEN: InteractUnit()"
        end,
    }
end

local function Q() return S().quest end
local function list(kind) return kind == "choice" and Q().choices or kind == "required" and Q().required or Q().rewards end

local function installQuest()
    _G.GetTitleText = function() return Q().title end
    _G.GetQuestText = function() return Q().text end
    _G.GetObjectiveText = function() return Q().objective end
    _G.GetProgressText = function() return Q().progress end
    _G.GetRewardText = function() return Q().reward end
    _G.GetGreetingText = function() return S().greeting.text end
    _G.GetQuestID = function() return Q().questID or 0 end
    _G.IsQuestCompletable = function() return Q().completable ~= false end
    _G.QuestGetAutoAccept = function() return Q().auto == true end
    _G.QuestFlagsPVP = function() return Q().pvp == true end
    _G.GetNumQuestChoices = function() return #(Q().choices or {}) end
    _G.GetNumQuestRewards = function() return #(Q().rewards or {}) end
    -- The quest log's side (a quest's `log`: { choices = n, loading = true }; none means not in the log).
    local function logged(id)
        local q = Q()
        return q.questID == id and q.log or nil
    end
    _G.C_QuestLog = _G.C_QuestLog or {}
    _G.C_QuestLog.GetLogIndexForQuestID = function(id) return logged(id) and 1 or nil end
    _G.C_QuestLog.RequestLoadQuestByID = function(id) record("RequestLoadQuestByID", id) end
    -- The quest's `level`; 0 for a quest the client knows nothing of, as the game answers.
    _G.C_QuestLog.GetQuestDifficultyLevel = function(id)
        local q = Q()
        return q.questID == id and q.level or 0
    end
    -- Quest tags by id (NW.tags[id] = tagID, 81 a dungeon), as the game's log reads them.
    NW.tags = {}
    _G.C_QuestLog.GetQuestTagInfo = function(id) local t = NW.tags[id]; return t and { tagID = t } or nil end
    _G.C_QuestLog.IsEliteQuest = function() return false end
    _G.HaveQuestData = function(id) local l = logged(id); return l ~= nil and not l.loading end
    _G.GetNumQuestLogChoices = function(id)
        local l = logged(id)
        return l and not l.loading and l.choices or 0
    end
    _G.GetNumQuestItems = function() return #(Q().required or {}) end
    _G.IsQuestItemHidden = function() return 0 end
    -- A reward's `lootType` is what the client answers for it (0 = an item).
    _G.GetQuestItemInfoLootType = function(kind, i)
        local it = (list(kind) or {})[i]
        return it and it.lootType or 0
    end
    -- The quest's fixed currency rewards (a quest's `currencies`: { name, count, currencyID }),
    -- apart from its item rewards, as QuestInfo.lua reads them.
    _G.C_QuestInfoSystem = _G.C_QuestInfoSystem or {}
    _G.C_QuestInfoSystem.GetQuestRewardCurrencies = function(id)
        local q = Q()
        if not q or q.questID ~= id then return {} end
        local out = {}
        for i, c in ipairs(q.currencies or {}) do
            out[i] = { name = c.name, texture = c.texture or 133784, totalRewardAmount = c.count or 1,
                baseRewardAmount = c.count or 1, quality = c.quality or 1, currencyID = c.currencyID or 1000 + i }
        end
        return out
    end
    _G.GetQuestItemInfo = function(kind, i)
        local it = (list(kind) or {})[i]
        if not it then return end
        -- `loading`: the game knows the slot but not the item yet (no name).
        if it.loading then return nil, it.texture or 134400, it.count or 1, nil, nil, it.itemID or i end
        return it.name, it.texture or 134400, it.count or 1, it.quality or 1, it.usable ~= false, it.itemID or i
    end
    _G.GetQuestItemLink = function(kind, i)
        local it = (list(kind) or {})[i]
        return it and ("|Hitem:" .. (it.itemID or i) .. "|h[" .. it.name .. "]|h")
    end
    -- A reward's vendor price. No `sell` on it means not loaded yet, like the game's cache.
    _G.C_Item.GetItemInfo = function(key)
        for _, kind in ipairs({ "choice", "reward" }) do
            for i, it in ipairs(list(kind) or {}) do
                if (it.itemID or i) == key and it.sell then
                    return it.name, nil, it.quality, nil, nil, nil, nil, nil, nil, nil, it.sell
                end
            end
        end
        -- A trainer recipe's item, by its link: `useLevel` on the service means the item
        -- is loaded (5th return: the level it needs), else nil like the game's cache.
        for _, s in ipairs(trainerList()) do
            if s.link and s.link == key and s.useLevel then
                return s.name, s.link, 2, nil, s.useLevel
            end
        end
        -- A gray item in the bags (C_Container above): its vendor price.
        if type(key) == "string" then
            local id = tonumber(key:match("Hitem:(%d+)"))
            local m = S().merchant
            if id and id >= 7000 and m and m.bags then
                local bag, slot = math.floor((id - 7000) / 100), (id - 7000) % 100
                local it = (m.bags[bag] or {})[slot]
                if it then return "Junk", key, it.quality or 0, nil, nil, nil, nil, nil, nil, nil, it.sell or 0 end
            end
        end
    end
    -- The rest of what QuestInfo.lua and QuestFrame.lua read from an offer: spell
    -- rewards (a quest's `spells`: { spellID, name, texture, type, known, hide }),
    -- a title, skill points { name, icon, points }, honor, the suggested group size,
    -- a "learn this spell" objective (`criteria` = { spellID, name, texture }),
    -- required currencies (`requiredCurrencies`: { name, count, currencyID }) and
    -- the offer's "hide the required items" flag (`hideRequired`).
    Enum.QuestCompleteSpellType = { LegacyBehavior = 0, Follower = 1, Tradeskill = 2, Ability = 3, Aura = 4, Spell = 5,
        Unlock = 6, Companion = 7, QuestlineUnlock = 8, QuestlineReward = 9, QuestlineUnlockPart = 10, PossibleReward = 11 }
    Enum.SpellBookSpellBank = Enum.SpellBookSpellBank or { Player = 0, Pet = 1 }
    local function spellOf(id)
        for _, s in ipairs(Q().spells or {}) do if s.spellID == id then return s end end
    end
    _G.C_QuestInfoSystem.GetQuestRewardSpells = function(id)
        local q = Q()
        if not q or q.questID ~= id then return {} end
        local out = {}
        for i, s in ipairs(q.spells or {}) do out[i] = s.spellID end
        return out
    end
    _G.C_QuestInfoSystem.GetQuestRewardSpellInfo = function(id, spellID)
        local s = Q().questID == id and spellOf(spellID)
        if not s then return nil end
        return { texture = s.texture or 136116, name = s.name, isTradeskill = false, isSpellLearned = s.type == 5,
            hideSpellLearnText = s.hide == true, isBoostSpell = false, genericUnlock = false, type = s.type or 0 }
    end
    _G.C_SpellBook = _G.C_SpellBook or {}
    _G.C_SpellBook.IsSpellInSpellBook = function(spellID)
        local s = spellOf(spellID)
        return s ~= nil and s.known == true
    end
    _G.C_Spell = _G.C_Spell or {}
    _G.C_Spell.GetSpellLink = function(id) return "|Hspell:" .. id .. "|h[" .. tostring(id) .. "]|h" end
    _G.GetRewardTitle = function() return Q().rewardTitle end
    _G.GetRewardSkillPoints = function()
        local s = Q().skill
        if s then return s.name, s.icon, s.points end
    end
    _G.GetRewardHonor = function() return Q().honor or 0 end
    _G.GetSuggestedGroupSize = function() return Q().group or 0 end
    _G.GetCriteriaSpell = function()
        local c = Q().criteria
        if c then return c.spellID, c.name, c.texture or 136116, false end
    end
    _G.GetNumQuestCurrencies = function() return #(Q().requiredCurrencies or {}) end
    _G.C_QuestOffer = _G.C_QuestOffer or {}
    _G.C_QuestOffer.GetQuestRequiredCurrencyInfo = function(i)
        local c = (Q().requiredCurrencies or {})[i]
        if c then return { texture = c.texture or 133784, name = c.name, currencyID = c.currencyID or 2000 + i, quality = 1, requiredAmount = c.count or 1 } end
    end
    _G.C_QuestOffer.GetHideRequiredItems = function() return Q().hideRequired == true end
    -- The game's quest icons (Blizzard_FrameXMLUtil QuestUtils.lua GetQuestIconOffer): a
    -- repeatable quest wears the blue "!", a plain one the gold.
    _G.QuestUtil = _G.QuestUtil or {}
    _G.QuestUtil.GetQuestIconOfferForQuestID = function(_, isLegendary, frequency, isRepeatable)
        if isLegendary then return "legendaryavailablequesticon", true end
        if isRepeatable then return "Interface/GossipFrame/DailyActiveQuestIcon", false end
        return "Interface/GossipFrame/AvailableQuestIcon", false
    end
    _G.GetRewardMoney = function() return Q().money or 0 end
    _G.GetRewardXP = function() return Q().xp or 0 end
    _G.GetQuestMoneyToGet = function() return Q().cost or 0 end
    _G.GetNumActiveQuests = function() return #S().greeting.active end
    _G.GetActiveTitle = function(i) local q = S().greeting.active[i]; return q.title, q.isComplete == true end
    _G.GetActiveQuestID = function(i) return S().greeting.active[i].questID end
    _G.IsActiveQuestTrivial = function(i) return S().greeting.active[i].isTrivial == true end
    _G.GetNumAvailableQuests = function() return #S().greeting.available end
    _G.GetAvailableTitle = function(i) return S().greeting.available[i].title end
    _G.GetAvailableQuestInfo = function(i)
        local q = S().greeting.available[i]
        return q.isTrivial == true, q.frequency, q.repeatable, q.isLegendary, q.questID, q.isImportant, q.isMeta, q.questInfoID
    end
    _G.SelectAvailableQuest = function(i) record("SelectAvailableQuestIndex", i) end
    _G.SelectActiveQuest = function(i)
        if i == nil then error("Usage: SelectActiveQuest(index)") end   -- the game's own check
        record("SelectActiveQuestIndex", i)
    end
    -- The server answers: accepting, handing in or closing ends the conversation.
    local function finish() later(function() stub.FireEvent("QUEST_FINISHED") end) end
    _G.AcceptQuest = function() record("AcceptQuest"); finish() end
    _G.AcknowledgeAutoAcceptQuest = function() record("AcknowledgeAutoAcceptQuest"); finish() end
    _G.DeclineQuest = function() record("DeclineQuest"); finish() end
    _G.CloseQuest = function() record("CloseQuest"); finish() end
    _G.CompleteQuest = function() record("CompleteQuest") end
    _G.GetQuestReward = function(i) record("GetQuestReward", i); finish() end
    _G.QuestChooseRewardError = function() record("QuestChooseRewardError") end
    -- The game's item loader (ItemMixin): the reward window waits on it for a name
    -- GetQuestItemInfo doesn't have yet. NW.LoadItem(id) is the item arriving.
    S().itemWaits = {}
    _G.Item = { CreateFromItemID = function(_, id)
        return { ContinueOnItemLoad = function(_, fn)
            record("ContinueOnItemLoad", id)
            local w = S().itemWaits
            w[id] = w[id] or {}
            table.insert(w[id], fn)
        end }
    end }
end

function NW.LoadItem(id)
    local w = S().itemWaits[id] or {}
    S().itemWaits[id] = nil
    for _, fn in ipairs(w) do fn() end
end

-- The NPC you talk to: name, reaction (5 friendly), guid.
function NW.Npc(spec)
    spec = spec or {}
    local units = { player = { name = "Daylight", class = "WARRIOR", level = 60, isPlayer = true } }
    units.npc = { name = spec.name or "William Pestle", reaction = spec.reaction or 5, guid = spec.guid or "Creature-0-1-2-3-253-0" }
    -- The quest window's unit: the NPC you talk to, unless spec.questnpc says who
    -- else gives the quest (a party member sharing one), or false for none.
    if spec.questnpc ~= false then units.questnpc = spec.questnpc or units.npc end
    stub.SetUnits(units)
end

-- A gossip page from the server.
function NW.Gossip(spec)
    spec = spec or {}
    S().gossip = { text = spec.text or "Welcome.", options = spec.options or {}, available = spec.available or {}, active = spec.active or {} }
    stub.FireEvent("GOSSIP_SHOW")
end

function NW.CloseGossip(continuing) stub.FireEvent("GOSSIP_CLOSED", continuing == true) end

-- A quest page from the server: mode GREETING, DETAIL, PROGRESS or COMPLETE.
function NW.Quest(mode, spec, startItem)
    spec = spec or {}
    if mode == "GREETING" then
        S().greeting = { text = spec.text or "Greetings.", available = spec.available or {}, active = spec.active or {} }
    else
        S().quest = spec
    end
    stub.FireEvent("QUEST_" .. mode, startItem or 0)
end

function NW.Escape() CloseAllWindows() end

-- A sample quest: three reward choices, money and experience.
function NW.Candles(extra)
    local q = { title = "Kobold Candles", questID = 60, text = "Bring me eight large candles.",
        objective = "Bring 8 Large Candles to William Pestle.", progress = "Have you got them?",
        reward = "Thank you! Pick something.", money = 80, xp = 450,
        choices = { { name = "Walking Boots", quality = 2 }, { name = "Herbalist's Band", quality = 2 }, { name = "Mine Blade", quality = 1 } },
        rewards = {}, required = { { name = "Large Candle", count = 8 } } }
    for k, v in pairs(extra or {}) do q[k] = v end
    return q
end

function NW.world(spec)
    spec = spec or {}
    return function()
        NW.state = { calls = {}, panel = {}, gossip = { text = "", options = {}, available = {}, active = {} },
            quest = {}, greeting = { text = "", available = {}, active = {} }, money = 21435,
            merchant = { items = {}, junk = 0, repair = 0, buyback = {} },
            trainer = { services = {}, filter = { available = true, unavailable = true, used = false } } }
        buildFrames()
        installGossip()
        installQuest()
        installMerchant()
        installTrainer()
        NW.Npc(spec.npc)
        if spec.before then spec.before() end
    end
end

return NW
