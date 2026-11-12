local stub = require("stub")

-- Profiles: all settings as one piece, packed as text by the game's encoder.
-- The encoder is faked here with a store behind a token, so a round trip returns
-- an equal table and corrupt text fails like the real one.

local function fakeEncoding()
    local store, n = {}, 0
    local function deep(v)
        if type(v) ~= "table" then return v end
        local o = {}
        for k, x in pairs(v) do o[k] = deep(x) end
        return o
    end
    _G.C_EncodingUtil = {
        SerializeCBOR = function(v) n = n + 1; store[n] = deep(v); return "cbor" .. n end,
        DeserializeCBOR = function(s)
            local i = tonumber(string.match(s, "^cbor(%d+)$"))
            if not i or not store[i] then error("bad cbor") end
            return deep(store[i])
        end,
        CompressString = function(s) return "z" .. s end,
        DecompressString = function(s)
            if string.sub(s, 1, 1) ~= "z" then error("bad deflate") end
            return string.sub(s, 2)
        end,
        EncodeBase64 = function(s) return "b" .. s end,
        DecodeBase64 = function(s) return string.sub(s, 2) end,
    }
end

local function login()
    local DUI = stub.Load({ module = true, before = fakeEncoding })
    stub.RunTimers()
    return DUI
end

T.test("profiles: exported as !DUI1_ text and read back to the same settings, only what differs from the defaults", function()
    local DUI = login()
    DUI:Set("general", "borderPx", 3)
    DUI:Set("UnitFrames", "swing.height", 30)
    DUI.DB.Positions()["unitframes.player"] = { 10, 20 }
    local P = DUI.Profiles
    local text = P.Encode(P.Snapshot())
    T.eq(string.sub(text, 1, 6), "!DUI1_", "marked as ours")
    local p = P.Decode("  " .. text .. "\n")
    T.truthy(p, "read back, whitespace and all")
    T.eq(p.general.borderPx, 3)
    T.isnil(p.general.softness, "defaults left out")
    T.eq(p.modules.UnitFrames.swing.height, 30)
    T.isnil(p.modules.UnitFrames.swing.width, "a module's defaults left out too")
    T.eq(p.positions["unitframes.player"][2], 20)
    T.truthy(string.find(P.Summary(p), "Unit Frames", 1, true), "said what it holds")
end)

T.test("profiles: a shared one leaves out window spots tied to one screen; an import keeps yours", function()
    local DUI = stub.Load({ module = true, skins = true, before = fakeEncoding })
    stub.RunTimers()
    local P, mods = DUI.Profiles, DUI.DB.Active().modules
    mods.Book.spot, mods.Inspect.spot = { 100, 200 }, { 300, 400 }
    mods.Skins.mapSpot, mods.Skins.mapScale = { 50, 60 }, 1.2
    local p = P.Decode(P.Encode(P.Snapshot()))
    T.isnil(p.modules.Book.spot, "spellbook")
    T.isnil(p.modules.Inspect.spot, "inspect")
    T.isnil(p.modules.Skins.mapSpot, "world map")
    T.eq(p.modules.Skins.mapScale, 1.2, "the map's size isn't the screen's: shared")
    mods.Book.spot = { 7, 8 }
    local made = DUI.DB.Root().profileData[assert(P.Create("Theirs", p))]
    T.eq(made.modules.Book.spot[1], 7, "your own spot")
end)

T.test("profiles: bad text is refused with why", function()
    local DUI = login()
    local P = DUI.Profiles
    local _, why = P.Decode("hello")
    T.truthy(string.find(why, "isn't a DaylightUI profile", 1, true))
    _, why = P.Decode("!DUI1_bxnope")
    T.truthy(string.find(why, "damaged", 1, true), "cut off or mangled")
    local text = P.Encode({ v = 99 })
    _, why = P.Decode(text)
    T.truthy(string.find(why, "newer", 1, true), "from a newer version")
end)

T.test("profiles: an import drops damaged positions and keeps the good ones", function()
    local DUI = login()
    local P = DUI.Profiles
    local text = P.Encode({ v = 1, positions = {
        good = { 10, -20 }, word = "x", short = { 1 }, letters = { "a", 2 },
        nan = { 1, 0 / 0 }, inf = { math.huge, 2 },
    } })
    local p = P.Decode(text)
    T.truthy(p, "still imports")
    T.eq(p.positions.good[1], 10); T.eq(p.positions.good[2], -20)
    for _, k in ipairs({ "word", "short", "letters", "nan", "inf" }) do
        T.isnil(p.positions[k], k .. " dropped")
    end
end)

-- A hand-edited or damaged string. A setting of the wrong kind would error in
-- every module that reads it, e.g. math on "1.2".
T.test("profiles: an import drops settings of the wrong kind and keeps the rest", function()
    local DUI = login()
    local P = DUI.Profiles
    local p = P.Decode(P.Encode({ v = 1,
        general = { scale = "1.2", borderPx = 3, lastNames = "yes", gradients = { invert = "no", palette = "daylight" } },
        modules = { UnitFrames = { swing = { height = "30", width = 120 }, notASetting = "kept" } } }))
    T.truthy(p, "still imports")
    local made = DUI.DB.Root().profileData[assert(P.Create("Hand-edited", p))]
    local G, UF = DUI.DB.GENERAL_DEFAULTS, DUI:GetModule("UnitFrames").defaults
    T.eq(made.general.scale, G.scale, "a word where a number goes: the default")
    T.eq(made.general.borderPx, 3)
    T.eq(type(made.general.lastNames), "table", "a word where a table goes: the default")
    T.eq(made.general.lastNames.player, G.lastNames.player)
    T.eq(made.general.gradients.invert, G.gradients.invert, "nested too")
    T.eq(made.general.gradients.palette, "daylight")
    T.eq(made.modules.UnitFrames.swing.height, UF.swing.height, "a module's setting too")
    T.eq(made.modules.UnitFrames.swing.width, 120)
    T.eq(made.modules.UnitFrames.notASetting, "kept", "a key with no default is left alone")
end)

-- Replace refills the profile in use in place. The modules get new settings
-- tables, and later changes must land in those (setup guide Finish, then
-- "Later" on the reload prompt).
T.test("profiles: after the profile in use is replaced, module changes go into it", function()
    local DUI = login()
    local P, DB = DUI.Profiles, DUI.DB
    P.Replace(DB.ActiveName(), { general = {}, modules = { UnitFrames = { swing = { height = 25 } } }, positions = {} })
    T.eq(DUI:Get("UnitFrames", "swing.height"), 25, "reads the new settings")
    DUI:Set("UnitFrames", "swing.height", 31)
    T.eq(DB.Active().modules.UnitFrames.swing.height, 31, "the change is in the saved profile")
    T.truthy(DB.Active().modules.UnitFrames.swing.width ~= nil, "defaults filled in")
end)


-- Dual spec as the game has it: how many talent sets, and the one in use.
local function talents(sets, active)
    _G.GetNumSpecGroups = function() return sets end
    _G.C_SpecializationInfo = { GetActiveSpecGroup = function() return stub.activeSpec end }
    stub.activeSpec = active
end

-- A reload: the saved table as it was, loaded again.
local function reload()
    stub.FireEvent("PLAYER_LOGOUT")
    local saved = DaylightUIDB
    local DUI = stub.Load({ module = true, before = function()
        fakeEncoding()
        DaylightUIDB = saved
    end })
    stub.RunTimers()
    return DUI
end

local function me()
    stub.units.player = { name = "Kaladin", isPlayer = true, class = "WARRIOR" }
end

T.test("profiles: plain fills switch to gradients once", function()
    talents(1, 1)
    local DUI = stub.Load({ module = true, before = function()
        fakeEncoding()
        me()
        DaylightUIDB = { version = 2, profileData = { Default = { modules = {
            UnitFrames = { colors = { health = "class", power = "custom" }, swing = { pairGradient = false } },
            InfoPanel = { meter = { gradient = false } } } } } }
    end })
    T.eq(DUI:Get("UnitFrames", "colors.health"), "classGradient")
    T.eq(DUI:Get("UnitFrames", "colors.power"), "custom")
    T.eq(DUI:Get("UnitFrames", "swing.fill"), "pair", "then the Fill style step keeps the pair")
    T.eq(DaylightUIDB.profileData[DUI.DB.DEFAULT].modules.InfoPanel.meter.gradient, true)
    T.eq(DaylightUIDB.profileData[DUI.DB.DEFAULT].gradients1, true)
    DUI:Set("UnitFrames", "colors.health", "class")
    DUI = reload()
    T.eq(DUI:Get("UnitFrames", "colors.health"), "class", "runs once")
end)

T.test("profiles: a new copy keeps the local font as picked; a shared or blank one gets this client's", function()
    local real = _G.GetLocale
    _G.GetLocale = function() return "koKR" end
    local DUI = login()
    T.eq(DUI.DB.General().localFont, true, "on for a Korean client")
    DUI:Set("general", "localFont", false)
    T.eq(DUI.Profiles.Create("Copy"), "Copy")
    T.eq(DUI.Profiles.Create("Shared", { general = {}, modules = {}, positions = {} }), "Shared")
    T.eq(DaylightUIDB.profileData.Shared.general.localFont, true, "on at once, not only after a reload")
    reload()
    T.falsy(DaylightUIDB.profileData.Copy.general.localFont, "turned off, stays off after a reload")
    T.eq(DaylightUIDB.profileData.Shared.general.localFont, true)
    _G.GetLocale = real
end)

-- Saved from before Default and DPS/Tank became one.
local function oldSave(pd, chars)
    talents(1, 1)
    return stub.Load({ module = true, before = function()
        fakeEncoding()
        me()
        DaylightUIDB = { version = 2, profileData = pd, characters = chars }
    end })
end

T.test("profiles: an old Default alone becomes DPS/Tank, every choice of it with it", function()
    -- A guide cut short left a preview (accent) in Default to undo.
    local DUI = oldSave({ Default = { general = { borderPx = 3, accent = "class" } }, Healer = {} }, {
        ["Kaladin-"] = { profile = "Default", installDraft = { profile = "Default", values = { ["general\taccent"] = "gold" } } },
        ["Other-Realm"] = { specProfiles = { "Healer", "Default" } },
    })
    local pd, chars = DaylightUIDB.profileData, DaylightUIDB.characters
    T.isnil(pd.Default, "no Default left")
    T.eq(pd["DPS/Tank"].general.borderPx, 3, "its settings are DPS/Tank's now")
    T.eq(DUI.DB.ActiveName(), "DPS/Tank")
    T.eq(chars["Kaladin-"].profile, "DPS/Tank")
    T.eq(pd["DPS/Tank"].general.accent, "gold", "a guide cut short is undone in it")
    T.eq(chars["Other-Realm"].specProfiles[2], "DPS/Tank")
    T.eq(chars["Other-Realm"].specProfiles[1], "Healer", "other choices as they were")
    T.deq(DUI.Profiles.Names(), { "DPS/Tank", "Healer" })
end)

T.test("profiles: an old Default next to DPS/Tank goes when nobody chose it", function()
    local DUI = oldSave({ Default = { general = { borderPx = 3 } }, ["DPS/Tank"] = { general = { borderPx = 5 } } },
        { ["Kaladin-"] = { profile = "DPS/Tank" } })
    T.isnil(DaylightUIDB.profileData.Default)
    T.eq(DUI:Get("general", "borderPx"), 5, "DPS/Tank as it was")
    T.deq(DUI.Profiles.Names(), { "DPS/Tank" })
end)

T.test("profiles: an old Default next to DPS/Tank stays, as a plain profile, for a character that chose it", function()
    local DUI = oldSave({ Default = { general = { borderPx = 3 } }, ["DPS/Tank"] = { general = { borderPx = 5 } } },
        { ["Kaladin-"] = { profile = "Default" } })
    T.eq(DUI.DB.ActiveName(), "Default", "still on it")
    T.eq(DUI:Get("general", "borderPx"), 3, "as it was")
    T.deq(DUI.Profiles.Names(), { "DPS/Tank", "Default" })
    DUI.Profiles.Choose("character", "DPS/Tank")
    DUI = reload()
    T.truthy(DUI.Profiles.Delete("Default"), "deletable like any other")
end)

T.test("profiles: the merge runs once; a new profile called Default is just a profile", function()
    local DUI = oldSave({ ["DPS/Tank"] = {} }, {})
    T.eq(DUI.Profiles.Create("Default"), "Default")
    DUI = reload()
    T.truthy(DaylightUIDB.profileData.Default, "kept")
    T.deq(DUI.Profiles.Names(), { "DPS/Tank", "Default" })
end)

T.test("profiles: a fresh install has no profile until it's installed", function()
    talents(1, 1)
    me()
    local DUI = login()
    T.eq(DUI.DB.ActiveName(), "DPS/Tank", "runs on an unsaved stand-in")
    T.deq(DUI.Profiles.Names(), {}, "nothing listed")
    DUI:Set("general", "softness", 0.5)
    stub.FireEvent("PLAYER_LOGOUT")
    T.isnil(next(DaylightUIDB.profileData), "nothing saved")
    DUI = reload()
    T.truthy(DaylightUIDB.profileData["DPS/Tank"].unsaved, "a new stand-in")
    T.isnil(DaylightUIDB.profileData.Default)
    DUI.Profiles.AddPreset("DPS/Tank")
    T.deq(DUI.Profiles.Names(), { "DPS/Tank" }, "installed")
    DUI = reload()
    T.truthy(DaylightUIDB.profileData["DPS/Tank"], "kept now")
end)

-- A player report: moved frames went back at every login. Nothing is saved
-- before the setup guide is finished, so unlock mode and the options say so.
T.test("profiles: unsaved, unlock mode and the options window offer to finish the setup guide", function()
    talents(1, 1)
    me()
    local DUI = login()
    T.truthy(DUI.DB.Unsaved())
    DUI.Movers.Unlock()
    T.truthy(DUI.Movers.SetupButton():IsShown(), "under the Lock bar")
    T.truthy(stub.ChatContains("/dui install"), "and said in chat")
    DUI.OptionsPanel.Show("home")
    local nav = DUI.OptionsPanel.Nav()
    T.truthy(nav.setup:IsShown(), "over Unlock frames")
    local opened = 0
    local show = DUI.Installer.Show
    DUI.Installer.Show = function() opened = opened + 1 end
    nav.setup:GetScript("OnClick")(nav.setup)
    DUI.Installer.Show = show
    T.eq(opened, 1, "opens the guide")
    T.falsy(DUI.Movers.unlocked, "unlock mode ended for it")
    DUI.Profiles.AddPreset("DPS/Tank")
    T.falsy(DUI.DB.Unsaved())
    DUI.Movers.Unlock()
    T.falsy(DUI.Movers.SetupButton():IsShown(), "saved: gone")
    DUI.Movers.Lock()
    DUI.OptionsPanel.Show("home")
    T.falsy(nav.setup:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("profiles: DPS/Tank can be deleted; its characters go to the first one left", function()
    talents(1, 1)
    me()
    local DUI = login()
    local P = DUI.Profiles
    P.AddPreset("DPS/Tank")
    P.Create("Zed")
    P.Create("Bee")
    local ok = P.Delete("DPS/Tank")
    T.falsy(ok, "not the one in use")
    P.Assign("character", "Zed")
    DUI = reload()
    P = DUI.Profiles
    T.truthy(P.Delete("DPS/Tank"))
    T.deq(P.Names(), { "Bee", "Zed" })
    T.truthy(P.Delete("Zed") == false, "Zed is in use")
    P.Assign("character", nil)
    DUI = reload()
    T.eq(DUI.DB.ActiveName(), "Bee", "the first one left")
    T.isnil(DaylightUIDB.profileData["DPS/Tank"], "not made again")
end)

T.test("profiles: a new profile keeps its plain fills after a reload", function()
    talents(1, 1)
    local DUI = stub.Load({ module = true, before = function() fakeEncoding(); me() end })
    DUI:Set("UnitFrames", "colors.health", "class")
    local made = DUI.Profiles.Create("Plain")
    T.eq(DaylightUIDB.profileData[made].modules.UnitFrames.colors.health, "class")
    DUI = reload()
    T.eq(DaylightUIDB.profileData[made].modules.UnitFrames.colors.health, "class", "not swapped to gradient")
end)

T.test("profiles: settings from before profiles become DPS/Tank; saved ones become profiles", function()
    talents(1, 1)
    local DUI = stub.Load({ module = true, before = function()
        fakeEncoding()
        me()
        DaylightUIDB = {
            version = 1,
            general = { borderPx = 3 },
            modules = { UnitFrames = { swing = { height = 12 } }, Buffs = { history = { a = 1 } } },
            positions = { ["unitframes.player"] = { 1, 2 } },
            profiles = { Raid = { v = 1, general = { borderPx = 5 }, modules = {}, positions = {} } },
            characters = { ["Kaladin-"] = "installed" },
        }
    end })
    local pd = DaylightUIDB.profileData
    T.eq(DUI.DB.ActiveName(), "DPS/Tank")
    T.eq(DUI:Get("general", "borderPx"), 3, "the settings kept")
    T.eq(DUI:Get("UnitFrames", "swing.height"), 12)
    T.eq(DUI.DB.Positions()["unitframes.player"][2], 2)
    T.eq(pd.Raid.general.borderPx, 5, "the saved one, a profile now")
    T.eq(pd.Raid.modules.Buffs.history.a, 1, "with what's learned as you play")
    T.isnil(DaylightUIDB.general, "the old places are gone")
    T.isnil(DaylightUIDB.profiles)
    T.eq(DUI.Installer.State(), "installed", "the installer's answer kept")
    T.eq(DaylightUIDB.version, 2)
end)

T.test("profiles: a new one copies the one in use; changes go only into the one in use", function()
    talents(1, 1)
    me()
    local DUI = login()
    local P = DUI.Profiles
    P.AddPreset("DPS/Tank")
    DUI:Set("UnitFrames", "swing.height", 30)
    T.eq(P.Create("Healer"), "Healer")
    T.eq(P.Names()[1], "DPS/Tank", "DPS/Tank first")
    T.eq(P.Names()[2], "Healer")
    T.eq(DaylightUIDB.profileData.Healer.modules.UnitFrames.swing.height, 30, "a copy")
    DUI:Set("UnitFrames", "swing.height", 12)
    T.eq(DaylightUIDB.profileData.Healer.modules.UnitFrames.swing.height, 30, "the copy unchanged")
    local _, why = P.Create("healer")
    T.truthy(string.find(why, "already", 1, true), "names are unique, whatever the case")
    _, why = P.Create("  ")
    T.truthy(string.find(why, "name", 1, true))
end)

T.test("profiles: choosing one for this character asks to reload, and the reload uses it", function()
    talents(1, 1)
    me()
    local DUI = login()
    local P = DUI.Profiles
    P.AddPreset("DPS/Tank")
    P.Create("Healer")
    stub.popup = nil
    P.Choose("character", "Healer")
    T.eq(stub.popup and stub.popup.which, "DAYLIGHTUI_PROFILE", "asked")
    T.eq(stub.popup.data, "Healer")
    T.eq(DUI.DB.ActiveName(), "DPS/Tank", "not until the reload")
    StaticPopupDialogs.DAYLIGHTUI_PROFILE.OnAccept(nil, stub.popup.data)
    stub.RunTimers()
    T.truthy(stub.reloaded, "reloaded")
    DUI = reload()
    T.eq(DUI.DB.ActiveName(), "Healer", "on it now")
    DUI:Set("UnitFrames", "swing.height", 44)
    T.eq(DaylightUIDB.profileData.Healer.modules.UnitFrames.swing.height, 44, "changes go into it")
    T.falsy(DUI.DB.Fill(DaylightUIDB.profileData[DUI.DB.DEFAULT]).modules.UnitFrames.swing.height == 44)
    -- Choosing the one in use again asks nothing.
    stub.popup = nil
    P = DUI.Profiles
    P.Choose("character", "Healer")
    T.isnil(stub.popup)
end)

T.test("profiles: with dual spec each talent set has its own, and swapping asks to switch", function()
    talents(2, 1)
    me()
    local DUI = login()
    local P = DUI.Profiles
    P.AddPreset("DPS/Tank")
    P.Create("Healer")
    P.Choose(1, "DPS/Tank")
    P.Choose(2, "Healer")
    stub.popup = nil
    stub.activeSpec = 2
    stub.FireEvent("ACTIVE_TALENT_GROUP_CHANGED", 2, 1)
    T.eq(stub.popup and stub.popup.data, "Healer", "these talents' profile offered")
    T.truthy(string.find(stub.popup.text, "talents", 1, true))
    -- "Later": the next login picks it by the talents anyway.
    DUI = reload()
    T.eq(DUI.DB.ActiveName(), "Healer")
    stub.activeSpec = 1
    DUI = reload()
    T.eq(DUI.DB.ActiveName(), "DPS/Tank")
end)

-- The game's controller UI on or off, as C_InputInterfaceStyle reports it
-- (see InputUtil.IsGamepadUIEnabled).
local function padUI(on)
    Enum.InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 }
    _G.C_InputInterfaceStyle = { GetCurrentStyle = function() return on and 1 or 0 end }
end

T.test("profiles: a controller mode profile is used while the controller UI is on, and switching asks", function()
    talents(2, 1)
    me()
    padUI(false)
    local DUI = login()
    local P = DUI.Profiles
    P.AddPreset("DPS/Tank")
    P.Create("Couch")
    T.eq(P.Chosen("pad"), P.NONE, "none at first")
    stub.popup = nil
    P.Choose("pad", "Couch")
    T.isnil(stub.popup, "not in use while the controller UI is off")
    T.eq(P.UsersOf("Couch")[1] ~= nil, true, "counted as chosen")
    -- The game turns its controller UI on: offered, and taken without an Edit Mode layout.
    padUI(true)
    stub.FireEvent("INPUT_DEVICE_INTERFACE_TRANSITION", 1, 0)
    T.eq(stub.popup and stub.popup.data, "Couch", "offered")
    T.truthy(string.find(stub.popup.text, "Controller", 1, true))
    stub.reloaded = nil
    StaticPopupDialogs.DAYLIGHTUI_PROFILE.OnAccept(nil, stub.popup.data)
    T.truthy(stub.reloaded, "reloaded at once")
    DUI = reload()
    T.eq(DUI.DB.ActiveName(), "Couch", "over the talent set's")
    -- And off again: back to the talents' own.
    padUI(false)
    stub.popup = nil
    stub.FireEvent("INPUT_DEVICE_INTERFACE_TRANSITION", 0, 1)
    T.eq(stub.popup and stub.popup.data, "DPS/Tank", "back offered")
    DUI = reload()
    T.eq(DUI.DB.ActiveName(), "DPS/Tank")
    -- Renamed and deleted with the others; None turns it off.
    T.truthy(DUI.Profiles.Rename("Couch", "Sofa"))
    T.eq(DUI.Profiles.Chosen("pad"), "Sofa")
    DUI.Profiles.Choose("pad", DUI.Profiles.NONE)
    T.isnil(DUI.DB.Character().padProfile)
    T.eq(DUI.Profiles.Chosen("pad"), DUI.Profiles.NONE)
    _G.C_InputInterfaceStyle = nil
end)

T.test("profiles: rename and delete keep every character's choice sensible", function()
    talents(1, 1)
    me()
    local DUI = login()
    local P = DUI.Profiles
    P.Create("Healer")
    P.Create("Tank")
    DaylightUIDB.characters["Other-Realm"] = { profile = "Tank" }
    T.truthy(P.Rename("Tank", "Prot"))
    T.eq(DaylightUIDB.characters["Other-Realm"].profile, "Prot", "follows the rename")
    T.eq(P.UsersOf("Prot")[1], "Other-Realm")
    T.falsy(P.Rename("DPS/Tank", "Main"), "DPS/Tank keeps its name")
    T.falsy(P.Delete("DPS/Tank"), "DPS/Tank stays")
    T.truthy(P.Delete("Prot"))
    T.isnil(DaylightUIDB.characters["Other-Realm"].profile, "back to DPS/Tank")
    T.isnil(DaylightUIDB.profileData.Prot)
    -- The one in use can't go.
    P.Choose("character", "Healer")
    DUI = reload()
    T.falsy(DUI.Profiles.Delete("Healer"), "in use")
    T.truthy(DUI.Profiles.Rename("Healer", "Mender"), "renamed while in use")
    T.eq(DUI.DB.ActiveName(), "Mender")
    T.eq(DUI.Profiles.Chosen("character"), "Mender")
end)

T.test("profiles: a rename that only changes case is allowed and carries everything", function()
    talents(1, 1)
    me()
    local DUI = login()
    local P = DUI.Profiles
    P.Create("healer")
    P.Create("Tank")
    DaylightUIDB.characters["Other-Realm"] = { profile = "healer", specProfiles = { "healer", "Tank" } }
    local ok, why = P.Rename("healer", "Healer")
    T.truthy(ok, why)
    T.truthy(DaylightUIDB.profileData.Healer, "under the new name")
    T.isnil(DaylightUIDB.profileData.healer, "not under the old")
    local c = DaylightUIDB.characters["Other-Realm"]
    T.eq(c.profile, "Healer"); T.eq(c.specProfiles[1], "Healer"); T.eq(c.specProfiles[2], "Tank")
    T.falsy(P.Rename("Healer", "tank"), "a clash with another profile is still refused")
    T.truthy(P.Rename("Healer", "Healer"), "the same name is a no-op")
    T.truthy(DaylightUIDB.profileData.Healer, "and keeps it")
    -- In use: the active name follows.
    P.Choose("character", "Healer")
    DUI = reload()
    T.truthy(DUI.Profiles.Rename("Healer", "HEALER"))
    T.eq(DUI.DB.ActiveName(), "HEALER")
    T.eq(DUI.Profiles.Chosen("character"), "HEALER")
end)

T.test("profiles: one deleted from under a character falls back to DPS/Tank", function()
    talents(1, 1)
    me()
    login()
    DaylightUIDB.characters[DaylightUI.DB.CharKey()] = { profile = "Gone" }
    local DUI = reload()
    T.eq(DUI.DB.ActiveName(), "DPS/Tank")
end)

T.test("profiles: logout strips defaults in every profile", function()
    talents(1, 1)
    me()
    local DUI = login()
    DUI.Profiles.Create("Healer")
    stub.FireEvent("PLAYER_LOGOUT")
    T.isnil(DaylightUIDB.profileData.Healer.general.softness)
    T.isnil(DaylightUIDB.profileData[DUI.DB.DEFAULT], "the unsaved stand-in isn't saved")
end)

T.test("profiles: importing makes a new profile, chosen for this character", function()
    talents(1, 1)
    me()
    local DUI = login()
    local P = DUI.Profiles
    DUI:Set("UnitFrames", "swing.height", 30)
    local text = P.Encode(P.Snapshot())
    DUI:Set("UnitFrames", "swing.height", 12)
    stub.popup = nil
    P.ShowImport()
    local box = _G.DaylightUIProfileBox
    box.edit:SetText(text)
    box.name:SetText("Theirs")
    box.go:GetScript("OnClick")()
    T.eq(DaylightUIDB.profileData.Theirs.modules.UnitFrames.swing.height, 30, "the shared settings")
    T.eq(DUI:Get("UnitFrames", "swing.height"), 12, "yours untouched")
    T.eq(P.Chosen("character"), "Theirs")
    T.eq(stub.popup and stub.popup.which, "DAYLIGHTUI_PROFILE", "asked to reload into it")
end)

T.test("profiles: the share window: export shows the text; import checks it as it's pasted", function()
    local DUI = login()
    local P = DUI.Profiles
    P.ShowExport()
    local box = _G.DaylightUIProfileBox
    T.truthy(box:IsShown())
    T.eq(string.sub(box.edit.__text, 1, 6), "!DUI1_", "the profile to copy")
    T.eq(box:GetFrameStrata(), "FULLSCREEN_DIALOG", "over the options window")
    T.truthy(string.find(box.edit.__text, "\n", 1, true) or #box.edit.__text <= DUI.Profiles.WRAP, "in lines, inside the box")
    local text = box.edit.__text
    P.ShowImport()
    T.eq(box.edit.__text, "", "an empty box to paste into")
    box.edit:SetText("nonsense")
    T.truthy(string.find(box.status.__text, "Can't import", 1, true))
    box.edit:SetText(text)
    T.truthy(string.find(box.status.__text, "Settings for", 1, true), "what it holds, before anything's changed")
    box.go:GetScript("OnClick")()
    T.truthy(box:IsShown(), "not without a name")
    T.truthy(string.find(box.status.__text, "name", 1, true), "asked for one")
    box.name:SetText("Their UI")
    box.go:GetScript("OnClick")()
    T.falsy(box:IsShown(), "imported")
    T.deq(DUI.Profiles.Names(), { "Their UI" }, "kept under its name")
end)

T.test("profiles: if the talents weren't known at login, entering the world asks", function()
    talents(2, nil)             -- not known yet at login: the last one stands in
    local DUI = login()
    DUI.Profiles.Create("Healer")
    DUI.Profiles.Choose(2, "Healer")
    stub.popup = nil
    stub.activeSpec = 2
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    T.eq(stub.popup and stub.popup.data, "Healer")
    stub.popup = nil
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    T.isnil(stub.popup, "once")
end)

T.test("characters: one entry each, by first and last name and realm; old keys folded in", function()
    talents(1, 1)
    local DUI = stub.Load({ module = true, before = function()
        fakeEncoding()
        _G.GetRealmName = function() return "Classic Beta PvE 2" end
        stub.units.player = { name = "Kaladin", lastName = "Stormblessed", isPlayer = true, class = "WARRIOR" }
        DaylightUIDB = { version = 2, profileData = { Default = {}, Healer = {} }, characters = {
            ["Kaladin-Stormblessed"] = { profile = "Healer", install = "installed" },
            ["Unknown-Classic Beta PvE 2"] = { lastSpec = 1 },
        } }
    end })
    local chars = DaylightUIDB.characters
    T.eq(DUI.DB.CharKey(), "Kaladin Stormblessed-Classic Beta PvE 2")
    T.eq(chars["Kaladin Stormblessed-Classic Beta PvE 2"].profile, "Healer", "the old entry's choice kept")
    T.isnil(chars["Kaladin-Stormblessed"], "and the old entry gone")
    T.isnil(chars["Unknown-Classic Beta PvE 2"], "no entries for no one")
    T.eq(DUI.DB.ActiveName(), "Healer", "on the profile it chose")
    T.eq(DUI.DB.Character("Kaladin-Classic Beta PvE 2"), DUI.DB.Character(), "a first-name key (DaylightMogul's) still finds you")
    _G.GetRealmName = nil
end)

-- Two characters with the same first name (Boopy Dadoopy, Boopy Mcdoopy) used to
-- share one "Boopy-Realm" entry: each saw the other's bags and bank.
T.test("characters: two with the same first name each keep their own bags; settings carry to both", function()
    talents(1, 1)
    local function as(last, class)
        local saved = DaylightUIDB
        local DUI = stub.Load({ module = true, before = function()
            fakeEncoding()
            _G.GetRealmName = function() return "Forever" end
            stub.units.player = { name = "Boopy", lastName = last, isPlayer = true, class = class }
            DaylightUIDB = saved
        end })
        stub.RunTimers()
        return DUI
    end
    DaylightUIDB = { version = 2, profileData = { Default = {}, Healer = {} }, characters = {
        ["Boopy-Forever"] = { profile = "Healer", install = "installed", money = 500, class = "PRIEST",
            mailName = "Boopy Mcdoopy", inventory = { class = "PRIEST", money = 500, bags = {} } },
    } }
    local DUI = as("Dadoopy", "MAGE")
    local chars = DaylightUIDB.characters
    local mine = chars["Boopy Dadoopy-Forever"]
    T.eq(DUI.DB.CharKey(), "Boopy Dadoopy-Forever")
    T.eq(mine.profile, "Healer", "the shared setup carries over")
    T.eq(mine.install, "installed", "no setup guide again")
    T.isnil(mine.inventory, "Mcdoopy's bags aren't taken")
    T.eq(chars["Boopy-Forever"].inventory.class, "PRIEST", "they stay for Mcdoopy")
    DUI.DB.Character().money = 100   -- as the gold text saves it
    stub.FireEvent("PLAYER_LOGOUT")

    DUI = as("Mcdoopy", "PRIEST")
    local his = chars["Boopy Mcdoopy-Forever"]
    T.eq(his.inventory and his.inventory.class, "PRIEST", "Mcdoopy takes his own bags")
    T.eq(his.money, 500, "and gold")
    T.eq(his.profile, "Healer")
    T.isnil(chars["Boopy-Forever"].inventory, "nothing of his left on the old entry")
    T.isnil(chars["Boopy-Forever"].money, "so the gold isn't counted twice")
    local names = {}
    for _, c in ipairs(DUI.Alts.List()) do names[#names + 1] = c.name end
    T.deq(names, { "Boopy Dadoopy" }, "each listed by full name, no stray Boopy")
    _G.GetRealmName = nil
end)

T.test("characters: while the game doesn't know the name, nothing is saved under it", function()
    local DUI = login()
    local before = 0
    for _ in pairs(DaylightUIDB.characters) do before = before + 1 end
    stub.units.player = { name = "Unknown" }
    DUI.DB.Character().profile = "X"
    local after = 0
    for _ in pairs(DaylightUIDB.characters) do after = after + 1 end
    T.eq(after, before)
end)

T.test("profiles: renaming DPS/Tank leaves the standard layout's name alone", function()
    local DUI = login()
    T.eq(DUI.Profiles.AddPreset("DPS/Tank"), "DPS/Tank")
    local ok = DUI.EditMode.RenameLayout("DPS/Tank", "Mine")
    T.falsy(ok, "the standard layout")
end)

T.test("profiles: copying action bar positions only touches actionbars.* keys", function()
    local DUI = login()
    local P = DUI.Profiles
    P.Create("Mine")
    T.falsy(P.HasBarPositions("Mine"), "nothing moved yet")
    DaylightUIDB.profileData.Mine.positions = { ["actionbars.main"] = { 10, 20 }, ["unitframes.player"] = { 1, 2 } }
    T.truthy(P.HasBarPositions("Mine"))
    P.Create("Other")
    P.CopyActionBarPositions("Mine", "Other")
    local pos = DaylightUIDB.profileData.Other.positions
    T.eq(pos["actionbars.main"][2], 20, "the bar came along")
    T.isnil(pos["unitframes.player"], "nothing else did")
end)

T.test("profiles: a ready-made profile offers to bring the current one's action bars, once", function()
    talents(1, 1)
    me()
    local DUI = login()
    local P = DUI.Profiles
    -- DPS/Tank is the standard profile, there already: nothing to offer.
    stub.popup = nil
    P.AddPresetOffering("DPS/Tank")
    T.isnil(stub.popup, "nothing made, so nothing to bring")
    -- Switch to a profile of our own with a moved bar.
    P.Create("Mine")
    P.Choose("character", "Mine")
    StaticPopupDialogs.DAYLIGHTUI_PROFILE.OnAccept(nil, stub.popup.data)
    stub.RunTimers()
    DUI = reload()
    P = DUI.Profiles
    DUI.DB.Positions()["actionbars.main"] = { 10, 20 }
    stub.popup = nil
    local made = P.AddPresetOffering("Healer")
    T.eq(made, "Healer")
    T.eq(stub.popup and stub.popup.which, "DAYLIGHTUI_PROFILE_BARS", "asked, since Mine moved a bar")
    T.isnil(DaylightUIDB.profileData.Healer.positions["actionbars.main"], "not yet")
    StaticPopupDialogs.DAYLIGHTUI_PROFILE_BARS.OnAccept(nil, stub.popup.data)
    T.eq(DaylightUIDB.profileData.Healer.positions["actionbars.main"][2], 20, "brought along")
    -- Healer already exists now: nothing more to ask.
    stub.popup = nil
    P.AddPresetOffering("Healer")
    T.isnil(stub.popup, "already made")
end)

T.test("the DPS/Tank and Healer setups show the micro menu in the corner, the Immersive Preset doesn't", function()
    local DUI = login()
    for _, name in ipairs({ "DPS/Tank", "Healer" }) do
        local ab = DUI.Profiles.ReadyData(name).modules.ActionBars
        T.eq(ab.microMenu, "shown", name)
        T.eq(ab.microMenuCorner, true, name)
    end
    local ab = DUI.Profiles.ReadyData("Immersive Preset").modules.ActionBars
    T.truthy(ab.microMenu ~= "shown", "immersive: still hidden")
end)

T.test("Healer spots fit a smaller screen: pulled in with the width, the player row over a full raid", function()
    local DUI = login()
    local P = DUI.Profiles
    local at = P.PRESET_POSITIONS.Healer
    local refW, refH = P.PRESET_SCREEN[1], P.PRESET_SCREEN[2]
    -- 1920x1080 at UI scale 1: 1365.33 x 768 UIParent units.
    stub.SetScreen(1920, 1080, 1)
    local w, h = 1920 / 1080 * 768, 768
    P.AddPreset("Healer")
    local pos = DaylightUIDB.profileData.Healer.positions
    local player, target, raid = pos["unitframes.player"], pos["unitframes.target"], pos["unitframes.raid"]
    local tot = pos["unitframes.targettarget"]
    T.near(player[1] / (w / 2), at["unitframes.player"][1] / (refW / 2), 1e-6, "the same share of the half width")
    T.near(h / 2 + raid[2], refH / 2 + at["unitframes.raid"][2], 1e-6, "the raid: the same height above the bottom")
    T.eq(raid[1], 0, "the middle stays the middle")
    -- A full raid: 5 tiles a column, as the preset sets them.
    local r = P.PRESETS.Healer.UnitFrames.raid
    local raidTop = raid[2] + (r.perLine * r.height + (r.perLine - 1) * r.spacing) / 2
    local raidHalfW = (8 * r.width + 7 * r.groupSpacing) / 2
    T.truthy(math.abs(player[1]) - 187 / 2 < raidHalfW, "pulled in, the row would meet the raid side by side")
    -- So it sits over it: the frame's bottom half and its cast bar (27) clear the top row.
    T.truthy(player[2] - 43 / 2 - 3 - 27 > raidTop, "the player and its cast bar over the raid")
    T.truthy(tot[2] - 22 / 2 > raidTop,"the target of target (its lowest frame) over the raid")
    T.eq(target[2], player[2], "the target level with the player")
    T.eq(pos["unitframes.pet"][2], player[2], "the pet beside the player")
    T.near(tot[2] - target[2], at["unitframes.targettarget"][2] - at["unitframes.target"][2], 1e-6,
        "the target of target lifted with the row: still under the target")
    -- Clear of the chat panel in the corner (428 wide, 12 in from the edge).
    T.truthy(h / 2 + player[2] - 43 / 2 - 30 > 12 + 11 + 208 + 20, "over the chat")
end)

T.test("Healer spots on the screen they were made on, or a bigger one: as they are", function()
    -- 2560x1600 with the UI scale up (made there), 1440p at that scale, 4K and ultrawide at the smallest.
    for _, s in ipairs({ { 2560, 1600, 768 / 1066 }, { 2560, 1440, 768 / 1066 },
                         { 3840, 2160, 0.64 }, { 3440, 1440, 0.64 } }) do
        local DUI = login()
        stub.SetScreen(s[1], s[2], s[3])
        DUI.Profiles.AddPreset("Healer")
        local pos = DaylightUIDB.profileData.Healer.positions
        for key, v in pairs(DUI.Profiles.PRESET_POSITIONS.Healer) do
            T.near(pos[key][1], v[1], 1e-6, key .. " x at " .. s[1])
            T.near(pos[key][2], v[2], 1e-6, key .. " y at " .. s[1])
        end
    end
end)

T.test("the Healer setup is ordinary settings: every one it sets is shown on the Party or Raid page", function()
    local DUI, ns = stub.Load({ module = true })
    local O = DUI.Options
    local found = {}
    for _, id in ipairs({ "UnitFrames.party", "UnitFrames.raid" }) do
        local page = O.GetPage(id)
        for _, g in ipairs(page.groups) do
            for _, item in ipairs(g.items) do
                -- A key may have one row per frame style; only one of them shows.
                if item.key then
                    found[item.key] = found[item.key] or {}
                    table.insert(found[item.key], { page = page, item = item })
                end
            end
        end
    end
    local preset = DUI.Profiles.PRESETS.Healer.UnitFrames
    -- Every setting it sets, nested ones (raid.auras.buffs.show) by their full path.
    local leaves = {}
    local function walk(t, path, defaults)
        for k, v in pairs(t) do
            local d
            if type(defaults) == "table" then d = defaults[k] end
            if type(v) == "table" and type(d) == "table" and #v == 0 then
                walk(v, path .. k .. ".", d)
            else
                leaves[#leaves + 1] = { path = path .. k, value = v, known = d ~= nil }
            end
        end
    end
    for tbl, values in pairs(preset) do
        T.eq(type(values), "table", tbl .. " is a settings table")
        walk(values, tbl .. ".", ns.DEFAULTS[tbl])
    end
    for _, l in ipairs(leaves) do DUI:Set("UnitFrames", l.path, l.value) end
    local n = 0
    for _, l in ipairs(leaves) do
        local path = l.path
        T.truthy(l.known, path .. " is a known setting")
        local f = found[path]
        T.truthy(f, path .. " has an option on the Party or Raid page")
        local shows = false
        for _, row in ipairs(f or {}) do shows = shows or not O.IsHidden(row.page, row.item) end
        T.truthy(shows, path .. "'s option shows")
        n = n + 1
    end
    T.truthy(n > 25, "it sets a real look")
    for key in pairs(DUI.Profiles.PRESET_POSITIONS.Healer) do
        T.truthy(DUI.Movers.Get(key), key .. " is a mover")
    end
end)

T.test("the Immersive Preset setup is ordinary settings: each one it sets is a row on an options page, and its button makes it", function()
    local DUI = stub.Load({ module = true, actionbars = true, infopanel = true, quests = true, chat = true, buffs = true,
        before = function()
            fakeEncoding()
            _G.UnitXP = function() return 300 end
            _G.UnitXPMax = function() return 1200 end
            _G.GetXPExhaustion = function() return 400 end
        end })
    stub.RunTimers()
    local O, P = DUI.Options, DUI.Profiles
    local keys = {}
    for _, page in O.Pages() do
        for _, g in ipairs(page.groups or {}) do
            for _, item in ipairs(g.items or {}) do
                if item.key then keys[page.scope .. "|" .. item.key] = true end
                for _, also in ipairs(item.alsoKeys or {}) do keys[page.scope .. "|" .. also] = true end
            end
        end
    end
    local n = 0
    local function walk(scope, t, path)
        for k, v in pairs(t) do
            local at = path and (path .. "." .. k) or k
            if type(v) == "table" then walk(scope, v, at) else
                n = n + 1
                T.truthy(keys[scope .. "|" .. at], scope .. " " .. at .. " is a row on its page")
            end
        end
    end
    for mod, t in pairs(P.PRESETS["Immersive Preset"]) do walk(mod, t) end
    walk("general", P.PRESET_GENERAL["Immersive Preset"])
    T.truthy(n >= 15, "it sets a real setup (" .. n .. ")")
    -- The Profiles page's Ready-made card has its button.
    local btn
    for _, g in ipairs(O.GetPage("profiles").groups) do
        for _, item in ipairs(g.items) do
            if item.type == "button" and item.label == "Immersive Preset" then btn = item end
        end
    end
    T.truthy(btn, "an Immersive Preset button")
    btn.func()
    local p = DaylightUIDB.profileData["Immersive Preset"]
    T.truthy(p, "made")
    T.eq(p.general.fadeOpenWorldOnly, true)
    T.eq(p.modules.ActionBars.bars.main.fade.mode, "ooc")
    T.eq(p.modules.ActionBars.bars.main.fade.delay, 2)
    T.eq(p.modules.ActionBars.bars.main.fade.mouseover, DUI.Fade.DEFAULT.mouseover, "the rest of a fade stays the default")
    T.eq(DUI:Get("general", "fadeOpenWorldOnly"), false, "the profile in use is left as it is")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- ---------------------------------------------------------------------
-- Profile packs (Profiles.RegisterPack): another addon's ready-made profiles
-- ---------------------------------------------------------------------

T.test("packs: a pack's profiles are offered, made only when added, as the pack has them", function()
    local DUI = login()
    local P = DUI.Profiles
    local text = P.Encode({ v = 1, general = { borderPx = 3 }, modules = { UnitFrames = { swing = { height = 12 } } },
        positions = { ["unitframes.player"] = { -400, -100 } } })
    DUI.RegisterPack("TestPack", { label = "Test UI", author = "Someone", version = 1,
        profiles = { { name = "Test UI Healer", text = text, sub = "Tiles.", role = "Healer" },
                     { name = "Test UI Tank", data = { general = { borderPx = 4 } } } } })
    T.deq(P.PackNames(), { "Test UI Healer", "Test UI Tank" })
    T.truthy(P.IsReady("test ui healer"), "any case")
    T.isnil(DaylightUIDB.profileData["Test UI Healer"], "not made yet")
    T.eq(P.AddPreset("Test UI Healer"), "Test UI Healer")
    local p = DaylightUIDB.profileData["Test UI Healer"]
    T.eq(p.general.borderPx, 3, "the pack's settings")
    T.eq(p.modules.UnitFrames.swing.height, 12)
    T.eq(p.positions["unitframes.player"][1], -400, "no screen given: spots as they are")
    T.eq(p.fromPack.id, "TestPack")
    T.eq(p.fromPack.version, 1)
    T.eq(DUI:Get("general", "borderPx"), DUI.DB.GENERAL_DEFAULTS.borderPx, "the profile in use left as it is")
    p.general.borderPx = 7
    T.eq(P.AddPreset("Test UI Healer"), "Test UI Healer")
    T.eq(DaylightUIDB.profileData["Test UI Healer"].general.borderPx, 7, "made once: used as it is after")
    T.eq(P.AddPreset("Test UI Tank"), "Test UI Tank")
    T.eq(DaylightUIDB.profileData["Test UI Tank"].general.borderPx, 4, "a table works as a share string does")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("packs: spots fit a smaller screen when the pack says which screen it was made on", function()
    local DUI = login()
    local P = DUI.Profiles
    stub.SetScreen(1920, 1080, 1)
    local w, h = 1920 / 1080 * 768, 768
    DUI.RegisterPack("Wide", { screen = { 2 * w, 2 * h },
        profiles = { { name = "Wide", data = { positions = { ["unitframes.player"] = { -600, -300 } } } } } })
    P.AddPreset("Wide")
    local pos = DaylightUIDB.profileData.Wide.positions["unitframes.player"]
    T.near(pos[1], -300, 1e-6, "half as wide: half as far out")
    T.near(pos[2], -300 + h / 2, 1e-6, "the same height above the bottom")
end)

T.test("packs: one that can't be read is left out with a line in chat; a mistake in the call is an error", function()
    local DUI = login()
    local P = DUI.Profiles
    DUI.RegisterPack("Broken", { label = "Broken UI",
        profiles = { { name = "Broken", text = "!DUI1_bxnope" }, { name = "Fine", data = {} } } })
    T.deq(P.PackNames(), { "Fine" }, "the damaged one left out")
    T.truthy(stub.ChatContains("Broken UI"), "said, naming the pack")
    T.isnil(P.AddPreset("Broken"), "can't be made")
    T.errors(function() DUI.RegisterPack("NoProfiles", { profiles = {} }) end, "no profiles")
    T.errors(function() DUI.RegisterPack("Ours", { profiles = { { name = "healer", data = {} } } }) end, "one of our own names")
    T.errors(function() DUI.RegisterPack("Broken", { profiles = { { name = "Z", data = {} } } }) end, "the same id twice")
    T.errors(function() DUI.RegisterPack("NoData", { profiles = { { name = "Empty" } } }) end, "no text or data")
    T.errors(function() DUI.RegisterPack("BadExtra", { profiles = { { name = "E", data = {} } }, extras = { { addon = "Details" } } }) end,
        "an extra without apply")
    -- Two packs with the same profile: the player's setup, so the second one's is left out, not an error.
    T.noerror(function() DUI.RegisterPack("Other", { label = "Other UI", profiles = { { name = "fine", data = {} } } }) end)
    T.eq(#P.PACKS.Other.profiles, 0)
    T.truthy(stub.ChatContains("Other UI"))
    -- Called like RegisterModule, with a colon, works too.
    DaylightUI:RegisterPack("Colon", { profiles = { { name = "Colon", data = {} } } })
    T.truthy(P.PACKS.Colon, "DaylightUI:RegisterPack")
end)

T.test("packs: a pack that offers updates brings its newer version in; one that doesn't never touches a made profile", function()
    local DUI = login()
    local P = DUI.Profiles
    local function register(version)
        DUI.RegisterPack("Up", { version = version, updates = "offer",
            profiles = { { name = "Up", data = { general = { borderPx = version + 2 } } } } })
        DUI.RegisterPack("Still", { version = version,
            profiles = { { name = "Still", data = { general = { borderPx = version + 2 } } } } })
    end
    register(1)
    P.AddPreset("Up")
    P.AddPreset("Still")
    T.isnil(P.PackUpdate("Up"), "the same version: nothing newer")
    DUI.DB.Active().modules.Buffs = { history = { a = 1 } }
    DaylightUIDB.profileData.Up.modules.Buffs = { history = { mine = 1 } }
    -- The pack's next version, after the player changed the profile.
    DUI = reload()
    P = DUI.Profiles
    register(2)
    local t = DaylightUIDB.profileData.Up
    t.general.borderPx = 9
    T.truthy(P.PackUpdate("Up"), "a newer version")
    T.isnil(P.PackUpdate("Still"), "never offered by that pack")
    -- The Profiles page: Update instead of Add.
    local O = DUI.Options
    local page = O.GetPage("profiles")
    local add, update
    for _, g in ipairs(page.groups) do
        for _, item in ipairs(g.items) do
            if item.label == "Up" and item.text == "Add" then add = item end
            if item.label == "Up" and item.text == "Update" then update = item end
        end
    end
    T.truthy(O.IsHidden(page, add), "Add hidden")
    T.falsy(O.IsHidden(page, update), "Update shown")
    T.truthy(update.confirm, "a second click: it overwrites the player's changes")
    update.func()
    T.eq(DaylightUIDB.profileData.Up, t, "the same profile")
    T.eq(t.general.borderPx, 4, "the pack's newer settings")
    T.eq(t.modules.Buffs.history.mine, 1, "what's learned as you play stays its own")
    T.eq(t.fromPack.version, 2)
    T.isnil(P.PackUpdate("Up"), "up to date")
    T.eq(DaylightUIDB.profileData.Still.general.borderPx, 3, "the other pack's profile as it was")
end)

T.test("packs: the Profiles page has a card per pack after Ready-made, and its button makes the profile", function()
    local DUI = login()
    local O = DUI.Options
    DUI.RegisterPack("Card", { label = "Card UI", author = "Ann", desc = "Calm and clean.",
        profiles = { { name = "Card UI", data = { general = { borderPx = 3 } }, sub = "Tiles for healers." } } })
    local page = O.GetPage("profiles")
    local at, ready
    for i, g in ipairs(page.groups) do
        if g.label == "Card UI" then at = i end
        if g.label == "Ready-made" then ready = i end
    end
    T.eq(at, ready + 1, "right after Ready-made")
    local group = page.groups[at]
    T.truthy(string.find(group.desc, "By Ann.", 1, true), "who made it")
    local add = group.items[1]
    T.eq(add.text, "Add")
    T.falsy(O.IsHidden(page, add))
    T.truthy(string.find(add.desc, "Tiles for healers.", 1, true))
    add.func()
    T.eq(DaylightUIDB.profileData["Card UI"].general.borderPx, 3)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
