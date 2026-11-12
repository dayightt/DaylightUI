-- Reads and writes the game's talent loadout string, ported from
-- Blizzard_ClassTalentImportExport.lua and ExportUtil.lua. It's a bit stream,
-- least significant bit first, six bits per base64 character (A-Z a-z 0-9 + /):
--   header: version 8, spec id 16, tree hash 16 x 8 (all zero = skip check)
--   then per node of C_Traits.GetTreeNodes(treeID), in that order:
--     selected 1 [purchased 1 [partial 1 [ranks 6] choice 1 [entry 2]]]
-- Values are small, so plain arithmetic is enough; no bit library needed.

local _, DUI = ...
DUI.Book = DUI.Book or {}   -- the book window's own namespace
local ns = DUI.Book

local LS = {}
ns.LoadoutString = LS

local CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local VALUE = {}
for i = 1, #CHARS do VALUE[string.sub(CHARS, i, i)] = i - 1 end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if ok then return a end
end

local function traits() return type(C_Traits) == "table" and C_Traits or nil end

-- On Forever a config has a single tree; the three class trees are display groups in it.
function LS.TreeOf(configID)
    local C = traits()
    local info = C and configID and call(C.GetConfigInfo, configID)
    return type(info) == "table" and type(info.treeIDs) == "table" and info.treeIDs[1] or nil
end

function LS.Version()
    local C = traits()
    local v = C and call(C.GetLoadoutSerializationVersion)
    return type(v) == "number" and v or nil
end

-- ---------------------------------------------------------------------
-- The bit stream
-- ---------------------------------------------------------------------

local function writer()
    local w = { out = {}, cur = 0, used = 0 }
    function w:Add(width, value)
        for _ = 1, width do
            local b = value % 2
            value = (value - b) / 2
            self.cur = self.cur + b * 2 ^ self.used
            self.used = self.used + 1
            if self.used == 6 then
                self.out[#self.out + 1] = string.sub(CHARS, self.cur + 1, self.cur + 1)
                self.cur, self.used = 0, 0
            end
        end
    end
    function w:String()
        if self.used > 0 then return table.concat(self.out) .. string.sub(CHARS, self.cur + 1, self.cur + 1) end
        return table.concat(self.out)
    end
    return w
end

local function reader(text)
    local vals = {}
    for i = 1, #text do
        local v = VALUE[string.sub(text, i, i)]
        if not v then return nil end
        vals[i] = v
    end
    local r = { vals = vals, i = 1, bit = 0 }
    function r:Bits() return #self.vals * 6 end
    -- Returns nil once the stream runs out, like the game's ExtractValue.
    function r:Take(width)
        local value = 0
        for k = 0, width - 1 do
            local v = self.vals[self.i]
            if not v then return nil end
            local b = math.floor(v / 2 ^ self.bit) % 2
            value = value + b * 2 ^ k
            self.bit = self.bit + 1
            if self.bit == 6 then self.i, self.bit = self.i + 1, 0 end
        end
        return value
    end
    return r
end

-- ---------------------------------------------------------------------
-- Writing, after the game's WriteLoadoutContent. Only used when the client
-- lacks C_Traits.GenerateImportString.
-- ---------------------------------------------------------------------

local function entryIndex(n)
    local active = type(n.activeEntry) == "table" and n.activeEntry.entryID
    for i, id in ipairs(type(n.entryIDs) == "table" and n.entryIDs or {}) do
        if id == active then return i end
    end
    return 1
end

local function isChoice(n)
    local T = type(Enum) == "table" and Enum.TraitNodeType
    return T ~= nil and (n.type == T.Selection or n.type == T.SubTreeSelection)
end

function LS.Encode(configID)
    local C = traits()
    local treeID = LS.TreeOf(configID)
    if not (C and treeID) then return nil end
    local w = writer()
    local spec = type(PlayerUtil) == "table" and call(PlayerUtil.GetCurrentSpecID)
    w:Add(8, LS.Version() or 0)
    w:Add(16, type(spec) == "number" and spec or 0)
    local hash = call(C.GetTreeHash, treeID)
    for i = 1, 16 do w:Add(8, type(hash) == "table" and type(hash[i]) == "number" and hash[i] or 0) end
    for _, id in ipairs(call(C.GetTreeNodes, treeID) or {}) do
        local n = call(C.GetNodeInfo, configID, id) or {}
        local bought = type(n.ranksPurchased) == "number" and n.ranksPurchased or 0
        local active = type(n.activeRank) == "number" and n.activeRank or bought
        local granted = active - bought > 0
        if granted or bought > 0 then
            w:Add(1, 1)
            w:Add(1, bought > 0 and 1 or 0)
            if bought > 0 then
                local partial = bought ~= n.maxRanks
                w:Add(1, partial and 1 or 0)
                if partial then w:Add(6, bought) end
                local choice = isChoice(n)
                w:Add(1, choice and 1 or 0)
                if choice then w:Add(2, entryIndex(n) - 1) end
            end
        else
            w:Add(1, 0)
        end
    end
    return w:String()
end

-- ---------------------------------------------------------------------
-- Reading, after the game's ReadLoadoutHeader and ReadLoadoutContent
-- ---------------------------------------------------------------------

-- Returns { ranks = { [nodeID] = ranks bought } }, or nil and an error
-- message (the game's own strings where available).
function LS.Decode(text, configID)
    local C = traits()
    local treeID = LS.TreeOf(configID)
    if not (C and treeID) then return nil, LOADOUT_ERROR_IMPORT_FAILED or "Couldn't read the talents." end
    text = type(text) == "string" and string.gsub(text, "%s", "") or ""
    local bad = LOADOUT_ERROR_BAD_STRING or "That isn't a talent string."
    local r = text ~= "" and reader(text)
    if not r or r:Bits() < 8 + 16 + 128 then return nil, bad end
    local version = r:Take(8)
    r:Take(16)   -- spec id, ignored: every set shares the class's one tree
    for _ = 1, 16 do r:Take(8) end   -- tree hash, ignored: PurchaseRank validates each rank anyway
    local want = LS.Version()
    if want and version ~= want then
        return nil, LOADOUT_ERROR_SERIALIZATION_VERSION_MISMATCH or "That talent string is from another game version."
    end
    local out = { ranks = {} }
    for _, id in ipairs(call(C.GetTreeNodes, treeID) or {}) do
        local selected = r:Take(1)
        if selected == nil then return nil, bad end
        if selected == 1 then
            local bought = r:Take(1) == 1
            if bought then
                local n = call(C.GetNodeInfo, configID, id) or {}
                local ranks = type(n.maxRanks) == "number" and n.maxRanks or 1
                if r:Take(1) == 1 then ranks = r:Take(6) or 0 end
                if r:Take(1) == 1 then r:Take(2) end   -- choice entry; classic trees have no choice nodes
                if ranks > 0 then out.ranks[id] = ranks end
            end
        end
    end
    return out
end
