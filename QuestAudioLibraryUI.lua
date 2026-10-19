local _, addon = ...

-- Where the list starts: below the Quests / Gossip / Books tabs and the
-- search box (owner, 2026-09-28: a Books button across the top).
local LIST_TOP = -86
-- Typing in the search box used to re-filter on every keystroke, and filtering
-- by name means resolving a title for every quest in the library. Held back by
-- this much, a burst of typing costs one pass instead of one per character.
local SEARCH_DEBOUNCE = 0.2
-- How long one pass of the filter may hold the client's frame before handing
-- it back. Resolving a quest title is two protected API calls, and a name
-- search asks for one per quest that does not match on ID -- tens of
-- thousands of them with a full pack set, which is seconds of frozen client
-- if it is done in a single pass. The search runs across frames instead, so
-- the window stays responsive and results fill in as they are found.
local FILTER_BUDGET_MS = 8
-- Consulted only every so many quests: reading the clock costs more than the
-- comparison it guards, and a hundred quests is far below one frame's worth.
local FILTER_CHECK_EVERY = 100
-- Used where debugprofilestop is unavailable, since there is then no way to
-- ask how long the pass has been running.
local FILTER_CHUNK = 400

-- The window, built the first time it is opened. It used to be assembled at
-- file scope: fourteen rows of a button and three sub-buttons apiece, around
-- eighty frames, put together on every login whether or not anyone ever looked
-- at the library.
local UI
local searchTimer

-- --------------------------------------------------------------------------
-- Voice info (race and sex of the voice on each clip)
--
-- Each audio pack can hand its own voice data to SpeakStone_RegisterSoundPack
-- (format documented there). Packs without it, or older packs, just show no
-- voice, and the library looks exactly as it did before.
-- --------------------------------------------------------------------------
local SEX_NAMES = { M = "male", F = "female", N = "" }
local QUEST_TYPE_KEYS = { description = "d", progress = "p", completion = "c" }
-- Tag -> { label = "Human male", search = " human male " }. A few dozen
-- distinct tags cover every clip, so this stays tiny.
local tagCache = {}

local function RaceName(code)
    for _, info in pairs(addon.voiceSources or {}) do
        local name = info.races and info.races[code]
        if name then return name end
    end
    return code
end

local function DescribeTag(tag)
    if type(tag) ~= "string" or tag == "" then return nil end
    local cached = tagCache[tag]
    if cached then return cached end
    local sexCode = tag:sub(-1)
    local raceCode = tag:sub(1, -2)
    if not SEX_NAMES[sexCode] then
        sexCode, raceCode = nil, tag
    end
    local sex = sexCode and SEX_NAMES[sexCode] or ""
    local label
    if raceCode == "" then
        -- A bare "M"/"F": the pack knows the sex but not a race worth naming.
        if sex == "" then return nil end
        label = sex:sub(1, 1):upper() .. sex:sub(2)
    else
        local race = RaceName(raceCode)
        label = sex ~= "" and (race .. " " .. sex) or race
    end
    cached = { label = label, search = " " .. label:lower() .. " " }
    tagCache[tag] = cached
    return cached
end

-- kind is "npc" or "quest"; questType picks one of a quest's three clips,
-- or nil for the quest as a whole (its description voice, else the first).
local function GetVoice(kind, id, questType)
    local entry
    for _, info in pairs(addon.voiceSources or {}) do
        local byID = info[kind]
        entry = byID and byID[id]
        if entry then break end
    end
    if type(entry) == "table" then
        if questType then
            entry = entry[QUEST_TYPE_KEYS[questType]]
        else
            entry = entry.d or entry.p or entry.c
        end
    end
    return DescribeTag(entry)
end
addon.GetVoiceInfo = GetVoice

-- Every word typed must start a word of the voice label, so "male" does not
-- match "female" and "orc f" finds female orcs.
local function VoiceMatches(voice, words)
    if not voice or #words == 0 then return false end
    for _, word in ipairs(words) do
        if not voice.search:find(" " .. word, 1, true) then return false end
    end
    return true
end

-- --------------------------------------------------------------------------
-- Quest titles
--
-- Resolving one is two pcall'd API calls, and the search filter asks for every
-- quest in the library -- tens of thousands of them with a full pack set. Once
-- known, a title never changes, so it is kept.
--
-- A miss is a different matter: the client may simply not know the quest yet
-- and may learn it later, so misses are remembered only for as long as the
-- window stays open, and are dropped each time it is reopened.
-- --------------------------------------------------------------------------
local titleCache = {}
local titleMisses = {}

local function GetQuestTitle(questID)
    if not questID then return nil end

    local cached = titleCache[questID]
    if cached then return cached end
    if titleMisses[questID] then return nil end

    local resolved
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
        if ok and title and title ~= "" and not (issecretvalue and issecretvalue(title)) then
            resolved = title
        end
    end
    if not resolved and QuestUtils_GetQuestName then
        local ok, title = pcall(QuestUtils_GetQuestName, questID)
        if ok and title and title ~= "" and not (issecretvalue and issecretvalue(title)) then
            resolved = title
        end
    end

    -- The client only knows a title for a quest it has actually seen --
    -- your faction's, your expansion's, ones you've picked up. That is a
    -- small slice of a full pack set, which is why most rows showed
    -- "Unknown quest". QuestTitles.lua ships a static Wowhead-sourced
    -- lookup built by tools/build_quest_titles.py that covers the rest;
    -- it is a fallback, not a delete step, since the client's own name is
    -- from the player's own locale where it exists.
    if not resolved and SpeakStone_QuestTitles then
        local title = SpeakStone_QuestTitles[questID]
        if title and title ~= "" then
            resolved = title
        end
    end

    if resolved then
        titleCache[questID] = resolved
    else
        titleMisses[questID] = true
    end
    return resolved
end

-- The client only knows a quest's title once it has the quest's data, which
-- for most of a pack's tens of thousands of quests it does not. Asking the
-- server closes that gap, but it is a per-quest round trip, so it is asked
-- only for the handful of rows actually on screen -- never for the filter
-- pass, which walks the whole library.
--
-- Requests are remembered for the session: a quest the server declined to
-- send is not going to answer differently a scroll later.
local titleRequests = {}
local pendingRefresh = false

local function RequestQuestTitle(questID)
    if not questID or titleCache[questID] or titleRequests[questID] then return end
    if not (C_QuestLog and C_QuestLog.RequestLoadQuestByID) then return end
    titleRequests[questID] = true
    pcall(C_QuestLog.RequestLoadQuestByID, questID)
end

-- Registered only while the window is open, from its OnShow. QUEST_DATA_LOAD_RESULT
-- fires for every quest anything in the UI asks the server about, all
-- session, and the only reason to hear it is to redraw a list that is on
-- screen -- so a player who never opens the library was paying for an event
-- handler that could not have anything to do.
local titleLoader = CreateFrame("Frame")
titleLoader:SetScript("OnEvent", function(_, _, questID, success)
    if not success or not questID or not titleRequests[questID] then return end
    -- The title is known now, so the miss recorded for it is stale.
    titleMisses[questID] = nil
    if pendingRefresh then return end
    pendingRefresh = true
    -- Answers arrive in bursts, one per row; redrawing once covers them all.
    C_Timer.After(0.1, function()
        pendingRefresh = false
        if UI and UI:IsShown() then
            UI:UpdateList()
        end
    end)
end)

-- --------------------------------------------------------------------------
-- Book names. Only book clips reach the Books tab: files named
-- "<name>_page<n>", where <name> is "item<ID>", "item_<title>", "<title>" or
-- "<title>_<first words of page 1>". This turns <name> back into something to
-- read. Item IDs are resolved through the client when it knows the item.
-- --------------------------------------------------------------------------
local bookNameCache = {}
local function BookName(base)
    local cached = bookNameCache[base]
    if cached then return cached end
    local name
    local itemID = tonumber(base:match("^item(%d+)$") or "")
    if itemID then
        local ok, n = pcall(function()
            return (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)) or GetItemInfo(itemID)
        end)
        if ok and n and n ~= "" and not (issecretvalue and issecretvalue(n)) then
            name = n
        else
            return "Item " .. itemID    -- not cached: the client may learn the name later
        end
    elseif SpeakStone_BookTitles and SpeakStone_BookTitles[base] then
        name = SpeakStone_BookTitles[base]
    else
        name = base:gsub("^item_", ""):gsub("_", " ")
        name = name:gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest end)
    end
    bookNameCache[base] = name
    return name
end

-- --------------------------------------------------------------------------
-- Rows of every kind share one list in the Favourites and Recent tabs, so a
-- row says what it is by its shape rather than by the tab it is in.
-- Keys match addon.ClipItemKey in SpeakStone_Main.lua.
-- --------------------------------------------------------------------------
local function EntryKind(entry)
    if entry.kind == "book" then return "book" end
    if entry.npcID then return "gossip" end
    return "quest"
end

local function EntryKey(entry)
    local kind = EntryKind(entry)
    if kind == "book" then return "b:" .. entry.book.base end
    if kind == "gossip" then return "g:" .. entry.npcID .. ":" .. entry.variant end
    return "q:" .. entry.id
end

local STAR_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"

local function PaintStar(button, on)
    local tex = button:GetNormalTexture()
    if not tex then return end
    tex:SetDesaturated(not on)
    tex:SetAlpha(on and 1 or 0.35)
end
addon.PaintFavouriteStar = PaintStar


-- --------------------------------------------------------------------------
-- The tree: expansions, then groups, then quests (Compendium style)
-- --------------------------------------------------------------------------
-- An expansion is read off the pack a quest's clips live in. Inside it a quest
-- is grouped by its zone when SpeakStone_QuestZones names one, and otherwise by
-- the first letter of its title. Progress is how many of its quests the player
-- has heard play.

local EXPANSION_NAMES = {
    Classic = "Classic", TheBurningCrusade = "The Burning Crusade", WrathoftheLichKing = "Wrath of the Lich King",
    Cataclysm = "Cataclysm", MistsofPandaria = "Mists of Pandaria", WarlordsofDraenor = "Warlords of Draenor",
    Legion = "Legion", BattleforAzeroth = "Battle for Azeroth", Shadowlands = "Shadowlands",
    Dragonflight = "Dragonflight", TheWarWithin = "The War Within", Midnight = "Midnight",
    Chatter = "Chatter and greetings",
}
-- WoW Forever has no expansions: its quests sit under the pack they shipped in.
local FOREVER_PACK_NAMES = { Audio_Pack1 = "Audio Pack 1", Audio_Pack2 = "Audio Pack 2", Chatter = "Chatter and greetings" }
local EXPANSION_ORDER = {
    "Classic", "The Burning Crusade", "Wrath of the Lich King", "Cataclysm", "Mists of Pandaria",
    "Warlords of Draenor", "Legion", "Battle for Azeroth", "Shadowlands", "Dragonflight", "The War Within",
    "Midnight", "Chatter and greetings", "WoW Forever", "Other",
}
local FOREVER_ORDER = { "Audio Pack 1", "Audio Pack 2", "Chatter and greetings", "WoW Forever", "Other" }
if addon.IS_FOREVER then EXPANSION_ORDER = FOREVER_ORDER end
local EXPANSION_RANK = {}
for rank, name in ipairs(EXPANSION_ORDER) do EXPANSION_RANK[name] = rank end

local function ExpansionOf(pack)
    if type(pack) ~= "string" then return "Other" end
    local foreverShort = pack:match("^SpeakStone_Forever_(.+)$")
    if foreverShort then
        return addon.IS_FOREVER and FOREVER_PACK_NAMES[foreverShort] or "WoW Forever"
    end
    local short = pack:match("^SpeakStone_Pack_(.+)$") or pack
    short = short:gsub("_Part%d+$", "")
    return EXPANSION_NAMES[short] or short
end
addon.GuideExpansionOf = ExpansionOf

local function IsHeard(id)
    local heard = SpeakStone_MainDB and SpeakStone_MainDB.heardQuests
    if not heard then return false end
    return (heard[id .. "_description"] or heard[id .. "_progress"] or heard[id .. "_completion"]) and true or false
end

local function FirstLetter(text)
    if type(text) == "string" and text ~= "" then
        local first = text:sub(1, 1):upper()
        if first:match("%a") then return first end
    end
    return "#"
end

-- Where a quest is and who gives it come from QuestInfo.lua (built by
-- tools/build_quest_info.py): names are kept once in a pool and quests point into it.
local function PoolName(index)
    local pool = SpeakStone_QuestNames
    return index and pool and pool[index] or nil
end

local function ZoneOf(id)
    local zones = SpeakStone_QuestZoneOf
    return zones and PoolName(zones[id]) or nil
end

local function ContinentOf(id)
    local zones, continents = SpeakStone_QuestZoneOf, SpeakStone_QuestContinentOf
    local zone = zones and zones[id]
    return zone and continents and PoolName(continents[zone]) or nil
end

local function GiverOf(id)
    local givers = SpeakStone_QuestGiverOf
    return givers and PoolName(givers[id]) or nil
end
addon.GuideZoneOf, addon.GuideGiverOf = ZoneOf, GiverOf

local UNKNOWN = "Unsorted"

local CONTINENT_ORDER = {
    "Eastern Kingdoms", "Kalimdor", "Outland", "Northrend", "Pandaria", "Draenor", "Broken Isles", "Argus",
    "Kul Tiras", "Zandalar", "The Shadowlands", "Dragon Isles", "Khaz Algar", "Quel'Thalas",
}
local CONTINENT_RANK = {}
for rank, name in ipairs(CONTINENT_ORDER) do CONTINENT_RANK[name] = rank end

local function GroupLess(a, b)
    if a.label == "#" or a.label == UNKNOWN then return false end
    if b.label == "#" or b.label == UNKNOWN then return true end
    return a.label < b.label
end

local function TopLess(a, b)
    local ra, rb = EXPANSION_RANK[a.label] or CONTINENT_RANK[a.label], EXPANSION_RANK[b.label] or CONTINENT_RANK[b.label]
    if ra and rb then return ra < rb end
    if ra then return true end
    if rb then return false end
    return GroupLess(a, b)
end

-- How the lists can be grouped, per tab (the Guide's "Group by" buttons).
local GROUPINGS = {
    quests = { { "expansion", addon.IS_FOREVER and "Pack" or "Expansion" }, { "zone", "Zone" }, { "npc", "NPC" }, { "quest", "Quest" } },
    gossip = { { "expansion", addon.IS_FOREVER and "Pack" or "Expansion" }, { "npc", "NPC" } },
}
addon.GuideGroupings = GROUPINGS

-- The two levels an entry sits under, by tab and grouping:
--   quests / expansion   expansion > zone > quest        quests / zone   continent > zone > quest
--   quests / npc         first letter > giver > quest    quests / quest  first letter > quest
--   gossip / expansion   expansion > first letter > line  gossip / npc    first letter > NPC > line
--   books                first letter > book
local function Levels(mode, groupBy, entry)
    if mode == "quests" then
        local id = entry.id
        if groupBy == "zone" then
            return ContinentOf(id) or UNKNOWN, ZoneOf(id) or UNKNOWN
        elseif groupBy == "npc" then
            local giver = GiverOf(id)
            return giver and FirstLetter(giver) or "#", giver or "Unknown giver"
        elseif groupBy == "quest" then
            return FirstLetter(SpeakStone_QuestTitles and SpeakStone_QuestTitles[id]), nil
        end
        return ExpansionOf(entry.pack), ZoneOf(id) or UNKNOWN
    elseif mode == "gossip" then
        local name = SpeakStone_NPCNames and SpeakStone_NPCNames[entry.npcID]
        if groupBy == "expansion" then
            return ExpansionOf(entry.pack), FirstLetter(name)
        end
        return FirstLetter(name), name or ("NPC " .. entry.npcID)
    end
    return FirstLetter(BookName(entry.book.base)), nil
end

-- mode: "quests", "gossip" or "books". groupBy: see GROUPINGS. heardFilter: nil, "heard" or "new" (quests only).
-- Returns the top-level nodes. A node is { key, label, kind, total, heard, groups, entries }.
local function BuildTree(mode, list, heardFilter, groupBy)
    local tops, topByKey = {}, {}
    local function Top(label)
        local top = topByKey[label]
        if not top then
            top = { key = label, label = label, kind = "header", total = 0, heard = 0, groups = {}, groupByKey = {}, entries = {} }
            topByKey[label] = top
            tops[#tops + 1] = top
        end
        return top
    end
    for _, entry in ipairs(list) do
        local heard = mode == "quests" and IsHeard(entry.id) or false
        if not ((heardFilter == "heard" and not heard) or (heardFilter == "new" and heard)) then
            local topLabel, groupLabel = Levels(mode, groupBy, entry)
            local top = Top(topLabel)
            top.total = top.total + 1
            if heard then top.heard = top.heard + 1 end
            if groupLabel then
                local group = top.groupByKey[groupLabel]
                if not group then
                    group = { key = top.key .. "/" .. groupLabel, label = groupLabel, kind = "group", total = 0, heard = 0, entries = {} }
                    top.groupByKey[groupLabel] = group
                    top.groups[#top.groups + 1] = group
                end
                group.total = group.total + 1
                if heard then group.heard = group.heard + 1 end
                group.entries[#group.entries + 1] = entry
            else
                top.entries[#top.entries + 1] = entry
            end
        end
    end
    table.sort(tops, TopLess)
    for _, top in ipairs(tops) do
        table.sort(top.groups, GroupLess)
    end
    return tops
end

-- The visible rows, top to bottom: open nodes show what is inside them.
local function Flatten(tops, expanded, forceOpen)
    local rows = {}
    for _, top in ipairs(tops) do
        local open = forceOpen or expanded[top.key]
        rows[#rows + 1] = { kind = "header", node = top, depth = 0, open = open }
        if open then
            for _, group in ipairs(top.groups) do
                local groupOpen = forceOpen or expanded[group.key]
                rows[#rows + 1] = { kind = "group", node = group, depth = 1, open = groupOpen }
                if groupOpen then
                    for _, entry in ipairs(group.entries) do
                        rows[#rows + 1] = { kind = "leaf", entry = entry, depth = 2 }
                    end
                end
            end
            for _, entry in ipairs(top.entries) do
                rows[#rows + 1] = { kind = "leaf", entry = entry, depth = 1 }
            end
        end
    end
    return rows
end
addon.GuideBuildTree, addon.GuideFlatten = BuildTree, Flatten

-- --------------------------------------------------------------------------
-- Voice packs: which of the expected packs are installed, per expansion
-- --------------------------------------------------------------------------
local function Thousands(n)
    local text = tostring(math.floor(tonumber(n) or 0))
    local out = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end
addon.GuideThousands = Thousands

local function PartLabel(short)
    local part = short:match("_Part(%d+)$")
    if part then return "Part " .. part end
    local number = short:match("^Audio_Pack(%d+)$")
    if number then return "Audio Pack " .. number end
    if short == "Chatter" then return "Chatter" end
    return nil
end

-- Rows for the Voice packs tab: { label, parts = { { label, installed, clips } }, have, total, clips }, in
-- expansion order, and the totals. A family with no pack installed at all (WoW Forever on a retail install) is
-- left out; the retail family is always there, so a missing pack shows as missing.
function addon.GuidePackRows(installedPacks)
    local installed = {}
    for _, pack in ipairs(installedPacks or {}) do installed[pack.name] = pack.clips or 0 end
    local rows, byLabel, seen = {}, {}, {}
    local function Row(label)
        local row = byLabel[label]
        if not row then
            row = { label = label, parts = {}, have = 0, total = 0, clips = 0 }
            byLabel[label] = row
            rows[#rows + 1] = row
        end
        return row
    end
    for index, family in ipairs(addon.EXPECTED_PACK_FAMILIES or {}) do
        local any = false
        for _, short in ipairs(family.packs) do
            if installed[family.prefix .. short] then any = true end
        end
        local primary = addon.IS_FOREVER and family.prefix == "SpeakStone_Forever_" or (not addon.IS_FOREVER and index == 1)
        if primary or any then
            for _, short in ipairs(family.packs) do
                local name = family.prefix .. short
                seen[name] = true
                local row = Row(ExpansionOf(name))
                local clips = installed[name]
                local part = PartLabel(short)
                if part == row.label or (part and addon.IS_FOREVER) then part = nil end
                row.parts[#row.parts + 1] = { label = part, installed = clips ~= nil, clips = clips or 0 }
                row.total = row.total + 1
                if clips then
                    row.have = row.have + 1
                    row.clips = row.clips + clips
                end
            end
        end
    end
    for name, clips in pairs(installed) do
        if not seen[name] and name ~= "SpeakStone_Main" then
            local row = Row("Other packs")
            row.parts[#row.parts + 1] = { label = name:gsub("^SpeakStone_", ""), installed = true, clips = clips }
            row.total, row.have, row.clips = row.total + 1, row.have + 1, row.clips + clips
        end
    end
    table.sort(rows, function(a, b)
        local ra, rb = EXPANSION_RANK[a.label], EXPANSION_RANK[b.label]
        if ra and rb then return ra < rb end
        if ra then return true end
        if rb then return false end
        return a.label < b.label
    end)
    local have, total, clips = 0, 0, 0
    for _, row in ipairs(rows) do
        have, total, clips = have + row.have, total + row.total, clips + row.clips
    end
    return rows, have, total, clips
end

-- --------------------------------------------------------------------------
-- The words of a quest line (QuestTexts.lua: DEFLATE chunks, unpacked on demand)
-- --------------------------------------------------------------------------
local textCache, textOrder = {}, {}

local function ChunkTexts(chunk)
    local hit = textCache[chunk]
    if hit then return hit end
    local records = {}
    local blobs = SpeakStone_QuestTexts
    local packed = type(blobs) == "table" and blobs[chunk]
    if type(packed) == "string" and addon.Inflate then
        local raw = addon.Inflate(addon.Base64Decode(packed))
        if raw then
            for id, passage, text in raw:gmatch("(%d+)\30(%a+)\30([^\31]*)") do
                records[id .. "_" .. passage] = text
            end
        end
    end
    textCache[chunk] = records
    textOrder[#textOrder + 1] = chunk
    if #textOrder > 6 then
        textCache[table.remove(textOrder, 1)] = nil
    end
    return records
end

-- The text a quest's description / progress / completion was voiced from, or nil.
function addon.QuestTextFor(id, passage)
    local size = tonumber(SpeakStone_QuestTextChunk) or 128
    return ChunkTexts(math.floor(id / size))[id .. "_" .. passage]
end

-- Quest and book text as the player would see it: $B line breaks, and the player's own
-- name / class / race / gendered words filled in.
local function LiveText(t)
    if not t or t == "" then return nil end
    local ok, out = pcall(function()
        local name = UnitName("player") or "friend"
        local _, class = UnitClass("player")
        local race = UnitRace("player") or "traveller"
        local female = UnitSex("player") == 3
        t = t:gsub("%$[bB]", "\n")
        t = t:gsub("%$[gG]%s*([^:;]*):([^;]*);", function(m, f) return female and f or m end)
        t = t:gsub("%$[nN]", name):gsub("<name>", name)
        t = t:gsub("%$[cC]", (class and class:lower():gsub("^%l", string.upper)) or "hero"):gsub("<class>", class or "hero")
        t = t:gsub("%$[rR]", race):gsub("<race>", race)
        return t
    end)
    return ok and out or t
end

-- --------------------------------------------------------------------------
-- Reading along: the word being spoken lit in the text on the page
-- --------------------------------------------------------------------------
-- The same estimate as the subtitles (Subtitles.lua): the clip's length shared out over its
-- words. Stage directions ("<Kinduru nods.>") are shown but not read, so they take no time.
local ReadTokens, Lit = addon.ReadTokens, addon.LitText


-- --------------------------------------------------------------------------
-- Building the window
-- --------------------------------------------------------------------------
local function DB_NoReadAlong()
    return SpeakStone_MainDB and SpeakStone_MainDB.guideReadAlong == false
end

local ROWS_SHOWN = 17      -- the most rows the quest tab shows (it has the most controls above the list)
local ROWS_MAX = 19        -- rows built: favourites and recent have no controls and show the most
local ROW_H = 24
local LIST_WIDTH = 350
local WINDOW_W, WINDOW_H = 900, 620

local function BuildUI()
    local frame = addon.UIK.Window("SpeakStoneAudioLibraryUI", WINDOW_W, WINDOW_H, "SpeakStone Guide")
    tinsert(UISpecialFrames, "SpeakStoneAudioLibraryUI")
    local function Colours() return addon.Theme().ui end

    -- Tabs across the top: Quests, Gossip, Books, Favourites, Recent.
    frame.tabs = {}
    local TAB_ORDER = {
        { "quests", "Quests" }, { "gossip", "Gossip" }, { "books", "Books" },
        { "favourites", "Favourites" }, { "recent", "Recent" }, { "packs", "Voice packs" },
    }
    local tabX = 16
    for _, t in ipairs(TAB_ORDER) do
        local width = t[1] == "packs" and 96 or 74
        local tab = addon.UIK.Button(frame, t[2], width, 24)
        tab:SetPoint("TOPLEFT", frame, "TOPLEFT", tabX, -44)
        tabX = tabX + width + 4
        frame.tabs[t[1]] = tab
    end

    -- Search and the quest filters.
    local searchBox = addon.UIK.EditBox(frame, LIST_WIDTH, "Search quest, NPC, zone, ID, race or sex...")
    searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -78)
    searchBox:SetMaxLetters(60)
    frame.searchBox = searchBox
    searchBox.Instructions = { SetText = function(_, text) searchBox:SetHint(text) end }

    -- Group by: how the tree is organised. Which choices there are depends on the tab.
    frame.groupBy = (SpeakStone_MainDB and SpeakStone_MainDB.guideGroupBy) or "expansion"
    frame.groupButtons = {}
    local groupLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    groupLabel.ssRole = false
    groupLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -111)
    groupLabel:SetText("Group by")
    frame.groupLabel = groupLabel
    for i = 1, 4 do
        local button = addon.UIK.Button(frame, "", 70, 22, function(self)
            frame.groupBy = self.value
            if SpeakStone_MainDB then SpeakStone_MainDB.guideGroupBy = self.value end
            frame.expanded = {}
            frame:UpdateFilters()
            frame.treeDirty = true
            frame:UpdateList()
        end)
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", 78 + (i - 1) * 74, -106)
        frame.groupButtons[i] = button
    end

    -- Quest filters, and open / close everything.
    frame.filterButtons = {}
    local filterX = 0
    for i, f in ipairs({ { nil, "All", 40 }, { "heard", "Heard", 58 }, { "new", "Not heard", 80 } }) do
        local button = addon.UIK.Button(frame, f[2], f[3], 22, function()
            frame.heardFilter = f[1]
            frame:UpdateFilters()
            frame.treeDirty = true
            frame:UpdateList()
        end)
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", 16 + filterX, -134)
        filterX = filterX + f[3] + 4
        button.value = f[1]
        frame.filterButtons[i] = button
    end
    frame.expandAll = addon.UIK.Button(frame, "Expand all", 78, 22, function() frame:SetAllOpen(true) end)
    frame.expandAll:SetPoint("TOPRIGHT", frame, "TOPLEFT", 16 + 350 - 84, -134)
    frame.collapseAll = addon.UIK.Button(frame, "Collapse all", 80, 22, function() frame:SetAllOpen(false) end)
    frame.collapseAll:SetPoint("TOPRIGHT", frame, "TOPLEFT", 16 + 350, -134)

    function frame:SetAllOpen(open)
        wipe(self.expanded)
        if open and self.tree then
            for _, top in ipairs(self.tree) do
                self.expanded[top.key] = true
                for _, group in ipairs(top.groups) do
                    self.expanded[group.key] = true
                end
            end
        end
        self.treeDirty = true
        self:UpdateList()
    end

    function frame:UpdateFilters()
        local mode = self.mode or "quests"
        local choices = addon.GuideGroupings[mode]
        -- A grouping the tab does not offer falls back to its first.
        if choices then
            local offered = false
            for _, c in ipairs(choices) do
                if c[1] == self.groupBy then offered = true end
            end
            if not offered then self.groupBy = choices[1][1] end
        end
        for i, button in ipairs(self.groupButtons) do
            local c = choices and choices[i]
            button:SetShown(c ~= nil)
            if c then
                button.value = c[1]
                button:SetText(c[2])
                button:SetSelected(c[1] == self.groupBy)
            end
        end
        self.groupLabel:SetShown(choices ~= nil)
        for _, button in ipairs(self.filterButtons) do
            button:SetShown(mode == "quests")
            button:SetSelected(button.value == self.heardFilter)
        end
        local tree = mode == "quests" or mode == "gossip" or mode == "books"
        self.expandAll:SetShown(tree)
        self.collapseAll:SetShown(tree)
        -- Open / close everything sits on the group row when there is no filter row, else beside the filters.
        local controlsY = (mode == "books") and -106 or -134
        self.expandAll:ClearAllPoints()
        self.expandAll:SetPoint("TOPRIGHT", self, "TOPLEFT", 16 + 350 - 84, controlsY)
        self.collapseAll:ClearAllPoints()
        self.collapseAll:SetPoint("TOPRIGHT", self, "TOPLEFT", 16 + 350, controlsY)
        -- The list starts under whatever controls this tab has.
        local top = (mode == "quests" or mode == "gossip") and -164 or (mode == "books" and -138 or -110)
        self.listFrame:ClearAllPoints()
        self.listFrame:SetPoint("TOPLEFT", self, "TOPLEFT", 16, top)
        local rows = math.min(ROWS_MAX, math.floor((572 + top) / ROW_H))
        self.rowsShown = rows
        self.listFrame:SetSize(LIST_WIDTH, rows * ROW_H)
        self.scroll:SetHeight(rows * ROW_H)
        -- The Voice packs tab replaces the list and the page with its own view.
        local packs = mode == "packs"
        self.listFrame:SetShown(not packs)
        self.page:SetShown(not packs)
        self.searchBox:SetShown(not packs)
        self.countText:SetShown(not packs)
        if packs then
            self.scroll:Hide()
            self.groupLabel:Hide()
            for _, button in ipairs(self.groupButtons) do button:Hide() end
            for _, button in ipairs(self.filterButtons) do button:Hide() end
            self.expandAll:Hide()
            self.collapseAll:Hide()
        end
        self.packsView:SetShown(packs)
    end

    -- The list: rows of the tree, drawn a screenful at a time.
    local listFrame = CreateFrame("Frame", nil, frame)
    listFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -164)
    listFrame:SetSize(LIST_WIDTH, ROWS_SHOWN * ROW_H)
    frame.rowsShown = ROWS_SHOWN
    listFrame.bg = listFrame:CreateTexture(nil, "BACKGROUND")
    listFrame.bg:SetAllPoints()
    listFrame.border = addon.UIK.MakeBorder(listFrame)
    local scroll = addon.UIK.VScroll(frame, ROWS_SHOWN * ROW_H)
    scroll:SetPoint("TOPLEFT", listFrame, "TOPRIGHT", 4, 0)
    frame.scroll = scroll
    frame.scrollFrame = scroll          -- the old name, still read by the filter pass
    frame.listFrame = listFrame

    local function OnListMouseWheel(delta)
        scroll:SetValue(scroll:GetValue() - delta * 3)
    end
    listFrame:EnableMouseWheel(true)
    listFrame:SetScript("OnMouseWheel", function(_, delta) OnListMouseWheel(delta) end)
    scroll:SetScript("OnValueChanged", function() frame:UpdateList() end)

    frame.rows = {}
    for i = 1, ROWS_MAX do
        local row = CreateFrame("Button", nil, listFrame)
        row:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", 0, -(i - 1) * ROW_H)
        row:SetHeight(ROW_H)
        row.select = row:CreateTexture(nil, "BACKGROUND")
        row.select:SetAllPoints()
        row.hover = row:CreateTexture(nil, "HIGHLIGHT")
        row.hover:SetAllPoints()
        row.sign = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.sign.ssRole = false
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.label.ssRole = false
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.count.ssRole = false
        row.count:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.count:SetJustifyH("RIGHT")
        row.barTrack = row:CreateTexture(nil, "ARTWORK")
        row.barTrack:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 2)
        row.barTrack:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 2)
        row.barTrack:SetHeight(2)
        row.barFill = row:CreateTexture(nil, "OVERLAY")
        row.barFill:SetPoint("BOTTOMLEFT", row.barTrack, "BOTTOMLEFT", 0, 0)
        row.barFill:SetHeight(2)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta) OnListMouseWheel(delta) end)
        row:SetScript("OnClick", function() frame:ClickRow(row) end)
        frame.rows[i] = row
    end

    -- Bottom bar
    local countText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 18)
    countText:SetJustifyH("LEFT")
    countText.ssRole = false
    frame.countText = countText

    local stopButton = addon.UIK.Button(frame, "Stop audio", 100, 24, function() frame:StopAudio() end)
    stopButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 12)
    frame.stopButton = stopButton
    stopButton:Hide()

    -- The page on the right
    local page = CreateFrame("Frame", nil, frame)
    page:SetPoint("TOPLEFT", frame, "TOPLEFT", 392, -78)
    page:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 44)
    page.bg = page:CreateTexture(nil, "BACKGROUND")
    page.bg:SetAllPoints()
    page.border = addon.UIK.MakeBorder(page)
    frame.page = page

    local function Text(parent, fontObject, width, justify)
        local fs = parent:CreateFontString(nil, "OVERLAY", fontObject)
        fs.ssRole = false
        fs:SetJustifyH(justify or "LEFT")
        fs:SetJustifyV("TOP")
        fs:SetWordWrap(true)
        if width then fs:SetWidth(width) end
        return fs
    end

    -- The Voice packs tab: every pack there should be, per expansion, with a tick when it is installed.
    local packsView = CreateFrame("Frame", nil, frame)
    packsView:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -78)
    packsView:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 44)
    packsView.bg = packsView:CreateTexture(nil, "BACKGROUND")
    packsView.bg:SetAllPoints()
    packsView.border = addon.UIK.MakeBorder(packsView)
    packsView:Hide()
    frame.packsView = packsView
    packsView.summary = Text(packsView, "GameFontNormalLarge", 700)
    packsView.summary:SetPoint("TOPLEFT", packsView, "TOPLEFT", 20, -16)
    packsView.hint = Text(packsView, "GameFontHighlightSmall", 820)
    packsView.hint:SetPoint("TOPLEFT", packsView.summary, "BOTTOMLEFT", 0, -6)
    packsView.rows = {}
    for i = 1, 16 do
        local row = CreateFrame("Frame", nil, packsView)
        row:SetPoint("TOPLEFT", packsView, "TOPLEFT", 14, -62 - (i - 1) * 28)
        row:SetPoint("RIGHT", packsView, "RIGHT", -14, 0)
        row:SetHeight(28)
        row.stripe = row:CreateTexture(nil, "BACKGROUND")
        row.stripe:SetAllPoints()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.name = Text(row, "GameFontNormal", 220)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
        row.name:SetJustifyV("MIDDLE")
        row.parts = Text(row, "GameFontNormalSmall", 380)
        row.parts:SetPoint("LEFT", row, "LEFT", 270, 0)
        row.parts:SetJustifyV("MIDDLE")
        row.count = Text(row, "GameFontNormalSmall", 150, "RIGHT")
        row.count:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        row.count:SetJustifyV("MIDDLE")
        packsView.rows[i] = row
    end
    packsView.linkLabel = Text(packsView, "GameFontNormalSmall", 600)
    packsView.linkLabel:SetPoint("BOTTOMLEFT", packsView, "BOTTOMLEFT", 20, 46)
    packsView.linkLabel:SetText("Get the missing packs on CurseForge (Ctrl+C to copy the address):")
    packsView.linkBox = addon.UIK.CopyBox(packsView, "https://www.curseforge.com/members/dandwhelan/projects", 520)
    packsView.linkBox:SetPoint("BOTTOMLEFT", packsView, "BOTTOMLEFT", 20, 16)

    local TICK = "Interface\\RaidFrame\\ReadyCheck-Ready"
    local CROSS = "Interface\\RaidFrame\\ReadyCheck-NotReady"
    local PARTIAL = "Interface\\RaidFrame\\ReadyCheck-Waiting"
    function frame:RefreshPacks()
        local ui = Colours()
        local index = addon.GetAudioIndex and addon.GetAudioIndex()
        local rows, have, total, clips = addon.GuidePackRows(index and index.packs)
        packsView.bg:SetColorTexture(ui.inset[1], ui.inset[2], ui.inset[3], ui.inset[4])
        packsView.border:SetColor(ui.edge[1], ui.edge[2], ui.edge[3], 0.6)
        local good = addon.Theme().light and "|cff1b6b2a" or "|cff4fd16f"
        local bad = addon.Theme().light and "|cffa02b20" or "|cffff6b5e"
        packsView.summary:SetText(string.format("%d of %d voice packs installed  \194\183  %s clips",
            have, total, Thousands(clips)))
        packsView.summary:SetTextColor(ui.title[1], ui.title[2], ui.title[3])
        packsView.hint:SetText(have == total and "Every pack is installed. Check CurseForge now and then for updates."
            or "A tick means every part of that expansion's audio is installed; a cross means none of it is.")
        packsView.hint:SetTextColor(ui.dim[1], ui.dim[2], ui.dim[3])
        packsView.linkLabel:SetTextColor(ui.dim[1], ui.dim[2], ui.dim[3])
        addon.ThemeShadow(packsView.linkLabel)
        for _, fs in ipairs({ packsView.summary, packsView.hint }) do addon.ThemeShadow(fs) end
        for i, row in ipairs(packsView.rows) do
            local data = rows[i]
            if not data then
                row:Hide()
            else
                row:Show()
                if i % 2 == 0 then
                    row.stripe:SetColorTexture(ui.hover[1], ui.hover[2], ui.hover[3], ui.hover[4])
                else
                    row.stripe:SetColorTexture(0, 0, 0, 0)
                end
                local all, none = data.have == data.total, data.have == 0
                row.icon:SetTexture(all and TICK or (none and CROSS or PARTIAL))
                row.name:SetText(data.label)
                row.name:SetTextColor(ui.title[1], ui.title[2], ui.title[3])
                local parts = {}
                if #data.parts > 1 or (data.parts[1] and data.parts[1].label) then
                    for _, part in ipairs(data.parts) do
                        local name = part.label or "Installed"
                        parts[#parts + 1] = part.installed and (good .. name .. "|r") or (bad .. name .. " (missing)|r")
                    end
                else
                    parts[1] = all and (good .. "Installed|r") or (bad .. "Not installed|r")
                end
                row.parts:SetText(table.concat(parts, "   "))
                row.count:SetText(data.clips > 0 and (Thousands(data.clips) .. " clips") or "")
                row.count:SetTextColor(ui.dim[1], ui.dim[2], ui.dim[3])
                for _, fs in ipairs({ row.name, row.parts, row.count }) do addon.ThemeShadow(fs) end
            end
        end
    end

    -- Reading along: while the clip for the text on the page plays, the word being spoken is lit.
    local lastLit
    function frame:ReadAlong()
        local target = self.readTarget
        if not target then
            if lastLit then lastLit.fs:SetText(lastLit.plain) end
            lastLit = nil
            return
        end
        local started, duration = self.playStarted, self.playDuration
        local playing = started and duration and duration > 0 and self.playKey == target.key
            and GetTime() - started <= duration + 0.4
        if lastLit and (not playing or lastLit.fs ~= target.fs or lastLit.key ~= target.key) then
            -- It has finished, stopped, or the page moved on: the text as it was.
            lastLit.fs:SetText(lastLit.plain)
            lastLit = nil
        end
        if not playing then
            return
        end
        if DB_NoReadAlong and DB_NoReadAlong() then return end
        if not target.tokens then
            target.tokens, target.spoken, target.words = ReadTokens(target.plain)
            target.times = addon.SubtitleWordTimes(target.words, duration)
        end
        local elapsed = GetTime() - started
        local index = addon.SubtitleWordAt(target.times, elapsed + 0.12)
        if elapsed >= duration then index = 0 end
        if target.lastIndex ~= index then
            target.lastIndex = index
            target.fs:SetText(Lit(target.plain, target.tokens, target.spoken, index,
                addon.HighlightCode(target.light or addon.ThemeIsLight())))
            -- Long text: keep the place in view.
            if target.scroll and target.child and index > 0 then
                local range = target.scroll:GetVerticalScrollRange()
                if range > 0 then
                    target.scroll:SetVerticalScroll(math.min(range, range * (elapsed / duration)))
                end
            end
        end
        lastLit = target
    end
    frame:HookScript("OnUpdate", function(_, dt)
        frame.readAcc = (frame.readAcc or 0) + dt
        if frame.readAcc >= 0.08 then
            frame.readAcc = 0
            -- Nothing tells an addon when a clip ends: it has, once its length has passed. (A book being read
            -- whole turns its own pages, so it is left to its own timer.)
            local started, duration = frame.playStarted, frame.playDuration
            if started and duration and duration > 0 and GetTime() - started > duration + 0.5 and not frame.playingWholeBook() then
                frame:StopAudio()
            end
            frame:ReadAlong()
        end
    end)

    -- A favourite star for whatever is selected.
    local star = CreateFrame("Button", nil, page)
    star:SetSize(20, 20)
    star:SetPoint("TOPRIGHT", page, "TOPRIGHT", -12, -12)
    star:SetNormalTexture(STAR_TEXTURE)
    star:SetScript("OnClick", function()
        local entry = frame.selectedEntry
        if entry and addon.ToggleFavourite then addon.ToggleFavourite(EntryKey(entry)) end
    end)
    star:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Favourite", 1, 0.82, 0)
        GameTooltip:AddLine("Keep this in the Favourites tab.", 1, 1, 1)
        GameTooltip:Show()
    end)
    star:SetScript("OnLeave", function() GameTooltip:Hide() end)
    star:Hide()
    frame.star = star

    -- Nothing selected / a header or group selected
    local info = CreateFrame("Frame", nil, page)
    info:SetAllPoints()
    info.title = Text(info, "GameFontNormalHuge", 440)
    info.title:SetPoint("TOPLEFT", info, "TOPLEFT", 20, -20)
    info.body = Text(info, "GameFontNormal", 440)
    info.body:SetPoint("TOPLEFT", info.title, "BOTTOMLEFT", 0, -12)
    info.body:SetSpacing(4)
    info.barTrack = info:CreateTexture(nil, "ARTWORK")
    info.barTrack:SetSize(440, 8)
    info.barTrack:SetPoint("TOPLEFT", info.body, "BOTTOMLEFT", 0, -16)
    info.barFill = info:CreateTexture(nil, "OVERLAY")
    info.barFill:SetHeight(8)
    info.barFill:SetPoint("TOPLEFT", info.barTrack, "TOPLEFT", 0, 0)
    frame.infoView = info

    -- A quest
    local qv = CreateFrame("Frame", nil, page)
    qv:SetAllPoints()
    qv.title = Text(qv, "GameFontNormalHuge", 410)
    qv.title:SetPoint("TOPLEFT", qv, "TOPLEFT", 20, -20)
    qv.sub = Text(qv, "GameFontNormalSmall", 440)
    qv.sub:SetPoint("TOPLEFT", qv.title, "BOTTOMLEFT", 0, -6)
    qv.voice = Text(qv, "GameFontNormal", 440)
    qv.voice:SetPoint("TOPLEFT", qv.sub, "BOTTOMLEFT", 0, -14)
    qv.heard = Text(qv, "GameFontNormalSmall", 440)
    qv.heard:SetPoint("TOPLEFT", qv.voice, "BOTTOMLEFT", 0, -6)
    qv.parts = {}
    for i, part in ipairs({
        { "description", "!", "Accept" }, { "progress", "\226\128\147", "In progress" }, { "completion", "?", "Hand in" },
    }) do
        local button = addon.UIK.Button(qv, "", 96, 52, function()
            if frame.selectedEntry then
                frame.questPassage = part[1]
                frame:PlaySpecificAudio(frame.selectedEntry.id, part[1])
            end
        end)
        button:SetPoint("TOPLEFT", qv, "TOPLEFT", 20 + (i - 1) * 112, -132)
        local path = button.label:GetFont()
        button.label:SetFont(path, 30, "OUTLINE")
        button.glyph = part[2]
        button.kind = part[1]
        button.caption = Text(qv, "GameFontNormalSmall", 96, "CENTER")
        button.caption:SetPoint("TOP", button, "BOTTOM", 0, -4)
        button.caption:SetText(part[3])
        button.length = Text(qv, "GameFontDisableSmall", 96, "CENTER")
        button.length:SetPoint("TOP", button.caption, "BOTTOM", 0, -2)
        qv.parts[i] = button
    end
    -- The words of the part being shown, scrollable; lit word by word while it plays.
    qv.scroll = CreateFrame("ScrollFrame", nil, qv)
    qv.scroll:SetPoint("TOPLEFT", qv, "TOPLEFT", 20, -214)
    qv.scroll:SetPoint("BOTTOMRIGHT", qv, "BOTTOMRIGHT", -20, 14)
    qv.scroll:EnableMouseWheel(true)
    qv.scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40)))
    end)
    qv.child = CreateFrame("Frame", nil, qv.scroll)
    qv.child:SetSize(430, 10)
    qv.scroll:SetScrollChild(qv.child)
    qv.text = Text(qv.child, "QuestFont", 430)
    qv.text:SetPoint("TOPLEFT", qv.child, "TOPLEFT", 0, 0)
    qv.text:SetSpacing(4)
    qv:Hide()
    frame.questView = qv

    -- A gossip line
    local gv = CreateFrame("Frame", nil, page)
    gv:SetAllPoints()
    gv.title = Text(gv, "GameFontNormalHuge", 410)
    gv.title:SetPoint("TOPLEFT", gv, "TOPLEFT", 20, -20)
    gv.sub = Text(gv, "GameFontNormalSmall", 440)
    gv.sub:SetPoint("TOPLEFT", gv.title, "BOTTOMLEFT", 0, -6)
    gv.text = Text(gv, "QuestFont", 440)
    gv.text:SetPoint("TOPLEFT", gv.sub, "BOTTOMLEFT", 0, -16)
    gv.text:SetSpacing(4)
    gv.play = addon.UIK.Button(gv, "Play", 110, 30, function()
        local e = frame.selectedEntry
        if e then frame:PlayGossipClip(e.npcID, e.variant) end
    end)
    gv.play:SetPoint("BOTTOMLEFT", gv, "BOTTOMLEFT", 20, 20)
    gv:Hide()
    frame.gossipView = gv

    local activeDebugSound = nil
    local activePlayingQuestID = nil
    local activePlayingType = nil
    local activePlayingNPCID = nil
    local activePlayingVariant = nil
    -- Book reading: which book, which page is sounding, whether the whole book
    -- is being read, and the timer that turns to the next page.
    local activeBook, activeBookPage, activeBookWhole, bookTimer = nil, nil, false, nil

    -- Duration lookup helper. The walk over every installed pack, in
    -- extension order, is the addon's own FindSound -- this file used to
    -- carry its own copy of it here and again in PlaySpecificAudio, which is
    -- three places to keep agreeing about which extension wins.
    function frame:GetAudioDuration(questID, audioType)
        if not addon.FindSound then return nil end
        local _, _, duration = addon.FindSound({ questID .. "_" .. audioType })
        return duration
    end

    function frame:GetPageDuration(book, page)
        if not addon.FindSound then return nil end
        local _, _, duration = addon.FindSound({ book.base .. "_page" .. page })
        return duration
    end

    function frame:GetGossipDuration(npcID, variant)
        if not addon.FindSound then return nil end
        local _, _, duration = addon.FindSound({ "npc" .. npcID .. "_gossip" .. variant })
        return duration
    end

    -- The filter pass currently running, if it has not finished yet. Declared
    -- ahead of BuildIndex so that rebuilding the index can retire one.
    local activeFilter
    local function CancelFilter()
        if activeFilter then
            if activeFilter.timer then activeFilter.timer:Cancel() end
            activeFilter = nil
        end
        frame.filtering = false
    end

    -- The per-quest index is built once for the whole addon, in
    -- SpeakStone_Main.lua, because the settings dashboard needs a walk over
    -- the same packs to count clips. This used to repeat that walk with its
    -- own string match per clip -- tens of thousands of them -- for an answer
    -- the other pass had already worked out.
    function frame:BuildIndex(force)
        if self.isIndexed and not force then
            return
        end

        CancelFilter()

        local quests = {}
        local gossip = {}
        local books = {}
        if addon.GetAudioIndex then
            local audioIndex = addon.GetAudioIndex()
            for _, entry in pairs(audioIndex.quests) do
                table.insert(quests, entry)
            end
            -- Already sorted by BuildAudioIndex; copied rather than sorted
            -- again so a resort here can't disagree with the source order.
            for _, entry in ipairs(audioIndex.gossip) do
                table.insert(gossip, entry)
            end
            -- Books tab: one row per book. Its pages are shown in the book
            -- view (owner, 2026-09-28: "a book with pages"). Only book clips.
            for _, book in ipairs(audioIndex.books or {}) do
                table.insert(books, { kind = "book", book = book })
            end
        end
        table.sort(quests, function(a, b) return a.id < b.id end)

        self.allQuests = quests
        self.allGossip = gossip
        self.allBooks = books
        -- Lookups for the Favourites and Recent tabs, which hold keys.
        local byKey = {}
        for _, e in ipairs(quests) do byKey[EntryKey(e)] = e end
        for _, e in ipairs(gossip) do byKey[EntryKey(e)] = e end
        for _, e in ipairs(books) do byKey[EntryKey(e)] = e end
        self.entryByKey = byKey
        self.keyedList = nil
        self.isIndexed = true
        self.filteredList = nil
        -- A rebuilt index invalidates the narrowing below, which assumes the
        -- previous result was drawn from the same library.
        self.lastQuery = nil
        self.lastResult = nil
    end

    -- A key list from the saved variables, as rows. Keys whose clips are
    -- not installed (a pack removed since) are left out.
    local function KeyedList(keys)
        local out = {}
        for _, key in ipairs(keys or {}) do
            local e = frame.entryByKey and frame.entryByKey[key]
            if e then out[#out + 1] = e end
        end
        return out
    end

    -- The list BuildIndex/FilterList/UpdateList operate on for the current
    -- mode. A method rather than a field lookup at each call site, so
    -- switching modes can't leave one of them reading the other's list.
    function frame:ActiveList()
        if self.mode == "favourites" then
            self.keyedList = self.keyedList or KeyedList(SpeakStone_MainDB and SpeakStone_MainDB.favourites)
            return self.keyedList
        elseif self.mode == "recent" then
            self.keyedList = self.keyedList or KeyedList(SpeakStone_MainDB and SpeakStone_MainDB.recentClips)
            return self.keyedList
        elseif self.mode == "gossip" then
            return self.allGossip
        elseif self.mode == "books" then
            return self.allBooks
        end
        return self.allQuests
    end

    -- Real-time filter, run across frames.
    --
    -- Matching on ID is a substring test; matching on name is not, because a
    -- title has to be resolved first and that is two protected API calls per
    -- quest. Done in one pass over a full pack set that is tens of thousands
    -- of them and a client frozen for seconds, so the pass takes a slice of
    -- each frame and yields, filling the list in as it goes.
    function frame:FilterList(query)
        if not self.allQuests then
            self:BuildIndex()
        end
        CancelFilter()

        if self.scroll then
            self.scroll:SetValue(0)
        end

        local activeList = self:ActiveList() or {}
        local cleanQuery = query and query:lower():match("^%s*(.-)%s*$") or ""
        if cleanQuery == "" then
            self.filteredList = activeList
            self.lastQuery = ""
            self.lastResult = activeList
            self:UpdateList()
            return
        end

        -- Extending a query can only ever narrow the result: a quest that
        -- matches "westf" matched "west" too, whether it matched on ID or on
        -- title. So the longer query is filtered over what the shorter one
        -- produced rather than over the whole library.
        --
        -- Only over a *finished* result, though. A pass that was cancelled
        -- part-way through -- which is what happens when someone keeps typing
        -- -- has found only some of its matches, and narrowing from that would
        -- drop the rest for good rather than merely deferring them. That is
        -- why the completed result is kept apart from the one on screen.
        local startingList = activeList
        if self.lastQuery and self.lastQuery ~= "" and self.lastResult
            and cleanQuery:sub(1, #self.lastQuery) == self.lastQuery then
            startingList = self.lastResult
        end

        local words = {}
        for word in cleanQuery:gmatch("%S+") do words[#words + 1] = word end
        local state = { query = cleanQuery, words = words, source = startingList, index = 1, results = {} }
        activeFilter = state
        self.filteredList = state.results
        self.filtering = true

        local function Step()
            -- A newer query, a rebuilt index or a closed window retires this
            -- pass; the timer that woke it may already be obsolete.
            if activeFilter ~= state then return end

            local source, results, needle = state.source, state.results, state.query
            local total = #source
            local i = state.index
            local startedAt = debugprofilestop and debugprofilestop() or nil
            local processed = 0

            while i <= total do
                local entry = source[i]
                local entryKind = EntryKind(entry)
                if entryKind == "book" then
                    -- A book matches by name; its page rows come with it.
                    if BookName(entry.book.base):lower():find(needle, 1, true) then
                        results[#results + 1] = entry
                    end
                elseif entryKind == "gossip" then
                    local idStr = entry.npcIDStr or tostring(entry.npcID)
                    local name = SpeakStone_NPCNames and SpeakStone_NPCNames[entry.npcID]
                    if idStr:find(needle, 1, true)
                        or (name and name:lower():find(needle, 1, true))
                        or VoiceMatches(GetVoice("npc", entry.npcID), state.words) then
                        results[#results + 1] = entry
                    end
                else
                    local idStr = entry.idStr or tostring(entry.id)
                    if idStr:find(needle, 1, true) then
                        results[#results + 1] = entry
                    else
                        local title = GetQuestTitle(entry.id)
                        local giver, zone = GiverOf(entry.id), ZoneOf(entry.id)
                        if (title and title:lower():find(needle, 1, true))
                            or (giver and giver:lower():find(needle, 1, true))
                            or (zone and zone:lower():find(needle, 1, true))
                            or VoiceMatches(GetVoice("quest", entry.id), state.words) then
                            results[#results + 1] = entry
                        end
                    end
                end
                i = i + 1
                processed = processed + 1
                if processed % FILTER_CHECK_EVERY == 0 then
                    if startedAt then
                        if debugprofilestop() - startedAt >= FILTER_BUDGET_MS then break end
                    elseif processed >= FILTER_CHUNK then
                        break
                    end
                end
            end

            state.index = i
            if i > total then
                activeFilter = nil
                frame.filtering = false
                -- Complete, so the next query may narrow over it.
                frame.lastQuery = needle
                frame.lastResult = results
                frame:UpdateList()
            else
                frame:UpdateList()
                -- Next frame, not next second: this is a yield, not a delay.
                state.timer = C_Timer.NewTimer(0, Step)
            end
        end

        Step()
    end

    -- Filtering by name touches the whole library, so a burst of typing is
    -- collapsed into one pass rather than one per character.
    function frame:QueueFilter(query)
        if searchTimer then
            searchTimer:Cancel()
        end
        searchTimer = C_Timer.NewTimer(SEARCH_DEBOUNCE, function()
            searchTimer = nil
            if frame:IsShown() then
                frame:FilterList(query)
            end
        end)
    end

    -- Audio playback
    function frame.playingWholeBook()
        return activeBook ~= nil and activeBookWhole
    end

    -- The Stop audio button shows only while something started here is playing.
    function frame:UpdateStop()
        local playing = activeDebugSound ~= nil or activePlayingQuestID ~= nil or activePlayingNPCID ~= nil or activeBook ~= nil
        self.stopButton:SetShown(playing)
    end

    function frame:StopAudio()
        if activeDebugSound then
            StopSound(activeDebugSound)
            activeDebugSound = nil
        end
        activePlayingQuestID = nil
        activePlayingType = nil
        activePlayingNPCID = nil
        activePlayingVariant = nil
        self.playKey, self.playStarted, self.playDuration = nil, nil, nil
        if bookTimer then
            bookTimer:Cancel()
            bookTimer = nil
        end
        activeBook, activeBookPage, activeBookWhole = nil, nil, false
        self:UpdateList()
        if self.RefreshBook then self:RefreshBook() end
    end

    -- ------------------------------------------------------------------
    -- Book view: one book shown as a book, page by page (owner, 2026-09-28).
    -- Fills the page on the right while a book is selected.
    -- ------------------------------------------------------------------

    local view = CreateFrame("Frame", nil, page)
    view:SetAllPoints()
    view:EnableMouse(true)
    view:Hide()
    local parchment = view:CreateTexture(nil, "BACKGROUND")
    parchment:SetAllPoints()
    parchment:SetColorTexture(0.87, 0.79, 0.62, 1)
    local edge = view:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT", 6, -6)
    edge:SetPoint("BOTTOMRIGHT", -6, 6)
    edge:SetColorTexture(0.93, 0.87, 0.73, 1)
    local bTitle = view:CreateFontString(nil, "OVERLAY", "QuestTitleFontBlackShadow")
    bTitle.ssRole = false
    bTitle:SetPoint("TOP", view, "TOP", 0, -18)
    bTitle:SetWidth(380)
    if bTitle.SetMaxLines then bTitle:SetMaxLines(2) end
    bTitle:SetWordWrap(true)
    bTitle:SetTextColor(0.25, 0.16, 0.06)
    local bStatus = view:CreateFontString(nil, "OVERLAY", "GameFontBlackSmall")
    bStatus.ssRole = false
    bStatus:SetPoint("TOP", bTitle, "BOTTOM", 0, -4)
    bStatus:SetWidth(380)

    local textScroll = CreateFrame("ScrollFrame", nil, view, "UIPanelScrollFrameTemplate")
    textScroll:SetPoint("TOPLEFT", view, "TOPLEFT", 24, -58)
    textScroll:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -40, 118)
    local textChild = CreateFrame("Frame", nil, textScroll)
    textChild:SetSize(400, 10)
    textScroll:SetScrollChild(textChild)
    local bText = textChild:CreateFontString(nil, "OVERLAY", "QuestFont")
    bText.ssRole = false
    bText:SetPoint("TOPLEFT", 0, 0)
    bText:SetWidth(400)
    bText:SetJustifyH("LEFT")
    bText:SetJustifyV("TOP")
    bText:SetTextColor(0.18, 0.12, 0.05)

    local bPage = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    bPage.ssRole = false
    bPage:SetPoint("BOTTOM", view, "BOTTOM", 0, 86)
    bPage:SetTextColor(0.3, 0.2, 0.08)
    local function Btn(label, w, point, x, y)
        local b = addon.UIK.Button(view, label, w, 24)
        b:SetPoint(point, view, point, x, y)
        return b
    end
    local prevBtn = Btn("< Prev", 80, "BOTTOMLEFT", 20, 80)
    local nextBtn = Btn("Next >", 80, "BOTTOMRIGHT", -20, 80)
    local playPageBtn = Btn("Play page", 100, "BOTTOM", -56, 46)
    local readBtn = Btn("Read book", 100, "BOTTOM", 56, 46)
    local backBtn = Btn("Close book", 120, "BOTTOM", 0, 12)

    -- Book text as the player would see it: $B line breaks, and the player's
    -- own name / class / race / gendered words filled in.
    local function PageText(book, index)
        local pages = SpeakStone_BookTexts and SpeakStone_BookTexts[book.base]
        local t = pages and pages[book.pages[index]]
        if not t or t == "" then
            return "|cff7a6a50(No text on file for this page.)|r"
        end
        local ok, out = pcall(function()
            local name = UnitName("player") or "friend"
            local _, class = UnitClass("player")
            local race = UnitRace("player") or "traveller"
            local female = UnitSex("player") == 3
            -- SimpleHTML pages ("<HTML><BODY><H1 ...>", "<IMG .../>") and
            -- world-state counters ("$4024w") were shown raw (owner, 2026-09-29).
            -- BookTexts.lua is cleaned at build time; this covers older copies.
            t = t:gsub("<[Bb][Rr]%s*/?>", "\n"):gsub("</[PpHh]%d?>", "\n")
            for _, tag in ipairs({ "[Hh][Tt][Mm][Ll]", "[Bb][Oo][Dd][Yy]", "[Hh]%d", "[Pp]", "[Ii][Mm][Gg]" }) do
                t = t:gsub("</?" .. tag .. "%f[%s/>][^<>]*>", "")
            end
            t = t:gsub("%$%d+[wW]", "")
            t = t:gsub("%$[bB]", "\n")
            t = t:gsub("[ \t]+\n", "\n"):gsub("\n\n\n+", "\n\n"):gsub("^%s+", ""):gsub("%s+$", "")
            if t == "" then t = "|cff7a6a50(This page is a picture.)|r" end
            t = t:gsub("%$[gG]%s*([^:;]*):([^;]*);", function(m, f) return female and f or m end)
            t = t:gsub("%$[nN]", name):gsub("<name>", name)
            t = t:gsub("%$[cC]", (class and class:lower():gsub("^%l", string.upper)) or "hero"):gsub("<class>", class or "hero")
            t = t:gsub("%$[rR]", race):gsub("<race>", race)
            return t
        end)
        return ok and out or t
    end
    frame.bookView = view

    function frame:RefreshBook()
        if not view.book then return end
        local book, idx = view.book, view.index
        bTitle:SetText(BookName(book.base))
        local top = 18 + math.ceil(bTitle:GetStringHeight() or 20) + 4 + 14 + 6
        textScroll:SetPoint("TOPLEFT", view, "TOPLEFT", 22, -math.max(58, top))
        bPage:SetText(string.format("Page %d of %d", idx, #book.pages))
        if view.shownIndex ~= idx or view.shownBook ~= book then
            view.plain = PageText(book, idx)
            bText:SetText(view.plain)
            textChild:SetHeight(math.max(10, bText:GetStringHeight() + 8))
            textScroll:SetVerticalScroll(0)
            view.shownIndex, view.shownBook = idx, book
        end
        local page = book.pages[idx]
        if view.plain and not view.plain:find("|", 1, true) then
            frame.readTarget = { fs = bText, plain = view.plain, key = "b:" .. book.base .. ":" .. page, scroll = textScroll,
                child = textChild, ink = { 0.18, 0.12, 0.05 }, light = true }
        else
            frame.readTarget = nil
        end
        local reading = activeBook == book and activeBookWhole
        if activeBook == book and activeBookPage == book.pages[idx] then
            bStatus:SetText(reading and "Reading the book..." or "Playing this page")
        else
            bStatus:SetText(" ")
        end
        readBtn:SetText(reading and "Stop" or "Read book")
        if idx > 1 then prevBtn:Enable() else prevBtn:Disable() end
        if idx < #book.pages then nextBtn:Enable() else nextBtn:Disable() end
    end

    function frame:OpenBook(book, index)
        view.book, view.index = book, index or 1
        view:Show()
        self:RefreshBook()
    end

    function frame:CloseBook()
        view.book = nil
        view:Hide()
    end

    local function Turn(delta)
        local book = view.book
        if not book then return end
        local idx = math.max(1, math.min(#book.pages, view.index + delta))
        if idx == view.index then return end
        view.index = idx
        -- Turning the page while the book is being read jumps the reading there.
        if activeBook == book and activeBookWhole then
            frame:PlayBook(book, idx)
        end
        frame:RefreshBook()
    end
    prevBtn:SetScript("OnClick", function() Turn(-1) end)
    nextBtn:SetScript("OnClick", function() Turn(1) end)
    playPageBtn:SetScript("OnClick", function()
        if view.book then frame:PlayBookPage(view.book, view.book.pages[view.index]) end
    end)
    readBtn:SetScript("OnClick", function()
        if not view.book then return end
        if activeBook == view.book and activeBookWhole then
            frame:StopAudio()
        else
            frame:PlayBook(view.book, view.index)
        end
    end)
    backBtn:SetScript("OnClick", function() frame:CloseBook() end)
    -- The wheel scrolls the page's text; Prev/Next turn pages.

    local function StartBookPage(book, index, whole)
        local page = book.pages[index]
        if not page then return false end
        local soundPath, duration
        if addon.FindSound then
            local _, path, len = addon.FindSound({ book.base .. "_page" .. page })
            soundPath, duration = path, len
        end
        if not soundPath then
            print("SpeakStone Guide: page " .. page .. " of '" .. BookName(book.base) .. "' not found")
            return false
        end
        local willPlay, handle = PlaySoundFile(soundPath, "Dialog")
        if not (willPlay and handle) then return false end
        if addon.NoteRecent then addon.NoteRecent("b:" .. book.base) end
        activeDebugSound = handle
        activeBook, activeBookPage, activeBookWhole = book, page, whole
        frame.playKey, frame.playStarted, frame.playDuration = "b:" .. book.base .. ":" .. page, GetTime(), tonumber(duration)
        if view.book == book then
            view.index = index
            frame:RefreshBook()
        end
        bookTimer = C_Timer.NewTimer((tonumber(duration) or 5) + 0.4, function()
            bookTimer = nil
            if activeBook ~= book or activeBookPage ~= page then return end
            if whole and book.pages[index + 1] then
                StartBookPage(book, index + 1, true)
            else
                activeBook, activeBookPage, activeBookWhole = nil, nil, false
            end
            if frame:IsShown() then
                frame:UpdateList()
                frame:RefreshBook()
            end
        end)
        return true
    end

    function frame:PlayBook(book, startIndex)
        self:StopAudio()
        if addon.StopCurrentSound then addon.StopCurrentSound() end
        StartBookPage(book, startIndex or 1, true)
        self:UpdateList()
    end

    function frame:PlayBookPage(book, page)
        self:StopAudio()
        if addon.StopCurrentSound then addon.StopCurrentSound() end
        for i, p in ipairs(book.pages) do
            if p == page then
                StartBookPage(book, i, false)
                break
            end
        end
        self:UpdateList()
    end

    function frame:PlaySpecificAudio(questID, audioType)
        self:StopAudio()
        -- Narration running behind the window would otherwise play over the
        -- preview -- and with "silence Blizzard's own voice lines" on it is
        -- holding Sound_DialogVolume at zero, which is the channel the
        -- preview plays on, so the preview was silent for as long as the
        -- narration lasted.
        if addon.StopCurrentSound then
            addon.StopCurrentSound()
        end

        local soundPath, length
        if addon.FindSound then
            local _, path, duration = addon.FindSound({ questID .. "_" .. audioType })
            soundPath, length = path, duration
        end

        if not soundPath then
            print("SpeakStone Guide: clip not found for Quest ID " .. tostring(questID) .. " (" .. tostring(audioType) .. ")")
            return
        end

        local willPlay, handle = PlaySoundFile(soundPath, "Dialog")
        if willPlay and handle then
            activeDebugSound = handle
            if addon.NoteRecent then addon.NoteRecent("q:" .. questID) end
            activePlayingQuestID = questID
            activePlayingType = audioType
            self.playKey, self.playStarted, self.playDuration = "q:" .. questID .. ":" .. audioType, GetTime(), tonumber(length)
            self:UpdateList()
        end
    end

    -- Gossip playback. Deliberately bypasses PlayGossipAudio's suppression
    -- check in SpeakStone_Main.lua: that check exists to stop the addon from
    -- *guessing* which variant to autoplay live at a real NPC, not to hide
    -- correctly-voiced audio from a player who is explicitly picking one by
    -- hand here.
    function frame:PlayGossipClip(npcID, variant)
        self:StopAudio()
        if addon.StopCurrentSound then
            addon.StopCurrentSound()
        end

        local soundPath, length
        if addon.FindSound then
            local _, path, duration = addon.FindSound({ "npc" .. npcID .. "_gossip" .. variant })
            soundPath, length = path, duration
        end

        if not soundPath then
            print("SpeakStone Guide: clip not found for NPC " .. tostring(npcID) .. " gossip " .. tostring(variant))
            return
        end

        local willPlay, handle = PlaySoundFile(soundPath, "Dialog")
        if willPlay and handle then
            activeDebugSound = handle
            if addon.NoteRecent then addon.NoteRecent("g:" .. npcID .. ":" .. variant) end
            activePlayingNPCID = npcID
            activePlayingVariant = variant
            self.playKey, self.playStarted, self.playDuration = "g:" .. npcID .. ":" .. variant, GetTime(), tonumber(length)
            self:UpdateList()
        end
    end


    -- ----------------------------------------------------------------------
    -- The tree on screen
    -- ----------------------------------------------------------------------
    local function LeafLabel(entry)
        local kind = EntryKind(entry)
        if kind == "book" then
            return BookName(entry.book.base)
        elseif kind == "gossip" then
            local name = SpeakStone_NPCNames and SpeakStone_NPCNames[entry.npcID]
            return (name or ("NPC " .. entry.npcID)) .. "  \194\183  " .. entry.variant
        end
        local title = GetQuestTitle(entry.id)
        if not title then
            RequestQuestTitle(entry.id)
            return "Quest " .. entry.id
        end
        return title
    end

    local function Percent(heard, total)
        return total > 0 and math.floor(heard / total * 100 + 0.5) or 0
    end

    -- Rebuild the rows from the list the filter produced, the tab and what is open.
    function frame:RebuildRows()
        self.treeDirty = false
        local list = self.filteredList or self:ActiveList() or {}
        local mode = self.mode or "quests"
        if mode == "favourites" or mode == "recent" then
            self.tree = nil
            local rows = {}
            for _, entry in ipairs(list) do
                rows[#rows + 1] = { kind = "leaf", entry = entry, depth = 0 }
            end
            self.flat = rows
        else
            self.tree = BuildTree(mode, list, mode == "quests" and self.heardFilter or nil, self.groupBy)
            local searching = self.searchBox:GetText() ~= ""
            self.flat = Flatten(self.tree, self.expanded, searching)
        end
        local shown = self.rowsShown or ROWS_SHOWN
        self.scroll:SetMinMaxValues(0, math.max(0, #self.flat - shown))
        self.scroll:SetShown(#self.flat > shown)
        if self.scroll:GetValue() > math.max(0, #self.flat - shown) then
            self.scroll:SetValue(math.max(0, #self.flat - shown))
        end
    end

    function frame:ClickRow(row)
        local r = row.rowData
        if not r then return end
        if r.kind == "leaf" then
            self.selectedEntry = r.entry
            self.selectedNode = nil
            self:ShowPage()
        else
            local key = r.node.key
            self.expanded[key] = not self.expanded[key] or nil
            self.selectedEntry = nil
            self.selectedNode = r.node
            self.treeDirty = true
            self:ShowPage()
        end
        self:UpdateList()
    end

    function frame:UpdateList()
        self:UpdateStop()
        if self.mode == "packs" then
            self:RefreshPacks()
            return
        end
        do
            local list = self.filteredList or self:ActiveList()
            local signature = tostring(list) .. ":" .. (list and #list or 0) .. ":" .. tostring(self.mode)
                .. ":" .. tostring(self.heardFilter) .. ":" .. tostring(self.groupBy) .. ":" .. tostring(self.searchBox:GetText() ~= "")
            if signature ~= self.treeSignature then
                self.treeSignature = signature
                self.treeDirty = true
            end
        end
        if not self.flat or self.treeDirty then
            self:RebuildRows()
        end
        local ui = Colours()
        self.groupLabel:SetTextColor(ui.dim[1], ui.dim[2], ui.dim[3])
        addon.ThemeShadow(self.groupLabel)
        self.listFrame.bg:SetColorTexture(ui.inset[1], ui.inset[2], ui.inset[3], ui.inset[4])
        self.listFrame.border:SetColor(ui.edge[1], ui.edge[2], ui.edge[3], 0.6)
        self.page.bg:SetColorTexture(ui.inset[1], ui.inset[2], ui.inset[3], ui.inset[4])
        self.page.border:SetColor(ui.edge[1], ui.edge[2], ui.edge[3], 0.6)
        local offset = math.floor(self.scroll:GetValue() + 0.5)
        local selectedEntry = self.selectedEntry
        for i = 1, ROWS_MAX do
            local row = self.rows[i]
            local r = i <= (self.rowsShown or ROWS_SHOWN) and self.flat[offset + i] or nil
            row.rowData = r
            if not r then
                row:Hide()
            else
                row:Show()
                local indent = 8 + r.depth * 16
                row.sign:ClearAllPoints()
                row.sign:SetPoint("LEFT", row, "LEFT", indent, 0)
                row.label:ClearAllPoints()
                row.label:SetPoint("LEFT", row, "LEFT", indent + 16, 0)
                row.label:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
                row.hover:SetColorTexture(ui.hover[1], ui.hover[2], ui.hover[3], ui.hover[4])
                if r.kind == "leaf" then
                    local entry = r.entry
                    local selected = selectedEntry == entry
                    row.sign:SetText("")
                    row.label:SetText(LeafLabel(entry))
                    local heard = EntryKind(entry) == "quest" and IsHeard(entry.id)
                    row.count:SetText(heard and "heard" or "")
                    row.count:SetTextColor(ui.accent[1], ui.accent[2], ui.accent[3])
                    row.label:SetTextColor(ui.text[1], ui.text[2], ui.text[3])
                    row.barTrack:Hide()
                    row.barFill:Hide()
                    if selected then
                        row.select:SetColorTexture(ui.select[1], ui.select[2], ui.select[3], ui.select[4])
                    else
                        row.select:SetColorTexture(0, 0, 0, 0)
                    end
                else
                    local node = r.node
                    row.sign:SetText(r.open and "-" or "+")
                    row.sign:SetTextColor(ui.accent[1], ui.accent[2], ui.accent[3])
                    row.label:SetText(node.label)
                    local isHeader = r.kind == "header"
                    row.label:SetTextColor(isHeader and ui.title[1] or ui.text[1], isHeader and ui.title[2] or ui.text[2],
                        isHeader and ui.title[3] or ui.text[3])
                    if self.mode == "quests" then
                        row.count:SetText(string.format("%d/%d \194\183 %d%%", node.heard, node.total, Percent(node.heard, node.total)))
                    else
                        row.count:SetText(tostring(node.total))
                    end
                    row.count:SetTextColor(ui.dim[1], ui.dim[2], ui.dim[3])
                    if self.mode == "quests" then
                        row.barTrack:Show()
                        row.barTrack:SetColorTexture(ui.divider[1], ui.divider[2], ui.divider[3], 0.5)
                        row.barFill:Show()
                        row.barFill:SetColorTexture(ui.accent[1], ui.accent[2], ui.accent[3], 1)
                        row.barFill:SetWidth(math.max(1, (LIST_WIDTH - 16) * (node.total > 0 and node.heard / node.total or 0)))
                    else
                        row.barTrack:Hide()
                        row.barFill:Hide()
                    end
                    if self.selectedNode == node then
                        row.select:SetColorTexture(ui.select[1], ui.select[2], ui.select[3], ui.select[4])
                    else
                        row.select:SetColorTexture(0, 0, 0, 0)
                    end
                end
                row.sign.ssRole, row.label.ssRole, row.count.ssRole = false, false, false
                addon.ThemeShadow(row.label)
                addon.ThemeShadow(row.count)
                addon.ThemeShadow(row.sign)
            end
        end
        self:UpdatePage()
        local mode = self.mode or "quests"
        local list = self.filteredList or self:ActiveList() or {}
        local activeList = self:ActiveList()
        local numItems, totalItems = #list, activeList and #activeList or 0
        local noun = mode == "books" and "books" or (mode == "gossip" and "gossip clips" or "quests")
        if mode == "favourites" then noun = "favourites" elseif mode == "recent" then noun = "recently played" end
        if self.filtering then
            self.countText:SetText(string.format("Searching... %d so far", numItems))
        elseif numItems == 0 and totalItems == 0 and mode == "favourites" then
            self.countText:SetText("No favourites yet: click the star on a quest, line or book.")
        elseif numItems == 0 and totalItems == 0 and mode == "recent" then
            self.countText:SetText("Nothing played yet.")
        elseif numItems == 0 then
            self.countText:SetText("No matching " .. noun .. " found.")
        elseif self.filteredList and numItems ~= totalItems then
            self.countText:SetText(string.format("Showing %d / %d %s", numItems, totalItems, noun))
        else
            self.countText:SetText(string.format("Total: %d %s", numItems, noun))
        end
        local c = ui.dim
        self.countText:SetTextColor(c[1], c[2], c[3])
        addon.ThemeShadow(self.countText)
    end

    -- ----------------------------------------------------------------------
    -- The page: what is selected
    -- ----------------------------------------------------------------------
    function frame:ShowPage()
        local entry, node = self.selectedEntry, self.selectedNode
        self.infoView:Hide()
        self.questView:Hide()
        self.gossipView:Hide()
        if self.CloseBook then self:CloseBook() end
        if entry then
            local kind = EntryKind(entry)
            if kind == "book" then
                self:OpenBook(entry.book, 1)
            elseif kind == "gossip" then
                self.gossipView:Show()
            else
                self.questView:Show()
            end
            self.star:Show()
        else
            self.infoView:Show()
            self.star:Hide()
        end
    end

    function frame:UpdatePage()
        local ui = Colours()
        local entry, node = self.selectedEntry, self.selectedNode
        local function Ink(fs, colour)
            fs:SetTextColor(colour[1], colour[2], colour[3])
            addon.ThemeShadow(fs)
        end
        if entry then
            PaintStar(self.star, addon.IsFavourite and addon.IsFavourite(EntryKey(entry)))
            local kind = EntryKind(entry)
            if kind == "quest" then
                local qv = self.questView
                qv.title:SetText(LeafLabel(entry))
                Ink(qv.title, ui.title)
                local heard = IsHeard(entry.id)
                local where = ZoneOf(entry.id)
                local giver = GiverOf(entry.id)
                qv.sub:SetText("Quest " .. entry.id .. "  \194\183  " .. ExpansionOf(entry.pack)
                    .. (where and ("  \194\183  " .. where) or "") .. (giver and ("  \194\183  from " .. giver) or ""))
                Ink(qv.sub, ui.dim)
                local voice = GetVoice("quest", entry.id)
                qv.voice:SetText(voice and ("Voice: " .. voice.label) or "")
                Ink(qv.voice, ui.text)
                qv.heard:SetText(heard and "You have heard this quest." or "You have not heard this quest read yet.")
                Ink(qv.heard, heard and ui.accent or ui.dim)
                for _, button in ipairs(qv.parts) do
                    local has = entry.types[button.kind]
                    button:SetShown(has and true or false)
                    button.caption:SetShown(has and true or false)
                    button.length:SetShown(has and true or false)
                    if has then
                        local playing = activePlayingQuestID == entry.id and activePlayingType == button.kind
                        button:SetText((playing and "|cff00ff00" or addon.Theme().titleCode) .. button.glyph .. "|r")
                        Ink(button.caption, ui.text)
                        local len = self:GetAudioDuration(entry.id, button.kind)
                        button.length:SetText(len and string.format("%.1fs", len) or "")
                        Ink(button.length, ui.dim)
                    end
                end
                -- The words of the part chosen (the description until one is picked).
                local passage = self.questPassage
                if not (passage and entry.types[passage]) then
                    passage = entry.types.description and "description" or (entry.types.progress and "progress" or "completion")
                end
                for _, button in ipairs(qv.parts) do
                    button:SetSelected(button.kind == passage)
                end
                local plain = LiveText(addon.QuestTextFor and addon.QuestTextFor(entry.id, passage))
                if not (addon.ApplyReadingFont and addon.ApplyReadingFont(qv.text, 16, "")) then
                    qv.text:SetFontObject("QuestFont")
                end
                qv.text:SetText(plain or "(The words of this part are not on file.)")
                qv.text:SetTextColor(ui.text[1], ui.text[2], ui.text[3])
                addon.ThemeShadow(qv.text)
                qv.child:SetHeight(math.max(10, qv.text:GetStringHeight() + 10))
                if plain and not plain:find("|", 1, true) then
                    self.readTarget = { fs = qv.text, plain = plain, key = "q:" .. entry.id .. ":" .. passage,
                        scroll = qv.scroll, child = qv.child, ink = ui.text }
                else
                    self.readTarget = nil
                end
            elseif kind == "gossip" then
                local gv = self.gossipView
                local name = SpeakStone_NPCNames and SpeakStone_NPCNames[entry.npcID]
                gv.title:SetText(name or ("NPC " .. entry.npcID))
                Ink(gv.title, ui.title)
                local sub = "NPC " .. entry.npcID .. "  \194\183  Gossip " .. entry.variant
                local voice = GetVoice("npc", entry.npcID)
                if voice then sub = sub .. "  \194\183  " .. voice.label end
                local state = addon.GossipClipAutoplayState and addon.GossipClipAutoplayState(entry.npcID)
                if state == "suppressed" then sub = sub .. "  \194\183  not autoplayed in the game" end
                gv.sub:SetText(sub)
                Ink(gv.sub, ui.dim)
                local text
                for line, variant in pairs(SpeakStone_GossipTexts and SpeakStone_GossipTexts[entry.npcID] or {}) do
                    if variant == entry.variant then text = line break end
                end
                if not (addon.ApplyReadingFont and addon.ApplyReadingFont(gv.text, 16, "")) then
                    gv.text:SetFontObject("QuestFont")
                end
                gv.text:SetText(text or "(The words of this line are not on file.)")
                if text and not text:find("|", 1, true) then
                    self.readTarget = { fs = gv.text, plain = text, key = "g:" .. entry.npcID .. ":" .. entry.variant, ink = ui.text }
                else
                    self.readTarget = nil
                end
                Ink(gv.text, ui.text)
                local playing = activePlayingNPCID == entry.npcID and activePlayingVariant == entry.variant
                gv.play:SetText(playing and "Playing" or "Play")
            end
        elseif node then
            local info = self.infoView
            info.title:SetText(node.label)
            Ink(info.title, ui.title)
            local lines = {}
            if self.mode == "quests" then
                lines[#lines + 1] = string.format("%d voiced quests", node.total)
                lines[#lines + 1] = string.format("%d heard \194\183 %d%%", node.heard, Percent(node.heard, node.total))
                info.barTrack:Show()
                info.barFill:Show()
                info.barTrack:SetColorTexture(ui.divider[1], ui.divider[2], ui.divider[3], 0.5)
                info.barFill:SetColorTexture(ui.accent[1], ui.accent[2], ui.accent[3], 1)
                info.barFill:SetWidth(math.max(1, 440 * (node.total > 0 and node.heard / node.total or 0)))
            else
                lines[#lines + 1] = string.format("%d in this group", node.total)
                info.barTrack:Hide()
                info.barFill:Hide()
            end
            info.body:SetText(table.concat(lines, "\n"))
            Ink(info.body, ui.text)
        else
            local info = self.infoView
            info.title:SetText("SpeakStone Guide")
            Ink(info.title, ui.title)
            info.body:SetText("Open an expansion on the left and pick a quest, greeting or book to hear it. "
                .. "The bar under each name shows how much of it you have heard.")
            Ink(info.body, ui.text)
            info.barTrack:Hide()
            info.barFill:Hide()
        end
    end
    addon.ThemeRegister(function() if frame:IsShown() then frame:UpdateList() end end)


    -- Main populate / toggle
    function frame:PopulateList()
        self:BuildIndex()
        self:FilterList(self.searchBox:GetText())
    end

    function frame:SetMode(mode)
        if self.mode == mode then return end
        self.filteredList = nil
        self.keyedList = nil
        self.selectedEntry, self.selectedNode = nil, nil
        self.flat = nil
        self.treeDirty = true
        self:StopAudio()
        self.mode = mode
        local hints = {
            quests = "Search quest, NPC, zone, ID, race or sex...",
            gossip = "Search NPC ID, name, race or sex...",
            books = "Search book name...",
            favourites = "Search favourites...",
            recent = "Search recently played...",
        }
        searchBox:SetHint(hints[mode] or hints.quests)
        self:UpdateTabs()
        self:UpdateFilters()
        self:ShowPage()
        self.lastQuery = nil
        self.lastResult = nil
        if mode == "packs" then
            self:RefreshPacks()
            return
        end
        self:FilterList(self.searchBox:GetText())
    end

    function frame:UpdateTabs()
        local current = self.mode or "quests"
        for mode, tab in pairs(self.tabs) do
            tab:SetSelected(mode == current)
        end
    end
    for mode, tab in pairs(frame.tabs) do
        tab:SetScript("OnClick", function() frame:SetMode(mode) end)
    end
    frame.expanded = {}
    frame:UpdateTabs()
    frame:UpdateFilters()

    function frame:ToggleVisibility()
        if self:IsVisible() then
            self:Hide()
        else
            self:Show()
        end
    end

    searchBox:SetScript("OnTextChanged", function(self)
        frame:QueueFilter(self:GetText())
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        if self:GetText() ~= "" then
            self:SetText("")
        else
            frame:Hide()
        end
    end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    frame:HookScript("OnShow", function(self)
        self:ClearAllPoints()
        self:SetPoint("CENTER")
        self:Raise()
        titleLoader:RegisterEvent("QUEST_DATA_LOAD_RESULT")
        wipe(titleMisses)
        self.keyedList = nil
        self.lastQuery = nil
        self.lastResult = nil
        self.mode = self.mode or "quests"
        self:UpdateTabs()
        self:UpdateFilters()
        if self.mode == "packs" then
            self:RefreshPacks()
        else
            self:PopulateList()
            self:ShowPage()
        end
    end)

    frame:HookScript("OnHide", function(self)
        titleLoader:UnregisterEvent("QUEST_DATA_LOAD_RESULT")
        if searchTimer then
            searchTimer:Cancel()
            searchTimer = nil
        end
        CancelFilter()
        self:StopAudio()
        self:CloseBook()
        self.allQuests, self.allGossip, self.allBooks = nil, nil, nil
        self.entryByKey, self.keyedList = nil, nil
        self.filteredList, self.lastQuery, self.lastResult = nil, nil, nil
        self.flat, self.tree, self.selectedEntry, self.selectedNode = nil, nil, nil, nil
        self.isIndexed = false
        if addon.ReleaseAudioIndex then addon.ReleaseAudioIndex() end
    end)

    return frame
end

local function EnsureUI()
    if not UI then
        UI = BuildUI()
    end
    return UI
end

-- Called when a sound pack registers after the index was built. Nothing to do
-- if the window has never been opened -- it will index on first show.
function addon.AudioLibraryInvalidate()
    if UI then
        UI.isIndexed = false
        if UI:IsShown() then
            UI:PopulateList()
        end
    end
end

-- A star clicked anywhere (a row here, or the speech frame). Rows elsewhere
-- repaint on their own; the Favourites tab's list itself has to be rebuilt.
function addon.FavouritesChanged()
    if UI and UI:IsShown() then
        if UI.mode == "favourites" then
            UI.keyedList = nil
            UI.lastQuery, UI.lastResult = nil, nil
            UI:FilterList(UI.searchBox:GetText())
        else
            UI:UpdateList()
        end
    end
    if addon.SpeechFrameRefreshStar then addon.SpeechFrameRefreshStar() end
end

-- `mode` ("quests", "gossip", "books", "favourites" or "recent") opens straight onto that tab: the
-- settings window's Play section has one button per tab.
function addon.OpenAudioLibrary(mode)
    local frame = EnsureUI()
    frame:Show()
    if type(mode) == "string" then
        frame:SetMode(mode)
    end
    return frame
end

function addon.ToggleAudioLibrary()
    EnsureUI():ToggleVisibility()
end

-- Slash command
SLASH_SPEAKSTONELIBRARY1, SLASH_SPEAKSTONELIBRARY2 = '/qrlibrary', '/sslibrary'
SlashCmdList["SPEAKSTONELIBRARY"] = function()
    addon.ToggleAudioLibrary()
end
