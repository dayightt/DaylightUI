local stub = require("stub")

-- The buffs the game's Cooldown Manager hides by default are switched on in its
-- saved layout (CdmSwitch). The game's side is faked the way it behaves: the layout
-- is one string behind C_CooldownViewer.GetLayoutData / SetLayoutData, and the
-- encoder hands back a copy of what went in, as a real round trip through CBOR
-- does, so a table changed after it was written doesn't change what was saved.

local CLASS, SPEC = 1, 1          -- a warrior
local TAG = CLASS * 10 + SPEC

local function deep(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deep(x) end
    return out
end

-- The game: saved = the layout string, writes = how often it was set, and the
-- cooldown ids it lists. 31-33 are buffs hidden by default (33 not learned), 34 a
-- buff shown by default, 41 a bar hidden by default, 11 a cooldown hidden by default.
local game
local function fakeGame(saved)
    local store, n = {}, 0
    game = { saved = saved or "", writes = 0, asked = {}, cvar = "1", cvarSets = 0 }
    _G.C_EncodingUtil = {
        SerializeCBOR = function(t) n = n + 1; store[n] = deep(t); return "cbor" .. n end,
        CompressString = function(s) return "z" .. s end,
        EncodeBase64 = function(s) return "b" .. s end,
        DecodeBase64 = function(s) return string.sub(s, 2) end,
        DecompressString = function(s)
            if string.sub(s, 1, 1) ~= "z" then error("bad deflate") end
            return string.sub(s, 2)
        end,
        DeserializeCBOR = function(s)
            local i = tonumber(string.match(s, "^cbor(%d+)$"))
            if not i or not store[i] then error("bad cbor") end
            return deep(store[i])
        end,
    }
    local sets = { [0] = { 11 }, [2] = { 31, 32, 33, 34 }, [3] = { 41 } }
    local flags = { [11] = 2, [31] = 2, [32] = 2, [33] = 2, [34] = 0, [41] = 2 }
    _G.C_CooldownViewer = {
        GetLayoutData = function() return game.saved end,
        SetLayoutData = function(s)
            assert(type(s) == "string", "SetLayoutData takes a string")
            game.saved, game.writes = s, game.writes + 1
        end,
        GetCooldownViewerCategorySet = function(cat, allowUnlearned)
            game.asked[cat] = allowUnlearned
            return sets[cat] or {}
        end,
        GetCooldownViewerCooldownInfo = function(id)
            if not flags[id] then return nil end
            local cat = (id == 11 and 0) or (id == 41 and 3) or 2
            return { cooldownID = id, spellID = 1000 + id, flags = flags[id], isKnown = id ~= 33, category = cat }
        end,
    }
    _G.C_SpecializationInfo = {
        GetSpecialization = function() return game.spec or SPEC end,
        GetSpecializationInfo = function() return 71, "Arms" end,
    }
    _G.GetClassInfo = function() return "Warrior", "WARRIOR", CLASS end
    _G.C_CVar = {
        GetCVar = function(name) if name == "cooldownViewerEnabled" then return game.cvar end end,
        SetCVar = function(name, v)
            if name == "cooldownViewerEnabled" then game.cvar, game.cvarSets = v, game.cvarSets + 1 end
            return true
        end,
    }
    _G.Enum.CompressionMethod = _G.Enum.CompressionMethod or { Deflate = 0 }
    -- A layout string as the game would have saved it.
    return function(t) return "1|b" .. C_EncodingUtil.CompressString(C_EncodingUtil.SerializeCBOR(t)) end
end

local function saved()
    if game.saved == "" then return nil end
    return C_EncodingUtil.DeserializeCBOR(C_EncodingUtil.DecompressString(C_EncodingUtil.DecodeBase64(string.sub(game.saved, 3))))
end

local keep = {}
local NAMES = { "C_EncodingUtil", "C_CooldownViewer", "C_SpecializationInfo", "GetClassInfo", "C_CVar" }

-- Loads the addon as a warrior with the game faked. opts.saved(encode) gives the
-- string saved before login, opts.off turns Daylight UI's Cooldown Manager off,
-- opts.switchOff one of the layout's per-character switches,
-- opts.switched is what an earlier session recorded (opts.unhid the buffs it took
-- out of a hidden row), opts.placed the cooldown ids placed in a Daylight UI layout
-- of the class, opts.arrived = false leaves the saved data "not here yet" at login.
local function world(opts)
    opts = opts or {}
    for _, name in ipairs(NAMES) do keep[name] = { rawget(_G, name) } end
    local encode
    _G.DaylightUITestDUI = stub.Load({ actionbars = true, login = false, before = function()
        encode = fakeGame()
        stub.units.player = { isPlayer = true, name = "Tester", class = "WARRIOR" }
    end })
    if opts.saved then game.saved = opts.saved(encode) end
    if opts.cvar then game.cvar = opts.cvar end
    local mods = DaylightUIDB.profileData[DaylightUI.DB.DEFAULT].modules
    mods.ActionBars = mods.ActionBars or {}
    if opts.off then mods.ActionBars.cooldowns = false end
    if opts.switchOff then stub.actionbars.CdmData.SetSwitch(opts.switchOff, false) end
    if opts.arrived ~= false then stub.FireEvent("COOLDOWN_VIEWER_DATA_LOADED") end
    if opts.switched then DaylightUI.DB.Character().cdmSwitched = opts.switched end
    if opts.unhid then DaylightUI.DB.Character().cdmUnhid = opts.unhid end
    if opts.learned then
        local own = stub.actionbars.CdmOwn
        own.AuraOf = function(sid) return opts.learned[sid] end
    end
    if opts.placed then
        local pieces = {}
        for _, id in ipairs(opts.placed) do pieces[id] = { x = 0, y = 0, shape = "icon" } end
        stub.actionbars.CdmData.NewProfile("Mine", "WARRIOR", { pieces = pieces, chains = {} })
    end
    stub.FireEvent("PLAYER_LOGIN")
    return stub.actionbars.CdmSwitch, encode
end

local function done()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    for _, name in ipairs(NAMES) do _G[name] = keep[name][1] end
end

T.test("cdm switch: a character on the game's default layout gets one with every hidden buff on", function()
    world()
    local t = saved()
    T.truthy(t, "written at login")
    T.eq(game.writes, 1)
    T.eq(t[1], 5)
    local id = t[2][TAG]
    T.truthy(id and id ~= 0, "the new layout is the one in use")
    T.eq(t[4][id], "Warrior - Arms", "named as the game names one made from its default")
    local rows = t[3][TAG][id][2]
    T.deq(rows[2], { 31, 32, 33 }, "the hidden buffs in Tracked Buffs, a buff not learned yet too")
    T.deq(rows[3], { 41 }, "a hidden bar in Tracked Bars")
    T.eq(rows[0], nil, "a hidden cooldown is left hidden: only buffs")
    T.eq(game.asked[2], true, "unlearned buffs asked for")
    T.deq(DaylightUI.DB.Character().cdmSwitched, { [31] = 2, [32] = 2, [33] = 2, [41] = 3 }, "what was added is kept per character")
    done()
end)

T.test("cdm switch: nothing is written while the saved layout hasn't arrived", function()
    local S = world({ arrived = false })
    T.eq(game.writes, 0, "an empty string before the data arrives may only mean not loaded yet")
    T.eq(S.Run(), nil)
    stub.FireEvent("COOLDOWN_VIEWER_DATA_LOADED")
    T.eq(game.writes, 1, "written the moment it arrives")
    T.deq(saved()[3][TAG][1][2][2], { 31, 32, 33 })
    done()
end)

T.test("cdm switch: a saved layout keeps everything the player set; only buffs with no entry are added", function()
    local S = world({ saved = function(encode)
        return encode({ 5, { [TAG] = 3, [21] = 0 }, {
            [TAG] = {
                [3] = { { 34, 31, 11 }, { [-2] = { 32 }, [3] = { 31 }, [0] = { 11 } }, { [31] = { "an alert" } } },
                [4] = { { 31 } },
            },
            [21] = { [9] = { { 500 }, { [1] = { 500 } } } },
        }, { [3] = "Mine", [4] = "Other", [9] = "A paladin's" } })
    end })
    T.eq(game.writes, 1)
    local t = saved()
    T.deq(t[2], { [TAG] = 3, [21] = 0 }, "the picks untouched")
    T.deq(t[4], { [3] = "Mine", [4] = "Other", [9] = "A paladin's" }, "no layout made")
    local mine = t[3][TAG][3]
    T.deq(mine[1], { 34, 31, 11 }, "the order untouched")
    T.deq(mine[3], { [31] = { "an alert" } }, "the alerts untouched")
    T.deq(mine[2][-2], { 32 }, "a buff the player hid by hand stays hidden")
    T.deq(mine[2][3], { 31, 41 }, "a buff the player made a bar stays one; the hidden bar joins its row")
    T.deq(mine[2][2], { 33 }, "only the buff with no entry is switched on")
    T.deq(mine[2][0], { 11 })
    T.deq(t[3][TAG][4][2][2], { 31, 32, 33 }, "the tag's other layout gets them too, for when the player switches")
    T.deq(t[3][21], { [9] = { { 500 }, { [1] = { 500 } } } }, "another class's layout untouched")
    -- Nothing left to do: the next look writes nothing.
    T.eq(S.Run(), 0)
    T.eq(game.writes, 1, "written once")
    done()
end)

T.test("cdm switch: a buff hidden in the game's layout but placed in Daylight UI's is switched back on", function()
    -- 34 is shown by default and 32 hidden by default; the player hid both by hand
    -- in the game's settings. Only 34 is placed, so only 34 comes back.
    local S = world({ placed = { 34 }, saved = function(encode)
        return encode({ 5, { [TAG] = 1 }, { [TAG] = { [1] = { {}, { [-2] = { 32, 34 } } } } }, { [1] = "Mine" } })
    end })
    local rows = saved()[3][TAG][1][2]
    T.deq(rows[-2], { 32 }, "a hidden buff nobody placed stays hidden")
    T.deq(rows[2], { 34, 31, 33 }, "the placed one is back in its row, so the game makes its icon")
    T.deq(DaylightUI.DB.Character().cdmUnhid, { [34] = -2 }, "where it was is kept, to put it back")
    T.eq(DaylightUI.DB.Character().cdmSwitched[34], 2)
    T.eq(S.Run(), 0, "nothing left to do")
    done()
    -- Daylight UI's Cooldown Manager switched off: it goes back where the player had it.
    world({ off = true, switched = { [31] = 2, [33] = 2, [34] = 2 }, unhid = { [34] = -2 }, saved = function(encode)
        return encode({ 5, { [TAG] = 1 }, { [TAG] = { [1] = { {}, { [-2] = { 32 }, [2] = { 31, 33, 34 } } } } }, { [1] = "Mine" } })
    end })
    rows = saved()[3][TAG][1][2]
    T.deq(rows[-2], { 32, 34 }, "hidden again, as the player left it")
    T.eq(rows[2], nil)
    T.eq(DaylightUI.DB.Character().cdmUnhid, nil)
    done()
end)

-- Improved Stormstrike: the game's item knows only its own spell, and the proc
-- lands as another. Back in the game's row it would never show, so it stays
-- hidden and Daylight UI's aura holder keeps drawing it.
T.test("cdm switch: a placed buff whose aura the game's item can't see stays hidden", function()
    world({ placed = { 34 }, learned = { [1034] = { [2034] = true } }, saved = function(encode)
        return encode({ 5, { [TAG] = 1 }, { [TAG] = { [1] = { {}, { [-2] = { 32, 34 } } } } }, { [1] = "Mine" } })
    end })
    local rows = saved()[3][TAG][1][2]
    T.deq(rows[-2], { 32, 34 }, "left hidden, as the player put it")
    T.eq(DaylightUI.DB.Character().cdmUnhid, nil)
    T.eq(stub.actionbars.CdmRows.DrawnBy(34) ~= "game", true, "the aura holder draws it")
    done()
    -- Already brought out by 2.2.5: it goes back to the hidden row it came from.
    world({ placed = { 34 }, learned = { [1034] = { [2034] = true } },
            switched = { [31] = 2, [33] = 2, [34] = 2 }, unhid = { [34] = -2 }, saved = function(encode)
        return encode({ 5, { [TAG] = 1 }, { [TAG] = { [1] = { {}, { [-2] = { 32 }, [2] = { 31, 33, 34 } } } } }, { [1] = "Mine" } })
    end })
    rows = saved()[3][TAG][1][2]
    T.deq(rows[-2], { 32, 34 }, "hidden again")
    T.deq(rows[2], { 31, 33 }, "the buffs switched on by default stay")
    T.eq(DaylightUI.DB.Character().cdmUnhid, nil)
    T.eq(DaylightUI.DB.Character().cdmSwitched[34], nil)
    T.eq(DaylightUI.DB.Character().cdmSwitched[31], 2)
    done()
    -- An aura the item sees (its own spell) still comes back.
    world({ placed = { 34 }, learned = { [1034] = { [1034] = true } }, saved = function(encode)
        return encode({ 5, { [TAG] = 1 }, { [TAG] = { [1] = { {}, { [-2] = { 32, 34 } } } } }, { [1] = "Mine" } })
    end })
    T.deq(DaylightUI.DB.Character().cdmUnhid, { [34] = -2 })
    done()
end)

-- A spell can list several auras (Vanish lists three), and the learned list grows.
-- One the item sees is enough for the game's icon to show it.
T.test("cdm switch: a placed buff with one aura the item sees and one it can't comes back", function()
    world({ placed = { 34 }, learned = { [1034] = { [1034] = true, [2034] = true } }, saved = function(encode)
        return encode({ 5, { [TAG] = 1 }, { [TAG] = { [1] = { {}, { [-2] = { 32, 34 } } } } }, { [1] = "Mine" } })
    end })
    T.deq(saved()[3][TAG][1][2][-2], { 32 })
    T.deq(DaylightUI.DB.Character().cdmUnhid, { [34] = -2 })
    done()
end)

-- Only a buff whose info is there and fails the check goes back to its hidden row.
T.test("cdm switch: a buff brought out stays out while the game has no answer for it, or its layout isn't this spec's", function()
    -- 35: the game has no info for it yet.
    world({ placed = { 34, 35 }, switched = { [34] = 2, [35] = 2 }, unhid = { [34] = -2, [35] = -2 }, saved = function(encode)
        return encode({ 5, { [TAG] = 1 }, { [TAG] = { [1] = { {}, { [-2] = { 32 }, [2] = { 31, 33, 34, 35 } } } } }, { [1] = "Mine" } })
    end })
    local rows = saved()[3][TAG][1][2]
    T.deq(rows[-2], { 32 }, "nothing sent back")
    T.deq(rows[2], { 31, 33, 34, 35 })
    T.deq(DaylightUI.DB.Character().cdmUnhid, { [34] = -2, [35] = -2 })
    T.eq(DaylightUI.DB.Character().cdmSwitched[35], 2)
    done()
    -- 34 fails the check, but it was brought out in another spec's layout.
    world({ placed = { 34 }, learned = { [1034] = { [2034] = true } },
            switched = { [34] = 2 }, unhid = { [34] = -2 }, saved = function(encode)
        return encode({ 5, { [TAG] = 1, [TAG + 1] = 1 }, { [TAG] = { [1] = { {}, { [-2] = { 32 } } } },
            [TAG + 1] = { [2] = { {}, { [2] = { 34 } } } } }, { [1] = "Mine", [2] = "Other" } })
    end })
    T.deq(saved()[3][TAG + 1][2][2][2], { 34 }, "the other spec's layout is untouched")
    T.deq(DaylightUI.DB.Character().cdmUnhid, { [34] = -2 }, "its record is kept")
    T.eq(DaylightUI.DB.Character().cdmSwitched[34], 2)
    done()
end)

T.test("cdm switch: the game's default picked on purpose gets a layout while there's room, none when all five are used", function()
    world({ saved = function(encode)
        return encode({ 5, { [TAG] = 0 }, { [TAG] = { [2] = { {}, { [2] = { 31 } } } } }, { [2] = "Old" } })
    end })
    local t = saved()
    T.eq(t[2][TAG], 3, "a new layout, picked")
    T.deq(t[3][TAG][3][2][2], { 31, 32, 33 })
    done()
    world({ saved = function(encode)
        local layouts, names = {}, {}
        for i = 1, 5 do layouts[i] = { {} }; names[i] = "L" .. i end
        return encode({ 5, { [TAG] = 0 }, { [TAG] = layouts }, names })
    end })
    T.eq(game.writes, 0, "no room for a layout: left alone")
    done()
end)

T.test("cdm switch: written again as the UI goes down when the game saved over it", function()
    local S, encode = world()
    T.eq(game.writes, 1)
    -- The game's settings window saved its own copy, read before the write landed.
    game.saved = encode({ 5, { [TAG] = 1 }, { [TAG] = { [1] = { { 34 }, { [2] = { 31 } } } } }, { [1] = "Warrior - Arms" } })
    stub.FireEvent("PLAYER_LOGOUT")
    T.eq(game.writes, 2)
    local rows = saved()[3][TAG][1][2]
    T.deq(rows[2], { 31, 32, 33 })
    T.deq(rows[3], { 41 })
    done()
end)

T.test("cdm switch: with Daylight UI's Cooldown Manager off it takes back only what it added", function()
    world({ off = true, switched = { [31] = 2, [32] = 2, [41] = 3 }, saved = function(encode)
        -- 32 was made a bar by the player since; 33 the player switched on themselves.
        return encode({ 5, { [TAG] = 1 }, { [TAG] = { [1] = { {}, { [2] = { 31, 33 }, [3] = { 32, 41 } } } } }, { [1] = "Mine" } })
    end })
    T.eq(game.writes, 1)
    local rows = saved()[3][TAG][1][2]
    T.deq(rows[2], { 33 }, "the player's own stays")
    T.deq(rows[3], { 32 }, "one the player moved stays where they put it")
    T.eq(DaylightUI.DB.Character().cdmSwitched, nil, "nothing left to take back")
    T.eq(game.cvarSets, 0)
    done()
    -- Never switched anything on: the layout isn't touched at all.
    world({ off = true, saved = function(encode)
        return encode({ 5, { [TAG] = 1 }, { [TAG] = { [1] = { {} } } }, { [1] = "Mine" } })
    end })
    T.eq(game.writes, 0)
    done()
end)

T.test("cdm switch: a player who uses the game's layout gets no extra buffs", function()
    for _, key in ipairs({ "on" }) do
        world({ switchOff = key })
        T.eq(game.writes, 0, key .. " off: the game's layout is the player's to see, left as it is")
        done()
        -- Switched on in an earlier session, before the player changed their mind.
        world({ switchOff = key, switched = { [31] = 2 }, saved = function(encode)
            return encode({ 5, { [TAG] = 1 }, { [TAG] = { [1] = { {}, { [2] = { 31, 34 } } } } }, { [1] = "Mine" } })
        end })
        T.deq(saved()[3][TAG][1][2][2], { 34 }, key .. " off: taken back out")
        done()
    end
end)

T.test("cdm switch: a layout it can't read, or no spec, is never written", function()
    world({ saved = function(encode) return encode({ 6, {}, {}, {} }) end })
    T.eq(game.writes, 0, "a newer format")
    done()
    world({ saved = function(encode) return encode({ 3, {}, { [TAG] = { Mine = { {} } } } }) end })
    T.eq(game.writes, 0, "an old format keyed by name")
    done()
    world({ saved = function() return "2|something" end })
    T.eq(game.writes, 0, "another encoding")
    done()
    local S = world({ arrived = false })
    game.spec = nil
    C_SpecializationInfo.GetSpecialization = function() return nil end
    stub.FireEvent("COOLDOWN_VIEWER_DATA_LOADED")
    T.eq(game.writes, 0, "no spec yet")
    T.eq(S.Run(), nil)
    done()
end)

T.test("cdm switch: the game's own Cooldown Manager is switched on at login, and only then", function()
    world({ cvar = "0" })
    T.eq(game.cvar, "1", "off: switched on")
    T.eq(game.cvarSets, 1)
    done()
    world({ cvar = "1" })
    T.eq(game.cvarSets, 0, "already on: not written")
    done()
    world({ cvar = "0", off = true })
    T.eq(game.cvar, "0", "Daylight UI's Cooldown Manager off: the player's choice stands")
    done()
end)
