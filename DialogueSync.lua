local addonName, addon = ...

-- Quest text that follows the voice inside Dialogue UI's own window (opt-in:
-- syncDialogueText). Dialogue UI lays a quest's text out in full the moment
-- the window opens and gives voiceover addons nothing to follow, so this works
-- it out as the subtitles do (Subtitles.lua): nothing reports a clip's
-- position, but we know when it started and how long it is, and the words'
-- start times are estimated from their length and punctuation.
--
-- With "type the words out" (subtitleTypeOut) each paragraph the voice reads
-- shows only the words reached so far, and the ones after it nothing; with
-- "highlight" (subtitleHighlight) the word being read and the one before it
-- are gold. The original text goes back when the line ends, the clip stops,
-- another quest takes the window, or the window closes: Dialogue UI reads that
-- text back for its own text-to-speech.
--
-- Nothing in Dialogue UI is changed. This reaches it from outside, through
-- names that are its internals rather than an API: DUIQuestFrame is the
-- window, each paragraph of text is a FontString in its fontStringPool, and
-- the Handle* methods build a page (hooked with hooksecurefunc, because it
-- rebuilds on an item reward resolving, a settings change or a repeated
-- QUEST_DETAIL). If any of it is missing nothing happens.
--
-- No flash: SpeakStone starts a clip a moment after the window opens (the
-- autoplay delay), and Dialogue UI draws the page at once. So the playback
-- code tells us a line is coming (QuestTextSyncExpect) and the words are blank
-- from the first frame until the voice reaches them.

local LEAD = 0.12              -- seconds the typing runs ahead of the voice
local UPDATE_INTERVAL = 0.05
local MIN_MATCH = 0.6          -- below this share of the spoken words matched, the window shows something else
local EXPECT_EXTRA = 2.5       -- seconds past the autoplay delay a coming line is waited for

local sync   -- { sd, paras, words, times, ticker, expecting, expectUntil }

local function DB()
    return SpeakStone_MainDB or {}
end

local function Norm(text)
    text = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return (text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

local function Enabled()
    return DB().syncDialogueText == true
end

-- Put every paragraph back as Dialogue UI wrote it. A paragraph whose text is
-- no longer what we last set belongs to a page built since: left alone.
local function Restore(s)
    for _, para in ipairs(s.paras or {}) do
        if para.fs:GetText() == para.shown then
            para.fs:SetText(para.orig)
        end
        para.shown = para.orig
    end
end

local function EndSync()
    local s = sync
    if not s then
        return
    end
    sync = nil
    if s.ticker then
        s.ticker:Cancel()
    end
    Restore(s)
end

-- The paragraphs of the spoken text Dialogue UI is showing, top to bottom,
-- with the words each holds. Nil when the window is not there or shows
-- something else.
local function Bind(sd)
    local ui = _G.DUIQuestFrame
    if not (ui and ui.IsShown and ui:IsShown() and ui.fontStringPool and ui.fontStringPool.EnumerateActive) then
        return nil
    end
    local spoken = Norm(sd.text)
    if spoken == "" then
        return nil
    end
    local found = {}
    for _, fs in ui.fontStringPool:EnumerateActive() do
        local orig = fs:GetText()
        local t = Norm(orig)
        if t ~= "" and fs:IsShown() and spoken:find(t, 1, true) then
            local direction = t:match("^<.*>$")           -- a stage direction is on screen but not read
            local linked = orig:find("|H", 1, true)       -- never split a link
            found[#found + 1] = {
                fs = fs, orig = orig, shown = orig, top = fs:GetTop() or 0, chars = #t,
                words = (not direction and not linked) and addon.SubtitleWords(orig) or {},
            }
            -- Dark text means light paper (the parchment theme).
            local r, g, b = fs:GetTextColor()
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                found[#found].light = (r + g + b) < 1.5
            end
        end
    end
    local matched = 0
    for _, para in ipairs(found) do
        matched = matched + para.chars
    end
    if #found == 0 or matched < MIN_MATCH * #spoken then
        return nil
    end
    table.sort(found, function(a, b) return a.top > b.top end)
    local words = {}
    for _, para in ipairs(found) do
        para.a = #words + 1
        for _, word in ipairs(para.words) do
            words[#words + 1] = word
        end
        para.b = #words
    end
    if #words == 0 then
        return nil
    end
    return found, words
end

local function Draw(s, index)
    local db = DB()
    local typeOut = db.subtitleTypeOut ~= false
    local highlight = db.subtitleHighlight ~= false
    for _, para in ipairs(s.paras) do
        if #para.words > 0 then
            local code = addon.HighlightCode(para.light)
            local want
            if typeOut and index < para.a then
                want = " "                                   -- not reached yet
            elseif not highlight and (not typeOut or index >= para.b) then
                want = para.orig                             -- nothing to mark: the text as it was
            else
                local parts = {}
                for k, word in ipairs(para.words) do
                    local global = para.a + k - 1
                    if typeOut and global > index then
                        break
                    end
                    if highlight and index > 0 and (global == index or global == index - 1) then
                        word = code .. word .. "|r"
                    end
                    parts[#parts + 1] = word
                end
                want = #parts > 0 and table.concat(parts, " ") or " "
            end
            if para.shown ~= want then
                para.fs:SetText(want)
                para.shown = want
            end
        end
    end
end

-- Long text: bring the paragraph being read into view (forward only, so a
-- player who scrolls back up is not dragged down again).
local function Follow(s, index)
    local ui = _G.DUIQuestFrame
    local range = ui and ui.ScrollFrame and ui.ScrollFrame.range or 0
    if range <= 0 or not ui.ScrollTo or not ui.ContentFrame or not ui.scrollViewHeight then
        return
    end
    for _, para in ipairs(s.paras) do
        if #para.words > 0 and index >= para.a and not para.scrolled then
            para.scrolled = true
            local top, bottom = ui.ContentFrame:GetTop(), para.fs:GetBottom()
            if top and bottom then
                local target = math.min(range, (top - bottom) - ui.scrollViewHeight)
                if target > (s.scrolledTo or 0) then
                    s.scrolledTo = target
                    pcall(ui.ScrollTo, ui, target)
                end
            end
        end
    end
end

local function Tick()
    local s = sync
    if not s then
        return
    end
    local ui = _G.DUIQuestFrame
    if not (ui and ui:IsShown()) then
        return EndSync()
    end
    local sd = s.sd
    if not s.paras then
        s.paras, s.words = Bind(sd)
        if not s.paras then
            if not s.expecting or GetTime() > s.expectUntil then
                EndSync()
            end
            return
        end
        s.times = nil
    end
    -- A page rebuilt under us is no longer ours.
    for _, para in ipairs(s.paras) do
        if #para.words > 0 and para.fs:GetText() ~= para.shown then
            s.paras = nil
            return
        end
    end
    local index = 0
    if s.expecting then
        -- The line is coming: nothing read yet. Give up if it never starts.
        if GetTime() > s.expectUntil then
            return EndSync()
        end
    else
        local duration = tonumber(sd.duration)
        if not (duration and duration > 0 and sd.startedAt) then
            return EndSync()
        end
        s.times = s.times or addon.SubtitleWordTimes(s.words, duration)
        local elapsed = math.max(0, GetTime() - sd.startedAt)
        index = elapsed >= duration and #s.words or addon.SubtitleWordAt(s.times, elapsed + LEAD)
    end
    Draw(s, index)
    if index > 0 then
        Follow(s, index)
    end
    if not s.expecting and index >= #s.words and GetTime() - sd.startedAt >= tonumber(sd.duration) then
        EndSync()
    end
end

local function StartSync(sd, expecting)
    EndSync()
    if not Enabled() or not sd or not sd.questID or not sd.text
        or not (sd.textType == "description" or sd.textType == "progress" or sd.textType == "completion") then
        return
    end
    if not _G.DUIQuestFrame then
        return
    end
    local wait = (tonumber(DB().autoPlayDelay) or 1.0) + EXPECT_EXTRA
    sync = { sd = sd, expecting = expecting, expectUntil = GetTime() + math.min(10, wait) }
    sync.ticker = C_Timer.NewTicker(UPDATE_INTERVAL, Tick)
    Tick()
end

-- The playback code has a quest line it is about to read: blank its words now.
function addon.QuestTextSyncExpect(sd)
    if sd and sd.duration and sd.duration > 0 then
        StartSync(sd, true)
    end
end

function addon.QuestTextSyncNotify(event, sd)
    if event == "start" then
        StartSync(sd, false)
    elseif event == "wait" then
        -- Held (combat): the text shows whole until the voice is ready.
        EndSync()
    elseif sync and sync.sd == sd and (event == "stop" or event == "finish") then
        EndSync()
    end
end
addon.QuestTextSyncEnd = EndSync

-- A page Dialogue UI has just built or rebuilt: bind it before it is drawn.
function addon.QuestTextSyncHook()
    local ui = _G.DUIQuestFrame
    if not ui or addon.dialogueSyncHooked or type(hooksecurefunc) ~= "function" then
        return
    end
    for _, name in ipairs({ "HandleQuestDetail", "HandleQuestProgress", "HandleQuestComplete",
                            "HandleQuestGreeting", "HandleGossip" }) do
        if type(ui[name]) == "function" then
            addon.dialogueSyncHooked = true
            hooksecurefunc(ui, name, function()
                if sync then
                    sync.paras = nil
                    Tick()
                end
            end)
        end
    end
end

-- --------------------------------------------------------------------------
-- Talking heads (opt-in: talkingHeadHighlight)
-- --------------------------------------------------------------------------
-- Blizzard's talking head plays its own voice line and shows the words in
-- TalkingHeadFrame.TextFrame.Text. The line's length is known
-- (C_TalkingHead.GetCurrentLineInfo), so the word being read is lit the way the
-- subtitles do it. The words are not typed out (the head shows them whole), and
-- the original text goes back when the line ends.

local head   -- { fs, orig, shown, words, times, startedAt, duration, ticker }

local function EndHead()
    local h = head
    if not h then
        return
    end
    head = nil
    if h.ticker then
        h.ticker:Cancel()
    end
    if h.fs:GetText() == h.shown then
        h.fs:SetText(h.orig)
    end
end

local function HeadTick()
    local h = head
    if not h then
        return
    end
    local frame = _G.TalkingHeadFrame
    local elapsed = GetTime() - h.startedAt
    if not (frame and frame:IsShown()) or elapsed > h.duration + 0.5 or h.fs:GetText() ~= h.shown then
        return EndHead()
    end
    local index = addon.SubtitleWordAt(h.times, elapsed + LEAD)
    local want = addon.SubtitleRender(h.words, index, false, true, addon.HighlightCode(false))
    if want ~= h.shown then
        h.fs:SetText(want)
        h.shown = want
    end
end

local function StartHead()
    EndHead()
    if DB().talkingHeadHighlight ~= true then
        return
    end
    local frame = _G.TalkingHeadFrame
    local fs = frame and frame.TextFrame and frame.TextFrame.Text
    if not fs or not C_TalkingHead or not C_TalkingHead.GetCurrentLineInfo then
        return
    end
    local ok, _, _, _, duration = pcall(C_TalkingHead.GetCurrentLineInfo)
    if not ok or type(duration) ~= "number" or duration <= 0 then
        return
    end
    local orig = fs:GetText()
    if type(orig) ~= "string" or (addon.IsSecret and addon.IsSecret(orig)) or orig == "" then
        return
    end
    local words = {}
    for word in orig:gmatch("%S+") do
        words[#words + 1] = word
    end
    if #words == 0 or orig:find("|", 1, true) then
        return
    end
    head = { fs = fs, orig = orig, shown = orig, words = words, duration = duration,
        times = addon.SubtitleWordTimes(words, duration), startedAt = GetTime() - 0.1 }
    head.ticker = C_Timer.NewTicker(UPDATE_INTERVAL, HeadTick)
    HeadTick()
end

-- A talking head with several lines sends TALKINGHEAD_REQUESTED for the first one only: the frame moves on to the
-- next line by itself. So once a head has started, a light watcher looks for a new line's words appearing in the
-- frame and starts the highlight again for it; it stops when the head closes.
local watcher, lastText

local function WatchHead()
    if head then
        lastText = head.orig
        return
    end
    local frame = _G.TalkingHeadFrame
    local fs = frame and frame:IsShown() and frame.TextFrame and frame.TextFrame.Text
    if not fs then
        return
    end
    local text = fs:GetText()
    if type(text) == "string" and text ~= "" and text ~= lastText and not (addon.IsSecret and addon.IsSecret(text)) then
        StartHead()
        if head then
            lastText = head.orig
        end
    end
end

local function StopWatching()
    if watcher then
        watcher:Cancel()
        watcher = nil
    end
    lastText = nil
end

local headEvents = CreateFrame("Frame")
for _, event in ipairs({ "TALKINGHEAD_REQUESTED", "TALKINGHEAD_CLOSE" }) do
    pcall(headEvents.RegisterEvent, headEvents, event)
end
headEvents:SetScript("OnEvent", function(_, event)
    if event == "TALKINGHEAD_CLOSE" then
        EndHead()
        StopWatching()
    else
        -- A fresh request is a fresh line: forget the last one so it is picked up even if the words repeat.
        lastText = nil
        if not watcher and DB().talkingHeadHighlight == true then
            watcher = C_Timer.NewTicker(0.2, WatchHead)
        end
        -- After the frame has put the line's words up.
        C_Timer.After(0.1, StartHead)
    end
end)
