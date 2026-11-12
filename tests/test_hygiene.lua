-- Project hygiene checks. No temporary or debug code in shipped files (probes
-- belong in DaylightUI_Dev/, which never ships). Reviewed exceptions go in the
-- ALLOW lists, with a reason.

-- Shipped means the core .toc plus each module .pkgmeta moves into a release.
local function shippedTocs()
    local tocs = { "DaylightUI.toc" }
    for line in io.lines(".pkgmeta") do
        local folder = line:gsub("\r", ""):match("^%s*DaylightUI/(DaylightUI_[%w_]+):")
        if folder then tocs[#tocs + 1] = folder .. "/" .. folder .. ".toc" end
    end
    return tocs
end

local function shippedFiles()
    local files = {}
    for _, toc in ipairs(shippedTocs()) do
        local dir = toc:match("^(.*/)") or ""
        for line in io.lines(toc) do
            line = line:gsub("\r", ""):gsub("\\", "/"):gsub("%s+$", "")
            if not line:find("^#") and line:find("%.lua$") then files[#files + 1] = dir .. line end
        end
    end
    return files
end

local function read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a"); f:close()
    return (text:gsub("\r", ""))
end

-- ---------------------------------------------------------------------
-- No temporary code in shipped files
-- ---------------------------------------------------------------------

local MARKERS = {
    "TEMPORARY",
    "%-%-%s*TEMP%f[^%w]",
    "DEBUG %(temporary",
    "not to be committed",
}

T.test("hygiene: no temporary or debug code in a shipped file (use DaylightUI_Dev/)", function()
    local bad = {}
    for _, path in ipairs(shippedFiles()) do
        local n = 0
        for line in (read(path) or ""):gmatch("([^\n]*)\n?") do
            n = n + 1
            for _, m in ipairs(MARKERS) do
                if line:find(m) then bad[#bad + 1] = path .. ":" .. n .. ": " .. line:gsub("^%s+", ""):sub(1, 90); break end
            end
        end
    end
    if #bad > 0 then error("\n  " .. table.concat(bad, "\n  "), 0) end
end)

-- Comments explain the code to the next person reading it. Notes about when
-- or why something was asked for belong in the commit message, not the code.
local NOTE_MARKERS = {
    { "the user", "say \"the player\", or just give the reason" },
    { "%d%d%d%d%-%d%d%-%d%d", "a date: git already knows when" },
    { "docs/", "a path into notes that aren't in the repo" },
    { "cheat sheet", "a pointer to notes that aren't in the repo" },
    { "maintenance §", "a pointer to notes that aren't in the repo" },
    { "probe run", "say \"seen in game\"" },
}

local function noteIn(line)
    local at = line:find("%-%-")
    if not at then return nil end
    local comment = line:sub(at):lower()
    for _, m in ipairs(NOTE_MARKERS) do
        if comment:find(m[1]) then return m[2] end
    end
end

local function testFiles()
    local files = {}
    local p = io.popen('git ls-files "tests/*.lua"')
    for line in p:lines() do
        if not line:find("^tests/blizzard/") and line ~= "tests/test_hygiene.lua" then files[#files + 1] = line end
    end
    p:close()
    return files
end

T.test("hygiene: comments in the addon and its tests carry no notes to self", function()
    local bad = {}
    local files = shippedFiles()
    for _, path in ipairs(testFiles()) do files[#files + 1] = path end
    for _, path in ipairs(files) do
        local n = 0
        for line in (read(path) or ""):gmatch("([^\n]*)\n?") do
            n = n + 1
            local why = noteIn(line)
            if why then bad[#bad + 1] = path .. ":" .. n .. ": " .. why .. ": " .. line:gsub("^%s+", ""):sub(1, 80) end
        end
    end
    if #bad > 0 then error("\n  " .. table.concat(bad, "\n  "), 0) end
end)

T.test("hygiene: the notes check finds a note", function()
    T.truthy(noteIn("local x = 1 -- the user asked for this"))
    T.truthy(noteIn("-- seen in game 2026-11-09"))
    T.falsy(noteIn("-- The player can change the accent any time."))
    T.falsy(noteIn('local s = "the user"'), "strings are code, not comments")
end)

-- Every control comes from Options/Widgets.lua so they all look the same.
-- The close X's art is easy to spot, and only the builders may draw it.
local CLOSE_ART_OK = { ["Options/Widgets.lua"] = true, ["DaylightUI_Skins/Kit.lua"] = true }

T.test("hygiene: no hand-built close X (use W.Close)", function()
    local bad = {}
    for _, path in ipairs(shippedFiles()) do
        if not CLOSE_ART_OK[path] and (read(path) or ""):find("ui-close.png", 1, true) then bad[#bad + 1] = path end
    end
    T.eq(table.concat(bad, ", "), "", "draw the X with W.Close")
end)

-- Text boxes too: W.Input (one line) or W.TextArea (many).
local EDITBOX_OK = { ["Options/Widgets.lua"] = true }

T.test("hygiene: no hand-built text box (use W.Input)", function()
    local bad = {}
    for _, path in ipairs(shippedFiles()) do
        if not EDITBOX_OK[path] and (read(path) or ""):find('CreateFrame("EditBox"', 1, true) then bad[#bad + 1] = path end
    end
    T.eq(table.concat(bad, ", "), "", "make the box with W.Input")
end)

-- Buttons too: a game button template only when W.DressButton dresses it.
T.test("hygiene: no undressed game button (use W.Button / W.DressButton)", function()
    local bad = {}
    for _, path in ipairs(shippedFiles()) do
        local src = read(path) or ""
        if src:find("UIPanelButtonTemplate", 1, true) and not src:find("DressButton", 1, true) then bad[#bad + 1] = path end
    end
    T.eq(table.concat(bad, ", "), "", "dress it with W.DressButton")
end)

-- Scroll bars too: every scrolling list wears W.Scroll. The quest tracker
-- keeps its own stepped wheel in the same look (Quests/Scroll.lua).
local SCROLL_OK = { ["DaylightUI_Quests/Tracker.lua"] = "Quests/Scroll.lua draws its bar in W.SCROLL's look" }

T.test("hygiene: every scroll frame has our scroll bar (W.Scroll)", function()
    local bad = {}
    for _, path in ipairs(shippedFiles()) do
        local src = read(path) or ""
        if not SCROLL_OK[path] and src:find('CreateFrame("ScrollFrame"', 1, true) and not src:find("%.Scroll%(") then bad[#bad + 1] = path end
    end
    T.eq(table.concat(bad, ", "), "", "give the scroll frame W.Scroll(sf)")
end)

-- Fonts: picked in one place. A font file named anywhere else skips the
-- player's font setting (use Style.Text / Style.DressText / Style.FONT).
local FONT_FILE_OK = { ["Style.lua"] = true, ["Options/Theme.lua"] = true, ["GameFonts.lua"] = true }

T.test("hygiene: no font file outside Style (use Style.Text / Style.FONT)", function()
    local bad = {}
    for _, path in ipairs(shippedFiles()) do
        local src = (read(path) or ""):lower()
        if not FONT_FILE_OK[path] and (src:find("%.ttf[\"']") or src:find("%.otf[\"']")) then bad[#bad + 1] = path end
    end
    T.eq(table.concat(bad, ", "), "", "fonts come from Style.FONTS")
end)

-- Each of the game's control templates has a replacement in Widgets.lua.
-- A button template is allowed only when W.DressButton dresses it.
local GAME_CONTROLS = { "TabButtonTemplate", "TabSystemButtonTemplate", "UICheckButtonTemplate",
    "OptionsSliderTemplate", "UIPanelScrollFrameTemplate", "ScrollFrameTemplate", "InputBoxTemplate",
    "UIDropDownMenuTemplate", "UIPanelCloseButton", "WowStyle1DropdownTemplate" }

T.test("hygiene: no game control templates (use our W.* controls)", function()
    local bad = {}
    for _, path in ipairs(shippedFiles()) do
        local src = read(path) or ""
        for _, t in ipairs(GAME_CONTROLS) do
            if src:find('"' .. t .. '"', 1, true) or src:find(', ' .. t, 1, true) then bad[#bad + 1] = path .. " (" .. t .. ")" end
        end
    end
    T.eq(table.concat(bad, ", "), "", "build it from Options/Widgets.lua")
end)

-- Menus too: W.OpenMenu (atCursor for a right-click menu), never the game's.
T.test("hygiene: no game context menu (use W.OpenMenu)", function()
    local bad = {}
    for _, path in ipairs(shippedFiles()) do
        if (read(path) or ""):find("MenuUtil.CreateContextMenu", 1, true) then bad[#bad + 1] = path end
    end
    T.eq(table.concat(bad, ", "), "", "open W.OpenMenu with { atCursor = true }")
end)

T.test("hygiene: the shipped list is found (the check above isn't empty)", function()
    local files = shippedFiles()
    T.truthy(#files > 100, "found " .. #files .. " shipped files")
    for _, toc in ipairs(shippedTocs()) do T.falsy(toc:find("DaylightUI_Dev", 1, true), "the dev tools never ship") end
end)

-- ---------------------------------------------------------------------
-- No accidental globals
-- ---------------------------------------------------------------------

-- A forgotten `local` writes into the global table. It can clash with another
-- addon and taints any game code that later reads that name. LuaJIT's
-- bytecode listing (`luajit -bl`) shows every global write as GSET, so this
-- check is exact.
local GLOBALS_OK = {
    GetMinimapShape = "minimap-button addons (LibDBIcon) ask our minimap for its shape (round while it turns)",
    DAMAGE_TEXT_FONT = "the damage numbers' font: the client reads this global at login (GameFonts.lua)",
}

local function ourName(name)
    return name:find("^DaylightUI") or name:find("^SLASH_DAYLIGHTUI") or name:find("^BINDING_[%u_]*DAYLIGHTUI")
end

T.test("hygiene: no file writes an accidental global (a forgotten local)", function()
    local files = shippedFiles()
    for line in T.dev and io.lines("DaylightUI_Dev/DaylightUI_Dev.toc") or function() end do
        line = line:gsub("\r", ""):gsub("%s+$", "")
        if line:find("%.lua$") and not line:find("^#") then files[#files + 1] = "DaylightUI_Dev/" .. line end
    end
    local bc = require("jit.bc")
    local bad = {}
    for _, path in ipairs(files) do
        local fn = assert(loadfile(path))
        local out = {}
        bc.dump(fn, { write = function(_, s) out[#out + 1] = s end, flush = function() end }, true)
        for name in table.concat(out):gmatch('GSET[^\n]-; "([^"]+)"') do
            if not ourName(name) and not GLOBALS_OK[name] then bad[#bad + 1] = path .. ": " .. name end
        end
    end
    if #bad > 0 then error("\n  globals written (add `local`, or GLOBALS_OK with a reason):\n  " .. table.concat(bad, "\n  "), 0) end
end)

-- ---------------------------------------------------------------------
-- The tests load what the game loads, in the game's order
-- ---------------------------------------------------------------------

-- A file in a .toc but missing from tests/stub.lua is never tested, and a
-- different order can hide a load-order bug. Load every module the way the
-- tests do, record each file, and compare with the .tocs. Libs/ and XML
-- aren't loaded by the fake game.
T.test("hygiene: the tests load every shipped file, in the .toc's order", function()
    local stub = require("stub")
    local loaded, realLoadfile = {}, loadfile
    _G.loadfile = function(path, ...)
        local chunk, err = realLoadfile(path, ...)
        -- The game's own code in tests/blizzard/ runs in its own environment.
        if not chunk or type(path) ~= "string" or path:find("^tests/") then return chunk, err end
        return function(...)
            loaded[#loaded + 1] = path
            return chunk(...)
        end
    end
    local ABW, QW = require("abworld"), require("questworld")
    local quests = QW.world({ quests = {} })
    stub.ForgetCompiled()
    local ok, err = pcall(stub.Load, { module = true, actionbars = true, buffs = true, skins = true, bags = true,
        nameplates = true, tooltip = true, qol = true, chat = true, infopanel = true, quests = true,
        before = function() ABW.world(); quests() end })
    _G.loadfile = realLoadfile
    stub.ForgetCompiled()
    assert(ok, err)
    local byToc = {}
    for _, path in ipairs(loaded) do
        local folder = path:match("^(DaylightUI_[%w_]+)/")
        local toc = folder and (folder .. "/" .. folder .. ".toc") or "DaylightUI.toc"
        byToc[toc] = byToc[toc] or {}
        table.insert(byToc[toc], path)
    end
    local bad = {}
    for _, toc in ipairs(shippedTocs()) do
        local want = {}
        local dir = toc:match("^(.*/)") or ""
        for line in io.lines(toc) do
            line = line:gsub("\r", ""):gsub("\\", "/"):gsub("%s+$", "")
            if not line:find("^#") and line:find("%.lua$") and not line:find("^Libs/") then want[#want + 1] = dir .. line end
        end
        local got = byToc[toc] or {}
        local gotSet, wantSet = {}, {}
        for _, p in ipairs(got) do gotSet[p] = true end
        for _, p in ipairs(want) do wantSet[p] = true end
        for _, p in ipairs(want) do
            if not gotSet[p] then bad[#bad + 1] = toc .. ": the tests never load " .. p .. " (add it to tests/stub.lua)" end
        end
        for _, p in ipairs(got) do
            if not wantSet[p] then bad[#bad + 1] = toc .. ": the tests load " .. p .. ", the .toc doesn't list it" end
        end
        -- Order: the files both lists have, in the same order.
        local a, b = {}, {}
        for _, p in ipairs(want) do if gotSet[p] then a[#a + 1] = p end end
        for _, p in ipairs(got) do if wantSet[p] then b[#b + 1] = p end end
        for i = 1, #a do
            if a[i] ~= b[i] then
                bad[#bad + 1] = toc .. ": order differs at " .. tostring(a[i]) .. " (the tests load " .. tostring(b[i]) .. " there)"
                break
            end
        end
    end
    if #bad > 0 then error("\n  " .. table.concat(bad, "\n  "), 0) end
end)

-- ---------------------------------------------------------------------
-- Shown text goes through DUI.L. No English literal straight into a text
-- setter, print, tooltip line, button, popup button or command help.
-- Options label/desc literals are fine because Options.Text translates them.
-- Modules listed in tests/locale_keys.lua's NOT_YET are skipped.
-- ---------------------------------------------------------------------

local LOCALE_SINKS = {
    ":SetText%(%s*%(?(\"[^\"]*\")",            -- also ("..."):format(...)
    ":SetFormattedText%(%s*(\"[^\"]*\")",
    ":AddLine%(%s*%(?(\"[^\"]*\")",
    ":AddDoubleLine%(%s*%(?(\"[^\"]*\")",
    "Tips%.%a+%(%s*%(?(\"[^\"]*\")",
    "DUI%.Print%(%s*%(?(\"[^\"]*\")",
    "DaylightUI%.Print%(%s*%(?(\"[^\"]*\")",
    "W%.Button%([^,]+,%s*(\"[^\"]*\")",
    "Widgets%.Button%([^,]+,%s*(\"[^\"]*\")",
    "W%.Confirm%([^,]+,%s*(\"[^\"]*\")",
    "W%.Tooltip%([^,]+,%s*(\"[^\"]*\")",
    "button[12]%s*=%s*[%w_]*%s*o?r?%s*(\"[^\"]*\")",
    "%f[%w_]say%((\"[^\"]*\")",
    "warn%((\"[^\"]*\")",
    "^%s*(\"/dui [^\"]*\")",
    "RegisterCommand%(.*[^%[](\"/dui [^\"]*\")",
}

-- Literals that are right as they are, with why.
local LOCALE_OK = {
    ['"Daylight 123"'] = "the font sample: the font, not words",
    ['"DaylightUI"'] = "the name",
    ['"debug: no shell on "'] = "/dui debug: a border dump for bug reports, read by us",
    -- /dui platefps and /dui platedebug: numbers and boxes for bug reports, read by us.
    ['"Profiler on: "'] = "/dui platefps dump", ['"Game\'s plate (takes the clicks) "'] = "/dui platedebug dump",
    ['"Stacking box "'] = "/dui platedebug dump", ['"Can set the click area: "'] = "/dui platedebug dump",
    ['"Plate size: "'] = "/dui platedebug dump",
    ['"Bram 60"'] = "a sample guild member's name and level (data texts in test mode)",
}

T.test("hygiene: our own text goes through L (core, Character, and modules done)", function()
    local K = require("locale_keys")
    local bad = {}
    for _, path in ipairs(shippedFiles()) do
        local module = path:match("^DaylightUI_(%w+)/")
        if not (module and K.NOT_YET[module]) and path ~= "PatchNotes.lua" then
            local n = 0
            for line in (read(path) or ""):gmatch("([^\n]*)\n?") do
                n = n + 1
                local code = line:gsub("%-%-.*$", "")
                for _, pat in ipairs(LOCALE_SINKS) do
                    local lit = code:match(pat)
                    local letters = lit and lit:gsub("|c%x*", ""):gsub("|r", "")
                    if lit and letters:find("%a%a") and not LOCALE_OK[lit] then
                        bad[#bad + 1] = path .. ":" .. n .. ": " .. line:gsub("^%s+", "")
                        break
                    end
                end
            end
        end
    end
    T.eq(table.concat(bad, "\n"), "", "wrap the text in L[...] (or add a reason to LOCALE_OK)")
end)

-- ---------------------------------------------------------------------
-- US spelling in everything a player reads
-- ---------------------------------------------------------------------

local BRITISH = {
    "colour", "colours", "coloured", "colouring", "grey", "greyed", "greys", "centre", "centred",
    "favourite", "favourites", "behaviour", "honour", "armour", "recognise", "recognised", "unrecognised",
    "organise", "organised", "customise", "customised", "categorised", "prioritise", "licence",
    "cancelled", "travelling", "levelling", "whilst",
    "centres", "recolour", "recolours", "recoloured", "behaviours", "maths", "licences", "capitalised",
}
-- Not "dialogue": US English keeps it for talk (the NPC window's "Dialogue keys"), "dialog" is a pop-up box.
-- Strings that are saved keys, not words a player sees (renaming one orphans saved settings).
local SPELLING_KEYS = { grey = true }

T.test("hygiene: no British spelling in a shipped string (US: color, gray, recognized)", function()
    local bad = {}
    for _, path in ipairs(shippedFiles()) do
        local n = 0
        -- A language file's words are that language's own ("centre" is French).
        local text = not path:find("^Locales/") and read(path) or ""
        for line in text:gmatch("([^\n]*)\n?") do
            n = n + 1
            if not line:find("^%s*%-%-") then
                for s in line:gmatch('"([^"]*)"') do
                    if not SPELLING_KEYS[s] then
                        local low = s:lower()
                        for _, w in ipairs(BRITISH) do
                            if low:find("%f[%a]" .. w .. "%f[%A]") then
                                bad[#bad + 1] = path .. ":" .. n .. ": " .. w .. " in \"" .. s:sub(1, 70) .. "\""
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    T.eq(table.concat(bad, "\n"), "", "use US spelling in player text")
end)

-- The same words in comments and docs (text in `backticks` is code: skipped).
local function britishIn(text)
    local low = text:gsub("`[^`]*`", ""):lower()
    for _, w in ipairs(BRITISH) do
        if low:find("%f[%a]" .. w .. "%f[%A]") then return w end
    end
end

local function docFiles()
    local files = {}
    -- Ignored files too, so local notes are checked as well.
    local p = io.popen('git ls-files --cached --others -- "*.md"')
    for line in p:lines() do
        if not line:find("^Libs/") and not line:find("/Libs/") and not line:find("node_modules/")
            and not line:find("^tests/blizzard/") and not line:find("^%.wrangler/") and not line:find("^%.superpowers/") then files[#files + 1] = line end
    end
    p:close()
    return files
end

T.test("hygiene: no British spelling in shipped comments or the docs", function()
    local bad = {}
    for _, path in ipairs(shippedFiles()) do
        local n = 0
        for line in (read(path) or ""):gmatch("([^\n]*)\n?") do
            n = n + 1
            local at = line:find("%-%-")
            local w = at and britishIn(line:sub(at))
            if w then bad[#bad + 1] = path .. ":" .. n .. ": " .. w end
        end
    end
    for _, path in ipairs(docFiles()) do
        local n, fence = 0, false
        for line in (read(path) or ""):gmatch("([^\n]*)\n?") do
            n = n + 1
            if line:find("^%s*```") then fence = not fence
            elseif not fence then
                local w = britishIn(line)
                if w then bad[#bad + 1] = path .. ":" .. n .. ": " .. w end
            end
        end
    end
    T.truthy(#docFiles() > 10, "the docs are found")
    T.eq(table.concat(bad, "\n"), "", "use US spelling")
end)

-- ---------------------------------------------------------------------
-- No neutral gray text. Flags a SetTextColor, |cff escape or
-- NAME = { r, g, b } where r, g and b are within 0.04 of each other and
-- between 0.3 and 0.96. GRAY_OK lists neutral colors that aren't text.
-- ---------------------------------------------------------------------
local GRAY_OK = {
    ["Style.lua|NEUTRAL"] = "bar fill for no class/reaction; text falls back to INK.VALUE",
    ["Style.lua|locked"] = "uninterruptible cast bar fill",
    ["Character/Slots.lua|EMPTY_TINT"] = "an empty slot's icon tint, not text",
    ["DaylightUI_ActionBars/CdmEffects.lua|no"] = "an icon that can't be cast: the game's own tint for it, not text",
    ["DaylightUI_UnitFrames/Defaults.lua|dead"] = "health bar fill",
    ["DaylightUI_UnitFrames/Defaults.lua|offline"] = "health bar fill",
    ["DaylightUI_UnitFrames/Defaults.lua|tapped"] = "health bar fill",
    ["DaylightUI_UnitFrames/Defaults.lua|locked"] = "cast bar fill",
    ["DaylightUI_Quests/Defaults.lua|headerLine"] = "a line texture",
    ["Character/Defaults.lua|line"] = "header underline texture",
    ["Dots.lua|AGONY"] = "tick size factors, not a color",
    ["Gradients.lua|lo"] = "the Tapped bar gradient's dark end (a bar fill)",
    ["InstallerCards.lua|RING_COLOR"] = "the sample portrait ring texture",
    ["DaylightUI_InfoPanel/Panel.lua|ARROW_COLOR"] = "the fold tab's arrow texture",
    ["DaylightUI_InfoPanel/Breakdown.lua|BAR"] = "the spell bars' fill (a bar, not text)",
    ["DaylightUI_Bags/Items.lua|EMPTY"] = "an empty slot's border",
    ["DaylightUI_Bags/Layout.lua|LINE"] = "a section's divider line (a texture)",
    ["DaylightUI_Buffs/Categories.lua|fallback"] = "Other's edge color; its name text uses Categories.TextColor",
    ["DaylightUI_Bags/Items.lua|COMMON"] = "a common item's border",
    ["DaylightUI_Bags/Items.lua|POOR"] = "a poor item's border",
    ["DaylightUI_Quests/Look.lua|RING"] = "the ready ring texture",
    ["DaylightUI_Quests/Look.lua|CHEVRON_COLOR"] = "the fold chevron texture",
    ["DaylightUI_UnitFrames/UnitFrames.lua|RING_COLOR"] = "the portrait ring texture",
    ["DaylightUI_UnitFrames/UnitFrames.lua|PVP_NEUTRAL"] = "the PvP badge icon's tint",
    ["DaylightUI_ActionBars/Skin.lua|UNUSABLE"] = "an unusable action's icon tint",
    ["DaylightUI_Skins/Packs/Addons/OPie.lua|UNUSABLE"] = "an unusable ring button's icon tint (the action bars')",
    ["DaylightUI_Skins/Kit.lua|CONTROL_BORDER"] = "a control's outline",
    ["DaylightUI_Skins/Kit.lua|DISABLED_BORDER"] = "a disabled control's outline",
    ["DaylightUI_Skins/Kit.lua|ROW_HOVER"] = "a row's outline under the mouse",
    ["DaylightUI_Skins/Kit.lua|EMPTY_ITEM_BORDER"] = "an empty item slot's outline",
}
local function neutral(r, g, b)
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
    if not (r and g and b) then return false end
    local hi, lo = math.max(r, g, b), math.min(r, g, b)
    return hi - lo <= 0.04 and hi >= 0.3 and hi <= 0.96
end

local function grayHits(path, text)
    local hits, n = {}, 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        local code = line:gsub("%-%-.*$", "")
        local r, g, b = code:match("SetTextColor%(%s*([%d%.]+)%s*,%s*([%d%.]+)%s*,%s*([%d%.]+)")
        if r and neutral(r, g, b) then hits[#hits + 1] = path .. ":" .. n .. " SetTextColor" end
        for x, y, z in code:gmatch("|c[fF][fF](%x%x)(%x%x)(%x%x)") do
            if neutral(tonumber(x, 16) / 255, tonumber(y, 16) / 255, tonumber(z, 16) / 255) then
                hits[#hits + 1] = path .. ":" .. n .. " |cff" .. x .. y .. z
            end
        end
        local name, r2, g2, b2 = code:match("([%w_]+)%s*=%s*{%s*([%d%.]+)%s*,%s*([%d%.]+)%s*,%s*([%d%.]+)%s*[,}]")
        if name and neutral(r2, g2, b2) and not GRAY_OK[path .. "|" .. name] then
            hits[#hits + 1] = path .. ":" .. n .. " " .. name
        end
    end
    return hits
end

T.test("hygiene: no neutral gray text (warm base, a touch of color)", function()
    local bad = {}
    for _, path in ipairs(shippedFiles()) do
        for _, h in ipairs(grayHits(path, read(path) or "")) do bad[#bad + 1] = h end
    end
    T.eq(#bad, 0, "neutral gray text (use Style.INK):\n  " .. table.concat(bad, "\n  "))
end)

T.test("hygiene: the gray check finds a gray", function()
    T.eq(#grayHits("x.lua", 'fs:SetTextColor(0.62, 0.62, 0.65)\nlocal DIM = { 0.6, 0.6, 0.6 }\ns = "|cff8a8a90x"'), 3)
    T.eq(#grayHits("x.lua", "fs:SetTextColor(1, 1, 1)\nlocal W = { 0.76, 0.71, 0.62 }"), 0)
end)

-- All text colors come from Style.INK or the accent, never typed-in numbers.
-- A literal text color (SetTextColor(0.9, ...) or a |cff code) fails unless
-- listed here with its reason. Keyed "path|the line's code, trimmed".
local TEXT_COLOR_OK = {
    ["DaylightUI_Skins/Packs/Addons/ForeverDungeonJournal.lua|FDJ.DONE_RUN = \"|cff6e5c40\""] = "the color it prints, looked for in its text and replaced, never painted",
    ["Style.lua|if on then fs:SetTextColor(1, 1, 1) else fs:SetTextColor(Style.Accent()) end"] = "white under per-letter accent colors",
    ["Character/Colors.lua|fs:SetTextColor(1, 1, 1)"] = "white under per-letter gradient colors",
    ["DaylightUI_Quests/Look.lua|fs:SetTextColor(1, 1, 1)"] = "white under per-letter gradient colors",
    ["DaylightUI_Nameplates/Plate.lua|fs:SetTextColor(1, 1, 1)"] = "white under per-letter colors (combat frame)",
    ["DaylightUI_Nameplates/Plate.lua|p.name:SetTextColor(1, 1, 1)"] = "white under per-letter colors (combat frame)",
    ["DaylightUI_Nameplates/Sample.lua|p.name:SetTextColor(1, 1, 1)"] = "white under per-letter colors (the plate preview, as Plate.lua)",
    ["DamageText.lua|if crit then fs:SetTextColor(1, 0.86, 0.35) else DUI.Style.InkText(fs, \"VALUE\") end"] = "the damage numbers sample: the game's crit color",
    ["DaylightUI_QoL/LevelUp.lua|f.old:SetTextColor(1, 0.95, 0.85)"] = "display art: the big level number",
    ["DaylightUI_QoL/LevelUp.lua|f.new:SetTextColor(1, 0.95, 0.85)"] = "display art: the big level number",
    ["GameMenu.lua|local LABEL = \"|cff1e90ffD|r|cff4083f5a|r|cff6276e8y|r|cff8569d8l|r|cffa65dc3i|r\""] = "the brand's letters",
    ["GameMenu.lua|.. \"|cffc556a3g|r|cffdc5881h|r|cffed685et|r|cfff8813cU|r|cffff9a1fI|r\""] = "the brand's letters",
}
local function textColorHits(path, text)
    local hits = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local code = line:gsub("%s+%-%-%s.*$", ""):gsub("^%s*%-%-.*$", ""):match("^%s*(.-)%s*$")
        if code ~= "" and (code:find("SetTextColor%(%s*[%d%.]") or code:find("|c[fF][fF]%x%x%x%x%x%x"))
            and not TEXT_COLOR_OK[path .. "|" .. code] then
            hits[#hits + 1] = path .. "|" .. code
        end
    end
    return hits
end

T.test("hygiene: text colors come from Style.INK, never typed-in numbers", function()
    local bad, used = {}, {}
    for _, path in ipairs(shippedFiles()) do
        local text = read(path) or ""
        for _, h in ipairs(textColorHits(path, text)) do bad[#bad + 1] = h end
        for key in pairs(TEXT_COLOR_OK) do
            local p, code = key:match("^(.-)|(.*)$")
            if p == path and text:find(code, 1, true) then used[key] = true end
        end
    end
    T.eq(#bad, 0, "a typed-in text color (use Style.INK / Style.InkText / DUI.Tips; a real exception goes in TEXT_COLOR_OK with its reason):\n  "
        .. table.concat(bad, "\n  "))
    for key in pairs(TEXT_COLOR_OK) do T.truthy(used[key], "TEXT_COLOR_OK entry no longer in the code: " .. key) end
end)

T.test("hygiene: the text color check finds a typed-in color", function()
    local hits = textColorHits("x.lua", 'fs:SetTextColor(0.9, 0.88, 0.84)\ns = "|cffc2b59e-- x"\nStyle.InkText(fs, "TEXT")\n-- fs:SetTextColor(1, 1, 1)')
    T.eq(#hits, 2)
end)

-- The fixed Daylight colors (W.TextDaylight, W.TintDaylight, GRADIENT_SHAPE,
-- GRADIENT_MID) belong to the options window and to "daylight" setting
-- choices, never to the player's accent. A shared menu once painted its rows
-- purple under a gradient accent. Accent-colored things read Style.Accent()
-- at paint time. Files allowed to use the fixed colors:
local DAYLIGHT_OK = {
    ["Style.lua"] = "where they're made, and the Daylight sweep itself",
    ["Options/Widgets.lua"] = "the options window's controls (settled: it keeps the Daylight gradient)",
    ["Options/Nav.lua"] = "the options window",
    ["Options/Panel.lua"] = "the options window (Tip Daylight's heart, in the gradient with Top donators)",
    ["Options/SampleStrip.lua"] = "the options window",
    ["Options/Registry.lua"] = "the options window's Home page (its shared profiles card, in the window's own gradient)",
    ["PatchNotesUI.lua"] = "shown in the options window's look",
    ["Donators.lua"] = "an options page, all in the Daylight gradient on purpose",
    ["InstallerCards.lua"] = "the setup guide, in the options window's look",
    ["DaylightUI_Buffs/Options.lua"] = "the options window",
    ["DaylightUI_UnitFrames/Options.lua"] = "the options window",
    ["DaylightUI_UnitFrames/Colors.lua"] = "your bar's Daylight gradient setting (its missing part in the purple)",
    ["DaylightUI_Quests/Look.lua"] = "the focus mode \"daylight\" choice",
    ["DaylightUI_UnitFrames/UnitFrames.lua"] = "the portrait ring's \"daylight\" choice",
    ["DaylightUI_ActionBars/Cooldowns.lua"] = "a gradient bar's missing part",
    ["DaylightUI_ActionBars/CdmCard.lua"] = "the bar color's Daylight default",
}
-- Not sorted yet (probably should use the accent). Fix one, then drop its line.
local DAYLIGHT_PENDING = {
    ["DaylightUI_ActionBars/CdmEditor.lua"] = true,
    ["DaylightUI_UnitFrames/ClickBinder.lua"] = true,
}
local function daylightHits(path, text)
    if DAYLIGHT_OK[path] or DAYLIGHT_PENDING[path] then return {} end
    local hits, n = {}, 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        local code = line:gsub("%-%-.*$", "")
        if code:find("TextDaylight") or code:find("TintDaylight") or code:find("GRADIENT_SHAPE")
            or code:find("GRADIENT_MID") then
            hits[#hits + 1] = path .. ":" .. n
        end
    end
    return hits
end

T.test("hygiene: the fixed Daylight colors stay in the options window and daylight choices", function()
    local bad, seen = {}, {}
    for _, path in ipairs(shippedFiles()) do
        local text = read(path) or ""
        for _, h in ipairs(daylightHits(path, text)) do bad[#bad + 1] = h end
        seen[path] = text:find("Daylight") ~= nil or text:find("GRADIENT_") ~= nil
    end
    T.eq(#bad, 0, "a fixed Daylight color outside the options window (the player's accent: Style.Accent() / "
        .. "Style.PaintAccent / W.TextAccent at paint time; a real exception goes in DAYLIGHT_OK with its reason):\n  "
        .. table.concat(bad, "\n  "))
    for path in pairs(DAYLIGHT_OK) do T.truthy(seen[path], "DAYLIGHT_OK file no longer uses them: " .. path) end
    for path in pairs(DAYLIGHT_PENDING) do T.truthy(seen[path], "DAYLIGHT_PENDING file no longer uses them: " .. path) end
end)

T.test("hygiene: the Daylight check finds one", function()
    T.eq(#daylightHits("x.lua", "W.TextDaylight(fs)\nlocal m = Style.GRADIENT_MID\n-- W.TintDaylight(t)\nW.TextAccent(fs)"), 2)
end)
