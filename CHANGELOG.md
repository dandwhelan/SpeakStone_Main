# Changelog

### Retail

- **The Misc voice pack is retired.** Every line in it turned out to belong only to WoW Forever, where it is already
  voiced, so it could never play in retail. The settings page no longer lists it as missing; you can delete
  SpeakStone_Pack_Misc from your AddOns folder.
- Voice packs 3.1.4: every line at the same volume as the game's own voices (the narrator is no longer quieter),
  about 1,700 lines re-recorded, about 80 more characters voiced, and greetings that were read by the narrator by
  mistake now use the character's own voice.

Unofficial; not affiliated with Blizzard Entertainment.

## 3.1.4 (October 2026)

### Retail

- **New pack: SpeakStone Narration - Misc.** About 2,800 quest lines whose expansion is not known yet now have a
  pack of their own. The settings page lists it among the packs a complete install has, so it tells you when it is
  missing.

### WoW Forever

- **Quest titles in the Audio Library now use WoW Forever's own names.** Classic quests that later versions of the
  game removed no longer show as "[DEPRECATED] ..." (for example Kobold Camp Cleanup, Journey to Tarren Mill),
  quests renamed in later versions show their Classic name (Raptor Horns, Supplying the Sepulcher), and quests
  with only a placeholder title now take their name from the game.
- **NPC names** no longer carry a "[Deprecated for 4.x]" tag.

### Packs released alongside this version

- Retail packs 3.1.3; WoW Forever Audio Pack 1, Audio Pack 2 and Chatter: every character keeps one voice in all
  of their lines, and three books (Civil War in the Plaguelands, Aftermath of the Second War, Beyond the Dark
  Portal) now read through every page. Install all four Forever addons: Main, Audio Pack 1, Audio Pack 2 and
  Chatter.

Unofficial; not affiliated with Blizzard Entertainment.

## 3.1.3 (October 2026)

### Narration

- **Books and quest lines keep reading:** talking to an NPC who has nothing to say, or opening a plaque or a quest
  that has no audio yet, no longer cuts off a book or quest line that is still being read after you closed its
  window. An NPC who does have something to say still takes over, and turning to a page with no audio still stops
  the book.
- **"Stop narration when the window closes":** closing a gossip window now only stops that NPC's gossip, not a book
  or quest line that is still being read.
- **Book titles:** a few books whose titles contain an unusual space character now find their audio.
- **NPC greetings with quotation marks** (book names and the like) now match their audio whichever quote marks the
  game uses.
- The speech bar's text for a quest now always comes from that quest.

### Captured text

- **Read Quest in the quest log:** pressing it on a quest that has no audio no longer saves the text of a different
  quest (the one a quest giver last showed you) under that quest's name.

### Data

- Quest titles, NPC names, NPC greetings and book pages refreshed to match the latest audio packs.

## 3.1.2 (October 2026)

### Books

- **Book text stays on screen:** when a book is being read aloud and you walk away (or close it), the speech bar now
  keeps showing the text of the page being read instead of "No text for this line".

### Behind the scenes

- The addon now also notes which character model an NPC uses when you talk to them, so a new NPC's voice can be
  matched to the right race and sex without guessing. Nothing about you is recorded.

## 3.1.1 (October 2026)

### Speech bar

- **Quest queue fixes:** anything else that cuts the current quest off (a book, a gossip line, the library) now clears
  the queue too, so stale quests never start later out of nowhere, and a quest whose clip fails to play moves on to
  the next. A talking head only pauses the queue: the rest carries on once the NPC has finished speaking.
- Turning "Show all the text" on or off from `/ss` or the Options page now resizes the bar straight away.

### Settings window

- **Tidier layout:** Queue quests and Auto-accept moved to Playback. Auto-scroll and Grow sit under "Show the speech
  frame" and grey out while it's off. Capture moved to Interface, and debug messages became a small Advanced line at
  the bottom. The three link cards are now one Links card with a button per address, Export and Clear moved onto the
  Capture card, and the bottom row is just the Library buttons and Profiles. The window is shorter, and the captures
  card only lists what you've actually captured.

### Tutorial

- **Speech bar page:** shows the sample bar so you can drag it into place, pick a size and set its options. The
  tutorial moves itself off the bar while you do. The "Where things are" page now covers the bar's buttons and
  keybinds.
- **What's new:** players who already went through the tutorial get a short run (what's new, the speech bar page)
  instead of the whole thing, with a button for the full tutorial.
- **Profiles** now set the speech bar options too (Story Only queues quests; Manual turns the bar off), and there's a
  new **Subtitles** profile: extra large bar, the whole passage shown, quests queued.

### Fixes

- **Audio Library quest titles:** the built-in title list (for quests your character has never seen) was loaded but
  never read, because of a leftover name from the rename. Far fewer quests now show as "Unknown quest".
- Leftover QuestReader names inside the addon renamed to SpeakStone. The old `/qr...` commands still work.
- **Lighter on busy cities:** NPC chat lines are no longer hashed when narration isn't set to wait for NPC voices, and
  a line is checked once rather than twice when harvesting is on.

## 3.1.0 (October 2026)

### Speech bar

- **Auto-scroll:** the text in the speech bar now scrolls along with the voice, so the line being spoken stays in
  view. Scroll with the mouse wheel to look around and it waits a few seconds before carrying on. Can be turned off
  ("Auto-scroll the speech frame text").
- **Show all the text:** a new option makes the bar grow taller to fit the whole passage instead of scrolling (very
  long text still scrolls). Off by default.
- **Extra large size** added to the bar's Size menu (gear or right-click).
- **Quest queue** (off by default, "Queue quests instead of interrupting"): talk to another quest giver while a quest
  is still being read and the new quest waits its turn instead of cutting the first one off. The bar shows where you
  are (1/2, 2/2...) and a **Next** button skips ahead. Stop clears the queue. While quests are queued, NPC greetings
  don't interrupt them and closing a gossip window doesn't stop them.
- The NPC name and quest title now sit on their own line, so the buttons no longer cover the quest name.
- All the new options are in `/ss` under "Speech frame", in the game's Options › AddOns page, and on the bar's gear
  menu.

## Unreleased

### Speech frame

- **A new speech bar for narration that keeps going after you walk away.** Close the quest window mid-line and a
  bar appears at the bottom of the screen with the NPC's portrait, their name, the quest title and the full text to
  read along (scroll with the mouse wheel).
- **Pause, Stop and Replay** buttons, plus a timer. The game can't pick a clip up part-way, so Resume starts the line
  again from the beginning.
- **Three sizes** (Small, Medium, Large). Right-click the bar or use its gear to change size, lock it or reset its
  position. Drag it anywhere. `/ss frame` shows a sample to place it with.
- **Auto-accept quests** (off by default): quests are accepted as soon as they're offered, and you hear them in the
  speech bar. Hold Shift at the quest giver to skip it for that quest.
- New keybind: **Pause / resume narration**.
- Both can be switched in `/ss` under "Speech frame", or in the game's Options › AddOns › SpeakStone page. The ⓘ icon
  there explains why Pause restarts the line.
- The bar's right-click menu has a shortcut to SpeakStone's settings.

## 3.0.0 — the big voice update (October 2026)

**The biggest update SpeakStone has ever had.** Almost the whole voice library has been redone, and there is more
of it than ever: **over 103,000 voiced lines, nearly 350 hours of audio.**

### Better voices, everywhere

- **Nearly every NPC sounds better.** More than **55,000 lines have been re-voiced**, and characters now speak with
  far more emphasis and personality instead of a flat read.
- **Exclamations sound natural now.**
- **Big improvements to sound quality across the whole library**: cleaner, clearer audio.
- **Voices match the character better.** Race and sex have been checked for every voiced NPC: no more female
  characters with male voices (or the reverse), and races now sound like their race (draenei no longer sound
  human, goblins no longer sound like gnomes, and so on).
- **Children** now have a child's voice.

### More to hear

- **Nearly 10,000 brand-new lines**, including quest progress and hand-in lines that used to be silent and gossip
  for NPCs that had none.
- **New voices for peoples who had none:** Earthen, Vulpera, Tuskarr, Centaur, Broken, Nerubians, Brokers,
  Ethereals, Ankoan, Taunka, Vrykul, Dredgers, Sylvar and Faeries.
- **More narration** for books and for creatures that speak without a race of their own.

### Fixes

- NPCs no longer read out long lists of quest rewards.
- Voices that sounded rushed or slowed down have been redone.

### Also in 3.0.0 (folded in from the unreleased 2.0.7)

- Lots more in-game gossip found and voiced, thanks to data shared by players.
- Lots more books found and voiced, and a new book view for reading and listening to in-game books.
- A new narrator voice, and quality-of-life improvements across the add-on.

### Thank you

A huge thanks to everyone who shared their game data: AuthenticSenpai, silvy, Pappnase, illset, Benny McBackstab
and Vanadan, plus everyone who contributed anonymously. Thanks as well to Benny McBackstab and Pappnase for
reporting voices that didn't match their NPCs. Report a voice, lend your own voice or send in quest text at
https://speakstone.beanw.co.uk.

*SpeakStone plays voices similar to the in-game NPCs. Unofficial; not affiliated with or endorsed by Blizzard
Entertainment.*
