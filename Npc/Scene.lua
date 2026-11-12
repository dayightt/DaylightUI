-- Immersive look for the NPC window (look = "immersive"). Gossip and quest pages show
-- as a card on the right while the rest of the UI fades out and the camera moves in
-- over the player's shoulder. Vendor and trainer stay in the normal window, since
-- their lists need the room.
--
-- This is a second window on the same kit and talk page (Npc.Fill, same rows, footer
-- and keys). Npc.FrameFor in Window.lua picks which one shows a page.

local _, DUI = ...
DUI.Npc = DUI.Npc or {}
local ns = DUI.Npc

local Scene = {}
ns.Scene = Scene

Scene.NAME = "DaylightUINpcScene"
Scene.W, Scene.H = 460, 560  -- created size; Scene.Place fits it to the screen
Scene.WIDE = 0.3             -- fraction of screen width the card takes
Scene.MIN_W, Scene.MAX_W = 440, 620
Scene.TALL = 0.7             -- max fraction of screen height
Scene.SHORT = 260            -- min height (short gossip)
Scene.RIGHT = 0.06           -- fraction of screen width between card and right edge
Scene.SIDE = 24              -- px of margin on each side
Scene.TOP = 16               -- px above the text
Scene.SPACING = 5            -- px between lines of NPC text
Scene.AIR = 4                -- extra px between choices
Scene.SLIDE = 30             -- px it glides in from the right
Scene.STEP = 0.09            -- s between choices fading in after the text
Scene.CPS = 70               -- letters per second when typing text out
Scene.SAY = DUI.Style.SIZE.body
Scene.SOFT = 30              -- letters over which the typing edge fades
Scene.ALL = 4096             -- any index past the end of the text: show it all
-- Camera, using the game's test camera CVars (same ones DialogueUI uses).
Scene.ZOOM = 4               -- yards, close enough for a person-sized NPC
Scene.MOVED = 0.5            -- yards: already this close, so leave it alone
Scene.SETTLE = 3             -- s until the game's own zoom easing has surely finished
Scene.SHOULDER = 1.5         -- yards to the right of the player, so the NPC ends up centered
Scene.CAMERA = {             -- each CVar and its fully-in value
    test_cameraTargetFocusInteractEnable = 1,
    test_cameraTargetFocusInteractStrengthPitch = 1,
    test_cameraTargetFocusInteractStrengthYaw = 0,
    test_cameraOverShoulder = Scene.SHOULDER,
    test_cameraHeadMovementStrength = 0,
    CameraKeepCharacterCentered = 0,                 -- otherwise these keep the camera on the player
    CameraReduceUnexpectedMovement = 0,
}
Scene.EASED = { test_cameraTargetFocusInteractStrengthPitch = true, test_cameraOverShoulder = true }
-- This event shows the game's "experimental feature" warning (see
-- Blizzard_GameShared/EventRouting.lua). It's silenced only while the camera is moved.
Scene.WARNING = "EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED"
Scene.QUIET = 1              -- s the warning stays silenced after a camera change
-- UIParent fades out; these frames stay visible: the card, plus the tooltips and
-- popups a talk can bring up (reward tooltips and comparisons, the PvP quest prompt,
-- the red "you must choose a reward" error).
Scene.KEEP = { "GameTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "ItemRefTooltip", "UIErrorsFrame",
    "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4" }

local Win = DUI.Win
local Motion = DUI.Motion

local function on(key) return ns.Setting(key) ~= false end

-- Typed-out text (Text Slow Mode)

local typer = { fs = nil, text = nil, shown = 0, len = 0 }

-- Choices below the text wait for it, then fade in one at a time.
local held
local function reveal()
    if not held then return end
    local list = held
    held = nil
    for i, p in ipairs(list) do Win.Feel.Piece(p, (i - 1) * Scene.STEP) end
end

-- Called after the page opens: hide everything under the text until it's typed out.
function Scene.Hold(page, said)
    if not (Scene.Typing() and page and page.pieces and said) then return end
    held = {}
    local after = false
    for _, p in ipairs(page.pieces) do
        if after then
            held[#held + 1] = p
            Win.Feel.Piece(p, 3600)   -- reveal() starts it again
        end
        if p == said then after = true end
    end
end

local function paintType()
    local fs = typer.fs
    if not fs then return end
    if typer.shown >= typer.len then
        fs:SetAlphaGradient(Scene.ALL, Scene.SOFT)
        Scene.frame.typer:Hide()
        reveal()
        return
    end
    fs:SetAlphaGradient(math.floor(typer.shown), Scene.SOFT)
end

-- Start typing fs out, unless it already shows this text (a refill keeps going).
function Scene.Type(fs, text)
    if not (Scene.frame and fs) then return end
    if typer.fs == fs and typer.text == text then return paintType() end
    Scene.Clear()   -- pooled strings must not keep a half-faded edge
    typer.fs, typer.text = fs, text
    typer.len = string.len(text or "")
    typer.shown = (Motion.On() and ns.Setting("typeText") == true) and 0 or typer.len
    if typer.shown < typer.len then Scene.frame.typer:Show() end
    paintType()
end

-- Show the text being typed in full and stop tracking it.
function Scene.Clear()
    reveal()
    if typer.fs then typer.fs:SetAlphaGradient(Scene.ALL, Scene.SOFT) end
    typer.fs, typer.text, typer.shown, typer.len = nil, nil, 0, 0
    if Scene.frame then Scene.frame.typer:Hide() end
end

function Scene.Typing() return typer.fs ~= nil and typer.shown < typer.len end

-- Skip to the end (click or Space).
function Scene.Finish()
    typer.shown = typer.len
    paintType()
end

local function tick(_, dt)
    typer.shown = typer.shown + dt * Scene.CPS
    DUI.Sound.Kit("IG_WRITE_QUEST")   -- the quill sound QuestFrame.lua plays while quest text fades in
    paintType()
end

-- Camera: move in over the shoulder toward the NPC, then back.
-- The player's own camera CVars are saved per account (DB.Root().npcCamera) before
-- the first change and restored when the talk ends, on logout or /reload, and on the
-- next login if the game closed mid-talk.

local function getCVar(name)
    local fn = (C_CVar and C_CVar.GetCVar) or GetCVar
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, name)
    return ok and v or nil
end

local function setCVar(name, v)
    local fn = (C_CVar and C_CVar.SetCVar) or SetCVar
    if type(fn) == "function" then pcall(fn, name, tostring(v)) end
end

local function kept()
    local root = DUI.DB and DUI.DB.Root and DUI.DB.Root()
    if not root then return nil end
    return root.npcCamera
end

-- Silence the warning now and restore the game's handler Scene.QUIET s after the
-- last change.
local quietRun = 0
local function quiet()
    local G = _G.GameEvent
    if type(G) ~= "table" or type(G.UnregisterInternalEvent) ~= "function" then return end
    G.UnregisterInternalEvent(Scene.WARNING)
    quietRun = quietRun + 1
    local run = quietRun
    C_Timer.After(Scene.QUIET, function()
        if run ~= quietRun then return end
        if type(G.RegisterInternalEvent) == "function" and type(G.HandleExperimentalCVarConfirmationNeeded) == "function" then
            G.RegisterInternalEvent(Scene.WARNING, G.HandleExperimentalCVarConfirmationNeeded)
        end
    end)
end
Scene.Quiet = quiet

-- p: 0 = player's camera, 1 = fully in.
local function paintCamera(p)
    Scene.cameraAt = p
    local from = kept() or {}
    for name in pairs(Scene.EASED) do
        local mine = tonumber(from[name]) or 0
        setCVar(name, mine + (Scene.CAMERA[name] - mine) * p)
    end
end
Scene.PaintCamera = paintCamera

local function zoomNow()
    if type(GetCameraZoom) ~= "function" then return nil end
    local z = GetCameraZoom()
    if type(z) ~= "number" or (issecretvalue and issecretvalue(z)) then return nil end
    return z
end

-- The game's zoom calls set a target and ease toward it, while GetCameraZoom reports
-- the current position mid-ease. So undo the zoom by the same distance it moved in,
-- never from a reading. Scene.zoomFrom is the player's zoom while in, Scene.zoomBack
-- while returning.
local ours = false
local function zoomBy(fn, yards)
    if type(fn) ~= "function" then return end
    ours = true
    fn(yards)
    ours = false
end

local function zoomHome()
    local from = Scene.zoomFrom
    Scene.zoomFrom = nil
    if not from then return end
    Scene.zoomBack, Scene.backUntil = from, GetTime() + Scene.SETTLE
    zoomBy(CameraZoomOut, from - Scene.ZOOM)
end

-- The player zoomed manually (wheel and zoom keys call these), so leave the camera there.
local CAMERA_CALLS = { "CameraZoomIn", "CameraZoomOut", "MoveViewInStart", "MoveViewOutStart", "SetView", "ResetView" }
local function hookCamera()
    for _, name in ipairs(CAMERA_CALLS) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, function()
                if not ours then Scene.zoomFrom, Scene.zoomBack = nil, nil end
            end)
        end
    end
end

-- Restore the player's settings immediately.
function Scene.GiveBack()
    local from = kept()
    if not from then return end
    quiet()
    for name, v in pairs(from) do setCVar(name, v) end
    DUI.DB.Root().npcCamera = nil
    Scene.cameraAt = 0
end

-- Save the player's settings once, before the first change.
function Scene.KeepCamera()
    local root = DUI.DB and DUI.DB.Root and DUI.DB.Root()
    if not root then return false end
    if not root.npcCamera then
        local keep = {}
        for name in pairs(Scene.CAMERA) do keep[name] = getCVar(name) end
        root.npcCamera = keep
    end
    return true
end

function Scene.CameraIn()
    if not on("zoom") or InCombatLockdown() or (type(IsMounted) == "function" and IsMounted()) then return end
    if not Scene.KeepCamera() then return end
    quiet()
    for name, v in pairs(Scene.CAMERA) do
        if not Scene.EASED[name] then setCVar(name, v) end
    end
    Motion.Tween("npc:camera", Scene.cameraAt or 0, 1, Motion.SLOW, paintCamera)
    -- Zoom in with the game's easing, never further out than the player had it.
    if Scene.zoomFrom then return end
    local mine = zoomNow()
    if Scene.zoomBack and GetTime() < Scene.backUntil then mine = Scene.zoomBack end   -- still returning
    Scene.zoomBack = nil
    if mine and mine - Scene.ZOOM >= Scene.MOVED then
        Scene.zoomFrom = mine
        zoomBy(CameraZoomIn, mine - Scene.ZOOM)
    end
end

-- Back to the player's camera, eased unless snap. Skip the zoom if they zoomed
-- in the meantime.
function Scene.CameraOut(snap)
    zoomHome()
    if not kept() then return end
    quiet()
    Motion.Tween("npc:camera", Scene.cameraAt or 1, 0, snap and 0 or Motion.NORMAL, paintCamera, Scene.GiveBack)
end

-- UI fade. UIParent's alpha can change in combat since nothing protected moves.

local ownIgnore = {}   -- frame -> its original ignore-parent-alpha while the UI is faded

local function paintUI(p)
    Scene.uiAt = p
    UIParent:SetAlpha(1 - p)
    -- Minimap blips ignore parent alpha, so hide the map once the UI is gone.
    DUI.Fade.MapAway("npc", p >= 1)
end

local function uiAway()
    for _, name in ipairs(Scene.KEEP) do
        local f = _G[name]
        if type(f) == "table" and f.SetIgnoreParentAlpha and ownIgnore[f] == nil then
            ownIgnore[f] = f:IsIgnoringParentAlpha() == true
            f:SetIgnoreParentAlpha(true)
        end
    end
    Motion.Tween("npc:ui", Scene.uiAt or 0, 1, Motion.SLOW, paintUI)
end

-- snap: immediately (combat started).
local function uiBack(snap)
    if not Scene.uiAt then return end
    Motion.Tween("npc:ui", Scene.uiAt, 0, snap and 0 or Motion.NORMAL, paintUI, function()
        if (Scene.uiAt or 0) > 0 then return end
        Scene.uiAt = nil
        UIParent:SetAlpha(1)
        for f, own in pairs(ownIgnore) do
            f:SetIgnoreParentAlpha(own)
            ownIgnore[f] = nil
        end
    end)
end

-- Open and close

function Scene.Entered()
    if on("fadeUI") then uiAway() end
    Scene.CameraIn()
end

-- snap: immediately (combat started), otherwise normal speed.
function Scene.Left(snap)
    if not Scene.frame then return end
    uiBack(snap)
    Scene.Clear()
    Scene.CameraOut(snap)
end

-- Build

-- Right side of the screen, vertically centered, sized from UIParent. Win.ShowPage
-- reads this spec for the size to open or glide to.
function Scene.Place()
    local f = Scene.frame
    if not f then return end
    local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local W, H = UIParent:GetWidth() or 1024, UIParent:GetHeight() or 768
    f.spec.w = math.floor(math.min(Scene.MAX_W, math.max(Scene.MIN_W, W * Scene.WIDE)) / k)
    f.spec.h = math.floor(H * Scene.TALL / k)
    f:ClearAllPoints()
    f:SetPoint("RIGHT", UIParent, "RIGHT", -W * Scene.RIGHT / k, 0)
end

-- Fit the height to the page content, clamped between Scene.SHORT and Scene.TALL,
-- and glide there when already open.
function Scene.Fit(page)
    local f = Scene.frame
    if not (f and page and page.stack) then return end
    local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local most = (UIParent:GetHeight() or 768) * Scene.TALL / k
    local want = Win.HEADER + Scene.TOP + (page.stack.height or 0) + ns.Window.FOOT + Scene.SIDE
    local h = math.floor(math.max(Scene.SHORT, math.min(most, want)))
    f.spec.h = h
    if Win.IsOpen(f) then Win.Feel.Size(f, f.spec.w, h) else f:SetSize(f.spec.w, h) end
end

function Scene.Build(talk)
    if Scene.frame then return Scene.frame end
    -- Above action bars and unit frames, which fade out but come back on mouseover.
    local f = Win.New({ name = Scene.NAME, back = "NPC", w = Scene.W, h = Scene.H, portrait = true, strata = "HIGH" })
    Scene.frame = f
    f.onClose = ns.Window.Goodbye
    f:SetIgnoreParentAlpha(true)   -- stays visible while the UI fades
    f.room = false   -- other windows don't move aside for it
    Win.AddPage(f, "talk", talk)   -- roomier Build, shared Fill
    Win.Build(f, "talk")
    Win.Keys(f, ns.Window.OnKey)
    -- Clicking anywhere finishes typing the text.
    f:SetScript("OnMouseDown", function() if Scene.Typing() then Scene.Finish() end end)
    f.typer = CreateFrame("Frame", nil, f)
    f.typer:Hide()
    f.typer:SetScript("OnUpdate", tick)
    -- Restore the camera on combat (immediately), logout, /reload, and after a game
    -- that closed mid-talk.
    f.typer:RegisterEvent("PLAYER_REGEN_DISABLED")
    f.typer:RegisterEvent("PLAYER_LOGOUT")
    hookCamera()
    f.typer:SetScript("OnEvent", function(_, event)
        zoomHome()
        if event == "PLAYER_LOGOUT" then
            Scene.GiveBack()
            return
        end
        uiBack(true)   -- combat: bring the UI back immediately
        if kept() then
            Motion.Tween("npc:camera", Scene.cameraAt or 1, 0, 0, paintCamera, Scene.GiveBack)
        end
    end)
    Scene.GiveBack()
    return f
end
