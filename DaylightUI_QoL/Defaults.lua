-- The quality-of-life helpers' defaults. Each feature adds its own keys.

local _, ns = ...

ns.features = {}

-- CVars a QoL switch takes over. The player's own value is saved per account
-- (DB.Root().qolCVars) when the switch is turned on and restored when it's turned
-- off. nil means nothing was saved, and the caller uses the game's default.
local function kept()
    local root = DaylightUI.DB.Root()
    if type(root.qolCVars) ~= "table" then root.qolCVars = {} end
    return root.qolCVars
end

function ns.KeepCVar(name)
    local t = kept()
    if t[name] ~= nil or type(GetCVar) ~= "function" then return end
    local ok, v = pcall(GetCVar, name)
    if ok and v ~= nil then t[name] = tostring(v) end
end

-- What's kept, still kept: for a switch that puts it back now and then itself.
function ns.KeptCVar(name) return kept()[name] end

function ns.GiveBackCVar(name)
    local t = kept()
    local v = t[name]
    t[name] = nil
    return v
end

ns.DEFAULTS = {
    autoDelete = true,      -- fill in DELETE when destroying a good item
    fastLoot = false,       -- pick up every slot at once when auto loot is on
    trainAll = true,        -- a Train all button at class trainers
    afkScreen = true,       -- the soft AFK screen: UI fades away, your character beside a card (Afk.lua)
    questAccept = false,    -- accept quests when an NPC offers them
    questTurnIn = false,    -- hand in finished quests (unless a reward must be picked)
    skipCinematics = false, -- end cutscenes and movies at once (Shift to watch)
    hideTutorials = false,  -- turn off the game's new-player tips (changes a game setting)
    skipGossip = false,     -- press an NPC's only service button (vendor, flight...)
    cameraZoom = 1,         -- max camera distance, share of the game's normal one (changes a game setting)
    lootSparkles = false,   -- outline mode off so lootable quest objects sparkle (changes game settings)
    -- A ring round the mouse cursor (CursorRing.lua): the accent's
    -- gradient, a breathing glow, light running round it, the global
    -- cooldown and your casts.
    cursorRing = false,
    cursorRingWhen = "always",  -- always | combat
    cursorRingSize = 40,
    cursorRingColor = "accent", -- accent | class | custom
    cursorRingCustom = { 1, 1, 1 },
    cursorRingAlpha = 0.8,
    cursorRingGcd = true,
    cursorRingFlash = true,     -- the ring flashes as the global cooldown ends
    cursorRingCast = true,      -- your casts and channels fill a ring outside it
    cursorRingGlow = true,
    cursorRingMotion = "comet", -- comet | breathe | still
    cursorRingTrail = false,
    objectGlow = true,      -- chests, quest objects and your bobber light up as you come near (Glow.lua; changes game settings while on)
    objectGlowLook = "sweep",  -- sweep | frame | daybreak | sunrise (Glow.LOOKS)
    objectGlowColor = "accent", -- accent | object: each kind its own color (Glow.KINDS)
    objectGlowHeight = 110,    -- how far under the object's name its light sits, once in reach
    objectGlowQuest = true,
    objectGlowChest = true,
    objectGlowBobber = true,
    objectGlowOther = false,   -- anything else you can use: doors, levers, mailboxes
    objectGlowFight = false,   -- lights in a fight too
    objectGlowInstance = false, -- lights in dungeons, raids and battlegrounds too
    keepTracking = true,    -- turn tracking (Find Minerals...) back on when the game drops it (Tracking.lua)
    quietErrors = true,     -- hide the red "not enough rage / not ready / out of range / no target" spam
    errorSound = true,      -- a soft "nope" in place of those errors' voice lines (Errors.lua)
    errorText = true,       -- the errors that still show, in our font and colors, easing in and out (ErrorText.lua)
    lootFeed = true,        -- what you loot slides in as ribbons at the bottom right (LootFeed.lua)
    lootFeedHold = 5,       -- seconds each loot feed line stays
    lootFeedTogether = false, -- every line leaves with the newest one instead of each on its own
    lootFeedItems = true,   -- what shows: items, money, skill-ups
    lootFeedMoney = true,
    lootFeedSkills = true,
    lootFeedQuality = "poor", -- lowest item quality shown (LootFeed.QUALITY)
    lootFeedMax = 6,        -- lines at once
    lootFeedGrow = "up",    -- up: newest at the bottom, older above; down: newest on top
    lootFeedFlip = false,   -- mirrored left and right: lined up on the left, in from the left
    lootFeedTextSize = 13,  -- the name's size (Style.SIZE.body)
    lootFeedFont = DaylightUI.Media.GENERAL, -- its own font, or General's (Media slot qol.loot.font)
    lootFeedNameColor = "quality", -- quality | white
    lootFeedBack = true,    -- the ribbon's background
    lootFeedAlphaOwn = false, -- off: as solid as every window (General windowAlpha)
    lootFeedAlpha = 0.85,
    lootFeedBorder = true,
    lootFeedSlant = true,   -- the ribbons' angled ends; off = straight
    lootFeedSlantSide = "both", -- which ends are angled: both | left | right
    lootFeedBorderColor = "normal", -- normal | quality | accent | custom
    lootFeedBorderCustom = { DaylightUI.Style.ACCENT[1], DaylightUI.Style.ACCENT[2], DaylightUI.Style.ACCENT[3] },
    lootFeedShine = true,   -- the light that runs across a new line
    flightTimer = true,     -- a bar with the time left while on a flight path
    flightTimerSlant = true, -- its angled end; off = straight
    fishClick = false,      -- a quick right-click on the world casts Fishing with a pole in hand (Fishing.lua)
    fishScene = true,       -- water along the bottom while the line is in, a splash on the catch (Fishing.lua)
    forgeScene = true,      -- an anvil and a molten tide while you smith, sparks on each item (Fishing.lua)
    brewScene = true,       -- a flask and a green tide while you brew, bubbles rising through it (Fishing.lua)
    workshopScene = true,   -- brass gears and a brass tide while you make engineering things (Fishing.lua)
    sewingScene = true,     -- a spool, a tide of cloth and a growing seam while you tailor (Fishing.lua)
    levelUp = true,         -- the level-up animation, in place of the game's banner (LevelUp.lua)
    zoneTitle = true,       -- the zone title animation, in place of the game's zone text (ZoneTitle.lua)
    repBanner = true,       -- a reputation standing gone up shows at the top of the screen (RepBanner.lua)
    campfire = true,        -- sitting by a campfire warms the screen and hushes bars and unit frames (Campfire.lua)
    campfireAll = true,     -- the campfire fades every area of ours (buffs, info panel, quests, chat...), not just bars and unit frames
    campfireRest = 10,      -- minutes after the flare before a new Welcoming Campfire fades the UI again (0 = every minute)
    campfireChat = true,    -- the campfire floats the chat: panel and tabs away, the lines stay (Chat.FloatWanted)
}
