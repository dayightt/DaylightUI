-- A Cooldown Manager group's lead frame. Positions: UIParent units from screen center, y up.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local isSecret = DUI.IsSecret
local Data = ns.CdmData

local Tether = {}
ns.CdmTether = Tether

Tether.NONE = ""             -- "Where you put it"
Tether.LOOP_DEPTH = 20

-- Leads that stay on screen while their area is off: key -> { module, setting path }.
Tether.OFF_SETTINGS = {
    ["unitframes.personal"] = { "UnitFrames", "personal.enabled" },
}

local function isLeadPoint(value)
    return type(value) == "string" and DUI.Movers.ANCHOR_SIGN[value] ~= nil
end

-- Malformed reads as the default.
local function savedChainValueOrDefault(set, id, key)
    local value = Data.SavedChainValue(key, Data.ChainValue(set, id, key))
    if value == nil then return Data.CHAIN[key] end
    return value
end

-- The offset is of the root piece's top-left from the lead's point.
function Tether.Of(set, id)
    local key = Data.ChainValue(set, id, "tether")
    if not Data.IsFrameKey(key) then return nil end
    return key, savedChainValueOrDefault(set, id, "tetherX"), savedChainValueOrDefault(set, id, "tetherY"),
        savedChainValueOrDefault(set, id, "tetherAt")
end

-- Plugin frames may error, and restricted ones (nameplates at login) do when asked.
local function ask(frame, method, ...)
    return pcall(frame[method], frame, ...)
end

local function isRestricted(frame)
    if type(frame.IsAnchoringRestricted) ~= "function" then return false end
    local ok, restricted = ask(frame, "IsAnchoringRestricted")
    return not ok or restricted == true
end

-- 0 when a plugin's frame can't say.
local function pointCount(frame)
    if type(frame.GetNumPoints) ~= "function" then return 0 end
    local ok, count = ask(frame, "GetNumPoints")
    if not ok or isSecret(count) or type(count) ~= "number" then return 0 end
    return count
end

-- Nil when a plugin's frame errors or the game keeps the anchoring secret.
local function readPoint(frame, index)
    local ok, point, relative, relativePoint, offsetX, offsetY = ask(frame, "GetPoint", index)
    if not ok or isSecret(point) or isSecret(relative) or isSecret(relativePoint)
        or isSecret(offsetX) or isSecret(offsetY) then
        return nil
    end
    return point, relative
end

local function isCdmFrame(frame)
    local rows = ns.CdmRows
    return rows ~= nil and rows.IsCdmFrame(frame)
end

-- A group attached to a frame that hangs off the layout would hang off itself.
local visited = {}
local function reachesCdm(frame, depth)
    if depth > Tether.LOOP_DEPTH or visited[frame] then return false end
    visited[frame] = true
    if isCdmFrame(frame) then return true end
    if isRestricted(frame) then return false end
    for index = 1, pointCount(frame) do
        local _, relative = readPoint(frame, index)
        if type(relative) == "table" and relative ~= UIParent and reachesCdm(relative, depth + 1) then
            return true
        end
    end
    return false
end

local function isSwitchedOff(key, entry)
    local setting = Tether.OFF_SETTINGS[key]
    if setting and DUI:Get(setting[1], setting[2]) ~= true then return true end
    return entry.active ~= nil and not entry.active()
end

local function workOutState(key)
    local entry = DUI.Movers.Get(key)
    if not entry or entry.proxy or not entry.frame then return "missing" end
    wipe(visited)
    local loops = reachesCdm(entry.frame, 1)
    wipe(visited)
    if loops then return "loop" end
    if isSwitchedOff(key, entry) then return "off" end
    return "ready"
end

-- Cached until Tether.Stale. "off": area switched off, but the frame is still there to follow.
local stateCache = {}
function Tether.State(key)
    local state = stateCache[key]
    if state then return state end
    if not Data.IsFrameKey(key) then return "missing" end
    state = workOutState(key)
    stateCache[key] = state
    return state
end

-- Clears the cached lead states.
function Tether.Stale()
    wipe(stateCache)
end

-- Works the cached lead states out again. True when any of them changed.
function Tether.Restate()
    local changed = false
    for key, state in pairs(stateCache) do
        local now = workOutState(key)
        if now ~= state then
            stateCache[key] = now
            changed = true
        end
    end
    return changed
end

-- Its single readable point, else CENTER.
local function hangPointOf(frame)
    if isRestricted(frame) or pointCount(frame) ~= 1 then return "CENTER" end
    local point = readPoint(frame, 1)
    if isLeadPoint(point) then return point end
    return "CENTER"
end

function Tether.Lead(key)
    local state = Tether.State(key)
    if state ~= "ready" and state ~= "off" then return nil end
    local frame = DUI.Movers.Get(key).frame
    return frame, hangPointOf(frame)
end

-- Whether a group can be anchored straight to its lead. Never a plugin's frame: it
-- could be hung off the layout later, or turn protected.
function Tether.Hangable(key, frame)
    if key:find("^plugin%.") or isRestricted(frame) then return false end
    local ok, protected = ask(frame, "IsProtected")
    return ok and not protected
end

local function measurableLead(key, at)
    local leadFrame, hang = Tether.Lead(key)
    if not (leadFrame and Tether.PointAt(leadFrame, at)) then return nil end
    return leadFrame, hang
end

-- Nil when the group is measured from screen center.
function Tether.MeasuredFromLead(set, id)
    local key, _, _, at = Tether.Of(set, Data.Root(set, id))
    local leadFrame = key and measurableLead(key, at)
    if not leadFrame then return nil end
    return key, leadFrame, at
end

local HEADING_PREFIX = "head:"

-- Written out as L["..."] so the language files pick them up.
local function unavailableNameFormat(state)
    if state == "off" then return L["%s (off)"] end
    if state == "missing" then return L["%s (not here)"] end
    return nil
end

local function leadLabel(key)
    local entry = DUI.Movers.Get(key)
    if entry and entry.label then return L[entry.label] end
    return key
end
Tether.Label = leadLabel

-- A lead that would loop shows its plain name.
function Tether.Name(key)
    if not Data.IsFrameKey(key) then return L["Where you put it"] end
    local nameFormat = unavailableNameFormat(Tether.State(key))
    if nameFormat then return nameFormat:format(leadLabel(key)) end
    return leadLabel(key)
end

local function anchorPointLabel(point)
    local labels = DUI.Movers.AnchorLabels()
    return labels[point] or labels.CENTER
end

-- The card's X/Y tooltip.
function Tether.MeasuredFrom(set, id)
    local key, _, _, at = Tether.Of(set, Data.Root(set, id))
    if not key then return L["Measured from the middle of the screen."] end
    if measurableLead(key, at) then
        return L["Measured from %s, at its anchor point (%s). If that frame takes the group past a screen edge, the group stops at the edge and comes back when it can."]
            :format(leadLabel(key), anchorPointLabel(at))
    end
    if Tether.State(key) == "missing" then
        return L["%s isn't here, so this is measured from the middle of the screen. The group follows it again once it's back."]
            :format(leadLabel(key))
    end
    return L["Measured from the middle of the screen."]
end

local function isListedLead(key, entry)
    if entry.proxy or isCdmFrame(entry.frame) then return false end
    return key:find("^cdm%.") == nil
end

-- One per area id.
local function areasInOrder()
    local areas, seen = {}, {}
    for _, area in ipairs(DUI.Movers.AREAS) do
        if area.label and not seen[area.id] then
            seen[area.id] = true
            areas[#areas + 1] = { id = area.id, label = area.label, keys = {} }
        end
    end
    return areas
end

local function areaWithId(areas, id)
    for _, area in ipairs(areas) do
        if area.id == id then return area end
    end
    return areas[#areas]
end

local function sortByLabel(keys)
    local labelOf = {}
    for _, key in ipairs(keys) do labelOf[key] = leadLabel(key) end
    table.sort(keys, function(a, b)
        if labelOf[a] ~= labelOf[b] then return labelOf[a] < labelOf[b] end
        return a < b
    end)
end

-- For W.dropdown. A saved lead not here for this character still shows. New tables each call.
function Tether.Choices(savedKey)
    local values, keys, titles = { [Tether.NONE] = L["Where you put it"] }, { Tether.NONE }, {}
    local areas, listed = areasInOrder(), {}
    for _, key in ipairs(DUI.Movers.Keys()) do
        local entry = DUI.Movers.Get(key)
        if isListedLead(key, entry) then
            listed[key] = true
            local keysOfArea = areaWithId(areas, DUI.Movers.AreaOf(key)).keys
            keysOfArea[#keysOfArea + 1] = key
        end
    end
    if Data.IsFrameKey(savedKey) and not listed[savedKey] then
        local keysOfArea = areaWithId(areas, DUI.Movers.AreaOf(savedKey)).keys
        keysOfArea[#keysOfArea + 1] = savedKey
    end
    for _, area in ipairs(areas) do
        if #area.keys > 0 then
            local heading = HEADING_PREFIX .. area.id
            keys[#keys + 1], values[heading], titles[heading] = heading, L[area.label], true
            sortByLabel(area.keys)
            for _, key in ipairs(area.keys) do
                keys[#keys + 1], values[key] = key, Tether.Name(key)
            end
        end
    end
    return values, keys, titles
end

local function isPlainNumber(value)
    return not isSecret(value) and type(value) == "number"
end

-- Nil when a plugin's frame errors, or the value is unplaced or secret.
local function readNumber(frame, method)
    local ok, value = ask(frame, method)
    if ok and isPlainNumber(value) then return value end
    return nil
end

local function readCenter(frame)
    local ok, x, y = ask(frame, "GetCenter")
    if ok and isPlainNumber(x) and isPlainNumber(y) then return x, y end
    return nil
end

-- Center from bottom-left. Hidden frames keep their rectangle.
local function readRectangle(frame)
    local centerX, centerY = readCenter(frame)
    local width, height = readNumber(frame, "GetWidth"), readNumber(frame, "GetHeight")
    local scale = readNumber(frame, "GetEffectiveScale")
    if not (centerX and width and height and scale) then return nil end
    local toUIParent = scale / UIParent:GetEffectiveScale()
    return centerX * toUIParent, centerY * toUIParent, width * toUIParent, height * toUIParent
end

-- Makes no table: the open editor calls it every frame.
function Tether.PointAt(frame, point)
    local centerX, centerY, width, height = readRectangle(frame)
    if not centerX then return nil end
    return DUI.Movers.PointOf(point,
        centerX - UIParent:GetWidth() / 2, centerY - UIParent:GetHeight() / 2, width, height)
end

-- Editor only, out of combat. A group's saved spot is its first piece's top-left (p.x, p.y).

local function wholePixel(value) return math.floor(value + 0.5) end

-- So an edit that changes nothing isn't counted as a layout write.
local function setChainValueIfChanged(set, root, key, value)
    local kept = Data.SavedChainValue(key, value)
    if kept == nil or kept == savedChainValueOrDefault(set, root, key) then return false end
    return Data.SetChainValue(set, root, key, kept)
end

local function attachedGroup(set, root)
    local p = set.pieces[root]
    if not p or Data.Root(set, root) ~= root then return nil end
    local key, offsetX, offsetY, at = Tether.Of(set, root)
    if not key then return nil end
    local leadFrame, hang = measurableLead(key, at)
    if not leadFrame then return nil end
    return p, offsetX, offsetY, at, leadFrame, hang
end

local function spotAtLeadPoint(set, root)
    local p, offsetX, offsetY, at, leadFrame = attachedGroup(set, root)
    if not p then return nil end
    local pointX, pointY = Tether.PointAt(leadFrame, at)
    if not pointX then return nil end
    return wholePixel(pointX + offsetX), wholePixel(pointY + offsetY)
end

local function followLeadPoint(set, root)
    local x, y = spotAtLeadPoint(set, root)
    if not x then return false end
    local p = set.pieces[root]
    local moved = p.x ~= x or p.y ~= y
    p.x, p.y = x, y
    return moved
end

-- Writes no layout version: the spot it sets is already what's on screen.
function Tether.Follow(set, draggedRoot)
    local moved = false
    for root in pairs(set.chains) do
        if root ~= draggedRoot and followLeadPoint(set, root) then moved = true end
    end
    return moved
end

-- The data layer rounds and limits the offset.
function Tether.MoveOffset(set, root, x, y)
    if Data.SavedChainValue("tetherX", x) == nil or Data.SavedChainValue("tetherY", y) == nil then return false end
    local changedX = setChainValueIfChanged(set, root, "tetherX", x)
    local changedY = setChainValueIfChanged(set, root, "tetherY", y)
    Tether.Follow(set)
    return true, changedX or changedY
end

local function offsetFromLeadPoint(set, root, leadFrame, hang)
    local pointX, pointY = Tether.PointAt(leadFrame, hang)
    if not pointX then return nil end
    local p = set.pieces[root]
    return p.x - pointX, p.y - pointY
end

local function saveOffset(set, root, hang, offsetX, offsetY)
    setChainValueIfChanged(set, root, "tetherAt", hang)
    setChainValueIfChanged(set, root, "tetherX", offsetX)
    setChainValueIfChanged(set, root, "tetherY", offsetY)
end

local function measureOffset(set, root, leadFrame, hang)
    local offsetX, offsetY = offsetFromLeadPoint(set, root, leadFrame, hang)
    if offsetX then saveOffset(set, root, hang, offsetX, offsetY) end
end

local function isAtSavedOffset(set, root)
    local p, x, y = set.pieces[root], spotAtLeadPoint(set, root)
    return p.x == x and p.y == y
end

-- Measured again, a whole-pixel spot off a lead point on a half pixel comes out a
-- pixel further each time, so a group still where its offset puts it keeps it.
local function rebaseOffset(set, root)
    local p, _, _, at, leadFrame, hang = attachedGroup(set, root)
    if not p or (at == hang and isAtSavedOffset(set, root)) then return end
    measureOffset(set, root, leadFrame, hang)
end

-- After an edit moved spots, so groups stay where the edit put them.
function Tether.Rebase(set)
    for root in pairs(set.chains) do rebaseOffset(set, root) end
end

local function detach(set, root)
    setChainValueIfChanged(set, root, "tether", false)
    setChainValueIfChanged(set, root, "tetherAt", Data.CHAIN.tetherAt)
    setChainValueIfChanged(set, root, "tetherX", Data.CHAIN.tetherX)
    setChainValueIfChanged(set, root, "tetherY", Data.CHAIN.tetherY)
end

local function hasArea(frame)
    local width, height = readNumber(frame, "GetWidth"), readNumber(frame, "GetHeight")
    return width ~= nil and height ~= nil and width > 0 and height > 0
end
Tether.HasArea = hasArea

local function measureAttachment(set, root, key)
    local leadFrame, hang = Tether.Lead(key)
    if not (leadFrame and hasArea(leadFrame)) then return nil end
    local offsetX, offsetY = offsetFromLeadPoint(set, root, leadFrame, hang)
    if not offsetX then return nil end
    return hang, offsetX, offsetY
end

-- Keeps the group in place. Refuses a lead it can't measure now: the group would jump once it appears.
function Tether.Attach(set, id, key)
    if key ~= Tether.NONE and not Data.IsFrameKey(key) then return false end
    local root = Data.Root(set, id)
    if not set.pieces[root] then return false end
    if key == Tether.NONE then key = false end
    if key == (Tether.Of(set, root) or false) then return false end
    if not key then
        detach(set, root)
        return true
    end
    local hang, offsetX, offsetY = measureAttachment(set, root, key)
    if not hang then return false end
    if not Data.SetChainValue(set, root, "tether", key) then return false end
    saveOffset(set, root, hang, offsetX, offsetY)
    Tether.Stale()
    return true
end
