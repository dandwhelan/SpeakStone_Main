local addonName, addon = ...

-- SpeakStone in Dialogue UI's window: its voiceover provider, and a report
-- flag in the corner (further down).
--
-- SpeakStone as Dialogue UI's voiceover provider. Dialogue UI has a public
-- API for this, DialogueUIAPI.SetVOProvider (its
-- Code/SupportedAddOns/VoiceoverPublic.lua; ChattyLittleNpc uses it too).
-- Registered, its play button (and its R / left-trigger key) plays our clip,
-- its tooltip says SpeakStone is handling the voiceover or has no file for
-- this line, and its own text-to-speech no longer reads a voiced line aloud
-- over our clip. Its play button shows only when the player has turned on
-- Dialogue UI's text-to-speech; nothing changes for anyone else.
--
-- Dialogue UI calls the provider in more situations than a click, and only
-- some of them may act on our clip:
--
--   doesFileExist  every quest or gossip page it shows (DialogueUI.HandleEvent).
--   stopPlaying    four callers, told apart here:
--     * its autoplay, in the same frame as doesFileExist, before it queues a
--       play. Ignored: SpeakStone's own autoplay already started or scheduled
--       the line, with all its settings (delay, skip heard, combat, NPC voice).
--     * the window closing (its "stop when leaving", on by default). Ignored:
--       stopDialogueOnClose / keepReadingQuests decide that, as without it.
--     * a book opening (BookUI.BookCached, whatever the settings). Ignored:
--       our book narration starts at that very moment and was cut off.
--     * a click on its play button while our line plays. Acted on.
--   playFile       its autoplay timer (once after the autoplay stop above:
--                  skipped, SpeakStone's autoplay decides) or a click (plays
--                  now, as the Read Quest button does).
--   isPlaying      true only for the line its window is showing, so a click
--                  while some other clip plays starts this line rather than
--                  stopping that one.
--
-- The window-closing and book stops are told from a click one frame later:
-- by then a closed window is hidden, and a book opens with the quest window
-- closed. A stop that cannot be placed is not acted on: an unwanted silence
-- is worse than one click too few.

local PASSAGES = { detail = "description", progress = "progress", completion = "completion" }

local shown          -- what Dialogue UI last showed: { kind, id, textType, at }
local autoPendingUntil = 0

local function AutoPlayDelay()
    return tonumber(SpeakStone_MainDB and SpeakStone_MainDB.autoPlayDelay) or 1.0
end

local function Secret(value)
    return addon.IsSecret and addon.IsSecret(value)
end

-- Whether a clip is the line Dialogue UI's window is showing.
local function Matches(sd)
    if not sd or not shown then
        return false
    end
    if shown.kind == "quest" then
        return sd.questID == shown.id and sd.textType == shown.textType
    end
    return sd.textType == "gossip" and sd.questID == "npc" .. shown.id
end

local function DoesFileExist(interactionType, id, arg1, arg2)
    shown, autoPendingUntil = nil, 0
    if Secret(id) or Secret(arg1) then
        return false
    end
    local ok, found = pcall(function()
        if interactionType == "quest" then
            local textType = PASSAGES[arg1]
            if type(id) == "number" and id > 0 and textType then
                shown = { kind = "quest", id = id, textType = textType, at = GetTime() }
                return addon.QuestClipFor(id, textType) ~= nil
            end
        elseif interactionType == "gossip" then
            -- Game objects (plaques, boards) have no gossip clips.
            if type(id) == "number" and (arg1 == "Creature" or arg1 == "Vehicle") then
                shown = { kind = "gossip", id = id, at = GetTime() }
                return addon.GossipClipFor(id, arg2) ~= nil
            end
        end
        return false
    end)
    if not ok then
        geterrorhandler()(found)
        return false
    end
    return found == true
end

local function PlayFile(interactionType, id, arg1)
    -- Dialogue UI's autoplay timer: SpeakStone's own autoplay has this line.
    if GetTime() <= autoPendingUntil then
        autoPendingUntil = 0
        return
    end
    if interactionType == "quest" then
        local textType = PASSAGES[arg1]
        if textType and type(id) == "number" then
            PlayQuestAudio(textType, true, id)
        end
    elseif interactionType == "gossip" then
        addon.PlayGossipAudio(true)
    end
end

local function StopPlaying()
    -- Same frame as doesFileExist: Dialogue UI's autoplay clearing the way
    -- for the play it is about to queue.
    if shown and shown.at == GetTime() then
        -- Its queue waits our delay (at least 0.5 s); a second over that and
        -- a play is a click again, not this autoplay.
        autoPendingUntil = GetTime() + math.max(AutoPlayDelay(), 0.5) + 1
        return
    end
    local sd = addon.activeSound
    if not sd or sd.textType == "item" or not Matches(sd) then
        return
    end
    C_Timer.After(0, function()
        local ui = _G.DUIQuestFrame
        if addon.activeSound == sd and ui and ui.IsShown and ui:IsShown() then
            addon.StopCurrentSound()
        end
    end)
end

local function IsPlaying()
    local sd = addon.activeSound
    return (sd and sd.isPlaying and Matches(sd)) and true or false
end

-- Another voiceover addon already speaks through Dialogue UI: leave it be
-- rather than take its place (Dialogue UI keeps one provider and prints a
-- warning when a second arrives).
local OTHER_PROVIDERS = { "ChattyLittleNpc" }

local registered = false

local function Register()
    local api = _G.DialogueUIAPI
    if registered or type(api) ~= "table" or type(api.SetVOProvider) ~= "function" then
        return
    end
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
    for _, name in ipairs(OTHER_PROVIDERS) do
        if isLoaded and isLoaded(name) then
            if addon.DebugPrint then
                addon.DebugPrint("SpeakStone: " .. name .. " already voices Dialogue UI -- not registering with it")
            end
            return
        end
    end
    registered = true
    api.SetVOProvider({
        name = "SpeakStone",
        doesFileExist = DoesFileExist,
        playFile = PlayFile,
        stopPlaying = StopPlaying,
        isPlaying = IsPlaying,
        getAutoPlayDelay = AutoPlayDelay,
    })
end
addon.RegisterDialogueUIVoice = Register

-- --------------------------------------------------------------------------
-- Report flag (showDialogueReportFlag): a small warning sign in the top-right
-- corner of Dialogue UI's window (left of its Copy Text button), on a quest page or
-- greeting SpeakStone voices. Click: the usual report menu for that line
-- (addon.OpenReportMenu), into the capture export. Owner, 2026-11-06.
--
-- The line is worked out from Dialogue UI's page builders (hooked, as
-- DialogueSync.lua does), not from the provider calls above, so the flag
-- works when another voiceover addon has Dialogue UI's provider slot.
-- --------------------------------------------------------------------------
local FLAG_ICON = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew"
local PAGE_PASSAGES = {
    HandleQuestDetail = "description",
    HandleQuestProgress = "progress",
    HandleQuestComplete = "completion",
}
local flag, flagLine

-- The voiced line the page Dialogue UI just built shows, as the report menu
-- wants it, or nil.
local function LineOnPage(handler)
    local passage = PAGE_PASSAGES[handler]
    if passage then
        local questID = GetQuestID()
        if type(questID) ~= "number" or questID <= 0 or Secret(questID) then
            return nil
        end
        local soundFile = addon.QuestClipFor(questID, passage)
        if not soundFile then
            return nil
        end
        local line = { questID = questID, textType = passage, soundFile = soundFile,
                       npcGUID = UnitGUID("npc"), npcName = UnitName("npc") }
        if addon.CaptureQuestText then
            line.text, line.title = addon.CaptureQuestText(questID, passage)
        end
        return line
    elseif handler == "HandleGossip" then
        local npcID = addon.CurrentGossipNPC and addon.CurrentGossipNPC()
        if not npcID then
            return nil
        end
        local ok, text = pcall(C_GossipInfo.GetText)
        text = ok and not Secret(text) and text or nil
        local soundFile = addon.GossipClipFor(npcID, text)
        if not soundFile then
            return nil
        end
        return { questID = "npc" .. npcID, textType = "gossip", soundFile = soundFile,
                 npcGUID = UnitGUID("npc"), npcName = UnitName("npc"), text = text }
    end
    return nil
end

function addon.UpdateDialogueReportFlag()
    if not flag then
        return
    end
    local ui = _G.DUIQuestFrame
    local show = flagLine ~= nil and SpeakStone_MainDB and SpeakStone_MainDB.showDialogueReportFlag ~= false
    if show then
        -- Top right (owner, 2026-11-07: the top left is Dialogue UI's play
        -- button). That corner holds Dialogue UI's own Copy Text and translator
        -- buttons when they are on (its LayoutTopWidgets: Copy Text at the
        -- corner, the translator to its left), so the flag goes left of them.
        flag:ClearAllPoints()
        local function Shown(b) return b and b.IsShown and b:IsShown() end
        local copy, translate = ui and ui.CopyTextButton, ui and ui.TranslatorButton
        local leftmost = (Shown(translate) and translate) or (Shown(copy) and copy) or nil
        if leftmost then
            flag:SetPoint("RIGHT", leftmost, "LEFT", -4, 0)
        else
            flag:SetPoint("TOPRIGHT", ui, "TOPRIGHT", -10, -10)
        end
    end
    flag:SetShown(show and true or false)
end

local function MakeFlag(ui)
    local b = CreateFrame("Button", nil, ui)
    b:SetSize(20, 20)
    b:SetFrameLevel(ui:GetFrameLevel() + 10)
    b:SetNormalTexture(FLAG_ICON)
    -- Grey and faint until the mouse is on it, so it does not stand out (owner, 2026-11-07).
    local function Quiet(self, on)
        local tex = self:GetNormalTexture()
        if tex then tex:SetDesaturated(not on) end
        self:SetAlpha(on and 1 or 0.3)
    end
    Quiet(b, false)
    b:SetScript("OnEnter", function(self)
        Quiet(self, true)
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        GameTooltip:AddLine("Report this voice line", 1, 0.82, 0)
        GameTooltip:AddLine("Wrong voice, audio glitch, pronunciation, text that doesn't match: "
            .. "click to pick what is wrong. It goes into your capture export.", 1, 1, 1, true)
        if flagLine then
            GameTooltip:AddLine(tostring(flagLine.soundFile), 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        Quiet(self, false)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function(self)
        if flagLine then
            addon.OpenReportMenu(self, flagLine)
        end
    end)
    b:Hide()
    return b
end

local function HookReportFlag()
    local ui = _G.DUIQuestFrame
    if flag or not ui or type(hooksecurefunc) ~= "function" then
        return
    end
    flag = MakeFlag(ui)
    for _, handler in ipairs({ "HandleQuestDetail", "HandleQuestProgress", "HandleQuestComplete",
                               "HandleQuestGreeting", "HandleGossip" }) do
        if type(ui[handler]) == "function" then
            hooksecurefunc(ui, handler, function()
                local ok, line = pcall(LineOnPage, handler)
                flagLine = ok and line or nil
                addon.UpdateDialogueReportFlag()
            end)
        end
    end
end
addon.HookDialogueReportFlag = HookReportFlag

-- PLAYER_LOGIN: every addon is loaded by then, whichever loaded first.
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    Register()
    HookReportFlag()
end)
