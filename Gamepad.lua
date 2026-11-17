local addonName, addon = ...

-- Controller support for the speech bar (owner, 2026-11-17), after Dialogue UI's approach: ask which controller
-- is in use the first time one is pressed, and name the buttons to match.
--
-- The bar shows over gameplay (you have walked away from the quest giver), so it cannot take the face buttons
-- for itself all the time. Instead one button -- View on Xbox, Create/Share on PlayStation -- "picks up" the
-- bar while it is on screen. While held, the face buttons drive it and the D-pad moves it; the same button, a
-- few seconds idle, combat, or the bar closing puts it down and the buttons go back to the game.
--
-- The four actions are also key bindings (Key Bindings > SpeakStone), so they can be put on any controller
-- combination in the game's own gamepad bindings.

local function DB()
    return SpeakStone_ForeverMainDB or SpeakStone_MainDB or {}
end

local IDLE_SECONDS = 8
local NUDGE = 12          -- UIParent units per D-pad step
local REPEAT_DELAY, REPEAT_RATE = 0.35, 0.05

-- WoW names face buttons by position on every pad: PAD1 bottom, PAD2 right, PAD3 left, PAD4 top.
local LABELS = {
    XBOX = { PAD1 = "A", PAD2 = "B", PAD3 = "X", PAD4 = "Y", PADBACK = "View", PADLSHOULDER = "LB", PADRSHOULDER = "RB", PADLSTICK = "LS", PADRSTICK = "RS" },
    PS = { PAD1 = "Cross", PAD2 = "Circle", PAD3 = "Square", PAD4 = "Triangle", PADBACK = "Create", PADLSHOULDER = "L1", PADRSHOULDER = "R1", PADLSTICK = "L3", PADRSTICK = "R3" },
}

local ACTIONS = {
    PAD1 = "pause",
    PAD3 = "next",
    PAD4 = "replay",
    PAD2 = "stop",
}

local MOVES = {
    PADDUP = { 0, 1 }, PADDDOWN = { 0, -1 }, PADDLEFT = { -1, 0 }, PADDRIGHT = { 1, 0 },
}

local function Layout()
    local l = DB().controllerLayout
    return (l == "XBOX" or l == "PS") and l or nil
end

local function FocusButton()
    return DB().controllerFocusButton or "PADBACK"
end

local function Label(button)
    local set = LABELS[Layout() or "XBOX"]
    return "|cffffd100[" .. (set[button] or button) .. "]|r"
end

-- --------------------------------------------------------------------------
-- Which controller? (asked once, like Dialogue UI's splash)
-- --------------------------------------------------------------------------

local function Detect()
    if not (C_GamePad and C_GamePad.GetAllDeviceIDs) then return nil end
    for _, id in pairs(C_GamePad.GetAllDeviceIDs()) do
        local raw = C_GamePad.GetDeviceRawState and C_GamePad.GetDeviceRawState(id)
        local name = raw and raw.name and string.upper(raw.name) or ""
        if name:find("PLAYSTATION") or name:find("DUALSENSE") or name:find("DUALSHOCK") then
            return "PS"
        elseif name:find("XBOX") then
            return "XBOX"
        end
    end
    return nil
end

StaticPopupDialogs["SPEAKSTONE_CONTROLLER_LAYOUT"] = {
    text = "SpeakStone: which controller are you using?\n\nThe speech bar will name its buttons to match. "
        .. "Press %s while it is on screen to pause, skip, replay, stop or move it.",
    button1 = "Xbox",
    button2 = "PlayStation",
    button3 = "Keyboard",
    OnAccept = function() DB().controllerLayout = "XBOX" end,
    OnCancel = function(_, _, reason)
        if reason == "clicked" then DB().controllerLayout = "PS" end
    end,
    OnAlt = function() DB().controllerLayout = "KBM" end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local asked = false
local function AskLayout()
    if asked or DB().controllerLayout then return end
    asked = true
    local detected = Detect()
    if detected then
        -- Known pad: no need to ask; say what was picked.
        DB().controllerLayout = detected
        print("|cff33ff99SpeakStone:|r " .. (detected == "PS" and "PlayStation" or "Xbox")
            .. " controller found. Press " .. Label(FocusButton()) .. " while the speech bar is up to control it. "
            .. "Change it in the bar's gear menu.")
        return
    end
    StaticPopup_Show("SPEAKSTONE_CONTROLLER_LAYOUT", "View / Create")
end

-- --------------------------------------------------------------------------
-- Holding the bar
-- --------------------------------------------------------------------------

local listener = CreateFrame("Frame", "SpeakStoneGamepadListener", UIParent)
listener:SetFrameStrata("DIALOG")
listener:SetSize(1, 1)
listener:SetPoint("TOPLEFT")
listener:Hide()
listener.focused = false
listener.lastInput = 0

local hint  -- the button legend under the bar

local function BuildHint(frame)
    if hint then return end
    hint = CreateFrame("Frame", nil, frame)
    hint:SetSize(1, 22)
    hint:SetPoint("TOP", frame, "BOTTOM", 0, -2)
    hint.bg = hint:CreateTexture(nil, "BACKGROUND")
    hint.bg:SetColorTexture(0, 0, 0, 0.6)
    hint.bg:SetAllPoints()
    hint.text = hint:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint.text:SetPoint("CENTER")
end

local function UpdateHint()
    local frame = addon.SpeechFrameGet and addon.SpeechFrameGet()
    if not frame then return end
    BuildHint(frame)
    if not Layout() or not frame:IsShown() then
        hint:Hide()
        return
    end
    local text
    if listener.focused then
        text = Label("PAD1") .. " Pause/Resume   " .. Label("PAD3") .. " Next   " .. Label("PAD4") .. " Replay   "
            .. Label("PAD2") .. " Stop   |cffffd100[D-pad]|r Move   " .. Label("PADLSHOULDER") .. "/"
            .. Label("PADRSHOULDER") .. " Size   " .. Label(FocusButton()) .. " Done"
    else
        text = Label(FocusButton()) .. " Control the speech bar"
    end
    hint.text:SetText(text)
    hint:SetWidth(hint.text:GetStringWidth() + 16)
    hint:SetAlpha(listener.focused and 1 or 0.6)
    hint:Show()
end

local function SetFocus(on)
    if on and InCombatLockdown() then
        print("|cff33ff99SpeakStone:|r can't take the controller in combat; use the key bindings instead.")
        return
    end
    listener.focused = on
    listener.lastInput = GetTime()
    listener.repeatKey = nil
    UpdateHint()
end

local function Propagate(yes)
    -- Protected in combat; there we never take a button anyway.
    if not InCombatLockdown() then
        listener:SetPropagateKeyboardInput(yes)
    end
end

local function DoMove(button)
    local m = MOVES[button]
    if m then addon.SpeechFrameNudge(m[1] * NUDGE, m[2] * NUDGE) end
end

listener:SetScript("OnGamePadButtonDown", function(self, button)
    if not Layout() or InCombatLockdown() then
        Propagate(true)
        return
    end
    local frame = addon.SpeechFrameGet()
    if not (frame and frame:IsShown()) then
        Propagate(true)
        return
    end
    if button == FocusButton() then
        Propagate(false)
        SetFocus(not self.focused)
        return
    end
    if not self.focused then
        Propagate(true)
        return
    end
    self.lastInput = GetTime()
    if ACTIONS[button] then
        Propagate(false)
        addon.SpeechFrameControl(ACTIONS[button])
        if button == "PAD2" then SetFocus(false) end
    elseif MOVES[button] then
        Propagate(false)
        DoMove(button)
        self.repeatKey, self.repeatAt = button, GetTime() + REPEAT_DELAY
    elseif button == "PADLSHOULDER" or button == "PADRSHOULDER" then
        Propagate(false)
        addon.SpeechFrameResize(button == "PADRSHOULDER" and 1 or -1)
    else
        -- Sticks, triggers, menu: back to the game, and let go so the player can just carry on.
        Propagate(true)
        SetFocus(false)
    end
    UpdateHint()
end)

listener:SetScript("OnGamePadButtonUp", function(self, button)
    if button == self.repeatKey then self.repeatKey = nil end
    -- Each press decides for itself; never leave the pad swallowed.
    Propagate(true)
end)

listener:SetScript("OnUpdate", function(self)
    local frame = addon.SpeechFrameGet and addon.SpeechFrameGet()
    local shown = frame and frame:IsShown()
    if self.focused then
        local now = GetTime()
        if not shown or now - self.lastInput > IDLE_SECONDS then
            SetFocus(false)
        elseif self.repeatKey and now >= self.repeatAt then
            DoMove(self.repeatKey)
            self.lastInput = now
            self.repeatAt = now + REPEAT_RATE
        end
    end
    if hint and hint:IsShown() ~= (shown and Layout() ~= nil) then
        UpdateHint()
    end
end)

local function Enable()
    if not listener.EnableGamePadButton or InCombatLockdown() then return end
    listener:SetPropagateKeyboardInput(true)
    listener:EnableGamePadButton(true)
    listener.enabled = true
    listener:Show()
end

-- --------------------------------------------------------------------------
-- Events
-- --------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(events.RegisterEvent, events, "GAME_PAD_ACTIVE_CHANGED")
pcall(events.RegisterEvent, events, "GAME_PAD_CONNECTED")
events:SetScript("OnEvent", function(_, event, arg)
    if event == "PLAYER_ENTERING_WORLD" then
        if C_GamePad and C_GamePad.IsEnabled and C_GamePad.IsEnabled() then Enable() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Fires just before lockdown: hand everything back and step aside for the fight.
        if listener.focused then SetFocus(false) end
        listener:SetPropagateKeyboardInput(true)
        listener:Hide()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if listener.enabled then listener:Show() end
    elseif event == "GAME_PAD_CONNECTED" or (event == "GAME_PAD_ACTIVE_CHANGED" and arg) then
        Enable()
        AskLayout()
    end
end)

-- For the gear menu.
function addon.ControllerLayout()
    return DB().controllerLayout
end

function addon.SetControllerLayout(key)
    DB().controllerLayout = key
    if key ~= "KBM" then Enable() end
    UpdateHint()
end

function addon.ControllerFocusButton()
    return FocusButton()
end

function addon.SetControllerFocusButton(button)
    DB().controllerFocusButton = button
    UpdateHint()
end

addon.ControllerLabel = Label

-- --------------------------------------------------------------------------
-- Key bindings (globals on purpose: Bindings.xml calls them by name)
-- --------------------------------------------------------------------------

function SpeakStone_Stop() addon.SpeechFrameControl("stop") end
function SpeakStone_Next() addon.SpeechFrameControl("next") end
function SpeakStone_Replay() addon.SpeechFrameControl("replay") end
function SpeakStone_ControllerFocus()
    local frame = addon.SpeechFrameGet and addon.SpeechFrameGet()
    if frame and frame:IsShown() then SetFocus(not listener.focused) end
end

BINDING_NAME_SPEAKSTONESTOP = "Stop narration (clears the queue)"
BINDING_NAME_SPEAKSTONENEXT = "Next queued quest"
BINDING_NAME_SPEAKSTONEREPLAY = "Replay the line"
BINDING_NAME_SPEAKSTONEPADFOCUS = "Controller: take / release the speech bar"
