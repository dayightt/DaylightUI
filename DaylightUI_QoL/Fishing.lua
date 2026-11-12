-- Right-click to fish: with a fishing pole equipped, a quick right-click on the
-- world casts Fishing. Holding the button still turns the camera, and clicks on
-- anything interactive (NPC, chest, the bobber) go to the game as usual.
--
-- Only a hardware press can cast, so on GLOBAL_MOUSE_DOWN an override binding
-- points BUTTON2 at a secure spell button for that press's release. It lasts at
-- most Fish.TAP seconds; a longer hold is a camera turn and the binding is gone
-- before release. Nothing is bound between presses or in combat.
--
-- While the line is in, clicks never cast, so a missed bobber doesn't reel in.
--
-- Bait: with none on the pole and some in the bags, the click applies the best
-- one and the next click casts. Bait is found by the number after "Fishing" in
-- its tooltip, so new baits work too. IsUsableItem says which ones your skill allows.

local _, ns = ...
local DUI = DaylightUI

local Fish = {}
ns.Fishing = Fish
ns.features[#ns.features + 1] = Fish

Fish.NAME = "DaylightUIFishCast"
Fish.KEY = "BUTTON2"
Fish.TAP = 0.2              -- seconds: held longer, the press is a camera turn
Fish.SKILL_LINE = 356       -- Fishing
Fish.SLOT = INVSLOT_MAINHAND or 16
Fish.BAIT_HOLD = 600        -- seconds a bait just put on counts, if the game doesn't show it on the pole
Fish.NOT_BAIT = { [2] = true, [4] = true, [9] = true, [12] = true }   -- weapons, armor, recipes, quest items

local mod, button
local armed = false
local press = 0
local baitedUntil = 0
local baitPower = {}        -- item id -> what its tooltip says it adds (0: not bait)

local function wanted() return mod and mod.db and mod.db.fishClick == true end

local function call(name, ...)
    local fn = _G[name]
    if type(fn) == "function" then return fn(...) end
end

-- The main hand holds a fishing pole.
function Fish.HasPole()
    local id = call("GetInventoryItemID", "player", Fish.SLOT)
    if type(id) ~= "number" or not (C_Item and C_Item.GetItemInfoInstant) then return false end
    local _, _, _, _, _, class, sub = C_Item.GetItemInfoInstant(id)
    local weapon = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
    local pole = Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole or 20
    return class == weapon and sub == pole
end

-- A profession spell that opens its trade skill window. Unknown = yes: a
-- click must never open a window by mistake.
local function opensWindow(id)
    local show = C_TradeSkillUI and C_TradeSkillUI.CanTradeSkillShowCraftingUI
    if type(show) ~= "function" then return true end
    return show(id) == true
end

-- The castable Fishing spell, or nil. The first book slot (Bait and Tackle)
-- opens the trade skill window, so the cast is the slot that is neither that
-- nor passive. Never guessed from a spell id.
function Fish.Spell()
    local book = C_SpellBook
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return nil end
    if not (book and type(book.GetSpellBookItemInfo) == "function") then return nil end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local list = { GetProfessions() }
    for i = 1, 7 do
        if list[i] then
            local _, _, _, _, count, offset, skillLine = GetProfessionInfo(list[i])
            if skillLine == Fish.SKILL_LINE and type(count) == "number" and type(offset) == "number" then
                for k = 1, count do
                    local item = book.GetSpellBookItemInfo(offset + k, bank)
                    local id = type(item) == "table" and not item.isPassive and item.spellID
                    if type(id) == "number" and not opensWindow(id) then return id end
                end
            end
        end
    end
end

-- The pole has bait on.
function Fish.Baited()
    if GetTime() < baitedUntil then return true end
    local paper = C_PaperDollInfo
    if not (paper and type(paper.GetTemporaryEnchantmentInfo) == "function") then return false end
    local info = paper.GetTemporaryEnchantmentInfo(Fish.SLOT)   -- none: it returns nothing at all
    return type(info) == "table"
end

-- What an item in the bags adds to Fishing (0: not bait), from its tooltip.
local function power(bag, slot, id, word)
    if baitPower[id] then return baitPower[id] end
    local _, _, _, _, _, class = C_Item.GetItemInfoInstant(id)
    if Fish.NOT_BAIT[class] or not C_Item.GetItemSpell(id) then
        baitPower[id] = 0
        return 0
    end
    local data = C_TooltipInfo.GetBagItem(bag, slot)
    if type(data) ~= "table" or type(data.lines) ~= "table" then return 0 end   -- not loaded yet: asked again
    local found = 0
    for _, line in ipairs(data.lines) do
        local text = type(line.leftText) == "string" and line.leftText:lower()
        local at = text and text:find(word, 1, true)
        if at then found = math.max(found, tonumber(text:match("(%d+)", at)) or 1) end
    end
    baitPower[id] = found
    return found
end

-- The best bait in the bags you can use: bag, slot (nil: none).
function Fish.BestBait(spell)
    if not (C_Container and C_TooltipInfo and C_Item.GetItemSpell and C_Item.IsUsableItem) then return nil end
    local word = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell)
    if type(word) ~= "string" then return nil end
    word = word:lower()
    local bestBag, bestSlot, best = nil, nil, 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = type(info) == "table" and info.itemID
            if type(id) == "number" then
                local p = power(bag, slot, id, word)
                if p > best and C_Item.IsUsableItem(id) then bestBag, bestSlot, best = bag, slot, p end
            end
        end
    end
    return bestBag, bestSlot
end

-- The mouse points at the world, not at a window or a bar of anything's.
local function overWorld()
    local foci = call("GetMouseFoci")
    if type(foci) ~= "table" then return false end
    return foci[1] == nil or foci[1] == WorldFrame
end

-- The mouse points at something the click means: a unit, or a thing the game
-- shows a tooltip for. A tooltip fading away has been left behind (the bobber
-- just looted), so the next click casts at once.
local function pointingAtThing()
    if UnitExists("mouseover") then return true end
    if not (GameTooltip and GameTooltip:IsShown()) then return false end
    local a = GameTooltip:GetAlpha()
    return type(a) ~= "number" or (issecretvalue and issecretvalue(a)) or a > 0.9
end

-- Something this press means already, or a cast that can't start.
local function busy()
    if call("IsModifierKeyDown") or call("IsMouseButtonDown", "LeftButton") then return true end
    if call("SpellIsTargeting") or call("GetCursorInfo") then return true end
    if LootFrame and LootFrame:IsShown() then return true end
    local casting, channeling = UnitCastingInfo("player"), UnitChannelInfo("player")   -- no cast returns nothing at all
    if type(casting) ~= "nil" or type(channeling) ~= "nil" then return true end
    if call("IsMounted") or call("UnitOnTaxi", "player") or call("UnitInVehicle", "player") then return true end
    if call("IsSwimming") or call("UnitIsDeadOrGhost", "player") then return true end
    local speed = call("GetUnitSpeed", "player")
    return type(speed) ~= "number" or speed > 0
end

local function disarm(entering)
    if not armed then return end
    if InCombatLockdown() and not entering then
        DUI.AfterCombat(disarm, "qol:fish")
        return
    end
    armed = false
    ClearOverrideBindings(button)
end

local function make()
    local ok, b = pcall(CreateFrame, "Button", Fish.NAME, UIParent, "SecureActionButtonTemplate")
    if not ok or type(b) ~= "table" then return nil end
    -- The binding arrives mid-press, so only the release reaches the button.
    -- Set by hand: nil here means the player's ActionButtonUseKeyDown, and
    -- with that on the game's secure code acts on a down that never comes.
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("useOnKeyDown", false)
    b:Hide()
    b:SetScript("PostClick", function(self)
        if self.baiting then baitedUntil = GetTime() + Fish.BAIT_HOLD end
        disarm()
    end)
    return b
end

-- What this click does: the bait, or the cast.
local function aim(b, spell)
    local bag, slot
    if not Fish.Baited() then bag, slot = Fish.BestBait(spell) end
    b.baiting = bag ~= nil
    b:SetAttribute("type", bag and "item" or "spell")
    b:SetAttribute("spell", not bag and spell or nil)
    b:SetAttribute("item", bag and (bag .. " " .. slot) or nil)
    b:SetAttribute("target-slot", bag and Fish.SLOT or nil)
end

local function onMouseDown(_, which)
    if which ~= "RightButton" or armed or not wanted() then return end
    if InCombatLockdown() or DUI.Restricted() then return end
    if not overWorld() or pointingAtThing() or busy() or not Fish.HasPole() then return end
    local spell = Fish.Spell()
    if not spell then return end
    button = button or make()
    if not button then return end
    aim(button, spell)
    armed = true
    press = press + 1
    local this = press
    SetOverrideBindingClick(button, true, Fish.KEY, Fish.NAME, "LeftButton")
    C_Timer.After(Fish.TAP, function()
        if this == press then disarm() end
    end)
end

----------------------------------------------------------------------------
-- The scene: while fishing, calm water lies along the bottom of the screen with a
-- bobber on it, and bars and unit frames fade out. On a catch the bobber dips and
-- the water splashes. The game gives addons no bite event, so a catch is loot
-- right after the channel stops.
--
-- The water doubles as the cast bar, closing in on the bobber as the channel
-- runs out. The player's own cast bar hides meanwhile (DUI.Fire("CastElsewhere")).
--
-- One BACKGROUND-strata frame, no clicks, its OnUpdate only runs while shown. It
-- lingers LINGER seconds after the line comes in so recasting doesn't flicker.
--
-- Scene.THEMES dresses the same parts for other crafts: a forge for smithing,
-- a flask for alchemy, gears for engineering and a spool for tailoring. Crafts
-- show progress like "3 / 20" in the tide, since the cast bar is hidden.
----------------------------------------------------------------------------

local Scene = {
    HUSH = { "ActionBars.", "UnitFrames." },
    LINGER = 5,         -- s the water waits for the next cast
    CRAFT_LINGER = 2.5, -- s a craft's scene waits for the next craft
    BUBBLE_LIFE = 2.4,  -- s a bubble lives
    GEAR_RATIO = 2,     -- the small gear turns this much faster: 16 teeth to 8
    GEAR_APART = 63,    -- between the gears' middles
    GEAR_KICK = 5,      -- the speed on a finished item, times normal
    GEAR_SETTLE = 0.8,  -- s back to normal
    NEEDLE_SEW = 9,     -- the needle's speed
    NEEDLE_DIP = 8,     -- how far it dips
    NEEDLE_EDGE = 40,   -- how near the screen's edge it goes
    HIT_EVERY = 1.1,    -- s between the hammer's blows
    HIT_LIFT = 0.95,    -- how far it lifts (radians)
    HIT_AT = 0.78,      -- it lands this share of the way through a blow
    HIT_SPARKS = 3,
    HAMMER = 84,
    CRAFT_SECS = 1.3,   -- s a craft takes in the preview
    CRAFT_PREVIEW = 5,  -- crafts in the preview
    CATCH = 0.6,        -- s after the channel stops that loot still means a catch
    GLOW_IN = 1.6,      -- s for the water to rise in
    GLOW_OUT = 1.2,     -- s to fade away
    REST = 0.6,         -- the light's level while fishing
    SWELL = 1.5,        -- the light's level at a catch
    SWELL_UP = 0.25,    -- s up to it
    SWELL_SETTLE = 1.8, -- s back down
    LINE = 0.095,       -- the waterline, this share of the screen up
    BITS = 30,          -- soft pieces of the surface across the screen
    BIT_ALPHA = 0.20,
    TIDE_WIDE = 1.1,    -- the tide's width when full: past the screen's edges
    FOAM_ALPHA = 0.32,  -- the foam at its two ends
    GLINT = 0.35,       -- how much the surface's light comes and goes
    DROP_IN = 0.4,      -- s the cast bobber falls
    DROP_FROM = 70,     -- from this far above the water
    UNDER = 0.22,       -- s it takes to go under: fast, this is the catch
    UNDER_BY = 34,      -- and how far down
    RIPPLES = 4,
    RIPPLE_EVERY = 3.2, -- s between the calm ripples round the bobber
    RIPPLE_LIFE = 2.6,
    DROPS = 44,         -- drops in the pool
    BURST = 34,         -- at a catch
    PLOP = 6,           -- when the bobber lands
    WAVE_LIFE = 1.5,    -- s the catch's wave runs
    WAVE_SPEED = 420,   -- its speed outward
    WAVE_RISE = 16,     -- its height
    PREVIEW_CHANNEL = 8,-- the preview's tide runs out over this, a real line's over 30 s
    BLOOM = 0.9,        -- s of the catch's light
    BLOOM_ALPHA = 0.4,
    PREVIEW_CATCH = 5,  -- the preview's catch comes after this
}
Scene.Random = math.random      -- tests fix it
Fish.Scene = Scene
Scene.state = "idle"            -- idle | line (in the water) | waiting (came in, the next cast may follow)

local Motion = DUI.Motion
local MEDIA_GLOW = DUI.MEDIA .. "char-glow.png"
local MEDIA_BOBBER = DUI.MEDIA .. "fish-bobber.png"
local MEDIA_RIPPLE = DUI.MEDIA .. "fish-ripple.png"
local MEDIA_TIDE = DUI.MEDIA .. "fish-tide.png"

Scene.THEMES = {
    water = { key = "fishScene", linger = Scene.LINGER, object = MEDIA_BOBBER, size = 34, sit = 7, sway = true,
        waves = 1, flick = 1, gravity = 520, sparkAt = 0, drop = 1, lift = 1, spread = 1, calm = true,
        sound = "splash", catch = true,
        deep = 0.30, shine = 0.22, tideAlpha = 0.62,
        deepColor = { 0.10, 0.34, 0.46 }, shineColor = { 0.26, 0.56, 0.60 }, foam = { 0.80, 0.93, 1 },
        crest = { 0.52, 0.76, 0.78 }, tideTop = { 0.20, 0.46, 0.52 }, tideLow = { 0.06, 0.18, 0.26 } },
    forge = { key = "forgeScene", linger = Scene.CRAFT_LINGER, object = DUI.MEDIA .. "forge-anvil.png", size = 96, sit = 30,
        still = true, hammer = true, fills = true, waves = 0.5, flick = 3, gravity = 300, sparkAt = 51, drop = 0.6,
        lift = 1, spread = 1,
        deep = 0.30, shine = 0.22, tideAlpha = 0.66,
        deepColor = { 0.46, 0.18, 0.08 }, shineColor = { 0.70, 0.34, 0.12 }, foam = { 1, 0.74, 0.38 },
        crest = { 0.98, 0.62, 0.26 }, tideTop = { 0.66, 0.26, 0.08 }, tideLow = { 0.20, 0.07, 0.04 } },
    -- Bubbles fall upward: a gravity under 0, a life, the ring art.
    brew = { key = "brewScene", linger = Scene.CRAFT_LINGER, object = DUI.MEDIA .. "brew-flask.png", size = 84, sit = 34,
        still = true, fills = true, waves = 1, flick = 0.8, gravity = -36, sparkAt = 70, drop = 1.3, lift = 0.16,
        spread = 0.2, dropArt = MEDIA_RIPPLE, life = Scene.BUBBLE_LIFE, bubbles = 4,
        deep = 0.30, shine = 0.22, tideAlpha = 0.66,
        deepColor = { 0.16, 0.40, 0.16 }, shineColor = { 0.36, 0.62, 0.24 }, foam = { 0.76, 0.96, 0.62 },
        crest = { 0.60, 0.90, 0.44 }, tideTop = { 0.28, 0.58, 0.20 }, tideLow = { 0.07, 0.22, 0.09 } },
    workshop = { key = "workshopScene", linger = Scene.CRAFT_LINGER, object = DUI.MEDIA .. "gear-big.png", size = 96, sit = 34,
        still = true, fills = true, waves = 0.5, flick = 0.6, gravity = 420, sparkAt = 34, sparkX = 42, drop = 0.6,
        lift = 0.8, spread = 0.8, spin = 0.7, second = DUI.MEDIA .. "gear-small.png", secondSize = 48,
        deep = 0.30, shine = 0.22, tideAlpha = 0.66,
        deepColor = { 0.30, 0.24, 0.12 }, shineColor = { 0.56, 0.44, 0.20 }, foam = { 0.70, 0.86, 1 },
        crest = { 0.86, 0.72, 0.40 }, tideTop = { 0.50, 0.40, 0.18 }, tideLow = { 0.14, 0.12, 0.08 } },
}
-- Fluff drifts: thrown a little way, a soft fall, a life. The bits of the
-- surface are stitches here: no waves, short and clear.
Scene.THEMES.sewing = { key = "sewingScene", linger = Scene.CRAFT_LINGER, object = DUI.MEDIA .. "sew-spool.png", size = 88, sit = 38,
    still = true, fills = true, waves = 0, flick = 0.6, gravity = 60, sparkAt = 60, drop = 1, lift = 0.35, spread = 0.9,
    life = 1.8, stitch = true, bitAlpha = 0.75, needle = true, second = DUI.MEDIA .. "sew-needle.png", secondSize = 44,
    deep = 0.30, shine = 0.22, tideAlpha = 0.66,
    deepColor = { 0.30, 0.16, 0.30 }, shineColor = { 0.52, 0.30, 0.50 }, foam = { 0.96, 0.84, 0.92 },
    crest = { 0.94, 0.80, 0.90 }, tideTop = { 0.44, 0.24, 0.44 }, tideLow = { 0.14, 0.08, 0.16 } }
-- skill line -> theme: Blacksmithing, Mining's smelting, Alchemy, Engineering, Tailoring
Scene.LINES = { [164] = "forge", [186] = "forge", [171] = "brew", [202] = "workshop", [197] = "sewing" }
local theme = Scene.THEMES.water

local f, watching
local run = 0                   -- each cast's id: a newer one stops the older one's timers
local spell                     -- the cast's spell id (nil in a preview)
local clock, ripAt = 0, 0
local stoppedAt                 -- GetTime when the line came in, until the catch is told
local waveAt, bloomAt           -- clock when the catch's wave and light started, or nil
local glow = { now = 0, from = 0, to = 0, t = 0, dur = 0 }
local glowNext                  -- { to, dur } once this ease lands
local bob = { phase = "none", t = 0 }   -- none | in | float | under
local tideFrom, tideTo          -- the channel's start and end on GetTime's clock
local tide = 1                  -- the share of the tide still in
local made, total = 0, 0        -- the batch: items done, items in all
local blow, struck = 0, false   -- s into the hammer's blow, it has landed this blow
local bubbleDebt = 0            -- bubbles owed to the tide
local spun, kick = 0, 0         -- the gears' turn so far, what's left of a finished item's speed

local function secret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end
local function ease(p) return 0.5 - 0.5 * math.cos(math.pi * p) end
local function sceneOn(t) return mod and mod.db and mod.db[(t or theme).key] == true end

local function glowTo(to, dur, after)
    if not Motion.On() then
        to = after and after[1] or to
        after = nil
        glow.now, dur = to, 0
    end
    glow.from, glow.to, glow.t, glow.dur = glow.now, to, 0, dur
    glowNext = after
end

local function light(layer, sub, file, blend)
    local t = f:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(file or MEDIA_GLOW)
    t:SetBlendMode(blend or "ADD")
    return t
end

local function paint(t, c) t:SetVertexColor(c[1], c[2], c[3]) end

local step

local function build()
    if f then return end
    f = CreateFrame("Frame", "DaylightUIFishScene", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("BACKGROUND")
    f:SetFrameLevel(0)
    f:EnableMouse(false)
    f:Hide()
    f.deep = light("BACKGROUND", 0)
    f.shine = light("BACKGROUND", 1)
    f.flare = light("BACKGROUND", 2)
    f.flare:SetAlpha(0)
    f.tide = light("BACKGROUND", 3, MEDIA_TIDE, "BLEND")
    f.ends = {}
    for side = 1, 2 do
        local t = light("BORDER", 0)
        t:SetSize(70, 22)
        f.ends[side] = t
    end
    f.bits = {}
    for i = 1, Scene.BITS do
        f.bits[i] = light("BORDER", 0)
    end
    f.ripples = {}
    for i = 1, Scene.RIPPLES do
        local t = light("BORDER", 1, MEDIA_RIPPLE)
        t:Hide()
        f.ripples[i] = { tex = t }
    end
    f.bobber = light("ARTWORK", 0, MEDIA_BOBBER, "BLEND")
    f.bobber:Hide()
    f.hammer = light("ARTWORK", 2, DUI.MEDIA .. "forge-hammer.png", "BLEND")
    f.hammer:SetSize(Scene.HAMMER, Scene.HAMMER)
    f.hammer:Hide()
    f.count = DUI.Style.Text(f, DUI.Style.SIZE.head, "CENTER")
    f.count:Hide()
    f.drops = {}
    for i = 1, Scene.DROPS do
        local t = light("ARTWORK", 1)
        t:Hide()
        f.drops[i] = { tex = t }
    end
    f:SetScript("OnUpdate", function(_, dt) step(dt) end)
end

-- The parts dressed for the work.
local function dress()
    paint(f.deep, theme.deepColor)
    paint(f.shine, theme.shineColor)
    paint(f.flare, theme.foam)
    f.tide:SetVertexColor(1, 1, 1)
    f.tide:SetGradient("VERTICAL", CreateColor(unpack(theme.tideLow)), CreateColor(unpack(theme.tideTop)))
    for _, t in ipairs(f.ends) do paint(t, theme.crest) end
    for _, t in ipairs(f.bits) do paint(t, theme.crest) end
    for _, r in ipairs(f.ripples) do paint(r.tex, theme.foam) end
    for _, d in ipairs(f.drops) do
        d.tex:SetTexture(theme.dropArt or MEDIA_GLOW)
        paint(d.tex, theme.foam)
    end
    f.bobber:SetTexture(theme.object)
    f.bobber:SetSize(theme.size, theme.size)
    f.hammer:SetTexture(theme.second or DUI.MEDIA .. "forge-hammer.png")
    f.hammer:SetSize(theme.secondSize or Scene.HAMMER, theme.secondSize or Scene.HAMMER)
    f.hammer:SetRotation(0)
    f.hammer:SetShown(theme.hammer == true or theme.second ~= nil)
    f.count:SetShown(false)
    DUI.Style.InkText(f.count, "TEXT")
end

local function layout()
    local W = UIParent:GetWidth() or 1024
    local H = UIParent:GetHeight() or 768
    f.w, f.h, f.line, f.mid = W, H, H * Scene.LINE, W / 2
    f.deep:ClearAllPoints()
    f.deep:SetPoint("CENTER", f, "BOTTOM", 0, -H * 0.1)
    f.deep:SetSize(W * 1.6, H * 0.62)
    f.shine:ClearAllPoints()
    f.shine:SetPoint("CENTER", f, "BOTTOM", 0, -H * 0.06)
    f.shine:SetSize(W * 0.9, H * 0.36)
    f.flare:ClearAllPoints()
    f.flare:SetPoint("CENTER", f, "BOTTOMLEFT", f.mid, f.line)
    local wide = W / Scene.BITS * 2.6
    for _, t in ipairs(f.bits) do
        t:SetSize(theme.stitch and wide * 0.22 or wide, theme.stitch and 4 or 9)
    end
    f.tide:ClearAllPoints()
    f.tide:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
    f.tide:SetHeight(f.line + 3)
    f.count:ClearAllPoints()
    f.count:SetPoint("CENTER", f, "BOTTOMLEFT", f.mid, f.line - 40)
end

-- The water's height at x: two slow swells, and the catch's wave running out.
local function height(x)
    local y = 0
    if Motion.On() then
        local k = x / f.w
        y = (math.sin(k * 9 + clock * 1.1) * 3 + math.sin(k * 23 - clock * 1.7) * 1.5) * theme.waves
    end
    if waveAt then
        local t = clock - waveAt
        local d = (math.abs(x - f.mid) - Scene.WAVE_SPEED * t) / 70
        y = y + Scene.WAVE_RISE * math.exp(-d * d) * (1 - t / Scene.WAVE_LIFE) ^ 2
    end
    return y
end

local function ripple(size, peak, life)
    for _, r in ipairs(f.ripples) do
        if not r.tex:IsShown() then
            r.age, r.size, r.peak, r.life = 0, size, peak, life
            r.tex:ClearAllPoints()
            r.tex:SetPoint("CENTER", f, "BOTTOMLEFT", f.mid, f.line)
            r.tex:SetSize(1, 1)
            r.tex:SetAlpha(0)
            r.tex:Show()
            return
        end
    end
end

local function stepRipples(dt, fade)
    for _, r in ipairs(f.ripples) do
        if r.tex:IsShown() then
            r.age = r.age + dt
            local p = r.age / r.life
            if p >= 1 then
                r.tex:Hide()
            else
                local out = 1 - (1 - p) ^ 2
                r.tex:SetSize(r.size * out, r.size * out * 0.22)
                r.tex:SetAlpha(r.peak * (1 - p) ^ 1.5 * math.min(1, p / 0.12) * fade)
            end
        end
    end
end

-- A drop thrown up from the bobber; high = a catch's, else a landing's. x, y:
-- from there instead (a bubble in the tide).
local function throw(high, x, y)
    local R = Scene.Random
    for _, d in ipairs(f.drops) do
        if not d.tex:IsShown() then
            local up = high and 180 + R() * 260 or 70 + R() * 70
            d.x, d.y = x or f.mid + (theme.sparkX or 0) + (R() - 0.5) * 30, y or f.line + theme.sparkAt
            d.vx, d.vy = (R() - 0.5) * (high and 340 or 120) * theme.spread, up * theme.lift
            d.age, d.peak = 0, 0.6 + R() * 0.4
            local size = (high and 4 + R() * 7 or 3 + R() * 3) * theme.drop
            d.tex:SetSize(size, size)
            d.tex:Show()
            return true
        end
    end
    return false
end

local function stepDrops(dt)
    for _, d in ipairs(f.drops) do
        if d.tex:IsShown() then
            d.age = d.age + dt
            d.vy = d.vy - theme.gravity * dt
            d.x, d.y = d.x + d.vx * dt, d.y + d.vy * dt
            local life = theme.life
            if (life and d.age >= life) or (not life and d.y < f.line - 6) then
                d.tex:Hide()
            else
                d.tex:ClearAllPoints()
                d.tex:SetPoint("CENTER", f, "BOTTOMLEFT", d.x, d.y)
                local out = life and math.min(1, (life - d.age) / 0.6) or 1
                d.tex:SetAlpha(d.peak * math.min(1, d.age / (life and 0.3 or 0.05)) * out)
            end
        end
    end
end

-- Bubbles rising through the tide while the work runs.
local function stepBubbles(dt)
    if not theme.bubbles or Scene.state ~= "line" then return end
    bubbleDebt = bubbleDebt + theme.bubbles * dt
    local R = Scene.Random
    local reach = f.w * Scene.TIDE_WIDE * tide * 0.5
    while bubbleDebt >= 1 do
        bubbleDebt = bubbleDebt - 1
        throw(false, f.mid + (R() * 2 - 1) * reach * 0.9, R() * f.line * 0.7)
    end
end

local function stepSurface(fade)
    local moving = Motion.On()
    local reach = f.w * Scene.TIDE_WIDE * tide * 0.5
    for i, t in ipairs(f.bits) do
        local x = f.w * (i - 0.5) / Scene.BITS
        t:ClearAllPoints()
        t:SetPoint("CENTER", f, "BOTTOMLEFT", x, f.line + height(x))
        -- Glints that come and go, never a drawn line; none past the tide.
        local glint = moving and 1 - Scene.GLINT * (0.5 + 0.5 * math.sin(i * 2.4 + clock * 1.3)) or 1
        local inside = math.max(0, math.min(1, (reach - math.abs(x - f.mid)) / 60))
        t:SetAlpha((theme.bitAlpha or Scene.BIT_ALPHA) * fade * glint * inside)
    end
end

local function stepBobber(dt, fade)
    if bob.phase == "none" then return end
    local t = f.bobber
    bob.t = bob.t + dt
    local y, a = 0, 1
    if bob.phase == "in" then
        local p = math.min(1, bob.t / Scene.DROP_IN)
        y, a = Scene.DROP_FROM * (1 - p * p), p
        if p >= 1 then
            bob.phase, bob.t = "float", 0
            ripple(180, 0.5, Scene.RIPPLE_LIFE)
            for _ = 1, Scene.PLOP do throw() end
        end
    elseif bob.phase == "under" then
        local p = math.min(1, bob.t / Scene.UNDER)
        y, a = -Scene.UNDER_BY * p, 1 - p
        if p >= 1 then
            bob.phase = "none"
            t:Hide()
            return
        end
    end
    local moving = Motion.On()
    local sway = moving and math.sin(clock * 2.2) * 2 or 0
    t:ClearAllPoints()
    local water = theme.sway and height(f.mid) + sway or 0
    t:SetPoint("CENTER", f, "BOTTOMLEFT", f.mid, f.line + water + y + theme.sit)
    t:SetRotation(moving and theme.sway and math.sin(clock * 1.4) * 0.14 or 0)
    t:SetAlpha(a * fade)
end

local function stepBloom()
    if not bloomAt then return end
    local t = clock - bloomAt
    if t >= Scene.BLOOM then
        bloomAt = nil
        f.flare:SetAlpha(0)
        return
    end
    local up = Motion.FAST
    local a = t < up and t / up or (1 - (t - up) / (Scene.BLOOM - up)) ^ 2
    local p = t / Scene.BLOOM
    f.flare:SetSize(f.w * (0.3 + 0.3 * p), f.h * (0.22 + 0.34 * p))
    f.flare:SetAlpha(Scene.BLOOM_ALPHA * a)
end

-- The hammer turns round the end of its handle, right of the anvil: up
-- slowly, down fast, sparks where it lands.
local function stepHammer(dt, fade)
    if not theme.hammer then return end
    local a = 0
    if Motion.On() then
        blow = blow + dt
        if blow >= Scene.HIT_EVERY then blow, struck = blow - Scene.HIT_EVERY, false end
        local p, up = blow / Scene.HIT_EVERY, Scene.HIT_AT * 0.8
        if p < up then
            a = Scene.HIT_LIFT * ease(p / up)
        elseif p < Scene.HIT_AT then
            a = Scene.HIT_LIFT * (1 - ((p - up) / (Scene.HIT_AT - up)) ^ 2)
        elseif not struck then
            struck = true
            if Scene.state == "line" then
                for _ = 1, Scene.HIT_SPARKS do throw() end
            end
        end
    end
    local reach = Scene.HAMMER * 0.48
    local t = f.hammer
    t:ClearAllPoints()
    t:SetPoint("CENTER", f, "BOTTOMLEFT", f.mid + Scene.HAMMER * 0.76 - reach * math.cos(a),
        f.line + theme.sparkAt + Scene.HAMMER * 0.28 + reach * math.sin(a))
    t:SetRotation(-a)
    t:SetAlpha(fade)
end

-- The gears turn all the time, faster for a moment on a finished item; the
-- small one the other way, twice as fast, so the teeth keep meeting.
local function stepGears(dt, fade)
    if not theme.spin then return end
    local small = f.hammer
    small:ClearAllPoints()
    small:SetPoint("CENTER", f, "BOTTOMLEFT", f.mid + Scene.GEAR_APART, f.line + theme.sit)
    small:SetAlpha(fade)
    if Motion.On() then
        kick = math.max(0, kick - dt / Scene.GEAR_SETTLE)
        spun = spun + dt * theme.spin * (1 + (Scene.GEAR_KICK - 1) * kick * kick)
    end
    f.bobber:SetRotation(spun)
    small:SetRotation(-spun * Scene.GEAR_RATIO)
end

-- The needle works at the end of the seam, dipping into the cloth.
local function stepNeedle(fade)
    if not theme.needle then return end
    local x = f.mid + f.w * Scene.TIDE_WIDE * tide * 0.46
    local dip = Motion.On() and math.sin(clock * Scene.NEEDLE_SEW) * Scene.NEEDLE_DIP or 0
    local t = f.hammer
    t:ClearAllPoints()
    t:SetPoint("CENTER", f, "BOTTOMLEFT", math.min(x, f.w - Scene.NEEDLE_EDGE), f.line + theme.secondSize * 0.4 + dip)
    t:SetAlpha(fade)
end

-- The tide is the cast bar. Water closes in on the bobber from both sides as the
-- channel runs out. The forge's tide instead fills out from the anvil over a batch.
local function stepTide(dt)
    if theme.fills and tideTo then
        local span = tideTo - tideFrom
        tide = span > 0 and math.max(0, math.min(1, (GetTime() - tideFrom) / span)) or 1
    elseif Scene.state == "line" and tideTo then
        local left = math.max(0, tideTo - GetTime())
        tide = tideTo > tideFrom and left / (tideTo - tideFrom) or 0
    elseif not Motion.On() then
        tide = 1
    elseif tide < 1 then
        tide = math.min(1, tide + dt / Motion.SLOW)
    end
    local fade = math.min(1, glow.now / Scene.REST)
    local wide = f.w * Scene.TIDE_WIDE * tide
    f.tide:SetWidth(math.max(1, wide))
    f.tide:SetAlpha(theme.tideAlpha * fade)
    local foam = tide < 1 and Scene.FOAM_ALPHA * fade * (Motion.On() and 0.8 + 0.2 * math.sin(clock * 2.3) or 1) or 0
    for side, t in ipairs(f.ends) do
        local x = f.mid + (side == 1 and -1 or 1) * wide * 0.46
        t:ClearAllPoints()
        t:SetPoint("CENTER", f, "BOTTOMLEFT", x, f.line + height(x) - 4)
        t:SetAlpha(foam)
    end
end

local function hideAll()
    if not f then return end
    waveAt, bloomAt, stoppedAt = nil, nil, nil
    f.flare:SetAlpha(0)
    for _, d in ipairs(f.drops) do d.tex:Hide() end
    for _, r in ipairs(f.ripples) do r.tex:Hide() end
    bob.phase = "none"
    f.bobber:Hide()
    tideTo, tide = nil, 1
    glow.now, glow.from, glow.to, glowNext = 0, 0, 0, nil
    f:Hide()
end

step = function(dt)
    clock = clock + dt
    if glow.now ~= glow.to then
        glow.t = glow.t + dt
        local p = glow.dur > 0 and math.min(1, glow.t / glow.dur) or 1
        glow.now = p >= 1 and glow.to or glow.from + (glow.to - glow.from) * ease(p)
        if p >= 1 and glowNext then
            local n = glowNext
            glowTo(n[1], n[2])
        end
    end
    local level = glow.now
    local fade = math.min(1, level / Scene.REST)
    local moving = Motion.On()
    local k = clock * theme.flick
    local swell = moving and 1 + 0.07 * math.sin(k * 0.9) + 0.04 * math.sin(k * 2.1 + 1) or 1
    f.deep:SetAlpha(math.min(0.8, theme.deep * level * swell))
    f.shine:SetAlpha(math.min(0.8, theme.shine * level * swell))
    if waveAt and clock - waveAt >= Scene.WAVE_LIFE then waveAt = nil end
    stepTide(dt)
    stepSurface(fade)
    stepBobber(dt, fade)
    stepHammer(dt, fade)
    stepGears(dt, fade)
    stepNeedle(fade)
    f.count:SetAlpha(fade)
    if moving then
        if theme.calm and Scene.state == "line" and bob.phase == "float" and clock >= ripAt then
            ripAt = clock + Scene.RIPPLE_EVERY
            ripple(150, 0.28, Scene.RIPPLE_LIFE)
        end
        stepRipples(dt, fade)
        stepBubbles(dt)
        stepDrops(dt)
    end
    stepBloom()
    if Scene.state == "idle" and glow.now == 0 and glow.to == 0 then hideAll() end
end

-- When this channel started and ends (GetTime's clock), the game's own times;
-- nil for a channel it can't say.
local function channelTimes(id)
    local from, to
    if id then
        local _, _, _, began, ends = UnitChannelInfo("player")
        if type(began) == "number" and type(ends) == "number" and not secret(began) and not secret(ends) then
            from, to = began / 1000, ends / 1000
        end
    else
        from, to = GetTime(), GetTime() + Scene.PREVIEW_CHANNEL
    end
    return from, to
end

-- The work started, in a theme, its bar running from from to to.
local function open(name, id, from, to)
    build()
    local next = Scene.THEMES[name]
    local fresh = next ~= theme or not f:IsShown()
    theme = next
    layout()
    run = run + 1
    spell, stoppedAt = id, nil
    Scene.state = "line"
    if not f:IsShown() then
        clock = 0
        f:Show()
    end
    if fresh then dress() end
    glowTo(Scene.REST, Scene.GLOW_IN)
    if fresh or not theme.still then
        bob.t = 0
        bob.phase = Motion.On() and not theme.still and "in" or "float"
        f.bobber:SetAlpha(0)
        f.bobber:Show()
    end
    ripAt = clock + Scene.DROP_IN + Scene.RIPPLE_EVERY
    tideFrom, tideTo = from, to
    step(0)
    DUI.Fade.Hush("work", Scene.HUSH)
    DUI.Fire("CastElsewhere", to ~= nil)
end

-- The line went in. Every cast but the first lands on water already there.
function Scene.Cast(id)
    open("water", id, channelTimes(id))
end

-- The crafts left after this one (the preview says its own).
local function recasts()
    if Scene.previewLeft then return Scene.previewLeft end
    local fn = C_TradeSkillUI and C_TradeSkillUI.GetRemainingRecasts
    if type(fn) ~= "function" then return 0 end
    local ok, n = pcall(fn)
    return ok and type(n) == "number" and not secret(n) and math.max(0, n) or 0
end

-- A craft started (from, to: the game's ms). Crafts of one batch run on one
-- tide: this one, then the rest at the pace so far.
function Scene.Craft(name, id, from, to)
    from, to = from / 1000, to / 1000
    local same = Scene.state ~= "idle" and theme == Scene.THEMES[name] and spell == id and made < total
    local left = recasts()
    if not same then made = 0 end
    local start = same and tideFrom or from
    local pace = made > 0 and (from - start) / made or to - from
    total = made + left + 1
    open(name, id, start, to + left * pace)
    f.count:SetShown(total > 1)
    f.count:SetText(string.format("%d / %d", made + 1, total))
end

-- One of the batch is done.
function Scene.Made()
    made = made + 1
    Scene.Caught()
end

-- Back to play: the bars come back, the water fades (snap: all at once).
function Scene.Wake(snap)
    if Scene.state == "idle" then return end
    Scene.state = "idle"
    run = run + 1
    spell, stoppedAt = nil, nil
    DUI.Fade.Unhush("work", snap)
    DUI.Fire("CastElsewhere", false)
    if snap or not Motion.On() then
        hideAll()
        return
    end
    if bob.phase ~= "none" then bob.phase, bob.t = "under", 0 end
    glowTo(0, Scene.GLOW_OUT)
end

-- The line came in, a fish on it or not: the next cast has LINGER seconds.
function Scene.LineIn()
    if Scene.state ~= "line" then return end
    Scene.state = "waiting"
    stoppedAt = GetTime()
    DUI.Fire("CastElsewhere", false)
    local id = run
    C_Timer.After(theme.linger, function() if id == run then Scene.Wake() end end)
end

-- A fish came in: the bobber goes under and the water splashes. An item
-- done: the anvil stays and the sparks fly.
function Scene.Caught()
    if Scene.state == "idle" then return end
    stoppedAt = nil
    if theme.sound then DUI.Sound.Play(theme.sound) end
    if not Motion.On() then
        if not theme.still then
            bob.phase = "none"
            f.bobber:Hide()
        end
        return
    end
    if not theme.still then bob.phase, bob.t = "under", 0 end
    kick = 1
    glowTo(Scene.SWELL, Scene.SWELL_UP, { Scene.REST, Scene.SWELL_SETTLE })
    waveAt, bloomAt = clock, clock
    ripple(520, 0.8, Scene.RIPPLE_LIFE)
    for _ = 1, Scene.BURST do throw(true) end
end

function Scene.Preview()
    if InCombatLockdown() then return end
    Scene.Cast()
    local id = run
    C_Timer.After(Scene.PREVIEW_CATCH, function()
        if id ~= run then return end
        Scene.LineIn()
        Scene.Caught()
    end)
end

-- A craft's preview: a small batch in its theme.
function Scene.PreviewCraft(name)
    if InCombatLockdown() then return end
    local mine = {}
    Scene.previewing = mine
    local function live() return Scene.previewing == mine and Scene.state ~= "idle" end
    local function craft(i)
        local now = GetTime()
        Scene.previewLeft = Scene.CRAFT_PREVIEW - i
        Scene.Craft(name, -1, now * 1000, (now + Scene.CRAFT_SECS) * 1000)
        Scene.previewLeft = nil
        C_Timer.After(Scene.CRAFT_SECS, function()
            if not live() then return end
            Scene.LineIn()
            Scene.Made()
            if i < Scene.CRAFT_PREVIEW then craft(i + 1) end
        end)
    end
    craft(1)
end

local function trade(name, ...)
    local fn = C_TradeSkillUI and C_TradeSkillUI[name]
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    return ok and v or nil
end

local function lineTheme(info)
    if type(info) ~= "table" then return nil end
    return Scene.LINES[info.parentProfessionID] or Scene.LINES[info.professionID]
end

-- The theme for a craft's recipe, or nil. Tries the recipe's profession, then
-- the skill line, then (with `window`) the profession open in the window. Only
-- used for casts the game calls a craft; an open window says nothing about a plain spell.
local function themeOf(id, window)
    local name = lineTheme(trade("GetProfessionInfoByRecipeID", id))
    if name then return name end
    for line, theme in pairs(Scene.LINES) do
        if trade("IsRecipeInSkillLine", id, line) == true then return theme end
    end
    return window and lineTheme(trade("GetBaseProfessionInfo")) or nil
end

local function free() return not InCombatLockdown() and not DUI.Restricted() end

local function onScene(_, event, _, b, c, d)
    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        if sceneOn(Scene.THEMES.water) and not secret(c) and free() and c == Fish.Spell() then
            Scene.Cast(c)
        end
    elseif event == "UNIT_SPELLCAST_START" then
        if secret(c) or not free() then return end
        local _, _, _, from, to, craft = UnitCastingInfo("player")
        if (issecretvalue and issecretvalue(craft)) or craft ~= true or type(from) ~= "number" or type(to) ~= "number" or secret(from) or secret(to) then return end
        local name = themeOf(c, true)
        if name and sceneOn(Scene.THEMES[name]) then Scene.Craft(name, c, from, to) end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if spell and not secret(c) and c == spell then Scene.LineIn() end
    elseif event == "UNIT_SPELLCAST_STOP" then
        if spell and theme.fills and not secret(c) and c == spell then Scene.LineIn() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if spell and theme.fills and not secret(c) and c == spell then Scene.Made() end
    elseif event == "LOOT_READY" then
        if theme.catch and stoppedAt and GetTime() - stoppedAt <= Scene.CATCH then Scene.Caught() end
    elseif event == "UNIT_SPELLCAST_SENT" then
        if Scene.state ~= "idle" and not secret(d) and d ~= spell and not (theme.fills and themeOf(d)) then Scene.Wake() end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_ENTERING_WORLD" then
        Scene.Wake(true)
    else
        Scene.Wake()
    end
end

local function watch()
    if watching then return end
    watching = CreateFrame("Frame")
    for _, event in ipairs({ "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_SENT",
                             "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED" }) do
        watching:RegisterUnitEvent(event, "player")
    end
    for _, event in ipairs({ "LOOT_READY", "PLAYER_STARTED_MOVING", "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED",
                             "PLAYER_ENTERING_WORLD" }) do
        watching:RegisterEvent(event)
    end
    watching:SetScript("OnEvent", onScene)
    DUI.RegisterCommand("fishing", Scene.Preview, DUI.L["/dui fishing - preview the fishing water"])
    DUI.RegisterCommand("forge", function() Scene.PreviewCraft("forge") end, DUI.L["/dui forge - preview the forge"])
    DUI.RegisterCommand("brew", function() Scene.PreviewCraft("brew") end, DUI.L["/dui brew - preview the brew"])
    DUI.RegisterCommand("workshop", function() Scene.PreviewCraft("workshop") end, DUI.L["/dui workshop - preview the workshop"])
    DUI.RegisterCommand("sewing", function() Scene.PreviewCraft("sewing") end, DUI.L["/dui sewing - preview the sewing"])
end

function Fish.Enable(m)
    mod = m
    watch()
    DUI.RegisterEvent("GLOBAL_MOUSE_DOWN", onMouseDown)
    DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function() disarm(true) end)   -- the last moment it's allowed
    local function failed(_, unit)
        if unit == "player" then baitedUntil = 0 end
    end
    DUI.RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", failed)
    DUI.RegisterEvent("UNIT_SPELLCAST_FAILED", failed)
end

function Fish.Refresh(m)
    mod = m
    if not wanted() then disarm() end
    if not sceneOn() then Scene.Wake(true) end
end
