-- Shared media. Bar textures and fonts that other addons registered with
-- LibSharedMedia are offered next to ours in Appearance, and ours are
-- registered there for everyone else. Without the library (embedded in the
-- release and in many other addons) only our own are offered.
--
-- A shared pick is saved as "lsm:<name>". Addons register media as they load,
-- some after us, so picks are looked up at use time and a late arrival
-- triggers a repaint.

local _, DUI = ...

local Media = {}
DUI.Media = Media

Media.PREFIX = "lsm:"
Media.OWN_BAR = "DaylightUI" -- our bar fill's name in the shared list

-- Our other bar fills (from tools/make_bar_textures.py). Picked by key like
-- shared ones (Media.Fetch resolves them), listed right after ours, and
-- registered in the shared list as "DaylightUI <label>".
Media.BARS = {
    { key = "silk", label = "Silk" },
    { key = "glass", label = "Glass" },
    { key = "tube", label = "Tube" },
    { key = "slant", label = "Slant" },
    { key = "brushed", label = "Brushed" },
    { key = "grain", label = "Grain" },
}
local ownBar = {}
Media.BAR_PICKS = { "daylight" } -- the setup guide's cards
for _, b in ipairs(Media.BARS) do
    b.file = DUI.MEDIA .. "bar-" .. b.key .. ".tga"
    b.shared = Media.OWN_BAR .. " " .. b.label
    ownBar[b.key] = b
    Media.BAR_PICKS[#Media.BAR_PICKS + 1] = b.key
end

-- Our own bar choices for a dropdown: fills values and order after
-- "daylight", and returns the shared names to leave out of the shared part.
function Media.OwnBars(values, order)
    local skip = { [Media.OWN_BAR] = true }
    for _, b in ipairs(Media.BARS) do
        values[b.key] = b.label
        order[#order + 1] = b.key
        skip[b.shared] = true
    end
    return skip
end

function Media.Lib()
    return LibStub and LibStub("LibSharedMedia-3.0", true) or nil
end

-- "lsm:Name" -> "Name", else nil.
function Media.SharedName(key)
    if type(key) ~= "string" then return nil end
    local plen = #Media.PREFIX
    if string.sub(key, 1, plen) ~= Media.PREFIX then return nil end
    return string.sub(key, plen + 1)
end

-- The file for a shared pick (or one of Media.BARS), or nil if there's no
-- library or it isn't registered yet.
function Media.Fetch(kind, key)
    if kind == "statusbar" and ownBar[key] then return ownBar[key].file end
    local name, lsm = Media.SharedName(key), Media.Lib()
    if not (name and lsm) then return nil end
    local ok, file = pcall(lsm.Fetch, lsm, kind, name, true)
    return ok and file or nil
end

-- One kind's shared list as dropdown values ({ ["lsm:Name"] = "Name" }) and
-- names in order, skipping `skip` (our own, already offered).
function Media.List(kind, skip)
    local values, order, lsm = {}, {}, Media.Lib()
    if not lsm then return values, order end
    local ok, names = pcall(lsm.List, lsm, kind)
    if not ok or type(names) ~= "table" then return values, order end
    for _, name in ipairs(names) do
        if not (skip and skip[name]) then
            local key = Media.PREFIX .. name
            values[key] = name
            order[#order + 1] = key
        end
    end
    return values, order
end

-- Slots. A slot is one area's own pick for its text or bars (the unit frames'
-- health bar, window text...), saved in that area's settings. A slot set to
-- "general" follows General > Appearance, and "Apply to all" resets every slot
-- of a kind back to that.
-- kind: "font" | "bar" (a bar's fill) | "back" (the dark part behind it).

Media.GENERAL = "general"
Media.SLOTS = {} -- id -> { scope, key, kind, parent }

-- parent (optional): another slot this one follows while set to "general",
-- e.g. a unit frame's name font follows the unit frame font, then General.
function Media.RegisterSlot(id, scope, key, kind, parent)
    Media.SLOTS[id] = { scope = scope, key = key, kind = kind, parent = parent }
end

-- A bar's two slots: the fill (id) and the empty part behind it (id ..
-- ".back", which Style.Bar's background follows). Both follow `parent` while
-- set to "general".
function Media.RegisterBar(id, scope, key, backKey, parent)
    Media.RegisterSlot(id, scope, key, "bar", parent)
    Media.RegisterSlot(id .. ".back", scope, backKey, "back", parent and parent .. ".back")
end

-- An area's whole set, saved under its `media` settings: bars (media.<key>
-- and media.<key>Back), its own font (media.font) and one per kind of text
-- (media.<key>Font). Each is independent and "general" means General >
-- Appearance. Returns the slot ids as { bars = { key = id }, font = id,
-- fonts = { key = id } }. Option rows: Options.BarRow/BackRow/FontRow.
function Media.RegisterArea(prefix, scope, bars, fonts)
    local ids = { bars = {}, fonts = {}, font = prefix .. ".font" }
    for _, k in ipairs(bars or {}) do
        ids.bars[k] = prefix .. "." .. k
        Media.RegisterBar(ids.bars[k], scope, "media." .. k, "media." .. k .. "Back")
    end
    Media.RegisterSlot(ids.font, scope, "media.font", "font")
    for _, k in ipairs(fonts or {}) do
        ids.fonts[k] = prefix .. ".font." .. k
        Media.RegisterSlot(ids.fonts[k], scope, "media." .. k .. "Font", "font")
    end
    return ids
end

-- Defaults for RegisterArea's settings: everything follows General.
function Media.AreaDefaults(bars, fonts)
    local d = { font = Media.GENERAL }
    for _, k in ipairs(bars or {}) do d[k], d[k .. "Back"] = Media.GENERAL, Media.GENERAL end
    for _, k in ipairs(fonts or {}) do d[k .. "Font"] = Media.GENERAL end
    return d
end

-- The slot's own pick (or its parent's), or nil when it follows General, is
-- unknown, or its module is off.
function Media.Pick(id)
    for _ = 1, 4 do
        local s = id and Media.SLOTS[id]
        if not s then return nil end
        local v = DUI:Get(s.scope, s.key)
        if type(v) == "string" and v ~= Media.GENERAL and v ~= "" then return v end
        id = s.parent
    end
end

-- A pick set on this slot itself, not inherited.
local function ownPick(s)
    local v = DUI:Get(s.scope, s.key)
    return type(v) == "string" and v ~= Media.GENERAL and v ~= ""
end

function Media.ApplyToAll(kind)
    for _, s in pairs(Media.SLOTS) do
        if s.kind == kind and ownPick(s) then
            DUI:Set(s.scope, s.key, Media.GENERAL)
        end
    end
end

-- Our windows' own slots (General > Appearance): their text and their bars (W.Bar).
Media.RegisterSlot("windows.font", "general", "windowFont", "font")
Media.RegisterSlot("windows.bar", "general", "windowBar", "bar")
Media.RegisterSlot("windows.back", "general", "windowBack", "back")

-- A slot changed, so the core repaints every bar and text that follows one.
DUI.On("SettingChanged", function(scope, path)
    for _, s in pairs(Media.SLOTS) do
        if s.scope == scope and s.key == path then
            if scope ~= "general" then DUI.NotifyStyleChanged() end
            return
        end
    end
end)

-- Whether any slot of this kind has its own pick (so "Apply to all" would change something).
function Media.AnyOwn(kind)
    for _, s in pairs(Media.SLOTS) do
        if s.kind == kind and ownPick(s) then return true end
    end
    return false
end

-- Register our bar fills and bundled fonts in the shared lists.
local registered = false
function Media.RegisterOwn()
    local lsm = Media.Lib()
    if registered or not lsm then return end
    registered = true
    pcall(lsm.Register, lsm, "statusbar", Media.OWN_BAR, DUI.Style.BAR.fill)
    for _, b in ipairs(Media.BARS) do
        pcall(lsm.Register, lsm, "statusbar", b.shared, b.file)
    end
    for _, key in ipairs(DUI.Style.FONT_ORDER) do
        local f = DUI.Style.FONTS[key]
        -- Only the fonts we ship, not the client's.
        if f.file and string.find(f.file, DUI.MEDIA, 1, true) == 1 then
            pcall(lsm.Register, lsm, "font", f.label, f.file)
        end
    end
end

-- Whether a pick (General's or a slot's) uses shared media. With name, only that one.
local function usesShared(name)
    local g = DUI.DB.General()
    local function is(v)
        local n = Media.SharedName(v)
        return n ~= nil and (name == nil or n == name)
    end
    if is(g.barTexture) or is(g.barBack) or is(g.font) then return true end
    for id in pairs(Media.SLOTS) do
        if is(Media.Pick(id)) then return true end
    end
    return false
end

-- At login, register ours and repaint if a shared pick is in use (its addon
-- may have loaded after us). Later arrivals repaint too.
local hooked = false
function Media.Hook()
    Media.RegisterOwn()
    local lsm = Media.Lib()
    if lsm and not hooked and lsm.RegisterCallback then
        hooked = true
        lsm.RegisterCallback(Media, "LibSharedMedia_Registered", function(_, kind, name)
            if (kind == "statusbar" or kind == "font") and usesShared(tostring(name)) then
                DUI.NotifyStyleChanged()
            end
        end)
    end
    if usesShared() then DUI.NotifyStyleChanged() end
end

DUI.RegisterEvent("PLAYER_LOGIN", Media.Hook)
