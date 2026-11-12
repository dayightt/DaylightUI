local stub = require("stub")

-- The info panel's data texts: the strip under the minimap.

-- The game as the texts read it: money, worn gear, bags, friends, a guild.
local function world(w)
    w = w or {}
    -- The damage meter is the fake game's own (stub.DamageMeter), empty.
    local tip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
    _G.GameTooltip = tip
    function tip:SetOwner(o) self.__owner, self.__lines = o, {} end
    function tip:IsOwned(o) return self.__owner == o end
    function tip:AddLine(t, r, g, b) self.__lines[#self.__lines + 1] = { t, lc = { r, g, b } } end
    function tip:AddDoubleLine(l, r, lr, lg, lb, rr, rg, rb)
        self.__lines[#self.__lines + 1] = { l, r, lc = { lr, lg, lb }, rc = { rr, rg, rb } }
    end
    local cluster = CreateFrame("Frame", "MinimapCluster", UIParent)
    local mm = CreateFrame("Frame", "Minimap", cluster)
    function mm:GetZoom() return 2 end
    _G.UnitXP = function() return 300 end
    _G.UnitXPMax = function() return 1200 end
    _G.IsPlayerAtEffectiveMaxLevel = function() return false end
    stub.money = w.money or 1234567
    _G.GetMoney = function() return stub.money end
    stub.gear = w.gear or { [1] = { 90, 100 }, [5] = { 40, 100 }, [16] = { 70, 70 } }
    _G.GetInventoryItemDurability = function(slot)
        local g = stub.gear[slot]
        if g then return g[1], g[2] end
    end
    stub.bags = w.bags or { [0] = { 16, 4, 0 }, [1] = { 20, 6, 0 }, [2] = { 12, 12, 8 } }   -- slots, free, family
    _G.C_Container = {
        GetContainerNumSlots = function(bag) return stub.bags[bag] and stub.bags[bag][1] or 0 end,
        GetContainerNumFreeSlots = function(bag)
            local b = stub.bags[bag]
            if b then return b[2], b[3] end
            return 0, 0
        end,
        GetBagName = function(bag) return bag == 0 and "Backpack" or ("Pouch " .. bag) end,
    }
    stub.friends = w.friends or { { connected = true, name = "Ellie", level = 60, className = "Mage", area = "Elwynn" },
                                  { connected = false, name = "Away", level = 12 } }
    _G.C_FriendList = {
        GetNumOnlineFriends = function()
            local n = 0
            for _, f in ipairs(stub.friends) do if f.connected then n = n + 1 end end
            return n
        end,
        GetNumFriends = function() return #stub.friends end,
        GetFriendInfoByIndex = function(i) return stub.friends[i] end,
    }
    _G.LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mage", WARRIOR = "Warrior" }
    _G.BNGetNumFriends = function() return 2, 1 end
    _G.C_BattleNet = { GetFriendAccountInfo = function(i)
        if i == 1 then
            return { accountName = "Sam", gameAccountInfo = { isOnline = true, characterName = "Thorn", areaName = "Duskwood",
                                                              classFilename = "WARRIOR" } }
        end
        return { accountName = "Off", gameAccountInfo = { isOnline = false } }
    end }
    stub.inGuild = w.inGuild ~= false
    _G.IsInGuild = function() return stub.inGuild end
    _G.GetNumGuildMembers = function() return 3, 2, 2 end
    _G.GetGuildInfo = function() return "Dawnbreakers" end
    _G.GetGuildRosterInfo = function(i)
        local r = ({ { "Bram-Realm", true, "WARRIOR", "Ironforge" }, { "Cass-Realm", true, "MAGE", "Darnassus" },
                     { "Dorn-Realm", false, "MAGE", "" } })[i]
        return r[1], "Member", 1, 60, "Warrior", r[4], "", "", r[2], 0, r[3]
    end
    stub.rosterAsks = 0
    _G.C_GuildInfo = { GuildRoster = function() stub.rosterAsks = stub.rosterAsks + 1 end }
    _G.GetFramerate = function() return 119.6 end
    _G.GetNetStats = function() return 0, 0, 38, 45 end
    stub.opened = {}
    _G.ToggleAllBags = function() stub.opened[#stub.opened + 1] = "bags" end
    _G.ToggleCharacter = function(page) stub.opened[#stub.opened + 1] = "character:" .. tostring(page) end
    _G.ToggleFriendsFrame = function() stub.opened[#stub.opened + 1] = "friends" end
    _G.ToggleGuildFrame = function() stub.opened[#stub.opened + 1] = "guild" end
end

local function login(w, more)
    local DUI = stub.Load({ infopanel = true, before = function()
        world(w)
        if more then more() end
    end })
    stub.RunTimers()
    return DUI
end

local function DT() return stub.infopanel.DataTexts end

-- Friends and guild in slot 4 (the default puts the framerate there).
local function socialIn4(DUI)
    DUI:Set("InfoPanel", "data.slot4", "social")
    stub.RunTimers()
end

-- The texts without their color codes and icons, as a player reads them.
local function plain(s)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T[^|]*coin%-(%a+)%.png[^|]*|t", function(k) return k:sub(1, 1) end)
    return s
end
local function shown()
    local out = {}
    for _, s in ipairs(DT().slots) do
        if s:IsShown() then out[#out + 1] = plain(s.text:GetText() or "") end
    end
    return out
end
-- The client measures what shows, not the color codes: 5 px a letter for a 10 px font.
local function measureLikeTheGame()
    for _, s in ipairs(DT().slots) do
        s.text.GetStringWidth = function(self) return #plain(self:GetText() or "") * 5 end
    end
    DT().Layout()
end

local function hover(i)
    local s = DT().slots[i]
    s:GetScript("OnEnter")(s)
    return s
end

-- The tooltip's lines as text (left and right joined).
local function tipText()
    local out = {}
    for _, l in ipairs(GameTooltip.__lines or {}) do
        out[#out + 1] = plain(tostring(l[1] or "")) .. (l[2] and (" | " .. plain(tostring(l[2]))) or "")
    end
    return table.concat(out, "\n")
end

T.test("data texts: on by default, four texts in a strip under the minimap", function()
    local DUI = login()
    local P, D = stub.infopanel.Panel, DT()
    T.truthy(P.dataArea:IsShown(), "the strip shows for a player who never opens the options")
    T.eq(P.dataArea:GetParent(), P.panel, "inside the panel's frame (it fades with it)")
    local point, rel, relPoint, x, y = P.dataArea:GetPoint(1)
    T.eq(point, "TOPLEFT"); T.eq(rel, P.mapArea); T.eq(relPoint, "BOTTOMLEFT")
    T.eq(y, -P.PAD, "one padding under the map")
    T.eq(P.dataArea:GetWidth(), P.mapArea:GetWidth(), "as wide as the minimap")
    T.eq(#shown(), 4, "four texts")
    T.deq(D.keys, { "gold", "durability", "bags", "system" })
    T.eq(DUI:Get("InfoPanel", "map.fps.enabled"), false, "the framerate is in the strip, not beside the clock")
    -- Gold, the worst piece of gear, free slots in plain bags, the framerate.
    measureLikeTheGame()
    local t = shown()
    T.eq(t[1], "123g", "whole gold only")
    T.eq(t[2], "Gear 40%", "the most worn piece")
    T.eq(t[3], "Bags 10", "free slots in the plain bags (the profession bag apart)")
    T.truthy(t[4]:find("120 fps", 1, true), "the framerate: " .. t[4])
    socialIn4(DUI)
    measureLikeTheGame()
    T.eq(shown()[4], "Friends 2  Guild 2", "friends list + Battle.net, and the guild")
    -- The panel grew by the strip, and the meter reaches down beside it.
    local room = D.Room(DUI:GetModule("InfoPanel").db)
    T.eq(room, P.PAD + D.Height(10))
    DUI:Set("InfoPanel", "data.enabled", false)
    stub.RunTimers()
    local without = P.panel:GetHeight()
    T.falsy(P.dataArea:IsShown(), "switched off: gone")
    DUI:Set("InfoPanel", "data.enabled", true)
    stub.RunTimers()
    T.eq(P.panel:GetHeight(), without + room, "the panel is taller by the strip")
    T.eq(P.meterArea:GetHeight(), P.mapArea:GetHeight() + room, "the meter uses the room beside the strip")
end)

T.test("data texts: the words drop when the strip is too narrow, the numbers stay", function()
    local DUI = login()
    socialIn4(DUI)
    measureLikeTheGame()
    T.eq(shown()[2], "Gear 40%")
    DUI:Set("InfoPanel", "map.size", 120)
    stub.RunTimers()
    measureLikeTheGame()
    local t = shown()
    T.eq(t[2], "40%", "no word")
    T.eq(t[4], "2 · 2", "friends · guild")
    T.truthy(DT().short)
    DUI:Set("InfoPanel", "data.labels", false)
    DUI:Set("InfoPanel", "map.size", 300)
    stub.RunTimers()
    measureLikeTheGame()
    T.eq(shown()[3], "10", "words switched off: numbers only, however wide")
end)

T.test("data texts: a long text beside short ones is never cut while the strip has room", function()
    local DUI = login()
    DUI:Set("InfoPanel", "data.count", 5)
    DUI:Set("InfoPanel", "map.size", 300)
    stub.RunTimers()
    measureLikeTheGame()
    local D = DT()
    local sum = 0
    for i = 1, 5 do sum = sum + D.slots[i].w end
    T.eq(plain(D.slots[4].text:GetText()), "120 fps  45 ms", "room for the latency too")
    T.truthy(sum + 4 * D.MIN_GAP <= D.slots[1]:GetParent():GetWidth(), "everything fits side by side")
    for i = 1, 5 do
        local s = D.slots[i]
        T.truthy(s.text:GetWidth() >= s.text:GetStringWidth(),
            "slot " .. i .. " (" .. plain(s.text:GetText() or "") .. ") is as wide as its text")
    end
end)

T.test("data texts: each redraws on its own events, and only when it changed", function()
    local DUI = login()
    socialIn4(DUI)
    measureLikeTheGame()
    local D = DT()
    local layouts = 0
    local layout = D.Layout
    D.Layout = function() layouts = layouts + 1; return layout() end
    stub.money = 50000
    stub.FireEvent("PLAYER_MONEY")
    local d = DaylightUI.Motion.Driver()
    if d then stub.RunOnUpdate(d, 1) end   -- the count runs to its end
    T.eq(shown()[1], "5g")
    T.eq(layouts, 1, "laid out again: it says something else")
    stub.FireEvent("PLAYER_MONEY")
    T.eq(layouts, 1, "the same money again: nothing laid out")
    stub.gear[5] = { 10, 100 }
    stub.FireEvent("UPDATE_INVENTORY_DURABILITY")
    if d then stub.RunOnUpdate(d, 1) end
    T.eq(shown()[2], "Gear 10%")
    local v = D.slots[2].text:GetText()
    T.truthy(v:find(string.format("|cff%02x%02x%02x", math.floor(D.BAD[1] * 255 + 0.5),
        math.floor(D.BAD[2] * 255 + 0.5), math.floor(D.BAD[3] * 255 + 0.5)), 1, true), "about to break: red")
    stub.bags[0][2], stub.bags[1][2] = 0, 0
    stub.FireEvent("BAG_UPDATE_DELAYED")
    if d then stub.RunOnUpdate(d, 1) end
    T.eq(shown()[3], "Bags 0")
    stub.friends[2].connected = true
    stub.FireEvent("FRIENDLIST_UPDATE")
    if d then stub.RunOnUpdate(d, 1) end
    T.eq(shown()[4], "Friends 3  Guild 2")
    stub.inGuild = false
    stub.FireEvent("PLAYER_GUILD_UPDATE")
    if d then stub.RunOnUpdate(d, 1) end
    T.eq(shown()[4], "Friends 3", "no guild: friends only")
    D.Layout = layout
end)

T.test("data texts: a bag change reads the bags once, a durability change the gear once", function()
    login()
    local D = DT()
    local reads = { bags = 0, gear = 0 }
    local bags, gear = D.ReadBags, D.ReadDurability
    D.ReadBags = function(...) reads.bags = reads.bags + 1; return bags(...) end
    D.ReadDurability = function(...) reads.gear = reads.gear + 1; return gear(...) end
    stub.bags[0][2] = 0
    stub.FireEvent("BAG_UPDATE_DELAYED")
    T.eq(reads.bags, 1, "one walk of every bag per update")
    stub.gear[5] = { 10, 100 }
    stub.FireEvent("UPDATE_INVENTORY_DURABILITY")
    T.eq(reads.gear, 1)
    D.ReadBags, D.ReadDurability = bags, gear
end)

-- Runs the shared number tweens (the gold count) on by dt seconds.
local function tweens(dt)
    local d = DaylightUI.Motion.Driver()
    if d then stub.RunOnUpdate(d, dt or 1) end
end
local function hexOf(c)
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5))
end

T.test("data texts: gold counts to the new amount, gold while it rises, laid out once for the end", function()
    login()
    measureLikeTheGame()
    local D = DT()
    stub.money = 100000
    stub.FireEvent("PLAYER_MONEY")
    tweens()
    T.eq(shown()[1], "10g", "a loss counts down to its end")
    local layouts = 0
    local layout = D.Layout
    D.Layout = function() layouts = layouts + 1; return layout() end
    stub.money = 250000
    stub.FireEvent("PLAYER_MONEY")
    T.eq(layouts, 1, "laid out once, for the final amount")
    T.eq(shown()[1], "10g", "starts from what was on screen")
    T.truthy(D.slots[1].text:GetText():find(hexOf(D.GAIN), 1, true), "tinted gold while it rises")
    tweens(0.1)
    local mid = tonumber(shown()[1]:match("^(%d+)g$"))
    T.truthy(mid and mid > 10 and mid < 25, "partway: " .. tostring(shown()[1]))
    tweens(1)
    T.eq(shown()[1], "25g")
    T.falsy(D.slots[1].text:GetText():find(hexOf(D.GAIN), 1, true), "back to its own color")
    T.eq(layouts, 1, "never laid out per step")
    T.truthy(D.slots[1].text:GetWidth() >= D.slots[1].text:GetStringWidth(), "the text's width is back")
    D.Layout = layout
end)

T.test("data texts: with a gradient accent each text takes the next color along it, gold first", function()
    local DUI = login()
    local D, S, Hex = DT(), DUI.Style, DUI.Win.Parts.Hex
    DUI:Set("general", "accent", "gradient")
    stub.RunTimers()
    local function has(i, t)
        return D.slots[i].text:GetText():find(Hex({ S.SweepAt(t) }), 1, true)
    end
    T.truthy(has(1, 0), "gold starts the sweep: " .. D.slots[1].text:GetText())
    T.eq(D.slots[2].spot, 1 / 3, "the next is a third along (this gear is low: amber wins)")
    T.truthy(has(3, 2 / 3), "then two thirds: " .. D.slots[3].text:GetText())
    T.truthy(has(4, 1), "the last ends it: " .. D.slots[4].text:GetText())
    DUI:Set("general", "accent", "custom")
    DUI:Set("general", "accentColor", { 0.2, 0.6, 0.9 })
    stub.RunTimers()
    local one = Hex({ 0.2, 0.6, 0.9 })
    T.truthy(D.slots[3].text:GetText():find(one, 1, true) and D.slots[4].text:GetText():find(one, 1, true),
        "a one-color accent stays that one color")
end)

T.test("data texts: bags, gear and friends count to the new number, its color following; the slots beside glide", function()
    socialIn4(login())
    measureLikeTheGame()
    local D = DT()
    tweens()
    T.eq(shown()[3], "Bags 10")
    local glides = {}
    local glide = DaylightUI.Motion.Glide
    DaylightUI.Motion.Glide = function(f, dx, dy, dur) glides[f] = dx; return glide(f, dx, dy, dur) end
    stub.bags[0][2], stub.bags[1][2] = 0, 0   -- 10 free down to 0
    stub.FireEvent("BAG_UPDATE_DELAYED")
    T.eq(shown()[3], "Bags 10", "starts from what was on screen")
    tweens(0.08)
    local mid = tonumber(shown()[3]:match("^Bags (%d+)$"))
    T.truthy(mid and mid < 10 and mid > 0, "partway: " .. tostring(shown()[3]))
    tweens(1)
    T.eq(shown()[3], "Bags 0")
    T.truthy(D.slots[3].text:GetText():find(hexOf(D.BAD), 1, true), "full: red at the end")
    T.truthy(glides[D.slots[4]] and glides[D.slots[4]] ~= 0, "the narrower text pulls the next slot over, gliding")
    T.falsy(glides[D.slots[1]], "the slots before it stay")
    T.truthy(D.slots[3].text:GetWidth() >= D.slots[3].text:GetStringWidth(), "the text's width is back")
    DaylightUI.Motion.Glide = glide
    stub.inGuild = false
    stub.FireEvent("PLAYER_GUILD_UPDATE")
    tweens()
    T.eq(shown()[4], "Friends 2", "no guild: no number to count, at once")
end)

T.test("data texts: gold writes at once at login, in test mode and with motion off", function()
    local DUI = login({ money = 50000 })
    measureLikeTheGame()
    local D = DT()
    T.eq(shown()[1], "5g", "the first read: no count")
    DUI.SetTestMode(true)
    stub.RunTimers()
    T.eq(shown()[1], "123g", "the sample at once")
    DUI.SetTestMode(false)
    stub.RunTimers()
    T.eq(shown()[1], "5g", "the real amount again, at once")
    DUI.DB.General().motion = false
    stub.money = 250000
    stub.FireEvent("PLAYER_MONEY")
    T.eq(shown()[1], "25g", "motion off: at once")
    T.falsy(D.slots[1].text:GetText():find(hexOf(D.GAIN), 1, true), "and no tint")
    DUI.DB.General().motion = true
end)

T.test("data texts: slots are picked in the options; the clock-like ones tick only while shown", function()
    local DUI = login()
    local D = DT()
    local function live()
        local n = 0
        for _, t in ipairs(stub.tickers) do if not t.cancelled then n = n + 1 end end
        return n
    end
    local base = live()
    DUI:Set("InfoPanel", "data.count", 5)
    stub.RunTimers()
    T.deq(D.keys, { "gold", "durability", "bags", "system", "social" })
    measureLikeTheGame()
    T.eq(#shown(), 5)
    T.truthy(shown()[4]:find("120 fps", 1, true), "framerate")
    T.eq(live(), base, "the framerate (shown by default) is the one ticker")
    DUI:Set("InfoPanel", "data.slot4", "xp")
    stub.RunTimers()
    T.eq(live(), base - 1, "an event text instead: the ticker stops")
    measureLikeTheGame()
    T.eq(shown()[4], "XP 25%")
    DUI:Set("InfoPanel", "data.count", 3)
    stub.RunTimers()
    T.eq(#shown(), 3, "three slots")
    -- The menus past the count are hidden.
    local page
    for _, p in ipairs(stub.infopanel.OPTIONS.pages) do if p.id == "data" then page = p end end
    local get = function(k) return DUI:Get("InfoPanel", k) end
    local slotsCard = page.groups[2]
    T.falsy(slotsCard.items[3].hidden(get), "slot 3 shows")
    T.eq(slotsCard.items[4].hidden(get), true, "slot 4 hidden at three")
    for _, item in ipairs(slotsCard.items) do
        local values = item.choices()
        for _, k in ipairs(D.ORDER) do T.truthy(values[k], "every text in each menu: " .. k) end
    end
end)

T.test("data texts: the gold tooltip lists every character's gold and the total", function()
    local DUI = login()
    local chars = DUI.DB.Root().characters
    chars["Alt-Realm"] = { money = 20000, class = "MAGE" }
    chars["Bank-Realm"] = { money = 990000 }
    hover(1)
    local t = tipText()
    T.truthy(t:find("Gold", 1, true), t)
    T.truthy(t:find("This character", 1, true))
    T.eq(DUI.DB.Character().money, 1234567, "this character's gold is kept for the others")
    local a, b, c = t:find("Bank", 1, true), t:find("Alt", 1, true), t:find("All characters", 1, true)
    T.truthy(a and b and c, t)
    T.truthy(a < b, "richest first")
    T.truthy(t:find("Click: bags", 1, true))
    DT().slots[1]:GetScript("OnLeave")(DT().slots[1])
end)

T.test("data texts: the gold tooltip can count only the faction you're playing", function()
    local DUI = login()
    stub.units.player = stub.units.player or { name = "Tester", class = "WARRIOR" }
    stub.units.player.faction = "Horde"
    local chars = DUI.DB.Root().characters
    chars["Ally-Realm"] = { money = 50000, class = "MAGE", faction = "Alliance" }
    chars["Hordie-Realm"] = { money = 30000, class = "ROGUE", faction = "Horde" }
    hover(1)
    local t = tipText()
    T.truthy(t:find("Ally", 1, true) and t:find("Hordie", 1, true), "every character by default: " .. t)
    DT().slots[1]:GetScript("OnLeave")(DT().slots[1])
    DUI:Set("InfoPanel", "data.goldChars", "faction")
    stub.RunTimers()
    stub.infopanel.DataTexts.SaveMoney()
    T.eq(DUI.DB.Character().faction, "Horde", "your faction is kept with your gold")
    hover(1)
    t = tipText()
    T.falsy(t:find("Ally", 1, true), "the other faction left out: " .. t)
    T.truthy(t:find("Hordie", 1, true), t)
    T.truthy(t:find("All characters of this faction", 1, true), t)
    DT().slots[1]:GetScript("OnLeave")(DT().slots[1])
end)

-- A right-click on the gold text: the menu it opens, as asked for.
local function goldMenu(DUI)
    local menu
    local real = DUI.Widgets.OpenMenu
    DUI.Widgets.OpenMenu = function(owner, keys, values, _, onPick, _, opts)
        menu = { owner = owner, keys = keys, values = values, pick = onPick, opts = opts }
    end
    local s = DT().slots[1]
    s:GetScript("OnClick")(s, "RightButton")
    return menu, function() DUI.Widgets.OpenMenu = real end
end

T.test("data texts: a right-click on gold removes a deleted character from the totals", function()
    local DUI = login()
    local chars = DUI.DB.Root().characters
    chars["Alt-Realm"] = { money = 20000, class = "MAGE", install = "installed", profile = "Mine" }
    chars["Bank-Realm"] = { money = 990000 }
    hover(1)
    T.truthy(tipText():find("Right-click: remove a character", 1, true), tipText())
    local menu, restore = goldMenu(DUI)
    T.truthy(menu, "a list opens")
    T.eq(menu.owner, DT().slots[1])
    T.truthy(menu.values["Alt-Realm"]:find("Alt", 1, true))
    T.truthy(menu.opts.confirm["Alt-Realm"], "asks first")
    T.falsy(menu.values[DUI.DB.CharKey()], "never yourself")
    menu.pick("Alt-Realm")
    T.eq(chars["Alt-Realm"].money, nil, "their gold is gone")
    T.eq(chars["Alt-Realm"].profile, "Mine", "a character still around keeps their profile")
    hover(1)
    T.falsy(tipText():find("Alt", 1, true), tipText())
    restore()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("data texts: removing one asks first, stays open for the next and closes after the last", function()
    local DUI = login()
    local W = DUI.Widgets
    local chars = DUI.DB.Root().characters
    chars["Alt-Realm"] = { money = 20000, class = "MAGE" }
    chars["Bank-Realm"] = { money = 990000 }
    local s = DT().slots[1]
    s:GetScript("OnClick")(s, "RightButton")
    T.eq(W.MenuRow(1).text:GetText(), "REMOVE A CHARACTER")
    W.MenuRow(1):Click()
    W.MenuRow(2):Click()
    T.eq(chars["Alt-Realm"].money, 20000, "a heading and the hint do nothing")
    W.MenuRow(3):Click()
    T.eq(W.MenuRow(3).text:GetText(), "Click again")
    T.eq(chars["Alt-Realm"].money, 20000, "not yet")
    stub.Advance(1)
    W.MenuRow(3):Click()
    T.eq(chars["Alt-Realm"].money, nil, "gone on the second click")
    T.truthy(W.MenuRow(3).text:GetText():find("Bank", 1, true), "the next one moved up")
    T.eq(W.menuOwner, s, "still open")
    W.MenuRow(3):Click()
    stub.Advance(1)
    W.MenuRow(3):Click()
    T.eq(chars["Bank-Realm"].money, nil)
    T.eq(W.menuOwner, nil, "nothing left: closed")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("data texts: with no other character a right-click on gold just opens the bags", function()
    local DUI = login()
    hover(1)
    T.falsy(tipText():find("Right-click", 1, true), tipText())
    local menu, restore = goldMenu(DUI)
    restore()
    T.eq(menu, nil)
end)

T.test("data texts: gear, bags and social tooltips show the details", function()
    socialIn4(login())
    hover(2)
    local t = tipText()
    T.truthy(t:find("Chest | 40%", 1, true), t)
    T.truthy(t:find("Head | 90%", 1, true), t)
    hover(3)
    t = tipText()
    T.truthy(t:find("Pouch 2 (profession)", 1, true), t)
    T.truthy(t:find("Free | 10 / 36", 1, true), t)
    local asks = stub.rosterAsks
    hover(4)
    t = tipText()
    T.truthy(t:find("Sam (Thorn)", 1, true), "a Battle.net friend in game: " .. t)
    T.truthy(t:find("Ellie 60", 1, true), t)
    T.falsy(t:find("Away", 1, true), "offline friends left out")
    T.truthy(t:find("Dawnbreakers: 2 online", 1, true), t)
    T.truthy(t:find("Bram 60", 1, true), "realm cut off: " .. t)
    T.falsy(t:find("Dorn", 1, true), "offline members left out")
    T.truthy(stub.rosterAsks > asks, "asks the game for a fresh roster")
end)

-- A tooltip line by its left text.
local function tipLine(left)
    for _, l in ipairs(GameTooltip.__lines or {}) do
        if plain(tostring(l[1] or "")) == left then return l end
    end
end

T.test("data texts: tooltip words wear the accent; durability is graded green to red", function()
    local DUI = login()
    DUI:Set("general", "accent", "custom")
    DUI:Set("general", "accentColor", { 0.2, 0.6, 0.9 })
    local ar, ag, ab = DUI.Style.Accent()
    hover(2)
    local head, chest, main = tipLine("Head"), tipLine("Chest"), tipLine("Main hand")
    T.rgb(head.lc, DUI.Tips.TEXT, "a gear piece's name warm text")
    T.rgb(main.lc, DUI.Tips.TEXT, "every label the same one color")
    T.truthy(main.rc[2] > main.rc[1] and main.rc[2] > main.rc[3], "100% reads green")
    T.truthy(head.rc[2] > head.rc[3] and head.rc[2] >= head.rc[1] * 0.9, "90% still mostly green")
    T.truthy(chest.rc[1] > chest.rc[2] and chest.rc[1] > chest.rc[3], "40% leans amber to red")
    T.truthy(chest.rc[2] < head.rc[2], "more worn, less green")
    local hint = GameTooltip.__lines[#GameTooltip.__lines]
    T.truthy(plain(hint[1]):find("Click", 1, true), "the click hint is last")
    T.truthy(hint[1]:find(DUI.Win.Parts.Hex({ ar, ag, ab }), 1, true), "the hint's click in the accent")
    DUI:Set("general", "accent", "daylight")
    hover(2)
    local h2 = GameTooltip.__lines[#GameTooltip.__lines]
    T.truthy(h2[1]:find(DUI.Win.Parts.Hex({ DUI.Style.Accent() }), 1, true), "follows the accent when it changes")
end)

T.test("data texts: with the Daylight gradient accent the words run down the sweep, blue to orange", function()
    local DUI = login()
    DUI:Set("general", "accent", "gradient")
    local S = DUI.Style
    hover(2)
    local lines = GameTooltip.__lines
    T.rgb(lines[1].lc, { 1, 1, 1 }, "the title stays white")
    T.rgb(tipLine("Head").lc, DUI.Tips.TEXT, "labels stay warm text")
    local last = lines[#lines]
    T.truthy(last[1]:find(DUI.Win.Parts.Hex({ S.AccentAt(nil) }), 1, true), "the lone click hint takes the sweep's middle: " .. last[1])
    socialIn4(DUI)
    hover(4)
    local ellie = tipLine("Ellie 60")
    T.truthy(ellie.lc[1] ~= ellie.rc[1] or ellie.lc[3] ~= ellie.rc[3], "a friend's name stays its class color, the place the sweep")
end)

-- The game's guild window (Blizzard_Communities) is load-on-demand and pulls in
-- Blizzard_GuildControlUI (a dependency in its .toc), whose OnLoad calls the
-- protected C_Discord.IsUserOAuthed. ToggleGuildFrame from addon code loads them
-- under addon taint: "AddOn 'DaylightUI' tried to call the protected function
-- 'IsUserOAuthed()'". Once loaded, a toggle from addon code still runs the
-- window's OnShow tainted, and the guild settings' event handler is blocked for
-- the rest of the session. Only the player's own click (a secure
-- /click GuildMicroButton) may open it, loaded or not.
T.test("data texts: the guild window opens only through a secure click, loaded or not", function()
    local DUI = login()
    _G.ToggleGuildFrame = function()
        local loaded = stub.loadedAddOns["Blizzard_Communities"]
        stub.opened[#stub.opened + 1] = loaded and "guild" or "guild loaded by addon code"
    end
    socialIn4(DUI)
    DUI:Set("InfoPanel", "data.slot3", "guild")
    stub.RunTimers()
    local S = DT().slots
    S[4]:GetScript("OnClick")(S[4], "RightButton")
    S[3]:GetScript("OnClick")(S[3], "LeftButton")
    T.deq(stub.opened, {}, "never loaded from addon code")
    stub.loadedAddOns["Blizzard_Communities"] = true
    S[4]:GetScript("OnClick")(S[4], "RightButton")
    S[3]:GetScript("OnClick")(S[3], "LeftButton")
    T.deq(stub.opened, {}, "never toggled from addon code once loaded either")
    stub.loadedAddOns["Blizzard_Communities"] = nil
    for i = 3, 4 do S[i].GetLeft, S[i].GetBottom = function() return 1700 end, function() return 900 end end
    hover(3)
    local b = _G.DaylightUIDataGuild
    T.truthy(b and b:IsShown(), "a secure button over the guild text")
    T.eq(b:GetAttribute("macrotext1"), "/click GuildMicroButton")
    hover(4)
    T.eq(b:GetAttribute("macrotext2"), "/click GuildMicroButton", "social: a right-click is the guild")
    T.falsy(b:GetAttribute("type1"), "social: a left-click stays friends")
    b:GetScript("PostClick")(b, "LeftButton")
    T.deq(stub.opened, { "friends" })
    stub.EnterCombat()
    T.falsy(b:IsShown(), "gone as a fight starts")
    stub.LeaveCombat()
    stub.loadedAddOns["Blizzard_Communities"] = nil
end)

T.test("data texts: clicks open the matching window; character and social wait out combat", function()
    socialIn4(login())
    local S = DT().slots
    S[1]:GetScript("OnClick")(S[1], "LeftButton")
    S[2]:GetScript("OnClick")(S[2], "LeftButton")
    S[4]:GetScript("OnClick")(S[4], "LeftButton")
    S[4]:GetScript("OnClick")(S[4], "RightButton")
    T.deq(stub.opened, { "bags", "character:PaperDollFrame", "friends" }, "the guild opens only by the secure button")
    stub.opened = {}
    stub.EnterCombat()
    S[2]:GetScript("OnClick")(S[2], "LeftButton")
    S[4]:GetScript("OnClick")(S[4], "LeftButton")
    S[3]:GetScript("OnClick")(S[3], "LeftButton")
    T.deq(stub.opened, { "bags" }, "in combat only the bags open (the game refuses the others from addon code)")
    hover(2)
    T.truthy(tipText():find("(after combat)", 1, true), "the tooltip says so")
    stub.LeaveCombat()
end)

T.test("data texts: in combat a click opens Daylight UI's character window when it's on", function()
    socialIn4(login())
    local S = DT().slots
    local DUI = DaylightUI
    local was = DUI.Char.Follow
    local toggled = 0
    DUI.Char.Follow = { Ready = function() return true end, ToggleInFight = function() toggled = toggled + 1; return true end }
    stub.EnterCombat()
    S[2]:GetScript("OnClick")(S[2], "LeftButton")
    T.eq(toggled, 1, "ours opens now")
    T.deq(stub.opened, {}, "never the game's ToggleCharacter in a fight")
    hover(2)
    T.isnil(tipText():find("(after combat)", 1, true), "no 'after combat' when it opens now")
    stub.LeaveCombat()
    DUI.Char.Follow = was
end)

T.test("data texts: test mode shows a sample, warning colors included", function()
    local DUI = login()
    DUI.SetTestMode(true)
    stub.RunTimers()
    measureLikeTheGame()
    local t = shown()
    T.eq(t[2], "Gear 18%", "a worn sample")
    T.eq(t[3], "Bags 3")
    DUI.SetTestMode(false)
    stub.RunTimers()
    measureLikeTheGame()
    T.eq(shown()[2], "Gear 40%", "the real gear again")
end)

T.test("data texts: the game's tracker kept under the panel moves down with the strip", function()
    local DUI = login(nil, function()
        Enum.EditModeSystem = { ActionBar = 0, ObjectiveTracker = 12 }
        CreateFrame("Frame", "ObjectiveTrackerFrame", UIParent):SetSize(260, 600)
    end)
    local P, Tr = stub.infopanel.Panel, stub.infopanel.Tracker
    -- The panel hangs from the screen's top right, so its bottom follows its height.
    function P.panel:GetRight() return 1900 end
    function P.panel:GetBottom() return 1000 - self:GetHeight() end
    DUI:Set("InfoPanel", "data.enabled", false)
    stub.RunTimers()
    local pos = DUI.DB.Positions()
    -- Kept under the panel before the strip, as an old profile has it.
    local hx, hy = Tr.Home()
    T.truthy(hx, "the panel has a place")
    pos[Tr.MOVER] = { hx, hy }
    DUI:Set("InfoPanel", "data.enabled", true)
    stub.RunTimers()
    local room = DT().Room(DUI:GetModule("InfoPanel").db)
    local nx, ny = Tr.Home()
    T.near(ny, hy - room, 0.01, "the panel's bottom is lower by the strip")
    Tr.PlaceAnchor()
    T.near(pos[Tr.MOVER][2], ny, 0.01, "followed the strip down: the strip never covers the tracker")
    T.near(pos[Tr.MOVER][1], nx, 0.01)
    -- Moved somewhere else by hand, it stays.
    pos[Tr.MOVER] = { hx - 300, hy }
    Tr.PlaceAnchor()
    T.near(pos[Tr.MOVER][1], hx - 300, 0.01, "a hand-placed tracker stays")
    T.near(pos[Tr.MOVER][2], hy, 0.01)
end)

T.test("data texts: with the minimap off the strip spans the panel, under the meter", function()
    local DUI = login()
    local P = stub.infopanel.Panel
    DUI:Set("InfoPanel", "map.enabled", false)
    DUI:Set("InfoPanel", "meter.enabled", false)
    stub.RunTimers()
    T.truthy(P.panel:IsShown(), "the panel stays for the strip alone")
    T.truthy(P.dataArea:IsShown())
    local m = DUI:Get("InfoPanel", "meter.width")
    T.eq(P.dataArea:GetWidth(), m, "as wide as the meter would be")
    local point, rel = P.dataArea:GetPoint(1)
    T.eq(point, "BOTTOMLEFT"); T.eq(rel, P.panel)
    measureLikeTheGame()
    T.eq(#shown(), 4)
end)

T.test("data texts: secret names in the friends list are left out, nothing errors", function()
    socialIn4(login())
    stub.friends[1].name = stub.Secret("Ellie")
    stub.friends[1].connected = stub.Secret(true)
    local errors = 0
    local real = DaylightUI.SafeCall
    DaylightUI.SafeCall = function(fn, ...)
        local ok = pcall(fn, ...)
        if not ok then errors = errors + 1 end
    end
    hover(4)
    local t = tipText()
    T.falsy(t:find("Ellie", 1, true), "a secret name isn't shown")
    T.truthy(t:find("Sam (Thorn)", 1, true), "the rest still lists")
    T.eq(errors, 0)
    DaylightUI.SafeCall = real
end)

-- Translations: every word a text or its tooltip shows comes through L (a pseudo
-- language wraps each in «»). What's left is the game's or a name.
T.test("data texts: every text and tooltip line is translated (pseudo language)", function()
    local DUI = stub.Load({ infopanel = true, before = world, locale = function(L)
        setmetatable(L, { __index = function(_, k) return "«" .. tostring(k) .. "»" end })
    end })
    stub.RunTimers()
    local NAMES = { "Ellie", "Sam", "Thorn", "Duskwood", "Elwynn", "Bram", "Cass", "Dawnbreakers", "Ironforge",
                    "Darnassus", "Backpack", "Pouch", "fps", "ms" }   -- the fake game's names and places, and units
    local function leftover(s)
        s = tostring(s or ""):gsub("«[^«»]*»", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
        for _, n in ipairs(NAMES) do s = s:gsub(n, "") end
        return s:find("%a%a") and s or nil
    end
    local bad = {}
    for _, sampleOn in ipairs({ false, true }) do
        DUI.SetTestMode(sampleOn)
        stub.RunTimers()
        for _, key in ipairs(DT().ORDER) do
            local t = DT().TEXTS[key]
            local long, short = t.text()
            if leftover(long) or leftover(short) then bad[#bad + 1] = key .. ": " .. long end
            GameTooltip:SetOwner(UIParent)
            t.tip()
            for _, l in ipairs(GameTooltip.__lines) do
                for _, side in ipairs({ l[1], l[2] }) do
                    if leftover(side) then bad[#bad + 1] = key .. " tooltip: " .. tostring(side) end
                end
            end
        end
    end
    T.eq(table.concat(bad, "\n"), "")
end)

T.test("data texts: a number that matters pops in the accent, and follows an accent switch", function()
    local DUI = login()
    local D = DT()
    DUI:Set("general", "accent", "custom")
    DUI:Set("general", "accentColor", { 0.2, 0.6, 0.9 })
    stub.RunTimers()
    local bags = D.slots[3].text:GetText()
    T.truthy(bags:find(hexOf({ 0.2, 0.6, 0.9 }), 1, true), "free bag slots in the accent: " .. bags)
    DUI:Set("general", "accentColor", { 0.9, 0.3, 0.1 })
    stub.RunTimers()
    T.truthy(D.slots[3].text:GetText():find(hexOf({ 0.9, 0.3, 0.1 }), 1, true), "repainted with the new accent")
end)

-- The data bar along the bottom of the screen.

local function bar() return stub.infopanel.DataBar end
local function barOn(DUI, key, value)
    DUI:Set("InfoPanel", key or "databar.enabled", value == nil and true or value)
    stub.RunTimers()
end
local function keysOf(strip)
    local out = {}
    for _, k in ipairs(strip.keys or {}) do out[#out + 1] = k end
    return table.concat(out, ",")
end

T.test("data bar: off by default, nothing listened to and no room taken", function()
    local DUI = login()
    T.eq(DUI:Get("InfoPanel", "databar.enabled"), false)
    T.falsy(bar().frame:IsShown(), "no bar")
    T.eq(bar().left.keys, nil, "no strip awake")
    T.eq(DUI.Movers.BottomRoom(), 0)
    T.eq(DUI.Movers.Above(12), 12, "the bottom pieces stay where they were")
end)

T.test("data bar: the clock in the middle, the texts on both sides, the panel's strip untouched", function()
    local DUI = login()
    local before = shown()
    barOn(DUI)
    T.truthy(bar().frame:IsShown())
    T.eq(keysOf(bar().left), "location,coords,xp,durability")
    T.eq(keysOf(bar().center), "time")
    T.eq(keysOf(bar().right), "bags,social,gold,system")
    T.truthy(bar().right.slots[3].text:GetText() ~= nil, "gold drawn")
    T.eq(table.concat(shown(), "|"), table.concat(before, "|"), "the panel's strip is its own")
end)

T.test("data bar: Framerate and latency shows the latency too, words off", function()
    local DUI = login()
    barOn(DUI)
    T.eq(DUI:Get("InfoPanel", "databar.labels"), false, "words off by default")
    T.eq(plain(bar().right.slots[4].text:GetText()), "120 fps · 45 ms")
end)

T.test("data bar: every slot is the player's, None leaves it out and the rest share the room", function()
    local DUI = login()
    barOn(DUI)
    barOn(DUI, "databar.left2", "none")
    barOn(DUI, "databar.right1", "guild")
    T.eq(keysOf(bar().left), "location,xp,durability")
    T.eq(keysOf(bar().right), "guild,social,gold,system")
    T.falsy(bar().left.slots[4]:IsShown(), "the emptied slot's frame goes")
    barOn(DUI, "databar.center", "none")
    T.falsy(bar().tab:IsShown(), "no middle text, no tab")
    T.eq(keysOf(bar().center), "", "and its strip sleeps")
    local all = { "left1", "left3", "left4", "right1", "right2", "right3", "right4" }
    for _, k in ipairs(all) do barOn(DUI, "databar." .. k, "none") end
    T.falsy(bar().left.slots[1]:IsShown(), "an all-empty side shows nothing")
end)

T.test("data bar: bottom pieces never moved glide above it, ones the player placed stay", function()
    local DUI = login()
    local M = DUI.Movers
    M.Register(CreateFrame("Frame", nil, UIParent), "t.free", "Free", function() return { "BOTTOM", nil, "BOTTOM", 0, M.Above(12) } end, { bottom = true })
    local placed = CreateFrame("Frame", nil, UIParent)
    M.Register(placed, "t.placed", "Placed", function() return { "BOTTOM", nil, "BOTTOM", 0, M.Above(12) } end, { bottom = true })
    DUI.DB.Positions()["t.placed"] = { 100, -200 }
    M.Apply("t.placed")
    stub.RunTimers()
    barOn(DUI)
    T.eq(M.BottomRoom(), 24)
    T.eq(M.Get("t.free").default()[5], 24 + M.ROOM_GAP, "a default spot rises")
    T.eq(select(4, placed:GetPoint()), 100, "a placed piece is left alone")
    barOn(DUI, "databar.widthPct", 30)
    T.eq(M.BottomRoom(), 0, "a bar that leaves the corners free takes no room")
end)

T.test("data bar: 60% of the screen, centered, angled at both ends, its width a slider, with a handle", function()
    local DUI = login()
    barOn(DUI)
    T.eq(bar().frame:GetWidth(), math.floor(UIParent:GetWidth() * 0.6))
    T.eq(select(3, bar().frame:GetPoint()), "BOTTOM", "centered on the bottom edge")
    T.eq(DUI.Style.GetSlant(bar().body).side, "both", "angled ends")
    T.eq(DUI.Movers.Get(bar().KEY).suspended, false, "a handle")
    barOn(DUI, "databar.widthPct", 80)
    T.eq(bar().frame:GetWidth(), math.floor(UIParent:GetWidth() * 0.8))
end)

T.test("data bar: the accent line can be turned off", function()
    local DUI = login()
    barOn(DUI)
    T.truthy(bar().line:IsShown(), "on by default")
    barOn(DUI, "databar.line", false)
    T.falsy(bar().line:IsShown(), "off")
end)

T.test("data bar: angled ends are a switch, the border a slider from none", function()
    local DUI = login()
    barOn(DUI)
    local shell = DUI.Style.GetShell(bar().body)
    T.eq(shell.opts.noBorder, true, "no border by default")
    barOn(DUI, "databar.borderAlpha", 0.4)
    T.eq(shell.opts.noBorder, false, "a border")
    T.eq(shell.opts.borderAlpha, 0.4)
    barOn(DUI, "databar.angled", false)
    T.eq(DUI.Style.GetSlant(bar().body).side, nil, "straight ends")
    barOn(DUI, "databar.angled", true)
    T.eq(DUI.Style.GetSlant(bar().body).side, "both", "angled again")
end)

T.test("data bar: fade until mouseover fades it, the mouse brings it back", function()
    local DUI = login()
    barOn(DUI)
    tweens()
    local F = DUI.Fade
    local function settle()
        F.Step()
        for _ = 1, 120 do stub.RunOnUpdate(F.driver, 1 / 60) end
    end
    DUI:Set("InfoPanel", "databar.fade.mode", "always")
    DUI:Set("InfoPanel", "databar.fade.delay", 0)
    stub.RunTimers()
    settle()
    T.eq(bar().frame:GetAlpha(), 0, "faded")
    bar().frame.IsMouseOver = function() return true end
    stub.Advance(3)
    settle()
    T.eq(bar().frame:GetAlpha(), 1, "back under the mouse")
end)

T.test("data bar: its own background opacity", function()
    local DUI = login()
    barOn(DUI)
    barOn(DUI, "databar.alphaOwn", true)
    barOn(DUI, "databar.alpha", 0.3)
    T.eq(DUI.Style.GetShell(bar().body).opts.bgAlpha, 0.3)
end)

T.test("data bar: it slides up on, down off, and only then stops listening", function()
    local DUI = login()
    barOn(DUI)
    T.truthy(DUI.Motion.On(), "motion on")
    T.truthy(bar().slid > 0, "it starts below the edge")
    tweens()
    T.eq(bar().slid, 0, "and comes to rest")
    local slid
    DUI:Set("InfoPanel", "databar.enabled", false)
    T.truthy(bar().frame:IsShown(), "still sliding out")
    tweens()
    slid = bar().frame:IsShown()
    T.falsy(slid, "gone at the end")
    T.eq(bar().left.keys, nil, "its strips asleep")
    T.eq(bar().slid, 0, "back at rest for next time")
end)

T.test("data bar: an icon before each text along the accent, labels a switch, the panel's strip has none", function()
    local DUI = login()
    barOn(DUI)
    local bags, gold = bar().right.slots[1], bar().right.slots[3]
    T.truthy(bags.icon:IsShown(), "bags has its icon")
    T.truthy(tostring(bags.icon:GetTexture()):find("ui-data-bags.png", 1, true), "its own art")
    T.falsy(gold.icon:IsShown(), "gold's text ends in its coin")
    T.truthy(bar().center.slots[1].icon:IsShown(), "the clock too")
    T.falsy(bags.text:GetText():find("Bags", 1, true), "no label by default")
    for _, k in ipairs({ "right2", "right3", "right4" }) do barOn(DUI, "databar." .. k, "none") end
    barOn(DUI, "databar.labels", true)
    T.truthy(bags.text:GetText():find("Bags", 1, true), "the label comes back beside the icon")
    T.truthy(bags.icon:IsShown(), "and the icon stays")
    barOn(DUI, "databar.icons", false)
    T.falsy(bags.icon:IsShown(), "icons off")
    T.eq(bags.iconW, 0, "and their room freed")
    for _, s in ipairs(stub.infopanel.DataTexts.slots) do T.falsy(s.icon:IsShown(), "none on the panel's strip") end
end)

T.test("data bar: the hover light finds the text and leaves with the mouse", function()
    local DUI = login()
    barOn(DUI)
    local s = bar().right.slots[3]
    s.GetLeft, s.GetRight = function() return 1000 end, function() return 1100 end
    bar().body.GetLeft = function() return 0 end
    s:GetScript("OnEnter")(s)
    T.truthy(bar().light:IsShown(), "lit")
    T.eq(bar().light.x + bar().light.w / 2, 1050, "centered on the text")
    s:GetScript("OnLeave")(s)
    tweens()
    T.falsy(bar().light:IsShown(), "out with the mouse")
end)

T.test("data texts: bags open close through Daylight UI's bag, never the game's toggle", function()
    local DUI = login()
    local S = DT().slots
    local bag = CreateFrame("Frame", "DaylightUIBag", UIParent)
    bag:Show()
    S[1]:GetScript("OnClick")(S[1], "LeftButton")
    T.deq(stub.opened, {}, "ToggleAllBags from addon code taints the game's who-opened-the-bags local")
    bag:Hide()
    S[1]:GetScript("OnClick")(S[1], "LeftButton")
    T.deq(stub.opened, { "bags" })
    _G.DaylightUIBag = nil
end)

T.test("data texts: combat says in or out of a fight at once, the tooltip times the last one", function()
    local DUI = login()
    DUI:Set("InfoPanel", "data.slot4", "combat")
    stub.RunTimers()
    measureLikeTheGame()
    T.eq(shown()[4], "Out of combat")
    stub.SetTime(nil, 100)
    stub.EnterCombat()
    T.eq(shown()[4], "In combat", "the event says it: the lockdown isn't on yet inside it in game")
    stub.SetTime(nil, 183)
    stub.LeaveCombat()
    T.eq(shown()[4], "Out of combat")
    hover(4)
    T.truthy(tipText():find("Last fight | 1:23", 1, true), tipText())
end)

-- The game's sound settings as plain CVars. A write fires CVAR_UPDATE.
local function sound(cvars)
    _G.C_CVar = _G.C_CVar or {}
    local oldGet, oldSet = _G.C_CVar.GetCVar, _G.C_CVar.SetCVar
    _G.C_CVar.GetCVar = function(k) return cvars[k] end
    _G.C_CVar.SetCVar = function(k, v)
        cvars[k] = tostring(v)
        stub.FireEvent("CVAR_UPDATE", k, cvars[k])
        return true
    end
    return function() _G.C_CVar.GetCVar, _G.C_CVar.SetCVar = oldGet, oldSet end
end

T.test("data texts: volume turns with the wheel, a click mutes all sound, a right-click picks the channel", function()
    local cvars = { Sound_MasterVolume = "0.6", Sound_EnableAllSound = "1", Sound_MusicVolume = "0.3",
                    Sound_EnableMusic = "1" }
    local undo = sound(cvars)
    local DUI = login()
    DUI:Set("InfoPanel", "data.slot4", "volume")
    stub.RunTimers()
    measureLikeTheGame()
    local s = DT().slots[4]
    T.eq(shown()[4], "Volume 60%")
    T.truthy(s:IsMouseWheelEnabled(), "the volume slot takes the wheel")
    T.falsy(DT().slots[1]:IsMouseWheelEnabled(), "gold leaves it to the camera")
    s:GetScript("OnMouseWheel")(s, 1)
    T.eq(cvars.Sound_MasterVolume, "0.65")
    T.eq(shown()[4], "Volume 65%", "redrawn from the game's CVAR_UPDATE")
    for _ = 1, 20 do s:GetScript("OnMouseWheel")(s, 1) end
    T.eq(cvars.Sound_MasterVolume, "1.00", "never past full")
    s:GetScript("OnClick")(s, "LeftButton")
    T.eq(cvars.Sound_EnableAllSound, "0")
    T.eq(shown()[4], "Volume Muted")
    hover(4)
    T.truthy(tipText():find("Click: sound back on", 1, true), tipText())
    s:GetScript("OnClick")(s, "LeftButton")
    T.eq(cvars.Sound_EnableAllSound, "1")
    -- Right-click opens the channel menu. With music picked, the wheel turns music.
    local W = DUI.Widgets
    s:GetScript("OnClick")(s, "RightButton")
    W.MenuRow(3):Click()
    T.eq(DUI:Get("InfoPanel", "data.volumeChannel"), "music")
    T.eq(shown()[4], "Music 30%", "redrawn at once, in a fight too")
    s:GetScript("OnMouseWheel")(s, -1)
    T.eq(cvars.Sound_MusicVolume, "0.25")
    T.eq(cvars.Sound_MasterVolume, "1.00", "master left alone")
    undo()
end)

T.test("data texts: item level shows what you wear, the tooltip the best in your bags", function()
    local DUI = login(nil, function() _G.GetAverageItemLevel = function() return 64.7, 61.2 end end)
    DUI:Set("InfoPanel", "data.slot4", "ilvl")
    stub.RunTimers()
    measureLikeTheGame()
    T.eq(shown()[4], "Item level 61")
    hover(4)
    T.truthy(tipText():find("Best in your bags | 64", 1, true), tipText())
    _G.GetAverageItemLevel = nil
end)

T.test("data texts: crit keeps its last plain number while a fight hides it; shards count the bag's", function()
    local crit = 12.5
    local DUI = login(nil, function()
        _G.GetCritChance = function() return crit end
        _G.GetItemCount = function(id) return id == 6265 and 7 or 0 end
    end)
    DUI:Set("InfoPanel", "data.slot4", "crit")
    DUI:Set("InfoPanel", "data.slot3", "shards")
    stub.RunTimers()
    measureLikeTheGame()
    T.eq(shown()[4], "Crit 12.50%")
    T.eq(shown()[3], "Shards 7")
    crit = stub.Secret(30)
    stub.FireEvent("COMBAT_RATING_UPDATE")
    T.eq(shown()[4], "Crit 12.50%", "a secret is never shown or compared: the last plain one stays")
    _G.GetCritChance, _G.GetItemCount = nil, nil
end)

T.test("data texts: a right-click on crit picks which crit it shows (a melee hybrid wants attack crit)", function()
    local DUI = login(nil, function()
        _G.GetCritChance = function() return 12.5 end
        _G.GetSpellCritChance = function() return 5 end
    end)
    DUI:Set("InfoPanel", "data.slot4", "crit")
    stub.RunTimers()
    measureLikeTheGame()
    local s = DT().slots[4]
    local W = DUI.Widgets
    s:GetScript("OnClick")(s, "RightButton")
    W.MenuRow(4):Click()
    T.eq(DUI:Get("InfoPanel", "data.critKind"), "spell")
    T.eq(shown()[4], "Crit 5.00%", "redrawn at once")
    hover(4)
    T.truthy(tipText():find("Right-click: pick which crit", 1, true), tipText())
    s:GetScript("OnClick")(s, "RightButton")
    W.MenuRow(2):Click()
    T.eq(shown()[4], "Crit 12.50%")
    _G.GetCritChance, _G.GetSpellCritChance = nil, nil
end)

T.test("data texts: AP shows for a caster class (its stat group has no attack power) and a right-click picks ranged", function()
    local DUI = login(nil, function()
        stub.units.player = stub.units.player or { name = "Tester" }
        stub.units.player.class = "SHAMAN"
        _G.UnitAttackPower = function() return 400, 8, 0 end
        _G.UnitRangedAttackPower = function() return 30, 1, 0 end
    end)
    DUI:Set("InfoPanel", "data.slot4", "ap")
    stub.RunTimers()
    measureLikeTheGame()
    T.eq(shown()[4], "AP 408", "a shaman's group is spell, which has no AP: attack power, not a dash")
    local s = DT().slots[4]
    s:GetScript("OnClick")(s, "RightButton")
    DUI.Widgets.MenuRow(3):Click()
    T.eq(DUI:Get("InfoPanel", "data.apKind"), "ranged")
    T.eq(shown()[4], "AP 31", "redrawn at once")
    hover(4)
    T.truthy(tipText():find("Right-click: pick which attack power", 1, true), tipText())
    _G.UnitAttackPower, _G.UnitRangedAttackPower = nil, nil
    stub.units.player.class = nil
end)

T.test("data texts: ammo and shards count up and down to the new number; ammo hears only your own shots", function()
    local ammo, uses, shards = 400, true, 2
    local DUI = login(nil, function()
        _G.UnitUsesAmmo = function() return uses end
        _G.GetInventorySlotInfo = function(name) if name == "AmmoSlot" then return 0, "empty" end end
        _G.GetInventoryItemTexture = function(_, id) if id == 0 and ammo > 0 then return "icon:arrow" end end
        _G.GetInventoryItemCount = function(_, id) return id == 0 and (ammo > 0 and ammo or 1) or 0 end
        _G.GetItemCount = function(id) return id == 6265 and shards or 0 end
    end)
    DUI:Set("InfoPanel", "data.slot3", "ammo")
    DUI:Set("InfoPanel", "data.slot4", "shards")
    stub.RunTimers()
    measureLikeTheGame()
    local D = DT()
    tweens()
    T.eq(shown()[3], "Ammo 400")
    T.eq(shown()[4], "Shards 2")
    ammo = 0
    stub.FireEvent("UNIT_INVENTORY_CHANGED", "party1")
    T.eq(shown()[3], "Ammo 400", "a party member's gear never redraws it")
    stub.FireEvent("UNIT_INVENTORY_CHANGED", "player")
    T.eq(shown()[3], "Ammo 400", "starts from what was on screen")
    tweens(0.08)
    local mid = tonumber(shown()[3]:match("^Ammo (%d+)$"))
    T.truthy(mid and mid < 400 and mid > 0, "counts down: " .. tostring(shown()[3]))
    tweens(1)
    T.eq(shown()[3], "Ammo 0", "an empty slot is none left, not the game's false 1")
    T.truthy(D.slots[3].text:GetText():find(hexOf(D.BAD), 1, true), "out: red")
    shards = 9
    stub.FireEvent("BAG_UPDATE_DELAYED")
    T.eq(shown()[4], "Shards 2", "starts from what was on screen")
    tweens(0.08)
    mid = tonumber(shown()[4]:match("^Shards (%d+)$"))
    T.truthy(mid and mid > 2 and mid < 9, "counts up: " .. tostring(shown()[4]))
    tweens(1)
    T.eq(shown()[4], "Shards 9")
    uses = false
    stub.FireEvent("PLAYER_EQUIPMENT_CHANGED")
    tweens(1)
    T.eq(shown()[3], "Ammo -", "a class or weapon that shoots none")
    _G.UnitUsesAmmo, _G.GetInventorySlotInfo, _G.GetInventoryItemTexture = nil, nil, nil
    _G.GetInventoryItemCount, _G.GetItemCount = nil, nil
end)

T.test("data texts: time played asks the game once, the chat windows skip that answer", function()
    local asked = 0
    local DUI = login(nil, function()
        _G.RequestTimePlayed = function()
            asked = asked + 1
            stub.chatHeard = ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG")
        end
        local cf = CreateFrame("Frame", "ChatFrame1", UIParent)
        cf:RegisterEvent("TIME_PLAYED_MSG")
    end)
    DUI:Set("InfoPanel", "data.slot4", "played")
    stub.RunTimers()
    measureLikeTheGame()
    T.eq(asked, 1)
    T.eq(stub.chatHeard, false, "off while we ask: the game's chat would print the answer")
    T.eq(shown()[4], "Played -")
    stub.FireEvent("TIME_PLAYED_MSG", 2 * 86400 + 5 * 3600, 3 * 3600 + 120)
    stub.RunTimers()
    T.truthy(ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"), "back on after the answer: a /played of yours still prints")
    T.eq(shown()[4], "Played 2d 5h")
    for _ = 1, 4 do DT().Update(true) end
    T.eq(asked, 1, "asked once, then counted by the clock")
    hover(4)
    T.truthy(tipText():find("This level | 3h 2m", 1, true), tipText())
    _G.RequestTimePlayed, _G.ChatFrame1 = nil, nil
end)

T.test("data texts: professions show the primaries' skill; a click opens the last used, a right-click picks", function()
    local opened = {}
    local DUI = login(nil, function()
        _G.GetProfessions = function() return 1, 2, nil, nil, 3 end
        local info = { { "Tailoring", 245, 300, 197 }, { "Herbalism", 120, 150, 182 }, { "Cooking", 75, 75, 185 } }
        _G.GetProfessionInfo = function(i) local p = info[i] return p[1], 0, p[2], p[3], 0, 0, p[4] end
        _G.C_TradeSkillUI = _G.C_TradeSkillUI or {}
        _G.C_TradeSkillUI.OpenTradeSkill = function(line) opened[#opened + 1] = line end
    end)
    DUI.Craft.Data.Tabs = function()
        return { { skillLine = 197, name = "Tailoring" }, { skillLine = 185, name = "Cooking" } }
    end
    DUI:Set("InfoPanel", "data.slot4", "professions")
    stub.RunTimers()
    measureLikeTheGame()
    T.eq(shown()[4], "245 · 120", "the two primaries (the words drop on a narrow strip)")
    hover(4)
    T.truthy(tipText():find("Cooking | 75 / 75", 1, true), tipText())
    local s = DT().slots[4]
    DUI.DB.Character().craftLast = 185
    s:GetScript("OnClick")(s, "LeftButton")
    T.deq(opened, { 185 }, "the one used last")
    s:GetScript("OnClick")(s, "RightButton")
    DUI.Widgets.MenuRow(1):Click()
    T.deq(opened, { 185, 197 })
    _G.GetProfessions, _G.GetProfessionInfo = nil, nil
end)

T.test("data texts: hearthstone shows home and its cooldown; out of combat a secure button over it uses it", function()
    local cd = { 0, 0 }
    local DUI = login(nil, function()
        _G.GetBindLocation = function() return "Goldshire" end
        _G.C_Container.GetItemCooldown = function() return cd[1], cd[2], 1 end
        _G.C_Item = _G.C_Item or {}
        _G.C_Item.GetItemCount = function(id) return id == 6948 and 1 or 0 end
    end)
    DUI:Set("InfoPanel", "data.slot4", "hearth")
    stub.RunTimers()
    measureLikeTheGame()
    T.eq(shown()[4], "Goldshire")
    cd[1], cd[2] = GetTime(), 1.5   -- the global cooldown, which an item reports too
    DT().Update(true)
    T.eq(shown()[4], "Goldshire", "the global cooldown isn't the hearth's own")
    cd[1], cd[2] = GetTime() - 600, 3600
    DT().Update(true)
    T.eq(shown()[4], "Goldshire 50:00", "the time left, ticking")
    local sl = DT().slots[4]
    sl.GetLeft, sl.GetBottom = function() return 1700 end, function() return 900 end   -- the fake game lays nothing out
    hover(4)
    local b = _G.DaylightUIDataHearth
    T.truthy(b and b:IsShown(), "a secure button over the slot")
    T.eq(b:GetAttribute("macrotext1"), "/use item:6948")
    stub.EnterCombat()
    T.falsy(b:IsShown(), "gone as a fight starts: an invisible button would use it on any click there")
    stub.LeaveCombat()
    _G.GetBindLocation, _G.C_Item.GetItemCount = nil, nil
end)

-- LibDataBroker-1.1 as the real one works: objects behind a proxy, where every
-- attribute write fires LibDataBroker_AttributeChanged.
local function fakeBroker()
    local lib = { objects = {}, cbs = {} }
    -- LibStub's real shape, since the fake game loads no libraries.
    _G.LibStub = setmetatable({ libs = { ["LibDataBroker-1.1"] = lib },
        GetLibrary = function(self, name) return self.libs[name] end,
    }, { __call = function(self, name) return self.libs[name] end })
    function lib.RegisterCallback(owner, event, fn) lib.cbs[event] = lib.cbs[event] or {}; table.insert(lib.cbs[event], fn) end
    local function fire(event, ...) for _, fn in ipairs(lib.cbs[event] or {}) do fn(event, ...) end end
    function lib:NewDataObject(name, data)
        local store = data
        local proxy = setmetatable({}, { __index = store, __newindex = function(_, k, v)
            if store[k] == v then return end
            store[k] = v
            fire("LibDataBroker_AttributeChanged", name, k, v, lib.objects[name])
        end })
        lib.objects[name] = proxy
        fire("LibDataBroker_DataObjectCreated", name, proxy)
        return proxy
    end
    function lib:DataObjectIterator() return pairs(lib.objects) end
    return lib
end

T.test("data texts: another addon's broker object sits in a slot, follows its changes, gets its clicks", function()
    local clicked
    local DUI = login()
    local lib = fakeBroker()   -- the library comes with another addon
    lib:NewDataObject("Early", { type = "data source", label = "Early", text = "7" })
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    T.truthy(DT().TEXTS["ldb:Early"], "one made before the look at login")
    -- Saved in a slot before its addon made it: empty, then there once it is.
    DUI:Set("InfoPanel", "data.slot4", "ldb:Later")
    stub.RunTimers()
    measureLikeTheGame()
    T.eq(#shown(), 3, "not made yet: the slot waits")
    local obj = lib:NewDataObject("Later", { type = "data source", label = "Later", text = "12 kills", icon = "Interface/Icons/Later",
        OnClick = function(frame, button) clicked = button end,
        OnTooltipShow = function(tip) tip:AddLine("From the addon") end })
    stub.RunTimers()
    measureLikeTheGame()
    T.eq(#shown(), 4, "made: the strip lays out with it")
    T.truthy(shown()[4]:find("12 kills", 1, true), shown()[4])
    obj.text = "13 kills"
    obj.text = "14 kills"
    stub.RunTimers()
    T.truthy(shown()[4]:find("14 kills", 1, true), "changes gathered, then redrawn")
    hover(4)
    T.truthy(tipText():find("From the addon", 1, true), tipText())
    local s = DT().slots[4]
    s:GetScript("OnClick")(s, "RightButton")
    T.eq(clicked, "RightButton", "its own OnClick")
    -- In the menus with the built-in ones.
    local page
    for _, p in ipairs(stub.infopanel.OPTIONS.pages) do if p.id == "data" then page = p end end
    local names = page.groups[2].items[1].choices()
    T.eq(names["ldb:Later"], "Later")
    _G.LibStub = nil
end)

T.test("data texts: speed shows how fast you go, your run speed standing still, the last plain one in a fight", function()
    local now, run, swimming = 0, 7, false
    local DUI = login(nil, function()
        _G.GetUnitSpeed = function(unit)
            assert(unit == "player")
            return now, run, 0, 4.72
        end
        _G.IsSwimming = function() return swimming end
        _G.IsFlying = function() return false end
    end)
    DUI:Set("InfoPanel", "data.slot3", "speed")
    stub.RunTimers()
    measureLikeTheGame()
    T.eq(shown()[3], "Speed 100%", "standing still: a normal run")
    run = 11.2   -- mounted, 60%
    DT().Update(true)
    T.eq(shown()[3], "Speed 160%", "on a mount: the mount's speed")
    now = 4.5    -- walking
    DT().Update(true)
    T.eq(shown()[3], "Speed 64%", "moving: how fast you go now")
    now, swimming = 0, true
    DT().Update(true)
    T.eq(shown()[3], "Speed 67%", "in the water, still: swim speed")
    now, run = stub.Secret(14), stub.Secret(14)
    DT().Update(true)
    T.eq(shown()[3], "Speed 67%", "a secret is never shown or compared: the last plain one stays")
    _G.GetUnitSpeed, _G.IsSwimming, _G.IsFlying = nil, nil, nil
end)
