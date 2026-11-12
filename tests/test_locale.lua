-- Translations: the shared table DUI.L (English text is the key and the
-- fallback), the language files in Locales/, and the pseudo-language sweep
-- that finds English drawn without going through L or Options.Text.
local stub = require("stub")
local K = require("locale_keys")

local ALL = { module = true, actionbars = true, buffs = true, bags = true, nameplates = true, tooltip = true,
              qol = true, chat = true, infopanel = true, skins = true, quests = true }

local function withLocale(locale, fn)
    local before = _G.GetLocale
    _G.GetLocale = function() return locale end
    local ok, err = pcall(fn)
    _G.GetLocale = before
    if not ok then error(err, 0) end
end

T.test("L falls back to the English text and stores nothing on a miss", function()
    local DUI = stub.Load{ login = false }
    T.eq(DUI.L["no such text"], "no such text")
    T.eq(rawget(DUI.L, "no such text"), nil, "nothing written on a miss")
    T.eq(DUI.LOCALE, "enUS", "no client locale in the fake game: English")
    T.eq(DaylightUI.L, DUI.L, "modules read it as DaylightUI.L")
end)

T.test("the client's locale is read before Core.lua", function()
    withLocale("deDE", function()
        local DUI = stub.Load{ login = false }
        T.eq(DUI.LOCALE, "deDE")
    end)
end)

T.test("every language file loads alone, and only for its own language", function()
    for locale, path in pairs(K.LanguageFiles()) do
        local lines, err = K.LoadLanguage(path, locale)
        T.truthy(lines, path .. ": " .. tostring(err))
        T.truthy(next(lines) ~= nil, path .. " has lines")
        local other = K.LoadLanguage(path, locale, locale == "enUS" and "deDE" or "enUS")
        T.eq(next(other), nil, path .. " stores nothing on another client")
    end
end)

-- Every key in a language file must still be shown text. Every translation
-- keeps the key's % holes (a wrong hole errors in string.format in game)
-- and its color and texture codes.
T.test("language files: keys exist, translations keep the holes and codes", function()
    local files = K.LanguageFiles()
    if next(files) == nil then return end
    local DUI = stub.Load(ALL)
    local keys = K.Walk(DUI, K.Scan())
    local bad = {}
    for locale, path in pairs(files) do
        for key, text in pairs(K.LoadLanguage(path, locale) or {}) do
            if not keys[key] then
                bad[#bad + 1] = path .. ": no longer shown: " .. key
            elseif type(text) ~= "string" or text == "" then
                bad[#bad + 1] = path .. ": empty: " .. key
            elseif K.Holes(text) ~= K.Holes(key) then
                bad[#bad + 1] = path .. ": holes differ: " .. key
            elseif K.Codes(text) ~= K.Codes(key) then
                bad[#bad + 1] = path .. ": color codes differ: " .. key
            end
        end
    end
    T.eq(table.concat(bad, "\n"), "")
end)

-- Each language's real lines drawn on every options page, the setup guide
-- and test mode without errors. A translation is only ever text, but this
-- is where one used as more than text would show up.
T.test("every language draws the options, the setup guide and test mode", function()
    for locale, path in pairs(K.LanguageFiles()) do
        local lines = K.LoadLanguage(path, locale)
        local DUI = stub.Load{ module = true, actionbars = true, buffs = true, bags = true, nameplates = true,
            tooltip = true, qol = true, chat = true, infopanel = true, skins = true, quests = true,
            locale = function(L) for k, v in pairs(lines) do L[k] = v end end }
        T.eq(DUI.L["Width"], lines["Width"] or "Width", locale .. " is in")
        for id in DUI.Options.Pages() do DUI.OptionsPanel.Show(id) end
        DUI.OptionsPanel.Search("sha")
        local I = DUI.Installer
        I.Show()
        I.Start("tour")
        for _, s in ipairs(I.Steps()) do I.Go(s.id) end
        DUI.SetTestMode(true)
        stub.RunTimers()
        DUI.SetTestMode(false)
    end
end)

T.test("the key scan joins split literals and reads escapes", function()
    local lits = K.Literals('x = L["a " .. "b"]\ny = L[\'it\\\'s\'] z = L[name] w = L["%d of %d"]')
    T.eq(#lits, 3)
    T.eq(lits[1].text, "a b"); T.eq(lits[2].text, "it's"); T.eq(lits[2].line, 2); T.eq(lits[3].text, "%d of %d")
    T.eq(K.Holes("%d of %s, %.1f%%"), "%d %s %.1f %%")
    T.eq(K.Holes("at 100% it turns, 5% of a level"), "", "a plain percent sign is no hole")
end)

T.test("the key set holds the options' and the guide's own text", function()
    local DUI = stub.Load(ALL)
    local keys = K.Walk(DUI, K.Scan())
    T.truthy(keys["Appearance"], "a core page")
    T.truthy(keys["Snap to grid"], "an item label")
    T.truthy(keys["Thin"], "a dropdown value")
    T.truthy(keys["What's included"], "a guide page")
    T.truthy(keys["Reset page"], "an L literal")
    T.truthy(keys["Shows a sample of just this frame while you edit it, and every change "
        .. "as you make it. Stays on across pages until you switch it off; combat ends it."], "a split literal")
end)

T.test("search finds a setting by its shown text and by its English", function()
    local DUI = stub.Load{ module = true, locale = function(L) L["Snap to grid"] = "Am Raster einrasten" end }
    local O = DUI.Options
    local function found(q)
        for _, hit in ipairs(O.Search(q)) do
            if hit.item.key == "gridSnap" then return true end
        end
    end
    T.truthy(found("raster"), "the shown text")
    T.truthy(found("snap to"), "the English")
end)

-- ---------------------------------------------------------------------
-- The pseudo sweep: every string looked up through L comes back «wrapped».
-- Text drawn on an options page or a guide page with two letters in a row
-- outside the wraps was drawn without L or Options.Text.
-- ---------------------------------------------------------------------

local function pseudo(L)
    setmetatable(L, { __index = function(_, k) return "«" .. tostring(k) .. "»" end })
end

-- Texts that are right in English everywhere, with the reason.
local ALLOW = {
    ["DaylightUI"] = "the name",
    ["Daylight 123"] = "the font sample on the guide's font cards",
    ["Discord"] = "the name, beside the version",
    ["vtest"] = "the version (the fake game's DUI.VERSION)",
    ["Tester"] = "the fake player's name on the guide's sample frames",
    ["Sadeas"] = "a sample target's name (names aren't translated)",
    ["Navani"] = "the unit frames' sample focus (names aren't translated)",
    ["Dalinar"] = "the PvP frames' sample flag carrier (names aren't translated)",
    ["Vivenna"] = "the PvP frames' second sample flag carrier (names aren't translated)",
    ["Syl"] = "the unit frames' sample pet (names aren't translated)",
    ["Kaladin"] = "a sample party/raid member (names aren't translated)",
    ["Lift"] = "a sample party member (names aren't translated)",
    ["Bridge Four"] = "the nameplate preview's sample guild (names aren't translated)",
}

local function leftover(text)
    local s = text
    repeat
        local before = s
        s = s:gsub("«[^«»]*»", "")
    until s == before
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    if not s:find("%a%a") or ALLOW[s] then return nil end
    for allowed in pairs(ALLOW) do
        s = s:gsub(allowed:gsub("%p", "%%%0"), "")
    end
    if s:find("%a%a") then return s end
end

local function walk(frame, where, bad, seen)
    seen = seen or {}
    if seen[frame] then return end
    seen[frame] = true
    for _, child in ipairs(stub.Children(frame)) do
        if child.__type == "FontString" then
            local text = child:GetText()
            -- child.english: text that stays English on purpose (the patch notes).
            if type(text) == "string" and child:IsVisible() and not child.english then
                local rest = leftover(text)
                if rest then bad[#bad + 1] = where .. ": " .. text end
            end
        elseif child.IsVisible and child:IsVisible() then
            walk(child, where, bad, seen)
        end
    end
end

T.test("pseudo sweep: every options page outside NOT_YET draws only translated text", function()
    local DUI = stub.Load{ module = true, actionbars = true, buffs = true, bags = true, nameplates = true,
        tooltip = true, qol = true, chat = true, infopanel = true, skins = true, quests = true, locale = pseudo }
    local bad = {}
    for id, page in DUI.Options.Pages() do
        if not K.NOT_YET[page.scope] then
            DUI.OptionsPanel.Show(id)
            walk(DUI.OptionsPanel.Frame(), "page " .. id, bad)
        end
    end
    DUI.OptionsPanel.Search("sha")
    walk(DUI.OptionsPanel.Frame(), "search", bad)
    T.eq(table.concat(bad, "\n"), "")
end)

T.test("pseudo sweep: every setup guide page draws only translated text", function()
    local DUI = stub.Load{ module = true, actionbars = true, buffs = true, bags = true, nameplates = true,
        tooltip = true, qol = true, chat = true, infopanel = true, skins = true, quests = true, locale = pseudo }
    local I = DUI.Installer
    local bad = {}
    I.Show()
    walk(DUI.InstallerUI.Frame(), "guide welcome", bad)
    I.Start("tour")
    for _, s in ipairs(I.Steps()) do
        I.Go(s.id)
        walk(DUI.InstallerUI.Frame(), "guide " .. s.id, bad)
    end
    T.eq(table.concat(bad, "\n"), "")
end)

-- The addon's frames in the world with test mode's samples up: the info
-- panel (meter, data texts, threat meter), the flight timer, the quest
-- tracker, the chat's copy window, the AFK screen and the zone title.
local WORLD_ALLOW = {
    "Kaladin", "Shallan", "Jasnah", "Adolin", "Lift", "Navani", "Dalinar", "Szeth", "Renarin", "Teft", "Rock",
    "Sigzil", "Lopen", "Moash", "Venli", "Rlain", "Taravangian", "Hoid", "Wit", "Syl",   -- sample players
    "fps", "ms",                                                                          -- units
    "Human",                                     -- the game's own word, UnitRace's localized name (the AFK card)
}

T.test("pseudo sweep: our frames in the world draw only translated text", function()
    local DUI = stub.Load{ module = true, actionbars = true, buffs = true, bags = true, nameplates = true,
        tooltip = true, qol = true, chat = true, infopanel = true, skins = true, quests = true, locale = pseudo }
    local before = {}
    for _, name in ipairs(WORLD_ALLOW) do before[name] = ALLOW[name]; ALLOW[name] = ALLOW[name] or "world sample" end
    DUI.SetTestMode(true)
    stub.RunTimers()
    local M = stub.infopanel.Meter
    M.Draw()
    if M.strip then M.UpdateStrip(); M.strip:Show() end   -- its buttons show on hover
    stub.chatModule.Copy.Show(ChatFrame1)
    stub.qol.Afk.Preview()
    stub.qol.ZoneTitle.Preview()
    stub.qol.Campfire.Preview()
    stub.qol.Campfire.Rested()
    local bad, wrapped = {}, {}
    local function count(frame)
        for _, child in ipairs(stub.Children(frame)) do
            if child.__type == "FontString" then
                local text = child:GetText()
                if child:IsVisible() and type(text) == "string" and text:find("«", 1, true) then
                    wrapped[#wrapped + 1] = text
                end
            elseif child.IsVisible and child:IsVisible() then
                count(child)
            end
        end
    end
    for _, name in ipairs({ "DaylightUIInfoPanel", "DaylightUIDamageMeter", "DaylightUIThreatMeter",
                            "DaylightUIFlightTimer", "DaylightUIQuestTracker", "DaylightUIChatCopy",
                            "DaylightUIChatPanel", "DaylightUIAfkScreen", "DaylightUIZoneTitle", "DaylightUICampfire" }) do
        local f = _G[name]
        if f then walk(f, name, bad); count(f) end
    end
    for _, name in ipairs(WORLD_ALLOW) do ALLOW[name] = before[name] end
    T.eq(table.concat(bad, "\n"), "")
    -- The sweep really saw the samples (the meter's mode, the AFK card...).
    T.truthy(#wrapped >= 5, "translated texts seen: " .. table.concat(wrapped, " | "))
end)

T.test("pseudo sweep: test mode (bars, buffs)", function()
    local DUI = stub.Load{ actionbars = true, buffs = true, bags = true, locale = pseudo }
    local bad = {}
    DUI.SetTestMode(true)
    walk(UIParent, "test mode", bad)
    DUI.SetTestMode(false)
    T.eq(table.concat(bad, "\n"), "")
end)

-- The spellbook and talents window (Book/), both pages. Spell, talent, school
-- and tree names come from the game (already in the player's language).
T.test("pseudo sweep: the spellbook and talents window", function()
    local BW = require("bookworld")
    local DUI = stub.Load{ locale = pseudo, before = function()
        BW.world()()
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { Book = { enabled = true } } } } }
    end }
    local B = DUI.Book.Window
    -- Every string the fake game hands over, plus its upper case for section titles.
    local added, seen = {}, {}
    local function allow(t)
        if seen[t] then return end
        seen[t] = true
        for _, v in pairs(t) do
            if type(v) == "string" then
                for _, w in ipairs({ v, v:upper() }) do
                    if not ALLOW[w] then ALLOW[w] = "the game's text"; added[#added + 1] = w end
                end
            elseif type(v) == "table" then allow(v) end
        end
    end
    allow(BW.book); allow(BW.tree)
    local bad = {}
    BW.Open(BW.SPELLBOOK)
    DUI.Win.Followers.Tick()
    stub.RunTimers()
    walk(B.frame, "spellbook", bad)
    B.Show("talents")
    stub.RunTimers()
    walk(B.frame, "talents", bad)
    for _, w in ipairs(added) do ALLOW[w] = nil end
    T.eq(table.concat(bad, "\n"), "")
end)

-- The profession window (Craft/): a profession, a recipe, a slot picked,
-- crafting under way. Profession, recipe, item and slot names come from
-- the game.
T.test("pseudo sweep: the profession window", function()
    local PW = require("craftworld")
    local DUI = stub.Load{ locale = pseudo, before = PW.world({}) }
    local C = DUI.Craft.Window
    local added = {}
    local function allow(w)
        for _, v in ipairs({ w, w:upper() }) do
            if not ALLOW[v] then ALLOW[v] = "the game's text"; added[#added + 1] = v end
        end
    end
    for _, p in ipairs(PW.state.profs) do
        allow(p.name)
        for _, r in ipairs(p.recipes) do allow(r.name) end
        for _, s in ipairs(p.slots or {}) do allow(s) end
    end
    for _, n in pairs(PW.ITEMS) do allow(n) end
    for _, c in pairs(PW.CATEGORIES) do allow(c.name) end
    allow("Cooking Fire")
    local bad = {}
    PW.Open(197)
    stub.RunTimers()
    DUI.Win.Followers.Tick()
    T.truthy(DUI.Win.IsOpen(C.frame), "the profession window opened")
    walk(C.frame, "professions", bad)
    DUI.Craft.List.PickSlot(2)
    walk(C.frame, "professions, a slot", bad)
    DUI.Craft.Make.Create()
    walk(C.frame, "professions, making", bad)
    PW.Cast()
    stub.RunTimers()
    for _, w in ipairs(added) do ALLOW[w] = nil end
    T.eq(table.concat(bad, "\n"), "")
end)

-- The group finder window (Lfg/): Find a group with a group opened, List
-- yourself, Who. Activity, category, people, guild, zone, race and class
-- names and the notes come from the game.
T.test("pseudo sweep: the group finder window", function()
    local LW = require("lfgworld")
    local DUI = stub.Load{ locale = pseudo, before = LW.world({}) }
    local G = DUI.Lfg.Window
    local added = {}
    local function allow(w)
        if type(w) ~= "string" or w == "" then return end
        for _, v in ipairs({ w, w:upper() }) do
            if not ALLOW[v] then ALLOW[v] = "the game's text"; added[#added + 1] = v end
        end
    end
    for _, a in pairs(LW.ACTIVITIES) do allow(a.fullName) end
    for _, c in pairs(LW.CATEGORIES) do allow(c.name) end
    for _, g in pairs(LW.GROUPS) do allow(g[1]) end
    for _, r in ipairs(LW.Sample()) do
        allow(r.comment)
        for _, m in ipairs(r.members) do allow(m.name); allow(m.areaName) end
    end
    for _, w in ipairs(LW.WHO) do
        for _, k in ipairs({ "fullName", "fullGuildName", "raceStr", "classStr", "area" }) do allow(w[k]) end
    end
    for i = 1, 4 do allow(_G["GROUP_FINDER_GENERAL_PLAYSTYLE" .. i]) end   -- the game's playstyle words
    -- A member's level and class (the game's class word).
    for _, r in ipairs(LW.Sample()) do
        for _, m in ipairs(r.members) do
            local what = m.level .. " " .. DUI.Lfg.Rows.ClassWord(m.classFilename)
            allow(what)
            if m.areaName then allow(what .. "  ·  " .. m.areaName) end
        end
    end
    local bad = {}
    LW.Toggle(1)
    stub.RunTimers()
    DUI.Win.Followers.Tick()
    T.truthy(DUI.Win.IsOpen(G.frame), "the group finder opened")
    stub.Key(G.ShowTab, "find", true)
    stub.RunTimers()
    DUI.Lfg.Browse.Toggle(17)
    walk(G.frame, "group finder, find", bad)
    stub.Key(G.ShowTab, "list", true)
    walk(G.frame, "group finder, list", bad)
    stub.Key(G.ShowTab, "who", true)
    stub.RunTimers()
    walk(G.frame, "group finder, who", bad)
    for _, w in ipairs(added) do ALLOW[w] = nil end
    T.eq(table.concat(bad, "\n"), "")
end)

-- The social window (Social/): Friends, Recent allies, Requests, Raid.
-- Friends' and allies' names, their characters, zones, races, games and
-- notes, the raid's names and saved raids come from the game.
T.test("pseudo sweep: the social window", function()
    local SW = require("socialworld")
    local DUI = stub.Load{ locale = pseudo, before = SW.world({ raid = SW.Roster() }) }
    local G = DUI.Social.Window
    local added = {}
    local function allow(w)
        if type(w) ~= "string" or w == "" then return end
        for _, v in ipairs({ w, w:upper() }) do
            if not ALLOW[v] then ALLOW[v] = "the game's text"; added[#added + 1] = v end
        end
    end
    for _, f in ipairs(SW.Friends()) do
        allow(f.accountName)
        local g = f.gameAccountInfo
        allow(g.characterName); allow(g.areaName); allow(g.raceName); allow(g.richPresence)
        if g.characterName then allow(f.accountName .. "  " .. g.characterName) end
        allow(f.note); allow(f.customMessage)
    end
    for _, a in ipairs(SW.Allies()) do allow(a.characterData.name) end
    allow("Bramblefoot#2231"); allow("Nyx#9810")
    for _, m in ipairs(SW.Roster()) do allow(m[1]); allow(m[1]:match("^(%S+)")) end
    allow("Molten Core"); allow("Onyxia's Lair")
    local bad = {}
    SW.Toggle()
    stub.RunTimers()
    DUI.Win.Followers.Tick()
    T.truthy(DUI.Win.IsOpen(G.frame), "the social window opened")
    walk(G.frame, "social, friends", bad)
    for _, id in ipairs({ "allies", "requests", "raid" }) do
        stub.Key(G.ShowTab, id, true)
        stub.RunTimers()
        walk(G.frame, "social, " .. id, bad)
    end
    for _, w in ipairs(added) do ALLOW[w] = nil end
    T.eq(table.concat(bad, "\n"), "")
end)

-- The mailbox window (Mail/): the Inbox with a letter open, Send, Ledger.
-- Senders, subjects and letters' words come from the game.
T.test("pseudo sweep: the mailbox window", function()
    local MW = require("mailworld")
    local LETTERS = { { sender = "Brannoc Ironhide", subject = "Ore money", money = 15000, body = "For the ore." },
                      { sender = "Thaxton Ashby", subject = "Hello" } }
    local DUI = stub.Load{ locale = pseudo, before = MW.world({ letters = LETTERS }) }
    local M = DUI.Mail.Window
    local added = {}
    local function allow(w)
        if type(w) ~= "string" or w == "" then return end
        for _, v in ipairs({ w, w:upper() }) do
            if not ALLOW[v] then ALLOW[v] = "the game's text"; added[#added + 1] = v end
        end
    end
    for _, l in ipairs(LETTERS) do allow(l.sender); allow(l.subject); allow(l.body) end
    local bad = {}
    MW.Open()
    stub.RunTimers()
    DUI.Win.Followers.Tick()
    T.truthy(DUI.Win.IsOpen(M.frame), "the mailbox window opened")
    walk(M.frame, "mailbox, inbox", bad)
    DUI.Mail.Inbox.Pick(1)
    stub.RunTimers()
    walk(M.frame, "mailbox, a letter", bad)
    for _, id in ipairs({ "send", "ledger" }) do
        M.ShowTab(id)
        stub.RunTimers()
        walk(M.frame, "mailbox, " .. id, bad)
    end
    for _, w in ipairs(added) do ALLOW[w] = nil end
    T.eq(table.concat(bad, "\n"), "")
end)

-- The Legacy window (Legacy/): Progress, Challenges, Legacy trees. Reward,
-- category, challenge, step and talent names come from the game.
T.test("pseudo sweep: the Legacy window", function()
    local LGW = require("legacyworld")
    local DUI = stub.Load{ locale = pseudo, before = LGW.world({}) }
    local G = DUI.Legacy.Window
    local added = {}
    local function allow(w)
        if type(w) ~= "string" or w == "" then return end
        for _, v in ipairs({ w, w:upper() }) do
            if not ALLOW[v] then ALLOW[v] = "the game's text"; added[#added + 1] = v end
        end
    end
    for _, lv in ipairs(LGW.Levels()) do for _, r in ipairs(lv.rewards) do allow(r.name) end end
    for _, c in ipairs(LGW.Categories()) do allow(c.name) end
    for _, a in ipairs(LGW.Achievements()) do
        allow(a.name); allow(a.desc)
        for _, st in ipairs(a.steps or {}) do allow(st.text) end
    end
    allow("Toy"); allow("Pet"); allow("Tabard"); allow("Mount")
    for _, t in pairs(LGW.Trees()) do
        for _, n in ipairs(t.nodes) do for _, e in ipairs(n.choices or { n.id * 10 }) do allow("Perk " .. e) end end
    end
    local bad = {}
    LGW.Toggle()
    stub.RunTimers()
    DUI.Win.Followers.Tick()
    T.truthy(DUI.Win.IsOpen(G.frame), "the Legacy window opened")
    walk(G.frame, "legacy, progress", bad)
    for _, id in ipairs({ "challenges", "trees" }) do
        stub.Key(G.ShowTab, id)
        stub.RunTimers()
        walk(G.frame, "legacy, " .. id, bad)
    end
    for _, w in ipairs(added) do ALLOW[w] = nil end
    T.eq(table.concat(bad, "\n"), "")
end)

-- The inspect window (Inspect/), both pages, empty and filled. Their name,
-- guild, item, enchant and talent names come from the game.
T.test("pseudo sweep: the inspect window", function()
    local CW, IW, BW = require("charworld"), require("inspectworld"), require("bookworld")
    local gear = { target = {
        [1] = CW.item("Lionheart Helm", { quality = 4, level = 65, enchantId = 2583, enchant = "+10 Defense" }),
        [16] = CW.item("Ashkandi", { quality = 4, level = 77 }),
    } }
    local DUI = stub.Load{ locale = pseudo, before = IW.world({ gear = gear, itemLevel = { target = 63.4 }, late = true }) }
    local I = DUI.Inspect.Window
    local added, seen = {}, {}
    local function allow(t)
        if seen[t] then return end
        seen[t] = true
        for _, v in pairs(t) do
            if type(v) == "string" then
                for _, w in ipairs({ v, v:upper() }) do
                    if not ALLOW[w] then ALLOW[w] = "the game's text"; added[#added + 1] = w end
                end
            elseif type(v) == "table" then allow(v) end
        end
    end
    allow(BW.trees[IW.CONFIG]); allow(gear)
    allow({ "Garrick", "Garrick Stone", "+10 Defense" })
    local bad = {}
    IW.Inspect("target")
    stub.RunTimers()
    DUI.Win.Followers.Tick()
    T.truthy(DUI.Win.IsOpen(I.frame), "the inspect window opened")
    walk(I.frame, "inspect, no gear yet", bad)
    IW.Arrive("target")
    stub.RunTimers()
    walk(I.frame, "inspect gear", bad)
    I.Show("talents")
    stub.RunTimers()
    walk(I.frame, "inspect talents", bad)
    for _, w in ipairs(added) do ALLOW[w] = nil end
    T.eq(table.concat(bad, "\n"), "")
end)

