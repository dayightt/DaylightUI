-- The first half of tools/snap.py. It opens a Daylight UI window in the fake game,
-- lets every fade and glide finish, and writes what's on screen (each shown frame,
-- texture and text: anchors, size, scale, alpha, colors, texture files, text and
-- font) to tests/snaps/<name>.json. snap.py lays it out the way the client does
-- and draws it. Run snap.py, not this.
--   luajit tools/snap.lua <recipe> [arg]       a recipe below
--   luajit tools/snap.lua --file my.lua [arg]  your own: the file returns
--       { before = fn() (optional, before load), open = fn(DUI, arg) -> frame to crop to (optional),
--         play = fn(DUI, arg) (optional: something to do once it's open, for --gif) }
-- With SNAP_GIF=<folder> (snap.py --gif) it instead writes every step of the
-- opening (and of play) as <folder>/0001.json..., and snap.py draws each into a GIF.

package.path = "tests/?.lua;" .. package.path
T = T or {}   -- tests/stub.lua reads the test helpers' table
local stub = require("stub")

local ALL = { module = true, actionbars = true, buffs = true, skins = true, bags = true, nameplates = true,
              tooltip = true, qol = true, chat = true, infopanel = true, quests = true }

-- Each recipe: before (the test world, optional), open(DUI, arg) -> the frame to crop to (nil = the whole screen).
-- For --gif, optional film = { open = s, play = s }: how long each part is filmed (1.2 s each by default).
local RECIPES = {
    ui = { about = "the screen after login: unit frames, bars, panel, chat", open = function() end },
    fight = { about = "in a fight with a target: everything awake [thin|thick: that portrait ring, no middle line]", open = function(DUI, ring)
        if ring == "thin" or ring == "thick" then
            DUI:Set("UnitFrames", "portraits.ringWidth", ring)
            DUI:Set("UnitFrames", "portraits.ringLine", false)
        end
        stub.units.target = { name = "Defias Thug", health = 640, maxHealth = 1000, reaction = 2, level = 20,
                              class = "WARRIOR", power = 40, maxPower = 100 }
        stub.FireEvent("PLAYER_TARGET_CHANGED")
        stub.EnterCombat()
    end },
    midcast = { about = "the player's cast bar between the frames, the swing timers fanning out under it", open = function(DUI)
        DUI:Set("UnitFrames", "playerCastbar.at", "middle")
        stub.RunTimers()
        DUI.SetTestMode(true)
        stub.RunTimers()
    end },
    padhud = { about = "the game's controller bars in the Daylight look [held: the left trigger's bar grown]", open = function(DUI, mode)
        _G.GamepadMode = { FrameControlsManager = { FrameShown = function() end, FrameHidden = function() end } }
        _G.InputUtil = { IsGamepadUIEnabled = function() return true end }
        local main = require("fake_padbars").Install()
        local slot = 0
        for _, bar in pairs(main.PageUnit.actionBars) do
            for i, b in ipairs(bar.actionButtons) do
                slot = slot + 1
                b.action = 300 + slot
                if i % 3 ~= 0 then
                    b.icon:SetTexture(135808 + slot)
                    stub.slots[b.action] = { texture = 135808 + slot }
                end
            end
        end
        DUI.Fire("PadChanged")
        stub.RunTimers()
        if mode == "held" then GamepadActionBarStyleUtil.ApplyExpandedActionBarStyle(main.PageUnit.actionBars.leftBar) end
        return main
    end },
    panel = { about = "the info panel: meter and threat meter out [left: moved to the top-left, so they come out of its right side]", open = function(DUI, side)
        DUI:Set("InfoPanel", "meter.enabled", true)
        if side == "left" then
            DUI.DB.Positions().infopanel = { -600, 250 }
            DUI.Movers.Apply("infopanel")
        end
        DUI.SetTestSolo({ "meter", "threat", "datatexts" })
        DUI.SetTestMode(true)
    end },
    meters = { about = "the meters: the panel's, a healing window, a threat window and the threat meter beside the panel", open = function(DUI)
        DUI:Set("InfoPanel", "meter.enabled", true)
        local W = DUI:GetModule("InfoPanel").ns.Windows
        W.Add("healing")
        W.Add("threat")
        local s = W.Add("summary")
        DUI.DB.Positions()["infopanel.meter." .. s] = { -200, 0 }
        DUI.SetTestSolo({ "meter", "threat", "meters", "datatexts" })
        DUI.SetTestMode(true)
    end },
    breakdown = { about = "the breakdown window: a click on the meter's first player [targets: its Targets tab]", open = function(DUI, tab)
        DUI:Set("InfoPanel", "meter.enabled", true)
        DUI.SetTestSolo({ "meter" })
        DUI.SetTestMode(true)
        local ns = DUI:GetModule("InfoPanel").ns
        ns.Meter.Draw()
        ns.BreakdownWindow.Open(ns.Meter, ns.Meter.rows[1].src)
        if tab then ns.BreakdownWindow.Show(tab) end
    end },
    databar = { about = "the data bar along the bottom of the screen [new: combat and volume in it] [ammo: ammo and shards in it]", open = function(DUI, arg)
        DUI:Set("InfoPanel", "databar.enabled", true)
        if arg == "new" then
            DUI:Set("InfoPanel", "databar.left4", "combat")
            DUI:Set("InfoPanel", "databar.right4", "volume")
            DUI:Set("InfoPanel", "databar.left3", "ilvl")
            DUI:Set("InfoPanel", "databar.left1", "hearth")
            DUI:Set("InfoPanel", "databar.right1", "professions")
            DUI:Set("InfoPanel", "databar.right3", "played")
        elseif arg == "ammo" then
            DUI:Set("InfoPanel", "databar.right3", "ammo")
            DUI:Set("InfoPanel", "databar.right4", "shards")
        end
        DUI.SetTestSolo({ "datatexts" })
        DUI.SetTestMode(true)
    end },
    campfire = { about = "sitting by a campfire: the seconds left", open = function()
        stub.SetAuras("player", "HELPFUL", { { spellId = 1229739, name = "Welcoming Campfire",
            expirationTime = GetTime() + 60, duration = 60 } })
        stub.FireEvent("UNIT_AURA", "player")
    end },
    guide = { about = "the setup guide, as a new character meets it [finish|done: Quick setup's last page]", guide = true,
        open = function(DUI, page)
            if page == "finish" or page == "done" then
                DUI.Installer.Start("quick", "Immersive Preset")
                DUI.Installer.Go("finish")
                if page == "done" then
                    -- As Finish leaves it, since the fake game has no Edit Mode layouts to write.
                    DUI.Installer.flow.finished = true
                    DUI.InstallerUI.Retitle(DUI.Installer.FinishWords())
                    DUI.Installer.pages.finish.RunChecklist(true)
                    stub.RunTimers()
                end
            end
            return _G.DaylightUIInstaller
        end },
    ccalert = { about = "the crowd control alert [secret: as under restrictions]", world = "locworld",
        before = function(LW) LW.Install() end, open = function(_, kind, LW)
            local dur = { "a duration object" }
            local v = kind == "secret" and stub.Secret or function(x) return x end
            stub.RunTimers()
            LW.Land(_G.LossOfControlFrame, v(LOSS_OF_CONTROL_DISPLAY_STUN), v(135860), v("4.2"), 2, dur)
            local h = _G.LossOfControlFrame
            return h
        end },
    loot = { about = "the loot window on a corpse [long: enough to scroll]", world = "lootworld",
        before = function(LW) LW.Install() end, open = function(_, kind, LW)
            stub.RunTimers()
            local slots = LW.Corpse()
            if kind == "long" then
                slots[#slots + 1] = { name = "Blood-Soaked Legplates of the Forgotten King", link = "item:2", quality = 3, icon = 134584 }
                slots[#slots + 1] = { name = "Bent Spoon", quality = 0, icon = 133747 }
            end
            LW.Open(_G.LootFrame, slots)
            stub.RunTimers()
            return _G.LootFrame
        end, play = function(_, _, LW) LW.Take(_G.LootFrame, 3) end },
    cdm = { about = "the Cooldown Manager layout editor with a spell's card [look|show|chain]", open = function(DUI, tab)
        local AB = stub.actionbars
        local D, Ed = AB.CdmData, AB.CdmEditor
        Ed.Open(DUI.DB.SpecGroup())
        local set = D.Current()
        D.AddChain(set, { 11, 12, 13 }, "icon", -60, -100)
        Ed.Select(12)
        if tab then AB.CdmCard.SetTab(tab) end
        return _G.DaylightUICdmEditor
    end },
    platepower = { about = "the nameplates' Health & Names page with the power bar on, zoomed in [friendly: the Friendly page]", open = function(DUI, which)
        DUI:Set("Nameplates", "power", true)
        DUI:Set("Nameplates", "friendly.enabled", true)
        DUI:Set("Nameplates", "friendly.power", true)
        stub.RunTimers()
        stub.nameplates.Sample.zoom = 3     -- big enough to judge a 4 px bar
        DUI.OptionsPanel.Show(which == "friendly" and "Nameplates.friendly" or "Nameplates.bars")
        return _G.DaylightUIOptions
    end },
    tour = { about = "the tour's card on a stop [ask: the question after setup] [meter|datatexts|buffs|unlock|options]", open = function(DUI, stop)
        DUI.Installer.Mark("installed")
        DUI.Installer.MarkSeen()
        if stop == "ask" then
            DUI.DB.Character().tourOffer = true
            DUI.Tour.Offer()
            return
        end
        DUI.Tour.Start()
        stub.RunTimers()
        for _ = 1, 8 do
            if not stop or DUI.Tour.StepId() == stop then break end
            DUI.Tour.Next()
            stub.RunTimers()
        end
    end },
    options = { about = "the options window [page id[:tab[:meter window id]]]", open = function(DUI, page)
        local id, tab, pick = string.match(page or "", "^([^:]*):?([^:]*):?(.*)$")
        if pick ~= "" and id == "InfoPanel.meter" then DUI:GetModule("InfoPanel").ns.MeterOptions.Pick(pick) end
        DUI.OptionsPanel.Show(id ~= "" and id or page)
        if tab ~= "" then DUI.OptionsPanel.SetTab(tab) end
        return _G.DaylightUIOptions
    end },
    book = { about = "the spellbook [spells|talents] [fight: opened by P in a fight, its cast layer on]", world = "bookworld", before = function(BW)
        BW.world({})()
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { Book = { enabled = true } } } } }
    end, open = function(_, tab, BW)
        if tab == "fight" then
            require("stub").EnterCombat()
            BW.Key("P")
            return _G.DaylightUIBook
        end
        BW.Open(tab == "talents" and BW.TALENTS or BW.SPELLBOOK)
        return _G.DaylightUIBook
    end },
    character = { about = "the character window [the game's page: ReputationFrame, SkillFrame...]", character = true,
        world = "charworld", before = function(CW)
        CW.world({ factions = {
            CW.faction("Alliance", 0, 0, 0, 0, { isHeader = true }),
            CW.faction("Stormwind", 5, 3000, 3000, 9000, { isChild = true }),
            CW.faction("Ironforge", 6, 9000, 9000, 21000, { isChild = true }),
        } })()
        local key = "Daylight-" .. tostring(GetRealmName and GetRealmName() or "")   -- charworld's player
        _G.DaylightUIDB = { characters = { [key] = { install = "installed" } } }
    end, open = function(DUI, page)
        ToggleCharacter(page or "PaperDollFrame")
        stub.character.Follow.Tick()
        stub.RunTimers()
        local w = stub.character.window
        w:ClearAllPoints()   -- it hangs from the parked game window, which has no place here
        w:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        return w
    end },
    tracker = { about = "the quest tracker with three quests, one in your party [voice: Spoken on, Play buttons] [scrolled: a long list scrolled down, the header pinned]", world = "questworld",
        before = function(QW)
            if arg[2] == "scrolled" then
                local qs = {}
                for i = 1, 12 do
                    qs[i] = QW.quest(i, "The Threat Within, part " .. i, { objs = { { text = "3/8 Abrecaminos Bosque Negro", have = 3, need = 8 } } })
                end
                QW.world({ quests = qs })()
                return
            end
            QW.world({ partySize = 2, quests = {
                QW.quest(1, "Westfall Stew", { objs = { { text = "4/5 Stringy Vulture Meat", have = 4, need = 5 },
                    { text = "3/6 Goretusk Snout", have = 3, need = 6 } } }),
                QW.quest(2, "The Defias Brotherhood", { onParty = { "party1" } }),
                QW.quest(3, "Red Leather Bandanas", { elite = true, objs = { { text = "2/15 Red Leather Bandana", have = 2, need = 15 } } }),
            } })()
            if arg[2] == "voice" then
                _G.Spoken = { RegisterCallback = function() end }
                _G.VoiceOver = { QuestOverlayUI = { ShowsTrackerButton = function(_, id) return id ~= 3 end,
                    BindPlayButton = function() end, FollowQueue = function(b) b:SetState(b.questID == 2 and "stop" or "play") end } }
            end
        end, open = function(DUI)
            for _ = 1, 10 do stub.RunTimers() end
            if arg[2] == "scrolled" then
                DUI:Set("Quests", "maxHeight", 260)
                for _ = 1, 5 do stub.RunTimers() end
                local Tr = stub.quests and stub.quests.Tracker
                if Tr and Tr.view then
                    Tr.view:GetScript("OnMouseWheel")(Tr.view, -2)
                    local d = DUI.Motion.Driver()
                    for _ = 1, 40 do if d then stub.RunOnUpdate(d, 1 / 60) end end
                    function Tr.view:IsMouseOver() return true end
                    Tr.Hovered()
                    for _ = 1, 40 do if d then stub.RunOnUpdate(d, 1 / 60) end end
                end
            end
            return _G.DaylightUIQuestTracker
        end },
    social = { about = "the social window [tab number]", world = "socialworld", before = function(SW)
        SW.world({})()
    end, open = function(_, tab, SW)
        SW.Toggle(tonumber(tab))
        return _G.DaylightUISocial
    end },
    lfg = { about = "the group finder's List yourself [group: leading a party of 3] [find: Find a group] [listed: listed, Find narrowed to it]", world = "lfgworld", before = function(LW)
        LW.world({})()
    end, open = function(_, how, LW)
        local Win = DaylightUI.Win
        local function settle()
            for _ = 1, 20 do
                stub.RunTimers()
                Win.Followers.Tick()
                local d = Win.Feel.Driver()
                if d then stub.RunOnUpdate(d, 1 / 30) end
                local m = DaylightUI.Motion.Driver()
                if m then stub.RunOnUpdate(m, 1 / 30) end
            end
        end
        LW.Toggle(1)
        settle()
        stub.Key(function() stub.lfg.Window.ShowTab(how == "find" and "find" or "list", true) end)
        if how == "listed" then
            local L = stub.lfg.Listing
            for _, b in ipairs(L.page.stack.used) do
                if b:IsShown() and b.spec and b.spec.kind == "act" then b:GetScript("OnClick")(b, "LeftButton"); break end
            end
            L.PickStyle(1)
            stub.Key(L.Post)
        end
        if how == "group" then
            LW.Group(3, true)
            stub.Key(function() _G.UnitSetRole("player", "HEALER") end)
        end
        settle()
        local fr = stub.lfg.Window.frame
        fr:ClearAllPoints()
        fr:SetPoint("CENTER", UIParent, "CENTER", 0, 0)   -- it follows the game's window, which has no place here
        return fr
    end },
    bags = { about = "the bag window, narrow [slot size]", open = function(DUI, size)
        stub.RunTimers()
        _G.C_Container = setmetatable({
            GetContainerNumSlots = function(id) return id == 0 and 20 or 0 end,
            GetContainerNumFreeSlots = function(id) return id == 0 and 20 or 0, 0 end,
        }, { __index = function() return function() end end })
        DUI:Set("Bags", "iconSize", tonumber(size) or 26)
        DUI:Set("Bags", "columns", 7)
        stub.RunTimers()
        _G.DaylightUIBag:Show()
        stub.RunTimers()
        return _G.DaylightUIBag
    end },
    whispers = { about = "the whispers window (/dui whispers) with three conversations", open = function(DUI)
        stub.RunTimers()
        DUI:Set("Chat", "style", "daylight")
        stub.RunTimers()
        local CH = stub.chatModule
        for _, who in ipairs({ { "Lephoque", "got the key?" }, { "Aelith", "thanks for the run" }, { "Maren", "still on for tonight?" } }) do
            stub.FireEvent("CHAT_MSG_WHISPER", who[2], who[1], "", "", "", "", 0, 0, "", 0, 1, "Player-1-0001")
        end
        CH.Talk.Pin(CH.Talk.Get("w:Lephoque"), true)
        CH.Hub.Open()
        return CH.Hub.Frame()
    end },
    chat = { about = "the Daylight chat box, its panel showing [voice: the headset icon on]", open = function(DUI, opt)
        stub.RunTimers()
        DUI:Set("Chat", "style", "daylight")
        DUI:Set("Chat", "hides", "never")
        if opt == "voice" then DUI:Set("Chat", "voiceButton", true) end
        stub.RunTimers()
        return _G.DaylightUIChat
    end },
    chatfilter = { about = "the chat's Show window (what a tab shows) [tab number]", open = function(_, tab)
        stub.RunTimers()
        -- The game's default message colors (the fake game has none).
        local c = { SAY = { 1, 1, 1 }, WHISPER = { 1, 0.5, 1 }, PARTY = { 0.667, 0.667, 1 },
            RAID = { 1, 0.498, 0 }, GUILD = { 0.251, 1, 0.251 }, OFFICER = { 0.251, 0.753, 0.251 },
            CHANNEL = { 1, 0.753, 0.753 }, LOOT = { 0, 0.667, 0 }, COMBAT_XP_GAIN = { 0.435, 0.435, 1 },
            MONSTER_SAY = { 1, 1, 0.624 }, SYSTEM = { 1, 1, 0 }, YELL = { 1, 0.251, 0.251 },
            EMOTE = { 1, 0.502, 0.251 }, INSTANCE_CHAT = { 1, 0.498, 0.039 }, RAID_WARNING = { 1, 0.282, 0 },
            MONEY = { 1, 1, 0 }, COMBAT_FACTION_CHANGE = { 0.502, 0.502, 1 }, SKILL = { 0.333, 0.333, 1 },
            ACHIEVEMENT = { 1, 1, 0 }, RAID_BOSS_EMOTE = { 1, 0.867, 0 } }
        _G.ChatTypeInfo = _G.ChatTypeInfo or {}
        for t, v in pairs(c) do _G.ChatTypeInfo[t] = { r = v[1], g = v[2], b = v[3] } end
        _G.GetChannelList = function() return 1, "General", false, 2, "Trade", false, 5, "Heroes", false end
        stub.chatModule.Filter.Open(tonumber(tab) or 2)
        return _G.DaylightUIChatFilter
    end },
    craft = { about = "the profession window on an enchant [pick: no item picked yet]", world = "craftworld",
        before = function(PW)
            PW.world({ profs = { { name = "Enchanting", skillLine = 333, icon = 136244, spellID = 7411, rank = 142, max = 225, recipes = {
                { id = 201, name = "Enchant Bracer - Minor Stamina", cat = 10, difficulty = 1, enchant = true, mats = { { 4306, 3 } }, quality = 1 },
                { id = 202, name = "Enchant Bracer - Lesser Spirit", cat = 10, difficulty = 2, enchant = true, mats = { { 4306, 2 } }, quality = 1 },
                { id = 203, name = "Enchant Cloak - Minor Agility", cat = 11, difficulty = 3, enchant = true, mats = { { 2589, 1 } }, quality = 1 },
            } } } })()
        end, open = function(DUI, look, PW)
            PW.EnchantItems({ { guid = "Item-1", name = "Worn Leather Bracers", quality = 1 },
                { guid = "Item-2", name = "Silver-thread Cuffs", quality = 2 } })
            PW.SetBag(4306, 24)
            PW.SetBag(2589, 12)
            if look ~= "pick" then DUI.Craft.Make.SetTarget("Item-2") end
            PW.Open(333)
            for _ = 1, 20 do
                stub.RunTimers()
                DUI.Win.Followers.Tick()
                local d = DUI.Win.Feel.Driver()
                if d then stub.RunOnUpdate(d, 1 / 30) end
                local m = DUI.Motion.Driver()
                if m then stub.RunOnUpdate(m, 1 / 30) end
            end
            local w = DUI.Craft.Window.frame
            w:ClearAllPoints()   -- it hangs from the parked game window, which has no place here
            w:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            return w
        end },
    craftview = { about = "someone's linked profession, the small look-only window", world = "craftworld",
        before = function(PW) PW.world({ linked = true })() end,
        open = function(DUI, _, PW)
            PW.state.linkedName, PW.state.linkedSkill = "Barry Maannalaow", 81
            PW.Open(197)
            for _ = 1, 20 do
                stub.RunTimers()
                DUI.Win.Followers.Tick()
                local d = DUI.Win.Feel.Driver()
                if d then stub.RunOnUpdate(d, 1 / 30) end
                local m = DUI.Motion.Driver()
                if m then stub.RunOnUpdate(m, 1 / 30) end
            end
            local w = DUI.Craft.View.frame
            w:ClearAllPoints()   -- it hangs from the parked game window, which has no place here
            w:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            return w
        end },
    npc = { about = "the NPC window's sample talk [immersive: the whole screen]", open = function(DUI, look)
        DUI:Set("NPC", "look", look == "immersive" and "immersive" or "window")
        DUI.Npc.Window.Sample()
        if look ~= "immersive" then return _G.DaylightUINpc end
    end },
}

local name, arg1 = arg[1], arg[2]
local recipe
if name == "--file" then
    recipe = dofile(arg[2])
    name, arg1 = arg[2]:match("([%w_%-]+)%.lua$") or "custom", arg[3]
else
    recipe = RECIPES[name or ""]
end
if not recipe then
    print("usage: py tools/snap.py <recipe> [arg]   or   py tools/snap.py --file my.lua [arg]")
    local names = {}
    for n in pairs(RECIPES) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do print(string.format("  %-9s %s", n, RECIPES[n].about)) end
    os.exit(1)
end

-- Text measured with the real fonts (tests/snaps/metrics.lua, made by snap.py), so
-- code that sizes or stacks things by their text lays out as in game. The tests
-- themselves keep the fake game's 7 px per letter.
local okMetrics, M = pcall(dofile, "tests/snaps/metrics.lua")
if okMetrics and type(M) == "table" then
    local function metricsOf(fs)
        local f = rawget(fs, "__font")
        local file = f and type(f[1]) == "string" and f[1]:lower():gsub("\\", "/"):match("([^/]+)$")
        return M.fonts[file or ""] or M.fonts[M.default], (f and tonumber(f[2])) or 12
    end
    -- A width from SetWidth, or from a left and a right anchor (as the client lays
    -- it out): the width a text wraps at.
    local SIDE = { LEFT = 0, RIGHT = 1 }
    local function side(point) return point:find("LEFT") and 0 or point:find("RIGHT") and 1 or 0.5 end
    local function widthOf(w, depth)
        depth = depth or 0
        if type(w) == "string" then w = _G[w] end
        if type(w) ~= "table" or depth > 12 then return nil end
        local own = tonumber(rawget(w, "__w"))
        if own and own > 0 then return own end
        local left, right
        for _, p in ipairs(rawget(w, "__points") or {}) do
            local rel = p[2] or rawget(w, "__parent")
            if p[1] == "ALL" then return widthOf(rel, depth + 1) end
            local s = side(p[1])
            if s == 0 then left = { rel, side(p[3] or p[1]), tonumber(stub.Plain(p[4])) or 0 } end
            if s == 1 then right = { rel, side(p[3] or p[1]), tonumber(stub.Plain(p[4])) or 0 } end
        end
        if not left or not right then
            if w == _G.UIParent then return rawget(w, "__w") end
            return nil
        end
        if left[1] == right[1] then
            local rw = widthOf(left[1], depth + 1)
            return rw and (rw * (right[2] - left[2]) + right[3] - left[3]) or nil
        end
        return nil
    end
    -- One letter at a time (for a multi-byte UTF-8 letter, the average width).
    local function lineWidth(m, size, line)
        local w = 0
        for ch in line:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            w = w + (#ch == 1 and m.w[ch:byte()] or m.avg)
        end
        return w * size
    end
    stub.measure = function(fs, unbounded)
        local m, size = metricsOf(fs)
        local text = fs.__text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "  ")
            :gsub("|A.-|a", "  "):gsub("|H.-|h", ""):gsub("|h", ""):gsub("|n", "\n")
        local limit = not unbounded and widthOf(fs) or nil
        if limit and limit <= 0 then limit = nil end
        local widest, lines = 0, 0
        for para in (text .. "\n"):gmatch("(.-)\n") do
            if limit and lineWidth(m, size, para) > limit then
                local cur = ""
                for word in para:gmatch("%S+") do
                    local test = cur == "" and word or (cur .. " " .. word)
                    if cur ~= "" and lineWidth(m, size, test) > limit then
                        widest, lines, cur = math.max(widest, lineWidth(m, size, cur)), lines + 1, word
                    else
                        cur = test
                    end
                end
                widest, lines = math.max(widest, lineWidth(m, size, cur)), lines + 1
            else
                widest, lines = math.max(widest, lineWidth(m, size, para)), lines + 1
            end
        end
        return widest, lines * (m.a + m.d) * size
    end
end

local world = recipe.world and require(recipe.world)
local opts = {}
for k, v in pairs(ALL) do opts[k] = v end
opts.character = recipe.character
-- A character set up already (the setup guide stays shut), unless the recipe wants it.
opts.before = function()
    if recipe.before then recipe.before(world) end
    -- A player worth looking at: some health and rage gone.
    stub.units = stub.units or {}
    stub.units.player = stub.units.player or { name = "Tester", class = "WARRIOR", isPlayer = true, level = 20,
        health = 820, maxHealth = 1000, power = 35, maxPower = 100, reaction = 5 }
    if recipe.guide then return end
    _G.DaylightUIDB = _G.DaylightUIDB or {}
    local sv = _G.DaylightUIDB
    sv.installerSeen = 1e9
    sv.characters = sv.characters or {}
    local key = "Tester-" .. tostring(GetRealmName and GetRealmName() or "")   -- the fake game's player
    sv.characters[key] = sv.characters[key] or {}
    sv.characters[key].install = "installed"
end
local DUI = stub.Load(opts)
stub.FireEvent("PLAYER_ENTERING_WORLD")

-- Read straight from the fake game's tables, since in a fight the client's aura
-- buttons refuse every method call from addon code, as in game.
local function shown(w)
    while type(w) == "table" do
        if not rawget(w, "__shown") then return false end
        w = rawget(w, "__parent")
    end
    return true
end
local function scaleOf(w)
    local s = 1
    while type(w) == "table" do
        s = s * (tonumber(rawget(w, "__scale")) or 1)
        if rawget(w, "__ignoreScale") then break end
        w = rawget(w, "__parent")
    end
    return s
end
local function strataOf(w)
    while type(w) == "table" do
        local st = rawget(w, "__strata")
        if st then return st end
        w = rawget(w, "__parent")
    end
    return "MEDIUM"
end

-- Frames pass as in game: timers, the kit's moves, every shown OnUpdate.
local function step(dt)
    stub.RunTimers()
    stub.Advance(dt)
    if DUI.Win and DUI.Win.Followers then DUI.Win.Followers.Tick() end
    local f = EnumerateFrames()
    while f do
        local fn = rawget(f, "__scripts") and f.__scripts.OnUpdate
        if fn and shown(f) then pcall(fn, f, dt) end
        f = EnumerateFrames(f)
    end
end
local function settle(seconds)
    for _ = 1, math.floor(seconds * 30) do step(1 / 30) end
    stub.RunTimers()
end
settle(3)   -- the login fade-in
local GIF = os.getenv("SNAP_GIF")
local crop
if not GIF then
    crop = recipe.open(DUI, arg1, world)
    settle(2)   -- the window's glide and fade
end

-- What the client draws
local ids, nodes, queue, n
local function idOf(w)
    if type(w) == "string" then w = _G[w] end
    if type(w) ~= "table" or not rawget(w, "__type") then return nil end
    if not ids[w] then
        n = n + 1
        ids[w] = n
        queue[#queue + 1] = w
    end
    return ids[w]
end
local function plain(v)
    v = stub.Plain(v)
    if type(v) == "table" then return nil end   -- a value the fake game keeps as an object
    if type(v) == "number" and (v ~= v or v == math.huge or v == -math.huge) then return nil end
    return v
end
local function color(c)
    if type(c) ~= "table" then return nil end
    if c.r then return { plain(c.r), plain(c.g), plain(c.b), plain(c.a) or 1 } end
    return { plain(c[1]) or 1, plain(c[2]) or 1, plain(c[3]) or 1, plain(c[4]) or 1 }
end
local function effAlpha(w)
    local a = 1
    while type(w) == "table" do
        local v = plain(rawget(w, "__alpha"))   -- an animation group's is a flag (true), not an alpha
        a = a * (type(v) == "number" and v or 1)
        if rawget(w, "__ignoreParentAlpha") then break end
        w = rawget(w, "__parent")
    end
    return a
end

local function dump(w)
    local d = { id = ids[w], type = rawget(w, "__type"), name = rawget(w, "__name"), parent = idOf(rawget(w, "__parent")),
                visible = shown(w), alpha = effAlpha(w), scale = scaleOf(w),
                strata = strataOf(w), level = rawget(w, "__level") or 0,
                layer = rawget(w, "__layer"), sublevel = rawget(w, "__sublevel"),
                w = plain(rawget(w, "__w")), h = plain(rawget(w, "__h")), points = {} }
    for _, p in ipairs(rawget(w, "__points") or {}) do
        d.points[#d.points + 1] = { p[1], idOf(p[2]) or false, p[3] or p[1], plain(p[4]) or 0, plain(p[5]) or 0 }
    end
    local tex = rawget(w, "__texture")
    if type(tex) == "string" then d.texture = tex elseif type(tex) == "number" then d.textureId = tex end
    d.color = color(rawget(w, "__color"))
    d.vertex = color(rawget(w, "__vertex"))
    local g = rawget(w, "__gradient")
    if g then d.gradient = { g[1], color(g[2]), color(g[3]) } end
    d.texCoord = rawget(w, "__texCoord")
    d.blend = rawget(w, "__blend")
    d.desaturated = rawget(w, "__desaturated")
    d.atlas = rawget(w, "__atlas")
    d.wrap = rawget(w, "__wrap")
    if rawget(w, "__masks") then
        d.masks = {}
        for _, m in ipairs(w.__masks) do d.masks[#d.masks + 1] = idOf(m) end
    end
    if w.__type == "FontString" or w.__type == "EditBox" then
        local t = stub.Text(w)
        if type(t) ~= "string" then t = rawget(w, "__text") end
        d.text = type(t) == "string" and t or nil
        local f = rawget(w, "__font")
        if f then d.font = { f[1], plain(f[2]), f[3] } end
        d.textColor = color(rawget(w, "__textColor"))
        d.justifyH, d.justifyV = rawget(w, "__justifyH"), rawget(w, "__justifyV")
        d.shadowOffset, d.shadowColor = rawget(w, "__shadowOffset"), color(rawget(w, "__shadowColor"))
        d.wrap = rawget(w, "__wordWrap")
    end
    if w.__type == "StatusBar" then
        d.bar = { min = plain(rawget(w, "__min")) or 0, max = plain(rawget(w, "__max")) or 1,
                  value = plain(rawget(w, "__value")) or 0, orientation = rawget(w, "__orientation"),
                  reverse = rawget(w, "__reverse"), fill = idOf(rawget(w, "__fill")),
                  color = color(rawget(w, "__barColor")) }
        local bt = rawget(w, "__barTexture")
        if type(bt) == "string" then d.bar.texture = bt end
    end
    if w.__type == "ScrollFrame" then
        d.scrollChild = idOf(rawget(w, "__scrollChild"))
        d.vscroll, d.hscroll = plain(rawget(w, "__vScroll")) or 0, plain(rawget(w, "__hScroll")) or 0
    end
    d.clips = rawget(w, "__clips") or w.__type == "ScrollFrame" or nil
    return d
end

-- Every shown widget, then whatever they hang off (anchors, parents), however far.
local function collect()
    ids, nodes, queue, n = {}, {}, {}, 0
    idOf(_G.UIParent)
    local f = EnumerateFrames()
    while f do
        if shown(f) then idOf(f) end
        f = EnumerateFrames(f)
    end
    local i = 1
    while i <= #queue do
        nodes[#nodes + 1] = dump(queue[i])
        i = i + 1
    end
end

-- JSON, by hand (no library in the tests).
local function enc(v, out)
    local t = type(v)
    if t == "nil" then out[#out + 1] = "null"
    elseif t == "boolean" then out[#out + 1] = tostring(v)
    elseif t == "number" then out[#out + 1] = (v ~= v or v == math.huge or v == -math.huge) and "null" or string.format("%.6g", v)
    elseif t == "string" then
        out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
    elseif t == "table" then
        if #v > 0 or next(v) == nil then
            out[#out + 1] = "["
            for k = 1, #v do if k > 1 then out[#out + 1] = "," end; enc(v[k], out) end
            out[#out + 1] = "]"
        else
            out[#out + 1] = "{"
            local first = true
            for k, x in pairs(v) do
                if type(k) == "string" and type(x) ~= "function" then
                    if not first then out[#out + 1] = "," end
                    first = false
                    enc(k, out); out[#out + 1] = ":"; enc(x, out)
                end
            end
            out[#out + 1] = "}"
        end
    else out[#out + 1] = "null" end
end
local function write(path)
    collect()
    local out = {}
    enc({ screen = { stub.physW, stub.physH }, crop = crop and idOf(crop) or nil, nodes = nodes }, out)
    local fh = assert(io.open(path, "w"))
    fh:write(table.concat(out))
    fh:close()
end

if GIF then
    -- A moment before, the opening, then play (if any): one frame per step, 30 a second.
    local count = 0
    local function film(seconds, dt)
        for _ = 1, math.floor(seconds * 30) do
            if dt then step(dt) end
            count = count + 1
            write(string.format("%s/%04d.json", GIF, count))
            dt = 1 / 30
        end
    end
    film(0.2)
    crop = recipe.open(DUI, arg1, world)
    local secs = recipe.film or {}
    film(secs.open or 1.2, 0)
    if recipe.play then
        recipe.play(DUI, arg1, world)
        film(secs.play or 1.2, 0)
    end
    print(GIF .. ": " .. count .. " frames")
else
    local path = "tests/snaps/" .. name .. ".json"
    write(path)
    print(path .. ": " .. #nodes .. " pieces" .. (crop and "" or " (whole screen)"))
end
