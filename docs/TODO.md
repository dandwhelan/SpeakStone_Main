# TODO

Ideas agreed for later, not yet scheduled.

## Voice NPC chat lines (say / yell)

Voice the lines NPCs say or yell in chat that Blizzard never recorded.
Parked because it is large:

- Needs the full BroadcastText table to count and script the lines. A rough
  guess is tens of thousands, mostly generic combat shouts.
- Limiting it to named NPCs and quest-event lines would probably bring it down
  to a few thousand clips.
- Playback can hook the CHAT_MSG_MONSTER_* events SpeakStone already listens
  to (they are how it waits for Blizzard's own voiced lines).

## Other ideas, not decided

- More keybinds: stop, replay, next in queue, show/hide the speech frame.
- Per-character settings.
- Progress stats: voiced vs missing quests in the current zone.
- Highlight the sentence being read in the speech frame.
- Voice the player's own character.
- One-click pronunciation report from the speech frame.
