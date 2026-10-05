local addonName, addon = ...

-- The speech frame: who is talking, what they are saying, and pause / stop /
-- replay, for narration that carries on after its window has closed -- the
-- player walked away, or the quest was auto-accepted (owner, 2026-10-05).
-- The cinematic-bar layout from docs/npc-speech-frame-mockups.html. The
-- text is shown whole, scrolled with the mouse wheel; following the voice
-- line by line is for later.
--
-- Driven by three notices from the playback code in SpeakStone_Main.lua --
-- "start", "finish" and "stop" -- and by the clip's own soundData, which
-- carries the text, title and NPC captured at play time.
--
-- Two limits are the client's:
-- * Nothing reports where a clip is. The timer is worked out from when it
--   started (soundData.startedAt) and its length (SoundLengths).
-- * PlaySoundFile has no pause and cannot start part-way into a file. Pause
--   stops the clip; Resume plays it again from the top.

local SIZES = {
    { key = "small", label = "Small", scale = 0.8 },
    { key = "medium", label = "Medium", scale = 1.0 },
    { key = "large", label = "Large", scale = 1.25 },
}

local WIDTH, HEIGHT = 660, 112
local PORTRAIT = 72
local TEXT_LINES = 4
-- How long the frame stays up after a line ends on its own.
local LINGER_SECONDS = 2
local UPDATE_INTERVAL = 0.1
local DEFAULT_POINT = { "BOTTOM", "BOTTOM", 0, 190 }

local PREVIEW_TEXT = "This is the SpeakStone speech frame. It appears when you walk away from a quest giver while "
    .. "narration is still going, or when a quest is auto-accepted, so you can read along and pause or stop the "
    .. "voice. Drag it where you want it. Right-click it, or use the gear, to change its size, lock it in place or "
    .. "reset its position. Scroll with the mouse wheel when a quest has more text than fits. Close it with the X "
    .. "or Stop when you are done."

-- --------------------------------------------------------------------------
-- State
-- --------------------------------------------------------------------------

local frame, driver
local current          -- the soundData on show
local paused = false
local pausedElapsed = 0
local lingerUntil = nil
local pausing = false  -- our own Pause is the one calling StopCurrentSound

local function DB()
    return SpeakStone_MainDB or {}
end

local function Readable(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end
    if addon.IsSecret and addon.IsSecret(value) then
        return nil
    end
    return value
end

local function SizeScale()
    local key = DB().speechSize or "medium"
    for _, size in ipairs(SIZES) do
        if size.key == key then
            return size.scale
        end
    end
    return 1
end

local function Duration(sd)
    local duration = tonumber(sd.duration)
    if duration and duration > 0 then
        return duration
    end
    return nil
end

local function Elapsed(sd)
    if paused then
        return pausedElapsed
    end
    if not sd.startedAt then
        return 0
    end
    local elapsed = math.max(0, GetTime() - sd.startedAt)
    if sd.preview then
        elapsed = elapsed % sd.duration
    end
    return elapsed
end

local function Clock(seconds)
    seconds = math.max(0, math.floor(seconds))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Whether the window the narration came from is still on screen, in which
-- case that window is already showing the text.
local function Shown(f)
    return f and f.IsShown and f:IsShown()
end

local function SourceWindowOpen(sd)
    if sd.preview then
        return false
    end
    if Shown(_G.ImmersionFrame) or Shown(_G.DUIQuestFrame) then
        return true
    end
    if sd.textType == "item" then
        return Shown(ItemTextFrame) or Shown(_G.DUIBookFrame)
    elseif sd.textType == "gossip" then
        return Shown(GossipFrame)
    end
    return Shown(QuestFrame) or (QuestMapFrame and QuestMapFrame:IsVisible())
end

-- --------------------------------------------------------------------------
-- The frame
-- --------------------------------------------------------------------------

local function SavePosition()
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    local scale = frame:GetScale()
    -- Stored in UIParent units, so changing the size keeps it in place.
    SpeakStone_MainDB.speechFramePos = { point, relativePoint, x * scale, y * scale }
end

local function ApplyPosition()
    local pos = DB().speechFramePos or DEFAULT_POINT
    local scale = SizeScale()
    frame:SetScale(scale)
    frame:ClearAllPoints()
    frame:SetPoint(pos[1], UIParent, pos[2], pos[3] / scale, pos[4] / scale)
end

local function MakeButton(parent, label, width, onClick, tooltip)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 20)
    button:SetText(label)
    button:SetNormalFontObject("GameFontNormalSmall")
    button:SetHighlightFontObject("GameFontHighlightSmall")
    button:SetDisabledFontObject("GameFontDisableSmall")
    button:SetScript("OnClick", onClick)
    if tooltip then
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return button
end

local Pause, Resume, StopNarration, Replay, Dismiss, OpenMenu

local function Build()
    if frame then
        return
    end

    frame = CreateFrame("Frame", "SpeakStoneSpeechFrame", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not DB().speechFrameLocked then
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
    frame:Hide()

    -- A dark band fading out to the right, gold hairlines top and bottom.
    local band = frame:CreateTexture(nil, "BACKGROUND")
    band:SetAllPoints()
    band:SetColorTexture(1, 1, 1, 1)
    band:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0.85), CreateColor(0, 0, 0, 0.45))
    local lineTop = frame:CreateTexture(nil, "BORDER")
    lineTop:SetPoint("TOPLEFT")
    lineTop:SetPoint("TOPRIGHT")
    lineTop:SetHeight(1)
    lineTop:SetColorTexture(0.94, 0.76, 0.35, 0.4)
    local lineBottom = frame:CreateTexture(nil, "BORDER")
    lineBottom:SetPoint("BOTTOMLEFT")
    lineBottom:SetPoint("BOTTOMRIGHT")
    lineBottom:SetHeight(1)
    lineBottom:SetColorTexture(0.94, 0.76, 0.35, 0.25)

    frame.portrait = frame:CreateTexture(nil, "ARTWORK")
    frame.portrait:SetSize(PORTRAIT, PORTRAIT)
    frame.portrait:SetPoint("LEFT", frame, "LEFT", 12, 0)
    local mask = frame:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(frame.portrait)
    frame.portrait:AddMaskTexture(mask)

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetSize(22, 22)
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    frame.close:SetScript("OnClick", function() Dismiss() end)

    -- Controls, right to left from the close button.
    local controls = CreateFrame("Frame", nil, frame)
    controls:SetSize(1, 20)
    controls:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, -8)
    frame.controls = controls
    controls.gear = CreateFrame("Button", nil, controls)
    controls.gear:SetSize(18, 18)
    controls.gear:SetPoint("RIGHT", controls, "RIGHT", 0, 0)
    controls.gear:SetNormalTexture("Interface\\WorldMap\\Gear_64Grey")
    controls.gear:SetHighlightTexture("Interface\\WorldMap\\Gear_64Grey", "ADD")
    controls.gear:SetScript("OnClick", function(self) OpenMenu(self) end)
    controls.gear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Size and position", 1, 1, 1)
        GameTooltip:AddLine("Also right-click the frame.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    controls.gear:SetScript("OnLeave", function() GameTooltip:Hide() end)
    controls.time = controls:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    controls.time:SetPoint("RIGHT", controls.gear, "LEFT", -8, 0)
    controls.time:SetTextColor(0.75, 0.72, 0.65)
    controls.replay = MakeButton(controls, "Replay", 56, function() Replay() end, "Hear the line again from the start.")
    controls.replay:SetPoint("RIGHT", controls.time, "LEFT", -8, 0)
    controls.stop = MakeButton(controls, "Stop", 46, function() StopNarration() end, "Stop the narration and close.")
    controls.stop:SetPoint("RIGHT", controls.replay, "LEFT", -4, 0)
    controls.pause = MakeButton(controls, "Pause", 60, function()
        if paused then Resume() else Pause() end
    end, "Pause the narration. The game cannot pick a clip up part-way, so Resume starts the line again.")
    controls.pause:SetPoint("RIGHT", controls.stop, "LEFT", -4, 0)

    frame.name = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    frame.name:SetPoint("TOPLEFT", frame.portrait, "TOPRIGHT", 14, 6)
    frame.name:SetPoint("RIGHT", controls.pause, "LEFT", -10, 0)
    frame.name:SetJustifyH("LEFT")
    frame.name:SetWordWrap(false)

    -- The text, whole, in a mouse-wheel scroll area TEXT_LINES tall.
    local textFont = CreateFont("SpeakStoneSpeechTextFont")
    textFont:CopyFontObject(GameFontHighlight)
    textFont:SetFont((GameFontHighlight:GetFont()), 13, "")
    textFont:SetSpacing(2)
    local lineHeight = 13 + 2

    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -6)
    scroll:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    scroll:SetHeight(lineHeight * TEXT_LINES)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local target = self:GetVerticalScroll() - delta * lineHeight * 2
        self:SetVerticalScroll(math.max(0, math.min(target, self:GetVerticalScrollRange())))
    end)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    frame.scroll = scroll
    frame.scrollChild = child

    frame.text = child:CreateFontString(nil, "ARTWORK")
    frame.text:SetFontObject(textFont)
    frame.text:SetPoint("TOPLEFT")
    frame.text:SetJustifyH("LEFT")
    frame.text:SetJustifyV("TOP")
    frame.text:SetWordWrap(true)

    frame.progress = CreateFrame("StatusBar", nil, frame)
    frame.progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    frame.progress:SetStatusBarColor(0.94, 0.76, 0.35, 0.9)
    frame.progress:SetHeight(2)
    frame.progress:SetMinMaxValues(0, 1)
    frame.progress:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -4)
    frame.progress:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
    local track = frame.progress:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(1, 1, 1, 0.1)

    ApplyPosition()
end

local function SetPortrait(sd)
    local done = false
    if sd.npcGUID and UnitExists("npc") then
        pcall(function()
            if UnitGUID("npc") == sd.npcGUID then
                SetPortraitTexture(frame.portrait, "npc")
                done = true
            end
        end)
    end
    if not done then
        frame.portrait:SetTexture(sd.textType == "item" and "Interface\\Icons\\INV_Misc_Book_09"
            or "Interface\\Icons\\INV_Misc_Note_01")
    end
end

local function HeaderText(sd)
    local name = Readable(sd.npcName)
    local title = Readable(sd.title)
    if sd.textType == "item" then
        name, title = title or "Book", sd.page and ("Page " .. sd.page) or nil
    end
    name = name or title or "SpeakStone"
    if title and title ~= name then
        return name .. "  |cff9d9d9d" .. title .. "|r"
    end
    return name
end

-- Text and header, once per clip.
local function Fill(sd)
    frame.name:SetText(HeaderText(sd))
    local text = Readable(sd.text)
    if text then
        text = text:gsub("\r", ""):gsub("\n%s*\n+", "\n\n")
    else
        text = "|cff9d9d9d(No text for this line.)|r"
    end
    local width = frame.scroll:GetWidth()
    if not width or width <= 0 then
        width = WIDTH - PORTRAIT - 12 - 14 - 16
    end
    frame.text:SetWidth(width)
    frame.text:SetText(text)
    frame.scrollChild:SetSize(width, math.max(1, frame.text:GetStringHeight()))
    frame.scroll:SetVerticalScroll(0)
    frame.filledFor = sd
end

local function Refresh()
    local sd = current
    if frame.filledFor ~= sd then
        Fill(sd)
    end
    local elapsed = Elapsed(sd)
    local duration = Duration(sd)
    if duration then
        frame.progress:SetValue(math.min(1, elapsed / duration))
        frame.controls.time:SetText(Clock(math.min(elapsed, duration)) .. " / " .. Clock(duration))
    else
        frame.progress:SetValue(0)
        frame.controls.time:SetText(Clock(elapsed))
    end
    frame.controls.pause:SetText(paused and "Resume" or "Pause")
end

local function ShouldShow(sd)
    if not sd then
        return false
    end
    if sd.preview then
        return true
    end
    if not DB().showSpeechFrame or sd.frameDismissed then
        return false
    end
    if TalkingHeadFrame and TalkingHeadFrame:IsShown() then
        return false
    end
    if SourceWindowOpen(sd) then
        return false
    end
    if paused then
        return true
    end
    if lingerUntil then
        return frame:IsShown() and GetTime() < lingerUntil
    end
    return sd.isPlaying
end

local function Clear()
    current = nil
    paused = false
    lingerUntil = nil
    if frame then
        frame:Hide()
    end
    if driver then
        driver:Hide()
    end
end

local function Tick()
    if not current or (lingerUntil and GetTime() >= lingerUntil) then
        Clear()
        return
    end
    if ShouldShow(current) then
        Refresh()
        frame:Show()
    else
        frame:Hide()
    end
end

local function Watch(sd)
    Build()
    current = sd
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
    Tick()
end

-- --------------------------------------------------------------------------
-- Controls
-- --------------------------------------------------------------------------

function Pause()
    local sd = current
    if not sd or paused then
        return
    end
    pausedElapsed = Elapsed(sd)
    paused = true
    if not sd.preview then
        pausing = true
        addon.StopCurrentSound()
        pausing = false
    end
    Tick()
end

function Resume()
    local sd = current
    if not sd or not paused then
        return
    end
    paused = false
    if sd.preview then
        sd.startedAt = GetTime() - pausedElapsed
    else
        -- From the top: see the note at the head of the file.
        addon.ReplaySound(sd)
    end
    Tick()
end

function Replay()
    local sd = current
    if not sd then
        return
    end
    paused = false
    lingerUntil = nil
    if sd.preview then
        sd.startedAt = GetTime()
    else
        addon.ReplaySound(sd)
    end
    Tick()
end

function StopNarration()
    local sd = current
    if sd and not sd.preview then
        if sd.textType == "item" and addon.StopBook then
            addon.StopBook()
        elseif addon.activeSound == sd then
            addon.StopCurrentSound()
        end
    end
    Clear()
end

-- Close the frame but let the line finish. A paused line has nothing left
-- to finish, so closing it is the same as Stop.
function Dismiss()
    if current and (paused or current.preview) then
        StopNarration()
        return
    end
    if current then
        current.frameDismissed = true
    end
    if frame then
        frame:Hide()
    end
end

-- Global on purpose: Bindings.xml calls it by name.
function SpeakStone_TogglePause()
    if paused then
        Resume()
        return
    end
    local sd = addon.activeSound
    if sd and (sd.isPlaying or sd.nextSoundTimer) then
        if current ~= sd then
            Watch(sd)
        end
        Pause()
    end
end

-- /ss frame: a sample line to place and size the frame with.
function addon.SpeechFramePreview()
    if current and current.preview then
        Clear()
        return
    end
    if addon.activeSound and addon.activeSound.isPlaying then
        print("|cff33ff99SpeakStone:|r narration is playing; try again once it has finished.")
        return
    end
    paused = false
    lingerUntil = nil
    Build()
    local sd = {
        preview = true,
        text = PREVIEW_TEXT,
        npcName = "SpeakStone",
        title = "Preview",
        duration = 24,
        startedAt = GetTime(),
    }
    SetPortrait(sd)
    Watch(sd)
end

-- --------------------------------------------------------------------------
-- Menu
-- --------------------------------------------------------------------------

function OpenMenu(owner)
    Build()
    local db = SpeakStone_MainDB
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        -- No menu API on this client: step through the sizes instead.
        local index = 1
        for i, size in ipairs(SIZES) do
            if size.key == db.speechSize then index = i end
        end
        db.speechSize = SIZES[index % #SIZES + 1].key
        ApplyPosition()
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("SpeakStone speech frame")
        local sizeMenu = root:CreateButton("Size")
        for _, size in ipairs(SIZES) do
            sizeMenu:CreateRadio(size.label,
                function() return (db.speechSize or "medium") == size.key end,
                function() db.speechSize = size.key; ApplyPosition() end)
        end
        root:CreateCheckbox("Lock position",
            function() return db.speechFrameLocked end,
            function() db.speechFrameLocked = not db.speechFrameLocked end)
        root:CreateButton("Reset position", function()
            db.speechFramePos = nil
            ApplyPosition()
        end)
        root:CreateDivider()
        root:CreateCheckbox("Auto-accept quests",
            function() return db.autoAcceptQuests end,
            function() db.autoAcceptQuests = not db.autoAcceptQuests end)
        root:CreateButton("SpeakStone settings...", function()
            if addon.ShowSettings then addon:ShowSettings() end
        end)
        root:CreateButton("Turn the speech frame off", function()
            db.showSpeechFrame = false
            print("|cff33ff99SpeakStone:|r speech frame off. Turn it back on in /ss.")
            Clear()
        end)
    end)
end

-- --------------------------------------------------------------------------
-- Notices from the playback code
-- --------------------------------------------------------------------------

function addon.SpeechFrameNotify(event, sd)
    if event == "start" then
        if current and current.preview then
            Clear()
        end
        paused = false
        lingerUntil = nil
        Build()
        -- Only on a fresh clip: a replay after walking away has no NPC to
        -- take the portrait from, and keeps the one it had.
        if frame.portraitFor ~= sd then
            SetPortrait(sd)
            frame.portraitFor = sd
        end
        Watch(sd)
    elseif sd ~= current then
        return
    elseif event == "finish" then
        lingerUntil = GetTime() + LINGER_SECONDS
        Tick()
    elseif event == "stop" then
        if pausing then
            return
        end
        Clear()
    end
end
