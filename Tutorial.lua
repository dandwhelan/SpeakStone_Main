local addonName, addon = ...

-- First-start setup and the premade settings profiles. Shown at login until the player closes it
-- (tutorialVersion), and again on demand with /ss tutorial or the Tutorial button in the settings window.
--
-- The flow follows what a player decides, in the order they meet it:
--   1. Welcome and voice packs  -- is there audio to play?
--   2. How to listen            -- a profile: what is read, and how much
--   3. When you walk away      -- nothing, subtitles or the text box, each with a live sample
--   4. How it looks             -- theme, font, size and the subtitle colours
--   5. While you play           -- combat, instances, queueing
--   6. Where things are         -- the Guide, the buttons, the keys
--   7. Help the project         -- capture and the website (optional)
--   8. Done
-- Players who saw an older setup get a short run instead: what's new, how it looks, done.

-- Bump to show the setup once more to everyone, e.g. after adding a page.
-- 2: the speech bar page. 3: the flow rebuilt (look, behaviour, the Guide); players who saw version 2 get the short run.
local TUTORIAL_VERSION = 3

local CURSEFORGE_URL = "https://www.curseforge.com/members/dandwhelan/projects"
local WEBSITE_URL = "https://speakstone.beanw.co.uk"

-- Every profile sets every playback option, so picking one gives the same result whatever the player had
-- before. Interface and capture options are left alone except where the profile is about them.
local PROFILES = {
    {
        key = "full",
        name = "Full narration",
        recommended = true,
        description = "Everything read aloud: quests, NPC greetings and books. Blizzard's own voice lines are silenced so nothing talks over SpeakStone.",
        settings = {
            autoPlayEnabled = true, autoPlayQuests = true, autoPlayGossip = true, autoPlayItemText = true,
            autoPlayInQuestMap = false, muteGossip = true, yieldToNPCVoice = true,
            stopDialogueOnClose = false, showDebugMessages = false, harvestEnabled = true,
            autoPlayDelay = 1.0,
            showSpeechFrame = true, speechAutoScroll = true, speechFitText = false, queueQuestSpeech = false,
            showSubtitles = false,
        },
    },
    {
        key = "subtitles",
        name = "Read along",
        description = "Full narration with subtitles over the world: the words type out as the voice reaches them and the word being read is lit. Good if you are hard of hearing, play with the sound low, or like to follow the text.",
        settings = {
            autoPlayEnabled = true, autoPlayQuests = true, autoPlayGossip = true, autoPlayItemText = true,
            autoPlayInQuestMap = false, muteGossip = true, yieldToNPCVoice = true,
            stopDialogueOnClose = false, showDebugMessages = false, harvestEnabled = true,
            autoPlayDelay = 1.0,
            showSpeechFrame = true, speechAutoScroll = true, speechFitText = true, queueQuestSpeech = true,
            showSubtitles = true, subtitleTypeOut = true, subtitleHighlight = true,
        },
    },
    {
        key = "story",
        name = "Story only",
        description = "Quests and books are read; passing NPC greetings stay quiet. Quests you pick up in a row wait their turn instead of cutting each other off.",
        settings = {
            autoPlayEnabled = true, autoPlayQuests = true, autoPlayGossip = false, autoPlayItemText = true,
            autoPlayInQuestMap = false, muteGossip = true, yieldToNPCVoice = true,
            stopDialogueOnClose = false, showDebugMessages = false, harvestEnabled = true,
            autoPlayDelay = 1.0,
            showSpeechFrame = true, speechAutoScroll = true, speechFitText = false, queueQuestSpeech = true,
            showSubtitles = false,
        },
    },
    {
        key = "blizzard",
        name = "Blizzard first",
        description = "Blizzard's own voice acting plays where it exists, and SpeakStone waits for it before filling the silence.",
        settings = {
            autoPlayEnabled = true, autoPlayQuests = true, autoPlayGossip = true, autoPlayItemText = true,
            autoPlayInQuestMap = false, muteGossip = false, yieldToNPCVoice = true,
            stopDialogueOnClose = false, showDebugMessages = false, harvestEnabled = true,
            autoPlayDelay = 1.5,
            showSpeechFrame = true, speechAutoScroll = true, speechFitText = false, queueQuestSpeech = false,
            showSubtitles = false,
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
            showSubtitles = false,
        },
    },
    {
        key = "helper",
        name = "Helper / tester",
        description = "Full narration plus debug messages in chat and text capture on, for reporting problems and helping voice missing quests.",
        settings = {
            autoPlayEnabled = true, autoPlayQuests = true, autoPlayGossip = true, autoPlayItemText = true,
            autoPlayInQuestMap = true, muteGossip = true, yieldToNPCVoice = true,
            stopDialogueOnClose = false, showDebugMessages = true, harvestEnabled = true,
            autoPlayDelay = 1.0,
            showSpeechFrame = true, speechAutoScroll = true, speechFitText = false, queueQuestSpeech = false,
            showSubtitles = false,
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
                for _, option in ipairs({ "speechFitText", "queueQuestSpeech", "speechSize", "showSubtitles", "subtitleTypeOut",
                                          "subtitleHighlight" }) do
                    addon.SpeechSettingChanged(option)
                end
            end
            if addon.UpdateMinimapButtonVisibility then addon.UpdateMinimapButtonVisibility() end
            if addon.UpdateQuestButtonVisibility then addon.UpdateQuestButtonVisibility() end
            -- The settings window reads everything in OnShow; if it is open, cycle it so the checkboxes and
            -- sliders show the new values.
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

-- "I don't care, let me play": the recommended choices in one go. Full narration, the text box with the whole passage
-- (and the word being read lit), words lit on Blizzard's talking heads, and in Dialogue UI's window if it is installed.
local function DialogueUIInstalled()
    return (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("DialogueUI")) or _G.DUIQuestFrame
end

local DEFAULTS_LIST = {
    "Full narration: quests, NPC greetings and books are read aloud",
    "When you walk away: the text box with the whole passage, and the word being said lit",
    "The words are lit on Blizzard's talking heads",
    "Quests queue instead of cutting each other off",
}
if addon.IS_FOREVER then table.remove(DEFAULTS_LIST, 3) end   -- WoW Forever has no talking heads

local function ApplyDefaults()
    ApplyProfile("full")
    local db = DB()
    db.showSubtitles = false
    db.showSpeechFrame = true
    db.speechFitText = true
    db.speechAutoScroll = true
    db.subtitleHighlight = true
    db.subtitleTypeOut = true
    db.talkingHeadHighlight = not addon.IS_FOREVER
    db.queueQuestSpeech = true
    db.syncDialogueText = DialogueUIInstalled() and true or false
    if addon.SpeechSettingChanged then
        for _, key in ipairs({ "showSubtitles", "showSpeechFrame", "speechFitText", "subtitleHighlight", "queueQuestSpeech",
                               "talkingHeadHighlight", "syncDialogueText" }) do
            addon.SpeechSettingChanged(key)
        end
    end
end
addon.ApplyTutorialDefaults = ApplyDefaults
local defaultsApplied = false

-- Which voice packs are not installed, by name, from the same list the Guide's Voice packs tab uses.
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
local WIDTH, HEIGHT = 640, 580
local CONTENT = WIDTH - 60
local frame, pages, pageIndex
local order, pageByName
local ShowPage
local FULL_ORDER = { "welcome", "listen", "words", "look", "play", "where", "help", "done" }
local SHORT_ORDER = { "whatsnew", "look", "done" }
local STEP_TITLES = {
    welcome = "Welcome", listen = "How to listen", words = "When you walk away", look = "How it looks", play = "While you play",
    where = "Where things are", help = "Help the project", done = "Done", whatsnew = "What's new",
}
local selectedProfile

-- Colour codes for text written into the pages: the theme's, so they read on paper as well as on dark.
local function Gold() return addon.Theme().titleCode end
local function Good() return addon.Theme().light and "|cff1b6b2a" or "|cff00ff00" end
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
    body:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(gap or 12))
    body:SetSpacing(4)
    body:SetText(text)
    return body
end

local function CopyBox(parent, url, width)
    return addon.UIK.CopyBox(parent, url, width)
end

-- A tick box tied to a saved setting.
local function Check(page, anchor, key, label, tip, gap, onChange)
    local check = addon.UIK.Check(page, label)
    check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", anchor.isCheck and 0 or 0, -(gap or 6))
    check.isCheck = true
    check:SetHitRectInsets(0, -(check.text:GetStringWidth() + 6), 0, 0)
    function check.Refresh()
        check:SetChecked(DB()[key] and true or false)
    end
    check:SetScript("OnClick", function(self)
        DB()[key] = self:GetChecked() and true or false
        if onChange then onChange() end
        if addon.SpeechSettingChanged then addon.SpeechSettingChanged(key) end
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
    page:SetPoint("TOPLEFT", 30, -78)
    page:SetPoint("BOTTOMRIGHT", -30, 58)
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

-- 1. Welcome, and whether there is audio
local function BuildWelcome()
    local page = NewPage("welcome")
    local title = Title(page, "Welcome to SpeakStone")
    local body = Body(page, title, "", 14)

    local packTitle = Text(page, "GameFontNormalLarge", CONTENT)
    packTitle:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -22)
    packTitle:SetText("Voice packs")
    local status = Text(page, "GameFontHighlight", CONTENT)
    status:SetPoint("TOPLEFT", packTitle, "BOTTOMLEFT", 0, -8)
    status:SetSpacing(4)
    local test = addon.UIK.Button(page, "Test a voice", 140, 26, function()
        if not PlayTestClip() then
            print("|cff33ff99SpeakStone:|r no audio pack installed yet, so there is nothing to play.")
        end
    end)
    test:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -14)
    local linkLabel = Text(page, "GameFontNormalSmall")
    linkLabel:SetPoint("TOPLEFT", test, "BOTTOMLEFT", 0, -16)
    linkLabel:SetText("All SpeakStone addons on CurseForge (Ctrl+C to copy):")
    local box = CopyBox(page, CURSEFORGE_URL, CONTENT - 20)
    box:SetPoint("TOPLEFT", linkLabel, "BOTTOMLEFT", 6, -6)

    -- For anyone who just wants to play: every recommended choice at once, then straight to the end.
    local skip = addon.UIK.Button(page, "I don't care, let me play", 240, 30, function()
        ApplyDefaults()
        defaultsApplied = true
        selectedProfile = "full"
        ShowPage(#order)
    end)
    skip:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 6)
    skip:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Use the defaults", 1, 0.82, 0)
        GameTooltip:AddLine("Skips the questions and picks the recommended choices:\n" .. table.concat(DEFAULTS_LIST, "\n")
            .. "\nYou can change any of it later in /ss.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    skip:HookScript("OnLeave", function() GameTooltip:Hide() end)

    page:SetScript("OnShow", function()
        body:SetText("SpeakStone reads quests, NPC greetings and books aloud, with voices similar to the in-game NPCs. "
            .. "Unofficial; not affiliated with Blizzard Entertainment.\n\nThis takes about a minute: how to listen, how the words "
            .. "show, how it looks, how it behaves while you play, and where things are. You can come back to it any time with "
            .. Gold() .. "/ss tutorial|r.")
        if HasAnyAudioPack() then
            local missing, have, total = MissingPackNames()
            local line
            if missing and #missing > 0 then
                line = Good() .. "Voice packs found" .. (have and total and (": " .. have .. " of " .. total .. " installed") or "") .. ".|r "
                    .. Bad() .. "Missing: " .. table.concat(missing, ", ") .. ".|r Get them on CurseForge (address below). "
                    .. "Press Test a voice to hear one."
            else
                line = Good() .. "Every voice pack is installed.|r Press Test a voice to hear one. "
                    .. "Packs are updated now and then, so look on CurseForge for new ones."
            end
            status:SetText(line)
            test:Enable()
        else
            status:SetText(Bad() .. "No voice packs installed.|r SpeakStone has nothing to play until you add some. "
                .. "Get them on CurseForge (the address is below); they are always being updated and improved."
                .. (addon.AUDIO_PACK_EXTRA_NOTE or ""))
            test:Disable()
        end
        -- This page covers the one-off audio-pack popup.
        DB().audioPackPromptShown = true
    end)
end

-- 2. How to listen: a profile
local function BuildListen()
    local page = NewPage("listen")
    local title = Title(page, "How should it read to you?")
    local hint = Text(page, "GameFontHighlightSmall", CONTENT)
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    hint:SetText("Pick the closest; every option can be changed afterwards in /ss. Skip this and Full narration is used on a new install.")

    local buttons = {}
    local function Refresh()
        local ui = addon.Theme().ui
        for _, button in ipairs(buttons) do
            local selected = button.key == selectedProfile
            button:SetSelected(selected)
            -- Text on the button is drawn in the button's own ink, not the page's.
            local ink = selected and ui.button.textSel or ui.button.text
            button.nameText:SetTextColor(ink[1], ink[2], ink[3])
            button.descText:SetTextColor(ink[1], ink[2], ink[3])
            addon.ThemeShadow(button.nameText)
            addon.ThemeShadow(button.descText)
            button.nameText:SetText(button.profileName .. (button.recommended and ("  " .. Good() .. "(recommended)|r") or ""))
        end
    end
    page:SetScript("OnShow", function()
        selectedProfile = selectedProfile or DB().profile
        Refresh()
    end)
    addon.ThemeRegister(function() if page:IsShown() then Refresh() end end)
    local y = -50
    for _, profile in ipairs(PROFILES) do
        local button = addon.UIK.Button(page, "", CONTENT, 54, function()
            selectedProfile = profile.key
            ApplyProfile(profile.key)
            Refresh()
        end)
        button:SetPoint("TOPLEFT", 0, y)
        button.key = profile.key
        button.profileName, button.recommended = profile.name, profile.recommended
        button.label:Hide()
        local name = Text(button, "GameFontNormal", CONTENT - 20)
        name.ssRole = false
        name:SetPoint("TOPLEFT", 10, -6)
        local desc = Text(button, "GameFontHighlightSmall", CONTENT - 24)
        desc.ssRole = false
        desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
        desc:SetText(profile.description)
        button.nameText, button.descText = name, desc
        buttons[#buttons + 1] = button
        y = y - 58
    end
end

-- 3. When you walk away: nothing, subtitles, or the text box -- each with a live sample
local function BuildWords()
    local page = NewPage("words")
    local title = Title(page, "Once you walk away, what do you want to see?")
    local hint = Text(page, "GameFontHighlightSmall", CONTENT)
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    hint:SetText("While you talk to an NPC, the quest window shows the text. Once you walk away mid-line (or accept a quest automatically), pick ONE of these:")

    -- What each choice sets. Subtitles and the text box are exclusive: with subtitles on, the speech frame stays away.
    local CHOICES = {
        { key = "nothing", name = "A.  Just listen",
          desc = "Nothing appears. You only hear the voice.",
          apply = function(db) db.showSubtitles = false; db.showSpeechFrame = false end },
        { key = "subtitles", name = "B.  Subtitles", style = "bar",
          desc = "A few words at a time in a small bar over the game, as the voice says them. You choose its colours on the next page.",
          apply = function(db) db.showSubtitles = true end },
        { key = "box", name = "C.  Text box", style = "box",
          desc = "The whole passage at once in one box, with Pause, Stop and Replay. The word being said is lit as it goes.",
          apply = function(db) db.showSubtitles = false; db.showSpeechFrame = true; db.speechFitText = true; db.speechAutoScroll = true end },
    }
    local function Current()
        local db = DB()
        if db.showSubtitles then return "subtitles" end
        if db.showSpeechFrame ~= false then return "box" end
        return "nothing"
    end

    local buttons = {}
    local function Refresh()
        local ui = addon.Theme().ui
        local current = Current()
        for _, button in ipairs(buttons) do
            local selected = button.key == current
            button:SetSelected(selected)
            button.tick:SetShown(selected)
            button.pick:SetText(selected and "Chosen" or "Click to choose")
            local ink = selected and ui.button.textSel or ui.button.text
            for _, fs in ipairs({ button.nameText, button.descText, button.pick }) do
                fs:SetTextColor(ink[1], ink[2], ink[3])
                addon.ThemeShadow(fs)
            end
        end
    end
    local previous = hint
    for _, choice in ipairs(CHOICES) do
        local button = addon.UIK.Button(page, "", CONTENT, 84, function()
            local db = DB()
            choice.apply(db)
            if addon.SpeechSettingChanged then
                for _, key in ipairs({ "showSubtitles", "showSpeechFrame", "speechFitText" }) do addon.SpeechSettingChanged(key) end
            end
            Refresh()
        end)
        button:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, previous == hint and -10 or -6)
        button.key = choice.key
        button.label:Hide()
        if choice.style then
            local preview = addon.UIK.WordPreview(button, 236, 72, choice.style)
            preview:SetPoint("TOPLEFT", button, "TOPLEFT", 6, -6)
            preview:EnableMouse(false)
        else
            local blank = CreateFrame("Frame", nil, button)
            blank:SetSize(236, 72)
            blank:SetPoint("TOPLEFT", button, "TOPLEFT", 6, -6)
            blank.bg = blank:CreateTexture(nil, "BACKGROUND")
            blank.bg:SetAllPoints()
            blank.bg:SetColorTexture(0, 0, 0, 0.18)
            blank.text = blank:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            blank.text.ssRole = false
            blank.text:SetPoint("CENTER")
            blank.text:SetText("Audio only")
            blank.text:SetTextColor(0.85, 0.85, 0.85)
        end
        button.tick = button:CreateTexture(nil, "OVERLAY")
        button.tick:SetSize(22, 22)
        button.tick:SetPoint("TOPRIGHT", button, "TOPRIGHT", -8, -8)
        button.tick:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        button.pick = Text(button, "GameFontHighlightSmall", 140, "RIGHT")
        button.pick.ssRole = false
        button.pick:SetJustifyH("RIGHT")
        button.pick:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -10, 8)
        local name = Text(button, "GameFontNormal", CONTENT - 290)
        name.ssRole = false
        name:SetPoint("TOPLEFT", button, "TOPLEFT", 254, -8)
        name:SetText(choice.name)
        local desc = Text(button, "GameFontHighlightSmall", CONTENT - 290)
        desc.ssRole = false
        desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
        desc:SetSpacing(2)
        desc:SetText(choice.desc)
        button.nameText, button.descText = name, desc
        buttons[#buttons + 1] = button
        previous = button
    end

    -- Extras that do not depend on walking away
    local extrasTitle = Text(page, "GameFontNormal", CONTENT)
    extrasTitle:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -12)
    extrasTitle:SetText("Also, for any of them (optional)")
    local effects = addon.UIK.Check(page, "Type the words out as they are said (subtitles)")
    effects:SetPoint("TOPLEFT", extrasTitle, "BOTTOMLEFT", 0, -6)
    effects:SetHitRectInsets(0, -(effects.text:GetStringWidth() + 6), 0, 0)
    effects:SetScript("OnClick", function(self)
        DB().subtitleTypeOut = self:GetChecked() and true or false
        if addon.SpeechSettingChanged then addon.SpeechSettingChanged("subtitleTypeOut") end
    end)
    local lit = addon.UIK.Check(page, "Light the word being read")
    lit:SetPoint("LEFT", effects, "LEFT", 360, 0)
    lit:SetHitRectInsets(0, -(lit.text:GetStringWidth() + 6), 0, 0)
    lit:SetScript("OnClick", function(self)
        DB().subtitleHighlight = self:GetChecked() and true or false
        if addon.SpeechSettingChanged then addon.SpeechSettingChanged("subtitleHighlight") end
    end)
    local dui = Check(page, effects, "syncDialogueText", "While the quest window is open: light the words in Dialogue UI's window",
        "With the Dialogue UI addon, its quest text follows the voice, word by word, while the window is open.", 8)
    local head = Check(page, dui, "talkingHeadHighlight", "Light the words on Blizzard's talking heads",
        "Blizzard's talking head shows its words whole; this lights the word being read as the line plays.", 6)

    page:SetScript("OnShow", function()
        Refresh()
        effects:SetChecked(DB().subtitleTypeOut ~= false)
        lit:SetChecked(DB().subtitleHighlight ~= false)
        dui.Refresh()
        head.Refresh()
        local installed = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("DialogueUI")) or _G.DUIQuestFrame
        if installed then dui:Enable() else dui:Disable() end
        if addon.IS_FOREVER or not _G.TalkingHeadFrame then head:Disable() end
    end)
    addon.ThemeRegister(function() if page:IsShown() then Refresh() end end)
end

-- 4. How it looks: theme, font, size
local function BuildLook()
    local page = NewPage("look")
    local title = Title(page, "Make it easy to read")
    local body = Text(page, "GameFontHighlightSmall", CONTENT)
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    body:SetText("Choose how SpeakStone's windows and subtitles look. A font made to be easier on the eye can help readers with dyslexia; try them. More colours are in /ss under Look.")

    local themeLabel = Text(page, "GameFontNormal")
    themeLabel:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -14)
    themeLabel:SetText("Theme")
    local themes = addon.UIK.ThemeButtons(page, CONTENT - 120)
    themes:SetPoint("LEFT", themeLabel, "LEFT", 120, 0)

    local fontLabel = Text(page, "GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", themeLabel, "BOTTOMLEFT", 0, -24)
    fontLabel:SetText("Reading font")
    local drop = addon.UIK.FontDropdown(page, 240)
    drop:SetPoint("LEFT", fontLabel, "LEFT", 120, 0)

    local sizeLabel = Text(page, "GameFontNormal")
    sizeLabel:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", 0, -26)
    sizeLabel:SetText("Text size")
    local slider = addon.UIK.Slider(page, 240)
    slider:SetPoint("LEFT", sizeLabel, "LEFT", 124, 0)
    slider:SetMinMaxValues(14, 36)
    slider:SetValueStep(2)
    slider:SetObeyStepOnDrag(true)
    slider.low:SetText("14")
    slider.high:SetText("36")
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 2 + 0.5) * 2
        DB().subtitleFontSize = value
        self.caption:SetText(tostring(value))
        if addon.SpeechSettingChanged then addon.SpeechSettingChanged("subtitleFontSize") end
    end)
    slider.caption:ClearAllPoints()
    slider.caption:SetPoint("LEFT", slider, "RIGHT", 12, 0)

    local preview = addon.UIK.FontPreview(page, CONTENT, 66)
    preview:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", 0, -42)

    -- The subtitle colours: background, text, and the word being read.
    local back = addon.UIK.SwatchRow(page, "Subtitle background", "subtitleBack", addon.SubtitleBackColours, "theme",
        { "The theme's own background.", "The colour behind the subtitle text. Soft cream, yellow, blue or green with dark text is easier on the eyes for many readers with dyslexia." }, 150)
    back:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -14)
    local ink = addon.UIK.SwatchRow(page, "Subtitle text", "subtitleText", addon.SubtitleTextColours, "theme",
        { "The theme's own text colour.", "The colour of the subtitle text. Dark blue or dark brown on a light background, or white or yellow on a dark one." }, 150)
    ink:SetPoint("TOPLEFT", back, "BOTTOMLEFT", 0, -6)
    local colour = addon.UIK.SwatchRow(page, "Word being read", "highlightColour", addon.HighlightColours, "auto",
        { "Gold, or deep red on light paper.", "The colour of the word being read." }, 150)
    colour:SetPoint("TOPLEFT", ink, "BOTTOMLEFT", 0, -6)
    local try = addon.UIK.Button(page, "Preview the subtitles over the world", 270, 26, function()
        if addon.PreviewSubtitles then addon.PreviewSubtitles() end
    end)
    try:SetPoint("TOPLEFT", colour, "BOTTOMLEFT", 0, -12)

    page:SetScript("OnShow", function()
        slider:SetValue(tonumber(DB().subtitleFontSize) or 18)
        slider.caption:SetText(tostring(tonumber(DB().subtitleFontSize) or 18))
    end)
end

-- 4. While you play
local function BuildPlay()
    local page = NewPage("play")
    local title = Title(page, "While you play")
    local body = Text(page, "GameFontHighlightSmall", CONTENT)
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    body:SetText("How SpeakStone behaves when things get busy. All of these are in /ss under Playback.")
    local checks = {}
    local previous = body
    local first = true
    for _, spec in ipairs({
        { "queueQuestSpeech", "Queue quests instead of cutting one off",
          "Talk to a second quest giver while the first is still being read and the new quest waits its turn (1/2 and a Next button)." },
        { "waitForCombatEnd", "Wait for combat to end before reading a quest",
          "A quest line that comes up in combat waits and plays once the fight is over." },
        { "pauseAutoPlayInInstances", "Stay quiet in dungeons, raids and battlegrounds",
          "Nothing starts reading by itself inside an instance. Read Quest and the keybind still work." },
        { "skipHeardQuests", "Skip quests I have already heard",
          "Autoplay leaves a quest passage alone once you have heard it, on any character." },
        { "stopDialogueOnClose", "Stop narration when I close the window",
          "Walking away mid-sentence stops the audio instead of leaving a voice following you." },
        { "autoAcceptQuests", "Auto-accept quests (hold Shift to skip)",
          "Accept quests as soon as they are offered and hear them on the subtitles or speech bar instead." },
    }) do
        local check = Check(page, previous, spec[1], spec[2], spec[3], first and 18 or 12)
        first = false
        checks[#checks + 1] = check
        previous = check
    end
    page:SetScript("OnShow", function()
        for _, check in ipairs(checks) do check.Refresh() end
    end)
end

-- 6. Where things are
local function BuildWhere()
    local page = NewPage("where")
    local title = Title(page, "Where things are")
    local body = Body(page, title, "", 14)
    page:SetScript("OnShow", function()
        local g = Gold()
        body:SetText(g .. "SpeakStone Guide|r: " .. g .. "/ss|r, then Open the Guide. Browse every voiced quest, greeting and book by "
            .. "expansion, zone, NPC or title, read the words and read along as it plays.\n\n"
            .. "|TInterface\\AddOns\\" .. addonName .. "\\cs_icon.tga:16:16|t  " .. g .. "Minimap button|r: left-click opens settings, "
            .. "right-click exports captured text.\n\n"
            .. g .. "Read Quest button|r: at the bottom of the quest window and the quest log. Plays, or replays, the current quest.\n\n"
            .. g .. "Subtitles and speech bar|r: right-click for size, position and options; Ctrl and the mouse wheel resize the subtitles.\n\n"
            .. g .. "Keys|r: F6 plays the current quest. Set a Pause / resume key in the game's Key Bindings, under SpeakStone.\n\n"
            .. g .. "/ss|r settings   " .. g .. "/sslibrary|r the Guide   " .. g .. "/sstoggle|r stop or replay   "
            .. g .. "/ssmissing|r quests with no audio yet")
    end)
end

-- 7. Help the project
local function BuildHelp()
    local page = NewPage("help")
    local title = Title(page, "Help SpeakStone grow")
    local voiceHead = Text(page, "GameFontNormal")
    voiceHead:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -14)
    voiceHead:SetText("Share what you capture")
    local share = Text(page, "GameFontHighlight", CONTENT)
    share:SetPoint("TOPLEFT", voiceHead, "BOTTOMLEFT", 0, -4)
    share:SetSpacing(3)
    share:SetText("New voices are built from text the community submits. As you play, SpeakStone captures quests, NPC talk, "
        .. "books and items that are not voiced yet. Export it, then paste it on the website.")

    local stats = {}
    local statWidth = math.floor((CONTENT - 12) / 3)
    for i, label in ipairs({ "QUESTS", "NPC TALK", "BOOKS AND ITEMS" }) do
        local tile = CreateFrame("Frame", nil, page)
        tile:SetSize(statWidth, 46)
        tile:SetPoint("TOPLEFT", share, "BOTTOMLEFT", (i - 1) * (statWidth + 6), -12)
        tile.bg = tile:CreateTexture(nil, "BACKGROUND")
        tile.bg:SetAllPoints()
        tile.ssCardBg = tile.bg
        local value = tile:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        value:SetPoint("TOP", 0, -5)
        local name = tile:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        name:SetPoint("BOTTOM", 0, 5)
        name:SetText(label)
        stats[i] = value
        if i == 1 then page.statsAnchor = tile end
    end

    local capture = Check(page, page.statsAnchor, "harvestEnabled", "Capture text as I play",
        "Records the text of quests, greetings and books you meet. Your character's name is replaced before anything is stored.", 12,
        function() if addon.RefreshSettingsStatus then addon.RefreshSettingsStatus() end end)
    local export = addon.UIK.Button(page, "Export captured text", 190, 26, function()
        if addon.ShowHarvestExport then addon.ShowHarvestExport() end
    end)
    export:SetPoint("LEFT", capture, "LEFT", CONTENT - 190, 0)

    local lend = Text(page, "GameFontNormal")
    lend:SetPoint("TOPLEFT", capture, "BOTTOMLEFT", 0, -22)
    lend:SetText("Lend your voice")
    local lendText = Text(page, "GameFontHighlight", CONTENT)
    lendText:SetPoint("TOPLEFT", lend, "BOTTOMLEFT", 0, -4)
    lendText:SetText("Want your voice in the quest voice pool? Visit the website and click Lend your voice. You can record straight from "
        .. "your browser or upload a clip.")
    local linkLabel = Text(page, "GameFontNormalSmall")
    linkLabel:SetPoint("TOPLEFT", lendText, "BOTTOMLEFT", 0, -12)
    linkLabel:SetText("Website (Ctrl+C to copy):")
    local box = CopyBox(page, WEBSITE_URL, CONTENT - 20)
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
        capture.Refresh()
    end)
end

-- 8. Done
local function BuildDone()
    local page = NewPage("done")
    local title = Title(page, "All set")
    local body = Body(page, title, "", 14)
    local guide = addon.UIK.Button(page, "Open the SpeakStone Guide", 220, 30, function()
        if addon.OpenAudioLibrary then addon.OpenAudioLibrary() end
    end)
    guide:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -22)
    local settings = addon.UIK.Button(page, "Open settings", 160, 30, function()
        if addon.ShowSettings then addon:ShowSettings() end
    end)
    settings:SetPoint("LEFT", guide, "RIGHT", 8, 0)
    page:SetScript("OnShow", function()
        local current = ProfileName(DB().profile)
        local chosen = ""
        if defaultsApplied then
            chosen = Good() .. "All the defaults are set:|r\n  - " .. table.concat(DEFAULTS_LIST, "\n  - ")
                .. "\n  - Dialogue UI's window lit too, if you use it\nChange any of it later in /ss.\n\n"
        elseif current then
            chosen = "Profile: " .. Good() .. current .. "|r\n\n"
        end
        body:SetText(chosen
            .. "Talk to a quest giver to hear SpeakStone in action.\n\n"
            .. "Wrong voice or missing audio? Report it from the settings window (/ss), under General.\n\n"
            .. "Thanks for helping voice Azeroth. Every capture you submit and every voice you lend makes the next pack better.")
    end)
end

-- Short run: what changed since the setup they saw
local function BuildWhatsNew()
    local page = NewPage("whatsnew")
    local title = Title(page, "New in SpeakStone")
    local body = Body(page, title, "", 14)
    local full = addon.UIK.Button(page, "See the full tutorial", 180, 26, function()
        SetOrder(FULL_ORDER)
        ShowPage(1)
    end)
    full:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -18)
    page:SetScript("OnShow", function()
        local g = Gold()
        body:SetText(g .. "The SpeakStone Guide|r is rebuilt: browse every voiced quest by expansion, zone, NPC or title, "
            .. "with the words of each quest and a read-along.\n\n"
            .. g .. "Subtitles|r over the world, with the word being read lit, plus the same in Dialogue UI's window and Blizzard's talking heads.\n\n"
            .. g .. "Three themes, a reading font and your own colours|r, made with readers who find some text harder in mind.\n\n"
            .. g .. "A tidier settings window|r: Playback, Sound, On screen, Look and General.\n\n"
            .. "Next: choose how it looks.")
    end)
end

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
end

local function Build()
    frame = addon.UIK.Window("SpeakStoneTutorialFrame", WIDTH, HEIGHT, "SpeakStone tutorial")
    tinsert(UISpecialFrames, "SpeakStoneTutorialFrame")

    frame.step = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.step:SetPoint("TOPLEFT", 30, -46)

    -- Beside Settings rather than on top of it: left if it fits, else right; when neither side has room,
    -- Settings slides over to make space.
    frame:HookScript("OnShow", function() addon.PlaceTutorial() end)

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

    frame:HookScript("OnHide", function()
        -- Done only once the player has actually had it in front of them and closed it; marking it on show
        -- lost it to whatever hid it at login. UIParent hiding (Alt+Z, a cinematic) fires this too; not a close.
        if DB() and UIParent:IsShown() then DB().tutorialVersion = TUTORIAL_VERSION end
        if testHandle then StopSound(testHandle) testHandle = nil end
        -- Closed without picking a profile: a fresh install gets the recommended one; an existing player
        -- keeps the settings they already had.
        if DB() and not DB().profile and addon.isFreshInstall then ApplyProfile("full") end
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
    BuildListen()
    BuildWords()
    BuildLook()
    BuildPlay()
    BuildWhere()
    BuildHelp()
    BuildDone()
    BuildWhatsNew()
    SetOrder(FULL_ORDER)
end

-- page: optional start page (2 = how to listen). whatsNew: the short run for players who saw an older version.
function addon.ShowTutorial(page, whatsNew)
    if not DB() then return end
    if not frame then Build() end
    SetOrder(whatsNew and SHORT_ORDER or FULL_ORDER)
    selectedProfile = nil
    defaultsApplied = false
    frame:Show()
    -- Show() on an already-open frame does not fire OnShow.
    addon.PlaceTutorial()
    ShowPage(page or 1)
end

-- Called from PLAYER_LOGIN. Returns true if the setup was shown.
function addon.MaybeShowTutorial()
    local db = DB()
    local seen = db and db.tutorialVersion or 0
    if not db or seen >= TUTORIAL_VERSION then return false end
    addon.ShowTutorial(1, seen >= 1)
    return true
end
