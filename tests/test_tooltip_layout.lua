local stub = require("stub")

-- The Rich card's layout: the pieces of each card in sections the player can
-- rearrange (Rich/Layout.lua), the Tooltips page's Design mode (Rich/Design.lua)
-- and the options that go with it.

local post = {}

-- A tooltip's lines as the game keeps them: <name>TextLeft<i> and Right.
local function lined(tip)
    local name = tip:GetName()
    tip.__n = 0
    local function line(side, i)
        local key = name .. "Text" .. side .. i
        _G[key] = _G[key] or tip:CreateFontString(key)
        return _G[key]
    end
    function tip:NumLines() return self.__n end
    function tip:ClearLines()
        for i = 1, self.__n do
            for _, side in ipairs({ "Left", "Right" }) do
                local fs = line(side, i)
                fs:SetText(nil)
                fs.__secretAspect = nil
            end
        end
        self.__n = 0
    end
    function tip:AddDoubleLine(l, r, lr, lg, lb, rr, rg, rb)
        self.__n = self.__n + 1
        local left, right = line("Left", self.__n), line("Right", self.__n)
        left:SetText(l); left:SetTextColor(lr or 1, lg or 1, lb or 1)
        right:SetText(r); right:SetTextColor(rr or 1, rg or 1, rb or 1)
    end
    function tip:AddLine(t, r, g, b) self:AddDoubleLine(t, nil, r, g, b) end
    function tip:SetOwner(owner, anchor)
        self.__owner, self.__anchor = owner, anchor
        self:ClearLines()
        local cleared = self:GetScript("OnTooltipCleared")
        if cleared then cleared(self) end
    end
    function tip:GetOwner() return self.__owner end
    function tip:GetAnchorType() return self.__anchor end
    stub.TooltipSizes(tip)
    return tip
end

local function world()
    post = {}
    Enum.TooltipDataType = { Item = 0, Spell = 1, Unit = 2 }
    _G.TooltipDataProcessor = {
        AllTypes = "ALL",
        AddTooltipPostCall = function(kind, fn)
            post[kind] = post[kind] or {}
            table.insert(post[kind], fn)
        end,
    }
    local tip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
    tip.NineSlice = CreateFrame("Frame", nil, tip)
    lined(tip)
    function tip:GetUnit() return self.__unitName, self.__unit end
    function tip:GetItem() return nil, self.__link end
    tip:SetScript("OnShow", function(self) self:ClearPadding() end)
    tip:SetScript("OnHide", function(self) self:ClearPadding(); GameTooltip_ClearMoney(self) end)
    tip:SetScript("OnTooltipCleared", function(self) GameTooltip_ClearMoney(self) end)
    tip:Hide()
    tip.shoppingTooltips = { lined(stub.CompareTooltip("ShoppingTooltip1")), lined(stub.CompareTooltip("ShoppingTooltip2")) }
    CreateFrame("StatusBar", "GameTooltipStatusBar", tip)
    for _, n in ipairs({ "GameTooltipHeaderText", "GameTooltipText", "GameTooltipTextSmall" }) do
        local f = stub.NewWidget("Font", n)
        function f:SetFont(file, size, flags) self.__font = { file, size, flags } end
    end
    local spot = CreateFrame("Frame", "GameTooltipDefaultContainer", UIParent)
    spot:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -100, 100)
    _G.GameTooltip_SetDefaultAnchor = function(t, parent)
        t:SetOwner(parent, "ANCHOR_NONE")
        t:ClearAllPoints()
        t:SetPoint("BOTTOMRIGHT", spot)
    end
    stub.units = {
        player = { name = "Me", class = "PRIEST", isPlayer = true },
        mouseover = { name = "Jaina", class = "MAGE", isPlayer = true },
    }
end

local GREEN, GRAY, YELLOW = { 0.1, 1, 0.1 }, { 0.5, 0.5, 0.5 }, { 1, 0.82, 0 }
local WHITE_LINE, RANK_GRAY = { 1, 1, 1 }, { 0.5, 0.5, 0.5 }

-- A new profile (Rich by default). saved: the profile's saved Tooltip table.
local function login(saved, opts)
    stub.Load({ tooltip = true, module = opts and opts.module, before = function()
        world()
        -- A saved profile from before Rich was the default is pinned to Simple.
        if saved then
            saved.style = "rich"
            _G.DaylightUIDB = { modules = { Tooltip = saved } }
        end
    end })
    return stub.tooltip
end

local function update() GameTooltip:GetScript("OnUpdate")(GameTooltip, 0.02) end
local function panel() return stub.tooltip.RichPanel.Get(GameTooltip) end

-- ---------------------------------------------------------------------
-- The fills (the snap recipes', line for line)
-- ---------------------------------------------------------------------

local function items()
    _G.ARMOR_TEMPLATE, _G.DAMAGE_TEMPLATE, _G.DPS_TEMPLATE = "%s Armor", "%s - %s Damage", "(%s damage per second)"
    _G.DURABILITY_TEMPLATE, _G.ITEM_LEVEL = "Durability %d / %d", "Item Level %d"
    _G.ITEM_SET_NAME, _G.ITEM_SET_BONUS, _G.ITEM_SET_BONUS_GRAY = "%s (%d/%d)", "Set: %s", "(%d) Set: %s"
    _G.ITEM_SPELL_TRIGGER_ONEQUIP, _G.ITEM_SPELL_TRIGGER_ONUSE = "Equip:", "Use:"
    _G.SELL_PRICE, _G.EQUIPPED, _G.ARMOR, _G.DAMAGE = "Sell Price", "Equipped", "Armor", "Damage"
    _G.ITEM_DELTA_DESCRIPTION = "If you replace this item, the following stat changes will occur:"
    _G.SHIFT_KEY_TEXT, _G.CTRL_KEY_TEXT = "Shift", "Ctrl"
    _G.INVTYPE_LEGS, _G.INVTYPE_WEAPON, _G.INVTYPE_2HWEAPON = "Legs", "One-Hand", "Two-Hand"
    stub.SetItems({
        greaves = { id = 19001, quality = 4, kind = "Armor", sub = "Plate", equip = "INVTYPE_LEGS", icon = 135000,
            class = 4, subClass = 4, level = 66, dressable = true },
        legplates = { id = 19002, quality = 3, kind = "Armor", sub = "Plate", equip = "INVTYPE_LEGS", icon = 135001,
            class = 4, subClass = 4, level = 58, dressable = true },
        cleaver = { id = 19004, quality = 4, kind = "Weapon", sub = "Axes", equip = "INVTYPE_2HWEAPON", icon = 135003,
            class = 2, level = 60 },
    })
end

local function fillItem(tip, link, list, after)
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip.__link = link
    local own = {}
    for i, t in ipairs(list) do
        if type(t) == "table" then
            local c, rc = t[3] or { 1, 1, 1 }, t[4] or { 1, 1, 1 }
            tip:AddDoubleLine(t[1], t[2], c[1], c[2], c[3], rc[1], rc[2], rc[3])
        else
            tip:AddLine(t)
        end
        -- The game's own sell price line is always a SellPrice data line (11).
        own[i] = { type = type(t) == "string" and t:sub(1, 11) == "Sell Price:" and 11 or nil }
    end
    local data = { type = Enum.TooltipDataType.Item, hyperlink = link, lines = own }
    for _, fn in ipairs(post.ALL or {}) do fn(tip, data) end
    for _, fn in ipairs(post[data.type] or {}) do fn(tip, data) end
    if after then after(tip) end
    tip:Show()
end

local EPIC = { 0.639, 0.208, 0.933 }
local GREAVES = {
    { "Dawnforged Greaves", nil, EPIC },
    "Binds when equipped",
    { "Legs", "Plate" },
    "742 Armor",
    "+24 Strength",
    "+31 Stamina",
    "Durability 98 / 100",
    "Requires Level 58",
    { "Equip: Improves your chance to get a critical strike by 1%.", nil, GREEN },
    "",
    { "Dawnforged Battlegear (2/5)", nil, YELLOW },
    { "  Dawnforged Helm", nil, GRAY },
    "  Dawnforged Greaves",
    "",
    { "Set: Increases attack power by 40.", nil, GREEN },
    { "(4) Set: 5% chance on hit to heal you for 120.", nil, GRAY },
    "Sell Price: 3|A:coin-gold:0:0|a 42|A:coin-silver:0:0|a",
}
local CLEAVER = {
    { "Ironhide Cleaver", nil, EPIC },
    "Soulbound",
    { "Two-Hand", "Axe" },
    { "46 - 86 Damage", "Speed 2.20" },
    "(30.0 damage per second)",
    "+9 Strength",
    { "Equip: +22 Attack Power.", nil, GREEN },
    "Durability 85 / 85",
    { "\"Still warm from the forge.\"", nil, YELLOW },
}

-- Other addons' lines as they write them, after the game's.
local function addonLines(t)
    t:AddLine(" ")
    t:AddDoubleLine("Auction x3", "|cffffffff4|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t 12|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t|r")
    t:AddDoubleLine("|cff82c5ffDBMarket:|r", "3|cffffd70ag|r 87|cffc7c7cfs|r 50|cffeda55fc|r")
    t:AddDoubleLine("Raider.IO M+ Score", "|cffff80002140|r")
    t:AddLine(" ")
    t:AddLine("[58] The Dawnforged Oath")
    t:AddLine("   |cffffffffDawnforged Greaves: 0/1|r |cff999999[12%]|r")
    t:AddLine(" ")
    t:AddDoubleLine("|TInterface\\Icons\\INV_Misc_Bag_08:0|t Bags: 1", "Bank: 2")
    t:AddLine("|cff999999Also on|r Aelindra, Moonvale")
end

local function player(loner)
    stub.units.mouseover = { name = "Aelindra", lastName = "Moonvale", class = "MAGE",
        isPlayer = true, level = 60, race = "Night Elf", guild = "Dawnwatch", guildRank = "Officer",
        health = 100, maxHealth = 100, power = 72, maxPower = 100, powerToken = "MANA", friend = true }
    stub.units.mouseovertarget = { name = "Gorvak", isPlayer = false, reaction = 2 }
    if loner then
        stub.units.mouseover.guild, stub.units.mouseover.guildRank, stub.units.mouseovertarget = nil, nil, nil
    end
    DaylightUI:Set("Tooltip", "buffs", true)
    stub.RunTimers()
    stub.SetAuras("mouseover", "HELPFUL", { { icon = 135932 }, { icon = 135987 }, { icon = 136078 }, { icon = 135964 } })
end

local function hoverPlayer(addon)
    local tip = GameTooltip
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip.__unit = "mouseover"
    tip:AddLine("Aelindra")
    tip:AddLine("Level 60")
    local data = { type = Enum.TooltipDataType.Unit, lines = { {}, {} } }
    for _, fn in ipairs(post.ALL or {}) do fn(tip, data) end
    for _, fn in ipairs(post[data.type] or {}) do fn(tip, data) end
    if addon then addon(tip) end
    tip:Show()
    update()
end

local function boar()
    stub.units.player.level = 22
    stub.units.mouseover = { name = "Ridgeback Boar", isPlayer = false, reaction = 2, level = 23, health = 78, pct = 78,
        maxHealth = 100, creatureType = "Beast", creatureTypeID = 1 }
    stub.units.mouseovertarget = stub.units.player
    DaylightUI.Npc.Data.QuestColor = function() return { 0.5, 0.88, 0.97 } end
end

local function hoverBoar(addon)
    local tip = GameTooltip
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip.__unit = "mouseover"
    tip:AddLine("Ridgeback Boar")
    tip:AddLine("Level 23 Beast")
    tip:AddLine("Skinnable", 1, 0.82, 0)
    tip:AddLine("Boar Hides for Farmer Rowan")
    tip:AddLine(" - 6/10 Ridgeback hide")
    tip:AddLine(" - 8/8 Boars slain")
    local data = { type = Enum.TooltipDataType.Unit,
        lines = { {}, {}, {}, { type = 17, id = 77 }, { type = 8 }, { type = 8 } } }
    for _, fn in ipairs(post.ALL or {}) do fn(tip, data) end
    for _, fn in ipairs(post[data.type] or {}) do fn(tip, data) end
    if addon then addon(tip) end
    tip:Show()
    update()
end

local function spells()
    _G.MANA, _G.DAMAGE = "Mana", "Damage"
    _G.STRING_SCHOOL_FROST = "Frost"
    Enum.TooltipDataType.UnitAura, Enum.TooltipDataType.Macro = 7, 25
    Enum.TooltipDataLineType = { SpellName = 13, SpellDescription = 34 }
    stub.spells = { [116] = { name = "Frostbolt", icon = 135846, cast = 2500, cost = 120 } }
    C_Spell.GetSpellTexture = function(id) local s = stub.spells[id]; return s and s.icon or 1 end
    C_Spell.GetSpellName = function(id) local s = stub.spells[id]; return s and s.name end
    C_Spell.GetSpellInfo = function(id)
        local s = stub.spells[id]
        return s and { name = s.name, castTime = s.cast, spellID = id }
    end
    C_Spell.GetSpellPowerCost = function(id)
        local s = stub.spells[id]
        return s and { { type = 0, name = "MANA", cost = s.cost } }
    end
    _G.GetSpellBonusDamage = function() return 40 end
    _G.GetSpellBonusHealing = function() return 40 end
    stub.SetItems({
        [20001] = { id = 20001, quality = 1, icon = 1001 },
        [20002] = { id = 20002, quality = 2, icon = 1002 },
        [20003] = { id = 20003, quality = 1, icon = 1003 },
        ["Runed Silver Rod"] = { id = 20010, quality = 1, icon = 1010 },
    })
    C_Item.GetItemCount = function() return 0 end
    _G.C_TradeSkillUI = { GetRecipeSchematic = function(id)
        if id ~= 13890 then return { reagentSlotSchematics = {} } end
        local function slot(item, n) return { reagents = { { itemID = item } }, quantityRequired = n, required = true } end
        return { reagentSlotSchematics = { slot(20001, 6), slot(20002, 4), slot(20003, 4) } }
    end }
end

local function fillSpell(id, list, owner, addon)
    local tip = GameTooltip
    tip:SetOwner(owner or UIParent, "ANCHOR_NONE")
    local own = {}
    for i, t in ipairs(list) do
        if type(t) == "table" then
            local c, rc = t[3] or WHITE_LINE, t[4] or WHITE_LINE
            tip:AddDoubleLine(t[1], t[2], c[1], c[2], c[3], rc[1], rc[2], rc[3])
        else
            tip:AddLine(t)
        end
        own[i] = {}
    end
    local data = { type = Enum.TooltipDataType.Spell, id = id, lines = own }
    for _, fn in ipairs(post.ALL or {}) do fn(tip, data) end
    for _, fn in ipairs(post[data.type] or {}) do fn(tip, data) end
    if addon then addon(tip) end
    tip:Show()
    update()
end

local FROSTBOLT = {
    { "Frostbolt", "Rank 4", WHITE_LINE, RANK_GRAY },
    { "120 Mana", "30 yd range" },
    "2.5 sec cast",
    { "Launches a bolt of frost at the enemy, causing 412 to 448 Frost damage and slowing movement speed by 40% for 9 sec.",
      nil, YELLOW },
}
local RECOVERY = {
    { "Enchanting: Enchant Weapon - Recovery" },
    "Reagents:",
    "Soul Dust (6), Large Glimmering Shard (4), Pyrite (4)",
    { "Permanently enchant a Melee Weapon to trigger Recovery when you are Parried or Dodged.", nil, YELLOW },
    "Tools: Runed Silver Rod",
    "Requires Enchanting (190)",
}

local function actionButton(slot)
    local b = CreateFrame("Button", nil, UIParent)
    b.action = slot
    return b
end

local function compareFill()
    fillItem(GameTooltip, "greaves", GREAVES)
    update()
    local tip = ShoppingTooltip1
    tip:SetOwner(GameTooltip, "ANCHOR_NONE")
    tip.CompareHeader:Show()
    tip.CompareHeader.Label:SetText("Equipped")
    fillItem(tip, "legplates", { { "Tarnished Legplates", nil, { 0, 0.439, 0.867 } }, { "Legs", "Plate" }, "646 Armor",
        "+16 Strength", "Durability 50 / 100" }, function(t)
        t:AddLine(" ")
        t:AddLine(ITEM_DELTA_DESCRIPTION, 1, 0.82, 0)
        for _, c in ipairs({ "+8 Strength", "+11 Stamina", "-96 Armor" }) do t:AddLine(c) end
    end)
    tip:GetScript("OnUpdate")(tip, 0.02)
    return stub.tooltip.RichPanel.Get(tip)
end

-- Each fill: makes the world, fills the tooltip, returns the panel.
local FILLS = {
    { "player", function() player(); hoverPlayer() end },
    { "loner", function() player(true); hoverPlayer() end },
    { "player addons", function() player(); hoverPlayer(function(t) t:AddDoubleLine("Raider.IO M+ Score", "2140") end) end },
    { "mob", function() boar(); hoverBoar() end },
    { "mob addons", function() boar(); hoverBoar(function(t) t:AddLine("Pet: Boar tamed"); t:AddLine("[22] Hide and Seek"); t:AddLine("   |cffffffffBoar tusk: 1/4|r") end) end },
    { "item", function() items(); fillItem(GameTooltip, "greaves", GREAVES); update() end },
    { "item addons", function() items(); fillItem(GameTooltip, "greaves", GREAVES, addonLines); update() end },
    { "weapon", function() items(); fillItem(GameTooltip, "cleaver", CLEAVER); update() end },
    { "compare", function() items(); return compareFill() end },
    { "spell", function() spells(); fillSpell(116, FROSTBOLT) end },
    { "spell addons", function() spells(); fillSpell(116, FROSTBOLT, nil, function(t) t:AddLine("Rotation helper: cast first") end) end },
    { "cooldown", function()
        spells()
        stub.ActionSlots({ [5] = { spellID = 116, cooldown = true, cdStart = GetTime() - 5.8, cdDuration = 10,
            charges = true, chargesNow = 1, chargesMax = 2 } })
        fillSpell(116, FROSTBOLT, actionButton(5))
    end },
    { "recipe", function() spells(); fillSpell(13890, RECOVERY) end },
}

-- A card as one line per piece: its kind, its y, and its words.
local function words(item)
    local fs = item.fs or item.title or item.label
    local t = fs and stub.Text(fs)
    if type(t) ~= "string" then return "" end
    return (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", ""):sub(1, 24))
end
local function shape(p)
    local out = {}
    for i = 1, p.count do
        local item = p.items[i]
        out[i] = string.format("%s %d %s", item.kind, math.floor((item.y or 0) + 0.5), words(item))
    end
    return out
end

local function run(fill)
    login()
    stub.RunTimers()
    local p = fill[2]() or panel()
    return p
end

-- Today's cards, recorded before the layout existed: the default layout must
-- draw every one piece for piece, at the same spots.
local BEFORE = {
    ["player"] = {
        "header 14 Aelindra Moonvale",
        "gap 58 ",
        "row 74 Guild",
        "row 95 Targeting",
        "gap 111 ",
        "bar 123 ",
        "gap 130 ",
        "bar 133 ",
        "gap 137 ",
        "icons 149 ",
    },
    ["loner"] = {
        "header 14 Aelindra Moonvale",
        "gap 58 ",
        "gap 74 ",
        "bar 86 ",
        "gap 93 ",
        "bar 96 ",
        "gap 100 ",
        "icons 112 ",
    },
    ["player addons"] = {
        "header 14 Aelindra Moonvale",
        "gap 58 ",
        "row 74 Guild",
        "row 95 Targeting",
        "gap 111 ",
        "bar 123 ",
        "gap 130 ",
        "bar 133 ",
        "gap 137 ",
        "icons 149 ",
        "rule 171 ",
        "row 192 Raider.IO M+ Score",
    },
    ["mob"] = {
        "header 16 Ridgeback Boar",
        "gap 79 ",
        "bar 91 ",
        "rule 98 ",
        "section 119 BOAR HIDES FOR FARMER RO",
        "row 137 Ridgeback hide",
        "bar 158 ",
        "row 167 Boars slain",
        "rule 183 ",
        "row 204 Targeting",
    },
    ["mob addons"] = {
        "header 16 Ridgeback Boar",
        "gap 79 ",
        "bar 91 ",
        "rule 98 ",
        "section 119 BOAR HIDES FOR FARMER RO",
        "row 137 Ridgeback hide",
        "bar 158 ",
        "row 167 Boars slain",
        "section 188 [22] HIDE AND SEEK",
        "row 206 Boar tusk",
        "bar 227 ",
        "rule 231 ",
        "row 252 Targeting",
        "rule 268 ",
        "text 288 Pet: Boar tamed",
    },
    ["item"] = {
        "header 16 Dawnforged Greaves",
        "gap 83 ",
        "line 93 742 Armor",
        "line 114 +24 Strength",
        "line 135 +31 Stamina",
        "line 156 +1% Crit",
        "rule 172 ",
        "line 189 DAWNFORGED BATTLEGEAR 2/",
        "text 209 +40 Attack Power",
        "text 229 (4) 5% chance on hit to ",
        "gap 262 ",
        "text 270 Requires Level 58",
        "rule 285 ",
        "row 302 Durability 98 / 100",
    },
    ["item addons"] = {
        "header 16 Dawnforged Greaves",
        "gap 83 ",
        "line 93 742 Armor",
        "line 114 +24 Strength",
        "line 135 +31 Stamina",
        "line 156 +1% Crit",
        "rule 172 ",
        "line 189 DAWNFORGED BATTLEGEAR 2/",
        "text 209 +40 Attack Power",
        "text 229 (4) 5% chance on hit to ",
        "gap 262 ",
        "text 270 Requires Level 58",
        "rule 285 ",
        "row 302 Auction x3",
        "row 323 DBMarket",
        "row 344 Raider.IO M+ Score",
        "rule 360 ",
        "section 376 [58] THE DAWNFORGED OATH",
        "row 394 Dawnforged Greaves 12%",
        "bar 415 ",
        "rule 419 ",
        "row 436  Bags: 1",
        "text 457 Also on Aelindra, Moonva",
        "gap 473 ",
        "row 481 Durability 98 / 100",
    },
    ["weapon"] = {
        "header 16 Ironhide Cleaver",
        "gap 83 ",
        "line 93 30.0 damage per second",
        "row 117 46 - 86 Damage",
        "line 138 +9 Strength",
        "line 159 +22 Attack Power",
        "rule 175 ",
        "text 192 \"Still warm from the for",
        "rule 207 ",
        "row 224 Durability 85 / 85",
    },
    ["compare"] = {
        "tags 16 ",
        "gap 34 ",
        "header 42 Tarnished Legplates",
        "gap 87 ",
        "line 97 646 Armor",
        "line 118 +16 Strength",
        "rule 134 ",
        "row 151 Durability 50 / 100",
        "rule 166 ",
        "section 183 IF YOU SWAP",
        "tags 201 ",
    },
    ["spell"] = {
        "header 16 Frostbolt",
        "gap 59 ",
        "tiles 71 ",
        "gap 111 ",
        "text 123 Launches a bolt of frost",
    },
    ["spell addons"] = {
        "header 16 Frostbolt",
        "gap 59 ",
        "tiles 71 ",
        "gap 111 ",
        "text 123 Launches a bolt of frost",
        "rule 196 ",
        "text 217 Rotation helper: cast fi",
    },
    ["cooldown"] = {
        "header 16 Frostbolt",
        "gap 59 ",
        "tiles 71 ",
        "gap 111 ",
        "row 123 Ready in",
        "gap 139 ",
        "bar 145 ",
        "gap 149 ",
        "row 161 Charges",
        "gap 177 ",
        "text 189 Launches a bolt of frost",
    },
    ["recipe"] = {
        "header 16 Enchant Weapon - Recover",
        "gap 59 ",
        "text 71 Permanently enchant a Me",
        "gap 125 ",
        "section 137 REAGENTS",
        "gap 150 ",
        "row 154  Soul Dust",
        "row 175  Large Glimmering Shard",
        "row 196  Pyrite",
        "row 217  Runed Silver Rod",
        "gap 233 ",
        "text 245 Requires Enchanting (190",
    },
}

T.test("the default layout draws every snap recipe's card item for item as before", function()
    for _, fill in ipairs(FILLS) do
        local p = run(fill)
        local got, want = shape(p), BEFORE[fill[1]]
        T.eq(#got, #want, fill[1] .. ": " .. table.concat(got, " / "))
        for i = 1, math.max(#got, #want) do T.eq(got[i], want[i], fill[1] .. " item " .. i) end
        T.eq(#stub.errors, 0, fill[1] .. ": " .. tostring(stub.errors[1]))
    end
end)

if os.getenv("DUMP_LAYOUT") then
    T.test("dump today's cards", function()
        local f = io.open(os.getenv("DUMP_LAYOUT"), "w")
        for _, fill in ipairs(FILLS) do
            local p = run(fill)
            f:write(string.format("    [%q] = {\n", fill[1]))
            for _, line in ipairs(shape(p)) do f:write(string.format("        %q,\n", line)) end
            f:write("    },\n")
        end
        f:close()
    end)
end

local function kinds(p)
    local out = {}
    for i = 1, p.count do out[i] = p.items[i].kind end
    return table.concat(out, " ")
end

T.test("Layout.Of repairs a layout with unknown and missing pieces", function()
    local TT = login({ layout = { mob = "quests,teleport,quests|facts" } })
    local L = TT.RichLayout
    -- The unknown piece and the repeat go; the missing ones come back at their
    -- default spots: health before quests, target after facts, addons last.
    T.eq(L.Encode(L.Of("mob")), "health|quests|facts,target|addons")
    DaylightUI:Set("Tooltip", "layout.item", "foot|numbers")
    T.eq(L.Encode(L.Of("item")), "addons,foot|numbers,stats|effects,set,facts,quote|made",
        "an older layout with only some pieces keeps its own order")
    DaylightUI:Set("Tooltip", "layout.spell", "")
    T.eq(L.Encode(L.Of("spell")), "tiles,cooldown,desc,reagents,facts|addons", "empty: the default")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("a section with nothing to show draws no line", function()
    login({ layout = { mob = "health|target|quests|facts|addons" } })
    stub.RunTimers()
    -- Nothing targeted, so the target's section is empty.
    boar()
    stub.units.mouseovertarget = nil
    hoverBoar()
    local p = panel()
    T.eq(kinds(p), "header gap bar rule section row bar row", "one line, before the quest only")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("a section starting with a bar gets a gap, not a line", function()
    login({ layout = { mob = "quests|facts,target|health|addons" } })
    stub.RunTimers()
    boar()
    hoverBoar()
    local p = panel()
    -- The quest first (no line under the header), then the target, then the
    -- bar after a gap.
    T.eq(kinds(p), "header section row bar row rule row gap bar", kinds(p))
    T.eq(p.items[p.count - 1].h, stub.tooltip.RichWorld.BEFORE_BAR)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("a card with every piece hidden is the header alone, no line, no trailing gap", function()
    local saved = { showTarget = false, buffs = false, pieces = {} }
    for kind, list in pairs({ player = { "guild", "zone", "ilvl", "health", "power", "addons" },
        mob = { "health", "quests", "facts", "addons" },
        item = { "numbers", "stats", "effects", "set", "facts", "quote", "made", "addons", "foot" },
        spell = { "tiles", "cooldown", "desc", "reagents", "facts", "addons" } }) do
        saved.pieces[kind] = {}
        for _, k in ipairs(list) do saved.pieces[kind][k] = false end
    end
    for _, name in ipairs({ "player", "mob", "item", "spell", "cooldown" }) do
        local fill
        for _, f in ipairs(FILLS) do if f[1] == name then fill = f end end
        login(saved)
        stub.RunTimers()
        local p = fill[2]() or panel()
        -- The player fill turns buffs on: off again for this card.
        if name == "player" then
            DaylightUI:Set("Tooltip", "buffs", false)
            stub.RunTimers()
            hoverPlayer()
            p = panel()
        end
        T.eq(kinds(p), "header", name .. ": " .. kinds(p))
        T.eq(#stub.errors, 0, name .. ": " .. tostring(stub.errors[1]))
    end
end)

T.test("a hidden addons piece still draws Daylight UI plugins' lines where it sits", function()
    login({ pieces = { item = { addons = false } }, layout = { item = "addons|numbers,stats|effects,set,facts,quote|made|foot" } })
    stub.RunTimers()
    local me = DaylightUI.API.For("Notes")
    me.AddTooltipLines("item", function(lines) lines.Row("Fish caught", 12) end)
    items()
    fillItem(GameTooltip, "greaves", GREAVES, function(t) t:AddDoubleLine("AH price", "9") end)
    update()
    local p = panel()
    local rows = {}
    for i = 1, p.count do
        if p.items[i].kind == "row" then rows[#rows + 1] = stub.Text(p.items[i].label) end
    end
    T.eq(rows[1], "Fish caught", "the plugin's row at the top, where the piece is")
    for _, r in ipairs(rows) do T.truthy(r ~= "AH price", "another addon's line left out") end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("late addon lines land in the moved addons piece", function()
    login({ layout = { mob = "addons|health|quests|facts,target" } })
    stub.RunTimers()
    boar()
    hoverBoar()
    local p = panel()
    T.eq(p.items[2].kind, "gap", "no addon lines yet: the bar first")
    -- Another addon adds its line once the card is up (the line count changes).
    GameTooltip:AddLine("Pet: Boar tamed")
    update()
    p = panel()
    T.eq(p.items[2].kind, "text", "its line right under the header: " .. kinds(p))
    T.eq(stub.Text(p.items[2].fs), "Pet: Boar tamed")
    T.eq(p.items[3].kind, "gap", "the bar's gap after it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("under a restriction the laid-out mob card builds from the unit; a secret line gives the frame only", function()
    login({ layout = { mob = "facts,target|quests|health|addons" } })
    stub.RunTimers()
    stub.units.mouseover = { name = "Krol'dok Brute", isPlayer = false, reaction = 2, level = 41,
        classification = "elite", health = 87, maxHealth = 100 }
    stub.units.mouseovertarget = stub.units.player
    stub.SetRestriction("Map", true)
    local tip = GameTooltip
    GameTooltip_SetDefaultAnchor(tip, UIParent)
    tip.__unit = stub.Secret("mouseover")
    tip:AddLine("Krol'dok Brute")
    tip:AddLine("Level 41 (Elite)")
    GameTooltipTextLeft1:SetText(stub.Secret("Krol'dok Brute"))
    GameTooltipTextLeft2:SetText(stub.Secret("Level 41 (Elite)"))
    local data = { type = Enum.TooltipDataType.Unit, lines = { { type = 0 }, { type = 0 },
        { type = 17, leftText = "Brute Force", id = 9 }, { type = 8, leftText = stub.Secret(" - 2/8 Brutes slain") } } }
    for _, fn in ipairs(post.ALL or {}) do fn(tip, data) end
    for _, fn in ipairs(post[Enum.TooltipDataType.Unit] or {}) do fn(tip, data) end
    tip:Show()
    update()
    local p = panel()
    T.falsy(p.chrome, "the whole card")
    T.eq(p.kind, "mob")
    T.eq(kinds(p), "header row rule section line gap bar", "target, the quest from the data, then the bar: " .. kinds(p))
    -- An item with a secret line (a unit's is built from the unit): the
    -- frame only, the layout skipped.
    stub.SetRestriction("Map", false)
    DaylightUI:Set("Tooltip", "layout.item", "foot|addons|numbers,stats|effects,set,facts,quote|made")
    stub.RunTimers()
    items()
    fillItem(GameTooltip, "greaves", GREAVES, function() GameTooltipTextLeft4:SetText(stub.Secret("742 Armor")) end)
    update()
    T.truthy(panel().chrome, "the frame only")
    T.eq(GameTooltipTextLeft4:GetAlpha(), 1, "the game's own lines show")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("Layout.Move and Step: a drop on a line starts a section, an emptied section closes", function()
    local L = login().RichLayout
    local all = setmetatable({}, { __index = function() return true end })
    local lay = L.Decode("guild,zone,ilvl,target|health,power,buffs|addons")
    local slots = L.Slots(lay, "zone", all)
    T.truthy(slots[1].new and slots[1].section == 1, "a line above the first section")
    -- Dropped on the line between the two sections: a section of its own.
    local line
    for _, s in ipairs(slots) do if s.new and s.section == 2 then line = s end end
    T.eq(L.Encode(L.Move(lay, "zone", line, all)), "guild,ilvl,target|zone|health,power,buffs|addons")
    -- addons, alone in its section, moved into the first: its section closes.
    local into
    for _, s in ipairs(L.Slots(lay, "addons", all)) do
        if not s.new and s.section == 1 and s.index == 1 then into = s end
    end
    T.eq(L.Encode(L.Move(lay, "addons", into, all)), "guild,addons,zone,ilvl,target|health,power,buffs")
    -- One step at a time.
    T.eq(L.Encode(L.Step(lay, "zone", -1, all)), "zone,guild,ilvl,target|health,power,buffs|addons", "past guild")
    T.eq(L.Encode(L.Step(L.Step(lay, "zone", -1, all), "zone", -1, all)), "zone|guild,ilvl,target|health,power,buffs|addons",
        "then a line of its own")
    T.isnil(L.Step(L.Decode("zone|guild,ilvl,target|health,power,buffs|addons"), "zone", -1, all), "the top: nowhere to go")
    T.eq(L.Encode(L.Step(lay, "target", 1, all)), "guild,zone,ilvl|target|health,power,buffs|addons", "down past the line")
    -- Pieces the card doesn't show stay put and take no step.
    local shown = setmetatable({ zone = false, ilvl = false }, { __index = function() return true end })
    T.eq(L.Encode(L.Step(lay, "target", -1, shown)), "target,guild,zone,ilvl|health,power,buffs|addons",
        "past guild in one step, over the hidden zone and item level")
end)

T.test("mobBar bottom and addonLines mixed/hidden become layouts once", function()
    local TT = login()
    -- Sparse: only what the player changed.
    local sparse = { modules = { Tooltip = { mobBar = "bottom", addonLines = "mixed", textSize = 12 } } }
    TT.UpgradeLayout(sparse)
    local t = sparse.modules.Tooltip
    T.isnil(t.mobBar, "the old key goes")
    T.isnil(t.addonLines)
    T.eq(t.layout.mob, "quests|facts,target,addons|health", "the bar at the end, other addons with the facts")
    T.eq(t.layout.player, "guild,zone,ilvl,target,addons|health,power,buffs")
    T.eq(t.layout.item, "numbers,stats|effects,set,facts,quote,addons|made|foot")
    T.eq(t.layout.spell, "tiles,cooldown,desc,reagents,facts,addons")
    T.eq(t.tipUpgrade, 2)
    -- A second run changes nothing.
    t.mobBar = "bottom"
    TT.UpgradeLayout(sparse)
    T.eq(t.layout.mob, "quests|facts,target,addons|health")
    T.eq(t.mobBar, "bottom", "already done: left alone")
    -- Full (every default in it), hidden lines, a layout of their own kept.
    local full = { modules = { Tooltip = { addonLines = "hidden", mobBar = "top",
        layout = { player = "health|guild,zone,ilvl,target|power,buffs|addons", mob = "health|quests|facts,target|addons" },
        pieces = { player = { addons = true } } } } }
    TT.UpgradeLayout(full)
    t = full.modules.Tooltip
    T.eq(t.layout.player, "health|guild,zone,ilvl,target|power,buffs|addons", "their own layout untouched")
    T.eq(t.layout.mob, "health|quests|facts,target|addons", "Top: no change")
    for _, kind in ipairs({ "player", "mob", "item", "spell" }) do T.eq(t.pieces[kind].addons, false, kind) end
    -- Untouched: nothing written.
    local plain = { modules = { Tooltip = { textSize = 13 } } }
    TT.UpgradeLayout(plain)
    T.isnil(plain.modules.Tooltip.layout)
    T.isnil(plain.modules.Tooltip.pieces)
    T.eq(plain.modules.Tooltip.titleSize, 15, "the sizes' step ran first")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("a player who had the creature bar at the bottom sees it there after the update", function()
    login({ mobBar = "bottom" })
    stub.RunTimers()
    boar()
    hoverBoar()
    local p = panel()
    T.eq(p.items[p.count].kind, "bar", "the bar last: " .. kinds(p))
    T.eq(DaylightUI:Get("Tooltip", "layout.mob"), "quests|facts,target|health|addons")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- ---------------------------------------------------------------------
-- Design mode on the Tooltips page
-- ---------------------------------------------------------------------

local function page()
    login()
    stub.RunTimers()
    local P = DaylightUI.OptionsPanel
    P.Show("Tooltip.tooltip")
    return P, P.Strip()
end

local function spot(P, label)
    for _, b in ipairs(P.Strip().Hotspots()) do
        if b.part.label == label then return b end
    end
end

-- The fake game doesn't lay frames out: the card is put on the fake screen
-- by hand before a drag is aimed at its slots.
local function onScreen(owner)
    owner.GetLeft = function() return 300 end
    owner.GetTop = function() return 500 end
end
local function cursorAt(owner, x, y)
    local s = owner:GetEffectiveScale()
    stub.cursorPos = { (owner:GetLeft() + x) * s, (owner:GetTop() - y) * s }
end

-- Presses on b, moves to the card's x, y, lets go. Returns whether the
-- insert line showed while held, and where.
local function drag(P, b, x, y)
    local owner = b.part.move.owner
    onScreen(owner)
    cursorAt(owner, 20, 20)
    b:GetScript("OnMouseDown")(b, "LeftButton")
    cursorAt(owner, x, y)
    stub.RunOnUpdate(P.Strip(), 0.016)
    local line = P.Strip().InsertLine()
    local shown, at = line:IsShown(), line.at
    local lifted = P.Strip().Lifted():IsShown()
    b:GetScript("OnMouseUp")(b, "LeftButton")
    return shown, at, lifted
end

local function slotWhere(b, test)
    for _, sl in ipairs(b.part.move.slots()) do
        if not sl.region and test(sl.slot) then return sl end
    end
end

T.test("the Tooltips page has a Design switch and every piece of the sample is a hotspot", function()
    local P, strip = page()
    T.truthy(strip:IsShown(), "a live sample on the page")
    T.truthy(P.DesignSwitch():IsShown(), "a Design switch")
    P.SetDesign(true)
    stub.RunTimers()
    local labels = {}
    for _, b in ipairs(strip.Hotspots()) do labels[b.part.label] = b end
    for _, piece in ipairs(stub.tooltip.RichLayout.PIECES.player) do
        T.truthy(labels[piece.label], "a hotspot for " .. piece.label)
        T.truthy(labels[piece.label].part.move.list, piece.label .. " moves up and down")
    end
    -- The friendly buffs are off by default: they sit in the tray.
    local buffs = labels["Friendly players' buffs"]
    T.eq(buffs.part.region:GetParent(), strip.Sample().Tray().box, "buffs in the Hidden tray")
    -- Each kind's chip; one is always on.
    local chips = strip.ViewChips()
    T.eq(#chips, 4)
    -- Right to left on the strip: Spell, Item, Creature, Player.
    T.eq(chips[4].viewKey, "player", "Player at the far left")
    chips[2]:Click()
    stub.RunTimers()
    T.eq(strip.Sample().View(), "item")
    T.truthy(spot(P, "Durability and vendor price"), "the item's pieces now")
    chips[2]:Click()
    T.eq(strip.Sample().View(), "item", "clicking the picked chip keeps it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("a list drag shows the insert line at the nearest slot and the piece lands there", function()
    local P, strip = page()
    P.SetDesign(true)
    stub.RunTimers()
    local b = spot(P, "Zone")
    -- The line between the rows and the bars: a new section.
    local sl = slotWhere(b, function(s) return s.new and s.section == 2 end)
    T.truthy(sl, "a line slot between the sections")
    local shown, at, lifted = drag(P, b, 40, sl.y + 1)
    T.truthy(shown, "the insert line showed")
    T.eq(at, sl.y, "at the nearest slot")
    T.truthy(lifted, "the piece rode in its lifted box")
    T.falsy(strip.Lifted():IsShown(), "and put down")
    T.eq(DaylightUI:Get("Tooltip", "layout.player"), "guild,ilvl,target|zone|health,power,buffs|addons", "a section of its own")
    T.eq(strip.Selected(), "Zone", "picked")
    -- Onto the tray: hidden.
    b = spot(P, "Zone")
    local tray = strip.Sample().Tray().box
    tray.GetRect = function() return 600, 300, 100, 60 end
    tray.GetEffectiveScale = function() return 1 end
    b:GetScript("OnMouseDown")(b, "LeftButton")
    stub.cursorPos = { 630, 330 }
    stub.RunOnUpdate(strip, 0.016)
    T.falsy(strip.InsertLine():IsShown(), "over the tray: no line")
    b:GetScript("OnMouseUp")(b, "LeftButton")
    T.eq(DaylightUI:Get("Tooltip", "pieces.player.zone"), false, "a drop on Hidden turns its Show key off")
    T.eq(spot(P, "Zone").part.region:GetParent(), tray, "now in the tray")
    -- And back onto the card: shown again, where it was dropped.
    b = spot(P, "Zone")
    sl = slotWhere(b, function(s) return not s.new and s.section == 1 and s.index == 0 end)
    drag(P, b, 40, sl.y)
    T.eq(DaylightUI:Get("Tooltip", "pieces.player.zone"), true, "a drop back turns it on")
    T.eq(DaylightUI:Get("Tooltip", "layout.player"), "zone,guild,ilvl,target|health,power,buffs|addons",
        "at the top of the first section; its empty section closed")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("a list drag dropped outside any slot changes nothing; nor does a window closed mid-drag", function()
    local P, strip = page()
    P.SetDesign(true)
    stub.RunTimers()
    local b = spot(P, "Guild")
    local shown = drag(P, b, 1500, 40)
    T.falsy(shown, "far off the card: no line")
    T.eq(DaylightUI:Get("Tooltip", "layout.player"), stub.tooltip.RichLayout.DefaultText("player"), "nothing moved")
    T.eq(DaylightUI:Get("Tooltip", "pieces.player.guild"), true)
    -- Held, then the window closes: dropped unsaved.
    b = spot(P, "Guild")
    local owner = b.part.move.owner
    onScreen(owner)
    cursorAt(owner, 20, 20)
    b:GetScript("OnMouseDown")(b, "LeftButton")
    local sl = slotWhere(b, function(s) return s.new and s.section == 2 end)
    cursorAt(owner, 40, sl.y)
    stub.RunOnUpdate(strip, 0.016)
    T.truthy(strip.Lifted():IsShown())
    P.Toggle()
    stub.FinishFade(P.Frame())
    T.falsy(P.Frame():IsShown(), "the window closed")
    T.falsy(strip.Lifted():IsShown(), "the lifted box goes")
    T.eq(DaylightUI:Get("Tooltip", "layout.player"), stub.tooltip.RichLayout.DefaultText("player"), "still nothing moved")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("the arrow keys move the picked piece one slot; dots never show for a list move", function()
    local P, strip = page()
    P.SetDesign(true)
    stub.RunTimers()
    local b = spot(P, "Item level")
    b:GetScript("OnClick")(b)
    T.eq(strip.Selected(), "Item level")
    T.truthy(strip.keys:IsKeyboardEnabled(), "picked: the arrows are ours")
    local press = strip.keys:GetScript("OnKeyDown")
    press(strip.keys, "UP")
    T.eq(DaylightUI:Get("Tooltip", "layout.player"), "guild,ilvl,zone,target|health,power,buffs|addons", "one up")
    press(strip.keys, "DOWN")
    press(strip.keys, "DOWN")
    T.eq(DaylightUI:Get("Tooltip", "layout.player"), "guild,zone,target,ilvl|health,power,buffs|addons", "two down")
    press(strip.keys, "LEFT")
    T.eq(DaylightUI:Get("Tooltip", "layout.player"), "guild,zone,target,ilvl|health,power,buffs|addons", "sideways: nothing")
    b = spot(P, "Guild")
    drag(P, b, 40, 30)
    T.eq(strip.DotsShown(), 0, "no dots")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("a piece only lands on a slot: never in the header, never sideways", function()
    local P, strip = page()
    P.SetDesign(true)
    stub.RunTimers()
    local b = spot(P, "Targeting")
    b = b or spot(P, "Show who they're targeting")
    local slots = b.part.move.slots()
    local p = strip.Sample().Card()
    local header = p.items[1]
    for _, sl in ipairs(slots) do
        if not sl.region then
            T.truthy(sl.y > header.y + header.tall, "below the header: " .. sl.y)
            T.eq(sl.x, p.padX or stub.tooltip.RichPanel.PAD_X, "the card's left edge")
        end
    end
    -- Dropped high up on the header: it lands on the first slot below it.
    drag(P, b, 40, 2)
    T.eq(DaylightUI:Get("Tooltip", "layout.player"), "target|guild,zone,ilvl|health,power,buffs|addons",
        "on the top line, a section of its own")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("a profile switch redraws the sample from the new profile's layout", function()
    local P, strip = page()
    P.SetDesign(true)
    stub.RunTimers()
    -- A change made elsewhere (a reset, another row) redraws it at once.
    DaylightUI:Set("Tooltip", "layout.player", "addons|guild,zone,ilvl,target|health,power,buffs")
    stub.RunTimers()
    local p = strip.Sample().Card()
    T.truthy(p.spans.addons.from < p.spans.guild.from, "other addons first now")
    -- A profile switch reloads the game: the other profile's layout, Design
    -- mode open again on the page.
    login({ layout = { player = "health,power,buffs|guild,zone,ilvl,target|addons" } })
    stub.RunTimers()
    P = DaylightUI.OptionsPanel
    P.Show("Tooltip.tooltip")
    P.SetDesign(true)
    stub.RunTimers()
    p = P.Strip().Sample().Card()
    T.truthy(p.spans.health.from < p.spans.guild.from, "that profile's own order")
    -- A new character: the default card.
    P, strip = page()
    p = strip.Sample().Card()
    T.truthy(p.spans.guild.from < p.spans.health.from and p.spans.health.from < p.spans.addons.from, "the default order")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("the sample follows Quest progress bars and shows nothing Forever doesn't have", function()
    local P, strip = page()
    P.SetDesign(true)
    stub.RunTimers()
    for _, line in ipairs(shape(strip.Sample().Card())) do
        T.falsy(line:find("Raider"), "no Raider.IO on Forever: " .. line)
    end
    local function questBars()
        local chips = strip.ViewChips()
        if strip.Sample().View() ~= "mob" then chips[3]:Click() end
        stub.RunTimers()
        T.eq(strip.Sample().View(), "mob")
        local p, n = strip.Sample().Card(), 0
        local span = p.spans.quests
        for i = span.from, span.to do
            if p.items[i].kind == "bar" then n = n + 1 end
        end
        return n
    end
    T.eq(questBars(), 1, "a bar under the objective by default")
    DaylightUI:Set("Tooltip", "questBars", false)
    stub.RunTimers()
    T.eq(questBars(), 0, "Quest progress bars off: the objective without its bar")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("Simple style: no sample on the Tooltips page", function()
    local P, strip = page()
    DaylightUI:Set("Tooltip", "style", "simple")
    stub.RunTimers()
    P.Show("Tooltip.tooltip")
    T.falsy(strip:IsShown(), "no Rich card to design")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- ---------------------------------------------------------------------
-- The new options: each changes the card and nothing else
-- ---------------------------------------------------------------------

local function fillNamed(name)
    for _, f in ipairs(FILLS) do
        if f[1] == name then return f end
    end
end

-- A card built with one setting, against the same card without it.
local function withSetting(name, key, value)
    local before = run(fillNamed(name))
    local shapeBefore = shape(before)
    local tagsBefore = {}
    for _, t in ipairs(before.items[1].tags or (before.items[3] and before.items[3].tags) or {}) do
        tagsBefore[#tagsBefore + 1] = stub.Text(t.text)
    end
    login({ [key:match("^[^.]+")] = nil })
    stub.RunTimers()
    DaylightUI:Set("Tooltip", key, value)
    stub.RunTimers()
    local p = fillNamed(name)[2]() or panel()
    return p, shapeBefore, tagsBefore
end

local function headerOf(p)
    for i = 1, p.count do
        if p.items[i].kind == "header" then return p.items[i] end
    end
end

local function tagTexts(head)
    local out = {}
    for _, t in ipairs(head.tags or {}) do out[#out + 1] = stub.Text(t.text) end
    return table.concat(out, " ")
end

T.test("each new option changes the card and nothing else", function()
    -- A tag off: that tag goes, the rest of the card stays.
    local tagCases = {
        { "player", "tags.player.class", "MAGE" }, { "player", "tags.player.race", "NIGHT ELF" },
        { "mob", "tags.mob.reaction", "HOSTILE" }, { "mob", "tags.mob.type", "BEAST" },
        { "item", "tags.item.level", "ILVL 66" }, { "item", "tags.item.slot", "LEGS" },
        { "item", "tags.item.bind", "BINDS WHEN EQUIPPED" },
        { "spell", "tags.spell.school", "FROST" }, { "spell", "tags.spell.rank", "RANK 4" },
    }
    for _, c in ipairs(tagCases) do
        local before = run(fillNamed(c[1]))
        local head0 = tagTexts(headerOf(before)):upper()
        local shape0 = shape(before)
        T.truthy(head0:find(c[3], 1, true), c[2] .. ": the tag is there by default (" .. head0 .. ")")
        local p = withSetting(c[1], c[2], false)
        local head1 = tagTexts(headerOf(p)):upper()
        T.falsy(head1:find(c[3], 1, true), c[2] .. ": gone (" .. head1 .. ")")
        local shape1 = shape(p)
        T.eq(#shape1, #shape0, c[2] .. ": the same pieces")
        for i = 2, #shape0 do
            T.eq(shape1[i]:match("^(%a+)"), shape0[i]:match("^(%a+)"), c[2] .. " item " .. i)
        end
        T.eq(#stub.errors, 0, c[2] .. ": " .. tostring(stub.errors[1]))
    end
    -- The level beside the name.
    for _, name in ipairs({ "player", "mob" }) do
        local p = withSetting(name, "headerLevel", false)
        T.isnil(headerOf(p).right, name .. ": no level")
        T.eq(stub.Text(headerOf(p).title):match("^%a+"), name == "player" and "Aelindra" or "Ridgeback", "the name stays")
    end
    -- The light, the wash, the cut.
    local p = withSetting("item", "cardLight", false)
    T.falsy(p.light[1]:IsShown(), "no top light")
    T.truthy(p.wash[1]:IsShown(), "the wash stays")
    p = withSetting("item", "cardWash", false)
    T.falsy(p.wash[1]:IsShown(), "no wash")
    T.truthy(p.light[1]:IsShown(), "the light stays")
    p = withSetting("item", "cardCut", false)
    T.eq(DaylightUI.Style.GetCut(p), 0, "no cut corner")
    DaylightUI:Set("Tooltip", "cardCut", true)
    stub.RunTimers()
    items(); fillItem(GameTooltip, "greaves", GREAVES); update()
    T.eq(DaylightUI.Style.GetCut(panel()), stub.tooltip.RichPanel.CUT, "and back")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("compact rows sit 3 apart; a wider card is its width times the setting, compare cards too", function()
    local Panel = function() return stub.tooltip.RichPanel end
    local p, shape0 = withSetting("player", "cardRows", "compact")
    local guild, target
    for i = 1, p.count do
        local it = p.items[i]
        if it.kind == "row" and stub.Text(it.label) == "Guild" then guild = it end
        if it.kind == "row" and stub.Text(it.label) == "Targeting" then target = it end
    end
    T.eq(target.y - (guild.y + guild.tall), Panel().COMPACT_ROW_GAP, "rows 3 apart")
    T.eq(#shape(p), #shape0, "the same pieces")
    p = withSetting("item", "cardRows", "compact")
    local rule
    for i = 1, p.count do if p.items[i].kind == "rule" then rule = p.items[i] break end end
    T.eq(rule.tall, 2 * Panel().COMPACT_RULE_GAP + DaylightUI.Pixel.Px(rule.tex, 1), "rules closer too")
    p = withSetting("player", "cardWidth", 1.3)
    T.eq(p.wantW, math.ceil(Panel().WIDTH.unit * 1.3), "the player card 1.3 times as wide")
    login()
    stub.RunTimers()
    DaylightUI:Set("Tooltip", "cardWidth", 0.8)
    stub.RunTimers()
    items()
    local compare = compareFill()
    T.eq(compare.wantW, math.ceil(Panel().WIDTH.compare * 0.8), "the compare card matches")
    T.eq(panel().wantW, math.ceil(Panel().WIDTH.item * 0.8), "and the item's")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("the stack size line on the Rich item card", function()
    login()
    stub.RunTimers()
    items()
    local info = C_Item.GetItemInfo
    C_Item.GetItemInfo = function(link)
        if link == "greaves" then return "Dawnforged Greaves", link, 4, 66, 58, "Armor", "Plate", 20 end
        return info(link)
    end
    fillItem(GameTooltip, "greaves", GREAVES)
    update()
    local function stackLine(p)
        for i = 1, p.count do
            local fs = p.items[i].fs
            if fs and (stub.Text(fs) or ""):find("Stacks to", 1, true) then return p.items[i] end
        end
    end
    T.isnil(stackLine(panel()), "off by default")
    local count = panel().count
    DaylightUI:Set("Tooltip", "stackSize", true)
    stub.RunTimers()
    fillItem(GameTooltip, "greaves", GREAVES)
    update()
    local line = stackLine(panel())
    T.truthy(line, "with the small facts")
    T.truthy(stub.Text(line.fs):find("20", 1, true), "the number")
    T.eq(panel().count, count + 1, "one line more, nothing else")
    C_Item.GetItemInfo = info
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
