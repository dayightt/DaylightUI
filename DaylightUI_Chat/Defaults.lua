-- Default settings for chat.

local _, ns = ...

-- Chat has its own font setting, used for the chat text and the speech bubbles.
ns.MEDIA = DaylightUI.Media.RegisterArea("chat", "Chat")

ns.DEFAULTS = {
    media = DaylightUI.Media.AreaDefaults(),
    -- "daylight" is Daylight UI's own chat box with its own message list and tabs.
    -- "classic" keeps the game's chat windows, restyled.
    style = "daylight",
    -- The corner panel either matches the info panel's size (matchInfo) or
    -- uses the chat's own size.
    matchInfo = true,
    width = 428,
    height = 208,
    sideWidth = 340, -- size of the second chat panel, shown while a tab is on it
    sideHeight = 140,       -- under the target of target's default spot
    panelShown = true,      -- the panel's background (and border) behind the chat
    panelAlphaOwn = false, -- off: same opacity as every window (General windowAlpha)
    panelAlpha = 0.85, -- used when panelAlphaOwn is on
    sideAlphaOwn = false,   -- off: the second panel is as solid as the main one
    sideAlpha = 0.85, -- used when sideAlphaOwn is on
    sideHides = "chat", -- "chat" follows the main panel; otherwise one of the hides values
    -- Border for every chat panel, including windows pulled out of the dock.
    -- "auto" follows the chat style (Daylight frame for the box, a thin line for
    -- Classic). "daylight" is the band inside a dark outline, "flat" a plain line.
    border = "auto",
    borderSize = 1, -- flat border thickness in px
    borderColor = "shell",  -- "shell", "accent", "class" or "custom"
    borderCustom = { 0.72, 0.70, 0.66 },
    -- "never", "fights" (panel and tabs float away in combat), "fightsIdle" (also
    -- fades the whole chat when nothing new arrives for a while), or "always"
    -- (only the lines show).
    hides = "fightsIdle",
    idleAfter = 10,         -- seconds
    ignoreGains = true,     -- loot, money, XP, rep and skill-ups don't bring it back
    fade = DaylightUI.Fade.Defaults(), -- opacity only, "hides" decides when
    lineTime = 8, -- seconds before each line fades; hovering the chat shows them all
    whisperTabs = true, -- also give each person's whispers their own tab (the game's whisperMode)
    hideButtons = true,     -- the menu, channel, voice and social buttons beside chat
    shortTags = true,       -- [G], [T], [P], [S]... instead of the channel's and speech's full words
    worldChannelsFirst = true, -- world channels keep the first numbers when an addon joins its own first (Kinds.WorldFirst)
    channelNumbers = false, -- numbered channels keep their number: [1. G], [2. T]
    -- channelTags: custom short tags per kind, set in a tab's Show window (Tags.lua). No default.
    classColors = true, -- class-colored names (the game's own setting)
    levels = false,     -- "[60] Name": a level beside each name the game has told us (Levels.lua)
    timestamps = "game", -- "game" uses the game's setting, "none" turns it off, else a time format
    links = true,           -- web addresses clickable, to copy
    linkTooltips = true,    -- an item, spell or quest link's tooltip on mouseover
    linkTooltipSpot = "chat",   -- "chat": just above the chat; "cursor": at the mouse; "game": at the Tooltip unlock handle
    linkTooltipCompare = true, -- compare with worn gear per the game's setting (off: only with Shift)
    linkTooltipDelay = 0,       -- seconds on a link before its tooltip shows
    whisperSound = "soft", -- "soft" (Breath), "dewdrop", "hello", "bell", "pop" mute the game's sound; "game"; "none"
    arrowHistory = true, -- Up/Down in the edit box recall sent lines (Alt+Up/Down keeps the game's)
    history = true,         -- the last lines of each chat window come back after /reload
    historyLogout = true,   -- history also comes back after a logout, not only a /reload
    historyLines = 100, -- lines kept per window
    copyButton = true,       -- a small Copy button on the panel while the mouse is over the chat
    menuButton = true,       -- the game's chat menu (languages, emotes) as an icon in the Daylight box's header
    voiceButton = false,     -- a headset icon in the Daylight box's header: opens the game's voice chat and channels window
    inputAt = "top", -- edit box position: over the tabs ("top"), the panel's bottom, or "below" it (Classic)
    locked = false, -- no dragging the tab row, no resize grip
    boxInputAt = "bottom", -- same for the Daylight chat box: inside its bottom, lines rising over it
    textSize = 0, -- text size for every chat window (0 = the game's per-window size)
    outline = false,        -- an outline on chat text
    tabSize = 13, -- tab label size
    inputSizeOwn = false, -- off: edit box text matches the message size
    inputSize = 14, -- used when inputSizeOwn is on
    sideTextSizeOwn = false, -- off: second panel text matches the message size
    sideTextSize = 14, -- used when sideTextSizeOwn is on
    bubbles = true, -- restyle speech bubbles too
    bubbleSize = 12,        -- the bubbles' font size
    -- Daylight chat box filters and alerts (Extras.lua)
    spamRepeats = true, -- drop the same message from the same person within a minute (public channels)
    spamAds = true, -- drop gold-seller spam in public channels
    spamWords = "", -- custom words and phrases to hide in public channels, one per line
    alertName = true, -- highlight your name with a soft sound
    alertWords = "", -- extra comma-separated words to highlight
    alertSound = false,     -- the soft sound for an alert
    groupLines = true, -- role icons on "LF2M need a healer" lines
    -- Whispers in the Daylight chat box (Talk.lua, Tiles.lua, Convo.lua, Hub.lua)
    whispersIn = "both", -- "both": tiles and chat; "window": tiles only; "chat": chat only
    whispersButton = true, -- speech bubble in the header with the unread count, opens every conversation
    whisperPreview = true,  -- a new whisper shows a preview above the tiles for a few seconds
    awayOn = false,         -- answer whispers with an away message
    awayWhen = "away", -- "away" (flagged Away), "instance" (dungeon or raid only), "combat" (in combat only)
    awayText = "",          -- the away message ("" = the standard one)
    tilesMax = 6,           -- whisper tiles at most
    tileArt = "letter", -- tile shows the initial in the class gradient ("letter") or the class icon ("icon")
    tileSize = 34, -- px
    previewTime = 6,        -- seconds a new whisper's preview stays
    whisperSide = "right", -- side the drawer opens on ("left" suits a chat on the right of the screen)
    cardWidth = 200, -- px
    cardAt = "side", -- "side" (beside the chat, same height), "above" the tiles, or "free" (where it was dragged)
    cardHeight = 300, -- height when above or dragged away, px
    -- Daylight chat box look and motion
    topLine = true,         -- the accent line along the top
    mentionGlow = true, -- glow behind lines mentioning your name or alert words
    tabDots = true, -- small unread count on a tab
    lineFadeIn = true,      -- new lines ease in
    typeLift = true, -- lines rise while typing, the edit box under them
}
