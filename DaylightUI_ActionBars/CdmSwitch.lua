-- Switches on the buffs the game's Cooldown Manager hides by default.
-- The game only makes an icon for a spell its layout shows, and on this client
-- every buff starts hidden. A buff with one of the game's icons can be followed
-- through a fight, since the icon says plainly whether the buff is up. One without
-- can only be drawn. So each hidden buff of the class goes into its own row of the
-- game's layout, and the player never has to open the game's settings for it.
--
-- The layout is one string (C_CooldownViewer.GetLayoutData), written the way the
-- game's own serializer writes it (Blizzard_CooldownViewer,
-- CooldownViewerSettingsDataStoreSerialization.lua): CBOR, deflate, base64. Only
-- those calls are used here. The game's Cooldown Manager code must never run from
-- addon code, because its viewers keep a table that refuses tainted access.
--
-- The game reads the string once while the UI loads and keeps its own copy from
-- then on, so a write counts from the next load. Two moments are used: as the UI
-- comes up, before the game's read, which makes it live in that same session, and
-- as the UI goes down, which keeps it for the next login whatever the game saved
-- in between.
--
-- The table: [1] format, [2] the layout picked per class-and-spec tag (0 = the
-- game's default, which is never stored), [3] layouts by tag then layout id,
-- [4] layout id -> name. A layout: [1] the order, [2] row -> ids moved there,
-- [3] alerts. A buff the player hid by hand is an id under a hidden row in [2];
-- one hidden only by default has no entry at all. Tag = class id * 10 + spec.
--
-- A buff hidden by hand is left alone, unless it is placed in a Daylight UI layout
-- of the class: the game's icon is the only thing that can say in a fight whether
-- it dropped, and Daylight UI keeps the game's icon out of sight anyway. Its old
-- row is remembered, so it goes back there if Daylight UI stops laying things out.

local _, ns = ...
local DUI = DaylightUI

local Switch = {}
ns.CdmSwitch = Switch

local Data = ns.CdmData

Switch.FORMAT = 5          -- what the game writes; 4 has the same shape
Switch.MAX_LAYOUTS = 5     -- CooldownViewerLayoutManagerMixin:GetMaxLayoutsForType
Switch.ROWS = { 2, 3 }     -- Enum.CooldownViewerCategory TrackedBuff, TrackedBar
local HIDE_BY_DEFAULT = 2  -- Enum.CooldownSetSpellFlags.HideByDefault
local GAME_DEFAULT = 0     -- the layout manager's DEFAULT_LAYOUT_ID

local function codec()
    local E = C_EncodingUtil
    if type(E) == "table" and E.DecodeBase64 and E.DecompressString and E.DeserializeCBOR
        and E.SerializeCBOR and E.CompressString and E.EncodeBase64 then return E end
end

local function deflate()
    return Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate
end

-- The string's table, or nil when it isn't a layout this file knows how to write.
-- An empty string is a character with nothing saved yet.
function Switch.Decode(text)
    local E = codec()
    if not E or type(text) ~= "string" then return nil end
    if text == "" then return { Switch.FORMAT, {} } end
    local version, payload = string.match(text, "^(%d+)|(.+)$")
    if version ~= "1" then return nil end
    local t = E.DeserializeCBOR(E.DecompressString(E.DecodeBase64(payload), deflate()))
    if type(t) ~= "table" or (t[1] ~= 4 and t[1] ~= 5) then return nil end
    return t
end

function Switch.Encode(t)
    local E = codec()
    if not E then return nil end
    local text = E.EncodeBase64(E.CompressString(E.SerializeCBOR(t), deflate()))
    if type(text) ~= "string" then return nil end
    return "1|" .. text
end

-- This character's tag, class id and spec, as the game's CooldownViewerUtil makes it.
function Switch.Tag()
    local _, _, classID = UnitClass("player")
    local S = C_SpecializationInfo
    local spec = type(S) == "table" and type(S.GetSpecialization) == "function" and S.GetSpecialization() or nil
    if type(classID) ~= "number" or type(spec) ~= "number" or spec < 1 or spec > 9 then return nil end
    return classID * 10 + spec, classID, spec
end

-- Every buff the game lists for this class and spec but hides until it's switched
-- on, learned or not: { [cooldown id] = its row }. Unlearned ones are included so
-- a buff learned later has its icon the moment the game refreshes its spells.
function Switch.Hidden()
    local CV = C_CooldownViewer
    local out = {}
    if type(CV) ~= "table" or type(CV.GetCooldownViewerCategorySet) ~= "function" then return out end
    for _, row in ipairs(Switch.ROWS) do
        local ids = CV.GetCooldownViewerCategorySet(row, true)
        for _, id in ipairs(type(ids) == "table" and ids or {}) do
            local info = Data.Info(id)
            local flags = info and tonumber(info.flags) or 0
            if bit.band(flags, HIDE_BY_DEFAULT) ~= 0 then out[id] = row end
        end
    end
    return out
end

-- The layout the game uses for the tag (its GetBestLayoutForSpec): the saved pick,
-- else any layout of the tag; none when the pick is the game's default.
local function inUse(t, tag)
    local layouts = type(t[3]) == "table" and t[3][tag]
    local pick = type(t[2]) == "table" and t[2][tag] or nil
    if type(layouts) ~= "table" or pick == GAME_DEFAULT then return nil end
    if pick ~= nil and type(layouts[pick]) == "table" then return layouts[pick] end
    for _, layout in pairs(layouts) do
        if type(layout) == "table" then return layout end
    end
end

-- A new layout for the tag, picked, named the way the game names one it makes
-- when the default is first changed. Nil when the game's layouts are all used.
local function make(t, tag, name)
    local count, highest = 0, 0
    for _, layouts in pairs(type(t[3]) == "table" and t[3] or {}) do
        for id in pairs(type(layouts) == "table" and layouts or {}) do
            count = count + 1
            if type(id) == "number" and id > highest then highest = id end
        end
    end
    if count >= Switch.MAX_LAYOUTS then return nil end
    if type(t[2]) ~= "table" then t[2] = {} end
    if type(t[3]) ~= "table" then t[3] = {} end
    if type(t[4]) ~= "table" then t[4] = {} end
    if type(t[3][tag]) ~= "table" then t[3][tag] = {} end
    local id, layout = highest + 1, {}
    t[3][tag][id] = layout
    t[4][id] = name
    t[2][tag] = id
    return layout
end

-- The game's rows that hide a spell: Enum.CooldownViewerCategory HiddenSpell, HiddenAura.
local HIDDEN_ROWS = { -1, -2 }

local function plainID(s)
    return type(s) == "number" and not (issecretvalue and issecretvalue(s))
end

-- The spell ids the game's item matches an aura by (its own, override and linked).
local function itemIDs(info)
    local ids = {}
    for _, k in ipairs({ "spellID", "overrideSpellID", "overrideTooltipSpellID", "linkedSpellID" }) do
        local s = info[k]
        if plainID(s) then ids[s] = true end
    end
    local linked = info.linkedSpellIDs
    if type(linked) == "table" and not (issecrettable and issecrettable(linked)) then
        for _, s in ipairs(linked) do
            if plainID(s) then ids[s] = true end
        end
    end
    return ids
end

-- Does the buff have known auras, none of which the game's item can match? Its
-- auras are the game data's (CdmCustom.Fact) and those seen from its casts
-- (CdmOwn.AuraOf). Such a buff never lights in the game's row, so the aura holder
-- keeps it.
local function unseenAura(info)
    local C, Own = ns.CdmCustom, ns.CdmOwn
    local ids, known = itemIDs(info), false
    for s in pairs(ids) do
        local fact = C and C.Fact and C.Fact(s)
        for _, a in ipairs(fact and fact.auras or {}) do
            if ids[a] then return false end
            known = true
        end
        for a in pairs(Own and Own.AuraOf and Own.AuraOf(s) or {}) do
            if ids[a] then return false end
            known = true
        end
    end
    return known
end

-- Every game cooldown id placed in a Daylight UI layout of this class whose game row
-- is a buff row and whose aura the game's item can see: { [id] = that row }.
function Switch.Placed()
    local out = {}
    for _, entry in ipairs(Data.Profiles()) do
        local p = Data.Profile(entry.id)
        for id in pairs(p and type(p.set.pieces) == "table" and p.set.pieces or {}) do
            if type(id) == "number" then
                local info = Data.Info(id)
                local row = info and info.category
                if (row == Switch.ROWS[1] or row == Switch.ROWS[2]) and not unseenAura(info) then
                    out[id] = row
                end
            end
        end
    end
    return out
end

-- Takes each placed buff out of the hidden row the player put it in and back into
-- its own row. unhid collects { [id] = the hidden row it came from }.
local function unhide(layout, placed, added, unhid)
    local rows, n = type(layout[2]) == "table" and layout[2] or nil, 0
    if not rows then return 0 end
    for _, from in ipairs(HIDDEN_ROWS) do
        local ids = rows[from]
        if type(ids) == "table" then
            for i = #ids, 1, -1 do
                local id = ids[i]
                local row = placed[id]
                if row then
                    table.remove(ids, i)
                    if type(rows[row]) ~= "table" then rows[row] = {} end
                    table.insert(rows[row], id)
                    added[id], unhid[id] = row, from
                    n = n + 1
                end
            end
            if next(ids) == nil then rows[from] = nil end
        end
    end
    return n
end

-- Every id the layout already places somewhere, hidden rows included.
local function placed(layout)
    local set = {}
    for _, ids in pairs(type(layout[2]) == "table" and layout[2] or {}) do
        for _, id in pairs(type(ids) == "table" and ids or {}) do set[id] = true end
    end
    return set
end

local function sorted(set)
    local ids = {}
    for id in pairs(set) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

-- Puts each hidden buff the layout says nothing about in its row. A buff the
-- player moved or hid by hand has an entry already and is left alone.
local function switchOn(layout, hidden, added)
    local has, n = placed(layout), 0
    for _, id in ipairs(sorted(hidden)) do
        if not has[id] then
            local row = hidden[id]
            if type(layout[2]) ~= "table" then layout[2] = {} end
            if type(layout[2][row]) ~= "table" then layout[2][row] = {} end
            table.insert(layout[2][row], id)
            added[id] = row
            n = n + 1
        end
    end
    return n
end

-- Switches the hidden buffs on in every layout of the tag in t, making and picking
-- a layout when the tag is on the game's default, and brings placed buffs back out
-- of a hidden row. added collects { [id] = row }, unhid { [id] = hidden row }.
-- Returns how many entries were written.
function Switch.Apply(t, tag, hidden, added, name, placed, unhid)
    placed, unhid = placed or {}, unhid or {}
    if next(hidden) == nil and next(placed) == nil then return 0 end
    if not inUse(t, tag) and not make(t, tag, name) then return 0 end
    local n = 0
    for _, layout in pairs(t[3][tag]) do
        if type(layout) == "table" then
            n = n + unhide(layout, placed, added, unhid) + switchOn(layout, hidden, added)
        end
    end
    return n
end

-- Takes back what Apply added: each id still in the row it was put in, and one it
-- brought out of a hidden row goes back there. One the player has since moved
-- stays where they put it. Returns how many were taken out.
function Switch.Remove(t, tag, added, unhid)
    unhid = unhid or {}
    local layouts = type(t[3]) == "table" and t[3][tag]
    if type(layouts) ~= "table" then return 0 end
    local n = 0
    for _, layout in pairs(layouts) do
        local rows = type(layout) == "table" and layout[2]
        if type(rows) == "table" then
            local back = {}
            for row, ids in pairs(rows) do
                if type(ids) == "table" then
                    for i = #ids, 1, -1 do
                        local id = ids[i]
                        if added[id] == row then
                            table.remove(ids, i)
                            if unhid[id] then back[#back + 1] = id end
                            n = n + 1
                        end
                    end
                end
            end
            table.sort(back)
            for _, id in ipairs(back) do
                local from = unhid[id]
                if type(rows[from]) ~= "table" then rows[from] = {} end
                table.insert(rows[from], id)
            end
            local empty = {}
            for row, ids in pairs(rows) do
                if type(ids) == "table" and next(ids) == nil then empty[#empty + 1] = row end
            end
            for _, row in ipairs(empty) do rows[row] = nil end
        end
    end
    return n
end

-- The name the game gives a layout made from its default: "Warrior - Arms".
local function layoutName(classID, spec)
    local class = GetClassInfo(classID)
    local S = C_SpecializationInfo
    local specName
    if type(S.GetSpecializationInfo) == "function" then
        specName = select(2, S.GetSpecializationInfo(spec, false, false, nil, nil, nil, classID))
    end
    if type(class) ~= "string" or type(specName) ~= "string" then return "Daylight UI" end
    local form = type(COOLDOWN_VIEWER_CLASS_AND_SPEC_FORMAT) == "string" and COOLDOWN_VIEWER_CLASS_AND_SPEC_FORMAT or "%s - %s"
    return string.format(form, class, specName)
end

-- The saved data has arrived (COOLDOWN_VIEWER_DATA_LOADED). Before that an empty
-- string may only mean "not here yet", and writing then would wipe the layouts.
local arrived, started = false, false

-- Only while Daylight UI lays the Cooldown Manager out and keeps the game's icons
-- nobody placed out of sight. A player who shows those, or uses the game's own
-- layout on this character, would get a row of buff icons they never asked for.
function Switch.Wanted()
    return ns.db ~= nil and ns.db.cooldowns == true and Data.Switch("on") and Data.Switch("hideUnplaced")
end

-- Reads the game's layout, switches the hidden buffs on (or, when they aren't
-- wanted any more, takes its own additions back out) and writes it only when
-- something changed. Returns how many entries changed, nil when it couldn't look.
function Switch.Run()
    local CV = C_CooldownViewer
    if not codec() or type(CV) ~= "table" or type(CV.GetLayoutData) ~= "function" or type(CV.SetLayoutData) ~= "function" then return nil end
    local text = CV.GetLayoutData()
    if type(text) ~= "string" or (text == "" and not arrived) then return nil end
    local t = Switch.Decode(text)
    local tag, classID, spec = Switch.Tag()
    if not t or not tag then return nil end
    local char = DUI.DB.Character()
    local n
    if Switch.Wanted() then
        local added = type(char.cdmSwitched) == "table" and char.cdmSwitched or {}
        local unhid = type(char.cdmUnhid) == "table" and char.cdmUnhid or {}
        local placed = Switch.Placed()
        -- A buff brought out of a hidden row whose info fails the check goes back
        -- there. Its record goes only once it was moved in this spec's layout.
        local back = 0
        for id, from in pairs(unhid) do
            if not placed[id] and Data.Info(id) then
                local moved = Switch.Remove(t, tag, { [id] = added[id] }, { [id] = from })
                if moved > 0 then added[id], unhid[id], back = nil, nil, back + moved end
            end
        end
        n = back + Switch.Apply(t, tag, Switch.Hidden(), added, layoutName(classID, spec), placed, unhid)
        if n > 0 then
            char.cdmSwitched = added
            char.cdmUnhid = next(unhid) ~= nil and unhid or nil
        end
    else
        if type(char.cdmSwitched) ~= "table" then return 0 end
        n = Switch.Remove(t, tag, char.cdmSwitched, char.cdmUnhid)
        char.cdmSwitched, char.cdmUnhid = nil, nil
    end
    if n == 0 then return 0 end
    local new = Switch.Encode(t)
    if not new then return nil end
    CV.SetLayoutData(new)
    return n
end

-- From the module's start at login: the settings can be read from here on.
function Switch.Start()
    started = true
    DUI.SafeCall(Switch.Run)
end

DUI.RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED", function()
    arrived = true
    if started then DUI.SafeCall(Switch.Run) end
end)

DUI.RegisterEvent("PLAYER_LOGOUT", function()
    if started then DUI.SafeCall(Switch.Run) end
end)
