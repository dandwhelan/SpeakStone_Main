local addonName, addon = ...

-- The lore book (owner picked the mock 2026-11-02): a two-page book, the zone's map on the left in a notebook-ink
-- style, the story on the right with Play and the sentence being read lit up, one tab per zone down the page edge.
-- No "heard" mark (owner: not interested). Open with /sslore or the Lore tab's button.
--
-- The map is <pack>/Maps/zonelore_<map>.tga in the pack that holds the zone's narration (tools/make_lore_maps.py
-- draws it, build_sound_packs.py copies it). The texture is 512x512 with the map in the top 512x342.
-- Text, audio and playback come from ZoneLore.lua; this file is only the window.

local BOOK_W, BOOK_H = 1110, 560
local MAP_W, MAP_H = 520, 347
local TEXT_W = 340
local TELLER = "Told by the narrator"

local book, current, ticker

function addon.LoreBookMapPath(entry)
    local _, path = addon.ZoneLoreClip(entry)
    if type(path) ~= "string" then return nil end
    local root = path:match("^(.-)[/\\][Ss]ounds[/\\]")
    return root and (root .. "\\Maps\\zonelore_" .. entry.map) or nil
end

-- Words, word times and sentence starts for the entry now playing (cached per play).
local timing
local function TimingFor(entry, sd)
    if timing and timing.sd == sd then return timing end
    local words = addon.SubtitleWords(entry.text)
    local times, starts = addon.SubtitleTiming(words, sd.duration, sd.soundFile)
    timing = { sd = sd, words = words, times = times, starts = starts }
    return timing
end

-- The story text for this moment: plain, or with the sentence being read in the highlight colour.
function addon.LoreBookText(entry)
    local sd = addon.activeSound
    if not (entry and sd and addon.ZoneLoreIsPlaying(entry) and sd.startedAt and sd.duration) then
        return entry and entry.text or ""
    end
    local t = TimingFor(entry, sd)
    local index = addon.SubtitleWordAt(t.times, GetTime() - sd.startedAt)
    local span = addon.SubtitleSpan(t.starts, index, t.words, false)
    return addon.SubtitleRender(t.words, index, false, true, addon.HighlightCode(true), span)
end

local function Refresh()
    if not (book and current) then return end
    book.story:SetText(addon.LoreBookText(current))
    local playing = addon.ZoneLoreIsPlaying(current)
    book.play:SetText(playing and "Stop" or "Play")
    book.play:SetShown(addon.ZoneLoreClip(current) ~= nil)
    if not playing and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function Show(entry)
    current = entry
    book.title:SetText(entry.title)
    local map = addon.LoreBookMapPath(entry)
    book.map:SetShown(map ~= nil)
    if map then book.map:SetTexture(map) end
    for _, tab in ipairs(book.tabs) do
        tab:SetAlpha(tab.entry == entry and 1 or 0.6)
    end
    Refresh()
end

local function Build()
    local UIK = addon.UIK
    book = UIK.Window("SpeakStoneLoreBook", BOOK_W, BOOK_H, "Lore")
    tinsert(UISpecialFrames, "SpeakStoneLoreBook")

    -- Left page: the map, framed by a soft shadow.
    book.mapBack = book:CreateTexture(nil, "BORDER")
    book.mapBack:SetColorTexture(0.93, 0.88, 0.75, 1)
    book.mapBack:SetSize(MAP_W + 8, MAP_H + 8)
    book.mapBack:SetPoint("TOPLEFT", book, "TOPLEFT", 26, -70)
    book.map = book:CreateTexture(nil, "ARTWORK")
    book.map:SetSize(MAP_W, MAP_H)
    book.map:SetPoint("CENTER", book.mapBack, "CENTER")
    book.map:SetTexCoord(0, 1, 0, 342 / 512)

    -- The fold between the pages.
    book.fold = book:CreateTexture(nil, "BORDER")
    book.fold:SetColorTexture(0, 0, 0, 0.18)
    book.fold:SetSize(2, BOOK_H - 80)
    book.fold:SetPoint("TOPLEFT", book, "TOPLEFT", MAP_W + 52, -50)

    -- Right page: title, teller, story, Play.
    local x = MAP_W + 72
    book.title = book:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    book.title:SetPoint("TOPLEFT", book, "TOPLEFT", x, -60)
    book.teller = book:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    book.teller:SetPoint("TOPLEFT", book.title, "BOTTOMLEFT", 0, -4)
    book.teller:SetText(TELLER)
    book.story = book:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    book.story:SetPoint("TOPLEFT", book.teller, "BOTTOMLEFT", 0, -14)
    book.story:SetWidth(TEXT_W)
    book.story:SetJustifyH("LEFT")
    book.story:SetSpacing(4)
    book.play = UIK.Button(book, "Play", 90, 26, function()
        if not current then return end
        if addon.ZoneLoreIsPlaying(current) then
            addon.ZoneLoreStop(current)
        elseif addon.ZoneLorePlay(current) then
            if ticker then ticker:Cancel() end
            ticker = C_Timer.NewTicker(0.1, Refresh)
        end
        Refresh()
    end)
    book.play:SetPoint("BOTTOMLEFT", book, "BOTTOMLEFT", x, 24)

    -- Tabs down the right edge, one per zone.
    book.tabs = {}
    local prev
    for _, item in ipairs(addon.ZoneLoreList()) do
        local tab = UIK.Button(book, item.title, 120, 24, function() Show(item.entry) end)
        tab.entry = item.entry
        if prev then
            tab:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -4)
        else
            tab:SetPoint("TOPRIGHT", book, "TOPRIGHT", -16, -60)
        end
        book.tabs[#book.tabs + 1] = tab
        prev = tab
    end

    book:HookScript("OnHide", function()
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
    end)
end

-- Open the book at an entry (default: the zone the player is in, else the first zone).
function addon.LoreBookOpen(entry)
    local list = addon.ZoneLoreList and addon.ZoneLoreList() or {}
    if #list == 0 then return false end
    if not book then Build() end
    if not entry then
        local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
        entry = ok and addon.ZoneLoreEntryFor(mapID) or nil
    end
    book:Show()
    Show(entry or current or list[1].entry)
    if addon.ZoneLoreIsPlaying(current) and not ticker then
        ticker = C_Timer.NewTicker(0.1, Refresh)
    end
    return true
end

function addon.LoreBookToggle()
    if book and book:IsShown() then
        book:Hide()
    else
        addon.LoreBookOpen()
    end
end

SLASH_SPEAKSTONELORE1, SLASH_SPEAKSTONELORE2 = "/sslore", "/speakstonelore"
SlashCmdList.SPEAKSTONELORE = function() addon.LoreBookToggle() end
