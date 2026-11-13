-- Reviewed exceptions to tests/test_guards.lua. Keys: "file|object|Method"
-- (hooks), "file|Name" (SetScript), "file|rule-id" (rules). Each needs a reason
-- someone can check. Hooks on the game's own objects were reviewed and replaced
-- area by area; what's left is a reviewed KEEP saying why.
-- Hooks on a game object's own method have broken the game's calls before (its
-- protected calls then failed with "attempt to call a nil value"), so a new one
-- needs a better reason than these.
return {
    hooks = {
        -- The game's controller bars. Not a frame's method: a plain table of functions.
        -- Its shape calls write each button's art on every press and on every bar's
        -- grow or shrink, with no event, so between the addon's passes a press showed
        -- the game's art and a round sweep. Post-hooks touch only textures and a cooldown's look.
        ["DaylightUI_ActionBars/PadSkin.lua|GamepadActionBarStyleUtil|ApplyExtraButtonStyles"] = "the game restyles a controller button here on every press: our look back on, and the press",
        ["DaylightUI_ActionBars/PadSkin.lua|GamepadActionBarStyleUtil|ApplyExpandedActionBarStyle"] = "a controller bar grows when its trigger is held: our look back on",
        ["DaylightUI_ActionBars/PadSkin.lua|GamepadActionBarStyleUtil|ApplyCollapsedActionBarStyle"] = "a controller bar shrinks again: our look back on",

        -- Daylight UI's own
        ["Motion.lua|frame|Show"] = "ours: Motion.Window is only called on our own windows (all 9 callers checked)",
        ["Motion.lua|frame|SetShown"] = "ours: Motion.Window is only called on our own windows (all 9 callers checked)",
        ["InstallerUI.lua|frame|Show"] = "ours: the setup guide's own frame",
        ["DaylightUI_Bags/MoneyRoll.lua|ns.Window|UpdateFooter"] = "ours: the Bags module's own Window table (not a game object)",
        ["DaylightUI_InfoPanel/Panel.lua|Panel.holder|SetAlpha"] = "ours: the info panel's holder frame (its callback also Hide/Shows the game's Minimap)",

        -- Other addons' own code (the addon skins, Packs/Addons), never the game's
        -- objects. A skin that breaks is caught (Engine.Safe) and stops, named once
        -- in chat.
        ["DaylightUI_Skins/Packs/Addons/Ace3.lua|lib|m"] = "the AceGUI-3.0 library's RegisterAsWidget/RegisterAsContainer: each widget dressed as it's made",
        ["DaylightUI_Skins/Packs/Addons/Ace3.lua|w|m"] = "an AceGUI checkbox's own SetValue/SetDisabled/SetType/SetTriState: our switch repainted",
        ["DaylightUI_Skins/Packs/Addons/Ace3.lua|w|SetDisabled"] = "an AceGUI widget's own SetDisabled: its label dimmed",
        ["DaylightUI_Skins/Packs/Addons/Ace3.lua|w|RefreshTree"] = "an AceGUI tree's own RefreshTree: the buttons it makes as it fills dressed",
        ["DaylightUI_Skins/Packs/Addons/Ace3.lua|w|BuildTabs"] = "an AceGUI tab group's own BuildTabs: the tabs it makes dressed",
        ["DaylightUI_Quests/QuestieBridge.lua|m|SetHighlighted"] = "Questie's QuestieWaypoints.SetHighlighted: says which of its map icons is hovered, for the quest log's row",
        ["DaylightUI_Skins/Packs/Addons/RXPGuides.lua|f|UpdateVisuals"] = "RestedXP's RXPFrame: its theme set its backdrops again, ours back over them",
        ["DaylightUI_Skins/Packs/Addons/RXPGuides.lua|f|UpdateScrollBar"] = "RestedXP's RXPFrame: its scroll bar art set again, our thumb back",
        ["DaylightUI_Skins/Packs/Addons/RXPGuides.lua|f.CurrentStepFrame|UpdateText"] = "RestedXP's step boxes, made as a step comes up: dressed",
        ["DaylightUI_Skins/Packs/Addons/RXPGuides.lua|f.BottomFrame|UpdateFrame"] = "RestedXP's step list rows, made as a guide loads: dressed",
        ["DaylightUI_Skins/Packs/Addons/RXPGuides.lua|ui|ApplyFrameBackdrop"] = "RestedXP V2 draws every frame's art here: its art hidden, a shell of ours",
        ["DaylightUI_Skins/Packs/Addons/RXPGuides.lua|ui|AddFrameShadow"] = "RestedXP V2's frame shadows: hidden (our shell has its own)",
        ["DaylightUI_Skins/Packs/Addons/RXPGuides.lua|v2|GetGuideWindow"] = "RestedXP V2's guide window, made once: dressed",
        ["DaylightUI_Skins/Packs/Addons/RXPGuides.lua|v2|UpdatePlayerActiveStepItem"] = "RestedXP V2's Step boxes, made and filled as steps come up: dressed",
        ["DaylightUI_Skins/Packs/Addons/RXPGuides.lua|w|UpdateSubTheme"] = "RestedXP V2's guide window: its theme set its font, colors and button art again, ours back",
        ["DaylightUI_Skins/Packs/Addons/RXPGuides.lua|w.guideSteps|SetRows"] = "RestedXP V2's step list, its rows made and refilled: dressed",
        ["DaylightUI_Skins/Packs/Addons/ForeverDungeonJournal.lua|api|name"] = "ForeverDungeonJournal's own exported refreshes and window toggles (RefreshHomeCards, RefreshLootNow, ToggleSettingsPanel...): what they fill or make dressed",
        ["DaylightUI_Skins/Packs/Addons/NeedRoll.lua|f|Paint"] = "NeedRoll's own pill buttons (Theme:Pill) paint their label gold on each hover and tone: our button ink back",
        ["DaylightUI_Skins/Packs/Addons/NeedRoll.lua|f|SetSelected"] = "NeedRoll's own list rows (Theme:Row) say here that they're picked: our wash follows",
        ["DaylightUI_Skins/Packs/Addons/NeedRoll.lua|f|PaintShut"] = "NeedRoll's own section headers repaint shut or open here: our band and ink follow",
        ["DaylightUI_Skins/Packs/Addons/NeedRoll.lua|f|SetOpen"] = "NeedRoll's own fold arrows (Theme:Arrow) paint gold as they turn: our ink back",
        ["DaylightUI_Skins/Packs/Addons/NeedRoll.lua|tab|SetActive"] = "NeedRoll's own top tabs (CreateNativeTab) pick here: our tab look follows, the game's lift undone",
        ["DaylightUI_Skins/Packs/Addons/NeedRoll.lua|f|SetColor"] = "NeedRoll's own heading rules paint gold here: our faint rule back",
        ["DaylightUI_Skins/Packs/Addons/NeedRoll.lua|card|Draw"] = "NeedRoll's own section cards (Theme:SectionCard tables) redraw in gold: ours laid over them again",
        ["DaylightUI_Skins/Packs/Addons/NeedRoll.lua|card|Hide"] = "NeedRoll's own section cards hidden: ours fades out",
        ["DaylightUI_Skins/Packs/Addons/NeedRoll.lua|pane|Refresh"] = "NeedRoll's own list panes redraw their section card on each refresh and scroll step: ours follows in the same frame",
        ["DaylightUI_Skins/Packs/Addons/NeedRoll.lua|lines|Set"] = "NeedRoll's own chip underlines (Theme:ChipUnderline) set gold: the accent back",
        ["DaylightUI_Skins/Packs/Addons/NeedRoll.lua|bar|SetActive"] = "NeedRoll's own word switches (Theme:LabelToggle) pick a word in gold: ours in the accent",
        ["DaylightUI_Skins/Packs/Addons/NeedRoll.lua|SlashCmdList|NEEDROLL"] = "NeedRoll's own /nr: its window is made the first time it opens, then dressed",
        ["DaylightUI_Skins/Packs/Addons/DBM.lua|dbt|CreateBar"] = "Deadly Boss Mods' own DBT:CreateBar: its first bar, to find the prototype its bars share",
        ["DaylightUI_Skins/Packs/Addons/DBM.lua|proto|ApplyStyle"] = "Deadly Boss Mods' own bar ApplyStyle sets its font and texture again: the player's look back on",
        ["DaylightUI_Skins/Packs/Addons/PrettyTooltip.lua|panel|SetHeight"] = "PrettyTooltip's own panel frame, never the game's: every render of it ends in this call, our border follows",
        ["DaylightUI_Skins/Packs/Addons/BigWigs.lua|style|ApplyStyle"] = "BigWigs' own Default bar style: its slot runs after every look change on a bar",
        ["DaylightUI_Skins/Packs/Addons/BigWigs.lua|style|BarStopped"] = "BigWigs' own Default bar style: its slot runs before a look comes off a bar",
        ["DaylightUI_Skins/Packs/Addons/Bagnon.lua|B.Item|UpdateBorder"] = "Bagnon's own item class: it colors a slot's border by quality, quest, set or unusable; our outline takes that color after",
        ["DaylightUI_Skins/Packs/Addons/RXPGuides.lua|item|m"] = "a RestedXP V2 Step box's own SetElements/UpdateSubTheme/SetTitle: its text set again, ours back",

        -- The game's, kept (KEEP)
        ["DaylightUI_ActionBars/Totems.lua|fs|SetTextColor"] = "KEEP: the game's totem time text; restyles it after the game's own updates (plain AuraButton code, not secure)",
        ["DaylightUI_ActionBars/Totems.lua|fs|SetFontObject"] = "KEEP: the game resets this font (BuffFrame.lua AuraButtonMixin calls Duration:SetFontObject); restyles it after",
        ["DaylightUI_ActionBars/CdmEffects.lua|cd|m"] = "KEEP (opt-in): only when a spell has an active color, its glow off, no swipe or no GCD swipe; re-applies our swipe tint or swipe rule after the game's update. First suspect if CDM errors appear",
        ["DaylightUI_ActionBars/CdmEffects.lua|icon|SetDesaturated"] = "KEEP (opt-in): only when a spell's gray-out option is set; re-applies it after RefreshIconDesaturation",
        ["DaylightUI_ActionBars/CdmEffects.lua|icon|SetDesaturation"] = "KEEP (opt-in): only when a spell's gray-out option is set; re-applies it after RefreshIconDesaturation",
        ["DaylightUI_Skins/Kit.lua|tex|m"] = "KEEP: the game's side-tab icon textures (plain buttons, set on window refresh); keeps our crop",
        ["DaylightUI_Chat/Box.lua|cf|AddMessage"] = "KEEP: the Daylight chat box's lines. Read only (an earlier hook that also rewrote the game's history entries caused errors), never the combat log; other chat addons do the same and work",
        ["DaylightUI_Skins/Packs/Social.lua|CommunitiesFrameMixin|name"] = "KEEP: OnClubSelected and SetDisplayMode move the club icon and the line under the title while the window stays open, with no event; the post-hook only places those",
        ["DaylightUI_Skins/Packs/Social.lua|CommunitiesListMixin|Update"] = "KEEP: the club list rebuilds while the window stays open, with no event; the post-hook only shows or hides the empty column",
        ["DaylightUI_Skins/Packs/Social.lua|CommunitiesListEntryMixin|name"] = "KEEP: SetAddCommunity paints the join row green after the row is dressed, with no event; the post-hook only sets that icon and its text",
    },
    setscript = {
    },
    rules = {
    },
}
