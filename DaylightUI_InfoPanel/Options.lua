-- Info panel options, one tab per page.

local _, ns = ...

local function off(key) return function(get) return get(key) ~= true end end
-- The separate reputation bar takes the experience bar's texture and font.
local function noBars(get) return get("xp.enabled") ~= true and get("rep.enabled") ~= true end
local function motionOff() return DaylightUI:Get("general", "motion") == false end
local function ours() return DaylightUI.questsOwnTracker == true end

-- XP bar fade card. Its rows are disabled until the "own fade" toggle on
-- top is on; otherwise the bar fades with the panel.
local function xpFadeCard()
    local card = DaylightUI.Fade.Card("xp.fade.", nil, function(get) return get("xp.enabled") ~= true end, "Experience bar", { own =
        { type = "toggle", key = "xp.ownFade", label = "Experience bar has its own fade",
          desc = "When off, the experience bar fades with the panel. When on, it follows the settings here, attached or separate." } })
    card.label = "Experience bar fade"
    card.tab = "Fade"
    return card
end
-- The data texts' own fade, the same way: off, they fade with the panel.
local function dataFadeCard()
    local card = DaylightUI.Fade.Card("data.fade.", nil, function(get) return get("data.enabled") ~= true end, "Data texts", { own =
        { type = "toggle", key = "data.ownFade", label = "Data texts have their own fade", since = "2.2.1",
          desc = "When off, the data texts fade with the panel. When on, they follow the settings here, so they can rest dimmer than the minimap or fade away on their own." } })
    card.label = "Data texts fade"
    return card
end
local function noClock(get) return get("map.enabled") ~= true or get("map.clock.enabled") ~= true end
local function noFps(get) return get("map.enabled") ~= true or get("map.fps.enabled") ~= true end
local function noLocation(get) return get("map.enabled") ~= true or get("map.location.enabled") ~= true end
local function noCoords(get) return get("map.enabled") ~= true or get("map.coords.enabled") ~= true end

-- Data texts: one dropdown per slot, up to the slot count.
local DT = ns.DataTexts
local function noData(get) return get("data.enabled") ~= true end
-- All texts sorted by their translated name, broker texts included.
local function byName()
    local text = DaylightUI.Options.Text
    local order = {}
    for i, key in ipairs(DT.ORDER) do order[i] = key end
    table.sort(order, function(a, b) return tostring(text(DT.NAMES[a])) < tostring(text(DT.NAMES[b])) end)
    return order
end
local function slotItem(i)
    return { type = "dropdown", key = "data.slot" .. i, label = "Data text slot " .. i,
             choices = function() return DT.NAMES, byName() end,
             desc = "What this slot on the data text strip shows. Slots count from the left.",
             hidden = function(get) return (tonumber(get("data.count")) or 4) < i end, disabled = noData }
end

-- Data bar: the same texts, plus "None" for an empty slot.
local function noBar(get) return get("databar.enabled") ~= true end

-- The numbers' color, for the strip under the map and for the data bar.
local NUMBER_COLORS = { accent = "Accent color", white = "White", class = "Class color", custom = "One color" }
local function numberColor(prefix, off, what)
    return { type = "dropdown", key = prefix .. "numberColor", label = what .. " color", since = "2.2",
             values = NUMBER_COLORS, order = { "accent", "white", "class", "custom" }, disabled = off,
             desc = "The color of the numbers. Accent color follows your accent along the strip. Pick White or One color if a dark accent is hard to read." }
end
local function numberCustom(prefix, off, what)
    return { type = "color", key = prefix .. "numberCustom", label = "Custom " .. what:lower() .. " color", since = "2.2",
             desc = "The numbers' color when " .. what .. " color is One color.",
             disabled = function(get) return off(get) or get(prefix .. "numberColor") ~= "custom" end }
end
local function barChoices()
    local names, order = { none = "None" }, { "none" }
    for _, key in ipairs(byName()) do
        names[key] = DT.NAMES[key]
        order[#order + 1] = key
    end
    return names, order
end
local function barSlot(key, label, desc)
    return { type = "dropdown", key = "databar." .. key, label = label, choices = barChoices,
             desc = desc, disabled = noBar }
end
local barLook = DaylightUI.Options.LookRows("databar.frameStyle", noBar)
local function barSlots()
    local items = { barSlot("center", "Data bar middle slot",
        "What the angled tab in the middle of the bar shows. Pick None to leave the tab out.") }
    for _, side in ipairs({ "left", "right" }) do
        for i = 1, ns.DataBar.SIDE do
            items[#items + 1] = barSlot(side .. i, "Data bar " .. side .. " slot " .. i,
                "What this slot on the " .. side .. " side of the data bar shows, counted from the screen's edge.")
        end
    end
    return items
end

-- XP bar sliders match the resize grip's range.
local XP_MIN, XP_MAX = ns.Panel.XP_MIN, ns.Panel.XP_MAX

-- A bar's own border, corners and shadow (<id>.shell, Panel.Look). Off, the bar
-- follows the Info panel border switch (attached to the panel) or
-- General > Appearance (on its own).
local function shellGroup(id, label, gate, attached)
    local k = function(s) return id .. ".shell." .. s end
    local dis = function(get) return get(gate) ~= true or get(k("own")) ~= true end
    return { label = label,
        desc = attached and "Attached to the info panel, the bar follows the panel's border. Turn on its own look to give it a border, corners and shadow of its own."
            or "This bar's own outline, corners and shadow. When off, it follows General > Appearance.",
        items = {
            { type = "toggle", key = k("own"), label = "Own border and shadow", disabled = off(gate),
              desc = "Gives the bar the border, corners and shadow below. When off, it takes the panel's style (attached) or General > Appearance's (separate)." },
            { type = "slider", key = k("borderPx"), label = "Border thickness", min = 0, max = 16, step = 1, unit = "px",
              desc = "0 leaves just the bar, with no outline round it.", disabled = dis },
            { type = "slider", key = k("cornerPx"), label = "Corner rounding", min = 0, max = 24, step = 1, unit = "px",
              desc = "How round the bar's corners are. 0 keeps them sharp.", disabled = dis },
            { type = "slider", key = k("shadowPx"), label = "Shadow size", min = 0, max = 12, step = 1, unit = "px",
              desc = "How far the bar's shadow spreads. 0 leaves no shadow.", disabled = dis },
        } }
end

local panelLook = DaylightUI.Options.LookRows("frameStyle")
local mapLook = DaylightUI.Options.LookRows("map.frameStyle", off("map.enabled"))
ns.OPTIONS = { pages = {
    { id = "panel", label = "General",
      desc = "The top-right panel: experience bar on top, damage meter and minimap below. Move it in unlock mode. The experience bar has its own page.",
      groups = {
        { label = "Borders and background", desc = "The experience bar's box. The minimap's box and each meter window have their own. At 0 opacity the box disappears; the bars still show.", items = panelLook },
        DaylightUI.Fade.Card("fade.", { { type = "text", label = "The damage meter and minimap fade together (and the separate meter windows, if used). So do the experience bar and the data texts, unless you give them their own fade on their pages. The damage meters can have their own on the Meters page." } }, nil, "Info panel"),
      } },
    { id = "xp", label = "Experience bar",
      desc = "What the experience and reputation bars show, how they look and where they sit.",
      groups = {
        { tab = "General", label = "Experience bar", desc = "At the level cap it shows the reputation you're watching. Before that, it turns to that faction for a few seconds when you gain reputation, and while the mouse is over it.", items = {
            { type = "toggle", key = "xp.enabled", label = "Show the experience bar",
              desc = "The experience bar on top of the panel, or reputation at the level cap." },
            { type = "toggle", key = "xp.gameBar", label = "Use the game's experience bar instead",
              desc = "With the experience bar above off, show the game's own bar at the bottom of the screen. When off, there's no experience bar at all.",
              hidden = function(get) return get("xp.enabled") == true end },
            { type = "toggle", key = "xpGain", label = "XP gain effects",
              disabled = function(get) return get("xp.enabled") ~= true or motionOff() end,
              desc = "The piece of the bar you just earned flashes and \"+XP\" rises; a sweep on a level up. Needs Motion effects (General > Appearance)." },
            { type = "toggle", key = "xp.showText", label = "Show XP and rested XP as text",
              desc = "The numbers on the bar, e.g. 1,200 / 5,000 (+800), where +800 is your rested XP.",
              disabled = off("xp.enabled") },
            { type = "toggle", key = "xp.showPercent", label = "Show experience percent",
              desc = "How far through the level you are, e.g. 24%. With the numbers on too, it sits between them and the rested XP.",
              disabled = off("xp.enabled") },
            { type = "slider", key = "xp.textSize", label = "Experience text size", min = 7, max = 40, step = 1,
              desc = "Size of the numbers on the experience bar.",
              disabled = function(get)
                  return get("xp.enabled") ~= true or (get("xp.showText") ~= true and get("xp.showPercent") ~= true)
              end },
            DaylightUI.Options.FontRow("media.xpFont", "Experience text font", "The experience bar's text and its +XP, and the separate reputation bar's", noBars),
            { type = "toggle", key = "xp.banked", label = "Show XP from finished quests",
              desc = "A colored part after your experience shows what the quests you can turn in will give. Hover the bar for the total.",
              disabled = off("xp.enabled") },
            { type = "color", key = "xp.bankedColor", label = "Finished quests color",
              desc = "The color of the part that shows the XP from quests you can turn in.",
              disabled = function(get) return get("xp.enabled") ~= true or get("xp.banked") == false end },
            { type = "color", key = "xp.restedColor", label = "Rested XP color",
              desc = "The color of the part that shows your rested XP, after your experience.",
              disabled = off("xp.enabled") },
            { type = "toggle", key = "xp.ticks", label = "Experience bar segments",
              desc = "Thin lines split the bar into 20 parts, like the classic bar: each one is 5% of a level.",
              disabled = off("xp.enabled") },
            { type = "dropdown", key = "xp.tipSide", label = "Experience details position",
              values = { auto = "Automatic", left = "Left", right = "Right", above = "Above", below = "Below" },
              order = { "auto", "left", "right", "above", "below" },
              desc = "Where the numbers open when you hover the bar. Automatic opens them toward the middle of the screen.",
              disabled = off("xp.enabled") },
        } },
        { tab = "Look", label = "Experience bar look", items = DaylightUI.Options.Join({
            { type = "toggle", key = "xp.gradient", label = "Experience bar gradient",
              desc = "The bar shades from dark to bright instead of one flat color. Reputation gets one per standing, editable on the Gradients page.",
              disabled = off("xp.enabled") },
            { type = "dropdown", key = "xp.color", label = "Experience bar color",
              values = { accent = "Accent color", class = "Class gradient", blue = "Blue", custom = "Custom gradient" }, order = { "accent", "class", "blue", "custom" },
              desc = "Accent color follows the accent on General > Appearance. Class gradient uses your class's two colors (set on the Gradients page). Custom gradient runs through two to five colors you pick. Reputation keeps its standing's colors.",
              onPick = function() DaylightUI:Set("InfoPanel", "xp.classColor", nil) end,
              disabled = off("xp.enabled") },
        }, DaylightUI.Options.StopsRows("xp.customGradient", { what = "experience bar", bar = "the experience bar",
            since = "2.2", disabled = off("xp.enabled"),
            shown = function(get) return get("xp.color") == "custom" end }), {
            DaylightUI.Options.BarRow("media.xp", "Experience bar", "the experience and reputation bars", noBars),
            DaylightUI.Options.BackRow("media.xp", "Experience bar", "the experience and reputation bars", noBars),
        }) },
        shellGroup("xp", "Experience bar border and shadow", "xp.enabled", true),
        DaylightUI.Options.BarFxCard({ module = "InfoPanel", tab = "Look",
            desc = "The experience and reputation bars move: their colors roll along them. An upright bar stays still.",
            choices = {
                { id = "xp", label = "Experience bar", base = "xp.barFx.", kind = "xp",
                  gate = function(get) return get("xp.enabled") ~= true end },
                { id = "rep", label = "Reputation bar", base = "rep.barFx.", kind = "rep",
                  gate = function(get) return get("rep.enabled") ~= true end },
            } }),
        { tab = "Size", label = "Experience bar size", items = {
            { type = "toggle", key = "xp.detached", label = "Separate experience bar",
              desc = "Takes the bar off the panel and puts it under your action bars. Move it in unlock mode; drag its corner to resize.",
              disabled = off("xp.enabled") },
            { type = "dropdown", key = "xp.orientation", label = "Experience bar orientation",
              values = { horizontal = "Horizontal", vertical = "Vertical" }, order = { "horizontal", "vertical" },
              desc = "Vertical stands the separate bar upright, filling from the bottom to the top. Its width is then how tall it stands, and its height how thick.",
              disabled = function(get) return get("xp.enabled") ~= true or get("xp.detached") ~= true end },
            { type = "toggle", key = "xp.matchBars", label = "Experience bar as wide as the action bar",
              desc = "Keeps the separate bar the same width as your main action bar. An upright bar keeps its own width.",
              disabled = function(get) return get("xp.enabled") ~= true or get("xp.detached") ~= true
                  or get("xp.orientation") == "vertical" end },
            { type = "slider", key = "xp.width", label = "Experience bar width", min = XP_MIN[1], max = XP_MAX[1], step = 1, unit = "px",
              desc = "How wide the separate experience bar is. Dragging its corner in unlock mode sets this too.",
              disabled = function(get) return get("xp.enabled") ~= true or get("xp.detached") ~= true
                  or (get("xp.matchBars") == true and get("xp.orientation") ~= "vertical") end },
            { type = "slider", key = "xp.height", label = "Experience bar height", min = XP_MIN[2], max = XP_MAX[2], step = 1, unit = "px",
              desc = "How tall the experience bar is, on the panel or on its own.",
              disabled = off("xp.enabled") },
        } },
        { tab = "Reputation", label = "Reputation bar", desc = "The reputation you're watching, always, on its own bar. Pick the faction on the Reputation page of the character window. Move it in unlock mode; drag its corner to resize.", items = {
            { type = "toggle", key = "rep.enabled", label = "Show a separate reputation bar",
              desc = "A bar of its own for the faction you're watching. While it's on, the experience bar no longer turns to reputation when you gain some." },
            { type = "dropdown", key = "rep.orientation", label = "Reputation bar orientation",
              values = { horizontal = "Horizontal", vertical = "Vertical" }, order = { "horizontal", "vertical" },
              desc = "Vertical stands the bar upright, filling from the bottom to the top. Its width is then how tall it stands, and its height how thick.",
              disabled = off("rep.enabled") },
            { type = "slider", key = "rep.width", label = "Reputation bar width", min = XP_MIN[1], max = XP_MAX[1], step = 1, unit = "px",
              desc = "How wide the reputation bar is. Dragging its corner in unlock mode sets this too.",
              disabled = off("rep.enabled") },
            { type = "slider", key = "rep.height", label = "Reputation bar height", min = XP_MIN[2], max = XP_MAX[2], step = 1, unit = "px",
              desc = "How tall the reputation bar is.",
              disabled = off("rep.enabled") },
            { type = "toggle", key = "rep.showName", label = "Show the faction's name",
              desc = "The faction's name on the bar.",
              disabled = off("rep.enabled") },
            { type = "toggle", key = "rep.showText", label = "Show reputation as text",
              desc = "The numbers on the bar, e.g. 1,800 / 3,000.",
              disabled = off("rep.enabled") },
            { type = "toggle", key = "rep.showPercent", label = "Show reputation percent",
              desc = "How far through the standing you are, e.g. 60%.",
              disabled = off("rep.enabled") },
            { type = "slider", key = "rep.textSize", label = "Reputation text size", min = 7, max = 40, step = 1,
              desc = "Size of the text on the reputation bar. Its font is the experience bar's.",
              disabled = off("rep.enabled") },
            { type = "toggle", key = "rep.gradient", label = "Reputation bar gradient",
              desc = "The bar shades from dark to bright in its standing's colors, editable on the Gradients page.",
              disabled = off("rep.enabled") },
            { type = "dropdown", key = "rep.tipSide", label = "Reputation details position",
              values = { auto = "Automatic", left = "Left", right = "Right", above = "Above", below = "Below" },
              order = { "auto", "left", "right", "above", "below" },
              desc = "Where the numbers open when you hover the bar. Automatic opens them toward the middle of the screen.",
              disabled = off("rep.enabled") },
        } },
        shellGroup("rep", "Reputation bar border and shadow", "rep.enabled"),
        xpFadeCard(),
      } },
    ns.MeterOptions.Page(),
    { id = "map", label = "Minimap",
      desc = "A square minimap in the panel. Scroll to zoom.",
      groups = {
        { label = "Minimap", items = {
            { type = "toggle", key = "map.enabled", label = "Show the minimap", reload = true,
              desc = "The square minimap in the panel." },
            { type = "slider", key = "map.size", label = "Minimap size", min = 120, max = 2800, step = 2, unit = "px",
              desc = "How big the square minimap is.",
              disabled = off("map.enabled") },
            { type = "slider", key = "map.iconScale", label = "Minimap icon size", since = "1.8.0", min = 0.5, max = 2, step = 0.1, unit = "%",
              desc = "How big the icons on the map are: herbs and ore, party members, quest spots and the like. The map keeps its size. This is Edit Mode's own setting, kept in your Edit Mode layout.",
              get = function() return ns.Minimap.GetIconScale() end,
              set = function(v) ns.Minimap.SetIconScale(v) end,
              default = function() return 1 end,
              disabled = off("map.enabled") },
            { type = "toggle", label = "Rotate as you turn",
              desc = "The game's own setting: the map turns with you, so the way you face is always up. When off, north is always up.",
              get = function() return type(GetCVarBool) == "function" and GetCVarBool("rotateMinimap") == true end,
              -- A game setting, so it's written out of a fight only.
              set = function(v) DaylightUI.AfterCombat(function()
                  if type(SetCVar) == "function" then DaylightUI.SafeCall(SetCVar, "rotateMinimap", v and "1" or "0") end
                  -- The game reapplies this from its Edit Mode layout at login,
                  -- so write it there too or it resets after a reload.
                  local sys, set = Enum.EditModeSystem, Enum.EditModeMinimapSetting
                  if sys and set then
                      DaylightUI.EditMode.WriteSetting(sys.Minimap, nil, set.RotateMinimap, v and 1 or 0)
                  end
                  -- Not one of Daylight UI's settings, so notify the options window directly.
                  DaylightUI.Fire("SettingChanged", "InfoPanel", "map.rotate", v)
              end, "infopanel:rotate") end,
              default = function() return false end,
              disabled = off("map.enabled") },
            { type = "dropdown", key = "map.shape", label = "Minimap shape", since = "1.8.0",
              values = { square = "Square", round = "Round" }, order = { "square", "round" },
              desc = "Round gives the map a thin ring with N at the top. While Rotate as you turn is on, the map is always round.",
              disabled = function(get)
                  return get("map.enabled") ~= true or (type(GetCVarBool) == "function" and GetCVarBool("rotateMinimap") == true)
              end },
            { type = "toggle", key = "map.buttons", label = "Calendar and tracking buttons",
              desc = "Shows the calendar and tracking buttons on the map's right edge while the mouse is over the map.",
              disabled = off("map.enabled") },
            { type = "toggle", key = "map.drawer", label = "Addon button drawer",
              desc = "Addons' minimap buttons and the game's addon menu are gathered into one drawer. The button in the map's bottom-right corner opens it.",
              reload = true, disabled = off("map.enabled") },
        } },
        { label = "Minimap box", desc = "The box around the minimap, with the damage meter and data texts in it.", items = {
            { type = "toggle", key = "map.noBox", label = "Frameless round map", since = "2.2.5",
              desc = "A round minimap stands on its own ring. The damage meter slides out from behind it in a box of its own, and the data texts sit in a small box under it. Needs Minimap shape set to Round, or Rotate as you turn.",
              disabled = function(get)
                  return get("map.enabled") ~= true
                      or (get("map.shape") ~= "round" and not (type(GetCVarBool) == "function" and GetCVarBool("rotateMinimap") == true))
              end },
        } },
        { label = "Borders and background", desc = "The box around the minimap, with the damage meter and data texts in it.", items = mapLook },
        { label = "Clock", desc = "A small time at the bottom of the map. Hover it for both local and server time.", items = {
            { type = "toggle", key = "map.clock.enabled", label = "Show the clock",
              desc = "The time at the bottom of the minimap.",
              disabled = off("map.enabled") },
            { type = "toggle", key = "map.clock.twentyFour", label = "24-hour clock",
              desc = "The clock reads 18:30 instead of 6:30 PM.",
              disabled = noClock },
            { type = "toggle", key = "map.clock.seconds", label = "Show seconds",
              desc = "The clock reads 18:30:15, ticking every second.",
              disabled = noClock },
            { type = "toggle", key = "map.clock.useServer", label = "Show server time",
              desc = "Shows server time instead of your local time.",
              disabled = noClock },
            { type = "slider", key = "map.clock.textSize", label = "Clock text size", min = 8, max = 20, step = 1,
              desc = "How big the clock is.",
              disabled = noClock },
            { type = "color", key = "map.clock.color", label = "Clock color",
              desc = "The color of the clock.",
              disabled = noClock },
        } },
        { label = "Framerate", desc = "Your frames per second beside the clock. Hover it for latency, addon CPU and memory.", items = {
            { type = "toggle", key = "map.fps.enabled", label = "Show the framerate",
              desc = "Your frames per second beside the clock.",
              disabled = off("map.enabled") },
            { type = "slider", key = "map.fps.textSize", label = "Framerate text size", min = 8, max = 20, step = 1,
              desc = "How big the framerate is.",
              disabled = noFps },
            { type = "color", key = "map.fps.color", label = "Framerate color",
              desc = "The color of the framerate.",
              disabled = noFps },
        } },
        { label = "Location", desc = "The zone or area you're in, at the top of the map (above the coordinates).", items = {
            { type = "toggle", key = "map.location.enabled", label = "Show the zone name",
              desc = "The zone or area you're in, at the top of the minimap.",
              disabled = off("map.enabled") },
            { type = "slider", key = "map.location.textSize", label = "Minimap zone name text size", min = 8, max = 20, step = 1,
              desc = "How big the zone name is.",
              disabled = noLocation },
            { type = "dropdown", key = "map.location.colorBy", label = "Minimap zone name color",
              values = { pvp = "By zone", custom = "One color" }, order = { "pvp", "custom" },
              desc = "By zone: green in friendly lands, amber in contested ones, red in hostile ones, blue in sanctuaries. One color: always Custom minimap zone name color.",
              disabled = noLocation },
            { type = "color", key = "map.location.color", label = "Custom minimap zone name color",
              desc = "The zone name's color when Minimap zone name color is One color.",
              disabled = function(get) return noLocation(get) or get("map.location.colorBy") ~= "custom" end },
        } },
        { label = "Coordinates", desc = "Your x, y position at the top of the map. Blank in dungeons and raids.", items = {
            { type = "toggle", key = "map.coords.enabled", label = "Show coordinates",
              desc = "Your x, y position at the top of the minimap. Blank in dungeons and raids.",
              disabled = off("map.enabled") },
            { type = "slider", key = "map.coords.textSize", label = "Coordinates text size", min = 8, max = 20, step = 1,
              desc = "How big the coordinates are.",
              disabled = noCoords },
            { type = "color", key = "map.coords.color", label = "Coordinates color",
              desc = "The color of the coordinates.",
              disabled = noCoords },
        } },
      } },
    { id = "data", label = "Data texts",
      desc = "A thin strip under the minimap: gold, gear, bag space, friends online. Hover one for details, click it to open its window.",
      groups = {
        { label = "Data texts", desc = "Each text updates as it changes. Hover for details: gold on every character, each piece of gear, each bag, who's online.", items = {
            { type = "toggle", key = "data.enabled", label = "Show the data texts",
              desc = "The thin strip under the minimap with gold, gear, bag space and more." },
            { type = "slider", key = "data.count", label = "Number of data texts", min = 3, max = DT.MAX, step = 1,
              desc = "How many data texts share the strip. Pick what each shows under Slots.",
              disabled = noData },
            { type = "toggle", key = "data.labels", label = "Data text labels",
              desc = "Short labels like Gear, Bags and Guild before each number. They drop off when the strip is too narrow.",
              disabled = noData },
            { type = "slider", key = "data.textSize", label = "Data text size", min = 8, max = 14, step = 1, disabled = noData,
              desc = "How big the data texts are." },
            numberColor("data.", noData, "Data text"),
            numberCustom("data.", noData, "Data text"),
            DaylightUI.Options.FontRow("media.font", "Data text font", "The data texts, the data bar, and the clock, framerate, zone name and coordinates on the minimap"),
            { type = "dropdown", key = "data.goldChars", label = "Gold characters",
              values = { all = "Every character", faction = "This faction" }, order = { "all", "faction" },
              desc = "Whose gold the Gold text's tooltip lists and adds up: every character, or only those of the faction you're playing. A character counts for its faction once it has logged in with Daylight UI 1.8 or later." },
            { type = "toggle", key = "data.soulBag", label = "Soul bag size", since = "1.7.2",
              desc = "Warlocks: the Soul Shards text shows how many your soul bag holds beside the count, and its tooltip the free slots. On the data bar too." },
        } },
        { label = "Slots", desc = "What each slot shows, left to right. The clock, framerate and coordinates are on the minimap too.", items = {
            slotItem(1), slotItem(2), slotItem(3), slotItem(4), slotItem(5),
        } },
        dataFadeCard(),
      } },
    { id = "databar", label = "Data bar",
      desc = "A slim angled bar at the bottom of the screen: the clock in the middle, your data texts on both sides.",
      groups = {
        { label = "Data bar", desc = "Hover a text for details, click it to open its window. Move it in unlock mode (/dui unlock). When it reaches the screen's corners, chat and the damage meters' windows start above it unless you've moved them.", items = {
            { type = "toggle", key = "databar.enabled", label = "Show the data bar",
              desc = "The bar along the bottom of the screen." },
            { type = "slider", key = "databar.widthPct", label = "Data bar width", min = 30, max = 100, step = 1,
              disabled = noBar, desc = "How much of the screen's width the bar takes, in percent." },
            { type = "slider", key = "databar.height", label = "Data bar height", min = 18, max = 36, step = 1, unit = "px",
              disabled = noBar, desc = "How tall the data bar is." },
            { type = "slider", key = "databar.textSize", label = "Data bar text size", min = 9, max = 16, step = 1,
              disabled = noBar, desc = "How big the texts are. The one in the middle is a little bigger." },
            numberColor("databar.", noBar, "Data bar text"),
            numberCustom("databar.", noBar, "Data bar text"),
            { type = "toggle", key = "databar.icons", label = "Data bar icons", disabled = noBar,
              desc = "A small icon before each text, in the numbers' color." },
            { type = "toggle", key = "databar.labels", label = "Data bar labels", disabled = noBar,
              desc = "Short labels like Gear, Bags and Guild before each number. They drop off when the bar is too narrow." },
            { type = "toggle", key = "databar.line", label = "Data bar accent line", disabled = noBar,
              desc = "The line along the top of the bar, in your accent color." },
            DaylightUI.Options.EndRows({ name = "Data bar", disabled = noBar, note = "The tab in the middle leans the same way.",
                left = { on = "databar.angled", flip = "databar.flipLeft" }, right = { on = "databar.angledRight", flip = "databar.flipRight" } })[1],
            DaylightUI.Options.EndRows({ name = "Data bar", disabled = noBar, note = "The tab in the middle leans the same way.",
                left = { on = "databar.angled", flip = "databar.flipLeft" }, right = { on = "databar.angledRight", flip = "databar.flipRight" } })[2],
        } },
        { label = "Borders and background", desc = "The data bar has no border on the global style: on a strip this thin the accent line is enough.", items = barLook },
        DaylightUI.Fade.Card("databar.fade.", nil, noBar, "Data bar"),
        { label = "Slots", desc = "What the bar shows. Pick None to leave a slot empty, and the others close up.", items = barSlots() },
      } },
    -- Only for the game's own tracker. With the Quests module loaded, its
    -- options live there instead.
    { id = "tracker", label = "Quest tracker", hidden = ours,
      desc = "The game's quest tracker, placed under the panel.",
      groups = {
        { label = "Quest tracker", items = {
            { type = "toggle", key = "tracker.enabled", label = "Place under the info panel", reload = true,
              desc = "When off, the game's tracker stays where Edit Mode puts it." },
        } },
        DaylightUI.Fade.Card("tracker.fade.", nil, function(get) return ours() or get("tracker.enabled") ~= true end),
      } },
} }
