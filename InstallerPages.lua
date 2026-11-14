-- The setup guide's content as data: the modules it introduces, other addons
-- that do the same jobs, and what each tour page offers. Choices point at the
-- options' own items by scope and key, so the guide always offers the same
-- labels, help text and values as the options window. Choices whose module
-- isn't loaded are left out, and a page left empty is skipped.

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
    { addon = "DaylightUI_QoL", name = "QoL", label = "Quality of Life",
      pitch = "Small helpers: faster looting, quest automation, trainers and more." },
}

-- Other addons that replace the same thing as one of ours. Same list
-- DUI.WarnIfLoaded warns about in chat.
Pages.CLASHES = {
    { module = "ActionBars", addon = "EllesmereUIActionBars", label = "EllesmereUI Action Bars", what = "action bars" },
    { module = "ActionBars", addon = "EllesmereUICooldownManager", label = "EllesmereUI Cooldown Manager", what = "Cooldown Manager icons" },
    { module = "Bags", addon = "Baganator", label = "Baganator", what = "bags" },
    { module = "Bags", addon = "Bagnon", label = "Bagnon", what = "bags" },
    { module = "Buffs", addon = "BuffLedger", label = "BuffLedger", what = "buff bars" },
    { module = "Chat", addon = "EllesmereUIChat", label = "EllesmereUI Chat", what = "chat" },
    { module = "InfoPanel", addon = "EllesmereUIMinimap", label = "EllesmereUI Minimap", what = "minimap" },
    { module = "InfoPanel", addon = "EllesmereUIDamageMeters", label = "EllesmereUI Damage Meters", what = "damage meter" },
    { module = "Quests", addon = "!KalielsTracker", label = "Kaliel's Tracker", what = "quest tracker" },
    { module = "Quests", addon = "EllesmereUIQuestTracker", label = "EllesmereUI Quest Tracker", what = "quest tracker" },
    { module = "Nameplates", addon = "Platynator", label = "Platynator", what = "nameplates" },
    { module = "Nameplates", addon = "EllesmereUINameplates", label = "EllesmereUI Nameplates", what = "nameplates" },
    { module = "Nameplates", addon = "TidyPlates_ThreatPlates", label = "Threat Plates", what = "nameplates" },
    { module = "Nameplates", addon = "Plater", label = "Plater", what = "nameplates" },
    { module = "Nameplates", addon = "Kui_Nameplates", label = "Kui Nameplates", what = "nameplates" },
    { module = "Skins", addon = "EllesmereUIBlizzardSkin", label = "EllesmereUI Blizzard Skin", what = "game windows" },
    { module = "UnitFrames", addon = "EllesmereUIUnitFrames", label = "EllesmereUI Unit Frames", what = "frames" },
}

-- One module's entries from that list (modules warn from it too).
function Pages.ClashesFor(module)
    local out = {}
    for _, c in ipairs(Pages.CLASHES) do
        if c.module == module then out[#out + 1] = c end
    end
    return out
end

-- Classes that can heal. Without a role from the game, the role page says so
-- instead of recommending one.
Pages.HEALERS = { PRIEST = true, DRUID = true, SHAMAN = true, PALADIN = true, MONK = true, EVOKER = true }

-- The frames one portrait choice sets. Not party, whose setup decides (the
-- Healer setup's tiles have none, and a pick here mustn't add them back).
Pages.PORTRAIT_UNITS = { "player", "target", "focus" }

-- The frames' own style picks (the unit frames' RIBBON_FRAMES). The Frame
-- style cards reset them to "global" so the pick reaches every frame.
Pages.STYLE_FOLLOWERS = { "player.style", "target.style", "focus.style", "party.style" }

-- The tour, in order. Pages with their own builder (InstallerSteps.lua) have
-- no groups. A group is a card (an options card heading) holding one of:
--   cards = one option as picture cards { scope, key, draw, cols, height,
--     only (these keys, in this order), max (at most this many), more (adds
--     a dropdown row of the same option with this label for the full list),
--     colorKey (picking "custom" opens the color picker for this key) }
--   rows = options as rows { { scope, key, label = optional } }; notes = true
--     prints each one's help under it
--   portraits = one choice for every frame's portrait (true), or another of
--     their settings by key ("portraitRing"), with draw/cols/height as cards
--   samples = your frame and a target drawn in the window (module Samples)
--   presets = several settings picked at once as picture cards { { id,
--     label, sub, set = { { scope, key, value } } } }, draw/cols/height as
--     cards. The card whose settings all match shows as picked.
-- needs: the module the group belongs to.
Pages.TOUR = {
    { id = "modules", title = "What's included", later = "home",
      desc = "Every part of DaylightUI and what it does. Switch off any you don't want; that applies when you reload." },
    { id = "role", title = "Your role", later = "profiles",
      desc = "Where your frames sit. Healers get the group as big tiles in the middle of the screen." },
    { id = "look", title = "Look",
      desc = "The colors, font and textures used everywhere. The screen changes as you pick.",
      groups = {
          { label = "Accent color", cards = { scope = "general", key = "accent", draw = "swatch", cols = 3, height = 64, colorKey = "accentColor" } },
          { label = "Font", cards = { scope = "general", key = "font", draw = "font", cols = 4, height = 56, only = DUI.Style.FONT_PICKS, more = "Every font" } },
          { label = "Bar texture", cards = { scope = "general", key = "barTexture", draw = "texture", cols = 4, height = 50, only = DUI.Media.BAR_PICKS, more = "Every texture" } },
          { label = "Size", rows = { { "general", "scale" }, { "general", "fontScale" } } },
          { label = "Finishing touches", rows = { { "general", "heavyBorder" }, { "general", "gradientBorder" }, { "general", "smoothBars" } } },
          { label = "Interrupts", needs = "Nameplates",
            cards = { scope = "Nameplates", key = "kickStyle", draw = "kick", cols = 4, height = 50 } },
          { label = "", needs = "Nameplates", rows = { { "Nameplates", "kickedBy" } } },
      } },
    -- Samples are drawn inside the window, not as test mode frames on screen,
    -- which the window would cover and crowd.
    { id = "frames", title = "Frames",
      desc = "Your unit frames, shown here with sample units so you can see each choice.",
      groups = {
          { label = "", needs = "UnitFrames", samples = true },
          { label = "Frame style", needs = "UnitFrames",
            cards = { scope = "UnitFrames", key = "look.style", draw = "frameStyle", cols = 2, height = 96,
                      follow = Pages.STYLE_FOLLOWERS } },
          { label = "Health bar color", needs = "UnitFrames",
            cards = { scope = "UnitFrames", key = "colors.health", draw = "health", cols = 3, height = 52 } },
          -- The color for "One color" (grayed out until picked, as in the options).
          { label = "", needs = "UnitFrames", rows = { { "UnitFrames", "colors.healthColor" } } },
          { label = "Portraits", needs = "UnitFrames", portraits = true },
          { label = "Ring color", needs = "UnitFrames", portraits = "portraitRing", draw = "portraitRing", cols = 3, height = 90 },
          -- Where your cast bar sits: under your frame, or between your frame and the
          -- target's with the swing timers fanning out below it.
          { label = "Cast bar", needs = "UnitFrames", draw = "castbar", cols = 2, height = 104, presets = {
              { id = "below", label = "Under your frame", sub = "Slides out from under your frame as you cast.", set = {
                  { "UnitFrames", "playerCastbar.at", "below" } } },
              { id = "middle", label = "Between the frames", sub = "In the middle, the swing timers fanning out under it.", set = {
                  { "UnitFrames", "playerCastbar.at", "middle" }, { "UnitFrames", "swing.attach", true } } },
          } },
      } },
    -- What players notice first: the bars, the plates, and whether the UI steps
    -- aside out of combat.
    { id = "bars", title = "Action bars", later = "ActionBars.barlayout",
      desc = "How many bars sit on your screen. Each one can be changed on its own later.",
      groups = {
          { label = "Bars on screen", needs = "ActionBars", draw = "bars", cols = 3, height = 104, presets = {
              { id = "one", label = "One row", sub = "Just your main bar.", set = {
                  { "ActionBars", "bars.bar2.visible", "hidden" }, { "ActionBars", "bars.left.visible", "hidden" },
                  { "ActionBars", "bars.right.visible", "hidden" } } },
              { id = "two", label = "Two rows", sub = "A second bar above it.", set = {
                  { "ActionBars", "bars.bar2.visible", "always" }, { "ActionBars", "bars.left.visible", "hidden" },
                  { "ActionBars", "bars.right.visible", "hidden" } } },
              { id = "sides", label = "Two rows and side bars", sub = "Side bars that fade until you need them.", set = {
                  { "ActionBars", "bars.bar2.visible", "always" }, { "ActionBars", "bars.left.visible", "always" },
                  { "ActionBars", "bars.right.visible", "always" } } },
          } },
          { label = "", needs = "ActionBars", rows = { { "ActionBars", "hideEmpty" } } },
      } },
    { id = "plates", title = "Nameplates", later = "Nameplates.plates",
      desc = "The bars over enemies' heads: how big they are, and what they show.",
      groups = {
          { label = "Size", needs = "Nameplates", draw = "plates", cols = 3, height = 84, presets = {
              { id = "small", label = "Small", set = {
                  { "Nameplates", "scale", 0.85 }, { "Nameplates", "width", 150 }, { "Nameplates", "height", 14 } } },
              { id = "medium", label = "Medium", set = {
                  { "Nameplates", "scale", 1 }, { "Nameplates", "width", 170 }, { "Nameplates", "height", 16 } } },
              { id = "large", label = "Large", set = {
                  { "Nameplates", "scale", 1.2 }, { "Nameplates", "width", 190 }, { "Nameplates", "height", 20 } } },
          } },
          { label = "", needs = "Nameplates", rows = { { "Nameplates", "percent" }, { "Nameplates", "debuffs" }, { "Nameplates", "threat" } } },
      } },
    { id = "calm", title = "Calm or always shown", later = "fade", needs = "ActionBars",
      desc = "Whether your bars and your frame step aside when you're not fighting. Every part has its own Visible setting later.",
      groups = {
          { label = "Out of a fight", needs = "ActionBars", draw = "calm", cols = 3, height = 104, presets = {
              { id = "shown", label = "Always shown", sub = "Everything stays on screen.", set = {
                  { "ActionBars", "bars.main.fade.mode", "never" }, { "ActionBars", "bars.bar2.fade.mode", "never" },
                  { "UnitFrames", "player.fade.mode", "never" } } },
              { id = "calm", label = "Calm", sub = "Bars and your frame fade after a fight.", set = {
                  { "ActionBars", "bars.main.fade.mode", "ooc" }, { "ActionBars", "bars.bar2.fade.mode", "ooc" },
                  { "UnitFrames", "player.fade.mode", "ooc" } } },
              { id = "float", label = "Only when something changes", sub = "Gone until a fight or a change.", set = {
                  { "ActionBars", "bars.main.fade.mode", "float" }, { "ActionBars", "bars.bar2.fade.mode", "float" },
                  { "UnitFrames", "player.fade.mode", "float" } } },
          } },
          { label = "", rows = { { "general", "fadeOpenWorldOnly" } } },
      } },
    { id = "everyday", title = "Everyday",
      spotlight = { "DaylightUIChat", "DaylightUIInfoPanel" },
      desc = "Bags, chat, the info panel and tooltips: the things you use all the time.",
      groups = {
          { label = "Bags", needs = "Bags", cards = { scope = "Bags", key = "view", draw = "bagview", cols = 2, height = 70 } },
          { label = "", needs = "Bags", rows = { { "Bags", "sellJunk" }, { "Bags", "autoRepair" } } },
          { label = "Chat", needs = "Chat", rows = { { "Chat", "timestamps" }, { "Chat", "classColors" }, { "Chat", "shortTags" }, { "Chat", "hides" } } },
          { label = "Info panel", needs = "InfoPanel", rows = {
              { "InfoPanel", "meter.enabled", label = "Damage meter" },
              { "InfoPanel", "meter.detached", label = "Damage meter position",
                choice = { "In the info panel", "Bottom-right corner" } },
              { "InfoPanel", "xp.enabled", label = "XP bar" },
              { "InfoPanel", "xp.detached", label = "XP bar position",
                choice = { "In the info panel", "Under the action bars" } } } },
          { label = "Tooltips", needs = "Tooltip", rows = { { "Tooltip", "anchor" } } },
      } },
    { id = "questing", title = "Questing",
      spotlight = { "DaylightUIQuestTracker" },
      desc = "How you find your way to quests, how they show in the tracker, and how talking to NPCs looks.",
      groups = {
          { label = "Finding your way", needs = "Quests", notes = true, rows = {
              { "Quests", "nav.marker" }, { "Quests", "nav.style" }, { "Quests", "nav.trail" },
              { "Quests", "nav.arrow" } } },
          { label = "Tracker", needs = "Quests", rows = {
              { "Quests", "filter" }, { "Quests", "sort" }, { "Quests", "questLevels" },
              { "Quests", "questTags" }, { "Quests", "hideDone" } } },
          { label = "Pop-up and quest log", needs = "Quests", notes = true, rows = {
              { "Quests", "progress" }, { "Quests", "journal" } } },
          { label = "Talking to NPCs", rows = { { "NPC", "look" } } },
      } },
    -- Quick setup's one questing question (Quick only, the tour has the page
    -- above), shown between the setup button and Finish. A bundle is yes or no:
    -- yes picks every setting in set, no leaves them as the setup has them. A
    -- setting with `addon` is only picked while that addon is on (the arrow has
    -- nothing to point at without QuestieDB).
    { id = "questhelp", title = "Questing", quick = true, tour = false, needs = "Quests", later = "Quests.navigation",
      desc = "A marker over the quest you picked and breadcrumbs on the ground leading to it. With the QuestieDB addon, an arrow to the nearest objective too.",
      bundle = {
          yes = { "Yes, the quest helper", "A marker and breadcrumbs to your quest." },
          no = { "No, keep it simple", "Just the tracker. Add the rest later." },
          summary = { yes = "the quest helper", no = "just the quest tracker" },
          needsAddon = "QuestieDB",
          hint = "QuestieDB isn't on, so the arrow is left out: it needs QuestieDB to know where each mob is.",
          set = {
              { "Quests", "nav.marker", true }, { "Quests", "nav.trail", true },
              { "Quests", "nav.arrow", true, addon = "QuestieDB" },
              { "Quests", "progress", true }, { "Quests", "journal", true },
          },
      } },
    { id = "qol", title = "Quality of life",
      desc = "Small helpers that save time every day. Each one says what it does.",
      groups = {
          { label = "", needs = "QoL", notes = true, rows = {
              { "QoL", "autoDelete" }, { "QoL", "fastLoot" }, { "QoL", "questAccept" }, { "QoL", "questTurnIn" },
              { "QoL", "skipGossip" }, { "QoL", "skipCinematics" }, { "QoL", "hideTutorials" },
              { "QoL", "quietErrors" } } },
      } },
}

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
    if c then
        out[#out + 1] = { c.scope, c.key }
        if c.colorKey then out[#out + 1] = { c.scope, c.colorKey } end
    end
    for _, r in ipairs(group.rows or {}) do out[#out + 1] = { r[1], r[2] } end
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

-- False (and why) when the step can't be taken: a missing id, title or
-- groups, or an id already used.
function Pages.AddStep(plugin, def)
    if type(def) ~= "table" or type(def.id) ~= "string" or def.id == "" or type(def.title) ~= "string"
        or type(def.groups) ~= "table" then
        return false, "a step needs an id, a title and groups"
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

-- The tour pages that will appear, in order (excluding Quick-only ones,
-- tour = false).
function Pages.Tour()
    local out = {}
    for _, def in ipairs(allPages()) do
        if def.tour ~= false and Pages.Available(def) then out[#out + 1] = def end
    end
    return out
end

-- The pages Quick setup shows, in order.
function Pages.Quick()
    local out = {}
    for _, def in ipairs(allPages()) do
        if def.quick and Pages.Available(def) then out[#out + 1] = def end
    end
    return out
end

-- Every option the tour (or the given pages) will show, for the draft to
-- track, as { scope, key }.
function Pages.Keys(defs)
    local out = {}
    for _, def in ipairs(defs or Pages.Tour()) do
        for _, s in ipairs(def.bundle and def.bundle.set or {}) do out[#out + 1] = { s[1], s[2] } end
        for _, s in ipairs(def.bundle and def.bundle.always or {}) do out[#out + 1] = { s[1], s[2] } end
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
    if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return nil end
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

-- The clashes to show: the other addon is loaded right now.
function Pages.Clashes()
    local out = {}
    local api = C_AddOns
    if not (api and api.IsAddOnLoaded) then return out end
    for _, c in ipairs(Pages.CLASHES) do
        if api.IsAddOnLoaded(c.addon) then out[#out + 1] = c end
    end
    return out
end
