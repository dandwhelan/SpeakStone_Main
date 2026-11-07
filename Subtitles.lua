local addonName, addon = ...

-- Subtitles: the line being spoken, over the world, in its own small bar --
-- who is speaking, the words typed out as the voice reaches them, the word
-- being read in gold, a thin progress line, and how many lines wait behind it.
-- An alternative to the speech frame (SpeechFrame.lua), which only shows once
-- the dialogue window has closed; the subtitles are there while it is open.
--
-- Nothing reports where a clip is, and the packs hold no word timestamps, so
-- the timing is an estimate: the clip's length is shared out over its words by
-- their length and the punctuation after them (a sentence end holds longer than
-- a comma). The gold lights the word being read and the one before it, so a
-- word the estimate gets slightly wrong is still lit.
--
-- Driven by the same notices as the speech frame ("start", "finish", "stop"),
-- passed on from addon.SpeechFrameNotify.

local GOLD = "|cfff0c94a"
-- The colour of the word being read. "auto" is gold, and deep red where the
-- text sits on light paper (Dialogue UI's parchment theme), where gold is
-- hard to read.
local HIGHLIGHT_COLOURS = {
    { key = "auto", label = "Automatic", rgb = { 0.94, 0.79, 0.29 } },
    { key = "gold", label = "Gold", code = GOLD, rgb = { 0.94, 0.79, 0.29 } },
    { key = "white", label = "White", code = "|cffffffff", rgb = { 1, 1, 1 } },
    { key = "cyan", label = "Cyan", code = "|cff5fe0ff", rgb = { 0.37, 0.88, 1 } },
    { key = "green", label = "Green", code = "|cff7dff7d", rgb = { 0.49, 1, 0.49 } },
    { key = "pink", label = "Pink", code = "|cffff7ab8", rgb = { 1, 0.48, 0.72 } },
    { key = "red", label = "Deep red", code = "|cffb01e1e", rgb = { 0.69, 0.12, 0.12 } },
}
addon.HighlightColours = HIGHLIGHT_COLOURS

-- The bar's background and its text, for readers who find some pairs easier
-- than others (dyslexia, low vision): six colours each, or the theme's own.
-- Soft cream, yellow, blue and green paper with dark ink are the pairings
-- most often recommended; black, white and yellow serve low vision.
addon.SubtitleBackColours = {
    { key = "theme", label = "Theme", rgb = { 0.45, 0.45, 0.5 } },
    { key = "black", label = "Black", rgb = { 0, 0, 0 } },
    { key = "navy", label = "Dark blue", rgb = { 0.05, 0.08, 0.25 } },
    { key = "cream", label = "Cream", rgb = { 0.98, 0.94, 0.82 } },
    { key = "yellow", label = "Pale yellow", rgb = { 1, 0.96, 0.62 } },
    { key = "blue", label = "Soft blue", rgb = { 0.8, 0.9, 1 } },
    { key = "green", label = "Soft green", rgb = { 0.82, 0.95, 0.84 } },
}
addon.SubtitleTextColours = {
    { key = "theme", label = "Theme", rgb = { 0.45, 0.45, 0.5 } },
    { key = "white", label = "White", rgb = { 1, 1, 1 } },
    { key = "black", label = "Black", rgb = { 0.05, 0.05, 0.05 } },
    { key = "ink", label = "Dark blue", rgb = { 0.08, 0.12, 0.38 } },
    { key = "brown", label = "Dark brown", rgb = { 0.25, 0.15, 0.08 } },
    { key = "yellow", label = "Yellow", rgb = { 1, 0.92, 0.4 } },
    { key = "mint", label = "Mint", rgb = { 0.7, 1, 0.85 } },
}

-- The colour a player picked with the colour picker, or nil.
local function Custom(option)
    local c = SpeakStone_MainDB and SpeakStone_MainDB[option .. "Custom"]
    if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number" then
        return c
    end
    return nil
end
addon.CustomColour = Custom

local function Pick(list, key, option)
    if key == "custom" then
        return Custom(option)
    end
    for _, colour in ipairs(list) do
        if colour.key == key and colour.key ~= "theme" then
            return colour.rgb
        end
    end
    return nil
end

-- The colours the bar is drawn in: the theme's, with the player's own choices over them.
function addon.SubtitleColours()
    local theme = addon.Theme()
    local db = SpeakStone_MainDB or {}
    local back = Pick(addon.SubtitleBackColours, db.subtitleBack, "subtitleBack")
    local text = Pick(addon.SubtitleTextColours, db.subtitleText, "subtitleText")
    local light = theme.light
    if back then
        light = (back[1] + back[2] + back[3]) / 3 > 0.55
    end
    local ink = text or (back and (light and { 0.08, 0.08, 0.1 } or { 1, 1, 1 })) or theme.text
    return {
        back = back, text = ink, light = light,
        name = text or (back and ink) or theme.title,
        sub = text or (back and ink) or theme.sub,
        accent = (back and ink) or theme.accent,
    }
end
local UPDATE_INTERVAL = 0.05
local LEAD = 0.12              -- seconds the typing runs ahead of the voice
local LINGER_SECONDS = 1.5
local WIDTH = 720
local LINE_SPACING = 3
local DEFAULT_FONT_SIZE = 18
local SNAP_PIXELS = 24
local MIN_SCALE, MAX_SCALE = 0.6, 2.0
local DEFAULT_POS = { 0, 150 }  -- x from the screen's middle, y from its foot

local frame, driver, current, lingerUntil

local function DB()
    return SpeakStone_MainDB or {}
end

-- --------------------------------------------------------------------------
-- Words and timing (no frames: tested on their own)
-- --------------------------------------------------------------------------

-- The words the voice reads. Stage directions in angle brackets are not read
-- ("<Kinduru stretches out a wing.>"), unless the brackets wrap the whole
-- passage, which is object text that is read with the brackets dropped.
-- narrated (addon.ClipNarrated): this clip's narrator reads the directions,
-- so their words stay, brackets and all, as ReadTokens keeps them.
-- tools/build_sentence_timings.py split_words mirrors this.
function addon.SubtitleWords(text, narrated)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    local inner = text:match("^%s*<(.*)>%s*$")
    if inner and not inner:find("[<>]") then
        text = inner
    elseif not narrated then
        text = text:gsub("<[^<>]*>", " ")
    end
    local words = {}
    for word in text:gmatch("%S+") do
        words[#words + 1] = word
    end
    return words
end

-- ">" closes like a quote: a narrated direction ends "...whisper.>".
local function Weight(word)
    local weight = #word + 2
    if word:find("[%.!%?][\"')%]>]*$") then
        weight = weight + 8
    elseif word:find("[,;:][\"')>]*$") then
        weight = weight + 4
    elseif word:find("%-%-$") or word:find("%.%.%.") then
        weight = weight + 3
    end
    return weight
end

-- When each word starts, in seconds from the start of the clip.
function addon.SubtitleWordTimes(words, duration)
    local total = 0
    local starts = {}
    for i, word in ipairs(words) do
        starts[i] = total
        total = total + Weight(word)
    end
    local times = {}
    for i = 1, #words do
        times[i] = total > 0 and starts[i] / total * duration or 0
    end
    return times
end

-- The word being read at `elapsed` seconds: the last one that has started
-- (0 before the first).
function addon.SubtitleWordAt(times, elapsed)
    local lo, hi, found = 1, #times, 0
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        if times[mid] <= elapsed then
            found = mid
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    return found
end

-- --------------------------------------------------------------------------
-- Sentences. tools/build_sentence_timings.py holds a mirror of the rules below (split_words, sentence_starts): change
-- both together. A word ends a sentence when it ends in . ! or ? (closing quotes allowed), is not an abbreviation
-- ("Mr.", a lone initial), and the next word does not begin with a lower-case letter.
-- --------------------------------------------------------------------------

local ABBREV = {
    mr = true, mrs = true, ms = true, dr = true, st = true, lt = true, capt = true, sgt = true, col = true,
    gen = true, cmdr = true, prof = true, jr = true, sr = true, vs = true, mt = true, ft = true, adm = true,
    maj = true, cpl = true, pvt = true, rev = true, hon = true, esq = true, etc = true,
}

local function EndsSentence(word)
    local core = word:gsub(">+$", "")             -- "...whisper.>": a narrated direction's end
    while true do
        local s = core:gsub("\226\128[\153\157]$", "")
        if s == core then break end
        core = s
    end
    if not core:find("[%.!%?][\"')%]]*$") then
        return false
    end
    if core:find("%a%.$") then
        local bare = core:gsub("[^%a]", ""):lower()
        if ABBREV[bare] or (#bare == 1 and bare ~= "i" and bare ~= "a") then
            return false
        end
    end
    return true
end

local function FirstLetter(word)
    while true do
        local s = word:gsub("^[\"'%(%[%-<]", "", 1)
        if s == word then s = word:gsub("^\226\128[\152\156]", "", 1) end
        if s == word then break end
        word = s
    end
    return word:sub(1, 1)
end

-- The word numbers (1-based) where a sentence begins; always starts with 1.
function addon.SubtitleSentences(words)
    local starts = {}
    if #words == 0 then
        return starts
    end
    starts[1] = 1
    for i = 2, #words do
        if EndsSentence(words[i - 1]) and not FirstLetter(words[i]):find("^%l$") then
            starts[#starts + 1] = i
        end
    end
    return starts
end

-- Which sentence a word belongs to (starts from SubtitleSentences).
function addon.SubtitleSentenceOf(starts, index)
    local found = 1
    for s = 1, #starts do
        if starts[s] <= index then found = s else break end
    end
    return found
end

-- True when `marks` (seconds, sentence 2 onward, from the pack's SentenceTimings) fit this text and clip: one per
-- sentence after the first, rising, inside the clip. Text that splits differently from the voiced text gets no marks.
function addon.SubtitleMarksFit(marks, sentenceCount, duration)
    if type(marks) ~= "table" or #marks ~= sentenceCount - 1 or not duration or duration <= 0 then
        return false
    end
    local prev = 0
    for _, t in ipairs(marks) do
        if type(t) ~= "number" or t <= prev or t >= duration then
            return false
        end
        prev = t
    end
    return true
end

-- Word start times when the sentence starts are known: each sentence's words share the stretch from its start to the
-- next sentence's start (the last one to the end of the clip), by the same weights as SubtitleWordTimes.
function addon.SubtitleWordTimesAnchored(words, starts, marks, duration)
    local times = {}
    for s = 1, #starts do
        local first = starts[s]
        local last = (starts[s + 1] or (#words + 1)) - 1
        local t0 = s == 1 and 0 or marks[s - 1]
        local t1 = starts[s + 1] and marks[s] or duration
        local total = 0
        for i = first, last do
            total = total + Weight(words[i])
        end
        local acc = 0
        for i = first, last do
            times[i] = t0 + (total > 0 and acc / total or 0) * (t1 - t0)
            acc = acc + Weight(words[i])
        end
    end
    return times
end

-- Word start times for a clip: the pack's sentence timings anchor them when they fit this text and clip (and then
-- `starts`, the first word of each sentence, comes back too); otherwise the plain estimate and no starts. Every place
-- that follows the voice through the words uses this, so they all light the same sentence.
function addon.SubtitleTiming(words, duration, soundFile)
    local times = addon.SubtitleWordTimes(words, duration)
    if duration and duration > 0 and addon.SentenceTimesFor and type(soundFile) == "string" then
        local ok, marks = pcall(addon.SentenceTimesFor, soundFile:match("[^/\\]+$") or soundFile)
        if ok and marks then
            local starts = addon.SubtitleSentences(words)
            if addon.SubtitleMarksFit(marks, #starts, duration) then
                return addon.SubtitleWordTimesAnchored(words, starts, marks, duration), starts
            end
        end
    end
    return times, nil
end

-- The { first, last } word span of the sentence holding word `index`, or nil (no sentence starts, nothing reached,
-- or the player turned sentence highlighting off). typeOut: the span ends at the word reached.
function addon.SubtitleSpan(starts, index, words, typeOut)
    if not starts or not index or index < 1 or (SpeakStone_MainDB and SpeakStone_MainDB.subtitleSentenceHighlight == false) then
        return nil
    end
    local si = addon.SubtitleSentenceOf(starts, index)
    return { starts[si], typeOut and index or ((starts[si + 1] or (#words + 1)) - 1) }
end

-- The text to draw for a reading position. typeOut: only the words reached.
-- highlight: the word being read and the one before it in gold -- or, with span = { first, last } (timings known),
-- every word of the sentence being read, up to the word reached.
function addon.HighlightCode(onLightBackground)
    local key = SpeakStone_MainDB and SpeakStone_MainDB.highlightColour or "auto"
    if key == "custom" then
        local c = Custom("highlightColour")
        if c then
            return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
                math.floor(c[3] * 255 + 0.5))
        end
    end
    for _, colour in ipairs(HIGHLIGHT_COLOURS) do
        if colour.key == key and colour.code then
            return colour.code
        end
    end
    return onLightBackground and "|cffb01e1e" or GOLD
end

-- The colour the text not being read fades to (fadeOtherParagraphs), on a light or a dark background; nil
-- when the player has the fading off. A colour rather than a transparency because the speech frame, the Guide
-- and the Lore Book draw a whole passage in one FontString.
function addon.FadeCode(onLightBackground)
    if SpeakStone_MainDB and SpeakStone_MainDB.fadeOtherParagraphs == false then
        return nil
    end
    -- Light: about halfway between parchment ink and paper (the first try, 9a8668, washed out in game).
    return onLightBackground and "|cff7d6749" or "|cff7d7d7d"
end

-- dimCode (the Lore Book): with the whole text shown and a sentence lit, the other sentences in that colour.
function addon.SubtitleRender(words, index, typeOut, highlight, code, span, dimCode)
    code = code or GOLD
    if dimCode and span and highlight and not typeOut and index > 0 then
        local before = table.concat(words, " ", 1, span[1] - 1)
        local after = table.concat(words, " ", span[2] + 1)
        local out = code .. table.concat(words, " ", span[1], span[2]) .. "|r"
        if before ~= "" then out = dimCode .. before .. "|r " .. out end
        if after ~= "" then out = out .. " " .. dimCode .. after .. "|r" end
        return out
    end
    local parts = {}
    for k = 1, #words do
        if typeOut and k > index then
            break
        end
        local word = words[k]
        local lit
        if span then
            lit = k >= span[1] and k <= span[2]
        else
            lit = k == index or k == index - 1
        end
        if highlight and index > 0 and lit then
            word = code .. word .. "|r"
        end
        parts[#parts + 1] = word
    end
    return table.concat(parts, " ")
end

-- --------------------------------------------------------------------------
-- The frame
-- --------------------------------------------------------------------------

local function Scale()
    local scale = tonumber(DB().subtitleScale) or 1
    return math.max(MIN_SCALE, math.min(MAX_SCALE, scale))
end

local function Rows()
    return math.max(1, math.min(4, tonumber(DB().subtitleRows) or 2))
end

local function FontSize()
    return math.max(12, math.min(40, tonumber(DB().subtitleFontSize) or DEFAULT_FONT_SIZE))
end

-- The distance from one row to the next, measured from the font in use (a
-- font with tall letters takes more than its size), once ApplyFont has run.
local function LineHeight()
    return (frame and frame.linePitch) or (FontSize() + LINE_SPACING)
end

local function ApplyPosition()
    if not frame then
        return
    end
    local pos = DB().subtitlePos or DEFAULT_POS
    local scale = Scale()
    frame:SetScale(scale)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOM", UIParent, "BOTTOM", pos[1] / scale, pos[2] / scale)
end

local function ApplyRows()
    if not frame then
        return
    end
    local rows = Rows()
    frame.clip:SetHeight(LineHeight() * rows)
    frame:SetHeight(frame.headerHeight + LineHeight() * rows + 22)
end

local function ApplyLock()
    if not frame then
        return
    end
    -- Locked: the bar does not catch the mouse at all, so it never gets in the
    -- way of clicking the world under it.
    frame:EnableMouse(not DB().subtitleLocked)
    frame:EnableMouseWheel(not DB().subtitleLocked)
end

-- Where the bar sits, in screen units from the middle (x) and the foot (y),
-- pulled to the middle and to the foot when it is released close to them.
local function SavePosition()
    local scale = frame:GetScale()
    local cx, bottom = frame:GetCenter(), frame:GetBottom()
    local screenX = UIParent:GetWidth() / 2
    local x = cx * scale - screenX
    local y = bottom * scale
    if math.abs(x) < SNAP_PIXELS then
        x = 0
    end
    if y < SNAP_PIXELS then
        y = 0
    end
    DB().subtitlePos = { x, y }
    ApplyPosition()
end

local Clear, OpenMenu

local function Build()
    if frame then
        return
    end
    frame = CreateFrame("Frame", "SpeakStoneSubtitleFrame", UIParent)
    frame:SetSize(WIDTH, 100)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not DB().subtitleLocked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    frame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            OpenMenu(self)
        end
    end)
    -- Ctrl and the wheel resize the bar, as the speech frame's gear menu does.
    frame:SetScript("OnMouseWheel", function(_, delta)
        if IsControlKeyDown and IsControlKeyDown() and not DB().subtitleLocked then
            local scale = math.max(MIN_SCALE, math.min(MAX_SCALE, Scale() + delta * 0.05))
            DB().subtitleScale = math.floor(scale * 100 + 0.5) / 100
            local pos = DB().subtitlePos or DEFAULT_POS
            DB().subtitlePos = { pos[1], pos[2] }
            ApplyPosition()
        end
    end)
    frame:Hide()

    local back = frame:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    frame.back = back
    local lineTop = frame:CreateTexture(nil, "BORDER")
    lineTop:SetPoint("TOPLEFT")
    lineTop:SetPoint("TOPRIGHT")
    lineTop:SetHeight(1)
    frame.lineTop = lineTop

    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.name:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -8)
    frame.name:SetJustifyH("LEFT")
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.title:SetPoint("LEFT", frame.name, "RIGHT", 10, 0)
    -- A faint X in the subtitle text's colour closes the bar for this line; the voice carries on, as with the
    -- speech bar's close button (owner, 2026-11-07). Brighter under the mouse.
    frame.close = CreateFrame("Button", nil, frame)
    frame.close:SetSize(18, 18)
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
    frame.close.label = frame.close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.close.label:SetPoint("CENTER")
    frame.close.label:SetText("X")
    frame.close:SetAlpha(0.4)
    frame.close:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    frame.close:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
    frame.close:SetScript("OnClick", function() Clear() end)
    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -9)
    frame.status:SetJustifyH("RIGHT")
    frame.headerHeight = 28

    local font = CreateFont("SpeakStoneSubtitleFont")
    font:CopyFontObject(GameFontHighlightLarge)
    font:SetShadowOffset(1, -1)
    frame.font = font

    local clip = CreateFrame("Frame", nil, frame)
    clip:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -28)
    clip:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    clip:SetClipsChildren(true)
    frame.clip = clip

    local function Text(parent)
        local fs = parent:CreateFontString(nil, "OVERLAY")
        fs:SetFontObject(font)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetWordWrap(true)
        fs:SetWidth(WIDTH - 32)
        return fs
    end
    frame.text = Text(clip)
    -- Measures how many rows the words read so far take; never shown.
    frame.measure = Text(frame)
    frame.measure:SetAlpha(0)
    frame.measure:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -50)

    frame.progress = CreateFrame("StatusBar", nil, frame)
    frame.progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    frame.progress:SetHeight(2)
    frame.progress:SetMinMaxValues(0, 1)
    frame.progress:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 8)
    frame.progress:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 8)
    frame.track = frame.progress:CreateTexture(nil, "BACKGROUND")
    frame.track:SetAllPoints()

    addon.SubtitleApplyFont()
    ApplyPosition()
    ApplyLock()
    addon.SubtitlePaint()
end

-- The reading font and size (Fonts.lua): set on the bar's font object, then the
-- row height is measured from it, so tall-lettered fonts get the room they need.
function addon.SubtitleApplyFont()
    if not frame then
        return
    end
    local size = FontSize()
    local custom = addon.ApplyReadingFont and addon.ApplyReadingFont(frame.font, size, "")
    if not custom then
        frame.font:SetFont((GameFontHighlight:GetFont()), size, "")
    end
    local spacing = (custom and 5 or LINE_SPACING) + (size >= 26 and 2 or 0)
    frame.font:SetSpacing(spacing)
    frame.measure:SetText("A")
    local one = frame.measure:GetStringHeight() or 0
    frame.measure:SetText("A\nA")
    local two = frame.measure:GetStringHeight() or 0
    frame.linePitch = (two - one > 4) and (two - one) or (size + spacing)
    ApplyRows()
    if current then
        current.signature = nil
    end
end

-- Colours and background from the chosen theme (Theme.lua).
function addon.SubtitlePaint()
    if not frame then
        return
    end
    local theme = addon.Theme()
    local colours = addon.SubtitleColours()
    if colours.back then
        -- The player's own background colour: flat, over any theme art.
        if frame.ssSlice then frame.ssSlice:Hide() end
        frame.back:Show()
        frame.back:SetColorTexture(colours.back[1], colours.back[2], colours.back[3], 0.94)
    else
        local art = addon.ThemeSlice(frame, "bar")
        frame.back:SetShown(not art)
        addon.ThemeBackground(frame.back, false)
    end
    frame.lineTop:SetColorTexture(unpack(theme.line))
    frame.name:SetTextColor(unpack(colours.name))
    frame.title:SetTextColor(unpack(colours.sub))
    frame.status:SetTextColor(unpack(colours.accent))
    frame.text:SetTextColor(unpack(colours.text))
    frame.measure:SetTextColor(unpack(colours.text))
    frame.close.label:SetTextColor(unpack(colours.text))
    frame.close.label:SetShadowColor(0, 0, 0, colours.light and 0 or 1)
    frame.font:SetShadowColor(0, 0, 0, colours.light and 0 or 1)
    -- Dark ink on a light background: no drop shadow on the speaker, title or status either (it reads as bold).
    for _, fs in ipairs({ frame.name, frame.title, frame.status }) do
        fs:SetShadowColor(0, 0, 0, colours.light and 0 or 1)
        fs:SetShadowOffset(colours.light and 0 or 1, colours.light and 0 or -1)
    end
    frame.progress:SetStatusBarColor(colours.accent[1], colours.accent[2], colours.accent[3], 0.9)
    frame.track:SetColorTexture(colours.accent[1], colours.accent[2], colours.accent[3], 0.2)
    if current then
        current.signature = nil
    end
end
if addon.ThemeRegister then
    addon.ThemeRegister(function() addon.SubtitlePaint() end)
end

function Clear()
    current = nil
    lingerUntil = nil
    if frame then
        frame:Hide()
    end
    if driver then
        driver:Hide()
    end
end

local function HeaderText(sd)
    local name = type(sd.npcName) == "string" and sd.npcName ~= "" and sd.npcName or nil
    local title = type(sd.title) == "string" and sd.title ~= "" and sd.title or nil
    if sd.textType == "item" then
        name, title = title or "Book", sd.page and ("Page " .. sd.page) or nil
    end
    name = name or title or "SpeakStone"
    if title == name then
        title = nil
    end
    return name, title
end

local function Status(sd)
    local parts = {}
    if sd.waitingReason then
        parts[#parts + 1] = sd.waitingReason
    end
    local queued = addon.speechQueue and #addon.speechQueue or 0
    if queued > 0 then
        parts[#parts + 1] = "+" .. queued .. " waiting"
    end
    return table.concat(parts, "   ")
end

local function Refresh()
    local sd, words = current.sd, current.words
    local duration = tonumber(sd.duration)
    local index, fraction
    if sd.waitingReason then
        -- Held (in combat): the speaker and why, no words yet.
        index, fraction = 0, 0
    elseif duration and duration > 0 and sd.startedAt then
        local elapsed = math.max(0, GetTime() - sd.startedAt)
        index = addon.SubtitleWordAt(current.times, elapsed + LEAD)
        fraction = math.min(1, elapsed / duration)
        if elapsed >= duration then
            index = #words
        end
    else
        -- No length recorded: the words show whole, nothing to follow.
        index, fraction = #words, 0
    end
    frame.progress:SetValue(fraction)
    frame.status:SetText(Status(sd))
    local db = DB()
    local typeOut = db.subtitleTypeOut ~= false
    local highlight = db.subtitleHighlight ~= false
    -- With the clip's sentence timings, the sentence being spoken is lit whole (up to the word reached when typing out).
    local span = highlight and addon.SubtitleSpan(current.starts, index, words, typeOut) or nil
    local signature = index .. ":" .. tostring(typeOut) .. tostring(highlight) .. Rows() .. tostring(db.highlightColour)
        .. (span and ("s" .. span[1]) or "")
    if current.signature == signature then
        return
    end
    current.signature = signature
    frame.text:SetText(addon.SubtitleRender(words, index, typeOut, highlight, addon.HighlightCode(addon.SubtitleColours().light), span))
    frame.text:ClearAllPoints()
    -- Rows the words read so far take, to keep the row being read in view.
    frame.measure:SetText(addon.SubtitleRender(words, index, true, false))
    local rows = math.max(1, math.ceil(frame.measure:GetStringHeight() / LineHeight() - 0.01))
    if typeOut then
        -- Roll up: the newest row sits at the foot, what was read scrolls up.
        frame.text:SetPoint("BOTTOMLEFT", frame.clip, "BOTTOMLEFT", 0, 0)
    else
        -- Whole text, shown a page ahead: the row being read is the second.
        local keep = Rows() > 1 and 2 or 1
        frame.text:SetPoint("TOPLEFT", frame.clip, "TOPLEFT", 0, math.max(0, rows - keep) * LineHeight())
    end
end

local function Tick()
    if not current or (lingerUntil and GetTime() >= lingerUntil) then
        Clear()
        return
    end
    -- A preview plays its sample a few times and then goes away.
    local sd = current.sd
    if sd.previewLoops and sd.startedAt and GetTime() - sd.startedAt > sd.duration + 1.2 then
        if sd.previewLoops <= 1 then
            Clear()
            return
        end
        sd.previewLoops = sd.previewLoops - 1
        sd.startedAt = GetTime()
        current.signature = nil
    end
    -- The quest window already shows the text: by default the bar waits until it is gone.
    local hide = not DB().subtitlesWhileOpen and not sd.previewLoops and addon.SourceWindowOpen and addon.SourceWindowOpen(sd)
    frame:SetShown(not hide)
    Refresh()
end

local function Show(sd, words)
    Build()
    local duration = tonumber(sd.duration)
    current = { sd = sd, words = words, times = {} }
    -- The pack's sentence timings for this clip, if it has them and they fit this text; else the estimate.
    if duration and duration > 0 then
        current.times, current.starts = addon.SubtitleTiming(words, duration, sd.soundFile)
    end
    lingerUntil = nil
    local name, title = HeaderText(sd)
    frame.name:SetText(name)
    frame.title:SetText(title or "")
    if not driver then
        driver = CreateFrame("Frame")
        local acc = 0
        driver:SetScript("OnUpdate", function(_, elapsed)
            acc = acc + elapsed
            if acc >= UPDATE_INTERVAL then
                acc = 0
                Tick()
            end
        end)
    end
    driver:Show()
    frame:Show()
    Refresh()
end

function OpenMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        return
    end
    local db = DB()
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("SpeakStone subtitles")
        root:CreateButton("Stop", function()
            if current and addon.StopCurrentSound then
                addon.StopCurrentSound()
            end
            Clear()
        end)
        root:CreateButton("Replay", function()
            if current and addon.ReplaySound then
                addon.ReplaySound(current.sd)
            end
        end)
        local rows = root:CreateButton("Rows at once")
        for n = 1, 4 do
            rows:CreateRadio(tostring(n), function() return Rows() == n end,
                function() db.subtitleRows = n; ApplyRows(); if current then current.signature = nil end end)
        end
        root:CreateCheckbox("Type the words out",
            function() return db.subtitleTypeOut ~= false end,
            function() db.subtitleTypeOut = db.subtitleTypeOut == false; if current then current.signature = nil end end)
        root:CreateCheckbox("Highlight the word being read",
            function() return db.subtitleHighlight ~= false end,
            function() db.subtitleHighlight = db.subtitleHighlight == false; if current then current.signature = nil end end)
        local themes = root:CreateButton("Theme")
        for _, key in ipairs(addon.ThemeOrder) do
            themes:CreateRadio(addon.Themes[key].label, function() return addon.Theme().key == key end,
                function() addon.SetTheme(key) end)
        end
        root:CreateCheckbox("Lock position",
            function() return db.subtitleLocked end,
            function() db.subtitleLocked = not db.subtitleLocked; ApplyLock() end)
        root:CreateButton("Reset position and size", function()
            db.subtitlePos, db.subtitleScale = nil, nil
            ApplyPosition()
        end)
        root:CreateButton("SpeakStone settings...", function()
            if addon.ShowSettings then addon:ShowSettings() end
        end)
    end)
end

-- --------------------------------------------------------------------------
-- Notices
-- --------------------------------------------------------------------------

function addon.SubtitlesEnabled()
    return DB().showSubtitles == true
end

function addon.SubtitleSettingChanged(key)
    if not frame then
        return
    end
    if key == "subtitleLocked" then
        ApplyLock()
    elseif key == "subtitleRows" or key == "subtitleTypeOut" or key == "subtitleHighlight" then
        ApplyRows()
        if current then
            current.signature = nil
        end
    elseif key == "readingFont" or key == "subtitleFontSize" then
        addon.SubtitleApplyFont()
    elseif key == "subtitleBack" or key == "subtitleText" then
        addon.SubtitlePaint()
    elseif key == "highlightColour" then
        if current then
            current.signature = nil
        end
    elseif key == "showSubtitles" and not addon.SubtitlesEnabled() and not (current and current.sd.previewLoops) then
        Clear()
    end
end

function addon.SubtitleNotify(event, sd)
    if event == "start" or event == "wait" then
        Clear()
        if not addon.SubtitlesEnabled() or not sd or sd.preview then
            return
        end
        local words = addon.SubtitleWords(sd.text, addon.ClipNarrated and addon.ClipNarrated(sd.soundFile))
        if #words == 0 then
            return
        end
        Show(sd, words)
    elseif current and current.sd == sd then
        if event == "finish" then
            lingerUntil = GetTime() + LINGER_SECONDS
        elseif event == "stop" then
            Clear()
        end
    end
end

-- --------------------------------------------------------------------------
-- Previews: what each feature looks like, shown in the game from the settings
-- --------------------------------------------------------------------------

local SAMPLE_TEXT = "Greetings, traveler. The spirits here are restless, and dey ain't too happy about dat. "
    .. "Be careful in the tombs ahead, and listen for the whisper of the loa."
local SAMPLE_SECONDS = 14

-- The real subtitle bar, playing a sample line three times.
function addon.PreviewSubtitles()
    if addon.activeSound and addon.activeSound.isPlaying then
        print("|cff33ff99SpeakStone:|r narration is playing; try again once it has finished.")
        return
    end
    Clear()
    local sd = { text = SAMPLE_TEXT, duration = SAMPLE_SECONDS, startedAt = GetTime(), npcName = "Kinduru",
        title = "Preview", previewLoops = 3, textType = "description" }
    Show(sd, addon.SubtitleWords(sd.text))
end

local demo

local function BuildDemo()
    if demo then
        return
    end
    demo = CreateFrame("Frame", "SpeakStonePreviewWindow", UIParent)
    demo:SetSize(520, 160)
    demo:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    -- Above the settings window its button sits in: on the same layer it came up behind it, since clicking the
    -- button raises that window ("preview talking heads didn't work", owner, 2026-11-07).
    demo:SetFrameStrata("FULLSCREEN_DIALOG")
    demo:SetMovable(true)
    demo:EnableMouse(true)
    demo:RegisterForDrag("LeftButton")
    demo:SetScript("OnDragStart", demo.StartMoving)
    demo:SetScript("OnDragStop", demo.StopMovingOrSizing)
    demo:Hide()
    demo.back = demo:CreateTexture(nil, "BACKGROUND")
    demo.back:SetAllPoints()
    demo.title = demo:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    demo.title:SetPoint("TOPLEFT", demo, "TOPLEFT", 14, -10)
    demo.note = demo:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    demo.note:SetPoint("BOTTOMLEFT", demo, "BOTTOMLEFT", 14, 8)
    demo.text = demo:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    demo.text:SetPoint("TOPLEFT", demo, "TOPLEFT", 14, -34)
    demo.text:SetWidth(492)
    demo.text:SetJustifyH("LEFT")
    demo.text:SetJustifyV("TOP")
    demo.text:SetWordWrap(true)
    -- A faint themed X, as on the speech bar (Blizzard's red-and-gold one where the kit is missing).
    if addon.UIK and addon.UIK.Button then
        demo.close = addon.UIK.Button(demo, "X", 20, 20, function() demo:Hide() end)
        demo.close:SetPoint("TOPRIGHT", demo, "TOPRIGHT", -6, -6)
        demo.close:SetAlpha(0.55)
        demo.close:HookScript("OnEnter", function(self) self:SetAlpha(1) end)
        demo.close:HookScript("OnLeave", function(self) self:SetAlpha(0.55) end)
    else
        demo.close = CreateFrame("Button", nil, demo, "UIPanelCloseButton")
        demo.close:SetPoint("TOPRIGHT", demo, "TOPRIGHT", 2, 2)
        demo.close:SetScript("OnClick", function() demo:Hide() end)
    end
    demo:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
    -- Dialogue UI's own look (PreviewWindow "dialogue" with it installed): a quest title over a rule.
    demo.heading = demo:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    demo.heading:SetPoint("TOPLEFT", demo, "TOPLEFT", 30, -34)
    demo.rule = demo:CreateTexture(nil, "ARTWORK")
    demo.rule:SetHeight(1)
    demo.rule:SetPoint("TOPLEFT", demo.heading, "BOTTOMLEFT", 0, -8)
    demo.rule:SetPoint("RIGHT", demo, "RIGHT", -30, 0)
    -- The talking head's speaker (PreviewWindow "talkinghead"): the player's own head, talking, on the left.
    demo.model = CreateFrame("PlayerModel", nil, demo)
    demo.model:SetSize(104, 104)
    demo.model:SetPoint("LEFT", demo, "LEFT", 14, 0)
    demo.model:SetScript("OnModelLoaded", function(self)
        if addon.ApplySpeakerFace then addon.ApplySpeakerFace(self) end
        pcall(self.SetAnimation, self, 60)
    end)
    demo.model:SetScript("OnAnimFinished", function(self) pcall(self.SetAnimation, self, 60) end)
    demo.model:Hide()
end

-- A talking head as Blizzard draws one: the speaker's moving portrait on the left, the name in gold over white words,
-- on a dark band (owner, 2026-11-07: the plain dark box "looks totally wrong"; the speech bar is how it should look).
local function TalkingHeadLook()
    demo:SetSize(580, 136)
    demo:ClearAllPoints()
    -- Where Blizzard's talking heads come up: low in the middle, above the action bars.
    demo:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 190)
    -- In SpeakStone's theme, as the speech bar is drawn (owner, 2026-11-07: "needs to follow the theme").
    local art = addon.ThemeSlice(demo, "bar")
    demo.back:SetShown(not art)
    addon.ThemeBackground(demo.back, false)
    demo.heading:Hide()
    demo.rule:Hide()
    demo.model:Show()
    pcall(demo.model.ClearModel, demo.model)
    pcall(demo.model.SetUnit, demo.model, "player")
    demo.title:Show()
    demo.title:ClearAllPoints()
    demo.title:SetPoint("TOPLEFT", demo, "TOPLEFT", 132, -16)
    demo.title:SetFontObject("GameFontNormalLarge")
    demo.text:ClearAllPoints()
    demo.text:SetPoint("TOPLEFT", demo.title, "BOTTOMLEFT", 0, -6)
    demo.text:SetWidth(430)
    demo.note:ClearAllPoints()
    demo.note:SetPoint("BOTTOMLEFT", demo, "BOTTOMLEFT", 132, 10)
    demo.note:SetWidth(0)
end

-- Dialogue UI is installed: the sample is its window as near as SpeakStone can draw it -- its own frame art in its
-- current theme and its own fonts (read at run time, never copied), its size and its place on the right. Until
-- 2026-11-07 it was a flat brown box with game fonts, and the owner rightly said Dialogue UI does not look like that.
local function DialogueUILook(duiTheme)
    local dark = duiTheme == 2
    demo:SetSize(380, 330)
    demo:ClearAllPoints()
    demo:SetPoint("RIGHT", UIParent, "RIGHT", -220, 40)
    local drawn = addon.ThemeSlice(demo, "window", dark and "Theme_Dark" or "Theme_Brown", { 1, 1, 1 })
    demo.back:SetShown(not drawn)
    demo.back:SetColorTexture(0.82, 0.72, 0.55, 0.97)
    local function Use(fs, fontObject, fallback)
        fs:SetFontObject(fontObject or fallback)
        local r, g, b = (fontObject or _G[fallback]):GetTextColor()
        fs:SetTextColor(r, g, b)
        fs:SetShadowColor(0, 0, 0, dark and 1 or 0)
        return r, g, b
    end
    local r, g, b = Use(demo.heading, _G.DUIFont_Quest_Title_18, "GameFontNormalLarge")
    demo.heading:SetText("You Remind Me of the Bird")
    demo.heading:Show()
    demo.rule:SetColorTexture(r, g, b, 0.45)
    demo.rule:Show()
    Use(demo.text, _G.DUIFont_Quest_Paragraph, "GameFontHighlight")
    demo.text:ClearAllPoints()
    demo.text:SetPoint("TOPLEFT", demo.rule, "BOTTOMLEFT", 0, -14)
    demo.text:SetWidth(320)
    demo.title:Hide()
    demo.model:Hide()
    Use(demo.note, _G.DUIFont_Quest_Paragraph, "GameFontHighlightSmall")
    demo.note:SetFontObject("GameFontHighlightSmall")
    demo.note:ClearAllPoints()
    demo.note:SetPoint("BOTTOMLEFT", demo, "BOTTOMLEFT", 30, 26)
    demo.note:SetWidth(320)
    demo.note:SetJustifyH("LEFT")
    demo.note:SetText("Dialogue UI's window: the words type out as the voice reaches them and the one being read is lit. "
        .. "Drag to move.")
    return not dark
end

-- Back to the plain sample (no Dialogue UI, or the talking head).
local function PlainLook()
    demo:SetSize(520, 160)
    demo:ClearAllPoints()
    demo:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    if demo.ssSlice then demo.ssSlice:Hide() end
    demo.back:Show()
    demo.heading:Hide()
    demo.rule:Hide()
    demo.model:Hide()
    demo.title:Show()
    demo.title:ClearAllPoints()
    demo.title:SetPoint("TOPLEFT", demo, "TOPLEFT", 14, -10)
    demo.title:SetFontObject("GameFontNormal")
    demo.text:ClearAllPoints()
    demo.text:SetPoint("TOPLEFT", demo, "TOPLEFT", 14, -34)
    demo.text:SetWidth(492)
    demo.note:ClearAllPoints()
    demo.note:SetPoint("BOTTOMLEFT", demo, "BOTTOMLEFT", 14, 8)
    demo.note:SetWidth(0)
end

-- kind "dialogue": Dialogue UI's parchment page with its words typed out and lit.
-- kind "talkinghead": a talking head's text box, the word being read lit.
-- A sample that cannot be drawn says so in chat; with Lua errors hidden it used to look like a button that did
-- nothing.
local DrawPreview
function addon.PreviewWindow(kind)
    local ok, err = pcall(DrawPreview, kind)
    if not ok then
        print("|cffffd100SpeakStone:|r the preview could not be shown (" .. tostring(err) .. ").")
    end
end

function DrawPreview(kind)
    BuildDemo()
    local words = addon.SubtitleWords(SAMPLE_TEXT)
    local times = addon.SubtitleWordTimes(words, SAMPLE_SECONDS)
    local light = kind == "dialogue"
    local duiTheme = light and addon.DialogueUIThemeID and addon.DialogueUIThemeID()
    if duiTheme then
        light = DialogueUILook(duiTheme)
    end
    local paper = light      -- the highlight colour's background: light paper or dark
    if duiTheme then
        -- drawn above
    else
        if kind == "talkinghead" then TalkingHeadLook() else PlainLook() end
        if not (addon.ApplyReadingFont and addon.ApplyReadingFont(demo.text, 15, "")) then
            demo.text:SetFontObject("GameFontHighlight")
        end
    end
    if duiTheme then
        -- Colours and words set by DialogueUILook.
    elseif light then
        demo.back:SetColorTexture(0.82, 0.72, 0.55, 0.97)
        demo.title:SetText("Dialogue UI (preview)")
        demo.title:SetTextColor(0.25, 0.15, 0.08)
        demo.note:SetText("Words type out and the one being read is lit. Drag to move.")
        demo.note:SetTextColor(0.35, 0.25, 0.15)
        demo.text:SetTextColor(0.2, 0.12, 0.06)
    else
        -- The talking head, in the theme's ink (TalkingHeadLook drew the theme's background). `paper` only picks the
        -- highlight colour; `light` stays false, as a talking head lights words but does not type them out.
        local theme = addon.Theme()
        paper = theme.light == true
        demo.title:SetText("Kinduru")
        demo.title:SetTextColor(unpack(theme.title))
        demo.note:SetText("A talking head (preview): the word being read is lit as the line plays. Drag to move.")
        demo.note:SetTextColor(unpack(theme.sub))
        demo.text:SetTextColor(unpack(theme.text))
        for _, fs in ipairs({ demo.title, demo.note, demo.text }) do
            addon.ThemeShadow(fs)
        end
    end
    local started, loops = GetTime(), 3
    demo:Show()
    demo:SetScript("OnUpdate", function(self)
        local elapsed = GetTime() - started
        if elapsed > SAMPLE_SECONDS + 1.2 then
            loops = loops - 1
            if loops <= 0 then
                self:Hide()
                return
            end
            started, elapsed = GetTime(), 0
        end
        local index = addon.SubtitleWordAt(times, elapsed + LEAD)
        if elapsed >= SAMPLE_SECONDS then
            index = #words
        end
        local db = DB()
        local typeOut = light and db.subtitleTypeOut ~= false
        local highlight = (not light) or db.subtitleHighlight ~= false
        self.text:SetText(addon.SubtitleRender(words, index, typeOut, highlight, addon.HighlightCode(paper)))
    end)
end

-- --------------------------------------------------------------------------
-- Reading along in any text (the Guide's page, the speech frame): the spoken word lit in place
-- --------------------------------------------------------------------------
-- The text keeps its own line breaks; only the word being read, and the one before it, are wrapped in the
-- highlight colour. Stage directions ("<Kinduru nods.>") are shown but not read, so they take no time.

-- narrated (addon.ClipNarrated): the clip's narrator reads the directions, so they are spoken words too.
function addon.ReadTokens(plain, narrated)
    local tokens, spoken = {}, {}
    local inDirection = false
    for s, e in plain:gmatch("()%S+()") do
        local word = plain:sub(s, e - 1)
        local silent = inDirection
        if word:sub(1, 1) == "<" then inDirection, silent = true, true end
        if inDirection and word:sub(-1) == ">" then inDirection = false end
        if narrated then silent = false end
        tokens[#tokens + 1] = { s = s, e = e - 1 }
        if not silent then spoken[#spoken + 1] = #tokens end
    end
    local words = {}
    for i, t in ipairs(spoken) do words[i] = plain:sub(tokens[t].s, tokens[t].e) end
    return tokens, spoken, words
end

-- The paragraph (text between blank lines) holding position pos: its first and last character.
local function ParagraphAround(plain, pos)
    local first, last = 1, #plain
    for s, e in plain:gmatch("()\n[ \t]*\n()") do
        if e <= pos then
            first = e
        elseif s > pos then
            last = s - 1
            break
        end
    end
    return first, last
end

-- dimCode (fadeOtherParagraphs): the paragraphs other than the one being read in that colour. Those hold no
-- lit word, so no colour code is ever opened inside another.
function addon.LitText(plain, tokens, spoken, index, code, span, dimCode)
    local marks = {}
    for k = span and span[1] or math.max(1, index - 1), span and span[2] or index do
        if spoken[k] then marks[#marks + 1] = tokens[spoken[k]] end
    end
    if #marks == 0 then return plain end
    local first, last = 1, #plain
    if dimCode and spoken[index] then
        first, last = ParagraphAround(plain, tokens[spoken[index]].s)
    end
    local out, from = {}, first
    for _, t in ipairs(marks) do
        if t.s >= first and t.e <= last then
            out[#out + 1] = plain:sub(from, t.s - 1)
            out[#out + 1] = code .. plain:sub(t.s, t.e) .. "|r"
            from = t.e + 1
        end
    end
    out[#out + 1] = plain:sub(from, last)
    local before, after = plain:sub(1, first - 1), plain:sub(last + 1)
    if before ~= "" then table.insert(out, 1, dimCode .. before .. "|r") end
    if after ~= "" then out[#out + 1] = dimCode .. after .. "|r" end
    return table.concat(out)
end
