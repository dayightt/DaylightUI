-- A shared profile imported on a screen of another shape (ultrawide, 16:10,
-- 4:3): its frames land where they sat on the screen it was made on.

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

local function login(w, h)
    local DUI = stub.Load({ module = true, chat = true, infopanel = true, before = fakeEncoding })
    stub.SetScreen(w or 1920, h or 1080, 1)
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

T.test("screen fit: from 16:9 to ultrawide, moved spots stay and edge pieces come in to the old edges", function()
    local DUI = login(1920, 1080)
    local P, M = DUI.Profiles, DUI.Movers
    DUI.DB.Positions()["unitframes.player"] = { -300, -200 }
    local w0 = UIParent:GetWidth()
    local _, _, _, chatX0, chatY0 = M.DefaultSpot("chat")
    local _, ipAx0 = M.DefaultSpot("infopanel")
    local text = P.Encode(P.Snapshot())

    stub.SetScreen(3440, 1440, 1)
    local w = UIParent:GetWidth()
    T.truthy(w > w0 + 100, "a wider screen in UI units at the same height")
    local made = import(DUI, text, "Wide")
    local pos = made.positions
    T.eq(pos["unitframes.player"][1], -300, "a moved spot stays: it's from the middle")
    T.eq(pos["unitframes.player"][2], -200)
    T.near(pos.chat[1], chatX0, 0.01, "chat where it sat on 16:9, not at the far left")
    T.near(pos.chat[2], chatY0, 0.01, "at the same height")
    T.eq(pos.chat.at, "BOTTOMLEFT", "still held by its corner")
    T.near(pos.infopanel.ax, ipAx0, 0.01, "the info panel by its corner, at the old right edge")
    T.eq(pos.infopanel.at, "TOPRIGHT")
    T.isnil(pos["unitframes.playerCastbar"], "a piece in the middle of the bottom isn't pinned")
    T.truthy(M.Valid(pos.chat) and M.Valid(pos.infopanel), "ordinary saved spots")
    T.truthy(string.find(stub.chat[#stub.chat] or "", "16:9 screen to your 21:9", 1, true), "says so")
end)

T.test("screen fit: from ultrawide to 16:9, spots are pulled in with the width", function()
    local DUI = login(3440, 1440)
    local P = DUI.Profiles
    DUI.DB.Positions()["unitframes.player"] = { -1200, -200 }
    DUI.DB.Positions()["unitframes.target"] = { 600, -200, at = "LEFT", ax = 500, ay = -200 }
    local w0 = UIParent:GetWidth()
    local text = P.Encode(P.Snapshot())

    stub.SetScreen(1920, 1080, 1)
    local k = UIParent:GetWidth() / w0
    local pos = import(DUI, text, "Narrow").positions
    T.near(pos["unitframes.player"][1], -1200 * k, 0.1, "the same share of the width: on screen")
    T.eq(pos["unitframes.player"][2], -200, "the height kept")
    T.near(pos["unitframes.target"][1], 600 * k, 0.1)
    T.near(pos["unitframes.target"].ax, 500 + 600 * k - 600, 0.1, "its corner moved with it")
    T.isnil(pos.chat, "a piece never moved stays at the edge it starts at")
end)

T.test("screen fit: the same shape, or positions left out: nothing moves", function()
    local DUI = login(2560, 1440)
    local P = DUI.Profiles
    DUI.DB.Positions()["unitframes.player"] = { -900, -200 }
    local text = P.Encode(P.Snapshot())
    stub.SetScreen(1920, 1080, 1)
    local pos = import(DUI, text, "Same").positions
    T.eq(pos["unitframes.player"][1], -900, "16:9 at another size: as made")
    T.isnil(pos.chat, "no edge pieces pinned")

    stub.SetScreen(3440, 1440, 1)
    DUI.DB.Positions()["unitframes.player"] = { 50, 60 }
    local made = import(DUI, text, "Mine", { positions = true })
    T.eq(made.positions["unitframes.player"][1], 50, "positions switched off: yours, untouched")
    T.isnil(made.positions.chat, "and nothing added")
end)

T.test("screen fit: a string from before the screen was saved counts as 16:9", function()
    local DUI = login(3440, 1440)
    local P = DUI.Profiles
    local text = P.Encode({ v = 1, general = {}, modules = {}, positions = { ["unitframes.player"] = { -10, -20 } } })
    local pos = import(DUI, text, "Old").positions
    T.eq(pos["unitframes.player"][1], -10)
    T.truthy(pos.chat, "the edge pieces brought in to a 16:9 width")
    local _, _, _, x = DUI.Movers.DefaultSpot("chat")
    T.near(pos.chat[1] - x, (UIParent:GetWidth() - UIParent:GetHeight() * 16 / 9) / 2, 0.01, "by the extra width")
end)

