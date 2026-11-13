-- Info panel options, one tab per page.

local _, ns = ...

local function off(key) return function(get) return get(key) ~= true end end
local function motionOff() return DaylightUI:Get("general", "motion") == false end
local function ours() return DaylightUI.questsOwnTracker == true end

-- XP bar fade card. Its rows are disabled until the "own fade" toggle on
-- top is on; otherwise the bar fades with the panel.
local function xpFadeCard()
    local card = DaylightUI.Fade.Card("xp.fade.", nil, function(get)
        return get("xp.enabled") ~= true or get("xp.ownFade") ~= true
    end, "Experience bar")
    card.label = "Experience bar fade"
    table.insert(card.items, 1, { type = "toggle", key = "xp.ownFade", label = "Experience bar has its own fade",
        desc = "Off, the experience bar fades with the panel. On, it follows the settings here, attached or separate.",
        disabled = function(get) return get("xp.enabled") ~= true end })
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
local barBack = DaylightUI.Options.BackAlphaRows("databar.alpha", "Data bar", noBar)
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

-- Panel background opacity, shared by the meter and threat meter windows.
local backRows = DaylightUI.Options.BackAlphaRows("panelAlpha", "Info panel")
backRows[2].desc = "How see-through the experience bar's box and the meters' own windows are (a meter window can have its own, on its page)."
local mapBack = DaylightUI.Options.BackAlphaRows("map.alpha", "Minimap box", off("map.enabled"))
mapBack[2].desc = "How see-through the box around the minimap (and the damage meter in it) is: 0 is fully see-through."
ns.OPTIONS = { pages = {
    { id = "panel", label = "General",
      desc = "The top-right panel: experience bar on top, damage meter and minimap below. Move it in unlock mode.",
      groups = {
        { label = "Background", desc = "The experience bar's box, and the meters' and threat meter's own windows. The minimap's box has its own on the Minimap page. At 0 opacity the boxes disappear; the bars still show.", items = {
            backRows[1], backRows[2],
            { type = "toggle", key = "panelBorder", label = "Border",
              desc = "A border and shadow around the experience bar's box and the threat meter's window." },
        } },
        { label = "Experience bar", desc = "At the level cap it shows the reputation you're watching. Before that, it turns to that faction for a few seconds when you gain reputation, and while the mouse is over it.", items = {
            { type = "toggle", key = "xp.enabled", label = "Show the experience bar",
              desc = "The experience bar on top of the panel, or reputation at the level cap." },
            { type = "toggle", key = "xpGain", label = "XP gain effects",
              disabled = function(get) return get("xp.enabled") ~= true or motionOff() end,
              desc = "The piece of the bar you just earned flashes and \"+XP\" rises; a sweep on a level up. Needs Motion effects (General > Appearance)." },
            { type = "toggle", key = "xp.showText", label = "Show XP and rested XP as text",
              desc = "The numbers on the bar, e.g. 1,200 / 5,000 (+800), where +800 is your rested XP.",
              disabled = off("xp.enabled") },
            { type = "toggle", key = "xp.showPercent", label = "Show percent as text",
              desc = "How far through the level you are, e.g. 24%. With the numbers on too, it sits between them and the rested XP.",
              disabled = off("xp.enabled") },
            { type = "slider", key = "xp.textSize", label = "Experience text size", min = 7, max = 40, step = 1,
              desc = "Size of the numbers on the experience bar.",
              disabled = function(get)
                  return get("xp.enabled") ~= true or (get("xp.showText") ~= true and get("xp.showPercent") ~= true)
              end },
            DaylightUI.Options.FontRow("media.xpFont", "Experience text font", "The experience bar's text and its +XP", off("xp.enabled")),
            { type = "toggle", key = "xp.banked", label = "Show XP from finished quests",
              desc = "A green part after your experience shows what the quests you can turn in will give. Hover the bar for the total.",
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
        { label = "Experience bar look", items = {
            { type = "toggle", key = "xp.gradient", label = "Experience bar gradient",
              desc = "The bar shades from dark to bright instead of one flat color. Reputation gets one per standing, editable on the Gradients page.",
              disabled = off("xp.enabled") },
            { type = "dropdown", key = "xp.color", label = "Experience bar color",
              values = { accent = "Accent", class = "Class", blue = "Blue", custom = "Custom" }, order = { "accent", "class", "blue", "custom" },
              desc = "Accent follows the accent color on the Appearance page. Class uses your class's gradient (set on the Gradients page). Reputation keeps its standing's colors.",
              onPick = function() DaylightUI:Set("InfoPanel", "xp.classColor", nil) end,
              disabled = off("xp.enabled") },
            { type = "gradient", label = "Custom experience bar color",
              get = function() return { lo = DaylightUI:Get("InfoPanel", "xp.customLo"), hi = DaylightUI:Get("InfoPanel", "xp.customHi") } end,
              set = function(v)
                  DaylightUI:Set("InfoPanel", "xp.customLo", v.lo)
                  DaylightUI:Set("InfoPanel", "xp.customHi", v.hi)
              end,
              default = function() return { lo = ns.DEFAULTS.xp.customLo, hi = ns.DEFAULTS.xp.customHi } end,
              desc = "The two ends of the bar's gradient. With Gradient off, the bar takes the bright end.",
              hidden = function(get) return get("xp.color") ~= "custom" end,
              disabled = off("xp.enabled") },
            { type = "slider", key = "xp.height", label = "Experience bar height", min = XP_MIN[2], max = XP_MAX[2], step = 1, unit = "px",
              desc = "How tall the experience bar is.",
              disabled = off("xp.enabled") },
            DaylightUI.Options.BarRow("media.xp", "Experience bar", "the experience and reputation bar", off("xp.enabled")),
            DaylightUI.Options.BackRow("media.xp", "Experience bar", "the experience and reputation bar", off("xp.enabled")),
        } },
        { label = "Separate experience bar", items = {
            { type = "toggle", key = "xp.detached", label = "Detach from the panel",
              desc = "Takes the bar off the panel and puts it under your action bars. Move it in unlock mode; drag its corner to resize.",
              disabled = off("xp.enabled") },
            { type = "toggle", key = "xp.matchBars", label = "As wide as the action bar",
              desc = "Keeps the separate bar the same width as your main action bar. An upright bar keeps its own width.",
              disabled = function(get) return get("xp.enabled") ~= true or get("xp.detached") ~= true
                  or get("xp.orientation") == "vertical" end },
            { type = "dropdown", key = "xp.orientation", label = "Experience bar orientation",
              values = { horizontal = "Horizontal", vertical = "Vertical" }, order = { "horizontal", "vertical" },
              desc = "Vertical stands the separate bar upright, filling from the bottom to the top. Its width is then how tall it stands, and its height how thick.",
              disabled = function(get) return get("xp.enabled") ~= true or get("xp.detached") ~= true end },
            { type = "slider", key = "xp.width", label = "Experience bar width", min = XP_MIN[1], max = XP_MAX[1], step = 1, unit = "px",
              desc = "How wide the separate experience bar is. Dragging its corner in unlock mode sets this too.",
              disabled = function(get) return get("xp.enabled") ~= true or get("xp.detached") ~= true
                  or (get("xp.matchBars") == true and get("xp.orientation") ~= "vertical") end },
        } },
        { label = "Reputation bar", desc = "The reputation you're watching, always, on its own bar. Pick the faction on the Reputation page of the character window. Move it in unlock mode; drag its corner to resize.", items = {
            { type = "toggle", key = "rep.enabled", label = "Show a separate reputation bar",
              desc = "A bar of its own for the faction you're watching. While it's on, the experience bar no longer turns to reputation when you gain some." },
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
            { type = "slider", key = "rep.width", label = "Reputation bar width", min = XP_MIN[1], max = XP_MAX[1], step = 1, unit = "px",
              desc = "How wide the reputation bar is. Dragging its corner in unlock mode sets this too.",
              disabled = off("rep.enabled") },
            { type = "slider", key = "rep.height", label = "Reputation bar height", min = XP_MIN[2], max = XP_MAX[2], step = 1, unit = "px",
              desc = "How tall the reputation bar is.",
              disabled = off("rep.enabled") },
            { type = "dropdown", key = "rep.orientation", label = "Reputation bar orientation",
              values = { horizontal = "Horizontal", vertical = "Vertical" }, order = { "horizontal", "vertical" },
              desc = "Vertical stands the bar upright, filling from the bottom to the top. Its width is then how tall it stands, and its height how thick.",
              disabled = off("rep.enabled") },
            { type = "dropdown", key = "rep.tipSide", label = "Reputation details position",
              values = { auto = "Automatic", left = "Left", right = "Right", above = "Above", below = "Below" },
              order = { "auto", "left", "right", "above", "below" },
              desc = "Where the numbers open when you hover the bar. Automatic opens them toward the middle of the screen.",
              disabled = off("rep.enabled") },
        } },
        DaylightUI.Fade.Card("fade.", { { type = "text", label = "The damage meter and minimap fade together (and the separate meter windows, if used). So does the experience bar, unless you give it its own fade below. The damage meters can have their own on the Meters page." } }, nil, "Info panel"),
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
            { type = "toggle", label = "Rotate as you turn",
              desc = "The game's own setting: the map turns with you, so the way you face is always up. When off, north is always up.",
              get = function() return type(GetCVarBool) == "function" and GetCVarBool("rotateMinimap") == true end,
              set = function(v)
                  if type(SetCVar) == "function" then SetCVar("rotateMinimap", v and "1" or "0") end
                  -- The game reapplies this from its Edit Mode layout at login,
                  -- so write it there too or it resets after a reload.
                  local sys, set = Enum.EditModeSystem, Enum.EditModeMinimapSetting
                  if sys and set then
                      DaylightUI.EditMode.WriteSetting(sys.Minimap, nil, set.RotateMinimap, v and 1 or 0)
                  end
                  -- Not one of our settings, so notify the options window directly.
                  DaylightUI.Fire("SettingChanged", "InfoPanel", "map.rotate", v)
              end,
              default = function() return false end,
              disabled = off("map.enabled") },
            { type = "toggle", key = "map.buttons", label = "Calendar and tracking buttons",
              desc = "Shows the calendar and tracking buttons on the map's right edge while the mouse is over the map.",
              disabled = off("map.enabled") },
            { type = "toggle", key = "map.drawer", label = "Addon button drawer",
              desc = "Addons' minimap buttons and the game's addon menu are gathered into one drawer. The button in the map's bottom-right corner opens it.",
              reload = true, disabled = off("map.enabled") },
        } },
        { label = "Minimap box", desc = "The box around the minimap, with the damage meter and data texts in it. The experience bar and the meters' own windows keep the General page's background.", items = {
            { type = "dropdown", key = "map.meterSide", label = "Damage meter side",
              values = { auto = "Automatic", left = "Left", right = "Right" }, order = { "auto", "left", "right" },
              desc = "Which side of the minimap the damage meter slides out of, with the threat meter beside it. Automatic picks the side toward the middle of the screen, so it follows when you move the panel." },
            mapBack[1], mapBack[2],
            { type = "toggle", key = "map.border", label = "Minimap box border",
              desc = "A border and shadow around the minimap's box.",
              disabled = off("map.enabled") },
        } },
        { label = "Clock", desc = "A small time at the bottom of the map. Hover it for both local and server time.", items = {
            { type = "toggle", key = "map.clock.enabled", label = "Show the clock",
              desc = "The time at the bottom of the minimap.",
              disabled = off("map.enabled") },
            { type = "toggle", key = "map.clock.twentyFour", label = "24-hour clock",
              desc = "The clock reads 18:30 instead of 6:30 PM.",
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
            { type = "slider", key = "map.location.textSize", label = "Zone name text size", min = 8, max = 20, step = 1,
              desc = "How big the zone name is.",
              disabled = noLocation },
            { type = "dropdown", key = "map.location.colorBy", label = "Zone name color",
              values = { pvp = "By zone", custom = "One color" }, order = { "pvp", "custom" },
              desc = "By zone: green in friendly lands, amber in contested ones, red in hostile ones, blue in sanctuaries. One color: always the color below.",
              disabled = noLocation },
            { type = "color", key = "map.location.color", label = "Custom zone name color",
              desc = "The zone name's color when Zone name color is One color.",
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
            { type = "toggle", key = "data.labels", label = "Labels",
              desc = "Short labels like Gear, Bags and Guild before each number. They drop off when the strip is too narrow.",
              disabled = noData },
            { type = "slider", key = "data.textSize", label = "Data text size", min = 8, max = 14, step = 1, disabled = noData,
              desc = "How big the data texts are." },
            DaylightUI.Options.FontRow("media.font", "Data text font", "The data texts, and the clock, framerate, zone name and coordinates on the minimap"),
            { type = "dropdown", key = "data.goldChars", label = "Gold characters",
              values = { all = "Every character", faction = "This faction" }, order = { "all", "faction" },
              desc = "Whose gold the Gold text's tooltip lists and adds up: every character, or only those of the faction you're playing. A character counts for its faction once it has logged in after this update." },
            { type = "toggle", key = "data.soulBag", label = "Soul bag size", since = "1.7.2", disabled = noData,
              desc = "Warlocks: the Soul Shards text shows how many your soul bag holds beside the count, and its tooltip the free slots." },
        } },
        { label = "Slots", desc = "What each slot shows, left to right. The clock, framerate and coordinates are on the minimap too.", items = {
            slotItem(1), slotItem(2), slotItem(3), slotItem(4), slotItem(5),
        } },
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
            { type = "toggle", key = "databar.icons", label = "Data bar icons", disabled = noBar,
              desc = "A small icon before each text, in your accent color." },
            { type = "toggle", key = "databar.labels", label = "Data bar labels", disabled = noBar,
              desc = "Short labels like Gear, Bags and Guild before each number. They drop off when the bar is too narrow." },
            { type = "toggle", key = "databar.line", label = "Data bar accent line", disabled = noBar,
              desc = "The line along the top of the bar, in your accent color." },
            { type = "toggle", key = "databar.angled", label = "Data bar angled ends", disabled = noBar,
              desc = "Cuts both ends of the bar at an angle. Off, they're straight." },
            barBack[1], barBack[2],
            { type = "slider", key = "databar.borderAlpha", label = "Data bar border opacity", min = 0, max = 1, step = 0.05, unit = "%",
              disabled = noBar, desc = "How solid the border around the bar is: 0 is no border." },
        } },
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
