-- The quality-of-life options page, as data. Each feature adds its own group.

local _, ns = ...

-- Its top end is the client's own limit, read whenever the slider is drawn or
-- refreshed (Camera.lua), so a slider drawn by a search or in a fight catches up.
ns.CAMERA_SLIDER = setmetatable({ type = "slider", key = "cameraZoom", label = "Max camera distance",
    min = 0.5, step = 0.05, unit = "%",
    desc = "How far the camera can zoom out. 100% is the game's normal limit; the far right end is as far as this client allows. At 100% the game's own setting is left alone." },
    { __index = function(_, k) if k == "max" then return ns.Camera.SliderTop() end end })

-- The loot feed page's pieces.
local LOOT_MOVER = "qol.loot"
local function lootOff(get) return get("lootFeed") ~= true end
local QUALITY = { poor = "Poor (gray) and up", common = "Common (white) and up", uncommon = "Uncommon (green) and up",
    rare = "Rare (blue) and up", epic = "Epic (purple) and up" }
local QUALITY_ORDER = { "poor", "common", "uncommon", "rare", "epic" }
local GROW = { up = "Up: newest at the bottom", down = "Down: newest on top" }
local NAME_COLOR = { quality = "Quality color", white = "White" }
local STYLE = { fade = "Fade away", log = "Keep as a log" }
local function logOn(get) return get("lootFeedStyle") == "log" end
-- Only a log stays on screen, so only a log fades like the rest of the UI.
local function logFadeOff(get) return lootOff(get) or not logOn(get) end
local logFade = DaylightUI.Fade.Card("lootFeedFade.", nil, logFadeOff, "Loot feed")
for _, item in ipairs(logFade.items) do
    item.hidden = logFadeOff
    -- The log doesn't come back in a fight, only for new loot.
    if item.key == "lootFeedFade.mode" then
        item.desc = "Fade out of combat: fades a while after a fight and comes back in one. Fade in combat: fades a while into a fight and comes back after. Fade until mouseover: stays faded until your mouse is over it. Only when something changes: gone until you loot something or a skill goes up, then back for a moment."
    end
end
local BORDER_COLOR = { normal = "Daylight UI", quality = "Quality color", accent = "Accent color", custom = "One color" }
local lootLook = DaylightUI.Options.LookRows("lootFeedFrame", function(get) return get("lootFeed") ~= true end, nil, {
    { type = "dropdown", key = "lootFeedBorderColor", label = "Loot feed border color", values = BORDER_COLOR,
      order = { "normal", "quality", "accent", "custom" },
      desc = "The Daylight UI border, the item's quality color, your accent color (General > Appearance), or a color you pick." },
    { type = "color", key = "lootFeedBorderCustom", label = "Custom loot feed border color",
      desc = "The border color of every loot feed line when Loot feed border color is One color.",
      disabled = function(get) return get("lootFeedBorderColor") ~= "custom" end },
})

-- The zone title page's pieces.
local ZONE_MOVER = "qol.zone"
local function zoneOff(get) return get("zoneTitle") ~= true end
local ZONE_COLOR = { accent = "Accent color", zone = "The zone's PvP color", white = "White", custom = "One color" }
local LINE_COLOR = { name = "Same as the name", accent = "Accent color", zone = "The zone's PvP color", white = "White", custom = "One color" }
local SUB_COLOR = { label = "Daylight UI tan", name = "Same as the name", accent = "Accent color", white = "White", custom = "One color" }
local PVP_COLOR = { zone = "The zone's PvP color", label = "Daylight UI tan", white = "White", custom = "One color" }
-- A color dropdown and its "One color" picker under it.
local function zoneColor(key, label, values, order, desc, customLabel, customDesc)
    return { type = "dropdown", key = key, since = "2.2.5", label = label, values = values, order = order,
             disabled = zoneOff, desc = desc },
           { type = "color", key = key .. "Custom", since = "2.2.5", label = customLabel, desc = customDesc,
             disabled = function(get) return zoneOff(get) or get(key) ~= "custom" end }
end
local zoneColors = {}
for _, row in ipairs({
    { "zoneTitleColor", "Zone name color", ZONE_COLOR, { "accent", "zone", "white", "custom" },
      "The zone's name: your accent color (General > Appearance), the zone's PvP color (green friendly, red hostile, amber contested), white, or a color you pick.",
      "Custom zone name color", "The name's color when Zone name color is One color." },
    { "zoneTitleLineColor", "Zone title line color", LINE_COLOR, { "name", "accent", "zone", "white", "custom" },
      "The thin line under the name, and the light, glow and diamond with it. Same as the name follows the name's color.",
      "Custom zone title line color", "The line's color when Zone title line color is One color." },
    { "zoneTitleSubColor", "Subzone color", SUB_COLOR, { "label", "name", "accent", "white", "custom" },
      "The subzone under the name, like Goldshire, and a subzone shown on its own.",
      "Custom subzone color", "The subzone's color when Subzone color is One color." },
    { "zoneTitlePvPColor", "PvP status color", PVP_COLOR, { "zone", "label", "white", "custom" },
      "Contested, Sanctuary, Horde or Alliance territory: in the zone's own PvP color, tan, white, or a color you pick.",
      "Custom PvP status color", "The PvP status's color when PvP status color is One color." },
}) do
    local a, b = zoneColor(row[1], row[2], row[3], row[4], row[5], row[6], row[7])
    zoneColors[#zoneColors + 1] = a
    zoneColors[#zoneColors + 1] = b
end
local zoneFont = DaylightUI.Options.FontRow("zoneTitleFont", "Zone title font", "Every text in the zone title", zoneOff)
zoneFont.since = "2.2.5"

-- The flight timer page's pieces.
local FLIGHT_MOVER, WELCOME_MOVER = "qol.flight", "qol.welcome"
local function flightOff(get) return get("flightTimer") ~= true end
local function welcomeOff(get) return flightOff(get) or get("flightWelcome") == false end
local FLIGHT_BORDER = { normal = "Daylight UI", accent = "Accent color", custom = "One color" }
local flightLook = DaylightUI.Options.LookRows("flightFrame", flightOff, nil, {
    { type = "dropdown", key = "flightBorderColor", label = "Flight timer border color", values = FLIGHT_BORDER,
      order = { "normal", "accent", "custom" },
      desc = "The Daylight UI border, your accent color (General > Appearance), or a color you pick." },
    { type = "color", key = "flightBorderCustom", label = "Custom flight timer border color",
      desc = "The flight timer's border color when Flight timer border color is One color.",
      disabled = function(get) return get("flightBorderColor") ~= "custom" end },
})

-- A loot feed end's menu (straight, / or \). Its lean is kept against the
-- lean it has in the pair, which follows Flip the loot feed, so a mirrored
-- feed keeps its look; the menu shows the shape it has now.
local function lootEnd(end_)
    local on = end_ == "left" and "lootFeedLeft" or "lootFeedRight"
    local flip = end_ == "left" and "lootFeedFlipLeft" or "lootFeedFlipRight"
    local function get(k) return DaylightUI:Get("QoL", k) end
    local function glyph(isOn, isFlip, mirrored)
        return DaylightUI.Style.EndGlyph(end_, isOn ~= false, ns.LootFeed.FlipsAt(end_, mirrored == true, isFlip))
    end
    return { type = "dropdown", key = on, alsoKeys = { flip }, label = "Loot feed " .. end_ .. " end",
        values = DaylightUI.Options.END_VALUES, order = DaylightUI.Options.END_ORDER,
        desc = "Straight, or angled either way. On the right end / puts the top corner out and \\ the bottom one; on the left end it's the other way round. Each end is set on its own.",
        disabled = function(g) return g("lootFeed") ~= true end,
        get = function() return glyph(get(on), get(flip), get("lootFeedFlip")) end,
        set = function(v)
            local isOn, under = DaylightUI.Style.EndFromGlyph(end_, v)
            -- Kept against the usual lean: flipped when it differs from it.
            local usual = ns.LootFeed.FlipsAt(end_, get("lootFeedFlip") == true, false)
            DaylightUI:Set("QoL", flip, isOn and (under ~= usual) or false)
            DaylightUI:Set("QoL", on, isOn)
        end,
        default = function()
            local d = ns.DEFAULTS
            return glyph(d[on], d[flip], d.lootFeedFlip)
        end }
end

ns.OPTIONS = { pages = {
    { id = "qol", label = "Quality of Life",
      desc = "Small helpers for looting, quests, trainers and more.",
      onShow = function() ns.Camera.Ask() end,
      groups = {
        { label = "Items and loot", items = {
            { type = "toggle", key = "autoDelete", label = "Type DELETE for me",
              desc = "When you destroy a good item, the confirmation box is filled in. You still press the button." },
            { type = "toggle", key = "fastLoot", label = "Faster looting",
              desc = "When auto loot is on, everything is picked up at once instead of one item at a time." },
            { type = "toggle", key = "lootSparkles", label = "Show quest item sparkles",
              desc = "Lootable quest objects sparkle, and so do quest givers (the game has no setting for one alone). The game only sparkles with its outline around what you point at off, so this keeps that outline off. Turning this off puts the outline back; the sparkle may stay until you restart the game." },
        } },
        { label = "Cursor ring", items = {
            { type = "toggle", key = "cursorRing", label = "Ring around the cursor",
              desc = "A ring follows your mouse cursor, so it's easy to find in a busy fight." },
            { type = "dropdown", key = "cursorRingWhen", label = "When the cursor ring shows",
              values = { always = "Always", combat = "In combat" }, order = { "always", "combat" },
              desc = "All the time, or only during a fight.",
              disabled = function(get) return get("cursorRing") ~= true end },
            { type = "slider", key = "cursorRingSize", label = "Cursor ring size", min = 24, max = 120, step = 2, unit = "px",
              desc = "How wide the ring is.", disabled = function(get) return get("cursorRing") ~= true end },
            { type = "dropdown", key = "cursorRingColor", label = "Cursor ring color",
              values = { accent = "Accent color", class = "Class color", custom = "One color" }, order = { "accent", "class", "custom" },
              desc = "Your accent color (a gradient accent runs across the ring), your class's colors, or one you pick.",
              disabled = function(get) return get("cursorRing") ~= true end },
            { type = "color", key = "cursorRingCustom", label = "Custom cursor ring color",
              desc = "The ring's color when Cursor ring color is One color.",
              hidden = function(get) return get("cursorRingColor") ~= "custom" end,
              disabled = function(get) return get("cursorRing") ~= true end },
            { type = "slider", key = "cursorRingAlpha", label = "Cursor ring opacity", min = 0.2, max = 1, step = 0.05, unit = "%",
              desc = "How solid the ring is.", disabled = function(get) return get("cursorRing") ~= true end },
            { type = "toggle", key = "cursorRingGcd", label = "Cursor ring global cooldown",
              desc = "A thin ring just outside the cursor's runs down after each spell, so you see when the next one is ready.",
              disabled = function(get) return get("cursorRing") ~= true end },
            { type = "toggle", key = "cursorRingFlash", label = "Flash when the global cooldown ends",
              desc = "The global cooldown's ring lights up the moment your next spell is ready.",
              disabled = function(get) return get("cursorRing") ~= true or get("cursorRingGcd") == false end },
            { type = "toggle", key = "cursorRingCast", label = "Casts on the cursor ring",
              desc = "Your casts and channels fill a ring further out, with a spark at the tip.",
              disabled = function(get) return get("cursorRing") ~= true end },
            { type = "toggle", key = "cursorRingGlow", label = "Cursor ring glow",
              desc = "A soft light around the ring.",
              disabled = function(get) return get("cursorRing") ~= true end },
            { type = "dropdown", key = "cursorRingMotion", label = "Cursor ring motion",
              values = { comet = "Light runs round it", breathe = "Breathes", still = "Still" },
              order = { "comet", "breathe", "still" },
              desc = "A light running round the ring, a slow breath, or no movement.",
              disabled = function(get) return get("cursorRing") ~= true end },
            { type = "toggle", key = "cursorRingTrail", label = "Cursor trail",
              desc = "A trail of light follows the cursor as it moves.",
              disabled = function(get) return get("cursorRing") ~= true end },
        } },
        { label = "Quests and NPCs", items = {
            { type = "toggle", key = "questAccept", label = "Accept quests automatically",
              desc = "Quests are accepted the moment an NPC offers them. Hold Shift to talk to the NPC normally." },
            { type = "toggle", key = "questTurnIn", label = "Turn in quests automatically",
              desc = "Finished quests are handed in unless you must pick a reward. Hold Shift to talk to the NPC normally." },
            { type = "toggle", key = "skipGossip", label = "Skip NPC dialogue",
              desc = "When an NPC has only one thing to offer (a vendor, flight master, banker or trainer) and no quests, its window opens straight away. Hold Shift to see the dialogue." },
            { type = "toggle", key = "trainAll", label = "Train All button on the game's trainer",
              disabled = function() return DaylightUI.npcOwnTrainer == true end,
              desc = "A button on the game's class trainer window that learns every spell you can afford in one click. The Daylight UI style NPC window's trainer page has its own, so this is for the game's window (NPC window > Trainer window off)." },
        } },
        { label = "Level up, zone and reputation", items = {
            { type = "toggle", key = "levelUp", label = "Level-up animation",
              desc = "A warm line of light spreads across the top of the screen, your new level rolls in and what you gained fades in under it, in place of the game's banner. Follows Motion effects (General > Appearance)." },
            { type = "button", label = "Preview the level-up animation", text = "Preview",
              desc = "Plays it now. Also /dui levelup.",
              func = function() if ns.LevelUp then ns.LevelUp.Preview() end end },
            { type = "toggle", key = "zoneTitle", label = "Zone title animation",
              desc = "A new zone's name rises in at the top of the screen with a thin line under it, then the subzone and PvP status; a subzone shows just its name, small. It replaces the game's zone text. Its text, colors and size are on the Zone title page. Follows Motion effects (General > Appearance)." },
            { type = "button", label = "Preview the zone title", text = "Preview",
              desc = "Plays it now. Also /dui zone.",
              func = function() if ns.ZoneTitle then ns.ZoneTitle.Preview() end end },
            { type = "toggle", key = "repBanner", label = "Reputation banner",
              desc = "When a reputation goes up a standing, like Friendly to Honored, the new standing rises in at the top of the screen in its color, with the faction's name and a bar showing how far into it you are. Follows Motion effects (General > Appearance)." },
            { type = "button", label = "Preview the reputation banner", text = "Preview",
              desc = "Plays it now. Also /dui rep.",
              func = function() if ns.RepBanner then ns.RepBanner.Preview() end end },
        } },
        { label = "Resting", items = {
            { type = "toggle", key = "afkScreen", label = "Soft AFK screen",
              desc = "When you go away, the world dims, the UI fades and your character stands beside a card with your name, zone, rested XP and a fun fact. Move, click or press any key to come back. Never in combat, boss fights, keystones or PvP matches." },
            { type = "button", label = "Preview the AFK screen", text = "Preview",
              desc = "Shows the AFK screen now. Click or press any key to close it. Also /dui afk.",
              func = function() if ns.Afk then ns.Afk.Preview() end end },
            { type = "toggle", key = "campfire", label = "Campfire glow",
              desc = "Sitting by a campfire warms the screen with firelight and embers, a soft crackle plays, and your action bars and unit frames fade away. Move, target or cast and everything comes back; a fight brings it back at once. The sounds follow Soft UI sounds (General > Appearance)." },
            { type = "toggle", key = "campfireAll", label = "Fade everything at the campfire",
              desc = "Your buffs, minimap and info panel, quest tracker and chat fade away too, so only the fire and the world are left. Point at any of them to see it.",
              disabled = function(get) return get("campfire") ~= true end },
            { type = "toggle", key = "campfireChat", label = "Float the chat at the campfire",
              desc = "Only the chat's messages stay over the world, each fading after a while, like Chat hides set to Always (Chat page). It stays even with Fade everything at the campfire on.",
              disabled = function(get) return get("campfire") ~= true end },
            { type = "slider", key = "campfireRest", label = "Campfire rest time", min = 0, max = 30, step = 1,
              desc = "Once you're warmed by the fire, sitting on doesn't fade your UI away again for this many minutes, so you can chat by the fire. 0 fades it every minute.",
              disabled = function(get) return get("campfire") ~= true end },
            { type = "button", label = "Preview the campfire glow", text = "Preview",
              desc = "Plays it now; move to end it. Also /dui campfire.",
              func = function() if ns.Campfire then ns.Campfire.Preview() end end },
            { type = "toggle", key = "sleepingBag", since = "1.7.2", label = "Sleeping bag timer",
              desc = "While you rest in a sleeping bag, a timer near the bottom of the screen counts down until Well-Rested is full (one stack a minute, three in all), so you can see it with your UI faded at the campfire." },
            { type = "button", label = "Preview the sleeping bag timer", text = "Preview",
              desc = "Shows it now; move to end it. Also /dui sleepingbag.",
              func = function() if ns.Campfire then ns.Campfire.PreviewBag() end end },
        } },
        { label = "Error messages", items = {
            { type = "toggle", key = "quietErrors", label = "Quiet error messages",
              desc = "Hides the red text and voice line from pressing a button too soon: not enough rage, mana or energy, not ready yet, out of range, no target. The useful ones still show: bags full, interrupted, line of sight, quest messages." },
            { type = "toggle", key = "errorSound", label = "Soft sound for quiet errors",
              desc = "Those quiet errors play one soft, low tick in place of the voice line, never in a burst. Follows Soft UI sounds (General > Appearance).",
              disabled = function(get) return get("quietErrors") ~= true end },
            { type = "toggle", key = "errorText", label = "Error text in Daylight UI style",
              desc = "The lines in the middle of the screen (interrupted, bags full, a new area found) in your font, errors in a soft red, easing in and out. Move them with /dui unlock. Turn it off to see the game's own red and yellow text." },
        } },
        { label = "Game and camera", items = {
            { type = "toggle", key = "skipCinematics", label = "Skip cinematics",
              desc = "Cutscenes and intro movies end at once. Hold Shift as one starts to watch it." },
            { type = "toggle", key = "hideTutorials", invert = true, label = "Show tutorial tips",
              desc = "The game's new-player tips (the game setting 'Tutorials'). When off, the game's tutorial tips are switched off." },
            ns.CAMERA_SLIDER,
            { type = "toggle", key = "keepTracking", label = "Keep tracking on",
              desc = "Tracking from a spell, like Find Minerals, comes back after you log out, change zones or die. Turn it off yourself and it stays off." },
            { type = "toggle", key = "fishClick", label = "Right-click to fish",
              desc = "With a fishing pole equipped, a quick right-click on the world casts Fishing. With no bait on the pole, the first click puts on the best bait in your bags. Holding the button still turns the camera, and clicking an NPC, an object or the bobber works as usual. Hold Shift, Ctrl or Alt to skip the cast." },
        } },
      } },
    { id = "loot", label = "Loot feed",
      desc = "What you loot and your skill-ups, sliding in as ribbons at the bottom right.",
      groups = {
        { label = "Loot feed", items = {
            { type = "toggle", key = "lootFeed", label = "Loot feed",
              desc = "What you loot slides in at the bottom right of the screen in its quality color, more of the same adding to its count, and fades a few seconds later. Point at a line for the item's tooltip. Move it with /dui unlock." },
            { type = "button", label = "Preview the loot feed", text = "Preview",
              desc = "Plays it now. Also /dui loot.", disabled = lootOff,
              func = function() if ns.LootFeed then ns.LootFeed.Preview() end end },
            { type = "toggle", key = "lootFeedItems", label = "Show items in the loot feed", disabled = lootOff,
              desc = "Items you loot, create, buy or get from a quest." },
            { type = "dropdown", key = "lootFeedQuality", label = "Loot feed lowest quality", values = QUALITY, order = QUALITY_ORDER,
              desc = "Items below this quality don't show, like gray junk.",
              disabled = function(get) return get("lootFeed") ~= true or get("lootFeedItems") == false end },
            { type = "toggle", key = "lootFeedMoney", label = "Show money in the loot feed", disabled = lootOff,
              desc = "Gold you loot adds up on one line." },
            { type = "toggle", key = "lootFeedSkills", label = "Show skill-ups in the loot feed", disabled = lootOff,
              desc = "A skill going up shows its new rank, out of its cap: Tailoring 152 / 225. More skill-ups move the same line on." },
        } },
        { label = "Timing", items = {
            { type = "dropdown", key = "lootFeedStyle", label = "Loot feed style", values = STYLE, order = { "fade", "log" },
              disabled = lootOff,
              desc = "Fade away: each line leaves a few seconds after your last loot of it. Keep as a log: lines stay, like a chat window for your loot. Scroll over it with the mouse wheel to see older loot; it goes back to the newest a few seconds after your mouse leaves. The last 50 are kept for this character, after a reload too." },
            { type = "slider", key = "lootFeedHold", label = "Loot feed line time", min = 2, max = 20, step = 1,
              desc = "How many seconds each line stays after your last loot of it. In a log, more of the same within this time adds to its line instead of a new one.", disabled = lootOff },
            { type = "toggle", key = "lootFeedTogether", label = "Loot feed lines leave together",
              disabled = function(get) return lootOff(get) or logOn(get) end,
              desc = "Every line stays until the newest one's time is up, then they all go. When off, each line leaves on its own." },
            { type = "button", label = "Clear the loot log", text = "Clear", confirm = true, disabled = lootOff,
              hidden = function(get) return not logOn(get) end,
              desc = "Empties the loot log for this character.",
              func = function() if ns.LootFeed then ns.LootFeed.Clear() end end },
        } },
        logFade,
        { label = "Size", items = {
            { type = "slider", label = "Loot feed scale", min = 0.5, max = 2, step = 0.05, unit = "x", disabled = lootOff,
              desc = "The whole feed. Also the mouse wheel over its handle in /dui unlock.",
              get = function() return DaylightUI.Movers.PieceScale(LOOT_MOVER) end,
              set = function(v) DaylightUI.Movers.SetPieceScale(LOOT_MOVER, v) end,
              default = function() return 1 end },
            { type = "slider", key = "lootFeedMax", label = "Loot feed max shown", min = 1, max = 10, step = 1, disabled = lootOff,
              desc = "Lines at once; the oldest makes room for a new one." },
            { type = "dropdown", key = "lootFeedGrow", label = "Loot feed grow direction", values = GROW, order = { "up", "down" },
              disabled = lootOff, desc = "Where new lines come in." },
            { type = "toggle", key = "lootFeedFlip", since = "1.5.1.1", label = "Flip the loot feed left and right", disabled = lootOff,
              desc = "Mirrors the feed: lines line up on the left, slide in from the left and leave to the right, with the icon at the right end. Handy when the feed sits on the left of the screen. When off, lines line up on the right." },
        } },
        { label = "Text", items = {
            DaylightUI.Options.FontRow("lootFeedFont", "Loot feed font", "Every text in the loot feed", lootOff),
            { type = "slider", key = "lootFeedTextSize", label = "Loot feed text size", min = 10, max = 18, step = 1, disabled = lootOff,
              desc = "How big the item names, counts and skill-up text are in the loot feed." },
            { type = "dropdown", key = "lootFeedNameColor", label = "Loot feed name color", values = NAME_COLOR, order = { "quality", "white" },
              disabled = lootOff, desc = "Item names in their quality color, or all white. The icon's edge keeps the quality color." },
        } },
        { label = "Background and border", items = {
            { type = "toggle", key = "lootFeedBack", label = "Loot feed background", disabled = lootOff,
              desc = "The dark ribbon behind each line. When off, only the icon and text show." },
            lootEnd("left"),
            lootEnd("right"),
            { type = "toggle", key = "lootFeedShine", label = "Light across new loot feed lines", disabled = lootOff,
              desc = "A soft light in the line's color runs across it as it comes in or adds up." },
        } },
        { label = "Borders and background", items = lootLook },
      } },
    { id = "flight", label = "Flight timer",
      desc = "Where you're going and the time left while on a flight path, and a welcome when you land.",
      groups = {
        { label = "Flight timer", items = {
            { type = "toggle", key = "flightTimer", label = "Flight timer",
              desc = "On a flight path, where you're going and the time left float near the top of the screen, with the route and its stops as a line. Every route has a time from your first flight, and your own flights keep it exact. Move it with /dui unlock." },
            { type = "toggle", key = "flightWelcome", label = "Welcome on landing", disabled = flightOff,
              desc = "When you land, \"Welcome to\" and the place's name slide in at the top of the screen, then fade away. Move it with /dui unlock." },
            { type = "button", label = "Preview the welcome on landing", text = "Preview", disabled = welcomeOff,
              desc = "Plays it now. Also /dui landing.",
              func = function() if ns.Flight then ns.Flight.PreviewWelcome() end end },
        } },
        { label = "What shows", items = {
            { type = "toggle", key = "flightLabel", label = "Show Flying to", disabled = flightOff,
              desc = "The small \"Flying to\" above the destination." },
            { type = "toggle", key = "flightLine", label = "Flight timer route line", disabled = flightOff,
              desc = "The line that fills as you fly, with a light at its front. When off, only the text shows." },
            { type = "toggle", key = "flightStops", label = "Flight timer stops",
              desc = "A dot on the route line for each flight point the flight passes, lit once you're past it.",
              disabled = function(get) return flightOff(get) or get("flightLine") == false end },
            { type = "toggle", key = "flightFrom", label = "Show where you flew from", disabled = flightOff,
              desc = "The flight point you left, under the start of the line." },
            { type = "toggle", key = "flightTime", label = "Flight timer time left", disabled = flightOff,
              desc = "The time until you land, under the end of the line. It turns amber in the last seconds." },
        } },
        { label = "Size", items = {
            { type = "slider", label = "Flight timer scale", min = 0.5, max = 2, step = 0.05, unit = "x", disabled = flightOff,
              desc = "The whole flight timer. Also the mouse wheel over its handle in /dui unlock.",
              get = function() return DaylightUI.Movers.PieceScale(FLIGHT_MOVER) end,
              set = function(v) DaylightUI.Movers.SetPieceScale(FLIGHT_MOVER, v) end,
              default = function() return 1 end },
            { type = "slider", key = "flightWidth", label = "Flight timer width", min = 200, max = 520, step = 10, unit = "px",
              disabled = flightOff, desc = "How wide the flight timer and its route line are." },
            { type = "slider", label = "Landing welcome scale", min = 0.5, max = 2, step = 0.05, unit = "x", disabled = welcomeOff,
              desc = "The whole landing welcome. Also the mouse wheel over its handle in /dui unlock.",
              get = function() return DaylightUI.Movers.PieceScale(WELCOME_MOVER) end,
              set = function(v) DaylightUI.Movers.SetPieceScale(WELCOME_MOVER, v) end,
              default = function() return 1 end },
        } },
        { label = "Text", items = {
            DaylightUI.Options.FontRow("flightFont", "Flight timer font", "Every text in the flight timer and the welcome on landing", flightOff),
            { type = "slider", key = "flightNameSize", label = "Flight destination text size", min = 14, max = 36, step = 1,
              disabled = flightOff, desc = "How big the name of where you're going is." },
            { type = "slider", key = "flightTextSize", label = "Flight timer small text size", min = 10, max = 18, step = 1,
              disabled = flightOff, desc = "How big \"Flying to\" and where you flew from are." },
            { type = "slider", key = "flightTimeSize", label = "Flight timer time text size", min = 10, max = 28, step = 1,
              disabled = flightOff, desc = "How big the time left is." },
            { type = "slider", key = "flightWelcomeSize", label = "Landing welcome text size", min = 18, max = 48, step = 1,
              disabled = welcomeOff, desc = "How big the place's name is in the welcome on landing." },
        } },
        { label = "Background and border", items = {
            { type = "toggle", key = "flightBack", label = "Flight timer background", disabled = flightOff,
              desc = "The dark box behind the flight timer. When off, the text and line float on their own." },
            { type = "toggle", key = "flightAccentLine", label = "Flight timer accent line", disabled = flightOff,
              desc = "A thin line in your accent color along the top of the box." },
        } },
        { label = "Borders and background", items = flightLook },
      } },
    { id = "zone", label = "Zone title",
      desc = "The zone's name at the top of the screen when you arrive somewhere new.",
      groups = {
        { label = "Zone title", items = {
            { type = "toggle", key = "zoneTitle", label = "Zone title animation",
              desc = "A new zone's name rises in at the top of the screen with a thin line under it, then the subzone and PvP status. It replaces the game's zone text. Move it with /dui unlock." },
            { type = "button", label = "Preview the zone title", text = "Preview", disabled = zoneOff,
              desc = "Plays it now. Also /dui zone.",
              func = function() if ns.ZoneTitle then ns.ZoneTitle.Preview() end end },
        } },
        { label = "What shows", items = {
            { type = "toggle", key = "zoneTitleSub", since = "2.2.5", label = "Show the subzone", disabled = zoneOff,
              desc = "The part of the zone you're in, like Goldshire, under the zone's name." },
            { type = "toggle", key = "zoneTitlePvP", since = "2.2.5", label = "Show the PvP status", disabled = zoneOff,
              desc = "Contested, Sanctuary, Horde or Alliance territory under the name, in its own color." },
            { type = "toggle", key = "zoneTitleSubAlone", since = "2.2.5", label = "Show subzone changes",
              desc = "Walking into a new part of the same zone shows its name, small. When off, only a new zone shows the title.",
              disabled = function(get) return zoneOff(get) or get("zoneTitleSub") == false end },
            { type = "toggle", key = "zoneTitleCaps", since = "2.2.5", label = "Zone name in capitals", disabled = zoneOff,
              desc = "Writes the zone's name in capital letters." },
            { type = "slider", key = "zoneTitleHold", since = "2.2.5", label = "Zone title duration", min = 1, max = 8, step = 0.5, unit = "s",
              disabled = zoneOff, desc = "How long the whole title stays before it drifts away." },
        } },
        { label = "Colors", items = zoneColors },
        { label = "Size and text", items = {
            { type = "slider", since = "2.2.5", label = "Zone title scale", min = 0.5, max = 2, step = 0.05, unit = "x", disabled = zoneOff,
              desc = "The whole zone title. Also the mouse wheel over its handle in /dui unlock.",
              get = function() return DaylightUI.Movers.PieceScale(ZONE_MOVER) end,
              set = function(v) DaylightUI.Movers.SetPieceScale(ZONE_MOVER, v) end,
              default = function() return 1 end },
            zoneFont,
            { type = "slider", key = "zoneTitleNameSize", since = "2.2.5", label = "Zone name text size", min = 16, max = 48, step = 1,
              disabled = zoneOff, desc = "How big the zone's name is." },
            { type = "slider", key = "zoneTitleSubSize", since = "2.2.5", label = "Subzone text size", min = 10, max = 24, step = 1,
              disabled = zoneOff, desc = "How big the subzone is. The PvP status is a little smaller." },
        } },
        { label = "Flourishes", items = {
            { type = "toggle", key = "zoneTitleShine", since = "2.2.5", label = "Light across the zone name", disabled = zoneOff,
              desc = "A soft light runs across the name as it settles in. Follows Motion effects (General > Appearance)." },
            { type = "toggle", key = "zoneTitleHaze", since = "2.2.5", label = "Glow behind the zone name", disabled = zoneOff,
              desc = "A soft haze in the name's color glows behind it." },
            { type = "toggle", key = "zoneTitleGem", since = "2.2.5", label = "Diamond on the line", disabled = zoneOff,
              desc = "A small diamond grows in where the line under the name starts from." },
        } },
      } },
    { id = "scenes", label = "Scenes",
      desc = "Calm scenes along the bottom of the screen while you fish or craft.",
      groups = {
        { label = "Profession scenes", items = {
            { type = "toggle", key = "fishScene", since = "1.5.0.1", label = "Fishing water",
              desc = "While your line is in, calm water lies along the bottom of the screen with a little bobber on it, and your action bars and unit frames fade away. When a fish comes in the water splashes. Move, target or cast something else and everything comes back; a fight brings it back at once. The game doesn't tell addons when a fish bites, so the splash comes on the catch, not the bite." },
            { type = "button", label = "Preview the fishing water", text = "Preview",
              desc = "Plays it now; move to end it. Also /dui fishing.",
              func = function() if ns.Fishing then ns.Fishing.Scene.Preview() end end },
            { type = "toggle", key = "forgeScene", since = "1.5.1", label = "Forge scene while smithing",
              desc = "While you smith, an anvil and hammer work along the bottom of the screen with sparks on each finished item, a molten tide shows how far through the batch you are, and your action bars and unit frames fade away. Move, target or cast something else and everything comes back; a fight brings it back at once." },
            { type = "button", label = "Preview the forge", text = "Preview",
              desc = "Plays it now; move to end it. Also /dui forge.",
              func = function() if ns.Fishing then ns.Fishing.Scene.PreviewCraft("forge") end end },
            { type = "toggle", key = "brewScene", label = "Brew scene while making potions",
              desc = "While you make potions, a flask sits at the bottom of the screen with bubbles rising past it, a green tide shows how far through the batch you are, and your action bars and unit frames fade away. Move, target or cast something else and everything comes back; a fight brings it back at once." },
            { type = "button", label = "Preview the brew", text = "Preview",
              desc = "Plays it now; move to end it. Also /dui brew.",
              func = function() if ns.Fishing then ns.Fishing.Scene.PreviewCraft("brew") end end },
            { type = "toggle", key = "workshopScene", label = "Workshop scene while engineering",
              desc = "While you do engineering, two brass gears turn at the bottom of the screen with sparks where they meet, a brass tide shows how far through the batch you are, and your action bars and unit frames fade away. Move, target or cast something else and everything comes back; a fight brings it back at once." },
            { type = "button", label = "Preview the workshop", text = "Preview",
              desc = "Plays it now; move to end it. Also /dui workshop.",
              func = function() if ns.Fishing then ns.Fishing.Scene.PreviewCraft("workshop") end end },
            { type = "toggle", key = "sewingScene", label = "Sewing scene while tailoring",
              desc = "While you tailor, a spool sits at the bottom of the screen, a tide of cloth with a growing seam shows how far through the batch you are, and your action bars and unit frames fade away. Move, target or cast something else and everything comes back; a fight brings it back at once." },
            { type = "button", label = "Preview the sewing", text = "Preview",
              desc = "Plays it now; move to end it. Also /dui sewing.",
              func = function() if ns.Fishing then ns.Fishing.Scene.PreviewCraft("sewing") end end },
        } },
      } },
} }
