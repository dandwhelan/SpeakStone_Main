local addonName, addon = ...

-- First-start tutorial and premade settings profiles. Shown at login until the
-- player closes it (tutorialVersion), and again on demand with /ss tutorial or the
-- Profiles button in the settings window.

-- Bump to show the tutorial once more to everyone, e.g. after adding a page.
-- Replaces the old tutorialDone flag, which is ignored so players who had it
-- set without ever seeing the tutorial get it once.
-- 2: the speech bar page. Players who saw version 1 get a short "what's
-- new" run instead of the whole tutorial again.
local TUTORIAL_VERSION = 2

local CURSEFORGE_URL ="https://www.curseforge.com/members/dandwhelan/projects"
local WEBSITE_URL = "https://speakstone.beanw.co.uk"

-- Every profile sets every playback option, so picking one gives the same
-- result whatever the player had before. Interface and capture options are
-- left alone except where the profile is about them.
local PROFILES = {
    {
        key = "full",
        name = "Full Narration",
        recommended = true,
        description = "Everything read aloud: quests, NPC greetings and books. Blizzard's own voice lines are silenced so nothing talks over SpeakStone.",
        settings = {
            autoPlayEnabled = true, autoPlayQuests = true, autoPlayGossip = true, autoPlayItemText = true,
            autoPlayInQuestMap = false, muteGossip = true, yieldToNPCVoice = true,
            stopDialogueOnClose = false, showDebugMessages = false, harvestEnabled = true,
            autoPlayDelay = 1.0,
            showSpeechFrame = true, speechAutoScroll = true, speechFitText = false, queueQuestSpeech = false,
        },
    },
    {
        key = "story",
        name = "Story Only",
        description = "Quests and books are read; passing NPC greetings stay quiet. Quests you pick up in a row wait their turn instead of cutting each other off.",
        settings = {
            autoPlayEnabled = true, autoPlayQuests = true, autoPlayGossip = false, autoPlayItemText = true,
            autoPlayInQuestMap = false, muteGossip = true, yieldToNPCVoice = true,
            stopDialogueOnClose = false, showDebugMessages = false, harvestEnabled = true,
            autoPlayDelay = 1.0,
            showSpeechFrame = true, speechAutoScroll = true, speechFitText = false, queueQuestSpeech = true,
        },
    },
    {
        key = "subtitles",
        name = "Subtitles",
        description = "Full narration with a speech bar for reading along: extra large, the whole passage shown, quests queued. Good if you're hard of hearing or play with the sound low.",
        settings = {
            autoPlayEnabled = true, autoPlayQuests = true, autoPlayGossip = true, autoPlayItemText = true,
            autoPlayInQuestMap = false, muteGossip = true, yieldToNPCVoice = true,
            stopDialogueOnClose = false, showDebugMessages = false, harvestEnabled = true,
            autoPlayDelay = 1.0,
            showSpeechFrame = true, speechAutoScroll = true, speechFitText = true, queueQuestSpeech = true,
            speechSize = "xlarge",
        },
    },
    {
        key = "blizzard",
        name = "Blizzard First",
        description = "Blizzard's own voice acting plays where it exists, and SpeakStone waits for it before filling the silence.",
        settings = {
            autoPlayEnabled = true, autoPlayQuests = true, autoPlayGossip = true, autoPlayItemText = true,
            autoPlayInQuestMap = false, muteGossip = false, yieldToNPCVoice = true,
            stopDialogueOnClose = false, showDebugMessages = false, harvestEnabled = true,
            autoPlayDelay = 1.5,
            showSpeechFrame = true, speechAutoScroll = true, speechFitText = false, queueQuestSpeech = false,
        },
    },
    {
        key = "manual",
        name = "Manual",
        description = "Nothing plays on its own. Press the Read Quest button when you want a quest read. Narration stops when you close the window.",
        settings = {
            autoPlayEnabled = false, autoPlayQuests = true, autoPlayGossip = true, autoPlayItemText = true,
            autoPlayInQuestMap = false, muteGossip = true, yieldToNPCVoice = true,
            stopDialogueOnClose = true, showDebugMessages = false, harvestEnabled = false,
            showQuestButton = true, autoPlayDelay = 1.0,
            showSpeechFrame = false, speechAutoScroll = true, speechFitText = false, queueQuestSpeech = false,
        },
    },
    {
        key = "helper",
        name = "Helper / Tester",
        description = "Full narration plus debug messages in chat and text capture on, for reporting problems and helping voice missing quests.",
        settings = {
            autoPlayEnabled = true, autoPlayQuests = true, autoPlayGossip = true, autoPlayItemText = true,
            autoPlayInQuestMap = true, muteGossip = true, yieldToNPCVoice = true,
            stopDialogueOnClose = false, showDebugMessages = true, harvestEnabled = true,
            autoPlayDelay = 1.0,
            showSpeechFrame = true, speechAutoScroll = true, speechFitText = false, queueQuestSpeech = false,
        },
    },
}
addon.PROFILES = PROFILES

local function DB()
    return SpeakStone_MainDB
end

local function ApplyProfile(key)
    local db = DB()
    if not db then return end
    for _, profile in ipairs(PROFILES) do
        if profile.key == key then
            for option, value in pairs(profile.settings) do
                db[option] = value
            end
            db.profile = key
            if addon.SpeechSettingChanged then
                for _, option in ipairs({ "speechFitText", "queueQuestSpeech", "speechSize" }) do
                    addon.SpeechSettingChanged(option)
                end
            end
            if addon.UpdateMinimapButtonVisibility then addon.UpdateMinimapButtonVisibility() end
            if addon.UpdateQuestButtonVisibility then addon.UpdateQuestButtonVisibility() end
            -- The settings window reads everything in OnShow; if it is open,
            -- cycle it so the checkboxes and slider show the new values.
            local window = addon.settingsWindow
            if window and window:IsShown() then
                window:Hide()
                window:Show()
            end
            print("|cff33ff99SpeakStone:|r profile set to " .. profile.name .. ". Fine-tune it any time with /ss.")
            return true
        end
    end
end
addon.ApplyProfile = ApplyProfile

local function ProfileName(key)
    for _, profile in ipairs(PROFILES) do
        if profile.key == key then return profile.name end
    end
end

-- --------------------------------------------------------------------------
-- Test clip: any clip from an installed pack.
-- --------------------------------------------------------------------------
local testHandle
local function PlayTestClip()
    if testHandle then
        StopSound(testHandle)
        testHandle = nil
    end
    for packName, soundLengths in pairs(addon.soundSources or {}) do
        if packName ~= addonName and type(soundLengths) == "table" then
            for file in pairs(soundLengths) do
                local _, handle = PlaySoundFile("Interface\\AddOns\\" .. packName .. "\\Sounds\\" .. file, "Dialog")
                testHandle = handle
                return true
            end
        end
    end
    return false
end

local function HasAnyAudioPack()
    for packName, soundLengths in pairs(addon.soundSources or {}) do
        if packName ~= addonName and type(soundLengths) == "table" and next(soundLengths) then
            return true
        end
    end
    return false
end

-- --------------------------------------------------------------------------
-- The window
-- --------------------------------------------------------------------------
local WIDTH, HEIGHT = 560, 440
local frame, pages, pageIndex
-- The pages this run walks through, as indices into pages: the whole
-- tutorial, or the short "what's new" run for players who saw an older one.
local order, pageByName
local ShowPage
local FULL_ORDER = { "welcome", "profiles", "packs", "speech", "controls", "contribute", "done" }
local WHATSNEW_ORDER = { "whatsnew", "speech", "done" }
local selectedProfile

local function Text(parent, template, width)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    if width then fs:SetWidth(width) end
    return fs
end

local function CopyBox(parent, url, width)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 22)
    box:SetAutoFocus(false)
    box:SetText(url)
    box:SetCursorPosition(0)
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(url) self:HighlightText() end
    end)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

local function NewPage(name)
    local page = CreateFrame("Frame", nil, frame)
    page:SetPoint("TOPLEFT", 20, -34)
    page:SetPoint("BOTTOMRIGHT", -20, 50)
    page:Hide()
    table.insert(pages, page)
    pageByName[name] = #pages
    return page
end

local function SetOrder(names)
    order = {}
    for _, name in ipairs(names) do
        table.insert(order, pageByName[name])
    end
end

local function BuildWelcome()
    local page = NewPage("welcome")
    local title = Text(page, "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 0, -10)
    title:SetText("Welcome to SpeakStone")
    local body = Text(page, "GameFontHighlight", WIDTH - 40)
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -16)
    body:SetSpacing(4)
    body:SetText("SpeakStone reads quests, NPC greetings and books aloud, with voices similar to the in-game NPCs.\n"
        .. "Unofficial; not affiliated with Blizzard Entertainment.\n\n"
        .. "This quick setup takes about a minute:\n"
        .. "  1. Pick how much you want narrated.\n"
        .. "  2. Check your audio packs.\n"
        .. "  3. Set up the speech bar.\n"
        .. "  4. Learn where the controls are.\n"
        .. "  5. See how you can help the project.\n\n"
        .. "You can reopen it any time with |cffffd100/ss tutorial|r.")
end

local function BuildProfiles()
    local page = NewPage("profiles")
    local title = Text(page, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText("Pick a profile")
    local hint = Text(page, "GameFontHighlightSmall", WIDTH - 40)
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    hint:SetText("Every option can still be changed afterwards in /ss. Skip this page and |cff00ff00Full Narration|r is used on a new install; otherwise your current settings are kept.")

    local buttons = {}
    local function Refresh()
        for _, button in ipairs(buttons) do
            if button.key == selectedProfile then
                button.bg:SetColorTexture(0.25, 0.4, 0.15, 0.9)
            else
                button.bg:SetColorTexture(0.09, 0.08, 0.07, 0.85)
            end
        end
    end
    page:SetScript("OnShow", function()
        selectedProfile = selectedProfile or DB().profile
        Refresh()
    end)

    local y = -40
    for _, profile in ipairs(PROFILES) do
        local button = CreateFrame("Button", nil, page)
        button:SetPoint("TOPLEFT", 0, y)
        button:SetSize(WIDTH - 40, 48)
        button.key = profile.key
        button.bg = button:CreateTexture(nil, "BACKGROUND")
        button.bg:SetAllPoints()
        local hl = button:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)

        local name = Text(button, "GameFontNormal")
        name:SetPoint("TOPLEFT", 8, -6)
        name:SetText(profile.name .. (profile.recommended and "  |cff00ff00(recommended)|r" or ""))
        local desc = Text(button, "GameFontHighlightSmall", WIDTH - 60)
        desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
        desc:SetText(profile.description)

        button:SetScript("OnClick", function()
            selectedProfile = profile.key
            ApplyProfile(profile.key)
            Refresh()
        end)
        table.insert(buttons, button)
        y = y - 52
    end
end

local function BuildPacks()
    local page = NewPage("packs")
    local title = Text(page, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText("Audio packs")
    local status = Text(page, "GameFontHighlight", WIDTH - 40)
    status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    status:SetSpacing(4)

    local linkLabel = Text(page, "GameFontNormalSmall")
    linkLabel:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -16)
    linkLabel:SetText("All SpeakStone addons on CurseForge (Ctrl+C to copy):")
    local box = CopyBox(page, CURSEFORGE_URL, WIDTH - 60)
    box:SetPoint("TOPLEFT", linkLabel, "BOTTOMLEFT", 6, -6)

    local test = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    test:SetSize(160, 24)
    test:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -18)
    test:SetText("Test a voice")
    test:SetScript("OnClick", function()
        if not PlayTestClip() then
            print("|cff33ff99SpeakStone:|r no audio pack installed yet, so there is nothing to play.")
        end
    end)

    page:SetScript("OnShow", function()
        if HasAnyAudioPack() then
            status:SetText("|cff00ff00Audio packs found.|r You're ready to go. Press Test a voice to hear one.\n\n"
                .. "Packs are always being updated and improved, so check CurseForge now and then for new ones.")
            test:Enable()
        else
            status:SetText("|cffff6b5eNo audio packs installed.|r SpeakStone works better with the audio packs installed.\n\n"
                .. "Please look on CurseForge to get the Audio packs. They are always being updated and improved."
                .. (addon.AUDIO_PACK_EXTRA_NOTE or ""))
            test:Disable()
            box:SetFocus()
        end
        -- This page covers the one-off audio-pack popup.
        DB().audioPackPromptShown = true
    end)
end

local function BuildControls()
    local page = NewPage("controls")
    local title = Text(page, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText("Where things are")
    local body = Text(page, "GameFontHighlight", WIDTH - 40)
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    body:SetSpacing(5)
    body:SetText("|TInterface\\AddOns\\" .. addonName .. "\\cs_icon.tga:16:16|t  |cffffd100Minimap button|r: left-click opens settings, right-click exports captured text.\n\n"
        .. "|cffffd100Read Quest button|r: at the bottom of the quest window and quest log. Plays (or replays) the current quest.\n\n"
        .. "|cffffd100Speech bar|r: Pause, Stop, Replay, and Next when quests are queued. Right-click it or use the gear for size and options; the mouse wheel scrolls the text.\n\n"
        .. "|cffffd100Keys|r: F6 plays the current quest. Set a Pause / resume key in the game's Key Bindings, under SpeakStone.\n\n"
        .. "|cffffd100/ss|r: opens the settings window, voice pack status and audio library.\n"
        .. "|cffffd100/sstoggle|r: stop or replay the current narration.\n"
        .. "|cffffd100/ss frame|r: show the sample speech bar to move or resize it.\n"
        .. "|cffffd100/ssmissing|r: list quests you've seen that have no audio yet.\n"
        .. "|cffffd100/ss tutorial|r: reopen this guide and change profile.")
end

local function BuildContribute()
    local page = NewPage("contribute")
    local title = Text(page, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText("Help SpeakStone grow")

    local voiceHead = Text(page, "GameFontNormal")
    voiceHead:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    voiceHead:SetText("Lend your voice")
    local voice = Text(page, "GameFontHighlight", WIDTH - 40)
    voice:SetPoint("TOPLEFT", voiceHead, "BOTTOMLEFT", 0, -4)
    voice:SetText("Want your voice in the quest voice pool? Visit the site below and click |cffffd100Lend your voice|r. "
        .. "You can record straight from your web browser or upload a clip.")

    local shareHead = Text(page, "GameFontNormal")
    shareHead:SetPoint("TOPLEFT", voice, "BOTTOMLEFT", 0, -12)
    shareHead:SetText("Share what you capture")
    local share = Text(page, "GameFontHighlight", WIDTH - 40)
    share:SetPoint("TOPLEFT", shareHead, "BOTTOMLEFT", 0, -4)
    share:SetText("New voices are built from text the community submits. As you play, SpeakStone captures quests, "
        .. "NPC talk, books and items that aren't voiced yet. Export it, then import it on the same site.")

    local stats = {}
    local labels = { "QUESTS", "NPC TALK", "BOOKS & ITEMS" }
    local statWidth = math.floor((WIDTH - 40 - 12) / 3)
    for i, label in ipairs(labels) do
        local tile = CreateFrame("Frame", nil, page)
        tile:SetSize(statWidth, 40)
        tile:SetPoint("TOPLEFT", share, "BOTTOMLEFT", (i - 1) * (statWidth + 6), -8)
        local bg = tile:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.09, 0.08, 0.07, 0.85)
        local value = tile:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        value:SetPoint("TOP", 0, -4)
        local name = tile:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        name:SetPoint("BOTTOM", 0, 4)
        name:SetText(label)
        stats[i] = value
        if i == 1 then page.statsAnchor = tile end
    end

    local capture = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    capture:SetSize(24, 24)
    capture:SetPoint("TOPLEFT", page.statsAnchor, "BOTTOMLEFT", -4, -6)
    local captureText = Text(capture, "GameFontHighlight")
    captureText:SetPoint("LEFT", capture, "RIGHT", 2, 0)
    captureText:SetText("Capture text as I play")
    capture:SetScript("OnClick", function(self)
        DB().harvestEnabled = self:GetChecked() and true or false
        if addon.RefreshSettingsStatus then addon.RefreshSettingsStatus() end
    end)

    local export = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    export:SetSize(170, 24)
    export:SetPoint("TOPRIGHT", page.statsAnchor, "BOTTOMLEFT", WIDTH - 40, -6)
    export:SetText("Export captured text")
    export:SetScript("OnClick", function()
        if addon.ShowHarvestExport then addon.ShowHarvestExport() end
    end)

    local linkLabel = Text(page, "GameFontNormalSmall")
    linkLabel:SetPoint("TOPLEFT", capture, "BOTTOMLEFT", 4, -8)
    linkLabel:SetText("Website (Ctrl+C to copy):")
    local box = CopyBox(page, WEBSITE_URL, WIDTH - 60)
    box:SetPoint("TOPLEFT", linkLabel, "BOTTOMLEFT", 6, -4)

    page:SetScript("OnShow", function()
        local quests, lines, items = 0, 0, 0
        if addon.HarvestCounts then
            local q, _, _, _, l, i = addon.HarvestCounts()
            quests, lines, items = q or 0, l or 0, i or 0
        end
        stats[1]:SetText(quests)
        stats[2]:SetText(lines)
        stats[3]:SetText(items)
        capture:SetChecked(DB().harvestEnabled)
    end)
end

local function BuildDone()
    local page = NewPage("done")
    local title = Text(page, "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 0, -10)
    title:SetText("All set!")
    local body = Text(page, "GameFontHighlight", WIDTH - 40)
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -16)
    body:SetSpacing(4)
    page:SetScript("OnShow", function()
        local current = ProfileName(DB().profile)
        body:SetText((current and ("Profile: |cff00ff00" .. current .. "|r\n\n") or "")
            .. "Talk to a quest giver to hear SpeakStone in action.\n\n"
            .. "Wrong voice or missing audio? Report it from the settings window (/ss).\n\n"
            .. "Thanks for helping voice Azeroth. Every capture you submit and every voice you lend makes the next pack better.")
    end)
end

local function BuildWhatsNew()
    local page = NewPage("whatsnew")
    local title = Text(page, "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 0, -10)
    title:SetText("New in SpeakStone")
    local body = Text(page, "GameFontHighlight", WIDTH - 40)
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -16)
    body:SetSpacing(4)
    body:SetText("|cffffd100The speech bar|r keeps the words on screen when you walk away mid-line, scrolls along "
        .. "with the voice, and can grow to show the whole passage.\n\n"
        .. "|cffffd100Quest queue|r: talk to a second quest giver while the first is still being read and the new "
        .. "quest waits its turn. Blizzard's talking heads only pause the queue.\n\n"
        .. "|cffffd100Extra large size|r, and a new |cff00ff00Subtitles|r profile for reading along (in the full "
        .. "tutorial, or the Profiles button in /ss).\n\n"
        .. "Next: set up the speech bar.")

    local full = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    full:SetSize(180, 24)
    full:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -18)
    full:SetText("See the full tutorial")
    full:SetScript("OnClick", function()
        SetOrder(FULL_ORDER)
        ShowPage(1)
    end)
end

-- Move the tutorial off the sample bar, above it if there is room, else
-- below. Next frame, so a bar that has just been shown or resized has its
-- new size.
local function KeepClearOfBar()
    C_Timer.After(0, function()
        if not (frame and frame:IsShown() and addon.SpeechFrameBounds) then return end
        local barBottom, barTop = addon.SpeechFrameBounds()
        local bottom, top = frame:GetBottom(), frame:GetTop()
        if not (barBottom and bottom) or barTop <= bottom or barBottom >= top then return end
        local gap, height = 10, frame:GetHeight()
        local x = frame:GetCenter() - UIParent:GetWidth() / 2
        frame:ClearAllPoints()
        if barTop + gap + height <= UIParent:GetHeight() then
            frame:SetPoint("BOTTOM", UIParent, "BOTTOM", x, barTop + gap)
        elseif barBottom - gap - height >= 0 then
            frame:SetPoint("TOP", UIParent, "BOTTOM", x, barBottom - gap)
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", x, 0)
        end
    end)
end

local SPEECH_SIZES = {
    { "small", "Small" }, { "medium", "Medium" }, { "large", "Large" }, { "xlarge", "Extra large" },
}

local function BuildSpeechBar()
    local page = NewPage("speech")
    local title = Text(page, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText("The speech bar")
    local body = Text(page, "GameFontHighlight", WIDTH - 40)
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    body:SetSpacing(4)
    body:SetText("Walk away from a quest giver mid-line and this bar keeps the words on screen, with who is "
        .. "speaking. A sample is showing now: |cffffd100drag it where you want it|r, then lock it. "
        .. "Right-click it later for the same options.")

    local function Changed(key)
        if addon.SpeechSettingChanged then addon.SpeechSettingChanged(key) end
        KeepClearOfBar()
    end

    local checks = {}
    local previous = body
    for _, spec in ipairs({
        { "showSpeechFrame", "Show the speech bar when I walk away" },
        { "speechAutoScroll", "Scroll the text along with the voice", true },
        { "speechFitText", "Grow the bar to show all the text" },
        { "queueQuestSpeech", "Queue quests instead of cutting one off (1/2 and a Next button)" },
        { "speechFrameLocked", "Lock the bar in place" },
    }) do
        local key, label, onByDefault = spec[1], spec[2], spec[3]
        local check = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
        check:SetSize(24, 24)
        check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", previous == body and -4 or 0, previous == body and -8 or 2)
        local text = Text(check, "GameFontHighlight")
        text:SetPoint("LEFT", check, "RIGHT", 2, 0)
        text:SetText(label)
        check:SetHitRectInsets(0, -text:GetStringWidth() - 4, 0, 0)
        function check.Refresh()
            local value = DB()[key]
            if onByDefault then value = value ~= false end
            check:SetChecked(value and true or false)
        end
        check:SetScript("OnClick", function(self)
            DB()[key] = self:GetChecked() and true or false
            Changed(key)
        end)
        table.insert(checks, check)
        previous = check
    end

    local sizeLabel = Text(page, "GameFontNormal")
    sizeLabel:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 4, -10)
    sizeLabel:SetText("Size:")
    local sizeButtons = {}
    local function RefreshSizes()
        local currentSize = DB().speechSize or "medium"
        for _, button in ipairs(sizeButtons) do
            if button.key == currentSize then button:LockHighlight() else button:UnlockHighlight() end
        end
    end
    local anchor = sizeLabel
    for _, size in ipairs(SPEECH_SIZES) do
        local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        button:SetSize(size[1] == "xlarge" and 100 or 80, 22)
        button:SetPoint("LEFT", anchor, "RIGHT", anchor == sizeLabel and 10 or 4, 0)
        button:SetText(size[2])
        button.key = size[1]
        button:SetScript("OnClick", function()
            DB().speechSize = size[1]
            Changed("speechSize")
            RefreshSizes()
        end)
        table.insert(sizeButtons, button)
        anchor = button
    end

    local sample = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    sample:SetSize(140, 24)
    sample:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", -4, -16)
    local function RefreshSample()
        local shown = addon.SpeechFramePreviewShown and addon.SpeechFramePreviewShown()
        sample:SetText(shown and "Hide the sample" or "Show the sample")
    end
    sample:SetScript("OnClick", function()
        if addon.SpeechFramePreviewShown and addon.SpeechFramePreviewShown() then
            addon.SpeechFrameHidePreview()
        elseif addon.SpeechFrameShowPreview then
            addon.SpeechFrameShowPreview()
            KeepClearOfBar()
        end
        RefreshSample()
    end)

    local reset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    reset:SetSize(140, 24)
    reset:SetPoint("LEFT", sample, "RIGHT", 8, 0)
    reset:SetText("Reset position")
    reset:SetScript("OnClick", function()
        DB().speechFramePos = nil
        Changed("speechFramePos")
    end)

    page:SetScript("OnShow", function()
        for _, check in ipairs(checks) do check.Refresh() end
        RefreshSizes()
        -- Not over narration that is already playing (the preview says so
        -- in chat and stays down).
        if addon.SpeechFrameShowPreview and addon.SpeechFrameShowPreview() then
            KeepClearOfBar()
        end
        RefreshSample()
    end)
    page:SetScript("OnHide", function()
        if addon.SpeechFrameHidePreview then addon.SpeechFrameHidePreview() end
        if addon.PlaceTutorial then addon.PlaceTutorial() end
    end)
end

function ShowPage(index)
    pageIndex = index
    local shown = order[index]
    for i, page in ipairs(pages) do
        page:SetShown(i == shown)
    end
    frame.back:SetEnabled(index > 1)
    frame.next:SetText(index == #order and "Finish" or "Next")
    frame.counter:SetText(index .. " / " .. #order)
end

local function Build()
    frame = CreateFrame("Frame", "SpeakStoneTutorialFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "SpeakStoneTutorialFrame")

    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    header:SetPoint("TOP", 0, -5)
    header:SetText("SpeakStone setup")

    -- Beside Settings rather than on top of it: left if it fits (the Audio
    -- Library takes the right), else right. Settings is wide, so when neither
    -- side has room, Settings slides over to make space. A plain side anchor
    -- just got clamped back on top of Settings.
    frame:SetScript("OnShow", function(self) addon.PlaceTutorial() end)

    function addon.PlaceTutorial()
        local self = frame
        if not self:IsShown() then return end
        local settings = SpeakStoneSettingsFrame
        self:ClearAllPoints()
        if not (settings and settings:IsShown() and settings:GetLeft()) then
            self:SetPoint("CENTER")
        else
            local gap, w = 12, self:GetWidth()
            local screen = UIParent:GetWidth()
            if settings:GetLeft() - gap >= w then
                self:SetPoint("RIGHT", settings, "LEFT", -gap, 0)
            elseif screen - settings:GetRight() - gap >= w then
                self:SetPoint("LEFT", settings, "RIGHT", gap, 0)
            else
                local start = math.max(0, (screen - (w + gap + settings:GetWidth())) / 2)
                local _, y = settings:GetCenter()
                settings:ClearAllPoints()
                settings:SetPoint("LEFT", UIParent, "BOTTOMLEFT", start + w + gap, y)
                self:SetPoint("RIGHT", settings, "LEFT", -gap, 0)
            end
        end
        self:Raise()
    end

    frame:SetScript("OnHide", function()
        -- Done only once the player has actually had it in front of them and
        -- closed it; marking it on show lost it to whatever hid it at login.
        -- UIParent hiding (Alt+Z, a cinematic) fires this too; not a close.
        if DB() and UIParent:IsShown() then DB().tutorialVersion = TUTORIAL_VERSION end
        if testHandle then StopSound(testHandle) testHandle = nil end
        -- Closed without picking a profile: a fresh install gets the recommended
        -- one; an existing player keeps the settings they already had.
        if DB() and not DB().profile and addon.isFreshInstall then ApplyProfile("full") end
    end)

    frame.back = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.back:SetSize(100, 24)
    frame.back:SetPoint("BOTTOMLEFT", 16, 14)
    frame.back:SetText("Back")
    frame.back:SetScript("OnClick", function() ShowPage(pageIndex - 1) end)

    frame.next = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.next:SetSize(100, 24)
    frame.next:SetPoint("BOTTOMRIGHT", -16, 14)
    frame.next:SetScript("OnClick", function()
        if pageIndex == #order then frame:Hide() else ShowPage(pageIndex + 1) end
    end)

    frame.counter = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.counter:SetPoint("BOTTOM", 0, 20)

    pages, pageByName = {}, {}
    BuildWelcome()
    BuildWhatsNew()
    BuildProfiles()
    BuildPacks()
    BuildSpeechBar()
    BuildControls()
    BuildContribute()
    BuildDone()
    SetOrder(FULL_ORDER)
end

-- page: optional start page (2 = profiles). whatsNew: the short run for
-- players who saw an older version of the tutorial.
function addon.ShowTutorial(page, whatsNew)
    if not DB() then return end
    if not frame then Build() end
    SetOrder(whatsNew and WHATSNEW_ORDER or FULL_ORDER)
    selectedProfile = nil
    frame:Show()
    -- Show() on an already-open frame does not fire OnShow.
    addon.PlaceTutorial()
    ShowPage(page or 1)
end

-- Called from PLAYER_LOGIN. Returns true if the tutorial was shown.
function addon.MaybeShowTutorial()
    local db = DB()
    local seen = db and db.tutorialVersion or 0
    if not db or seen >= TUTORIAL_VERSION then return false end
    addon.ShowTutorial(1, seen >= 1)
    return true
end
