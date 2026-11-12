-- Options page for the scrolling combat text. Registry.lua calls CT.Page once
-- Options is loaded, right after the damage numbers page.

local _, DUI = ...
local CT = DUI.CombatText

local function off() return CT.Live() ~= true end

local function row(item)
    item.disabled = off
    return item
end

local function fontRow(Options)
    return row({ type = "dropdown", key = "damage.sctFont", label = "Combat text font", choices = Options.DamageFontChoices,
        fallback = "auto", preview = "font", fetch = function(key)
            if key == "auto" then return DUI.GameFonts.CombatTextWanted() or DUI.Style.FONT end
            return DUI.Media.Fetch("font", key) or (DUI.Style.FONTS[key] and DUI.Style.FONTS[key].file)
        end,
        desc = "Automatic uses your Appearance font." })
end

local function presetRow()
    local values, order = { custom = "Custom" }, {}
    for _, id in ipairs(CT.PRESET_ORDER) do
        values[id] = CT.PRESETS[id].label
        order[#order + 1] = id
    end
    return row({ type = "dropdown", label = "Combat text preset", values = values, order = order,
        get = function() return CT.Preset() end,
        set = function(v) CT.SetPreset(v) end,
        default = function() return "daylight" end,
        desc = "A whole look at once. Daylight leans the numbers along the UI's slant and lights up crits. Calm is small and slow. "
            .. "Punchy is big and flung out both ways. Classic curves like the game's own. Changing a row below makes it Custom." })
end

-- All of a stream's settings in one card. Search can show a row without its
-- card, so every label names its stream.
local function streamCard(id, tab)
    local path = "sct.streams." .. id .. "."
    local name = CT.STREAMS[id].label
    local function dim() return off() or CT.Get("streams." .. id .. ".on") == false end
    local function r(item)
        item.disabled = dim
        return item
    end
    return { label = name, tab = tab, items = {
        { type = "toggle", key = path .. "on", label = "Show the " .. CT.STREAMS[id].word .. " stream", disabled = off,
          desc = "When off, nothing shows here, even for the messages that go to it." },
        r({ type = "dropdown", key = path .. "motion", label = name .. " motion", values = CT.MOTIONS, order = CT.MOTION_ORDER,
            desc = "Slant leans along the UI's angle. Rise and Fall go straight. Arc curves away from you. Fountain sprays both ways. "
                .. "Stack stays put, and new lines push the older ones up." }),
        r({ type = "slider", key = path .. "size", label = name .. " text size", min = 10, max = 50, step = 1, unit = "px",
            desc = "How tall a line of text is." }),
        r({ type = "slider", key = path .. "critSize", label = name .. " crit size", min = 12, max = 80, step = 1, unit = "px",
            desc = "How tall a crit is once it settles." }),
        r({ type = "dropdown", key = path .. "align", label = name .. " alignment", values = CT.ALIGNS, order = CT.ALIGN_ORDER,
            desc = "Which side of the spot the lines line up on." }),
        r({ type = "slider", key = path .. "life", label = name .. " time on screen", min = 0.6, max = 5, step = 0.1,
            desc = "Seconds a line stays before it fades." }),
        r({ type = "slider", key = path .. "dist", label = name .. " travel distance", min = 0, max = 400, step = 5, unit = "px",
            desc = "How far a line travels. Stack ignores this." }),
        r({ type = "slider", key = path .. "lines", label = name .. " most lines at once", min = 3, max = 20, step = 1,
            desc = "Past this the oldest line leaves early, so a big pull never floods the screen." }),
    } }
end

local BESIDE_W = 190    -- room for the stream menu and color swatch on each message row
local MENU_W = 134

-- Stream menu and color for a message, placed on its switch's row.
local function beside(id)
    return function(row)
        local W = DUI.Widgets
        local f = CreateFrame("Frame", nil, row)
        f:SetSize(BESIDE_W, W.ROW_HEIGHT)
        local path = "kinds." .. id .. "."

        local color = W.Swatch(f, row, function() return CT.Get(path .. "color") end, function(c)
            CT.Set(path .. "color", c)
            if CT.KINDS[id].power then CT.Set(path .. "power", false) end   -- a picked color overrides the power color
        end)
        color:SetPoint("RIGHT", f, "RIGHT", 0, 0)

        local menu
        if not CT.KINDS[id].fixed then
            menu = W.MenuButton(f, "", 24)
            menu:SetWidth(MENU_W)
            menu:SetPoint("RIGHT", color, "LEFT", -8, 0)
            local names, order = {}, {}
            for _, s in ipairs(CT.STREAM_ORDER) do
                names[s] = DUI.L[CT.STREAMS[s].label]
                order[#order + 1] = s
            end
            menu:SetScript("OnClick", function(self)
                if row.disabled then return end
                W.OpenMenu(self, order, names, CT.Get(path .. "stream"), function(s) CT.Set(path .. "stream", s) end, MENU_W)
            end)
            function f.Paint() menu.SetLabel(names[CT.Get(path .. "stream")] or "", MENU_W) end
        end

        function f.Refresh()
            color.Refresh()
            if f.Paint then f.Paint() end
            local on = not row.disabled and CT.Get(path .. "on") ~= false
            DUI.Motion.AlphaTo(f, on and 1 or 0.35, DUI.Motion.FAST)
        end
        f.Refresh()
        return f
    end
end

local function messageCard(label, tab, ids, more)
    local items = {}
    for _, id in ipairs(ids) do
        local k = CT.KINDS[id]
        items[#items + 1] = { type = "toggle", key = "sct.kinds." .. id .. ".on", label = k.label, desc = k.desc,
            disabled = off, beside = beside(id) }
    end
    for _, item in ipairs(more or {}) do items[#items + 1] = item end
    return { label = label, tab = tab, wide = true, items = items }
end

-- Page reset. The rows only own the switches, so the rest of each message is reset here.
local function resetKinds()
    local defaults = DUI.DB.GENERAL_DEFAULTS.sct.kinds
    for id, d in pairs(defaults) do
        CT.Set("kinds." .. id .. ".stream", d.stream)
        CT.Set("kinds." .. id .. ".color", { d.color[1], d.color[2], d.color[3] })
        if d.power ~= nil then CT.Set("kinds." .. id .. ".power", d.power) end
    end
end

function CT.Page(Options)
    return {
        id = "combattext", section = "core", label = "Combat text", scope = "general", defaults = DUI.DB.GENERAL_DEFAULTS,
        desc = "The text scrolling around your character: hits you take, heals, procs and more.",
        sample = function(parent) return CT.Sample(parent) end,
        resetAll = resetKinds,
        groups = {
            { label = "Look", tab = "Look", items = {
                { type = "toggle", key = "sct.enabled", label = "Show combat text",
                  desc = "The text scrolling around your character. When off, none shows, the game's own included." },
                presetRow(),
                fontRow(Options),
                row({ type = "dropdown", key = "sct.outline", label = "Combat text outline", values = CT.OUTLINES, order = CT.OUTLINE_ORDER,
                      desc = "An outline keeps the text readable over bright ground and spell effects." }),
                row({ type = "toggle", key = "sct.shadow", label = "Combat text shadow", desc = "A soft shadow under each line." }),
                row({ type = "toggle", key = "sct.tick", label = "Slanted mark", desc = "A small slanted mark beside each line, in its color." }),
            } },
            { label = "Crits", desc = "How a big hit or heal, or a spell lighting up, lands.", items = {
                row({ type = "dropdown", key = "sct.crit", label = "Crit style", values = CT.CRITS, order = CT.CRIT_ORDER,
                     desc = "Flare lands big in a burst of soft light. Slam lands bigger and faster. Pop is a small bump. Plain is just bigger text." }),
                row({ type = "slider", key = "sct.glow", label = "Crit light", min = 0, max = 1, step = 0.05, unit = "%",
                     desc = "How bright the light behind a crit is. At 0 there is none." }),
                row({ type = "toggle", key = "sct.underline", label = "Crit underline", desc = "A line of light under each crit." }),
                row({ type = "toggle", key = "sct.critMark", label = "Crit exclamation mark", desc = "A ! after each crit." }),
            } },
            { label = "Numbers", items = {
                row({ type = "dropdown", key = "sct.numbers", label = "Number format", values = CT.NUMBERS, order = CT.NUMBER_ORDER,
                     desc = "Full numbers, or short ones for high-level play." }),
                row({ type = "toggle", key = "sct.signs", label = "Plus and minus signs", desc = "A - before damage and a + before heals." }),
                row({ type = "toggle", key = "sct.schoolColors", label = "Color spell hits by school",
                     desc = "Fire orange, frost blue, shadow purple. When off, they use the Spell hits color." }),
                row({ type = "toggle", key = "sct.healerNames", label = "Names of who heals you",
                     desc = "The healer's name beside each heal. In a fight the game can hide who it was, so your own heals may show your name too." }),
            } },
            { label = "Move the text", tab = "Streams", wide = true, items = {
                { type = "button", label = "Move the text streams", desc = "Shows a handle on every spot. Drag to move it.",
                  text = function() return DUI.Movers.unlocked and DUI.L["Lock"] or DUI.L["Unlock"] end,
                  func = function()
                      if DUI.Movers.unlocked then DUI.Movers.Lock() else DUI.Movers.Unlock() end
                  end },
            } },
            streamCard("hits"), streamCard("heals"), streamCard("notes"),
            messageCard("Hits on you", "Messages", { "hit", "spell", "avoid", "reduce" }),
            messageCard("Healing and power", nil, { "heal", "hot", "shield", "power", "powerTick" }),
            messageCard("Notices", nil, { "proc", "low", "buff", "debuff", "combat", "other", "rep", "honor" }, {
                row({ type = "slider", key = "sct.warnAt", label = "Low health warning at", min = 0.1, max = 0.6, step = 0.05, unit = "%",
                      desc = "How low your health or mana gets before the warning shows." }),
            }),
        },
    }
end
