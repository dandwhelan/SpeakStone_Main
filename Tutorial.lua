local addonName, addon = ...

-- First-start setup and the premade settings profiles. Shown at login until the player closes it
-- (tutorialVersion), and again on demand with /ss tutorial or the Tutorial button in the settings window.
--
-- The flow follows what a player decides, in the order they meet it:
--   1. Welcome and voice packs  -- is there audio to play?
--   2. How to listen            -- a profile: what is read, and how much
--   3. When you walk away      -- nothing, subtitles or the text box, each with a live sample
--   3b. The speaker            -- the text box's portrait: a still picture or a moving 3D head
--   (How it looks -- theme, font, subtitle colours -- was a page until 2026-11-07; the owner took it out: not
--   everyone uses subtitles, and the text box with the speaker is the way to follow along. It is all in /ss > Look.)
--   5. While you play           -- combat, instances, queueing
--   6. Where things are         -- the Guide, the buttons, the keys
--   7a. Report a voice         -- the report sign, with a real example
--   7. Help the project         -- capture and the website (optional)
--   8. Done
-- Players who saw an older setup get a short run instead: what's new, the speaker, reporting, done.

-- Bump to show the setup once more to everyone, e.g. after adding a page.
-- 2: the speech bar page. 3: the flow rebuilt (look, behaviour, the Guide); players who saw version 2 get the short run.
-- 4: the speaker and report pages (2026-11-07); everyone who saw 3 gets the short run with them once.
local TUTORIAL_VERSION = 4

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
    "When you walk away: the speech bar with the whole passage, and the word being said lit",
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
local FULL_ORDER = { "welcome", "listen", "words", "head", "play", "where", "report", "help", "done" }
local SHORT_ORDER = { "whatsnew", "head", "report", "done" }
local STEP_TITLES = {
    welcome = "Welcome", listen = "How to listen", words = "When you walk away", head = "The speaker",
    play = "While you play", report = "Report a voice",
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
            .. "show, who is speaking, how it behaves while you play, and where things are. You can come back to it any time with "
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
        DB().audioPack3PromptShown = true
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

-- A round portrait in a ring of the theme's accent, as the speech bar draws its still picture. Returns the ring and the
-- picture (call SetPortraitTexture on it when the page shows).
local function SpeakerDisc(parent, size, x, y)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size, size)
    holder:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    holder:EnableMouse(false)
    local function Disc(layer, sub, s)
        local t = holder:CreateTexture(nil, layer, nil, sub)
        t:SetSize(s, s)
        t:SetPoint("CENTER", holder, "CENTER")
        local m = holder:CreateMaskTexture()
        m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(t)
        t:AddMaskTexture(m)
        return t
    end
    return Disc("BORDER", 1, size), Disc("ARTWORK", 0, size - 6)
end

-- 3. When you walk away: nothing, subtitles, or the speech bar -- each with a live sample
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
        -- preview: the real thing for a few seconds, because the three samples look alike (owner, 2026-11-07).
        { key = "subtitles", name = "B.  Subtitles", style = "bar",
          desc = "A few words at a time in a small bar over the game, as the voice says them.",
          preview = function() if addon.PreviewSubtitles then addon.PreviewSubtitles() end end,
          apply = function(db) db.showSubtitles = true end },
        { key = "box", name = "C.  Text box with the speaker", style = "box",
          desc = "Recommended. The whole passage beside the speaker's head, with Pause, Stop and Replay; the word being said "
              .. "is lit. (The speech bar in /ss.)",
          preview = function() if addon.SpeechFramePreview then addon.SpeechFramePreview() end end,
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
            if button.ring then
                local a = addon.Theme().accent
                button.ring:SetColorTexture(a[1], a[2], a[3], 1)
                pcall(SetPortraitTexture, button.speaker, "player")
            end
        end
    end
    local previous = hint
    for _, choice in ipairs(CHOICES) do
        -- Room for a Preview button only where there is one: three tall choices pushed the last tick box onto Back
        -- (owner, 2026-11-07).
        local button = addon.UIK.Button(page, "", CONTENT, choice.preview and 90 or 80, function()
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
            if choice.style == "box" then
                -- Like the real speech bar: the speaker in a ring on the left (the player's own face here), the
                -- name and the words beside it (owner, 2026-11-07).
                button.ring, button.speaker = SpeakerDisc(preview, 54, 8, -9)
                preview.name:ClearAllPoints()
                preview.name:SetPoint("TOPLEFT", preview, "TOPLEFT", 70, -6)
                -- Name and quest title on one line that stops at the box's edge (it ran on into the choice's own
                -- name beside it).
                preview.name:SetPoint("RIGHT", preview, "RIGHT", -8, 0)
                preview.name:SetJustifyH("LEFT")
                preview.name:SetWordWrap(false)
            end
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
        if choice.preview then
            -- On top of the choice: clicking it shows the real thing and does not pick the choice.
            local show = addon.UIK.Button(button, "Preview", 80, 20, choice.preview)
            show:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 254, 6)
            show:SetFrameLevel(button:GetFrameLevel() + 2)
        end
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

-- 3b. Who is speaking: the text box's portrait, a still picture or the moving 3D head (owner, 2026-11-07: "add an
-- option in the tutorial for people to pick 2d or 3d heads"; the picture is the default). Each choice shows the
-- player's own character the way it would show an NPC.
local function BuildHead()
    local page = NewPage("head")
    local title = Title(page, "How should the speaker look?")
    local hint = Text(page, "GameFontHighlightSmall", CONTENT)
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    hint:SetText("The speech bar shows who is speaking beside their words. Here it is with your own character; you can "
        .. "change it any time in /ss under On screen.")

    local CHOICES = {
        { key = false, name = "A.  A picture",
          desc = "A still portrait in a thin ring, in the theme's colour. Quiet, and easy on older computers." },
        { key = true, name = "B.  A moving head",
          desc = "The speaker's own 3D model with nothing behind it, talking sentence by sentence as the voice reads, "
              .. "and still when it pauses." },
    }
    local buttons, model = {}, nil
    local function Refresh()
        local ui = addon.Theme().ui
        local current = DB().speechPortrait3D == true
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
            if button.ring then
                local a = addon.Theme().accent
                button.ring:SetColorTexture(a[1], a[2], a[3], 1)
            end
        end
    end
    local function Disc(parent, layer, sub, size)
        local t = parent:CreateTexture(nil, layer, nil, sub)
        t:SetSize(size, size)
        t:SetPoint("CENTER", parent, "CENTER")
        local m = parent:CreateMaskTexture()
        m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(t)
        t:AddMaskTexture(m)
        return t
    end
    local previous = hint
    for _, choice in ipairs(CHOICES) do
        local button = addon.UIK.Button(page, "", CONTENT, 110, function()
            DB().speechPortrait3D = choice.key
            if addon.SpeechFrameRefreshPortrait then addon.SpeechFrameRefreshPortrait() end
            Refresh()
        end)
        button:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, previous == hint and -12 or -8)
        button.key = choice.key
        button.label:Hide()
        local holder = CreateFrame("Frame", nil, button)
        holder:SetSize(96, 96)
        holder:SetPoint("LEFT", button, "LEFT", 70, 0)
        holder:EnableMouse(false)
        if choice.key then
            -- The moving head, talking on a loop.
            model = CreateFrame("PlayerModel", nil, holder)
            model:SetAllPoints(holder)
            -- Framed exactly as the speech bar frames a speaker (SpeechFrame.lua ApplySpeakerFace: the owner's zoom,
            -- 1.35 by default), so the example looks as it will in play (owner, 2026-11-07).
            model:SetScript("OnModelLoaded", function(self)
                if addon.ApplySpeakerFace then
                    addon.ApplySpeakerFace(self)
                else
                    pcall(self.SetPortraitZoom, self, 1)
                    pcall(self.SetCamDistanceScale, self, 1.35)
                end
                pcall(self.SetAnimation, self, 60)
            end)
            model:SetScript("OnAnimFinished", function(self) pcall(self.SetAnimation, self, 60) end)
        else
            button.ring = Disc(holder, "BORDER", 1, 92)
            button.portrait = Disc(holder, "ARTWORK", 0, 86)
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
        name:SetPoint("TOPLEFT", button, "TOPLEFT", 254, -14)
        name:SetText(choice.name)
        local desc = Text(button, "GameFontHighlightSmall", CONTENT - 290)
        desc.ssRole = false
        desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6)
        desc:SetSpacing(2)
        desc:SetText(choice.desc)
        button.nameText, button.descText = name, desc
        buttons[#buttons + 1] = button
        previous = button
    end

    page:SetScript("OnShow", function()
        Refresh()
        for _, button in ipairs(buttons) do
            if button.portrait then pcall(SetPortraitTexture, button.portrait, "player") end
        end
        if model then
            pcall(model.ClearModel, model)
            pcall(model.SetUnit, model, "player")
        end
    end)
    addon.ThemeRegister(function() if page:IsShown() then Refresh() end end)
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
-- 7a. Report a voice: where the report sign is, and what clicking it does -- with a real example, the owner's own
-- screenshot of the menu on Dialogue UI's window (Art/TutorialReport.png, 370x256 on a 512x256 canvas; owner,
-- 2026-11-07: "show an example of how to report an issue on a played clip").
local REPORT_PICTURE = "Interface\\AddOns\\" .. addonName .. "\\Art\\TutorialReport.png"
local ALERT = "|TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:15:15|t"

local function BuildReport()
    local page = NewPage("report")
    local title = Title(page, "Something sounds wrong? Report it")
    local body = Body(page, title, "", 8)
    local W, H = 315, 218            -- the screenshot at 85%, so the page fits above Back / Next
    local picture = page:CreateTexture(nil, "ARTWORK")
    picture:SetSize(W, H)
    picture:SetTexture(REPORT_PICTURE)
    picture:SetTexCoord(0, 370 / 512, 0, 1)
    picture:SetPoint("TOPLEFT", body, "BOTTOMLEFT", math.floor((CONTENT - W) / 2), -12)
    local caption = Text(page, "GameFontDisableSmall", W)
    caption:SetPoint("TOP", picture, "BOTTOM", 0, -4)
    caption:SetPoint("LEFT", picture, "LEFT", 0, 0)
    caption:SetText("The sign on Dialogue UI's window, clicked: the line it is about, and what can be wrong with it.")
    page:SetScript("OnShow", function()
        local g = Gold()
        body:SetText("Every voiced line can be reported from where you hear it. Look for the faint " .. ALERT
            .. " sign: it lights up when you point at it.\n\n"
            .. "  " .. g .. "Dialogue UI's window|r: top-right corner.\n"
            .. "  " .. g .. "The speech bar|r (after you walk away): beside Replay.\n\n"
            .. "Click it and pick what is wrong: the wrong voice or sex, an audio glitch, a name said wrong, "
            .. "cut off, or words that do not match. It goes into your captured text, so it reaches us with the next "
            .. "export (last page).")
    end)
end

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

    -- The reminder that keeps the voices growing (owner, 2026-11-07): what was not voiced is captured as you play,
    -- and pasting it on the website gets it voiced, usually by the next day.
    local growHead = Text(page, "GameFontNormal")
    growHead:SetPoint("TOPLEFT", guide, "BOTTOMLEFT", 0, -26)
    growHead:SetText("Help fill the gaps")
    local grow = Text(page, "GameFontHighlight", CONTENT)
    grow:SetPoint("TOPLEFT", growHead, "BOTTOMLEFT", 0, -4)
    grow:SetSpacing(3)
    local export = addon.UIK.Button(page, "Export captured text", 200, 28, function()
        if addon.ShowHarvestExport then addon.ShowHarvestExport() end
    end)
    export:SetPoint("TOPLEFT", grow, "BOTTOMLEFT", 0, -10)
    local box = CopyBox(page, WEBSITE_URL, CONTENT - 230)
    box:SetPoint("LEFT", export, "RIGHT", 18, 0)

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
            .. "Something sounds wrong? Click the faint " .. ALERT .. " sign beside the words.")
        local waiting = 0
        if addon.HarvestCounts then
            local q, _, _, _, l, i = addon.HarvestCounts()
            waiting = (q or 0) + (l or 0) + (i or 0)
        end
        grow:SetText("Quests, NPC greetings and books with no voice yet are saved as you play"
            .. (waiting > 0 and (" (" .. Good() .. waiting .. " waiting now|r)") or "")
            .. ". Every so often, export them and paste them on the website: new lines are usually voiced by the "
            .. "next day, for you and everyone else. Your reports go with them.")
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
        body:SetText(g .. "The speaker beside the words|r: a picture in a ring, or a moving head that talks with the "
            .. "voice. Pick one on the next page.\n\n"
            .. g .. "Dialogue UI|r: its play button and R key play SpeakStone's voice, and the words follow it.\n\n"
            .. g .. "Report a line where you hear it|r: a faint " .. ALERT .. " sign on Dialogue UI's window and "
            .. "the speech bar.\n\n"
            .. g .. "Reading along keeps time better|r, the text not being read is dimmed, and SpeakStone can match "
            .. "Dialogue UI's Brown or Dark theme.\n\n"
            .. "Next: the speaker.")
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
    BuildHead()
    BuildPlay()
    BuildWhere()
    BuildReport()
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
