#!/usr/bin/env python3
"""Rebuild SpeakStone_Forever_Main's code from SpeakStone_Main.

    python tools/build_forever_main.py <retail_dir> <forever_dir> [--check]

Copies every code file from retail into Forever and renames the saved
variables (SpeakStone_MainDB -> SpeakStone_ForeverMainDB). Forever keeps its
own game data (quest/gossip/NPC tables), CHANGELOG, README, pkgmeta and .toc
header; only the .toc's Version and file list follow retail.

--check: change nothing, exit 1 if Forever is out of date (for CI).
"""
import filecmp
import os
import re
import shutil
import sys

RETAIL_DB, FOREVER_DB = "SpeakStone_MainDB", "SpeakStone_ForeverMainDB"
RETAIL_TOC, FOREVER_TOC = "SpeakStone_Main.toc", "SpeakStone_Forever_Main.toc"

# Per-game data: generated separately for each game, never copied across.
DATA_FILES = {
    "QuestInfo.lua", "QuestTitles.lua", "QuestTexts.lua", "GossipTexts.lua", "NPCNames.lua",
    "DynamicGossipNPCs.lua", "VoicedLines.lua", "BookTexts.lua", "ZoneLoreData.lua", "SoundLengths.lua",
}
COPY_DIRS = ["Art", "Libs"]
COPY_FILES = ["Bindings.xml", "cs_icon.tga"]


def rename(text):
    # `ForeverMainDB or MainDB` (files that look for both names) is left as it is.
    return re.sub(r"(?<!%s or )\b%s\b" % (FOREVER_DB, RETAIL_DB), FOREVER_DB, text)


def build_toc(retail_toc, forever_toc):
    """Forever's header (interface, title, IDs, SavedVariables), retail's version and file list."""
    head = forever_toc.split("# Libraries", 1)[0]
    version = re.search(r"^## Version:.*$", retail_toc, re.M).group(0)
    head = re.sub(r"^## Version:.*$", version, head, flags=re.M)
    return head + "# Libraries" + retail_toc.split("# Libraries", 1)[1]


def plan(retail, forever):
    """Yield (relative path, new bytes) for every file Forever should hold."""
    for name in sorted(os.listdir(retail)):
        if name.endswith(".lua") and name not in DATA_FILES:
            with open(os.path.join(retail, name), encoding="utf-8") as f:
                yield name, rename(f.read()).encode("utf-8")
    for name in COPY_FILES:
        if os.path.exists(os.path.join(retail, name)):
            with open(os.path.join(retail, name), "rb") as f:
                yield name, f.read()
    for d in COPY_DIRS:
        for root, _, files in os.walk(os.path.join(retail, d)):
            for name in files:
                src = os.path.join(root, name)
                with open(src, "rb") as f:
                    yield os.path.relpath(src, retail), f.read()
    with open(os.path.join(retail, RETAIL_TOC), encoding="utf-8") as f:
        retail_toc = f.read()
    with open(os.path.join(forever, FOREVER_TOC), encoding="utf-8") as f:
        forever_toc = f.read()
    yield FOREVER_TOC, build_toc(retail_toc, forever_toc).encode("utf-8")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check = "--check" in sys.argv
    if len(args) != 2:
        sys.exit(__doc__)
    retail, forever = args
    changed = []
    for rel, data in plan(retail, forever):
        dst = os.path.join(forever, rel)
        if os.path.exists(dst):
            with open(dst, "rb") as f:
                if f.read() == data:
                    continue
        changed.append(rel)
        if not check:
            os.makedirs(os.path.dirname(dst) or ".", exist_ok=True)
            with open(dst, "wb") as f:
                f.write(data)
    for rel in changed:
        print(("out of date: " if check else "updated: ") + rel)
    if check and changed:
        sys.exit(1)
    if not changed:
        print("Forever is up to date.")


if __name__ == "__main__":
    main()
