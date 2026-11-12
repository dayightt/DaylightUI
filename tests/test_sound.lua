local stub = require("stub")

-- Soft UI sounds (Sound.lua): ours in place of the game's UI clicks.

-- Kit ids handed out on first read, so any kit name has a number.
local function soundkits()
    local n = 1000
    return setmetatable({ LEVELUP = 888 }, { __index = function(t, k)
        n = n + 1
        rawset(t, k, n)
        return n
    end })
end

local function login(opts)
    opts = opts or {}
    local W = { played = {}, kits = {}, muted = {}, unmuted = {} }
    local DUI = stub.Load({ login = false, before = function()
        _G.SOUNDKIT = soundkits()
        _G.PlaySound = function(kit) W.kits[#W.kits + 1] = kit end
        _G.PlaySoundFile = function(file, channel) W.played[#W.played + 1] = { file, channel } end
        _G.MuteSoundFile = function(id) W.muted[id] = true end
        _G.UnmuteSoundFile = function(id) W.muted[id] = nil; W.unmuted[id] = true end
        if opts.before then opts.before() end
    end })
    DUI.Sound.REPLACE = opts.replace or { TEST_OPEN = { ours = "open", files = { 111, 112 } } }
    stub.FireEvent("PLAYER_LOGIN")
    stub.RunTimers()
    -- A brand-new character's setup guide opens at login (and plays open):
    -- start each test from silence.
    stub.Advance(1)
    for k in pairs(W.played) do W.played[k] = nil end
    for k in pairs(W.kits) do W.kits[k] = nil end
    return DUI, W
end

local function last(W) local p = W.played[#W.played]; return p and p[1] end

T.test("sound: Sound.Kit plays a game kit, once per GAP, and a kind's None keeps it quiet", function()
    local DUI, W = login()
    DUI.Sound.Kit("ITEM_REPAIR", "confirms")
    DUI.Sound.Kit("ITEM_REPAIR", "confirms")
    T.deq(W.kits, { SOUNDKIT.ITEM_REPAIR }, "asked twice at once, heard once")
    stub.Advance(DUI.Sound.GAP + 0.01)
    DUI:Set("general", "soundKinds.confirms", "none")
    DUI.Sound.Kit("ITEM_REPAIR", "confirms")
    T.eq(#W.kits, 1, "Confirmations: None")
    DUI.Sound.Kit("IG_WRITE_QUEST")
    T.eq(#W.kits, 2, "no kind: it always plays")
    DUI.Sound.Kit("NOT_A_KIT_THE_GAME_HAS_SOUNDKIT", nil)
end)

T.test("sound: a replaced kit plays ours once, on the SFX channel, and its files are muted", function()
    local DUI, W = login()
    PlaySound(SOUNDKIT.TEST_OPEN)
    T.eq(#W.played, 1)
    T.eq(last(W), DUI.Sound.FILES.open); T.eq(W.played[1][2], "SFX")
    T.truthy(W.muted[111]); T.truthy(W.muted[112])
    T.truthy(DUI.DB.Root().uiSoundsMuted[111], "remembered as ours")
end)

T.test("sound: a kit not in the list plays nothing of ours", function()
    local _, W = login()
    PlaySound(SOUNDKIT.LEVELUP)
    T.eq(#W.played, 0)
end)

T.test("sound: the same sound at most once per 0.1 s", function()
    local DUI, W = login()
    DUI.Sound.Play("click"); DUI.Sound.Play("click")
    T.eq(#W.played, 1)
    stub.Advance(0.11)
    DUI.Sound.Play("click")
    T.eq(#W.played, 2)
end)

T.test("sound: switched off, the game's files are unmuted at once and ours stay quiet", function()
    local DUI, W = login()
    DUI:Set("general", "sounds", false)
    stub.RunTimers()
    T.truthy(W.unmuted[111]); T.isnil(W.muted[111])
    T.isnil(DUI.DB.Root().uiSoundsMuted)
    PlaySound(SOUNDKIT.TEST_OPEN); DUI.Sound.Play("toggle")
    T.eq(#W.played, 0)
end)

T.test("sound: a window wired with Motion.Window plays open on show and close as it goes", function()
    local DUI, W = login()
    local f = CreateFrame("Frame", nil, UIParent)
    f:Hide()
    DUI.Motion.Window(f)
    f:Show()
    T.eq(last(W), DUI.Sound.FILES.open)
    stub.Advance(0.2)
    DUI.Motion.Vanish(f)
    T.eq(last(W), DUI.Sound.FILES.close)
    T.eq(#W.played, 2, "each once")
end)

T.test("sound: every shipped replacement names one of our sounds and at least one file", function()
    local DUI = stub.Load()
    local n = 0
    for kit, r in pairs(DUI.Sound.REPLACE) do
        n = n + 1
        T.truthy(DUI.Sound.FILES[r.ours], kit .. ": a sound of ours")
        T.truthy(type(r.files) == "table" and #r.files > 0, kit .. ": its files")
        for _, id in ipairs(r.files) do T.eq(type(id), "number", kit) end
    end
    T.truthy(n > 0, "some kits replaced")
end)

T.test("sound: an options toggle plays toggle, a menu pick or page click plays click", function()
    local DUI, W = login()
    DUI.OptionsPanel.Show("appearance")
    stub.RunTimers(); stub.Advance(1)
    local row
    for _, card in ipairs(DUI.OptionsPanel.PageFrame().cards) do
        for _, r in ipairs(card.rows) do if r.item.key == "motion" then row = r end end
    end
    T.truthy(row, "the Motion effects row")
    row.control:Click()
    T.eq(last(W), DUI.Sound.FILES.toggle)
end)

-- One choice per kind (general.soundKinds): soft, the game's own, none.
local function kind(DUI, k, v)
    DUI:Set("general", "soundKinds." .. k, v)
    stub.RunTimers()
end

T.test("sound kinds: every kind starts soft, and every sound with a kind names a real one", function()
    local DUI = login()
    for _, k in pairs(DUI.Sound.KINDS) do
        T.eq(DUI:Get("general", "soundKinds." .. k), "soft", k)
        T.truthy(DUI.Sound.SAMPLE[k], k .. ": a sample")
    end
end)

T.test("sound kinds: the game's own unmutes that kind's files, and our windows play the game's kit", function()
    local DUI, W = login()
    kind(DUI, "windows", "game")
    T.isnil(W.muted[111]); T.truthy(W.unmuted[111]); T.isnil(W.muted[112])
    PlaySound(SOUNDKIT.TEST_OPEN)
    T.eq(#W.played, 0, "the game's kit plays the game's file, not ours")
    stub.Advance(1)
    W.kits = {}
    DUI.Sound.Play("open")
    T.eq(#W.played, 0)
    T.deq(W.kits, { SOUNDKIT.IG_CHARACTER_INFO_OPEN }, "ours plays the game's open")
    DUI.Sound.Play("click")
    T.eq(last(W), DUI.Sound.FILES.click, "other kinds stay soft")
end)

T.test("sound kinds: the game's kit and ours at once are heard once", function()
    local DUI, W = login()
    kind(DUI, "windows", "game")
    W.kits = {}
    PlaySound(SOUNDKIT.TEST_OPEN)
    DUI.Sound.Play("open")
    T.deq(W.kits, { SOUNDKIT.TEST_OPEN })
end)

T.test("sound kinds: none keeps the game's files muted and plays nothing", function()
    local DUI, W = login()
    kind(DUI, "windows", "none")
    T.truthy(W.muted[111]); T.truthy(W.muted[112])
    PlaySound(SOUNDKIT.TEST_OPEN); DUI.Sound.Play("open"); DUI.Sound.Play("close")
    T.eq(#W.played, 0)
    kind(DUI, "snaps", "none")
    DUI.Sound.Play("snap")
    T.eq(#W.played, 0)
    DUI.Sound.Play("toggle")
    T.eq(last(W), DUI.Sound.FILES.toggle, "toggles still soft")
end)

T.test("sound kinds: back to soft mutes the files again", function()
    local DUI, W = login()
    kind(DUI, "windows", "game")
    T.isnil(W.muted[111])
    kind(DUI, "windows", "soft")
    T.truthy(W.muted[111]); T.truthy(DUI.DB.Root().uiSoundsMuted[111])
end)

T.test("sound kinds: only files we muted are ever unmuted, never another addon's", function()
    local DUI, W = login({ replace = {
        TEST_OPEN = { ours = "open", files = { 111 } },
        TEST_CLICK = { ours = "click", files = { 200 } },
    } })
    kind(DUI, "clicks", "game")
    T.isnil(W.muted[200], "ours lifted")
    T.isnil(DUI.DB.Root().uiSoundsMuted[200])
    W.unmuted = {}
    W.muted[200] = true                 -- another addon mutes it
    kind(DUI, "windows", "none")        -- any later pass
    T.truthy(W.muted[200], "theirs stays muted")
    T.isnil(W.unmuted[200])
    T.truthy(W.muted[111]); T.truthy(DUI.DB.Root().uiSoundsMuted[111])
end)

T.test("sound kinds: the old yes/no mark lifts the game kinds' files once, then only ours are kept", function()
    local DUI, W = login({ replace = {
        TEST_OPEN = { ours = "open", files = { 111 } },
        TEST_CLICK = { ours = "click", files = { 200 } },
    } })
    kind(DUI, "clicks", "game")
    W.unmuted = {}
    DUI.DB.Root().uiSoundsMuted = true  -- saved by an older version
    DUI.Sound.ApplyMutes()
    T.truthy(W.unmuted[200], "as before, once")
    local saved = DUI.DB.Root().uiSoundsMuted
    T.eq(type(saved), "table"); T.truthy(saved[111]); T.isnil(saved[200])
end)

T.test("sound kinds: the master switch off wins over every kind, the game's own included", function()
    local DUI, W = login()
    kind(DUI, "windows", "game"); kind(DUI, "clicks", "none")
    DUI:Set("general", "sounds", false)
    stub.RunTimers(); stub.Advance(1)
    W.kits = {}
    DUI.Sound.Play("open"); DUI.Sound.Play("click")
    T.eq(#W.played, 0); T.eq(#W.kits, 0)
    T.isnil(W.muted[111]); T.isnil(DUI.DB.Root().uiSoundsMuted)
end)

T.test("sound kinds: a pick is heard once, a moment later, in the new choice", function()
    local DUI, W = login()
    kind(DUI, "snaps", "soft")
    DUI.Sound.Sample("snaps")
    stub.RunTimers()
    T.eq(last(W), DUI.Sound.FILES.snap)
end)

T.test("sound kinds: the Sound card has a dropdown per kind, grayed with the master switch off", function()
    local DUI = login()
    DUI.OptionsPanel.Show("appearance")
    stub.RunTimers(); stub.Advance(1)
    local rows = {}
    for _, card in ipairs(DUI.OptionsPanel.PageFrame().cards) do
        for _, r in ipairs(card.rows) do if r.item.key then rows[r.item.key] = r end end
    end
    for _, k in pairs(DUI.Sound.KINDS) do
        local r = rows["soundKinds." .. k]
        T.truthy(r, k .. ": a row")
        T.eq(r.item.type, "dropdown", k)
        T.falsy(r.item.disabled(function(key) return DUI:Get("general", key) end), k .. ": on")
    end
    DUI:Set("general", "sounds", false)
    T.eq(rows["soundKinds.windows"].item.disabled(function(key) return DUI:Get("general", key) end), true)
end)

T.test("sound: a loop plays its file again and again, and stops with a fade", function()
    local DUI, W = login()
    local handles, stopped = 0, {}
    _G.PlaySoundFile = function(file, channel)
        W.played[#W.played + 1] = { file, channel }
        handles = handles + 1
        return true, handles
    end
    _G.StopSound = function(h, ms) stopped[#stopped + 1] = { h, ms } end
    local loop = DUI.Sound.Loop("campfire", 7.5)
    T.truthy(loop, "a loop")
    T.eq(#W.played, 1); T.eq(last(W), DUI.Sound.FILES.campfire); T.eq(W.played[1][2], "SFX")
    stub.RunTimers()
    T.truthy(#W.played >= 2, "played again")
    local n = #W.played
    DUI.Sound.StopLoop(loop, 1.2)
    T.truthy(#stopped >= 1, "the copies playing are stopped")
    T.eq(stopped[#stopped][2], 1200, "fading out over the time asked, in ms")
    stub.RunTimers()
    T.eq(#W.played, n, "and never played again")
    DUI.Sound.StopLoop(loop, 1)   -- twice is harmless
    DUI.Sound.StopLoop(nil, 1)
    DUI:Set("general", "sounds", false)
    T.isnil(DUI.Sound.Loop("campfire", 7.5), "Soft UI sounds off: no loop")
    _G.StopSound = nil
end)
