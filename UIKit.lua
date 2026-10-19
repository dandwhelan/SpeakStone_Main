local addonName, addon = ...

-- SpeakStone's own window parts: a window, buttons, tick boxes, sliders and
-- dividers drawn from flat colour and one-pixel borders, in the colours of the
-- chosen theme (Theme.lua). They replace the Blizzard templates the settings
-- window used (BasicFrameTemplateWithInset, UIPanelButtonTemplate,
-- SettingsCheckBoxTemplate, OptionsSliderTemplate), which cannot be given
-- another look without fighting their own art.
--
-- Everything made here is repainted when the theme changes. Where Dialogue UI
-- is installed a window also takes its paper frame (Theme.lua: ThemeSlice).

local UIK = {}
addon.UIK = UIK

local widgets = {}      -- widget -> function that paints it from the current theme

local function UI()
    return addon.Theme().ui
end

local function Track(widget, paint)
    widgets[widget] = paint
    paint()
end

-- Enable and Disable repaint the widget (their scripts are not on every
-- widget type, so the methods themselves are wrapped).
local function RepaintOnEnable(widget, paint)
    local enable, disable = widget.Enable, widget.Disable
    function widget:Enable() enable(self); paint() end
    function widget:Disable() disable(self); paint() end
end

local function RepaintAll()
    for widget, paint in pairs(widgets) do
        local ok, err = pcall(paint)
        if not ok then
            geterrorhandler()(err)
        end
    end
end
if addon.ThemeRegister then
    addon.ThemeRegister(RepaintAll)
end

-- Text this file paints itself: the theme walker must leave it alone.
local function Own(fontString)
    fontString.ssRole = false
    return fontString
end

local function MakeBorder(frame, layer)
    local border = {}
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        border[side] = frame:CreateTexture(nil, layer or "BORDER")
    end
    border.top:SetPoint("TOPLEFT")
    border.top:SetPoint("TOPRIGHT")
    border.top:SetHeight(1)
    border.bottom:SetPoint("BOTTOMLEFT")
    border.bottom:SetPoint("BOTTOMRIGHT")
    border.bottom:SetHeight(1)
    border.left:SetPoint("TOPLEFT")
    border.left:SetPoint("BOTTOMLEFT")
    border.left:SetWidth(1)
    border.right:SetPoint("TOPRIGHT")
    border.right:SetPoint("BOTTOMRIGHT")
    border.right:SetWidth(1)
    function border:SetColor(r, g, b, a)
        for _, side in ipairs({ "top", "bottom", "left", "right" }) do
            self[side]:SetColorTexture(r, g, b, a or 1)
        end
    end
    function border:SetShown(shown)
        for _, side in ipairs({ "top", "bottom", "left", "right" }) do
            self[side]:SetShown(shown)
        end
    end
    return border
end
UIK.MakeBorder = MakeBorder

-- --------------------------------------------------------------------------
-- Button
-- --------------------------------------------------------------------------

function UIK.Button(parent, text, width, height, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height or 22)
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()
    button.border = MakeBorder(button)
    button.label = Own(button:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
    button.label:SetPoint("CENTER", 0, 0)
    button.label:SetText(text or "")

    local function Paint()
        local ui = UI()
        local style = ui.button
        local fill = style.bg
        local ink = style.text
        if not button:IsEnabled() then
            fill, ink = style.off, style.textOff
        elseif button.selected then
            fill, ink = style.selected, style.textSel
        elseif button.over then
            fill = style.hover
        end
        button.bg:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)
        local edge = button.selected and ui.accent or style.edge
        button.border:SetColor(edge[1], edge[2], edge[3], 1)
        button.label:SetTextColor(ink[1], ink[2], ink[3])
        addon.ThemeShadow(button.label)
    end
    button.Paint = Paint

    button:SetScript("OnEnter", function() button.over = true; Paint() end)
    button:SetScript("OnLeave", function() button.over = false; Paint() end)
    RepaintOnEnable(button, Paint)
    button:HookScript("OnMouseDown", function() button.label:SetPoint("CENTER", 0, -1) end)
    button:HookScript("OnMouseUp", function() button.label:SetPoint("CENTER", 0, 0) end)

    function button:SetText(value)
        self.label:SetText(value or "")
    end
    function button:GetText()
        return self.label:GetText()
    end
    -- A tab or a chosen option: lit, and not meant to be clicked again.
    function button:SetSelected(selected)
        self.selected = selected and true or false
        Paint()
    end

    if onClick then
        button:SetScript("OnClick", onClick)
    end
    Track(button, Paint)
    return button
end

-- --------------------------------------------------------------------------
-- Tick box
-- --------------------------------------------------------------------------

function UIK.Check(parent, labelText, fontObject)
    local check = CreateFrame("CheckButton", nil, parent)
    check:SetSize(20, 20)
    check.bg = check:CreateTexture(nil, "BACKGROUND")
    check.bg:SetAllPoints()
    check.border = MakeBorder(check)
    local tick = check:CreateTexture(nil, "ARTWORK")
    tick:SetPoint("TOPLEFT", 5, -5)
    tick:SetPoint("BOTTOMRIGHT", -5, 5)
    check:SetCheckedTexture(tick)
    check.tick = tick
    check.text = Own(check:CreateFontString(nil, "ARTWORK", fontObject or "GameFontNormal"))
    check.text:SetPoint("LEFT", check, "RIGHT", 6, 0)
    check.text:SetText(labelText or "")

    local function Paint()
        local ui = UI()
        local box = ui.box
        local enabled = check:IsEnabled()
        check.bg:SetColorTexture(box.bg[1], box.bg[2], box.bg[3], 1)
        local edge = enabled and (check.over and ui.accent or box.edge) or ui.off
        check.border:SetColor(edge[1], edge[2], edge[3], 1)
        local tickColour = enabled and box.tick or ui.off
        tick:SetColorTexture(tickColour[1], tickColour[2], tickColour[3], 1)
        local ink = enabled and ui.title or ui.off
        check.text:SetTextColor(ink[1], ink[2], ink[3])
        addon.ThemeShadow(check.text)
    end
    check.Paint = Paint
    check:SetScript("OnEnter", function() check.over = true; Paint() end)
    check:SetScript("OnLeave", function() check.over = false; Paint() end)
    RepaintOnEnable(check, Paint)
    Track(check, Paint)
    return check
end

-- --------------------------------------------------------------------------
-- Slider
-- --------------------------------------------------------------------------

-- A horizontal slider with its caption above and its end labels below.
function UIK.Slider(parent, width)
    local slider = CreateFrame("Slider", nil, parent)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(width, 16)
    slider.track = slider:CreateTexture(nil, "BACKGROUND")
    slider.track:SetPoint("LEFT")
    slider.track:SetPoint("RIGHT")
    slider.track:SetHeight(4)
    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(10, 18)
    slider:SetThumbTexture(thumb)
    slider.thumb = thumb
    slider.caption = Own(slider:CreateFontString(nil, "OVERLAY", "GameFontHighlight"))
    slider.caption:SetPoint("BOTTOM", slider, "TOP", 0, 4)
    slider.low = Own(slider:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"))
    slider.low:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -2)
    slider.high = Own(slider:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"))
    slider.high:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -2)
    slider.text = slider.caption

    local function Paint()
        local ui = UI()
        local enabled = slider:IsEnabled()
        local track = enabled and ui.divider or ui.off
        slider.track:SetColorTexture(track[1], track[2], track[3], 1)
        local knob = enabled and ui.accent or ui.off
        thumb:SetColorTexture(knob[1], knob[2], knob[3], 1)
        local ink = enabled and ui.text or ui.off
        slider.caption:SetTextColor(ink[1], ink[2], ink[3])
        slider.low:SetTextColor(ui.dim[1], ui.dim[2], ui.dim[3])
        slider.high:SetTextColor(ui.dim[1], ui.dim[2], ui.dim[3])
        addon.ThemeShadow(slider.caption)
        addon.ThemeShadow(slider.low)
        addon.ThemeShadow(slider.high)
    end
    RepaintOnEnable(slider, Paint)
    Track(slider, Paint)
    return slider
end

-- --------------------------------------------------------------------------
-- Divider
-- --------------------------------------------------------------------------

function UIK.Divider(parent)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    Track(line, function()
        local colour = UI().divider
        line:SetColorTexture(colour[1], colour[2], colour[3], colour[4] or 1)
    end)
    return line
end

-- --------------------------------------------------------------------------
-- Window
-- --------------------------------------------------------------------------

function UIK.Window(name, width, height, title)
    local window = CreateFrame("Frame", name, UIParent)
    window:SetSize(width, height)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetToplevel(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetClampedToScreen(true)
    window:Hide()

    window.panel = window:CreateTexture(nil, "BACKGROUND")
    window.panel:SetAllPoints()
    window.border = MakeBorder(window)

    window.TitleText = Own(window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"))
    window.TitleText:SetPoint("TOP", window, "TOP", 0, -10)
    window.TitleText:SetText(title or "")
    window.titleLine = UIK.Divider(window)
    window.titleLine:SetPoint("TOPLEFT", window, "TOPLEFT", 14, -32)
    window.titleLine:SetPoint("TOPRIGHT", window, "TOPRIGHT", -14, -32)

    window.close = UIK.Button(window, "X", 22, 22, function() window:Hide() end)
    window.close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -8, -6)

    local function Paint()
        local ui = UI()
        -- Dialogue UI's paper frame when it is there; flat colour and a thin edge otherwise.
        local art = addon.ThemeSlice and addon.ThemeSlice(window, "window")
        window.panel:SetShown(not art)
        window.border:SetShown(not art)
        window.panel:SetColorTexture(ui.panel[1], ui.panel[2], ui.panel[3], ui.panel[4] or 1)
        window.border:SetColor(ui.edge[1], ui.edge[2], ui.edge[3], 1)
        window.TitleText:SetTextColor(ui.title[1], ui.title[2], ui.title[3])
        addon.ThemeShadow(window.TitleText)
        if addon.ThemeRecolour then
            addon.ThemeRecolour(window)
        end
    end
    window.Paint = Paint
    Track(window, Paint)
    window:HookScript("OnShow", Paint)
    return window
end

-- --------------------------------------------------------------------------
-- Vertical scroll bar (a slider whose value 0 is the top)
-- --------------------------------------------------------------------------

function UIK.VScroll(parent, height)
    local bar = CreateFrame("Slider", nil, parent)
    bar:SetOrientation("VERTICAL")
    bar:SetSize(12, height)
    bar:SetValueStep(1)
    bar:SetObeyStepOnDrag(true)
    bar:SetMinMaxValues(0, 0)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetPoint("TOP")
    bar.track:SetPoint("BOTTOM")
    bar.track:SetWidth(4)
    local thumb = bar:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(12, 44)
    bar:SetThumbTexture(thumb)
    local function Paint()
        local ui = UI()
        bar.track:SetColorTexture(ui.divider[1], ui.divider[2], ui.divider[3], 0.6)
        thumb:SetColorTexture(ui.accent[1], ui.accent[2], ui.accent[3], 0.9)
    end
    Track(bar, Paint)
    return bar
end

-- --------------------------------------------------------------------------
-- Text box with a hint shown while it is empty
-- --------------------------------------------------------------------------

function UIK.EditBox(parent, width, hint)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width, 24)
    box:SetAutoFocus(false)
    box:SetFontObject("ChatFontNormal")
    box:SetTextInsets(8, 8, 0, 0)
    box.bg = box:CreateTexture(nil, "BACKGROUND")
    box.bg:SetAllPoints()
    box.border = MakeBorder(box)
    box.hint = Own(box:CreateFontString(nil, "OVERLAY", "GameFontDisable"))
    box.hint:SetPoint("LEFT", 8, 0)
    box.hint:SetText(hint or "")
    local function ShowHint()
        box.hint:SetShown(box:GetText() == "" and not box:HasFocus())
    end
    box:HookScript("OnEditFocusGained", ShowHint)
    box:HookScript("OnEditFocusLost", ShowHint)
    box:HookScript("OnTextChanged", ShowHint)
    function box:SetHint(text)
        self.hint:SetText(text or "")
    end
    local function Paint()
        local ui = UI()
        box.bg:SetColorTexture(ui.box.bg[1], ui.box.bg[2], ui.box.bg[3], 1)
        box.border:SetColor(ui.box.edge[1], ui.box.edge[2], ui.box.edge[3], 1)
        box:SetTextColor(ui.text[1], ui.text[2], ui.text[3])
        box.hint:SetTextColor(ui.dim[1], ui.dim[2], ui.dim[3])
        addon.ThemeShadow(box.hint)
        ShowHint()
    end
    Track(box, Paint)
    return box
end

-- --------------------------------------------------------------------------
-- Drop-down: a button showing the choice, and a list under it
-- --------------------------------------------------------------------------
-- getItems() returns { { key, label, font = path or nil, disabled = bool, tip = text }, ... }; each row
-- is drawn in its own font when it has one, so the list is a specimen of what it offers.
-- onSelect(key) runs when a row is chosen. SetChoice(key, label) names the current one.

function UIK.Dropdown(parent, width, getItems, onSelect)
    local drop = UIK.Button(parent, "", width, 26)
    drop.label:ClearAllPoints()
    drop.label:SetPoint("LEFT", drop, "LEFT", 10, 0)
    drop.label:SetPoint("RIGHT", drop, "RIGHT", -24, 0)
    drop.label:SetJustifyH("LEFT")
    drop.arrow = Own(drop:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
    drop.arrow:SetPoint("RIGHT", drop, "RIGHT", -8, 0)
    drop.arrow:SetText("v")

    local menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetToplevel(true)
    menu:EnableMouse(true)
    menu:Hide()
    menu.bg = menu:CreateTexture(nil, "BACKGROUND")
    menu.bg:SetAllPoints()
    menu.border = MakeBorder(menu)
    menu.rows = {}

    local ROW = 30
    local function PaintMenu()
        local ui = UI()
        menu.bg:SetColorTexture(ui.box.bg[1], ui.box.bg[2], ui.box.bg[3], 1)
        menu.border:SetColor(ui.edge[1], ui.edge[2], ui.edge[3], 1)
        drop.arrow:SetTextColor(ui.accent[1], ui.accent[2], ui.accent[3])
    end
    Track(menu, PaintMenu)

    local function Fill()
        local items = getItems() or {}
        menu:SetSize(width, #items * ROW + 6)
        for i, item in ipairs(items) do
            local row = menu.rows[i]
            if not row then
                row = CreateFrame("Button", nil, menu)
                row:SetHeight(ROW)
                row:SetPoint("TOPLEFT", menu, "TOPLEFT", 3, -3 - (i - 1) * ROW)
                row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -3, -3 - (i - 1) * ROW)
                row.hover = row:CreateTexture(nil, "HIGHLIGHT")
                row.hover:SetAllPoints()
                row.text = Own(row:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
                row.text:SetPoint("LEFT", row, "LEFT", 8, 0)
                row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                row.text:SetJustifyH("LEFT")
                menu.rows[i] = row
            end
            local ui = UI()
            row:Show()
            row.hover:SetColorTexture(ui.hover[1], ui.hover[2], ui.hover[3], ui.hover[4])
            if item.font then
                pcall(row.text.SetFont, row.text, item.font, 16, "")
            else
                row.text:SetFontObject("GameFontNormal")
            end
            row.text:SetText(item.label .. (item.disabled and "  (not available)" or ""))
            local ink = item.disabled and ui.off or ui.text
            row.text:SetTextColor(ink[1], ink[2], ink[3])
            addon.ThemeShadow(row.text)
            row:SetScript("OnClick", function()
                if item.disabled then return end
                menu:Hide()
                if onSelect then onSelect(item.key) end
            end)
            row:SetScript("OnEnter", function(self)
                if item.tip then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(item.label, 1, 0.82, 0)
                    GameTooltip:AddLine(item.tip, 1, 1, 1, true)
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        for i = #items + 1, #menu.rows do
            menu.rows[i]:Hide()
        end
    end

    drop:SetScript("OnClick", function()
        if menu:IsShown() then
            menu:Hide()
            return
        end
        Fill()
        menu:ClearAllPoints()
        menu:SetPoint("TOPLEFT", drop, "BOTTOMLEFT", 0, -2)
        menu:Show()
    end)
    -- A click anywhere else closes it.
    menu:SetScript("OnUpdate", function(self)
        if IsMouseButtonDown and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
            and not self:IsMouseOver() and not drop:IsMouseOver() then
            self:Hide()
        end
    end)
    drop:HookScript("OnHide", function() menu:Hide() end)

    function drop:SetChoice(key, label, font)
        self.key = key
        if font then
            pcall(self.label.SetFont, self.label, font, 14, "")
        else
            self.label:SetFontObject("GameFontNormal")
        end
        self.label:SetText(label or "")
        self.Paint()
    end
    return drop
end

-- --------------------------------------------------------------------------
-- Shared rows: the theme buttons, the reading font with its preview
-- --------------------------------------------------------------------------

-- Buttons for the three themes; the chosen one lit. Returns a frame that is `width` wide.
function UIK.ThemeButtons(parent, width)
    local row = CreateFrame("Frame", nil, parent)
    local each = math.floor((width - 8) / 3)
    row:SetSize(width, 26)
    local buttons = {}
    local function Paint()
        local chosen = addon.Theme().key
        for _, button in ipairs(buttons) do
            button:SetSelected(button.key == chosen)
        end
    end
    for i, key in ipairs(addon.ThemeOrder or {}) do
        local button = UIK.Button(row, addon.Themes[key].label, each, 26, function() addon.SetTheme(key); Paint() end)
        button:SetPoint("LEFT", row, "LEFT", (i - 1) * (each + 4), 0)
        button.key = key
        buttons[#buttons + 1] = button
    end
    row:SetScript("OnShow", Paint)
    addon.ThemeRegister(Paint)
    Paint()
    return row
end

-- A drop-down of the reading fonts, each row drawn in its own letters. Changing it tells the addon.
function UIK.FontDropdown(parent, width)
    local function Items()
        local items = {}
        for _, entry in ipairs(addon.Fonts or {}) do
            local usable = addon.FontUsable and addon.FontUsable(entry)
            items[#items + 1] = {
                key = entry.key, label = entry.label,
                font = usable and addon.FontFile(entry),
                disabled = not usable,
                tip = usable and (entry.credit or "The game's own font.") or "This copy of the game could not load this font file.",
            }
        end
        return items
    end
    local drop
    local function Show()
        local entry = addon.FontEntry(SpeakStone_MainDB.readingFont or "default")
        if not (entry and addon.FontUsable(entry)) then entry = addon.FontEntry("default") end
        drop:SetChoice(entry.key, entry.label, addon.FontFile(entry))
    end
    drop = UIK.Dropdown(parent, width, Items, function(key)
        SpeakStone_MainDB.readingFont = key
        Show()
        if addon.SpeechSettingChanged then addon.SpeechSettingChanged("readingFont") end
    end)
    drop:SetScript("OnShow", Show)
    Show()
    return drop
end

-- What the reading font, its size and the subtitle colours look like together, as the bar draws them.
function UIK.FontPreview(parent, width, height)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(width, height or 64)
    box.bg = box:CreateTexture(nil, "BACKGROUND")
    box.bg:SetAllPoints()
    box.border = MakeBorder(box)
    box.text = Own(box:CreateFontString(nil, "OVERLAY", "GameFontHighlight"))
    box.text:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -8)
    box.text:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 8)
    box.text:SetJustifyH("LEFT")
    box.text:SetJustifyV("MIDDLE")
    box.text:SetWordWrap(true)
    local function Refresh()
        local colours = addon.SubtitleColours and addon.SubtitleColours() or { text = { 1, 1, 1 } }
        local theme = addon.Theme()
        local back = colours.back or theme.ui.inset
        box.bg:SetColorTexture(back[1], back[2], back[3], colours.back and 0.94 or 1)
        box.border:SetColor(theme.ui.edge[1], theme.ui.edge[2], theme.ui.edge[3], 0.8)
        local size = math.min(tonumber(SpeakStone_MainDB.subtitleFontSize) or 18, 24)
        if not (addon.ApplyReadingFont and addon.ApplyReadingFont(box.text, size, "")) then
            box.text:SetFont((GameFontHighlight:GetFont()), size, "")
        end
        local code = addon.HighlightCode and addon.HighlightCode(colours.light) or "|cfff0c94a"
        box.text:SetText("The quick brown fox " .. code .. "jumps|r over the lazy dog.\nBdpq 69 Il1 O0 -- 1234567890")
        local ink = colours.text or theme.text
        box.text:SetTextColor(ink[1], ink[2], ink[3])
        box.text:SetShadowColor(0, 0, 0, colours.light and 0 or 1)
    end
    box:SetScript("OnShow", Refresh)
    addon.ThemeRegister(Refresh)
    box.Refresh = Refresh
    -- Any settings change that affects it (SpeechSettingChanged) refreshes every preview that exists.
    UIK.previews = UIK.previews or {}
    UIK.previews[#UIK.previews + 1] = Refresh
    addon.FontPreviewRefresh = function()
        for _, refresh in ipairs(UIK.previews) do pcall(refresh) end
    end
    Refresh()
    return box
end

-- --------------------------------------------------------------------------
-- A box holding an address to copy: themed, and read-only in effect
-- --------------------------------------------------------------------------

function UIK.CopyBox(parent, url, width)
    local box = UIK.EditBox(parent, width, "")
    -- The plain game font, no outline or shadow: the chat font's outline read as bold.
    box:SetFont((GameFontHighlight:GetFont()), 13, "")
    if box.SetShadowColor then box:SetShadowColor(0, 0, 0, 0) end
    box.url = url
    box:SetText(url)
    box:SetCursorPosition(0)
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(self.url)
            self:HighlightText()
        end
    end)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    function box:SetURL(value)
        self.url = value
        self:SetText(value)
    end
    return box
end

-- --------------------------------------------------------------------------
-- A small animated sample of how the words can be shown
-- --------------------------------------------------------------------------
-- style "bar": the subtitle bar (typed words, the word being read lit, in the player's colours);
-- "window": a quest window's text on paper; "head": a talking head's text, the word lit as it plays.
-- It follows the type-out and highlight settings and the reading font, and loops while it is on screen.

local SAMPLE = "The spirits here are restless, and dey ain't too happy about dat."

function UIK.WordPreview(parent, width, height, style)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(width, height)
    box.bg = box:CreateTexture(nil, "BACKGROUND")
    box.bg:SetAllPoints()
    box.border = MakeBorder(box)
    box.name = Own(box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
    box.name:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -6)
    box.text = Own(box:CreateFontString(nil, "OVERLAY", "GameFontHighlight"))
    box.text:SetPoint("TOPLEFT", box.name, "BOTTOMLEFT", 0, -3)
    box.text:SetPoint("RIGHT", box, "RIGHT", -10, 0)
    box.text:SetJustifyH("LEFT")
    box.text:SetJustifyV("TOP")
    box.text:SetWordWrap(true)
    local words, times, started
    local LENGTH = 7

    local function Paint()
        local theme = addon.Theme()
        local ink, edge, back, nameInk
        if style == "bar" then
            local c = addon.SubtitleColours and addon.SubtitleColours() or { text = theme.text, name = theme.title }
            back = c.back or { 0.05, 0.05, 0.07 }
            ink, nameInk, edge = c.text, c.name or theme.title, theme.line
            box.light = c.light
        elseif style == "window" then
            back, ink, nameInk, edge = { 0.83, 0.73, 0.55 }, { 0.2, 0.12, 0.06 }, { 0.27, 0.13, 0.05 }, { 0.35, 0.2, 0.1 }
            box.light = true
        elseif style == "box" then
            back, ink, nameInk, edge = theme.back, theme.text, theme.title, theme.line
            box.light = theme.light
        else
            back, ink, nameInk, edge = { 0.04, 0.06, 0.09 }, { 1, 1, 1 }, { 0.94, 0.82, 0.48 }, { 0.5, 0.45, 0.3 }
            box.light = false
        end
        box.bg:SetColorTexture(back[1], back[2], back[3], back[4] or (style == "bar" and 0.95 or 1))
        box.border:SetColor(edge[1], edge[2], edge[3], 0.9)
        box.name:SetTextColor(nameInk[1], nameInk[2], nameInk[3])
        box.text:SetTextColor(ink[1], ink[2], ink[3])
        local shadow = box.light and 0 or 1
        box.text:SetShadowColor(0, 0, 0, shadow)
        box.name:SetShadowColor(0, 0, 0, shadow)
        if style == "bar" and addon.ApplyReadingFont and addon.ApplyReadingFont(box.text, 14, "") then
            -- the player's reading font
        else
            box.text:SetFontObject("GameFontHighlight")
        end
        box.name:SetText(style == "window" and "Quest window" or (style == "head" and "Talking head" or (style == "box" and "Kinduru   You Remind Me of the Bird" or "Kinduru")))
    end

    box:SetScript("OnShow", function()
        started = GetTime()
        if addon.SubtitleWords and not words then
            words = addon.SubtitleWords(SAMPLE)
            times = addon.SubtitleWordTimes(words, LENGTH)
        end
        Paint()
    end)
    box:SetScript("OnUpdate", function()
        if not words or not started then return end
        local elapsed = (GetTime() - started) % (LENGTH + 2.5)
        local index = elapsed >= LENGTH and #words or addon.SubtitleWordAt(times, elapsed + 0.12)
        local db = SpeakStone_MainDB or {}
        local typeOut = style ~= "head" and style ~= "box" and db.subtitleTypeOut ~= false
        local highlight = db.subtitleHighlight ~= false
        if elapsed >= LENGTH then index = #words end
        local code = addon.HighlightCode and addon.HighlightCode(box.light) or "|cfff0c94a"
        box.text:SetText(addon.SubtitleRender(words, index, typeOut, highlight and elapsed < LENGTH, code))
    end)
    addon.ThemeRegister(function() if box:IsShown() then Paint() end end)
    UIK.previews = UIK.previews or {}
    UIK.previews[#UIK.previews + 1] = function() if box:IsShown() then Paint() end end
    addon.FontPreviewRefresh = function()
        for _, refresh in ipairs(UIK.previews) do pcall(refresh) end
    end
    box.Paint = Paint
    return box
end

-- --------------------------------------------------------------------------
-- A row of colour swatches for one setting, the last one opening the game's colour picker
-- --------------------------------------------------------------------------
-- list: { { key, label, rgb }, ... }; option: the saved setting (the picked colour is kept in option .. "Custom");
-- tip = { text for the default swatch, text for the others }.

function UIK.SwatchRow(parent, title, option, list, default, tip, labelWidth)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(600, 24)
    local label = Own(row:CreateFontString(nil, "ARTWORK", "GameFontHighlight"))
    label:SetPoint("LEFT", row, "LEFT", 0, 0)
    label:SetText(title)
    row.label = label
    local function Ink()
        local ui = UI()
        label:SetTextColor(ui.text[1], ui.text[2], ui.text[3])
        addon.ThemeShadow(label)
    end
    Track(label, Ink)
    local swatches = {}
    local function Paint()
        local chosen = SpeakStone_MainDB[option] or default
        for _, swatch in ipairs(swatches) do
            swatch.ring:SetShown(swatch.key == chosen)
        end
    end
    local function Notify()
        if addon.SpeechSettingChanged then addon.SpeechSettingChanged(option) end
    end
    local entries = {}
    for _, colour in ipairs(list or {}) do entries[#entries + 1] = colour end
    entries[#entries + 1] = { key = "custom", label = "Pick your own colour", rgb = { 0.5, 0.5, 0.5 }, custom = true }
    for i, colour in ipairs(entries) do
        local swatch = CreateFrame("Button", nil, row)
        swatch:SetSize(20, 20)
        swatch:SetPoint("LEFT", row, "LEFT", (labelWidth or 150) + (i - 1) * 28, 0)
        swatch.key = colour.key
        swatch.ring = swatch:CreateTexture(nil, "BACKGROUND")
        swatch.ring:SetPoint("TOPLEFT", -2, 2)
        swatch.ring:SetPoint("BOTTOMRIGHT", 2, -2)
        swatch.ring:SetColorTexture(1, 1, 1, 1)
        swatch.fill = swatch:CreateTexture(nil, "ARTWORK")
        swatch.fill:SetAllPoints()
        swatch.fill:SetColorTexture(colour.rgb[1], colour.rgb[2], colour.rgb[3], 1)
        if colour.key == default or colour.custom then
            local mark = Own(swatch:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
            mark:SetPoint("CENTER")
            mark:SetText(colour.custom and "+" or "A")
            mark:SetTextColor(0.1, 0.1, 0.1)
            mark:SetShadowColor(0, 0, 0, 0)
            swatch.mark = mark
        end
        if colour.custom then
            local function ShowCustom()
                local c = addon.CustomColour and addon.CustomColour(option)
                if c then
                    swatch.fill:SetColorTexture(c[1], c[2], c[3], 1)
                    swatch.mark:SetText("")
                end
            end
            ShowCustom()
            swatch:SetScript("OnClick", function()
                local saved = addon.CustomColour and addon.CustomColour(option) or { 0.9, 0.9, 0.9 }
                local before = { choice = SpeakStone_MainDB[option], custom = SpeakStone_MainDB[option .. "Custom"] }
                if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
                    pcall(ColorPickerFrame.SetFrameStrata, ColorPickerFrame, "FULLSCREEN_DIALOG")
                    ColorPickerFrame:SetupColorPickerAndShow({
                        r = saved[1], g = saved[2], b = saved[3], hasOpacity = false,
                        swatchFunc = function()
                            local r, g, b = ColorPickerFrame:GetColorRGB()
                            SpeakStone_MainDB[option .. "Custom"] = { r, g, b }
                            SpeakStone_MainDB[option] = "custom"
                            ShowCustom()
                            Paint()
                            Notify()
                        end,
                        cancelFunc = function()
                            SpeakStone_MainDB[option] = before.choice
                            SpeakStone_MainDB[option .. "Custom"] = before.custom
                            ShowCustom()
                            Paint()
                            Notify()
                        end,
                    })
                else
                    print("|cff33ff99SpeakStone:|r the colour picker is not available on this client.")
                end
            end)
        else
            swatch:SetScript("OnClick", function()
                SpeakStone_MainDB[option] = colour.key
                Paint()
                Notify()
            end)
        end
        local body = colour.custom and "Choose any colour with the colour picker. Click again to change it."
            or (colour.key == default and tip[1] or tip[2])
        swatch:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(colour.label, 1, 0.82, 0)
            if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        swatch:SetScript("OnLeave", function() GameTooltip:Hide() end)
        swatches[#swatches + 1] = swatch
    end
    row:SetScript("OnShow", Paint)
    Paint()
    return row
end
