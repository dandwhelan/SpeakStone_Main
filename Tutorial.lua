local addonName, addon = ...

-- Streamlined first-start setup and premade settings profiles.
-- Redesigned (2026-11-22) from 10 pages down to 4 crisp steps (5 when a controller
-- is active):
--   1. Welcome & voice packs    -- pack check, Test a voice, 1-click "Let me play (use defaults)"
--   1b. TV & Controller         -- auto-inserted ONLY when WoW's controller support is enabled (or via Step 1 link)
--   2. Voice & Display          -- listening preset (2x2), walk-away bar (Compact 4-line default / Subtitles / Audio only), 2D vs 3D speaker
--   3. While you play           -- queue, 3-way combat behaviour, lower music, auto-accept (+ Dialogue UI sync if installed)
--   4. Ready to play            -- 3 quick tips (/ss, F6, faint report sign) + compact capture/export card
--
-- Existing players who saw an older version get a short What's New run instead.

local TUTORIAL_VERSION = 5

local CURSEFORGE_URL = "https://www.curseforge.com/members/dandwhelan/projects"
local WEBSITE_URL = "https://speakstone.beanw.co.uk"

local PROFILES = {
    {
        key = "full",
        name = "Full narration",
        recommended = true,
        description = "Quests, NPC greetings and books read aloud. Blizzard's own lines silenced.",
        settings = {
            autoPlayEnabled = true, autoPlayQuests = true, autoPlayGossip = true, autoPlayItemText = true,
            autoPlayInQuestMap = false, muteGossip = true, yieldToNPCVoice = true,
            stopDialogueOnClose = false, showDebugMessages = false, harvestEnabled = true,
            autoPlayDelay = 1.0,
            showSpeechFrame = true, speechCompact = true, speechFitText = false, speechTVAlways = false,
            speechAutoScroll = true, queueQuestSpeech = true,
            showSubtitles = false, subtitleHighlight = true, fadeOtherParagraphs = true,
        },
    },
    {
        key = "story",
        name = "Story only",
        description = "Quests and books are read; passing NPC greetings stay quiet.",
        settings = {
            autoPlayEnabled = true, autoPlayQuests = true, autoPlayGossip = false, autoPlayItemText = true,
            autoPlayInQuestMap = false, muteGossip = true, yieldToNPCVoice = true,
            stopDialogueOnClose = false, showDebugMessages = false, harvestEnabled = true,
            autoPlayDelay = 1.0,
            showSpeechFrame = true, speechCompact = true, speechFitText = false, speechTVAlways = false,
            speechAutoScroll = true, queueQuestSpeech = true,
            showSubtitles = false, subtitleHighlight = true, fadeOtherParagraphs = true,
        },
    },
    {
        key = "blizzard",
        name = "Blizzard first",
        description = "Blizzard's own voice acting plays where it exists; SpeakStone fills the rest.",
        settings = {
            autoPlayEnabled = true, autoPlayQuests = true, autoPlayGossip = true, autoPlayItemText = true,
            autoPlayInQuestMap = false, muteGossip = false, yieldToNPCVoice = true,
            stopDialogueOnClose = false, showDebugMessages = false, harvestEnabled = true,
            autoPlayDelay = 1.5,
            showSpeechFrame = true, speechCompact = true, speechFitText = false, speechTVAlways = false,
            speechAutoScroll = true, queueQuestSpeech = true,
            showSubtitles = false, subtitleHighlight = true, fadeOtherParagraphs = true,
        },
    },
    {
        key = "manual",
        name = "Manual",
        description = "Nothing plays on its own. Press Read Quest or F6 when you want a quest read.",
        settings = {
            autoPlayEnabled = false, autoPlayQuests = true, autoPlayGossip = true, autoPlayItemText = true,
            autoPlayInQuestMap = false, muteGossip = true, yieldToNPCVoice = true,
            stopDialogueOnClose = true, showDebugMessages = false, harvestEnabled = false,
            showQuestButton = true, autoPlayDelay = 1.0,
            showSpeechFrame = false, speechCompact = true, speechFitText = false, speechTVAlways = false,
            speechAutoScroll = true, queueQuestSpeech = false,
            showSubtitles = false,
        },
    },
    {
        key = "subtitles",
        name = "Read along",
        description = "Full narration with subtitles typing out over the world.",
        settings = {
            autoPlayEnabled = true, autoPlayQuests = true, autoPlayGossip = true, autoPlayItemText = true,
            autoPlayInQuestMap = false, muteGossip = true, yieldToNPCVoice = true,
            stopDialogueOnClose = false, showDebugMessages = false, harvestEnabled = true,
            autoPlayDelay = 1.0,
            showSpeechFrame = true, speechCompact = true, speechFitText = false, speechTVAlways = false,
            speechAutoScroll = true, queueQuestSpeech = true,
            showSubtitles = true, subtitleTypeOut = true, subtitleHighlight = true,
        },
    },
    {
        key = "helper",
        name = "Helper / tester",
        description = "Full narration plus debug messages in chat and text capture on.",
        settings = {
            autoPlayEnabled = true, autoPlayQuests = true, autoPlayGossip = true, autoPlayItemText = true,
            autoPlayInQuestMap = true, muteGossip = true, yieldToNPCVoice = true,
            stopDialogueOnClose = false, showDebugMessages = true, harvestEnabled = true,
            autoPlayDelay = 1.0,
            showSpeechFrame = true, speechCompact = true, speechFitText = false, speechTVAlways = false,
            speechAutoScroll = true, queueQuestSpeech = true,
            showSubtitles = false,
        },
    },
}
addon.PROFILES = PROFILES

local function DB()
    return SpeakStone_MainDB
end

local function PadOn()
    return C_GamePad and C_GamePad.IsEnabled and C_GamePad.IsEnabled()
end

local function DialogueUIInstalled()
    return (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("DialogueUI")) or _G.DUIQuestFrame
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
                for _, option in ipairs({ "speechCompact", "speechFitText", "speechTVAlways", "queueQuestSpeech",
                                          "speechSize", "showSubtitles", "subtitleTypeOut", "subtitleHighlight" }) do
                    addon.SpeechSettingChanged(option)
                end
            end
            if addon.UpdateMinimapButtonVisibility then addon.UpdateMinimapButtonVisibility() end
            if addon.UpdateQuestButtonVisibility then addon.UpdateQuestButtonVisibility() end
            if addon.RefreshSettingChecks then addon.RefreshSettingChecks() end
            print("|cff33ff99SpeakStone:|r profile set to " .. profile.name .. ". Fine-tune any time with /ss.")
            return true
        end
    end
end
addon.ApplyProfile = ApplyProfile

local DEFAULTS_LIST = {
    "Full narration: quests, NPC greetings and books read aloud",
    "Compact 4-line scrolling speech bar with auto-scroll and word highlight",
    "Quests queue instead of cutting each other off",
    "Words lit on Blizzard's talking heads (and Dialogue UI if installed)",
}
if addon.IS_FOREVER then
    DEFAULTS_LIST[4] = "Dialogue UI's window lit too, if installed"
end

local function ApplyDefaults()
    ApplyProfile("full")
    local db = DB()
    db.showSubtitles = false
    db.showSpeechFrame = true
    db.speechCompact = true
    db.speechFitText = false
    db.speechTVAlways = false
    db.speechAutoScroll = true
    db.subtitleHighlight = true
    db.subtitleTypeOut = true
    db.fadeOtherParagraphs = true
    db.speechHideOnTaxi = false
    db.talkingHeadHighlight = not addon.IS_FOREVER
    db.queueQuestSpeech = true
    db.syncDialogueText = DialogueUIInstalled() and true or false
    -- Incorporate TV / controller defaults automatically when controller support is on.
    db.speechTVOnPad = true
    db.speechTVSize = nil
    db.speechTVTextSize = nil
    db.controllerRumble = true
    db.controllerShowLegend = true
    if PadOn() then
        db.speechCombat = "hide"
    end
    if addon.SpeechSettingChanged then
        for _, key in ipairs({ "showSubtitles", "showSpeechFrame", "speechCompact", "speechFitText",
                               "speechTVOnPad", "subtitleHighlight", "queueQuestSpeech",
                               "talkingHeadHighlight", "syncDialogueText" }) do
            addon.SpeechSettingChanged(key)
        end
    end
    if addon.RefreshSettingChecks then addon.RefreshSettingChecks() end
end
addon.ApplyTutorialDefaults = ApplyDefaults
local defaultsApplied = false

local function MissingPackNames()
    if not (addon.GuidePackRows and addon.GetInstalledAudioSummary) then return nil end
    local packs = addon.GetInstalledAudioSummary()
    local rows, have, total = addon.GuidePackRows(packs)
    local missing = {}
    for _, row in ipairs(rows) do
        for _, part in ipairs(row.parts) do
            if not part.installed then
                missing[#missing + 1] = row.label .. (part.label and (" " .. part.label) or "")
            end
        end
    end
    return missing, have, total
end

local function ProfileName(key)
    for _, profile in ipairs(PROFILES) do
        if profile.key == key then return profile.name end
    end
end

-- Test clip playback
local testHandle
local function PlayTestClip()
    if testHandle then
        testHandle:Stop()
        testHandle = nil
    end
    for packName, soundLengths in pairs(addon.soundSources or {}) do
        if packName ~= addonName and type(soundLengths) == "table" then
            for file in pairs(soundLengths) do
                -- addon.PlayClip: the file may be stored in chunks (ClipChunks.lua).
                testHandle = addon.PlayClip and addon.PlayClip("Interface\\AddOns\\" .. packName .. "\\Sounds\\" .. file, "Dialog")
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
-- Window layout
-- --------------------------------------------------------------------------
local WIDTH, HEIGHT = 640, 520
local CONTENT = WIDTH - 60
local frame, pages, pageIndex
local order, pageByName
local ShowPage
local KBM_ORDER = { "welcome", "voice", "play", "done" }
local PAD_ORDER = { "welcome", "controller", "voice", "play", "done" }
local SHORT_ORDER = { "whatsnew", "done" }
local STEP_TITLES = {
    welcome = "Welcome",
    controller = "TV & Controller",
    voice = "Voice & Display",
    play = "While you play",
    done = "Ready to play",
    whatsnew = "What's new",
}
local selectedProfile

local function Gold() return addon.Theme().titleCode end
local function Good() return addon.Theme().light and "|cff1b6b2a" or "|cff4cd97b" end
local function Bad() return addon.Theme().light and "|cffa02b20" or "|cffff6b5e" end

local function Text(parent, template, width)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    if width then fs:SetWidth(width) end
    return fs
end

local function Title(page, text)
    local title = Text(page, "GameFontNormalHuge", CONTENT)
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText(text)
    return title
end

local function Body(page, anchor, text, gap)
    local body = Text(page, "GameFontHighlight", CONTENT)
    body:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(gap or 10))
    body:SetSpacing(3)
    body:SetText(text)
    return body
end

local function Check(page, anchor, key, label, tip, gap, onChange)
    local check = addon.UIK.Check(page, label)
    check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(gap or 8))
    check:SetHitRectInsets(0, -(check.text:GetStringWidth() + 6), 0, 0)
    function check.Refresh()
        check:SetChecked(DB()[key] and true or false)
    end
    check:SetScript("OnClick", function(self)
        DB()[key] = self:GetChecked() and true or false
        if onChange then onChange(DB()[key]) end
        if addon.SpeechSettingChanged then addon.SpeechSettingChanged(key) end
        if addon.RefreshSettingChecks then addon.RefreshSettingChecks() end
    end)
    if tip then
        check:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(label, 1, 0.82, 0)
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        check:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return check
end

local function NewPage(name)
    local page = CreateFrame("Frame", nil, frame)
    page:SetPoint("TOPLEFT", 30, -72)
    page:SetPoint("BOTTOMRIGHT", -30, 56)
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
    order.names = names
end

-- --------------------------------------------------------------------------
-- Step 1: Welcome & Voice Packs
-- --------------------------------------------------------------------------
local function BuildWelcome()
    local page = NewPage("welcome")
    local title = Title(page, "Welcome to SpeakStone")
    local body = Body(page, title, "", 10)

    local status = Text(page, "GameFontHighlight", CONTENT - 140)
    status:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -18)
    status:SetSpacing(3)

    local test = addon.UIK.Button(page, "Test a voice", 126, 26, function()
        if not PlayTestClip() then
            print("|cff33ff99SpeakStone:|r no audio pack installed yet, so there is nothing to play.")
        end
    end)
    test:SetPoint("TOPRIGHT", body, "BOTTOMRIGHT", 0, -18)

    -- CurseForge box: only shown when voice packs are missing
    local linkLabel = Text(page, "GameFontNormalSmall")
    linkLabel:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -14)
    linkLabel:SetText("Get voice packs on CurseForge (Ctrl+C to copy):")
    local box = addon.UIK.CopyBox(page, CURSEFORGE_URL, CONTENT - 12)
    box:SetPoint("TOPLEFT", linkLabel, "BOTTOMLEFT", 0, -4)

    -- Quick defaults summary + 1-click button
    local defTitle = Text(page, "GameFontNormal", CONTENT)
    defTitle:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -18)
    defTitle:SetText("Recommended defaults:")

    local defBody = Text(page, "GameFontHighlightSmall", CONTENT)
    defBody:SetPoint("TOPLEFT", defTitle, "BOTTOMLEFT", 0, -6)
    defBody:SetSpacing(3)

    local skip = addon.UIK.Button(page, "Let me play (use defaults)", 230, 30, function()
        ApplyDefaults()
        defaultsApplied = true
        selectedProfile = "full"
        ShowPage(#order)
    end)
    skip:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 4)
    skip:SetSelected(true)

    local padLink = addon.UIK.Button(page, "Playing on a controller or TV?", 210, 26, function()
        SetOrder(PAD_ORDER)
        ShowPage(2)
    end)
    padLink:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 6)

    page:SetScript("OnShow", function()
        body:SetText("SpeakStone voices quests, NPC greetings and books across Azeroth. Unofficial; not affiliated with Blizzard Entertainment.\n\n"
            .. "This takes about 20 seconds — or jump straight in with our recommended defaults. Re-open any time with "
            .. Gold() .. "/ss tutorial|r.")

        local lines = {}
        for _, item in ipairs(DEFAULTS_LIST) do lines[#lines + 1] = "  - " .. item end
        if PadOn() then
            lines[#lines + 1] = "  - " .. Good() .. "TV / Sofa mode ON|r (big gliding text on controller, hides in combat)"
        end
        defBody:SetText(table.concat(lines, "\n"))

        local showLink = false
        if HasAnyAudioPack() then
            local missing, have, total = MissingPackNames()
            if missing and #missing > 0 then
                status:SetText(Good() .. "Voice packs found" .. (have and total and (": " .. have .. " of " .. total) or "") .. ".|r "
                    .. Bad() .. "Missing: " .. table.concat(missing, ", ") .. ".|r")
                showLink = true
            else
                status:SetText(Good() .. "All voice packs installed.|r Press Test a voice to check your volume.")
            end
            test:Enable()
        else
            status:SetText(Bad() .. "No voice packs installed yet.|r Download packs on CurseForge so SpeakStone has audio to play."
                .. (addon.AUDIO_PACK_EXTRA_NOTE or ""))
            test:Disable()
            showLink = true
        end
        linkLabel:SetShown(showLink)
        box:SetShown(showLink)
        defTitle:ClearAllPoints()
        if showLink then
            defTitle:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -18)
        else
            defTitle:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -24)
        end
        padLink:SetShown(not PadOn())

        DB().audioPackPromptShown = true
        DB().audioPack3BooksPromptShown = true
    end)
end

-- --------------------------------------------------------------------------
-- Step 1b (conditional): TV & Controller
-- --------------------------------------------------------------------------
local function ApplyTVSize(on)
    local db = DB()
    db.speechTVOnPad = on and true or false
    db.speechAutoScroll = true
    if on and addon.SpeechFrameResetPosition then addon.SpeechFrameResetPosition() end
    if addon.SpeechSettingChanged then
        addon.SpeechSettingChanged("speechTVOnPad")
        addon.SpeechSettingChanged("speechSize")
        addon.SpeechSettingChanged("speechTextSize")
    end
end

local function BuildController()
    local page = NewPage("controller")
    local title = Title(page, "Playing with a controller or on a TV?")
    local hint = Body(page, title, "Pick your prompts below. Every setting here also lives in /ss under TV & More.", 6)

    local choices = {}
    local function Refresh()
        local layout = addon.ControllerLayout and addon.ControllerLayout()
        for _, b in ipairs(choices) do b:SetSelected(b.key == layout) end
        page.gameSupport:SetShown(not PadOn())
        page.big:SetChecked(DB().speechTVOnPad and true or false)
        page.combat:SetChecked(DB().speechCombat == "hide")
        page.taxi:SetChecked(DB().speechHideOnTaxi == true)
        page.rumble:SetChecked(DB().controllerRumble ~= false)
        page.legend:SetChecked(DB().controllerShowLegend ~= false)
    end
    page.Refresh = Refresh

    local x = 0
    for _, opt in ipairs({ { "XBOX", "Xbox" }, { "PS", "PlayStation" }, { "KBM", "Keyboard & Mouse" } }) do
        local b = addon.UIK.Button(page, opt[2], 180, 30, function()
            if addon.SetControllerLayout then addon.SetControllerLayout(opt[1]) end
            Refresh()
        end)
        b:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", x, -14)
        b.key = opt[1]
        choices[#choices + 1] = b
        x = x + 190
    end

    page.gameSupport = addon.UIK.Button(page, "Turn on WoW's controller support", 260, 24, function()
        if SetCVar then SetCVar("GamePadEnable", "1") end
        print("|cff33ff99SpeakStone:|r controller support turned on. If the pad does nothing yet, /reload.")
        C_Timer.After(0.5, Refresh)
    end)
    page.gameSupport:SetPoint("TOPLEFT", choices[1], "BOTTOMLEFT", 0, -10)

    page.big = addon.UIK.Check(page, "TV / Sofa size on controller: big gliding text at top of screen")
    page.big:SetPoint("TOPLEFT", choices[1], "BOTTOMLEFT", 0, -46)
    page.big:SetHitRectInsets(0, -(page.big.text:GetStringWidth() + 6), 0, 0)
    page.big:SetScript("OnClick", function(self) ApplyTVSize(self:GetChecked()) end)

    page.combat = addon.UIK.Check(page, "Hide the speech bar in combat (the voice carries on)")
    page.combat:SetPoint("TOPLEFT", page.big, "BOTTOMLEFT", 0, -8)
    page.combat:SetHitRectInsets(0, -(page.combat.text:GetStringWidth() + 6), 0, 0)
    page.combat:SetScript("OnClick", function(self) DB().speechCombat = self:GetChecked() and "hide" or "show" end)

    page.taxi = addon.UIK.Check(page, "Hide the speech bar on flight paths")
    page.taxi:SetPoint("TOPLEFT", page.combat, "BOTTOMLEFT", 0, -8)
    page.taxi:SetHitRectInsets(0, -(page.taxi.text:GetStringWidth() + 6), 0, 0)
    page.taxi:SetScript("OnClick", function(self) DB().speechHideOnTaxi = self:GetChecked() and true or false end)

    page.rumble = addon.UIK.Check(page, "Rumble when a quest is queued or the next one starts")
    page.rumble:SetPoint("TOPLEFT", page.taxi, "BOTTOMLEFT", 0, -8)
    page.rumble:SetHitRectInsets(0, -(page.rumble.text:GetStringWidth() + 6), 0, 0)
    page.rumble:SetScript("OnClick", function(self)
        DB().controllerRumble = self:GetChecked() and true or false
        if self:GetChecked() and addon.Rumble then addon.Rumble("queue") end
    end)

    page.legend = addon.UIK.Check(page, "Show which button does what under the speech bar")
    page.legend:SetPoint("TOPLEFT", page.rumble, "BOTTOMLEFT", 0, -8)
    page.legend:SetHitRectInsets(0, -(page.legend.text:GetStringWidth() + 6), 0, 0)
    page.legend:SetScript("OnClick", function(self) DB().controllerShowLegend = self:GetChecked() and true or false end)

    local rec = addon.UIK.Button(page, "Apply recommended TV / Sofa settings", 280, 28, function()
        local db = DB()
        if not (db.controllerLayout == "XBOX" or db.controllerLayout == "PS") and addon.SetControllerLayout then
            addon.SetControllerLayout((addon.ControllerDetect and addon.ControllerDetect()) or "XBOX")
        end
        ApplyTVSize(true)
        db.speechCompact = true
        db.speechFitText = false
        db.speechAutoScroll = true
        db.speechCombat = "hide"
        db.speechHideOnTaxi = false
        db.controllerRumble = true
        db.controllerShowLegend = true
        db.autoAcceptQuests = true
        db.queueQuestSpeech = true
        db.showSpeechFrame = true
        Refresh()
        if addon.RefreshSettingChecks then addon.RefreshSettingChecks() end
        print("|cff33ff99SpeakStone:|r TV / Sofa controller settings on.")
    end)
    rec:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 4)
    rec:SetSelected(true)

    page:SetScript("OnShow", Refresh)
    addon.ThemeRegister(function() if page:IsShown() then Refresh() end end)
end

-- --------------------------------------------------------------------------
-- Step 2: Voice & Display (merges Listen + Walk Away + Speaker into 1 page!)
-- --------------------------------------------------------------------------
local function BuildVoiceAndDisplay()
    local page = NewPage("voice")
    local title = Title(page, "How should it read & look?")
    local hint = Body(page, title, "Pick your style — everything can be fine-tuned later in /ss.", 6)

    -- 2x2 listening preset grid
    local MAIN_PRESETS = { PROFILES[1], PROFILES[2], PROFILES[3], PROFILES[4] }
    local presetBtns = {}
    local cardW = math.floor((CONTENT - 10) / 2)
    for i, prof in ipairs(MAIN_PRESETS) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local b = addon.UIK.Button(page, "", cardW, 60, function()
            selectedProfile = prof.key
            ApplyProfile(prof.key)
            page.Refresh()
        end)
        b:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", col * (cardW + 10), -12 - row * 66)
        b.key = prof.key
        b.profileName = prof.name
        b.recommended = prof.recommended
        b.label:Hide()
        local name = Text(b, "GameFontNormal", cardW - 16)
        name.ssRole = false
        name:SetPoint("TOPLEFT", 10, -8)
        local desc = Text(b, "GameFontHighlightSmall", cardW - 18)
        desc.ssRole = false
        desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
        desc:SetText(prof.description)
        b.nameText, b.descText = name, desc
        presetBtns[#presetBtns + 1] = b
    end

    -- Walk-away display mode (Compact 4-line default / Subtitles / Audio only)
    local walkHead = Text(page, "GameFontNormal", CONTENT)
    walkHead:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -158)
    walkHead:SetText("When you walk away from an NPC:")

    local walkBtns = {}
    local walkSpecs = {
        { key = "bar",       label = "Compact 4-line bar (default)", w = 210 },
        { key = "subtitles", label = "Subtitles",                    w = 104 },
        { key = "none",      label = "Audio only",                   w = 104 },
    }
    local wx = 0
    for _, sp in ipairs(walkSpecs) do
        local b = addon.UIK.Button(page, sp.label, sp.w, 26, function()
            local db = DB()
            if sp.key == "bar" then
                db.showSubtitles = false
                db.showSpeechFrame = true
                db.speechCompact = true
                db.speechFitText = false
                db.speechAutoScroll = true
            elseif sp.key == "subtitles" then
                db.showSubtitles = true
            else
                db.showSubtitles = false
                db.showSpeechFrame = false
            end
            if addon.SpeechSettingChanged then
                for _, k in ipairs({ "showSubtitles", "showSpeechFrame", "speechCompact", "speechFitText" }) do
                    addon.SpeechSettingChanged(k)
                end
            end
            page.Refresh()
        end)
        b:SetPoint("TOPLEFT", walkHead, "BOTTOMLEFT", wx, -8)
        b.key = sp.key
        walkBtns[#walkBtns + 1] = b
        wx = wx + sp.w + 6
    end

    local previewBtn = addon.UIK.Button(page, "Preview", 82, 26, function()
        local db = DB()
        if db.showSubtitles then
            if addon.PreviewSubtitles then addon.PreviewSubtitles() end
        elseif db.showSpeechFrame ~= false then
            if addon.SpeechFramePreview then addon.SpeechFramePreview() end
        end
    end)
    previewBtn:SetPoint("TOPRIGHT", walkHead, "BOTTOMRIGHT", 0, -8)

    -- Speaker portrait (2D ring vs 3D moving head)
    local headLabel = Text(page, "GameFontNormal", CONTENT)
    headLabel:SetPoint("TOPLEFT", walkBtns[1], "BOTTOMLEFT", 0, -20)
    headLabel:SetText("Speaker portrait on the speech bar:")

    local headBtns = {}
    local hx = 0
    for _, sp in ipairs({
        { key = false, label = "2D Portrait Ring (default)", w = 195 },
        { key = true,  label = "Moving 3D Head",             w = 155 },
    }) do
        local b = addon.UIK.Button(page, sp.label, sp.w, 26, function()
            DB().speechPortrait3D = sp.key
            if addon.SpeechFrameRefreshPortrait then addon.SpeechFrameRefreshPortrait() end
            page.Refresh()
        end)
        b:SetPoint("TOPLEFT", headLabel, "BOTTOMLEFT", hx, -8)
        b.key = sp.key
        headBtns[#headBtns + 1] = b
        hx = hx + sp.w + 8
    end

    function page.Refresh()
        local db = DB()
        local ui = addon.Theme().ui
        selectedProfile = selectedProfile or db.profile or "full"
        for _, b in ipairs(presetBtns) do
            local sel = b.key == selectedProfile
            b:SetSelected(sel)
            local ink = sel and ui.button.textSel or ui.button.text
            b.nameText:SetTextColor(ink[1], ink[2], ink[3])
            b.descText:SetTextColor(ink[1], ink[2], ink[3])
            addon.ThemeShadow(b.nameText)
            addon.ThemeShadow(b.descText)
            b.nameText:SetText(b.profileName .. (b.recommended and ("  " .. Good() .. "(default)|r") or ""))
        end

        local mode = db.showSubtitles and "subtitles" or (db.showSpeechFrame ~= false and "bar" or "none")
        for _, b in ipairs(walkBtns) do b:SetSelected(b.key == mode) end
        previewBtn:SetShown(mode ~= "none")

        local isBar = mode == "bar"
        headLabel:SetShown(isBar)
        local is3d = db.speechPortrait3D == true
        for _, b in ipairs(headBtns) do
            b:SetShown(isBar)
            b:SetSelected(b.key == is3d)
        end
    end

    page:SetScript("OnShow", page.Refresh)
    addon.ThemeRegister(function() if page:IsShown() then page.Refresh() end end)
end

-- --------------------------------------------------------------------------
-- Step 3: While you play (trimmed to the 4 essential switches + combat pill)
-- --------------------------------------------------------------------------
local function BuildPlay()
    local page = NewPage("play")
    local title = Title(page, "While you play")
    local body = Body(page, title, "Just the essentials for when things get busy. More options live in /ss.", 6)

    local qCheck = Check(page, body, "queueQuestSpeech", "Queue quests instead of cutting one off",
        "Pick up several quests in a row and each waits its turn (with a Next button).", 16)

    -- 3-way combat selector
    local combatLbl = Text(page, "GameFontNormal", CONTENT)
    combatLbl:SetPoint("TOPLEFT", qCheck, "BOTTOMLEFT", 0, -16)
    combatLbl:SetText("During combat:")

    local combatBtns = {}
    local cx = 0
    for _, sp in ipairs({
        { key = "play", label = "Play normally",          w = 130 },
        { key = "wait", label = "Wait until combat ends", w = 175 },
        { key = "skip", label = "Skip in combat",         w = 130 },
    }) do
        local b = addon.UIK.Button(page, sp.label, sp.w, 24, function()
            local db = DB()
            db.pauseAutoPlayInCombat = (sp.key == "skip")
            db.waitForCombatEnd = (sp.key == "wait")
            if addon.SpeechSettingChanged then addon.SpeechSettingChanged("waitForCombatEnd") end
            page.Refresh()
        end)
        b:SetPoint("TOPLEFT", combatLbl, "BOTTOMLEFT", cx, -6)
        b.key = sp.key
        combatBtns[#combatBtns + 1] = b
        cx = cx + sp.w + 6
    end

    local duckCheck = Check(page, combatBtns[1], "duckOtherSounds", "Lower music and ambience while speaking",
        "Turns game music and ambience down during narration, then restores them.", 16)
    local acceptCheck = Check(page, duckCheck, "autoAcceptQuests", "Auto-accept quests (hold Shift to skip)",
        "Accepts quests immediately and reads them on the speech bar.", 10)
    local duiCheck = Check(page, acceptCheck, "syncDialogueText", "Follow voice in Dialogue UI's window",
        "With Dialogue UI installed, highlights each word as it is spoken.", 10)

    function page.Refresh()
        qCheck.Refresh()
        duckCheck.Refresh()
        acceptCheck.Refresh()
        duiCheck.Refresh()
        local db = DB()
        local cm = db.pauseAutoPlayInCombat and "skip" or (db.waitForCombatEnd and "wait" or "play")
        for _, b in ipairs(combatBtns) do b:SetSelected(b.key == cm) end
        duiCheck:SetShown(DialogueUIInstalled() and true or false)
    end
    page:SetScript("OnShow", page.Refresh)
end

-- --------------------------------------------------------------------------
-- Step 4: Ready to play (merges Where + Report + Help Grow + Done)
-- --------------------------------------------------------------------------
local ALERT = "|TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:14:14|t"

local function BuildDone()
    local page = NewPage("done")
    local title = Title(page, "You're all set!")
    local body = Body(page, title, "", 10)

    local growHead = Text(page, "GameFontNormal", CONTENT)
    growHead:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -18)
    growHead:SetText("Help fill the gaps (optional)")

    local grow = Text(page, "GameFontHighlightSmall", CONTENT)
    grow:SetPoint("TOPLEFT", growHead, "BOTTOMLEFT", 0, -4)
    grow:SetSpacing(3)

    local capture = Check(page, grow, "harvestEnabled", "Capture missing text as I play",
        "Records unvoiced quests, greetings and books (your character name is scrubbed).", 10,
        function() if addon.RefreshSettingsStatus then addon.RefreshSettingsStatus() end end)

    local export = addon.UIK.Button(page, "Export captured text", 170, 26, function()
        if addon.ShowHarvestExport then addon.ShowHarvestExport() end
    end)
    export:SetPoint("TOPLEFT", capture, "BOTTOMLEFT", 0, -10)

    local box = addon.UIK.CopyBox(page, WEBSITE_URL, CONTENT - 186)
    box:SetPoint("LEFT", export, "RIGHT", 14, 0)

    local guide = addon.UIK.Button(page, "Open SpeakStone Guide", 200, 28, function()
        if addon.OpenAudioLibrary then addon.OpenAudioLibrary() end
    end)
    guide:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 4)
    guide:SetSelected(true)

    local settings = addon.UIK.Button(page, "Open Settings", 140, 28, function()
        if addon.ShowSettings then addon:ShowSettings() end
    end)
    settings:SetPoint("LEFT", guide, "RIGHT", 8, 0)

    page:SetScript("OnShow", function()
        local g = Gold()
        local lead = defaultsApplied
            and (Good() .. "Recommended defaults applied|r (Full narration + Compact 4-line scrolling bar).\n\n")
            or ("Profile: " .. Good() .. (ProfileName(DB().profile) or "Custom") .. "|r\n\n")
        body:SetText(lead
            .. "Talk to any quest giver to hear SpeakStone in action. Three quick things to know:\n\n"
            .. "  - " .. g .. "/ss|r (or the minimap icon) opens Settings and the " .. g .. "SpeakStone Guide|r.\n"
            .. "  - " .. g .. "F6|r plays the current quest; right-click the speech bar to resize or lock it.\n"
            .. "  - Something sound wrong? Click the faint " .. ALERT .. " sign on the speech bar or Dialogue UI.")

        local waiting = 0
        if addon.HarvestCounts then
            local q, _, _, _, l, i = addon.HarvestCounts()
            waiting = (q or 0) + (l or 0) + (i or 0)
        end
        grow:SetText("Unvoiced quests, greetings, books and your " .. ALERT .. " reports are saved automatically"
            .. (waiting > 0 and (" (" .. Good() .. waiting .. " ready now|r)") or "")
            .. ". Export and paste them on the website — new lines are usually voiced by the next day.")
        capture.Refresh()
    end)
end

-- Short What's New page for returning players
local function BuildWhatsNew()
    local page = NewPage("whatsnew")
    local title = Title(page, "New in SpeakStone")
    local body = Body(page, title, "", 12)
    local full = addon.UIK.Button(page, "Run full 4-step setup", 180, 26, function()
        SetOrder(PadOn() and PAD_ORDER or KBM_ORDER)
        ShowPage(1)
    end)
    full:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -18)
    page:SetScript("OnShow", function()
        local g = Gold()
        body:SetText(g .. "Cleaner Settings window|r: slim top bar with clickable voice-pack and capture badges, four focused tabs, and smooth scrolling.\n\n"
            .. g .. "Compact 4-line scrolling bar|r is now the default, with Auto-scroll on.\n\n"
            .. g .. "TV / Sofa & Controller settings|r are now right inside /ss under TV & More.\n\n"
            .. g .. "Report a line|r: click the faint " .. ALERT .. " sign on the speech bar or Dialogue UI.")
    end)
end

-- --------------------------------------------------------------------------
-- Navigation & Window builder
-- --------------------------------------------------------------------------
function ShowPage(index)
    pageIndex = index
    local shown = order[index]
    for i, page in ipairs(pages) do
        page:SetShown(i == shown)
    end
    frame.back:SetShown(index > 1)
    frame.next:SetText(index == #order and "Finish" or "Next")
    local name = order.names[index]
    frame.step:SetText(string.format("Step %d of %d  \194\183  %s", index, #order, STEP_TITLES[name] or ""))
    if frame.nav then frame.nav.Reset() end
end

local function Build()
    frame = addon.UIK.Window("SpeakStoneTutorialFrame", WIDTH, HEIGHT, "SpeakStone Setup")
    tinsert(UISpecialFrames, "SpeakStoneTutorialFrame")

    frame.step = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.step:SetPoint("TOPLEFT", 30, -44)

    frame:HookScript("OnShow", function() addon.PlaceTutorial() end)

    function addon.PlaceTutorial()
        local self = frame
        if not self:IsShown() then return end
        local layout = DB().controllerLayout
        local pad = layout == "XBOX" or layout == "PS"
            or (layout == nil and addon.ControllerDetect and addon.ControllerDetect() ~= nil)
        local padScale = pad and 1.25 or 1
        self:SetScale(math.min(padScale, (UIParent:GetHeight() - 20) / HEIGHT))
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

    frame:HookScript("OnHide", function()
        if DB() and UIParent:IsShown() then DB().tutorialVersion = TUTORIAL_VERSION end
        if testHandle then testHandle:Stop() testHandle = nil end
        if DB() and not DB().profile and addon.isFreshInstall then ApplyDefaults() end
    end)

    frame.back = addon.UIK.Button(frame, "Back", 100, 28, function() ShowPage(pageIndex - 1) end)
    frame.back:SetPoint("BOTTOMLEFT", 24, 16)
    frame.next = addon.UIK.Button(frame, "Next", 120, 28, function()
        if pageIndex == #order then frame:Hide() else ShowPage(pageIndex + 1) end
    end)
    frame.next:SetPoint("BOTTOMRIGHT", -24, 16)
    frame.next:SetSelected(true)

    pages, pageByName = {}, {}
    BuildWelcome()
    BuildController()
    BuildVoiceAndDisplay()
    BuildPlay()
    BuildDone()
    BuildWhatsNew()
    SetOrder(KBM_ORDER)

    if addon.GamepadNav then
        frame.nav = addon.GamepadNav(frame, {
            start = function() return frame.next end,
            back = function() if pageIndex > 1 then ShowPage(pageIndex - 1) else frame:Hide() end end,
            prev = function() if pageIndex > 1 then ShowPage(pageIndex - 1) end end,
            next = function() if pageIndex == #order then frame:Hide() else ShowPage(pageIndex + 1) end end,
            close = function() frame:Hide() end,
            onLayout = function()
                addon.PlaceTutorial()
                local page = pages[order[pageIndex]]
                if page and page.Refresh then page.Refresh() end
            end,
        })
    end
end

function addon.ShowTutorial(page, whatsNew)
    if not DB() then return end
    if not frame then Build() end
    local names = whatsNew and SHORT_ORDER or (PadOn() and PAD_ORDER or KBM_ORDER)
    SetOrder(names)
    selectedProfile = nil
    defaultsApplied = false
    frame:Show()
    addon.PlaceTutorial()
    ShowPage(page or 1)
end

function addon.MaybeShowTutorial()
    local db = DB()
    local seen = db and db.tutorialVersion or 0
    if not db or seen >= TUTORIAL_VERSION then return false end
    if seen == 4 and not PadOn() then
        db.tutorialVersion = TUTORIAL_VERSION
        return false
    end
    addon.ShowTutorial(1, seen >= 1)
    return true
end
