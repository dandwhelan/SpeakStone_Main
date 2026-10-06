# Changelog

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
  Anything else that cuts the current quest off (a talking head, a book, a gossip line, the library) clears the queue
  too, so stale quests never start later out of nowhere, and a quest whose clip fails to play moves on to the next.
  A talking head only pauses the queue: the rest carries on once the NPC has finished speaking.
- Turning "Show all the text" on or off from `/ss` or the Options page now resizes the bar straight away.
- The NPC name and quest title now sit on their own line, so the buttons no longer cover the quest name.
- **Audio Library quest titles:** the built-in title list (for quests your character has never seen) was loaded but
  never read, because of a leftover name from the rename. Far fewer quests now show as "Unknown quest".
- Leftover QuestReader names inside the addon renamed to SpeakStone. The old `/qr...` commands still work.
- **Lighter on busy cities:** NPC chat lines are no longer hashed when narration isn't set to wait for NPC voices, and
  a line is checked once rather than twice when harvesting is on.
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
