-- The "Use this font for the game's text" option. Applies the Appearance font
-- to the game's own text (menus, tooltips, quest text, error popups, nameplate
-- names, combat numbers) by changing its named font objects, keeping each
-- one's size and outline. Font objects aren't protected, so this is safe in
-- combat, and no game frame is touched. Turning it off restores every face.
-- Damage numbers (DAMAGE_TEXT_FONT) follow this font unless the Damage numbers
-- page picks its own. The client reads that one only at login, so a change
-- shows after a game restart.

local ADDON_NAME, DUI = ...

local GameFonts = {}
DUI.GameFonts = GameFonts

GameFonts.GLOBALS = { "STANDARD_TEXT_FONT", "UNIT_NAME_FONT", "NAMEPLATE_FONT" }

local savedGlobals -- the client's own paths, saved the first time they're replaced
local savedFaces = {} -- font object -> the { face, flags } it had before
local clientDamage -- { the client's DAMAGE_TEXT_FONT } while ours is set

-- The client's own font, even after STANDARD_TEXT_FONT has been replaced.
function GameFonts.ClientFont()
    return (savedGlobals and savedGlobals.STANDARD_TEXT_FONT) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

-- The font for the game's text, or nil to keep the game's own.
function GameFonts.Wanted()
    if DUI.DB.General().gameText ~= true or DUI.DB.UseLocalFont() then return nil end
    local font = DUI.Style.FONT
    if type(font) ~= "string" or font == GameFonts.ClientFont() then return nil end
    return font
end

-- A font page's own pick, or nil for the game's.
local function picked(key)
    if DUI.DB.UseLocalFont() then return nil end
    local f = DUI.Style.FONTS[key]
    local file = (DUI.Media and DUI.Media.Fetch("font", key)) or (f and f.file)
    if type(file) ~= "string" or file == GameFonts.ClientFont() then return nil end
    return file
end

-- "Automatic" means the Appearance font, even when that's the Game font pick,
-- because the game's damage font is DAMAGE_TEXT_FONT, not STANDARD_TEXT_FONT.
local function appearance()
    if DUI.DB.UseLocalFont() then return nil end
    local font = DUI.Style.FONT
    return type(font) == "string" and font or nil
end

-- The damage number font, or nil for the game's.
function GameFonts.DamageWanted()
    local key = DUI:Get("general", "damage.font")
    if key == nil or key == "auto" then return appearance() end
    return picked(key)
end

-- Font for the scrolling combat text over you (ours and the game's
-- CombatTextFont), or nil for the game's. A font object, so it updates live.
function GameFonts.CombatTextWanted()
    local key = DUI:Get("general", "damage.sctFont")
    if key == nil or key == "auto" then return appearance() end
    return picked(key)
end

-- Every named font object the game has. GetFonts lists them; without it, one
-- pass over the globals finds them.
local function fontObjects()
    local list = {}
    if type(GetFonts) == "function" then
        local ok, names = pcall(GetFonts)
        if ok and type(names) == "table" then
            for _, name in ipairs(names) do
                local obj = type(name) == "string" and _G[name] or name
                if type(obj) == "table" then list[#list + 1] = obj end
            end
            return list
        end
    end
    for _, obj in pairs(_G) do
        if type(obj) == "table" and type(obj.IsObjectType) == "function" and type(obj.SetFont) == "function" then
            local ok, isFont = pcall(obj.IsObjectType, obj, "Font")
            if ok and isFont == true then list[#list + 1] = obj end
        end
    end
    return list
end

-- The client draws the combat text over the player with "FILTER, FIXEDHEIGHT"
-- and shrinks each line with SetTextHeight. Any other face that keeps those
-- flags spaces out every letter ("B l o c k").
local function ourFlags(flags)
    if type(flags) ~= "string" or not flags:find("FIXEDHEIGHT", 1, true) then return flags end
    local keep = {}
    for flag in flags:gmatch("[^,%s]+") do
        if flag ~= "FIXEDHEIGHT" and flag ~= "FILTER" then keep[#keep + 1] = flag end
    end
    return table.concat(keep, ", ")
end

local function setFace(obj, face)
    if type(obj.GetFont) ~= "function" or type(obj.SetFont) ~= "function" then return end
    local ok, current, size, flags = pcall(obj.GetFont, obj)
    if not ok or type(size) ~= "number" or size <= 0 then return end
    local saved = savedFaces[obj]
    if face == nil then
        if saved == nil then return end
        face, flags = saved[1], saved[2]
        savedFaces[obj] = nil
    else
        if saved == nil then
            if current == face then return end
            savedFaces[obj] = { current, flags }
            flags = ourFlags(flags)
        else
            -- Already set (every later ADDON_LOADED walks them all again). SetFont redraws
            -- every text using the object, so skip it.
            local want = ourFlags(saved[2])
            if current == face and flags == want then return end
            flags = want
        end
    end
    pcall(obj.SetFont, obj, face, size, flags)
end

-- Applies the wanted font to the game's text, or restores the game's own.
function GameFonts.Apply()
    local font = GameFonts.Wanted()
    if font then
        if not savedGlobals then
            savedGlobals = {}
            for _, k in ipairs(GameFonts.GLOBALS) do savedGlobals[k] = _G[k] end
        end
        for _, k in ipairs(GameFonts.GLOBALS) do _G[k] = font end
        for _, obj in ipairs(fontObjects()) do
            if obj ~= CombatTextFont then setFace(obj, font) end
        end
    elseif savedGlobals then
        for _, k in ipairs(GameFonts.GLOBALS) do _G[k] = savedGlobals[k] end
        savedGlobals = nil
        for obj in pairs(savedFaces) do
            if obj ~= CombatTextFont then setFace(obj, nil) end
        end
    end
    -- The combat text over you has its own pick on the Damage numbers page.
    if type(CombatTextFont) == "table" then setFace(CombatTextFont, GameFonts.CombatTextWanted()) end
    -- The client reads DAMAGE_TEXT_FONT once, early in login. Before PLAYER_LOGIN
    -- the spec's profile isn't chosen yet, so apply the last chosen font (saved
    -- account-wide, false = the game's).
    local root, damage = DUI.DB.Root(), GameFonts.DamageWanted()
    if DUI.loggedIn then
        root.damageFont = damage or false
    elseif root.damageFont ~= nil then
        damage = root.damageFont or nil
    end
    if damage then
        clientDamage = clientDamage or { DAMAGE_TEXT_FONT }
        DAMAGE_TEXT_FONT = damage
    elseif clientDamage then
        DAMAGE_TEXT_FONT = clientDamage[1]
        clientDamage = nil
    end
end

-- Ours first (Core has picked the font by then). Each game addon that loads
-- later brings its own font objects, so walk them once on the next frame no
-- matter how many loaded (dozens at login, a few per window).
local walkQueued = false
DUI.RegisterEvent("ADDON_LOADED", function(_, name)
    if not DUI.DB.sv then return end
    if name == ADDON_NAME then return GameFonts.Apply() end
    if walkQueued then return end
    walkQueued = true
    C_Timer.After(0, function()
        walkQueued = false
        DUI.SafeCall(GameFonts.Apply)
    end)
end)
DUI.On("RepaintCore", GameFonts.Apply)
-- Once the spec's profile is active, its damage font is saved for next time.
DUI.On("Login", GameFonts.Apply)
