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

-- The detail panel under a list: "closed", or its buttons.
local function panel(page)
    local d = page.detail
    if not d:IsOpen() then return "closed" end
    local out = {}
    for _, b in ipairs(d.buttons) do
        if b:IsShown() then out[#out + 1] = b.text:GetText() end
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

T.test("social: the header's swap icon hands over to the game's window and it stays picked", function()
    -- Blizzard_SocialUI loads with the game, before Daylight UI.
    stub.Load({ before = function() SW.world()(); stub.loadedAddOns.Blizzard_SocialUI = true end, skins = true })
    local ns = stub.social
    local f = open(ns)
    T.truthy(DaylightUI.Win.IsOpen(f))
    T.truthy(f.swap and f.swap:IsShown(), "the swap icon sits in the header")
    T.isnil(stub.skins.Kit.ShellOf(SocialUIFrame), "the skins leave it alone while covered")
    f.swap:Click()
    frame(10)
    T.eq(DaylightUI:Get("Social", "enabled"), false, "the pick is saved")
    T.falsy(DaylightUI.Win.IsOpen(f), "ours steps aside")
    T.eq(SocialUIFrame:GetParent(), UIParent, "the game's window is back")
    T.truthy(SocialUIFrame:IsVisible(), "and shows")
    T.truthy(ns.Window.swap.link:IsShown(), "with its way back")
    T.falsy(ns.Window.Covers(), "the skins may dress it")
    stub.RunTimers()
    T.truthy(stub.skins.Kit.ShellOf(SocialUIFrame), "in the Daylight UI look")
    SW.Close()
    frame(10)
    T.eq(SocialUIFrame:GetParent(), UIParent, "never parked while it's the pick")
    SW.Toggle()
    frame(20)
    T.falsy(DaylightUI.Win.IsOpen(f), "O opens the game's window next time")
    T.truthy(SocialUIFrame:IsVisible())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("social: the game's window's link switches back to Daylight UI's, no reload", function()
    stub.Load({ before = function() SW.world({ enabled = false })(); stub.loadedAddOns.Blizzard_SocialUI = true end, skins = true })
    local ns = stub.social
    SW.Toggle(2)
    frame(5)
    T.isnil(ns.Window.frame, "nothing built while the game's is picked")
    local b = ns.Window.swap.link
    T.truthy(b and b:IsShown(), "the game's window has the switch")
    T.eq(b:GetParent(), SocialUIFrame, "it rides on the game's window")
    b:Click()
    frame(20)
    T.eq(DaylightUI:Get("Social", "enabled"), true, "the pick is saved")
    local f = ns.Window.frame
    T.truthy(f and DaylightUI.Win.IsOpen(f), "ours opens in its place")
    T.eq(f.tab, "requests", "on the page the game's showed")
    T.eq(SocialUIFrame:GetParent(), DaylightUI.Win.Followers.hidden, "the game's frame is parked")
    T.truthy(SocialUIFrame:IsShown(), "still open underneath, so O closes both")
    T.falsy(b:IsVisible(), "the link is gone with the game's look")
    T.truthy(ns.Window.Covers())
    SW.Toggle()
    frame(20)
    T.falsy(DaylightUI.Win.IsOpen(f), "O closes ours")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
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
    T.eq(panel(page), "closed", "nothing picked: no panel")
    local kit = rows(page.stack, "friend")[4]
    stub.Key(function() kit:Click() end)
    T.eq(panel(page), "Invite, Whisper")
    stub.Key(function() page.detail.buttons[1]:Click() end)
    T.eq(SW.Calls("InviteFriend")[1][1], 100 + #"Thessaly Moor")
    local asked = {}
    DaylightUI.Widgets.Prompt = function(text) asked[#asked + 1] = text end
    stub.Key(function() page.detail.buttons[2]:Click() end)
    T.eq(asked[1], "Whisper Kit", "Daylight UI's own box asks for the words")
    T.eq(#SW.Calls("SendBNetTell"), 0, "the game's chat box is never opened from here")
    -- Sol plays another game: no invite.
    local sol = rows(page.stack, "friend")[6]
    stub.Key(function() sol:Click() end)
    T.eq(panel(page), "Whisper", "no Invite where it can't be done: not dimmed, not there")
    -- Picking it again closes the panel.
    stub.Key(function() sol:Click() end)
    T.eq(panel(page), "closed")
    clean()
end)

-- A quick Invite at the row's right end, as the game's own friends list has: only
-- on a friend you can play with now, without picking the row, and the row's light
-- stays on while the mouse is on the button.
T.test("social: a friend you can invite has a quick Invite button at the end of the row", function()
    local ns = load()
    open(ns)
    local page = ns.Friends.page
    local list = rows(page.stack, "friend")
    local Rows = DaylightUI.Lfg.Rows
    local kit, ambrose, sol = list[4], list[3], list[6]
    T.truthy(kit.action:IsShown(), "Kit is on your ruleset: a button")
    T.falsy(ambrose.action:IsShown(), "Ambrose is offline: none")
    T.falsy(sol.action:IsShown(), "Sol plays another game: none")
    -- The name stops short of it.
    T.eq(select(4, kit.name:GetPoint(2)), -(10 + Rows.ACTION_W + Rows.ACTION_INSET - 4), "the text leaves room for the button")
    T.eq(select(4, sol.name:GetPoint(2)), -10, "and not where there is none")
    -- It sits at the right end, level with the row's middle.
    local p, rel, rp, x, y = kit.action:GetPoint(1)
    T.eq(p, "RIGHT"); T.eq(rel, kit); T.eq(rp, "RIGHT"); T.eq(y, 0, "in the middle")
    T.truthy(x < 0 and x > -12, "against the right edge")
    T.eq(kit.action:GetWidth(), Rows.ACTION_W); T.eq(kit.action:GetHeight(), Rows.ACTION_W, "square")
    T.truthy(kit.action.SetIcon and kit.action.icon, "W.IconButton: tan, accent on hover")
    -- Clicking invites that friend and doesn't pick the row.
    stub.Key(function() kit.action:Click() end)
    T.eq(SW.Calls("InviteFriend")[1][1], 100 + #"Thessaly Moor", "their game account")
    T.isnil(ns.Friends.picked, "the row isn't picked by it")
    T.eq(panel(page), "closed")
    -- The mouse on the button keeps the row lit; leaving it with the mouse off the row lets it go.
    kit.action:GetScript("OnEnter")(kit.action)
    frame(3)
    T.truthy(kit.hi:IsShown(), "the row stays lit under its button")
    kit.action:GetScript("OnLeave")(kit.action)
    frame(10)
    T.falsy(kit.hi:IsShown(), "and goes dark once the mouse is gone")
    -- Every row: a button exactly when that friend can be invited.
    local can = 0
    for _, b in ipairs(rows(page.stack, "friend")) do
        local ok = ns.Data.CanInviteFriend(b.spec.friend)
        T.eq(b.action:IsShown(), ok, b.name:GetText() .. ": a button only if they can be invited")
        if ok then can = can + 1 end
    end
    T.truthy(can >= 2, "more than the one row")
    clean()
end)

-- The name and the sub line are one block centered on the row, so the selection
-- wash has the same room above and below (the sub used to sit on its bottom edge).
T.test("social: a friend's two lines are centered in the row's wash", function()
    local ns = load()
    open(ns)
    local page = ns.Friends.page
    local Rows = DaylightUI.Lfg.Rows
    for _, b in ipairs(rows(page.stack, "friend")) do
        if b.sub:IsShown() then
            local function line(fs, size)
                local v = fs:GetStringHeight()
                return (type(v) == "number" and v > 0) and v or size + 2   -- the fake game has no text metrics
            end
            local top = -select(5, b.name:GetPoint(1))
            local block = line(b.name, DaylightUI.Style.SIZE.body) + Rows.LINE_GAP + line(b.sub, DaylightUI.Style.SIZE.small)
            local below = ns.Friends.ROW - top - block
            T.truthy(math.abs(top - below) <= 1, b.name:GetText() .. ": room above " .. top .. ", below " .. below)
            T.truthy(top >= 4, "room round the text, not on the edge")
        end
    end
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

-- The game's party button is off for a friend of the other faction (a Horde friend
-- can't join an Alliance group). A faction that isn't known is left to the game, and
-- a client that hands over the localized name is read by the game's own words.
T.test("social: a friend of the other faction can't be invited; a localized faction name is read", function()
    local function friend(id, name, extra)
        local g = { gameAccountID = 100 + id, clientProgram = "WoW", isOnline = true, wowProjectID = WOW_PROJECT_ID,
            characterName = name, classFilename = "MAGE", characterLevel = 10, areaName = "Durotar",
            realmDisplayName = "CAMWOW US1 Realm 8 PvP" }
        for k, v in pairs(extra) do g[k] = v end
        return { bnetAccountID = id, accountName = name, gameAccountInfo = g }
    end
    local was = { realm = _G.GetRealmName, horde = _G.FACTION_HORDE, alliance = _G.FACTION_ALLIANCE }
    _G.GetRealmName = function() return "CAMWOW US1 Realm 8 PvP" end
    _G.FACTION_HORDE, _G.FACTION_ALLIANCE = "Horda", "Alianza"
    local ns = load({ friends = {
        friend(1, "Ally", { factionName = "Alliance" }),
        friend(2, "Hordie", { factionName = "Horde" }),
        friend(3, "Localized", { factionName = "Horda" }),
        friend(4, "Unknown", {}),
    } })
    stub.SetUnits({ player = { name = "Me", class = "MAGE", faction = "Alliance" } })
    local D = ns.Data
    T.eq(D.FactionOf("Horde"), "Horde"); T.eq(D.FactionOf("Alianza"), "Alliance"); T.eq(D.FactionOf("Horda"), "Horde")
    T.isnil(D.FactionOf("Gnome")); T.isnil(D.FactionOf(nil))
    open(ns)
    local page = ns.Friends.page
    local byName = {}
    for _, b in ipairs(rows(page.stack, "friend")) do byName[b.spec.friend.char] = b end
    T.truthy(byName.Ally.action:IsShown(), "same faction: a button")
    T.falsy(byName.Hordie.action:IsShown(), "the other faction: none")
    T.falsy(byName.Localized.action:IsShown(), "the other faction by its localized name: none")
    T.truthy(byName.Unknown.action:IsShown(), "no faction known: left to the game")
    -- The panel's Invite agrees.
    stub.Key(function() byName.Hordie:Click() end)
    T.eq(panel(page), "Whisper")
    -- A Horde player: it turns round.
    stub.SetUnits({ player = { name = "Me", class = "MAGE", faction = "Horde" } })
    T.truthy(D.CanInviteFriend(byName.Hordie.spec.friend))
    T.falsy(D.CanInviteFriend(byName.Ally.spec.friend))
    _G.GetRealmName, _G.FACTION_HORDE, _G.FACTION_ALLIANCE = was.realm, was.horde, was.alliance
    clean()
end)

-- The rest of what the game's party button reads (FriendsFrame_GetInviteRestriction):
-- a server that lets the factions group, a realm with no info yet, another region, and
-- a friend already in a group, who is asked to invite instead of being invited.
T.test("social: the invite follows the game's rules: cross-faction servers, realm info, region, request to join", function()
    local function friend(id, name, extra)
        local g = { gameAccountID = 100 + id, clientProgram = "WoW", isOnline = true, wowProjectID = WOW_PROJECT_ID,
            characterName = name, classFilename = "MAGE", characterLevel = 10, areaName = "Durotar",
            realmDisplayName = "CAMWOW US1 Realm 8 PvP", factionName = "Alliance", playerGuid = "Player-" .. id }
        for k, v in pairs(extra) do g[k] = v end
        return { bnetAccountID = id, accountName = name, gameAccountInfo = g }
    end
    local was = { realm = _G.GetRealmName, party = _G.C_PartyInfo, kind = _G.GetDisplayedInviteType, ask = _G.BNRequestInviteFriend }
    _G.GetRealmName = function() return "CAMWOW US1 Realm 8 PvP" end
    local ns = load({ friends = {
        friend(1, "Home", {}),
        friend(2, "Hordie", { factionName = "Horde" }),
        friend(3, "NoRealm", { realmID = 0 }),
        friend(4, "Abroad", { isInCurrentRegion = false }),
        friend(5, "Grouped", {}),
    } })
    stub.SetUnits({ player = { name = "Me", class = "MAGE", faction = "Alliance" } })
    local D = ns.Data
    local byName = {}
    for _, f in ipairs(D.Friends()) do byName[f.char] = f end
    T.truthy(D.CanInviteFriend(byName.Home), "the plain case")
    T.falsy(D.CanInviteFriend(byName.Hordie), "another faction")
    T.falsy(D.CanInviteFriend(byName.NoRealm), "a realm with no info yet (realmID 0): the game's restriction INFO")
    T.falsy(D.CanInviteFriend(byName.Abroad), "another region")
    -- A server that lets the factions group: the faction no longer stops it.
    _G.C_PartyInfo = { CanFormCrossFactionParties = function() return true end }
    T.truthy(D.CanInviteFriend(byName.Hordie), "cross-faction parties allowed")
    T.falsy(D.CanInviteFriend(byName.NoRealm), "but the other rules still hold")
    _G.C_PartyInfo = { CanFormCrossFactionParties = function() return false end }
    T.falsy(D.CanInviteFriend(byName.Hordie), "not allowed here")
    _G.C_PartyInfo = was.party
    -- The game's own call: invite, or ask to be invited when they are in a group.
    local asked
    _G.BNRequestInviteFriend = function(id) asked = id end
    _G.GetDisplayedInviteType = function(guid) return guid == "Player-5" and "REQUEST_INVITE" or "INVITE" end
    D.InviteFriend(byName.Home)
    T.eq(SW.Calls("InviteFriend")[1][1], 101, "an invite for a friend not in a group")
    T.isnil(asked)
    D.InviteFriend(byName.Grouped)
    T.eq(asked, 105, "a friend already in a group: asked to invite, as the game does")
    T.eq(#SW.Calls("InviteFriend"), 1, "no plain invite on top of it")
    _G.GetDisplayedInviteType = nil
    D.InviteFriend(byName.Grouped)
    T.eq(#SW.Calls("InviteFriend"), 2, "a client without that call: a plain invite")
    _G.GetRealmName, _G.GetDisplayedInviteType, _G.BNRequestInviteFriend = was.realm, was.kind, was.ask
    clean()
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

-- Two copies of the game on one Battle.net account: GetFriendAccountInfo gives only the
-- one in focus, so the other character went missing from the card and the tooltip.
T.test("social: a friend playing on two game accounts shows both characters", function()
    local function wow(id, name, class, level, zone, race)
        return { gameAccountID = id, clientProgram = "WoW", isOnline = true, wowProjectID = WOW_PROJECT_ID,
            characterName = name, classFilename = class, characterLevel = level, areaName = zone, raceName = race }
    end
    local ns = load({ friends = {
        { bnetAccountID = 1, accountName = "Bo", gameAccountInfo = wow(101, "Lyra", "PALADIN", 45, "Riverglades", "Undead"),
          gameAccounts = { wow(102, "Tarn", "HUNTER", 46, "Stranglethorn Vale", "Tauren"),
                           { gameAccountID = 103, clientProgram = "App", isOnline = true } } },
        -- In focus in another game, a character in this one: the character leads.
        { bnetAccountID = 2, accountName = "Cy", gameAccountInfo = { gameAccountID = 201, clientProgram = "Fen", isOnline = true, richPresence = "Diablo IV" },
          gameAccounts = { wow(202, "Vess", "MAGE", 30, "Tanaris", "Gnome") } },
    } })
    open(ns)
    local list = ns.Data.Friends()
    local bo, cy = list[1], list[2]
    T.eq(bo.char, "Lyra")
    T.eq(#bo.others, 1, "the Battle.net app isn't a character")
    T.eq(bo.others[1].char, "Tarn")
    T.eq(bo.others[1].level, 46)
    T.eq(cy.char, "Vess")
    T.truthy(cy.inGame)
    T.eq(cy.gameAccountID, 202, "Invite goes to the character in this game")
    T.eq(cy.others[1].game, "Diablo IV")

    _G.GameTooltip = _G.GameTooltip or CreateFrame("GameTooltip", "GameTooltip", UIParent)
    local Tips, people, was = DaylightUI.Tips, {}, DaylightUI.Tips.Person
    Tips.Person = function(name, where, ...) people[#people + 1] = name .. " / " .. tostring(where); return was(name, where, ...) end
    ns.Friends.Tip(ns.Window.frame, bo)
    Tips.Person = was
    T.deq(people, { "Lyra / Riverglades", "Tarn / Stranglethorn Vale" })

    local spec = ns.Friends.Spec(bo)
    local also
    for _, r in ipairs(spec.rows) do if r.label == "Also playing" then also = r end end
    T.truthy(also, "the card lists the other character")
    T.truthy(also.value:find("Tarn", 1, true) and also.value:find("Level 46 Tauren Hunter", 1, true), also.value)
    T.truthy(also.value:find("Stranglethorn Vale", 1, true), also.value)
    clean()
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
    T.eq(stub.Asked(), "removeFriend", "asked first")
    T.eq(#SW.Calls("BNRemoveFriend"), 0, "nothing removed yet")
    stub.Answer(true)
    T.eq(SW.Calls("BNRemoveFriend")[1][1], 3, "yes removes that friend")
end)

T.test("social: your status from the header (a click), and a broadcast", function()
    local ns = load()
    local f = open(ns)
    local m = menuOf(function() f.status:Click() end)
    T.eq(table.concat(m.keys, ","), "on,away,busy,hidden,broadcast")
    stub.Key(function() m.pick("away") end)
    T.eq(SW.Calls("SetAFK")[1][1], true)
    frame(3)
    T.eq(f.status.text:GetText(), "Away")
    clean()
end)

T.test("social: a status change sends one call, never two in a row", function()
    local ns = load()
    local f = open(ns)
    local function pick(key)
        local m = menuOf(function() f.status:Click() end)
        stub.Key(function() m.pick(key) end)
        frame(3)
    end
    local function sent()
        local out = {}
        for _, kind in ipairs({ "SetAFK", "SetDND" }) do
            for _, a in ipairs(SW.Calls(kind)) do out[#out + 1] = kind .. "=" .. tostring(a[1]) end
        end
        return table.concat(out, ",")
    end
    pick("away")
    T.eq(sent(), "SetAFK=true", "Away sets Away and leaves Busy alone")
    pick("on")
    T.eq(sent(), "SetAFK=true,SetAFK=false", "Available clears Away only")
    pick("busy")
    T.eq(sent(), "SetAFK=true,SetAFK=false,SetDND=true", "Busy sets Busy and leaves Away alone")
    pick("on")
    T.eq(sent(), "SetAFK=true,SetAFK=false,SetDND=true,SetDND=false", "Available clears Busy only")
    T.eq(f.status.text:GetText(), "Available")
    clean()
end)

T.test("social: appear offline from the header, and back to Available", function()
    local ns = load()
    local f = open(ns)
    local function pick(key)
        local m = menuOf(function() f.status:Click() end)
        stub.Key(function() m.pick(key) end)
        frame(3)
    end
    stub.errors = {}
    pick("hidden")
    T.eq(#stub.errors, 0, "the game refused it: " .. tostring(stub.errors[1]))
    T.eq(SW.Calls("SetAppearOffline")[1][1], true)
    T.eq(f.status.text:GetText(), "Appearing offline")
    pick("on")
    T.eq(SW.Calls("SetAppearOffline")[2][1], false, "Available shows you again")
    T.eq(#SW.Calls("SetAFK") + #SW.Calls("SetDND"), 0, "one call per click")
    T.eq(f.status.text:GetText(), "Available")
    clean()
end)

T.test("social: appearing offline set elsewhere shows in the header", function()
    local ns = load()
    local f = open(ns)
    SW.state.hidden = true   -- set from the game's own menu or the Battle.net app
    stub.FireEvent("BN_INFO_CHANGED")
    frame(3)
    T.eq(f.status.text:GetText(), "Appearing offline")
    SW.state.hidden = false
    stub.FireEvent("BN_INFO_CHANGED")
    frame(3)
    T.eq(f.status.text:GetText(), "Available")
    clean()
end)

-- The prompt's Accept, pressed by the player: a key or click of theirs around it.
local function accept(text)
    stub.Key(stub.Reply, text)
    stub.RunTimers()
end

T.test("social: Add friend and a broadcast reach the game inside the prompt's click (a timer loses it)", function()
    local ns = load()
    local f = open(ns)
    stub.errors = {}
    stub.Key(function() ns.Friends.page.add:Click() end)
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
    T.eq(panel(page), "closed")
    local odessa = rows(page.stack, "ally")[4]
    stub.Key(function() odessa:Click() end)
    T.eq(panel(page), "Invite, Whisper, Pin, Add friend")
    stub.Key(function() page.detail.buttons[1]:Click() end)
    T.eq(SW.Calls("InviteUnit")[1][1], "Odessa Reed")
    local shone = {}
    local real = DaylightUI.Win.Parts.Shine
    DaylightUI.Win.Parts.Shine = function(b) shone[#shone + 1] = b end
    stub.Key(function() page.detail.buttons[3]:Click() end)
    frame(3)
    DaylightUI.Win.Parts.Shine = real
    T.eq(SW.Calls("SetRecentAllyPinned")[1][2], true)
    T.eq(heads(page.stack), "PINNED 3 / 3 | RECENT 1 / 3")
    T.eq(shone[1] and shone[1].spec.ally.name, "Odessa Reed")
    T.eq(panel(page), "Invite, Whisper, Unpin, Add friend", "still picked")
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

T.test("social: not in a raid: the game's own explanation of raids shows under the button", function()
    local old = _G.RAID_DESCRIPTION
    _G.RAID_DESCRIPTION = "Raids are groups of more than 5 players.\n|cffffffff- Up to 40.|r"
    local ns = load()
    open(ns, SW.TAB.RaidList)
    local page = ns.Raid.page
    T.truthy(page.about, "the text")
    T.eq(page.about:GetText(), "Raids are groups of more than 5 players.\n- Up to 40.", "as the game words it, without its own colors")
    T.eq(page.about:GetJustifyH(), "LEFT", "left aligned, like the game draws it")
    T.truthy(page.leaderOnly and page.leaderOnly:IsShown(), "a line on who can convert")
    T.eq(page.leaderOnly:GetText(), "Only the party leader can do this.")
    T.truthy(page.about:IsShown())
    T.eq(page.about:GetFont() and select(2, page.about:GetFont()), DaylightUI.Style.SIZE.body, "body size, a sentence")
    local c, r, g, b = DaylightUI.Style.INK.TEXT, page.about:GetTextColor()
    T.near(r, c[1], 0.01, "in the sentence color")
    T.near(g, c[2], 0.01)
    T.near(b, c[3], 0.01)
    T.eq(#page.noRaidPieces, 4, "title, button, the leader line and the text: our own line is not there")
    _G.RAID_DESCRIPTION = nil
    local ns2 = load()
    open(ns2, SW.TAB.RaidList)
    T.eq(ns2.Raid.page.about, nil, "a client without it shows none")
    _G.RAID_DESCRIPTION = old
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

-- The detail card: a row picked widens the window and opens it on the right, it says who
-- and where, and it closes (the window goes back) when nothing is picked.
T.test("social: a picked friend opens a detail card on the right and the window widens for it", function()
    local ns = load()
    local win = open(ns)
    local page = ns.Friends.page
    local d = page.detail
    local Detail = ns.Detail
    local function listRight() return select(4, page.stack.scroll:GetPoint(2)) end
    T.eq(win:GetWidth(), ns.Window.W, "closed: the usual width")
    T.falsy(d.frame:IsShown())
    T.eq(listRight(), -page.stack.side)
    local mara = rows(page.stack, "friend")[1]
    stub.Key(function() mara:Click() end)
    frame(30)
    T.truthy(d.frame:IsShown(), "open")
    T.eq(d.frame:GetAlpha(), 1, "faded in")
    T.eq(win:GetWidth(), ns.Window.W + Detail.SPAN, "the window made room for it")
    T.eq(listRight(), -page.stack.side - Detail.SPAN, "the list stops short of it")
    T.eq(select(4, page.add:GetPoint(1)), -(ns.Friends.EDGE + Detail.SPAN), "the search and its button keep to the list")
    T.eq(d.frame.title:GetText(), "Ysella Dawnwhisper", "their character")
    T.eq(d.frame.sub:GetText(), "Mara", "and the account")
    T.falsy(d.frame.dot, "no status dot: the status has its own line")
    local seen = {}
    for _, r in ipairs(d.rows) do
        if r.value:IsShown() then seen[#seen + 1] = (r.label:IsShown() and (r.label:GetText() .. ": ") or "") .. r.value:GetText() end
    end
    local text = table.concat(seen, " | ")
    T.truthy(text:find("Level: 44", 1, true), "their level: " .. text)
    T.truthy(text:find("Race: Dwarf", 1, true), "their race: " .. text)
    T.truthy(text:find("Zone: Tanaris", 1, true), "where they are: " .. text)
    T.truthy(text:find("Note: Heals on Tuesdays", 1, true), "their note: " .. text)
    T.truthy(text:find("\"Running ZF later\"", 1, true), "what they said: " .. text)
    -- No Add friend on a friend: they are one already.
    for _, b in ipairs(d.buttons) do
        if b:IsShown() then T.truthy(b.text:GetText() ~= "Add friend", "no Add friend on a friend") end
    end
    -- Picked again: the card closes and the window goes back.
    stub.Key(function() mara:Click() end)
    frame(30)
    T.falsy(d.frame:IsShown(), "closed again")
    T.eq(win:GetWidth(), ns.Window.W)
    T.eq(listRight(), -page.stack.side)
    T.eq(select(4, page.add:GetPoint(1)), -ns.Friends.EDGE)
    -- A friend who's offline (Pip, folded under Offline until unfolded): who and when, and
    -- nothing to press.
    ns.Friends.folds.offline = nil
    stub.Key(function() ns.Friends.Render() end)
    frame(20)
    local pip
    for _, b in ipairs(rows(page.stack, "friend")) do if b.spec.friend.account == "Pip" then pip = b end end
    T.truthy(pip, "Pip is listed")
    stub.Key(function() pip:Click() end)
    frame(30)
    T.eq(panel(page), "", "nothing to press")
    T.eq(d.frame.title:GetText(), "Pip")
    clean()
end)

-- Add friend: a square button beside the search, not a button about the picked row.
T.test("social: Add friend is a square button beside the search", function()
    local ns = load()
    open(ns)
    local page = ns.Friends.page
    T.eq(page.add:GetWidth(), page.add:GetHeight(), "square")
    local p, rel = page.search:GetPoint(2)
    T.eq(rel, page.add, "the search stops short of it")
    T.truthy(page.add:IsShown())
    local q = ns.Friends.Pieces(page)
    local found
    for _, v in ipairs(q) do if v == page.add then found = true end end
    T.truthy(found, "the controller reaches it")
    clean()
end)

T.test("social: the add-friend button is a W.IconButton", function()
    local ns = load()
    open(ns)
    local page = ns.Friends.page
    T.truthy(page.add.SetIcon and page.add.icon, "W.IconButton")
    T.eq(page.add:GetWidth(), page.add:GetHeight(), "square")
end)

-- A friend already in your group has no Invite: not on the row, not in the panel.
T.test("social: a friend already in your group has no Invite, on the row or in the panel", function()
    local ns = load()
    open(ns)
    local page = ns.Friends.page
    local kit = rows(page.stack, "friend")[4]
    T.truthy(kit.action:IsShown(), "not grouped yet: a button")
    stub.Key(function() kit:Click() end)
    T.eq(panel(page), "Invite, Whisper")
    -- Thessaly Moor joins the party.
    stub.inGroup = true
    stub.SetUnits({ party1 = { name = "Thessaly Moor" } })
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    frame(20)
    kit = rows(page.stack, "friend")[4]
    T.falsy(kit.action:IsShown(), "in the group: no quick button")
    T.eq(panel(page), "Whisper", "and no Invite in the panel")
    T.falsy(ns.Data.CanInviteFriend(kit.spec.friend))
    -- A friend who isn't in it keeps theirs.
    T.truthy(rows(page.stack, "friend")[3] and true, "other rows are still there")
    stub.inGroup, stub.units = nil, {}
    clean()
end)

T.test("social: a name in a party or raid is found by its name, with or without a realm", function()
    local ns = load()
    local D = ns.Data
    stub.inGroup = true
    stub.SetUnits({ party2 = { name = "Odessa Reed" } })
    T.truthy(D.InGroup("Odessa Reed"))
    T.truthy(D.InGroup("Odessa Reed-Realm"), "a name with its realm")
    T.falsy(D.InGroup("Lirien Vale"))
    T.falsy(D.InGroup(nil))
    stub.inGroup, stub.inRaid, stub.groupSize = nil, true, 10
    stub.SetUnits({ raid7 = { name = "Lirien Vale" } })
    T.truthy(D.InGroup("Lirien Vale"), "in a raid too")
    stub.inRaid, stub.groupSize, stub.units = nil, nil, {}
    T.falsy(D.InGroup("Lirien Vale"), "not in a group at all")
end)

-- Recent allies: Invite only for someone online and not in your group, Add friend only
-- for someone who isn't a friend (a legacy friend already is one).
T.test("social: an ally's panel: Invite unless grouped or offline, Add friend unless a friend", function()
    local list = SW.Allies()
    -- An ally with the name of Kit's character: already a friend.
    local twin = SW.Allies()[3]
    twin.characterData.guid, twin.characterData.name, twin.characterData.fullName = "Player-9", "Thessaly Moor", "Thessaly Moor"
    list[#list + 1] = twin
    local ns = load({ allies = list })
    open(ns)
    tab(ns, "allies")
    local page = ns.Allies.page
    local function pickByName(name)
        for _, b in ipairs(rows(page.stack, "ally")) do
            if b.spec.ally.name == name then
                if ns.Allies.picked == b.spec.ally.guid then stub.Key(function() b:Click() end) end
                stub.Key(function() b:Click() end)
                return
            end
        end
        error("no ally " .. name)
    end
    pickByName("Odessa Reed")
    T.eq(panel(page), "Invite, Whisper, Pin, Add friend", "online, alone, not a friend")
    pickByName("Thessaly Moor")
    T.eq(panel(page), "Invite, Whisper, Pin", "a friend already: no Add friend")
    pickByName("Sabine Kett")
    T.eq(panel(page), "Invite, Whisper, Pin", "a legacy friend is a friend")
    pickByName("Fenwick Harrow")
    T.eq(panel(page), "Pin, Add friend", "offline: neither Invite nor Whisper")
    -- Odessa joins the party: no Invite for her.
    stub.inGroup = true
    stub.SetUnits({ party1 = { name = "Odessa Reed" } })
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    frame(20)
    pickByName("Odessa Reed")
    T.eq(panel(page), "Whisper, Pin, Add friend", "in the group: no Invite")
    -- The menu agrees.
    local row
    for _, b in ipairs(rows(page.stack, "ally")) do if b.spec.ally.name == "Odessa Reed" then row = b end end
    local m = menuOf(function() row.spec.onMenu(row) end)
    T.eq(table.concat(m.keys, ","), "whisper,pin,note,friend,ignore")
    stub.inGroup, stub.units = nil, {}
    clean()
end)

-- Each page keeps its own card: Allies widens the window on its own, and a page change
-- takes the window to that page's width.
T.test("social: an ally's card widens the window; each page keeps its own, the raid never", function()
    local ns = load()
    local win = open(ns)
    tab(ns, "allies")
    local page = ns.Allies.page
    local W = ns.Window
    T.eq(win:GetWidth(), W.W)
    local odessa
    for _, b in ipairs(rows(page.stack, "ally")) do if b.spec.ally.name == "Odessa Reed" then odessa = b end end
    stub.Key(function() odessa:Click() end)
    frame(30)
    T.eq(win:GetWidth(), W.W + ns.Detail.SPAN)
    T.eq(page.detail.frame.title:GetText(), "Odessa Reed")
    -- Friends has nothing picked: its width is the usual one.
    tab(ns, "friends")
    T.eq(win:GetWidth(), W.W, "Friends has no card")
    tab(ns, "allies")
    T.eq(win:GetWidth(), W.W + ns.Detail.SPAN, "Allies still does")
    tab(ns, "raid")
    T.eq(win:GetWidth(), W.RAID_W, "the raid keeps its own width")
    -- The controller's X presses the card's main button.
    tab(ns, "allies")
    T.truthy(page.detail.frame.padFooter, "found through padFooter")
    local main
    for _, b in ipairs(page.detail.buttons) do if b:IsShown() and b.spec and b.spec.primary then main = b end end
    T.eq(main and main.text:GetText(), "Invite")
    clean()
end)

-- A friend with no character (Sol plays another game, Pip is offline): the card still has
-- a name, their BattleTag under it, and a round badge with their initial where a class
-- icon would be.
T.test("social: a friend with no character: BattleTag under the name, an initial for the icon", function()
    local ns = load()
    open(ns)
    local page = ns.Friends.page
    local d = page.detail
    local sol
    for _, b in ipairs(rows(page.stack, "friend")) do if b.spec.friend.account == "Sol" then sol = b end end
    stub.Key(function() sol:Click() end)
    frame(30)
    T.eq(d.frame.title:GetText(), "Sol")
    T.eq(d.frame.sub:GetText(), "Sol#5555", "their BattleTag")
    T.falsy(d.frame.icon:IsShown(), "no class icon")
    T.truthy(d.frame.avatar:IsShown() and d.frame.letter:IsShown(), "a badge instead")
    T.eq(d.frame.letter:GetText(), "S")
    local seen = {}
    for _, r in ipairs(d.rows) do if r.value:IsShown() then seen[#seen + 1] = r.value:GetText() end end
    T.truthy(table.concat(seen, "|"):find("Diablo IV", 1, true), "the game they play: " .. table.concat(seen, "|"))
    clean()
end)

-- The titles over Zone, Faction and Server are tan (the accent is for a word or two) with a rule under them, and
-- each line has room.
T.test("social: the card's titles are tan with a rule under them", function()
    local ns = load()
    open(ns)
    local page = ns.Friends.page
    local d = page.detail
    stub.Key(function() rows(page.stack, "friend")[1]:Click() end)
    frame(30)
    local titled
    for _, r in ipairs(d.rows) do if r.label:IsShown() then titled = r; break end end
    T.truthy(titled, "a titled line")
    T.truthy(titled.rule:IsShown(), "with a rule")
    local ar, ag, ab = DaylightUI.Style.Accent()
    local lr, lg, lb = titled.label:GetTextColor()
    T.rgb({ lr, lg, lb }, DaylightUI.Style.INK.LABEL, "tan, like the other labels")
    T.falsy(math.abs(lr - ar) < 0.01 and math.abs(lg - ag) < 0.01 and math.abs(lb - ab) < 0.01, "not the accent")
    -- Titled lines keep their room: the next one starts a full line lower.
    local ys = {}
    for _, r in ipairs(d.rows) do if r.label:IsShown() then ys[#ys + 1] = select(5, r.label:GetPoint(1)) end end
    T.truthy(#ys >= 2 and ys[1] - ys[2] >= ns.Detail.ROW - 0.5, "room between titled lines")
    clean()
end)

-- A recent ally's class comes from C_CreatureInfo.GetClassInfo, the one the game has.
T.test("social: a recent ally's class is read from C_CreatureInfo", function()
    local ns = load({ allies = SW.Allies() })
    open(ns)
    tab(ns, "allies")
    local found
    for _, b in ipairs(rows(ns.Allies.page.stack, "ally")) do
        if b.spec.ally.name == "Odessa Reed" then found = b.spec.ally end
    end
    T.eq(found and found.class, "SHAMAN")
    T.falsy(_G.C_ClassInfo, "the game has no C_ClassInfo.GetClassInfo, and the fake game doesn't teach it")
    clean()
end)

-- An ally's race, faction and realm come from the character's race id and realm.
T.test("social: an ally's card has race, faction and server from the game's data", function()
    local creature = _G.C_CreatureInfo
    local race, faction = creature.GetRaceInfo, creature.GetFactionInfo
    creature.GetRaceInfo = function(id) return { raceName = id == 3 and "Dwarf" or "Human" } end
    creature.GetFactionInfo = function(id) return { groupTag = "Alliance", name = "Alliance" } end
    local list = SW.Allies()
    for _, a in ipairs(list) do a.characterData.realmName = "CAMWOW US1 Realm 8 PvP" end
    local ns = load({ allies = list })
    open(ns)
    tab(ns, "allies")
    local page = ns.Allies.page
    local odessa
    for _, b in ipairs(rows(page.stack, "ally")) do if b.spec.ally.name == "Odessa Reed" then odessa = b end end
    T.eq(odessa.spec.ally.race, "Dwarf"); T.eq(odessa.spec.ally.faction, "Alliance")
    stub.Key(function() odessa:Click() end)
    frame(30)
    local d = page.detail
    T.eq(d.frame.sub:GetText(), "Shaman")
    local seen = {}
    for _, r in ipairs(d.rows) do if r.value:IsShown() then seen[#seen + 1] = (r.label:IsShown() and (r.label:GetText() .. ": ") or "") .. r.value:GetText() end end
    local all = table.concat(seen, "|")
    T.truthy(all:find("Level: 43", 1, true), "level: " .. all)
    T.truthy(all:find("Race: Dwarf", 1, true), "race: " .. all)
    T.truthy(all:find("Alliance", 1, true), "faction: " .. all)
    T.falsy(all:find("CAMWOW", 1, true), "no Server block on an ally: " .. all)
    T.falsy(all:find("Server", 1, true), "none: " .. all)
    T.truthy(all:find("Faction: Alliance|History:", 1, true), "History comes under the faction: " .. all)
    creature.GetRaceInfo, creature.GetFactionInfo = race, faction
    clean()
end)

-- The name and the line under it are one block centered on the icon, the initial fills the
-- badge (so it sits in its middle), and the status has air under it before the titled lines.
T.test("social: the card's header is centered on the icon; the status has air under it", function()
    local ns = load()
    open(ns)
    local page = ns.Friends.page
    local d = page.detail
    local Detail = ns.Detail
    local sol
    for _, b in ipairs(rows(page.stack, "friend")) do if b.spec.friend.account == "Sol" then sol = b end end
    stub.Key(function() sol:Click() end)
    frame(30)
    local f = d.frame
    -- Two lines (name, BattleTag): the block's middle is the icon's middle.
    local top = -select(5, f.title:GetPoint(1))
    local titleH, subH = f.title:GetStringHeight() or Detail.NAME, f.sub:GetStringHeight() or (Detail.UNDER - 2)
    local middle = top + (titleH + 2 + subH) / 2
    T.truthy(math.abs(middle - (Detail.PAD + Detail.ICON / 2)) <= 1, "centered on the icon: " .. middle)
    T.eq(-select(5, f.sub:GetPoint(1)), top + titleH + 2, "the line under follows the name")
    -- The badge's letter fills it.
    T.eq(select(2, f.letter:GetPoint(1)), f.avatar, "the letter is anchored to the badge")
    T.eq(f.letter:GetJustifyH(), "CENTER")
    -- Mara: the status line, then room, then the first titled line.
    stub.Key(function() sol:Click() end)
    frame(30)
    local mara = rows(page.stack, "friend")[1]
    stub.Key(function() mara:Click() end)
    frame(30)
    local plainY, titledY
    for _, r in ipairs(d.rows) do
        if r.value:IsShown() then
            local y = -select(5, (r.label:IsShown() and r.label or r.value):GetPoint(1))
            if r.label:IsShown() then titledY = titledY or y elseif not titledY then plainY = y end
        end
    end
    T.truthy(titledY - plainY >= Detail.PLAIN + Detail.GAP_AFTER - 0.5, "air under the status: " .. tostring(titledY) .. " vs " .. tostring(plainY))
    clean()
end)

-- How you met, whole: its own titled block under the zone, wrapping onto more lines
-- instead of being cut; and the badge's letter has a box of its own.
T.test("social: an ally's History block shows the whole text under Zone; values wrap", function()
    local list = SW.Allies()
    local long = "You fought side by side in a long dungeon run and then traded a few things after it"
    list[4].interactionData.interactions[1].description = long
    list[4].stateData.currentLocation = "Stormwind City"
    local ns = load({ allies = list })
    open(ns)
    tab(ns, "allies")
    local page = ns.Allies.page
    local odessa
    for _, b in ipairs(rows(page.stack, "ally")) do if b.spec.ally.name == "Odessa Reed" then odessa = b end end
    stub.Key(function() odessa:Click() end)
    frame(30)
    local d = page.detail
    local order = {}
    for _, r in ipairs(d.rows) do
        if r.label:IsShown() then order[#order + 1] = r.label:GetText() .. "=" .. r.value:GetText() end
    end
    local all = table.concat(order, "|")
    local zone, history = all:find("Zone=", 1, true), all:find("History=", 1, true)
    T.truthy(zone and history and history > zone, "History comes after Zone: " .. all)
    T.truthy(all:find("History=" .. long, 1, true), "the whole text, not cut: " .. all)
    T.eq(d.frame.letter:GetWidth(), ns.Detail.ICON, "the letter's box is the badge's size")
    T.eq(d.frame.letter:GetHeight(), ns.Detail.ICON)
    clean()
end)

-- A Battle.net name can come as a protected string ("|K...|k") that only a FontString can
-- draw: the badge's letter then comes from the plain BattleTag, never a "|".
T.test("social: the badge's letter of a friend with a protected name comes from the BattleTag", function()
    local friends = SW.Friends()
    friends[5].accountName = "|Kq1|k0000005|k"
    local ns = load({ friends = friends })
    open(ns)
    local page = ns.Friends.page
    local sol
    for _, b in ipairs(rows(page.stack, "friend")) do if b.spec.friend.tag == "Sol#5555" then sol = b end end
    T.truthy(sol, "Sol is listed")
    stub.Key(function() sol:Click() end)
    frame(30)
    T.eq(page.detail.frame.letter:GetText(), "S", "their initial, not the escape's bar")
    clean()
end)

-- The list's right edge eases to and from the card's room like the window does, and the
-- rows are laid out once it's there (CONTRIBUTING: what changes size eases).
T.test("social: the list's edge eases when the card opens and closes", function()
    local ns = load()
    open(ns)
    local page = ns.Friends.page
    local side, span = page.stack.side, ns.Detail.SPAN
    local function inset() return -select(4, page.stack.scroll:GetPoint(2)) end
    T.eq(inset(), side)
    local mara = rows(page.stack, "friend")[1]
    stub.Key(function() mara:Click() end)
    frame(3)
    local mid = inset()
    T.truthy(mid > side and mid < side + span, "on its way in: " .. mid)
    local addMid = -select(4, page.add:GetPoint(1))
    T.truthy(addMid > ns.Friends.EDGE and addMid < ns.Friends.EDGE + span, "the search's button goes with it: " .. addMid)
    frame(30)
    T.eq(inset(), side + span, "all the way")
    stub.Key(function() mara:Click() end)
    frame(3)
    local back = inset()
    T.truthy(back > side and back < side + span, "on its way out: " .. back)
    frame(30)
    T.eq(inset(), side, "back where it was")
    clean()
end)

-- Review fixes ---------------------------------------------------------------------------

-- The controller's X finds the card's main button: the controller looks for a window's
-- parts only on a page change or when the window gets the focus, and the card was still
-- hidden then.
T.test("social: the controller's X presses the card's Invite once the card has opened", function()
    local ns = load()
    local win = open(ns)
    local Pad = DaylightUI.Pad
    Pad.focused = win
    local page = ns.Friends.page
    local kit = rows(page.stack, "friend")[4]
    stub.Key(function() kit:Click() end)
    frame(30)
    T.truthy(win.padFoot, "the card's parts were looked up when it opened")
    T.eq(win.padFoot.frame, page.detail.frame)
    T.truthy(Pad.FOOTER_KEY.when(), "X has a main button to press")
    Pad.focused = nil
    clean()
end)

-- Resizing with the card open keeps the window's own width, not the card's room.
T.test("social: a window resized with the card open doesn't keep the card's width", function()
    local ns = load()
    local win = open(ns)
    local page = ns.Friends.page
    local W, SPAN = ns.Window.W, ns.Detail.SPAN
    local kit = rows(page.stack, "friend")[4]
    stub.Key(function() kit:Click() end)
    frame(30)
    T.eq(win:GetWidth(), W + SPAN)
    win.GetLeft = function() return 100 end
    win.GetTop = function() return 700 end
    local e = win:GetEffectiveScale()
    stub.cursorPos = { 800 * e, 137 * e }
    win.grip:GetScript("OnMouseDown")(win.grip, "LeftButton")
    stub.cursorPos = { 850 * e, 137 * e }
    stub.RunOnUpdate(win.grip, 1 / 30)
    win.grip:GetScript("OnMouseUp")(win.grip, "LeftButton")
    frame(5)
    T.eq(win:GetWidth(), W + SPAN + 50, "50 px wider with the card")
    T.eq(ns.module.db.sizes.friends[1], W + 50, "what is kept leaves the card's room out")
    -- The card closes: the list keeps the 50 px, not the card's.
    stub.Key(function() kit:Click() end)
    frame(30)
    T.eq(win:GetWidth(), W + 50, "the window goes back to its own width")
    -- And it opens at that size plus the card again.
    stub.Key(function() kit:Click() end)
    frame(30)
    T.eq(win:GetWidth(), W + 50 + SPAN)
    clean()
end)

-- A larger text scale makes the lines taller: nothing is laid on top of anything.
T.test("social: the card lays its lines out by their real height (a larger text scale)", function()
    local ns = load()
    open(ns)
    local page = ns.Friends.page
    local d = page.detail
    -- Texts taller than at the default size, as at a text scale of 1.6.
    local function tall(fs, h) fs.GetStringHeight = function() return h end end
    tall(d.frame.title, 30); tall(d.frame.sub, 24)
    for _, r in ipairs(d.rows) do tall(r.label, 24); tall(r.value, 24) end
    local mara = rows(page.stack, "friend")[1]
    stub.Key(function() mara:Click() end)
    frame(30)
    local f = d.frame
    local titleY, subY = -select(5, f.title:GetPoint(1)), -select(5, f.sub:GetPoint(1))
    T.truthy(subY >= titleY + 30, "the second line starts under the name: " .. titleY .. " / " .. subY)
    local ruleY = -select(5, f.rule:GetPoint(1))
    T.truthy(ruleY >= subY + 24, "the header's rule is under both: " .. ruleY)
    local shown = {}
    for _, r in ipairs(d.rows) do if r.value:IsShown() then shown[#shown + 1] = r end end
    T.truthy(#shown >= 3, "lines to compare")
    local prevEnd = ruleY
    for _, r in ipairs(shown) do
        local top = -select(5, (r.label:IsShown() and r.label or r.value):GetPoint(1))
        T.truthy(top >= prevEnd, "a line starts below the one before: " .. top .. " vs " .. prevEnd)
        local valueY = -select(5, r.value:GetPoint(1))
        if r.label:IsShown() then
            local rule = -select(5, r.rule:GetPoint(1))
            T.truthy(rule >= top + 24, "its rule is under its title")
            T.truthy(valueY > rule, "and its value under the rule")
        end
        prevEnd = valueY + 24
    end
    clean()
end)

-- Two players of one name on different realms are two players.
T.test("social: a same-named player of another realm doesn't hide Invite or Add friend", function()
    local ns = load()
    local D = ns.Data
    _G.GetNormalizedRealmName = function() return "Stormrage" end
    local was = _G.UnitName
    _G.UnitName = function(u) if u == "party1" then return "Odessa Reed", "Area52" end end
    stub.inGroup = true
    T.truthy(D.InGroup("Odessa Reed", "Area 52"), "the one in your group (the realm spelled as it is shown)")
    T.truthy(D.InGroup("Odessa Reed-Area52"), "a name with its realm")
    T.falsy(D.InGroup("Odessa Reed", "Stormrage"), "the same name on your own realm is someone else")
    T.falsy(D.InGroup("Odessa Reed-Stormrage"))
    T.truthy(D.InGroup("Odessa Reed"), "no realm known: by the name")
    -- A unit of your own realm carries no realm in its name.
    _G.UnitName = function(u) if u == "party2" then return "Lirien Vale" end end
    T.truthy(D.InGroup("Lirien Vale", "Stormrage"))
    T.falsy(D.InGroup("Lirien Vale", "Area 52"))
    -- Friends: a friend's character of the same name on another realm isn't this ally.
    local friends = SW.Friends()
    friends[3].gameAccountInfo.realmName = "Area52"
    friends[3].gameAccountInfo.characterName = "Odessa Reed"
    local ns2 = load({ friends = friends })
    local D2 = ns2.Data
    _G.GetNormalizedRealmName = function() return "Stormrage" end
    T.falsy(D2.IsFriendName("Odessa Reed", "Stormrage"), "same name, another realm: not your friend")
    T.truthy(D2.IsFriendName("Odessa Reed", "Area 52"), "the same realm: your friend")
    T.truthy(D2.IsFriendName("Odessa Reed-Area52"), "a name with its realm")
    _G.UnitName, _G.GetNormalizedRealmName, stub.inGroup = was, nil, nil
end)

-- A friend already in a group: the game asks to be invited into theirs, and says so.
T.test("social: a friend in a group has Request invite where it would say Invite", function()
    local friends = SW.Friends()
    friends[3].gameAccountInfo.playerGuid = "Player-kit"
    local ns = load({ friends = friends })
    _G.GetDisplayedInviteType = function(guid) return guid == "Player-kit" and "REQUEST_INVITE" or "INVITE" end
    open(ns)
    local page = ns.Friends.page
    local kit = rows(page.stack, "friend")[4]
    T.eq(ns.Data.InviteKind(kit.spec.friend), "REQUEST_INVITE")
    T.eq(ns.Friends.InviteWord(kit.spec.friend), "Request invite")
    stub.Key(function() kit:Click() end)
    frame(30)
    T.eq(panel(page), "Request invite, Whisper", "the card's button")
    local m = menuOf(function() kit.spec.onMenu(kit) end)
    T.eq(m.values.invite, "Request invite", "the menu's")
    -- Anyone else is invited.
    local other = rows(page.stack, "friend")[1]
    T.eq(ns.Data.InviteKind(other.spec.friend), "INVITE")
    _G.GetDisplayedInviteType = nil
    clean()
end)

T.test("social: your BattleTag is in the header on every tab, and a click shows it selected to copy", function()
    local ns = load()
    local f = open(ns, "friends")
    T.eq(ns.Friends.page.copyTag, nil, "not a Friends piece: the search keeps its room")
    T.truthy(f.tag:IsShown(), "your tag is there")
    T.eq(f.tag.text:GetText(), "Curt#1674")
    local _, rel = f.tagDot:GetPoint(1)
    T.eq(rel, f.status.text, "right after the status, on its row")
    local _, tagAt = f.tag.text:GetPoint(1)
    T.eq(tagAt, f.tagDot, "the tag follows the separator")
    local _, linkAt = f.tag:GetPoint(1)
    T.eq(linkAt, f.tag.text, "its mouse area is its words")
    local _, onlineAt = f.online:GetPoint(1)
    T.eq(onlineAt, f.tag.text, "and the friends online follow the tag")
    for _, id in ipairs({ "allies", "requests", "raid" }) do
        stub.Key(function() ns.Window.ShowTab(id, true) end)
        frame(20)
        T.truthy(f.tag:IsShown(), id .. " shows it too")
    end
    local W, was, got = DaylightUI.Widgets, DaylightUI.Widgets.Tooltip, {}
    W.Tooltip = function(owner, title, desc) got[owner] = { title, desc } end
    for _, w in ipairs({ { f.status, "Change status" }, { f.tag, "Copy your BattleTag" } }) do
        w[1]:GetScript("OnEnter")(w[1])
        T.eq(got[w[1]] and got[w[1]][1], w[2], "its title")
        T.truthy(type(got[w[1]][2]) == "string" and got[w[1]][2] ~= "", w[2] .. ": and a description")
    end
    W.Tooltip = was
    stub.Key(function() f.tag:GetScript("OnClick")(f.tag) end)
    frame(5)
    local ask = DaylightUI.Widgets.Asking()
    T.truthy(ask, "the box with the tag")
    T.eq(ask.input.initial, "Curt#1674")
    T.eq(ask.input.locked, true, "selected for Ctrl+C, not editable")
    DaylightUI.Widgets.Answer(true)
    frame(5)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    clean()
end)

-- Tabs wider than the header (a bigger font, a long translation) leave the title no
-- width, and the client then gives it no height either: a status row hung under the
-- title rode up into the tabs, its dots between them and the BattleTag link under
-- Recent allies. The fake game doesn't lay frames out, so this checks what each
-- piece of the row hangs from: never the squeezed title, never a tab, and each text
-- by its top so a tab's middle can't move it.
T.test("social: the status row keeps its line under the tabs when the tabs leave the title no room", function()
    local ns = load()
    local f = open(ns, "friends")
    local _, subAt = f.sub:GetPoint(1)
    T.truthy(subAt ~= f.title, "the sub line doesn't hang from the title the tabs squeeze")
    T.eq(subAt, f.titleLine, "it hangs from a line of the title's size")
    T.eq(f.titleLine:GetNumPoints(), 1, "which nothing squeezes")
    local tabs = {}
    for _, b in ipairs(f.tabs) do tabs[b] = true end
    for name, piece in pairs({ statusDot = f.statusDot, status = f.status, statusText = f.status.text,
        tagDot = f.tagDot, tag = f.tag, tagText = f.tag.text, online = f.online }) do
        for i = 1, piece:GetNumPoints() do
            local point, rel = piece:GetPoint(i)
            T.falsy(tabs[rel], name .. " never hangs from a tab")
            T.truthy(rel ~= f.title, name .. " never hangs from the title")
            if i == 1 and piece:GetObjectType() == "FontString" and piece ~= f.status.text then
                T.truthy(point:find("TOP"), name .. " hangs by its top: " .. point)
            end
        end
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    clean()
end)

T.test("social: without a BattleTag (not connected) the header has none", function()
    local old = _G.BNGetInfo
    local ns = load()
    _G.BNGetInfo = function() return 1, nil, nil, "", false, false, false end
    local f = open(ns, "friends")
    T.eq(f.tag:IsShown(), false)
    T.eq(f.tagDot:IsShown(), false, "no lone separator either")
    local _, onlineAt = f.online:GetPoint(1)
    T.eq(onlineAt, f.status.text, "the friends online follow the status")
    _G.BNGetInfo = old
    clean()
end)
