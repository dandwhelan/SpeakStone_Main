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

-- The game's own button pictures (UiTextureAtlasMember, gamepad_ltr_* = Xbox letters, gamepad_shp_* = PlayStation
-- shapes). Shown inline in text; a button whose picture this client lacks falls back to its gold [name].
local ICONS = {
    XBOX = { PAD1 = "gamepad_ltr_a_64", PAD2 = "gamepad_ltr_b_64", PAD3 = "gamepad_ltr_x_64", PAD4 = "gamepad_ltr_y_64",
        PADBACK = "gamepad_ltr_view_64", PADFORWARD = "gamepad_ltr_menu_64",
        PADLSHOULDER = "gamepad_ltr_lshoulder_64", PADRSHOULDER = "gamepad_ltr_rshoulder_64",
        PADLSTICK = "gamepad_gen_lstickin_64", PADRSTICK = "gamepad_gen_rstickin_64",
        PADDUP = "gamepad_ltr_up_64", PADDDOWN = "gamepad_ltr_down_64",
        PADDLEFT = "gamepad_ltr_left_64", PADDRIGHT = "gamepad_ltr_right_64" },
    PS = { PAD1 = "gamepad_shp_cross_64", PAD2 = "gamepad_shp_circle_64", PAD3 = "gamepad_shp_square_64",
        PAD4 = "gamepad_shp_triangle_64", PADBACK = "gamepad_shp_share_64", PADFORWARD = "gamepad_shp_menu_64",
        PADLSHOULDER = "gamepad_shp_lshoulder_64", PADRSHOULDER = "gamepad_shp_rshoulder_64",
        PADLSTICK = "gamepad_shp_lstickin_64", PADRSTICK = "gamepad_shp_rstickin_64",
        PADDUP = "gamepad_shp_up_64", PADDDOWN = "gamepad_shp_down_64",
        PADDLEFT = "gamepad_shp_left_64", PADDRIGHT = "gamepad_shp_right_64" },
}
local ICON_SIZE = 18

local hasAtlas = {}
local function AtlasExists(name)
    if hasAtlas[name] == nil then
        hasAtlas[name] = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)) and true or false
    end
    return hasAtlas[name]
end

local function Icon(layout, button)
    local atlas = ICONS[layout][button]
    if atlas and AtlasExists(atlas) then
        return "|A:" .. atlas .. ":" .. ICON_SIZE .. ":" .. ICON_SIZE .. "|a"
    end
end

local function Label(button)
    local layout = Layout() or "XBOX"
    if button == "DPAD" then
        local up, down = Icon(layout, "PADDUP"), Icon(layout, "PADDDOWN")
        local left, right = Icon(layout, "PADDLEFT"), Icon(layout, "PADDRIGHT")
        if up and down and left and right then return left .. up .. down .. right end
        return "|cffffd100[D-pad]|r"
    end
    return Icon(layout, button) or ("|cffffd100[" .. (LABELS[layout][button] or button) .. "]|r")
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

-- Which device the player is using right now: the game says when it flips between controller and mouse.
-- The bar's line count and the TV size (speechTVOnPad) follow it.
addon.padActive = false
local function PadActiveChanged(active)
    active = active and true or false
    if addon.padActive == active then return end
    addon.padActive = active
    if not addon.SpeechSettingChanged then return end
    -- The bar keeps to three lines on a controller (SpeechFrame Lines()), so refit it either way.
    addon.SpeechSettingChanged("speechLines")
    if DB().speechTVOnPad then
        addon.SpeechSettingChanged("speechTextSize")
        addon.SpeechSettingChanged("speechSize")
    end
end

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

-- While the player holds the bar, each of its own buttons wears the pad button that works it (owner,
-- 2026-11-18), as well as the legend underneath.
local BADGE_SIZE = 13

local function Badges(frame, on)
    local controls = frame.controls
    if not controls then return end
    local layout = Layout()
    for button, action in pairs(ACTIONS) do
        local target = controls[action]
        if target then
            local atlas = on and layout and ICONS[layout][button]
            if atlas and AtlasExists(atlas) then
                if not target.padBadge then
                    target.padBadge = target:CreateTexture(nil, "OVERLAY", nil, 7)
                    target.padBadge:SetSize(BADGE_SIZE, BADGE_SIZE)
                    target.padBadge:SetPoint("CENTER", target, "BOTTOMRIGHT", 1, 1)
                end
                target.padBadge:SetAtlas(atlas)
                target.padBadge:Show()
            elseif target.padBadge then
                target.padBadge:Hide()
            end
        end
    end
end

local function UpdateHint()
    local frame = addon.SpeechFrameGet and addon.SpeechFrameGet()
    if not frame then return end
    BuildHint(frame)
    Badges(frame, listener.focused and Layout() ~= nil and frame:IsShown())
    if not Layout() or not frame:IsShown() or DB().controllerShowLegend == false then
        hint:Hide()
        return
    end
    local text
    if listener.focused then
        text = Label("PAD1") .. " Pause/Resume   " .. Label("PAD3") .. " Next   " .. Label("PAD4") .. " Replay   "
            .. Label("PAD2") .. " Stop   " .. Label("DPAD") .. " Move   " .. Label("PADLSHOULDER") .. "/"
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
    -- A button press means the controller is in use, even if the game has not said so yet (it only
    -- reports a change, so a player who logs in on the pad would otherwise stay on mouse sizes).
    PadActiveChanged(true)
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
    if hint and hint:IsShown() ~= (shown and Layout() ~= nil and DB().controllerShowLegend ~= false) then
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
    elseif event == "GAME_PAD_ACTIVE_CHANGED" then
        PadActiveChanged(arg)
        if arg then
            Enable()
            AskLayout()
        end
    elseif event == "GAME_PAD_CONNECTED" then
        Enable()
        AskLayout()
    end
end)

-- A short buzz: "queue" when a quest joins the queue, "next" when a queued quest starts.
function addon.Rumble(kind)
    if not (Layout() and addon.padActive and DB().controllerRumble ~= false) then return end
    if not (C_GamePad and C_GamePad.SetVibration) then return end
    local pulses = kind == "next" and 2 or 1
    for i = 1, pulses do
        C_Timer.After((i - 1) * 0.25, function()
            pcall(C_GamePad.SetVibration, "Low", 0.6)
            C_Timer.After(0.12, function() pcall(C_GamePad.StopVibration) end)
        end)
    end
end

-- For the gear menu.
function addon.ControllerLayout()
    return DB().controllerLayout
end

function addon.SetControllerLayout(key)
    DB().controllerLayout = key
    if key ~= "KBM" then Enable() end
    UpdateHint()
    local tut = SpeakStoneTutorialFrame
    if tut and tut:IsShown() and addon.PlaceTutorial then addon.PlaceTutorial() end
    if tut and tut.ssNav then tut.ssNav.Refresh() end
end

function addon.ControllerFocusButton()
    return FocusButton()
end

function addon.SetControllerFocusButton(button)
    DB().controllerFocusButton = button
    UpdateHint()
end

addon.ControllerLabel = Label
addon.ControllerDetect = Detect

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

-- --------------------------------------------------------------------------
-- Driving a window with the controller (the tutorial; owner, 2026-11-18)
-- --------------------------------------------------------------------------
-- A gold box sits on one button or tick box at a time. D-pad moves it to the nearest one that way, A/Cross
-- presses it, B/Circle goes back, LB/RB (L1/R1) turn the page, Menu/Options goes on. While the window is open
-- it takes the controller (out of combat only); the sticks still go to the game.

local function Usable(w)
    if w and w.IsObjectType and w:IsObjectType("Slider") then
        return w:IsVisible() and w:IsEnabled() and w:GetLeft() ~= nil and w:GetOrientation() == "HORIZONTAL"
    end
    return w and w:IsVisible() and w:IsEnabled() and w:IsMouseEnabled() and w:GetScript("OnClick") ~= nil
        and w:GetLeft() ~= nil
end

-- Every clickable button / tick box under `root`, however deep.
local function Collect(root, out)
    out = out or {}
    for _, child in ipairs({ root:GetChildren() }) do
        if child:IsVisible() then
            if (child:IsObjectType("Button") or child:IsObjectType("Slider")) and Usable(child) then
                out[#out + 1] = child
            end
            Collect(child, out)
        end
    end
    return out
end

local function Center(w)
    local x, y = w:GetCenter()
    local s = w:GetEffectiveScale()
    return x * s, y * s
end

-- The nearest item in direction (dx, dy): along the way counts once, off to the side counts three times.
local function Nearest(items, from, dx, dy)
    local fx, fy = Center(from)
    local best, bestScore
    for _, w in ipairs(items) do
        if w ~= from then
            local x, y = Center(w)
            local along = (x - fx) * dx + (y - fy) * dy
            local side = math.abs((x - fx) * dy) + math.abs((y - fy) * dx)
            if along > 2 then
                local score = along + side * 3
                if not bestScore or score < bestScore then best, bestScore = w, score end
            end
        end
    end
    return best
end

local function Leave(w)
    if w and w:GetScript("OnLeave") then pcall(w:GetScript("OnLeave"), w) end
    GameTooltip:Hide()
end

local function Enter(w)
    if w and w:GetScript("OnEnter") then pcall(w:GetScript("OnEnter"), w) end
end

-- opts: items() -> list (default: every button in the window), start() -> the item to begin on,
-- back(), prev(), next(), close().
function addon.GamepadNav(window, opts)
    if not window.EnableGamePadButton then return end
    opts = opts or {}
    local nav = { window = window }
    window.ssNav = nav

    local ring = CreateFrame("Frame", nil, window, BackdropTemplateMixin and "BackdropTemplate" or nil)
    ring:SetFrameStrata("TOOLTIP")
    ring:SetFrameLevel(500)
    if ring.SetBackdrop then
        ring:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        ring:SetBackdropBorderColor(1, 0.82, 0, 1)
    end
    ring:Hide()

    local legend = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    legend:SetPoint("BOTTOM", window, "BOTTOM", 0, 4)
    legend:Hide()

    -- A dropdown's list hangs off UIParent, not the window: while one is open, it is all there is.
    local function OpenMenu()
        local m = addon.UIK and addon.UIK.openMenu
        return m and m:IsShown() and m or nil
    end

    local function Items()
        local menu = OpenMenu()
        if menu then return Collect(menu) end
        return opts.items and opts.items() or Collect(window)
    end

    local function Put(w)
        if nav.current ~= w then Leave(nav.current) end
        nav.current = w
        if not w then ring:Hide() return end
        ring:ClearAllPoints()
        ring:SetPoint("TOPLEFT", w, "TOPLEFT", -4, 4)
        -- A tick box: ring the box and its words.
        local extra = (w.text and w.text.GetStringWidth and w:IsObjectType("CheckButton")) and (w.text:GetStringWidth() + 8) or 0
        ring:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", 4 + extra, -4)
        ring:Show()
        Enter(w)
    end

    function nav.Reset()
        local items = Items()
        local start = not OpenMenu() and opts.start and opts.start()
        if not Usable(start) then start = items[1] end
        Put(start)
    end

    local function Active()
        return Layout() ~= nil and not InCombatLockdown()
    end

    local function Refresh()
        local on = Active()
        legend:SetShown(on)
        if on then
            legend:SetText(Label("PAD1") .. " Select   " .. Label("PAD2") .. " Back   " .. Label("DPAD") .. " Move   "
                .. (opts.prev and (Label("PADLSHOULDER") .. "/" .. Label("PADRSHOULDER") .. " Page") or ""))
            if not Usable(nav.current) then nav.Reset() end
        else
            Put(nil)
        end
    end
    nav.Refresh = Refresh

    window:HookScript("OnShow", function()
        if not InCombatLockdown() then
            window:EnableGamePadButton(true)
            window:SetPropagateKeyboardInput(true)
        end
        Refresh()
    end)
    window:HookScript("OnHide", function() Put(nil) end)

    local function Move(dx, dy)
        local items = Items()
        if not Usable(nav.current) then nav.Reset() return end
        local w = Nearest(items, nav.current, dx, dy)
        if w then Put(w) end
    end

    window:HookScript("OnGamePadButtonDown", function(self, button)
        if DB().controllerLayout == nil and not InCombatLockdown() then
            -- First press in the window: that is the answer to "do you use a controller".
            DB().controllerLayout = Detect() or "XBOX"
            StaticPopup_Hide("SPEAKSTONE_CONTROLLER_LAYOUT")
            Refresh()
            if opts.onLayout then opts.onLayout() end
        end
        if not Active() then
            if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
            return
        end
        local handled = true
        local cur = nav.current
        local onSlider = Usable(cur) and cur:IsObjectType("Slider")
        if button == "PAD1" then
            if onSlider then
                -- nothing to press; left / right change it
            elseif Usable(cur) then
                local wasMenu = OpenMenu()
                cur:Click()
                if OpenMenu() and not wasMenu then
                    -- Opened a dropdown: into its list.
                    nav.menuOwner = cur
                    nav.Reset()
                elseif wasMenu and not OpenMenu() and Usable(nav.menuOwner) then
                    -- Picked from the list: back on the dropdown.
                    Put(nav.menuOwner)
                    nav.menuOwner = nil
                elseif not Usable(cur) then
                    -- The page changed under it.
                    nav.Reset()
                else
                    Put(cur)
                end
            else
                nav.Reset()
            end
        elseif button == "PAD2" then
            local menu = OpenMenu()
            if menu then
                menu:Hide()
                if Usable(nav.menuOwner) then Put(nav.menuOwner) else nav.Reset() end
                nav.menuOwner = nil
            elseif opts.back then opts.back() else self:Hide() end
        elseif (button == "PADDLEFT" or button == "PADDRIGHT") and onSlider then
            local lo, hi = cur:GetMinMaxValues()
            local step = cur:GetValueStep()
            if not step or step <= 0 then step = (hi - lo) / 20 end
            local v = cur:GetValue() + (button == "PADDRIGHT" and step or -step)
            cur:SetValue(math.max(lo, math.min(hi, v)))
        elseif button == "PADDUP" then Move(0, 1)
        elseif button == "PADDDOWN" then Move(0, -1)
        elseif button == "PADDLEFT" then Move(-1, 0)
        elseif button == "PADDRIGHT" then Move(1, 0)
        elseif button == "PADLSHOULDER" and opts.prev then opts.prev()
        elseif button == "PADRSHOULDER" and opts.next then opts.next()
        elseif button == "PADFORWARD" and opts.next then opts.next()
        elseif button == "PADBACK" then
            if opts.close then opts.close() else self:Hide() end
        else
            handled = false
        end
        self:SetPropagateKeyboardInput(not handled)
    end)
    window:HookScript("OnGamePadButtonUp", function(self)
        if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
    end)

    return nav
end
