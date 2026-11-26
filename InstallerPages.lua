-- The setup guide's content as data: the modules it knows, other addons that
-- do the same jobs, and the questions Make it mine asks. Choices point at the
-- options' own items by scope and key, so the guide always writes the same
-- settings as the options window. Questions whose module isn't loaded are
-- left out.

local _, DUI = ...

local Pages = {}
DUI.InstallerPages = Pages

-- Every module in display order: addon folder, name in the suite
-- (DUI:GetModule), and a line on what it does.
Pages.MODULES = {
    { addon = "DaylightUI_UnitFrames", name = "UnitFrames", label = "Unit Frames",
      pitch = "Soft player, target, party and raid frames with cast bars and debuffs." },
    { addon = "DaylightUI_ActionBars", name = "ActionBars", label = "Action Bars",
      pitch = "Framed buttons in a centered layout, with side bars that fade until needed." },
    { addon = "DaylightUI_Nameplates", name = "Nameplates", label = "Nameplates",
      pitch = "Clear plates with interruptible casts, your debuffs and quest marks." },
    { addon = "DaylightUI_Buffs", name = "Buffs", label = "Buffs & Debuffs",
      pitch = "Your buffs sorted into color-coded groups; debuffs edged by type." },
    { addon = "DaylightUI_Bags", name = "Bags", label = "Bags",
      pitch = "Every bag in one window, with search, sorting and categories." },
    { addon = "DaylightUI_Chat", name = "Chat", label = "Chat",
      pitch = "A clean chat panel with class colors, timestamps and copyable links." },
    { addon = "DaylightUI_InfoPanel", name = "InfoPanel", label = "Info Panel",
      pitch = "XP bar, damage meter and a square minimap in one corner panel." },
    { addon = "DaylightUI_Quests", name = "Quests", label = "Quest Tracker",
      pitch = "Your quests in the DaylightUI look, with item buttons and smooth motion." },
    { addon = "DaylightUI_Tooltip", name = "Tooltip", label = "Tooltips",
      pitch = "Dark tooltips with class colors, item quality borders and a health bar." },
    { addon = "DaylightUI_Skins", name = "Skins", label = "Game window skins",
      pitch = "The game's own windows in the DaylightUI look." },
    { addon = "DaylightUI_Procs", name = "Procs", label = "Proc Alerts",
      pitch = "A painted flare around your character when a proc like Clearcasting or Overpower is ready." },
    { addon = "DaylightUI_QoL", name = "QoL", label = "Quality of Life",
      pitch = "Small helpers: faster looting, quest automation, trainers and more." },
}

-- Other addons that replace the same thing as one of Daylight UI's. The setup
-- guide asks about them, and so does the clash box at login (Clashes.lua).
-- Daylight UI's side of each is one of:
--   module           the whole module (its addon is switched off)
--   settings = {...} only part of a module: these settings, { scope, key },
--                    turned off; the clash counts only while one is on
--   core = true      the whole of Daylight UI
-- what names the part, the same for every addon fighting over it.
-- options: for an addon that clashes only through some of its own options, a
-- function giving the names of those that are on (nil = no clash now).
local RAID = { { "UnitFrames", "party.enabled" }, { "UnitFrames", "raid.enabled" } }
local CDM = { { "ActionBars", "cooldowns" } }
local MAP = { { "InfoPanel", "map.enabled" } }
local CHARACTER = { { "Character", "enabled" } }

-- Leatrix Plus fights Daylight UI only through some of its options, saved as
-- "On"/"Off" in LeaPlusDB. It writes its own copy back over that table at
-- logout, so Daylight UI can't switch them off for it: the pick is the
-- whole addon. Its option names, as Leatrix Plus shows them.
Pages.LEATRIX_CHAT = {
    { "UseEasyChatResizing", "Use easy resizing" }, { "NoCombatLogTab", "Hide the combat log" },
    { "NoChatButtons", "Hide chat buttons" }, { "UnclampChat", "Unclamp chat frame" },
    { "MoveChatEditBoxToTop", "Move editbox to top" }, { "NoStickyChat", "Disable sticky chat" },
    { "UseArrowKeysInChat", "Use arrow keys in chat" }, { "NoChatFade", "Disable chat fade" },
    { "RecentChatWindow", "Recent chat window" }, { "RestoreChatMessages", "Restore chat messages" },
}
Pages.LEATRIX_MAP = { { "MinimapModder", "Enhance minimap" } }

-- The names of those options that are on, or nil when none is.
function Pages.LeatrixOn(list)
    local db = _G.LeaPlusDB
    if type(db) ~= "table" then return nil end
    local on = {}
    for _, o in ipairs(list) do
        if db[o[1]] == "On" then on[#on + 1] = o[2] end
    end
    return #on > 0 and on or nil
end
Pages.CLASHES = {
    { core = true, addon = "ElvUI", label = "ElvUI", what = "whole UI" },
    { module = "ActionBars", addon = "EllesmereUIActionBars", label = "EllesmereUI Action Bars", what = "action bars" },
    { module = "ActionBars", addon = "Bartender4", label = "Bartender4", what = "action bars" },
    { module = "ActionBars", addon = "Dominos", label = "Dominos", what = "action bars" },
    { module = "ActionBars", settings = CDM, addon = "EllesmereUICooldownManager", label = "EllesmereUI Cooldown Manager", what = "Cooldown Manager icons" },
    { module = "ActionBars", settings = CDM, addon = "BetterCooldownManager", label = "Better Cooldown Manager", what = "Cooldown Manager icons" },
    { module = "ActionBars", settings = CDM, addon = "CooldownManagerCentered", label = "Cooldown Manager Centered", what = "Cooldown Manager icons" },
    { module = "ActionBars", settings = CDM, addon = "SkironCooldownManager", label = "Skiron Cooldown Manager", what = "Cooldown Manager icons" },
    { module = "ActionBars", settings = CDM, addon = "ArcUI", label = "ArcUI", what = "Cooldown Manager icons" },
    { module = "ActionBars", settings = CDM, addon = "Ayije_CDM", label = "Ayije CDM", what = "Cooldown Manager icons" },
    { module = "Bags", addon = "Baganator", label = "Baganator", what = "bags" },
    { module = "Bags", addon = "Bagnon", label = "Bagnon", what = "bags" },
    { module = "Bags", addon = "AdiBags", label = "AdiBags", what = "bags" },
    { module = "Bags", addon = "ArkInventory", label = "ArkInventory", what = "bags" },
    { module = "Bags", addon = "BetterBags", label = "BetterBags", what = "bags" },
    { module = "Bags", addon = "Sorted", label = "Sorted", what = "bags" },
    { module = "Buffs", addon = "BuffLedger", label = "BuffLedger", what = "buff bars" },
    { module = "Chat", addon = "EllesmereUIChat", label = "EllesmereUI Chat", what = "chat" },
    { module = "Chat", addon = "Prat-3.0", label = "Prat", what = "chat" },
    { module = "Chat", addon = "Chatter", label = "Chatter", what = "chat" },
    { module = "Chat", addon = "Chattynator", label = "Chattynator", what = "chat" },
    { module = "Chat", addon = "Glass", label = "Glass", what = "chat" },
    { module = "InfoPanel", settings = MAP, addon = "EllesmereUIMinimap", label = "EllesmereUI Minimap", what = "minimap" },
    { module = "Chat", addon = "Leatrix_Plus", label = "Leatrix Plus", what = "chat",
      options = function() return Pages.LeatrixOn(Pages.LEATRIX_CHAT) end },
    { module = "InfoPanel", settings = MAP, addon = "SexyMap", label = "SexyMap", what = "minimap" },
    { module = "InfoPanel", settings = MAP, addon = "Leatrix_Plus", label = "Leatrix Plus", what = "minimap",
      options = function() return Pages.LeatrixOn(Pages.LEATRIX_MAP) end },
    { module = "InfoPanel", settings = { { "InfoPanel", "map.drawer" } }, addon = "MinimapButtonButton", label = "MinimapButtonButton", what = "minimap buttons" },
    { module = "InfoPanel", settings = { { "InfoPanel", "meter.enabled" } }, addon = "EllesmereUIDamageMeters", label = "EllesmereUI Damage Meters", what = "damage meter" },
    { module = "Quests", addon = "!KalielsTracker", label = "Kaliel's Tracker", what = "quest tracker" },
    { module = "Quests", addon = "EllesmereUIQuestTracker", label = "EllesmereUI Quest Tracker", what = "quest tracker" },
    { module = "Nameplates", addon = "Platynator", label = "Platynator", what = "nameplates" },
    { module = "Nameplates", addon = "EllesmereUINameplates", label = "EllesmereUI Nameplates", what = "nameplates" },
    { module = "Nameplates", addon = "TidyPlates_ThreatPlates", label = "Threat Plates", what = "nameplates" },
    { module = "Nameplates", addon = "Plater", label = "Plater", what = "nameplates" },
    { module = "Nameplates", addon = "Kui_Nameplates", label = "Kui Nameplates", what = "nameplates" },
    { module = "Nameplates", addon = "TidyPlates", label = "TidyPlates", what = "nameplates" },
    { module = "Nameplates", addon = "Aloft", label = "Aloft", what = "nameplates" },
    { module = "Skins", addon = "EllesmereUIBlizzardSkin", label = "EllesmereUI Blizzard Skin", what = "game windows" },
    { module = "UnitFrames", addon = "EllesmereUIUnitFrames", label = "EllesmereUI Unit Frames", what = "frames" },
    { module = "UnitFrames", addon = "UnhaltedUnitFrames", label = "Unhalted Unit Frames", what = "frames" },
    { module = "UnitFrames", settings = RAID, addon = "Grid2", label = "Grid2", what = "party and raid frames" },
    { module = "UnitFrames", settings = RAID, addon = "DandersFrames", label = "Danders Frames", what = "party and raid frames" },
    { module = "UnitFrames", settings = RAID, addon = "HarreksAdvancedRaidFrames", label = "Harreks Raid Frames", what = "party and raid frames" },
    { module = "Character", settings = CHARACTER, addon = "ChonkyCharacterSheet", label = "Chonky Character Sheet", what = "character window" },
    { module = "Character", settings = CHARACTER, addon = "DejaCharacterStats", label = "Deja Character Stats", what = "character window" },
    { module = "Character", settings = CHARACTER, addon = "BetterCharacterPanel", label = "Better Character Panel", what = "character window" },
}

-- One module's entries from that list (the quest tracker steps aside for them).
function Pages.ClashesFor(module)
    local out = {}
    for _, c in ipairs(Pages.CLASHES) do
        if c.module == module then out[#out + 1] = c end
    end
    return out
end

-- Whether Daylight UI's side of a clash is a whole module, the kind the setup
-- guide asks about (it switches modules, not settings).
function Pages.ClashWhole(c)
    return c.module ~= nil and c.settings == nil and not c.core
end

-- Whether Daylight UI's side of a clash is running right now: the module is
-- on and, for a part of one, one of its settings is.
function Pages.ClashOurs(c)
    if c.core then return true end
    local mod = DUI:GetModule(c.module)
    if not (mod and mod.enabled) then return false end
    if not c.settings then return DUI:Get(c.module, "enabled") ~= false end
    for _, s in ipairs(c.settings) do
        if DUI:Get(s[1], s[2]) then return true end
    end
    return false
end

-- The frames one portrait choice sets. Not party, whose setup decides (the
-- Healer setup's tiles have none, and a pick here mustn't add them back).
Pages.PORTRAIT_UNITS = { "player", "target", "focus" }

-- The frames' own style picks (the unit frames' STYLE_FRAMES). The Frame
-- style cards reset them to "global" so the pick reaches every frame.
Pages.STYLE_FOLLOWERS = { "player.style", "target.style", "focus.style", "party.style" }

-- The setup guide's questions, one page each, in parts (the part's title
-- shows over the question). A question is answered by one pick of:
--   role = true      the layout (every talent set gets it)
--   option = { scope, key } with only = { values, in order }: one options item;
--     colorKey: picking "custom" opens the color picker for this key
--   presets = { { id, label, sub, set = { { scope, key, value } } } }: several
--     settings at once
--   look = kind      two looks of one thing (InstallerLooks.KINDS)
--   bundle = { yes, no, set, ... }: a yes or no that picks a set of settings
-- and carries its words (ask, what), a short name for the Finish page's tags
-- (short), its picture (draw), and optional labels and subs per choice and new
-- (a choice that's new in 2.0). needs: the module it belongs to; a question's
-- own needs wins over its part's. A question whose module is off, missing or
-- handed to another addon is left out, and so is a look that can't show.
-- quick = true: Quick setup asks it too.
Pages.PARTS = {
    { id = "layout", title = "Layout", questions = {
        { id = "role", short = "Layout", role = true, draw = "screen",
          ask = "Which layout do you start from?",
          what = "This decides where everything sits on your screen. You can move any piece later." },
    } },
    { id = "look", title = "Look", questions = {
        { id = "accent", short = "Colors", option = { "general", "accent" }, colorKey = "accentColor", draw = "accent", width = 237,
          only = { "classGradient", "gradient", "daylight", "class", "custom" },
          subs = { classGradient = "Your class color as a sweep.", gradient = "The signature blue to pink.",
                   daylight = "A soft warm gray.", class = "One flat class color.", custom = "Opens the color picker." },
          ask = "Pick your colors",
          what = "This color goes on your bars, borders and highlights. Run your mouse across them to try each one." },
        { id = "font", short = "Font", option = { "general", "font" }, only = DUI.Style.FONT_PICKS, draw = "font",
          ask = "Pick your font",
          what = "The lettering for every name, number and window. Run your mouse across them to try each one." },
    } },
    { id = "frames", title = "Frames", needs = "UnitFrames", questions = {
        { id = "portrait", short = "Portraits", look = "portraitLook",
          labels = { socket = "2.0", classic = "Classic" },
          subs = { socket = "The border runs around the portrait and the bar as one piece.",
                   classic = "The ring lies over the frame." },
          new = { socket = true },
          ask = "How should portraits look?",
          what = "The portrait is the picture of your character beside your health bar." },
        -- Under your frame, or between your frame and the target's with the
        -- swing timers fanning out below it.
        { id = "cast", short = "Cast bar", draw = "screen", screen = "cast",
          presets = {
              { id = "below", label = "Under your frame", sub = "Slides out from under your frame as you cast.", set = {
                  { "UnitFrames", "playerCastbar.at", "below" } } },
              { id = "middle", label = "Between the frames", sub = "In the middle, the swing timers fanning out under it.", set = {
                  { "UnitFrames", "playerCastbar.at", "middle" }, { "UnitFrames", "swing.attach", true } } },
          },
          ask = "Where should your cast bar sit?",
          what = "The cast bar fills up while you cast a spell." },
    } },
    { id = "bars", title = "Action bars", needs = "ActionBars", questions = {
        { id = "bars", short = "Action bars", draw = "screen", screen = "bars",
          presets = {
              { id = "one", label = "One row", sub = "Just your main bar.", set = {
                  { "ActionBars", "bars.bar2.visible", "hidden" }, { "ActionBars", "bars.left.visible", "hidden" },
                  { "ActionBars", "bars.right.visible", "hidden" } } },
              { id = "two", label = "Two rows", sub = "A second bar above it.", set = {
                  { "ActionBars", "bars.bar2.visible", "always" }, { "ActionBars", "bars.left.visible", "hidden" },
                  { "ActionBars", "bars.right.visible", "hidden" } } },
              { id = "sides", label = "Two rows and side bars", sub = "Side bars that fade until you need them.", set = {
                  { "ActionBars", "bars.bar2.visible", "always" }, { "ActionBars", "bars.left.visible", "always" },
                  { "ActionBars", "bars.right.visible", "always" } } },
          },
          ask = "How many bars on screen?",
          what = "Your spells and abilities sit on these. You can add or move bars later." },
        { id = "barCosts", short = "Spell costs", look = "spellCosts",
          labels = { on = "Show costs", off = "Keep it clean" },
          subs = { on = "Mana, rage or energy on each button.", off = "Just the icon and its key." },
          ask = "Spell costs on your buttons?",
          what = "Each spell's cost in the corner of its button, turning red while you're short of mana, rage or energy." },
    } },
    { id = "procs", title = "Proc Alerts", needs = "Procs", questions = {
        { id = "procs", short = "Proc Alerts", look = "procAlerts",
          labels = { on = "Light them up", off = "Leave them off" },
          subs = { on = "A flare around you when a proc is ready.", off = "No flares, as before." },
          new = { on = true },
          ask = "Light up your procs?",
          what = "A painted flare around your character when a proc like Clearcasting or Overpower is ready to use." },
    } },
    { id = "plates", title = "Nameplates", needs = "Nameplates", questions = {
        { id = "plateSize", short = "Nameplate size", draw = "plate", width = 250,
          presets = {
              { id = "small", label = "Small", set = {
                  { "Nameplates", "scale", 0.85 }, { "Nameplates", "width", 150 }, { "Nameplates", "height", 14 } } },
              { id = "medium", label = "Medium", set = {
                  { "Nameplates", "scale", 1 }, { "Nameplates", "width", 170 }, { "Nameplates", "height", 16 } } },
              { id = "large", label = "Large", set = {
                  { "Nameplates", "scale", 1.2 }, { "Nameplates", "width", 190 }, { "Nameplates", "height", 20 } } },
          },
          ask = "How big should nameplates be?",
          what = "Nameplates are the health bars that float over enemies' heads." },
        -- The row is "Health text"; its own format setting decides what the number shows.
        { id = "platePct", short = "Health percent", option = { "Nameplates", "percent" }, only = { true, false },
          draw = "plate", plate = "percent",
          labels = { [true] = "Show it", [false] = "Keep it clean" },
          subs = { [true] = "A number you can read at a glance.", [false] = "Just the bar." },
          ask = "Health numbers on nameplates?",
          what = "A number on each nameplate showing how much health the enemy has left." },
        { id = "plateDebuffs", short = "Debuffs", option = { "Nameplates", "debuffs" }, only = { true, false },
          draw = "plate", plate = "debuffs",
          labels = { [true] = "Show them", [false] = "Leave them off" },
          subs = { [true] = "Your DoTs and effects over each enemy.", [false] = "Nothing over the name." },
          ask = "Your debuffs on nameplates?",
          what = "Little icons over an enemy for the effects you put on it, with their time left." },
        { id = "plateIcons", short = "Class icons", look = "plateClassIcon",
          labels = { above = "Show class icons", none = "Names only" },
          subs = { above = "An icon above each name.", none = "Just the name, as it is now." },
          new = { above = true },
          ask = "Class icons on friendly players?",
          what = "A small icon over other players' heads, so you can spot the healer in a crowd." },
    } },
    { id = "calm", title = "Out of a fight", needs = "ActionBars", questions = {
        { id = "calm", short = "Out of a fight", draw = "screen", screen = "calm",
          presets = {
              { id = "shown", label = "Always shown", sub = "Everything stays on screen.", set = {
                  { "ActionBars", "bars.main.fade.mode", "never" }, { "ActionBars", "bars.bar2.fade.mode", "never" },
                  { "UnitFrames", "player.fade.mode", "never" } } },
              { id = "calm", label = "Calm", sub = "Bars and your frame fade after a fight.", set = {
                  { "ActionBars", "bars.main.fade.mode", "ooc" }, { "ActionBars", "bars.bar2.fade.mode", "ooc" },
                  { "UnitFrames", "player.fade.mode", "ooc" } } },
              { id = "float", label = "Only when something changes", sub = "Gone until a fight or a change.", set = {
                  { "ActionBars", "bars.main.fade.mode", "float" }, { "ActionBars", "bars.bar2.fade.mode", "float" },
                  { "UnitFrames", "player.fade.mode", "float" } } },
          },
          ask = "Out of a fight, what stays?",
          what = "When you're not fighting, Daylight UI can step out of the way. Hover one to watch it." },
    } },
    { id = "everyday", title = "Everyday", questions = {
        { id = "tooltip", short = "Tooltips", needs = "Tooltip", look = "tooltipStyle",
          labels = { rich = "Rich", simple = "Simple" },
          subs = { rich = "Daylight UI's own cards: name and tags up top, every number in tidy rows.",
                   simple = "The game's tooltip in the Daylight look." },
          new = { rich = true },
          ask = "Which tooltips do you like?",
          what = "The tooltip is the box that pops up when you point at an item or a player." },
        { id = "bags", short = "Bags", needs = "Bags", option = { "Bags", "view" }, only = { "categories", "grid", "list" },
          draw = "bags",
          labels = { categories = "Shelf", grid = "Grid", list = "List" },
          subs = { categories = "Grouped by kind, a heading for each group.", grid = "One even grid, bag by bag.",
                   list = "A row per item." },
          ask = "How should your bags be arranged?",
          what = "How your items are laid out when you open your bags." },
    } },
    -- A bundle is yes or no: yes picks every setting in set, no leaves them as
    -- the setup has them. A setting with `addon` is only picked while that
    -- addon is on (the arrow has nothing to point at without QuestieDB).
    { id = "questing", title = "Questing", needs = "Quests", questions = {
        { id = "quest", short = "Quest helper", quick = true, draw = "quest",
          ask = "Want the quest helper?",
          what = "The quest helper points the way to your next quest.",
          bundle = {
              yes = { "Yes, the quest helper", "A marker and breadcrumbs to your quest." },
              no = { "No, keep it simple", "Just the tracker. Add the rest later." },
              set = {
                  { "Quests", "nav.marker", true }, { "Quests", "nav.trail", true },
                  { "Quests", "nav.arrow", true, addon = "QuestieDB" },
                  { "Quests", "progress", true }, { "Quests", "journal", true },
              },
          } },
    } },
}

-- Every question with its part's title (part) and the module it needs, in order.
function Pages.AllQuestions()
    local out = {}
    for _, part in ipairs(Pages.PARTS) do
        for _, q in ipairs(part.questions) do
            q.part, q.partId = part.title, part.id
            q.needs = q.needs or part.needs
            out[#out + 1] = q
        end
    end
    return out
end

-- A question by id.
function Pages.Question(id)
    for _, q in ipairs(Pages.AllQuestions()) do
        if q.id == id then return q end
    end
end

-- Whether a question can be asked now: its module is loaded and not handed
-- to another addon, its look can show and its options exist.
function Pages.Asks(q)
    if q.needs and not Pages.Loaded(q.needs) then return false end
    local flow = DUI.Installer and DUI.Installer.flow
    local mod = q.needs and Pages.Module(q.needs)
    if mod and flow and flow.modules and flow.modules[mod.addon] == false then return false end
    if q.look then return DUI.InstallerLooks.Available(q.look) end
    if q.option then return Pages.Find(q.option[1], q.option[2]) ~= nil end
    for _, r in ipairs(Pages.Refs(q)) do
        if Pages.Find(r[1], r[2]) then return true end
    end
    return q.role == true or q.bundle ~= nil
end

-- The questions that apply now: every one for "tour", the quick ones for "quick".
function Pages.Questions(path)
    local out = {}
    for _, q in ipairs(Pages.AllQuestions()) do
        if (path == "tour" or (path == "quick" and q.quick)) and Pages.Asks(q) then out[#out + 1] = q end
    end
    return out
end

-- Pages before plugins' own (Pages.PLUGIN), in the shape plugins use: a page
-- of groups. Daylight UI's own questions are Pages.PARTS now, so this is
-- empty; plugins' pages are built on the same shape (Pages.All).
-- A group is a card (an options card heading) holding one of:
--   cards = one option as picture cards { scope, key, draw, cols, height,
--     only (these keys, in this order), max (at most this many), more (adds
--     a dropdown row of the same option with this label for the full list),
--     colorKey (picking "custom" opens the color picker for this key),
--     along (these keys take the same pick; another module's as { module, key }) }
--   rows = options as rows { { scope, key, label = optional } }; notes = true
--     prints each one's help under it
--   portraits = one choice for every frame's portrait (true), or another of
--     their settings by key ("portraitRing"), with draw/cols/height as cards
--   samples = your frame and a target drawn in the window (module Samples)
--   look = two looks of one thing drawn side by side, a card each to pick
--   presets = several settings picked at once as picture cards { { id,
--     label, sub, set = { { scope, key, value } } } }, draw/cols/height as
--     cards. The card whose settings all match shows as picked.
-- needs: the module the group belongs to.
Pages.TOUR = {}

-- The setting a portraits group sets in each frame: "portrait" or its own.
function Pages.PortraitKey(group)
    return group.portraits == true and "portrait" or group.portraits
end

-- An option's page and item by scope and key. Nil when its module isn't
-- loaded or the options changed. An item shown on another module's page
-- (its `scope` names the module that owns it, like the Tooltip page's
-- "Quests in NPC tooltips") is found by that module's scope too.
function Pages.Find(scope, key)
    local Options = DUI.Options
    if not (Options and Options.Pages) then return nil end
    local shown
    for _, page in Options.Pages() do
        for _, group in ipairs(page.groups or {}) do
            for _, item in ipairs(group.items or {}) do
                local also = false
                for _, k in ipairs(item.alsoKeys or {}) do also = also or k == key end
                if item.key == key or also then
                    if page.scope == scope then return page, item end
                    if item.scope == scope then shown = item end
                end
            end
        end
    end
    local mod = shown and DUI:GetModule(scope)
    if mod then return { scope = scope, defaults = mod.defaults }, shown end
end

-- Whether a module (by suite name, e.g. "Bags") is loaded and running.
function Pages.Loaded(name)
    if name == nil or name == "general" then return true end
    local mod = DUI:GetModule(name)
    return mod ~= nil and mod.enabled == true
end

-- A group's option references as { scope, key } pairs.
function Pages.Refs(group)
    local out = {}
    local c = group.cards
    if not c and group.option then c = { scope = group.option[1], key = group.option[2], colorKey = group.colorKey } end
    if c then
        out[#out + 1] = { c.scope, c.key }
        if c.colorKey then out[#out + 1] = { c.scope, c.colorKey } end
    end
    for _, r in ipairs(group.rows or {}) do out[#out + 1] = { r[1], r[2] } end
    local look = group.look and DUI.InstallerLooks.KINDS[group.look]
    if look then out[#out + 1] = { look.ref[1], look.ref[2] } end
    local seen = {}
    for _, p in ipairs(group.presets or {}) do
        for _, s in ipairs(p.set) do
            local id = s[1] .. "|" .. s[2]
            if not seen[id] then seen[id] = true; out[#out + 1] = { s[1], s[2] } end
        end
    end
    return out
end

-- The preset whose settings all match right now, or nil. Settings of a module
-- that's off are skipped, as picking one skips them.
function Pages.PresetOn(group)
    for _, p in ipairs(group.presets or {}) do
        local all, any = true, false
        for _, s in ipairs(p.set) do
            if Pages.Loaded(s[1]) then
                any = true
                if DUI:Get(s[1], s[2]) ~= s[3] then all = false; break end
            end
        end
        if all and any then return p end
    end
end

-- Whether a group can show: its module is loaded and one of its options exists.
function Pages.GroupAvailable(group)
    if group.needs and not Pages.Loaded(group.needs) then return false end
    if group.portraits then return Pages.Find("UnitFrames", "player." .. Pages.PortraitKey(group)) ~= nil end
    if group.look and not DUI.InstallerLooks.Available(group.look) then return false end
    if group.samples then
        local mod = DUI:GetModule("UnitFrames")
        return mod ~= nil and mod.Samples ~= nil
    end
    for _, r in ipairs(Pages.Refs(group)) do
        if Pages.Find(r[1], r[2]) then return true end
    end
    return false
end

-- Whether a tour page appears: it has a builder, or it's a page of groups
-- with at least one group to show.
function Pages.Available(def)
    local Steps = DUI.InstallerSteps
    if not (Steps and Steps.Has(def)) then return false end
    if def.needs and not Pages.Loaded(def.needs) then return false end
    if not def.groups then return true end
    for _, g in ipairs(def.groups) do
        if Pages.GroupAvailable(g) then return true end
    end
    return false
end

-- Plugins' pages (DaylightUI.API: me.AddSetupStep), after Daylight UI's own,
-- in the order they were added. Same shape as TOUR's, plus `plugin` (its name)
-- and an optional `onFinish` run when the player finishes the guide.
Pages.PLUGIN = {}

local function allPages()
    local out = {}
    for _, def in ipairs(Pages.TOUR) do out[#out + 1] = def end
    for _, def in ipairs(Pages.PLUGIN) do out[#out + 1] = def end
    return out
end
Pages.All = allPages

-- Whether a plugin's page has something to show: settings (groups) or its
-- own content (text, image, buttons, build).
function Pages.HasContent(def)
    return type(def.groups) == "table" or type(def.text) == "string" or def.image ~= nil
        or type(def.buttons) == "table" or type(def.build) == "function"
end

-- False (and why) when the step can't be taken: a missing id or title,
-- nothing to show, or an id already used.
function Pages.AddStep(plugin, def)
    if type(def) ~= "table" or type(def.id) ~= "string" or def.id == "" or type(def.title) ~= "string"
        or not Pages.HasContent(def) then
        return false, "a step needs an id, a title, and groups, text, image, buttons or build"
    end
    local id = plugin .. ":" .. def.id
    if id == "welcome" or id == "finish" then return false, "that id is taken" end
    for _, d in ipairs(allPages()) do
        if d.id == id and d.plugin ~= plugin then return false, "that id is taken" end
    end
    local copy = {}
    for k, v in pairs(def) do copy[k] = v end
    copy.id, copy.plugin, copy.quick = id, plugin, def.quick == true or nil
    for i, d in ipairs(Pages.PLUGIN) do
        if d.id == id then Pages.PLUGIN[i] = copy return true end
    end
    Pages.PLUGIN[#Pages.PLUGIN + 1] = copy
    return true
end

function Pages.Get(id)
    for _, def in ipairs(allPages()) do
        if def.id == id then return def end
    end
end

-- Plugins' pages Make it mine shows after the questions, in order
-- (excluding Quick-only ones, tour = false).
function Pages.Tour()
    local out = {}
    for _, def in ipairs(allPages()) do
        if def.tour ~= false and Pages.Available(def) then out[#out + 1] = def end
    end
    return out
end

-- Plugins' pages Quick setup shows after its questions, in order.
function Pages.Quick()
    local out = {}
    for _, def in ipairs(allPages()) do
        if def.quick and Pages.Available(def) then out[#out + 1] = def end
    end
    return out
end

-- Every option the questions (or the given questions and pages) can write,
-- for the draft to track, as { scope, key }.
function Pages.Keys(defs)
    local out = {}
    for _, def in ipairs(defs or Pages.Questions("tour")) do
        for _, s in ipairs(def.bundle and def.bundle.set or {}) do out[#out + 1] = { s[1], s[2] } end
        for _, s in ipairs(def.bundle and def.bundle.always or {}) do out[#out + 1] = { s[1], s[2] } end
        if not def.groups then
            for _, r in ipairs(Pages.Refs(def)) do
                if Pages.Find(r[1], r[2]) then out[#out + 1] = { r[1], r[2] } end
            end
        end
        for _, g in ipairs(def.groups or {}) do
            if Pages.GroupAvailable(g) then
                if g.portraits then
                    local key = Pages.PortraitKey(g)
                    for _, u in ipairs(Pages.PORTRAIT_UNITS) do
                        if DUI:Get("UnitFrames", u .. "." .. key) ~= nil then out[#out + 1] = { "UnitFrames", u .. "." .. key } end
                    end
                end
                for _, r in ipairs(Pages.Refs(g)) do
                    if Pages.Find(r[1], r[2]) then out[#out + 1] = { r[1], r[2] } end
                end
            end
        end
    end
    return out
end

-- The options page for changing a tour page's choices later: its own, else
-- the page its first option is on.
function Pages.Later(def)
    if def.later then return DUI.Options.GetPage(def.later) and def.later or nil end
    for _, g in ipairs(def.groups or {}) do
        if Pages.GroupAvailable(g) then
            local refs = Pages.Refs(g)
            if g.portraits then refs = { { "UnitFrames", "player." .. Pages.PortraitKey(g) } } end
            for _, r in ipairs(refs) do
                local page = Pages.Find(r[1], r[2])
                if page then return page.id end
            end
        end
    end
end

-- Where an options page sits in the window, e.g. "General > Appearance".
function Pages.Where(pageId)
    local Options = DUI.Options
    local page = Options.GetPage(pageId)
    if not page then return nil end
    for _, s in ipairs(Options.Sections()) do
        if s.id == page.section then return Options.Text(s.label) .. " > " .. Options.Text(page.label) end
    end
    return Options.Text(page.label)
end

function Pages.Module(name)
    for _, m in ipairs(Pages.MODULES) do
        if m.name == name then return m end
    end
end

-- This character as the AddOns list identifies it: its GUID, as the game's
-- own list passes it (Blizzard_AddOnList uses UnitGUID("player")). A name
-- switched nothing for the player. Nil when the game can't say plainly; never
-- falls back to every character.
function Pages.Character()
    local guid = UnitGUID("player")
    if type(guid) ~= "string" or DUI.IsSecret(guid) then return nil end
    return guid
end

function Pages.EnabledFor(addon)
    local api = C_AddOns
    local me = Pages.Character()
    if not (api and api.GetAddOnEnableState and me) then return nil end
    local ok, state = pcall(api.GetAddOnEnableState, addon, me)
    if ok and type(state) == "number" then return state > 0 end
    return nil
end

-- Enabled for this character, or loaded when the game can't say.
function Pages.AddonOn(addon)
    local on = Pages.EnabledFor(addon)
    if on ~= nil then return on end
    local api = C_AddOns
    return api ~= nil and api.IsAddOnLoaded ~= nil and api.IsAddOnLoaded(addon) == true
end

function Pages.AddonInstalled(addon)
    local api = C_AddOns
    if api and api.DoesAddOnExist then return api.DoesAddOnExist(addon) == true end
    return Pages.AddonOn(addon)
end

-- The clashes to show: the other addon is loaded right now (and, for one
-- that clashes only through its own options, one of them is on).
function Pages.Clashes()
    local out = {}
    local api = C_AddOns
    if not (api and api.IsAddOnLoaded) then return out end
    for _, c in ipairs(Pages.CLASHES) do
        if api.IsAddOnLoaded(c.addon) and (not c.options or c.options()) then out[#out + 1] = c end
    end
    return out
end
