-- A shared profile imported on another screen (ultrawide, 16:10, a higher
-- resolution at another UI scale): its frames land where they sat on the
-- screen it was made on, the same size for the screen.

local stub = require("stub")

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
        DecompressString = function(s) return string.sub(s, 2) end,
        EncodeBase64 = function(s) return "b" .. s end,
        DecodeBase64 = function(s) return string.sub(s, 2) end,
    }
end

local function login(w, h, scale)
    local DUI = stub.Load({ module = true, chat = true, infopanel = true, before = fakeEncoding })
    stub.SetScreen(w or 1920, h or 1080, scale or 1)
    stub.RunTimers()
    return DUI
end

-- Pastes text into the import box with only the parts in off switched off.
local function import(DUI, text, name, off)
    local P = DUI.Profiles
    stub.Dismiss()
    P.ShowImport()
    local box = _G.DaylightUIProfileBox
    box.edit:SetText(text)
    for i, part in ipairs(P.Parts(P.Decode(text))) do
        if off and off[part.key] then box.parts.rows[i]:GetScript("OnClick")() end
    end
    box.name:SetText(name)
    box.go:GetScript("OnClick")()
    return DaylightUIDB.profileData[name]
end

T.test("screen fit: a shared profile says the screen it was made on", function()
    local DUI = login(1920, 1080)
    local P = DUI.Profiles
    local p = P.Decode(P.Encode(P.Snapshot()))
    T.near(p.screen[1] / p.screen[2], 16 / 9, 0.01, "16:9")
    T.isnil(P.Check({ v = 1, screen = { "wide", 2 } }).screen, "a damaged one is dropped")
    T.isnil(P.Check({ v = 1, screen = { 0, 768 } }).screen, "so is an empty one")
end)

T.test("screen fit: shapes by the names players know", function()
    local P = login().Profiles
    T.eq(P.ShapeName(1920 / 1080), "16:9")
    T.eq(P.ShapeName(3440 / 1440), "21:9", "sold as 21:9 though it's 2.39")
    T.eq(P.ShapeName(2560 / 1080), "21:9")
    T.eq(P.ShapeName(5120 / 1440), "32:9")
    T.eq(P.ShapeName(1920 / 1200), "16:10")
    T.eq(P.ShapeName(1024 / 768), "4:3")
    T.eq(P.ShapeName(3), "3.00:1", "anything else as a number")
end)

-- A piece's box at spot v, drawn s times its size now.
local function box(DUI, key, v, s)
    local w, h = DUI.Movers.SizeOf(key)
    w, h = w * (s or 1) / 2, h * (s or 1) / 2
    return { l = v[1] - w, r = v[1] + w, b = v[2] - h, t = v[2] + h }
end

local function apart(a, b) return a.r <= b.l or b.r <= a.l or a.t <= b.b or b.t <= a.b end

T.test("screen fit: from 16:9 to 32:9, the middle stays and a side piece keeps its gap from its edge", function()
    local DUI = login(1920, 1080)
    local P = DUI.Profiles
    DUI.DB.Positions()["unitframes.player"] = { -300, -200 }
    DUI.DB.Positions()["unitframes.focus"] = { 500, 100 }
    local w0 = UIParent:GetWidth()
    local text = P.Encode(P.Snapshot())

    stub.SetScreen(5120, 1440, 1)
    local w = UIParent:GetWidth()
    local made = import(DUI, text, "Wide")
    local pos = made.positions
    T.eq(pos["unitframes.player"][1], -300, "in the middle half: as far from the middle")
    T.eq(pos["unitframes.player"][2], -200, "the same height (the same UI scale)")
    T.near(pos["unitframes.focus"][1], w / 2 - (w0 / 2 - 500), 1e-6, "as far from the right edge")
    T.eq(pos["unitframes.focus"][2], 100)
    T.isnil(pos.chat, "a piece never moved starts at its own edge anyway: not pinned")
    T.eq(made.general.scale, 1, "same height: the same size")
    T.truthy(string.find(stub.chat[#stub.chat] or "", "16:9 screen to your 32:9", 1, true), "says so")
end)

T.test("screen fit: from 32:9 to 16:9, the middle and the edges keep their spots, what's between is squeezed, and a side piece in the way shrinks", function()
    local DUI = login(5120, 1440)
    local P, M = DUI.Profiles, DUI.Movers
    DUI:Set("general", "borderPx", 3) -- so Appearance comes along, and with it the pieces' sizes
    local w0 = UIParent:GetWidth()
    local at = DUI.DB.Positions()
    at["unitframes.player"] = { -300, -200 } -- the middle
    at["unitframes.target"] = { 1250, -100 } -- by the right edge
    at["unitframes.focus"] = { -980, 300 } -- between
    -- Either side of where the middle ends: they stay in order, close together.
    at["combattext.hits"] = { 335, -450 }
    at["combattext.heals"] = { 350, -450 }
    -- By the right edge, a big piece; in the middle, one it only reaches at full
    -- size and one in its way at any size.
    at["unitframes.pet"] = { 1300, 300 }
    at["infopanel"] = { 300, 300 }
    at["chat.side"] = { 340, 300 }
    M.SetPieceScale("unitframes.pet", 2)
    M.SetPieceScale("infopanel", 2)
    M.SetPieceScale("chat.side", 1.5)
    local text = P.Encode(P.Snapshot())

    stub.SetScreen(1920, 1080, 1)
    local w = UIParent:GetWidth()
    local made = import(DUI, text, "Narrow")
    local pos, scales = made.positions, made.general.frameScales or {}
    local room, half = w / 2, w0 / 2
    local mid, edge = room * P.FIT_MIDDLE, room * P.FIT_EDGE
    T.deq(pos["unitframes.player"], { -300, -200 }, "the middle stays")
    T.near(pos["unitframes.target"][1], room - (half - 1250), 1e-6, "by the edge: the same gap from it")
    T.isnil(scales["unitframes.target"], "and the same size")
    T.near(pos["unitframes.focus"][1], -(mid + (980 - mid) * (room - edge - mid) / (half - edge - mid)), 1e-6,
        "between: squeezed evenly into the room between the middle and the edge")
    T.eq(pos["unitframes.focus"][2], 300)
    local a, b = pos["combattext.hits"][1], pos["combattext.heals"][1]
    T.truthy(a < b and b - a < 15, "across where the middle ends: still in order, still close: " .. a .. ", " .. b)

    local s = scales["unitframes.pet"] / 2
    local pet = box(DUI, "unitframes.pet", pos["unitframes.pet"], s)
    local panel = box(DUI, "infopanel", pos.infopanel)
    T.near(s, (room - panel.r) / ((half - 1300) + M.SizeOf("unitframes.pet") / 2), 0.005,
        "shrinks just clear of what it can clear: not on to half size for the piece in the way at any size")
    T.truthy(apart(pet, panel), "clear of the piece only its full size reached")
    T.falsy(apart(pet, box(DUI, "chat.side", pos["chat.side"])), "(the other really is in the way at any size)")
    T.eq(made.general.scale, 1, "the Scale is the same: same height")
end)

T.test("screen fit: from 1080p's UI scale to 1440p's, everything grows with the height, in the same places", function()
    local DUI = login(1920, 1080, 768 / 1080)
    local P, M = DUI.Profiles, DUI.Movers
    DUI:Set("general", "borderPx", 3)
    DUI.DB.Positions()["unitframes.player"] = { -300, -200 }
    DUI.DB.Positions()["unitframes.focus"] = { 700, 300 }
    T.near(UIParent:GetHeight(), 1080, 1e-6, "1080 units tall")
    local text = P.Encode(P.Snapshot())

    stub.SetScreen(2560, 1440, 768 / 1440)
    local k = UIParent:GetHeight() / 1080
    T.near(k, 4 / 3, 1e-6)
    local at, ax0, ay0 = M.DefaultSpot("chat", 1920, 1080)
    local made = import(DUI, text, "Big")
    local pos = made.positions
    T.near(made.general.scale, k, 1e-6, "the Scale times the height: the same size for the screen")
    T.near(pos["unitframes.player"][1], -300 * k, 1e-6, "as far from the middle, for the screen")
    T.near(pos["unitframes.player"][2], -200 * k, 1e-6)
    T.near(pos["unitframes.focus"][1], 2560 / 2 - (1920 / 2 - 700) * k, 1e-6)
    T.near(pos["unitframes.focus"][2], 300 * k, 1e-6)
    T.truthy(pos.chat, "a piece never moved gets its spot, since its start spot doesn't grow")
    T.eq(pos.chat.at, at, "held by the same corner")
    T.near(pos.chat.ax, -2560 / 2 + (ax0 + 1920 / 2) * k, 1e-6, "its gap from the edge grown too")
    T.near(pos.chat.ay, ay0 * k, 1e-6)
    T.isnil(next(made.general.frameScales), "nothing shrunk: the same shape")
    T.truthy(string.find(stub.chat[#stub.chat] or "", "Imported the profile Big.", 1, true), "the same shape: nothing more to say")
end)

T.test("screen fit: from 16:10 to 16:9, the extra width goes between the middle and the sides", function()
    local DUI = login(1920, 1200)
    local P = DUI.Profiles
    DUI.DB.Positions()["unitframes.player"] = { -300, -200 }
    DUI.DB.Positions()["unitframes.focus"] = { -500, 100 }
    DUI.DB.Positions()["unitframes.target"] = { 450, -100, at = "LEFT", ax = 357, ay = -100 }
    local w0 = UIParent:GetWidth()
    local text = P.Encode(P.Snapshot())

    stub.SetScreen(1920, 1080, 1)
    local w = UIParent:GetWidth()
    local pos = import(DUI, text, "Sixteen").positions
    T.eq(pos["unitframes.player"][1], -300)
    T.near(pos["unitframes.focus"][1], -w / 2 + (w0 / 2 - 500), 1e-6, "as far from the left edge")
    T.near(pos["unitframes.target"][1], w / 2 - (w0 / 2 - 450), 1e-6, "as far from the right edge")
    T.near(pos["unitframes.target"].ax - pos["unitframes.target"][1], 357 - 450, 1e-6, "its corner moved with it")
    T.eq(pos["unitframes.target"].at, "LEFT")
    T.truthy(string.find(stub.chat[#stub.chat] or "", "16:10 screen to your 16:9", 1, true), "says so")
end)

T.test("screen fit: on the screen it was made on, or another resolution at the same UI scale, nothing changes", function()
    local DUI = login(1920, 1080, 768 / 1080)
    local P = DUI.Profiles
    DUI:Set("general", "borderPx", 3)
    DUI:Set("general", "scale", 1.15)
    DUI.DB.Positions()["unitframes.player"] = { -300.123456789, -200.987654321 }
    DUI.DB.Positions()["unitframes.target"] = { 550.5, -100.25, at = "LEFT", ax = 457.1, ay = -100.25 }
    local before = DUI.DB.Positions()
    local text = P.Encode(P.Snapshot())
    local p = P.Decode(text)
    T.truthy(rawequal(P.Fit(p), p), "the very same profile back")

    local pos = import(DUI, text, "Same").positions
    T.deq(pos["unitframes.player"], before["unitframes.player"], "no drift")
    T.deq(pos["unitframes.target"], before["unitframes.target"])
    T.isnil(pos.chat, "nothing pinned")
    T.eq(DaylightUIDB.profileData.Same.general.scale, 1.15, "the Scale as it was")

    stub.SetScreen(2560, 1440, 768 / 1080)
    T.near(UIParent:GetHeight(), 1080, 1e-6, "the same UI scale: as many units tall")
    T.truthy(rawequal(P.Fit(p), p), "1440p at the same UI scale is the same screen to a profile")
    pos = import(DUI, text, "Same2").positions
    T.deq(pos["unitframes.player"], before["unitframes.player"])
end)

T.test("screen fit: a string from before the screen was saved, or positions left out: nothing moves", function()
    local DUI = login(3440, 1440)
    local P = DUI.Profiles
    local text = P.Encode({ v = 1, general = { borderPx = 3 }, modules = {},
        positions = { ["unitframes.player"] = { -10, -20 } } })
    local made = import(DUI, text, "Old")
    T.deq(made.positions["unitframes.player"], { -10, -20 }, "as it was")
    T.isnil(made.positions.chat, "nothing pinned")
    T.eq(made.general.scale, 1)

    DUI.DB.Positions()["unitframes.player"] = { -900, -200 }
    local wide = P.Encode(P.Snapshot())
    stub.SetScreen(1920, 1080, 1)
    DUI.DB.Positions()["unitframes.player"] = { 50, 60 }
    made = import(DUI, wide, "Mine", { positions = true })
    T.deq(made.positions["unitframes.player"], { 50, 60 }, "positions switched off: yours, untouched")
    T.isnil(made.positions.chat, "and nothing added")
end)

-- The game's layout text, faked like the encoder: a store behind a token.
local function fakeEditMode(DUI)
    local store, n = {}, 0
    local function deep(v)
        if type(v) ~= "table" then return v end
        local o = {}
        for k, x in pairs(v) do o[k] = deep(x) end
        return o
    end
    local had = rawget(_G, "C_EditMode")
    _G.C_EditMode = had or {}
    C_EditMode.ConvertLayoutInfoToString = function(l) n = n + 1; store[n] = deep(l); return "layout" .. n end
    C_EditMode.ConvertStringToLayoutInfo = function(s)
        local i = tonumber(string.match(s, "^layout(%d+)$"))
        if not i or not store[i] then error("bad layout") end
        return deep(store[i])
    end
    Enum.EditModeSystem = { ActionBar = 0, Minimap = 2 }
    Enum.EditModeActionBarSetting = { Orientation = 0, IconSize = 3 }
    Enum.EditModeMinimapSetting = { Size = 2 }
    Enum.EditModeSettingDisplayType = { Dropdown = 0, Checkbox = 1, Slider = 2 }
    -- The game's sliders: stored as steps above the minimum.
    local function slider(min, max, step)
        return { type = 2, minValue = min, maxValue = max, stepSize = step,
                 ConvertValueForDisplay = function(self, v) return math.min(self.maxValue, v * self.stepSize + self.minValue) end,
                 ConvertValue = function(self, v, shown)
                     if shown then return v * self.stepSize + self.minValue end
                     return (v - self.minValue) / self.stepSize
                 end }
    end
    local map = { [0] = { [3] = slider(50, 200, 10), [0] = { type = 0 } }, [2] = { [2] = slider(50, 200, 10) } }
    _G.EditModeSettingDisplayInfoManager = { GetSystemSettingDisplayInfoMap = function(_, system) return map[system] end }
    return function()
        Enum.EditModeSystem, Enum.EditModeActionBarSetting, Enum.EditModeMinimapSetting = nil, nil, nil
        Enum.EditModeSettingDisplayType = nil
        _G.C_EditMode, _G.EditModeSettingDisplayInfoManager = had, nil
    end
end

local function anchor(point, rel, relPoint, x, y)
    return { point = point, relativeTo = rel, relativePoint = relPoint, offsetX = x, offsetY = y }
end

T.test("screen fit: the Edit Mode layout's spots and sizes fitted, written back as the game reads it", function()
    local DUI = login(1920, 1080, 768 / 1080)
    local P = DUI.Profiles
    local undo = fakeEditMode(DUI)
    local layout = { layoutName = "Theirs", systems = {
        { system = 0, systemIndex = 1, isInDefaultPosition = false, anchorInfo = anchor("BOTTOM", "UIParent", "BOTTOM", 0, 50),
          settings = { { setting = 0, value = 1 }, { setting = 3, value = 5 } } },
        { system = 2, isInDefaultPosition = false, anchorInfo = anchor("TOPRIGHT", "UIParent", "TOPRIGHT", -20, -20),
          settings = { { setting = 2, value = 15 } } },
        { system = 0, systemIndex = 2, isInDefaultPosition = false, anchorInfo = anchor("BOTTOM", "MainMenuBar", "TOP", 3, 6),
          settings = { { setting = 3, value = 5 } } },
        { system = 0, systemIndex = 3, isInDefaultPosition = true, anchorInfo = anchor("BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 7, 9),
          settings = {} },
        -- Edit Mode keeps this one from the left edge though it sits right of the middle half.
        { system = 0, systemIndex = 4, isInDefaultPosition = false, anchorInfo = anchor("LEFT", "UIParent", "LEFT", 1500, 0),
          settings = {} },
        { system = 0, systemIndex = 5, isInDefaultPosition = false, anchorInfo = anchor("BOTTOM", "UIParent", "BOTTOM", 0, -4),
          settings = {} },
    } }
    local text = P.Encode({ v = 1, screen = { 1920, 1080 }, general = { borderPx = 3 }, modules = {},
        layout = C_EditMode.ConvertLayoutInfoToString(layout) })

    T.eq(import(DUI, text, "Same").pendingLayout, P.Decode(text).layout, "the same screen: the very same text")

    stub.SetScreen(2560, 1440, 768 / 1440)
    local k = 4 / 3
    local made = import(DUI, text, "Big")
    T.truthy(made.pendingLayout ~= P.Decode(text).layout, "new text")
    local got = C_EditMode.ConvertStringToLayoutInfo(made.pendingLayout)
    T.eq(got.layoutName, "Theirs", "the rest of it as it was")
    local bar, map, snapped, home, far = got.systems[1], got.systems[2], got.systems[3], got.systems[4], got.systems[5]
    T.near(got.systems[6].anchorInfo.offsetY, -4 * k, 1e-6, "tucked under the bottom edge: still, times the height")
    T.near(bar.anchorInfo.offsetY, 50 * k, 1e-6, "from the bottom, times the height")
    T.near(bar.anchorInfo.offsetX, 0, 1e-6)
    T.eq(bar.settings[1].value, 1, "a setting that isn't a size: as it was")
    T.eq(bar.settings[2].value, 8, "100% times 4/3 on a 10% slider: 130%")
    T.near(map.anchorInfo.offsetX, -20 * k, 1e-6, "from its corner, times the height")
    T.near(map.anchorInfo.offsetY, -20 * k, 1e-6)
    T.eq(map.settings[1].value, 15, "200% is the slider's top: kept there")
    T.near(snapped.anchorInfo.offsetX, 3 * k, 1e-6, "snapped to another frame: only its gap grows")
    T.near(snapped.anchorInfo.offsetY, 6 * k, 1e-6)
    T.eq(snapped.anchorInfo.relativeTo, "MainMenuBar")
    T.deq(home.anchorInfo, anchor("BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 7, 9), "in its default place: the game places it")
    T.near(far.anchorInfo.offsetX, 2560 - (1920 - 1500) * k, 1e-6, "right of the middle: as far from the right edge")
    T.eq(far.anchorInfo.relativePoint, "LEFT", "still held the way Edit Mode held it")

    local bad = P.Encode({ v = 1, screen = { 1920, 1080 }, modules = {}, layout = "not a layout" })
    T.eq(import(DUI, bad, "Bad").pendingLayout, "not a layout", "text the game can't read: as it is")
    undo()
end)
