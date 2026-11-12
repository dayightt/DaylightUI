-- Keeps chat across a /reload, and across a logout when "Keep chat after logging
-- out" is on. At logout the newest lines of each window are saved per character,
-- then restored at login above a divider: "before reload" if it was within a
-- couple of minutes, else "last session" with the save time.
-- Lines are only read with GetMessageInfo and re-added with AddMessage, like any
-- addon printing to chat; nothing is hooked. Secret lines are skipped, and so
-- are lines with a Battle.net name, which can't be shown again after a reload.
-- The combat log keeps its own history.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local History = {}
ns.History = History

History.MAX_AGE = 120 -- saved longer ago than this (seconds) means a logout, not a reload
History.LABEL = DUI.Win.Parts.Hex(DUI.Style.INK.LABEL) -- divider labels
History.DIVIDER = History.LABEL .. "-- " .. L["before reload"] .. " --|r"

-- Divider lines, never saved themselves. The "-- ... --" frame is the same in
-- every language. Older saved history may still hold the old gray (808080).
History.DIVIDER_PATTERN = "^|cff(%x%x%x%x%x%x)%-%- .* %-%-|r$"
History.DIVIDER_COLORS = { c2b59e = true, ["808080"] = true }

-- Divider after a logout: the save time, with the day if it wasn't today.
function History.SessionDivider(savedAt)
    local sameDay = date("%Y%m%d", savedAt) == date("%Y%m%d")
    local when = sameDay and date("%H:%M", savedAt) or date("%d %b %H:%M", savedAt)
    return History.LABEL .. "-- " .. string.format(L["last session, %s"], when) .. " --|r"
end

local function secret(v) return issecretvalue and issecretvalue(v) end

-- Chat windows 1 to NUM_CHAT_WINDOWS, minus the combat log.
function History.Windows()
    local out = {}
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local name = "ChatFrame" .. i
        local cf = _G[name]
        if type(cf) == "table" and cf ~= _G.ChatFrame2 then out[#out + 1] = { name = name, cf = cf } end
    end
    return out
end

-- A window's newest lines (at most max), oldest first, as { text, r, g, b }.
function History.Read(cf, max)
    local out = {}
    if type(cf.GetNumMessages) ~= "function" or type(cf.GetMessageInfo) ~= "function" then return out end
    local n = cf:GetNumMessages() or 0
    for i = n, 1, -1 do
        if #out >= max then break end
        local text, r, g, b = cf:GetMessageInfo(i)
        if type(text) == "string" and not secret(text) then
            table.insert(out, 1, { text, r, g, b })
        end
    end
    return out
end

local function keep(text)
    local color = string.match(text, History.DIVIDER_PATTERN)
    if color and History.DIVIDER_COLORS[string.lower(color)] then return false end
    return not string.find(text, "|K", 1, true)
end

function History.Save(cfg)
    local char = DUI.DB.Character()
    char.chatHistory = nil
    if cfg.history == false then return end
    -- Daylight chat box: its own lines, each tagged with its kind for the tabs.
    if ns.Box.On() then
        local lines = {}
        for _, l in ipairs(ns.Box.Saved(cfg.historyLines or ns.DEFAULTS.historyLines)) do
            if keep(l[1]) then lines[#lines + 1] = l end
        end
        if #lines > 0 then char.chatHistory = { savedAt = time(), box = lines } end
        return
    end
    local frames, any = {}, false
    for _, w in ipairs(History.Windows()) do
        local lines = {}
        for _, l in ipairs(History.Read(w.cf, cfg.historyLines or ns.DEFAULTS.historyLines)) do
            if keep(l[1]) then lines[#lines + 1] = l end
        end
        if #lines > 0 then frames[w.name] = lines; any = true end
    end
    if any then char.chatHistory = { savedAt = time(), frames = frames } end
end

-- Puts saved lines back after a reload (or a logout, if enabled), then clears
-- them. Returns how many lines were restored.
function History.Restore(cfg)
    local char = DUI.DB.Character()
    local saved = char.chatHistory
    char.chatHistory = nil
    if cfg.history == false or type(saved) ~= "table" then return 0 end
    if type(saved.frames) ~= "table" and type(saved.box) ~= "table" then return 0 end
    if type(saved.savedAt) ~= "number" then return 0 end
    local reload = time() - saved.savedAt <= History.MAX_AGE
    if not reload and cfg.historyLogout == false then return 0 end
    local divider = reload and History.DIVIDER or History.SessionDivider(saved.savedAt)
    local count = 0
    -- Saved under one chat style, restored in the other: the Daylight box's lines go
    -- to the main window, the main window's to the box (every tab, "*").
    if ns.Box.On() then
        local lines = saved.box or (saved.frames and saved.frames.ChatFrame1) or {}
        for _, l in ipairs(lines) do
            if type(l[1]) == "string" then
                ns.Box.Push({ l[1], l[2], l[3], l[4], l[5] or "*" })
                count = count + 1
            end
        end
        if count > 0 then ns.Box.Push({ divider, nil, nil, nil, "*" }) end
        return count
    end
    if type(saved.frames) ~= "table" then saved.frames = { ChatFrame1 = saved.box } end
    for _, w in ipairs(History.Windows()) do
        local lines = saved.frames[w.name]
        if type(lines) == "table" and #lines > 0 then
            for _, l in ipairs(lines) do
                if type(l[1]) == "string" then
                    w.cf:AddMessage(l[1], l[2], l[3], l[4])
                    count = count + 1
                end
            end
            w.cf:AddMessage(divider)
        end
    end
    return count
end
