local stub = require("stub")
local SW = require("socialworld")

-- The social window.

local function load(spec)
    stub.Load({ before = SW.world(spec) })
    return stub.social
end

-- A frame of the world: timers, the follower's look, the moves.
local function frame(n)
    for _ = 1, n or 1 do
        stub.RunTimers()
        DaylightUI.Win.Followers.Tick()
        local d = DaylightUI.Win.Feel.Driver()
        if d then stub.RunOnUpdate(d, 1 / 30) end
        local m = DaylightUI.Motion.Driver()
        if m then stub.RunOnUpdate(m, 1 / 30) end
        local raid = stub.social and stub.social.Raid and stub.social.Raid.page
        if raid and raid:IsVisible() then stub.RunOnUpdate(raid, 1 / 30) end   -- its watcher, as the game runs it
    end
end

-- O (the game's ToggleFriendsFrame) opens ours.
local function open(ns, tab)
    SW.Toggle(tab)
    frame(20)
    return ns.Window.frame
end

local function tab(ns, id)
    stub.Key(function() ns.Window.ShowTab(id, true) end)
    frame(20)
end

local function rows(stack, kind)
    local out = {}
    for _, b in ipairs(stack.used) do
        if b:IsShown() and b.spec and b.spec.kind == kind then out[#out + 1] = b end
    end
    return out
end

local function heads(stack)
    local out = {}
    for _, b in ipairs(stack.used) do
        if b:IsShown() and b.isSection and b.text then out[#out + 1] = b.text:GetText() .. " " .. (b.count and b.count:GetText() or "") .. (b.state and b.state:GetText() or "") end
    end
    return table.concat(out, " | ")
end

local function names(list)
    local out = {}
    for _, b in ipairs(list) do out[#out + 1] = (b.name:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    return table.concat(out, ", ")
end

local function blocked()
    for _, e in ipairs(stub.errors) do if tostring(e):find("ADDON_ACTION_BLOCKED", 1, true) then return e end end
    return nil
end

local function clean()
    T.isnil(blocked(), tostring(blocked()))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end

-- Our menu (W.OpenMenu): its keys and a pick.
local function menuOf(fn)
    local W = DaylightUI.Widgets
    local seen
    local real = W.OpenMenu
    W.OpenMenu = function(_, keys, values, _, onPick) seen = { keys = keys, values = values, pick = onPick } end
    fn()
    W.OpenMenu = real
    return seen
end

local function footer(page)
    local out = {}
    for _, b in ipairs(page.foot.buttons) do
        if b:IsShown() then out[#out + 1] = b.text:GetText() .. (b.spec and b.spec.off and " (off)" or "") end
    end
    return table.concat(out, ", ")
end

T.test("social: on by default", function()
    stub.Load({ before = function() SW.world({})(); DaylightUIDB = nil end })
    T.truthy(stub.social.Window.frame, "built")
end)

T.test("social: switched off, the game's window stays the game's", function()
    local ns = load({ enabled = false })
    T.isnil(ns.Window.frame, "nothing built")
    SW.Toggle()
    frame(5)
    T.eq(SocialUIFrame:GetParent(), UIParent, "not parked")
    T.truthy(SocialUIFrame:IsVisible(), "the game's own window shows")
end)

T.test("social: O opens ours in the game's place, on Friends, with your status and who's online", function()
    local ns = load()
    local f = open(ns)
    T.truthy(DaylightUI.Win.IsOpen(f), "ours open")
    T.eq(SocialUIFrame:GetParent(), DaylightUI.Win.Followers.hidden, "the game's frame is parked")
    T.eq(#SW.Calls("GameOnShow"), 0, "parked: the game's OnShow never ran")
    T.eq(#f.tabs, 4)
    T.eq(f.tabs[1].id, "friends")
    T.eq(f.tab, "friends")
    T.eq(f.title:GetText(), "Social")
    T.eq(f.status.text:GetText(), "Available")
    T.truthy(f.online:GetText():find("5", 1, true), f.online:GetText())
    T.truthy(f.tabs[3].text:GetText():find("Requests", 1, true) and f.tabs[3].text:GetText():find("2", 1, true), "the requests' count on its tab")
    clean()
end)

T.test("social: the game asked for the Raid tab (ToggleRaidFrame): ours opens on Raid", function()
    local ns = load()
    local f = open(ns, SW.TAB.RaidList)
    T.eq(f.tab, "raid")
    T.isnil(SocialUIFrame.deferredOpenTabType, "taken with the game's ConsumeDeferredOpenTab")
    T.eq(f:GetWidth(), ns.Window.RAID_W, "the wider page")
    clean()
end)

T.test("social: closing ours hides the game's; O again closes ours", function()
    local ns = load()
    local f = open(ns)
    ns.Window.Close()
    frame(20)
    T.falsy(SocialUIFrame:IsShown(), "the game's frame hidden too")
    T.falsy(DaylightUI.Win.IsOpen(f))
    open(ns)
    T.truthy(DaylightUI.Win.IsOpen(f))
    SW.Toggle()
    frame(20)
    T.falsy(DaylightUI.Win.IsOpen(f), "ours follows")
end)

T.test("social: opens and closes in a fight (nothing of it is protected)", function()
    local ns = load()
    stub.secure = true
    stub.EnterCombat()
    local f = open(ns)
    T.truthy(DaylightUI.Win.IsOpen(f))
    SW.Toggle()
    frame(20)
    T.falsy(DaylightUI.Win.IsOpen(f))
    stub.LeaveCombat()
    stub.secure = false
    clean()
end)

T.test("social: friends under Favorites, Online and Offline (folded), then Ignored (folded)", function()
    local ns = load()
    open(ns)
    local page = ns.Friends.page
    T.eq(heads(page.stack), "FAVORITES 2 / 3 | ONLINE 3 | OFFLINE 1+ | IGNORED 2+")
    local list = rows(page.stack, "friend")
    T.eq(names(list), "Mara  Ysella Dawnwhisper, Jonno  Brannoc Ironvein, Ambrose, Kit  Thessaly Moor, Riven  Dorrik Ashgrove, Sol")
    T.eq(list[1].sub:GetText(), "Level 44 · Tanaris")
    T.eq(list[3].sub:GetText(), "Last online 3 days ago")
    T.eq(list[6].sub:GetText(), "Playing Diablo IV")
    T.truthy(list[1].dot:IsShown(), "a status dot")
    T.near(list[2].dot.__vertexColor and list[2].dot.__vertexColor[1] or DaylightUI.Style.INK.WARN[1], DaylightUI.Style.INK.WARN[1], 0.01)
    -- Unfold Offline.
    for _, b in ipairs(page.stack.used) do
        if b:IsShown() and b.isSection and b.text:GetText() == "OFFLINE" then b:Click() end
    end
    frame(2)
    T.eq(#rows(page.stack, "friend"), 7, "Pip shows")
    clean()
end)

T.test("social: a friend picked: Invite (their game account) and Whisper (Battle.net)", function()
    local ns = load()
    open(ns)
    local page = ns.Friends.page
    T.eq(footer(page), "Invite (off), Whisper (off), Add friend")
    local kit = rows(page.stack, "friend")[4]
    stub.Key(function() kit:Click() end)
    T.eq(footer(page), "Invite, Whisper, Add friend")
    stub.Key(function() page.foot.buttons[1]:Click() end)
    T.eq(SW.Calls("InviteFriend")[1][1], 100 + #"Thessaly Moor")
    stub.Key(function() page.foot.buttons[2]:Click() end)
    T.eq(SW.Calls("SendBNetTell")[1][1], "Kit")
    -- Sol plays another game: no invite.
    local sol = rows(page.stack, "friend")[6]
    stub.Key(function() sol:Click() end)
    T.eq(footer(page), "Invite (off), Whisper, Add friend")
    clean()
end)

T.test("social: the search box filters friends", function()
    local ns = load()
    open(ns)
    local page = ns.Friends.page
    page.search:SetText("tanaris")
    frame(2)
    T.eq(names(rows(page.stack, "friend")), "Mara  Ysella Dawnwhisper")
    page.search:SetText("nobody")
    frame(2)
    T.truthy(page.note:IsShown())
    T.eq(page.note:GetText(), "No friends match.")
end)

-- Real realm names read like "CAMWOW US1 Realm 8 PvP" (seen in game).
T.test("social: a friend's realm name comes down to its ruleset", function()
    local ns = load()
    local R = ns.Data.Ruleset
    T.eq(R("CAMWOW US1 Realm 8 PvP"), "PvP")
    T.eq(R("CAMWOW US2 Realm 5 PvE"), "PvE")
    T.eq(R("CAMWOW US1 Realm 10 RP"), "RP")
    T.eq(R("CAMWOW US1 Realm 3 RP PvP"), "RP PvP")
    T.eq(R("CAMWOW US1 Realm 3 RPPvP"), "RP PvP")
    T.eq(R("CAMWOW US1 Realm 3 RPvP"), "RP PvP")
    T.eq(R("CAMWOW US1 Realm 3 Hardcore"), "Hardcore")
    T.eq(R("Sharpvale"), "Sharpvale")   -- no ruleset word: the whole name
    T.eq(R(nil), nil)
end)

T.test("social: invite only friends on your ruleset; a realm with no ruleset word is left to the game", function()
    local ns = load()
    local D = ns.Data
    local was = _G.GetRealmName
    _G.GetRealmName = function() return "CAMWOW US1 Realm 8 PvP" end
    T.truthy(D.SameRuleset("CAMWOW US2 Realm 3 PvP"), "another realm, the same rules")
    T.truthy(D.SameRuleset("CAMWOWUS2Realm3PvP"), "as a whisper's name writes it")
    T.falsy(D.SameRuleset("CAMWOW US1 Realm 10 RP PvP"))
    T.falsy(D.SameRuleset("CAMWOW US1 Realm 3 Hardcore"))
    T.truthy(D.SameRuleset("Sharpvale"), "no word: can't tell")
    T.truthy(D.SameRuleset(nil), "your own realm")
    local f = { inGame = true, gameAccountID = 7, realm = "CAMWOW US1 Realm 2 PvP" }
    T.truthy(D.CanInviteFriend(f))
    f.realm = "CAMWOW US1 Realm 2 PvE"
    T.falsy(D.CanInviteFriend(f))
    _G.GetRealmName = was
end)

T.test("social: a friend's ruleset is on the row and the card, and searchable; the game's card hides it abroad", function()
    local function friend(id, name, extra)
        local g = { gameAccountID = 100 + id, clientProgram = "WoW", isOnline = true, wowProjectID = WOW_PROJECT_ID,
            characterName = name, classFilename = "MAGE", characterLevel = 10, areaName = "Durotar" }
        for k, v in pairs(extra) do g[k] = v end
        return { bnetAccountID = id, accountName = name, gameAccountInfo = g }
    end
    local ns = load({ friends = {
        friend(1, "Fighter", { realmDisplayName = "CAMWOW US1 Realm 8 PvP" }),
        friend(2, "Actor", { realmDisplayName = "CAMWOW US1 Realm 10 RP", isInCurrentRegion = true }),
        friend(3, "Abroad", { realmDisplayName = "CAMWOW EU1 Realm 2 RP", isInCurrentRegion = false }),
    } })
    open(ns)
    local list = ns.Data.Friends()
    T.eq(ns.Friends.Sub(list[1]), "Level 10 · Durotar · PvP")
    T.eq(ns.Friends.Sub(list[2]), "Level 10 · Durotar · RP")
    T.eq(ns.Friends.Sub(list[3]), "Level 10 · Durotar")

    _G.GameTooltip = _G.GameTooltip or CreateFrame("GameTooltip", "GameTooltip", UIParent)
    local Tips, lines, was = DaylightUI.Tips, {}, DaylightUI.Tips.Line
    Tips.Line = function(label, value, ...) lines[label] = value; return was(label, value, ...) end
    ns.Friends.Tip(ns.Window.frame, list[1])
    Tips.Line = was
    T.eq(lines["Server"], "PvP")

    local page = ns.Friends.page
    page.search:SetText("rp")
    frame(2)
    T.eq(#rows(page.stack, "friend"), 1)
end)

T.test("social: friends show their faction; another game or ruleset is dimmed; chips filter All, Same game, Online", function()
    local function friend(id, name, extra)
        local g = { gameAccountID = 100 + id, clientProgram = "WoW", isOnline = true, wowProjectID = WOW_PROJECT_ID,
            characterName = name, classFilename = "MAGE", characterLevel = 10, areaName = "Durotar" }
        for k, v in pairs(extra) do g[k] = v end
        return { bnetAccountID = id, accountName = name, gameAccountInfo = g }
    end
    local was = _G.GetRealmName
    _G.GetRealmName = function() return "CAMWOW US1 Realm 8 PvP" end
    local ns = load({ friends = {
        friend(1, "Ally", { factionName = "Alliance", realmDisplayName = "CAMWOW US1 Realm 2 PvP" }),
        friend(2, "Hordie", { factionName = "Horde", realmDisplayName = "CAMWOW US1 Realm 10 RP" }),
        { bnetAccountID = 3, accountName = "Sol", gameAccountInfo = { gameAccountID = 103, clientProgram = "Fen", isOnline = true, richPresence = "Diablo IV" } },
        { bnetAccountID = 4, accountName = "Pip", lastOnlineTime = time() - 60, gameAccountInfo = { isOnline = false, clientProgram = "" } },
    } })
    open(ns)
    local page = ns.Friends.page
    local INK = DaylightUI.Style.INK
    local list = rows(page.stack, "friend")
    T.falsy(list[1].name:GetText():find("|T", 1, true), "off as shipped: no faction")
    T.rgb({ list[2].name:GetTextColor() }, INK.VALUE, "off as shipped: not dimmed")
    T.falsy(page.chips.all:IsShown(), "off as shipped: no chips")
    DaylightUI:Set("Social", "friendFactions", true)
    DaylightUI:Set("Social", "friendDim", true)
    DaylightUI:Set("Social", "friendChips", true)
    frame(2)
    list = rows(page.stack, "friend")
    T.truthy(page.chips.all:IsShown(), "on: the chips")
    T.truthy(list[1].name:GetText():find("INV_BannerPVP_02", 1, true), "Alliance's banner")
    T.truthy(list[2].name:GetText():find("INV_BannerPVP_01", 1, true), "Horde's banner")
    T.falsy(list[3].name:GetText():find("|T", 1, true), "another game: no faction")
    local function color(b) local r, g, bl = b.name:GetTextColor() return { r, g, bl } end
    T.rgb(color(list[1]), INK.VALUE, "your ruleset, this game: bright")
    T.rgb(color(list[2]), INK.OFF, "another ruleset: dimmed")
    T.rgb(color(list[3]), INK.OFF, "another game: dimmed")
    T.falsy(list[2].name:GetText():find("|c", 1, true), "dimmed: no class color either")
    stub.Key(function() page.chips.game:Click() end)
    frame(2)
    T.eq(#rows(page.stack, "friend"), 1, "Same game: only who you can play with")
    stub.Key(function() page.chips.online:Click() end)
    frame(2)
    T.eq(#rows(page.stack, "friend"), 3, "Online: everyone on, any game")
    stub.Key(function() page.chips.all:Click() end)
    frame(2)
    _G.GetRealmName = was
    clean()
end)

T.test("social: a friend coming online moves up to Online with a shine", function()
    local ns = load()
    open(ns)
    local page = ns.Friends.page
    local shone = {}
    local real = DaylightUI.Win.Parts.Shine
    DaylightUI.Win.Parts.Shine = function(b) shone[#shone + 1] = b end
    SW.Login(6)
    frame(3)
    DaylightUI.Win.Parts.Shine = real
    local online = rows(page.stack, "friend")
    T.eq(names(online), "Mara  Ysella Dawnwhisper, Jonno  Brannoc Ironvein, Ambrose, Kit  Thessaly Moor, Riven  Dorrik Ashgrove, Sol, Pip  Wren Haddock")
    T.eq(#shone, 1)
    T.eq(shone[1].spec.friend.account, "Pip")
    clean()
end)

T.test("social: the right-click menu: note, favorite, remove asks first", function()
    local ns = load()
    open(ns)
    local kit = rows(ns.Friends.page.stack, "friend")[4]
    local m = menuOf(function() kit.spec.onMenu(kit) end)
    T.eq(table.concat(m.keys, ","), "whisper,invite,note,favorite,remove")
    m.pick("favorite")
    T.eq(SW.Calls("BNSetFriendFavoriteFlag")[1][2], true)
    m.pick("remove")
    T.eq(stub.popup.which, "CONFIRM_REMOVE_BN_FRIEND", "the game's own question")
    T.eq(stub.popup.data, 3)
    T.eq(#SW.Calls("BNRemoveFriend"), 0, "nothing removed yet")
end)

T.test("social: your status from the header (a click), and a broadcast", function()
    local ns = load()
    local f = open(ns)
    local m = menuOf(function() f.status:Click() end)
    T.eq(table.concat(m.keys, ","), "on,away,busy,broadcast")
    stub.Key(function() m.pick("away") end)
    T.eq(SW.Calls("SetAFK")[1][1], true)
    frame(3)
    T.eq(f.status.text:GetText(), "Away")
    clean()
end)

-- The prompt's Accept, pressed by the player: a key or click of theirs around it.
local function accept(text)
    local dialog = StaticPopupDialogs[stub.popup.which]
    stub.Key(dialog.OnAccept, { editBox = { GetText = function() return text end } }, stub.popup.data)
    stub.RunTimers()
end

T.test("social: Add friend and a broadcast reach the game inside the prompt's click (a timer loses it)", function()
    local ns = load()
    local f = open(ns)
    stub.errors = {}
    stub.Key(function() ns.Friends.page.foot.buttons[3]:Click() end)
    accept("Odessa Reed")
    T.eq(#stub.errors, 0, "the game refused it: " .. tostring(stub.errors[1]))
    T.eq(SW.Calls("SendTitleFriendInviteByName")[1][1], "Odessa Reed")
    local m = menuOf(function() f.status:Click() end)
    stub.Key(function() m.pick("broadcast") end)
    accept("Raiding at 8")
    T.eq(#stub.errors, 0, "the game refused it: " .. tostring(stub.errors[1]))
    T.eq(SW.Calls("SetCustomMessage")[1][1], "Raiding at 8")
    clean()
end)

T.test("social: recent allies under Pinned (and legacy friends) and Recent, the client's order; chips filter", function()
    local ns = load()
    open(ns)
    tab(ns, "allies")
    local page = ns.Allies.page
    T.eq(heads(page.stack), "PINNED 2 / 2 | RECENT 2 / 4")
    T.eq(names(rows(page.stack, "ally")), "Halvar Stonefist, Sabine Kett, Lirien Vale, Odessa Reed, Fenwick Harrow, Garrett Lowe")
    local first = rows(page.stack, "ally")[1]
    T.eq(first.sub:GetText(), "Level 41 · Grouped with you")
    T.eq(first.value:GetText(), "20 min")
    stub.Key(function() page.chips.trade:Click() end)
    frame(2)
    T.eq(names(rows(page.stack, "ally")), "Odessa Reed")
    stub.Key(function() page.chips.all:Click() end)
    frame(2)
    clean()
end)

T.test("social: an ally picked: Invite and Whisper by name, Pin keeps them (a shine as they move up)", function()
    local ns = load()
    open(ns)
    tab(ns, "allies")
    local page = ns.Allies.page
    T.eq(footer(page), "Invite (off), Whisper (off), Pin (off)")
    local odessa = rows(page.stack, "ally")[4]
    stub.Key(function() odessa:Click() end)
    T.eq(footer(page), "Invite, Whisper, Pin")
    stub.Key(function() page.foot.buttons[1]:Click() end)
    T.eq(SW.Calls("InviteUnit")[1][1], "Odessa Reed")
    local shone = {}
    local real = DaylightUI.Win.Parts.Shine
    DaylightUI.Win.Parts.Shine = function(b) shone[#shone + 1] = b end
    stub.Key(function() page.foot.buttons[3]:Click() end)
    frame(3)
    DaylightUI.Win.Parts.Shine = real
    T.eq(SW.Calls("SetRecentAllyPinned")[1][2], true)
    T.eq(heads(page.stack), "PINNED 3 / 3 | RECENT 1 / 3")
    T.eq(shone[1] and shone[1].spec.ally.name, "Odessa Reed")
    T.eq(footer(page), "Invite, Whisper, Unpin", "still picked")
    clean()
end)

T.test("social: no recent allies cached yet: the tab never asks (refused to addons), the list comes with the game's data", function()
    local ns = load({ alliesReady = false })
    open(ns)
    tab(ns, "allies")
    T.eq(#stub.errors, 0, "nothing blocked")
    T.eq(#rows(ns.Allies.page.stack, "ally"), 0)
    SW.state.alliesReady = true
    stub.FireEvent("RECENT_ALLIES_DATA_READY")
    frame(3)
    T.eq(#rows(ns.Allies.page.stack, "ally"), 6)
    clean()
end)

T.test("social: requests: Accept (after its light and fade) and Decline or Block", function()
    local ns = load()
    local f = open(ns)
    tab(ns, "requests")
    local page = ns.Requests.page
    local list = {}
    for _, b in ipairs(page.stack.used) do if b:IsShown() and b.accept then list[#list + 1] = b end end
    T.eq(#list, 2)
    T.eq(list[1].name:GetText(), "Bramblefoot#2231")
    T.eq(list[1].sub:GetText(), "Sent 2 days ago")
    stub.Key(function() list[1].accept:Click() end)
    T.eq(#SW.Calls("BNAcceptFriendInvite"), 0, "the line eases out first")
    frame(15)
    T.eq(SW.Calls("BNAcceptFriendInvite")[1][1], 21)
    frame(3)
    T.truthy(f.tabs[3].text:GetText():find("1", 1, true), "the tab's count: " .. f.tabs[3].text:GetText())
    local left
    for _, b in ipairs(page.stack.used) do if b:IsShown() and b.accept then left = b end end
    local m = menuOf(function() left.decline:Click() end)
    T.eq(table.concat(m.keys, ","), "decline,block")
    m.pick("block")
    frame(15)
    T.eq(SW.Calls("SetBlocked")[1][1], 22)
    T.eq(SW.Calls("BNDeclineFriendInvite")[1][1], 22)
    frame(3)
    T.eq(f.tabs[3].text:GetText(), "Requests", "no count left")
    T.truthy(page.note:IsShown())
    T.eq(page.note:GetText(), "No requests yet.")
    SW.Invite("Quill#4417")
    frame(3)
    T.truthy(f.tabs[3].text:GetText():find("1", 1, true))
    clean()
end)

-- The fake game lays nothing out: each raid row gets a spot on screen
-- (the client's GetLeft/GetTop), so the target layer can be laid over it.
local function spots(ns)
    for g, card in ipairs(ns.Raid.page.cards) do
        card.GetLeft = function() return 100 + (g - 1) % 4 * 170 end
        card.GetTop = function() return 800 - math.floor((g - 1) / 4) * 140 end
        for i, s in ipairs(card.slots) do
            s.GetLeft = function() return card:GetLeft() end
            s.GetTop = function() return card:GetTop() - 20 - (i - 1) * 22 end
        end
    end
end

-- The raid's rows: card by card, the names shown.
local function raidNames(page)
    local out = {}
    for _, card in ipairs(page.cards) do
        local g = {}
        for _, s in ipairs(card.slots) do if s.member then g[#g + 1] = s.name:GetText() end end
        if #g > 0 then out[#out + 1] = card.group .. ": " .. table.concat(g, " ") end
    end
    return table.concat(out, " | ")
end

T.test("social: the raid: counts, groups, marks; target buttons laid over our rows out of combat", function()
    local ns = load({ raid = SW.Roster() })
    spots(ns)
    open(ns, SW.TAB.RaidList)
    local page = ns.Raid.page
    T.eq(raidNames(page), "1: Sunwalker Brannoc Ysella Thessaly Dorrik | 2: Lirien Odessa Fenwick Wren Corvin | 3: Garrett Halvar")
    T.truthy(page.count:GetText():find("12", 1, true), page.count:GetText())
    local s1 = page.cards[1].slots[1]
    T.truthy(s1.mark:IsShown(), "the leader's mark")
    T.eq(page.cards[2].slots[3].level:GetText(), "58", "below max level: shown")
    T.eq(page.cards[1].slots[2].level:GetText(), "", "max level: not shown")
    T.eq(page.cards[3].slots[3].name:GetText(), "Empty")
    local layer = _G.DaylightUISocialRaidTargets
    T.truthy(layer, "made")
    T.eq(layer:GetParent(), UIParent, "not inside our window")
    local b1 = _G.DaylightUISocialRaidTarget1
    T.truthy(b1:IsShown())
    T.eq(b1:GetAttribute("unit"), "raid1")
    T.eq(b1:GetAttribute("type1"), "target")
    T.eq(b1.slot, s1)
    T.falsy(_G.DaylightUISocialRaidTarget13:IsShown(), "twelve members, twelve buttons")
    ns.Window.Close()
    frame(20)
    T.falsy(b1:IsVisible())
    clean()
end)

T.test("social: holding a name and letting go on another group moves them; onto a person, swaps", function()
    local ns = load({ raid = SW.Roster() })
    open(ns, SW.TAB.RaidList)
    local page = ns.Raid.page
    local over = {}
    for _, c in ipairs(page.cards) do
        c.IsMouseOver = function(self) return over.card == self or (over.slot ~= nil and over.slot:GetParent() == self) end
        for _, s in ipairs(c.slots) do s.IsMouseOver = function(self) return over.slot == self end end
    end
    local thessaly = page.cards[1].slots[4]
    ns.Raid.Lift(thessaly)
    T.near(thessaly:GetAlpha(), 0.35, 0.01)
    over = { card = page.cards[3] }
    ns.Raid.Drop()
    T.eq(SW.Calls("SetRaidSubgroup")[1][1], 4)
    T.eq(SW.Calls("SetRaidSubgroup")[1][2], 3)
    frame(3)
    T.eq(raidNames(page), "1: Sunwalker Brannoc Ysella Dorrik | 2: Lirien Odessa Fenwick Wren Corvin | 3: Thessaly Garrett Halvar")
    local dorrik = page.cards[1].slots[4]
    ns.Raid.Lift(dorrik)
    over = { slot = page.cards[2].slots[1] }
    ns.Raid.Drop()
    T.eq(SW.Calls("SwapRaidSubgroup")[1][1], 5)
    T.eq(SW.Calls("SwapRaidSubgroup")[1][2], 6)
    clean()
end)

T.test("social: the raid page's right-click makes leader, assistant, or removes, through C_PartyInfo", function()
    local ns = load({ raid = SW.Roster() })
    open(ns, SW.TAB.RaidList)
    local slot = ns.Raid.page.cards[1].slots[4]
    local m = slot.member or slot.m
    T.truthy(m, "a member on the slot")
    for _, k in ipairs({ "leader", "assist", "remove" }) do
        local menu = menuOf(function() ns.Raid.Menu(slot, m) end)
        T.truthy(menu.values[k], k)
        menu.pick(k)
    end
    T.eq(SW.Calls("PromoteToLeader")[1][1], m.name)
    T.eq(SW.Calls("PromoteToLeader")[1][2], true, "exact name")
    T.eq(#SW.Calls(m.rank == 1 and "DemoteAssistant" or "PromoteToAssistant"), 1)
    T.eq(SW.Calls("UninviteUnit")[1][1], m.name)
    clean()
end)

T.test("social: not the leader or an assistant: nothing moves", function()
    local ns = load({ raid = SW.Roster() })
    SW.Raid(nil, false)
    open(ns, SW.TAB.RaidList)
    local page = ns.Raid.page
    ns.Raid.Lift(page.cards[1].slots[4])
    T.isnil(ns.Raid.dragging)
    T.eq(#SW.Calls("SetRaidSubgroup"), 0)
    T.truthy(page.assist.off, "everyone-is-assistant is the leader's")
end)

T.test("social: in a fight the target layer waits; the page still updates; after it, the buttons follow", function()
    local ns = load({ raid = SW.Roster() })
    spots(ns)
    stub.secure = true
    open(ns, SW.TAB.RaidList)
    local page = ns.Raid.page
    T.truthy(_G.DaylightUISocialRaidTargets:IsShown())
    stub.EnterCombat()
    stub.SetConditions({ combat = true })
    T.falsy(_G.DaylightUISocialRaidTargets:IsShown(), "the game's state driver hid it")
    local r = SW.Roster()
    table.insert(r, { "Petra Vane", "DRUID", 60, 3, "DAMAGER", 0 })
    SW.Raid(r)
    frame(3)
    T.truthy(raidNames(page):find("Petra", 1, true), "our rows update in the fight")
    T.falsy(_G.DaylightUISocialRaidTarget13:IsShown(), "the secure button waits")
    stub.SetConditions({ combat = false })
    stub.LeaveCombat()
    frame(2)
    T.truthy(_G.DaylightUISocialRaidTarget13:IsShown(), "laid over Petra after the fight")
    stub.secure = false
    clean()
end)

T.test("social: a raid roster's secret online, dead and role are never compared", function()
    local ns = load()
    SW.Raid(SW.Roster())
    local real = _G.GetRaidRosterInfo
    _G.GetRaidRosterInfo = function(i)
        local name, rank, group, level, class, token, zone, online, dead, a, b, role = real(i)
        if not name then return nil end
        return name, rank, group, level, class, token, zone, stub.Secret(online), stub.Secret(dead), a, b, stub.Secret(role)
    end
    local list
    T.noerror(function() list = ns.Data.Roster() end)
    _G.GetRaidRosterInfo = real
    T.truthy(#list > 0)
    T.truthy(list[1].online, "read as online")
    T.falsy(list[1].dead, "alive")
    T.isnil(list[1].role, "no role")
    clean()
end)

T.test("social: not in a raid: one line and Convert to raid (the party leader's)", function()
    local ns = load()
    open(ns, SW.TAB.RaidList)
    local page = ns.Raid.page
    T.truthy(page.noRaid:IsShown())
    T.falsy(page.inRaid:IsShown())
    T.truthy(page.convert.off, "alone: off")
    clean()
end)

T.test("social: the target buttons sit above our window's rows; our rows take the hold too", function()
    local ns = load({ raid = SW.Roster() })
    spots(ns)
    open(ns, SW.TAB.RaidList)
    local slot = ns.Raid.page.cards[1].slots[4]
    local b1 = _G.DaylightUISocialRaidTarget1
    T.truthy(b1:GetFrameLevel() > slot:GetFrameLevel(), b1:GetFrameLevel() .. " over " .. slot:GetFrameLevel())
    T.eq(b1:GetFrameStrata(), ns.Window.frame:GetFrameStrata())
    T.truthy(slot:GetScript("OnDragStart"), "the row lifts")
    slot:GetScript("OnDragStart")(slot)
    T.eq(ns.Raid.dragging, slot.member.index)
    ns.Raid.Drop(true)
    clean()
end)
