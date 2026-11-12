-- Quests an NPC has for the player, in its tooltip (mapQuests.tooltip, on with
-- Questie). A "?" line for each quest ready to turn in to them, a "!" line for each
-- one available, then one for each quest in progress that ends with them (with its
-- progress, drawn like the NPC window does). Name and level in the quest log's
-- difficulty color, type (Elite, Dungeon, Repeatable...) in tan. Available quests
-- come from Questie's own list (Bridge.NpcQuests, not worked out here); quests
-- ending with them come from QuestieDB's finishedBy for quests in the log.
-- Questie's own NPC tooltip lines step aside meanwhile (QuestieAside in the core).
-- Also repaints the game's own quest lines on mobs and items in the addon's text
-- colors (GT.PaintQuestLines), always, even with the Tooltip module off.

local _, ns = ...
local DUI = DaylightUI
local Style, L = DUI.Style, DUI.L

local GT = {
    MAX = 6,        -- quest lines before "And N more"
    ICON = 14,      -- size of the ! and ? at the start of a line, px
    -- The game's map atlases (quest offer pin, turn-in pin). ART_ELSE is used when the
    -- client doesn't have the first.
    ART = { ["!"] = "QuestNormal", ["?"] = "QuestTurnin" },
    ART_ELSE = { ["?"] = "UI-QuestIcon-TurnIn-Normal" },
}
ns.GiverTips = GT

local mod, hooked

function GT.On()
    local n = mod and mod.db and mod.db.mapQuests
    return n ~= nil and n.tooltip ~= false and ns.Bridge ~= nil and ns.Bridge.Loaded()
end

local function plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function call(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(f, ...)
    if ok then return a, b, c, d, e end
end
local function QL(name) return C_QuestLog and C_QuestLog[name] end

-- An NPC's id from its GUID ("Creature-0-1-2-3-<npcID>-<spawn>"). nil for players,
-- pets, objects and secret GUIDs.
function GT.NpcID(guid)
    guid = plain(guid)
    if type(guid) ~= "string" then return nil end
    local id = guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    return id and tonumber(id) or nil
end

-- An NPC's quests

local function quest(id, key) return ns.Spots.Quest(id, key) end

-- Too low to give experience, i.e. below the game's gray level.
function GT.Low(level)
    local you = UnitLevel("player") or 1
    if type(level) ~= "number" or level <= 0 then return false end
    local range = UnitQuestTrivialLevelRange and UnitQuestTrivialLevelRange("player")
    if type(range) ~= "number" then range = 5 end
    return you - level > range
end

local function ready(id)
    local done = call(QL("ReadyForTurnIn"), id)
    if done == nil then done = call(QL("IsComplete"), id) end
    return done == true
end

-- Turn-ins first, then available quests, then ones in progress.
local RANK = { ["?"] = 1, ["!"] = 2, ["~"] = 3 }
local function order(a, b)
    if a.kind ~= b.kind then return (RANK[a.kind] or 9) < (RANK[b.kind] or 9) end
    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
    return tostring(a.name) < tostring(b.name)
end

-- Everything for one NPC: { { kind, quest, name, level, low, rep }, ... }, sorted
-- by kind (RANK), then level.
function GT.For(npc)
    local out = {}
    for _, id in ipairs(ns.Bridge.NpcQuests(npc) or {}) do
        if not call(QL("GetLogIndexForQuestID"), id) then
            local lv = quest(id, "questLevel")
            lv = type(lv) == "number" and lv or 0
            local flags = quest(id, "specialFlags")
            local name = quest(id, "name")
            out[#out + 1] = { kind = "!", quest = id, name = type(name) == "string" and name or nil, level = lv,
                              low = GT.Low(lv), rep = type(flags) == "number" and flags % 2 == 1 }
        end
    end
    local n = call(QL("GetNumQuestLogEntries"))
    for i = 1, (type(n) == "number" and n or 0) do
        local info = call(QL("GetInfo"), i)
        local id = type(info) == "table" and not info.isHeader and info.questID
        if type(id) == "number" and id > 0 then
            for _, eid in ipairs(ns.Spots.Enders(id)) do
                if eid == npc then
                    out[#out + 1] = { kind = ready(id) and "?" or "~", quest = id,
                                      name = call(QL("GetTitleForQuestID"), id) or info.title,
                                      level = type(info.level) == "number" and info.level or 0 }
                    break
                end
            end
        end
    end
    table.sort(out, order)
    return out
end

-- Tooltip lines

-- A mark's art: GT.ART, or GT.ART_ELSE when the client lacks that atlas.
function GT.Art(kind)
    local art, alt = GT.ART[kind], GT.ART_ELSE[kind]
    local T = _G.C_Texture
    if alt and type(T) == "table" and type(T.GetAtlasInfo) == "function" and not T.GetAtlasInfo(art) then
        return alt
    end
    return art
end

-- Quest type in the game's own words: Elite, Dungeon, Raid, PvP, Repeatable.
function GT.Kind(q)
    local kind = q.kind == "!" and ns.Data and ns.Data.Tag and ns.Data.Tag(q.quest)
    local word = kind and ns.Look and ns.Look.TAG_WORDS[kind]
    if word then return word() end
    if q.rep then return L["Repeatable"] end
    return nil
end

-- The NPC window's in-progress icon (Npc/Window.lua, `Window.BUSY`), in its color.
function GT.BusyIcon()
    local c = DUI.Npc.Window.BUSY
    return string.format("|T%s:%d:%d:0:0:64:64:0:64:0:64:%d:%d:%d|t ", DUI.MEDIA .. "quest-progress.png", GT.ICON, GT.ICON,
        math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- A quest's counts summed (have, need); nil when there's nothing to count.
function GT.Progress(id)
    local have, need = 0, 0
    for _, o in ipairs(call(QL("GetQuestObjectives"), id) or {}) do
        if type(o) == "table" and type(o.numRequired) == "number" and o.numRequired > 0 then
            have, need = have + math.min(o.numFulfilled or 0, o.numRequired), need + o.numRequired
        end
    end
    if need > 0 then return have, need end
end

function GT.Add(tip, list)
    if #list == 0 then return end
    local INK, hex = Style.INK, DUI.Win.Parts.Hex
    tip:AddLine(" ")
    for i, q in ipairs(list) do
        if i > GT.MAX then
            local c = INK.LABEL
            tip:AddLine(string.format(L["And %d more"], #list - GT.MAX), c[1], c[2], c[3])
            break
        end
        local icon, c
        if q.kind == "~" then
            icon, c = GT.BusyIcon(), DUI.Npc.Window.BUSY
        else
            icon = string.format("|A:%s:%d:%d|a ", GT.Art(q.kind), GT.ICON, GT.ICON)
            c = DUI.Npc.Data.QuestColor(q.quest, q.level, q.low)
        end
        local right, rc
        if q.kind == "~" then
            local have, need = GT.Progress(q.quest)
            right = need and (have .. "/" .. need) or L["In progress"]
            rc = need and DUI.Tips.Progress(have, need) or INK.LABEL
        elseif q.kind == "?" then
            right, rc = L["Ready"], INK.GOOD
        else
            local kind = GT.Kind(q)
            right = (q.level or 0) > 0 and tostring(q.level) or ""
            if kind then right = hex(INK.LABEL) .. kind .. "|r" .. (right ~= "" and "  " .. right or "") end
            rc = c
        end
        tip:AddDoubleLine(icon .. (q.name or "?"), right, c[1], c[2], c[3], rc[1], rc[2], rc[3])
    end
    -- Refit to the new lines, but only if it's already showing (showing it from here
    -- would run its show handlers tainted). Same as Tooltip.lua.
    if tip.Show and tip:IsShown() then tip:Show() end
end

-- The game's quest lines on mobs and items

-- Quest name in the quest log's difficulty color, the objective in soft white, its
-- count in the accent (good color when done). Goes by the data's line types (data
-- line i = tooltip line i); a line that reads secret is left alone.
local function lineText(name, i)
    local fs = _G[name .. "TextLeft" .. i]
    local text = type(fs) == "table" and fs.GetText and plain(fs:GetText())
    if type(text) ~= "string" or text == "" or text:find("|c", 1, true) then return nil end
    return fs, text
end

function GT.QuestByName(title)
    local n = call(QL("GetNumQuestLogEntries"))
    for i = 1, (type(n) == "number" and n or 0) do
        local info = call(QL("GetInfo"), i)
        if type(info) == "table" and not info.isHeader and info.title == title then return info.questID, info.level end
    end
end

function GT.PaintQuestLines(tip, data)
    local kinds = Enum and Enum.TooltipDataLineType
    local lines = type(data) == "table" and type(data.lines) == "table" and data.lines
    local name = tip.GetName and tip:GetName()
    if not (kinds and lines and type(name) == "string") then return end
    local INK, hex = Style.INK, DUI.Win.Parts.Hex
    for i, line in ipairs(lines) do
        local kind = type(line) == "table" and plain(line.type)
        local fs, text
        if kind == kinds.QuestTitle or kind == kinds.QuestObjective or kind == kinds.QuestPlayer then
            fs, text = lineText(name, i)
        end
        if fs and kind == kinds.QuestTitle then
            local id, level = GT.QuestByName(text)
            local c = id and DUI.Npc.Data.QuestColor(id, level) or INK.VALUE
            fs:SetTextColor(c[1], c[2], c[3])
        elseif fs and kind == kinds.QuestPlayer then
            fs:SetTextColor(INK.LABEL[1], INK.LABEL[2], INK.LABEL[3])
        elseif fs then
            local count = text:match("%d+%s*/%s*%d+")
            if count then
                local pop = plain(line.completed) == true and INK.GOOD or { Style.Accent() }
                local a, b = text:find(count, 1, true)
                text = text:sub(1, a - 1) .. hex(pop) .. count .. "|r" .. text:sub(b + 1)
                fs:SetText(text)
            end
            fs:SetTextColor(INK.TEXT[1], INK.TEXT[2], INK.TEXT[3])
        end
    end
end

local function paint(tip, data)
    if tip == GameTooltip then DUI.SafeCall(GT.PaintQuestLines, tip, data) end
end

function GT.OnUnit(tip, data)
    if tip ~= GameTooltip then return end
    GT.PaintQuestLines(tip, data)
    if not GT.On() then return end
    local guid = type(data) == "table" and plain(data.guid) or nil
    if type(guid) ~= "string" then
        local ok, _, unit = pcall(tip.GetUnit, tip)
        unit = ok and plain(unit) or nil
        if type(unit) == "string" then guid = call(UnitGUID, unit) end
    end
    local npc = GT.NpcID(guid)
    if npc then GT.Add(tip, GT.For(npc)) end
end

function GT.Enable(m)
    mod = m
    local TDP = TooltipDataProcessor
    local types = Enum and Enum.TooltipDataType
    if hooked or type(TDP) ~= "table" or type(TDP.AddTooltipPostCall) ~= "function" or not types then return end
    hooked = true
    if types.Unit then TDP.AddTooltipPostCall(types.Unit, function(tip, data) DUI.SafeCall(GT.OnUnit, tip, data) end) end
    if types.Item then TDP.AddTooltipPostCall(types.Item, paint) end
end
