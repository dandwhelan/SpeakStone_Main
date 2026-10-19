local addonName, addon = ...

-- The reading font: what the subtitle bar, the speech frame, the Guide's text and
-- the previews are drawn in, picked in the settings (readingFont). Fonts that ship with
-- the game itself (`path`), so there is nothing to bundle. An entry can instead name a
-- file in this addon's Fonts folder (`file`) -- see docs/todo.md: bundled dyslexia-friendly
-- fonts did not load in the game (2026-10-19) and were taken out until that is understood.
--
-- The settings page lists whatever is here.
--
-- Whether the client can load a file is asked of the client itself: SetFont
-- returns false for a file it cannot use, and that font is then greyed out in
-- the settings and never chosen, so a bad file can never leave text with no font.

local FOLDER = "Interface\\AddOns\\" .. addonName .. "\\Fonts\\"

addon.Fonts = {
    { key = "default", label = "Game default" },
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
    if UIParent and UIParent.CreateFontString then
        probe = probe or UIParent:CreateFontString(nil, "BACKGROUND")
        -- Start from a font that certainly loads, then ask what the font string ended up with: SetFont's own
        -- return value is not something to rely on across clients (it is nil on some), the font in use is.
        pcall(probe.SetFont, probe, "Fonts\\FRIZQT__.TTF", 14, "")
        local path = addon.FontFile(entry)
        local called, result = pcall(probe.SetFont, probe, path, 14, "")
        local function Norm(p) return (tostring(p or ""):lower():gsub("/", "\\")) end
        local now = called and probe.GetFont and probe:GetFont()
        ok = called and result ~= false and now ~= nil and Norm(now) == Norm(path)
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
