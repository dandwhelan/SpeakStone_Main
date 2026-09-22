-- Quest/gossip/book text capture, built into the base addon.
--
-- This began life as a separate companion addon
-- (tools/SpeakStoneHarvester/) and is now folded in here, because asking a
-- player to find and install a second addon to contribute the one thing the
-- project most needs was a poor trade. It is on by default and can be turned
-- off in the settings panel.
--
-- Why capture at all: quest description/progress/completion text is delivered
-- by the server at runtime and exists nowhere in the files Blizzard ships, so
-- the only ways to get it are to read it off a live client or scrape a site
-- that already did. Gossip text is worse -- there is no gossip-text table in
-- the client either, and no scrapeable equivalent, so it can *only* come from
-- capture like this.
--
-- The standalone addon still exists and still works. If someone has it
-- installed and enabled, this module stands down entirely rather than both
-- recording the same lines into two different stores.

local addonName, addon = ...

local QUEST_PASSAGES = { "description", "progress", "completion" }

local function DebugPrint(...)
    if addon.DebugPrint then addon.DebugPrint(...) end
end

-- The standalone companion addon, if the player still has it, owns capture.
local function StandaloneActive()
    return C_AddOns and C_AddOns.IsAddOnLoaded
        and C_AddOns.IsAddOnLoaded("SpeakStoneHarvester")
end

local function Enabled()
    return SpeakStone_MainDB and SpeakStone_MainDB.harvestEnabled
        and not StandaloneActive()
end
addon.HarvestEnabled = Enabled

local function Store()
    SpeakStone_MainDB.harvest = SpeakStone_MainDB.harvest or {}
    local h = SpeakStone_MainDB.harvest
    h.quests = h.quests or {}
    h.gossip = h.gossip or {}
    h.itemText = h.itemText or {}
    -- What NPCs say aloud in chat (/say, /yell, whisper, party), per NPC.
    -- The client can't tell which of these are voiced; the site can, by
    -- matching them against sources that list NPC sounds. See RecordNPCChat.
    h.npcChat = h.npcChat or {}
    -- Which characters did the capturing. The store is account-wide, so one
    -- export carries lines from every character on the account, but the
    -- export header only describes whoever is logged in when it's made.
    -- The site resolves $c/$r by comparing captures from different classes,
    -- and was being told every line came from that one character. Each
    -- capture now points at an entry here. Class, race, sex and faction
    -- only, never a name; deduplicated, so it is one row per kind of
    -- character, not per login.
    h.chars = h.chars or {}
    h.npcs = h.npcs or {}
    -- Which captured quests had no audio installed at the time. A set of IDs
    -- pointing into h.quests, so it costs nothing beyond the IDs. It used to
    -- drive a separate "missing quests only" export; that is gone, and this is
    -- now only a statistic -- and a soft one, since a quest with no audio is as
    -- likely to have been removed from the game as to be waiting for a voice.
    h.missingIDs = h.missingIDs or {}
    -- Hashes of everything already submitted (see HarvestMarkSent). Without
    -- it the store only ever grew: every export resent everything ever
    -- captured, the reminder kept counting lines long since sent, and the
    -- saved-variables file -- read at every login and /reload, written at
    -- every logout -- kept getting bigger for nothing. One number per line
    -- is a fraction of the text it stands for.
    h.sent = h.sent or {}
    return h
end
addon.HarvestStore = Store

-- One hash per captured line, keyed on where it lives as well as what it
-- says, so the same greeting from two NPCs stays two lines. HashText is
-- defined in SpeakStone_Main.lua, which loads first.
local function SentKey(...)
    return addon.HashText(table.concat({ ... }, "\31"))
end

-- --------------------------------------------------------------------------
-- Secret-value guards. WoW 12.x returns tagged "secret" values where plain
-- strings used to be; touching one throws, so everything from a unit is
-- checked before use.
-- --------------------------------------------------------------------------
local function IsSecret(val)
    if val == nil then return false end
    if issecretvalue and issecretvalue(val) then return true end
    if SecretUtil and SecretUtil.IsSecretValue and SecretUtil.IsSecretValue(val) then return true end
    return false
end

-- "Creature-0-<server>-<instance>-<zone>-<creatureID>-<spawn>"
local function CreatureIDFromGUID(guid)
    if not guid or IsSecret(guid) or type(guid) ~= "string" then
        return nil
    end
    local ok, unitType, _, _, _, _, creatureID = pcall(strsplit, "-", guid)
    if ok and (unitType == "Creature" or unitType == "Vehicle") then
        return tonumber(creatureID)
    end
    return nil
end

-- Resolve who is actually speaking, or admit that it cannot.
--
-- The "npc" unit token is only meaningful while an interaction is genuinely
-- open, and it is not safe to assume it is. Observed in the wild: with a
-- replacement dialogue addon (DialogueUI and similar) the event can arrive
-- when the unit has already gone, and UnitName("npc") then returned the
-- *player's own* name -- which got recorded as the quest giver. Worse, a
-- stale GUID persisted across several different NPCs, so every gossip line
-- captured in a session collapsed into one creature ID.
--
-- Attributing a line to the wrong NPC is worse than not attributing it: it
-- gets voiced in a stranger's voice and nothing downstream can tell. So each
-- of these checks fails closed, to "unknown speaker", rather than guessing.
local function CurrentSpeaker()
    if not UnitExists("npc") then
        return {}
    end
    -- The decisive one. If "npc" has fallen back to the player, everything
    -- read from it is the player, not the speaker.
    local okUnit, isPlayer = pcall(UnitIsUnit, "npc", "player")
    if not okUnit or isPlayer then
        return {}
    end

    local guid = UnitGUID("npc")
    local name = UnitName("npc")
    if IsSecret(guid) then guid = nil end
    if IsSecret(name) then name = nil end
    if name == UnitName("player") then
        return {}
    end

    -- Race, sex and creature type decide which stand-in voice an NPC gets
    -- when it has no recorded audio of its own -- roughly a fifth of them,
    -- the generic unnamed quest givers. tools/npc_traits.py resolves this
    -- from the client's Creature/CreatureDisplayInfo tables, but its own
    -- header notes where that fails: models with no extended display record,
    -- and NPCs too new to be in the published tables at all. That second case
    -- is precisely what gets captured here -- a live client knows what a
    -- datamined table published weeks ago does not.
    --
    -- Getting it wrong is not cosmetic: with race and sex unresolved, 2,671
    -- NPCs were once all assigned the same single fallback voice. Anything
    -- unavailable is left nil rather than guessed, so the resolver can tell
    -- "not captured" from "captured as unknown".
    local sex = UnitSex("npc")
    -- 1 is the API's "unknown", which is not a fact worth recording.
    if sex ~= 2 and sex ~= 3 then sex = nil end

    local raceName, raceToken
    local okRace, r1, r2 = pcall(UnitRace, "npc")
    if okRace and not IsSecret(r1) then
        raceName, raceToken = r1, r2
    end

    local creatureType
    local okType, t = pcall(UnitCreatureType, "npc")
    if okType and not IsSecret(t) then creatureType = t end

    return {
        id = CreatureIDFromGUID(guid),
        name = name,
        sex = sex,
        race = raceName,
        raceToken = raceToken,
        creatureType = creatureType,
    }
end

-- --------------------------------------------------------------------------
-- Identity scrubbing.
--
-- Server text arrives with the player's own name already substituted in: "$n"
-- became the character's name before the addon ever saw the string. Left
-- alone that costs three things -- two players' captures of the same line are
-- different text and can never confirm each other, a stranger's character
-- name gets baked into generated audio, and that name travels to whoever the
-- capture is shared with for no purpose. So it is put back to "$n" at capture
-- time and never reaches SavedVariables at all.
--
-- Only the name is reverted. Class and race substitutions are just as real --
-- a Silvermoon Guard greets a priest as "priest", which is $c -- but words
-- like "priest" also occur naturally in quest text and a single capture
-- cannot tell the two apart. Guessing would corrupt genuine lines, so class
-- and race travel as metadata instead and get resolved where several players'
-- captures of one line can be compared.
-- --------------------------------------------------------------------------
local playerNamePattern = nil

local function Detokenize(text)
    if not text or text == "" then return text end
    if not playerNamePattern then
        local name = UnitName("player")
        if not name or name == "" then return text end
        local ok, escaped = pcall(function() return (name:gsub("(%W)", "%%%1")) end)
        if ok and escaped then
            playerNamePattern = escaped
        else
            return text
        end
    end
    local ok, res = pcall(function() return (text:gsub(playerNamePattern, "$n")) end)
    return (ok and res) or text
end

local function PlayerMetadata()
    local localizedClass, classToken = UnitClass("player")
    local localizedRace, raceToken = UnitRace("player")
    return {
        playerClass = classToken,
        playerClassName = localizedClass,
        playerRace = raceToken,
        playerRaceName = localizedRace,
        -- 1 unknown, 2 male, 3 female.
        playerSex = UnitSex("player"),
        faction = UnitFactionGroup("player"),
    }
end

-- An NPC's name, sex, race and creature type, kept once per creature ID.
-- Every quest passage used to carry its own copy -- six fields, about 150
-- bytes of saved variables each -- although the same quest giver hands out
-- every passage of a quest chain. Passages keep only the npcID now; the
-- export carries this table and the site reads a passage's speaker from it.
local NPC_TRAITS = { "npcName", "npcSex", "npcRace", "npcRaceToken", "npcCreatureType" }

local function NoteNPC(h, npcID, traits)
    local npc = h.npcs[npcID] or {}
    for _, key in ipairs(NPC_TRAITS) do
        if traits[key] ~= nil then npc[key] = traits[key] end
    end
    h.npcs[npcID] = npc
end

-- The index into h.chars for the character playing now, adding a row the
-- first time this kind of character captures anything. Cached for the
-- session: none of these change without a relog.
local charIndex

local function CurrentCharIndex()
    if charIndex then return charIndex end
    local me = PlayerMetadata()
    local chars = Store().chars
    for i, c in ipairs(chars) do
        if c.playerClass == me.playerClass and c.playerRace == me.playerRace
            and c.playerSex == me.playerSex and c.faction == me.faction then
            charIndex = i
            return i
        end
    end
    chars[#chars + 1] = me
    charIndex = #chars
    return charIndex
end

-- --------------------------------------------------------------------------
-- Recording
-- --------------------------------------------------------------------------

-- The speaker is recorded per passage, not per quest: the NPC who offers a
-- quest is frequently not the one who takes it back, and voicing the turn-in
-- in the giver's voice is a mistake that can only be fixed by regenerating.
local function RecordPassage(questID, passage, text, wasMissing)
    if not questID or questID == 0 or not text or text == "" then return end

    local h = Store()
    text = Detokenize(text)
    if h.sent[SentKey("q", questID, passage, text)] then
        return
    end
    local entry = h.quests[questID]
    if not entry then
        entry = {}
        h.quests[questID] = entry
    end
    entry.title = GetTitleText() or entry.title

    local speaker = CurrentSpeaker()
    local traits = {
        npcName = speaker.name,
        npcSex = speaker.sex,
        npcRace = speaker.race,
        npcRaceToken = speaker.raceToken,
        npcCreatureType = speaker.creatureType,
    }
    local captured = { text = text, npcID = speaker.id, char = CurrentCharIndex() }
    if speaker.id then
        -- Who the NPC is lives once in h.npcs; see NoteNPC.
        NoteNPC(h, speaker.id, traits)
    else
        -- No ID to point at, so the passage has to carry them itself.
        for key, value in pairs(traits) do captured[key] = value end
    end
    entry[passage] = captured
    if wasMissing then
        h.missingIDs[questID] = true
    end
end
addon.HarvestRecordPassage = RecordPassage

-- Gossip is keyed on npcID directly: an NPC that gives no quest has no quest
-- ID to fold into. Some NPCs cycle through several greeting variants, so
-- distinct texts are kept as a list, deduplicated by exact match so revisiting
-- does not grow it without bound.
local function RecordGossip(speaker, text)
    local npcID, npcName = speaker.id, speaker.name
    if not text or text == "" then return end
    -- With no way to say who spoke, the line cannot be voiced by anyone in
    -- particular, so there is nothing worth storing.
    if not npcID and not npcName then return end

    -- Before the duplicate check, not after: two greetings differing only by
    -- the player's name are the same greeting, and comparing raw strings
    -- would store both.
    text = Detokenize(text)

    local gossip = Store().gossip
    local key = npcID

    -- A creature ID maps to exactly one name, so an existing bucket under
    -- this ID carrying a different name means the ID is stale -- the symptom
    -- that previously merged many NPCs into one entry. Fall back to keying by
    -- name so the two stay separate, and drop the untrustworthy ID rather
    -- than record it against the wrong speaker.
    if key and npcName then
        local existing = gossip[key]
        if existing and existing.npcName and existing.npcName ~= npcName then
            DebugPrint("SpeakStone: creature " .. tostring(key)
                .. " already recorded as '" .. existing.npcName
                .. "', now reporting '" .. npcName .. "' -- keying by name.")
            key = nil
        end
    end
    if not key then
        key = "name:" .. (npcName or "unknown")
        npcID = nil
    end

    if Store().sent[SentKey("g", key, text)] then
        return
    end

    local entry = gossip[key]
    if not entry then
        entry = { npcName = npcName, npcID = npcID, texts = {} }
        gossip[key] = entry
    end
    entry.npcName = npcName or entry.npcName
    entry.npcID = npcID or entry.npcID
    -- Same reason as quest passages: this is what picks a stand-in voice for
    -- an NPC with no audio of its own.
    entry.npcSex = speaker.sex or entry.npcSex
    entry.npcRace = speaker.race or entry.npcRace
    entry.npcRaceToken = speaker.raceToken or entry.npcRaceToken
    entry.npcCreatureType = speaker.creatureType or entry.npcCreatureType
    -- Per variant, parallel to texts: which character first captured it,
    -- and how often and when it has been seen since. A greeting that stops
    -- appearing after a story beat keeps an old "last"; the one that
    -- replaced it keeps climbing. That is what lets the site tell the
    -- current line from a retired one, and voice the common ones first.
    entry.chars = entry.chars or {}
    entry.seen = entry.seen or {}
    local now = time()
    for i, existing in ipairs(entry.texts) do
        if existing == text then
            local seen = entry.seen[i]
            if seen then
                seen.count = (seen.count or 1) + 1
                seen.last = now
            else
                entry.seen[i] = { count = 1, first = now, last = now }
            end
            return
        end
    end
    table.insert(entry.texts, text)
    local i = #entry.texts
    entry.chars[i] = CurrentCharIndex()
    entry.seen[i] = { count = 1, first = now, last = now }
end

-- NPC chat lines. Same bucket shape as gossip ({ npcName, npcID, texts }),
-- so the site can treat both alike.
--
-- Kept narrow on purpose, because chat is a firehose: only creatures (a
-- GUID says so), never while the player is fighting (combat barks are most
-- of the volume and none of the story), nothing already known to be voiced,
-- and at most NPC_CHAT_MAX distinct lines per NPC.
local NPC_CHAT_MAX = 25
-- And at most this many NPCs. Past it, new speakers are ignored until an
-- export clears the store, so a week of city idling can't bloat the file.
local NPC_CHAT_MAX_NPCS = 300

local function RecordNPCChat(text, sender, guid)
    if type(text) ~= "string" or IsSecret(text) or text == "" then return end
    if IsSecret(sender) then sender = nil end
    local npcID = CreatureIDFromGUID(guid)
    if not npcID then return end
    if InCombatLockdown() or (UnitAffectingCombat and UnitAffectingCombat("player")) then return end
    if addon.IsKnownVoicedLine and addon.IsKnownVoicedLine(text) then return end

    text = Detokenize(text)
    local h = Store()
    if h.sent[SentKey("c", npcID, text)] then return end

    local entry = h.npcChat[npcID]
    if not entry then
        local npcs = 0
        for _ in pairs(h.npcChat) do npcs = npcs + 1 end
        if npcs >= NPC_CHAT_MAX_NPCS then return end
        entry = { npcName = sender, npcID = npcID, texts = {} }
        h.npcChat[npcID] = entry
    end
    entry.npcName = sender or entry.npcName
    if #entry.texts >= NPC_CHAT_MAX then return end
    for _, existing in ipairs(entry.texts) do
        if existing == text then return end
    end
    table.insert(entry.texts, text)
end

-- Books, letters, scrolls and dungeon plaques, read through ItemTextFrame.
local function RecordItemText(itemID, itemName, page, text)
    if not text or text == "" then return end
    local h = Store()
    local items = h.itemText
    -- Plaques and world objects come through the same frame as books but
    -- carry no item link, so they can only be keyed by name. Both key shapes
    -- have to be accepted; the ID is recorded whenever known so the two can be
    -- reconciled later.
    local key = itemID or itemName or "unknown"
    page = page or 1
    text = Detokenize(text)
    if h.sent[SentKey("i", key, page, text)] then
        return
    end
    local entry = items[key]
    if not entry then
        entry = { itemID = itemID, itemName = itemName, pages = {} }
        items[key] = entry
    end
    entry.itemName = itemName or entry.itemName
    entry.itemID = itemID or entry.itemID
    entry.pages[page] = text
end

-- --------------------------------------------------------------------------
-- Events
-- --------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("QUEST_DETAIL")
frame:RegisterEvent("QUEST_PROGRESS")
frame:RegisterEvent("QUEST_COMPLETE")
frame:RegisterEvent("GOSSIP_SHOW")
frame:RegisterEvent("ITEM_TEXT_READY")
frame:RegisterEvent("CHAT_MSG_MONSTER_SAY")
frame:RegisterEvent("CHAT_MSG_MONSTER_YELL")
frame:RegisterEvent("CHAT_MSG_MONSTER_WHISPER")
frame:RegisterEvent("CHAT_MSG_MONSTER_PARTY")

frame:SetScript("OnEvent", function(_, event, ...)
    if not Enabled() then return end

    if event:sub(1, 17) == "CHAT_MSG_MONSTER_" then
        local text, sender = ...
        RecordNPCChat(text, sender, (select(12, ...)))
        return
    end

    if event == "GOSSIP_SHOW" then
        local speaker = CurrentSpeaker()
        local ok, text = pcall(C_GossipInfo.GetText)
        -- A greeting already matched to a voiced clip is already in the
        -- corpus; recording it again only grows the store.
        if ok and not (addon.GossipTextKnown and addon.GossipTextKnown(speaker.id, text)) then
            RecordGossip(speaker, text)
        end
        return
    end

    if event == "ITEM_TEXT_READY" then
        local itemLink = ItemTextGetItem()
        local itemID, itemName
        if itemLink then
            pcall(function()
                itemID = tonumber(itemLink:match("item:(%d+)"))
                itemName = itemLink:match("%[(.-)%]")
            end)
        end
        if not itemName then
            local ok, rawItem = pcall(ItemTextGetItem)
            if ok and type(rawItem) == "string" then itemName = rawItem end
        end
        RecordItemText(itemID, itemName, ItemTextGetPage() or 1, ItemTextGetText())
        return
    end

    local questID = GetQuestID()
    -- Same for quest text: audio for a passage means its text was already
    -- in hand when the clip was generated.
    local passage = (event == "QUEST_DETAIL" and "description")
        or (event == "QUEST_PROGRESS" and "progress")
        or (event == "QUEST_COMPLETE" and "completion")
    if passage and questID and addon.FindSound and addon.FindSound({ questID .. "_" .. passage }) then
        return
    end
    if event == "QUEST_DETAIL" then
        RecordPassage(questID, "description", GetQuestText())
    elseif event == "QUEST_PROGRESS" then
        RecordPassage(questID, "progress", GetProgressText())
    elseif event == "QUEST_COMPLETE" then
        RecordPassage(questID, "completion", GetRewardText())
    end
end)

-- --------------------------------------------------------------------------
-- Submitting
--
-- Capture is only worth anything once it reaches the website; until then it
-- is a table in a saved-variables file doing nobody any good. Nothing in the
-- addon ever said so unprompted, so a player could collect for months and
-- never think to send it. This is that prompt.
--
-- It is a reminder, not a limit: nothing is dropped, capture keeps running,
-- and a player who ignores it loses nothing.
-- --------------------------------------------------------------------------

-- Roughly a long evening's play. Low enough to catch people early, high
-- enough not to fire at someone who just installed the addon.
local REMIND_AT = 250
-- And not again for this long, however much more accumulates. A reminder that
-- arrives every login is an annoyance, not a prompt.
local REMIND_INTERVAL = 3 * 24 * 60 * 60

-- Top-level entries only -- quests, NPCs and books -- which is the same thing
-- the export counts. Deliberately not the full per-passage walk HarvestCounts
-- does: this runs at login, where the cheap answer is the right one.
function addon.HarvestEntryCount()
    local h = Store()
    local count = 0
    for _ in pairs(h.quests) do count = count + 1 end
    for _ in pairs(h.gossip) do count = count + 1 end
    for _ in pairs(h.itemText) do count = count + 1 end
    for _ in pairs(h.npcChat) do count = count + 1 end
    return count
end

-- Whether the store has grown past the point of being worth sending in. The
-- settings dashboard asks this to colour its card, so it carries no
-- side-effects and no time check.
--
-- Takes the count when the caller already has it. The dashboard calls
-- HarvestCounts immediately before this, which walks the whole store, and
-- then walked it a second time here for a number the first walk had already
-- counted -- twice over on every settings open, since the window refreshed
-- itself once on build and again on show.
function addon.HarvestShouldSubmit(entries)
    return (entries or addon.HarvestEntryCount()) >= REMIND_AT
end

-- Called after an export: the player has just been handed the payload, so
-- the clock starts again whether or not they paste it anywhere.
function addon.HarvestMarkOffered()
    Store().lastReminder = time()
end

function addon.HarvestRemindIfLarge()
    if not Enabled() then return end

    local count = addon.HarvestEntryCount()
    if count < REMIND_AT then return end

    local h = Store()
    local now = time()
    if h.lastReminder and (now - h.lastReminder) < REMIND_INTERVAL then
        return
    end
    -- Not over a fight: a dialog popping up mid-pull is how a reminder gets
    -- dismissed unread. Try again once combat ends instead.
    if InCombatLockdown() then
        local waiter = CreateFrame("Frame")
        waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        waiter:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            addon.HarvestRemindIfLarge()
        end)
        return
    end
    h.lastReminder = now

    -- A dialog, not only a chat line: the chat line scrolled away in the
    -- login spam and was the only prompt there was.
    StaticPopup_Show("SPEAKSTONE_HARVEST_REMINDER", count)
    print("|cffffd100SpeakStone:|r " .. count .. " captured entries are waiting to be sent in."
        .. " |cff00ff00/ssharvest export|r copies them out for |cff00ccffspeakstone.beanw.co.uk|r.")
end

StaticPopupDialogs["SPEAKSTONE_HARVEST_REMINDER"] = {
    text = "SpeakStone has captured %d quests, greetings and books that aren't voiced yet.\n\n"
        .. "Send them in at speakstone.beanw.co.uk and they can be voiced for everyone -- "
        .. "greetings and book text can only come from a live client like yours.",
    button1 = "Export now",
    button2 = "Later",
    OnAccept = function()
        if addon.ShowHarvestExport then addon.ShowHarvestExport() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- --------------------------------------------------------------------------
-- Counting and export
-- --------------------------------------------------------------------------
function addon.HarvestCounts()
    local h = Store()
    local quests, passages, unvoiced = 0, 0, 0
    for _, entry in pairs(h.quests) do
        quests = quests + 1
        for _, passage in ipairs(QUEST_PASSAGES) do
            local captured = entry[passage]
            if captured then
                passages = passages + 1
                -- A passage with no creature ID cannot be matched to a voice.
                if not captured.npcID then unvoiced = unvoiced + 1 end
            end
        end
    end
    local npcs, lines = 0, 0
    for _, entry in pairs(h.gossip) do
        npcs = npcs + 1
        lines = lines + #entry.texts
    end
    local items, pages = 0, 0
    for _, entry in pairs(h.itemText) do
        items = items + 1
        for _ in pairs(entry.pages) do pages = pages + 1 end
    end
    local missing = 0
    for _ in pairs(h.missingIDs) do missing = missing + 1 end
    local chatNPCs, chatLines = 0, 0
    for _, entry in pairs(h.npcChat) do
        chatNPCs = chatNPCs + 1
        chatLines = chatLines + #entry.texts
    end
    local sent = 0
    for _ in pairs(h.sent) do sent = sent + 1 end
    return quests, passages, unvoiced, npcs, lines, items, pages, missing, chatNPCs, chatLines, sent
end

-- Minimal Lua-table serialiser. The website's parser only cares about the
-- shape (top-level .quests/.gossip/.itemText plus locale and player
-- metadata), not which addon wrote it, so this output is interchangeable with
-- the standalone Harvester's.
-- One pass over the string rather than four chained gsubs, each of which
-- copied the whole thing again. Quest and gossip text is the bulk of the
-- payload, so every passage in the store was being rebuilt four times over on
-- every export. A replacement table also removes the ordering trap the old
-- chain had to be careful about -- each character is matched and replaced
-- exactly once, so an added escape can no longer be escaped again.
local ESCAPES = { ["\\"] = "\\\\", ['"'] = '\\"', ["\r"] = "\\r", ["\n"] = "\\n" }

local function EscapeString(text)
    return (text:gsub('[\\"\r\n]', ESCAPES))
end

-- Forever reports interface numbers in the 16xxx band, which no Blizzard
-- client uses: retail is 110000+, and every Classic flavour lands between
-- 11500 and 50500. Matching the band rather than one exact number means a
-- Forever point release keeps being recognised.
local FOREVER_INTERFACE_MIN = 16000
local FOREVER_INTERFACE_MAX = 16999

local function HarvestFlavour()
    local interfaceVersion = select(4, GetBuildInfo())
    if type(interfaceVersion) == "number"
        and interfaceVersion >= FOREVER_INTERFACE_MIN
        and interfaceVersion <= FOREVER_INTERFACE_MAX then
        return "forever"
    end
    return "retail"
end

-- Append this table's lines to `out`, depth-first.
--
-- This used to return a string per level, which the level above embedded in a
-- string of its own: with the payload four tables deep, every byte of it was
-- copied four times and the intermediates handed straight to the collector. A
-- player with a few hundred captured quests exports megabytes, so that was
-- the export's whole cost. Fragments go into one buffer now and are joined
-- once at the end.
--
-- The old version also wrapped each key in a pcall over a fresh closure --
-- two allocations and a protected call per key, tens of thousands of them on
-- a real store -- to guard operations that cannot throw on the only key types
-- this data holds. A key that is neither a string nor a number has no
-- representation here and is skipped rather than written out as
-- "table: 0x...", which is what the guarded path produced.
local function SerializeInto(out, tbl, indent)
    local childIndent = indent .. "  "
    for k, v in pairs(tbl) do
        local keyStr
        local kt = type(k)
        if kt == "number" then
            keyStr = "[" .. k .. "]"
        elseif kt == "string" then
            -- Escaped like any other string. Table keys are not all ours to
            -- choose: books and plaques are keyed by their in-game name when
            -- they carry no item ID, and a name holding a quote -- or a
            -- backslash, or a newline -- closed the key early and left the
            -- whole export unparseable at the far end.
            keyStr = '["' .. EscapeString(k) .. '"]'
        end
        if keyStr then
            local vt = type(v)
            if vt == "table" then
                out[#out + 1] = indent .. keyStr .. " = {\n"
                SerializeInto(out, v, childIndent)
                out[#out + 1] = indent .. "},\n"
            elseif vt == "string" then
                out[#out + 1] = indent .. keyStr .. ' = "' .. EscapeString(v) .. '",\n'
            elseif vt == "number" or vt == "boolean" then
                out[#out + 1] = indent .. keyStr .. " = " .. tostring(v) .. ",\n"
            end
        end
    end
end

--- How much of a payload to put in front of the player at once.
---
--- The export goes into a game edit box for the player to select and copy,
--- and that widget is not built for a document. A store that has been
--- collecting for months serialises to megabytes -- the reminder to submit
--- fires at 250 entries and nothing prunes the store afterwards, so this is
--- the ordinary end state of an addon left switched on, not a pathological
--- one. Past some size the box stops being something a person can select and
--- copy out, and the failure is silent: the text is simply not all there.
---
--- So the payload is cut into pieces, each a complete and valid export in its
--- own right rather than a fragment that only means something reassembled.
--- The website already merges and deduplicates submissions, so pasting three
--- pieces one after another lands exactly what one big paste would have, and
--- a player who stops after the first has still sent real, usable data rather
--- than a broken half of something.
---
--- The number is deliberately conservative and has not been measured against
--- a live client -- it wants checking against a real edit box with a real
--- store behind it, and can be raised if the widget turns out to cope.
local EXPORT_BATCH_BYTES = 384 * 1024

--- Build the export payload: everything captured, of every kind, split into
--- pieces no larger than `maxBytes`.
---
--- Returns the list of payload strings and the number of top-level entries
--- across all of them.
---
--- There used to be a second, narrower export of "quests with no audio
--- installed" only, promoted as the most useful thing to submit. Two things
--- were wrong with it. Most of those quests turn out to have been removed from
--- the game, so they can never be voiced no matter how often they are
--- submitted. And it dropped gossip and book text from the payload entirely --
--- which is precisely the material that cannot be obtained any other way,
--- since neither has a table in the client or a scrapeable equivalent. The
--- narrow export was therefore worth less than the full one it was recommended
--- over, so there is now only the full one.
function addon.HarvestExportBatches(maxBytes)
    maxBytes = maxBytes or EXPORT_BATCH_BYTES
    local h = Store()

    -- Every piece carries the same metadata. Which client, which build and
    -- which player wrote a capture is not a property of the quests in it, so
    -- a piece without it would be worth less than the whole.
    local meta = {
        locale = GetLocale(),
        build = select(2, GetBuildInfo()),
        -- The interface number, and the site's name for the game it belongs
        -- to. Quest IDs -- and the flat sound filenames built from them -- are
        -- only unique within one game's corpus, and Forever allocates IDs that
        -- interleave the retail space, so a capture that does not say which
        -- game it came from cannot be told apart from one that did. Retail is
        -- the default because every capture before Forever was retail.
        --
        -- The raw interface number goes alongside deliberately: the flavour is
        -- this addon's reading of it, and if a later Forever build moves out
        -- of the band below, the site can still reclassify from the number
        -- without waiting for players to update.
        interface = select(4, GetBuildInfo()),
        flavour = HarvestFlavour(),
        addonVersion = (C_AddOns and C_AddOns.GetAddOnMetadata
                        and C_AddOns.GetAddOnMetadata(addonName, "Version")) or "unknown",
    }
    for key, value in pairs(PlayerMetadata()) do
        meta[key] = value
    end
    -- Every piece carries both lists, since any piece may point into them.
    meta.chars = h.chars
    meta.npcs = h.npcs
    local header = {}
    SerializeInto(header, meta, "  ")
    header = table.concat(header)

    -- One flat, ordered list of everything to write, so the cut between two
    -- pieces can fall anywhere without either losing an entry or repeating
    -- one. Grouped by kind, which is what lets a piece hold at most one open
    -- sub-table at a time.
    local plan = {}
    for key, entry in pairs(h.quests) do plan[#plan + 1] = { "quests", key, entry } end
    for key, entry in pairs(h.gossip) do plan[#plan + 1] = { "gossip", key, entry } end
    for key, entry in pairs(h.itemText) do plan[#plan + 1] = { "itemText", key, entry } end
    for key, entry in pairs(h.npcChat) do plan[#plan + 1] = { "npcChat", key, entry } end

    local batches = {}
    local out, size, openKind, inBatch

    local function Emit(text)
        out[#out + 1] = text
        size = size + #text
    end
    local function Begin()
        out, size, openKind, inBatch = {}, 0, nil, 0
        Emit("SpeakStone_MainExport = {\n")
        Emit(header)
    end
    local function CloseKind()
        if openKind then
            Emit("  },\n")
            openKind = nil
        end
    end
    local function Finish()
        CloseKind()
        Emit("}")
        batches[#batches + 1] = table.concat(out)
    end

    Begin()
    for _, item in ipairs(plan) do
        local kind, key, entry = item[1], item[2], item[3]

        -- Serialised on its own first, because whether it fits cannot be known
        -- until its size is.
        local piece = {}
        piece[#piece + 1] = "    " ..
            (type(key) == "number" and ("[" .. key .. "]")
                                    or ('["' .. EscapeString(tostring(key)) .. '"]')) .. " = {\n"
        SerializeInto(piece, entry, "      ")
        piece[#piece + 1] = "    },\n"
        piece = table.concat(piece)

        local opening = (openKind ~= kind) and ('  ["' .. kind .. '"] = {\n') or nil
        -- Room for what this entry costs plus the punctuation that has to
        -- follow it: closing whatever sub-table is open, and the final brace.
        local needed = #piece + (opening and #opening or 0) + (openKind and 5 or 0) + 1

        -- An entry larger than a whole batch still has to go somewhere, so a
        -- batch holding nothing yet always accepts one. Without that guard
        -- this loop would cut forever without ever writing it.
        if inBatch > 0 and size + needed > maxBytes then
            Finish()
            Begin()
            opening = '  ["' .. kind .. '"] = {\n'
        end

        if openKind ~= kind then
            CloseKind()
            Emit(opening or ('  ["' .. kind .. '"] = {\n'))
            openKind = kind
        end
        Emit(piece)
        inBatch = inBatch + 1
    end
    Finish()

    return batches, #plan
end

--- The whole capture as a single payload, however large.
---
--- Kept because it is the shape anything outside this file expects, and
--- because the split above has to be able to say what it would otherwise have
--- produced. Everything the player sees goes through HarvestExportBatches.
function addon.HarvestExportText()
    -- Count everything the payload actually carries, not just quests. Counting
    -- quests alone made a full export refuse to open whenever a session had
    -- captured gossip but no new quest text -- which is the normal shape of a
    -- session spent talking to NPCs -- and the "nothing captured yet" message
    -- then wrongly blamed the capture setting for data that was sitting right
    -- there in the payload.
    local batches, count = addon.HarvestExportBatches(math.huge)
    return batches[1], count
end

-- Every captured line's SentKey, as of now. Taken when the export window
-- opens, so marking it sent later clears exactly what the player was given
-- and nothing captured since.
function addon.HarvestSnapshot()
    local h = Store()
    local snap = {}
    for questID, entry in pairs(h.quests) do
        for _, passage in ipairs(QUEST_PASSAGES) do
            local captured = entry[passage]
            if captured and captured.text then
                snap[SentKey("q", questID, passage, captured.text)] = true
            end
        end
    end
    for key, entry in pairs(h.gossip) do
        for _, text in ipairs(entry.texts or {}) do
            snap[SentKey("g", key, text)] = true
        end
    end
    for key, entry in pairs(h.itemText) do
        for page, text in pairs(entry.pages or {}) do
            snap[SentKey("i", key, page, text)] = true
        end
    end
    for key, entry in pairs(h.npcChat) do
        for _, text in ipairs(entry.texts or {}) do
            snap[SentKey("c", key, text)] = true
        end
    end
    return snap
end

-- The player has pasted it in: drop those lines from the store and remember
-- their hashes, so meeting the same line again doesn't capture it again.
-- Returns how many lines were cleared.
function addon.HarvestMarkSent(snap)
    if type(snap) ~= "table" then return 0 end
    local h = Store()
    local cleared = 0
    local function Take(key)
        if snap[key] then
            h.sent[key] = true
            cleared = cleared + 1
            return true
        end
    end

    for questID, entry in pairs(h.quests) do
        local left = false
        for _, passage in ipairs(QUEST_PASSAGES) do
            local captured = entry[passage]
            if captured then
                if captured.text and Take(SentKey("q", questID, passage, captured.text)) then
                    entry[passage] = nil
                else
                    left = true
                end
            end
        end
        if not left then
            h.quests[questID] = nil
            h.missingIDs[questID] = nil
        end
    end
    for key, entry in pairs(h.gossip) do
        -- texts, chars and seen are parallel lists; they move together.
        local kept, keptChars, keptSeen = {}, {}, {}
        for i, text in ipairs(entry.texts or {}) do
            if not Take(SentKey("g", key, text)) then
                local n = #kept + 1
                kept[n] = text
                keptChars[n] = entry.chars and entry.chars[i]
                keptSeen[n] = entry.seen and entry.seen[i]
            end
        end
        if #kept == 0 then
            h.gossip[key] = nil
        else
            entry.texts, entry.chars, entry.seen = kept, keptChars, keptSeen
        end
    end
    for key, entry in pairs(h.itemText) do
        for page, text in pairs(entry.pages or {}) do
            if Take(SentKey("i", key, page, text)) then
                entry.pages[page] = nil
            end
        end
        if not next(entry.pages or {}) then
            h.itemText[key] = nil
        end
    end
    for key, entry in pairs(h.npcChat) do
        local kept = {}
        for _, text in ipairs(entry.texts or {}) do
            if not Take(SentKey("c", key, text)) then
                kept[#kept + 1] = text
            end
        end
        if #kept == 0 then
            h.npcChat[key] = nil
        else
            entry.texts = kept
        end
    end
    -- An NPC nobody remaining points at has nothing left to describe.
    local referenced = {}
    for _, entry in pairs(h.quests) do
        for _, passage in ipairs(QUEST_PASSAGES) do
            local captured = entry[passage]
            if captured and captured.npcID then referenced[captured.npcID] = true end
        end
    end
    for npcID in pairs(h.npcs) do
        if not referenced[npcID] then h.npcs[npcID] = nil end
    end
    h.lastReminder = nil
    return cleared
end

function addon.HarvestWipe()
    local h = Store()
    h.quests, h.gossip, h.itemText, h.missingIDs, h.npcChat = {}, {}, {}, {}, {}
    h.npcs = {}
    -- Nothing left to submit, so nothing to be reminded about: an empty store
    -- should not sit silently through the interval before it can prompt again.
    h.lastReminder = nil
end

-- --------------------------------------------------------------------------
-- Migration
--
-- Two older stores fed into this one: the standalone addon's saved variables,
-- and the short-lived missingCaptures table this addon used before capture
-- was folded in. Both are drained on first load and then left alone, so
-- nothing a player already collected is stranded.
-- --------------------------------------------------------------------------
-- Bumped when captured data has to be repaired rather than just carried
-- forward.
--   2: speaker attribution was unreliable -- see CurrentSpeaker.
--   3: the pass for 2 kept quest npcIDs. Every one of them was a zoneUID, so
--      they all had to go, not just the ones that were obviously wrong.
--   4: NPC traits moved off every quest passage into h.npcs. A layout
--      change, not a repair: nothing is lost, the store just gets smaller.
local HARVEST_SCHEMA = 4

local function HoistNPCTraits(h)
    for _, entry in pairs(h.quests) do
        for _, passage in ipairs(QUEST_PASSAGES) do
            local captured = entry[passage]
            if captured and captured.npcID then
                NoteNPC(h, captured.npcID, captured)
                for _, key in ipairs(NPC_TRAITS) do captured[key] = nil end
            end
        end
    end
end

-- Throw away what the speaker bug produced.
--
-- Gossip goes entirely: it is keyed on the speaker, and a stale creature ID
-- merged many different NPCs into one bucket, so there is no way after the
-- fact to tell which line belonged to whom. Keeping it would mean submitting
-- lines to be voiced by an NPC who never said them, which is worse than
-- having none.
--
-- Quest text is kept -- the text itself is correct and is keyed by quest ID,
-- not by speaker. Every npcID recorded before the fix is a zoneUID rather
-- than a creature ID, though, so all of them go: a plausible-looking but
-- wrong ID is more dangerous than none, because nothing downstream can tell
-- it is wrong. npcName was always read correctly and is kept, except where it
-- is the player's own name, which is the one case that was visibly broken.
local function RepairSpeakerData(h)
    local dropped = 0
    for _ in pairs(h.gossip) do dropped = dropped + 1 end
    h.gossip = {}

    local playerName = UnitName("player")
    local ids, names = 0, 0
    for _, entry in pairs(h.quests) do
        for _, passage in ipairs(QUEST_PASSAGES) do
            local captured = entry[passage]
            if captured then
                if captured.npcID then
                    captured.npcID = nil
                    ids = ids + 1
                end
                if captured.npcName and captured.npcName == playerName then
                    captured.npcName = nil
                    names = names + 1
                end
            end
        end
    end

    if dropped > 0 or ids > 0 or names > 0 then
        print("SpeakStone: repaired captured data after a speaker-ID bug -- dropped "
            .. dropped .. " gossip capture(s), cleared " .. ids
            .. " wrong NPC ID(s) and " .. names
            .. " passage(s) attributed to your own character. All quest text was kept."
            .. " Talk to NPCs again to re-capture gossip with correct IDs.")
    end
end

function addon.HarvestMigrate()
    local h = Store()
    local moved = 0

    local schema = h.schema or 1
    if schema < 3 then
        RepairSpeakerData(h)
    end
    if schema < 4 then
        HoistNPCTraits(h)
    end
    h.schema = HARVEST_SCHEMA

    local old = SpeakStone_MainDB.missingCaptures
    if old and old.quests then
        for questID, entry in pairs(old.quests) do
            if not h.quests[questID] then
                h.quests[questID] = entry
                moved = moved + 1
            end
            h.missingIDs[questID] = true
        end
        SpeakStone_MainDB.missingCaptures = nil
    end

    if type(SpeakStoneHarvesterDB) == "table" then
        for questID, entry in pairs(SpeakStoneHarvesterDB.quests or {}) do
            if not h.quests[questID] then
                h.quests[questID] = entry
                moved = moved + 1
            end
        end
        for npcID, entry in pairs(SpeakStoneHarvesterDB.gossip or {}) do
            if not h.gossip[npcID] then h.gossip[npcID] = entry end
        end
        for key, entry in pairs(SpeakStoneHarvesterDB.itemText or {}) do
            if not h.itemText[key] then h.itemText[key] = entry end
        end
    end

    if moved > 0 then
        DebugPrint("SpeakStone: imported " .. moved .. " previously captured quest(s).")
    end
end
