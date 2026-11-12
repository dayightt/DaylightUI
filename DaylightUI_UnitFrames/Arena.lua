-- Enemy flag carriers. In a battleground the game exposes each enemy carrying
-- a flag or orb as an arena unit (arena1, arena2...) and shows them in its own
-- CompactArenaFrame. These replace it: built like the focus frame, angled like
-- the target, one shared setup (settings `arena`, `arenaText`), stacked in one
-- holder that carries the mover. Each is a secure unit button with a fixed
-- unit and the game's unit watch, so it shows while the carrier exists and
-- clicks target them even in combat. Right-click sets focus, like the game's.

local _, ns = ...
local DUI = DaylightUI
local UF = ns.UF

local Arena = {}
ns.Arena = Arena

Arena.MAX = 3   -- carriers at once, a flag or orb per team with room to spare
Arena.KEY = "unitframes.arena"
Arena.buttons = {}
Arena.shown = 0   -- how many are shown; the range ticker skips them all at 0

-- Built like the focus frame, angled the target's way since it's an enemy.
function Arena.Spec(i)
    return { unit = "arena" .. i, label = "PvP Frame", power = true, slant = "left", tab = true, marker = true,
             portrait = true, range = true, ribbon = true }
end

Arena.SAMPLES = {
    { name = "Dalinar", class = "WARRIOR", reaction = 2, health = 58, healthValue = 2600, power = 30, powerToken = "RAGE",
      portraitClass = "WARRIOR", level = 20, pvp = true, marker = 8 },
    { name = "Vivenna", class = "DRUID", reaction = 2, health = 86, healthValue = 1900, power = 64, powerToken = "MANA",
      portraitClass = "DRUID", level = 20, pvp = true },
}

local function db() return ns.module and ns.module.db end

function Arena.Count()
    local n = 0
    for _, b in ipairs(Arena.buttons) do
        if b:IsShown() then n = n + 1 end
    end
    Arena.shown = n
end

function Arena.IsArenaUnit(unit)
    return type(unit) == "string" and not (issecretvalue and issecretvalue(unit)) and unit:find("^arena%d") ~= nil
end

-- Built once, out of combat, since these are secure buttons.
function Arena.Create()
    local holder = CreateFrame("Frame", "DaylightUIArenaHolder", UIParent)
    holder:SetSize(1, 1)
    Arena.holder = holder
    for i = 1, Arena.MAX do
        local b = UF.Create(Arena.Spec(i))
        b:SetParent(holder)
        -- The game's arena frames set focus on right-click (CompactArenaFrame.lua).
        b:SetAttribute("*type2", "focus")
        b.moverKey = Arena.KEY
        UF.Wire(b)
        b:HookScript("OnShow", Arena.Count)
        b:HookScript("OnHide", Arena.Count)
        DUI.APIReport.Made("unit", b, b.unitToken, false)
        Arena.buttons[i] = b
    end
    DUI.Movers.Register(holder, Arena.KEY, "PvP Frames", { "TOPRIGHT", nil, "RIGHT", -240, 160 })
    DUI.Fade.Register{ key = "UnitFrames.arena", scope = "UnitFrames", path = "arena.fade",
        page = "UnitFrames.arena", frames = function() return Arena.buttons end, paint = UF.PaintFade, whole = true,
        float = false }
    -- A carrier appeared, went out of sight or left. Redraw their frame.
    DUI.RegisterEvent("ARENA_OPPONENT_UPDATE", function(_, unit)
        local d = db()
        if d and d.arena.enabled then ns.Blizzard.Hide("CompactArenaFrame") end
        for _, b in ipairs(Arena.buttons) do
            if b.unitToken == unit and not b.test then UF.UpdateAll(b, true) end
        end
    end)
    return holder
end

-- Sizes, places and toggles every frame from the settings. Protected, so
-- out of combat only (ns.Refresh calls it there).
function Arena.Layout(d)
    if not Arena.holder then return end
    local cfg, text = d.arena, d.arenaText
    local step = cfg.height + (tonumber(cfg.spacing) or 0)
    for i, b in ipairs(Arena.buttons) do
        b.iconStyle, b.classIcons = d.portraits.icons, d.portraits.classIcons
        b.rangeFade, b.rangeAlpha = d.range.enabled, UF.RangeAlpha(d.range, false)
        UF.Layout(b, cfg, text)
        b:ClearAllPoints()
        b:SetPoint("TOPRIGHT", Arena.holder, "TOPRIGHT", 0, -(i - 1) * step)
        if not b.test then ns.SetEnabled(b, cfg.enabled) end
        UF.UpdateAll(b, true)
    end
    Arena.holder:SetSize(cfg.width, Arena.MAX * step - (tonumber(cfg.spacing) or 0))
end

-- Test mode: two sample carriers. Test.lua starts and stops it.
function Arena.ShowSamples()
    local d = db()
    if not (d and d.arena.enabled and DUI.TestPartShown("arena")) then return end
    for i, b in ipairs(Arena.buttons) do
        local s = Arena.SAMPLES[i]
        if s then
            b.test = s
            ns.Release(b)
            b:Show()
            b:SetAlpha(1)
            UF.ShowSample(b)
        end
    end
end

function Arena.HideSamples()
    for _, b in ipairs(Arena.buttons) do
        if b.test then
            b.test = nil
            if not UnitExists(b.unitToken) then b:SetAlpha(0) end
            UF.UpdateAll(b, true)
        end
    end
end

-- Go back to watching the real units once out of combat, after test mode.
function Arena.Rewatch()
    local d = db()
    if not d then return end
    for _, b in ipairs(Arena.buttons) do
        b:SetAlpha(1)
        ns.SetEnabled(b, d.arena.enabled)
        UF.UpdateAll(b, true)
    end
end

DUI.RegisterTestPart("arena", "PvP frames", 35, function()
    local d = db()
    return d ~= nil and d.arena.enabled == true
end)
