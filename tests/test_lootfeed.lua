local stub = require("stub")

-- The loot feed (QoL/LootFeed.lua): your loot and money as ribbons at the
-- bottom right, read from the game's own loot lines.

local SILK = "|cffffffff|Hitem:4337::::::::1:::::::|h[Tough Spider Silk]|h|r"
local FANG = "|cff1eff00|Hitem:2858::::::::1:::::::|h[Large Spider Fang]|h|r"

local function world()
    _G.LOOT_ITEM_SELF = "You receive loot: %s."
    _G.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
    _G.LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
    _G.LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
    _G.LOOT_ITEM_CREATED_SELF = "You create: %s."
    _G.LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %sx%d."
    _G.LOOT_ITEM = "%s receives loot: %s."
    _G.SKILL_RANK_UP = "Your skill in %s has increased to %d."
    _G.GetMoney = function() return _G.TEST_MONEY or 0 end
    _G.YOU_LOOT_MONEY = "You loot %s"
    _G.LOOT_MONEY_SPLIT = "Your share of the loot is %s."
    _G.GOLD_AMOUNT, _G.SILVER_AMOUNT, _G.COPPER_AMOUNT = "%d Gold", "%d Silver", "%d Copper"
    C_Item = C_Item or {}
    C_Item.GetItemInfo = function(link)
        if link:find("4337") then return "Tough Spider Silk", link, 1, 20, 0, "", "", 20, "", 132886 end
        if link:find("2858") then return "Large Spider Fang", link, 2, 20, 0, "", "", 20, "", 133723 end
        if link:find("12784") then return "Arcanite Reaper", link, 4, 63, 0, "", "", 1, "", 135562 end
    end
end

local function login(on)
    stub.Load({ qol = true, before = world })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    if on ~= nil then DaylightUI:Set("QoL", "lootFeed", on) end
    return stub.qol.LootFeed
end

local function settle()
    local d = DaylightUI.Motion.Driver()
    for _ = 1, 120 do
        if not (d and d:GetScript("OnUpdate")) then return end
        stub.RunOnUpdate(d, 1 / 60)
    end
end

local function loot(text) stub.FireEvent("CHAT_MSG_LOOT", text, "", "", "", "", "", 0, 0, "", 0, 1, "Player-1", 0) end
local function money(text) stub.FireEvent("CHAT_MSG_MONEY", text, "", "", "", "", "", 0, 0, "", 0, 1, "Player-1", 0) end

local function live(F)
    local out = {}
    for _, r in ipairs(F.Rows()) do if not r.leaving then out[#out + 1] = r end end
    return out
end

T.test("loot feed: on by default, the option and preview are on its own QoL page", function()
    login()
    T.eq(DaylightUI:Get("QoL", "lootFeed"), true)
    local page = DaylightUI.Options.GetPage("QoL.loot")
    local found = false
    for _, g in ipairs(page.groups) do
        for _, item in ipairs(g.items) do if item.key == "lootFeed" then found = true end end
    end
    T.truthy(found, "the toggle is on the page")
    T.truthy(DaylightUI.Movers.Get("qol.loot"), "it has an unlock handle")
end)

T.test("loot feed: the game's lines are read in their own words", function()
    local F = login()
    T.eq(F.ParseItem("You receive loot: " .. SILK .. "."), SILK)
    local link, n = F.ParseItem("You receive loot: " .. SILK .. "x3.")
    T.eq(link, SILK) T.eq(n, 3)
    T.eq(F.ParseItem("You receive item: " .. FANG .. "."), FANG, "a quest reward or a buy")
    T.isnil(F.ParseItem("Bob receives loot: " .. SILK .. "."), "someone else's loot")
    T.eq(F.ParseMoney("You loot 1 Silver, 24 Copper"), 124)
    T.eq(F.ParseMoney("Your share of the loot is 2 Gold, 3 Copper."), 20003)
    T.isnil(F.ParseMoney("Bob loots 5 Copper"))
    T.isnil(F.ParseItem(stub.Secret("You receive loot: " .. SILK .. ".")), "a secret line is skipped")
end)

T.test("loot feed: a loot slides in as a ribbon, its name in its quality color", function()
    local F = login()
    loot("You receive loot: " .. FANG .. ".")
    local rows = live(F)
    T.eq(#rows, 1)
    T.truthy(_G.DaylightUILootFeed:IsShown())
    local r = rows[1]
    T.eq(r.name:GetText(), "Large Spider Fang")
    T.eq(r.count:GetText(), "", "one: no count")
    T.near(select(2, r.name:GetTextColor()), select(2, DaylightUI.Win.Parts.QualityColor(2)), 0.001)
    T.eq(r.icon:GetTexture(), 133723)
end)

T.test("loot feed: more of the same adds to its count; money adds up on one ribbon", function()
    local F = login()
    loot("You receive loot: " .. SILK .. ".")
    loot("You receive loot: " .. FANG .. ".")
    loot("You receive loot: " .. SILK .. "x2.")
    money("You loot 1 Silver, 24 Copper")
    money("You loot 3 Copper")
    local rows = live(F)
    T.eq(#rows, 3, "silk, fang, money")
    local silk, coin
    for _, r in ipairs(rows) do
        if r.entry.name == "Tough Spider Silk" then silk = r end
        if r.entry.money then coin = r end
    end
    T.eq(silk.count:GetText(), "x3")
    T.eq(coin.entry.money, 127)
    T.near(select(1, silk.count:GetTextColor()), select(1, DaylightUI.Style.Accent()), 0.001, "the count pops")
end)

T.test("loot feed: one item with different suffixes gets a ribbon each", function()
    local F = login()
    loot("You receive loot: |cff1eff00|Hitem:15248::::::1018:::::::::|h[Gleaming Claymore of the Monkey]|h|r.")
    loot("You receive loot: |cff1eff00|Hitem:15248::::::1017:::::::::|h[Gleaming Claymore of Agility]|h|r.")
    loot("You receive loot: |cff1eff00|Hitem:15248::::::1018:::::::::|h[Gleaming Claymore of the Monkey]|h|r.")
    local rows = live(F)
    T.eq(#rows, 2, "Monkey and Agility apart")
    local monkey
    for _, r in ipairs(rows) do
        if r.entry.name == "Gleaming Claymore of the Monkey" then monkey = r end
    end
    T.eq(monkey.count:GetText(), "x2")
end)

T.test("loot feed: newest at the bottom, older ones above", function()
    local F = login()
    loot("You receive loot: " .. SILK .. ".")
    loot("You receive loot: " .. FANG .. ".")
    local rows = live(F)
    T.eq(rows[1].entry.name, "Large Spider Fang", "newest first in the list")
    T.eq(rows[1].y, 0, "at the bottom")
    T.eq(rows[2].y, F.ROW_H + F.GAP, "the older one a step up")
end)

T.test("loot feed: a ribbon leaves after a few seconds, a new loot keeps it", function()
    local F = login()
    loot("You receive loot: " .. SILK .. ".")
    stub.Advance(F.HOLD - 1)
    loot("You receive loot: " .. SILK .. ".")
    stub.Advance(F.HOLD - 1)
    F.Tick()
    T.eq(#live(F), 1, "still up: the second loot started its time again")
    stub.Advance(2)
    F.Tick()
    settle()
    T.eq(#F.Rows(), 0, "gone")
    F.Tick()
    T.falsy(_G.DaylightUILootFeed:IsShown(), "the holder rests")
end)

T.test("loot feed: never more than its rows at once", function()
    local F = login()
    for i = 1, F.MAX + 2 do
        loot("You receive loot: |cffffffff|Hitem:" .. (100 + i) .. "::|h[Thing " .. i .. "]|h|r.")
    end
    T.eq(#live(F), F.MAX)
end)

T.test("loot feed: switched off, nothing shows", function()
    local F = login(false)
    loot("You receive loot: " .. SILK .. ".")
    T.eq(#F.Rows(), 0)
end)

T.test("loot feed: unlock mode shows the sample, locking lets it go", function()
    local F = login()
    DaylightUI.Movers.unlocked = true
    DaylightUI.Fire("UnlockChanged")
    T.eq(#live(F), #F.SAMPLE)
    DaylightUI.Movers.unlocked = false
    DaylightUI.Fire("UnlockChanged")
    settle()
    T.eq(#F.Rows(), 0)
end)

T.test("loot feed: works in a fight and in chat lockdown", function()
    local F = login()
    stub.EnterCombat()
    stub.SetRestriction("Chat", true)
    loot("You receive loot: " .. SILK .. ".")
    money("You loot 5 Copper")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    stub.SetRestriction("Chat", false)
    stub.LeaveCombat()
    T.truthy(#live(F) <= 2)
end)

T.test("loot feed: pointing at a ribbon shows the item and keeps the feed up", function()
    local F = login()
    loot("You receive loot: " .. SILK .. ".")
    local r = live(F)[1]
    _G.GameTooltip = _G.GameTooltip or CreateFrame("GameTooltip", "GameTooltip", UIParent)
    local linked
    local owner
    GameTooltip.SetOwner = function(_, o) owner = o end
    GameTooltip.GetOwner = function() return owner end
    GameTooltip.SetHyperlink = function(_, link) linked = link end
    r:GetScript("OnEnter")(r)
    T.eq(linked, SILK, "the item's own tooltip")
    T.eq(GameTooltip:GetOwner(), r)
    stub.Advance(F.HOLD + 10)
    F.Tick()
    T.eq(#live(F), 1, "nothing leaves while pointed at")
    r:GetScript("OnLeave")(r)
    T.falsy(GameTooltip:IsShown(), "the tooltip goes")
    F.Tick()
    T.eq(#live(F), 1, "a moment's grace after the mouse leaves")
    stub.Advance(F.GRACE + 0.1)
    F.Tick()
    T.eq(#live(F), 0, "then it goes")
end)

T.test("loot feed: how long a ribbon stays is a setting", function()
    local F = login()
    DaylightUI:Set("QoL", "lootFeedHold", 12)
    loot("You receive loot: " .. SILK .. ".")
    stub.Advance(10)
    F.Tick()
    T.eq(#live(F), 1, "still up at 10 s")
    stub.Advance(3)
    F.Tick()
    T.eq(#live(F), 0, "gone after 12 s")
end)

T.test("loot feed: crafted items show, one or many", function()
    local F = login(true)
    T.eq(select(2, F.ParseItem("You create: " .. SILK .. "x3.")), 3)
    loot("You create: " .. FANG .. ".")
    loot("You create: " .. SILK .. "x3.")
    settle()
    local rows = live(F)
    T.eq(#rows, 2, "fang and silk")
    T.eq(rows[1].entry.count, 3, "the stack's count")
end)

T.test("loot feed: money shows the moment it lands, its late chat line isn't counted twice", function()
    _G.TEST_MONEY = 1000
    local F = login(true)
    stub.FireEvent("LOOT_OPENED")
    _G.TEST_MONEY = 1124
    stub.FireEvent("PLAYER_MONEY")
    local rows = live(F)
    T.eq(#rows, 1, "money up before the chat line")
    T.eq(rows[1].entry.money, 124)
    stub.FireEvent("LOOT_CLOSED")
    money("You loot 1 Silver, 24 Copper")
    T.eq(live(F)[1].entry.money, 124, "the chat line for the same coins adds nothing")
    -- A group split: the chat line first, then the money; still counted once.
    money("Your share of the loot is 5 Copper.")
    _G.TEST_MONEY = 1129
    stub.FireEvent("PLAYER_MONEY")
    T.eq(live(F)[1].entry.money, 129)
    -- Selling to a vendor (no loot window) stays quiet.
    stub.Advance(10)
    _G.TEST_MONEY = 5000
    stub.FireEvent("PLAYER_MONEY")
    T.eq(live(F)[1].entry.money, 129, "not loot")
    _G.TEST_MONEY = nil
end)

local function skill(text) stub.FireEvent("CHAT_MSG_SKILL", text, "", "", "", "", "", 0, 0, "", 0, 1, "", 0) end

T.test("loot feed: a skill-up gets its own ribbon, more of them move it on", function()
    local F = login()
    _G.GetNumSkillLines = function() return 2 end
    _G.GetSkillLineInfo = function(i)
        if i == 1 then return "Professions", true end
        return "Tailoring", false, nil, 152, 0, 0, 225
    end
    local name, rank = F.ParseSkill("Your skill in Tailoring has increased to 152.")
    T.eq(name, "Tailoring") T.eq(rank, 152)
    T.isnil(F.ParseSkill("You receive loot: " .. SILK .. "."))
    T.isnil(F.ParseSkill(stub.Secret("Your skill in Tailoring has increased to 152.")), "a secret line is skipped")
    skill("Your skill in Tailoring has increased to 152.")
    skill("Your skill in Tailoring has increased to 153.")
    T.truthy(live(F)[1].count:GetText():find("^152"), "the number counts up from the old rank")
    settle()
    local rows = live(F)
    T.eq(#rows, 1, "one ribbon for the skill")
    T.eq(rows[1].name:GetText(), "Tailoring")
    T.truthy(rows[1].count:GetText():find("^153"), "the new rank")
    T.truthy(rows[1].count:GetText():find("225", 1, true), "out of its cap")
    T.near(select(1, rows[1].count:GetTextColor()), select(1, DaylightUI.Style.Accent()), 0.001, "the rank pops")
    _G.GetNumSkillLines, _G.GetSkillLineInfo = nil, nil
    DaylightUI:Set("QoL", "lootFeedSkills", false)
    skill("Your skill in Swords has increased to 40.")
    T.eq(#live(F), 1, "skill-ups switched off")
end)

T.test("loot feed: a weapon skill shows your weapon, Defense your shield", function()
    local F = login()
    local gear = {
        [16] = { 501, "One-Handed Maces", 2, 4 },
        [17] = { 502, "Shields", 4, 6 },
        [18] = { 503, "Bows", 2, 2 },
    }
    _G.GetInventoryItemID = function(_, slot) return gear[slot] and gear[slot][1] end
    _G.GetInventoryItemTexture = function(_, slot) return gear[slot] and ("gear:" .. slot) end
    local instant = C_Item.GetItemInfoInstant
    C_Item.GetItemInfoInstant = function(id)
        for _, g in pairs(gear) do
            if g[1] == id then return id, "", g[2], "", "x", g[3], g[4] end
        end
    end
    T.eq(F.SkillOf("Maces", 10).icon, "gear:16", "the mace in your hand")
    T.eq(F.SkillOf("Bows", 10).icon, "gear:18", "the bow")
    T.eq(F.SkillOf("Defense", 10).icon, "gear:17", "the shield")
    T.eq(F.SkillOf("Two-Handed Maces", 10).icon, F.SKILL_ICON, "a one-handed mace isn't a two-handed one")
    gear[16] = { 504, "Two-Handed Maces", 2, 5 }
    T.eq(F.SkillOf("Two-Handed Maces", 10).icon, "gear:16", "an exact kind")
    gear[17] = nil
    T.eq(F.SkillOf("Defense", 10).icon, F.SHIELD_ICON, "no shield: a plain one")
    C_Item.GetItemInfoInstant, _G.GetInventoryItemID = instant, nil
    _G.GetInventoryItemTexture = function(_, slot) return "tex:" .. tostring(slot) end
end)

T.test("loot feed: items, money and low qualities can be left out", function()
    local F = login()
    DaylightUI:Set("QoL", "lootFeedQuality", "uncommon")
    loot("You receive loot: " .. SILK .. ".")
    loot("You receive loot: " .. FANG .. ".")
    T.eq(#live(F), 1, "the white silk left out")
    DaylightUI:Set("QoL", "lootFeedMoney", false)
    money("You loot 5 Copper")
    T.eq(#live(F), 1, "no money")
    DaylightUI:Set("QoL", "lootFeedItems", false)
    loot("You receive loot: " .. FANG .. "x2.")
    T.eq(live(F)[1].entry.count, 1, "no items")
end)

T.test("loot feed: max shown, grow direction and leaving together are settings", function()
    local F = login()
    DaylightUI:Set("QoL", "lootFeedMax", 2)
    for i = 1, 4 do loot("You receive loot: |cffffffff|Hitem:" .. (100 + i) .. "::|h[Thing " .. i .. "]|h|r.") end
    T.eq(#live(F), 2)
    settle()
    DaylightUI:Set("QoL", "lootFeedGrow", "down")
    local p = { live(F)[1]:GetPoint(1) }
    T.eq(p[1], "TOPRIGHT", "newest on top")
    DaylightUI:Set("QoL", "lootFeedTogether", true)
    stub.Advance(F.HOLD - 2)
    loot("You receive loot: |cffffffff|Hitem:104::|h[Thing 4]|h|r.")
    stub.Advance(3)
    F.Tick()
    T.eq(#live(F), 2, "the older line waits for the newest")
    stub.Advance(F.HOLD)
    F.Tick()
    T.eq(#live(F), 0, "then they go together")
end)

T.test("loot feed: flipped, it mirrors left and right, and back again", function()
    local F = login()
    local Style, Motion = DaylightUI.Style, DaylightUI.Motion
    local slide, sweep = Motion.SlideIn, Motion.Sweep
    local slid, swept
    Motion.SlideIn = function(f, dx, ...) slid = dx return slide(f, dx, ...) end
    Motion.Sweep = function(t, o, opts) swept = opts return sweep(t, o, opts) end
    DaylightUI:Set("QoL", "lootFeedFlip", true)
    loot("You receive loot: " .. SILK .. "x2.")
    T.eq(slid, -F.SLIDE, "slides in from the left")
    T.truthy(swept.reverse, "the light runs the other way")
    Motion.SlideIn, Motion.Sweep = slide, sweep
    settle()
    local r = live(F)[1]
    local p = { r:GetPoint(1) }
    T.eq(p[1], "BOTTOMLEFT", "lined up on the left") T.eq(p[3], "BOTTOMLEFT")
    T.eq(Style.GetSlant(r).under, "right", "the ends lean the other way")
    T.eq((r.edge:GetPoint(1)), "RIGHT", "the icon at the right end")
    local n = { r.name:GetPoint(1) }
    T.eq(n[1], "LEFT") T.eq(n[2], r, "the name from the left end")
    T.eq((r.count:GetPoint(1)), "LEFT", "the count still after the name")
    -- It leaves to the right.
    stub.Advance(F.HOLD + 1)
    F.Tick()
    T.truthy(r.leaving)
    stub.RunOnUpdate(Motion.Driver(), 0.1)
    T.truthy(select(4, r:GetPoint(1)) > 0, "drifts right as it fades")
    settle()
    -- A ribbon already showing goes back with the setting.
    loot("You receive loot: " .. FANG .. ".")
    settle()
    r = live(F)[1]
    DaylightUI:Set("QoL", "lootFeedFlip", false)
    settle()
    T.eq((r:GetPoint(1)), "BOTTOMRIGHT", "back on the right")
    T.eq(Style.GetSlant(r).under, "left")
    T.eq((r.edge:GetPoint(1)), "LEFT")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("loot feed: the tooltip opens away from the edge the feed lines up on", function()
    local F = login()
    DaylightUI:Set("QoL", "lootFeedFlip", true)
    loot("You receive loot: " .. SILK .. ".")
    local r = live(F)[1]
    _G.GameTooltip = _G.GameTooltip or CreateFrame("GameTooltip", "GameTooltip", UIParent)
    local anchor
    GameTooltip.SetOwner = function(_, _, a) anchor = a end
    GameTooltip.SetHyperlink = function() end
    r:GetScript("OnEnter")(r)
    T.eq(anchor, "ANCHOR_RIGHT")
    r:GetScript("OnLeave")(r)
end)

T.test("loot feed: background, border and its color follow the settings", function()
    local F = login()
    loot("You receive loot: " .. FANG .. ".")
    local r = live(F)[1]
    T.isnil(r.shell.opts.borderColor, "our border by default")
    DaylightUI:Set("QoL", "lootFeedBorderColor", "quality")
    T.near(r.shell.opts.borderColor[2], select(2, DaylightUI.Win.Parts.QualityColor(2)), 0.001, "the item's quality")
    DaylightUI:Set("QoL", "lootFeedBorderColor", "custom")
    DaylightUI:Set("QoL", "lootFeedBorderCustom", { 0.1, 0.9, 0.2 })
    T.eq(r.shell.opts.borderColor[2], 0.9, "the player's own")
    DaylightUI:Set("QoL", "lootFeedBack", false)
    DaylightUI:Set("QoL", "lootFeedBorder", false)
    T.truthy(r.shell.opts.noBackground) T.truthy(r.shell.opts.noBorder)
    -- Nothing of the ribbon left: no bevel lines, no shadow (seen in game).
    T.falsy(r.shell.bevelBottom:IsShown(), "no bevel line without a background")
    T.eq(r.shell.opts.shadowAlpha, 0, "no shadow without border or background")
    DaylightUI:Set("QoL", "lootFeedNameColor", "white")
    T.near(select(1, r.name:GetTextColor()), DaylightUI.Style.INK.VALUE[1], 0.001)
    DaylightUI:Set("QoL", "lootFeedTextSize", 16)
    T.eq(select(2, r.name:GetFont()), 16 * DaylightUI:Get("general", "fontScale"))
end)

T.test("loot feed: follows the General Scale slider", function()
    login()
    local DUI = DaylightUI
    local holder = _G.DaylightUILootFeed
    T.truthy(holder, "built")
    DUI:Set("general", "scale", 1.4)
    stub.RunTimers()
    T.near(holder:GetScale(), 1.4)
    loot(SILK)
    settle()
    T.near(holder:GetScale(), 1.4, 1e-6, "still after a ribbon")
    T.near(holder:GetEffectiveScale() / UIParent:GetEffectiveScale(), 1.4)
end)

T.test("loot feed: angled ends can be turned off (straight ribbons, narrower)", function()
    local F = login()
    loot("You receive loot: " .. FANG .. ".")
    local r = live(F)[1]
    T.truthy(DaylightUI.Style.GetSlant(r).cut > 0, "angled by default")
    local w = r:GetWidth()
    DaylightUI:Set("QoL", "lootFeedSlant", false)
    T.eq(DaylightUI.Style.GetSlant(r).cut, 0, "straight ends")
    T.truthy(r:GetWidth() < w, "no room kept for the cut")
    DaylightUI:Set("QoL", "lootFeedSlant", true)
    T.truthy(DaylightUI.Style.GetSlant(r).cut > 0, "angled again")
end)

T.test("loot feed: angled on one end only, either side, the other straight", function()
    local F = login()
    loot("You receive loot: " .. FANG .. ".")
    local r = live(F)[1]
    local Style = DaylightUI.Style
    local w = r:GetWidth()
    T.eq(Style.GetSlant(r).side, "both", "both ends by default")
    DaylightUI:Set("QoL", "lootFeedSlantSide", "right")
    local sl = Style.GetSlant(r)
    T.eq(sl.side, "right", "the right end alone"); T.isnil(sl.under, "top corner out, as in the pair")
    T.truthy(r:GetWidth() < w, "no room kept for the straight end")
    DaylightUI:Set("QoL", "lootFeedSlantSide", "left")
    sl = Style.GetSlant(r)
    T.eq(sl.side, "left"); T.eq(sl.under, "left", "leaning under, as in the pair")
    DaylightUI:Set("QoL", "lootFeedSlantSide", "both")
    T.eq(Style.GetSlant(r).side, "both")
    T.near(r:GetWidth(), w, 0.5, "as wide as before")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

local REAPER = "|cffa335ee|Hitem:12784::::::::60:::::::|h[Arcanite Reaper]|h|r"

T.test("loot feed: an epic arrives with a burst and a flash on its edge; others don't", function()
    local F = login()
    loot("You receive loot: " .. FANG .. ".")
    local fang = live(F)[1]
    T.falsy(fang.burst:IsShown(), "an uncommon has no burst")
    T.isnil(fang.shell.opts.borderColor, "nor a flash")
    loot("You receive loot: " .. REAPER .. ".")
    local r = live(F)[1]
    T.eq(r.name:GetText(), "Arcanite Reaper")
    T.truthy(r.burst:IsShown(), "the burst spreads from the icon")
    local c = r.shell.opts.borderColor
    local q = { DaylightUI.Win.Parts.QualityColor(4) }
    T.truthy(type(c) == "table" and c[1] >= q[1] and c[2] >= q[2] and c[3] >= q[3], "the edge flashes in its color, lifted")
    settle()
    T.falsy(r.burst:IsShown(), "the burst is gone")
    T.isnil(r.shell.opts.borderColor, "the edge is back to the border setting")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The flash eases all the way to the border it settles on: no snap from the
-- item's color to the border setting at its end.
T.test("loot feed: an epic's edge flash eases into the border setting", function()
    local F = login()
    local Style = DaylightUI.Style
    local set, last = Style.SetShellColors, nil
    Style.SetShellColors = function(s, border, ...)
        if border then last = border end
        return set(s, border, ...)
    end
    loot("You receive loot: " .. REAPER .. ".")
    settle()
    Style.SetShellColors = set
    local b = Style.BORDER
    T.truthy(last and math.abs(last[1] - b[1]) < 0.01 and math.abs(last[2] - b[2]) < 0.01 and math.abs(last[3] - b[3]) < 0.01,
        "the flash ends on the border's own color")
    T.isnil(live(F)[1].shell.opts.borderColor)
end)

T.test("loot feed: with Motion effects off an epic just shows", function()
    local F = login()
    DaylightUI:Set("general", "motion", false)
    loot("You receive loot: " .. REAPER .. ".")
    local r = live(F)[1]
    T.falsy(r.burst:IsShown(), "no burst")
    T.isnil(r.shell.opts.borderColor, "no flash")
    DaylightUI:Set("general", "motion", true)
end)

T.test("loot feed: the coin shows the biggest coin in the amount", function()
    local F = login()
    money("You loot 5 Copper")
    local coin = live(F)[1]
    T.eq(coin.icon:GetTexture(), stub.COIN_ICONS.copper, "copper only: a copper coin")
    money("You loot 1 Silver")
    T.eq(live(F)[1].icon:GetTexture(), stub.COIN_ICONS.silver, "past a silver: a silver coin")
    money("You loot 1 Gold")
    T.eq(live(F)[1].icon:GetTexture(), stub.COIN_ICONS.gold, "past a gold: a gold coin")
end)
