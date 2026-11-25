-- The tooltips' options page.

local _, ns = ...

local lookRows = DaylightUI.Options.LookRows("frameStyle")

local function notRich(get) return get("style") ~= "rich" end
local SINCE = "2.3"

-- Each Rich card's pieces (Rich/Layout.lua): a switch per piece, the same
-- ones Design mode's Hidden tray flips, and a reset for the card's order.
local CARDS = {
    { id = "player", label = "Player",
      reset = "Reset the player card's layout", resetDesc = "Puts the pieces of player cards back in their first order and sections. Hidden pieces stay hidden.",
      pieces = {
        { "guild", "Guild on player cards", "Their guild, and their rank in it when Guild rank is on." },
        { "zone", "Zone on player cards", "Where a party or raid member is." },
        { "ilvl", "Item level on player cards", "Their average item level, once the game knows it (yours, or someone you've inspected)." },
        { "health", "Health bar on player cards", "Their health as a bar under the rows." },
        { "power", "Power bar on player cards", "Their mana, rage or energy as a thin bar under their health." },
        { "addons", "Other addons' lines on player cards", "Lines other addons add (scores, notes). When off, only Daylight UI plugins' lines still show." },
    } },
    { id = "mob", label = "Creature",
      reset = "Reset the creature card's layout", resetDesc = "Puts the pieces of creature cards back in their first order and sections. Hidden pieces stay hidden.",
      pieces = {
        { "health", "Health bar on creature cards", "The creature's health as a bar." },
        { "quests", "Quests on creature cards", "The quests it counts for, with each objective's progress." },
        { "facts", "Small facts on creature cards", "The game's other lines about it, in small text (a skill it needs, a title)." },
        { "addons", "Other addons' lines on creature cards", "Lines other addons add. When off, only Daylight UI plugins' lines still show." },
    } },
    { id = "item", label = "Item",
      reset = "Reset the item card's layout", resetDesc = "Puts the pieces of item cards back in their first order and sections. Hidden pieces stay hidden.",
      pieces = {
        { "numbers", "Damage and armor on item cards", "A weapon's damage, speed and damage per second, or a piece's armor and block." },
        { "stats", "Stats on item cards", "Strength, Stamina and every other stat, one line each." },
        { "effects", "Effects on item cards", "What it does when you equip or use it." },
        { "set", "Set on item cards", "Its set's name, how many pieces you have, and the set bonuses." },
        { "facts", "Requirements on item cards", "Level, class and other requirements, and the game's other small lines." },
        { "quote", "Quote on item cards", "The item's flavor text." },
        { "made", "Crafted item on item cards", "On a recipe, the item it makes." },
        { "addons", "Other addons' lines on item cards", "Prices, counts and other lines other addons add. When off, only Daylight UI plugins' lines still show." },
        { "foot", "Durability and vendor price on item cards", "Its durability and what a vendor pays for it." },
    } },
    { id = "spell", label = "Spell",
      reset = "Reset the spell card's layout", resetDesc = "Puts the pieces of spell cards back in their first order and sections. Hidden pieces stay hidden.",
      pieces = {
        { "tiles", "Cast, cost and range on spell cards", "The three boxes under the spell's name: cast time, cost and range or cooldown." },
        { "cooldown", "Cooldown countdown on spell cards", "When a spell on your action bar is cooling down, how long until it's ready." },
        { "desc", "Description on spell cards", "What the spell does." },
        { "reagents", "Reagents on spell cards", "On a profession recipe, the reagents and tools it needs." },
        { "facts", "Small facts on spell cards", "The game's other small lines about the spell." },
        { "addons", "Other addons' lines on spell cards", "Lines other addons add. When off, only Daylight UI plugins' lines still show." },
    } },
}

local function pieceChoices()
    local out = {}
    for _, c in ipairs(CARDS) do
        local items = {}
        for _, piece in ipairs(c.pieces) do
            items[#items + 1] = { type = "toggle", key = "pieces." .. c.id .. "." .. piece[1],
                label = piece[2], desc = piece[3], since = SINCE, hidden = notRich }
        end
        items[#items + 1] = { type = "button", label = c.reset, text = "Reset",
            confirm = true, since = SINCE, hidden = notRich, desc = c.resetDesc,
            func = function()
                local L = ns.RichLayout
                DaylightUI:Set("Tooltip", "layout." .. c.id, L.DefaultText(c.id))
            end }
        out[#out + 1] = { id = c.id, label = c.label, items = items }
    end
    return out
end

-- The tags under each card's name.
local TAGS = {
    { id = "player", label = "Player", tags = {
        { "class", "Class tag on player cards", "Their spec, or their class until the game knows it, in their class color." },
        { "race", "Race tag on player cards", "Their race, in their faction's color." },
    } },
    { id = "mob", label = "Creature", tags = {
        { "reaction", "Reaction tag on creature cards", "Hostile, Neutral or Friendly, in its color." },
        { "type", "Creature type tag on creature cards", "What it is: Beast, Humanoid, Undead and so on." },
    } },
    { id = "item", label = "Item", tags = {
        { "level", "Item level tag on item cards", "The item's level." },
        { "slot", "Slot tags on item cards", "Where it's worn and what it is (Legs, Plate)." },
        { "bind", "Binding tags on item cards", "Binds when picked up or equipped, Unique and the like." },
    } },
    { id = "spell", label = "Spell", tags = {
        { "school", "School tag on spell cards", "The spell's school (Frost, Fire), in its color." },
        { "rank", "Rank tag on spell cards", "The spell's rank." },
    } },
}

local function tagChoices()
    local out = {}
    for _, c in ipairs(TAGS) do
        local items = {}
        for _, t in ipairs(c.tags) do
            items[#items + 1] = { type = "toggle", key = "tags." .. c.id .. "." .. t[1], label = t[2],
                desc = t[3], since = SINCE, hidden = notRich }
        end
        out[#out + 1] = { id = c.id, label = c.label, items = items }
    end
    return out
end

-- Other addons' lines hidden on every Rich card: their looks have nothing to do.
local function noAddonLines(get)
    for _, kind in ipairs({ "player", "mob", "item", "spell" }) do
        if get("pieces." .. kind .. ".addons") ~= false then return false end
    end
    return true
end

ns.OPTIONS = { pages = {
    { id = "tooltip", label = "Tooltips",
      desc = "The game's tooltips in the Daylight UI look.",
      -- With PrettyTooltip on this module is off (Module.lua), so none of this would apply.
      hidden = function() return DaylightUI.PrettyAside.Draws() end,
      groups = {
        { label = "Style", items = {
            { type = "dropdown", key = "style", label = "Tooltip style", since = "2.0",
              values = { rich = "Rich", simple = "Simple" }, order = { "rich", "simple" },
              desc = "Rich: Daylight UI's own cards, with a colored light along the top and everything laid out as rows. "
                  .. "Simple: the game's tooltips in the Daylight UI look. In a fight Rich keeps its frame around the game's own lines." },
            { type = "dropdown", key = "pill", label = "Fight pill", since = "2.0",
              values = { combat = "In combat", always = "Always", never = "Never" }, order = { "combat", "always", "never" },
              desc = "A player or creature as one small line where the tooltip would be: their name, their health and a thin bar. Hold the full card key to see the whole card.",
              hidden = function(get) return get("style") ~= "rich" end },
            { type = "dropdown", key = "pillKey", label = "Full card key", since = "2.0",
              values = { shift = SHIFT_KEY_TEXT or "Shift", ctrl = CTRL_KEY_TEXT or "Ctrl", alt = ALT_KEY_TEXT or "Alt", none = NONE or "None" },
              order = { "shift", "ctrl", "alt", "none" },
              desc = "Hold this key over a player or creature to see their whole card in place of the fight pill. None keeps the pill whatever you hold.",
              hidden = function(get) return get("style") ~= "rich" or get("pill") == "never" end },
            { type = "toggle", key = "portraits", label = "Portraits", since = "2.0.2",
              desc = "A creature's face and a player's class icon at the top of their card. Off, the card starts with the name.",
              hidden = function(get) return get("style") ~= "rich" end },
            { type = "toggle", key = "questBars", label = "Quest progress bars", since = "2.1.4",
              desc = "A thin bar under each quest objective on the card. Off, the objective and its count still show.",
              hidden = function(get) return get("style") ~= "rich" end },
        } },
        DaylightUI.Options.PickCard({ label = "Card pieces",
            desc = "What each Rich card shows. Turn on Design mode at the top of the page to drag them into your own order.",
            pickDesc = "Which card's pieces to set.", choices = pieceChoices(), pickHidden = notRich }),
        DaylightUI.Options.PickCard({ label = "Card header",
            desc = "The name at the top of each Rich card, its tags and level.",
            lead = {
                { type = "toggle", key = "headerLevel", label = "Level beside the name", since = SINCE, hidden = notRich,
                  desc = "A player's or creature's level at the right of their name, colored by how hard they are for you." },
            },
            pickDesc = "Which card's tags to set.", choices = tagChoices(), pickHidden = notRich }),
        { label = "Other addons", items = {
            { type = "toggle", key = "addonAdapters.questie", label = "Quest progress from other addons", since = "2.0",
              desc = "Quest rows another addon adds (Questie) drawn like the game's own: the quest's name in its difficulty color and a thin bar per objective. A quest the game already lists isn't shown twice.",
              hidden = function(get) return get("style") ~= "rich" or noAddonLines(get) end },
            { type = "toggle", key = "addonAdapters.prices", label = "Prices from other addons", since = "2.0",
              desc = "Price lines another addon adds (Auctionator, TSM) as a label and Daylight UI's coins.",
              hidden = function(get) return get("style") ~= "rich" or noAddonLines(get) end },
            { type = "toggle", key = "addonAdapters.score", label = "Scores from other addons", since = "2.0",
              desc = "A score or rating another addon adds, as a row with the number in your accent color.",
              hidden = function(get) return get("style") ~= "rich" or noAddonLines(get) end },
            { type = "toggle", key = "addonAdapters.itemtree", label = "ItemTree's advice",
              desc = "ItemTree's lines under a heading of their own, with what it says to do (keep, sell, open) as colored tags.",
              hidden = function(get)
                  return get("style") ~= "rich" or noAddonLines(get) or rawget(_G, "ItemTreeAPI") == nil
              end },
        } },
        { label = "Placement", items = {
            { type = "dropdown", key = "anchor", label = "Tooltip position",
              values = { game = "Default position", cursor = "At the cursor" }, order = { "game", "cursor" },
              desc = "Default position: where the game puts it, or where you dragged it in unlock mode. "
                  .. "Tooltips for bags, bars and other frames that place their own still sit beside what you hover." },
            { type = "slider", key = "cursorX", label = "Tooltip left / right of the cursor", min = -100, max = 100, step = 1, unit = "px",
              desc = "How far right of the cursor the tooltip's corner sits (below zero: to the left).",
              hidden = function(get) return get("anchor") ~= "cursor" end },
            { type = "slider", key = "cursorY", label = "Tooltip up / down from the cursor", min = -100, max = 100, step = 1, unit = "px",
              desc = "How far above the cursor the tooltip's corner sits (below zero: lower down).",
              hidden = function(get) return get("anchor") ~= "cursor" end },
        } },
        { label = "Size", items = {
            { type = "slider", key = "scale", label = "Tooltip scale", min = 0.6, max = 1.6, step = 0.05, unit = "x",
              desc = "Makes tooltips bigger or smaller, text and all, on top of Daylight UI scale (General > Appearance)." },
            { type = "slider", key = "textSize", label = "Tooltip text size", min = 9, max = 18, step = 1,
              desc = "The tooltip's lines. Titles and small text have sizes of their own." },
            DaylightUI.Options.FontRow("media.font", "Tooltip font", "Every line in the tooltips"),
            { type = "slider", key = "titleSize", label = "Tooltip title size", min = 9, max = 24, step = 1, since = "2.0",
              desc = "The name at the top of a tooltip (a player, a creature, an item, a spell) and the headings on Rich cards." },
            DaylightUI.Options.MediaPick("font", "media.titleFont", "Tooltip title font",
                "The name at the top of a tooltip and the headings on Rich cards. General uses the tooltip font.",
                { since = "2.0", follows = { slot = "tooltip.font", label = "Tooltip font" } }),
            { type = "slider", key = "smallSize", label = "Tooltip small text size", min = 8, max = 18, step = 1, since = "2.0",
              desc = "The small lines: under a title, short facts, quotes and captions." },
            DaylightUI.Options.MediaPick("font", "media.smallFont", "Tooltip small text font",
                "The small lines under a title, short facts, quotes and captions. General uses the tooltip font.",
                { since = "2.0", follows = { slot = "tooltip.font", label = "Tooltip font" } }),
            { type = "slider", key = "dpsSize", label = "Damage per second size", min = 9, max = 24, step = 1, since = "2.2",
              desc = "A weapon's damage per second, the big number over its damage and speed.",
              hidden = function(get) return get("style") ~= "rich" end },
            { type = "dropdown", key = "cardRows", label = "Card row spacing", since = SINCE,
              values = { roomy = "Roomy", compact = "Compact" }, order = { "roomy", "compact" },
              desc = "How far apart the rows and lines of a Rich card sit. Compact makes every card shorter.",
              hidden = notRich },
            { type = "slider", key = "cardWidth", label = "Card width", min = 0.8, max = 1.3, step = 0.05, unit = "x", since = SINCE,
              desc = "Makes every Rich card wider or narrower than its usual width. Long lines wrap on a narrow card.",
              hidden = notRich },
        } },
        { label = "Borders and background", items = lookRows },
        { label = "Look", items = {
            { type = "toggle", key = "classColors", label = "Class-colored names",
              desc = "A player's name in their class color; other units in their reaction's color." },
            { type = "toggle", key = "classBorder", label = "Class-colored border",
              desc = "The border in a player's class color, other units in their reaction color." },
            { type = "toggle", key = "borderGradient", label = "Gradient border",
              desc = "The class-colored border in the unit's class (or reaction) gradient from General > Gradients, running left to right.",
              disabled = function(get) return get("classBorder") == false end },
            { type = "toggle", key = "qualityBorder", label = "Item quality border",
              desc = "Items that are uncommon or better get a border in their quality color." },
            { type = "toggle", key = "cardLight", label = "Colored light along the card's top", since = SINCE,
              desc = "A thin line in the class, reaction or quality color across the top of each Rich card.",
              hidden = notRich },
            { type = "toggle", key = "cardWash", label = "Color wash behind the name", since = SINCE,
              desc = "A soft glow of the same color behind the name at the top of a Rich card.",
              hidden = notRich },
            { type = "toggle", key = "cardCut", label = "Cut corner on cards", since = SINCE,
              desc = "The Rich card's bottom right corner cut at an angle. When off, the card is a plain box.",
              hidden = notRich },
        } },
        { label = "Health bar", items = DaylightUI.Options.Join({
            { type = "toggle", key = "healthBar", label = "Health bar",
              desc = "A slim bar under the tooltip of a player or creature." },
            { type = "slider", key = "barHeight", label = "Health bar height", min = 2, max = 12, step = 1, unit = "px",
              desc = "How tall the health bar under the tooltip is.",
              disabled = function(get) return get("healthBar") ~= true end },
            DaylightUI.Options.BarRow("media.health", "Health bar", "the health bar under a unit's tooltip", function(get) return get("healthBar") ~= true end),
            DaylightUI.Options.BackRow("media.health", "Health bar", "the health bar under a unit's tooltip", function(get) return get("healthBar") ~= true end),
            { type = "dropdown", key = "barGradient", label = "Health bar color",
              values = { frames = "Same as unit frames", gradient = "Class gradient", flat = "Class and reaction",
                         customGradient = "Custom gradient" },
              order = { "frames", "gradient", "flat", "customGradient" },
              desc = "Same as unit frames: a class gradient or custom gradient when your unit frames' health bars use one. "
                  .. "Class gradient uses the pairs from General > Gradients. Custom gradient runs through colors you pick.",
              disabled = function(get) return get("healthBar") ~= true end },
        }, DaylightUI.Options.StopsRows("barStops", { what = "tooltip health", bar = "the tooltip's health bar", since = "2.2",
            disabled = function(get) return get("healthBar") ~= true end,
            shown = function(get) return get("barGradient") == "customGradient" end })) },
        { label = "Player and creature lines", items = {
            { type = "toggle", key = "showTarget", label = "Show who they're targeting",
              desc = "Who a player or creature is targeting, in their color (\">> You <<\" when it's you)." },
            { type = "toggle", key = "guildRank", label = "Guild rank", desc = "A player's guild rank, after their guild name." },
            { type = "toggle", key = "buffs", label = "Friendly players' buffs",
              desc = "A friendly player's buffs as a row of small icons, so you can see what they're missing before you rebuff. Not in combat: the game hides other players' buffs then." },
            { type = "toggle", key = "lastNames.tooltip", label = "First and last names",
              desc = "Players' last names after their first, on tooltips. Where the game hides names (in combat, in places) only the first name shows.",
              get = function() return DaylightUI:Get("general", "lastNames.tooltip") == true end,
              set = function(v) DaylightUI:Set("general", "lastNames.tooltip", v) end,
              default = function() return true end },
            -- Lives in the Quests module (GiverTips.lua), which draws it even with this module off.
            { type = "toggle", key = "mapQuests.tooltip", scope = "Quests", label = "Quests in NPC tooltips",
              desc = "Point at a quest giver to see the quests you can pick up from them and the ones ready to hand in, each with its level in its difficulty color. Needs Questie.",
              hidden = function() return not DaylightUI:GetModule("Quests") end,
              -- The list comes from Questie (GiverTips' GT.On), so nothing shows without it.
              disabled = function()
                  local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
                  return not (type(loaded) == "function" and loaded("Questie") == true)
              end,
              get = function() return DaylightUI:Get("Quests", "mapQuests.tooltip") ~= false end,
              set = function(v) DaylightUI:Set("Quests", "mapQuests.tooltip", v) end,
              default = function() return true end },
        } },
        { label = "Item and spell lines", items = {
            { type = "toggle", key = "greenStats", label = "Short, colored item stats",
              desc = "An item's green Equip lines in a few words (\"Improves your chance to hit by 1%\" reads \"+1% Hit\"), and every stat in a color of its own: each school, hit, crit, spell power, healing, the base stats. Food, drink, potions and bandages too (\"530 health over 24 sec\", \"Well Fed: +5 Stamina (15 min)\"). Procs and other use effects stay as they are.",
              hidden = function(get) return get("style") == "rich" end },
            { type = "toggle", key = "itemLevel", label = "Item level line",
              desc = "An Item Level line on weapon and armor tooltips, in soft gold.",
              hidden = function(get) return get("style") == "rich" end },
            { type = "toggle", key = "stackSize", label = "Stack size line",
              desc = "How many of an item fit in one bag slot (\"Stacks to 20\"), on items that stack. On a Rich card it sits with the small facts." },
            { type = "toggle", key = "compareItems", label = "Compare with what you wear", since = "2.2.3",
              desc = "Pointing at an item shows what you have on beside it, as the game's own compare setting says. When off, it shows only while Shift is held." },
            { type = "toggle", key = "showIDs", label = "Spell and item IDs",
              desc = "A small line at the bottom of spell and item tooltips with its ID, the word in your accent color: handy for macros, other addons and bug reports. Buff and debuff icons use the game's own tooltip, which can't show it." },
        } },
        { label = "Hiding", items = {
            { type = "toggle", key = "fadeOut", label = "Fade out world tooltips",
              desc = "A tooltip for something in the world (a creature, a player, a mailbox) fades away slowly after the mouse leaves it, as the game does. When off, it's gone at once." },
            { type = "toggle", key = "hideInCombat", invert = true, label = "Show unit tooltips in combat",
              desc = "Players' and creatures' tooltips show while you're fighting. When off, they stay hidden in a fight; hold Shift to see one." },
            { type = "toggle", key = "hideBobber", since = "2.2.4", label = "Hide the fishing bobber's tooltip",
              desc = "While your line is in the water, pointing at the bobber shows no tooltip, so nothing covers it. Clicking the bobber still reels in." },
        } },
    } },
} }
