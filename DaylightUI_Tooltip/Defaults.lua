-- Default settings for the tooltips.

local _, ns = ...

-- Bar texture and fonts picked separately for this area (Media.RegisterArea):
-- the health bar, the tooltip text, and the titles and small text, which
-- follow the tooltip font until given their own.
ns.MEDIA_BARS = { "health" }
ns.MEDIA_FONTS = { "title", "small" }
ns.MEDIA = DaylightUI.Media.RegisterArea("tooltip", "Tooltip", ns.MEDIA_BARS, ns.MEDIA_FONTS)
for _, k in ipairs(ns.MEDIA_FONTS) do
    DaylightUI.Media.RegisterSlot(ns.MEDIA.fonts[k], "Tooltip", "media." .. k .. "Font", "font", ns.MEDIA.font)
end

ns.DEFAULTS = {
    media = DaylightUI.Media.AreaDefaults(ns.MEDIA_BARS, ns.MEDIA_FONTS),
    -- "simple": the game's tooltip in the Daylight UI look; "rich": Daylight UI's
    -- own cards drawn over it (Rich/).
    style = "rich",
    pill = "never", -- a unit as one small line where the tooltip would be: "combat" (and under restrictions), "always", "never"
    pillKey = "shift", -- held, the full card in the pill's place: "shift", "ctrl", "alt", "none"
    portraits = true, -- a creature's face and a player's class icon at the top of their card
    questBars = true, -- a thin progress bar under each quest objective on the card
    -- Each Rich card's pieces: whether one shows (Design mode's Hidden tray
    -- writes these too) and their order in sections (Rich/Layout.lua, saved
    -- as text: "guild,zone|health,power"). Other addons' lines are a piece.
    pieces = {
        player = { guild = true, zone = true, ilvl = true, health = true, power = true, addons = true },
        mob = { health = true, quests = true, facts = true, addons = true },
        item = { numbers = true, stats = true, effects = true, set = true, facts = true, quote = true, made = true,
                 addons = true, foot = true },
        spell = { tiles = true, cooldown = true, desc = true, reagents = true, facts = true, addons = true },
    },
    -- The tags under a card's name, and its level beside it.
    tags = {
        player = { class = true, race = true },
        mob = { reaction = true, type = true },
        item = { level = true, slot = true, bind = true },
        spell = { school = true, rank = true },
    },
    headerLevel = true,
    cardLight = true,   -- the colored light along a card's top
    cardWash = true,    -- the color behind its name
    cardCut = true,     -- its cut bottom right corner
    cardRows = "roomy", -- "roomy" or "compact": how far apart its rows and lines sit
    cardWidth = 1,      -- times each card's own width
    layout = {
        player = "guild,zone,ilvl,target|health,power,buffs|addons",
        mob = "health|quests|facts,target|addons",
        item = "numbers,stats|effects,set,facts,quote|made|addons,foot",
        spell = "tiles,cooldown,desc,reagents,facts|addons",
    },
    -- Which kinds of other addons' lines get a look of their own; off, they're
    -- repainted like any other line.
    addonAdapters = { questie = true, prices = true, score = true, itemtree = true },
    anchor = "game", -- "game": at Daylight UI's unlock handle (near the game's spot); "cursor": follows the mouse
    cursorX = 12, -- offset of the cursor tooltip's bottom-left corner from the cursor
    cursorY = 12,
    scale = 1,
    textSize = 12,   -- every line
    titleSize = 14,  -- a name, an item's name, a spell's name
    smallSize = 11,  -- sub lines, the quote, small facts
    dpsSize = 14,    -- a weapon's damage per second on the Rich card
    -- Their border, shadow and background. By design tooltips are a little
    -- more solid than the windows, also on the global style.
    frameStyle = DaylightUI.Style.LookDefaults({ windowAlpha = 0.92 }),
    classColors = true,     -- players' names in their class color
    classBorder = true, -- class-colored border too
    borderGradient = false, -- border uses the unit's class (or reaction) gradient
    showTarget = true, -- a "Target:" line showing who the unit is targeting
    guildRank = true,       -- a player's rank after their guild
    buffs = false, -- a friendly player's buffs as icons (out of combat only; secret in combat)
    greenStats = true, -- shorten items' green "Equip:" lines ("+1% Hit")
    itemLevel = false,      -- an "Item Level" line on weapons and armor
    stackSize = false,      -- "Stacks to 20" on items that stack
    showIDs = false,        -- an "Item ID" / "Spell ID" line on items, spells and auras
    compareItems = false,   -- what you wear beside an item without Shift, when the game's compare setting is on
    qualityBorder = true, -- item border in its quality color
    healthBar = true,
    barGradient = "frames", -- health bar color: "frames" (a gradient when unit frame health uses one), "gradient", "flat", "customGradient"
    barStops = DaylightUI.Style.DefaultStops(), -- ...the colors for "customGradient"
    barHeight = 5,
    hideInCombat = false, -- in combat, show unit tooltips only while Shift is held
    hideBobber = false, -- no tooltip on the fishing bobber while the line is in
    fadeOut = false, -- world object tooltips fade out like the game's (off: hide at once)
}

-- Titles and small text used to be the text size plus 2 and minus 1. A
-- profile that changed the text size before they had sizes of their own
-- keeps them where they were. Runs once per profile (tipUpgrade), on full or
-- sparse settings alike.
function ns.UpgradeSizes(p)
    if type(p) ~= "table" or type(p.modules) ~= "table" then return end
    local t = p.modules.Tooltip
    if type(t) ~= "table" or (tonumber(t.tipUpgrade) or 0) >= 1 then return end
    t.tipUpgrade = 1
    local text = tonumber(t.textSize)
    if not text or text == ns.DEFAULTS.textSize then return end
    if t.titleSize == nil or t.titleSize == ns.DEFAULTS.titleSize then t.titleSize = text + 2 end
    if t.smallSize == nil or t.smallSize == ns.DEFAULTS.smallSize then t.smallSize = text - 1 end
end
DaylightUI.DB.RegisterUpgrade(ns.UpgradeSizes)

-- Two settings became spots on the cards (Rich/Layout.lua): "Creature health
-- bar: Bottom" is the creature card's bar in a section at the end, and other
-- addons' lines "Mixed in" are the addons piece moved in with each card's own
-- rows ("Hidden": that piece hidden on every card). A profile that changed
-- either keeps its look. Runs once per profile (tipUpgrade 2), after the
-- sizes' step, on full or sparse settings alike.
ns.MIXED_SPOT = { player = "target", mob = "facts", item = "effects", spell = "tiles" }
function ns.UpgradeLayout(p)
    if type(p) ~= "table" or type(p.modules) ~= "table" then return end
    local t = p.modules.Tooltip
    if type(t) ~= "table" or (tonumber(t.tipUpgrade) or 0) >= 2 then return end
    ns.UpgradeSizes(p)
    t.tipUpgrade = 2
    local Layout = ns.RichLayout
    local mobBar, lines = t.mobBar, t.addonLines
    t.mobBar, t.addonLines = nil, nil
    if type(t.layout) ~= "table" then t.layout = {} end
    local function edit(kind, fn)
        local text = t.layout[kind]
        local sections = Layout.Decode(type(text) == "string" and text ~= "" and text or Layout.DefaultText(kind))
        t.layout[kind] = Layout.Encode(fn(sections))
    end
    if mobBar == "bottom" then
        edit("mob", function(sections)
            local out = Layout.Without(sections, "health")
            -- At the end of the card, before other addons' own area.
            local at = #out + 1
            for i, sec in ipairs(out) do
                if #sec == 1 and sec[1] == "addons" then at = i end
            end
            table.insert(out, at, { "health" })
            return out
        end)
    end
    if lines == "mixed" then
        for _, kind in ipairs(Layout.KINDS) do
            edit(kind, function(sections)
                local out = Layout.Without(sections, "addons")
                local s = Layout.Find(out, ns.MIXED_SPOT[kind])
                if s then table.insert(out[s], "addons") else out[#out + 1] = { "addons" } end
                return out
            end)
        end
    elseif lines == "hidden" then
        if type(t.pieces) ~= "table" then t.pieces = {} end
        for _, kind in ipairs(Layout.KINDS) do
            if type(t.pieces[kind]) ~= "table" then t.pieces[kind] = {} end
            t.pieces[kind].addons = false
        end
    end
    if next(t.layout) == nil then t.layout = nil end
end
DaylightUI.DB.RegisterUpgrade(ns.UpgradeLayout)
