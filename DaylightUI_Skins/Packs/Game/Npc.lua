-- The game's own Npc window, in the Daylight UI look, for players who pick it over
-- Daylight UI's (Win.Swap). Never walked while Daylight UI's window covers it.
-- Gossip, quests and the vendor are here. The trainer is the NPC pack's Beast
-- Training skin, which the NPC window turns on once the game's trainer shows as itself.

local _, ns = ...
local Engine = ns.Engine

local function g(name) return _G[name] end

-- Daylight UI's NPC window stands in for this game window right now.
local function covered(kind)
    local N = DaylightUI.Npc and DaylightUI.Npc.Window
    return type(N) == "table" and type(N.Covers) == "function" and N.Covers(kind) == true
end

-- Whether a frame sits inside the game's quest window, not the world map's quest
-- log, which fills the same text through QuestInfo_Display.
local function inQuestFrame(f)
    local q = g("QuestFrame")
    for _ = 1, 12 do
        if type(f) ~= "table" or not f.GetParent then return false end
        if f == q then return true end
        f = f:GetParent()
    end
    return false
end

-- ---------------------------------------------------------------------
-- Quests
-- ---------------------------------------------------------------------

-- The quest text is printed dark for the game's parchment. On the dark panel it's
-- made light, titles in the header color, every time the game fills the window.
local function lightQuest(Kit)
    if covered("quest") then return end
    ns.LightQuestInfo(Kit)
    -- The greeting's quest buttons come from a pool and have no names, so the whole
    -- panel is searched.
    local function buttonsIn(frame, depth)
        if type(frame) ~= "table" or not frame.GetChildren or depth > 6 then return end
        for _, c in ipairs({ frame:GetChildren() }) do
            if Kit.Kind(c) == "Button" then Kit.LightAll(c) end
            buttonsIn(c, depth + 1)
        end
    end
    buttonsIn(g("QuestFrameGreetingPanel"), 0)
end

local questHooked = false
Engine.Window({ key = "game:quest", pack = "npc", frame = "QuestFrame", watch = true,
    skip = function() return covered("quest") end,
    after = function(Kit, f)
        for _, n in ipairs({ "QuestFrameDetailPanel", "QuestFrameRewardPanel", "QuestFrameProgressPanel", "QuestFrameGreetingPanel" }) do
            Kit.Strip(g(n))
        end
        for _, n in ipairs({ "QuestDetailScrollFrame", "QuestRewardScrollFrame", "QuestProgressScrollFrame", "QuestGreetingScrollFrame" }) do
            local sf = g(n)
            Kit.Strip(sf)
            if type(sf) == "table" then Kit.ScrollBar(sf.ScrollBar or g(n .. "ScrollBar")) end
        end
        for _, n in ipairs({ "QuestFrameAcceptButton", "QuestFrameDeclineButton", "QuestFrameCompleteQuestButton",
                             "QuestFrameCompleteButton", "QuestFrameGoodbyeButton", "QuestFrameGreetingGoodbyeButton" }) do
            Kit.Button(g(n))
        end
        lightQuest(Kit)
        if questHooked then return end
        questHooked = true
        -- The game fills and colors the text each time it shows a page. The world
        -- map's skin may put the game's dark ink back after this, so it's lit again
        -- next frame too.
        local function relight()
            lightQuest(Kit)
            C_Timer.After(0, function() lightQuest(Kit) end)
        end
        if type(QuestInfo_Display) == "function" then
            hooksecurefunc("QuestInfo_Display", function(_, parent)
                if inQuestFrame(parent) then relight() end
            end)
        end
        if type(QuestFrameProgressItems_Update) == "function" then hooksecurefunc("QuestFrameProgressItems_Update", relight) end
        local greeting = g("QuestFrameGreetingPanel")
        if type(greeting) == "table" and greeting.HookScript then greeting:HookScript("OnShow", relight) end
        f:HookScript("OnShow", relight)
    end })

-- ---------------------------------------------------------------------
-- Gossip
-- ---------------------------------------------------------------------

Engine.Window({ key = "game:gossip", pack = "npc", frame = "GossipFrame", watch = true,
    skip = function() return covered("gossip") end,
    after = function(Kit, f)
        local panel = f.GreetingPanel
        if type(panel) ~= "table" then return end
        Kit.Strip(panel)
        Kit.Button(panel.GoodbyeButton)
        Kit.ScrollBar(panel.ScrollBar)
        -- Each greeting and option row gets light text. The greeting's text sits a
        -- few levels down in its row.
        Kit.EachRow(panel.ScrollBox, function(row)
            if not covered("gossip") then Kit.LightAll(row, nil, 3) end
        end)
    end })

-- ---------------------------------------------------------------------
-- Vendor. DaylightMogul's vendor parks the game's window itself.
-- ---------------------------------------------------------------------

Engine.Window({ key = "game:merchant", pack = "npc", frame = "MerchantFrame", watch = true,
    skip = function() return DaylightUI.vendorMogul == true or covered("merchant") end,
    after = function(Kit, f)
        for i = 1, 4 do Kit.Tab(g("MerchantFrameTab" .. i)) end
        local function item(prefix)
            if not g(prefix) then return end
            Kit.Item(g(prefix .. "ItemButton"))
            Kit.Hide(g(prefix .. "SlotTexture"))
            Kit.Hide(g(prefix .. "NameFrame"))
            Kit.Font(g(prefix .. "Name"), nil, Kit.TEXT)
        end
        for i = 1, 12 do item("MerchantItem" .. i) end
        item("MerchantBuyBackItem")
        Kit.PageButton(g("MerchantPrevPageButton"), "left")
        Kit.PageButton(g("MerchantNextPageButton"), "right")
        Kit.Dropdown(f.FilterDropdown or g("MerchantFrameFilterDropdown"))
        for _, n in ipairs({ "MerchantMoneyInset", "MerchantExtraCurrencyInset" }) do Kit.Inset(g(n)) end
        for _, n in ipairs({ "MerchantMoneyBg", "MerchantExtraCurrencyBg" }) do Kit.Hide(g(n)) end
        Kit.Light(g("MerchantPageText"), Kit.DIM)
    end })
