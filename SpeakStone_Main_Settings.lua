local addonName, addon = ...
local SpeakStone = {}

EventUtil.ContinueOnAddOnLoaded(addonName, function()
    SpeakStone_MainDB = SpeakStone_MainDB or {}
    if addon.EnsureDB then addon.EnsureDB() end
    SpeakStone:CreateSettings()
end)

local WEBSITE = "speakstone.beanw.co.uk"

local SPEECH_FRAME_INFO = "When you walk away from a quest giver while a line is still being read (or a quest is "
    .. "auto-accepted), a bar shows the NPC, the quest and the text, with Pause, Stop and Replay.\n\n"
    .. "|cffffd100About Pause:|r WoW can only play a sound file from the start. It can't pause one or jump into the "
    .. "middle, so Pause stops the voice and Resume plays the line again from the beginning.\n\n"
    .. "Right-click the bar to change its size or lock it. |cffffd100/ss frame|r shows a sample to place it with."

local GOLD = { 1, 0.82, 0 }

local function AttachTooltip(frame, title, body)
    if not body then return end
    frame:HookScript("OnEnter", function(self)
        local text = type(body) == "function" and body() or body
        if not text or text == "" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(type(title) == "function" and title() or title, GOLD[1], GOLD[2], GOLD[3])
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function CreateInfoIcon(parent, title, body)
    local icon = CreateFrame("Button", nil, parent)
    icon:SetSize(16, 16)
    icon:SetNormalTexture("Interface\\common\\help-i")
    icon:SetHighlightTexture("Interface\\common\\help-i", "ADD")
    AttachTooltip(icon, title, body)
    return icon
end

local function OpenAudioLibraryUI(mode)
    if addon.OpenAudioLibrary then
        addon.OpenAudioLibrary(mode)
    else
        print("SpeakStone: the audio library window is not available.")
    end
end

local function ExportHarvest()
    if addon.ShowHarvestExport then
        addon.ShowHarvestExport()
    end
end

StaticPopupDialogs["SPEAKSTONE_CONFIRM_CLEAR_HARVEST"] = {
    text = "Clear everything SpeakStone has captured -- quest text, greetings and books?\n\nThis cannot be undone, and anything not yet submitted is lost.",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        if SpeakStoneHarvesterDB then
            SpeakStoneHarvesterDB.quests = {}
            SpeakStoneHarvesterDB.gossip = {}
            SpeakStoneHarvesterDB.itemText = {}
        end
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

-- Every pack a complete install has, per family.
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
        packs = { "Audio_Pack1", "Audio_Pack2", "Audio_Pack3", "Chatter" },
    },
}
addon.EXPECTED_PACK_FAMILIES = EXPECTED_PACK_FAMILIES

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

-- What's new (newest first, up to 20 items). Player wording only.
local WHATS_NEW = {
    { "6.1.0", "2026-11-22", {
        "Slimmer, cleaner settings window: clickable voice-pack and capture badges in the top bar, four focused tabs, scrollable panels that never overflow, and room reserved for the controller bar.",
        "Compact four-line scrolling speech bar with auto-scroll is now the default.",
        "TV / Sofa and controller settings from the tutorial are now right inside /ss under TV & More, plus a 3-way bar layout picker (Compact, Full passage, TV / Sofa).",
        "Streamlined 4-step setup tutorial (5 steps when a controller is active)." } },
    { "5.0.2", "2026-11-07", {
        "The speech bar shows who is speaking: a picture in a ring in your theme's colour, or a moving 3D head that talks with the voice (choose in the tutorial or /ss, Display).",
        "Report a line where you hear it: a faint warning sign on Dialogue UI's window and on the speech bar. Reports go out with your captured text.",
        "Dialogue UI's play button and R key play SpeakStone's voice, and its own text-to-speech no longer talks over a voiced line.",
        "Reading along keeps better time with lines the narrator reads, and the text not being read is dimmed.",
        "SpeakStone can match Dialogue UI's Brown or Dark theme; the speech bar's buttons follow your theme and stay faint; the subtitles have a close X.",
        "Play buttons show whether autoplay is on (right-click to switch it), and the greeting window has a Play button.",
        "The tutorial has pages for the speaker and for reporting a line, and reminds you to export what you capture." } },
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

-- --------------------------------------------------------------------------
-- Settings window: Slim Top Bar + 4 Focused Tabs + Scrollable Body
-- --------------------------------------------------------------------------

local FRAME_WIDTH = 700
local FRAME_HEIGHT = 580
local CONTENT_WIDTH = FRAME_WIDTH - 46 -- room for left margin + right scrollbar

local function NotifySetting(key)
    if addon.SpeechSettingChanged then addon.SpeechSettingChanged(key) end
end

function SpeakStone:CreateWindow()
    if addon.settingsWindow then return addon.settingsWindow end

    local frame = addon.UIK.Window("SpeakStoneSettingsFrame", FRAME_WIDTH, FRAME_HEIGHT, "SpeakStone")
    tinsert(UISpecialFrames, "SpeakStoneSettingsFrame")

    -- Left-align the title so status pills and quick actions fit cleanly in the top bar.
    frame.TitleText:ClearAllPoints()
    frame.TitleText:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -9)

    local version = C_AddOns and C_AddOns.GetAddOnMetadata
        and C_AddOns.GetAddOnMetadata(addonName, "Version")
    local versionText
    if version then
        versionText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        versionText:SetPoint("RIGHT", frame.close, "LEFT", -8, 0)
        versionText:SetText("v" .. version)
    end

    -- Top-right quick actions: Tutorial + Open Guide
    local tutorialBtn = addon.UIK.Button(frame, "Tutorial", 66, 22, function()
        if addon.ShowTutorial then addon.ShowTutorial(1) end
    end)
    tutorialBtn:SetPoint("RIGHT", versionText or frame.close, "LEFT", -8, 0)
    AttachTooltip(tutorialBtn, "Tutorial", "Run the quick 4-step setup again. Also /ss tutorial.")

    local guideBtn = addon.UIK.Button(frame, "Open Guide", 90, 22, function() OpenAudioLibraryUI() end)
    guideBtn:SetPoint("RIGHT", tutorialBtn, "LEFT", -6, 0)
    guideBtn:SetSelected(true)
    AttachTooltip(guideBtn, "SpeakStone Guide", "Browse and replay every voiced quest, greeting and book, grouped by expansion, zone, NPC or title. Also /sslibrary.")

    -- Clickable status pills right beside the title (replaces the old 226px left sidebar)
    local packsTooltip, capturesTooltip = "", ""

    local packsPill = addon.UIK.Button(frame, "Voice packs...", 168, 22, function() OpenAudioLibraryUI("packs") end)
    packsPill:SetPoint("LEFT", frame.TitleText, "RIGHT", 12, 0)
    packsPill.label:SetFontObject("GameFontHighlightSmall")
    packsPill.Paint()
    AttachTooltip(packsPill, "Voice packs", function() return packsTooltip end)

    local capturesPill = addon.UIK.Button(frame, "0 captures", 104, 22, ExportHarvest)
    capturesPill:SetPoint("LEFT", packsPill, "RIGHT", 6, 0)
    capturesPill.label:SetFontObject("GameFontHighlightSmall")
    capturesPill.Paint()
    AttachTooltip(capturesPill, "Your captures (click to export)", function() return capturesTooltip end)

    -- ----------------------------------------------------------------------
    -- Tab strip (4 clean tabs)
    -- ----------------------------------------------------------------------
    local TAB_SPECS = {
        { key = "display",  title = "Display" },
        { key = "playback", title = "Playback" },
        { key = "look",     title = "Look" },
        { key = "more",     title = "TV & More" },
    }
    local tabButtons = {}
    local activeTab = 1
    local layoutTab -- forward declaration

    -- ----------------------------------------------------------------------
    -- Scrollable content area (leaves 30px at bottom for Gamepad legend)
    -- ----------------------------------------------------------------------
    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -72)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 30)
    scroll:EnableMouseWheel(true)

    local scrollBar = addon.UIK.VScroll(frame, FRAME_HEIGHT - 102)
    scrollBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -72)
    scrollBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 30)

    local scrollRange = 0
    local function SetScroll(y)
        y = math.max(0, math.min(scrollRange, y or 0))
        scroll:SetVerticalScroll(y)
        scrollBar:SetValue(y)
    end
    scrollBar:SetScript("OnValueChanged", function(_, value)
        scroll:SetVerticalScroll(value)
    end)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        SetScroll(scroll:GetVerticalScroll() - delta * 36)
    end)

    local function UpdateScrollRange(contentHeight)
        local viewH = scroll:GetHeight()
        if not viewH or viewH <= 0 then viewH = FRAME_HEIGHT - 102 end
        scrollRange = math.max(0, math.ceil((contentHeight or 0) - viewH))
        scrollBar:SetMinMaxValues(0, scrollRange)
        scrollBar:SetShown(scrollRange > 0)
        if scroll:GetVerticalScroll() > scrollRange then
            SetScroll(scrollRange)
        end
    end

    -- One scroll child per tab; we swap SetScrollChild on tab switch.
    local tabContents = {}
    local tabRelayout = {}

    local function SelectTab(index)
        if index < 1 or index > #TAB_SPECS then index = 1 end
        activeTab = index
        SpeakStone_MainDB.settingsTab = index
        for i, btn in ipairs(tabButtons) do
            btn:SetSelected(i == index)
            if tabContents[i] then tabContents[i]:SetShown(i == index) end
        end
        local content = tabContents[index]
        if content then
            scroll:SetScrollChild(content)
            if tabRelayout[index] then
                local h = tabRelayout[index]()
                content:SetHeight(math.max(h, 100))
                UpdateScrollRange(h)
            else
                UpdateScrollRange(content:GetHeight())
            end
            SetScroll(0)
        end
        if frame.nav and frame.nav.Reset then frame.nav.Reset() end
    end

    local tabX = 14
    for i, spec in ipairs(TAB_SPECS) do
        local w = math.max(88, #spec.title * 8 + 28)
        local btn = addon.UIK.Button(frame, spec.title, w, 24, function() SelectTab(i) end)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", tabX, -40)
        tabX = tabX + w + 6
        tabButtons[i] = btn
    end
    local tabDivider = addon.UIK.Divider(frame)
    tabDivider:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -67)
    tabDivider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -67)

    -- ----------------------------------------------------------------------
    -- Shared widget builders for tabs
    -- ----------------------------------------------------------------------
    local allChecks = {}
    local refreshers = {}

    function addon.RefreshSettingChecks()
        for _, check in ipairs(allChecks) do
            check:SetChecked(SpeakStone_MainDB[check.optionKey] and true or false)
        end
        for _, fn in ipairs(refreshers) do fn() end
    end

    local function MakeHeader(parent, title, info)
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(CONTENT_WIDTH, 24)
        local text = row:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        text:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        text:SetText(title)
        if info then
            CreateInfoIcon(row, title, info):SetPoint("LEFT", text, "RIGHT", 6, 0)
        end
        local div = addon.UIK.Divider(row)
        div:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -21)
        div:SetSize(CONTENT_WIDTH, 1)
        row.height = 28
        return row
    end

    local function MakeCheck(parent, option, label, tooltip, onChange, width)
        local check = addon.UIK.Check(parent, label, "GameFontNormal")
        check.optionKey = option
        check:SetHitRectInsets(0, -math.min(width or 290, check.text:GetStringWidth() + 6), 0, 0)
        check:SetChecked(SpeakStone_MainDB[option] and true or false)
        check:SetScript("OnClick", function(self)
            SpeakStone_MainDB[option] = self:GetChecked() and true or false
            if onChange then onChange(SpeakStone_MainDB[option]) end
            NotifySetting(option)
            addon.RefreshSettingChecks()
        end)
        allChecks[#allChecks + 1] = check
        AttachTooltip(check, label, tooltip)
        return check
    end

    -- 2-column row of checkboxes
    local function MakeCheckPair(parent, leftSpec, rightSpec)
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(CONTENT_WIDTH, 24)
        local half = math.floor(CONTENT_WIDTH / 2)
        if leftSpec then
            local c = MakeCheck(row, leftSpec.option, leftSpec.label, leftSpec.tooltip, leftSpec.onChange, half - 28)
            c:SetPoint("TOPLEFT", row, "TOPLEFT", leftSpec.indent and 18 or 2, -2)
            row.left = c
        end
        if rightSpec then
            local c = MakeCheck(row, rightSpec.option, rightSpec.label, rightSpec.tooltip, rightSpec.onChange, half - 28)
            c:SetPoint("TOPLEFT", row, "TOPLEFT", half + 4, -2)
            row.right = c
        end
        row.height = 26
        return row
    end

    -- Segmented button group (label on left, pill buttons on right)
    local function MakeSegmentRow(parent, label, options, getVal, setVal, tooltip, rightExtra)
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(CONTENT_WIDTH, 28)
        local lbl = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        lbl:SetPoint("LEFT", row, "LEFT", 2, 0)
        lbl:SetText(label)
        if tooltip then AttachTooltip(row, label, tooltip) end

        local btns = {}
        local x = 165
        for _, opt in ipairs(options) do
            local bw = opt.w or math.max(76, #opt.label * 7 + 22)
            local b = addon.UIK.Button(row, opt.label, bw, 22, function()
                setVal(opt.value)
                addon.RefreshSettingChecks()
                if tabRelayout[activeTab] then
                    local h = tabRelayout[activeTab]()
                    tabContents[activeTab]:SetHeight(math.max(h, 100))
                    UpdateScrollRange(h)
                end
            end)
            b:SetPoint("LEFT", row, "LEFT", x, 0)
            b.segValue = opt.value
            if opt.tooltip then AttachTooltip(b, opt.label, opt.tooltip) end
            btns[#btns + 1] = b
            x = x + bw + 4
        end
        if rightExtra then
            local eb = addon.UIK.Button(row, rightExtra.label, rightExtra.w or 78, 22, rightExtra.onClick)
            eb:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            if rightExtra.tooltip then AttachTooltip(eb, rightExtra.label, rightExtra.tooltip) end
            row.extraBtn = eb
        end
        local function Refresh()
            local cur = getVal()
            for _, b in ipairs(btns) do b:SetSelected(b.segValue == cur) end
        end
        refreshers[#refreshers + 1] = Refresh
        Refresh()
        row.height = 30
        return row
    end

    local function MakeSliderRow(parent, spec)
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(CONTENT_WIDTH, 54)
        local slider = addon.UIK.Slider(row, 260)
        slider:SetPoint("TOPLEFT", row, "TOPLEFT", 22, -16)
        slider:SetMinMaxValues(spec.min, spec.max)
        slider:SetValueStep(spec.step)
        slider:SetObeyStepOnDrag(true)
        slider.low:SetText(spec.low)
        slider.high:SetText(spec.high)

        local function Snap(v) return math.floor(v / spec.step + 0.5) * spec.step end
        local function Describe(v) slider.caption:SetText(spec.describe(v)) end

        slider:SetScript("OnValueChanged", function(_, value)
            value = Snap(value)
            SpeakStone_MainDB[spec.option] = value
            Describe(value)
            NotifySetting(spec.option)
        end)
        local function Refresh()
            local v = tonumber(SpeakStone_MainDB[spec.option]) or spec.default
            slider:SetValue(v)
            Describe(v)
        end
        refreshers[#refreshers + 1] = Refresh
        Refresh()
        AttachTooltip(slider, spec.title, spec.tooltip)
        row.slider = slider
        row.height = 56
        return row
    end

    -- Helper to stack visible widgets dynamically and return total height
    local function LayoutRows(rows, startY)
        local y = startY or -4
        for _, item in ipairs(rows) do
            if type(item) == "number" then
                y = y - item
            elseif item and (not item.when or item.when()) then
                local w = item.frame or item
                w:Show()
                w:ClearAllPoints()
                w:SetPoint("TOPLEFT", w:GetParent(), "TOPLEFT", item.x or 0, y)
                y = y - (item.height or w.height or w:GetHeight() or 26)
            elseif item and (item.frame or item) then
                local w = item.frame or item
                w:Hide()
            end
        end
        return -y + 12
    end

    -- Helper to trigger relayout of the current tab immediately
    local function RelayoutActive()
        if tabRelayout[activeTab] then
            local h = tabRelayout[activeTab]()
            tabContents[activeTab]:SetHeight(math.max(h, 100))
            UpdateScrollRange(h)
        end
    end

    -- ======================================================================
    -- TAB 1: Display
    -- ======================================================================
    do
        local p = CreateFrame("Frame", nil, scroll)
        p:SetWidth(CONTENT_WIDTH)
        tabContents[1] = p

        local function WalkAwayMode()
            local db = SpeakStone_MainDB
            if db.showSubtitles then return "subtitles" end
            if db.showSpeechFrame ~= false then return "bar" end
            return "none"
        end
        local function SetWalkAwayMode(mode)
            local db = SpeakStone_MainDB
            if mode == "bar" then
                db.showSubtitles = false
                db.showSpeechFrame = true
            elseif mode == "subtitles" then
                db.showSubtitles = true
            else
                db.showSubtitles = false
                db.showSpeechFrame = false
            end
            NotifySetting("showSubtitles")
            NotifySetting("showSpeechFrame")
        end

        local function BarLayoutMode()
            local db = SpeakStone_MainDB
            if db.speechTVAlways then return "tv" end
            if db.speechCompact then return "compact" end
            return "full"
        end
        local function SetBarLayoutMode(mode)
            local db = SpeakStone_MainDB
            if mode == "compact" then
                db.speechCompact = true
                db.speechFitText = false
                db.speechTVAlways = false
                db.speechAutoScroll = true
            elseif mode == "tv" then
                db.speechCompact = true
                db.speechFitText = false
                db.speechTVAlways = true
                db.speechAutoScroll = true
            else
                db.speechCompact = false
                db.speechFitText = true
                db.speechTVAlways = false
            end
            NotifySetting("speechCompact")
            NotifySetting("speechFitText")
            NotifySetting("speechTVAlways")
        end

        local hWalk = MakeHeader(p, "When you walk away", SPEECH_FRAME_INFO)
        local rMode = MakeSegmentRow(p, "Show on screen", {
            { value = "bar",       label = "Speech bar", w = 96, tooltip = "Shows the speaker, text and controls when you walk away." },
            { value = "subtitles", label = "Subtitles",  w = 88, tooltip = "A small bar over the world showing words as the voice reaches them." },
            { value = "none",      label = "Audio only", w = 88, tooltip = "Nothing appears on screen; you only hear the voice." },
        }, WalkAwayMode, SetWalkAwayMode, nil, {
            label = "Preview",
            w = 74,
            tooltip = "Show a live in-game preview of your current bar or subtitles.",
            onClick = function()
                if WalkAwayMode() == "subtitles" then
                    if addon.PreviewSubtitles then addon.PreviewSubtitles() end
                elseif WalkAwayMode() == "bar" then
                    if addon.SpeechFramePreview then addon.SpeechFramePreview() end
                else
                    print("|cff33ff99SpeakStone:|r Audio only is selected, so no bar is shown.")
                end
            end,
        })

        -- Speech bar options (only shown when Speech bar is active)
        local rLayout = MakeSegmentRow(p, "Bar layout", {
            { value = "compact", label = "Compact (4 lines)", w = 132, tooltip = "Default. Four lines that scroll smoothly with the voice so the bar stays out of the way." },
            { value = "full",    label = "Full passage",      w = 104, tooltip = "Grows taller to show the whole passage at once." },
            { value = "tv",      label = "TV / Sofa",         w = 92,  tooltip = "Larger bar and big gliding text for reading from across the room." },
        }, BarLayoutMode, SetBarLayoutMode)

        local rPortrait = MakeSegmentRow(p, "Speaker portrait", {
            { value = false, label = "2D Ring",         w = 90,  tooltip = "A still portrait in a theme-coloured ring." },
            { value = true,  label = "Moving 3D Head",  w = 122, tooltip = "The NPC's own 3D model talking along with the voice." },
        }, function() return SpeakStone_MainDB.speechPortrait3D == true end,
           function(v)
               SpeakStone_MainDB.speechPortrait3D = v
               if addon.SpeechFrameRefreshPortrait then addon.SpeechFrameRefreshPortrait() end
           end)

        local rBarCombat = MakeSegmentRow(p, "Bar in combat", {
            { value = "show", label = "Show", w = 74, tooltip = "Keep the speech bar visible during combat." },
            { value = "fade", label = "Fade", w = 74, tooltip = "Fade the speech bar back during combat." },
            { value = "hide", label = "Hide", w = 74, tooltip = "Hide the speech bar in combat (the voice keeps playing)." },
        }, function()
            local m = SpeakStone_MainDB.speechCombat
            return (m == "fade" or m == "hide") and m or "show"
        end, function(v)
            SpeakStone_MainDB.speechCombat = v
            NotifySetting("speechCombat")
        end)

        local rBarChecks1 = MakeCheckPair(p,
            { option = "speechAutoScroll", label = "Auto-scroll with voice", tooltip = "Scroll the text along with the voice so the current line stays in view." },
            { option = "subtitleHighlight", label = "Highlight spoken word", tooltip = "Lights the word being read in the highlight colour." })
        local rBarChecks2 = MakeCheckPair(p,
            { option = "speechHideOnTaxi", label = "Hide on flight paths", tooltip = "Step the bar aside while flying; the voice keeps playing." },
            { option = "speechFrameLocked", label = "Lock bar in place", tooltip = "Prevent accidentally dragging the speech bar." })

        -- Subtitles options (only shown when Subtitles is active)
        local rSubChecks1 = MakeCheckPair(p,
            { option = "subtitleTypeOut", label = "Type the words out", tooltip = "Words appear as the voice reaches them." },
            { option = "subtitleHighlight", label = "Highlight spoken word", tooltip = "Lights the word being read in the highlight colour." })
        local rSubChecks2 = MakeCheckPair(p,
            { option = "subtitlesWhileOpen", label = "Also show while quest window open", tooltip = "Show subtitles over the world even while the quest window is open." },
            { option = "subtitleLocked", label = "Lock subtitles in place", tooltip = "Clicks pass through to the game." })

        -- Audio-only note
        local rAudioNote = CreateFrame("Frame", nil, p)
        rAudioNote:SetSize(CONTENT_WIDTH, 24)
        local noteText = rAudioNote:CreateFontString(nil, "ARTWORK", "GameFontDisable")
        noteText:SetPoint("LEFT", 4, 0)
        noteText:SetText("Audio only: nothing appears on screen when you walk away. Narration still plays.")
        rAudioNote.height = 28

        -- In other windows
        local hOther = MakeHeader(p, "In other windows")
        local rOtherChecks = MakeCheckPair(p,
            { option = "syncDialogueText", label = "Reveal text in Dialogue UI", tooltip = "With Dialogue UI installed, quest text follows the voice word by word." },
            { option = "talkingHeadHighlight", label = "Light words in talking heads", tooltip = "Highlights the word being read on Blizzard's talking head." })

        local rPreviewRow = CreateFrame("Frame", nil, p)
        rPreviewRow:SetSize(CONTENT_WIDTH, 28)
        local bPrevDui = addon.UIK.Button(rPreviewRow, "Preview Dialogue UI", 146, 22, function()
            if addon.PreviewWindow then addon.PreviewWindow("dialogue") end
        end)
        bPrevDui:SetPoint("LEFT", 2, 0)
        local bPrevTH = addon.UIK.Button(rPreviewRow, "Preview talking head", 150, 22, function()
            if addon.PreviewWindow then addon.PreviewWindow("talkinghead") end
        end)
        bPrevTH:SetPoint("LEFT", bPrevDui, "RIGHT", 8, 0)
        rPreviewRow.height = 30

        local isBar = function() return WalkAwayMode() == "bar" end
        local isSub = function() return WalkAwayMode() == "subtitles" end
        local isNone = function() return WalkAwayMode() == "none" end

        local rows = {
            hWalk, rMode, 6,
            { frame = rLayout,     when = isBar },
            { frame = rPortrait,   when = isBar },
            { frame = rBarCombat,  when = isBar },
            { frame = rBarChecks1, when = isBar },
            { frame = rBarChecks2, when = isBar },
            { frame = rSubChecks1, when = isSub },
            { frame = rSubChecks2, when = isSub },
            { frame = rAudioNote,  when = isNone },
            14,
            hOther, rOtherChecks, 4, rPreviewRow,
        }
        tabRelayout[1] = function() return LayoutRows(rows, -4) end
    end

    -- ======================================================================
    -- TAB 2: Playback
    -- ======================================================================
    do
        local p = CreateFrame("Frame", nil, scroll)
        p:SetWidth(CONTENT_WIDTH)
        tabContents[2] = p

        local function ApplyQuickPreset(key)
            if key == "tv" then
                if addon.ApplyProfile then addon.ApplyProfile("full") end
                local db = SpeakStone_MainDB
                db.speechTVOnPad = true
                db.speechTVAlways = true
                db.speechCompact = true
                db.speechFitText = false
                db.speechAutoScroll = true
                db.speechCombat = "hide"
                db.speechHideOnTaxi = false
                db.queueQuestSpeech = true
                db.autoAcceptQuests = true
                db.profile = "tv"
                NotifySetting("speechTVAlways")
                NotifySetting("speechCompact")
            elseif addon.ApplyProfile then
                addon.ApplyProfile(key)
            end
            addon.RefreshSettingChecks()
            RelayoutActive()
        end

        local rPresets = MakeSegmentRow(p, "Quick preset", {
            { value = "full",     label = "Full",          w = 68, tooltip = "Quests, greetings and books read aloud. Blizzard voices muted." },
            { value = "story",    label = "Story only",    w = 88, tooltip = "Quests and books read; passing NPC greetings stay quiet." },
            { value = "blizzard", label = "Blizzard first", w = 104, tooltip = "Keep Blizzard's own voice lines; SpeakStone fills the rest." },
            { value = "manual",   label = "Manual",        w = 72, tooltip = "Only read when you click Read Quest or press F6." },
            { value = "tv",       label = "TV / Sofa",     w = 84, tooltip = "Big gliding text, auto-accept, quest queue, and hide bar in combat." },
        }, function() return SpeakStone_MainDB.profile end, ApplyQuickPreset)

        local hWhat = MakeHeader(p, "What is read automatically")
        local rAutoMaster = MakeCheckPair(p, {
            option = "autoPlayEnabled",
            label = "Read automatically when text opens",
            tooltip = "Start narrating as soon as text appears. Turn off if you only want manual playback.",
            onChange = RelayoutActive,
        }, nil)
        local rWhat1 = MakeCheckPair(p,
            { option = "autoPlayQuests", label = "Quests", indent = true, tooltip = "Quest descriptions, progress and completion text." },
            { option = "autoPlayGossip", label = "NPC greetings", indent = true, tooltip = "Lines an NPC says when you first talk to them." })
        local rWhat2 = MakeCheckPair(p,
            { option = "autoPlayItemText", label = "Books, letters & plaques", indent = true, tooltip = "Tomes, scrolls, letters and dungeon plaques." },
            { option = "autoPlayInQuestMap", label = "From the quest log map", indent = true, tooltip = "Narrate when selecting a quest in the world map's quest list." })
        local rWhat3 = MakeCheckPair(p,
            { option = "skipHeardQuests", label = "Skip quests I've already heard", indent = true, tooltip = "Autoplay skips passages you've already heard. /ss forget clears the list." },
            nil)

        local hWhen = MakeHeader(p, "Behaviour & combat")
        local function CombatAudioMode()
            local db = SpeakStone_MainDB
            if db.pauseAutoPlayInCombat then return "skip" end
            if db.waitForCombatEnd then return "wait" end
            return "play"
        end
        local function SetCombatAudioMode(mode)
            local db = SpeakStone_MainDB
            db.pauseAutoPlayInCombat = (mode == "skip")
            db.waitForCombatEnd = (mode == "wait")
            NotifySetting("waitForCombatEnd")
        end
        local rCombat = MakeSegmentRow(p, "During combat", {
            { value = "play", label = "Play normally",         w = 112, tooltip = "Start reading right away even in combat." },
            { value = "wait", label = "Wait until combat ends", w = 152, tooltip = "Hold quest narration until the fight finishes, then play it." },
            { value = "skip", label = "Skip in combat",        w = 110, tooltip = "Don't autoplay while in combat (Read Quest still works)." },
        }, CombatAudioMode, SetCombatAudioMode)

        local rWhen1 = MakeCheckPair(p,
            { option = "queueQuestSpeech", label = "Queue quests instead of cutting off", tooltip = "Talking to another quest giver adds it to a queue (1/2 and Next button)." },
            { option = "autoAcceptQuests", label = "Auto-accept quests (Shift skips)", tooltip = "Accept quests immediately and hear them on the speech bar." })
        local rWhen2 = MakeCheckPair(p,
            { option = "pauseAutoPlayInInstances", label = "Quiet in dungeons, raids & BGs", tooltip = "Nothing autoplays inside an instance. Manual play still works." },
            { option = "stopDialogueOnClose", label = "Stop narration when window closes", tooltip = "Stop audio when you walk away or close the quest window." })

        local hAudio = MakeHeader(p, "Audio mixing")
        local rMuteBlizz = MakeCheckPair(p, {
            option = "muteGossip",
            label = "Silence Blizzard's own voice lines (start immediately)",
            tooltip = "On: mutes the game's Dialog channel so SpeakStone starts right away. Off: waits for Blizzard's voice line first.",
            onChange = RelayoutActive,
        }, nil)
        local rDelaySlider = MakeSliderRow(p, {
            option = "autoPlayDelay", default = 1.0, min = 0, max = 6, step = 0.5, low = "0s", high = "6s",
            describe = function(v) return string.format("Wait before speaking: %.1fs", v) end,
            title = "Wait before speaking",
            tooltip = "How long to wait for Blizzard's own voice line to finish before SpeakStone speaks.",
        })
        local rDuckCheck = MakeCheckPair(p, {
            option = "duckOtherSounds",
            label = "Lower music and ambience while speaking",
            tooltip = "Turns game music and ambience down while a line is read, then restores them.",
            onChange = RelayoutActive,
        }, nil)
        local rDuckSlider = MakeSliderRow(p, {
            option = "duckAmount", default = 0.7, min = 0.1, max = 1.0, step = 0.1, low = "10%", high = "100%",
            describe = function(v) return string.format("Lower music & ambience by: %d%%", math.floor(v * 100 + 0.5)) end,
            title = "Lower music and ambience by",
            tooltip = "100% silences music and ambience while speaking.",
        })

        local autoOn = function() return SpeakStone_MainDB.autoPlayEnabled and true or false end
        local showDelay = function() return not SpeakStone_MainDB.muteGossip end
        local showDuck = function() return SpeakStone_MainDB.duckOtherSounds and true or false end

        local rows = {
            rPresets, 10,
            hWhat, rAutoMaster,
            { frame = rWhat1, when = autoOn },
            { frame = rWhat2, when = autoOn },
            { frame = rWhat3, when = autoOn },
            10,
            hWhen, rCombat, 4, rWhen1, rWhen2,
            10,
            hAudio, rMuteBlizz,
            { frame = rDelaySlider, when = showDelay },
            rDuckCheck,
            { frame = rDuckSlider, when = showDuck },
        }
        tabRelayout[2] = function() return LayoutRows(rows, -4) end
    end

    -- ======================================================================
    -- TAB 3: Look
    -- ======================================================================
    do
        local p = CreateFrame("Frame", nil, scroll)
        p:SetWidth(CONTENT_WIDTH)
        tabContents[3] = p

        local hTheme = MakeHeader(p, "Theme")
        local rTheme = CreateFrame("Frame", nil, p)
        rTheme:SetSize(CONTENT_WIDTH, 32)
        local themeRow = addon.UIK.ThemeButtons(rTheme, 420)
        themeRow:SetPoint("TOPLEFT", rTheme, "TOPLEFT", 2, 0)
        rTheme.height = 34

        local rThemeChecks = MakeCheckPair(p,
            { option = "followDialogueUITheme", label = "Match Dialogue UI's theme", tooltip = "Automatically match Dialogue UI's Brown or Dark theme.",
              onChange = function() if addon.ThemeFollowChanged then addon.ThemeFollowChanged() end end },
            { option = "fadeOtherParagraphs", label = "Dim text not being read", tooltip = "Draws unread paragraphs fainter so your eye stays on the spoken line." })

        local hText = MakeHeader(p, "Text & highlight",
            "Reading font applies to the speech bar, subtitles and the Guide. Highlight colour lights the word being read in the speech bar, subtitles, Dialogue UI and Blizzard's talking heads.")

        local rTextNote = CreateFrame("Frame", nil, p)
        rTextNote:SetSize(CONTENT_WIDTH, 18)
        local textNote = rTextNote:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        textNote:SetPoint("LEFT", 2, 0)
        textNote:SetText("Applies to the speech bar, subtitles, Dialogue UI and talking heads.")
        rTextNote.height = 20

        local rFont = CreateFrame("Frame", nil, p)
        rFont:SetSize(CONTENT_WIDTH, 32)
        if addon.FontEntry and addon.UIK.FontDropdown then
            local lbl = rFont:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            lbl:SetPoint("LEFT", 2, 0)
            lbl:SetText("Reading font")
            local drop = addon.UIK.FontDropdown(rFont, 260)
            drop:SetPoint("LEFT", lbl, "LEFT", 160, 0)
        end
        rFont.height = 34

        local function MakeSwatchWrap(title, option, list, default, tip)
            local wrap = CreateFrame("Frame", nil, p)
            wrap:SetSize(CONTENT_WIDTH, 28)
            local sw = addon.UIK.SwatchRow(wrap, title, option, list, default, tip, 160)
            sw:SetPoint("TOPLEFT", 2, -2)
            wrap.height = 30
            return wrap
        end

        local rHighlight = MakeSwatchWrap("Highlight colour", "highlightColour", addon.HighlightColours, "auto", {
            "Gold, or deep red on light paper.",
            "Colour of the word being read in the speech bar, subtitles, Dialogue UI and talking heads." })

        -- Subtitles-only appearance section
        local hSub = MakeHeader(p, "Subtitles appearance",
            "These colours and size only apply when Subtitles are selected on the Display tab (not the Speech bar).")

        local showSubAnyway = false
        local rSubOff = CreateFrame("Frame", nil, p)
        rSubOff:SetSize(CONTENT_WIDTH, 28)
        local subOffText = rSubOff:CreateFontString(nil, "ARTWORK", "GameFontDisable")
        subOffText:SetPoint("LEFT", 2, 0)
        subOffText:SetText("Subtitles are off (you are using the Speech bar). Switch on Display to use these.")
        local subAnywayBtn = addon.UIK.Button(rSubOff, "Edit anyway", 96, 22, function()
            showSubAnyway = true
            RelayoutActive()
        end)
        subAnywayBtn:SetPoint("RIGHT", rSubOff, "RIGHT", -2, 0)
        rSubOff.height = 30

        local rPreview = CreateFrame("Frame", nil, p)
        rPreview:SetSize(CONTENT_WIDTH, 70)
        local fbox = addon.UIK.FontPreview(rPreview, CONTENT_WIDTH - 8, 62)
        fbox:SetPoint("TOPLEFT", 2, 0)
        rPreview.height = 74

        local rFontSize = MakeSliderRow(p, {
            option = "subtitleFontSize", default = 18, min = 14, max = 36, step = 2, low = "14", high = "36",
            describe = function(v) return string.format("Subtitle text size: %d", v) end,
            title = "Subtitle text size",
            tooltip = "Size of the subtitle words over the world (Subtitles mode only).",
        })

        local rSubBack = MakeSwatchWrap("Subtitle background", "subtitleBack", addon.SubtitleBackColours, "theme", {
            "The theme's own background.",
            "Soft cream, yellow, blue or green with dark text can be easier on the eyes (Subtitles mode only)." })
        local rSubText = MakeSwatchWrap("Subtitle text", "subtitleText", addon.SubtitleTextColours, "theme", {
            "The theme's own text colour.",
            "Choose dark text on a light background or light text on a dark one (Subtitles mode only)." })

        local subVisible = function() return (SpeakStone_MainDB.showSubtitles and true or false) or showSubAnyway end
        local subHidden = function() return not subVisible() end

        local rows = {
            hTheme, rTheme, rThemeChecks, 10,
            hText, rTextNote, 2, rFont, rHighlight, 12,
            hSub,
            { frame = rSubOff,   when = subHidden },
            { frame = rPreview,  when = subVisible },
            { frame = rFontSize, when = subVisible },
            { frame = rSubBack,  when = subVisible },
            { frame = rSubText,  when = subVisible },
        }
        tabRelayout[3] = function() return LayoutRows(rows, -4) end
    end

    -- ======================================================================
    -- TAB 4: TV & More (Controller / TV, Zone Lore, Community, Collapsible Advanced)
    -- ======================================================================
    do
        local p = CreateFrame("Frame", nil, scroll)
        p:SetWidth(CONTENT_WIDTH)
        tabContents[4] = p

        local hTV = MakeHeader(p, "TV / Sofa & Controller",
            "Settings from the controller tutorial, now right here in /ss. TV size scales up automatically when you pick up a controller and reverts when you use a mouse.")

        local rPadLayout = MakeSegmentRow(p, "Button prompts", {
            { value = "XBOX", label = "Xbox",               w = 78 },
            { value = "PS",   label = "PlayStation",        w = 104 },
            { value = "KBM",  label = "Keyboard & Mouse",   w = 136 },
        }, function()
            return (addon.ControllerLayout and addon.ControllerLayout()) or SpeakStone_MainDB.controllerLayout or "KBM"
        end, function(v)
            if addon.SetControllerLayout then
                addon.SetControllerLayout(v)
            else
                SpeakStone_MainDB.controllerLayout = v
            end
        end)

        local rTVChecks1 = MakeCheckPair(p,
            { option = "speechTVOnPad", label = "TV size while on controller",
              tooltip = "Bigger bar and large gliding text while using a controller; switches back when you move the mouse.",
              onChange = function(on)
                  if on and addon.SpeechFrameResetPosition then addon.SpeechFrameResetPosition() end
                  NotifySetting("speechTVOnPad")
              end },
            { option = "controllerRumble", label = "Rumble on queued / next quest",
              tooltip = "Gentle controller vibration when a quest queues or the next one starts.",
              onChange = function(on) if on and addon.Rumble then addon.Rumble("queue") end end })

        local rTVChecks2 = MakeCheckPair(p,
            { option = "controllerShowLegend", label = "Show button legend under bar",
              tooltip = "Displays which controller button pauses, skips or stops under the speech bar." },
            { option = "speechHideOnTaxi", label = "Hide bar on flight paths",
              tooltip = "Steps the speech bar aside during flight paths while audio continues." })

        local rPadActions = CreateFrame("Frame", nil, p)
        rPadActions:SetSize(CONTENT_WIDTH, 30)
        local focusBtn = addon.UIK.Button(rPadActions, "", 240, 24, function()
            local cycle = { PADBACK = "PADLSTICK", PADLSTICK = "PADRSTICK", PADRSTICK = "PADBACK" }
            local cur = addon.ControllerFocusButton and addon.ControllerFocusButton() or "PADBACK"
            if addon.SetControllerFocusButton then
                addon.SetControllerFocusButton(cycle[cur] or "PADBACK")
            end
            addon.RefreshSettingChecks()
        end)
        focusBtn:SetPoint("LEFT", 2, 0)
        local function UpdateFocusLabel()
            local lbl = (addon.ControllerLabel and addon.ControllerFocusButton)
                and addon.ControllerLabel(addon.ControllerFocusButton()):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                or "View"
            focusBtn:SetText("Focus speech bar: " .. lbl)
        end
        refreshers[#refreshers + 1] = UpdateFocusLabel
        UpdateFocusLabel()

        local tvPresetBtn = addon.UIK.Button(rPadActions, "Apply TV / Sofa Preset", 170, 24, function()
            local db = SpeakStone_MainDB
            if not (db.controllerLayout == "XBOX" or db.controllerLayout == "PS") and addon.SetControllerLayout then
                addon.SetControllerLayout((addon.ControllerDetect and addon.ControllerDetect()) or "XBOX")
            end
            db.speechTVOnPad = true
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
            if addon.SpeechFrameResetPosition then addon.SpeechFrameResetPosition() end
            NotifySetting("speechTVOnPad")
            NotifySetting("speechCompact")
            addon.RefreshSettingChecks()
            print("|cff33ff99SpeakStone:|r TV / Sofa controller settings applied.")
        end)
        tvPresetBtn:SetPoint("LEFT", focusBtn, "RIGHT", 10, 0)
        tvPresetBtn:SetSelected(true)
        rPadActions.height = 32

        -- Zone Lore
        local hLore = MakeHeader(p, "Zone lore",
            "Short voiced pieces about each zone. Turn the banner on to be offered each zone once as you enter it.")
        local rLoreTop = CreateFrame("Frame", nil, p)
        rLoreTop:SetSize(CONTENT_WIDTH, 28)
        local cLoreBanner = MakeCheck(rLoreTop, "zoneLoreBanner", "Show a banner when entering a new zone",
            "Offers the zone's lore piece once per zone as you enter it.", nil, 320)
        cLoreBanner:SetPoint("LEFT", 2, 0)
        local bLoreBook = addon.UIK.Button(rLoreTop, "Open Lore Book", 132, 22, function()
            if addon.LoreBookOpen then addon.LoreBookOpen() end
        end)
        bLoreBook:SetPoint("RIGHT", rLoreTop, "RIGHT", -2, 0)
        AttachTooltip(bLoreBook, "Lore Book", "Read and listen to every zone's story beside its map. Also /sslore.")
        rLoreTop.height = 30

        -- Community & Release Notes
        local hComm = MakeHeader(p, "Community & help")
        local rComm = CreateFrame("Frame", nil, p)
        rComm:SetSize(CONTENT_WIDTH, 62)
        local copyBox = addon.UIK.CopyBox(rComm, "https://" .. WEBSITE, CONTENT_WIDTH - 12)
        local bw = 118
        for i, spec in ipairs({
            { "Submit text",     "",        "Submit captured text and get voice packs." },
            { "Report issue",    "/report", "Flag a wrong voice or audio glitch." },
            { "Lend your voice", "/voice",  "Sign up to lend your voice to an NPC." },
        }) do
            local path = spec[2]
            local b = addon.UIK.Button(rComm, spec[1], bw, 22, function()
                copyBox:SetURL("https://" .. WEBSITE .. path)
                copyBox:SetFocus()
                copyBox:HighlightText()
            end)
            b:SetPoint("TOPLEFT", 2 + (i - 1) * (bw + 6), 0)
            AttachTooltip(b, spec[1], spec[3] .. " Puts the URL below to copy (Ctrl+C).")
        end
        local bWhatsNew = addon.UIK.Button(rComm, "What's new", 94, 22, function() addon.ShowWhatsNew() end)
        bWhatsNew:SetPoint("TOPRIGHT", rComm, "TOPRIGHT", -2, 0)
        local bClearCap = addon.UIK.Button(rComm, "Clear captures", 104, 22, function()
            StaticPopup_Show("SPEAKSTONE_CONFIRM_CLEAR_HARVEST")
        end)
        bClearCap:SetPoint("RIGHT", bWhatsNew, "LEFT", -6, 0)
        copyBox:SetPoint("TOPLEFT", 2, -30)
        rComm.height = 62

        -- Collapsible Advanced & Interface drawer
        local showAdvanced = false
        local rAdvToggle = CreateFrame("Frame", nil, p)
        rAdvToggle:SetSize(CONTENT_WIDTH, 26)
        local advBtn = addon.UIK.Button(rAdvToggle, "+ Advanced & interface options", 240, 22, function()
            showAdvanced = not showAdvanced
            RelayoutActive()
        end)
        advBtn:SetPoint("LEFT", 2, 0)
        rAdvToggle.height = 28

        local rAdv1 = MakeCheckPair(p,
            { option = "harvestEnabled", label = "Capture missing quest text",
              tooltip = "Records unvoiced quests, greetings and books (your character name is scrubbed).",
              onChange = function() if addon.RefreshSettingsStatus then addon.RefreshSettingsStatus() end end },
            { option = "showMinimapButton", label = "Show minimap button",
              tooltip = "Left-click opens settings, right-click exports captures.",
              onChange = function() if addon.UpdateMinimapButtonVisibility then addon.UpdateMinimapButtonVisibility() end end })
        local rAdv2 = MakeCheckPair(p,
            { option = "showQuestButton", label = "Show Read Quest button",
              tooltip = "Button at the bottom of the quest window and greeting window.",
              onChange = function() if addon.UpdateQuestButtonVisibility then addon.UpdateQuestButtonVisibility() end end },
            { option = "showMissingVoiceIcon", label = "Show missing-voice icon",
              tooltip = "Muted speaker beside Read Quest when a passage has no voice yet.",
              onChange = function() if addon.UpdateMissingVoiceIcons then addon.UpdateMissingVoiceIcons() end end })
        local rAdv3 = MakeCheckPair(p,
            { option = "showKTTrackerButton", label = "Show Kaliel's Tracker play icons",
              tooltip = "Small speaker beside each quest in Kaliel's Tracker.",
              onChange = function() if addon.RefreshKTTracker then addon.RefreshKTTracker() end end },
            { option = "showDialogueReportFlag", label = "Show report flag on Dialogue UI",
              tooltip = "Faint warning flag in the top-right corner of Dialogue UI.",
              onChange = function() if addon.UpdateDialogueReportFlag then addon.UpdateDialogueReportFlag() end end })
        local rAdv4 = MakeCheckPair(p,
            { option = "showReportButton", label = "Show Report button on quest window",
              tooltip = "Adds a Report button beside Read Quest on Blizzard's quest window.",
              onChange = function()
                  if addon.UpdateQuestButtonVisibility then addon.UpdateQuestButtonVisibility() end
                  if addon.UpdateMissingVoiceIcons then addon.UpdateMissingVoiceIcons() end
              end },
            { option = "showDebugMessages", label = "Show debug messages in chat",
              tooltip = "Prints which clip was chosen and when a quest has no audio." })

        local advOpen = function()
            advBtn:SetText(showAdvanced and "- Hide advanced & interface options" or "+ Advanced & interface options")
            return showAdvanced
        end

        local rows = {
            hTV, rPadLayout, 4, rTVChecks1, rTVChecks2, 4, rPadActions, 12,
            hLore, rLoreTop, 12,
            hComm, rComm, 10,
            rAdvToggle,
            { frame = rAdv1, when = advOpen },
            { frame = rAdv2, when = advOpen },
            { frame = rAdv3, when = advOpen },
            { frame = rAdv4, when = advOpen },
        }
        tabRelayout[4] = function() return LayoutRows(rows, -4) end
    end

    -- ----------------------------------------------------------------------
    -- Keep header status pills fresh
    -- ----------------------------------------------------------------------
    local function RefreshDashboard()
        -- Top-bar pills always sit on dark button fills (even on Parchment), so use bright accents for contrast.
        local good = "|cff7dff9b"
        local bad = "|cffff887a"

        if addon.GetInstalledAudioSummary then
            local packs, clips, quests = addon.GetInstalledAudioSummary()
            if clips == 0 then
                packsPill:SetText(bad .. "No voice packs|r")
                packsTooltip = "No voice packs are installed yet. Click to see what is missing, or get packs at " .. WEBSITE .. "."
            else
                local missing = MissingPacks(packs)
                if #missing == 0 then
                    packsPill:SetText(good .. clips .. " clips|r · All packs")
                    packsTooltip = string.format("%d clip(s) across %d quest(s).\nAll voice packs installed.\n\nClick to view packs in the SpeakStone Guide.", clips, quests)
                else
                    packsPill:SetText(clips .. " clips · " .. bad .. #missing .. " missing|r")
                    packsTooltip = string.format("%d clip(s) across %d quest(s).\nMissing: %s\n\nClick to view packs in the SpeakStone Guide.", clips, quests, table.concat(missing, ", "))
                end
            end
        end

        if addon.HarvestCounts then
            local capturedQuests, passages, _, npcs, glines, items, pages, _, _, _, _, bugs = addon.HarvestCounts()
            bugs = bugs or 0
            local function Count(n, one, many) return n .. " " .. (n == 1 and one or many) end
            local parts = {}
            if npcs > 0 then table.insert(parts, (glines == 1 and "greeting" or "greetings") .. " from " .. Count(npcs, "NPC", "NPCs")) end
            if items > 0 then table.insert(parts, Count(pages, "page", "pages") .. " in " .. Count(items, "book", "books")) end
            if capturedQuests > 0 then table.insert(parts, Count(passages, "passage", "passages") .. " from " .. Count(capturedQuests, "quest", "quests")) end
            if bugs > 0 then table.insert(parts, Count(bugs, "reported line", "reported lines")) end

            local entries = capturedQuests + npcs + items + bugs
            local headline = glines > 0 and glines or entries
            local recording = SpeakStone_MainDB.harvestEnabled
            local ready = addon.HarvestShouldSubmit and addon.HarvestShouldSubmit(entries)

            if not recording then
                capturesPill:SetText(bad .. headline .. " captures (off)|r")
            elseif ready then
                capturesPill:SetText(good .. headline .. " captures (export)|r")
            else
                capturesPill:SetText(headline .. " captures")
            end

            local summary = #parts > 0 and table.concat(parts, "\n") or "Nothing captured yet."
            if not recording then
                summary = summary .. "\nCapture is currently off (TV & More > Advanced)."
            elseif ready then
                summary = summary .. "\nReady to submit -- click to export."
            else
                summary = summary .. "\nClick to export everything captured so far."
            end
            capturesTooltip = summary
        end
    end

    addon.RefreshSettingsStatus = RefreshDashboard
    addon.ThemeRegister(function() if frame:IsShown() then RefreshDashboard() end end)

    -- Gamepad navigation: LB / RB switch tabs, D-pad moves between controls.
    if addon.GamepadNav then
        frame.nav = addon.GamepadNav(frame, {
            prev = function() SelectTab(activeTab > 1 and (activeTab - 1) or #TAB_SPECS) end,
            next = function() SelectTab(activeTab < #TAB_SPECS and (activeTab + 1) or 1) end,
        })
    end

    frame:HookScript("OnShow", function()
        if addon.PlaceTutorial then addon.PlaceTutorial() end
        RefreshDashboard()
        addon.RefreshSettingChecks()
        local savedTab = tonumber(SpeakStone_MainDB.settingsTab) or 1
        SelectTab((savedTab >= 1 and savedTab <= #TAB_SPECS) and savedTab or 1)
    end)

    addon.settingsWindow = frame
    return frame
end

-- Blizzard Options > AddOns doorway
function SpeakStone:CreateSettings()
    local optionsFrame = CreateFrame("Frame", nil, nil, "VerticalLayoutFrame")
    optionsFrame.spacing = 8
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

    local speechFrame = CreateFrame("Frame", nil, optionsFrame)
    speechFrame:SetSize(500, 230)
    speechFrame.layoutIndex = 4
    speechFrame.topPadding = 14
    local speechTitle = speechFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    speechTitle:SetPoint("TOPLEFT", speechFrame, "TOPLEFT", 7, 0)
    speechTitle:SetText("Quick toggles")
    CreateInfoIcon(speechFrame, "Speech bar", SPEECH_FRAME_INFO):SetPoint("LEFT", speechTitle, "RIGHT", 6, 0)

    local previous = speechTitle
    for _, spec in ipairs({
        { "showSpeechFrame", "Show the speech bar when you walk away" },
        { "speechCompact", "Compact speech bar: four scrolling lines" },
        { "speechAutoScroll", "Auto-scroll the speech bar text" },
        { "speechTVOnPad", "TV / Sofa size while using a controller" },
        { "showSubtitles", "Show subtitles instead of the speech bar" },
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

function addon:ShowSettings()
    local frame = addon.settingsWindow or SpeakStone:CreateWindow()
    frame:Show()
end

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
    elseif msg:match("^face") then
        local zoom = msg:match("^face%s+([%d%.]+)")
        if addon.SpeechFrameFace then
            local z = addon.SpeechFrameFace(tonumber(zoom))
            print(string.format("SpeakStone: head zoom %.2f (the default is 1.35; lower = closer). "
                .. "/ss frame shows your own head to try it on.", z))
        end
        return
    elseif msg == "whatsnew" or msg == "new" then
        addon.ShowWhatsNew()
        return
    end
    addon:OpenSettings()
end
