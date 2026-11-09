-- Kaliel's Tracker integration (owner, 2026-11-09; player report SpeakStone_Main#28).
--
-- Kaliel's Tracker (KT) draws its own copy of the quest details panel (KT_QuestsFrame.DetailsFrame) instead of
-- the game's QuestMapFrame.DetailsFrame, so SpeakStone's Play button and "no voice yet" icon never showed there.
-- KT is not changed: everything here hooks KT from our side, and does nothing when KT is not loaded. KT's
-- internal names can change in a KT update, so every hook is guarded: a missing name means no button, not an error.
--
--   1. Play + "no voice yet" on KT's quest details panel.
--   2. A small play button beside each quest title in KT's tracker (only for quests with audio).
--   3. PlayQuestAudio / autoplay treat KT's open details panel like the quest log (SpeakStone_Main.lua).

local addonName, addon = ...

local KT_ICON = "Interface\\Common\\VoiceChat-Speaker"
local KT_ICON_ON = "Interface\\Common\\VoiceChat-On"

-- The quest KT's details panel is showing, or nil when it is closed.
function addon.KTDetailsQuestID()
    local f = KT_QuestsFrame and KT_QuestsFrame.DetailsFrame
    if f and f:IsVisible() and type(f.questID) == "number" and f.questID > 0 then
        return f.questID
    end
    return nil
end

local function IsPlaying(questID)
    local cur = addon.GetCurrentSound and addon.GetCurrentSound()
    return cur and questID and cur.questID == questID and cur.isPlaying
end

local function Toggle(questID)
    if not questID then return end
    if IsPlaying(questID) then
        addon.StopCurrentSound()
    else
        addon.PlayQuestAudio("description", true, questID)
    end
end

local function Voiced(questID)
    return questID and addon.QuestClipFor and addon.QuestClipFor(questID, "description") ~= nil
end

-- 1. KT's quest details panel ----------------------------------------------------------------------------------

local detailsButton, detailsMissing

local function UpdateDetails()
    if not detailsButton then return end
    local qid = addon.KTDetailsQuestID()
    local back = KT_QuestsFrame.DetailsFrame.BackFrame and KT_QuestsFrame.DetailsFrame.BackFrame.BackButton
    if back then
        detailsButton:ClearAllPoints()
        detailsButton:SetPoint("RIGHT", back:GetParent(), "RIGHT", -10, 0)
        detailsButton:SetPoint("TOP", back, "TOP", 0, 0)
        detailsButton:SetFrameLevel(back:GetFrameLevel() + 1)
    end
    detailsButton:SetShown(SpeakStone_MainDB.showQuestButton and true or false)
    detailsButton:SetText(IsPlaying(qid) and "Stop" or "Play")
    if detailsMissing then
        detailsMissing:SetShown(SpeakStone_MainDB.showMissingVoiceIcon ~= false and qid ~= nil and not Voiced(qid))
    end
end

local function HookDetails()
    local f = KT_QuestsFrame and KT_QuestsFrame.DetailsFrame
    if not f or detailsButton then return end
    local back = f.BackFrame and f.BackFrame.BackButton
    detailsButton = CreateFrame("Button", "SpeakStoneKTDetailsButton", back and back:GetParent() or f, "UIPanelButtonTemplate")
    detailsButton:SetSize(75, back and back:GetHeight() or 22)
    detailsButton:SetText("Play")
    if not back then detailsButton:SetPoint("TOPLEFT", f, "TOPLEFT", 105, -10) end
    addon.SetUpPlayButton(detailsButton, {
        kind = "quest", title = "Read the quest description",
        hint = "Left-click: play it, or stop it while it plays.",
        onClick = function() Toggle(addon.KTDetailsQuestID()); UpdateDetails() end,
        voiced = function() return Voiced(addon.KTDetailsQuestID()) end,
    })
    table.insert(addon.questButtons, detailsButton)

    detailsMissing = CreateFrame("Button", nil, detailsButton:GetParent())
    detailsMissing:SetSize(20, 20)
    detailsMissing:SetNormalTexture("Interface\\Common\\VoiceChat-Muted")
    detailsMissing:GetNormalTexture():SetVertexColor(0.75, 0.75, 0.75)
    detailsMissing:SetPoint("RIGHT", detailsButton, "LEFT", -4, 0)
    detailsMissing:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("No voice yet", 1, 0.82, 0)
        GameTooltip:AddLine("SpeakStone has no recording of this text. With capture on, it has been "
            .. "saved for you: export it from /ss and send it in at speakstone.beanw.co.uk "
            .. "so it can be voiced.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    detailsMissing:SetScript("OnLeave", function() GameTooltip:Hide() end)
    detailsMissing:Hide()

    f:HookScript("OnShow", function() C_Timer.After(0, UpdateDetails) end)
    if type(KT_QuestMapFrame_ShowQuestDetails) == "function" then
        hooksecurefunc("KT_QuestMapFrame_ShowQuestDetails", function() C_Timer.After(0, UpdateDetails) end)
    end
end

-- 2. Play button beside each quest in KT's tracker -------------------------------------------------------------

local trackerButtons = {}   -- block -> button (KT recycles blocks, so one button per block, re-pointed each layout)

local function UpdateTrackerButton(b)
    local tex = IsPlaying(b.questID) and KT_ICON_ON or KT_ICON
    b:SetNormalTexture(tex)
    local t = b:GetNormalTexture()
    if b.voiced then t:SetVertexColor(1, 1, 1) t:SetAlpha(1) else t:SetVertexColor(0.5, 0.5, 0.5) t:SetAlpha(0.6) end
end

local function TrackerButtonFor(block)
    local b = trackerButtons[block]
    if b then return b end
    b = CreateFrame("Button", nil, block)
    b:SetSize(16, 16)
    b:SetNormalTexture(KT_ICON)
    b:SetHighlightTexture(KT_ICON, "ADD")
    addon.SetUpPlayButton(b, {
        kind = "quest", title = "Read the quest description",
        hint = "Left-click: play it, or stop it while it plays.",
        onClick = function(self)
            if self.voiced then Toggle(self.questID) end
            UpdateTrackerButton(self)
        end,
        voiced = function(self) return Voiced(b.questID) end,
    })
    trackerButtons[block] = b
    return b
end

local function OnLayoutBlock(_, block)
    if type(block) ~= "table" or not block.HeaderText then return end
    local qid = type(block.id) == "number" and block.id or nil
    local show = qid and SpeakStone_MainDB.showKTTrackerButton ~= false
    local b = trackerButtons[block]
    if not show then
        if b and b:IsShown() then
            b:Hide()
            block.HeaderText:SetPoint("RIGHT", block.rightEdgeOffset or 0, 0)   -- give KT its title width back
        end
        return
    end
    b = TrackerButtonFor(block)
    b.questID = qid
    b.voiced = Voiced(qid) and true or false
    b:SetFrameLevel(block:GetFrameLevel() + 5)
    b:ClearAllPoints()
    -- Right end of the title line, left of KT's own item button when there is one.
    if block.rightEdgeFrame and block.rightEdgeFrame:IsShown() then
        b:SetPoint("RIGHT", block.rightEdgeFrame, "LEFT", -4, 0)
    else
        b:SetPoint("TOPRIGHT", block, "TOPRIGHT", -2, 0)
    end
    block.HeaderText:SetPoint("RIGHT", b, "LEFT", -2, 0)
    UpdateTrackerButton(b)
    b:Show()
end

local function HookTracker()
    for _, name in ipairs({ "KT_QuestObjectiveTracker", "KT_CampaignQuestObjectiveTracker" }) do
        local module = _G[name]
        if type(module) == "table" and type(module.LayoutBlock) == "function" and not module.ssHooked then
            hooksecurefunc(module, "LayoutBlock", OnLayoutBlock)
            module.ssHooked = true
        end
    end
end

-- The settings toggle (showKTTrackerButton): add or remove the buttons on the quests already on screen.
function addon.RefreshKTTracker()
    for block in pairs(trackerButtons) do
        if block:IsShown() then OnLayoutBlock(nil, block) end
    end
    if SpeakStone_MainDB.showKTTrackerButton ~= false then
        for _, m in ipairs({ KT_QuestObjectiveTracker, KT_CampaignQuestObjectiveTracker }) do
            if m and m.usedBlocks then
                for _, byKey in pairs(m.usedBlocks) do
                    if type(byKey) == "table" then
                        for _, block in pairs(byKey) do OnLayoutBlock(nil, block) end
                    end
                end
            end
        end
    end
end

-- Keep every KT button's Play/Stop state in step with playback.
function addon.UpdateKTButtons()
    if detailsButton then UpdateDetails() end
    for _, b in pairs(trackerButtons) do
        if b:IsShown() then UpdateTrackerButton(b) end
    end
end

local function Init()
    if not (KT_QuestsFrame or KT_QuestObjectiveTracker) then return false end
    local ok, err = pcall(function()
        HookDetails()
        HookTracker()
    end)
    if not ok and SpeakStone_MainDB and SpeakStone_MainDB.debugMode then
        print("|cffffd100SpeakStone:|r Kaliel's Tracker hook failed: " .. tostring(err))
    end
    return true
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name ~= "!KalielsTracker" then return end
    -- KT builds its tracker modules during its own login; try again once the world is up.
    if Init() and event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterAllEvents()
        if SpeakStone_MainDB and SpeakStone_MainDB.showDebugMessages then
            local n = 0
            for _, m in ipairs({ KT_QuestObjectiveTracker, KT_CampaignQuestObjectiveTracker }) do
                if m and m.ssHooked then n = n + 1 end
            end
            print("|cffffd100SpeakStone:|r Kaliel's Tracker found; tracker hooks: " .. n .. ", details panel: "
                .. (detailsButton and "yes" or "no"))
        end
    end
end)

-- Play/Stop text follows playback on a light ticker only while a KT button is on screen.
local ticker = C_Timer.NewTicker(0.5, function()
    if (detailsButton and detailsButton:IsVisible()) or next(trackerButtons) then
        addon.UpdateKTButtons()
    end
end)
-- No Kaliel's Tracker after login: stop the ticker, nothing here will ever show.
local stop = CreateFrame("Frame")
stop:RegisterEvent("PLAYER_ENTERING_WORLD")
stop:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if not (KT_QuestsFrame or KT_QuestObjectiveTracker) then ticker:Cancel() end
end)
