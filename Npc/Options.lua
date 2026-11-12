-- The NPC window's options, as data.

local _, DUI = ...
DUI.Npc = DUI.Npc or {}
local ns = DUI.Npc

local backRows = DUI.Options.BackAlphaRows("windowAlpha", "NPC window", nil, "1.6.2")

ns.OPTIONS = { pages = {
    { id = "window", label = "NPC window",
      desc = "Talking to NPCs: gossip, quests to accept and hand in, rewards to choose, all in one window, in DaylightUI style.",
      groups = {
        { label = "Window", items = {
            { type = "toggle", key = "enabled", label = "DaylightUI style NPC window", reload = true,
              desc = "Talking to an NPC opens DaylightUI's window for gossip, quests and rewards. Turn it off to use the game's own windows." },
            { type = "text", label = "DaylightMogul's vendor window is in use.",
              hidden = function() return not DaylightUI.vendorMogul end },
            { type = "toggle", key = "vendor", label = "Vendor window", reload = true,
              disabled = function() return DaylightUI.vendorMogul == true end,
              desc = "Vendors open in the NPC window too, with their goods on a shelf. Turn it off to use the game's vendor window." },
            { type = "toggle", key = "trainer", label = "Trainer window", reload = true,
              desc = "Class and profession trainers open in the NPC window too, with what you can learn now and what's coming up. Pick a spell, then press Train or Train all: a click or a key alone never spends gold. Turn it off to use the game's trainer window." },
            { type = "dropdown", key = "look", label = "Look", values = { window = "Window", immersive = "Immersive" },
              order = { "window", "immersive" },
              disabled = function(get) return get("enabled") == false end,
              desc = "Window: talking opens a window at the side. Immersive: the talk is a card on the right, the camera comes in over your shoulder and the rest of the UI fades away until you're done. Vendors and trainers stay a window." },
            { type = "toggle", key = "typeText", label = "Text Slow Mode",
              disabled = function(get) return get("enabled") == false or get("look") ~= "immersive" end,
              desc = "With the immersive look, the NPC's words appear letter by letter and the choices drift in after them. Click or press the accept key to see them all at once." },
            { type = "toggle", key = "fadeUI", label = "Fade the UI while talking",
              disabled = function(get) return get("enabled") == false or get("look") ~= "immersive" end,
              desc = "With the immersive look, the whole UI fades away while you talk, so only the NPC and the talk are left. A fight brings everything back at once." },
            { type = "toggle", key = "zoom", label = "Move the camera in",
              disabled = function(get) return get("enabled") == false or get("look") ~= "immersive" end,
              desc = "With the immersive look, the camera comes in over your shoulder and looks at the NPC while you talk, then goes back to how you had it. Not while mounted or in a fight." },
            { type = "slider", key = "scale", label = "Window scale", min = 0.7, max = 1.3, step = 0.05, unit = "x",
              desc = "How big the window is." },
            backRows[1], backRows[2],
        } },
        { label = "Keys", items = {
            { type = "toggle", key = "keys", label = "Dialogue keys",
              desc = "Press 1 to 9 to pick a line or a reward, Space for the next step (accept, continue, complete), Escape to back out. Space never jumps while you talk. Other keys still go to the game, and in combat every key is the game's." },
            { type = "dropdown", key = "acceptKey", label = "Accept key", values = { both = "Enter or Space", enter = "Enter", space = "Space" },
              order = { "space", "enter", "both" },
              disabled = function(get) return get("keys") == false end,
              desc = "Which key accepts, continues and completes. Enter is also the key that opens chat." },
            { type = "toggle", key = "popupKeys", label = "Pop-up keys",
              desc = "Enter says yes when someone asks you something: a group invite, a shared quest, a summon, a resurrect. Never on anything that binds, rolls or costs, and never in combat. Making an inn your home takes your Accept key too." },
        } },
    } },
} }
