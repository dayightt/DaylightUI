-- Restyles the speech bubbles over units' heads: a plain dark box, our border and
-- font. Addons can't touch bubbles inside instances, so those are left alone.
-- The game hands out bubble frames a moment after each line that shows one, so
-- this watches for them and skins each pooled bubble once.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style

local Bubbles = {}
ns.Bubbles = Bubbles

local styled = setmetatable({}, { __mode = "k" })

-- One region of a bubble. The font is only set when it isn't ours yet: every line
-- checks every visible bubble, and most already have it.
local function dressRegion(r, first, want, file, outline)
    local kind = r.GetObjectType and r:GetObjectType()
    if kind == "Texture" then
        if first then r:SetTexture(nil) end
    elseif kind == "FontString" then
        local had, now, flags = r:GetFont()
        local size = type(want) == "number" and want or now
        if type(size) ~= "number" then return end
        if had == file and now == size and (flags or "") == (outline or "") then return end
        r:SetFont(file, size, outline)
    end
end

-- Walks GetRegions' returns directly, no table per bubble per line.
local function dressRegions(first, want, file, outline, ...)
    for i = 1, select("#", ...) do
        dressRegion((select(i, ...)), first, want, file, outline)
    end
end

-- The bubble itself is an empty holder; its art (box, tail) and text are on its
-- first child frame.
local function dress(bubble)
    if type(bubble) ~= "table" or not bubble.GetChildren then return end
    if bubble.IsForbidden and bubble:IsForbidden() then return end
    local frame = bubble:GetChildren()
    if type(frame) ~= "table" or not frame.GetRegions then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    -- The box is anchored around the text with a margin, so the size goes on the text
    -- and the box follows. Never scale the frame: the game positions the text by an
    -- offset, and scaling stretches it, pulling the bubble off the unit's head.
    -- Bubbles are pooled, so the size is set again on every line.
    local want = ns.module and ns.module.db and ns.module.db.bubbleSize
    local first = not styled[bubble]
    styled[bubble] = true
    dressRegions(first, want, Style.FontFile(ns.MEDIA.font), Style.Outline(), frame:GetRegions())
    if first then Style.Shell(frame) end
end

function Bubbles.DressAll()
    if type(C_ChatBubbles) ~= "table" or type(C_ChatBubbles.GetAllChatBubbles) ~= "function" then return end
    -- One table for the visible bubbles, not one value each.
    for _, bubble in pairs(C_ChatBubbles.GetAllChatBubbles() or {}) do
        DUI.SafeCall(dress, bubble)
    end
end

-- Say, yell and party lines (and monster versions) show bubbles; whispers, guild
-- and the rest never do.
Bubbles.EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_PARTY" }

local hooked = false
function Bubbles.Build(mod)
    ns.module = mod
    if hooked then return end
    hooked = true
    -- A burst of lines in one frame (a whole group talking) restyles once, the next
    -- frame; a line in a later frame checks again.
    local queuedAt
    local function onMessage()
        if not mod.db.bubbles then return end
        local now = GetTime()
        if queuedAt == now then return end
        queuedAt = now
        C_Timer.After(0, Bubbles.DressAll)
    end
    for _, e in ipairs(Bubbles.EVENTS) do DUI.RegisterEvent(e, onMessage) end
end
