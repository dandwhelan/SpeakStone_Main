local _, addon = ...

local NUM_VISIBLE_ROWS = 14
local ROW_HEIGHT = 34
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
    -- QuestTitles.lua still ships under the pre-rename global name; reading
    -- only the new one left the whole table unused.
    local titles = SpeakStone_QuestTitles or QuestReaderAddon_QuestTitles
    if not resolved and titles then
        local title = titles[questID]
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
-- Building the window
-- --------------------------------------------------------------------------
local function BuildUI()
    local frame = CreateFrame("Frame", "SpeakStoneAudioLibraryUI", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(400, 636)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    -- Allow closing with Escape key
    tinsert(UISpecialFrames, "SpeakStoneAudioLibraryUI")

    -- Title
    if frame.TitleText then
        frame.TitleText:SetText("SpeakStone Audio Library")
    else
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", frame, "TOP", 0, -5)
        title:SetText("SpeakStone Audio Library")
        frame.title = title
    end

    -- Tabs across the top: Quests, Gossip, Books (owner, 2026-09-28). This
    -- replaced a single Quests <-> Gossip toggle when books became a third list.
    frame.tabs = {}
    local TAB_ORDER = { { "quests", "Quests" }, { "gossip", "Gossip" }, { "books", "Books" } }
    for i, t in ipairs(TAB_ORDER) do
        local tab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        tab:SetSize(118, 22)
        tab:SetPoint("TOPLEFT", frame, "TOPLEFT", 14 + (i - 1) * 122, -28)
        tab:SetText(t[2])
        frame.tabs[t[1]] = tab
    end

    -- Search Box
    local searchBox = CreateFrame("EditBox", "SpeakStoneAudioLibrarySearchBox", frame, "SearchBoxTemplate")
    searchBox:SetSize(360, 22)
    searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -56)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(60)
    if searchBox.Instructions then
        searchBox.Instructions:SetText("Search quest ID, name, race or sex...")
    end
    frame.searchBox = searchBox

    -- One list per tab, since a quest row, a gossip row and a book row show
    -- different data: gossip has no "types" to key three fixed buttons off,
    -- and a book is a set of pages.

    -- ScrollFrame (FauxScrollFrame for high performance virtualized rows)
    local scrollFrame = CreateFrame("ScrollFrame", "SpeakStoneAudioLibraryScrollFrame", frame, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, LIST_TOP)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -36, 44)
    frame.scrollFrame = scrollFrame

    -- Bottom status and stop preview button
    local countText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 16)
    countText:SetJustifyH("LEFT")
    frame.countText = countText

    local stopButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    stopButton:SetSize(90, 22)
    stopButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 12)
    stopButton:SetText("Stop Audio")
    stopButton:SetScript("OnClick", function()
        frame:StopAudio()
    end)
    frame.stopButton = stopButton

    -- Mouse wheel scrolling handler
    local function OnListMouseWheel(delta)
        local scrollBar = _G["SpeakStoneAudioLibraryScrollFrameScrollBar"]
        if scrollBar and scrollBar:IsShown() then
            local current = scrollBar:GetValue()
            local minVal, maxVal = scrollBar:GetMinMaxValues()
            local step = ROW_HEIGHT * 3
            if delta > 0 then
                scrollBar:SetValue(math.max(minVal, current - step))
            else
                scrollBar:SetValue(math.min(maxVal, current + step))
            end
        end
    end

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(self, delta)
        OnListMouseWheel(delta)
    end)

    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function()
            frame:UpdateList()
        end)
    end)

    -- Create pooled row frames (14 rows created once and reused)
    frame.rows = {}
    for i = 1, NUM_VISIBLE_ROWS do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(342, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, LIST_TOP - (i - 1) * ROW_HEIGHT)

        -- Highlight texture
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.08)

        -- Alternate row background
        if i % 2 == 0 then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(1, 1, 1, 0.025)
        end

        -- Two lines: the quest's name on top, its ID beneath, so a row reads
        -- as the quest it is and still carries the number the files are
        -- named after.
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -3)
        text:SetPoint("RIGHT", row, "RIGHT", -144, 0)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        row.text = text

        local idText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        idText:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -1)
        idText:SetPoint("RIGHT", row, "RIGHT", -144, 0)
        idText:SetJustifyH("LEFT")
        idText:SetWordWrap(false)
        row.idText = idText

        -- Completion button
        local compBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        compBtn:SetSize(44, 20)
        compBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        compBtn:SetText("Comp")
        row.compBtn = compBtn

        -- Progress button
        local progBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        progBtn:SetSize(44, 20)
        progBtn:SetPoint("RIGHT", compBtn, "LEFT", -3, 0)
        progBtn:SetText("Prog")
        row.progBtn = progBtn

        -- Description button
        local descBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        descBtn:SetSize(44, 20)
        descBtn:SetPoint("RIGHT", progBtn, "LEFT", -3, 0)
        descBtn:SetText("Desc")
        row.descBtn = descBtn

        -- Click handlers. Quest rows use all three buttons; a gossip row uses
        -- only descBtn, relabeled "Play" -- see UpdateList.
        descBtn:SetScript("OnClick", function()
            if row.bookData then
                frame:OpenBook(row.bookData.book, 1)
            elseif row.gossipData then
                frame:PlayGossipClip(row.gossipData.npcID, row.gossipData.variant)
            elseif row.questData then
                frame:PlaySpecificAudio(row.questData.id, "description")
            end
        end)
        progBtn:SetScript("OnClick", function()
            if row.bookData then
                frame:OpenBook(row.bookData.book, 1)
                frame:PlayBook(row.bookData.book, 1)
            elseif row.questData then
                frame:PlaySpecificAudio(row.questData.id, "progress")
            end
        end)
        compBtn:SetScript("OnClick", function()
            if row.questData then
                frame:PlaySpecificAudio(row.questData.id, "completion")
            end
        end)

        -- Tooltips
        local function ShowRowTooltip(owner)
            if row.bookData then
                local b = row.bookData
                GameTooltip:SetOwner(owner or row, "ANCHOR_RIGHT")
                GameTooltip:AddLine(BookName(b.book.base), 1, 0.82, 0)
                if b.kind == "book" then
                    local total = 0
                    for _, page in ipairs(b.book.pages) do
                        total = total + (frame:GetPageDuration(b.book, page) or 0)
                    end
                    GameTooltip:AddLine(#b.book.pages .. " page(s)", 0.7, 0.7, 0.7)
                    if total > 0 then GameTooltip:AddLine(string.format("%.1fs in all", total), 0.3, 1, 0.3) end
                    GameTooltip:AddLine("Book: reads every page in order.", 0.8, 0.8, 1)
                else
                    GameTooltip:AddLine("Page " .. b.page, 0.7, 0.7, 0.7)
                    local d = frame:GetPageDuration(b.book, b.page)
                    if d then GameTooltip:AddLine(string.format("%.1fs", d), 0.3, 1, 0.3) end
                end
                GameTooltip:Show()
                return
            end
            if row.gossipData then
                local g = row.gossipData
                GameTooltip:SetOwner(owner or row, "ANCHOR_RIGHT")
                local name = SpeakStone_NPCNames and SpeakStone_NPCNames[g.npcID]
                GameTooltip:AddLine(name or ("NPC " .. g.npcID), 1, 0.82, 0)
                GameTooltip:AddLine("NPC ID: " .. g.npcID .. "  |  Gossip variant " .. g.variant, 0.7, 0.7, 0.7)
                local voice = GetVoice("npc", g.npcID)
                if voice then
                    GameTooltip:AddLine("Voice: " .. voice.label, 0.8, 0.8, 1)
                end
                local duration = frame:GetGossipDuration(g.npcID, g.variant)
                if duration then
                    GameTooltip:AddLine(string.format("%.1fs", duration), 0.3, 1, 0.3)
                end
                local state = addon.GossipClipAutoplayState and addon.GossipClipAutoplayState(g.npcID)
                if state == "suppressed" then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Not autoplayed in-game: this NPC's gossip", 1, 0.5, 0.2)
                    GameTooltip:AddLine("changes with quest/story state, and no captured", 1, 0.5, 0.2)
                    GameTooltip:AddLine("text is on file to match the live line against.", 1, 0.5, 0.2)
                elseif state == "matched" then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Autoplays only when the NPC is showing the exact", 0.6, 0.9, 0.6)
                    GameTooltip:AddLine("line this clip was voiced from.", 0.6, 0.9, 0.6)
                end
                GameTooltip:Show()
                return
            end

            if not row.questData then return end
            GameTooltip:SetOwner(owner or row, "ANCHOR_RIGHT")
            local title = GetQuestTitle(row.questData.id)
            if title then
                GameTooltip:AddLine(title, 1, 0.82, 0)
                GameTooltip:AddLine("Quest ID: " .. row.questData.id, 0.7, 0.7, 0.7)
            else
                GameTooltip:AddLine("Quest ID: " .. row.questData.id, 1, 0.82, 0)
            end
            for _, questType in ipairs({ "description", "progress", "completion" }) do
                local voice = row.questData.types[questType] and GetVoice("quest", row.questData.id, questType)
                if voice then
                    GameTooltip:AddLine(questType:sub(1, 1):upper() .. questType:sub(2) .. " voice: " .. voice.label, 0.8, 0.8, 1)
                end
            end

            local dLen = frame:GetAudioDuration(row.questData.id, "description")
            local pLen = frame:GetAudioDuration(row.questData.id, "progress")
            local cLen = frame:GetAudioDuration(row.questData.id, "completion")

            if dLen then GameTooltip:AddLine("Description: " .. string.format("%.1fs", dLen), 0.3, 1, 0.3) end
            if pLen then GameTooltip:AddLine("Progress: " .. string.format("%.1fs", pLen), 0.3, 1, 0.3) end
            if cLen then GameTooltip:AddLine("Completion: " .. string.format("%.1fs", cLen), 0.3, 1, 0.3) end

            GameTooltip:Show()
        end

        row:SetScript("OnEnter", function(self) ShowRowTooltip(self) end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        descBtn:SetScript("OnEnter", function(self) ShowRowTooltip(self) end)
        descBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        progBtn:SetScript("OnEnter", function(self) ShowRowTooltip(self) end)
        progBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        compBtn:SetScript("OnEnter", function(self) ShowRowTooltip(self) end)
        compBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Mouse wheel forwarding
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(self, delta) OnListMouseWheel(delta) end)
        descBtn:EnableMouseWheel(true)
        descBtn:SetScript("OnMouseWheel", function(self, delta) OnListMouseWheel(delta) end)
        progBtn:EnableMouseWheel(true)
        progBtn:SetScript("OnMouseWheel", function(self, delta) OnListMouseWheel(delta) end)
        compBtn:EnableMouseWheel(true)
        compBtn:SetScript("OnMouseWheel", function(self, delta) OnListMouseWheel(delta) end)

        frame.rows[i] = row
    end

    -- ----------------------------------------------------------------------
    -- Methods
    -- ----------------------------------------------------------------------
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
        self.isIndexed = true
        self.filteredList = nil
        -- A rebuilt index invalidates the narrowing below, which assumes the
        -- previous result was drawn from the same library.
        self.lastQuery = nil
        self.lastResult = nil
    end

    -- The list BuildIndex/FilterList/UpdateList operate on for the current
    -- mode. A method rather than a field lookup at each call site, so
    -- switching modes can't leave one of them reading the other's list.
    function frame:ActiveList()
        if self.mode == "gossip" then
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

        local scrollBar = _G["SpeakStoneAudioLibraryScrollFrameScrollBar"]
        if scrollBar then
            scrollBar:SetValue(0)
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

            local isGossip = frame.mode == "gossip"
            local isBooks = frame.mode == "books"
            while i <= total do
                local entry = source[i]
                if isBooks then
                    -- A book matches by name; its page rows come with it.
                    if BookName(entry.book.base):lower():find(needle, 1, true) then
                        results[#results + 1] = entry
                    end
                elseif isGossip then
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
                        if (title and title:lower():find(needle, 1, true))
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

    -- Update visible rows
    function frame:UpdateList()
        local isGossip = self.mode == "gossip"
        local isBooks = self.mode == "books"
        local list = self.filteredList or self:ActiveList() or {}
        local numItems = #list
        -- Taken once. UpdateList runs on every frame of a search pass, and
        -- each of the branches below used to build a throwaway table to take
        -- a length from.
        local activeList = self:ActiveList()
        local totalItems = activeList and #activeList or 0
        FauxScrollFrame_Update(self.scrollFrame, numItems, NUM_VISIBLE_ROWS, ROW_HEIGHT)
        local offset = FauxScrollFrame_GetOffset(self.scrollFrame)

        for i = 1, NUM_VISIBLE_ROWS do
            local index = offset + i
            local row = self.rows[i]
            if index <= numItems then
                local data = list[index]
                row:Show()

                if isBooks then
                    row.questData = nil
                    row.gossipData = nil
                    row.bookData = data
                    local name = BookName(data.book.base)
                    row.compBtn:Hide()
                    row.descBtn:Show()
                    row.progBtn:Show()
                    row.text:SetText("|cffffd100" .. name .. "|r")
                    row.idText:SetText(#data.book.pages .. (#data.book.pages == 1 and " page" or " pages"))
                    row.descBtn:SetText("Open")
                    local on = activeBook == data.book and activeBookWhole
                    row.progBtn:SetText(on and "|cff00ff00Read|r" or "Read")
                elseif isGossip then
                    row.questData = nil
                    row.bookData = nil
                    row.gossipData = data

                    local name = SpeakStone_NPCNames and SpeakStone_NPCNames[data.npcID]
                    if name then
                        row.text:SetText("|cffffd100" .. name .. "|r")
                    else
                        row.text:SetText("|cff9d9d9dUnknown NPC|r")
                    end

                    local state = addon.GossipClipAutoplayState and addon.GossipClipAutoplayState(data.npcID)
                    local label = "NPC " .. data.npcID .. "  \194\183  Gossip " .. data.variant
                    local voice = GetVoice("npc", data.npcID)
                    if voice then
                        label = label .. "  \194\183  |cffb0b0ff" .. voice.label .. "|r"
                    end
                    if state == "suppressed" then
                        label = label .. "  \194\183  |cffff8000not autoplayed|r"
                    elseif state == "matched" then
                        label = label .. "  \194\183  |cff80c080text-matched|r"
                    end
                    row.idText:SetText(label)

                    row.progBtn:Hide()
                    row.compBtn:Hide()
                    row.descBtn:Show()
                    if activePlayingNPCID == data.npcID and activePlayingVariant == data.variant then
                        row.descBtn:SetText("|cff00ff00Play|r")
                    else
                        row.descBtn:SetText("Play")
                    end
                else
                    row.gossipData = nil
                    row.bookData = nil
                    row.questData = data

                    local title = GetQuestTitle(data.id)
                    if not title then
                        RequestQuestTitle(data.id)
                    end
                    if title and title ~= "" then
                        row.text:SetText("|cffffd100" .. title .. "|r")
                    else
                        row.text:SetText("|cff9d9d9dUnknown quest|r")
                    end
                    local voice = GetVoice("quest", data.id)
                    if voice then
                        row.idText:SetText("Quest " .. data.id .. "  \194\183  |cffb0b0ff" .. voice.label .. "|r")
                    else
                        row.idText:SetText("Quest " .. data.id)
                    end

                    -- Description
                    if data.types["description"] then
                        row.descBtn:Show()
                        if activePlayingQuestID == data.id and activePlayingType == "description" then
                            row.descBtn:SetText("|cff00ff00Desc|r")
                        else
                            row.descBtn:SetText("Desc")
                        end
                    else
                        row.descBtn:Hide()
                    end

                    -- Progress
                    if data.types["progress"] then
                        row.progBtn:Show()
                        if activePlayingQuestID == data.id and activePlayingType == "progress" then
                            row.progBtn:SetText("|cff00ff00Prog|r")
                        else
                            row.progBtn:SetText("Prog")
                        end
                    else
                        row.progBtn:Hide()
                    end

                    -- Completion
                    if data.types["completion"] then
                        row.compBtn:Show()
                        if activePlayingQuestID == data.id and activePlayingType == "completion" then
                            row.compBtn:SetText("|cff00ff00Comp|r")
                        else
                            row.compBtn:SetText("Comp")
                        end
                    else
                        row.compBtn:Hide()
                    end
                end
            else
                row.questData = nil
                row.gossipData = nil
                row.bookData = nil
                row:Hide()
            end
        end

        local noun = isBooks and "books" or (isGossip and "gossip clips" or "quests")
        if self.filtering then
            -- A pass still running has not found everything yet, and "no
            -- matching quests" while it is still looking is simply wrong --
            -- which is what the empty result reads as for the first frame of
            -- every name search.
            self.countText:SetText(string.format("Searching... %d so far", numItems))
        elseif numItems == 0 then
            self.countText:SetText("No matching " .. noun .. " found.")
        elseif self.filteredList and numItems ~= totalItems then
            self.countText:SetText(string.format("Showing %d / %d %s", numItems, totalItems, noun))
        else
            self.countText:SetText(string.format("Total: %d %s", numItems, noun))
        end
    end

    -- Audio playback
    function frame:StopAudio()
        if activeDebugSound then
            StopSound(activeDebugSound)
            activeDebugSound = nil
        end
        activePlayingQuestID = nil
        activePlayingType = nil
        activePlayingNPCID = nil
        activePlayingVariant = nil
        if bookTimer then
            bookTimer:Cancel()
            bookTimer = nil
        end
        activeBook, activeBookPage, activeBookWhole = nil, nil, false
        self:UpdateList()
        if self.RefreshBook then self:RefreshBook() end
    end

    -- Plays one page of a book. With `whole`, the next page follows when this
    -- one ends, through to the last page; StopAudio (or playing anything
    -- else) ends the reading.
    -- ------------------------------------------------------------------
    -- Book view: one book shown as a book, page by page (owner, 2026-09-28).
    -- Covers the list; the page shown follows the reading.
    -- ------------------------------------------------------------------
    local view = CreateFrame("Frame", nil, frame)
    view:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, LIST_TOP)
    view:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 44)
    view:SetFrameLevel(frame:GetFrameLevel() + 20)
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
    bTitle:SetPoint("TOP", view, "TOP", 0, -18)
    bTitle:SetWidth(300)
    -- Long titles wrapped to three lines and ran into the page text; cap at two.
    if bTitle.SetMaxLines then bTitle:SetMaxLines(2) end
    bTitle:SetWordWrap(true)
    bTitle:SetTextColor(0.25, 0.16, 0.06)
    local bStatus = view:CreateFontString(nil, "OVERLAY", "GameFontBlackSmall")
    bStatus:SetPoint("TOP", bTitle, "BOTTOM", 0, -4)
    bStatus:SetWidth(300)

    -- The page's words (owner, 2026-09-28: "look at adding the book text"),
    -- from BookTexts.lua, scrollable for long pages.
    local textScroll = CreateFrame("ScrollFrame", nil, view, "UIPanelScrollFrameTemplate")
    -- Top edge is set in RefreshBook from the title's height, so a two-line
    -- title pushes the text down instead of the title and "Reading the
    -- book..." sitting on top of it.
    textScroll:SetPoint("TOPLEFT", view, "TOPLEFT", 22, -58)
    textScroll:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -34, 118)
    local textChild = CreateFrame("Frame", nil, textScroll)
    textChild:SetSize(300, 10)
    textScroll:SetScrollChild(textChild)
    local bText = textChild:CreateFontString(nil, "OVERLAY", "QuestFont")
    bText:SetPoint("TOPLEFT", 0, 0)
    bText:SetWidth(300)
    bText:SetJustifyH("LEFT")
    bText:SetJustifyV("TOP")
    bText:SetTextColor(0.18, 0.12, 0.05)

    local bPage = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    bPage:SetPoint("BOTTOM", view, "BOTTOM", 0, 86)
    bPage:SetTextColor(0.3, 0.2, 0.08)
    local function Btn(label, w, point, x, y)
        local b = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
        b:SetSize(w, 24)
        b:SetPoint(point, view, point, x, y)
        b:SetText(label)
        return b
    end
    local prevBtn = Btn("< Prev", 80, "BOTTOMLEFT", 20, 80)
    local nextBtn = Btn("Next >", 80, "BOTTOMRIGHT", -20, 80)
    local playPageBtn = Btn("Play page", 100, "BOTTOM", -56, 46)
    local readBtn = Btn("Read book", 100, "BOTTOM", 56, 46)
    local backBtn = Btn("Back to books", 120, "BOTTOM", 0, 12)

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
            bText:SetText(PageText(book, idx))
            textChild:SetHeight(math.max(10, bText:GetStringHeight() + 8))
            textScroll:SetVerticalScroll(0)
            view.shownIndex, view.shownBook = idx, book
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
            print("SpeakStone Audio Library: page " .. page .. " of '" .. BookName(book.base) .. "' not found")
            return false
        end
        local willPlay, handle = PlaySoundFile(soundPath, "Dialog")
        if not (willPlay and handle) then return false end
        activeDebugSound = handle
        activeBook, activeBookPage, activeBookWhole = book, page, whole
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

        local soundPath
        if addon.FindSound then
            local _, path = addon.FindSound({ questID .. "_" .. audioType })
            soundPath = path
        end

        if not soundPath then
            print("SpeakStone Audio Library: clip not found for Quest ID " .. tostring(questID) .. " (" .. tostring(audioType) .. ")")
            return
        end

        local willPlay, handle = PlaySoundFile(soundPath, "Dialog")
        if willPlay and handle then
            activeDebugSound = handle
            activePlayingQuestID = questID
            activePlayingType = audioType
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

        local soundPath
        if addon.FindSound then
            local _, path = addon.FindSound({ "npc" .. npcID .. "_gossip" .. variant })
            soundPath = path
        end

        if not soundPath then
            print("SpeakStone Audio Library: clip not found for NPC " .. tostring(npcID) .. " gossip " .. tostring(variant))
            return
        end

        local willPlay, handle = PlaySoundFile(soundPath, "Dialog")
        if willPlay and handle then
            activeDebugSound = handle
            activePlayingNPCID = npcID
            activePlayingVariant = variant
            self:UpdateList()
        end
    end

    -- Main populate / toggle
    function frame:PopulateList()
        self:BuildIndex()
        self:FilterList(self.searchBox:GetText())
    end

    function frame:SetMode(mode)
        if self.mode == mode then return end
        -- Drop the previous tab's list BEFORE anything redraws: resetting the
        -- scrollbar in FilterList redraws at once, and it used to draw the old
        -- tab's rows under the new mode (gossip rows as books, etc.).
        self.filteredList = nil
        if self.CloseBook then self:CloseBook() end
        self:StopAudio()
        self.mode = mode
        local hints = {
            quests = "Search quest ID, name, race or sex...",
            gossip = "Search NPC ID, name, race or sex...",
            books = "Search book name...",
        }
        if searchBox.Instructions then
            searchBox.Instructions:SetText(hints[mode] or hints.quests)
        end
        self:UpdateTabs()
        -- A rebuilt index invalidates the narrowing FilterList relies on --
        -- the previous result was drawn from the other mode's list.
        self.lastQuery = nil
        self.lastResult = nil
        self:FilterList(self.searchBox:GetText())
    end

    -- The selected tab is shown pressed and can't be clicked again.
    function frame:UpdateTabs()
        local current = self.mode or "quests"
        for mode, tab in pairs(self.tabs) do
            if mode == current then
                tab:Disable()
                tab:LockHighlight()
            else
                tab:Enable()
                tab:UnlockHighlight()
            end
        end
    end
    for mode, tab in pairs(frame.tabs) do
        tab:SetScript("OnClick", function() frame:SetMode(mode) end)
    end
    frame:UpdateTabs()

    function frame:ToggleVisibility()
        if self:IsVisible() then
            self:Hide()
        else
            self:Show()
        end
    end

    -- SearchBox script
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if SearchBoxTemplate_OnTextChanged then
            SearchBoxTemplate_OnTextChanged(self)
        end
        frame:QueueFilter(self:GetText())
    end)

    searchBox:SetScript("OnEscapePressed", function(self)
        if self:GetText() ~= "" then
            self:SetText("")
        else
            frame:Hide()
        end
    end)

    frame:SetScript("OnShow", function(self)
        -- Every SpeakStone window defaulted to plain SetPoint("CENTER"), so
        -- opening this from the Settings window (its main entry point) landed
        -- it in the exact same screen position, stacked on top. Anchor beside
        -- Settings when it is open; otherwise fall back to centered.
        self:ClearAllPoints()
        if SpeakStoneSettingsFrame and SpeakStoneSettingsFrame:IsShown() then
            self:SetPoint("LEFT", SpeakStoneSettingsFrame, "RIGHT", 12, 0)
        else
            self:SetPoint("CENTER")
        end
        self:Raise()
        titleLoader:RegisterEvent("QUEST_DATA_LOAD_RESULT")
        -- A title the client did not know last time it may know now -- so the
        -- narrowed result from the previous open, computed while those were
        -- still misses, cannot be reused either.
        wipe(titleMisses)
        self.lastQuery = nil
        self.lastResult = nil
        self:PopulateList()
    end)

    frame:SetScript("OnHide", function(self)
        -- Titles still in flight are of no use to a list nobody is looking
        -- at, and the client caches what it has already sent -- so a quest
        -- whose answer lands after this is resolved from the cache on the
        -- next open rather than lost.
        titleLoader:UnregisterEvent("QUEST_DATA_LOAD_RESULT")
        if searchTimer then
            searchTimer:Cancel()
            searchTimer = nil
        end
        -- A pass left running against a closed window is work nobody is
        -- waiting for, and it would keep waking every frame until it finished.
        CancelFilter()
        self:StopAudio()
        self:CloseBook()
        -- The index is tens of thousands of rows and most of the addon's
        -- memory. Rebuilding it on the next open costs a moment; keeping it
        -- costs every player the memory all session.
        self.allQuests, self.allGossip, self.allBooks = nil, nil, nil
        self.filteredList, self.lastQuery, self.lastResult = nil, nil, nil
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

-- `mode` ("quests", "gossip" or "books") opens straight onto that tab: the
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
SLASH_QRLIBRARY1, SLASH_QRLIBRARY2 = '/qrlibrary', '/sslibrary'
SlashCmdList["QRLIBRARY"] = function()
    addon.ToggleAudioLibrary()
end
