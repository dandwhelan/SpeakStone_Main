local addonName, addon = ...

-- The reading font: what the subtitle bar, the speech frame, the Guide's text and
-- the previews are drawn in, picked in the settings (readingFont). Entries can name
-- either a font that ships with the game (`path`) or a bundled SIL OFL 1.1 file in
-- this addon's Fonts folder (`file`).
--
-- The settings page lists whatever is here.
--
-- Whether the client can load a file is asked of the client itself via CreateFont:
-- a font the client cannot load is greyed out in the settings and never chosen, so
-- a bad file can never leave text with no font.

local FOLDER = "Interface/AddOns/" .. addonName .. "/Fonts/"

addon.Fonts = {
    { key = "default", label = "Game default" },
    { key = "atkinson", label = "Atkinson Hyperlegible", file = "AtkinsonHyperlegible-Regular.ttf",
      credit = "Designed by the Braille Institute for low vision and dyslexia: distinct letterforms (SIL OFL 1.1)." },
    { key = "lexend", label = "Lexend", file = "Lexend-Regular.ttf",
      credit = "Designed to reduce visual crowding and improve reading fluency (SIL OFL 1.1)." },
    { key = "andika", label = "Andika", file = "Andika-Regular.ttf",
      credit = "Designed by SIL for literacy and dyslexic readers: open counters and simple letter shapes (SIL OFL 1.1)." },
    { key = "opendyslexic", label = "OpenDyslexic", file = "OpenDyslexic-Regular.otf",
      credit = "Weighted bottoms designed to help prevent letters flipping or swapping (SIL OFL 1.1)." },
    { key = "arial", label = "Arial Narrow", path = "Fonts\\ARIALN.TTF",
      credit = "The game's own plain sans-serif font: even strokes and open letter shapes." },
    { key = "morpheus", label = "Morpheus", path = "Fonts\\MORPHEUS.TTF",
      credit = "The game's own storybook font, the one its book and quest text uses." },
}

local usable = {}
local probe

-- Whether this client loads the font's file.
function addon.FontUsable(entry)
    if not (entry.file or entry.path) then
        return true
    end
    if usable[entry.key] ~= nil then
        return usable[entry.key]
    end
    local ok = false
    if CreateFont or (UIParent and UIParent.CreateFontString) then
        if not probe then
            probe = CreateFont and (_G.SpeakStoneFontProbe or CreateFont("SpeakStoneFontProbe"))
                or UIParent:CreateFontString(nil, "BACKGROUND")
        end
        -- Start from a font that certainly loads, then ask what the font object ended up with: SetFont on a
        -- CreateFont object returns nil on success (not true), whereas a bare CreateFontString rejects custom
        -- addon .ttf paths in WoW Forever / 12.x. Checking GetFont() on a CreateFont object works in both.
        pcall(probe.SetFont, probe, "Fonts\\FRIZQT__.TTF", 14, "")
        local before = probe.GetFont and probe:GetFont()
        local path = addon.FontFile(entry)
        local called, result = pcall(probe.SetFont, probe, path, 14, "")
        local function Norm(p) return (tostring(p or ""):lower():gsub("/", "\\")) end
        local now = called and probe.GetFont and probe:GetFont()
        ok = called and result ~= false and now ~= nil
            and (Norm(now) == Norm(path) or (before ~= nil and Norm(now) ~= Norm(before) and Norm(now) ~= ""))
    end
    usable[entry.key] = ok
    return ok
end

function addon.FontFile(entry)
    return entry.path or (entry.file and (FOLDER .. entry.file)) or nil
end

function addon.FontEntry(key)
    for _, entry in ipairs(addon.Fonts) do
        if entry.key == key then
            return entry
        end
    end
    return nil
end

-- The file path for the chosen reading font, or nil for the game's own (also
-- when the chosen file cannot be loaded).
function addon.ReadingFontPath()
    local key = SpeakStone_MainDB and SpeakStone_MainDB.readingFont or "default"
    local entry = addon.FontEntry(key)
    if entry and (entry.file or entry.path) and addon.FontUsable(entry) then
        return addon.FontFile(entry)
    end
    return nil
end

-- Set a font string or font object to the reading font at `size`, or to
-- `fallback` (a font object's own font) when the game's is chosen.
-- Returns whether the chosen (non-default) font was used.
function addon.ApplyReadingFont(target, size, flags, fallbackFont)
    local custom = addon.ReadingFontPath()
    local path = custom or fallbackFont or (GameFontHighlight and (GameFontHighlight:GetFont()))
    if path then
        target:SetFont(path, size, flags or "")
    end
    return custom ~= nil
end

-- Bundled italic font for narrator stage directions (SpeechFrame.lua). Probed via FontUsable so if the client
-- cannot load it (e.g. before a full restart after install), callers fall back cleanly to the reading/game font.
local NARRATOR_ITALIC = { key = "_narrator_italic", file = "AtkinsonHyperlegible-Italic.ttf" }

function addon.NarratorItalicFontPath()
    if addon.FontUsable(NARRATOR_ITALIC) then
        return addon.FontFile(NARRATOR_ITALIC)
    end
    return nil
end
