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
function addon.SubtitleWords(text)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    local inner = text:match("^%s*<(.*)>%s*$")
    if inner and not inner:find("[<>]") then
        text = inner
    else
        text = text:gsub("<[^<>]*>", " ")
    end
    local words = {}
    for word in text:gmatch("%S+") do
        words[#words + 1] = word
    end
    return words
end

local function Weight(word)
    local weight = #word + 2
    if word:find("[%.!%?][\"')%]]*$") then
        weight = weight + 8
    elseif word:find("[,;:][\"')]*$") then
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

-- The text to draw for a reading position. typeOut: only the words reached.
-- highlight: the word being read and the one before it in gold.
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

function addon.SubtitleRender(words, index, typeOut, highlight, code)
    code = code or GOLD
    local parts = {}
    for k = 1, #words do
        if typeOut and k > index then
            break
        end
        local word = words[k]
        if highlight and index > 0 and (k == index or k == index - 1) then
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
    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -9)
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
    local signature = index .. ":" .. tostring(typeOut) .. tostring(highlight) .. Rows() .. tostring(db.highlightColour)
    if current.signature == signature then
        return
    end
    current.signature = signature
    frame.text:SetText(addon.SubtitleRender(words, index, typeOut, highlight, addon.HighlightCode(addon.SubtitleColours().light)))
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
    current = {
        sd = sd,
        words = words,
        times = (duration and duration > 0) and addon.SubtitleWordTimes(words, duration) or {},
    }
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
        local words = addon.SubtitleWords(sd.text)
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
    demo:SetFrameStrata("DIALOG")
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
    demo.close = CreateFrame("Button", nil, demo, "UIPanelCloseButton")
    demo.close:SetPoint("TOPRIGHT", demo, "TOPRIGHT", 2, 2)
    demo.close:SetScript("OnClick", function() demo:Hide() end)
    demo:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
end

-- kind "dialogue": Dialogue UI's parchment page with its words typed out and lit.
-- kind "talkinghead": a talking head's text box, the word being read lit.
function addon.PreviewWindow(kind)
    BuildDemo()
    local words = addon.SubtitleWords(SAMPLE_TEXT)
    local times = addon.SubtitleWordTimes(words, SAMPLE_SECONDS)
    local light = kind == "dialogue"
    if not (addon.ApplyReadingFont and addon.ApplyReadingFont(demo.text, 15, "")) then
        demo.text:SetFontObject("GameFontHighlight")
    end
    if light then
        demo.back:SetColorTexture(0.82, 0.72, 0.55, 0.97)
        demo.title:SetText("Dialogue UI (preview)")
        demo.title:SetTextColor(0.25, 0.15, 0.08)
        demo.note:SetText("Words type out and the one being read is lit. Drag to move.")
        demo.note:SetTextColor(0.35, 0.25, 0.15)
        demo.text:SetTextColor(0.2, 0.12, 0.06)
    else
        demo.back:SetColorTexture(0.04, 0.06, 0.09, 0.92)
        demo.title:SetText("Talking head (preview)")
        demo.title:SetTextColor(0.94, 0.82, 0.48)
        demo.note:SetText("The word being read is lit as the line plays. Drag to move.")
        demo.note:SetTextColor(0.7, 0.72, 0.75)
        demo.text:SetTextColor(1, 1, 1)
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
        self.text:SetText(addon.SubtitleRender(words, index, typeOut, highlight, addon.HighlightCode(light)))
    end)
end

-- --------------------------------------------------------------------------
-- Reading along in any text (the Guide's page, the speech frame): the spoken word lit in place
-- --------------------------------------------------------------------------
-- The text keeps its own line breaks; only the word being read, and the one before it, are wrapped in the
-- highlight colour. Stage directions ("<Kinduru nods.>") are shown but not read, so they take no time.

function addon.ReadTokens(plain)
    local tokens, spoken = {}, {}
    local inDirection = false
    for s, e in plain:gmatch("()%S+()") do
        local word = plain:sub(s, e - 1)
        local silent = inDirection
        if word:sub(1, 1) == "<" then inDirection, silent = true, true end
        if inDirection and word:sub(-1) == ">" then inDirection = false end
        tokens[#tokens + 1] = { s = s, e = e - 1 }
        if not silent then spoken[#spoken + 1] = #tokens end
    end
    local words = {}
    for i, t in ipairs(spoken) do words[i] = plain:sub(tokens[t].s, tokens[t].e) end
    return tokens, spoken, words
end

function addon.LitText(plain, tokens, spoken, index, code)
    local marks = {}
    for k = math.max(1, index - 1), index do
        if spoken[k] then marks[#marks + 1] = tokens[spoken[k]] end
    end
    if #marks == 0 then return plain end
    local out, from = {}, 1
    for _, t in ipairs(marks) do
        out[#out + 1] = plain:sub(from, t.s - 1)
        out[#out + 1] = code .. plain:sub(t.s, t.e) .. "|r"
        from = t.e + 1
    end
    out[#out + 1] = plain:sub(from)
    return table.concat(out)
end
