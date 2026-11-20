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

-- The font for text the game makes from no font object. NAMEPLATE_FONT and
-- UNIT_NAME_FONT (the names over heads) stay the game's, as EllesmereUI leaves them.
GameFonts.GLOBALS = { "STANDARD_TEXT_FONT" }

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
            -- redraws every text using the object, so skip it. Compared with what
            -- was set here: the client may hand the path back in another form.
            if saved.face == face then return end
            flags = ourFlags(saved[2])
        end
    end
    if DUI.SafeCall(obj.SetFont, obj, face, size, flags) and savedFaces[obj] then savedFaces[obj].face = face end
end

-- The game's fonts the pass leaves whole. The combat text over you draws with
-- CombatTextFont, which inherits SystemFont_World, so every member of both is
-- left as it is: the combat text has its own pick on the Damage numbers page.
GameFonts.KEEP = { "CombatTextFont", "SystemFont_World" }
-- The hotkey text shows the range dot (U+25CF), which most bundled fonts can't
-- draw, so this one keeps its own faces.
GameFonts.KEEP_FACE = { "NumberFontNormalSmallGray" }

local CJK_ALPHABET = { koKR = "korean", zhCN = "simplifiedchinese", zhTW = "traditionalchinese" }

local function locale() return type(GetLocale) == "function" and GetLocale() or "" end

-- The alphabet the client's own language draws with.
local function clientAlphabet()
    local l = locale()
    return CJK_ALPHABET[l] or (l == "ruRU" and "russian") or "roman"
end

-- Whether one alphabet's member of a family takes the face. Korean and Chinese
-- letters keep the game's: a font that draws them is the client's own, and then
-- there's nothing to swap.
local function takes(alphabet, face)
    if alphabet == "roman" then return true end
    if alphabet == "russian" then return DUI.Style.HasCyrillic(face) end
    return false
end

-- A family has members of its own for its Latin and Russian letters.
local function isFamily(obj)
    if type(obj.GetFontObjectForAlphabet) ~= "function" then return false end
    local okR, roman = pcall(obj.GetFontObjectForAlphabet, obj, "roman")
    local okC, russian = pcall(obj.GetFontObjectForAlphabet, obj, "russian")
    return okR and okC and type(roman) == "table" and type(russian) == "table" and roman ~= russian
end

local function members(obj, fn)
    for _, alphabet in ipairs(DUI.Style.ALPHABETS) do
        local ok, member = pcall(obj.GetFontObjectForAlphabet, obj, alphabet)
        if ok and type(member) == "table" then fn(alphabet, member) end
    end
end

-- One member (or a plain font) takes the face at its own size and flags. A
-- member several fonts share is set once.
local function setMember(member, face, done)
    if done[member] then return end
    done[member] = true
    if face == nil or type(member.GetFont) ~= "function" then return end
    local ok, current, size, flags = pcall(member.GetFont, member)
    if not ok or type(size) ~= "number" or size <= 0 or current == face then return end
    DUI.SafeCall(member.SetFont, member, face, size, flags or "")
end

-- A family changes member by member: a SetFont on the family itself changes
-- none of them. Its own font (what GetFont reads and copies take) changes only
-- when the face draws the client's own language.
local function putOn(obj, face, done)
    if not isFamily(obj) then return setMember(obj, face, done) end
    members(obj, function(alphabet, member)
        setMember(member, takes(alphabet, face) and face or nil, done)
    end)
    setMember(obj, takes(clientAlphabet(), face) and face or nil, done)
end

local function leaveWhole(obj, done)
    done[obj] = true
    if isFamily(obj) then members(obj, function(_, member) done[member] = true end) end
end

-- A font that draws through members it shares with another family gets a
-- family of its own made from those members' faces, so the shared members can
-- take the face while it keeps its own. Its color and shadow come with it.
local keptCount = 0
local function keepFaces(obj, done)
    if not isFamily(obj) then done[obj] = true return end
    if type(CreateFontFamily) ~= "function" or type(obj.SetFontObject) ~= "function" then return end
    local list = {}
    members(obj, function(alphabet, member)
        local ok, face, size, flags = pcall(member.GetFont, member)
        if ok and face and type(size) == "number" and size > 0 then
            list[#list + 1] = { alphabet = alphabet, file = face, height = size, flags = flags or "" }
        end
    end)
    if #list == 0 then return end
    keptCount = keptCount + 1
    local okFam, fam = DUI.SafeReturn(CreateFontFamily, "DaylightUIKeptFont" .. keptCount, list)
    if not (okFam and type(fam) == "table") then return end
    local r, g, b, a
    if obj.GetTextColor then r, g, b, a = obj:GetTextColor() end
    local sr, sg, sb, sa
    if obj.GetShadowColor then sr, sg, sb, sa = obj:GetShadowColor() end
    local sx, sy
    if obj.GetShadowOffset then sx, sy = obj:GetShadowOffset() end
    if not DUI.SafeCall(obj.SetFontObject, obj, fam) then return end
    if r and obj.SetTextColor then obj:SetTextColor(r, g, b, a) end
    if sr and obj.SetShadowColor then obj:SetShadowColor(sr, sg, sb, sa) end
    if sx and obj.SetShadowOffset then obj:SetShadowOffset(sx, sy) end
    leaveWhole(fam, done)
    done[obj] = true
end

-- Gives one of the game's font objects a face, size and flags, member by member
-- when it's a family (each member keeps its own face where the face can't draw
-- its letters). Only what differs is set: a SetFont redraws every text using it.
-- What was last set on each object here. The client may hand a path back in
-- another form, so this is what's compared, not GetFont.
local setOn = setmetatable({}, { __mode = "k" })

function GameFonts.SetObjectFont(obj, face, size, flags)
    if type(obj) ~= "table" or type(obj.SetFont) ~= "function" then return end
    flags = flags or ""
    local spec = tostring(face) .. "|" .. tostring(size) .. "|" .. flags
    if setOn[obj] == spec then return end
    setOn[obj] = spec
    local function one(member, f)
        local ok, current, currentSize, currentFlags = pcall(member.GetFont, member)
        if not ok then return end
        f = f or current
        if f == nil then return end
        if f == current and currentSize == size and (currentFlags or "") == flags then return end
        DUI.SafeCall(member.SetFont, member, f, size, flags)
    end
    if not isFamily(obj) then return one(obj, face) end
    members(obj, function(alphabet, member) one(member, takes(alphabet, face) and face or nil) end)
    one(obj, takes(clientAlphabet(), face) and face or nil)
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
    local done = {}
    for _, name in ipairs(GameFonts.KEEP) do
        local obj = _G[name]
        if type(obj) == "table" then leaveWhole(obj, done) end
    end
    for _, name in ipairs(GameFonts.KEEP_FACE) do
        local obj = _G[name]
        if type(obj) == "table" then keepFaces(obj, done) end
    end
    -- Daylight UI's own families are named fonts too: each carries a face picked
    -- for its own text (the chat's, for one) and keeps it.
    local own = DUI.Style.OwnFamily
    for _, obj in ipairs(fontObjects()) do
        if not own(obj) and type(obj.SetFont) == "function" then putOn(obj, font, done) end
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
        if DAMAGE_TEXT_FONT ~= damage then DAMAGE_TEXT_FONT = damage end
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
