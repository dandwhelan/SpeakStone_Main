local addonName, addon = ...

-- The look of SpeakStone's own windows (the subtitle bar, the speech frame):
-- three themes the player chooses between (uiTheme), drawn from the designs in
-- docs/ui_theme_designs_20261019.html.
--
--   parchment  tan paper and brown ink, like Dialogue UI's Brown theme
--   stone      dark charcoal and gold, like the Compendium window (the default)
--   midnight   dark blue-violet glass with a teal accent
--
-- All three draw Dialogue UI's torn-paper frame in their own colour (the Brown art, tinted) when that addon is installed
-- (read from its folder at run time: its art is not copied into SpeakStone, and
-- is not ours to ship), and a flat tan when it is not.
--
-- A window registers a function that paints it (addon.ThemeRegister); choosing a
-- theme runs them all, so a change shows at once.

local DUI_ART = "Interface\\AddOns\\DialogueUI\\Art\\"

addon.Themes = {
    stone = {
        key = "stone", label = "Stone",
        back = { 0.05, 0.05, 0.06, 0.88 }, backEnd = { 0.05, 0.05, 0.06, 0.5 },
        line = { 0.94, 0.76, 0.35, 0.4 },
        title = { 0.94, 0.82, 0.48 }, sub = { 0.7, 0.72, 0.75 }, text = { 1, 1, 1 },
        accent = { 0.94, 0.76, 0.35 }, track = { 1, 1, 1, 0.12 },
        subCode = "|cffb3b8bf", light = false,
        art = "Theme_Brown", tint = { 0.3, 0.32, 0.36 },   -- the torn-paper frame in charcoal
        card = { 0.09, 0.08, 0.07, 0.85 },
        ui = {
            panel = { 0.115, 0.105, 0.095, 0.98 }, edge = { 0.62, 0.5, 0.25, 1 }, divider = { 0.45, 0.38, 0.24, 0.9 },
            title = { 1, 0.82, 0 }, text = { 0.96, 0.9, 0.7 }, dim = { 0.6, 0.57, 0.5 }, off = { 0.42, 0.4, 0.37 },
            accent = { 0.94, 0.76, 0.35 },
            inset = { 0.075, 0.07, 0.065, 0.9 }, select = { 0.34, 0.27, 0.1, 0.85 }, hover = { 1, 1, 1, 0.07 },
            button = { bg = { 0.24, 0.1, 0.08, 1 }, hover = { 0.36, 0.14, 0.1, 1 }, selected = { 0.2, 0.2, 0.2, 1 },
                       off = { 0.15, 0.14, 0.13, 1 }, edge = { 0.55, 0.42, 0.2, 1 },
                       text = { 1, 0.82, 0 }, textSel = { 1, 1, 1 }, textOff = { 0.45, 0.43, 0.4 } },
            box = { bg = { 0.05, 0.045, 0.04, 1 }, edge = { 0.55, 0.45, 0.25, 1 }, tick = { 1, 0.82, 0 } },
        },
        titleCode = "|cffffd100", voiceCode = "|cffb0b0ff", dimCode = "|cff9d9d9d", border = { 1, 1, 1 },
    },
    parchment = {
        key = "parchment", label = "Parchment",
        back = { 0.83, 0.73, 0.55, 0.96 }, backEnd = { 0.8, 0.69, 0.5, 0.9 },
        line = { 0.35, 0.2, 0.1, 0.6 },
        title = { 0.27, 0.13, 0.05 }, sub = { 0.4, 0.27, 0.17 }, text = { 0.2, 0.12, 0.06 },
        accent = { 0.45, 0.2, 0.1 }, track = { 0.35, 0.2, 0.1, 0.2 },
        subCode = "|cff684429", light = true, paper = true,
        art = "Theme_Brown", tint = { 1, 1, 1 }, card = { 0.45, 0.3, 0.15, 0.16 },
        ui = {
            panel = { 0.8, 0.69, 0.5, 1 }, edge = { 0.42, 0.27, 0.13, 1 }, divider = { 0.42, 0.27, 0.13, 0.7 },
            title = { 0.27, 0.13, 0.05 }, text = { 0.2, 0.12, 0.06 }, dim = { 0.4, 0.28, 0.17 }, off = { 0.55, 0.45, 0.33 },
            accent = { 0.5, 0.22, 0.1 },
            inset = { 0.88, 0.8, 0.62, 0.65 }, select = { 0.55, 0.36, 0.17, 0.4 }, hover = { 0.3, 0.17, 0.05, 0.12 },
            button = { bg = { 0.42, 0.26, 0.14, 1 }, hover = { 0.52, 0.32, 0.17, 1 }, selected = { 0.67, 0.5, 0.3, 1 },
                       off = { 0.68, 0.58, 0.42, 1 }, edge = { 0.25, 0.14, 0.07, 1 },
                       text = { 0.97, 0.9, 0.72 }, textSel = { 0.22, 0.11, 0.04 }, textOff = { 0.5, 0.42, 0.3 } },
            box = { bg = { 0.9, 0.82, 0.64, 1 }, edge = { 0.35, 0.2, 0.1, 1 }, tick = { 0.45, 0.17, 0.08 } },
        },
        titleCode = "|cff4a2410", voiceCode = "|cff2f2f7a", dimCode = "|cff7a6650", border = { 0.62, 0.42, 0.24 },
    },
    midnight = {
        key = "midnight", label = "Midnight",
        back = { 0.06, 0.07, 0.16, 0.88 }, backEnd = { 0.05, 0.06, 0.13, 0.55 },
        line = { 0.25, 0.8, 0.75, 0.55 },
        title = { 0.55, 0.92, 0.88 }, sub = { 0.65, 0.7, 0.85 }, text = { 0.93, 0.95, 1 },
        accent = { 0.25, 0.8, 0.75 }, track = { 1, 1, 1, 0.12 },
        subCode = "|cffa6b3d9", light = false,
        art = "Theme_Brown", tint = { 0.26, 0.3, 0.62 }, card = { 0.1, 0.13, 0.32, 0.45 },
        ui = {
            panel = { 0.07, 0.08, 0.18, 0.98 }, edge = { 0.25, 0.8, 0.75, 1 }, divider = { 0.25, 0.8, 0.75, 0.5 },
            title = { 0.55, 0.92, 0.88 }, text = { 0.9, 0.94, 1 }, dim = { 0.6, 0.66, 0.85 }, off = { 0.4, 0.44, 0.6 },
            accent = { 0.25, 0.8, 0.75 },
            inset = { 0.05, 0.06, 0.14, 0.9 }, select = { 0.1, 0.42, 0.44, 0.6 }, hover = { 1, 1, 1, 0.07 },
            button = { bg = { 0.12, 0.17, 0.36, 1 }, hover = { 0.17, 0.25, 0.5, 1 }, selected = { 0.1, 0.5, 0.5, 1 },
                       off = { 0.09, 0.1, 0.2, 1 }, edge = { 0.25, 0.8, 0.75, 1 },
                       text = { 0.75, 0.95, 0.95 }, textSel = { 1, 1, 1 }, textOff = { 0.4, 0.44, 0.6 } },
            box = { bg = { 0.04, 0.05, 0.12, 1 }, edge = { 0.25, 0.8, 0.75, 1 }, tick = { 0.35, 0.95, 0.9 } },
        },
        titleCode = "|cff8ee8e0", voiceCode = "|cffc6b8ff", dimCode = "|cff8a93b3", border = { 0.45, 0.85, 0.85 },
    },
}
addon.ThemeOrder = { "parchment", "stone", "midnight" }

function addon.Theme()
    local key = SpeakStone_MainDB and SpeakStone_MainDB.uiTheme or "stone"
    return addon.Themes[key] or addon.Themes.stone
end

local function PaperAvailable()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("DialogueUI")
    return loaded or (IsAddOnLoaded and IsAddOnLoaded("DialogueUI"))
end

-- Paint a background texture in the theme, flat (or a left-to-right fade when
-- asked, as the speech frame's band has). Dialogue UI's art is drawn by
-- ThemeSlice instead.
function addon.ThemeBackground(texture, gradient)
    local theme = addon.Theme()
    texture:SetTexture(nil)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetVertexColor(1, 1, 1, 1)
    texture:SetColorTexture(1, 1, 1, 1)
    if gradient and texture.SetGradient and CreateColor then
        texture:SetGradient("HORIZONTAL", CreateColor(unpack(theme.back)), CreateColor(unpack(theme.backEnd)))
    else
        texture:SetColorTexture(unpack(theme.back))
    end
end

-- Dialogue UI draws its frames as a nine-slice picture (512 px square, 80 px
-- margins, a soft shadow outside): a torn-paper frame in the Brown theme, a
-- dark slate one in the Dark theme. This lays the same picture behind a frame,
-- read from Dialogue UI's folder at run time (its art is not ours to ship), a
-- little larger than the frame so the torn edge and shadow sit outside it.
-- Returns whether it did: false when Dialogue UI is not installed or the
-- theme has no art, and the caller paints a flat background instead.
local SLICE_KINDS = {
    window = { scale = 0.45, outset = 22 },
    bar = { scale = 0.3, outset = 13 },
}

function addon.ThemeSlice(frame, kind)
    local theme = addon.Theme()
    local slice = frame.ssSlice
    if not (theme.art and PaperAvailable()) then
        if slice then
            slice:Hide()
        end
        return false
    end
    local spec = SLICE_KINDS[kind or "window"]
    if not slice then
        slice = CreateFrame("Frame", nil, frame)
        frame.ssSlice = slice
        slice.tex = slice:CreateTexture(nil, "BACKGROUND")
        slice.tex:SetAllPoints()
        pcall(slice.tex.SetTextureSliceMargins, slice.tex, 80, 80, 80, 80)
        pcall(slice.tex.SetTextureSliceMode, slice.tex, 1)
    end
    slice.tex:SetTexture(DUI_ART .. theme.art .. "\\GenericFrame-Tiled-Large.png")
    slice.tex:SetVertexColor(theme.tint[1], theme.tint[2], theme.tint[3], 1)
    slice:SetScale(spec.scale)
    slice:ClearAllPoints()
    local o = spec.outset / spec.scale
    slice:SetPoint("TOPLEFT", frame, "TOPLEFT", -o, o)
    slice:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", o, -o)
    -- Under the frame's own text and pictures: one level below it.
    local level = frame:GetFrameLevel()
    if level < 2 then
        frame:SetFrameLevel(2)
        level = 2
    end
    slice:SetFrameLevel(level - 1)
    slice:Show()
    return true
end

local painters = {}

-- fn() paints one window from addon.Theme(); it also runs now if the window exists.
function addon.ThemeRegister(fn)
    painters[#painters + 1] = fn
end

function addon.ThemeChanged()
    for _, fn in ipairs(painters) do
        local ok, err = pcall(fn)
        if not ok then
            geterrorhandler()(err)
        end
    end
end

function addon.SetTheme(key)
    if addon.Themes[key] then
        SpeakStone_MainDB.uiTheme = key
        addon.ThemeChanged()
        if addon.SubtitleSettingChanged then
            addon.SubtitleSettingChanged("highlightColour")
        end
    end
end

-- The word being read, in "auto": deep red on the parchment theme.
function addon.ThemeIsLight()
    return addon.Theme().light == true
end

-- --------------------------------------------------------------------------
-- Windows built on Blizzard's BasicFrameTemplateWithInset (the settings
-- window, the SpeakStone Guide)
-- --------------------------------------------------------------------------
-- Stone is the look they already have, so it leaves them untouched. The other
-- two lay their background over the inset, tint the border and recolour the
-- text: a FontString's role (title, text, quiet) is worked out once from the
-- colour it was made with and remembered, so a later theme change can repaint
-- it. Buttons built from UIPanelButtonTemplate keep their own look and their
-- own text colour.

local function Role(fs)
    if fs.ssRole ~= nil then
        return fs.ssRole
    end
    local r, g, b = fs:GetTextColor()
    local role = false
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
        if r > 0.9 and g > 0.7 and g < 0.92 and b < 0.3 then
            role = "title"            -- the game's gold
        elseif r > 0.85 and g > 0.85 and b > 0.85 then
            role = "text"
        elseif math.abs(r - g) < 0.08 and math.abs(g - b) < 0.08 and r < 0.8 and r > 0.4 then
            role = "sub"
        end
    end
    fs.ssRole = role
    return role
end

local function IsTemplateButton(child)
    return child.GetObjectType and child:GetObjectType() == "Button" and (child.Left or child.Middle)
end

-- Dark ink on paper reads badly with the game's drop shadow behind it: off on
-- the light theme, back to the game's own on the dark ones.
function addon.ThemeShadow(fontString)
    if fontString.SetShadowColor then
        local light = addon.Theme().light
        fontString:SetShadowColor(0, 0, 0, light and 0 or 1)
        fontString:SetShadowOffset(light and 0 or 1, light and 0 or -1)
    end
end

local function Recolour(frame, theme, depth)
    if depth > 8 then
        return
    end
    if frame.ssCardBg then
        frame.ssCardBg:SetColorTexture(unpack(theme.card))
    end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "FontString" then
            addon.ThemeShadow(region)
            local role = Role(region)
            if role then
                region:SetTextColor(unpack(theme[role]))
            end
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        if not IsTemplateButton(child) then
            Recolour(child, theme, depth + 1)
        end
    end
end

-- For windows drawn by UIKit.lua: recolour the text it did not paint itself.
function addon.ThemeRecolour(window)
    Recolour(window, addon.Theme(), 0)
end

local CHROME = { "NineSlice", "Bg", "TitleBg", "TopTileStreaks", "Inset" }

local function SetChrome(window, shown)
    for _, key in ipairs(CHROME) do
        local part = window[key]
        if part and part.SetShown then
            part:SetShown(shown)
        end
    end
end

function addon.ThemeWindow(window)
    if not window then
        return
    end
    local theme = addon.Theme()
    local plain = theme.key == "stone"
    local art = addon.ThemeSlice(window, "window")
    -- Blizzard's own frame art steps aside for Dialogue UI's.
    SetChrome(window, not art)
    if not window.ssBack then
        window.ssBack = window:CreateTexture(nil, "BACKGROUND", nil, 3)
        window.ssBack:SetAllPoints(window.Inset or window)
    end
    if plain or art then
        window.ssBack:Hide()
    else
        addon.ThemeBackground(window.ssBack, false)
        window.ssBack:Show()
    end
    local tint = (plain or art) and { 1, 1, 1 } or theme.border
    if window.NineSlice and not art then
        for _, region in ipairs({ window.NineSlice:GetRegions() }) do
            if region.SetVertexColor then
                region:SetVertexColor(tint[1], tint[2], tint[3])
            end
        end
    end
    if window.TitleBg and window.TitleBg.SetVertexColor then
        window.TitleBg:SetVertexColor(tint[1], tint[2], tint[3])
    end
    if window.TitleText then
        window.TitleText:SetTextColor(unpack(plain and { 1, 0.82, 0 } or theme.title))
    end
    Recolour(window, theme, 0)
end
