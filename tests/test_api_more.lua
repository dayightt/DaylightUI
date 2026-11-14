local stub = require("stub")

-- DaylightUI.API 1.7: what plugins reached into Daylight UI's insides for
-- before: frames by name, movers, previews, motion, media, a setting changed
-- for a while, the vendor's shelf, the AFK screen, a frame being placed.

local function load(opts)
    opts = opts or {}
    opts.module = true
    local DUI = stub.Load(opts)
    stub.RunTimers()
    return DUI, DUI.API
end

T.test("api more: frames by name, the mover's frame, unlock and previews, motion and media", function()
    local DUI, API = load({ infopanel = true })
    T.eq(API.GetFrame("infopanel"), _G.DaylightUIInfoPanelBody)
    T.isnil(API.GetFrame("bags"), "a module that isn't loaded: nil")
    T.isnil(API.GetFrame("nope"))
    T.truthy(#API.FRAME_NAMES >= 10)
    T.eq(API.GetMoverFrame("infopanel"), DUI.Movers.Get("infopanel").frame)
    T.isnil(API.GetMoverFrame("nope"))
    T.eq(API.MotionOn(), true)
    DUI:Set("general", "motion", false)
    T.eq(API.MotionOn(), false)
    T.eq(API.Media("ui-mail.png"), DUI.MEDIA .. "ui-mail.png")
    T.isnil(API.Media("../x.png"), "only inside the media folder")
    local me = API.For("Boxes")
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(40, 20)
    me.RegisterMover(f, "box", "Box", { point = "CENTER", x = 0, y = 0 })
    me.RegisterTestPart("box", "Box")
    T.eq(me.IsPreviewing("box"), false)
    DUI.Movers.Unlock()
    T.eq(API.IsUnlocked(), true)
    T.eq(me.IsPreviewing("box"), true, "unlocked")
    DUI.Movers.Lock()
    DUI.SetTestMode(true)
    T.eq(me.IsPreviewing("box"), true, "test mode with its part ticked")
    DUI.SetTestMode(false)
    T.eq(me.SuspendMover("box", true), true)
    T.eq(me.SuspendMover("box", false), true)
    local placed
    API.On("FramePlaced", function(key) placed = key end)
    DUI.Fire("MoverApplied", "plugin.Boxes.box")
    T.eq(placed, "plugin.Boxes.box")
end)

T.test("api more: a setting changed for a while comes back, never saved, and the player wins", function()
    local DUI, API = load({ qol = true })
    local me = API.For("Fisher")
    local was = DUI:Get("general", "motion")
    local h = me.Override("general", "motion", not was)
    T.truthy(h)
    T.eq(DUI:Get("general", "motion"), not was)
    T.isnil(API.For("Other").Override("general", "motion", was), "one plugin per setting")
    API.Off(h)
    T.eq(DUI:Get("general", "motion"), was, "back as it was")
    -- Logging out with one held: the player's value is what's saved.
    me.Override("general", "motion", not was)
    stub.FireEvent("PLAYER_LOGOUT")
    T.eq(DUI:Get("general", "motion"), was)
    -- The player changing it themself takes it over.
    local h2 = me.Override("general", "motion", not was)
    DUI:Set("general", "motion", was)
    API.Off(h2)
    T.eq(DUI:Get("general", "motion"), was, "their pick stays")
    T.isnil(me.Override("Nope", "x", 1), "a module that isn't there")
end)

T.test("api more: shop filters leave items off the shelf, and stop", function()
    local DUI, API = load()
    local R = DUI.APIReport
    local list = { { index = 1, name = "Grimoire of Firebolt" }, { index = 2, name = "Bread" } }
    T.eq(#R.FilterShop(list), 2, "no filter: all")
    local me = API.For("Books")
    local h = me.FilterShop(function(item) return string.find(item.name, "Grimoire", 1, true) ~= nil end)
    local out = R.FilterShop(list)
    T.eq(#out, 1); T.eq(out[1].index, 1)
    API.For("Broken").FilterShop(function() error("nope") end)
    T.eq(#R.FilterShop(list), 1, "a broken filter keeps everything it can't judge")
    API.Off(h)
    T.eq(#R.FilterShop(list), 2)
end)

T.test("api more: the AFK screen tells plugins when it comes and goes", function()
    local DUI, API = load({ qol = true })
    local log = {}
    API.On("AfkScreenShown", function() log[#log + 1] = "shown" end)
    API.On("AfkScreenHidden", function() log[#log + 1] = "hidden" end)
    local Afk = stub.qol and stub.qol.Afk
    T.truthy(Afk, "the AFK screen")
    T.eq(Afk.Show(true), true, "the preview shows")
    T.eq(API.IsAfkScreen(), true)
    Afk.Leave(true)
    T.eq(log[1], "shown"); T.eq(log[2], "hidden")
end)
