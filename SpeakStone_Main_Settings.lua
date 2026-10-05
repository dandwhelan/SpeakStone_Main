local addonName, addon = ...
local SpeakStone = {}

EventUtil.ContinueOnAddOnLoaded(addonName, function()
    SpeakStone_MainDB = SpeakStone_MainDB or {}
    -- The two ADDON_LOADED handlers -- this one and the main file's -- have no
    -- guaranteed order between them, and every checkbox below reads its
    -- default out of the saved variables. Arriving first meant reading nil and
    -- drawing a fresh install's options as all-off. The call is idempotent, so
    -- it costs nothing when the main file got here first.
    if addon.EnsureDB then addon.EnsureDB() end
    SpeakStone:CreateSettings()
end)

local WEBSITE = "speakstone.beanw.co.uk"

-- Shown behind the info icon by the speech frame options, here and on the
-- game's AddOns page.
local SPEECH_FRAME_INFO = "When you walk away from a quest giver while a line is still being read (or a quest is "
    .. "auto-accepted), a bar shows the NPC, the quest and the full text, with Pause, Stop and Replay.\n\n"
    .. "|cffffd100About Pause:|r WoW can only play a sound file from the start. It can't pause one or jump into the "
    .. "middle, so Pause stops the voice and Resume plays the line again from the beginning.\n\n"
    .. "Right-click the bar to change its size or lock it. |cffffd100/ss frame|r shows a sample to place it with."

-- A small "i" that explains a section on mouse-over.
local function CreateInfoIcon(parent, title, body)
    local icon = CreateFrame("Button", nil, parent)
    icon:SetSize(18, 18)
    icon:SetNormalTexture("Interface\\common\\help-i")
    icon:SetHighlightTexture("Interface\\common\\help-i", "ADD")
    icon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, 1, 0.82, 0)
        GameTooltip:AddLine(body, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return icon
end

local function OpenAudioLibraryUI(mode)
    if addon.OpenAudioLibrary then
        addon.OpenAudioLibrary(mode)
    else
        print("SpeakStone: the audio library window is not available.")
    end
end

-- Capture lives entirely in this addon. The old standalone Harvester addon
-- is no longer deferred to; anything it left in its saved variables is still
-- folded into the export (Harvester.lua), so nothing recorded with it is lost.
local function ExportHarvest()
    addon.ShowHarvestExport()
end

StaticPopupDialogs["QUESTREADER_CONFIRM_CLEAR_HARVEST"] = {
    text = "Clear everything SpeakStone has captured -- quest text, greetings and books?\n\nThis cannot be undone, and anything not yet submitted is lost.",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        if SpeakStoneHarvesterDB then
            -- Left over from the standalone addon, cleared silently: the one
            -- line printed below covers both stores, and two "cleared"
            -- messages for one click read as if something went twice.
            SpeakStoneHarvesterDB.quests = {}
            SpeakStoneHarvesterDB.gossip = {}
            SpeakStoneHarvesterDB.itemText = {}
        end
        -- Clear this addon's own store too. It is separate from the
        -- standalone Harvester's, so wiping only one would leave the player
        -- looking at data they thought they had just cleared.
        if addon.HarvestWipe then
            addon.HarvestWipe()
            print("SpeakStone: captured text cleared.")
        end
        if addon.RefreshSettingsStatus then addon.RefreshSettingsStatus() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Every option, with the one-line explanation that used to live only in the
-- README. Grouped, because a flat list of seven checkboxes gave no clue which
-- of them mattered when quest audio was not playing.
local SETTINGS_SECTIONS = {
    {
        title = "Playback",
        options = {
            {
                option = "autoPlayEnabled",
                label = "Read automatically",
                tooltip = "Start narrating as soon as text appears, rather than waiting for the Read Quest button. The three below choose what that covers; with this off, none of them apply. Turn this on if you use Immersion or DialogueUI -- their windows bypass the Read Quest button.",
            },
            {
                option = "autoPlayQuests",
                label = "Quests",
                indent = true,
                tooltip = "Quest descriptions, progress and completion text, read at the quest giver.",
            },
            {
                option = "autoPlayGossip",
                label = "NPC greetings",
                indent = true,
                tooltip = "The lines an NPC says when you first talk to them. Turn this off if you pass a lot of NPCs and only want quest text read.",
            },
            {
                option = "autoPlayItemText",
                label = "Books, letters and plaques",
                indent = true,
                tooltip = "Anything read through the book window -- tomes, scrolls, letters and the plaques in dungeons.",
            },
            {
                option = "autoPlayInQuestMap",
                label = "Also read from the quest log map",
                indent = true,
                tooltip = "Narrate when a quest is selected in the world map's quest list, not just at the quest giver.",
            },
            {
                option = "muteGossip",
                label = "Silence Blizzard's own voice lines",
                tooltip = "Off by default: where Blizzard has voiced a line, that recording plays and SpeakStone waits its turn. Turn this on to mute the game's Dialog channel instead, so narration starts immediately and nothing plays over it.",
            },
            {
                option = "stopDialogueOnClose",
                label = "Stop narration when the window closes",
                tooltip = "Walking away mid-sentence stops the audio instead of leaving a disembodied voice following you.",
            },
        },
    },
    {
        title = "Speech frame",
        info = SPEECH_FRAME_INFO,
        options = {
            {
                option = "showSpeechFrame",
                label = "Show the speech frame when you walk away",
                tooltip = "When you close the quest window while it is still being read, a bar shows who is speaking and what they are saying, with Pause, Stop and Replay. Right-click it to change its size or lock it. /ss frame shows a sample to place it with.",
            },
            {
                option = "speechAutoScroll",
                label = "Auto-scroll the speech frame text",
                tooltip = "Scroll the text along with the voice so the line being spoken stays in view. Off: the text stays put and the mouse wheel scrolls it.",
            },
            {
                option = "speechFitText",
                label = "Grow the speech frame to show all the text",
                tooltip = "Make the frame taller so the whole passage shows without scrolling (very long text still scrolls). Pair with the Extra large size on the frame's gear menu.",
            },
            {
                option = "queueQuestSpeech",
                label = "Queue quests instead of interrupting",
                tooltip = "Talking to another quest giver while a quest is still being read adds the new quest to a queue instead of cutting the first one off. The speech frame shows where you are (1/2) and a Next button to skip ahead. Stop clears the queue.",
            },
            {
                option = "autoAcceptQuests",
                label = "Auto-accept quests",
                tooltip = "Accept quests as soon as they are offered and hear them in the speech frame instead. Hold Shift while talking to the quest giver to skip it for that quest.",
            },
        },
    },
    {
        title = "Interface",
        options = {
            {
                option = "showMinimapButton",
                label = "Show the minimap button",
                tooltip = "Left-click opens these settings, right-click exports captured text, middle-click toggles debug messages.",
                onChange = function() if addon.UpdateMinimapButtonVisibility then addon.UpdateMinimapButtonVisibility() end end,
            },
            {
                option = "showQuestButton",
                label = "Show the Read Quest button",
                tooltip = "The button at the bottom of the quest window and in the quest log. Hide it if your quest UI already covers that spot -- narration still works.",
                onChange = function() if addon.UpdateQuestButtonVisibility then addon.UpdateQuestButtonVisibility() end end,
            },
        },
    },
    {
        title = "Contribute",
        options = {
            {
                option = "harvestEnabled",
                label = "Auto capture quest text to help voice missing quests",
                tooltip = "Records the text of quests, greetings and books you encounter, so unvoiced ones can be queued up. Your character's name is replaced with $n before anything is stored.",
                onChange = function() if addon.RefreshSettingsStatus then addon.RefreshSettingsStatus() end end,
            },
            {
                option = "showDebugMessages",
                label = "Show debug messages in chat",
                tooltip = "Prints which clip was chosen, and says so when a quest has no audio installed. Useful when reporting a problem.",
            },
        },
    },
}

-- --------------------------------------------------------------------------
-- Small shared helpers
-- --------------------------------------------------------------------------

local GOLD = { 1, 0.82, 0 }

local function AttachTooltip(frame, title, body)
    if not body then return end
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, GOLD[1], GOLD[2], GOLD[3])
        GameTooltip:AddLine(body, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- --------------------------------------------------------------------------
-- The window
-- --------------------------------------------------------------------------

local FRAME_WIDTH = 700
local FRAME_HEIGHT = 740
local CARD_WIDTH = 226
local CARD_HEIGHT = 92
local CARD_GAP = 8
local LEFT_X = 16
local RIGHT_X = LEFT_X + CARD_WIDTH + 20
local TOP_Y = -34

-- A dashboard tile: a small label, a headline value, a wrapped caption and an
-- optional action line. The state a player needs first -- whether any voice
-- pack is installed at all -- used to be one red sentence inside a paragraph
-- below the options, which is to say invisible.
local function CreateCard(parent, spec)
    local card = CreateFrame("Button", nil, parent)
    card:SetSize(CARD_WIDTH, CARD_HEIGHT)
    -- A long pack list or caption used to grow past the card's own edges --
    -- anchored at BOTTOMLEFT with no top bound, extra lines pushed upward
    -- right out of the card and, for the top card, clean over the window's
    -- own title bar. Clipping keeps overflow inside the tile instead.
    card:SetClipsChildren(true)

    local bg = card:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.09, 0.08, 0.07, 0.85)

    -- The one piece of colour on the tile. It carries the state, so a glance
    -- at the left column says which tile wants attention.
    local accent = card:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("TOPRIGHT")
    accent:SetHeight(2)
    accent:SetColorTexture(0.72, 0.57, 0.19, 1)
    card.accent = accent

    local label = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    label:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -9)
    label:SetText(spec.label)
    card.label = label

    local value = card:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
    value:SetWidth(CARD_WIDTH - 20)
    value:SetJustifyH("LEFT")
    card.value = value

    local caption = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    -- Anchored below the value line now, not off the card's bottom edge --
    -- extra lines grow down and get clipped by the card itself instead of
    -- growing up over whatever this card overlaps (see SetClipsChildren above).
    caption:SetPoint("TOPLEFT", value, "BOTTOMLEFT", 0, -6)
    caption:SetWidth(CARD_WIDTH - 20)
    caption:SetJustifyH("LEFT")
    caption:SetJustifyV("TOP")
    caption:SetSpacing(2)
    card.caption = caption

    if spec.onClick then
        card:SetScript("OnClick", spec.onClick)
        local highlight = card:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.06)
    end

    return card
end

-- Colour and text for one card, given the current state. Kept apart from the
-- frame building so a refresh is a data update, not a rebuild.
local function SetCardState(card, accent, value, caption)
    card.accent:SetColorTexture(accent[1], accent[2], accent[3], 1)
    card.value:SetText(value or "")
    card.value:SetTextColor(accent[1], accent[2], accent[3])
    card.caption:SetText(caption or "")
end

-- Every pack a complete install has, per family. A missing pack cannot
-- announce itself -- it is not loaded -- so the only way to say what is absent
-- is to know what should be there. Update this when a pack is added or a
-- volume split is sealed (tools/pack_split_state.json). 2026-09-29: Cataclysm and
-- Classic re-split (2 parts) below CurseForge's ~600 MB upload limit.
local EXPECTED_PACK_FAMILIES = {
    {
        prefix = "SpeakStone_Pack_",
        packs = {
            "Classic_Part1", "Classic_Part2", "TheBurningCrusade",
            "WrathoftheLichKing", "Cataclysm_Part1", "Cataclysm_Part2", "MistsofPandaria",
            "WarlordsofDraenor", "Legion", "BattleforAzeroth", "Shadowlands",
            "Dragonflight", "TheWarWithin", "Midnight", "Chatter_Part1", "Chatter_Part2",
        },
    },
    {
        prefix = "SpeakStone_Forever_",
        packs = { "Audio_Pack1", "Audio_Pack2", "Chatter" },
    },
}

-- Judged against whichever family the player actually uses, so someone on
-- the Forever bundle is not told they lack every expansion pack.
local function MissingPacks(installedPacks)
    local installed = {}
    for _, pack in ipairs(installedPacks) do installed[pack.name] = true end
    local best, bestHits = EXPECTED_PACK_FAMILIES[1], -1
    for _, family in ipairs(EXPECTED_PACK_FAMILIES) do
        local hits = 0
        for _, short in ipairs(family.packs) do
            if installed[family.prefix .. short] then hits = hits + 1 end
        end
        if hits > bestHits then best, bestHits = family, hits end
    end
    local missing = {}
    for _, short in ipairs(best.packs) do
        if not installed[best.prefix .. short] then
            table.insert(missing, (short:gsub("_", " ")))
        end
    end
    return missing
end

local ACCENT_GOOD = { 0.25, 0.82, 0.48 }
local ACCENT_BAD = { 1, 0.42, 0.37 }
local ACCENT_NEUTRAL = { 0.85, 0.75, 0.45 }

function SpeakStone:CreateWindow()
    if addon.settingsWindow then return addon.settingsWindow end

    local frame = CreateFrame("Frame", "SpeakStoneSettingsFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    tinsert(UISpecialFrames, "SpeakStoneSettingsFrame")
    -- The tutorial opens at login, so Settings often opens on top of it.
    frame:HookScript("OnShow", function()
        if addon.PlaceTutorial then addon.PlaceTutorial() end
    end)

    if frame.TitleText then
        frame.TitleText:SetText("SpeakStone")
    end

    local version = C_AddOns and C_AddOns.GetAddOnMetadata
        and C_AddOns.GetAddOnMetadata(addonName, "Version")
    if version then
        local versionText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        versionText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -8)
        versionText:SetText("v" .. version)
    end

    -- ----------------------------------------------------------------------
    -- Left column: status cards
    -- ----------------------------------------------------------------------
    local cards = {}

    local function PlaceCard(spec, index)
        local card = CreateCard(frame, spec)
        card:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_X, TOP_Y - (index - 1) * (CARD_HEIGHT + CARD_GAP))
        return card
    end

    cards.packs = PlaceCard({ label = "VOICE PACKS", onClick = function() OpenAudioLibraryUI() end }, 1)
    AttachTooltip(cards.packs, "Voice packs", "How much audio is installed and where it came from. Click to browse and replay every voiced quest your packs provide.")

    cards.captured = PlaceCard({ label = "YOUR CAPTURES", onClick = ExportHarvest }, 2)
    AttachTooltip(cards.captured, "Your captures", "Greetings and book pages exist nowhere but a live client, so they are the part worth sending. Click to export everything recorded so far.")

    cards.capture = PlaceCard({ label = "CAPTURE" }, 3)
    AttachTooltip(cards.capture, "Capture", "Whether SpeakStone is recording the text it encounters. Your character's name is replaced with $n before anything is stored.")

    -- A clickable link is not something an addon can offer, so the next best
    -- thing is a box the player can select and copy without leaving the panel.
    local linkCard = PlaceCard({ label = "CONTRIBUTE" }, 4)
    linkCard.value:Hide()
    linkCard.caption:ClearAllPoints()
    linkCard.caption:SetPoint("TOPLEFT", linkCard.label, "BOTTOMLEFT", 0, -4)
    linkCard.caption:SetText("Submit captured text, and get voice packs, at:")
    linkCard.accent:SetColorTexture(ACCENT_NEUTRAL[1], ACCENT_NEUTRAL[2], ACCENT_NEUTRAL[3], 1)

    local linkBox = CreateFrame("EditBox", nil, linkCard, "InputBoxTemplate")
    linkBox:SetSize(CARD_WIDTH - 30, 20)
    linkBox:SetPoint("BOTTOMLEFT", linkCard, "BOTTOMLEFT", 16, 8)
    linkBox:SetAutoFocus(false)
    linkBox:SetText("https://" .. WEBSITE)
    linkBox:SetCursorPosition(0)
    -- Read-only in effect: typing into it would only mislead.
    linkBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText("https://" .. WEBSITE)
            self:HighlightText()
        end
    end)
    linkBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    linkBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Same copyable-box pattern as CONTRIBUTE above -- an addon cannot open a
    -- browser, so a selectable link is the closest thing to a clickable one.
    local function CreateLinkCard(index, label, caption, path)
        local card = PlaceCard({ label = label }, index)
        card.value:Hide()
        card.caption:ClearAllPoints()
        card.caption:SetPoint("TOPLEFT", card.label, "BOTTOMLEFT", 0, -4)
        card.caption:SetText(caption)
        card.accent:SetColorTexture(ACCENT_NEUTRAL[1], ACCENT_NEUTRAL[2], ACCENT_NEUTRAL[3], 1)

        local box = CreateFrame("EditBox", nil, card, "InputBoxTemplate")
        box:SetSize(CARD_WIDTH - 30, 20)
        box:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 16, 8)
        box:SetAutoFocus(false)
        local url = "https://" .. WEBSITE .. path
        box:SetText(url)
        box:SetCursorPosition(0)
        box:SetScript("OnTextChanged", function(self, userInput)
            if userInput then
                self:SetText(url)
                self:HighlightText()
            end
        end)
        box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        return card
    end

    cards.reportIssue = CreateLinkCard(5, "REPORT ISSUE", "Wrong voice, broken audio, or anything else -- report it at:", "/report")
    AttachTooltip(cards.reportIssue, "Report an issue", "Opens a copyable link to SpeakStone's issue-report page. Wrong-sex voices, mispronunciations, missing audio, and anything else worth flagging goes here.")

    cards.addVoice = CreateLinkCard(6, "ADD YOUR VOICE", "Want to lend your voice to an NPC? Sign up at:", "/voice")
    AttachTooltip(cards.addVoice, "Add your voice", "Opens a copyable link to SpeakStone's voice-donation page, where you can contribute your own voice as a reference for future NPCs.")

    -- ----------------------------------------------------------------------
    -- Right column: the options themselves, unchanged in content
    -- ----------------------------------------------------------------------
    local optionsWidth = FRAME_WIDTH - RIGHT_X - 22
    local cursorY = TOP_Y

    -- The options under "Read automatically", greyed while it is off: they
    -- still hold their own value, but none of them does anything until the
    -- master switch is back on, and a live checkbox that changes nothing is a
    -- worse answer than a dimmed one.
    local dependentButtons = {}
    local function RefreshOptionStates()
        local master = SpeakStone_MainDB.autoPlayEnabled
        for _, button in ipairs(dependentButtons) do
            if master then button:Enable() else button:Disable() end
            if button.text then
                if master then
                    button.text:SetTextColor(1, 0.82, 0)
                else
                    button.text:SetTextColor(0.5, 0.5, 0.5)
                end
            end
        end
    end

    local function Advance(height)
        cursorY = cursorY - height
    end

    local function makeSectionHeader(title, info)
        local text = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        text:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_X, cursorY)
        text:SetText(title)
        if info then
            CreateInfoIcon(frame, title, info):SetPoint("LEFT", text, "RIGHT", 6, 0)
        end
        Advance(20)

        local divider = frame:CreateTexture(nil, "ARTWORK")
        divider:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_X, cursorY)
        divider:SetSize(optionsWidth, 1)
        divider:SetColorTexture(0.35, 0.31, 0.24, 0.9)
        Advance(8)
    end

    local function makeCheckButton(info)
        local checkButton = CreateFrame("CheckButton", addonName .. "CheckBox_" .. info.option, frame, "SettingsCheckBoxTemplate")
        -- Indented options are the ones the option above them governs, so the
        -- shape of the list says which switch turns which off.
        local x = RIGHT_X + 2 + (info.indent and 18 or 0)
        checkButton:SetPoint("TOPLEFT", frame, "TOPLEFT", x, cursorY)
        checkButton.text = checkButton:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        checkButton.text:SetText(info.label)
        checkButton.text:SetPoint("LEFT", checkButton, "RIGHT", 4, 0)
        checkButton:SetSize(21, 20)
        -- The label is part of the click target, not just decoration next to it.
        checkButton:SetHitRectInsets(0, -checkButton.text:GetWidth(), 0, 0)
        checkButton.HoverBackground = nil
        checkButton:SetChecked(SpeakStone_MainDB[info.option])

        checkButton:SetScript("OnClick", function(self)
            SpeakStone_MainDB[info.option] = self:GetChecked()
            if info.onChange then info.onChange(self:GetChecked()) end
            RefreshOptionStates()
        end)
        checkButton:SetScript("OnShow", function(self)
            self:SetChecked(SpeakStone_MainDB[info.option])
        end)

        if info.indent then
            table.insert(dependentButtons, checkButton)
        end

        AttachTooltip(checkButton, info.label, info.tooltip)
        Advance(24)
        return checkButton
    end

    for index, section in ipairs(SETTINGS_SECTIONS) do
        if index > 1 then Advance(12) end
        makeSectionHeader(section.title, section.info)
        for _, info in ipairs(section.options) do
            makeCheckButton(info)
        end

        -- The delay only means anything while Blizzard's own greeting is
        -- audible, so it sits with the option that controls that.
        if section.title == "Playback" then
            Advance(14)
            local slider = CreateFrame("Slider", addonName .. "AutoPlayDelaySlider", frame, "OptionsSliderTemplate")
            slider:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_X + 8, cursorY)
            slider:SetWidth(220)
            slider:SetMinMaxValues(0, 6)
            slider:SetValueStep(0.5)
            slider:SetObeyStepOnDrag(true)
            _G[slider:GetName() .. "Low"]:SetText("0s")
            _G[slider:GetName() .. "High"]:SetText("6s")

            local function Describe(value)
                _G[slider:GetName() .. "Text"]:SetText(string.format("Wait before speaking: %.1fs", value))
            end

            slider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value * 2 + 0.5) / 2
                SpeakStone_MainDB.autoPlayDelay = value
                Describe(value)
            end)
            slider:SetScript("OnShow", function(self)
                local value = tonumber(SpeakStone_MainDB.autoPlayDelay) or 0.5
                self:SetValue(value)
                Describe(value)
            end)
            AttachTooltip(slider, "Wait before speaking", "How long to hold back so Blizzard's own voice line can finish before SpeakStone speaks. Ignored when those lines are silenced above, because then there is nothing to wait for.")
            Advance(34)
        end
    end

    -- ----------------------------------------------------------------------
    -- Actions. The cards are shortcuts to two of these, not replacements.
    -- ----------------------------------------------------------------------
    -- "Play" section (owner, 2026-09-28): one button per Audio Library tab,
    -- in place of a single "Open Audio Library" button.
    local playLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    playLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", LEFT_X, 19)
    playLabel:SetText("Play")
    local previous
    for _, spec in ipairs({
        { "books", "Books", "Browse every voiced book and read it aloud, whole or page by page." },
        { "gossip", "Gossip", "Browse and replay voiced NPC greetings." },
        { "quests", "Quests", "Browse and replay every voiced quest your installed packs provide. Also /qrlibrary." },
    }) do
        local mode, label, tip = spec[1], spec[2], spec[3]
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(68, 24)
        button:SetText(label)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            button:SetPoint("LEFT", playLabel, "RIGHT", 6, 0)
        end
        button:SetScript("OnClick", function() OpenAudioLibraryUI(mode) end)
        AttachTooltip(button, label, tip)
        previous = button
    end

    local buttons = {
        {
            text = "Export Captured Text",
            width = 150,
            onClick = ExportHarvest,
            tooltip = "Everything recorded: NPC greetings, books and quest text, in one payload to paste at the site. Also /ssharvest export.",
        },
        {
            text = "Clear Captured Data",
            width = 140,
            onClick = function() StaticPopup_Show("QUESTREADER_CONFIRM_CLEAR_HARVEST") end,
            tooltip = "Throw away everything captured so far. Submit it first if you have not.",
        },
        {
            text = "Profiles",
            width = 90,
            onClick = function() if addon.ShowTutorial then addon.ShowTutorial(2) end end,
            tooltip = "Switch to a premade profile, or rerun the first-start setup. Also /ss tutorial.",
        },
    }

    local first = true
    for _, spec in ipairs(buttons) do
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(spec.width or 170, 24)
        button:SetText(spec.text)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", first and 14 or 8, 0)
            first = false
        else
            button:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", LEFT_X, 14)
        end
        button:SetScript("OnClick", spec.onClick)
        AttachTooltip(button, spec.text, spec.tooltip)
        previous = button
    end

    -- ----------------------------------------------------------------------
    -- Keeping the cards true
    -- ----------------------------------------------------------------------
    local function RefreshDashboard()
        if addon.GetInstalledAudioSummary then
            local packs, clips, quests = addon.GetInstalledAudioSummary()
            if clips == 0 then
                SetCardState(cards.packs, ACCENT_BAD, "None installed",
                    "The addon has nothing to play until you add one. Get a pack at " .. WEBSITE .. ".")
            else
                -- What the player wants to know is what they lack, not a list
                -- of what they already have -- that ran off the card and
                -- answered the wrong question.
                local missing = MissingPacks(packs)
                local packLine
                if #missing == 0 then
                    packLine = "|cff00ff00All voice packs installed|r"
                else
                    packLine = "|cffff6b5eMissing:|r " .. table.concat(missing, ", ")
                end
                local caption = string.format("clip(s) across %d quest(s)\n%s", quests, packLine)
                SetCardState(cards.packs, ACCENT_GOOD, clips, caption)
            end
        end

        -- Whether capture is running is not a fact about the counts, so it is
        -- set outside the block below: with the capture module absent, the
        -- card used to be left blank rather than saying anything.
        if SpeakStone_MainDB.harvestEnabled then
            SetCardState(cards.capture, ACCENT_GOOD, "Recording",
                "Quest text, greetings and books are being recorded as you meet them.")
        else
            SetCardState(cards.capture, ACCENT_BAD, "Off",
                "Nothing new is being recorded. Turn on capture under Contribute.")
        end

        if addon.HarvestCounts then
            local capturedQuests, passages, _, npcs, glines, items, pages = addon.HarvestCounts()
            -- Greetings and books lead. Neither has a table in the client nor
            -- a scrapeable equivalent, so capture is the only way they can
            -- ever be obtained; quest text can be sourced other ways.
            local summary = string.format("greeting(s) from %d NPC(s)\n%d page(s) in %d book(s) - %d quest(s), %d passage(s)",
                npcs, pages, items, capturedQuests, passages)
            -- Once there is a real amount sitting here, the card stops being a
            -- statistic and starts asking for something. Capture that nobody
            -- submits helps nobody.
            -- The top-level entry total is exactly what HarvestCounts just
            -- counted, so it is handed over rather than walked for again.
            local entries = capturedQuests + npcs + items
            if addon.HarvestShouldSubmit and addon.HarvestShouldSubmit(entries) then
                SetCardState(cards.captured, ACCENT_GOOD, glines,
                    summary .. "\n|cff00ff00Ready to submit -- click to export.|r")
            else
                SetCardState(cards.captured, ACCENT_NEUTRAL, glines, summary)
            end
        end
    end

    addon.RefreshSettingsStatus = RefreshDashboard
    frame:SetScript("OnShow", function()
        RefreshDashboard()
        RefreshOptionStates()
    end)
    -- Not refreshed here as well. The window is only ever built on the way to
    -- being shown, and Show fires OnShow, so doing it eagerly meant every
    -- first open walked the whole capture store twice and filled the cards
    -- twice before anyone saw either result.

    addon.settingsWindow = frame
    return frame
end

-- The game's own AddOns list still needs an entry, or the addon looks absent
-- from Options entirely. It is a doorway now, not the settings themselves.
function SpeakStone:CreateSettings()
    -- Deliberately not CreateWindow: the settings window is seven hundred
    -- pixels of cards, checkboxes and sliders, and building it at login also
    -- meant walking every clip in every installed pack to fill the dashboard.
    -- addon:OpenSettings builds it the first time someone asks for it.
    local optionsFrame = CreateFrame("Frame", nil, nil, "VerticalLayoutFrame")
    optionsFrame.spacing = 8
    -- Textures resolve from the game root, not the addon folder, so the
    -- path needs the Interface\\AddOns prefix -- without it the escape drew
    -- nothing at all.
    local category = Settings.RegisterCanvasLayoutCategory(optionsFrame, "SpeakStone |TInterface\\AddOns\\" .. addonName .. "\\cs_icon.tga:18:18:0:0|t")
    addon.settingsCategoryID = category.ID
    Settings.RegisterAddOnCategory(category)

    local header = CreateFrame("Frame", nil, optionsFrame)
    header:SetSize(400, 50)
    local headerText = header:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    headerText:SetPoint("TOPLEFT", 7, -22)
    headerText:SetText("SpeakStone")
    local divider = header:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider", true)
    divider:SetPoint("BOTTOMLEFT", -50)
    header.layoutIndex = 1
    header.bottomPadding = 10

    local blurbFrame = CreateFrame("Frame", nil, optionsFrame)
    blurbFrame:SetSize(500, 40)
    blurbFrame.layoutIndex = 2
    blurbFrame.bottomPadding = 8
    local blurb = blurbFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    blurb:SetPoint("TOPLEFT", blurbFrame, "TOPLEFT", 7, 0)
    blurb:SetWidth(490)
    blurb:SetJustifyH("LEFT")
    blurb:SetSpacing(3)
    blurb:SetText("SpeakStone's settings, voice pack status and captured text all live in its own window.\nOpen it here, with the minimap button, or by typing |cffffd100/ss|r.")

    local openFrame = CreateFrame("Frame", nil, optionsFrame)
    openFrame:SetSize(500, 30)
    openFrame.layoutIndex = 3
    local openButton = CreateFrame("Button", nil, openFrame, "UIPanelButtonTemplate")
    openButton:SetSize(200, 24)
    openButton:SetPoint("TOPLEFT", openFrame, "TOPLEFT", 7, 0)
    openButton:SetText("Open SpeakStone settings")
    openButton:SetScript("OnClick", function()
        HideUIPanel(SettingsPanel)
        addon:OpenSettings()
    end)

    -- The speech frame's two switches, here as well as in the window, so it
    -- can be turned off from the game's own Options without knowing /ss.
    local speechFrame = CreateFrame("Frame", nil, optionsFrame)
    speechFrame:SetSize(500, 174)
    speechFrame.layoutIndex = 4
    speechFrame.topPadding = 14
    local speechTitle = speechFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    speechTitle:SetPoint("TOPLEFT", speechFrame, "TOPLEFT", 7, 0)
    speechTitle:SetText("Speech frame")
    CreateInfoIcon(speechFrame, "Speech frame", SPEECH_FRAME_INFO):SetPoint("LEFT", speechTitle, "RIGHT", 6, 0)

    local previous = speechTitle
    for _, spec in ipairs({
        { "showSpeechFrame", "Show the speech frame when you walk away" },
        { "speechAutoScroll", "Auto-scroll the speech frame text" },
        { "speechFitText", "Grow the speech frame to show all the text" },
        { "queueQuestSpeech", "Queue quests instead of interrupting" },
        { "autoAcceptQuests", "Auto-accept quests (hold Shift to skip)" },
    }) do
        local key, label = spec[1], spec[2]
        local check = CreateFrame("CheckButton", nil, speechFrame, "UICheckButtonTemplate")
        check:SetSize(26, 26)
        check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", previous == speechTitle and -4 or 0, previous == speechTitle and -6 or 0)
        local text = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        text:SetPoint("LEFT", check, "RIGHT", 2, 1)
        text:SetText(label)
        check:SetHitRectInsets(0, -text:GetStringWidth() - 4, 0, 0)
        check:SetScript("OnShow", function(self) self:SetChecked(SpeakStone_MainDB[key]) end)
        check:SetScript("OnClick", function(self) SpeakStone_MainDB[key] = self:GetChecked() and true or false end)
        check:SetChecked(SpeakStone_MainDB[key])
        previous = check
    end

    optionsFrame:Layout()
end

-- Open the window without toggling it shut when it is already up.
function addon:ShowSettings()
    local frame = addon.settingsWindow or SpeakStone:CreateWindow()
    frame:Show()
end

-- Function to open settings
function addon:OpenSettings()
    local frame = addon.settingsWindow or SpeakStone:CreateWindow()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

SLASH_QUESTREADER1, SLASH_QUESTREADER2, SLASH_QUESTREADER3, SLASH_QUESTREADER4 = '/qr', '/questreader', '/ss', '/speakstone'
SlashCmdList.QUESTREADER = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "tutorial" or msg == "setup" then
        if addon.ShowTutorial then addon.ShowTutorial(1) end
        return
    elseif msg == "profile" or msg == "profiles" then
        if addon.ShowTutorial then addon.ShowTutorial(2) end
        return
    elseif msg == "frame" then
        if addon.SpeechFramePreview then addon.SpeechFramePreview() end
        return
    end
    addon:OpenSettings()
end
