# Handover 2026-10-08: books showing fewer pages than they have

For the PC build workspace (`questwow`). The cloud session could not push to
the two Forever packs, and the pack repos are rebuilt from the local library
anyway, so the fix has to land there.

## The report

Player (via @danerf): in the Audio Library, *Civil War in the Plaguelands*
(Northshire) showed **1 page**, but the book has 4. Opening it in game also read
only page 1. Later it showed 4.

## Cause

The addon is fine. The library counts a book's pages by the `<base>_page<n>`
clips it finds across all installed packs, and reading aloud stops at the first
page with no clip. `BookTexts.lua` has had all 4 pages since it was added; only
the audio was missing.

- 2026-09-29: Forever Audio Pack 2 got `item_civil_war_in_the_plaguelands_page1`.
- 2026-10-07: Forever Chatter 3.1.4 ("new Forever lines from the latest website
  submissions") added pages 2-4. That is when it started showing 4.

That left two problems, found by an audit of every pack:

1. **Split book.** *Civil War* page 1 is in Forever Audio Pack 2 and pages 2-4
   are in Forever Chatter. Anyone without Chatter still gets 1 page. The Forever
   README said "install all three" (Main + Pack 1 + Pack 2) and never mentioned
   Chatter. This is the only split book.
2. **Pages voiced in one game only.** The text is identical in both games
   (`BookTexts.lua` matches), but the clips were never synced:

   | Book (`base`) | Forever has | Retail has |
   |---|---|---|
   | `item_aftermath_of_the_second_war` | page 1 | pages 1-6 (Chatter_Part1) |
   | `item_beyond_the_dark_portal` | page 1 | pages 1-4 (Chatter_Part1) |
   | `item_the_fall_of_ametharan` | pages 1-3 (Forever Chatter) | page 1 |
   | `item_the_lay_of_ametharan` | pages 1-3 (Forever Chatter) | page 1 |

   Copy the **whole book**, page 1 included. The Ametharan page 1 clips are
   different takes in each game (24.72s vs 24.92s, 23.11s vs 27.28s), so mixing
   them would switch voice after page 1. For Aftermath and Dark Portal, page 1
   has the same length in both games (24.46s, 23.68s), so it is probably the
   same take, and replacing it costs nothing.

## Already done in the cloud (draft PRs, not merged)

- **SpeakStone_Pack_Chatter_Part1 #1:** copied both Ametharan books (pages 1-3)
  from Forever Chatter and updated `SoundLengths.lua`.
  https://github.com/dandwhelan/SpeakStone_Pack_Chatter_Part1/pull/1
- **SpeakStone_Forever_Main #7:** README install list now includes Forever
  Chatter ("Install all four").
  https://github.com/dandwhelan/SpeakStone_Forever_Main/pull/7

## To do on the PC

1. **Forever packs** (blocked from the cloud). Use `fix_book_pages.py` below on
   local clones, or do the same thing in the library and republish:
   - Move `item_civil_war_in_the_plaguelands_page1.ogg` from Forever Audio
     Pack 2 into Forever Chatter, so the whole book is in Chatter (Chatter
     already holds 1114 of the 1132 Forever book clips).
   - Copy `item_aftermath_of_the_second_war_page1-6` and
     `item_beyond_the_dark_portal_page1-4` from retail Chatter_Part1 into
     Forever Chatter, replacing Forever's page 1.
   - Listen to Forever's *Civil War* page 1 next to pages 2-4. Page 1 has the
     same length as retail's (22.16s), but pages 2-4 don't (21.28s vs 20.80s,
     14.64s vs 14.72s), so page 1 may be a different take or voice. If it
     sounds different, re-voice page 1 with the voice used for pages 2-4.
2. **Mirror into the library.** Put all of the above, plus the retail
   Ametharan change from PR #1, into the `questwow` library under the right
   flavour. Otherwise the next "Refresh ... pack from current library" /
   `publish_packs.py` run reverts it. If the site still lists these pages as
   unvoiced for a flavour, mark them voiced the usual way (`markVoiced()` /
   `/api/admin/mark-voiced`) so they are not queued again.
3. **Pipeline rule: one book, one pack.** Wherever clips are assigned to packs
   (probably `publish_packs.py`), assign by book `base`, not by clip. A new page
   goes into the pack that already holds that book's other pages, and books go
   into Chatter. That is what split *Civil War*: page 1 went to Audio Pack 2 in
   a "gossip, books, quests" batch, and the later pages went to Chatter.
4. **Pipeline check: sync books across games.** Before publishing, run
   `audit_book_pages.py` below for both games. Where one game has every page,
   the other is missing some, and the `BookTexts.lua` text is identical, copy
   the whole set across. Fail the publish if any book is split across packs.
5. **README generator.** `tools/build_forever_main.py` writes the Forever
   README. Give its install list the same four entries as PR #7, or the next
   build reverts that PR.
6. **Release.** Merge the PRs, bump the version in each changed pack's `.toc`
   and push tags (`release.yml` releases on any tag push) for:
   SpeakStone_Pack_Chatter_Part1, SpeakStone_Forever_Chatter and
   SpeakStone_Forever_Audio_Pack2. Forever_Main does not need a release for the
   README alone, because `pkgmeta.yaml` leaves `README.md` out of the package.
7. **Verify.** Re-run the audit. You should see `split across packs: 0` and
   `missing pages: 0` for both games. Then, in game (Forever and retail), check
   that the library shows *Civil War* with 4 pages, *Aftermath* with 6, *Dark
   Portal* with 4 and both Ametharan books with 3, and that opening each one
   reads through to the last page.

## fix_book_pages.py

Copies every page clip of one book from one pack folder to another, and copies
its lengths into the target's `SoundLengths.lua`. Pages the source lacks are
left alone in the target. With `--move`, it also removes the book from the
source pack. It keeps `SoundLengths.lua` sorted the way the packs already are,
so the diff is only the book's own lines.

```python
#!/usr/bin/env python3
"""python fix_book_pages.py SRC_PACK DST_PACK BOOK_BASE [--move]"""
import argparse, pathlib, re, shutil

ENTRY = re.compile(r'^    \["([^"]+)"\] = (.+),$')

def read_lengths(pack):
    path = pathlib.Path(pack, "SoundLengths.lua")
    lines = path.read_text(encoding="utf-8").split("\n")
    entries = {}
    for line in lines[1:]:
        m = ENTRY.match(line)
        if m:
            entries[m.group(1)] = m.group(2)
        elif line not in ("}", ""):
            raise SystemExit(f"{path}: unexpected line {line!r}")
    return path, lines[0], entries

def write_lengths(path, header, entries):
    body = [f'    ["{k}"] = {entries[k]},' for k in sorted(entries)]
    path.write_text("\n".join([header, *body, "}", ""]), encoding="utf-8", newline="\n")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src"); ap.add_argument("dst"); ap.add_argument("base")
    ap.add_argument("--move", action="store_true", help="remove the book from SRC afterwards")
    a = ap.parse_args()
    page = re.compile(re.escape(a.base) + r"_page\d+\.(ogg|wav)$")
    clips = sorted(p for p in pathlib.Path(a.src, "Sounds").iterdir() if page.match(p.name))
    if not clips:
        raise SystemExit(f"no {a.base}_page* clips in {a.src}")
    spath, shead, sent = read_lengths(a.src)
    dpath, dhead, dent = read_lengths(a.dst)
    for clip in clips:
        shutil.copy2(clip, pathlib.Path(a.dst, "Sounds", clip.name))
        dent[clip.name] = sent[clip.name]
        print(f"{clip.name} -> {a.dst} ({sent[clip.name]}s)")
        if a.move:
            clip.unlink()
            del sent[clip.name]
    write_lengths(dpath, dhead, dent)
    if a.move:
        write_lengths(spath, shead, sent)

main()
```

Run it from a folder that holds clones of all three packs:

```
python fix_book_pages.py SpeakStone_Forever_Audio_Pack2 SpeakStone_Forever_Chatter item_civil_war_in_the_plaguelands --move
python fix_book_pages.py SpeakStone_Pack_Chatter_Part1  SpeakStone_Forever_Chatter item_aftermath_of_the_second_war
python fix_book_pages.py SpeakStone_Pack_Chatter_Part1  SpeakStone_Forever_Chatter item_beyond_the_dark_portal
```

(The retail Ametharan copy is already on PR #1. Without that PR, it would be
`python fix_book_pages.py SpeakStone_Forever_Chatter SpeakStone_Pack_Chatter_Part1 item_the_fall_of_ametharan`,
and the same again with `item_the_lay_of_ametharan`.)

Expected diffs: Audio Pack 2 loses one line (the *Civil War* page 1 entry).
Forever Chatter gains 9 lines (*Civil War* page 1, *Aftermath* pages 2-6, *Dark
Portal* pages 2-4). Page 1 of *Aftermath* and *Dark Portal* keeps the same
length, so only the `.ogg` changes. Check with `git diff --stat` before
committing.

## audit_book_pages.py

```python
#!/usr/bin/env python3
"""python audit_book_pages.py BOOKTEXTS.lua PACK_DIR [PACK_DIR ...]

Lists books whose pages are split across packs, and books whose clips cover
fewer pages than BookTexts.lua has text for (or have a gap in the numbering).
"""
import collections, pathlib, re, subprocess, sys

def page_counts(booktexts):
    out = {}
    for line in pathlib.Path(booktexts).read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r'\s*\["([^"]+)"\]\s*=\s*\{(.*)\},?\s*$', line)
        if m:
            out[m.group(1)] = len(re.findall(r'"(?:[^"\\]|\\.)*"', m.group(2)))
    return out

def clip_names(pack):
    sounds = pathlib.Path(pack, "Sounds")
    if sounds.is_dir():
        return [p.name for p in sounds.iterdir()]
    # A clone without a working tree: read the names from git instead.
    tree = subprocess.run(["git", "-C", pack, "ls-tree", "-r", "--name-only", "HEAD", "Sounds/"],
                          capture_output=True, text=True, check=True).stdout
    return [n.split("/", 1)[1] for n in tree.split()]

texts = page_counts(sys.argv[1])
where = collections.defaultdict(lambda: collections.defaultdict(set))  # base -> page -> packs
for pack in sys.argv[2:]:
    for name in clip_names(pack):
        m = re.match(r"(.+)_page(\d+)\.(ogg|wav)$", name)
        if m and not name.startswith("npc"):
            where[m.group(1)][int(m.group(2))].add(pathlib.Path(pack).name)
split = {b: p for b, p in where.items() if len({x for s in p.values() for x in s}) > 1}
missing = {}
for base, pages in where.items():
    want = max(texts.get(base, 0), max(pages))
    gap = sorted(set(range(1, want + 1)) - set(pages))
    if gap:
        missing[base] = (sorted(pages), texts.get(base), gap)
print(f"{len(where)} books voiced; split across packs: {len(split)}; missing pages: {len(missing)}")
for base, pages in sorted(split.items()):
    print("  SPLIT  ", base, {p: sorted(s) for p, s in sorted(pages.items())})
for base, (have, want, gap) in sorted(missing.items()):
    print("  MISSING", base, f"has pages {have}, text has {want}, missing {gap}")
sys.exit(1 if split or missing else 0)
```

```
python audit_book_pages.py SpeakStone_Forever_Main/BookTexts.lua SpeakStone_Forever_Audio_Pack1 SpeakStone_Forever_Audio_Pack2 SpeakStone_Forever_Chatter
python audit_book_pages.py SpeakStone_Main/BookTexts.lua SpeakStone_Pack_*
```

Run it on full clones. In a sparse checkout it only sees the files that are
checked out.

Output on 2026-10-08, before the fixes:

```
# Forever
362 books voiced; split across packs: 1; missing pages: 2
  SPLIT   item_civil_war_in_the_plaguelands {1: ['SpeakStone_Forever_Audio_Pack2'], 2: ['SpeakStone_Forever_Chatter'], 3: ['SpeakStone_Forever_Chatter'], 4: ['SpeakStone_Forever_Chatter']}
  MISSING item_aftermath_of_the_second_war has pages [1], text has 6, missing [2, 3, 4, 5, 6]
  MISSING item_beyond_the_dark_portal has pages [1], text has 4, missing [2, 3, 4]
# Retail
753 books voiced; split across packs: 0; missing pages: 2
  MISSING item_the_fall_of_ametharan has pages [1], text has 3, missing [2, 3]
  MISSING item_the_lay_of_ametharan has pages [1], text has 3, missing [2, 3]
```

After the three `fix_book_pages.py` runs above (tested on copies of the
packs) and with PR #1, both games print
`split across packs: 0; missing pages: 0` and exit 0.
