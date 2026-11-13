# DaylightUI 1.7.1

Controller support is officially in beta, layers for your unit frames, quest mob colors on nameplates, full Spanish and a round of fixes.

## New
- Controller: Officially in beta!
- Performance: Large performance increases
- Unit frames: Pick which layer each unit frame, cast bar and the swing timer draws in, so you decide which one sits on top where they overlap
- Nameplates: Mobs your quests still need can have their health bar in their own color

## Changed
- Whispers: Right-click a conversation in the list to pin it or close it
- Copy chat: The copy window has an X, and Escape closes it before any window behind it
- Cast bars: Each cast bar's spell name and cast time have their own switch, size, position and color
- Damage meter: Class icons match the set you picked for your unit frames, Jiberish styles included
- Object glow: Ore and herbs don't light up for now, while nameplates that vanish until a /reload are looked into. Quest objects, chests and your bobber still do
- Languages: Spanish now covers all of Daylight UI, thanks to Narian, and more Simplified Chinese thanks to Hwtaps

## Fixed
- NPC window: Turning in a quest no longer hangs on "Retrieving item information"
- Books: Every page of a book or letter is light and easy to read, not just the first
- Minimap: No more error at login from an addon whose minimap button has a round icon
- Fishing: The bobber shows only the Daylight UI light, not the game's interact icon on top of it
- Action bars: Shadowform switches bar 1 to its own page, like a druid's forms
- Legacy: Challenges the game can't track no longer show a Track switch
- Cooldown Manager: Arcane Blast's stacks show on a bar too, not just as an icon
- Minimap: No more small stutters from the addon button drawer while Questie or other map pin addons add pins as you move
- Character: The stats show everything the game's own sheet does: health, mana, haste, off-hand damage, armor and spell penetration, and your pet's crit, dodge and a demon's mana
- Action bars: The "Daylight UI tried to call SetShown()" error for the bottom bars, which still showed up after looting in a fight, is gone for good
- Item outlines: The colored outline around reward and shop items no longer loses a side at smaller UI scales
- DoT damage: The damage your DoTs still have to do shows on a French game client too, not only in English
- Action bars: Round and other shaped buttons are see-through like square ones

# DaylightUI 1.7

A complete Damage Meter refresh, a cast bar between your frames, buffs on friendly tooltips and faction crests on nameplates.

## New
- Cast bar: Your cast bar can sit between your frame and the target's, with your swing timers fanning out under it
- Tooltip: A friendly player's tooltip shows their buffs as small icons, so you can see what they're missing
- Action bars: A new rank of a spell takes the old rank's place on your bars
- Action bars: Druids: a powershift macro can swap your bar the moment you press it (/click DaylightUICat, DaylightUIBear or DaylightUIMoonkin)
- Nameplates: Players of the other faction get an Alliance or Horde crest, and friendly names can each have a color you pick
- Portraits: Pick how thick the portrait rings are, drop their middle line, or use the game's class icons
- Profiles: A profile of its own for when the game's controller mode is on
- Little touches: Pick which ends of the loot lines are angled; right-click the attack power text for melee or ranged

## Changed
- Meters: Complete Damage Meter refresh: sleek new look, as many windows as you want, and every hit one click away
- Action bars: Keybinds are short by default (S2 instead of SHIFT-2)
- Copy chat: Dragging past the top or bottom of the copy window scrolls it, so you can copy part of a long log

## Fixed
- Cooldown Manager: A buff can play a sound as it runs out, as in the game's own Cooldown Manager
- Cooldown Manager: Fixed groups drifting off center, Arcane Blast's empty icon, a blank Add by ID menu, stiff size sliders, and totem buffs counted as cooldowns
- Unit frames: Target of target can show a power bar, and your focus's target gets its own small frame, as in the game's own UI
- Action bars: No more "the game blocked ... SetShown()" messages in chat for the stance and bottom bars during a fight
- Nameplates: Enemy players' names are red again
- Quest tracker: The Quests header and its buttons no longer lie over the quests as the list scrolls
- Whispers: Right-click a whisper to ignore that player, as in the game's own menu
- Pet frame: Your hunter pet's happiness is a clear color square again by default
- Party frames: No more error when a ready check ends while someone is out of range
- Little touches: Attack power shows for casters, your pet's attack speed is back, totem timers no longer jump, new loot no longer shows blank in bags, trade shows full names, a moved micro menu stays put after you die, and enchants link in chat again

# DaylightUI 1.6.9

Other addons can now add to Daylight UI, whispers can float anywhere, /kb, and a report tool for nameplates that vanish.

## New
- Plugins: Other addons can restyle Daylight UI's cast bars, unit frames, quest tracker and bags, and add their own texts and settings: daylightui.com/plugins
- Whispers: A conversation can open above the chat, be dragged anywhere on screen and resized by its corner
- Key bindings: Type /kb to bind keys straight on your action bars
- Data texts: Right-click the crit text to pick melee, ranged or spell crit
- Nameplates: Choose how much a nameplate lights up under your mouse, or not at all
- Cooldown Manager: Paladins can add one Aura icon that shows whichever aura is on, and glows when none is
- Bag addons: Bagnon and Baganator in the Daylight UI look
- Nameplate report: If your nameplates vanish, /dui platelog makes a report to send to the Daylight UI Discord

## Fixed
- Totem bar: No longer jumps onto the middle of the action bars at login, after a fight or in Ghost Wolf
- Chat: The game's own chat settings (tradeskills, currency, target icons and the rest) can be switched on and off again

# DaylightUI 1.6.8.1

Shared profiles and a tour from the options, nameplate target arrows, spells by form in the Cooldown Manager, and a big round of fixes.

## New
- Options: Find ready-made profiles other players share at daylightui.com/profiles, right from the options home page
- Tour: A short tour after setup shows where things are. Take it again from the options home page
- Nameplates: Arrows by your target's plate, a bigger target name, and a mark by your group's names
- Unit frames: Overshield options, see-through missing health, and the cast bar and swing timer's own border
- Raid frames: Raid 20 and Raid 40 can each have a spot of their own
- Cooldown Manager: Show a spell only in the forms you pick: druid forms, warrior stances, Stealth
- Little touches: Move the guild window, a junk coin on junk items' tooltips, a Gold tooltip for one faction, buff timers with their own outline

## Changed
- World map: Maximized, the quest list opens beside the map instead of shrinking it
- Heal indicators: Six squares instead of four, with room for a group buff beside your heals
- Controller: Every window uses the same buttons as the game's own: cast and put spells on your controller bars from the spellbook, use items from your bags, learn talents, place gear in your bags, switch chat tabs, buy, train, open mail, swap gear
- Languages: Simplified Chinese checked through by a native speaker, thanks to Finn
- Little touches: Easier-to-hit close buttons, a softer DoT end line, party icons you can move with a name tab, a clearer Unlearn, a simpler loot window, and a one-line "blocked" notice

## Fixed
- Setup guide: Turning a part off, or keeping an addon like Baganator, now really turns it off; no more layout popup or buff errors after setup
- Guild: Opening the guild window from a data text no longer breaks officers' rank settings
- Legacy: Trees that can only be reset at the NPC no longer offer a free reset
- Minimap: No longer blank in dungeons
- Cooldown Manager: Imported layouts keep the game's order, debuffs on you show their icon, hidden buffs give their spot up, no glows that could never show
- Chat: Whispers show in front of action bars, and a community-only tab shows everyone's messages
- Unit frames: Mob levels colored like the game's own again, and an incoming heal no longer runs across the screen
- Action bars: Druids: shifting from one form straight to another no longer leaves your caster bar up
- Bags: Collapsing a bag group no longer leaves gaps: collapsed groups line up on one row
- Little touches: The hunter's stable in Daylight UI style, no error when a fight starts with the profession window open, a slim map top with OpenMap, no gray emblem on the guild window

# DaylightUI 1.6.8

A cursor ring, junk marking and shared bag groups, druid resource bars, frames that grow any way, and a big round of fixes.

## New
- Cursor ring: A glowing ring around your mouse cursor, showing your global cooldown and casts (Quality of Life)
- Bags: Mark any item as junk so it sells with your gray items
- Bags: Share your own bag groups as text, and import someone else's (Bags > Categories)
- Bags: See your bank from anywhere: right-click the bag window's title bar
- Player frame: Druid resource bars: rage and energy in caster form, mana in bear or cat form
- Party and raid frames: Can grow up, down, left or right, and party frames can show while you're alone
- Unit frames: Copy one frame's setup onto another, like party onto raid (Copy from, on each frame's page)
- Heal indicators: Can watch group buffs like Mark of the Wild or Fortitude, and show as spell icons
- Cooldown Manager: Can fade out of combat or until you mouse over it, like the action bars
- Action bars: Action Bar 1 can keep its own buttons when you change stance or form
- Data texts: Movement speed, on foot, mounted or swimming
- Little touches: A name tab for the pet frame, a text size for the second chat panel, and right-click Recent in the bags to clear it

## Changed
- Spellbook: Stays in Daylight UI style in a fight, and you can cast from it
- Campfire: Sit and chat by the fire without your UI fading away every minute, and no more bar along the bottom
- Chat: Unread whisper tiles glow in the whisper color until you read them
- Pet frame: Your hunter pet's happiness shows as a small mood face you can move and size
- Little touches: A tidier Cooldown Manager spell card, scroll bars that show, A to Z data text menus, the stack split box in Daylight UI style, Train all asks before spending gold, and a Show all button in the group finder

## Fixed
- Cooldown Manager: Spells in a group can trade places, groups from the middle stay centered, and debuffs on you added by ID show (like Weakened Soul)
- Action bars: The totem bar no longer jumps away in Ghost Wolf or a fight, and a tall data bar moves your bars up out of its way
- Minimap: No longer blank after logging in, after talking to someone in town, or in some dungeons; the N on the turning minimap shows again, and the minimap fades away at a campfire and on the AFK screen
- Character window: Movement speed is back, Damage shows attack speed on hover, and your character shows at once in a form
- Unit frames: The pet's health bar shows on smaller screens, and target of target no longer cuts through your target's portrait
- Loot: Looted money shows the right coin, and the loot popup keeps the Daylight UI look
- Other addons: Upgrade arrows show in the bags, ItemTree's buttons sit on the profession window, and ManaRise fills the action buttons
- Nameplates: No longer stay on a dead mob you can loot
- Vendors: Clicking an item quickly buys one on every click again
- Chat: Up and Down in the chat box bring back slash commands too, like /dance
- Group finder: Unlisting yourself takes your listing away right away
- Professions: The X to unlearn a profession shows for every profession, Leatherworking too
- Little touches: Names on a nameplate's bar draw over it, the swing timer's name and time switches work, and bottom buttons no longer overlap with a wide font

# DaylightUI 1.6.7.1

A minimap fix: no more black map in cities, and no more zooming by itself.

## Fixed
- Minimap: No longer goes black in cities and buildings, and no longer zooms in and out by itself

# DaylightUI 1.6.7

Cast bars on party frames, more Cooldown Manager options, a minimap that no longer goes black, and a round of fixes.

## New
- Party frames: Cast bars on your party members' frames: inside the frame, sliding out under it, or beside it
- Cooldown Manager: A buff can glow while it's up, like Clearcasting or Nightfall
- Cooldown Manager: A spell can hide or fade while you can't afford it, like Kick showing only when you have the energy

## Fixed
- Minimap: No longer goes black at random, after a reload, or in buildings, caves and dungeons
- Cooldown Manager: Buffs from passive talents (like Flurry) and Arcane Blast's stacks show on their bars and icons again
- Cooldown Manager: Some icons no longer disappear when the game's own Cooldown Manager is off, and a hidden buff no longer leaves its keybind floating
- Cooldown Manager: Groups growing from the middle stay centered when a buff drops
- Data texts: The Hearthstone no longer shows a short cooldown every time you cast a spell
- Chat: Communities stay out of tabs they're switched off in, and Trade (Local) is no longer listed twice
- Chat: The glow behind a message with your name no longer stays after the message fades
- Quest log: Ctrl-click a reward to try it on, Shift-click to link it in chat
- Group finder: The gear by the X shows dungeons and raids of every level again
- Battlegrounds: Enemy flag carriers get frames in Daylight UI style instead of the game's plain ones
- Spellbook: "Hide lower ranks" now hides a Paladin's lower-rank Blessings too

# DaylightUI 1.6.6

German, power bars on nameplates, an ammo data text, modifier pages on Action Bar 1, and a round of fixes.

## New
- Language: Daylight UI now speaks German. Thanks to Haengematte for the translation!
- Nameplates: A thin mana, rage or energy bar under the health bar (Nameplates > Health & Names)
- Action bars: Action Bar 1 can switch pages while you hold Shift, Ctrl or Alt
- Data texts: Ammo in any data text slot: amber, then red, as you run low
- Quest tracker: With the Spoken addon, a play button on each voiced quest
- Gradients: One switch turns every gradient into a flat color (General > Gradients)

## Fixed
- Click-casting: A lower rank of a spell lands on the friend you clicked, not on yourself
- Cooldown Manager: Arcane Blast shows its stacks and how long they last
- Cooldown Manager: Shooting your wand no longer shows hidden spells or sets off other spells' sounds
- Nameplates: Enemy cast bars show their color again instead of turning white
- Action bars: Yellow corners no longer show on every button with a pet autocast spell in your first slot
- Social: Recent Allies no longer shows a "the game blocked" warning
- Quest log: Quests ready to turn in keep their level color instead of all turning gold
- Professions: The profession window shows your real skill level and updates when you skill up
- Info panel: The broken armor figure stays where you move it in Edit Mode
- Whispers: The chat no longer fades away while you type a whisper reply
- Data bar: Framerate and latency shows your latency too, not just your framerate
- Legacy: Dungeons and Raids have their heading back
- Little touches: A softer loot flash, and tidier text in the bags' currencies and the guild window

# DaylightUI 1.6.5.2

Spanish, new data texts, any spell or item in the Cooldown Manager, quest XP on the experience bar, and a dungeon tooltip error fixed.

## New
- Language: Daylight UI now speaks Spanish. Thanks to Narian for the translation!
- Data texts: Crit, attack power, spell power, hit and Soul Shards can go in any data text slot, on the panel or the data bar
- Cooldown Manager: Add any spell or item by its ID: trinkets, racials, potions with how many you carry, and more
- Cooldown Manager: Shield Block and Holy Shield show how many charges they have left
- Experience bar: A green part on the experience bar shows the XP waiting in quests you can turn in

## Changed
- Damage meter: Entering a dungeon, raid or battleground now asks whether to clear your old fights
- Chat: The copy chat window keeps the chat's colors, font and size

## Fixed
- Tooltip: In dungeons, hovering a mob with a ?? level no longer throws errors and leaves the tooltip stuck to your cursor
- Data bar: Fixed an error at login with some data text addons
- Minimap: Rotate minimap no longer spills past the info panel: while it turns the map is round, with a thin ring and an N pointing north
- Minimap: The zone name, coordinates, clock and framerate are no longer cut off at the top with a bigger text size
- Options: Dragging around the color wheel no longer makes the game stutter
- Inspect: Ctrl-click someone's gear to try it on, Shift-click to link it in chat
- Trade window: Names no longer run under the other player's portrait
- Legacy: Dungeons and Raids have their heading back
- Languages: More Chinese translations thanks to Hwtaps

# DaylightUI 1.6.5.1

Roleplay names with Total RP 3, more nameplate colors, a freer swing timer, and lost Cooldown Manager layouts restored.

## New
- Names: With Total RP 3, players show by their roleplay name on unit frames, raid frames, nameplates and the threat meter
- Nameplates: Bosses, rares and casters can each have their own health bar color, on the Health & Names page
- Nameplates: The level number can have its own color, size and font
- Nameplates: Friendly nameplates can switch off by themselves in dungeons, raids and battlegrounds, and come back when you leave
- Minimap: Drag the addon drawer's buttons into any order you like
- Unit frames: Heal indicators show Oath of Light for paladins, counting down its last minute so you know when to swear it again
- Swing timer: Move the main hand, off hand and ranged bars each on their own, with their own size and look, or turn the main hand bar off
- Chat: The second chat panel can fade and hide on its own, apart from the main chat
- Loot window: A switch to turn off all of its animations, under Window skins

## Changed
- Swing timer: Detaching the cast bar no longer takes the swing timers with it, and swing timers detached together now slide in and out
- Bags: Swapping out a bag that's still full works with packed bags too: half stacks merge, profession bags and quivers take what fits, and at a banker the bank takes the rest
- Cooldown Manager: Buff swipes use your accent color, and a missing buff's gray icon matches the rest of the layout
- Little touches: More Simplified Chinese translations, and the group finder's Sort button flips between level and name in one click

## Fixed
- Cooldown Manager: Fixed a rare bug where Cooldown Manager layouts could disappear after an update
- Chat: The second chat panel no longer flashes and goes invisible when you turn it on or move a tab to it
- Loot window: Loot rows no longer flicker as the window opens
- Character: Block chance shows again in the Defense stats when you have a shield on
- Talents: Talent tooltips show an ability's cost, range, cast time, cooldown and what it needs again
- Bags: Characters with the same first name each keep their own bags, bank and gold, instead of sharing one
- Mailbox: Letters you write can have several lines again: Enter starts a new one

# DaylightUI 1.6.4

The Cooldown Manager expansion: import the game's own layouts, layout profiles for every class and talent set, and a sharper editor. Plus new data texts and threat on nameplates.

## New
- Cooldown Manager: Import layouts from the game's own Cooldown Manager (guides, other UIs), and they look just like they did in the game
- Cooldown Manager: The layout editor glows round the picked spell and its whole group, with Import, Reset and Remove group close at hand
- Group finder: List yourself can sort dungeons, quests and zones by level or by name
- Unit frames: The target's threat % tag can sit on its own anywhere on screen, with its own size, font, color and box
- Data texts: New data texts: Combat, Volume, Item level, Time played, Professions and Hearthstone, and other addons' broker texts can fill a slot too
- Damage meter: A see-through window and bar background, and names and numbers in class colors, for both meters
- Nameplates: Your threat % on each enemy can show by its health bar, with its own spot, size, color and font, on the Threat page
- Nameplates: Friendly plates can show your party and raid members' names in a color of your choice
- Bags: The keyring shows in the bag only when you want it: click the key on the bag slots bar
- Chat: The second chat panel can fade and float away on its own, apart from the main chat

## Changed
- Cooldown Manager: Layouts are now profiles: as many as you like for each class, shared by all your characters of that class, and each talent set picks its own
- Bags: Your own empty bag groups stay out of the way until you hold Shift while dragging an item (or turn on Show empty groups)
- Bags: The built-in bag groups (Weapons, Armor, Junk...) can be deleted too, and brought back from the Categories page
- Tooltip: An item's healing and spell damage each get a line of their own

## Fixed
- Cooldown Manager: Spells with no cooldown of their own, like Rend, show all the time like the game's icon, lit while the debuff is up
- Cooldown Manager: Reverse swipe now also turns the sweep around on buff icons
- Chat: Voice chat can be reached from the chat again: turn on Voice chat button for a headset at the top-right of the chat
- Quests: The quest tracker's This zone filter shows a dungeon's quests again (The Stockade)
- Group finder: After listing yourself, Find shows the dungeon you listed for instead of All activities

# DaylightUI 1.6.3

Action bars that change with your stance or a held key, more chat and minimap looks, and fixes.

## New
- Action bars: Bars 2 to 8 can swap pages in a stance, form, Stealth, or while holding Shift, Ctrl or Alt
- Damage numbers: A Size slider for the numbers over what you hit
- Chat: Pick the chat's border, the second panel's opacity, and tab and typing text sizes
- Minimap: Pick the size and color of the zone name, coordinates, clock and framerate
- Unit frames: Player, target and focus each get their own Power bar switch
- Loot window: Switches to turn off the flash on each item, or all of the loot window's animations, under Window skins > Loot window

## Fixed
- Minimap: No more black minimap in cities and indoors, and a rotating square map keeps its corners
- Character: After closing the Character window with its X in a fight, C opens it on the first press
- Info panel: Clicking durability opens the Character window in a fight too
- Talents: The Secondary talents tab opens once you learn Dual Talent Specialization
- Bags: Gold at the bottom of the bags no longer sticks out past the edge
- Bags: The keyring shows only the key slots you can use, not rows of padlocks
- Chat: A chat window pulled out on its own no longer has a border covering its newest lines
- Chat: Looking for Group channel messages always land in the LFG tabs and get their [LFG] tag
- Languages: More Simplified Chinese, thanks to Hwtaps

# DaylightUI 1.6.2.1

Buff timers where you want them, mouseover casting with extra mouse buttons, and fixes.

## New
- Buffs: Show the time left on buffs and debuffs at the top, middle or bottom of their icons
- Unit frames: Extra mouse buttons bound to your action bars now work over unit frames too, so they can mouseover cast
- Unit frames: Health text can show the whole number, like 1,400, instead of 1.4K

## Changed
- Campfire: Your bars and frames come back once Camp Benefits lands, and a burning fuse counts down the minute while you sit
- Loot window: The light on items as they come in and as you take them is much softer
- Languages: Simplified Chinese now covers far more of Daylight UI, thanks to a Chinese player

## Fixed
- Bags: Items no longer show as an empty slot now and then
- Damage meter: Small amounts per second in a fight show as a whole number, no longer a long decimal like 0.1298239838983
- Party frames: Hovering a party member's debuff shows what it is again
- Unlock mode: Two frames with the same X or Y now really line up, instead of sitting a pixel or two apart

# DaylightUI 1.6.2

Window opacity of your own, guild name colors on nameplates, combat text that stays on, and lots of fixes.

## New
- Nameplates: Pick the color and size of guild names and NPC jobs on nameplates
- Windows: Each window can have its own background opacity, and one button makes them all match again
- Tooltips: PrettyTooltip now wears the Daylight UI frame, and replaces Daylight UI's tooltips while it's on
- Unit frames: One switch hides the power bars on every frame
- Damage meter: Show the meter's numbers in full (12,345) instead of short (12.3K)

## Changed
- Combat text: On Automatic, combat text uses your Daylight UI font, no longer the damage numbers' font
- Action bars: New DPS/Tank and Healer setups show the micro menu in the bottom-right corner
- Minimap: The damage meter can open on either side, and the minimap's box has its own background and border
- Professions: Shift-click a profession's icon or name to link it in the chat box you're typing in, instead of the chat button

## Fixed
- Combat text: No longer goes missing when the game's own floating combat text option is off
- Damage numbers: On Automatic, they now use your Daylight UI font, the one the sample shows
- Chat: The chat menu is back, so you can pick which language you speak and find emotes again
- Chat: Trade (Services) and Trade (Local) now show in the Trade tab with short tags, and each has its own switch
- Chat: Each chat tab remembers the channel you last talked in, so the Guild tab stays on guild chat
- Chat: Timestamps can use a 12-hour clock with AM/PM, like the game's own setting
- Bags: With smaller bag slots, borders, glows and cooldown numbers stay inside each slot, and the search hint fits its box
- Party and raid frames: Fixed an error when the group changed as someone was being healed, such as after releasing
- Minimap: No longer shifts when the damage meter opens after you've moved it
- Action bars: The totem bar stays where you put it in unlock mode, instead of jumping back to its Edit Mode spot
- Class icons: Party frames and the spellbook now show the icon style and icon you picked for each class
- Buffs: Rogue poisons show once on the buff bar, instead of twice
- Little touches: Changing the damage numbers font now tells you the game needs a restart

# DaylightUI 1.6.1

Ore, herbs and chests glow as you get close, a new loot window, shareable professions, and lots of fixes.

## New
- Glowing objects: Ore, herbs, chests, quest objects and your fishing bobber glow as you get close
- Loot window: A new look, with each item's slot and armor type under its name
- Professions: Share your profession in chat so others can see your recipes
- Professions: Clicking someone's shared profession shows their recipes in a small Daylight UI window
- Gold: Characters you've deleted can be removed from your gold total and bag lists
- Chat: Hide public chat messages containing words or phrases you choose
- Design mode: Move health numbers, power numbers, party pets and more, and nudge them with the arrow keys
- Personal display: Its health bar can be hidden, leaving just your power bar
- Click-casting: Cast on whoever your mouse is over, switched on from the Click-casting page
- Leader tools: In a party, the tank can place raid markers without being the leader
- Leader tools: They now open during a fight
- Dressing room: Drag the window anywhere and it stays there
- Quests: A small icon and number show how many of your party have a quest
- Character window: Using an enchant or armor kit lights up the gear it can go on
- Sounds: Spending talent points, mail, repairs and quest text now have their own sounds

## Changed
- Stun alert: The alert for being stunned, silenced or feared has a new look, and you can move it
- Chat: A thin bar beside the chat shows how far up you've scrolled
- Party frames: Now in order by default: tank, healer, then damage
- Enemy cast bars: No longer flash, because the game often got wrong whether a cast could be interrupted
- Quests: In a dungeon or raid, the quest list shows only that place's quests
- Smoother fights: Raid frames, the quest list, the damage meter and the Cooldown Manager do less work during fights
- Class icons: New icons drawn for Daylight UI

## Fixed
- Quests: Clicking to finish a quest before its rewards appeared no longer closes the window
- Mail: You can now mail gold on its own, with no item or subject
- Fading: Faded frames, action bars and buffs no longer show through each other
- Action bars: Buttons no longer stay grayed out after logging in, reloading or getting off a mount
- Action bars: The bag bar and micro menu size sliders no longer jump around, and their reset works
- Party and raid: Click-casting no longer misses when your mouse is on someone's buff or debuff icons
- Party and raid: Frames now appear right away if you join a group during a fight
- Minimap: No longer turns black indoors, and no more errors when addons fill it with icons
- Chat: Whisper conversations now scroll down to the newest message
- Chat: Clicking a community invite no longer causes an error
- Chat: Your away message only goes out while you're marked Away, and never to someone you just whispered
- Scale: The Scale setting now also changes the size of the loot window, loot rolls and alerts
- Friends: Add Friend and Broadcast now work instead of being blocked by the game
- Group finder: You can list yourself as any role your class can fill, not just your current spec's
- Swing timer: No more empty Ranged bar in fights if you have no ranged weapon
- Little touches: Cleaner rounded corners, tidier combo points and flight timer, red eyes on elite dragons, and no blank icons from the old icon pack

# DaylightUI 1.6.0.1

The damage meter can start fresh when you enter an instance, plus a few fixes.

## New
- Damage meter: Can clear itself when you enter an instance, or ask you first

## Changed
- Character window: Your Hit chance shows under melee, ranged and spell again

## Fixed
- Unit frames: Priests can now see Weakened Soul on party and raid frames, even from another priest
- Cooldown Manager: Fixed a rare bug that left the layout editor empty

# DaylightUI 1.6

A data bar, frame groups in unlock mode, threat colors on nameplates, and locked items in your bags.

## New
- Info panel: An optional data bar along the bottom of the screen, every slot your pick
- Info panel: The experience bar can have its own fade, apart from the panel's
- Unlock mode: Frame groups, arrow key nudges, and a pick of which corner of a frame stays put
- Nameplates: Optional threat colors for a mob attacking you and one that isn't
- Bags: Lock items against selling or disenchanting, and keep an item in its slot on clean up
- Unit frames: Heal indicators show Weakened Soul for priests
- Unit frames: The personal display shows incoming heals and shields
- Action bars: The micro menu has its own icons in your accent, and the bag bar loses its gold dividers
- Cooldown Manager: Icons can show the key that casts them
- Group finder: Shows the zone each group leader and solo player is in
- NPC window: A little coin marks the best-selling quest reward, and your last sold item is one click to buy back
- Chat: Clear a whisper conversation, or all of them, from the whispers window
- Controller: Daylight UI windows work with the D-pad and B button
- General: New options carry a NEW tag, counted from a version you pick on Home
- Quality of life: Tracking like Find Minerals turns itself back on after a logout

## Changed
- Character window: One Hit row, the biggest of your melee, ranged and spell hit
- Buffs: Icon size now sizes the bars, in place of the Scale sliders

## Fixed
- Nameplates: Design mode moves the DoT skull, health text, level, cast bar, spell icon and combo points too
- Nameplates: Enemy buffs you can purge also show in battlegrounds and arenas
- NPC window: Quest rewards on a first visit show their choices before you can hand in
- General: Little touches: long dropdown names show in a tooltip, and a clicked item's X in Daylight UI style

# DaylightUI 1.5.1.1

A mana regen sweep, a personal display with its own look, and BigWigs timers in Daylight UI style.

## New
- Unit frames: Mana regen sweep on your mana bar for the five second rule
- Unit frames: The personal display gets its own look, plus health and power numbers
- QoL: The loot feed can flip left and right
- Skins: BigWigs and LittleWigs timer bars in Daylight UI style
- Chat: Battle.net whispers get their own switch and color in a tab's Show window
- General: Battle.net login toasts in Daylight UI style, and they move with /dui unlock

## Fixed
- Party and raid: Joining a group in the middle of a fight shows everyone right away
- Quests: Share stays off in a fight, where the game blocks it, and comes back after
- General: Little touches: trainer spells for later keep full color icons, and switches on the Combat text page show your click right away

# DaylightUI 1.5.1

Forge, brew, workshop and sewing scenes for your crafts, and a target cast bar that slides out.

## New
- QoL: Forge, Brew, Workshop and Sewing: a scene and tide as your cast bar while you craft. /dui forge to try one
- Unit frames: The target's cast bar can slide out from under the target frame
- Professions: Rarity colors: recipe names colored by what they make instead of by skill-up
- QoL: Straight ends for the flight timer and the breath bar

## Changed
- Professions: Made unlearning a profession clearer

## Fixed
- Cooldown Manager: Slice and Dice, Rupture and Kidney Shot can show their buff or debuff
- Group finder: In a group, List yourself has your role
- Bags: Adding your own category works, and an empty one waits in your bag for items
- Chat: Right-clicking a name opens the player menu again
- Cooldown Manager: Icons no longer flicker to the game's spot on a new target
- Action bars: The leave vehicle button stays on its spot when another bar shows or hides
- Quests: A tracker opened in a dungeon stays open until you leave
- Cast bars: Spells show their display name, the same one the game's own bar shows
- General: Little touches: the threat meter's top, bag tutorials, chat tab counts and Chinese option names

# DaylightUI 1.5.0.1

Create and Create all work again in the profession window, plus fishing water.

## New
- QoL: Fishing water: calm water while your line is in, the tide as your cast bar, a splash on a catch. /dui fishing to try it
- Unit frames: New options: time left and stack count text sizes on buffs and debuffs

## Fixed
- Professions: Create and Create all work again
- Tooltip: Compare tooltips get the item's quality border, item level and ID lines

# DaylightUI 1.5

A second chat panel, scrolling combat text in Daylight UI style, and enchanting an item again and again.

## New
- Chat: A second chat panel with its own tabs, for loot, guild or a combat log
- Combat text: Scrolling combat text redrawn in Daylight UI style: three movable streams, crit light, spell school colors
- Action bars: New options: a lit border and a glow on a queued spell, like Heroic Strike
- Professions: Pick an item to enchant in the profession window, with an amount and Enchant all

## Changed
- Options: Font lists are in A to Z order, and long dropdowns glide with a scroll bar
- Little touches: Sell prices wear Daylight UI's coins, waiting mail is a simple envelope, and repeated error text glows softly

## Fixed
- Quests: A quest that progresses reaches the very top of the tracker, and untracking no longer leaves titles missing
- Threat: The threat meter, target tag and plate colors also work alone with a pet out
- NPC window: Spamming Space no longer closes a quest's reward page on a first visit
- Bags: The Disenchant button no longer misses clicks
- Unit frames: The swing timer's border goes around the bar, not into it
- Skins: The layering notice shows again

# DaylightUI 1.4.1.4

Sounds for your cooldowns, a fuller personal display, right-click fishing and French.

## New
- Cooldown Manager: Sounds per spell: when it's ready, when it turns usable, and when its buff lands, for procs
- Unit frames: The personal display is one angled piece under your feet and can carry your buffs, debuffs, cast bar and swing timers
- QoL: New option: right-click to fish with a pole equipped, putting on your best bait first
- Chat: Link tooltips can sit next to the chat, at the mouse or in the tooltip spot, and compare only on Shift
- Languages: French (first draft: corrections welcome on Discord)

## Changed
- Action bars: The stance, form or aura you're in lights up on the stance bar and the others go gray
- Cooldown Manager: Groups are made only with the + on a spell, dragging moves a whole group, and X and Y read from its middle
- General: Every area's Opacity slider now goes down to 0
- Party and raid: Joining a group builds far less, so it hitches less
- Quests: New option: turn off the quest tracker's tooltips
- Little touches: The leave vehicle button wears the action bars' look, and Enter or Space accepts an innkeeper's new home

## Fixed
- Quests: Clicking a quest in the tracker opens the quest log on that quest's page, not the list
- Mail: An addon's own mailing window, like TradeSkillMaster, keeps the mailbox open
- Skins: The dungeon journal's quest page stays readable
- Info panel: No more errors from the minimap in a fight or from addon buttons with masked icons

# DaylightUI 1.4.1.3

Your own short chat tags, new portrait ring colors, and a batch of fixes for chat, the bank and nameplates.

## New
- Chat: New option: Whispers button, to take the speech bubble off the top of the chat
- Chat: Give channels, guild, party and the rest your own short tags in a chat tab's Show window
- Unit frames: Portrait rings can take your accent color or the Daylight gradient

## Changed
- Spellbook: Training folds weapon skills under one row, out of Learn now and its total
- Little touches: A brighter edge on debuffs with no type, and the Window Skins card names only the windows it skins

## Fixed
- Bank: A character's first bank visit opens the bank with its free slots, not an empty window that says the bank is full
- Chat: The chat scroll keys (Page Up, Page Down, Shift+Page Down) scroll the Daylight chat box
- Chat: Shift-clicking a name shows its /who answer on the tab you're on, and so do the game's replies to anything you send
- Chat: A locked line in chat no longer causes an error when the spam note updates, and the note replaces itself instead of piling up
- Chat: Turning off the Chat copy button now removes the Copy icon from the top of the chat
- Tooltip: Tooltips no longer flicker over Dialogue UI's quest items
- Nameplates: Plates fix themselves after a layer or phase swap, and mobs that turn hostile keep their bars
- NPC: The vendor and mailbox windows make way for addons with their own, like TradeSkillMaster

# DaylightUI 1.4.1.2

Soft chimes for the things you just did, a quest log you can tune, and cooldowns that dim when you can't cast them.

## New
- Sound: Soft confirmation chimes when you apply talents, switch a talent set, learn a spell or send a letter
- Quests: The quest log on the map can change its sort order, text size, row height, opacity and what each row shows

## Changed
- Skins: Softer, cleaner lists in NeedRoll, the guild window and the collections journal
- Quests: Abandon in the tracker's right-click menu asks in a pop-up, no quest log needed
- Cooldown Manager: Spells you can't cast right now dim, and When not usable can fade or hide them
- Quests: The tracker's wheel glides like every other list

## Fixed
- Cooldown Manager: A buff missing glow always has its icon inside it
- Chat: Shift-clicking a Questie quest link puts a link that really sends into the box

# DaylightUI 1.4.1.1

DoT timers that stay right, your accent color on more of the UI, and buff settings for cooldowns like Bloodrage.

## New
- Unit Frames: Your health bar can wear your accent color
- Cooldown Manager: Cooldowns with a buff, like Bloodrage, get Buff up and Buff missing

## Changed
- Accent color: The character window, quest tracker and experience bar wear it by default
- Data texts: With a gradient accent, each number takes the next color along it
- Cooldown Manager: Buff up and Buff missing each have one Visibility setting
- Quests: A Questie icon under the mouse, on the map or minimap, spotlights its quest

## Fixed
- DoTs: Ticks are seen in a fight, so timers no longer end early
- NPC window: The immersive look always puts your camera back at your zoom
- Minimap: The addon drawer holds each real minimap button once, and map pins stay out

# DaylightUI 1.4.1

Chat tabs and whispers fixed, DoT timers that last to the end, and quest colors back.

## New
- Social: Battle.net friends show their ruleset: PvE, PvP, RP or RP PvP

## Changed
- Quests: Hovering a quest in the map's quest log spotlights it and its Questie icons on the map
- Quests: Abandon names the quest items it would destroy
- Unit frames: Your buffs and debuffs sit exactly where you place them
- Whispers: Conversations are narrower by default, and Invite shows only for someone on your ruleset

## Fixed
- DoTs: Timers last to the end, even when ticks land late or off rhythm
- Cooldown Manager: Hide (Buff up) works on every spell, in a fight too
- Nameplates: Quest marks and counts show again in a party
- Quests: Quests well above you show orange and red again
- Quests: Timed quests keep showing their time left once they're ready to hand in, and on their quest log page
- Chat: A tab's Show window lists the channels you're in, so any one can go on a tab
- Chat: Your own messages no longer glow as if someone said your name, and the sound for lit-up words starts off
- Chat: Tabs show their loot, XP and money again, more tabs than fit slide instead of overlapping, and a floating chat eases back under the mouse
- Chat: The glow behind a mention fades with its line, and group lines no longer get whisper or invite links
- Whispers: Battle.net friends' tiles show their name, and a new whisper's tile fades in over a floating chat
- Spellbook: A spell dragged over an action bar drops when you let go
- Fade: Someone joining your group brings faded party and raid tiles back
- Little fixes: NPC window, tooltips and Questie's map pins

# DaylightUI 1.4.0

A new chat box, an immersive NPC window, your bank from anywhere, and a UI that ripples in at login.

## New
- Chat: A new chat box in Daylight UI style, with whispers as conversations. Chat style: Classic keeps the old one
- NPC window: An immersive look: the talk beside the NPC, the camera over your shoulder. NPC window > Look
- Bags: Your bank from anywhere, plus your other characters' bags and banks. /dui bank
- Bags: A stronger search, item level on gear, a Disenchant button, locked items, and red icons on what you can't use
- Unit frames: A personal display at your feet: health, power and combo points. Unit Frames > Personal Display
- Reputation: Its own bar to place anywhere, and each new standing shows at the top of the screen
- Motion: The UI ripples in at login, your frames light up as fights start and end, and epic loot bursts in its color
- Languages: Russian, Simplified Chinese and Korean (first drafts: corrections welcome on Discord)
- Skins: NeedRoll, Deadly Boss Mods, Attune and OPie in Daylight UI style
- Spellbook: A Training tab with What's Training: what your trainer teaches next, and its cost
- Setup guide: New steps for action bars, nameplate size, and calm or always shown
- Plugins: Other addons can build on Daylight UI's frames (API.md in the download)
- Little touches: Right-click equipment sets, an Options button on each piece in unlock mode, campfire smoke

## Changed
- Options: A new Home page, long pages in tabs, and a description on every setting
- Unit frames: Elites, rares and bosses get a dragon on their portrait and nameplate
- Fade: Float and Fade are one Visible setting; Show with a target can count only enemies
- Quests: Map marks are left to Questie, in Daylight UI icons: far less memory
- Quests: The log's tooltip sits beside the log, and hovering a quest on the map lights its row in the log
- Motion: More of the UI moves smoothly: numbers count, lists glide, menus drop open
- Performance: Lighter on the game everywhere, and less memory at login
- Bags: The footer shows profession bags' free slots
- Profiles: The Leveling preset is now called Immersive Preset

## Fixed
- Settings: Module settings are no longer lost after the setup guide or a profile update
- Mail: Fixed a rare bug that could send gold twice or delete the wrong letter; Collect all no longer gets stuck
- NPC: Fixed rare bugs that could give the wrong quest reward or train the wrong rank
- Spellbook: Fixed a rare bug where a click after scrolling could cast the wrong spell
- Quests: Tracker chat links, Abandon and quest item buttons in combat work properly
- Skins: RestedXP's guide no longer slows the game down
- Little fixes: Options, unit frames, nameplates, action bars, bags, chat, inspect, group finder, social, professions, windows, sound, pop-ups and more

# DaylightUI 1.3.1

Float your UI away out of a fight, name suggestions in the mail, and a round of quest fixes.

## New
- Fade: Float: any part, or the whole UI, fades away out of a fight (General > Fade)
- Mail: The To box suggests names as you type: recent, your characters, friends and guild
- Bags: Soul Shards show as one stack with a count

## Changed
- Fade: In combat dims as soon as a fight starts and eases back after
- Tooltip: Tooltips fade in softly
- Quests: Choose how long the quest progress pop-up stays, on Quests > Tracker

## Fixed
- Quests: The All / This zone buttons no longer ride up over the minimap
- Quests: The ? where a ready quest is handed in is back on the world map
- Quests: The journal's quest tooltip works with Questie's tracker picked
- Legacy: Each tree shows its own points spent, not all three trees' total
- Loot feed: With border and background off, no lines or shadow are left under the rows

# DaylightUI 1.3.0

A thank-you page for our donators, all your mail in one press, and a chat that scales.

## New
- Options: A Top donators page thanking the players who support Daylight UI, with the Ko-fi link

## Changed
- Mail: Collect all takes every letter in one press
- Chat: The Scale slider sizes the game's docked chat windows too
- Setup guide: New setups start with the chat floating and quest turn-ins shown on the map
- Quests: Elite, Dungeon, Raid and PvP tags are slanted boxes in Daylight UI style
- General: Little touches: menu ticks and picks take your accent color

## Fixed
- Setup guide: The layout you pick is the one you get, even on an account with changed profiles
- Unit frames: The party and raid dispel glow no longer covers the portrait
- Bags: Items from mail show their icon without a hover
- Action bars: An empty totem bar no longer leaves a dot in the middle of the screen
- Skins: No more options warning at login about the Other addons switches

# DaylightUI 1.2.0

Quests come alive on the map, a town finder, other addons in Daylight UI style, and health numbers your way.

## New
- Quests: More on the map: nearby quests, patrol paths, coordinates and your group's objectives
- Quests: Map marks and nameplates show what a quest wants: kill, loot, use or explore
- Quests: The town finder: innkeepers, flight masters, mailboxes and more. Quests > Map
- Quests: Hide the game's blue quest areas and quest icons. Quests > Map
- Quests: A right-click menu on tracked quests, your own clicks, and more tracker options
- Skins: Other addons in Daylight UI style: Ace3 options, RestedXP guide, dungeon journal
- General: Health and power numbers your way: short, more exact or in full
- QoL: Skill-ups in the loot feed, which gets its own options page
- Cooldown Manager: Show a spell only while its buff is up; shields show what's left
- Cooldown Manager: Hide duration swipe on buff icons

## Changed
- Quests: With Questie, choose our quest tracker or Questie's
- Cast bar: Crafting a stack (like 50 bandages) shows one bar for the whole batch, with a count

# DaylightUI 1.1.1

Small fixes: smoother sliders, no more "?" spells in the Cooldown Manager, tidier window titles.

## New
- Cooldown Manager: Only when usable: a spell shows only once you can cast it, like Riposte or Overpower
- Character and NPC windows: Drag them by their header; right-click it to put them back

## Fixed
- Options: Dragging a slider on a page with a preview no longer stutters the game
- Cooldown Manager: No more "?" Unknown spells in the tray
- Skins: Window titles no longer sit on the accent line
- NPC window: A quest from a poster or item shows the quest book, not an empty ring

# DaylightUI 1.1.0

Name tabs you can style on the unit frames, plus fixes for chat, the group finder and the world map.

## New
- Unit frames: The name tab gets its own border, corners, shadow, angle, position and width on the player, target, focus and party frames

## Changed
- Quests: Quest givers on the map use far less memory
- World map: Maximized, it's one slim title row with more room for the map

## Fixed
- Chat: Whisper tab names no longer spill over each other
- Group finder: Picking an activity filters the shown groups again
- Quests: No more error when sharing the map pin with the world map open
- Unit frames: No more black wedges in the portrait ring

# DaylightUI 1.0.1

Bug fixes for the totem bar, the Cooldown Manager and target cast bars.

## New
- Unit frames: Hunters: an Auto Shot stop-moving line and the target's range on the ranged swing bar

## Fixed
- Action bars: The totem bar stays where you put it when a fight starts or ends
- Cooldown Manager: Spells without a real cooldown (Moonfire, Rend) show their debuff or buff while it's up
- Unit frames: Target and focus cast bars above or below the frame match the frame's width

# DaylightUI 1.0

Daylight UI 1.0: a big speed boost, social and Legacy windows, raid frames by size, leader tools and quest help everywhere.

## New
- Social: Friends, recent allies, friend requests and the raid in one window in Daylight UI style
- Legacy: Legacy Points, rewards, challenges and the Legacy trees in one window in Daylight UI style
- Unit frames: Separate raid frames for 10, 20 and 40 players, swapped as the raid grows
- Unit frames: Ribbon, a second frame style: a slim bar with a thin power line
- Unit frames: Leader tools: ready check, role check, pull timer and markers, with answers on group frames. /dui leader test
- Quests: Quest givers' tooltips list their quests; with QuestieDB, your quests' targets dotted on the map
- Damage numbers: Scrolling combat text options: direction, font, sizes and which messages show
- Quality of Life: Error messages in Daylight UI style; by a campfire, fade everything and float the chat
- Setup guide: A Questing page in the tour

## Changed
- Performance: A big speed boost across every module, so big raids and battlegrounds stay smooth
- Options: A full review before 1.0: overlapping settings merged, clearer labels
- Skins: The guild window in Daylight UI style, all the way through
- Windows: A window opening over another slides it aside, and back once it closes

## Fixed
- World map: With Questie on, no more doubled ! and ? on the map and minimap
- Minimap: No more blank map in cities after a loading screen or /reload

# DaylightUI 0.11.3

A quest marker in the world, ! and ? on the map, shield bars that drain with the shield and new map icons.

## New
- Quests: A quest marker in the world in Daylight UI style, with breadcrumbs on the ground; with QuestieDB, smart routing to the nearest objective and a quest arrow
- World map: With QuestieDB, quests to pick up and hand in show as ! and ? on the world map and minimap, with Questie-style display options
- Cooldown Manager: Shield bars: Power Word: Shield, Mana Shield, Ice Barrier and the Wards drain with the shield left instead of the time, on your friendly target or yourself
- Cooldown Manager: Each spell its own text sizes and colors: cooldown numbers, stacks, a bar's name and time
- World map: New icons by Wawis for dungeons, raids, flight masters, boats and zeppelins
- Unit frames: The level badge moves anywhere in Design mode
- Skins: Auction house item icons in Daylight UI style, edged in their quality color

## Fixed
- Chat: Messages fade after 8 seconds only while chat is floating
- Chat: No more errors from the game's chat on system and skill lines
- Cast bars: Crafting shows like any other cast instead of grayed out
- Action bars: A bar background with its border off is a plain panel, no dark rim
- QoL: The loot feed's stack count no longer gets stuck huge and blurry
- Character window: The footer no longer hangs over the window's bottom edge
- Skins: The breath bar's border no longer covers the bar on smaller screens

# DaylightUI 0.11.2

Our own mailbox with a gold ledger, heal indicators on group frames, a live nameplate preview and plugins.

## New
- Mailbox: Mail, sending and a gold ledger in one window in Daylight UI style, for mail and auction house profits
- Unit frames: Heal indicators: colored squares for your heals over time and shields on party and raid frames
- Unit frames: Party pets: a small bar beside each party member's frame (Party page)
- Unit frames: Each frame its own bar colors, border, shadow, name and level spots, and extra texts
- Nameplates: A live nameplate preview on every nameplate page: Design mode moves and resizes its pieces
- Nameplates: Six more interrupt animations and "Kicked by" with who interrupted, on cast bars too
- Appearance: Bar backgrounds, and each area its own bar textures and fonts
- Appearance: Six new bar textures: Silk, Glass, Tube, Slant, Brushed and Grain
- Fade: Show with a target: anything that fades can come back while you have a target
- Plugins: Plugins and profile packs: other addons can add options sections and ready-made setups
- General: Little touches: the loot window and compare tooltips in Daylight UI style, calendar and tracking in the minimap drawer

# DaylightUI 0.11.1.1

Auras that hold up in battlegrounds, enemy tooltips that stay up, crafted items in the loot feed and real costs at vendors.

## Fixed
- Tooltip: An enemy's tooltip shows while the mouse is on it again
- QoL: The loot feed shows crafted items, and gold the moment you loot it
- Vendor: Items paid in items or currency show their real cost, and how many you hold
- Unit frames: Raid, party, target and player auras keep their size, timers and swipe in battlegrounds, and the dispel icon shows there
- Unit frames: Big battlegrounds no longer stall while the raid fills up

# DaylightUI 0.11.1

Our own group finder window, a loot feed, loot rolls in our look and windows you can make bigger.

## New
- Group Finder: Finding a group, listing yourself and the who list in one window of ours
- QoL: A loot feed: what you loot slides in at the bottom right
- Skins: Loot rolls and the dressing room in our look; our buttons and titles on every game window
- Windows: Drag a window's corner to make it bigger: more room, more rows
- General: Window background opacity for every window at once
- Professions: Your profession spells in a row under the recipes; the window works in fights too
- Chat: Messages fade after 8 seconds each in floating chat mode
- Nameplates: An interrupt slices the cast bar in two, and threat breathes on the bar
- Nameplates: Execute range styles: a band, a line, the whole bar or a breathing band
- Auras: Debuffs you can dispel on a friendly target glow and come first
- Unit frames: Party and raid auras can show a clock swipe instead of numbers
- World map: Map symbol scale and opacity, and the other faction's flight masters
- General: Little touches: the target frame eases in, new chat lines fade in, window portraits flare as they open, more boat and zeppelin routes on the map, a raid marker size

## Changed
- Defaults: Faster looting and nameplate execute range are off by default

## Fixed
- Tooltip: Unit tooltips hidden in combat no longer flash for a moment

# DaylightUI 0.11.0

Our own chat and inspect windows, a look per action bar, a deeper Cooldown Manager and color-coded item stats.

## New
- Chat: A calmer chat window of ours: floating chat, a tab per whisper, every message color in the options
- Inspect: Inspecting someone opens a window of ours: gear, item level, enchants and talents
- Tooltips: Short, color-coded item stats: "+1% Hit", "+12 Spell Power"
- Action bars: A look per bar (shapes, borders, cooldown shade) and a Bind keys button
- Cooldown Manager: More icon and bar options, groups that show only when they matter, one Seal spell for paladins
- Unit frames: A free-standing power bar, and Add piece in Design mode for extra texts and aura groups
- Nameplates: Execute range, badges for pets and totems, other plates fade behind your target, a raid marker size
- Party and raid: Your target's tile gets an outline; dispellable debuffs glow in their color
- Auras: Enemy buffs you can purge or steal glow on the target frame and nameplates
- World map: Dungeon and raid entrances, flight masters, boats and zeppelins
- Scale: Size any frame on its own in unlock mode; Ctrl + scroll sizes any window
- General: Little touches: quest type tags, a damage meter Report button, Enter accepts the game's pop-ups

## Changed
- Cooldown Manager: Livelier spells: proc glow in your color, a shine when ready, buffs sliding in
- Info panel: Reputation now lives in the XP bar, which gets its own colors and segments
- Talents: Talent rings fill with their ranks, and Apply rolls a wave of gold light

## Fixed
- Minimap: No longer blank after logging in or a /reload in a main city
- Class colors: A class-color addon's colors now show everywhere
- Profiles: An imported profile keeps your own window spots
- Timers: Buff and totem timers no longer flash "0s" in their last second

# DaylightUI 0.10.2

Buttons and colors unified, per-spell missing buffs and a minimap that always shows.

## Changed
- Look and Feel: Unified buttons and colors
- Cooldown Manager: Show when missing is per spell now, with Glow when not active and Hide when active: see Battle Shout only when it's down
- Character: Gear slots wear the bags' soft quality outline

## Fixed
- Minimap: The minimap no longer stays blank after logging in, a /reload or a loading screen

# DaylightUI 0.10.1.2

Bank slots on the first visit, steadier bags and no doubled minimap addons.

## Fixed
- Bags: Stacks no longer pop up in odd places after you sell or bank something with the bags open
- Minimap: Addons no longer show twice in the minimap's addon drawer
- Bank: The bank shows its slots on the first visit, and buying bank bag slots works again

# DaylightUI 0.10.1.1

Roomier talent trees without retired talents, the vendor's buy cursor back, and small fixes.

## Changed
- Character: The PvP tab shows before your first rank too, as in the game's window

## Fixed
- NPC window: The vendor shows the game's buy cursor over its items again
- Talents: Roomier trees, Priest and Hunter trees no longer show retired talents, and the Apply button fits in every language
- Skins: The professions book's skill bars lose the stray box at their end

# DaylightUI 0.10.1

A Pet tab in the character window, our spellbook on for everyone, and buffs that slide in and out.

## New
- Character: A Pet tab for hunters and warlocks: your pet's model, level, mood and stats

## Changed
- Spellbook: Our spellbook and talents window is now on for everyone and can be dragged by its top bar (switch it off on /dui > Extras > Spellbook)
- Buffs: Buffs and debuffs slide in as they land and lift away as they leave, instead of the glow
- Tooltip: Spell and talent tooltips in our warm colors, costs and numbers colored, in fights too; our own tooltips easier to read, the accent only on the clicks

## Fixed
- Talents: Hunter talents show again instead of tiny dots
- Action Bars: Shooting a wand no longer makes every button pulse as if it came off cooldown
- Minimap: The addon drawer leaves map pins (Questie, HandyNotes) on the map, and hovering an addon menu entry no longer errors
- Buffs: Shaman imbues, oils, stones and poisons put on in a fight show on the buff bar at once, and right-clicking an imbue no longer errors

# DaylightUI 0.10.0.2

Bags stay put while you sell, the totem bar can be moved again, and minimap clock text size.

## New
- Info panel: Text size for the minimap's clock and framerate, on Info Panel > Minimap

## Changed
- Bags: Items sold or used leave their slot in place until the bag is reopened, so nothing jumps under the cursor while selling

## Fixed
- Action Bars: The shaman totem bar gets its handle in unlock mode again
- Layout: Unlock mode's Lock and Snap buttons sit on a dark bar again, readable over any scenery
- Character: The Equipment sets button lights up and clicks like the rest

# DaylightUI 0.10.0.1

No more error hovering action bar spells in a fight, plus recipe and profession window fixes.

## New
- Quests: Scale for the quest progress pop-up, on Quests > Tracker

## Changed
- NPC window: Profession trainers show each recipe in its item's quality color

## Fixed
- Skins: The profession window's skill bar is back, and the recipe's icon has a clean ring in its quality color
- Tooltip: No more error hovering action bar spells in a fight; recipe tooltips show their item in the game's own colors again

# DaylightUI 0.10.0

Our own spellbook and talents window, any class spell in the Cooldown Manager, campfire firelight, class-colored portrait rings and warmer text.

## New
- Spellbook: Our own spellbook and talents window: all three trees at a glance, builds you keep
- Cooldown Manager: Any spell or buff of your class, and group buffs, can go in your layout
- Quests: Quest kills and items show as a small line with a progress bar, in place of the game's yellow text
- Unit frames: Portrait rings in the unit's class gradient, elites' too; a pulsing red ring means it's attacking you
- Quality of Life: Sit by a campfire: firelight, embers and a soft crackle while your bars fade. /dui campfire to try it
- Unit frames: Hide the power text while it's full, like the health text

## Changed
- Look: Warmer text, the numbers that matter in your accent; spell tooltips color heals, damage and mana
- Appearance: Your class gradient is the default accent, and buttons are a quiet warm outline
- Cooldown Manager: Every look setting is on the spell card's Look tab
- Skins: The world map's top is one slim row
- Info panel: A first-time setup starts with the panel closed: its left tab opens the damage meter
- Options: Search shows the section you're on first; skins and our windows are pages under Extras

## Fixed
- NPC window: Shift-click at a vendor asks how many to buy, Accept is back on the left, and vendor items no longer open too small
- Info panel: More addons' minimap buttons go in the drawer, each once, and the minimap no longer goes blank indoors
- Quests: The quest log's Show on map button fits again, and Shift-click tracks a quest again
- Buffs: No second weapon in a weapon buff's tooltip, and a faded buff bar no longer flashes
- Chat: The typing box follows the chat's text size and outline
- Appearance: Bars in the Daylight gradient keep the bar texture you picked
- Bags: Buying a bank tab works again
- Skins: No more stray bar piece over the recipe's icon in the profession window

# DaylightUI 0.9.2

The world map's quest log in our look, a resizable map that can show unexplored areas, quest levels in the tracker and Cooldown Manager fixes.

## New
- Quests: The world map's quest log in our look: hover a quest to light its area, each quest on its own page with Track, Share and Abandon, right-click menus too
- Quests: Quest levels in front of the tracker's titles, like [15] (Tracker > Text)
- Skins: Resize the world map from its bottom-right corner; it keeps its size and spot
- Skins: Show the world map's unexplored areas, dimmed (Window Skins > World map)
- Cooldown Manager: Show a spell only while it's on cooldown: When ready on the spell's card, Show tab

## Changed
- Quality of Life: The level-up screen is shorter: about 7 seconds
- Setup guide: Until it's finished, a Finish setup button reminds you that changes aren't saved yet
- Unit frames: The DoT kill shading has an angled end like the health bar's, on nameplates too

## Fixed
- Quests: The quest tracker stays where you moved it after a reload
- Cooldown Manager: Every cooldown shows and can fade, hide or glow, plus layout and editor fixes

# DaylightUI 0.9.1.1

Bug fixes: bags open without a freeze, buff timers, the chat typing box, tooltips and the click-cast switch, plus clearer option names.

## Changed
- Options: Clearer names and descriptions on many settings

## Fixed
- Bags: Opening the bags no longer freezes the game for a moment
- Buffs: Turning off Time left hides the buff timers again
- Chat: The typing box matches the chat's size and spot on every tab
- Tooltips: World tooltips vanish at once when the mouse leaves (unless Fade out is on)
- Unit frames: The spellbook's Click-cast switch can be clicked again

# DaylightUI 0.9.1

A new NPC window for talking, vendors and trainers, damage number styling, DoT kill shading and lots of small touches.

## New
- NPC window: Gossip, quests, vendors and trainers in one window of ours. /dui npc to try it
- Damage numbers: Style the game's damage numbers: font, presets, spread. /dui > Damage numbers
- Appearance: 48 new fonts
- Unit frames: Your DoTs' damage left shows on your target's health, with a skull when it's enough to kill. On nameplates too
- Unit frames: Buffs and debuffs on the player frame (off by default)
- General: A Fade page with every part's fade settings in one place
- Appearance: Class gradient accent color
- Quality of Life: A new zone title and level-up animation
- Quality of Life: A soft tick when you press a button too soon, instead of the game's voice line
- General: Little touches: quest-ready sheen and chime, new loot shine, combo point sparks, "Kicked" tag on interrupts

## Changed
- Unit frames: Aggro fills the portrait ring in red
- Cooldown Manager: Can be switched off to keep the game's own
- Sound: Pick ours, the game's or none for each kind of UI sound
- General: Character and options windows animate more smoothly
- Skins: Buttons in the game's windows light up on hover
- Quality of Life: Auto accept leaves PvP quests to you

## Fixed
- Tooltips: Cursor tooltips no longer flash at the default spot first
- Action bars: Buttons light up again when you walk into range

# DaylightUI 0.9.0.1

Bug fixes: no more crash on /reload, heal bars, drinking after the bank, nameplate gather icons, plus glow-when-usable for cooldowns.

## New
- Cooldown Manager: Glow when usable: a spell can glow while you can cast it and it's off cooldown, like Revenge after a block, dodge or parry, Overpower after a dodge or Execute on a low target. On the spell's card in /cdm, Alerts tab

## Fixed
- Nameplates: The game's interaction icons (the pick over ore, the hand over herbs) show again with our nameplates on
- Action bars: Fixed a full game crash (BC_ASSERT) on /reload with our action bars on
- Unit frames: Incoming heal and shield bars show again on raid and party frames that hadn't been sized yet when they were set up (e.g. someone joining mid-fight)
- Bags: Using a drink, food or potion from your bags after a bank visit no longer says "the game blocked UNKNOWN()"

# DaylightUI 0.9.0

A big one: lay out your cooldowns right on screen, a threat meter, a second damage meter, data texts under the map, click-casting, boss debuffs on your frames, a missing-buffs reminder, a soft AFK screen and a Leveling profile.

## New
- Cooldown Manager: Lay out your cooldowns right on screen: /cdm opens an editor where you drag spells from a tray, snap them to each other, your frames or the grid, and set each one's look on a card beside it. Any spell can be an icon or a bar the game fills (a cooldown fills as it comes back, a buff empties as it runs out), with its time and stacks. Your old layout moves over by itself
- Threat: In a group, see who's about to pull: a threat meter slides out of the damage meter in combat (who's closest, with a pull line; or under the meter, or in its own window), the target frame shows your threat % and turns orange as you near the pull, and nameplates go orange first (tanks: loose adds in red). Its own page: /dui > Info Panel > Threat meter
- Info panel: A second damage meter: healing beside damage (or any two modes) at once, in its own window you can move and resize (/dui unlock), with its own mode, fight, size and colors (off by default; /dui > Info Panel > Second meter)
- Info panel: Data texts: a thin strip under the minimap with your gold, gear durability, free bag space and friends and guild online, or framerate, time, XP or coordinates. Hover one for details (gold on all your characters, each piece of gear, each bag, who's online), click it to open its window (on by default; /dui > Info Panel > Data texts)
- Unit frames: Click-casting: switch on Click-cast at the top of your spellbook (or Bind in spellbook on /dui > Unit Frames > Click-casting) and click a spell with any mouse button, plus Shift, Ctrl or Alt if you like, to cast it by clicking your player, target, focus, pet, party and raid frames. Kept per character and talent set, nothing bound until you bind it; Clique wins when it's loaded
- Unit frames: Special boss debuffs that addons normally can't show now appear on our frames: big icons in the middle of party and raid frames, and under your own debuffs. You'll only see them when a boss uses them (on by default; Boss debuffs on the Party, Raid and Debuffs pages)
- Unit frames: You can ping our unit frames (yours, target, party, raid and the rest) with the ping key, just like the game's own frames
- Buffs: Missing group buffs: on a ready check, and when you enter a dungeon or raid with a group, a calm line lists the buffs you lack that someone in your group can give; each one leaves as its buff lands, or close it with its x (on by default; /dui > Buffs & Debuffs > Buffs; move it with /dui unlock)
- Quality of Life: A soft AFK screen: when you go away the world dims, the UI fades and your character stands beside a card with your zone, XP, rested, time away and a fun fact that changes every few seconds; move or press any key to come back. Never in combat (on by default; /dui > Quality of Life, /dui afk to preview)
- Profiles: A Leveling profile, calm for questing: out of combat your bars dim and your own frame fades away at full health, the damage meter starts folded (click its tab to bring it out) and the minimap is a bit smaller, yet everything shows in dungeons, raids, battlegrounds and arenas. Pick it in the setup guide's Quick setup or under Profiles > Ready-made. That last part works on any profile: Fade only in the open world (/dui > Appearance > Fade)
- Quests: Quest details in our look: right-click a quest in the tracker, then Quest details, for a card beside it with the quest's text, objectives and rewards, even in combat
- Quests: The quest you're working on comes first: when a kill or item counts, an objective is done or it's ready to hand in, it glides to the top of its zone and stays there after a reload (on by default; /dui > Quests > Tracker)
- Character: Enchants show as a soft green line under each item, the window has its own First and last names switch (on; /dui > Character), and folding a group (stats, reputation, skills, currency) animates smoothly
- Quality of Life: Flight timer: on a flight path, a bar at the top of the screen shows where you're going and the time left, learned from your own flights (on by default; /dui > Quality of Life > Travel; move it with /dui unlock)
- Quality of Life: Quiet error messages: the red "Not enough rage", "Spell is not ready yet", "Out of range" and "You have no target" spam is hidden; bags full, loot, interrupted and quest messages still show (on by default; /dui > Quality of Life > Error messages)
- Tooltips: Item level on weapon and armor tooltips, and spell and item IDs at the bottom (both off; /dui > Tooltips > Extra lines)
- General: Move the loot window with /dui unlock (takes one /reload after moving it); the "You won" loot toasts move with the Alerts handle, now called Alerts & Loot Won

## Changed
- General: Our own tooltips are easier to read: words in your accent color, quest objectives graded red to green, money in gold and each click hint on its own line
- General: Smoother play: fading frames, colored borders and the quest tracker use less of your computer
- Tooltips: Unit tooltips show in combat again by default. With Hide in combat on (/dui > Tooltips > In combat), hold Shift to see one, and it no longer lingers after the mouse leaves
- Unit frames: The hit and heal trail is gone: health bars simply glide to their new value (/dui > Appearance > Smooth bars)
- Options: The Party page's preview shows one member with every piece (crown, role, marker, dispel, every aura group), like the Raid page, so it's clear what you drag in Design mode
- Info panel: With our quest tracker off, the game's tracker keeps its own look and is only placed under the panel

## Fixed
- Cooldown Manager: Looking at your other talent set's layout no longer switches the one you play with; spells in an "Only in combat" group stay hidden out of combat; buff bars no longer cause error pop-ups, and bar times read 2:58, or just 9 under a minute, in combat too
- Unit frames: Target and focus casts you can't interrupt go gray in boss fights, keystones and battlegrounds too; preview frames show your last name when it's on
- Raid frames: Someone who joins mid-fight shows their buffs and debuffs right away, and the move handle fits the frames you show
- Buffs: On German, French, Spanish, Russian, Chinese and other game languages, buffs sort into their groups instead of all landing in Other; buffs gained in a boss fight or battleground sort as soon as it ends; a buff moved into Weapon no longer vanishes; debuff edges use the dispel colors from the unit frames' Colors page; the preview no longer shows the real bar through it
- Quests: The tracker follows the minimap's Size slider at once, and Reset puts it back under the panel; quest titles take the quest log's colors again (gray to red by level) and change as you level
- Character: Resistances no longer all show as buffed, armor goes red under Sunder, an equipment set picked in combat equips when it ends, stat folds are kept per character, item icons no longer wash white as the window fades; hovering a stat shows the game's full tooltip in your language
- Bags: Junk selling never sells a gray item in an equipment set or a quest item; a split stack lands as its own stack at trade, mail and the auction house; the bank works without first opening it with the addon off, and right-click puts an item in the bank tab you see; guild repair pays from your own gold when the guild bank is short; the bag and bank windows rise in softly again, without a stutter
- General: Text size, outline and Shadow now reach keybinds, cooldown numbers, bag counts, buff timers, skinned windows and menus; a new font, accent or bar texture shows everywhere at once, no /reload needed
- Profiles: Renaming a profile works properly, even when only the capital letters change; importing a broken profile string can no longer leave frames missing
- Options: Search in the options no longer shows empty cards, and its result counts are right; in Design mode a dragged piece lands where you let go instead of creeping further out with every drag
- Setup guide: The Custom accent swatch and bar textures update as you pick; running the setup again no longer slows things down
- Action bars: Unlock mode no longer shows handles for bars set to Hidden (bars 5-8 to start with), the totem bar on classes without totems or the stance bar without forms; the Proc border options are gone (WoW: Forever has no proc glows)
- Quality of Life: Train All never learns a new profession, stays off at pet trainers, and shows after a /reload at a trainer
- Skins: A quest opened from the map's quest log has light, readable text again when "Talking to NPCs" skins are off

# DaylightUI 0.8.3

The biggest performance update yet: rebuilt nameplates with the same look, and the whole UI does far less work, so crowds, raids and battlegrounds play much smoother.

## New
- Quality of Life: Quest items you can loot out in the world sparkle, so they're easy to spot. This turns off the game's outline on what you point at (off by default; /dui > Quality of Life > Items)
- Unit frames: Party and raid aura timers can show only under a minute, so long buffs stay quiet (each aura card: Only under a minute)
- Action bars: Bag bar size and Micro menu size sliders (/dui > Action Bars > Bag bar and micro menu)

## Changed
- Nameplates: Rebuilt for speed with the same look: far cheaper to draw, and smooth when switching targets in a crowd. Your target's plate grows in one step, and its outline draws on with a soft gleam. A big pull never builds plates mid-fight
- Unit frames: Smoother raids: raid frames do far less work on threat, roster and health changes
- Action bars: Less work on every cast, target switch and camera turn, Cooldown Manager included
- Info panel: The meter, map and clock only redraw what changed, and pulls no longer rebuild the panel
- Buffs: The buff bar does far less work in the background
- Bags: Fewer hitches with the bags open while casting or questing
- Tooltip: Smoother hovering over units and items
- Quests: The tracker does less work as quests update
- General: Chat, the character window, skinned windows and fading areas all do less work

## Fixed
- Battlegrounds: Enemy players show their class colors again on unit frames, cast bars and the tooltip
- Info panel: Rotate minimap stays on after a reload or logout
- General: Moved bag bar, micro menu and game frames stay where you put them when you level up or change talents
- Character: An empty ammo slot shows as empty, not as a gray box with a 1

# DaylightUI 0.8.2.2

Smoother play with nameplates on: less of a hitch when you switch targets or hover units, and the frame rate should no longer sink over a long session.

## Fixed
- Nameplates: The frame rate should no longer sink over a play session as you switch targets (only a restart brought it back): your target's plate now grows through the same few sizes every time
- Tooltip: Hovering a unit costs fewer frames: the tooltip is only moved when its spot changes, not every frame
- Buffs: Fewer random hitches: a change to your buffs no longer re-reads every buff and every spell the bar knows when no group is consolidated (that work made garbage the game had to clear)
- Action bars: Less of a hitch when you switch targets: the bars find the buttons whose range changed directly instead of checking every button for every slot, and only those buttons are redrawn

# DaylightUI 0.8.2.1

Healers' party and raid frames fade out of range at your heal's real range, and your ammo shows in the character window.

## Fixed
- Unit frames: Out of range fading on party and raid frames now uses your heal's real range (Priest, Paladin, Shaman, Druid), so members you can still heal at 40 yards no longer fade
- Character: Your equipped arrows and bullets now show in the ammo slot (it said Empty)

# DaylightUI 0.8.2

Raid frames show debuffs and crowd control with one-click Quick looks, Design mode on every frame page, soft UI sounds, frames that snap to each other, and smoother nameplates in crowds.

## New
- Options: Design mode: switch it on at the top of any frame page, then drag pieces of the preview to move them and pull their grips to resize them. Every frame preview also has a Zoom slider (up to 4x)
- Raid frames: Debuffs, crowd control and buffs on raid tiles, each placeable anywhere on or beside the tile with optional timers; Quick looks set up Healer, DPS / Tank, Battleground or Minimal in one click; the Raid page has a live preview (Unit Frames > Raid)
- Unit frames: Combo points: above the frame or across it, with more colors (a shade along the row, class color, a color per point) (Unit Frames > Extras > Combo points)
- Nameplates: Combo points on your target's plate, above or below the bar, fully adjustable, in your unit frame combo colors (Nameplates > Target)
- General: Soft UI sounds in place of the game's clicks (General > Sound)
- Layout: Frames snap to each other's edges and centers while moving, with a guide line (hold Shift to drop anywhere)
- Buffs: A buff's timer warms up in its last 5 seconds, and new buffs glow softly as they land
- Action bars: Totem timers can be switched off, made see-through and faded (Action Bars > Bar Layout)
- Info panel: Damage meter names can be any color
- Options: Switches for Motion effects, Ping when ready, Count gold changes and XP gain effects

## Changed
- Unit frames: Target, party and raid auras, names, icons and cast bars can sit at any spot on or around the frame, with nudges; your current layout is kept
- Raid frames: Tiles up to 80 tall, power bars up to 20, up to 40 tiles per line
- Nameplates: Smoother in crowds: cheaper to draw, and your target glides to its size while the others stay put
- Action bars: Pressed buttons spring back, and range and power tints fade instead of flicking
- Minimap: The addon drawer opens from the map's bottom-right corner and holds the game's addon menu too
- Quests: Click a zone name to fold its quests
- General: Errors are reported once (then at 10, 100, 1000) instead of flooding the screen

## Fixed
- Nameplates: Much less stutter turning the camera or switching targets in a crowd
- Raid frames: Dispellable debuffs show in battlegrounds again, and settings changed during a battleground or boss fight apply once it ends
- Unit frames: Moving health or power text no longer errors in combat or battlegrounds
- Skins: The friends list is in our look again, and side tabs no longer show a tinted block
- Quests: No more big black box under the minimap, and no error from item cooldowns in restricted fights
- Setup guide: No longer reappears on characters already set up, or writes a debug log at login
- Appearance: Scrolling combat text no longer spaces its letters out with the game-text font on
- Chat: The Copy window opens at the newest lines
- Cooldown Manager: /dui cdm place says which new block it filled

# DaylightUI 0.8.1.1

A small update: class colors for enemy players in battlegrounds, a raid frame error fixed, quest counts on nameplates, and the zone name on the minimap.

## New
- Nameplates: Quest targets show how far along you are (4/10) beside the gold ! (switch: Quest count)
- Minimap: The name of the area you're in shows at the top of the minimap, above the coordinates (switch in Info panel > Minimap)

## Fixed
- Nameplates: Enemy players in battlegrounds have their class colors (or class gradients) on the health bar again instead of gray
- Nameplates: Enemy players' names and guilds in battlegrounds use your class colors too, the same as anywhere else
- Raid frames: No more "ClearAllPoints" error after changing a setting with the raid tiles' dispel tint in use

# DaylightUI 0.8.1

An Opacity slider for every fading area, coordinates on the minimap, and tooltip cursor offsets.

## New
- Minimap: Your x, y coordinates show at the top of the minimap (switch in Info panel > Minimap)
- General: Every unit frame, action bar, the buffs, chat, info panel and quest tracker get their own Opacity slider (in their "Opacity & fade" card): set the target to 50% and it stays at 50%, fading out and back to 50%
- Tooltip: With Position "At the cursor", two sliders set how far left/right and up/down the tooltip sits from the cursor

## Fixed
- Profiles: On Korean and Chinese clients, a new profile keeps "Use my language's font" off if you turned it off (it came back on after a reload)

# DaylightUI 0.8.0.1

A quick fix: professions no longer show twice on the Skills page.

## Fixed
- Character: The Skills page no longer lists each profession and secondary skill twice

# DaylightUI 0.8.0

DaylightUI's own character window, raid frames in a party, and our own flat icons.

## New
- Unit frames: New option: Use in a party. Your raid frames show in a party too, in place of the party frames (Unit Frames > Raid).
- Icons: Our own flat raid markers, coins, role icons and status icons
- Character: DaylightUI now draws its own character window. Item names beside their icons, an ammo slot with its count for classes that use ammo, a model you drag to turn, stats in plain words, repair warnings, titles and equipment sets, plus Reputation, Skills, PvP, Statistics and Currency pages, with a real fade. Part of DaylightUI, no extra addon: to keep the game's, switch it off in /dui, Character.

## Changed
- Unit frames: The target's raid marker is bigger, in step with the bigger frame
- Character: More color: a soft glow behind your character (closer in, rising in with the window), stat headers bigger and each in its own color, striped rows, thicker bars, a colored item level and durability, your first and last name, a snugger layout; new Colors options in /dui, Character
- Character: The line under the open tab (Character, Reputation, Skills...) is in your class gradient; pick another color in /dui, Character > Colors > Tab underline
- Character: Your character is no longer cut off at the sides (it can reach out behind the gear columns), starts a bit smaller, and scrolls out far enough to show the feet
- Character: New option: switch off the glow behind your character (/dui, Character > Colors)
- Character: The lines under the headers (Attributes, Attack...) match the tab underline and follow its setting; give them their own color in /dui, Character > Colors > Header lines

## Fixed
- Nameplates: The level and health numbers sit in the middle of the bar (they were a pixel low)
- Character: Your character no longer flickers or goes invisible when the window opens or you come back to the Character tab

# DaylightUI 0.7.5

DaylightUI's own quest tracker, an In combat fade, your font on the game's text, and a farther camera.

## New
- Appearance: New option: Use it for the game's text too. Your font goes on the game's own text as well: menus, tooltips, quest text, popups and, after you log out and back in, combat numbers (Appearance > Font).
- Unit frames: With JiberishUI Icons installed, pick a class icon for each class: any of its styles, or one of the class's spec icons. Fabled Class and Fabled Regalia added to Icon style.
- Quests: DaylightUI now draws its own quest tracker: our look, counts on the right, zone names, and quests that slide in and out smoothly. The game's tracker is switched off while it's on (Quest Tracker module).
- Quests: Click a quest's icon in the tracker to make it your priority: the minimap arrow points to it and its icon turns the Daylight gradient (another color: Quest Tracker > Colors > Priority quest). Click it again to clear it.
- Fading: New fade choice for every area: In combat. It fades a while into a fight and comes back after.
- Minimap: New option: Rotate as you turn, so the way you face is always up (Info Panel > Minimap).
- Action bars: The bag bar and micro menu, when shown, can be moved in unlock mode (/dui unlock).
- Quests: Section headers, the line under them and zone names can use your class color or class gradient (Quest Tracker > Colors). The line starts in your class gradient. The mouseover box's color and strength can be set there too.
- Camera: New option: Max camera distance. 100% is the game's normal limit; slide it higher to zoom out as far as the game allows (Quality of Life > Camera).
- World map: Drag the world map window by its title bar; it remembers the spot. Right-click the title bar (or /dui reset) to put it back.

## Changed
- Buffs: Buff and debuff icons now round their corners to match the Corner rounding setting.
- Fading: Faded areas come back a little more smoothly when you mouse over them or a fade ends.

## Fixed
- Tooltip: Hovering a quest on the minimap shows its tooltip at the mouse again, not at the tooltip's moved spot.
- Unit frames: The Class icons options no longer error when JiberishUI Icons isn't installed.
- Skins: The loot and money toasts ("You received", "You won") now use the DaylightUI look, with the item's icon outlined in its quality color.
- Action bars: Reloading during a fight while auto attacking no longer leaves every button flashing red.
- General: /dui taint no longer stops with an error when a buff button is on screen.

# DaylightUI 0.7.4.1

Fixes an error on login.

## Fixed
- General: No more error on login about a missing Taint.lua file.

# DaylightUI 0.7.4

Faded chat stays faded while you grind, buff bar fade fixes, and the renamed JiberishUI Icons addon works again.

## New
- Chat: New fade option: Ignore loot and combat gains (on by default). Loot, money, XP, reputation and skill-ups no longer bring faded chat back while you grind.
- General: /dui taint lists anything of the game's that DaylightUI has marked, for tracking down blocked-action errors.

## Changed
- Options: No more orange dot beside settings you've changed. The reset arrow still shows next to them.
- Chat: Faded chat comes back only for a new line in the tab you're looking at. Messages for other tabs, or kinds that tab doesn't show, leave it faded.

## Fixed
- Unit frames: The class icon styles now unlock with the current JiberishUI Icons addon (it was renamed), not only the old ElvUI version.
- Unit frames: The cast bar under the player frame no longer slides away before an interrupt has shown, or right after test mode is switched on.
- Skins: Windows no longer flash a white border as they close, and the loot window no longer pops back for a moment after fading out.
- Buffs: A faded buff or debuff bar comes back when you mouse over it (Show on mouseover).
- Buffs: Weapon enchant icons (poisons, oils, stones) now fade along with the buff bar.
- General: If an update leaves a part with a file missing, it says so once in chat and stays off, instead of filling the screen with errors.

# DaylightUI 0.7.3.2

Fixes a cooldown error on the action bars in combat.

## Fixed
- Action bars: No more cooldown error when hovering a button or switching bar pages in combat (for example right after leaving stealth).

# DaylightUI 0.7.3.1

Player and pet frames can fade only at full health, smoother options pages, and an action bar fix.

## New
- Unit frames: New fade option for the player and pet frames: Only at full health. They fade only while health is full and come back as soon as it drops.

## Changed
- Options: Switching pages in the options window slides the new page in from the side of the list it's on.

## Fixed
- Action bars: Moving an item off a bar slot no longer leaves its stack count behind on the empty slot.

# DaylightUI 0.7.3

A smooth fade-in on login, new fade choices everywhere, chat link tooltips, chat history and a softer whisper chime, and sliding cast and swing bars.

## New
- General: The UI fades in smoothly on login and /reload; anything set to fade ends faded. Turn it off in General, Appearance.
- Chat: Hovering an item, spell or quest link in chat shows its tooltip, just above the chat.
- Chat: Whispers play a soft chime made for DaylightUI instead of the game's sound. Pick one of five chimes, the game's own or None under Chat > Messages; Play lets you hear it.
- Chat: Up and Down in the chat box bring back what you sent. Alt+Up and Alt+Down still work as before.
- Chat: Your chat comes back after logging out too, under a gray line with when you left. Turn it off under Chat > Messages.

## Changed
- Info panel: Opening or folding the damage meter slides the panel smoothly instead of jumping.
- Unit frames: Under the player frame, the cast bar and swing timers slide out from under it and back instead of popping in, and the swing timers glide down to make room for a cast.
- Info panel: The panel and quest tracker have a new Fade section: fade out of combat or always, how far, show on mouseover, and the delay.
- Buffs: Buffs and debuffs have the new fade choices: out of combat or always, how far, show on mouseover, and the delay.
- Chat: Chat fading uses the new fade choices; Hide until mouseover is now Fade: Always with no delay. Fade when idle stays.
- Unit frames: Every frame, party and raid has a Fade section; party and raid tiles now come back together when your mouse is over any of them.
- Action bars: Every bar, the bag bar and the micro menu share the new fade choices: out of combat or always, how far, show on mouseover, and the delay.
- Action bars: Action bars 5 to 8 now start hidden (turn each on under Action Bars). If you already use DaylightUI, any of them with something on it stays shown.

## Fixed
- Info panel: The framerate counter's tooltip now opens at the mouse, like the clock's, instead of at the tooltip's usual spot.
- Chat: Short channel tags ([G], [T], [P], [S]...) and clickable web links work again.
- Action bars: Short keybinds now work in every game language (French "5 du pavé num." shows as N5).
- Action bars: The leave-vehicle button can be moved in unlock mode (/dui unlock) and stays there, instead of snapping back beside bar 1.
- Skins: The world map no longer opens blank (only the wood background) the first time after logging in, and the game menu fades in like the other windows.

# DaylightUI 0.7.2

Hit and heal trail options, a framerate counter, skip-the-dialogue NPCs, matching bag bar and micro menu, and a few error fixes.

## New
- Unit frames: New Hit and heal trail card on the Colors page (the trail now starts off): turn it on or off, pick the hit chunk's and heal sliver's colors, set how long the chunk lingers, or keep the chunk and drop the sliver.
- Action bars: The bag bar and micro menu, when you turn them on, now match the action buttons' look (Action Bars > Bag bar and micro menu).
- Info panel: A framerate counter beside the minimap clock. Hover it for latency, addon CPU and memory, like the Game Menu button (Info Panel > Framerate).
- Unit frames: The target cast bar's text can now be resized, moved and recolored while it sits inside the target frame (Unit Frames > Cast Bars > Target cast bar).
- QoL: Skip NPC dialogue: an NPC with only one thing to offer (vendor, flight master, banker, trainer) opens its window straight away. Hold Shift to see the dialogue (Quality of Life > NPCs).

## Changed
- Windows: Every skinned game window (not only the character window) now fades softly away when you close it.

## Fixed
- Unit frames: Fixed a Lua error (UnitLevel) when party or raid frames had an empty slot.
- Info panel: Fixed a Lua error at login (DaylightUIInfoPanelBody) from the game's Edit Mode looking for the armor figure's spot before the info panel was made.
- Action bars: Totem timers above the player frame now show every time you drop a totem, not only after opening and closing Edit Mode.

# DaylightUI 0.7.1

DaylightUI's own action bars, a new options window look, live frame samples, health bar hit and heal effects, window fades and smoother bags.

## New
- Windows: The options window and the setup guide now fade in and out like the other windows, and the character window fades softly away when you close it.
- Action bars: When a spell comes off its cooldown, its button's icon pops and lights up once, so you see it's ready. The global cooldown never does this.
- Bags: The gold in the bags window counts up or down to its new amount when you earn or spend it, and glows gold while it counts up. The experience bar eases to its new value, flashes the part you just gained and shows a rising +XP (kills in a row add up), and a level up sweeps a bright band across it. Reputation at the level cap does the same. Both follow the Motion effects setting; their own switches are coming to the options window.
- Unit frames: Hits leave a light red chunk on the health bar that lingers a moment, then drains away, and heals flash a white sliver ahead of the filling bar (needs Smooth bars). Player, target, focus, party and raid frames.
- Bags: The bags window and the bank now fade in when they open. A new Motion effects setting (off: everything just appears) is coming to the options window.
- Chat: Chat input position has a new choice, Under the panel: the box you type in opens below the chat instead of covering its text.
- Options: Frame pages (Player, Target, Focus, Target of Target, Pet and Party) show a live sample of the frame at the top. It changes as you change settings, and clicking any part of it jumps to that part's settings.
- Window skins: The breath bar (and fatigue and feign death) is now one of our bars: our border settings, an angled end like the other bars, its label inside, and a gradient fill you can change on the Gradients page.
- Party frames: More debuff settings: where they go (under, above, inside or beside the frame), all debuffs or only ones you can dispel, spacing, rows, and a left/right and up/down nudge.

## Changed
- Bags: New items keep a still glow instead of flashing and pulsing.
- Bags: The bags open without a hitch, even the first time after logging in: they get ready quietly while closed (never in combat), and opening only redraws the bags that changed.
- Windows: Windows now fade out when you close them (Escape, the close button or the key), and fade in when they open: bags and bank, the chat copy and link boxes, the frame editor in unlock mode, profile import and export, the test mode box and the buff border editor (the small ones also slide up a little). The game's windows we restyle, like the character sheet and spellbook, fade in when you open them out of combat (the game menu just opens).
- Action bars: Bars set to fade (on mouseover or out of combat) start faded when you log in or reload, instead of showing for a few seconds first.
- Options: The options window has a new look: easier to read, with a softer violet-dark background and the Daylight gradient on switches and sliders. Each section has its own color and icon down the left, its pages are listed beside it, settings sit in two or three columns, chips at the top show one card at a time, a dot beside each setting you've changed, and you can resize the window from its bottom-right corner. Search now lists every matching setting from every page, and you can change them right there.
- Action Bars: DaylightUI now draws its own action bars: every bar setting and every move applies at once, without a reload. The stance, pet, possess and totem bars get every option too. Your bars stay where they were and your keybinds keep working.
- Action Bars: The switch back to the game's own action bars is gone: DaylightUI's own bars are the only ones now.
- Minimap: The Size slider now goes up to 2800 px instead of 280.
- Unit frames: The target's buff and debuff settings moved onto the Target page.
- Quest tracker: The quest tracker keeps its own spot: moving or resizing the info panel or minimap no longer drags it along and asks you to reload. The minimap's "Same width as quest tracker" option is gone.
- Action Bars: The big extra ability button (Extra Abilities in Edit Mode) now sits above the right-hand bars instead of on top of the middle ones. If you already moved it yourself, it stays where you put it.
- Profiles: The DPS/Tank profile can be deleted like any other (just not while you're using it). A new install has no profiles until you finish the setup guide.

## Fixed
- Options: Drop-down lists open upward when there's no room below them, instead of running off the bottom of the screen, and they use the same frame border as the rest of the UI (this includes the damage meter's menus).
- Quest tracker: No more surprise "moved the quest tracker" reload popup at login after the game window or UI scale changed size.
- Nameplates: Your target's outline no longer shows a visible join where its rounded corners meet the straight edges.
- Tooltips: Tooltips sit at the DaylightUI tooltip spot (the one you move in unlock mode) even if you never moved it, instead of jumping to the game's Edit Mode spot.
- Action Bars: No more 'attempt to call a nil value' error piling up from the game's action buttons (it came from the Cooldown Manager's proc glow).
- Action Bars: No more 'attempt to call a nil value' errors piling up from the action buttons (worst with a pet out or mousing over enemies), the totem bar, the armor figure or the Group Finder's drop-downs. Pet bar keybinds no longer flash.
- Buffs: Right-clicking a weapon buff (Rockbiter, poisons, oils and so on) removes it again.
- Nameplates: The game's own nameplate no longer shows up under ours in combat.
- Party frames: With buffs set to Only mine, allies who are far away no longer show buffs other people cast on them.

# DaylightUI 0.7.0.1

Profession bags colored by type, easier bag swaps, a Discord link, and fixes for empty bag slots and damage meter chat spam.

## New
- Options: A Discord link in the Daylight gradient beside the version in the options window: click it to copy the invite.
- Bags: Profession bags color their slots: herbs green, mining dark brown, leather light brown, soul shards purple, and more.
- Bags: Drop a new bag on a bag slot that still has things in it: if your other bags have room, the things are moved out and the bags swap.

## Changed
- Quest tracker: The tracked quest's icon is drawn in the Daylight gradient instead of a blue glow behind it.
- Setup guide: The welcome greets you by your first and last name.
- Bags: The "Open automatically" options are gone: the game already opens your bags at vendors, the bank, mail, trade and the auction house.

## Fixed
- Bags: Empty bag slots no longer sometimes show the game's own slot picture behind them.
- Damage meter: Hovering a meter bar no longer prints debug lines about its spells into chat.

# DaylightUI 0.7.0

A new setup guide, party frames rebuilt on the raid engine with tile options, a Healer profile, bag stacking and many fixes.

## New
- Party frames: New party options: run them across or in a grid, sort by role, show yourself, put the name on the bar with icons in the corners, dispel highlights and buffs inside the frame.
- Raid frames: Raid frames gain the tile options: tiles per line, fill upward, hide yourself, name position, buffs on tiles and an angled end.
- Raid frames: New raid sort: Group, then role. Each group keeps its own column, with tanks, then healers, then damage at the top.
- Unit frames: Names can use a class gradient, set on the Colors page or per frame. Raid frames now have their own name color setting too.
- Unit frames: A "Test frame" switch at the top of each frame's options page shows a sample of just that frame, with your changes as you make them, until you switch it off.
- Unit frames: /dui sweep party and /dui sweep raid step through sample looks, one click at a time, without changing your settings.
- Bags: Opening your bag fills up part stacks of the same item (15 and 5 Linen Cloth become one stack of 20), so no slot is wasted. Turn it off with "Stack items when the bag opens".
- Bags: Splitting a stack while trading, at the mailbox or at the auction house now gives the trade window just the amount you split, not the whole stack (it needs one free bag slot).
- Bags: Stacks of the same item that show as one now show apart while you trade or have the mailbox or auction house open, so you can split one. Turn off the new Combine stacks option to always show them apart.
- Info panel: The quest tracker can be moved in unlock mode. Its spot is saved with your profile and stays put through reloads; right-click its handle to put it back under the panel.
- Info panel: The experience bar can show how far through the level you are as a percent, has a text size option, and can now be much bigger (up to 2500 wide and 60 tall).
- Info panel: Taken off the panel, the experience bar sits under your action bars at their width, and the damage meter window starts in the bottom-right corner. The setup guide asks where you want each.
- Info panel: The damage meter is now on by default.
- Tooltips: The tooltip health bar uses the class gradient when your unit frames do, or always/never with the new Health bar color option.
- Tooltips: New Gradient border option: the class-colored border runs in the unit's class gradient.
- Chat: New option: hide chat until you mouse over it.
- General: /dui test shows a small box at the top of the screen with a checkbox for each sample (target, party, raid, buffs, meter...). Untick one to hide it; your choices are remembered.
- General: /rl and /reloadui reload the UI.
- General: Beta and PTR only: a Layout option hides Blizzard's Issue Reporter bug button.

## Changed
- Installer: A new setup guide: one-click quick setup, or a short tour of everything DaylightUI does, previewed live on your screen. Everyone sees it once.
- Installer: The setup tour saves your picks as a profile named after your character (you can rename it on the last page), so it no longer changes DPS/Tank for your other characters.
- Party frames: Party frames are rebuilt on the raid frames' engine: the game keeps them in order and swaps members safely in combat. They look the same as before.
- Raid frames: "Use raid frames in a party" is gone: the party frames can look like tiles themselves. If you used it, your party keeps the same look.
- Unit frames: Healer frames are now part of the Party and Raid pages. If you used them, your party and raid stay where and how they were.
- Unit frames: The thin class-colored line along the top of the health bar is gone.
- Profiles: A new Healer profile has its own layout: your party and raid as square tiles (you included), the player and target either side of them level with the top rows, the pet past the player and the target of target under the target. Change anything on the Party and Raid pages.
- Profiles: Default and DPS/Tank are now one profile, DPS/Tank. If you had both, your DPS/Tank stays as it was, and Default is kept only if a character still uses it.
- Bags: The Hearthstone stays in your bag like any other item: the Hearthstone button by your gold and its two options are gone. It has a light blue border so it's easy to spot.
- Nameplates: Nameplate names now start in plain class and reaction colors instead of the class gradient; pick Class gradient under Name color to get it back.
- Skins: The game's pop-up menus (right-click menus, the buff bar's category list) now match the rest of the UI.

## Fixed
- General: Installing could freeze the game with "blocked from an action only available to the Blizzard UI" popups over and over: DaylightUI now saves its layout at most once before you reload.
- General: Fresh installs no longer show LibStub / LibSharedMedia loading errors: the download includes its libraries again.
- Installer: The setup guide opens on every new character again: the game was closing it the moment you entered the world.
- Installer: "Use a setup I have" lists your DPS/Tank profile again, not just the others.
- Profiles: Switching profile takes one Reload click again, not two.
- Profiles: The Healer profile fits its frames to smaller screens or bigger UI scales: the player and target sit above the raid instead of over the chat, quest tracker or raid tiles.
- Unit frames: Portraits are left off very short frames instead of swamping them, and aggro shows on the border when there's no portrait.
- Action bars: The totem bar starts where the stance bar goes, above your action bars, instead of on top of bar 2.
- Buffs: Turning off Attach to the info panel for the first time leaves the buff and debuff bars where they are instead of jumping away.
- Buffs: Right-clicking a weapon buff (poison, oil, sharpening stone) removes it again instead of showing a blocked-action warning.
- Nameplates: The target outline's corners now curve with the nameplate's rounded border instead of leaving gaps.
- Quest tracker: A quest you just picked up gets our quest icon right away instead of keeping the game's own.
- Chat: Speech bubbles stay over the speaker's head instead of sometimes appearing off to the side.

# DaylightUI 0.6.4.2

Fixes for raid frame errors, health text under portraits, fishing bobber nameplates and the trainer skill highlight.

## Changed
- Damage meter: Its settings can be changed while the meter is hidden.

## Fixed
- Raid frames: No more errors when joining a group, after combat, or when raid markers change.
- Unit frames: With the large health number off, the health text stays at the frame's inner end instead of hiding under the target's portrait.
- Nameplates: Fishing bobbers and other objects show just their name, without an empty health bar.
- Skins: The selected skill at a trainer is easy to see: outlined and tinted in your class color (or your accent, if you picked one).

# DaylightUI 0.6.4.1

Crisp angled frame edges, cleaner shadows and corners, and a flash for missing buffs on cooldown bars.

## New
- Cooldowns: Bars can flash when their buff is down (with Always show on), so a missing Battle Shout catches your eye.

## Fixed
- Nameplates: Cast bars no longer show an odd shield icon on the left for casts you can't interrupt.
- Unit frames: Big angled edges (the player frame and the cast bar and swing timers under it) are crisp and solid now, with no blurry diagonal, borders sticking out, or shadows over the borders at each join.
- Style: With corner rounding on, the shadow no longer looks doubled and darker at the corners of action buttons and other small frames, and the tiny dark dots just off each corner are gone.
- Action Bars: With empty buttons hidden, no tiny dots are left at the corners of the empty slots.
- Unit Frames: Stacked swing timer bars cast one even shadow down their sides, angled ends cast a shadow along the angle, and no sliver of the world shows between a bar and its angled border.

# DaylightUI 0.6.4

Small cooldown polish: bar name options, active buff sweep color, and cleaner bar borders.

## New
- Cooldowns: Each cooldown bar can hide its spell name or put it in the middle of the bar.
- Cooldowns: Icons can turn off the yellow sweep while their buff is up (just the timer), or give it your own color.

## Fixed
- Cooldowns: A bar's own background color now goes fully see-through at 0 opacity instead of staying dark.
- Cooldowns: Cooldown bars get a clean plain border at thinner border settings instead of a cramped, muddy one.

# DaylightUI 0.6.3

Dispel highlights and sorting for raid and healer tiles, plus per-frame colors and more unit frame options.

## New
- Unit frames: Raid and healer tiles can light up their border and/or tint the health bar when a member has a dispellable debuff, with a choice of any typed debuff or only ones you can remove.
- Unit Frames: Target of target and pet frames can show health text; focus, party and pet get power text position and size.
- Unit Frames: Each unit frame has its own name color, health text color and name length, plus name tab height, portrait size and raid marker size.
- Unit Frames: Extras page: set the angle of the slanted frame ends, and hang the combo points under your own frame.
- Unit Frames: Pet frame has a Power bar switch.
- Unit frames: Raid and healer tiles can hide the health text at full health.
- Unit Frames: Healer tiles have their own First and last names switch.
- Unit frames: Raid and healer tiles can be sorted by group, role, class or name, and can hide the higher raid groups.
- Unit frames: Raid and healer tiles let you move and resize the role, marker, leader and dispel icons, and hide the role and crown in combat.
- Unit Frames: Colors page: pick the dispel type, dead, offline, tapped and NPC reaction colors, a custom missing-health color, and a separate faded opacity for party and tiles.

## Changed
- Unit Frames: The range fade description now says it covers party, raid and healer tiles too.

## Fixed
- Nameplates: Name-only friendly plates are a little lighter in crowded cities.
- Unit Frames: Cast bars now use the Can't be interrupted color for casts that can't be interrupted, and you can pick it on the Cast Bars page.
- QoL: The Train all button no longer shows in the hunter Beast Training window, where it caused a blocked-action error.

# DaylightUI 0.6.2.1

Buffs on party and healer frames, and movable health and power text.

## New
- Unit Frames: Party frames and healer tiles can show buffs, only the ones you cast by default.
- Unit Frames: Health and power text on the player, target, party, raid and healer frames can be moved with left/right and up/down sliders.
- Unit Frames: Healer frames can hide your own tile, and the name can be aligned left, center or right and nudged with sliders.
- Unit Frames: Healer tile buffs can sit outside the tile: left, right, top or bottom.

## Fixed
- Unit Frames: Test mode frames (target, party and others) no longer vanish when you change a setting while it's on.
- Unit Frames: Removed the Angled end switch from raid and healer frames; it never did anything there.

# DaylightUI 0.6.2

Snap to grid in unlock mode, action bars that move smoothly, and no more empty squares on unbound buttons.

## New
- Layout: Unlock mode has a Snap to grid button next to Lock, to turn snapping on or off while you move things.

## Changed
- Action Bars: The Left Grid and Right Grid bars are now called Action bar 3 and Action bar 4.
- Action Bars: Action bars turned off in the game's settings no longer show up in unlock mode.

## Fixed
- Action Bars: Action bars now move as you drag them in unlock mode and snap to the grid like everything else.
- Layout: The position window opens above a frame that sits near the bottom of the screen, instead of off screen.
- Cooldowns: With your cooldown layout on, spells the game adds to its Cooldown Manager no longer pop up when your layout is empty.
- Action Bars: Buttons with no keybind no longer show a small empty square in the corner when you have a target.

# DaylightUI 0.6.1

More options for detached swing timers and cast bars.

## New
- Unit Frames: Detached swing timers and cast bars: angled end, icon, text size and fill direction; swing bars can also be spaced apart and stack upward, and no longer shift up and down between swings.

# DaylightUI 0.6.0.1

Fixes: no tooltip flicker in combat, the armor figure back in view, the Lock button on top.

## Fixed
- Tooltip: With Off in combat on, unit tooltips no longer flicker in combat.
- Minimap: The armor figure that shows broken gear now sits left of the quest tracker's top corner instead of hidden under the info panel.
- Unlock mode: The Lock button now stays on top of movers instead of getting covered.

# DaylightUI 0.6.0

Design your own cooldown layout, Action Bars 5 to 8, chat history and copy, and more to move in unlock mode.

## New
- Cooldowns: Design your own cooldown layout in /dui > Cooldown Manager > Layout: place blocks of icons and bars, drag spells into them, move it all as one piece. One layout per talent set.
- Cooldowns: The layout editor lists every spell you know, also ones set to Not Displayed in the game's Cooldown Manager, and can show unlearned spells to plan for other talents.
- Cooldowns: Spells like Rend that the game's Cooldown Manager doesn't display now show in your layout while they're up.
- Cooldowns: Click a spell in the layout editor to give it a proc glow, its own size, no swipe, or fade/hide/glow based on its cooldown.
- Cooldowns: Layout blocks have Only in combat (hidden out of combat) and Always show (buffs that aren't up stay as a grayed icon or an empty bar).
- Cooldowns: Bars can have their own fill and background color per spell, both can be gradients, and Glow when ready has its own color.
- Action Bars: Action Bars 5 to 8 now get the same look, layout options, fading and moving as the other bars.
- Chat: Chat comes back after /reload: the last 100 messages in each tab (Chat > Messages).
- Chat: Copy chat text: a Copy button on the chat (or /dui copy) opens it so you can select and Ctrl+C.
- General: Unlock mode can now move the tooltip, the bag and bank windows, loot rolls, alerts, the top center status bar, error messages and the ticket icon.

## Changed
- Cooldowns: Typing /cdm opens the DaylightUI cooldown layout instead of the game's Cooldown Manager settings.
- Cooldowns: The Cooldown Manager options are one page now, Layout, with a side panel next to the layout. Buff bar color, icon, text size and time are set on each bar block; bars outside your layout are the game's own (size them in Edit Mode).
- Cooldowns: Cooldown layouts are saved per character, one per talent set. Your old shared layout is kept: use Copy from... in the editor to bring it back.
- Options: Clearer option names and descriptions.
- Options: The last-name switches for nameplates and tooltips moved to the Nameplates and Tooltips pages.
- Options: Cast bar, swing timer and combo point gradient colors are now set only on the Gradients page.

## Fixed
- Cooldowns: Clicking Set 1 or Set 2 in the layout editor now switches the layout you see in game too, and a talent change switches it back automatically.
- Unit frames: Clique click-casting works on the unit and healer frames, and no longer stops the healer frames from loading.
- Unit frames: Target, focus and party power bars now fill smoothly between ticks instead of jumping.

# DaylightUI 0.5.6

Gradient experience and reputation bars, and a batch of tooltip, healer frame and trainer fixes.

## New
- Experience bar: The experience and reputation bars now use gradients: your class's for experience, and one per standing (Hated to Exalted) for reputation, editable on the Gradients page. Switches to turn them off.

## Changed
- Minimap: The addon drawer's tab no longer shows a tooltip
- Unit frames: While healer frames show your party or raid, the Party and Raid options gray out with a note and a button to the Healer Frames page
- Unit frames: Healer frames now always show your party as well as your raid; the confusing "In a party too" switch is gone

## Fixed
- Minimap: Clicking an addon button in the drawer no longer throws an error
- Unit frames: Healer frames: /dui test raid now previews the raid tiles with their own settings and place, and setting changes show in the preview right away
- Quality of life: Train all at class trainers now counts and learns your skills instead of always showing 0
- Tooltips: Position: Mouseover (renamed from Follow the cursor) works again; tooltips at the game's usual spot now follow your mouse
- Tooltips: With Fade out off, a tooltip for something in the world now vanishes the moment you mouse off it, instead of lingering and fading slowly
- Tooltips: Hide unit tooltips in combat works again

# DaylightUI 0.5.5

See what a spell will cost on your power bar, and Cooldown Manager buff bars in Daylight's style.

## New
- Unit frames: Power cost preview: while you cast, the mana, rage or energy the spell will use is shaded on the end of your power bar, so you can see what you'll have left
- Unit frames: The cost preview also shows while Heroic Strike, Cleave or Maul is queued for your next swing
- Unit frames: The shade follows your frame's slanted edges; its color and strength (or turning it off) are in the player frame options
- Action bars: Cooldown Manager buff bars are restyled: a small square icon and a thin bordered bar with the name and time, in your class gradient, Daylight's gradient or one color per spell
- Action bars: Buff bars can dock above your player frame, match its width, and grow up or down, with options for height, gap, text size, icon and time (Action Bars > Cooldown Manager > Buff bars)

## Changed
- Options: The sidebar text is about 20% smaller

# DaylightUI 0.5.4

Quality-of-life switches, a minimap button drawer, and profile loading in the installer.

## New
- Quality of Life: Optional switch to hide the game's new-player tutorial tips (off by default)
- Quality of Life: Optional skip for cutscenes and intro movies (off by default; hold Shift to watch)
- Quality of Life: Optional automatic quest accept and turn-in (off by default; hold Shift to pause)
- Info panel: Addon minimap buttons (BugSack etc.) can be tucked into a drawer under the map, opened with a small tab
- Installer: New characters can load a profile you already have, picked from a list, exactly as it is

## Fixed
- Action bars: Pet bar keybinds no longer flicker between bright and dull white
- Action bars: Shortened keybinds no longer briefly show the full name when the game updates them
- Installer: Installing with controller mode on no longer crashes the game; it asks you to turn controller mode off first (and no longer asks when only gamepad input is on)
- Profiles: New profiles keep plain class colors after a reload instead of switching back to class gradients

# DaylightUI 0.5.3

Bugfix release, plus combo point options.

## New
- Combo points: Options for pip height, spacing, position, colors, border, slant and gradient (Unit Frames > Extras)

## Fixed
- Info panel: Spell breakdown rows now fill the icon correctly and use the same school/class gradient as the meter bars
- Info panel: Small layout fixes in the meter and panel

# DaylightUI 0.5.2

Gradients everywhere by default: power bars now use power gradients, and existing setups switch plain class/power colors, cast bars, swing timers, nameplates and the meter to gradients once. One-color custom picks are kept.

# DaylightUI 0.5.1

Damage meter bars can now use the gradient colors.

## New
- Info panel: The damage meter bars have a "Gradient" toggle (on by default) that uses the class gradient from the Gradients page
