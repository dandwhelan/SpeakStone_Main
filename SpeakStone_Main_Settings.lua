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

StaticPopupDialogs["SPEAKSTONE_CONFIRM_CLEAR_HARVEST"] = {
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
-- README. Grouped into tabs (owner, 2026-10-16: design 1 of the menu
-- mock-ups), because one column of options no longer fitted the window.
local DELAY_SLIDER = {
    name = "AutoPlayDelaySlider", option = "autoPlayDelay", default = 1.0,
    min = 0, max = 6, step = 0.5, low = "0s", high = "6s",
    describe = function(v) return string.format("Wait before speaking: %.1fs", v) end,
    title = "Wait before speaking",
    tooltip = "How long to hold back so Blizzard's own voice line can finish before SpeakStone speaks. Ignored when those lines are silenced above, because then there is nothing to wait for.",
}
local DUCK_SLIDER = {
    name = "DuckAmountSlider", option = "duckAmount", default = 0.7, parent = "duckOtherSounds",
    min = 0.1, max = 1, step = 0.1, low = "10%", high = "100%",
    describe = function(v) return string.format("Lower them by: %d%%", math.floor(v * 100 + 0.5)) end,
    title = "Lower them by",
    tooltip = "How far music and ambience drop while a line is read. 100% silences them. They go back to where they were when the line ends.",
}

local SETTINGS_TABS = {
    {
        title = "Playback",
        sections = {
            {
                title = "What is read",
                options = {
                    {
                        option = "autoPlayEnabled",
                        label = "Read automatically",
                        tooltip = "Start narrating as soon as text appears, rather than waiting for the Read Quest button. The options below choose what that covers; with this off, none of them apply. Turn this on if you use Immersion or DialogueUI -- their windows bypass the Read Quest button.",
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
                        option = "skipHeardQuests",
                        label = "Skip quests I've already heard",
                        indent = true,
                        tooltip = "Autoplay leaves a quest passage alone once you have heard it, on any character. Read Quest still plays it. /ss forget clears the list.",
                    },
                },
            },
            {
                title = "When it is read",
                options = {
                    {
                        option = "queueQuestSpeech",
                        label = "Queue quests instead of interrupting",
                        tooltip = "Talking to another quest giver while a quest is still being read adds the new quest to a queue instead of cutting the first one off. The speech frame shows where you are (1/2) and a Next button to skip ahead. Stop clears the queue.",
                    },
                    {
                        option = "autoAcceptQuests",
                        label = "Auto-accept quests (hold Shift to skip)",
                        tooltip = "Accept quests as soon as they are offered and hear them in the speech frame instead. Hold Shift while talking to the quest giver to skip it for that quest.",
                    },
                    {
                        option = "waitForCombatEnd",
                        label = "Wait for combat to end before reading a quest",
                        tooltip = "A quest line that comes up in combat waits, and plays once the fight is over. Subtitles show it waiting. Off: it plays straight away (or is skipped, if autoplay is set to pause in combat).",
                    },
                    {
                        option = "pauseAutoPlayInCombat",
                        label = "Not in combat",
                        tooltip = "Nothing starts reading by itself while you are in combat. Read Quest and the keybind still work.",
                    },
                    {
                        option = "pauseAutoPlayInInstances",
                        label = "Not in dungeons, raids or battlegrounds",
                        tooltip = "Nothing starts reading by itself inside an instance. Read Quest and the keybind still work.",
                    },
                    {
                        option = "stopDialogueOnClose",
                        label = "Stop narration when the window closes",
                        tooltip = "Walking away mid-sentence stops the audio instead of leaving a disembodied voice following you. Off: the line finishes after the window closes, and plays at your Master volume rather than the Dialog slider.",
                    },
                },
            },
        },
    },
    {
        title = "Sound",
        sections = {
            {
                title = "Blizzard's voice lines",
                options = {
                    {
                        option = "muteGossip",
                        label = "Silence Blizzard's own voice lines",
                        tooltip = "Off: where Blizzard has voiced a line, that recording plays and SpeakStone waits its turn. On: the game's Dialog channel is muted instead, so narration starts immediately and nothing plays over it.",
                    },
                },
                slider = DELAY_SLIDER,
            },
            {
                title = "Other sounds",
                options = {
                    {
                        option = "duckOtherSounds",
                        label = "Lower music and ambience while speaking",
                        tooltip = "WoW cannot set a volume for one sound, so this turns music and ambience down while a line is read instead, and back up when it ends.",
                    },
                },
                slider = DUCK_SLIDER,
            },
        },
    },
    {
        title = "On screen",
        sections = {
            {
                title = "Subtitles",
                info = "A small bar over the world that shows who is speaking and the words as the voice reaches them once you walk "
                    .. "away from the NPC. Drag it to move it, right-click it for more, Ctrl and the mouse wheel resize it.",
                options = {
                    {
                        option = "showSubtitles",
                        label = "Show subtitles instead of the speech frame",
                        tooltip = "A small bar over the world shows who is speaking and the words as the voice reaches them, even while the quest window is open. Drag it to move it; right-click for more. Ctrl and the mouse wheel resize it.",
                    },
                    {
                        option = "subtitlesWhileOpen",
                        label = "Also show them while the quest window is open",
                        indent = true,
                        parent = "showSubtitles",
                        tooltip = "The quest window already shows the text, so by default the subtitles appear once you walk away or the window closes. Turn this on to have them over the world even while the window is open.",
                    },
                    {
                        option = "subtitleTypeOut",
                        label = "Type the words out",
                        indent = true,
                        parent = "showSubtitles",
                        tooltip = "The words appear as the voice reaches them. Off: the whole line shows and the row being read stays in view. The timing is an estimate: the recordings do not mark where each word falls.",
                    },
                    {
                        option = "subtitleHighlight",
                        label = "Highlight the word being read in gold",
                        indent = true,
                        parent = "showSubtitles",
                        tooltip = "Lights the word being read and the one before it.",
                    },
                    {
                        option = "subtitleLocked",
                        label = "Lock the subtitles in place",
                        indent = true,
                        parent = "showSubtitles",
                        tooltip = "The bar no longer catches the mouse: it cannot be dragged or resized, and clicks pass through to the game.",
                    },
                },
            },
            {
                title = "Speech bar",
                info = SPEECH_FRAME_INFO,
                options = {
                    {
                        option = "showSpeechFrame",
                        label = "Show the speech frame when you walk away",
                        tooltip = "When you close the quest window while it is still being read, a bar shows who is speaking and what they are saying, with Pause, Stop, Replay and a favourite star. Right-click it to change its size or lock it. /ss frame shows a sample to place it with.",
                    },
                    {
                        option = "speechAutoScroll",
                        label = "Auto-scroll the text",
                        indent = true,
                        parent = "showSpeechFrame",
                        tooltip = "Scroll the text along with the voice so the line being spoken stays in view. Off: the text stays put and the mouse wheel scrolls it.",
                    },
                    {
                        option = "speechFitText",
                        label = "Grow to show all the text",
                        indent = true,
                        parent = "showSpeechFrame",
                        tooltip = "Make the frame taller so the whole passage shows without scrolling (very long text still scrolls). Pair with the Extra large size on the frame's gear menu.",
                    },
                },
            },
            {
                title = "In other windows",
                options = {
                    {
                        option = "syncDialogueText",
                        label = "Reveal quest text as it is spoken (Dialogue UI)",
                        tooltip = "With the Dialogue UI addon, the quest text follows the voice: words appear as it reaches them and the word being read is gold (set under Subtitles: Type the words out, Highlight). The timing is an estimate. Off: the full text shows straight away.",
                    },
                    {
                        option = "talkingHeadHighlight",
                        label = "Light the word being read in talking heads",
                        tooltip = "Blizzard's talking head shows its words whole. This lights the word being read as the line plays, in the highlight colour. The timing is an estimate.",
                    },
                },
                extras = { "previews" },
            },
        },
    },
    {
        title = "Look",
        sections = {
            {
                title = "Theme",
                extras = { "theme" },
                options = {},
            },
            {
                title = "Font and colours",
                info = "How the words SpeakStone shows are drawn: the font, its size and the colours, in the subtitle bar, the "
                    .. "speech frame and the Guide. A font made to be easier on the eye can help readers with dyslexia; which one "
                    .. "works best is personal, so there are several to try.",
                extras = { "font", "fontpreview", "fontsize", "subback", "subtext", "colour" },
                options = {},
            },
        },
    },
    {
        title = "General",
        sections = {
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
                    {
                        option = "showMissingVoiceIcon",
                        label = "Show the missing-voice icon",
                        tooltip = "A small muted speaker beside Read Quest when the text on screen has no voice yet.",
                        onChange = function() if addon.UpdateMissingVoiceIcons then addon.UpdateMissingVoiceIcons() end end,
                    },
                    {
                        option = "harvestEnabled",
                        label = "Capture quest text to help voice missing quests",
                        tooltip = "Records the text of quests, greetings and books you encounter, so unvoiced ones can be queued up. Your character's name is replaced with $n before anything is stored.",
                        onChange = function() if addon.RefreshSettingsStatus then addon.RefreshSettingsStatus() end end,
                    },
                },
            },
            {
                title = "Help and community",
                extrasFirst = true,
                extras = { "links" },
                options = {
                    {
                        option = "showDebugMessages",
                        label = "Advanced: show debug messages in chat",
                        small = true,
                        tooltip = "Prints which clip was chosen, and says so when a quest has no audio installed. Useful when reporting a problem.",
                    },
                },
            },
        },
    },
}

-- A troubleshooting switch, not a preference: drawn small at the foot of the General tab.
local DEBUG_OPTION = {
    option = "showDebugMessages",
    label = "Advanced: show debug messages in chat",
    small = true,
    tooltip = "Prints which clip was chosen, and says so when a quest has no audio installed. Useful when reporting a problem.",
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
local FRAME_HEIGHT = 620
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
    card.ssCardBg = bg

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
    value.ssRole = false

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
    -- Bright greens and golds vanish on paper: the same hues, darker.
    local shade = addon.Theme().light and 0.55 or 1
    card.value:SetTextColor(accent[1] * shade, accent[2] * shade, accent[3] * shade)
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
            -- "Misc" (2026-10-09) was retired 2026-10-10: every one of its lines turned out to be WoW Forever-only.
        },
    },
    {
        prefix = "SpeakStone_Forever_",
        packs = { "Audio_Pack1", "Audio_Pack2", "Chatter" },
    },
}

addon.EXPECTED_PACK_FAMILIES = EXPECTED_PACK_FAMILIES   -- the Guide's Voice packs tab reads it

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

-- What's new (owner, 2026-10-18: "Add a What's new button ... up to 20 items with the dates"). Newest first; keep
-- at most 20 and drop the oldest when adding a release. Player wording only (CLAUDE.md public wording rules).
local WHATS_NEW = {
    { "4.0.1", "2026-10-20", {
        "Narration finishes after you close the quest or gossip window when \"Stop narration when the window closes\" is off. It plays at your Master volume, since the game cuts the Dialog volume channel when a window closes.",
        "The Guide names the character you hear giving each quest instead of a different one (Thrall's quests now show Princess Moira Bronzebeard and Greatmother Geyah where they speak).",
        "Eternus shows as a female dragon.",
        "Voice packs: better pronunciation of Primalists, Nozdormu, Murozond, Khadgar, Kel'Thuzad and Runecarver; Jesper has a child's voice; new takes for Archmage Khadgar and Chromie." } },
    { "4.0.0", "2026-10-19", {
        "A complete interface rebuild: three themes (Parchment, Stone, Midnight), a new settings window and a guided tutorial.",
        "The SpeakStone Guide: browse every voiced quest, greeting and book by expansion, zone, NPC or title, read the text and read along as it plays.",
        "A Voice packs tab shows which packs you have and which are missing.",
        "Subtitles and a text box when you walk away, with the word being read lit.",
        "Optional: quest text follows the voice inside Dialogue UI's own window.",
        "Choose subtitle colours, a reading font and text size, helpful for dyslexia and low vision.",
        "WoW Forever has the same new interface, with its own quest texts and packs." } },
    { "3.2.6", "2026-10-18", {
        "NPC greetings play even when the game's text differs slightly from ours (dashes, quote marks, capitals).",
        "Greetings for about 250 more lines are recognised, among them all nine of Orweyna's.",
        "This What's new window." } },
    { "3.2.5", "2026-10-18", {
        "Settings window with tabs: Playback, Sound, Speech frame and Interface.",
        "New options: skip quests you've already heard, stay quiet in combat or in instances, and lower music and ambience while speaking.",
        "A muted-speaker icon beside Read Quest shows when a quest has no voice yet.",
        "Audio Library: Favourites and Recent tabs." } },
    { "3.2.4", "2026-10-14", { "Updated for World of Warcraft 12.1.5." } },
    { "3.2.3", "2026-10-14", {
        "New greetings sent in through the website, among them Lilian Voss and Timothy Cunningham." } },
    { "3.2.2", "2026-10-14", {
        "About 2,300 retail quest lines re-recorded; over 1,200 now spoken by their quest giver instead of the narrator.",
        "Every child, boy or girl, has the same child voice in both games.",
        "WoW Forever: 89 new quest lines." } },
    { "3.2.1", "2026-10-13", {
        "New lines sent in by players for both games, and four re-recorded books.",
        "Titles for 755 more quests and names for 81 more characters in the Audio Library." } },
    { "3.2.0", "2026-10-12", {
        "Place names said properly: the Deadmines, Darkshire, the Burning Steppes, Auchindoun and more.",
        "Greetings that called every player by one class now say \"hero\" or \"traveller\".",
        "About 1,600 lines re-recorded in the same voices." } },
    { "3.1.6", "2026-10-11", {
        "Quest queue: a greeting no longer holds up a quest, and queued lines keep the character's portrait." } },
    { "3.1.5", "2026-10-10", {
        "The Misc voice pack is retired: its lines belong to WoW Forever, where they are already voiced.",
        "Every line plays at the same volume as the game's own voices." } },
    { "3.1.4", "2026-10-09", {
        "WoW Forever: quest titles and character names use Forever's own names, without \"[DEPRECATED]\" tags." } },
    { "3.1.3", "2026-10-08", {
        "Books and quest lines keep reading when you talk to an NPC who has nothing to say.",
        "Greetings with quotation marks find their audio." } },
    { "3.1.2", "2026-10-07", {
        "A book's text stays on the speech bar after you walk away." } },
    { "3.1.1", "2026-10-06", {
        "Tidier settings window, quest queue fixes and a new Subtitles profile.",
        "Far fewer quests show as \"Unknown quest\" in the Audio Library." } },
    { "3.1.0", "2026-10-05", {
        "Speech bar: the text scrolls along with the voice, can grow to show the whole passage, and has an Extra large size.",
        "Quest queue: a second quest waits its turn instead of cutting the first one off." } },
    { "3.0.1", "2026-10-04", {
        "Captured text never includes your character's name.",
        "Gossip reply pages no longer replay the greeting." } },
    { "3.0.0", "2026-10-04", {
        "The big voice update: over 103,000 voiced lines, more than 55,000 of them re-voiced.",
        "Voices checked for every NPC's race and sex; new voices for Earthen, Vulpera, Tuskarr, Centaur and more." } },
    { "2.0.5", "2026-09-29", { "Book text for more voiced pages." } },
    { "2.0.3", "2026-09-29", { "The settings page knows the Cataclysm and Forever Chatter packs." } },
}

local whatsNewFrame
function addon.ShowWhatsNew()
    if whatsNewFrame then
        whatsNewFrame:SetShown(not whatsNewFrame:IsShown())
        return
    end
    local f = addon.UIK.Window("SpeakStoneWhatsNewFrame", 500, 460, "What's new in SpeakStone")
    tinsert(UISpecialFrames, "SpeakStoneWhatsNewFrame")

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -42)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 12)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(440, 10)
    scroll:SetScrollChild(content)

    local lines = {}
    for _, entry in ipairs(WHATS_NEW) do
        lines[#lines + 1] = addon.Theme().titleCode .. entry[1] .. "|r  " .. addon.Theme().dimCode .. entry[2] .. "|r"
        for _, item in ipairs(entry[3]) do
            lines[#lines + 1] = "  - " .. item
        end
        lines[#lines + 1] = " "
    end
    lines[#lines + 1] = addon.Theme().dimCode .. "Unofficial; not affiliated with Blizzard Entertainment.|r"
    local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 4, -4)
    text:SetWidth(430)
    text:SetJustifyH("LEFT")
    text:SetSpacing(3)
    text:SetText(table.concat(lines, "\n"))
    content:SetHeight(text:GetStringHeight() + 12)

    whatsNewFrame = f
    f:Show()
end

function SpeakStone:CreateWindow()
    if addon.settingsWindow then return addon.settingsWindow end

    local frame = addon.UIK.Window("SpeakStoneSettingsFrame", FRAME_WIDTH, FRAME_HEIGHT, "SpeakStone")
    tinsert(UISpecialFrames, "SpeakStoneSettingsFrame")
    -- The tutorial opens at login, so Settings often opens on top of it.
    frame:HookScript("OnShow", function()
        if addon.PlaceTutorial then addon.PlaceTutorial() end
    end)

    local version = C_AddOns and C_AddOns.GetAddOnMetadata
        and C_AddOns.GetAddOnMetadata(addonName, "Version")
    if version then
        local versionText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        versionText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -42, -12)
        versionText:SetText("v" .. version)
    end

    -- ----------------------------------------------------------------------
    -- Left column: status cards
    -- ----------------------------------------------------------------------
    local cards = {}

    -- Stacked top to bottom; a card that holds buttons is taller.
    local nextCardY = TOP_Y
    local function PlaceCard(spec, height)
        local card = CreateCard(frame, spec)
        height = height or CARD_HEIGHT
        card:SetHeight(height)
        card:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_X, nextCardY)
        nextCardY = nextCardY - height - CARD_GAP
        return card
    end

    local function CardButton(card, text, width, onClick, tooltip)
        local button = addon.UIK.Button(card, text, width, 22, onClick)
        AttachTooltip(button, text, tooltip)
        return button
    end

    cards.packs = PlaceCard({ label = "VOICE PACKS", onClick = function() OpenAudioLibraryUI("packs") end })
    AttachTooltip(cards.packs, "Voice packs", "How much audio is installed and where it came from. Click to see, in the SpeakStone Guide, which pack of each expansion is installed and which is missing.")

    cards.captured = PlaceCard({ label = "YOUR CAPTURES", onClick = ExportHarvest })
    AttachTooltip(cards.captured, "Your captures", "Greetings and book pages exist nowhere but a live client, so they are the part worth sending. Click to export everything recorded so far.")

    -- The way into everything else, one button each: the Guide browses what is voiced, the setup
    -- guide walks through the choices again, What's new lists the changes.
    local guideButton = addon.UIK.Button(frame, "Open SpeakStone Guide", CARD_WIDTH, 36, function() OpenAudioLibraryUI() end)
    guideButton:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_X, nextCardY - 6)
    -- The same dark button as Tutorial and What's new, but taller with a larger label so it is the one to press.
    guideButton:SetHeight(44)
    guideButton.label:SetFontObject("GameFontNormalMed3")
    guideButton.Paint()   -- SetFontObject resets the label colour
    AttachTooltip(guideButton, "SpeakStone Guide", "Browse and replay every voiced quest, greeting and book, grouped by expansion, zone, NPC or title, with the words and how much you have heard. Also /sslibrary.")
    local guideHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    guideHint:SetPoint("TOPLEFT", guideButton, "BOTTOMLEFT", 2, -6)
    guideHint:SetWidth(CARD_WIDTH - 4)
    guideHint:SetJustifyH("LEFT")
    guideHint:SetText("Quests, gossip, books, favourites and recent, with the text and a read-along.")
    local setupButton = addon.UIK.Button(frame, "Tutorial", CARD_WIDTH, 26, function() if addon.ShowTutorial then addon.ShowTutorial(1) end end)
    setupButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", LEFT_X, 48)
    AttachTooltip(setupButton, "Tutorial", "Walk through the choices again: profile, how it looks, and how it behaves while you play. Also /ss tutorial.")
    local newButton = addon.UIK.Button(frame, "What's new", CARD_WIDTH, 26, function() addon.ShowWhatsNew() end)
    newButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", LEFT_X, 16)
    AttachTooltip(newButton, "What's new", "The changes in each release, newest first, with dates. Also /ss whatsnew.")

    -- ----------------------------------------------------------------------
    -- Right column: the options, one tab at a time
    -- ----------------------------------------------------------------------
    local optionsWidth = FRAME_WIDTH - RIGHT_X - 22
    local TAB_HEIGHT = 22
    local cursorY = TOP_Y
    -- What the controls being made now belong to: one panel per tab, or the
    -- window itself for the debug switch that every tab shares.
    local panel = frame

    -- The options under "Read automatically", greyed while it is off: they
    -- still hold their own value, but none of them does anything until the
    -- master switch is back on, and a live checkbox that changes nothing is a
    -- worse answer than a dimmed one.
    -- The same goes for the speech frame's own options under its switch, and
    -- the "lower by" slider under its own.
    local dependentButtons = {}
    local function RefreshOptionStates()
        for _, button in ipairs(dependentButtons) do
            local master = SpeakStone_MainDB[button.parentOption]
            if master then button:Enable() else button:Disable() end
        end
    end

    local function Advance(height)
        cursorY = cursorY - height
    end

    local function makeSectionHeader(title, info)
        local text = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        text:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_X, cursorY)
        text:SetText(title)
        if info then
            CreateInfoIcon(panel, title, info):SetPoint("LEFT", text, "RIGHT", 6, 0)
        end
        Advance(20)

        local divider = addon.UIK.Divider(panel)
        divider:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_X, cursorY)
        divider:SetSize(optionsWidth, 1)
        Advance(8)
    end

    local function makeCheckButton(info)
        local checkButton = addon.UIK.Check(panel, info.label, info.small and "GameFontDisableSmall" or "GameFontNormal")
        -- Indented options are the ones the option above them governs, so the
        -- shape of the list says which switch turns which off.
        local x = RIGHT_X + 2 + (info.indent and 18 or 0)
        checkButton:SetPoint("TOPLEFT", frame, "TOPLEFT", x, cursorY)
        -- The label is part of the click target, not just decoration next to it.
        checkButton:SetHitRectInsets(0, -checkButton.text:GetWidth(), 0, 0)
        checkButton:SetChecked(SpeakStone_MainDB[info.option])

        checkButton:SetScript("OnClick", function(self)
            SpeakStone_MainDB[info.option] = self:GetChecked()
            if info.onChange then info.onChange(self:GetChecked()) end
            if addon.SpeechSettingChanged then addon.SpeechSettingChanged(info.option) end
            RefreshOptionStates()
        end)
        checkButton:SetScript("OnShow", function(self)
            self:SetChecked(SpeakStone_MainDB[info.option])
        end)

        if info.indent then
            checkButton.parentOption = info.parent or "autoPlayEnabled"
            table.insert(dependentButtons, checkButton)
        end

        AttachTooltip(checkButton, info.label, info.tooltip)
        Advance(24)
        return checkButton
    end

    -- The look of SpeakStone's own windows: three themes (Theme.lua).
    local function makeThemeRow()
        local row = addon.UIK.ThemeButtons(panel, optionsWidth - 16)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_X + 8, cursorY)
        Advance(34)
    end

    -- The reading font: a drop-down listing the fonts in Fonts.lua, each in its own letters; a font this
    -- client cannot load is listed greyed out. Under it, a preview in the chosen font and colours.
    local function makeFontRow()
        if not (addon.FontEntry and addon.UIK.FontDropdown) then return end
        local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_X + 8, cursorY - 6)
        label:SetText("Reading font")
        local drop = addon.UIK.FontDropdown(panel, 240)
        drop:SetPoint("LEFT", label, "LEFT", 150, 0)
        Advance(34)
    end

    local function makeFontPreview()
        local box = addon.UIK.FontPreview(panel, optionsWidth - 16, 64)
        box:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_X + 8, cursorY)
        Advance(86)
    end

    -- Where to get help and give it: the website's pages (the address goes in the box, ready to copy), and
    -- the captured text to send.
    local function makeLinks()
        local linkURL = "https://" .. WEBSITE
        local box = addon.UIK.CopyBox(panel, linkURL, optionsWidth - 40)
        local bw = math.floor((optionsWidth - 16 - 8) / 3)
        for i, spec in ipairs({
            { "Submit text", "", "Submit your captured text, and get voice packs." },
            { "Report an issue", "/report", "Wrong voice, broken audio, or anything else worth flagging." },
            { "Lend your voice", "/voice", "Sign up to lend your voice to an NPC." },
        }) do
            local path = spec[2]
            local button = addon.UIK.Button(panel, spec[1], bw, 26, function()
                linkURL = "https://" .. WEBSITE .. path
                box:SetURL(linkURL)
                box:SetFocus()
                box:HighlightText()
            end)
            button:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_X + 8 + (i - 1) * (bw + 4), cursorY)
            AttachTooltip(button, spec[1], spec[3] .. " Puts the address in the box below to copy (Ctrl+C).")
        end
        Advance(32)
        box:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_X + 8, cursorY)
        Advance(30)
        local export = addon.UIK.Button(panel, "Export captured text", 170, 26, ExportHarvest)
        export:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_X + 8, cursorY)
        AttachTooltip(export, "Export captured text", "Everything recorded: NPC greetings, books and quest text, in one payload to paste at the site. Also /ssharvest export.")
        local clear = addon.UIK.Button(panel, "Clear captured text", 170, 26, function() StaticPopup_Show("SPEAKSTONE_CONFIRM_CLEAR_HARVEST") end)
        clear:SetPoint("LEFT", export, "RIGHT", 6, 0)
        AttachTooltip(clear, "Clear captured text", "Throw away everything captured so far. Submit it first if you have not.")
        Advance(34)
    end

    -- A row of colour swatches for one setting (UIKit.lua).
    local function makeSwatchRow(title, option, list, default, tip)
        local row = addon.UIK.SwatchRow(panel, title, option, list, default, tip, 150)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_X + 8, cursorY - 4)
        Advance(30)
    end

    local function makeColourRow()
        makeSwatchRow("Highlight colour", "highlightColour", addon.HighlightColours, "auto", {
            "Gold, or deep red where the text is on light paper (Dialogue UI's parchment theme).",
            "The colour of the word being read, in subtitles, Dialogue UI and talking heads." })
    end

    local function makeSubBackRow()
        makeSwatchRow("Subtitle background", "subtitleBack", addon.SubtitleBackColours, "theme", {
            "The theme's own background.",
            "The colour behind the subtitle text. Soft cream, yellow, blue or green with dark text is easier on the eyes for many people with dyslexia." })
    end

    local function makeSubTextRow()
        makeSwatchRow("Subtitle text", "subtitleText", addon.SubtitleTextColours, "theme", {
            "The theme's own text colour.",
            "The colour of the subtitle text. Dark blue or dark brown on a light background, or white or yellow on a dark one." })
    end

    -- Buttons that show each feature working, in the game.
    local function makePreviewRow()
        local specs = {
            { "Preview subtitles", 130, function() if addon.PreviewSubtitles then addon.PreviewSubtitles() end end,
              "Plays a sample line three times in the subtitle bar, with your current settings." },
            { "Preview Dialogue UI", 140, function() if addon.PreviewWindow then addon.PreviewWindow("dialogue") end end,
              "A sample quest page with the words typing out and the one being read lit, as Dialogue UI's window would show it." },
            { "Preview talking head", 150, function() if addon.PreviewWindow then addon.PreviewWindow("talkinghead") end end,
              "A sample talking head text with the word being read lit." },
        }
        local x = RIGHT_X + 8
        for _, spec in ipairs(specs) do
            local button = addon.UIK.Button(panel, spec[1], spec[2], 22, spec[3])
            button:SetPoint("TOPLEFT", frame, "TOPLEFT", x, cursorY)
            AttachTooltip(button, spec[1], spec[4])
            x = x + spec[2] + 6
        end
        Advance(30)
    end

    -- A slider under its section's options: DELAY_SLIDER, DUCK_SLIDER.
    local function makeSlider(spec)
        Advance(14)
        local slider = addon.UIK.Slider(panel, 220)
        slider:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_X + 8, cursorY - 6)
        slider:SetMinMaxValues(spec.min, spec.max)
        slider:SetValueStep(spec.step)
        slider:SetObeyStepOnDrag(true)
        slider.low:SetText(spec.low)
        slider.high:SetText(spec.high)

        local function Snap(value)
            return math.floor(value / spec.step + 0.5) * spec.step
        end
        local function Describe(value)
            slider.caption:SetText(spec.describe(value))
        end

        slider:SetScript("OnValueChanged", function(self, value)
            value = Snap(value)
            SpeakStone_MainDB[spec.option] = value
            Describe(value)
            if addon.SpeechSettingChanged then addon.SpeechSettingChanged(spec.option) end
        end)
        slider:SetScript("OnShow", function(self)
            local value = tonumber(SpeakStone_MainDB[spec.option]) or spec.default
            self:SetValue(value)
            Describe(value)
        end)
        AttachTooltip(slider, spec.title, spec.tooltip)
        if spec.parent then
            slider.parentOption = spec.parent
            table.insert(dependentButtons, slider)
        end
        Advance(50)
    end

    -- Tabs across the top of the column (owner, 2026-10-16: design 1).
    local tabButtons, panels = {}, {}
    local function SelectTab(index)
        if not panels[index] then index = 1 end
        SpeakStone_MainDB.settingsTab = index
        for i, p in ipairs(panels) do
            p:SetShown(i == index)
            tabButtons[i]:SetSelected(i == index)
        end
    end

    -- Each tab as wide as its name needs, shrunk together if they do not all fit.
    local measure = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local tabWidths, tabTotal = {}, 4 * (#SETTINGS_TABS - 1)
    for i, tab in ipairs(SETTINGS_TABS) do
        measure:SetText(tab.title)
        tabWidths[i] = math.max(60, math.floor(measure:GetStringWidth() + 26))
        tabTotal = tabTotal + tabWidths[i]
    end
    measure:Hide()
    local tabShrink = tabTotal > optionsWidth and (optionsWidth - 4 * (#SETTINGS_TABS - 1)) / (tabTotal - 4 * (#SETTINGS_TABS - 1)) or 1
    local tabX = 0
    for tabIndex, tab in ipairs(SETTINGS_TABS) do
        local tabWidth = math.floor(tabWidths[tabIndex] * tabShrink)
        local button = addon.UIK.Button(frame, tab.title, tabWidth, TAB_HEIGHT, function() SelectTab(tabIndex) end)
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_X + tabX, TOP_Y)
        tabX = tabX + tabWidth + 4
        tabButtons[tabIndex] = button

        -- Same size as the window, so every control below keeps its offsets
        -- from the window's corner.
        panel = CreateFrame("Frame", nil, frame)
        panel:SetAllPoints(frame)
        panel:Hide()
        panels[tabIndex] = panel

        cursorY = TOP_Y - TAB_HEIGHT - 12
        for index, section in ipairs(tab.sections) do
            if index > 1 then Advance(12) end
            makeSectionHeader(section.title, section.info)
            local function Extras(first)
                for _, kind in ipairs(section.extras or {}) do
                    if kind == "theme" then
                        if first == (section.extrasFirst or false) then makeThemeRow() end
                    elseif first == (section.extrasFirst or false) then
                        if kind == "font" then
                            makeFontRow()
                        elseif kind == "fontpreview" then
                            makeFontPreview()
                        elseif kind == "links" then
                            makeLinks()
                        elseif kind == "fontsize" then
                            makeSlider({
                                option = "subtitleFontSize", default = 18, min = 14, max = 36, step = 2, low = "14", high = "36",
                                describe = function(v) return string.format("Subtitle text size: %d", v) end,
                                title = "Subtitle text size",
                                tooltip = "How large the subtitle words are. Larger text takes more rows' height, so the bar grows.",
                            })
                        elseif kind == "subback" then
                            makeSubBackRow()
                        elseif kind == "subtext" then
                            makeSubTextRow()
                        elseif kind == "colour" then
                            makeColourRow()
                        elseif kind == "previews" then
                            makePreviewRow()
                        end
                    end
                end
            end
            if section.extrasFirst then Extras(true) end
            for _, info in ipairs(section.options) do
                makeCheckButton(info)
            end
            if not section.extrasFirst then Extras(false) end
            if section.slider then
                makeSlider(section.slider)
            end
        end
    end
    panel = frame
    SelectTab(tonumber(SpeakStone_MainDB.settingsTab) or 1)

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
                    packLine = (addon.Theme().light and "|cff1b6b2a" or "|cff00ff00") .. "All voice packs installed|r"
                else
                    packLine = (addon.Theme().light and "|cffa02b20" or "|cffff6b5e") .. "Missing:|r " .. table.concat(missing, ", ")
                end
                local caption = string.format("clip(s) across %d quest(s)\n%s", quests, packLine)
                SetCardState(cards.packs, ACCENT_GOOD, clips, caption)
            end
        end

        if addon.HarvestCounts then
            local capturedQuests, passages, _, npcs, glines, items, pages = addon.HarvestCounts()
            -- Greetings and books lead. Neither has a table in the client nor
            -- a scrapeable equivalent, so capture is the only way they can
            -- ever be obtained; quest text can be sourced other ways.
            -- Only what there is: a row of zeros wrapped across the card and
            -- said nothing. The greeting count is the headline above.
            local function Count(n, one, many)
                return n .. " " .. (n == 1 and one or many)
            end
            local parts = {}
            if npcs > 0 then
                table.insert(parts, (glines == 1 and "greeting" or "greetings") .. " from " .. Count(npcs, "NPC", "NPCs"))
            end
            if items > 0 then
                table.insert(parts, Count(pages, "page", "pages") .. " in " .. Count(items, "book", "books"))
            end
            if capturedQuests > 0 then
                table.insert(parts, Count(passages, "passage", "passages") .. " from " .. Count(capturedQuests, "quest", "quests"))
            end
            local summary = #parts > 0 and table.concat(parts, "\n") or "Nothing captured yet."
            -- Once there is a real amount sitting here, the card stops being a
            -- statistic and starts asking for something. Capture that nobody
            -- submits helps nobody.
            -- The top-level entry total is exactly what HarvestCounts just
            -- counted, so it is handed over rather than walked for again.
            local entries = capturedQuests + npcs + items
            local recording = SpeakStone_MainDB.harvestEnabled
            local good = addon.Theme().light and "|cff1b6b2a" or "|cff00ff00"
            if not recording then
                summary = summary .. "\n|cffff6b5eCapture is off (General tab).|r"
            end
            if addon.HarvestShouldSubmit and addon.HarvestShouldSubmit(entries) then
                SetCardState(cards.captured, ACCENT_GOOD, glines, summary .. "\n" .. good .. "Ready to submit -- click to export.|r")
            else
                SetCardState(cards.captured, recording and ACCENT_NEUTRAL or ACCENT_BAD, glines, summary)
            end
        end
    end

    addon.RefreshSettingsStatus = RefreshDashboard
    addon.ThemeRegister(function() if frame:IsShown() then RefreshDashboard() end end)
    frame:HookScript("OnShow", function()
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
    speechFrame:SetSize(500, 306)
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
        { "waitForCombatEnd", "Wait for combat to end before reading a quest" },
        { "showSubtitles", "Show subtitles instead of the speech frame" },
        { "subtitleTypeOut", "Type the subtitle words out" },
        { "subtitleHighlight", "Highlight the word being read" },
        { "syncDialogueText", "Reveal quest text as it is spoken (Dialogue UI)" },
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
        check:SetScript("OnClick", function(self)
            SpeakStone_MainDB[key] = self:GetChecked() and true or false
            if addon.SpeechSettingChanged then addon.SpeechSettingChanged(key) end
        end)
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

SLASH_SPEAKSTONE1, SLASH_SPEAKSTONE2, SLASH_SPEAKSTONE3, SLASH_SPEAKSTONE4 = '/qr', '/questreader', '/ss', '/speakstone'
SlashCmdList.SPEAKSTONE = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "tutorial" or msg == "setup" then
        if addon.ShowTutorial then addon.ShowTutorial(1) end
        return
    elseif msg == "profile" or msg == "profiles" then
        if addon.ShowTutorial then addon.ShowTutorial(2) end
        return
    elseif msg == "forget" then
        if SpeakStone_MainDB and SpeakStone_MainDB.heardQuests then
            wipe(SpeakStone_MainDB.heardQuests)
        end
        print("SpeakStone: forgot which quests you have heard. They will autoplay again.")
        return
    elseif msg == "frame" then
        if addon.SpeechFramePreview then addon.SpeechFramePreview() end
        return
    elseif msg == "whatsnew" or msg == "new" then
        addon.ShowWhatsNew()
        return
    end
    addon:OpenSettings()
end
