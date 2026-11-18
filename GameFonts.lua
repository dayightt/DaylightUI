-- The "Use this font for the game's text" option. Puts the Appearance font on
-- the game's own text (menus, tooltips, quest text, popups, nameplate and
-- speech bubble text) by changing its named font objects, keeping each one's
-- size and outline. It runs once, at login, the way EllesmereUI's "Apply to
-- All Game Text" does: the game's fonts are never changed while its frames are
-- drawing with them, so switching it or picking another font shows after a
-- /reload. Font objects that load later keep the game's face until then.
-- Damage numbers (DAMAGE_TEXT_FONT) and the combat text over you have picks of
-- their own on the Damage numbers page and follow them live.

local ADDON_NAME, DUI = ...

local GameFonts = {}
DUI.GameFonts = GameFonts

-- NAMEPLATE_FONT stays the game's: the plates' text follows their font objects.
GameFonts.GLOBALS = { "STANDARD_TEXT_FONT", "UNIT_NAME_FONT" }

local savedGlobals -- the client's own paths, saved the first time they're replaced
local savedFaces = {} -- font object -> the { face, flags } it had before
local clientDamage -- { the client's DAMAGE_TEXT_FONT } while Daylight UI's is set

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
    local f = DUI.Style.FontEntry(key)
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

-- Font for the scrolling combat text over you (Daylight UI's and the game's
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
            -- Already set (the combat text font comes back on every repaint). SetFont
            -- redraws every text using the object, so skip it.
            local want = ourFlags(saved[2])
            if current == face and flags == want then return end
            flags = want
        end
    end
    pcall(obj.SetFont, obj, face, size, flags)
end

-- Many of the game's fonts are families, one font per alphabet (the nameplate
-- and speech bubble ones among them). A SetFont on the family itself changes
-- none of them, so each member takes the face on its own, keeping its own
-- flags. An alphabet the face can't draw keeps the game's.
local function takes(alphabet, face)
    if alphabet == "roman" then return true end
    if alphabet == "russian" then return DUI.Style.HasCyrillic(face) end
    return false
end

local CJK = { koKR = true, zhCN = true, zhTW = true }

local function putOn(obj, face)
    if type(obj.GetFontObjectForAlphabet) == "function" then
        for _, alphabet in ipairs(DUI.Style.ALPHABETS) do
            local ok, member = pcall(obj.GetFontObjectForAlphabet, obj, alphabet)
            if ok and type(member) == "table" and member ~= obj and takes(alphabet, face) then
                setFace(member, face)
            end
        end
        -- The family's own font is what GetFont reads and copies take.
        if CJK[type(GetLocale) == "function" and GetLocale() or ""] then return end
    end
    setFace(obj, face)
end

-- Puts the wanted font on the game's text. Only the first call of a session
-- does anything.
local applied = false
function GameFonts.ApplyGameText()
    if applied then return end
    applied = true
    local font = GameFonts.Wanted()
    if not font then return end
    savedGlobals = {}
    for _, k in ipairs(GameFonts.GLOBALS) do
        savedGlobals[k] = _G[k]
        _G[k] = font
    end
    -- Daylight UI's own families are named fonts too: each carries a face picked
    -- for its own text (the chat's, for one) and keeps it.
    local own = DUI.Style.OwnFamily
    for _, obj in ipairs(fontObjects()) do
        if obj ~= CombatTextFont and not own(obj) then putOn(obj, font) end
    end
end

-- The damage number and combat text fonts, which change live.
function GameFonts.Apply()
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

-- Daylight UI's first (Core has picked the font by then), for the damage font.
DUI.RegisterEvent("ADDON_LOADED", function(_, name)
    if name == ADDON_NAME and DUI.DB.sv then GameFonts.Apply() end
end)
DUI.On("RepaintCore", GameFonts.Apply)
-- The spec's profile is active at login: the game's text takes its font once,
-- and its damage font is saved for next time.
DUI.On("Login", function()
    GameFonts.ApplyGameText()
    GameFonts.Apply()
end)
